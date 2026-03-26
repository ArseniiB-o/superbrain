#!/usr/bin/env bash
# teams/mobile/lead.sh — Mobile Team Lead

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$SCRIPT_DIR/../.."

source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"
source "$AGENTS2_DIR/lib/fallback.sh"

TEAM="mobile"
PRIMARY_MODEL="openai/gpt-4o-mini"
FALLBACK1_MODEL="deepseek/deepseek-chat"
FALLBACK2_MODEL="google/gemini-2.0-flash-001"

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

log_action "$TEAM" "lead" "$PRIMARY_MODEL" "RUNNING" "$TASK_SUMMARY" "$RAW_TASK"
echo "🔧 [$TEAM/lead] Starting: ${TASK_SUMMARY:0:70}..." >&2

TEAM_MEMORY=$(memory_read "$TEAM")

echo "  📝 [$TEAM/lead] Optimizing prompt..." >&2
OPTIMIZED_PROMPT=$(echo "$RAW_TASK" | \
    TEAM_MEMORY="$TEAM_MEMORY" \
    "$AGENTS2_DIR/lib/prompt_engineer.sh" "$TEAM" 2>/dev/null || echo "$RAW_TASK")

PROMPT_FILE=$(mktemp)
SYSPROMPT_FILE=$(mktemp)
trap 'rm -f "$TMPFILE" "$PROMPT_FILE" "$SYSPROMPT_FILE"' EXIT

printf '%s' "$OPTIMIZED_PROMPT" > "$PROMPT_FILE"
printf '%s' "You are a Staff Mobile Engineer with 20 years of experience. You have shipped apps with 50M+ downloads on both iOS and Android. Deep expertise in: React Native (performance optimization, bridge architecture, native modules), Flutter (Dart, widget lifecycle, platform channels), iOS (Swift, SwiftUI, UIKit, Core Data, push notifications, App Store guidelines), Android (Kotlin, Jetpack Compose, Room, WorkManager). You understand mobile-specific constraints: battery life, network conditions (2G to 5G), memory limits, app startup time, crash-free rate, ANR prevention. You always think about offline-first architecture, proper state restoration, and deep linking." > "$SYSPROMPT_FILE"

echo "  🤖 [$TEAM/lead] Running agent (primary: $PRIMARY_MODEL)..." >&2
RESULT=$(run_with_fallback "$PROMPT_FILE" "$SYSPROMPT_FILE" \
    "$PRIMARY_MODEL" "$FALLBACK1_MODEL" "$FALLBACK2_MODEL")
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ] || [ -z "$RESULT" ]; then
    log_action "$TEAM" "lead" "$PRIMARY_MODEL" "FAILED" "$TASK_SUMMARY" "$RAW_TASK" ""
    echo "❌ [$TEAM/lead] All models failed" >&2
    exit 1
fi

LEARNING="$(date '+%Y-%m-%d'): ${TASK_SUMMARY:0:80}"
memory_append "$TEAM" "$LEARNING"

log_action "$TEAM" "lead" "$PRIMARY_MODEL" "SUCCESS" "$TASK_SUMMARY" "$OPTIMIZED_PROMPT" "$RESULT"
echo "  ✅ [$TEAM/lead] Done" >&2

echo "$RESULT"
