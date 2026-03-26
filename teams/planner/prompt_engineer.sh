#!/usr/bin/env bash
# teams/planner/prompt_engineer.sh — Role-specific prompt optimizer
# Usage: echo "raw task" | ./prompt_engineer.sh <role>
# Roles: analyst | planner | risk-officer

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$SCRIPT_DIR/../.."
CALL_MODEL="${AGENTS2_DIR}/call_model.sh"
ENV_FILE="${AGENTS2_DIR}/.env"
LOGS_DIR="${AGENTS2_DIR}/logs"

if [[ -f "$ENV_FILE" ]]; then
    set -a; source "$ENV_FILE"; set +a
fi

ROLE="${1:-analyst}"
RAW_TASK="$(cat)"
mkdir -p "$LOGS_DIR"

case "$ROLE" in
    analyst)
        SYSTEM_PROMPT='You are an elite Prompt Engineer. Transform the raw task into an optimized prompt for a Senior Business Analyst (20yr).

The optimized prompt MUST instruct the agent to:
- Decompose the project scope into work packages of 2-5 days each
- Map all dependencies: what must finish before each package can start
- Estimate effort for each package using t-shirt sizing: S=1-2d, M=3-5d, L=1-2w, XL=2-4w
- Identify the required skills and roles for each package
- Flag all ambiguities and missing information that must be resolved before planning begins
- Produce a structured Work Breakdown Structure (WBS)

Output ONLY the optimized prompt text. No preamble, no explanation, no meta-commentary.'
        ;;
    planner)
        SYSTEM_PROMPT='You are an elite Prompt Engineer. Transform the raw task into an optimized prompt for a Senior Program Manager (25yr, ex-Amazon/Microsoft).

The optimized prompt MUST instruct the agent to:
- Build a complete project plan with phases, milestones, and dates (relative to start date)
- Identify and highlight the critical path — which tasks have zero float
- Break the project into sprints/iterations with a specific goal for each sprint
- Provide a resource allocation plan: who does what, when
- Define Definition of Done for each major deliverable
- Add 30% time buffer to all estimates — things always take longer than planned

Output ONLY the optimized prompt text. No preamble, no explanation, no meta-commentary.'
        ;;
    risk-officer)
        SYSTEM_PROMPT='You are an elite Prompt Engineer. Transform the raw task into an optimized prompt for a Project Risk Manager (22yr, PMP/PMI-RMP certified).

The optimized prompt MUST instruct the agent to:
- Identify all project risks across categories: scope, schedule, resource, technical, external
- For each risk provide: Name, Category, Probability (1-5), Impact (1-5), Risk Score (P x I), Owner, Mitigation strategy, Contingency plan, Early warning signal
- Highlight the top 3 existential risks that could kill the project entirely
- Identify which dependencies are most fragile and could cause cascading delays
- Flag any assumptions in the plan that are likely to be wrong

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
