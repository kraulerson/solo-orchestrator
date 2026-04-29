#!/usr/bin/env bash
# tests/test-bypass-audit-lib.sh — BL-029 audit-log library tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/bypass-audit.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup_lib_or_skip() {
  if [ ! -f "$LIB" ]; then
    fail_ "$1" "scripts/lib/bypass-audit.sh missing (RED)"
    return 1
  fi
  # shellcheck disable=SC1090
  source "$LIB"
}

setup() { TMP=$(mktemp -d); mkdir -p "$TMP/.claude"; }
teardown() { rm -rf "$TMP"; }

# T1: bypass_audit_init creates an empty array file.
echo "T1: bypass_audit_init creates [] file"
setup
setup_lib_or_skip "T1" && {
  bypass_audit_init "$TMP"
  if [ -f "$TMP/.claude/bypass-audit.json" ] && [ "$(jq 'length' "$TMP/.claude/bypass-audit.json")" = "0" ]; then
    pass "T1"
  else
    fail_ "T1" "file missing or not empty array"
  fi
}
teardown

# T2: bypass_audit_init is idempotent (does not clobber existing rows).
echo "T2: bypass_audit_init is idempotent"
setup
setup_lib_or_skip "T2" && {
  echo '[{"type":"sentinel","actor":"framework","timestamp":"x","enforcement_level_at_event":"strict","details":{},"user_response":"n/a","final_outcome":"recorded_only"}]' > "$TMP/.claude/bypass-audit.json"
  bypass_audit_init "$TMP"
  if [ "$(jq 'length' "$TMP/.claude/bypass-audit.json")" = "1" ]; then pass "T2"; else fail_ "T2" "init clobbered"; fi
}
teardown

# T3: bypass_audit_append appends a single row.
echo "T3: bypass_audit_append appends one row"
setup
setup_lib_or_skip "T3" && {
  bypass_audit_init "$TMP"
  bypass_audit_append "$TMP" '{"type":"claude_bypass_proposal","actor":"claude","timestamp":"2026-04-28T00:00:00Z","enforcement_level_at_event":"strict","details":{"pattern":"--no-verify"},"user_response":"PENDING","final_outcome":"recorded_only"}'
  if [ "$(jq 'length' "$TMP/.claude/bypass-audit.json")" = "1" ]; then pass "T3"; else fail_ "T3" "append failed"; fi
}
teardown

# T4: bypass_audit_append rejects malformed JSON.
echo "T4: bypass_audit_append rejects non-JSON"
setup
setup_lib_or_skip "T4" && {
  bypass_audit_init "$TMP"
  if bypass_audit_append "$TMP" 'this is not json' 2>/dev/null; then
    fail_ "T4" "expected non-zero return"
  else
    if [ "$(jq 'length' "$TMP/.claude/bypass-audit.json")" = "0" ]; then pass "T4"; else fail_ "T4" "row leaked into file"; fi
  fi
}
teardown

# T5: concurrent appends (10 parallel) all land — flock works.
echo "T5: concurrent appends all land"
setup
setup_lib_or_skip "T5" && {
  bypass_audit_init "$TMP"
  ROW='{"type":"claude_bypass_proposal","actor":"claude","timestamp":"2026-04-28T00:00:00Z","enforcement_level_at_event":"strict","details":{"i":0},"user_response":"PENDING","final_outcome":"recorded_only"}'
  for i in $(seq 1 10); do
    ( bypass_audit_append "$TMP" "$ROW" ) &
  done
  wait
  count=$(jq 'length' "$TMP/.claude/bypass-audit.json")
  if [ "$count" = "10" ]; then pass "T5"; else fail_ "T5" "expected 10, got $count"; fi
}
teardown

# T6: bypass_audit_count_pending returns the number of rows whose user_response is "PENDING".
echo "T6: bypass_audit_count_pending counts PENDING rows"
setup
setup_lib_or_skip "T6" && {
  bypass_audit_init "$TMP"
  bypass_audit_append "$TMP" '{"type":"claude_bypass_proposal","actor":"claude","timestamp":"x","enforcement_level_at_event":"strict","details":{},"user_response":"PENDING","final_outcome":"recorded_only"}'
  bypass_audit_append "$TMP" '{"type":"claude_bypass_proposal","actor":"claude","timestamp":"x","enforcement_level_at_event":"strict","details":{},"user_response":"accepted","final_outcome":"committed"}'
  n=$(bypass_audit_count_pending "$TMP")
  if [ "$n" = "1" ]; then pass "T6"; else fail_ "T6" "got $n"; fi
}
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
