#!/usr/bin/env bash
# tests/test-lint-delta-boundary.sh
#
# Behavior tests for scripts/lint-delta-boundary.sh — the dependency-direction
# boundary lint specified by docs/designs/2026-08-02-delta-track-v1.md §3.3
# (settled decision D1: the delta track is a SEVERABLE module and the boundary
# is lint-enforced FROM THE FIRST COMMIT).
#
# Each case stages a hermetic mini-tree under mktemp -d, points the lint at it
# with --root, and asserts on the EXIT CODE (never on a printed label — the
# repo's [WARN] trap is that labels and exit predicates disagree).
#
# WHAT THE SUITE PINS, and why each pin exists
#
#   DIRECTION (§3.3 clauses 1-2)
#     D1  clean tree                                     -> 0
#     D2  core file names a delta path (T1)              -> 1
#     D3  variable-composed reference (T2)               -> 1
#     D4  delta -> core reference is unasserted          -> 0
#     D5  T1 and T2 do not double-report the same line   -> exactly one row
#
#   SURFACE (§3.3 "Set definitions")
#     S1  init.sh is scanned
#     S2  scripts/hooks/*.sh is scanned
#     S3  scripts/lib/*.sh (non-delta members) is scanned
#     A narrowed surface would pass D1-D5 while seeing nothing; these three are
#     the anti-vacuity pins for the CORE half specifically.
#
#   THE EXECUTED-LINES STRIPPER (§3.3 "Executed lines only")
#     This predicate has repo scar tissue. CLAUDE.md records that a
#     ONE-CHARACTER narrowing of the sibling predicate in
#     scripts/lint-tests-registered.sh (# BL-181-UNIT-LANE-PREDICATE) re-opened
#     the same hole THREE times while passing both PR-blocking checks each
#     time. So the pins below name each ATOM of the two sed expressions and
#     pin its WIDTH and its SPELLING, not merely its presence.
#
#     TWO DIRECTIONS, AND ONLY ONE OF THEM IS CHEAP TO CATCH. Read this before
#     trusting any row of the map:
#       • NARROWING (the stripper does too LITTLE) leaves comments looking
#         executed, so it produces FALSE POSITIVES. Any exit-0 fixture catches
#         it. X2/X3/X4/X5 are all of this kind and they are easy.
#       • WIDENING (the stripper does too MUCH) eats executed code, so it
#         produces FALSE NEGATIVES. NO exit-0 fixture can ever see it, because
#         an over-stripped tree is a QUIETER tree. It is caught only by a
#         VIOLATION fixture whose token sits where the widened match would
#         reach. X8 is that fixture and it is the load-bearing one.
#
#     The original version of this map got two rows wrong, and an adversarial
#     review caught it (WP1 R-WP1-1/R-WP1-2). The false claim was that dropping
#     E1's `^` "blanks the whole line": sed's s/// replaces only the MATCHED
#     REGION, never the line, so the code prefix and its token survive and the
#     case that claimed to pin the anchor did not. Three separate mutations
#     survived all 27 cases as a result. The rows below describe what each case
#     ACTUALLY kills, verified by executing the mutants.
#
#       E1 = 's/^[[:space:]]*#.*$//'                     (whole-line comments)
#         C1  the `^` anchor          -> pinned by X8, NOT by X1. Dropping `^`
#             does not blank anything; it lets the leftmost match START at any
#             `#` that has only optional whitespace before it, so `x#token`
#             truncates to `x` and the reference vanishes. That is a widening,
#             so only a violation fixture sees it. (Mutant M-A: survives
#             X1-X7, dies to X8.)
#         C2  `[[:space:]]*` WIDTH    -> pinned by X2 (0, 1, 4, 8 spaces, tab,
#             tab+spaces, all ignored). Narrowing to `^#` false-positives on
#             every indented comment. NOTE the asymmetry: `*` cannot be widened
#             further, so C2's only failure mode is the narrowing X2 catches.
#         C3  `#` SPELLING            -> pinned by X3 (no space required after
#             `#`). Narrowing to `#[[:space:]]` false-positives on `#code`.
#         C4  `.*$` reach             -> pinned by X2/X3 implicitly: the token
#             sits AFTER the `#`, so a non-greedy or anchored variant leaves it
#             behind and reds.
#         C4b THE WHOLE-EXPRESSION widening (`s/#.*$//`, any `#` anywhere)
#             -> pinned by X8. (Mutant M-B: survives X1-X7, dies to X8.)
#
#       E2 = 's/\([^[:space:]]\)[[:space:]][[:space:]]*#.*$/\1/'  (trailing)
#         C5  `[[:space:]][[:space:]]*` WIDTH -> pinned in BOTH directions, by
#             two different cases, because this atom can fail either way:
#               narrowing to two-or-more
#               (`[[:space:]][[:space:]][[:space:]]*`) false-positives on the
#               single-space form -> X4 (which carries ONE space, TAB, two and
#               six spaces; the single-space form is the commonest spelling in
#               this repo);
#               widening to zero-or-more (`[[:space:]]*`) makes `x#token`
#               strippable and the reference vanishes -> X8. (Mutant M-H:
#               survives X1-X7, dies to X8.)
#         C6  `#` SPELLING            -> pinned by X5 (no space after `#`).
#         C7  `\([^[:space:]]\)` guard + `\1` back-reference — the executed
#             PREFIX must survive the strip -> pinned at TWO resolutions:
#               X1 (COARSE): a mutation that discards the whole line whenever a
#               trailing comment is present, e.g.
#               `s/.*[[:space:]][[:space:]]*#.*$//`, loses the violation
#               outright. Measured: X1, X6, L2, L6 and L7 all go RED (24/5).
#               X6 (FINE): dropping the capture eats exactly ONE character of
#               executed code, which is NOT enough to make the line green — it
#               DEMOTES the hit from T1 to T2 (the truncated token stops
#               matching a literal path but still carries the `delta-` prefix).
#               X6 therefore asserts the TIER, not the exit code: rc alone
#               cannot see this. The demotion matters because T2 is
#               inline-allowlistable and T1 is not.
#             Both are kept: an edit that eats everything and one that eats a
#             single byte are different mutations and X1 cannot see the latter.
#         C8  `#` INSIDE a word is not a comment -> pinned by X7 and X8, which
#             cover OPPOSITE failure modes of the same atom and are deliberately
#             not folded together:
#               X7 = the DELETION direction (a `grep -v '#'` refactor, or an E1
#               rewritten `s/^.*#.*$//`, discards the whole line). X7's token
#               sits BEFORE the `#`, so it survives a truncating mutant — X7
#               alone does NOT pin over-stripping, and the earlier claim that
#               it did was the second refuted claim.
#               X8 = the TRUNCATION direction (token AFTER the `#`).
#
#   ALLOWLISTS (§3.3 clause 3 + the T2 row)
#     L1  T2 inline allow WITH a reason is honored       -> 0
#     L2  T2 inline allow with an EMPTY reason           -> 1
#     L3  the seam file passes                           -> 0
#     L4  seam allowlist cardinality is exactly 1        -> 1 when it grows
#         (mutation, executed here against a lint COPY)
#     L5  a seam row with no reason                      -> 1
#     L6  T1 is NOT inline-allowlistable (only the file-level seam is)
#     L7  a NEAR-MISS marker (`allowed`, `allowlist`) does not allowlist -> 1
#         (the marker is an exact token, not a prefix)
#
#   VACUITY FLOOR (§3.3 clause 4)
#     V1  no delta-module file present                   -> 2 (not 0, not 1)
#     V2  no core file present                           -> 2
#     V3  mutation: empty the DELTA manifest in a lint COPY and run it against
#         the REAL repo root                             -> 2 (not 0)
#
#   INTERFACE
#     I1  --list emits the STATUS table incl. the population INFO row
#     I2  an unknown flag                                -> 2
#     I3  the REAL tree passes                           -> 0
#
# HAZARD NOTE — why this file may safely contain delta paths.
# The lint's CORE surface is init.sh + scripts/*.sh + scripts/lib/*.sh +
# scripts/hooks/*.sh. tests/ is NOT in it, so the literals below never become
# violations on the real tree. (Contrast tests/test-lint-bl-markers.sh, whose
# fixtures DO land in that lint's surface and must be built by concatenation.)
#
# Style mirrors tests/test-lint-bl-markers.sh: set -uo pipefail, mktemp
# fixtures, pass/fail counters, teardown after each case, bash 3.2 only.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINTER="$REPO_ROOT/scripts/lint-delta-boundary.sh"

