module danode.post;

import danode.imports;
import danode.httpstatus : StatusCode;
import danode.request : Request;
import danode.response : SERVERINFO, Response, redirect, create, notmodified;
import danode.webconfig : WebConfig;
import danode.payload : Message, CGI;
import danode.mimetypes : mime;
import danode.filesystem : FileSystem;
import danode.functions : from, has, isCGI, isFILE, isDIR, writefile;
import danode.log : info, custom, trace, warning;

immutable string      MPHEADER         = "multipart/form-data";                     /// Multipart header id
immutable string      XFORMHEADER      = "application/x-www-form-urlencoded";       /// X-form header id
enum PostType { Input, File };

struct PostItem {
  PostType  type;
  string    name;
  string    filename;
  string    value;
  string    mime = "post/input";
  long      size = 0;
}

final bool parsePost (ref Request request, ref Response response, in FileSystem filesystem) {
  if (response.havepost || request.method != "POST") {
    response.havepost = true;
    return(true);
  }
  long expectedlength = to!long(from(request.headers, "Content-Length", "0"));
  string content = request.body;
  if (expectedlength == 0) {
    custom(0, "POST", "Content-Length was not specified or 0: real length: %s", content.length);
    response.havepost = true;
    return(true); // When we don't receive any post data it is meaningless to scan for any content
  }
  custom(2, "POST", "received %s of %s", content.length, expectedlength);
  if(content.length < expectedlength) return(false);

  string contenttype  = from(request.headers, "Content-Type");
  custom(2, "POST", "content type: %s", contenttype);

  if (contenttype.indexOf(XFORMHEADER) >= 0) {
    // parse the X-form content in the body of the request
    custom(1, "XFORM", "parsing %d bytes", expectedlength);
    foreach(s; content.split("&")){
      string[] elem = strip(s).split("=");
      request.postinfo[ elem[0] ] = PostItem( PostType.Input, elem[0], "", elem[1] );
    }
    custom(1, "XFORM", "# of items: %s", request.postinfo.length);

  } else if(contenttype.indexOf(MPHEADER) >= 0) {
    // parse the Multipart content in the body of the request
    string mpid = split(contenttype, "boundary=")[1];
    info("header: %s, parsing %d bytes", mpid, expectedlength);
    foreach(size_t i, part; chomp(content).split(mpid)){
      string[] elem = strip(part).split("\r\n");
      if (elem[0] != "--") {
        string[] mphdr = elem[0].split("; ");
        string key = mphdr[1][6 .. ($-1)];
        if (mphdr.length == 2) {
          request.postinfo[key] = PostItem(PostType.Input, key, "", join(elem[2 .. ($-1)]));
        } else if (mphdr.length == 3) {
          string fname = mphdr[2][10 .. ($-1)];
          if (fname != "") {
            string localpath = request.uploadfile(filesystem, key);
            string mpcontent = join(elem[3 .. ($-1)], "\r\n");
            request.postinfo[key] = PostItem(PostType.File, key, mphdr[2][10 .. ($-1)], localpath, split(elem[1],": ")[1], mpcontent.length);
            writefile(localpath, mpcontent);
          } else {
            request.postinfo[key] = PostItem(PostType.Input, key, "");
          }
        }
      }
    }
    info(", # of items: %s", request.postinfo.length);
  } else {
    warning("unsupported post content type: %s [%s] -> %s", contenttype, expectedlength, content);
  }
  response.havepost = true;
  return(response.havepost);
}

final void serverAPI(in FileSystem filesystem, in WebConfig config, in Request request, in Response response)  {
  Appender!(string) content;

  content.put(format("S=PHP_SELF=%s\n",             request.path));
  content.put(format("S=GATEWAY_INTERFACE=%s\n",    "CGI/1.1"));
  content.put(format("S=SERVER_ADDR=%s\n",          "127.0.0.1"));
  content.put(format("S=SERVER_NAME=%s\n",          "laptop.danny"));
  content.put(format("S=SERVER_SOFTWARE=%s\n",      SERVERINFO));
  content.put(format("S=SERVER_PROTOCOL=%s\n",      request.protocol));
  content.put(format("S=REQUEST_METHOD=%s\n",       request.method));
  content.put(format("S=REQUEST_TIME=%s\n",         request.starttime.toUnixTime));
  content.put(format("S=DOCUMENT_ROOT=%s\n",        filesystem.localroot(request.shorthost())));
  content.put(format("S=QUERY_STRING=%s\n",         request.query));
  content.put(format("S=HTTP_CONNECTION=%s\n",      (response.keepalive)? "Keep-Alive" : "Close" ));
  content.put(format("S=HTTP_HOST=%s:%s\n",         request.host, request.serverport));
  content.put(format("S=HTTPS=%s\n",                (request.isSecure)? "1" : "0" ));
  content.put(format("S=REMOTE_ADDR=%s\n",          request.ip));
  content.put(format("S=REMOTE_PORT=%s\n",          request.port));
  content.put(format("S=REMOTE_PAGE=%s\n",          request.page));
  content.put(format("S=REQUEST_DIR=%s\n",          request.dir));
  content.put(format("S=SCRIPT_FILENAME=%s\n",      config.localpath(filesystem.localroot(request.shorthost()), request.path)));
  content.put(format("S=SERVER_PORT=%s\n",          request.serverport));
  content.put(format("S=REQUEST_URI=%s\n",          request.uripath));
  content.put(format("S=HTTP_USER_AGENT=%s\n",      request.headers.from("User-Agent")));
  content.put(format("S=HTTP_ACCEPT=%s\n",          request.headers.from("Accept")));
  content.put(format("S=HTTP_ACCEPT_CHARSET=%s\n",  request.headers.from("Accept-Charset")));
  content.put(format("S=HTTP_ACCEPT_ENCODING=%s\n", request.headers.from("Accept-Encoding")));
  content.put(format("S=HTTP_ACCEPT_LANGUAGE=%s\n", request.headers.from("Accept-Language")));

  foreach (c; request.cookies.split("; ")) {
    content.put(format("C=%s\n", chomp(c)) );
  }

  foreach (p; request.postinfo) {
    if(p.type == PostType.Input)  content.put(format("P=%s=%s\n", p.name, p.value));
    if(p.type == PostType.File)   content.put(format("F=%s=%s=%s=%s\n", p.name, p.filename, p.mime, p.value));
  }

  string filename = request.inputfile(filesystem);
  trace("[IN %s]\n%s[/IN %s]", filename, content.data, filename);
  writefile(filename, content.data);
}

