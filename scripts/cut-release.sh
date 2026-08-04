#!/usr/bin/env bash
set -euo pipefail

# scripts/cut-release.sh — the post-1.0 release cut.
#
# SPEC: docs/designs/2026-08-02-delta-track-v1.md §9.1 (semver, decided by the
# TOOL — the class->bump map is retunable, the PRECEDENCE is machinery, and
# there is NO override in v1), §9.2 (THE THREE REFUSALS AND THEIR ORDER, and
# "performs no write of any kind before all three pass"), §9.3 (promotion, and
# the tag format C7 forces), §8.2 (a major bump re-runs run-phase3-validation.sh
# in full BEFORE the tag is written), §8.3 (overdue and unmeasurable are both
# refusals), §7.1 (`shipped_in` recorded at cut time THROUGH THE SEAM, never by
# touching the file), §3.1 (this file is a DELTA-MODULE file despite its
# core-sounding name), §0.3-C7, §0.3-C8, §11-WP7.
#
# (No `# BL-NNN-…` marker anywhere in the delta track on purpose — no backlog
# entry exists for this build, and minting one would red
# scripts/lint-bl-markers.sh, whose first pass resolves every marker to a real
# `## BL-NNN:` entry. The design-doc path above is the citation, per the WP1-WP6
# precedent. The grep-able CUTREL-* markers below are this file's citation
# primitive and its mutation addresses.)
#
# ═════════════════════════════════════════════════════════════════════════════
# THE ONE PROPERTY THIS FILE IS ORGANISED AROUND
#
# NO WRITE OF ANY KIND HAPPENS BEFORE ALL THREE REFUSALS PASS (§9.2's last
# line). Not the changelog, not the state record, not the tag, not a scanner
# summary. The reason is stated in the design rather than assumed: "a
# partially-cut release (changelog promoted, tag absent) is a worse state than
# a refused one" — a refusal is a situation you can read and fix, while a
# half-cut release is a repository whose changelog claims a version that no tag
# names and no pipeline ever built.
#
# The whole script is therefore two phases with a hard line between them, and
# the line is marked. PHASE A reads and refuses; it opens no file for writing
# and runs no tool that writes. PHASE B writes, in an order chosen so that the
# most recoverable write happens first. tests/test-delta-wp7-cut-release.sh
# asserts Phase A's emptiness with a whole-tree `find` + per-file md5 manifest
# taken across every refusal path, singly and in combination, PLUS a separate
# count of the repository's tags — because `git tag` writes into `.git/`, which
# a working-tree manifest cannot see.
#
# ═════════════════════════════════════════════════════════════════════════════
# THE THREE REFUSALS, IN §9.2's ORDER, AND WHY THE ORDER IS THAT ONE
#
# The order is author-proposed in the design and chosen so the cheapest and
# clearest refusal speaks first. An operator who has a delta open does not need
# to sit through a maintenance-cadence scan to be told so.
#
#   1. AN OPEN DELTA (`active_delta != null`). Instant, no I/O beyond the state
#      read every refusal needs anyway. "Finish or abandon DELTA-NNN first."
#   2. AN UNFILED HOTFIX RETRO. This is D3's collateral being called in: the
#      hotfix lane ships fast by BORROWING the checks a normal change goes
#      through, `hotfix_retros[]` is the loan, and this refusal is the only
#      thing that ever collects. §7.1 makes the array outlive `active_delta`
#      deliberately for this one moment.
#   3. AN OVERDUE OR UNMEASURABLE CADENCE. The expensive one — it shells out to
#      scripts/check-maintenance.sh, which walks git history and the evidence
#      directory.
#
# TWO CONSUMED CONTRACTS. Neither is re-derived here, and both were written for
# this file by the WPs that shipped them; read their headers before changing a
# line below.
#
#   • scripts/lib/delta-cadence.sh — WP5's retro predicates, and the calling
#     shape at the top of that file. THE STRICT READ IS MANDATORY: the tolerant
#     `--delta-state-read` answers a corrupt file with the EMPTY SCHEMA at rc 0
#     and an ABSENT file in complete silence, so with a retro owed, corrupting
#     the record — or `rm`-ing it — would make "is anything owed?" answer "no"
#     and refusal 2 would never fire. `rm` as loan forgiveness in one keystroke.
#     `--delta-state-read-strict` answers rc 0 + document, rc 3 unreadable, rc 4
#     absent, with nothing on stdout in either failure. THIS FILE REFUSES ON
#     BOTH 3 AND 4. On 4: a project that has never opened a delta has nothing to
#     release either (§9.1 refuses "nothing closed since the last tag"), so
#     refusing costs a real project nothing and closes the erasure path.
#   • scripts/check-maintenance.sh — WP6's exit contract: 0 measured-current,
#     1 overdue, 2 unmeasurable. THIS FILE REFUSES ON BOTH 1 AND 2 (§8.3:
#     "overdue and unmeasurable are both refusals"). Its report NAMES every arm
#     it could not measure even inside an rc-1 answer, so the report is
#     surfaced verbatim rather than replaced by a headline of our own.
#
# THE FAIL-CLOSED DIRECTION IS THE SAME EVERYWHERE. Refusal 2 refuses on
# anything that is not a definite "none owed" — an UNDETERMINED ledger refuses
# too. Refusal 3 refuses on any non-zero the checker can produce, not on a
# whitelist of two. An unmapped class refuses rather than defaulting to patch.
# Every one of those is the same judgement: under-refusing ships a release over
# an obligation nobody could see, and over-refusing costs an operator one
# command and a clear message.
#
# ═════════════════════════════════════════════════════════════════════════════
# THE TAG IS CONSTRAINED, NOT CHOSEN (§9.3 + C7) — DO NOT "IMPROVE" IT
#
# C7 measured the shipped release lanes. GitHub's four templates and
# Bitbucket's four match `v*`. GitLab's four match `/^v\d+\.\d+\.\d+$/` —
# three numeric components, no pre-release suffix, no two-component tag. So a
# `v1.2.0-rc1` would build on two hosts and SILENTLY DO NOTHING on the third:
# green on the host you tested, nothing at all on the one you did not. That is
# the worst available failure mode, and it is why this emits exactly
# `vMAJOR.MINOR.PATCH` and then checks its own output against the regex before
# using it. Pre-release tags are §13-R3's business, not v1's.
#
# ═════════════════════════════════════════════════════════════════════════════
# SEMVER: THE MAP IS POLICY, THE PRECEDENCE IS MACHINERY (§9.1)
#
# Each closed row not yet shipped contributes ONE token: `breaking` if the row
# carries a breaking marker, otherwise its class. `delta-policy.json::semver`
# maps tokens to bumps and a project may retune it — a `0.x` project can make
# every fix a minor. What a project may NOT do is reorder how the bumps
# COMBINE: major beats minor beats patch, always, because a project that could
# reorder that could make a feature release a patch (§9.1 says so in as many
# words). There is no policy key for it and no flag for it; the rank function
# below is the whole of it.
#
# NO OVERRIDE, AND THE COST IS REAL. An operator who disagrees with the
# computed bump has no flag in v1. §13-R2 records what that costs: a project
# that wants a marketing-driven major has to change the class of what it
# shipped or tag by hand outside this tool. That is the decision; do not soften
# it with a `--version` flag, and do not add one "just for CI".
#
# WHAT "SINCE THE LAST TAG" MEANS OPERATIONALLY. A closed row whose
# `shipped_in` is null has not been carried by any release — that IS the
# question, and it is a stronger reading than a date comparison against the
# last tag, because it survives clock skew, a re-tagged history and a tag
# created by hand. The two coincide in every ordinary case. `shipped_in` is
# write-once at the seam, so a row can never be double-counted.
#
# ═════════════════════════════════════════════════════════════════════════════
# TWO ADJACENCIES, RECORDED RATHER THAN WIRED
#
#   • `check-phase-gate.sh --finalize-phase 4` (§0.3-C8) is the natural pre-tag
#     check and is invoked by NOTHING today — a second orphan sitting beside
#     the cadence checker this file now calls. Karl did not decide to wire it
#     (design Q3 asks), so it is named here and nowhere else. No executed line
#     in this file references it, and the test suite asserts that.
#   • THE TAG NAMES HEAD, AND HEAD DOES NOT YET CONTAIN THE PROMOTION. This
#     tool deliberately does not COMMIT. Committing would run the project's own
#     pre-commit gate, which can refuse for reasons that have nothing to do
#     with the release and would leave exactly the half-cut state above; and
#     `--no-verify` is never an option in this framework. So the cut ends by
#     telling the operator, in order, to commit what it wrote and to move the
#     (unpushed, therefore free to move) tag onto that commit before pushing.
#
# ═════════════════════════════════════════════════════════════════════════════
# EXIT CODES ARE THE ANSWER; THE LABELS ARE DECORATION
#
#   0   the release was cut
#   2   invocation / environment error
#   3   REFUSAL 1 — a delta is open
#   4   REFUSAL 2 — an unfiled hotfix retro (or a ledger nobody can read)
#   5   REFUSAL 3 — cadence overdue or unmeasurable
#   6   REFUSAL — the delta record exists and cannot be read (strict rc 3)
#   7   REFUSAL — there is no delta record at all (strict rc 4)
#   8   REFUSAL — nothing closed since the last tag (§9.1)
#   9   REFUSAL — a closed row's class maps to no bump (fail-closed)
#  10   REFUSAL — major bump, and the §8.2 revalidation did not pass
#  11   a write FAILED after every refusal passed — the cut is incomplete, and
#       the message says exactly how far it got
#
# CLAUDE.md's `[WARN]` trap is that a printed label and an exit predicate can
# disagree — in check-phase-gate.sh two arms printing the same word have
# opposite gate outcomes. Every assertion in the WP7 suite is on one of these
# codes, on a file's bytes, on a whole-tree manifest, or on `git tag --list`.
#
# DEPENDENCY DIRECTION (D1). This file is a DELTA-MODULE file (§3.1) even
# though its name sounds core: it reads `delta-state.json`, and classifying it
# as core would create a second core -> delta edge. delta -> core is allowed and
# unasserted, which is why it may call check-maintenance.sh and
# run-phase3-validation.sh directly. It sources the module's OWN policy and
# cadence libs directly (delta -> delta, the scripts/delta.sh precedent) and
# reaches `delta-state.json` ONLY through the seam.
#
# BASH 3.2: no associative arrays, no ${var,,}, no `((x++))`, no `nullglob`.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/helpers-core.sh"

