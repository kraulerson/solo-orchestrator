#!/usr/bin/env bash
# tests/test-upgrade-bl030-backfill.sh — verify upgrade-project.sh
# backfills the BL-030 manifest fields (deployment, poc_mode,
# enforcement_level) on pre-BL-030 projects. Without the backfill,
# assert_choosable's jq default of 'personal' silently lets an
# operator relax enforcement_level=no on what should be forced-strict
# (the safety regression survey #1 called out for PR A).
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

# Build a fresh BL-030-era project, then mutate it to LOOK like a
# pre-BL-030 project: strip enforcement_level / deployment / poc_mode
# from manifest, remove last-checked-commit.txt, uninstall the
# filesystem gate, remove the BL-030 audit-log row. This mimics what
# an operator who initialized before PR #48 would see.
setup_pre_bl030_personal() {
  TMP=$(mktemp -d); PROJ="$TMP/p"
  bash "$INIT" --non-interactive --project x --project-dir "$PROJ" --no-remote-creation \
    --platform web --language javascript --track light --deployment personal \
    >/dev/null 2>&1
  # Strip the BL-030 fields from manifest.
  tmp=$(mktemp)
  jq 'del(.enforcement_level, .deployment, .poc_mode)' "$PROJ/.claude/manifest.json" > "$tmp" \
    && mv "$tmp" "$PROJ/.claude/manifest.json"
  # Strip the BL-030 init artifacts.
  rm -f "$PROJ/.claude/last-checked-commit.txt"
  rm -f "$PROJ/.git/hooks/framework-gate.sh"
  # Remove the marker block from pre-commit.
  bash "$PROJ/scripts/install-filesystem-gates.sh" --uninstall "$PROJ" >/dev/null 2>&1
  # Strip the enforcement_level_set rows so we can assert a NEW one is added.
  tmp=$(mktemp)
  jq '[.[] | select(.type != "enforcement_level_set")]' "$PROJ/.claude/bypass-audit.json" > "$tmp" \
    && mv "$tmp" "$PROJ/.claude/bypass-audit.json"
  # Add a phase-state.json deployment field so the backfill can read it.
  # (phase-state already has these per S2 cluster 4; defensive set here.)
  tmp=$(mktemp)
  jq '. + {deployment: "personal", poc_mode: null}' "$PROJ/.claude/phase-state.json" > "$tmp" \
    && mv "$tmp" "$PROJ/.claude/phase-state.json"
  UPGRADE="$PROJ/scripts/upgrade-project.sh"
}
setup_pre_bl030_organizational_production() {
  TMP=$(mktemp -d); PROJ="$TMP/p"
  bash "$INIT" --non-interactive --project x --project-dir "$PROJ" --no-remote-creation \
    --platform web --language javascript --track standard --deployment organizational --gov-mode production \
    >/dev/null 2>&1
  tmp=$(mktemp)
  jq 'del(.enforcement_level, .deployment, .poc_mode)' "$PROJ/.claude/manifest.json" > "$tmp" \
    && mv "$tmp" "$PROJ/.claude/manifest.json"
  rm -f "$PROJ/.claude/last-checked-commit.txt"
  rm -f "$PROJ/.git/hooks/framework-gate.sh"
  bash "$PROJ/scripts/install-filesystem-gates.sh" --uninstall "$PROJ" >/dev/null 2>&1
  tmp=$(mktemp)
  jq '[.[] | select(.type != "enforcement_level_set")]' "$PROJ/.claude/bypass-audit.json" > "$tmp" \
    && mv "$tmp" "$PROJ/.claude/bypass-audit.json"
  UPGRADE="$PROJ/scripts/upgrade-project.sh"
}
teardown() { rm -rf "$TMP"; }

# T1: pre-BL-030 personal project: upgrade backfills manifest fields.
echo "T1: pre-BL-030 personal project → enforcement_level=strict, deployment=personal"
setup_pre_bl030_personal
( cd "$PROJ" && bash "$UPGRADE" --backfill-only >/dev/null 2>&1 ) || true
level=$(jq -r '.enforcement_level // empty' "$PROJ/.claude/manifest.json")
dep=$(jq -r '.deployment // empty' "$PROJ/.claude/manifest.json")
if [ "$level" = "strict" ] && [ "$dep" = "personal" ]; then
  pass "T1: manifest now has deployment=personal enforcement_level=strict"
else
  fail_ "T1" "got enforcement_level='$level' deployment='$dep'"
fi
teardown

