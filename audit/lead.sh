#!/usr/bin/env bash
# audit/lead.sh — Final Cross-Team Audit Lead
#
# Called after all team work is done. Performs:
# 1. Security audit (OWASP + custom)
# 2. Code quality audit
# 3. Architecture review
# 4. Business logic validation
# 5. Final verdict with severity-ranked issues
#
# Usage:
#   ./lead.sh "audit this project: /path/to/project"
#   cat all_team_outputs.txt | ./lead.sh "final audit"
#   ./lead.sh --project /path/to/project "audit description"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$SCRIPT_DIR/.."

# Load .env if present
ENV_FILE="${AGENTS2_DIR}/.env"
if [[ -f "$ENV_FILE" ]]; then
    set -a; source "$ENV_FILE"; set +a
fi

source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"

# ── Argument parsing ───────────────────────────────────────────────────────────
TASK_INPUT=""
PROJECT_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project|-p)
            PROJECT_PATH="${2:-}"
            shift 2
            ;;
        *)
            TASK_INPUT="$1"
            shift
            ;;
    esac
done

TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

if [ -z "$TASK_INPUT" ] && [ ! -t 0 ]; then
    cat > "$TMPFILE"
    TASK_INPUT="$(cat "$TMPFILE")"
elif [ -n "$TASK_INPUT" ]; then
    printf '%s' "$TASK_INPUT" > "$TMPFILE"
else
    printf 'Error: provide audit task via argument or stdin\n' >&2
    printf '  Usage: ./lead.sh "audit this project: description"\n' >&2
    printf '  Usage: cat outputs.txt | ./lead.sh "final audit"\n' >&2
    exit 1
fi

if [ -z "${TASK_INPUT:-}" ]; then
    printf 'Error: audit task description is empty\n' >&2
    exit 1
fi

TASK_SUMMARY="${TASK_INPUT:0:120}"

# Append project path to task if provided
if [ -n "$PROJECT_PATH" ]; then
    TASK_INPUT="${TASK_INPUT}

Project path for reference: ${PROJECT_PATH}"
fi

log_session_start
log_action "audit" "lead" "orchestrator" "RUNNING" "$TASK_SUMMARY"

printf '\n\033[1;31m╔══════════════════════════════════════════════════════════════╗\033[0m\n' >&2
printf '\033[1;31m║              FINAL AUDIT LEAD — STARTING                      ║\033[0m\n' >&2
printf '\033[1;31m╚══════════════════════════════════════════════════════════════╝\033[0m\n\n' >&2
printf '  Audit target: %s\n\n' "${TASK_SUMMARY:0:80}" >&2

# ── Team leads ─────────────────────────────────────────────────────────────────
SECURITY_LEAD="$AGENTS2_DIR/teams/security/lead.sh"
BACKEND_LEAD="$AGENTS2_DIR/teams/backend/lead.sh"
QA_LEAD="$AGENTS2_DIR/teams/qa/lead.sh"

# ── Temp files for parallel sub-audit results ──────────────────────────────────
SEC_OUT=$(mktemp)
ARCH_OUT=$(mktemp)
QA_OUT=$(mktemp)

trap 'rm -f "$TMPFILE" "$SEC_OUT" "$ARCH_OUT" "$QA_OUT"' EXIT

# ── Helper: run a sub-audit with error capture ─────────────────────────────────
run_audit() {
    local lead_script="$1"
    local task="$2"
    local output_file="$3"
    local audit_label="$4"

    if [ ! -x "$lead_script" ]; then
        printf '[UNAVAILABLE] Audit team not found: %s\n' "$lead_script" > "$output_file"
        printf '  \033[0;33m⚠\033[0m  [audit/lead] %s team not found, using placeholder\n' "$audit_label" >&2
        return 0
    fi

    printf '  \033[0;36m▶\033[0m  [audit/lead] Starting %s...\n' "$audit_label" >&2

    if "$lead_script" "$task" > "$output_file" 2>/dev/null; then
        printf '  \033[0;32m✓\033[0m  [audit/lead] %s complete\n' "$audit_label" >&2
    else
        printf '[FAILED] %s failed — proceeding without it\n' "$audit_label" > "$output_file"
        printf '  \033[0;31m✗\033[0m  [audit/lead] %s failed, using placeholder\n' "$audit_label" >&2
    fi
}

