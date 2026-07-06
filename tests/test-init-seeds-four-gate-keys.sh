#!/usr/bin/env bash
# tests/test-init-seeds-four-gate-keys.sh
#
# BL-071 (rolled-in minor): init.sh's phase-state.json seed heredoc must
# emit ALL FOUR gate keys. Pre-fix it seeded only three
# (phase_0_to_1, phase_1_to_2, phase_3_to_4) — the phase_2_to_3 key was
# missing, so a fresh `init.sh` project lacked the 2→3 gate slot until an
# operator happened to run verify-install.sh (whose fixup path at
# verify-install.sh:844-847 already seeds all four). This test bootstraps
# a real init.sh project and asserts the generated
# .claude/phase-state.json::gates object carries all four keys, each null.
#
# bash-3.2 safe.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SH="$REPO_ROOT/init.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] jq not available — needed to assert the gates object shape."
  exit 0
fi

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PROJ="$TMP/proj"

echo "== tests/test-init-seeds-four-gate-keys.sh =="
echo "Bootstrapping init.sh project (one-time setup; ~30-60s)..."

( cd "$TMP" && "$INIT_SH" --non-interactive \
    --project test-seeds-four \
    --platform web \
    --deployment personal \
    --language typescript \
    --git-host github \
    --visibility private \
    --project-dir "$PROJ" \
    --no-remote-creation \
    >"$TMP/init.out" 2>"$TMP/init.err" ) || {
  echo "  [FATAL] init.sh bootstrap failed; rc=$?"
  tail -20 "$TMP/init.err" | sed 's/^/    /'
  exit 1
}

STATE="$PROJ/.claude/phase-state.json"
if [ ! -f "$STATE" ]; then
  echo "  [FATAL] phase-state.json not generated at $STATE"
  exit 1
fi

echo ""
echo "=== T-init-seeds-four: all 4 gate keys present as null ==="

for key in phase_0_to_1 phase_1_to_2 phase_2_to_3 phase_3_to_4; do
  present=$(jq --arg k "$key" 'if (.gates | has($k)) then "yes" else "no" end' "$STATE" 2>/dev/null | tr -d '"')
  val=$(jq -r --arg k "$key" '.gates[$k]' "$STATE" 2>/dev/null)
  if [ "$present" = "yes" ] && [ "$val" = "null" ]; then
    pass "gates.$key present and null"
  else
    fail_ "gates.$key" "expected present+null, got present=$present value='$val'"
  fi
done

# Guard against extra/typo'd gate keys creeping in.
gate_key_count=$(jq '[.gates | keys[] | select(test("^phase_[0-9]+_to_[0-9]+$"))] | length' "$STATE" 2>/dev/null)
if [ "$gate_key_count" = "4" ]; then
  pass "exactly 4 phase_*_to_* gate keys seeded"
else
  fail_ "gate-key-count" "expected 4 phase_*_to_* keys, got $gate_key_count; gates: $(jq -c '.gates' "$STATE")"
fi

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