# This script promotes the project's changelog and tags the project's history.
# Running it from the framework clone would cut a release OF THE FRAMEWORK from
# a downstream project's record. Refuse early — the same guard, for the same
# reason, as scripts/delta.sh's and scripts/process-checklist.sh's.
guard_not_in_framework || exit 1

# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/delta-policy.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/delta-cadence.sh"

SEAM="$SCRIPT_DIR/process-checklist.sh"
CHECKER="$SCRIPT_DIR/check-maintenance.sh"
REVALIDATOR="$SCRIPT_DIR/run-phase3-validation.sh"
CHANGELOG="CHANGELOG.md"

USAGE="Usage:
  scripts/cut-release.sh
  scripts/cut-release.sh --help

  Cuts the next release. It works out the version number from the work you
  have closed, moves your changelog's Unreleased section under that version,
  records which release carried each closed change, and creates the tag your
  release pipeline watches for.

  It refuses, and does nothing at all, while any of these is true:
    - a delta is still open
    - a hotfix still owes its write-up
    - a maintenance cadence is overdue, or could not be measured

  THERE IS NO WAY TO CHOOSE THE VERSION BY HAND. The tool decides it from the
  classes of what you closed. That is deliberate and it is written down:
  see §9.1 and §13-R2 of docs/designs/2026-08-02-delta-track-v1.md."

