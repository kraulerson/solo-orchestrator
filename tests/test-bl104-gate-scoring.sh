#!/usr/bin/env bash
# tests/test-bl104-gate-scoring.sh
#
# BL-104 regression: two SCORING INVERSIONS in scripts/check-phase-gate.sh's
# Phase 3→4 block — each one a case where doing LESS work scored BETTER than
# doing some.
#
#   Inversion 1 — the zero-step silent pass (P3-007).
#     The Phase-3 process-checklist cross-check read:
#         if   [ p3 -ge 9 ]; then OK
#         elif [ p3 -gt  0 ]; then WARN + issues++      # blocks
#         fi                                            # <-- no else
#     8/9 steps BLOCKED the gate. 0/9 steps hit NEITHER arm and PASSED in
#     silence. A project that never ran Phase-3 validation at all outscored one
#     that ran eight of nine steps. Fixed by the missing `else` arm, which WARNs
#     and — deliberately — INCREMENTS `issues` (blocking), because a gate where
#     8/9 blocks and 0/9 passes has no credibility. Marker: # BL-104-P3-ZERO.
#
#   Inversion 2 — the empty-manifest bypass.
#     The no-manifest arm WARNs and increments `issues` (blocks) even on the
#     non-enforced / light / grandfathered track. The manifest-present-but-
#     incomplete arm WARNs and does NOT increment (passes). So on a
#     grandfathered project:
#         (no manifest)                        → BLOCKED
#         echo '{"reviews":[]}' > manifest.json → PASSES
#     Creating an empty file — recording zero reviews — turned a blocking gate
#     into a passing one. Fixed by scoring on CONTENT, not file existence: a
#     manifest that records ZERO completed reviews is materially identical to no
#     manifest and blocks the same way. A PARTIAL manifest (>= 1 completed
#     review) keeps the DOCUMENTED light/grandfathered WARN-only contract
#     (builders-guide.md § Phase 3→4: "track=light / personal: WARN only (POC
#     preserved)"), and the enforced standard/full FAIL is untouched.
#     Marker: # BL-104-MANIFEST-ARM.
#
#   THE TRAP BOTH BUGS LIVE IN: in check-phase-gate.sh the [WARN]/[FAIL] text is
#   COSMETIC. The exit predicate is `if [ $issues -eq 0 ]`. Any "WARN" that runs
#   `issues=$((issues + 1))` BLOCKS; a WARN that omits it does not. Two arms that
#   both print [WARN] can have opposite gate outcomes — which is exactly how
#   these inversions hid.
#
# TESTS
#   T-p3-zero-steps-warns          0/9 steps → WARN emitted AND gate blocks
#                                  (RED on main: silently passes).
#   T-p3-partial-steps-blocks      control: 5/9 → blocks (unchanged behaviour).
#   T-p3-nine-steps-passes         control: 9/9 → passes (the fixture is
#                                  otherwise golden-clean; proves the 0-step
#                                  block is attributable to the step count).
#   T-empty-manifest-not-a-bypass  grandfathered/light + {"reviews":[]} → still
#                                  blocks (RED on main: passes). Paired with
#                                  T-no-manifest-blocks, which shows the arm it
#                                  must be consistent with.
#   T-no-manifest-blocks           control: grandfathered/light + NO manifest →
#                                  blocks (the arm the empty manifest must not
#                                  score better than).
#   T-empty-manifest-enforced-fails  enforced standard + {"reviews":[]} → still
#                                  the review-gate FAIL (proves the fix did not
#                                  weaken the enforced track).
#   T-light-track-warn-only-preserved  light/grandfathered + PARTIAL manifest
#                                  (5 of 6, Security absent) → WARN, NOT
#                                  blocking. Proves the documented POC contract
#                                  survived the fix.
#   T-mutation-p3-zero             excise the # BL-104-P3-ZERO line → the
#                                  0-step fixture passes again (RED).
#   T-mutation-manifest-arm        excise the # BL-104-MANIFEST-ARM line → the
#                                  empty-manifest fixture passes again (RED).
#
# bash-3.2 safe: no associative arrays, no mapfile, no ${var^^}.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-phase-gate.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] jq not available — the BL-104 scoring arms are jq-gated."
  exit 0
