#!/usr/bin/env bash
# scripts/pending-approval.sh — Solo Orchestrator pending-approval sentinel helper (BL-015)
#
# Writes / reads / validates .claude/pending-approval.json to coordinate
# blocking user decisions across the Development Guardrails (CDF) and Solo's
# pre-commit-gate. See docs/builders-guide.md § "Structured Decision Points".
#
# Schema 2 (`## BL-320:` — CDF 4.4.0's approval design B, D1):
#   {
#     "schema": 2,
#     "question": "string (non-empty)",
#     "options": [{"id": "A1", "text": "...", "approves": "commit"},
#                 {"id": "A2", "text": "...", "approves": "none"}],   # >= 2
#     "recommendation": "A1",                          # one option's id
#     "offered_at": "2026-10-06T12:00:00Z"             # ISO-8601 UTC
#   }
# Ids are a letter and one or two digits (A1 ... Z99), unique ignoring case. At
# least one option approves nothing. An option approves a commit only when
# --approves names it, and such a question is refused unless a change is
# staged: stage exactly the change, THEN ask. With the Guardrails at
# SOIF_GUARDRAILS_MIN (scripts/lib/guardrails.sh) or later the user answers by
# replying with the option id, twice; the Guardrails' record-approval.sh shows
# them the staged change, records the pick in .claude/approvals.jsonl and
# removes this file. --resolve and --clear only clean up.
#
# Schema 1 (the CDF 4.2.3 contract this script wrote before BL-320) is still
# read by --status and --validate: options were "A1: text" strings.
#
# Existence alone signals "user is deciding" — every consumer honors file
# presence regardless of validity. Malformed files are not auto-cleaned;
# use --clear.

set -euo pipefail

# `## BL-320:` the schema this writer produces. A project's other scripts read
# this line (scripts/lib/guardrails.sh soif_gr_writer_schema) to tell a writer
# that predates schema 2 — a project whose Guardrails must not move to 4.4.0
# without it. Keep it a plain assignment at the start of a line.
SOIF_APPROVAL_SCHEMA=2   # BL-320-PA-SCHEMA-MARK

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# BL-046: uses print_ok/fail/info + guard_not_in_framework only — core subset.
if [ -f "$SCRIPT_DIR/lib/helpers-core.sh" ]; then
  source "$SCRIPT_DIR/lib/helpers-core.sh"
else
  print_ok()   { echo "[OK] $1"; }
  print_fail() { echo "[FAIL] $1" >&2; }
  print_info() { echo "[INFO] $1"; }
  # When helpers-core.sh is unavailable (vendored stub install), no-op the
  # framework guard: there's nothing to source. The full Solo install always
  # ships helpers.
  guard_not_in_framework() { return 0; }
fi

# `## BL-320:` schema-2 rules and the Guardrails route (pick | legacy |
# unknown) live in one shared lib. Without it --offer and --validate refuse.
if [ -f "$SCRIPT_DIR/lib/guardrails.sh" ]; then
  # shellcheck source=scripts/lib/guardrails.sh
  . "$SCRIPT_DIR/lib/guardrails.sh"
fi
_pa_need_lib() {
  command -v soif_pa_v2_problems >/dev/null 2>&1 && return 0
  print_fail "scripts/lib/guardrails.sh is missing, so a question cannot be checked against the Development Guardrails' rules. Re-sync this project's framework scripts."
  return 1
}
_pa_route() { if command -v soif_gr_route >/dev/null 2>&1; then soif_gr_route "$1"; else echo unknown; fi; }

# security-audits-2 (S3, 2026-04-26 audit sweep): the helpers.sh docstring at
# guard_not_in_framework explicitly names scripts/pending-approval.sh as a
# script that MUST call the guard before any file writes. The pre-existing
# script wrote .claude/pending-approval.json via cmd_offer (and cmd_resolve
# deleted+rewrote it) without ever invoking the guard — a contract violation
# silently missed by the bl-015 audit. Invoke the guard at dispatch time so
# every subcommand (including read-only ones like --status / --validate)
# refuses to operate when cwd is the framework repo. Read-only commands are
# also gated because the find_project_root walk would otherwise return the
# framework root, painting an inconsistent picture for the caller.
guard_not_in_framework || exit 1

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

# _pa_has_staged ROOT — true when the index differs from HEAD (a change is
# staged). An unstaged edit does not count; outside a git repository nothing is.
_pa_has_staged() {
  local rc=0
  git -C "$1" rev-parse --git-dir >/dev/null 2>&1 || return 1
  git -C "$1" diff --cached --quiet 2>/dev/null || rc=$?
  [ "$rc" -eq 1 ]
}