# ── Arguments ───────────────────────────────────────────────────────────────
# The surface is one command. Every unrecognised argument is an invocation
# error, INCLUDING the version-override spellings someone will reach for first:
# answering them with "unknown option" rather than silently ignoring them is
# the difference between a decision the operator can read and a flag they think
# worked.
case "${1:-}" in
  "") : ;;
  --help|-h) printf '%s\n' "$USAGE"; exit 0 ;;
  *)
    print_fail "cut-release.sh: '$1' is not something this command takes."
    printf '%s\n' "$USAGE" >&2
    exit 2
    ;;
esac

# ── Environment ─────────────────────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  print_fail "jq is required to read the delta record, and it is not on PATH."
  echo "To clear this: install jq (https://jqlang.github.io/jq/), then run this again." >&2
  exit 2
fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  print_fail "This is not a git repository, so there is nowhere to put a release tag."
  echo "To clear this: run this from inside your project's git repository." >&2
  exit 2
fi
if [ ! -f "$CHANGELOG" ]; then
  print_fail "There is no $CHANGELOG here, so there is nothing to promote."
  echo "To clear this: create $CHANGELOG with an '## [Unreleased]' section (the framework's" >&2
  echo "  template is templates/generated/changelog.tmpl), then run this again." >&2
  exit 2
fi

# _refuse <code> <headline> — the one shape every refusal takes. The remedy is
# printed by the caller immediately after; `To clear this:` is the anchor the
# suite asserts on, so every refusal has to earn it.
_refuse() {
  local code="$1"; shift
  echo ""
  print_fail "$*"
  return "$code"
}

echo -e "${BOLD}Cutting a release${NC}"
echo ""

# ═════════════════════════════════════════════════════════════════════════════
# PHASE A — READ AND REFUSE. NOTHING BELOW THIS LINE WRITES ANYTHING, ALL THE
# WAY DOWN TO THE `PHASE B` BANNER. Adding a write here is the defect §9.2 is
# about; the WP7 suite's whole-tree manifest is what would catch it.
# ═════════════════════════════════════════════════════════════════════════════

