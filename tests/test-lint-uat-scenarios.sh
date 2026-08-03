#!/usr/bin/env bash
# tests/test-lint-uat-scenarios.sh — unit tests for scripts/lint-uat-scenarios.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINTER="$REPO_ROOT/scripts/lint-uat-scenarios.sh"

PASSED=0
FAILED=0

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [ "$expected" != "$actual" ]; then
    echo "  ASSERT FAIL${msg:+ [$msg]}: expected '$expected', got '$actual'" >&2
    return 1
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  ASSERT FAIL${msg:+ [$msg]}: does not contain '$needle'" >&2
    return 1
  fi
}

run_case() {
  local name="$1"
  shift
  if ( set -e; "$@" ); then
    echo "✓ $name"
    PASSED=$((PASSED + 1))
  else
    echo "✗ $name FAILED"
    FAILED=$((FAILED + 1))
  fi
}

seed_html() {
  local file="$1" scenarios="$2"
  cat > "$file" <<HTML
<!DOCTYPE html>
<html><body>
<div class="fixture-ref">
  <strong>System under test:</strong> macOS (darwin/arm64).<br>
  <strong>Project root:</strong> <code>/tmp/example</code><br>
</div>
<script>
const scenarios = $scenarios;
</script>
</body></html>
HTML
}

case_1_happy_path() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  seed_html "$work/ok.html" '[
    {"id":1,"feature":1,"title":"T1","steps":"You are in the project root.\n\n1. Run pytest.","expected":"Pytest output contains PASSED and exits 0. No test failures reported. Total test count matches what you expected to run."},
    {"id":2,"feature":1,"title":"T2","steps":"You are in the project root.\n\n1. Run make build.","expected":"Build completes in under 30 seconds. Output contains \"Build complete\" and exits 0. Artifacts appear in dist/."},
    {"id":3,"feature":2,"title":"T3","steps":"cd services/web && npm test","expected":"npm test exits 0 with \"All tests passed\" line. Coverage summary shows >=80% on lines and branches."}
  ]'
  local out; out=$(bash "$LINTER" "$work/ok.html" 2>&1)
  local code=$?
  assert_eq "0" "$code" "exit 0 on happy path"
  assert_contains "$out" "3 scenarios clean" "success message"
}

case_2_unreplaced_preflight_placeholder() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  cat > "$work/bad.html" <<'HTML'
<html><body>
__TESTER_PRE_FLIGHT__
<script>const scenarios = [];</script>
</body></html>
HTML
  set +e
  local out; out=$(bash "$LINTER" "$work/bad.html" 2>&1)
  local code=$?
  set -e
  assert_eq "1" "$code" "exit 1 on unreplaced placeholder"
  assert_contains "$out" "unreplaced placeholder" "mentions placeholder"
  assert_contains "$out" "__TESTER_PRE_FLIGHT__" "names the placeholder"
}

case_3_unreplaced_scenarios_placeholder() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  cat > "$work/bad.html" <<'HTML'
<html><body>
<script>const scenarios = __SCENARIOS_JSON__;</script>
</body></html>
HTML
  set +e
  local out; out=$(bash "$LINTER" "$work/bad.html" 2>&1)
  local code=$?
  set -e
  if [ "$code" != "1" ] && [ "$code" != "2" ]; then
    echo "  Expected exit 1 or 2, got $code" >&2; return 1
  fi
  assert_contains "$out" "__SCENARIOS_JSON__" "names the placeholder"
}

case_4_expected_too_short() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  seed_html "$work/bad.html" '[
    {"id":1,"feature":1,"title":"T","steps":"You are in the project root.\n\n1. Run foo.","expected":"OK"}
  ]'
  set +e
  local out; out=$(bash "$LINTER" "$work/bad.html" 2>&1)
  local code=$?
  set -e
  assert_eq "1" "$code"
  assert_contains "$out" "expected too short" "mentions short expected"
}

