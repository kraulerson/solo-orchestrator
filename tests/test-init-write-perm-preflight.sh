#!/usr/bin/env bash
# tests/test-init-write-perm-preflight.sh — BL-041 closer.
#
# Verifies the layering fix for the init.sh write-permission preflight vs.
# the framework-repo guard. Before this fix, the framework-repo guard ran
# FIRST when cwd was inside the framework checkout, masking any write-
# permission failure path and forcing tests/edge-cases-pre-init.sh E8b to
# be SKIPped (see solo-orchestrator-backlog.md::BL-041).
#
# Test matrix
#   T1 — write-perm preflight fires BEFORE framework-repo guard.
#        cwd = framework repo, --project-dir points at a read-only parent
#        OUTSIDE the framework. Expect: init.sh exits non-zero AND emits
#        the write-permission error, NOT the framework-repo refusal.
#   T2 — framework-repo guard still fires when preflight passes.
#        cwd = framework repo, --project-dir under a WRITABLE parent.
#        Expect: init.sh exits non-zero AND emits the framework-repo
#        refusal (defense-in-depth preserved).
#   T3 — clean tmp dir OUTSIDE framework: neither check false-positives.
#        cwd = tmp dir OUTSIDE framework, --project-dir under writable
#        parent. Expect: --validate-only exits 0 (preflight + guard pass).
#   T-mutation — verified by the operator manually reverting the reorder
#        block in init.sh and re-running T1; documented in the PR body
#        rather than scripted here (the script would have to mutate
#        committed source, which is fragile under CI).
#
# Self-verify (must exit 0 after fix):
#   bash tests/test-init-write-perm-preflight.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SH="$REPO_ROOT/init.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Refuse to run as root — chmod 0444 won't actually deny root write
# (root bypasses POSIX permission bits), so the preflight assertion would
# false-pass. This matches the same guard used in other read-only tests.
if [ "$(id -u)" = "0" ]; then
  echo "  [SKIP] running as root — POSIX 0444 doesn't deny root; preflight cannot be exercised"
  exit 0
fi

# --- T1: write-perm preflight fires BEFORE framework-repo guard ---
t1_preflight_runs_before_framework_guard() {
  local tmpdir; tmpdir=$(mktemp -d)
  local ro_parent="$tmpdir/ro-parent"
  local proj_target="$ro_parent/proj"
  mkdir -p "$ro_parent"
  chmod 0555 "$ro_parent"     # read+execute, NO write

  local rc=0 out
  # cwd intentionally set to REPO_ROOT — that is the framework checkout,
  # which historically triggered guard_not_in_framework BEFORE any
  # write-permission check. After the BL-041 fix, the preflight must
  # fire first and short-circuit with a write-permission error.
  out=$( cd "$REPO_ROOT" && "$INIT_SH" --non-interactive \
           --project bl041-t1 \
           --platform web \
           --deployment personal \
           --language typescript \
           --git-host github \
           --visibility private \
           --project-dir "$proj_target" \
           --no-remote-creation 2>&1 ) || rc=$?

  # Restore permissions so cleanup can rm -rf
  chmod 0755 "$ro_parent" 2>/dev/null || true
  rm -rf "$tmpdir"

  if [ "$rc" -eq 0 ]; then
    fail_ "T1" "expected non-zero exit (write-perm preflight); got rc=0; tail: $(echo "$out" | tail -5)"
    return
  fi
  # Preflight MUST win — look for its distinctive marker.
  if ! echo "$out" | grep -qE "write permission denied|Cannot create project directory"; then
    fail_ "T1" "missing write-permission marker; tail: $(echo "$out" | tail -10)"
    return
  fi
  # Framework-repo guard MUST NOT have produced its refusal banner.
  # (If it had, the preflight didn't run first and the layering is wrong.)
  if echo "$out" | grep -q "Refusing to operate inside the Solo Orchestrator framework repo"; then
    fail_ "T1" "framework-repo guard fired first (layering not fixed); tail: $(echo "$out" | tail -10)"
    return
  fi
  pass "T1: write-perm preflight fires before framework-repo guard (cwd=framework, target parent ro)"
}

# --- T2: framework-repo guard still fires when preflight passes ---
t2_framework_guard_still_fires() {
  local tmpdir; tmpdir=$(mktemp -d)
  local proj_target="$tmpdir/proj"   # parent writable, target doesn't exist

  local rc=0 out
  # cwd = framework checkout, target writable. Preflight passes (writable
  # parent), then the framework-repo guard cwd check fires. Confirms
  # defense-in-depth is preserved.
  out=$( cd "$REPO_ROOT" && "$INIT_SH" --non-interactive \
           --project bl041-t2 \
           --platform web \
           --deployment personal \
           --language typescript \
           --git-host github \
           --visibility private \
           --project-dir "$proj_target" \
           --no-remote-creation 2>&1 ) || rc=$?

  rm -rf "$tmpdir"

  if [ "$rc" -eq 0 ]; then
    fail_ "T2" "expected non-zero exit (framework-repo guard); got rc=0; tail: $(echo "$out" | tail -5)"
    return
  fi
  if ! echo "$out" | grep -q "Refusing to operate inside the Solo Orchestrator framework repo"; then
    fail_ "T2" "framework-repo guard did not fire when preflight passed; tail: $(echo "$out" | tail -10)"
    return
  fi
  pass "T2: framework-repo guard still fires when preflight passes (defense-in-depth preserved)"
}

# --- T3: clean tmpdir OUTSIDE framework — neither check false-positives ---
t3_non_framework_fresh_create_succeeds() {
  local tmpdir; tmpdir=$(mktemp -d)
  local proj_target="$tmpdir/proj"

  local rc=0 out
  # cwd = tmp dir (NOT the framework repo) and target is writable.
  # --validate-only is enough to prove both guards passed without paying
  # for the full project scaffold (which is exercised end-to-end in
  # other suites). --validate-only exits 0 after the resolved-JSON dump
  # only when no pre-resolution check (incl. the new preflight) fails.
  out=$( cd "$tmpdir" && "$INIT_SH" --non-interactive --validate-only \
           --project bl041-t3 \
           --platform web \
           --deployment personal \
           --language typescript \
           --git-host github \
           --visibility private \
           --project-dir "$proj_target" \
           --no-remote-creation 2>&1 ) || rc=$?

  rm -rf "$tmpdir"

  if [ "$rc" -ne 0 ]; then
    fail_ "T3" "expected exit 0 outside framework with writable target; got rc=$rc; tail: $(echo "$out" | tail -5)"
    return
  fi
  if echo "$out" | grep -qE "write permission denied|Refusing to operate inside the Solo Orchestrator framework repo"; then
    fail_ "T3" "preflight or framework guard false-positive; tail: $(echo "$out" | tail -10)"
    return
  fi
  pass "T3: outside-framework + writable target → neither guard false-positives"
}

echo "== tests/test-init-write-perm-preflight.sh =="
t1_preflight_runs_before_framework_guard
t2_framework_guard_still_fires
t3_non_framework_fresh_create_succeeds

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
