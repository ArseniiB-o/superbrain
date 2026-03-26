#!/usr/bin/env bash
# teams/marketing/lead.sh — Marketing Team Lead

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$SCRIPT_DIR/../.."

source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"
source "$AGENTS2_DIR/lib/fallback.sh"

TEAM="marketing"
PRIMARY_MODEL="deepseek/deepseek-chat"
FALLBACK1_MODEL="openai/gpt-4o"
FALLBACK2_MODEL="openai/gpt-4o-mini"

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
printf '%s' "You are a Chief Marketing Officer and Growth Expert with 22 years of experience. You have scaled B2B and B2C companies from 0 to \$100M ARR, led marketing at Dropbox and HubSpot, and built demand generation engines across SaaS, marketplace, and consumer products. Deep expertise in: go-to-market strategy, product-led growth, content marketing, SEO/SEM, paid acquisition (Google, Meta, LinkedIn), email marketing, brand positioning, competitive messaging, market sizing (TAM/SAM/SOM with real data), customer persona development, and growth metrics (CAC, LTV, payback period, viral coefficient). You think in funnels and feedback loops. You validate every assumption with data. You always identify the lowest-cost, highest-impact acquisition channel first. For market analysis, you cite real industry reports, benchmark data, and comparable company trajectories." > "$SYSPROMPT_FILE"

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

# --- Self-assessment: what this team couldn't cover ---
SELF_ASSESSMENT="

---
## 🔍 [$TEAM Team] Self-Assessment
**What I covered:** ${TASK_SUMMARY:0:60}
**What may need additional teams:**
- If this involves financial projections or unit economics modeling → finance team
- If this involves EU/GDPR data collection compliance → legal team
- If this involves validating market data with primary sources → researcher team
- If this involves competitive risk or market timing risk → risk team
- If this involves deployment of marketing tech stack → devops team"

RESULT="${RESULT}${SELF_ASSESSMENT}"

log_action "$TEAM" "lead" "$PRIMARY_MODEL" "SUCCESS" "$TASK_SUMMARY" "$OPTIMIZED_PROMPT" "$RESULT"
echo "  ✅ [$TEAM/lead] Done" >&2

echo "$RESULT"
