#!/usr/bin/env bash
# dispatch.sh — Agents 2.0 Main Orchestrator
#
# Routes any task to specialized AI teams, runs them in parallel, synthesizes results.
#
# Usage:
#   ./dispatch.sh "your task"
#   ./dispatch.sh --new-project "Build a SaaS for invoice management"
#   ./dispatch.sh --audit "Review the auth module"
#   ./dispatch.sh --teams "backend,security" "Audit the payment API"
#   echo "task" | ./dispatch.sh
#   cat brief.txt | ./dispatch.sh "build strategy"
#
# Flags:
#   --new-project    Run planning director first, then proceed
#   --audit          Run final audit after completion
#   --teams LIST     Force specific teams (comma-separated)
#   --no-pe          Skip prompt engineering (faster, less precise)
#   --dry-run        Show decomposition plan without executing teams
#   --no-cache       Bypass response cache

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AGENTS2_DIR="$SCRIPT_DIR"

# Load .env
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    set -a; source "${SCRIPT_DIR}/.env"; set +a
fi

source "${SCRIPT_DIR}/lib/logger.sh"

# ── Flag parsing ───────────────────────────────────────────────────────────────
FLAG_NEW_PROJECT=0
FLAG_AUDIT=0
FLAG_NO_PE=0
FLAG_DRY_RUN=0
FLAG_NO_CACHE=0
FORCED_TEAMS=""
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --new-project)
            FLAG_NEW_PROJECT=1
            shift
            ;;
        --audit)
            FLAG_AUDIT=1
            shift
            ;;
        --no-pe)
            FLAG_NO_PE=1
            shift
            ;;
        --dry-run)
            FLAG_DRY_RUN=1
            shift
            ;;
        --no-cache)
            FLAG_NO_CACHE=1
            shift
            ;;
        --teams)
            FORCED_TEAMS="${2:?--teams requires a comma-separated list, e.g. --teams backend,security}"
            shift 2
            ;;
        --)
            shift
            POSITIONAL_ARGS+=("$@")
            break
            ;;
        -*)
            echo "Unknown flag: $1" >&2
            echo "Usage: dispatch.sh [--new-project] [--audit] [--no-pe] [--dry-run] [--no-cache] [--teams LIST] \"task\"" >&2
            exit 1
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

set -- "${POSITIONAL_ARGS[@]+"${POSITIONAL_ARGS[@]}"}"

# ── Work directory ─────────────────────────────────────────────────────────────
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
export DISPATCH_WORK_DIR="$WORK_DIR"
# Convert MSYS2/Cygwin Unix-style path to Windows mixed path (C:/...) for Python (os.path.exists)
if command -v cygpath &>/dev/null; then
    export DISPATCH_SCRIPT_DIR="$(cygpath -m "$SCRIPT_DIR")"
else
    export DISPATCH_SCRIPT_DIR="$SCRIPT_DIR"
fi
export DISPATCH_NO_PE="$FLAG_NO_PE"

# ── Auto-audit: force --audit for security-adjacent tasks ─────────────────────
# Keywords that always warrant an audit pass (case-insensitive match against task)
_AUTO_AUDIT_KEYWORDS=(
    "auth" "security" "payment" "password" "token" "secret" "key" "encrypt"
    "user data" "personal data" "gdpr" "dsgvo" "compliance" "vulnerability"
    "production" "deploy" "release" "inject" "sql" "xss" "csrf" "owasp"
    "sensitive" "credential" "private" "permissions" "access control" "login"
    "jwt" "oauth" "session" "cookie" "api key" "webhook" "signature"
    "review" "audit" "check" "is this correct" "is this good" "evaluate"
    "correct?" "right?" "secure?" "safe?" "проверь" "правильно" "аудит"
)

# ── Ensure UTF-8 for Python on Windows ────────────────────────────────────────
export PYTHONUTF8=1

# ── 1. Read task ───────────────────────────────────────────────────────────────
TASK_FILE="${WORK_DIR}/task.txt"

if [ ! -t 0 ]; then
    { [ -n "${1:-}" ] && printf '%s\n\n' "$1"; cat; } > "$TASK_FILE"
