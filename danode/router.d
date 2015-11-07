module danode.router;

import std.array : Appender, split, join;
import std.stdio, std.string, std.conv, std.datetime, std.file, std.math;
import std.uri : encode;
import std.string : indexOf;
import danode.client : ClientInterface;
import danode.httpstatus : StatusCode;
import danode.request : Request, internalredirect;
import danode.response : SERVERINFO, Response, redirect, create, notmodified;
import danode.webconfig : WebConfig;
import danode.payload : Message, CGI;
import danode.mimetypes : mime;
import danode.functions : from, has, isCGI, isFILE, isDIR, Msecs, htmltime, browsedir, isAllowed, writefile;
import danode.filesystem : FileSystem, FileInfo;
import danode.post : parsepost, PostType, servervariables;
import danode.log;

class Router {
  private:
    FileSystem      filesystem;
    Log             logger;

  public:
    this(int verbose = NORMAL){ logger = new Log(verbose); filesystem = new FileSystem(logger); }

    void logrequest(in ClientInterface client, in Request request, Response response){ logger.write(client, request, response); }

    final bool parse(ClientInterface client, in string reqstr, ref Request request, ref Response response) const {
      long header = reqstr.indexOf("\r\n\r\n");
      if(header > 0){
        if(!response.created){
          request   = Request(client, reqstr[0 .. header], reqstr[(header + 4) .. $], logger.verbose);
          response  = request.create();
        }else{
          request.content = reqstr[(header + 4) .. $];
        }
        return(true);
      }
      return(false);
    }

    final void route(ClientInterface client, ref Request request, ref Response response, in string reqstr) {
      if(!response.routed && parse(client, reqstr, request, response) ) {
        if( parsepost(request, response, filesystem, logger.verbose) ) {
          route(client, request, response);
        }
      }
    }

    final void route(ClientInterface client, ref Request request, ref Response response, bool finalrewrite = false) {
      if(logger.verbose >= DEBUG) writefln("[DEBUG]  start to %s client %s:%s", (finalrewrite? "redirect" : "route"), client.ip,client.port);
      string      localroot   = filesystem.localroot(request.shorthost());    // writefln("[INFO]   shorthost -> localroot: %s -> %s", request.shorthost(), localroot);
      if(request.shorthost() == "" || !exists(localroot)) {
        writefln("[WARN]   requested domain '%s', was not found", request.shorthost());
        response.payload = new Message(StatusCode.NotFound, format("404 - No such domain is available"));
        response.ready = true;
        return;
      }
      FileInfo    configfile  = filesystem.file(localroot, "/web.config");    // writefln("[INFO]   configfile at: %s%s", localroot, "/web.config");
      WebConfig   config      = WebConfig(configfile);                        // writefln("[INFO]   parsed config file");
      string      fqdn        = config.domain(request.shorthost());           // writefln("[INFO]   fqdn: %s", fqdn);
      string      localpath   = config.localpath(localroot, request.path);    // writefln("[INFO]   localpath: %s", localpath);

      if(request.host != fqdn){                                                                       // Requested the wrong shortdomain
        response.redirect(request, fqdn);
        response.ready = true;
      } else if(localpath.exists()) {                                                                 // Requested an existing resource
        if(localpath.isCGI() && config.allowcgi){                                                       // CGI File
          if(!response.routed){              // Check, and store POST data (could fail multiple times)
            filesystem.servervariables(config, request, response, logger.verbose);
            response.payload = new CGI(request.command(localpath), request.inputfile(filesystem), logger.verbose);
            response.ready = true;
          }
        }else if(localpath.isFILE() && !localpath.isCGI() && localpath.isAllowed()){                    // Static File
          response.payload = filesystem.file(localroot, request.path);
          if(request.ifModified >= response.payload.mtime()){                            // Non modified static content
            response.notmodified(request, response.payload.mimetype);
          }
          response.ready = true;
        }else if(localpath.isDIR() && config.isAllowed(localroot, localpath)){                          // Directory
          if(config.internalredirect(request)) return route(client, request, response);
          response.payload = new Message(StatusCode.Ok, browsedir(localroot, localpath), "text/html");
          response.ready = true;
        }else{                                                                                          // Forbidden to access from the web
          response.payload = new Message(StatusCode.Forbidden, format("403 - Access to this resource has been restricted"));
          response.ready = true;
        }
      }else if(config.redirect && !finalrewrite){                                                     // Try to re-route this request to the index page
        request.page = request.uripath();                                                             // Save the URL path
        request.url  = format("%s?%s", config.index, request.query);
        return route(client, request, response, true);
      }else{                                                                                          // Request is not hosted on this server
        response.payload = new Message(StatusCode.NotFound, format("404 - The requested path does not exists on disk"));
        response.ready = true;
      }
      if(logger.verbose >= DEBUG) writefln("[DEBUG]  routing performed for client %s:%s", client.ip,client.port);
    }

    final @property int verbose(string verbose = "") {
      string[] sp = verbose.split(" ");
      int nval = NOTSET;
      if(sp.length >= 2) nval = to!int(sp[1]);
      return(logger.verbose(nval)); 
    }

    final @property string stats(){ return(format("%s", logger.statistics)); }
}

