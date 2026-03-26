#!/usr/bin/env bash
# teams/writer/lead.sh — Writer Team Lead (3 specialists in parallel)
# Specialists: researcher (gpt-4o-mini) + drafter (gpt-4o) + editor (deepseek)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$SCRIPT_DIR/../.."

source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"

CALL_MODEL="${AGENTS2_DIR}/call_model.sh"
TEAM="writer"
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

PE_R=$(mktemp); PE_D=$(mktemp); PE_E=$(mktemp)
trap 'rm -f "$TMPFILE" "$PE_R" "$PE_D" "$PE_E"' EXIT

(echo "$RAW_TASK" | TEAM_MEMORY="$TEAM_MEMORY" "$PE_SCRIPT" "researcher" 2>/dev/null > "$PE_R" || echo "$RAW_TASK" > "$PE_R") &
PID_PE_R=$!
(echo "$RAW_TASK" | TEAM_MEMORY="$TEAM_MEMORY" "$PE_SCRIPT" "drafter" 2>/dev/null > "$PE_D" || echo "$RAW_TASK" > "$PE_D") &
PID_PE_D=$!
(echo "$RAW_TASK" | TEAM_MEMORY="$TEAM_MEMORY" "$PE_SCRIPT" "editor" 2>/dev/null > "$PE_E" || echo "$RAW_TASK" > "$PE_E") &
PID_PE_E=$!

wait "$PID_PE_R" "$PID_PE_D" "$PID_PE_E"

PROMPT_R=$(cat "$PE_R")
PROMPT_D=$(cat "$PE_D")
PROMPT_E=$(cat "$PE_E")

# ── Step 2: researcher and drafter run first (editor needs the draft) ─────────
# Note: researcher and drafter run in parallel, then editor runs with draft context
echo "  🤖 [$TEAM/lead] Running researcher + drafter in parallel..." >&2

OUT_R=$(mktemp); OUT_D=$(mktemp); OUT_E=$(mktemp)
SYS_R=$(mktemp); SYS_D=$(mktemp); SYS_E=$(mktemp)
trap 'rm -f "$TMPFILE" "$PE_R" "$PE_D" "$PE_E" "$OUT_R" "$OUT_D" "$OUT_E" "$SYS_R" "$SYS_D" "$SYS_E"' EXIT

printf '%s' "You are a Content Research Specialist with 15 years of experience. Research the writing task: (1) 5-7 key facts, statistics, or examples to include (with sources), (2) Target audience profile (who is this for, what do they know, what do they want to achieve?), (3) Tone requirements (formal/technical vs conversational vs persuasive), (4) Key messages that must be communicated, (5) What existing content misses that this should provide. Output: research brief for the writer." > "$SYS_R"

printf '%s' "You are a Principal Technical Writer and Copywriter with 20 years at Stripe, Twilio, and AWS developer docs. Write a complete, compelling draft based on the research brief. Requirements: hook first (why should the reader care?), logical structure with clear headers, active voice throughout, concrete examples over abstract statements, sentences under 25 words average, no jargon without explanation, strong close with clear next step. Write the full content — no placeholders." > "$SYS_D"

(SYSTEM_PROMPT="$(cat "$SYS_R")" printf '%s' "$PROMPT_R" | "$CALL_MODEL" "openai/gpt-4o-mini" 2>/dev/null > "$OUT_R" || echo "[researcher failed]" > "$OUT_R") &
PID_R=$!
(SYSTEM_PROMPT="$(cat "$SYS_D")" printf '%s' "$PROMPT_D" | "$CALL_MODEL" "openai/gpt-4o" 2>/dev/null > "$OUT_D" || echo "[drafter failed]" > "$OUT_D") &
PID_D=$!

wait "$PID_R" "$PID_D"

RESULT_R=$(cat "$OUT_R")
RESULT_D=$(cat "$OUT_D")

echo "  🤖 [$TEAM/lead] Running editor on draft..." >&2

printf '%s' "You are a Senior Editor with 18 years at The Economist and Wired. Review and improve the draft. Apply: cut every word that doesn't earn its place, replace passive voice, make abstract claims concrete (add numbers/examples), ensure each paragraph has one clear purpose, verify the opening hooks the reader in the first sentence, ensure the structure serves the reader's goal. Return the fully edited version with a brief list of major changes made." > "$SYS_E"

EDITOR_PROMPT="Research brief:
$RESULT_R

---
Draft to edit:
$RESULT_D

---
Original task: $PROMPT_E"

SYSTEM_PROMPT="$(cat "$SYS_E")" printf '%s' "$EDITOR_PROMPT" | "$CALL_MODEL" "deepseek/deepseek-chat" 2>/dev/null > "$OUT_E" || echo "[editor failed]" > "$OUT_E"

RESULT_E=$(cat "$OUT_E")

echo "  ✅ [$TEAM/lead] Specialists done. Synthesizing..." >&2

# ── Step 3: Synthesize with gpt-4o ───────────────────────────────────────────
SYNTH_SYS=$(mktemp)
SYNTH_PROMPT=$(mktemp)
trap 'rm -f "$TMPFILE" "$PE_R" "$PE_D" "$PE_E" "$OUT_R" "$OUT_D" "$OUT_E" "$SYS_R" "$SYS_D" "$SYS_E" "$SYNTH_SYS" "$SYNTH_PROMPT"' EXIT

printf '%s' "You are the Content Team Lead. Combine: Research Brief, Draft Content, and Edited Version. Deliver the FINAL edited version of the content (use the Editor's improved version), with: (1) Final content (complete, ready to publish), (2) Key sources used, (3) Editor's change summary. The output must be publication-ready." > "$SYNTH_SYS"

cat > "$SYNTH_PROMPT" <<SYNTHEOF
Original task: $TASK_SUMMARY

=== RESEARCH BRIEF ===
$RESULT_R

=== DRAFT ===
$RESULT_D

=== EDITED VERSION ===
$RESULT_E
SYNTHEOF

RESULT=$(SYSTEM_PROMPT="$(cat "$SYNTH_SYS")" "$CALL_MODEL" "openai/gpt-4o" < "$SYNTH_PROMPT" 2>/dev/null) || RESULT=""

if [ -z "$RESULT" ]; then
    RESULT="$RESULT_E"
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
**Specialists used:** Researcher(gpt-4o-mini) + Drafter(gpt-4o) + Editor(deepseek)
**What may need additional teams:**
- analyst: quantitative data to strengthen content claims
- strategy: strategic messaging alignment
- marketing: distribution and channel strategy for the content
- legal: review if content makes product claims or involves compliance"

RESULT="${RESULT}${SELF_ASSESSMENT}"

echo "  ✅ [$TEAM/lead] Done" >&2
echo "$RESULT"
