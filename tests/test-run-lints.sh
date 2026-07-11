#!/usr/bin/env bash
# tests/test-run-lints.sh — behavior suite for scripts/run-lints.sh, the
# canonical local lint runner.
#
#   T-all-pass        Runner over the REAL repo → rc=0, one status line per
#                     real scripts/lint-*.sh, and lint-uat-scenarios.sh ABSENT
#                     from the output (it is a parametrized tool, not a lint).
#                     Note: this actually executes every real lint, including
#                     the two slow full-tree scans, so it takes a couple of
#                     minutes — that is the honest end-to-end signal.
#   T-fail-propagates A temp lint dir containing one deliberately-failing stub
#                     lint → rc≠0 and the failing lint is NAMED in the output.
#                     Also proves a uat-scenarios stub is skipped in an override
#                     dir.
#   T-mutation        Neuter the failure-collection line (marker
#                     RUN-LINTS-FAIL-COLLECT) in a COPY of the runner → the
#                     failing-stub case goes RED (rc becomes 0). The intact
#                     runner is GREEN (rc≠0). Proves the collection line is
#                     load-bearing for both the summary and the exit status.
#
# Hermetic, bash-3.2 safe (no associative arrays), set -uo pipefail (not -e so a
# single failed assertion does not abort the suite before the tally prints).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/run-lints.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Build a temp lint dir: one passing stub, one failing stub, and a
# uat-scenarios stub (to prove it is skipped even when present in an override
# dir). Prints the dir path on stdout.
make_stub_lint_dir() {
  local d; d="$(mktemp -d)"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/lint-aaa-ok.sh"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$d/lint-zzz-fail.sh"
  printf '#!/usr/bin/env bash\nexit 2\n' > "$d/lint-uat-scenarios.sh"
  chmod +x "$d"/lint-*.sh
  echo "$d"
}

# ── T-all-pass: the real repo ────────────────────────────────────────────────
out="$(bash "$RUNNER" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T-all-pass: runner over real repo exits 0"
else
  fail "T-all-pass: runner over real repo exits 0" "rc=$rc; out=$out"
fi

missing=""
for lint in "$REPO_ROOT"/scripts/lint-*.sh; do
  n="$(basename "$lint")"
  [ "$n" = "lint-uat-scenarios.sh" ] && continue
  echo "$out" | grep -q "$n" || missing="$missing $n"
done
if [ -z "$missing" ]; then
  pass "T-all-pass: every real lint named in output"
else
  fail "T-all-pass: every real lint named in output" "missing:$missing"
fi

if echo "$out" | grep -q "lint-uat-scenarios.sh"; then
  fail "T-all-pass: lint-uat-scenarios.sh excluded" "it appeared in output"
else
  pass "T-all-pass: lint-uat-scenarios.sh excluded"
fi

# ── T-fail-propagates: override dir with a failing stub lint ─────────────────
stub_dir="$(make_stub_lint_dir)"
out="$(bash "$RUNNER" "$stub_dir" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
  pass "T-fail-propagates: failing stub lint → rc≠0"
else
  fail "T-fail-propagates: failing stub lint → rc≠0" "rc=$rc; out=$out"
fi
if echo "$out" | grep -q "lint-zzz-fail.sh"; then
  pass "T-fail-propagates: failing lint named in summary"
else
  fail "T-fail-propagates: failing lint named in summary" "out=$out"
fi
if echo "$out" | grep -q "lint-uat-scenarios.sh"; then
  fail "T-fail-propagates: uat-scenarios skipped in override dir" "it appeared"
else
  pass "T-fail-propagates: uat-scenarios skipped in override dir"
fi

# ── T-mutation: neuter the failure-collection line in a COPY ─────────────────
copy="$(mktemp)"
sed 's/.*# RUN-LINTS-FAIL-COLLECT.*/    : # neutered for mutation test/' "$RUNNER" > "$copy"
if diff -q "$RUNNER" "$copy" >/dev/null 2>&1; then
  fail "T-mutation: marker line present and mutated" \
       "sed changed nothing — marker RUN-LINTS-FAIL-COLLECT missing from runner?"
else
  out="$(bash "$copy" "$stub_dir" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "T-mutation: neutered collection line → failure no longer propagates (RED)"
  else
    fail "T-mutation: neutered collection line → failure no longer propagates (RED)" \
         "rc=$rc still non-zero; mutation was ineffective; out=$out"
  fi
fi

# GREEN: the intact runner still propagates the same failure.
out="$(bash "$RUNNER" "$stub_dir" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
  pass "T-mutation: intact runner propagates failure (GREEN)"
else
  fail "T-mutation: intact runner propagates failure (GREEN)" "rc=$rc"
fi

rm -rf "$stub_dir" "$copy"

echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
