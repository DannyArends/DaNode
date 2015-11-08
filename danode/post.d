module danode.post;

import std.array : Appender, split, join;
import std.stdio : write, writef, writeln, writefln, File;
import std.file : exists, isFile;
import std.datetime : SysTime;
import std.string : format, lastIndexOf, strip, chomp, indexOf;
import std.math : fmax;
import std.conv : to;
import danode.httpstatus : StatusCode;
import danode.request : Request, internalredirect;
import danode.response : SERVERINFO, Response, redirect, create, notmodified;
import danode.webconfig : WebConfig;
import danode.payload : Message, CGI;
import danode.mimetypes : mime;
import danode.filesystem : FileSystem;
import danode.functions : from, has, isCGI, isFILE, isDIR, writefile;
import danode.log : NORMAL, INFO, DEBUG;

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

final bool parsepost(ref Request request, ref Response response, in FileSystem filesystem, int verbose = NORMAL){
  if(response.havepost || request.method != "POST"){ response.havepost = true; return(true); }
  long expectedlength = to!long(from(request.headers, "Content-Length"));
  if(expectedlength == 0){
    response.havepost = true;
    return(true); // When we don't receive any post data it is meaningless to scan for any content
  }
  if(verbose >= DEBUG) writefln("[POST]   received %s of %s", request.content.length, expectedlength);
  if(request.content.length < expectedlength) return(false);

  string contenttype  = from(request.headers, "Content-Type");
  if(verbose >= DEBUG) writefln("[POST]   content type: %s", contenttype);

  if(contenttype.indexOf(XFORMHEADER) >= 0){                // X-form
    if(verbose >= INFO) writefln("[XFORM]  parsing %d bytes", expectedlength);
    foreach(s; request.content.split("&")){
      string[] elem = strip(s).split("=");
      request.postinfo[ elem[0] ] = PostItem( PostType.Input, elem[0], "", elem[1] );
    }
    if(verbose >= INFO) writefln("[XFORM]  # of items: %s", request.postinfo.length);

  }else if(contenttype.indexOf(MPHEADER) >= 0){             // Multipart
    string mpid = split(contenttype, "boundary=")[1];
    if(verbose >= INFO) writef("[MPART]  header: %s, parsing %d bytes", mpid, expectedlength);
    foreach(int i, part; chomp(request.content).split(mpid)){
      string[] elem = strip(part).split("\r\n");
      if(elem[0] != "--"){
        string[] mphdr = elem[0].split("; ");
        string key = mphdr[1][6 .. ($-1)];
        if(mphdr.length == 2){
          request.postinfo[key] = PostItem(PostType.Input, key, "", join(elem[2 .. ($-1)]));
        }else if(mphdr.length == 3){
          string fname = mphdr[2][10 .. ($-1)];
          if(fname != ""){
            string localpath = request.uploadfile(filesystem, key);
            string content = join(elem[3 .. ($-1)], "\r\n");
            request.postinfo[key] = PostItem(PostType.File, key, mphdr[2][10 .. ($-1)], localpath, split(elem[1],": ")[1], content.length);
            writefile(localpath, content);
          }else{
            request.postinfo[key] = PostItem(PostType.Input, key, "");
          }
        }
      }
    }
    if(verbose >= INFO) writefln(", # of items: %s", request.postinfo.length);
  }else{ 
    writefln("[WARN]   unsupported post content type: %s [%s] -> %s", contenttype, expectedlength, request.content);
  }
  response.havepost = true;
  return(response.havepost);
}

final void servervariables(in FileSystem filesystem, in WebConfig config, in Request request, in Response response, int verbose = NORMAL) {
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
  content.put(format("S=HTTPS=%s\n",                ""));
  content.put(format("S=REMOTE_ADDR=%s\n",          request.ip));
  content.put(format("S=REMOTE_PORT=%s\n",          request.port));
  content.put(format("S=REMOTE_PAGE=%s\n",          request.page));
  content.put(format("S=SCRIPT_FILENAME=%s\n",      config.localpath(filesystem.localroot(request.shorthost()), request.path)));
  content.put(format("S=SERVER_PORT=%s\n",          request.serverport));
  content.put(format("S=REQUEST_URI=%s\n",          request.uripath));
  content.put(format("S=HTTP_USER_AGENT=%s\n",      request.headers.from("User-Agent")));
  content.put(format("S=HTTP_ACCEPT=%s\n",          request.headers.from("Accept")));
  content.put(format("S=HTTP_ACCEPT_CHARSET=%s\n",  request.headers.from("Accept-Charset")));
  content.put(format("S=HTTP_ACCEPT_ENCODING=%s\n", request.headers.from("Accept-Encoding")));
  content.put(format("S=HTTP_ACCEPT_LANGUAGE=%s\n", request.headers.from("Accept-Language")));

  foreach(s; request.cookies.split("; ")){
    content.put(format("C=%s\n", chomp(s)) );
  }

  foreach(p; request.postinfo){
    if(p.type == PostType.Input)  content.put(format("P=%s=%s\n", p.name, p.value));
    if(p.type == PostType.File)   content.put(format("F=%s=%s=%s=%s\n", p.name, p.filename, p.mime, p.value));
  }

  string filename = request.inputfile(filesystem);
  if(verbose >= DEBUG) writefln("[IN %s]\n%s[/IN %s]", filename, content.data, filename);
  writefile(filename, content.data);
}