cmd_offer() {
  local question="" recommendation="" opt id text a n_approves=0 ids=""
  local -a options=() approves=()

  while [ $# -gt 0 ]; do
    case "$1" in
      --question)        question="$2"; shift 2 ;;
      --recommendation)  recommendation="$2"; shift 2 ;;
      --approves)        approves+=("${2:-}"); n_approves=$((n_approves + 1)); shift 2 ;;
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
  _pa_need_lib || return 1

  # Each option is "ID: what picking it does". Its effect starts as "none"; an
  # option approves a commit only when --approves names it.
  local options_json="[]"
  for opt in "${options[@]}"; do
    id="$(leading_id "$opt")"
    text=""
    [[ "$opt" == *:* ]] && text="${opt#*:}"
    text="${text#"${text%%[![:space:]]*}"}"
    if [ -z "$text" ]; then
      print_fail "option '$opt' has no text after its id. Write each option as \"A1: what picking it does\"."
      return 1
    fi
    options_json="$(jq -c --arg id "$id" --arg t "$text" '. + [{id: $id, text: $t, approves: "none"}]' <<< "$options_json")"
    ids="${ids:+$ids, }$id"
  done
  for a in ${approves[@]+"${approves[@]}"}; do
    jq -e --arg a "$a" 'any(.[]; (.id | ascii_upcase) == ($a | ascii_upcase))' <<< "$options_json" >/dev/null || { print_fail "--approves '$a' names no option (the ids are: $ids)."; return 1; }   # BL-320-OFFER-APPROVES-ID
    options_json="$(jq -c --arg a "$a" 'map(if (.id | ascii_upcase) == ($a | ascii_upcase) then .approves = "commit" else . end)' <<< "$options_json")"
  done

  local match=false
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

  # Stage, THEN ask: the Guardrails bind an approval to the staged change the
  # user is shown, so an approving question with nothing staged approves
  # nothing — after the user has replied twice. Refused here instead.
  [ "$n_approves" -eq 0 ] || _pa_has_staged "$project_root" || { print_fail "--approves needs a staged change, and nothing is staged. Stage exactly the change to commit (git add <files>), then ask."; return 1; }   # BL-320-OFFER-STAGED

  if [ -f "$sentinel" ]; then
    local existing_q existing_at
    existing_q=$(jq -r '.question // "(unparseable)"' "$sentinel" 2>/dev/null || echo "(unparseable)")
    existing_at=$(jq -r '.offered_at // "(unknown)"' "$sentinel" 2>/dev/null || echo "(unknown)")
    print_fail "A pending approval already exists: \"$existing_q\" (offered $existing_at)."
    echo "Wait for the user's answer, or withdraw it first:" >&2
    echo "  scripts/pending-approval.sh --clear     # withdraw the question" >&2
    return 1
  fi

  local now
  now=$(iso_timestamp_utc)
  local payload
  payload=$(jq -n --arg q "$question" --argjson opts "$options_json" --arg rec "$recommendation" --arg at "$now" '{schema: 2, question: $q, options: $opts, recommendation: $rec, offered_at: $at}')   # BL-320-OFFER-SCHEMA

  local tmpfile problems
  # Trailing Xs (review round 1, R-1): BSD mktemp randomises only those, and
  # with "XXXXXX.tmp" it created that literal name — so a temp file left by an
  # interrupted offer made every later one fail.
  tmpfile=$(mktemp "$project_root/.claude/pending-approval.json.XXXXXX")   # BL-320-OFFER-TMP
  printf '%s\n' "$payload" > "$tmpfile"
  problems="$(soif_pa_v2_problems "$tmpfile")"
  if [ -n "$problems" ]; then
    rm -f "$tmpfile"
    while IFS= read -r a; do [ -n "$a" ] && print_fail "The Development Guardrails could not take an answer to this question: $a."; done <<< "$problems"
    return 1
  fi
  mv "$tmpfile" "$sentinel"

  print_ok "Pending approval offered: $question"
  if [ "$(_pa_route "$project_root")" = pick ]; then
    echo "Stop now and wait. The user answers by replying with the option id first (for example: $recommendation),"
    echo "then again once the Development Guardrails have shown them the question and the staged change."
    # `## BL-322:` S4 (dogfood run 3, finding 14): the commit's shape, here,
    # where the agent reads it just before it commits — it had been learned
    # from refusals. The Guardrails' commit_shape_problem refuses anything but
    # a lone `git commit` with message options under an approval, and
    # config-guard refuses a command whose text — the message included — names
    # a protected path or (4.4.1) a hook script that writes approvals. Only
    # for a question that can approve a commit.
    if [ "$n_approves" -gt 0 ]; then   # BL-322-S4-OFFER-IF
      echo "After a pick that approves the commit, commit with one lone command: git commit -m \"subject\" -m \"body\""   # BL-322-S4-OFFER-COMMIT
      echo "(one -m per paragraph; nothing before it, not even cd <folder> &&; nothing after it; no -a, no paths)."
      echo "If the message names a Guardrails hook script (mark-evaluated.sh, record-approval.sh, marker-tracker.sh,"
      echo "session-start.sh, session-end.sh, stop-checklist.sh, mark-plan-closed.sh) or a path they protect, such as"
      echo ".claude/settings.json, .claude/manifest.json, .claude/framework, .git/hooks or .git/config, they refuse the"
      echo "command: write the message to a file outside the project with the Write tool, then: git commit -F <that file>"   # BL-322-S4-OFFER-FILE
    fi
  else
    echo "Stop now and wait for the user's answer, then: scripts/pending-approval.sh --resolve"
  fi
}

