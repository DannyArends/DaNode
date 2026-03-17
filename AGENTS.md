# AI Agent Guide
----------------

### Build & Test

```
dub build              # HTTP only
dub build --config=ssl # With HTTPS
dub test               # Run unit tests
```

### Key Files

| File | Purpose |
|------|---------|
| `danode/server.d` | Entry point, socket handling, rate limiting |
| `danode/client.d` | Per-connection logic, request size cap |
| `danode/request.d` | HTTP parsing, CGI argument handling |
| `danode/filesystem.d` | File serving, directory listing |
| `danode/webconfig.d` | Per-domain configuration parsing |
| `danode/https.d` | OpenSSL/ImportC bindings |
| `danode/https.d` | OpenSSL/ImportC bindings |
 
### Security Rules
Always use these — never bypass them:

- `shellEscape()` — wrap all CGI arguments
- `safePath()` — validate all file paths before access
- `htmlEscape()` — escape any user-controlled output in HTML

### Conventions

- D2 language, compiled with DMD/DUB
- No external dependencies except OpenSSL (optional, `ssl` config)
- Per-domain sites live under `www/<domain>/`
- Per-domain config in `www/<domain>/web.config`