fi

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

E_SEC='{"reviewer":"security","status":"complete","artifact":"security-review-v1.md","date":"2026-05-01"}'
E_RT='{"reviewer":"Red Team / Offensive Security","status":"complete","artifact":"red-team-review-v1.md","date":"2026-05-01"}'
E_ENG='{"reviewer":"Senior Software Engineer","status":"complete","artifact":"senior-engineer-review-v1.md","date":"2026-05-01"}'
E_CIO='{"reviewer":"CIO Strategic","status":"complete","artifact":"cio-review-v1.md","date":"2026-05-01"}'
E_LEGAL='{"reviewer":"Corporate Legal","status":"complete","artifact":"legal-review-v1.md","date":"2026-05-01"}'
E_TU='{"reviewer":"Technical User (Non-Coder)","status":"complete","artifact":"technical-user-review-v1.md","date":"2026-05-01"}'

# The nine Phase-3 validation steps process-checklist.sh records.
P3_NINE='"integration_testing","security_hardening","chaos_testing","accessibility_audit","performance_audit","contract_testing","results_archived","pre_launch_preparation","legal_review"'
P3_FIVE='"integration_testing","security_hardening","chaos_testing","accessibility_audit","performance_audit"'

# write_manifest <path> <kind>
#   complete | partial-miss-security | empty | absent
write_manifest() {
  local path="$1" kind="$2" entries=""
  [ "$kind" = "absent" ] && return 0
  case "$kind" in
    complete)              entries="$E_SEC,$E_RT,$E_ENG,$E_CIO,$E_LEGAL,$E_TU" ;;
    partial-miss-security) entries="$E_RT,$E_ENG,$E_CIO,$E_LEGAL,$E_TU" ;;
    empty)                 entries="" ;;
  esac
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<JSON
{ "framework_version": "1.0", "module": "web-app", "commit": "abc1234def", "reviews": [ $entries ] }
JSON
}

# build_project <track> <enforced: yes|no> <manifest_kind> <p3_steps: nine|five|zero>
# Golden-clean Phase-3 project: every OTHER Phase 3→4 check passes, so the exit
# code is attributable to the two variables under test.
#
# NOTE (fixture correctness): this fixture records NINE completed Phase-3 steps
# by default. tests/test-bl073-review-manifest-gate.sh's equivalent fixture used
# `"steps_completed": []` and still exited 0 — it was riding Inversion 1. That is
# precisely the fixture-hides-product-gap shape BL-104 removes.
build_project() {
  local track="$1" enforced="$2" mkind="$3" steps="$4"
  TMP=$(mktemp -d)
  PROJ="$TMP/p"
  mkdir -p "$PROJ/.claude" "$PROJ/docs/test-results" "$PROJ/docs/eval-results"

  local flag_json=""
  [ "$enforced" = "yes" ] && flag_json='"review_gate_enforced": true,'

  local steps_json=""
  case "$steps" in
    nine) steps_json="$P3_NINE" ;;
    five) steps_json="$P3_FIVE" ;;
    zero) steps_json="" ;;
  esac

  cat > "$PROJ/.claude/phase-state.json" <<JSON
{
  "project": "bl104",
  "current_phase": 3,
  "track": "$track",
  "deployment": "personal",
  $flag_json
  "gates": {
    "phase_0_to_1": "2026-02-01",
    "phase_1_to_2": "2026-03-01",
    "phase_2_to_3": "2026-04-01",
    "phase_3_to_4": null
  }
}
JSON

  cat > "$PROJ/.claude/process-state.json" <<JSON
{
  "phase1_artifacts": { "data_classification": "public" },
  "phase2_init": { "steps_completed": ["remote_repo_created","pushed_initial"], "attestations": { "branch_protection": { "reason": "github_free_tier" } } },
  "phase3_validation": { "steps_completed": [ $steps_json ] }
}
JSON

  cat > "$PROJ/.claude/manifest.json" <<'JSON'
{ "host": "github", "mode": "personal" }
JSON

  cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# Approval Log

