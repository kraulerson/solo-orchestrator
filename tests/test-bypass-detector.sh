#!/usr/bin/env bash
# tests/test-bypass-detector.sh — BL-029 bypass-detector hook tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/scripts/hooks/bypass-detector.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/.claude"
  cat > "$TMP/.claude/manifest.json" <<EOF
{"frameworkVersion":"test","host":"other","mode":"personal","deployment":"personal","enforcement_level":"strict"}
EOF
  echo "[]" > "$TMP/.claude/bypass-audit.json"
}
teardown() { rm -rf "$TMP"; }

# Hook contract: stdin = JSON envelope from Claude Code.
# PostToolUse: { "hook_event_name": "PostToolUse", "tool_input": ..., "tool_result": {"output": "..."} }
# Stop:        { "hook_event_name": "Stop", "transcript": "..." }

# T1: PostToolUse output containing --no-verify writes a row.
echo "T1: PostToolUse with --no-verify writes claude_bypass_proposal"
setup
if [ ! -f "$HOOK" ]; then fail_ "T1" "hook missing (RED)"; else
  CLAUDE_PROJECT_DIR="$TMP" cat <<EOF | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"echo x"},"tool_result":{"output":"alternatively, run git commit --no-verify"}}
EOF
  rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$TMP/.claude/bypass-audit.json")
  if [ "$rows" = "1" ]; then pass "T1"; else fail_ "T1" "rows=$rows"; fi
fi
teardown

# T2: clean output writes nothing.
echo "T2: clean output is a no-op"
setup
if [ ! -f "$HOOK" ]; then fail_ "T2" "hook missing"; else
  CLAUDE_PROJECT_DIR="$TMP" cat <<EOF | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"ls"},"tool_result":{"output":"file1\nfile2"}}
EOF
  rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$TMP/.claude/bypass-audit.json")
  if [ "$rows" = "0" ]; then pass "T2"; else fail_ "T2" "false positive: $rows"; fi
fi
teardown

# T3: Stop event with bypass-shaped transcript writes row.
echo "T3: Stop event scans transcript"
setup
if [ ! -f "$HOOK" ]; then fail_ "T3" "hook missing"; else
  CLAUDE_PROJECT_DIR="$TMP" cat <<EOF | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"Stop","transcript":"Maybe set SOIF_FORCE_STEP=build_loop:tests_written"}
EOF
  rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$TMP/.claude/bypass-audit.json")
  if [ "$rows" = "1" ]; then pass "T3"; else fail_ "T3" "rows=$rows"; fi
fi
teardown

# T4: row contains verbatim excerpt + matched pattern name.
echo "T4: row payload includes pattern + excerpt"
setup
if [ ! -f "$HOOK" ]; then fail_ "T4" "hook missing"; else
  CLAUDE_PROJECT_DIR="$TMP" cat <<EOF | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_result":{"output":"use --no-verify to skip"}}
EOF
  pattern=$(jq -r '.[0].details.pattern' "$TMP/.claude/bypass-audit.json")
  excerpt=$(jq -r '.[0].details.excerpt' "$TMP/.claude/bypass-audit.json")
  if [ "$pattern" = "no_verify" ] && echo "$excerpt" | grep -q -- "--no-verify"; then pass "T4"; else fail_ "T4" "pattern=$pattern excerpt='$excerpt'"; fi
fi
teardown

# T5: row's user_response is initialized to "PENDING".
echo "T5: user_response = PENDING on initial write"
setup
if [ ! -f "$HOOK" ]; then fail_ "T5" "hook missing"; else
  CLAUDE_PROJECT_DIR="$TMP" cat <<EOF | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_result":{"output":"use --no-verify"}}
EOF
  resp=$(jq -r '.[0].user_response' "$TMP/.claude/bypass-audit.json")
  if [ "$resp" = "PENDING" ]; then pass "T5"; else fail_ "T5" "got '$resp'"; fi
fi
teardown