# ── Construct highly critical sub-audit prompts ────────────────────────────────
SEC_TASK="You are auditing for a defense contractor. Find EVERY security flaw. Be ruthless.

AUDIT SCOPE: ${TASK_INPUT}

Required checks:
- OWASP Top 10: SQL injection, XSS, CSRF, SSRF, XXE, broken auth, security misconfiguration, insecure deserialization, using components with known vulnerabilities, insufficient logging
- Authentication: JWT implementation, session management, token expiry, refresh token security
- Authorization: RBAC, privilege escalation paths, IDOR vulnerabilities
- Input validation: All entry points, sanitization, encoding
- Cryptography: Algorithm choices, key management, entropy, hardcoded secrets
- API security: Rate limiting, mass assignment, exposed sensitive endpoints
- Secrets management: Env vars, config files, git history risks
- Third-party dependencies: Known CVEs, supply chain risks
- Infrastructure: HTTPS enforcement, CORS policy, security headers

For each finding use format:
[SEVERITY] [CODE] Short title
- Location: specific file/component/endpoint
- Exploit: how an attacker would abuse this
- Fix: concrete remediation with code example if possible

Severity levels: CRITICAL / HIGH / MEDIUM / LOW / INFO"

ARCH_TASK="You are a senior architect performing a ruthless architecture review. Find every design flaw.

AUDIT SCOPE: ${TASK_INPUT}

Required checks:
- Scalability: bottlenecks, single points of failure, horizontal scaling readiness
- Design patterns: anti-patterns used, SOLID violations, coupling issues
- Data layer: N+1 queries, missing indexes, transaction boundaries, race conditions
- API design: RESTful correctness, versioning, pagination, error responses
- Caching: strategies used, cache invalidation risks, stale data problems
- Async/concurrency: deadlocks, race conditions, queue management
- Error handling: missing error boundaries, unhandled rejections, silent failures
- Observability: logging gaps, missing metrics, alerting blind spots
- Dependency management: circular dependencies, over-engineering, missing abstractions
- Performance: algorithmic complexity, memory leaks, resource cleanup

For each finding use format:
[SEVERITY] [CODE] Short title
- Location: specific component/module/layer
- Problem: what's wrong and why it matters
- Impact: what breaks at scale or under load
- Fix: concrete recommendation

Severity levels: CRITICAL / HIGH / MEDIUM / LOW / INFO"

QA_TASK="You are a QA Lead performing a ruthless quality and reliability audit. Find every gap.

AUDIT SCOPE: ${TASK_INPUT}

Required checks:
- Test coverage: untested paths, missing unit/integration/e2e tests
- Error handling: unhandled edge cases, missing null checks, type coercion issues
- Input validation: boundary conditions, empty inputs, malformed data
- Business logic: incorrect assumptions, missing validation rules, state machine gaps
- Data integrity: missing constraints, orphaned records, cascading delete issues
- Concurrency: race conditions in business logic, double-submission vulnerabilities
- External dependencies: missing retry logic, timeout handling, circuit breakers
- Logging: insufficient audit trails, missing error context, PII in logs
- Configuration: hardcoded values, missing environment validation, defaults that fail in prod
- Deployment: missing health checks, graceful shutdown, migration safety

For each finding use format:
[SEVERITY] [CODE] Short title
- Location: specific component/function/flow
- Scenario: what triggers this issue
- Impact: what the user or system experiences
- Fix: concrete fix

Severity levels: CRITICAL / HIGH / MEDIUM / LOW / INFO"

# ── Run all 3 sub-audits in parallel ──────────────────────────────────────────
printf '\033[1m[1/3] Running 3 parallel sub-audits...\033[0m\n\n' >&2

run_audit "$SECURITY_LEAD" "$SEC_TASK"  "$SEC_OUT"  "security deep-dive (OWASP)" &
PID_SEC=$!

run_audit "$BACKEND_LEAD"  "$ARCH_TASK" "$ARCH_OUT" "architecture review" &
PID_ARCH=$!

run_audit "$QA_LEAD"       "$QA_TASK"   "$QA_OUT"   "quality/reliability review" &
PID_QA=$!

