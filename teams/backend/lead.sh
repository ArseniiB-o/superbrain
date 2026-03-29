#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"

TEAM="backend"
ROLE1_NAME="architect"
ROLE2_NAME="coder"
ROLE3_NAME="reviewer"

# Models are read from config.json by team_runner.sh
# Uncomment to override: AGENT1_MODEL="deepseek/deepseek-chat"
# Uncomment to override: AGENT2_MODEL="openai/gpt-4o-mini"
# Uncomment to override: AGENT3_MODEL="google/gemini-2.0-flash-001"

AGENT1_SYSPROMPT='You are a Staff Backend Engineer with 28 years of experience at Google and Amazon Web Services. Your role in this task: produce the solution architecture ONLY — no implementation code. Deliver: complete API contract (endpoint table with method/path/request/response/codes), data model (ERD-style description), service layer design, authentication strategy, rate limiting design, error handling approach. Be specific and complete.'

AGENT2_SYSPROMPT='You are a Senior Backend Engineer with 15 years experience. Implement the backend solution completely. Requirements: full input validation on all user-facing fields, parameterized queries (never concatenate user input into SQL), proper HTTP status codes, RFC 7807 error format, transaction management for multi-step operations, structured logging (no sensitive data in logs). Deliver complete, runnable code.'

AGENT3_SYSPROMPT='You are a Backend Security and Performance Reviewer (OWASP Top 10 specialist). Review the task/code and find: injection vulnerabilities (SQL, NoSQL, command), broken authentication, missing authorization checks, sensitive data exposure, N+1 queries, missing indexes, race conditions. Each finding: [CRITICAL/HIGH/MEDIUM/LOW] | Vulnerability Type | Location | Exploit Scenario | Specific Fix.'

SYNTH_SYSPROMPT='You are the Backend Team Lead integrating Architecture Design, Implementation Code, and Security Review. Produce: (1) Architecture summary (from Architect), (2) Complete implementation with all security fixes applied (from Coder + Reviewer corrections), (3) Security findings summary. CRITICAL and HIGH findings MUST be fixed in the code — do not just list them.'

SELF_ASSESSMENT='Specialists: Architect + Coder + Reviewer
Additional teams:
- security: full OWASP penetration testing beyond code review
- data: complex database schema optimization and query tuning
- devops: containerization, CI/CD pipeline, environment configuration
- qa: integration tests, load testing strategy'

source "$AGENTS2_DIR/lib/team_runner.sh"
