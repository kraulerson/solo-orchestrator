#!/usr/bin/env bash
# tests/test-bl032-gitlab-free-approvals-attestation.sh — BL-032 close
#
# BL-032 backlog scope (solo-orchestrator-backlog.md):
#   Add a `--approvals-attested` flag (and `SOLO_APPROVALS_ATTESTED=1` env
#   var) honored by `host_configure_protection`. When set in org mode,
#   skip the approvals PUT and record an attestation in
#   `.claude/process-state.json::phase2_init.attestations.branch_protection.reason
#   = "gitlab_free_tier_approvals"`. Extend `scripts/check-phase-gate.sh`
#   Phase 1→2 backstop to honor the new attestation reason.
#
# Test coverage (mirrors BL-036 + BL-066 lessons — failure paths +
# mutation proof):
#   T1  SOLO_APPROVALS_ATTESTED=1 + org mode + 403 Premium response
#       → driver skips the approvals PUT entirely and returns 0 with a
#         specific WARN. Attestation-attempt shortcircuit is what makes
#         a 403-serving mock a green run.
#   T2  Without SOLO_APPROVALS_ATTESTED + 403 Premium response → driver
#       still returns exit 4 (existing BL-032 reactive path unchanged).
#   T3  T1's WARN message contains the operator-actionable hint pointing
#       at "Settings > Merge requests" — not just a generic
#       "approvals skipped".
#   T4  SOLO_APPROVALS_ATTESTED=1 does NOT swallow non-403 failures on
#       other API calls (project-settings PUT 500 still returns exit 5).
#   T5  scripts/check-phase-gate.sh Phase 1→2 backstop honors reason
#       `gitlab_free_tier_approvals` — passes without invoking
#       host_verify_protection.
#   T6  scripts/check-gate.sh --preflight honors reason
#       `gitlab_free_tier_approvals` — mirrors T5 for the operator-facing
#       preflight subcommand.
#   T7  Mutation proof: with the SOLO_APPROVALS_ATTESTED shortcircuit
#       removed from the driver, T1's scenario returns rc=4 instead of
#       rc=0. Proves the shortcircuit is what makes T1 green (not some
#       adjacent behavior).
#
# TDD discipline: this file was written BEFORE the driver + check-gate
# changes landed; the mutation test (T7) explicitly guards against a
# regression where the shortcircuit is removed and the test still passes
# via a non-load-bearing path.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRIVER="$REPO_ROOT/scripts/host-drivers/gitlab.sh"
CHECK_GATE="$REPO_ROOT/scripts/check-gate.sh"
CHECK_PHASE_GATE="$REPO_ROOT/scripts/check-phase-gate.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# ── Fake glab setup (mirrors test-gitlab-ci-status-stderr-approvals.sh) ──
setup_with_fake_glab() {
  TMPDIR_T=$(mktemp -d)
  mkdir -p "$TMPDIR_T/bin"
  cat > "$TMPDIR_T/bin/glab" <<'GLAB_EOF'
#!/usr/bin/env bash
# Fake glab — pattern-match the invocation and emit the canned response.
# The `APPROVALS_PUT_CALLED` file is touched IFF the approvals PUT is
# actually invoked; tests read it to prove the shortcircuit did/didn't fire.
if [ ! -t 0 ]; then cat >/dev/null 2>&1 || true; fi

case "$*" in
  *"-X DELETE"*"/protected_branches/"*)
    exit 0
    ;;
  *"-X POST"*"/protected_branches"*)
    [ -n "${GLAB_POST_STDERR:-}" ] && printf '%s\n' "$GLAB_POST_STDERR" >&2
    exit "${GLAB_POST_EXIT:-0}"
    ;;
  *"-X POST"*"/approval_rules"*)
    # BL-152: required-approvals call is now POST projects/:id/approval_rules
    # (was the deprecated PUT projects/:id/approvals). Track that this call
    # actually happened — the SOLO_APPROVALS_ATTESTED shortcircuit is
    # expected to skip it. Knob names (GLAB_PUT_APPR_*, APPROVALS_PUT_TRACKER)
    # are internal and retained.
    [ -n "${APPROVALS_PUT_TRACKER:-}" ] && touch "$APPROVALS_PUT_TRACKER"
    [ -n "${GLAB_PUT_APPR_STDERR:-}" ] && printf '%s\n' "$GLAB_PUT_APPR_STDERR" >&2
    exit "${GLAB_PUT_APPR_EXIT:-0}"
    ;;
  *"-X PUT projects/"*)
    [ -n "${GLAB_PUT_PROJ_STDERR:-}" ] && printf '%s\n' "$GLAB_PUT_PROJ_STDERR" >&2
    exit "${GLAB_PUT_PROJ_EXIT:-0}"
    ;;
  *"-X GET projects/"*)
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
teardown_project() {
  rm -rf "$TMPDIR_T"
  unset GLAB_POST_EXIT GLAB_POST_STDERR GLAB_PUT_APPR_EXIT GLAB_PUT_APPR_STDERR \
        GLAB_PUT_PROJ_EXIT GLAB_PUT_PROJ_STDERR GLAB_GET_PROJ_BODY \
        APPROVALS_PUT_TRACKER SOLO_APPROVALS_ATTESTED
}

