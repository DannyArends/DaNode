module danode.router;

import danode.imports;
import danode.interfaces : ClientInterface;
import danode.httpstatus : StatusCode;
import danode.request : Request;
import danode.response;
import danode.webconfig : WebConfig;
import danode.payload : Message, CGI;
import danode.mimetypes : mime;
import danode.functions : from, has, isCGI, isFILE, isDIR, Msecs, htmltime, isAllowed, writefile;
import danode.filesystem : FileSystem, FileInfo;
import danode.post : parsePost, PostType, serverVariables;
import danode.log : trace, Log, NOTSET, NORMAL;
version(SSL) {
  import danode.ssl : hasCertificate;
}

class Router {
  private:
    FileSystem filesystem;
    Log logger;

  public:
    this(string wwwRoot = "./www/", int verbose = NORMAL){
      this.logger = new Log(verbose);
      this.filesystem = new FileSystem(logger, wwwRoot);
    }

    void logrequest(in ClientInterface client, in Request request, in Response response) {
      logger.updatePerformanceStatistics(client, request, response);
      logger.logRequest(client, request, response);
    }

    final bool parse(in string ip, long port, ref Request request, ref Response response, in string inputSoFar, bool isSecure) const {
      ptrdiff_t idx = inputSoFar.indexOf("\r\n\r\n");
      if(idx <= 0) idx = inputSoFar.indexOf("\n\n");
      if(idx <= 0) return(false);
      if(!response.created) {
        request.parse(ip, port, inputSoFar[0 .. idx], inputSoFar[(idx + 4) .. $], isSecure);
        response = request.create();
      } else {
        request.update(inputSoFar[(idx + 4) .. $]);
      }
      return(true);
    }

    final void route(in string ip, long port, ref Request request, ref Response response, in string inputSoFar, bool isSecure) {
      if ( !response.routed && parse(ip, port, request, response, inputSoFar, isSecure)) {
        if ( parsePost(request, response, filesystem) ) {
          route(request, response);
        }
      }
    }

    final void route(ref Request request, ref Response response, bool finalrewrite = false) {
      string localroot = filesystem.localroot(request.shorthost());

      trace("%s client %s:%s", (finalrewrite? "redirecting" : "routing"), request.ip, request.port);
      trace("shorthost -> localroot: %s -> %s", request.shorthost(), localroot);

      if (request.shorthost() == "" || !exists(localroot)) // No domain requested, or we are not hosting it
        return response.domainNotFound(request);

      WebConfig config = WebConfig(filesystem.file(localroot, "/web.config"));
      string fqdn = config.domain(request.shorthost());
      string localpath = config.localpath(localroot, request.path);

      trace("configfile at: %s%s", localroot, "/web.config");
      trace("request.host: %s, fqdn: %s", request.host, fqdn);
      trace("localpath: %s, exists ? %s", localpath, localpath.exists());

      version(SSL) {
        // SSL is available, or requested the wrong shortdomain
        if (request.isSecure != hasCertificate(fqdn) || request.host != fqdn) {
          return response.redirect(request, fqdn, hasCertificate(fqdn));
        }
      } else {  // Requested the wrong shortdomain
        if (request.host != fqdn) {
          return response.redirect(request, fqdn, false);
        }
      }

      if(localpath.exists()) {  // Requested an existing resource
        if(localpath.isCGI() && config.allowcgi)
          return response.serveCGI(request, config, filesystem);

        if(localpath.isFILE() && !localpath.isCGI() && localpath.isAllowed())
          return response.serveStaticFile(request, filesystem);

        if(localpath.isDIR() && config.isAllowed(localroot, localpath)){
          if(config.redirectdir() && !finalrewrite)  // Route this directory request to the index page
            return this.redirectDirectory(request, response, config);

          if(config.redirect && !finalrewrite)  // Modify request as canonical to the index page
            return this.redirectCanonical(request, response, config);

          return response.serveDirectory(request, config, filesystem);
        }
        return response.serveForbidden(request);
      }
      trace("redirect: %s %d", config.redirect, finalrewrite);
      if(config.redirect && !finalrewrite)  // Route this request as canonical request the index page
        return this.redirectCanonical(request, response, config);

      return response.notFound(logger.verbose);  // Request is not hosted on this server
    }

    void redirectDirectory(ref Request request, ref Response response, in WebConfig config){
      trace("redirecting directory request to index page");
      request.redirectdir(config);
      return route(request, response, true);
    }

    void redirectCanonical(ref Request request, ref Response response, in WebConfig config){
      trace("redirecting non-existing page (canonical url) to the index page");
      request.page = request.uripath(); // Save the URL path
      request.url  = format("%s?%s", config.index, request.query);
      return route(request, response, true);
    }

    final @property int verbose(string verbose = "") {
      string[] sp = verbose.split(" ");
      int nval = NOTSET;
      if(sp.length >= 2) nval = to!int(sp[1]);
      return(logger.verbose(nval)); 
    }
}

