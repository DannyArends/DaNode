module danode.ssl;

version(SSL) {
  import danode.imports;
  import danode.includes;

  import danode.imports;
  import danode.client;
  import danode.log : log, tag, error, Level;
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
      log(Level.Verbose, "SSL: [I] Looking for hostname: %s", hostname);
      if(hostname is null) { log(Level.Verbose, "SSL: [W] Client no SNI support, using default: contexts[0]"); return; }
      ptrdiff_t idx = findContext(hostname);
      if (idx >= 0) { 
        log(Level.Verbose, "SSL: [I] Switching SSL context to %s", hostname); 
        SSL_set_SSL_CTX(ssl, contexts[idx].context);
      }else{ error("SSL: Callback failed to find certificate for %s", hostname); }
    }
  }

  void generateKey(string path, int bits = 4096) {
    if (path.exists()) return;
    log(Level.Always, "SSL: Generating %d-bit RSA key at %s", bits, path);
    EVP_PKEY_CTX* ctx = EVP_PKEY_CTX_new_id(6, null);  // 6 = EVP_PKEY_RSA
    scope(exit) EVP_PKEY_CTX_free(ctx);
    EVP_PKEY_keygen_init(ctx);
    EVP_PKEY_CTX_ctrl(ctx, 6, 8, 1, bits, null);  // set_rsa_keygen_bits: op=KEYGEN(8), ctrl=KEYBITS(1)
    EVP_PKEY* pkey;
    if (EVP_PKEY_keygen(ctx, &pkey) <= 0) { error("SSL: Keygen failed for %s", path); return; }
    scope(exit) EVP_PKEY_free(pkey);
    BIO* bio = BIO_new_file(toStringz(path), "w");
    scope(exit) BIO_free(bio);
    PEM_write_bio_PrivateKey(bio, pkey, null, null, 0, null, null);
  }

  ptrdiff_t findContext(string hostname) {
    for (size_t x = 0; x < contexts.length; x++) {
      if (hostname.endsWith(to!string(contexts[x].hostname.ptr))) return(x);
    }
    return(-1);
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
      log(Level.Verbose, "SSL: [I] Loading certificate+chain from file: %s", chainFile);
      sslAssert(SSL_CTX_use_certificate_chain_file(ctx, cast(const char*) toStringz(chainFile)) > 0);
    } else {
      log(Level.Verbose, "SSL: [W] No chain file for %s", chainFile);
      return(null);
    }
    sslAssert(SSL_CTX_use_PrivateKey_file(ctx, cast(const char*) toStringz(keyFile), 1) > 0);
    sslAssert(SSL_CTX_check_private_key(ctx) > 0);
    return ctx;
  }

  // Does the hostname requested have a certificate ?
  bool hasCertificate(string hostname) {
    bool found = (findContext(hostname) >= 0);
    log(Level.Trace, "SSL: [T] '%s' certificate? %s", hostname, found);
    return found;
  }

  // Should be used after all SSL class
  int checkForError(SSL* ssl, Socket socket, int retcode) {
    int err = SSL_get_error(ssl, retcode);
    switch (err) {
      case SSL_ERROR_NONE: break;
      case SSL_ERROR_SSL: break;
      case SSL_ERROR_ZERO_RETURN: break;
      case SSL_ERROR_WANT_READ: break;
      case SSL_ERROR_WANT_WRITE: break;
      case SSL_ERROR_WANT_CONNECT: break;
      case SSL_ERROR_WANT_ACCEPT: break;
      case SSL_ERROR_WANT_X509_LOOKUP: break;
      case SSL_ERROR_SYSCALL: break;
      default: error("SSL: SSL_get_error %s %d", err, retcode); break;
    }
    return(err);
  }

  // loads an SSL context for hostname from the .chain file at path;
  SSLcontext loadContext(string chainFile, string hostname, string keyFile) {
    SSLcontext ctx;
    for(size_t x = 0; x < hostname.length; x++) { ctx.hostname[x] = hostname[x]; }
    ctx.hostname[hostname.length] = '\0';
    ctx.context = createCTX(chainFile, keyFile);
    if (ctx.context is null) { error("SSL: Failed to create context for %s", hostname); return ctx; }
    log(Level.Verbose, "SSL: [I] Context created, certificate: %s", fromStringz(ctx.hostname));
    SSL_CTX_callback_ctrl(ctx.context,SSL_CTRL_SET_TLSEXT_SERVERNAME_CB, cast(ExternC!(void function())) &switchContext);
    return(ctx);
  }

  // Reload all SSL contexts from sslPath without restarting the server
  void loadSSL(string sslPath = ".ssl/", string sslKey = ".ssl/server.key") {
    log(Level.Verbose, "SSL: [I] loading sslPath: %s, sslKey: %s", sslPath, sslKey);
    if (!exists(sslPath) || !isDir(sslPath)) { error("SSL: sslPath '%s' not found", sslPath); return; }
    if (!exists(sslKey) || !isFile(sslKey)) { sslKey.generateKey(); }

    SSLcontext[] localContexts;
    foreach (DirEntry d; dirEntries(sslPath, SpanMode.shallow)) {
      if (d.name.endsWith(".chain")) {
        string hostname = baseName(d.name, ".chain");
        if (hostname.length < 255) {
          string chainFile = d.name;
          log(Level.Verbose, "SSL: [I] Reloading certificate at: '%s'", chainFile);
          auto lc = loadContext(chainFile, hostname, sslKey);
          if (lc.context !is null) localContexts ~= lc;
        }
      }
    }
    contexts = localContexts;  // atomic single assignment
    log(Level.Always, "SSL: [I] Loaded %s SSL certificates", contexts.length);
  }

  // Close the server SSL socket, and clean up the different contexts
  void closeSSL(Socket socket) {
    log(Level.Verbose, "SSL: [I] Closing server SSL socket");
    socket.close();
    log(Level.Verbose, "SSL: [I] Cleaning up %d SSL contexts", contexts.length);
    foreach (ref ctx; contexts) { SSL_CTX_free(ctx.context); }
    contexts = null;
  }

  void sslAssert(bool ret) { if (!ret) { ERR_print_errors_fp(null); throw new Exception("SSL_ERROR"); } }

  unittest {
    tag(Level.Always, "FILE", "%s", __FILE__);
  }
}
