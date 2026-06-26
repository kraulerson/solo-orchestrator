#!/usr/bin/env bash
# tests/test-enforcement-level-lib.sh — BL-030 enforcement-level library tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/enforcement-level.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup_lib_or_skip() {
  if [ ! -f "$LIB" ]; then
    fail_ "$1" "scripts/lib/enforcement-level.sh does not exist (RED expected before impl)"
    return 1
  fi
  # shellcheck disable=SC1090
  source "$LIB"
}

setup() { TMP=$(mktemp -d); mkdir -p "$TMP/.claude"; }
teardown() { rm -rf "$TMP"; }

write_manifest() {
  local proj="$1" deployment="$2" poc_mode="$3" enforcement_level="${4:-}"
  local body='{"frameworkVersion":"test","host":"other","mode":"personal","deployment":"'"$deployment"'"'
  if [ -n "$poc_mode" ]; then body+=',"poc_mode":"'"$poc_mode"'"'; fi
  if [ -n "$enforcement_level" ]; then body+=',"enforcement_level":"'"$enforcement_level"'"'; fi
  body+='}'
  echo "$body" > "$proj/.claude/manifest.json"
}

# T1: read_enforcement_level returns explicit value when set.
echo "T1: read_enforcement_level returns explicit value"
setup
setup_lib_or_skip "T1" && {
  write_manifest "$TMP" "personal" "" "light"
  result=$(read_enforcement_level "$TMP")
  if [ "$result" = "light" ]; then pass "T1"; else fail_ "T1" "got '$result' expected 'light'"; fi
}
teardown

# T2: read_enforcement_level defaults to strict when field missing.
echo "T2: read_enforcement_level defaults to 'strict' on missing field"
setup
setup_lib_or_skip "T2" && {
  write_manifest "$TMP" "personal" "" ""
  result=$(read_enforcement_level "$TMP")
  if [ "$result" = "strict" ]; then pass "T2"; else fail_ "T2" "got '$result' expected 'strict'"; fi
}
teardown

# T3: read_enforcement_level defaults to strict when manifest missing.
echo "T3: read_enforcement_level defaults to 'strict' on missing manifest"
setup
setup_lib_or_skip "T3" && {
  result=$(read_enforcement_level "$TMP")
  if [ "$result" = "strict" ]; then pass "T3"; else fail_ "T3" "got '$result' expected 'strict'"; fi
}
teardown

# T4: assert_choosable accepts personal.
echo "T4: assert_choosable returns 0 for personal"
setup
setup_lib_or_skip "T4" && {
  write_manifest "$TMP" "personal" "" ""
  if assert_choosable "$TMP" 2>/dev/null; then pass "T4"; else fail_ "T4" "expected return 0"; fi
}
teardown

# T5: assert_choosable accepts private_poc.
echo "T5: assert_choosable returns 0 for organizational + private_poc"
setup
setup_lib_or_skip "T5" && {
  write_manifest "$TMP" "organizational" "private_poc" ""
  if assert_choosable "$TMP" 2>/dev/null; then pass "T5"; else fail_ "T5" "expected return 0"; fi
}
teardown

# T6: assert_choosable rejects sponsored_poc.
echo "T6: assert_choosable returns 1 for organizational + sponsored_poc"
setup
setup_lib_or_skip "T6" && {
  write_manifest "$TMP" "organizational" "sponsored_poc" ""
  if assert_choosable "$TMP" 2>/dev/null; then fail_ "T6" "expected return 1"; else pass "T6"; fi
}
teardown

# T7: assert_choosable rejects production (no poc_mode).
echo "T7: assert_choosable returns 1 for organizational + production"
setup
setup_lib_or_skip "T7" && {
  write_manifest "$TMP" "organizational" "" ""
  if assert_choosable "$TMP" 2>/dev/null; then fail_ "T7" "expected return 1"; else pass "T7"; fi
}
teardown

# T8: validate_transition allows strict→light on choosable.
echo "T8: validate_transition allows strict→light for personal"
setup
setup_lib_or_skip "T8" && {
  write_manifest "$TMP" "personal" "" "strict"
  if validate_transition "$TMP" "light" 2>/dev/null; then pass "T8"; else fail_ "T8" "expected return 0"; fi
}
teardown

# T9: validate_transition rejects strict→light on production.
echo "T9: validate_transition rejects strict→light for organizational+production"
setup
setup_lib_or_skip "T9" && {
  write_manifest "$TMP" "organizational" "" "strict"
  if validate_transition "$TMP" "light" 2>/dev/null; then fail_ "T9" "expected return 1"; else pass "T9"; fi
}
teardown

# T10: validate_transition rejects unknown level.
echo "T10: validate_transition rejects level='foo'"
setup
setup_lib_or_skip "T10" && {
  write_manifest "$TMP" "personal" "" "strict"
  if validate_transition "$TMP" "foo" 2>/dev/null; then fail_ "T10" "expected return 1"; else pass "T10"; fi
}
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
