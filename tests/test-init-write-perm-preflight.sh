#!/usr/bin/env bash
# tests/test-init-write-perm-preflight.sh — BL-041 closer.
#
# Verifies the layering fix for the init.sh write-permission preflight vs.
# the framework-repo guard. Before this fix, the framework-repo guard ran
# FIRST when cwd was inside the framework checkout, masking any write-
# permission failure path and forcing tests/edge-cases-pre-init.sh E8b to
# be SKIPped (see solo-orchestrator-backlog.md::BL-041).
#
# CONTRACT FLIP — 2026-07-29 (BL-199). Read this before touching T2.
#   init.sh no longer runs the cwd arm of guard_not_in_framework. Karl's
#   decision: running init.sh FROM INSIDE the clone is the SUPPORTED flow (it
#   is what README § Quick Start has always told operators to do), so init.sh
#   guards the TARGET only, via guard_target_not_in_framework
#   (# BL-199-TARGET-GUARD in scripts/lib/helpers-core.sh).
#
#   T2 used to assert: cwd = framework + WRITABLE EXTERNAL target → refusal.
#   Under the new contract that exact invocation SUCCEEDS — it is the flow the
#   README documents. Asserting a refusal there would pin the defect. T2 is
#   therefore rewritten to pin the defense-in-depth that DID survive: with the
#   preflight passing, a target INSIDE the framework tree is still refused.
#   That is the arm the old cwd check never had (a subdirectory target was
#   invisible to it) and the one that now carries the whole invariant, so it
#   is the one worth a regression test here.
#
#   guard_not_in_framework itself is UNCHANGED and still cwd-first for the six
#   other scripts that call it (eight call sites). Only init.sh's flipped.
#   The end-to-end supported-flow coverage lives in
#   tests/test-bl199-quickstart-from-clone.sh.
#
# Test matrix
#   T1 — write-perm preflight fires BEFORE the framework-repo guard.
#        cwd = framework repo, --project-dir points at a read-only parent
#        OUTSIDE the framework. Expect: init.sh exits non-zero AND emits
#        the write-permission error, NOT any framework-repo refusal.
#        (This is the ordering pin. Unchanged by BL-199.)
#   T2 — the TARGET guard still fires when the preflight passes.
#        cwd = framework repo, --project-dir INSIDE the framework under a
#        writable parent (so the preflight passes and cannot be what blocks).
#        Expect: init.sh exits non-zero, emits the refusal, and creates
#        NOTHING (the guard runs before mkdir).
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
  # No framework refusal may have been produced. (If one had, the preflight
  # didn't run first and the layering is wrong.) BL-199 widened this grep from
  # the old guard's exact banner to the shared "Refusing to operate" opener, so
  # it catches EITHER guard's message — the new target guard deliberately does
  # not reuse the old wording.
  if echo "$out" | grep -q "Refusing to operate"; then
    fail_ "T1" "a framework refusal fired first (layering not fixed); tail: $(echo "$out" | tail -10)"
    return
  fi
  pass "T1: write-perm preflight fires before framework-repo guard (cwd=framework, target parent ro)"
}

# --- T2: the TARGET guard still fires when the preflight passes ---
# BL-199 contract flip — see the CONTRACT FLIP block in this file's header.
# Pre-BL-199 this asserted that cwd=framework + a WRITABLE EXTERNAL target was
# refused. That invocation is now the SUPPORTED flow and succeeds, so the
# assertion moved to the surviving defense-in-depth: a target INSIDE the
# framework tree, under a writable parent so the preflight cannot be what
# blocks. T1 remains the ordering pin.
t2_target_guard_still_fires() {
  # A dot-prefixed probe path directly under the framework root. The parent
  # (REPO_ROOT) is writable, so preflight_target_writable passes and the only
  # thing that can produce a non-zero exit is the target guard.
  #
  # R-199-9: this is the one case in the repo that aims a real init.sh run at
  # the developer's OWN checkout, so it is armed with an EXIT trap before the
  # run — an interrupt between mkdir and the assertion would otherwise strand a
  # ~600-file nested project in the working tree. The path is also in
  # .gitignore as a second line of defence, so a stranded probe can never be
  # committed by accident. Both belt and braces are deliberate: the guard runs
  # before mkdir, so on a healthy tree nothing is ever created here.
  local probe_root="$REPO_ROOT/.bl199-t2-guard-probe"
  local proj_target="$probe_root/proj"
  trap 'rm -rf "$REPO_ROOT/.bl199-t2-guard-probe"' EXIT INT TERM

  local rc=0 out
  out=$( cd "$REPO_ROOT" && "$INIT_SH" --non-interactive \
           --project bl199-t2 \
           --platform web \
           --deployment personal \
           --language typescript \
           --git-host github \
           --visibility private \
           --project-dir "$proj_target" \
           --no-remote-creation 2>&1 ) || rc=$?

  # Record then remove anything a regression scaffolded, so a red run cannot
  # leave debris in the developer's checkout.
  local created="no"
  [ -e "$probe_root" ] && created="yes"
  if [ -n "$REPO_ROOT" ] && [ "$probe_root" != "/" ]; then
    rm -rf "$probe_root"
  fi
  trap - EXIT INT TERM

  if [ "$rc" -eq 0 ]; then
    fail_ "T2" "expected non-zero exit (target inside the framework); got rc=0; tail: $(echo "$out" | tail -5)"
    return
  fi
  # R-199-11: assert on text UNIQUE to the BL-199 target guard, not the shared
  # "Refusing to operate" opener. cwd is the framework here, so a regression
  # that restored guard_not_in_framework would print the same opener and leave
  # this case green while claiming to pin the new guard. The old guard's advice
  # is the OPPOSITE of this sentence, so it can never emit it.
  if ! echo "$out" | grep -q "Running init.sh from inside the clone is fine"; then
    fail_ "T2" "the BL-199 target guard did not fire when the preflight passed (a bare 'Refusing to operate' is not enough — that opener is shared with the old cwd guard); tail: $(echo "$out" | tail -10)"
    return
  fi
  # The preflight must NOT be what blocked — the parent is writable. If the
  # permission error shows up here, the probe path is wrong, not the guard.
  if echo "$out" | grep -qE "write permission denied|Cannot create project directory"; then
    fail_ "T2" "preflight blocked instead of the guard (probe parent should be writable); tail: $(echo "$out" | tail -10)"
    return
  fi
  if [ "$created" = "yes" ]; then
    fail_ "T2" "guard fired AFTER mkdir — $probe_root was created inside the framework"
    return
  fi
  pass "T2: target INSIDE the framework is refused when preflight passes, with nothing created (BL-199 defense-in-depth)"
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
  if echo "$out" | grep -qE "write permission denied|Refusing to operate"; then
    fail_ "T3" "preflight or framework guard false-positive; tail: $(echo "$out" | tail -10)"
    return
  fi
  pass "T3: outside-framework + writable target → neither guard false-positives"
}

echo "== tests/test-init-write-perm-preflight.sh =="
t1_preflight_runs_before_framework_guard
t2_target_guard_still_fires
t3_non_framework_fresh_create_succeeds

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
