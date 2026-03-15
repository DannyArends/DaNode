module danode.ssl;

version(SSL) {
  import danode.imports;
  import danode.includes;

  import danode.imports;
  import danode.client;
  import danode.log : custom, warning, info, error;
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
      custom(1, "SSL", "looking for hostname: %s", hostname);
      if(hostname is null) { custom(1, "WARN", "Client no SNI support, using default: contexts[0]"); return; }
      ptrdiff_t idx = findContext(hostname);
      if (idx >= 0) { 
        custom(1, "SSL", "switching SSL context to %s", hostname); 
        SSL_set_SSL_CTX(ssl, contexts[idx].context);
      }else{ custom(1, "WARN", "callback failed to find certificate for %s", hostname); }
    }
  }

  void generateKey(string path, int bits = 4096) {
    if (exists(path)) return;
    custom(0, "SSL", "ACME: generating %d-bit RSA key at %s", bits, path);
    EVP_PKEY_CTX* ctx = EVP_PKEY_CTX_new_id(6, null);  // 6 = EVP_PKEY_RSA
    scope(exit) EVP_PKEY_CTX_free(ctx);
    EVP_PKEY_keygen_init(ctx);
    EVP_PKEY_CTX_ctrl(ctx, 6, 8, 1, bits, null);  // set_rsa_keygen_bits: op=KEYGEN(8), ctrl=KEYBITS(1)
    EVP_PKEY* pkey;
    if (EVP_PKEY_keygen(ctx, &pkey) <= 0) { error("ACME: keygen failed for %s", path); return; }
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
      custom(1, "SSL", "loading certificate+chain from file: %s", chainFile);
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
    bool found = (findContext(hostname) >= 0);
    custom(2, "SSL", "'%s' certificate? %s", hostname, found);
    return found;
  }

  // Should be used after all SSL class
  int checkForError(SSL* ssl, Socket socket, int retcode) {
    int err = SSL_get_error(ssl, retcode);
    switch (err) {
      case SSL_ERROR_NONE: break;
      default: custom(2, "SSL", "SSL_get_error %s %d", err, retcode); break;
    }
    return(err);
  }

  // loads an SSL context for hostname from the .chain file at path;
  SSLcontext loadContext(string chainFile, string hostname, string keyFile) {
    SSLcontext ctx;
    for(size_t x = 0; x < hostname.length; x++) { ctx.hostname[x] = hostname[x]; }
    ctx.hostname[hostname.length] = '\0';
    ctx.context = createCTX(chainFile, keyFile);
    if (ctx.context is null) { warning("SSL: failed to create context for %s", hostname); return ctx; }
    custom(1, "SSL", "context created for certificate: %s", fromStringz(ctx.hostname));
    SSL_CTX_callback_ctrl(ctx.context,SSL_CTRL_SET_TLSEXT_SERVERNAME_CB, cast(ExternC!(void function())) &switchContext);
    return(ctx);
  }

  // loads all chain files in the server.certDir, using server.keyFile
  void initSSL(Server server) { reloadSSL(server.certDir, server.keyFile); }

  // Reload all SSL contexts from certDir without restarting the server
  void reloadSSL(string certDir = ".ssl/", string keyFile = ".ssl/server.key") {
    custom(0, "SSL", "loading Deimos.openSSL, certDir: %s, keyFile: %s", certDir, keyFile);
    if (!exists(certDir) || !isDir(certDir)) { warning("SSL cert dir '%s' not found", certDir); return; }
    if (!exists(keyFile) || !isFile(keyFile)) { warning("SSL key file '%s' not found", keyFile); return; }

    SSLcontext[] localContexts;
    foreach (DirEntry d; dirEntries(certDir, SpanMode.shallow)) {
      if (d.name.endsWith(".chain")) {
        string hostname = baseName(d.name, ".chain");
        if (hostname.length < 255) {
          string chainFile = d.name;
          info("reloading certificate at: '%s'", chainFile);
          auto lc = loadContext(chainFile, hostname, keyFile);
          if (lc.context !is null) localContexts ~= lc;
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

  void sslAssert(bool ret) { if (!ret) { ERR_print_errors_fp(null); throw new Exception("SSL_ERROR"); } }

  unittest {
    custom(0, "FILE", "%s", __FILE__);
  }
}
