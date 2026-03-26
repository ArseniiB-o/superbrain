#!/usr/bin/env bash
# teams/marketing/lead.sh — Marketing Team Lead (3 specialists in parallel)
# Specialists: researcher (deepseek) + strategist (gpt-4o) + analyst (gpt-4o-mini)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$SCRIPT_DIR/../.."

source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"

CALL_MODEL="${AGENTS2_DIR}/call_model.sh"
TEAM="marketing"
PE_SCRIPT="$SCRIPT_DIR/prompt_engineer.sh"

# ── Phase 0: Parse input ──────────────────────────────────────────────────────
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

if [ ! -t 0 ]; then
    { [ -n "${1:-}" ] && printf '%s\n\n' "$1"; cat; } > "$TMPFILE"
elif [ -n "${1:-}" ]; then
    printf '%s' "$1" > "$TMPFILE"
else
    echo "Error: provide task via argument or stdin" >&2; exit 1
fi

RAW_TASK=$(cat "$TMPFILE")
TASK_SUMMARY="${RAW_TASK:0:120}"

log_action "$TEAM" "lead" "orchestrator" "RUNNING" "$TASK_SUMMARY" "$RAW_TASK"
echo "[${TEAM}/lead] Starting: ${TASK_SUMMARY:0:70}..." >&2

TEAM_MEMORY=$(memory_read "$TEAM")

# ── Phase 1: 3 parallel PE calls ─────────────────────────────────────────────
echo "  [${TEAM}/lead] Optimizing prompts (3 specialists in parallel)..." >&2

PE_1=$(mktemp); PE_2=$(mktemp); PE_3=$(mktemp)
trap 'rm -f "$TMPFILE" "$PE_1" "$PE_2" "$PE_3"' EXIT

(echo "$RAW_TASK" | TEAM_MEMORY="$TEAM_MEMORY" "$PE_SCRIPT" "researcher" 2>/dev/null > "$PE_1" || echo "$RAW_TASK" > "$PE_1") &
PID_PE_1=$!
(echo "$RAW_TASK" | TEAM_MEMORY="$TEAM_MEMORY" "$PE_SCRIPT" "strategist" 2>/dev/null > "$PE_2" || echo "$RAW_TASK" > "$PE_2") &
PID_PE_2=$!
(echo "$RAW_TASK" | TEAM_MEMORY="$TEAM_MEMORY" "$PE_SCRIPT" "analyst" 2>/dev/null > "$PE_3" || echo "$RAW_TASK" > "$PE_3") &
PID_PE_3=$!

wait "$PID_PE_1" "$PID_PE_2" "$PID_PE_3"

PROMPT_1=$(cat "$PE_1")
PROMPT_2=$(cat "$PE_2")
PROMPT_3=$(cat "$PE_3")

# ── Phase 2: Run 3 agents in parallel with system prompts via temp files ──────
echo "  [${TEAM}/lead] Running 3 specialists in parallel..." >&2

WORK_DIR=$(mktemp -d)
trap 'rm -f "$TMPFILE" "$PE_1" "$PE_2" "$PE_3"; rm -rf "$WORK_DIR"' EXIT

printf '%s' "$PROMPT_1" > "$WORK_DIR/p1.txt"
printf '%s' "$PROMPT_2" > "$WORK_DIR/p2.txt"
printf '%s' "$PROMPT_3" > "$WORK_DIR/p3.txt"

SP1_FILE=$(mktemp)
cat > "$SP1_FILE" << 'HEREDOC'
Senior Market Research Analyst with 18 years at Forrester and CB Insights. Research this marketing challenge: (1) Market size — TAM (total addressable), SAM (serviceable), SOM (obtainable) with bottom-up calculations, (2) 3 acquisition channels proven in this market with estimated CAC per channel, (3) 3 comparable companies — their GTM approach, growth trajectory, and what made them succeed or fail, (4) Target customer insights — what problems they complain about, what solutions they've tried. Cite sources for all numbers.
HEREDOC

SP2_FILE=$(mktemp)
cat > "$SP2_FILE" << 'HEREDOC'
CMO and Growth Expert with 22 years scaling B2B SaaS from 0 to $100M ARR. Build the marketing strategy: (1) ICP definition (industry, company size, title, trigger events, pain points), (2) Positioning statement (for [ICP] who [pain], [product] is [category] that [value], unlike [alternative] which [limitation]), (3) Top 3 acquisition channels with 90-day activation plan for each, (4) Content pillars and distribution strategy, (5) Key metrics targets: Month 3 / Month 6 / Month 12 (leads, MQLs, SQLs, CAC). Be specific and actionable.
HEREDOC

