#!/usr/bin/env bash
# teams/strategy/lead.sh — Strategy Team Lead (3 specialists in parallel)
# Specialists: researcher (deepseek) + strategist (gpt-4o) + critic (gpt-4o-mini)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$SCRIPT_DIR/../.."

source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"

CALL_MODEL="${AGENTS2_DIR}/call_model.sh"
TEAM="strategy"
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

PE_R=$(mktemp); PE_S=$(mktemp); PE_C=$(mktemp)
trap 'rm -f "$TMPFILE" "$PE_R" "$PE_S" "$PE_C"' EXIT

(echo "$RAW_TASK" | TEAM_MEMORY="$TEAM_MEMORY" "$PE_SCRIPT" "researcher" 2>/dev/null > "$PE_R" || echo "$RAW_TASK" > "$PE_R") &
PID_PE_R=$!
(echo "$RAW_TASK" | TEAM_MEMORY="$TEAM_MEMORY" "$PE_SCRIPT" "strategist" 2>/dev/null > "$PE_S" || echo "$RAW_TASK" > "$PE_S") &
PID_PE_S=$!
(echo "$RAW_TASK" | TEAM_MEMORY="$TEAM_MEMORY" "$PE_SCRIPT" "critic" 2>/dev/null > "$PE_C" || echo "$RAW_TASK" > "$PE_C") &
PID_PE_C=$!

wait "$PID_PE_R" "$PID_PE_S" "$PID_PE_C"

PROMPT_R=$(cat "$PE_R")
PROMPT_S=$(cat "$PE_S")
PROMPT_C=$(cat "$PE_C")

# ── Step 2: Run 3 agents in parallel with system prompts via temp files ───────
echo "  🤖 [$TEAM/lead] Running 3 specialists in parallel..." >&2

OUT_R=$(mktemp); OUT_S=$(mktemp); OUT_C=$(mktemp)
SYS_R=$(mktemp); SYS_S=$(mktemp); SYS_C=$(mktemp)
trap 'rm -f "$TMPFILE" "$PE_R" "$PE_S" "$PE_C" "$OUT_R" "$OUT_S" "$OUT_C" "$SYS_R" "$SYS_S" "$SYS_C"' EXIT

printf '%s' "You are a Competitive Intelligence Analyst with 18 years at Forrester and McKinsey. Map the strategic landscape: identify top 5 direct and indirect competitors (features, pricing, positioning, strengths, weaknesses), market trends and timing (is the market growing? is timing right?), what customers love and hate about existing solutions (based on reviews/patterns), and comparable company GTM trajectories. Include specific numbers where possible." > "$SYS_R"

printf '%s' "You are a Senior Strategy Consultant (ex-BCG Partner) with 25 years advising startups from seed to IPO. Build the strategic recommendation: (1) Market opportunity summary, (2) Positioning statement (for [target customer] who [has problem], [product] is [category] that [differentiation], unlike [alternative]), (3) GTM strategy (beachhead customer, acquisition motion, land-and-expand or direct sales), (4) Pricing strategy with rationale, (5) Key strategic bets for 90 days and 12 months, (6) 3 partnerships that would accelerate growth. Be direct and opinionated." > "$SYS_S"

printf '%s' "You are a Devil's Advocate investor who has seen 1,000 startup pitches and watched 800 of them fail. Your role: find every flaw in the strategy. Challenge: what assumption is most likely wrong? why will customers not pay for this? what does a well-funded competitor do in response? what market conditions (recession, regulation change, platform shift) would kill this? what has this strategy failed to consider? Give probability estimates for each failure mode (e.g., 40% chance customers won't pay this price)." > "$SYS_C"

(SYSTEM_PROMPT="$(cat "$SYS_R")" printf '%s' "$PROMPT_R" | "$CALL_MODEL" "deepseek/deepseek-chat" 2>/dev/null > "$OUT_R" || echo "[researcher failed]" > "$OUT_R") &
PID_R=$!
(SYSTEM_PROMPT="$(cat "$SYS_S")" printf '%s' "$PROMPT_S" | "$CALL_MODEL" "openai/gpt-4o" 2>/dev/null > "$OUT_S" || echo "[strategist failed]" > "$OUT_S") &
PID_S=$!
(SYSTEM_PROMPT="$(cat "$SYS_C")" printf '%s' "$PROMPT_C" | "$CALL_MODEL" "openai/gpt-4o-mini" 2>/dev/null > "$OUT_C" || echo "[critic failed]" > "$OUT_C") &
PID_C=$!

wait "$PID_R" "$PID_S" "$PID_C"

RESULT_R=$(cat "$OUT_R")
RESULT_S=$(cat "$OUT_S")
RESULT_C=$(cat "$OUT_C")

echo "  ✅ [$TEAM/lead] Specialists done. Synthesizing..." >&2

# ── Step 3: Synthesize with gpt-4o ───────────────────────────────────────────
SYNTH_SYS=$(mktemp)
SYNTH_PROMPT=$(mktemp)
trap 'rm -f "$TMPFILE" "$PE_R" "$PE_S" "$PE_C" "$OUT_R" "$OUT_S" "$OUT_C" "$SYS_R" "$SYS_S" "$SYS_C" "$SYNTH_SYS" "$SYNTH_PROMPT"' EXIT

printf '%s' "You are the Chief Strategy Officer. Integrate: Competitive Research, Strategic Recommendation, and Critical Challenge. Produce: (1) Competitive landscape summary, (2) Recommended strategy with full justification, (3) Refined strategy that addresses the critic's top concerns (update the strategy, don't just list concerns), (4) Risk-adjusted action plan (90 days), (5) Key assumptions to validate before committing. The output is a strategic brief for the founding team." > "$SYNTH_SYS"

cat > "$SYNTH_PROMPT" <<SYNTHEOF
Original task: $TASK_SUMMARY

=== RESEARCHER OUTPUT ===
$RESULT_R

=== STRATEGIST OUTPUT ===
$RESULT_S

=== CRITIC OUTPUT ===
$RESULT_C
SYNTHEOF

RESULT=$(SYSTEM_PROMPT="$(cat "$SYNTH_SYS")" "$CALL_MODEL" "openai/gpt-4o" < "$SYNTH_PROMPT" 2>/dev/null) || RESULT=""

if [ -z "$RESULT" ]; then
    RESULT="$RESULT_R

---

$RESULT_S

---

$RESULT_C"
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
**Specialists used:** Researcher(deepseek) + Strategist(gpt-4o) + Critic(gpt-4o-mini)
**What may need additional teams:**
- marketing: detailed GTM execution (channels, messaging, campaigns)
- finance: financial modeling of the strategy (revenue projections, required investment)
- legal: regulatory constraints on the strategy
- analyst: quantitative backing for strategic assumptions"

RESULT="${RESULT}${SELF_ASSESSMENT}"

echo "  ✅ [$TEAM/lead] Done" >&2
echo "$RESULT"
