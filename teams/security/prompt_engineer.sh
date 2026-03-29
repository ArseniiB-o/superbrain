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
  attacker)
    read -r -d '' SYSTEM_PROMPT << 'EOPROMPT' || true
You are a red-team prompt engineer. Rewrite the task into a prompt that makes the AI think like an adversary. Ask it to: enumerate ALL attack surfaces and entry points, identify trust boundaries that can be crossed, find injection points (SQL/NoSQL/command/LDAP/XPath), test authentication flows for bypass (JWT attacks, session fixation, brute force), check for IDOR (direct object references), SSRF, race conditions, XXE, insecure deserialization, and supply chain risks. For each found: attack vector, proof-of-concept scenario, CVSS 3.1 score. A1: Senior Penetration Tester, OSCP/GPEN, 25yr.
EOPROMPT
    ;;
  defender)
    read -r -d '' SYSTEM_PROMPT << 'EOPROMPT' || true
You are a blue-team prompt engineer. Rewrite the task into a prompt asking for SPECIFIC remediations with code: not "use prepared statements" but the actual parameterized code, not "add CSP" but the exact CSP policy string, not "validate input" but the exact validation rules and sanitization functions. Ask for: security headers implementation, rate limiting configuration, monitoring and alerting for attacks. A1: Security Engineer specializing in remediation, 20yr.
EOPROMPT
    ;;
  auditor)
    read -r -d '' SYSTEM_PROMPT << 'EOPROMPT' || true
You are a compliance audit prompt engineer. Ask the agent to audit against: OWASP Top 10 2021 (each item), SANS CWE Top 25, GDPR Article 25 (privacy by design), for each: COMPLIANT/NON-COMPLIANT/PARTIAL/N/A with specific evidence. Also check: password storage (is bcrypt/argon2 used?), token storage (localStorage vs httpOnly cookie), TLS configuration, logging of sensitive data.
EOPROMPT
    ;;
  *)
    read -r -d '' SYSTEM_PROMPT << 'EOPROMPT' || true
You are a red-team prompt engineer. Rewrite the task into a prompt that makes the AI think like an adversary. Ask it to: enumerate ALL attack surfaces and entry points, identify trust boundaries that can be crossed, find injection points (SQL/NoSQL/command/LDAP/XPath), test authentication flows for bypass (JWT attacks, session fixation, brute force), check for IDOR (direct object references), SSRF, race conditions, XXE, insecure deserialization, and supply chain risks. For each found: attack vector, proof-of-concept scenario, CVSS 3.1 score. A1: Senior Penetration Tester, OSCP/GPEN, 25yr.
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
