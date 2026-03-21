/** danode/filesystem.d - File system abstraction: path resolution, security checks, directory listing
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.filesystem;

import danode.imports;

import danode.statuscode : StatusCode;
import danode.payload : Payload, PayloadType;
import danode.mimetypes : mime, CGI_FILE, UNSUPPORTED_FILE;
import danode.functions : has;
import danode.log : log, tag, error, Level;

/* Domain name structure containing files in that domain
   Domains are loaded by the FileSystem from the -wwwRoot variable (set to www/ by default)
   Note 1: Domains are named as requested by the HTTP client so SSL keynames must match domainnames (e.g.: localhost / 127.0.0.1 / XX.XX.XX.XX or xxx.xx)
   Note 2: ./www/localhost existing is required for unit testing */
struct Domain {
  FilePayload[string] files;

  @property long entries() const { return files.length; }
  @property long buffered() const { long n = 0; foreach(ref f; files.byValue) { if(f.isBuffered) n++; } return n; }
  @property long buffersize() const { long sum = 0; foreach(ref f; files.byKey){ sum += files[f].buffersize(); } return sum; }
  @property long size() const { long sum = 0; foreach(ref f; files.byKey){ sum += files[f].length(); } return sum; }
}

/* File system class that manages the underlying domains */
class FileSystem {
  private:
    string         root;
    Domain[string] domains;
    size_t         maxsize;

  public:
    this(string root = "./www/", size_t maxsize = 1024 * 512){
      this.root = buildNormalizedPath(absolutePath(root)).replace("\\", "/");
      if (!this.root.endsWith("/")) this.root ~= "/";
      this.maxsize  = maxsize;
      scan();
    }

    /* Scan the whole filesystem for changes */
    final void scan(){ synchronized {
      foreach (DirEntry d; dirEntries(root, SpanMode.shallow)){ if(d.name.isDIR()){
        domains[d.name] = scan(d.name);
      } }
      // Remove domains that no longer exist on disk
      foreach (k; domains.keys) { if (!exists(k)) domains.remove(k); }
    } }

    /* Scan a single folder */
    final Domain scan(string dname){ synchronized {
      Domain domain;
      try {
        foreach (DirEntry f; dirEntries(dname, SpanMode.depth)) {
          if (f.isFILE()) {
            string shortname = replace(f.name[dname.length .. $], "\\", "/");
            if (shortname.endsWith(".in") || shortname.endsWith(".up")) continue;
            log(Level.Trace, "File: '%s' as '%s'", f.name, shortname);
            if (!domain.files.has(shortname)) {
              domain.files[shortname] = new FilePayload(f.name, maxsize);
            }
          }
        }
      } catch (Exception e) { log(Level.Trace, "scan: directory iteration interrupted: %s", e.msg); }
      // Remove files that no longer exist on disk
      foreach (k; domain.files.keys) { if (!exists(dname ~ k)) { domain.files.remove(k); } }

      log(Level.Verbose, "Domain: '%s' files %s|%s", dname, domain.buffered, domain.entries);
      log(Level.Verbose, "Domain: '%s' size %.2f/%.2f kB", dname, domain.buffersize / 1024.0, domain.size / 1024.0);
      return(domain);
    } }

    /* Get the localroot of the domain */
    final string localroot(string hostname) const { return(format("%s%s", this.root, hostname)); }

    /* Get the FilePayload at path from the localroot, with update check on buffers */
    final FilePayload file(string localroot, string path){ synchronized {
      if (!(localroot in domains)) {
        log(Level.Verbose, "File: '%s' unknown domain '%s'", path, localroot);
        return new FilePayload("", maxsize);
      }
      if (!domains[localroot].files.has(path) && exists(format("%s%s", localroot, path))) {
        log(Level.Verbose, "File: '%s' new, rescanning index: %s", path, localroot);
        domains[localroot] = scan(localroot);
      }
      // File exists, buffer the individual file if modified after buffer date
      if (domains[localroot].files.has(path)) {
        if (domains[localroot].files[path].needsupdate) domains[localroot].files[path].buffer();
        return(domains[localroot].files[path]);
      }
      error("Should not be here, %s not in index, but exists %s", path, localroot);
      return new FilePayload("", maxsize);
    } }

    /* Rebuffer all file domains from disk, 
       By reusing domain keys so, we don't buffer new domains. This is ok since we would need to load SSL */
    final void rebuffer() { synchronized {
      foreach(ref d; domains.byValue) { foreach(ref f; d.files.byValue) { f.buffer(); } }
    } }
}

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
      if (!isStaticFile()) return false; // CGI files are never buffered, since they are executed
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
       Updates the buffer time and status.
    */
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
    final @property bool isStaticFile() { return(!path.isCGI()); }
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

