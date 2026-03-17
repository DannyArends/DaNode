/** danode/acme.d - Automatic certificate renewal via the ACME protocol (Let's Encrypt)
  * License: GPLv3 (https://github.com/DannyArends/DaNode) - Danny Arends **/
module danode.acme;

version(SSL) {
  import danode.imports;
  import danode.includes;

  import danode.log : log, error, Level;
  import danode.ssl : loadSSL, generateKey;
  import danode.functions : writeFile;

  immutable string ACME_DIR_PROD    = "https://acme-v02.api.letsencrypt.org/directory";
  immutable string ACME_DIR_STAGING = "https://acme-staging-v02.api.letsencrypt.org/directory";

  __gshared string[string] acmeChallenges; // Shared challenge store: token -> keyAuthorization
  __gshared Mutex acmeMutex;

  Mutex getAcmeMutex() { if (acmeMutex is null) { acmeMutex = new Mutex(); } return acmeMutex; }

  // POST a JWS request to an ACME URL and return parsed JSON response
  JSONValue acmePost(EVP_PKEY* pkey, JSONValue dir, string url, string kid, string payload,
                     string* location = null) {
    string nonce    = acmeNonce(dir);
    string postData = buildJWS(pkey, nonce, url, kid, payload);
    char[] response;
    auto http = HTTP(url);
    http.method = HTTP.Method.post;
    http.addRequestHeader("Content-Type", "application/jose+json");
    http.postData = postData;
    http.onReceive = (ubyte[] data) { response ~= cast(char[]) data; return data.length; };
    if (location !is null) {
      http.onReceiveHeader = (in char[] key, in char[] value) {
        if (icmp(key, "location") == 0) *location = value.idup;
      };
    }
    http.perform();
    log(Level.Trace, "ACME: POST %s -> %s", url, cast(string) response);
    return parseJSON(response);
  }

  // Full ACME renewal flow
  bool renewCert(string domain, string email, string csrPath, string chainPath, string accountKey, bool staging) {
    log(Level.Always, "ACME: starting renewal for %s", domain);

    EVP_PKEY* pkey = loadAccountKey(accountKey);
    if (pkey is null) return false;

    JSONValue dir = acmeDirectory(staging);
    string kid = acmeAccountURL(dir, pkey, email);
    if (kid.length == 0) { error("ACME: failed to get account URL"); return false; }
    log(Level.Verbose, "Account URL: %s", kid);

    string orderURL;
    JSONValue order = newOrder(dir, pkey, kid, domain, orderURL);
    log(Level.Verbose, "ACME: order: %s, orderURL: %s", order.toString(), orderURL);
    string[] tokens;
    foreach (authURL; order["authorizations"].array) {
      JSONValue challenge = getHTTP01Challenge(authURL.str, dir, pkey, kid);
      if (challenge.type == JSONType.null_) return false;
      tokens ~= prepareChallenge(challenge, pkey);
      triggerChallenge(challenge, dir, pkey, kid);
    }

    if (!pollAllAuthorizations(order, dir, pkey, kid)) {
      foreach (t; tokens) synchronized(getAcmeMutex()) { acmeChallenges.remove(t); }
      return false;
    }
    foreach (t; tokens) synchronized(getAcmeMutex()) { acmeChallenges.remove(t); }

    JSONValue finalized = finalizeOrder(order, dir, pkey, kid, csrPath);
    log(Level.Verbose, "ACME: order status: %s, finalized: %s", finalized["status"].str, finalized.toString());

    foreach (i; 0 .. 10) { // Poll until certificate is ready
      if (finalized["status"].str == "valid") break;
      Thread.sleep(dur!"seconds"(5));
      finalized = acmePost(pkey, dir, orderURL, kid, "");
    }
    return downloadCert(finalized, dir, pkey, kid, chainPath);
  }

    // Check cert expiry and renew if < 30 days remaining
  void checkAndRenew(string certDir = ".ssl/", string keyFile = ".ssl/server.key", string accountKey = ".ssl/account.key", bool staging = false) {
    if (!exists(accountKey) || !isFile(accountKey)) { accountKey.generateKey(); }
    new Thread({
      try {
        log(Level.Always, "checkAndRenew called on '%s' with key '%s'", certDir, accountKey);
        foreach (DirEntry d; dirEntries(certDir, SpanMode.shallow)) {
          if (!d.name.endsWith(".csr")) continue;
          string domain = baseName(d.name, ".csr");
          string chainPath = certDir ~ domain ~ ".chain";

          if (!exists(chainPath)) { log(Level.Always, "ACME: no chain found for %s, bootstrapping", domain);
            if (renewCert(domain, "Danny.Arends@gmail.com", d.name, chainPath, accountKey, staging)) { loadSSL(certDir, keyFile); }
            continue;
          }

          BIO* bio = BIO_new_file(toStringz(chainPath), "r");
          X509* cert = PEM_read_bio_X509(bio, null, null, null);
          BIO_free(bio);
          if (cert is null) continue;

          ASN1_TIME* notAfter = X509_getm_notAfter(cert);
          int days, secs;
          ASN1_TIME_diff(&days, &secs, null, notAfter);
          X509_free(cert);

          log(Level.Verbose, "ACME: chain %s expires in %d days", domain, days);
          if (days < 30) { log(Level.Verbose, "ACME: renewing chain for %s", domain);
            if (renewCert(domain, "Danny.Arends@gmail.com", d.name, chainPath, accountKey, staging)) { loadSSL(certDir, keyFile); }
          }
        }
      }
      catch (Exception e) { error("ACME: checkAndRenew exception: %s", e.msg); }
      catch (Error e) { error("ACME: checkAndRenew error: %s", e.msg); }
    }).start();
  }

  // Base64url encode without padding
  string b64url(const(ubyte)[] data) { return Base64URL.encode(data).replace("=", ""); }

  // Fetch the ACME directory and return as JSONValue
  JSONValue acmeDirectory(bool staging) { return parseJSON(get(staging ? ACME_DIR_STAGING : ACME_DIR_PROD)); }

  // Compute and store key authorization for a challenge
  string prepareChallenge(JSONValue challenge, EVP_PKEY* pkey) {
    string token = challenge["token"].str;
    string keyAuth = token ~ "." ~ jwkThumbprint(pkey);
    synchronized(getAcmeMutex()) { acmeChallenges[token] = keyAuth; }
    log(Level.Trace, "ACME: challenge token: %s", token);
    return token;
  }

  // Finalize order by submitting CSR (DER encoded, base64url)
  JSONValue finalizeOrder(JSONValue order, JSONValue dir, EVP_PKEY* pkey, string kid, string csrPath) {
    // Load CSR from file
    BIO* bio = BIO_new_file(toStringz(csrPath), "r");
    X509_REQ* req = PEM_read_bio_X509_REQ(bio, null, null, null);
    if (req is null) { error("ACME: failed to load CSR from %s", csrPath); return JSONValue.init; }
    BIO_free(bio);

    // Convert CSR to DER
    ubyte* der = null;
    int derlen = i2d_X509_REQ(req, &der);
    ubyte[] csrDER = der[0 .. derlen].dup;
    CRYPTO_free(der, "acme.d", 0);
    X509_REQ_free(req);

    return acmePost(pkey, dir, order["finalize"].str, kid, `{"csr":"` ~ b64url(csrDER) ~ `"}`);
  }

  // Download and save certificate chain
  bool downloadCert(JSONValue order, JSONValue dir, EVP_PKEY* pkey, string kid, string certPath) {
    string certURL = order["certificate"].str;
    string nonce = acmeNonce(dir);
    string postData = buildJWS(pkey, nonce, certURL, kid, "");  // POST-as-GET

    char[] response;
    auto http = HTTP(certURL);
    http.method = HTTP.Method.post;
    http.addRequestHeader("Content-Type", "application/jose+json");
    http.postData = postData;
    http.onReceive = (ubyte[] data) { response ~= cast(char[]) data; return data.length; };
    http.perform();

    certPath.writeFile(cast(string) response);
    log(Level.Verbose, "ACME: certificate saved to %s", certPath);
    return true;
  }

  // Notify LE to validate the HTTP-01 challenge
  void triggerChallenge(JSONValue challenge, JSONValue dir, EVP_PKEY* pkey, string kid) {
    acmePost(pkey, dir, challenge["url"].str, kid, "{}");
  }

  // Poll authorization URL until valid or invalid
  bool pollAllAuthorizations(JSONValue order, JSONValue dir, EVP_PKEY* pkey, string kid) {
    foreach (i; 0 .. 10) {
      Thread.sleep(dur!"seconds"(2));
      bool allValid = true;
      foreach (authURL; order["authorizations"].array) {
        JSONValue auth = acmePost(pkey, dir, authURL.str, kid, "");
        string status = auth["status"].str;
        log(Level.Verbose, "ACME: authorization status for %s: %s", authURL.str, status);
        if (status == "invalid") { error("ACME: authorization failed"); return false; }
        if (status != "valid") allValid = false;
      }
      if (allValid) return true;
    }
    error("ACME: authorization timed out");
    return false;
  }

  // Place a new order for a domain certificate
  JSONValue newOrder(JSONValue dir, EVP_PKEY* pkey, string kid, string domain, out string orderURL) {
    return acmePost(pkey, dir, dir["newOrder"].str, kid, `{"identifiers":[{"type":"dns","value":"` ~ domain ~ `"},{"type":"dns","value":"www.` ~ domain ~ `"}]}`, &orderURL);
  }

  // Fetch challenge URL and token for HTTP-01 from an order
  JSONValue getHTTP01Challenge(string authURL, JSONValue dir, EVP_PKEY* pkey, string kid) {
    JSONValue auth = acmePost(pkey, dir, authURL, kid, "");
    foreach (challenge; auth["challenges"].array) { if (challenge["type"].str == "http-01") return challenge; }
    error("ACME: no HTTP-01 challenge found");
    return JSONValue.init;
  }

 // Compute SHA256 thumbprint of the public JWK
  string jwkThumbprint(EVP_PKEY* pkey) {
    // JWK thumbprint requires canonical JSON: sorted keys, no whitespace
    BIGNUM* bn_n = BN_new();
    BIGNUM* bn_e = BN_new();
    EVP_PKEY_get_bn_param(pkey, "n", &bn_n);
    EVP_PKEY_get_bn_param(pkey, "e", &bn_e);
    int nlen = BN_num_bytes(bn_n);
    int elen = BN_num_bytes(bn_e);
    ubyte[] nbuf = new ubyte[](nlen);
    ubyte[] ebuf = new ubyte[](elen);
    BN_bn2bin(bn_n, nbuf.ptr);
    BN_bn2bin(bn_e, ebuf.ptr);
    BN_free(bn_n);
    BN_free(bn_e);

    // RFC 7638 canonical form - keys must be sorted alphabetically
    string canonical = `{"e":"` ~ b64url(ebuf) ~ `","kty":"RSA","n":"` ~ b64url(nbuf) ~ `"}`;

    ubyte[32] digest;
    EVP_MD_CTX* ctx = EVP_MD_CTX_new();
    scope(exit) EVP_MD_CTX_free(ctx);
    EVP_DigestInit_ex(ctx, EVP_sha256(), null);
    EVP_DigestUpdate(ctx, canonical.ptr, canonical.length);
    uint dlen = 32;
    EVP_DigestFinal_ex(ctx, digest.ptr, &dlen);
    return b64url(digest[0 .. dlen]);
  }

  // Fetch a fresh nonce from ACME
  string acmeNonce(JSONValue dir) {
    auto http = HTTP(dir["newNonce"].str);
    http.method = HTTP.Method.head;
    string nonce;
    http.onReceiveHeader = (in char[] key, in char[] value) { if (icmp(key, "replay-nonce") == 0) nonce = value.idup; };
    http.perform();
    return nonce;
  }

  // Get account URL using existing account key (onlyReturnExisting)
  string acmeAccountURL(JSONValue dir, EVP_PKEY* pkey, string email) {
    string kid;
    acmePost(pkey, dir, dir["newAccount"].str, "", `{"termsOfServiceAgreed":true,"onlyReturnExisting":true,"contact":["mailto:` ~ email ~ `"]}`, &kid);
    log(Level.Verbose, "ACME: kid: %s", kid);
    return kid;
  }

  // Extract public key as JWK JSON (for newAccount header)
  string jwkPublic(EVP_PKEY* pkey) {
    import std.json : JSONValue, toJSON;
    BIGNUM* bn_n = BN_new();
    BIGNUM* bn_e = BN_new();
    EVP_PKEY_get_bn_param(pkey, "n", &bn_n);
    EVP_PKEY_get_bn_param(pkey, "e", &bn_e);

    int nlen = BN_num_bytes(bn_n);
    int elen = BN_num_bytes(bn_e);
    ubyte[] nbuf = new ubyte[](nlen);
    ubyte[] ebuf = new ubyte[](elen);
    BN_bn2bin(bn_n, nbuf.ptr);
    BN_bn2bin(bn_e, ebuf.ptr);
    BN_free(bn_n);
    BN_free(bn_e);

    JSONValue jwk = ["kty": JSONValue("RSA"), "n": JSONValue(b64url(nbuf)), "e": JSONValue(b64url(ebuf))];
    return toJSON(jwk);
  }

  // Sign data with RS256 using the account key
  ubyte[] signRS256(EVP_PKEY* pkey, const(ubyte)[] data) {
    EVP_MD_CTX* ctx = EVP_MD_CTX_new();
    if (ctx is null) { error("ACME: EVP_MD_CTX_new failed"); return null; }
    scope(exit) EVP_MD_CTX_free(ctx);

    if (EVP_DigestSignInit(ctx, null, EVP_sha256(), null, pkey) <= 0) { error("ACME: EVP_DigestSignInit failed"); return null; }
    if (EVP_DigestSignUpdate(ctx, data.ptr, data.length) <= 0) { error("ACME: EVP_DigestSignUpdate failed"); return null; }
    size_t siglen;
    if (EVP_DigestSignFinal(ctx, null, &siglen) <= 0) { error("ACME: EVP_DigestSignFinal (len) failed"); return null; }
    ubyte[] sig = new ubyte[](siglen);
    if (EVP_DigestSignFinal(ctx, sig.ptr, &siglen) <= 0) { error("ACME: EVP_DigestSignFinal failed"); return null; }
    return sig[0 .. siglen];
  }

  // Build a JWS signed request
  string buildJWS(EVP_PKEY* pkey, string nonce, string url, string kid, string payload) {
    JSONValue hdr;
    if (kid.length) {
      hdr = ["alg": JSONValue("RS256"), "nonce": JSONValue(nonce), "url": JSONValue(url), "kid": JSONValue(kid)];
    } else {
      hdr = ["alg": JSONValue("RS256"), "nonce": JSONValue(nonce), "url": JSONValue(url), "jwk": JSONValue(parseJSON(jwkPublic(pkey)))];
    }
    string protected_ = b64url(cast(ubyte[]) toJSON(hdr));
    string payload64 = payload.length ? b64url(cast(ubyte[]) payload) : "";
    string sigInput = protected_ ~ "." ~ payload64;
    ubyte[] sig = signRS256(pkey, cast(ubyte[]) sigInput);
    return `{"protected":"` ~ protected_ ~ `","payload":"` ~ payload64 ~ `","signature":"` ~ b64url(sig) ~ `"}`;
  }

  EVP_PKEY* loadAccountKey(string path = ".ssl/account.key") {
    BIO* bio = BIO_new_file(toStringz(path), "r");
    if (bio is null) { error("ACME: cannot open account key: %s", path); return null; }
    EVP_PKEY* pkey = PEM_read_bio_PrivateKey(bio, null, null, null);
    BIO_free(bio);
    if (pkey is null) { error("ACME: failed to parse account key"); return null; }
    log(Level.Always, "ACME: account key loaded from %s", path);
    return pkey;
  }
}
