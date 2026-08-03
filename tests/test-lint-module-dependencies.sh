#!/usr/bin/env bash
# tests/test-lint-module-dependencies.sh
#
# Behavior tests for scripts/lint-module-dependencies.sh — the module-dependency
# lint for the BROWNFIELD module set (Scout + the adoption driver), specified by
# docs/designs/2026-08-02-brownfield-adoption-v1.md §3.3 (M1-M5) and transcribed
# as a contract in docs/module-contract.md.
#
# Each case stages a hermetic mini-tree under mktemp -d, points the lint at it
# with --root, and asserts on the EXIT CODE (never on a printed label — the
# repo's [WARN] trap is that labels and exit predicates disagree).
#
# This suite is a SIBLING of tests/test-lint-delta-boundary.sh and deliberately
# inherits its discipline, including two adversarial-review rounds of lessons it
# paid for. Where the two lints genuinely differ, the difference is MEASURED and
# recorded below rather than copied over — see the X6 note in particular.
#
# WHAT THE SUITE PINS, and which named mutant each row kills
#
#   DIRECTION — M3, `core -> module` forbidden
#     D1  clean tree                                          -> 0
#     D2  core names a literal module dir (T1)                -> 1   kills M-DIR
#     D3  `$SCRIPT_DIR/lib/scout/${p}.sh` composition (T2)    -> 1   kills M-T2S
#     D4  `$SCRIPT_DIR/lib/adopt/${p}.sh` composition (T2)    -> 1   kills M-T2A
#     D5  core invokes the scout entry script (T1 basename)   -> 1
#     D6  core invokes the adopt entry script (T1 basename)   -> 1
#     D7  `module -> core` is permitted for the DRIVER        -> 0
#     D8  T1 and T2 do not double-report the same line        -> exactly one row
#
#   SURFACE — the four CORE globs, minus module files and BOTH boundary lints
#     S1  init.sh is scanned
#     S2  scripts/hooks/*.sh is scanned
#     S3  scripts/lib/*.sh (non-module members) is scanned
#     S4  the two boundary lints are NOT scanned (self + sibling exclusion)
#     A narrowed surface would pass D1-D8 while seeing nothing; S1-S3 are the
#     anti-vacuity pins for the CORE half specifically.
#
#   M5 — the scanner depends on NOTHING
#     M1  a scout module file sourcing a core lib             -> 1   kills M-M5
#     M2  the scout ENTRY script sourcing a core lib          -> 1
#     M3  an ADOPT module file sourcing a core lib            -> 0
#         (M5 is scout-only; the driver may source core, like the delta module)
#     M4  M5 is not inline-allowlistable                      -> 1
#
#   THE EXECUTED-LINES STRIPPER
#     Same predicate, same scar tissue: CLAUDE.md records that a ONE-CHARACTER
#     narrowing of the sibling predicate in scripts/lint-tests-registered.sh
#     (`# BL-181-UNIT-LANE-PREDICATE`) re-opened the same hole THREE times while
#     passing both PR-blocking checks each time. The pins below name each ATOM
#     of the two sed expressions and pin its WIDTH and its SPELLING, not merely
#     its presence.
#
#     TWO DIRECTIONS, AND ONLY ONE OF THEM IS CHEAP TO CATCH:
#       • NARROWING (strips too LITTLE) leaves comments looking executed ->
#         FALSE POSITIVES. Any exit-0 fixture catches it. X2/X3/X4/X5/X9 are
#         all of this kind and they are easy.
#       • WIDENING (strips too MUCH) eats executed code -> FALSE NEGATIVES. NO
#         exit-0 fixture can ever see it, because an over-stripped tree is a
#         QUIETER tree. It is caught only by a VIOLATION fixture whose token
#         sits where the widened match would reach. X8 and X10 are those
#         fixtures and they are the load-bearing ones. This suite ships them
#         from day one rather than relearning the lesson.
#
#       E1 = 's/^[[:space:]]*#.*$//'                     (whole-line comments)
#         C1  the `^` anchor          -> pinned by X8, NOT by X7. Dropping `^`
#             blanks nothing: sed's s/// replaces only the MATCHED REGION, so
#             the leftmost match simply starts at the `#` and `x#token`
#             truncates to `x`. A widening — only a violation fixture sees it.
#             (Mutant M-A.)
#         C2  `[[:space:]]*` WIDTH    -> pinned by X2 (0, 1, 4, 8 spaces, tab,
#             tab+spaces). `*` cannot be widened further, so C2's only failure
#             mode is the narrowing X2 catches.
#         C3  `#` SPELLING            -> pinned by X3 (no space after `#`).
#         C4  the WHOLE-EXPRESSION widening (`s/#.*$//`) -> pinned by X8.
#             (Mutant M-B.)
#
#       E2 = 's/\([^[:space:]]\)[[:space:]][[:space:]]*#.*$/\1/'  (trailing)
#         C5  `[[:space:]][[:space:]]*` WIDTH -> pinned in BOTH directions:
#               narrowing to two-or-more false-positives on the single-space
#               form -> X4;
#               widening to zero-or-more makes `x#token` strippable -> X8.
#               (Mutant M-H.)
#         C6  `#` SPELLING            -> pinned by X5.
#         C7  `\([^[:space:]]\)` guard + `\1` back-reference — the executed
#             PREFIX must survive -> pinned at TWO resolutions:
#               X1 (COARSE): a mutation that discards the whole line whenever a
#               trailing comment is present (M-C7C) loses the violation
#               outright. Measured: M-C7C kills X1, X6, M4, L2, L4 and L5.
#               X6 (FINE): dropping the capture (M-C7F) eats exactly ONE
#               character. Measured: kills X6 and nothing else.
#             Both are kept: an edit that eats everything and one that eats a
#             single byte are different mutations and X1 cannot see the latter.
#
#             MEASURED DIFFERENCE FROM THE DELTA SUITE, recorded rather than
#             copied. There, dropping the capture merely DEMOTES a hit from T1
#             to T2, so the exit code cannot see it and X6 must assert the
#             TIER. Here it is rc-VISIBLE instead, because this lint's T2
#             directory tokens are a SUFFIX-SUBSET of its T1 set (`scout/` is a
#             suffix of `scripts/lib/scout/`; the two entry tokens are
#             IDENTICAL in both tiers). Eating the last character of a line
#             that ENDS at a module token therefore breaks T1 and T2 together
#             and the line goes green.
#             X6's FIXTURE QUOTING IS PART OF THE PIN — see the case body. The
#             first draft quoted the path, M-C7F ate the closing `"` instead of
#             the token's slash, and the mutant survived at 39/0.
#         C8  `#` INSIDE a word is not a comment -> pinned by X7 and X8, which
#             cover OPPOSITE failure modes and are deliberately not folded:
#               X7 = the DELETION direction (token BEFORE the `#`; a `grep -v`
#               refactor drops the whole line). X7 does NOT pin over-stripping.
#               X8 = the TRUNCATION direction (token AFTER the `#`).
#
#     X9/X10 pin the SAME stripper on the M5 arm, which is a second, independent
#     call site. A stripper fix applied to one arm and not the other is exactly
#     the kind of half-edit these two catch.
#
#   ALLOWLISTS
#     L1  T2 inline allow WITH a reason is honored             -> 0
#     L2  T2 inline allow with an EMPTY reason                 -> 1
#     L3  the core allowlist's cardinality is exactly ZERO     -> 1 when it grows
#         (mutation M-CARD, executed against a lint COPY)
#     L4  T1 is NOT inline-allowlistable
#     L5  a NEAR-MISS marker (`allowed`, `allowlist`) does not allowlist -> 1
#
#   VACUITY FLOOR
#     V1  no module file present                               -> 2
#     V2  no core file present                                 -> 2
#     V3  mutation M-MAN: empty the MODULE manifest in a lint COPY, run against
#         the REAL repo root                                   -> 2 (not 0)
#     V4  zero-dependency module files present but NO core lib -> 2
#         (the M5 arm's own anti-vacuity clause: an empty forbidden-token set
#         would let M5 pass trivially)
#
#   MANIFEST EROSION
#     E1  deleting a manifest ROW does not fully disarm the lint: the T2 token
#         list is an INDEPENDENT literal, so an entry-script reference is still
#         caught. This is the reason the two entry tokens appear in BOTH tiers
#         despite looking redundant — without this case that redundancy is
#         unjustified dead weight.
#
#   INTERFACE
#     I1  --list emits the STATUS table incl. the population INFO row
#     I2  an unknown flag                                      -> 2
#     I3  the REAL tree passes                                 -> 0
#
# HAZARD NOTE — why this file may safely contain module paths.
# The lint's CORE surface is init.sh + scripts/*.sh + scripts/lib/*.sh +
# scripts/hooks/*.sh. tests/ is NOT in it, so the literals below never become
# violations on the real tree. (Contrast tests/test-lint-bl-markers.sh, whose
# fixtures DO land in that lint's surface and must be built by concatenation.)
#
# Style mirrors tests/test-lint-delta-boundary.sh: set -uo pipefail, mktemp
# fixtures, pass/fail counters, teardown after each case, bash 3.2 only.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINTER="$REPO_ROOT/scripts/lint-module-dependencies.sh"

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
# A minimal tree carrying every population the floors demand: CORE files, a
# CORE LIB (so the M5 forbidden-token set is non-empty), and BOTH module
# halves (so the module floor is met and the scout/adopt asymmetry is
# exercisable).
setup_fixture() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/scripts/lib" "$TMP/scripts/hooks" \
           "$TMP/scripts/lib/scout" "$TMP/scripts/lib/adopt"
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
  # The MODULE half of the floor: the scout module (zero-dependency by M5)
  # and the adoption driver's lib (module -> core permitted).
  cat > "$TMP/scripts/lib/scout/scout-core.sh" <<'SH'
