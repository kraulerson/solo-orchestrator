#!/usr/bin/env bash
# tests/test-verify-install-bl030-coverage.sh — verify-install.sh must
# check the BL-030 scripts, libs, and hook registrations. Without these
# checks, a hand-edited or pre-BL-030 project passes verify with the
# BL-030 chain silently broken — exactly the silent-degrade class
# code-verify-reconfigure-10 was rewritten to prevent.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT="$REPO_ROOT/init.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

cd /tmp

setup_clean_project() {
  TMP=$(mktemp -d); PROJ="$TMP/p"
  bash "$INIT" --non-interactive --project x --project-dir "$PROJ" --no-remote-creation \
    --platform web --language typescript --track light --deployment personal \
    >/dev/null 2>&1
  VERIFY="$PROJ/scripts/verify-install.sh"
}
teardown() { rm -rf "$TMP"; }

# Helper: run verify in check-only mode and capture stdout.
run_verify() {
  ( cd "$PROJ" && bash "$VERIFY" --check-only 2>&1 ) || true
}

# T1: clean project passes BL-030 script checks for the 4 new scripts.
echo "T1: clean project — verify reports BL-030 scripts present/executable"
setup_clean_project
out=$(run_verify)
fail_count=0
for s in detect-out-of-band-commits install-filesystem-gates record-claude-commit lint-fixture-envelopes; do
  if ! echo "$out" | grep -qE "\[OK\] $s present and executable"; then
    fail_count=$((fail_count + 1))
    echo "    (missing OK row for $s)"
  fi
done
if [ "$fail_count" = "0" ]; then
  pass "T1: all 4 BL-030 scripts checked + reported OK"
else
  fail_ "T1" "$fail_count of 4 BL-030 scripts not checked by verify-install"
fi
teardown

# T2: verify detects missing record-claude-commit.sh (PostToolUse hook script).
echo "T2: missing record-claude-commit.sh is flagged"
setup_clean_project
rm -f "$PROJ/scripts/hooks/record-claude-commit.sh"
out=$(run_verify)
if echo "$out" | grep -qE "record-claude-commit (missing|not executable)"; then
  pass "T2: missing record-claude-commit.sh flagged"
else
  fail_ "T2" "no flag for missing record-claude-commit"
fi
teardown

# T3: verify detects missing detect-out-of-band-commits.sh.
echo "T3: missing detect-out-of-band-commits.sh is flagged"
setup_clean_project
rm -f "$PROJ/scripts/detect-out-of-band-commits.sh"
out=$(run_verify)
if echo "$out" | grep -qE "detect-out-of-band-commits (missing|not executable)"; then
  pass "T3: missing detect-out-of-band-commits flagged"
else
  fail_ "T3" "no flag for missing detect-out-of-band-commits"
fi
teardown

# T4: verify detects missing install-filesystem-gates.sh.
echo "T4: missing install-filesystem-gates.sh is flagged"
setup_clean_project
rm -f "$PROJ/scripts/install-filesystem-gates.sh"
out=$(run_verify)
if echo "$out" | grep -qE "install-filesystem-gates (missing|not executable)"; then
  pass "T4: missing install-filesystem-gates flagged"
else
  fail_ "T4" "no flag for missing install-filesystem-gates"
fi
teardown

# T5: verify detects missing lib/enforcement-level.sh.
echo "T5: missing lib/enforcement-level.sh is flagged"
setup_clean_project
rm -f "$PROJ/scripts/lib/enforcement-level.sh"
out=$(run_verify)
if echo "$out" | grep -qE "enforcement-level lib (missing|not present)"; then
  pass "T5: missing lib/enforcement-level.sh flagged"
else
  fail_ "T5" "no flag for missing enforcement-level lib"
fi
teardown

# T6: verify detects missing PostToolUse:record-claude-commit hook
# registration in .claude/settings.json.
echo "T6: PostToolUse missing record-claude-commit hook is flagged"
setup_clean_project
# Strip the registration.
tmp=$(mktemp)
jq '(.hooks.PostToolUse // []) |= map(.hooks |= [.[] | select(.command | contains("record-claude-commit.sh") | not)])' \
  "$PROJ/.claude/settings.json" > "$tmp" && mv "$tmp" "$PROJ/.claude/settings.json"
out=$(run_verify)
if echo "$out" | grep -qE "PostToolUse hook: record-claude-commit.*not registered"; then
  pass "T6: missing PostToolUse:record-claude-commit hook flagged"
else
  fail_ "T6" "no flag for missing record-claude-commit hook"
fi
teardown

# T7: verify detects missing SessionStart:detect-out-of-band hook.
echo "T7: SessionStart missing detect-out-of-band hook is flagged"
setup_clean_project
tmp=$(mktemp)
jq '(.hooks.SessionStart // []) |= map(.hooks |= [.[] | select(.command | contains("detect-out-of-band-commits.sh") | not)])' \
  "$PROJ/.claude/settings.json" > "$tmp" && mv "$tmp" "$PROJ/.claude/settings.json"
out=$(run_verify)
if echo "$out" | grep -qE "SessionStart hook: detect-out-of-band.*not registered"; then
  pass "T7: missing SessionStart:detect-out-of-band hook flagged"
else
  fail_ "T7" "no flag for missing detect-out-of-band hook"
fi
teardown

# T8: verify detects missing PostToolUse:bypass-detector hook (BL-029
# regression coverage gap noted by the survey).
echo "T8: PostToolUse missing bypass-detector hook (BL-029) is flagged"
setup_clean_project
tmp=$(mktemp)
jq '(.hooks.PostToolUse // []) |= map(.hooks |= [.[] | select(.command | contains("bypass-detector.sh") | not)])' \
  "$PROJ/.claude/settings.json" > "$tmp" && mv "$tmp" "$PROJ/.claude/settings.json"
out=$(run_verify)
if echo "$out" | grep -qE "(PostToolUse|Stop) hook: bypass-detector.*not registered"; then
  pass "T8: missing bypass-detector hook flagged"
else
  fail_ "T8" "no flag for missing bypass-detector hook"
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
