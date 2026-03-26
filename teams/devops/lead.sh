#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"

TEAM="devops"
ROLE1_NAME="designer"
ROLE2_NAME="implementer"
ROLE3_NAME="reviewer"
AGENT1_MODEL="openai/gpt-4o-mini"
AGENT2_MODEL="deepseek/deepseek-chat"
AGENT3_MODEL="google/gemini-2.0-flash-001"

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

AGENT1_SYSPROMPT='You are a Staff Platform Engineer with 24 years of experience building infrastructure for Netflix (100M+ users) and Meta. Your role: design the infrastructure architecture ONLY. Produce: service diagram (ASCII), environment strategy, secrets management plan, monitoring/alerting design, scaling approach, DR strategy. No implementation files — produce a clear infrastructure design doc.'

AGENT2_SYSPROMPT='You are a Senior DevOps Engineer with 18 years of experience. Implement complete, production-ready infrastructure. Requirements: Docker images use non-root users and pinned versions, CI/CD includes test gates before deploy, Kubernetes configs include resource limits and probes, no secrets in code or configs, rollback strategy defined. Deliver complete, working configuration files.'

AGENT3_SYSPROMPT='You are a DevOps Security Auditor. Review the infrastructure for: secrets exposure (grep for passwords/keys/tokens in configs), over-privileged containers (root user, SYS_ADMIN), missing network segmentation, SPOFs (no redundancy), inadequate monitoring gaps, blast radius of failures. Each finding: [CRITICAL/HIGH/MEDIUM/LOW] | Issue | Location | Risk | Fix.'

SYNTH_SYSPROMPT='You are the DevOps Team Lead. Combine Infrastructure Design, Implementation, and Security Review. Produce: (1) Infrastructure architecture summary, (2) Complete configuration files with security fixes applied, (3) Deployment checklist (ordered steps), (4) Monitoring setup guide. Fix all CRITICAL and HIGH findings before delivering.'

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
Specialists: Designer(gpt-4o-mini) + Implementer(deepseek) + Reviewer(gemini-flash)
Additional teams:
- security: application-level security audit beyond infrastructure
- backend: application configuration and environment variables
- data: database backup and migration strategy"

echo "  ✅ [$TEAM] Done" >&2
echo "$RESULT"