if [ ! -f "$LINTER" ]; then
  echo "FATAL: linter not found at $LINTER" >&2
  exit 2
fi

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TAB=$(printf '\t')

# ── Fixture builder ─────────────────────────────────────────────────────
# A minimal tree carrying BOTH halves the vacuity floor demands: at least one
# CORE file and at least one DELTA-module file. Cases add to it.
setup_fixture() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/scripts/lib" "$TMP/scripts/hooks"
  cat > "$TMP/init.sh" <<'SH'
#!/usr/bin/env bash
echo "scaffold"
SH
  cat > "$TMP/scripts/check-gate.sh" <<'SH'
#!/usr/bin/env bash
. "$(dirname "$0")/lib/helpers-core.sh"
echo "gate"
SH
  cat > "$TMP/scripts/lib/helpers-core.sh" <<'SH'
#!/usr/bin/env bash
helper() { echo "help"; }
SH
  cat > "$TMP/scripts/hooks/record-thing.sh" <<'SH'
#!/usr/bin/env bash
echo "hook"
SH
  # The DELTA half of the floor.
  cat > "$TMP/scripts/lib/delta-state.sh" <<'SH'
#!/usr/bin/env bash
delta_state_read() { echo "{}"; }
SH
}
teardown_fixture() { rm -rf "$TMP"; }

