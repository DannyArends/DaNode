/** danode/request.d - HTTP request parsing: method, headers, range, CGI environment
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.request;

import danode.imports;

import danode.filesystem : FileSystem, interpreter;
import danode.interfaces : DriverInterface;
import danode.functions : from, parseHtmlDate;
import danode.webconfig : WebConfig;
import danode.post : PostItem, PostType;
import danode.log : log, tag, error, Level;
import danode.multipart : MultipartParser;

// The Request-Method indicates which method is to be performed on the specified resource
enum RequestMethod : string {
  GET = "GET", HEAD = "HEAD", POST = "POST", PUT = "PUT", DELETE = "DELETE", 
  CONNECT = "CONNECT", OPTIONS = "OPTIONS", TRACE = "TRACE"
}

// The HTTP-Version indicates which protocol version is requested to obtain the specified resource
enum HTTPVersion : string { v09 = "HTTP/0.9", v10 = "HTTP/1.0", v11 = "HTTP/1.1", v20 = "HTTP/2", v30 = "HTTP/3" }

// Parse the HTTP-Version, throw an error if it cannot be parsed
@nogc pure HTTPVersion parseHTTPVersion(const string line) nothrow {
  foreach (immutable v; EnumMembers!HTTPVersion) { if (v == line) return(v); }
  return(HTTPVersion.v09);
}

// Parse the Request-Line: "method uri protocol"
pure bool parseRequestLine(ref Request request, const string line) {
  auto parts = line.split(" ");
  if (parts.length < 3) { throw new Exception(format("malformed Request-Line: '%s'", line)); }
  request.method = to!RequestMethod(strip(parts[0]));
  // uri and url start identical; url may be rewritten during routing, uri is preserved as-is
  request.uri = request.url = strip(join(parts[1 .. ($-1)], " "));
  request.protocol = parseHTTPVersion(strip(parts[($-1)]));
  return(true);
}

struct Request {
  string ip; /// IP location of the client
  long port; /// Port at which the client is connected
  string content; /// the content of the HTTP request
  bool isSecure; /// was a secure request made
  bool isValid; /// Is the header valid ?
  UUID id; /// md5UUID for this request
  RequestMethod method; /// requested HTTP method
  string uri = "/"; /// raw URI from the request line, never modified after parsing
  string url = "/"; /// working path used for routing, may be rewritten by canonical/directory redirects
  string dir;  /// original dir path for directory redirects
  HTTPVersion protocol; /// protocol requested
  string[string] headers; /// Associative array holding the header values
  SysTime starttime; /// start time of the Request
  PostItem[string] postinfo; /// Associative array holding the post parameters and values
  bool postParsed = false;
  MultipartParser mpParser;  /// streaming multipart parser
  
  // Start a new Request, and parseHeader on the DriverInterface
  final void initialize(const DriverInterface driver) {
    this.ip = driver.ip;
    this.port = driver.port;
    this.content = driver.content;
    this.isSecure = driver.isSecure;
    this.starttime = Clock.currTime();
    this.id = md5UUID(format("%s:%d-%s", driver.ip, driver.port, starttime));
    this.isValid = this.parseHeader(driver.header);
    log(Level.Verbose, "request: %s to %s from %s:%d - %s", method, uri, this.ip, this.port, this.id);
    log(Level.Trace, "request header: %s", driver.header);
  }

  // Parse the HTTP request header (method, uri, protocol) as well as the supplemental headers
  final bool parseHeader(const string header) {
    try {
      foreach (i, line; header.replace("\r\n", "\n").split("\n")) {
        if (i == 0) {
          this.parseRequestLine(line);
        } else { // next lines: header-param: attribute 
          auto parts = line.split(":");
          if (parts.length > 1) this.headers[strip(parts[0])] = strip(join(parts[1 .. $], ":"));
        }
      }
    } catch (Exception e) { error("parseHeader exception: %s", e.msg); return(false); }
    log(Level.Trace, "headers received: %s", this.headers);
    log(Level.Trace, "parseHeader %s %s %s, nParams: %d", this.method, this.uri, this.protocol, this.headers.length);
    return(true);
  }

  // New input was obtained and / or the driver has been changed, update the driver
  final void update(string content) { this.content = content; }

  // Parse Range header: "bytes=start-end" or "bytes=start-"
  final @property long[2] range() const {
    string r = headers.from("Range");
    if (r.length == 0 || !r.startsWith("bytes=")) return [-1, -1];
    string[] parts = r[6 .. $].split("-");
    try {
      long start = parts[0].length > 0 ? to!long(parts[0]) : 0;
      long end = (parts.length > 1 && parts[1].length > 0) ? to!long(parts[1]) : -1;
      return [start, end];
    } catch (Exception e) { return [-1, -1]; }
  }

  final @property @nogc bool hasRange() const nothrow { return headers.from("Range").startsWith("bytes="); }

  // The Host header requested in the request
  final @property @nogc string host() const nothrow {
    ptrdiff_t i;
    string h = headers.from("Host");
    if (h.startsWith("[")) { // IPv6: [::1]:8080
      i = h.indexOf("]"); return((i > 0)? h[0 .. i+1] : h);
    }
    i = h.indexOf(":"); return((i > 0)? h[0 .. i] : h);
  }

  // The Port from the Host header in the request
  final @property ushort serverport() const {
    ptrdiff_t i;
    string h = headers.from("Host");
    if (h.startsWith("[")) { // IPv6: [::1]:8080
      i = h.indexOf("]:");
      if (i > 0) { return(to!ushort(h[i+2 .. $])); }
      return(isSecure ? to!ushort(443) : to!ushort(80));
    }
    i = h.indexOf(":");
    if (i > 0) { return(to!ushort(h[i+1 .. $])); }
    return(isSecure ? to!ushort(443) : to!ushort(80));
  }

  // Input file generated storing the headers of the request
  final @property string inputfile(in FileSystem filesystem) const {
    return format("%s/%s.in", filesystem.localroot(shorthost()), this.id);
  }

  // Location of a file with name, uploaded by POST request
  final @property string uploadfile(in FileSystem filesystem, in string name) const {
    return format("%s/%s.up", filesystem.localroot(shorthost()), md5UUID(format("%s-%s", this.id, name)));
  }

  // List of filenames uploaded by the user
  final @property string[]  postfiles() const { 
    string[] files;
    foreach (p; postinfo) { if(p.type == PostType.File && p.size > 0) { files ~= p.value; } } 
    return(files);
  }

  // decoded path component of url (post-rewrite)
  final @property @nogc string path() const nothrow { ptrdiff_t i = url.indexOf("?"); if(i > 0){ return(url[0 .. i]); }else{ return(url); } }

  // query string component of uri (pre-rewrite)
  final @property @nogc string query() const nothrow { ptrdiff_t i = uri.indexOf("?"); if(i > 0){ return(uri[i .. $]); }else{ return("?"); } }

  // path component of uri (pre-rewrite, used for canonical redirects)
  final @property @nogc string uripath() const nothrow { ptrdiff_t i = uri.indexOf("?"); if(i > 0){ return(uri[0 .. i]); }else{ return(uri); } }
  final @property @nogc bool keepalive() const nothrow { return(icmp(headers.from("Connection"), "keep-alive") == 0); }
  final @property SysTime ifModified() const { return(parseHtmlDate(headers.from("If-Modified-Since"))); }
  final @property @nogc bool acceptsEncoding(string encoding = "deflate") const nothrow { return(headers.from("Accept-Encoding").canFind(encoding)); }
  final @property @nogc bool track() const nothrow { return(  headers.from("DNT","0") == "0"); }
  final @property @nogc string cookies() const nothrow { return(headers.from("Cookie")); }
  final @property @nogc string useragent() const nothrow { return(headers.from("User-Agent", "Unknown")); }
  final @property @nogc string ifNoneMatch() const nothrow { return headers.from("If-None-Match"); }
  final @nogc string shorthost() const nothrow { return host.startsWith("www.") ? host[4 .. $] : host; }
  final string[] command(string localpath) const {
    import std.path : dirName;
    string interp = localpath.interpreter();
    if (interp.length == 0) return [localpath];
    string[] cmd = interp.split(" ");
    if (cmd[0] == "php-cgi") {
      string daroot = dirName(dirName(dirName(localpath)));
      cmd ~= ["-d", "include_path=.:" ~ daroot];
    }
    return cmd ~ localpath;
  }

  final string[string] environ(string localpath) const {
    string[string] env;
    env["REQUEST_METHOD"] = to!string(method);
    env["QUERY_STRING"] = query.length > 1 ? query[1 .. $] : "";
    env["REQUEST_URI"] = decodeComponent(uripath);
    env["SCRIPT_FILENAME"] = localpath;
    env["SCRIPT_NAME"] = path;
    env["SERVER_PROTOCOL"] = cast(string)protocol;
    env["REMOTE_ADDR"] = ip;
    env["REMOTE_PORT"] = to!string(port);
    env["HTTP_HOST"] = host;
    env["HTTPS"] = isSecure ? "on" : "";
    env["REDIRECT_STATUS"] = "200";
    env["PATH"] = environment.get("PATH", "");
    foreach (k, v; headers) { env["HTTP_" ~ k.toUpper().replace("-", "_")] = v; }
    return env;
  }

  // Canonical redirect of the Request for a directory to the index page specified in the WebConfig
  final void redirectdir(in WebConfig config) {
    this.dir = this.path()[1..$];
    if(config.redirectdir() && config.redirect) { this.url = config.index; }
  }

  // Clear all files uploaded by the user after the Request is done
  final void clearUploadFiles() const {
    foreach(f; postfiles) { if(exists(f)) {
      log(Level.Verbose, "Removing uploaded file at %s", f); 
      remove(f);
    } }
  }
}

unittest {
  tag(Level.Always, "FILE", "%s", __FILE__);

  // parseHTTPVersion
  assert(parseHTTPVersion("HTTP/1.1") == HTTPVersion.v11, "HTTP/1.1 must parse");
  assert(parseHTTPVersion("HTTP/1.0") == HTTPVersion.v10, "HTTP/1.0 must parse");
  assert(parseHTTPVersion("HTTP/2")   == HTTPVersion.v20, "HTTP/2 must parse");
  assert(parseHTTPVersion("garbage")  == HTTPVersion.v09, "invalid must return v09");
  assert(parseHTTPVersion("")         == HTTPVersion.v09, "empty must return v09");

  // parseRequestLine
  Request r;
  assert(parseRequestLine(r, "GET /index.html HTTP/1.1"), "valid request line must parse");
  assert(r.method == RequestMethod.GET, "method must be GET");
  assert(r.uri == "/index.html", "uri must be /index.html");
  assert(r.protocol == HTTPVersion.v11, "protocol must be HTTP/1.1");

  // uri with query string
  Request r2;
  assert(parseRequestLine(r2, "GET /search?q=hello HTTP/1.1"), "uri with query must parse");
  assert(r2.uri == "/search?q=hello", "uri must include query string");
  assert(r2.path == "/search", "path must strip query string");
  assert(r2.query == "?q=hello", "query must include ?");

  // shorthost
  Request r3;
  r3.headers["Host"] = "www.example.com";
  assert(r3.shorthost() == "example.com", "www. must be stripped");
  assert(r3.host == "www.example.com", "host must strip www.");

  Request r4;
  r4.headers["Host"] = "example.com";
  assert(r4.shorthost() == "example.com", "shorthost without www. must be unchanged");

  // host with port
  Request r5;
  r5.headers["Host"] = "example.com:8080";
  assert(r5.host == "example.com", "host must strip port");
  assert(r5.serverport() == 8080, "serverport must return 8080");

  // range parsing
  Request r6;
  r6.headers["Range"] = "bytes=0-1023";
  assert(r6.hasRange, "hasRange must be true");
  assert(r6.range()[0] == 0, "range start must be 0");
  assert(r6.range()[1] == 1023, "range end must be 1023");

  Request r7;
  r7.headers["Range"] = "bytes=512-";
  assert(r7.range()[0] == 512, "open range start must be 512");
  assert(r7.range()[1] == -1, "open range end must be -1");

  // keepalive
  Request r8;
  r8.headers["Connection"] = "keep-alive";
  assert(r8.keepalive, "keep-alive must be detected");

  Request r9;
  r9.headers["Connection"] = "Close";
  assert(!r9.keepalive, "Close must not be keepalive");

  // acceptsEncoding
  Request r10;
  r10.headers["Accept-Encoding"] = "gzip, deflate";
  assert(r10.acceptsEncoding("deflate"), "deflate must be accepted");
  assert(!r10.acceptsEncoding("br"), "br must not be accepted");

  Request r11;
  r11.headers["Range"] = "bytes=abc-def";
  assert(r11.range() == [-1, -1], "malformed range must return [-1, -1]");

  Request r_ipv6;
  r_ipv6.headers["Host"] = "[::1]:8080";
  assert(r_ipv6.host == "[::1]", "IPv6 host must include brackets");
  assert(r_ipv6.serverport() == 8080, "IPv6 port must be 8080");

  Request r_ipv6b;
  r_ipv6b.headers["Host"] = "[::1]";
  assert(r_ipv6b.host == "[::1]", "IPv6 without port must return host");
  assert(r_ipv6b.serverport() == 80, "IPv6 without port must return default");
}
