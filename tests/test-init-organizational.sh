#!/usr/bin/env bash
# tests/test-init-organizational.sh — audit tests-init-host-attestation-4 closure.
#
# Pre-fix coverage gap: tests/test-init-no-remote-creation.sh and
# tests/test-init-other-host-attestation.sh both ran init.sh end-to-end
# but only with --deployment personal. Nothing exercised the
# --deployment organizational + --gov-mode path against the real init.sh
# code (the only org-flow coverage was --validate-only at
# tests/edge-cases-scripts.sh E50/E51, which exits before file writes
# and before bl030_finalize_init runs). That left a real regression hole:
# breaking the org branch of init.sh's create_project / phase-state
# writer / governance scaffolding would not flip any test red.
#
# This file fills the gap with a single integration test that runs
# init.sh --non-interactive --deployment organizational --gov-mode
# production end-to-end (using --no-remote-creation so the test never
# touches a real host), then asserts the organizational markers landed
# correctly in the resulting project.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SH="$REPO_ROOT/init.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# T1: end-to-end organizational init writes manifest deployment field +
# APPROVAL_LOG.md governance scaffolding.
t1_organizational_e2e_writes_governance_scaffolding() {
  local tmpdir; tmpdir=$(mktemp -d)
  local proj="$tmpdir/org-proj"
  local rc=0
  # cd to tmpdir so the framework-self-guard doesn't refuse.
  # < <(printf 'Y\nY\n...) feeds finite stdin so any install confirms
  # auto-accept without breaking pipefail (yes(1) gets SIGPIPE → 141).
  ( cd "$tmpdir" && \
    "$INIT_SH" --non-interactive \
        --project test-org \
        --platform web \
        --deployment organizational \
        --gov-mode production \
        --language typescript \
        --git-host github \
        --visibility private \
        --project-dir "$proj" \
        --no-remote-creation \
        < <(printf 'Y\nY\nY\nY\nY\nY\nY\nY\nY\nY\n') \
        > "$tmpdir/init.log" 2>&1 ) || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail_ "T1" "expected init exit 0; rc=$rc tail:\n$(tail -15 "$tmpdir/init.log")"
    rm -rf "$tmpdir"; return
  fi

  # T1a: manifest.json records deployment=organizational. Pre-fix
  # nothing asserted this against a real run.
  if [ ! -f "$proj/.claude/manifest.json" ]; then
    fail_ "T1" "manifest.json not written"
    rm -rf "$tmpdir"; return
  fi
  local manifest_deployment
  manifest_deployment=$(jq -r '.deployment // empty' "$proj/.claude/manifest.json")
  if [ "$manifest_deployment" != "organizational" ]; then
    fail_ "T1" "expected manifest.deployment='organizational'; got '$manifest_deployment'"
    rm -rf "$tmpdir"; return
  fi

  # T1b: manifest.json records the host correctly even on the
  # --no-remote-creation path (same T2-C invariant as the personal
  # test). Organizational deployments must not silently lose this.
  local manifest_host
  manifest_host=$(jq -r '.host // empty' "$proj/.claude/manifest.json")
  if [ "$manifest_host" != "github" ]; then
    fail_ "T1" "expected manifest.host='github'; got '$manifest_host'"
    rm -rf "$tmpdir"; return
  fi

  # T1c: APPROVAL_LOG.md exists and is the ORGANIZATIONAL template, not
  # the personal one. The organizational template carries the
  # 'deployment: organizational' frontmatter key and the
  # Pre-Phase 0 Organizational Pre-Conditions section. The personal
  # template carries neither. This is what proves init's org branch
  # actually picked the right template.
  if [ ! -f "$proj/APPROVAL_LOG.md" ]; then
    fail_ "T1" "APPROVAL_LOG.md not written"
    rm -rf "$tmpdir"; return
  fi
  if ! grep -q '^deployment: organizational' "$proj/APPROVAL_LOG.md"; then
    fail_ "T1" "APPROVAL_LOG.md missing 'deployment: organizational' frontmatter; head:\n$(head -10 "$proj/APPROVAL_LOG.md")"
    rm -rf "$tmpdir"; return
  fi
  if ! grep -q "Pre-Phase 0.*Organizational Pre-Conditions" "$proj/APPROVAL_LOG.md"; then
    fail_ "T1" "APPROVAL_LOG.md missing 'Pre-Phase 0: Organizational Pre-Conditions' section"
    rm -rf "$tmpdir"; return
  fi

  # T1d: phase-state.json records deployment=organizational + (because
  # gov-mode=production) poc_mode is null. POC modes carry a non-null
  # poc_mode; production must be the explicit absence.
  local ps_deploy ps_poc
  ps_deploy=$(jq -r '.deployment // empty' "$proj/.claude/phase-state.json" 2>/dev/null || echo "")
  ps_poc=$(jq -r '.poc_mode // "null"' "$proj/.claude/phase-state.json" 2>/dev/null || echo "")
  if [ "$ps_deploy" != "organizational" ]; then
    fail_ "T1" "expected phase-state.deployment='organizational'; got '$ps_deploy'"
    rm -rf "$tmpdir"; return
  fi
  if [ "$ps_poc" != "null" ] && [ -n "$ps_poc" ]; then
    fail_ "T1" "expected phase-state.poc_mode=null for production gov-mode; got '$ps_poc'"
    rm -rf "$tmpdir"; return
  fi

  # T1e: --no-remote-creation contract still holds — no real origin
  # remote was added. This catches any future regression where the
  # organizational branch accidentally bypasses the no-remote-creation
  # guard.
  if (cd "$proj" && git remote get-url origin >/dev/null 2>&1); then
    local url; url=$(cd "$proj" && git remote get-url origin)
    fail_ "T1" "expected NO origin remote (--no-remote-creation); got: $url"
    rm -rf "$tmpdir"; return
  fi

  pass "T1: organizational end-to-end init writes deployment=organizational manifest + org APPROVAL_LOG.md + null poc_mode + no remote"
  rm -rf "$tmpdir"
}