run_fixture() { bash "$LINTER" --root "$TMP" 2>&1; return $?; }
# --list asserts on the TABLE, so stderr is dropped: the per-violation
# diagnostics carry the same file:line text and would double every row count.
run_fixture_list() { bash "$LINTER" --root "$TMP" --list 2>/dev/null; return $?; }

# ════════════════════════════════════════════════════════════════════
echo "=== D1: a clean tree -> exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
out=$(run_fixture); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "D1: clean fixture exits 0"
else
  fail_ "D1" "expected rc=0; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== D2: core file names a delta path (T1) -> exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# This is mutation m1 executed as a permanent test: the design's worked
# example is someone adding `source .../lib/delta-state.sh` to a core gate
# script on a Tuesday and the severability property vanishing silently.
setup_fixture
cat > "$TMP/scripts/check-gate.sh" <<'SH'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/delta-state.sh"
echo "gate"
SH
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -q 'scripts/check-gate\.sh:3' \
   && echo "$out" | grep -q 'delta-state\.sh'; then
  pass "D2: T1 literal-path reference exits 1 naming file:line and the token"
else
  fail_ "D2" "expected rc=1 + check-gate.sh:3 + the token; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== D3: variable-composed reference is caught by T2 -> exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# R-DT-6: a path-only lint is evadable because bash composes at runtime.
# The line below carries NO literal delta path, so T1 cannot see it.
setup_fixture
cat > "$TMP/scripts/check-gate.sh" <<'SH'
#!/usr/bin/env bash
LIB="$(cd "$(dirname "$0")/lib" && pwd)"
kind="state"
source "$LIB/delta-${kind}.sh"
echo "gate"
SH
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -q 'scripts/check-gate\.sh:4' \
   && echo "$out" | grep -q 'T2'; then
  pass "D3: variable-composed reference caught by T2 at the right line"
else
  fail_ "D3" "expected rc=1 + check-gate.sh:4 + a T2 tier row; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== D4: delta -> core reference is allowed and unasserted -> exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/scripts/lib/delta-state.sh" <<'SH'
