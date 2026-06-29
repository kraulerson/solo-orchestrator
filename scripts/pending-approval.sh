#!/usr/bin/env bash
# scripts/pending-approval.sh — Solo Orchestrator pending-approval sentinel helper (BL-015)
#
# Writes / reads / validates .claude/pending-approval.json to coordinate
# blocking user decisions across the CDF stop-hook (4.2.3+) and Solo's
# pre-commit-gate. See docs/builders-guide.md § "Structured Decision Points".
#
# Schema (CDF 4.2.3 contract):
#   {
#     "question": "string (non-empty)",
#     "options": ["A1: foo", "A2: bar", ...],          # >= 2 entries
#     "recommendation": "A1",                          # leading id of one option
#     "offered_at": "2026-04-25T12:00:00Z"             # ISO-8601 UTC
#   }
#
# Existence alone signals "user is deciding" — both consumers honor file
# presence regardless of validity. Malformed files are not auto-cleaned;
# `rm` manually or use `--clear`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/lib/helpers.sh" ]; then
  source "$SCRIPT_DIR/lib/helpers.sh"
else
  print_ok()   { echo "[OK] $1"; }
  print_fail() { echo "[FAIL] $1" >&2; }
  print_info() { echo "[INFO] $1"; }
fi

# --- Helpers ---

find_project_root() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    [ -d "$dir/.claude" ] && { echo "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  return 1
}

iso_timestamp_utc() {
  date -u "+%Y-%m-%dT%H:%M:%SZ"
}

leading_id() {
  local s="$1"
  if [[ "$s" == *:* ]]; then
    echo "${s%%:*}"
  else
    echo "$s"
  fi
}

sentinel_path() {
  echo "$1/.claude/pending-approval.json"
}

# --- Subcommand: --offer ---

cmd_offer() {
  local question="" recommendation=""
  local -a options=()

  while [ $# -gt 0 ]; do
    case "$1" in
      --question)        question="$2"; shift 2 ;;
      --recommendation)  recommendation="$2"; shift 2 ;;
      --options)
        shift
        while [ $# -gt 0 ] && [[ "$1" != --* ]]; do
          options+=("$1")
          shift
        done
        ;;
      *)
        if [ -z "$question" ] && [[ "$1" != --* ]]; then
          question="$1"; shift
        else
          print_fail "Unknown argument: $1"
          return 1
        fi
        ;;
    esac
  done

  if [ -z "$question" ]; then
    print_fail "--offer requires a non-empty question (positional arg or --question)."
    return 1
  fi
  if [ "${#options[@]}" -lt 2 ]; then
    print_fail "--offer requires at least 2 options via --options."
    return 1
  fi
  if [ -z "$recommendation" ]; then
    print_fail "--offer requires --recommendation."
    return 1
  fi
  local match=false opt id
  for opt in "${options[@]}"; do
    id=$(leading_id "$opt")
    if [ "$id" = "$recommendation" ]; then
      match=true
      break
    fi
  done
  if [ "$match" = false ]; then
    print_fail "--recommendation '$recommendation' does not match the leading id of any option."
    print_fail "Options: ${options[*]}"
    return 1
  fi

  local project_root
  project_root=$(find_project_root) || {
    print_fail "Not in a Solo project — no .claude/ directory found in \$PWD or any parent."
    return 1
  }
  local sentinel
  sentinel=$(sentinel_path "$project_root")

  if [ -f "$sentinel" ]; then
    local existing_q existing_at
    existing_q=$(jq -r '.question // "(unparseable)"' "$sentinel" 2>/dev/null || echo "(unparseable)")
    existing_at=$(jq -r '.offered_at // "(unknown)"' "$sentinel" 2>/dev/null || echo "(unknown)")
    print_fail "A pending approval already exists: \"$existing_q\" (offered $existing_at)."
    echo "Resolve or clear the existing one first:" >&2
    echo "  scripts/pending-approval.sh --resolve   # user picked" >&2
    echo "  scripts/pending-approval.sh --clear     # abort the question" >&2
    return 1
  fi

  local now
  now=$(iso_timestamp_utc)
  local options_json
  options_json=$(printf '%s\n' "${options[@]}" | jq -R . | jq -s .)
  local payload
  payload=$(jq -n \
    --arg q "$question" \
    --argjson opts "$options_json" \
    --arg rec "$recommendation" \
    --arg at "$now" \
    '{question: $q, options: $opts, recommendation: $rec, offered_at: $at}')

  local tmpfile
  tmpfile=$(mktemp "$project_root/.claude/pending-approval.XXXXXX.tmp")
  printf '%s\n' "$payload" > "$tmpfile"
  mv "$tmpfile" "$sentinel"

  print_ok "Pending approval offered: $question"
}

