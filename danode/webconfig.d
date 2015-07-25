module danode.webconfig;

import std.stdio : writeln, writefln;
import std.string : chomp, format, split, strip, toLower, join, indexOf;
import std.file : DirEntry, dirEntries, exists, isDir, SpanMode, readText;
import danode.functions : has, from;
import danode.filesystem : FileInfo;

struct WebConfig {
  string[string]  data;

  this(FileInfo file, string def = "no") {
    string[] elements;
    foreach(line; split(file.content, "\n")){
      if(chomp(strip(line)) != "" && line[0] != '#'){
        elements = split(line, "=");
        string key = toLower(chomp(strip(elements[0])));
        if(elements.length == 1){
          data[key] = def;
        }else if(elements.length >= 2){
          data[key] = toLower(chomp(strip(join(elements[1 .. $], "="))));
        }
      }
    }
  }

  final @property string    domain(string shorthost) const { if(data.from("shorturl", "yes") == "yes") return(shorthost); return(format("www.%s", shorthost)); }
  final @property bool      allowcgi() const { if(data.from("allowcgi", "no") == "yes"){ return(true); } return(false); }
  final @property string    localpath(in string localroot, in string path) const { return(format("%s%s", localroot, path)); }
  final @property bool      redirect() const { return(data.from("redirect", "/") != "/"); }
  final @property string    index() const {
    string to = data.from("redirect", "/");
    if(to[0] != '/') return(format("/%s", to));
    return(to);
  }
  final @property string[]  allowdirs() const { return(data.from("allowdirs", "/").split(",")); }
  final @property bool      isAllowed(in string localroot, in string path) const {
    string npath = path[(localroot.length + 1) .. $]; if(npath == "") return(true);
    foreach(d; allowdirs){ if(npath.indexOf(d) == 0) return(true); } 
    return false; 
  }
}

