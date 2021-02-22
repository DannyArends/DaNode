module danode.response;

import danode.imports;
import danode.cgi : CGI;
import danode.interfaces : DriverInterface, StringDriver;
import danode.process : Process, WaitResult;
import danode.functions : htmltime;
import danode.statuscode : StatusCode;
import danode.request : Request;
import danode.router : Router;
import danode.mimetypes : UNSUPPORTED_FILE;
import danode.payload : Payload, FilePayload, PayloadType, HeaderType, Empty, Message;
import danode.log;
import danode.webconfig;
import danode.filesystem : FileSystem;
import danode.post : serverAPI;
import danode.functions : browseDir;

immutable string SERVERINFO = "DaNode/0.0.2 (Universal)";

struct Response {
  string            protocol = "HTTP/1.1";
  string            connection = "Keep-Alive";
  string            charset = "UTF-8";
  Address           address;
  long              maxage = 0;
  string[string]    headers;
  Payload           payload;
  bool              created = false;
  bool              havepost = false;
  bool              routed = false;
  bool              completed = false;
  bool              cgiheader = false;
  Appender!(char[]) hdr;
  ptrdiff_t         index = 0;

  final void customheader(string key, string value) nothrow { headers[key] = value; }

  // Generate a HTML header for the response
  @property final char[] header() {
    if (hdr.data) {
      return(hdr.data); // Header was constructed
    }
    // Scripts are allowed to have their own header
    if (payload.type == PayloadType.Script) {
      CGI script = to!CGI(payload);
      HeaderType type = script.headerType();
      long clength = script.getHeader("Content-Length", -1); // Is the content length provided ?
      if (type != HeaderType.None) {
        custom(1, "WARN", "script '%s', parsing header (%s, %d)", script.command, type, clength);
        return(parseHTTPResponseHeader(this, script, type, clength));
      } else {
        custom(1, "WARN", "script '%s', failed to generate a valid header (%s, %d)", script.command, type, clength);
        connection = "Close";
      }
    }
    // Construct the header for all other requests (and scripts that failed to provide a valid one
    hdr.put(format("%s %d %s\r\n", protocol, payload.statuscode, payload.statuscode.reason));
    foreach (key, value; headers) { 
      hdr.put(format("%s: %s\r\n", key, value));
    }
    hdr.put(format("Date: %s\r\n", htmltime()));
    if (payload.type != PayloadType.Script && payload.length >= 0) { // If we have any payload
      hdr.put(format("Content-Length: %d\r\n", payload.length)); // We can send the expected size
      hdr.put(format("Last-Modified: %s\r\n", htmltime(payload.mtime))); // It could be modified long ago, lets inform the client
      if (maxage > 0) { // Perhaps we can have the client cache it (when very old)
        hdr.put(format("Cache-Control: max-age=%d, public\r\n", maxage));
      }
    }
    hdr.put(format("Content-Type: %s; charset=%s\r\n", payload.mimetype, charset)); // We just send our mime and an encoding
    hdr.put(format("Connection: %s\r\n\r\n", connection)); // Client can choose to keep-alive
    return(hdr.data);
  }

  @property final StatusCode statuscode() const { return payload.statuscode; }
  @property final bool keepalive() const { return( toLower(connection) == "keep-alive"); }
  @property final long length() { return header.length + payload.length; }
  @property final const(char)[] bytes(in ptrdiff_t maxsize = 1024) {                       // Stream of bytes (header + stream of bytes)
    ptrdiff_t hsize = header.length;
    if(index <= hsize) {  // We haven't completed the header yet
      return(header[index .. hsize] ~ payload.bytes(0, maxsize-hsize));
    }
    return(payload.bytes(index-hsize));                                                    // Header completed, just stream bytes from the payload
  }

  @property final bool ready(bool r = false){ if(r){ routed = r; } return(routed && payload.ready()); }
}

// parse a HTTPresponse header from an external script
char[] parseHTTPResponseHeader(ref Response response, CGI script, HeaderType type, long clength) {
  if (type == HeaderType.FastCGI) {
    // FastCGI type header, create response line on Status: indicator
    string status = script.getHeader("Status", "500 Internal Server Error");
    response.hdr.put(format("%s %s\n", "HTTP/1.1", status));
  }
  response.hdr.put(script.fullHeader());
  info("script: status: %d, eoh: %d, content: %d", script.statuscode, script.endOfHeader(), clength);
  response.connection = strip(script.getHeader("Connection", "Close"));
  info("connection: %s -> %s, to %s in %d bytes", strip(script.getHeader("Connection", "Close")), response.connection, type, response.hdr.data.length);
  response.cgiheader = true;
  return(response.hdr.data);
}

