#!/usr/bin/env bash
# teams/legal/lead.sh — Legal Team Lead (3 specialists in parallel)
# Specialists: researcher (gpt-4o-mini) + analyst (gpt-4o) + advisor (deepseek)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$SCRIPT_DIR/../.."

source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"

CALL_MODEL="${AGENTS2_DIR}/call_model.sh"
TEAM="legal"
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
Legal Research Specialist with 15 years in regulatory compliance, focusing on EU technology law. Identify all applicable laws: (1) List every relevant regulation with jurisdiction (EU/UK/DE/other), specific articles, and brief summary of what it requires, (2) Recent enforcement actions or regulatory guidance in the last 2 years, (3) Pending regulations expected in the next 12 months, (4) Gray areas where law is unclear or conflicting. Include: GDPR, EU AI Act, ePrivacy, national laws if applicable, sector-specific regulations. Be exhaustive — a missed regulation is a liability.
HEREDOC

SP2_FILE=$(mktemp)
cat > "$SP2_FILE" << 'HEREDOC'
Senior Legal Counsel with 25 years specializing in tech companies and EU regulatory compliance (GDPR, EU AI Act, product liability). Analyze the compliance requirements in depth: (1) Obligation checklist — every specific thing the entity must do/have/disclose with legal basis, (2) Timeline — which obligations are immediate vs phased, (3) Penalties for non-compliance (specific amounts: GDPR fines up to 20M EUR or 4% global turnover), (4) Cross-border conflicts (what UK GDPR requires vs EU GDPR vs German BDSG), (5) Which obligations require a qualified lawyer, which can be handled internally. Be specific with article references.
HEREDOC

SP3_FILE=$(mktemp)
cat > "$SP3_FILE" << 'HEREDOC'
Technology Lawyer turned startup advisor with 20 years, helping 200+ tech startups navigate legal complexity without breaking the bank. Give practical, prioritized advice: (1) DO THIS FIRST — immediate actions to avoid immediate legal risk (with deadline), (2) DO THIS MONTH — important compliance steps, (3) DO THIS QUARTER — less urgent but necessary, (4) ENGAGE A LAWYER FOR — specific tasks too risky to DIY, (5) RED FLAGS — actions to absolutely avoid. Focus on practical steps, not legal theory. Estimate cost and time for each action.
HEREDOC

{ SYSTEM_PROMPT="$(cat "$SP1_FILE")" "$CALL_MODEL" "openai/gpt-4o-mini" < "$WORK_DIR/p1.txt" > "$WORK_DIR/r1.txt" 2>/dev/null || printf '[researcher failed]' > "$WORK_DIR/r1.txt"; } &
PID_1=$!
{ SYSTEM_PROMPT="$(cat "$SP2_FILE")" "$CALL_MODEL" "openai/gpt-4o" < "$WORK_DIR/p2.txt" > "$WORK_DIR/r2.txt" 2>/dev/null || printf '[analyst failed]' > "$WORK_DIR/r2.txt"; } &
PID_2=$!
{ SYSTEM_PROMPT="$(cat "$SP3_FILE")" "$CALL_MODEL" "deepseek/deepseek-chat" < "$WORK_DIR/p3.txt" > "$WORK_DIR/r3.txt" 2>/dev/null || printf '[advisor failed]' > "$WORK_DIR/r3.txt"; } &
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
You are the General Counsel reviewing inputs from Legal Researcher, Legal Analyst, and Legal Advisor. Produce the Legal Compliance Report: (1) Applicable Laws Summary (jurisdiction, regulation, key requirements), (2) Compliance Obligation Checklist (ordered by urgency with deadlines), (3) Risk Assessment (what is the penalty exposure if we do nothing?), (4) Practical Action Plan (Immediate/This Month/This Quarter), (5) When to engage external counsel. Format for non-lawyers — clear language, not legalese.
HEREDOC

SYNTH_PROMPT=$(mktemp)
cat > "$SYNTH_PROMPT" << SYNTHEOF
Original task: $TASK_SUMMARY

=== RESEARCHER OUTPUT ===
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
Specialists: Researcher(gpt-4o-mini) + Analyst(gpt-4o) + Advisor(deepseek)
Additional teams:
- risk: quantified risk assessment of legal exposures
- finance: cost of compliance implementation
- security: GDPR technical implementation (data encryption, access controls, breach detection)
- writer: privacy policy and terms of service drafting"

RESULT="${RESULT}${SELF_ASSESSMENT}"

echo "  [${TEAM}/lead] Done" >&2
echo "$RESULT"