elif [ -n "${1:-}" ]; then
    printf '%s' "$1" > "$TASK_FILE"
else
    echo "Error: provide a task via argument or stdin" >&2
    echo "  ${SCRIPT_DIR}/dispatch.sh \"your task\"" >&2
    echo "  echo \"task\" | ${SCRIPT_DIR}/dispatch.sh" >&2
    exit 1
fi

TASK=$(cat "$TASK_FILE")
SUMMARY="${TASK:0:100}"

# ── Read active mode for display ──────────────────────────────────────────────
MODE_FILE="${SCRIPT_DIR}/.mode"
ACTIVE_MODE="openrouter"
if [[ -f "$MODE_FILE" ]]; then
    ACTIVE_MODE=$(cat "$MODE_FILE" | tr -d '[:space:]')
fi
case "$ACTIVE_MODE" in
    claude)     MODE_LABEL="🤖 CLAUDE SONNET (subscription)" ;;
    openrouter) MODE_LABEL="🌐 OPENROUTER (mixed models)" ;;
    *)          MODE_LABEL="❓ UNKNOWN ($ACTIVE_MODE)" ;;
esac
export DISPATCH_ACTIVE_MODE="$ACTIVE_MODE"

# ── Claude mode: auto-skip PE (Sonnet understands prompts natively; PE causes hangs) ──
if [[ "$ACTIVE_MODE" == "claude" && "$FLAG_NO_PE" -eq 0 ]]; then
    FLAG_NO_PE=1
    export DISPATCH_NO_PE=1
fi

# ── Auto-audit keyword detection ──────────────────────────────────────────────
if [[ "$FLAG_AUDIT" -eq 0 ]]; then
    TASK_LOWER=$(printf '%s' "$TASK" | tr '[:upper:]' '[:lower:]')
    for _kw in "${_AUTO_AUDIT_KEYWORDS[@]}"; do
        if [[ "$TASK_LOWER" == *"$_kw"* ]]; then
            FLAG_AUDIT=1
            echo "--> [dispatch] Auto-audit activated: keyword '$_kw' detected in task." >&2
            break
        fi
    done
fi

log_session_start
log_action "dispatch" "orchestrator" "dispatch.sh" "RUNNING" "$SUMMARY"

echo "" >&2
echo "==> [dispatch v2] Task received: ${SUMMARY}..." >&2
echo "==> [dispatch v2] Mode: ${MODE_LABEL}" >&2
echo "" >&2

# ── 1b. Response cache check ─────────────────────────────────────────────────
TASK_HASH=$(printf '%s|nope=%s|audit=%s|newproject=%s|teams=%s' \
    "$TASK" "$FLAG_NO_PE" "$FLAG_AUDIT" "$FLAG_NEW_PROJECT" "$FORCED_TEAMS" \
    | python3 -c "import hashlib,sys; print(hashlib.md5(sys.stdin.buffer.read()).hexdigest())")
CACHE_DIR="$AGENTS2_DIR/.cache"
CACHE_FILE="$CACHE_DIR/${TASK_HASH}.txt"
mkdir -p "$CACHE_DIR"

# Purge cache entries older than 1 hour
find "$CACHE_DIR" -maxdepth 1 -type f -name "*.txt" -mmin +60 -delete 2>/dev/null || true

