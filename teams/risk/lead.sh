#!/usr/bin/env bash
# teams/risk/lead.sh — Risk Team Lead

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$SCRIPT_DIR/../.."

source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"
source "$AGENTS2_DIR/lib/fallback.sh"

TEAM="risk"
PRIMARY_MODEL="openai/gpt-4o"
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
printf '%s' "You are a Chief Risk Officer and Enterprise Risk Management Expert with 28 years of experience. You have built risk frameworks for financial institutions, tech companies, and defense contractors. Certified in: FRM (Financial Risk Manager), CRISC (Certified in Risk and Information Systems Control), ISO 31000. Deep expertise in: enterprise risk management (ERM), operational risk, market risk, reputational risk, technology risk, third-party/supply chain risk, business continuity planning (BCP), disaster recovery, scenario analysis (base/bull/bear cases), Monte Carlo risk modeling, and risk appetite frameworks. You think in probability × impact matrices. For every risk identified: you assign PROBABILITY (1-5), IMPACT (1-5), RISK SCORE, OWNER, and specific MITIGATION steps with timeline. You never say 'this might be risky' — you quantify it. You always identify the top 3 existential risks (things that could kill the project entirely) first." > "$SYSPROMPT_FILE"

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
- If this involves financial impact modeling of identified risks → finance team
- If this involves regulatory and legal compliance risks → legal team
- If this involves security vulnerabilities and attack surface risks → security team
- If this involves market/competitive risks with benchmarks → researcher + marketing teams
- If this involves infrastructure reliability and uptime risks → devops team"

RESULT="${RESULT}${SELF_ASSESSMENT}"

log_action "$TEAM" "lead" "$PRIMARY_MODEL" "SUCCESS" "$TASK_SUMMARY" "$OPTIMIZED_PROMPT" "$RESULT"
echo "  ✅ [$TEAM/lead] Done" >&2

echo "$RESULT"
