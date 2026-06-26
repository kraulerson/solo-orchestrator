#!/usr/bin/env bash
# tests/test-enforcement-level-reconfigure.sh — BL-030 reconfigure tests.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT="$REPO_ROOT/init.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# init.sh refuses to run from inside the framework repo.
cd /tmp

# Set up a personal/strict project. The reconfigure script must be
# invoked via the PROJECT-LOCAL copy (PROJECT_ROOT = ../scripts/..) so
# init.sh installs it into each test project.
setup_personal() {
  TMP=$(mktemp -d); PROJ="$TMP/p"
  bash "$INIT" --non-interactive --project x --project-dir "$PROJ" --no-remote-creation \
    --platform web --language javascript --track light --deployment personal \
    >/dev/null 2>&1
  RECONFIG="$PROJ/scripts/reconfigure-project.sh"
}
setup_org_production() {
  TMP=$(mktemp -d); PROJ="$TMP/p"
  bash "$INIT" --non-interactive --project x --project-dir "$PROJ" --no-remote-creation \
    --platform web --language javascript --track standard --deployment organizational --gov-mode production \
    >/dev/null 2>&1
  RECONFIG="$PROJ/scripts/reconfigure-project.sh"
}
teardown() { rm -rf "$TMP"; }

# T1: strict→light on personal with --confirm-pitfalls succeeds.
echo "T1: strict→light on personal succeeds with --confirm-pitfalls"
setup_personal
if [ -x "$RECONFIG" ] && ( cd "$PROJ" && bash "$RECONFIG" --enforcement-level light --confirm-pitfalls >/dev/null 2>&1 ); then
  level=$(jq -r '.enforcement_level' "$PROJ/.claude/manifest.json")
  if [ "$level" = "light" ]; then pass "T1"; else fail_ "T1" "level=$level"; fi
else
  fail_ "T1" "reconfigure failed (or not installed)"
fi
teardown

# T2: strict→light on personal WITHOUT --confirm-pitfalls fails.
echo "T2: strict→light without --confirm-pitfalls fails"
setup_personal
( cd "$PROJ" && bash "$RECONFIG" --enforcement-level light >/dev/null 2>&1 )
if [ $? -ne 0 ]; then pass "T2"; else fail_ "T2" "expected non-zero"; fi
teardown

# T3: any→light on org+production fails.
echo "T3: org+production rejects --enforcement-level light"
setup_org_production
( cd "$PROJ" && bash "$RECONFIG" --enforcement-level light --confirm-pitfalls >/dev/null 2>&1 )
if [ $? -ne 0 ]; then pass "T3"; else fail_ "T3" "expected non-zero"; fi
teardown

# T4: light→strict installs filesystem gate.
echo "T4: light→strict installs filesystem gate"
TMP=$(mktemp -d); PROJ="$TMP/p"
bash "$INIT" --non-interactive --project x --project-dir "$PROJ" --no-remote-creation \
  --platform web --language javascript --track light --deployment personal \
  --enforcement-level light --confirm-pitfalls >/dev/null 2>&1
RECONFIG="$PROJ/scripts/reconfigure-project.sh"
if ( cd "$PROJ" && bash "$RECONFIG" --enforcement-level strict >/dev/null 2>&1 ); then
  if grep -q "SOIF framework gate" "$PROJ/.git/hooks/pre-commit" 2>/dev/null; then pass "T4"; else fail_ "T4" "marker not added"; fi
else
  fail_ "T4" "reconfigure failed"
fi
teardown

# T5: strict→light uninstalls filesystem gate.
echo "T5: strict→light uninstalls filesystem gate"
setup_personal
if ( cd "$PROJ" && bash "$RECONFIG" --enforcement-level light --confirm-pitfalls >/dev/null 2>&1 ); then
  if ! grep -q "SOIF framework gate" "$PROJ/.git/hooks/pre-commit" 2>/dev/null; then pass "T5"; else fail_ "T5" "marker still present"; fi
else
  fail_ "T5" "reconfigure failed"
fi
teardown

# T6: each transition appends one enforcement_level_set audit row.
echo "T6: transitions are recorded in audit log"
setup_personal
initial=$(jq '[.[] | select(.type=="enforcement_level_set")] | length' "$PROJ/.claude/bypass-audit.json")
( cd "$PROJ" && bash "$RECONFIG" --enforcement-level light --confirm-pitfalls >/dev/null 2>&1 )
after=$(jq '[.[] | select(.type=="enforcement_level_set")] | length' "$PROJ/.claude/bypass-audit.json")
if [ "$after" = "$((initial + 1))" ]; then pass "T6"; else fail_ "T6" "rows: $initial → $after"; fi
teardown

# T7: --reset-detection-baseline writes current HEAD.
echo "T7: --reset-detection-baseline updates last-checked-commit.txt"
setup_personal
( cd "$PROJ" && echo z > z && git add z && git commit -qm z )
expected=$(cd "$PROJ" && git rev-parse HEAD)
if ( cd "$PROJ" && bash "$RECONFIG" --reset-detection-baseline >/dev/null 2>&1 ); then
  actual=$(cat "$PROJ/.claude/last-checked-commit.txt")
  if [ "$actual" = "$expected" ]; then pass "T7"; else fail_ "T7" "$expected vs $actual"; fi
else
  fail_ "T7" "reconfigure failed"
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
