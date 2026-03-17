module danode.files;

import danode.imports;
import danode.statuscode : StatusCode;
import danode.mimetypes : mime;
import danode.payload : Payload, PayloadType, Message;
import danode.log : log, tag, error, Level;
import danode.functions : isCGI, htmltime;
import danode.request : Request;
import danode.response : Response, notModified;
import danode.filesystem : FileSystem;

/* Per-client streaming wrapper around a shared FilePayload.
   Keeps its own File handle open for the duration of streaming,
   avoiding repeated open/seek/close per chunk. */
class FileStream : Payload {
  private:
    FilePayload payload;
    File        handle;

  public:
    this(FilePayload payload) {
      this.payload = payload;
      if (payload.realfile) {
        try { handle = File(payload.filePath(), "rb"); }
        catch (Exception e) { log(Level.Verbose, "FileStream: failed to open '%s': %s", payload.filePath(), e.msg); }
      }
    }

    final @property PayloadType type() const { return PayloadType.File; }
    final @property long ready() { return payload.ready(); }
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
    }

    /* Does the file require to be updated before sending ? */
    final bool needsupdate() {
      if (!isStaticFile()) return false; // CGI files are never buffered, since they are executed
      if (fileSize() > 0 && fileSize() < buffermaxsize) { //
        if (!buffered) { log(Level.Trace, "File: '%s' needs buffering", path); return true; }
        if (mtime > btime) { log(Level.Trace, "File: '%s' stale record", path); return true; }
      }else{
        log(Level.Verbose, "File: '%s' exceeds buffer (%dkb > %dkb)", path, fileSize() / 1024, buffermaxsize / 1024);
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
        auto f = File(path, "rb");
        f.rawRead(buf);
        f.close();
      } catch (Exception e) { error("Exception during buffering '%s': %s", path, e.msg); return; }
      try {
        auto c = new Compress(6, HeaderFormat.gzip);
        encbuf = cast(char[])(c.compress(buf));
        encbuf ~= cast(char[])(c.flush());
      } catch (Exception e) { error("Exception during compressing '%s': %s", path, e.msg); }
      btime = Clock.currTime();
      log(Level.Trace, "File: '%s' buffered %d|%d bytes", path, fileSize(), encbuf.length);
      buffered = true;
    } }

    /* Whole file content served via the bytes function */
    final @property string content(){ return( to!string(bytes(0, length)) ); }
    /* Is the file a real file (i.e. does it exist on disk) */
    final @property bool realfile() const { return(path.exists()); }
    /* Do we have a gzip encoded version */
    final @property bool hasEncodedVersion() const { return(encbuf !is null); }
    /* Is the file defined as static in mimetypes.d ? */
    final @property bool isStaticFile() { return(!path.isCGI()); }
    /* Time the file was last modified ? */
    final @property SysTime mtime() const { if(!realfile){ return btime; } return path.timeLastModified(); }
    /* Files are always assumed ready to be handled (unlike Common Gate Way threads)  */
    final @property long ready() { return(true); }
    /* Payload type delivered to the client  */
    final @property PayloadType type() const { return(PayloadType.File); }
    /* Size of the file, -1 if it does not exist  */
    final @property ptrdiff_t fileSize() const { if(!realfile){ return -1; } return to!ptrdiff_t(path.getSize()); }
    /* Length of the buffer  */
    final @property long buffersize() const { return cast(long)(buf.length); }
    /* Mimetype of the file  */
    final @property string mimetype() const { return mime(path); }
    /* Buffer status of the file  */
    final @property bool isBuffered() const { return buffered; }
    /* Path of the file  */
    final @property string filePath() const { return path; }
    /* Status code for file is StatusCode.Ok ? */
    final @property StatusCode statuscode() const { 
      return realfile ? StatusCode.Ok : StatusCode.NotFound; 
    }
    /* Get the number of bytes that the client response has, based on encoding */
    final @property ptrdiff_t length() const {
      if(hasEncodedVersion && gzip) return(encbuf.length);
      return(fileSize());
    }

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
}