# Wait for all with error tolerance
for pid in $PID_SEC $PID_ARCH $PID_QA; do
    wait "$pid" 2>/dev/null || true
done

printf '\n\033[1m[2/3] All sub-audits complete. Synthesizing final report...\033[0m\n\n' >&2

# ── Collect results ────────────────────────────────────────────────────────────
SEC_RESULT="$(cat "$SEC_OUT"  2>/dev/null || printf '[Security audit unavailable]')"
ARCH_RESULT="$(cat "$ARCH_OUT" 2>/dev/null || printf '[Architecture audit unavailable]')"
QA_RESULT="$(cat "$QA_OUT"   2>/dev/null || printf '[Quality audit unavailable]')"

# ── Read audit memory for context ──────────────────────────────────────────────
AUDIT_MEMORY="$(memory_read "audit" 2>/dev/null || true)"

# ── Synthesis prompt ───────────────────────────────────────────────────────────
SYNTHESIS_PROMPT="You are a Chief Security Officer producing the final audit report. Synthesize three sub-audit reports into a single, authoritative, severity-ranked final report.

ORIGINAL AUDIT TASK:
${TASK_INPUT}

SECURITY AUDIT FINDINGS:
${SEC_RESULT}

ARCHITECTURE AUDIT FINDINGS:
${ARCH_RESULT}

QUALITY AUDIT FINDINGS:
${QA_RESULT}

${AUDIT_MEMORY:+AUDIT MEMORY (patterns from past audits):
$AUDIT_MEMORY
}

Produce the final audit report using EXACTLY this format:

## 🔴 CRITICAL ISSUES (fix before deploy)
### [SEC-001] [Issue title]
- **Location**: specific file/component/endpoint
- **Exploit**: how an attacker or bug triggers this
- **Fix**: concrete remediation steps with code where applicable

[include ALL critical issues, even if many]

## 🟠 HIGH ISSUES
### [SEC-002] [Issue title]
- **Location**: ...
- **Problem**: ...
- **Fix**: ...

[include ALL high issues]