#!/usr/bin/env bash
scout_probe() { echo "probe"; }
SH
  cat > "$TMP/scripts/lib/adopt/adopt-core.sh" <<'SH'
#!/usr/bin/env bash
adopt_run() { echo "run"; }
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
echo "=== D2 (mutant M-DIR): core names a literal module path (T1) -> 1 ==="
# ════════════════════════════════════════════════════════════════════
# M3's worked example: someone adds a convenience source line to a core gate
# script on a Tuesday and severability is gone with no test failing. Deleting
# the direction check makes this case pass — that is mutation m1.
setup_fixture
cat > "$TMP/scripts/check-gate.sh" <<'SH'
#!/usr/bin/env bash
REPO="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO/scripts/lib/scout/scout-core.sh"
echo "gate"
SH
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -q 'scripts/check-gate\.sh:3' \
   && echo "$out" | grep -q 'scripts/lib/scout/'; then
  pass "D2: T1 literal-path reference exits 1 naming file:line and the token"
else
  fail_ "D2" "expected rc=1 + check-gate.sh:3 + the token; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== D3 (mutant M-T2S): '\$SCRIPT_DIR/lib/scout/' composition -> T2, 1 ==="
# ════════════════════════════════════════════════════════════════════
# The measured reason T2 exists for a DIRECTORY module. `$SCRIPT_DIR/lib/...`
# is the house's dominant sourcing idiom (17 of the top call sites in
# scripts/*.sh spell it that way), and it carries NO `scripts/` segment — so
# T1's full-prefix token `scripts/lib/scout/` cannot see it. Drop the `scout/`
# T2 token and this case goes green. S3 covers the sibling spelling
# (`$LIBDIR/scout/`) that a narrower `lib/scout/` token would still miss.
setup_fixture
cat > "$TMP/scripts/check-gate.sh" <<'SH'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
part="core"
source "$SCRIPT_DIR/lib/scout/scout-${part}.sh"
echo "gate"
SH
out=$(run_fixture_list); rc=$?
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -q '^FAIL.*T2.*scripts/check-gate\.sh:4'; then
  pass "D3: '\$SCRIPT_DIR/lib/scout/' composition caught at tier T2"
