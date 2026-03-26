#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"

TEAM="aiml"
ROLE1_NAME="researcher"
ROLE2_NAME="implementer"
ROLE3_NAME="evaluator"
AGENT1_MODEL="openai/gpt-4o"
AGENT2_MODEL="deepseek/deepseek-chat"
AGENT3_MODEL="openai/gpt-4o-mini"

TMPFILE=$(mktemp)
WORK_DIR=$(mktemp -d)
trap 'rm -f "$TMPFILE"; rm -rf "$WORK_DIR"' EXIT

if [ ! -t 0 ]; then
  { [ -n "${1:-}" ] && printf '%s\n\n' "$1"; cat; } > "$TMPFILE"
elif [ -n "${1:-}" ]; then
  printf '%s' "$1" > "$TMPFILE"
else
  echo "Error: provide task via argument or stdin" >&2; exit 1
fi

RAW_TASK=$(cat "$TMPFILE")
TASK_SUMMARY="${RAW_TASK:0:120}"

log_action "$TEAM" "lead" "3-parallel" "RUNNING" "$TASK_SUMMARY" "$RAW_TASK"
echo "🔧 [$TEAM] Starting 3-parallel: ${TASK_SUMMARY:0:60}..." >&2

{ echo "$RAW_TASK" | bash "$SCRIPT_DIR/prompt_engineer.sh" "$ROLE1_NAME" > "$WORK_DIR/p1.txt" 2>/dev/null || cp "$TMPFILE" "$WORK_DIR/p1.txt"; } &
{ echo "$RAW_TASK" | bash "$SCRIPT_DIR/prompt_engineer.sh" "$ROLE2_NAME" > "$WORK_DIR/p2.txt" 2>/dev/null || cp "$TMPFILE" "$WORK_DIR/p2.txt"; } &
{ echo "$RAW_TASK" | bash "$SCRIPT_DIR/prompt_engineer.sh" "$ROLE3_NAME" > "$WORK_DIR/p3.txt" 2>/dev/null || cp "$TMPFILE" "$WORK_DIR/p3.txt"; } &
wait

echo "  🤖 [$TEAM] $ROLE1_NAME+$ROLE2_NAME+$ROLE3_NAME running..." >&2

SP1_FILE=$(mktemp)
SP2_FILE=$(mktemp)
SP3_FILE=$(mktemp)
SYNTH_FILE=$(mktemp)
trap 'rm -f "$TMPFILE" "$SP1_FILE" "$SP2_FILE" "$SP3_FILE" "$SYNTH_FILE"; rm -rf "$WORK_DIR"' EXIT

printf '%s' 'You are a Senior AI Research Scientist with 15 years at OpenAI and DeepMind. Your role: research and recommend the best approach for this AI/ML task. Analyze: (1) What technique is best (RAG, fine-tuning, prompt engineering, traditional ML, or hybrid), (2) Which models to use and why (compare at least 3 options with cost/quality/latency), (3) What data or context is needed, (4) Known failure modes of the recommended approach, (5) Implementation complexity estimate. Produce a clear recommendation with justification.' > "$SP1_FILE"

printf '%s' 'You are a Senior ML Engineer with 12 years building production AI systems. Implement the solution completely: working Python code, proper prompt templates (with few-shot examples), API error handling with exponential backoff, token usage tracking, cost estimation per query, evaluation function stubs. Code must handle rate limits, API failures, and partial responses gracefully. Complete, production-ready implementation.' > "$SP2_FILE"

printf '%s' 'You are an AI Systems Evaluator specializing in production ML reliability and cost. Evaluate the AI solution for: hallucination risk (which outputs can be wrong and how to detect?), cost analysis (tokens per query times model price times expected volume = monthly cost estimate), latency (is it acceptable for the use case?), evaluation metrics to track (what KPIs indicate the system is working?), degradation scenarios (what causes the model to fail?). Produce an evaluation report with go/no-go recommendation.' > "$SP3_FILE"

printf '%s' 'You are the AI/ML Team Lead. Combine: Research Recommendation, Implementation Code, and Evaluation Report. Deliver: (1) Technical approach summary (from Researcher), (2) Complete implementation code (from Implementer), (3) Evaluation criteria and monitoring setup (from Evaluator), (4) Cost estimate at scale, (5) Go/No-Go recommendation with conditions. If evaluator flagged serious risks, include mitigations in the implementation.' > "$SYNTH_FILE"

{
  SYSTEM_PROMPT="$(cat "$SP1_FILE")" "$AGENTS2_DIR/call_model.sh" "$AGENT1_MODEL" < "$WORK_DIR/p1.txt" > "$WORK_DIR/r1.txt" 2>/dev/null \
    || printf '[%s/%s failed]' "$TEAM" "$ROLE1_NAME" > "$WORK_DIR/r1.txt"
} &
{
  SYSTEM_PROMPT="$(cat "$SP2_FILE")" "$AGENTS2_DIR/call_model.sh" "$AGENT2_MODEL" < "$WORK_DIR/p2.txt" > "$WORK_DIR/r2.txt" 2>/dev/null \
    || printf '[%s/%s failed]' "$TEAM" "$ROLE2_NAME" > "$WORK_DIR/r2.txt"
} &
{
  SYSTEM_PROMPT="$(cat "$SP3_FILE")" "$AGENTS2_DIR/call_model.sh" "$AGENT3_MODEL" < "$WORK_DIR/p3.txt" > "$WORK_DIR/r3.txt" 2>/dev/null \
    || printf '[%s/%s failed]' "$TEAM" "$ROLE3_NAME" > "$WORK_DIR/r3.txt"
} &
wait

echo "  ✅ [$TEAM] Agents done, synthesizing..." >&2

COMBINED="## [$ROLE1_NAME — $AGENT1_MODEL]
$(cat "$WORK_DIR/r1.txt")

## [$ROLE2_NAME — $AGENT2_MODEL]
$(cat "$WORK_DIR/r2.txt")

## [$ROLE3_NAME — $AGENT3_MODEL]
$(cat "$WORK_DIR/r3.txt")"

RESULT=$(printf '%s' "$COMBINED" | SYSTEM_PROMPT="$(cat "$SYNTH_FILE")" "$AGENTS2_DIR/call_model.sh" "openai/gpt-4o" 2>/dev/null) || RESULT="$COMBINED"
[ -z "$RESULT" ] && RESULT="$COMBINED"

memory_append "$TEAM" "$(date '+%Y-%m-%d'): ${TASK_SUMMARY:0:80}"
log_action "$TEAM" "lead" "3-parallel" "SUCCESS" "$TASK_SUMMARY" "$RAW_TASK" "$RESULT"

RESULT="${RESULT}
---
## 🔍 [$TEAM Team] Self-Assessment
Specialists: Researcher(gpt-4o) + Implementer(deepseek) + Evaluator(gpt-4o-mini)
Additional teams that could add value:
- backend: API integration and serving infrastructure
- data: vector database setup and embedding pipeline
- devops: model serving infrastructure, GPU provisioning
- security: prompt injection protection, data privacy in AI inputs"

echo "  ✅ [$TEAM] Done" >&2
echo "$RESULT"
