#!/usr/bin/env bash
# tests/test-delta-wp4-close-rubric.sh — Delta Track WP4.
#
# SPEC: docs/designs/2026-08-02-delta-track-v1.md §5.2 (the per-class gate
# table and its token vocabulary), §5.3 (the brief's done-observable section IS
# the close review's rubric — "the close gate reads the brief's criteria
# section and refuses an unchecked box"), §4.2 (the two honest limits: the
# close-time re-derivation RATCHETS and never lowers, and a raise APPENDS
# gates), §6.2 (the brief's five sections; done-observable is the rubric),
# §7.1 (gates_required / gates_completed, the append-only `closed` tail, the
# single-writer rule), §7.2 (every gate list and threshold is READ FROM
# POLICY), §11-WP4.
#
# (No `# BL-NNN-…` marker anywhere in the delta track on purpose: no backlog
# entry exists for this build and minting one would red
# scripts/lint-bl-markers.sh, whose first pass resolves every marker to a real
# `## BL-NNN:` entry. The design-doc path above is the citation, per the WP1,
# WP2 and WP3 precedent.)
#
# ═════════════════════════════════════════════════════════════════════════════
# EXIT CODES, NEVER LABELS
#
# Every assertion below reads a process EXIT CODE, a JSON value read back off
# disk, or a byte-level md5 / whole-tree manifest. None reads a printed
# [OK]/[WARN]/[FAIL] banner. CLAUDE.md's `[WARN]` trap is exactly that the label
# and the exit predicate can disagree. The close flow has SIX distinct refusal
# outcomes and they are told apart by their codes:
#
#     6   nothing is open to close
#     7   required gates are still outstanding
#     8   the brief's rubric has an unchecked (or unreadable) criterion
#     9   an unknown gate token — a configuration error, failing CLOSED
#    10   the close-time re-measurement RAISED an attribute and added
#         obligations, so the close refuses on the LARGER checklist
#
# Codes 7 and 9 are deliberately different, and U2 is the case that needs the
# difference: a project that retunes `attribute_toggles` to a token the
# framework has never heard of must get "you still owe this" (7) and never
# "this is not a gate" (9). A suite that asserted "the close was refused" could
# not tell those two apart, and the wrong one of them is a project locked out
# of closing its own deltas.
#
# ═════════════════════════════════════════════════════════════════════════════
# WHAT THIS SUITE PINS, AND WHICH MUTANT EACH ROW KILLS
#
#   C — THE PER-CLASS GATE REFUSAL (§5.2)
#     C1  a FEATURE with brief_review outstanding is refused (7), named  KILLS m5
#     C2  a FIX with repro_test_red_first outstanding is refused (7), named
#     C3  a close with nothing open is refused (6) and creates nothing
#     C4  every gate complete => the close proceeds (rc 0). Without this the
#         refusals could be a script that always refuses, which is not a gate
#
#   K — --complete-gate, AND ITS HONEST NOTE
#     K1  a listed token is recorded, idempotently; a token this delta does not
#         owe is an invocation error (2) that writes nothing; nothing open is 6
#     K2  the surface does not OVERCLAIM: it says the gate is ATTESTED and
#         names the two mechanical exceptions this WP actually makes real
#
#   W — THE ATOMIC CLOSE WRITE (§7.1, and carry-forward (a))
#     W1  ONE seam write: `closed` grows by exactly one AND the slot nulls,
#         with class / severity / closed_at / attributes / gates_completed
#         archived on the row                                            KILLS m3
#     W2  THE ID-REUSE PIN: the next open takes DELTA-002, because the closed
#         row is what `_next_id` reads. A close that nulls without appending
#         hands the NEXT delta the id of the one just closed
#     W3  the close is NOT era-guarded. §10.1 puts the era refusal at OPEN; an
#         open delta at phase < 4 is already the inconsistency validate.sh
#         reports, and closing it is the only way to restore the invariant
#
#   X — THE CLOSE-TIME RE-DERIVATION AND ITS RATCHET (§4.2)
#     X1  a delta opened small/feature-local whose REAL diff at close crosses
#         into evolution/core raises both attributes, APPENDS the newly toggled
#         gates, and refuses (10) naming them                            KILLS m1
#     X2  the ratchet is not a dead end: completing the new obligations (and
#         satisfying the brief the ratchet just demanded) closes the delta
#     X3  RATCHET DIRECTION: a shrunken diff does NOT lower a confirmed
#         attribute, and removes no gate
#
#   B — THE RUBRIC BIND (§5.3)
#     B1  a brief with one unchecked box refuses the close (8) and NAMES the
#         criterion                                                      KILLS m2
#     B2  all boxes checked => the close proceeds
#     B3  a class with no `brief` gate is unaffected — it closes with no
#         docs/deltas directory in the tree at all
#     B4  FAIL-CLOSED, four ways: no brief file; no Done-observable section;
#         a section with zero checkboxes; a malformed marker. A rubric that
#         cannot be read is not a rubric that passed
#
#   U — THE GATE-TOKEN VOCABULARY (§5.2)
#     U1  an unknown token in gates_required is a config error (9) even when it
#         is also marked complete — it fails CLOSED                      KILLS m4
#     U2  and the vocabulary is POLICY-DERIVED, not a hardcoded table: a project
#         that retunes attribute_toggles to `second_reviewer` gets 7, not 9,
#         and closes once it completes it
#
#   N — REFUSAL RESIDUE (the WP3 standard, inherited verbatim)
#     N1  every refused close leaves the tree EXACTLY as it found it — asserted
#         as a whole-tree `find` manifest with a per-file md5, not against one
#         expected filename
#
#   R — R-WP3-3: THE SEAM-LEVEL REPLACEMENT REFUSAL (carry-forward (b), taken)
#     R1  --delta-state-update REPLACING an open active_delta with a different
#         id is refused at the SEAM, file byte-identical                 KILLS m6
#     R2  and the atom refuses REPLACEMENT, not MUTATION: the same delta's
#         gates_completed append still writes. Without R2 the atom could be a
#         blanket non-null->non-null refusal, which would break --complete-gate
#         and the ratchet write — both of which are exactly that shape
#
# ═════════════════════════════════════════════════════════════════════════════
# COUNTERFACTUAL DISCIPLINE — how the mutations below are built
#
# Inherited from tests/test-delta-wp3-era-classify.sh and unchanged, because it
# is what makes a mutation proof a proof:
#
#   • ANCHORED SINGLE-SITE addresses. Every marker is pinned to END-OF-LINE
#     (`/# DELTA-CLOSE-RATCHET$/`), never a bare substring — WP2's suite records
#     what over-matching costs: an unanchored `/SHAPE-ATOM-CLOSED/` also matches
#     SHAPE-ATOM-CLOSED-ROWS and credits one RED to two atoms.
#   • THREE PROPERTIES ASSERTED BEFORE THE RESULT IS BELIEVED: the marker
#     resolves to EXACTLY ONE line in the pristine file; the mutant DIFFERS from
#     it; and EXACTLY ONE LINE changed (one `<` and one `>`).
#   • MODE-PRESERVING harness. `_sed_inplace` reads each file's mode and puts it
#     back; the obvious `chmod +x` spelling silently turns a sourced 0644 lib
#     into 0755 and the mode rides along in the next commit.
#   • FRESH-FIXTURE ISOLATION. Every mutation builds its own mktemp project, and
#     — this is the part that bites in a close flow — the fixture must reach the
#     guard under test. m2's brief-rubric fixture must have every gate COMPLETE,
#     or the outstanding-gates refusal fires two guards earlier and the mutant
#     looks pinned when it is not. m4's fixture must mark the unknown token
#     COMPLETE for the same reason.
#   • STRUCTURAL DISCRIMINATORS WHERE THE EXPECTED RESULT IS AN ABSENCE. Four of
#     the six mutants below expect "the refusal did not happen", which is the
#     same answer a fixture that never reached the guard would give. Each of
#     those rows therefore also asserts a POSITIVE consequence of the mutation
#     having landed — the closed row's attributes are still the SMALL ones while
#     the real diff in the same fixture measures evolution (m1); the brief in
#     the mutant's own tree still carries an unchecked box (m2); the next id is
#     REUSED (m3); the closed row's gates_completed lacks the gate that was
#     outstanding (m5) — and every one of them is measured against the PRISTINE
#     tree run on an identical fixture in the same case.
#
# ═════════════════════════════════════════════════════════════════════════════
# HERMETICITY: every fixture is a mktemp -d project carrying NO init.sh and NO
# templates/generated, so guard_not_in_framework sees a project and not the
# framework. Git fixtures configure an identity and unset GITHUB_BASE_REF. No
# remote is ever created; nothing reaches the network; nothing is written inside
# the checkout. bash-3.2 safe: no associative arrays, no ${var,,}, no ((x++)).
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
  echo "jq is required for tests/test-delta-wp4-close-rubric.sh" >&2
  exit 2
