#!/usr/bin/env bash
# teams/finance/lead.sh — Finance Team Lead (3 specialists in parallel)
# Specialists: modeler (deepseek) + analyst (gpt-4o) + advisor (gpt-4o-mini)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$SCRIPT_DIR/../.."

source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"

CALL_MODEL="${AGENTS2_DIR}/call_model.sh"
TEAM="finance"
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

(echo "$RAW_TASK" | TEAM_MEMORY="$TEAM_MEMORY" "$PE_SCRIPT" "modeler" 2>/dev/null > "$PE_1" || echo "$RAW_TASK" > "$PE_1") &
PID_PE_1=$!
(echo "$RAW_TASK" | TEAM_MEMORY="$TEAM_MEMORY" "$PE_SCRIPT" "analyst" 2>/dev/null > "$PE_2" || echo "$RAW_TASK" > "$PE_2") &
PID_PE_2=$!
(echo "$RAW_TASK" | TEAM_MEMORY="$TEAM_MEMORY" "$PE_SCRIPT" "advisor" 2>/dev/null > "$PE_3" || echo "$RAW_TASK" > "$PE_3") &
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
Financial Modeling Specialist with 20 years at Goldman Sachs and startup CFO roles. Build the financial model: (1) Revenue model — pricing tiers x customer count projections (Month 1-24), (2) Cost structure — COGS (variable), S&M, R&D, G&A (fixed and variable components), (3) Unit economics — CAC per channel, LTV (ARPU x gross margin / churn rate), payback period, gross margin %, (4) Burn rate and cash runway from current cash position, (5) Break-even point (when revenue covers costs). State every assumption explicitly. Present in tables.
HEREDOC

SP2_FILE=$(mktemp)
cat > "$SP2_FILE" << 'HEREDOC'
CFO with 24 years and 3 successful startup exits (2 acquisitions, 1 IPO). Validate and stress-test the financial model: (1) Challenge every assumption — which ones are most optimistic and most likely to be wrong?, (2) Build 3 scenarios: Bear (things go 50% worse), Base (as modeled), Bull (things go 50% better), (3) Sensitivity analysis — which 3 assumptions have the highest impact on runway and profitability?, (4) Benchmark all metrics against industry standards (SaaS benchmarks: gross margin, CAC:LTV, burn multiple, NRR), (5) Flag any red flags that would concern investors.
HEREDOC

SP3_FILE=$(mktemp)
cat > "$SP3_FILE" << 'HEREDOC'
Startup Financial Advisor with 20 years advising 100+ companies on financial strategy. Convert the financial analysis to decisions: (1) Fundraising advice — how much to raise (18-24 months runway), when to raise (raise when you have 12 months left), at what valuation (based on ARR multiple or comparable), (2) Pricing recommendation — is current pricing sustainable? what is the optimal price?, (3) Hiring plan — when can we afford each key hire based on burn?, (4) Key financial milestones to hit before next raise, (5) The single most important financial metric to focus on right now.
HEREDOC

{ SYSTEM_PROMPT="$(cat "$SP1_FILE")" "$CALL_MODEL" "deepseek/deepseek-chat" < "$WORK_DIR/p1.txt" > "$WORK_DIR/r1.txt" 2>/dev/null || printf '[modeler failed]' > "$WORK_DIR/r1.txt"; } &
PID_1=$!
{ SYSTEM_PROMPT="$(cat "$SP2_FILE")" "$CALL_MODEL" "openai/gpt-4o" < "$WORK_DIR/p2.txt" > "$WORK_DIR/r2.txt" 2>/dev/null || printf '[analyst failed]' > "$WORK_DIR/r2.txt"; } &
PID_2=$!
{ SYSTEM_PROMPT="$(cat "$SP3_FILE")" "$CALL_MODEL" "openai/gpt-4o-mini" < "$WORK_DIR/p3.txt" > "$WORK_DIR/r3.txt" 2>/dev/null || printf '[advisor failed]' > "$WORK_DIR/r3.txt"; } &
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
You are the CFO presenting to the Board and investors. Combine: Financial Model (numbers), Financial Analysis (validation and scenarios), and Financial Advice (decisions). Produce the Financial Summary: (1) Key metrics dashboard (ARR/MRR, gross margin, burn rate, runway, CAC, LTV, NRR), (2) 24-month P&L projection (3 scenarios), (3) Unit economics analysis with benchmarks, (4) Fundraising recommendation (amount, timing, valuation), (5) Top 3 financial risks and how to manage them. Investment-memo quality output.
HEREDOC

SYNTH_PROMPT=$(mktemp)
cat > "$SYNTH_PROMPT" << SYNTHEOF
Original task: $TASK_SUMMARY

=== MODELER OUTPUT ===
$RESULT_1

=== ANALYST OUTPUT ===
$RESULT_2

=== ADVISOR OUTPUT ===
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
Specialists: Modeler(deepseek) + Analyst(gpt-4o) + Advisor(gpt-4o-mini)
Additional teams:
- analyst: market data to validate revenue assumptions
- marketing: CAC estimates per channel
- legal: financial regulatory requirements (accounting standards, tax)
- risk: financial risk scenarios and insurance"

RESULT="${RESULT}${SELF_ASSESSMENT}"

echo "  [${TEAM}/lead] Done" >&2
echo "$RESULT"
