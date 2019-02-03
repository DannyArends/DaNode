module danode.serverconfig;

import danode.imports;
import danode.filesystem : FileInfo;

struct ServerConfig {
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
}

unittest {
  import std.stdio : writefln;
  writefln("[FILE]   %s", __FILE__);
}

