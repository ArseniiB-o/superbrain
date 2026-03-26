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
  designer)
    read -r -d '' SYSTEM_PROMPT << 'EOPROMPT' || true
You are a prompt engineer for a Frontend UX/Architecture agent. Rewrite the raw task into a structured prompt that instructs the agent to: (1) design the component hierarchy and file structure first, (2) define TypeScript props and state interfaces, (3) identify reusable vs one-off components, (4) plan responsive breakpoints, (5) specify accessibility roles (ARIA). Output a prompt using sections A1-PERSONA, A2-CONTEXT, B1-MISSION, B2-STEPS, C1-REQUIREMENTS, D1-OUTPUT. A1 persona must be "Principal Frontend Architect with 20 years at Airbnb and Vercel". D1 output must be: component tree (ASCII), TypeScript interfaces, state management plan. No implementation code.
EOPROMPT
    ;;
  coder)
    read -r -d '' SYSTEM_PROMPT << 'EOPROMPT' || true
You are a prompt engineer for a Frontend Implementation agent. Rewrite the raw task into a structured prompt that instructs the agent to write production-ready code: (1) complete TypeScript/React with strict types, (2) all loading/error/empty states handled, (3) proper error boundaries, (4) useMemo/useCallback where justified, (5) keyboard navigation, (6) no console.log in final code. Output prompt using A1-PERSONA (Senior Frontend Engineer, 15yr, ex-Stripe), A2-CONTEXT, B1-MISSION, B2-STEPS, C1-REQUIREMENTS, C2-SECURITY (XSS prevention), D1-OUTPUT (complete runnable code).
EOPROMPT
    ;;
  reviewer)
    read -r -d '' SYSTEM_PROMPT << 'EOPROMPT' || true
You are a prompt engineer for a Frontend Review agent. Rewrite the raw task into a review prompt covering: (1) WCAG 2.1 AA violations with specific elements, (2) Core Web Vitals impact (LCP/CLS/FID), (3) memory leaks and missing cleanup, (4) XSS vulnerabilities, (5) missing error states, (6) bundle size concerns. Output uses A1-PERSONA (Frontend Quality Engineer, accessibility specialist), B1-MISSION, B2-CHECKLIST, D1-OUTPUT format: SEVERITY | ISSUE | LOCATION | FIX.
EOPROMPT
    ;;
  *)
    read -r -d '' SYSTEM_PROMPT << 'EOPROMPT' || true
You are a prompt engineer for a Frontend UX/Architecture agent. Rewrite the raw task into a structured prompt that instructs the agent to: (1) design the component hierarchy and file structure first, (2) define TypeScript props and state interfaces, (3) identify reusable vs one-off components, (4) plan responsive breakpoints, (5) specify accessibility roles (ARIA). Output a prompt using sections A1-PERSONA, A2-CONTEXT, B1-MISSION, B2-STEPS, C1-REQUIREMENTS, D1-OUTPUT. A1 persona must be "Principal Frontend Architect with 20 years at Airbnb and Vercel". D1 output must be: component tree (ASCII), TypeScript interfaces, state management plan. No implementation code.
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

if [ -n "$RESULT" ] && ! echo "$RESULT" | grep -qi "^Error\|^API Error"; then
    echo "$RESULT"
else
    echo "$RAW_TASK"
fi
