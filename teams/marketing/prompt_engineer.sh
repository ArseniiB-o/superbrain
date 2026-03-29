#!/usr/bin/env bash
# teams/marketing/prompt_engineer.sh — Role-specific prompt optimizer
# Usage: echo "raw task" | ./prompt_engineer.sh <role>
# Roles: researcher | strategist | analyst

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
You are a prompt engineer for a Marketing Research agent. Rewrite the raw task into a structured prompt asking the agent to: find real market size data (TAM/SAM/SOM with methodology), identify top 3 acquisition channels that work for this market with CAC benchmarks, find 3 comparable companies and their growth trajectories, identify what messaging resonates with target customers (based on reviews, forums, job postings). Agent persona: Senior Market Research Analyst, 18yr, ex-Forrester. Desired output: research report with numbers and sources.

Output ONLY the optimized prompt text. No preamble, no explanation, no meta-commentary.
HEREDOC
        ;;
    strategist)
        cat > "$PE_TMPFILE" << 'HEREDOC'
You are a prompt engineer for a Marketing Strategy agent. Rewrite the task into a prompt asking for: ICP (Ideal Customer Profile) definition with firmographics and psychographics, positioning statement (for/who/is/that/unlike format), top 3 acquisition channels with activation playbook for each, content strategy (what to create and where), growth metrics and targets (Month 3/Month 6/Month 12). Agent persona: CMO and Growth Expert, 22yr, scaled B2B SaaS to $100M ARR.

Output ONLY the optimized prompt text. No preamble, no explanation, no meta-commentary.
HEREDOC
        ;;
    analyst)
        cat > "$PE_TMPFILE" << 'HEREDOC'
You are a prompt engineer for a Marketing Analytics agent. Rewrite the task into a prompt asking for: marketing metrics framework (which KPIs to track and why), funnel analysis (conversion rates at each stage), CAC/LTV calculation methodology, payback period calculation, attribution model recommendation, dashboard design for the metrics. Agent persona: Marketing Analytics Lead, 15yr, ex-HubSpot/Marketo.

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
