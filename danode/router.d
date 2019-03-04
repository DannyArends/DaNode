module danode.router;

import danode.imports;
import danode.cgi : CGI;
import danode.client : Client;
import danode.interfaces : ClientInterface, DriverInterface, StringDriver;
import danode.httpstatus : StatusCode;
import danode.request : Request;
import danode.response;
import danode.webconfig : WebConfig;
import danode.payload : Message;
import danode.mimetypes : mime;
import danode.functions : from, has, isCGI, isFILE, isDIR, Msecs, htmltime, isAllowed, writefile;
import danode.filesystem : FileSystem, FileInfo;
import danode.post : parsePost, PostType;
import danode.log : custom, trace, info, Log, NOTSET, NORMAL;
version(SSL) {
  import danode.ssl : hasCertificate;
}

class Router {
  private:
    FileSystem filesystem;
    Log logger;
    WebConfig config;

  public:
    this(string wwwRoot = "./www/", int verbose = NORMAL){
      this.logger = new Log(verbose);
      this.filesystem = new FileSystem(logger, wwwRoot);
    }

    FileSystem getFileSystem() { return(this.filesystem); }
    WebConfig getWebConfig() { return(this.config); }

    void logRequest(in ClientInterface client, in Request request, in Response response) {
      logger.updatePerformanceStatistics(client, request, response);
      logger.logRequest(client, request, response);
    }

    final bool parse(in DriverInterface driver, ref Request request, ref Response response) const {
      if (!driver.hasHeader()) return(false);
      if (!response.created) {
        request.initialize(driver);
        response = request.create();
      } else {
        request.update(driver.body);
      }
      return(true);
    }

    final void route(DriverInterface driver, ref Request request, ref Response response) {
      if ( !response.routed && parse(driver, request, response)) {
        if ( parsePost(request, response, filesystem) ) { // We have stored all the post data, and can deliver a response
          deliver(request, response);
        }
      }
    }

    final void deliver(ref Request request, ref Response response, bool finalrewrite = false) {
      string localroot = filesystem.localroot(request.shorthost());

      trace("%s:%s %s client (%s)", request.ip, request.port, (finalrewrite? "redirecting" : "routing"), request.id);
      trace("shorthost -> localroot: %s -> %s", request.shorthost(), localroot);

      if (request.shorthost() == "" || !exists(localroot)) // No domain requested, or we are not hosting it
        return response.domainNotFound(request);

      config = WebConfig(filesystem.file(localroot, "/web.config"));
      string fqdn = config.domain(request.shorthost());
      string localpath = config.localpath(localroot, request.path);

      trace("configfile at: %s%s", localroot, "/web.config");
      trace("request.host: %s, fqdn: %s", request.host, fqdn);
      trace("localpath: %s, exists ? %s", localpath, localpath.exists());

      version (SSL) {
        // Check if teh security requested can be provided, by checking SSL status
        // against a certificate availability, and/or fix the requested the wrong 
        // shortdomain requested by the client (domain.com or www.domain.com)
        if (request.isSecure != hasCertificate(fqdn) || request.host != fqdn) {
          trace("SSL redirect %s != %s for %s to fqdn: %s", request.isSecure, hasCertificate(fqdn), request.host, fqdn);
          return response.redirect(request, fqdn, hasCertificate(fqdn));
        }
      } else {  
        // No SSL, just check if the client requested the 'wrong' fully qualified 
        // domain (domain.com or www.domain.com), and redirect them
        if (request.host != fqdn) {
          return response.redirect(request, fqdn, false);
        }
      }

      if (localpath.exists()) {
        trace("localpath %s exists", localpath);
        // A path that can be responded to has been detected, it is an existing resource
        if (localpath.isCGI() && config.allowcgi) {
          trace("localpath %s is a CGI file", localpath);
          return response.serveCGI(request, config, filesystem); // Serve CGI script
        }
        if (localpath.isFILE() && !localpath.isCGI() && localpath.isAllowed()) {
          trace("localpath %s is a normal file", localpath);
          return response.serveStaticFile(request, filesystem);
        }
        if (localpath.isDIR() && config.isAllowed(localroot, localpath)) {
          trace("localpath %s is a directory [%s,%s]", localpath, config.redirectdir(), config.index());
          if (config.redirectdir() && !finalrewrite)  // Route this directory request to the index page
            return this.redirectDirectory(request, response); // Redirect the directory

          if (config.redirect() && exists(localpath ~ "/" ~ config.index()) && !finalrewrite)  // Route this directory request to the index page
            return this.redirectCanonical(request, response); // Redirect the directory

          return response.serveDirectory(request, config, filesystem);
        }
        return response.serveForbidden(request);
      }
      trace("redirect: %s %d", config.redirect, finalrewrite);
      if(config.redirect && !finalrewrite)  // Route this request as canonical request the index page
        return this.redirectCanonical(request, response);

      return response.notFound();  // Request is not hosted on this server
    }

    void redirectDirectory(ref Request request, ref Response response){
      trace("redirecting directory request to index page");
      request.redirectdir(config);
      return deliver(request, response, true);
    }

    void redirectCanonical(ref Request request, ref Response response){
      trace("redirecting non-existing page (canonical url) to the index page");
      request.page = request.uripath(); // Save the URL path
      request.url  = format("%s?%s", config.index, request.query);
      return deliver(request, response, true);
    }

    final @property int verbose(string verbose = "") {
      string[] sp = verbose.split(" ");
      int nval = NOTSET;
      if(sp.length == 1) nval = to!int(sp[0]);
      if(sp.length >= 2) nval = to!int(sp[1]);
      return(logger.verbose(nval)); 
    }
}

void runRequest(Router router, string request = "GET /dmd.d HTTP/1.1\nHost: localhost\n\n") {
  auto driver = new StringDriver(request);
  auto client = new Client(router, driver, 100);
  custom(0, "TEST", "%s:%s %s", client.ip(), client.port(), split(request, "\n")[0]);
  client.start();
  while (client.running()) {
    Thread.sleep(dur!"msecs"(2));
  }
}

unittest {
  custom(0, "FILE", "%s", __FILE__);

  auto router = new Router("./www/", NORMAL);
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

  router.runRequest("GET /test.txt HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("POST /test.txt HTTP/1.1\nHost: localhost\n\n");

  router.runRequest("GET /test HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("POST /test HTTP/1.1\nHost: localhost\n\n");

  router.runRequest("GET /test/1.txt HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("POST /test/1.txt HTTP/1.1\nHost: localhost\n\n");

  router.runRequest("GET /test/notfound.txt HTTP/1.1\nHost: localhost\n\n");
  router.runRequest("POST /test/notfound.txt HTTP/1.1\nHost: localhost\n\n");
}

