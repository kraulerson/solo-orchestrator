#!/usr/bin/env bash
# tests/test-lint-tests-registered.sh
#
# Behavior tests for scripts/lint-tests-registered.sh — the BL-038
# runner-registration backstop. Each test stages a tmpdir fixture with
# a fake `tests/` directory plus a fake aggregator, invokes the lint
# with --tests-dir + --aggregators pointing at the fixture, and asserts
# on exit code + stderr.
#
# Per BL-066 lesson (exercise both success AND failure paths):
#   • T1 (positive): clean fixture, one registered test → exit 0
#   • T2 (negative): one unregistered test → exit 1, file named in stderr
#   • T3 (allowlist marker): unregistered + EXEMPT marker → exit 0
#   • T4 (empty reason): EXEMPT marker with no reason → exit 1 with
#       "allowlist requires non-empty reason" diagnostic
#   • T5 (regression against current repo): real repo invocation → exit 0
#   • T6 (mutation experiment): comment-out a real registration in
#       full-project-test-suite.sh, confirm the lint catches it (proves
#       the lint sees real invocations, not just comment-mention noise)
#   • T7 (reverse-mutation): no false-positive on existing aggregator
#       comments that mention test basenames (e.g.
#       `# Hook test scaffolding (same shape as test-foo.sh)`)
#
# Style mirrors tests/test-lint-counter-antipattern.sh (PR #72) and
# tests/test-lint-fix-functions-stderr.sh (PR #96): set -uo pipefail,
# mktemp fixtures, pass/fail counters, teardown after each test.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINTER="$REPO_ROOT/scripts/lint-tests-registered.sh"

if [ ! -f "$LINTER" ]; then
  echo "FATAL: linter not found at $LINTER" >&2
  exit 2
fi

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Build an isolated fixture: $TMP/tests/ with the given file content,
# plus an aggregator at $TMP/tests/myagg.sh that invokes whatever you
# pass. Return $TMP via the global TMP variable.
setup_fixture() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/tests"
}
teardown_fixture() { rm -rf "$TMP"; }

