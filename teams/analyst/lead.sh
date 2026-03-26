#!/usr/bin/env bash
# teams/analyst/lead.sh — Analyst Team Lead (3 specialists in parallel)
# Specialists: researcher (deepseek) + analyst (deepseek) + advisor (gpt-4o-mini)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$SCRIPT_DIR/../.."

source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"

CALL_MODEL="${AGENTS2_DIR}/call_model.sh"
TEAM="analyst"
PE_SCRIPT="$SCRIPT_DIR/prompt_engineer.sh"

# ── Read task ─────────────────────────────────────────────────────────────────
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
echo "🔧 [$TEAM/lead] Starting: ${TASK_SUMMARY:0:70}..." >&2

TEAM_MEMORY=$(memory_read "$TEAM")

# ── Step 1: 3 PE calls in parallel ───────────────────────────────────────────
echo "  📝 [$TEAM/lead] Optimizing prompts (3 specialists in parallel)..." >&2

PE_R=$(mktemp); PE_A=$(mktemp); PE_V=$(mktemp)
trap 'rm -f "$TMPFILE" "$PE_R" "$PE_A" "$PE_V"' EXIT

(echo "$RAW_TASK" | TEAM_MEMORY="$TEAM_MEMORY" "$PE_SCRIPT" "researcher" 2>/dev/null > "$PE_R" || echo "$RAW_TASK" > "$PE_R") &
PID_PE_R=$!
(echo "$RAW_TASK" | TEAM_MEMORY="$TEAM_MEMORY" "$PE_SCRIPT" "analyst" 2>/dev/null > "$PE_A" || echo "$RAW_TASK" > "$PE_A") &
PID_PE_A=$!
(echo "$RAW_TASK" | TEAM_MEMORY="$TEAM_MEMORY" "$PE_SCRIPT" "advisor" 2>/dev/null > "$PE_V" || echo "$RAW_TASK" > "$PE_V") &
PID_PE_V=$!

wait "$PID_PE_R" "$PID_PE_A" "$PID_PE_V"

PROMPT_R=$(cat "$PE_R")
PROMPT_A=$(cat "$PE_A")
PROMPT_V=$(cat "$PE_V")

# ── Step 2: Run 3 agents in parallel with system prompts via temp files ───────
echo "  🤖 [$TEAM/lead] Running 3 specialists in parallel..." >&2

OUT_R=$(mktemp); OUT_A=$(mktemp); OUT_V=$(mktemp)
SYS_R=$(mktemp); SYS_A=$(mktemp); SYS_V=$(mktemp)
trap 'rm -f "$TMPFILE" "$PE_R" "$PE_A" "$PE_V" "$OUT_R" "$OUT_A" "$OUT_V" "$SYS_R" "$SYS_A" "$SYS_V"' EXIT

printf '%s' "You are a Senior Research Analyst with 20 years at Gartner and McKinsey Global Institute. Your role: gather all relevant facts, data, and context. Find: industry benchmarks, relevant statistics with sources, comparable company examples, market size estimates, trend data. Always cite where data comes from. Flag data older than 2 years. If precise numbers unavailable, provide a researched range with reasoning." > "$SYS_R"

printf '%s' "You are a Senior Data and Business Analyst with 18 years at Google and Stripe. Your role: interpret the research data and extract insights. Structure your analysis: (1) Situation — what's happening, (2) Complication — what's wrong or what's the challenge, (3) Key Question — what decision needs to be made, (4) Insights — what the data tells us (with numbers), (5) So What — why it matters. Every claim must reference a specific number or fact." > "$SYS_A"

printf '%s' "You are a Senior Business Advisor (ex-McKinsey Partner) with 22 years advising companies. Your role: convert analysis into specific, actionable recommendations. For each recommendation: (1) Action — exactly what to do, (2) Evidence — the specific insight that supports it, (3) Priority — P0 (do now) / P1 (this month) / P2 (this quarter), (4) Expected outcome — which metric improves and by how much. Maximum 5 recommendations, ranked by impact." > "$SYS_V"