#!/usr/bin/env bash
. "$(dirname "$0")/helpers-core.sh"
. "$(dirname "$0")/enforcement-level.sh"
delta_state_read() { helper; }
SH
out=$(run_fixture); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "D4: a delta-module file sourcing core is not a violation"
else
  fail_ "D4" "expected rc=0; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== D5: a T1 line is not ALSO reported as T2 (tier discrimination) ==="
# ════════════════════════════════════════════════════════════════════
# §3.3's T2 row reads "on any executed line of a CORE file that T1 did not
# already catch". Double-reporting would inflate the count and make the
# operator chase one defect twice.
setup_fixture
cat > "$TMP/scripts/check-gate.sh" <<'SH'
#!/usr/bin/env bash
source "lib/delta-state.sh"
SH
out=$(run_fixture_list); rc=$?
rows=$(echo "$out" | grep -c 'scripts/check-gate\.sh:2')
if [ "$rc" -eq 1 ] && [ "$rows" -eq 1 ]; then
  pass "D5: the T1 line yields exactly one row (no T2 double-report)"
else
  fail_ "D5" "expected rc=1 and exactly 1 row for that line; rc=$rc rows=$rows; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== S1: init.sh is inside the CORE surface ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/init.sh" <<'SH'
#!/usr/bin/env bash
cp "$SCRIPT_DIR/scripts/lib/delta-state.sh" "$TARGET/scripts/lib/"
SH
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'init\.sh:2'; then
  pass "S1: init.sh is scanned"
else
  fail_ "S1" "expected rc=1 naming init.sh:2; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== S2: scripts/hooks/*.sh is inside the CORE surface ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/scripts/hooks/record-thing.sh" <<'SH'
#!/usr/bin/env bash
jq . .claude/delta-state.json
SH
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'scripts/hooks/record-thing\.sh:2'; then
  pass "S2: scripts/hooks/*.sh is scanned"
else
  fail_ "S2" "expected rc=1 naming the hook; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== S3: scripts/lib/*.sh non-delta members are inside CORE ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/scripts/lib/helpers-core.sh" <<'SH'
#!/usr/bin/env bash
helper() { cat docs/deltas/DELTA-001.md; }
SH
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'scripts/lib/helpers-core\.sh:2'; then
  pass "S3: a non-delta scripts/lib member is scanned"
else
  fail_ "S3" "expected rc=1 naming helpers-core.sh:2; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== X1 (atom C7, coarse form): stripping a trailing comment must leave"
echo "    the EXECUTED PREFIX intact -> exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# CORRECTED after adversarial review (R-WP1-2). This case used to claim it
# pinned E1's `^` anchor, on the theory that an unanchored E1 "blanks the whole
# line". That theory is wrong about sed: `s///` replaces only the MATCHED
# REGION, never the line, so an unanchored E1 simply truncates at the ` #` and
# this fixture's token — which sits BEFORE the comment — survives. X1 stayed
# green under that mutation and the anchor was unpinned. The `^` anchor and the
# whole over-strip/widening family are pinned by X8; see the atom -> case map
# in this file's header.
#
# What X1 ACTUALLY pins, verified by executing the mutation rather than
# reasoning about it: the trailing-comment strip must remove ONLY the comment
# and never the executed prefix. Mutate E2 to `s/.*[[:space:]][[:space:]]*#.*$//`
# — which discards the whole line whenever a trailing comment is present — and
# this case goes RED (measured: X1, X6, L2, L6 and L7 all fail, 24 passed /
# 5 failed).
#
# X1 is the COARSE form of that pin and X6 is the FINE one: X1 catches a
# mutation that loses the whole prefix, X6 catches one that loses a SINGLE
# character (by asserting the tier, because one lost character only demotes
# T1 -> T2 and never changes the exit code). Both are kept — a mutation that
# eats everything and one that eats one byte are different edits.
setup_fixture
cat > "$TMP/scripts/check-gate.sh" <<'SH'
#!/usr/bin/env bash
source "$SCRIPT_DIR/lib/delta-state.sh"  # convenience, just this once
SH
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'scripts/check-gate\.sh:2'; then
  pass "X1: the executed prefix survives a trailing-comment strip"
