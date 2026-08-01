#!/usr/bin/env bash
# tests/test-lint-bl-markers.sh
#
# Behavior tests for scripts/lint-bl-markers.sh — the BL-196 marker-citation
# backstop. Each case stages a hermetic tmpdir tree (a fake code surface, a
# fake backlog, fake prose), points the lint at it with --root, and asserts
# on exit code + diagnostics.
#
# CORE COVERAGE (the defect class BL-196 files)
#   • T2 (negative): prose cites a marker that exists nowhere in the code
#       surface -> exit 1, and the diagnostic NAMES the cite and where.
#   • T13 (mutation): excise the BL-196-PROSE-CITE fence from a copy of the
#       lint and T2's fixture PASSES -> the fence carries the whole check.
#
# SURROUNDING COVERAGE
#   • T1  clean tree -> exit 0
#   • T3  marker in code whose BL-NNN has no `## BL-NNN:` entry -> exit 1
#   • T4  FAMILY resolution: prose cites the fence family, code carries
#         -BEGIN/-END -> exit 0
#   • T5  glob form `# BL-...-*` resolves the same way -> exit 0
#   • T6  a TRUNCATION typo does NOT get rescued by the family rule
#   • T7  false-positive guards: bare prose hyphenation and the literal
#         `# BL-NNN-…` placeholder are not citations
#   • T8  frozen surfaces (Reports/, docs/handoffs/archive/) are out of scope
#   • T9  inline allow with a reason suppresses; an EMPTY reason fails
#   • T10 --list emits the STATUS table including the FAIL row
#   • T11 unknown flag -> exit 2
#   • T12 vacuity floor -> exit 2 (pass c)
#   • T-REPO / T-REPO-LIST: the real tree passes, and the script-level
#         allowlist is live (>=1 rendered allowlist row)
#
# A NOTE ON THIS SUITE'S OWN TEXT, because it is a real hazard here.
# This file lives under tests/, which IS the lint's code surface — every
# marker-shaped token written below becomes a marker DEFINITION on the real
# tree. Two consequences are designed around:
#   1. Fixture markers use the `BL-196-FIXTURE-*` family, so pass (a) on the
#      real tree resolves them to the existing `## BL-196:` entry.
#   2. The no-entry id for T3 is BUILT BY CONCATENATION and never appears
#      here as a literal. Writing it out would mint a marker on the real
#      tree naming an entry that does not exist, and this suite would red
#      the repo it is meant to guard.
# For the same reason no fixture cites a token that the real backlog also
# cites: a fixture literal would silently satisfy a real broken citation.
#
# Style mirrors tests/test-lint-doc-anchors.sh: set -uo pipefail, mktemp
# fixtures, pass/fail counters, teardown after each case.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINTER="$REPO_ROOT/scripts/lint-bl-markers.sh"

if [ ! -f "$LINTER" ]; then
  echo "FATAL: linter not found at $LINTER" >&2
  exit 2
fi

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# ── Fixture builder ─────────────────────────────────────────────────────
# A minimal tree with the shapes the lint cares about: one code dir, a
# backlog carrying two entry headers, and an empty docs/ ready for prose.
setup_fixture() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/scripts" "$TMP/docs"
  cat > "$TMP/solo-orchestrator-backlog.md" <<'MD'
# fixture backlog

## BL-196: fixture entry the fixture markers hang off

**Status:** Open

---

## BL-042: second fixture entry

**Status:** Closed — PR #1

---
MD
  cat > "$TMP/scripts/thing.sh" <<'SH'
#!/usr/bin/env bash
# BL-196-FIXTURE-LIVE: a marker that really is in the code surface.
echo live
# BL-196-FIXTURE-FENCE-BEGIN
echo fenced
# BL-196-FIXTURE-FENCE-END
SH
}
teardown_fixture() { rm -rf "$TMP"; }

run_fixture() { bash "$LINTER" --root "$TMP" 2>&1; return $?; }

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: prose cite that resolves exactly -> exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

The live arm is marked `# BL-196-FIXTURE-LIVE` — grep for it.
MD
out=$(run_fixture); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "OK:"; then
  pass "T1: resolving citation exits 0"
else
  fail_ "T1" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: prose cites a marker that exists nowhere -> exit 1, named ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

The live arm is marked `# BL-196-FIXTURE-LIVE` — grep for it.
The renamed arm is marked `# BL-196-FIXTURE-GHOST`, which no longer exists.
MD
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -q 'CLAUDE\.md:4' \
   && echo "$out" | grep -q 'BL-196-FIXTURE-GHOST'; then
  pass "T2: broken citation exits 1 naming the token AND file:line"
