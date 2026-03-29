#!/usr/bin/env bash
# call_model.sh — Call any OpenRouter model directly by name
#
# Usage:
#   echo "prompt text"    | ./call_model.sh <model_name>
#   cat file.txt          | ./call_model.sh <model_name>
#   ./call_model.sh <model_name> "prompt text"   # no stdin
#
# Optional env:
#   SYSTEM_PROMPT="…"         — system-level instruction prepended to the conversation
#   OPENROUTER_API_KEY="…"    — overrides key read from .env
#
# Behaviour:
#   - Reads OPENROUTER_API_KEY from environment; if missing, tries .env in this
#     script's directory, then ~/.agents2/.env, then ~/.agents/.env
#   - Timeout: 60 s per attempt
#   - Retries: up to 2 times on HTTP 429 (rate limit), with 5 s back-off
#   - UTF-8 safe on Windows (reconfigures sys.stdout/stderr)
#   - Exits 0 on success (response on stdout), non-zero on all errors

set -euo pipefail

# Ensure UTF-8 for Python on Windows
export PYTHONUTF8=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Load API key ──────────────────────────────────────────────────────────────
# Priority: env var → script-dir .env → ~/.agents2/.env → ~/.agents/.env
_load_env() {
    local candidate
    for candidate in \
        "${SCRIPT_DIR}/.env" \
        "${HOME}/.agents2/.env" \
        "${HOME}/.agents/.env"
    do
        if [ -f "$candidate" ]; then
            # shellcheck disable=SC1090
            source "$candidate"
            break
        fi
    done
}

if [ -z "${OPENROUTER_API_KEY:-}" ]; then
    _load_env
fi

# ── Argument parsing ──────────────────────────────────────────────────────────
MODEL="${1:?Error: model name required. Usage: echo prompt | $0 <model_name>}"

# ── Build prompt ──────────────────────────────────────────────────────────────
PROMPT_FILE="$(mktemp)"
SYSTEM_FILE="$(mktemp)"
trap 'rm -f "$PROMPT_FILE" "$SYSTEM_FILE"' EXIT

if [ ! -t 0 ]; then
    # Stdin available
    if [ -n "${2:-}" ]; then
        # Prepend $2 then append stdin
        { printf '%s\n\n' "$2"; cat; } > "$PROMPT_FILE"
    else
        cat > "$PROMPT_FILE"
    fi
elif [ -n "${2:-}" ]; then
    # No stdin — use $2 directly
    printf '%s' "$2" > "$PROMPT_FILE"
else
    printf 'Error: prompt required — pass via stdin or as second argument\n' >&2
    printf '  echo "prompt" | %s %s\n' "$0" "$MODEL" >&2
    printf '  %s %s "prompt"\n' "$0" "$MODEL" >&2
    exit 1
fi

# Write system prompt to file (may be empty — Python handles that)
printf '%s' "${SYSTEM_PROMPT:-}" > "$SYSTEM_FILE"

# ── Export env vars for Python block ─────────────────────────────────────────
export _CM_MODEL="$MODEL"
export _CM_PROMPT_FILE="$PROMPT_FILE"
export _CM_SYSTEM_FILE="$SYSTEM_FILE"
export _CM_API_KEY="${OPENROUTER_API_KEY:-}"

# ── Python: call OpenRouter API ───────────────────────────────────────────────
python3 - << 'PYEOF'
import json, os, sys, time, socket
import urllib.request, urllib.error

# ── UTF-8 safety (Windows) ────────────────────────────────────────────────────
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

# ── Read env ──────────────────────────────────────────────────────────────────
model       = os.environ["_CM_MODEL"]
prompt_file = os.environ["_CM_PROMPT_FILE"]
system_file = os.environ["_CM_SYSTEM_FILE"]
api_key     = os.environ.get("_CM_API_KEY", "")

