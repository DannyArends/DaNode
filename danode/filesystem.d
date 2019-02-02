module danode.filesystem;

import std.stdio, std.conv, std.datetime, std.file, std.math;
import std.string : replace, format;
import std.zlib : compress;

import danode.httpstatus : StatusCode;
import danode.mimetypes : mime;
import danode.payload : Payload, PayLoadType;
import danode.functions : has, isCGI;
import danode.log : Log, NORMAL, INFO, DEBUG;

class FileInfo : Payload {
  public:
    bool      deflate = false;
  private:
    string    path;
    SysTime   btime;
    bool      buffered = false;
    char[]    buf = null;
    char[]    encbuf = null;
    File*     fp = null;
    int       verbose = NORMAL;

  public:
    this(string path){ this.path = path; }

    final bool needsupdate(size_t buffersize = 4096, int verbose = NORMAL) {
      this.verbose = verbose;
      if( fitsInBuffer(buffersize) && needsBuffer() ) {
        if (!buffered) {
          if(verbose >= INFO) writefln("[INFO]   Need to buffering file record: %s", path);
          return true;
        }
        if (mtime > btime) {
          if(verbose >= INFO) writefln("[INFO]   Rebuffering stale record: %s", path);
          return true;
        }
      }
      return false;
    }

    final bool fitsInBuffer(size_t buffersize = 4096) {
      if(fileSize() > 0 && fileSize() < buffersize){ return(true); }
      return(false);
    }

    final void buffer(int verbose = NORMAL) { synchronized {
      this.verbose = verbose;
      if(buf is null) buf = new char[](fileSize());
      buf.length = fileSize();
      try {
        if(fp is null) fp = new File(path, "rb");
        fp.open(path, "rb");
        fp.rawRead(buf);
        fp.close();
      } catch (Exception e) {
        writefln("[WARN]   exception while buffering '%s': %s", path, e.msg);
        return;
      }
      try {
        encbuf = cast(char[])( compress(buf, 9) );
      } catch (Exception e) {
        writefln("[WARN]   exception while compressing '%s': %s", path, e.msg);
      }
      btime = Clock.currTime();
      if(verbose >= DEBUG) writefln("[DEBUG]  buffered %s: %d|%d bytes", path, fileSize(), encbuf.length);
      buffered = true;
    } }

    final @property string content(){ return( to!string(bytes(0, length)) ); }
    final @property bool realfile() const { return(path.exists()); }
    final @property bool hasEncodedVersion() const { return(encbuf !is null); }
    final @property bool needsBuffer() { return(!path.isCGI()); }
    final @property SysTime mtime() const { if(!realfile){ return btime; } return path.timeLastModified(); }
    final @property long ready() { return(true); }
    final @property PayLoadType type() const { return(PayLoadType.Message); }
    final @property ptrdiff_t fileSize() const { if(!realfile){ return -1; } return to!ptrdiff_t(path.getSize()); }
    final @property long buffersize() const { return cast(long)(buf.length); }
    final @property string mimetype() const { return mime(path); }
    final @property StatusCode statuscode() const { return StatusCode.Ok; }

    final @property ptrdiff_t length() const {
      if(hasEncodedVersion && deflate) return(encbuf.length);
      return(fileSize());
    }

    final char[] asStream(ptrdiff_t from, ptrdiff_t maxsize = 1024) {
      if(buf is null) buf = new char[](maxsize);
      char[] slice = [];
      if (verbose >= DEBUG && from == 0) write("[STREAM] .");
      if (from >= fileSize()) {
        if(verbose >= DEBUG) writeln("[DEBUG]  from >= filesize, are we still trying to send?");
        return([]);
      }
      try {
        if(fp is null) fp = new File(path, "rb");
        fp.open(path, "rb");
        if(fp.isOpen()) {
          fp.seek(from);
          slice = fp.rawRead!char(buf);
          fp.close();
          if(verbose >= DEBUG) write(".");
          if (verbose >= DEBUG && (from + slice.length) >= fileSize()) write("\n");
        }
      } catch(Exception e) { 
        writefln("[WARN]   exception %s while streaming file: %s", e.msg, path);
      }
      return(slice);
    }

