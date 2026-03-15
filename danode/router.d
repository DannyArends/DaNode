module danode.router;

import danode.imports;
import danode.client : Client;
import danode.interfaces : ClientInterface, DriverInterface, StringDriver;
import danode.statuscode : StatusCode;
import danode.request : Request;
import danode.response : Response, setPayload, create, badRequest, domainNotFound, forbidden, redirect, serveCGI, serveDirectory, notFound;
import danode.payload : Message;
import danode.files : serveStaticFile;
import danode.webconfig : WebConfig;
import danode.functions : from, has, isCGI, isFILE, isDIR, isAllowed, safePath;
import danode.filesystem : FileSystem;
import danode.post : parsePost;
import danode.log : log, tag, error, Level;

version(SSL) {
  import danode.ssl : hasCertificate;
}

class Router {
  private:
    FileSystem filesystem;
    WebConfig config;
    Address address;

  public:
    this(string wwwRoot = "./www/", Address address = Address.init){
      this.address = address;
      this.filesystem = new FileSystem(wwwRoot);
    }

    // Parse the header of a request, or receive additional post data when the user is uploading
    final bool parse(in DriverInterface driver, ref Request request, ref Response response, long maxtime = 4500) {
      if (!driver.hasHeader()) return(false);
      if (!response.created) {
        request.initialize(driver, maxtime);
        response = request.create(this.address);
      } else { request.update(driver.body); }
      return(true);
    }

    // Route a request based on the request header
    final void route(DriverInterface driver, ref Request request, ref Response response, long maxtime = 4500) {
      if (!response.routed && parse(driver, request, response, maxtime)) {
        if (request.parsePost(response, filesystem)) { deliver(request, response); }
      }
    }

    // Deliver a response to the request
    final void deliver(ref Request request, ref Response response, bool finalrewrite = false) {
      if (!request.isValid) return(response.badRequest());

      string localroot = filesystem.localroot(request.shorthost());
      log(Level.Trace, "%s:%s %s client (%s)", request.ip, request.port, (finalrewrite? "redirecting" : "routing"), request.id);
      log(Level.Trace, "shorthost -> localroot: %s -> %s", request.shorthost(), localroot);
      if (request.shorthost() == "" || !exists(localroot)) return(response.domainNotFound());

      version(SSL) { if (serveACMEChallenge(request, response)) return; }

      config = WebConfig(filesystem.file(localroot, "/web.config"));
      string fqdn = config.domain(request.shorthost());
      string localpath = safePath(localroot, decodeComponent(request.path));
      if (localpath is null) return(response.forbidden());

      bool pathExists  = localpath.exists();
      bool pathIsCGI   = pathExists && localpath.isCGI();
      bool pathIsFILE  = pathExists && localpath.isFILE();
      bool pathIsDIR   = pathExists && localpath.isDIR();
      bool pathAllowed = localpath.isAllowed();
      log(Level.Trace, "safePath result: '%s', isFILE: %s, isAllowed: %s, isCGI: %s", localpath, pathIsFILE, pathAllowed, pathIsCGI);
      log(Level.Trace, "configfile at: %s%s", localroot, "/web.config");
      log(Level.Trace, "request.host: %s, fqdn: %s", request.host, fqdn);
      log(Level.Trace, "localpath: %s, exists ? %s", localpath, pathExists);

      version (SSL) {
        bool hasCert = hasCertificate(fqdn);
        if (request.isSecure != hasCert || request.host != fqdn) {
          log(Level.Trace, "SSL redirect %s != %s for %s to fqdn: %s", request.isSecure, hasCert, request.host, fqdn);
          return(response.redirect(request, fqdn, hasCert));
        }
      } else { if (request.host != fqdn) { return(response.redirect(request, fqdn, false)); } }

      if (pathExists) {
        log(Level.Trace, "allowcgi: %s, localpath %s exists", config.allowcgi, localpath);
        if (pathIsCGI && config.allowcgi) {
          log(Level.Trace, "localpath %s is a CGI file", localpath);
          return(response.serveCGI(request, config, filesystem));
        }
        if (pathIsFILE && !pathIsCGI && pathAllowed) {
          log(Level.Trace, "localpath %s is a normal file", localpath);
          return(response.serveStaticFile(request, filesystem));
        }
        if (pathIsDIR && config.dirAllowed(localroot, localpath)) {
          log(Level.Trace, "localpath %s is a directory [%s,%s]", localpath, config.redirectdir(), config.index());
          if (config.redirectdir() && !finalrewrite) { return(redirectDirectory(request, response)); }
          if (config.redirect() && exists(localpath ~ "/" ~ config.index()) && !finalrewrite) { return(redirectCanonical(request, response)); }
          return(response.serveDirectory(request, config, filesystem));
        }
        return(response.forbidden());
      }

      log(Level.Trace, "redirect: %s %d", config.redirect, finalrewrite);
      if(config.redirect && !finalrewrite) { return(this.redirectCanonical(request, response)); }
      return(response.notFound());  // Request is not hosted on this server
    }