else
  fail_ "D3" "expected rc=1 with a T2 row for line 4; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== D4 (mutant M-T2A): '\$SCRIPT_DIR/lib/adopt/' composition -> T2, 1 ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/scripts/hooks/record-thing.sh" <<'SH'
#!/usr/bin/env bash
D="$(cd "$(dirname "$0")/.." && pwd)"
kind="core"
. "$D/lib/adopt/adopt-${kind}.sh"
SH
out=$(run_fixture_list); rc=$?
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -q '^FAIL.*T2.*scripts/hooks/record-thing\.sh:4'; then
  pass "D4: '\$D/lib/adopt/' composition caught at tier T2"
else
  fail_ "D4" "expected rc=1 with a T2 row for line 4; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== D5: core invokes the scout ENTRY script -> exit 1 ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/init.sh" <<'SH'
#!/usr/bin/env bash
bash "$SCRIPT_DIR/scripts/scout.sh" --report
SH
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'init\.sh:2'; then
  pass "D5: a core file invoking scout.sh is a violation"
else
  fail_ "D5" "expected rc=1 naming init.sh:2; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== D6: core invokes the adopt ENTRY script -> exit 1 ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/scripts/check-gate.sh" <<'SH'
#!/usr/bin/env bash
bash "$(dirname "$0")/adopt-project.sh" --resume
SH
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'scripts/check-gate\.sh:2'; then
  pass "D6: a core file invoking adopt-project.sh is a violation"
else
  fail_ "D6" "expected rc=1 naming check-gate.sh:2; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== D7: 'module -> core' is permitted for the DRIVER -> exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# M3 clause 1. The driver is severable, not isolated: it may source core libs
# and name core paths freely. Only the SCANNER is zero-dependency (M5).
setup_fixture
cat > "$TMP/scripts/lib/adopt/adopt-core.sh" <<'SH'
#!/usr/bin/env bash
. "$(dirname "$0")/../helpers-core.sh"
. "$(dirname "$0")/../enforcement-level.sh"
adopt_run() { helper; }
SH
cat > "$TMP/scripts/adopt-project.sh" <<'SH'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/helpers-core.sh"
source "$SCRIPT_DIR/lib/adopt/adopt-core.sh"
SH
out=$(run_fixture); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "D7: the adoption driver may source core and its own module dir"
else
  fail_ "D7" "expected rc=0; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== D8: a T1 line is not ALSO reported as T2 (tier discrimination) ==="
