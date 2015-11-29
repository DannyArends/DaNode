module danode.ssl;

version(SSL){
  import std.socket;
  import std.file;
  import std.traits;
  import std.string;
  import std.algorithm;
  import core.thread;
  import std.stdio : writefln;
  import std.c.stdio;
  import danode.client;

  import deimos.openssl.ssl;
  import deimos.openssl.err;
  import danode.server;

  struct SSLcontext {
    string    hostname;
    SSL_CTX*  context;
  }

  alias size_t VERSION;
  immutable VERSION SSL23 = 0, SSL3 = 1, TLS1 = 2, DTLS1 = 3;

  alias ExternC(T) = SetFunctionAttributes!(T, "C", functionAttributes!T);

  class HTTPS : DriverInterface {
    private:
      SSL*                ssl;

    public:
      this(Socket socket, SSLcontext[] contexts, bool blocking = false){
        this.ssl = SSL_new(contexts[0].context);            // writefln("[INFO]   SSL created, using standard certificate");
        SSL_set_fd(this.ssl, socket.handle());              // writefln("[INFO]   Added socket handle");
        sslAssert(SSL_accept(this.ssl) != -1);
        this.socket           = socket;
        this.socket.blocking  = blocking;
        this.starttime        = Clock.currTime();           /// Time in ms since this process came alive
        this.modtime          = Clock.currTime();           /// Time in ms since this process was modified
        try {
          this.address        = socket.remoteAddress();
        } catch(Exception e) {
          writefln("[WARN]   unable to resolve requesting origin");
        }
      }

      override long receive(Socket socket, long maxsize = 4096){ synchronized {
        long received;
        char[] tmpbuffer = new char[](maxsize);
        if((received = SSL_read(ssl, cast(void*) tmpbuffer, cast(int)maxsize)) > 0){
          inbuffer.put(tmpbuffer[0 .. received]); modtime = Clock.currTime();
        }
        return(inbuffer.data.length);
      } }

      override void send(ref Response response, Socket socket, long maxsize = 4096){ synchronized {
        auto slice = response.bytes(maxsize);
        long send = SSL_write(ssl, cast(void*) slice, cast(int) slice.length);
        if(send >= 0){
          response.index += send; modtime = Clock.currTime(); senddata[requests] += send;
          if(response.index >= response.length) response.completed = true;
        }
      } }

      override bool isSecure(){ return(true); }
  }

  SSL_CTX* getCTX(string CertFile, string KeyFile) {
    SSL_CTX *ctx = SSL_CTX_new(SSLv23_server_method());
    sslAssert(!(ctx is null));
    sslAssert(SSL_CTX_use_certificate_file(ctx, cast(const char*) toStringz(CertFile), SSL_FILETYPE_PEM) > 0);
    sslAssert(SSL_CTX_use_PrivateKey_file(ctx, cast(const char*) KeyFile, SSL_FILETYPE_PEM) > 0);
    sslAssert(SSL_CTX_check_private_key(ctx) > 0);
    return ctx;
  }

  extern (C) static void switchContext(SSL* ssl, int *ad, void *arg){
    auto hostname = to!string(cast(const char*) SSL_get_servername(ssl, TLSEXT_NAMETYPE_host_name));
    if(hostname is null) {
      writefln("[WARN]   Client does not support Server Name Indication (SNI)");
    }
    Server* s = cast(Server*) arg;
    foreach(ctx; s.getSSLContexts()) {
      if(hostname.endsWith(ctx.hostname)) {
        writefln("[HTTPS]  Switching SSL context to %s", hostname);
        SSL_set_SSL_CTX(ssl, ctx.context);
        return;
      }
    }
    writefln("[WARN]   callback failed to find certificate for %s", hostname);
  }

  SSLcontext[] initSSL(Server server, string CertDir = ".ssl/", string KeyFile = ".ssl/server.key", VERSION v = SSL23) {
    writefln("[HTTPS]  loading Deimos.openSSL, from %s using key: %s, SSL:%s", CertDir, KeyFile, v);
    SSL_library_init();
    OpenSSL_add_all_algorithms();
    SSL_load_error_strings();
    SSLcontext[] contexts;
    foreach (DirEntry d; dirEntries(CertDir, SpanMode.shallow)){
      if(d.name.endsWith(".crt")){
        writefln("[INFO]   Loading certificate: %s", d.name);
        SSLcontext ctx;
        ctx.hostname = d.name[CertDir.length .. ($-4)];
        ctx.context = getCTX(d.name, KeyFile);
        SSL_CTX_callback_ctrl(ctx.context, SSL_CTRL_SET_TLSEXT_SERVERNAME_CB, cast(ExternC!(void function())) &switchContext);
        SSL_CTX_set_tlsext_servername_arg(ctx.context, &server);
        contexts ~= ctx;
      }
    }
    writefln("[HTTPS]  loaded %s SSL certificates", contexts.length);
    return contexts;
  }

  void closeSSL(Socket socket, SSLcontext[] contexts){
    writefln("[HTTPS]  closing socket");
    socket.close();
    foreach(ctx; contexts) { // Free the different SSL contexts
      SSL_CTX_free(ctx.context);
    }
  }

  void sslAssert(bool ret){ if (!ret){
    ERR_print_errors_fp(std.c.stdio.stderr);
    throw new Exception("SSL_ERROR");
  } }

} // End version SSL

