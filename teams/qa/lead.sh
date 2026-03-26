#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"

TEAM="qa"
ROLE1_NAME="analyst"
ROLE2_NAME="writer"
ROLE3_NAME="reviewer"
AGENT1_MODEL="deepseek/deepseek-chat"
AGENT2_MODEL="openai/gpt-4o-mini"
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
echo "🔧 [$TEAM] Starting 3-parallel: ${TASK_SUMMARY:0:60}..." >&2

{ echo "$RAW_TASK" | bash "$SCRIPT_DIR/prompt_engineer.sh" "$ROLE1_NAME" > "$WORK_DIR/p1.txt" 2>/dev/null || cp "$TMPFILE" "$WORK_DIR/p1.txt"; } &
{ echo "$RAW_TASK" | bash "$SCRIPT_DIR/prompt_engineer.sh" "$ROLE2_NAME" > "$WORK_DIR/p2.txt" 2>/dev/null || cp "$TMPFILE" "$WORK_DIR/p2.txt"; } &
{ echo "$RAW_TASK" | bash "$SCRIPT_DIR/prompt_engineer.sh" "$ROLE3_NAME" > "$WORK_DIR/p3.txt" 2>/dev/null || cp "$TMPFILE" "$WORK_DIR/p3.txt"; } &
wait

echo "  🤖 [$TEAM] $ROLE1_NAME+$ROLE2_NAME+$ROLE3_NAME running..." >&2

SP1_FILE=$(mktemp)
SP2_FILE=$(mktemp)
SP3_FILE=$(mktemp)
SYNTH_FILE=$(mktemp)
trap 'rm -f "$TMPFILE" "$SP1_FILE" "$SP2_FILE" "$SP3_FILE" "$SYNTH_FILE"; rm -rf "$WORK_DIR"' EXIT

printf '%s' 'You are a Senior QA Analyst and Test Strategist with 22 years of experience. Your role: identify EVERY test scenario, not just the happy path. Think like a user trying to break the system. Enumerate: (1) happy path scenarios, (2) boundary value tests (off-by-one, max/min values), (3) empty/null/undefined inputs, (4) race conditions and concurrent access, (5) network failure scenarios, (6) permission/auth edge cases, (7) data type edge cases. Output: structured list of test scenarios grouped by priority (P0/P1/P2) with acceptance criteria for each.' > "$SP1_FILE"

printf '%s' 'You are a Test Automation Engineer with 15 years of experience. Write complete, runnable tests based on the test scenarios. Requirements: use appropriate framework for the context (Jest for JS, pytest for Python, etc.), all external dependencies mocked, clear test names that describe the scenario in plain English, strict arrange/act/assert structure, no flaky timing dependencies, complete file with all imports — copy-paste ready.' > "$SP2_FILE"

printf '%s' 'You are a QA Quality Reviewer. Check the test scenarios and code for: gaps (missing important scenarios), weak assertions (assertTrue(result) instead of assertEqual(result, expected)), shared mutable state between tests, hardcoded test data that should be parameterized, missing async handling, tests that test implementation instead of behavior. Format: [MISSING/WEAK/FLAKY/OK] | Scenario | Issue | Recommendation.' > "$SP3_FILE"

printf '%s' 'You are the QA Team Lead integrating: Test Strategy (from Analyst), Test Implementation (from Writer), and Quality Review (from Reviewer). Deliver: (1) Final test plan with all scenarios, (2) Complete test code with all gaps filled and reviewer fixes applied, (3) Coverage summary (what is and is not covered). All MISSING scenarios from reviewer must be added to the test code.' > "$SYNTH_FILE"

{
  SYSTEM_PROMPT="$(cat "$SP1_FILE")" "$AGENTS2_DIR/call_model.sh" "$AGENT1_MODEL" < "$WORK_DIR/p1.txt" > "$WORK_DIR/r1.txt" 2>/dev/null \
    || printf '[%s/%s failed]' "$TEAM" "$ROLE1_NAME" > "$WORK_DIR/r1.txt"
} &
{
  SYSTEM_PROMPT="$(cat "$SP2_FILE")" "$AGENTS2_DIR/call_model.sh" "$AGENT2_MODEL" < "$WORK_DIR/p2.txt" > "$WORK_DIR/r2.txt" 2>/dev/null \
    || printf '[%s/%s failed]' "$TEAM" "$ROLE2_NAME" > "$WORK_DIR/r2.txt"
} &
{
  SYSTEM_PROMPT="$(cat "$SP3_FILE")" "$AGENTS2_DIR/call_model.sh" "$AGENT3_MODEL" < "$WORK_DIR/p3.txt" > "$WORK_DIR/r3.txt" 2>/dev/null \
    || printf '[%s/%s failed]' "$TEAM" "$ROLE3_NAME" > "$WORK_DIR/r3.txt"
} &
wait

echo "  ✅ [$TEAM] Agents done, synthesizing..." >&2

COMBINED="## [$ROLE1_NAME — $AGENT1_MODEL]
$(cat "$WORK_DIR/r1.txt")

## [$ROLE2_NAME — $AGENT2_MODEL]
$(cat "$WORK_DIR/r2.txt")

## [$ROLE3_NAME — $AGENT3_MODEL]
$(cat "$WORK_DIR/r3.txt")"

RESULT=$(printf '%s' "$COMBINED" | SYSTEM_PROMPT="$(cat "$SYNTH_FILE")" "$AGENTS2_DIR/call_model.sh" "openai/gpt-4o" 2>/dev/null) || RESULT="$COMBINED"
[ -z "$RESULT" ] && RESULT="$COMBINED"

memory_append "$TEAM" "$(date '+%Y-%m-%d'): ${TASK_SUMMARY:0:80}"
log_action "$TEAM" "lead" "3-parallel" "SUCCESS" "$TASK_SUMMARY" "$RAW_TASK" "$RESULT"

RESULT="${RESULT}
---
## 🔍 [$TEAM Team] Self-Assessment
Specialists: Analyst(deepseek) + Writer(gpt-4o-mini) + Reviewer(gemini-flash)
Additional teams that could add value:
- backend: understanding the implementation to test edge cases correctly
- security: security-specific test scenarios (injection, auth bypass tests)
- devops: CI/CD integration and test environment setup"

echo "  ✅ [$TEAM] Done" >&2
echo "$RESULT"
