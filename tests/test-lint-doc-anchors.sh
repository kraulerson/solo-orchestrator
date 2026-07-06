#!/usr/bin/env bash
# tests/test-lint-doc-anchors.sh
#
# Behavior tests for scripts/lint-doc-anchors.sh — the BL-048
# dead-in-document-anchor backstop. Each test stages a tmpdir fixture
# with a fake `docs/` tree, invokes the lint with --docs-dir pointing
# at the fixture, and asserts on exit code + stderr/stdout.
#
# Required coverage (per BL-048 scope):
#   • T1 (positive): all-valid-anchors doc → exit 0
#   • T2 (negative): one-broken-anchor doc → exit 1, "FILE:LINE broken
#       anchor #x" diagnostic
#   • T-REPO (regression): the real docs/ tree passes after BL-048's
#       repairs landed
#
# Additional coverage exercising the fence-aware / dedup-aware slug
# logic (the parts most likely to regress silently):
#   • T3: headings/links inside fenced code blocks are ignored
#   • T4: duplicate heading text gets GitHub's -1/-2 dedup suffix
#   • T5: cross-file anchor refs (`other.md#anchor`) are out of scope
#   • T6: --list mode emits a STATUS table
#   • T7: unknown flag → exit 2
#
# Style mirrors tests/test-lint-tests-registered.sh and
# tests/test-lint-raw-read-prompt.sh: set -uo pipefail, mktemp
# fixtures, pass/fail counters, teardown after each test.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINTER="$REPO_ROOT/scripts/lint-doc-anchors.sh"

if [ ! -f "$LINTER" ]; then
  echo "FATAL: linter not found at $LINTER" >&2
  exit 2
fi

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup_fixture() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/docs"
}
teardown_fixture() { rm -rf "$TMP"; }

run_lint_fixture() {
  bash "$LINTER" --docs-dir "$TMP/docs" 2>&1
  return $?
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: all-valid-anchors doc → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/docs/valid.md" <<'MD'
# Valid Anchors Fixture

## Row Schema

See the [schema section](#row-schema) above.

## Another Section (With Punctuation!)

Back to [the top](#valid-anchors-fixture) or over to
[another section](#another-section-with-punctuation).
MD
out=$(run_lint_fixture); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "OK:"; then
  pass "T1: all-valid-anchors fixture exits 0"
else
  fail_ "T1" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: one-broken-anchor doc → exit 1, FILE:LINE broken anchor #x ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/docs/broken.md" <<'MD'
# Broken Anchor Fixture

## Real Heading

See the [missing section](#this-anchor-does-not-exist) for details.
MD
out=$(run_lint_fixture); rc=$?
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -qE 'broken\.md:5 broken anchor #this-anchor-does-not-exist'; then
  pass "T2: broken anchor exits 1 with FILE:LINE broken anchor #x diagnostic"
else
  fail_ "T2" "expected exit 1 + 'broken.md:5 broken anchor #this-anchor-does-not-exist'; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: headings/links inside fenced code blocks are ignored ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/docs/fenced.md" <<'MD'
# Fenced Fixture

## Real Section

```markdown
# This is example text, not a real heading
[fake link](#this-anchor-would-be-broken-if-real)
```

See the [real section](#real-section) — the only real reference.
MD
out=$(run_lint_fixture); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "OK:"; then
  pass "T3: fenced example content ignored, real reference resolves"
else
  fail_ "T3" "expected exit 0 (fenced content should not be scanned); rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T4: duplicate heading text gets GitHub's -1/-2 dedup suffix ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/docs/dedup.md" <<'MD'
# Dedup Fixture

## Setup

First setup section.

## Setup

Second setup section — GitHub gives this one `#setup-1`.

[Link to first](#setup) and [link to second](#setup-1).
MD
out=$(run_lint_fixture); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "OK:"; then
  pass "T4: duplicate heading dedup suffix (-1) resolves correctly"
else
  fail_ "T4" "expected exit 0 (dedup suffix should resolve); rc=$rc; output:\n$out"
fi
teardown_fixture

# T4b: the same fixture's un-suffixed second reference should FAIL,
# proving the dedup logic isn't just accepting everything.
setup_fixture
cat > "$TMP/docs/dedup-bad.md" <<'MD'
# Dedup Bad Fixture

## Setup

First setup section.

## Setup

Second setup section.

[Link to second (wrong, missing -1 suffix)](#setup-2).
MD
out=$(run_lint_fixture); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q "broken anchor #setup-2"; then
  pass "T4b: over-eager dedup suffix (one past the real count) still fails"
else
  fail_ "T4b" "expected exit 1 for nonexistent #setup-2; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T5: cross-file anchor refs (other.md#anchor) are out of scope ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/docs/crossfile.md" <<'MD'
# Cross-File Fixture

See [another doc](other.md#some-anchor-that-does-not-exist-here) for details.
MD
out=$(run_lint_fixture); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "OK:"; then
  pass "T5: cross-file anchor reference is out of scope, exits 0"
else
  fail_ "T5" "expected exit 0 (cross-file refs out of scope); rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T6: --list mode emits a STATUS table ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/docs/listed.md" <<'MD'
# Listed Fixture

## Section One

[Link](#section-one).
MD
out=$(bash "$LINTER" --docs-dir "$TMP/docs" --list 2>&1); rc=$?
if [ "$rc" -eq 0 ] \
   && echo "$out" | grep -q "STATUS" \
   && echo "$out" | grep -q "#section-one"; then
  pass "T6: --list mode prints STATUS table with anchor detail"
else
  fail_ "T6" "expected --list header + row; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T7: unknown flag returns exit 2 ==="
# ════════════════════════════════════════════════════════════════════
out=$(bash "$LINTER" --bogus-flag 2>&1); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -q "Usage:"; then
  pass "T7: unknown flag rejected with exit 2 + usage"
else
  fail_ "T7" "expected exit 2 + usage; rc=$rc; output:\n$out"
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-REPO: real docs/ tree passes after BL-048 repairs → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# This is the merge gate: the lint must pass on the actual repo HEAD.
# If it fails, either a new broken anchor landed, or a repair regressed.
out=$(bash "$LINTER" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T-REPO: real docs/ tree is anchor-clean after BL-048 repairs"
else
  fail_ "T-REPO" "current docs/ tree has broken anchors; rc=$rc; output:\n$out"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
