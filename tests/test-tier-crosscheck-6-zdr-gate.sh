#!/usr/bin/env bash
# tests/test-tier-crosscheck-6-zdr-gate.sh — closes the final S3 audit
# finding `tier-crosscheck-6` (Phase 1→2 ZDR / data-classification gate).
#
# Audit context:
#   docs/governance-framework.md:299 declares a "Mandatory ZDR gate":
#     "Projects with data classified as Internal or higher (Internal,
#     Confidential, PII, Financial, Regulated) must use the ZDR or
#     self-hosted deployment path. This is a hard gate at Phase 1 — the
#     Orchestrator may not proceed to Phase 2 with a non-ZDR deployment
#     path."
#   The gate was declared but nothing enforced it: no field captured the
#   classification, no field recorded the ZDR attestation, and
#   check-phase-gate.sh had no Phase 1→2 backstop reading any such field.
#
# Fix (this PR):
#   * intake-wizard.sh prompts for data_classification + zdr_attested (+
#     optional zdr_attestation_reason when not attested).
#   * Both are persisted under
#     .claude/process-state.json::phase1_artifacts.{data_classification,
#       zdr_attested, zdr_attestation_reason}.
#   * scripts/check-phase-gate.sh refuses Phase 1→2 when
#     current_phase >= 2 AND (data_classification missing/invalid OR
#     no attestation evidence). Mirrors the github_free_tier backstop
#     pattern at scripts/check-phase-gate.sh:445-488 (PR #75).
#   * scripts/reconfigure-project.sh --field data_classification and
#     --field zdr_attested let operators correct post-intake (with
#     APPROVAL_LOG.md audit row + atomic snapshot/rollback).
#   * scripts/upgrade-project.sh refuses personal→organizational when
#     data_classification missing, redirecting to reconfigure.
#
# Taxonomy (7-tier, canonical lowercase form — adopted from
# templates/project-intake.md:209 and docs/user-guide.md:466):
#   public, internal, confidential, pii, financial, health, regulated
#
# Attestation shape:
#   zdr_attested: boolean. true means ZDR (or self-hosted) deployment
#     is in place. Required for any data_classification > public.
#   zdr_attestation_reason: free text (non-empty). Documents a written
#     exception (e.g. "customer requires retention", "self-hosted Ollama").
#     Either zdr_attested=true OR a non-empty reason satisfies the gate.
#
# RED→GREEN evidence — each T# below was confirmed RED on origin/main
# before implementing the fix. Verification command for each:
#   git stash && bash tests/test-tier-crosscheck-6-zdr-gate.sh
# Expected: every assertion FAILS on main (no gate exists).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# BL-074: copy the full helpers shim chain (helpers.sh -> helpers-full.sh
# -> helpers-core.sh) into every fixture, not just the helpers.sh shim.
source "$REPO_ROOT/tests/test-helpers/scaffold-libs.sh"
CHECK_GATE="$REPO_ROOT/scripts/check-phase-gate.sh"
RECONFIGURE="$REPO_ROOT/scripts/reconfigure-project.sh"
UPGRADE="$REPO_ROOT/scripts/upgrade-project.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Build a Phase-2 project that's syntactically clean for every OTHER
# check in check-phase-gate.sh so the only signal we measure is the
# ZDR/classification gate. Mirrors the fixture shape used by
# tests/test-check-phase-gate-backstop-attestation.sh.
mk_phase2_project() {
  local proj="$1"
  local classification="${2:-}"
  local zdr_attested="${3:-}"     # "true", "false", or "" (omit)
  local zdr_reason="${4:-}"       # free text, or "" (omit)

  mkdir -p "$proj/.claude"

  cat > "$proj/.claude/manifest.json" <<'JSON'
{"frameworkVersion":"test","host":"github","mode":"personal","enforcement_level":"strict"}
JSON

  cat > "$proj/.claude/phase-state.json" <<'JSON'
{"current_phase":2,"deployment":"personal","track":"light",
 "gates":{"phase_0_to_1":"2026-01-01","phase_1_to_2":"2026-02-01"},
 "phase_0_to_1":"2026-01-01","phase_1_to_2":"2026-02-01"}
JSON

  # process-state.json — base shape from the canonical seed in
  # scripts/init.sh + the github_free_tier attestation so the existing
  # Phase 1→2 backstop doesn't fail and mask our signal.
  local pstate
  pstate=$(jq -nc \
    --arg cls "$classification" \
    --arg att "$zdr_attested" \
    --arg rsn "$zdr_reason" \
    '{
      phase2_init: {
        steps_completed: [],
        verified: false,
        attestations: {
          branch_protection: {
            attested_by: "orchestrator",
            at: "2026-04-27T00:00:00Z",
            reason: "github_free_tier"
          }
        }
      },
      phase1_artifacts: (
        ({} as $base
        | (if $cls != "" then $base + {data_classification: $cls} else $base end)
        | (if $att != "" then . + {zdr_attested: ($att == "true")} else . end)
        | (if $rsn != "" then . + {zdr_attestation_reason: $rsn} else . end))
      )
    }')
  echo "$pstate" > "$proj/.claude/process-state.json"

  # APPROVAL_LOG.md with dated Phase 0→1 and Phase 1→2 entries so the
  # gate-date / approval-field checks don't accumulate issues.
  cat > "$proj/APPROVAL_LOG.md" <<'MD'
---
project: t
deployment: personal
created: 2026-01-01
framework: Solo Orchestrator v1.0
---

# Approval Log — t

## Phase Gate: Phase 0 → Phase 1
| Field | Value |
|---|---|
| **Approver** | Karl |
| **Role** | Sponsor |
| **Date** | 2026-01-01 |

## Phase Gate: Phase 1 → Phase 2
| Field | Value |
|---|---|
| **Approver** | Karl |
| **Role** | STA |
| **Date** | 2026-02-01 |
MD

  # PRODUCT_MANIFESTO.md — 8 numbered sections with content.
  {
    echo "# PRODUCT_MANIFESTO"
    for i in 1 2 3 4 5 6 7 8; do
      echo "## ${i}. Section ${i}"
      echo "Content for section ${i}."
      echo ""
    done
  } > "$proj/PRODUCT_MANIFESTO.md"

  # PROJECT_BIBLE.md — 14 numbered sections.
  {
    echo "# PROJECT_BIBLE"
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do
      echo "## ${i}. Section ${i}"
      echo "Content."
      echo ""
    done
  } > "$proj/PROJECT_BIBLE.md"
}