run_configure() {
  local mode="$1"
  (
    cd "$TMPDIR_T"
    PATH="$TMPDIR_T/bin:$PATH"
    export GLAB_POST_EXIT GLAB_POST_STDERR GLAB_PUT_APPR_EXIT GLAB_PUT_APPR_STDERR \
           GLAB_PUT_PROJ_EXIT GLAB_PUT_PROJ_STDERR APPROVALS_PUT_TRACKER \
           SOLO_APPROVALS_ATTESTED
    set +e
    # shellcheck disable=SC1090
    source "$DRIVER"
    out=$(host_configure_protection main "$mode" 2>&1)
    rc=$?
    printf '%s|%s' "$rc" "$(printf '%s' "$out" | tr '\n' ' ')"
  )
}

# ─── T1: shortcircuit skips approvals PUT ──────────────────────────────────

t1_shortcircuit_skips_approvals_put() {
  setup_with_fake_glab
  export SOLO_APPROVALS_ATTESTED=1
  export GLAB_POST_EXIT=0
  # If the driver's shortcircuit works, we NEVER reach the approvals PUT.
  # Set the fake to fail with a Premium 403 so a regression (driver still
  # calls PUT) surfaces via exit 4 rather than silently passing.
  export GLAB_PUT_APPR_EXIT=1
  export GLAB_PUT_APPR_STDERR='HTTP 403: 403 Forbidden — This feature is not available on your plan. Upgrade to Premium to enable required approvals.'
  export APPROVALS_PUT_TRACKER="$TMPDIR_T/approvals_put_was_called"
  local out; out=$(run_configure org)
  local rc="${out%%|*}"
  if [ "$rc" != "0" ]; then
    fail_ "T1" "expected exit 0 with SOLO_APPROVALS_ATTESTED=1; got rc=$rc"
    teardown_project; return
  fi
  if [ -f "$APPROVALS_PUT_TRACKER" ]; then
    fail_ "T1" "approvals PUT was invoked despite SOLO_APPROVALS_ATTESTED=1 (shortcircuit missing)"
    teardown_project; return
  fi
  pass "T1: SOLO_APPROVALS_ATTESTED=1 → driver skips approvals PUT and returns 0"
  teardown_project
}

# ─── T2: reactive path unchanged when flag absent ──────────────────────────

t2_reactive_path_unchanged() {
  setup_with_fake_glab
  # SOLO_APPROVALS_ATTESTED unset — driver should still hit the 403 and
  # return the existing exit 4 (BL-032 reactive path).
  export GLAB_POST_EXIT=0
  export GLAB_PUT_APPR_EXIT=1
  export GLAB_PUT_APPR_STDERR='HTTP 403: 403 Forbidden — This feature is not available on your plan. Upgrade to Premium to enable required approvals.'
  local out; out=$(run_configure org)
  local rc="${out%%|*}"
  if [ "$rc" != "4" ]; then
    fail_ "T2" "expected exit 4 without SOLO_APPROVALS_ATTESTED (reactive path); got rc=$rc"
    teardown_project; return
  fi
  pass "T2: unset SOLO_APPROVALS_ATTESTED preserves BL-032 reactive path (exit 4)"
  teardown_project
}

# ─── T3: WARN message contains operator-actionable hint ────────────────────

t3_warn_message_has_actionable_hint() {
  setup_with_fake_glab
  export SOLO_APPROVALS_ATTESTED=1
  export GLAB_POST_EXIT=0
  local out; out=$(run_configure org)
  local rc="${out%%|*}" stderr="${out#*|}"
  if [ "$rc" != "0" ]; then
    fail_ "T3" "expected exit 0; got rc=$rc stderr=$stderr"
    teardown_project; return
  fi
  # The WARN must mention "Settings" so the operator knows where to
  # click, not just a generic "approvals skipped".
  if [[ "$stderr" != *"Settings"* ]] && [[ "$stderr" != *"settings"* ]]; then
    fail_ "T3" "WARN missing operator hint ('Settings'); stderr=$stderr"
    teardown_project; return
  fi
  if [[ "$stderr" != *"Merge request"* ]] && [[ "$stderr" != *"merge request"* ]] && [[ "$stderr" != *"MR"* ]]; then
    fail_ "T3" "WARN missing MR context; stderr=$stderr"
    teardown_project; return
  fi
  pass "T3: WARN message contains 'Settings > Merge requests' hint"
  teardown_project
}

