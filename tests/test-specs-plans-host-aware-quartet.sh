#!/usr/bin/env bash
# tests/test-specs-plans-host-aware-quartet.sh
#
# Regression tests for the S3 specs-plans-host-aware quartet:
#   - specs-plans-host-aware-1  : spec ↔ implementation drift (Cat 5 vs free-tier attestation)
#   - specs-plans-host-aware-2  : plan vs init.sh drift (steps_completed written once, not incrementally)
#   - specs-plans-host-aware-8  : plan tasks 7.4/7.5 leave per-language CI templates as "follow the pattern"
#   - specs-plans-host-aware-11 : plan task 6.4 cmd_repair ignores steps_completed contract
#
# All assertions intentionally encode the recommended option from the audit brief
# so future drift between spec/plan/impl trips a test.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SPEC="$REPO_ROOT/docs/superpowers/specs/2026-04-21-host-aware-repo-gate-design.md"
PLAN="$REPO_ROOT/docs/superpowers/plans/2026-04-22-host-aware-repo-gate-implementation.md"
INIT_SH="$REPO_ROOT/init.sh"
CHECK_GATE="$REPO_ROOT/scripts/check-gate.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# ----------------------------------------------------------------------------
# Finding #1 — Spec must document Error Handling category 6 (tier-limited
# host capability gaps / BL-002) that legitimises the github_free_tier
# attestation fallback at scripts/host-drivers/github.sh:131-133.
# ----------------------------------------------------------------------------
t1_spec_documents_category_6_tier_limited() {
  if [ ! -f "$SPEC" ]; then
    fail_ "T1" "spec file not found at $SPEC"
    return
  fi
  # Must have a "### 6. " heading in the Error Handling section.
  if ! grep -qE '^### 6\. ' "$SPEC"; then
    fail_ "T1" "spec missing Error Handling category 6 heading"
    return
  fi
  # Must mention tier-limited / BL-002 / github_free_tier so future readers
  # can tie spec text to driver behaviour and backlog item.
  if ! grep -qE 'Tier-limited|tier-limited|tier limited' "$SPEC"; then
    fail_ "T1" "category 6 must describe 'tier-limited host capability gaps'"
    return
  fi
  if ! grep -q 'BL-002' "$SPEC"; then
    fail_ "T1" "category 6 must cross-link to BL-002"
    return
  fi
  if ! grep -q 'github_free_tier' "$SPEC"; then
    fail_ "T1" "category 6 must name the github_free_tier attestation reason"
    return
  fi
  if ! grep -q 'branch-protection-attested' "$SPEC"; then
    fail_ "T1" "category 6 must reference the --branch-protection-attested flag"
    return
  fi
  # And it must be after categories 1-5 in document order.
  local line5 line6
  line5=$(grep -nE '^### 5\. ' "$SPEC" | head -n1 | cut -d: -f1)
  line6=$(grep -nE '^### 6\. ' "$SPEC" | head -n1 | cut -d: -f1)
  if [ -z "$line5" ] || [ -z "$line6" ] || [ "$line6" -le "$line5" ]; then
    fail_ "T1" "category 6 must appear after category 5 (line5=$line5 line6=$line6)"
    return
  fi
  # And the Cat-5 outage-fallback promise ("Never falls back to manual
  # attestation") must be preserved — Option B leaves it intact.
  if ! grep -q 'Never falls back to manual attestation' "$SPEC"; then
    fail_ "T1" "spec category 5 must still state 'Never falls back to manual attestation' (Option B keeps Cat-5 intact)"
    return
  fi
  pass "T1: spec documents Error Handling category 6 (tier-limited / BL-002 / github_free_tier)"
}

# ----------------------------------------------------------------------------
# Finding #2 — Plan task 4.3 + init.sh must record incremental
# steps_completed entries. Each successful host_ call should append its
# named step before the next call.
# ----------------------------------------------------------------------------
t2_init_writes_incremental_steps_completed() {
  if [ ! -f "$INIT_SH" ]; then
    fail_ "T2" "init.sh not found"
    return
  fi
  # The four named steps must each be referenced in init.sh so the
  # incremental writes are findable by grep.
  local missing=""
  for step in remote_repo_created pushed_initial branch_protection_configured branch_protection_verified; do
    if ! grep -q "\"$step\"" "$INIT_SH"; then
      missing="$missing $step"
    fi
  done
  if [ -n "$missing" ]; then
    fail_ "T2" "init.sh missing named steps:$missing"
    return
  fi
  # There must be MORE than one incremental write of steps_completed — the
  # bug was a single batched write at the end. Count the per-step write
  # sites: either direct jq mutations or calls to the _record_phase2_step
  # helper (which itself encapsulates the jq write). Either pattern is fine
  # so long as there are ≥4 distinct call sites (one per named step) so a
  # mid-flight failure leaves accurate partial state.
  local writes call_sites
  writes=$(grep -cE '\.phase2_init\.steps_completed[[:space:]]*\+?=' "$INIT_SH" || true)
  case "$writes" in ''|*[!0-9]*) writes=0 ;; esac
  call_sites=$(grep -cE '_record_phase2_step[[:space:]]+"(remote_repo_created|pushed_initial|branch_protection_configured|branch_protection_verified)"' "$INIT_SH" || true)
  case "$call_sites" in ''|*[!0-9]*) call_sites=0 ;; esac
  local total=$((writes + call_sites))
  if [ "$total" -lt 4 ]; then
    fail_ "T2" "expected ≥4 incremental write sites for phase2_init.steps_completed in init.sh, found writes=$writes call_sites=$call_sites"
    return
  fi
  # And the helper itself must be defined exactly once if call_sites > 0.
  if [ "$call_sites" -gt 0 ]; then
    local helper_def
    helper_def=$(grep -cE '^[[:space:]]*_record_phase2_step\(\)' "$INIT_SH" || true)
    case "$helper_def" in ''|*[!0-9]*) helper_def=0 ;; esac
    if [ "$helper_def" -lt 1 ]; then
      fail_ "T2" "helper _record_phase2_step is called but not defined"
      return
    fi
  fi
  pass "T2: init.sh writes the 4 named steps_completed entries incrementally (writes=$writes call_sites=$call_sites)"
}

