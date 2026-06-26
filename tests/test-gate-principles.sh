#!/usr/bin/env bash
# tests/test-gate-principles.sh — BL-030 block-message principle table tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/gate-principles.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if [ ! -f "$LIB" ]; then
  fail_ "lib-exists" "scripts/lib/gate-principles.sh missing (RED)"
else
  # shellcheck disable=SC1090
  source "$LIB"

  # T1: principle_for("commit-classifier") returns non-empty multiline content.
  out=$(principle_for "commit-classifier" 2>/dev/null)
  if echo "$out" | grep -q "discipline of its commit boundary"; then pass "T1: commit-classifier"; else fail_ "T1" "missing or wrong"; fi

  # T2: principle_for("phase-prereq") returns non-empty content.
  out=$(principle_for "phase-prereq" 2>/dev/null)
  if [ -n "$out" ] && echo "$out" | grep -q "remote"; then pass "T2: phase-prereq"; else fail_ "T2" "missing"; fi

  # T3: principle_for("unknown-gate") returns a generic fallback rather than failing.
  out=$(principle_for "totally-fake-gate" 2>/dev/null)
  if [ -n "$out" ]; then pass "T3: fallback"; else fail_ "T3" "no fallback"; fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
