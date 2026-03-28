# Team Memory: backend
Last updated: 2026-03-28 10:47

## Accumulated Knowledge
- Always validate ALL user input at API boundaries
- Use parameterized queries — never string concatenation in SQL
- Rate limiting: required on all public endpoints (100 req/min default)
- Auth: JWT with 15m access token, 7d refresh token
- Error responses: always return RFC 7807 Problem Details format
- Logging: structured JSON logs, never log passwords or tokens
