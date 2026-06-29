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

# _bypass_audit_preserve_mode <reference_file> <target_file>
# Copies <reference_file>'s octal mode onto <target_file>. Tries GNU
# `chmod --reference` first (single syscall path); falls back to
# `stat`-then-`chmod` covering BSD (macOS) and GNU stat invocations;
# finally falls back to `chmod 600` (the mktemp default, safe for a
# governance artifact). Used to preserve operator-set perms across the
# adjacent-mktemp rename in append / close_pending.
_bypass_audit_preserve_mode() {
  local ref="$1" tgt="$2" mode
  if chmod --reference="$ref" "$tgt" 2>/dev/null; then
    return 0
  fi
  if mode=$(stat -f "%Lp" "$ref" 2>/dev/null) && [ -n "$mode" ]; then
    chmod "$mode" "$tgt" 2>/dev/null && return 0
  fi
  if mode=$(stat -c "%a" "$ref" 2>/dev/null) && [ -n "$mode" ]; then
    chmod "$mode" "$tgt" 2>/dev/null && return 0
  fi
  chmod 600 "$tgt" 2>/dev/null || true
}

# bypass_audit_init <project_root>
# Creates .claude/bypass-audit.json as an empty array if it does not already
# exist. Idempotent — preserves existing rows.
#
# Verifier follow-up (2026-06-28): chmod 600 after creation. The plain
# `echo "[]" > "$file"` redirect inherits the caller's umask (commonly
# 0022 → file mode 0644), which leaves the governance ledger world-
# readable on a default-umask multi-user box. Forcing 0600 here gives
# _bypass_audit_preserve_mode a sane baseline to copy from on the first
# append, so an umask-derived leak doesn't perpetuate through later
# rename cycles.
bypass_audit_init() {
  local project_root="${1:-.}"
  local file="$project_root/.claude/bypass-audit.json"
  [ -f "$file" ] && return 0
  mkdir -p "$project_root/.claude"
  echo "[]" > "$file"
  chmod 600 "$file" 2>/dev/null || true
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

  # D3 fix (post-PR-A): create the temp file ADJACENT to the audit
  # file so the subsequent `mv` is a same-filesystem rename — atomic
  # on POSIX. With $TMPDIR mktemp (/var/folders on macOS), the audit
  # file lives on a different filesystem from /tmp/* or $HOME-based
  # project dirs, turning `mv` into copy+unlink. A SIGKILL during the
  # write window can then truncate the append-only ledger.
  #
  # Audit fix code-lib-2 (2026-06-28): two residual hardenings.
  # (a) Preserve target file permissions across the rename. mktemp
  #     defaults to 0600; if the operator chmod'd the ledger to e.g.
  #     0640 for a shared-team setup, the post-rename file would
  #     silently revert. _bypass_audit_preserve_mode tries GNU
  #     `chmod --reference`, then BSD/GNU `stat`-then-`chmod`, then
  #     a `chmod 600` fallback — keeps the operator's intent on
  #     either platform.
  # (b) Trap on EXIT/INT/TERM so a signal between mktemp and either
  #     branch doesn't leave an orphan ${file}.XXXXXX littering the
  #     governance dir.
  #
  # Verifier follow-up (2026-06-28): wrap the rename window in a
  # SUBSHELL. bash `trap` is shell-global, not function-local — the
  # prior `trap '...' EXIT INT TERM` / `trap - EXIT INT TERM` pair at
  # function scope silently destroyed any pre-existing EXIT trap the
  # caller had installed. Containing the trap in a subshell means it
  # only governs that subshell's exit; the caller's trap survives
  # untouched. tmp/rc must be captured from the subshell's exit code
  # since locals don't propagate up.
  local rc=0
  (
    tmp=$(mktemp "${file}.XXXXXX") || exit 1
    trap 'rm -f "$tmp"; rmdir "$lock_dir" 2>/dev/null' EXIT INT TERM
    if jq --argjson r "$row" '. + [$r]' "$file" > "$tmp" 2>/dev/null; then
      _bypass_audit_preserve_mode "$file" "$tmp"
      mv "$tmp" "$file" || exit 1
      # Successful rename: clear the trap so the EXIT path doesn't try
      # to rm a now-renamed (i.e. nonexistent) tmp path. Also let the
      # outer caller manage the lock_dir cleanup uniformly.
      trap - EXIT INT TERM
      exit 0
    else
      rm -f "$tmp"
      echo "[FAIL] bypass_audit_append: jq failed" >&2
      trap - EXIT INT TERM
      exit 1
    fi
  ) || rc=1

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

  # D2 fix (post-PR-A): scope the close to claude_bypass_proposal rows
  # only. Pre-fix, this flipped EVERY PENDING row regardless of type,
  # including escalation rows whose final_outcome is 'escalated' (not
  # 'bypassed' or 'abandoned'). That collapsed two distinct lifecycle
  # paths into one and broke the W7 successor-handoff use case the
  # close was added to support — a successor reading the log could not
  # tell an accepted bypass from a closed-by-the-side-effects escalation.
  #
  # D3 fix (post-PR-A): same adjacent-mktemp atomicity fix as
  # bypass_audit_append above.
  #
  # Audit fix code-lib-2 (2026-06-28): mirror append's chmod-preserve
  # + EXIT/INT/TERM trap so close_pending doesn't silently downgrade
  # operator-set perms or leave orphan tmp files on signal.
  #
  # Verifier follow-up (2026-06-28): subshell-isolate the trap (see
  # bypass_audit_append for rationale). Function-scope traps clobber
  # the caller's EXIT handler shell-wide; the subshell contains it.
  local rc=0
  (
    tmp=$(mktemp "${file}.XXXXXX") || exit 1
    trap 'rm -f "$tmp"; rmdir "$lock_dir" 2>/dev/null' EXIT INT TERM
    if jq --arg ur "$user_resp" --arg fo "$final_out" \
         '[.[] | if .type == "claude_bypass_proposal" and .user_response == "PENDING" then .user_response = $ur | .final_outcome = $fo else . end]' \
         "$file" > "$tmp" 2>/dev/null; then
      _bypass_audit_preserve_mode "$file" "$tmp"
      mv "$tmp" "$file" || exit 1
      trap - EXIT INT TERM
      exit 0
    else
      rm -f "$tmp"
      echo "[FAIL] bypass_audit_close_pending: jq failed" >&2
      trap - EXIT INT TERM
      exit 1
    fi
  ) || rc=1

  rmdir "$lock_dir" 2>/dev/null
  return "$rc"
}
