#!/usr/bin/env bash
# tests/test-bl073-review-manifest-gate.sh
#
# BL-073 regression: the Phase 3 → 4 review-manifest check in
# scripts/check-phase-gate.sh must be a REAL, track-aware gate — not the
# pre-BL-073 WARN-that-only-checks-the-file-exists. Contract pinned here:
#
#   T-full-missing-security-fails   track=full  + review_gate_enforced,
#                                   manifest present but no Security review
#                                   → gate FAILs (blocks, rc!=0) with the
#                                   review-gate [FAIL] line.
#   T-full-missing-redteam-fails    same, Red Team absent → FAIL.
#   T-standard-missing-security-fails  track=standard, Security absent → FAIL.
#   T-full-missing-cio-warns        track=full, CIO absent (non-mandatory)
#                                   → WARN + still-blocking (Full needs six),
#                                   NO review-gate FAIL line.
#   T-light-missing-security-warns  track=light, Security absent → WARN only,
#                                   NOT blocked (POC preserved), no FAIL line.
#   T-grandfather                   pre-existing project (NO
#                                   review_gate_enforced flag), full track,
#                                   Security absent → WARN only, NOT blocked
#                                   (never retroactively FAILs). Contrast with
#                                   T-full-missing-security-fails proves the
#                                   flag is the cutover.
#   T-attested-escape               SOLO_REVIEWERS_ATTESTED=1 + reason on an
#                                   enforced full-track project with a gap →
#                                   attested OK (not blocked), and the reason
#                                   is RECORDED to
#                                   process-state.json::phase3.attestations.reviewers.
#   T-full-complete-passes          sanity: enforced full track + all six
#                                   reviewers complete → gate PASSES (rc=0).
#   T-mutation                      MUTATION-PROOF: strip the marked
#                                   `# BL-073-ESCALATE` line(s) from a copy of
#                                   the script (reverts the FAIL escalation to
#                                   WARN-only) and re-run the full-missing-
#                                   security fixture → the review-gate [FAIL]
#                                   line disappears. Proves the escalation is
#                                   load-bearing (remove it → the *-fails tests
#                                   go RED).
#   Linter: T-lint-valid / T-lint-invalid pin scripts/lint-review-manifest.sh.
#
# bash-3.2 safe: no associative arrays, no mapfile, no ${var^^}.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-phase-gate.sh"
LINTER="$REPO_ROOT/scripts/lint-review-manifest.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] jq not available — the BL-073 review gate requires jq to parse the manifest."
  exit 0
fi

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# ── Reviewer manifest entries (BL-073 contract shape) ─────────────────
E_SEC='{"reviewer":"security","status":"complete","artifact":"security-review-v1.md","signed_by":"AI review (SVP IT Security)","date":"2026-05-01"}'
E_RT='{"reviewer":"Red Team / Offensive Security","status":"complete","artifact":"redteam-review-v1.md","signed_by":"AI review","date":"2026-05-01"}'
E_ENG='{"reviewer":"Senior Software Engineer","status":"complete","artifact":"engineer-review-v1.md","date":"2026-05-01"}'
E_CIO='{"reviewer":"CIO Strategic","status":"complete","artifact":"cio-review-v1.md","date":"2026-05-01"}'
E_LEGAL='{"reviewer":"Corporate Legal","status":"complete","artifact":"legal-review-v1.md","date":"2026-05-01"}'
E_TU='{"reviewer":"Technical User (Non-Coder)","status":"complete","artifact":"techuser-review-v1.md","date":"2026-05-01"}'

# write_manifest <path> <kind>
#   kind: complete | miss-security | miss-redteam | miss-cio | absent
write_manifest() {
  local path="$1" kind="$2" entries=""
  [ "$kind" = "absent" ] && return 0
  case "$kind" in
    complete)      entries="$E_SEC,$E_RT,$E_ENG,$E_CIO,$E_LEGAL,$E_TU" ;;
    miss-security) entries="$E_RT,$E_ENG,$E_CIO,$E_LEGAL,$E_TU" ;;
    miss-redteam)  entries="$E_SEC,$E_ENG,$E_CIO,$E_LEGAL,$E_TU" ;;
    miss-cio)      entries="$E_SEC,$E_RT,$E_ENG,$E_LEGAL,$E_TU" ;;
  esac
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<JSON
{ "framework_version": "1.0", "module": "web-app", "commit": "abc1234def", "reviews": [ $entries ] }
JSON
}

