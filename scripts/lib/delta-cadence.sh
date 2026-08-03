#!/usr/bin/env bash
# scripts/lib/delta-cadence.sh — the delta module's DATE ARITHMETIC: the hotfix
# retro ledger's due/overdue predicates, and the parse helper they and §8.3's
# cadence checker are both built on.
#
# SPEC: docs/designs/2026-08-02-delta-track-v1.md §5.2 (the hotfix row, and
# "reading the hotfix row honestly" — the fast lane is a LOAN, collateralised by
# the release refusal), §7.1 (`hotfix_retros[]`, an array that OUTLIVES
# `active_delta` deliberately: "an open retro must block a release cut long
# after its delta closed"), §7.2 (`classes.hotfix.retro_due_days`), §9.2 (the
# release refusals — refusal 2 is this file's whole reason to exist), §3.1 (a
# member of the severable delta module's inventory), §11-WP5.
#
# (No `# BL-NNN-…` marker anywhere in the delta track on purpose — no backlog
# entry exists for this build, and minting one would red
# scripts/lint-bl-markers.sh, whose first pass resolves every marker to a real
# `## BL-NNN:` entry. The design-doc path above is the citation, per the WP1,
# WP2, WP3 and WP4 precedent. The grep-able `DELTA-CADENCE-*` markers below are
# this file's citation primitive and its mutation addresses.)
#
# ═════════════════════════════════════════════════════════════════════════════
# THE INTERFACE WP7's `scripts/cut-release.sh` CONSUMES — designed for it
#
# §9.2's second refusal is "any `hotfix_retros[]` with `closed_at == null`.
# Names the delta, its `due_by`, and how overdue it is." That sentence names
# exactly three things, so this file exposes exactly three shapes: a whole-
# ledger yes/no for the refusal itself, a per-row verdict for a targeted
# question, and a renderable row list for the message.
#
# ★ THE CALLING SHAPE — USE THE STRICT READ, NOT THE TOLERANT ONE (R-WP5-2):
#
#     doc="$(bash scripts/process-checklist.sh --delta-state-read-strict)"; rc=$?
#     case "$rc" in
#       0) : ;;                        # a real ledger; ask it the questions below
#       3) refuse "the delta record exists and cannot be read — repair it before
#                  cutting a release" ;;
#       4) refuse "there is no delta record at all" ;;   # see the note below
#     esac
#     if delta_any_open_retro "$doc"; then
#       delta_retro_rows "$doc" | while IFS= read -r r; do … done   # the message
#       exit 1                                                       # the refusal
#     fi
#
# WHY `--delta-state-read-strict` AND NOT `--delta-state-read`. The tolerant
# read answers a corrupt file with the EMPTY SCHEMA at rc 0 (warning on stderr
# only) and an ABSENT file with the empty schema in complete silence. An
# adversarial review walked that straight through the shape this header used to
# document: with a retro owed, corrupting the state file — or `rm`-ing it —
# made `delta_any_open_retro` answer "nothing owed", so §9.2's refusal never
# fired. That is BL-213's fail-open class one level up from the dates this file
# already refuses it for. Illegibility of a due DATE is treated as overdue;
# illegibility of the LEDGER must not be treated as absolution.
#
# ON rc 4 (no state file at all): a project that has never opened a delta has
# nothing to release either — §9.1 already refuses a cut with "nothing closed
# since the last tag" — so treating 4 as a refusal costs a real project nothing
# and closes the one-keystroke erasure. It is a SEPARATE code from 3 so the
# caller can say which one happened; do not collapse them.
#
# EVERY FUNCTION TAKES THE STATE DOCUMENT, NOT A PROJECT ROOT, and that is the
# design rather than an inconvenience. `.claude/delta-state.json` has ONE reader
# and ONE writer (§7.1/D7) — scripts/lib/delta-state.sh, reached through the
# seam. A cadence lib that opened the file itself would be a second reader, and
# the single-reader property is what makes the fallback contract in
# delta_state_read a guarantee for every consumer instead of a local courtesy.
# So callers read once, through the seam, and pass the document down.
#
# EXIT CODES ARE THE ANSWER; NOTHING HERE PRINTS PROSE. CLAUDE.md's `[WARN]`
# trap is that a label and an exit predicate can disagree, so the predicates
# below have no labels to disagree with. The one function that prints
# (delta_retro_rows) prints DATA — tab-separated fields for a caller to render —
# never a sentence.
#
#     delta_retro_overdue <doc> <id>
#         0  OVERDUE — due_by is in the past, OR could not be read at all
#         1  open and not yet due
#         2  there is no OPEN retro with that id (filed, or no such row)
#         3  UNDETERMINED — that document is not a readable ledger
#     delta_any_open_retro <doc>
#         0  at least one row has closed_at == null   1  none   3 UNDETERMINED
#     delta_any_overdue_retro <doc>
#         0  at least one OPEN row is overdue or unreadable
#         1  none                                     3 UNDETERMINED
#     delta_retro_rows <doc>
#         one TSV row per OPEN retro, rc 0:
#             id <TAB> due_by <TAB> state <TAB> days
#         state ∈ current | overdue | undetermined
#         days  = whole days OVERDUE for `overdue`, whole days REMAINING for
#                 `current`, and the literal `-` for `undetermined` (there is no
#                 number to give, and inventing one is how a placeholder becomes
#                 a fact three surfaces downstream)
#         rc 3 and NOTHING printed when the document is not a readable ledger
#
# ★ rc 3 IS THE SECOND HALF OF THE FAIL-CLOSED REPAIR, and it is deliberately
# NOT folded into 1 ("none owed") or 2 ("no such open retro"). A caller that
# treated "I cannot read the ledger" as "nothing is owed" is the defect; a
# caller that treats it as a refusal is correct. The strict read above is what
# normally prevents a caller ever seeing it — this is the backstop for a caller
# that acquired the document some other way (a `cat`, a pipeline, a future
# surface), because a contract that only holds when everyone uses the right
# front door is a convention, not a property.
#
# THE PREDICATES RETURN NON-ZERO IN THE ORDINARY CASE, so a caller under `set -e`
# must use them in an `if`, `||` or `!` context — and one that cares about the
# difference between "no" and "cannot tell" must capture `$?` rather than
# branching on truthiness alone. That is the shell's own convention for a
# predicate and is deliberate.
#
# ═════════════════════════════════════════════════════════════════════════════
# FAIL-CLOSED ON AN UNREADABLE DATE — BL-213's CLASS, AND WHY IT IS HERE
#
# §14-V13 records the shipped sibling defect: scripts/check-maintenance.sh
# resolves an unparseable date to epoch 0, then guards every arm with
# `[ "$last_epoch" -gt 0 ]`, so a scan file it could not read is skipped
# ENTIRELY and the script prints "All maintenance cadences current" and exits 0.
# A date nobody could read became a clean bill of health. WP6 repairs that
# script by adding an `undetermined` counter and a new exit 2.
#
# This file must not reproduce it, and the direction is not symmetric with
# check-maintenance's. There, the unreadable value is a LAST-DONE date and the
# fail-closed answer is "assume it is ancient". Here it is a DUE date and the
# fail-closed answer is "assume it has passed" — an unreadable `due_by` is
# OVERDUE, an absent one is OVERDUE, and a `null` one is OVERDUE. The collateral
# on a loan cannot be released because the paperwork became illegible.
#
# Concretely: delta_cadence_epoch returns non-zero AND PRINTS NOTHING when
# neither parser accepts its input — printing a stale or zero value would let a
# caller that ignored the return code read it as a date, which is exactly the
# `|| echo "0"` shape that produced the original defect. Its one caller,
# delta_retro_rows, turns that failure into `undetermined`, and BOTH overdue
# predicates count `undetermined` as overdue. The atom is
# `# DELTA-CADENCE-UNPARSEABLE` and tests/test-delta-wp5-hotfix-retro.sh's m3
# neuters it to prove the exit code moves.
#
# ═════════════════════════════════════════════════════════════════════════════
# THE TWO CLOCKS ARE DIFFERENT ON PURPOSE, AND NEITHER IS BUILT INTO THE OTHER
#
# §5.2: `templates/generated/incident-response.tmpl` already owns the
# SEV→response-time notification chain (Immediate / 1 h / 4 h / next window),
# the escalation rule, and a post-incident review "within 48 hours of
# resolution" filed at `docs/incidents/YYYY-MM-DD-<slug>.md`. NONE of that is
# duplicated here or anywhere in the delta track. The incident template's 48 h
# governs the INCIDENT write-up; `retro_due_days` governs the CODE retro; they
# are deliberately different clocks and both are readable from
# `.claude/delta-policy.json` so a project can align them if it wants to. Do not
# make this file read the incident template, and do not make the incident
# template read this policy — the whole point of §7.2 holding both is that the
# alignment is the PROJECT's decision and not the framework's.
#
# ═════════════════════════════════════════════════════════════════════════════
# DEPENDENCY DIRECTION (D1)
#   delta -> core is allowed and deliberately unasserted. core -> delta is
#   forbidden and lint-enforced by scripts/lint-delta-boundary.sh, with ONE
#   allowlisted seam. This file sources nothing at all.
#
# BASH 3.2 COMPATIBILITY
#   macOS ships bash 3.2.57. No associative arrays, no ${var,,}, no `((x++))`.
#   Every function is errexit-safe: this lib is sourced into scripts/delta.sh
#   (and, in WP7, scripts/cut-release.sh), both of which run under
#   `set -euo pipefail`, so no bare command is left to fail on its own.

