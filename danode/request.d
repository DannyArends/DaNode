module danode.request;

import std.array : join, indexOf, Appender;
import std.conv : to;
import std.math : fmax;
import std.stdio : write, writeln, writefln;
import std.datetime;
import std.string : split, strip, format, toLower, lastIndexOf;
import danode.filesystem : FileSystem;
import danode.client : Client;
import std.regex : regex, match;
import danode.functions : interpreter, from, toD, mtoI;
import danode.webconfig : WebConfig;
import danode.post : PostItem, PostType;

SysTime parseHtmlDate(string datestr){ // 21 Apr 2014 20:20:13 CET
  auto dateregex = regex(r"([0-9]{1,2}) ([a-z]{1,3}) ([0-9]{4}) ([0-9]{1,2}):([0-9]{1,2}):([0-9]{1,2}) cet", "g");
  auto m = match(datestr.toLower(), dateregex);
  if(m.captures.length == 7){
    SysTime ts = SysTime(DateTime(to!int(m.captures[3]), mtoI(m.captures[2]), to!int(m.captures[1]), to!int(m.captures[4]), to!int(m.captures[5]), to!int(m.captures[6])));
    return(ts);
  }
  return(SysTime(DateTime(-7, 1, 1, 1, 0, 0)));
}

struct Request {
  Client            client;
  string            method = "GET";
  string            uri;
  string            url;
  string            protocol;
  string[string]    headers;
  SysTime           starttime;
  string            content;
  PostItem[string]  postinfo;

  this(Client client, string header, in string content){
    this.client = client;
    this.content = content;
    string[] parts;
    foreach(i, line; header.split("\r\n")){
      if(i == 0){
        parts = line.split(" ");
        if(parts.length == 3){ method = strip(parts[0]); uri = url = strip(parts[1]); protocol = strip(parts[2]); }
      }else{
        parts = line.split(":");
        if(parts.length > 1){ headers[strip(parts[0])] = strip(join(parts[1 .. $], ":")); }
      }
    }
    starttime = Clock.currTime();
  }

  final @property string    host() const {  string h = headers.from("Host"); long i = h.indexOf(":"); if(i > 0){ return( h[0 .. i]); } return(h); }
  final @property ushort    serverport() const {  string h = headers.from("Host"); long i = h.indexOf(":"); if(i > 0){ return( to!ushort(h[(i+1) .. $])); } return(to!ushort(80)); }
  final @property string    path() const {  long i = url.indexOf("?"); if(i > 0){ return(url[0 .. i]); }else{ return(url); } }
  final @property string    query() const { long i = uri.indexOf("?"); if(i > 0){ return(uri[i .. $]); }else{ return("?"); } }
  final @property string    uripath() const { long i = uri.indexOf("?"); if(i > 0){ return(uri[0 .. i]); }else{ return(uri); } }
  final @property bool      keepalive() const { return( headers.from("Connection") == "keep-alive"); }
  final @property SysTime   ifModified() const { return(parseHtmlDate(headers.from("If-Modified-Since"))); }
  final @property bool      track() const { return(  headers.from("DNT","0") == "0"); }
  final @property long      port() const { return(client.port); };
  final @property string    ip() const { return(client.ip); };
  final @property string    params() const { Appender!string str; foreach(k; get.byKey()){ str.put(format(" \"%s=%s\"", k, get[k])); } return(str.data); }
  final @property string    inputfile(in FileSystem filesystem) const { return format("%s/tmp%s%s", filesystem.localroot(shorthost()), port, ".in"); }
  final @property string    uploadfile(FileSystem filesystem, in string name) const { return format("%s/tmp_%s_%s%s", filesystem.localroot(shorthost()), name, port, ".up"); }
  final @property string    cookies() const {  return(headers.from("Cookie")); }
  final @property string    useragent() const {  return(headers.from("User-Agent", "Unknown")); }
  final @property string[]  postfiles() const { string[] files; foreach(p; postinfo){ if(p.type == PostType.File && p.size > 0) files ~= p.value; } return(files); }
  final string              shorthost() const { return( (host.indexOf("www.") >= 0)? host[4 .. $] : host ); }
  final string              command(string localpath) const { return(format("%s %s%s", localpath.interpreter(), localpath, params())); }
  final string[string]      get() const {
    string[string] params;
    foreach(param; query[1 .. $].split("&")){ string[] elems = param.split("="); if(elems.length == 1){ elems ~= "TRUE"; } params[elems[0]] = elems[1]; }
    return params;
  }

}

bool internalredirect(in WebConfig config, ref Request request){
  if(!config.redirect) return false;
  long folders = request.path.lastIndexOf("/");
  request.url = format("%s%s", request.path[0 .. cast(ulong)fmax(folders, 0)], config.index);
  return(config.redirect);
}

