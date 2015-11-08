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
enum HeaderType { None, FastCGI, HTTP10, HTTP11 }

interface Payload {
  public:
    @property long                ready();
    @property StatusCode          statuscode() const;
    @property PayLoadType         type() const;
    @property long                length() const;
    @property SysTime             mtime();
    @property string              mimetype() const;

    const(char)[] bytes(long from, long maxsize = 1024);
}

class CGI : Payload {
  private:
    Process external;

  public:
    this(string command, string path, int verbose = NORMAL){ external = new Process(command, path, verbose); external.start(); }

    final @property PayLoadType   type() const { return(PayLoadType.Script); }
    final @property long          ready() { return(external.finished); }
    final @property long          length() const { 
      if(!external.running) return(getHeader!long("Content-Length", external.length));
      return -1; 
    }
    final @property SysTime       mtime() { return Clock.currTime(); }
    final @property string        mimetype() const { return "text/html"; } // Todo if there is a header parse it out of there

    final T getHeader(T)(string key, T def = T.init, long i = 1) const {
      if(endOfHeader > 0){
        foreach(line; to!string(external.output(0))[0..endOfHeader()].split("\n")){
          string[] elems = line.split(": ");
          if(elems.length >= (i+1) && toLower(elems[0]) == toLower(key)) return to!T(elems[i].split(" ")[0]);
        }
      }
      return(def);
    }

    @property final HeaderType headerType() {
      if(endOfHeader() <= 0) return HeaderType.None;
      string respl = fullHeader().split("\n")[0];
      string[] values = respl.split(" ");
      if(values.length == 3 && values[0] == "HTTP/1.0") return HeaderType.HTTP10;
      if(values.length == 3 && values[0] == "HTTP/1.1") return HeaderType.HTTP11;
      if(getHeader("Status", "") != "") return HeaderType.FastCGI;
      return HeaderType.None;
    }

    @property final string fullHeader() {
      return(to!string( bytes(0, endOfHeader()) ));
    }

    @property final StatusCode statuscode() const {
      long status = getHeader("status", -1);
      if(status == -1) return((external.status == 0)? StatusCode.Ok : StatusCode.ISE );
      return(to!StatusCode(to!int(status)));
    }

    const(char)[] bytes(long from, long maxsize = 1024){ return(external.output(from)[0 .. to!long(fmin(from+maxsize, $))]); }

    final long endOfHeader() const {
      string outputSoFar = to!string(external.output(0));
      long idx = outputSoFar.indexOf("\r\n\r\n");
      if(idx <= 0) idx = outputSoFar.indexOf("\n\n");
      return(idx);
    }

}

class Message : Payload {
  private:
    StatusCode status;
    string message;
    string mime;

  public:
    this(StatusCode status, string message, string mime = "text/plain"){ this.status = status; this.message = message; this.mime = mime; }

    final @property PayLoadType   type() const { return(PayLoadType.Message); }
    final @property long      ready() { return(true); }
    final @property long      length() const { return(message.length); }
    final @property SysTime   mtime() { return Clock.currTime(); }
    final @property string    mimetype() const { return mime; }
    final @property StatusCode statuscode() const { return status; }
    char[] bytes(long from, long maxsize = 1024){ return(cast(char[])message[from .. cast(ulong)fmin(from+maxsize, $)]); }
}

class Empty : Message {
  public:
    this(StatusCode status, string mime = UNSUPPORTED_FILE){ super(status, "", mime); }
}

