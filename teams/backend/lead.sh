#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"

TEAM="backend"
ROLE1_NAME="architect"
ROLE2_NAME="coder"
ROLE3_NAME="reviewer"
AGENT1_MODEL="deepseek/deepseek-chat"
AGENT2_MODEL="openai/gpt-4o-mini"
AGENT3_MODEL="google/gemini-2.0-flash-001"

TMPFILE=$(mktemp)
WORK_DIR=$(mktemp -d)
trap 'rm -f "$TMPFILE"; rm -rf "$WORK_DIR"' EXIT

if [ ! -t 0 ]; then
    { [ -n "${1:-}" ] && printf '%s\n\n' "$1"; cat; } > "$TMPFILE"
elif [ -n "${1:-}" ]; then
    printf '%s' "$1" > "$TMPFILE"
else
    echo "Error: provide task via argument or stdin" >&2; exit 1
fi

RAW_TASK=$(cat "$TMPFILE")
TASK_SUMMARY="${RAW_TASK:0:120}"
log_action "$TEAM" "lead" "3-parallel" "RUNNING" "$TASK_SUMMARY" "$RAW_TASK"
echo "🔧 [$TEAM] Starting: ${TASK_SUMMARY:0:60}..." >&2

# Phase 1: 3 PE calls in parallel
echo "  📝 [$TEAM] Team PE optimizing for $ROLE1_NAME + $ROLE2_NAME + $ROLE3_NAME..." >&2
{ echo "$RAW_TASK" | bash "$SCRIPT_DIR/prompt_engineer.sh" "$ROLE1_NAME" > "$WORK_DIR/p1.txt" 2>/dev/null || cp "$TMPFILE" "$WORK_DIR/p1.txt"; } &
{ echo "$RAW_TASK" | bash "$SCRIPT_DIR/prompt_engineer.sh" "$ROLE2_NAME" > "$WORK_DIR/p2.txt" 2>/dev/null || cp "$TMPFILE" "$WORK_DIR/p2.txt"; } &
{ echo "$RAW_TASK" | bash "$SCRIPT_DIR/prompt_engineer.sh" "$ROLE3_NAME" > "$WORK_DIR/p3.txt" 2>/dev/null || cp "$TMPFILE" "$WORK_DIR/p3.txt"; } &
wait
echo "  ✅ [$TEAM] Prompts ready" >&2

# Phase 2: 3 agents in parallel
echo "  🤖 [$TEAM] $ROLE1_NAME($AGENT1_MODEL) + $ROLE2_NAME($AGENT2_MODEL) + $ROLE3_NAME($AGENT3_MODEL)..." >&2

AGENT1_SYSPROMPT='You are a Staff Backend Engineer with 28 years of experience at Google and Amazon Web Services. Your role in this task: produce the solution architecture ONLY — no implementation code. Deliver: complete API contract (endpoint table with method/path/request/response/codes), data model (ERD-style description), service layer design, authentication strategy, rate limiting design, error handling approach. Be specific and complete.'

AGENT2_SYSPROMPT='You are a Senior Backend Engineer with 15 years experience. Implement the backend solution completely. Requirements: full input validation on all user-facing fields, parameterized queries (never concatenate user input into SQL), proper HTTP status codes, RFC 7807 error format, transaction management for multi-step operations, structured logging (no sensitive data in logs). Deliver complete, runnable code.'

AGENT3_SYSPROMPT='You are a Backend Security and Performance Reviewer (OWASP Top 10 specialist). Review the task/code and find: injection vulnerabilities (SQL, NoSQL, command), broken authentication, missing authorization checks, sensitive data exposure, N+1 queries, missing indexes, race conditions. Each finding: [CRITICAL/HIGH/MEDIUM/LOW] | Vulnerability Type | Location | Exploit Scenario | Specific Fix.'

SYNTH_SYSPROMPT='You are the Backend Team Lead integrating Architecture Design, Implementation Code, and Security Review. Produce: (1) Architecture summary (from Architect), (2) Complete implementation with all security fixes applied (from Coder + Reviewer corrections), (3) Security findings summary. CRITICAL and HIGH findings MUST be fixed in the code — do not just list them.'

{
SYSTEM_PROMPT="$AGENT1_SYSPROMPT" \
"$AGENTS2_DIR/call_model.sh" "$AGENT1_MODEL" < "$WORK_DIR/p1.txt" > "$WORK_DIR/r1.txt" 2>/dev/null \
    || printf '[%s/%s failed]\n' "$TEAM" "$ROLE1_NAME" > "$WORK_DIR/r1.txt"
} &
{
SYSTEM_PROMPT="$AGENT2_SYSPROMPT" \
"$AGENTS2_DIR/call_model.sh" "$AGENT2_MODEL" < "$WORK_DIR/p2.txt" > "$WORK_DIR/r2.txt" 2>/dev/null \
    || printf '[%s/%s failed]\n' "$TEAM" "$ROLE2_NAME" > "$WORK_DIR/r2.txt"
} &
{
SYSTEM_PROMPT="$AGENT3_SYSPROMPT" \
"$AGENTS2_DIR/call_model.sh" "$AGENT3_MODEL" < "$WORK_DIR/p3.txt" > "$WORK_DIR/r3.txt" 2>/dev/null \
    || printf '[%s/%s failed]\n' "$TEAM" "$ROLE3_NAME" > "$WORK_DIR/r3.txt"
} &
wait
echo "  ✅ [$TEAM] All 3 done" >&2

# Phase 3: Team synthesis
COMBINED="## [$ROLE1_NAME — $AGENT1_MODEL]
$(cat "$WORK_DIR/r1.txt")

## [$ROLE2_NAME — $AGENT2_MODEL]
$(cat "$WORK_DIR/r2.txt")

## [$ROLE3_NAME — $AGENT3_MODEL]
$(cat "$WORK_DIR/r3.txt")"

echo "  🔗 [$TEAM] Synthesizing..." >&2
RESULT=$(printf '%s' "$COMBINED" | \
SYSTEM_PROMPT="$SYNTH_SYSPROMPT" \
"$AGENTS2_DIR/call_model.sh" "openai/gpt-4o" 2>/dev/null) || RESULT="$COMBINED"

[ -z "$RESULT" ] && RESULT="$COMBINED"

memory_append "$TEAM" "$(date '+%Y-%m-%d'): ${TASK_SUMMARY:0:80}"
log_action "$TEAM" "lead" "3-parallel" "SUCCESS" "$TASK_SUMMARY" "$RAW_TASK" "$RESULT"

RESULT="${RESULT}
---
## 🔍 [$TEAM Team] Self-Assessment
Specialists: Architect(deepseek) + Coder(gpt-4o-mini) + Reviewer(gemini-flash)
Additional teams:
- security: full OWASP penetration testing beyond code review
- data: complex database schema optimization and query tuning
- devops: containerization, CI/CD pipeline, environment configuration
- qa: integration tests, load testing strategy"

echo "  ✅ [$TEAM] Done" >&2
echo "$RESULT"
