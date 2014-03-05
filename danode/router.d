/**
 * | <a href="index.html">Home</a>             | <a href="server.html">Server</a>              |
 *   <a href="client.html">Client</a>          | <a href="router.html">Router</a>              |
 *   <a href="cgi.html">CGI</a>                | <a href="filebuffer.html">File Buffer</a>     |
 *   <a href="structs.html">Structures</a>     | <a href="helper.html">Helper functions</a>    |
 *
 * License: Use freely for any purpose
 */
module danode.router;

import std.stdio, std.string, std.file, std.path, std.conv, std.uri;
import danode.structs, danode.httpstatus, danode.filebuffer, danode.helper, danode.mimetypes;
import danode.cgi, danode.webconfig, danode.client, danode.clientfunctions, danode.request;
import danode.overview, danode.response, danode.crypto.daemon;

/***********************************
 * Route a canonical URL request from client to its destination using specified server and configuration
 */
void routeCanonical(Server server, ref Client client, in string[string] configuration, char type = 'p'){
  client.request.query = format("%c=%s", type, client.request.path[1..$]);
  client.request.path = "/" ~ getIndexPage(client.webroot, configuration);
  server.route(client, configuration);
}

/***********************************
 * Route a request from client to its destination using specified server and configuration
 */
void route(Server server, ref Client client, in string[string] configuration){
  string path;
  try{
    path = strrepl(client.webroot ~ decode(client.request.path), "//", "/");
  }catch(URIerror e){
    writefln("[URI]    Error: cannot decode URI: %s, server continuing", client.request.path);
    throw(new RException("PATH could not be decoded:" ~ e.msg, STATUS_BAD_REQUEST));
  }
  string rootpath   = strrepl(client.webroot ~ getIndexPage(client.webroot, configuration),"//","/");
  string redirect   = shortDomain(client.request.domain, configuration);

  debug writefln("[ROUTE]  %s, Root: %s, Domain: %s->%s", path, rootpath, client.request.domain, redirect);

  if(redirect != client.request.domain){                // We serve a short domain or a long domain
    client.sendMovedPermanent("http://" ~ redirect);    // The correct way is to send 301 Moved
  }else if(directRequest(path)){
    if(isCGI(path)){
      if(configuration.allowsCGI()) return client.execute(path);
      throw(new RException("CGI scripts are not allowed", STATUS_FORBIDDEN));
    }else if(allowedFileType(path)){
      return server.filebuffer.sendFile(client, path);
    }else{
      throw(new RException("File type not allowed", STATUS_FORBIDDEN));
    }
  }else if(exists(path) && isDir(path)){
    if(path != getIndexPage(path, configuration)){
      client.request.path ~= getIndexPage(path, configuration);
      return server.route(client, configuration);
    }else{
      if(path.length > 0 && path[($-1)] != '/'){        // Directory without trailing slash
        client.sendMovedPermanent(client.request.shorturl ~ "/");
      }else if(isAllowedDir(path, configuration)){                   // Directory browsing is allowed
        if(redirectDirToIndex(configuration)) return server.routeCanonical(client, configuration, 'd');
        client.setResponse(STATUS_OK, PayLoad(client.browseDir(path)));
        return client.sendResponse();
      }else{                                            // Directory browsing is not allowed
        throw(new RException("Directory browsing is not allowed for this directory", STATUS_FORBIDDEN));
      }
    }      // Filter out 'local' server requests to 127.0.0.1
  }else{   // Otherwise there is no such file, so route canonical to root path when thats CGI
    if(client.webroot.indexOf("127.0.0.1") >= 0) return serverPage(server, client);
    if(configuration.allowsCoins() && client.request.path == "/crypto") return cryptoPage(server.cryptodaemon, client);
    if(isCGI(rootpath)) return server.routeCanonical(client, configuration, 'p');
    // Too bad we failed even canonical request, return not found 
    throw(new RException("Page cannot be found or URL cannot be interpreted", STATUS_PAGE_NOT_FOUND));
  }
}

