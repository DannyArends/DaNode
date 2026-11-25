Security Policy
---------------

### Reporting a Vulnerability
Please report vulnerabilities by opening a [GitHub issue](https://github.com/DannyArends/DaNode/issues) or emailing danny.arends@gmail.com.

### Mitigations in Place

- **Shell injection**: CGI commands run as an argv array via `spawnProcess` (no shell), built in `Request.command()` in `request.d`
- **Path traversal**: requests are validated via `safePath()` in `filesystem.d`
- **XSS**: directory listings are sanitized via `htmlEscape()` (`functions.d`) in `browseDir` (`response.d`)
- **Request size**: capped at 2MB in `client.d`
- **Rate limiting**: per-IP connection limiting in `server.d`
