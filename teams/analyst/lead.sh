#!/usr/bin/env bash
# teams/analyst/lead.sh — Analyst Team Lead

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$SCRIPT_DIR/../.."

source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"
source "$AGENTS2_DIR/lib/fallback.sh"

TEAM="analyst"
PRIMARY_MODEL="deepseek/deepseek-chat"
FALLBACK1_MODEL="openai/gpt-4o-mini"
FALLBACK2_MODEL="google/gemini-2.0-flash-001"

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

TEAM_MEMORY=$(memory_read "$TEAM")

echo "  📝 [$TEAM/lead] Optimizing prompt..." >&2
OPTIMIZED_PROMPT=$(echo "$RAW_TASK" | \
    TEAM_MEMORY="$TEAM_MEMORY" \
    "$AGENTS2_DIR/lib/prompt_engineer.sh" "$TEAM" 2>/dev/null || echo "$RAW_TASK")

PROMPT_FILE=$(mktemp)
SYSPROMPT_FILE=$(mktemp)
trap 'rm -f "$TMPFILE" "$PROMPT_FILE" "$SYSPROMPT_FILE"' EXIT

printf '%s' "$OPTIMIZED_PROMPT" > "$PROMPT_FILE"
printf '%s' "You are a Senior Business Analyst and Data Scientist with 22 years of experience at McKinsey, Bain, and multiple tech companies. You transform raw data and business problems into clear, actionable insights. Expert in: market analysis, competitive intelligence, unit economics (CAC, LTV, churn, NRR), cohort analysis, funnel optimization, financial modeling, SQL analytics, Python (pandas, matplotlib, seaborn), A/B testing design and statistical significance, business case development, and executive storytelling. You always structure analysis with: situation → complication → key question → hypothesis → data → insight → recommendation. You never present data without context. Every number needs a comparison point (vs last period, vs benchmark, vs target)." > "$SYSPROMPT_FILE"

echo "  🤖 [$TEAM/lead] Running agent (primary: $PRIMARY_MODEL)..." >&2
RESULT=$(run_with_fallback "$PROMPT_FILE" "$SYSPROMPT_FILE" \
    "$PRIMARY_MODEL" "$FALLBACK1_MODEL" "$FALLBACK2_MODEL")
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ] || [ -z "$RESULT" ]; then
    log_action "$TEAM" "lead" "$PRIMARY_MODEL" "FAILED" "$TASK_SUMMARY" "$RAW_TASK" ""
    echo "❌ [$TEAM/lead] All models failed" >&2
    exit 1
fi

LEARNING="$(date '+%Y-%m-%d'): ${TASK_SUMMARY:0:80}"
memory_append "$TEAM" "$LEARNING"

log_action "$TEAM" "lead" "$PRIMARY_MODEL" "SUCCESS" "$TASK_SUMMARY" "$OPTIMIZED_PROMPT" "$RESULT"
echo "  ✅ [$TEAM/lead] Done" >&2

echo "$RESULT"
