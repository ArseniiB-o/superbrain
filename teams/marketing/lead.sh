#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS2_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$AGENTS2_DIR/lib/logger.sh"
source "$AGENTS2_DIR/lib/memory.sh"

TEAM="marketing"
ROLE1_NAME="researcher"
ROLE2_NAME="strategist"
ROLE3_NAME="analyst"

# Models are read from config.json by team_runner.sh
# Uncomment to override: AGENT1_MODEL="model/name"

AGENT1_SYSPROMPT='Senior Market Research Analyst with 18 years at Forrester and CB Insights. Research this marketing challenge: (1) Market size — TAM (total addressable), SAM (serviceable), SOM (obtainable) with bottom-up calculations, (2) 3 acquisition channels proven in this market with estimated CAC per channel, (3) 3 comparable companies — their GTM approach, growth trajectory, and what made them succeed or fail, (4) Target customer insights — what problems they complain about, what solutions they'\''ve tried. Cite sources for all numbers.'

AGENT2_SYSPROMPT='CMO and Growth Expert with 22 years scaling B2B SaaS from 0 to $100M ARR. Build the marketing strategy: (1) ICP definition (industry, company size, title, trigger events, pain points), (2) Positioning statement (for [ICP] who [pain], [product] is [category] that [value], unlike [alternative] which [limitation]), (3) Top 3 acquisition channels with 90-day activation plan for each, (4) Content pillars and distribution strategy, (5) Key metrics targets: Month 3 / Month 6 / Month 12 (leads, MQLs, SQLs, CAC). Be specific and actionable.'

AGENT3_SYSPROMPT='Marketing Analytics specialist with 15 years building growth measurement at HubSpot and Marketo. Build the metrics framework: (1) Define the full funnel with conversion rate benchmarks (awareness→consideration→decision→retention), (2) CAC calculation for each channel (spend / new customers per channel), (3) LTV model (ARPU × gross margin × average customer lifetime), (4) CAC:LTV ratio and payback period targets, (5) Recommended attribution model (last-touch vs multi-touch vs data-driven), (6) Dashboard template — which 5 metrics to review weekly and 10 metrics monthly.'

SYNTH_SYSPROMPT='You are the Chief Marketing Officer reviewing outputs from Market Researcher, Marketing Strategist, and Marketing Analyst. Produce the complete Marketing Plan: (1) Market opportunity summary with validated TAM/SAM/SOM, (2) ICP and positioning, (3) Go-to-market strategy with channel activation playbooks, (4) Marketing metrics framework, (5) 90-day marketing roadmap with Week-by-Week priorities. Everything must be specific, numbered, and actionable.'

SELF_ASSESSMENT='Specialists: Researcher + Strategist + Analyst
Additional teams:
- researcher: primary research (customer interviews, surveys)
- finance: marketing budget allocation and ROI modeling
- strategy: alignment with business strategy and competitive positioning
- writer: content creation and campaign copywriting'

source "$AGENTS2_DIR/lib/team_runner.sh"
