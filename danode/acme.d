module danode.acme;

version(SSL) {
  import danode.imports;
  import danode.includes;
  import danode.log : info, warning, error;
  import danode.ssl : reloadSSL;
  import danode.functions : writeinfile;

  immutable string ACME_DIR_PROD    = "https://acme-v02.api.letsencrypt.org/directory";
  immutable string ACME_DIR_STAGING = "https://acme-staging-v02.api.letsencrypt.org/directory";

  __gshared string[string] acmeChallenges; // Shared challenge store: token -> keyAuthorization
  __gshared Mutex acmeMutex;
  Mutex getAcmeMutex() {
    if (acmeMutex is null) acmeMutex = new Mutex();
    return acmeMutex;
  }

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
    info("ACME: POST %s -> %s", url, cast(string) response);
    return parseJSON(response);
  }

  // Full ACME renewal flow
  bool renewCert(string domain, string email, string csrPath, string chainPath, string accountKey, bool staging) {
    info("ACME: starting renewal for %s", domain);

    EVP_PKEY* pkey = loadAccountKey(accountKey);
    if (pkey is null) return false;

    JSONValue dir = acmeDirectory(staging);
    string kid = acmeAccountURL(dir, pkey, email);
    if (kid.length == 0) { error("ACME: failed to get account URL"); return false; }
    info("ACME: account URL: %s", kid);

    string orderURL;
    JSONValue order = newOrder(dir, pkey, kid, domain, orderURL);
    info("ACME: order: %s, orderURL: %s", order.toString(), orderURL);
    JSONValue challenge = getHTTP01Challenge(order, dir, pkey, kid);
    if (challenge.type == JSONType.null_) return false;

    string token = prepareChallenge(challenge, pkey);
    triggerChallenge(challenge, dir, pkey, kid);

    if (!pollAuthorization(order, dir, pkey, kid)) { synchronized(getAcmeMutex()) { acmeChallenges.remove(token); } return false; }
    synchronized(getAcmeMutex()) { acmeChallenges.remove(token); }

    JSONValue finalized = finalizeOrder(order, dir, pkey, kid, csrPath);
    info("ACME: order status: %s, finalized: %s", finalized["status"].str, finalized.toString());

    foreach (i; 0 .. 10) { // Poll until certificate is ready
      if (finalized["status"].str == "valid") break;
      Thread.sleep(dur!"seconds"(5));
      finalized = acmePost(pkey, dir, orderURL, kid, "");
    }
    return downloadCert(finalized, dir, pkey, kid, chainPath);
  }

    // Check cert expiry and renew if < 30 days remaining
  void checkAndRenew(string certDir = ".ssl/", string keyFile = ".ssl/server.key", string accountKey = ".ssl/account.key", bool staging = true) {
    info("ACME: checkAndRenew called on '%s' with key '%s'", certDir, accountKey);
    foreach (DirEntry d; dirEntries(certDir, SpanMode.shallow)) {
      if (!d.name.endsWith(".csr")) continue;
      string domain = baseName(d.name, ".csr");
      string chainPath = certDir ~ domain ~ ".chain";

      auto _certDir = certDir; auto _keyFile = keyFile; auto _domain = domain;
      auto _csr = d.name; auto _chain = chainPath; auto _key = accountKey; auto _staging = staging;
      if (!exists(chainPath)) { info("ACME: no chain found for %s, bootstrapping", domain);
        new Thread({
          if (renewCert(_domain, "Danny.Arends@gmail.com", _csr, _chain, _key, _staging)) {
            reloadSSL(_certDir, _keyFile);
          }
        }).start();
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

      info("ACME: chain %s expires in %d days", domain, days);
      if (days < 30) { info("ACME: renewing chain for %s", domain);
        new Thread({
          if (renewCert(_domain, "Danny.Arends@gmail.com", _csr, _chain, _key, _staging)) {
            reloadSSL(_certDir, _keyFile);
          }
        }).start();
      }
    }
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
    info("ACME: challenge token: %s", token);
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

    writeinfile(certPath, cast(string) response);
    info("ACME: certificate saved to %s", certPath);
    return true;
  }

  // Notify LE to validate the HTTP-01 challenge
  void triggerChallenge(JSONValue challenge, JSONValue dir, EVP_PKEY* pkey, string kid) {
    acmePost(pkey, dir, challenge["url"].str, kid, "{}");
  }

  // Poll authorization URL until valid or invalid
  bool pollAuthorization(JSONValue order, JSONValue dir, EVP_PKEY* pkey, string kid) {
    string authURL = order["authorizations"][0].str;
    foreach (i; 0 .. 10) {
      Thread.sleep(dur!"seconds"(2));
      JSONValue auth = acmePost(pkey, dir, authURL, kid, "");

      string status = auth["status"].str;
      info("ACME: authorization status: %s", status);
      if (status == "valid")   return true;
      if (status == "invalid") { error("ACME: authorization failed"); return false; }
    }
    error("ACME: authorization timed out");
    return false;
  }

  // Place a new order for a domain certificate
  JSONValue newOrder(JSONValue dir, EVP_PKEY* pkey, string kid, string domain, out string orderURL) {
    return acmePost(pkey, dir, dir["newOrder"].str, kid, `{"identifiers":[{"type":"dns","value":"` ~ domain ~ `"}]}`, &orderURL);
  }

  // Fetch challenge URL and token for HTTP-01 from an order
  JSONValue getHTTP01Challenge(JSONValue order, JSONValue dir, EVP_PKEY* pkey, string kid) {
    JSONValue auth = acmePost(pkey, dir, order["authorizations"][0].str, kid, "");

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
    info("ACME: kid: %s", kid);
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
    info("ACME: account key loaded from %s", path);
    return pkey;
  }
}