t2b_plan_task_4_3_documents_named_steps() {
  if [ ! -f "$PLAN" ]; then
    fail_ "T2b" "plan file not found"
    return
  fi
  # Plan task 4.3 must explicitly list the 4 named steps so the spec
  # contract is unambiguous for executing agents.
  local task_line
  task_line=$(grep -nE '^### Task 4\.3' "$PLAN" | head -n1 | cut -d: -f1)
  if [ -z "$task_line" ]; then
    fail_ "T2b" "could not locate '### Task 4.3' in plan"
    return
  fi
  # Read the next ~250 lines (task body) and confirm all four step names appear.
  local body
  body=$(awk -v start="$task_line" 'NR>=start && NR<start+250' "$PLAN")
  for step in remote_repo_created pushed_initial branch_protection_configured branch_protection_verified; do
    if ! echo "$body" | grep -q "$step"; then
      fail_ "T2b" "plan task 4.3 missing step name '$step'"
      return
    fi
  done
  pass "T2b: plan task 4.3 lists all 4 named steps_completed entries"
}

# ----------------------------------------------------------------------------
# Finding #8 — Plan tasks 7.2 (GitLab CI), 7.4 (Bitbucket CI), 7.3 (GitLab
# release) and 7.5 (Bitbucket release) must each carry a normative per-
# language / per-platform translation-delta table covering ALL remaining
# templates, not just leave them as "follow the pattern".
# ----------------------------------------------------------------------------
t8_plan_has_translation_delta_tables() {
  if [ ! -f "$PLAN" ]; then
    fail_ "T8" "plan file not found"
    return
  fi
  local missing=""
  for task in "7\.2" "7\.3" "7\.4" "7\.5"; do
    local start
    start=$(grep -nE "^### Task ${task}" "$PLAN" | head -n1 | cut -d: -f1)
    if [ -z "$start" ]; then
      missing="$missing Task${task//\\/}"
      continue
    fi
    local body
    body=$(awk -v s="$start" 'NR>=s && NR<s+400' "$PLAN")
    # The translation delta marker must appear in each task body.
    if ! echo "$body" | grep -q 'Translation delta table'; then
      missing="$missing Task${task//\\/}:no-delta-table"
    fi
  done
  if [ -n "$missing" ]; then
    fail_ "T8" "missing translation delta tables in plan:$missing"
    return
  fi
  # The CI delta tables (7.2 / 7.4) must cover all 10 non-exemplar
  # languages so executing agents have a row to consult per file.
  # Python + TypeScript are exemplars; the remaining 8 must each appear.
  for task in "7\.2" "7\.4"; do
    local start body
    start=$(grep -nE "^### Task ${task}" "$PLAN" | head -n1 | cut -d: -f1)
    body=$(awk -v s="$start" 'NR>=s && NR<s+400' "$PLAN")
    for lang in rust go java kotlin csharp swift dart other; do
      if ! echo "$body" | grep -qiE "\\| ?${lang}\\b"; then
        fail_ "T8" "Task ${task//\\/} delta table missing language row: $lang"
        return
      fi
    done
  done
  # The release delta tables (7.3 / 7.5) must cover the 3 non-exemplar
  # platforms (web is the exemplar in current plan text).
  for task in "7\.3" "7\.5"; do
    local start body
    start=$(grep -nE "^### Task ${task}" "$PLAN" | head -n1 | cut -d: -f1)
    body=$(awk -v s="$start" 'NR>=s && NR<s+400' "$PLAN")
    for platform in desktop mobile mcp-server; do
      if ! echo "$body" | grep -qiE "\\| ?${platform}\\b"; then
        fail_ "T8" "Task ${task//\\/} delta table missing platform row: $platform"
        return
      fi
    done
  done
  pass "T8: plan tasks 7.2/7.3/7.4/7.5 carry normative per-language/platform translation delta tables"
}

