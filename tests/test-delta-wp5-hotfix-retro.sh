#!/usr/bin/env bash
# tests/test-delta-wp5-hotfix-retro.sh — Delta Track WP5.
#
# SPEC: docs/designs/2026-08-02-delta-track-v1.md §5.2 (the per-class gate
# table, its hotfix row, and "reading the hotfix row honestly" — the fast lane
# is a LOAN, collateralised by the release refusal), §5.2's incident-response
# seam paragraph (the two clocks differ on purpose and neither is built into the
# other), §7.1 (`hotfix_retros[]` — an array that OUTLIVES `active_delta`
# deliberately), §7.2 (`retro_due_days`, and the gate-token equivalence note:
# hotfix carries no `close_review` because `retro_review` IS its close review,
# arriving late), §9.2 (the release refusals WP7 will build on the predicates
# this WP ships), §11-WP5.
#
# (No `# BL-NNN-…` marker anywhere in the delta track on purpose: no backlog
# entry exists for this build and minting one would red
# scripts/lint-bl-markers.sh, whose first pass resolves every marker to a real
# `## BL-NNN:` entry. The design-doc path above is the citation, per the WP1,
# WP2, WP3 and WP4 precedent.)
#
# ═════════════════════════════════════════════════════════════════════════════
# THE ONE PROPERTY THIS SUITE EXISTS FOR
#
# A hotfix ships fast by BORROWING rigor. The retro is the repayment. So the
# retro ledger must OUTLIVE the delta's close — if closing the delta also closed
# the retro, the loan is forgiven the instant it is taken out and the entire
# §5.2 design intent is gone, silently, with every visible surface still saying
# the right things. S1 is that property and m2 is the mutant that proves S1 can
# see it.
#
# ═════════════════════════════════════════════════════════════════════════════
# EXIT CODES, NEVER LABELS
#
# Every assertion below reads a process EXIT CODE, a JSON value read back off
# disk, or a byte-level md5 / whole-tree manifest. None reads a printed
# [OK]/[WARN]/[FAIL] banner. CLAUDE.md's `[WARN]` trap is exactly that the label
# and the exit predicate can disagree — and WP6's sibling defect (BL-213's
# fail-open class) is the same disease in date form: check-maintenance.sh today
# prints "All maintenance cadences current" at rc 0 for a date it could not
# read. O2 and m3 pin the WP5 half of that repair ON THE EXIT CODE.
#
# The codes this WP adds to scripts/delta.sh:
#     11  there is no retro on the record with that id
#     12  that retro is already filed — the record is write-once
# and the ones it inherits and re-reads: 0 ok, 2 invocation error, 6 nothing
# open, 7 gates outstanding.
#
# The codes scripts/lib/delta-cadence.sh answers with — the interface WP7's
# cut-release.sh consumes, asserted here so WP7 can build against it:
#     delta_retro_overdue     0 OVERDUE (including an unreadable due_by), 1 open
#                             and not yet due, 2 no OPEN retro with that id
#     delta_any_open_retro    0 at least one open retro, 1 none
#     delta_any_overdue_retro 0 at least one open retro that is overdue or
#                             unreadable, 1 none
#
# ═════════════════════════════════════════════════════════════════════════════
# WHAT THIS SUITE PINS, AND WHICH MUTANT EACH ROW KILLS
#
#   H — THE HOTFIX FAST LANE AT OPEN (§5.2)
#     H1  a hotfix materialises EXACTLY the §5.2 row and NOTHING heavier — the
#         set is asserted whole, not as a subset; no brief is demanded anywhere;
#         and the open writes no file outside the two `.claude/` documents, so
#         the floor (§5.1) is inherited rather than re-implemented
#     H2  the AUDIT ROW IS WRITTEN AT OPEN, not at close: the stamp is on the
#         record and the gate is already complete the moment the delta opens —
#         it is the one gate in the system nobody attests, because the framework
#         did it
#     H3  and the trace survives ABANDONMENT — a hotfix that never closes still
#         left it, and its id is never handed out again
#
#   L — THE RETRO LEDGER, APPENDED AT OPEN (§7.1)
#     L1  the row is appended AT OPEN with exactly §7.1's five keys and
#         due_by = shipped_at + 3 days (Karl set 3, not 7)             KILLS m1
#     L2  `retro_due_days` is READ FROM POLICY: retune it and the date moves
#                                                                      KILLS m5
#     L3  no other class writes a retro row
#
#   S — THE RETRO OUTLIVES THE CLOSE (the whole point)
#     S1  closing the hotfix delta nulls `active_delta` and grows `closed` — and
#         leaves the retro row byte-identically OPEN                   KILLS m2
#     S2  the close is not BLOCKED by the open retro, but it IS blocked when the
#         retro row is absent: fail-closed, rc 7, naming retro_review  KILLS m6
#     S3  `--complete-gate retro_review` is refused — the loan cannot be repaid
#         by ticking a box, which is §7.2's "the loan going unrepaid" spelled as
#         the one thing that would make it happen
#
#   T — `--retro`
#     T1  closes EXACTLY one retro; the other open row is untouched; the write
#         is one atomic seam call and its residue is bounded to that row's two
#         fields
#     T2  a second `--retro` on the same id is refused (12)            KILLS m4
#     T3  an unknown id (11) and a missing record (2) are refused
#     T4  THE RECORD CONTRACT, honestly kinded: a value that names an existing
#         file is recorded as `file`, anything else as `attested` — the
#         framework never claims to have read a write-up it cannot find
#
#   O — OVERDUE ARITHMETIC (scripts/lib/delta-cadence.sh)
#     O1  2 days old is not overdue at the default 3; 4 days old is; a project
#         that retunes to 7 finds the same 4-day-old retro current
#     O2  AN UNREADABLE `due_by` IS OVERDUE, NOT SILENTLY CURRENT — BL-213's
#         fail-open class, refused here                                KILLS m3
#     O3  the whole-ledger predicates in all four states
#     O4  the parse helper: GNU-first `date -d`, BSD `date -j -f` fallback,
#         rc 1 AND NO OUTPUT on garbage, and a bare date normalised to midnight
#         UTC so BSD's fill-from-now can never leak in
#
#   V — `--status` RENDERS OPEN AND OVERDUE RETROS
#     V1  with nothing open and with a delta open; overdue named as overdue; an
#         unreadable date named as unreadable AND late; and — the structural
#         discriminator — a filed retro appears nowhere
#
#   N — REFUSAL RESIDUE (the WP4 standard, inherited verbatim)
#     N1  every `--retro` refusal leaves the WHOLE TREE byte-for-byte as it
#         found it, asserted as a find-based manifest with a per-file md5
#
# ═════════════════════════════════════════════════════════════════════════════
# COUNTERFACTUAL DISCIPLINE — how the mutations below are built
#
# Inherited from tests/test-delta-wp3-era-classify.sh and
# tests/test-delta-wp4-close-rubric.sh, unchanged, because it is what makes a
# mutation proof a proof:
#
#   • ANCHORED SINGLE-SITE addresses. Every marker is pinned to END-OF-LINE
#     (`/# DELTA-OPEN-RETRO-APPEND$/`), never a bare substring — WP2's suite
#     records what over-matching costs.
#   • THREE PROPERTIES ASSERTED BEFORE THE RESULT IS BELIEVED: the marker
#     resolves to EXACTLY ONE line in the pristine file; the mutant DIFFERS from
#     it; and EXACTLY ONE LINE changed (one `<` and one `>`).
#   • MODE-PRESERVING harness. `_sed_inplace` reads each file's mode and puts it
#     back; the obvious `chmod +x` spelling silently turns a sourced 0644 lib
#     into 0755 and the mode rides along in the next commit.
#   • FRESH-FIXTURE ISOLATION. Every mutation builds its own mktemp project, and
#     the fixture must REACH the guard under test — m6's fixture has to have the
#     retro row removed, or the bind is satisfied for the honest reason and the
#     mutant looks pinned when it is not.
#   • STRUCTURAL DISCRIMINATORS WHERE THE EXPECTED RESULT IS AN ABSENCE. Five of
#     the six mutants below expect "the refusal did not happen", which is the
#     same answer a fixture that never reached the guard would give. Each of
#     those rows therefore also asserts a POSITIVE consequence of the mutation
#     having landed — the mutant's ledger is EMPTY while the pristine tree's
#     carries a row (m1); the mutant's retro is CLOSED with the delta's own
#     closed_at while the pristine tree's is still open (m2); the mutant's
#     record still holds the FIRST write-up while reporting the second as saved
#     (m4); the mutant's due_by interval is 3 days under a policy that says 9
#     (m5); the mutant closed a hotfix whose ledger has no row at all (m6) — and
#     every one of them is measured against the PRISTINE tree run on an
#     identical fixture in the same case.
#
# ═════════════════════════════════════════════════════════════════════════════
# HERMETICITY: every fixture is a mktemp -d project carrying NO init.sh and NO
# templates/generated, so guard_not_in_framework sees a project and not the
# framework. Git fixtures configure an identity and unset GITHUB_BASE_REF. No
# remote is ever created; nothing reaches the network; nothing is written inside
# the checkout. bash-3.2 safe: no associative arrays, no ${var,,}, no ((x++)).
#
# TIME: no test overrides "now". Ageing a retro is done by shifting BOTH
# `shipped_at` and `due_by` back by the same amount through the seam, so the
# INTERVAL between them — the product's own arithmetic — is preserved exactly
# and only the row's age moves. A suite that faked `now` would be pinning its
# own clock.
#
# LANE: registered in tests/full-project-test-suite.sh AND in the tests.yml
# `unit-shard` list. Its executed lines never name init.sh.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for tests/test-delta-wp5-hotfix-retro.sh" >&2
  exit 2