SP3_FILE=$(mktemp)
cat > "$SP3_FILE" << 'HEREDOC'
Marketing Analytics specialist with 15 years building growth measurement at HubSpot and Marketo. Build the metrics framework: (1) Define the full funnel with conversion rate benchmarks (awareness→consideration→decision→retention), (2) CAC calculation for each channel (spend / new customers per channel), (3) LTV model (ARPU × gross margin × average customer lifetime), (4) CAC:LTV ratio and payback period targets, (5) Recommended attribution model (last-touch vs multi-touch vs data-driven), (6) Dashboard template — which 5 metrics to review weekly and 10 metrics monthly.
HEREDOC

{ SYSTEM_PROMPT="$(cat "$SP1_FILE")" "$CALL_MODEL" "deepseek/deepseek-chat" < "$WORK_DIR/p1.txt" > "$WORK_DIR/r1.txt" 2>/dev/null || printf '[researcher failed]' > "$WORK_DIR/r1.txt"; } &
PID_1=$!
{ SYSTEM_PROMPT="$(cat "$SP2_FILE")" "$CALL_MODEL" "openai/gpt-4o" < "$WORK_DIR/p2.txt" > "$WORK_DIR/r2.txt" 2>/dev/null || printf '[strategist failed]' > "$WORK_DIR/r2.txt"; } &
PID_2=$!
{ SYSTEM_PROMPT="$(cat "$SP3_FILE")" "$CALL_MODEL" "openai/gpt-4o-mini" < "$WORK_DIR/p3.txt" > "$WORK_DIR/r3.txt" 2>/dev/null || printf '[analyst failed]' > "$WORK_DIR/r3.txt"; } &
PID_3=$!

wait "$PID_1" "$PID_2" "$PID_3"
rm -f "$SP1_FILE" "$SP2_FILE" "$SP3_FILE"

RESULT_1=$(cat "$WORK_DIR/r1.txt")
RESULT_2=$(cat "$WORK_DIR/r2.txt")
RESULT_3=$(cat "$WORK_DIR/r3.txt")

echo "  [${TEAM}/lead] Specialists done. Synthesizing..." >&2

# ── Phase 3: Synthesize ───────────────────────────────────────────────────────
SYNTH_FILE=$(mktemp)
cat > "$SYNTH_FILE" << 'HEREDOC'
You are the Chief Marketing Officer reviewing outputs from Market Researcher, Marketing Strategist, and Marketing Analyst. Produce the complete Marketing Plan: (1) Market opportunity summary with validated TAM/SAM/SOM, (2) ICP and positioning, (3) Go-to-market strategy with channel activation playbooks, (4) Marketing metrics framework, (5) 90-day marketing roadmap with Week-by-Week priorities. Everything must be specific, numbered, and actionable.
HEREDOC

SYNTH_PROMPT=$(mktemp)
cat > "$SYNTH_PROMPT" << SYNTHEOF
Original task: $TASK_SUMMARY

=== RESEARCHER OUTPUT ===
$RESULT_1

=== STRATEGIST OUTPUT ===
$RESULT_2

=== ANALYST OUTPUT ===
$RESULT_3
SYNTHEOF

RESULT=$(SYSTEM_PROMPT="$(cat "$SYNTH_FILE")" "$CALL_MODEL" "openai/gpt-4o" < "$SYNTH_PROMPT" 2>/dev/null) || RESULT=""
rm -f "$SYNTH_FILE" "$SYNTH_PROMPT"

if [ -z "$RESULT" ]; then
    RESULT="$RESULT_1

---

$RESULT_2

---

$RESULT_3"
fi

# ── Phase 4: memory_append + log_action + self-assessment ─────────────────────
LEARNING="$(date '+%Y-%m-%d'): ${TASK_SUMMARY:0:80}"
memory_append "$TEAM" "$LEARNING"

log_action "$TEAM" "lead" "orchestrator" "SUCCESS" "$TASK_SUMMARY" "$RAW_TASK" "$RESULT"

SELF_ASSESSMENT="

---
## [${TEAM} Team] Self-Assessment
Specialists: Researcher(deepseek) + Strategist(gpt-4o) + Analyst(gpt-4o-mini)
Additional teams:
- researcher: primary research (customer interviews, surveys)
- finance: marketing budget allocation and ROI modeling
- strategy: alignment with business strategy and competitive positioning
- writer: content creation and campaign copywriting"

RESULT="${RESULT}${SELF_ASSESSMENT}"

echo "  [${TEAM}/lead] Done" >&2
echo "$RESULT"
