module danode.webconfig;

import danode.imports;
import danode.functions : has, from;
import danode.filesystem : FileInfo;
import danode.request : Request;
import danode.log : trace;

struct WebConfig {
  string[string]  data;

  this(FileInfo file, string def = "no") {
    string[] elements;
    foreach (line; split(file.content, "\n")) {
      if (chomp(strip(line)) != "" && line[0] != '#') {
        elements = split(line, "=");
        string key = toLower(chomp(strip(elements[0])));
        if (elements.length == 1) {
          data[key] = def;
        }else if (elements.length >= 2) {
          data[key] = toLower(chomp(strip(join(elements[1 .. $], "="))));
        }
      }
    }
  }

  @property string domain(string shorthost) const { 
    if (data.from("shorturl", "yes") == "yes") return(shorthost);
    return(format("www.%s", shorthost));
  }

  @property @nogc bool allowcgi() const nothrow { 
    if (data.from("allowcgi", "no") == "yes") return(true);
    return(false);
  }

  @property string localpath(in string localroot, in string path) const {
    return(format("%s%s", localroot, path));
  }

  @property @nogc bool redirect() const nothrow { 
    return(data.from("redirect", "/") != "/");
  }

  @property @nogc bool redirectdir() const nothrow { 
    return(data.from("redirectdir", "no") != "no");
  }

  @property string index() const {
    string to = data.from("redirect", "/");
    if (to[0] != '/') return(format("/%s", to));
    return(to);
  }

  @property string[] allowdirs() const nothrow { 
    return(data.from("allowdirs", "/").split(","));
  }

  @property bool isAllowed(in string localroot, in string path) const {
    trace("isAllowed: %s %s", localroot, path);
    string npath = path[(localroot.length + 1) .. $];
    trace("npath: %s", npath);
    if (npath == "") // path / is always allowed
      return(true);

    foreach (d; allowdirs) {
      trace("%s in allowdirs: %s %s", npath, d, npath.indexOf(d));
      if(indexOf(strip(d), strip(npath)) == 0) return(true);
    }
    return(false);
  }
}

