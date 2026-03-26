#!/usr/bin/env bash
# teams/risk/lead.sh — Risk Team Lead (3 specialists in parallel)
# Specialists: identifier (gpt-4o) + assessor (deepseek) + mitigator (gpt-4o-mini)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$SCRIPT_DIR/../.."

source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"

CALL_MODEL="${AGENTS2_DIR}/call_model.sh"
TEAM="risk"
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

(echo "$RAW_TASK" | TEAM_MEMORY="$TEAM_MEMORY" "$PE_SCRIPT" "identifier" 2>/dev/null > "$PE_1" || echo "$RAW_TASK" > "$PE_1") &
PID_PE_1=$!
(echo "$RAW_TASK" | TEAM_MEMORY="$TEAM_MEMORY" "$PE_SCRIPT" "assessor" 2>/dev/null > "$PE_2" || echo "$RAW_TASK" > "$PE_2") &
PID_PE_2=$!
(echo "$RAW_TASK" | TEAM_MEMORY="$TEAM_MEMORY" "$PE_SCRIPT" "mitigator" 2>/dev/null > "$PE_3" || echo "$RAW_TASK" > "$PE_3") &
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
Chief Risk Officer with 28 years at financial institutions and tech companies. Your job: find EVERY risk, miss nothing. Brainstorm risks across all categories — (1) Strategic (wrong market, wrong timing, wrong team), (2) Financial (cash flow, pricing, funding), (3) Operational (process failures, key person dependency, supplier risk), (4) Technical (security breaches, system failures, technical debt), (5) Legal/Regulatory (compliance failures, IP disputes, contract risks), (6) Reputational (PR crises, customer trust), (7) Market (competition, market shift, economic downturn), (8) External (geopolitical, regulatory change, force majeure). List minimum 20 risks. No filtering — quantity over quality at this stage.
HEREDOC

SP2_FILE=$(mktemp)
cat > "$SP2_FILE" << 'HEREDOC'
Risk Assessment Specialist (FRM, CRISC certified) with 20 years building risk frameworks for banks and Fortune 500 companies. Score each identified risk: Probability (1=rare, 5=almost certain), Impact (1=negligible, 5=existential), Risk Score (P times I, max 25), Time Horizon (immediate <3m / short 3-12m / medium 1-3yr / long 3yr+), Velocity (how fast does it escalate?), Current Controls (what is already in place to manage it?). Flag as CRITICAL if score >= 15. Flag as EXISTENTIAL if it could kill the project entirely regardless of score. Present as a risk register table.
HEREDOC

SP3_FILE=$(mktemp)
cat > "$SP3_FILE" << 'HEREDOC'
Business Continuity and Risk Mitigation Expert with 18 years. For each CRITICAL and HIGH risk: (1) Prevention — specific actions to reduce probability (with owner and deadline), (2) Response Plan — what to do when it materializes, (3) Early Warning Indicators — specific measurable signals that the risk is becoming real, (4) Residual Risk — risk score after mitigation is in place, (5) Cost of mitigation (time and money estimate). Prioritize by risk score. Include a BCP (Business Continuity Plan) for top 3 existential risks.
HEREDOC

{ SYSTEM_PROMPT="$(cat "$SP1_FILE")" "$CALL_MODEL" "openai/gpt-4o" < "$WORK_DIR/p1.txt" > "$WORK_DIR/r1.txt" 2>/dev/null || printf '[identifier failed]' > "$WORK_DIR/r1.txt"; } &
PID_1=$!
{ SYSTEM_PROMPT="$(cat "$SP2_FILE")" "$CALL_MODEL" "deepseek/deepseek-chat" < "$WORK_DIR/p2.txt" > "$WORK_DIR/r2.txt" 2>/dev/null || printf '[assessor failed]' > "$WORK_DIR/r2.txt"; } &
PID_2=$!
{ SYSTEM_PROMPT="$(cat "$SP3_FILE")" "$CALL_MODEL" "openai/gpt-4o-mini" < "$WORK_DIR/p3.txt" > "$WORK_DIR/r3.txt" 2>/dev/null || printf '[mitigator failed]' > "$WORK_DIR/r3.txt"; } &
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
You are the Chief Risk Officer presenting to the Board. Combine: Risk Identification, Risk Assessment, and Mitigation Planning. Produce the Enterprise Risk Report: (1) Executive Risk Dashboard (overall risk level: RED/AMBER/GREEN, top 5 risks), (2) Complete Risk Register (all risks scored and prioritized), (3) Top 3 Existential Risks with full BCP, (4) Risk Mitigation Roadmap (next 90 days, which risks to tackle first), (5) Key Risk Indicators to monitor monthly. Designed for executive decision-making.
HEREDOC

SYNTH_PROMPT=$(mktemp)
cat > "$SYNTH_PROMPT" << SYNTHEOF
Original task: $TASK_SUMMARY

=== IDENTIFIER OUTPUT ===
$RESULT_1

=== ASSESSOR OUTPUT ===
$RESULT_2

=== MITIGATOR OUTPUT ===
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
Specialists: Identifier(gpt-4o) + Assessor(deepseek) + Mitigator(gpt-4o-mini)
Additional teams:
- legal: regulatory and compliance risk details
- finance: financial risk quantification and insurance options
- security: cybersecurity risk technical details
- devops: infrastructure reliability and disaster recovery"

RESULT="${RESULT}${SELF_ASSESSMENT}"

echo "  [${TEAM}/lead] Done" >&2
echo "$RESULT"