run_gate() {
  ( cd "$1" && bash "$CHECK_GATE" 2>&1 ); return $?
}

# Run check-phase-gate.sh and capture both output and exit code.
# We can't share rc through subshell exit because we want both.
run_gate_capture() {
  local proj="$1"
  local out
  out=$(cd "$proj" && bash "$CHECK_GATE" 2>&1)
  local rc=$?
  printf '%s\n--RC=%d' "$out" "$rc"
}

# Assert the captured output contains the ZDR/classification FAIL line
# AND the exit code is non-zero.
assert_gate_fails_with_classification_msg() {
  local label="$1" captured="$2"
  local rc="${captured##*--RC=}"
  local out="${captured%--RC=*}"
  if [ "$rc" = "0" ]; then
    fail_ "$label" "expected non-zero exit; got rc=0. Output tail:\n$(echo "$out" | tail -20)"
    return 1
  fi
  if ! echo "$out" | grep -qiE "data_classification|zdr"; then
    fail_ "$label" "expected FAIL line mentioning data_classification or ZDR; got:\n$(echo "$out" | tail -20)"
    return 1
  fi
  if ! echo "$out" | grep -qE "\[FAIL\].*Phase 1.*2.*ZDR|\[FAIL\].*ZDR|\[FAIL\].*data_classification"; then
    fail_ "$label" "expected a [FAIL]-prefixed line tied to the ZDR gate; got:\n$(echo "$out" | grep -E '\[FAIL\]')"
    return 1
  fi
  return 0
}

