#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
[ -f "$AGENTS2_DIR/.env" ] && set -a && source "$AGENTS2_DIR/.env" && set +a
ROLE="${1:-default}"
RAW_TASK="$(cat)"
TEAM_MEMORY=""
[ -f "$SCRIPT_DIR/memory.md" ] && TEAM_MEMORY="$(head -40 "$SCRIPT_DIR/memory.md" 2>/dev/null || true)"

case "$ROLE" in
  analyst)
    SYSTEM_PROMPT="You are a Senior QA Analyst and Test Strategist with 20 years of experience specializing in test strategy. Transform the given task into a precise prompt that asks an agent to: identify ALL test scenarios (happy path, edge cases, error cases, boundary values — off-by-one, max/min — race conditions, null/empty/undefined inputs, timezone edge cases, float precision issues, auth/permission edge cases, network failure scenarios), group scenarios by priority (P0 must-have critical path, P1 important edge cases, P2 nice-to-have), identify all integration points that need mocking (external APIs, databases, file system, time), and define acceptance criteria for each scenario. Output only the transformed prompt, nothing else."
    ;;
  writer)
    SYSTEM_PROMPT="You are a Senior Test Engineer with 15 years of experience specializing in test automation. Transform the given task into a precise prompt that asks an agent to: write complete, runnable test code using the appropriate framework (Jest/Vitest for JS/TS, pytest for Python, JUnit for Java), include a complete test file with all imports at the top, mock/stub ALL external dependencies (no real network calls, no real DB), write clear test names that describe the scenario in plain English (not 'test1' or 'shouldWork'), use strict Arrange/Act/Assert structure, handle async correctly (async/await, not callbacks), include no TODOs or placeholder comments, produce copy-paste ready code. Output only the transformed prompt, nothing else."
    ;;
  reviewer)
    SYSTEM_PROMPT="You are a QA Quality Reviewer specializing in test coverage analysis. Transform the given task into a precise prompt that asks an agent to: review test scenarios and code for gaps (missing important scenarios), weak assertions (assertTrue(result) instead of assertEqual(result, expected)), shared mutable state between tests that causes flakiness, hardcoded test data that should be parameterized, missing async handling, tests that verify implementation details instead of behavior, missing error case coverage, determinism issues (time-dependent tests). Format findings as: [MISSING/WEAK/FLAKY/OK] | Test Scenario | Issue | Fix. Output only the transformed prompt, nothing else."
    ;;
  *)
    SYSTEM_PROMPT="You are a QA engineering assistant. Refine the given task into a clear, actionable prompt for a QA agent. Output only the transformed prompt, nothing else."
    ;;
esac

USER_MSG="TEAM MEMORY:
${TEAM_MEMORY:-none}

RAW TASK:
${RAW_TASK}"

RESULT=$(printf '%s' "$USER_MSG" | SYSTEM_PROMPT="$SYSTEM_PROMPT" "$AGENTS2_DIR/call_model.sh" "openai/gpt-4o" 2>/dev/null) || RESULT=""
if [ -n "$RESULT" ] && ! printf '%s' "$RESULT" | grep -qi "^Error\|^API Error"; then echo "$RESULT"; else echo "$RAW_TASK"; fi
