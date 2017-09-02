module danode.ssl;

version(SSL){

  import std.socket;
  import std.file;
  import std.path : baseName;
  import std.traits;
  import std.string;
  import std.algorithm;
  import core.thread;
  import core.stdc.stdlib : malloc, realloc, free;
  import std.conv : to;
  import std.stdio : writefln, writeln;
  import core.stdc.stdio;
  import danode.client;

  import deimos.openssl.ssl;
  import deimos.openssl.err;
  import danode.server;
  import danode.client : Response, Clock;
  import danode.log : NORMAL, INFO, DEBUG;

  // SSL context structure, stored relation between hostname 
  // and the SSL context, should be allocated only once available to C, and deallocated at exit
  struct SSLcontext {
    char[256]   hostname;
    SSL_CTX*    context;
  }

  alias size_t VERSION;
  immutable VERSION SSL23 = 0, SSL3 = 1, TLS1 = 2, DTLS1 = 3;

  alias ExternC(T) = SetFunctionAttributes!(T, "C", functionAttributes!T);

  extern (C)
  {
    __gshared int             ncontext;         // How many contexts are available
    __gshared int             cverbose;         // Verbose level of C-Code
    __gshared SSLcontext*     contexts;         // SSL / HTTPs contexts (allocated globally from C)

    // C callback function to switch SSL contexts after hostname lookup
    static void switchContext(SSL* ssl, int *ad, void *arg) {
      string hostname = to!(string)(cast(const(char*)) SSL_get_servername(ssl, TLSEXT_NAMETYPE_host_name));
      if(cverbose >= INFO) writefln("[HTTPS]  Looking for hostname: %s", hostname);
      if(hostname is null) {
        if(cverbose >= INFO) writefln("[WARN]   Client does not support Server Name Indication (SNI)");
        return;
      }
      string s;
      for(int x = 0; x < ncontext; x++) {
        s = to!string(contexts[x].hostname.ptr);
        if(cverbose >= INFO) writefln("[HTTPS]  context: %s %s", hostname, s);
        if(hostname.endsWith(s)) {
          if(cverbose >= INFO) writefln("[HTTPS]  Switching SSL context to %s", hostname);
          SSL_set_SSL_CTX(ssl, contexts[x].context);
          return;
        }
      }
      if(cverbose >= INFO) writefln("[WARN]   callback failed to find certificate for %s", hostname);
      return;
    }
  }

  class HTTPS : DriverInterface {
    private:
      SSL* ssl = null;
      bool blocking = false;
      int verbose = NORMAL;

    public:
      this(Socket socket, bool blocking = false, int verbose = NORMAL) {
        this.serversocket = socket;
        this.blocking = blocking;
        cverbose = verbose;
        this.starttime = Clock.currTime(); /// Time in ms since this process came alive
        this.modtime = Clock.currTime(); /// Time in ms since this process was modified
        if(verbose >= INFO) writeln("[HTTPS]  HTTPS driver initialized");
      }

      override bool openConnection() { synchronized {
        if(ncontext > 0) {
          try {
            this.socket = this.serversocket.accept(); // Accept the incoming socket connection
            if (this.socket is null) return(false);
            this.ssl = SSL_new(contexts[0].context); // writefln("[INFO]   SSL created, using standard certificate contexts[0].context");
            if(verbose >= INFO) writefln("[HTTPS]  initial SSL tunnel created");
            this.ssl.SSL_set_fd(socket.handle()); // writefln("[INFO]   Added socket handle");
            sslAssert(SSL_accept(this.ssl) != -1);
            this.socket.blocking = this.blocking;
          } catch(Exception e) {
            if(verbose >= INFO) writefln("[ERROR]  Couldn't open SSL connection : %s", e.msg);
            return(false);
          }
          try {
            if (this.socket !is null) {
              this.address = this.socket.remoteAddress();
            }
          } catch(Exception e) {
            if(verbose >= INFO) writefln("[WARN]   unable to resolve requesting origin: %s", e.msg);
          }
          if(verbose >= INFO) writeln("[HTTPS]  HTTPS driver initialized");
          return(true);
        } else {
          writeln("[ERROR]  HTTPS driver failed, reason: Server has no certificates loaded");
          socket.close();
        }
        return(false);
      } }

      override ptrdiff_t receive(Socket socket, ptrdiff_t maxsize = 4096){ synchronized {
        ptrdiff_t received;
        if(ssl is null) return -1;
        char[] tmpbuffer = new char[](maxsize);
        if((received = SSL_read(ssl, cast(void*) tmpbuffer, cast(int)maxsize)) > 0) {
          inbuffer.put(tmpbuffer[0 .. received]); modtime = Clock.currTime();
        }
        return(inbuffer.data.length);
      } }

      override void send(ref Response response, Socket socket, ptrdiff_t maxsize = 4096){ synchronized {
        auto slice = response.bytes(maxsize);
        if(ssl is null) return;
        ptrdiff_t send = SSL_write(ssl, cast(void*) slice, cast(int) slice.length);
        if(send >= 0) {
          response.index += send; modtime = Clock.currTime(); senddata[requests] += send;
          if(response.index >= response.length) response.completed = true;
        }
      } }

      override bool isSecure() { return(true); }
  }

  SSL_CTX* getCTX(string CertFile, string keyFile) {
    SSL_CTX *ctx = SSL_CTX_new(SSLv23_server_method());
    sslAssert(!(ctx is null));
    sslAssert(SSL_CTX_use_certificate_file(ctx, cast(const char*) toStringz(CertFile), SSL_FILETYPE_PEM) > 0);
    sslAssert(SSL_CTX_use_PrivateKey_file(ctx, cast(const char*) keyFile, SSL_FILETYPE_PEM) > 0);
    sslAssert(SSL_CTX_check_private_key(ctx) > 0);
    return ctx;
  }

  bool hasCertificate(string hostname) {
    if(cverbose >= INFO) writefln("[HTTPS]  '%s' certificate?", hostname);
    string s;
    for(size_t x = 0; x < ncontext; x++) {
      s = to!string(contexts[x].hostname.ptr);
      if(hostname.endsWith(s)) {
        if(cverbose >= INFO) writefln("[HTTPS]  '%s' certificate found", hostname);
        return true;
      }
    }
    return false;
  }

  // loads an SSL context for hostname from the .crt file at path;
  SSLcontext loadContext(string path, string hostname, string keyFile){
    SSLcontext ctx;
    size_t certNameEnd = (path.length - 4);
    for(size_t x = 0; x < hostname.length; x++) {
      ctx.hostname[x] = hostname[x];
    }
    ctx.hostname[hostname.length] = '\0';
    ctx.context = getCTX(path, keyFile);
    if(cverbose >= INFO) writefln("[INFO]   context created for certificate: %s", to!string(ctx.hostname.ptr));
    SSL_CTX_callback_ctrl(ctx.context,SSL_CTRL_SET_TLSEXT_SERVERNAME_CB, cast(ExternC!(void function())) &switchContext);
    return(ctx);
  }

  // loads all crt files in the certDir, using keyfile: server.key
  SSLcontext* initSSL(Server server, string certDir = ".ssl/", string keyFile = ".ssl/server.key", VERSION v = SSL23) {
    writefln("[HTTPS]  loading Deimos.openSSL, certDir: %s, keyFile: %s, SSL:%s", certDir, keyFile, v);
    SSL_library_init();
    OpenSSL_add_all_algorithms();
    SSL_load_error_strings();
    contexts = cast(SSLcontext*) malloc(0 * SSLcontext.sizeof);
    writefln("[HTTPS]  Certificate folder: %d", exists(certDir));
    if (!exists(certDir)) {
      writefln("[WARN]   SSL certificate folder '%s' not found", certDir);
      return contexts;
    }
    if (!isDir(certDir)) {
      writefln("[WARN]   SSL certificate folder '%s' not a folder", certDir);
      return contexts;
    }
    if (!exists(keyFile)) {
      writefln("[WARN]   SSL private key file: '%s' not found", certDir);
      return contexts;
    }
    if (!isFile(keyFile)) {
      writefln("[WARN]   SSL private key file: '%s' not a file", certDir);
      return contexts;
    }
    string hostname;
    foreach (DirEntry d; dirEntries(certDir, SpanMode.shallow)) {
      if(d.name.endsWith(".crt")) {
        hostname = baseName(d.name, ".crt");
        if(hostname.length < 255) {
          if(cverbose >= INFO) writefln("[INFO]   loading certificate from file: %s", d.name);
          contexts = cast(SSLcontext*) realloc(contexts, (ncontext+1) * SSLcontext.sizeof);
          contexts[ncontext] = loadContext(d.name, hostname, keyFile);
          if(cverbose >= INFO) writefln("[HTTPS]  stored certificate: %s in context: %d", to!string(contexts[ncontext].hostname.ptr), ncontext);
          ncontext++;
        }
      }
    }
    writefln("[HTTPS]  loaded %s SSL certificates", ncontext);
    return contexts;
  }

  void closeSSL(Socket socket) {
    writefln("[INFO]   closing server SSL socket");
    socket.close();
    writefln("[INFO]   cleaning up %d HTTPS contexts", ncontext);
    for(int x = 0; x < ncontext; x++) {
      // Free the different SSL contexts
      SSL_CTX_free(contexts[x].context);
    }
    free(contexts);
  }

  void sslAssert(bool ret){ if (!ret) {
    ERR_print_errors_fp(stderr);
    throw new Exception("SSL_ERROR");
  } }

} // End version SSL

