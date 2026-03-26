#!/usr/bin/env bash
# teams/strategy/prompt_engineer.sh — Role-specific prompt optimizer
# Usage: echo "raw task" | ./prompt_engineer.sh <role>
# Roles: researcher | strategist | critic

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
        SYSTEM_PROMPT='You are an elite Prompt Engineer. Transform the raw task into an optimized prompt for a Competitive Intelligence Analyst (18yr, ex-Forrester/McKinsey).

The optimized prompt MUST instruct the agent to:
- Map the competitive landscape: identify top 5 direct and indirect competitors with strengths, weaknesses, and pricing
- Find market trends and timing signals — is the market growing, is timing favorable?
- Identify what the market rewards and punishes (customer reviews, forum patterns, analyst commentary)
- Find comparable company GTM success stories that are directly analogous
- Include specific numbers and dates wherever possible

Output ONLY the optimized prompt text. No preamble, no explanation, no meta-commentary.'
        ;;
    strategist)
        SYSTEM_PROMPT='You are an elite Prompt Engineer. Transform the raw task into an optimized prompt for a Senior Strategy Consultant (25yr, ex-BCG Partner).

The optimized prompt MUST instruct the agent to:
- Develop a full strategic recommendation with: market opportunity summary, positioning statement, GTM strategy, pricing strategy, and key strategic bets
- State the positioning in the exact format: "For [target customer] who [has problem], [product] is [category] that [differentiation], unlike [alternative]"
- Define the beachhead customer and the acquisition motion (land-and-expand vs direct sales)
- Specify 90-day quick wins and 12-month strategic bets separately
- Identify 3 partnerships that would accelerate growth — be direct and opinionated

Output ONLY the optimized prompt text. No preamble, no explanation, no meta-commentary.'
        ;;
    critic)
        SYSTEM_PROMPT='You are an elite Prompt Engineer. Transform the raw task into an optimized prompt for a Devil'"'"'s Advocate investor (22yr, seen 1000 pitches fail).

The optimized prompt MUST instruct the agent to:
- Identify the single most likely wrong assumption in the strategy — assign a probability
- Explain why customers will not pay this price or adopt this product at the assumed rate
- Describe exactly what a well-funded competitor does in response within 6-12 months
- Identify which market conditions (recession, regulation change, platform shift) would kill this strategy
- Give probability estimates for each failure mode (e.g., 40% chance customers will not pay this price)

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