fi
if ! command -v git >/dev/null 2>&1; then
  echo "git is required for tests/test-delta-wp5-hotfix-retro.sh" >&2
  exit 2
fi

# Portable md5 of a single file (macOS `md5 -q`, Linux `md5sum`) — house pattern.
_md5file() {
  if command -v md5 >/dev/null 2>&1; then md5 -q "$1"
  else md5sum "$1" | awk '{print $1}'; fi
}

# ── Fixtures ────────────────────────────────────────────────────────────────

mk_proj() {
  local d="$1" phase="$2"
  mkdir -p "$d/.claude"
  printf '{"track":"light","deployment":"personal","poc_mode":null,"current_phase":%s,"phases":{}}\n' \
    "$phase" > "$d/.claude/phase-state.json"
}

# A project carrying DECOYS: a generated pre-commit hook and the two ledgers a
# real post-1.0 project has. H1 asserts the fast lane touches none of them —
# §5.1's floor is INHERITED, and the delta track adds no floor arm. A fixture
# with nothing to disturb could not tell "added no arm" from "found nothing".
mk_decoy_proj() {
  local d="$1" phase="$2"
  mk_proj "$d" "$phase"
  mkdir -p "$d/.git/hooks" "$d/docs"
  printf '#!/bin/sh\n# the shipped floor: gitleaks, semgrep, tests, TDD ordering\nexit 0\n' \
    > "$d/.git/hooks/pre-commit"
  printf '# BUGS\n\n| # | Severity | Title |\n|---|---|---|\n' > "$d/BUGS.md"
  printf '# FEATURES\n\n| # | Title |\n|---|---|\n' > "$d/FEATURES.md"
  printf '# Changelog\n\n## [Unreleased]\n\n### Fixed\n' > "$d/CHANGELOG.md"
}

mk_scripts_tree() {
  mkdir -p "$1"
  cp -R "$REPO_ROOT/scripts" "$1/scripts"
}

write_policy() { printf '%s\n' "$2" > "$1/.claude/delta-policy.json"; }

# ── Runners ─────────────────────────────────────────────────────────────────

delta_run() {
  local sd="$1" p="$2"; shift 2
  ( cd "$p" && unset GITHUB_BASE_REF; bash "$sd/delta.sh" "$@" </dev/null 2>&1 )
}

seam() {
  local sd="$1" p="$2"; shift 2
  ( cd "$p" && unset GITHUB_BASE_REF; bash "$sd/process-checklist.sh" "$@" </dev/null 2>/dev/null )
}

# cad <scripts-dir> <function> [args…] — call one scripts/lib/delta-cadence.sh
# function the way a real consumer does: sourced into a script running under
# `set -euo pipefail`, with its EXIT CODE propagated. WP7's cut-release.sh is
# the consumer this shape is designed for, so the tests call it that way too.
cad() {
  local sd="$1"; shift
  bash -c 'set -euo pipefail
           . "$0/lib/delta-cadence.sh"
           fn="$1"; shift
           "$fn" "$@"' "$sd" "$@"
}

# active_json <project-dir> [jq-flags…] <filter> — read an assertion straight
# off the state file the seam wrote. A missing or unreadable file yields the
# literal READ-FAILED, which no expectation below ever matches: a helper that
# returned "" would let an absent file satisfy any negative assertion.
active_json() {
  local p="$1"; shift
  jq "$@" "$p/.claude/delta-state.json" 2>/dev/null || printf 'READ-FAILED'
}

# complete_gates <scripts-dir> <project-dir> [skip-token]
#   Attest every gate this delta owes, optionally leaving ONE outstanding. Every
#   completion goes through the production surface, never a hand-written file.
#   `retro_review` is deliberately NOT special-cased here: the production
#   surface refuses it (S3), this helper ignores the refusal, and the close
#   still succeeds because the ledger row is what satisfies it.
complete_gates() {
  local sd="$1" p="$2" skip="${3:-}" g
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    [ "$g" = "$skip" ] && continue
    delta_run "$sd" "$p" --complete-gate "$g" >/dev/null 2>&1
  done <<EOF
$(jq -r '.active_delta.gates_required[]? // empty' "$p/.claude/delta-state.json" 2>/dev/null)
EOF
  return 0
}

# open_hotfix <scripts-dir> <project-dir> <slug>
open_hotfix() {
  local sd="$1" p="$2" slug="$3"
  delta_run "$sd" "$p" --open --describe "checkout is down in production right now" \
    --class hotfix --slug "$slug" --confirm >/dev/null 2>&1
  return 0
}

# ship_hotfix <scripts-dir> <project-dir> <slug> — open a hotfix and CLOSE it,
# which is the state every retro spends most of its life in: the delta is done,
# the write-up is not.
ship_hotfix() {
  local sd="$1" p="$2" slug="$3"
  open_hotfix "$sd" "$p" "$slug"
  complete_gates "$sd" "$p"
  delta_run "$sd" "$p" --close >/dev/null 2>&1
  return 0
}

