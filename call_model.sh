#!/usr/bin/env bash
# call_model.sh — Call AI model (OpenRouter or Claude Max subscription)
#
# Usage:
#   echo "prompt"    | ./call_model.sh <model_name>
#   cat file.txt     | ./call_model.sh <model_name>
#   ./call_model.sh <model_name> "prompt text"
#
# Optional env:
#   SYSTEM_PROMPT="…"       — system-level instruction
#   OPENROUTER_API_KEY="…"  — for openrouter mode
#
# Mode (read from .mode file):
#   openrouter (default) — calls OpenRouter API with specified model
#   claude               — ALL calls use claude-sonnet-4-6 via Max subscription
#                          (claude -p CLI, no API key needed)

set -euo pipefail

export PYTHONUTF8=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE_FILE="${SCRIPT_DIR}/.mode"

# ── Load API key (for openrouter mode) ───────────────────────────────────────
_load_env() {
    local candidate
    for candidate in \
        "${SCRIPT_DIR}/.env" \
        "${HOME}/.agents2/.env" \
        "${HOME}/.agents/.env"
    do
        if [ -f "$candidate" ]; then
            set -a; source "$candidate"; set +a
            break
        fi
    done
}

if [ -z "${OPENROUTER_API_KEY:-}" ]; then
    _load_env
fi

# ── Read active mode ──────────────────────────────────────────────────────────
ACTIVE_MODE="claude"
if [[ -f "$MODE_FILE" ]]; then
    ACTIVE_MODE=$(cat "$MODE_FILE" | tr -d '[:space:]')
fi

# ── Argument parsing ──────────────────────────────────────────────────────────
_REQUESTED_MODEL="${1:?Error: model name required. Usage: echo prompt | $0 <model_name>}"

# In claude mode: ignore requested model, always use sonnet subscription
if [[ "$ACTIVE_MODE" == "claude" ]]; then
    MODEL="sonnet"  # claude CLI alias → claude-sonnet-4-6
else
    MODEL="$_REQUESTED_MODEL"
fi

# ── Build prompt files ────────────────────────────────────────────────────────
PROMPT_FILE="$(mktemp)"
SYSTEM_FILE="$(mktemp)"
trap 'rm -f "$PROMPT_FILE" "$SYSTEM_FILE"' EXIT

if [ ! -t 0 ]; then
    if [ -n "${2:-}" ]; then
        { printf '%s\n\n' "$2"; cat; } > "$PROMPT_FILE"
    else
        cat > "$PROMPT_FILE"
    fi
elif [ -n "${2:-}" ]; then
    printf '%s' "$2" > "$PROMPT_FILE"
else
    printf 'Error: prompt required — pass via stdin or as second argument\n' >&2
    exit 1
fi

printf '%s' "${SYSTEM_PROMPT:-}" > "$SYSTEM_FILE"

PROMPT_CONTENT=$(cat "$PROMPT_FILE")
SYSTEM_CONTENT=$(cat "$SYSTEM_FILE")

# ════════════════════════════════════════════════════════════════
# CLAUDE MODE — use claude -p with Max subscription (no API key)
# ════════════════════════════════════════════════════════════════
if [[ "$ACTIVE_MODE" == "claude" ]]; then

    # ── Find claude binary ────────────────────────────────────────────────────
    CLAUDE_BIN=""

    # 1. Claude Code extension path (always set inside Claude Code sessions)
    if [[ -n "${CLAUDE_CODE_EXECPATH:-}" && -x "${CLAUDE_CODE_EXECPATH}" ]]; then
        CLAUDE_BIN="$CLAUDE_CODE_EXECPATH"

    # 2. npm global claude (in PATH)
    elif command -v claude &>/dev/null; then
        CLAUDE_BIN="$(command -v claude)"

    # 3. Common Windows paths
    elif [[ -x "${APPDATA}/npm/claude.cmd" ]]; then
        CLAUDE_BIN="${APPDATA}/npm/claude.cmd"

    # 4. Fallback: OpenRouter with Claude model
    else
        echo "Warning: claude binary not found. Falling back to OpenRouter claude model." >&2
        ACTIVE_MODE="openrouter"
        MODEL="anthropic/claude-sonnet-4-6"
    fi

    if [[ "$ACTIVE_MODE" == "claude" ]]; then
        # ── Build claude -p command ───────────────────────────────────────────
        CMD_ARGS=(
            "$CLAUDE_BIN"
            -p
            --model "sonnet"
            --output-format text
            --no-session-persistence
            --tools ""
            --dangerously-skip-permissions
        )

        # System prompt: pass via --system-prompt if non-empty
        if [[ -n "$SYSTEM_CONTENT" ]]; then
            CMD_ARGS+=(--system-prompt "$SYSTEM_CONTENT")
        fi

        # Unset CLAUDECODE to allow nested claude -p calls from within Claude Code sessions
        # (Claude Code blocks nested sessions unless CLAUDECODE is unset)
        unset CLAUDECODE

        # Run via printf to avoid shell injection on prompt content
        RESPONSE=$(printf '%s' "$PROMPT_CONTENT" | "${CMD_ARGS[@]}" 2>/dev/null) || {
            echo "Error: claude -p call failed" >&2
            exit 1
        }

        if [[ -z "$RESPONSE" ]]; then
            echo "Error: claude -p returned empty response" >&2
            exit 1
        fi

        printf '%s' "$RESPONSE"
        exit 0
    fi
