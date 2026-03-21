/** danode/router.d - Request routing: domain resolution, path dispatch, CGI/static/directory
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.router;

import danode.imports;

import danode.client : Client;
import danode.interfaces : DriverInterface, StringDriver;
import danode.statuscode : StatusCode;
import danode.request : Request;
import danode.response : Response, setPayload, create, badRequest, domainNotFound, forbidden, redirect, serveCGI, serveDirectory, notFound;
import danode.files : serveStaticFile;
import danode.webconfig : getConfig, WebConfig;
import danode.filesystem : FileSystem, isCGI, isFILE, isDIR, isAllowed, safePath;
import danode.post : parsePost;
import danode.log : log, tag, Level;
import danode.signals : shutdownSignal;

version(SSL) {
  import danode.ssl : hasCertificate;
}

class Router {
  private:
    FileSystem filesystem;
    WebConfig[string] configs;
    Address address;

  public:
    this(string wwwRoot = "./www/", Address address = Address.init){
      this.address = address;
      this.filesystem = new FileSystem(wwwRoot);
    }

    // Parse the header of a request, or receive additional post data when the user is uploading
    final bool parse(in DriverInterface driver, ref Request request, ref Response response) {
      if (!driver.hasHeader()) return(false);
      if (!response.created) {
        request.initialize(driver);
        response = request.create(this.address);
      } else { request.update(driver.content); }
      return(true);
    }

    // Route a request based on the request header
    final void route(DriverInterface driver, ref Request request, ref Response response) {
      if (!response.routed && parse(driver, request, response)) {
        if (request.parsePost(response, filesystem, driver)) { deliver(request, response); }
      }
    }

    // Deliver a response to the request
    final void deliver(ref Request request, ref Response response, bool finalrewrite = false) {
      if (!request.isValid) return(response.badRequest());

      string localroot = filesystem.localroot(request.shorthost());
      log(Level.Trace, "Router: [T] %s:%s %s client (%s)", request.ip, request.port, (finalrewrite? "redirecting" : "routing"), request.id);
      log(Level.Trace, "Router: [T] shorthost '%s' -> localroot '%s'", request.shorthost(), localroot);
      if (request.shorthost() == "" || !exists(localroot)) return(response.domainNotFound());

      version(SSL) { if (serveACMEChallenge(request, response)) return; }

      auto config = getConfig(configs, filesystem.file(localroot, "/web.config"), localroot);
      auto fqdn = config.domain(request.shorthost());
      auto localpath = safePath(localroot, decodeComponent(request.path));
      if (localpath is null) return(response.forbidden());

      bool pathExists  = localpath.exists();
      bool pathIsCGI   = pathExists && localpath.isCGI();
      bool pathIsFILE  = pathExists && localpath.isFILE();
      bool pathIsDIR   = pathExists && localpath.isDIR();
      bool pathAllowed = localpath.isAllowed();
      log(Level.Trace, "Router: [T] safePath result: '%s', isFILE: %s, isAllowed: %s, isCGI: %s", localpath, pathIsFILE, pathAllowed, pathIsCGI);
      log(Level.Trace, "Router: [T] configfile at: %s%s", localroot, "/web.config");
      log(Level.Trace, "Router: [T] request.host: %s, fqdn: %s", request.host, fqdn);
      log(Level.Trace, "Router: [T] localpath: %s, exists ? %s", localpath, pathExists);

      version (SSL) {
        bool hasCert = hasCertificate(fqdn);
        if (request.isSecure != hasCert || request.host != fqdn) {
          log(Level.Trace, "Router: [T] SSL redirect %s != %s for %s to fqdn: %s", request.isSecure, hasCert, request.host, fqdn);
          return(response.redirect(request, fqdn, hasCert));
        }
      } else { if (request.host != fqdn) { return(response.redirect(request, fqdn, false)); } }

      if (pathExists) {
        log(Level.Trace, "Router: [T] allowcgi: %s, localpath %s exists", config.allowcgi, localpath);
        if (pathIsCGI && config.allowcgi) {
          log(Level.Trace, "Router: [T] localpath %s is a CGI file", localpath);
          return(response.serveCGI(request, config, filesystem, localpath));
        }
        if (pathIsFILE && !pathIsCGI && pathAllowed) {
          log(Level.Trace, "Router: [T] localpath %s is a normal file", localpath);
          return(response.serveStaticFile(request, filesystem.file(filesystem.localroot(request.shorthost()), request.path)));
        }
        if (pathIsDIR && config.dirAllowed(localroot, localpath)) {
          log(Level.Trace, "Router: [T] localpath %s is a directory [%s,%s]", localpath, config.redirectdir(), config.index());
          if (config.redirectdir() && !finalrewrite) { return(redirectDirectory(config, request, response)); }
          if (config.redirect() && exists(localpath ~ "/" ~ config.index()) && !finalrewrite) {
            if (!config.allowcgi) return(response.notFound());
            return(redirectCanonical(config, request, response));
          }
          return(response.serveDirectory(request, config, filesystem, localpath));
        }
        return(response.forbidden());
      }

      log(Level.Trace, "Router: [T] Redirect: %s %d", config.redirect, finalrewrite);
      if(config.redirect && !finalrewrite) {
        if (!config.allowcgi) return(response.notFound());
        return(this.redirectCanonical(config, request, response));
      }
      return(response.notFound());  // Request is not hosted on this server
    }

    version(SSL) {
      import danode.acme : acmeChallenges, getAcmeMutex;

      bool serveACMEChallenge(ref Request request, ref Response response) {
        if (!request.isSecure && request.path.startsWith("/.well-known/acme-challenge/")) {
          log(Level.Verbose, "Router: [I] serveACMEChallenge path: %s", request.path);
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
    void redirectDirectory(WebConfig config, ref Request request, ref Response response){
      log(Level.Trace, "Router: [T] Redirecting directory request to index page");
      request.redirectdir(config);
      return deliver(request, response, true);
    }

    // Perform a canonical redirect of a non-existing page to the index script
    void redirectCanonical(WebConfig config, ref Request request, ref Response response){
      log(Level.Trace, "Router: [T] Redirecting canonical url to the index page");
      request.url = config.index ~ request.query;
      return deliver(request, response, true);
    }
}

// Helper function used to make calls during a unittest, setup a driver, a client and run the request
StringDriver runRequest(Router router, string request = "GET /dmd.d HTTP/1.1\nHost: localhost\n\n", long maxtime = 1000) {
  if(atomicLoad(shutdownSignal)) { exit(1); }
  tag(Level.Verbose, "runRequest", "%s", request);
  auto driver = new StringDriver(request);
  auto client = new Client(router, driver, maxtime);
  log(Level.Verbose, "Router: [I] %s:%s %s", client.ip(), client.port(), request.splitLines()[0]);
  client.run();
  return driver;
}

unittest {
  tag(Level.Always, "FILE", "%s", __FILE__);

  auto router = new Router("./www/", Address.init);
  StringDriver res;

  res = router.runRequest("GET /dmd.d HTTP/1.1\nHost: localhost\n\n");
  assert(res.lastStatus == StatusCode.Ok, format("GET /dmd.d expected 200, got %d", res.lastStatus.code));

  res = router.runRequest("POST /dmd.d HTTP/1.1\nHost: localhost\n\n");
  assert(res.lastStatus == StatusCode.Ok, format("POST /dmd.d expected 200, got %d", res.lastStatus.code));

  res = router.runRequest("GET /keepalive.d HTTP/1.1\nHost: localhost\n\n");
  assert(res.lastStatus == StatusCode.Ok, format("GET /keepalive.d expected 200, got %d", res.lastStatus.code));
  res = router.runRequest("POST /keepalive.d HTTP/1.1\nHost: localhost\n\n");
  assert(res.lastStatus == StatusCode.Ok, format("POST /keepalive.d expected 200, got %d", res.lastStatus.code));

  res = router.runRequest("GET /notfound.txt HTTP/1.1\nHost: localhost\n\n");
  assert(res.lastStatus == StatusCode.NotFound, format("GET /notfound.txt expected 404, got %d", res.lastStatus.code));
  res = router.runRequest("POST /notfound.txt HTTP/1.1\nHost: localhost\n\n");
  assert(res.lastStatus == StatusCode.NotFound, format("POST /notfound.txt expected 404, got %d", res.lastStatus.code));

  res = router.runRequest("GET /data.ill HTTP/1.1\nHost: localhost\n\n");
  assert(res.lastStatus == StatusCode.Forbidden, format("GET /data.ill expected 403, got %d", res.lastStatus.code));
  res = router.runRequest("POST /data.ill HTTP/1.1\nHost: localhost\n\n");
  assert(res.lastStatus == StatusCode.Forbidden, format("POST /data.ill expected 403, got %d", res.lastStatus.code));

  res = router.runRequest("GET /ISE1.d HTTP/1.1\nHost: localhost\n\n");
  assert(res.lastStatus == StatusCode.ISE, format("GET /ISE1.d expected 500, got %d", res.lastStatus.code));
  res = router.runRequest("POST /ISE1.d HTTP/1.1\nHost: localhost\n\n");
  assert(res.lastStatus == StatusCode.ISE, format("POST /ISE1.d expected 500, got %d", res.lastStatus.code));

  res = router.runRequest("GET /ISE2.d HTTP/1.1\nHost: localhost\n\n");
  assert(res.lastStatus == StatusCode.ISE, format("GET /ISE2.d expected 500, got %d", res.lastStatus.code));
  res = router.runRequest("POST /ISE2.d HTTP/1.1\nHost: localhost\n\n");
  assert(res.lastStatus == StatusCode.ISE, format("POST /ISE2.d expected 500, got %d", res.lastStatus.code));

  res = router.runRequest("GET /ISE3.d HTTP/1.1\nHost: localhost\nConnection: keep-alive\n\n");
  assert(res.lastStatus == StatusCode.TimedOut, format("GET /ISE3.d expected 408, got %d", res.lastStatus.code));
  res = router.runRequest("POST /ISE3.d HTTP/1.1\nHost: localhost\nConnection: keep-alive\n\n");
  assert(res.lastStatus == StatusCode.TimedOut, format("POST /ISE3.d expected 408, got %d", res.lastStatus.code));

  res = router.runRequest("GET /test.txt HTTP/1.1\nHost: localhost\n\n");
  assert(res.lastStatus == StatusCode.Ok, format("GET /test.txt expected 200, got %d", res.lastStatus.code));
  res = router.runRequest("POST /test.txt HTTP/1.1\nHost: localhost\n\n");
  assert(res.lastStatus == StatusCode.Ok, format("POST /test.txt expected 200, got %d", res.lastStatus.code));

  res = router.runRequest("GET /test/ HTTP/1.1\nHost: localhost\n\n");
  assert(res.lastStatus == StatusCode.Ok, format("POST /test/ expected 200, got %d", res.lastStatus.code));
  res = router.runRequest("POST /test/ HTTP/1.1\nHost: localhost\n\n");
  assert(res.lastStatus == StatusCode.Ok, format("POST /test/ expected 200, got %d", res.lastStatus.code));

  res = router.runRequest("GET /test/1.txt HTTP/1.1\nHost: localhost\n\n");
  assert(res.lastStatus == StatusCode.Ok, format("POST /test expected 200, got %d", res.lastStatus.code));
  res = router.runRequest("POST /test/1.txt HTTP/1.1\nHost: localhost\n\n");
  assert(res.lastStatus == StatusCode.Ok, format("POST /test expected 200, got %d", res.lastStatus.code));

  res = router.runRequest("GET /test/notfound.txt HTTP/1.1\nHost: localhost\n\n");
  assert(res.lastStatus == StatusCode.NotFound, format("POST /test/notfound.txt expected 404, got %d", res.lastStatus.code));
  res = router.runRequest("POST /test/notfound.txt HTTP/1.1\nHost: localhost\n\n");
  assert(res.lastStatus == StatusCode.NotFound, format("POST /test/notfound.txt expected 404, got %d", res.lastStatus.code));
}

