#!/usr/bin/env bash
# teams/risk/prompt_engineer.sh — Role-specific prompt optimizer
# Usage: echo "raw task" | ./prompt_engineer.sh <role>
# Roles: identifier | assessor | mitigator

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CALL_MODEL="${AGENTS2_DIR}/call_model.sh"
ENV_FILE="${AGENTS2_DIR}/.env"
LOGS_DIR="${AGENTS2_DIR}/logs"

if [[ -f "$ENV_FILE" ]]; then
    set -a; source "$ENV_FILE"; set +a
fi

ROLE="${1:-identifier}"
RAW_TASK="$(cat)"
mkdir -p "$LOGS_DIR"

PE_TMPFILE=$(mktemp)
trap 'rm -f "$PE_TMPFILE"' EXIT

case "$ROLE" in
    identifier)
        cat > "$PE_TMPFILE" << 'HEREDOC'
You are a prompt engineer for a Risk Identification agent. Ask the agent to find ALL risks: brainstorm exhaustively across categories (strategic, operational, financial, legal/regulatory, technical, reputational, people/HR, market, external/macro). Do not filter — list everything, then rate top 10 by gut instinct. Agent persona: Chief Risk Officer, 28yr, enterprise risk management.

Output ONLY the optimized prompt text. No preamble, no explanation, no meta-commentary.
HEREDOC
        ;;
    assessor)
        cat > "$PE_TMPFILE" << 'HEREDOC'
You are a prompt engineer for a Risk Assessment agent. Ask the agent to score all identified risks: Probability (1-5), Impact (1-5), Risk Score (P times I), Time Horizon (immediate/short/medium/long term), Risk Velocity (how fast could it materialize?), Current Controls (what is already in place?). Identify top 3 existential risks (score >= 20 or existential by nature). Agent persona: Risk Assessment Specialist, FRM/CRISC certified, 20yr.

Output ONLY the optimized prompt text. No preamble, no explanation, no meta-commentary.
HEREDOC
        ;;
    mitigator)
        cat > "$PE_TMPFILE" << 'HEREDOC'
You are a prompt engineer for a Risk Mitigation agent. Ask the agent to develop mitigation strategies: for each HIGH+ risk, provide Prevention (reduce probability), Response (reduce impact if it happens), Early Warning Indicators (how to detect early), Owner (who is responsible), Timeline (when mitigation must be in place). Agent persona: Business Continuity and Risk Mitigation Expert, 18yr.

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