## Phase Gate: Phase 0 → Phase 1
| Field | Value |
|---|---|
| Approver | Alice Signer |
| Date | 2026-02-01 |

## Phase Gate: Phase 1 → Phase 2
| Field | Value |
|---|---|
| Approver | Alice Signer |
| Date | 2026-03-01 |

## Phase Gate: Phase 2 → Phase 3
| Field | Value |
|---|---|
| Approver | Alice Signer |
| Date | 2026-04-01 |
MD

  {
    local n
    for n in 1 2 3 4 5 6 7 8; do
      echo "## ${n}. Section ${n}"
      echo "Substantive content for section ${n} that is not a template placeholder."
      echo ""
    done
  } > "$PROJ/PRODUCT_MANIFESTO.md"

  {
    echo "# Features"
    echo ""
    echo "## Feature One"
    echo "Implemented."
    echo ""
    echo "## Feature Two"
    echo "Implemented."
  } > "$PROJ/FEATURES.md"

  {
    echo "# Project Bible"
    local b
    for b in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
      echo "## ${b}. Section ${b}"
      echo "Content for bible section ${b}."
      echo ""
    done
  } > "$PROJ/PROJECT_BIBLE.md"

  mkdir -p "$PROJ/docs/phase-0"
  printf 'frd\n' > "$PROJ/docs/phase-0/frd.md"
  printf 'journey\n' > "$PROJ/docs/phase-0/user-journey.md"
  printf 'contract\n' > "$PROJ/docs/phase-0/data-contract.md"
  echo "# Changelog" > "$PROJ/CHANGELOG.md"
  echo "# Handoff" > "$PROJ/HANDOFF.md"
  echo "# Incident Response" > "$PROJ/docs/INCIDENT_RESPONSE.md"
  echo '{"sbom":"ok"}' > "$PROJ/sbom.json"
  echo "# Security Policy" > "$PROJ/SECURITY.md"
  printf '# Bugs\n\nNo open bugs.\n' > "$PROJ/BUGS.md"
  echo "test results archived" > "$PROJ/docs/test-results/results.txt"
  echo "# Penetration Test Results" > "$PROJ/docs/test-results/pen-test.md"

  write_manifest "$PROJ/docs/eval-results/review-manifest.json" "$mkind"
}

teardown() { rm -rf "$TMP"; }

# run_gate [script_override]
run_gate() { ( cd "$PROJ" && bash "${1:-$SCRIPT}" 2>&1 ); }

has_p3_zero_warn()   { echo "$1" | grep -q "0/9 steps"; }
has_review_fail()    { echo "$1" | grep -q "requires the Security AND Red Team reviews before Phase 4"; }
has_bypass_warn()    { echo "$1" | grep -q "bypass logged (grandfathered / POC"; }
has_empty_man_warn() { echo "$1" | grep -q "ZERO completed reviews"; }

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-p3-nine-steps-passes: control — golden-clean fixture, 9/9 steps → rc=0 ==="
# ════════════════════════════════════════════════════════════════════
build_project light no complete nine
rc=0; out=$(run_gate) || rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T-p3-nine-steps-passes: the fixture is otherwise clean (rc=0) — the baseline is sound"
else
  fail_ "T-p3-nine-steps-passes" "expected rc=0 from the golden-clean fixture; got rc=$rc; out:
$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-p3-partial-steps-blocks: control — 5/9 steps → WARN + BLOCKS (unchanged) ==="
# ════════════════════════════════════════════════════════════════════
build_project light no complete five
rc=0; out=$(run_gate) || rc=$?
if echo "$out" | grep -q "5/9 steps" && [ "$rc" -ne 0 ]; then
  pass "T-p3-partial-steps-blocks: 5/9 WARNs and blocks (rc=$rc) — the arm the 0-step case must be consistent with"
else
  fail_ "T-p3-partial-steps-blocks" "expected a '5/9 steps' WARN and a non-zero exit; got rc=$rc; out:
$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-p3-zero-steps-warns: 0/9 steps → WARN AND BLOCKS (was: silent PASS) ==="
# ════════════════════════════════════════════════════════════════════
build_project light no complete zero
rc=0; out=$(run_gate) || rc=$?
if has_p3_zero_warn "$out"; then
  pass "T-p3-zero-steps-warns: emits the 0/9-steps WARN (main emitted nothing at all)"
