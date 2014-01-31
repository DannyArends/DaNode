/**
 * | <a href="index.html">Home</a>             | <a href="server.html">Server</a>              |
 *   <a href="client.html">Client</a>          | <a href="router.html">Router</a>              |
 *   <a href="cgi.html">CGI</a>                | <a href="filebuffer.html">File Buffer</a>     |
 *   <a href="structs.html">Structures</a>     | <a href="helper.html">Helper functions</a>    |
 *
 * License: Use freely for any purpose
 */
module danode.https;

version(SSL){

  import deimos.openssl.bio, deimos.openssl.err, deimos.openssl.rand, deimos.openssl.ssl;
  import std.stdio, std.string, std.c.stdlib, std.conv, std.math, std.utf, core.thread;
  import danode.helper, danode.structs, danode.client, danode.clientfunctions, danode.httpstatus;

  alias size_t VERSION;
  immutable VERSION SSL23 = 0, SSL3 = 1, TLS1 = 2, DTLS1 = 3;

  /***********************************
   * Context structure holding the SSL Context and server realted BIO*
   */
  struct Context{
    const(SSL_METHOD)*  method;
    char*               port;
    ssl_ctx_st*         context;
    SSL*                ssl;
    BIO*                sbio;
    BIO*                bbio;
    BIO*                acpt;
  }

  /***********************************
   * Create a new Context using the certificate from cfile and private key from kfile
   */
  Context createContext(string cfile, string kfile, VERSION v = SSL23){
    Context ctx = Context();
    switch(v){
      case SSL23: ctx.method = SSLv23_method(); break;
      case SSL3:  ctx.method = SSLv3_method();  break;
      case TLS1:  ctx.method = TLSv1_method();  break;
      case DTLS1: ctx.method = DTLSv1_method(); break;
      default: ctx.method = SSLv23_method();
    }
    ctx.context = SSL_CTX_new(ctx.method);
    if(!SSL_CTX_use_certificate_file(ctx.context, toStringz(cfile),SSL_FILETYPE_PEM)){
      writefln("[ERROR]  Failed to load: %s", cfile);
      exit(-1); // Exit or throw ?
    }
    if(!SSL_CTX_use_PrivateKey_file(ctx.context, toStringz(kfile),SSL_FILETYPE_PEM)){
      writefln("[ERROR]  Failed to load: %s", cfile);
      exit(-1); // Exit or throw ?
    }
    if(!SSL_CTX_check_private_key(ctx.context)){
      writefln("[ERROR]  Failed to check private key: %s");
      exit(-1); // Exit or throw ?
    }
    writefln("[HTTPS]  Keys loaded and validated");
    return(ctx);
  }

  /***********************************
   * Setup a non blocking SSL socket on port using Context ctx
   */
  void setupSSL(ref Context ctx, char* port = cast(char*)"443"){
    ctx.port = port;
    ctx.sbio = BIO_new_ssl(ctx.context, 0);
    if(ctx.sbio) writefln("[HTTPS]  sbio created from context");

    BIO_get_ssl(ctx.sbio, &ctx.ssl);

    if(ctx.ssl) writefln("[HTTPS]  Valid SSL pointer from sbio");

    SSL_set_mode(ctx.ssl, SSL_MODE_ENABLE_PARTIAL_WRITE);

    ctx.bbio = BIO_new(BIO_f_buffer());
    ctx.sbio = BIO_push(ctx.bbio, ctx.sbio);
    ctx.acpt = BIO_new_accept(port);

    BIO_set_nbio(ctx.acpt, 1);

    BIO_set_accept_bios(ctx.acpt,cast(char*) ctx.sbio);
    if(BIO_do_accept(ctx.acpt) <= 0){
      writefln("[ERROR]  Error setting up accept BIO");
      exit(-1); // Exit or throw ?
    }
  }

  /***********************************
   * Initialize openSSL and create an SSL context
   */
  Context initSSL(string cfile = ".ssl/server.crt", string kfile = ".ssl/server.key", VERSION v = SSL23){
    writefln("[HTTPS]  Loading Deimos.openSSL, Using certificate: %s and key: %s, SSL:%s", cfile, kfile, v);
    SSL_library_init();
    OpenSSL_add_all_algorithms();
    SSL_load_error_strings();
    Context ctx = createContext(cfile, kfile, v);
    ctx.setupSSL();
    return(ctx);
  }

  /***********************************
   * HTTPS Acceptor class, holds the SSL context and spawns clients
   */
  class HTTPS : Thread {
    Server server;
    Context ctx;
    bool running = true;
    bool verbose = false;

    /***********************************
     * Constructor for the HTTPS Acceptor class
     */
    this(Server server, Context ctx){ 
      this.server = server;
      this.ctx = ctx;
      super(&run);
    }

    /***********************************
     * Main work loop HTTPS Acceptor class, spawns new Clients
     */
    void run(){
      writefln("[HTTPS]  Socket is now listening on: %s", to!string(ctx.port));
      while(running){
        try{
          int code = 0;
          if((code = to!int(BIO_do_accept(ctx.acpt))) <= 0) {
            ERR_print_errors_fp(std.c.stdio.stderr);
            writefln("[ERROR]  Error setting up connection");
          }
          Client cl  = new Client(server, ctx.acpt);
          cl.start();
        }catch(Error e){
          writefln("Error: %s", e.msg);
        }
      }
    }
  }

  /***********************************
   * Greadily read input from SSL, till the timeout occurs, or # of bytes read <= 0
   */
  void getSSLinput(ref Client client){
    char buf[KBYTE];
    int  read;
    while(!client.isTimedOut()){
      read = BIO_gets(client.getSSL(), buf.ptr, buf.length);
      if(read <= 0){ break; }
      client.data(to!string(buf[0 .. read].dup));
      client.isModified();
    }
  }

  /***********************************
   * Wait for the SSL handshake on socket, returns true on succesful handshake
   */
  bool waitForHandShake(Client client, BIO* socket){
    int rc = 0;
    while(!client.isTimedOut()){
      if((rc = to!int(BIO_do_handshake(socket))) > 0) return true;
      if(!BIO_should_retry(socket)){
        writeln("[INFO] Giving up on handshake");
        return false;                     // Should we retry ?
      }
      Sleep(msecs(5));
    }
    writeln("[WARN]   Handshake TimedOut");
    return false;
  }

  /***********************************
   * Set the ip/hostname and port from the BIO* bio in the client
   */
  void setHost(ref Client client, BIO* bio){
    import std.c.linux.linux;
    import std.c.linux.socket;
    int         sockfd;
    sockaddr    addr;
    socklen_t   addrlen = addr.sizeof;
    ubyte       host[80];                         // ubyte is initialized as 0

    BIO_get_fd(bio, &sockfd);                     // Get the socket file descriptor
    getpeername(sockfd, &addr, &addrlen);         // Get the peername in sockaddr addr

    if(addr.sa_family == AF_INET){
      client.setPort((cast(sockaddr_in*)&addr).sin_port);
      inet_ntop(AF_INET, cast(void*)&(cast(sockaddr_in*)&addr).sin_addr, cast(char*)host.ptr, 40);
    }else if(addr.sa_family == AF_INET6){
      client.setPort((cast(sockaddr_in6*)&addr).sin6_port);
      inet_ntop(AF_INET6, cast(void*)&(cast(sockaddr_in6 *)&addr).sin6_addr, cast(char*)host.ptr, 40);
    }else{
      writefln("[WARN]   Unknown socket type: %i", addr.sa_family);
    }
    // Set the hostname
    client.setIp(to!string(cast(char*)host));
  }

} // End of version(SSL)

