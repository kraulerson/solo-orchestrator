#!/usr/bin/env bash
# tests/test-gitlab-ci-status-stderr-approvals.sh — regression suite for
# three GitLab driver S3 audit findings remediated in PR
# fix/host-gitlab-ci-status-stderr-approvals:
#
#   code-host-gitlab-2  Org mode must enforce CI pipeline-success gate
#                       (PUT projects/:id only_allow_merge_if_pipeline_succeeds)
#                       and host_verify_protection must fail when the flag
#                       is false — parity with github.sh required_status_checks.
#
#   code-host-gitlab-3  Both glab api calls in host_configure_protection
#                       must capture stderr and surface the upstream
#                       message on failure (mirroring github.sh BL-002
#                       pattern). Otherwise operators see only a generic
#                       "failed to configure protection" with no detail.
#
#   code-host-gitlab-8  Premium-only failure on projects/:id/approvals
#                       (gitlab.com Free org-mode) must be detected and
#                       returned as a distinct exit code (4) with a
#                       BL-032-style remediation message documenting the
#                       attestation escape hatch.
#
# TDD discipline: this file was written BEFORE the driver change and
# initially failed RED against the baseline gitlab.sh. After the driver
# was updated, all scenarios pass GREEN.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRIVER="$REPO_ROOT/scripts/host-drivers/gitlab.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Build a tempdir with a fake glab on PATH. The fake is driven by env vars
# the caller sets before invoking the driver:
#   GLAB_POST_EXIT       — exit code for `glab api -X POST .../protected_branches`
#   GLAB_POST_STDERR     — stderr emitted on the protected_branches POST
#   GLAB_PUT_APPR_EXIT   — exit code for `glab api -X PUT .../approvals`
#   GLAB_PUT_APPR_STDERR — stderr emitted on the approvals PUT
#   GLAB_PUT_PROJ_EXIT   — exit code for `glab api -X PUT projects/:id` (settings)
#   GLAB_PUT_PROJ_STDERR — stderr emitted on the project-settings PUT
#   GLAB_GET_PROJ_BODY   — stdout (JSON) returned by `glab api projects/:id`
#                          when host_verify_protection inspects settings
#   GLAB_GET_BRANCH_BODY — stdout (JSON) returned by
#                          `glab api projects/:id/protected_branches/main`
#   GLAB_GET_APPR_BODY   — stdout (JSON) returned by
#                          `glab api projects/:id/approvals`
setup_with_fake_glab() {
  TMPDIR_T=$(mktemp -d)
  mkdir -p "$TMPDIR_T/bin"
  cat > "$TMPDIR_T/bin/glab" <<'GLAB_EOF'
#!/usr/bin/env bash
# Fake glab — pattern-match the invocation and emit the canned response.
# Drain stdin so piped --input payloads don't SIGPIPE. BL-152: capture the
# payload (instead of discarding) so, when GLAB_ARGV_LOG is set, we can
# record argv + payload and assert on the exact call shape (which
# endpoint/method the driver invoked). Recording is off unless GLAB_ARGV_LOG
# is set, so the other scenarios are unaffected.
_glab_stdin=""
if [ ! -t 0 ]; then _glab_stdin="$(cat 2>/dev/null || true)"; fi
if [ -n "${GLAB_ARGV_LOG:-}" ]; then printf '%s\t%s\n' "$*" "$_glab_stdin" >> "$GLAB_ARGV_LOG"; fi

case "$*" in
  *"-X DELETE"*"/protected_branches/"*)
    exit 0  # idempotent delete always "succeeds"
    ;;
  *"-X POST"*"/protected_branches"*)
    [ -n "${GLAB_POST_STDERR:-}" ] && printf '%s\n' "$GLAB_POST_STDERR" >&2
    exit "${GLAB_POST_EXIT:-0}"
    ;;
  *"-X POST"*"/approval_rules"*)
    # BL-152: the required-approvals call is now POST projects/:id/approval_rules
    # (was the deprecated PUT projects/:id/approvals). The GLAB_PUT_APPR_*
    # knobs keep their names (internal test knobs) and drive this arm.
    [ -n "${GLAB_PUT_APPR_STDERR:-}" ] && printf '%s\n' "$GLAB_PUT_APPR_STDERR" >&2
    exit "${GLAB_PUT_APPR_EXIT:-0}"
    ;;
  *"-X POST"*"/approvals"*)
    # BL-152: reset_approvals_on_push config (POST projects/:id/approvals —
    # the non-rule config endpoint). Must be matched AFTER the approval_rules
    # arm above (approval_rules never contains the substring "/approvals").
    [ -n "${GLAB_POST_RESET_STDERR:-}" ] && printf '%s\n' "$GLAB_POST_RESET_STDERR" >&2
    exit "${GLAB_POST_RESET_EXIT:-0}"
    ;;
  *"-X PUT projects/"*)
    # PUT projects/:id  (sets only_allow_merge_if_pipeline_succeeds etc.)
    [ -n "${GLAB_PUT_PROJ_STDERR:-}" ] && printf '%s\n' "$GLAB_PUT_PROJ_STDERR" >&2
    exit "${GLAB_PUT_PROJ_EXIT:-0}"
    ;;
  *"-X GET projects/"*)
    # Explicit GET projects/:id — settings payload for verify
    printf '%s' "${GLAB_GET_PROJ_BODY:-{\}}"
    exit 0
    ;;
  *"projects/"*"/protected_branches/"*)
    printf '%s' "${GLAB_GET_BRANCH_BODY:-{\}}"
    exit 0
    ;;
  *"projects/"*"/approval_rules"*)
    # BL-152: verify now reads the approval-rules LIST (a JSON array) instead
    # of the deprecated GET .../approvals + approvals_before_merge scalar.
    printf '%s' "${GLAB_GET_APPR_BODY:-[]}"
    exit 0
    ;;
  api\ projects/*)
    # GET projects/:id (bare) — settings payload for verify (fallback)
    printf '%s' "${GLAB_GET_PROJ_BODY:-{\}}"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
GLAB_EOF
  chmod +x "$TMPDIR_T/bin/glab"
  (
    cd "$TMPDIR_T"
    git init -q
    git config user.email "test@test.local"
    git config user.name "test"
    git remote add origin https://gitlab.com/org/repo.git
  )
}
teardown_project() { rm -rf "$TMPDIR_T"; unset GLAB_POST_EXIT GLAB_POST_STDERR \
  GLAB_PUT_APPR_EXIT GLAB_PUT_APPR_STDERR GLAB_POST_RESET_EXIT GLAB_POST_RESET_STDERR \
  GLAB_PUT_PROJ_EXIT GLAB_PUT_PROJ_STDERR \
  GLAB_GET_PROJ_BODY GLAB_GET_BRANCH_BODY GLAB_GET_APPR_BODY GLAB_ARGV_LOG; }

run_configure() {
  local mode="$1"
  (
    cd "$TMPDIR_T"
    PATH="$TMPDIR_T/bin:$PATH"
    export GLAB_POST_EXIT GLAB_POST_STDERR GLAB_PUT_APPR_EXIT GLAB_PUT_APPR_STDERR \
           GLAB_PUT_PROJ_EXIT GLAB_PUT_PROJ_STDERR
    set +e
    # shellcheck disable=SC1090
    source "$DRIVER"
    out=$(host_configure_protection main "$mode" 2>&1)
    rc=$?
    printf '%s|%s' "$rc" "$(printf '%s' "$out" | tr '\n' ' ')"
  )
}

run_verify() {
  local mode="$1"
  (
    cd "$TMPDIR_T"
    PATH="$TMPDIR_T/bin:$PATH"
    export GLAB_GET_PROJ_BODY GLAB_GET_BRANCH_BODY GLAB_GET_APPR_BODY
    set +e
    # shellcheck disable=SC1090
    source "$DRIVER"
    out=$(host_verify_protection main "$mode" 2>&1)
    rc=$?
    printf '%s|%s' "$rc" "$(printf '%s' "$out" | tr '\n' ' ')"
  )
}

# ─── code-host-gitlab-2 ──────────────────────────────────────────────────────

t1_org_configure_sets_pipeline_succeeds() {
  # host_configure_protection in org mode must call PUT projects/:id with
  # only_allow_merge_if_pipeline_succeeds=true (in addition to the existing
  # protected_branches POST + approvals PUT). We instrument the fake glab to
  # FAIL on the project-settings PUT specifically and assert that the driver
  # returns a non-zero exit code attributable to that call — proving the call
  # was actually attempted.
  setup_with_fake_glab
  export GLAB_POST_EXIT=0 GLAB_PUT_APPR_EXIT=0
  export GLAB_PUT_PROJ_EXIT=1 GLAB_PUT_PROJ_STDERR='HTTP 500: simulated failure'
  local out; out=$(run_configure org)
  local rc="${out%%|*}" stderr="${out#*|}"
  if [ "$rc" = "0" ]; then
    fail_ "T1" "expected non-zero rc when project-settings PUT fails (proves driver called it); got rc=0 out=$stderr"
    teardown_project; return
  fi
  if [[ "$stderr" != *"pipeline"* ]] && [[ "$stderr" != *"settings"* ]]; then
    fail_ "T1" "expected error mentioning pipeline/settings; stderr=$stderr"
    teardown_project; return
  fi
  pass "T1: org configure invokes project-settings PUT (pipeline-succeeds gate)"
  teardown_project
}

t2_org_verify_fails_when_pipeline_gate_off() {
  # host_verify_protection in org mode must GET projects/:id and assert
  # only_allow_merge_if_pipeline_succeeds=true. When the API reports false,
  # the gate must fail with the parity error message.
  setup_with_fake_glab
  export GLAB_GET_BRANCH_BODY='{"name":"main","allow_force_push":false,"push_access_levels":[{"access_level":0}]}'
  export GLAB_GET_APPR_BODY='[{"approvals_required":1}]'
  export GLAB_GET_PROJ_BODY='{"only_allow_merge_if_pipeline_succeeds":false}'
  local out; out=$(run_verify org)
  local rc="${out%%|*}" stderr="${out#*|}"
  if [ "$rc" = "0" ]; then
    fail_ "T2" "expected verify to fail when pipeline gate off; got rc=0 out=$stderr"
    teardown_project; return
  fi
  if [[ "$stderr" != *"pipeline"* ]]; then
    fail_ "T2" "expected stderr to mention pipeline gate; stderr=$stderr"
    teardown_project; return
  fi
  pass "T2: org verify fails with pipeline-gate parity message when API reports false"
  teardown_project
}

t3_org_verify_passes_when_pipeline_gate_on() {
  setup_with_fake_glab
  export GLAB_GET_BRANCH_BODY='{"name":"main","allow_force_push":false,"push_access_levels":[{"access_level":0}]}'
  export GLAB_GET_APPR_BODY='[{"approvals_required":1}]'
  export GLAB_GET_PROJ_BODY='{"only_allow_merge_if_pipeline_succeeds":true}'
  local out; out=$(run_verify org)
  local rc="${out%%|*}" stderr="${out#*|}"
  if [ "$rc" != "0" ]; then
    fail_ "T3" "expected verify pass; got rc=$rc out=$stderr"
    teardown_project; return
  fi
  pass "T3: org verify passes when pipeline gate enabled"
  teardown_project
}

# ─── code-host-gitlab-3 ──────────────────────────────────────────────────────

t4_protected_branches_post_surfaces_stderr() {
  # When the protected_branches POST fails, the driver must capture and
  # surface the upstream glab error message rather than swallowing it
  # under a generic "failed to configure protection".
  setup_with_fake_glab
  export GLAB_POST_EXIT=1
  export GLAB_POST_STDERR='HTTP 403: insufficient privileges to write to projects/org%2Frepo/protected_branches'
  local out; out=$(run_configure personal)
  local rc="${out%%|*}" stderr="${out#*|}"
  if [ "$rc" != "2" ]; then
    fail_ "T4" "expected exit 2 for generic POST failure; got rc=$rc stderr=$stderr"
    teardown_project; return
  fi
  if [[ "$stderr" != *"insufficient privileges"* ]]; then
    fail_ "T4" "expected upstream stderr to be surfaced; stderr=$stderr"
    teardown_project; return
  fi
  pass "T4: protected_branches POST failure surfaces upstream glab stderr"
  teardown_project
}

t5_approvals_put_generic_failure_surfaces_stderr() {
  setup_with_fake_glab
  export GLAB_POST_EXIT=0
  export GLAB_PUT_APPR_EXIT=1
  export GLAB_PUT_APPR_STDERR='HTTP 500: internal server error on approvals endpoint'
  local out; out=$(run_configure org)
  local rc="${out%%|*}" stderr="${out#*|}"
  if [ "$rc" != "3" ]; then
    fail_ "T5" "expected exit 3 for generic approvals failure; got rc=$rc stderr=$stderr"
    teardown_project; return
  fi
  if [[ "$stderr" != *"internal server error"* ]]; then
    fail_ "T5" "expected upstream stderr to be surfaced; stderr=$stderr"
    teardown_project; return
  fi
  pass "T5: approvals PUT generic failure surfaces upstream glab stderr"
  teardown_project
}

# ─── code-host-gitlab-8 ──────────────────────────────────────────────────────

t6_approvals_premium_only_returns_distinct_code() {
  # gitlab.com Free returns a Premium-feature-not-available error on the
  # approvals PUT. The driver must detect this pattern and return exit
  # code 4 (distinct from 3=generic-approvals-failure), with a remediation
  # message naming the BL-032 / Premium tier limitation and the
  # attestation escape-hatch path.
  setup_with_fake_glab
  export GLAB_POST_EXIT=0
  export GLAB_PUT_APPR_EXIT=1
  export GLAB_PUT_APPR_STDERR='HTTP 403: 403 Forbidden — This feature is not available on your plan. Upgrade to Premium to enable required approvals.'
  local out; out=$(run_configure org)
  local rc="${out%%|*}" stderr="${out#*|}"
  if [ "$rc" != "4" ]; then
    fail_ "T6" "expected exit 4 for Premium-only approvals; got rc=$rc stderr=$stderr"
    teardown_project; return
  fi
  if [[ "$stderr" != *"Premium"* ]] && [[ "$stderr" != *"premium"* ]]; then
    fail_ "T6" "expected remediation mentioning Premium tier; stderr=$stderr"
    teardown_project; return
  fi
  if [[ "$stderr" != *"BL-032"* ]] && [[ "$stderr" != *"attested"* ]]; then
    fail_ "T6" "expected remediation mentioning BL-032 / attestation escape hatch; stderr=$stderr"
    teardown_project; return
  fi
  pass "T6: Premium-only approvals failure → exit 4 + BL-032 remediation"
  teardown_project
}

t7_personal_mode_unchanged_on_success() {
  # Sanity: personal mode (no approvals PUT, no project-settings PUT)
  # still returns 0 on a clean run. Guards against the refactor breaking
  # the simple happy path.
  setup_with_fake_glab
  export GLAB_POST_EXIT=0
  local out; out=$(run_configure personal)
  local rc="${out%%|*}" stderr="${out#*|}"
  if [ "$rc" != "0" ]; then
    fail_ "T7" "expected exit 0 on personal success; got rc=$rc stderr=$stderr"
    teardown_project; return
  fi
  pass "T7: personal mode happy path returns 0"
  teardown_project
}

# ─── backlog-doc parity check ────────────────────────────────────────────────

t8_backlog_has_bl032_entry() {
  # code-host-gitlab-8 requires a BL-032 entry in the backlog documenting
  # the gitlab.com Free org-mode approvals graceful-degradation gap,
  # mirroring BL-002's GitHub free-tier carve-out.
  local backlog="$REPO_ROOT/solo-orchestrator-backlog.md"
  if ! grep -qE '^## BL-032:' "$backlog"; then
    fail_ "T8" "expected BL-032 header in $backlog"
    return
  fi
  if ! grep -q -i 'gitlab' "$backlog"; then
    fail_ "T8" "expected BL-032 entry to mention GitLab"
    return
  fi
  pass "T8: BL-032 entry exists in backlog (GitLab BL-002 analog)"
}

# ─── BL-152: current approval-rules API (not the deprecated approvals PUT) ────

t9_org_configure_uses_approval_rules_post() {
  # BL-152: org mode must set required approvals via the CURRENT API —
  # POST projects/:id/approval_rules with approvals_required — not the
  # deprecated PUT projects/:id/approvals + approvals_before_merge (the
  # field is scheduled for removal in GitLab REST API v5). The fake glab
  # records every invocation's argv + payload to GLAB_ARGV_LOG; we assert
  # on the recorded call shape rather than on an exit code, so this pins
  # the exact endpoint/method/field the driver emits.
  setup_with_fake_glab
  export GLAB_POST_EXIT=0 GLAB_PUT_APPR_EXIT=0 GLAB_PUT_PROJ_EXIT=0
  local log="$TMPDIR_T/glab_calls.log"
  : > "$log"
  (
    cd "$TMPDIR_T"
    PATH="$TMPDIR_T/bin:$PATH"
    export GLAB_POST_EXIT GLAB_PUT_APPR_EXIT GLAB_PUT_PROJ_EXIT
    export GLAB_ARGV_LOG="$log"
    set +e
    # shellcheck disable=SC1090
    source "$DRIVER"
    host_configure_protection main org >/dev/null 2>&1
  )
  # The required-approvals call must be a POST to .../approval_rules.
  if ! grep 'approval_rules' "$log" | grep -q -- '-X POST'; then
    fail_ "T9" "expected a 'POST projects/:id/approval_rules' invocation; log=$(tr '\n' ';' < "$log")"
    teardown_project; return
  fi
  # ...carrying approvals_required in its payload.
  if ! grep 'approval_rules' "$log" | grep -q 'approvals_required'; then
    fail_ "T9" "approval_rules call missing approvals_required payload; log=$(grep approval_rules "$log")"
    teardown_project; return
  fi
  # ...and must NOT emit the deprecated approvals_before_merge field anywhere.
  if grep -q 'approvals_before_merge' "$log"; then
    fail_ "T9" "driver still emits deprecated approvals_before_merge; log=$(grep approvals_before_merge "$log")"
    teardown_project; return
  fi
  pass "T9: org configure uses POST projects/:id/approval_rules with approvals_required (BL-152)"
  teardown_project
}

t10_org_verify_reads_approval_rules() {
  # BL-152 follow-up: host_verify_protection must read the required-approval
  # count from the CURRENT API — GET projects/:id/approval_rules (a JSON
  # array; any rule with approvals_required >= 1 satisfies it) — not the
  # deprecated GET .../approvals + approvals_before_merge scalar (which no
  # longer reflects approval_rules and would false-fail on Premium today).
  setup_with_fake_glab
  export GLAB_GET_BRANCH_BODY='{"name":"main","allow_force_push":false,"push_access_levels":[{"access_level":0}]}'
  export GLAB_GET_APPR_BODY='[{"name":"Require approval","approvals_required":1}]'
  export GLAB_GET_PROJ_BODY='{"only_allow_merge_if_pipeline_succeeds":true}'
  local log="$TMPDIR_T/glab_calls.log"; : > "$log"
  (
    cd "$TMPDIR_T"
    PATH="$TMPDIR_T/bin:$PATH"
    export GLAB_GET_BRANCH_BODY GLAB_GET_APPR_BODY GLAB_GET_PROJ_BODY
    export GLAB_ARGV_LOG="$log"
    set +e
    # shellcheck disable=SC1090
    source "$DRIVER"
    host_verify_protection main org >/dev/null 2>&1
  )
  # Verify must GET the approval-rules list.
  if ! grep -qF 'approval_rules' "$log"; then
    fail_ "T10" "expected verify to GET projects/:id/approval_rules; log=$(tr '\n' ';' < "$log")"
    teardown_project; return
  fi
  # ...and must NOT still hit the deprecated GET projects/:id/approvals scalar.
  if grep -qF 'projects/org%2Frepo/approvals' "$log"; then
    fail_ "T10" "verify still calls the deprecated GET projects/:id/approvals; log=$(grep -F approvals "$log")"
    teardown_project; return
  fi
  pass "T10: org verify reads approval_rules (approvals_required), not the deprecated approvals_before_merge (BL-152)"
  teardown_project
}

t11_org_configure_sets_reset_approvals_on_push() {
  # BL-152 follow-up: reset_approvals_on_push rode on the old /approvals PUT.
  # It belongs to the /approvals CONFIG endpoint (not approval_rules), so it
  # is re-applied via a dedicated POST projects/:id/approvals call after the
  # approval_rules POST succeeds.
  setup_with_fake_glab
  export GLAB_POST_EXIT=0 GLAB_PUT_APPR_EXIT=0 GLAB_POST_RESET_EXIT=0 GLAB_PUT_PROJ_EXIT=0
  local log="$TMPDIR_T/glab_calls.log"; : > "$log"
  (
    cd "$TMPDIR_T"
    PATH="$TMPDIR_T/bin:$PATH"
    export GLAB_POST_EXIT GLAB_PUT_APPR_EXIT GLAB_POST_RESET_EXIT GLAB_PUT_PROJ_EXIT
    export GLAB_ARGV_LOG="$log"
    set +e
    # shellcheck disable=SC1090
    source "$DRIVER"
    host_configure_protection main org >/dev/null 2>&1
  )
  # There must be a POST carrying reset_approvals_on_push...
  if ! grep 'reset_approvals_on_push' "$log" | grep -q -- '-X POST'; then
    fail_ "T11" "expected a POST carrying reset_approvals_on_push; log=$(tr '\n' ';' < "$log")"
    teardown_project; return
  fi
  # ...aimed at the /approvals config endpoint, NOT approval_rules.
  if ! grep 'reset_approvals_on_push' "$log" | grep -qF '/approvals'; then
    fail_ "T11" "reset_approvals_on_push not sent to the /approvals config endpoint; log=$(grep -F reset_approvals_on_push "$log")"
    teardown_project; return
  fi
  if grep 'reset_approvals_on_push' "$log" | grep -qF 'approval_rules'; then
    fail_ "T11" "reset_approvals_on_push wrongly sent to approval_rules; log=$(grep -F reset_approvals_on_push "$log")"
    teardown_project; return
  fi
  pass "T11: org configure re-applies reset_approvals_on_push via POST /approvals (BL-152)"
  teardown_project
}

echo "== tests/test-gitlab-ci-status-stderr-approvals.sh =="
t1_org_configure_sets_pipeline_succeeds
t2_org_verify_fails_when_pipeline_gate_off
t3_org_verify_passes_when_pipeline_gate_on
t4_protected_branches_post_surfaces_stderr
t5_approvals_put_generic_failure_surfaces_stderr
t6_approvals_premium_only_returns_distinct_code
t7_personal_mode_unchanged_on_success
t8_backlog_has_bl032_entry
t9_org_configure_uses_approval_rules_post
t10_org_verify_reads_approval_rules
t11_org_configure_sets_reset_approvals_on_push

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