else
  fail_ "X1" "expected rc=1; an E2 that discards the code half loses this violation; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== X2 (atom C2, E1 '[[:space:]]*' WIDTH): whole-line comments are"
echo "    ignored at EVERY indent width -> exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# Six widths in one file: column 0, one space, four spaces, eight spaces, a
# TAB, and TAB+spaces. Narrowing E1 to `^#` reds on five of the six; narrowing
# to `^[[:space:]]` reds on the first.
setup_fixture
{
  printf '#!/usr/bin/env bash\n'
  printf '# source "$SCRIPT_DIR/lib/delta-state.sh" would fuse the module\n'
  printf ' # one space: scripts/lib/delta-policy.sh\n'
  printf '    # four spaces: scripts/delta.sh\n'
  printf '        # eight spaces: .claude/delta-state.json\n'
  printf '%s# a tab: docs/deltas/\n' "$TAB"
  printf '%s   # tab plus spaces: scripts/cut-release.sh\n' "$TAB"
  printf 'echo gate\n'
} > "$TMP/scripts/check-gate.sh"
out=$(run_fixture); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "X2: E1 strips whole-line comments at 0/1/4/8-space, tab and tab+space indents"
else
  fail_ "X2" "expected rc=0 — a narrowed E1 width false-positives here; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== X3 (atom C3, E1 '#' SPELLING): no space is required after '#' ==="
# ════════════════════════════════════════════════════════════════════
# Narrowing E1 to `^[[:space:]]*#[[:space:]]` makes every one of these an
# "executed" line and the lint cries wolf. Both indent widths are present so
# the mutation cannot be papered over by the width pin alone.
setup_fixture
{
  printf '#!/usr/bin/env bash\n'
  printf '#source "$SCRIPT_DIR/lib/delta-state.sh"\n'
  printf '    #source "$SCRIPT_DIR/lib/delta-policy.sh"\n'
  printf '%s#delta-composed reference sketch\n' "$TAB"
  printf 'echo gate\n'
} > "$TMP/scripts/check-gate.sh"
out=$(run_fixture); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "X3: E1 strips '#comment' with no space after the hash, at any indent"
else
  fail_ "X3" "expected rc=0; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== X4 (atom C5, E2 whitespace WIDTH): trailing comments strip after"
echo "    ONE space, a TAB, and many spaces -> exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# The single-space form is the commonest spelling in this repo, and it is the
# one a two-or-more narrowing silently drops.
setup_fixture
{
  printf '#!/usr/bin/env bash\n'
  printf 'echo one #see scripts/lib/delta-state.sh\n'
  printf 'echo two  # see scripts/lib/delta-policy.sh\n'
  printf 'echo three%s# see scripts/delta.sh\n' "$TAB"
  printf 'echo four      # see docs/deltas/ and .claude/delta-policy.json\n'
} > "$TMP/scripts/check-gate.sh"
out=$(run_fixture); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "X4: E2 strips trailing comments at 1-space, 2-space, tab and 6-space widths"
else
  fail_ "X4" "expected rc=0 — a widened E2 minimum false-positives on the 1-space form; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== X5 (atom C6, E2 '#' SPELLING): trailing '#token' with no space ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
{
  printf '#!/usr/bin/env bash\n'
  printf 'echo one #delta-state.sh\n'
  printf 'echo two%s#delta-cadence.sh\n' "$TAB"
} > "$TMP/scripts/check-gate.sh"
out=$(run_fixture); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "X5: E2 strips a trailing comment with no space after the hash"
else
  fail_ "X5" "expected rc=0; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== X6 (atom C7, E2's capture + '\\1' back-reference): the last code"
