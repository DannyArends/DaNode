module danode.request;

import danode.imports;
import danode.filesystem : FileSystem;
import danode.interfaces : ClientInterface, DriverInterface;
import danode.functions : interpreter, from, parseHtmlDate, parseQueryString, shellEscape;
import danode.webconfig : WebConfig;
import danode.http : HTTP;
import danode.post : PostItem, PostType;
import danode.log : custom, info, trace, warning;

// The Request-Method indicates which method is to be performed on the specified resource
enum RequestMethod : string {
  GET = "GET", HEAD = "HEAD", POST = "POST", PUT = "PUT", DELETE = "DELETE", 
  CONNECT = "CONNECT", OPTIONS = "OPTIONS", TRACE = "TRACE"
}

// The HTTP-Version indicates which protocol version is requested to obtain the specified resource
enum HTTPVersion : string {
  v09 = "HTTP/0.9", v10 = "HTTP/1.0", v11 = "HTTP/1.1", v20 = "HTTP/2", v30 = "HTTP/3"
}

// Parse the HTTP-Version, throw an error if it cannot be parsed
pure HTTPVersion parseHTTPVersion(const string line) {
  foreach (immutable v; EnumMembers!HTTPVersion) {
    if (v == line) return(v);
  }
  throw new Exception(format("invalid HTTP-Version requested: %s", line));
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
  string body; /// the body of the HTTP request
  bool isSecure; /// was a secure request made
  bool isValid; /// Is the header valid ?
  UUID id; /// md5UUID for this request
  RequestMethod method; /// requested HTTP method
  string uri = "/"; /// raw URI from the request line, never modified after parsing
  string url = "/"; /// working path used for routing, may be rewritten by canonical/directory redirects
  string page; /// page is used when performing a canonical redirect
  string dir; /// dir is used in directory redirection
  HTTPVersion protocol; /// protocol requested
  string[string] headers; /// Associative array holding the header values
  SysTime starttime; /// start time of the Request
  PostItem[string] postinfo;  /// Associative array holding the post parameters and values
  long maxtime;  /// Maximum time in ms before the request is discarded

  // Start a new Request, and parseHeader on the DriverInterface
  final void initialize(const DriverInterface driver, long maxtime = 4500) {
    this.ip = driver.ip;
    this.port = driver.port;
    this.body = driver.body;
    this.isSecure = driver.isSecure;
    this.starttime = Clock.currTime();
    this.maxtime = maxtime;
    this.id = md5UUID(format("%s:%d-%s", driver.ip, driver.port, starttime));
    this.isValid = this.parseHeader(driver.header);
    info("request: %s to %s from %s:%d - %s", method, uri, this.ip, this.port, this.id);
    trace("request header: %s", driver.header);
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
    } catch (Exception e) {
      warning("parseHeader exception: %s", e.msg);
      return(false);
    }
    trace("parseHeader %s %s %s, nParams: %d", this.method, this.uri, this.protocol, this.headers.length);
    return(true);
  }

  // New input was obtained and / or the driver has been changed, update the driver
  final void update(string body) { this.body = body; }

  // Parse Range header: "bytes=start-end" or "bytes=start-"
  final @property long[2] range() const {
    string r = headers.from("Range");
    if (r.length == 0 || !r.startsWith("bytes=")) return [-1, -1];
    string[] parts = r[6 .. $].split("-");
    long start = parts[0].length > 0 ? to!long(parts[0]) : 0;
    long end = (parts.length > 1 && parts[1].length > 0) ? to!long(parts[1]) : -1;
    return [start, end];
  }

  final @property bool hasRange() const { return headers.from("Range").startsWith("bytes="); }

  // The Host header requested in the request
  final @property string host() const { 
    ptrdiff_t i = headers.from("Host").indexOf(":");
    if (i > 0) {
      return(headers.from("Host")[0 .. i]);
    }
    return(headers.from("Host")); 
  }

  // The Port from the Host header in the request
  final @property ushort serverport() const {
    ptrdiff_t i = headers.from("Host").indexOf(":");
    if (i > 0) { 
      return( to!ushort(headers.from("Host")[(i+1) .. $]));
    }
    return(isSecure ? to!ushort(443) : to!ushort(80)); // return the default ports
  }

  // Input file generated storing the headers of the request
  final @property string inputfile(in FileSystem filesystem) const {
    return format("%s/%s.in", filesystem.localroot(shorthost()), this.id);
  }

  // Location of a file with name, uploaded by POST request
  final @property string uploadfile(in FileSystem filesystem, in string name) const {
    return format("%s/%s.up", filesystem.localroot(shorthost()), md5UUID(format("%s-%s", this.id, name)));
  }

  // Get parameters as associative array
  final string[string] get() const { return parseQueryString(query[1 .. $], "TRUE"); }

  // List of filenames uploaded by the user
  final @property string[]  postfiles() const { 
    string[] files;
    foreach (p; postinfo) {
      if(p.type == PostType.File && p.size > 0) files ~= p.value;
    } 
    return(files);
  }

  // decoded path component of url (post-rewrite)
  final @property string path() const { ptrdiff_t i = url.indexOf("?"); if(i > 0){ return(url[0 .. i]); }else{ return(url); } }

  // query string component of uri (pre-rewrite)
  final @property string query() const { ptrdiff_t i = uri.indexOf("?"); if(i > 0){ return(uri[i .. $]); }else{ return("?"); } }

  // path component of uri (pre-rewrite, used for canonical redirects)
  final @property string uripath() const { ptrdiff_t i = uri.indexOf("?"); if(i > 0){ return(uri[0 .. i]); }else{ return(uri); } }
  final @property bool keepalive() const { return( toLower(headers.from("Connection")) == "keep-alive"); }
  final @property SysTime ifModified() const { return(parseHtmlDate(headers.from("If-Modified-Since"))); }
  final @property bool acceptsEncoding(string encoding = "deflate") const { return(headers.from("Accept-Encoding").canFind(encoding)); }
  final @property bool track() const { return(  headers.from("DNT","0") == "0"); }
  final @property string cookies() const { return(headers.from("Cookie")); }
  final @property string useragent() const { return(headers.from("User-Agent", "Unknown")); }
  final string shorthost() const { return( (host.indexOf("www.") >= 0)? host[4 .. $] : host ); }
  final string[] command(string localpath) const {
    string[] args = [localpath.interpreter(), localpath];
    foreach(k; get.byKey()) { args ~= shellEscape(k ~ "=" ~ get[k]); }
    return(args);
  }
  final @property string    params() const {
      Appender!string str; 
      foreach(k; get.byKey()){ str.put(format(" %s", shellEscape(k ~ "=" ~ get[k]))); }
      return(str.data); 
  }

  // Canonical redirect of the Request for a directory to the index page specified in the WebConfig
  final void redirectdir(in WebConfig config) {
    if(config.redirectdir() && config.redirect){
      this.dir = this.path()[1..$]; // We need to redirect, so save the path to this.dir
      this.url = config.index;
    }
  }

  // Clear all files uploaded by the user after the Request is done
  final void clearUploadFiles() const {
    foreach(f; postfiles) { if(exists(f)) {
      trace("removing uploaded file at %s", f); 
      remove(f);
    } }
  }
}

unittest {
  custom(0, "FILE", "%s", __FILE__);
}