# ─────────────────────────────────────────────────────────────────────────────
# THE PARSE LAYER — GNU-first, BSD fallback, and NO third answer
# ─────────────────────────────────────────────────────────────────────────────

# delta_cadence_epoch <stamp>
#   Echo the UTC epoch seconds of `YYYY-MM-DDTHH:MM:SSZ` or of a bare
#   `YYYY-MM-DD`. rc 0 and the number on success; rc 1 AND NO OUTPUT when
#   neither parser accepts it. There is no third answer and no default — see the
#   fail-closed block in this file's header for why a `|| echo 0` tail is the
#   shape that produced the defect this function exists to avoid.
#
#   THE ORDER IS GNU-FIRST, AND IT IS SAFE IN BOTH DIRECTIONS BECAUSE EACH
#   PARSER REJECTS THE OTHER'S SPELLING. On macOS `date -d` is an ILLEGAL OPTION
#   (rc 1, usage on stderr, nothing on stdout) — it does not silently succeed
#   with some other meaning, which is the failure that would matter here: BSD's
#   `-d` sets the kernel's daylight-saving value, and a version of it that
#   accepted the argument and printed `now` would make every date on this host
#   parse as today. Verified on the host (GNU bash 3.2.57, Darwin) before this
#   order was chosen. On GNU, `date -j -f` is likewise rejected. The shipped
#   idiom in scripts/check-maintenance.sh spells the same pair BSD-first for the
#   same reason; either order works, and this one matches §11-WP5's brief.
#
#   A BARE DATE IS NORMALISED TO MIDNIGHT UTC BEFORE EITHER PARSER SEES IT, and
#   that is not tidiness. BSD's `date -j -f` fills fields the format did not
#   specify FROM THE CURRENT TIME, so `date -u -j -f '%Y-%m-%d' 2026-08-03 +%s`
#   answers "2026-08-03 at whatever o'clock it is right now" — a different
#   number every time it is called, and a different number from GNU's answer for
#   the same input. Appending `T00:00:00Z` makes the two hosts agree exactly.
#
#   The STRUCTURAL gate below is a shape check, not a validity check: it rejects
#   inputs that are not date-shaped at all (empty, `banana`, an ISO stamp with
#   an offset instead of `Z`) and passes date-SHAPED nonsense like `2026-13-45`
#   through to the real parser, which is what must reject it. A gate that tried
#   to validate month and day ranges here would be a second, worse date library.
delta_cadence_epoch() {
  local s="${1:-}" e=""
  case "$s" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
      s="${s}T00:00:00Z" ;;                                          # DELTA-CADENCE-BARE-DATE
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z)
      : ;;
    *) return 1 ;;
  esac
  e="$(date -u -d "$s" +%s 2>/dev/null)" || e=""                     # DELTA-CADENCE-EPOCH-GNU
  if [ -z "$e" ]; then
    e="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$s" +%s 2>/dev/null)" || e=""   # DELTA-CADENCE-EPOCH-BSD
  fi
  # Digits only. A leading `-` (a pre-1970 stamp) is refused rather than
  # accepted, which is the fail-closed direction for a DUE date: an obligation
  # dated before the epoch is not a current one.
  case "$e" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s\n' "$e"
  return 0
}

