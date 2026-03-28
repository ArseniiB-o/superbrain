#!/usr/bin/env bash
# lib/team_runner.sh — Shared execution engine for all team lead scripts
#
# This file is SOURCED (not executed) by each team's lead.sh.
# The calling script must set these variables before sourcing:
#
#   Required:
#     TEAM              — team name (e.g. "backend", "security")
#     ROLE1_NAME        — name of specialist 1 (e.g. "architect")
#     ROLE2_NAME        — name of specialist 2 (e.g. "coder")
#     ROLE3_NAME        — name of specialist 3 (e.g. "reviewer")
#     AGENT1_SYSPROMPT  — system prompt for specialist 1
#     AGENT2_SYSPROMPT  — system prompt for specialist 2
#     AGENT3_SYSPROMPT  — system prompt for specialist 3
#     SYNTH_SYSPROMPT   — system prompt for the gpt-4o synthesizer
#     SELF_ASSESSMENT   — text appended after "## [TEAM Team] Self-Assessment"
#
#   Optional (override config.json):
#     AGENT1_MODEL      — model for specialist 1
#     AGENT2_MODEL      — model for specialist 2
#     AGENT3_MODEL      — model for specialist 3
#
#   Pre-set by the calling lead.sh:
#     SCRIPT_DIR        — directory of the calling lead.sh
#     AGENTS2_DIR       — root of .agents2
#
# Environment:
#     DISPATCH_NO_PE=1  — skip prompt engineering phase (--no-pe flag)
#
# The caller must have already sourced lib/logger.sh and lib/memory.sh.

set -euo pipefail

# Ensure UTF-8 for Python on Windows
export PYTHONUTF8=1

# ── Validate required variables ──────────────────────────────────────────────

_tr_require_var() {
    local name="$1"
    if [ -z "${!name:-}" ]; then
        printf 'team_runner.sh: required variable %s is not set\n' "$name" >&2
        exit 1
    fi
}

for _tr_var in TEAM ROLE1_NAME ROLE2_NAME ROLE3_NAME \
               AGENT1_SYSPROMPT AGENT2_SYSPROMPT AGENT3_SYSPROMPT \
               SYNTH_SYSPROMPT SELF_ASSESSMENT SCRIPT_DIR AGENTS2_DIR; do
    _tr_require_var "$_tr_var"
done

# ── Resolve models: lead.sh override > config.json > hardcoded fallback ──────

_tr_read_config_model() {
    # _tr_read_config_model <team> <slot>
    # slot is one of: primary, fallback1, fallback2
    local team="$1"
    local slot="$2"
    local config_file="${AGENTS2_DIR}/config.json"

    if [ ! -f "$config_file" ]; then
        return 1
    fi

    python3 -c "
import json, sys
try:
    with open('${config_file}', encoding='utf-8') as f:
        cfg = json.load(f)
    model = cfg['teams']['${team}']['models']['${slot}']
    print(model, end='')
except (KeyError, FileNotFoundError, json.JSONDecodeError):
    sys.exit(1)
" 2>/dev/null
}

# Only read from config.json if the lead.sh did not already set the variable
if [ -z "${AGENT1_MODEL:-}" ]; then
    AGENT1_MODEL="$(_tr_read_config_model "$TEAM" "primary")" \
        || AGENT1_MODEL="deepseek/deepseek-chat"
fi
if [ -z "${AGENT2_MODEL:-}" ]; then
    AGENT2_MODEL="$(_tr_read_config_model "$TEAM" "fallback1")" \
        || AGENT2_MODEL="openai/gpt-4o-mini"
fi
if [ -z "${AGENT3_MODEL:-}" ]; then
    AGENT3_MODEL="$(_tr_read_config_model "$TEAM" "fallback2")" \
        || AGENT3_MODEL="google/gemini-2.0-flash-001"
fi

# ── Temp files with guaranteed cleanup ───────────────────────────────────────

_TR_TMPFILE="$(mktemp)"
_TR_WORK_DIR="$(mktemp -d)"

_tr_cleanup() {
    rm -f "$_TR_TMPFILE"
    rm -rf "$_TR_WORK_DIR"
}
trap '_tr_cleanup' EXIT INT TERM

# ── Phase 0: Read task from stdin/arg ────────────────────────────────────────

if [ ! -t 0 ]; then
    # stdin available
    if [ -n "${1:-}" ]; then
        { printf '%s\n\n' "$1"; cat; } > "$_TR_TMPFILE"
    else
        cat > "$_TR_TMPFILE"
    fi
elif [ -n "${1:-}" ]; then
    printf '%s' "$1" > "$_TR_TMPFILE"
else
    printf 'Error: provide task via argument or stdin\n' >&2
    exit 1
fi

RAW_TASK="$(cat "$_TR_TMPFILE")"
TASK_SUMMARY="${RAW_TASK:0:120}"

log_action "$TEAM" "lead" "3-parallel" "RUNNING" "$TASK_SUMMARY" "$RAW_TASK"
printf '  [%s] Starting: %s...\n' "$TEAM" "${TASK_SUMMARY:0:60}" >&2

# ── Phase 1: Prompt Engineering (3 PE calls in parallel) ─────────────────────

if [ "${DISPATCH_NO_PE:-0}" = "1" ]; then
    # Skip PE — use raw task for all three specialists
    printf '  [%s] Skipping PE (--no-pe)\n' "$TEAM" >&2
    printf '%s' "$RAW_TASK" > "$_TR_WORK_DIR/p1.txt"
    printf '%s' "$RAW_TASK" > "$_TR_WORK_DIR/p2.txt"
    printf '%s' "$RAW_TASK" > "$_TR_WORK_DIR/p3.txt"
