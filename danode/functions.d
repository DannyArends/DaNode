/** danode/functions.d - Utility functions: date parsing, CGI detection, query strings, encoding
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.functions;

import danode.imports;

import danode.log : log, tag, error, Level;

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

string htmltime(in SysTime d = Clock.currTime()) {
  auto utc = d.toUTC();
  return format("%s %s %s %02d:%02d:%02d GMT", utc.day(), months[utc.month()], utc.year(), utc.hour(), utc.minute(), utc.second());
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
  // Msecs unittest
  assert(Msecs(SysTime.init) == -1, "SysTime.init must return -1");
  assert(Msecs(Clock.currTime()) >= 0, "current time must return >= 0");
}
