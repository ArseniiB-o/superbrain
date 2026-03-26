#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"

TEAM="data"
ROLE1_NAME="designer"
ROLE2_NAME="implementer"
ROLE3_NAME="reviewer"
AGENT1_MODEL="deepseek/deepseek-chat"
AGENT2_MODEL="openai/gpt-4o-mini"
AGENT3_MODEL="google/gemini-2.0-flash-001"

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

printf '%s' 'You are a Principal Data Architect with 25 years of experience at Shopify and Stripe, designing schemas for systems processing billions of transactions. Your role: design the data architecture. Produce: entity-relationship description (all entities, attributes, relationships), normalization decisions with justification, indexing strategy (every index with reason), partitioning plan if applicable, data lifecycle and retention policy. NO SQL yet — produce the design spec.' > "$SP1_FILE"

printf '%s' 'You are a Senior Data Engineer with 15 years experience. Implement the database schema completely. Requirements: proper PostgreSQL data types (timestamptz not timestamp, UUID not INT for IDs, JSONB for flexible data), all constraints defined (NOT NULL, UNIQUE, CHECK, FK with ON DELETE strategy), all indexes created, both UP and DOWN migration scripts, timestamps on all tables (created_at, updated_at using trigger or DEFAULT NOW()), soft delete with deleted_at column.' > "$SP2_FILE"

printf '%s' 'You are a Database Performance and Quality Reviewer. Review schema and queries for: missing indexes (FK columns without index, columns in WHERE clauses without index), missing constraints (NULLable columns that should be NOT NULL), N+1 query patterns, queries without LIMIT on potentially large tables, UUID vs BIGSERIAL decision impact, missing query optimization opportunities. Format: [CRITICAL/HIGH/MEDIUM/LOW] | Issue | Table/Query | Performance Impact | Fix.' > "$SP3_FILE"

printf '%s' 'You are the Data Team Lead. Combine: Data Architecture Design, Schema Implementation, and Performance Review. Deliver: (1) Data architecture summary with ER description, (2) Complete, optimized SQL migrations with all reviewer fixes applied, (3) Index optimization summary, (4) Query performance notes. All CRITICAL/HIGH reviewer findings must be fixed in the SQL.' > "$SYNTH_FILE"

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
Specialists: Designer(deepseek) + Implementer(gpt-4o-mini) + Reviewer(gemini-flash)
Additional teams that could add value:
- backend: ORM integration and query patterns from application layer
- security: data encryption at rest, column-level encryption for PII, audit logging
- devops: database backup strategy, replication setup, connection pooling"

echo "  ✅ [$TEAM] Done" >&2
echo "$RESULT"
