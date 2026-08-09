#!/usr/bin/env bash
set -euo pipefail

# scripts/delta.sh — the post-1.0 delta track's operator front door.
#
# SPEC: docs/designs/2026-08-02-delta-track-v1.md §10.1 (THE ERA INVARIANT —
# `active_delta != null => current_phase == 4`, and this file is its LOAD-BEARING
# enforcement point), §7.1 (the state schema, the single-writer rule, and
# `gates_required` materialised AT OPEN), §4.1–§4.3 (the four classes, the
# derived-then-confirmed attributes, confirm-not-quiz), §5.2 (the per-class gate
# subset the materialisation produces), §6.1 (this is the GUIDED creation path),
# §3.1 (a member of the severable delta module), §11-WP3.
#
# (No `# BL-NNN-…` marker anywhere in the delta track on purpose — no backlog
# entry exists for this build, and minting one would red
# scripts/lint-bl-markers.sh. The design-doc path above is the citation, per the
# WP1/WP2 precedent. The grep-able `DELTA-OPEN-*` markers below are this file's
# citation primitive and its mutation addresses.)
#
# ═════════════════════════════════════════════════════════════════════════════
# WHAT THIS FILE IS FOR, IN ONE PARAGRAPH
#
# After a project ships 1.0 it never goes back through Phases 0–3. Everything
# after that is a DELTA: a feature, a fix, a hotfix, or a security patch. This
# script opens one. It asks the operator a single question, having already
# proposed every answer from what they typed and from what the repository can
# measure — and it refuses, loudly, in the two situations where opening a delta
# would quietly destroy something.
#
# ═════════════════════════════════════════════════════════════════════════════
# THE TWO REFUSALS, AND WHY EACH ONE EARNS ITS EXIT CODE
#
# 1. THE ERA INVARIANT (§10.1) — `# DELTA-OPEN-ERA-GUARD`, exit 3.
#    `--open` refuses unless `.claude/phase-state.json::current_phase` is
#    EXACTLY 4. §10.1 calls this "the load-bearing one — it is what makes the
#    delta track unable to substitute for building the product properly." A
#    project at phase 2 that could open a delta has discovered a way to do
#    post-release maintenance ceremony INSTEAD of building the product, and the
#    ceremony is cheaper, so it would win.
#
#    READ THE `[WARN]` TRAP BEFORE TOUCHING THIS (CLAUDE.md, and §10.1 repeats
#    it). In check-phase-gate.sh the `[WARN]`/`[FAIL]` text is COSMETIC — the
#    exit predicate is `if [ $issues -eq 0 ]`, so two arms that print the same
#    label can have opposite gate outcomes. The lesson generalises to here: what
#    makes this a refusal is the NON-ZERO RETURN, not the red word next to it.
#    tests/test-delta-wp3-era-classify.sh asserts the exit CODE, never the
#    label, and its m1 mutation neuters this one line to prove the code moves.
#
# 2. THE SECOND-ACTIVATION REFUSAL (§7.1) — `# DELTA-OPEN-ACTIVE-GUARD`, exit 4.
#    WP2 DEFERRED THIS TO HERE, in as many words: scripts/lib/delta-state.sh's
#    "WHAT IT DELIBERATELY DOES NOT ENFORCE" block says overwriting an OPEN
#    active_delta is accepted at the state layer, that §11-WP3 owns open/confirm
#    and therefore owns the business refusal, and that one-at-a-time is only
#    STRUCTURAL until then. This is that refusal, and it is where it belongs:
#    the schema's single `active_delta` slot means a second open would not fail —
#    it would SUCCEED and silently discard the first delta's `gates_completed`,
#    which is the audit trail of everything already done. A refusal that names
#    the open delta is the only outcome that leaves the operator informed.
#
# ═════════════════════════════════════════════════════════════════════════════
# THE SINGLE-WRITER RULE (D7), AND WHAT IT COSTS THIS FILE
#
# `.claude/delta-state.json` has exactly ONE writer: scripts/process-checklist.sh
# (§7.1). This script NEVER touches it — not to read, not to write. Every state
# operation routes through the seam's `--delta-*` actions. That is more
# indirection than a direct `jq` would need, and it is bought deliberately: the
# guard lives in the seam, and a second writer is a guard that can be forgotten.
# scripts/lint-delta-boundary.sh makes the rule checkable, with a seam allowlist
# whose cardinality is asserted at exactly one.
#
# ═════════════════════════════════════════════════════════════════════════════
# CONFIRM, DO NOT QUIZ (§4.3) — the `# BL-204-PREFILL` pattern
#
# The repo's reference implementation is `# BL-204-PREFILL` in
# scripts/intake-wizard.sh: read the remembered answer, PRINT it, print WHY
# re-asking would be wrong, and ask the operator to keep or change. This
# transcript copies it exactly, with one addition §4.3 insists on — every one of
# the four lines names WHERE ITS VALUE CAME FROM, "because a proposal whose
# provenance is hidden is a quiz with extra steps." The provenance text is not
# written here; it is returned alongside each value by
# scripts/lib/delta-classify.sh, so a caller cannot print the value and drop the
# reason.
#
# RAISES ARE FREE, LOWERS ARE REASON-RECORDED (§4.2). The operator may raise
# `risk` to core, `level` to evolution, or `severity` toward SEV-1 with no
# justification at all — they know things the formula does not. Going the other
# way removes a gate, so it records a reason into the delta's own row. A lower
# with no reason available (a scripted run with no `--reason`) is REFUSED rather
# than recorded blank: a blank reason is indistinguishable from a raise nobody
# noticed, three months later, in the audit tail.
#
# ═════════════════════════════════════════════════════════════════════════════
# OPERATOR-FACING TEXT IS PLAIN ENGLISH ON PURPOSE
# §4.3's transcript is the register for everything this script prints. No
# framework jargon, no file paths in the confirm flow, no "invariant". The
# person reading it has just shipped a product and wants to fix a bug.
#
# ═════════════════════════════════════════════════════════════════════════════
# ═════════════════════════════════════════════════════════════════════════════
# THE CLOSE FLOW (WP4) — FIVE REFUSALS, IN THIS ORDER, AND WHY THE ORDER IS THE
# DESIGN
#
# `--close` walks the delta's own record and refuses at the first thing that is
# not true. The ORDER is load-bearing, not cosmetic:
#
#   1. NOTHING OPEN                    exit 6.  Nothing to reason about.
#   2. UNKNOWN GATE TOKEN              exit 9.  A configuration error, and it
#      goes FIRST among the substantive checks because it is the only one whose
#      answer cannot be trusted otherwise: if a token is meaningless, so is
#      "outstanding" and so is "complete". It fails CLOSED and writes nothing.
#   3. CLOSE-TIME RE-DERIVATION        exit 10 (only when it appends).
#      §4.2: the open-time derivation was a FORECAST; this measures the real
#      diff. A higher bracket RAISES the attribute and APPENDS the gates that
#      raise toggles on. It never lowers. It runs BEFORE the outstanding-gates
#      check because the whole point is that the checklist may have grown —
#      running it after would let a delta opened `small` and grown into an auth
#      rewrite close on the small checklist, which is §11-WP4's own mutation.
#   4. GATES OUTSTANDING               exit 7.  gates_required minus
#      gates_completed, named.
#   5. THE RUBRIC BIND                 exit 8.  §5.3's strongest sentence: "the
#      brief's acceptance criteria ARE the close review's rubric". It runs LAST
#      because it needs the brief to exist, and `brief` is itself a gate that
#      step 4 is still able to be waiting on.
#
# REFUSAL RESIDUE — THE STANDARD THIS FILE'S OPEN FLOW SET, SCOPED TO WHAT
# EXECUTION ACTUALLY SHOWS.
#
# READ THIS AS A PROPERTY OF THE RAISE, NOT OF THE EXIT CODE. An earlier version
# of this block said "for 6/7/8/9 that sentence is true of the WHOLE TREE", and
# an adversarial review REFUTED it by execution. The refutation is worth keeping
# because the mistake is the natural one to make: the ratchet writes whenever an
# attribute ROSE, while exit 10 fires only when a gate was ALSO APPENDED, and
# those are different conditions. A raise that toggles nothing — small ->
# significant, which no toggle answers; or risk -> core on a class already
# carrying brief_review — records itself and then falls through to the exit-7 or
# exit-8 refusal. So:
#
#   6 and 9   ALWAYS leave the whole tree pristine. 6 returns before anything is
#             measured, and 9 is ordered BEFORE the ratchet precisely so that a
#             configuration error can never write. N1 pins both.
#   7 and 8   leave the tree pristine WHEN NO RAISE OCCURRED (N1), and carry
#             exactly the bounded ratchet record when one did (N3, N4).
#   10        always carries that record, by construction (N2).
#
# THE RECORD IS BOUNDED, IDEMPOTENT AND ANNOUNCED, and those three are what make
# the exception safe rather than merely admitted. Bounded: it touches the
# delta's own `attributes`, `gates_required` and `ratcheted_at`, and nothing
# else anywhere — asserted in both directions by N2/N3/N4. Idempotent: a second
# close re-measures to the same bracket and writes nothing at all, so the record
# cannot accrete one stamp per attempt. Announced: the transcript names the
# old -> new value every time, so the operator is never the last to know their
# own record moved.
#
# The alternative — announce the new obligations without recording them — was
# rejected: the operator would be told about a larger checklist the record does
# not contain, and every subsequent close would re-announce it as news. §4.2 is
# explicit that the raise is recorded.
#
# GATES ARE ATTESTED, AND THE HELP TEXT MUST NOT PRETEND OTHERWISE. §5.3 tiers
# the review honestly: the rubric is MECHANICAL, the reviewer is ADVISORY.
# `--complete-gate` records that the OPERATOR SAYS a gate is satisfied. The
# framework does not verify that the adversarial review happened, that the
# changelog entry is under the right heading, or that the repro test was RED
# first. The two things it does check itself are the two this WP makes real: the
# brief's done-observable boxes, and the close-time re-measurement of size and
# risk. Do not widen the wording beyond those two.
#
# ═════════════════════════════════════════════════════════════════════════════
# THE HOTFIX FAST LANE AND THE RETRO LEDGER (WP5) — §5.2's LOAN
#
# A hotfix ships on the floor (§5.1: gitleaks, semgrep, project tests, TDD
# ordering — all four already shipped, in the generated hook and in
# pre-commit-gate.sh) plus an audit row, and NOTHING heavier: no brief, no
# pre-build review, no Build Loop. The delta track adds NO floor arm and no
# second copy of any of them.
#
# §5.2 is careful about what that is: "The hotfix lane ships on the floor alone
# plus an audit row. It does not skip review — it DEFERS it, by exactly 3 days
# (Karl set 3, not 7), and the deferral is COLLATERALISED: cut-release.sh
# refuses while any retro is open (§9.2). That is what makes the fast lane a
# loan rather than a leak." Everything below follows from reading that as a
# loan:
#
#   THE AUDIT ROW IS WRITTEN AT OPEN — `# DELTA-OPEN-AUDIT-ROW`. The token is
#   spelled `audit_row_at_open` and it means it. The stamp goes on the delta's
#   own record in the SAME atomic write that opens it, and the gate is recorded
#   COMPLETE at that moment. It is the one gate in the system nobody attests,
#   because the framework wrote it rather than asking — which is exactly what
#   distinguishes it from `ledger_row`, the operator's own BUGS.md row, which
#   stays attested like every other class's. A hotfix that is never closed still
#   left its trace.
#
#   THE OBLIGATION IS BOOKED AT OPEN — `# DELTA-OPEN-RETRO-APPEND`. One row in
#   `hotfix_retros[]`, §7.1's five keys exactly, `due_by = shipped_at +
#   classes.hotfix.retro_due_days` read from policy. Booked at open and not at
#   close, because a hotfix that never reaches its close is precisely the one
#   whose write-up nobody would otherwise be waiting for.
#
#   AND THE LEDGER OUTLIVES THE CLOSE — `# DELTA-CLOSE-ATOMIC-WRITE`. §7.1:
#   "`hotfix_retros` is an array and outlives `active_delta` deliberately: an
#   open retro must block a release cut long after its delta closed." The close
#   filter touches `.closed` and `.active_delta` and NOTHING ELSE. If closing
#   the delta also closed the retro, the loan would be forgiven the instant it
#   was taken out — and every visible surface would still say the right thing.
#   That is the defect tests/test-delta-wp5-hotfix-retro.sh's m2 builds.
#
#   `retro_review` IS SATISFIED BY THE OBLIGATION, NOT BY A TICK-BOX —
#   `# DELTA-CLOSE-RETRO-BIND` and `# DELTA-GATE-RETRO-NOT-ATTESTABLE`. §7.2:
#   "hotfix has no `close_review` because `retro_review` carries it … a separate
#   `close_review` token on the hotfix row would either double-charge the review
#   or, worse, let a hotfix satisfy `close_review` at ship time and make the
#   retro optional — which is precisely the loan going unrepaid." So
#   `--complete-gate retro_review` is REFUSED, and the close waives the token
#   when — and only when — this delta's row is on the ledger. No row, no waiver:
#   an obligation nobody is holding is not a deferral, it is a disappearance,
#   and the close fails CLOSED (exit 7) rather than archiving a hotfix with no
#   collateral behind it.
#
# WHY THE CLOSE IS ALLOWED TO SUCCEED WITH THE RETRO STILL OPEN, spelled out
# because the opposite reading is the tempting one: a close that refused until
# the retro was filed would hold the single `active_delta` slot for three days,
# so the 3am operator who just shipped a hotfix could not open ANYTHING else
# until they had written it up. That trades the fast lane away to enforce the
# repayment, when §9.2 already enforces it at the only place that matters — the
# release. The debt is announced at close, surfaced by `--status`, and called in
# by `cut-release.sh`.
#
# THE INCIDENT-RESPONSE SEAM (§5.2) — DO NOT FUSE THE TWO CLOCKS.
# `templates/generated/incident-response.tmpl` already owns the SEV→response
# chain (Immediate / 1 h / 4 h / next window), the escalation rule, and a
# post-incident review "within 48 hours of resolution" filed at
# `docs/incidents/YYYY-MM-DD-<slug>.md`. None of it is duplicated here. The two
# clocks differ ON PURPOSE and neither is wrong: 48 h governs the INCIDENT
# write-up, `retro_due_days` governs the CODE retro. §7.2 makes both readable
# from one place so a project can align them if it wants — that alignment is the
# project's decision, not the framework's, so this flow neither reads the
# template nor teaches the template to read the policy.
#
# ═════════════════════════════════════════════════════════════════════════════
# THE RUBRIC PARSE CONTRACT (§5.3/§6.2) — WP8's template must match this
#
# The brief is `docs/deltas/DELTA-NNN-slug.md` (§6.3). This flow reads exactly
# one section of it:
#
#   • A RUBRIC SECTION is opened by ANY heading whose text begins
#     `Done-observable`, case-insensitively, at any heading depth
#     (`## Done-observable`, and a trailing parenthetical is fine). It ENDS at
#     the next heading of the same depth or shallower — so a `### Nice-to-have`
#     subsection inside it is still part of the rubric, and the next `## …` is
#     not. A brief carrying TWO such headings has BOTH read, and the criteria
#     are pooled.
#     THIS SENTENCE USED TO SAY "the FIRST heading" and the code disagreed with
#     it; an adversarial review found the mismatch by execution. The SENTENCE
#     moved, not the code, and deliberately: the implementation is the stricter
#     of the two readings, and a criterion the operator wrote under a second
#     Done-observable heading is still a criterion — a first-only reader would
#     have ignored it and closed. B5 pins both directions so it cannot drift
#     back. WP8's template codifies THIS wording.
#   • A CRITERION is a list item whose marker is `-`, `*` or `+`, at any indent,
#     followed by a bracketed single character: `- [x]` / `- [X]` is CHECKED,
#     `- [ ]` is NOT. Anything else between the brackets is treated as NOT
#     checked and named — an undefined marker is a criterion nobody has decided
#     about, and guessing in the permissive direction is how a rubric quietly
#     stops being one.
#   • ONLY that section is read. Checkboxes under What / Must-not-change /
#     Touched surfaces are ignored, which is pinned in both directions (the
#     refusal never names them; a brief whose rubric is fully checked closes
#     even though other sections carry unchecked boxes).
#   • IT FAILS CLOSED. No brief file, two files matching the id, no
#     Done-observable section, or a section containing NO checkboxes at all are
#     each a refusal. A rubric that cannot be read is not a rubric that passed —
#     and the zero-checkbox case is the one worth naming, because it is the
#     shape a brief takes when the section heading was copied from the template
#     and never filled in.
#
# ═════════════════════════════════════════════════════════════════════════════
# EXIT CODES — CODES, NEVER LABELS
#   0  the delta was opened or closed, a gate was recorded, or `--status`
#      reported successfully
#   1  an operation failed (the seam refused a write, jq is missing, …)
#   2  invocation error: bad flag, missing argument, a gate this delta does not
#      owe, or a confirmation that could not be obtained (no terminal and no
#      `--confirm`)
#   3  ERA REFUSAL — the project is not at phase 4          (§10.1)
#   4  SECOND-ACTIVATION REFUSAL — a delta is already open  (§7.1)
#   5  an attribute was LOWERED with no reason recorded     (§4.2)
#   6  there is nothing open to close or to record against  (§7.1)
#   7  required gates are still outstanding                 (§5.2)
#   8  the brief's rubric has an unchecked or unreadable criterion  (§5.3)
#   9  an unknown gate token — a configuration error, failing CLOSED (§5.2)
#  10  the close-time re-measurement RAISED an attribute and added obligations,
#      so the close refuses on the LARGER checklist          (§4.2)
#  11  `--retro` names an id no retro on the record carries  (§7.1)
#  12  that retro is already filed — the write-up is WRITE-ONCE, for the same
#      reason `shipped_in` is (§7.1): overwriting it would destroy the only
#      record of what was decided at the time
#
# There is NO era refusal on `--close`, and that is a decision. §10.1 places the
# invariant's enforcement at OPEN (load-bearing) and in scripts/validate.sh
# (report-only). An `active_delta` at phase < 4 is already the inconsistency
# validate.sh reports, and closing it is the ONLY path back to a consistent
# record — a close that refused there would strand the delta permanently in the
# state the invariant forbids. Pinned by W3.
#
# BASH 3.2: no associative arrays, no ${var,,} (hence `tr`), no `((x++))`.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/helpers-core.sh"