fi
if ! command -v git >/dev/null 2>&1; then
  echo "git is required for tests/test-delta-wp4-close-rubric.sh" >&2
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

# A REAL git project, so the close-time re-derivation runs against a real
# `git diff --name-only` / `--shortstat`. One tracked file under a path a
# project would plausibly call a risk surface, one that plainly is not.
mk_git_proj() {
  local d="$1" phase="$2"
  mk_proj "$d" "$phase"
  mkdir -p "$d/src/auth" "$d/src/ui"
  printf 'base\n' > "$d/src/auth/login.ts"
  printf 'base\n' > "$d/src/ui/theme.ts"
  ( cd "$d" && git init -q \
      && git config user.email t@t.local && git config user.name T \
      && unset GITHUB_BASE_REF && git add -A && git commit -q -m init ) >/dev/null 2>&1
}

# grow <file> <n> — append exactly n lines, so `git diff --shortstat` reports a
# KNOWN insertion count and the level bracket is a measurement, not a guess.
grow() {
  local f="$1" n="$2" i=1
  while [ "$i" -le "$n" ]; do printf 'added line %s\n' "$i" >> "$f"; i=$((i + 1)); done
}

write_policy() { printf '%s\n' "$2" > "$1/.claude/delta-policy.json"; }

# write_brief <project> <id> <slug> [done-observable lines…]
#   §6.2's five-section brief, rendered in the convention this WP parses and
#   WP8's template must match: checkbox rows under a `## Done-observable`
#   heading. The other four sections are present so the parser is proved to
#   SCOPE to the rubric rather than scanning the whole file — Must-not-change
#   below deliberately carries an unchecked box of its own.
write_brief() {
  local p="$1" id="$2" slug="$3" l
  shift 3
  mkdir -p "$p/docs/deltas"
  {
    printf '# %s — %s\n\n' "$id" "$slug"
    printf '## What\n\n- [ ] this box is not a criterion and must be ignored\n\n'
    printf '## Why\n\nA user asked for it.\n\n'
    printf '## Done-observable\n\n'
    for l in "$@"; do printf '%s\n' "$l"; done
    printf '\n## Must-not-change\n\n- [ ] nor is this one\n\n'
    printf '## Touched surfaces\n\nsrc/\n'
  } > "$p/docs/deltas/$id-$slug.md"
}

mk_scripts_tree() {
  mkdir -p "$1"
  cp -R "$REPO_ROOT/scripts" "$1/scripts"
}

# ── Runners ─────────────────────────────────────────────────────────────────

delta_run() {
  local sd="$1" p="$2"; shift 2
  ( cd "$p" && unset GITHUB_BASE_REF; bash "$sd/delta.sh" "$@" </dev/null 2>&1 )
}