# ── The state read: STRICT, never tolerant (WP5's R-WP5-2) ──────────────────
STATE_RC=0
STATE_DOC="$(bash "$SEAM" --delta-state-read-strict </dev/null 2>/dev/null)" || STATE_RC=$?
case "$STATE_RC" in
  0) : ;;
  4)
    _refuse 7 "There is no delta record in this project, so there is nothing this tool can honestly release." || true
    echo "  A release cut reads .claude/delta-state.json to work out what shipped and what is still"
    echo "  owed. With no record at all it cannot tell an empty release from an erased one, and it"
    echo "  will not guess."
    echo ""
    echo "To clear this: open and close your work with scripts/delta.sh so there is a record to"
    echo "  release — or, if the record was deleted by accident, restore it from git."
    exit 7
    ;;
  *)
    _refuse 6 "The delta record exists and cannot be read, so this release is refused." || true
    echo "  .claude/delta-state.json is present but is not a readable delta record (the strict read"
    echo "  answered $STATE_RC). An unreadable record is NOT the same as an empty one, and treating"
    echo "  it as empty is how an outstanding obligation disappears silently."
    echo ""
    echo "To clear this: repair .claude/delta-state.json — 'git diff .claude/delta-state.json' and"
    echo "  'git checkout -- .claude/delta-state.json' will usually do it — then run this again."
    exit 6
    ;;
esac

# ── REFUSAL 1 — an open delta (§9.2). Instant, no I/O. ──────────────────────
ACTIVE_ID="$(printf '%s\n' "$STATE_DOC" \
  | jq -r 'if (.active_delta // null) == null then "__none__" else (.active_delta.id // "an unnamed delta") end' 2>/dev/null)" \
  || ACTIVE_ID="__none__"
[ -n "$ACTIVE_ID" ] || ACTIVE_ID="__none__"
ACTIVE_OPEN=n
if [ "$ACTIVE_ID" != "__none__" ]; then ACTIVE_OPEN=y; fi   # CUTREL-REFUSE-ACTIVE
if [ "$ACTIVE_OPEN" = y ]; then
  _refuse 3 "$ACTIVE_ID is still open, so there is nothing settled enough to release." || true
  echo "  A release names what is finished. Work that is still open is neither in this release nor"
  echo "  out of it, and whichever the tag implied would be wrong."
  echo ""
  echo "To clear this: finish or abandon $ACTIVE_ID first —"
  echo "  scripts/delta.sh --status     to see what it is still waiting on"
  echo "  scripts/delta.sh --close      when everything it needs is done"
  exit 3
fi

# ── REFUSAL 2 — an unfiled hotfix retro (§9.2). D3's collateral. ────────────
# FAIL-CLOSED: anything that is not a definite "none owed" refuses. WP5's
# predicate answers rc 1 for "none", rc 0 for "at least one open", and rc 3 for
# "that document is not a readable ledger" — and rc 3 must never be read as
# absolution. The strict read above makes rc 3 unreachable in practice; this is
# the backstop, because a contract that only holds when everyone uses the right
# front door is a convention and not a property.
RETRO_RC=0
delta_any_open_retro "$STATE_DOC" || RETRO_RC=$?
RETRO_REFUSE=n
if [ "$RETRO_RC" -ne 1 ]; then RETRO_REFUSE=y; fi   # CUTREL-REFUSE-RETRO
if [ "$RETRO_REFUSE" = y ]; then
  _refuse 4 "A hotfix still owes its write-up, so this release is refused." || true
  if [ "$RETRO_RC" -eq 0 ]; then
    echo "  Shipping a hotfix borrows the checks a normal change goes through. The write-up is how"
    echo "  that gets paid back, and a release is the moment it comes due. Still outstanding:"
    echo ""
    delta_retro_rows "$STATE_DOC" | while IFS="$(printf '\t')" read -r rid rdue rstate rdays; do
      [ -n "$rid" ] || continue
      case "$rstate" in
        overdue)      echo "    $rid — was due $rdue, $rdays day(s) overdue" ;;
        current)      echo "    $rid — due $rdue, $rdays day(s) from now" ;;
        *)            echo "    $rid — due date '$rdue' could not be read, so it is treated as overdue" ;;
      esac
    done
  else
    echo "  The hotfix ledger could not be read at all (the predicate answered $RETRO_RC), and an"
    echo "  unreadable ledger is not the same as an empty one."
  fi
  echo ""
  echo "To clear this: file each write-up with"
  echo "  scripts/delta.sh --retro DELTA-NNN --record \"what happened, and what stops it happening again\""
  exit 4
