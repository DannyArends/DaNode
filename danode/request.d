/**
 * | <a href="index.html">Home</a>             | <a href="server.html">Server</a>              |
 *   <a href="client.html">Client</a>          | <a href="router.html">Router</a>              |
 *   <a href="cgi.html">CGI</a>                | <a href="filebuffer.html">File Buffer</a>     |
 *   <a href="structs.html">Structures</a>     | <a href="helper.html">Helper functions</a>    |
 *
 * License: Use freely for any purpose
 */
module danode.request;

import std.stdio, std.string, std.socket, std.regex, std.uri, std.conv;
import danode.structs, danode.helper, danode.client, danode.response, danode.httpstatus;

/***********************************
 * Ceate a standard HTML error string from the request and the response status using msg
 */
string stdErr(in Request request, in Response status, in string msg = ""){
  return al(format(errFmt, status.code, status.reason, status.reason, request.domain, msg, SERVER_INFO), 2*KBYTE);
}

/***********************************
 * Parse the header from input string reqstring
 */
bool parseHeader(ref Request request, in string reqstring){
  debug writefln("[REQ]    Start parsing header");
  string[] lines  = reqstring.split("\r\n");
  string[] hline  = lines[0].split(" ");
  if(hline.length != 3)
    throw(new RException("Malformed header (incorrect first line)", STATUS_BAD_REQUEST));

  request.method   = strip(hline[0]);
  request.path     = strip(hline[1]);
  request.protocol = strip(hline[2]);

  if(!(request.method == "POST" || request.method == "GET"))
    throw(new RException(format("Method %s not allowed", request.method), STATUS_METHOD_NOT_ALLOWED));
  if(!(request.protocol == "HTTP/1.0" || request.protocol == "HTTP/1.1"))
    throw(new RException(format("HTTP version %s not supported", request.protocol), STATUS_VERSION_UNSUPPORTED));

  int qmark = cast(int)request.path.indexOf("?");
  if(qmark > 0){                                      // Query String
    request.query = request.path[(qmark+1) .. $];
    request.path  = request.path[0 .. qmark];
  }
  if(lines.length > 1){
    foreach(line; lines[1..$]){
      string[] parts = line.split(":");
      if(parts.length > 1){
        request.headers[strip(parts[0])] = strip(parts[1]);
        if(strip(parts[0]) == "Host") request.domain = request.headers[strip(parts[0])];
      }
    }
  }
  debug writefln("[REQ]    Header information");
  return true;
}

/***********************************
 * What url do we need to serve http://domain.ext or http://www.domain.ext
 */
string shortDomain(string domain, in string[string] config){
  if(!inarr("shorturl", config)) return domain;      // No option set
  if(domain.length > 4){
    string start     = toLower(domain[0 .. 4]);
    bool shortDomain = fromarr("shorturl", config) == "yes";
    if(start == "www." && shortDomain)  return domain[4..$];
    if(start != "www." && !shortDomain) return "www." ~ domain;
  }
  return domain;
}