# ════════════════════════════════════════════════════════════════════
# Double-reporting would inflate the count and make the operator chase one
# defect twice. It also matters semantically: T2 is inline-allowlistable and
# T1 is not, so a duplicated row offers a waiver for an unwaivable finding.
setup_fixture
cat > "$TMP/scripts/check-gate.sh" <<'SH'
#!/usr/bin/env bash
source "scripts/lib/scout/scout-core.sh"
SH
out=$(run_fixture_list); rc=$?
rows=$(echo "$out" | grep -c 'scripts/check-gate\.sh:2')
if [ "$rc" -eq 1 ] && [ "$rows" -eq 1 ]; then
  pass "D8: the T1 line yields exactly one row (no T2 double-report)"
else
  fail_ "D8" "expected rc=1 and exactly 1 row for that line; rc=$rc rows=$rows; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== S1: init.sh is inside the CORE surface ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/init.sh" <<'SH'
#!/usr/bin/env bash
cp -R "$SRC/scripts/lib/scout/" "$TARGET/scripts/lib/"
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
bash scripts/adopt-project.sh --audit
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
echo "=== S3: scripts/lib/*.sh non-module members are inside CORE, and the"
echo "    '\$LIBDIR/scout/' spelling is caught -> exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# TWO PINS IN ONE FIXTURE, and the second one was EARNED rather than designed.
#
# The surface pin: scripts/lib/*.sh members that are not module files are core
# and must be scanned.
#
# The token pin: this case was written with the natural `$LIBDIR/scout/…`
# spelling — a variable that already ends in `lib` — and it FAILED against the
# lint's first draft, whose T2 token was `lib/scout/`. That token only covers
# the `$SCRIPT_DIR/lib/…` idiom; it is blind to this one, and T1's
# `scripts/lib/scout/` is blind to both. The fix was to make T2's directory
# tokens bare path SEGMENTS (`scout/`, `adopt/`), which closes the whole
# variable-prefix family. Narrow either token back to `lib/scout/` and this
# case goes green again — it is the pin for that decision, not incidental
# coverage.
setup_fixture
cat > "$TMP/scripts/lib/helpers-core.sh" <<'SH'
#!/usr/bin/env bash
helper() { . "$LIBDIR/scout/scout-core.sh"; }
SH
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'scripts/lib/helpers-core\.sh:2'; then
  pass "S3: a non-module scripts/lib member is scanned, and '\$LIBDIR/scout/' is caught"
else
  fail_ "S3" "expected rc=1 naming helpers-core.sh:2; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== S4: BOTH boundary lints are outside the CORE surface -> exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# Each boundary lint names every path of the module it guards, by construction.
# This lint self-excludes (SELF_REL) and excludes its delta-track sibling for
# the same reason — the sibling's manifest and prose are lint infrastructure,
# not a core dependency edge. Both exclusions are by EXACT PATH, so a renamed
# copy elsewhere in scripts/ is still scanned and still reds: fail-closed is
# the right direction for a boundary lint.
setup_fixture
{
  printf '#!/usr/bin/env bash\n'
  printf 'MODULE_MANIFEST=("scripts/lib/scout/" "scripts/adopt-project.sh")\n'
} > "$TMP/scripts/lint-module-dependencies.sh"
{
  printf '#!/usr/bin/env bash\n'
  printf 'echo "sibling lint mentions scripts/lib/adopt/ and scout.sh"\n'
} > "$TMP/scripts/lint-delta-boundary.sh"
out=$(run_fixture); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "S4: neither boundary lint is scanned as a core file"
else
  fail_ "S4" "expected rc=0; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== M1 (mutant M-M5): a scout module file sourcing a core lib -> 1 ==="
# ════════════════════════════════════════════════════════════════════
# M5: "The scanner sources NO core lib. Its bootstrap must work in a clone that
# has never run init.sh." This is mutation m4 executed as a permanent test:
# neuter the M5 arm and this fixture passes, silently converting Scout from a
# standalone survey tool into something that only runs inside an installed
# framework — the exact property §3.1 says makes "let me just look" cost
# nothing.
setup_fixture
cat > "$TMP/scripts/lib/scout/scout-core.sh" <<'SH'
#!/usr/bin/env bash
. "$(dirname "$0")/../helpers-core.sh"
scout_probe() { helper; }
SH
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -q 'scripts/lib/scout/scout-core\.sh:2' \
   && echo "$out" | grep -q 'M5'; then
  pass "M1: a scout module file sourcing a core lib is an M5 violation"
else
  fail_ "M1" "expected rc=1 + the file:line + an M5 tier; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== M2: the scout ENTRY script is inside the M5 surface -> exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# M5 binds the module, not just its lib subtree. An arm that only walked
# scripts/lib/scout/ would let the entry script — the very file a bootstrap
# invocation runs — source anything it liked.
setup_fixture
cat > "$TMP/scripts/scout.sh" <<'SH'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/helpers-core.sh"
SH
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'scripts/scout\.sh:3'; then
  pass "M2: the scout entry script is bound by M5"