# delta_cadence_stamp <epoch-seconds>
#   The inverse: epoch -> `YYYY-MM-DDTHH:MM:SSZ`, the spelling §7.1's schema
#   uses. Same two-host pattern, same no-default contract.
delta_cadence_stamp() {
  local n="${1:-}" out=""
  case "$n" in ''|*[!0-9]*) return 1 ;; esac
  out="$(date -u -d "@$n" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || out=""
  if [ -z "$out" ]; then
    out="$(date -u -r "$n" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || out=""
  fi
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
  return 0
}

# delta_cadence_due_by <shipped-at> <days>
#   §7.1's `due_by = shipped_at + policy.retro_due_days`, as one call. rc 1 when
#   the stamp cannot be read or `days` is not a whole number — the caller
#   (scripts/delta.sh's hotfix lane) refuses the open rather than writing a row
#   whose deadline is a guess.
delta_cadence_due_by() {
  local at="${1:-}" days="${2:-}" e
  case "$days" in ''|*[!0-9]*) return 1 ;; esac
  e="$(delta_cadence_epoch "$at")" || return 1
  delta_cadence_stamp "$((e + days * 86400))"
}

# ─────────────────────────────────────────────────────────────────────────────
# THE LEDGER LAYER — §7.1's `hotfix_retros[]`, read as obligations
# ─────────────────────────────────────────────────────────────────────────────

