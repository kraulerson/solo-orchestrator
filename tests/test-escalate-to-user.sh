#!/usr/bin/env bash
# tests/test-escalate-to-user.sh — BL-029 escalate-to-user CLI tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ESCALATE="$REPO_ROOT/scripts/escalate-to-user.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup() {
  TMP=$(mktemp -d); mkdir -p "$TMP/.claude"
  ( cd "$TMP" && git init -q && git config user.email "t@t.l" && git config user.name "t"
    echo init > i && git add i && git commit -qm init )
  echo "[]" > "$TMP/.claude/bypass-audit.json"
}
teardown() { rm -rf "$TMP"; }

# T1: escalate writes pending-approval.json with question + options.
echo "T1: escalate writes a structured pending-approval"
setup
if [ ! -f "$ESCALATE" ]; then fail_ "T1" "missing"; else
  ( cd "$TMP" && bash "$ESCALATE" \
      --question "should we proceed?" \
      --option "A1: proceed" \
      --option "A2: stop" \
      --recommendation "A2" >/dev/null 2>&1 )
  if [ -f "$TMP/.claude/pending-approval.json" ]; then pass "T1"; else fail_ "T1" "no sentinel written"; fi
fi
teardown

# T2: escalate writes an audit row of type='escalation' (per Fix #2).
echo "T2: escalate writes audit row with type='escalation'"
setup
if [ ! -f "$ESCALATE" ]; then fail_ "T2" "missing"; else
  ( cd "$TMP" && bash "$ESCALATE" --question q --option "A1: x" --option "A2: y" --recommendation A1 >/dev/null 2>&1 )
  rows=$(jq '[.[] | select(.type=="escalation")] | length' "$TMP/.claude/bypass-audit.json")
  if [ "$rows" = "1" ]; then pass "T2"; else fail_ "T2" "rows=$rows"; fi
fi
teardown

# T3: missing required arg fails fast.
echo "T3: --question is required"
setup
if [ ! -f "$ESCALATE" ]; then fail_ "T3" "missing"; else
  if ( cd "$TMP" && bash "$ESCALATE" --option "A1: x" --option "A2: y" --recommendation A1 >/dev/null 2>&1 ); then
    fail_ "T3" "expected non-zero"
  else
    pass "T3"
  fi
fi
teardown

# T4: < 2 options fails fast (CDF schema requires >= 2).
echo "T4: requires at least 2 options"
setup
if [ ! -f "$ESCALATE" ]; then fail_ "T4" "missing"; else
  if ( cd "$TMP" && bash "$ESCALATE" --question q --option "A1: only" --recommendation A1 >/dev/null 2>&1 ); then
    fail_ "T4" "expected non-zero"
  else
    pass "T4"
  fi
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