echo "    character must survive the strip -> the hit is still TIER T1 ==="
# ════════════════════════════════════════════════════════════════════
# Drop the `\([^[:space:]]\)` capture and the `\1` replacement — i.e. mutate
# E2 to `s/[^[:space:]][[:space:]][[:space:]]*#.*$//` — and the strip eats ONE
# character of executed code. The line below then reads `...delta-policy.jso`,
# the T1 literal token no longer matches, and the reference is demoted to a T2
# hit: still non-zero, so an rc-only assertion would MISS the regression
# entirely. Asserting the TIER is what makes this atom pinned. (Note the
# demotion is not harmless — T2 is inline-allowlistable and T1 is not, so the
# mutation silently converts an unarguable violation into a waivable one.)
setup_fixture
{
  printf '#!/usr/bin/env bash\n'
  printf 'jq . .claude/delta-policy.json   # read the policy\n'
} > "$TMP/scripts/check-gate.sh"
out=$(run_fixture_list); rc=$?
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -q '^FAIL.*T1.*scripts/check-gate\.sh:2'; then
  pass "X6: E2 keeps the last executed character, so the hit stays tier T1"
else
  fail_ "X6" "expected rc=1 with a T1 row for line 2; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== X7 (atom C8, whole-line-deletion direction): a line carrying a"
echo "    mid-word '#' is not discarded wholesale -> exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# `echo delta-state.sh#x` is a single bash WORD; bash executes it. This case
# guards the DELETION direction — a refactor to `grep -v '#'`, or an E1
# rewritten as `s/^.*#.*$//`, drops the entire line and the reference with it.
# It does NOT guard the truncation direction: the token here sits BEFORE the
# `#`, so an over-stripping mutant leaves it intact and X7 still passes. X8
# below is the case that covers truncation, and the two are deliberately kept
# apart rather than folded, because they die to different mutations.
setup_fixture
{
  printf '#!/usr/bin/env bash\n'
  printf 'echo scripts/lib/delta-state.sh#fragment\n'
} > "$TMP/scripts/check-gate.sh"
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'scripts/check-gate\.sh:2'; then
  pass "X7: a line with a mid-word '#' is not deleted wholesale"
else
  fail_ "X7" "expected rc=1; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== X8 (atoms C1/C5/C8, the OVER-STRIP direction): a delta token"
echo "    AFTER a mid-word '#' must still be seen -> exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# THE CASE THAT PINS THE STRIPPER'S UPPER BOUND. Every other X case pins a
# narrowing (the stripper doing too little, producing false positives, which
# any exit-0 fixture catches). This one pins a WIDENING — the stripper doing
# too MUCH, silently eating executed code, which no exit-0 fixture can ever
# see because an over-stripped tree is a QUIETER tree.
#
# `echo "ref=x#delta-state.sh"` is one bash WORD after `ref=`: bash does not
# treat that `#` as a comment (a comment `#` must start a word), so the delta
# path is genuinely referenced on an executed line. Three separate
# one-character-class mutations all make the stripper eat from that `#`
# onward, and all three were verified to survive the other 27 cases AND every
# PR-blocking check before this case existed:
#
#   M-A  E1 `s/^[[:space:]]*#.*$//` -> `s/[[:space:]]*#.*$//`  (drop `^`)
#        sed's s/// replaces only the MATCHED REGION, not the line, so the
#        leftmost match simply starts at the `#` and truncates there.
#   M-B  E1 -> `s/#.*$//`                              (strip from any `#`)
#   M-H  E2 `[[:space:]][[:space:]]*` -> `[[:space:]]*`  (one-or-more becomes
#        zero-or-more, so `x#word` becomes strippable)
#
# Measured on the real tree with the same construct planted in
# scripts/lib/freshness-detect.sh: shipped lint rc=1, M-A/M-B/M-H rc=0 each.
# If this case is ever deleted or its `#` given a leading space, all three
# holes re-open silently — which is precisely how BL-181 was re-opened three
# times.
setup_fixture
{
  printf '#!/usr/bin/env bash\n'
  printf 'echo "ref=x#delta-state.sh"\n'
} > "$TMP/scripts/check-gate.sh"
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'scripts/check-gate\.sh:2'; then
  pass "X8: a delta token AFTER a mid-word '#' is still on an executed line"
