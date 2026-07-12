#!/usr/bin/env bash
# tests/test-freshness-birth.sh — BL-109 S2 AGGREGATOR fidelity test.
#
# The BL-088 precedent (mirrors tests/test-currency-birth-stamp.sh): fixtures
# hide scaffold gaps, so this test runs the REAL init.sh into a hermetic scratch
# project and proves the session-start freshness detector (BL-109 S2, Layer 1)
# behaves correctly against a genuine birth manifest + genuine injected hook:
#
#   • DAY-ZERO SILENCE — on a freshly scaffolded project the detector prints
#     ZERO bytes (stdout AND stderr) and exits 0 (Appendix P rung 1: a noisy day
#     zero is an instant live-test abort).
#   • The freshness hook is INJECTED into SessionStart and actually RUNS (exit 0).
#   • The whole S2 lib chain is present downstream: session-freshness-check.sh,
#     lib/freshness-detect.sh, lib/currency-manifest.sh (S1 obligation 5).
#   • SEEDED POST-BIRTH DRIFT is detected in the right tier: editing a vendored
#     script → informational local-edit; deleting a line from an installed hook's
#     managed block → enforcement hook drift.
#   • WHOLE-TREE FINGERPRINT — running the detector changes NOTHING outside
#     `.claude/cache/` (invariant I7), and leaves the git tree clean.
#
# It is an AGGREGATOR: registered ONLY in tests/full-project-test-suite.sh
# (SUITE_SKIP_AGGREGATORS-gated — it executes init.sh), NEVER in the tests.yml
# unit list.
#
# Hermetic: mktemp, GITHUB_BASE_REF unset, init.sh run with --no-remote-creation
# (the blessed no-live-remote path). CDF_HOME pinned to a nonexistent path for
# the silence + seeded-drift assertions so the CDF-staleness axis (a real,
# separate signal) cannot make day zero flaky. bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT="$REPO_ROOT/init.sh"

unset GITHUB_BASE_REF 2>/dev/null || true

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

if ! command -v jq >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  echo "SKIP: jq/git required for the init.sh-driven freshness birth test"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

NOCDF="$TOPTMP/no-cdf"   # deliberately nonexistent → CDF check skips silently

# ── Scaffold a real project via init.sh (hermetic) ───────────────────────────
echo "=== Scaffolding typescript project via real init.sh (hermetic) ==="
PROJ="$TOPTMP/proj"
if ! ( cd "$TOPTMP" && "$INIT" --non-interactive \
        --project frbl109 \
        --platform web \
        --deployment personal \
        --gov-mode private_poc \
        --language typescript \
        --project-dir "$PROJ" \
        --no-remote-creation ) >"$TOPTMP/init.out" 2>"$TOPTMP/init.err"; then
  fail_ "scaffold-init" "init.sh exited non-zero; stderr tail: $(tail -6 "$TOPTMP/init.err" | tr '\n' '|')"
  echo "Results: $PASSED passed, $FAILED failed"
  exit 1
fi

SUT="$PROJ/scripts/session-freshness-check.sh"

# ── The S2 lib chain ships downstream (S1 obligation 5 + S2) ─────────────────
missing=""
for f in scripts/session-freshness-check.sh scripts/lib/freshness-detect.sh scripts/lib/currency-manifest.sh; do
  [ -f "$PROJ/$f" ] || missing="$missing $f"
done
if [ -z "$missing" ]; then
  pass "S2 lib chain shipped downstream (session-freshness-check.sh + freshness-detect.sh + currency-manifest.sh)"
else
  fail_ "ship-set" "missing downstream:$missing"
fi

# ── The freshness hook is injected into SessionStart ─────────────────────────
if [ -f "$PROJ/.claude/settings.json" ] \
   && jq -e '.hooks.SessionStart[]?.hooks[]? | select(.command | contains("session-freshness-check.sh"))' \
        "$PROJ/.claude/settings.json" >/dev/null 2>&1; then
  pass "session-freshness-check.sh injected into SessionStart"
else
  fail_ "hook-injected" "no SessionStart entry for session-freshness-check.sh (settings.json present? $( [ -f "$PROJ/.claude/settings.json" ] && echo yes || echo no ))"
fi

# ── DAY-ZERO SILENCE — zero bytes stdout+stderr, exit 0 ──────────────────────
echo "=== day-zero silence ==="
d0_out="$(CDF_HOME="$NOCDF" CLAUDE_PROJECT_DIR="$PROJ" bash "$SUT" 2>"$TOPTMP/d0.err")"; d0_rc=$?
d0_err="$(cat "$TOPTMP/d0.err")"
if [ "$d0_rc" -eq 0 ] && [ -z "$d0_out" ] && [ -z "$d0_err" ]; then
  pass "day-zero: byte-empty stdout+stderr, exit 0 (the hook actually ran)"