# T2: end-to-end organizational + sponsored_poc init records poc_mode
# correctly. Asserts the POC-mode branch of init.sh's organizational
# path, which is otherwise only covered at --validate-only level.
t2_organizational_sponsored_poc_records_poc_mode() {
  local tmpdir; tmpdir=$(mktemp -d)
  local proj="$tmpdir/poc-proj"
  local rc=0
  ( cd "$tmpdir" && \
    "$INIT_SH" --non-interactive \
        --project test-poc \
        --platform web \
        --deployment organizational \
        --gov-mode sponsored_poc \
        --language typescript \
        --git-host github \
        --visibility private \
        --project-dir "$proj" \
        --no-remote-creation \
        < <(printf 'Y\nY\nY\nY\nY\nY\nY\nY\nY\nY\n') \
        > "$tmpdir/init.log" 2>&1 ) || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail_ "T2" "expected init exit 0; rc=$rc tail:\n$(tail -15 "$tmpdir/init.log")"
    rm -rf "$tmpdir"; return
  fi
  local ps_poc
  ps_poc=$(jq -r '.poc_mode // empty' "$proj/.claude/phase-state.json" 2>/dev/null || echo "")
  if [ "$ps_poc" != "sponsored_poc" ]; then
    fail_ "T2" "expected phase-state.poc_mode='sponsored_poc'; got '$ps_poc'"
    rm -rf "$tmpdir"; return
  fi
  pass "T2: organizational + sponsored_poc writes phase-state.poc_mode='sponsored_poc'"
  rm -rf "$tmpdir"
}

echo "== tests/test-init-organizational.sh =="
t1_organizational_e2e_writes_governance_scaffolding
t2_organizational_sponsored_poc_records_poc_mode

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
