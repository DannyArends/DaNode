module api.danode;
import std.stdio, std.getopt, std.conv, std.string, std.uri, std.file;

void setGET(string[] args){
  foreach(arg;args[1..$]){
    string[] s = arg.split("=");
    if(s.length > 1) GET[decode(s[0])] = decode(s[1]);
  }
}

void setCONFIG(){
  string myloc = SERVER["SCRIPT_FILENAME"];
  string configfile = myloc[0 .. (myloc.lastIndexOf("/"))] ~ "/web.config";
  if(exists(configfile)){
    string[] configcont = to!string(std.file.read(configfile)).split("\n");
    foreach(line; configcont){
      if(chomp(line) != "" && line[0] != '#'){
        string[] s = line.split("=");
        CONFIG[chomp(strip(s[0]))] = chomp(strip(s[1]));
      }
    }
  }
}

void move_upload_file(string tmp, string to){
  if(tmp != "") return copy(tmp, to);
}

struct FileInfo{
  string name;
  string mime;
  string loc;
}

string[string] CONFIG;
string[string] COOKIES;
string[string] GET;
string[string] POST;
string[string] SERVER;
FileInfo[string] FILES;

void setPOST(){
  char[] buf;
  if(ftell(stdin.getFP()) == -1) return;
  while(stdin.readln(buf)){
    string s = chomp(to!string(buf));
    if(s == "") return;
    string[] splitted = decodeComponent(s).split("=");
    if(splitted.length > 2){
      if(splitted[0] == "S")  SERVER[decode(splitted[1])]  = chomp(strip(splitted[2]));
      if(splitted[0] == "P")  POST[decode(splitted[1])]    = chomp(strip(splitted[2]));
      if(splitted[0] == "F"){
        POST[decode(splitted[1])] = chomp(strip(splitted[2]));
        FILES[decode(splitted[1])] = FileInfo(chomp(strip(splitted[2])), chomp(strip(splitted[3])),chomp(strip(splitted[4])));
      }
      if(splitted[0] == "C")  COOKIES[decode(splitted[1])] = chomp(strip(splitted[2]));
    }
  }
}

static this(){ 
  setPOST();
  setCONFIG();
}