fi

# ── REFUSAL 3 — cadence overdue OR unmeasurable (§9.2 + §8.3) ───────────────
# The checker's own report names each arm and its remediation, including the
# arms it could not measure INSIDE an rc-1 answer, so it is surfaced verbatim.
# Replacing it with a headline of our own would drop exactly the detail that
# tells the operator which cadence to go and fix.
CADENCE_RC=0
CADENCE_OUT="$(bash "$CHECKER" </dev/null 2>&1)" || CADENCE_RC=$?
CADENCE_REFUSE=n
case "$CADENCE_RC" in
  0) : ;;
  1) CADENCE_REFUSE=y ;;   # CUTREL-CADENCE-OVERDUE
  2) CADENCE_REFUSE=y ;;   # CUTREL-CADENCE-UNMEASURABLE
  *) CADENCE_REFUSE=y ;;   # CUTREL-CADENCE-OTHER
esac
if [ "$CADENCE_REFUSE" = y ]; then
  case "$CADENCE_RC" in
    1) _refuse 5 "A maintenance cadence is overdue, so this release is refused." || true ;;
    2) _refuse 5 "A maintenance cadence could not be measured, so this release is refused." || true ;;
    *) _refuse 5 "The maintenance check did not complete (it exited $CADENCE_RC), so this release is refused." || true ;;
  esac
  echo "  What the check reported, verbatim:"
  echo ""
  printf '%s\n' "$CADENCE_OUT" | sed -e 's/^/    /'
  echo ""
  echo "To clear this: do the maintenance the report names above, commit it so the dates move,"
  echo "  and run 'bash scripts/check-maintenance.sh' until it exits 0. An unmeasurable cadence"
  echo "  needs a signal the check can read, not an exemption."
  exit 5
fi

# ═════════════════════════════════════════════════════════════════════════════
# THE THREE REFUSALS HAVE PASSED. Everything from here to the PHASE B banner is
# still read-only — the version arithmetic and its own two refusals.
# ═════════════════════════════════════════════════════════════════════════════

# _cutrel_last_tag — the highest `vMAJOR.MINOR.PATCH` tag in this repository,
#   with the `v` stripped, or the empty string when there is none.
#
#   Non-conforming tags are IGNORED rather than refused: a project may carry
#   `nightly`, `v1.2` or `release-2024` from before it adopted this tool, and
#   none of them is a version this arithmetic can build on. `sort -t. -kN,Nn`
#   is numeric per component, so v1.10.0 correctly outranks v1.9.0 — a plain
#   lexical sort gets that backwards and would cut a release that goes
#   BACKWARDS. Each stage absolves itself with `|| true` because bash's
#   `pipefail` promotes a no-match `grep` (rc 1) into the substitution, and
#   under `set -e` that is an abort rather than "no tags yet".
_cutrel_last_tag() {
  local out=""
  out="$( { git tag --list 2>/dev/null || true; } \
        | { grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true; } \
        | sed -e 's/^v//' \
        | sort -t. -k1,1n -k2,2n -k3,3n \
        | awk 'END { if (NR > 0) print }' )" || out=""
  printf '%s' "$out"
}

# THE PRECEDENCE — machinery, not policy (§9.1). One line, on purpose: it is
# the whole of "how bumps combine", it has no configuration surface, and the
# WP7 suite's m4 changes exactly this line to prove a feature can be made to
# ship as a patch when it is wrong.
_cutrel_rank() { case "${1:-}" in major) printf 3 ;; minor) printf 2 ;; *) printf 1 ;; esac; }   # CUTREL-SEMVER-PRECEDENCE

LAST_VERSION="$(_cutrel_last_tag)"
if [ -n "$LAST_VERSION" ]; then
  CUR_MAJOR="$(printf '%s' "$LAST_VERSION" | cut -d. -f1)"
  CUR_MINOR="$(printf '%s' "$LAST_VERSION" | cut -d. -f2)"
  CUR_PATCH="$(printf '%s' "$LAST_VERSION" | cut -d. -f3)"
else
  CUR_MAJOR=0; CUR_MINOR=0; CUR_PATCH=0
fi
case "$CUR_MAJOR" in ''|*[!0-9]*) CUR_MAJOR=0 ;; esac
case "$CUR_MINOR" in ''|*[!0-9]*) CUR_MINOR=0 ;; esac
case "$CUR_PATCH" in ''|*[!0-9]*) CUR_PATCH=0 ;; esac