# _delta_cadence_readable <state-document>
#   rc 0 iff the argument is a document this file can answer questions about: it
#   parses as JSON AND carries a `hotfix_retros` ARRAY. Anything else — an empty
#   string, a truncated file, a JSON array, a document with no ledger key — is
#   UNDETERMINED, and every public function below turns that into rc 3 rather
#   than into an answer.
#
#   THE EMPTY LEDGER IS NOT UNDETERMINED. `hotfix_retros: []` is a real, readable
#   answer meaning "nothing owed"; only an unreadable DOCUMENT is undetermined.
#   Conflating the two would make every healthy project's release refuse.
_delta_cadence_readable() {
  printf '%s\n' "${1:-}" | jq -e '(type == "object") and ((.hotfix_retros | type) == "array")' >/dev/null 2>&1
}

# _delta_cadence_open_rows <state-document>
#   `id<TAB>due_by` for every OPEN row (closed_at == null), in ledger order.
#   A row with no `due_by`, or a null one, yields an EMPTY second field on
#   purpose: empty is not date-shaped, so delta_cadence_epoch refuses it and the
#   row lands in `undetermined`. Absence and illegibility are the same answer
#   here, which is the fail-closed direction.
_delta_cadence_open_rows() {
  printf '%s\n' "${1:-}" | jq -r '
      .hotfix_retros[]?
    | select(type == "object")
    | select(.closed_at == null)
    | [ (.id // ""), (.due_by // "" | tostring) ]
    | @tsv' 2>/dev/null || true
  return 0
}

# delta_retro_rows <state-document>
#   `id<TAB>due_by<TAB>state<TAB>days` for every OPEN retro. Always rc 0 — an
#   empty ledger is not an error, it is the answer "nothing is owed".
#
#   The classification lives HERE and not in jq because jq cannot tell a date it
#   cannot parse from one it can: `strptime` errors out and takes the whole
#   program with it, so the "unreadable" branch would become "no rows at all",
#   which is the fail-OPEN answer wearing the fail-closed one's clothes.
delta_retro_rows() {
  local doc="${1:-}" now line id due e delta days state
  _delta_cadence_readable "$doc" || return 3                          # DELTA-CADENCE-LEDGER-UNDETERMINED-ROWS
  now="$(date -u +%s 2>/dev/null)" || now=""
  case "$now" in ''|*[!0-9]*) now=0 ;; esac
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    id="$(printf '%s' "$line" | cut -f1)"
    due="$(printf '%s' "$line" | cut -f2)"
    if e="$(delta_cadence_epoch "$due")"; then
      delta=$((now - e))
      if [ "$delta" -ge 0 ]; then
        state=overdue; days=$((delta / 86400))
      else
        state=current; days=$(((0 - delta) / 86400))
      fi
    else
      state=undetermined; days="-"                                   # DELTA-CADENCE-UNPARSEABLE
    fi
    printf '%s\t%s\t%s\t%s\n' "$id" "$due" "$state" "$days"
  done <<EOF
$(_delta_cadence_open_rows "$doc")
EOF
  return 0
}

# delta_retro_overdue <state-document> <delta-id>
#   0 OVERDUE (past due, or a due date nobody can read) · 1 open and not yet
#   due · 2 no OPEN retro with that id. The third code matters to WP7: "this
#   delta's retro is filed" and "this delta's retro is late" must never collapse
#   into one answer at a release cut.
#
#   The lookup consumes ALL of delta_retro_rows' output (the awk keeps the first
#   match in a variable and prints it in END rather than calling `exit`). That
#   is the SIGPIPE trap written up on scripts/lint-delta-boundary.sh's T1 scan:
#   an early-exiting downstream stage kills the upstream writer, and `pipefail`
#   promotes rc 141 into the enclosing substitution — which under `set -e` in
#   the caller is an abort, not a verdict.
delta_retro_overdue() {
  local doc="${1:-}" id="${2:-}" row state
  _delta_cadence_readable "$doc" || return 3                          # DELTA-CADENCE-LEDGER-UNDETERMINED-ONE
  [ -n "$id" ] || return 2
  row="$(delta_retro_rows "$doc" | awk -F'\t' -v want="$id" \
    '$1 == want { if (!found) { r = $0; found = 1 } } END { if (found) print r }')" || row=""
  [ -n "$row" ] || return 2
  state="$(printf '%s' "$row" | cut -f3)"
  case "$state" in
    overdue|undetermined) return 0 ;;                                # DELTA-CADENCE-OVERDUE-VERDICT
    *) return 1 ;;
  esac
}

