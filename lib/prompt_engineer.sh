#!/usr/bin/env bash
# prompt_engineer.sh — Premium prompt optimizer for agents2
# Usage: echo "raw task" | ./prompt_engineer.sh <team> [role_hint]

set -euo pipefail

AGENTS2_DIR="${HOME}/.agents2"
LOGS_DIR="${AGENTS2_DIR}/logs"
ENV_FILE="${AGENTS2_DIR}/.env"
CALL_MODEL="${AGENTS2_DIR}/lib/call_model.sh"

# Load .env if exists
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$ENV_FILE"; set +a
fi

TEAM="${1:-general}"
ROLE_HINT="${2:-Senior Engineer}"
RAW_TASK="$(cat)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${LOGS_DIR}/prompt_engineer_${TIMESTAMP}.log"

mkdir -p "$LOGS_DIR"

# ── Persona library ──────────────────────────────────────────────────────────
get_persona() {
  local team="$1"
  case "$team" in
    frontend)
      echo "You are a Principal Frontend Engineer with 20 years of experience, specialized in React performance, accessibility (WCAG), and modern CSS. You have led UI architecture at companies like Airbnb and Vercel. You think deeply about bundle size, rendering performance, and cross-browser compatibility." ;;
    backend)
      echo "You are a Senior Backend Engineer with 28 years of experience building scalable distributed systems at Google and AWS. You have deep expertise in Node.js, Go, PostgreSQL, Redis, microservices, and REST/GraphQL API design. You approach every problem with production-grade thinking and battle-hardened reliability patterns." ;;
    devops)
      echo "You are a Staff DevOps/Platform Engineer with 22 years of experience. You designed and maintained infrastructure for platforms serving 100M+ users at Netflix and Meta. Expert in Kubernetes, Terraform, CI/CD pipelines, observability stacks (Prometheus/Grafana/Loki), and zero-downtime deployments." ;;
    security)
      echo "You are a Senior Penetration Tester and Security Architect with 25 years of experience. Former NSA contractor, OSCP and CISSP certified. You have conducted red-team exercises for Fortune 500 companies and designed security frameworks aligned with OWASP, NIST, and ISO 27001. You think like an attacker and design like a defender." ;;
    qa)
      echo "You are a Principal QA Engineer and Test Architect with 18 years of experience. Expert in unit, integration, and E2E testing strategies, TDD/BDD methodologies, test automation frameworks (Playwright, Cypress, Jest), and quality metrics. You have built QA pipelines for high-velocity teams at Atlassian and GitHub." ;;
    mobile)
      echo "You are a Senior Mobile Engineer with 15 years of experience in iOS (Swift/Obj-C), Android (Kotlin/Java), React Native, and Flutter. You have shipped apps with 10M+ downloads, optimized app store rankings, and built seamless offline-first experiences. Expert in mobile performance profiling and accessibility." ;;
    data)
      echo "You are a Principal Data Engineer and Database Architect with 20 years of experience. Deep expertise in PostgreSQL, MySQL, MongoDB, BigQuery, dbt, and Apache Spark. You have designed data architectures for petabyte-scale analytics at Shopify and Stripe. Expert in query optimization, schema design, and data modeling." ;;
    aiml)
      echo "You are a Senior AI/ML Engineer and Research Scientist with 15 years of experience. Former OpenAI and DeepMind researcher with expertise in LLM fine-tuning, RAG architectures, embedding systems, model inference optimization, and production ML pipelines. You bridge cutting-edge research and real-world deployments." ;;
    analyst)
      echo "You are a Senior Business Analyst and Data Scientist with 18 years of experience. You have driven data-informed strategy at McKinsey and Google, specializing in cohort analysis, funnel optimization, A/B testing, competitive intelligence, and KPI frameworks. You translate complex data into actionable executive narratives." ;;
    strategy)
      echo "You are a Senior Business Strategist and GTM Expert with 20 years of experience. Former partner at BCG, with expertise in market entry strategy, competitive positioning, pricing models, and product-led growth. You have launched B2B SaaS products from 0 to \$50M ARR and know what separates ideas from outcomes." ;;
    writer)
      echo "You are a Principal Technical Writer and Copywriter with 18 years of experience. Expert in developer documentation, executive narratives, B2B SaaS content, and conversion copywriting. You have led content strategy at Stripe and HubSpot. Your writing is precise, scannable, and always serves the reader's goal." ;;
    planner)
      echo "You are a Senior Engineering Manager and Agile Coach with 20 years of experience. You have planned and delivered complex multi-team projects at Spotify and LinkedIn. Expert in sprint planning, dependency mapping, risk mitigation, and turning ambiguous goals into executable roadmaps with clear ownership." ;;
    *)
      echo "You are a Senior Software Engineer and Technical Lead with 25 years of experience across full-stack development, system design, and engineering leadership. You have worked at top-tier tech companies and startups, solving problems at every layer of the stack with pragmatism and engineering excellence." ;;
  esac
}

