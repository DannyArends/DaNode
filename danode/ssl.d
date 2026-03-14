module danode.ssl;

import danode.log : custom, warning, info;

version(SSL) {
  import danode.includes;

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
    __gshared SSLcontext[]    contexts;         // SSL / HTTPs contexts (allocated globally from C)

    // C callback function to switch SSL contexts after hostname lookup
    static void switchContext(SSL* ssl, int *ad, void *arg) {
      string hostname = to!(string)(cast(const(char*)) SSL_get_servername(ssl, TLSEXT_NAMETYPE_host_name));
      custom(1, "HTTPS", "looking for hostname: %s", hostname);
      if(hostname is null) {
        custom(1, "WARN", "client does not support Server Name Indication (SNI), using default: contexts[0]");
        return;
      }
      string s;
      for(int x = 0; x < contexts.length; x++) {
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
  SSL_CTX* createCTX(string chainFile, string keyFile) {
    SSL_CTX* ctx = SSL_CTX_new(TLS_server_method());
    sslAssert(!(ctx is null));

    SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION);
    SSL_CTX_set_cipher_list(ctx, "ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-CHACHA20-POLY1305");
    SSL_CTX_set_ciphersuites(ctx, "TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256");
    SSL_CTX_set_options(ctx, 0x00400000U); //SSL_OP_CIPHER_SERVER_PREFERENCE
    SSL_CTX_set1_groups_list(ctx, "X25519:P-256:P-384");

    if (exists(chainFile) && isFile(chainFile)) {
      custom(1, "HTTPS", "loading certificate+chain from file: %s", chainFile);
      sslAssert(SSL_CTX_use_certificate_chain_file(ctx, cast(const char*) toStringz(chainFile)) > 0);
    } else {
      custom(1, "WARN", "No chain file for %s", chainFile);
      return(null);
    }
    sslAssert(SSL_CTX_use_PrivateKey_file(ctx, cast(const char*) toStringz(keyFile), 1) > 0);
    sslAssert(SSL_CTX_check_private_key(ctx) > 0);
    return ctx;
  }

  // Does the hostname requested have a certificate ?
  bool hasCertificate(string hostname) {
    custom(1, "HTTPS", "'%s' certificate?", hostname);
    string s;
    for(size_t x = 0; x < contexts.length; x++) {
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

  // loads an SSL context for hostname from the .chain file at path;
  SSLcontext loadContext(string chainFile, string hostname, string keyFile) {
    SSLcontext ctx;
    for(size_t x = 0; x < hostname.length; x++) { ctx.hostname[x] = hostname[x]; }
    ctx.hostname[hostname.length] = '\0';
    ctx.context = createCTX(chainFile, keyFile);
    custom(1, "HTTPS", "context created for certificate: %s", to!string(ctx.hostname.ptr));
    SSL_CTX_callback_ctrl(ctx.context,SSL_CTRL_SET_TLSEXT_SERVERNAME_CB, cast(ExternC!(void function())) &switchContext);
    return(ctx);
  }

  // loads all chain files in the server.certDir, using server.keyFile
  void initSSL(Server server, VERSION v = SSL23) {
    custom(0, "HTTPS", "loading Deimos.openSSL, certDir: %s, keyFile: %s, SSL:%s", server.certDir, server.keyFile, v);
    reloadSSL(server.certDir, server.keyFile);
  }

  // Reload all SSL contexts from certDir without restarting the server
  void reloadSSL(string certDir = ".ssl/", string keyFile = ".ssl/server.key") {
    custom(0, "HTTPS", "(re)loading SSL certificates from: %s", certDir);
    if (!exists(certDir) || !isDir(certDir)) { warning("SSL cert dir '%s' not found", certDir); return; }
    if (!exists(keyFile) || !isFile(keyFile)) { warning("SSL key file '%s' not found", keyFile); return; }

    SSLcontext[] localContexts;
    foreach (DirEntry d; dirEntries(certDir, SpanMode.shallow)) {
      if (d.name.endsWith(".chain")) {
        string hostname = baseName(d.name, ".chain");
        if (hostname.length < 255) {
          string chainFile = d.name;
          info("reloading certificate at: '%s'", chainFile);
          localContexts ~= loadContext(chainFile, hostname, keyFile);
        }
      }
    }
    contexts = localContexts;  // atomic single assignment
    custom(0, "HTTPS", "(re)loaded %s SSL certificates", contexts.length);
  }

  // Close the server SSL socket, and clean up the different contexts
  void closeSSL(Socket socket) {
    custom(1, "HTTPS", "closing server SSL socket");
    socket.close();
    custom(1, "HTTPS", "cleaning up %d HTTPS contexts", contexts.length);
    foreach (ref ctx; contexts) { SSL_CTX_free(ctx.context); }
    contexts = null;
  }

  void sslAssert(bool ret) { 
    if (!ret) { ERR_print_errors_fp(null); throw new Exception("SSL_ERROR"); }
  }

  unittest {
    custom(0, "FILE", "%s", __FILE__);
  }
} else {// End version SSL
  unittest {
    custom(0, "WARN", "Skipping unittest for: '%s'", __FILE__);
  }
}
