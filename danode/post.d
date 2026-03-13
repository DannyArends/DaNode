module danode.post;

import danode.imports;
import danode.cgi : CGI;
import danode.client : MAX_REQUEST_SIZE;
import danode.statuscode : StatusCode;
import danode.request : Request;
import danode.response : SERVERINFO, Response, redirect, create, notmodified;
import danode.webconfig : WebConfig;
import danode.payload : Message;
import danode.mimetypes : mime;
import danode.filesystem : FileSystem;
import danode.functions : from, has, isCGI, isFILE, isDIR, writeinfile, parseQueryString;
import danode.log : info, custom, trace, warning;

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
final bool parsePost (ref Request request, ref Response response, in FileSystem filesystem) {
  if (response.havepost || request.method != "POST") {
    response.havepost = true;
    return(true);
  }
  long expectedlength = to!long(from(request.headers, "Content-Length", "0"));
  string content = request.body;
  if (expectedlength == 0) {
    custom(2, "POST", "Content-Length was not specified or 0: real length: %s", content.length);
    response.havepost = true;
    return(true); // When we don't receive any post data it is meaningless to scan for any content
  } else if (expectedlength > MAX_REQUEST_SIZE) {
    warning("Upload too large: %d bytes from %s", expectedlength, request.ip);
    response.payload = new Message(StatusCode.PayloadTooLarge, "413 - Payload Too Large\n");
    response.ready = true;
    response.havepost = true;
    return(true);
  }
  custom(2, "POST", "received %s of %s", content.length, expectedlength);
  if(content.length < expectedlength) return(false);

  string contenttype = from(request.headers, "Content-Type");
  custom(2, "POST", "content type: %s", contenttype);

  if (contenttype.indexOf(XFORMHEADER) >= 0) {
    custom(0, "XFORM", "parsing %d bytes", expectedlength);
    request.parseXform(content);
    custom(1, "XFORM", "# of items: %s", request.postinfo.length);
  } else if (contenttype.indexOf(MPHEADER) >= 0) {
    auto parts = split(contenttype, "boundary=");
    if (parts.length < 2) return response.havepost = true;
    string mpid = parts[1];
    custom(1, "MPART", "header: %s, parsing %d bytes", mpid, expectedlength);
    request.parseMultipart(filesystem, content, mpid);
    custom(1, "MPART", "# of items: %s", request.postinfo.length);
  } else if (contenttype.indexOf(JSON) >= 0) {
    custom(0, "JSONP", "parsing %d bytes", expectedlength);
    //request.postinfo["php://input"] = PostItem(PostType.File, "stdin", "php://input", content, JSON, content.length);
  } else {
    warning("unsupported POST content type: %s [%s] -> %s", contenttype, expectedlength, content);
    request.parseXform(content);
  }
  response.havepost = true;
  return(response.havepost);
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

pure ptrdiff_t findBodyLine(in string[] lines) nothrow {
  foreach (i, line; lines) { if (strip(line).length == 0) return i + 1; }
  return -1;
}

// Parse Multipart content in the body of the request
final void parseMultipart(ref Request request, in FileSystem filesystem, const string content, const string mpid) {
  int[string] keys;
  foreach (part; chomp(content).split(mpid)) {
    string[] elem = strip(part).split("\r\n");
    if (elem.length < 2 || elem[0] == "--") { custom(1, "MPART", "ID element: %s", elem.length > 0 ? elem[0] : ""); continue; }

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
      custom(1, "MPART", "found on key %s file %s", key, fname);
      bool isarraykey = key.length > 2 && key[($-2) .. $] == "[]";
      keys[key] = keys.get(key, -1) + 1;
      custom(1, "MPART", "found on key %s #%d file %s", key, keys[key], fname);
      if (fname != "") {
        string fkey      = isarraykey ? key ~ to!string(keys[key]) : key;
        string skey      = isarraykey ? key[0 .. $-2] : key;
        string localpath = request.uploadfile(filesystem, fkey);
        string mpcontent = join(elem[bodyLine .. ($-1)], "\r\n");
        auto mimeParts   = split(elem[bodyLine-1], ": ");
        string fileMime  = mimeParts.length >= 2 ? mimeParts[1] : "application/octet-stream";
        request.postinfo[fkey] = PostItem(PostType.File, skey, fname, localpath, fileMime, mpcontent.length);
        writeinfile(localpath, mpcontent);
        custom(1, "MPART", "wrote %d bytes to file %s", mpcontent.length, localpath);
      } else { request.postinfo[key] = PostItem(PostType.Input, key, ""); }
    }
  }
}

/* The serverAPI functions prepares and writes out the input file for external process execution
   The inputfile contains the SERVER, COOKIES, POST, and FILES information that can be used by the external script
   This data is picked-up by the different CGI APIs, and presented to the client in the regular way */
final void serverAPI(in FileSystem filesystem, in WebConfig config, in Request request, in Response response)  {
  Appender!(string) content;
  content.put(format("S=REDIRECT_STATUS=%d\n", response.payload.statuscode));

  // Give HTTP_COOKIES to CGI
  foreach (c; request.cookies.split("; ")) { content.put(format("C=%s\n", chomp(c)) ); }
  content.put(format("S=SERVER_SOFTWARE=%s\n", SERVERINFO));
  try{
    content.put(format("S=SERVER_NAME=%s\n", (response.address)? response.address.toHostNameString() : "localhost"));
  }catch(Exception e){
    warning("Exception while trying to call: toHostNameString()");
    content.put("S=SERVER_NAME=localhost\n");
  }
  content.put(format("S=SERVER_ADDR=%s\n", (response.address)? response.address.toAddrString() : "127.0.0.1"));
  content.put(format("S=SERVER_PORT=%s\n", (response.address)? response.address.toPortString() : "80"));
  content.put(format("S=DOCUMENT_ROOT=%s\n", filesystem.localroot(request.shorthost())));
  content.put(format("S=GATEWAY_INTERFACE=%s\n", "CGI/1.1"));
  content.put(format("S=PHP_SELF=%s\n", request.path));
  content.put(format("S=REQUEST_TIME=%s\n", request.starttime.toUnixTime));

  // Were the following invented / made up by me ? or mistaken/old ones ?
  content.put(format("S=REMOTE_PAGE=%s\n", request.page));
  content.put(format("S=REQUEST_DIR=%s\n", request.dir));

  // Write the post information we received
  foreach (p; request.postinfo) {
    if(p.type == PostType.Input)  content.put(format("P=%s=%s\n", p.name, p.value));
    if(p.type == PostType.File)   content.put(format("F=%s=%s=%s=%s\n", p.name, p.filename, p.mime, p.value));
  }

  string filename = request.inputfile(filesystem);
  trace("[IN %s]\n%s[/IN %s]", filename, content.data, filename);
  writeinfile(filename, content.data);
}

