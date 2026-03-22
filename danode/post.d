/** danode/post.d - HTTP POST parsing: form data, multipart, file uploads
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.post;

import danode.imports;

import danode.cgi : CGI;
import danode.statuscode : StatusCode;
import danode.interfaces : StringDriver, DriverInterface;
import danode.request : Request, RequestMethod, PostItem, PostType;
import danode.response : Response, setPayload;
import danode.webconfig : WebConfig;
import danode.mimetypes : mime;
import danode.filesystem : FileSystem, writeFile;
import danode.functions : from, parseQueryString;
import danode.log : log, tag, error, Level;
import danode.webconfig : serverConfig;
import danode.multipart : MultipartParser;

immutable string MPHEADER = "multipart/form-data";                    /// Multipart header mime
immutable string XFORMHEADER = "application/x-www-form-urlencoded";   /// X-form header mime

// Parse the POST request data from the client, or waits (returning false) for more data 
// when the entire request body is not yet available. POST data supplied in Multipart 
// and X-form post formats are currently supported
final bool parsePost(ref Request request, ref Response response, in FileSystem filesystem, DriverInterface driver = null) {
  if (request.postParsed || request.method != RequestMethod.POST) { return(request.postParsed = true); }

  long expectedlength;
  try {
    expectedlength = to!long(request.headers.from("Content-Length", "0"));
  } catch (Exception e) { return(response.setPayload(StatusCode.BadRequest, "400 - Bad Request\n", "text/plain")); }

  string contenttype = from(request.headers, "Content-Type");
  size_t limit = (contenttype.indexOf("multipart/") >= 0)? serverConfig.maxUploadSize : serverConfig.maxRequestSize;

  if (expectedlength == 0) { return(request.postParsed = true); }
  if (expectedlength > limit) {
    log(Level.Verbose, "Post: [W] Upload too large: %d bytes from %s", expectedlength, request.ip);
    return(response.setPayload(StatusCode.PayloadTooLarge, "413 - Payload Too Large\n", "text/plain"));
  }

  if (contenttype.indexOf(MPHEADER) >= 0) {
    auto parts = split(contenttype, "boundary=");
    if (parts.length < 2) return(request.postParsed = true);
    if (!request.mpParser.isActive) {
      string mpid = "--" ~ parts[1];
      request.mpParser = MultipartParser(mpid, filesystem.localroot(request.shorthost()) ~ "/");
      log(Level.Verbose, "MPART: [I] streaming mode activated, boundary: %s", mpid);
    }
    if (driver !is null) {
      auto chunk = driver.receiveChunk();
      if (chunk.length > 0 && request.mpParser.feed(request, chunk)) return(request.postParsed = true);
      return false;
    }
  }

  // Non-multipart: wait for full body as before
  log(Level.Trace, "Post: [T] Received %s of %s", request.content.length, expectedlength);
  if(request.content.length < expectedlength) return(false);

  if (contenttype.indexOf(XFORMHEADER) >= 0) {
    request.parseXform(request.content);
  } else if (contenttype.indexOf(mime(".json")) >= 0) {
    log(Level.Verbose, "JSON: [I] passing %d bytes raw to script", expectedlength);
  } else {
    error("parsePost: Unsupported POST content type: %s [%s]", contenttype, expectedlength);
    request.parseXform(request.content);
  }
  return(request.postParsed = true);
}

// Parse X-form content in the body of the request
final void parseXform(ref Request request, const string content) {
  foreach (k, v; parseQueryString(content)) { request.postinfo[k] = PostItem(PostType.Input, k, "", v); }
}

@nogc pure ptrdiff_t findBodyLine(in string[] lines) nothrow {
  foreach (i, line; lines) { if (strip(line).length == 0) return i + 1; }
  return -1;
}

/* The serverAPI functions prepares and writes out the input file for external process execution
   The inputfile contains the SERVER, COOKIES, POST, and FILES information that can be used by the external script
   This data is picked-up by the different CGI APIs, and presented to the client in the regular way */
final void serverAPI(in FileSystem filesystem, in WebConfig config, in Request request, in Response response)  {
  Appender!(string) content;
  content.put(format("S=REDIRECT_STATUS=%d\n", (response.payload !is null)? response.payload.statuscode.code : 200));

  // Give HTTP_COOKIES to CGI
  foreach (c; request.cookies.split("; ")) { content.put(format("C=%s\n", chomp(c)) ); }
  content.put(format("S=SERVER_SOFTWARE=%s\n", serverConfig.get("serverinfo", "DaNode/0.0.3")));
  try{
    content.put(format("S=SERVER_NAME=%s\n", (response.address !is null)? response.address.toHostNameString() : "localhost"));
  }catch(Exception e){
    error("Exception while trying to call: toHostNameString()");
    content.put("S=SERVER_NAME=localhost\n");
  }
  content.put(format("S=SERVER_ADDR=%s\n", (response.address !is null)? response.address.toAddrString() : "127.0.0.1"));
  content.put(format("S=SERVER_PORT=%s\n", (response.address !is null)? response.address.toPortString() : "80"));
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

  // findBodyLine
  assert(findBodyLine(["Content-Disposition: form-data", "", "value"]) == 2, "findBodyLine must find blank line");
  assert(findBodyLine(["Content-Disposition: form-data"]) == -1, "findBodyLine no blank must return -1");

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
