#!/usr/bin/env bash
# planning/director.sh — Pre-Project Planning Director
#
# Runs BEFORE any new project starts. Performs deep multi-team analysis.
# Produces: project brief, architecture sketch, risk list, clarifying questions
#
# Usage:
#   ./director.sh "Build a SaaS platform for invoice management"
#   echo "project description" | ./director.sh
#   ./director.sh --skip-questions "Build..."   # auto-answer all questions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load .env if present
ENV_FILE="${AGENTS2_DIR}/.env"
if [[ -f "$ENV_FILE" ]]; then
    set -a; source "$ENV_FILE"; set +a
fi

source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"

# ── Argument parsing ───────────────────────────────────────────────────────────
SKIP_QUESTIONS=0
TASK_INPUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-questions|-s)
            SKIP_QUESTIONS=1
            shift
            ;;
        *)
            TASK_INPUT="$1"
            shift
            ;;
    esac
done

# Read from stdin if no positional arg
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

if [ -z "$TASK_INPUT" ] && [ ! -t 0 ]; then
    cat > "$TMPFILE"
    TASK_INPUT="$(cat "$TMPFILE")"
elif [ -n "$TASK_INPUT" ]; then
    printf '%s' "$TASK_INPUT" > "$TMPFILE"
else
    printf 'Error: provide project description via argument or stdin\n' >&2
    printf '  Usage: ./director.sh "Build a SaaS platform..."\n' >&2
    printf '  Usage: echo "project description" | ./director.sh\n' >&2
    exit 1
fi

if [ -z "${TASK_INPUT:-}" ]; then
    printf 'Error: project description is empty\n' >&2
    exit 1
fi

TASK_SUMMARY="${TASK_INPUT:0:120}"
PROJECT_NAME="$(printf '%s' "$TASK_INPUT" | head -1 | cut -c1-60)"

log_session_start
log_action "planning" "director" "orchestrator" "RUNNING" "$TASK_SUMMARY"

printf '\n\033[1;36m╔══════════════════════════════════════════════════════════════╗\033[0m\n' >&2
printf '\033[1;36m║         PRE-PROJECT PLANNING DIRECTOR — STARTING              ║\033[0m\n' >&2
printf '\033[1;36m╚══════════════════════════════════════════════════════════════╝\033[0m\n\n' >&2
printf '  Project: %s\n\n' "$PROJECT_NAME" >&2

# ── Read planning memory for context ───────────────────────────────────────────
PLANNING_MEMORY="$(memory_read "planning" 2>/dev/null || true)"

# ── Define team leads ──────────────────────────────────────────────────────────
BACKEND_LEAD="$AGENTS2_DIR/teams/backend/lead.sh"
SECURITY_LEAD="$AGENTS2_DIR/teams/security/lead.sh"
ANALYST_LEAD="$AGENTS2_DIR/teams/analyst/lead.sh"
PLANNER_LEAD="$AGENTS2_DIR/teams/planner/lead.sh"
STRATEGY_LEAD="$AGENTS2_DIR/teams/strategy/lead.sh"

# ── Temp files for parallel results ───────────────────────────────────────────
ARCH_OUT=$(mktemp)
RISK_OUT=$(mktemp)
BIZ_OUT=$(mktemp)
PLAN_OUT=$(mktemp)
CRITIC_OUT=$(mktemp)

trap 'rm -f "$TMPFILE" "$ARCH_OUT" "$RISK_OUT" "$BIZ_OUT" "$PLAN_OUT" "$CRITIC_OUT"' EXIT