seam() {
  local sd="$1" p="$2"; shift 2
  ( cd "$p" && unset GITHUB_BASE_REF; bash "$sd/process-checklist.sh" "$@" </dev/null 2>/dev/null )
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

# tree_files <project-dir> — every file in the tree, one per line, sorted.
# `.git/**` is excluded and that exclusion is not a convenience: `git diff` is
# allowed to refresh the index's stat cache, so `.git/index` can legitimately
# change bytes during a read-only measurement. Including it would make the
# residue assertion fail for a reason that has nothing to do with the close.
tree_files() {
  ( cd "$1" && find . -type f ! -path './.git/*' | LC_ALL=C sort )
}

# tree_manifest <project-dir> — every file in the tree with its md5. THE
# refusal-residue instrument: a refusal that says "nothing was closed" is a
# claim about the whole filesystem, and checking one expected filename cannot
# see a file nobody thought to look for.
tree_manifest() {
  local p="$1" f
  tree_files "$p" | while IFS= read -r f; do
    printf '%s  %s\n' "$(_md5file "$p/$f")" "$f"
  done
}

# ── Mutation harness (inherited from the WP2/WP3 suites) ────────────────────

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

echo "== tests/test-delta-wp4-close-rubric.sh =="
echo ""

# ════════════════════════════════════════════════════════════════════════════
echo "=== C — the per-class gate refusal (§5.2) ==="
# ════════════════════════════════════════════════════════════════════════════

# ── C1: a FEATURE with brief_review outstanding  [KILLS m5] ─────────────────
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "add dark mode" --class feature --slug dark-mode --confirm >/dev/null 2>&1
complete_gates "$REPO_ROOT/scripts" "$P" brief_review
before="$(_md5file "$P/.claude/delta-state.json")"
out=$(delta_run "$REPO_ROOT/scripts" "$P" --close); rc=$?
after="$(_md5file "$P/.claude/delta-state.json")"
names=n; printf '%s' "$out" | grep -qF 'brief_review' && names=y
still_open="$(active_json "$P" -r '.active_delta.id')"
if [ "$rc" -eq 7 ] && [ "$names" = y ] && [ "$before" = "$after" ] && [ "$still_open" = "DELTA-001" ]; then
  pass "C1: a feature whose brief_review is still outstanding cannot close (rc $rc), the refusal NAMES the outstanding gate, and the record is byte-identical afterwards — the delta is still open ($still_open)"
else
  fail_ "C1" "rc=$rc (expect 7); names the gate=$names; bytes before=$before after=$after (must MATCH); active id=$still_open (expect DELTA-001); output:\n$out"
fi
rm -rf "$T"

# ── C2: a FIX with repro_test_red_first outstanding ─────────────────────────
# The other §5.2 row, and a different token: the refusal reads the delta's OWN
# materialised list, it does not carry a per-class table of its own.
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "the CSV export crashes on unicode" --confirm >/dev/null 2>&1
complete_gates "$REPO_ROOT/scripts" "$P" repro_test_red_first
out=$(delta_run "$REPO_ROOT/scripts" "$P" --close); rc=$?
names=n; printf '%s' "$out" | grep -qF 'repro_test_red_first' && names=y
leaks=n; printf '%s' "$out" | grep -qF 'brief_review' && leaks=y
if [ "$rc" -eq 7 ] && [ "$names" = y ] && [ "$leaks" = n ]; then
  pass "C2: a fix whose repro_test_red_first is outstanding is refused (rc $rc) naming that token and no other — the outstanding set is gates_required minus gates_completed on THIS delta's row"
else
  fail_ "C2" "rc=$rc (expect 7); names repro_test_red_first=$names; mentions a gate this class does not owe=$leaks (expect n); output:\n$out"
fi
rm -rf "$T"

# ── C3: nothing open ────────────────────────────────────────────────────────
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
out=$(delta_run "$REPO_ROOT/scripts" "$P" --close); rc=$?
left="$( ( cd "$P" && find . -type f | LC_ALL=C sort ) | tr '\n' ' ')"
if [ "$rc" -eq 6 ] && [ "$left" = "./.claude/phase-state.json " ]; then
  pass "C3: --close with nothing open is refused (rc $rc) and creates nothing — the tree still holds exactly the one file it started with"
else
  fail_ "C3" "rc=$rc (expect 6); files after='$left' (expect exactly './.claude/phase-state.json ')"
fi
rm -rf "$T"

# ── C4: every gate complete => the close proceeds ───────────────────────────
# Without this the refusals above are consistent with a --close that always
# refuses, which is not a gate.
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "the CSV export crashes on unicode" --confirm >/dev/null 2>&1
complete_gates "$REPO_ROOT/scripts" "$P"
out=$(delta_run "$REPO_ROOT/scripts" "$P" --close); rc=$?
slot="$(active_json "$P" -r '.active_delta')"
n_closed="$(active_json "$P" -r '.closed | length')"
if [ "$rc" -eq 0 ] && [ "$slot" = "null" ] && [ "$n_closed" = "1" ]; then
  pass "C4: with every §5.2 gate attested the close proceeds (rc $rc), the slot empties and the audit tail grows to $n_closed row"
else
  fail_ "C4" "rc=$rc (expect 0); active_delta=$slot (expect null); closed length=$n_closed (expect 1); output:\n$out"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== K — --complete-gate, and its honest note ==="
# ════════════════════════════════════════════════════════════════════════════

# ── K1: record, idempotence, a gate this delta does not owe, nothing open ───
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
delta_run "$REPO_ROOT/scripts" "$P" --complete-gate ledger_row >/dev/null 2>&1; rc_none=$?
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "the CSV export crashes on unicode" --confirm >/dev/null 2>&1
delta_run "$REPO_ROOT/scripts" "$P" --complete-gate ledger_row >/dev/null 2>&1; rc_first=$?
delta_run "$REPO_ROOT/scripts" "$P" --complete-gate ledger_row >/dev/null 2>&1; rc_again=$?
done_once="$(active_json "$P" -c '[.active_delta.gates_completed[] | select(. == "ledger_row")] | length')"
before="$(_md5file "$P/.claude/delta-state.json")"
delta_run "$REPO_ROOT/scripts" "$P" --complete-gate build_loop >/dev/null 2>&1; rc_notowed=$?
after="$(_md5file "$P/.claude/delta-state.json")"
if [ "$rc_none" -eq 6 ] && [ "$rc_first" -eq 0 ] && [ "$rc_again" -eq 0 ] \
   && [ "$done_once" = "1" ] && [ "$rc_notowed" -eq 2 ] && [ "$before" = "$after" ]; then
  pass "K1: --complete-gate is refused with nothing open (rc $rc_none), records a listed token (rc $rc_first), is IDEMPOTENT (rc $rc_again, recorded $done_once time), and refuses a token this delta does not owe (rc $rc_notowed) without touching the record"
else
  fail_ "K1" "nothing-open rc=$rc_none (expect 6); first rc=$rc_first (expect 0); repeat rc=$rc_again (expect 0); times recorded=$done_once (expect 1); not-owed rc=$rc_notowed (expect 2); bytes $before -> $after (must MATCH)"
fi
rm -rf "$T"

# ── K2: the surface does not OVERCLAIM ──────────────────────────────────────
# §5.3 tiers the review honestly: the RUBRIC is mechanical, everything else is
# advisory. A --complete-gate that printed "verified" would be exactly the
# overclaim the design refuses to make.
#
# WHAT THIS ASSERTS, AND WHAT IT DELIBERATELY DOES NOT. It does not require any
# particular word — an earlier cut demanded the literal "attest" and was pinning
# its own prose, which §4.3's plain register can legitimately reword tomorrow.
# The two DURABLE properties are: (a) the surface never claims a check it does
# not perform, and (b) it names BOTH of the two things this WP does check
# mechanically — the brief's boxes and the close-time re-measurement — so a
# future edit cannot quietly drop one and leave the operator believing the
# remaining half is everything.
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "the CSV export crashes on unicode" --confirm >/dev/null 2>&1
out=$(delta_run "$REPO_ROOT/scripts" "$P" --complete-gate ledger_row)
help_out=$(delta_run "$REPO_ROOT/scripts" "$P" --help)
no_verify=y; printf '%s' "$out" | grep -qiE 'verified|we checked|checked for you|confirmed by the framework|guarantee' && no_verify=n
names_brief=n;  printf '%s' "$out" | grep -qi 'brief' && names_brief=y
names_close=n;  printf '%s' "$out" | grep -qi 'close' && names_close=y
help_close=n;   printf '%s' "$help_out" | grep -qF -- '--close' && help_close=y
help_gate=n;    printf '%s' "$help_out" | grep -qF -- '--complete-gate' && help_gate=y
help_honest=y;  printf '%s' "$help_out" | grep -qiE 'verified|we checked|checked for you|guarantee' && help_honest=n
if [ "$no_verify" = y ] && [ "$names_brief" = y ] && [ "$names_close" = y ] \
   && [ "$help_close" = y ] && [ "$help_gate" = y ] && [ "$help_honest" = y ]; then
  pass "K2: recording a gate claims no check the framework does not perform, and names BOTH mechanical exceptions (the brief's boxes and the close-time re-measurement); --help names both new surfaces and is free of the same overclaim"
else
  fail_ "K2" "free of a verification overclaim=$no_verify (expect y); names the brief check=$names_brief; names the close-time check=$names_close; help names --close=$help_close, --complete-gate=$help_gate, help free of overclaim=$help_honest; output:\n$out"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== W — the atomic close write (§7.1) and the id-reuse pin ==="
# ════════════════════════════════════════════════════════════════════════════

# ── W1/W2: ONE write; the tail grows by one as the slot empties  [KILLS m3] ─
# CARRY-FORWARD (a), the id-reuse hazard, stated as the thing it actually is:
# `_next_id` computes max(existing ids) + 1 over closed[] + hotfix_retros[] +
# active_delta. A close that empties the slot WITHOUT appending to closed erases
# the id from the record entirely — so the next open legitimately reuses it, and
# two different pieces of work end up sharing one identifier in the audit tail.
# The append and the null must therefore land in ONE seam write, and W2 is what
# makes the consequence observable rather than asserted.
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "the CSV export crashes on unicode" --confirm >/dev/null 2>&1
complete_gates "$REPO_ROOT/scripts" "$P"
delta_run "$REPO_ROOT/scripts" "$P" --close >/dev/null 2>&1; rc=$?
row="$(active_json "$P" -c '.closed[0]')"
# NOTE the unquoted `$(` on this assignment: bash 3.2 mis-parses a MULTI-LINE
# command substitution that carries nested double quotes when it sits inside an
# outer pair of them. `x=$( … )` is exactly as safe on the right-hand side of an
# assignment and parses; `x="$( … )"` is a syntax error before it is anything
# else. (Same reason the WP2 suite spells its multi-line jq reads this way.)
shape=$(printf '%s' "$row" | jq -r '
  [ (.id == "DELTA-001"),
    (.class == "fix"),
    (.severity == "SEV-2"),
    ((.closed_at | type) == "string"), ((.closed_at | length) > 0),
    (.shipped_in == null),
    (.attributes.risk == "feature-local"), (.attributes.level == "small"),
    ((.gates_completed | type) == "array"),
    ((.gates_completed | index("repro_test_red_first")) != null),
    ((.gates_completed | index("changelog")) != null) ] | all' 2>/dev/null)
shape="${shape:-READ-FAILED}"
slot="$(active_json "$P" -r '.active_delta')"
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "add dark mode" --confirm >/dev/null 2>&1
next_id="$(active_json "$P" -r '.active_delta.id')"
if [ "$rc" -eq 0 ] && [ "$shape" = "true" ] && [ "$slot" = "null" ] && [ "$next_id" = "DELTA-002" ]; then
  pass "W1/W2: the close appends a full audit row (class, severity, closed_at, shipped_in null, the ratcheted attributes and the archived gates_completed) AND empties the slot in one write; the NEXT open takes $next_id, so the id is not reused"
else
  fail_ "W1/W2" "rc=$rc (expect 0); closed row shape=$shape (expect true) row=$row; active_delta=$slot (expect null); next id=$next_id (expect DELTA-002)"
fi
rm -rf "$T"

# ── W3: the close is NOT era-guarded ────────────────────────────────────────
# §10.1 places the era refusal at OPEN, and only there. An `active_delta` at
# phase < 4 is the inconsistency scripts/validate.sh reports — and closing it is
# the only way to restore `active_delta != null => current_phase == 4`. A close
# that refused below phase 4 would strand the delta in the very state the
# invariant forbids, forever.
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "the CSV export crashes on unicode" --confirm >/dev/null 2>&1
complete_gates "$REPO_ROOT/scripts" "$P"
mk_proj "$P" 2
delta_run "$REPO_ROOT/scripts" "$P" --close >/dev/null 2>&1; rc=$?
slot="$(active_json "$P" -r '.active_delta')"
if [ "$rc" -eq 0 ] && [ "$slot" = "null" ]; then
  pass "W3: an open delta at phase 2 CAN be closed (rc $rc, slot now $slot) — the era refusal is at open only, so closing is the one path back to a consistent record"
else
  fail_ "W3" "rc=$rc (expect 0); active_delta=$slot (expect null) — a close refused below phase 4 would strand the delta in exactly the state §10.1 forbids"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== X — close-time re-derivation and the ratchet (§4.2) ==="
# ════════════════════════════════════════════════════════════════════════════

# ── X1: grown past both brackets => raise, append, refuse  [KILLS m1] ───────
# THE DESIGN'S OWN CASE (§11-WP4), built from a REAL diff: opened with an empty
# working tree (small, feature-local), then thirty lines land in a risk surface.
T=$(mktemp -d); P="$T/proj"; mk_git_proj "$P" 4
write_policy "$P" '{"schemaVersion":1,"risk_surfaces":["src/auth/**"],"size_thresholds":{"small":5,"significant":20}}'
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "token check is wrong" --class fix --slug token-check --confirm >/dev/null 2>&1
open_attrs="$(active_json "$P" -c '.active_delta.attributes | {risk, level}')"
complete_gates "$REPO_ROOT/scripts" "$P"
grow "$P/src/auth/login.ts" 30
files_before="$(tree_files "$P" | tr '\n' ' ')"
out=$(delta_run "$REPO_ROOT/scripts" "$P" --close); rc=$?
files_after="$(tree_files "$P" | tr '\n' ' ')"
close_attrs="$(active_json "$P" -c '.active_delta.attributes | {risk, level}')"
gates="$(active_json "$P" -c '.active_delta.gates_required')"
n_closed="$(active_json "$P" -r '.closed | length')"
names=n
printf '%s' "$out" | grep -qF 'brief_review' && printf '%s' "$out" | grep -qF 'brief' && names=y
if [ "$rc" -eq 10 ] \
   && [ "$open_attrs" = '{"risk":"feature-local","level":"small"}' ] \
   && [ "$close_attrs" = '{"risk":"core","level":"evolution"}' ] \
   && [ "$gates" = '["ledger_row","repro_test_red_first","close_review","changelog","brief_review","brief"]' ] \
   && [ "$n_closed" = "0" ] && [ "$names" = y ] && [ "$files_before" = "$files_after" ]; then
  pass "X1: a delta opened $open_attrs whose real diff at close measures $close_attrs raises BOTH attributes, appends the newly toggled gates ($gates) and refuses (rc $rc) naming them — the audit tail is still empty ($n_closed rows) and no file was created or removed"
else
  fail_ "X1" "rc=$rc (expect 10); at open=$open_attrs (expect feature-local/small); at close=$close_attrs (expect core/evolution); gates=$gates; closed length=$n_closed (expect 0); names the new obligations=$names; files before='$files_before' after='$files_after'"
fi
rm -rf "$T"

# ── X2: the ratchet is not a dead end ───────────────────────────────────────
# The appended gates include `brief`, which turns the rubric bind ON for a class
# that did not have it at open. Satisfying both closes the delta — and the
# closed row records the RAISED attributes, not the ones confirmed at open.
T=$(mktemp -d); P="$T/proj"; mk_git_proj "$P" 4
write_policy "$P" '{"schemaVersion":1,"risk_surfaces":["src/auth/**"],"size_thresholds":{"small":5,"significant":20}}'
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "token check is wrong" --class fix --slug token-check --confirm >/dev/null 2>&1
complete_gates "$REPO_ROOT/scripts" "$P"
grow "$P/src/auth/login.ts" 30
delta_run "$REPO_ROOT/scripts" "$P" --close >/dev/null 2>&1; rc_first=$?
write_brief "$P" DELTA-001 token-check '- [x] the token check rejects an expired token' '- [x] the regression test covers it'
complete_gates "$REPO_ROOT/scripts" "$P"
delta_run "$REPO_ROOT/scripts" "$P" --close >/dev/null 2>&1; rc_second=$?
row_attrs="$(active_json "$P" -c '.closed[0].attributes | {risk, level}')"
n_gates="$(active_json "$P" -r '.closed[0].gates_completed | length')"
slot="$(active_json "$P" -r '.active_delta')"
if [ "$rc_first" -eq 10 ] && [ "$rc_second" -eq 0 ] && [ "$slot" = "null" ] \
   && [ "$row_attrs" = '{"risk":"core","level":"evolution"}' ] && [ "$n_gates" = "6" ]; then
  pass "X2: after the ratchet refusal (rc $rc_first) the operator completes the two new obligations and satisfies the brief the ratchet demanded, and the close proceeds (rc $rc_second) recording the RAISED attributes $row_attrs and all $n_gates attested gates"
else
  fail_ "X2" "first close rc=$rc_first (expect 10); second rc=$rc_second (expect 0); active_delta=$slot (expect null); closed attributes=$row_attrs (expect core/evolution); archived gate count=$n_gates (expect 6)"
fi
rm -rf "$T"

# ── X3: RATCHET DIRECTION — a shrunken diff never lowers ────────────────────
# The operator raised risk to core at open; the real diff at close touches
# nothing sensitive and measures feature-local. §4.2 is explicit that the
# re-derivation "never lowers", so the confirmed value stands and the gate it
# toggled stays on the list.
T=$(mktemp -d); P="$T/proj"; mk_git_proj "$P" 4
write_policy "$P" '{"schemaVersion":1,"risk_surfaces":["src/auth/**"],"size_thresholds":{"small":5,"significant":20}}'
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "the theme toggle is wrong" --class fix --risk core --confirm >/dev/null 2>&1
gates_open="$(active_json "$P" -c '.active_delta.gates_required')"
complete_gates "$REPO_ROOT/scripts" "$P"
delta_run "$REPO_ROOT/scripts" "$P" --close >/dev/null 2>&1; rc=$?
row_risk="$(active_json "$P" -r '.closed[0].attributes.risk')"
row_gates="$(active_json "$P" -c '.closed[0].gates_completed')"
if [ "$rc" -eq 0 ] && [ "$row_risk" = "core" ] \
   && [ "$gates_open" = '["ledger_row","repro_test_red_first","close_review","changelog","brief_review"]' ] \
   && [ "$row_gates" = "$gates_open" ]; then
  pass "X3: a delta confirmed at risk=core whose close-time diff measures feature-local closes (rc $rc) STILL AT core — the re-derivation ratchets up only, and the brief_review the raise toggled on is still on the archived list"
else
  fail_ "X3" "rc=$rc (expect 0); closed attributes.risk=$row_risk (expect core — a lower would mean the ratchet runs both ways); gates at open=$gates_open; archived=$row_gates (must match)"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== B — the rubric bind: the brief's Done-observable section (§5.3) ==="
# ════════════════════════════════════════════════════════════════════════════

# ── B1: one unchecked box refuses the close and NAMES it  [KILLS m2] ───────
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "add dark mode" --class feature --slug dark-mode --confirm >/dev/null 2>&1
write_brief "$P" DELTA-001 dark-mode \
  '- [x] the settings screen offers a dark theme' \
  '- [ ] the choice survives a restart' \
  '- [x] the contrast ratio passes AA'
complete_gates "$REPO_ROOT/scripts" "$P"
before="$(_md5file "$P/.claude/delta-state.json")"
out=$(delta_run "$REPO_ROOT/scripts" "$P" --close); rc=$?
after="$(_md5file "$P/.claude/delta-state.json")"
names=n; printf '%s' "$out" | grep -qF 'the choice survives a restart' && names=y
leaks=n; printf '%s' "$out" | grep -qF 'must be ignored' && leaks=y
n_closed="$(active_json "$P" -r '.closed | length')"
if [ "$rc" -eq 8 ] && [ "$names" = y ] && [ "$leaks" = n ] && [ "$before" = "$after" ] && [ "$n_closed" = "0" ]; then
  pass "B1: a brief with one unchecked criterion refuses the close (rc $rc) and NAMES the criterion verbatim; the checkbox in another section is correctly ignored ($leaks), the record is byte-identical and the audit tail is still empty"
else
  fail_ "B1" "rc=$rc (expect 8); names the unchecked criterion=$names; scanned outside Done-observable=$leaks (expect n); bytes $before -> $after (must MATCH); closed length=$n_closed (expect 0); output:\n$out"
fi
rm -rf "$T"

# ── B2: all boxes checked => the close proceeds ────────────────────────────
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "add dark mode" --class feature --slug dark-mode --confirm >/dev/null 2>&1
write_brief "$P" DELTA-001 dark-mode \
  '- [x] the settings screen offers a dark theme' \
  '- [X] the choice survives a restart' \
  '- [x] the contrast ratio passes AA'
complete_gates "$REPO_ROOT/scripts" "$P"
out=$(delta_run "$REPO_ROOT/scripts" "$P" --close); rc=$?
n_closed="$(active_json "$P" -r '.closed | length')"
if [ "$rc" -eq 0 ] && [ "$n_closed" = "1" ]; then
  pass "B2: with every criterion checked (upper and lower case markers both accepted) the same feature closes (rc $rc) and the audit tail grows to $n_closed"
else
  fail_ "B2" "rc=$rc (expect 0); closed length=$n_closed (expect 1); output:\n$out"
fi
rm -rf "$T"

# ── B3: a class with no `brief` gate is unaffected ─────────────────────────
# Asserted in a tree with no docs/deltas directory AT ALL, so a rubric check
# that fired unconditionally could not possibly pass this case.
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "the CSV export crashes on unicode" --confirm >/dev/null 2>&1
complete_gates "$REPO_ROOT/scripts" "$P"
delta_run "$REPO_ROOT/scripts" "$P" --close >/dev/null 2>&1; rc=$?
had_dir=n; [ -d "$P/docs/deltas" ] && had_dir=y
n_closed="$(active_json "$P" -r '.closed | length')"
if [ "$rc" -eq 0 ] && [ "$had_dir" = n ] && [ "$n_closed" = "1" ]; then
  pass "B3: a fix carries no brief gate, so it closes (rc $rc) in a tree that has no docs/deltas directory at all (present=$had_dir) — the rubric bind is keyed on the gate, not on the class"
else
  fail_ "B3" "rc=$rc (expect 0); docs/deltas present=$had_dir (expect n); closed length=$n_closed (expect 1)"
fi
rm -rf "$T"

# ── B4: fail CLOSED, four ways ─────────────────────────────────────────────
# A rubric that cannot be READ is not a rubric that PASSED. Each arm gets its
# own fixture: sharing one would let an earlier arm's leftover brief satisfy a
# later one.
T=$(mktemp -d)
b4_detail=""; b4_ok=y
_b4() {
  local name="$1" rc P
  shift
  P="$T/$name"; mk_proj "$P" 4
  delta_run "$REPO_ROOT/scripts" "$P" --open --describe "add dark mode" --class feature --slug dark-mode --confirm >/dev/null 2>&1
  "$@" "$P"
  complete_gates "$REPO_ROOT/scripts" "$P"
  delta_run "$REPO_ROOT/scripts" "$P" --close >/dev/null 2>&1; rc=$?
  b4_detail="$b4_detail [$name=rc$rc]"
  [ "$rc" -eq 8 ] || b4_ok=n
}
_b4_nofile()   { :; }
_b4_nosection(){ mkdir -p "$1/docs/deltas"; printf '# DELTA-001\n\n## What\n\nSomething.\n' > "$1/docs/deltas/DELTA-001-dark-mode.md"; }
_b4_noboxes()  { mkdir -p "$1/docs/deltas"; printf '# DELTA-001\n\n## Done-observable\n\nIt should feel nicer.\n\n## Must-not-change\n\nx\n' > "$1/docs/deltas/DELTA-001-dark-mode.md"; }
_b4_malformed(){ write_brief "$1" DELTA-001 dark-mode '- [x] a real one' '- [?] a marker nobody defined'; }
# Two files claim the same id, and BOTH are fully checked — so a first-match
# implementation would close cleanly here and the arm would look like a
# formality. It is not: picking one of two silently means the close review ran
# against a document the operator may never have opened.
_b4_ambiguous(){ write_brief "$1" DELTA-001 dark-mode '- [x] all done'
                 write_brief "$1" DELTA-001 dark-theme '- [x] all done'; }
_b4 nofile    _b4_nofile
_b4 nosection _b4_nosection
_b4 noboxes   _b4_noboxes
_b4 malformed _b4_malformed
_b4 ambiguous _b4_ambiguous
if [ "$b4_ok" = y ]; then
  pass "B4: the rubric fails CLOSED five ways —$b4_detail — a missing brief, a brief with no Done-observable section, a section with no checkboxes at all, an undefined marker, and two briefs claiming the same delta (both fully checked, so first-match would have passed) are each a refusal, never a silent pass"
else
  fail_ "B4" "expected rc 8 from every arm; got:$b4_detail"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== U — the gate-token vocabulary (§5.2) ==="
# ════════════════════════════════════════════════════════════════════════════

# ── U1: an unknown token fails CLOSED  [KILLS m4] ──────────────────────────
# Marked COMPLETE as well as required, on purpose: otherwise the
# outstanding-gates refusal fires first and the vocabulary check is never
# reached, which is precisely the masking that makes a mutant look pinned.
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "the CSV export crashes on unicode" --confirm >/dev/null 2>&1
complete_gates "$REPO_ROOT/scripts" "$P"
seam "$REPO_ROOT/scripts" "$P" --delta-state-update \
  '.active_delta.gates_required += ["frobnicate"] | .active_delta.gates_completed += ["frobnicate"]' >/dev/null 2>&1
before="$(_md5file "$P/.claude/delta-state.json")"
out=$(delta_run "$REPO_ROOT/scripts" "$P" --close); rc=$?
after="$(_md5file "$P/.claude/delta-state.json")"
names=n; printf '%s' "$out" | grep -qF 'frobnicate' && names=y
n_closed="$(active_json "$P" -r '.closed | length')"
if [ "$rc" -eq 9 ] && [ "$names" = y ] && [ "$before" = "$after" ] && [ "$n_closed" = "0" ]; then
  pass "U1: a gate token that is in neither §5.2's table nor this project's policy is a CONFIGURATION error (rc $rc), named, refused even though it is marked complete, and nothing is written"
else
  fail_ "U1" "rc=$rc (expect 9); names the token=$names; bytes $before -> $after (must MATCH); closed length=$n_closed (expect 0); output:\n$out"
fi
rm -rf "$T"

# ── U2: the vocabulary is POLICY-DERIVED, not a hardcoded table ────────────
# WP3's G4 pins that a project may retune `attribute_toggles.risk_core` to a
# token of its own. A vocabulary check reading only §5.2's table would answer 9
# and lock that project out of ever closing a delta. The right answer is 7 —
# "you still owe this" — and then a clean close once it is attested.
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
write_policy "$P" '{"schemaVersion":1,"attribute_toggles":{"risk_core":["second_reviewer"],"level_evolution":["brief"]}}'
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "the export is broken" --class fix --risk core --confirm >/dev/null 2>&1
gates="$(active_json "$P" -c '.active_delta.gates_required')"
complete_gates "$REPO_ROOT/scripts" "$P" second_reviewer
out=$(delta_run "$REPO_ROOT/scripts" "$P" --close); rc_outstanding=$?
delta_run "$REPO_ROOT/scripts" "$P" --complete-gate second_reviewer >/dev/null 2>&1; rc_mark=$?
delta_run "$REPO_ROOT/scripts" "$P" --close >/dev/null 2>&1; rc_close=$?
n_closed="$(active_json "$P" -r '.closed | length')"
if [ "$gates" = '["ledger_row","repro_test_red_first","close_review","changelog","second_reviewer"]' ] \
   && [ "$rc_outstanding" -eq 7 ] && [ "$rc_mark" -eq 0 ] && [ "$rc_close" -eq 0 ] && [ "$n_closed" = "1" ]; then
  pass "U2: a project-defined gate token (second_reviewer, from its own attribute_toggles) is KNOWN — the close says 'still outstanding' (rc $rc_outstanding) and not 'unknown token' (9), --complete-gate accepts it (rc $rc_mark) and the delta then closes (rc $rc_close)"
else
  fail_ "U2" "gates=$gates; outstanding rc=$rc_outstanding (expect 7, NOT 9 — a 9 here means the vocabulary is a hardcoded table and the project is locked out); --complete-gate rc=$rc_mark (expect 0); close rc=$rc_close (expect 0); closed length=$n_closed (expect 1); output:\n$out"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== N — refusal residue: every refused close leaves the tree as found ==="
# ════════════════════════════════════════════════════════════════════════════

# The WP3 standard, applied to all five refusal shapes at once. `find` over the
# WHOLE tree with a per-file md5 — not `[ -e ]` on one expected filename, which
# cannot see a file nobody thought to look for. The ratchet refusal (10) is
# deliberately EXCLUDED from this list and gets its own honest treatment below:
# it is the one refusal that is SUPPOSED to record something.
T=$(mktemp -d)
n1_detail=""; n1_ok=y
_n1() {
  local name="$1" want="$2" P before after rc
  shift 2
  P="$T/$name"; mk_proj "$P" 4
  delta_run "$REPO_ROOT/scripts" "$P" --open --describe "add dark mode" --class feature --slug dark-mode --confirm >/dev/null 2>&1
  "$@" "$P"
  before="$(tree_manifest "$P")"
  delta_run "$REPO_ROOT/scripts" "$P" --close >/dev/null 2>&1; rc=$?
  after="$(tree_manifest "$P")"
  n1_detail="$n1_detail [$name=rc$rc]"
  [ "$rc" -eq "$want" ] || n1_ok=n
  [ "$before" = "$after" ] || { n1_ok=n; n1_detail="$n1_detail(TREE MOVED)"; }
}
_n1_outstanding() { complete_gates "$REPO_ROOT/scripts" "$1" brief_review; }
_n1_rubric()      { write_brief "$1" DELTA-001 dark-mode '- [ ] not done yet'; complete_gates "$REPO_ROOT/scripts" "$1"; }
_n1_unknown()     { complete_gates "$REPO_ROOT/scripts" "$1"
                    seam "$REPO_ROOT/scripts" "$1" --delta-state-update \
                      '.active_delta.gates_required += ["frobnicate"] | .active_delta.gates_completed += ["frobnicate"]' >/dev/null 2>&1; }
_n1 outstanding 7 _n1_outstanding
_n1 rubric      8 _n1_rubric
_n1 unknown     9 _n1_unknown
# The fifth shape needs no arrangement at all — and no open delta.
P="$T/nothing"; mk_proj "$P" 4
before="$(tree_manifest "$P")"
delta_run "$REPO_ROOT/scripts" "$P" --close >/dev/null 2>&1; rc=$?
after="$(tree_manifest "$P")"
n1_detail="$n1_detail [nothing-open=rc$rc]"
[ "$rc" -eq 6 ] || n1_ok=n
[ "$before" = "$after" ] || { n1_ok=n; n1_detail="$n1_detail(TREE MOVED)"; }
if [ "$n1_ok" = y ]; then
  pass "N1: every PURE refusal —$n1_detail — leaves the whole tree byte-for-byte as it found it, asserted as a find-based manifest with a per-file md5 and not against one expected filename"
else
  fail_ "N1" "expected rc 7/8/9/6 with an unchanged tree; got:$n1_detail"
fi
rm -rf "$T"

# ── N2: the ratchet refusal's residue is EXACTLY the ratchet record ────────
# Stated rather than smoothed. §4.2 requires the close-time raise to be RECORDED
# — "it never lowers", and a raise the operator is told about but that is not
# written would be re-derived and re-announced on every subsequent close. So the
# ratchet refusal is the ONE refusal that writes, and what it writes is bounded:
# the delta's own attributes and its gates_required, and nothing else anywhere.
T=$(mktemp -d); P="$T/proj"; mk_git_proj "$P" 4
write_policy "$P" '{"schemaVersion":1,"risk_surfaces":["src/auth/**"],"size_thresholds":{"small":5,"significant":20}}'
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "token check is wrong" --class fix --slug token-check --confirm >/dev/null 2>&1
complete_gates "$REPO_ROOT/scripts" "$P"
grow "$P/src/auth/login.ts" 30
before="$(tree_manifest "$P")"
snapshot="$(active_json "$P" -c '.')"
delta_run "$REPO_ROOT/scripts" "$P" --close >/dev/null 2>&1; rc=$?
after="$(tree_manifest "$P")"
# Which FILES moved — everything except the state file must be byte-identical.
b_others="$(printf '%s\n' "$before" | grep -v 'delta-state.json' || true)"
a_others="$(printf '%s\n' "$after"  | grep -v 'delta-state.json' || true)"
others_moved=n; [ "$b_others" = "$a_others" ] || others_moved=y
# And WITHIN the state file, nothing but the delta's own attributes and
# gates_required: strip exactly those three fields from both documents and the
# remainder must be equal.
now_json="$(active_json "$P" -c '.')"
confined=$(jq -n --argjson a "$snapshot" --argjson b "$now_json" '
    ($a | .active_delta |= (del(.attributes) | del(.gates_required) | del(.ratcheted_at)))
 == ($b | .active_delta |= (del(.attributes) | del(.gates_required) | del(.ratcheted_at)))' 2>/dev/null)
confined="${confined:-READ-FAILED}"
if [ "$rc" -eq 10 ] && [ "$others_moved" = n ] && [ "$confined" = "true" ] && [ "$before" != "$after" ]; then
  pass "N2: the ratchet refusal (rc $rc) is the ONE close refusal that records something, and its residue is bounded — no file outside .claude/delta-state.json moved, and inside it nothing but the delta's attributes and gates_required changed"
else
  fail_ "N2" "rc=$rc (expect 10); a file other than the state file moved=$others_moved (expect n); the state change is confined to attributes+gates_required=$confined (expect true); state file actually changed=$([ "$before" != "$after" ] && echo y || echo n) (expect y)"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== R — R-WP3-3: the seam refuses a crafted active_delta REPLACEMENT ==="
# ════════════════════════════════════════════════════════════════════════════

# CARRY-FORWARD (b), taken. WP2 recorded that the state layer accepts
# overwriting an OPEN active_delta and deferred the refusal to WP3's business
# layer — which delivered it in delta.sh. The residual R-WP3-3 named the hole
# that leaves: `--delta-state-update` is a general primitive, so a crafted
# filter still replaces the open delta AT THE SEAM, taking its gates_completed
# with it. This is the seam-level atom, and it is narrower than "refuse
# non-null -> non-null" on purpose (see R2).

# ── R1: a different id in the slot is refused  [KILLS m6] ──────────────────
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "the CSV export crashes on unicode" --confirm >/dev/null 2>&1
delta_run "$REPO_ROOT/scripts" "$P" --complete-gate ledger_row >/dev/null 2>&1
before="$(_md5file "$P/.claude/delta-state.json")"
seam "$REPO_ROOT/scripts" "$P" --delta-state-update \
  '.active_delta = {"id":"DELTA-002","slug":"stolen","class":"feature","gates_required":[],"gates_completed":[]}' >/dev/null 2>&1
rc=$?
after="$(_md5file "$P/.claude/delta-state.json")"
id="$(active_json "$P" -r '.active_delta.id')"
kept="$(active_json "$P" -c '.active_delta.gates_completed')"
if [ "$rc" -ne 0 ] && [ "$before" = "$after" ] && [ "$id" = "DELTA-001" ] && [ "$kept" = '["ledger_row"]' ]; then
  pass "R1: a crafted --delta-state-update that swaps a DIFFERENT delta into the open slot is refused at the SEAM (rc $rc), the file is byte-identical, and DELTA-001 keeps its completed-gate history ($kept)"
else
  fail_ "R1" "rc=$rc (expect non-zero); bytes $before -> $after (must MATCH); id now=$id (expect DELTA-001); gates_completed=$kept (expect [\"ledger_row\"])"
fi
rm -rf "$T"

# ── R2: it refuses REPLACEMENT, not MUTATION ───────────────────────────────
# The load-bearing half. A blanket non-null -> non-null refusal would have been
# two characters shorter and would break BOTH of this WP's own writes:
# --complete-gate appends to gates_completed and the ratchet raises attributes,
# and each of those is a non-null -> non-null write on the SAME delta. The atom
# keys on the ID, so the same delta may be mutated freely and only a swap is
# refused. Without this case the atom could tighten into that blanket form and
# the suite would stay green while the product stopped working.
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "the CSV export crashes on unicode" --confirm >/dev/null 2>&1
before="$(_md5file "$P/.claude/delta-state.json")"
seam "$REPO_ROOT/scripts" "$P" --delta-state-update \
  '.active_delta.gates_completed += ["ledger_row"] | .active_delta.attributes.level = "significant"' >/dev/null 2>&1
rc=$?
after="$(_md5file "$P/.claude/delta-state.json")"
lvl="$(active_json "$P" -r '.active_delta.attributes.level')"
# And the OTHER two legal transitions the atom must not touch.
seam "$REPO_ROOT/scripts" "$P" --delta-state-update \
  '.closed += [{"id": .active_delta.id, "class": "fix", "closed_at": "2026-08-03T00:00:00Z", "shipped_in": null}] | .active_delta = null' >/dev/null 2>&1
rc_null=$?
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "add dark mode" --confirm >/dev/null 2>&1; rc_reopen=$?
new_id="$(active_json "$P" -r '.active_delta.id')"
if [ "$rc" -eq 0 ] && [ "$before" != "$after" ] && [ "$lvl" = "significant" ] \
   && [ "$rc_null" -eq 0 ] && [ "$rc_reopen" -eq 0 ] && [ "$new_id" = "DELTA-002" ]; then
  pass "R2: the same delta's own row is still freely mutable through the seam (rc $rc, level now $lvl) — which is exactly the shape --complete-gate and the ratchet write use — and both non-null->null (rc $rc_null) and null->non-null (rc $rc_reopen, $new_id) still pass. The atom refuses a SWAP, not a write"
else
  fail_ "R2" "same-id mutation rc=$rc (expect 0); bytes $before -> $after (must DIFFER); level=$lvl (expect significant); close-to-null rc=$rc_null (expect 0); reopen rc=$rc_reopen (expect 0); new id=$new_id (expect DELTA-002)"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== M — mutation proofs (each mutant is BUILT and RUN here) ==="
# ════════════════════════════════════════════════════════════════════════════

# ── m1: drop the close-time re-derivation  [X1 RED] ────────────────────────
# THE DESIGN'S OWN MUTATION (§11-WP4): "drop the close-time re-derivation -> a
# delta opened `small` and grown to `evolution` closes on the small checklist".
# `measured=""` is exactly that: the ratchet arithmetic still runs, and with
# nothing measured to compare against it can only ever keep the open-time values.
#
# THE STRUCTURAL DISCRIMINATOR. "It closed" is also what a fixture that never
# reached the ratchet would report. So this row runs the PRISTINE tree on an
# IDENTICAL fixture in the same breath (rc 10, nothing closed) and asserts the
# mutant's closed row still carries the SMALL attributes — the checklist it
# closed on, named.
T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"
_sed_inplace "$MT/scripts/delta.sh" '/# DELTA-CLOSE-RATCHET$/s@.*@  measured=""@'
rep="$(_mutation_report "$REPO_ROOT/scripts/delta.sh" "$MT/scripts/delta.sh" 'DELTA-CLOSE-RATCHET$')"
sites="${rep%%|*}"; rest="${rep#*|}"; changed="${rest%%|*}"; nlines="${rest##*|}"
_m1_fixture() {
  local P="$1"
  mk_git_proj "$P" 4
  write_policy "$P" '{"schemaVersion":1,"risk_surfaces":["src/auth/**"],"size_thresholds":{"small":5,"significant":20}}'
  delta_run "$REPO_ROOT/scripts" "$P" --open --describe "token check is wrong" --class fix --slug token-check --confirm >/dev/null 2>&1
  complete_gates "$REPO_ROOT/scripts" "$P"
  grow "$P/src/auth/login.ts" 30
}
Pp="$T/pristine"; _m1_fixture "$Pp"
delta_run "$REPO_ROOT/scripts" "$Pp" --close >/dev/null 2>&1; pri_rc=$?
pri_closed="$(active_json "$Pp" -r '.closed | length')"
Pm="$T/mutant";   _m1_fixture "$Pm"
delta_run "$MT/scripts" "$Pm" --close >/dev/null 2>&1; mut_rc=$?
mut_closed="$(active_json "$Pm" -r '.closed | length')"
mut_attrs="$(active_json "$Pm" -c '.closed[0].attributes | {risk, level}')"
mut_gates="$(active_json "$Pm" -c '.closed[0].gates_completed')"
if [ "$sites" = "1" ] && [ "$changed" = y ] && [ "$nlines" -eq 2 ] \
   && [ "$pri_rc" -eq 10 ] && [ "$pri_closed" = "0" ] \
   && [ "$mut_rc" -eq 0 ] && [ "$mut_closed" = "1" ] \
   && [ "$mut_attrs" = '{"risk":"feature-local","level":"small"}' ] \
   && [ "$mut_gates" = '["ledger_row","repro_test_red_first","close_review","changelog"]' ]; then
  pass "m1: with the close-time re-derivation dropped, the SAME fixture — thirty lines added to a risk surface — closes clean (rc $mut_rc) on the SMALL checklist ($mut_gates, attributes $mut_attrs) where the pristine tree refuses (rc $pri_rc, nothing closed). X1 goes RED, and the failure mode is silent: no error, just a delta that never had to justify what it grew into (marker sites=$sites, one line changed=$nlines/2)"
else
  fail_ "m1" "marker sites=$sites (expect 1); mutation applied=$changed (expect y); diff lines=$nlines (expect 2); PRISTINE rc=$pri_rc (expect 10) closed=$pri_closed (expect 0); MUTANT rc=$mut_rc (expect 0) closed=$mut_closed (expect 1) attributes=$mut_attrs (expect feature-local/small) gates=$mut_gates (expect the bare fix row)"
fi
rm -rf "$T"

# ── m2: neuter the unchecked-box refusal  [B1 RED] ─────────────────────────
# FRESH FIXTURE WITH EVERY GATE COMPLETE, on purpose: with brief_review still
# outstanding the gates refusal fires two guards earlier, the rubric bind never
# executes, and the mutant looks pinned when it is not.
# STRUCTURAL DISCRIMINATOR: the mutant's OWN tree is re-read to confirm the brief
# it closed against still carries an unchecked box.
T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"
_sed_inplace "$MT/scripts/delta.sh" '/# DELTA-CLOSE-RUBRIC-GUARD$/s@.*@  if false; then@'
rep="$(_mutation_report "$REPO_ROOT/scripts/delta.sh" "$MT/scripts/delta.sh" 'DELTA-CLOSE-RUBRIC-GUARD$')"
sites="${rep%%|*}"; rest="${rep#*|}"; changed="${rest%%|*}"; nlines="${rest##*|}"
_m2_fixture() {
  local P="$1"
  mk_proj "$P" 4
  delta_run "$REPO_ROOT/scripts" "$P" --open --describe "add dark mode" --class feature --slug dark-mode --confirm >/dev/null 2>&1
  write_brief "$P" DELTA-001 dark-mode '- [x] the settings screen offers a dark theme' '- [ ] the choice survives a restart'
  complete_gates "$REPO_ROOT/scripts" "$P"
}
Pp="$T/pristine"; _m2_fixture "$Pp"
delta_run "$REPO_ROOT/scripts" "$Pp" --close >/dev/null 2>&1; pri_rc=$?
Pm="$T/mutant";   _m2_fixture "$Pm"
delta_run "$MT/scripts" "$Pm" --close >/dev/null 2>&1; mut_rc=$?
mut_closed="$(active_json "$Pm" -r '.closed | length')"
still_unchecked=n
grep -qF -- '- [ ] the choice survives a restart' "$Pm/docs/deltas/DELTA-001-dark-mode.md" && still_unchecked=y
if [ "$sites" = "1" ] && [ "$changed" = y ] && [ "$nlines" -eq 2 ] \
   && [ "$pri_rc" -eq 8 ] && [ "$mut_rc" -eq 0 ] && [ "$mut_closed" = "1" ] && [ "$still_unchecked" = y ]; then
  pass "m2: with the unchecked-box refusal neutered, a feature closes (rc $mut_rc, audit row written) against a brief whose 'the choice survives a restart' criterion is STILL unchecked in the mutant's own tree (present=$still_unchecked), where the pristine tree refuses (rc $pri_rc). B1 goes RED — and §5.3's one mechanical review surface is gone (marker sites=$sites, one line changed=$nlines/2)"
else
  fail_ "m2" "marker sites=$sites (expect 1); mutation applied=$changed (expect y); diff lines=$nlines (expect 2); PRISTINE rc=$pri_rc (expect 8); MUTANT rc=$mut_rc (expect 0) closed=$mut_closed (expect 1); brief still carries the unchecked box=$still_unchecked (expect y — if n the fixture never violated the rubric and this row proves nothing)"
fi
rm -rf "$T"

# ── m3: null the slot WITHOUT appending  [W1/W2 RED — carry-forward (a)] ───
# The id-reuse hazard, executed. The mutant's close still "works" from the
# operator's side — rc 0, the slot empties, --status says there is nothing open —
# and the delta has been erased from the record rather than archived, so the very
# next open is handed DELTA-001 again.
T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"
_sed_inplace "$MT/scripts/delta.sh" '/# DELTA-CLOSE-ATOMIC-WRITE$/s@.*@  filter=".active_delta = null"@'
rep="$(_mutation_report "$REPO_ROOT/scripts/delta.sh" "$MT/scripts/delta.sh" 'DELTA-CLOSE-ATOMIC-WRITE$')"
sites="${rep%%|*}"; rest="${rep#*|}"; changed="${rest%%|*}"; nlines="${rest##*|}"
_m3_fixture() {
  local P="$1"
  mk_proj "$P" 4
  delta_run "$REPO_ROOT/scripts" "$P" --open --describe "the CSV export crashes on unicode" --confirm >/dev/null 2>&1
  complete_gates "$REPO_ROOT/scripts" "$P"
}
Pp="$T/pristine"; _m3_fixture "$Pp"
delta_run "$REPO_ROOT/scripts" "$Pp" --close >/dev/null 2>&1
delta_run "$REPO_ROOT/scripts" "$Pp" --open --describe "add dark mode" --confirm >/dev/null 2>&1
pri_next="$(active_json "$Pp" -r '.active_delta.id')"
pri_closed="$(active_json "$Pp" -r '.closed | length')"
Pm="$T/mutant";   _m3_fixture "$Pm"
delta_run "$MT/scripts" "$Pm" --close >/dev/null 2>&1; mut_rc=$?
mut_closed="$(active_json "$Pm" -r '.closed | length')"
mut_slot="$(active_json "$Pm" -r '.active_delta')"
delta_run "$MT/scripts" "$Pm" --open --describe "add dark mode" --confirm >/dev/null 2>&1
mut_next="$(active_json "$Pm" -r '.active_delta.id')"
if [ "$sites" = "1" ] && [ "$changed" = y ] && [ "$nlines" -eq 2 ] \
   && [ "$pri_closed" = "1" ] && [ "$pri_next" = "DELTA-002" ] \
   && [ "$mut_rc" -eq 0 ] && [ "$mut_closed" = "0" ] && [ "$mut_slot" = "null" ] \
   && [ "$mut_next" = "DELTA-001" ]; then
  pass "m3: with the append half of the close write removed the close still reports success (rc $mut_rc) and still empties the slot ($mut_slot), but the audit tail stays at $mut_closed rows and the NEXT open is handed $mut_next — the id the just-closed delta had — where the pristine tree archives one row and issues $pri_next. W1/W2 go RED. This is carry-forward (a) executed rather than argued (marker sites=$sites, one line changed=$nlines/2)"
else
  fail_ "m3" "marker sites=$sites (expect 1); mutation applied=$changed (expect y); diff lines=$nlines (expect 2); PRISTINE closed=$pri_closed (expect 1) next id=$pri_next (expect DELTA-002); MUTANT rc=$mut_rc (expect 0) closed=$mut_closed (expect 0) slot=$mut_slot (expect null) next id=$mut_next (expect DELTA-001, the reuse)"
fi
rm -rf "$T"

# ── m4: neuter the vocabulary check  [U1 RED] ──────────────────────────────
T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"
_sed_inplace "$MT/scripts/delta.sh" '/# DELTA-CLOSE-VOCAB-GUARD$/s@.*@  if false; then@'
rep="$(_mutation_report "$REPO_ROOT/scripts/delta.sh" "$MT/scripts/delta.sh" 'DELTA-CLOSE-VOCAB-GUARD$')"
sites="${rep%%|*}"; rest="${rep#*|}"; changed="${rest%%|*}"; nlines="${rest##*|}"
_m4_fixture() {
  local P="$1"
  mk_proj "$P" 4
  delta_run "$REPO_ROOT/scripts" "$P" --open --describe "the CSV export crashes on unicode" --confirm >/dev/null 2>&1
  complete_gates "$REPO_ROOT/scripts" "$P"
  seam "$REPO_ROOT/scripts" "$P" --delta-state-update \
    '.active_delta.gates_required += ["frobnicate"] | .active_delta.gates_completed += ["frobnicate"]' >/dev/null 2>&1
}
Pp="$T/pristine"; _m4_fixture "$Pp"
delta_run "$REPO_ROOT/scripts" "$Pp" --close >/dev/null 2>&1; pri_rc=$?
Pm="$T/mutant";   _m4_fixture "$Pm"
delta_run "$MT/scripts" "$Pm" --close >/dev/null 2>&1; mut_rc=$?
mut_closed="$(active_json "$Pm" -r '.closed | length')"
mut_archived="$(active_json "$Pm" -r '.closed[0].gates_completed | index("frobnicate") != null')"
if [ "$sites" = "1" ] && [ "$changed" = y ] && [ "$nlines" -eq 2 ] \
   && [ "$pri_rc" -eq 9 ] && [ "$mut_rc" -eq 0 ] && [ "$mut_closed" = "1" ] && [ "$mut_archived" = "true" ]; then
  pass "m4: with the vocabulary check neutered a delta carrying the meaningless token 'frobnicate' closes clean (rc $mut_rc) and archives it into the audit tail (present=$mut_archived), where the pristine tree fails CLOSED (rc $pri_rc). U1 goes RED — a typo in a project's policy would silently become a gate nobody can ever fail (marker sites=$sites, one line changed=$nlines/2)"
else
  fail_ "m4" "marker sites=$sites (expect 1); mutation applied=$changed (expect y); diff lines=$nlines (expect 2); PRISTINE rc=$pri_rc (expect 9); MUTANT rc=$mut_rc (expect 0) closed=$mut_closed (expect 1) archived the bogus token=$mut_archived (expect true)"
fi
rm -rf "$T"

# ── m5: neuter the outstanding-gates refusal  [C1 RED] ─────────────────────
T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"
_sed_inplace "$MT/scripts/delta.sh" '/# DELTA-CLOSE-GATES-GUARD$/s@.*@  if false; then@'
rep="$(_mutation_report "$REPO_ROOT/scripts/delta.sh" "$MT/scripts/delta.sh" 'DELTA-CLOSE-GATES-GUARD$')"
sites="${rep%%|*}"; rest="${rep#*|}"; changed="${rest%%|*}"; nlines="${rest##*|}"
_m5_fixture() {
  local P="$1"
  mk_proj "$P" 4
  delta_run "$REPO_ROOT/scripts" "$P" --open --describe "add dark mode" --class feature --slug dark-mode --confirm >/dev/null 2>&1
  write_brief "$P" DELTA-001 dark-mode '- [x] the settings screen offers a dark theme'
  complete_gates "$REPO_ROOT/scripts" "$P" brief_review
}
Pp="$T/pristine"; _m5_fixture "$Pp"
delta_run "$REPO_ROOT/scripts" "$Pp" --close >/dev/null 2>&1; pri_rc=$?
Pm="$T/mutant";   _m5_fixture "$Pm"
delta_run "$MT/scripts" "$Pm" --close >/dev/null 2>&1; mut_rc=$?
mut_closed="$(active_json "$Pm" -r '.closed | length')"
mut_missing="$(active_json "$Pm" -r '.closed[0].gates_completed | index("brief_review") == null')"
if [ "$sites" = "1" ] && [ "$changed" = y ] && [ "$nlines" -eq 2 ] \
   && [ "$pri_rc" -eq 7 ] && [ "$mut_rc" -eq 0 ] && [ "$mut_closed" = "1" ] && [ "$mut_missing" = "true" ]; then
  pass "m5: with the outstanding-gates refusal neutered a feature closes (rc $mut_rc) with brief_review never attested — the archived gates_completed is missing it (missing=$mut_missing) — where the pristine tree refuses (rc $pri_rc). C1 goes RED, and §5.3's pre-build adversarial review is silently optional (marker sites=$sites, one line changed=$nlines/2)"
else
  fail_ "m5" "marker sites=$sites (expect 1); mutation applied=$changed (expect y); diff lines=$nlines (expect 2); PRISTINE rc=$pri_rc (expect 7); MUTANT rc=$mut_rc (expect 0) closed=$mut_closed (expect 1) brief_review absent from the archive=$mut_missing (expect true)"
fi
rm -rf "$T"

# ── m6: neuter the seam's replacement atom  [R1 RED] ───────────────────────
# The atom lives inside a jq program, so the neuter is the WP2 form — replace the
# marked line with `and (true)` so the program stays syntactically whole and
# exactly one atom stops asserting.
T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"
_sed_inplace "$MT/scripts/lib/delta-state.sh" '/# ACTIVE-ATOM-NO-REPLACE$/s@.*@      and (true)@'
rep="$(_mutation_report "$REPO_ROOT/scripts/lib/delta-state.sh" "$MT/scripts/lib/delta-state.sh" 'ACTIVE-ATOM-NO-REPLACE$')"
sites="${rep%%|*}"; rest="${rep#*|}"; changed="${rest%%|*}"; nlines="${rest##*|}"
P="$T/proj"; mk_proj "$P" 4
delta_run "$MT/scripts" "$P" --open --describe "the CSV export crashes on unicode" --confirm >/dev/null 2>&1
delta_run "$MT/scripts" "$P" --complete-gate ledger_row >/dev/null 2>&1
before="$(_md5file "$P/.claude/delta-state.json")"
seam "$MT/scripts" "$P" --delta-state-update \
  '.active_delta = {"id":"DELTA-002","slug":"stolen","class":"feature","gates_required":[],"gates_completed":[]}' >/dev/null 2>&1
mut_rc=$?
after="$(_md5file "$P/.claude/delta-state.json")"
mut_id="$(active_json "$P" -r '.active_delta.id')"
mut_lost="$(active_json "$P" -r '.active_delta.gates_completed | length')"
if [ "$sites" = "1" ] && [ "$changed" = y ] && [ "$nlines" -eq 2 ] \
   && [ "$mut_rc" -eq 0 ] && [ "$before" != "$after" ] && [ "$mut_id" = "DELTA-002" ] && [ "$mut_lost" = "0" ]; then
  pass "m6: with the replacement atom neutered the crafted seam write SUCCEEDS (rc $mut_rc), the open slot now holds $mut_id and DELTA-001's completed-gate history is gone ($mut_lost rows left). R1 goes RED — which is R-WP3-3 exactly: the business refusal in delta.sh never sees this write (marker sites=$sites, one line changed=$nlines/2)"
else
  fail_ "m6" "marker sites=$sites (expect 1); mutation applied=$changed (expect y); diff lines=$nlines (expect 2); mutant rc=$mut_rc (expect 0); bytes $before -> $after (must DIFFER); id now=$mut_id (expect DELTA-002); surviving gates_completed rows=$mut_lost (expect 0)"
fi
rm -rf "$T"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
