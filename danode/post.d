/** danode/post.d - HTTP POST parsing: form data, multipart, file uploads
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.post;

import danode.imports;

import danode.cgi : CGI;
import danode.statuscode : StatusCode;
import danode.interfaces : StringDriver;
import danode.request : Request, RequestMethod;
import danode.response : Response, setPayload;
import danode.webconfig : WebConfig;
import danode.mimetypes : mime;
import danode.filesystem : FileSystem;
import danode.functions : from, writeFile, parseQueryString;
import danode.log : log, tag, error, Level;
import danode.webconfig : serverConfig;

immutable string      MPHEADER         = "multipart/form-data";                     /// Multipart header id
immutable string      XFORMHEADER      = "application/x-www-form-urlencoded";       /// X-form header id
immutable string      JSON             = "application/json"; /// json input
enum PostType { Input, File };

struct PostItem {
  PostType  type;
  string    name;
  string    filename;
  string    value;
  string    mime = "post/input";
  long      size = 0;
}

// Parse the POST request data from the client, or waits (returning false) for more data 
// when the entire request body is not yet available. POST data supplied in Multipart 
// and X-form post formats are currently supported
final bool parsePost(ref Request request, ref Response response, in FileSystem filesystem) {
  if (response.havepost || request.method != RequestMethod.POST) { return(response.havepost = true); }

  long expectedlength;
  try {
    expectedlength = to!long(request.headers.from("Content-Length", "0"));
  } catch (Exception e) {
    return(response.setPayload(StatusCode.BadRequest, "400 - Bad Request\n", "text/plain"));
  }
  string content = request.body;
  if (expectedlength == 0) {
    log(Level.Trace, "Post: [T] Content-Length not specified (or 0), length: %s", content.length);
    return(response.havepost = true); // When we don't receive any post data it is meaningless to scan for any content
  } else if (expectedlength > serverConfig.get("max_request_size", 2   * 1024 * 1024)) {
    log(Level.Verbose, "Post: [W] Upload too large: %d bytes from %s", expectedlength, request.ip);
    return(response.setPayload(StatusCode.PayloadTooLarge, "413 - Payload Too Large\n", "text/plain"));
  }
  log(Level.Trace, "Post: [T] Received %s of %s", content.length, expectedlength);
  if(content.length < expectedlength) return(false);

  string contenttype = from(request.headers, "Content-Type");
  log(Level.Trace, "content type: %s", contenttype);

  if (contenttype.indexOf(XFORMHEADER) >= 0) {
    log(Level.Verbose, "XFORM: [I] parsing %d bytes", expectedlength);
    request.parseXform(content);
    log(Level.Verbose, "XFORM: [T] # of items: %s", request.postinfo.length);
  } else if (contenttype.indexOf(MPHEADER) >= 0) {
    auto parts = split(contenttype, "boundary=");
    if (parts.length < 2) return(response.havepost = true);
    string mpid = parts[1];
    log(Level.Verbose, "MPART: [I] header: %s, parsing %d bytes", mpid, expectedlength);
    request.parseMultipart(filesystem, content, mpid);
    log(Level.Verbose, "MPART: [I] # of items: %s", request.postinfo.length);
  } else if (contenttype.indexOf(JSON) >= 0) {
    log(Level.Verbose, "JSON: [I] Parsing %d bytes", expectedlength);
    //request.postinfo["php://input"] = PostItem(PostType.File, "stdin", "php://input", content, JSON, content.length);
  } else {
    error("parsePost: Unsupported POST content type: %s [%s] -> %s", contenttype, expectedlength, content);
    request.parseXform(content);
  }
  return(response.havepost = true);
}

// Parse X-form content in the body of the request
final void parseXform(ref Request request, const string content) {
  foreach (k, v; parseQueryString(content)) { request.postinfo[k] = PostItem(PostType.Input, k, "", v); }
}

// Extract value from: name="value" or filename="value"
pure string extractQuoted(string s, string key) nothrow {
  ptrdiff_t i = s.indexOf(key ~ "=\"");
  if (i < 0) return "";
  i += key.length + 2;
  ptrdiff_t j = s.indexOf("\"", i);
  return j > i ? s[i .. j] : "";
}

@nogc pure ptrdiff_t findBodyLine(in string[] lines) nothrow {
  foreach (i, line; lines) { if (strip(line).length == 0) return i + 1; }
  return -1;
}

// Parse Multipart content in the body of the request
final void parseMultipart(ref Request request, in FileSystem filesystem, const string content, const string mpid) {
  int[string] keys;
  foreach (part; chomp(content).split(mpid)) {
    string[] elem = strip(part).split("\r\n");
    if (elem.length < 2 || elem[0] == "--") { 
      log(Level.Verbose, "MPART: [I] ID element: %s", elem.length > 0 ? elem[0] : ""); continue; 
    }

    string[] mphdr = elem[0].split("; ");
    if (mphdr.length < 2) continue;

    string key = extractQuoted(elem[0], "name");
    if (key.length == 0) continue;

    ptrdiff_t bodyLine = findBodyLine(elem);
    if (bodyLine < 0 || bodyLine >= elem.length) continue;

    if (mphdr.length == 2) {
      request.postinfo[key] = PostItem(PostType.Input, key, "", join(elem[bodyLine .. ($-1)]));
    } else if (mphdr.length >= 3) {
      string fname = extractQuoted(elem[0], "filename");
      log(Level.Verbose, "MPART: [I] found on key %s file %s", key, fname);
      bool isarraykey = key.length > 2 && key[($-2) .. $] == "[]";
      keys[key] = keys.get(key, -1) + 1;
      log(Level.Verbose, "MPART: [I] found on key %s #%d file %s", key, keys[key], fname);
      if (fname != "") {
        string fkey      = isarraykey ? key ~ to!string(keys[key]) : key;
        string skey      = isarraykey ? key[0 .. $-2] : key;
        string localpath = request.uploadfile(filesystem, fkey);
        string mpcontent = join(elem[bodyLine .. ($-1)], "\r\n");
        auto mimeParts   = split(elem[bodyLine-1], ": ");
        string fileMime  = mimeParts.length >= 2 ? mimeParts[1] : "application/octet-stream";
        request.postinfo[fkey] = PostItem(PostType.File, skey, fname, localpath, fileMime, mpcontent.length);
        localpath.writeFile(mpcontent);
        log(Level.Verbose, "MPART: [I] Wrote %d bytes to file %s", mpcontent.length, localpath);
      } else { request.postinfo[key] = PostItem(PostType.Input, key, ""); }
    }
  }
}

/* The serverAPI functions prepares and writes out the input file for external process execution
   The inputfile contains the SERVER, COOKIES, POST, and FILES information that can be used by the external script
   This data is picked-up by the different CGI APIs, and presented to the client in the regular way */
