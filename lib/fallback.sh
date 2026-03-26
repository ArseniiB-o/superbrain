#!/usr/bin/env bash
# lib/fallback.sh — Model fallback chain executor
#
# Tries a list of models in order and returns the output of the first one that
# succeeds.  Designed to make teams resilient to individual model outages or
# rate limits.
#
# Usage:
#   run_with_fallback <prompt_file> <system_prompt_file> <model1> [model2] [model3…]
#
# Arguments:
#   prompt_file        — path to a file containing the user prompt
#   system_prompt_file — path to a file containing the system prompt (may be empty)
#   model1 …           — one or more OpenRouter model identifiers
#
# Environment (optional):
#   FALLBACK_VERBOSE=1 — print per-attempt status to stderr
#
# Exit codes:
#   0 — at least one model succeeded; output on stdout
#   1 — all models failed; last error message on stderr
#
# Internals:
#   - Delegates each attempt to call_model.sh
#   - Logs which model succeeded and how many attempts were made (via logger.sh)

set -euo pipefail

AGENTS2_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CALL_MODEL="${AGENTS2_DIR}/call_model.sh"
LIB_DIR="${AGENTS2_DIR}/lib"

# Source logger if available (non-fatal if missing)
if [ -f "${LIB_DIR}/logger.sh" ]; then
    # shellcheck source=lib/logger.sh
    source "${LIB_DIR}/logger.sh"
fi

FALLBACK_VERBOSE="${FALLBACK_VERBOSE:-0}"

# ── Internal helpers ──────────────────────────────────────────────────────────

_fb_log() {
    if [ "$FALLBACK_VERBOSE" = "1" ]; then
        printf '[fallback] %s\n' "$*" >&2
    fi
}

_fb_action() {
    # Emit a log_action entry if logger.sh was sourced
    if command -v log_action &>/dev/null; then
        log_action "fallback" "executor" "$1" "$2" "$3" "" ""
    fi
}

# ── Public: run_with_fallback ─────────────────────────────────────────────────
run_with_fallback() {
    local prompt_file="${1:?run_with_fallback: <prompt_file> required}"
    local system_file="${2:?run_with_fallback: <system_prompt_file> required}"
    shift 2

    if [ "$#" -eq 0 ]; then
        printf 'run_with_fallback: at least one model name required\n' >&2
        return 1
    fi

    if [ ! -f "$prompt_file" ]; then
        printf 'run_with_fallback: prompt file not found: %s\n' "$prompt_file" >&2
        return 1
    fi

    if [ ! -x "$CALL_MODEL" ]; then
        printf 'run_with_fallback: call_model.sh not found or not executable: %s\n' \
            "$CALL_MODEL" >&2
        return 1
    fi

    local models=("$@")
    local total="${#models[@]}"
    local attempt=0
    local last_error=""
    local output
    local model

    for model in "${models[@]}"; do
        attempt=$(( attempt + 1 ))
        _fb_log "attempt ${attempt}/${total} — trying model: ${model}"

        # Export system prompt so call_model.sh picks it up
        local sys_content=""
        if [ -f "$system_file" ] && [ -s "$system_file" ]; then
            sys_content="$(cat "$system_file")"
        fi

        if output="$(SYSTEM_PROMPT="$sys_content" \
                     "$CALL_MODEL" "$model" < "$prompt_file" 2>/tmp/fallback_stderr_$$)"; then

            if [ -n "$output" ]; then
                _fb_log "success with model: ${model} (attempt ${attempt}/${total})"
                _fb_action "$model" "SUCCESS" \
                    "Succeeded on attempt ${attempt}/${total} using model ${model}"

                # Surface which model was actually used
                printf '%s' "$output"

                # Export for callers that want to know which model won
                export FALLBACK_USED_MODEL="$model"
                export FALLBACK_ATTEMPTS="$attempt"

                rm -f "/tmp/fallback_stderr_$$"
                return 0
            else
                last_error="Model ${model} returned empty output"
                _fb_log "empty response from ${model}, trying next"
            fi
        else
            last_error="$(cat /tmp/fallback_stderr_$$ 2>/dev/null || true)"
            [ -z "$last_error" ] && last_error="Model ${model} exited non-zero"
            _fb_log "failed: ${last_error}"
        fi

        rm -f "/tmp/fallback_stderr_$$"
    done

    # All models failed
    printf '[fallback] All %d model(s) failed. Last error: %s\n' \
        "$total" "$last_error" >&2

    _fb_action "none" "FAILED" \
        "All ${total} model(s) exhausted. Last error: ${last_error}"

    export FALLBACK_USED_MODEL=""
    export FALLBACK_ATTEMPTS="$attempt"

    return 1
}

# ── Allow direct invocation ───────────────────────────────────────────────────
# If this script is executed directly (not sourced), call run_with_fallback
# with all provided arguments.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_with_fallback "$@"
fi
