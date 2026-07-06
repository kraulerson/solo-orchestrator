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
    --platform web --language typescript --track light --deployment personal \
    >/dev/null 2>&1
  RECONFIG="$PROJ/scripts/reconfigure-project.sh"
}
setup_org_production() {
  TMP=$(mktemp -d); PROJ="$TMP/p"
  bash "$INIT" --non-interactive --project x --project-dir "$PROJ" --no-remote-creation \
    --platform web --language typescript --track standard --deployment organizational --gov-mode production \
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
  --platform web --language typescript --track light --deployment personal \
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
# Post-fix (atomic finalize): the reset path commits the audit-row write, so
# baseline tracks the new chore-finalize HEAD, not the pre-call HEAD.
echo "T7: --reset-detection-baseline updates last-checked-commit.txt"
setup_personal
( cd "$PROJ" && echo z > z && git add z && git commit -qm z )
if ( cd "$PROJ" && bash "$RECONFIG" --reset-detection-baseline >/dev/null 2>&1 ); then
  expected=$(cd "$PROJ" && git rev-parse HEAD)
  actual=$(cat "$PROJ/.claude/last-checked-commit.txt")
  if [ "$actual" = "$expected" ]; then pass "T7"; else fail_ "T7" "$expected vs $actual"; fi
else
  fail_ "T7" "reconfigure failed"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Atomic finalize + rollback (sibling to PR #54) ==="
# ════════════════════════════════════════════════════════════════════

# T8: after a successful --enforcement-level transition, the working
# tree is clean (parity with the PR #54 init.sh invariant).
# Pre-fix the reconfigure left manifest.json + bypass-audit.json
# modifications uncommitted.
echo "T8: --enforcement-level → working tree clean"
setup_personal
if ( cd "$PROJ" && bash "$RECONFIG" --enforcement-level light --confirm-pitfalls >/dev/null 2>&1 ); then
  dirty=$( cd "$PROJ" && git status --porcelain 2>/dev/null )
  if [ -z "$dirty" ]; then
    pass "T8: working tree clean post-reconfigure"
  else
    fail_ "T8" "dirty:\n$dirty"
  fi
else
  fail_ "T8" "reconfigure failed"
fi
teardown

# T9: the commit emitted by the reconfigure has a chore subject naming
# the transition. Lets a reader (or W7 successor) reconstruct what the
# operator did from `git log --oneline`.
echo "T9: --enforcement-level emits 'chore: enforcement-level ... reconfigure' commit"
setup_personal
if ( cd "$PROJ" && bash "$RECONFIG" --enforcement-level light --confirm-pitfalls >/dev/null 2>&1 ); then
  subject=$( cd "$PROJ" && git log -1 --format='%s' )
  if echo "$subject" | grep -qE '^chore: enforcement-level (strict|light|no) -> (strict|light|no) \(reconfigure\)$'; then
    pass "T9: commit subject: '$subject'"
  else
    fail_ "T9" "unexpected commit subject: '$subject'"
  fi
else
  fail_ "T9" "reconfigure failed"
fi
teardown

# T10: install-filesystem-gates.sh FAILURE on light→strict.
# Pre-fix: the installer was invoked with `|| true`, so the failure was
# swallowed, the manifest had already been written claiming strict, the
# audit row claimed strict, but no SOIF marker was installed in
# .git/hooks/pre-commit — silent-bypass security defect.
# Post-fix: failure propagates, manifest + audit are rolled back, exit
# non-zero. The pre-call manifest level + audit row count are preserved.
echo "T10: light→strict installer FAILURE rolls back manifest + audit"
TMP=$(mktemp -d); PROJ="$TMP/p"
bash "$INIT" --non-interactive --project x --project-dir "$PROJ" --no-remote-creation \
  --platform web --language typescript --track light --deployment personal \
  --enforcement-level light --confirm-pitfalls >/dev/null 2>&1
RECONFIG="$PROJ/scripts/reconfigure-project.sh"
# Replace the project-local installer with a stub that exits 1.
printf '#!/usr/bin/env bash\nexit 1\n' > "$PROJ/scripts/install-filesystem-gates.sh"
chmod +x "$PROJ/scripts/install-filesystem-gates.sh"
before_level=$(jq -r '.enforcement_level' "$PROJ/.claude/manifest.json")
before_rows=$(jq '[.[] | select(.type=="enforcement_level_set")] | length' "$PROJ/.claude/bypass-audit.json")
( cd "$PROJ" && bash "$RECONFIG" --enforcement-level strict >/dev/null 2>&1 )
rc=$?
after_level=$(jq -r '.enforcement_level' "$PROJ/.claude/manifest.json")
after_rows=$(jq '[.[] | select(.type=="enforcement_level_set")] | length' "$PROJ/.claude/bypass-audit.json")
marker_present=no
if grep -q "SOIF framework gate" "$PROJ/.git/hooks/pre-commit" 2>/dev/null; then marker_present=yes; fi
if [ "$rc" -ne 0 ] && [ "$after_level" = "$before_level" ] && [ "$after_rows" = "$before_rows" ] && [ "$marker_present" = "no" ]; then
  pass "T10: rollback complete (rc=$rc level=$after_level rows=$after_rows marker=$marker_present)"
else
  fail_ "T10" "rc=$rc level=${before_level}->${after_level} rows=${before_rows}->${after_rows} marker=$marker_present"
fi
teardown

# T11: install-filesystem-gates.sh FAILURE on strict→light.
# Mirror of T10. Pre-fix: manifest got rewritten to "light" while the
# SOIF marker stayed in place — surprise blocks on commits the user
# thought they had freed. Post-fix: rollback, manifest stays strict,
# marker stays present, audit row count unchanged.
echo "T11: strict→light installer FAILURE rolls back"
setup_personal
printf '#!/usr/bin/env bash\nexit 1\n' > "$PROJ/scripts/install-filesystem-gates.sh"
chmod +x "$PROJ/scripts/install-filesystem-gates.sh"
before_level=$(jq -r '.enforcement_level' "$PROJ/.claude/manifest.json")
before_rows=$(jq '[.[] | select(.type=="enforcement_level_set")] | length' "$PROJ/.claude/bypass-audit.json")
( cd "$PROJ" && bash "$RECONFIG" --enforcement-level light --confirm-pitfalls >/dev/null 2>&1 )
rc=$?
after_level=$(jq -r '.enforcement_level' "$PROJ/.claude/manifest.json")
after_rows=$(jq '[.[] | select(.type=="enforcement_level_set")] | length' "$PROJ/.claude/bypass-audit.json")
marker_present=no
if grep -q "SOIF framework gate" "$PROJ/.git/hooks/pre-commit" 2>/dev/null; then marker_present=yes; fi
if [ "$rc" -ne 0 ] && [ "$after_level" = "strict" ] && [ "$after_rows" = "$before_rows" ] && [ "$marker_present" = "yes" ]; then
  pass "T11: rollback complete (rc=$rc level=$after_level rows=$after_rows marker=$marker_present)"
else
  fail_ "T11" "rc=$rc level=${before_level}->${after_level} rows=${before_rows}->${after_rows} marker=$marker_present"
fi
teardown

# T12: --reset-detection-baseline also leaves the tree clean (parity
# with --enforcement-level). The audit-row write that the reset path
# performs now lands in a commit, not as drift.
echo "T12: --reset-detection-baseline → working tree clean"
setup_personal
( cd "$PROJ" && echo zz > zz && git add zz && git commit -qm zz )
if ( cd "$PROJ" && bash "$RECONFIG" --reset-detection-baseline >/dev/null 2>&1 ); then
  dirty=$( cd "$PROJ" && git status --porcelain 2>/dev/null )
  if [ -z "$dirty" ]; then
    pass "T12: working tree clean post-baseline-reset"
  else
    fail_ "T12" "dirty:\n$dirty"
  fi
else
  fail_ "T12" "reconfigure failed"
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
