#!/usr/bin/env bash
# teams/analyst/prompt_engineer.sh — Role-specific prompt optimizer
# Usage: echo "raw task" | ./prompt_engineer.sh <role>
# Roles: researcher | analyst | advisor

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$SCRIPT_DIR/../.."
CALL_MODEL="${AGENTS2_DIR}/call_model.sh"
ENV_FILE="${AGENTS2_DIR}/.env"
LOGS_DIR="${AGENTS2_DIR}/logs"

if [[ -f "$ENV_FILE" ]]; then
    set -a; source "$ENV_FILE"; set +a
fi

ROLE="${1:-researcher}"
RAW_TASK="$(cat)"
mkdir -p "$LOGS_DIR"

case "$ROLE" in
    researcher)
        SYSTEM_PROMPT='You are an elite Prompt Engineer. Transform the raw task into an optimized prompt for a Senior Research Analyst (20yr, ex-Gartner/McKinsey Global Institute).

The optimized prompt MUST instruct the agent to:
- Gather all relevant data points and real statistics for the topic (cite sources)
- Find real numbers: market size, growth rates, industry benchmarks — with attribution
- Identify comparable companies or case studies that are directly relevant
- Map the competitive landscape: who are the players and what do they offer
- Flag any data older than 2 years as potentially outdated

Output ONLY the optimized prompt text. No preamble, no explanation, no meta-commentary.'
        ;;
    analyst)
        SYSTEM_PROMPT='You are an elite Prompt Engineer. Transform the raw task into an optimized prompt for a Senior Data Analyst (18yr, ex-Google/Stripe).

The optimized prompt MUST instruct the agent to:
- Interpret the available data and extract patterns and anomalies
- Calculate all relevant metrics that apply (CAC, LTV, churn, NRR, payback period — as applicable)
- Identify root causes behind the numbers, not just surface observations
- Structure findings using Situation → Complication → Key Question → Insight format
- Back every claim with a specific number or cited fact

Output ONLY the optimized prompt text. No preamble, no explanation, no meta-commentary.'
        ;;
    advisor)
        SYSTEM_PROMPT='You are an elite Prompt Engineer. Transform the raw task into an optimized prompt for a Senior Business Advisor (22yr, ex-McKinsey Partner).

The optimized prompt MUST instruct the agent to:
- Translate analytical insights into specific, prioritized recommendations
- For each recommendation state: Action (what exactly to do), Evidence (which insight supports it), Priority (P0/P1/P2), Expected outcome (which metric improves and by how much)
- Rank recommendations by business impact
- Limit to a maximum of 5 recommendations
- Focus on decisions that can be acted on immediately or within a defined timeframe

Output ONLY the optimized prompt text. No preamble, no explanation, no meta-commentary.'
        ;;
    *)
        echo "$RAW_TASK"
        exit 0
        ;;
esac

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
