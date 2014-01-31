/**
 * | <a href="index.html">Home</a>             | <a href="server.html">Server</a>              |
 *   <a href="client.html">Client</a>          | <a href="router.html">Router</a>              |
 *   <a href="cgi.html">CGI</a>                | <a href="filebuffer.html">File Buffer</a>     |
 *   <a href="structs.html">Structures</a>     | <a href="helper.html">Helper functions</a>    |
 *
 * License: Use freely for any purpose
 */
module danode.response;

import std.stdio, std.string, std.datetime, std.compiler, std.conv, std.file;
import danode.structs, danode.helper;

/***********************************
 * Create a string header from the response
 */
string createResponseHeader(in Response response){
  string header = format(headerFMT, response.code, response.reason, SERVER_INFO, std.compiler.name
                         , version_major, version_minor, (response.keepalive)? "keep-alive" : "close"
                         , response.mime, response.charset, response.payload.length);
  foreach(key; response.headers.byKey()){
    header ~= format("%s: %s\r\n", key, response.headers[key]); 
  }
  if(response.date != SysTime.init) header ~= format("Date: %s\r\n", htmlTime(response.date));
  return header ~ "\r\n";
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