assert_gate_passes_classification() {
  local label="$1" captured="$2"
  local out="${captured%--RC=*}"
  if echo "$out" | grep -qE '\[FAIL\].*(ZDR|data_classification)'; then
    fail_ "$label" "did not expect ZDR/classification FAIL; got:\n$(echo "$out" | grep -E '\[FAIL\]')"
    return 1
  fi
  if ! echo "$out" | grep -qE '\[OK\].*Phase 1.*2.*(ZDR|data_classification|classification|attestation)'; then
    fail_ "$label" "expected an [OK] confirmation line for the ZDR gate; got tail:\n$(echo "$out" | tail -10)"
    return 1
  fi
  return 0
}

echo "== tests/test-tier-crosscheck-6-zdr-gate.sh =="
echo ""

# ════════════════════════════════════════════════════════════════════
# T1: positive — each valid classification with zdr_attested=true passes
# ════════════════════════════════════════════════════════════════════
echo "T1: each valid data_classification value + zdr_attested=true passes"
T1_FAILED=0
for cls in public internal confidential pii financial health regulated; do
  T=$(mktemp -d); P="$T/p"
  mk_phase2_project "$P" "$cls" "true" ""
  cap=$(run_gate_capture "$P")
  if ! assert_gate_passes_classification "T1[$cls]" "$cap"; then
    T1_FAILED=$((T1_FAILED + 1))
  fi
  rm -rf "$T"
done
if [ "$T1_FAILED" -eq 0 ]; then
  pass "T1: all 7 taxonomy values pass with zdr_attested=true (public, internal, confidential, pii, financial, health, regulated)"
fi

# ════════════════════════════════════════════════════════════════════
# T2: negative — classification absent → Phase 1→2 fails
# ════════════════════════════════════════════════════════════════════
echo ""
echo "T2: missing data_classification → Phase 1→2 fails"
T=$(mktemp -d); P="$T/p"
mk_phase2_project "$P" "" "true" ""   # no classification, has attestation
cap=$(run_gate_capture "$P")
assert_gate_fails_with_classification_msg "T2" "$cap" && pass "T2"
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
# T3: negative — classification set but neither attested nor reason → fails
# ════════════════════════════════════════════════════════════════════
echo ""
echo "T3: classification set, no zdr_attested, no reason → Phase 1→2 fails"
T=$(mktemp -d); P="$T/p"
mk_phase2_project "$P" "internal" "" ""   # classification only
cap=$(run_gate_capture "$P")
assert_gate_fails_with_classification_msg "T3" "$cap" && pass "T3"
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
# T4: attestation-reason path — zdr_attested=false but reason present → passes
# ════════════════════════════════════════════════════════════════════
echo ""
echo "T4: zdr_attested=false but zdr_attestation_reason='customer requires retention' → passes"
T=$(mktemp -d); P="$T/p"
mk_phase2_project "$P" "confidential" "false" "customer requires retention per signed SOW 2026-03-15"
cap=$(run_gate_capture "$P")
assert_gate_passes_classification "T4" "$cap" && pass "T4"
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
# T5: invalid value — data_classification="bogus" → fails
# ════════════════════════════════════════════════════════════════════
echo ""
echo "T5: data_classification='bogus' → fails with taxonomy-mismatch message"
T=$(mktemp -d); P="$T/p"
mk_phase2_project "$P" "bogus" "true" ""
cap=$(run_gate_capture "$P")
rc="${cap##*--RC=}"
out="${cap%--RC=*}"
if [ "$rc" = "0" ]; then
  fail_ "T5" "expected non-zero exit for invalid classification; got rc=0"
elif echo "$out" | grep -qiE "invalid.*classification|not.*(one of|in).*(public|taxonomy)|bogus"; then
  pass "T5"
else
  fail_ "T5" "expected message identifying the invalid value; got:\n$(echo "$out" | grep -iE 'classification|zdr' | head -3)"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
# T6: reconfigure-project.sh --field data_classification writes back
#     correctly and adds an APPROVAL_LOG.md audit row.
# ════════════════════════════════════════════════════════════════════
echo ""
echo "T6: reconfigure-project.sh --field data_classification --new <value> updates state + audit"
T=$(mktemp -d); P="$T/p"

