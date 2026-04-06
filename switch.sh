#!/usr/bin/env bash
# ============================================================
# switch.sh — Agents2 Mode Switcher
#
# Usage:
#   ./switch.sh openrouter     — Mixed models via OpenRouter (default)
#   ./switch.sh claude         — All agents use claude-sonnet-4-6
#   ./switch.sh status         — Show current mode
#   ./switch.sh help           — Show this help
#
# Modes:
#   openrouter  — Each team uses its configured model (gpt-4o, deepseek, gemini, etc.)
#   claude      — ALL calls use claude-sonnet-4-6, regardless of team config
#                 Route: direct Anthropic API (if ANTHROPIC_API_KEY in .env)
#                        OR OpenRouter with anthropic/claude-sonnet-4-6 (fallback)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE_FILE="$SCRIPT_DIR/.mode"
ENV_FILE="$SCRIPT_DIR/.env"

# Load .env to check for keys
if [[ -f "$ENV_FILE" ]]; then
    set -a; source "$ENV_FILE"; set +a
fi

# ── Current mode ──────────────────────────────────────────────────────────────
current_mode() {
    if [[ -f "$MODE_FILE" ]]; then
        cat "$MODE_FILE"
    else
        echo "claude"
    fi
}

# ── Status display ────────────────────────────────────────────────────────────
show_status() {
    local mode
    mode=$(current_mode)

    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║          Agents2 Mode Status                     ║"
    echo "╠══════════════════════════════════════════════════╣"

    case "$mode" in
        openrouter)
            echo "║  Active mode: 🌐 OPENROUTER (mixed models)      ║"
            echo "║                                                  ║"
            echo "║  frontend  → gpt-4o-mini                         ║"
            echo "║  backend   → deepseek-chat                       ║"
            echo "║  security  → gpt-4o                              ║"
            echo "║  aiml      → gpt-4o                              ║"
            echo "║  writer    → gpt-4o                              ║"
            echo "║  (each team uses its own configured model)       ║"
            ;;
        claude)
            echo "║  Active mode: 🤖 CLAUDE MAX SUBSCRIPTION         ║"
            echo "║                                                  ║"
            echo "║  ALL teams → claude-sonnet-4-6                  ║"
            echo "║  Backend:   claude -p (Max subscription) ✓       ║"
            echo "║  No API key required — uses your Max plan        ║"
            ;;
        *)
            echo "║  Active mode: ❓ UNKNOWN ($mode)                 ║"
            ;;
    esac

    echo "╚══════════════════════════════════════════════════╝"
    echo ""
}

# ── Help ──────────────────────────────────────────────────────────────────────
show_help() {
    echo ""
    echo "Agents2 Mode Switcher"
    echo ""
    echo "Usage:"
    echo "  $(basename "$0") openrouter   — Mixed models (default)"
    echo "  $(basename "$0") claude       — All agents use claude-sonnet-4-6"
    echo "  $(basename "$0") status       — Show current mode"
    echo "  $(basename "$0") help         — Show this help"
    echo ""
}

# ── Switch mode (atomic write with temp file) ─────────────────────────────────
switch_to() {
    local new_mode="$1"
    local old_mode
    old_mode=$(current_mode)

    if [[ "$old_mode" == "$new_mode" ]]; then
        echo ""
        echo "Already in $new_mode mode — no change needed."
        show_status
        exit 0
    fi

    # Atomic write: write to temp, then move
    local tmp_file
    tmp_file=$(mktemp "${SCRIPT_DIR}/.mode.XXXXXX")
    printf '%s' "$new_mode" > "$tmp_file"
    mv "$tmp_file" "$MODE_FILE"

    echo ""
    echo "✅ Switched: $old_mode → $new_mode"
    show_status

    # Validate the switch worked
    local actual_mode
    actual_mode=$(current_mode)
    if [[ "$actual_mode" != "$new_mode" ]]; then
        echo "❌ ERROR: Mode file mismatch! Expected $new_mode, got $actual_mode" >&2
        exit 1
    fi

    if [[ "$new_mode" == "claude" ]]; then
        echo "ℹ️  All agent calls will now use claude-sonnet-4-6"
        echo "ℹ️  Backend: claude -p (Max subscription) — no API key needed"
    else
        echo "ℹ️  Each team will use its configured model from config.json"
    fi
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
ACTION="${1:-status}"

case "$ACTION" in
    openrouter)
        switch_to "openrouter"
        ;;
    claude)
        switch_to "claude"
        ;;
    status)
        show_status
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Error: unknown mode '$ACTION'" >&2
        echo "Valid modes: openrouter, claude" >&2
        echo "Run '$(basename "$0") help' for usage." >&2
        exit 1
        ;;
esac