(SYSTEM_PROMPT="$(cat "$SYS_R")" printf '%s' "$PROMPT_R" | "$CALL_MODEL" "deepseek/deepseek-chat" 2>/dev/null > "$OUT_R" || echo "[researcher failed]" > "$OUT_R") &
PID_R=$!
(SYSTEM_PROMPT="$(cat "$SYS_A")" printf '%s' "$PROMPT_A" | "$CALL_MODEL" "deepseek/deepseek-chat" 2>/dev/null > "$OUT_A" || echo "[analyst failed]" > "$OUT_A") &
PID_A=$!
(SYSTEM_PROMPT="$(cat "$SYS_V")" printf '%s' "$PROMPT_V" | "$CALL_MODEL" "openai/gpt-4o-mini" 2>/dev/null > "$OUT_V" || echo "[advisor failed]" > "$OUT_V") &
PID_V=$!

wait "$PID_R" "$PID_A" "$PID_V"

RESULT_R=$(cat "$OUT_R")
RESULT_A=$(cat "$OUT_A")
RESULT_V=$(cat "$OUT_V")

echo "  ✅ [$TEAM/lead] Specialists done. Synthesizing..." >&2

# ── Step 3: Synthesize with gpt-4o ───────────────────────────────────────────
SYNTH_SYS=$(mktemp)
SYNTH_PROMPT=$(mktemp)
trap 'rm -f "$TMPFILE" "$PE_R" "$PE_A" "$PE_V" "$OUT_R" "$OUT_A" "$OUT_V" "$SYS_R" "$SYS_A" "$SYS_V" "$SYNTH_SYS" "$SYNTH_PROMPT"' EXIT

printf '%s' "You are the Analytics Team Lead. Combine outputs from: Researcher (data gathering), Analyst (interpretation), and Advisor (recommendations). Produce a structured business analysis report: (1) Executive Summary (3 bullet points max), (2) Key Findings with supporting data, (3) Root Cause Analysis, (4) Prioritized Recommendations (P0/P1/P2 with expected outcomes), (5) Metrics to track progress. Format for executive readability." > "$SYNTH_SYS"

cat > "$SYNTH_PROMPT" <<SYNTHEOF
Original task: $TASK_SUMMARY

=== RESEARCHER OUTPUT ===
$RESULT_R

=== ANALYST OUTPUT ===
$RESULT_A

=== ADVISOR OUTPUT ===
$RESULT_V
SYNTHEOF

RESULT=$(SYSTEM_PROMPT="$(cat "$SYNTH_SYS")" "$CALL_MODEL" "openai/gpt-4o" < "$SYNTH_PROMPT" 2>/dev/null) || RESULT=""

if [ -z "$RESULT" ]; then
    RESULT="$RESULT_R

---

$RESULT_A

---

$RESULT_V"
fi

# ── Step 4: memory_append + log_action ───────────────────────────────────────
LEARNING="$(date '+%Y-%m-%d'): ${TASK_SUMMARY:0:80}"
memory_append "$TEAM" "$LEARNING"

log_action "$TEAM" "lead" "orchestrator" "SUCCESS" "$TASK_SUMMARY" "$RAW_TASK" "$RESULT"

# ── Step 5: Self-assessment ───────────────────────────────────────────────────
SELF_ASSESSMENT="

---
## 🔍 [$TEAM Team] Self-Assessment
**What I covered:** ${TASK_SUMMARY:0:60}
**Specialists used:** Researcher(deepseek) + Analyst(deepseek) + Advisor(gpt-4o-mini)
**What may need additional teams:**
- researcher: real-time market data and primary source research
- finance: financial modeling and unit economics calculations
- strategy: strategic implications and competitive response
- marketing: market sizing and customer acquisition analysis"

RESULT="${RESULT}${SELF_ASSESSMENT}"

echo "  ✅ [$TEAM/lead] Done" >&2
echo "$RESULT"
