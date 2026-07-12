#!/usr/bin/env bash
# tests/test-plan-birth.sh — BL-109 S3 AGGREGATOR (real init.sh + real --plan).
#
# The BL-088 precedent: fixtures hide scaffold gaps. This test scaffolds a REAL
# project with the REAL init.sh out of a scratch framework CLONE it can advance,
# then runs the REAL `upgrade-project.sh --plan` against it. It proves the things a
# hand-built fixture cannot: the I1 whole-tree fingerprint (only the run folder
# appears), real A1 candidate generation from a genuinely-drifted template, a live-
# tree placeholder/conflict-marker scan, and that day-after-plan freshness detection
# is still coherent.
#
# AGGREGATOR: registered ONLY in tests/full-project-test-suite.sh (it runs init.sh);
# NEVER in the tests.yml unit list. Hermetic: mktemp, GITHUB_BASE_REF unset,
# --no-remote-creation, zero network. bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

unset GITHUB_BASE_REF 2>/dev/null || true

PASSED=0; FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  echo "SKIP: jq + git required"; echo "Results: 0 passed, 0 failed"; exit 0
fi

TOP="$(mktemp -d)"
trap 'rm -rf "$TOP"' EXIT

# ── Build a scratch framework CLONE we can advance (drift a template + commit) ──
FW="$TOP/fw"
mkdir -p "$FW"
# Copy the WORKING tree (uncommitted branch changes included) — the dirs init.sh
# reads. Then make it a fresh git repo so we control its history/pin.
( cd "$REPO_ROOT" && tar -cf - init.sh scripts templates docs evaluation-prompts ) | ( cd "$FW" && tar -xf - )
( cd "$FW" && git init -q && git config user.email fw@t.local && git config user.name FW \
    && git add -A && git commit -qm "scratch framework c0" ) >/dev/null 2>&1
PIN="$(git -C "$FW" rev-parse HEAD)"

# ── Scaffold a real project from the scratch framework ──
PROJ="$TOP/proj"
if ! ( cd "$TOP" && "$FW/init.sh" --non-interactive \
        --project birthplan --platform web --deployment personal \
        --gov-mode private_poc --language typescript \
        --project-dir "$PROJ" --no-remote-creation ) >"$TOP/init.out" 2>"$TOP/init.err"; then
  fail_ "scaffold" "init.sh exited non-zero; stderr tail: $(tail -6 "$TOP/init.err" | tr '\n' '|')"
  echo "Results: $PASSED passed, $FAILED failed"; exit 1
fi

# BL-110: --no-remote-creation does NOT stamp soloFrameworkCommit. Stamp the pin so
# the full (non-degraded) plan path runs — exactly what a synced project would have.
MAN="$PROJ/.claude/manifest.json"
jq --arg p "$PIN" '.soloFrameworkCommit = $p' "$MAN" > "$MAN.tmp" && mv "$MAN.tmp" "$MAN"

# ── Whole-tree fingerprint BEFORE the plan (exclude volatile/expected dirs) ──
_fp() {
  find "$1" -type f \
    -not -path '*/docs/updates/*' -not -path '*/.git/*' \
    -not -path '*/.claude/cache/*' -not -path '*/.solo-orchestrator/*' 2>/dev/null \
    | sort | while IFS= read -r f; do printf '%s  %s\n' "$(shasum -a 256 "$f" | awk '{print $1}')" "${f#"$1"}"; done
}
BEFORE="$(_fp "$PROJ")"

# ── Drift the framework past the pin + commit. Two drifts on purpose:
#   • the CLAUDE.md TEMPLATE (A1 render-base drift → A1 candidate), and
#   • a shipped SCRIPT (Class-M file drift → a diffs/ entry). The M drift is what
#     exercises _soif_plan_build_diff's `diff -u` (which returns 1 on differences)
#     under the REAL `set -euo pipefail` of upgrade-project.sh — the regression the
#     `set +e` subshell in _run_plan guards. Without that guard, the plan would
#     abort mid-run and this M diff would never be produced.
printf '\n<!-- NEW UPSTREAM LINE injected for the plan aggregator test -->\n' \
  >> "$FW/templates/generated/claude-md.tmpl"
M_DRIFT_REL=""
for cand in scripts/check-versions.sh scripts/resume.sh scripts/verify-install.sh; do
  if [ -f "$FW/$cand" ] && [ -f "$PROJ/$cand" ]; then M_DRIFT_REL="$cand"; break; fi
done
[ -n "$M_DRIFT_REL" ] && printf '\n# BL-109 plan aggregator: upstream drift marker\n' >> "$FW/$M_DRIFT_REL"
( cd "$FW" && git add -A && git commit -qm "scratch framework c1 (template + script drift)" ) >/dev/null 2>&1

# ── Run the REAL --plan from the scratch framework ──
if ! ( cd "$PROJ" && bash "$FW/scripts/upgrade-project.sh" --plan ) >"$TOP/plan.out" 2>"$TOP/plan.err"; then
  fail_ "plan-exit" "--plan exited non-zero; tail: $(tail -6 "$TOP/plan.err" | tr '\n' '|')"