else
  fail_ "M2" "expected rc=1 naming scripts/scout.sh:3; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== M3: M5 is SCOUT-ONLY — the adopt module may source core -> 0 ==="
# ════════════════════════════════════════════════════════════════════
# The bound matters as much as the rule. An M5 arm applied to every module
# would forbid the driver from using helpers-core.sh, which §3.3 explicitly
# permits (module -> core is direction-legal; only the SCANNER is isolated).
# This is the exemption half of the dual-direction proof.
setup_fixture
cat > "$TMP/scripts/lib/adopt/adopt-core.sh" <<'SH'
#!/usr/bin/env bash
. "$(dirname "$0")/../helpers-core.sh"
. "$(dirname "$0")/../enforcement-level.sh"
adopt_run() { helper; }
SH
out=$(run_fixture); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "M3: the adopt module sourcing core libs is not an M5 violation"
else
  fail_ "M3" "expected rc=0 — M5 must be scout-only; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== M4: M5 is NOT inline-allowlistable -> exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# "Depends on nothing" has no reasoned exceptions — a waived dependency is a
# dependency. If the marker worked here it would become the standard way to
# add "just one" core call, which is the fusion-by-a-thousand-cuts this whole
# lint exists to stop.
setup_fixture
cat > "$TMP/scripts/lib/scout/scout-core.sh" <<'SH'
#!/usr/bin/env bash
. "$(dirname "$0")/../helpers-core.sh"  # lint-module-dependencies: allow it was easier
SH
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ]; then
  pass "M4: an inline allow cannot waive an M5 zero-dependency violation"
else
  fail_ "M4" "expected rc=1; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== X1 (atom C7, coarse form): stripping a trailing comment must leave"