// create a standard response
Response create(in Request request, Address address, in StatusCode statuscode = StatusCode.Ok, in string mimetype = UNSUPPORTED_FILE){
  Response response = Response(request.protocol);
  response.address = address;
  response.customheader("Server", SERVERINFO);
  response.customheader("X-Powered-By", format("%s %s.%s", name, version_major, version_minor));
  response.payload = new Empty(statuscode, mimetype);
  if (request.keepalive) response.connection = "Keep-Alive";
  response.created = true;
  return(response);
}

// send a redirect permanently response
void redirect(ref Response response, in Request request, in string fqdn, bool isSecure = false) {
  trace("redirecting request to %s", fqdn);
  response.payload = new Empty(StatusCode.MovedPermanently);
  response.customheader("Location", format("http%s://%s%s%s", isSecure? "s": "", fqdn, request.path, request.query));
  response.connection = "Close";
  response.ready = true;
}

// serve a not modified response
void notmodified(ref Response response, in Request request, in string mimetype = UNSUPPORTED_FILE) {
  response.payload = new Empty(StatusCode.NotModified, mimetype);
  response.ready = true;
}

// serve a 404 domain not found page
void domainNotFound(ref Response response, in Request request) {
  warning("requested domain '%s', was not found", request.shorthost());
  response.payload = new Message(StatusCode.NotFound, format("404 - No such domain is available\n"));
  response.ready = true;
}

// serve a 408 connection timed out page
void setTimedOut(ref DriverInterface driver, ref Response response) {
  if(response.payload && response.payload.type == PayloadType.Script){
    CGI cgi = to!CGI(response.payload);
    cgi.notifyovertime();
  }
  response.payload = new Message(StatusCode.TimedOut, format("408 - Connection Timed Out\n"));
  response.ready = true;
  driver.send(response, driver.socket);           // Send the response, hit multiple times, send what you can and return
}

// serve a the output of an external script 
void serveCGI(ref Response response, in Request request, in WebConfig config, in FileSystem fs, bool removeInput = true) {
  trace("requested a cgi file, execution allowed");
  string localroot = fs.localroot(request.shorthost());
  string localpath = config.localpath(localroot, request.path);
  if (!response.routed) { // Store POST data (could fail multiple times)
    trace("writing server variables");
    fs.serverAPI(config, request, response);
    trace("creating CGI payload");
    response.payload = new CGI(request.command(localpath), request.inputfile(fs), removeInput, request.maxtime-5);
    response.ready = true;
  }
}

// serve a static file from the disc, send encrypted when requested and available
void serveStaticFile(ref Response response, in Request request, FileSystem fs) {
  trace("serving a static file");
  string localroot = fs.localroot(request.shorthost());
  FilePayload reqFile = fs.file(localroot, request.path);
  if (request.acceptsEncoding("deflate") && reqFile.hasEncodedVersion) {
    info("will serve %s with deflate encoding", request.path);
    reqFile.deflate = true;
    response.customheader("Content-Encoding","deflate");
  }
  response.payload = reqFile;
  if (request.ifModified >= response.payload.mtime()) {                                        // Non modified static content
    trace("static file has not changed, sending notmodified");
    response.notmodified(request, response.payload.mimetype);
  }

  response.ready = true;
}

// serve a directory browsing request, via a message
void serveDirectory(ref Response response, ref Request request, in WebConfig config, in FileSystem fs) {
  trace("sending browse directory");
  string localroot = fs.localroot(request.shorthost());
  string localpath = config.localpath(localroot, request.path);
  response.payload = new Message(StatusCode.Ok, browseDir(localroot, localpath), "text/html");
  response.ready = true;
}

// serve a forbidden page
void serveForbidden(ref Response response, in Request request) {
  trace("resource is restricted from being accessed");
  response.payload = new Message(StatusCode.Forbidden, format("403 - Access to this resource has been restricted\n"));
  response.ready = true;
}

// serve a 400 bad request 
void serveBadRequest(ref Response response, in Request request) {
  trace("Request was malformed");
  response.payload = new Message(StatusCode.BadRequest, format("400 - Bad Request\n"));
  response.ready = true;
}

// serve a 404 not found page
void notFound(ref Response response) {
  trace("resource not found");
  response.payload = new Message(StatusCode.NotFound, format("404 - The requested path does not exists on disk\n"));
  response.ready = true;
}

unittest {
  custom(0, "FILE", "%s", __FILE__);
}

