<div align="center">

# ⚡ SuperBrain

**Multi-model AI orchestration framework with team-based parallel execution**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.0.0-green.svg)](https://github.com/ArseniiB-o/superbrain/releases)
[![Shell](https://img.shields.io/badge/shell-bash-lightgrey.svg)](https://www.gnu.org/software/bash/)
[![Models](https://img.shields.io/badge/models-OpenRouter-orange.svg)](https://openrouter.ai)

</div>

---

SuperBrain is a production-grade multi-model orchestration framework that routes complex tasks to specialized AI teams, runs three parallel specialists per team, and synthesizes outputs into a single authoritative result.

Instead of sending every task to a single model, SuperBrain decomposes work into domain-specific subtasks, assigns each to a team of three parallel specialists (each on the best model for their role), and merges everything through a dedicated synthesizer.

---

## Architecture

```
User Task
    │
    ▼
┌─────────────────────────────────────────────┐
│          Global Prompt Engineer              │  ← optimizes the raw input
│             (gpt-4o)                         │
└─────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────┐
│              Decomposer                      │  ← breaks task into team subtasks
│             (deepseek-chat)                  │
└─────────────────────────────────────────────┘
    │
    ▼  (up to 6 teams in parallel)
┌────────────┐  ┌────────────┐  ┌────────────┐
│  Team A    │  │  Team B    │  │  Team C    │
│ 3 parallel │  │ 3 parallel │  │ 3 parallel │
│ specialists│  │ specialists│  │ specialists│
└────────────┘  └────────────┘  └────────────┘
    │
    ▼
┌─────────────────────────────────────────────┐
│              Synthesizer                     │  ← merges all team outputs
│              (gpt-4o)                        │
└─────────────────────────────────────────────┘
    │
    ▼
 Final Answer
```

### Inside each team

Each team runs a **3-phase internal pipeline**:

1. **Phase 1 — Prompt Engineering** (parallel): Three role-specific prompt engineers optimize the task for each specialist's context
2. **Phase 2 — Specialist Execution** (parallel): Three specialists with different models and roles work simultaneously
3. **Phase 3 — Team Synthesis**: Internal gpt-4o synthesizer merges the three outputs

---

## Teams

| Team | Specialists | Domain |
|------|-------------|--------|
| `frontend` | designer · coder · reviewer | React, Vue, CSS, accessibility, web performance |
| `backend` | architect · coder · reviewer | APIs, databases, microservices, Node.js, Go |
| `devops` | designer · implementer · reviewer | CI/CD, Docker, Kubernetes, Terraform, monitoring |
| `security` | attacker · defender · auditor | OWASP, penetration testing, threat modeling |
| `qa` | analyst · writer · reviewer | Unit/integration/E2E tests, test plans, coverage |
| `mobile` | designer · coder · reviewer | iOS, Android, React Native, Flutter |
| `data` | designer · implementer · reviewer | PostgreSQL, MongoDB, BigQuery, data pipelines |
| `aiml` | researcher · implementer · evaluator | LLMs, RAG, embeddings, ML pipelines |
| `analyst` | researcher · analyst · advisor | Business metrics, KPIs, cohort analysis |
| `strategy` | researcher · strategist · critic | GTM, competitive positioning, B2B SaaS |
| `writer` | researcher · drafter · editor | Documentation, copywriting, content |
| `planner` | analyst · planner · risk-officer | Sprint planning, roadmaps, dependency mapping |
| `marketing` | researcher · strategist · analyst | TAM/SAM/SOM, acquisition channels, growth |
| `legal` | researcher · analyst · advisor | GDPR, EU AI Act, compliance, contracts |
| `risk` | identifier · assessor · mitigator | Risk register, probability/impact matrix |
| `finance` | modeler · analyst · advisor | Unit economics, CAC/LTV, burn rate, pricing |
| `researcher` | finder · synthesizer · validator | Market research, case studies, intelligence |

---

## Models Used

SuperBrain selects the best model for each role via [OpenRouter](https://openrouter.ai):

| Model | Used for |
|-------|---------|
| `openai/gpt-4o` | Security (attacker), strategy, legal analysis, synthesis |
| `openai/gpt-4o-mini` | UI design, QA writing, mobile, planning, lighter tasks |
| `deepseek/deepseek-chat` | Architecture, backend, data modeling, research |
| `google/gemini-2.0-flash-001` | Code review, fast validation, broad knowledge tasks |

---

## Installation

### Requirements

- bash 4+
- `curl`
- `jq`
- OpenRouter API key → [openrouter.ai/keys](https://openrouter.ai/keys)

### Setup

```bash
git clone https://github.com/ArseniiB-o/superbrain.git ~/.agents2
cd ~/.agents2
cp .env.example .env
# edit .env and set your OPENROUTER_API_KEY
chmod +x dispatch.sh call_model.sh
chmod +x teams/*/lead.sh teams/*/prompt_engineer.sh
chmod +x planning/director.sh audit/lead.sh
chmod +x lib/*.sh
```

`.env` format:
```
OPENROUTER_API_KEY=sk-or-v1-your-key-here
```

---

## Usage

### Basic dispatch

```bash
# Any complex task → automatic team routing
bash ~/.agents2/dispatch.sh "design a REST API for a multi-tenant SaaS platform"

# Pre-project planning (runs 5 teams in parallel, produces full project brief)
bash ~/.agents2/dispatch.sh --new-project "invoice management SaaS for EU market"

# Final audit (security + architecture + quality, all in parallel)
bash ~/.agents2/dispatch.sh --audit "review the payment processing module"

# Target specific teams
bash ~/.agents2/dispatch.sh --teams "security,backend,qa" "review authentication flow"

# Skip prompt engineering (faster, lower cost)
bash ~/.agents2/dispatch.sh --no-pe "quick review of this config file"
```

### Direct team access

```bash
# Call any team directly
bash ~/.agents2/teams/backend/lead.sh "design a PostgreSQL schema for a booking system"
bash ~/.agents2/teams/security/lead.sh "audit this JWT implementation"
bash ~/.agents2/teams/marketing/lead.sh "TAM analysis for B2B developer tools in Europe"
```

### Standalone planning director

```bash
# Full pre-project analysis (5 teams parallel → GPT-4o brief)
bash ~/.agents2/planning/director.sh "Build a drone flight management platform"

# Skip the interactive Q&A
bash ~/.agents2/planning/director.sh --skip-questions "Build a marketplace for freelancers"
```

### Standalone audit lead

```bash
# Full audit (security + architecture + quality → GPT-4o report)
bash ~/.agents2/audit/lead.sh "audit this backend project: /path/to/project"

# Pipe team outputs into the auditor
cat all_outputs.txt | bash ~/.agents2/audit/lead.sh "final audit"
```

---

## Configuration

`config.json` controls team models, orchestration models, memory limits, and logging:

```json
{
  "teams": {
    "backend": {
      "models": {
        "primary": "deepseek/deepseek-chat",
        "fallback1": "openai/gpt-4o-mini",
        "fallback2": "google/gemini-2.0-flash-001"
      }
    }
  },
  "orchestration": {
    "decomposer": { "model": "deepseek/deepseek-chat" },
    "synthesizer": { "model": "openai/gpt-4o" },
    "prompt_engineer": { "model": "openai/gpt-4o" }
  },
  "memory": {
    "max_lines": 40,
    "truncate_to": 35
  }
}
```

---

## Memory System

Each team maintains its own `memory.md` — a rolling log of patterns, decisions, and accumulated knowledge from past runs.

- Auto-truncates to 35 lines when it exceeds 40
- AI-compressed when full (via `gpt-4o-mini`)
- Read at prompt-engineering time to give specialists context from past sessions

Memory files live at `~/.agents2/teams/<team>/memory.md` and `~/.agents2/planning/memory.md`.

---

## Logs

Every run produces two log files in `~/.agents2/logs/`:

| File | Contents |
|------|---------|
| `session_YYYYMMDD.log` | Compact log: agent, model, status, timing |
| `session_YYYYMMDD.full.log` | Full prompts and responses for every agent call |

---

## Project Brief (--new-project)

When run with `--new-project`, SuperBrain:

1. Runs 5 parallel team analyses (architecture, security, business, planning, critic)
2. Synthesizes into a structured project brief (GPT-4o)
3. Creates a `~/project-name/` folder with 10 pre-populated documents:

| File | Contents |
|------|---------|
| `brief.md` | Full project brief |
| `architecture.md` | Tech stack, system design |
| `api-design.md` | Endpoint design |
| `database.md` | Schema design |
| `security.md` | Threat model, OWASP checklist |
| `timeline.md` | Milestones, sprints |
| `risks.md` | Risk register |
| `metrics.md` | KPIs, success criteria |
| `gtm.md` | Go-to-market plan |
| `testing.md` | Test strategy |

---

## Audit Report (--audit)

The audit lead runs three sub-audits in parallel:

- **Security** — OWASP Top 10, auth, crypto, secrets, dependencies
- **Architecture** — scalability, design patterns, data layer, observability
- **Quality** — test coverage, error handling, business logic, deployment

Output format:

```
## 🔴 CRITICAL ISSUES (fix before deploy)
## 🟠 HIGH ISSUES
## 🟡 MEDIUM ISSUES
## 🟢 LOW / INFO
## 📊 AUDIT SCORES  (Security: X/10, Code Quality: X/10, Architecture: X/10)
## ✅ WHAT'S GOOD
## 🚨 IMMEDIATE ACTIONS REQUIRED
```

---

## Cost Estimate

Approximate cost per full dispatch run (all teams):

| Scenario | Teams | API calls | Est. cost |
|----------|-------|-----------|-----------|
| Simple task | 2-3 teams | ~20 calls | $0.02–0.05 |
| Complex task | 5-6 teams | ~50 calls | $0.10–0.25 |
| New project | 5 + planning | ~55 calls | $0.15–0.35 |
| Full audit | 3 sub-audits + synthesis | ~30 calls | $0.08–0.20 |

---

## File Structure

```
~/.agents2/
├── dispatch.sh              # Main orchestrator
├── call_model.sh            # Direct OpenRouter model caller
├── config.json              # Team and model configuration
├── AGENTS.md                # Full documentation (Russian)
├── .env                     # API keys (not committed)
├── lib/
│   ├── logger.sh            # Structured logging
│   ├── memory.sh            # Per-team memory management
│   ├── fallback.sh          # Sequential model fallback
│   └── prompt_engineer.sh   # Global dispatch-level PE
├── teams/
│   └── <team>/
│       ├── lead.sh          # Team lead (3-specialist parallel pipeline)
│       ├── prompt_engineer.sh  # Team-specific prompt optimizer
│       └── memory.md        # Team's accumulated knowledge
├── planning/
│   ├── director.sh          # Pre-project planning director
│   └── memory.md            # Planning session memory
├── audit/
│   ├── lead.sh              # Cross-team audit orchestrator
│   └── memory.md            # Audit pattern memory
└── logs/
    ├── session_*.log        # Compact session logs
    └── session_*.full.log   # Full prompt/response logs
```

---

## License

MIT © [ArseniiB-o](https://github.com/ArseniiB-o)
