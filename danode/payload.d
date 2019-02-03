module danode.payload;

import danode.imports;
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
    @property ptrdiff_t           length() const;
    @property SysTime             mtime();
    @property string              mimetype() const;

    const(char)[] bytes(ptrdiff_t from, ptrdiff_t maxsize = 1024);
}

class CGI : Payload {
  private:
    Process external;

  public:
    this(string command, string path, int verbose = NORMAL){ external = new Process(command, path, verbose); external.start(); }

    final @property PayLoadType   type() const { return(PayLoadType.Script); }
    final @property long          ready() { return(external.finished); }
    final @property ptrdiff_t     length() const {
      if(!external.running) {
        ptrdiff_t msglength = to!ptrdiff_t(external.length);
        if(endOfHeader > 0) msglength = msglength - endOfHeader;
        return(getHeader!ptrdiff_t("Content-Length", msglength));
      }
      return -1; 
    }
    final @property SysTime       mtime() { return Clock.currTime(); }
    final @property string        mimetype() const { return "text/html"; } // Todo if there is a header parse it out of there

    final T getHeader(T)(string key, T def = T.init) const {
      if (endOfHeader > 0) {
        foreach(line; fullHeader().split("\n")){
          string[] elems = line.split(": ");
          if(elems.length == 2) {
            if(toLower(elems[0]) == toLower(key)) return to!T(strip(elems[1]));
          }
        }
      }
      return(def);
    }

    @property final HeaderType headerType() const {
      if(endOfHeader() <= 0) return HeaderType.None;
      string[] values = firstHeaderLine().split(" ");
      if(values.length >= 3 && values[0] == "HTTP/1.0") return HeaderType.HTTP10;
      if(values.length >= 3 && values[0] == "HTTP/1.1") return HeaderType.HTTP11;
      if(getHeader("Status", "") != "") return HeaderType.FastCGI;
      return HeaderType.None;
    }

    @property final string fullHeader() const {
      string outputSoFar = to!string(external.output(0));
      if(endOfHeader() > 0) return outputSoFar[0 .. endOfHeader()];
      return [];
    }

    @property final string firstHeaderLine() const {
      string outputSoFar = to!string(external.output(0));
      return(outputSoFar[0 .. outputSoFar.indexOf("\n")]);
    }

    @property final StatusCode statuscode() const {
      string status = "";
      if(headerType() == HeaderType.FastCGI) {
        status = getHeader!string("Status", ""); // Fast-CGI provides: "Status: Code Reason"
        status = status.split(" ")[0];
      }
      if(headerType() == HeaderType.HTTP10 || headerType() == HeaderType.HTTP11) {
        string[] values = firstHeaderLine().split(" "); // Normal HTTP header: "Version Code Reason"
        if(values.length >= 3) status = values[1];
      }
      if(status == "") return((external.status == 0)? StatusCode.Ok : StatusCode.ISE );
      StatusCode s = StatusCode.ISE;
      try {
        s = to!StatusCode(to!int(status));
      } catch (Exception e){
        writeln("[ERROR]  Unable to get statuscode from script");
      }
      return(s);
    }

    const(char)[] bytes(ptrdiff_t from, ptrdiff_t maxsize = 1024) {
      // Stream of message bytes, skip the header the script generated (since the webserver parses this)
      if(from + endOfHeader > from) from = from + endOfHeader;
      return(external.output(from)[0 .. to!ptrdiff_t(fmin(from+maxsize, $))]);
    }

    final ptrdiff_t endOfHeader() const {
      string outputSoFar = to!string(external.output(0));
      ptrdiff_t idx = outputSoFar.indexOf("\r\n\r\n");
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
    final @property long          ready() { return(true); }
    final @property ptrdiff_t     length() const { return(message.length); }
    final @property SysTime       mtime() { return Clock.currTime(); }
    final @property string        mimetype() const { return mime; }
    final @property StatusCode    statuscode() const { return status; }
    char[] bytes(ptrdiff_t from, ptrdiff_t maxsize = 1024){ return( message[from .. to!ptrdiff_t(fmin(from+maxsize, $))].dup ); }
}

class Empty : Message {
  public:
    this(StatusCode status, string mime = UNSUPPORTED_FILE){ super(status, "", mime); }
}