# ── What is being released: every closed row with no `shipped_in` ───────────
UNSHIPPED_IDS="$(printf '%s\n' "$STATE_DOC" \
  | jq -r '[.closed[]? | select(type == "object") | select((.shipped_in // null) == null)] | .[] | (.id // "")' 2>/dev/null)" \
  || UNSHIPPED_IDS=""
UNSHIPPED_N="$(printf '%s\n' "$UNSHIPPED_IDS" | grep -c . || true)"
case "$UNSHIPPED_N" in ''|*[!0-9]*) UNSHIPPED_N=0 ;; esac

if [ "$UNSHIPPED_N" -eq 0 ]; then
  _refuse 8 "Nothing has been closed since the last release, so there is nothing to cut." || true
  if [ -n "$LAST_VERSION" ]; then
    echo "  The last release was v$LAST_VERSION and every closed change already records the release"
    echo "  that carried it. A tag with nothing behind it is noise in the history."
  else
    echo "  There are no closed changes on the record at all yet."
  fi
  echo ""
  echo "To clear this: close some work first —"
  echo "  scripts/delta.sh --open       to start the next change"
  echo "  scripts/delta.sh --close      when it is done"
  exit 8
fi

# ── The bump (§9.1) ─────────────────────────────────────────────────────────
# The token per row: `breaking` when the row carries a breaking marker,
# otherwise its class. The map from token to bump is project policy; the
# combination of bumps is not.
SEMVER_MAP="$(delta_policy_get "." semver 2>/dev/null)" || SEMVER_MAP=""
[ -n "$SEMVER_MAP" ] || SEMVER_MAP='{}'

ROW_TOKENS="$(printf '%s\n' "$STATE_DOC" \
  | jq -r '.closed[]? | select(type == "object") | select((.shipped_in // null) == null)
           | [ (.id // "?"), (if (.breaking // false) == true then "breaking" else (.class // "") end) ] | @tsv' 2>/dev/null)" \
  || ROW_TOKENS=""

BUMP=""
BUMP_RANK=0
UNMAPPED=""
RELEASE_LINES=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  rid="$(printf '%s' "$line" | cut -f1)"
  tok="$(printf '%s' "$line" | cut -f2)"
  rbump="$(printf '%s\n' "$SEMVER_MAP" | jq -r --arg t "$tok" '.[$t] // ""' 2>/dev/null)" || rbump=""
  case "$rbump" in
    major|minor|patch) : ;;
    *) UNMAPPED="${UNMAPPED}    $rid — class '$tok'
"; continue ;;
  esac
  RELEASE_LINES="${RELEASE_LINES}    $rid ($tok -> $rbump)
"
  r="$(_cutrel_rank "$rbump")"
  if [ "$r" -gt "$BUMP_RANK" ]; then BUMP_RANK="$r"; BUMP="$rbump"; fi
done <<EOF
$ROW_TOKENS
EOF

# FAIL-CLOSED on a class nobody scored. The tempting default is `patch`, and it
# is the wrong one: the whole danger in this arithmetic is UNDER-bumping, and a
# class the policy never heard of is precisely the case where nobody has said
# whether it breaks anything.
if [ -n "$UNMAPPED" ]; then
  _refuse 9 "Some of the closed work has a class this project's policy does not score, so the version cannot be computed." || true
  echo "  Unscored:"
  echo ""
  printf '%s' "$UNMAPPED"
  echo ""
  echo "  Guessing here would mean guessing whether those changes break anything, and the safe"
  echo "  guess and the honest one are not the same guess."
  echo ""
  echo "To clear this: add the class to the 'semver' object in .claude/delta-policy.json (values:"
  echo "  major, minor or patch), or correct the class on the closed row."
  exit 9
fi

if [ -z "$BUMP" ]; then BUMP=patch; fi

case "$BUMP" in
  major) NEXT_MAJOR=$((CUR_MAJOR + 1)); NEXT_MINOR=0;                  NEXT_PATCH=0 ;;
  minor) NEXT_MAJOR=$CUR_MAJOR;         NEXT_MINOR=$((CUR_MINOR + 1)); NEXT_PATCH=0 ;;
  *)     NEXT_MAJOR=$CUR_MAJOR;         NEXT_MINOR=$CUR_MINOR;         NEXT_PATCH=$((CUR_PATCH + 1)) ;;
esac

# THE TAG FORMAT — exactly three numeric components, nothing else (§9.3 + C7).
TAG="v${NEXT_MAJOR}.${NEXT_MINOR}.${NEXT_PATCH}"   # CUTREL-TAG-FORMAT
VERSION="${TAG#v}"

