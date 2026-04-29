#!/usr/bin/env bash
# scripts/hooks/bypass-detector.sh — BL-029 bypass-shape detector.
#
# Wires into Claude Code's PostToolUse and Stop hooks. Reads the JSON
# envelope from stdin, extracts the relevant text (tool_result.output for
# PostToolUse; transcript for Stop), scans against bypass-patterns.sh,
# and writes a claude_bypass_proposal row to bypass-audit.json on match.
#
# No-op conditions:
#   - .claude/ doesn't exist
#   - jq isn't installed
#   - envelope can't be parsed
#   - text contains no bypass-shaped language
#
# The hook is silent on the no-op paths. The audit-log writer (lib) is
# the framework's voice for matches; this script does not print anything
# to stdout (which would inject text into Claude's view).

set -uo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "")}"
[ -z "$PROJECT_ROOT" ] && exit 0
[ ! -d "$PROJECT_ROOT/.claude" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Locate libraries: prefer project's own scripts/lib/ (post-init layout),
# fall back to framework repo's scripts/lib/ (running on the framework itself).
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$HOOK_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPTS_DIR/lib/bypass-patterns.sh"
# shellcheck disable=SC1091
source "$SCRIPTS_DIR/lib/bypass-audit.sh"

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null)

# Extract scannable text by event type.
TEXT=""
case "$EVENT" in
  PostToolUse)
    TEXT=$(echo "$INPUT" | jq -r '.tool_result.output // .tool_result.stderr // ""' 2>/dev/null)
    ;;
  Stop)
    TEXT=$(echo "$INPUT" | jq -r '.transcript // .stop_reason // ""' 2>/dev/null)
    ;;
  *)
    # Unknown event — skip (defense against schema changes).
    exit 0
    ;;
esac

[ -z "$TEXT" ] && exit 0

PATTERN=$(scan_bypass_patterns "$TEXT") || exit 0
[ -z "$PATTERN" ] && exit 0

# Look up the original regex for excerpt extraction (per BL-029 plan
# amendment — using the pattern name as a regex via tr was broken).
REGEX=$(pattern_regex_for "$PATTERN" 2>/dev/null || echo "$PATTERN")

# Trim excerpt to the line containing the match.
EXCERPT=$(echo "$TEXT" | grep -iE -e "$REGEX" 2>/dev/null | head -1 | head -c 500)

# Build the row.
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
LEVEL=$(jq -r '.enforcement_level // "strict"' "$PROJECT_ROOT/.claude/manifest.json" 2>/dev/null)

ROW=$(jq -nc \
  --arg ts "$TS" \
  --arg sid "$SESSION_ID" \
  --arg lvl "$LEVEL" \
  --arg pat "$PATTERN" \
  --arg evt "$EVENT" \
  --arg ex "$EXCERPT" \
  '{
    timestamp: $ts,
    session_id: $sid,
    type: "claude_bypass_proposal",
    actor: "claude",
    enforcement_level_at_event: $lvl,
    details: {pattern: $pat, event: $evt, excerpt: $ex},
    user_response: "PENDING",
    final_outcome: "recorded_only"
  }')

bypass_audit_append "$PROJECT_ROOT" "$ROW" || true

exit 0