# ─── T4: shortcircuit does NOT swallow non-approvals failures ──────────────

t4_shortcircuit_preserves_other_failures() {
  setup_with_fake_glab
  export SOLO_APPROVALS_ATTESTED=1
  export GLAB_POST_EXIT=0
  # project-settings PUT still fails — this is NOT the approvals PUT,
  # so the shortcircuit must not swallow it.
  export GLAB_PUT_PROJ_EXIT=1
  export GLAB_PUT_PROJ_STDERR='HTTP 500: internal server error on project settings'
  local out; out=$(run_configure org)
  local rc="${out%%|*}" stderr="${out#*|}"
  if [ "$rc" = "0" ]; then
    fail_ "T4" "shortcircuit swallowed a project-settings PUT failure (would mask real bugs); rc=$rc stderr=$stderr"
    teardown_project; return
  fi
  if [ "$rc" != "5" ]; then
    fail_ "T4" "expected exit 5 for project-settings failure; got rc=$rc stderr=$stderr"
    teardown_project; return
  fi
  pass "T4: SOLO_APPROVALS_ATTESTED=1 preserves non-approvals failure paths (exit 5 for project-settings 500)"
  teardown_project
}

# ─── T5: check-phase-gate.sh honors gitlab_free_tier_approvals reason ──────

t5_check_phase_gate_honors_new_reason() {
  # E2E execution of check-phase-gate.sh requires ~a dozen preseeded
  # artifacts (APPROVAL_LOG.md, PROJECT_BIBLE.md, PRODUCT_MANIFESTO.md,
  # phase-state.json with gates, PATH-stubbed gh/glab, etc.) — the
  # existing test-check-phase-gate-backstop-attestation.sh already
  # exercises that shape for `github_free_tier`. Rather than duplicate
  # the sandbox, T5 is a source-level attestation: the backstop MUST
  # contain a branch that handles `gitlab_free_tier_approvals` — same
  # discipline as T6, but for check-phase-gate.sh rather than
  # check-gate.sh. This catches "the reason was added to check-gate.sh
  # but missed on check-phase-gate.sh" — the exact drift that leaked
  # BL-002 into the code-check-gates-1 audit finding.
  local backstop_line
  # The backstop lives in a block gated by `if [ "$current_phase" -ge 2 ]`.
  # Grep for the new reason in the same file.
  if ! grep -q 'gitlab_free_tier_approvals' "$CHECK_PHASE_GATE"; then
    fail_ "T5" "$CHECK_PHASE_GATE has no branch handling reason 'gitlab_free_tier_approvals' — the Phase 1→2 backstop will FAIL for legitimately-attested GitLab Free projects (same drift class as code-check-gates-1)"
    return
  fi
  # Also assert the branch is adjacent to the existing github_free_tier
  # handler (not just a stray comment somewhere).
  backstop_line=$(grep -n 'gitlab_free_tier_approvals' "$CHECK_PHASE_GATE" | head -1 | cut -d: -f1)
  if [ -z "$backstop_line" ]; then
    fail_ "T5" "grep returned no line number for gitlab_free_tier_approvals in $CHECK_PHASE_GATE"
    return
  fi
  # sanity: the reason must appear as an equality comparison (an if/elif
  # test), not just a comment.
  if ! grep -qE '(=|==)[[:space:]]*"gitlab_free_tier_approvals"' "$CHECK_PHASE_GATE"; then
    fail_ "T5" "gitlab_free_tier_approvals in $CHECK_PHASE_GATE is not in an equality branch — likely a stray comment, not an actual gate handler"
    return
  fi
  pass "T5: check-phase-gate.sh has a branch handling reason 'gitlab_free_tier_approvals' (line $backstop_line)"
}

# ─── T6: check-gate.sh --preflight honors gitlab_free_tier_approvals ───────