# age_retro <scripts-dir> <project-dir> <id> <days>
#   Shift one retro row BACK in time by <days>, moving `shipped_at` and `due_by`
#   by the SAME amount. The interval between them — which is the product's own
#   arithmetic and the thing under test — is preserved exactly; only the row's
#   age changes. Through the seam, because the seam is the only writer (§7.1).
age_retro() {
  local sd="$1" p="$2" id="$3" days="$4"
  seam "$sd" "$p" --delta-state-update "
    .hotfix_retros = [ .hotfix_retros[]
      | if .id == \"$id\" then
            .shipped_at = ((.shipped_at | strptime(\"%Y-%m-%dT%H:%M:%SZ\") | mktime) - $days * 86400 | strftime(\"%Y-%m-%dT%H:%M:%SZ\"))
          | .due_by     = ((.due_by     | strptime(\"%Y-%m-%dT%H:%M:%SZ\") | mktime) - $days * 86400 | strftime(\"%Y-%m-%dT%H:%M:%SZ\"))
        else . end ]" >/dev/null 2>&1
  return 0
}

# interval_days <project-dir> <index> — whole days between shipped_at and due_by
# on one ledger row, computed from the row itself. This is what proves the
# product read the policy: the test never states an expected DATE, only an
# expected INTERVAL.
interval_days() {
  local p="$1" i="$2"
  active_json "$p" -r --argjson i "$i" '
    .hotfix_retros[$i] as $r
    | (($r.due_by | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime)
       - ($r.shipped_at | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime)) / 86400
    | floor'
}

# tree_files <project-dir> — every file in the tree, one per line, sorted.
# `.git/**` is excluded and that exclusion is not a convenience: `git diff` is
# allowed to refresh the index's stat cache, so `.git/index` can legitimately
# change bytes during a read-only measurement.
tree_files() {
  ( cd "$1" && find . -type f ! -path './.git/*' | LC_ALL=C sort )
}

# tree_manifest <project-dir> — every file in the tree with its md5. THE
# refusal-residue instrument: a refusal that says "nothing was recorded" is a
# claim about the whole filesystem, and checking one expected filename cannot
# see a file nobody thought to look for.
tree_manifest() {
  local p="$1" f
  tree_files "$p" | while IFS= read -r f; do
    printf '%s  %s\n' "$(_md5file "$p/$f")" "$f"
  done
}

# ── Mutation harness (inherited from the WP2/WP3/WP4 suites) ────────────────

_sed_inplace() {
  local file="$1" expr="$2" tmp mode
  mode="$(stat -c '%a' "$file" 2>/dev/null || stat -f '%Lp' "$file" 2>/dev/null || echo "")"
  tmp="$(mktemp)"
  sed -e "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
  [ -n "$mode" ] && chmod "$mode" "$file" 2>/dev/null
  return 0
}

_mutation_report() {
  local orig="$1" mut="$2" marker="$3" sites changed n
  sites="$(grep -c "$marker" "$orig" || true)"
  case "$sites" in ''|*[!0-9]*) sites=0 ;; esac
  if diff "$orig" "$mut" >/dev/null 2>&1; then changed=n; else changed=y; fi
  n="$(diff "$orig" "$mut" | grep -c '^[<>]' || true)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s|%s|%s' "$sites" "$changed" "$n"
}

echo "== tests/test-delta-wp5-hotfix-retro.sh =="
echo ""

# ════════════════════════════════════════════════════════════════════════════
echo "=== H — the hotfix fast lane at open (§5.2) ==="
# ════════════════════════════════════════════════════════════════════════════

# ── H1: EXACTLY the §5.2 row, and nothing heavier ───────────────────────────
# The set is asserted WHOLE. A subset assertion ("it has ledger_row") would pass
# for a hotfix that also demanded a brief, a brief review and the full Build
# Loop — which is the entire thing the fast lane is not.
#
# And the floor is INHERITED, not re-implemented (§5.1): the decoy tree carries
# a pre-commit hook and three ledgers, and the whole-tree manifest says the open
# added exactly the two `.claude/` documents and disturbed nothing else.
T=$(mktemp -d); P="$T/proj"; mk_decoy_proj "$P" 4
before="$(tree_manifest "$P")"
out=$(delta_run "$REPO_ROOT/scripts" "$P" --open --describe "checkout is down in production right now" --class hotfix --slug checkout --confirm); rc=$?
after_files="$(tree_files "$P" | tr '\n' ' ')"
gates="$(active_json "$P" -c '.active_delta.gates_required')"
klass="$(active_json "$P" -r '.active_delta.class')"
# Nothing heavier: none of the three heavy tokens anywhere on the row or in the
# transcript, and no docs/deltas directory conjured into being.
heavy=n
printf '%s' "$gates" | grep -qE 'brief|build_loop' && heavy=y
had_deltas=n; [ -d "$P/docs/deltas" ] && had_deltas=y
# Everything that existed before is byte-identical afterwards.
undisturbed=y
printf '%s\n' "$before" | while IFS= read -r row; do
  [ -n "$row" ] || continue
  f="${row#*  }"
  printf '%s  %s\n' "$(_md5file "$P/$f")" "$f"
done > "$T/recheck"
printf '%s\n' "$before" | grep -v '^$' > "$T/before"
diff -q "$T/before" "$T/recheck" >/dev/null 2>&1 || undisturbed=n
if [ "$rc" -eq 0 ] && [ "$klass" = "hotfix" ] \
   && [ "$gates" = '["ledger_row","audit_row_at_open","retro_review","changelog"]' ] \
   && [ "$heavy" = n ] && [ "$had_deltas" = n ] && [ "$undisturbed" = y ] \
   && [ "$after_files" = "./.claude/delta-policy.json ./.claude/delta-state.json ./.claude/phase-state.json ./BUGS.md ./CHANGELOG.md ./FEATURES.md " ]; then
  pass "H1: a hotfix materialises EXACTLY the §5.2 row ($gates) and nothing heavier (no brief, no brief_review, no build_loop: heavy=$heavy, docs/deltas created=$had_deltas); the open adds only the two .claude documents and leaves the pre-commit hook and all three ledgers byte-identical (undisturbed=$undisturbed) — the floor is inherited, not re-implemented"
else
  fail_ "H1" "rc=$rc (expect 0); class=$klass; gates=$gates (expect the §5.2 hotfix row EXACTLY); heavy token present=$heavy (expect n); docs/deltas created=$had_deltas (expect n); pre-existing files undisturbed=$undisturbed (expect y); files after='$after_files'; output:\n$out"
fi
rm -rf "$T"

# ── H2: the AUDIT ROW is written AT OPEN, not at close ──────────────────────
# §5.2 spells the token `audit_row_at_open` and means it literally. The trace is
# on the record the instant the fast lane opens, and the gate is ALREADY
# COMPLETE — it is the one gate nobody attests, because the framework wrote it
# rather than asking. Asserted in both directions: the hotfix has it, and the
# other three classes have neither the stamp nor the pre-completed gate.
T=$(mktemp -d); P="$T/hotfix"; mk_proj "$P" 4
open_hotfix "$REPO_ROOT/scripts" "$P" checkout
stamp="$(active_json "$P" -r '.active_delta.audit_row_at_open')"
done_at_open="$(active_json "$P" -c '.active_delta.gates_completed')"
stamp_shape=n
printf '%s' "$stamp" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' && stamp_shape=y
Pf="$T/fix"; mk_proj "$Pf" 4
delta_run "$REPO_ROOT/scripts" "$Pf" --open --describe "the CSV export crashes on unicode" --confirm >/dev/null 2>&1
fix_stamp="$(active_json "$Pf" -r '.active_delta.audit_row_at_open // "ABSENT"')"
fix_done="$(active_json "$Pf" -c '.active_delta.gates_completed')"
if [ "$stamp_shape" = y ] && [ "$done_at_open" = '["audit_row_at_open"]' ] \
   && [ "$fix_stamp" = "ABSENT" ] && [ "$fix_done" = "[]" ]; then
  pass "H2: the audit row is stamped AT OPEN ($stamp) and audit_row_at_open is already complete before the operator has done anything ($done_at_open) — while a fix carries neither (stamp=$fix_stamp, completed=$fix_done). It is written, not claimed"
else
  fail_ "H2" "hotfix stamp='$stamp' well-formed=$stamp_shape (expect y); gates_completed at open=$done_at_open (expect [\"audit_row_at_open\"]); fix stamp=$fix_stamp (expect ABSENT); fix gates_completed=$fix_done (expect [])"
fi
rm -rf "$T"

# ── H3: the trace survives ABANDONMENT ──────────────────────────────────────
# "A hotfix that never closes still left its trace." Abandonment is spelled the
# only way it can be — the slot is emptied without a close — and the ledger row
# is still there afterwards, with its id still reserved so the next delta cannot
# be handed it.
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
open_hotfix "$REPO_ROOT/scripts" "$P" checkout
seam "$REPO_ROOT/scripts" "$P" --delta-state-update '.active_delta = null' >/dev/null 2>&1
slot="$(active_json "$P" -r '.active_delta')"
n_closed="$(active_json "$P" -r '.closed | length')"
ledger="$(active_json "$P" -c '[.hotfix_retros[] | {id, closed_at}]')"
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "add dark mode" --confirm >/dev/null 2>&1
next_id="$(active_json "$P" -r '.active_delta.id')"
if [ "$slot" = "null" ] && [ "$n_closed" = "0" ] \
   && [ "$ledger" = '[{"id":"DELTA-001","closed_at":null}]' ] && [ "$next_id" = "DELTA-002" ]; then
  pass "H3: a hotfix abandoned without ever closing (slot $slot, audit tail $n_closed rows) still left its trace — the ledger holds $ledger — and its id stays reserved, so the next open takes $next_id"
else
  fail_ "H3" "slot=$slot (expect null); closed length=$n_closed (expect 0); ledger=$ledger (expect DELTA-001 still open); next id=$next_id (expect DELTA-002)"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== L — the retro ledger, appended at OPEN (§7.1) ==="
# ════════════════════════════════════════════════════════════════════════════

# ── L1: appended at OPEN, §7.1's five keys, three days  [KILLS m1] ─────────
# THE DESIGN'S OWN MUTATION TARGET (§11-WP5): "the retro row is written at OPEN,
# not at close". So the row is read back BEFORE anything is closed, and the
# interval is computed off the row itself rather than compared to a date this
# test worked out — the test states an INTERVAL, never a DATE.
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
open_hotfix "$REPO_ROOT/scripts" "$P" checkout
n_rows="$(active_json "$P" -r '.hotfix_retros | length')"
keys="$(active_json "$P" -c '.hotfix_retros[0] | keys_unsorted')"
row_id="$(active_json "$P" -r '.hotfix_retros[0].id')"
row_closed="$(active_json "$P" -r '.hotfix_retros[0].closed_at')"
row_record="$(active_json "$P" -r '.hotfix_retros[0].record')"
shipped_is_open="$(active_json "$P" -r '.hotfix_retros[0].shipped_at == .active_delta.opened_at')"
days="$(interval_days "$P" 0)"
if [ "$n_rows" = "1" ] && [ "$row_id" = "DELTA-001" ] \
   && [ "$keys" = '["id","shipped_at","due_by","closed_at","record"]' ] \
   && [ "$row_closed" = "null" ] && [ "$row_record" = "null" ] \
   && [ "$shipped_is_open" = "true" ] && [ "$days" = "3" ]; then
  pass "L1: the retro row is on the record the moment the hotfix OPENS — one row, §7.1's five keys in order ($keys), id $row_id, closed_at $row_closed, record $row_record, shipped_at equal to the delta's own opened_at, and due_by exactly $days days later (Karl set 3, not 7)"
else
  fail_ "L1" "rows=$n_rows (expect 1); keys=$keys (expect §7.1's five, in order); id=$row_id; closed_at=$row_closed (expect null); record=$row_record (expect null); shipped_at == opened_at: $shipped_is_open (expect true); due_by - shipped_at = $days day(s) (expect 3)"
fi
rm -rf "$T"

# ── L2: retro_due_days is READ FROM POLICY  [KILLS m5] ─────────────────────
# The pin that separates "computed from policy" from "computed from a number
# that happens to agree with policy today". A project that retunes the window
# gets ITS window (§7.2 — "every key is overridable").
T=$(mktemp -d)
Pd="$T/default"; mk_proj "$Pd" 4
open_hotfix "$REPO_ROOT/scripts" "$Pd" checkout
d_default="$(interval_days "$Pd" 0)"
Pr="$T/retuned"; mk_proj "$Pr" 4
write_policy "$Pr" '{"schemaVersion":1,"classes":{"hotfix":{"gates":["ledger_row","audit_row_at_open","retro_review","changelog"],"retro_due_days":9}}}'
open_hotfix "$REPO_ROOT/scripts" "$Pr" checkout
d_retuned="$(interval_days "$Pr" 0)"
if [ "$d_default" = "3" ] && [ "$d_retuned" = "9" ]; then
  pass "L2: the window is READ FROM POLICY — the framework default gives $d_default days and a project that retunes classes.hotfix.retro_due_days to 9 gets $d_retuned, from the same code path"
else
  fail_ "L2" "framework default interval=$d_default (expect 3); retuned-to-9 interval=$d_retuned (expect 9) — if both are 3 the number is hardcoded, not read"
fi
rm -rf "$T"

# ── L3: no other class writes a retro row ──────────────────────────────────
# The ledger is the hotfix's alone. A fix, a feature and a security patch each
# open and close with an EMPTY ledger — asserted after the close, so a row that
# appeared at either moment would show.
T=$(mktemp -d)
l3_ok=y; l3_detail=""
_l3() {
  local class="$1" P n
  P="$T/$class"; mk_proj "$P" 4
  delta_run "$REPO_ROOT/scripts" "$P" --open --describe "something to do" --class "$class" --confirm >/dev/null 2>&1
  n="$(active_json "$P" -r '.hotfix_retros | length')"
  complete_gates "$REPO_ROOT/scripts" "$P"
  delta_run "$REPO_ROOT/scripts" "$P" --close >/dev/null 2>&1
  n="$n/$(active_json "$P" -r '.hotfix_retros | length')"
  l3_detail="$l3_detail [$class=$n]"
  [ "$n" = "0/0" ] || l3_ok=n
}
_l3 fix
_l3 security-patch
if [ "$l3_ok" = y ]; then
  pass "L3: no class but hotfix touches the ledger — at open and again after close, it is empty:$l3_detail"
else
  fail_ "L3" "expected 0/0 (rows at open / rows after close) for every non-hotfix class; got:$l3_detail"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== S — the retro OUTLIVES the close (§5.2's loan) ==="
# ════════════════════════════════════════════════════════════════════════════

# ── S1: the close does not close the retro  [KILLS m2] ─────────────────────
# THE PROPERTY THIS WHOLE SUITE EXISTS FOR. A hotfix ships fast by BORROWING
# rigor; the retro is the repayment. If closing the delta closed the retro, the
# loan would be forgiven the instant it was taken out — and every visible
# surface would still say the right thing.
#
# Asserted three ways so it cannot be satisfied by accident: the delta really
# did close (slot null, tail grew), the retro row is byte-identical to what open
# wrote (not merely "still present"), and the close ANNOUNCES the debt.
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
open_hotfix "$REPO_ROOT/scripts" "$P" checkout
row_at_open="$(active_json "$P" -c '.hotfix_retros[0]')"
complete_gates "$REPO_ROOT/scripts" "$P"
out=$(delta_run "$REPO_ROOT/scripts" "$P" --close); rc=$?
slot="$(active_json "$P" -r '.active_delta')"
n_closed="$(active_json "$P" -r '.closed | length')"
row_after="$(active_json "$P" -c '.hotfix_retros[0]')"
still_open="$(active_json "$P" -r '.hotfix_retros[0].closed_at == null')"
announced=n; printf '%s' "$out" | grep -qi 'write-up' && announced=y
names_id=n; printf '%s' "$out" | grep -qF 'DELTA-001' && names_id=y
carried="$(active_json "$P" -r '.closed[0].audit_row_at_open != null')"
if [ "$rc" -eq 0 ] && [ "$slot" = "null" ] && [ "$n_closed" = "1" ] \
   && [ "$still_open" = "true" ] && [ "$row_at_open" = "$row_after" ] \
   && [ "$announced" = y ] && [ "$names_id" = y ] && [ "$carried" = "true" ]; then
  pass "S1: closing the hotfix delta empties the slot ($slot) and grows the audit tail to $n_closed — and the retro row is byte-identical to what open wrote ($row_after), still open. The close ANNOUNCES the outstanding write-up and names the delta. The loan is not forgiven by being repaid-looking; the audit row is carried onto the closed record ($carried)"
else
  fail_ "S1" "rc=$rc (expect 0); slot=$slot (expect null); closed length=$n_closed (expect 1); retro still open=$still_open (expect true); row at open=$row_at_open row after close=$row_after (must MATCH); close announced the debt=$announced names the id=$names_id (both expect y); audit stamp carried onto the closed row=$carried (expect true); output:\n$out"
fi
rm -rf "$T"

# ── S2: the bind is on the LEDGER ROW, and it fails CLOSED  [KILLS m6] ─────
# `retro_review` is satisfied by the OBLIGATION being on the record — that is
# what §7.2 means by "retro_review IS that close review, arriving late and
# collateralised by the §9.2 release refusal". So the close proceeds while the
# retro is open (S1) and REFUSES when the row is gone: a hotfix whose obligation
# has been erased has nothing collateralising it, and closing it would let the
# loan disappear from the record entirely.
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
open_hotfix "$REPO_ROOT/scripts" "$P" checkout
complete_gates "$REPO_ROOT/scripts" "$P"
seam "$REPO_ROOT/scripts" "$P" --delta-state-update '.hotfix_retros = []' >/dev/null 2>&1
before="$(_md5file "$P/.claude/delta-state.json")"
out=$(delta_run "$REPO_ROOT/scripts" "$P" --close); rc=$?
after="$(_md5file "$P/.claude/delta-state.json")"
names=n; printf '%s' "$out" | grep -qF 'retro_review' && names=y
n_closed="$(active_json "$P" -r '.closed | length')"
if [ "$rc" -eq 7 ] && [ "$names" = y ] && [ "$before" = "$after" ] && [ "$n_closed" = "0" ]; then
  pass "S2: with the ledger row erased the close is REFUSED (rc $rc) naming retro_review, the record is byte-identical and the audit tail is still empty — the gate is bound to the obligation, and an obligation nobody is holding fails CLOSED"
else
  fail_ "S2" "rc=$rc (expect 7); names retro_review=$names; bytes $before -> $after (must MATCH); closed length=$n_closed (expect 0); output:\n$out"
fi
rm -rf "$T"

# ── S3: retro_review is not attestable ─────────────────────────────────────
# §7.2 names the exact failure this prevents: letting a hotfix "satisfy
# close_review at ship time and make the retro optional — which is precisely the
# loan going unrepaid". A tick-box would be that. So the surface refuses, and
# points at the one thing that does repay it.
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
open_hotfix "$REPO_ROOT/scripts" "$P" checkout
before="$(_md5file "$P/.claude/delta-state.json")"
out=$(delta_run "$REPO_ROOT/scripts" "$P" --complete-gate retro_review); rc=$?
after="$(_md5file "$P/.claude/delta-state.json")"
done_list="$(active_json "$P" -c '.active_delta.gates_completed')"
points=n; printf '%s' "$out" | grep -qF -- '--retro' && points=y
if [ "$rc" -eq 2 ] && [ "$before" = "$after" ] && [ "$points" = y ] \
   && [ "$done_list" = '["audit_row_at_open"]' ]; then
  pass "S3: --complete-gate retro_review is refused (rc $rc) and points the operator at --retro; the record is byte-identical and gates_completed is unchanged ($done_list). The loan cannot be repaid by ticking a box"
else
  fail_ "S3" "rc=$rc (expect 2); bytes $before -> $after (must MATCH); refusal points at --retro=$points (expect y); gates_completed=$done_list (expect [\"audit_row_at_open\"]); output:\n$out"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T — --retro: filing the write-up ==="
# ════════════════════════════════════════════════════════════════════════════

# ── T1: closes EXACTLY one retro, bounded, one write ───────────────────────
# Two shipped hotfixes, so "exactly one" is observable rather than trivially
# true. The residue is bounded by stripping precisely the two fields the write
# is allowed to touch from BOTH documents and requiring the remainders to be
# equal — the same instrument WP4's N2 uses on the ratchet record.
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
ship_hotfix "$REPO_ROOT/scripts" "$P" checkout
ship_hotfix "$REPO_ROOT/scripts" "$P" payments
n_open_before="$(active_json "$P" -r '[.hotfix_retros[] | select(.closed_at == null)] | length')"
snapshot="$(active_json "$P" -c '.')"
files_before="$(tree_manifest "$P" | grep -v 'delta-state.json' || true)"
out=$(delta_run "$REPO_ROOT/scripts" "$P" --retro DELTA-001 --record "the payment gateway timed out; we now retry twice and alert on the second failure"); rc=$?
files_after="$(tree_manifest "$P" | grep -v 'delta-state.json' || true)"
now_json="$(active_json "$P" -c '.')"
n_open_after="$(active_json "$P" -r '[.hotfix_retros[] | select(.closed_at == null)] | length')"
first_closed="$(active_json "$P" -r '.hotfix_retros[0].closed_at != null')"
second_open="$(active_json "$P" -r '.hotfix_retros[1].closed_at == null')"
recorded="$(active_json "$P" -r '.hotfix_retros[0].record.value')"
confined=$(jq -n --argjson a "$snapshot" --argjson b "$now_json" '
    ($a | .hotfix_retros |= map(del(.closed_at) | del(.record)))
 == ($b | .hotfix_retros |= map(del(.closed_at) | del(.record)))' 2>/dev/null)
confined="${confined:-READ-FAILED}"
if [ "$rc" -eq 0 ] && [ "$n_open_before" = "2" ] && [ "$n_open_after" = "1" ] \
   && [ "$first_closed" = "true" ] && [ "$second_open" = "true" ] \
   && [ "$confined" = "true" ] && [ "$files_before" = "$files_after" ] \
   && [ "$recorded" = "the payment gateway timed out; we now retry twice and alert on the second failure" ]; then
  pass "T1: --retro files EXACTLY one write-up — $n_open_before open before, $n_open_after after; DELTA-001 is closed and DELTA-002 untouched; the substance is on the record verbatim; and the residue is bounded to those rows' closed_at and record with no other file in the tree moved"
else
  fail_ "T1" "rc=$rc (expect 0); open before=$n_open_before (expect 2) after=$n_open_after (expect 1); first closed=$first_closed second still open=$second_open (both expect true); change confined to closed_at+record=$confined (expect true); other files moved=$([ "$files_before" = "$files_after" ] && echo n || echo y) (expect n); recorded='$recorded'; output:\n$out"
fi
rm -rf "$T"

# ── T2: a second --retro on the same id is refused  [KILLS m4] ─────────────
# WRITE-ONCE, for the same reason `shipped_in` is (§7.1): a second write-up
# claiming the same incident is a bug worth stopping, and overwriting the first
# would destroy the only record of what was decided at the time.
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
ship_hotfix "$REPO_ROOT/scripts" "$P" checkout
delta_run "$REPO_ROOT/scripts" "$P" --retro DELTA-001 --record "first write-up" >/dev/null 2>&1; rc_first=$?
before="$(_md5file "$P/.claude/delta-state.json")"
out=$(delta_run "$REPO_ROOT/scripts" "$P" --retro DELTA-001 --record "second write-up"); rc_second=$?
after="$(_md5file "$P/.claude/delta-state.json")"
kept="$(active_json "$P" -r '.hotfix_retros[0].record.value')"
if [ "$rc_first" -eq 0 ] && [ "$rc_second" -eq 12 ] && [ "$before" = "$after" ] \
   && [ "$kept" = "first write-up" ]; then
  pass "T2: the first --retro files (rc $rc_first) and a second on the same id is refused (rc $rc_second) — the record is byte-identical and still holds '$kept'. The write-up is write-once"
else
  fail_ "T2" "first rc=$rc_first (expect 0); second rc=$rc_second (expect 12); bytes $before -> $after (must MATCH); record now='$kept' (expect 'first write-up'); output:\n$out"
fi
rm -rf "$T"

# ── T3: an unknown id (11) and a missing record (2) ────────────────────────
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
ship_hotfix "$REPO_ROOT/scripts" "$P" checkout
out_u=$(delta_run "$REPO_ROOT/scripts" "$P" --retro DELTA-777 --record "never happened"); rc_unknown=$?
out_r=$(delta_run "$REPO_ROOT/scripts" "$P" --retro DELTA-001); rc_norecord=$?
out_n=$(delta_run "$REPO_ROOT/scripts" "$P" --retro DELTA-001 --record ""); rc_empty=$?
still_open="$(active_json "$P" -r '.hotfix_retros[0].closed_at == null')"
if [ "$rc_unknown" -eq 11 ] && [ "$rc_norecord" -eq 2 ] && [ "$rc_empty" -eq 2 ] \
   && [ "$still_open" = "true" ]; then
  pass "T3: an id nothing on the record carries is refused (rc $rc_unknown) and a write-up with no substance is an invocation error whether the flag is absent (rc $rc_norecord) or empty (rc $rc_empty) — the real retro is untouched"
else
  fail_ "T3" "unknown id rc=$rc_unknown (expect 11); missing --record rc=$rc_norecord (expect 2); empty --record rc=$rc_empty (expect 2); the real retro is still open=$still_open (expect true); outputs:\n$out_u\n$out_r\n$out_n"
fi
rm -rf "$T"

# ── T4: the record contract, honestly kinded ───────────────────────────────
# "State your contract and keep it honest about which it is." A value that names
# a file THAT EXISTS is recorded as a file; anything else is recorded as the
# operator's own summary. The framework never claims to have read a write-up it
# cannot find — which is why a path that does not resolve is stored as
# `attested` and SAID to be, rather than filed as though a document existed.
T=$(mktemp -d)
Pf="$T/file"; mk_proj "$Pf" 4
ship_hotfix "$REPO_ROOT/scripts" "$Pf" checkout
mkdir -p "$Pf/docs/incidents"
printf '# 2026-08-03 checkout\n\nWhat happened.\n' > "$Pf/docs/incidents/2026-08-03-checkout.md"
out_f=$(delta_run "$REPO_ROOT/scripts" "$Pf" --retro DELTA-001 --record docs/incidents/2026-08-03-checkout.md); rc_f=$?
kind_f="$(active_json "$Pf" -r '.hotfix_retros[0].record.kind')"
val_f="$(active_json "$Pf" -r '.hotfix_retros[0].record.value')"
Pa="$T/attested"; mk_proj "$Pa" 4
ship_hotfix "$REPO_ROOT/scripts" "$Pa" checkout
out_a=$(delta_run "$REPO_ROOT/scripts" "$Pa" --retro DELTA-001 --record docs/incidents/never-written.md); rc_a=$?
kind_a="$(active_json "$Pa" -r '.hotfix_retros[0].record.kind')"
says_which=n; printf '%s' "$out_a" | grep -qi 'could not find\|no file' && says_which=y
if [ "$rc_f" -eq 0 ] && [ "$kind_f" = "file" ] && [ "$val_f" = "docs/incidents/2026-08-03-checkout.md" ] \
   && [ "$rc_a" -eq 0 ] && [ "$kind_a" = "attested" ] && [ "$says_which" = y ]; then
  pass "T4: a --record naming a file that EXISTS is recorded as kind '$kind_f' pointing at $val_f; a --record naming one that does not is recorded as kind '$kind_a' and the transcript SAYS no such file was found ($says_which) — the framework never files a document it did not see"
else
  fail_ "T4" "existing-file rc=$rc_f kind=$kind_f (expect file) value=$val_f; missing-file rc=$rc_a kind=$kind_a (expect attested) transcript says so=$says_which (expect y); outputs:\n$out_f\n$out_a"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== O — overdue arithmetic (scripts/lib/delta-cadence.sh) ==="
# ════════════════════════════════════════════════════════════════════════════

# ── O1: 2 days is not overdue at 3; 4 days is; 7 makes 4 current ───────────
# The brief's own scenario. Each fixture opens under the policy it is testing,
# so the WINDOW is the product's; the test only ages the row, moving shipped_at
# and due_by together so the interval it computed is preserved exactly.
T=$(mktemp -d)
o1_ok=y; o1_detail=""
_o1() {
  local name="$1" policy="$2" age="$3" want="$4" P doc rc
  P="$T/$name"; mk_proj "$P" 4
  [ -n "$policy" ] && write_policy "$P" "$policy"
  ship_hotfix "$REPO_ROOT/scripts" "$P" checkout
  age_retro "$REPO_ROOT/scripts" "$P" DELTA-001 "$age"
  doc="$(active_json "$P" -c '.')"
  rc=0; cad "$REPO_ROOT/scripts" delta_retro_overdue "$doc" DELTA-001 >/dev/null 2>&1 || rc=$?
  o1_detail="$o1_detail [$name=rc$rc]"
  [ "$rc" -eq "$want" ] || o1_ok=n
}
_o1 "default-2days" "" 2 1
_o1 "default-4days" "" 4 0
_o1 "retuned7-4days" '{"schemaVersion":1,"classes":{"hotfix":{"gates":["ledger_row","audit_row_at_open","retro_review","changelog"],"retro_due_days":7}}}' 4 1
if [ "$o1_ok" = y ]; then
  pass "O1: at the framework's 3-day window a 2-day-old retro is not yet due (rc 1) and a 4-day-old one is OVERDUE (rc 0); a project that retunes the window to 7 finds the same 4-day-old retro current again —$o1_detail"
else
  fail_ "O1" "expected rc 1 / 0 / 1 in order (0 = overdue); got:$o1_detail"
fi
rm -rf "$T"

# ── O2: AN UNREADABLE due_by IS OVERDUE  [KILLS m3] ────────────────────────
# BL-213's fail-open class, refused. §14-V13 records the sibling defect: today
# check-maintenance.sh prints "All maintenance cadences current" at rc 0 for a
# date it could not read. The fixture's date is `2026-13-45` — month 13, day 45 —
# which NEITHER `date -d` nor `date -j -f` accepts, so this is the real parser
# failing and not a mocked one. ASSERTED ON THE EXIT CODE, never on the text.
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
ship_hotfix "$REPO_ROOT/scripts" "$P" checkout
seam "$REPO_ROOT/scripts" "$P" --delta-state-update '.hotfix_retros[0].due_by = "2026-13-45"' >/dev/null 2>&1
stored="$(active_json "$P" -r '.hotfix_retros[0].due_by')"
doc="$(active_json "$P" -c '.')"
rc_one=0; cad "$REPO_ROOT/scripts" delta_retro_overdue "$doc" DELTA-001 >/dev/null 2>&1 || rc_one=$?
rc_any=0; cad "$REPO_ROOT/scripts" delta_any_overdue_retro "$doc" >/dev/null 2>&1 || rc_any=$?
state="$(cad "$REPO_ROOT/scripts" delta_retro_rows "$doc" 2>/dev/null | awk -F'\t' '{ if (NR == 1) s = $3 } END { print s }')"
# And an ABSENT due_by is the same class of unreadable, not a free pass.
seam "$REPO_ROOT/scripts" "$P" --delta-state-update 'del(.hotfix_retros[0].due_by)' >/dev/null 2>&1
doc2="$(active_json "$P" -c '.')"
rc_absent=0; cad "$REPO_ROOT/scripts" delta_retro_overdue "$doc2" DELTA-001 >/dev/null 2>&1 || rc_absent=$?
if [ "$stored" = "2026-13-45" ] && [ "$rc_one" -eq 0 ] && [ "$rc_any" -eq 0 ] \
   && [ "$state" = "undetermined" ] && [ "$rc_absent" -eq 0 ]; then
  pass "O2: a due_by neither parser can read ($stored) is OVERDUE (rc $rc_one) and not silently current — the ledger predicate agrees (rc $rc_any), the row renders as '$state' rather than as a date, and an ABSENT due_by is the same refusal (rc $rc_absent). This is BL-213's fail-open class, closed"
else
  fail_ "O2" "stored due_by='$stored'; delta_retro_overdue rc=$rc_one (expect 0 = OVERDUE); delta_any_overdue_retro rc=$rc_any (expect 0); rendered state='$state' (expect undetermined); absent due_by rc=$rc_absent (expect 0)"
fi
rm -rf "$T"

# ── O3: the whole-ledger predicates, in all four states ────────────────────
# The interface §9.2's second refusal is built on: `cut-release.sh` refuses on
# ANY open retro, and the cadence nag arm reads the overdue half. Both are
# asserted here so WP7 can build against a pinned contract.
T=$(mktemp -d)
o3_ok=y; o3_detail=""
_o3() {
  local name="$1" want_open="$2" want_overdue="$3" P="$4" doc ro rv
  doc="$(active_json "$P" -c '.')"
  ro=0; cad "$REPO_ROOT/scripts" delta_any_open_retro "$doc" >/dev/null 2>&1 || ro=$?
  rv=0; cad "$REPO_ROOT/scripts" delta_any_overdue_retro "$doc" >/dev/null 2>&1 || rv=$?
  o3_detail="$o3_detail [$name open=$ro overdue=$rv]"
  [ "$ro" -eq "$want_open" ] || o3_ok=n
  [ "$rv" -eq "$want_overdue" ] || o3_ok=n
}
Pn="$T/none"; mk_proj "$Pn" 4
delta_run "$REPO_ROOT/scripts" "$Pn" --open --describe "the CSV export crashes on unicode" --confirm >/dev/null 2>&1
_o3 "empty-ledger" 1 1 "$Pn"
Pc="$T/current"; mk_proj "$Pc" 4
ship_hotfix "$REPO_ROOT/scripts" "$Pc" checkout
_o3 "one-open-current" 0 1 "$Pc"
Po="$T/overdue"; mk_proj "$Po" 4
ship_hotfix "$REPO_ROOT/scripts" "$Po" checkout
age_retro "$REPO_ROOT/scripts" "$Po" DELTA-001 5
_o3 "one-open-overdue" 0 0 "$Po"
delta_run "$REPO_ROOT/scripts" "$Po" --retro DELTA-001 --record "filed" >/dev/null 2>&1
_o3 "all-filed" 1 1 "$Po"
if [ "$o3_ok" = y ]; then
  pass "O3: the whole-ledger predicates answer the four states WP7 needs (0 = yes, 1 = no) —$o3_detail — including the one that matters most: filing the write-up on an OVERDUE retro clears both"
else
  fail_ "O3" "expected open/overdue of 1,1 then 0,1 then 0,0 then 1,1; got:$o3_detail"
fi
rm -rf "$T"

# ── O4: the parse helper ───────────────────────────────────────────────────
# GNU-first `date -d`, BSD `date -j -f` fallback — the two spellings this repo
# has to support, each of which REJECTS the other's input, so the order is safe
# in both directions. Garbage returns rc 1 AND PRINTS NOTHING: a helper that
# printed a stale value on failure would let a caller that ignored rc read it as
# a date. And a bare `YYYY-MM-DD` is normalised to midnight UTC before either
# parser sees it, because BSD's `-j -f` fills unspecified fields FROM NOW — so
# the un-normalised spelling would make the same date parse differently every
# time it was read.
T=$(mktemp -d)
o4_ok=y; o4_detail=""
e_iso="$(cad "$REPO_ROOT/scripts" delta_cadence_epoch "2026-08-03T00:00:00Z" 2>/dev/null)" || e_iso="ERR"
e_bare="$(cad "$REPO_ROOT/scripts" delta_cadence_epoch "2026-08-03" 2>/dev/null)" || e_bare="ERR"
rc_bad=0; out_bad="$(cad "$REPO_ROOT/scripts" delta_cadence_epoch "2026-13-45" 2>/dev/null)" || rc_bad=$?
rc_junk=0; cad "$REPO_ROOT/scripts" delta_cadence_epoch "banana" >/dev/null 2>&1 || rc_junk=$?
rc_empty=0; cad "$REPO_ROOT/scripts" delta_cadence_epoch "" >/dev/null 2>&1 || rc_empty=$?
round="$(cad "$REPO_ROOT/scripts" delta_cadence_stamp "$e_iso" 2>/dev/null)" || round="ERR"
plus3="$(cad "$REPO_ROOT/scripts" delta_cadence_due_by "2026-08-03T00:00:00Z" 3 2>/dev/null)" || plus3="ERR"
[ "$e_iso" = "$e_bare" ] || { o4_ok=n; o4_detail="$o4_detail(BARE DATE NOT MIDNIGHT: iso=$e_iso bare=$e_bare)"; }
[ "$rc_bad" -ne 0 ] || { o4_ok=n; o4_detail="$o4_detail(2026-13-45 PARSED)"; }
[ -z "$out_bad" ] || { o4_ok=n; o4_detail="$o4_detail(GARBAGE PRINTED '$out_bad')"; }
[ "$rc_junk" -ne 0 ] || { o4_ok=n; o4_detail="$o4_detail(banana PARSED)"; }
[ "$rc_empty" -ne 0 ] || { o4_ok=n; o4_detail="$o4_detail(EMPTY PARSED)"; }
[ "$round" = "2026-08-03T00:00:00Z" ] || { o4_ok=n; o4_detail="$o4_detail(ROUND TRIP=$round)"; }
[ "$plus3" = "2026-08-06T00:00:00Z" ] || { o4_ok=n; o4_detail="$o4_detail(PLUS3=$plus3)"; }
if [ "$o4_ok" = y ]; then
  pass "O4: the parse helper reads full ISO and bare dates identically (both $e_iso — the bare form is normalised to midnight UTC, so BSD's fill-from-now can never leak in), round-trips through the formatter ($round), adds days ($plus3), and refuses 2026-13-45 / banana / empty with a non-zero code AND NO OUTPUT"
else
  fail_ "O4" "problems:$o4_detail (iso=$e_iso bare=$e_bare bad-rc=$rc_bad bad-out='$out_bad' junk-rc=$rc_junk empty-rc=$rc_empty round=$round plus3=$plus3)"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== V — --status renders open and overdue retros ==="
# ════════════════════════════════════════════════════════════════════════════

# ── V1: named when owed, in both branches, and absent when filed ───────────
# THE STRUCTURAL DISCRIMINATOR is the last arm: a suite that only asserted "the
# id appears" would pass for a --status that printed the whole ledger including
# everything already filed, which is the opposite of the surface's job.
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
ship_hotfix "$REPO_ROOT/scripts" "$P" checkout
out_none=$(delta_run "$REPO_ROOT/scripts" "$P" --status)
v_none=n; printf '%s' "$out_none" | grep -qF 'DELTA-001' && v_none=y
age_retro "$REPO_ROOT/scripts" "$P" DELTA-001 5
out_over=$(delta_run "$REPO_ROOT/scripts" "$P" --status)
v_over=n; printf '%s' "$out_over" | grep -qiE 'overdue|late' && v_over=y
# With a NEW delta open the retro block must still render — the ledger outlives
# the delta, so a surface that only showed it in the idle branch would hide it
# exactly when the operator is busy.
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "add dark mode" --confirm >/dev/null 2>&1
out_busy=$(delta_run "$REPO_ROOT/scripts" "$P" --status)
v_busy=n; printf '%s' "$out_busy" | grep -qF 'DELTA-001' && v_busy=y
v_new=n;  printf '%s' "$out_busy" | grep -qF 'DELTA-002' && v_new=y
# An unreadable date is named as unreadable, not rendered as a day count.
seam "$REPO_ROOT/scripts" "$P" --delta-state-update '.hotfix_retros[0].due_by = "2026-13-45"' >/dev/null 2>&1
out_bad=$(delta_run "$REPO_ROOT/scripts" "$P" --status)
v_bad=n; printf '%s' "$out_bad" | grep -qiE 'cannot be read|OVERDUE' && v_bad=y
# Filed: gone.
seam "$REPO_ROOT/scripts" "$P" --delta-state-update '.hotfix_retros[0].due_by = "2026-08-06T00:00:00Z"' >/dev/null 2>&1
delta_run "$REPO_ROOT/scripts" "$P" --retro DELTA-001 --record "filed" >/dev/null 2>&1
out_filed=$(delta_run "$REPO_ROOT/scripts" "$P" --status)
v_filed=n; printf '%s' "$out_filed" | grep -qF 'DELTA-001' && v_filed=y
if [ "$v_none" = y ] && [ "$v_over" = y ] && [ "$v_busy" = y ] && [ "$v_new" = y ] \
   && [ "$v_bad" = y ] && [ "$v_filed" = n ]; then
  pass "V1: --status names the outstanding write-up with nothing else open ($v_none), calls it overdue once it is ($v_over), still shows it while a DIFFERENT delta is open ($v_busy alongside $v_new), names an unreadable due date rather than rendering it as a day count ($v_bad) — and once filed it appears nowhere ($v_filed)"
else
  fail_ "V1" "idle-branch names it=$v_none; overdue named=$v_over; shown while another delta is open=$v_busy (new delta also shown=$v_new); unreadable date named=$v_bad; STILL SHOWN AFTER FILING=$v_filed (expect n); outputs:\n--- idle ---\n$out_none\n--- overdue ---\n$out_over\n--- busy ---\n$out_busy\n--- bad ---\n$out_bad\n--- filed ---\n$out_filed"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== N — refusal residue (the WP4 standard) ==="
# ════════════════════════════════════════════════════════════════════════════

# ── N1: every --retro refusal leaves the WHOLE TREE pristine ───────────────
# WP4's doctrine, inherited: a pure refusal leaves the tree byte-for-byte as it
# found it, and the instrument is a `find` over the whole tree with a per-file
# md5 — not `[ -e ]` on one expected filename, which cannot see a file nobody
# thought to look for. None of these refusals carries a raise, so unlike the
# close flow there is no bounded-residue arm here: the answer is zero, always.
T=$(mktemp -d)
n1_ok=y; n1_detail=""
_n1_run() {
  local name="$1" want="$2" P before after rc
  shift 2
  P="$T/$name"; mk_proj "$P" 4
  ship_hotfix "$REPO_ROOT/scripts" "$P" checkout
  # The already-filed arm needs a filed retro first; every other arm refuses on
  # the tree as shipped.
  case "$name" in
    already) delta_run "$REPO_ROOT/scripts" "$P" --retro DELTA-001 --record "first" >/dev/null 2>&1 ;;
  esac
  before="$(tree_manifest "$P")"
  delta_run "$REPO_ROOT/scripts" "$P" "$@" >/dev/null 2>&1; rc=$?
  after="$(tree_manifest "$P")"
  n1_detail="$n1_detail [$name=rc$rc]"
  [ "$rc" -eq "$want" ] || n1_ok=n
  [ "$before" = "$after" ] || { n1_ok=n; n1_detail="$n1_detail(TREE MOVED)"; }
}
_n1_run unknown-id 11 --retro DELTA-777 --record "x"
_n1_run no-record   2 --retro DELTA-001
_n1_run already    12 --retro DELTA-001 --record "second"
_n1_run no-id       2 --retro
if [ "$n1_ok" = y ]; then
  pass "N1: every --retro refusal —$n1_detail — leaves the whole tree byte-for-byte as it found it, asserted as a find-based manifest with a per-file md5"
else
  fail_ "N1" "expected rc 11 / 2 / 12 / 2 with an unchanged tree; got:$n1_detail"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== M — mutation proofs (each mutant is BUILT and RUN here) ==="
# ════════════════════════════════════════════════════════════════════════════

# ── m1: suppress the retro-row append  [L1 RED] ────────────────────────────
# THE DESIGN'S OWN MUTATION (§11-WP5): "suppress the retro-row append -> a
# hotfix ships with no retro obligation -> RED". The failure mode is entirely
# silent: the hotfix opens, ships and closes, every surface says the right
# thing, and nothing anywhere is ever going to ask for the write-up again.
T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"
_sed_inplace "$MT/scripts/delta.sh" '/# DELTA-OPEN-RETRO-APPEND$/s@.*@    filter="$filter"@'
rep="$(_mutation_report "$REPO_ROOT/scripts/delta.sh" "$MT/scripts/delta.sh" 'DELTA-OPEN-RETRO-APPEND$')"
sites="${rep%%|*}"; rest="${rep#*|}"; changed="${rest%%|*}"; nlines="${rest##*|}"
Pp="$T/pristine"; mk_proj "$Pp" 4
open_hotfix "$REPO_ROOT/scripts" "$Pp" checkout
pri_rows="$(active_json "$Pp" -r '.hotfix_retros | length')"
Pm="$T/mutant"; mk_proj "$Pm" 4
open_hotfix "$MT/scripts" "$Pm" checkout
mut_rows="$(active_json "$Pm" -r '.hotfix_retros | length')"
mut_open="$(active_json "$Pm" -r '.active_delta.id')"
complete_gates "$MT/scripts" "$Pm"
delta_run "$MT/scripts" "$Pm" --close >/dev/null 2>&1; mut_close_rc=$?
mut_doc="$(active_json "$Pm" -c '.')"
mut_any=0; cad "$MT/scripts" delta_any_open_retro "$mut_doc" >/dev/null 2>&1 || mut_any=$?
if [ "$sites" = "1" ] && [ "$changed" = y ] && [ "$nlines" -eq 2 ] \
   && [ "$pri_rows" = "1" ] && [ "$mut_rows" = "0" ] && [ "$mut_open" = "DELTA-001" ] \
   && [ "$mut_close_rc" -eq 7 ] && [ "$mut_any" -eq 1 ]; then
  pass "m1: with the retro-row append suppressed the hotfix still opens ($mut_open) but the ledger is EMPTY ($mut_rows rows, where the pristine tree writes $pri_rows). L1 goes RED. The residual damage is legible in this row too: the close then fails CLOSED (rc $mut_close_rc) because the bind has no obligation to find, and the whole-ledger predicate WP7 will call reports nothing owed (rc $mut_any) (marker sites=$sites, one line changed=$nlines/2)"
else
  fail_ "m1" "marker sites=$sites (expect 1); mutation applied=$changed (expect y); diff lines=$nlines (expect 2); PRISTINE ledger rows=$pri_rows (expect 1); MUTANT rows=$mut_rows (expect 0) open delta=$mut_open; mutant close rc=$mut_close_rc (expect 7); mutant any-open-retro rc=$mut_any (expect 1 = none owed)"
fi
rm -rf "$T"

# ── m2: make the close ALSO close the retro  [S1 RED] ──────────────────────
# THE LOAN-FORGIVENESS BUG, built and run. This is the one mutation that has to
# be caught, because it is the one that leaves every visible surface saying
# exactly the right things: the delta closes, the audit tail grows, --status is
# clean, and the debt has vanished. §5.2's "that is what makes the fast lane a
# loan rather than a leak" is precisely what this mutant deletes.
T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"
_sed_inplace "$MT/scripts/delta.sh" \
  '/# DELTA-CLOSE-ATOMIC-WRITE$/s@.*@  filter=".closed += [$row] | .active_delta = null | .hotfix_retros = [.hotfix_retros[] | .closed_at = \\"$now\\"]"@'
rep="$(_mutation_report "$REPO_ROOT/scripts/delta.sh" "$MT/scripts/delta.sh" 'DELTA-CLOSE-ATOMIC-WRITE$')"
sites="${rep%%|*}"; rest="${rep#*|}"; changed="${rest%%|*}"; nlines="${rest##*|}"
_m2_fixture() {
  local sd="$1" P="$2"
  mk_proj "$P" 4
  open_hotfix "$sd" "$P" checkout
  complete_gates "$sd" "$P"
}
Pp="$T/pristine"; _m2_fixture "$REPO_ROOT/scripts" "$Pp"
delta_run "$REPO_ROOT/scripts" "$Pp" --close >/dev/null 2>&1; pri_rc=$?
pri_open="$(active_json "$Pp" -r '.hotfix_retros[0].closed_at == null')"
pri_doc="$(active_json "$Pp" -c '.')"
pri_any=0; cad "$REPO_ROOT/scripts" delta_any_open_retro "$pri_doc" >/dev/null 2>&1 || pri_any=$?
Pm="$T/mutant"; _m2_fixture "$MT/scripts" "$Pm"
delta_run "$MT/scripts" "$Pm" --close >/dev/null 2>&1; mut_rc=$?
mut_open="$(active_json "$Pm" -r '.hotfix_retros[0].closed_at == null')"
mut_record="$(active_json "$Pm" -r '.hotfix_retros[0].record')"
mut_doc="$(active_json "$Pm" -c '.')"
mut_any=0; cad "$MT/scripts" delta_any_open_retro "$mut_doc" >/dev/null 2>&1 || mut_any=$?
if [ "$sites" = "1" ] && [ "$changed" = y ] && [ "$nlines" -eq 2 ] \
   && [ "$pri_rc" -eq 0 ] && [ "$pri_open" = "true" ] && [ "$pri_any" -eq 0 ] \
   && [ "$mut_rc" -eq 0 ] && [ "$mut_open" = "false" ] && [ "$mut_record" = "null" ] && [ "$mut_any" -eq 1 ]; then
  pass "m2: with the close ALSO closing the retro, the hotfix closes exactly as cleanly (rc $mut_rc) and the debt is GONE — the ledger row is marked filed with a record of $mut_record, and the predicate WP7's release refusal will call reports nothing owed (rc $mut_any) where the pristine tree reports one (rc $pri_any). S1 goes RED. This is the loan forgiven the instant it was taken out, with every surface still saying the right thing (marker sites=$sites, one line changed=$nlines/2)"
else
  fail_ "m2" "marker sites=$sites (expect 1); mutation applied=$changed (expect y); diff lines=$nlines (expect 2); PRISTINE rc=$pri_rc (expect 0) retro still open=$pri_open (expect true) any-open rc=$pri_any (expect 0); MUTANT rc=$mut_rc (expect 0) retro still open=$mut_open (expect false — the mutant closed it) record=$mut_record (expect null — filed with no substance) any-open rc=$mut_any (expect 1 = nothing owed)"
fi
rm -rf "$T"

# ── m3: neuter the fail-closed unparseable arm  [O2 RED] ───────────────────
# BL-213's class, executed. §11-WP6's own mutation for the sibling defect is
# "remove the new undetermined counter -> the unparseable fixture reports 'All
# maintenance cadences current' at rc=0 -> RED, and it must assert the EXIT
# CODE, not the printed text". Same discipline here: the assertion is the code.
T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"
_sed_inplace "$MT/scripts/lib/delta-cadence.sh" '/# DELTA-CADENCE-UNPARSEABLE$/s@.*@      state=current; days=999@'
rep="$(_mutation_report "$REPO_ROOT/scripts/lib/delta-cadence.sh" "$MT/scripts/lib/delta-cadence.sh" 'DELTA-CADENCE-UNPARSEABLE$')"
sites="${rep%%|*}"; rest="${rep#*|}"; changed="${rest%%|*}"; nlines="${rest##*|}"
P="$T/proj"; mk_proj "$P" 4
ship_hotfix "$REPO_ROOT/scripts" "$P" checkout
seam "$REPO_ROOT/scripts" "$P" --delta-state-update '.hotfix_retros[0].due_by = "2026-13-45"' >/dev/null 2>&1
doc="$(active_json "$P" -c '.')"
pri_rc=0; cad "$REPO_ROOT/scripts" delta_retro_overdue "$doc" DELTA-001 >/dev/null 2>&1 || pri_rc=$?
pri_any=0; cad "$REPO_ROOT/scripts" delta_any_overdue_retro "$doc" >/dev/null 2>&1 || pri_any=$?
mut_rc=0; cad "$MT/scripts" delta_retro_overdue "$doc" DELTA-001 >/dev/null 2>&1 || mut_rc=$?
mut_any=0; cad "$MT/scripts" delta_any_overdue_retro "$doc" >/dev/null 2>&1 || mut_any=$?
mut_state="$(cad "$MT/scripts" delta_retro_rows "$doc" 2>/dev/null | awk -F'\t' '{ if (NR == 1) s = $3 } END { print s }')"
if [ "$sites" = "1" ] && [ "$changed" = y ] && [ "$nlines" -eq 2 ] \
   && [ "$pri_rc" -eq 0 ] && [ "$pri_any" -eq 0 ] \
   && [ "$mut_rc" -eq 1 ] && [ "$mut_any" -eq 1 ] && [ "$mut_state" = "current" ]; then
  pass "m3: with the fail-closed arm neutered, a due_by of 2026-13-45 — a date NEITHER parser accepts — reads as '$mut_state' and the overdue predicates answer 'no' (rc $mut_rc / $mut_any) where the pristine tree answers 'yes' (rc $pri_rc / $pri_any). O2 goes RED, on the EXIT CODE and not on any printed word. This is BL-213's fail-open class re-opened in one line (marker sites=$sites, one line changed=$nlines/2)"
else
  fail_ "m3" "marker sites=$sites (expect 1); mutation applied=$changed (expect y); diff lines=$nlines (expect 2); PRISTINE overdue rc=$pri_rc any rc=$pri_any (both expect 0 = overdue); MUTANT overdue rc=$mut_rc any rc=$mut_any (both expect 1 = not overdue) state='$mut_state' (expect current)"
fi
rm -rf "$T"

# ── m4: neuter the write-once guard on --retro  [T2 RED] ───────────────────
# STRUCTURAL DISCRIMINATOR: the mutant does not merely stop refusing — it
# reports SUCCESS for a write-up it did not record, because the filter's own
# `closed_at == null` guard still skips the already-filed row. The operator is
# told their second write-up is on the record and it is not. That is the worse
# of the two failure modes and it is the one a rc-only assertion would miss.
T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"
_sed_inplace "$MT/scripts/delta.sh" '/# DELTA-RETRO-STATE-GUARD$/s@.*@  state="OPEN"@'
rep="$(_mutation_report "$REPO_ROOT/scripts/delta.sh" "$MT/scripts/delta.sh" 'DELTA-RETRO-STATE-GUARD$')"
sites="${rep%%|*}"; rest="${rep#*|}"; changed="${rest%%|*}"; nlines="${rest##*|}"
_m4_fixture() {
  local sd="$1" P="$2"
  mk_proj "$P" 4
  ship_hotfix "$sd" "$P" checkout
  delta_run "$sd" "$P" --retro DELTA-001 --record "first write-up" >/dev/null 2>&1
}
Pp="$T/pristine"; _m4_fixture "$REPO_ROOT/scripts" "$Pp"
delta_run "$REPO_ROOT/scripts" "$Pp" --retro DELTA-001 --record "second write-up" >/dev/null 2>&1; pri_rc=$?
Pm="$T/mutant"; _m4_fixture "$MT/scripts" "$Pm"
delta_run "$MT/scripts" "$Pm" --retro DELTA-001 --record "second write-up" >/dev/null 2>&1; mut_rc=$?
mut_kept="$(active_json "$Pm" -r '.hotfix_retros[0].record.value')"
mut_unknown=0
delta_run "$MT/scripts" "$Pm" --retro DELTA-777 --record "never happened" >/dev/null 2>&1 || mut_unknown=$?
if [ "$sites" = "1" ] && [ "$changed" = y ] && [ "$nlines" -eq 2 ] \
   && [ "$pri_rc" -eq 12 ] && [ "$mut_rc" -eq 0 ] && [ "$mut_kept" = "first write-up" ] \
   && [ "$mut_unknown" -eq 0 ]; then
  pass "m4: with the write-once guard neutered a second --retro on a filed retro reports SUCCESS (rc $mut_rc) while the record still holds '$mut_kept' — the operator is told their write-up is filed and it is not — and an id nothing carries also reports success (rc $mut_unknown) instead of refusing. T2 goes RED (marker sites=$sites, one line changed=$nlines/2)"
else
  fail_ "m4" "marker sites=$sites (expect 1); mutation applied=$changed (expect y); diff lines=$nlines (expect 2); PRISTINE second-file rc=$pri_rc (expect 12); MUTANT rc=$mut_rc (expect 0) record kept='$mut_kept' (expect 'first write-up' — the silent discard) unknown-id rc=$mut_unknown (expect 0)"
fi
rm -rf "$T"

# ── m5: hardcode the retro window  [L2 RED] ────────────────────────────────
T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"
_sed_inplace "$MT/scripts/delta.sh" '/# DELTA-OPEN-RETRO-DUE-DAYS$/s@.*@    days=3@'
rep="$(_mutation_report "$REPO_ROOT/scripts/delta.sh" "$MT/scripts/delta.sh" 'DELTA-OPEN-RETRO-DUE-DAYS$')"
sites="${rep%%|*}"; rest="${rep#*|}"; changed="${rest%%|*}"; nlines="${rest##*|}"
POL='{"schemaVersion":1,"classes":{"hotfix":{"gates":["ledger_row","audit_row_at_open","retro_review","changelog"],"retro_due_days":9}}}'
Pp="$T/pristine"; mk_proj "$Pp" 4; write_policy "$Pp" "$POL"
open_hotfix "$REPO_ROOT/scripts" "$Pp" checkout
pri_days="$(interval_days "$Pp" 0)"
Pm="$T/mutant"; mk_proj "$Pm" 4; write_policy "$Pm" "$POL"
open_hotfix "$MT/scripts" "$Pm" checkout
mut_days="$(interval_days "$Pm" 0)"
mut_policy="$(jq -r '.classes.hotfix.retro_due_days' "$Pm/.claude/delta-policy.json" 2>/dev/null)"
if [ "$sites" = "1" ] && [ "$changed" = y ] && [ "$nlines" -eq 2 ] \
   && [ "$pri_days" = "9" ] && [ "$mut_days" = "3" ] && [ "$mut_policy" = "9" ]; then
  pass "m5: with the policy read replaced by a literal, a project whose own file says $mut_policy days gets a $mut_days-day window anyway, where the pristine tree honours it ($pri_days). L2 goes RED — and the failure is silent: no error, no warning, just a deadline the project did not choose (marker sites=$sites, one line changed=$nlines/2)"
else
  fail_ "m5" "marker sites=$sites (expect 1); mutation applied=$changed (expect y); diff lines=$nlines (expect 2); PRISTINE interval=$pri_days (expect 9); MUTANT interval=$mut_days (expect 3) while the mutant's own policy file says $mut_policy (expect 9)"
fi
rm -rf "$T"

# ── m6: waive retro_review unconditionally  [S2 RED] ───────────────────────
# FRESH FIXTURE THAT REACHES THE GUARD: the ledger row must be erased first, or
# the bind is satisfied for the honest reason and the mutant looks pinned when
# it is not.
T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"
_sed_inplace "$MT/scripts/delta.sh" '/# DELTA-CLOSE-RETRO-BIND$/s@.*@    retro_state="open"@'
rep="$(_mutation_report "$REPO_ROOT/scripts/delta.sh" "$MT/scripts/delta.sh" 'DELTA-CLOSE-RETRO-BIND$')"
sites="${rep%%|*}"; rest="${rep#*|}"; changed="${rest%%|*}"; nlines="${rest##*|}"
_m6_fixture() {
  local sd="$1" P="$2"
  mk_proj "$P" 4
  open_hotfix "$sd" "$P" checkout
  complete_gates "$sd" "$P"
  seam "$sd" "$P" --delta-state-update '.hotfix_retros = []' >/dev/null 2>&1
}
Pp="$T/pristine"; _m6_fixture "$REPO_ROOT/scripts" "$Pp"
delta_run "$REPO_ROOT/scripts" "$Pp" --close >/dev/null 2>&1; pri_rc=$?
pri_closed="$(active_json "$Pp" -r '.closed | length')"
Pm="$T/mutant"; _m6_fixture "$MT/scripts" "$Pm"
delta_run "$MT/scripts" "$Pm" --close >/dev/null 2>&1; mut_rc=$?
mut_closed="$(active_json "$Pm" -r '.closed | length')"
mut_ledger="$(active_json "$Pm" -r '.hotfix_retros | length')"
mut_doc="$(active_json "$Pm" -c '.')"
mut_any=0; cad "$MT/scripts" delta_any_open_retro "$mut_doc" >/dev/null 2>&1 || mut_any=$?
if [ "$sites" = "1" ] && [ "$changed" = y ] && [ "$nlines" -eq 2 ] \
   && [ "$pri_rc" -eq 7 ] && [ "$pri_closed" = "0" ] \
   && [ "$mut_rc" -eq 0 ] && [ "$mut_closed" = "1" ] && [ "$mut_ledger" = "0" ] && [ "$mut_any" -eq 1 ]; then
  pass "m6: with retro_review waived unconditionally, a hotfix whose obligation has been erased closes clean (rc $mut_rc, $mut_closed row archived) over an EMPTY ledger ($mut_ledger rows, nothing owed: rc $mut_any) where the pristine tree fails CLOSED (rc $pri_rc, nothing archived). S2 goes RED — the gate would be satisfied by the class rather than by the obligation, and a hotfix could ship with no collateral at all (marker sites=$sites, one line changed=$nlines/2)"
else
  fail_ "m6" "marker sites=$sites (expect 1); mutation applied=$changed (expect y); diff lines=$nlines (expect 2); PRISTINE rc=$pri_rc (expect 7) closed=$pri_closed (expect 0); MUTANT rc=$mut_rc (expect 0) closed=$mut_closed (expect 1) ledger rows=$mut_ledger (expect 0) any-open rc=$mut_any (expect 1)"
fi
rm -rf "$T"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
