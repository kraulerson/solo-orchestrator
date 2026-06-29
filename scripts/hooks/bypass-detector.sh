#!/usr/bin/env bash
# scripts/hooks/bypass-detector.sh — BL-029 bypass-shape detector.
#
# Wires into Claude Code's PostToolUse and Stop hooks. Reads the JSON
# envelope from stdin (per https://code.claude.com/docs/en/hooks),
# extracts the relevant text (tool_response.{stdout,stderr,output,content}
# for PostToolUse; last_assistant_message for Stop), scans against
# bypass-patterns.sh, and writes a claude_bypass_proposal row to
# bypass-audit.json on match. Stop passes with .stop_hook_active == true
# are skipped to avoid re-entrant double-scanning.
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

# Re-entrancy guard: when a Stop hook itself triggers further model
# activity (e.g. blocking with a follow-up), Claude Code re-invokes the
# Stop hook with .stop_hook_active == true. Skip those passes so we
# don't double-scan the same assistant turn and emit duplicate audit
# rows / pending-approval sentinels.
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$STOP_HOOK_ACTIVE" = "true" ] && exit 0

# Extract scannable text by event type.
TEXT=""
case "$EVENT" in
  PostToolUse)
    # Claude Code envelope: .tool_response. For Bash, .stdout/.stderr/.exit_code/.interrupted;
    # for Read/Edit/Write, .output or .content (or a string). Cover all
    # known shapes; missing field returns "" and the next guard exits.
    TEXT=$(echo "$INPUT" | jq -r '.tool_response.stdout // .tool_response.stderr // .tool_response.output // .tool_response.content // ""' 2>/dev/null)
    ;;
  Stop)
    # Claude Code Stop envelope: .last_assistant_message (Claude's final
    # turn) and .transcript_path (path to session JSONL, optional). We
    # scan the inline message — the file is only consulted as a fallback.
    TEXT=$(echo "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null)
    if [ -z "$TEXT" ]; then
      TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)
      if [ -n "$TRANSCRIPT_PATH" ] && [ -r "$TRANSCRIPT_PATH" ]; then
        TEXT=$(tail -n 50 "$TRANSCRIPT_PATH" 2>/dev/null \
          | jq -r 'select(.role=="assistant" or .type=="assistant") | (.content // .message.content // "")' 2>/dev/null \
          | tail -n 5)
      fi
    fi
    ;;
  *)
    # Unknown event — skip (defense against schema changes).
    exit 0
    ;;
esac

[ -z "$TEXT" ] && exit 0

# BL-029.1 fix S3 (2026-05-04): strip fenced code blocks before scanning.
# Documentation / CHANGELOG / docstring text wrapping a bypass pattern in
# ```...``` is descriptive, not advisory — earlier behavior false-positived
# on changelog entries that named the patterns. Inline backtick code
# (`--no-verify`) is preserved because Claude typesets active proposals
# with inline backticks too. This handles the common doc-FP class without
# suppressing legitimate proposals.
TEXT=$(printf '%s\n' "$TEXT" | awk '
  BEGIN { in_fence = 0 }
  /^[[:space:]]*```/ { in_fence = !in_fence; next }
  !in_fence { print }
')

[ -z "$TEXT" ] && exit 0

# BL-029 + 2026-04-29 calibration fix S1: scan for ALL matched patterns
# and emit one audit row per match. Without this, an earlier-table
# normal-severity pattern silently masked refuse_to_recommend severity
# rows for higher-impact bypasses appearing later in the same proposal.
PATTERNS=$(scan_bypass_patterns_all "$TEXT" || true)
[ -z "$PATTERNS" ] && exit 0

# Build the rows.
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Audit fix code-hooks-bypass-detector-3 (2026-06-28): the Claude Code
# hook envelope carries .session_id as a documented top-level field;
# CLAUDE_SESSION_ID is NOT exported by Claude Code, so the previous
# env-only read landed every row with session_id="unknown" and broke
# the W7 successor-handoff correlation. Read the envelope first; fall
# back to $CLAUDE_SESSION_ID (belt-and-suspenders for unexpected
# envelope shapes), then to "unknown".
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
LEVEL=$(jq -r '.enforcement_level // "strict"' "$PROJECT_ROOT/.claude/manifest.json" 2>/dev/null)
FIRST_PATTERN=""

while IFS= read -r PATTERN; do
  [ -z "$PATTERN" ] && continue
  [ -z "$FIRST_PATTERN" ] && FIRST_PATTERN="$PATTERN"

  # Refuse-to-recommend severity for fake-loop class patterns. Per agent-5
  # spec: framework should not rely on Claude's good taste alone.
  SEVERITY="normal"
  case "$PATTERN" in
    fake_loop|manual_step_complete) SEVERITY="refuse_to_recommend" ;;
  esac

  # Look up the original regex for excerpt extraction (per BL-029 plan
  # amendment — using the pattern name as a regex via tr was broken).
  REGEX=$(pattern_regex_for "$PATTERN" 2>/dev/null || echo "$PATTERN")

  # Trim excerpt to the line containing the match.
  EXCERPT=$(echo "$TEXT" | grep -iE -e "$REGEX" 2>/dev/null | head -1 | head -c 500)

  ROW=$(jq -nc \
    --arg ts "$TS" \
    --arg sid "$SESSION_ID" \
    --arg lvl "$LEVEL" \
    --arg pat "$PATTERN" \
    --arg evt "$EVENT" \
    --arg ex "$EXCERPT" \
    --arg sev "$SEVERITY" \
    '{
      timestamp: $ts,
      session_id: $sid,
      type: "claude_bypass_proposal",
      actor: "claude",
      enforcement_level_at_event: $lvl,
      details: {pattern: $pat, event: $evt, excerpt: $ex, severity: $sev},
      user_response: "PENDING",
      final_outcome: "recorded_only"
    }')

  bypass_audit_append "$PROJECT_ROOT" "$ROW" || true
done <<< "$PATTERNS"

# BL-029: write pending-approval sentinel iff one isn't already pending.
# Forces non-trivial confirmation phrase to accept (defends against generic
# 'OK' / 'yes' / 'proceed' acceptance, per agent-5 spec). One sentinel
# covers all matched patterns from this proposal.
#
# S5 fix (2026-05-04): the confirmation phrase is NO LONGER embedded in the
# question text. Earlier behavior let Claude/user reading the sentinel
# copy-paste the phrase out of compliance — defeating the defense. The
# phrase remains in options[0] (structurally required for matching), and
# the question instructs the user to read options[0] verbatim.
SENTINEL="$PROJECT_ROOT/.claude/pending-approval.json"
if [ ! -f "$SENTINEL" ]; then
  CONFIRM_PHRASE="I have read the proposal at .claude/bypass-audit.json and accept the bypass"
  jq -nc \
    --arg q "Bypass proposal detected (pattern: $FIRST_PATTERN). Review .claude/bypass-audit.json before deciding. To accept, type option A1 verbatim. To decline, say 'decline' or describe what you want instead." \
    --arg phrase "$CONFIRM_PHRASE" \
    --arg ts "$TS" \
    '{
      question: $q,
      options: [
        ("A1: " + $phrase),
        "A2: decline"
      ],
      recommendation: "A2",
      offered_at: $ts
    }' > "$SENTINEL"
fi

exit 0