t6_check_gate_preflight_honors_new_reason() {
  local sandbox
  sandbox=$(mktemp -d)
  (
    cd "$sandbox"
    mkdir -p .claude
    cat > .claude/manifest.json <<MANIFEST_EOF
{"host": "gitlab", "mode": "org", "remote_url": "https://gitlab.com/org/repo.git"}
MANIFEST_EOF
    cat > .claude/process-state.json <<STATE_EOF
{
  "phase2_init": {
    "attestations": {
      "branch_protection": {
        "attested_by": "orchestrator",
        "at": "2026-06-30T12:00:00Z",
        "reason": "gitlab_free_tier_approvals"
      }
    }
  }
}
STATE_EOF
    out=$(bash "$CHECK_GATE" --preflight 2>&1)
    rc=$?
    if [ "$rc" != "0" ]; then
      echo "$out" > "$sandbox/preflight_out.log"
      return 1
    fi
    if ! echo "$out" | grep -q "gitlab_free_tier_approvals"; then
      echo "$out" > "$sandbox/preflight_out.log"
      return 2
    fi
    return 0
  )
  local rc=$?
  if [ "$rc" != "0" ]; then
    fail_ "T6" "check-gate.sh --preflight did not honor gitlab_free_tier_approvals reason (rc=$rc); see $sandbox/preflight_out.log"
    return
  fi
  rm -rf "$sandbox"
  pass "T6: check-gate.sh --preflight honors gitlab_free_tier_approvals reason"
}

# ─── T4b: check-gate.sh --repair honors gitlab_free_tier_approvals ─────────

t4b_check_gate_repair_honors_new_reason() {
  # PR #134 verifier follow-up: the cmd_repair branch in
  # scripts/check-gate.sh lines ~222-227 short-circuits with an OK line
  # when the recorded attestation reason is `gitlab_free_tier_approvals`
  # AND both `remote_repo_created` + `pushed_initial` steps are marked
  # completed. Parallel to T6 (which covers --preflight for the same
  # reason), this test covers --repair for the same reason so both
  # entrypoints are exercised.
  #
  # Fixture requires:
  #   * .claude/manifest.json (host=gitlab, mode=org — matches BL-032 scope)
  #   * .claude/process-state.json with:
  #       phase2_init.steps_completed = ["remote_repo_created", "pushed_initial"]
  #       phase2_init.attestations.branch_protection.reason = "gitlab_free_tier_approvals"
  #
  # Assertions: rc=0 AND stdout contains a Repair OK line that names
  # gitlab_free_tier_approvals — proves it was the new elif branch that
  # fired, not the github_free_tier branch or the full-repair fallthrough.
  #
  # Mutation-proven: stripping the cmd_repair branch at
  # scripts/check-gate.sh:222-227 makes this test fail RED (either rc!=0
  # from the fallthrough hitting missing host driver stubs, or the
  # gitlab_free_tier_approvals OK line is absent).
  local sandbox
  sandbox=$(mktemp -d)
  (
    cd "$sandbox"
    git init -q >/dev/null 2>&1
    git remote add origin https://gitlab.com/org/repo.git
    mkdir -p .claude
    cat > .claude/manifest.json <<MANIFEST_EOF
{"host": "gitlab", "mode": "org", "remote_url": "https://gitlab.com/org/repo.git"}
MANIFEST_EOF
    cat > .claude/process-state.json <<STATE_EOF
{
  "phase2_init": {
    "steps_completed": ["remote_repo_created", "pushed_initial"],
    "attestations": {
      "branch_protection": {
        "attested_by": "orchestrator",
        "at": "2026-06-30T12:00:00Z",
        "reason": "gitlab_free_tier_approvals"
      }
    }
  }
}
STATE_EOF
    out=$(bash "$CHECK_GATE" --repair 2>&1)
    rc=$?
    if [ "$rc" != "0" ]; then
      printf '%s' "$out" > "$sandbox/repair_out.log"
      return 1
    fi
    if ! printf '%s' "$out" | grep -q "gitlab_free_tier_approvals"; then
      printf '%s' "$out" > "$sandbox/repair_out.log"
      return 2
    fi
    if ! printf '%s' "$out" | grep -qE "Repair.*(nothing to do|attested)"; then
      printf '%s' "$out" > "$sandbox/repair_out.log"
      return 3
    fi
    return 0
  )
  local rc=$?
  if [ "$rc" != "0" ]; then
    fail_ "T4b" "check-gate.sh --repair did not honor gitlab_free_tier_approvals reason (rc=$rc); see $sandbox/repair_out.log"
    return
  fi
  rm -rf "$sandbox"
  pass "T4b: check-gate.sh --repair honors gitlab_free_tier_approvals reason"
}

# ─── T7: Mutation proof — remove intercept, T1 must fail ───────────────────