if not api_key:
    print(
        "Error: OPENROUTER_API_KEY is not set.\n"
        "  export OPENROUTER_API_KEY=your_key\n"
        "  Get a key at: https://openrouter.ai/keys",
        file=sys.stderr,
    )
    sys.exit(1)

# ── Read prompt & system prompt ───────────────────────────────────────────────
with open(prompt_file, encoding='utf-8', errors='replace') as f:
    prompt = f.read()

if not prompt.strip():
    print("Error: prompt is empty", file=sys.stderr)
    sys.exit(1)

system_prompt = ""
if os.path.exists(system_file):
    with open(system_file, encoding='utf-8', errors='replace') as f:
        system_prompt = f.read()

# ── Build request ─────────────────────────────────────────────────────────────
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

# ── Send with retry on 429 / 5xx ─────────────────────────────────────────────
MAX_RETRIES = 3
BASE_DELAY  = 2   # seconds for exponential backoff: 2^attempt
TIMEOUT     = 120 # seconds — long AI responses need headroom

for attempt in range(MAX_RETRIES + 1):
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            raw = resp.read().decode("utf-8", errors="replace")

        data = json.loads(raw)

        try:
            choice  = data["choices"][0]
            content = choice["message"]["content"]
        except (KeyError, IndexError, TypeError):
            print(
                f"Error: unexpected API response format:\n{json.dumps(data, indent=2)}",
                file=sys.stderr,
            )
            sys.exit(1)

        if not content or not content.strip():
            print("Error: model returned an empty response", file=sys.stderr)
            sys.exit(2)

        # Warn if response was truncated
        finish_reason = choice.get("finish_reason", "")
        if finish_reason == "length":
            print(
                "Warning: response truncated (finish_reason=length). "
                "Consider increasing max_tokens or splitting the task.",
                file=sys.stderr,
            )

        print(content, end="")
        sys.exit(0)

    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        try:
            err_msg = json.loads(body).get("error", {}).get("message", body)
        except Exception:
            err_msg = body

        # Non-retryable client errors
        if exc.code in (400, 401, 403, 404):
            print(f"API Error ({exc.code}): {err_msg}", file=sys.stderr)
            sys.exit(1)

        if exc.code == 429 and attempt < MAX_RETRIES:
            # Respect Retry-After header if present
            retry_after_str = exc.headers.get("Retry-After", "")
            try:
                retry_after = int(retry_after_str)
            except (ValueError, TypeError):
                retry_after = int(BASE_DELAY ** (attempt + 1))
            print(
                f"Warning: rate limited by OpenRouter (attempt {attempt + 1}/{MAX_RETRIES + 1}), "
                f"retrying in {retry_after}s…",
                file=sys.stderr,
            )
            time.sleep(retry_after)
            continue

        if exc.code >= 500 and attempt < MAX_RETRIES:
            delay = int(BASE_DELAY ** (attempt + 1))
            print(
                f"Warning: server error {exc.code} (attempt {attempt + 1}/{MAX_RETRIES + 1}), "
                f"retrying in {delay}s…",
                file=sys.stderr,
            )
            time.sleep(delay)
            continue

        print(f"API Error ({exc.code}): {err_msg}", file=sys.stderr)
        sys.exit(1)

    except (TimeoutError, socket.timeout, OSError) as exc:
        if attempt < MAX_RETRIES:
            delay = int(BASE_DELAY ** (attempt + 1))
            print(
                f"Warning: request timed out (attempt {attempt + 1}/{MAX_RETRIES + 1}), "
                f"retrying in {delay}s…",
                file=sys.stderr,
            )
            time.sleep(delay)
            continue
        print(f"Error: request timed out after {TIMEOUT}s", file=sys.stderr)
        sys.exit(1)

    except Exception as exc:
        print(f"Unexpected error: {exc}", file=sys.stderr)
        sys.exit(1)

# Should not reach here
print("Error: all retry attempts exhausted", file=sys.stderr)
sys.exit(1)
PYEOF
