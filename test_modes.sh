#!/usr/bin/env bash
# ============================================================
# test_modes.sh — Mode Switcher Test Suite
#
# Tests:
#   1. switch.sh syntax and help
#   2. Mode switching: openrouter → claude → openrouter
#   3. Mode persistence (file written correctly)
#   4. call_model.sh model override in claude mode
#   5. Real API call in each mode (optional, pass --live)
#
# Usage:
#   ./test_modes.sh           — fast tests (no API calls)
#   ./test_modes.sh --live    — include real API call tests
# ============================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWITCH="$SCRIPT_DIR/switch.sh"
CALL_MODEL="$SCRIPT_DIR/call_model.sh"
MODE_FILE="$SCRIPT_DIR/.mode"
LIVE="${1:-}"

PASS=0
FAIL=0
SKIP=0

# Load env
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a; source "$SCRIPT_DIR/.env"; set +a
fi

export PYTHONUTF8=1

# ── Test runner ───────────────────────────────────────────────────────────────
run_test() {
    local name="$1"
    local result="$2"   # "pass" | "fail" | "skip"
    local detail="${3:-}"

    case "$result" in
        pass)
            echo "  ✅ PASS: $name"
            PASS=$((PASS+1))
            ;;
        fail)
            echo "  ❌ FAIL: $name"
            [[ -n "$detail" ]] && echo "         Detail: $detail"
            FAIL=$((FAIL+1))
            ;;
        skip)
            echo "  ⏭️  SKIP: $name ($detail)"
            SKIP=$((SKIP+1))
            ;;
    esac
}

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║      Agents2 Mode Switcher Test Suite            ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── Test 1: Files exist ───────────────────────────────────────────────────────
echo "── Module: File Existence ──"

[[ -f "$SWITCH" ]]     && run_test "switch.sh exists"     "pass" || run_test "switch.sh exists"     "fail" "not found: $SWITCH"
[[ -f "$CALL_MODEL" ]] && run_test "call_model.sh exists" "pass" || run_test "call_model.sh exists" "fail" "not found: $CALL_MODEL"
[[ -x "$SWITCH" ]]     && run_test "switch.sh executable" "pass" || run_test "switch.sh executable" "fail" "not executable"
[[ -x "$CALL_MODEL" ]] && run_test "call_model.sh executable" "pass" || run_test "call_model.sh executable" "fail" "not executable"

# ── Test 2: Syntax check ─────────────────────────────────────────────────────
echo ""
echo "── Module: Syntax ──"

bash -n "$SWITCH"     2>/dev/null && run_test "switch.sh bash syntax"     "pass" || run_test "switch.sh bash syntax"     "fail"
bash -n "$CALL_MODEL" 2>/dev/null && run_test "call_model.sh bash syntax" "pass" || run_test "call_model.sh bash syntax" "fail"
bash -n "$SCRIPT_DIR/dispatch.sh" 2>/dev/null && run_test "dispatch.sh bash syntax" "pass" || run_test "dispatch.sh bash syntax" "fail"

# ── Test 3: switch.sh help ────────────────────────────────────────────────────
echo ""
echo "── Module: switch.sh CLI ──"

HELP_OUTPUT=$(bash "$SWITCH" help 2>&1 || true)
printf '%s' "$HELP_OUTPUT" | grep -q "openrouter" && run_test "help mentions openrouter" "pass" || run_test "help mentions openrouter" "fail"
printf '%s' "$HELP_OUTPUT" | grep -q "claude"     && run_test "help mentions claude"     "pass" || run_test "help mentions claude"     "fail"

STATUS_OUTPUT=$(bash "$SWITCH" status 2>&1 || true)
printf '%s' "$STATUS_OUTPUT" | grep -qiE "Active mode|OPENROUTER|CLAUDE" && run_test "status shows mode" "pass" || run_test "status shows mode" "fail"

UNKNOWN_OUTPUT=$(bash "$SWITCH" unknown_mode 2>&1 || true)
printf '%s' "$UNKNOWN_OUTPUT" | grep -qi "error\|unknown\|valid" && run_test "invalid mode shows error" "pass" || run_test "invalid mode shows error" "fail"

# ── Test 4: Mode switching ────────────────────────────────────────────────────
echo ""
echo "── Module: Mode Persistence ──"

# Save original mode
ORIG_MODE=$(cat "$MODE_FILE" 2>/dev/null || echo "openrouter")

# Switch to claude
bash "$SWITCH" claude > /dev/null 2>&1
READ_MODE=$(cat "$MODE_FILE" 2>/dev/null || echo "")
[[ "$READ_MODE" == "claude" ]] && run_test "switch to claude: .mode file = claude" "pass" || run_test "switch to claude: .mode file = claude" "fail" "got: $READ_MODE"

# Check status reflects claude
STATUS_AFTER=$(bash "$SWITCH" status 2>&1 || true)
printf '%s' "$STATUS_AFTER" | grep -qi "claude\|CLAUDE" && run_test "status after switch shows claude" "pass" || run_test "status after switch shows claude" "fail"