# This script writes into `.claude/` (through the seam) and reads the project's
# own git history. Running it from the framework clone would classify the
# FRAMEWORK's diff and open a delta on the framework's state. Refuse early —
# the same guard, for the same reason, as process-checklist.sh's.
guard_not_in_framework || exit 1

# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/delta-policy.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/delta-classify.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/delta-cadence.sh"

SEAM="$SCRIPT_DIR/process-checklist.sh"
PHASE_STATE=".claude/phase-state.json"

# ── THE ONE SPELLING OF "WHAT DOES THE LEDGER SAY ABOUT THIS DELTA?" ────────
# `none` (no row) · `open` (owed) · `filed` (written up). TWO callers need it —
# the close gate's waiver (`# DELTA-CLOSE-RETRO-BIND`) and `--retro`'s
# write-once guard (`# DELTA-RETRO-STATE-GUARD`) — and an adversarial review
# found them spelled out twice with different label vocabularies. That is the
# sync-sibling hazard the repo has scar tissue for (`# BL-084-TIER-KEY` says
# "SYNC SIBLINGS" for the same reason): an edit to one — say, tolerating
# duplicate ids — would silently diverge the close's waiver from `--retro`'s
# refusal, and nothing would fail. One definition, no siblings to keep in sync.
#
# `$id` is a jq variable supplied by each caller with `--arg`; bash does not
# re-scan the expansion of this variable, so the single quotes here are the
# whole of the quoting story.
DELTA_RETRO_ROW_STATE_JQ='
    [ .hotfix_retros[]? | select(type == "object") | select(.id == $id) ] as $r
  | if ($r | length) == 0 then "none"
    elif ($r[0].closed_at == null) then "open"
    else "filed" end'

USAGE="Usage:
  scripts/delta.sh --open [--describe TEXT] [--slug SLUG] [--confirm]
                   [--via guided|conversational|manual]
                   [--class feature|fix|hotfix|security-patch]
                   [--risk core|feature-local] [--level small|significant|evolution]
                   [--severity SEV-1|SEV-2|SEV-3|SEV-4] [--reason TEXT]
                   [--touched-file FILE]
  scripts/delta.sh --complete-gate TOKEN
  scripts/delta.sh --close
  scripts/delta.sh --retro DELTA-NNN --record FILE-OR-TEXT
  scripts/delta.sh --status
  scripts/delta.sh --help

  --complete-gate records that YOU say a check is done. Most of them are
  attested that way: the framework does not re-run your review, re-read your
  changelog entry or watch your test go red. The two it checks itself are the
  brief's done-observable boxes and the size/risk re-measurement at close.

  --close runs those two checks and refuses while anything is outstanding.

  --retro files the write-up a hotfix owes. Shipping a hotfix borrows the
  checks a normal change goes through; the write-up is how you pay that
  back, and nothing can be released until every one of them is filed.
  Point it at a file you wrote, or type the short version in quotes."

# ── The seam, and nothing but the seam ──────────────────────────────────────
# Every state read and every state write in this file goes through here. The
# `if` form suspends errexit for the call so a legitimate refusal returns as
# itself instead of aborting the script mid-transcript.
_seam() {
  if bash "$SEAM" "$@" </dev/null; then return 0; else return $?; fi
}

# _current_phase — the project's phase as a bare integer, or "" when it cannot
# be read. An unreadable phase is NOT treated as 4: the era guard below compares
# for equality, so "unknown" refuses, which is the fail-closed direction.
_current_phase() {
  local v=""
  if [ -f "$PHASE_STATE" ] && command -v jq >/dev/null 2>&1; then
    v="$(jq -r '.current_phase // empty' "$PHASE_STATE" 2>/dev/null || true)"
  fi
  case "$v" in ''|*[!0-9]*) v="" ;; esac
  printf '%s' "$v"
}

_phase_words() {
  local p="${1:-}"
  case "$p" in
    "")  printf '%s' "no recorded phase at all" ;;
    0|1) printf '%s' "phase $p — still designing" ;;
    2)   printf '%s' "phase $p — still building" ;;
    3)   printf '%s' "phase $p — still hardening for launch" ;;
    *)   printf '%s' "phase $p" ;;
  esac
}

# ── §4.3's transcript rendering ─────────────────────────────────────────────

# _tline <label> <value> <why> — one line of the confirm transcript: the label,
# the proposed value, and the parenthetical that names where the value came
# from. Long provenance wraps under the parenthesis rather than being truncated;
# a truncated reason is a hidden reason, which §4.3 is specifically about.
_tline() {
  local label="$1" value="$2" why="$3" line n=0 text
  # ASCII placeholder on purpose: `%-15s` pads by BYTES, so a multi-byte dash
  # here would silently misalign the whole column under `printf`.
  [ -n "$value" ] || value="none"
  text="($why)"
  while IFS= read -r line; do
    line="$(printf '%s' "$line" | sed -e 's/[[:space:]]*$//')"
    [ -n "$line" ] || continue
    if [ "$n" -eq 0 ]; then
      printf '  %-9s %-15s %s\n' "$label" "$value" "$line"
      n=1
    else
      printf '                            %s\n' "$line"
    fi
  done <<EOF
$(printf '%s\n' "$text" | fold -s -w 58)
EOF
  return 0
}

_render_transcript() {
  echo ""
  printf 'You said: "%s"\n' "$DESCRIBE"
  echo ""
  _tline "Class:"    "$CLASS" "$CLASS_WHY"
  _tline "Severity:" "$SEV"   "$SEV_WHY"
  _tline "Risk:"     "$RISK"  "$RISK_WHY"
  _tline "Level:"    "$LEVEL" "$LEVEL_WHY"
  echo ""
  echo "  [1] Keep all four        [2] Change the class        [3] Change an attribute"
  echo ""
  return 0
}

# ── Raise / lower (§4.2) ────────────────────────────────────────────────────
# One ordering per attribute, lowest first. `severity` runs BACKWARDS from the
# spelling — SEV-1 is the most severe, so raising severity means moving toward
# SEV-1 and the rank has to invert or every raise would read as a lower.
_rank() {
  local attr="$1" v="$2"
  case "$attr" in
    risk)  case "$v" in feature-local) printf '0' ;; core) printf '1' ;; *) printf '-1' ;; esac ;;
    level) case "$v" in small) printf '0' ;; significant) printf '1' ;; evolution) printf '2' ;; *) printf '-1' ;; esac ;;
    severity) case "$v" in SEV-4) printf '0' ;; SEV-3) printf '1' ;; SEV-2) printf '2' ;; SEV-1) printf '3' ;; *) printf '-1' ;; esac ;;
    *) printf '-1' ;;
  esac
}

_valid_values() {
  case "$1" in
    risk) printf '%s' "core or feature-local" ;;
    level) printf '%s' "small, significant or evolution" ;;
    severity) printf '%s' "SEV-1, SEV-2, SEV-3 or SEV-4" ;;
    class) printf '%s' "feature, fix, hotfix or security-patch" ;;
  esac
}

# _reason_for <attribute> — the recorded reason for lowering, or "" if none can
# be obtained. `--reason` wins; otherwise an operator at a terminal is asked.
# A scripted run with no `--reason` gets "", and the caller REFUSES.
_reason_for() {
  local attr="$1"
  if [ -n "$REASON" ]; then printf '%s' "$REASON"; return 0; fi
  if [ -t 0 ] && [ -z "${CI:-}" ] && [ -z "${SOIF_NONINTERACTIVE:-}" ]; then
    prompt_input "You are lowering $attr, which removes a check. Why is that right here?" ""
    return 0
  fi
  printf '%s' ""
  return 0
}