# Run the lint pointed at the fixture's tests/ and aggregator file.
# Args: aggregator-file (relative to $TMP). Captures exit + combined output.
run_lint_fixture() {
  local agg="${1:-tests/myagg.sh}"
  bash "$LINTER" --tests-dir "$TMP/tests" --aggregators "$TMP/$agg" 2>&1
  return $?
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: clean fixture (one registered test) → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/tests/test-registered.sh" <<'SH'
#!/usr/bin/env bash
echo "fixture test"
SH
cat > "$TMP/tests/myagg.sh" <<SH
#!/usr/bin/env bash
bash "$TMP/tests/test-registered.sh"
SH
out=$(run_lint_fixture); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "OK:"; then
  pass "T1: clean registered fixture exits 0"
else
  fail_ "T1" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: unregistered test → exit 1, names file in stderr ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/tests/test-orphan.sh" <<'SH'
#!/usr/bin/env bash
echo "this test is never invoked"
SH
# Aggregator file exists but does NOT mention test-orphan.sh.
cat > "$TMP/tests/myagg.sh" <<'SH'
#!/usr/bin/env bash
echo "I register nothing"
SH
out=$(run_lint_fixture); rc=$?
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -q "test-orphan.sh" \
   && echo "$out" | grep -q "not invoked by any aggregator"; then
  pass "T2: unregistered test exits 1 with file name + diagnostic"
else
  fail_ "T2" "expected exit 1 + diagnostic mentioning test-orphan.sh; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: EXEMPT marker with reason → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/tests/test-orphan-exempt.sh" <<'SH'
#!/usr/bin/env bash
# LINT_TEST_REGISTRATION_EXEMPT: manual-only smoke test, runs in nightly cron
echo "exempted orphan"
SH
cat > "$TMP/tests/myagg.sh" <<'SH'
#!/usr/bin/env bash
echo "I register nothing"
SH
out=$(run_lint_fixture); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "OK:"; then
  pass "T3: EXEMPT marker with reason exits 0"
else
  fail_ "T3" "expected exit 0 with EXEMPT marker; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T4: EXEMPT marker with empty reason → exit 1 + 'non-empty reason' diagnostic ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/tests/test-orphan-bad-exempt.sh" <<'SH'
#!/usr/bin/env bash
# LINT_TEST_REGISTRATION_EXEMPT:
echo "bad exempt"
SH
cat > "$TMP/tests/myagg.sh" <<'SH'
#!/usr/bin/env bash
echo "I register nothing"
SH
out=$(run_lint_fixture); rc=$?
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -q "test-orphan-bad-exempt.sh" \
   && echo "$out" | grep -q "allowlist requires non-empty reason"; then
  pass "T4: empty-reason EXEMPT marker fails with specific diagnostic"
else
  fail_ "T4" "expected exit 1 + 'allowlist requires non-empty reason'; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T4b: trailing-whitespace EXEMPT marker still treated as empty ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
# Marker has whitespace after the colon but no actual reason.
printf '%s\n%s\n%s\n' '#!/usr/bin/env bash' \
  '# LINT_TEST_REGISTRATION_EXEMPT:   ' \
  'echo "whitespace-only reason"' > "$TMP/tests/test-orphan-ws-exempt.sh"
cat > "$TMP/tests/myagg.sh" <<'SH'
#!/usr/bin/env bash
echo "I register nothing"
SH
out=$(run_lint_fixture); rc=$?
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -q "allowlist requires non-empty reason"; then
  pass "T4b: whitespace-only reason rejected"
else
  fail_ "T4b" "expected exit 1; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T5: real repo state (BL-038 invariant) → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# This is the merge gate: the lint must pass on the actual repo HEAD
# (with the KNOWN_ORPHANS_PENDING_BL035 bridge in place). If it fails,
# the bridge list is stale OR a Wave 5+ orphan slipped past the gate.
out=$(bash "$LINTER" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T5: repo HEAD is lint-clean (bridge list + Wave 1-4 registration)"
else
  fail_ "T5" "current repo HEAD has unregistered tests; rc=$rc; output:\n$out"
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T6: mutation — comment-out a real aggregator registration ==="
# ════════════════════════════════════════════════════════════════════
# Pick a known-registered test, write a fixture that copies it into a
# tmpdir, and stage an aggregator where the invocation is COMMENTED OUT
# instead of live. Expect the lint to surface the orphan.
setup_fixture
cat > "$TMP/tests/test-mutation-target.sh" <<'SH'
#!/usr/bin/env bash
echo "registered in fixture aggregator only via a comment line"
SH
# Aggregator mentions the basename but only in a comment — the BL-038
# defect class. A correct lint must NOT count the comment as a real
# registration (the false-positive caught during BL-038 self-test:
# `# Hook test scaffolding (same shape as test-foo.sh)`).
cat > "$TMP/tests/myagg.sh" <<'SH'
#!/usr/bin/env bash
# This comment mentions test-mutation-target.sh but does NOT invoke it.
echo "real aggregator body"
SH
out=$(run_lint_fixture); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q "test-mutation-target.sh"; then
  pass "T6: mutation — comment-mention does NOT count as registration"
else
  fail_ "T6" "expected exit 1 (comment shouldn't register); rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T7: reverse-mutation — live invocation DOES count ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/tests/test-live-invoked.sh" <<'SH'
#!/usr/bin/env bash
echo "live"
SH
# Aggregator has BOTH a comment mention AND a live invocation. Lint
# must pass — the live invocation is what counts, the comment is noise.
cat > "$TMP/tests/myagg.sh" <<SH
#!/usr/bin/env bash
# Comment about test-live-invoked.sh that should be ignored
bash "\$SCRIPT_DIR/tests/test-live-invoked.sh"
SH
out=$(run_lint_fixture); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T7: reverse-mutation — live invocation passes despite comment"
else
  fail_ "T7" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T8: aggregator file itself is skipped (not lint-checked as test) ==="
# ════════════════════════════════════════════════════════════════════
# The aggregator file might match the test-*.sh pattern itself (e.g.
# a file named test-aggregator.sh). It must be SKIPPED from the
# registration check, not flagged as an orphan.
setup_fixture
cat > "$TMP/tests/test-aggregator.sh" <<'SH'
#!/usr/bin/env bash
echo "I am an aggregator, not a test"
SH
cat > "$TMP/tests/test-real.sh" <<'SH'
#!/usr/bin/env bash
echo "real test"
SH
cat > "$TMP/tests/test-aggregator.sh" <<SH
#!/usr/bin/env bash
bash "$TMP/tests/test-real.sh"
SH
# Pass test-aggregator.sh AS the aggregator. It should not appear as
# a violation (it's in the aggregator allowlist).
out=$(bash "$LINTER" --tests-dir "$TMP/tests" --aggregators "$TMP/tests/test-aggregator.sh" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T8: aggregator file skipped from registration check"
else
  fail_ "T8" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T9: --list mode emits PASS/FAIL table ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/tests/test-listed.sh" <<'SH'
#!/usr/bin/env bash
echo "fixture"
SH
cat > "$TMP/tests/myagg.sh" <<SH
#!/usr/bin/env bash
bash "\$SCRIPT_DIR/tests/test-listed.sh"
SH
out=$(bash "$LINTER" --tests-dir "$TMP/tests" --aggregators "$TMP/tests/myagg.sh" --list 2>&1); rc=$?
if [ "$rc" -eq 0 ] \
   && echo "$out" | grep -q "STATUS" \
   && echo "$out" | grep -q "test-listed.sh" \
   && echo "$out" | grep -q "registered"; then
  pass "T9: --list mode prints STATUS table"
else
  fail_ "T9" "expected --list header + row; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T10: unknown flag returns exit 2 ==="
# ════════════════════════════════════════════════════════════════════
out=$(bash "$LINTER" --bogus-flag 2>&1); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -q "Usage:"; then
  pass "T10: unknown flag rejected with exit 2 + usage"
else
  fail_ "T10" "expected exit 2 + usage; rc=$rc; output:\n$out"
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T11: BL-067 wall-clock budget — real repo run completes in < 20s ==="
# ════════════════════════════════════════════════════════════════════
# BL-067 root cause: the original per-test-file grep loop was
# O(n_tests × m_aggregators) subprocesses. On a heavily-loaded
# workstation this crossed 2 minutes and busted the pre-commit gate.
# The BL-067 rewrite collapses the algorithm to O(n + m) by
# pre-computing a pipe-delimited "registered basename" set in a single
# pass over the aggregators, then doing an in-memory `case` lookup per
# test file (zero subprocesses in the hot loop).
#
# Mutation contract:
#   • This test asserts the real-repo lint completes in under 20s.
#     Median on a warm Mac (bash 3.2 + APFS) is <0.2s; the 20s budget
#     is deliberately loose so it doesn't false-fire under CI load,
#     but tight enough that a return to the O(n×m) subprocess-per-file
#     shape (~1s per 100 tests on a fast box, extrapolating past 2min
#     on the environment BL-067 was filed from) trips the test.
#   • Reverting scripts/lint-tests-registered.sh to the pre-BL-067
#     grep-per-aggregator inner loop puts the runtime at ~1s locally
#     but blows past this budget on the reproducer environments.
BUDGET_SEC=20
# Capture wall-clock via `date +%s`. This is 1s resolution which is
# more than enough for a 20s budget check and avoids depending on
# `time` output parsing (portability across gnu-time / bash-time).
start_s=$(date +%s)
bash "$LINTER" >/dev/null 2>&1
lint_rc=$?
end_s=$(date +%s)
elapsed=$((end_s - start_s))
if [ "$lint_rc" -eq 0 ] && [ "$elapsed" -lt "$BUDGET_SEC" ]; then
  pass "T11: real-repo lint completed in ${elapsed}s < ${BUDGET_SEC}s budget (BL-067 perf gate)"
else
  fail_ "T11" "elapsed=${elapsed}s (budget ${BUDGET_SEC}s), lint_rc=${lint_rc} — BL-067 perf regression suspected"
fi

# ════════════════════════════════════════════════════════════════════
# BL-154: the tests.yml unit-lane enforcement arm.
#
# Before BL-154 the lint enforced ONLY aggregator registration; the
# CANONICAL COMMANDS / HOUSE RULES sentences in CLAUDE.md claimed it also
# enforced membership of the .github/workflows/tests.yml fast-lane unit
# list. It did not. The new arm (behind the # BL-154-UNIT-LANE fence)
# closes that gap: every top-level tests/test-*.sh that does NOT invoke
# init.sh must appear in the tests.yml `tests=(` array; an init.sh-invoking
# test is EXEMPT (it belongs to the slow lane / aggregators only). The arm
# consumes the unit list via a --tests-yml FILE override (fixture idiom
# mirroring --tests-dir / --aggregators); in repo mode it defaults to the
# real .github/workflows/tests.yml.
#   • U1 (exempt): an init.sh-invoking test absent from the unit list → OK
#   • U2 (flag):   a non-init test aggregator-registered but ABSENT from
#                  the fixture unit list → exit 1, named + "unit lane"
#   • U3 (repo):   the real repo passes the unit-lane arm (delta 0 today)
#   • U4 (mutation, fence-excision): excise the BL-154 fence from a COPY →
#                  the U2 scenario stops flagging (the fence is load-bearing)
#   • U5 (mutation, tests.yml): drop one real entry from a COPY of the real
#                  tests.yml consumed via --tests-yml → that test is flagged
# ════════════════════════════════════════════════════════════════════

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== U1: init.sh-invoking test absent from unit list is EXEMPT → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# A test that scaffolds a project (invokes init.sh) is aggregator-only by
# design — it must NOT be required in the fast-lane unit list. The arm
# derives this from the file's own text (the grep -L 'init\.sh' convention
# that tests.yml itself documents).
setup_fixture
cat > "$TMP/tests/test-scaffolder.sh" <<'SH'
#!/usr/bin/env bash
# This test scaffolds a real project (hermetic: --no-remote-creation, BL-076):
bash "$REPO/init.sh" --no-remote-creation --platform web
SH
cat > "$TMP/tests/myagg.sh" <<SH
#!/usr/bin/env bash
bash "$TMP/tests/test-scaffolder.sh"
SH
# Fixture unit list that does NOT mention test-scaffolder.sh.
cat > "$TMP/tests.yml" <<'SH'
          tests=(
            tests/test-some-fast-unit.sh
          )
SH
out=$(bash "$LINTER" --tests-dir "$TMP/tests" --aggregators "$TMP/tests/myagg.sh" --tests-yml "$TMP/tests.yml" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && ! echo "$out" | grep -q "unit lane"; then
  pass "U1: init.sh-invoking test exempt from the unit lane"
else
  fail_ "U1" "expected exit 0, no unit-lane flag; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== U2: non-init test registered but ABSENT from unit list → exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# The load-bearing case: a fast (no init.sh) test that IS aggregator-
# registered but is missing from the tests.yml unit list must be flagged.
setup_fixture
cat > "$TMP/tests/test-noninit-fast.sh" <<'SH'
#!/usr/bin/env bash
echo "fast unit test — no project scaffolding here"
SH
cat > "$TMP/tests/myagg.sh" <<SH
#!/usr/bin/env bash
bash "$TMP/tests/test-noninit-fast.sh"
SH
cat > "$TMP/tests.yml" <<'SH'
          tests=(
            tests/test-some-other-unit.sh
          )
SH
out=$(bash "$LINTER" --tests-dir "$TMP/tests" --aggregators "$TMP/tests/myagg.sh" --tests-yml "$TMP/tests.yml" 2>&1); rc=$?
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -q "test-noninit-fast.sh" \
   && echo "$out" | grep -q "unit lane"; then
  pass "U2: unregistered-from-unit-lane non-init test flagged (exit 1 + diagnostic)"
else
  fail_ "U2" "expected exit 1 + 'unit lane' naming test-noninit-fast.sh; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== U3: real repo passes the unit-lane arm (BL-154 delta 0) → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# Repo-mode run resolves the real .github/workflows/tests.yml. Every
# non-init tests/test-*.sh is present in the unit list today (verified
# 2026-07-21), so the arm must not flag anything on the real repo.
out=$(bash "$LINTER" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && ! echo "$out" | grep -q "unit lane"; then
  pass "U3: repo HEAD is unit-lane-clean"
else
  fail_ "U3" "unit-lane arm flagged the real repo (delta should be 0); rc=$rc; output:\n$out"
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== U4: mutation — excise the BL-154 fence → U2 scenario stops flagging ==="
# ════════════════════════════════════════════════════════════════════
# Copy the linter, excise every # BL-154-UNIT-LANE-BEGIN..END region, and
# re-run the U2 fixture. Without the fence the non-init unregistered test
# must NO LONGER be flagged — proving the fence is what does the enforcing.
setup_fixture
cat > "$TMP/tests/test-noninit-fast.sh" <<'SH'
#!/usr/bin/env bash
echo "fast unit test — no project scaffolding here"
SH
cat > "$TMP/tests/myagg.sh" <<SH
#!/usr/bin/env bash
bash "$TMP/tests/test-noninit-fast.sh"
SH
cat > "$TMP/tests.yml" <<'SH'
          tests=(
            tests/test-some-other-unit.sh
          )
SH
MUT="$TMP/mut"
mkdir -p "$MUT/scripts"
marker_n=$(grep -c 'BL-154-UNIT-LANE-BEGIN' "$LINTER" 2>/dev/null || echo "0")
case "$marker_n" in ''|*[!0-9]*) marker_n=0 ;; esac
orig_lines=$(wc -l < "$LINTER")
sed '/# BL-154-UNIT-LANE-BEGIN/,/# BL-154-UNIT-LANE-END/d' "$LINTER" > "$MUT/scripts/lint-tests-registered.sh"
mut_lines=$(wc -l < "$MUT/scripts/lint-tests-registered.sh")
chmod +x "$MUT/scripts/lint-tests-registered.sh"
if [ "$marker_n" -lt 1 ]; then
  fail_ "U4" "no BL-154-UNIT-LANE fence found in the linter — nothing to excise (fix not in place)"
elif [ "$mut_lines" -ge "$orig_lines" ]; then
  fail_ "U4" "fence excision removed no lines (orig=$orig_lines mut=$mut_lines) — the marked region is empty/vacuous"
elif ! bash -n "$MUT/scripts/lint-tests-registered.sh" 2>/dev/null; then
  fail_ "U4" "excised mutant is syntactically broken — keep the fence excision-safe"
else
  out=$(bash "$MUT/scripts/lint-tests-registered.sh" --tests-dir "$TMP/tests" --aggregators "$TMP/tests/myagg.sh" --tests-yml "$TMP/tests.yml" 2>&1); rc=$?
  if [ "$rc" -eq 0 ] && ! echo "$out" | grep -q "unit lane"; then
    pass "U4: fence excised → the U2 scenario no longer flags (fence is load-bearing)"
  else
    fail_ "U4" "fence excised but the non-init test is still flagged — the fence does not contain the enforcement; rc=$rc; output:\n$out"
  fi
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== U5: mutation — drop one real entry from a tests.yml COPY → flagged ==="
# ════════════════════════════════════════════════════════════════════
# Copy the REAL tests.yml, remove one real non-init test's unit-list line,
# and consume the copy via --tests-yml against the real tests dir. That one
# test must now be flagged as missing from the unit lane.
REAL_YML="$REPO_ROOT/.github/workflows/tests.yml"
DROP="tests/test-check-gate.sh"
MUTYML=$(mktemp)
grep -vF "$DROP" "$REAL_YML" > "$MUTYML"
out=$(bash "$LINTER" --tests-yml "$MUTYML" 2>&1); rc=$?
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -q "test-check-gate.sh" \
   && echo "$out" | grep -q "unit lane"; then
  pass "U5: dropping a real entry from the tests.yml copy flags that test"
else
  fail_ "U5" "expected exit 1 naming test-check-gate.sh via the unit lane; rc=$rc; output:\n$out"
fi
rm -f "$MUTYML"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
