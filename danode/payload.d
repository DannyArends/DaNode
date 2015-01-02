module danode.payload;

import std.stdio;
import std.file;
import std.conv;
import std.datetime;
import std.string;
import std.math : fmin;
import danode.process : Process;
import danode.httpstatus : StatusCode;
import danode.mimetypes : UNSUPPORTED_FILE, mime;
import danode.log : NORMAL, INFO, DEBUG;

enum PayLoadType { Message, Script, File }

interface Payload {
  public:
    @property long                ready();
    @property StatusCode          statuscode();
    @property PayLoadType         type();
    @property long                length();
    @property SysTime             mtime();
    @property string              mimetype() const;

    char[] bytes(long from, long maxsize = 1024);
}

class CGI : Payload {
  private:
    Process external;

  public:
    this(string command, string path, int verbose = NORMAL){ external = new Process(command, path, verbose); external.start(); }


    final @property PayLoadType   type(){ return(PayLoadType.Script); }
    final @property long          ready()  { if(external.running){ return(header != ""); } return(!external.running); }
    final @property long          length() const { if(!external.running){ return external.length; } return -1; }
    final @property SysTime       mtime() { return Clock.currTime(); }
    final @property string        mimetype() const { return "text/html"; } // Todo if there is a header parse it out of there

    @property final StatusCode statuscode(){
      foreach(line; header.split("\r\n")){
        string[] elems = line.split(": ");
        if(elems.length >= 2 && elems[0] == "Status") return to!StatusCode(to!int(elems[1].split(" ")[0]));
      }
      return((external.status == 0)? StatusCode.Ok : StatusCode.ISE );
    }

    char[] bytes(long from, long maxsize = 1024){ return(external.output(from)[0 .. cast(ulong)fmin(from+maxsize, $)]); }
    final string header(){
      string content = to!string(bytes(0, 1024));
      long idx = content.indexOf("\r\n\r\n"); return((idx > 0)? content[0 .. idx] : "");
    }
}

class Message : Payload {
  private:
    StatusCode status;
    string message;
    string mime;

  public:
    this(StatusCode status, string message, string mime = "text/plain"){ this.status = status; this.message = message; this.mime = mime; }

    final @property PayLoadType   type(){ return(PayLoadType.Message); }
    final @property long      ready(){ return(true); }
    final @property long      length() const { return(message.length); }
    final @property SysTime   mtime() { return Clock.currTime(); }
    final @property string    mimetype() const { return mime; }
    final @property StatusCode statuscode(){ return status; }
    char[] bytes(long from, long maxsize = 1024){ return(cast(char[])message[from .. cast(ulong)fmin(from+maxsize, $)]); }
}

class Empty : Message {
  public:
    this(StatusCode status, string mime = UNSUPPORTED_FILE){ super(status, "", mime); }
}

