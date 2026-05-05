# scripts/lib/bypass-audit.sh — BL-029 audit-log writer library.
#
# Canonical schema for .claude/bypass-audit.json. Provides flock-protected
# append so concurrent writers (PostToolUse hooks, Stop hooks, SessionStart
# detector, init/reconfigure recorders) don't race on the file.
#
# Schema per row (per BL-030 spec § 6):
#   {
#     "timestamp":                 ISO-8601 UTC,
#     "session_id":                string-or-null,
#     "type":                      "claude_bypass_proposal" | "terminal_commit_blocked" |
#                                  "terminal_commit_passed" | "out_of_band_commit" |
#                                  "enforcement_level_set" | "detector_error" | "escalation",
#     "actor":                     "claude" | "user_terminal" | "user_terminal_inferred" | "framework",
#     "enforcement_level_at_event":"no" | "light" | "strict" | "n/a",
#     "details":                   { type-specific },
#     "user_response":             "PENDING" | "accepted" | "declined" | "n/a",
#     "final_outcome":             "committed" | "bypassed" | "escalated" | "abandoned" | "recorded_only" | "n/a"
#   }

# shellcheck shell=bash

# bypass_audit_init <project_root>
# Creates .claude/bypass-audit.json as an empty array if it does not already
# exist. Idempotent — preserves existing rows.
bypass_audit_init() {
  local project_root="${1:-.}"
  local file="$project_root/.claude/bypass-audit.json"
  [ -f "$file" ] && return 0
  mkdir -p "$project_root/.claude"
  echo "[]" > "$file"
}

# bypass_audit_append <project_root> <row_json>
# Validates row_json is a JSON object, then appends to the audit array
# under flock. Returns 0 on success, 1 on validation or write failure.
bypass_audit_append() {
  local project_root="${1:-.}"
  local row="${2:-}"
  local file="$project_root/.claude/bypass-audit.json"

  if [ -z "$row" ]; then
    echo "[FAIL] bypass_audit_append: empty row" >&2
    return 1
  fi
  if ! echo "$row" | jq -e 'type == "object"' >/dev/null 2>&1; then
    echo "[FAIL] bypass_audit_append: row is not a JSON object" >&2
    return 1
  fi

  bypass_audit_init "$project_root"

  # Portable advisory lock via atomic mkdir. flock isn't on macOS by
  # default; mkdir works everywhere. Lock is held for the read-modify-
  # write window only.
  local lock_dir="$file.lockdir"
  local attempts=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 100 ]; then
      echo "[FAIL] bypass_audit_append: lock timeout (>10s)" >&2
      return 1
    fi
    sleep 0.1
  done

  local tmp rc
  tmp=$(mktemp)
  if jq --argjson r "$row" '. + [$r]' "$file" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$file"
    rc=0
  else
    rm -f "$tmp"
    echo "[FAIL] bypass_audit_append: jq failed" >&2
    rc=1
  fi

  rmdir "$lock_dir" 2>/dev/null
  return "$rc"
}

# bypass_audit_count_pending <project_root>
# Echoes the number of rows whose user_response is "PENDING".
bypass_audit_count_pending() {
  local project_root="${1:-.}"
  local file="$project_root/.claude/bypass-audit.json"
  [ -f "$file" ] || { echo 0; return 0; }
  jq '[.[] | select(.user_response == "PENDING")] | length' "$file" 2>/dev/null || echo 0
}

# bypass_audit_close_pending <project_root> <decision>
# Updates every PENDING row to the given decision. decision ∈ {accept, decline}.
#   accept  → user_response=accepted,  final_outcome=bypassed
#   decline → user_response=declined,  final_outcome=abandoned
# Idempotent — leaves already-resolved rows untouched. Holds the same lock
# bypass_audit_append uses to avoid races. Returns 0 on success, 1 on
# unknown decision or write failure.
#
# S4 fix (2026-05-04): without this, PENDING rows accumulated forever.
# The W7 successor-handoff use case (audit log as historical governance
# record) was half-built — a successor reading the log couldn't tell
# accepted from declined from never-resolved.
bypass_audit_close_pending() {
  local project_root="${1:-.}"
  local decision="${2:-}"
  local file="$project_root/.claude/bypass-audit.json"

  local user_resp final_out
  case "$decision" in
    accept)  user_resp="accepted"; final_out="bypassed" ;;
    decline) user_resp="declined"; final_out="abandoned" ;;
    *)
      echo "[FAIL] bypass_audit_close_pending: unknown decision '$decision' (expected: accept | decline)" >&2
      return 1
      ;;
  esac

  [ -f "$file" ] || return 0

  local lock_dir="$file.lockdir"
  local attempts=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 100 ]; then
      echo "[FAIL] bypass_audit_close_pending: lock timeout (>10s)" >&2
      return 1
    fi
    sleep 0.1
  done

  local tmp rc
  tmp=$(mktemp)
  if jq --arg ur "$user_resp" --arg fo "$final_out" \
       '[.[] | if .user_response == "PENDING" then .user_response = $ur | .final_outcome = $fo else . end]' \
       "$file" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$file"
    rc=0
  else
    rm -f "$tmp"
    echo "[FAIL] bypass_audit_close_pending: jq failed" >&2
    rc=1
  fi

  rmdir "$lock_dir" 2>/dev/null
  return "$rc"
}