else
  fail_ "T-p3-zero-steps-warns" "expected a '0/9 steps' WARN line; got none. out:
$out"
fi
if [ "$rc" -ne 0 ]; then
  pass "T-p3-zero-steps-warns: gate BLOCKS on zero Phase-3 steps (rc=$rc) — consistent with the 1-8 arm"
else
  fail_ "T-p3-zero-steps-warns" "SCORING INVERSION: 0/9 Phase-3 steps PASSED the gate (rc=0) while 5/9 blocks. out:
$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-no-manifest-blocks: control — grandfathered/light, NO manifest → blocks ==="
# ════════════════════════════════════════════════════════════════════
build_project light no absent nine
rc=0; out=$(run_gate) || rc=$?
if echo "$out" | grep -q "No review manifest found" && [ "$rc" -ne 0 ]; then
  pass "T-no-manifest-blocks: absent manifest WARNs and blocks (rc=$rc) — the reference arm"
else
  fail_ "T-no-manifest-blocks" "expected the no-manifest WARN + a non-zero exit; got rc=$rc; out:
$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-empty-manifest-not-a-bypass: {\"reviews\":[]} must not outscore no manifest ==="
# ════════════════════════════════════════════════════════════════════
build_project light no empty nine
rc=0; out=$(run_gate) || rc=$?
if has_empty_man_warn "$out"; then
  pass "T-empty-manifest-not-a-bypass: emits the ZERO-completed-reviews WARN"
else
  fail_ "T-empty-manifest-not-a-bypass" "expected a 'ZERO completed reviews' WARN; got none. out:
$out"
fi
if [ "$rc" -ne 0 ]; then
  pass "T-empty-manifest-not-a-bypass: an empty manifest still BLOCKS (rc=$rc) — the file-existence bypass is closed"
else
  fail_ "T-empty-manifest-not-a-bypass" "SCORING INVERSION: \`echo '{\"reviews\":[]}' > docs/eval-results/review-manifest.json\` flipped a BLOCKING gate into a PASSING one (rc=0). out:
$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-empty-manifest-enforced-fails: enforced standard + empty manifest → FAIL (not weakened) ==="
# ════════════════════════════════════════════════════════════════════
build_project standard yes empty nine
rc=0; out=$(run_gate) || rc=$?
if has_review_fail "$out" && [ "$rc" -ne 0 ]; then
  pass "T-empty-manifest-enforced-fails: enforced track still emits the review-gate [FAIL] and blocks (rc=$rc)"
else
  fail_ "T-empty-manifest-enforced-fails" "the enforced-track FAIL was weakened; rc=$rc; out:
$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-light-track-warn-only-preserved: light + PARTIAL manifest → WARN, NOT blocking ==="
# ════════════════════════════════════════════════════════════════════
# builders-guide.md § Phase 3→4: "track=light / personal: WARN only (POC
# preserved); the bypass is logged." A partial manifest records REAL review work;
# it must keep scoring as a non-blocking WARN. This is the contract the
# empty-manifest fix must NOT have trampled.
build_project light no partial-miss-security nine
rc=0; out=$(run_gate) || rc=$?
if has_bypass_warn "$out"; then
  pass "T-light-track-warn-only-preserved: emits the grandfathered/POC bypass WARN"
else
  fail_ "T-light-track-warn-only-preserved" "expected the 'bypass logged (grandfathered / POC' WARN; out:
$out"
fi
if [ "$rc" -eq 0 ]; then
  pass "T-light-track-warn-only-preserved: light track with a PARTIAL manifest still PASSES (rc=0) — POC contract intact"
else
  fail_ "T-light-track-warn-only-preserved" "REGRESSION: the documented light-track WARN-only contract now blocks (rc=$rc). out:
$out"
fi
if has_review_fail "$out"; then
  fail_ "T-light-track-warn-only-preserved" "light track must NOT emit the review-gate [FAIL] line; out:
$out"
else
  pass "T-light-track-warn-only-preserved: no review-gate [FAIL] on the light track"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-mutation-p3-zero: excise # BL-104-P3-ZERO → the 0-step fixture passes again ==="
# ════════════════════════════════════════════════════════════════════
MUT=$(mktemp -d)
MUT_SCRIPT="$MUT/scripts/check-phase-gate.sh"

# The gate sources scripts/lib/*.sh relative to its OWN path, so the mutant needs
# the libs beside it — otherwise it dies on startup and its non-zero exit would
# masquerade as "the gate blocked", a false GREEN.
mkdir -p "$MUT/scripts/lib"
cp "$REPO_ROOT"/scripts/lib/*.sh "$MUT/scripts/lib/" 2>/dev/null || true

# Excise the marked line — this neuters the BLOCK (issues++) while leaving the
# WARN echo intact, so the mutant is a valid script and the ONLY thing that
# changed is the gate outcome. Grepping for the marker would be tautological;
# we attack the behaviour.
grep -v '# BL-104-P3-ZERO$' "$SCRIPT" > "$MUT_SCRIPT"
chmod +x "$MUT_SCRIPT"
marker_n=$(grep -c '# BL-104-P3-ZERO$' "$SCRIPT" 2>/dev/null || echo "0")
case "$marker_n" in ''|*[!0-9]*) marker_n=0 ;; esac
if [ "$marker_n" -eq 0 ]; then
  fail_ "T-mutation-p3-zero" "no '# BL-104-P3-ZERO' marked line found in check-phase-gate.sh — nothing to mutate"
else
  if ! /bin/bash -n "$MUT_SCRIPT" 2>/dev/null; then
    fail_ "T-mutation-p3-zero" "the mutant is a syntax error — the excision must leave a valid script (add a non-marked guard line in the branch)"
  else
    build_project light no complete zero
    rc=0; out=$(run_gate "$MUT_SCRIPT") || rc=$?
    if [ "$rc" -eq 0 ]; then
      pass "T-mutation-p3-zero: without the marked line the 0-step gate PASSES again → the block is load-bearing (RED↔GREEN)"
    else
      fail_ "T-mutation-p3-zero" "mutant still blocked (rc=$rc) — the # BL-104-P3-ZERO line is not the thing doing the blocking. out:
$out"
    fi
    teardown
  fi
fi
rm -rf "$MUT"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-mutation-manifest-arm: excise # BL-104-MANIFEST-ARM → the empty manifest bypasses again ==="
# ════════════════════════════════════════════════════════════════════
MUT=$(mktemp -d)
MUT_SCRIPT="$MUT/scripts/check-phase-gate.sh"
mkdir -p "$MUT/scripts/lib"
cp "$REPO_ROOT"/scripts/lib/*.sh "$MUT/scripts/lib/" 2>/dev/null || true
grep -v '# BL-104-MANIFEST-ARM$' "$SCRIPT" > "$MUT_SCRIPT"
chmod +x "$MUT_SCRIPT"
marker_n=$(grep -c '# BL-104-MANIFEST-ARM$' "$SCRIPT" 2>/dev/null || echo "0")
case "$marker_n" in ''|*[!0-9]*) marker_n=0 ;; esac
if [ "$marker_n" -eq 0 ]; then
  fail_ "T-mutation-manifest-arm" "no '# BL-104-MANIFEST-ARM' marked line found in check-phase-gate.sh — nothing to mutate"
else
  if ! /bin/bash -n "$MUT_SCRIPT" 2>/dev/null; then
    fail_ "T-mutation-manifest-arm" "the mutant is a syntax error — the excision must leave a valid script"
  else
    build_project light no empty nine
    rc=0; out=$(run_gate "$MUT_SCRIPT") || rc=$?
    if [ "$rc" -eq 0 ]; then
      pass "T-mutation-manifest-arm: without the marked line the empty manifest BYPASSES again → the block is load-bearing (RED↔GREEN)"
    else
      fail_ "T-mutation-manifest-arm" "mutant still blocked (rc=$rc) — the # BL-104-MANIFEST-ARM line is not the thing doing the blocking. out:
$out"
    fi
    teardown
  fi
fi
rm -rf "$MUT"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
