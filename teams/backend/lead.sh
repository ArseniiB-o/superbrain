#!/usr/bin/env bash
# teams/backend/lead.sh — Backend Team Lead
# Orchestrates the backend team: optimizes prompt → tries models → updates memory → returns result

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load .env if present
ENV_FILE="${AGENTS2_DIR}/.env"
if [[ -f "$ENV_FILE" ]]; then
    set -a; source "$ENV_FILE"; set +a
fi

source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"
source "$AGENTS2_DIR/lib/fallback.sh"

TEAM="backend"
PRIMARY_MODEL="deepseek/deepseek-chat"
FALLBACK1_MODEL="openai/gpt-4o-mini"
FALLBACK2_MODEL="google/gemini-2.0-flash-001"

# ── System prompt ──────────────────────────────────────────────────────────────
TEAM_SYSTEM_PROMPT="You are a Staff Backend Engineer with 28 years of experience designing and scaling distributed systems at Google, Amazon, and multiple funded startups. You have shipped production systems serving 100M+ users. Your expertise spans: RESTful and GraphQL API design, microservices and monolith architecture, SQL (PostgreSQL, MySQL) and NoSQL (MongoDB, Redis) at scale, message queues (Kafka, RabbitMQ), authentication/authorization (OAuth 2.0, JWT, RBAC), caching strategies, and database optimization. You write clean, SOLID code with proper error handling, logging, and observability. You never ship without considering rate limiting, input validation, and proper HTTP status codes. Security is always your second thought (after correctness)."

# ── Read input ─────────────────────────────────────────────────────────────────
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

if [ ! -t 0 ]; then
    { [ -n "${1:-}" ] && printf '%s\n\n' "$1"; cat; } > "$TMPFILE"
elif [ -n "${1:-}" ]; then
    printf '%s' "$1" > "$TMPFILE"
else
    echo "Error: provide task via argument or stdin" >&2; exit 1
fi

RAW_TASK=$(cat "$TMPFILE")
TASK_SUMMARY="${RAW_TASK:0:120}"

log_action "$TEAM" "lead" "$PRIMARY_MODEL" "RUNNING" "$TASK_SUMMARY" "$RAW_TASK"
echo "🔧 [$TEAM/lead] Starting: ${TASK_SUMMARY:0:70}..." >&2

# ── Read team memory ───────────────────────────────────────────────────────────
TEAM_MEMORY=$(memory_read "$TEAM")

# ── Optimize prompt ────────────────────────────────────────────────────────────
echo "  📝 [$TEAM/lead] Optimizing prompt..." >&2
OPTIMIZED_PROMPT=$(echo "$RAW_TASK" | \
    TEAM_MEMORY="$TEAM_MEMORY" \
    "$AGENTS2_DIR/lib/prompt_engineer.sh" "$TEAM" 2>/dev/null || echo "$RAW_TASK")

PROMPT_FILE=$(mktemp)
SYSPROMPT_FILE=$(mktemp)
trap 'rm -f "$TMPFILE" "$PROMPT_FILE" "$SYSPROMPT_FILE"' EXIT

printf '%s' "$OPTIMIZED_PROMPT" > "$PROMPT_FILE"
printf '%s' "$TEAM_SYSTEM_PROMPT" > "$SYSPROMPT_FILE"

# ── Run with fallback ──────────────────────────────────────────────────────────
echo "  🤖 [$TEAM/lead] Running agent (primary: $PRIMARY_MODEL)..." >&2
RESULT=$(run_with_fallback "$PROMPT_FILE" "$SYSPROMPT_FILE" \
    "$PRIMARY_MODEL" "$FALLBACK1_MODEL" "$FALLBACK2_MODEL") || true
EXIT_CODE=${PIPESTATUS[0]:-$?}

if [ "${EXIT_CODE:-0}" -ne 0 ] || [ -z "${RESULT:-}" ]; then
    log_action "$TEAM" "lead" "$PRIMARY_MODEL" "FAILED" "$TASK_SUMMARY" "$RAW_TASK" ""
    echo "❌ [$TEAM/lead] All models failed" >&2
    exit 1
fi

# ── Update memory ──────────────────────────────────────────────────────────────
LEARNING="$(date '+%Y-%m-%d'): ${TASK_SUMMARY:0:80}"
memory_append "$TEAM" "$LEARNING"

# ── Log success ───────────────────────────────────────────────────────────────
log_action "$TEAM" "lead" "${FALLBACK_USED_MODEL:-$PRIMARY_MODEL}" "SUCCESS" \
    "$TASK_SUMMARY" "$OPTIMIZED_PROMPT" "$RESULT"
echo "  ✅ [$TEAM/lead] Done (model: ${FALLBACK_USED_MODEL:-$PRIMARY_MODEL}, attempts: ${FALLBACK_ATTEMPTS:-1})" >&2

echo "$RESULT"
