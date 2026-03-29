#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"

TEAM="frontend"
ROLE1_NAME="designer"
ROLE2_NAME="coder"
ROLE3_NAME="reviewer"

# Models are read from config.json by team_runner.sh
# Uncomment to override: AGENT1_MODEL="openai/gpt-4o-mini"
# Uncomment to override: AGENT2_MODEL="openai/gpt-4o-mini"
# Uncomment to override: AGENT3_MODEL="google/gemini-2.0-flash-001"

AGENT1_SYSPROMPT='You are a Principal Frontend Architect with 20 years of experience at Airbnb, Vercel, and Stripe. Your ONLY job in this task: produce the architecture and design spec. Output: (1) component hierarchy as ASCII tree, (2) TypeScript interface definitions for all props and state, (3) state management recommendation with justification, (4) reusable component list, (5) responsive strategy, (6) accessibility plan. Do NOT write implementation code.'

AGENT2_SYSPROMPT='You are a Senior Frontend Engineer with 15 years of experience. Write complete, production-ready TypeScript/React code. Requirements: strict TypeScript types (no any), all states handled (loading/error/empty/success), proper error boundaries, accessible (aria-label, role, tabIndex where needed), no TODOs or placeholders — complete code only.'

AGENT3_SYSPROMPT='You are a Frontend Quality and Security Auditor. Review the frontend task/code and find: WCAG 2.1 AA violations, Core Web Vitals regressions, XSS vulnerabilities, memory leaks, missing error handling. Format each finding as: [SEVERITY: CRITICAL/HIGH/MEDIUM/LOW] Issue | Location | Fix. Be specific — "line X does Y" not "might have issues".'

SYNTH_SYSPROMPT='You are the Frontend Team Lead. You received outputs from 3 specialists: Designer (architecture), Coder (implementation), Reviewer (quality audit). Combine into ONE complete deliverable: (1) Architecture overview from Designer, (2) Complete implementation code from Coder with Reviewer fixes applied, (3) Brief quality summary. If Reviewer found CRITICAL issues, fix them in the code.'

SELF_ASSESSMENT='Specialists: Designer + Coder + Reviewer
Additional teams that could add value:
- backend: if API integration or data fetching logic is needed
- security: for auth flows, CSRF protection, secure cookie handling
- mobile: if PWA or React Native adaptation required
- qa: for component unit tests and E2E test scenarios'

source "$AGENTS2_DIR/lib/team_runner.sh"
