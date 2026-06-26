#!/usr/bin/env bash
# scripts/detect-out-of-band-commits.sh — BL-030 out-of-band commit detector.
#
# SessionStart hook. Diffs commits since last-checked-commit.txt against
# claude-commits.jsonl. Anything that's reachable in `git log A..HEAD` and
# NOT in the Claude ledger AND NOT a derivative (merge/revert/cherry-pick/
# squash) is recorded as an out_of_band_commit row in bypass-audit.json.
#
# Runs on light AND strict (strict for --no-verify capture). No-ops on
# enforcement_level=no.

set -uo pipefail

PROJECT_ROOT="${1:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "")}}"
[ -z "$PROJECT_ROOT" ] && exit 0
[ ! -d "$PROJECT_ROOT/.claude" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/enforcement-level.sh"

LEVEL=$(read_enforcement_level "$PROJECT_ROOT")
[ "$LEVEL" = "no" ] && exit 0

LEDGER="$PROJECT_ROOT/.claude/claude-commits.jsonl"
AUDIT="$PROJECT_ROOT/.claude/bypass-audit.json"
BASELINE_FILE="$PROJECT_ROOT/.claude/last-checked-commit.txt"

# Initialize empty audit array if missing (BL-029 should provide; defensive).
[ -f "$AUDIT" ] || echo "[]" > "$AUDIT"

# Append a row to the audit array, preserving valid JSON.
append_audit_row() {
  local row="$1"
  local tmp
  tmp=$(mktemp)
  if jq --argjson r "$row" '. + [$r]' "$AUDIT" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$AUDIT"
  else
    rm -f "$tmp"
    echo "[FAIL] detect-out-of-band-commits: failed to append audit row" >&2
  fi
}

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# Record a detector_error row and exit non-zero (still surface to stderr).
record_error() {
  local reason="$1"
  local row
  row=$(jq -nc \
    --arg ts "$(ts)" \
    --arg lvl "$LEVEL" \
    --arg reason "$reason" \
    '{timestamp:$ts, session_id:null, type:"detector_error", actor:"framework", enforcement_level_at_event:$lvl, details:{reason:$reason}, user_response:"n/a", final_outcome:"n/a"}')
  append_audit_row "$row"
  echo "[FAIL] detect-out-of-band-commits: $reason" >&2
}

# Establish baseline if missing.
if [ ! -f "$BASELINE_FILE" ]; then
  cd "$PROJECT_ROOT" && git rev-parse HEAD > "$BASELINE_FILE" 2>/dev/null || {
    record_error "could not establish baseline (no HEAD)"
    exit 0
  }
  exit 0
fi

BASELINE=$(cat "$BASELINE_FILE")
[ -z "$BASELINE" ] && { record_error "baseline file empty"; exit 0; }

# Validate ledger is parseable JSONL (or empty).
if [ -s "$LEDGER" ] && ! jq -s '.' "$LEDGER" >/dev/null 2>&1; then
  record_error "claude-commits.jsonl is not valid JSONL"
  exit 0
fi

cd "$PROJECT_ROOT"

# Validate baseline is reachable.
if ! git cat-file -e "$BASELINE" 2>/dev/null; then
  echo "[NOTE] detect-out-of-band-commits: baseline $BASELINE is not reachable — likely rebased/force-pushed. Conservatively flagging everything between origin merge-base and HEAD as out-of-band." >&2
  # Conservative: use the root commit as the baseline.
  BASELINE=$(git rev-list --max-parents=0 HEAD | head -1)
fi

# Build SHA set from ledger.
LEDGER_SHAS=""
if [ -s "$LEDGER" ]; then
  LEDGER_SHAS=$(jq -r '.sha' "$LEDGER" 2>/dev/null | tr '\n' ' ')
fi

is_in_ledger() {
  local sha="$1"
  case " $LEDGER_SHAS " in
    *" $sha "*) return 0 ;;
    *) return 1 ;;
  esac
}

is_derivative() {
  local subject="$1"
  case "$subject" in
    "Merge "*|"Revert "*|"Squashed commit"*|"squash! "*|"fixup! "*) return 0 ;;
  esac
  echo "$subject" | grep -qiE '^(merge|revert)[ :]' && return 0
  echo "$subject" | grep -q "cherry picked from" && return 0
  return 1
}

WROTE_ANY=0
NEW_HEAD=$(git rev-parse HEAD)

# git log <baseline>..HEAD — list new commits, oldest first.
while IFS=$'\t' read -r sha author_ts subject; do
  [ -z "$sha" ] && continue
  if is_in_ledger "$sha"; then continue; fi
  if is_derivative "$subject"; then continue; fi
  row=$(jq -nc \
    --arg ts "$(ts)" \
    --arg lvl "$LEVEL" \
    --arg sha "$sha" \
    --arg ats "$author_ts" \
    --arg subj "$subject" \
    '{timestamp:$ts, session_id:null, type:"out_of_band_commit", actor:"user_terminal_inferred",
      enforcement_level_at_event:$lvl,
      details:{commit_sha:$sha, commit_subject:$subj, author_timestamp:$ats},
      user_response:"n/a", final_outcome:"recorded_only"}')
  append_audit_row "$row"
  WROTE_ANY=$((WROTE_ANY + 1))
done < <(git log --reverse --format='%H%x09%aI%x09%s' "$BASELINE..HEAD" 2>/dev/null)

# Update baseline.
echo "$NEW_HEAD" > "$BASELINE_FILE"

if [ "$WROTE_ANY" -gt 0 ]; then
  echo "⚠ $WROTE_ANY user-terminal commit(s) detected since last session — recorded to .claude/bypass-audit.json." >&2
fi

exit 0
