module danode.functions;

import danode.imports;
import danode.log : error, custom;
import danode.mimetypes : CGI_FILE, mime, UNSUPPORTED_FILE;

immutable string timeFmt =  "%s %s %s %s:%s:%s %s";
immutable string[int] months; 
static this(){
  months = [ 1 : "Jan", 2 : "Feb", 3 : "Mar", 4 : "Apr",
             5 : "May", 6 : "Jun", 7 : "Jul", 8 : "Aug",
             9 : "Sep", 10: "Oct", 11: "Nov", 12: "Dec"];
}

// Month to index
pure int monthToIndex(in string m) {
  for(int x = 1; x < 12; ++x) {
    if(m.toLower() == months[x].toLower()) return x;
  }
  return -1;
}

pure string toD(T, U)(in T x, in U digits = 6) nothrow {
  string s = to!string(x);
  while (s.length < digits) { s = "0" ~ s; }
  return s;
}

@nogc pure long Msecs(in SysTime t, in SysTime t0 = Clock.currTime()) nothrow {
  return((t0 - t).total!"msecs"());
}

@nogc pure bool has(T,K)(in T[K] buffer, in K key) nothrow {
  return((key in buffer) !is null);
}

@nogc pure bool has(T)(in T[] buffer, in T key) nothrow {
  foreach(T i; buffer) { 
    if(i == key) return(true);
  } 
  return false;
}

@nogc pure T from(T,K)(in T[K] buffer, in K key, T def = T.init) nothrow {
  T* p = cast(T*)(key in buffer);
  if(p is null) return def;
  return(*p);
}

void writefile(in string localpath, in string content) {
  if(content.length > 0){ auto fp = File(localpath, "wb"); fp.rawWrite(content); fp.close(); }
}

string htmltime(in SysTime d = Clock.currTime()) {
  return format(timeFmt, d.day(), months[d.month()], d.year(), d.hour(), toD(d.minute(),2), toD(d.second(),2), "CET");
}

bool isFILE(in string path) {
  try {
    if (exists(path) && isFile(path)) return true;
  } catch(Exception e) {
    error("isFILE: I/O exception '%s'", e.msg);
  }
  return false;
}

bool isDIR(in string path) {
  try {
    if (exists(path) && isDir(path)) return true;
  } catch(Exception e) {
    error("isDIR: I/O exception '%s'", e.msg);
  }
  return false;
}

bool isCGI(in string path) {
  try {
    if (exists(path) && isFile(path) && mime(path).indexOf(CGI_FILE) >= 0) return true;
  } catch(Exception e) {
    error("isCGI: I/O exception '%s'", e.msg);
  }
  return false;
}

pure bool isAllowed(in string path) {
  if (mime(path) == UNSUPPORTED_FILE) return false;
  return true;
}

// Where does the HTML request header end ?
ptrdiff_t endofheader(T)(T buffer) { 
  ptrdiff_t idx = to!string(buffer).indexOf("\r\n\r\n");
  if(idx <= 0) idx = to!string(buffer).indexOf("\n\n");
  return(idx);
}

// Where does the HTML request header end ?
string getheader(T)(T buffer) {
  auto i = endofheader(buffer);
  if (i > 0 && i < buffer.length)
    return(to!string(buffer[0 .. i]));
  return [];
}

pure string interpreter(in string path) {
  string[] mime = mime(path).split("/");
  if(mime.length > 1) return(mime[1]);
  return "";
}

string browseDir(in string root, in string localpath){
  Appender!(string) content;
  content.put(format("Content of: %s<br>\n", localpath));
  foreach (DirEntry d; dirEntries(localpath, SpanMode.shallow)) {
    content.put(format("<a href='%s'>%s</a><br>", d.name[root.length .. $], d.name[root.length .. $]));
  }
  return(format("<html><head><title>200 - Allowed directory</title></head><body>%s</body></html>", content.data));
}

// Reset the socketset and add a server socket to the set
int sISelect(SocketSet set, Socket socket, int timeout = 10) {
  set.reset();
  set.add(socket);
  return Socket.select(set, null, null, dur!"msecs"(timeout));
}

unittest {
  custom(0, "FILE", "%s", __FILE__);
  custom(0, "TEST", "monthToIndex('Feb') = %s", monthToIndex("Feb"));
  custom(0, "TEST", "toD(5, 4) = %s", toD(5, 4));
  custom(0, "TEST", "toD(12, 3) = %s", toD(12, 3));
  custom(0, "TEST", "htmltime() = %s", htmltime());
  custom(0, "TEST", "isFILE('danode/functions.d') = %s", isFILE("danode/functions.d"));
  custom(0, "TEST", "isDIR('danode') = %s", isDIR("danode"));
  custom(0, "TEST", "isCGI('www/localhost/dmd.d') = %s", isCGI("www/localhost/dmd.d"));
  custom(0, "TEST", "isAllowed('www/localhost/data.ill') = %s", isAllowed("www/localhost/data.ill"));
  custom(0, "TEST", "isAllowed('www/localhost/index.html') = %s", isAllowed("www/localhost/index.html"));
  custom(0, "TEST", "interpreter('www/localhost/dmd.d') = %s", interpreter("www/localhost/dmd.d"));
  custom(0, "TEST", "interpreter('www/localhost/php.php') = %s", interpreter("www/localhost/php.php"));
  custom(0, "TEST", "browseDir('www', 'localhost') = %s", browseDir("www", "www/localhost"));
}