// Compute the Range
@nogc pure ptrdiff_t[2] rangeCalc(ptrdiff_t from, ptrdiff_t maxsize, bool isRange, long start, long end) nothrow {
  ptrdiff_t offset = isRange ? to!ptrdiff_t(start) + from : from;
  ptrdiff_t limit = isRange ? to!ptrdiff_t(end - start + 1) : -1;
  ptrdiff_t sz = (limit > 0) ? to!ptrdiff_t(min(maxsize, max(0, limit - from))) : maxsize;
  return [offset, sz];
}

// Should the file be compressed ?
bool isCompressible(string mime) {
  return mime.startsWith("text/") || mime == "application/json" || mime == "application/javascript" || mime == "image/svg+xml";
}

// Serve a static file from the disc, send encrypted when requested and available
void serveStaticFile(ref Response response, in Request request, FileSystem fs) {
  log(Level.Trace, "serving a static file");
  FilePayload reqFile = fs.file(fs.localroot(request.shorthost()), request.path);

  if (request.ifModified >= reqFile.mtime()) { return(response.notModified(reqFile.mimetype)); }
  if (reqFile.needsupdate()) reqFile.buffer();
  if (request.hasRange) { return(response.serveRangeFile(request, reqFile)); }

  if (request.acceptsEncoding("gzip") && reqFile.hasEncodedVersion && isCompressible(reqFile.mimetype)) {
    log(Level.Verbose, "will serve %s with gzip encoding", request.path);
    reqFile.gzip = true;
    response.customheader("Content-Encoding", "gzip");
  }
  response.payload = new FileStream(reqFile);
  if (!reqFile.gzip) response.customheader("Accept-Ranges", "bytes");
  response.ready = true;
}

// Serve a File Range from a static file on disc
void serveRangeFile(ref Response response, in Request request, FilePayload reqFile) {
  long[2] r = request.range();
  long total = reqFile.fileSize();
  long start = r[0];
  long end = r[1] < 0 ? total - 1 : r[1];
  if (start >= total || end >= total || start > end) {
    response.payload = new Message(StatusCode.RangeNotSatisfiable);
    response.customheader("Content-Range", format("bytes */%d", total));
  } else {
    response.customheader("Content-Range", format("bytes %d-%d/%d", start, end, total));
    response.customheader("Accept-Ranges", "bytes");
    response.rangeStart = start;
    response.rangeEnd = end;
    response.isRange = true;
    response.payload = new FileStream(reqFile);
    log(Level.Trace, "serveRangeFile: serving %d bytes", end - start + 1);
  }
  response.ready = true;
}

unittest {
  import danode.interfaces : StringDriver;
  import danode.router : Router, runRequest;

  tag(Level.Always, "FILE", "%s", __FILE__);

  auto router = new Router("./www/", Address.init);
  StringDriver res;

  // Route 1: 304 Not Modified
  res = router.runRequest("GET /index.html HTTP/1.1\nHost: localhost\nIf-Modified-Since: " ~ htmltime(Clock.currTime + 1.hours) ~ "\n\n");
  assert(res.lastStatus == StatusCode.NotModified, format("Expected 304, got %d", res.lastStatus.code));

  // Route 2: Range request
  res = router.runRequest("GET /test.pdf HTTP/1.1\nHost: localhost\nRange: bytes=0-1023\n\n");
  assert(res.lastStatus == StatusCode.PartialContent, format("Expected 206, got %d", res.lastStatus.code));

  // Route 3: Gzip compression
  res = router.runRequest("GET /index.html HTTP/1.1\nHost: localhost\nAccept-Encoding: gzip\n\n");
  assert(res.lastStatus == StatusCode.Ok, format("Expected 200, got %d", res.lastStatus.code));
  assert(res.lastHeaders.get("Content-Encoding", "") == "gzip", "Expected gzip Content-Encoding header");
}