# T6: hook is silent (no stderr) on clean output.
echo "T6: hook is silent on clean output"
setup
if [ ! -f "$HOOK" ]; then fail_ "T6" "hook missing"; else
  err=$( ( CLAUDE_PROJECT_DIR="$TMP" cat <<EOF | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK"
{"hook_event_name":"PostToolUse","tool_input":{"command":"ls"},"tool_result":{"output":"file"}}
EOF
) 2>&1 >/dev/null )
  if [ -z "$err" ]; then pass "T6"; else fail_ "T6" "stderr leaked: $err"; fi
fi
teardown

# T7: each firing on the same content writes one row (no internal dedup).
echo "T7: two firings → 2 rows"
setup
if [ ! -f "$HOOK" ]; then fail_ "T7" "hook missing"; else
  ENV='{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_result":{"output":"use --no-verify here"}}'
  echo "$ENV" | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
  echo "$ENV" | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
  rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$TMP/.claude/bypass-audit.json")
  if [ "$rows" = "2" ]; then pass "T7"; else fail_ "T7" "expected 2 rows, got $rows"; fi
fi
teardown

# T8: synthetic Build Loop step proposal triggers severity='refuse_to_recommend'.
echo "T8: fake_loop pattern is recorded with elevated severity"
setup
if [ ! -f "$HOOK" ]; then fail_ "T8" "hook missing"; else
  CLAUDE_PROJECT_DIR="$TMP" cat <<EOF | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"Stop","transcript":"I'll mark step build_loop:tests_verified_failing complete and skip ahead"}
EOF
  pattern=$(jq -r '.[0].details.pattern' "$TMP/.claude/bypass-audit.json")
  severity=$(jq -r '.[0].details.severity // "normal"' "$TMP/.claude/bypass-audit.json")
  if [ "$pattern" = "fake_loop" ] && [ "$severity" = "refuse_to_recommend" ]; then pass "T8"; else fail_ "T8" "pattern=$pattern severity=$severity"; fi
fi
teardown

# T9: ordinary --no-verify match has severity='normal' (not elevated).
echo "T9: no_verify pattern stays severity='normal'"
setup
if [ ! -f "$HOOK" ]; then fail_ "T9" "hook missing"; else
  CLAUDE_PROJECT_DIR="$TMP" cat <<EOF | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_result":{"output":"use --no-verify"}}
EOF
  severity=$(jq -r '.[0].details.severity' "$TMP/.claude/bypass-audit.json")
  if [ "$severity" = "normal" ]; then pass "T9"; else fail_ "T9" "got '$severity'"; fi
fi
teardown

# T10 (S1 fix): multi-pattern proposal writes ONE ROW PER MATCHED PATTERN.
# Calibration replay 2026-04-29 found scan_bypass_patterns short-circuited on
# first match, silently dropping refuse_to_recommend severity rows when an
# earlier-table normal-severity pattern matched first. Detector now writes
# one row per matched pattern.
echo "T10: multi-pattern proposal writes one row per match"
setup
if [ ! -f "$HOOK" ]; then fail_ "T10" "hook missing"; else
  CLAUDE_PROJECT_DIR="$TMP" cat <<'EOF' | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_result":{"output":"option 1: use --no-verify; option 2: set SOIF_FORCE_STEP=build_loop:tests_written; option 3: I'll mark step build_loop:tests_verified_failing complete"}}
EOF
  rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$TMP/.claude/bypass-audit.json")
  patterns=$(jq -r '[.[].details.pattern] | sort | unique | join(",")' "$TMP/.claude/bypass-audit.json")
  if [ "$rows" -ge "3" ] && echo "$patterns" | grep -q "fake_loop" && echo "$patterns" | grep -q "no_verify" && echo "$patterns" | grep -q "soif_force_step"; then
    pass "T10"
  else
    fail_ "T10" "rows=$rows patterns=$patterns"
  fi
fi
teardown