case_5_expected_banned_phrase() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  seed_html "$work/bad.html" '[
    {"id":1,"feature":1,"title":"T","steps":"You are in the project root.\n\n1. Build.","expected":"works"}
  ]'
  set +e
  local out; out=$(bash "$LINTER" "$work/bad.html" 2>&1)
  local code=$?
  set -e
  assert_eq "1" "$code"
  if [[ "$out" != *"banned vague phrase"* ]] && [[ "$out" != *"expected too short"* ]]; then
    echo "  Expected 'banned vague phrase' or 'expected too short' in output" >&2; return 1
  fi
}

case_6_banned_cross_ref() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  seed_html "$work/bad.html" '[
    {"id":1,"feature":1,"title":"T","steps":"You are in the project root.\n\n1. Run the command from scenario 1 again.","expected":"Output matches what the prior scenario produced. Same exit code. Same stdout text to the byte."}
  ]'
  set +e
  local out; out=$(bash "$LINTER" "$work/bad.html" 2>&1)
  local code=$?
  set -e
  assert_eq "1" "$code"
  assert_contains "$out" "banned cross-ref" "mentions cross-ref"
}

case_7_missing_state_restatement() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  seed_html "$work/bad.html" '[
    {"id":1,"feature":1,"title":"T","steps":"1. Run pytest tests/\n2. Check the output","expected":"Pytest output contains PASSED. All 47 tests pass. Exit code is 0. No warnings printed to stderr."}
  ]'
  set +e
  local out; out=$(bash "$LINTER" "$work/bad.html" 2>&1)
  local code=$?
  set -e
  assert_eq "1" "$code"
  assert_contains "$out" "state-restatement" "mentions state-restatement"
}

case_8_duplicate_ids() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  seed_html "$work/bad.html" '[
    {"id":2,"feature":1,"title":"T1","steps":"You are in the project root.\n\n1. Run A.","expected":"Command A exits 0 and prints the expected success message to stdout. No errors on stderr."},
    {"id":2,"feature":1,"title":"T2","steps":"You are in the project root.\n\n1. Run B.","expected":"Command B exits 0 and prints the expected success message to stdout. No errors on stderr."}
  ]'
  set +e
  local out; out=$(bash "$LINTER" "$work/bad.html" 2>&1)
  local code=$?
  set -e
  assert_eq "1" "$code"
  assert_contains "$out" "duplicate scenario id" "mentions duplicate"
}

case_9_missing_file() {
  set +e
  local out; out=$(bash "$LINTER" "/nonexistent/path/foo.html" 2>&1)
  local code=$?
  set -e
  assert_eq "2" "$code" "exit 2 on missing file"
  assert_contains "$out" "No such file" "mentions missing"
}

case_10_malformed_json() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  cat > "$work/bad.html" <<'HTML'
<html><body>
<script>const scenarios = [{"id": 1, broken };</script>
</body></html>
HTML
  set +e
  local out; out=$(bash "$LINTER" "$work/bad.html" 2>&1)
  local code=$?
  set -e
  assert_eq "2" "$code" "exit 2 on malformed JSON"
  assert_contains "$out" "parse failed" "mentions parse failure"
}

case_12_seed_template_no_placeholder_collision() {
  # T2-H regression: the seed template must not contain literal __PLACEHOLDER__
  # in comments, because that token matches the linter's `__[A-Z][A-Z_]*__`
  # placeholder pattern and false-flags every populated copy that retains the
  # comment.
  local template="$REPO_ROOT/templates/uat/test-session-template.html"
  if grep -q '__PLACEHOLDER__' "$template"; then
    local hit; hit=$(grep -n '__PLACEHOLDER__' "$template" | head -1)
    echo "  Seed template contains literal __PLACEHOLDER__ at: $hit" >&2
    echo "  This will false-flag the linter on every populated UAT HTML." >&2
    return 1
  fi
}

