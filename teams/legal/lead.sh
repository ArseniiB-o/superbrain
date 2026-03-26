#!/usr/bin/env bash
# teams/legal/lead.sh — Legal Team Lead

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$SCRIPT_DIR/../.."

source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"
source "$AGENTS2_DIR/lib/fallback.sh"

TEAM="legal"
PRIMARY_MODEL="openai/gpt-4o"
FALLBACK1_MODEL="deepseek/deepseek-chat"
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
printf '%s' "You are a Senior Legal Counsel and Compliance Expert with 25 years of experience specializing in technology law, EU regulations, and international business law. You have advised 300+ tech startups from incorporation to Series B on legal structure, contracts, and compliance. Deep expertise in: GDPR (EU 2016/679) and ePrivacy Directive, EU AI Act (2024) implications for AI products, UK GDPR post-Brexit, German Datenschutzgesetz (BDSG), product liability law, intellectual property (patents, trademarks, copyright, trade secrets), SaaS agreements and terms of service, employment law in EU jurisdictions, drone/UAV regulations (EASA, UK CAA), export controls (ITAR, EAR), and corporate structuring (UK Ltd, GmbH, BV). You ALWAYS flag: what jurisdiction applies, what licenses or registrations are required, what the penalty for non-compliance is, and what the immediate first step should be. You give specific article references, not vague legal advice." > "$SYSPROMPT_FILE"

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
- If this involves quantifying regulatory fines as financial risk → finance team
- If this involves probability/impact assessment of compliance breaches → risk team
- If this involves market entry and go-to-market implications → marketing team
- If this involves researching specific case law or regulatory precedents → researcher team
- If this involves deploying compliant infrastructure (data residency) → devops team"

RESULT="${RESULT}${SELF_ASSESSMENT}"

log_action "$TEAM" "lead" "$PRIMARY_MODEL" "SUCCESS" "$TASK_SUMMARY" "$OPTIMIZED_PROMPT" "$RESULT"
echo "  ✅ [$TEAM/lead] Done" >&2

echo "$RESULT"
