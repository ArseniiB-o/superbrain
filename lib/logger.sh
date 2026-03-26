#!/usr/bin/env bash
# lib/logger.sh — Enhanced agent action logger v2
#
# Logs to two files per day:
#   logs/session_YYYYMMDD.log       — one-liner per call (machine-friendly)
#   logs/session_YYYYMMDD.full.log  — full prompts + responses (human-readable)
#
# Public API:
#   log_action <team> <role> <model> <status> <task_summary> [prompt] [response]
#   log_session_start
#   log_session_end
#
# Status values: SUCCESS | FAILED | SKIPPED | RETRY
#
# Color output goes to stderr only (terminal feedback).
# Log files contain no ANSI codes.

set -euo pipefail

# ── Paths ────────────────────────────────────────────────────────────────────
AGENTS2_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGS_DIR="${AGENTS2_DIR}/logs"
mkdir -p "$LOGS_DIR"

_DATE_TAG="$(date +%Y%m%d)"
LOG_FILE="${LOGS_DIR}/session_${_DATE_TAG}.log"
FULL_LOG_FILE="${LOGS_DIR}/session_${_DATE_TAG}.full.log"

# ── ANSI colors (stderr only) ─────────────────────────────────────────────────
_CLR_RESET="\033[0m"
_CLR_GREEN="\033[0;32m"
_CLR_RED="\033[0;31m"
_CLR_YELLOW="\033[0;33m"
_CLR_CYAN="\033[0;36m"
_CLR_GRAY="\033[0;90m"
_CLR_BOLD="\033[1m"

# ── Internal helpers ──────────────────────────────────────────────────────────

_ts() {
    date "+%Y-%m-%d %H:%M:%S"
}

_status_color() {
    local status="$1"
    case "$status" in
        SUCCESS) printf '%b' "${_CLR_GREEN}" ;;
        FAILED)  printf '%b' "${_CLR_RED}"   ;;
        RETRY)   printf '%b' "${_CLR_YELLOW}";;
        SKIPPED) printf '%b' "${_CLR_GRAY}"  ;;
        *)        printf '%b' "${_CLR_CYAN}"  ;;
    esac
}

_truncate() {
    # _truncate <max_chars> <text>
    local max="$1"
    local text="$2"
    if [ "${#text}" -le "$max" ]; then
        printf '%s' "$text"
    else
        printf '%s' "${text:0:$max}…"
    fi
}

# ── Public: log_action ────────────────────────────────────────────────────────
#
# log_action <team> <role> <model> <status> <task_summary> [prompt] [response]
#
# All args after $5 are optional.  Prompt and response may be multi-line strings.
log_action() {
    local team="${1:-unknown}"
    local role="${2:-unknown}"
    local model="${3:-unknown}"
    local status="${4:-UNKNOWN}"
    local summary="${5:-}"
    local prompt="${6:-}"
    local response="${7:-}"

    local ts
    ts="$(_ts)"

    # ── Previews for the one-liner log ───────────────────────────────────────
    local prompt_preview
    prompt_preview="$(_truncate 100 "$(printf '%s' "$prompt" | tr '\n' ' ')")"

    local response_preview
    response_preview="$(_truncate 300 "$(printf '%s' "$response" | tr '\n' ' ')")"

    # ── One-liner → .log ─────────────────────────────────────────────────────
    # Format: [ts] [team:role] [model] [STATUS] summary | prompt_preview | response_preview
    {
        printf '[%s] [%s:%s] [%s] [%s] %s | %s | %s\n' \
            "$ts" "$team" "$role" "$model" "$status" \
            "$summary" "$prompt_preview" "$response_preview"
    } >> "$LOG_FILE"

    # ── Full entry → .full.log ────────────────────────────────────────────────
    local prompt_500
    prompt_500="$(_truncate 500 "$prompt")"

    local response_500
    response_500="$(_truncate 500 "$response")"

    {
        printf '════════════════════════════════════════\n'
        printf '[%s] %s:%s [%s] %s\n' "$ts" "$team" "$role" "$model" "$status"
        printf 'TASK: %s\n' "$summary"
        if [ -n "$prompt" ]; then
            printf 'PROMPT (first 500 chars):\n%s\n' "$prompt_500"
        fi
        if [ -n "$response" ]; then
            printf 'RESPONSE (first 500 chars):\n%s\n' "$response_500"
        fi
        printf '════════════════════════════════════════\n\n'
    } >> "$FULL_LOG_FILE"

    # ── Colored terminal feedback → stderr ────────────────────────────────────
    local color
    color="$(_status_color "$status")"

    printf '%b[%s] %b%s:%s%b [%s] %b%s%b — %s\n' \
        "${_CLR_GRAY}" "$ts" \
        "${_CLR_CYAN}" "$team" "$role" "${_CLR_RESET}" \
        "$model" \
        "$color" "$status" "${_CLR_RESET}" \
        "$summary" \
        >&2
}

# ── Public: log_session_start ─────────────────────────────────────────────────
log_session_start() {
    local ts
    ts="$(_ts)"

    local banner
    banner="══════════════ SESSION START [$ts] ══════════════"

    printf '%s\n' "$banner" >> "$LOG_FILE"
    printf '%s\n\n' "$banner" >> "$FULL_LOG_FILE"

    printf '%b%s%b\n' "${_CLR_BOLD}${_CLR_CYAN}" "$banner" "${_CLR_RESET}" >&2
}

# ── Public: log_session_end ───────────────────────────────────────────────────
log_session_end() {
    local ts
    ts="$(_ts)"

    local banner
    banner="══════════════ SESSION END   [$ts] ══════════════"

    printf '%s\n\n' "$banner" >> "$LOG_FILE"
    printf '%s\n\n' "$banner" >> "$FULL_LOG_FILE"

    printf '%b%s%b\n' "${_CLR_BOLD}${_CLR_CYAN}" "$banner" "${_CLR_RESET}" >&2
}
