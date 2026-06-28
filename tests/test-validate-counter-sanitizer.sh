#!/usr/bin/env bash
# tests/test-validate-counter-sanitizer.sh
#
# Regression: three scripts used the antipattern
#   var=$(cmd_that_may_exit_nonzero || echo "0")
# where the inner command can print a leading "0\n" before failing, so
# the `||` appends a second "0" — the variable ends up holding the
# two-line string "0\n0" (grep -c case) or the literal string "null"
# (jq -r on a missing key case). Subsequent arithmetic tests
# (`[ "$var" -gt 0 ]`, `[ "$var" -eq 0 ]`) then error with
# "integer expression expected", and under `set -euo pipefail` the
# failed arithmetic returns non-zero — silently skipping the warning
# branch the gate was supposed to take.
#
# Sites covered here:
#
# 1. scripts/validate.sh:258 — `grep -c "[RESET]" .claude/process-audit.log
#    || echo "0"` feeding `[ "$reset_count" -gt 0 ]`. On a zero-match log
#    this leaked "integer expression expected" to stderr and the
#    "no resets recorded" OK branch never fired.
#
# 2. scripts/session-test-gate-check.sh:198 — `jq -r '.features_completed
#    | length' || echo "0"` feeding `[ "$FEATURES_COMPLETED" -eq 0 ]`.
#    If build-progress.json is missing the .features_completed key, jq
#    on the .length filter against null fails (jq -r prints "null"
#    on `null | length` → error), so the `|| echo "0"` fallback fires
#    but the variable can also hold "null" depending on jq's behavior.
#    The downstream `-eq 0` then errors.
#
# 3. scripts/session-end-qdrant-reminder.sh:36-38 — three sites using
#    `jq '... | length' "$TOOL_USAGE" || echo "0"`. Advisory-only output
#    but the captured value is later compared with `-eq 0` /  `-gt 0`,
#    same defect class.
#
# Fix: append the sanitizer line immediately after the capture
#   case "$var" in ''|*[!0-9]*) var=0 ;; esac
# so the arithmetic always sees a single non-negative integer.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATE="$REPO_ROOT/scripts/validate.sh"
GATE_CHECK="$REPO_ROOT/scripts/session-test-gate-check.sh"
QDRANT_REMINDER="$REPO_ROOT/scripts/session-end-qdrant-reminder.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup() {
  TMP=$(mktemp -d)
  PROJ="$TMP/p"
  mkdir -p "$PROJ/.claude"
  # Minimal CLAUDE.md so validate.sh doesn't early-exit on "not a project"
  cat > "$PROJ/CLAUDE.md" <<'MD'
# Project Context
- **Project:** SanitizerTest
- **Platform:** web
- **Track:** standard
- **Primary Language:** typescript
MD
}
teardown() { rm -rf "$TMP"; }

# Run validate.sh capturing stdout+stderr separately so we can assert
# that NOTHING bash-arithmetic-related leaks to stderr.
run_validate() {
  ( cd "$PROJ" && bash "$VALIDATE" >"$TMP/out" 2>"$TMP/err" ) || true
}

run_gate_check() {
  ( cd "$PROJ" && bash "$GATE_CHECK" </dev/null >"$TMP/out" 2>"$TMP/err" ) || true
}

run_qdrant_reminder() {
  ( cd "$PROJ" && bash "$QDRANT_REMINDER" >"$TMP/out" 2>"$TMP/err" ) || true
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Site 1: scripts/validate.sh:258 — [RESET] grep counter ==="
# ════════════════════════════════════════════════════════════════════

# T1: process-audit.log present with one [RESET] line → WARN fires.
echo "T1: process-audit.log has 1 [RESET] line → WARN about resets"
setup
cat > "$PROJ/.claude/process-audit.log" <<'LOG'
2026-06-20T10:00:00Z [START] some normal entry
2026-06-21T11:00:00Z [RESET] manual counter reset for X
2026-06-22T12:00:00Z [START] another normal entry
LOG
run_validate
if grep -q "process-audit.log contains 1 reset event" "$TMP/out"; then
  pass "T1: WARN fires with reset_count=1"
else
  fail_ "T1" "expected WARN about 1 reset event; out:\n$(grep -i 'process-audit\|reset' "$TMP/out" || true)"
fi
teardown

# T2: process-audit.log present with ZERO [RESET] lines. Pre-fix this
# is the defect: grep -c exits 1, prints "0\n", `||` appends a second
# "0", reset_count="0\n0", `[ "$reset_count" -gt 0 ]` errors with
# 'integer expression expected' to stderr AND skips the OK branch
# (under set -euo pipefail the failed arithmetic short-circuits).
# Post-fix: the [OK] line fires AND stderr is clean of arithmetic
# errors.
echo "T2: process-audit.log has 0 [RESET] lines → [OK] no resets AND clean stderr"
setup
cat > "$PROJ/.claude/process-audit.log" <<'LOG'
2026-06-20T10:00:00Z [START] some normal entry
2026-06-22T12:00:00Z [START] another normal entry
LOG
run_validate

ok_branch_hit=false
if grep -q "process-audit.log (no resets recorded)" "$TMP/out"; then
  ok_branch_hit=true
fi

stderr_clean=true
if grep -q "integer expression expected" "$TMP/err"; then
  stderr_clean=false
fi

if $ok_branch_hit && $stderr_clean; then
  pass "T2: [OK] no-resets branch fired AND stderr clean (no arithmetic leak)"
elif ! $ok_branch_hit && ! $stderr_clean; then
  fail_ "T2" "OK branch missed AND 'integer expression expected' leaked:\nstdout reset line: $(grep -i 'process-audit\|reset' "$TMP/out" || echo NONE)\nstderr: $(grep -i integer "$TMP/err" || echo NONE)"
elif ! $ok_branch_hit; then
  fail_ "T2" "OK branch missed (stderr was clean):\nstdout reset line: $(grep -i 'process-audit\|reset' "$TMP/out" || echo NONE)"
else
  fail_ "T2" "'integer expression expected' leaked to stderr (OK branch fired):\nstderr: $(grep -i integer "$TMP/err" || echo NONE)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Site 2: scripts/session-test-gate-check.sh:198 — features_completed ==="
# ════════════════════════════════════════════════════════════════════

if ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] jq not available — skipping Site 2 + Site 3 (jq-dependent)"
else

