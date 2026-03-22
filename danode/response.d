/** danode/response.d - HTTP response construction, CGI header handling, static helpers
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.response;

import danode.imports;

import danode.cgi : CGI;
import danode.functions : htmltime, htmlEscape;
import danode.statuscode : StatusCode, noBody;
import danode.request : Request;
import danode.router : notFound, forbidden, badRequest, domainNotFound;
import danode.mimetypes : UNSUPPORTED_FILE;
import danode.payload : Payload, PayloadType, HeaderType, Message;
import danode.log : tag, log, Level;
import danode.webconfig : WebConfig, serverConfig;

struct Response {
  string            protocol = "HTTP/1.1";
  string            connection = "Close";
  Address           address;
  long              maxage = 0;
  string[string]    headers;
  Payload           payload;
  bool              created = false;
  bool              routed = false;
  bool              completed = false;
  Appender!(char[]) hdr;
  ptrdiff_t         index = 0;
  bool              isRange    = false;
  long              rangeStart = 0;
  long              rangeEnd   = -1;

  final void customheader(string key, string value) nothrow { headers[key] = value; }

  // Generate a HTTP header for the response
  @property final char[] header() {
    if (hdr.data) { return(hdr.data); } // Header was already constructed

    // Scripts are allowed to have/send their own header
    if (payload.type == PayloadType.Script) {
      CGI script = to!CGI(payload);
      if (buildScriptHeader(hdr, connection, script, protocol)) return(hdr.data);
      // Fallback: Populate headers from script output
      foreach (line; script.fullHeader().split("\n")) {
        auto v = line.split(":");
        if(v.length >= 2) this.headers[v[0]] = strip(join(v[1 .. $], ":"));
      }
    }
    // Server always owns these, overwrite anything the script has set
    headers["Connection"] = connection;
    headers["Date"] = htmltime();
    if (payload.mtime != SysTime.init) headers["Last-Modified"] = htmltime(payload.mtime);
    if (payload.type != PayloadType.Script && !noBody(statuscode)) {
      headers["Content-Length"] = to!string(isRange ? (rangeEnd - rangeStart + 1) : payload.length);
      headers["Content-Type"] = payload.mimetype;
      if (maxage > 0) headers["Cache-Control"] = format("max-age=%d, public", maxage);
    }

    // Header emit loop
    hdr.put(format("%s %d %s\r\n", protocol, statuscode, statuscode.reason));
    foreach (key, value; headers) { hdr.put(format("%s: %s\r\n", key, value)); }
    hdr.put("\r\n");
    return(hdr.data);
  }

  // Propagate shutdown through the chain to kill Process
  final void kill() {
    if (payload !is null && payload.type == PayloadType.Script) { 
      auto cgi = to!CGI(payload);
      cgi.notifyovertime();
      cgi.joinThread();
    }
  }

  @property final StatusCode statuscode() const {
    if (isRange) return StatusCode.PartialContent;
    return payload.statuscode;
  }
  @property @nogc final bool keepalive() const nothrow { return(icmp(connection, "keep-alive") == 0); }
  @property final long length() {
    if (isRange) return header.length + (rangeEnd - rangeStart + 1);
    return header.length + payload.length;
  }

  @property final bool isSSE() const { return(payload !is null && payload.mimetype == "text/event-stream"); }
  @property final bool scriptCompleted() { return(canComplete && payload.type == PayloadType.Script && payload.ready && index >= length); }
  @property final bool canComplete() const { return(payload !is null && payload.length >= 0); }

  // Stream of bytes (header + stream of bytes)
  @property final const(char)[] bytes(in ptrdiff_t maxsize = 4096) {
    ptrdiff_t hsize = header.length;
    if(index < hsize) {  // We haven't completed the header yet
      ptrdiff_t remaining = maxsize - hsize;
      return(header[index .. hsize] ~ payload.bytes(0, remaining > 0 ? remaining : 0, isRange, rangeStart, rangeEnd));
    }
    return(payload.bytes(index-hsize, maxsize, isRange, rangeStart, rangeEnd));
  }

  @property final bool ready(bool r = false){ 
    if(r){ routed = r; } return(routed && payload !is null && payload.ready()); }
}

bool buildScriptHeader(ref Appender!(char[]) hdr, ref string connection, CGI script, string protocol) {
  string scriptheader = script.fullHeader();
  long clength = script.getHeader("Content-Length", -1);
  auto status = script.statuscode();
  bool isSSE = script.mimetype == "text/event-stream";
  bool valid = status.code != 500 && scriptheader.length > 0 && 
               (isSSE || (clength != -1 && script.contentLengthValid));
  if (valid) {
    log(Level.Verbose, "Script '%s', status (%s)", script.command, status);
    auto htype = script.headerType();
    if (htype == HeaderType.FastCGI || htype == HeaderType.None) {
      hdr.put(format("%s %d %s\r\n", protocol, script.statuscode, script.statuscode.reason));
    }
    foreach (line; scriptheader.split("\n")) {
      auto parts = strip(line).split(":");
      if (parts.length > 0 && parts[0].length > 0 && icmp(parts[0], "connection") != 0) { hdr.put(line ~ "\n"); }
    }
    hdr.put(format("Connection: %s\r\n\r\n", connection));
    return true;
  }
  log(Level.Verbose, "Script '%s' falling back to server header (status=%s, clength=%d)", script.command, status, clength);
  connection = "Close";
  return false;
}

// create a standard response
Response create(in Request request, Address address, in StatusCode statuscode = StatusCode.Ok, in string mimetype = UNSUPPORTED_FILE){
  Response response = Response(request.protocol);
  response.address = address;
  response.customheader("Server", serverConfig.get("serverinfo", "DaNode/0.0.3"));
  response.customheader("X-Powered-By", format("%s %s.%s", name, version_major, version_minor));
  response.payload = new Message(statuscode, "", mimetype);
  response.connection = request.keepalive ? "Keep-Alive" : "Close";
  response.created = true;
  return(response);
}

bool setPayload(ref Response response, StatusCode code, string msg = "", in string mimetype = UNSUPPORTED_FILE) {
  response.payload = new Message(code, msg, mimetype);
  return(response.ready = true);
}

// Browse the content of a directory, generate a rudimentairy HTML file
string browseDir(in string root, in string localpath) {
  Appender!(string) content;
  content.put(format("Content of: %s<br>\n", htmlEscape(localpath)));
  foreach (DirEntry d; dirEntries(localpath, SpanMode.shallow)) {
    string name = d.name[root.length .. $].replace("\\", "/");
    if (name.endsWith(".in") || name.endsWith(".up")) continue;
    string escaped = htmlEscape(name);
    content.put(format("<a href='%s'>%s</a><br>", escaped, escaped));
  }
  return(format("<html><head><title>200 - Allowed directory</title></head><body>%s</body></html>", content.data));
}

unittest {
  tag(Level.Always, "FILE", "%s", __FILE__);
  Response r;

  // setPayload
  r.setPayload(StatusCode.Ok, "hello", "text/plain");
  assert(r.ready, "setPayload must set ready");
  assert(r.statuscode == StatusCode.Ok, "setPayload must set statuscode");
  assert(r.payload.mimetype == "text/plain", "setPayload must set mimetype");
  // notFound
  r.notFound();
  assert(r.ready, "notFound must set ready");
  assert(r.statuscode == StatusCode.NotFound, "notFound must be 404");
  // forbidden
  r.forbidden();
  assert(r.ready, "forbidden must set ready");
  assert(r.statuscode == StatusCode.Forbidden, "forbidden must be 403");
  // badRequest
  r.badRequest();
  assert(r.ready, "badRequest must set ready");
  assert(r.statuscode == StatusCode.BadRequest, "badRequest must be 400");
  // domainNotFound
  r.domainNotFound();
  assert(r.ready, "domainNotFound must set ready");
  assert(r.statuscode == StatusCode.NotFound, "domainNotFound must be 404");
}
