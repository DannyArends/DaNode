module danode.webconfig;

import std.stdio, std.string, std.file;
import danode.structs, danode.helper;

bool allowsCGI(in string[string] config){
  return(!inarr("allowcgi", config) || (fromarr("allowcgi", config) == "yes"));
}

string[string] parseWebConfig(in string content){
  string[string] config;
  foreach(line; strsplit(content, "\n")){
    if(chomp(strip(line)) != "" && line[0] != '#'){
      string[] elem = strsplit(line, "=");
      if(elem.length == 1) elem ~= "FALSE";
      if(elem.length == 2){
        config[chomp(strip(elem[0]))] = chomp(strip(elem[1]));
      }
    }
  }
  return config;
}

string[string] getWebConfig(Server server, in string path){ with(server){
  string configpath = strrepl((path ~ "/web.config"),"//","/");
  string[string] config;
  if(filebuffer.has(configpath) && !filebuffer.needUpdate(configpath)){
    BFile bf = filebuffer.get(configpath);
    config   = parseWebConfig(cast(string)(bf.content));
  }else{
    if(exists(configpath) && isFile(configpath)){
      config = parseWebConfig(filebuffer.loadFile(configpath));
    }else{ debug writefln("[WARN]   No config file for: %s", path); }
  }
  config["webroot"] = path;
  if(path[($-1)] != '/') config["webroot"] = format("%s/", path);
  return config;
}}

bool redirectDirToIndex(in string[string] config){
  if(inarr("redirectdir", config)){ if(fromarr("redirectdir", config)=="yes") return true; }
  return false;
}

bool isAllowedDir(in string path, in string[string] config){
  if(inarr("allowdirs", config)){ // If we have allowed dirs
    foreach(string dir; strsplit(fromarr("allowdirs", config), ",")){
      if(path == config["webroot"] ~ chomp(strip(dir))) return true;
    }
  }
  return false;
}

bool hasIndex(string path, string index){
  string indexpath = strrepl((path ~ "/" ~ index), "//", "/");
  if(exists(indexpath) && isFile(indexpath)) return true;
  return false;
}

string getIndexPage(in string path, in string[string] config){
  if(exists(path) && isDir(path)){    // If we request a directory, check for an index
    if(inarr("redirecturl", config)){ // If the config has an index, redirect to that
      if(hasIndex(path, fromarr("redirecturl", config))) return fromarr("redirecturl", config);
    }
    foreach(index; DEFAULTINDICES){          // Check for default index pages
      if(hasIndex(path, index)) return index;
    }
  }
  return path; // No index page, just return the requested path;
}