case_13_seed_template_placeholder_manifest_is_complete() {
  # Walk 2026-08-02 ISSUE-008: the seed template's placeholders were documented
  # one-by-one next to the markup they fill — except __FEATURE_OPTIONS__, whose
  # only instructions sit mid-file inside addBug(). An author who worked the
  # comments near the top replaced six of seven and was caught by the linter,
  # which reports a line in the OUTPUT file while the fix belongs in a
  # different, mid-file spot in the TEMPLATE.
  #
  # The fix is a top-of-file PLACEHOLDER MANIFEST; this case makes it
  # self-maintaining. The token list is DERIVED, never retyped: the linter's
  # own comment-stripper decides which placeholders survive into a populated
  # file, so a NEW placeholder added to the template with no manifest row
  # fails here. Floor 7 keeps the derivation from passing vacuously.
  local template="$REPO_ROOT/templates/uat/test-session-template.html"
  local manifest tokens count missing=""
  # The manifest block: from the marker line to the end of that HTML comment.
  manifest=$(awk '/AGENT: PLACEHOLDER MANIFEST/{f=1} f{print} f&&/-->/{exit}' "$template")
  if [ -z "$manifest" ]; then
    echo "  templates/uat/test-session-template.html has no 'AGENT: PLACEHOLDER MANIFEST' block" >&2
    return 1
  fi
  # Placeholders that SURVIVE comment-stripping = the ones an author must
  # replace. Sourced from the linter itself so the two cannot disagree.
  set +e
  tokens=$(bash "$LINTER" "$template" 2>&1 | grep -o '__[A-Z][A-Z_]*__' | sort -u)
  set -e
  count=$(printf '%s\n' "$tokens" | grep -c '__')
  if [ "$count" -lt 7 ]; then
    echo "  derived only $count placeholder token(s) from the seed template (floor 7) — derivation is vacuous" >&2
    return 1
  fi
  local t
  for t in $tokens; do
    case "$manifest" in *"$t"*) ;; *) missing="$missing $t" ;; esac
  done
  if [ -n "$missing" ]; then
    echo "  placeholder(s) present in the template but ABSENT from the manifest:$missing" >&2
    return 1
  fi
  # And the one the walk found must be named as the easy-to-miss one.
  case "$manifest" in *ISSUE-008*) ;; *)
    echo "  the manifest does not flag __FEATURE_OPTIONS__ as the mid-file outlier (walk ISSUE-008)" >&2
    return 1 ;;
  esac
}

case_11_multiple_violations() {
  local work; work=$(mktemp -d); trap "rm -rf '$work'" RETURN
  seed_html "$work/bad.html" '[
    {"id":1,"feature":1,"title":"T1","steps":"1. run","expected":"OK"},
    {"id":2,"feature":1,"title":"T2","steps":"2. see above","expected":"works"},
    {"id":3,"feature":1,"title":"T3","steps":"3. do stuff","expected":"succeeds"}
  ]'
  set +e
  local out; out=$(bash "$LINTER" "$work/bad.html" 2>&1)
  local code=$?
  set -e
  assert_eq "1" "$code"
  assert_contains "$out" "violations found" "summary line present"
}

echo "═══ test-lint-uat-scenarios.sh ═══"
run_case "case 1: happy path"                        case_1_happy_path
run_case "case 2: unreplaced __TESTER_PRE_FLIGHT__"  case_2_unreplaced_preflight_placeholder
run_case "case 3: unreplaced __SCENARIOS_JSON__"     case_3_unreplaced_scenarios_placeholder
run_case "case 4: expected too short"                case_4_expected_too_short
run_case "case 5: expected is banned phrase"         case_5_expected_banned_phrase
run_case "case 6: banned cross-ref"                  case_6_banned_cross_ref
run_case "case 7: missing state-restatement"         case_7_missing_state_restatement
run_case "case 8: duplicate scenario IDs"            case_8_duplicate_ids
run_case "case 9: missing input file"                case_9_missing_file
run_case "case 10: malformed JSON"                   case_10_malformed_json
run_case "case 11: multiple violations"              case_11_multiple_violations
run_case "case 12: seed template no __PLACEHOLDER__" case_12_seed_template_no_placeholder_collision
run_case "case 13: seed template placeholder manifest is complete" case_13_seed_template_placeholder_manifest_is_complete

echo ""
echo "═══════════════════════════════════════════"
echo "Tests: $PASSED passed, $FAILED failed"
echo "═══════════════════════════════════════════"
[ "$FAILED" -eq 0 ]
