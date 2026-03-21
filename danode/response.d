/** danode/response.d - HTTP response construction, CGI header handling, static helpers
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.response;

import danode.imports;

import danode.cgi : CGI;
import danode.functions : htmltime;
import danode.statuscode : StatusCode, noBody;
import danode.request : Request;
import danode.mimetypes : UNSUPPORTED_FILE;
import danode.payload : Payload, PayloadType, HeaderType, Message;
import danode.log : tag, log, Level;
import danode.webconfig : WebConfig, serverConfig;
import danode.filesystem : FileSystem;
import danode.post : serverAPI;
import danode.functions : browseDir;

struct Response {
  string            protocol = "HTTP/1.1";
  string            connection = "Close";
  Address           address;
  long              maxage = 0;
  string[string]    headers;
  Payload           payload;
  bool              created = false;
  bool              havepost = false;
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
  return(response.ready = response.havepost = true);
}

// send a redirect permanently response
void redirect(ref Response response, in Request request, in string fqdn, bool isSecure = false) {
  log(Level.Trace, "Redirecting request to %s", fqdn);
  response.setPayload(StatusCode.MovedPermanently);
  response.customheader("Location", format("http%s://%s%s%s", isSecure? "s": "", fqdn, request.path, request.query));
  response.connection = "Close";
}

// serve a not modified response
void notModified(ref Response response, in string mimetype = UNSUPPORTED_FILE, string etag = "") { 
  if (etag.length) response.customheader("ETag", etag);
  response.setPayload(StatusCode.NotModified, "", mimetype);
}

// serve a 404 domain not found page
void domainNotFound(ref Response response) {
  response.setPayload(StatusCode.NotFound, "404 - No such domain is available\n", "text/plain");
}

// serve a the output of an external script 
void serveCGI(ref Response response, in Request request, in WebConfig config, in FileSystem fs, string localpath, bool removeInput = true) {
  log(Level.Trace, "Requested a cgi file, execution allowed");
  if (!response.routed) { // Store POST data (could fail multiple times)
    log(Level.Trace, "Writing server variables");
    fs.serverAPI(config, request, response);
    log(Level.Trace, "Creating CGI payload");
    response.payload = new CGI(request.command(localpath), request.inputfile(fs), request.environ(localpath), removeInput);
    response.ready = true;
  }
}

// serve a directory browsing request, via a message
void serveDirectory(ref Response response, ref Request request, in WebConfig config, in FileSystem fs, string localpath) {
  log(Level.Trace, "Sending browse directory");
  response.setPayload(StatusCode.Ok, browseDir(fs.localroot(request.shorthost()), localpath), "text/html");
}

// serve a forbidden page
void forbidden(ref Response response) {
  response.setPayload(StatusCode.Forbidden, "403 - Access to this resource has been restricted\n", "text/plain");
}

// serve a 400 bad request 
void badRequest(ref Response response) {
  response.setPayload(StatusCode.BadRequest, "400 - Bad Request\n", "text/plain");
}

// serve a 404 not found page
void notFound(ref Response response) {
  response.setPayload(StatusCode.NotFound, "404 - The requested path does not exists on disk\n", "text/plain");
}

unittest {
  tag(Level.Always, "FILE", "%s", __FILE__);

  // setPayload
  Response r;
  r.setPayload(StatusCode.Ok, "hello", "text/plain");
  assert(r.ready, "setPayload must set ready");
  assert(r.statuscode == StatusCode.Ok, "setPayload must set statuscode");
  assert(r.payload.mimetype == "text/plain", "setPayload must set mimetype");

  // notFound
  Response r2;
  r2.notFound();
  assert(r2.ready, "notFound must set ready");
  assert(r2.statuscode == StatusCode.NotFound, "notFound must be 404");

  // forbidden
  Response r3;
  r3.forbidden();
  assert(r3.ready, "forbidden must set ready");
  assert(r3.statuscode == StatusCode.Forbidden, "forbidden must be 403");

  // badRequest
  Response r4;
  r4.badRequest();
  assert(r4.ready, "badRequest must set ready");
  assert(r4.statuscode == StatusCode.BadRequest, "badRequest must be 400");

  // domainNotFound
  Response r5;
  r5.domainNotFound();
  assert(r5.ready, "domainNotFound must set ready");
  assert(r5.statuscode == StatusCode.NotFound, "domainNotFound must be 404");
}
