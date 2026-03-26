#!/usr/bin/env bash
# teams/researcher/prompt_engineer.sh — Role-specific prompt optimizer
# Usage: echo "raw task" | ./prompt_engineer.sh <role>
# Roles: finder | synthesizer | validator

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$SCRIPT_DIR/../.."
CALL_MODEL="${AGENTS2_DIR}/call_model.sh"
ENV_FILE="${AGENTS2_DIR}/.env"
LOGS_DIR="${AGENTS2_DIR}/logs"

if [[ -f "$ENV_FILE" ]]; then
    set -a; source "$ENV_FILE"; set +a
fi

ROLE="${1:-finder}"
RAW_TASK="$(cat)"
mkdir -p "$LOGS_DIR"

PE_TMPFILE=$(mktemp)
trap 'rm -f "$PE_TMPFILE"' EXIT

case "$ROLE" in
    finder)
        cat > "$PE_TMPFILE" << 'HEREDOC'
You are a prompt engineer for a Research Finder agent. Ask the agent to find all relevant information: primary sources (industry reports, academic papers, government data), secondary sources (news, analysis, case studies), key statistics and data points with dates, and identify gaps where data is missing or conflicting. Agent persona: Research Librarian and Intelligence Analyst, 20yr.

Output ONLY the optimized prompt text. No preamble, no explanation, no meta-commentary.
HEREDOC
        ;;
    synthesizer)
        cat > "$PE_TMPFILE" << 'HEREDOC'
You are a prompt engineer for a Research Synthesis agent. Ask the agent to synthesize findings into coherent narrative: group findings by theme, identify patterns and trends, highlight agreements and contradictions between sources, extract key insights, and produce an executive summary. Agent persona: Senior Research Analyst, 18yr.

Output ONLY the optimized prompt text. No preamble, no explanation, no meta-commentary.
HEREDOC
        ;;
    validator)
        cat > "$PE_TMPFILE" << 'HEREDOC'
You are a prompt engineer for a Research Validation agent. Ask the agent to critically validate all claims: verify each statistic has a credible source, flag data older than 2 years, identify potential biases in sources, find counterarguments and contradicting data, assess confidence level for each major claim. Agent persona: Fact-Checker and Research Integrity Specialist, 15yr.

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
