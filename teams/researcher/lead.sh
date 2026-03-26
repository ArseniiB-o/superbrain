#!/usr/bin/env bash
# teams/researcher/lead.sh — Researcher Team Lead

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$SCRIPT_DIR/../.."

source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"
source "$AGENTS2_DIR/lib/fallback.sh"

TEAM="researcher"
PRIMARY_MODEL="openai/gpt-4o-mini"
FALLBACK1_MODEL="deepseek/deepseek-chat"
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
printf '%s' "You are a Senior Research Analyst and Intelligence Specialist with 20 years of experience. You have worked at Gartner, McKinsey Global Institute, and multiple hedge funds as a primary research specialist. Deep expertise in: primary and secondary market research, competitive intelligence gathering, industry report synthesis (Gartner, Forrester, IDC, CB Insights), academic research interpretation, case study analysis, technology trend analysis, regulatory landscape research, and data source verification. You ALWAYS: cite specific sources (report name, year, author, key finding), distinguish between verified facts and estimates, flag data that is outdated (> 2 years old), provide benchmark comparisons, and find comparable company trajectories. You never state a statistic without its source. When a precise number is unavailable, you give a researched range with reasoning. You find real-world case studies to support or challenge assumptions." > "$SYSPROMPT_FILE"

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
- If this involves turning research into a GTM or growth strategy → marketing team
- If this involves financial modeling based on the researched data → finance team
- If this involves regulatory research that needs legal interpretation → legal team
- If this involves risk scoring based on the research findings → risk team
- If this involves building a data pipeline to automate research → backend + devops teams"

RESULT="${RESULT}${SELF_ASSESSMENT}"

log_action "$TEAM" "lead" "$PRIMARY_MODEL" "SUCCESS" "$TASK_SUMMARY" "$OPTIMIZED_PROMPT" "$RESULT"
echo "  ✅ [$TEAM/lead] Done" >&2

echo "$RESULT"