else
  fail_ "day-zero-silence" "rc=$d0_rc stdout=[$d0_out] stderr=[$d0_err]"
fi

# ── WHOLE-TREE FINGERPRINT — only .claude/cache/ changed ─────────────────────
# Fingerprint every file EXCEPT .git/** and .claude/cache/**; running detection
# again must not perturb it (I7: detection writes nothing but the cache).
echo "=== whole-tree fingerprint (only .claude/cache/ may change) ==="
fingerprint() {
  ( cd "$PROJ" && find . -type f \
      -not -path './.git/*' \
      -not -path './.claude/cache/*' \
      | LC_ALL=C sort \
      | while IFS= read -r p; do shasum -a 256 "$p"; done \
      | shasum -a 256 | awk '{print $1}' )
}
fp_before="$(fingerprint)"
CDF_HOME="$NOCDF" CLAUDE_PROJECT_DIR="$PROJ" bash "$SUT" >/dev/null 2>&1
fp_after="$(fingerprint)"
git_dirty="$(git -C "$PROJ" status --porcelain 2>/dev/null)"
cache_present="no"; [ -f "$PROJ/.claude/cache/freshness.json" ] && cache_present="yes"
if [ "$fp_before" = "$fp_after" ] && [ -z "$git_dirty" ] && [ "$cache_present" = "yes" ]; then
  pass "detection changed nothing outside .claude/cache/ and the git tree stays clean (I7)"
else
  fail_ "fingerprint" "changed=$( [ "$fp_before" = "$fp_after" ] && echo no || echo YES) git_dirty=[$git_dirty] cache=$cache_present"
fi

# ── SEEDED DRIFT 1: edit a vendored script → informational local-edit ────────
echo "=== seeded drift: edit a vendored script → informational ==="
printf '\n# locally hand-edited line (seeded drift)\n' >> "$PROJ/scripts/validate.sh"
se_out="$(CDF_HOME="$NOCDF" CLAUDE_PROJECT_DIR="$PROJ" bash "$SUT" 2>/dev/null)"
se_mach="$(printf '%s' "$se_out" | sed -n '/```soif-freshness/,/```/p' | sed '1d;$d')"
se_tier="$(printf '%s' "$se_mach" | jq -r '.items[] | select(.id=="local-edit:scripts/validate.sh") | .tier' 2>/dev/null)"
if [ "$se_tier" = "informational" ] && printf '%s' "$se_out" | grep -qi 'archive-and-replace'; then
  pass "editing a vendored script surfaces as informational local-edit drift"
else
  fail_ "seeded-local-edit" "tier=[$se_tier] out=[$se_out]"
fi
# restore the vendored script so the next seed is isolated
git -C "$PROJ" checkout -- scripts/validate.sh >/dev/null 2>&1 || \
  printf 'true\n' > "$PROJ/scripts/validate.sh"

# ── SEEDED DRIFT 2: delete a hook managed-block line → enforcement hook drift ─
echo "=== seeded drift: delete an installed hook line → enforcement ==="
CM="$PROJ/.git/hooks/commit-msg"
if [ -f "$CM" ]; then
  # Delete the load-bearing gate invocation line from the managed block.
  grep -v 'pre-commit-gate.sh --terminal-mode --tdd-only' "$CM" > "$CM.tmp" && mv "$CM.tmp" "$CM"
  sh_out="$(CDF_HOME="$NOCDF" CLAUDE_PROJECT_DIR="$PROJ" bash "$SUT" 2>/dev/null)"
  sh_mach="$(printf '%s' "$sh_out" | sed -n '/```soif-freshness/,/```/p' | sed '1d;$d')"
  sh_tier="$(printf '%s' "$sh_mach" | jq -r '.items[] | select(.id=="hook-drift:commit-msg") | .tier' 2>/dev/null)"
  if [ "$sh_tier" = "enforcement" ] && printf '%s' "$sh_out" | grep -q 'Recommended now (enforcement):'; then
    pass "deleting a hook managed-block line surfaces as enforcement hook drift"
  else
    fail_ "seeded-hook-drift" "tier=[$sh_tier] out=[$sh_out]"
  fi
else
  fail_ "seeded-hook-drift" "no installed commit-msg hook to perturb (unexpected for typescript)"
fi

# ── Tally ────────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