# T2: idempotent — running upgrade twice doesn't re-overwrite.
echo "T2: upgrade is idempotent on already-backfilled projects"
setup_pre_bl030_personal
( cd "$PROJ" && bash "$UPGRADE" --backfill-only >/dev/null 2>&1 ) || true
# Capture timestamp of latest enforcement_level_set row.
ts1=$(jq -r '[.[] | select(.type=="enforcement_level_set")] | last | .timestamp' "$PROJ/.claude/bypass-audit.json")
sleep 1
( cd "$PROJ" && bash "$UPGRADE" --backfill-only >/dev/null 2>&1 ) || true
ts2=$(jq -r '[.[] | select(.type=="enforcement_level_set")] | last | .timestamp' "$PROJ/.claude/bypass-audit.json")
# Second run should NOT add a duplicate backfill row.
if [ "$ts1" = "$ts2" ]; then pass "T2: second upgrade did not re-backfill"; else fail_ "T2" "ts1=$ts1 ts2=$ts2"; fi
teardown

# T3: pre-BL-030 organizational/production: upgrade backfills with
# deployment=organizational, NOT personal. This is the load-bearing
# regression survey #1 called out.
echo "T3: pre-BL-030 organizational project → deployment=organizational (no silent personal default)"
setup_pre_bl030_organizational_production
( cd "$PROJ" && bash "$UPGRADE" --backfill-only >/dev/null 2>&1 ) || true
dep=$(jq -r '.deployment // empty' "$PROJ/.claude/manifest.json")
level=$(jq -r '.enforcement_level // empty' "$PROJ/.claude/manifest.json")
if [ "$dep" = "organizational" ] && [ "$level" = "strict" ]; then
  pass "T3: org project backfilled correctly (no silent personal-default)"
else
  fail_ "T3" "deployment='$dep' enforcement_level='$level' (expected organizational + strict)"
fi
teardown

# T4: post-upgrade reconfigure-project --enforcement-level no on org/
# production project is REJECTED (validate_transition reads correct
# deployment from backfilled manifest).
echo "T4: post-upgrade reconfigure to 'no' on org/production is rejected"
setup_pre_bl030_organizational_production
( cd "$PROJ" && bash "$UPGRADE" --backfill-only >/dev/null 2>&1 ) || true
RECONFIG="$PROJ/scripts/reconfigure-project.sh"
( cd "$PROJ" && bash "$RECONFIG" --enforcement-level no --confirm-pitfalls >/dev/null 2>&1 )
if [ $? -ne 0 ]; then
  pass "T4: validate_transition correctly rejected downgrade on org/production"
else
  fail_ "T4" "BUG: org/production project was allowed to downgrade to no"
fi
teardown

# T5: post-upgrade, filesystem gate IS installed (strict default).
echo "T5: post-upgrade, .git/hooks/framework-gate.sh + marker block installed"
setup_pre_bl030_personal
( cd "$PROJ" && bash "$UPGRADE" --backfill-only >/dev/null 2>&1 ) || true
if [ -x "$PROJ/.git/hooks/framework-gate.sh" ] \
   && grep -q "SOIF framework gate" "$PROJ/.git/hooks/pre-commit" 2>/dev/null; then
  pass "T5: filesystem gate installed by upgrade backfill"
else
  fail_ "T5" "gate not installed"
fi
teardown

# T6: post-upgrade, enforcement_level_set row added with
# source='upgrade-backfill' to distinguish from init/reconfigure rows.
echo "T6: backfill adds an enforcement_level_set row sourced 'upgrade-backfill'"
setup_pre_bl030_personal
( cd "$PROJ" && bash "$UPGRADE" --backfill-only >/dev/null 2>&1 ) || true
sources=$(jq -r '[.[] | select(.type=="enforcement_level_set") | .details.source] | unique | join(",")' "$PROJ/.claude/bypass-audit.json")
if echo "$sources" | grep -q "upgrade-backfill"; then
  pass "T6: audit row source='upgrade-backfill' present"
else
  fail_ "T6" "sources='$sources' (expected one to be 'upgrade-backfill')"
fi
teardown

# T7: post-upgrade, last-checked-commit.txt is initialized so the
# SessionStart detector has a baseline.
echo "T7: backfill initializes last-checked-commit.txt"
setup_pre_bl030_personal
( cd "$PROJ" && bash "$UPGRADE" --backfill-only >/dev/null 2>&1 ) || true
if [ -s "$PROJ/.claude/last-checked-commit.txt" ]; then
  pass "T7: last-checked-commit.txt initialized"
else
  fail_ "T7" "last-checked-commit.txt missing or empty"
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