# --- Subcommand: --resolve ---

cmd_resolve() {
  local project_root decision=""
  # Parse optional --decision <accept|decline>.
  while [ $# -gt 0 ]; do
    case "$1" in
      --decision) decision="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done

  # code-escalate-pending-4 (audit v2, S3): validate --decision
  # BEFORE deleting the sentinel. Pre-fix, cmd_resolve removed the
  # sentinel first and only afterward called bypass_audit_close_pending,
  # which rejected unknown decisions with exit 1. A typo such as
  # `--decision accpet` therefore produced the documented [OK]+[FAIL]
  # split: sentinel deleted (consumers unblocked) but PENDING audit
  # rows stranded — the W7 successor-handoff governance record was
  # silently half-built until the operator noticed and re-ran with
  # the correct decision string.
  if [ -n "$decision" ]; then
    case "$decision" in
      accept|decline) ;;
      *)
        print_fail "--resolve: unknown decision '$decision' (expected: accept | decline). Sentinel left in place."
        echo "  Re-run: scripts/pending-approval.sh --resolve --decision accept" >&2
        echo "      or: scripts/pending-approval.sh --resolve --decision decline" >&2
        return 1
        ;;
    esac
  fi

  project_root=$(find_project_root) || {
    print_fail "Not in a Solo project — no .claude/ directory found in \$PWD or any parent."
    return 1
  }
  local sentinel
  sentinel=$(sentinel_path "$project_root")
  if [ -f "$sentinel" ]; then
    rm -f "$sentinel"
    print_ok "Pending approval resolved."
  else
    print_info "No pending approval."
  fi

  # BL-029.1 S4 (2026-05-04): if a decision was provided, close any
  # PENDING claude_bypass_proposal rows in the audit log to match.
  # Without this, audit rows stay PENDING forever and the W7 successor-
  # handoff use case (audit log as historical governance record) is
  # half-built.
  if [ -n "$decision" ]; then
    local lib="$SCRIPT_DIR/lib/bypass-audit.sh"
    if [ -f "$lib" ]; then
      # shellcheck disable=SC1090
      source "$lib"
      if bypass_audit_close_pending "$project_root" "$decision" 2>&1; then
        print_ok "Audit log closed: pending bypass rows marked $decision."
      else
        print_fail "Audit log close failed (decision='$decision')."
        echo "  Re-run 'pending-approval --resolve --decision $decision' to retry the audit close." >&2
        return 1
      fi
    fi
  fi
}

# --- Subcommand: --clear ---

cmd_clear() {
  local project_root
  project_root=$(find_project_root) || {
    print_fail "Not in a Solo project — no .claude/ directory found in \$PWD or any parent."
    return 1
  }
  local sentinel
  sentinel=$(sentinel_path "$project_root")
  if [ -f "$sentinel" ]; then
    rm -f "$sentinel"
    print_ok "Pending approval cleared (abort)."
  else
    print_ok "No pending approval."
  fi
}

# --- Subcommand: --status ---