else
  fail_ "T2" "expected exit 1 + 'CLAUDE.md:4' + the ghost token; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: code marker whose BL-NNN has no backlog entry -> exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# The id is assembled at runtime so this suite's own text never mints a
# marker naming a nonexistent entry on the real tree (see header note).
setup_fixture
NOENT_ID="BL-9""97"
{
  printf '#!/usr/bin/env bash\n'
  printf '# %s-NO-SUCH-ENTRY: minted against an id nobody filed.\n' "$NOENT_ID"
  printf 'echo orphan\n'
} > "$TMP/scripts/orphan.sh"
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

The live arm is marked `# BL-196-FIXTURE-LIVE`.
MD
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -q 'scripts/orphan\.sh:2' \
   && echo "$out" | grep -q "no '## ${NOENT_ID}:' entry"; then
  pass "T3: marker naming a nonexistent entry exits 1 naming the site"
else
  fail_ "T3" "expected exit 1 + orphan.sh:2 + missing-entry text; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T4: FAMILY resolution — prose cites the fence family -> exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

The fenced arm is `# BL-196-FIXTURE-FENCE` (BEGIN/END in the code).
MD
out=$(run_fixture); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "OK:"; then
  pass "T4: family cite resolves against the -BEGIN/-END pair"
else
  fail_ "T4" "expected exit 0 for the family cite; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T5: glob form '# BL-...-*' resolves the same way -> exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

Per the fenced-arm template (`# BL-196-FIXTURE-FENCE-*`, no issues++).
MD
out=$(run_fixture); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "OK:"; then
  pass "T5: glob-suffixed family cite resolves"
else
  fail_ "T5" "expected exit 0 for the glob cite; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T6: a TRUNCATION typo is NOT rescued by the family rule ==="
# ════════════════════════════════════════════════════════════════════
# The family rule appends a HYPHEN before the prefix test, so a token that
# is merely a character-prefix of a live marker still fails. Without that
# hyphen this whole lint would accept any truncation.
setup_fixture
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

The fenced arm is `# BL-196-FIXTURE-FENC` — one character short.
MD
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'BL-196-FIXTURE-FENC'; then
  pass "T6: truncation typo still fails (family rule requires the hyphen)"
else
  fail_ "T6" "expected exit 1 for the truncated cite; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T7: bare prose hyphenation and the NNN placeholder are not cites ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

Cite code by a grep-able `# BL-NNN-…` marker comment, never a file:line.
This is the BL-042-family of entries, and the BL-042-class of defects;
the BL-042-correct reading is the one below. None of those is a citation.
MD
out=$(run_fixture); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "OK:"; then
  pass "T7: bare hyphenation + '# BL-NNN-…' placeholder produce zero hits"
else
  fail_ "T7" "a non-citation shape was flagged; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T8: frozen surfaces (Reports/, docs/handoffs/archive/) out of scope ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
mkdir -p "$TMP/Reports/2026-01-01-run" "$TMP/docs/handoffs/archive"
cat > "$TMP/Reports/2026-01-01-run/LEDGER.md" <<'MD'
# Frozen run artifact

Stamped at its own tree: `# BL-196-FIXTURE-GONE-FROM-MAIN`.
MD
cat > "$TMP/docs/handoffs/archive/2026-01-01-old.md" <<'MD'
# Superseded handoff

Also stamped: `# BL-196-FIXTURE-ALSO-GONE`.
MD
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

The live arm is marked `# BL-196-FIXTURE-LIVE`.
MD
out=$(run_fixture); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "OK:"; then
  pass "T8: frozen dated artifacts are not scanned"
else
  fail_ "T8" "a frozen surface was scanned; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T9a: inline allow WITH a reason suppresses the violation ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

The withdrawn arm was `# BL-196-FIXTURE-GHOST`. <!-- lint-bl-markers: allow lives on an unmerged branch -->
MD
out=$(run_fixture); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "OK:"; then
  pass "T9a: inline allow with a reason suppresses the broken cite"
else
  fail_ "T9a" "expected exit 0 under the inline allow; rc=$rc; output:\n$out"
fi
teardown_fixture

echo ""
echo "=== T9b: inline allow with an EMPTY reason still fails ==="
setup_fixture
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

The withdrawn arm was `# BL-196-FIXTURE-GHOST`. <!-- lint-bl-markers: allow -->
MD
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'EMPTY allowlist reason'; then
  pass "T9b: empty allowlist reason is itself a violation"
