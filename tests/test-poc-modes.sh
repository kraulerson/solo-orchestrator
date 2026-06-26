#!/usr/bin/env bash
# tests/test-poc-modes.sh — Audit S2 cluster 2 regression tests
#
# Baseline §2.5: Private POC is always personal; Sponsored POC is always
# organizational; Production is valid for both. Pre-fix (PR #46-era),
# init.sh refused --gov-mode for personal deployments at all, making
# Private POC unreachable; upgrade-project.sh --to-private-poc forced
# TARGET_DEPLOYMENT=organizational; intake-wizard run_upgrade_to_production
# forced DEPLOYMENT=organizational.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT="$REPO_ROOT/init.sh"
UPGRADE="$REPO_ROOT/scripts/upgrade-project.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# init.sh refuses to scaffold inside the framework repo.
cd /tmp

# Portable wall-clock bound on init.sh runs.
RC=0
run_bounded() {
  local secs="$1"; shift
  ("$@") &
  local pid=$!
  local deadline=$(( $(date +%s) + secs ))
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      RC=124
      return 0
    fi
    sleep 1
  done
  wait "$pid" 2>/dev/null
  RC=$?
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Private POC reachability (init.sh non-interactive) ==="
# ════════════════════════════════════════════════════════════════════

# T1: --deployment=personal --gov-mode=private_poc is accepted (the
# fix's primary behavior — pre-fix this combination was rejected with
# "--gov-mode is not valid for --deployment=personal").
T=$(mktemp -d); P="$T/p"
run_bounded 90 bash "$INIT" --non-interactive --project x --project-dir "$P" \
  --no-remote-creation --platform web --language javascript --track light \
  --deployment personal --gov-mode private_poc > "$T/log" 2>&1 < /dev/null
rc=$RC
if [ "$rc" = "0" ] && [ -f "$P/.claude/phase-state.json" ]; then
  pm=$(jq -r '.poc_mode // empty' "$P/.claude/phase-state.json")
  dep=$(jq -r '.deployment // empty' "$P/.claude/phase-state.json")
  if [ "$pm" = "private_poc" ] && [ "$dep" = "personal" ]; then
    pass "T1: personal + private_poc accepted; phase-state shows personal/private_poc"
  else
    fail_ "T1" "phase-state has deployment='$dep' poc_mode='$pm' (expected personal/private_poc)"
  fi
else
  fail_ "T1" "init.sh rc=$rc; log tail: $(tail -3 "$T/log" 2>/dev/null | tr '\n' '|')"
fi
rm -rf "$T"

# T2: --deployment=personal --gov-mode=sponsored_poc rejected with the
# tier-semantics message.
T=$(mktemp -d); P="$T/p"
run_bounded 30 bash "$INIT" --non-interactive --project x --project-dir "$P" \
  --no-remote-creation --platform web --language javascript --track standard \
  --deployment personal --gov-mode sponsored_poc > "$T/log" 2>&1 < /dev/null
rc=$RC
if [ "$rc" != "0" ] && grep -qE "sponsored_poc is not valid for --deployment=personal" "$T/log"; then
  pass "T2: personal + sponsored_poc rejected with tier-semantics message"
else
  fail_ "T2" "rc=$rc; expected non-zero + clear message"
fi
rm -rf "$T"

# T3: --deployment=organizational --gov-mode=private_poc rejected.
T=$(mktemp -d); P="$T/p"
run_bounded 30 bash "$INIT" --non-interactive --project x --project-dir "$P" \
  --no-remote-creation --platform web --language javascript --track standard \
  --deployment organizational --gov-mode private_poc > "$T/log" 2>&1 < /dev/null
rc=$RC
if [ "$rc" != "0" ] && grep -qE "private_poc is not valid for --deployment=organizational" "$T/log"; then
  pass "T3: organizational + private_poc rejected with tier-semantics message"
else
  fail_ "T3" "rc=$rc; expected non-zero + clear message"
fi
rm -rf "$T"

# T4: --deployment=organizational --gov-mode=sponsored_poc still works
# (regression check for the org+sponsored_poc happy path).
T=$(mktemp -d); P="$T/p"
run_bounded 90 bash "$INIT" --non-interactive --project x --project-dir "$P" \
  --no-remote-creation --platform web --language javascript --track standard \
  --deployment organizational --gov-mode sponsored_poc > "$T/log" 2>&1 < /dev/null
rc=$RC
if [ "$rc" = "0" ] && [ -f "$P/.claude/phase-state.json" ]; then
  pm=$(jq -r '.poc_mode // empty' "$P/.claude/phase-state.json")
  dep=$(jq -r '.deployment // empty' "$P/.claude/phase-state.json")
  if [ "$pm" = "sponsored_poc" ] && [ "$dep" = "organizational" ]; then
    pass "T4: organizational + sponsored_poc still accepted; phase-state matches"
  else
    fail_ "T4" "phase-state has deployment='$dep' poc_mode='$pm'"
  fi
else
  fail_ "T4" "init.sh rc=$rc"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== upgrade-project.sh --to-private-poc target deployment ==="
# ════════════════════════════════════════════════════════════════════

# T5: --to-private-poc on a personal/production project sets
# TARGET_DEPLOYMENT=personal (pre-fix it forced organizational, producing
# the impossible organizational/private_poc shape).
T=$(mktemp -d); P="$T/p"
mkdir -p "$P/.claude"
cat > "$P/.claude/phase-state.json" <<'JSON'
{
  "project": "test",
  "framework_version": "1.0",
  "current_phase": 0,
  "track": "standard",
  "deployment": "personal",
  "poc_mode": null,
  "compliance_ready": false,
  "gates": {"phase_0_to_1": null, "phase_1_to_2": null, "phase_3_to_4": null}
}
JSON
( cd "$P" && git init -q && git config user.email t@t.l && git config user.name t \
    && git add -A && git commit -q -m "init" ) >/dev/null 2>&1
# Use --dry-run to inspect TARGET_DEPLOYMENT resolution without actually
# committing the upgrade (upgrade-project.sh's --dry-run prints the plan
# and exits before mutating files).
( cd "$P" && run_bounded 30 bash "$UPGRADE" --to-private-poc --dry-run ) > "$T/log" 2>&1
rc=$RC
if grep -qE "(TARGET_DEPLOYMENT.*personal|target.*deployment.*personal|will (stay|remain) personal)" "$T/log"; then
  pass "T5: --to-private-poc from personal stays personal (no org coercion)"
elif grep -qE "(TARGET_DEPLOYMENT.*organizational|target.*deployment.*organizational)" "$T/log"; then
  fail_ "T5" "BUG: TARGET_DEPLOYMENT forced to organizational. Log tail: $(tail -10 "$T/log" 2>/dev/null | tr '\n' '|')"
else
  # If --dry-run output doesn't print TARGET_DEPLOYMENT explicitly, fall
  # back to running without --dry-run and check the resulting phase-state.
  run_bounded 30 bash -c "cd '$P' && bash '$UPGRADE' --to-private-poc" > "$T/log2" 2>&1
  dep=$(jq -r '.deployment // empty' "$P/.claude/phase-state.json" 2>/dev/null)
  if [ "$dep" = "personal" ]; then
    pass "T5: --to-private-poc result phase-state.deployment=personal (no org coercion)"
  elif [ "$dep" = "organizational" ]; then
    fail_ "T5" "BUG: phase-state.deployment was forced to 'organizational' (legacy bug)"
  else
    fail_ "T5" "phase-state.deployment is '$dep' (expected personal). Log tail: $(tail -5 "$T/log2" 2>/dev/null | tr '\n' '|')"
  fi
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
