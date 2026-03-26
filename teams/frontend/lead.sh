#!/usr/bin/env bash
# teams/frontend/lead.sh — Frontend Team Lead
# Orchestrates the frontend team: optimizes prompt → tries models → updates memory → returns result

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

TEAM="frontend"
PRIMARY_MODEL="openai/gpt-4o-mini"
FALLBACK1_MODEL="google/gemini-2.0-flash-001"
FALLBACK2_MODEL="deepseek/deepseek-chat"

# ── System prompt ──────────────────────────────────────────────────────────────
TEAM_SYSTEM_PROMPT="You are a Principal Frontend Engineer with 22 years of experience building world-class web applications at companies like Airbnb, Stripe, and Vercel. You are a deep expert in React (hooks, performance, architecture), Vue 3, TypeScript, CSS architecture (BEM, CSS Modules, Tailwind), web accessibility (WCAG 2.1), Core Web Vitals optimization, and modern bundling (Vite, webpack). You write pixel-perfect, performant, accessible code. You think in component systems. You never ship code with N+1 render issues, memory leaks, or missing error boundaries. You treat every UI interaction as a UX problem first."

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