# Build a minimal project that reconfigure-project.sh can operate on.
mkdir -p "$P/.claude" "$P/scripts/lib"
cp "$REPO_ROOT/scripts/reconfigure-project.sh" "$P/scripts/reconfigure-project.sh"
scaffold_helpers_libs "$P/scripts/lib" "$REPO_ROOT"
[ -f "$REPO_ROOT/scripts/lib/enforcement-level.sh" ] && cp "$REPO_ROOT/scripts/lib/enforcement-level.sh" "$P/scripts/lib/enforcement-level.sh"

cat > "$P/.claude/phase-state.json" <<'JSON'
{"project":"t","framework_version":"1.0","current_phase":1,"track":"light","deployment":"personal","poc_mode":null}
JSON
cat > "$P/.claude/tool-preferences.json" <<'JSON'
{"context":{"project":"t","platform":"web","language":"javascript","track":"light"}}
JSON
cat > "$P/.claude/orchestrator-source.json" <<JSON
{ "source_dir": "$REPO_ROOT" }
JSON
echo '{}' > "$P/.claude/process-state.json"
echo "# t — Operator Brief" > "$P/CLAUDE.md"
echo "# Project Intake — t" > "$P/PROJECT_INTAKE.md"
cat > "$P/APPROVAL_LOG.md" <<'MD'
---
project: t
deployment: personal
---

# Approval Log — t

## Approval History
| Date | Gate / Event | Approver | Role | Decision | Reference |
|---|---|---|---|---|---|
MD

( cd "$P" \
    && git init -q \
    && git config user.email t@t.l \
    && git config user.name t \
    && git add -A \
    && git commit -q -m "fixture" ) >/dev/null 2>&1

if ( cd "$P" && bash "$P/scripts/reconfigure-project.sh" --field data_classification --new confidential > "$T/log" 2>&1 ); then
  cls_after=$(jq -r '.phase1_artifacts.data_classification // ""' "$P/.claude/process-state.json")
  if [ "$cls_after" != "confidential" ]; then
    fail_ "T6" "process-state.json did not record data_classification=confidential (got '$cls_after'). Log:\n$(cat "$T/log")"
  elif ! grep -qE "data_classification|classification" "$P/APPROVAL_LOG.md"; then
    fail_ "T6" "APPROVAL_LOG.md did not get a classification audit row. Tail:\n$(tail -20 "$P/APPROVAL_LOG.md")"
  else
    pass "T6"
  fi
else
  fail_ "T6" "reconfigure-project.sh --field data_classification exited non-zero. Log:\n$(cat "$T/log")"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
# T7: upgrade-project.sh personal→organizational refuses when
#     data_classification missing (non-interactive context).
# ════════════════════════════════════════════════════════════════════
echo ""
echo "T7: upgrade-project.sh --deployment organizational (non-interactive) refuses without data_classification"
T=$(mktemp -d); P="$T/p"

# Hand-rolled fixture so we don't pay the full init.sh cost. Mirrors the
# fixture pattern used by tests/test-upgrade-project-retroactive-section.sh.
mkdir -p "$P/.claude" "$P/scripts/lib" "$P/scripts/host-drivers" "$P/scripts/hooks"
cp "$REPO_ROOT/scripts/upgrade-project.sh" "$P/scripts/upgrade-project.sh"
scaffold_helpers_libs "$P/scripts/lib" "$REPO_ROOT"
[ -f "$REPO_ROOT/scripts/lib/host.sh" ] && cp "$REPO_ROOT/scripts/lib/host.sh" "$P/scripts/lib/host.sh"
[ -f "$REPO_ROOT/scripts/host-drivers/github.sh" ] && cp "$REPO_ROOT/scripts/host-drivers/github.sh" "$P/scripts/host-drivers/github.sh"