## 🟡 MEDIUM ISSUES
[Use compact format: ### [CODE] Title — Location | Problem | Fix]

## 🟢 LOW / INFO
[Use compact format: ### [CODE] Title — brief description and recommendation]

## 📊 AUDIT SCORES
Security: X/10 — [one-line justification]
Code Quality: X/10 — [one-line justification]
Architecture: X/10 — [one-line justification]
Overall: X/10 — [weighted average with reasoning]

## ✅ WHAT'S GOOD
[3-5 bullet points highlighting genuine strengths found during the audit]

## 🚨 IMMEDIATE ACTIONS REQUIRED
1. [Highest priority action — what to fix first and why]
2. [Second priority]
3. [Third priority]
4. [Fourth priority]
5. [Fifth priority]

Merge duplicate findings from multiple audits. Deduplicate by issue (keep highest severity version). Be specific — never say 'add input validation' without specifying WHERE and HOW. Assign sequential codes: SEC-001, ARCH-001, QA-001 by category."

SYNTHESIS_SYS="You are a Chief Security Officer producing final audit reports for enterprise clients. Your reports are thorough, specific, and actionable. Every finding must have a concrete location and fix. Scores are honest — not inflated."

# ── Synthesize with GPT-4o, fallback to Gemini ────────────────────────────────
SYNTHESIS_FILE=$(mktemp)
trap 'rm -f "$TMPFILE" "$SEC_OUT" "$ARCH_OUT" "$QA_OUT" "$SYNTHESIS_FILE"' EXIT

printf '%s' "$SYNTHESIS_PROMPT" > "$SYNTHESIS_FILE"

SYNTHESIS_RESULT=""
SYNTHESIS_MODEL="openai/gpt-4o"

printf '  \033[0;36m▶\033[0m  [audit/lead] Synthesizing with %s...\n' "$SYNTHESIS_MODEL" >&2

if SYNTHESIS_RESULT="$(SYSTEM_PROMPT="$SYNTHESIS_SYS" \
    "$AGENTS2_DIR/call_model.sh" "openai/gpt-4o" < "$SYNTHESIS_FILE" 2>/dev/null)" \
    && [ -n "${SYNTHESIS_RESULT:-}" ]; then
    SYNTHESIS_MODEL="openai/gpt-4o"
    printf '  \033[0;32m✓\033[0m  [audit/lead] Synthesis complete (gpt-4o)\n' >&2
elif SYNTHESIS_RESULT="$(SYSTEM_PROMPT="$SYNTHESIS_SYS" \
    "$AGENTS2_DIR/call_model.sh" "google/gemini-2.0-flash-001" < "$SYNTHESIS_FILE" 2>/dev/null)" \
    && [ -n "${SYNTHESIS_RESULT:-}" ]; then
    SYNTHESIS_MODEL="google/gemini-2.0-flash-001"
    printf '  \033[0;32m✓\033[0m  [audit/lead] Synthesis complete (gemini fallback)\n' >&2
else
    # Manual fallback assembly
    SYNTHESIS_RESULT="## 🔴 CRITICAL ISSUES (fix before deploy)
$(printf '%s' "$SEC_RESULT" | grep -A5 'CRITICAL' | head -30 || printf '[See security audit above]')

## 🟠 HIGH ISSUES
$(printf '%s' "$SEC_RESULT$ARCH_RESULT$QA_RESULT" | grep -A3 'HIGH' | head -30 || printf '[See sub-audits above]')

## 🟡 MEDIUM ISSUES
[See detailed sub-audits above]

## 🟢 LOW / INFO
[See detailed sub-audits above]

## 📊 AUDIT SCORES
Security: ?/10 — synthesis model unavailable
Code Quality: ?/10 — synthesis model unavailable
Architecture: ?/10 — synthesis model unavailable
Overall: ?/10 — review sub-audits directly

## ✅ WHAT'S GOOD
- Sub-audits completed successfully
- Multiple security dimensions covered

## 🚨 IMMEDIATE ACTIONS REQUIRED
1. Review CRITICAL security findings first
2. Address HIGH architecture issues
3. Improve test coverage gaps
4. Fix error handling gaps
5. Review and rotate any exposed secrets"
    SYNTHESIS_MODEL="fallback-manual"
    printf '  \033[0;33m⚠\033[0m  [audit/lead] All synthesis models failed — using manual assembly\n' >&2
fi

# ── Print final audit report ───────────────────────────────────────────────────
printf '\n'
printf '╔══════════════════════════════════════════════════════════════╗\n'
printf '║                    FINAL AUDIT REPORT                        ║\n'
printf '╚══════════════════════════════════════════════════════════════╝\n'
printf '\n'
printf '%s\n' "$SYNTHESIS_RESULT"
printf '\n'
printf '── Sub-Audit Sources ────────────────────────────────────────────\n'
printf 'Security (OWASP)  : %s\n' "$SECURITY_LEAD"
printf 'Architecture      : %s\n' "$BACKEND_LEAD"
printf 'Quality/Reliability: %s\n' "$QA_LEAD"
printf 'Synthesis model   : %s\n' "$SYNTHESIS_MODEL"
printf '─────────────────────────────────────────────────────────────────\n'
printf '\n'

# ── Append key findings to audit memory ───────────────────────────────────────
printf '\033[1m[3/3] Updating audit memory...\033[0m\n' >&2

# Extract overall score line for memory
SCORE_LINE="$(printf '%s' "$SYNTHESIS_RESULT" | grep -i 'Overall:' | head -1 | sed 's/[[:space:]]*$//' || printf 'score unknown')"
CRITICAL_COUNT="$(printf '%s' "$SYNTHESIS_RESULT" | grep -c '## 🔴 CRITICAL\|CRITICAL\]' | head -1 || printf '?')"

memory_append "audit" "Audit: ${TASK_SUMMARY:0:70} | ${SCORE_LINE} | Synthesis: ${SYNTHESIS_MODEL}"
memory_append "audit" "Pattern: ran security+architecture+quality sub-audits in parallel, synthesized with ${SYNTHESIS_MODEL}"

log_action "audit" "lead" "$SYNTHESIS_MODEL" "SUCCESS" \
    "Final audit complete: $TASK_SUMMARY" "" ""
log_session_end

printf '\n\033[1;32m✅ Audit complete.\033[0m\n' >&2
printf '   Memory updated: %s/audit/memory.md\n' "$AGENTS2_DIR" >&2
printf '\n' >&2
