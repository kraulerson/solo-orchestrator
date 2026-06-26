#!/usr/bin/env bash
# tests/test-enforcement-level-init.sh — BL-030 init UX tests.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT="$REPO_ROOT/init.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# init.sh refuses to scaffold inside the framework repo. Run from /tmp.
cd /tmp

# Convenience wrapper. Required minimums for a personal-light non-interactive run.
run_init() {
  local proj="$1"; shift
  bash "$INIT" --non-interactive --project x --project-dir "$proj" --no-remote-creation \
    --platform web --language javascript "$@" >/dev/null 2>&1
}

# T1: personal + default → enforcement_level=strict.
echo "T1: personal default = strict"
TMP=$(mktemp -d); PROJ="$TMP/p"
if run_init "$PROJ" --track light --deployment personal; then
  level=$(jq -r '.enforcement_level' "$PROJ/.claude/manifest.json")
  if [ "$level" = "strict" ]; then pass "T1"; else fail_ "T1" "got $level"; fi
else
  fail_ "T1" "init failed"
fi
rm -rf "$TMP"

# T2: organizational + sponsored_poc + --enforcement-level light → ignored, manifest is strict.
echo "T2: org+sponsored_poc forces strict (flag ignored)"
TMP=$(mktemp -d); PROJ="$TMP/p"
if run_init "$PROJ" --track standard --deployment organizational --gov-mode sponsored_poc \
              --enforcement-level light --confirm-pitfalls; then
  level=$(jq -r '.enforcement_level' "$PROJ/.claude/manifest.json")
  if [ "$level" = "strict" ]; then pass "T2"; else fail_ "T2" "got $level"; fi
else
  fail_ "T2" "init failed"
fi
rm -rf "$TMP"

# T3: personal + --enforcement-level light + --confirm-pitfalls → manifest is light.
echo "T3: personal + --enforcement-level light --confirm-pitfalls → light"
TMP=$(mktemp -d); PROJ="$TMP/p"
if run_init "$PROJ" --track light --deployment personal --enforcement-level light --confirm-pitfalls; then
  level=$(jq -r '.enforcement_level' "$PROJ/.claude/manifest.json")
  if [ "$level" = "light" ]; then pass "T3"; else fail_ "T3" "got $level"; fi
else
  fail_ "T3" "init failed"
fi
rm -rf "$TMP"

# T4: --enforcement-level no without --confirm-pitfalls → init exits non-zero.
echo "T4: --enforcement-level no without --confirm-pitfalls fails"
TMP=$(mktemp -d); PROJ="$TMP/p"
bash "$INIT" --non-interactive --project x --project-dir "$PROJ" --no-remote-creation \
    --platform web --language javascript --track light --deployment personal \
    --enforcement-level no >/dev/null 2>&1
rc=$?
if [ "$rc" != "0" ]; then pass "T4"; else fail_ "T4" "expected non-zero exit, rc=$rc"; fi
rm -rf "$TMP"

# T5: init writes last-checked-commit.txt to current HEAD.
echo "T5: init initializes last-checked-commit.txt"
TMP=$(mktemp -d); PROJ="$TMP/p"
if run_init "$PROJ" --track light --deployment personal; then
  if [ -f "$PROJ/.claude/last-checked-commit.txt" ] && [ -s "$PROJ/.claude/last-checked-commit.txt" ]; then
    pass "T5"
  else
    fail_ "T5" "last-checked-commit.txt missing or empty"
  fi
else
  fail_ "T5" "init failed"
fi
rm -rf "$TMP"

# T6: strict init installs filesystem-gate.
echo "T6: strict init installs framework-gate.sh + marker block"
TMP=$(mktemp -d); PROJ="$TMP/p"
if run_init "$PROJ" --track light --deployment personal; then
  if grep -q "SOIF framework gate" "$PROJ/.git/hooks/pre-commit" 2>/dev/null \
     && [ -x "$PROJ/.git/hooks/framework-gate.sh" ]; then
    pass "T6"
  else
    fail_ "T6" "filesystem gate not installed"
  fi
else
  fail_ "T6" "init failed"
fi
rm -rf "$TMP"

# T7: light init does NOT install filesystem-gate.
echo "T7: light init skips filesystem-gate install"
TMP=$(mktemp -d); PROJ="$TMP/p"
if run_init "$PROJ" --track light --deployment personal --enforcement-level light --confirm-pitfalls; then
  if ! grep -q "SOIF framework gate" "$PROJ/.git/hooks/pre-commit" 2>/dev/null; then
    pass "T7"
  else
    fail_ "T7" "filesystem gate installed in light mode"
  fi
else
  fail_ "T7" "init failed"
fi
rm -rf "$TMP"

# T8: init appends an enforcement_level_set audit row.
echo "T8: init writes enforcement_level_set audit row"
TMP=$(mktemp -d); PROJ="$TMP/p"
if run_init "$PROJ" --track light --deployment personal; then
  rows=$(jq '[.[] | select(.type=="enforcement_level_set")] | length' "$PROJ/.claude/bypass-audit.json" 2>/dev/null || echo 0)
  if [ "$rows" -ge "1" ]; then pass "T8"; else fail_ "T8" "rows=$rows"; fi
else
  fail_ "T8" "init failed"
fi
rm -rf "$TMP"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
