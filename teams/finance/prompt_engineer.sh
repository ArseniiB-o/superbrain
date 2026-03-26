#!/usr/bin/env bash
# teams/finance/prompt_engineer.sh — Role-specific prompt optimizer
# Usage: echo "raw task" | ./prompt_engineer.sh <role>
# Roles: modeler | analyst | advisor

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$SCRIPT_DIR/../.."
CALL_MODEL="${AGENTS2_DIR}/call_model.sh"
ENV_FILE="${AGENTS2_DIR}/.env"
LOGS_DIR="${AGENTS2_DIR}/logs"

if [[ -f "$ENV_FILE" ]]; then
    set -a; source "$ENV_FILE"; set +a
fi

ROLE="${1:-modeler}"
RAW_TASK="$(cat)"
mkdir -p "$LOGS_DIR"

PE_TMPFILE=$(mktemp)
trap 'rm -f "$PE_TMPFILE"' EXIT

case "$ROLE" in
    modeler)
        cat > "$PE_TMPFILE" << 'HEREDOC'
You are a prompt engineer for a Financial Modeling agent. Ask the agent to build the financial model: revenue model (pricing x volume projections), cost structure (fixed and variable), unit economics (CAC/LTV/payback period/gross margin), burn rate and runway calculation, break-even analysis. All with explicit assumptions stated. Agent persona: Financial Modeling Specialist, 20yr, ex-Goldman Sachs.

Output ONLY the optimized prompt text. No preamble, no explanation, no meta-commentary.
HEREDOC
        ;;
    analyst)
        cat > "$PE_TMPFILE" << 'HEREDOC'
You are a prompt engineer for a Financial Analysis agent. Ask the agent to validate and stress-test the model: identify unrealistic assumptions, build 3 scenarios (bear/base/bull), identify key sensitivity drivers (which assumption has biggest impact on outcome?), compare metrics to industry benchmarks, flag red flags. Agent persona: CFO, 24yr, 3 startup exits.

Output ONLY the optimized prompt text. No preamble, no explanation, no meta-commentary.
HEREDOC
        ;;
    advisor)
        cat > "$PE_TMPFILE" << 'HEREDOC'
You are a prompt engineer for a Financial Advisor agent. Ask the agent to translate model to decisions: what does this mean for fundraising (how much to raise, at what valuation, when?), pricing (is pricing right?), hiring (when can we afford to hire?), runway (when is the point of no return?). Agent persona: Startup Financial Advisor, 20yr, 100+ companies advised.

Output ONLY the optimized prompt text. No preamble, no explanation, no meta-commentary.
HEREDOC
        ;;
    *)
        echo "$RAW_TASK"
        exit 0
        ;;
esac

SYSTEM_PROMPT="$(cat "$PE_TMPFILE")"

if [[ ! -x "$CALL_MODEL" ]]; then
    echo "$RAW_TASK"
    exit 0
fi

RESULT="$(printf '%s' "$RAW_TASK" | SYSTEM_PROMPT="$SYSTEM_PROMPT" "$CALL_MODEL" "openai/gpt-4o" 2>/dev/null)" || RESULT=""

if [[ -n "$RESULT" ]]; then
    echo "$RESULT"
else
    echo "$RAW_TASK"
fi
