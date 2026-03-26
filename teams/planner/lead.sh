#!/usr/bin/env bash
# teams/planner/lead.sh — Planner Team Lead (3 specialists in parallel)
# Specialists: analyst (deepseek) + planner (gpt-4o-mini) + risk-officer (gpt-4o-mini)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$SCRIPT_DIR/../.."

source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"

CALL_MODEL="${AGENTS2_DIR}/call_model.sh"
TEAM="planner"
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

PE_A=$(mktemp); PE_P=$(mktemp); PE_RO=$(mktemp)
trap 'rm -f "$TMPFILE" "$PE_A" "$PE_P" "$PE_RO"' EXIT

(echo "$RAW_TASK" | TEAM_MEMORY="$TEAM_MEMORY" "$PE_SCRIPT" "analyst" 2>/dev/null > "$PE_A" || echo "$RAW_TASK" > "$PE_A") &
PID_PE_A=$!
(echo "$RAW_TASK" | TEAM_MEMORY="$TEAM_MEMORY" "$PE_SCRIPT" "planner" 2>/dev/null > "$PE_P" || echo "$RAW_TASK" > "$PE_P") &
PID_PE_P=$!
(echo "$RAW_TASK" | TEAM_MEMORY="$TEAM_MEMORY" "$PE_SCRIPT" "risk-officer" 2>/dev/null > "$PE_RO" || echo "$RAW_TASK" > "$PE_RO") &
PID_PE_RO=$!

wait "$PID_PE_A" "$PID_PE_P" "$PID_PE_RO"

PROMPT_A=$(cat "$PE_A")
PROMPT_P=$(cat "$PE_P")
PROMPT_RO=$(cat "$PE_RO")

# ── Step 2: Run 3 agents in parallel with system prompts via temp files ───────
echo "  🤖 [$TEAM/lead] Running 3 specialists in parallel..." >&2

OUT_A=$(mktemp); OUT_P=$(mktemp); OUT_RO=$(mktemp)
SYS_A=$(mktemp); SYS_P=$(mktemp); SYS_RO=$(mktemp)
trap 'rm -f "$TMPFILE" "$PE_A" "$PE_P" "$PE_RO" "$OUT_A" "$OUT_P" "$OUT_RO" "$SYS_A" "$SYS_P" "$SYS_RO"' EXIT

printf '%s' "You are a Senior Business Analyst with 20 years experience. Analyze the project scope: (1) Break down into work packages (2-5 day chunks), (2) Map dependencies (what must finish before what starts), (3) Estimate effort (S=1-2d, M=3-5d, L=1-2w, XL=2-4w), (4) Identify skills required for each package, (5) Flag all ambiguities and missing information that must be resolved before planning. Produce a work breakdown structure (WBS)." > "$SYS_A"

printf '%s' "You are a Senior Program Manager with 25 years at Amazon and Microsoft, having delivered 50+ major projects. Build the project plan: (1) Timeline with phases and milestones (with dates relative to start), (2) Critical path highlighted, (3) Sprint/iteration breakdown with goals for each sprint, (4) Resource allocation plan, (5) Definition of Done for each major deliverable, (6) Communication plan (who gets what update when). Add 30% time buffer to all estimates — things always take longer." > "$SYS_P"

printf '%s' "You are a Project Risk Manager (PMP, PMI-RMP certified) with 22 years experience. Identify and assess all project risks. For each risk: Name, Category (scope/schedule/resource/technical/external), Probability (1-5), Impact (1-5), Risk Score (P x I), Owner (who is responsible), Mitigation (how to reduce probability), Contingency (what to do if it happens), Early Warning Signal (how to detect it early). Identify the top 3 existential risks that could kill the project." > "$SYS_RO"

(SYSTEM_PROMPT="$(cat "$SYS_A")" printf '%s' "$PROMPT_A" | "$CALL_MODEL" "deepseek/deepseek-chat" 2>/dev/null > "$OUT_A" || echo "[analyst failed]" > "$OUT_A") &
PID_A=$!
(SYSTEM_PROMPT="$(cat "$SYS_P")" printf '%s' "$PROMPT_P" | "$CALL_MODEL" "openai/gpt-4o-mini" 2>/dev/null > "$OUT_P" || echo "[planner failed]" > "$OUT_P") &
PID_P=$!
(SYSTEM_PROMPT="$(cat "$SYS_RO")" printf '%s' "$PROMPT_RO" | "$CALL_MODEL" "openai/gpt-4o-mini" 2>/dev/null > "$OUT_RO" || echo "[risk-officer failed]" > "$OUT_RO") &
PID_RO=$!

wait "$PID_A" "$PID_P" "$PID_RO"

RESULT_A=$(cat "$OUT_A")
RESULT_P=$(cat "$OUT_P")
RESULT_RO=$(cat "$OUT_RO")

echo "  ✅ [$TEAM/lead] Specialists done. Synthesizing..." >&2

# ── Step 3: Synthesize with gpt-4o ───────────────────────────────────────────
SYNTH_SYS=$(mktemp)
SYNTH_PROMPT=$(mktemp)
trap 'rm -f "$TMPFILE" "$PE_A" "$PE_P" "$PE_RO" "$OUT_A" "$OUT_P" "$OUT_RO" "$SYS_A" "$SYS_P" "$SYS_RO" "$SYNTH_SYS" "$SYNTH_PROMPT"' EXIT

printf '%s' "You are the Head of PMO. Integrate: Scope Analysis (WBS), Project Plan (timeline, milestones), and Risk Register. Deliver the complete Project Charter: (1) Executive summary (scope, timeline, budget range), (2) Work breakdown structure, (3) Project timeline with milestones and critical path, (4) Risk register with top risks highlighted, (5) Next 2 weeks action items (what starts immediately). Format for stakeholder presentation." > "$SYNTH_SYS"

cat > "$SYNTH_PROMPT" <<SYNTHEOF
Original task: $TASK_SUMMARY

=== SCOPE ANALYSIS (WBS) ===
$RESULT_A

=== PROJECT PLAN ===
$RESULT_P

=== RISK REGISTER ===
$RESULT_RO
SYNTHEOF

RESULT=$(SYSTEM_PROMPT="$(cat "$SYNTH_SYS")" "$CALL_MODEL" "openai/gpt-4o" < "$SYNTH_PROMPT" 2>/dev/null) || RESULT=""

if [ -z "$RESULT" ]; then
    RESULT="$RESULT_A

---

$RESULT_P

---

$RESULT_RO"
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
**Specialists used:** Analyst(deepseek) + Planner(gpt-4o-mini) + Risk-Officer(gpt-4o-mini)
**What may need additional teams:**
- finance: budget modeling and financial projections
- risk: deeper enterprise risk assessment
- devops: technical infrastructure timeline and dependencies
- security: security review timeline and compliance milestones"

RESULT="${RESULT}${SELF_ASSESSMENT}"

echo "  ✅ [$TEAM/lead] Done" >&2
echo "$RESULT"
