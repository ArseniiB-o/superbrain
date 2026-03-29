# Team Memory: security
Last updated: 2026-03-29 18:20

## Accumulated Knowledge
- ALWAYS check: SQL injection, XSS, CSRF, SSRF, XXE, broken auth
- Secrets: never in code, env vars, or logs — use vault/secrets manager
- Cryptography: AES-256-GCM for encryption, bcrypt/argon2 for passwords
- Never use MD5 or SHA1 for security purposes
- CORS: explicit allowlist only, never wildcard with credentials
- HTTP headers: always set CSP, HSTS, X-Frame-Options, X-Content-Type-Options
- JWT: verify signature, check expiry, use RS256 not HS256 for production
- [2026-03-27 21:44] 2026-03-27: What are 2 REST API security practices?
- [2026-03-28 10:34] 2026-03-28: Implement escapeHtml function to ensure XSS safety for all dynamic content rende
- [2026-03-28 11:12] 2026-03-28: Validate SSL certificate for obstudios.de and check for expiration or misconfigu
- [2026-03-28 11:32] 2026-03-28: Implement all security requirements including CSP meta tag, external link protec
- [2026-03-29 18:20] 2026-03-29: Implement all security fixes including CSP headers, XSS protections, form harden
