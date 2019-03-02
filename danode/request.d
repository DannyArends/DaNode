module danode.request;

import danode.imports;
import danode.filesystem : FileSystem;
import danode.interfaces : ClientInterface, DriverInterface;
import danode.functions : interpreter, from, toD, monthToIndex;
import danode.webconfig : WebConfig;
import danode.post : PostItem, PostType;
import danode.log : custom, info, trace, warning;

SysTime parseHtmlDate(const string datestr){ // 21 Apr 2014 20:20:13 CET
  SysTime ts =  SysTime(DateTime(-7, 1, 1, 1, 0, 0));
  auto dateregex = regex(r"([0-9]{1,2}) ([a-z]{1,3}) ([0-9]{4}) ([0-9]{1,2}):([0-9]{1,2}):([0-9]{1,2}) cet", "g");
  auto m = match(datestr.toLower(), dateregex);
  if(m.captures.length == 7){
    ts = SysTime(DateTime(to!int(m.captures[3]), monthToIndex(m.captures[2]), to!int(m.captures[1]),        // 21 Apr 2014
                          to!int(m.captures[4]), to!int(m.captures[5]), to!int(m.captures[6])));    // 20:20:13
  }
  return(ts);
}

struct Request {
  UUID              requestid; ///md5UUID for this request
  DriverInterface   driver; /// DriverInterface associated with the Request object
  string            method = "GET"; /// requested HTTP method (GET, POST, HEAD)
  string            uri = "/"; /// uri requested
  string            url = "/"; /// url requested
  string            page; /// page is used when redirecting
  string            dir; /// dir is used in directory redirection
  string            protocol = "HTTP/1.1"; /// protocol requested
  string[string]    headers; /// Associative array holding the header values
  SysTime           starttime; /// start time of the Request
  PostItem[string]  postinfo;  /// Associative array holding the post parameters and values

  // Start a new Request, and parseHeader on the DriverInterface
  final void parse(DriverInterface driver) {
    this.driver = driver;
    this.starttime = Clock.currTime();
    this.requestid = md5UUID(format("%s:%d-%s", driver.ip, driver.port, starttime));
    parseHeader(driver.header);
    info("request: %s to %s from %s:%d - %s", method, uri, driver.ip, driver.port, requestid);
    trace("request header: %s", driver.header);
  }

  // Parse the HTML request header (method, uri, protocol) as well as the supplemental headers
  final void parseHeader(in string header) {
    string[] parts;
    foreach(i, line; header.split("\n")){
      if(i == 0) {                    // first line: method uri protocol
        parts = line.split(" ");
        if(parts.length >= 3) {
          this.method = strip(parts[0]);
          this.uri = this.url = strip(join(parts[1 .. ($-1)], " "));
          this.protocol = strip(parts[($-1)]);
        } else {
          warning("could not decode header line for client");
        }
      } else {                        // next lines: header-param: attribute 
        parts = line.split(":");
        if(parts.length > 1) this.headers[strip(parts[0])] = strip(join(parts[1 .. $], ":"));
      }
    }
  }

  // New input was obtained and / or the driver has been changed, update the driver
  final void update(DriverInterface driver) { this.driver = driver; }

  // The Host header requested in the request
  final @property string host() const { 
    ptrdiff_t i = headers.from("Host").indexOf(":");
    if(i > 0) return(headers.from("Host")[0 .. i]);
    return(headers.from("Host")); 
  }

  // The Post from the Host header in the request
  final @property ushort serverport() const {
    ptrdiff_t i = headers.from("Host").indexOf(":");
    if(i > 0){ return( to!ushort(headers.from("Host")[(i+1) .. $])); } 
    return(to!ushort(80));
  }

  // Input file generated storing the headers of the request
  final @property string inputfile(in FileSystem filesystem) const {
    return format("%s/%s.in", filesystem.localroot(shorthost()), this.requestid);
  }

  // Location of a file with name, uploaded by POST request
  final @property string uploadfile(in FileSystem filesystem, in string name) const {
    return format("%s/%s.up", filesystem.localroot(shorthost()), md5UUID(format("%s:%d-%s-%s", driver.ip, driver.port, starttime, name)));
  }

  // Get parameters as associative array
  final string[string] get() const {
    string[string] params;
    foreach(param; query[1 .. $].split("&")){ string[] elems = param.split("="); if(elems.length == 1){ elems ~= "TRUE"; } params[elems[0]] = elems[1]; }
    return params;
  }

  // List of filenames uploaded by the user
  final @property string[]  postfiles() const { 
    string[] files;
    foreach (p; postinfo) {
      if(p.type == PostType.File && p.size > 0) files ~= p.value;
    } 
    return(files);
  }

  final @property string    path() const { ptrdiff_t i = url.indexOf("?"); if(i > 0){ return(url[0 .. i]); }else{ return(url); } }
  final @property string    query() const { ptrdiff_t i = uri.indexOf("?"); if(i > 0){ return(uri[i .. $]); }else{ return("?"); } }
  final @property string    uripath() const { ptrdiff_t i = uri.indexOf("?"); if(i > 0){ return(uri[0 .. i]); }else{ return(uri); } }
  final @property bool      keepalive() const { return( toLower(headers.from("Connection")) == "keep-alive"); }
  final @property SysTime   ifModified() const { return(parseHtmlDate(headers.from("If-Modified-Since"))); }
  final @property bool      acceptsEncoding(string encoding = "deflate") const { return(headers.from("Accept-Encoding").canFind(encoding)); }
  final @property bool      track() const { return(  headers.from("DNT","0") == "0"); }
  final @property string    params() const { Appender!string str; foreach(k; get.byKey()){ str.put(format(" \"%s=%s\"", k, get[k])); } return(str.data); }
  final @property string    cookies() const { return(headers.from("Cookie")); }
  final @property string    useragent() const { return(headers.from("User-Agent", "Unknown")); }
  final string              shorthost() const { return( (host.indexOf("www.") >= 0)? host[4 .. $] : host ); }
  final string              command(string localpath) const { return(format("%s %s%s", localpath.interpreter(), localpath, params())); }

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

