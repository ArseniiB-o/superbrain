#!/usr/bin/env bash
# teams/researcher/lead.sh — Researcher Team Lead (3 specialists in parallel)
# Specialists: finder (gpt-4o-mini) + synthesizer (deepseek) + validator (gpt-4o-mini)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$SCRIPT_DIR/../.."

source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"

CALL_MODEL="${AGENTS2_DIR}/call_model.sh"
TEAM="researcher"
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

(echo "$RAW_TASK" | TEAM_MEMORY="$TEAM_MEMORY" "$PE_SCRIPT" "finder" 2>/dev/null > "$PE_1" || echo "$RAW_TASK" > "$PE_1") &
PID_PE_1=$!
(echo "$RAW_TASK" | TEAM_MEMORY="$TEAM_MEMORY" "$PE_SCRIPT" "synthesizer" 2>/dev/null > "$PE_2" || echo "$RAW_TASK" > "$PE_2") &
PID_PE_2=$!
(echo "$RAW_TASK" | TEAM_MEMORY="$TEAM_MEMORY" "$PE_SCRIPT" "validator" 2>/dev/null > "$PE_3" || echo "$RAW_TASK" > "$PE_3") &
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
Research Intelligence Analyst with 20 years at Gartner and McKinsey Global Institute. Your role: find all relevant information. Gather: (1) Key statistics and market data (with source, year, methodology), (2) Industry reports and their main findings (Gartner, IDC, Forrester, CB Insights as relevant), (3) Real-world case studies and comparable examples, (4) Expert opinions and authoritative quotes, (5) Regulatory or government data if relevant. Flag: data older than 2 years, estimated vs measured numbers, conflicting data from different sources. Quantity and coverage — find everything.
HEREDOC

SP2_FILE=$(mktemp)
cat > "$SP2_FILE" << 'HEREDOC'
Senior Research Analyst with 18 years synthesizing complex information for executive decision-making. Your role: organize and synthesize all research into coherent insights. (1) Group findings by theme, (2) Identify patterns and trends across sources, (3) Highlight key insights (the non-obvious conclusions), (4) Note agreements and contradictions between sources, (5) Extract the 5 most important findings with supporting evidence. Structure for executive readability: lead with the conclusion, support with evidence.
HEREDOC

SP3_FILE=$(mktemp)
cat > "$SP3_FILE" << 'HEREDOC'
Research Integrity and Fact-Checking Specialist with 15 years at Reuters and academic journals. Your role: validate all claims critically. For each major claim: (1) Source credibility (who published it? when? what is their methodology?), (2) Data freshness (is it current? if > 2 years old, flag it), (3) Sample size and statistical significance (is the sample representative?), (4) Potential bias (does the source have incentive to show specific results?), (5) Contradicting evidence (find data that challenges each claim). Produce a confidence rating: HIGH/MEDIUM/LOW for each major finding.
HEREDOC

{ SYSTEM_PROMPT="$(cat "$SP1_FILE")" "$CALL_MODEL" "openai/gpt-4o-mini" < "$WORK_DIR/p1.txt" > "$WORK_DIR/r1.txt" 2>/dev/null || printf '[finder failed]' > "$WORK_DIR/r1.txt"; } &
PID_1=$!
{ SYSTEM_PROMPT="$(cat "$SP2_FILE")" "$CALL_MODEL" "deepseek/deepseek-chat" < "$WORK_DIR/p2.txt" > "$WORK_DIR/r2.txt" 2>/dev/null || printf '[synthesizer failed]' > "$WORK_DIR/r2.txt"; } &
PID_2=$!
{ SYSTEM_PROMPT="$(cat "$SP3_FILE")" "$CALL_MODEL" "openai/gpt-4o-mini" < "$WORK_DIR/p3.txt" > "$WORK_DIR/r3.txt" 2>/dev/null || printf '[validator failed]' > "$WORK_DIR/r3.txt"; } &
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
You are the Head of Research. Combine: Raw Research (Finder), Synthesis (Synthesizer), and Validation (Validator). Produce the Research Report: (1) Executive Summary (5 key findings in 3 sentences each), (2) Detailed findings by theme with source citations, (3) Confidence ratings for each major claim, (4) Data gaps and areas of uncertainty, (5) Recommended next research steps. All statistics must include: source, year, and confidence rating.
HEREDOC

SYNTH_PROMPT=$(mktemp)
cat > "$SYNTH_PROMPT" << SYNTHEOF
Original task: $TASK_SUMMARY

=== FINDER OUTPUT ===
$RESULT_1

=== SYNTHESIZER OUTPUT ===
$RESULT_2

=== VALIDATOR OUTPUT ===
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
Specialists: Finder(gpt-4o-mini) + Synthesizer(deepseek) + Validator(gpt-4o-mini)
Additional teams:
- analyst: business interpretation of research findings
- strategy: strategic implications of research
- marketing: market research for GTM decisions
- legal: regulatory research validation"

RESULT="${RESULT}${SELF_ASSESSMENT}"

echo "  [${TEAM}/lead] Done" >&2
echo "$RESULT"
