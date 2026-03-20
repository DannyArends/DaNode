/** danode/webconfig.d - Server configuration and per-domain web.config parsing: CGI, redirects, directory access control
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.webconfig;

import danode.imports;

import danode.functions : has, from;
import danode.files : FilePayload;
import danode.log : log, tag, Level;

__gshared ServerConfig serverConfig;
__gshared Mutex serverConfigMutex;

shared static this() { serverConfigMutex = new Mutex(); }

struct Config {
  string[string] data;
  SysTime mtime;
}

Config parseConfig(string content, string def = "no") {
  Config config;
  foreach (line; split(content, "\n")) {
    if (chomp(strip(line)) == "" || line[0] == '#') continue;
    auto parts = line.split("=");
    string key = toLower(chomp(strip(parts[0])));
    if (parts.length == 1) {
      config.data[key] = def;
    } else if (parts.length >= 2) {
      config.data[key] = toLower(chomp(strip(join(parts[1 .. $], "="))));
    }
  }
  return config;
}

struct ServerConfig {
  private:
    Config config;
    alias config this;

  public:
    this(string path) {
      if (!exists(path)) { log(Level.Trace, "No server.config at: '%s'", path); return; }
      config = parseConfig(readText(path));
      config.mtime = timeLastModified(path);
    }

    T get(T)(string key, T def) { synchronized(serverConfigMutex) {
      try { return to!T(data.from(key, to!string(def))); }
      catch (Exception e) { return def; }
    } }
}

struct WebConfig {
  private:
    Config config;
    alias config this;

    @nogc bool flag(string key, string def, string match) const nothrow { return data.from(key, def) == match; }

  public:
    this(FilePayload file, string def = "no") {
      config = parseConfig(file.content, def);
      config.mtime = file.mtime;
    }

    @property string domain(string shorthost) const { return flag("shorturl", "yes", "yes") ? shorthost : format("www.%s", shorthost); }
    @property @nogc bool allowcgi() const nothrow { return flag("allowcgi", "no", "yes"); }
    @property @nogc bool redirect() const nothrow { return !flag("redirect", "/",  "/"); }
    @property @nogc bool redirectdir() const nothrow { return !flag("redirectdir","no", "no"); }
    @property string index() const { string to = data.from("redirect", "/"); if (to[0] != '/') { return(format("/%s", to)); } return(to); }
    @property string[] allowdirs() const nothrow { return(data.from("allowdirs", "/").split(",")); }

    // Is the directory allowed to be viewed ?
    @property bool dirAllowed(in string localroot, in string path) const {
      string root = localroot.endsWith("/") ? localroot : localroot ~ "/";
      string p = path.startsWith(root) ? path : path.replace(localroot, root);
      if (p.length <= root.length) return true;
      string npath = p[root.length .. $];
      foreach (d; allowdirs) { if (indexOf(strip(npath), strip(d)) == 0) return true; }
      return false;
    }
}

WebConfig getConfig(ref WebConfig[string] configs, FilePayload fp, string key) {
  if (key !in configs || fp.mtime > configs[key].mtime) { configs[key] = WebConfig(fp); }
  return configs[key];
}

unittest {
  tag(Level.Always, "FILE", "%s", __FILE__);
  import danode.filesystem : FileSystem;

  FileSystem fs = new FileSystem("./www/");
  auto fp = fs.file(fs.localroot("localhost"), "/web.config");
  WebConfig config = WebConfig(fp);

  // localhost web.config has: shorturl=yes, allowcgi=yes, redirect=dmd.d, allowdirs=ddoc/,test/
  assert(config.allowcgi, "allowcgi must be yes");
  assert(config.redirect(), "redirect must be set");
  assert(config.domain("localhost") == "localhost", "shorturl=yes must return shorthost");
  assert(config.index() == "/dmd.d", "index must be /dmd.d");
  assert(!config.redirectdir(), "redirectdir must be no");

  // dirAllowed
  string localroot = fs.localroot("localhost");
  assert(config.dirAllowed(localroot, localroot), "root dir must be allowed");
  assert(config.dirAllowed(localroot, localroot ~ "test/"), "test/ must be allowed");
  assert(!config.dirAllowed(localroot, localroot ~ "etc/"), "etc/ must not be allowed");

  // shorturl=no → www. prefix
  WebConfig noShort = WebConfig(fp);
  noShort.data["shorturl"] = "no";
  assert(noShort.domain("localhost") == "www.localhost", "shorturl=no must add www.");

  ServerConfig sc = ServerConfig("nonexistent.config");
  assert(sc.maxClients()      == 2048, "default maxClients must be 2048");
  assert(sc.maxClientsPerIP() == 32, "default maxClientsPerIP must be 32");
  assert(sc.poolSize()        == 200, "default poolSize must be 200");
  assert(sc.serverInfo()      == "DaNode/0.0.3", "default serverInfo must be set");
}