# The C7 defence in depth: whatever the line above produced, refuse to use it
# unless it is the shape GitLab's release lane will actually match. A tag that
# only two of the three hosts build is worse than no tag, because two of them
# go green. A glob would NOT do here — `v[0-9]*.[0-9]*.[0-9]*` matches
# `v1.2.0-rc1` perfectly well, since `*` spans the suffix — so the check is the
# same anchored ERE the GitLab lane itself uses.
if ! printf '%s' "$TAG" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then   # CUTREL-TAG-STRICT
  print_fail "cut-release.sh computed the tag '$TAG', which is not the vMAJOR.MINOR.PATCH form the release lanes require."
  echo "To clear this: this is a bug in cut-release.sh — report it. GitLab's release lanes match" >&2
  echo "  /^v[0-9]+\\.[0-9]+\\.[0-9]+\$/, so a tag of any other shape silently never builds there." >&2
  exit 2
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
  print_fail "The tag $TAG already exists in this repository, but the record says its work has not been released."
  echo "To clear this: the tag and .claude/delta-state.json disagree. Decide which is right —" >&2
  echo "  delete the tag if it was created by mistake, or record the release against the closed" >&2
  echo "  rows — and run this again." >&2
  exit 2
fi

echo "  Last release:      ${LAST_VERSION:-none}"
echo "  Closed since then: $UNSHIPPED_N change(s)"
printf '%s' "$RELEASE_LINES"
echo "  Version:           $TAG  (a $BUMP release, decided from the classes above)"
echo ""

# ═════════════════════════════════════════════════════════════════════════════
# PHASE B — WRITES. Everything above refused without touching anything.
#
# THE ORDER IS DELIBERATE, cheapest-to-undo first:
#   1. the §8.2 revalidation (major only) — it writes its OWN scan summaries,
#      which is why it is here and not in Phase A;
#   2. the changelog promotion — a text edit, visible in `git diff`;
#   3. `shipped_in`, one write-once seam call per released row;
#   4. the tag — last, because it is the thing the release pipelines watch, so
#      nothing fires until everything else is on disk.
# ═════════════════════════════════════════════════════════════════════════════

# ── §8.2: a major bump re-runs the FULL Phase 3 validation, before the tag ──
# "Composes with D6's 'breaking => major + full revalidation' as the same
# sentence seen from two sides." All five scanners, the same attest-on-skip
# contract as the 3->4 gate; this file does not re-implement any of it.
NEED_REVALIDATION=n
if [ "$BUMP" = major ]; then NEED_REVALIDATION=y; fi   # CUTREL-MAJOR-REVALIDATE
if [ "$NEED_REVALIDATION" = y ]; then
  if [ ! -f "$REVALIDATOR" ]; then
    _refuse 10 "This is a breaking release, and the full validation re-run it requires is not installed." || true
    echo "  Expected: $REVALIDATOR"
    echo ""
    echo "To clear this: reinstall the framework scripts, or re-run 'bash scripts/upgrade-project.sh'."
    exit 10
  fi
  print_info "A breaking change is in this release, so the full Phase 3 validation runs again before the tag."
  echo ""
  REVAL_RC=0
  bash "$REVALIDATOR" </dev/null || REVAL_RC=$?
  if [ "$REVAL_RC" -ne 0 ]; then
    _refuse 10 "The full validation re-run did not pass (it exited $REVAL_RC), so the breaking release is refused." || true
    echo "  A major version is the one release where the promise to your users changes. It does not"
    echo "  go out over a failing scan."
    echo ""
    echo "To clear this: fix what the run above reported, or attest each skipped scanner with a"
    echo "  reason and a sign-off, then run this again. Nothing has been written."
    exit 10
  fi
  echo ""
fi

# ── §9.3: promotion ─────────────────────────────────────────────────────────
# The categories are HARVESTED from the project's own `## [Unreleased]` block
# rather than retyped here. In a stock project that is the eight headings
# templates/generated/changelog.tmpl ships; in a project that added a ninth it
# is the ninth too. Retyping the list would have made this tool the second
# place the categories live, and the two would drift — exactly the class of
# split C2 measured between check-maintenance.sh and the builders' guide.
# The fallback list exists only for a changelog whose Unreleased block has no
# headings at all, and it is the template's list verbatim.
_cutrel_promote() {
  local file="$1" ver="$2" date="$3" n cats tmp
  n="$(awk '/^## \[Unreleased\]/ { print NR; exit }' "$file")" || n=""
  [ -n "$n" ] || return 1
  cats="$(awk -v s="$n" 'NR > s { if ($0 ~ /^## /) exit; if ($0 ~ /^### /) print }' "$file")" || cats=""
  if [ -z "$cats" ]; then                                            # CUTREL-PROMOTE-CATEGORIES
    cats="$(printf '### Security\n### Data Model\n### Added\n### Changed\n### Fixed\n### Removed\n### Infrastructure\n### Documentation')"
  fi
  tmp="$file.cutrel.tmp"
  rm -f "$tmp" 2>/dev/null || true
  {
    awk -v s="$n" 'NR < s { print }' "$file"
    printf '## [Unreleased]\n\n'
    printf '%s\n' "$cats"
    printf '\n'
    # The separator is passed as an ARGUMENT, never spliced next to a `$`
    # expansion — CLAUDE.md's portability rule about multibyte characters
    # adjacent to expansions under `set -u`.
    printf '## [%s] %s %s\n' "$ver" "—" "$date"
    awk -v s="$n" 'NR > s { print }' "$file"
  } > "$tmp" || { rm -f "$tmp" 2>/dev/null || true; return 1; }
  mv "$tmp" "$file" || { rm -f "$tmp" 2>/dev/null || true; return 1; }
  return 0
}