    final char[] bytes(ptrdiff_t from, ptrdiff_t maxsize = 1024){ synchronized {
      if (!realfile) { return []; }
      if(verbose >= DEBUG) writeln("[DEBUG]  Real file");
      if (needsupdate) { buffer(); }
      if (!buffered) {
        return(asStream(from, maxsize));
      } else {
        if(hasEncodedVersion && deflate) {
          if(from < encbuf.length) return( encbuf[from .. to!ptrdiff_t(fmin(from+maxsize, $))] );
        } else {
          if(from < buf.length) return( buf[from .. to!ptrdiff_t(fmin(from+maxsize, $))] );
        }
      }
      return([]);
    } }
}

struct Domain {
  FileInfo[string] files;
  long entries;
  long buffered;

  @property long buffersize() const { long sum = 0; foreach(ref f; files.byKey){ sum += files[f].buffersize(); } return sum; }
  @property long size() const { long sum = 0; foreach(ref f; files.byKey){ sum += files[f].length(); } return sum; }
}

class FileSystem {
  private:
    string            root;
    Domain[string]    domains;
    Log               logger;
    long              maxsize;

  public:
    this(Log logger, string root = "./www/", int maxsize = 1024 * 512){
      this.logger   = logger;
      this.root     = root;
      this.maxsize  = maxsize;
      scan();
    }

    final void scan(){ synchronized {
      foreach (DirEntry d; dirEntries(root, SpanMode.shallow)){ if(d.isDir()){
        domains[d.name] = scan(d.name);
      } }
    } }

    final Domain scan(string dname){ synchronized {
      Domain domain;
      foreach (DirEntry f; dirEntries(dname, SpanMode.depth)) {
        if (f.isFile()) {
          string shortname = replace(f.name[dname.length .. $], "\\", "/");
          if (logger.verbose >= INFO) writefln("[SCAN]   File: %s -> %s", f.name, shortname);
          if (!domain.files.has(shortname)) {
            domain.files[shortname] = new FileInfo(f.name);
            domain.entries++;
            if (domain.files[shortname].needsupdate(maxsize)) {
              domain.files[shortname].buffer(logger.verbose);
              domain.buffered++;
            }
          }
        }
      }
      if (logger.verbose >= INFO) {
        writef("[INFO]   domain: %s, files %s|%s", dname, domain.buffered, domain.entries);
        writefln(", size: %.2f/%.2f kB", domain.buffersize/1024.0, domain.size/1024.0);
      }
      return(domain);
    } }

    final string localroot(string hostname) const { return(format("%s%s",this.root, hostname)); }

    final FileInfo file(string localroot, string path, int verbose = NORMAL){ synchronized {
      if(!domains[localroot].files.has(path) && exists(format("%s%s", localroot, path))){
        if(logger.verbose >= INFO) writefln("[FILES]  new file %s, rescanning index: %s", path, localroot);
        domains[localroot] = scan(localroot);
      }
      if(domains[localroot].files.has(path)) return(domains[localroot].files[path]);
      return new FileInfo("");
    } }

    final void rebuffer(){
      foreach(ref d; domains.byKey){ foreach(ref f; domains[d].files.byKey){
        domains[d].files[f].buffer();
      } }
    }
}

unittest {
  import std.stdio : writefln;
  writefln("[FILE]   %s", __FILE__);
  Log             logger = new Log(1);
  FileSystem      filesystem = new FileSystem(logger, "./test");
  writefln("[TEST]   ./test/server.files/server.conf (12 bytes): %s", filesystem.file("./test/server.files","/server.conf").bytes(0,12));
}

