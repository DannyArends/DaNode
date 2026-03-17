/** danode/functions.d - Utility functions: date parsing, CGI detection, query strings, encoding
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.functions;

import danode.imports;

import danode.log : log, tag, error, Level;
import danode.mimetypes : CGI_FILE, mime, UNSUPPORTED_FILE;

immutable string[int] months; 
shared static this(){
  months = [ 1 : "Jan", 2 : "Feb", 3 : "Mar", 4 : "Apr",
             5 : "May", 6 : "Jun", 7 : "Jul", 8 : "Aug",
             9 : "Sep", 10: "Oct", 11: "Nov", 12: "Dec"];
}

immutable auto htmlDateRegex = ctRegex!(r"([0-9]{1,2}) ([a-z]{1,3}) ([0-9]{4}) ([0-9]{1,2}):([0-9]{1,2}):([0-9]{1,2}) [a-z]{3}", "g");

// Try to convert a HTML date in a string into a SysTime
// Structure that we expect: "21 Apr 2014 20:20:13 GMT"
SysTime parseHtmlDate(const string datestr) {
  SysTime ts =  SysTime(DateTime(-7, 1, 1, 1, 0, 0));
  auto m = match(datestr.toLower(), htmlDateRegex);
  if (m.captures.length == 7) {
    try {
      ts = SysTime(DateTime(to!int(m.captures[3]), monthToIndex(m.captures[2]), to!int(m.captures[1]),      // 21 Apr 2014
                            to!int(m.captures[4]), to!int(m.captures[5]), to!int(m.captures[6])), UTC());   // 20:20:13
    } catch(Exception e) { error("parseHtmlDate exception, could not parse '%s'", datestr); }
  }
  return(ts);
}

pure string htmlEscape(string s) nothrow {
  return(s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&#39;"));
}

pure string resolve(string path) { return(buildNormalizedPath(absolutePath(path)).replace("\\", "/")); }

string resolveFolder(string path) {
  path = path.resolve();
  path = (path.endsWith("/"))? path : path ~ "/";
  if (!exists(path)) mkdirRecurse(path);
  return(path);
}

// Returns null if path escapes root
string safePath(in string root, in string path) {
  if (path.canFind("..")) return null;
  if (path.canFind("\0")) return null;
  string full = root ~ (path.startsWith("/") ? path : "/" ~ path);
  try {
    if (exists(full)) {
      string resolved = full.resolve();
      string absroot = root.resolve();
      if (!absroot.endsWith("/")) absroot ~= "/";
      if (resolved != absroot[0..$-1] && !resolved.startsWith(absroot)) return null;
    }
  } catch (Exception e) { return null; }
  return full;
}

// Month to index of the year
@nogc pure int monthToIndex(in string m) nothrow {
  for (int x = 1; x <= 12; ++x) { if(icmp(m, months[x]) == 0) return x; }
  return -1;
}

@nogc pure long Msecs(in SysTime t, in SysTime t0 = Clock.currTime()) nothrow {
  if(t == SysTime.init) return(-1);
  return((t0 - t).total!"msecs"());
}

@nogc pure bool has(T,K)(in T[K] buffer, in K key) nothrow {
  return((key in buffer) !is null);
}

string[string] parseQueryString(const string query) {
  string[string] params;
  foreach (param; query.split("&")) {
    try {
      string s     = strip(param);
      ptrdiff_t i  = s.indexOf("=");
      string key   = decodeComponent(i > 0 ? s[0 .. i]   : s);
      string value = decodeComponent((i > 0 ? s[i+1 .. $] : "").replace("+", " "));
      if (key.length > 0) params[key] = value;
    } catch (Exception e) { error("parseQueryString: failed to decode '%s'", param); }
  }
  return params;
}

@nogc pure T from(T,K)(in T[K] buffer, in K key, T def = T.init) nothrow {
  T* p = cast(T*)(key in buffer);
  if(p is null) return def;
  return(*p);
}

void writeFile(in string localpath, in string content) {
  try {
    auto fp = File(localpath, "wb");
    fp.rawWrite(content);
    fp.close();
    log(Level.Trace, "writeFile: %d bytes to: %s", content.length, localpath);
  } catch(Exception e) { error("writeFile: I/O exception '%s'", e.msg); }
}

string htmltime(in SysTime d = Clock.currTime()) {
  auto utc = d.toUTC();
  return format("%s %s %s %02d:%02d:%02d GMT", utc.day(), months[utc.month()], utc.year(), utc.hour(), utc.minute(), utc.second());
}

bool isFILE(in string path) {
  try { return(isFile(path)); } catch(Exception e) { error("isFILE: I/O exception '%s'", e.msg); } return false;
}

bool isDIR(in string path) {
  try { return(isDir(path)); } catch(Exception e) { error("isDIR: I/O exception '%s'", e.msg); }
  return false;
}

bool isCGI(in string path) {
  try { return(isFile(path) && mime(path).indexOf(CGI_FILE) >= 0); }
  catch(Exception e) { error("isCGI: I/O exception '%s'", e.msg); }
  return false;
}

pure bool isAllowed(in string path) { return(mime(path) != UNSUPPORTED_FILE); }

// Where does the HTTP request header end ?
@nogc pure ptrdiff_t endofheader(T)(const(T) buffer) nothrow {
  ptrdiff_t len = buffer.length;
  for (ptrdiff_t i = 0; i < len - 1; i++) {
    if (i < len - 3 && buffer[i] == '\r' && buffer[i+1] == '\n' && buffer[i+2] == '\r' && buffer[i+3] == '\n') return i;
    if (buffer[i] == '\n' && buffer[i+1] == '\n') return i;
  }
  return -1;
}

// Where does the HTTP request body start ?
@nogc pure ptrdiff_t bodystart(T)(const(T) buffer) nothrow {
  ptrdiff_t i = endofheader(buffer);
  if (i < 0) return -1;
  return((i + 3 < buffer.length && buffer[i] == '\r' && buffer[i+1] == '\n') ? i + 4 : i + 2);
}

// get the HTTP header contained in the buffer (including the \r\n\r\n)
pure string fullheader(T)(const(T) buffer) {
  auto i = bodystart(buffer);
  if (i > 0 && i <= buffer.length) { return(to!string(buffer[0 .. i])); }
  return [];
}

// Which interpreter (if any) should be used for the path ?
string interpreter(in string path) {
  if (!isCGI(path)) return [];
  string[] parts = mime(path).split("/");
  if(parts.length > 1) return(parts[1]);
  return [];
}

// Browse the content of a directory, generate a rudimentairy HTML file
string browseDir(in string root, in string localpath) {
  Appender!(string) content;
  content.put(format("Content of: %s<br>\n", htmlEscape(localpath)));
  foreach (DirEntry d; dirEntries(localpath, SpanMode.shallow)) {
    string name = d.name[root.length .. $].replace("\\", "/");
    if (name.endsWith(".in") || name.endsWith(".up")) continue;
    string escaped = htmlEscape(name);
    content.put(format("<a href='%s'>%s</a><br>", escaped, escaped));
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
  tag(Level.Always, "FILE", "%s", __FILE__);

  // monthToIndex
  assert(monthToIndex("Feb") == 2,  "Feb must be month 2");
  assert(monthToIndex("Jan") == 1,  "Jan must be month 1");
  assert(monthToIndex("Dec") == 12, "Dec must be month 12");
  assert(monthToIndex("xyz") == -1, "invalid month must return -1");

  // htmltime
  assert(htmltime().length > 0, "htmltime must return non-empty string");

  // isFILE / isDIR / isCGI
  assert(isFILE("danode/functions.d"),    "functions.d must be a file");
  assert(!isFILE("danode"),               "directory must not be a file");
  assert(isDIR("danode"),                 "danode must be a directory");
  assert(!isDIR("danode/functions.d"),    "file must not be a directory");
  assert(isCGI("www/localhost/dmd.d"),    "dmd.d must be CGI");
  assert(!isCGI("www/localhost/test.txt"),"txt must not be CGI");

  // interpreter
  assert(interpreter("www/localhost/dmd.d").length > 0,   "dmd.d must have interpreter");
  assert(interpreter("www/localhost/php.php").length > 0,  "php must have interpreter");
  assert(interpreter("www/localhost/test.txt").length == 0,"txt must have no interpreter");

  // safePath - security critical
  assert(safePath("www/localhost", "/../etc/passwd") is null, "path traversal .. must be blocked");
  assert(safePath("www/localhost", "/\0etc/passwd") is null, "null byte must be blocked");
  assert(safePath("www/localhost", "/test.txt") !is null, "valid path must be allowed");
  assert(safePath("www/localhost", "/test/1.txt") !is null, "valid subpath must be allowed");

  // htmlEscape - XSS critical
  assert(htmlEscape("<script>") == "&lt;script&gt;", "< and > must be escaped");
  assert(htmlEscape("\"quoted\"") == "&quot;quoted&quot;", "quotes must be escaped");
  assert(htmlEscape("a&b") == "a&amp;b", "& must be escaped");
  assert(htmlEscape("it's") == "it&#39;s", "apostrophe must be escaped");
  assert(htmlEscape("safe") == "safe", "safe string must pass through");

  // parseQueryString
  auto qs = parseQueryString("a=1&b=2&c=hello+world");
  assert(qs["a"] == "1", "simple value must parse");
  assert(qs["b"] == "2", "second value must parse");
  assert(qs["c"] == "hello world", "plus must decode to space");
  assert(parseQueryString("").length == 0, "empty query must return empty");

  // isAllowed / isAllowedFile
  assert(isAllowed("test.html"), "html must be allowed");
  assert(isAllowed("test.txt"), "txt must be allowed");
  assert(!isAllowed("test.ill"), "unknown extension must be blocked");

  // bodystart / endofheader
  assert(endofheader("GET / HTTP/1.1\r\nHost: x\r\n\r\n") >= 0, "\\r\\n\\r\\n header must be found");
  assert(endofheader("GET / HTTP/1.1\nHost: x\n\n") >= 0, "\\n\\n header must be found");
  assert(endofheader("incomplete header") == -1, "no terminator must return -1");
  assert(bodystart("GET / HTTP/1.1\nHost: x\n\nbody") > 0, "bodystart must be positive");

  // endofheader - \r\n\r\n &  \n\n
  assert(endofheader("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\nbody content") == 40, "\\r\\n\\r\\n position must be 40");
  assert(endofheader("HTTP/1.1 200 OK\nContent-Type: text/html\n\nbody content") == 39,  "\\n\\n position must be 39");

  // endofheader - no terminator
  assert(endofheader("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n") == -1, "incomplete must return -1");
  assert(endofheader("") == -1, "empty must return -1");

  // bodystart - \r\n\r\n & \n\n
  assert(bodystart("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\nbody content") == 44, "\\r\\n\\r\\n bodystart must be 44");
  assert(bodystart("HTTP/1.1 200 OK\nContent-Type: text/html\n\nbody content") == 41,  "\\n\\n bodystart must be 41");

  // bodystart - no body
  assert(bodystart("incomplete") == -1, "no terminator must return -1");

  // functions.d unittest
  assert(Msecs(SysTime.init) == -1, "SysTime.init must return -1");
  assert(Msecs(Clock.currTime()) >= 0, "current time must return >= 0");
}