# _set_attr <attribute> <wanted-value> — apply an operator override.
#   RAISE  -> free, recorded as the operator's own call.
#   LOWER  -> a reason is required, recorded on the delta's row; refused (5) if
#             none can be obtained.
#   Same value -> no-op.
_set_attr() {
  local attr="$1" want="$2" cur why rc rw reason
  case "$attr" in
    risk)     cur="$RISK" ;;
    level)    cur="$LEVEL" ;;
    severity) cur="$SEV" ;;
    *) print_fail "Unknown attribute '$attr'."; return 2 ;;
  esac

  rw="$(_rank "$attr" "$want")"
  if [ "$rw" -lt 0 ]; then
    print_fail "'$want' is not one of the values $attr can take ($(_valid_values "$attr"))."
    return 2
  fi
  if [ "$attr" = "severity" ] && [ "$CLASS" = "feature" ]; then
    print_fail "A feature has no severity — severity belongs to a fix, a hotfix or a security patch."
    return 2
  fi
  [ "$want" = "$cur" ] && return 0

  rc="$(_rank "$attr" "$cur")"
  if [ "$rw" -gt "$rc" ]; then
    why="you raised this yourself — raising is always allowed, because you know things the measurement does not"
  else
    reason="$(_reason_for "$attr")"
    if [ -z "$reason" ]; then
      print_fail "Lowering $attr from $cur to $want removes a check, so it needs a reason on the record."
      print_info "Re-run with --reason \"why this is right here\", or keep $cur."
      return 5
    fi
    why="you lowered this from $cur and recorded: $reason"
    case "$attr" in
      risk)     REASON_RISK="$reason" ;;
      level)    REASON_LEVEL="$reason" ;;
      severity) REASON_SEVERITY="$reason" ;;
    esac
  fi

  case "$attr" in
    risk)     RISK="$want";  RISK_WHY="$why" ;;
    level)    LEVEL="$want"; LEVEL_WHY="$why" ;;
    severity) SEV="$want";   SEV_WHY="$why" ;;
  esac
  return 0
}

# _set_class <class> — changing the class is the ONE question §4.3 asks, so it
# is always free. Severity is re-proposed for the new class, because the old
# proposal was reasoned from the old class (and a feature carries none at all).
_set_class() {
  local want="$1" pair
  case "$want" in
    feature|fix|hotfix|security-patch) : ;;
    *) print_fail "'$want' is not one of the four classes ($(_valid_values class))."; return 2 ;;
  esac
  [ "$want" = "$CLASS" ] && return 0
  CLASS="$want"
  CLASS_WHY="you chose this class yourself"
  pair="$(delta_classify_severity "." "$CLASS" "$DESCRIBE")"
  SEV="$(printf '%s' "$pair" | cut -f1)"
  SEV_WHY="$(printf '%s' "$pair" | cut -f2-)"
  REASON_SEVERITY=""
  return 0
}

# ── The interactive confirm loop (§4.3) ─────────────────────────────────────
_confirm_loop() {
  local choice attr value rc
  while :; do
    _render_transcript
    choice="$(prompt_choice "One question — is this right?" \
      "Keep all four" "Change the class" "Change an attribute")" || return 2
    case "$choice" in
      "Keep all four") return 0 ;;
      "Change the class")
        value="$(prompt_choice "Which class is it?" feature fix hotfix security-patch)" || return 2
        _set_class "$value" || return $?
        ;;
      "Change an attribute")
        attr="$(prompt_choice "Which one?" risk level severity)" || return 2
        case "$attr" in
          risk)     value="$(prompt_choice "Risk:" core feature-local)" || return 2 ;;
          level)    value="$(prompt_choice "Level:" small significant evolution)" || return 2 ;;
          severity) value="$(prompt_choice "Severity:" SEV-1 SEV-2 SEV-3 SEV-4)" || return 2 ;;
        esac
        rc=0; _set_attr "$attr" "$value" || rc=$?
        # A refused LOWER is not fatal in the interactive flow: the operator is
        # right there and can pick again. It IS fatal in a scripted run, which
        # never reaches this loop.
        if [ "$rc" -ne 0 ] && [ "$rc" -ne 5 ]; then return "$rc"; fi
        ;;
    esac
  done
}