fi

# ════════════════════════════════════════════════════════════════
# OPENROUTER MODE — call OpenRouter API
# ════════════════════════════════════════════════════════════════
if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
    echo "Error: OPENROUTER_API_KEY is not set." >&2
    echo "  export OPENROUTER_API_KEY=your_key" >&2
    echo "  Get a key at: https://openrouter.ai/keys" >&2
    exit 1
fi

export _CM_MODEL="$MODEL"
export _CM_PROMPT_FILE="$PROMPT_FILE"
export _CM_SYSTEM_FILE="$SYSTEM_FILE"
export _CM_API_KEY="${OPENROUTER_API_KEY:-}"

python3 - << 'PYEOF'
import json, os, sys, time, socket
import urllib.request, urllib.error

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

model       = os.environ["_CM_MODEL"]
prompt_file = os.environ["_CM_PROMPT_FILE"]
system_file = os.environ["_CM_SYSTEM_FILE"]
api_key     = os.environ.get("_CM_API_KEY", "")

with open(prompt_file, encoding='utf-8', errors='replace') as f:
    prompt = f.read()

if not prompt.strip():
    print("Error: prompt is empty", file=sys.stderr)
    sys.exit(1)

system_prompt = ""
if os.path.exists(system_file):
    with open(system_file, encoding='utf-8', errors='replace') as f:
        system_prompt = f.read()

messages = []
if system_prompt.strip():
    messages.append({"role": "system", "content": system_prompt})
messages.append({"role": "user", "content": prompt})

payload = json.dumps({
    "model": model,
    "messages": messages,
    "max_tokens": 8192,
}).encode("utf-8")

req = urllib.request.Request(
    "https://openrouter.ai/api/v1/chat/completions",
    data=payload,
    headers={
        "Content-Type":  "application/json",
        "Authorization": f"Bearer {api_key}",
        "HTTP-Referer":  "https://github.com/agents2",
        "X-Title":       "Agents2 Orchestration",
    },
    method="POST",
)

MAX_RETRIES = 3
BASE_DELAY  = 2
TIMEOUT     = 120

for attempt in range(MAX_RETRIES + 1):
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            raw = resp.read().decode("utf-8", errors="replace")

        data = json.loads(raw)

        try:
            choice  = data["choices"][0]
            content = choice["message"]["content"]
        except (KeyError, IndexError, TypeError):
            print(f"Error: unexpected API response format:\n{json.dumps(data, indent=2)}", file=sys.stderr)
            sys.exit(1)

        if not content or not content.strip():
            print("Error: model returned an empty response", file=sys.stderr)
            sys.exit(2)

        finish_reason = choice.get("finish_reason", "")
        if finish_reason == "length":
            print("Warning: response truncated (finish_reason=length).", file=sys.stderr)

        print(content, end="")
        sys.exit(0)

    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        try:
            err_msg = json.loads(body).get("error", {}).get("message", body)
        except Exception:
            err_msg = body

        if exc.code in (400, 401, 403, 404):
            print(f"API Error ({exc.code}): {err_msg}", file=sys.stderr)
            sys.exit(1)

        if exc.code == 429 and attempt < MAX_RETRIES:
            retry_after_str = exc.headers.get("Retry-After", "")
            try:
                retry_after = int(retry_after_str)
            except (ValueError, TypeError):
                retry_after = int(BASE_DELAY ** (attempt + 1))
            print(f"Warning: rate limited (attempt {attempt+1}/{MAX_RETRIES+1}), retrying in {retry_after}s…", file=sys.stderr)
            time.sleep(retry_after)
            continue

        if exc.code >= 500 and attempt < MAX_RETRIES:
            delay = int(BASE_DELAY ** (attempt + 1))
            print(f"Warning: server error {exc.code} (attempt {attempt+1}/{MAX_RETRIES+1}), retrying in {delay}s…", file=sys.stderr)
            time.sleep(delay)
            continue

        print(f"API Error ({exc.code}): {err_msg}", file=sys.stderr)
        sys.exit(1)

    except (TimeoutError, socket.timeout, OSError) as exc:
        if attempt < MAX_RETRIES:
            delay = int(BASE_DELAY ** (attempt + 1))
            print(f"Warning: timeout (attempt {attempt+1}/{MAX_RETRIES+1}), retrying in {delay}s…", file=sys.stderr)
            time.sleep(delay)
            continue
        print(f"Error: request timed out after {TIMEOUT}s", file=sys.stderr)
        sys.exit(1)

    except Exception as exc:
        print(f"Unexpected error: {exc}", file=sys.stderr)
        sys.exit(1)

print("Error: all retry attempts exhausted", file=sys.stderr)
sys.exit(1)
PYEOF
