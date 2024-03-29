module danode.cgi;

import danode.imports;
import danode.functions : bodystart, endofheader, fullheader;
import danode.log : error;
import danode.process : Process;
import danode.statuscode : StatusCode;
import danode.payload : HeaderType, Payload, PayloadType;

// Class structure for common gateway interface (CGI) scripts
class CGI : Payload {
  private:
    Process external;

  public:
    string command;
    string path;

    this(string command, string path, bool removeInput = true, long maxtime = 4500){
      this.command = command;
      this.path = path;
      external = new Process(command, path, removeInput, maxtime); 
      external.start();
    }

    // The sort of payload carried (PayLoadType.Script)
    final @property PayloadType type() const { return(PayloadType.Script); }

    // Is the payload ready ?
    final @property long ready() { return(external.finished); }

    // length of the message portion of the output (generated HTML headers are detected and substracted)
    final @property ptrdiff_t length() const {
      if (!external.running) {
        ptrdiff_t msglength = to!ptrdiff_t(external.length);
        if(endOfHeader > 0) msglength = msglength - bodyStart;
        return(getHeader!ptrdiff_t("Content-Length", msglength));
      }
      return -1; 
    }

    @property void notifyovertime() { external.notifyovertime(); }

    // Last modified time (not interesting for scripts)
    final @property SysTime mtime() { return Clock.currTime(); }

    // MIME type of the content: "Content-Type: text/html; charset=utf-8"
    // split by ; since the Content-Type might be combined with a charset
    final @property string mimetype() const { 
      auto type = getHeader("Content-Type", "text/html");
      return(type.split(";")[0]);
    }

    // Get a header value from the header generated by the script
    final T getHeader(T)(string key, T def = T.init) const {
      if (endOfHeader > 0) {
        foreach (line; fullHeader().split("\n")) {
          string[] elems = line.split(": ");
          if (elems.length == 2) {
            if (toLower(elems[0]) == toLower(key)) return to!T(strip(elems[1]));
          }
        }
      }
      return(def);
    }

    // Type of header returned by the script: FastCGI, HTTP10, HTTP11
    @property final HeaderType headerType() const {
      if (endOfHeader <= 0) return HeaderType.None;
      string[] values = firstHeaderLine().split(" ");
      if (values.length >= 3 && values[0] == "HTTP/1.0") return HeaderType.HTTP10;
      if (values.length >= 3 && values[0] == "HTTP/1.1") return HeaderType.HTTP11;
      if (getHeader("Status", "") != "") return HeaderType.FastCGI;
      //if (getHeader("Content-Type", "") != "") return HeaderType.FastCGI;
      return HeaderType.None;
    }

    // Get the full header generated by the script
    @property final string fullHeader() const { return(fullheader(external.output(0))); }

    // Get the first line of the header
    @property final string firstHeaderLine() const {
      string outputSoFar = to!string(external.output(0));
      return(outputSoFar[0 .. outputSoFar.indexOf("\n")]);
    }

    // Return the status code provided by the external script
    @property final StatusCode statuscode() const {
      string status = "";
      if (headerType() == HeaderType.FastCGI) {
        status = getHeader!string("Status", ""); // Fast-CGI provides: "Status: Code Reason"
        status = status.split(" ")[0];
      }
      if (headerType() == HeaderType.HTTP10 || headerType() == HeaderType.HTTP11) {
        string[] values = firstHeaderLine().split(" "); // Normal HTTP header: "Version Code Reason"
        if(values.length >= 3) status = values[1];
      }
      if (status == "")
        return((external.status == 0)? StatusCode.Ok : StatusCode.ISE);
      StatusCode s = StatusCode.ISE;
      try {
        s = to!StatusCode(to!int(status));
      } catch (Exception e){
        error("unable to get statuscode from script");
      }
      return(s);
    }

    // Stream of message bytes, skips the script generated header since the webserver 
    // parses the header and generates it's own
    const(char)[] bytes(ptrdiff_t from, ptrdiff_t maxsize = 1024) {
      if (from + endOfHeader > from)
        from += bodyStart;
      return(external.output(from)[0 .. to!ptrdiff_t(min(from+maxsize, $))]);
    }

    // Position of the end of the header
    @property final ptrdiff_t endOfHeader() const { return(endofheader(external.output(0))); }
    // Position of the start of the body
    @property final ptrdiff_t bodyStart() const { return(bodystart(external.output(0))); }
}