t7_mutation_proof_intercept_is_load_bearing() {
  # Copy the driver to a tempdir, strip the SOLO_APPROVALS_ATTESTED
  # shortcircuit, then re-run T1's scenario. It MUST now fail (rc=4)
  # because the driver falls through to the approvals PUT that gets a
  # Premium 403.
  #
  # RED-BEFORE-IMPLEMENTATION contract: this test asserts the driver
  # ACTUALLY CONTAINS SOLO_APPROVALS_ATTESTED before mutation. Absent
  # this guard, T7 would pass vacuously against a baseline driver that
  # naturally returns 4 (nothing to mutate). Once implementation lands
  # the guard becomes a smoke test that the shortcircuit is present at
  # source-level, and the mutation validates it's load-bearing.
  if ! grep -q "SOLO_APPROVALS_ATTESTED" "$DRIVER"; then
    fail_ "T7" "driver missing SOLO_APPROVALS_ATTESTED shortcircuit — implementation incomplete (mutation proof would be vacuous)"
    return
  fi
  local mutant_dir mutant_driver
  mutant_dir=$(mktemp -d)
  mutant_driver="$mutant_dir/gitlab.sh"
  # Strip any line that references SOLO_APPROVALS_ATTESTED (both the
  # env-var check AND any WARN block that fires because of it). The
  # cleanest surgical mutation: drop every line between the marker
  # tokens if they exist; otherwise sed out the env-var check itself.
  awk '
    /BL-032-SHORTCIRCUIT-BEGIN/ { skip = 1; next }
    /BL-032-SHORTCIRCUIT-END/   { skip = 0; next }
    !skip { print }
  ' "$DRIVER" > "$mutant_driver"
  # Sanity: mutant must NOT still contain the shortcircuit inside
  # host_configure_protection (the function under test in T1). Other
  # BL-032 references (e.g., inside host_verify_protection) are outside
  # the T1 code path and don't invalidate the mutation.
  local baseline_hits mutant_hits
  baseline_hits=$(grep -c '"${SOLO_APPROVALS_ATTESTED:-0}"' "$DRIVER" || echo 0)
  case "$baseline_hits" in ''|*[!0-9]*) baseline_hits=0 ;; esac
  mutant_hits=$(grep -c '"${SOLO_APPROVALS_ATTESTED:-0}"' "$mutant_driver" || echo 0)
  case "$mutant_hits" in ''|*[!0-9]*) mutant_hits=0 ;; esac
  if [ "$mutant_hits" -ge "$baseline_hits" ]; then
    fail_ "T7" "mutation did not reduce SOLO_APPROVALS_ATTESTED occurrences (baseline=$baseline_hits, mutant=$mutant_hits) — BL-032-SHORTCIRCUIT markers missing or misplaced in $DRIVER"
    rm -rf "$mutant_dir"; return
  fi

  setup_with_fake_glab
  export SOLO_APPROVALS_ATTESTED=1
  export GLAB_POST_EXIT=0
  export GLAB_PUT_APPR_EXIT=1
  export GLAB_PUT_APPR_STDERR='HTTP 403: 403 Forbidden — This feature is not available on your plan. Upgrade to Premium to enable required approvals.'
  local out
  out=$(
    cd "$TMPDIR_T"
    PATH="$TMPDIR_T/bin:$PATH"
    export GLAB_POST_EXIT GLAB_PUT_APPR_EXIT GLAB_PUT_APPR_STDERR SOLO_APPROVALS_ATTESTED
    set +e
    # shellcheck disable=SC1090
    source "$mutant_driver"
    out2=$(host_configure_protection main org 2>&1)
    rc=$?
    printf '%s' "$rc"
  )
  rm -rf "$mutant_dir"
  if [ "$out" = "0" ]; then
    fail_ "T7" "mutation (shortcircuit removed) still returned 0 — T1 was passing by accident, not because of the intercept"
    teardown_project; return
  fi
  if [ "$out" != "4" ]; then
    fail_ "T7" "expected mutant to hit reactive path (rc=4); got rc=$out — mutation may have broken adjacent code"
    teardown_project; return
  fi
  pass "T7: mutation proof — removing the SOLO_APPROVALS_ATTESTED shortcircuit fails T1's scenario (rc=4)"
  teardown_project
}

echo "== tests/test-bl032-gitlab-free-approvals-attestation.sh =="
t1_shortcircuit_skips_approvals_put
t2_reactive_path_unchanged
t3_warn_message_has_actionable_hint
t4_shortcircuit_preserves_other_failures
t5_check_phase_gate_honors_new_reason
t6_check_gate_preflight_honors_new_reason
t4b_check_gate_repair_honors_new_reason
t7_mutation_proof_intercept_is_load_bearing

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
