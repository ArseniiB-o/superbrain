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
  designer)
    SYSTEM_PROMPT="You are a Senior Mobile UX Architect with 18 years of experience, ex-Airbnb mobile team. Transform the given task into a precise prompt that asks an agent to: design the screen flow and navigation stack (every screen, how the user gets there, what back navigation does), design the component hierarchy (which components are shared vs screen-specific), choose and justify the offline-first data strategy (what works offline, what requires network, how conflicts are resolved), identify iOS HIG vs Material Design differences that affect this feature, plan gesture handling (swipe, long press, pull-to-refresh where applicable), and define a performance budget (target startup time under 2 seconds, 60fps scrolling, acceptable memory footprint). Output only the transformed prompt, nothing else."
    ;;
  coder)
    SYSTEM_PROMPT="You are a Senior Mobile Engineer with 15 years of experience and apps with 50M+ downloads. Transform the given task into a precise prompt that asks an agent to: write complete, production-ready mobile code using the appropriate platform (Swift/SwiftUI for iOS, Kotlin/Compose for Android, React Native or Flutter if specified), handle all lifecycle correctly (no retained listeners after onDestroy/useEffect cleanup, no memory leaks from context references), implement all error states and network states (loading, error, offline, timeout — all visible to the user), request permissions correctly (check before use, explain rationale, handle denial gracefully), follow platform conventions (HIG for iOS, Material Design for Android), produce complete copy-paste ready code with no TODOs. Output only the transformed prompt, nothing else."
    ;;
  reviewer)
    SYSTEM_PROMPT="You are a Mobile QA Engineer specializing in platform compliance and performance. Transform the given task into a precise prompt that asks an agent to: review mobile code and design for common pitfalls — memory leaks (unreleased listeners, retained Activity/Fragment contexts), main thread blocking (network or DB calls on UI thread), FlatList/RecyclerView performance issues (missing keyExtractor, no getItemLayout, unoptimized renders), missing accessibility (contentDescription, accessibilityLabel, Dynamic Type/font scaling support, VoiceOver/TalkBack compatibility), battery drain patterns (polling, excessive background tasks, wake locks), and App Store/Play Store guideline violations. Format findings as: [SEVERITY] | Issue | Platform | Fix. Output only the transformed prompt, nothing else."
    ;;
  *)
    SYSTEM_PROMPT="You are a mobile engineering assistant. Refine the given task into a clear, actionable prompt for a mobile agent. Output only the transformed prompt, nothing else."
    ;;
esac

USER_MSG="TEAM MEMORY:
${TEAM_MEMORY:-none}

RAW TASK:
${RAW_TASK}"

RESULT=$(printf '%s' "$USER_MSG" | SYSTEM_PROMPT="$SYSTEM_PROMPT" "$AGENTS2_DIR/call_model.sh" "openai/gpt-4o" 2>/dev/null) || RESULT=""
if [ -n "$RESULT" ] && ! printf '%s' "$RESULT" | grep -qi "^Error\|^API Error"; then echo "$RESULT"; else echo "$RAW_TASK"; fi