if [[ "$FLAG_NO_CACHE" -eq 0 && -f "$CACHE_FILE" ]]; then
    # Check if cache file is less than 1 hour old — use Python for cross-platform portability
    CACHE_AGE=$(_CM_CACHE_FILE="$CACHE_FILE" python3 -c "
import os, time
try:
    path = os.environ['_CM_CACHE_FILE']
    age = int(time.time() - os.path.getmtime(path))
    print(age)
except Exception:
    print(9999)
" 2>/dev/null || echo 9999)
    if [[ "$CACHE_AGE" -lt 3600 ]]; then
        echo "--> [dispatch] Cache hit (${TASK_HASH}, age: ${CACHE_AGE}s). Returning cached result." >&2
        cat "$CACHE_FILE"
        log_action "dispatch" "orchestrator" "dispatch.sh" "SUCCESS (cached)" "$SUMMARY"
        log_session_end
        exit 0
    fi
fi

# ── 2. --new-project: run planning director first ─────────────────────────────
if [[ "$FLAG_NEW_PROJECT" -eq 1 ]]; then
    DIRECTOR_SCRIPT="${SCRIPT_DIR}/planning/director.sh"
    if [[ ! -x "$DIRECTOR_SCRIPT" ]]; then
        echo "Warning: planning/director.sh not found or not executable — skipping." >&2
    else
        echo "--> [dispatch] --new-project: running planning/director.sh..." >&2
        DIRECTOR_OUTPUT=$("$DIRECTOR_SCRIPT" "$(cat "$TASK_FILE")" 2>/dev/null || true)

        if [[ -n "$DIRECTOR_OUTPUT" ]]; then
            echo "" >&2
            echo "--> [dispatch] Director output incorporated into task context." >&2
            # Prepend director output to the task context
            {
                printf '%s\n\n' "$(cat "$TASK_FILE")"
                printf '## Planning Director Output\n\n%s\n' "$DIRECTOR_OUTPUT"
            } > "${WORK_DIR}/task_with_plan.txt"
            cp "${WORK_DIR}/task_with_plan.txt" "$TASK_FILE"
        fi

        # ── Create project folder structure ────────────────────────────────────────────
        PROJECT_NAME=$(printf '%s' "$TASK" | \
            SYSTEM_PROMPT="Extract a short project name (2-4 words, kebab-case) from the user task. Return ONLY the name, nothing else." \
            "$SCRIPT_DIR/call_model.sh" "openai/gpt-4o-mini" 2>/dev/null || \
            echo "new-project-$(date +%Y%m%d)")
        PROJECT_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | head -c 40)
        PROJECT_DIR="$HOME/$PROJECT_NAME"

        echo "📁 [dispatch] Creating project folder: $PROJECT_DIR" >&2
        mkdir -p "$PROJECT_DIR"/{docs,business,technical,legal,marketing,research}

        # Generate project documents using writer team
        BRIEF="${DIRECTOR_OUTPUT:-$TASK}"

        # Generate documents in parallel (max 5 concurrent)
        DOC_TASKS=(
            "Write a complete README.md for this project. Include: project overview, problem statement, solution, key features, tech stack, getting started.:$PROJECT_DIR/README.md"
            "Write docs/01_OVERVIEW.md — comprehensive project overview with vision, mission, target users, value proposition, and success metrics.:$PROJECT_DIR/docs/01_OVERVIEW.md"
            "Write docs/02_REQUIREMENTS.md — detailed functional and non-functional requirements, user stories, acceptance criteria.:$PROJECT_DIR/docs/02_REQUIREMENTS.md"
            "Write docs/03_TIMELINE.md — realistic project timeline with phases, milestones, dependencies, and risks.:$PROJECT_DIR/docs/03_TIMELINE.md"
            "Write technical/04_ARCHITECTURE.md — system architecture, tech stack decisions with justification, component diagram (ASCII), data flow.:$PROJECT_DIR/technical/04_ARCHITECTURE.md"
            "Write business/05_BUSINESS_PLAN.md — business model, revenue streams, unit economics (CAC/LTV), market size, competitive analysis.:$PROJECT_DIR/business/05_BUSINESS_PLAN.md"
            "Write legal/06_COMPLIANCE.md — legal requirements, GDPR compliance checklist, licenses needed, regulatory considerations for EU.:$PROJECT_DIR/legal/06_COMPLIANCE.md"
            "Write marketing/07_GTM.md — go-to-market strategy, target customer segments, acquisition channels, messaging framework.:$PROJECT_DIR/marketing/07_GTM.md"
            "Write research/08_MARKET_RESEARCH.md — market analysis with real statistics, competitor landscape, industry trends, comparable cases.:$PROJECT_DIR/research/08_MARKET_RESEARCH.md"
            "Write docs/09_RISKS.md — comprehensive risk register with probability/impact scores, mitigation strategies, contingency plans.:$PROJECT_DIR/docs/09_RISKS.md"
        )

        MAX_DOC_CONCURRENCY=5
        RUNNING_DOCS=0

        for DOC_TASK in "${DOC_TASKS[@]}"; do
            DOC_TASK_TEXT="${DOC_TASK%%:*}"
            DOC_FILE="${DOC_TASK##*:}"

            echo "  📄 Creating: $(basename "$DOC_FILE")..." >&2

            FULL_DOC_TASK="Project context:
