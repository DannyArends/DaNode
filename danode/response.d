module danode.response;

import danode.imports;
import danode.cgi : CGI;
import danode.interfaces : StringDriver;
import danode.process : Process;
import danode.functions : htmltime;
import danode.httpstatus : reason, StatusCode;
import danode.request : Request;
import danode.router : Router;
import danode.mimetypes : UNSUPPORTED_FILE;
import danode.payload : Payload, PayloadType, HeaderType, Empty, Message;
import danode.log;
import danode.webconfig;
import danode.filesystem;
import danode.post : serverAPI;
import danode.functions : browseDir;

immutable string SERVERINFO = "DaNode/0.0.2 (Universal)";

struct Response {
  string            protocol     = "HTTP/1.1";
  string            connection   = "Close";
  string            charset      = "UTF-8";
  long              maxage       = 0;
  string[string]    headers;
  Payload           payload;
  bool              created      = false;
  bool              havepost     = false;
  bool              routed       = false;
  bool              completed    = false;
  bool              cgiheader    = false;
  Appender!(char[]) hdr;
  ptrdiff_t         index        = 0;

  final void customheader(string key, string value) nothrow { headers[key] = value; }

  @property final char[] header() {
    if (hdr.data) {
      return(hdr.data); // Header was constructed
    }
    // Scripts are allowed to have their own header
    if(payload.type == PayloadType.Script) {
      CGI script = to!CGI(payload);
      connection = "Close";
      HeaderType type = script.headerType();
      info("Header-type: %s", type);
      if (type != HeaderType.None) {
        return(parseHTTPResponseHeader(this, script, type));
      }
      warning("script '%s',  failed to generate a header", script.command);
    }
    hdr.put(format("%s %d %s\r\n", protocol, payload.statuscode, reason(payload.statuscode)));
    foreach(key, value; headers) { hdr.put(format("%s: %s\r\n", key, value)); }
    hdr.put(format("Date: %s\r\n", htmltime()));
    if(payload.type != PayloadType.Script && payload.length >= 0){                        // If we have any payload
      hdr.put(format("Content-Length: %d\r\n", payload.length));                          // We can send the expected size
      hdr.put(format("Last-Modified: %s\r\n", htmltime(payload.mtime)));                  // It could be modified long ago, lets inform the client
      if(maxage > 0) hdr.put(format("Cache-Control: max-age=%d, public\r\n", maxage));    // Perhaps we can have the client cache it (when very old)
    }
    hdr.put(format("Content-Type: %s; charset=%s\r\n", payload.mimetype, charset));       // We just send our mime and an encoding
    hdr.put(format("Connection: %s\r\n\r\n", connection));                                // Client can choose to keep-alive
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

char[] parseHTTPResponseHeader(ref Response response, CGI script, HeaderType type) {
  long clength = script.getHeader("Content-Length", -1);                              // Is the content length provided ?
  if(clength >= 0) response.connection = script.getHeader("Connection", "Close");              // Yes ? then the script, can try to keep alive
  if(type == HeaderType.FastCGI) {
    // FastCGI type header, create response line on Status: indicator
    string status = script.getHeader("Status", "500 Internal Server Error");
    string[] inparts = status.split(" ");
    if(inparts.length == 2) {
      response.hdr.put(format("%s %s %s\n", "HTTP/1.1", inparts[0], inparts[1]));
    } else {
      response.hdr.put(format("%s %s\n", "HTTP/1.1", "500 Internal Server Error"));
    }
  }
  response.hdr.put(script.fullHeader());
  info("script: status: %d, eoh: %d, content: %d", script.statuscode, script.endOfHeader(), clength);
  info("connection: %s -> %s, to %s in %d bytes", strip(script.getHeader("Connection", "Close")), response.connection, type, response.hdr.data.length);
  response.cgiheader = true;
  return(response.hdr.data);
}

Response create(in Request request, in StatusCode statuscode = StatusCode.Ok, in string mimetype = UNSUPPORTED_FILE){
  Response response = Response(request.protocol);
  response.customheader("Server", SERVERINFO);
  response.customheader("X-Powered-By", format("%s %s.%s", name, version_major, version_minor));
  response.payload = new Empty(statuscode, mimetype);
  if (request.keepalive) response.connection = "Keep-Alive";
  response.created = true;
  return(response);
}

void redirect(ref Response response, in Request request, in string fqdn, bool isSecure = false) {
  trace("redirecting request to %s", fqdn);
  response.payload = new Empty(StatusCode.MovedPermanently);
  response.customheader("Location", format("http%s://%s%s%s", isSecure? "s": "", fqdn, request.path, request.query));
  response.connection = "Close";
  response.ready = true;
}

void notmodified(ref Response response, in Request request, in string mimetype = UNSUPPORTED_FILE) {
  response.payload = new Empty(StatusCode.NotModified, mimetype);
  response.ready = true;
}

void domainNotFound(ref Response response, in Request request) {
  warning("requested domain '%s', was not found", request.shorthost());
  response.payload = new Message(StatusCode.NotFound, format("404 - No such domain is available\n"));
  response.ready = true;
}

void serveCGI(ref Response response, in Request request, in WebConfig config, in FileSystem fs) {
  trace("requested a cgi file, execution allowed");
  string localroot = fs.localroot(request.shorthost());
  string localpath = config.localpath(localroot, request.path);
  if (!response.routed) { // Store POST data (could fail multiple times)
    trace("writing server variables");
    fs.serverAPI(config, request, response);
    trace("creating CGI payload");
    response.payload = new CGI(request.command(localpath), request.inputfile(fs));
    response.ready = true;
  }
}

void serveStaticFile(ref Response response, in Request request, FileSystem fs) {
  trace("serving a static file");
  string localroot = fs.localroot(request.shorthost());
  FileInfo reqFile = fs.file(localroot, request.path);
  if(request.acceptsEncoding("deflate") && reqFile.hasEncodedVersion) {
    info("will serve %s with deflate encoding", request.path);
    reqFile.deflate = true;
    response.customheader("Content-Encoding","deflate");
  }
  response.payload = reqFile;
  if(request.ifModified >= response.payload.mtime()) {                                        // Non modified static content
    trace("static file has not changed, sending notmodified");
    response.notmodified(request, response.payload.mimetype);
  }

  response.ready = true;
}

void serveDirectory(ref Response response, ref Request request, in WebConfig config, in FileSystem fs) {
  trace("sending browse directory");
  string localroot = fs.localroot(request.shorthost());
  string localpath = config.localpath(localroot, request.path);
  response.payload = new Message(StatusCode.Ok, browseDir(localroot, localpath), "text/html");
  response.ready = true;
}

void serveForbidden(ref Response response, in Request request) {
  trace("resource is restricted from being accessed");
  response.payload = new Message(StatusCode.Forbidden, format("403 - Access to this resource has been restricted\n"));
  response.ready = true;
}

void notFound(ref Response response) {
  trace("resource not found");
  response.payload = new Message(StatusCode.NotFound, format("404 - The requested path does not exists on disk\n"));
  response.ready = true;
}

unittest {
  custom(0, "FILE", "%s", __FILE__);
}