fi
RUN="$(ls -d "$PROJ"/docs/updates/*/ 2>/dev/null | head -1)"; RUN="${RUN%/}"

# (1) run folder + UPDATE-PLAN.md + manifest.json exist
if [ -n "$RUN" ] && [ -f "$RUN/UPDATE-PLAN.md" ] && [ -f "$RUN/manifest.json" ]; then
  pass "run folder created with UPDATE-PLAN.md + manifest.json"
else
  fail_ "run folder" "no run folder / UPDATE-PLAN.md / manifest.json produced"
fi

# (2) I1 whole-tree fingerprint — ONLY the run folder appears; nothing else changed
AFTER="$(_fp "$PROJ")"
if [ "$BEFORE" = "$AFTER" ]; then
  pass "I1 fingerprint: the project tree is byte-identical outside docs/updates/"
else
  fail_ "I1 fingerprint" "the tree changed outside docs/updates/:"$'\n'"$(diff <(printf '%s' "$BEFORE") <(printf '%s' "$AFTER") | head)"
fi

# (3) real A1 candidate: generated, placeholder-free, picks up the upstream delta
CAND="$RUN/merged/CLAUDE.md.candidate"
if [ -f "$CAND" ]; then
  ok=1
  grep -qE '__[A-Z][A-Z_]*__' "$CAND" && { ok=0; echo "    candidate has a generator placeholder"; }
  grep -q 'birthplan' "$CAND" || { ok=0; echo "    candidate lost the recovered project name"; }
  grep -q 'NEW UPSTREAM LINE injected' "$CAND" || { ok=0; echo "    candidate did not pick up the upstream template change"; }
  grep -q '<<<<<<<' "$CAND" && echo "    (note: candidate carries conflict markers — allowed; they stay in the candidate)"
  [ "$ok" = 1 ] && pass "A1 candidate: real render, placeholder-free, applies the upstream delta, keeps user values" \
    || fail_ "A1 candidate" "see above"
else
  fail_ "A1 candidate" "no merged/CLAUDE.md.candidate generated for a genuinely drifted template"
fi

# (3b) the Class-M script drift produced a diffs/ entry — proving the full M-item
#      path (verb classification → _soif_plan_build_diff's `diff -u`, which exits 1
#      on differences → the mechanical roll-up) runs to completion under the REAL
#      upgrade-project.sh caller (`set -euo pipefail`; the plan runs in a `set +e`
#      subshell per the lib's documented no-errexit contract). A unit test alone
#      never exercises this under the real caller's shell options.
if [ -n "$M_DRIFT_REL" ]; then
  if ls "$RUN"/diffs/*fw-drift*.diff >/dev/null 2>&1 \
     && grep -rqF 'BL-109 plan aggregator: upstream drift marker' "$RUN"/diffs/ 2>/dev/null; then
    pass "Class-M script drift → diffs/ entry produced by the real --plan caller"
  else
    fail_ "M-diff under real caller" "no diffs/ entry for the drifted script $M_DRIFT_REL"
  fi
else
  pass "M-diff under real caller — SKIPPED (no shippable script to drift in this scaffold)"
fi

# (4) live-tree scan — NO git conflict markers in a live USER artifact, and NO A1
#     generator placeholder in a rendered A1 artifact. Scope is the project-root
#     markdown artifacts (the user/rendered docs) — framework machinery
#     (scripts/, templates/generated/*.tmpl) legitimately mentions "<<<<<<<" in
#     strings and carries unrendered placeholders, and is not a live artifact.
#     Conflict markers are matched at LINE START (git's real format:
#     "<<<<<<< …" / ">>>>>>> …"), which markdown prose never produces.
cm_leak=0
for f in "$PROJ"/*.md; do
  [ -f "$f" ] || continue
  if grep -qE '^(<<<<<<<|>>>>>>>) ' "$f" 2>/dev/null; then cm_leak=1; echo "    conflict marker in $(basename "$f")"; fi
done
ph_leak=0
for a in CLAUDE.md PROJECT_INTAKE.md; do
  [ -f "$PROJ/$a" ] || continue
  grep -qE '__[A-Z][A-Z_]*__' "$PROJ/$a" && { ph_leak=1; echo "    placeholder in live $a"; }
done
if [ "$cm_leak" = 0 ] && [ "$ph_leak" = 0 ]; then
  pass "live-tree scan: no conflict markers in a user artifact, no generator placeholder in a rendered A1 artifact"
else
  fail_ "live-tree scan" "conflict-marker leak=$cm_leak placeholder leak=$ph_leak"
fi

# (5) day-after-plan freshness detection still coherent (reads the same manifest;
#     the plan did not disturb it). Runs the real session detector; must exit 0.
FRC=0
( cd "$PROJ" && CDF_HOME="$TOP/no-such-cdf" bash "$PROJ/scripts/session-freshness-check.sh" ) >"$TOP/frc.out" 2>&1 || FRC=$?
if [ "$FRC" = 0 ]; then
  pass "day-after-plan freshness detection runs coherently (exit 0)"
else
  fail_ "freshness coherence" "session-freshness-check exited $FRC; tail: $(tail -4 "$TOP/frc.out" | tr '\n' '|')"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