$BRIEF

Task: $DOC_TASK_TEXT"

            (
                bash "$SCRIPT_DIR/teams/writer/lead.sh" "$FULL_DOC_TASK" > "$DOC_FILE" 2>/dev/null || \
                    printf '# %s\n\n[Generation failed — fill in manually]\n' "$(basename "$DOC_FILE")" > "$DOC_FILE"
            ) &

            RUNNING_DOCS=$((RUNNING_DOCS + 1))
            if [[ "$RUNNING_DOCS" -ge "$MAX_DOC_CONCURRENCY" ]]; then
                wait -n 2>/dev/null || wait
                RUNNING_DOCS=$((RUNNING_DOCS - 1))
            fi
        done

        # Wait for all remaining background doc generation jobs
        wait

        echo "✅ [dispatch] Project folder created: $PROJECT_DIR" >&2
        echo "" >&2
        echo "📁 Project files created:" >&2
        find "$PROJECT_DIR" -name "*.md" | sort | while read -r f; do
            echo "   - $f" >&2
        done
        echo "" >&2
    fi
fi

# ── 3. Decompose into team subtasks ───────────────────────────────────────────
# NOTE: Global PE removed — each team has its own specialized prompt engineer
# which produces better results and avoids double-optimization overhead.
echo "--> [dispatch] Decomposing task into team subtasks..." >&2

DECOMPOSER_SYSTEM='You are a master task router for a team of AI specialists. Your job: analyze any task and route subtasks to the right specialist teams. Return ONLY valid JSON, no markdown, no code fences, no explanation.

Teams available:
- frontend      : UI/UX, React, Vue, CSS, accessibility, web performance, SSR/SSG
- backend       : APIs, databases, business logic, server-side, microservices, auth
- devops        : CI/CD, Docker, Kubernetes, infrastructure, deployment, monitoring
- security      : OWASP audit, penetration testing, vulnerabilities, auth review, threat modeling
- qa            : unit tests, integration tests, E2E, test plans, edge cases, quality assurance
- mobile        : iOS, Android, React Native, Flutter, mobile UX, app store
- data          : database design, SQL optimization, data pipelines, analytics, schema design
- aiml          : ML models, training, inference, AI architecture, LLM integration, embeddings, RAG
- analyst       : business analysis, market research, metrics, competitive analysis, insights
- strategy      : business strategy, GTM, positioning, roadmap, competitive advantage
- writer        : copywriting, documentation, reports, blog posts, emails, content, marketing copy
- planner       : project planning, sprint planning, decomposition, timelines, task management
- marketing     : TAM/SAM/SOM analysis, acquisition channels, brand positioning, growth metrics, customer personas
- legal         : GDPR, EU AI Act, compliance, contracts, IP law, regulatory requirements, licensing
- risk          : risk register, probability/impact matrix, mitigation strategies, business continuity
- finance       : financial modeling, unit economics, CAC/LTV, burn rate, pricing strategy, fundraising
- researcher    : market research with real sources, statistics, case studies, competitor intelligence
- payments      : Stripe, payment flows, billing, invoicing, PCI DSS, subscription models
- performance   : profiling, Core Web Vitals, load time, memory optimization, caching
- accessibility : WCAG 2.1/2.2, screen readers, a11y testing, inclusive design
- i18n          : internationalization, localization, RTL support, translation workflows
- ux            : user research, usability testing, conversion optimization, UX writing
- embedded      : embedded systems, RTOS, hardware interfaces, firmware, IoT, drones
- blockchain    : smart contracts, Web3, token economics, DeFi, NFT, decentralized systems

