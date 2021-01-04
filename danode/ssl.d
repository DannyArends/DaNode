module danode.ssl;

import danode.log : custom, warning, info;

version(SSL) {
  import deimos.openssl.ssl;
  import deimos.openssl.err;

  import danode.imports;
  import danode.client;
  import danode.server : Server;
  import danode.response : Response;

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
    __gshared SSLcontext*     contexts;         // SSL / HTTPs contexts (allocated globally from C)

    // C callback function to switch SSL contexts after hostname lookup
    static void switchContext(SSL* ssl, int *ad, void *arg) {
      string hostname = to!(string)(cast(const(char*)) SSL_get_servername(ssl, TLSEXT_NAMETYPE_host_name));
      custom(1, "HTTPS", "looking for hostname: %s", hostname);
      if(hostname is null) {
        custom(1, "WARN", "client does not support Server Name Indication (SNI), using default: contexts[0]");
        return;
      }
      string s;
      for(int x = 0; x < ncontext; x++) {
        s = to!string(contexts[x].hostname.ptr);
        custom(1, "HTTPS", "context: %s %s", hostname, s);
        if(hostname.endsWith(s)) {
          custom(1, "HTTPS", "switching SSL context to %s", hostname);
          SSL_set_SSL_CTX(ssl, contexts[x].context);
          return;
        }
      }
      custom(1, "WARN", "callback failed to find certificate for %s", hostname);
      return;
    }
  }

  // Create a new SSL context pointer using a certificate, chain and privateKey file
  SSL_CTX* createCTX(string certFile, string keyFile, string chainFile) {
    SSL_CTX* ctx = SSL_CTX_new(SSLv3_server_method());
    sslAssert(!(ctx is null));
    sslAssert(SSL_CTX_use_certificate_file(ctx, cast(const char*) toStringz(certFile), SSL_FILETYPE_PEM) > 0);
    if (exists(chainFile) && isFile(chainFile)) {
      custom(1, "HTTPS", "loading certificate chain from file: %s", chainFile);
      sslAssert(SSL_CTX_use_certificate_chain_file(ctx, cast(const char*) toStringz(chainFile)) > 0);
    }
    sslAssert(SSL_CTX_use_PrivateKey_file(ctx, cast(const char*) toStringz(keyFile), SSL_FILETYPE_PEM) > 0);
    sslAssert(SSL_CTX_check_private_key(ctx) > 0);
    return ctx;
  }

  // Does the hostname requested have a certificate ?
  bool hasCertificate(string hostname) {
    custom(1, "HTTPS", "'%s' certificate?", hostname);
    string s;
    for(size_t x = 0; x < ncontext; x++) {
      s = to!string(contexts[x].hostname.ptr);
      if(hostname.endsWith(s)) {
        custom(1, "HTTPS", "'%s' certificate found", hostname);
        return true;
      }
    }
    return false;
  }

  // Should be used after SSL_connect(), SSL_accept(), SSL_do_handshake(), 
  // SSL_read_ex(), SSL_read(), SSL_peek_ex(), SSL_peek(), SSL_write_ex() 
  // or SSL_write() on the ssl
  int checkForError(SSL* ssl, Socket socket, int retcode) {
    int err = SSL_get_error(ssl, retcode);
    switch (err) {
      case SSL_ERROR_NONE:
        /* warning("SSL_ERROR_NONE"); */ break;
      case SSL_ERROR_SSL:
        /* warning("SSL_ERROR_SSL"); */ break;
      case SSL_ERROR_ZERO_RETURN:
        /* warning("SSL_ERROR_ZERO_RETURN"); */ break;
      case SSL_ERROR_WANT_READ:
        /* warning("SSL_ERROR_WANT_READ"); */ break;
      case SSL_ERROR_WANT_WRITE:
        /* warning("SSL_ERROR_WANT_WRITE"); */ break;
      case SSL_ERROR_WANT_CONNECT:
        /* warning("SSL_ERROR_WANT_CONNECT"); */ break;
      case SSL_ERROR_WANT_ACCEPT:
        /* warning("SSL_ERROR_WANT_ACCEPT"); */ break;
      case SSL_ERROR_WANT_X509_LOOKUP:
        /* warning("SSL_ERROR_WANT_X509_LOOKUP"); */ break;
      case SSL_ERROR_SYSCALL:
        /* warning("[ERROR]  SSL_ERROR_SYSCALL: RETURN: %d", retcode); */ break;
      default: /*  warning("[ERROR]  SSL_ERROR Error %d %d", err, retcode); */ break;
    }
    return(err);
  }

  // loads an SSL context for hostname from the .crt file at path;
  SSLcontext loadContext(string path, string hostname, string keyFile, string chainFile) {
    SSLcontext ctx;
    size_t certNameEnd = (path.length - 4);
    for(size_t x = 0; x < hostname.length; x++) {
      ctx.hostname[x] = hostname[x];
    }
    ctx.hostname[hostname.length] = '\0';
    ctx.context = createCTX(path, keyFile, chainFile);
    custom(1, "HTTPS", "context created for certificate: %s", to!string(ctx.hostname.ptr));
    SSL_CTX_callback_ctrl(ctx.context,SSL_CTRL_SET_TLSEXT_SERVERNAME_CB, cast(ExternC!(void function())) &switchContext);
    return(ctx);
  }

  // loads all crt files in the certDir, using keyfile: server.key
  SSLcontext* initSSL(Server server, string certDir = ".ssl/", string keyFile = ".ssl/server.key", VERSION v = SSL23) {
    custom(0, "HTTPS", "loading Deimos.openSSL, certDir: %s, keyFile: %s, SSL:%s", certDir, keyFile, v);
    SSL_library_init();
    OpenSSL_add_all_algorithms();
    SSL_load_error_strings();
    contexts = cast(SSLcontext*) malloc(0 * SSLcontext.sizeof);
    custom(0, "HTTPS", "certificate folder: %d", exists(certDir));
    if (!exists(certDir)) {
      warning("SSL certificate folder '%s' not found", certDir);
      return contexts;
    }
    if (!isDir(certDir)) {
      warning("SSL certificate folder '%s' not a folder", certDir);
      return contexts;
    }
    if (!exists(keyFile)) {
      warning("SSL private key file: '%s' not found", certDir);
      return contexts;
    }
    if (!isFile(keyFile)) {
      warning("SSL private key file: '%s' not a file", certDir);
      return contexts;
    }

    foreach (DirEntry d; dirEntries(certDir, SpanMode.shallow)) {
      if (d.name.endsWith(".crt")) {
        string hostname = baseName(d.name, ".crt");
        if (hostname.length < 255) {
          string chainFile = baseName(d.name, ".crt") ~ ".chain";
          custom(1, "HTTPS", "loading certificate from file: %s", d.name);
          contexts = cast(SSLcontext*) realloc(contexts, (ncontext+1) * SSLcontext.sizeof);
          contexts[ncontext] = loadContext(d.name, hostname, keyFile, chainFile);
          custom(1, "HTTPS", "stored certificate: %s in context: %d", to!string(contexts[ncontext].hostname.ptr), ncontext);
          ncontext++;
        }
      }
    }
    custom(0, "HTTPS", "loaded %s SSL certificates", ncontext);
    return contexts;
  }

  // Close the server SSL socket, and clean up the different contexts
  void closeSSL(Socket socket) {
    custom(1, "HTTPS", "closing server SSL socket");
    socket.close();
    custom(1, "HTTPS", "cleaning up %d HTTPS contexts", ncontext);
    for(int x = 0; x < ncontext; x++) {
      // Free the different SSL contexts
      SSL_CTX_free(contexts[x].context);
    }
    free(contexts);
  }

  void sslAssert(bool ret) { 
    if (!ret) {
      ERR_print_errors_fp(stderr.getFP());
      throw new Exception("SSL_ERROR");
    }
  }

  unittest {
    custom(0, "FILE", "%s", __FILE__);
  }
} else {// End version SSL
  unittest {
    custom(0, "WARN", "Skipping unittest for: '%s'", __FILE__);
  }
}