# ----------------------------------------------------------------------------
# Finding #11 — check-gate.sh cmd_repair must consult
# phase2_init.steps_completed and skip already-completed steps before
# falling back to a git-remote probe. Plan task 6.4 must reflect the
# same contract.
# ----------------------------------------------------------------------------
t11_cmd_repair_consults_steps_completed() {
  if [ ! -f "$CHECK_GATE" ]; then
    fail_ "T11" "check-gate.sh not found"
    return
  fi
  # cmd_repair body must read phase2_init.steps_completed.
  local body
  body=$(awk '/^cmd_repair\(\)/{flag=1} flag{print} /^}/{if(flag){flag=0; exit}}' "$CHECK_GATE")
  if [ -z "$body" ]; then
    fail_ "T11" "could not extract cmd_repair body"
    return
  fi
  if ! echo "$body" | grep -q 'phase2_init.steps_completed'; then
    fail_ "T11" "cmd_repair does not read phase2_init.steps_completed"
    return
  fi
  # It must check at least one of the four named steps so resume logic
  # actually fires for partial state.
  local matched=0
  for step in remote_repo_created pushed_initial branch_protection_configured branch_protection_verified; do
    if echo "$body" | grep -q "$step"; then
      matched=$((matched + 1))
    fi
  done
  if [ "$matched" -lt 3 ]; then
    fail_ "T11" "cmd_repair must reference ≥3 named steps for resume logic, found $matched"
    return
  fi
  # The git-remote probe must remain as a defensive fallback for
  # pre-fix projects (those without steps_completed populated).
  if ! echo "$body" | grep -q 'git remote get-url origin'; then
    fail_ "T11" "cmd_repair must still probe git remote as fallback for legacy projects"
    return
  fi
  pass "T11: cmd_repair consults steps_completed + retains git-remote fallback"
}

t11b_plan_task_6_4_documents_steps_completed_contract() {
  if [ ! -f "$PLAN" ]; then
    fail_ "T11b" "plan file not found"
    return
  fi
  local start body
  start=$(grep -nE '^### Task 6\.4' "$PLAN" | head -n1 | cut -d: -f1)
  if [ -z "$start" ]; then
    fail_ "T11b" "could not locate '### Task 6.4' in plan"
    return
  fi
  body=$(awk -v s="$start" 'NR>=s && NR<s+200' "$PLAN")
  if ! echo "$body" | grep -q 'phase2_init.steps_completed'; then
    fail_ "T11b" "plan task 6.4 must reference phase2_init.steps_completed"
    return
  fi
  if ! echo "$body" | grep -qiE 'skip|already.completed|resume'; then
    fail_ "T11b" "plan task 6.4 must describe skipping/resuming completed steps"
    return
  fi
  pass "T11b: plan task 6.4 documents the steps_completed resume contract"
}

# ----------------------------------------------------------------------------
# Integration test for finding #11 — exercise cmd_repair on a project whose
# steps_completed shows full completion. It must early-return success
# without attempting any host_* calls (which would otherwise fail with
# "host not loaded" since we have no real gh installed in the test env).
# ----------------------------------------------------------------------------
t11c_cmd_repair_skips_when_all_steps_complete() {
  local tmpdir; tmpdir=$(mktemp -d)
  (
    cd "$tmpdir"
    git init -q
    git remote add origin https://github.com/example/repo.git
    mkdir -p .claude
    cat > .claude/manifest.json <<'JSON'
{"host":"github","mode":"personal","remote_url":"https://github.com/example/repo.git"}
JSON
    cat > .claude/process-state.json <<'JSON'
{"phase2_init":{"steps_completed":["remote_repo_created","pushed_initial","branch_protection_configured","branch_protection_verified"]}}
JSON
  )
  local out rc=0
  out=$(cd "$tmpdir" && "$CHECK_GATE" --repair 2>&1) || rc=$?
  rm -rf "$tmpdir"
  if [ "$rc" -ne 0 ]; then
    fail_ "T11c" "expected cmd_repair to early-return success when all steps complete, got rc=$rc out=$out"
    return
  fi
  if ! echo "$out" | grep -qiE 'already|complete|nothing to repair'; then
    fail_ "T11c" "expected message indicating no work remained; got: $out"
    return
  fi
  pass "T11c: cmd_repair short-circuits when steps_completed shows full success"
}

echo "== tests/test-specs-plans-host-aware-quartet.sh =="
t1_spec_documents_category_6_tier_limited
t2_init_writes_incremental_steps_completed
t2b_plan_task_4_3_documents_named_steps
t8_plan_has_translation_delta_tables
t11_cmd_repair_consults_steps_completed
t11b_plan_task_6_4_documents_steps_completed_contract
t11c_cmd_repair_skips_when_all_steps_complete

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
