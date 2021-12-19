module danode.router;

import danode.imports;
import danode.cgi : CGI;
import danode.client : Client;
import danode.interfaces : ClientInterface, DriverInterface, StringDriver;
import danode.statuscode : StatusCode;
import danode.request : Request;
import danode.response;
import danode.webconfig : WebConfig;
import danode.payload : Message, FilePayload;
import danode.mimetypes : mime;
import danode.functions : from, has, isCGI, isFILE, isDIR, Msecs, htmltime, isAllowed;
import danode.filesystem : FileSystem;
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
    Address address;

  public:
    this(string wwwRoot = "./www/", Address address = Address.init, int verbose = NORMAL){
      this.logger = new Log(verbose);
      this.address = address;
      this.filesystem = new FileSystem(logger, wwwRoot);
    }

    // Update the performance statistics and log the finished request
    void logRequest(in ClientInterface client, in Request request, in Response response) {
      logger.updatePerformanceStatistics(client, request, response);
      logger.logRequest(client, request, response);
    }

    // Parse the header of a request, or receive additional post data when the user is uploading
    final bool parse(in DriverInterface driver, ref Request request, ref Response response, long maxtime = 4500) {
      if (!driver.hasHeader()) return(false);
      if (!response.created) {
        request.initialize(driver, maxtime);
        response = request.create(this.address);
      } else {
        request.update(driver.body);
      }
      return(true);
    }

    // Route a request based on the request header
    final void route(DriverInterface driver, ref Request request, ref Response response, long maxtime = 4500) {
      if ( !response.routed && parse(driver, request, response, maxtime + 10)) {
        if ( parsePost(request, response, filesystem) ) { // We have stored all the post data, and can deliver a response
          deliver(request, response);
        }
      }
    }

    // Deliver a response to the request
    final void deliver(ref Request request, ref Response response, bool finalrewrite = false) {
      if (!request.isValid) return response.serveBadRequest(request);

      string localroot = filesystem.localroot(request.shorthost());

      trace("%s:%s %s client (%s)", request.ip, request.port, (finalrewrite? "redirecting" : "routing"), request.id);
      trace("shorthost -> localroot: %s -> %s", request.shorthost(), localroot);

      if (request.shorthost() == "" || !exists(localroot)) // No domain requested, or we are not hosting it
        return response.domainNotFound(request);

      config = WebConfig(filesystem.file(localroot, "/web.config"));
      string fqdn = config.domain(request.shorthost());
      string localpath = config.localpath(localroot, decodeComponent(request.path));

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
        if (localpath.isDIR() && config.dirAllowed(localroot, localpath)) {
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

    // Redirect a directory browsing request to the index script
    void redirectDirectory(ref Request request, ref Response response){
      trace("redirecting directory request to index page");
      request.redirectdir(config);
      return deliver(request, response, true);
    }

    // Perform a canonical redirect of a non-existing page to the index script
    void redirectCanonical(ref Request request, ref Response response){
      trace("redirecting non-existing page (canonical url) to the index page");
      request.page = request.uripath(); // Save the URL path
      request.url  = format("%s?%s", config.index, request.query);
      return deliver(request, response, true);
    }

    // Set the verbose level by string value
    final @property int verbose(string verbose = "") {
      string[] sp = verbose.split(" ");
      int nval = NOTSET;
      if(sp.length == 1) nval = to!int(sp[0]);
      if(sp.length >= 2) nval = to!int(sp[1]);
      return(logger.verbose(nval)); 
    }
}

// Helper function used to make calls during a unittest, setup a driver, a client and run the request
void runRequest(Router router, string request = "GET /dmd.d HTTP/1.1\nHost: localhost\n\n") {
  auto driver = new StringDriver(request);
  auto client = new Client(router, driver, 250);
  custom(0, "TEST", "%s:%s %s", client.ip(), client.port(), split(request, "\n")[0]);
  client.start();
  while (client.running()) {
    Thread.sleep(dur!"msecs"(2));
  }
}

unittest {
  custom(0, "FILE", "%s", __FILE__);

  auto router = new Router("./www/", Address.init, NORMAL);
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

