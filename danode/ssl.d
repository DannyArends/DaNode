module danode.ssl;

version(SSL){
  import std.socket;
  import core.thread;
  import std.stdio : writefln;
  import std.c.stdio;
  import danode.client;

  import deimos.openssl.ssl;
  import deimos.openssl.err;

  alias size_t VERSION;
  immutable VERSION SSL23 = 0, SSL3 = 1, TLS1 = 2, DTLS1 = 3;
  const RecvSize = 1024;

  class HTTPS : DriverInterface {
    private:
      Address             address;             /// Private  address field
      SysTime             starttime;           /// Time in ms since this process came alive
      SysTime             modtime;             /// Time in ms since this process was last modified
      long                requests;            /// Number of requests we handled
      long[long]          senddata;            /// Size of data send per request
      SSL_CTX*            ctx;
      SSL*                ssl;

    public:
      this(Socket socket, SSL_CTX* ctx, bool blocking = false){
        this.ctx = ctx;
        ssl = SSL_new(ctx);
        writefln("[INFO]   SSL created");
        SSL_set_fd(ssl, socket.handle());
        writefln("[INFO]   Added socket handle");
        sslAssert(SSL_accept(ssl) != -1);
        this.socket           = socket;
        this.socket.blocking  = blocking;
        try{
          this.address        = socket.remoteAddress();
        }catch(Exception e){ writefln("[WARN]   unable to resolve requesting origin"); }
        writefln("[INFO]   SSL driver created");
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
        long send = SSL_write(ssl, cast(void*) response.bytes, cast(int)maxsize);
        if(send >= 0){
          response.index += send; modtime = Clock.currTime(); senddata[requests] += send;
          if(response.index >= response.length) response.completed = true;
        }
      } }
  }

  SSL_CTX* getCTX(string CertFile, string KeyFile) {
    SSL_CTX *ctx = SSL_CTX_new(SSLv23_server_method());
    sslAssert(!(ctx is null));
    sslAssert(SSL_CTX_use_certificate_file(ctx, cast(const char*) CertFile, SSL_FILETYPE_PEM) > 0);
    sslAssert(SSL_CTX_use_PrivateKey_file(ctx, cast(const char*) KeyFile, SSL_FILETYPE_PEM) > 0);
    sslAssert(SSL_CTX_check_private_key(ctx) > 0);
    return ctx;
  }

  SSL_CTX* initSSL(string CertFile = ".ssl/server.crt", string KeyFile = ".ssl/server.key", VERSION v = SSL23) {
    writefln("[HTTPS]  loading Deimos.openSSL, Using certificate: %s and key: %s, SSL:%s", CertFile, KeyFile, v);
    SSL_library_init();
    OpenSSL_add_all_algorithms();
  	SSL_load_error_strings();
    SSL_CTX* ctx = getCTX(CertFile, KeyFile);
    writefln("[HTTPS]  context created");
    return ctx;
  }

  void closeSSL(Socket socket, SSL_CTX* ctx){
    writefln("[HTTPS]  closing socket");
    socket.close();
    SSL_CTX_free(ctx);
  }

  void sslAssert(bool ret){ if (!ret){
    ERR_print_errors_fp(std.c.stdio.stderr);
    throw new Exception("SSL_ERROR");
  } }

} // End version SSL