# T3: Phase 2 with build-progress.json that is MISSING the
# .features_completed key entirely. Pre-fix: jq -r '.features_completed
# | length' on a missing key prints "null" and exits 0 (the `||` doesn't
# fire), but downstream `[ "$FEATURES_COMPLETED" -eq 0 ]` then errors
# with "integer expression expected" because "null" isn't an integer.
# Under set -euo pipefail, the failed arithmetic short-circuits the
# Phase-2-no-features warning. Post-fix: the sanitizer turns "null"
# into 0 and the no-features detector behaves correctly.
echo "T3: build-progress.json missing .features_completed → no arithmetic leak"
setup
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":2,"deployment":"personal","gates":{"phase_1_to_2":"2026-01-01"}}
JSON
cat > "$PROJ/.claude/build-progress.json" <<'JSON'
{"features_since_last_test":0,"test_interval":2,"testing_required":false}
JSON
( cd "$PROJ" && printf '{"hook_event_name":"SessionStart","source":"startup"}' \
    | bash "$GATE_CHECK" >"$TMP/out" 2>"$TMP/err" ) || true

if grep -q "integer expression expected" "$TMP/err"; then
  fail_ "T3" "'integer expression expected' leaked to stderr:\n$(grep -i integer "$TMP/err")"
else
  pass "T3: no 'integer expression expected' leak with missing features_completed key"
fi
teardown

# T4: Phase 2 with build-progress.json that has features_completed=[]
# (empty array) AND zero commits on main since the gate date. The
# no-features branch's inner COMMIT_COUNT check (`-gt 5`) must NOT
# warn, since there's no evidence of missed --record-feature calls.
# This is the regression guard for the happy path of the same fix.
echo "T4: features_completed=[] with no commits since gate → no false TEST GATE WARNING"
setup
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":2,"deployment":"personal","gates":{"phase_1_to_2":"2099-01-01"}}
JSON
cat > "$PROJ/.claude/build-progress.json" <<'JSON'
{"features_completed":[],"features_since_last_test":0,"test_interval":2,"testing_required":false}
JSON
( cd "$PROJ" && printf '{"hook_event_name":"SessionStart","source":"startup"}' \
    | bash "$GATE_CHECK" >"$TMP/out" 2>"$TMP/err" ) || true

if grep -q "integer expression expected" "$TMP/err"; then
  fail_ "T4" "'integer expression expected' leaked to stderr:\n$(grep -i integer "$TMP/err")"
elif grep -q "TEST GATE WARNING" "$TMP/out"; then
  fail_ "T4" "false TEST GATE WARNING with zero commits since future gate date; out:\n$(cat "$TMP/out")"
else
  pass "T4: clean run with no false warning + no arithmetic leak"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Site 3: scripts/session-end-qdrant-reminder.sh:36-38 — qdrant counters ==="
# ════════════════════════════════════════════════════════════════════

# T5: tool-usage.json has all-empty arrays. Post-fix the three counters
# should each be 0 and no 'integer expression expected' should leak,
# even though the script ONLY runs if Qdrant MCP is configured. We
# simulate that by pointing HOME at a tempdir with a settings.json
# that registers a qdrant MCP server.
echo "T5: empty tool-usage.json with qdrant configured → counts=0, no stderr leak"
setup
FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.claude"
cat > "$FAKE_HOME/.claude/settings.json" <<'JSON'
{"mcpServers":{"qdrant":{"command":"true"}}}
JSON
cat > "$PROJ/.claude/tool-usage.json" <<'JSON'
{"calls":[],"commits_since_last_context7":0,"qdrant_store_called":false}
JSON
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":2}
JSON
( cd "$PROJ" && HOME="$FAKE_HOME" bash "$QDRANT_REMINDER" >"$TMP/out" 2>"$TMP/err" ) || true

if grep -q "integer expression expected" "$TMP/err"; then
  fail_ "T5" "'integer expression expected' leaked to stderr:\n$(grep -i integer "$TMP/err")"
elif ! grep -q "Context7: 0 calls" "$TMP/out"; then
  fail_ "T5" "Expected 'Context7: 0 calls' in tool usage line; out:\n$(grep -i 'tool usage\|context7' "$TMP/out" || echo NONE)"
else
  pass "T5: counts=0 cleanly with no arithmetic leak"
fi
teardown

fi  # /jq available

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
