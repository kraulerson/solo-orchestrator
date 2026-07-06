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
PLAN="$REPO_ROOT/docs/superpowers/plans/archive/2026-04-22-host-aware-repo-gate-implementation.md"
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
  # PR #97 verifier follow-up: the helper was lifted from init.sh into
  # scripts/lib/phase2-state.sh so scripts/check-gate.sh::cmd_repair can
  # reuse it. Accept the definition in either location, but require init.sh
  # to source the lib (otherwise the call sites would reference an undefined
  # symbol).
  if [ "$call_sites" -gt 0 ]; then
    local helper_def_init helper_def_lib
    helper_def_init=$(grep -cE '^[[:space:]]*_record_phase2_step\(\)' "$INIT_SH" || true)
    case "$helper_def_init" in ''|*[!0-9]*) helper_def_init=0 ;; esac
    local lib="$REPO_ROOT/scripts/lib/phase2-state.sh"
    helper_def_lib=0
    if [ -f "$lib" ]; then
      helper_def_lib=$(grep -cE '^[[:space:]]*_record_phase2_step\(\)' "$lib" || true)
      case "$helper_def_lib" in ''|*[!0-9]*) helper_def_lib=0 ;; esac
    fi
    local total_defs=$((helper_def_init + helper_def_lib))
    if [ "$total_defs" -lt 1 ]; then
      fail_ "T2" "helper _record_phase2_step is called but not defined in init.sh or scripts/lib/phase2-state.sh"
      return
    fi
    # If the helper lives in the lib, init.sh MUST source it.
    if [ "$helper_def_init" -eq 0 ] && [ "$helper_def_lib" -gt 0 ]; then
      if ! grep -qE 'source[[:space:]]+.*scripts/lib/phase2-state\.sh' "$INIT_SH"; then
        fail_ "T2" "scripts/lib/phase2-state.sh defines _record_phase2_step but init.sh does not source it"
        return
      fi
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
      # POSIX-portable cell boundary: '| <lang>' followed by whitespace OR
      # the next table separator. Pre-fix this used GNU/BSD `\b`, which
      # other contributors' greps may not support.
      if ! echo "$body" | grep -qiE "\\| ?${lang}([[:space:]]|\\|)"; then
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
      # POSIX-portable cell boundary (see lang loop above).
      if ! echo "$body" | grep -qiE "\\| ?${platform}([[:space:]]|\\|)"; then
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
# steps_completed shows full completion. Pre-PR-#97-verifier-fix this used
# to assert an all-4-steps short-circuit, but that early return contradicted
# the "always re-run verify so the gate sees fresh state" contract (PR #97
# verifier Issue #3, option A). Post-fix: --repair still completes
# successfully when everything is recorded, but it runs verify against
# live state and re-records branch_protection_verified — the per-step skips
# guarantee no redundant create/push/configure API writes happen.
# ----------------------------------------------------------------------------
t11c_cmd_repair_runs_verify_when_all_steps_complete() {
  local tmpdir; tmpdir=$(mktemp -d)
  local mockdir="$tmpdir/bin"
  mkdir -p "$mockdir"
  # Mock gh: succeed on auth/version + protection GET (return personal-
  # mode-compliant rules so host_verify_protection passes).
  cat > "$mockdir/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*|*"--version"*) exit 0 ;;
  *"api "*protection*)
    printf '%s\n' '{"required_status_checks":null,"enforce_admins":{"enabled":true},"required_pull_request_reviews":null,"restrictions":null,"allow_force_pushes":{"enabled":false},"allow_deletions":{"enabled":false}}'
    exit 0
    ;;
  *)
    echo "mock gh: unhandled: $*" >&2; exit 127 ;;
esac
STUB
  chmod +x "$mockdir/gh"

  (
    cd "$tmpdir"
    git init -q
    git remote add origin "https://github.com/example/repo.git"
    mkdir -p .claude scripts/lib scripts/host-drivers
    # Symlink real scripts so host_load_driver finds them in this tmp
    # project (mirrors production layout — init.sh scaffolds scripts/
    # into the project).
    ln -s "$REPO_ROOT/scripts/lib/host.sh"            scripts/lib/host.sh
    ln -s "$REPO_ROOT/scripts/lib/helpers.sh"         scripts/lib/helpers.sh
    ln -s "$REPO_ROOT/scripts/lib/phase2-state.sh"    scripts/lib/phase2-state.sh
    ln -s "$REPO_ROOT/scripts/host-drivers/github.sh" scripts/host-drivers/github.sh
    cat > .claude/manifest.json <<'JSON'
{"host":"github","mode":"personal","remote_url":"https://github.com/example/repo.git"}
JSON
    cat > .claude/process-state.json <<'JSON'
{"phase2_init":{"steps_completed":["remote_repo_created","pushed_initial","branch_protection_configured","branch_protection_verified"],"attestations":{}}}
JSON
  )
  local out rc=0
  out=$(cd "$tmpdir" && PATH="$mockdir:$PATH" "$CHECK_GATE" --repair 2>&1) || rc=$?
  rm -rf "$tmpdir"
  if [ "$rc" -ne 0 ]; then
    fail_ "T11c" "expected cmd_repair to succeed when all steps complete, got rc=$rc out=$out"
    return
  fi
  # All four per-step "Skipping ... already recorded" messages must appear —
  # this confirms the per-step skips fired (no redundant create/push/
  # configure API writes) while verify still ran.
  for msg in "Skipping create" "Skipping push" "Skipping configure" "Repair complete"; do
    if ! echo "$out" | grep -qF "$msg"; then
      fail_ "T11c" "expected output to contain '$msg'; got: $out"
      return
    fi
  done
  pass "T11c: cmd_repair skips create/push/configure when recorded + still re-runs verify (option A)"
}