cmd_status() {
  local project_root
  project_root=$(find_project_root) || {
    print_fail "Not in a Solo project — no .claude/ directory found in \$PWD or any parent."
    return 1
  }
  local sentinel
  sentinel=$(sentinel_path "$project_root")
  if [ ! -f "$sentinel" ]; then
    print_ok "No pending approval."
    return 0
  fi
  if ! jq -e . "$sentinel" >/dev/null 2>&1; then
    print_info "Malformed sentinel present at $sentinel"
    return 0
  fi
  local q rec at
  q=$(jq -r '.question // "(missing)"' "$sentinel")
  rec=$(jq -r '.recommendation // "(missing)"' "$sentinel")
  at=$(jq -r '.offered_at // "(missing)"' "$sentinel")
  echo "Pending question: \"$q\""
  echo "Options:"
  jq -r '.options[]? // empty | "  " + .' "$sentinel"
  echo "Recommendation: $rec"
  echo "Offered at: $at"
}

# --- Subcommand: --validate ---

cmd_validate() {
  local path="${1:-}"
  if [ -z "$path" ]; then
    local project_root
    if project_root=$(find_project_root); then
      path=$(sentinel_path "$project_root")
    else
      print_ok "No sentinel to validate."
      return 0
    fi
  fi
  if [ ! -f "$path" ]; then
    print_ok "No sentinel to validate."
    return 0
  fi
  if ! jq -e . "$path" >/dev/null 2>&1; then
    print_fail "Malformed JSON: $path"
    return 1
  fi
  local q opts_count rec at_present
  q=$(jq -r '.question // ""' "$path")
  opts_count=$(jq -r '.options // [] | length' "$path")
  rec=$(jq -r '.recommendation // ""' "$path")
  at_present=$(jq -r 'has("offered_at")' "$path")
  if [ -z "$q" ]; then
    print_fail "Schema error: question missing or empty"
    return 1
  fi
  if [ "$opts_count" -lt 2 ]; then
    print_fail "Schema error: options must have at least 2 entries (got $opts_count)"
    return 1
  fi
  if [ -z "$rec" ]; then
    print_fail "Schema error: recommendation missing or empty"
    return 1
  fi
  if [ "$at_present" != "true" ]; then
    print_fail "Schema error: offered_at missing"
    return 1
  fi
  local match=false opt id
  while IFS= read -r opt; do
    id=$(leading_id "$opt")
    if [ "$id" = "$rec" ]; then
      match=true
      break
    fi
  done < <(jq -r '.options[]' "$path")
  if [ "$match" = false ]; then
    print_fail "Schema error: recommendation '$rec' does not match the leading id of any option"
    return 1
  fi
  print_ok "Valid sentinel."
}

# --- Subcommand: --help ---

cmd_help() {
  cat <<HELP
Usage: scripts/pending-approval.sh [COMMAND] [ARGS]

Commands:
  --offer "QUESTION" --options "A1: ..." "A2: ..." ... --recommendation "A1"
                                  Write a pending-approval sentinel.
                                  Refuses if one already exists.
  --resolve [--decision X]        Delete the sentinel (user picked an option).
                                  Optional: --decision accept|decline closes
                                  any PENDING claude_bypass_proposal rows in
                                  .claude/bypass-audit.json to match (BL-029.1).
  --clear                         Delete the sentinel (agent abort, semantic alias).
  --status                        Print the current pending question, if any.
  --validate [PATH]               Lint a sentinel file. Default: .claude/pending-approval.json.
  --help, -h                      Show this help.

The sentinel file is .claude/pending-approval.json. Both the CDF stop-hook
(4.2.3+) and Solo's pre-commit-gate honor it as "user is deciding."

See docs/builders-guide.md "Structured Decision Points" for the full
lifecycle and rationale.
HELP
}

# --- Dispatch ---

case "${1:-}" in
  --offer)    shift; cmd_offer "$@" ;;
  --resolve)  shift; cmd_resolve "$@" ;;
  --clear)    shift; cmd_clear ;;
  --status)   shift; cmd_status ;;
  --validate) shift; cmd_validate "${1:-}" ;;
  --help|-h|"") cmd_help ;;
  *)
    print_fail "Unknown command: $1"
    cmd_help >&2
    exit 1
    ;;
esac