else
  fail_ "X8" "expected rc=1 — an over-stripping mutant eats the token; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== L1: a T2 inline allow WITH a reason is honored -> exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# §3.3: T2 is deliberately coarse and will occasionally fire on prose in a
# string. The trade is explicit — a false positive costs one allowlist row
# with a reason; a false negative costs the severability property silently.
setup_fixture
{
  printf '#!/usr/bin/env bash\n'
  printf 'echo "unknown delta-class; see the policy file"  # lint-delta-boundary: allow prose in an operator message, not a reference\n'
} > "$TMP/scripts/check-gate.sh"
out=$(run_fixture); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "L1: reasoned inline allow suppresses the T2 hit"
else
  fail_ "L1" "expected rc=0; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== L2: a T2 inline allow with an EMPTY reason is rejected -> exit 1 ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
{
  printf '#!/usr/bin/env bash\n'
  printf 'echo "unknown delta-class"  # lint-delta-boundary: allow\n'
} > "$TMP/scripts/check-gate.sh"
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'reason'; then
  pass "L2: an empty allowlist reason fails and says so"
else
  fail_ "L2" "expected rc=1 mentioning the reason; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== L3: the seam file may reference delta paths -> exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/scripts/process-checklist.sh" <<'SH'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/delta-state.sh"
case "${1:-}" in
  --delta-open) delta_state_open "$@" ;;
esac
SH
out=$(run_fixture); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "L3: scripts/process-checklist.sh is the allowlisted seam"
else
  fail_ "L3" "expected rc=0; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== L4 (mutation m2): a SECOND seam allowlist entry -> exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# §3.3 clause 3: "The lint asserts the allowlist array has length 1 and fails