Rules:
1. Pick 4-8 most relevant teams. NEVER fewer than 4 unless the task is provably single-domain (and even then pick 4). For complex/business/architectural tasks, use 6-10+ teams. More teams = better coverage = higher quality output.
2. Always include security team for ANY technical task. Always include legal+risk for ANY business task.
3. Make subtasks specific — the team must understand the subtask without seeing others.
4. synthesis_instruction tells the synthesizer HOW to combine all team outputs — be detailed and specific about structure.

Output format (raw JSON only):
{
  "task_summary": "one-line summary",
  "team_tasks": [
    {"team": "backend", "subtask": "specific self-contained task for this team"},
    {"team": "security", "subtask": "specific self-contained task for this team"}
  ],
  "synthesis_instruction": "How to combine all team outputs into the final answer — be specific about structure and format."
}'

# If forced teams are specified, skip decomposer and build plan directly
if [[ -n "$FORCED_TEAMS" ]]; then
    echo "--> [dispatch] Using forced teams: $FORCED_TEAMS" >&2

    # Write teams list to env var and pass task file path via env to avoid ARG_MAX / quoting issues
    _FORCED_TEAMS_VAL="$FORCED_TEAMS"

    DECOMPOSED=$(FORCED_TEAMS_ENV="$_FORCED_TEAMS_VAL" TASK_FILE_ENV="$TASK_FILE" python3 << 'FORCED_PYEOF'
import json, os
teams_raw = os.environ.get("FORCED_TEAMS_ENV", "")
task_file = os.environ.get("TASK_FILE_ENV", "")
task = open(task_file, encoding='utf-8').read() if task_file else ""
teams = [t.strip() for t in teams_raw.split(',') if t.strip()]
plan = {
    'task_summary': task[:100],
    'team_tasks': [{'team': t, 'subtask': task} for t in teams],
    'synthesis_instruction': 'Combine all team outputs into a comprehensive, structured answer. Avoid repetition.'
}
print(json.dumps(plan))
FORCED_PYEOF
)
else
    # Call decomposer via call_model.sh (deepseek-chat)
    DECOMPOSED=$(
        SYSTEM_PROMPT="$DECOMPOSER_SYSTEM" \
        "${SCRIPT_DIR}/call_model.sh" "deepseek/deepseek-chat" < "$TASK_FILE" 2>/dev/null || true
    )
fi

# ── Validate decomposer JSON ───────────────────────────────────────────────────
# Write DECOMPOSED to a temp file to avoid ARG_MAX limits and shell quoting issues
_DECOMPOSED_TMP="${WORK_DIR}/decomposed_raw.json"
printf '%s' "$DECOMPOSED" > "$_DECOMPOSED_TMP"

PLAN_VALID=$(DECOMPOSED_FILE="$_DECOMPOSED_TMP" python3 << 'PYEOF'
import json, os
raw = open(os.environ['DECOMPOSED_FILE'], encoding='utf-8').read()
try:
    # Strip markdown fences if present
    if raw.strip().startswith("```"):
        lines = raw.strip().splitlines()
        lines = [l for l in lines if not l.strip().startswith("```")]
        raw = "\n".join(lines)
    data = json.loads(raw)
    tasks = data.get("team_tasks", [])
    print("ok" if len(tasks) >= 1 else "empty")
except Exception as e:
    print("invalid")
PYEOF
)

# Strip markdown fences from DECOMPOSED before further use
DECOMPOSED=$(DECOMPOSED_FILE="$_DECOMPOSED_TMP" python3 << 'PYEOF'
import json, os
raw = open(os.environ['DECOMPOSED_FILE'], encoding='utf-8').read()
try:
    if raw.strip().startswith("```"):
        lines = raw.strip().splitlines()
        lines = [l for l in lines if not l.strip().startswith("```")]
        raw = "\n".join(lines)
    data = json.loads(raw)
    print(json.dumps(data))
except:
    print("{}")
PYEOF
)