# ── Helper: run a team lead with error capture ─────────────────────────────────
run_team() {
    local lead_script="$1"
    local task="$2"
    local output_file="$3"
    local team_label="$4"

    if [ ! -x "$lead_script" ]; then
        printf '[UNAVAILABLE] Team lead not found: %s\n' "$lead_script" > "$output_file"
        printf '  \033[0;33m⚠\033[0m  [planning/director] %s team lead not found, using placeholder\n' "$team_label" >&2
        return 0
    fi

    printf '  \033[0;36m▶\033[0m  [planning/director] Starting %s analysis...\n' "$team_label" >&2

    if bash "$lead_script" "$task" > "$output_file" 2>/dev/null; then
        printf '  \033[0;32m✓\033[0m  [planning/director] %s analysis done\n' "$team_label" >&2
    else
        printf '[FAILED] %s analysis failed — proceeding without it\n' "$team_label" > "$output_file"
        printf '  \033[0;31m✗\033[0m  [planning/director] %s analysis failed, using placeholder\n' "$team_label" >&2
    fi
}

# ── Run all analyses in parallel (max 5 subshells) ────────────────────────────
printf '\033[1m[1/3] Running parallel team analyses (max 5 concurrent)...\033[0m\n\n' >&2

ARCH_TASK="Analyze the technical architecture for this project. Provide: recommended tech stack with justifications, system design overview (services, databases, APIs), scalability considerations, key technical decisions and tradeoffs, potential technical bottlenecks. Project: ${TASK_INPUT}"

RISK_TASK="Perform a security and compliance risk analysis for this project. Identify: top security risks (OWASP-style), compliance requirements (GDPR, SOC2, PCI-DSS if applicable), authentication/authorization risks, data privacy concerns, third-party dependency risks, infrastructure security considerations. Project: ${TASK_INPUT}"

BIZ_TASK="Analyze the business viability and market fit for this project. Provide: target market analysis, key metrics to track (KPIs), monetization model assessment, competitive landscape overview, critical success factors, go-to-market considerations. Project: ${TASK_INPUT}"

PLAN_TASK="Create a realistic project timeline and scope plan. Provide: MVP definition (what is strictly necessary for launch), milestone breakdown with time estimates, resource requirements, suggested sprint structure for first 4 weeks, definition of done for MVP. Project: ${TASK_INPUT}"

CRITIC_TASK="You are a devil's advocate. Critically analyze what could go wrong with this project. Identify: top 5 failure modes and why projects like this fail, unrealistic assumptions being made, technical debt risks, market risks, execution risks, questions that MUST be answered before starting. Be brutally honest. Project: ${TASK_INPUT}"

# Launch all in parallel
run_team "$BACKEND_LEAD"  "$ARCH_TASK"   "$ARCH_OUT"   "architecture" &
PID_ARCH=$!

run_team "$SECURITY_LEAD" "$RISK_TASK"   "$RISK_OUT"   "security/risk" &
PID_RISK=$!

run_team "$ANALYST_LEAD"  "$BIZ_TASK"    "$BIZ_OUT"    "business" &
PID_BIZ=$!

run_team "$PLANNER_LEAD"  "$PLAN_TASK"   "$PLAN_OUT"   "planning" &
PID_PLAN=$!

run_team "$STRATEGY_LEAD" "$CRITIC_TASK" "$CRITIC_OUT" "critic/strategy" &
PID_CRITIC=$!

# Wait for all with error tolerance
for pid in $PID_ARCH $PID_RISK $PID_BIZ $PID_PLAN $PID_CRITIC; do
    wait "$pid" 2>/dev/null || true
done

printf '\n\033[1m[2/3] All team analyses complete. Synthesizing project brief...\033[0m\n\n' >&2

# ── Collect results ────────────────────────────────────────────────────────────
ARCH_RESULT="$(cat "$ARCH_OUT" 2>/dev/null || printf '[Architecture analysis unavailable]')"
RISK_RESULT="$(cat "$RISK_OUT" 2>/dev/null || printf '[Risk analysis unavailable]')"
BIZ_RESULT="$(cat "$BIZ_OUT"  2>/dev/null || printf '[Business analysis unavailable]')"
PLAN_RESULT="$(cat "$PLAN_OUT" 2>/dev/null || printf '[Planning analysis unavailable]')"
CRITIC_RESULT="$(cat "$CRITIC_OUT" 2>/dev/null || printf '[Critic analysis unavailable]')"

