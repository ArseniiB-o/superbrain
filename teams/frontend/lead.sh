#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"

TEAM="frontend"
ROLE1_NAME="designer"
ROLE2_NAME="coder"
ROLE3_NAME="reviewer"
AGENT1_MODEL="openai/gpt-4o-mini"
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

AGENT1_SYSPROMPT='You are a Principal Frontend Architect with 20 years of experience at Airbnb, Vercel, and Stripe. Your ONLY job in this task: produce the architecture and design spec. Output: (1) component hierarchy as ASCII tree, (2) TypeScript interface definitions for all props and state, (3) state management recommendation with justification, (4) reusable component list, (5) responsive strategy, (6) accessibility plan. Do NOT write implementation code.'

AGENT2_SYSPROMPT='You are a Senior Frontend Engineer with 15 years of experience. Write complete, production-ready TypeScript/React code. Requirements: strict TypeScript types (no any), all states handled (loading/error/empty/success), proper error boundaries, accessible (aria-label, role, tabIndex where needed), no TODOs or placeholders — complete code only.'

AGENT3_SYSPROMPT='You are a Frontend Quality and Security Auditor. Review the frontend task/code and find: WCAG 2.1 AA violations, Core Web Vitals regressions, XSS vulnerabilities, memory leaks, missing error handling. Format each finding as: [SEVERITY: CRITICAL/HIGH/MEDIUM/LOW] Issue | Location | Fix. Be specific — "line X does Y" not "might have issues".'

SYNTH_SYSPROMPT='You are the Frontend Team Lead. You received outputs from 3 specialists: Designer (architecture), Coder (implementation), Reviewer (quality audit). Combine into ONE complete deliverable: (1) Architecture overview from Designer, (2) Complete implementation code from Coder with Reviewer fixes applied, (3) Brief quality summary. If Reviewer found CRITICAL issues, fix them in the code.'

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
Specialists used: Designer(gpt-4o-mini) + Coder(gpt-4o-mini) + Reviewer(gemini-flash)
Additional teams that could add value:
- backend: if API integration or data fetching logic is needed
- security: for auth flows, CSRF protection, secure cookie handling
- mobile: if PWA or React Native adaptation required
- qa: for component unit tests and E2E test scenarios"

echo "  ✅ [$TEAM] Done" >&2
echo "$RESULT"