# ── Identity (§6.3) ─────────────────────────────────────────────────────────
_next_id() {
  printf '%s\n' "$1" | jq -r '
      [ (.closed[]?.id // empty), (.hotfix_retros[]?.id // empty), (.active_delta.id // empty) ]
    | map(select(type == "string") | select(test("DELTA-[0-9]+")))
    | map(capture("DELTA-(?<n>[0-9]+)") | .n | tonumber)
    | ((max // 0) + 1) as $n
    | "DELTA-" + (if $n < 10 then "00" elif $n < 100 then "0" else "" end) + ($n | tostring)
  ' 2>/dev/null || printf 'DELTA-001\n'
}

_slugify() {
  local s
  s="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' \
        | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-*//' -e 's/-*$//' \
        | cut -c1-40 | sed -e 's/-*$//')"
  [ -n "$s" ] && printf '%s' "$s" || printf '%s' "delta"
}

# _slug_path_safe <raw> — rc 0 when the operator's `--slug` may be sanitised,
# rc 2 when it is PATH-SHAPED and must be refused outright.
#
# WP8 IS WHERE A USER STRING BECOMES A FILESYSTEM PATH, and that is why the
# refusal lives here rather than anywhere earlier. WP3's adversarial review
# recorded `--slug ../../../etc/cron.d/evil` stored VERBATIM: harmless at the
# time, because WP3 only ever wrote it into JSON. This work package composes
# `docs/deltas/<id>-<slug>.md` out of it, so the same string is now a write
# target.
#
# WHY REFUSE AND NOT JUST SANITISE. `_slugify` would in fact flatten every one
# of these to something harmless — but silently, and the operator would find
# their delta under a name they did not choose with no idea why. Worse, a
# future edit that composed the path before slugifying (or slugified with a
# looser expression) would re-open the hole with nothing failing. A refusal is
# a fact the operator can see and a line a mutation can kill; sanitisation
# alone is a property that has to keep being true. So it is BOTH: refuse the
# path-shaped spellings loudly, sanitise everything else.
#
# The four spellings are one class and are matched as one, because a guard that
# catches `../` and misses `..\` or a leading `.` is not a guard:
#   */*      any separator, which covers `/etc/passwd` and `a/../b`
#   *\\*     a Windows separator
#   *..*     a traversal segment anywhere, even without a separator
#   .*       a leading dot: `.hidden`, `.` and `..` all land here
# An EMPTY slug is accepted — it means the operator did not pass `--slug` at
# all, and the description is slugified instead.
#
# THE FIFTH SPELLING IS NOT A SEPARATOR AT ALL (review R-WP8-3). A NEWLINE
# passes every pattern above — it is not `/`, not `\`, not `..`, not a leading
# dot — and `_slugify` PRESERVES it, because sed is line-oriented and processes
# each half independently. The composed name `docs/deltas/$id-$slug.md` then
# carries an embedded newline. No traversal and no injection is reachable
# through it (each half is still reduced to [a-z0-9-], the ledger cell strips
# `\n\r|`, and the state value goes through `jq --arg`), so this is robustness
# rather than security — but a file whose name contains a line break is a file
# the operator cannot type, and the guard is the honest place to say no.
#
# `tr -d '[:cntrl:]'` and not a pattern: it covers tab and carriage return by
# the same stroke, and it leaves accented UTF-8 bytes alone — those are not
# control characters, and `_slugify` already folds them to a hyphen, so a slug
# like "Café Export" should be SANITISED rather than refused. Note the command
# substitution strips trailing newlines from its own output, which is why a
# slug that merely ENDS in a newline also compares unequal and is refused.
_slug_path_safe() {
  local raw="${1:-}"
  [ -n "$raw" ] || return 0
  case "$raw" in
    */*|*\\*|*..*|.*) return 2 ;;
  esac
  [ "$(printf '%s' "$raw" | tr -d '[:cntrl:]')" = "$raw" ] || return 2
  return 0
}

# ── The brief (§6.2/§6.3) ───────────────────────────────────────────────────
# _brief_template — the template to render, project copy first.
#
# The PROJECT's own templates/generated/delta-brief.tmpl wins, because a
# project may edit it and the manual path (§6.1) tells the operator to copy
# THAT file. The framework-side sibling is the fallback for a scaffold that
# predates the template shipping.
_brief_template() {
  if [ -f "templates/generated/delta-brief.tmpl" ]; then
    printf '%s' "templates/generated/delta-brief.tmpl"; return 0
  fi
  if [ -f "$SCRIPT_DIR/../templates/generated/delta-brief.tmpl" ]; then
    printf '%s' "$SCRIPT_DIR/../templates/generated/delta-brief.tmpl"; return 0
  fi
  return 1
}

# _brief_render <template> <dest> <id> <slug> <class> <at> <risk> <level> <sev>
#   Substitute the {{…}} tokens and write the file. Every value spliced here is
#   already constrained — the id matches DELTA-[0-9]+, the slug has been through
#   `_slugify` so it is [a-z0-9-] only, the class and the attributes come from
#   fixed vocabularies, and the timestamp is this script's own `date -u`. None
#   of them can carry a `#`, a `&` or a newline into the sed replacement.
#
# THERE IS A BUILT-IN FALLBACK AND IT IS NOT A CONVENIENCE. A project whose
# template file is missing — deleted, or scaffolded before the template
# shipped — must still be able to open a feature delta. Refusing would make a
# missing DOCUMENT stop the WORK, and it would do it at the worst moment: the
# operator has just described what they need and confirmed four lines about it.
# The fallback carries the same five sections and the same parse contract, so
# the close gate behaves identically; only the prose guidance is thinner.
_brief_builtin() {
  local dest="$1" id="$2" slug="$3" class="$4" at="$5" risk="$6" level="$7" sev="$8"
  [ -n "$sev" ] || sev="not applicable"
  {
    printf '# %s — %s\n\n' "$id" "$slug"
    printf '**Class:** %s\n' "$class"
    printf '**Opened:** %s\n' "$at"
    printf '**Risk:** %s · **Level:** %s · **Severity:** %s\n\n' "$risk" "$level" "$sev"
    printf '## What\n\n[One paragraph, in your own words.]\n\n'
    printf '## Why\n\n[The user signal — what someone did, said, or failed to do.]\n\n'
    printf '## Done-observable\n\n'
    printf '<!-- One line per thing you will be able to SEE working. Tick a box\n'
    printf '     only when you have watched that thing happen. This list is the\n'
    printf '     whole review at close, and the close refuses while any box here\n'
    printf '     is unticked. -->\n\n'
    printf -- '- [ ] [the first thing you will be able to see working]\n'
    printf -- '- [ ] [the second thing you will be able to see working]\n\n'
    printf '## Must-not-change\n\n- [what must still work exactly as it does today]\n\n'
    printf '## Touched surfaces\n\n- [file or area]\n'
  } > "$dest"
}

_brief_render() {
  local tmpl="$1" dest="$2" id="$3" slug="$4" class="$5" at="$6" risk="$7" level="$8" sev="$9"
  [ -n "$sev" ] || sev="not applicable"
  sed -e "s#{{DELTA_ID}}#$id#g" \
      -e "s#{{SLUG}}#$slug#g" \
      -e "s#{{CLASS}}#$class#g" \
      -e "s#{{OPENED_AT}}#$at#g" \
      -e "s#{{RISK}}#$risk#g" \
      -e "s#{{LEVEL}}#$level#g" \
      -e "s#{{SEVERITY}}#$sev#g" \
      "$tmpl" > "$dest"
}

# ── The ledger row (§6.3) ───────────────────────────────────────────────────
# THE HARD CONSTRAINT, restated at the code because it is the one thing here
# that cannot be undone by an edit that looks tidy: `BUGS.md`'s table format is
# PARSED BY SCRIPTS. Its own header says "Do NOT change the table format", and
# scripts/test-gate.sh greps `SEV-1.*Open`, `SEV-2.*Open`, `SEV-2.*Deferred`
# and `SEV-3.*Open` across it. So the delta link goes in the EXISTING
# `Fix Reference` column — which already takes "PR #12"-shaped values — and
# never in a new one. A new column shifts nothing today and is exactly the
# edit that silently breaks a `grep -c` months later.

# _ledger_for <class> — which ledger this class's row belongs in (§5.2).
_ledger_for() {
  case "${1:-}" in
    feature) printf 'FEATURES.md' ;;
    *)       printf 'BUGS.md' ;;
  esac
}

# _cell <text> — a value safe to put in a markdown table cell: pipes would add
# columns, newlines would add rows.
_cell() {
  printf '%s' "${1:-}" | tr '\n\r|' '   ' | sed -e 's/[[:space:]]\{1,\}/ /g' -e 's/^ //' -e 's/ $//'
}

# _bugs_next_num <file> — max of the `#` column + 1. Only the FIRST table's rows
# carry a bare integer there, so the Status and Severity guide tables below it
# cannot contribute.
_bugs_next_num() {
  local f="$1" n
  n="$(grep -oE '^\|[[:space:]]*[0-9]+[[:space:]]*\|' "$f" 2>/dev/null \
        | grep -oE '[0-9]+' | sort -n | tail -1)"
  case "$n" in ''|*[!0-9]*) printf '1' ;; *) printf '%s' "$((n + 1))" ;; esac
}

# _bugs_append_row <file> <row> — append to the FIRST table only.
#   The insertion point is the last line of the run of `|`-rows that begins at
#   the separator, so the row lands at the bottom of the bug table and never
#   inside the Status Guide or Severity Guide tables further down the file.
_bugs_append_row() {
  local f="$1" row="$2" tmp
  tmp="$(mktemp)" || return 1
  awk -v row="$row" '
    { lines[NR] = $0 }
    sep == 0 && /^\|---/ { sep = NR; last = NR; next }
    sep > 0 && last == NR - 1 && /^\|/ { last = NR }
    END {
      if (last == 0) { for (i = 1; i <= NR; i++) print lines[i]; print row; exit }
      for (i = 1; i <= NR; i++) { print lines[i]; if (i == last) print row }
    }
  ' "$f" > "$tmp" && mv "$tmp" "$f"
}

# _features_next_num <file>
_features_next_num() {
  local f="$1" n
  n="$(grep -oE '^##[[:space:]]+Feature[[:space:]]+[0-9]+' "$f" 2>/dev/null \
        | grep -oE '[0-9]+' | sort -n | tail -1)"
  case "$n" in ''|*[!0-9]*) printf '1' ;; *) printf '%s' "$((n + 1))" ;; esac
}

# _ledger_write <class> <id> <slug> <describe> <severity> <brief-or-empty>
#   Writes the delta's row and echoes the ledger's filename, or echoes nothing
#   when there is no ledger to write into. rc is always 0: a project that has
#   deleted its ledger should not be unable to open a delta, it should be told.
#
#   THE ROW IS SEEDED, NOT ATTESTED. `ledger_row` stays an operator-attested
#   gate (WP5: "the operator's own BUGS.md row … stays attested like every
#   other class's"). The framework writes what it knows — the id, the class's
#   severity, the link — and the operator fills in the description and ticks
#   the gate. For a HOTFIX this same row is Karl's decision-3 audit trace: a
#   visible ledger row written the moment the fast lane opens, which survives
#   an abandoned hotfix and a lost state file, neither of which the state
#   document's own `audit_row_at_open` stamp does.
_ledger_write() {
  local class="$1" id="$2" slug="$3" desc="$4" sev="$5" brief="$6"
  local ledger num row link feat
  ledger="$(_ledger_for "$class")"
  [ -f "$ledger" ] || return 0
  if [ -n "$brief" ]; then link="$id ($brief)"; else link="$id"; fi
  if [ "$ledger" = "BUGS.md" ]; then
    num="$(_bugs_next_num "$ledger")"
    [ -n "$sev" ] || sev="SEV-3"
    # THE NINE SHIPPED COLUMNS, IN ORDER, AND NOT A TENTH:
    # # | Severity | Status | Feature | Description | Session | Disposition |
    # Fix Reference | Verified In
    row="| $num | $sev | Open | $(_cell "$slug") | $(_cell "$desc") | - | Fix Now | $link | - |"   # DELTA-OPEN-LEDGER-COLUMN
    _bugs_append_row "$ledger" "$row" || return 0
  else
    feat="$(_features_next_num "$ledger")"
    {
      printf '\n## Feature %s: %s\n\n' "$feat" "$(_cell "$slug")"
      printf '**Phase Built:** 4 (post-1.0 %s)\n' "$id"
      printf '**Status:** In Progress\n'
      printf '**Summary:** %s\n' "$(_cell "$desc")"
      if [ -n "$brief" ]; then printf '**Brief:** %s\n' "$brief"; fi
      printf '**Key Interfaces:** [to be filled in at close]\n'
      printf '**Related ADRs:** [to be filled in at close]\n'
      printf '**Test Coverage:** [to be filled in at close]\n'
      printf '**Known Limitations:** [to be filled in at close]\n\n---\n'
    } >> "$ledger"
  fi
  printf '%s' "$ledger"
  return 0
}

# ── The bridge (§10.4): the manifesto's § 6 read as CANDIDATES ──────────────
# D7's bridge at v1.0, and the whole of it is a READ. § 6 Post-MVP Backlog
# items become candidates listed by `--status`; nothing is auto-opened, nothing
# is deleted from the manifesto, and the § 5 MVP-cutline governance is
# untouched — because § 6's own text says these are candidates prioritised
# "after launch based on real usage data", and auto-promoting them into a queue
# would contradict the document being read.
#
# The awk program is a VARIABLE and the invocation is ONE self-contained line,
# on purpose: `# DELTA-BRIDGE-READ-ONLY` is a mutation address, and a marker on
# the last line of a multi-line quoted program would let a mutant delete the
# closing quote and produce a parse error that reads as "the guard caught it".
_MANIFESTO_S6_AWK='/^##[ \t]*6[. ]/ { insec = 1; next }
/^##.*Post-MVP Backlog/ { insec = 1; next }
insec && /^##/ { insec = 0 }
insec && /^[-*+][ \t]+/ { print }'

_manifesto_candidates() {
  local mf="PRODUCT_MANIFESTO.md"
  [ -f "$mf" ] || return 1
  awk "$_MANIFESTO_S6_AWK" "$mf" 2>/dev/null || true                  # DELTA-BRIDGE-READ-ONLY
  return 0
}

_render_candidates() {
  local cands n
  cands="$(_manifesto_candidates)" || return 0
  [ -n "$cands" ] || return 0
  n="$(printf '%s\n' "$cands" | grep -c '' || true)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  echo ""
  print_info "From your Post-MVP Backlog — $n candidate(s). Nothing here is scheduled and nothing has been opened; this is a read of PRODUCT_MANIFESTO.md section 6, which stays the place they live:"
  printf '%s\n' "$cands" | sed -e 's/^[-*+][[:space:]]*/  - /'
  return 0
}

# ═════════════════════════════════════════════════════════════════════════════
# --status
# ═════════════════════════════════════════════════════════════════════════════
# _retro_dead_end_advice <class-or-empty>
#   THE EXIT FROM THE NO-ROW STATE, NAMED (R-WP5-3). §4.3 requires a refusal to
#   "say exactly what to do next", and an adversarial review found this path
#   saying three things in a circle at 3am, in the lane built for 3am: `--close`
#   pointed at `--complete-gate`, which refused and pointed at `--retro`, which
#   refused with "nothing owes a write-up". Every command named was one that
#   refuses.
#
#   There are exactly TWO ways to be here and they have DIFFERENT exits, so both
#   are named and the class is used to say which is likely. The second is
#   reachable with NO hand edit at all — a project that adds `retro_review` to a
#   non-hotfix class's gates gets a permanently uncloseable delta, because only
#   a hotfix ever books a row for the waiver to find, and nothing in the old
#   transcript hinted that the policy was the cause.
#
#   ASCII bullets on purpose: these lines interpolate variables, and the house
#   portability rule keeps multibyte characters away from expansions under
#   `set -u` on bash 3.2.
_retro_dead_end_advice() {
  local class="${1:-}"
  print_info "A write-up is only ever booked when a HOTFIX opens, and there is no row for this one. That happens in exactly two ways:"
  print_info "  - it WAS a hotfix and the delta record lost its row. Restore the record: git checkout -- .claude/delta-state.json"
  print_info "    (there is deliberately no command that re-books it, because a command that could would also be one that restarts the clock)"
  if [ -n "$class" ] && [ "$class" != "hotfix" ]; then
    print_info "  - or your own settings ask for it where it can never happen. This is a $class, and no class but hotfix books a row, so remove \"retro_review\" from classes.$class.gates in .claude/delta-policy.json."
  else
    print_info "  - or some class other than hotfix lists \"retro_review\" in .claude/delta-policy.json. No class but hotfix books a row, so that check can never be satisfied there — remove it from that class's gates."
  fi
  return 0
}

# _render_retros — the outstanding-write-up block (§7.1/§9.2).
#
# Rendered in BOTH `--status` branches, because the ledger outlives the delta: a
# surface that only showed it when nothing was open would hide the debt exactly
# when the operator is busiest. Silent when nothing is owed — a project with no
# outstanding write-ups should not have to read a line saying so.
#
# IT READS STRICTLY, AND ON ITS OWN (R-WP5-2). Every other read in this file is
# the TOLERANT one, deliberately: a corrupt state file must not stop an operator
# closing a delta. But this block answers the release question — "what do I still
# owe" — and for that question the tolerant read's empty-schema fallback prints
# a clean bill of health over a file nobody could parse. So this one asks
# `--delta-state-read-strict` and says which of the two failures it hit. Its
# non-zero paths are the operator-facing half of the same fail-closed repair
# that gives WP7 rc 3 and rc 4.
#
# The classification is delta-cadence.sh's, not this file's, so the words the
# operator reads and the verdict `cut-release.sh` will act on can never
# disagree. Note `undetermined` renders as OVERDUE and SAYS WHY: a date nobody
# can read is not a deadline that has not arrived, and rendering it as a day
# count would invent a number the record does not contain.
_render_retros() {
  local doc rows line id due state days rc
  rc=0; doc="$(_seam --delta-state-read-strict 2>/dev/null)" || rc=$?
  if [ "$rc" -eq 3 ]; then
    echo ""
    print_fail "The delta record is there but cannot be read, so any write-ups you owe cannot be listed."
    print_info "Do not read that as a clean bill of health — releases will refuse until it is repaired."
    print_info "Restore .claude/delta-state.json from version control: git checkout -- .claude/delta-state.json"
    return 0
  fi
  [ "$rc" -eq 0 ] || return 0
  rows="$(delta_retro_rows "$doc")" || rows=""
  [ -n "$rows" ] || return 0
  echo ""
  print_info "Write-ups you still owe — nothing can be released until these are filed:"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    id="$(printf '%s' "$line" | cut -f1)"
    due="$(printf '%s' "$line" | cut -f2)"
    state="$(printf '%s' "$line" | cut -f3)"
    days="$(printf '%s' "$line" | cut -f4)"
    case "$state" in
      overdue)
        printf '  %-12s was due %s — OVERDUE by %s day(s)\n' "$id" "$due" "$days" ;;
      current)
        printf '  %-12s due %s — %s day(s) left\n' "$id" "$due" "$days" ;;
      *)
        printf '  %-12s due "%s" — that date cannot be read, so it counts as OVERDUE\n' "$id" "$due" ;;
    esac
  done <<EOF
$rows
EOF
  print_info "File one with: scripts/delta.sh --retro <id> --record \"what happened, and what stops it happening again\""
  return 0
}

cmd_status() {
  local doc phase
  phase="$(_current_phase)"
  if ! doc="$(_seam --delta-state-read)"; then
    print_fail "Could not read the delta record."
    return 1
  fi
  echo ""
  print_info "Project phase: ${phase:-unknown}"
  if [ "$(printf '%s\n' "$doc" | jq -r '.active_delta == null')" = "true" ]; then
    print_info "No delta is open. Start one with: scripts/delta.sh --open"
    _render_retros
    _render_candidates
    echo ""
    return 0
  fi
  printf '%s\n' "$doc" | jq -r '
    .active_delta as $d
    | "  Open delta:  \($d.id)  (\($d.class))",
      "  What:        \($d.slug)",
      "  Opened:      \($d.opened_at // "unknown")  via \($d.opened_via // "unknown")",
      "  Risk:        \($d.attributes.risk // "unknown")",
      "  Level:       \($d.attributes.level // "unknown")",
      "  Severity:    \($d.attributes.severity // "—")",
      "  Still to do: " + (( ($d.gates_required // []) - ($d.gates_completed // []) ) | join(", ")),
      "  Done:        " + ((($d.gates_completed // []) | join(", ")) | if . == "" then "nothing yet" else . end)
  '
  _render_retros
  echo ""
  return 0
}

# ═════════════════════════════════════════════════════════════════════════════
# --open
# ═════════════════════════════════════════════════════════════════════════════
cmd_open() {
  local phase doc active_id pair touched lines gates obj now id slug reasons rc
  local retro_days retro_due retro_row audit_at gates_done filter
  local brief_rel brief_created brief_json ledger_json ledger_file tmpl existing

  command -v jq >/dev/null 2>&1 || { print_fail "jq is required to open a delta."; return 1; }

  # ── REFUSAL 1 — THE ERA INVARIANT (§10.1) ────────────────────────────────
  # `active_delta != null => current_phase == 4`, enforced where it is
  # load-bearing: at open. Equality, not `-ge`: §10.2 fixes current_phase at 4
  # forever (a phase 5 was rejected by decision), so anything else is a project
  # that has not shipped yet.
  phase="$(_current_phase)"
  if [ "$phase" != "4" ]; then                                        # DELTA-OPEN-ERA-GUARD
    echo ""
    print_fail "This project is not finished yet, so there is nothing to maintain."
    print_info "The delta track is for after your product has shipped. This project is at $(_phase_words "$phase")."
    print_info "Finish the build and the launch first — then every later change comes through here."
    echo ""
    return 3
  fi

  if ! doc="$(_seam --delta-state-read)"; then
    print_fail "Could not read the delta record."
    return 1
  fi

  # ── REFUSAL 2 — SECOND ACTIVATION (§7.1, deferred to WP3 by WP2) ─────────
  # One delta at a time. The schema's single `active_delta` slot makes a second
  # open SUCCEED and overwrite — taking the first delta's completed-gate history
  # with it — so the refusal has to live here, in the business layer, and it has
  # to name the delta that is in the way.
  active_id="$(printf '%s\n' "$doc" | jq -r '.active_delta.id // "NONE"' 2>/dev/null || printf 'NONE')"
  if [ "$active_id" != "NONE" ]; then                                 # DELTA-OPEN-ACTIVE-GUARD
    echo ""
    print_fail "You already have one piece of work open: $active_id."
    print_info "$(printf '%s\n' "$doc" | jq -r '"It is a \(.active_delta.class // "delta") — \(.active_delta.slug // "no description recorded")."')"
    print_info "Finish it or close it before starting another. Run: scripts/delta.sh --status"
    echo ""
    return 4
  fi

  # ── REFUSAL 3 — THE SLUG IS A WRITE TARGET (§6.3, WP8) ───────────────────
  # It sits HERE — after the two refusals that describe the project's state,
  # before anything at all is written — because it is an invocation error, not
  # a state error: the operator typed something this flow cannot turn into a
  # file name. Ordering it after the era guard keeps the load-bearing refusal
  # first; ordering it before every write is what makes "nothing was opened"
  # true of the whole tree.
  if ! _slug_path_safe "$SLUG"; then                                  # DELTA-OPEN-SLUG-GUARD
    echo ""
    print_fail "That short name cannot be used: it looks like a file path, not a name."
    print_info "The short name becomes part of a file name, so it can only contain letters, numbers and hyphens — no slashes, no dots at the start, and no \"..\"."
    print_info "Try something like: --slug csv-export-unicode"
    print_info "Nothing was opened."
    echo ""
    return 2
  fi

  # The recorded path is the one the operator asked for and the one they will
  # be shown, so it is validated here too. Neither is a substitute for the
  # other: `--via` is a vocabulary check, the slug guard above is a path check.
  case "$VIA" in
    guided|conversational|manual) : ;;
    *)
      print_fail "'$VIA' is not one of the three ways a piece of work gets started."
      print_info "Use --via guided (you ran this script), --via conversational (an agent walked you through it) or --via manual (you wrote the plan by hand first)."
      print_info "Nothing was opened."
      return 2 ;;
  esac

  if [ -z "$DESCRIBE" ]; then
    if [ -t 0 ] && [ -z "${CI:-}" ] && [ -z "${SOIF_NONINTERACTIVE:-}" ]; then
      DESCRIBE="$(prompt_input "In your own words — what needs doing?" "")"
    fi
  fi
  if [ -z "$DESCRIBE" ]; then
    print_fail "Tell me what needs doing: scripts/delta.sh --open --describe \"the CSV export crashes on unicode\""
    return 2
  fi

  # ── §4.2's three derivations, each returning value + provenance ──────────
  pair="$(delta_classify_class "$DESCRIBE")"
  CLASS="$(printf '%s' "$pair" | cut -f1)"
  CLASS_WHY="$(printf '%s' "$pair" | cut -f2-)"

  pair="$(delta_classify_severity "." "$CLASS" "$DESCRIBE")"
  SEV="$(printf '%s' "$pair" | cut -f1)"
  SEV_WHY="$(printf '%s' "$pair" | cut -f2-)"

  touched="$TOUCHED_FILE"
  if [ -z "$touched" ]; then
    touched="$(mktemp)"
    delta_classify_touched "." > "$touched" 2>/dev/null || : > "$touched"
    TOUCHED_TMP="$touched"
  fi
  pair="$(delta_classify_risk "." "$touched")"
  RISK="$(printf '%s' "$pair" | cut -f1)"
  RISK_WHY="$(printf '%s' "$pair" | cut -f2-)"

  lines="$LINES_OVERRIDE"
  [ -n "$lines" ] || lines="$(delta_classify_lines ".")"
  pair="$(delta_classify_level "." "$lines")"
  LEVEL="$(printf '%s' "$pair" | cut -f1)"
  LEVEL_WHY="$(printf '%s' "$pair" | cut -f2-)"

  # ── Command-line overrides, applied BEFORE the transcript is shown, so the
  #    operator confirms what will actually be recorded. Class first: it
  #    re-proposes severity, and an explicit --severity must survive that.
  if [ -n "$WANT_CLASS" ]; then _set_class "$WANT_CLASS" || return $?; fi
  if [ -n "$WANT_RISK" ];  then _set_attr risk "$WANT_RISK" || return $?; fi
  if [ -n "$WANT_LEVEL" ]; then _set_attr level "$WANT_LEVEL" || return $?; fi
  if [ -n "$WANT_SEV" ];   then _set_attr severity "$WANT_SEV" || return $?; fi

  # ── §4.3: confirm, do not quiz ──────────────────────────────────────────
  if [ "$CONFIRMED" -eq 1 ]; then
    _render_transcript
  elif [ -t 0 ] && [ -z "${CI:-}" ] && [ -z "${SOIF_NONINTERACTIVE:-}" ]; then
    rc=0; _confirm_loop || rc=$?
    [ "$rc" -eq 0 ] || return "$rc"
  else
    _render_transcript
    print_fail "Nobody is here to confirm this, so nothing was opened."
    print_info "Re-run in a terminal, or add --confirm to accept the four lines above as they stand."
    return 2
  fi

  # The policy file is project-owned from birth, and this is §7.2's "the first
  # delta.sh --open" seeding moment. It goes through the seam like every other
  # write, even though it is birth-once and never overwrites.
  #
  # IT SITS AFTER THE CONFIRMATION, DELIBERATELY. Every refusal above says
  # "nothing was opened", and a refusal that says that while leaving a new file
  # behind is a refusal the operator cannot trust. Seeding earlier costs nothing
  # in derivation accuracy — an absent policy file already resolves every key to
  # the framework default at read time (§3.2), so the transcript the operator
  # just confirmed was computed from exactly the values this seed writes. Pinned
  # by T2: after the no-confirmation refusal the project contains exactly the one
  # file it started with.
  _seam --delta-policy-init >/dev/null 2>&1 || true

  # ── §7.1: gates_required MATERIALISED AT OPEN from class + attributes ────
  if ! gates="$(delta_classify_gates "." "$CLASS" "$RISK" "$LEVEL")"; then
    print_fail "Could not work out which checks this delta needs, so nothing was opened."
    return 1
  fi

  id="$(_next_id "$doc")"
  # BOTH sources go through `_slugify`, and the operator's is no exception.
  # The guard above already refused the path-shaped spellings; this is the
  # second half of the same defence — whatever survives is reduced to
  # [a-z0-9-], so the composed file name cannot be anything else.
  if [ -n "$SLUG" ]; then slug="$(_slugify "$SLUG")"; else slug="$(_slugify "$DESCRIBE")"; fi
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  reasons="$(jq -c -n --arg r "$REASON_RISK" --arg l "$REASON_LEVEL" --arg s "$REASON_SEVERITY" '
    { risk: (if $r == "" then null else $r end),
      level: (if $l == "" then null else $l end),
      severity: (if $s == "" then null else $s end) }')"

  # ── §5.2's HOTFIX FAST LANE (WP5) ────────────────────────────────────────
  # Two things happen at OPEN for a hotfix and for no other class: the audit
  # row is stamped, and the retro obligation is booked. Both ride the same
  # atomic write as the delta itself, so there is no window in which a hotfix
  # exists without its trace or without its debt.
  retro_row=""
  audit_at="null"
  gates_done="[]"
  if [ "$CLASS" = "hotfix" ]; then
    # §7.2, read per key with fallback: the window is the PROJECT's number, not
    # a literal. Neuter this read and a project that retuned it silently keeps
    # the framework's deadline — no error, no warning, just a date nobody chose.
    retro_days="$(delta_policy_get "." "classes.$CLASS.retro_due_days")" || retro_days=3   # DELTA-OPEN-RETRO-DUE-DAYS
    case "$retro_days" in
      ''|*[!0-9]*)
        print_info "Your project's retro window is not a whole number of days, so this is using the standard 3."
        retro_days=3 ;;
    esac
    if ! retro_due="$(delta_cadence_due_by "$now" "$retro_days")"; then
      print_fail "Could not work out when the write-up would be due, so nothing was opened."
      return 1
    fi
    # THE AUDIT ROW, AT OPEN. Written by the framework, so the gate is complete
    # the moment the delta exists — the one gate nobody attests. `ledger_row`,
    # the operator's own BUGS.md row, is untouched by this and stays attested
    # like every other class's.
    audit_at="$(_json_str "$now")"                                    # DELTA-OPEN-AUDIT-ROW
    gates_done='["audit_row_at_open"]'
    # §7.1's row, five keys, in the schema's order.
    if ! retro_row="$(jq -c -n --arg id "$id" --arg at "$now" --arg due "$retro_due" '
        { id: $id, shipped_at: $at, due_by: $due, closed_at: null, record: null }')"; then
      print_fail "Could not write down the write-up you would owe, so nothing was opened."
      return 1
    fi
  fi

  # ── §6.1's OTHER TWO WRITES (WP8) ────────────────────────────────────────
  # All three creation paths converge on the same three writes — the brief
  # file, the ledger row and the state activation — and this is where the first
  # two happen. The third has exactly one writer (the seam) and it is the call
  # below.
  #
  # THE ORDER IS THE DESIGN. The brief and the ledger row are written FIRST and
  # rolled back if the state write is refused, so the refusal's "nothing was
  # opened" stays true of the whole tree. The reverse order would be worse in
  # the way that matters: a state document pointing at a brief that does not
  # exist closes on `_brief_path`'s "there isn't one to check against", which
  # reads like the operator's fault.
  brief_rel=""
  brief_created=""
  brief_json="null"
  ledger_json="null"

  # THE BRIEF IS WRITTEN ONLY WHEN THE CLASS OWES ONE (§5.2). A hotfix ships on
  # the floor plus an audit row and nothing heavier; rendering it a brief would
  # be exactly the ceremony the fast lane exists to skip.
  if printf '%s\n' "$gates" | jq -e 'index("brief") != null' >/dev/null 2>&1; then
    rc=0; existing="$(_brief_path "$id" "")" || rc=$?
    if [ "$rc" -eq 2 ]; then
      echo ""
      print_fail "More than one written-up plan already claims to be $id's, so it is not clear which one this work would be reviewed against."
      printf '%s\n' "$existing" | sed -e 's/^/  /'
      print_info "Keep one and rename or remove the other. Nothing was opened."
      echo ""
      return 2
    fi
    if [ "$rc" -eq 0 ] && [ -n "$existing" ] && [ -f "$existing" ]; then
      # THE MANUAL PATH (§6.1). The operator wrote their own plan before
      # running anything; it is ADOPTED, never overwritten. A template render
      # on top of it would destroy the very thing they came here with.
      brief_rel="$existing"
      print_info "Using the plan you already wrote at $existing."
    else
      brief_rel="docs/deltas/$id-$slug.md"
      mkdir -p "docs/deltas" 2>/dev/null || true
      rc=0
      if tmpl="$(_brief_template)"; then
        _brief_render "$tmpl" "$brief_rel" "$id" "$slug" "$CLASS" "$now" \
          "$RISK" "$LEVEL" "$SEV" || rc=$?
      else
        _brief_builtin "$brief_rel" "$id" "$slug" "$CLASS" "$now" \
          "$RISK" "$LEVEL" "$SEV" || rc=$?
        print_info "There is no brief template in this project, so a plain one was written for you. If you want the fuller version back, restore templates/generated/delta-brief.tmpl."
      fi
      if [ "$rc" -ne 0 ]; then
        rm -f "$brief_rel" 2>/dev/null || true
        print_fail "Could not write the plan file, so nothing was opened."
        return 1
      fi
      brief_created="$brief_rel"
    fi
    brief_json="$(_json_str "$brief_rel")"
  fi

  ledger_file="$(_ledger_write "$CLASS" "$id" "$slug" "$DESCRIBE" "$SEV" "$brief_rel")"   # DELTA-OPEN-LEDGER-ROW
  if [ -n "$ledger_file" ]; then
    ledger_json="$(_json_str "$ledger_file")"
  else
    print_info "There is no ledger file here to add a row to, so this delta is recorded only in its own record."
  fi

  obj="$(jq -c -n \
    --arg id "$id" --arg slug "$slug" --arg class "$CLASS" \
    --arg at "$now" --arg via "$VIA" \
    --argjson brief "$brief_json" --argjson ledger "$ledger_json" \
    --arg risk "$RISK" --arg level "$LEVEL" --arg sev "$SEV" \
    --argjson gates "$gates" --argjson reasons "$reasons" \
    --argjson audit "$audit_at" --argjson done "$gates_done" '
    { id: $id, slug: $slug, class: $class,
      brief: $brief, ledger: $ledger,
      opened_at: $at, opened_via: $via,
      attributes: { risk: $risk, level: $level,
                    severity: (if $sev == "" then null else $sev end) },
      attributes_confirmed_at: $at,
      attribute_reasons: $reasons,
      audit_row_at_open: $audit,
      gates_required: $gates,
      gates_completed: $done }')"

  # THE ONLY WRITE IN THIS FILE, AND IT IS NOT A WRITE — it is a request to the
  # single writer (§7.1/D7). delta.sh never opens the state file.
  #
  # ONE filter, therefore ONE atomic rename: the delta and its obligation land
  # together or not at all. Splitting them would leave a crash window in which a
  # hotfix had shipped and owed nothing.
  filter=".active_delta = $obj"
  if [ -n "$retro_row" ]; then
    filter="$filter | .hotfix_retros += [$retro_row]"                 # DELTA-OPEN-RETRO-APPEND
  fi
  if ! _seam --delta-state-update "$filter"; then
    # THE ROLLBACK. Only a brief THIS run created is removed — an adopted one
    # is the operator's own file and was here before we were. Spelled as an
    # `if` and not `[ -n … ] && rm`: this arm only runs when the seam has
    # already refused, so it is the least-exercised path in the flow, and an
    # AND-list whose left side is false is exactly the shape that trips `set -e`
    # readings nobody has tested.
    if [ -n "$brief_created" ]; then rm -f "$brief_created" 2>/dev/null || true; fi
    print_fail "The delta record refused the change, so nothing was opened."
    return 1
  fi

  echo ""
  print_ok "Opened $id — $slug ($CLASS)."
  if [ -n "$brief_rel" ]; then
    print_info "Write down what has to be TRUE when this is finished, in $brief_rel under 'Done-observable'. That list is the whole review at the end — you are writing it now, before you are invested in how you built it."
  fi
  if [ -n "$ledger_file" ]; then
    print_info "A row for $id is on $ledger_file. Fill in what it says before you mark that check done."
  fi
  printf '%s\n' "$gates" | jq -r '"  Before this can ship: " + join(", ")'
  if [ -n "$retro_row" ]; then
    # §4.3's plain register, and it is read at 3am: say what was borrowed, when
    # it is owed back, and the exact command that repays it.
    print_info "This is the fast lane: it ships on the standard safety checks and nothing heavier."
    print_info "That borrows the checking a normal change goes through, so you owe a write-up of what happened by $retro_due — $retro_days day(s) from now."
    print_info "It is already on the record. Nothing can be released until you file it:"
    print_info "  scripts/delta.sh --retro $id --record \"what happened, and what stops it happening again\""
  fi
  print_info "Check where you are at any time with: scripts/delta.sh --status"
  echo ""
  return 0
}

# ═════════════════════════════════════════════════════════════════════════════
# CLOSE-FLOW HELPERS (§4.2 / §5.3)
# ═════════════════════════════════════════════════════════════════════════════

# _json_str <value> — the value as a JSON string literal, quoting and escaping
# included. Every value this file splices into a jq filter goes through here.
# Some of them originate in `.claude/delta-state.json`, which a human can edit,
# so "it came from our own record" is not the same as "it is safe to paste into
# a program". One helper is cheaper than one audit per splice site.
_json_str() { jq -c -n --arg v "${1:-}" '$v'; }

# _higher <attribute> <a> <b> — whichever of the two ranks HIGHER on that
# attribute's ordering, `a` on a tie or when neither ranks. THE RATCHET, as one
# expression (§4.2: "it never lowers"). An unrecognised value ranks -1, so a
# measurement that could not be taken can only ever lose — which is the
# fail-safe direction here and is what makes the m1 mutant's `measured=""` a
# clean, total neuter rather than a crash.
_higher() {
  local attr="$1" a="$2" b="$3" ra rb
  ra="$(_rank "$attr" "$a")"
  rb="$(_rank "$attr" "$b")"
  if [ "$rb" -gt "$ra" ]; then printf '%s' "$b"; else printf '%s' "$a"; fi
}

# _close_measure <root> <touched-file-list> <changed-lines>
#   `<risk><TAB><level>` measured from the REAL diff at close, using the SAME
#   formulas the open flow used on its forecast (§4.2 is explicit that
#   delta-classify.sh "computes the same way at both moments; it does not know
#   which moment it is in"). The ratchet is applied to these outputs, not here.
_close_measure() {
  local root="${1:-.}" files="${2:-}" lines="${3:-0}" r l
  r="$(delta_classify_risk "$root" "$files" | cut -f1)"
  l="$(delta_classify_level "$root" "$lines" | cut -f1)"
  printf '%s\t%s' "$r" "$l"
}

# _brief_path <delta-id> <recorded-path>
#   Echo the brief's path. rc 0 = found; 1 = none; 2 = AMBIGUOUS (two files
#   claim the same id — the paths are echoed so the operator can see both).
#
#   The recorded path wins when there is one: §11-WP8 owns the guided intake
#   that writes `active_delta.brief`, and a delta that names its own brief is
#   not to be second-guessed by a glob. Until WP8 lands, that field is null and
#   the glob over §6.3's `docs/deltas/DELTA-NNN-slug.md` is the whole answer.
#   Ambiguity is a refusal rather than a first-match: picking one of two briefs
#   silently means the close review ran against a document the operator may not
#   have been looking at.
#   WP8 AMENDMENT — THE AMBIGUITY CHECK NOW RUNS FIRST, AND UNCONDITIONALLY.
#   The recorded path still wins, but it no longer SKIPS the glob. Once WP8's
#   guided intake started filling `active_delta.brief`, an early return on the
#   recorded value made the two-files-claim-one-id refusal unreachable through
#   the front door: the close would review the framework's own render while the
#   operator had been editing the other file all week, and if that other file
#   happened to be complete, nothing anywhere would say so. Order matters here
#   and it is the only thing that changed — a delta that names its own brief is
#   still not second-guessed about WHICH file to read, it is only refused when
#   there is genuinely more than one candidate to be confused by.
_brief_path() {
  local id="$1" recorded="${2:-}" hits="" n
  if [ -d "docs/deltas" ]; then
    hits="$(find docs/deltas -maxdepth 1 -type f \( -name "$id-*.md" -o -name "$id.md" \) 2>/dev/null | LC_ALL=C sort)"
    if [ -n "$hits" ]; then
      n="$(printf '%s\n' "$hits" | grep -c '' || true)"
      case "$n" in ''|*[!0-9]*) n=0 ;; esac
      if [ "$n" -gt 1 ]; then
        printf '%s' "$hits"
        return 2
      fi
    fi
  fi
  if [ -n "$recorded" ] && [ "$recorded" != "null" ]; then
    printf '%s' "$recorded"
    return 0
  fi
  [ -n "$hits" ] || return 1
  printf '%s' "$hits"
  return 0
}

# _rubric_boxes <brief-file>
#   One `checked<TAB>text` or `unchecked<TAB>text` line per criterion in the
#   brief's Done-observable section, in document order. Empty output means the
#   section is absent OR carries no checkboxes — the caller treats both as a
#   refusal, so this function does not need to tell them apart.
#
#   THE CONTRACT IS SPELLED OUT IN THIS FILE'S HEADER and WP8's
#   `delta-brief.tmpl` must match it. The two decisions worth restating at the
#   code: the section ends at the next heading of the same depth or SHALLOWER
#   (so a `###` sub-list is still rubric), and a bracket holding anything other
#   than `x`/`X` counts as NOT checked. A permissive reading of an undefined
#   marker is how a rubric quietly stops being one.
_rubric_boxes() {
  local f="$1"
  [ -f "$f" ] || return 1
  awk '
    function hashes(s,   n) { n = 0; while (substr(s, n + 1, 1) == "#") n++; return n }
    {
      line = $0
      sub(/^[ \t]+/, "", line)
      if (line ~ /^#+[ \t]/) {
        d = hashes(line)
        rest = substr(line, d + 1)
        sub(/^[ \t]+/, "", rest)
        if (tolower(rest) ~ /^done-observable/) { insec = 1; depth = d; next }
        if (insec == 1 && d <= depth) { insec = 0 }
        next
      }
      if (insec != 1) next
      if (line ~ /^[-*+][ \t]+\[.\]/) {
        mark = substr(line, index(line, "[") + 1, 1)
        text = substr(line, index(line, "]") + 1)
        sub(/^[ \t]+/, "", text)
        sub(/[ \t]+$/, "", text)
        if (mark == "x" || mark == "X") printf "checked\t%s\n", text
        else printf "unchecked\t%s\n", text
      }
    }
  ' "$f" 2>/dev/null
  return 0
}

# ═════════════════════════════════════════════════════════════════════════════
# --complete-gate
# ═════════════════════════════════════════════════════════════════════════════
cmd_complete_gate() {
  local doc id token gates_req present already gate_state gate_class

  token="$GATE_TOKEN"
  command -v jq >/dev/null 2>&1 || { print_fail "jq is required to record a check."; return 1; }
  if [ -z "$token" ]; then
    print_fail "Name the check you finished: scripts/delta.sh --complete-gate ledger_row"
    return 2
  fi

  if ! doc="$(_seam --delta-state-read)"; then
    print_fail "Could not read the delta record."
    return 1
  fi
  if [ "$(printf '%s\n' "$doc" | jq -r '.active_delta == null')" = "true" ]; then
    echo ""
    print_fail "There is nothing open, so there is no check to record against."
    print_info "Start a piece of work with: scripts/delta.sh --open"
    echo ""
    return 6
  fi

  id="$(printf '%s\n' "$doc" | jq -r '.active_delta.id // "unknown"')"
  gates_req="$(printf '%s\n' "$doc" | jq -c '.active_delta.gates_required // []')"

  # A token this delta does not owe is an INVOCATION error, not a config one:
  # the vocabulary may well know the word, this delta simply is not carrying it.
  present=n
  if printf '%s\n' "$gates_req" | jq -r '.[]? | select(type == "string")' | grep -qxF "$token"; then
    present=y
  fi
  if [ "$present" = n ]; then
    echo ""
    print_fail "$id does not need '$token'."
    printf '%s\n' "$gates_req" | jq -r '"  What it does need: " + join(", ")'
    echo ""
    return 2
  fi

  # `retro_review` IS NOT ATTESTABLE (§7.2). It is the hotfix's close review,
  # arriving late, and §7.2 names the exact failure a tick-box here would be:
  # letting a hotfix "satisfy close_review at ship time and make the retro
  # optional — which is precisely the loan going unrepaid". The only thing that
  # repays it is the write-up, so the refusal points at the command that files
  # one rather than explaining a policy.
  if [ "$token" = "retro_review" ]; then                              # DELTA-GATE-RETRO-NOT-ATTESTABLE
    echo ""
    print_fail "The write-up is not something you can tick off — it is something you write."
    print_info "Shipping fast borrowed the checking a normal change goes through, and the write-up is how you pay it back. Ticking a box here would be the borrowing with none of the paying."
    # DO NOT POINT AT A COMMAND THAT WILL ALSO REFUSE (R-WP5-3). `--retro` is
    # the right answer only when there IS a row for it to file; when there is
    # not, that advice completes a circle instead of ending one.
    gate_state="$(printf '%s\n' "$doc" | jq -r --arg id "$id" "$DELTA_RETRO_ROW_STATE_JQ" 2>/dev/null)" || gate_state="none"
    if [ "$gate_state" = "none" ]; then
      gate_class="$(printf '%s\n' "$doc" | jq -r '.active_delta.class // ""' 2>/dev/null)" || gate_class=""
      _retro_dead_end_advice "$gate_class"
    else
      print_info "File it with: scripts/delta.sh --retro $id --record \"what happened, and what stops it happening again\""
      print_info "You can close $id before then — the write-up stays owed, and nothing can be released until it is filed."
    fi
    echo ""
    return 2
  fi

  # Idempotent by design. Re-recording is the most likely repeat invocation
  # there is, and making it an error would teach the operator to fear the tool.
  already=n
  if printf '%s\n' "$doc" | jq -r '.active_delta.gates_completed[]? | select(type == "string")' | grep -qxF "$token"; then
    already=y
  fi
  if [ "$already" = y ]; then
    print_ok "$token was already recorded for $id — nothing to do."
    return 0
  fi

  if ! _seam --delta-state-update ".active_delta.gates_completed += [$(_json_str "$token")]"; then
    print_fail "The delta record refused the change, so nothing was recorded."
    return 1
  fi

  echo ""
  print_ok "Recorded: $token is done for $id."
  # §5.3's honest tiering, in the operator's own words. Do not widen this.
  print_info "This is your word for it — the record now says you did it, and nothing here re-checks it."
  print_info "The two things this tool does check for itself are the tick-boxes in your brief and how big the change actually turned out to be, both when you close."
  print_info "See where you are with: scripts/delta.sh --status"
  echo ""
  return 0
}

# ═════════════════════════════════════════════════════════════════════════════
# --close
# ═════════════════════════════════════════════════════════════════════════════
cmd_close() {
  local doc id class sev risk level recorded gates_req gates_done
  local vocab unknown g outstanding
  local touched lines measured mrisk mlevel nrisk nlevel
  local newgates appended n_appended now row filter
  local brief brc boxes unchecked
  local audit retro_state retro_q waived retro_due

  command -v jq >/dev/null 2>&1 || { print_fail "jq is required to close a delta."; return 1; }

  if ! doc="$(_seam --delta-state-read)"; then
    print_fail "Could not read the delta record."
    return 1
  fi

  # ── REFUSAL 1 — NOTHING IS OPEN ──────────────────────────────────────────
  if [ "$(printf '%s\n' "$doc" | jq -r '.active_delta == null')" = "true" ]; then
    echo ""
    print_fail "There is nothing open to close."
    print_info "Start a piece of work with: scripts/delta.sh --open"
    echo ""
    return 6
  fi

  id="$(printf '%s\n' "$doc" | jq -r '.active_delta.id // "unknown"')"
  class="$(printf '%s\n' "$doc" | jq -r '.active_delta.class // ""')"
  sev="$(printf '%s\n' "$doc" | jq -r '.active_delta.attributes.severity // ""')"
  risk="$(printf '%s\n' "$doc" | jq -r '.active_delta.attributes.risk // ""')"
  level="$(printf '%s\n' "$doc" | jq -r '.active_delta.attributes.level // ""')"
  recorded="$(printf '%s\n' "$doc" | jq -r '.active_delta.brief // ""')"
  gates_req="$(printf '%s\n' "$doc" | jq -c '.active_delta.gates_required // []')"
  gates_done="$(printf '%s\n' "$doc" | jq -c '.active_delta.gates_completed // []')"

  # ── REFUSAL 2 — AN UNKNOWN GATE TOKEN, FAILING CLOSED ────────────────────
  # FIRST among the substantive checks, deliberately: if a token is meaningless
  # then "outstanding" and "complete" are both meaningless too, so every answer
  # downstream of it is untrustworthy. It also means this refusal is reached
  # before the ratchet, which is what keeps its residue at zero.
  vocab="$(delta_classify_gate_vocabulary ".")"
  unknown=""
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    if printf '%s\n' "$vocab" | grep -qxF "$g"; then continue; fi
    unknown="$unknown $g"
  done <<EOF
$(printf '%s\n' "$gates_req" | jq -r '.[]? | select(type == "string")')
EOF
  if [ -n "$unknown" ]; then                                          # DELTA-CLOSE-VOCAB-GUARD
    echo ""
    print_fail "This piece of work lists a check nothing here recognises:$unknown."
    print_info "That is not something you can finish — nothing in the project knows what would satisfy it, so it would block you forever."
    print_info "It is almost always a typo. Fix the spelling in .claude/delta-policy.json and re-open, or correct the delta's own record. Nothing was closed."
    echo ""
    return 9
  fi

  # ── THE CLOSE-TIME RE-DERIVATION AND ITS RATCHET (§4.2) ──────────────────
  # The open-time values were a FORECAST measured against an empty diff. This is
  # the measurement. A higher bracket raises the attribute and appends whatever
  # gates that raise toggles on; a lower one changes nothing at all.
  touched="$TOUCHED_FILE"
  if [ -z "$touched" ]; then
    touched="$(mktemp)"
    TOUCHED_TMP="$touched"
    delta_classify_touched "." > "$touched" 2>/dev/null || : > "$touched"
  fi
  lines="$LINES_OVERRIDE"
  [ -n "$lines" ] || lines="$(delta_classify_lines ".")"

  measured="$(_close_measure "." "$touched" "$lines")"                # DELTA-CLOSE-RATCHET
  mrisk="$(printf '%s' "$measured" | cut -f1)"
  mlevel="$(printf '%s' "$measured" | cut -f2)"
  nrisk="$(_higher risk "$risk" "$mrisk")"
  nlevel="$(_higher level "$level" "$mlevel")"

  if [ "$nrisk" != "$risk" ] || [ "$nlevel" != "$level" ]; then
    if ! newgates="$(delta_classify_gates "." "$class" "$nrisk" "$nlevel")"; then
      print_fail "Could not work out what the bigger change needs, so nothing was closed."
      return 1
    fi
    # APPEND-ONLY, never recompute-and-replace (§7.1): a policy edit mid-delta
    # must not be able to drop a gate the operator was already told about, so
    # the recomputed set contributes only what is NEW.
    if ! appended="$(jq -c -n --argjson have "$gates_req" --argjson want "$newgates" \
        '[ $want[] | . as $g | select(($have | index($g)) == null) ]')"; then
      print_fail "Could not work out what the bigger change needs, so nothing was closed."
      return 1
    fi
    n_appended="$(printf '%s' "$appended" | jq -r 'length' 2>/dev/null)" || n_appended=0
    case "$n_appended" in ''|*[!0-9]*) n_appended=0 ;; esac
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if ! _seam --delta-state-update \
        ".active_delta.attributes.risk = $(_json_str "$nrisk") \
       | .active_delta.attributes.level = $(_json_str "$nlevel") \
       | .active_delta.gates_required = (.active_delta.gates_required + $appended) \
       | .active_delta.ratcheted_at = $(_json_str "$now")"; then
      print_fail "The delta record refused the re-measurement, so nothing was closed."
      return 1
    fi

    # ANNOUNCE THE RAISE — ALWAYS, INCLUDING WHEN NO GATE WAS TOGGLED.
    # This sits ABOVE the `n_appended` branch on purpose. The write above
    # happens whenever an attribute rose; the rc-10 refusal below happens only
    # when a gate was ALSO appended. Those two conditions are not the same, and
    # an adversarial review found the gap by execution: a raise that toggles
    # nothing (small -> significant, which no toggle answers; or risk -> core on
    # a class that already carries brief_review) rewrote the operator's recorded
    # attributes and then returned 7 or 8 without a word about it. The record
    # changing under someone who was never told is the half of that defect that
    # is not about doctrine, and this is the whole fix for it. Pinned by N3/N4.
    echo ""
    print_info "Re-measured from what you actually changed:"
    if [ "$nrisk" != "$risk" ];   then print_info "  how risky:  $risk -> $nrisk"; fi
    if [ "$nlevel" != "$level" ]; then print_info "  how big:    $level -> $nlevel"; fi
    print_info "That is on the record now. It only ever goes up — a smaller change later never talks it back down."

    gates_req="$(printf '%s\n' "$gates_req" | jq -c ". + $appended")"
    risk="$nrisk"
    level="$nlevel"

    if [ "$n_appended" -gt 0 ]; then
      echo ""
      print_fail "This turned out to be a bigger change than it looked when you started, so it needs more checking before it can close."
      printf '%s\n' "$appended" | jq -r '"  Now also needed: " + join(", ")'
      print_info "That is measured from what you actually changed, not from what you said at the start — and it only ever goes up."
      print_info "Do those, mark them done with --complete-gate, then close again."
      echo ""
      return 10
    fi
  fi

  # ── THE RETRO BIND (§7.2), COMPUTED BEFORE THE OUTSTANDING SET ───────────
  # `retro_review` is not a gate the operator finishes; it is a gate the LEDGER
  # answers. §7.2: "retro_review IS that close review, arriving late and
  # collateralised by the §9.2 release refusal." So the token is WAIVED at close
  # exactly when this delta's obligation is on the record — filed or still owed,
  # both are the deferral working — and it is NOT waived when no row exists.
  #
  # THE NO-ROW CASE IS THE LOAD-BEARING ONE AND IT FAILS CLOSED. A hotfix whose
  # ledger row has been erased has nothing collateralising it: closing it would
  # archive a delta that skipped the review and owes nobody anything, which is
  # the leak §5.2 says the fast lane must not be. That falls through to REFUSAL
  # 3 below and refuses (7) naming retro_review, rather than being waived by the
  # class. Neuter this line and that distinction is gone — m6.
  #
  # THE LOOKUP LIVES IN A VARIABLE so the VERDICT below is a SINGLE, SELF-
  # CONTAINED LINE. That is not cosmetic: a marker sitting on the tail of a
  # multi-line command substitution cannot be neutered by a one-line
  # counterfactual — replacing it leaves the opening lines dangling and the
  # mutant dies of a syntax error instead of exhibiting the defect, which reads
  # as "the mutation was caught" while proving nothing at all.
  retro_state="none"
  waived="[]"
  if printf '%s\n' "$gates_req" | jq -e 'index("retro_review") != null' >/dev/null 2>&1; then
    retro_state="$(printf '%s\n' "$doc" | jq -r --arg id "$id" "$DELTA_RETRO_ROW_STATE_JQ" 2>/dev/null)" || retro_state="none"   # DELTA-CLOSE-RETRO-BIND
    case "$retro_state" in
      open|filed) waived='["retro_review"]' ;;
      *) waived="[]" ;;
    esac
  fi

  # ── REFUSAL 3 — REQUIRED GATES STILL OUTSTANDING (§5.2) ──────────────────
  # `waived` is held SEPARATELY from `gates_completed` rather than folded into
  # it, and that is the honest spelling: the archived checklist must not claim
  # the operator did a write-up they have not written. The obligation's record
  # is the ledger row, and it stays open.
  if ! outstanding="$(jq -r -n --argjson req "$gates_req" --argjson done "$gates_done" \
      --argjson waived "$waived" \
      '[ $req[] | . as $g | select((($done + $waived) | index($g)) == null) ] | join(", ")')"; then
    print_fail "Could not work out what is left to do, so nothing was closed."
    return 1
  fi
  if [ -n "$outstanding" ]; then                                      # DELTA-CLOSE-GATES-GUARD
    echo ""
    print_fail "$id is not finished yet."
    print_info "Still to do: $outstanding"
    # The no-row branch gets its own exit named, because "--complete-gate <name>"
    # is a refusal for this particular token and pointing at it was a circle.
    case "$retro_state,$outstanding" in
      none,*retro_review*)
        _retro_dead_end_advice "$class"
        print_info "Anything else on that list is marked done with: scripts/delta.sh --complete-gate <name>"
        ;;
      *)
        print_info "Mark one done with: scripts/delta.sh --complete-gate <name>" ;;
    esac
    echo ""
    return 7
  fi

  # ── REFUSAL 4 — THE RUBRIC BIND (§5.3) ───────────────────────────────────
  # Keyed on the GATE, not on the class: a fix that grew past the evolution
  # threshold gains `brief` at the ratchet above and gains this check with it.
  if printf '%s\n' "$gates_req" | jq -e 'index("brief") != null' >/dev/null 2>&1; then
    brc=0
    brief="$(_brief_path "$id" "$recorded")" || brc=$?
    if [ "$brc" -eq 2 ]; then
      echo ""
      print_fail "More than one write-up claims to be $id's, so it is not clear which one to check against."
      printf '%s\n' "$brief" | sed -e 's/^/  /'
      print_info "Keep one and rename or remove the other. Nothing was closed."
      echo ""
      return 8
    fi
    if [ "$brc" -ne 0 ] || [ -z "$brief" ] || [ ! -f "$brief" ]; then
      echo ""
      print_fail "$id needs a written-up plan and there isn't one to check against."
      print_info "It should be at docs/deltas/$id-<short-name>.md, with a '## Done-observable' section listing what has to be true when this is finished."
      print_info "Nothing was closed."
      echo ""
      return 8
    fi
    boxes="$(_rubric_boxes "$brief")" || boxes=""
    if [ -z "$boxes" ]; then
      echo ""
      print_fail "$brief has no list of things that have to be true when this is done, so there is nothing to check it against."
      print_info "Add a '## Done-observable' section with one '- [ ] …' line per thing you will be able to see working."
      print_info "An empty list would let this close on nothing at all, so it is refused rather than passed. Nothing was closed."
      echo ""
      return 8
    fi
    unchecked="$(printf '%s\n' "$boxes" | awk -F'\t' '$1 == "unchecked" { print "  - " $2 }')"
    if [ -n "$unchecked" ]; then                                      # DELTA-CLOSE-RUBRIC-GUARD
      echo ""
      print_fail "You wrote down what would be true when $id is done, and some of it is not ticked off yet."
      printf '%s\n' "$unchecked"
      print_info "That list is in $brief, and it is the whole review — you wrote it before you were invested in how you built this."
      print_info "Finish those, tick them, then close. Nothing was closed."
      echo ""
      return 8
    fi
  fi

  # ── THE CLOSE WRITE — ONE SEAM CALL, ONE ATOMIC RENAME ───────────────────
  # "ONE" IS A CLAIM ABOUT THIS WRITE, NOT ABOUT THE INVOCATION. A close that
  # was preceded by a silent raise performs TWO seam writes: the ratchet record
  # above, then this one. That is fine and is not what the property is about —
  # the load-bearing guarantee is that the `closed` APPEND and the slot NULL are
  # a single filter and therefore a single atomic rename, so no crash can land
  # between them. m3 kills the split; W1/W2 pin the result.
  # THE `closed` APPEND AND THE SLOT NULL ARE ONE FILTER, and that is not
  # tidiness. `_next_id` reads ids out of closed[] + hotfix_retros[] +
  # active_delta, so a close that empties the slot without appending ERASES the
  # id from the record and the very next open is handed it again — two pieces of
  # work sharing one identifier in the audit tail, with nothing anywhere that
  # would notice. Splitting this into two seam calls would additionally make the
  # window between them a crash away from exactly that state.
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  audit="$(printf '%s\n' "$doc" | jq -r '.active_delta.audit_row_at_open // ""')"
  if ! row="$(jq -c -n --arg id "$id" --arg class "$class" --arg sev "$sev" \
      --arg at "$now" --arg risk "$risk" --arg level "$level" --argjson done "$gates_done" \
      --arg audit "$audit" '
      ($sev | if . == "" then null else . end) as $s
      | { id: $id, class: $class, severity: $s,
          closed_at: $at, shipped_in: null,
          audit_row_at_open: ($audit | if . == "" then null else . end),
          attributes: { risk: $risk, level: $level, severity: $s },
          gates_completed: $done }')"; then
    print_fail "Could not write up the finished record, so nothing was closed."
    return 1
  fi

  # THE FILTER TOUCHES `.closed` AND `.active_delta`, AND NOTHING ELSE — most
  # pointedly not `.hotfix_retros`. §7.1: "hotfix_retros is an array and outlives
  # active_delta deliberately: an open retro must block a release cut long after
  # its delta closed." A hotfix ships fast by BORROWING rigor and the retro is
  # the repayment; a close that also closed the retro would forgive the loan the
  # instant it was taken out, and every visible surface would still say the
  # right thing — the delta closes, the audit tail grows, --status is clean, and
  # nothing anywhere is ever going to ask for the write-up again. That is the
  # mutation tests/test-delta-wp5-hotfix-retro.sh's m2 builds against this line.
  filter=".closed += [$row] | .active_delta = null"                   # DELTA-CLOSE-ATOMIC-WRITE
  if ! _seam --delta-state-update "$filter"; then
    print_fail "The delta record refused the change, so nothing was closed."
    return 1
  fi

  echo ""
  print_ok "Closed $id ($class)."
  print_info "It is on the record with everything you ticked off, and it will be listed in the next release you cut."
  if [ "$retro_state" = "open" ]; then
    # ANNOUNCED, NOT MERELY RECORDED. The operator has just been allowed to
    # close something while still owing the write-up; being told so here is the
    # difference between a deferral and a thing they find out about at the next
    # release cut.
    retro_due="$(delta_retro_rows "$doc" | awk -F'\t' -v want="$id" \
      '$1 == want { if (!f) { d = $2; f = 1 } } END { if (f) print d }')" || retro_due=""
    echo ""
    # Spelled as two branches rather than one `${retro_due:+…}` expansion: the
    # house portability rule forbids a multibyte character adjacent to a
    # variable expansion under `set -u` on bash 3.2, and the dash in the
    # alternate word would sit exactly there.
    if [ -n "$retro_due" ]; then
      printf '%s\n' "  You still owe the write-up for $id, due $retro_due."
    else
      printf '%s\n' "  You still owe the write-up for $id."
    fi
    print_info "Closing this did not clear it, and nothing can be released until it is filed:"
    print_info "  scripts/delta.sh --retro $id --record \"what happened, and what stops it happening again\""
  fi
  print_info "Start the next one with: scripts/delta.sh --open"
  echo ""
  return 0
}

