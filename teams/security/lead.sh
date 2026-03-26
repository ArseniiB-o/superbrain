#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"

TEAM="security"
ROLE1_NAME="attacker"
ROLE2_NAME="defender"
ROLE3_NAME="auditor"
AGENT1_MODEL="openai/gpt-4o"
AGENT2_MODEL="google/gemini-2.0-flash-001"
AGENT3_MODEL="deepseek/deepseek-chat"

TMPFILE=$(mktemp)
WORK_DIR=$(mktemp -d)
trap 'rm -f "$TMPFILE"; rm -rf "$WORK_DIR"' EXIT

if [ ! -t 0 ]; then
    { [ -n "${1:-}" ] && printf '%s\n\n' "$1"; cat; } > "$TMPFILE"
elif [ -n "${1:-}" ]; then
    printf '%s' "$1" > "$TMPFILE"
else
    echo "Error: provide task via argument or stdin" >&2; exit 1
fi

RAW_TASK=$(cat "$TMPFILE")
TASK_SUMMARY="${RAW_TASK:0:120}"
log_action "$TEAM" "lead" "3-parallel" "RUNNING" "$TASK_SUMMARY" "$RAW_TASK"
echo "🔧 [$TEAM] Starting: ${TASK_SUMMARY:0:60}..." >&2

# Phase 1: 3 PE calls in parallel
echo "  📝 [$TEAM] Team PE optimizing for $ROLE1_NAME + $ROLE2_NAME + $ROLE3_NAME..." >&2
{ echo "$RAW_TASK" | bash "$SCRIPT_DIR/prompt_engineer.sh" "$ROLE1_NAME" > "$WORK_DIR/p1.txt" 2>/dev/null || cp "$TMPFILE" "$WORK_DIR/p1.txt"; } &
{ echo "$RAW_TASK" | bash "$SCRIPT_DIR/prompt_engineer.sh" "$ROLE2_NAME" > "$WORK_DIR/p2.txt" 2>/dev/null || cp "$TMPFILE" "$WORK_DIR/p2.txt"; } &
{ echo "$RAW_TASK" | bash "$SCRIPT_DIR/prompt_engineer.sh" "$ROLE3_NAME" > "$WORK_DIR/p3.txt" 2>/dev/null || cp "$TMPFILE" "$WORK_DIR/p3.txt"; } &
wait
echo "  ✅ [$TEAM] Prompts ready" >&2

# Phase 2: 3 agents in parallel
echo "  🤖 [$TEAM] $ROLE1_NAME($AGENT1_MODEL) + $ROLE2_NAME($AGENT2_MODEL) + $ROLE3_NAME($AGENT3_MODEL)..." >&2

AGENT1_SYSPROMPT='You are a Senior Penetration Tester with 25 years of experience, OSCP and GPEN certified, former NSA red team contractor. Your ONLY job: find every vulnerability like an attacker would. Think adversarially. Check: all OWASP Top 10 attack categories, business logic flaws, authentication bypass, privilege escalation paths, data exfiltration routes, denial-of-service vectors. For each vulnerability: Name, Attack Vector (step-by-step), Proof of Concept, CVSS 3.1 Score, Affected Components. Be exhaustive — a missed vulnerability in production is a breach.'

AGENT2_SYSPROMPT='You are a Security Engineer specializing in remediation and hardening with 20 years of experience. For each vulnerability identified: provide the EXACT code fix (not general advice), the specific configuration change, security headers to add (with exact values), monitoring rules to detect exploitation, and estimated effort to fix (hours). Prioritize CRITICAL issues first. Never give vague advice — always provide specific, copy-paste-ready fixes.'

AGENT3_SYSPROMPT='You are a Security Compliance Auditor. Systematically check compliance against: OWASP Top 10 2021 (A01-A10), GDPR technical requirements (encryption at rest/transit, data minimization, right to erasure), secure coding standards (input validation, output encoding, error handling). For each item: status (COMPLIANT/NON-COMPLIANT/PARTIAL), evidence or reason, and remediation if non-compliant. Produce a structured compliance checklist.'

SYNTH_SYSPROMPT='You are the CISO reviewing outputs from Penetration Tester (attack findings), Security Engineer (remediations), and Compliance Auditor (standards check). Produce the final security audit report: (1) Executive Risk Summary (overall rating: CRITICAL/HIGH/MEDIUM/LOW), (2) Vulnerability Register sorted by severity with remediation steps, (3) Compliance Status Dashboard, (4) Top 5 Immediate Actions (what to fix TODAY). This report will be reviewed by executives and developers.'

{
SYSTEM_PROMPT="$AGENT1_SYSPROMPT" \
"$AGENTS2_DIR/call_model.sh" "$AGENT1_MODEL" < "$WORK_DIR/p1.txt" > "$WORK_DIR/r1.txt" 2>/dev/null \
    || printf '[%s/%s failed]\n' "$TEAM" "$ROLE1_NAME" > "$WORK_DIR/r1.txt"
} &
{
SYSTEM_PROMPT="$AGENT2_SYSPROMPT" \
"$AGENTS2_DIR/call_model.sh" "$AGENT2_MODEL" < "$WORK_DIR/p2.txt" > "$WORK_DIR/r2.txt" 2>/dev/null \
    || printf '[%s/%s failed]\n' "$TEAM" "$ROLE2_NAME" > "$WORK_DIR/r2.txt"
} &
{
SYSTEM_PROMPT="$AGENT3_SYSPROMPT" \
"$AGENTS2_DIR/call_model.sh" "$AGENT3_MODEL" < "$WORK_DIR/p3.txt" > "$WORK_DIR/r3.txt" 2>/dev/null \
    || printf '[%s/%s failed]\n' "$TEAM" "$ROLE3_NAME" > "$WORK_DIR/r3.txt"
} &
wait
echo "  ✅ [$TEAM] All 3 done" >&2

# Phase 3: Team synthesis
COMBINED="## [$ROLE1_NAME — $AGENT1_MODEL]
$(cat "$WORK_DIR/r1.txt")

## [$ROLE2_NAME — $AGENT2_MODEL]
$(cat "$WORK_DIR/r2.txt")

## [$ROLE3_NAME — $AGENT3_MODEL]
$(cat "$WORK_DIR/r3.txt")"

echo "  🔗 [$TEAM] Synthesizing..." >&2
RESULT=$(printf '%s' "$COMBINED" | \
SYSTEM_PROMPT="$SYNTH_SYSPROMPT" \
"$AGENTS2_DIR/call_model.sh" "openai/gpt-4o" 2>/dev/null) || RESULT="$COMBINED"

[ -z "$RESULT" ] && RESULT="$COMBINED"

memory_append "$TEAM" "$(date '+%Y-%m-%d'): ${TASK_SUMMARY:0:80}"
log_action "$TEAM" "lead" "3-parallel" "SUCCESS" "$TASK_SUMMARY" "$RAW_TASK" "$RESULT"

RESULT="${RESULT}
---
## 🔍 [$TEAM Team] Self-Assessment
Specialists: Attacker/Red-Team(gpt-4o) + Defender/Blue-Team(gemini-flash) + Compliance-Auditor(deepseek)
Additional teams:
- legal: regulatory and liability implications of security findings
- devops: infrastructure-level hardening implementation
- backend: application code fixes implementation
- risk: quantified business risk assessment of identified vulnerabilities"

echo "  ✅ [$TEAM] Done" >&2
echo "$RESULT"