else
  fail_ "T9b" "expected exit 1 + empty-reason diagnostic; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T10: --list emits a STATUS table carrying the FAIL row ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

The renamed arm is `# BL-196-FIXTURE-GHOST`.
MD
out=$(bash "$LINTER" --root "$TMP" --list 2>&1); rc=$?
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -q 'STATUS' \
   && echo "$out" | grep -q 'FAIL.*BL-196-FIXTURE-GHOST.*broken citation' \
   && echo "$out" | grep -q 'INFO.*population'; then
  pass "T10: --list prints the STATUS table, the FAIL row and the population line"
else
  fail_ "T10" "expected --list header + FAIL row + INFO row; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T11: unknown flag -> exit 2 + usage ==="
# ════════════════════════════════════════════════════════════════════
out=$(bash "$LINTER" --bogus-flag 2>&1); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -q "Usage:"; then
  pass "T11: unknown flag rejected with exit 2 + usage"
else
  fail_ "T11" "expected exit 2 + usage; rc=$rc; output:\n$out"
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T12: vacuity floor (pass c) -> exit 2, not a silent pass ==="
# ════════════════════════════════════════════════════════════════════
# The fixture is clean, so without the floor this run would exit 0. With a
# floor above the fixture's population it must exit 2 instead — that is the
# whole point: a collapsed scan must never read as a pass.
setup_fixture
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

The live arm is marked `# BL-196-FIXTURE-LIVE`.
MD
out=$(bash "$LINTER" --root "$TMP" 2>&1); rc_clean=$?
out2=$(bash "$LINTER" --root "$TMP" --min-cites 999 2>&1); rc=$?
if [ "$rc_clean" -eq 0 ] && [ "$rc" -eq 2 ] && echo "$out2" | grep -q 'VACUOUS SCAN'; then
  pass "T12: population below the floor exits 2 where the same tree otherwise exits 0"
else
  fail_ "T12" "expected clean rc=0 then floored rc=2 + VACUOUS SCAN; rc_clean=$rc_clean rc=$rc; output:\n$out2"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T13 (MUTATION): excise the BL-196-PROSE-CITE fence -> T2 passes ==="
# ════════════════════════════════════════════════════════════════════
# The decisive check for BL-196's core defect class lives entirely inside
# the fence. Delete the fence and the broken-citation fixture must sail
# through — if it still fails, the check is not (only) where the comment
# says it is, and the mutation proves nothing.
m=$(grep -c 'BL-196-PROSE-CITE' "$LINTER") || m=0
case "$m" in ''|*[!0-9]*) m=0 ;; esac
MUTDIR=$(mktemp -d)
MUTL="$MUTDIR/lint.mut.sh"
sed '/BL-196-PROSE-CITE-BEGIN/,/BL-196-PROSE-CITE-END/d' "$LINTER" > "$MUTL"
l=$(grep -c 'BL-196-PROSE-CITE' "$MUTL") || l=0
case "$l" in ''|*[!0-9]*) l=0 ;; esac
setup_fixture
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

The renamed arm is `# BL-196-FIXTURE-GHOST`, which no longer exists.
MD
if [ "$m" -lt 2 ] || [ "$l" -ne 0 ]; then
  fail_ "T13" "excision vacuous (fence markers before=$m after=$l) — the fence is absent"
else
  out=$(bash "$MUTL" --root "$TMP" 2>&1); rc=$?
  if [ "$rc" -eq 0 ] && ! echo "$out" | grep -q 'BL-196-FIXTURE-GHOST'; then
    pass "T13: fence-excised mutant misses the broken cite — the fence carries the check"
  else
    fail_ "T13" "mutant still caught it (or broke, rc=$rc) — check does not live only in the fence:\n$out"
  fi
fi
teardown_fixture
rm -rf "$MUTDIR"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-REPO: the real tree passes -> exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# The merge gate. If this fails, either a new broken citation landed or a
# marker was renamed without updating the prose that points at it.
out=$(bash "$LINTER" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T-REPO: every live citation on the real tree resolves"
else
  fail_ "T-REPO" "the real tree has broken marker citations; rc=$rc; output:\n$out"
fi

echo ""
echo "=== T-REPO-LIST: the script-level allowlist is live and rendered ==="
out=$(bash "$LINTER" --list 2>&1); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'allowlist: '; then
  pass "T-REPO-LIST: --list renders at least one reasoned allowlist row"
else
  fail_ "T-REPO-LIST" "expected rc=0 and a rendered allowlist row; rc=$rc"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