# ═════════════════════════════════════════════════════════════════════════════
# --retro — filing the write-up a hotfix owes (§5.2's repayment)
# ═════════════════════════════════════════════════════════════════════════════
#
# THE RECORD'S CONTRACT, STATED RATHER THAN IMPLIED. `record` is an object with
# a `kind` and a `value`, and the kind is the honest part:
#
#   {"kind":"file","value":"docs/incidents/2026-08-03-checkout.md"}
#       the value named a file THAT EXISTS when this ran. The framework has not
#       read it and does not claim to — §5.3's tiering applies here exactly as
#       it does to every other gate — but it did check that there is something
#       at that path.
#   {"kind":"attested","value":"the gateway timed out; we retry twice now"}
#       anything else, including a path that did not resolve. A path stored as
#       `attested` is SAID to be, out loud, at the moment it is filed: a typo'd
#       filename recorded as though a document existed would be the framework
#       inventing evidence.
#
# WRITE-ONCE, for the same reason `shipped_in` is (§7.1): a second write-up
# claiming the same incident is a bug worth stopping, and overwriting the first
# would destroy the only record of what was decided at the time.
#
# THE RETRO IS FOUND ON THE LEDGER, NOT ON `active_delta` — it outlives its
# delta, so filing it must work long after the delta closed, and while a
# completely different delta is open.
cmd_retro() {
  local doc id state now kind record_json filter known_class rc

  id="$RETRO_ID"
  command -v jq >/dev/null 2>&1 || { print_fail "jq is required to file a write-up."; return 1; }
  if [ -z "$id" ]; then
    print_fail "Name the piece of work you are writing up: scripts/delta.sh --retro DELTA-003 --record \"…\""
    return 2
  fi
  if [ -z "$RECORD" ]; then
    echo ""
    print_fail "A write-up needs something in it."
    print_info "Either point at the file you wrote — --record docs/incidents/2026-08-03-checkout.md — or type the short version in quotes after --record."
    print_info "Nothing was filed."
    echo ""
    return 2
  fi

  if ! doc="$(_seam --delta-state-read)"; then
    print_fail "Could not read the delta record."
    return 1
  fi

  # ONE read of the ledger answers both refusals, and it is the mutation address
  # for the write-once property: force it to "OPEN" and a second filing reports
  # success while the jq filter below quietly declines to touch the already-
  # filed row — the operator is told their write-up is on the record and it is
  # not. That is m4.
  #
  # The query is `$DELTA_RETRO_ROW_STATE_JQ`, defined once at the top of this
  # file and shared with the close gate's waiver — see the comment there for why
  # a second spelling is the hazard. Keeping it in a variable also makes this
  # verdict a SINGLE, SELF-CONTAINED LINE: a marker on the tail of a multi-line
  # substitution cannot be neutered by a one-line counterfactual without leaving
  # a dangling continuation, and a mutant that dies of a syntax error proves
  # nothing.
  state="$(printf '%s\n' "$doc" | jq -r --arg id "$id" "$DELTA_RETRO_ROW_STATE_JQ" 2>/dev/null)" || state="none"   # DELTA-RETRO-STATE-GUARD

  case "$state" in
    open) : ;;
    filed)
      echo ""
      print_fail "The write-up for $id is already filed."
      printf '%s\n' "$doc" | jq -r --arg id "$id" '
        [ .hotfix_retros[]? | select(.id == $id) ][0] as $r
        | "  Filed \($r.closed_at // "at an unrecorded time"): \($r.record.value // "no detail recorded")"'
      print_info "It is kept as it was written. If there is more to say, add it to that write-up rather than replacing what you decided at the time. Nothing was changed."
      echo ""
      return 12 ;;
    none)
      echo ""
      print_fail "Nothing on the record owes a write-up under the name $id."
      # The class, when the record knows it, turns the generic advice into the
      # specific one — see _retro_dead_end_advice.
      known_class="$(printf '%s\n' "$doc" | jq -r --arg id "$id" '
        [ (.active_delta // empty), (.closed[]? // empty) ]
        | map(select(type == "object") | select(.id == $id) | .class)
        | (.[0] // "")' 2>/dev/null)" || known_class=""
      _retro_dead_end_advice "$known_class"
      print_info "See what is outstanding with: scripts/delta.sh --status. Nothing was filed."
      echo ""
      return 11 ;;
    *)
      print_fail "Could not read the list of write-ups you owe. Nothing was filed."
      return 1 ;;
  esac

  kind="attested"
  if [ -f "$RECORD" ]; then kind="file"; fi
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if ! record_json="$(jq -c -n --arg k "$kind" --arg v "$RECORD" '{ kind: $k, value: $v }')"; then
    print_fail "Could not write down what you filed, so nothing was recorded."
    return 1
  fi

  # ONE seam call, therefore ONE atomic rename. The array is rebuilt rather than
  # indexed so the write cannot depend on a position the document might not
  # have; every other row passes through untouched.
  filter=".hotfix_retros = [ .hotfix_retros[]
            | if (.id == $(_json_str "$id")) and (.closed_at == null)
              then (.closed_at = $(_json_str "$now") | .record = $record_json)
              else . end ]"                                           # DELTA-RETRO-CLOSE-WRITE
  if ! _seam --delta-state-update "$filter"; then
    print_fail "The delta record refused the change, so nothing was filed."
    return 1
  fi

  echo ""
  print_ok "Filed the write-up for $id."
  if [ "$kind" = "file" ]; then
    print_info "The record points at $RECORD."
  else
    print_info "Recorded as your own summary — there is no file at \"$RECORD\", so the words you typed are what is on the record."
  fi
  # rc 3 (the ledger cannot be read) must NOT print "releases are clear" — that
  # is the fail-open sentence in its most reassuring possible costume. Capture
  # the code rather than branching on truthiness.
  rc=0; doc="$(_seam --delta-state-read-strict 2>/dev/null)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    _render_retros
  elif delta_any_open_retro "$doc"; then
    _render_retros
  else
    print_info "Nothing else is outstanding — releases are clear."
  fi
  echo ""
  return 0
}

