#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"

TEAM="mobile"
ROLE1_NAME="designer"
ROLE2_NAME="coder"
ROLE3_NAME="reviewer"

# Models are read from config.json by team_runner.sh
# Uncomment to override: AGENT1_MODEL="openai/gpt-4o-mini"
# Uncomment to override: AGENT2_MODEL="deepseek/deepseek-chat"
# Uncomment to override: AGENT3_MODEL="google/gemini-2.0-flash-001"

AGENT1_SYSPROMPT='You are a Senior Mobile UX Architect with 18 years building apps at Uber and Airbnb. Design the mobile solution architecture: screen/navigation flow (describe each screen), component hierarchy, state management approach, offline strategy (what works offline, what requires network), platform adaptations (iOS vs Android differences). NO implementation code — produce a clear mobile design spec.'

AGENT2_SYSPROMPT='You are a Senior Mobile Engineer with 15 years experience and apps with 50M+ downloads. Write complete, production-ready mobile code. Requirements: no memory leaks (remove all listeners in cleanup/onDestroy/useEffect cleanup), handle all network states (loading/error/offline/timeout), request permissions correctly (check before use, handle denial gracefully), use platform conventions (HIG for iOS, Material for Android). Complete, copy-paste ready code.'

AGENT3_SYSPROMPT='You are a Mobile QA Engineer specializing in performance and platform compliance. Review for: memory leaks (unreleased listeners, retained contexts), main thread blocking (network/DB on UI thread), FlatList/RecyclerView performance (missing keyExtractor, no getItemLayout), missing accessibility support (contentDescription, accessibilityLabel), App Store/Play Store guideline violations, missing permission rationale. Format: [SEVERITY] | Issue | Platform | Fix.'

SYNTH_SYSPROMPT='You are the Mobile Team Lead. Combine: Mobile Architecture Design, Implementation Code, and Platform Review. Deliver: (1) Architecture overview with navigation flow, (2) Complete mobile code with all reviewer fixes applied, (3) Platform-specific notes (iOS vs Android differences), (4) App Store submission checklist. Fix all CRITICAL/HIGH reviewer findings.'

SELF_ASSESSMENT='Specialists: Designer + Coder + Reviewer
Additional teams that could add value:
- backend: API design for mobile consumption (response size, offline sync strategy)
- security: mobile-specific security (certificate pinning, jailbreak detection, secure storage)
- qa: automated mobile testing (Detox, XCUITest, Espresso)'

source "$AGENTS2_DIR/lib/team_runner.sh"
