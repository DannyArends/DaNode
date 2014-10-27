module danode.filesystem;

import std.stdio, std.string, std.conv, std.datetime, std.file, std.math;
import danode.mimetypes : mime;
import danode.payload : StatusCode, Payload, PayLoadType;
import danode.functions : has;
import danode.log : Log, NORMAL, INFO, DEBUG;

class FileInfo : Payload {
  private:
    string    path;
    SysTime   btime;
    bool      buffered = false;
    ubyte[]   buf;
    char[]    slice;

  public:
    this(string path){ this.path = path; }

    final bool needsupdate(int verbose = NORMAL) {
      if(!buffered) return true;
      if(mtime > btime){ if(verbose >= INFO) writefln("[INFO]   rebuffering stale record: %s", path); 
        return true;
      }
      return false;
    }

    final void unbuffer(int verbose = NORMAL) {
      ubyte[]   buf   = null;
      char[]    slice = null;
      buffered        = false;
    }

    final bool buffer(long maxsize = 4096, int verbose = NORMAL) { synchronized {
      if(length > 0 && length < maxsize && needsupdate(verbose)){
        buf = new ubyte[](length);
        try{
          auto fp = new File(path, "rb");
          fp.rawRead(buf);
          fp.close();
        }catch(Exception e){
          writefln("[WARN]   exception %s while buffering file: %s", e.msg, path);
        }
        btime = Clock.currTime();
        if(verbose >= DEBUG) writefln("[DEBUG]  buffered %s: %s bytes", path, length);
        return(buffered = true);
      }
      return(false);
    } }

    final @property string        content(){ return(cast(string)bytes(0, length)); }
    final @property bool          realfile() const { return(path.exists()); }
    final @property SysTime       mtime() const { if(!realfile){ return btime; } return path.timeLastModified(); }
    final @property long          ready(){ return(true); }
    final @property PayLoadType   type(){ return(PayLoadType.Message); }
    final @property long          length() const { if(!realfile){ return 0; } return cast(long)(path.getSize()); }
    final @property long          buffersize() const { return cast(long)(buf.length); }
    final @property string        mimetype() const { return mime(path); }
    final @property StatusCode    statuscode(){ return StatusCode.Ok; }

    final char[] bytes(long from, long maxsize = 1024){ synchronized {
      if(!realfile){ return []; }
      if(needsupdate) buffer();
      if(!buffered){
        buf = new ubyte[](maxsize);
        try{
          auto fp = new File(path, "rb");
          fp.seek(from);
          slice = cast(char[])fp.rawRead(buf);
          fp.close();
        }catch(Exception e){ writefln("[WARN]   exception %s while streaming file: %s", e.msg, path); }
        return(slice);
      }else if(from < buf.length){
        return(cast(char[]) buf[from .. cast(ulong)fmin(from+maxsize, $)]);
      }
      return([]);
    } }
}

struct Domain {
  FileInfo[string] files;
  long             entries;
  long             buffered;

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
    this(Log logger, string root = "./www/", int maxsize = 4096){
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
      foreach (DirEntry f; dirEntries(dname, SpanMode.depth)){ if(f.isFile()){
        string shortname = f.name[dname.length .. $];
        if(!domain.files.has(shortname)){
          domain.files[shortname] = new FileInfo(f.name);
          domain.entries++;
          if(domain.files[shortname].buffer(maxsize, logger.verbose)) domain.buffered++;
        }
      } }
      if(logger.verbose >= INFO)
        writefln("[INFO]   domain: %s, files %s|%s, size: %.2f/%.2f kB", dname, domain.buffered, domain.entries, domain.buffersize/1024.0, domain.size/1024.0);
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