# --- Subcommand: --resolve ---

# --resolve: the question is over. It removes a question still on disk (with
# Guardrails 4.4.0 and later the user's pick has already removed it, so one
# still there was not answered and is withdrawn), then closes the bypass-audit
# rows whose question the user picked an answer to, reading the pick from
# .claude/approvals.jsonl — the file only the Guardrails write.
# --decision accept|decline is the agent's own account of the answer, used
# only where the Guardrails record no pick (older than SOIF_GUARDRAILS_MIN).
cmd_resolve() {
  local project_root decision="" route
  # Parse optional --decision <accept|decline>.
  while [ $# -gt 0 ]; do
    case "$1" in
      --decision) decision="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done

  project_root=$(find_project_root) || {
    print_fail "Not in a Solo project — no .claude/ directory found in \$PWD or any parent."
    return 1
  }
  route="$(_pa_route "$project_root")"
  # FAILS CLOSED (review round 1, R-3): --decision is the agent's own account of
  # the user's answer, so it is accepted only where the Guardrails are KNOWN to
  # be older than the minimum and record no pick. With 4.4.0 or later, with no
  # readable version, or with scripts/lib/guardrails.sh missing (the route then
  # reads "unknown"), it is refused.
  [ -z "$decision" ] || [ "$route" = legacy ] || { print_fail "--decision is not used here: it is accepted only where the Development Guardrails are known to be older than ${SOIF_GUARDRAILS_MIN:-4.4.0}, which record no pick (this project: ${route}). With 4.4.0 and later the user's pick is recorded by the Guardrails in .claude/approvals.jsonl, and --resolve reads it from there. Nothing was changed."; return 1; }   # BL-320-RESOLVE-DECISION

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

  local sentinel
  sentinel=$(sentinel_path "$project_root")
  if [ -f "$sentinel" ]; then
    rm -f "$sentinel"
    if [ "$route" = pick ]; then
      print_ok "Pending question withdrawn: the user had not answered it, so nothing was approved."
    else
      print_ok "Pending approval resolved."
    fi
  else
    print_info "No pending approval."
  fi

  # BL-029.1 S4 (2026-05-04): if a decision was provided, close any
  # PENDING claude_bypass_proposal rows in the audit log to match.
  # Without this, audit rows stay PENDING forever and the W7 successor-
  # handoff use case (audit log as historical governance record) is
  # half-built.
  local lib="$SCRIPT_DIR/lib/bypass-audit.sh"
  if [ -n "$decision" ]; then
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

  # `## BL-320:` the user's own pick decides a bypass question.
  if [ -f "$lib" ]; then
    # shellcheck disable=SC1090
    source "$lib"
    local closed=0
    if ! command -v bypass_audit_close_from_approvals >/dev/null 2>&1; then
      [ ! -f "$project_root/.claude/approvals.jsonl" ] || { print_fail "scripts/lib/bypass-audit.sh predates BL-320 and cannot read the user's picks from .claude/approvals.jsonl, so no bypass decision was recorded. Re-sync this project's framework scripts (upgrade-project.sh --sync-framework, from the framework's clone)."; return 1; }   # BL-320-RESOLVE-READER
      return 0
    fi
    closed="$(bypass_audit_close_from_approvals "$project_root")" || { print_fail "Could not read the user's picks from .claude/approvals.jsonl into the audit log."; return 1; }   # BL-320-RESOLVE-RECONCILE
    [ "${closed:-0}" = 0 ] || print_ok "Audit log: $closed pending bypass row(s) closed from the user's pick in .claude/approvals.jsonl."
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
  if command -v soif_pa_option_lines >/dev/null 2>&1; then
    soif_pa_option_lines "$sentinel" | sed 's/^/  /'
  else
    jq -r '(.options // [])[]? | "  " + tostring' "$sentinel"
  fi
  echo "Recommendation: $rec"
  echo "Offered at: $at"
}