final void serverAPI(in FileSystem filesystem, in WebConfig config, in Request request, in Response response)  {
  Appender!(string) content;
  content.put(format("S=REDIRECT_STATUS=%d\n", (response.payload)? response.payload.statuscode.code : 200));

  // Give HTTP_COOKIES to CGI
  foreach (c; request.cookies.split("; ")) { content.put(format("C=%s\n", chomp(c)) ); }
  content.put(format("S=SERVER_SOFTWARE=%s\n", serverConfig.get("serverinfo", "DaNode/0.0.3")));
  try{
    content.put(format("S=SERVER_NAME=%s\n", (response.address)? response.address.toHostNameString() : "localhost"));
  }catch(Exception e){
    error("Exception while trying to call: toHostNameString()");
    content.put("S=SERVER_NAME=localhost\n");
  }
  content.put(format("S=SERVER_ADDR=%s\n", (response.address)? response.address.toAddrString() : "127.0.0.1"));
  content.put(format("S=SERVER_PORT=%s\n", (response.address)? response.address.toPortString() : "80"));
  content.put(format("S=DOCUMENT_ROOT=%s\n", filesystem.localroot(request.shorthost())));
  content.put(format("S=GATEWAY_INTERFACE=%s\n", "CGI/1.1"));
  content.put(format("S=PHP_SELF=%s\n", request.path));
  content.put(format("S=REQUEST_TIME=%s\n", request.starttime.toUnixTime));

  // This is DaNode specific
  content.put(format("S=REQUEST_DIR=%s\n", request.dir));

  // Write the post information we received
  foreach (p; request.postinfo) {
    if(p.type == PostType.Input)  content.put(format("P=%s=%s\n", p.name, p.value));
    if(p.type == PostType.File)   content.put(format("F=%s=%s=%s=%s\n", p.name, p.filename, p.mime, p.value));
  }

  string fIn = request.inputfile(filesystem);
  log(Level.Trace, "API: [T] [IN %s]\n%s[/IN %s]", fIn, content.data, fIn);
  fIn.writeFile(content.data);
}

unittest {
  import danode.router : Router, runRequest;

  tag(Level.Always, "FILE", "%s", __FILE__);

  FileSystem fs = new FileSystem("./www/");

  // extractQuoted
  assert(extractQuoted("name=\"hello\"", "name") == "hello",            "extractQuoted must get name");
  assert(extractQuoted("filename=\"test.txt\"", "filename") == "test.txt", "extractQuoted must get filename");
  assert(extractQuoted("name=\"\"", "name") == "",                      "extractQuoted empty value");
  assert(extractQuoted("nothing here", "name") == "",                   "extractQuoted missing key");

  // findBodyLine
  assert(findBodyLine(["Content-Disposition: form-data", "", "value"]) == 2, "findBodyLine must find blank line");
  assert(findBodyLine(["Content-Disposition: form-data"]) == -1,             "findBodyLine no blank must return -1");

  // parseXform via runRequest
  auto router = new Router("./www/", Address.init);
  StringDriver res;

  // POST with xform body
  string fmtXform = "POST /dmd.d HTTP/1.1\nHost: localhost\nContent-Type: application/x-www-form-urlencoded\nContent-Length: %d\n\n%s";
  string smallbody = "name=danny&age=42&city=amsterdam";
  res = router.runRequest(format(fmtXform, smallbody.length, smallbody));
  assert(res.lastStatus == StatusCode.Ok, format("POST xform expected 200, got %d", res.lastStatus.code));

  // POST too large
  string bigbody = "x".replicate(1024 * 1024 * 3); // 3MB
  res = router.runRequest(format(fmtXform, bigbody.length, bigbody));
  assert(res.lastStatus == StatusCode.PayloadTooLarge, format("POST too large expected 413, got %d", res.lastStatus.code));
}
