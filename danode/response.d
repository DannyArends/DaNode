module danode.response;

import danode.imports;
import danode.cgi : CGI;
import danode.interfaces : DriverInterface, StringDriver;
import danode.functions : htmltime;
import danode.statuscode : StatusCode, noBody;
import danode.request : Request;
import danode.mimetypes : UNSUPPORTED_FILE;
import danode.files : FileStream, FilePayload;
import danode.payload : Payload, PayloadType, HeaderType, Message;
import danode.log : tag, log, Level;
import danode.webconfig;
import danode.filesystem : FileSystem;
import danode.post : serverAPI;
import danode.functions : browseDir;

immutable string SERVERINFO = "DaNode/0.0.3";

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
    if (hdr.data) { return(hdr.data); /* Header was constructed */ }

    // Scripts are allowed to have/send their own header
    if (payload.type == PayloadType.Script) {
      CGI script = to!CGI(payload);
      foreach (line; script.fullHeader().split("\n")) {
        auto v = line.split(": ");
        if(v.length == 2) this.headers[v[0]] = chomp(v[1]);
      }
      if (buildScriptHeader(hdr, connection, script, protocol)) return(hdr.data);
    }
    // Server-generated header
    hdr.put(format("%s %d %s\r\n", protocol, statuscode, statuscode.reason));
    foreach (key, value; headers) { hdr.put(format("%s: %s\r\n", key, value)); }
    hdr.put(format("Date: %s\r\n", htmltime()));
    if (payload.type != PayloadType.Script && !noBody(statuscode)) {
      long contentLength = isRange ? (rangeEnd - rangeStart + 1) : payload.length;
      hdr.put(format("Content-Length: %d\r\n", contentLength));
      hdr.put(format("Content-Type: %s\r\n", payload.mimetype));
      if (maxage > 0) { hdr.put(format("Cache-Control: max-age=%d, public\r\n", maxage)); }
    }
    if (payload.mtime != SysTime.init) { hdr.put(format("Last-Modified: %s\r\n", htmltime(payload.mtime))); }
    hdr.put(format("Connection: %s\r\n\r\n", connection));
    return(hdr.data);
  }

  // Propagate shutdown through the chain to kill Process
  final void kill() {
    if (payload && payload.type == PayloadType.Script) { to!CGI(payload).notifyovertime(); }
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
  @property final bool scriptCompleted() { return(canComplete && payload.type == PayloadType.Script && payload.ready > 0 && index >= length); }
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
  connection = script.getHeader("Connection", "No Request");
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
    hdr.put(scriptheader);
    if (!hdr.data.endsWith("\r\n\r\n")) hdr.put("\r\n");
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
  response.customheader("Server", SERVERINFO);
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
void serveCGI(ref Response response, in Request request, in WebConfig config, in FileSystem fs, bool removeInput = true) {
  log(Level.Trace, "Requested a cgi file, execution allowed");
  string localroot = fs.localroot(request.shorthost());
  string localpath = config.localpath(localroot, request.path);
  if (!response.routed) { // Store POST data (could fail multiple times)
    log(Level.Trace, "Writing server variables");
    fs.serverAPI(config, request, response);
    log(Level.Trace, "Creating CGI payload");
    response.payload = new CGI(request.command(localpath), request.inputfile(fs), request.environ(localpath), removeInput, request.maxtime-5);
    response.ready = true;
  }
}

// serve a directory browsing request, via a message
void serveDirectory(ref Response response, ref Request request, in WebConfig config, in FileSystem fs) {
  log(Level.Trace, "Sending browse directory");
  string localroot = fs.localroot(request.shorthost());
  string localpath = config.localpath(localroot, request.path);
  response.setPayload(StatusCode.Ok, browseDir(localroot, localpath), "text/html");
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
