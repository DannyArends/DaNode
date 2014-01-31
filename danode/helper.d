/**
 * | <a href="index.html">Home</a>             | <a href="server.html">Server</a>              |
 *   <a href="client.html">Client</a>          | <a href="router.html">Router</a>              |
 *   <a href="cgi.html">CGI</a>                | <a href="filebuffer.html">File Buffer</a>     |
 *   <a href="structs.html">Structures</a>     | <a href="helper.html">Helper functions</a>    |
 *
 * License: Use freely for any purpose
 */
module danode.helper;

import std.stdio, std.string, std.socket, std.datetime, std.file, std.concurrency;
import std.conv, std.regex, std.compiler, std.random, core.memory, core.thread;
import danode.structs, danode.httpstatus, danode.mimetypes, danode.math;

/***********************************
 * Extend integer x to a string of length digits
 */
string toD(int x, size_t digits = 6){
  string s = to!string(x);
  while(s.length < digits){ s = "0" ~ s; }
  return s;
}

/***********************************
 * Get the remote information available for socket
 */
string remoteInfo(Socket socket){
  try{
    if(socket){
      Address a = socket.remoteAddress();
      if(a !is null){ return a.toAddrString() ~ ":" ~ a.toPortString(); }else{ return "x.x.x.x:-1"; }
    }
  }catch(Exception e){ debug writeln("[Error]  Unable to get remoteAddress"); }
  return "x.x.x.x:-1";
}

/***********************************
 * Log msg to file and/or console
 */
void log(in string msg, in string file = "debug.log", bool console = false){
  if(LOGENABLED){
    try{
      auto logfile = new File(file,"at");
      logfile.writefln("%s - %s",htmlTime(now()), msg);
      logfile.close();
    }catch(Exception e){ writefln("Log error: '%s' not saved", msg); }
  }
  if(console) writeln(msg);
}

/***********************************
 * Close a socket
 */
void closeSocket(Socket socket){ if(socket && socket.isAlive){
    socket.shutdown(SocketShutdown.BOTH);
    socket.close();
}}

/***********************************
 * Get the local OS root folder for a requested hostname
 */
string getRootFolder(in string hostname, in string root = "www"){
  if(hostname.indexOf("127.0.0.1") >= 0)  return format("Admin: %s", hostname);
  foreach(string name; dirEntries(root, SpanMode.shallow)){
    string shortname = name[(root.length+1)..$];
    if(isDir(name) && hostname.indexOf(shortname) >= 0){
      return format("./%s/", name);
    }
  }
  return format("NotHosted: %s",hostname);
}

/***********************************
 * Get all the local OS root folders
 */
string[] getRootFolders(in string root = "www"){
  string[] list;
  foreach(string name; dirEntries(root, SpanMode.shallow)){
    if(isDir(name)) list ~= format("%s/%s/", root, name[(root.length+1) .. $]);
  }
  return list;
}

/***********************************
 * Get a header from a request by name
 */
string getHeader(in Request request, in string name = "host"){
  return fromarr!(string, string)(name, request.headers);
}

string bufferToString(in ubyte[] buffer){ return to!string(cast(char[])buffer); }

/***********************************
 * Extend string s to length f
 */
string al(in string s, in int f){
  int size = f-cast(int)s.length;
  if(size <= 0) return s;
  string rs = s;
  char[] additional = new char[](size);
  for(size_t i =0; i < size; i++){ additional[i] = ' '; }
  rs = format("%s%s", rs, additional);
  additional = null;
  return rs;
}

string strfrom(string str, string k){ return str[(str.indexOf(k)+1) .. $]; }
long   Msecs(in SysTime t, in SysTime t0 = now()){ return (t0-t).total!"msecs"(); }
long   secs(in SysTime t, in SysTime t0 = now()){  return (t0-t).total!"seconds"(); }
string htmlTime(in SysTime d){ 
  return format(timeFmt, d.day(), months[d.month()], d.year(), d.hour(), 
                         toD(d.minute(),2), toD(d.second(),2), "CET"); }

/***********************************
 * Is key in buffer ?
 */
bool inarr(T,K)(in K key, in T[K] buffer){
  return((key in buffer) !is null);
}

/***********************************
 * Get from array return T.init on not found
 */
T fromarr(T,K)(in K key, in T[K] buffer){
  T* p = cast(T*)(key in buffer);
  if(p is null) return T.init;
  return(*p);
}

/***********************************
 * Is path a direct request to a file
 */
bool directRequest(in string path){
  if(exists(path) && isFile(path)) return true;
  return false;
}

/***********************************
 * Is path a CGI request
 */
pure bool isCGI(in string path){
  if(toMime(path).indexOf(CGI_FILE) >= 0) return true;
  return false;
}

/***********************************
 * Is path an allowed filetype ?
 */
pure bool allowedFileType(in string path){
  if(toMime(path) == UNSUPPORTED_FILE) return false;
  return true;
}

/***********************************
 * Is path a direct request to a directory
 */
bool directoryRequested(in string path){
  if(exists(path) && isDir(path)) return true;
  return false;
}

/***********************************
 * Which interpreter should be used to interpret path
 */
string whichInterpreter(in string path){
  string[] mime = toMime(path).strsplit("/");
  if(mime.length > 1) return mime[1];
  writefln("[WARN]    Mime %s cannot be used as interpreter", mime);
  return "";
}

/***********************************
 * Get a free filename
 *
 * Must return a free filename !!! 
 * Should be thread safe and not depend on luck
 *
 */
string freeFile(in string dir = "", in string stem = "temp", int port = 80, in string ext = ".dat", size_t d = 6){
  return format("%s%s%s%s", dir, stem, toD(port, d), ext);
}

