#!/usr/bin/env bash
# tests/test-init-fail-status-propagation.sh — BL-064 regression test.
#
# BL-064 (Major, 2026-06-29 adversarial certainty pass): init.sh exits 0
# with the "Setup Complete" banner even after emitting a [FAIL] line for
# branch protection (or push, or any other create_and_protect_remote step
# that returns non-zero). Operators who only check the exit code (or scan
# for the banner) miss the gap entirely — same silent-success defect class
# that PR #105 fixed in intake-wizard.sh:2028.
#
# The fix (see init.sh::record_init_failure + print_init_failures_summary):
#   1. create_and_protect_remote's failure is tracked in INIT_FAILURES.
#   2. main() checks INIT_FAILURES after verify-install:
#        - empty → prints "Setup Complete" banner, returns 0
#        - non-empty → prints "Setup INCOMPLETE" summary re-listing every
#          tracked [FAIL], returns 2.
#   3. The exit code propagates to the script's exit status so wrapper
#      scripts that gate downstream actions on init.sh succeeding observe
#      the failure.
#
# This test is the regression guard: with a controlled push-failure trigger
# (fake remote URL), init.sh must exit non-zero AND must NOT print the
# unconditional "Setup Complete" banner AND must re-list the failure in a
# structured summary.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SH="$REPO_ROOT/init.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Helper: run init.sh against a fake URL (push always fails) and capture
# rc + full output. Used by both T1 (propagation) and T2 (summary content).
_run_init_with_fake_url() {
  local tmpdir="$1"
  local proj="$tmpdir/proj"
  local rc=0
  ( cd "$tmpdir" && "$INIT_SH" --non-interactive \
        --project bl064-trace \
        --platform web \
        --deployment personal \
        --language typescript \
        --project-dir "$proj" \
        --git-host other \
        --remote-url https://example.invalid/fake.git \
        --branch-protection-attested \
        --visibility private \
        --allow-existing-dir > "$tmpdir/out" 2>&1 ) || rc=$?
  echo "$rc"
}

# T1: rc must be non-zero when create_and_protect_remote emits [FAIL].
t1_rc_nonzero_after_create_and_protect_remote_fail() {
  local tmpdir; tmpdir=$(mktemp -d)
  local rc; rc=$(_run_init_with_fake_url "$tmpdir")

  # Sanity: the test's trigger relies on the fake URL producing a push [FAIL].
  if ! grep -q "Push failed" "$tmpdir/out"; then
    fail_ "T1" "trigger broken — expected [FAIL] 'Push failed' in output; tail:\n$(tail -20 "$tmpdir/out")"
    rm -rf "$tmpdir"; return
  fi

  # The actual contract: rc must be non-zero so wrapper scripts see the gap.
  if [ "$rc" -eq 0 ]; then
    fail_ "T1" "BL-064 silent-success regression: init.sh exited 0 despite [FAIL] line; tail:\n$(tail -20 "$tmpdir/out")"
    rm -rf "$tmpdir"; return
  fi

  pass "T1: init.sh exits non-zero (rc=$rc) when create_and_protect_remote emits [FAIL]"
  rm -rf "$tmpdir"
}

# T2: the unconditional "Setup Complete" banner must NOT print on the failure
# path. Either the banner is suppressed entirely or it is replaced by an
# explicit "Setup INCOMPLETE" banner that re-lists the failures.
t2_setup_complete_banner_suppressed_on_failure() {
  local tmpdir; tmpdir=$(mktemp -d)
  _run_init_with_fake_url "$tmpdir" > /dev/null

  if ! grep -q "Push failed" "$tmpdir/out"; then
    fail_ "T2" "trigger broken — expected [FAIL] 'Push failed' in output"
    rm -rf "$tmpdir"; return
  fi

  # The defect signature: a bare "Setup Complete" line appears even after
  # [FAIL]. After the fix, that banner must not appear; an explicit
  # "Setup INCOMPLETE" banner takes its place.
  if grep -Eq '^[^|]*Setup Complete' "$tmpdir/out" && ! grep -q "Setup INCOMPLETE" "$tmpdir/out"; then
    fail_ "T2" "BL-064 silent-success regression: 'Setup Complete' banner printed without 'Setup INCOMPLETE' override; tail:\n$(tail -20 "$tmpdir/out")"
    rm -rf "$tmpdir"; return
  fi

  if ! grep -q "Setup INCOMPLETE" "$tmpdir/out"; then
    fail_ "T2" "expected 'Setup INCOMPLETE' banner on failure path; tail:\n$(tail -20 "$tmpdir/out")"
    rm -rf "$tmpdir"; return
  fi

  pass "T2: 'Setup Complete' banner suppressed; 'Setup INCOMPLETE' replaces it on failure path"
  rm -rf "$tmpdir"
}

