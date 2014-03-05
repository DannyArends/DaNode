/**
 * | <a href="index.html">Home</a>             | <a href="server.html">Server</a>              |
 *   <a href="client.html">Client</a>          | <a href="router.html">Router</a>              |
 *   <a href="cgi.html">CGI</a>                | <a href="filebuffer.html">File Buffer</a>     |
 *   <a href="structs.html">Structures</a>     | <a href="helper.html">Helper functions</a>    |
 *
 * License: Use freely for any purpose
 */
module danode.response;

import std.stdio, std.string, std.datetime, std.compiler, std.conv, std.array;
import danode.structs, danode.helper;

/***********************************
 * Create a string header from the response
 */
string createResponseHeader(in Response response){
  auto header = appender!string("");
  header.put(format(headerFMT, response.code, response.reason, SERVER_INFO, std.compiler.name
                         , version_major, version_minor, (response.keepalive)? "keep-alive" : "close"
                         , response.mime, response.charset, response.payload.length));
  foreach(key; response.headers.byKey()){
    header.put(format("%s: %s\r\n", key, response.headers[key]));
  }
  if(response.date != SysTime.init) header.put(format("Date: %s\r\n", htmlTime(response.date)));
  header.put(format("Cache-Control: max-age=%d, public, must-revalidate\r\n", response.maxage));
  header.put("\r\n");
  return(header.data);
}

/***********************************
 * Response expection class
 */
class RException : Exception{
  Response response;  /// The response we need to send to the client
  this(string msg, Response r, Throwable next = null){ 
    response=r; response.payload = PayLoad(msg);
    response.mime = "text/html"; super(msg, next);
  }
}