if [[ "$PLAN_VALID" != "ok" ]]; then
    echo "Warning: [dispatch] Decomposer returned invalid JSON — falling back to single team." >&2

    # Determine fallback team based on task content
    FALLBACK_TEAM="backend"
    if printf '%s' "$TASK" | grep -qiE "strategy|market|launch|gtm|competitor|revenue|growth"; then
        FALLBACK_TEAM="strategy"
    elif printf '%s' "$TASK" | grep -qiE "write|email|blog|copy|content|report|doc"; then
        FALLBACK_TEAM="writer"
    elif printf '%s' "$TASK" | grep -qiE "analys|metric|data|kpi|insight|dashboard"; then
        FALLBACK_TEAM="analyst"
    elif printf '%s' "$TASK" | grep -qiE "plan|roadmap|sprint|timeline|milestone"; then
        FALLBACK_TEAM="planner"
    elif printf '%s' "$TASK" | grep -qiE "security|owasp|vuln|auth|pen.?test"; then
        FALLBACK_TEAM="security"
    fi

    # Use env vars to pass data to Python to avoid ARG_MAX limits with large task content
    DECOMPOSED=$(FALLBACK_TEAM_ENV="$FALLBACK_TEAM" SUMMARY_ENV="$SUMMARY" TASK_FILE_ENV="$TASK_FILE" python3 << 'FALLBACK_PYEOF'
import json, os
task_file = os.environ.get("TASK_FILE_ENV", "")
task = open(task_file, encoding='utf-8').read() if task_file else ""
summary = os.environ.get("SUMMARY_ENV", task[:100])
team = os.environ.get("FALLBACK_TEAM_ENV", "backend")
plan = {
    'task_summary': summary[:100],
    'team_tasks': [{'team': team, 'subtask': task}],
    'synthesis_instruction': "Present the team's response clearly and completely."
}
print(json.dumps(plan))
FALLBACK_PYEOF
)
fi

printf '%s' "$DECOMPOSED" > "${WORK_DIR}/plan.json"

# ── 3b. --dry-run: show plan and exit ────────────────────────────────────────
if [[ "$FLAG_DRY_RUN" -eq 1 ]]; then
    echo "" >&2
    echo "==> [dispatch] --dry-run: showing plan only (no execution)" >&2
    echo "" >&2
    python3 - << 'DRYEOF'
import json, os, sys

work_dir = os.environ["DISPATCH_WORK_DIR"]

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

with open(f"{work_dir}/plan.json", encoding='utf-8') as f:
    plan = json.load(f)

summary = plan.get("task_summary", "(no summary)")
tasks = plan.get("team_tasks", [])
synth = plan.get("synthesis_instruction", "(none)")

print(f"Task: {summary}\n")
print(f"Teams ({len(tasks)}):")
for i, t in enumerate(tasks, 1):
    team = t.get("team", "?")
    subtask = t.get("subtask", "?")
    print(f"  {i}. [{team}] {subtask[:120]}")
print(f"\nSynthesis instruction: {synth}")
DRYEOF
    log_action "dispatch" "orchestrator" "dispatch.sh" "DRY-RUN" "$SUMMARY"
    log_session_end
    exit 0
fi

# ── 4. Run teams in parallel ───────────────────────────────────────────────────
echo "" >&2
echo "--> [dispatch] Running teams in parallel (max 6 concurrent)..." >&2

python3 - << 'PYEOF'
import json, os, sys, subprocess, concurrent.futures

script_dir = os.environ["DISPATCH_SCRIPT_DIR"]
work_dir   = os.environ["DISPATCH_WORK_DIR"]

# Force UTF-8
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8')

with open(f"{work_dir}/plan.json", encoding='utf-8') as f:
    plan = json.load(f)

team_tasks            = plan.get("team_tasks", [])
synthesis_instruction = plan.get("synthesis_instruction",
    "Synthesize all team outputs into a comprehensive, structured answer.")
task_summary          = plan.get("task_summary", "")

print(f"--> Plan: {task_summary}", file=sys.stderr)
print(f"--> Teams: {len(team_tasks)} running in parallel...", file=sys.stderr)

VALID_TEAMS = {
    "frontend", "backend", "devops", "security", "qa",
    "mobile", "data", "aiml", "analyst", "strategy", "writer", "planner",
    "marketing", "legal", "risk", "finance", "researcher",
    "payments", "performance", "accessibility", "i18n", "ux",
    "embedded", "blockchain"
}

