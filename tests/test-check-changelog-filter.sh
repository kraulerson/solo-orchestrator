#!/usr/bin/env bash
# tests/test-check-changelog-filter.sh — code-checks-utility-2.
#
# scripts/check-changelog.sh's test-file filter is unanchored: the
# pre-fix regex `(test|spec|_test|Test)\.` matches `latest.ts`,
# `contest.py`, `protest.go`, `protested.rs`, etc. — wrongly excluding
# legitimate source files and silencing the changelog-freshness warning
# for them.
#
# After the fix, only true test-naming conventions are excluded:
#   foo.test.ts, foo_test.go, FooTest.java, foo.spec.ts, foo_spec.rb
# while latest.ts / contest.py / protest.go remain INCLUDED in the
# source-changed count.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# The fix's contract: the test/spec filter pattern (the second `grep -vE`
# in check-changelog.sh, currently `(test|spec|_test|Test)\.`) must be
# anchored so it only matches:
#   * a basename-prefix-dot:   foo.test.ts, bar.spec.js  (i.e. `\.test\.` / `\.spec\.`)
#   * a basename-suffix:       FooTest.java, BarSpec.kt  (i.e. `(Test|Spec)\.[a-z]+$`)
#   * an underscore-prefix:    foo_test.go, bar_spec.rb  (i.e. `_test\.` / `_spec\.`)
# Pulling the regex out as a function makes it unit-testable: the fix
# exports a helper `_is_test_file` callable for inspection. But to keep
# the test independent of any internal helper name, we drive the script
# end-to-end through a temp git repo.

# Helper: build a tiny project, plant a file `f` as a diff against HEAD,
# run check-changelog.sh in strict mode, and return rc.
run_with_file() {
  local f="$1"
  local TMP=$(mktemp -d)
  (
    cd "$TMP"
    git init -q
    git config user.email "test@test.local"
    git config user.name "test"
    mkdir -p "$(dirname "$f")" 2>/dev/null || true
    # Seed an initial commit so HEAD~1 exists.
    echo "init" > .seed
    git add .seed
    git commit -q -m "init"
    # Stage and commit the candidate file as the only change.
    echo "x" > "$f"
    git add "$f"
    git commit -q -m "add $f"
  )
  # Run in strict mode so the script EXITs 1 on missing changelog (rather
  # than the GH-Actions warning-only default).
  local rc=0
  # GITHUB_BASE_REF= isolates this temp repo from CI/PR env: on a pull_request
  # event check-changelog.sh would diff against origin/$GITHUB_BASE_REF (absent
  # in this throwaway repo → empty diff → false pass). Force the HEAD~1..HEAD path.
  ( cd "$TMP" && GITHUB_BASE_REF= SOIF_STRICT_CHANGELOG=true bash "$REPO_ROOT/scripts/check-changelog.sh" >/dev/null 2>&1 ) || rc=$?
  rm -rf "$TMP"
  echo "$rc"
}

# T1: latest.ts is a SOURCE file — the script must classify it as
# source-changed and (in strict mode) exit 1 because CHANGELOG.md
# wasn't updated.
echo "T1: src/latest.ts triggers changelog warning (not silently exempt)"
rc=$(run_with_file "src/latest.ts")
if [ "$rc" -eq 1 ]; then
  pass "T1: latest.ts correctly flagged (rc=1)"
else
  fail_ "T1" "expected rc=1 (source change without changelog), got rc=$rc"
fi

# T2: contest.py — same.
echo "T2: src/contest.py triggers changelog warning"
rc=$(run_with_file "src/contest.py")
if [ "$rc" -eq 1 ]; then
  pass "T2: contest.py correctly flagged"
else
  fail_ "T2" "expected rc=1, got rc=$rc"
fi

# T3: protest.go — same.
echo "T3: src/protest.go triggers changelog warning"
rc=$(run_with_file "src/protest.go")
if [ "$rc" -eq 1 ]; then
  pass "T3: protest.go correctly flagged"
else
  fail_ "T3" "expected rc=1, got rc=$rc"
fi

# T4: foo.test.ts is a TRUE test file — must still be exempt (rc=0).
echo "T4: src/foo.test.ts is exempt (rc=0)"
rc=$(run_with_file "src/foo.test.ts")
if [ "$rc" -eq 0 ]; then
  pass "T4: foo.test.ts exempt"
else
  fail_ "T4" "expected rc=0 (test exempt), got rc=$rc"
fi

# T5: foo_test.go — Go test convention — exempt.
echo "T5: src/foo_test.go is exempt (rc=0)"
rc=$(run_with_file "src/foo_test.go")
if [ "$rc" -eq 0 ]; then
  pass "T5: foo_test.go exempt"
else
  fail_ "T5" "expected rc=0, got rc=$rc"
fi

# T6: FooTest.java — Java/Kotlin convention — exempt.
echo "T6: src/FooTest.java is exempt (rc=0)"
rc=$(run_with_file "src/FooTest.java")
if [ "$rc" -eq 0 ]; then
  pass "T6: FooTest.java exempt"
else
  fail_ "T6" "expected rc=0, got rc=$rc"
fi

# T7: foo.spec.ts — JS/TS spec convention — exempt.
echo "T7: src/foo.spec.ts is exempt (rc=0)"
rc=$(run_with_file "src/foo.spec.ts")
if [ "$rc" -eq 0 ]; then
  pass "T7: foo.spec.ts exempt"
else
  fail_ "T7" "expected rc=0, got rc=$rc"
fi

# T8: bar_spec.rb — Ruby RSpec convention — exempt.
echo "T8: src/bar_spec.rb is exempt (rc=0)"
rc=$(run_with_file "src/bar_spec.rb")
if [ "$rc" -eq 0 ]; then
  pass "T8: bar_spec.rb exempt"
else
  fail_ "T8" "expected rc=0, got rc=$rc"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
