#!/usr/bin/env bash
# tests/test-bl030-calibration-replay.sh — replay calibration scenario S11
# across all three enforcement levels. The design's central invariant
# (BL-029 is universal; BL-030 layers on top) must hold at each level:
#   - strict: --no-verify bypass STILL recorded by SessionStart detector
#   - light:  user terminal commit recorded
#   - no:     user terminal commit NOT recorded, but the Claude-side
#             audit (enforcement_level_set row from init) is present
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT="$REPO_ROOT/init.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

cd /tmp

run_init() {
  local proj="$1" level="$2"
  local extra=""
  if [ "$level" != "strict" ]; then extra="--enforcement-level $level --confirm-pitfalls"; fi
  # shellcheck disable=SC2086
  bash "$INIT" --non-interactive --project x --project-dir "$proj" --no-remote-creation \
    --platform web --language typescript --track light --deployment personal $extra \
    >/dev/null 2>&1
}

# strict: user terminal --no-verify lands but is detected on next session.
echo "REPLAY strict: --no-verify bypass is recorded on next session start"
TMP=$(mktemp -d); PROJ="$TMP/p"
run_init "$PROJ" "strict"
# --no-verify bypasses the framework gate that strict mode installed,
# but the SessionStart detector should still capture the commit.
( cd "$PROJ" && echo bypass > b.txt && git add b.txt && git commit --no-verify -qm "user --no-verify bypass" )
bash "$PROJ/scripts/detect-out-of-band-commits.sh" "$PROJ" >/dev/null 2>&1
rows=$(jq '[.[] | select(.type=="out_of_band_commit")] | length' "$PROJ/.claude/bypass-audit.json")
if [ "$rows" -ge "1" ]; then pass "strict: --no-verify recorded"; else fail_ "strict" "no row written"; fi
rm -rf "$TMP"

# light: user terminal commit lands without block, recorded on next session.
echo "REPLAY light: terminal commit lands and is recorded"
TMP=$(mktemp -d); PROJ="$TMP/p"
run_init "$PROJ" "light"
( cd "$PROJ" && echo light > l.txt && git add l.txt && git commit -qm "user light commit" )
bash "$PROJ/scripts/detect-out-of-band-commits.sh" "$PROJ" >/dev/null 2>&1
rows=$(jq '[.[] | select(.type=="out_of_band_commit")] | length' "$PROJ/.claude/bypass-audit.json")
if [ "$rows" -ge "1" ]; then pass "light: terminal commit recorded"; else fail_ "light" "no row written"; fi
rm -rf "$TMP"

# no: user terminal commit lands without block AND is NOT recorded.
echo "REPLAY no: terminal commit lands and is NOT recorded"
TMP=$(mktemp -d); PROJ="$TMP/p"
run_init "$PROJ" "no"
( cd "$PROJ" && echo no > n.txt && git add n.txt && git commit -qm "user no-mode commit" )
bash "$PROJ/scripts/detect-out-of-band-commits.sh" "$PROJ" >/dev/null 2>&1
rows=$(jq '[.[] | select(.type=="out_of_band_commit")] | length' "$PROJ/.claude/bypass-audit.json")
if [ "$rows" = "0" ]; then pass "no: terminal commit NOT recorded"; else fail_ "no" "$rows rows written"; fi

# But the init-time row should still exist (Claude-side audit always-on).
init_rows=$(jq '[.[] | select(.type=="enforcement_level_set")] | length' "$PROJ/.claude/bypass-audit.json")
if [ "$init_rows" -ge "1" ]; then pass "no: framework-side audit still on"; else fail_ "no-framework-audit" "init row absent"; fi
rm -rf "$TMP"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
