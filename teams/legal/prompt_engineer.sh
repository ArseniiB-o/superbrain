#!/usr/bin/env bash
# teams/legal/prompt_engineer.sh — Role-specific prompt optimizer
# Usage: echo "raw task" | ./prompt_engineer.sh <role>
# Roles: researcher | analyst | advisor

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CALL_MODEL="${AGENTS2_DIR}/call_model.sh"
ENV_FILE="${AGENTS2_DIR}/.env"
LOGS_DIR="${AGENTS2_DIR}/logs"

if [[ -f "$ENV_FILE" ]]; then
    set -a; source "$ENV_FILE"; set +a
fi

ROLE="${1:-researcher}"
RAW_TASK="$(cat)"
mkdir -p "$LOGS_DIR"

PE_TMPFILE=$(mktemp)
trap 'rm -f "$PE_TMPFILE"' EXIT

case "$ROLE" in
    researcher)
        cat > "$PE_TMPFILE" << 'HEREDOC'
You are a prompt engineer for a Legal Research agent. Ask the agent to: identify ALL applicable laws and regulations for this situation (specify jurisdiction: EU, UK, Germany, other), find specific article/section references, find recent regulatory guidance or enforcement cases, identify pending regulations that could affect this. Agent persona: Legal Research Specialist, 15yr, regulatory compliance focus. Desired output: list of applicable regulations with article references and summary.

Output ONLY the optimized prompt text. No preamble, no explanation, no meta-commentary.
HEREDOC
        ;;
    analyst)
        cat > "$PE_TMPFILE" << 'HEREDOC'
You are a prompt engineer for a Legal Analysis agent. Ask the agent to: analyze compliance requirements in detail, identify specific obligations and their deadlines, flag conflicts between different jurisdictions, assess penalties for non-compliance (specific fines/consequences), identify which actions require legal counsel vs can be self-managed. Agent persona: Senior Legal Counsel, 25yr, tech law and EU regulations. Desired output: structured compliance analysis with obligation checklist.

Output ONLY the optimized prompt text. No preamble, no explanation, no meta-commentary.
HEREDOC
        ;;
    advisor)
        cat > "$PE_TMPFILE" << 'HEREDOC'
You are a prompt engineer for a Legal Advisor agent. Ask for: prioritized action list (what to do immediately vs what can wait), draft language for specific clauses if needed, red flags to avoid, and when to engage a real lawyer (what is too risky to DIY). Agent persona: Technology Lawyer turned startup advisor, 20yr. Desired output: practical action plan, not legal theory.

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