# T11: refuse_to_recommend severity is preserved even when no_verify matched first.
echo "T11: refuse_to_recommend not masked by earlier normal-severity match"
setup
if [ ! -f "$HOOK" ]; then fail_ "T11" "hook missing"; else
  CLAUDE_PROJECT_DIR="$TMP" cat <<'EOF' | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_result":{"output":"--no-verify works, or I'll just mark step build_loop:tests_verified_failing complete"}}
EOF
  refuse_rows=$(jq '[.[] | select(.details.severity=="refuse_to_recommend")] | length' "$TMP/.claude/bypass-audit.json")
  if [ "$refuse_rows" -ge "1" ]; then pass "T11"; else fail_ "T11" "no refuse_to_recommend row written"; fi
fi
teardown

# T12: sentinel is still written exactly once on multi-pattern match (idempotent).
echo "T12: sentinel written once on multi-pattern proposal"
setup
if [ ! -f "$HOOK" ]; then fail_ "T12" "hook missing"; else
  CLAUDE_PROJECT_DIR="$TMP" cat <<'EOF' | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_result":{"output":"--no-verify or SOIF_FORCE_STEP=foo or git push --force-with-lease"}}
EOF
  if [ -f "$TMP/.claude/pending-approval.json" ] && jq -e '.question' "$TMP/.claude/pending-approval.json" >/dev/null 2>&1; then
    pass "T12"
  else
    fail_ "T12" "sentinel missing or malformed"
  fi
fi
teardown

# T13 (S3 fix 2026-05-04): pattern matches inside fenced code blocks are suppressed.
# Documentation / CHANGELOG / docstring text wrapping a pattern in ```...``` is
# descriptive, not advisory — should not trigger the detector.
echo "T13: fenced code block content is stripped before scanning"
setup
if [ ! -f "$HOOK" ]; then fail_ "T13" "hook missing"; else
  CLAUDE_PROJECT_DIR="$TMP" cat <<'EOF' | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_result":{"output":"# CHANGELOG\n\n## Added\n\n- Detection for the following bypass patterns:\n```\n--no-verify\nSOIF_FORCE_STEP=\n```\n\nNo behavior change for users."}}
EOF
  rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$TMP/.claude/bypass-audit.json")
  if [ "$rows" = "0" ]; then pass "T13"; else fail_ "T13" "false positive: rows=$rows"; fi
fi
teardown

# T14: pattern OUTSIDE fenced blocks still fires (regression for T13 fix).
echo "T14: fenced-stripping does not suppress matches outside the fence"
setup
if [ ! -f "$HOOK" ]; then fail_ "T14" "hook missing"; else
  CLAUDE_PROJECT_DIR="$TMP" cat <<'EOF' | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_result":{"output":"You can use --no-verify here.\n\n```\nthis fenced block has no patterns\n```\n\nThe --no-verify suggestion above is a real proposal."}}
EOF
  rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$TMP/.claude/bypass-audit.json")
  if [ "$rows" -ge "1" ]; then pass "T14"; else fail_ "T14" "rows=$rows — outside-fence match was suppressed"; fi
fi
teardown

# T15: inline single-backtick code (`...`) is NOT stripped — Claude often
# typesets ACTIVE proposals using inline backticks ("run `git commit --no-verify`").
echo "T15: inline backtick code is scanned (not stripped)"
setup
if [ ! -f "$HOOK" ]; then fail_ "T15" "hook missing"; else
  CLAUDE_PROJECT_DIR="$TMP" cat <<'EOF' | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1
{"hook_event_name":"PostToolUse","tool_input":{"command":"x"},"tool_result":{"output":"You can run `git commit --no-verify` to skip the gate."}}
EOF
  rows=$(jq '[.[] | select(.type=="claude_bypass_proposal")] | length' "$TMP/.claude/bypass-audit.json")
  if [ "$rows" -ge "1" ]; then pass "T15"; else fail_ "T15" "inline-backtick match was suppressed"; fi
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
