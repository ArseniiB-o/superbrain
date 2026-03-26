#!/usr/bin/env bash
# lib/memory.sh — Team memory utilities
#
# Each team persists a memory.md file that accumulates shared knowledge across
# sessions.  The file is plain Markdown so it is human-readable and can be
# pasted directly into any AI prompt.
#
# File locations:
#   Regular teams : ~/.agents2/teams/<team>/memory.md
#   Special teams : ~/.agents2/<team>/memory.md  (planning, audit, …)
#
# Public API:
#   memory_read      <team>        → prints full memory content (stdout)
#   memory_append    <team> <text> → adds timestamped bullet, trims if needed
#   memory_summarize <team>        → asks AI to compress when > 30 lines
#
# Constants:
#   MAX_LINES=40   — hard cap before trimming
#   TRIM_TO=35     — keep this many recent lines after trim
#   SUMMARIZE_AT=30 — trigger AI summarization at this line count

set -euo pipefail

AGENTS2_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MAX_LINES=40
TRIM_TO=35
SUMMARIZE_AT=30

# ── Internal: resolve memory file path ───────────────────────────────────────
_memory_file() {
    local team="$1"

    # Special top-level teams (planning, audit) live directly under AGENTS2_DIR
    for special in planning audit; do
        if [ "$team" = "$special" ]; then
            echo "${AGENTS2_DIR}/${team}/memory.md"
            return 0
        fi
    done

    # All other teams live under teams/
    echo "${AGENTS2_DIR}/teams/${team}/memory.md"
}

# ── Internal: ensure memory file exists with correct header ──────────────────
_memory_ensure() {
    local team="$1"
    local file
    file="$(_memory_file "$team")"

    if [ ! -f "$file" ]; then
        mkdir -p "$(dirname "$file")"
        local ts
        ts="$(date "+%Y-%m-%d %H:%M")"
        cat > "$file" <<EOF
# Team Memory: ${team}
Last updated: ${ts}

## Accumulated Knowledge
EOF
    fi
}

# ── Internal: update "Last updated" timestamp in place ───────────────────────
_memory_touch_timestamp() {
    local file="$1"
    local ts
    ts="$(date "+%Y-%m-%d %H:%M")"

    # Replace the "Last updated: …" line using a temp file (portable, no sed -i issues on all platforms)
    local tmp
    tmp="$(mktemp)"
    while IFS= read -r line; do
        if [[ "$line" == "Last updated:"* ]]; then
            printf 'Last updated: %s\n' "$ts"
        else
            printf '%s\n' "$line"
        fi
    done < "$file" > "$tmp"
    mv "$tmp" "$file"
}

# ── Public: memory_read ───────────────────────────────────────────────────────
# Prints the full memory file to stdout.
# Prints nothing (exit 0) if the file does not yet exist.
memory_read() {
    local team="${1:?memory_read requires <team>}"
    local file
    file="$(_memory_file "$team")"

    if [ -f "$file" ]; then
        cat "$file"
    fi
}

# ── Public: memory_append ─────────────────────────────────────────────────────
# Appends a timestamped bullet point to the memory file.
# After appending:
#   - If total lines > MAX_LINES  → truncate to last TRIM_TO lines
#   - If content lines > SUMMARIZE_AT → call memory_summarize
memory_append() {
    local team="${1:?memory_append requires <team>}"
    local text="${2:?memory_append requires <text>}"

    _memory_ensure "$team"

    local file
    file="$(_memory_file "$team")"

    local ts
    ts="$(date "+%Y-%m-%d %H:%M")"

    # Append the bullet
    printf '- [%s] %s\n' "$ts" "$text" >> "$file"

    # Update timestamp header
    _memory_touch_timestamp "$file"

    # Count total lines
    local total_lines
    total_lines="$(wc -l < "$file")"

    # Hard trim if over MAX_LINES (keep header + last TRIM_TO lines)
    if [ "$total_lines" -gt "$MAX_LINES" ]; then
        local tmp
        tmp="$(mktemp)"

        # Preserve the 3-line header (title, last-updated, blank) + last TRIM_TO lines
        {
            head -n 3 "$file"
            tail -n "$TRIM_TO" "$file"
        } > "$tmp"

        mv "$tmp" "$file"
        _memory_touch_timestamp "$file"
    fi

    # Count lines in the "Accumulated Knowledge" section to decide if summarization is needed.
    # We count bullet lines (lines starting with '-') as a proxy.
    local bullet_lines
    bullet_lines="$(grep -c '^-' "$file" 2>/dev/null || true)"

    if [ "${bullet_lines:-0}" -gt "$SUMMARIZE_AT" ]; then
        memory_summarize "$team"
    fi
}

# ── Public: memory_summarize ──────────────────────────────────────────────────
# Asks an AI model (via call_model.sh) to compress the memory file.
# Replaces the "Accumulated Knowledge" section with a condensed version.
# Falls back gracefully if call_model.sh is unavailable or the API call fails.
memory_summarize() {
    local team="${1:?memory_summarize requires <team>}"
    local file
    file="$(_memory_file "$team")"

    if [ ! -f "$file" ]; then
        return 0
    fi

    local call_model="${AGENTS2_DIR}/call_model.sh"
    if [ ! -x "$call_model" ]; then
        # Silently skip — summarization is an enhancement, not a hard requirement
        return 0
    fi

    local current_content
    current_content="$(cat "$file")"

    local system_prompt
    system_prompt="You are a memory compression assistant. You receive a team memory file and return a compressed version. Rules:
1. Keep the most important and actionable facts.
2. Merge redundant items.
3. Output ONLY the bullet list (lines starting with '-'), no headers, no extra text.
4. Maximum 20 bullet points.
5. Each bullet must be concise (≤ 120 chars)."

    local user_prompt
    user_prompt="Compress this team memory to the most important bullet points:

${current_content}"

    local compressed
    if compressed="$(SYSTEM_PROMPT="$system_prompt" printf '%s' "$user_prompt" | \
                     "$call_model" "openai/gpt-4o-mini" 2>/dev/null)"; then

        local ts
        ts="$(date "+%Y-%m-%d %H:%M")"

        local tmp
        tmp="$(mktemp)"
        cat > "$tmp" <<EOF
# Team Memory: ${team}
Last updated: ${ts}

## Accumulated Knowledge
${compressed}
EOF
        mv "$tmp" "$file"
    fi
    # If the AI call fails, leave the file unchanged — no error propagation
    return 0
}