TODAY="$(date -u +%Y-%m-%d)"
if ! _cutrel_promote "$CHANGELOG" "$VERSION" "$TODAY"; then
  _refuse 11 "The changelog could not be promoted, so the cut stopped here." || true
  echo "  Nothing else has been written: no release was recorded and no tag was created."
  echo ""
  echo "To clear this: make sure $CHANGELOG has a line reading exactly '## [Unreleased]' and that"
  echo "  the file is writable, then run this again."
  exit 11
fi
print_ok "Promoted $CHANGELOG: '## [Unreleased]' is now '## [$VERSION] — $TODAY', with a fresh empty Unreleased above it."

# ── §7.1: `shipped_in`, through WP2's write-once ship pathway ────────────────
# Never a generic state write and never a direct file touch. The seam permits
# exactly ONE mutation shape here — one closed row's shipped_in going null to a
# non-empty string with everything else byte-identical — and refuses a row that
# already carries a version rather than overwriting it. That is D7's
# single-writer rule applied at the one place it is easiest to break.
SHIPPED_N=0
SHIP_FAILED=""
while IFS= read -r rid; do
  [ -n "$rid" ] || continue
  if bash "$SEAM" --delta-state-ship "$rid" "$TAG" </dev/null >/dev/null 2>&1; then
    SHIPPED_N=$((SHIPPED_N + 1))
  else
    SHIP_FAILED="${SHIP_FAILED}    $rid
"
  fi
done <<EOF
$UNSHIPPED_IDS
EOF

if [ -n "$SHIP_FAILED" ]; then
  _refuse 11 "The changelog was promoted, but the delta record refused to accept part of this release." || true
  echo "  Recorded: $SHIPPED_N of $UNSHIPPED_N. Refused:"
  echo ""
  printf '%s' "$SHIP_FAILED"
  echo ""
  echo "  NO TAG WAS CREATED, so no release pipeline has fired and nothing has been published."
  echo ""
  echo "To clear this: check .claude/delta-state.json for those ids (a row that already carries a"
  echo "  'shipped_in' is refused rather than overwritten, on purpose), fix it, and run this again."
  exit 11
fi
print_ok "Recorded $TAG against $SHIPPED_N closed change(s) in the delta record."

# ── §9.3: the tag. LAST, because this is what the pipelines watch. ──────────
# Created LOCALLY and never pushed. Pushing is the operator's decision and the
# moment the release becomes public; a tool that pushed would take that
# decision away and would also need a remote, which no test in this framework
# is allowed to create.
if ! git tag "$TAG" >/dev/null 2>&1; then
  _refuse 11 "The changelog and the delta record were both written, but the tag $TAG could not be created." || true
  echo ""
  echo "To clear this: create it yourself with 'git tag $TAG' once git will accept it. Do NOT"
  echo "  change the name — GitLab's release lanes match /^v[0-9]+\\.[0-9]+\\.[0-9]+\$/ exactly, so"
  echo "  any other shape silently never builds there."
  exit 11
fi

echo ""
print_ok "$TAG is cut."
echo ""
echo "What happens next, in this order:"
echo "  1. git add $CHANGELOG .claude/delta-state.json"
echo "  2. git commit -m \"chore(release): $TAG\""
echo "  3. git tag -f $TAG          # the tag is not pushed yet, so moving it onto the commit is free"
echo "  4. git push && git push origin $TAG"
echo ""
echo "  Step 3 is not optional: the tag currently names the commit you were on BEFORE the changelog"
echo "  was promoted, so a pipeline building from it would publish a changelog without this version"
echo "  in it. Your release pipeline fires on the tag push in step 4."
exit 0