# ═════════════════════════════════════════════════════════════════════════════
# Argument parsing
# ═════════════════════════════════════════════════════════════════════════════
ACTION=""
DESCRIBE=""
SLUG=""
# §6.1's three creation paths. They differ ONLY in who authored the brief; all
# three end in this script performing the same three writes, which is what
# keeps the state single-writer rule intact no matter how the operator got
# here. `guided` is the default because that is what running this script IS.
VIA="guided"
CONFIRMED=0
WANT_CLASS=""
WANT_RISK=""
WANT_LEVEL=""
WANT_SEV=""
REASON=""
TOUCHED_FILE=""
TOUCHED_TMP=""
LINES_OVERRIDE=""
GATE_TOKEN=""
RETRO_ID=""
RECORD=""

CLASS=""; CLASS_WHY=""
SEV="";   SEV_WHY=""
RISK="";  RISK_WHY=""
LEVEL=""; LEVEL_WHY=""
REASON_RISK=""; REASON_LEVEL=""; REASON_SEVERITY=""

_need() {
  if [ "$2" -lt 2 ]; then
    echo "delta: $1 needs a value." >&2
    echo "$USAGE" >&2
    exit 2
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --open)     ACTION="open"; shift ;;
    --close)    ACTION="close"; shift ;;
    --complete-gate) _need "$1" $#; ACTION="complete-gate"; GATE_TOKEN="$2"; shift 2 ;;
    --retro)    _need "$1" $#; ACTION="retro"; RETRO_ID="$2"; shift 2 ;;
    # `--record` deliberately accepts an EMPTY value rather than rejecting it in
    # the parser: `--record ""` and a missing `--record` are the same mistake
    # from the operator's side, and cmd_retro answers both with one sentence
    # about what a write-up needs. A parser-level refusal here would give the
    # two spellings different messages for no reason.
    --record)   _need "$1" $#; RECORD="$2"; shift 2 ;;
    --status)   ACTION="status"; shift ;;
    --describe) _need "$1" $#; DESCRIBE="$2"; shift 2 ;;
    --slug)     _need "$1" $#; SLUG="$2"; shift 2 ;;
    --via)      _need "$1" $#; VIA="$2"; shift 2 ;;
    --class)    _need "$1" $#; WANT_CLASS="$2"; shift 2 ;;
    --risk)     _need "$1" $#; WANT_RISK="$2"; shift 2 ;;
    --level)    _need "$1" $#; WANT_LEVEL="$2"; shift 2 ;;
    --severity) _need "$1" $#; WANT_SEV="$2"; shift 2 ;;
    --reason)   _need "$1" $#; REASON="$2"; shift 2 ;;
    # An explicit touched-file list and an explicit line count exist so the
    # derivations can be exercised against a KNOWN input. At open the real diff
    # is usually empty (§4.2's forecast), so a test that relied on the ambient
    # git state would be pinning the host, not the formula. BOTH FLOWS honour
    # them — `--close` re-measures with the same two functions, so the same
    # override is the same override there. The WP4 ratchet cases deliberately do
    # NOT use them: the design's own mutation is about a REAL diff crossing a
    # bracket, and feeding that measurement by hand would prove the arithmetic
    # while assuming away the thing being measured.
    --touched-file) _need "$1" $#; TOUCHED_FILE="$2"; shift 2 ;;
    --lines)        _need "$1" $#; LINES_OVERRIDE="$2"; shift 2 ;;
    --confirm)  CONFIRMED=1; shift ;;
    -h|--help)  echo "$USAGE"; exit 0 ;;
    *) echo "delta: unknown option '$1'." >&2; echo "$USAGE" >&2; exit 2 ;;
  esac
done

_cleanup() { [ -n "$TOUCHED_TMP" ] && rm -f "$TOUCHED_TMP" 2>/dev/null; return 0; }
trap _cleanup EXIT

RC=0
case "$ACTION" in
  open)          cmd_open          || RC=$? ;;
  close)         cmd_close         || RC=$? ;;
  complete-gate) cmd_complete_gate || RC=$? ;;
  retro)         cmd_retro         || RC=$? ;;
  status)        cmd_status        || RC=$? ;;
  *)             echo "$USAGE" >&2; RC=2 ;;
esac
exit "$RC"
