#!/bin/bash
# regression.sh — Run after any change to ~/.agents2
AGENTS2_DIR="${HOME}/.agents2"
PASS=0
FAIL=0

run_test() {
    local name="$1"
    local check="$2"
    if eval "$check" > /dev/null 2>&1; then
        echo "  PASS: $name"
        ((PASS++))
    else
        echo "  FAIL: $name"
        ((FAIL++))
    fi
}

echo "=== AGENTS2 REGRESSION SUITE ==="

run_test "config.json valid" "python3 -m json.tool $AGENTS2_DIR/config.json"
run_test "dispatch.sh syntax" "bash -n $AGENTS2_DIR/dispatch.sh"
run_test "team_runner.sh syntax" "bash -n $AGENTS2_DIR/lib/team_runner.sh"
run_test "memory.sh syntax" "bash -n $AGENTS2_DIR/lib/memory.sh"
run_test "logger.sh syntax" "bash -n $AGENTS2_DIR/lib/logger.sh"
run_test "call_model.sh syntax" "bash -n $AGENTS2_DIR/call_model.sh"
run_test "no md5sum usage" "! grep -r 'md5sum' $AGENTS2_DIR --include='*.sh' | grep -v .git"
run_test "no date -r usage" "! grep -r 'date -r' $AGENTS2_DIR --include='*.sh' | grep -v .git"
run_test "no hardcoded MSYS2 paths" "! grep -r '/c/Users/' $AGENTS2_DIR --include='*.sh' | grep -v .git"
run_test "PYTHONUTF8 exported" "grep -r 'PYTHONUTF8' $AGENTS2_DIR --include='*.sh' | grep -v .git"
run_test "cygpath -m fix present" "grep 'cygpath -m' $AGENTS2_DIR/dispatch.sh"
run_test "printf -- fix present" "grep 'printf -- ' $AGENTS2_DIR/lib/memory.sh"
run_test "atomic cache write" "grep 'CACHE_TMP\|mv -f' $AGENTS2_DIR/dispatch.sh"
run_test "no orphaned fallback.sh" "! test -f $AGENTS2_DIR/lib/fallback.sh"
run_test "log rotation present" "grep 'mtime +7' $AGENTS2_DIR/lib/logger.sh"
run_test "exponential backoff" "grep 'BASE_DELAY\|backoff\|2.*attempt' $AGENTS2_DIR/call_model.sh"
run_test "retry on 5xx" "grep 'exc.code >= 500\|status_code >= 500\|>= 500' $AGENTS2_DIR/call_model.sh"
run_test "timeout 120s" "grep 'TIMEOUT.*120\|120.*TIMEOUT\|timeout.*120\|120.*timeout' $AGENTS2_DIR/call_model.sh"
run_test "all teams have lead.sh" "[ $(find $AGENTS2_DIR/teams -name 'lead.sh' | wc -l) -eq 17 ]"
run_test "all teams have PE script" "[ $(find $AGENTS2_DIR/teams -name 'prompt_engineer.sh' | wc -l) -eq 17 ]"
run_test "all team lead.sh syntax OK" "bash -c 'for f in $AGENTS2_DIR/teams/*/lead.sh; do bash -n \"\$f\" || exit 1; done'"
run_test "all PE scripts syntax OK" "bash -c 'for f in $AGENTS2_DIR/teams/*/prompt_engineer.sh; do bash -n \"\$f\" || exit 1; done'"
run_test "no orphaned .tmp files in cache" "! ls $AGENTS2_DIR/.cache/*.tmp 2>/dev/null"
run_test "ANSI-free log files" "! grep -lP '\x1b\[' $AGENTS2_DIR/logs/session_$(date +%Y%m%d).log 2>/dev/null"
run_test "gitignore covers .env" "grep -q '^\.env' $AGENTS2_DIR/.gitignore"
run_test "gitignore covers .cache/" "grep -q '\.cache/' $AGENTS2_DIR/.gitignore"
run_test "gitignore covers logs/" "grep -q '^logs/' $AGENTS2_DIR/.gitignore"
run_test ".env not tracked by git" "! git -C $AGENTS2_DIR ls-files .env | grep -q .env"

if [ -n "${OPENROUTER_API_KEY:-}" ]; then
    RESULT=$(printf "Reply with: AGENTS2_OK" | SYSTEM_PROMPT="You are a test bot." "$AGENTS2_DIR/call_model.sh" "openai/gpt-4o-mini" 2>/dev/null || echo "")
    run_test "API call works" "echo '$RESULT' | grep -q 'AGENTS2_OK'"
    DISPATCH_RESULT=$(bash "$AGENTS2_DIR/dispatch.sh" --no-cache --teams "backend" "Reply with exactly: DISPATCH_OK" 2>/dev/null || echo "")
    run_test "dispatch pipeline works" "! echo '$DISPATCH_RESULT' | grep -q 'returned no output'"
    run_test "dispatch has real output" "[ ${#DISPATCH_RESULT} -gt 50 ]"
fi

echo ""
echo "=== RESULTS: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
