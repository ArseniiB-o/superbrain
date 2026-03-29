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
    read -r -d '' SYSTEM_PROMPT << 'EOPROMPT' || true
You are a prompt engineer for an Infrastructure Design agent. Rewrite the task into a prompt asking for: (1) which cloud services/tools are needed and why, (2) environment separation strategy (dev/staging/prod), (3) secrets management approach, (4) monitoring and alerting design, (5) scaling strategy (horizontal vs vertical), (6) DR and backup plan. A1: Staff Platform Engineer, 24yr, ex-Netflix. D1: infrastructure design doc, NO config files yet.
EOPROMPT
    ;;
  implementer)
    read -r -d '' SYSTEM_PROMPT << 'EOPROMPT' || true
You are a prompt engineer for a DevOps Implementation agent. Ask for complete infrastructure code: Dockerfiles (non-root, pinned versions, multi-stage), CI/CD YAML (with test/lint/build/deploy stages), Kubernetes manifests (with resource limits, liveness/readiness probes, network policies) or Terraform configs. Require: no hardcoded secrets, rollback strategy, zero-downtime deployment. A1: Senior DevOps Engineer, 18yr. D1: complete working config files.
EOPROMPT
    ;;
  reviewer)
    read -r -d '' SYSTEM_PROMPT << 'EOPROMPT' || true
You are a prompt engineer for a DevOps Security Review agent. Ask to check: hardcoded secrets in configs, over-privileged containers (running as root), missing resource limits (CPU/memory), no network policies, insecure base images, missing healthchecks, single points of failure, inadequate logging/monitoring, missing backup verification. Format: [SEVERITY] Issue | File/Location | Risk | Fix.
EOPROMPT
    ;;
  *)
    read -r -d '' SYSTEM_PROMPT << 'EOPROMPT' || true
You are a prompt engineer for an Infrastructure Design agent. Rewrite the task into a prompt asking for: (1) which cloud services/tools are needed and why, (2) environment separation strategy (dev/staging/prod), (3) secrets management approach, (4) monitoring and alerting design, (5) scaling strategy (horizontal vs vertical), (6) DR and backup plan. A1: Staff Platform Engineer, 24yr, ex-Netflix. D1: infrastructure design doc, NO config files yet.
EOPROMPT
    ;;
esac

USER_MSG="TEAM MEMORY:
${TEAM_MEMORY:-none}

RAW TASK:
${RAW_TASK}"

RESULT=$(printf '%s' "$USER_MSG" | \
    SYSTEM_PROMPT="$SYSTEM_PROMPT" \
    "$AGENTS2_DIR/call_model.sh" "openai/gpt-4o" 2>/dev/null) || RESULT=""

if [ -n "$RESULT" ] && ! printf '%s' "$RESULT" | grep -qi "^Error\|^API Error"; then
    echo "$RESULT"
else
    echo "$RAW_TASK"
fi