# ── Synthesize with GPT-4o ─────────────────────────────────────────────────────
SYNTHESIS_PROMPT="You are a senior project director creating a comprehensive pre-project brief.

PROJECT DESCRIPTION:
${TASK_INPUT}

ARCHITECTURE ANALYSIS:
${ARCH_RESULT}

SECURITY & RISK ANALYSIS:
${RISK_RESULT}

BUSINESS ANALYSIS:
${BIZ_RESULT}

PLANNING & TIMELINE:
${PLAN_RESULT}

CRITIC REVIEW (failure modes):
${CRITIC_RESULT}

${PLANNING_MEMORY:+PLANNING MEMORY (past projects):
$PLANNING_MEMORY
}

Synthesize all of the above into a single, well-structured PROJECT BRIEF using EXACTLY this format:

## 🎯 PROJECT SUMMARY
[2-3 sentence description of what this project is, who it's for, and why it matters]

## 🏗️ RECOMMENDED ARCHITECTURE
[Tech stack and system design recommendations, 5-8 bullet points with brief justifications]

## ⚠️ TOP RISKS (ranked by severity)
1. [CRITICAL] [risk title]: [brief explanation and mitigation]
2. [HIGH] [risk title]: [brief explanation and mitigation]
3. [HIGH] [risk title]: [brief explanation and mitigation]
4. [MEDIUM] [risk title]: [brief explanation]
5. [MEDIUM] [risk title]: [brief explanation]

## 📅 TIMELINE ESTIMATE
MVP: [X weeks/months] — [what's included]
Phase 2: [timeframe] — [what's added]
Full Launch: [timeframe] — [complete feature set]

Key milestones:
- Week 1-2: [milestone]
- Week 3-4: [milestone]
- [continue as needed]

## 📊 SUCCESS METRICS
[5-7 KPIs to track, with target values where possible]

## ❓ CLARIFYING QUESTIONS
Q1: [question — what needs to be decided before starting?]
Q2: [question]
Q3: [question]
Q4: [question]
Q5: [question]

## 🚀 RECOMMENDED FIRST STEPS
1. [concrete action]
2. [concrete action]
3. [concrete action]
4. [concrete action]
5. [concrete action]

Be specific, actionable, and concise. No padding or filler text."

SYNTHESIS_SYS="You are a senior technical project director. You synthesize multi-team analyses into clear, structured project briefs. Be specific and actionable. Never pad responses."

SYNTHESIS_FILE=$(mktemp)
SYS_FILE=$(mktemp)
trap 'rm -f "$TMPFILE" "$ARCH_OUT" "$RISK_OUT" "$BIZ_OUT" "$PLAN_OUT" "$CRITIC_OUT" "$SYNTHESIS_FILE" "$SYS_FILE"' EXIT

printf '%s' "$SYNTHESIS_PROMPT" > "$SYNTHESIS_FILE"
printf '%s' "$SYNTHESIS_SYS" > "$SYS_FILE"

# Try synthesis with GPT-4o, fallback to gemini
SYNTHESIS_RESULT=""
SYNTHESIS_MODEL="openai/gpt-4o"

if SYNTHESIS_RESULT="$(SYSTEM_PROMPT="$SYNTHESIS_SYS" \
    "$AGENTS2_DIR/call_model.sh" "openai/gpt-4o" < "$SYNTHESIS_FILE" 2>/dev/null)"; then
    SYNTHESIS_MODEL="openai/gpt-4o"
elif SYNTHESIS_RESULT="$(SYSTEM_PROMPT="$SYNTHESIS_SYS" \
    "$AGENTS2_DIR/call_model.sh" "google/gemini-2.0-flash-001" < "$SYNTHESIS_FILE" 2>/dev/null)"; then
    SYNTHESIS_MODEL="google/gemini-2.0-flash-001"
else
    # Fallback: assemble manually from raw results
    SYNTHESIS_RESULT="## 🎯 PROJECT SUMMARY
${TASK_INPUT}

## 🏗️ RECOMMENDED ARCHITECTURE
${ARCH_RESULT}

## ⚠️ TOP RISKS
${RISK_RESULT}

## 📅 TIMELINE ESTIMATE
${PLAN_RESULT}

## ❓ CLARIFYING QUESTIONS
Q1: What is the primary target user segment?
Q2: What is the monetization model?
Q3: What are the compliance requirements?
Q4: What is the expected initial scale?
Q5: What is the launch deadline?

## 🚀 RECOMMENDED FIRST STEPS
1. Define MVP scope precisely
2. Set up development environment and CI/CD
3. Implement core data model
4. Build authentication layer
5. Create first working prototype"
    SYNTHESIS_MODEL="fallback-manual"
fi

log_action "planning" "director" "$SYNTHESIS_MODEL" "SUCCESS" \
    "Synthesis complete: $TASK_SUMMARY"

# ── Print the project brief ────────────────────────────────────────────────────
printf '\n'
printf '╔══════════════════════════════════════════════════════════════╗\n'
printf '║              PROJECT BRIEF — %-32s║\n' "${PROJECT_NAME:0:32}"
printf '╚══════════════════════════════════════════════════════════════╝\n'
printf '\n'
printf '%s\n' "$SYNTHESIS_RESULT"
printf '\n'

# ── Clarifying questions with 30-second timeout ────────────────────────────────
if [ "$SKIP_QUESTIONS" -eq 0 ] && [ -t 0 ]; then
    printf '\n\033[1m[3/3] Clarifying Questions — you have 30 seconds to respond\033[0m\n' >&2
    printf '      (Press Enter after each answer, or wait to auto-proceed)\n\n' >&2

    # Extract Q lines from synthesis
    Q_LINES=$(printf '%s' "$SYNTHESIS_RESULT" | grep -E '^Q[0-9]+:' | head -5 || true)

    ANSWERS=""
    if [ -n "$Q_LINES" ]; then
        printf '%s\n\n' "$Q_LINES"

        printf 'Your answers (optional, 30s timeout):\n> ' >&2
        USER_INPUT=""
        if read -r -t 30 USER_INPUT 2>/dev/null; then
            if [ -n "$USER_INPUT" ]; then
                ANSWERS="$USER_INPUT"
                printf '\n  Answers recorded. Proceeding with your input.\n\n' >&2
            else
                printf '\n  No input. Proceeding with best assumptions.\n\n' >&2
            fi
        else
            printf '\n\n  Timeout reached (30s). Proceeding with best assumptions.\n\n' >&2
        fi
    fi
elif [ "$SKIP_QUESTIONS" -eq 0 ]; then
    # Non-interactive context (called from dispatch.sh or pipe) — skip without waiting
    printf '\n  [non-interactive] Skipping clarifying questions (no tty).\n\n' >&2
    ANSWERS="[auto-proceed: non-interactive mode]"
else
    printf '\n  [--skip-questions] Skipping clarifying questions, auto-proceeding.\n\n' >&2
    ANSWERS="[auto-proceed: no user input requested]"
fi

# ── Update planning memory ─────────────────────────────────────────────────────
MEMORY_ENTRY="Project: ${PROJECT_NAME:0:60} | Stack: $(printf '%s' "$SYNTHESIS_RESULT" | grep -i 'stack\|framework\|language' | head -1 | cut -c1-80 || true) | Risks: top risks analyzed"
memory_append "planning" "$MEMORY_ENTRY"

if [ -n "${ANSWERS:-}" ] && [ "$ANSWERS" != "[auto-proceed: no user input requested]" ]; then
    memory_append "planning" "User clarifications for ${PROJECT_NAME:0:50}: ${ANSWERS:0:100}"
fi

log_action "planning" "director" "$SYNTHESIS_MODEL" "SUCCESS" \
    "Planning brief complete for: $TASK_SUMMARY" "" ""
log_session_end

printf '\033[1;32m✅ Planning brief complete.\033[0m\n' >&2
printf '   Memory updated: %s/planning/memory.md\n' "$AGENTS2_DIR" >&2
printf '\n' >&2