echo "    the EXECUTED PREFIX intact -> exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# Mutate E2 to `s/.*[[:space:]][[:space:]]*#.*$//` — which discards the whole
# line whenever a trailing comment is present — and this case goes RED. X1 is
# the COARSE form of the C7 pin and X6 is the FINE one.
setup_fixture
{
  printf '#!/usr/bin/env bash\n'
  printf 'source "$SCRIPT_DIR/lib/scout/scout-core.sh"  # convenience, just this once\n'
} > "$TMP/scripts/check-gate.sh"
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
  printf '# source "$SCRIPT_DIR/lib/scout/scout-core.sh" would fuse the module\n'
  printf ' # one space: scripts/lib/adopt/adopt-core.sh\n'
  printf '    # four spaces: scripts/scout.sh\n'
  printf '        # eight spaces: scripts/adopt-project.sh\n'
  printf '%s# a tab: scripts/lib/scout/\n' "$TAB"
  printf '%s   # tab plus spaces: lib/adopt/\n' "$TAB"
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
setup_fixture
{
  printf '#!/usr/bin/env bash\n'
  printf '#source "$SCRIPT_DIR/lib/scout/scout-core.sh"\n'
  printf '    #source "$SCRIPT_DIR/lib/adopt/adopt-core.sh"\n'
  printf '%s#scripts/scout.sh sketch\n' "$TAB"
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
  printf 'echo one #see scripts/lib/scout/scout-core.sh\n'
  printf 'echo two  # see lib/adopt/adopt-core.sh\n'
  printf 'echo three%s# see scripts/scout.sh\n' "$TAB"
  printf 'echo four      # see scripts/adopt-project.sh and lib/scout/\n'
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
  printf 'echo one #lib/scout/scout-core.sh\n'
  printf 'echo two%s#scripts/adopt-project.sh\n' "$TAB"
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
echo "    character must survive the strip -> exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# Drop the `\([^[:space:]]\)` capture and the `\1` replacement — i.e. mutate
# E2 to `s/[^[:space:]][[:space:]][[:space:]]*#.*$//` (mutant M-C7F) — and the
# strip eats exactly ONE character of executed code: the last one before the
# whitespace that precedes the comment.
#
# THE FIXTURE'S QUOTING IS LOAD-BEARING, and the first version of this case got
# it wrong. It was written as
#     ls "$REPO/scripts/lib/scout/"   # inventory the module
# and M-C7F SURVIVED it — measured, 39/0 with the mutant installed. The
# character M-C7F eats there is the closing DOUBLE QUOTE, not the token's
# trailing slash, so `scripts/lib/scout/` was still intact on the stripped line
# and the case stayed green while the atom it claimed to pin was unpinned. This
# is the same failure the delta suite's adversarial review found in its own X1
# (R-WP1-2): a pin asserted by reasoning about sed rather than by running it.
# The line below is UNQUOTED so the final `/` is the last executed character,
# which is what M-C7F then eats. Re-verified by execution: M-C7F now dies here.
#
# HERE THE ATOM IS rc-VISIBLE, and the difference from the delta suite is
# measured, not assumed. In tests/test-lint-delta-boundary.sh the same mutation
# only DEMOTES a hit from T1 to T2 (the truncated token stops matching a
# literal path but still carries the `delta-` prefix), so X6 there must assert
# the TIER because rc cannot see it. This lint's T2 directory tokens are a
# SUFFIX-SUBSET of its T1 tokens — `scout/` is a suffix of
# `scripts/lib/scout/`, and the two entry tokens are identical across tiers —
# so eating the final `/` breaks BOTH tiers at once and the line goes green.
setup_fixture
{
  printf '#!/usr/bin/env bash\n'
  printf 'ls $REPO/scripts/lib/scout/   # inventory the module\n'
} > "$TMP/scripts/check-gate.sh"
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'scripts/check-gate\.sh:2'; then
  pass "X6: E2 keeps the last executed character, so the module token still matches"
else
  fail_ "X6" "expected rc=1; a capture-less E2 eats the trailing '/' and both tiers go blind; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== X7 (atom C8, whole-line-deletion direction): a line carrying a"
echo "    mid-word '#' is not discarded wholesale -> exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# `echo scripts/lib/scout/x.sh#frag` is a single bash WORD; bash executes it.
# This case guards the DELETION direction — a refactor to `grep -v '#'`, or an
# E1 rewritten as `s/^.*#.*$//`, drops the entire line and the reference with
# it. It does NOT guard the truncation direction: the token here sits BEFORE
# the `#`, so an over-stripping mutant leaves it intact and X7 still passes.
# X8 covers truncation, and the two are deliberately kept apart.
setup_fixture
{
  printf '#!/usr/bin/env bash\n'
  printf 'echo scripts/lib/scout/scout-core.sh#fragment\n'
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
echo "=== X8 (atoms C1/C4/C5/C8, the OVER-STRIP direction): a module token"
echo "    AFTER a mid-word '#' must still be seen -> exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# THE CASE THAT PINS THE STRIPPER'S UPPER BOUND, shipped with the suite rather
# than added after a regression. Every other X case pins a NARROWING (the
# stripper doing too little, producing false positives, which any exit-0
# fixture catches). This one pins a WIDENING — the stripper doing too MUCH,
# silently eating executed code, which no exit-0 fixture can ever see because
# an over-stripped tree is a QUIETER tree.
#
# `echo "ref=x#scripts/lib/scout/scout-core.sh"` is one bash WORD after `ref=`:
# bash does not treat that `#` as a comment (a comment `#` must start a word),
# so the module path is genuinely referenced on an executed line. Three
# separate one-character-class mutations all make the stripper eat from that
# `#` onward:
#
#   M-A  E1 `s/^[[:space:]]*#.*$//` -> `s/[[:space:]]*#.*$//`  (drop `^`)
#        sed's s/// replaces only the MATCHED REGION, not the line, so the
#        leftmost match simply starts at the `#` and truncates there.
#   M-B  E1 -> `s/#.*$//`                              (strip from any `#`)
#   M-H  E2 `[[:space:]][[:space:]]*` -> `[[:space:]]*`  (one-or-more becomes
#        zero-or-more, so `x#word` becomes strippable)
#
# All three survive every other case in this file. If this case is ever deleted
# or its `#` given a leading space, all three holes open silently — which is
# precisely how BL-181 was re-opened three times.
setup_fixture
{
  printf '#!/usr/bin/env bash\n'
  printf 'echo "ref=x#scripts/lib/scout/scout-core.sh"\n'
} > "$TMP/scripts/check-gate.sh"
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'scripts/check-gate\.sh:2'; then
  pass "X8: a module token AFTER a mid-word '#' is still on an executed line"
else
  fail_ "X8" "expected rc=1 — an over-stripping mutant eats the token; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== X9 (M5 arm, NARROWING direction): a commented core-lib mention in a"
echo "    scout file is not a dependency -> exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# The M5 arm is a SECOND, independent call site of the same stripper. A fix or
# a regression applied to one arm and not the other is exactly the half-edit
# X9/X10 exist to catch — and M5's whole point is that Scout re-implements what
# it needs, so its files WILL carry comments naming the core libs they
# deliberately do not use.
setup_fixture
{
  printf '#!/usr/bin/env bash\n'
  printf '# M5: deliberately does NOT source scripts/lib/helpers-core.sh\n'
  printf '    # nor host.sh, nor enforcement-level.sh\n'
  printf 'scout_probe() { echo "probe"; }  # not helpers-core.sh\n'
} > "$TMP/scripts/lib/scout/scout-core.sh"
out=$(run_fixture); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "X9: commented core-lib mentions in a scout file are not dependencies"
else
  fail_ "X9" "expected rc=0 — the M5 arm must use the same stripper; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== X10 (M5 arm, WIDENING direction): a core-lib token AFTER a mid-word"
echo "    '#' in a scout file is still a dependency -> exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# X9's mirror, and the load-bearing half. Without it, an over-stripping mutant
# applied to the M5 arm makes Scout look zero-dependency while it sources
# whatever it likes — the quieter-tree failure mode again, on the arm the
# design calls "the load-bearing one".
setup_fixture
{
  printf '#!/usr/bin/env bash\n'
  printf 'src="$D#helpers-core.sh"; . "$src"\n'
} > "$TMP/scripts/lib/scout/scout-core.sh"
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'scripts/lib/scout/scout-core\.sh:2'; then
  pass "X10: a core-lib token after a mid-word '#' is still an M5 dependency"
else
  fail_ "X10" "expected rc=1 — an over-stripping mutant on the M5 arm eats it; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== L1: a T2 inline allow WITH a reason is honored -> exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# T2 is deliberately coarse and will occasionally fire on prose in a string.
# The trade is explicit — a false positive costs one allowlist row with a
# reason; a false negative costs the severability property silently.
setup_fixture
{
  printf '#!/usr/bin/env bash\n'
  printf 'echo "run lib/scout/ yourself to survey first"  # lint-module-dependencies: allow prose in an operator message, not a reference\n'
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
  printf 'echo "run lib/adopt/ yourself"  # lint-module-dependencies: allow\n'
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
echo "=== L3 (mutation M-CARD): the core allowlist's cardinality is ZERO ==="
# ════════════════════════════════════════════════════════════════════
# §3.1 + the WP0 convergence decision: the brownfield module has NO seam. The
# in-core enabling arms of §3.2 (WP3) read an `adopted` flag and never source
# module code, so they are ordinary core files, not allowlisted seams. The
# array's length IS the assertion and it starts — and must stay — at zero.
# Growing it is a design change to be argued in §3.1, not a row to append.
#
# Executed here against a COPY so the real lint is never mutated. The fixture
# is CLEAN, so the ONLY thing that can red is the cardinality assertion — that
# is what makes this a proof and not a coincidence.
#
# NOTE ON THE MUTATION MECHANISM, because the first version of this case was a
# FALSE PROOF. The delta suite's sibling mutation appends a row after the
# `SEAM_ALLOWLIST=(` opening line, which works because that array spans several
# lines. This array is EMPTY, so it is written closed on one line —
# `CORE_ALLOWLIST=()` — and appending after it emitted the row as a COMMAND,
# not an element. The array stayed empty, the lint stayed green, and the case
# reported a failure to grow the allowlist rather than a failure of the
# assertion. The mutation now REWRITES the whole declaration, and `grew` below
# asserts the mutant really is mutated, so a no-op edit can never be read as a
# proof again.
setup_fixture
COPY="$TMP/lint-copy-cardinality.sh"
awk '/^CORE_ALLOWLIST=\(\)$/ {
       print "CORE_ALLOWLIST=("
       print "  \"scripts/check-gate.sh|an invented seam\""
       print ")"
       next
     }
     { print }' "$LINTER" > "$COPY"
grew=$(grep -c 'an invented seam' "$COPY")
out=$(bash "$COPY" --root "$TMP" 2>&1); rc=$?
# Control: the unmutated lint on the same fixture is green.
out_ctl=$(run_fixture); rc_ctl=$?
if [ "$rc" -eq 1 ] && [ "$rc_ctl" -eq 0 ] && [ "$grew" -eq 1 ] \
   && echo "$out" | grep -q -i 'cardinal'; then
  pass "L3: growing the core allowlist reds on the cardinality assertion (control green)"
else
  fail_ "L3" "expected mutated rc=1 (cardinality), control rc=0, grew=1; rc=$rc rc_ctl=$rc_ctl grew=$grew; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== L4: T1 is NOT inline-allowlistable -> exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# The inline allowlist belongs to T2 only. T1 is unambiguous — a core file
# names a module file — and the brownfield module has no sanctioned escape at
# all, because its allowlist cardinality is zero. Without this pin the marker
# would quietly become a universal opt-out and the zero would mean nothing.
setup_fixture
{
  printf '#!/usr/bin/env bash\n'
  printf 'source "scripts/lib/scout/scout-core.sh"  # lint-module-dependencies: allow it was easier\n'
} > "$TMP/scripts/check-gate.sh"
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ]; then
  pass "L4: an inline allow cannot suppress a T1 literal-path reference"
else
  fail_ "L4" "expected rc=1; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== L5: a near-miss allowlist marker does NOT allowlist -> exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# The marker is matched as an EXACT TOKEN, not as a prefix. Under a prefix
# test, `allowed because …` parses as marker + reason "ed because …" and waives
# the violation — a typo, or a sentence that merely starts with the right
# letters, becomes a silent opt-out. Exact-token matching fails CLOSED.
setup_fixture
{
  printf '#!/usr/bin/env bash\n'
  printf 'echo "see lib/scout/"  # lint-module-dependencies: allowed because it is prose\n'
  printf 'echo "see lib/adopt/"  # lint-module-dependencies: allowlist prose too\n'
} > "$TMP/scripts/check-gate.sh"
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -q 'scripts/check-gate\.sh:2' \
   && echo "$out" | grep -q 'scripts/check-gate\.sh:3'; then
  pass "L5: 'allowed'/'allowlist' are not the 'allow' token — both stay violations"
else
  fail_ "L5" "expected rc=1 naming BOTH lines; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== V1 (vacuity floor): no module file present -> exit 2 ==="
# ════════════════════════════════════════════════════════════════════
# The floor is the whole point: a passing lint that proves nothing is worse
# than no lint (CLAUDE.md's BL-104 scar — an empty manifest scored better than
# no manifest). Asserted as exit 2 EXACTLY: 0 and 1 are both wrong answers and
# only the code distinguishes them.
setup_fixture
rm -rf "$TMP/scripts/lib/scout" "$TMP/scripts/lib/adopt"
out=$(run_fixture); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "V1: a scan with no module file exits 2, not 0"
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
echo "=== V3 (mutation M-MAN): an EMPTY module manifest -> exit 2, not 0 ==="
# ════════════════════════════════════════════════════════════════════
# Run against the REAL repo root, so this also proves the floor is what stops a
# manifest-shaped regression on the tree we actually ship.
setup_fixture
COPY="$TMP/lint-copy-emptymanifest.sh"
awk '
  /MODULE-DEPS-MANIFEST-BEGIN/ { skip = 1; print; next }
  /MODULE-DEPS-MANIFEST-END/   { skip = 0; print "MODULE_MANIFEST=()"; print; next }
  skip != 1 { print }
' "$LINTER" > "$COPY"
out=$(bash "$COPY" --root "$REPO_ROOT" 2>&1); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "V3: emptying the MODULE manifest exits 2 on the real tree"
else
  fail_ "V3" "expected rc=2; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== V4 (M5 anti-vacuity): zero-dep module files but NO core lib -> 2 ==="
# ════════════════════════════════════════════════════════════════════
# The M5 arm's forbidden-token set is DERIVED from the scanned tree's
# scripts/lib/*.sh. If that set is empty the arm matches nothing and passes
# trivially — the same defect class as the main floor, one level down. A tree
# with a scout module and no core libs is therefore an error, not a pass.
setup_fixture
rm -f "$TMP/scripts/lib/helpers-core.sh"
out=$(run_fixture); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "V4: an empty M5 forbidden-token set exits 2, not 0"
else
  fail_ "V4" "expected rc=2; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== E1 (manifest erosion): deleting a manifest row does not disarm T2 ==="
# ════════════════════════════════════════════════════════════════════
# WHY THE TWO ENTRY TOKENS APPEAR IN BOTH TIERS. T1's tokens are DERIVED from
# the manifest, so the manifest and the tokens can never disagree — but that
# also means deleting a row disarms T1 for that path. T2's token list is an
# INDEPENDENT literal, so it still fires. Without this case that duplication is
# unjustified dead weight; with it, the duplication is a measured fail-closed
# property: the cheapest way to silence a violation (drop the manifest row)
# does not silence the lint.
setup_fixture
cat > "$TMP/scripts/check-gate.sh" <<'SH'
#!/usr/bin/env bash
bash "$(dirname "$0")/adopt-project.sh" --resume
SH
COPY="$TMP/lint-copy-erosion.sh"
grep -v '"adopt|scripts/adopt-project.sh"' "$LINTER" > "$COPY"
# Guard: the row really was removed, so a no-op grep cannot fake this pass.
removed=$(grep -c '"adopt|scripts/adopt-project.sh"' "$COPY")
out=$(bash "$COPY" --root "$TMP" --list 2>/dev/null); rc=$?
if [ "$rc" -eq 1 ] && [ "$removed" -eq 0 ] \
   && echo "$out" | grep -q '^FAIL.*T2.*scripts/check-gate\.sh:2'; then
  pass "E1: an eroded manifest still catches the entry script at tier T2"
else
  fail_ "E1" "expected rc=1 with a T2 row and the row removed; rc=$rc removed=$removed; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== I1: --list emits the STATUS table and the population row ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/scripts/check-gate.sh" <<'SH'
#!/usr/bin/env bash
source "scripts/lib/scout/scout-core.sh"
SH
out=$(run_fixture_list); rc=$?
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -q '^STATUS' \
   && echo "$out" | grep -q '^FAIL' \
   && echo "$out" | grep -q 'population' \
   && echo "$out" | grep -q 'allowlist'; then
  pass "I1: --list prints the header, the FAIL row, the allowlist row and the population row"
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
  pass "I3: the real repository has no core -> module edge and no M5 dependency"
else
  fail_ "I3" "expected rc=0 on the real tree; rc=$rc; output:\n$out"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
