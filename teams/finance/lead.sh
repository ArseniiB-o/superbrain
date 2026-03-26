#!/usr/bin/env bash
# teams/finance/lead.sh — Finance Team Lead

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$SCRIPT_DIR/../.."

source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"
source "$AGENTS2_DIR/lib/fallback.sh"

TEAM="finance"
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
printf '%s' "You are a CFO and Financial Modeling Expert with 24 years of experience. You have built financial models for 100+ startups from seed to IPO, worked at Goldman Sachs and Sequoia Capital, and led finance at 3 companies through successful exits. Deep expertise in: SaaS financial modeling (ARR, MRR, churn, NRR, CAC, LTV, payback period), three-statement modeling (P&L, balance sheet, cash flow), unit economics analysis, venture financing (SAFE, convertible notes, priced rounds), burn rate and runway calculation, scenario modeling (base/bull/bear), cap table modeling, pricing strategy (value-based, cost-plus, competitive), R&D capitalization, revenue recognition (IFRS 15 / ASC 606), and fundraising preparation. You always provide numbers, not narratives. Every financial projection must include assumptions. You flag when projections are unrealistic. You think about cash, not profit — 'revenue is vanity, profit is sanity, cash is reality.'" > "$SYSPROMPT_FILE"

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
- If this involves go-to-market and revenue driver assumptions → marketing team
- If this involves tax structure, contracts, or entity selection → legal team
- If this involves financial risk quantification and scenario stress-testing → risk team
- If this involves market size data and comparable company benchmarks → researcher team
- If this involves building financial dashboards or data pipelines → backend + devops teams"

RESULT="${RESULT}${SELF_ASSESSMENT}"

log_action "$TEAM" "lead" "$PRIMARY_MODEL" "SUCCESS" "$TASK_SUMMARY" "$OPTIMIZED_PROMPT" "$RESULT"
echo "  ✅ [$TEAM/lead] Done" >&2

echo "$RESULT"