# Switch back to openrouter
bash "$SWITCH" openrouter > /dev/null 2>&1
READ_MODE=$(cat "$MODE_FILE" 2>/dev/null || echo "")
[[ "$READ_MODE" == "openrouter" ]] && run_test "switch to openrouter: .mode file = openrouter" "pass" || run_test "switch to openrouter: .mode file = openrouter" "fail" "got: $READ_MODE"

# Restore original mode
printf '%s' "$ORIG_MODE" > "$MODE_FILE"

# ── Test 5: call_model.sh model override ──────────────────────────────────────
echo ""
echo "── Module: Model Override ──"

# In claude mode, check that MODEL env var is overridden
# We test this by checking the script logic directly
bash "$SWITCH" claude > /dev/null 2>&1
CURRENT_MODE=$(cat "$MODE_FILE" 2>/dev/null || echo "openrouter")
[[ "$CURRENT_MODE" == "claude" ]] && run_test "mode=claude set for override test" "pass" || run_test "mode=claude set for override test" "fail"

# The model override happens inside call_model.sh bash section
# Check that the script contains the override logic
grep -q "sonnet\|claude-sonnet" "$CALL_MODEL" && \
    run_test "call_model.sh contains sonnet model reference" "pass" || \
    run_test "call_model.sh contains sonnet model reference" "fail"

grep -q "CLAUDE_CODE_EXECPATH\|claude.*-p\|command -v claude" "$CALL_MODEL" && \
    run_test "call_model.sh has claude CLI binary detection" "pass" || \
    run_test "call_model.sh has claude CLI binary detection" "fail"

# Check ANTHROPIC_API_KEY is NOT required (subscription mode)
grep -q "^.*ANTHROPIC_API_KEY.*required\|sys.exit.*ANTHROPIC" "$CALL_MODEL" && \
    run_test "call_model.sh does NOT require ANTHROPIC_API_KEY" "fail" "API key check found" || \
    run_test "call_model.sh does NOT require ANTHROPIC_API_KEY" "pass"

# Restore openrouter
bash "$SWITCH" openrouter > /dev/null 2>&1

# ── Test 6: dispatch.sh banner ────────────────────────────────────────────────
echo ""
echo "── Module: dispatch.sh Banner ──"

grep -q "MODE_LABEL\|ACTIVE_MODE\|Mode:" "$SCRIPT_DIR/dispatch.sh" && \
    run_test "dispatch.sh shows mode in banner" "pass" || \
    run_test "dispatch.sh shows mode in banner" "fail"

# ── Test 7: Live API tests ────────────────────────────────────────────────────
echo ""
echo "── Module: Live API Tests ──"

if [[ "$LIVE" != "--live" ]]; then
    run_test "openrouter API call (live)" "skip" "pass --live to run"
    run_test "claude mode API call (live)" "skip" "pass --live to run"
else
    # Test openrouter mode
    bash "$SWITCH" openrouter > /dev/null 2>&1
    OR_RESPONSE=$(echo "Say only: OPENROUTER_OK" | bash "$CALL_MODEL" "openai/gpt-4o-mini" 2>/dev/null || echo "")
    printf '%s' "$OR_RESPONSE" | grep -q "OPENROUTER_OK\|OK" && \
        run_test "openrouter API call works" "pass" || \
        run_test "openrouter API call works" "fail" "Response: ${OR_RESPONSE:0:100}"

    # Test claude mode (uses Claude Code subscription via claude -p)
    bash "$SWITCH" claude > /dev/null 2>&1
    CL_RESPONSE=$(echo "Reply with exactly: CLAUDE_SUBSCRIPTION_OK" | bash "$CALL_MODEL" "ignored-model" 2>/dev/null || echo "")
    printf '%s' "$CL_RESPONSE" | grep -q "CLAUDE_SUBSCRIPTION_OK\|OK" && \
        run_test "claude mode uses Max subscription (claude -p works)" "pass" || \
        run_test "claude mode uses Max subscription (claude -p works)" "fail" "Response: ${CL_RESPONSE:0:100}"

    # Restore
    bash "$SWITCH" openrouter > /dev/null 2>&1
fi

# ── Summary ───────────────────────────────────────────────────────────────────
TOTAL=$((PASS + FAIL + SKIP))
echo ""
echo "╔══════════════════════════════════════════════════╗"
printf "║  Results: %3d passed  %3d failed  %3d skipped   ║\n" "$PASS" "$FAIL" "$SKIP"
printf "║  Total:   %3d tests                              ║\n" "$TOTAL"

if [[ "$FAIL" -eq 0 ]]; then
    echo "║  Status:  ✅ ALL TESTS PASSED                    ║"
else
    echo "║  Status:  ❌ SOME TESTS FAILED                   ║"
fi
echo "╚══════════════════════════════════════════════════╝"
echo ""

# Ensure mode restored
printf 'openrouter' > "$MODE_FILE"

[[ "$FAIL" -eq 0 ]]