pure bool isAllowed(in string path) { return(mime(path) != UNSUPPORTED_FILE); }
bool isFILE(in string path) { try { return(isFile(path)); } catch(Exception e) { error("isFILE: I/O exception '%s'", e.msg); } return false; }
bool isDIR(in string path) { try { return(isDir(path)); } catch(Exception e) { error("isDIR: I/O exception '%s'", e.msg); } return false; }
bool isCGI(in string path) {
  try { return(isFile(path) && mime(path).indexOf(CGI_FILE) >= 0);
  }catch(Exception e) { error("isCGI: I/O exception '%s'", e.msg); }
  return false;
}

// Write content into a file to disk
void writeFile(in string localpath, in string content) {
  try {
    auto fp = File(localpath, "wb");
    fp.rawWrite(content);
    fp.close();
    log(Level.Trace, "writeFile: %d bytes to: %s", content.length, localpath);
  } catch(Exception e) { error("writeFile: I/O exception '%s'", e.msg); }
}

// Which interpreter (if any) should be used for the path ?
string interpreter(in string path) {
  if (!isCGI(path)) return [];
  string[] parts = mime(path).split("/");
  if(parts.length > 1) return(parts[1]);
  return [];
}

pure string resolve(string path) { return(buildNormalizedPath(absolutePath(path)).replace("\\", "/")); }

string resolveFolder(string path) {
  path = path.resolve();
  path = (path.endsWith("/"))? path : path ~ "/";
  if (!exists(path)) mkdirRecurse(path);
  return(path);
}

// Returns null if path escapes root
string safePath(in string root, in string path) {
  if (path.canFind("..")) return null;
  if (path.canFind("\0")) return null;
  string full = root ~ (path.startsWith("/") ? path : "/" ~ path);
  try {
    string absroot = root.resolve();
    if (!absroot.endsWith("/")) absroot ~= "/";
    if (exists(full)) {
      string resolved = full.resolve();
      if (resolved != absroot[0..$-1] && !resolved.startsWith(absroot)) return null;
    } else {
      string parent = dirName(full).resolve();
      if (parent != absroot[0..$-1] && !parent.startsWith(absroot)) return null;
    }
  } catch (Exception e) { return null; }
  return full;
}

unittest {
  tag(Level.Always, "FILE", "%s", __FILE__);
  FileSystem fs = new FileSystem("./www/");

  // Local root
  assert(fs.localroot("localhost").length > 0, "localroot must resolve");
  // Domains
  Domain localdomain = fs.scan("www/localhost");
  assert(localdomain.buffersize() > 0, "buffersize must be positive");
  assert(localdomain.size() > 0, "size must be positive");
  // Files
  auto fp = fs.file(fs.localroot("localhost"), "/dmd.d");
  auto stream = new FileStream(fp);
  assert(stream.bytes(0, 6).length == 6, "FileStream must read 6 bytes");
  assert(fp.statuscode() == StatusCode.Ok, "file statuscode must be Ok");
  assert(fp.mimetype().length > 0, "file must have mimetype");
  assert(fp.type() == PayloadType.File, "type must be File");
  assert(fp.ready() > 0, "file must be ready");
  // isFILE / isDIR / isCGI
  assert(isFILE("danode/functions.d"), "functions.d must be a file");
  assert(!isFILE("danode"), "directory must not be a file");
  assert(isDIR("danode"), "danode must be a directory");
  assert(!isDIR("danode/functions.d"), "file must not be a directory");
  assert(isCGI("www/localhost/dmd.d"), "dmd.d must be CGI");
  assert(!isCGI("www/localhost/test.txt"),"txt must not be CGI");
  // interpreter
  assert(interpreter("www/localhost/dmd.d").length > 0, "dmd.d must have interpreter");
  assert(interpreter("www/localhost/php.php").length > 0, "php must have interpreter");
  assert(interpreter("www/localhost/test.txt").length == 0,"txt must have no interpreter");
  // safePath - security critical
  assert(safePath("www/localhost", "/../etc/passwd") is null, "path traversal .. must be blocked");
  assert(safePath("www/localhost", "/\0etc/passwd") is null, "null byte must be blocked");
  assert(safePath("www/localhost", "/test.txt") !is null, "valid path must be allowed");
  assert(safePath("www/localhost", "/test/1.txt") !is null, "valid subpath must be allowed");
  assert(safePath("www/localhost", "/nonexistent.txt") !is null, "non-existent valid path must be allowed");
  // isAllowed / isAllowedFile
  assert(isAllowed("test.html"), "html must be allowed");
  assert(isAllowed("test.txt"), "txt must be allowed");
  assert(!isAllowed("test.ill"), "unknown extension must be blocked");
}
