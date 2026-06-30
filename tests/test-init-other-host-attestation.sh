#!/usr/bin/env bash
# tests/test-init-other-host-attestation.sh — BL-024 + BL-064 regression test.
#
# BL-024 (fixed earlier): init.sh::create_and_protect_remote on the
# --git-host other path used to perform `git push` BEFORE the
# --branch-protection-attested attestation block. When the push failed
# (fake URL, corporate firewall, connectivity blip), `return 1` aborted
# the function and the attestation was silently dropped — even though
# the operator had explicitly passed --branch-protection-attested.
# The BL-024 fix reorders the attestation block to run BEFORE push, since
# attestation is a forward-looking commitment by the operator and is
# independent of push success.
#
# BL-064 (Major, 2026-06-30): init.sh used to exit 0 with the
# "Setup Complete" banner even after emitting a [FAIL] line for push
# (or branch protection, or any other create_and_protect_remote step
# that returns non-zero). Operators who only check the exit code missed
# the gap — same silent-success defect class as PR #105's intake-wizard.sh
# fix. The BL-064 fix tracks create_and_protect_remote's failure in
# INIT_FAILURES and exits the script with rc=2 + a "Setup INCOMPLETE"
# banner that re-lists the failure.
#
# T1 below covers BOTH contracts on the same fixture:
#   • BL-064: rc must be non-zero (was rc=0 before BL-064 fix).
#   • BL-064: "Setup INCOMPLETE" banner replaces "Setup Complete".
#   • BL-024: attestation must STILL be recorded despite the push fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SH="$REPO_ROOT/init.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Run init.sh against a fake URL so push fails. With --branch-protection-attested,
# attestation must still be recorded despite the push failure.
t1_attestation_recorded_when_push_fails_to_fake_url() {
  local tmpdir; tmpdir=$(mktemp -d)
  local proj="$tmpdir/proj"
  local rc=0
  ( cd "$tmpdir" && "$INIT_SH" --non-interactive \
        --project bl024-trace \
        --platform web \
        --deployment personal \
        --language typescript \
        --project-dir "$proj" \
        --git-host other \
        --remote-url https://example.com/fake.git \
        --branch-protection-attested \
        --visibility private \
        --allow-existing-dir > "$tmpdir/out" 2>&1 ) || rc=$?

  # BL-064: init.sh now exits non-zero (rc=2) when create_and_protect_remote
  # emits [FAIL]. Pre-BL-064, rc was 0 with the unconditional "Setup Complete"
  # banner — the silent-success defect closed by BL-064. The script still
  # writes attestation + project files (BL-024 invariant, asserted below);
  # only the exit code and banner change.
  if [ "$rc" -eq 0 ]; then
    fail_ "T1" "BL-064 silent-success regression: expected non-zero rc on push failure; got rc=0; tail:\n$(tail -15 "$tmpdir/out")"
    rm -rf "$tmpdir"; return
  fi

  # The push failure should still be visible in the log.
  if ! grep -q "Push failed" "$tmpdir/out"; then
    fail_ "T1" "expected to see 'Push failed' in output (this test relies on the fake URL failing); not present"
    rm -rf "$tmpdir"; return
  fi

  # BL-064: the "Setup INCOMPLETE" banner must replace "Setup Complete" on
  # the failure path so an operator scanning only the tail sees the gap.
  if ! grep -q "Setup INCOMPLETE" "$tmpdir/out"; then
    fail_ "T1" "BL-064: expected 'Setup INCOMPLETE' banner; tail:\n$(tail -15 "$tmpdir/out")"
    rm -rf "$tmpdir"; return
  fi

  # BL-024 invariant: the attestation MUST be recorded despite the push failure.
  if [ ! -f "$proj/.claude/process-state.json" ]; then
    fail_ "T1" "BL-024 regression: process-state.json missing"
    rm -rf "$tmpdir"; return
  fi
  local attested_by
  attested_by=$(jq -r '.phase2_init.attestations.branch_protection.attested_by // "MISSING"' "$proj/.claude/process-state.json")
  if [ "$attested_by" != "orchestrator" ]; then
    fail_ "T1" "BL-024 regression: expected attested_by=orchestrator; got '$attested_by'"
    rm -rf "$tmpdir"; return
  fi
  pass "T1: --branch-protection-attested recorded (BL-024) + rc=2 + Setup INCOMPLETE banner (BL-064)"
  rm -rf "$tmpdir"
}

# Negative: without the attestation flag, push failure must NOT silently record an attestation.
t2_no_attestation_when_flag_absent() {
  local tmpdir; tmpdir=$(mktemp -d)
  local proj="$tmpdir/proj"
  # --git-host other REQUIRES --branch-protection-attested in non-interactive mode
  # (init.sh validates this and would exit 1 before reaching create_and_protect_remote).
  # So we test by checking that the attestation only appears when the flag was passed —
  # i.e., the recording is gated on the flag, not on push success.
  local rc=0
  ( cd "$tmpdir" && "$INIT_SH" --non-interactive \
        --project bl024-neg \
        --platform web \
        --deployment personal \
        --language typescript \
        --project-dir "$proj" \
        --git-host other \
        --remote-url https://example.com/fake.git \
        --visibility private \
        --allow-existing-dir > "$tmpdir/out" 2>&1 ) || rc=$?

  # Without --branch-protection-attested, init.sh should fail validation early.
  if [ "$rc" -eq 0 ]; then
    fail_ "T2" "expected init validation failure without --branch-protection-attested; got rc=0"
    rm -rf "$tmpdir"; return
  fi
  pass "T2: --git-host other without --branch-protection-attested fails validation (regression)"
  rm -rf "$tmpdir"
}

echo "== tests/test-init-other-host-attestation.sh =="
t1_attestation_recorded_when_push_fails_to_fake_url
t2_no_attestation_when_flag_absent

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