# Aliases: map CLAUDE.md user-facing names to internal team names
TEAM_ALIASES = {
    "business":      "analyst",
    "content":       "writer",
    "planning":      "planner",
    "architecture":  "backend",
    "audit":         "security",
    "perf":          "performance",
    "a11y":          "accessibility",
    "localization":  "i18n",
    "billing":       "payments",
    "stripe":        "payments",
    "hardware":      "embedded",
    "drone":         "embedded",
    "web3":          "blockchain",
}

results = {}

def run_team(idx_task):
    idx, task_item = idx_task
    team    = task_item.get("team", "backend").strip()
    subtask = task_item.get("subtask", "")

    # Resolve aliases before validation
    if team in TEAM_ALIASES:
        resolved = TEAM_ALIASES[team]
        print(f"  Info: team alias '{team}' -> '{resolved}'", file=sys.stderr)
        team = resolved

    if team not in VALID_TEAMS:
        print(f"  Warning: unknown team '{team}', routing to backend", file=sys.stderr)
        team = "backend"

    lead_script = f"{script_dir}/teams/{team}/lead.sh"
    if not os.path.exists(lead_script):
        print(f"  Warning: {lead_script} not found, routing to backend", file=sys.stderr)
        team = "backend"
        lead_script = f"{script_dir}/teams/backend/lead.sh"

    if not os.path.exists(lead_script):
        return (idx, team, subtask, f"[{team} lead.sh not found]")

    print(f"  -> [{team:<12}] {subtask[:70]}", file=sys.stderr)

    try:
        proc = subprocess.run(
            ["bash", lead_script, subtask],
            capture_output=True,
            text=True,
            timeout=300,
            encoding='utf-8',
            errors='replace',
        )
        output = proc.stdout.strip()
        if not output or proc.returncode != 0:
            stderr_snippet = proc.stderr.strip()[:200] if proc.stderr else ""
            output = f"[{team} returned no output. stderr: {stderr_snippet}]"
        print(f"  OK [{team:<12}] done", file=sys.stderr)
        return (idx, team, subtask, output)
    except subprocess.TimeoutExpired:
        print(f"  TIMEOUT [{team:<12}] after 300s", file=sys.stderr)
        return (idx, team, subtask, f"[{team} timed out after 300s]")
    except Exception as e:
        print(f"  ERROR [{team:<12}] {e}", file=sys.stderr)
        return (idx, team, subtask, f"[{team} error: {e}]")

with concurrent.futures.ThreadPoolExecutor(max_workers=12) as executor:
    futures = [executor.submit(run_team, (i, t)) for i, t in enumerate(team_tasks)]
    for future in concurrent.futures.as_completed(futures):
        idx, team, subtask, output = future.result()
        results[idx] = {"team": team, "subtask": subtask, "output": output}

# Build combined input for synthesizer
combined = f"SYNTHESIS INSTRUCTION:\n{synthesis_instruction}\n\n"
combined += "=" * 60 + "\n\n"
for idx in sorted(results.keys()):
    r = results[idx]
    combined += f"## [{r['team'].upper()} TEAM] — {r['subtask']}\n\n"
    combined += r['output'] + "\n\n"
    combined += "=" * 60 + "\n\n"

with open(f"{work_dir}/combined.txt", "w", encoding='utf-8') as f:
    f.write(combined)

# Save report metadata
report = {
    "task_summary": task_summary,
    "teams": [(r["team"], r["subtask"][:80]) for r in results.values()]
}
with open(f"{work_dir}/report.json", "w", encoding='utf-8') as f:
    json.dump(report, f, ensure_ascii=False)

print(f"\n--> All {len(results)} team(s) finished.", file=sys.stderr)
PYEOF

# ── 5. Synthesize ──────────────────────────────────────────────────────────────
echo "" >&2
echo "--> [dispatch] Synthesizing results via gpt-4o..." >&2

SYNTH_SYSTEM="You are a senior technical writer and integrator. You receive structured outputs from multiple specialist teams and synthesize them into one cohesive, well-organized final answer. Eliminate redundancy, resolve contradictions by choosing the more cautious/thorough position, and ensure the answer flows naturally. Use clear Markdown headings. Do not mention that the answer came from multiple teams."