# build_project <track> <flag: yes|no> <manifest_kind>
# Constructs a golden-clean Phase-3 project so the ONLY variable is the
# review manifest — every other Phase 3→4 check passes, so the gate's exit
# code reflects the review gate alone.
build_project() {
  local track="$1" flag="$2" mkind="$3"
  TMP=$(mktemp -d)
  PROJ="$TMP/p"
  mkdir -p "$PROJ/.claude" "$PROJ/docs/test-results" "$PROJ/docs/eval-results"

  local flag_json=""
  [ "$flag" = "yes" ] && flag_json='"review_gate_enforced": true,'

  cat > "$PROJ/.claude/phase-state.json" <<JSON
{
  "project": "bl073",
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

  # process-state.json: satisfy the Phase 1→2 ZDR gate (public) and the
  # branch-protection backstop (github_free_tier attestation) so neither
  # adds an unrelated issue.
  cat > "$PROJ/.claude/process-state.json" <<JSON
{
  "phase1_artifacts": { "data_classification": "public" },
  "phase2_init": { "attestations": { "branch_protection": { "reason": "github_free_tier" } } },
  "phase3_validation": { "steps_completed": [] }
}
JSON

  # manifest.json must exist for the backstop block to reach the attestation.
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

  # FEATURES.md needs `## ` feature headings or test-gate.sh's feature-
  # completeness check WARNs ("appears empty") → bug gate rc=2 → an issue.
  {
    echo "# Features"
    echo ""
    echo "## Feature One"
    echo "Implemented."
    echo ""
    echo "## Feature Two"
    echo "Implemented."
  } > "$PROJ/FEATURES.md"
  # PROJECT_BIBLE.md is a Phase 1→2 artifact (FAIL if missing); 16 numbered
  # sections and no YYYY-MM-DD placeholders keep it WARN-free too.
  {
    echo "# Project Bible"
    local b
    for b in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
      echo "## ${b}. Section ${b}"
      echo "Content for bible section ${b}."
      echo ""
    done
  } > "$PROJ/PROJECT_BIBLE.md"
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

run_gate() { ( cd "$PROJ" && bash "$SCRIPT" 2>&1 ); }

# Distinctive review-gate output signals.
has_review_fail() { echo "$1" | grep -q "requires the Security AND Red Team reviews before Phase 4"; }
has_bypass_warn() { echo "$1" | grep -q "bypass logged (grandfathered / POC"; }
has_attested()    { echo "$1" | grep -q "ATTESTED (reason"; }
has_full_six()    { echo "$1" | grep -q "Full Track requires all six reviewers"; }

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-full-complete-passes: enforced full track + all six complete → PASS (rc=0) ==="
# ════════════════════════════════════════════════════════════════════
build_project full yes complete
rc=0; out=$(run_gate) || rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T-full-complete-passes: clean fixture with a complete manifest exits 0 (golden baseline)"
else
  fail_ "T-full-complete-passes" "expected exit 0 with a complete manifest; got rc=$rc; out:
$out"
fi
if echo "$out" | grep -q "Security and Red Team reviews complete"; then
  pass "T-full-complete-passes: emits the 'reviews complete' OK line"
else
  fail_ "T-full-complete-passes" "missing the 'Security and Red Team reviews complete' OK line; out:
$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-full-missing-security-fails: track=full enforced, no Security → FAIL ==="
# ════════════════════════════════════════════════════════════════════
build_project full yes miss-security
rc=0; out=$(run_gate) || rc=$?
if has_review_fail "$out"; then
  pass "T-full-missing-security-fails: emits the review-gate [FAIL] line"
else
  fail_ "T-full-missing-security-fails" "expected a review-gate FAIL line; out:
$out"
fi
if [ "$rc" -ne 0 ]; then
  pass "T-full-missing-security-fails: gate blocks (rc=$rc)"
else
  fail_ "T-full-missing-security-fails" "expected non-zero exit; got rc=0; out:
$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-full-missing-redteam-fails: track=full enforced, no Red Team → FAIL ==="
# ════════════════════════════════════════════════════════════════════
build_project full yes miss-redteam
rc=0; out=$(run_gate) || rc=$?
if has_review_fail "$out" && [ "$rc" -ne 0 ]; then
  pass "T-full-missing-redteam-fails: review-gate FAIL + blocks (rc=$rc)"
else
  fail_ "T-full-missing-redteam-fails" "expected review-gate FAIL and rc!=0; rc=$rc; out:
$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-standard-missing-security-fails: track=standard enforced, no Security → FAIL ==="
# ════════════════════════════════════════════════════════════════════
build_project standard yes miss-security
rc=0; out=$(run_gate) || rc=$?
if has_review_fail "$out" && [ "$rc" -ne 0 ]; then
  pass "T-standard-missing-security-fails: review-gate FAIL + blocks (rc=$rc)"
else
  fail_ "T-standard-missing-security-fails" "expected review-gate FAIL and rc!=0; rc=$rc; out:
$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-full-missing-cio-warns: track=full enforced, mandatory present, CIO absent → WARN + block, no review FAIL ==="
# ════════════════════════════════════════════════════════════════════
build_project full yes miss-cio
rc=0; out=$(run_gate) || rc=$?
if has_full_six "$out"; then
  pass "T-full-missing-cio-warns: emits the Full-Track-requires-all-six WARN"
else
  fail_ "T-full-missing-cio-warns" "expected the Full-Track all-six WARN; out:
$out"
fi
if ! has_review_fail "$out"; then
  pass "T-full-missing-cio-warns: does NOT emit the mandatory-reviewer [FAIL] (Security + Red Team present)"
else
  fail_ "T-full-missing-cio-warns" "unexpected mandatory-reviewer FAIL when only CIO is missing; out:
$out"
fi
if [ "$rc" -ne 0 ]; then
  pass "T-full-missing-cio-warns: still gate-blocking (rc=$rc) — Full needs all six"
else
  fail_ "T-full-missing-cio-warns" "expected rc!=0 (all-six blocking); got rc=0; out:
$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-light-missing-security-warns: track=light enforced-flag, no Security → WARN only, NOT blocked ==="
# ════════════════════════════════════════════════════════════════════
build_project light yes miss-security
rc=0; out=$(run_gate) || rc=$?
if has_bypass_warn "$out" && ! has_review_fail "$out"; then
  pass "T-light-missing-security-warns: WARN (bypass logged), no FAIL (POC preserved)"
else
  fail_ "T-light-missing-security-warns" "expected a bypass WARN and no FAIL; out:
$out"
fi
if [ "$rc" -eq 0 ]; then
  pass "T-light-missing-security-warns: gate NOT blocked by the review gate (rc=0)"
else
  fail_ "T-light-missing-security-warns" "expected rc=0 (light not blocked); got rc=$rc; out:
$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-grandfather: pre-existing (no flag) full track, no Security → WARN only, NOT blocked ==="
# ════════════════════════════════════════════════════════════════════
build_project full no miss-security
rc=0; out=$(run_gate) || rc=$?
if ! has_review_fail "$out"; then
  pass "T-grandfather: no review-gate FAIL despite full track (grandfathered — flag absent)"
else
  fail_ "T-grandfather" "grandfathered project was retroactively FAILed; out:
$out"
fi
if has_bypass_warn "$out"; then
  pass "T-grandfather: emits the WARN-only bypass line"
else
  fail_ "T-grandfather" "expected a WARN bypass line for the grandfathered project; out:
$out"
fi
if [ "$rc" -eq 0 ]; then
  pass "T-grandfather: NOT blocked (rc=0) — enforcement keyed on review_gate_enforced"
else
  fail_ "T-grandfather" "expected rc=0 (grandfathered not blocked); got rc=$rc; out:
$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-attested-escape: SOLO_REVIEWERS_ATTESTED=1 + reason → attested OK + recorded ==="
# ════════════════════════════════════════════════════════════════════
build_project full yes miss-security
REASON="poc time-box; Security review deferred to sponsor sign-off"
rc=0
out=$( cd "$PROJ" && SOLO_REVIEWERS_ATTESTED=1 SOLO_REVIEWERS_ATTESTED_REASON="$REASON" bash "$SCRIPT" 2>&1 ) || rc=$?
if has_attested "$out" && ! has_review_fail "$out"; then
  pass "T-attested-escape: attested OK line present, no review-gate FAIL"
else
  fail_ "T-attested-escape" "expected attested OK and no FAIL; out:
$out"
fi
if [ "$rc" -eq 0 ]; then
  pass "T-attested-escape: gate NOT blocked (rc=0)"
else
  fail_ "T-attested-escape" "expected rc=0 under attestation; got rc=$rc; out:
$out"
fi
recorded=$(jq -r '.phase3.attestations.reviewers.reason // ""' "$PROJ/.claude/process-state.json" 2>/dev/null || echo "")
if [ "$recorded" = "$REASON" ]; then
  pass "T-attested-escape: reason recorded to process-state.json::phase3.attestations.reviewers (not silenced)"
else
  fail_ "T-attested-escape" "expected recorded reason '$REASON', got '$recorded'"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-mutation: strip # BL-073-ESCALATE → review-gate FAIL disappears (RED proof) ==="
# ════════════════════════════════════════════════════════════════════
# Copy the script + libs, excise every line carrying the BL-073-ESCALATE
# marker (the review_sev=\"FAIL\" escalation), and re-run the full-missing-
# security fixture. With the escalation removed the gate reverts to
# WARN-only, so the review-gate [FAIL] line must be gone — proving the
# marked line is what makes T-full-missing-security-fails (and its siblings)
# blocking. Remove it → those tests go RED.
build_project full yes miss-security
MUT="$TMP/mut"
mkdir -p "$MUT/scripts/lib"
cp "$SCRIPT" "$MUT/scripts/check-phase-gate.sh"
cp "$REPO_ROOT"/scripts/lib/*.sh "$MUT/scripts/lib/" 2>/dev/null || true
grep -v 'BL-073-ESCALATE' "$MUT/scripts/check-phase-gate.sh" > "$MUT/scripts/check-phase-gate.sh.tmp"
mv "$MUT/scripts/check-phase-gate.sh.tmp" "$MUT/scripts/check-phase-gate.sh"
chmod +x "$MUT/scripts/check-phase-gate.sh"
if ! grep -q 'BL-073-ESCALATE' "$SCRIPT"; then
  fail_ "T-mutation" "BL-073-ESCALATE marker missing from the REAL script — nothing to mutate (escalation unmarked?)"
elif grep -q 'BL-073-ESCALATE' "$MUT/scripts/check-phase-gate.sh"; then
  fail_ "T-mutation" "BL-073-ESCALATE marker still present after excision — mutation did not apply"
else
  mut_out=$( cd "$PROJ" && bash "$MUT/scripts/check-phase-gate.sh" 2>&1 ) || true
  if has_review_fail "$mut_out"; then
    fail_ "T-mutation" "review-gate FAIL still emitted after excising the escalation — mutation is not proof; out:
$mut_out"
  else
    pass "T-mutation: excising BL-073-ESCALATE removes the review-gate FAIL (escalation is load-bearing)"
  fi
  # And confirm the real (un-mutated) script DID emit the FAIL on the same fixture.
  real_out=$(run_gate) || true
  if has_review_fail "$real_out"; then
    pass "T-mutation: the un-mutated script emits the FAIL on the same fixture (RED→GREEN contrast)"
  else
    fail_ "T-mutation" "the real script did NOT emit the FAIL on the mutation fixture — contrast broken; out:
$real_out"
  fi
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Linter: T-lint-valid / T-lint-invalid (scripts/lint-review-manifest.sh) ==="
# ════════════════════════════════════════════════════════════════════
LTMP=$(mktemp -d)
write_manifest "$LTMP/valid.json" complete
if bash "$LINTER" --file "$LTMP/valid.json" >/dev/null 2>&1; then
  pass "T-lint-valid: a well-formed manifest passes the linter (rc=0)"
else
  fail_ "T-lint-valid" "the linter rejected a valid manifest"
fi
cat > "$LTMP/invalid.json" <<'JSON'
{ "reviews": [ {"reviewer": "security", "artifact": "x.md"} ] }
JSON
if bash "$LINTER" --file "$LTMP/invalid.json" >/dev/null 2>&1; then
  fail_ "T-lint-invalid" "the linter accepted a manifest with a missing status field"
else
  pass "T-lint-invalid: a manifest missing the required 'status' field is rejected (rc!=0)"
fi
cat > "$LTMP/notarray.json" <<'JSON'
{ "reviews": {"reviewer": "security"} }
JSON
if bash "$LINTER" --file "$LTMP/notarray.json" >/dev/null 2>&1; then
  fail_ "T-lint-invalid" "the linter accepted a non-array .reviews"
else
  pass "T-lint-invalid: a non-array .reviews is rejected (rc!=0)"
fi
rm -rf "$LTMP"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