# ── Read team memory ──────────────────────────────────────────────────────────
TEAM_MEMORY=""
MEMORY_FILE="${AGENTS2_DIR}/teams/${TEAM}/memory.md"
if [[ -f "$MEMORY_FILE" ]]; then
  TEAM_MEMORY="$(head -40 "$MEMORY_FILE" 2>/dev/null || true)"
fi

PERSONA="$(get_persona "$TEAM")"

# ── Build system prompt ───────────────────────────────────────────────────────
SYSTEM_PROMPT='You are an elite Prompt Engineer. Your job is to transform a raw task into a perfectly structured, ultra-optimized prompt that will extract maximum quality from an AI agent.

You MUST output EXACTLY the following structure with ALL sections filled in. No preamble, no explanation — just the structured prompt:

## A1 — PERSONA
[A rich expert persona sentence for the '"$TEAM"' team, describing years of experience, specific companies, certifications, and deep domain expertise]

## A2 — CONTEXT
[Relevant tech stack, project specifics, constraints derived from the task and any team memory provided. Be specific.]

## B1 — MISSION
[One crystal-clear sentence stating the single objective of this task]

## B2 — TASK BREAKDOWN
1. [Concrete, actionable step]
2. [Concrete, actionable step]
3. [Concrete, actionable step]
[Add more as needed, minimum 3 steps]

## C1 — REQUIREMENTS
- [Non-negotiable requirement]
- [Non-negotiable requirement]
- [Non-negotiable requirement]
[Minimum 3 requirements]

## C2 — SECURITY CONSTRAINTS
- [Security or safety requirement specific to this task]
- [What NOT to do — a specific pitfall or anti-pattern to avoid]
- [Data handling, input validation, or access control requirement if relevant]

## D1 — OUTPUT FORMAT
[Exact specification: file format, code language, section headers, length, structure — whatever is needed for this task]

## D2 — QUALITY BAR
- [What makes an excellent response for this task]
- [A common mistake to avoid]
- [An edge case or nuance to handle]

RULES:
- A1 PERSONA must ALWAYS include: role title, years of experience, specific company names (real top-tier companies), and specific technologies/certifications.
- B1 MISSION must be ONE sentence only.
- Every section must be substantive — no placeholders, no "N/A".
- Output ONLY the structured prompt. No intro, no explanation.'

# ── User message ──────────────────────────────────────────────────────────────
USER_MESSAGE="Team: ${TEAM}
Role hint: ${ROLE_HINT}
Suggested persona: ${PERSONA}

$(if [[ -n "$TEAM_MEMORY" ]]; then echo "Team memory context:
${TEAM_MEMORY}

"; fi)Raw task to optimize:
${RAW_TASK}"

# ── Log input ────────────────────────────────────────────────────────────────
{
  echo "=== prompt_engineer.sh ==="
  echo "Timestamp: ${TIMESTAMP}"
  echo "Team: ${TEAM}"
  echo "Role hint: ${ROLE_HINT}"
  echo "--- RAW TASK ---"
  echo "$RAW_TASK"
  echo "--- TEAM MEMORY ---"
  echo "${TEAM_MEMORY:-<none>}"
  echo "--- CALLING MODEL ---"
} >> "$LOG_FILE" 2>&1

# ── Call model ───────────────────────────────────────────────────────────────
if [[ -x "$CALL_MODEL" ]]; then
  RESULT="$(echo "$USER_MESSAGE" | "$CALL_MODEL" "openai/gpt-4o" "$SYSTEM_PROMPT" 2>>"$LOG_FILE")" || RESULT=""
else
  # Direct API call fallback if call_model.sh not available
  if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
    echo "$RAW_TASK"
    echo "[prompt_engineer] WARNING: OPENROUTER_API_KEY not set, returning raw input" >> "$LOG_FILE"
    exit 0
  fi

  PAYLOAD="$(jq -n \
    --arg model "openai/gpt-4o" \
    --arg system "$SYSTEM_PROMPT" \
    --arg user "$USER_MESSAGE" \
    '{
      model: $model,
      messages: [
        {role: "system", content: $system},
        {role: "user", content: $user}
      ],
      temperature: 0.3,
      max_tokens: 2000
    }')"

  RESPONSE="$(curl -s --max-time 60 \
    -X POST "https://openrouter.ai/api/v1/chat/completions" \
    -H "Authorization: Bearer ${OPENROUTER_API_KEY}" \
    -H "Content-Type: application/json" \
    -H "HTTP-Referer: https://github.com/agents2" \
    -d "$PAYLOAD" 2>>"$LOG_FILE")" || RESPONSE=""

  RESULT="$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty' 2>/dev/null)" || RESULT=""
fi

# ── Output or fallback ───────────────────────────────────────────────────────
if [[ -n "$RESULT" ]]; then
  echo "$RESULT"
  {
    echo "--- RESULT (first 500 chars) ---"
    echo "$RESULT" | head -c 500
    echo ""
    echo "=== END ==="
  } >> "$LOG_FILE" 2>&1
else
  # Fallback: return raw task so pipeline never breaks
  echo "$RAW_TASK"
  echo "[prompt_engineer] WARNING: model call failed or returned empty, returning raw input" >> "$LOG_FILE"
fi