    version(SSL) {
      import danode.acme : acmeChallenges, getAcmeMutex;

      bool serveACMEChallenge(ref Request request, ref Response response) {
        if (!request.isSecure && request.path.startsWith("/.well-known/acme-challenge/")) {
          log(Level.Verbose, "Router: serveACMEChallenge path: %s", request.path);
          string token = baseName(request.path);
          string keyAuth;
          synchronized(getAcmeMutex()) {
            if (token in acmeChallenges) keyAuth = acmeChallenges[token];
          }
          if (keyAuth.length) { return(response.setPayload(StatusCode.Ok, keyAuth, "text/plain")); }
        }
        return(false);
      }
    }

    // Expose scan() by forwarding to filesystem.scan()
    final void scan() { filesystem.scan(); }

    // Redirect a directory browsing request to the index script
    void redirectDirectory(ref Request request, ref Response response){
      log(Level.Trace, "redirecting directory request to index page");
      request.redirectdir(config);
      return deliver(request, response, true);
    }

    // Perform a canonical redirect of a non-existing page to the index script
    void redirectCanonical(ref Request request, ref Response response){
      log(Level.Trace, "redirecting non-existing page (canonical url) to the index page");
      request.url  = format("%s?%s", config.index, request.query);
      return deliver(request, response, true);
    }
}

// Helper function used to make calls during a unittest, setup a driver, a client and run the request
void runRequest(Router router, string request = "GET /dmd.d HTTP/1.1\nHost: localhost\n\n") {
  auto driver = new StringDriver(request);
  auto client = new Client(router, driver, 250);
  log(Level.Verbose, "%s:%s %s", client.ip(), client.port(), request.splitLines()[0]);
  client.start();
  while (client.running()) {
    Thread.sleep(dur!"msecs"(2));
  }
}

unittest {
  tag(Level.Always, "FILE", "%s", __FILE__);

  auto router = new Router("./www/", Address.init);
  router.runRequest("GET /dmd.d HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("POST /dmd.d HTTP/1.1\nHost: localhost\n\n");

  router.runRequest("GET /keepalive.d HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("POST /keepalive.d HTTP/1.1\nHost: localhost\n\n");

  router.runRequest("GET /notfound.txt HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("POST /notfound.txt HTTP/1.1\nHost: localhost\n\n");

  router.runRequest("GET /data.ill HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("POST /data.ill HTTP/1.1\nHost: localhost\n\n");

  router.runRequest("GET /ISE1.d HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("POST /ISE1.d HTTP/1.1\nHost: localhost\n\n");

  router.runRequest("GET /ISE2.d HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("POST /ISE2.d HTTP/1.1\nHost: localhost\n\n");

  router.runRequest("GET /ISE3.d HTTP/1.1\nHost: localhost\nConnection: keep-alive\n\n");
  router.runRequest("POST /ISE3.d HTTP/1.1\nHost: localhost\nConnection: keep-alive\n\n");

  router.runRequest("GET /test.txt HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("POST /test.txt HTTP/1.1\nHost: localhost\n\n");

  router.runRequest("GET /test HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("POST /test HTTP/1.1\nHost: localhost\n\n");

  router.runRequest("GET /test/1.txt HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("POST /test/1.txt HTTP/1.1\nHost: localhost\n\n");

  router.runRequest("GET /test/notfound.txt HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("POST /test/notfound.txt HTTP/1.1\nHost: localhost\n\n");
}