cat > "$P/.claude/manifest.json" <<'JSON'
{"frameworkVersion":"test","host":"github","mode":"personal","enforcement_level":"strict","deployment":"personal","poc_mode":null}
JSON
cat > "$P/.claude/phase-state.json" <<'JSON'
{"project":"t","framework_version":"1.0","current_phase":2,"track":"light","deployment":"personal","poc_mode":null,
 "phase_0_to_1":"2026-01-01","phase_1_to_2":"2026-02-01"}
JSON
cat > "$P/.claude/tool-preferences.json" <<'JSON'
{"context":{"project":"t","platform":"web","language":"javascript","track":"light","dev_os":"darwin"}}
JSON
cat > "$P/.claude/orchestrator-source.json" <<JSON
{ "source_dir": "$REPO_ROOT" }
JSON
# Intentionally NO data_classification in process-state.json.
echo '{"phase2_init":{"steps_completed":[],"verified":false}}' > "$P/.claude/process-state.json"

# Minimal personal APPROVAL_LOG (org template fields will be regenerated).
cat > "$P/APPROVAL_LOG.md" <<'MD'
---
project: t
deployment: personal
---

# Approval Log — t

## Phase Gate: Phase 0 → Phase 1
| Field | Value |
|---|---|
| **Approver** | Karl |
| **Role** | Sponsor |
| **Date** | 2026-01-01 |
MD

# Minimal CLAUDE.md / PROJECT_INTAKE.md
echo "# t" > "$P/CLAUDE.md"
echo "# Project Intake — t" > "$P/PROJECT_INTAKE.md"
# bypass-audit.json so upgrade's BL-030 backfill is a no-op write.
echo "[]" > "$P/.claude/bypass-audit.json"

( cd "$P" \
    && git init -q \
    && git config user.email t@t.l \
    && git config user.name t \
    && git add -A \
    && git commit -q -m "fixture" ) >/dev/null 2>&1

# Run upgrade with --non-interactive so the missing-classification check
# refuses (rather than prompting). Expect non-zero exit + a message that
# names data_classification and points the operator at reconfigure.
if ( cd "$P" && SOIF_NONINTERACTIVE=1 bash "$P/scripts/upgrade-project.sh" --deployment organizational --non-interactive > "$T/log" 2>&1 ); then
  fail_ "T7" "upgrade-project.sh succeeded without data_classification (expected refusal). Log tail:\n$(tail -30 "$T/log")"
else
  if grep -qiE "data_classification" "$T/log"; then
    if grep -qE "reconfigure-project|--field data_classification" "$T/log"; then
      pass "T7"
    else
      fail_ "T7" "refused but did not point to reconfigure-project.sh / --field data_classification. Log:\n$(tail -30 "$T/log")"
    fi
  else
    fail_ "T7" "refused for unrelated reason — log does not mention data_classification. Tail:\n$(tail -30 "$T/log")"
  fi
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
# T8: public-data exemption — Public doesn't need ZDR attestation.
# docs/governance-framework.md § VII line 297-299 makes ZDR mandatory
# for "Internal or higher". Public is the explicit exemption — there
# is no sensitive data to retain, so no attestation is needed. Verify
# the gate honors this by passing with classification='public' and
# NO attestation at all (no zdr_attested, no reason).
# ════════════════════════════════════════════════════════════════════
echo ""
echo "T8: data_classification='public' with no attestation evidence → passes (governance-framework.md § VII line 297-299 exemption)"
T=$(mktemp -d); P="$T/p"
mk_phase2_project "$P" "public" "" ""   # no attestation, no reason
cap=$(run_gate_capture "$P")
out="${cap%--RC=*}"
rc="${cap##*--RC=}"
if [ "$rc" != "0" ]; then
  fail_ "T8" "expected exit 0 with public data + no attestation; got rc=$rc. Tail:\n$(echo "$out" | tail -10)"
elif ! echo "$out" | grep -qE "\[OK\].*public.*not required|\[OK\].*ZDR.*public"; then
  fail_ "T8" "expected [OK] line mentioning public exemption; got:\n$(echo "$out" | grep -E '\[OK\].*ZDR' | head -3)"
else
  pass "T8"
fi
rm -rf "$T"

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
