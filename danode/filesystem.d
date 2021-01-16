module danode.filesystem;

import danode.imports;
import danode.statuscode : StatusCode;
import danode.mimetypes : mime;
import danode.payload : Payload, FilePayload, PayloadType;
import danode.functions : has, isCGI;
import danode.log : custom, info, Log, warning, trace, cverbose, NOTSET, NORMAL, DEBUG;

/* Domain name structure containing files in that domain
   Domains are loaded by the FileSystem from the -wwwRoot variable (set to www/ by default)
   Note 1: Domains are named as requested by the HTTP client so SSL keynames must match domainnames (e.g.: localhost / 127.0.0.1 / XX.XX.XX.XX or xxx.xx)
   Note 2: ./www/localhost existing is required for unit testing */
struct Domain {
  FilePayload[string] files;
  long entries;
  long buffered;

  @property long buffersize() const { long sum = 0; foreach(ref f; files.byKey){ sum += files[f].buffersize(); } return sum; }
  @property long size() const { long sum = 0; foreach(ref f; files.byKey){ sum += files[f].length(); } return sum; }
}

/* File system class that manages the underlying domains
   Note: Should this really be thread synchronized access ?
 */
class FileSystem {
  private:
    string         root;
    Domain[string] domains;
    Log            logger;
    size_t         maxsize;

  public:
    this(Log logger, string root = "./www/", size_t maxsize = 1024 * 512){
      this.logger   = logger;
      this.root     = root;
      this.maxsize  = maxsize;
      scan();
    }

    /* Scan the whole filesystem for changes */
    final void scan(){ synchronized {
      foreach (DirEntry d; dirEntries(root, SpanMode.shallow)){ if(d.isDir()){
        domains[d.name] = scan(d.name);
      } }
    } }

    /* Scan a single folder */
    final Domain scan(string dname){ synchronized {
      Domain domain;
      foreach (DirEntry f; dirEntries(dname, SpanMode.depth)) {
        if (f.isFile()) {
          string shortname = replace(f.name[dname.length .. $], "\\", "/");
          custom(1, "SCAN", "file: %s -> %s", f.name, shortname);
          if (!domain.files.has(shortname)) {
            domain.files[shortname] = new FilePayload(f.name, maxsize);
            domain.entries++;
            if (domain.files[shortname].needsupdate()) {
              domain.files[shortname].buffer();
              domain.buffered++;
            }
          }
        }
      }
      custom(1, "SCAN", "domain: %s, files %s|%s", dname, domain.buffered, domain.entries);
      custom(1, "SCAN", "%s = size: %.2f/%.2f kB", dname, domain.buffersize / 1024.0, domain.size / 1024.0);
      return(domain);
    } }

    /* Get the localroot of the domain (TODO is there a bug, did I asumme this.root should always end in a /) */
    final string localroot(string hostname) const { return(format("%s%s", this.root, hostname)); }

    /* Get the FilePayload at path from the localroot, with update check on buffers */
    final FilePayload file(string localroot, string path){ synchronized {
      if(!domains[localroot].files.has(path) && exists(format("%s%s", localroot, path))){
        custom(1, "SCAN", "new file %s, rescanning index: %s", path, localroot);
        domains[localroot] = scan(localroot);
      }
      if(domains[localroot].files.has(path)) return(domains[localroot].files[path]);
      return new FilePayload("", maxsize);
    } }

    /* Rebuffer all file domains from disk, 
       By reusing domain keys so, we don't buffer new domains. This is ok since we would need to load SSL */
    final void rebuffer() {
      foreach(ref d; domains.byKey){ foreach(ref f; domains[d].files.byKey){
        domains[d].files[f].buffer();
      } }
    }
}

/* Basic unit-tests should be extended */
unittest {
  custom(0, "FILE", "%s", __FILE__);
  Log logger = new Log(NORMAL);
  FileSystem filesystem = new FileSystem(logger, "./www/");
  custom(0, "TEST", "./www/localhost/dmd.d (6 bytes) = %s", filesystem.file("./www/localhost", "/dmd.d").bytes(0,6));
  custom(0, "TEST", "filesystem.localroot('localhost') = %s", filesystem.localroot("localhost"));
  Domain localhost = filesystem.scan("www/localhost");
  custom(0, "TEST", "localhost.buffersize() = %s", localhost.buffersize());
  custom(0, "TEST", "localhost.size() = %s", localhost.size());
  auto file = filesystem.file(filesystem.localroot("localhost"), "localhost/dmd.d");
  custom(0, "TEST", "file.asStream(0) = %s", file.asStream(0));
  custom(0, "TEST", "file.statuscode() = %s", file.statuscode());
  custom(0, "TEST", "file.mimetype() = %s", file.mimetype());
  custom(0, "TEST", "file.mtime() = %s", file.mtime());
  custom(0, "TEST", "file.ready() = %s", file.ready());
  custom(0, "TEST", "file.type() = %s", file.type());
  custom(0, "TEST", "file.content() = %s", file.content());
}

