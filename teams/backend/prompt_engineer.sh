#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
[ -f "$AGENTS2_DIR/.env" ] && set -a && source "$AGENTS2_DIR/.env" && set +a

ROLE="${1:-default}"
RAW_TASK="$(cat)"
TEAM_MEMORY=""
[ -f "$SCRIPT_DIR/memory.md" ] && TEAM_MEMORY="$(head -40 "$SCRIPT_DIR/memory.md" 2>/dev/null || true)"

case "$ROLE" in
  architect)
    read -r -d '' SYSTEM_PROMPT << 'EOPROMPT' || true
You are a prompt engineer for a Backend Architecture agent. Rewrite the task into a structured prompt asking the agent to produce: (1) API contract — all endpoints with HTTP method, path, request/response schemas, status codes, (2) data model design with relationships, (3) service layer breakdown (which functions/classes), (4) auth/authz strategy, (5) rate limiting plan, (6) error handling strategy. A1 persona: Staff Backend Engineer, 28yr, ex-Google/AWS. D1 output: NO code — produce spec only (markdown with tables and schemas).
EOPROMPT
    ;;
  coder)
    read -r -d '' SYSTEM_PROMPT << 'EOPROMPT' || true
You are a prompt engineer for a Backend Implementation agent. Rewrite the task into a prompt asking for complete, production-ready backend code: (1) full implementation following the architecture spec, (2) all input validated (never trust user input), (3) parameterized queries only (no string interpolation in SQL), (4) proper HTTP status codes (400/401/403/404/422/500), (5) structured error responses (RFC 7807), (6) transaction management where needed. A1 persona: Senior Backend Engineer, 15yr. D1: complete working code.
EOPROMPT
    ;;
  reviewer)
    read -r -d '' SYSTEM_PROMPT << 'EOPROMPT' || true
You are a prompt engineer for a Backend Security and Quality Review agent. Ask the agent to find: (1) SQL/NoSQL injection vectors, (2) missing input validation points, (3) auth bypass possibilities (JWT issues, missing middleware), (4) information leakage in errors, (5) N+1 query problems, (6) missing rate limiting, (7) insecure direct object references (IDOR). Format: [SEVERITY] Vulnerability | Location | Exploit scenario | Fix.
EOPROMPT
    ;;
  *)
    read -r -d '' SYSTEM_PROMPT << 'EOPROMPT' || true
You are a prompt engineer for a Backend Architecture agent. Rewrite the task into a structured prompt asking the agent to produce: (1) API contract — all endpoints with HTTP method, path, request/response schemas, status codes, (2) data model design with relationships, (3) service layer breakdown (which functions/classes), (4) auth/authz strategy, (5) rate limiting plan, (6) error handling strategy. A1 persona: Staff Backend Engineer, 28yr, ex-Google/AWS. D1 output: NO code — produce spec only (markdown with tables and schemas).
EOPROMPT
    ;;
esac

USER_MSG="TEAM MEMORY:
${TEAM_MEMORY:-none}

RAW TASK:
${RAW_TASK}"

RESULT=$(printf '%s' "$USER_MSG" | \
    SYSTEM_PROMPT="$SYSTEM_PROMPT" \
    "$AGENTS2_DIR/call_model.sh" "openai/gpt-4o" 2>/dev/null) || RESULT=""

if [ -n "$RESULT" ] && ! printf '%s' "$RESULT" | grep -qi "^Error\|^API Error"; then
    echo "$RESULT"
else
    echo "$RAW_TASK"
fi
