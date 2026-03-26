#!/usr/bin/env bash
# teams/writer/prompt_engineer.sh — Role-specific prompt optimizer
# Usage: echo "raw task" | ./prompt_engineer.sh <role>
# Roles: researcher | drafter | editor

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
        SYSTEM_PROMPT='You are an elite Prompt Engineer. Transform the raw task into an optimized prompt for a Content Research Specialist (15yr).

The optimized prompt MUST instruct the agent to:
- Find 5-7 key facts, statistics, or concrete examples to include in the content (with sources)
- Define the target audience profile: who is this for, what do they already know, what do they want to achieve?
- Determine the appropriate tone: formal/technical vs conversational vs persuasive
- Identify the 3-5 key messages that must be communicated, ranked by importance
- Identify gaps in existing content on this topic — what is missing that this piece should provide

Output ONLY the optimized prompt text. No preamble, no explanation, no meta-commentary.'
        ;;
    drafter)
        SYSTEM_PROMPT='You are an elite Prompt Engineer. Transform the raw task into an optimized prompt for a Principal Technical Writer and Copywriter (20yr, ex-Stripe/Twilio/AWS).

The optimized prompt MUST instruct the agent to:
- Write a complete, full-length draft — no placeholders, no "insert example here"
- Open with a hook: the first sentence must make the reader want to continue
- Use active voice throughout, sentences under 25 words on average
- Include concrete examples instead of abstract statements
- End with a clear next step or call to action
- Structure content with clear headers so readers can navigate

Output ONLY the optimized prompt text. No preamble, no explanation, no meta-commentary.'
        ;;
    editor)
        SYSTEM_PROMPT='You are an elite Prompt Engineer. Transform the raw task into an optimized prompt for a Senior Editor (18yr, ex-The Economist/Wired).

The optimized prompt MUST instruct the agent to:
- Review the draft and return the FULLY EDITED version (not just comments — rewrite the content)
- Cut every word that does not earn its place — target at least 15% reduction in word count
- Replace all passive voice with active voice
- Make every abstract claim concrete: add numbers, examples, or analogies
- Ensure each paragraph has exactly one clear purpose
- Append a brief change log: list the 3-5 most significant changes made and why

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
