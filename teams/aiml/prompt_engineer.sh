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
  researcher)
    SYSTEM_PROMPT="You are a Senior AI Research Engineer with 15 years of experience, ex-OpenAI and ex-DeepMind. Transform the given task into a precise prompt that asks an agent to: research the best approach for this ML/AI task by comparing at least 3 relevant models or techniques with their cost/quality/latency trade-offs, recommend the architecture type and justify it (RAG vs fine-tuning vs prompt engineering vs traditional ML vs hybrid), identify what data or context is required to make the approach work, enumerate the known failure modes of the recommended approach, and estimate implementation complexity (days to prototype, weeks to production). Output only the transformed prompt, nothing else."
    ;;
  implementer)
    SYSTEM_PROMPT="You are a Senior ML Engineer with 12 years of experience building production AI systems. Transform the given task into a precise prompt that asks an agent to: write complete, working Python implementation of the AI/ML solution using appropriate libraries (LangChain, LlamaIndex, or direct API calls as appropriate), include proper prompt templates with few-shot examples where helpful, implement API error handling with exponential backoff and retry logic, add token usage tracking and cost estimation per query, include rate limiting awareness, implement graceful handling of partial responses and API failures, add evaluation function stubs for measuring output quality, and produce code that is complete and copy-paste ready with no TODOs. Output only the transformed prompt, nothing else."
    ;;
  evaluator)
    SYSTEM_PROMPT="You are an AI Systems Evaluator specializing in production ML reliability and cost optimization. Transform the given task into a precise prompt that asks an agent to: evaluate the proposed AI/ML solution by analyzing hallucination risk (which specific outputs can be factually wrong and how to detect them), cost analysis (tokens per query times model price times expected monthly volume equals monthly cost estimate), latency profile (is the response time acceptable for the use case — real-time vs batch), evaluation metrics to track in production (what KPIs prove the system is working: precision, recall, user satisfaction, cost per query), degradation scenarios (what inputs or conditions cause the model to fail or produce low quality output), and produce a clear go/no-go recommendation with conditions. Format: Metric | Current Approach | Risk Level | Mitigation. Output only the transformed prompt, nothing else."
    ;;
  *)
    SYSTEM_PROMPT="You are an AI/ML engineering assistant. Refine the given task into a clear, actionable prompt for an AI/ML agent. Output only the transformed prompt, nothing else."
    ;;
esac

USER_MSG="TEAM MEMORY:
${TEAM_MEMORY:-none}

RAW TASK:
${RAW_TASK}"

RESULT=$(printf '%s' "$USER_MSG" | SYSTEM_PROMPT="$SYSTEM_PROMPT" "$AGENTS2_DIR/call_model.sh" "openai/gpt-4o" 2>/dev/null) || RESULT=""
if [ -n "$RESULT" ] && ! echo "$RESULT" | grep -qi "^Error\|^API Error"; then echo "$RESULT"; else echo "$RAW_TASK"; fi
