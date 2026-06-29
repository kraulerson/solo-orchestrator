#!/usr/bin/env bash
# tests/test-check-phase-gate-backstop-attestation.sh
#
# Regression test for code-check-gates-1 (BL-002 follow-up).
#
# Bug: scripts/check-phase-gate.sh's Phase 1→2 BACKSTOP block (lines
# ~279-305) unconditionally invoked `host_verify_protection "main" "$mode"`
# whenever current_phase >= 2, without first consulting
# `.claude/process-state.json::phase2_init.attestations.branch_protection.reason`.
#
# When a project legitimately attested `github_free_tier` at init (because
# branch protection is not available on free-tier private repos), the
# backstop would still call gh api and surface
#   [FAIL] Phase 1→2 backstop: protection verification failed
# even though `scripts/check-gate.sh --preflight` PASSED at the same
# moment. Operator gets contradictory signals; the FAIL is a
# silent-bypass-shaped false-fail affecting the BL-002 demographic.
#
# Fix: mirror the pattern shipped at scripts/check-gate.sh::cmd_preflight
# lines 52-64 — read the attestation reason; on `github_free_tier`, print
# an [OK] line and SKIP the host_verify_protection call (do not increment
# $issues).
#
# Test pattern blueprint: tests/test-check-gate.sh::T5
# (t5_preflight_honors_free_tier_attestation).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-phase-gate.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Create a Phase-2 project shape that triggers the backstop block.
# Seeded with the minimum artifacts (PRODUCT_MANIFESTO.md, PROJECT_BIBLE.md,
# dated APPROVAL_LOG entries) so the unrelated Phase 0→1 / Phase 1→2
# artifact checks don't accumulate `issues` and mask the backstop signal
# the test is exercising.
setup_phase2_project() {
  TMP=$(mktemp -d)
  PROJ="$TMP/p"
  mkdir -p "$PROJ/.claude"

  cat > "$PROJ/.claude/manifest.json" <<'JSON'
{"frameworkVersion":"test","host":"github","mode":"personal"}
JSON

  cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":2,"deployment":"personal","gates":{"phase_0_to_1":"2026-01-01","phase_1_to_2":"2026-02-01"}}
JSON

  cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# APPROVAL_LOG

## Phase 0 → Phase 1
Approved 2026-01-01

## Phase 1 → Phase 2
Approved 2026-02-01
MD

  # PRODUCT_MANIFESTO.md: minimal but with all 8 sections + content so
  # validate_manifesto_content doesn't FAIL/WARN.
  {
    echo "# PRODUCT_MANIFESTO"
    echo ""
    for i in 1 2 3 4 5 6 7 8; do
      echo "## ${i}. Section ${i}"
      echo "Filled content for section ${i}."
      echo ""
    done
  } > "$PROJ/PRODUCT_MANIFESTO.md"

  # PROJECT_BIBLE.md: minimal 14 numbered sections so the backstop
  # block's downstream BIBLE checks don't accumulate issues.
  {
    echo "# PROJECT_BIBLE"
    echo ""
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do
      echo "## ${i}. Section ${i}"
      echo "Content."
      echo ""
    done
  } > "$PROJ/PROJECT_BIBLE.md"

  # Provide git + remote so the github driver's parse-origin step
  # doesn't bail before the attestation check fires. We want
  # host_load_driver to succeed so the test exercises the actual
  # backstop branch under audit (not the WARN-couldn't-load-driver
  # branch). host.sh sources scripts/host-drivers/<host>.sh from
  # `git rev-parse --show-toplevel` so we mirror the layout here.
  ( cd "$PROJ" && git init -q && git remote add origin https://github.com/example/free-tier-repo.git )
  mkdir -p "$PROJ/scripts/lib" "$PROJ/scripts/host-drivers"
  cp "$REPO_ROOT/scripts/lib/host.sh" "$PROJ/scripts/lib/"
  cp "$REPO_ROOT/scripts/host-drivers/github.sh" "$PROJ/scripts/host-drivers/"

  # PATH-prepended gh stub: returns 403 (Upgrade to GitHub Pro) on the
  # protection GET. Proves that, without the fix, the backstop FAILS —
  # and with the fix, it never reaches the stub at all when an
  # attestation is present.
  STUBDIR="$TMP/bin"
  mkdir -p "$STUBDIR"
  cat > "$STUBDIR/gh" <<'STUB'
#!/usr/bin/env bash
# Minimal gh stub: any `gh api .../protection` call returns 403.
if [[ "$*" == *"protection"* ]]; then
  echo '{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","status":"403"}' >&2
  exit 1
fi
exit 0
STUB
  chmod +x "$STUBDIR/gh"
}

teardown_project() { rm -rf "$TMP"; }

run_gate() {
  ( cd "$PROJ" && PATH="$STUBDIR:$PATH" bash "$SCRIPT" 2>&1 )
}

# ════════════════════════════════════════════════════════════════════
echo "== tests/test-check-phase-gate-backstop-attestation.sh =="
echo ""

# T1 (positive — primary): attestation present → backstop must skip
# host_verify_protection (the stub would fail it), exit 0, and the
# output must mention the attestation.
#
# tier-crosscheck-6 cross-cutting update: process-state.json fixture
# now also carries phase1_artifacts (data_classification + zdr_attested)
# so the NEW Phase 1→2 ZDR backstop doesn't fail and mask this test's
# signal. The classification value is "public" because this fixture
# isn't testing the ZDR gate — we want it green so we can isolate the
# branch-protection-attestation behavior under test.
echo "T1: attestation present → backstop honors it, exits 0"
setup_phase2_project
cat > "$PROJ/.claude/process-state.json" <<'JSON'
{"phase2_init":{"steps_completed":[],"attestations":{"branch_protection":{"attested_by":"orchestrator","at":"2026-04-27T00:00:00Z","reason":"github_free_tier"}}},
 "phase1_artifacts":{"data_classification":"public","zdr_attested":false}}
JSON
out=$(run_gate)
rc=$?
if [ "$rc" -ne 0 ]; then
  fail_ "T1" "expected exit 0 with github_free_tier attestation, got rc=$rc out:\n$out"
elif echo "$out" | grep -q "Phase 1→2 backstop: protection verification failed"; then
  fail_ "T1" "backstop FAIL emitted despite attestation; out:\n$(echo "$out" | grep -i backstop)"
elif echo "$out" | grep -qiE "backstop.*(attested|github_free_tier)"; then
  pass "T1: backstop honors github_free_tier attestation (skips API verify)"
else
  fail_ "T1" "expected backstop line mentioning attestation; out:\n$(echo "$out" | grep -i backstop)"
fi
teardown_project

# T2 (negative — regression guard): no attestation → backstop must
# still call host_verify_protection (which the stub will fail), so the
# FAIL line surfaces and exit code is non-zero. Proves the fix did not
# over-broadly skip verification.
echo "T2: no attestation → backstop still runs, exits non-zero on stub 403"
setup_phase2_project
# Intentionally no process-state.json
out=$(run_gate)
rc=$?
if [ "$rc" -eq 0 ]; then
  fail_ "T2" "expected non-zero exit without attestation (stub returns 403), got rc=0 out:\n$out"
elif echo "$out" | grep -q "Phase 1→2 backstop: protection verification failed"; then
  pass "T2: backstop FAIL fires without attestation (fix did not over-skip)"
else
  fail_ "T2" "expected backstop FAIL line; out:\n$(echo "$out" | grep -i backstop)"
fi
teardown_project

# T3 (coexistence): the canonical fix at scripts/check-gate.sh
# cmd_preflight (covered by tests/test-check-gate.sh::T5) must still
# pass with the new fix in place. Run the existing T5 file end-to-end.
echo "T3: tests/test-check-gate.sh suite (incl. T5) still passes post-fix"
if bash "$REPO_ROOT/tests/test-check-gate.sh" >/dev/null 2>&1; then
  pass "T3: tests/test-check-gate.sh suite (5/5) passes — preflight attestation contract preserved"
else
  fail_ "T3" "tests/test-check-gate.sh suite failed — possible cross-script regression"
fi

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