# T3: the exit-time summary must re-list the tracked failure so an operator
# scanning only the tail of the log still sees the gap.
t3_exit_summary_relists_failure() {
  local tmpdir; tmpdir=$(mktemp -d)
  _run_init_with_fake_url "$tmpdir" > /dev/null

  if ! grep -q "Push failed" "$tmpdir/out"; then
    fail_ "T3" "trigger broken — expected [FAIL] 'Push failed' in output"
    rm -rf "$tmpdir"; return
  fi

  # The structured summary must contain a re-listing of the tracked failure.
  # We anchor on the summary section keyword and the host-setup phase token
  # that record_init_failure cites; the exact wording is informational only.
  if ! grep -qi "failure(s) occurred during init" "$tmpdir/out"; then
    fail_ "T3" "expected exit-time summary keyword 'failure(s) occurred during init'; tail:\n$(tail -25 "$tmpdir/out")"
    rm -rf "$tmpdir"; return
  fi
  if ! grep -qi "Host repo setup" "$tmpdir/out"; then
    fail_ "T3" "expected summary to cite 'Host repo setup' phase; tail:\n$(tail -25 "$tmpdir/out")"
    rm -rf "$tmpdir"; return
  fi

  pass "T3: exit-time summary re-lists the host-setup failure"
  rm -rf "$tmpdir"
}

# T4: BL-024 invariant preservation — the attestation MUST still be recorded
# even though init.sh now exits non-zero. The BL-024 fix recorded attestation
# BEFORE push so a push failure cannot drop the operator's commitment; BL-064
# must not regress that.
t4_attestation_still_recorded_under_new_contract() {
  local tmpdir; tmpdir=$(mktemp -d)
  local proj="$tmpdir/proj"
  _run_init_with_fake_url "$tmpdir" > /dev/null

  if [ ! -f "$proj/.claude/process-state.json" ]; then
    fail_ "T4" "process-state.json missing — BL-024 attestation invariant regressed"
    rm -rf "$tmpdir"; return
  fi
  local attested_by
  attested_by=$(jq -r '.phase2_init.attestations.branch_protection.attested_by // "MISSING"' "$proj/.claude/process-state.json")
  if [ "$attested_by" != "orchestrator" ]; then
    fail_ "T4" "BL-024 regression: expected attested_by=orchestrator; got '$attested_by'"
    rm -rf "$tmpdir"; return
  fi

  pass "T4: BL-024 attestation recorded under BL-064 non-zero-exit contract"
  rm -rf "$tmpdir"
}

# T5: clean-path invariant — when create_and_protect_remote succeeds (here
# via --no-remote-creation, which skips the API entirely), init.sh must
# still exit 0 with the unmodified "Setup Complete" banner. This pins the
# negative side of the new contract — the BL-064 fix must not flag every
# init as INCOMPLETE.
t5_clean_path_still_setup_complete() {
  local tmpdir; tmpdir=$(mktemp -d)
  local proj="$tmpdir/proj"
  local rc=0
  ( cd "$tmpdir" && "$INIT_SH" --non-interactive \
        --project bl064-clean \
        --platform web \
        --deployment personal \
        --language typescript \
        --project-dir "$proj" \
        --git-host github \
        --visibility private \
        --no-remote-creation \
        --allow-existing-dir > "$tmpdir/out" 2>&1 ) || rc=$?

  if [ "$rc" -ne 0 ]; then
    fail_ "T5" "BL-064 over-flag regression: clean-path init exited rc=$rc; tail:\n$(tail -20 "$tmpdir/out")"
    rm -rf "$tmpdir"; return
  fi
  if ! grep -q "Setup Complete" "$tmpdir/out"; then
    fail_ "T5" "clean-path init missing 'Setup Complete' banner; tail:\n$(tail -20 "$tmpdir/out")"
    rm -rf "$tmpdir"; return
  fi
  if grep -q "Setup INCOMPLETE" "$tmpdir/out"; then
    fail_ "T5" "clean-path init wrongly printed 'Setup INCOMPLETE'; tail:\n$(tail -20 "$tmpdir/out")"
    rm -rf "$tmpdir"; return
  fi

  pass "T5: clean-path init still produces 'Setup Complete' with rc=0"
  rm -rf "$tmpdir"
}

echo "== tests/test-init-fail-status-propagation.sh =="
t1_rc_nonzero_after_create_and_protect_remote_fail
t2_setup_complete_banner_suppressed_on_failure
t3_exit_summary_relists_failure
t4_attestation_still_recorded_under_new_contract
t5_clean_path_still_setup_complete

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