# ----------------------------------------------------------------------------
# Verifier follow-up to PR #97 (cmd_repair-write-back) — the original t11c
# only exercised the all-4-preseeded short-circuit. The actual resume path
# (partial steps_completed → --repair runs missing steps → state file MUST
# now reflect the completed steps) was never integration-tested. Without
# write-back, the state file becomes a lying source of truth on every
# successful repair: re-runs hit the host API even though there's nothing
# left to do, and any future consumer that reads steps_completed sees
# stale data.
#
# Fixture mirrors e2e-init.test.sh::T5 (protect-fail) — create + push
# succeeded, configure failed — so steps_completed is ["remote_repo_created",
# "pushed_initial"] on entry. After --repair drives configure + verify
# through mocked-gh success, steps_completed MUST include all four.
# ----------------------------------------------------------------------------
t11d_cmd_repair_writes_back_after_successful_resume() {
  local tmpdir; tmpdir=$(mktemp -d)
  local mockdir="$tmpdir/bin"
  mkdir -p "$mockdir"
  # Mock gh: respond OK to auth/version, succeed on protection PUT, return
  # a personal-mode-compliant protection GET so host_verify_protection
  # passes. The create branch is bypassed by the git-remote probe in
  # cmd_repair (origin is already configured below).
  cat > "$mockdir/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"auth status"*|*"--version"*) exit 0 ;;
  *"api -X PUT "*protection*) exit 0 ;;
  *"api "*protection*)
    printf '%s\n' '{"required_status_checks":null,"enforce_admins":{"enabled":true},"required_pull_request_reviews":null,"restrictions":null,"allow_force_pushes":{"enabled":false},"allow_deletions":{"enabled":false}}'
    exit 0
    ;;
  *)
    echo "mock gh: unhandled: $*" >&2; exit 127 ;;
esac
STUB
  chmod +x "$mockdir/gh"

  (
    cd "$tmpdir"
    git init -q
    git remote add origin "https://github.com/example/repo.git"
    mkdir -p .claude scripts/lib scripts/host-drivers
    # The host dispatcher (scripts/lib/host.sh::host_load_driver) loads
    # drivers from _host_repo_root, which is the PROJECT's git root —
    # mirroring the production layout where init.sh scaffolds scripts/
    # into the new project. Symlink the framework's scripts so cmd_repair
    # can source the real host.sh + github driver in this tmp project.
    ln -s "$REPO_ROOT/scripts/lib/host.sh"            scripts/lib/host.sh
    ln -s "$REPO_ROOT/scripts/lib/helpers.sh"         scripts/lib/helpers.sh
    ln -s "$REPO_ROOT/scripts/lib/phase2-state.sh"    scripts/lib/phase2-state.sh
    ln -s "$REPO_ROOT/scripts/host-drivers/github.sh" scripts/host-drivers/github.sh
    cat > .claude/manifest.json <<'JSON'
{"host":"github","mode":"personal","remote_url":"https://github.com/example/repo.git"}
JSON
    # Partial-fail fixture: configure failed, so only the first 2 steps
    # are recorded. --repair must run configure + verify AND write both
    # newly-completed steps back to steps_completed. The host_push_initial
    # call inside --repair is short-circuited by the steps_completed
    # check, so no real `git push` happens.
    cat > .claude/process-state.json <<'JSON'
{"phase2_init":{"steps_completed":["remote_repo_created","pushed_initial"],"attestations":{}}}
JSON
  )

  local out rc=0
  out=$(cd "$tmpdir" && PATH="$mockdir:$PATH" "$CHECK_GATE" --repair 2>&1) || rc=$?

  # Pull the post-repair state before teardown so failure messages can cite it.
  local post_steps
  post_steps=$(jq -r '.phase2_init.steps_completed | sort | join(",")' \
    "$tmpdir/.claude/process-state.json" 2>/dev/null || echo "<read-failed>")
  rm -rf "$tmpdir"

  if [ "$rc" -ne 0 ]; then
    fail_ "T11d" "cmd_repair returned non-zero rc=$rc post_steps=$post_steps out=$out"
    return
  fi
  # All four steps MUST now be present; the bug was that configure/verify
  # succeeded inside cmd_repair but no _record_phase2_step call happened,
  # so the state file silently stayed at length=2.
  local expected="branch_protection_configured,branch_protection_verified,pushed_initial,remote_repo_created"
  if [ "$post_steps" != "$expected" ]; then
    fail_ "T11d" "expected steps_completed=$expected after resume, got $post_steps (out: $out)"
    return
  fi
  pass "T11d: cmd_repair writes back steps_completed after successful resume (partial-fail → all 4 present)"
}

echo "== tests/test-specs-plans-host-aware-quartet.sh =="
t1_spec_documents_category_6_tier_limited
t2_init_writes_incremental_steps_completed
t2b_plan_task_4_3_documents_named_steps
t8_plan_has_translation_delta_tables
t11_cmd_repair_consults_steps_completed
t11b_plan_task_6_4_documents_steps_completed_contract
t11c_cmd_repair_runs_verify_when_all_steps_complete
t11d_cmd_repair_writes_back_after_successful_resume

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