# if it grows. A second seam is a design change and must be argued, not
# merged." Executed here against a COPY so the real lint is never mutated.
# The fixture is CLEAN, so the ONLY thing that can red is the cardinality
# assertion — that is what makes this a proof and not a coincidence.
setup_fixture
COPY="$TMP/lint-copy-cardinality.sh"
awk '{ print }
     /^SEAM_ALLOWLIST=\(/ { print "  \"scripts/check-gate.sh|an invented second seam\"" }' \
  "$LINTER" > "$COPY"
out=$(bash "$COPY" --root "$TMP" 2>&1); rc=$?
# Control: the unmutated lint on the same fixture is green.
out_ctl=$(run_fixture); rc_ctl=$?
if [ "$rc" -eq 1 ] && [ "$rc_ctl" -eq 0 ] \
   && echo "$out" | grep -q -i 'cardinal'; then
  pass "L4: growing the seam allowlist reds on the cardinality assertion (control green)"
else
  fail_ "L4" "expected mutated rc=1 (cardinality) and control rc=0; rc=$rc rc_ctl=$rc_ctl; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== L5: a seam allowlist row with no reason -> exit 1 ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
COPY="$TMP/lint-copy-noreason.sh"
sed 's/^  "scripts\/process-checklist\.sh|.*$/  "scripts\/process-checklist.sh|"/' \
  "$LINTER" > "$COPY"
out=$(bash "$COPY" --root "$TMP" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'reason'; then
  pass "L5: a reasonless seam row fails the lint"
else
  fail_ "L5" "expected rc=1 mentioning the reason; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== L6: T1 is NOT inline-allowlistable -> exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# §3.3's tier table gives the inline allowlist to T2 only; T1 is
# "Unambiguous: a core file names a module file". The single sanctioned
# escape for a T1-class reference is the file-level seam, whose cardinality
# is pinned at one. Without this pin, the allowlist marker would quietly
# become a universal opt-out and clause 3 would mean nothing.
setup_fixture
{
  printf '#!/usr/bin/env bash\n'
  printf 'source "lib/delta-state.sh"  # lint-delta-boundary: allow it was easier\n'
} > "$TMP/scripts/check-gate.sh"
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ]; then
  pass "L6: an inline allow cannot suppress a T1 literal-path reference"
else
  fail_ "L6" "expected rc=1; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== L7: a near-miss allowlist marker does NOT allowlist -> exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# The marker is matched as an EXACT TOKEN, not as a prefix. Under a prefix
# test, `allowed because …` parses as marker + reason "ed because …" and
# waives the violation — a typo, or a sentence that merely starts with the
# right letters, becomes a silent opt-out. Exact-token matching fails CLOSED:
# a near-miss is not a marker, so the line stays a violation. Both spellings
# below are near-misses of the SAME token and must both be refused.
setup_fixture
{
  printf '#!/usr/bin/env bash\n'
  printf 'echo "unknown delta-class"  # lint-delta-boundary: allowed because it is prose\n'
  printf 'echo "another delta-class"  # lint-delta-boundary: allowlist prose too\n'
} > "$TMP/scripts/check-gate.sh"
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -q 'scripts/check-gate\.sh:2' \
   && echo "$out" | grep -q 'scripts/check-gate\.sh:3'; then
  pass "L7: 'allowed'/'allowlist' are not the 'allow' token — both stay violations"
else
  fail_ "L7" "expected rc=1 naming BOTH lines; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== V1 (vacuity floor): no delta-module file present -> exit 2 ==="
# ════════════════════════════════════════════════════════════════════
# The floor is the whole point: "a passing lint that proves nothing is worse
# than no lint". Asserted as exit 2 EXACTLY — 0 and 1 are both wrong answers
# and only the code distinguishes them.
setup_fixture
rm -f "$TMP/scripts/lib/delta-state.sh"
out=$(run_fixture); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "V1: a scan with no delta-module file exits 2, not 0"
else
  fail_ "V1" "expected rc=2; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== V2 (vacuity floor): no core file present -> exit 2 ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
rm -f "$TMP/init.sh" "$TMP/scripts/check-gate.sh" \
      "$TMP/scripts/lib/helpers-core.sh" "$TMP/scripts/hooks/record-thing.sh"
out=$(run_fixture); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "V2: a scan with no core file exits 2, not 0"
else
  fail_ "V2" "expected rc=2; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== V3 (mutation m3): an EMPTY delta manifest -> exit 2, not 0 ==="
# ════════════════════════════════════════════════════════════════════
# Run against the REAL repo root, so this also proves the floor is what stops
# a manifest-shaped regression on the tree we actually ship.
setup_fixture
COPY="$TMP/lint-copy-emptymanifest.sh"
awk '
  /DELTA-BOUNDARY-MANIFEST-BEGIN/ { skip = 1 }
  /DELTA-BOUNDARY-MANIFEST-END/   { skip = 0; print "DELTA_MANIFEST=()"; print; next }
  skip != 1 { print }
  skip == 1 && /DELTA-BOUNDARY-MANIFEST-BEGIN/ { print }
' "$LINTER" > "$COPY"
out=$(bash "$COPY" --root "$REPO_ROOT" 2>&1); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "V3: emptying the DELTA manifest exits 2 on the real tree"
else
  fail_ "V3" "expected rc=2; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== I1: --list emits the STATUS table and the population row ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/scripts/check-gate.sh" <<'SH'
#!/usr/bin/env bash
source "lib/delta-state.sh"
SH
out=$(run_fixture_list); rc=$?
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -q '^STATUS' \
   && echo "$out" | grep -q '^FAIL' \
   && echo "$out" | grep -q 'population' \
   && echo "$out" | grep -q 'seam'; then
  pass "I1: --list prints the header, the FAIL row, the seam row and the population row"
else
  fail_ "I1" "expected the full --list shape; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== I2: an unknown flag -> exit 2 ==="
# ════════════════════════════════════════════════════════════════════
out=$(bash "$LINTER" --not-a-flag 2>&1); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "I2: unknown flag exits 2"
else
  fail_ "I2" "expected rc=2; rc=$rc; output:\n$out"
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== I3: the REAL tree passes -> exit 0 ==="
# ════════════════════════════════════════════════════════════════════
out=$(bash "$LINTER" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "I3: the real repository has no core -> delta edge"
else
  fail_ "I3" "expected rc=0 on the real tree; rc=$rc; output:\n$out"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
