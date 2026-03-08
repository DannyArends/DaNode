module danode.payload;

import danode.imports;
import danode.statuscode : StatusCode;
import danode.mimetypes : mime, UNSUPPORTED_FILE;
import danode.log : info, warning, trace, cverbose, DEBUG;
import danode.functions : isCGI;

enum PayloadType { Message, Script, File }
enum HeaderType { None, FastCGI, HTTP10, HTTP11 }

/* Payload interface, Payload is carried by the Response structure, not the Request structure */
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

/* Implementation of the Payload interface, by using an empty string message */
class Empty : Message {
  public:
    this(StatusCode status, string mime = UNSUPPORTED_FILE) {
      super(status, "", mime);
    }
}

/* Implementation of the Payload interface, by using an underlying string buffer */
class Message : Payload {
  private:
    StatusCode status;
    string message;
    string mime;

  public:
    this(StatusCode status, string message, string mime = "text/plain") {
      this.status = status;
      this.message = message;
      this.mime = mime;
    }

    final @property PayloadType type() const { return(PayloadType.Message); }
    final @property long ready() { return(true); }
    final @property ptrdiff_t length() const { return(message.length); }
    final @property SysTime mtime() { return Clock.currTime(); }
    final @property string mimetype() const { return mime; }
    final @property StatusCode statuscode() const { return status; }
    char[] bytes(ptrdiff_t from, ptrdiff_t maxsize = 1024) { 
      return( message[from .. to!ptrdiff_t(min(from+maxsize, $))].dup );
    }
}

/* Implementation of the Payload interface, by using an underlying file (static / deflate / cgi) */
class FilePayload : Payload {
  public:
    bool      deflate = false; // Is a deflate version of the file available ?
  private:
    string    path; // Path of the file
    SysTime   btime; // Time buffered
    bool      buffered = false; // Is buffered ?
    size_t    buffermaxsize; // Maximum size of the buffer
    char[]    buf = null; // Byte buffer of the file
    char[]    encbuf = null; // Encoded buffer for the file
    File*     fp = null; // Pointer to the file

  public:
    this(string path, size_t buffermaxsize) {
      this.path = path;
      this.buffermaxsize = buffermaxsize;
    }

    /* Does the file require to be updated before sending ? */
    final bool needsupdate() {
      if (!isStaticFile()) return false; // CGI files are never buffered, since they are executed
      if (fileSize() > 0 && fileSize() < buffermaxsize) { //
        if (!buffered) {
          info("need to buffer file record: %s", path);
          return true;
        }
        if (mtime > btime) {
          info("re-buffer stale file record: %s", path);
          return true;
        }
      }else{
        info("file %s does not fit into the buffer (%d)", path, buffermaxsize);
      }
      return false;
    }

    /* Reads the file into the internal buffer, and compress the buffer to the enc buffer
       Updates the buffer time and status.
    */
    final void buffer() { synchronized {
      if(buf is null) buf = new char[](fileSize());
      buf.length = fileSize();
      try {
        if(fp is null) fp = new File(path, "rb");
        fp.open(path, "rb");
        fp.rawRead(buf);
        fp.close();
      } catch (Exception e) {
        warning("exception during buffering '%s': %s", path, e.msg);
        return;
      }
      try {
        encbuf = cast(char[])( compress(buf, 9) );
      } catch (Exception e) {
        warning("exception during compressing '%s': %s", path, e.msg);
      }
      btime = Clock.currTime();
      trace("buffered %s: %d|%d bytes", path, fileSize(), encbuf.length);
      buffered = true;
    } }

    /* Whole file content served via the bytes function */
    final @property string content(){ return( to!string(bytes(0, length)) ); }
    /* Is the file a real file (i.e. does it exist on disk) */
    final @property bool realfile() const { return(path.exists()); }
    /* Do we have a deflate encoded version */
    final @property bool hasEncodedVersion() const { return(encbuf !is null); }
    /* Is the file defined as static in mimetypes.d ? */
    final @property bool isStaticFile() { return(!path.isCGI()); }
    /* Time the file was last modified ? 
       TODO: Is there a BUG here related to encbuf update ? */
    final @property SysTime mtime() const { if(!realfile){ return btime; } return path.timeLastModified(); }
    /* Files are always assumed ready to be handled (unlike Common Gate Way threads)  */
    final @property long ready() { return(true); }
    /* Payload type delivered to the client  */
    final @property PayloadType type() const { return(PayloadType.Message); }
    /* Size of the file, -1 if it does not exist  */
    final @property ptrdiff_t fileSize() const { if(!realfile){ return -1; } return to!ptrdiff_t(path.getSize()); }
    /* Length of the buffer  */
    final @property long buffersize() const { return cast(long)(buf.length); }
    /* Mimetype of the file  */
    final @property string mimetype() const { return mime(path); }
    /* Status code for file is StatusCode.Ok ? 
       TODO: Shouldn't this be based on realfile ? */
    final @property StatusCode statuscode() const { return StatusCode.Ok; }
    /* Get the number of bytes that the client response has, based on encoding */
    final @property ptrdiff_t length() const {
      if(hasEncodedVersion && deflate) return(encbuf.length);
      return(fileSize());
    }

    /* Send the file from the underlying raw byte source stream using fseek, fp are closed */
    final char[] asStream(ptrdiff_t from, ptrdiff_t maxsize = 1024) {
      if(buf is null) buf = new char[](maxsize);
      char[] slice = [];
      if (cverbose >= DEBUG && from == 0) write("[STREAM] .");
      if (from >= fileSize()) {
        trace("from >= filesize, are we still trying to send?");
        return([]);
      }
      try {
        if(fp is null) fp = new File(path, "rb");
        fp.open(path, "rb");
        if(fp.isOpen()) {
          fp.seek(from);
          slice = fp.rawRead!char(buf);
          fp.close();
          if (cverbose >= DEBUG) write(".");
          if (cverbose >= DEBUG && (from + slice.length) >= fileSize()) write("\n");
        }
      } catch(Exception e) { 
        warning("exception %s while streaming file: %s", e.msg, path);
      }
      return(slice);
    }

    /* Get bytes in a lockfree manner from the correct underlying buffer */
    final char[] bytes(ptrdiff_t from, ptrdiff_t maxsize = 1024){ synchronized {
      if (!realfile) { return []; }
      trace("file provided is a real file");
      if (needsupdate) { buffer(); }
      if (!buffered) {
        return(asStream(from, maxsize));
      } else {
        if(hasEncodedVersion && deflate) {
          if(from < encbuf.length) return( encbuf[from .. to!ptrdiff_t(min(from+maxsize, $))] );
        } else {
          if(from < buf.length) return( buf[from .. to!ptrdiff_t(min(from+maxsize, $))] );
        }
      }
      return([]);
    } }
}