else
    printf '  [%s] PE optimizing for %s + %s + %s...\n' \
        "$TEAM" "$ROLE1_NAME" "$ROLE2_NAME" "$ROLE3_NAME" >&2

    _tr_pe_script="${SCRIPT_DIR}/prompt_engineer.sh"

    {
        printf '%s' "$RAW_TASK" \
            | bash "$_tr_pe_script" "$ROLE1_NAME" > "$_TR_WORK_DIR/p1.txt" 2>/dev/null \
            || cp "$_TR_TMPFILE" "$_TR_WORK_DIR/p1.txt"
        [ -s "$_TR_WORK_DIR/p1.txt" ] || cp "$_TR_TMPFILE" "$_TR_WORK_DIR/p1.txt"
    } &
    {
        printf '%s' "$RAW_TASK" \
            | bash "$_tr_pe_script" "$ROLE2_NAME" > "$_TR_WORK_DIR/p2.txt" 2>/dev/null \
            || cp "$_TR_TMPFILE" "$_TR_WORK_DIR/p2.txt"
        [ -s "$_TR_WORK_DIR/p2.txt" ] || cp "$_TR_TMPFILE" "$_TR_WORK_DIR/p2.txt"
    } &
    {
        printf '%s' "$RAW_TASK" \
            | bash "$_tr_pe_script" "$ROLE3_NAME" > "$_TR_WORK_DIR/p3.txt" 2>/dev/null \
            || cp "$_TR_TMPFILE" "$_TR_WORK_DIR/p3.txt"
        [ -s "$_TR_WORK_DIR/p3.txt" ] || cp "$_TR_TMPFILE" "$_TR_WORK_DIR/p3.txt"
    } &
    wait

    printf '  [%s] Prompts ready\n' "$TEAM" >&2
fi

# ── Phase 2: 3 specialist agents in parallel ─────────────────────────────────

printf '  [%s] %s(%s) + %s(%s) + %s(%s)...\n' \
    "$TEAM" \
    "$ROLE1_NAME" "$AGENT1_MODEL" \
    "$ROLE2_NAME" "$AGENT2_MODEL" \
    "$ROLE3_NAME" "$AGENT3_MODEL" >&2

{
    SYSTEM_PROMPT="$AGENT1_SYSPROMPT" \
        "$AGENTS2_DIR/call_model.sh" "$AGENT1_MODEL" < "$_TR_WORK_DIR/p1.txt" \
        > "$_TR_WORK_DIR/r1.txt" 2>/dev/null \
        || printf '[%s/%s failed]\n' "$TEAM" "$ROLE1_NAME" > "$_TR_WORK_DIR/r1.txt"
} &
{
    SYSTEM_PROMPT="$AGENT2_SYSPROMPT" \
        "$AGENTS2_DIR/call_model.sh" "$AGENT2_MODEL" < "$_TR_WORK_DIR/p2.txt" \
        > "$_TR_WORK_DIR/r2.txt" 2>/dev/null \
        || printf '[%s/%s failed]\n' "$TEAM" "$ROLE2_NAME" > "$_TR_WORK_DIR/r2.txt"
} &
{
    SYSTEM_PROMPT="$AGENT3_SYSPROMPT" \
        "$AGENTS2_DIR/call_model.sh" "$AGENT3_MODEL" < "$_TR_WORK_DIR/p3.txt" \
        > "$_TR_WORK_DIR/r3.txt" 2>/dev/null \
        || printf '[%s/%s failed]\n' "$TEAM" "$ROLE3_NAME" > "$_TR_WORK_DIR/r3.txt"
} &
wait

printf '  [%s] All 3 done\n' "$TEAM" >&2

# ── Phase 3: Synthesis with gpt-4o ──────────────────────────────────────────

COMBINED="## [$ROLE1_NAME -- $AGENT1_MODEL]
$(cat "$_TR_WORK_DIR/r1.txt" 2>/dev/null || printf '[%s failed to produce output]' "$ROLE1_NAME")

## [$ROLE2_NAME -- $AGENT2_MODEL]
$(cat "$_TR_WORK_DIR/r2.txt" 2>/dev/null || printf '[%s failed to produce output]' "$ROLE2_NAME")

## [$ROLE3_NAME -- $AGENT3_MODEL]
$(cat "$_TR_WORK_DIR/r3.txt" 2>/dev/null || printf '[%s failed to produce output]' "$ROLE3_NAME")"

printf '  [%s] Synthesizing...\n' "$TEAM" >&2

RESULT="$(printf '%s' "$COMBINED" | \
    SYSTEM_PROMPT="$SYNTH_SYSPROMPT" \
    "$AGENTS2_DIR/call_model.sh" "openai/gpt-4o" 2>/dev/null)" \
    || RESULT="$COMBINED"

[ -z "$RESULT" ] && RESULT="$COMBINED"

# ── Phase 4: Memory update ───────────────────────────────────────────────────

memory_append "$TEAM" "$(date '+%Y-%m-%d'): ${TASK_SUMMARY:0:80}" || true
log_action "$TEAM" "lead" "3-parallel" "SUCCESS" "$TASK_SUMMARY" "$RAW_TASK" "$RESULT"

# ── Phase 5: Append self-assessment ──────────────────────────────────────────

RESULT="${RESULT}
---
## [$TEAM Team] Self-Assessment
${SELF_ASSESSMENT}"

printf '  [%s] Done\n' "$TEAM" >&2
printf '%s\n' "$RESULT"
