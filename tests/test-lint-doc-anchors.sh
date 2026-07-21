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

# ════════════════════════════════════════════════════════════════════
# BL-090 cases — the cross-file reference arm (Karl's 2026-07-20
# decision: EXTEND this lint). WARN-tier by default (measured rollout):
# broken relative refs report but do not fail; --strict-refs escalates.
# ════════════════════════════════════════════════════════════════════

echo ""
echo "=== T8 (BL-090): broken relative ref → WARN line, exit stays 0 ==="
setup_fixture
cat > "$TMP/docs/refs.md" <<'MD'
# Refs Fixture

See [the missing doc](nonexistent-target.md) for details.
MD
out=$(run_lint_fixture); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'warn:.*refs.md.*nonexistent-target.md'; then
  pass "T8: broken relative ref warns without failing (measured rollout)"
else
  fail_ "T8" "expected rc=0 + a warn: line naming the ghost target; rc=$rc; output: $out"
fi
teardown_fixture

echo ""
echo "=== T9 (BL-090): --strict-refs escalates the same break to exit 1 ==="
setup_fixture
cat > "$TMP/docs/refs.md" <<'MD'
# Refs Fixture

See [the missing doc](nonexistent-target.md) for details.
MD
out=$(bash "$LINTER" --docs-dir "$TMP/docs" --strict-refs 2>&1); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'nonexistent-target.md'; then
  pass "T9: --strict-refs fails on the broken ref"
else
  fail_ "T9" "expected rc=1 under --strict-refs; rc=$rc; output: $out"
fi
teardown_fixture

echo ""
echo "=== T10 (BL-090): valid relative refs (sibling, subdir, ../, #suffix, image) pass ==="
setup_fixture
mkdir -p "$TMP/docs/sub"
printf '# Target\n\n## A Section\n' > "$TMP/docs/target.md"
printf '# Sub target\n' > "$TMP/docs/sub/inner.md"
printf 'fake-png-bytes\n' > "$TMP/docs/diagram.png"
cat > "$TMP/docs/refs.md" <<'MD'
# Refs Fixture

Sibling: [target](target.md). Subdir: [inner](sub/inner.md).
With anchor suffix: [section](target.md#a-section).
Image: ![diagram](diagram.png)
MD
cat > "$TMP/docs/sub/up.md" <<'MD'
# Up-reference

Parent: [target](../target.md)
MD
out=$(run_lint_fixture); rc=$?
if [ "$rc" -eq 0 ] && ! echo "$out" | grep -q 'warn:'; then
  pass "T10: sibling/subdir/parent/anchored/image refs all resolve"
else
  fail_ "T10" "valid refs produced warnings; rc=$rc; output: $out"
fi
teardown_fixture

echo ""
echo "=== T11 (BL-090): URLs, mailto, absolute paths, bare anchors, fenced code — all out of scope ==="
setup_fixture
cat > "$TMP/docs/skips.md" <<'MD'
# Skips Fixture

[web](https://example.com/page.md) [plain](http://example.com)
[mail](mailto:x@example.com) [abs](/etc/hosts.md)
[anchor-only](#skips-fixture)

```
[inside a fence](ghost-in-fence.md)
```
MD
out=$(run_lint_fixture); rc=$?
if [ "$rc" -eq 0 ] && ! echo "$out" | grep -q 'warn:'; then
  pass "T11: out-of-scope reference shapes produce zero warnings"
else
  fail_ "T11" "an out-of-scope shape was flagged; rc=$rc; output: $out"
fi
teardown_fixture

echo ""
echo "=== T12 (BL-090): the (planned) inline exemption suppresses the warn ==="
setup_fixture
cat > "$TMP/docs/planned.md" <<'MD'
# Planned Fixture

The upcoming guide lives at [future doc](not-written-yet.md) (planned).
MD
out=$(run_lint_fixture); rc=$?
if [ "$rc" -eq 0 ] && ! echo "$out" | grep -q 'warn:'; then
  pass "T12: (planned) on the referencing line exempts the ghost target"
else
  fail_ "T12" "(planned) exemption not honored; rc=$rc; output: $out"
fi
teardown_fixture

echo ""
echo "=== T13 (BL-090): fence-excision mutant — the refs arm lives in its fence ==="
m=$(grep -c 'BL-090-DOC-REFS' "$LINTER") || m=0
case "$m" in ''|*[!0-9]*) m=0 ;; esac
TMP_MUT_DIR=$(mktemp -d)
MUTL="$TMP_MUT_DIR/lint.mut.sh"
sed '/# BL-090-DOC-REFS-BEGIN/,/# BL-090-DOC-REFS-END/d' "$LINTER" > "$MUTL"
l=$(grep -c 'BL-090-DOC-REFS' "$MUTL") || l=0
case "$l" in ''|*[!0-9]*) l=0 ;; esac
setup_fixture
cat > "$TMP/docs/refs.md" <<'MD'
# Refs Fixture

See [the missing doc](nonexistent-target.md) for details.
MD
if [ "$m" -lt 2 ] || [ "$l" -ne 0 ]; then
  fail_ "T13" "excision vacuous (markers before=$m after=$l) — fence absent"
else
  out=$(bash "$MUTL" --docs-dir "$TMP/docs" 2>&1); rc=$?
  if [ "$rc" -eq 0 ] && ! echo "$out" | grep -q 'warn:'; then
    pass "T13: excised arm warns on nothing — the fence carries the whole refs check"
  else
    fail_ "T13" "mutant still warned (or broke, rc=$rc) — the arm does not live (only) inside the fence: $out"
  fi
fi
teardown_fixture
rm -rf "$TMP_MUT_DIR"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
