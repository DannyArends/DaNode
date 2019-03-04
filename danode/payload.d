module danode.payload;

import danode.imports;
import danode.process : Process;
import danode.httpstatus : StatusCode;
import danode.mimetypes : UNSUPPORTED_FILE, mime;
import danode.log : error;

enum PayloadType { Message, Script, File }
enum HeaderType { None, FastCGI, HTTP10, HTTP11 }

interface Payload {
  public:
    @property long                ready();
    @property StatusCode          statuscode() const;
    @property PayloadType         type() const;
    @property ptrdiff_t           length() const;
    @property SysTime             mtime();
    @property string              mimetype() const;

    const(char)[] bytes(ptrdiff_t from, ptrdiff_t maxsize = 1024);
}

class Message : Payload {
  private:
    StatusCode status;
    string message;
    string mime;

  public:
    this(StatusCode status, string message, string mime = "text/plain"){ this.status = status; this.message = message; this.mime = mime; }

    final @property PayloadType   type() const { return(PayloadType.Message); }
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