# --- Subcommand: --validate ---

cmd_validate() {
  local path="${1:-}" project_root=""
  if [ -z "$path" ]; then
    if project_root=$(find_project_root); then
      path=$(sentinel_path "$project_root")
    else
      print_ok "No sentinel to validate."
      return 0
    fi
  else
    project_root=$(find_project_root) || project_root=""
  fi
  if [ ! -f "$path" ]; then
    print_ok "No sentinel to validate."
    return 0
  fi
  if ! jq -e . "$path" >/dev/null 2>&1; then
    print_fail "Malformed JSON: $path"
    return 1
  fi
  _pa_need_lib || return 1
  local q opts_count rec at_present problems p
  rec=$(jq -r '.recommendation // ""' "$path")
  at_present=$(jq -r 'has("offered_at")' "$path")
  if [ "$(soif_pa_schema "$path")" = 2 ]; then
    problems="$(soif_pa_v2_problems "$path")"
    if [ -n "$problems" ]; then
      while IFS= read -r p; do [ -n "$p" ] && print_fail "Schema error: $p"; done <<< "$problems"
      return 1
    fi
    if [ -z "$rec" ] || ! jq -e --arg r "$rec" 'any(.options[]; .id == $r)' "$path" >/dev/null 2>&1; then
      print_fail "Schema error: recommendation '$rec' is not an option id"
      return 1
    fi
    if [ "$at_present" != "true" ]; then
      print_fail "Schema error: offered_at missing"
      return 1
    fi
    print_ok "Valid sentinel (schema 2)."
    return 0
  fi
  q=$(jq -r '.question // ""' "$path")
  opts_count=$(jq -r '.options // [] | length' "$path")
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
  done < <(jq -r '.options[] | tostring' "$path")
  if [ "$match" = false ]; then
    print_fail "Schema error: recommendation '$rec' does not match the leading id of any option"
    return 1
  fi
  [ -z "$project_root" ] || [ "$(_pa_route "$project_root")" != pick ] || { print_fail "Schema error: schema 1 — the Development Guardrails ${SOIF_GUARDRAILS_MIN:-4.4.0} and later cannot take an answer to it. Withdraw it (--clear) and ask again with --offer."; return 1; }   # BL-320-VALIDATE-V1
  print_ok "Valid sentinel (schema 1)."
}

# --- Subcommand: --help ---

cmd_help() {
  cat <<HELP
Usage: scripts/pending-approval.sh [COMMAND] [ARGS]

Commands:
  --offer "QUESTION" --options "A1: ..." "A2: ..." ... --recommendation "A1" [--approves A1 ...]
                                  Write the question (schema 2). Option ids are
                                  a letter and one or two digits. --approves ID
                                  (repeatable) marks an option that approves
                                  committing the STAGED change; it is refused
                                  when nothing is staged, and at least one
                                  option must approve nothing.
                                  Refuses if a question already exists.
  --resolve [--decision X]        The question is over: remove it if it is still
                                  there, and close the bypass-audit rows the
                                  user's pick in .claude/approvals.jsonl answers.
                                  --decision accept|decline is accepted only
                                  with Development Guardrails older than 4.4.0,
                                  which record no pick (BL-029.1).
  --clear                         Withdraw the question (abort).
  --status                        Print the current question and what each option does.
  --validate [PATH]               Lint a question file. Default: .claude/pending-approval.json.
  --help, -h                      Show this help.

The question is .claude/pending-approval.json. The Development Guardrails'
stop hook and Solo's pre-commit-gate honor it as "user is deciding". With
Guardrails 4.4.0 and later the user answers by replying with the option id,
twice, and the Guardrails remove it.

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
