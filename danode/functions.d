module danode.functions;

import danode.imports;
import danode.mimetypes : CGI_FILE, mime, UNSUPPORTED_FILE;

immutable string timeFmt =  "%s %s %s %s:%s:%s %s";
immutable string[int] months; 
static this(){
  months = [ 1 : "Jan", 2 : "Feb", 3 : "Mar", 4 : "Apr",
             5 : "May", 6 : "Jun", 7 : "Jul", 8 : "Aug",
             9 : "Sep", 10: "Oct", 11: "Nov", 12: "Dec"];
}

pure int mtoI(string m) { for(int x = 1; x < 12; ++x){ if(m == months[x].toLower()) return x; } return 1; }
pure string toD(T, U)(in T x, in U digits = 6){ string s = to!string(x); while(s.length < digits){ s = "0" ~ s; } return s; }
pure long Msecs(in SysTime t, in SysTime t0 = Clock.currTime()){ return((t0 - t).total!"msecs"()); }
pure bool has(T,K)(in T[K] buffer, in K key){ return((key in buffer) !is null); }
pure bool has(T)(in T[] buffer, in T key){ foreach(T i; buffer){ if(i == key) return(true); } return false; }

pure T from(T,K)(in T[K] buffer, in K key, T def = T.init){
  T* p = cast(T*)(key in buffer);
  if(p is null) return def;
  return(*p);
}

void writefile(in string localpath, in string content){
  if(content.length > 0){ auto fp = File(localpath, "wb"); fp.rawWrite(content); fp.close(); }
}

string htmltime(in SysTime d = Clock.currTime()){
  return format(timeFmt, d.day(), months[d.month()], d.year(), d.hour(), toD(d.minute(),2), toD(d.second(),2), "CET");
}

bool isFILE(in string path){ if(exists(path) && isFile(path)){ return true; } return false; }
bool isDIR(in string path){ if(exists(path) && isDir(path)){ return true; } return false; }

bool isCGI(in string path){
  if(exists(path) && mime(path).indexOf(CGI_FILE) >= 0) return true;
  return false;
}

pure bool isAllowed(in string path){
  if(mime(path) == UNSUPPORTED_FILE) return false;
  return true;
}

pure string interpreter(in string path){
  string[] mime = mime(path).split("/");
  if(mime.length > 1) return(mime[1]);
  return "";
}

string browsedir(in string root, in string localpath){
  Appender!(string) content;
  content.put(format("Content of: %s<br>\n", localpath));
  foreach (DirEntry d; dirEntries(localpath, SpanMode.shallow)) {
    content.put(format("<a href='%s'>%s</a><br>", d.name[root.length .. $], d.name[root.length .. $]));
  }
  return(format("<html><head><title>200 - Allowed directory</title></head><body>%s</body></html>", content.data));
}

int sISelect(SocketSet set, Socket socket, int timeout = 10) {         // Reset the socketset and add a server socket to listen to
  set.reset();
  set.add(socket);
  return Socket.select(set, null, null, dur!"msecs"(timeout));
}

unittest {
  import std.stdio : writefln;
  writefln("[FILE]   %s", __FILE__);
  writefln("[TEST]   htmltime() = %s", htmltime());
}