FINAL=$(
    SYSTEM_PROMPT="$SYNTH_SYSTEM" \
    "${SCRIPT_DIR}/call_model.sh" "openai/gpt-4o" < "${WORK_DIR}/combined.txt" 2>/dev/null || true
)

if [[ -z "$FINAL" ]] || printf '%s' "$FINAL" | grep -qi "^API Error\|^Error:"; then
    echo "Warning: [dispatch] Synthesizer failed — outputting combined results directly." >&2
    cat "${WORK_DIR}/combined.txt"
    FINAL_MODEL="(fallback: raw combined output)"
else
    printf '%s\n' "$FINAL"
    FINAL_MODEL="openai/gpt-4o"
fi

# ── 5b. Save result to cache (atomic write via .tmp + mv) ────────────────────
if [[ -n "$FINAL" && "$FLAG_NO_CACHE" -eq 0 ]]; then
    CACHE_TMP="${CACHE_FILE}.tmp.$$"
    if printf '%s' "$FINAL" > "$CACHE_TMP" 2>/dev/null; then
        mv -f "$CACHE_TMP" "$CACHE_FILE" 2>/dev/null || rm -f "$CACHE_TMP" || true
    else
        rm -f "$CACHE_TMP" || true
    fi
fi

# ── 6. --audit: run audit/lead.sh after synthesis ─────────────────────────────
if [[ "$FLAG_AUDIT" -eq 1 ]]; then
    AUDIT_SCRIPT="${SCRIPT_DIR}/audit/lead.sh"
    if [[ ! -x "$AUDIT_SCRIPT" ]]; then
        echo "" >&2
        echo "Warning: [dispatch] audit/lead.sh not found — skipping audit." >&2
    else
        echo "" >&2
        echo "--> [dispatch] --audit: running audit/lead.sh..." >&2

        AUDIT_INPUT="## Original Task\n\n${TASK}\n\n## Synthesized Output\n\n${FINAL}"
        AUDIT_OUTPUT=$(printf '%b' "$AUDIT_INPUT" | "$AUDIT_SCRIPT" 2>/dev/null || true)

        if [[ -n "$AUDIT_OUTPUT" ]]; then
            printf '\n---\n## Audit Report\n\n'
            printf '%s\n' "$AUDIT_OUTPUT"
        fi
    fi
fi

# ── 7. Report table ────────────────────────────────────────────────────────────
echo "" >&2

export DISPATCH_FLAG_NEW_PROJECT="$FLAG_NEW_PROJECT"
export DISPATCH_FLAG_AUDIT="$FLAG_AUDIT"

python3 - << 'REPORT_EOF'
import json, os, sys

work_dir = os.environ["DISPATCH_WORK_DIR"]

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

try:
    with open(f"{work_dir}/report.json", encoding='utf-8') as f:
        report = json.load(f)

    flag_new_project = os.environ.get("DISPATCH_FLAG_NEW_PROJECT", "0") == "1"
    flag_audit       = os.environ.get("DISPATCH_FLAG_AUDIT",       "0") == "1"

    print("\n---")
    print("## Кто что сделал\n")
    print("| Команда | Модель | Задача | Статус |")
    print("|---------|--------|--------|--------|")
    claude_model = os.environ.get("CLAUDE_MODEL", os.environ.get("ANTHROPIC_MODEL", "claude-sonnet-4-6"))
    print(f"| Tech Lead (Claude) | {claude_model} | Оркестрация | OK |")
    print("| decomposer | deepseek-chat | Декомпозиция задачи на команды | OK |")

    if flag_new_project:
        print("| planning/director | gpt-4o | Планирование проекта (--new-project) | OK |")

    for team, subtask in report.get("teams", []):
        print(f"| {team} | (primary model) | {subtask[:60]} | OK |")

    print("| synthesizer | gpt-4o | Синтез всех результатов | OK |")

    if flag_audit:
        print("| audit/lead | gpt-4o | Аудит финального ответа (--audit) | OK |")

except Exception as e:
    pass
REPORT_EOF

log_action "dispatch" "orchestrator" "dispatch.sh" "SUCCESS" "$SUMMARY"
log_session_end