# delta_any_open_retro <state-document>
#   §9.2's second refusal, as a predicate: 0 when ANY retro is unfiled. Note it
#   asks nothing about due dates — the release refusal fires on an OPEN retro,
#   overdue or not, because the collateral is the obligation itself.
delta_any_open_retro() {
  local doc="${1:-}" n
  _delta_cadence_readable "$doc" || return 3                          # DELTA-CADENCE-LEDGER-UNDETERMINED-ANYOPEN
  n="$(printf '%s\n' "$doc" | jq -r \
    '[.hotfix_retros[]? | select(type == "object") | select(.closed_at == null)] | length' 2>/dev/null)" || n=0
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  [ "$n" -gt 0 ]
}

# delta_any_overdue_retro <state-document>
#   0 when any OPEN retro is overdue OR undetermined. This is the narrower
#   signal — for a nag surface (§8.3's SessionStart arm, WP6) rather than for
#   the release refusal, which uses the one above.
delta_any_overdue_retro() {
  local doc="${1:-}" hit
  _delta_cadence_readable "$doc" || return 3                          # DELTA-CADENCE-LEDGER-UNDETERMINED-ANYOVERDUE
  hit="$(delta_retro_rows "$doc" | awk -F'\t' \
    '$3 == "overdue" || $3 == "undetermined" { n = n + 1 } END { if (n > 0) print "y" }')" || hit=""
  [ -n "$hit" ]
}
