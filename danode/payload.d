/** danode/payload.d - Payload interface and Message type for server-generated responses
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.payload;

import danode.imports;

import danode.statuscode : StatusCode;
import danode.mimetypes : mime, isStaticFile, UNSUPPORTED_FILE;
import danode.log : log, tag, error, Level;

enum PayloadType { Message, Script, File }
enum HeaderType { None, FastCGI, HTTP10, HTTP11 }

/* Payload interface, Payload is carried by the Response structure, not the Request structure */
interface Payload {
  public:
    @property bool ready();
    @property StatusCode statuscode() const;
    @property PayloadType type() const;
    @property ptrdiff_t length() const;
    @property SysTime mtime();
    @property string mimetype() const;

    const(char)[] bytes(ptrdiff_t from, ptrdiff_t maxsize = 4096, bool isRange = false, long start = 0, long end = -1);
}

/* Implementation of the Payload interface, by using an underlying string buffer */
class Message : Payload {
  private:
    StatusCode status;
    string message;
    string mime;

  public:
    this(StatusCode status, string message = "", string mime = UNSUPPORTED_FILE) {
      this.status = status;
      this.message = message;
      this.mime = mime;
    }

    final @property PayloadType type() const { return(PayloadType.Message); }
    final @property bool ready() { return(true); }
    final @property ptrdiff_t length() const { return(message.length); }
    final @property SysTime mtime() { return SysTime.init; }
    final @property string mimetype() const { return mime; }
    final @property StatusCode statuscode() const { return status; }
    char[] bytes(ptrdiff_t from, ptrdiff_t maxsize = 4096, bool isRange = false, long start = 0, long end = -1) {
      return( message[from .. to!ptrdiff_t(min(from + maxsize, $))].dup );
    }
}

/* Implementation of the Payload interface, by using an underlying file (static / deflate / cgi) */
class FilePayload : Payload {
  public:
    bool      gzip = false; // Is a gzip version of the file available ?

  private:
    string    path; // Path of the file
    SysTime   btime; // Time buffered
    bool      buffered = false; // Is buffered ?
    size_t    buffermaxsize; // Maximum size of the buffer
    char[]    buf = null; // Byte buffer of the file
    char[]    encbuf = null; // Encoded buffer for the file

  public:
    this(string path, size_t buffermaxsize) {
      this.path = path;
      this.buffermaxsize = buffermaxsize;
      this.buffer();
    }

    /* Does the file require to be updated before sending ? */
    final bool needsupdate() {
      if (!path.isStaticFile()) return false; // CGI files are never buffered, since they are executed
      ptrdiff_t sz = fileSize();
      if (sz > 0 && sz < buffermaxsize) { //
        if (!buffered) { log(Level.Trace, "File: '%s' needs buffering", path); return true; }
        if (mtime > btime) { log(Level.Trace, "File: '%s' stale record", path); return true; }
      }else{
        log(Level.Verbose, "File: '%s' exceeds buffer (%.1fkb > %.1fkb)", path, sz / 1024f, buffermaxsize / 1024f);
      }
      return false;
    }

    /* Reads the file into the internal buffer, and compress the buffer to the enc buffer
       Updates the buffer time and status. */
    final bool buffer() { synchronized {
      if (!needsupdate()) return(false);  // re-check under lock
      ptrdiff_t sz = fileSize();
      if(buf is null) buf = new char[](sz);
      buf.length = sz;
      try {
        auto f = File(path, "rb");
        f.rawRead(buf);
        f.close();
      } catch (Exception e) { error("Exception during buffering '%s': %s", path, e.msg); return(false); }
      try {
        auto c = new Compress(6, HeaderFormat.gzip);
        encbuf = cast(char[])(c.compress(buf));
        encbuf ~= cast(char[])(c.flush());
      } catch (Exception e) { error("Exception during compressing '%s': %s", path, e.msg); return(false); }
      btime = Clock.currTime();
      log(Level.Trace, "File: '%s' buffered %.1fkb|%.1fkb", path, sz / 1024f, encbuf.length / 1024f);
      return(buffered = true);
    } }

    /* Get bytes in a lockfree manner from the correct underlying buffer */
    final const(char)[] bytes(ptrdiff_t from, ptrdiff_t maxsize = 4096, bool isRange = false, long start = 0, long end = -1) { synchronized {
      if (!realfile) { return []; }
      if (needsupdate) { buffer();  if (!buffered) { log(Level.Verbose, "FilePayload.bytes() failed to buffer '%s'", path); return([]); } }
      auto r = rangeCalc(from, maxsize, isRange, start, end);
      log(Level.Trace, "bytes: isRange=%s start=%d end=%d from=%d offset=%d sz=%d", isRange, start, end, from, r[0], r[1]);
      if(hasEncodedVersion && gzip) {
        if(r[0] < encbuf.length) return( encbuf[r[0] .. to!ptrdiff_t(min(r[0]+r[1], $))] );
      } else {
        if(r[0] < buf.length) return( buf[r[0] .. to!ptrdiff_t(min(r[0]+r[1], $))] );
      }
      log(Level.Verbose, "FilePayload.bytes() called on unbuffered file '%s', this should not happen", path);
      return([]);
    } }

    final @property string content(){ return( to!string(bytes(0, length)) ); }
    final @property bool realfile() const { return(path.exists()); }
    final @property bool hasEncodedVersion() const { return(encbuf !is null); }
    final @property SysTime mtime() const { try { return path.timeLastModified(); }catch (Exception e) { return btime; } }
    final @property bool ready() { return(true); }
    final @property PayloadType type() const { return(PayloadType.File); }
    final @property ptrdiff_t fileSize() const { if(!realfile){ return -1; } return to!ptrdiff_t(path.getSize()); }
    final @property long buffersize() const { return cast(long)(buf.length); }
    final @property string mimetype() const { return mime(path); }
    final @property bool isBuffered() const { return buffered; }
    final @property string filePath() const { return path; }
    final @property StatusCode statuscode() const { return realfile ? StatusCode.Ok : StatusCode.NotFound; }
    final @property ptrdiff_t length() const { if(hasEncodedVersion && gzip) { return(encbuf.length); } return(fileSize()); }
}

/* Per-client streaming wrapper around a shared FilePayload. Keeps its own File handle open for the duration of streaming,
   avoiding repeated open/seek/close per chunk. */
class FileStream : Payload {
  private:
    FilePayload payload;
    File handle;

  public:
    this(FilePayload payload) {
      this.payload = payload;
      if (payload.realfile) {
        try { handle = File(payload.filePath(), "rb"); }
        catch (Exception e) { log(Level.Verbose, "FileStream: failed to open '%s': %s", payload.filePath(), e.msg); }
      }
    }

    final @property PayloadType type() const { return PayloadType.File; }
    final @property bool ready() { return payload.ready(); }
    final @property ptrdiff_t length() const { return payload.length(); }
    final @property SysTime mtime() { return payload.mtime(); }
    final @property string mimetype() const { return payload.mimetype(); }
    final @property StatusCode statuscode() const { return payload.statuscode(); }

    final const(char)[] bytes(ptrdiff_t from, ptrdiff_t maxsize = 4096, bool isRange = false, long start = 0, long end = -1) {
      // If buffered, delegate to the shared in-memory buffer — no file handle needed
      if (payload.isBuffered()) { return payload.bytes(from, maxsize, isRange, start, end); }
      if (!handle.isOpen()) return [];
      auto r = rangeCalc(from, maxsize, isRange, start, end);
      if (r[0] >= payload.fileSize()) return [];
      try {
        char[] tmpbuf = new char[](r[1]);
        handle.seek(r[0]);
        return handle.rawRead!char(tmpbuf).dup;
      } catch (Exception e) { log(Level.Verbose, "FileStream.bytes exception '%s': %s", payload.filePath(), e.msg); return []; }
    }
}

// Compute the Range
@nogc pure ptrdiff_t[2] rangeCalc(ptrdiff_t from, ptrdiff_t maxsize, bool isRange, long start, long end) nothrow {
  ptrdiff_t offset = isRange ? to!ptrdiff_t(start) + from : from;
  ptrdiff_t limit = isRange ? to!ptrdiff_t(end - start + 1) : -1;
  ptrdiff_t sz = (limit > 0) ? to!ptrdiff_t(min(maxsize, max(0, limit - from))) : maxsize;
  return [offset, sz];
}
