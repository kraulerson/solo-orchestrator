#!/usr/bin/env bash
# scripts/check-gate.sh — host-aware gate remediation helper.
# Subcommands:
#   --preflight       dry-run verification (does not modify anything)
#   --repair          re-apply repo setup from last successful step
#   --backfill-host   detect and record missing host field in manifest
#
# All subcommands operate on the current project (cwd).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# BL-046: uses print_step/ok/fail/info/warn + log_line + prompt_yes_no
# only — source core subset. Fallback still triggers when lib is missing.
# shellcheck disable=SC1090
source "$SCRIPT_DIR/lib/helpers-core.sh" 2>/dev/null || {
  # Minimal fallback if helpers not available (e.g., pre-init migration scenario)
  print_step() { echo "[STEP] $*"; }
  print_ok()   { echo "  [OK] $*"; }
  print_fail() { echo "[FAIL] $*" >&2; }
  print_info() { echo "[INFO] $*"; }
  print_warn() { echo "[WARN] $*"; }
  log_line()   { :; }
  # Wave-3 raw-read sweep: prompt_yes_no fallback honors the same
  # non-interactive hard-N contract as the helpers-core.sh version.
  # Reached only in pre-init migration scenarios where lib/helpers-core.sh
  # is absent; behavior must match the canonical helper so the manifest
  # mutation in --backfill-host below stays consistent.
  prompt_yes_no() {
    local message="$1" default_answer="${2:-N}"
    if [ ! -t 0 ] || [ -n "${CI:-}" ] || [ -n "${SOIF_NONINTERACTIVE:-}" ]; then
      echo "[WARN] Non-interactive context: skipping prompt (\"$message\") — defaulting to 'N' (caller default '$default_answer' ignored)." >&2
      return 1
    fi
    local reply
    read -rp "${message}: " reply # lint-raw-read-prompt: allow fallback prompt_yes_no defined inline when lib/helpers-core.sh is absent (pre-init migration scenario); semantically equivalent to lib/helpers-core.sh::prompt_yes_no
    [ -z "$reply" ] && { case "$default_answer" in [Yy]*) return 0 ;; *) return 1 ;; esac; }
    case "$reply" in [Nn]*) return 1 ;; *) return 0 ;; esac
  }
}

usage() {
  cat <<'EOM'
Usage: check-gate.sh <subcommand> [--yes]

Subcommands:
  --preflight       Dry-run: check current protection status without modifying anything.
                    Exits 0 if ready to cross Phase 1→2, non-zero if blocked.
  --repair          Re-run repo setup from last successful step (idempotent).
                    With --branch-protection-attested (or SOLO_BP_ATTESTED=1):
                    record the tier-limited branch-protection attestation
                    post-hoc (host-keyed reason; explicit only — BL-123) so a
                    project that met the free-tier 403 unattested can recover
                    without destroy-and-recreate.
  --backfill-host   Infer host from git remote URL and write to manifest.
  --setup-ci-token  RECOMMENDED. Guided end-to-end setup of the CI branch-
                    protection token (walk ISSUE-006). A workflow runner has no
                    credential to verify branch protection — the built-in
                    secrets.GITHUB_TOKEN cannot read it at all — so that one
                    gate check WARNs instead of enforcing until you finish this.
                    Walks you through creating a least-privilege fine-grained
                    PAT (Administration: Read-only, this repo only), VERIFIES it
                    can actually read protection before storing anything, sets
                    it as the Actions secret SOIF_PROTECTION_TOKEN, and confirms
                    the workflow reads it. GitHub-only.
                      --secret-name <name>  secret name
                                            (default SOIF_PROTECTION_TOKEN)
                      --token-env <VAR>     read the token from $VAR instead of
                                            prompting (scriptable opt-in)
                      --skip-verify         store without the read-protection probe
  --release-env-policy
                    Check that the release deployment ENVIRONMENT admits
                    tag deploys before you push a version tag (walk
                    ISSUE-016). Enabling GitHub Pages auto-creates a
                    `github-pages` environment whose default policy admits
                    the default branch only, so a tag-triggered release is
                    rejected before any step runs — empty step list, no
                    readable error. Exits 1 when tag deploys would be
                    rejected and prints the exact remediation.
                      --fix                 apply the policy instead of
                                            just reporting it
                      --env <name>          environment (default github-pages)
                      --tag-pattern <glob>  the tag class your release must be
                                            able to deploy (default v*). An
                                            existing policy SATISFIES it when the
                                            policy, read as a glob, matches this
                                            value — so a `v*` policy satisfies
                                            both `v*` and `v1.0.0`, while a
                                            `v1.0.0` policy does not satisfy `v*`.
                    GitHub-only; other hosts report NOT APPLICABLE (exit 0).

Flags:
  --yes, -y         Skip confirmation prompts (for non-interactive use,
                    e.g. CI or scripted setup). Currently honored by
                    --backfill-host.
EOM
}

_require_manifest() {
  if [ ! -f .claude/manifest.json ]; then
    print_fail ".claude/manifest.json not found — run this in a solo-orchestrator project root"
    return 1
  fi
}

cmd_preflight() {
  _require_manifest || return 1
  print_step "Preflight: checking protection status"

  # BL-002: honor a recorded `github_free_tier` (or `other_host_attestation`)
  # branch-protection attestation from process-state.json. When the project
  # was init'd against a tier-limited host, host_verify_protection has
  # nothing to verify — the attestation IS the gate.
  #
  # BL-032: `gitlab_free_tier_approvals` is the GitLab analog — set when
  # the operator pre-attests via --approvals-attested for gitlab.com Free
  # org-mode projects (approvals PUT is Premium-only). Honored here the
  # same way `github_free_tier` is: the attestation IS the gate, no API
  # verify possible.
  local attest_reason=""
  if [ -f .claude/process-state.json ]; then
    attest_reason=$(jq -r '.phase2_init.attestations.branch_protection.reason // ""' \
                       .claude/process-state.json 2>/dev/null || echo "")
  fi
  if [ "$attest_reason" = "github_free_tier" ]; then
    print_ok "Ready: branch protection attested (reason: github_free_tier — upgrade to GitHub Pro to enable API enforcement)"
    return 0
  fi
  if [ "$attest_reason" = "gitlab_free_tier_approvals" ]; then
    print_ok "Ready: branch protection attested (reason: gitlab_free_tier_approvals — set required-approvals manually via GitLab Settings > Merge requests, or upgrade to Premium for API enforcement)"
    return 0
  fi

  # shellcheck disable=SC1090
  source "$SCRIPT_DIR/lib/host.sh"
  host_load_driver || {
    print_fail "Dispatcher load failed — check manifest host field (scripts/check-gate.sh --backfill-host)"
    return 1
  }
  local mode
  mode=$(jq -r '.mode // "personal"' .claude/manifest.json)
  if host_verify_protection "main" "$mode"; then
    print_ok "Ready: protection verified for $mode mode"
    return 0
  fi
  print_fail "Not ready: protection verification failed (see rules above)"
  return 1
}

cmd_backfill_host() {
  _require_manifest || return 1
  local url
  url=$(git remote get-url origin 2>/dev/null) || {
    print_fail "No git remote configured — cannot infer host"
    return 1
  }
  local inferred
  case "$url" in
    *github.com*)    inferred="github" ;;
    *gitlab*)        inferred="gitlab" ;;
    *bitbucket.org*) inferred="bitbucket" ;;
    *)               inferred="other" ;;
  esac
  print_info "Inferred host '$inferred' from origin URL: $url"
  local yn
  if [ "${ASSUME_YES:-0}" = "1" ]; then
    yn="y"
    print_info "Auto-confirmed via --yes."
  else
    # Wave-3 raw-read sweep: prompt_yes_no honors !-t 0 / CI /
    # SOIF_NONINTERACTIVE and hard-returns N rather than auto-Y'ing
    # a manifest mutation in CI.
    if prompt_yes_no "Confirm this is correct? [y/N]" "N"; then
      yn="y"
    else
      yn="n"
    fi
  fi
  case "$yn" in
    [yY]*)
      jq --arg h "$inferred" '.host = $h' .claude/manifest.json > .claude/manifest.json.tmp \
        && mv .claude/manifest.json.tmp .claude/manifest.json
      print_ok "Host field written to manifest as '$inferred'"
      ;;
    *)
      print_fail "Aborted — no changes made. Manually set the host field if different."
      return 1
      ;;
  esac
}

cmd_repair() {
  _require_manifest || return 1
  print_step "Repair: re-applying repo setup from last successful step"

  # Audit finding specs-plans-host-aware-11: honor the spec contract by
  # consulting phase2_init.steps_completed before running any host_ call.
  # init.sh writes the four named steps (remote_repo_created, pushed_initial,
  # branch_protection_configured, branch_protection_verified) incrementally
  # via _record_phase2_step, so a mid-flight failure leaves accurate state
  # and --repair can resume from the first missing step.
  #
  # PR #97 verifier follow-up: after each successful resume step, --repair
  # writes the matching step back to steps_completed via _record_phase2_step
  # (shared with init.sh via scripts/lib/phase2-state.sh). Without write-back
  # the state file became a lying source of truth — subsequent --repair calls
  # would re-hit the host API for already-completed work and any consumer
  # reading steps_completed would see stale data.
  #
  # The git-remote probe below remains as a defensive fallback for legacy
  # projects (those init'd before incremental writes landed) — when
  # steps_completed is empty/missing we infer "remote_repo_created" from
  # `git remote get-url origin` succeeding.
  # shellcheck disable=SC1090
  source "$SCRIPT_DIR/lib/phase2-state.sh"

  local steps_json="[]"
  local has_state=0
  if [ -f .claude/process-state.json ]; then
    steps_json=$(jq -c '.phase2_init.steps_completed // []' .claude/process-state.json 2>/dev/null || echo "[]")
    has_state=1
  fi
  _step_done() {
    local s="$1"
    echo "$steps_json" | jq -e --arg s "$s" 'index($s) != null' >/dev/null 2>&1
  }
  # _refresh_steps_json — pull the latest steps_completed off disk so the
  # in-memory cache stays in sync after a _record_phase2_step write. Cheap
  # (one jq + one read) and called only after each successful resume step.
  _refresh_steps_json() {
    if [ -f .claude/process-state.json ]; then
      steps_json=$(jq -c '.phase2_init.steps_completed // []' .claude/process-state.json 2>/dev/null || echo "[]")
    fi
  }

  # BL-157-REMOTE-MARKER-BEGIN
  # BL-157: a scaffold created with `init.sh --no-remote-creation` whose
  # operator later wired `origin` by hand and pushed never gets
  # remote_repo_created / pushed_initial recorded — init.sh's recorder only
  # fires on the API-create path that flag skipped. The BL-123 post-hoc
  # attestation block just below REFUSES until those two markers are on record,
  # so a free-tier operator was forced into an undocumented two-step: a plain
  # `--repair` (which reconciles the markers via Steps 1-2 and then re-hits the
  # 403), and only THEN `--repair --branch-protection-attested`.
  #
  # Reconcile the markers HERE, in the repair preflight, BEFORE the BL-123
  # block runs — so a single `--repair --branch-protection-attested` succeeds
  # when the remote is genuinely present. GENUINE detection only, never an
  # assumption: remote_repo_created is recorded only when the configured
  # `origin` answers `git ls-remote` (the repo provably exists on the host);
  # pushed_initial only when that remote actually carries the project's branch
  # head (current branch, else main/master — the same `git ls-remote --heads
  # origin` primitive the check-phase-gate.sh BL-084 push backstop uses). A
  # truly remote-less project (no `origin`, or an `origin` with no pushed
  # branch) records NOTHING here, so the BL-123 refusal below stays exactly as
  # designed — this SATISFIES the precondition when it is legitimately met, it
  # does not weaken the guard. Idempotent (skips already-recorded steps) and
  # provenance-consistent with the BL-123 recorder (writes through the shared
  # _record_phase2_step helper).
  if ! _step_done "remote_repo_created" || ! _step_done "pushed_initial"; then
    local _bl157_heads _bl157_branch _bl157_cand _bl157_sha
    if git remote get-url origin >/dev/null 2>&1 \
       && _bl157_heads=$(git ls-remote --heads origin 2>/dev/null); then
      # The configured remote answered ls-remote — the repo genuinely exists.
      if ! _step_done "remote_repo_created"; then
        _record_phase2_step "remote_repo_created"
        _refresh_steps_json
        print_info "Repair: recorded remote_repo_created — configured 'origin' answers ls-remote (repo exists on host). [BL-157]"
      fi
      # pushed_initial only if that remote actually carries OUR branch head.
      # BL-157 (verifier HIGH-1/2): match the branch EXACTLY via an awk field
      # compare — NOT a grep BRE, where a branch name with regex metacharacters
      # (`rel/1.x`) would launder a lookalike (`rel/1yx`) — AND require the
      # matched remote head to be a commit THIS repo holds locally
      # (`cat-file -e … ^{commit}`). Name-existence alone let a same-named but
      # UNPUSHED remote branch (GitHub's "Initialize with README" default `main`,
      # disjoint history) satisfy the marker with zero project code on the host,
      # then earn the BL-123 attestation AND the BL-116 push-gate exemption. A
      # genuine push guarantees the shared commit; an unrelated auto-init does
      # not — so this records only when the code was really pushed.
      if ! _step_done "pushed_initial"; then
        _bl157_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
        for _bl157_cand in "$_bl157_branch" main master; do
          [ -z "$_bl157_cand" ] && continue
          [ "$_bl157_cand" = "HEAD" ] && continue
          _bl157_sha=$(printf '%s\n' "$_bl157_heads" \
            | awk -v r="refs/heads/$_bl157_cand" '$2 == r { print $1; exit }')
          [ -z "$_bl157_sha" ] && continue
          git cat-file -e "$_bl157_sha^{commit}" 2>/dev/null || continue
          _record_phase2_step "pushed_initial"
          _refresh_steps_json
          print_info "Repair: recorded pushed_initial — 'origin' carries our pushed '$_bl157_cand' head ($(printf '%.7s' "$_bl157_sha")). [BL-157]"
          break
        done
      fi
    fi
  fi
  # BL-157-REMOTE-MARKER-END

  # BL-123-BP-ATTEST-RECORD-BEGIN
  # BL-123 / BL-111: an attestation-RECORDING path for --repair. The
  # tier-limited attestation used to be writable ONLY inside init.sh's
  # in-flight 403 fallback, so an unattested first contact with the 403 was
  # unrecoverable: --repair re-hit the 403 and recommended a flag only
  # init.sh accepted, and re-running init.sh died on "Name already exists"
  # (Dogfood-2 F-DF2-002; BL-111 is the hermetic sibling). Accepting
  # `--branch-protection-attested` (or SOLO_BP_ATTESTED=1) here records the
  # SAME shape init.sh writes — attested_by/at/host-keyed reason plus the two
  # bp step records — and the attested short-circuit below then fires before
  # any host API call. EXPLICIT ONLY: never inferred, never defaulted;
  # idempotent (skipped when an attestation already exists).
  local _bp_want=0 _bp_arg
  for _bp_arg in "$@"; do
    case "$_bp_arg" in
      --branch-protection-attested) _bp_want=1 ;;
    esac
  done
  [ "${SOLO_BP_ATTESTED:-0}" = "1" ] && _bp_want=1
  if [ "$_bp_want" -eq 1 ] && [ -f .claude/process-state.json ]; then
    local _bp_existing_at _bp_existing_reason _bp_host _bp_reason
    # Idempotency keys on the attestation's PRESENCE (.at), not on .reason —
    # init.sh's 'other'-host attestation is reasonless, and a healthy attested
    # project + the flag must be a no-op, never a refusal (verifier finding C).
    _bp_existing_at=$(jq -r '.phase2_init.attestations.branch_protection.at // ""' \
                        .claude/process-state.json 2>/dev/null || echo "")
    _bp_existing_reason=$(jq -r '.phase2_init.attestations.branch_protection.reason // ""' \
                            .claude/process-state.json 2>/dev/null || echo "")
    if [ -n "$_bp_existing_at" ]; then
      print_info "Repair: attestation already recorded (reason: ${_bp_existing_reason:-none — manual-host shape}) — --branch-protection-attested is a no-op."
    elif ! _step_done "remote_repo_created" || ! _step_done "pushed_initial"; then
      # Verifier finding A: the recorder must mirror the attested
      # short-circuit's preconditions. init.sh's 403 fallback is only
      # reachable AFTER create+push succeeded; recording without them would
      # let 3 of 4 consumers honor a branch-protection attestation on a
      # project with no pushed remote at all — a laundered gate.
      # BL-157-REMOTE-MARKER: with the preflight reconciler above, this refusal
      # now fires ONLY for a genuinely remote-less project (no `origin`, or an
      # `origin` with no pushed branch) — the guard is intact, we simply have
      # nothing legitimate to reconcile from. Name the exact recovery command
      # so the operator is not left guessing (BL-157 message ask).
      print_fail "Post-hoc attestation preconditions unmet: no pushed remote branch detected on 'origin' (remote_repo_created / pushed_initial are not on record, and the repair preflight found no repo+branch to reconcile them from — BL-157). The attestation covers the protection TIER, not the remote's existence. Create and push the remote first, e.g.:  git push -u origin main   then re-run:  scripts/check-gate.sh --repair --branch-protection-attested"
      return 1
    else
      _bp_host=$(jq -r '.host // ""' .claude/manifest.json 2>/dev/null || echo "")
      case "$_bp_host" in
        github) _bp_reason="github_free_tier" ;;
        gitlab) _bp_reason="gitlab_free_tier_approvals" ;;
        *)
          print_fail "Post-hoc branch-protection attestation is host-keyed (github/gitlab tier-limited plans); manifest host is '${_bp_host:-unset}'."
          return 1 ;;
      esac
      # recorded_via: the provenance discriminator (verifier finding B) — an
      # auditor must be able to tell a witnessed-at-403 init-time attestation
      # from a post-hoc one recorded through this repair path.
      jq --arg at "$(date -u +%FT%TZ)" --arg reason "$_bp_reason" \
         '.phase2_init.attestations.branch_protection = {attested_by: "orchestrator", at: $at, reason: $reason, recorded_via: "check-gate-repair"}' \
         .claude/process-state.json > .claude/process-state.json.tmp \
         && mv .claude/process-state.json.tmp .claude/process-state.json
      _record_phase2_step "branch_protection_configured"
      _record_phase2_step "branch_protection_verified"
      _refresh_steps_json
      print_ok "Repair: branch-protection attestation RECORDED post-hoc (reason: $_bp_reason — upgrade the host plan to enable API enforcement; recorded_via: check-gate-repair). Explicit operator attestation; recorded to .claude/process-state.json."
    fi
  fi
  # BL-123-BP-ATTEST-RECORD-END

  # Honor a recorded tier-limited attestation (spec category 6 / BL-002).
  # If the operator attested branch protection at init time, --repair has
  # nothing further to do — the attestation IS the gate. This mirrors
  # cmd_preflight's branch and keeps the two subcommands consistent.
  #
  # PR #97 verifier defensive fix: also require remote_repo_created AND
  # pushed_initial to be recorded before short-circuiting on attestation.
  # Today init.sh's write ordering guarantees both are set before the
  # attestation is recorded, but coupling cmd_repair's correctness to
  # init.sh's internal ordering is fragile — a future change that records
  # attestation earlier (e.g., for prompt UX) would silently break --repair
  # for broken-but-attested projects. The two extra checks make the
  # short-circuit self-justifying instead of order-dependent.
  local attest_reason=""
  if [ "$has_state" -eq 1 ]; then
    attest_reason=$(jq -r '.phase2_init.attestations.branch_protection.reason // ""' \
                       .claude/process-state.json 2>/dev/null || echo "")
  fi
  if [ "$attest_reason" = "github_free_tier" ] \
     && _step_done "remote_repo_created" \
     && _step_done "pushed_initial"; then
    print_ok "Repair: nothing to do — branch protection attested (reason: github_free_tier)"
    return 0
  fi
  # BL-032: same short-circuit for the GitLab Free tier approvals
  # attestation reason.
  if [ "$attest_reason" = "gitlab_free_tier_approvals" ] \
     && _step_done "remote_repo_created" \
     && _step_done "pushed_initial"; then
    print_ok "Repair: nothing to do — branch protection attested (reason: gitlab_free_tier_approvals)"
    return 0
  fi

  # No all-four-steps short-circuit (PR #97 verifier Issue #3 — option A).
  # Pre-fix the early return at the top of cmd_repair conflicted with the
  # "always re-run verify so the gate sees fresh state" comment further
  # down: in the common case (full success) verify was never re-run because
  # the short-circuit fired first, so drift detection on repair was
  # silently dead. Drift detection is also cmd_preflight's job, but having
  # --repair always probe live state matches the documented intent and
  # costs one extra API call per repair invocation. The per-step skips
  # below keep the create/push/configure work idempotent (no redundant API
  # writes) — only the verify GET is repeated when all four are done.

  # shellcheck disable=SC1090
  source "$SCRIPT_DIR/lib/host.sh"
  host_load_driver || {
    print_fail "Dispatcher load failed — run --backfill-host first"
    return 1
  }
  local mode
  mode=$(jq -r '.mode // "personal"' .claude/manifest.json)

  # Step 1: remote_repo_created. Skip if steps_completed says done, OR (legacy
  # fallback) if `git remote get-url origin` succeeds on a project that
  # predates incremental writes (has_state=0). In the legacy-fallback case
  # we record the step on first --repair so the state file stops lying.
  if _step_done "remote_repo_created"; then
    print_info "Skipping create — already recorded"
  elif git remote get-url origin >/dev/null 2>&1; then
    print_info "Skipping create — remote already configured (legacy project, recording step)"
    _record_phase2_step "remote_repo_created"
    _refresh_steps_json
  else
    local name visibility
    if [ -f .claude/intake-progress.json ]; then
      name=$(jq -r '.answers.project_name // empty' .claude/intake-progress.json)
      visibility=$(jq -r '.answers.repo_visibility // "private"' .claude/intake-progress.json)
    fi
    name="${name:-$(basename "$(pwd)")}"
    visibility="${visibility:-private}"
    print_info "Creating $visibility repo '$name' on $(host_name)..."
    local url
    url=$(host_create_repo "$name" "$visibility") || { print_fail "Repo creation failed"; return 1; }
    host_register_remote "$url"
    _record_phase2_step "remote_repo_created"
    _refresh_steps_json
    print_ok "Remote created at $url"
  fi

  # Step 2: pushed_initial. Skip if recorded, else attempt push (idempotent
  # at the git layer — a no-op if remote is already in sync).
  if _step_done "pushed_initial"; then
    print_info "Skipping push — already recorded"
  else
    host_push_initial main 2>/dev/null || host_push_initial master || {
      print_fail "Push failed — see driver error above"
      return 1
    }
    _record_phase2_step "pushed_initial"
    _refresh_steps_json
    print_ok "Initial push complete"
  fi

  # Step 3: branch_protection_configured. Skip if recorded.
  if _step_done "branch_protection_configured"; then
    print_info "Skipping configure — protection already recorded"
  else
    print_info "Re-applying protection for $mode mode..."
    host_configure_protection main "$mode" 2>/dev/null || host_configure_protection master "$mode" \
      || { print_fail "Protection config failed"
           # BL-157-REMOTE-MARKER: on a tier-limited host (free-tier 403 on the
           # protection API) remote_repo_created/pushed_initial are already on
           # record by now (recorded by init.sh's push, or reconciled in the
           # BL-157 preflight above), so the operator can record the
           # tier-limited attestation in ONE more step. Pre-BL-157 the first
           # `--repair` never named the flag to add — the BL-157 message ask.
           print_info "If the host rejected the protection API (free-tier 403 'Upgrade to…' on GitHub private repos, or GitLab Premium-only approvals), the create/push markers are on record — record the tier-limited attestation with:  scripts/check-gate.sh --repair --branch-protection-attested"
           return 1; }
    _record_phase2_step "branch_protection_configured"
    _refresh_steps_json
  fi

  # Step 4: branch_protection_verified. Always re-run verify on repair so the
  # gate sees fresh state, even if steps_completed says verified — protection
  # may have drifted since the original write. With the all-4 short-circuit
  # removed above, this verify also runs on the "everything already done"
  # path, which is the documented behavior the PR #97 bonus-catch claimed.
  if ! host_verify_protection main "$mode" 2>/dev/null && ! host_verify_protection master "$mode"; then
    sleep 5
    host_verify_protection main "$mode" 2>/dev/null || host_verify_protection master "$mode" \
      || { print_fail "Verification still failing — check host UI"; return 1; }
  fi
  # Record verification last — only after the GET above confirmed live
  # state matches the configured rules. Idempotent via the `unique` filter
  # in _record_phase2_step (no duplicates accumulate on re-runs).
  _record_phase2_step "branch_protection_verified"
  print_ok "Repair complete"
}

# WALK-ISSUE-006-SETUP-CI-TOKEN-BEGIN
# Walk 2026-08-02, ISSUE-006 remediation, part 3 of 3. Part 1 stops the gate's
# branch-protection backstop from blocking a runner that structurally cannot
# perform the check (`grep -n 'WALK-ISSUE-006' scripts/check-phase-gate.sh`);
# part 2 makes every generated ci.yml SAY so at the step. Neither of those
# RESTORES the check — and a permanently-warning check is a check on its way to
# being ignored. This arm is the guided path back to hard enforcement: it
# explains what the token is for, names the MINIMUM permission, stores it as an
# Actions secret, and verifies the workflow will actually read it.
#
# WHY A WALKTHROUGH AND NOT A DOC LINE: the failure mode this closes is not
# ignorance of the option, it is the five separate steps between knowing and
# having (which token type, which permission, where it goes, what it is called,
# what reads it) — each of which is a place to stop.
#
# GitHub-only: `gh secret set` has no gitlab/bitbucket equivalent worth
# pretending about here, so those hosts get the manual instruction and exit 0.
cmd_setup_ci_token() {
  _require_manifest || return 1

  local secret_name="SOIF_PROTECTION_TOKEN"
  local token_env="SOIF_PROTECTION_TOKEN"
  local skip_verify=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --secret-name)   shift; secret_name="${1:?--secret-name requires a value}" ;;
      --secret-name=*) secret_name="${1#--secret-name=}" ;;
      --token-env)     shift; token_env="${1:?--token-env requires a value}" ;;
      --token-env=*)   token_env="${1#--token-env=}" ;;
      --skip-verify)   skip_verify=1 ;;
      *) print_fail "--setup-ci-token: unknown flag '$1'"; return 1 ;;
    esac
    shift || true
  done

  local host
  host=$(jq -r '.host // empty' .claude/manifest.json 2>/dev/null || echo "")
  if [ "$host" != "github" ]; then
    print_info "CI protection token: NOT APPLICABLE for host='${host:-unset}' — this walkthrough drives \`gh secret set\`."
    case "$host" in
      gitlab)
        echo "  GitLab: add a masked, protected CI/CD variable GITLAB_TOKEN (Settings > CI/CD > Variables)"
        echo "          holding a PAT with the \`api\` scope, AND install \`glab\` in the governance job."
        echo "          GitLab injects CI/CD variables into the job environment automatically, so no"
        echo "          workflow wiring is needed — but WITHOUT glab the check still cannot run."
        ;;
      bitbucket)
        echo "  Bitbucket: add repository variables BITBUCKET_API_TOKEN + BITBUCKET_API_TOKEN_EMAIL"
        echo "             (Repository settings > Repository variables), AND install curl in the"
        echo "             Governance step. Both are required before the check can run."
        ;;
    esac
    return 0
  fi

  if ! command -v gh >/dev/null 2>&1; then
    print_fail "CI protection token: \`gh\` CLI not found — install it, run \`gh auth login\`, then re-run."
    return 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    print_fail "CI protection token: \`gh\` is not authenticated — run \`gh auth login\`, then re-run."
    return 1
  fi

  # shellcheck disable=SC1090
  source "$SCRIPT_DIR/lib/host.sh"
  host_load_driver || {
    print_fail "Dispatcher load failed — check manifest host field (scripts/check-gate.sh --backfill-host)"
    return 1
  }
  local owner_repo
  owner_repo=$(_github_parse_origin) || {
    print_fail "Could not parse a GitHub owner/repo from 'origin'"
    return 1
  }

  print_step "CI protection token for $owner_repo"
  cat <<EOM

  WHAT THIS IS FOR
    Your CI's phase-gate step verifies that branch protection on main is still
    configured. That is an AUTHENTICATED GitHub API read, and a workflow runner
    has no credential for it: Actions puts no token in a step's environment, and
    the built-in secrets.GITHUB_TOKEN CANNOT read branch protection at all —
    there is no \`administration\` key in the workflow \`permissions:\` block.
    Until you finish this, that one check WARNS on every run instead of
    enforcing. Everything else in the gate keeps blocking as normal.

  THE TOKEN YOU NEED (least privilege — read-only, one repo)
    1. Open:  https://github.com/settings/personal-access-tokens/new
    2. Token name:        soif-protection-read ($owner_repo)
       Expiration:        your policy (90 days is a reasonable default)
       Repository access: "Only select repositories" -> $owner_repo
    3. Repository permissions -> Administration: **Read-only**
       That single permission is the whole requirement. Do NOT grant write.
       (A classic PAT with the \`repo\` scope also works but is far broader —
       prefer the fine-grained token.)
    4. Generate, then copy the value once.

  WHAT HAPPENS NEXT
    The value is stored as the Actions secret \`$secret_name\` on $owner_repo
    and nothing else. This command then CHECKS your workflow — it must both map
    the secret into the phase-gate step as GH_TOKEN and let the gate's exit code
    decide that step — and tells you exactly what to add if either is missing.
    When both hold, the very next push re-arms the check.
    An UNSET secret evaluates to the empty string, which the gate reads as
    "no credential" — which is exactly today's warning.

EOM

  # Token source. An exported \$$token_env is an explicit, scriptable opt-in
  # (and is how the hermetic tests drive this arm); otherwise prompt with echo
  # OFF. `read -rs` carries no -p, so the raw-prompt lint's target does not
  # apply — but the non-interactive guard it exists to enforce still does, and
  # is implemented here explicitly rather than inherited.
  local token=""
  # The indirect read is an `eval`, so the variable NAME is validated as a
  # shell identifier first — `--token-env` is operator-supplied and an
  # unvalidated name would be a command-injection sink.
  case "$token_env" in
    [A-Za-z_]*) : ;;
    *) print_fail "--token-env: '$token_env' is not a valid environment variable name"; return 1 ;;
  esac
  case "$token_env" in
    *[!A-Za-z0-9_]*) print_fail "--token-env: '$token_env' is not a valid environment variable name"; return 1 ;;   # F-015-TOKEN-ENV-CHARSET
  esac
  eval "token=\${$token_env:-}"
  if [ -n "$token" ]; then
    print_info "Using the token from \$$token_env (explicit opt-in — no prompt)."
  else
    if [ "${ASSUME_YES:-0}" -ne 1 ]; then
      if ! prompt_yes_no "Create the $secret_name secret on $owner_repo now? [y/N]" N; then
        print_info "Nothing changed. Re-run this command when you have the token, or export $token_env=<token> and re-run non-interactively."
        return 0
      fi
    fi
    if [ ! -t 0 ] || [ -n "${CI:-}" ] || [ -n "${SOIF_NONINTERACTIVE:-}" ]; then
      print_fail "No terminal to read the token from. Export it instead and re-run:  $token_env=<token> scripts/check-gate.sh --setup-ci-token"
      return 1
    fi
    printf '  Paste the token (input hidden), then press Enter: ' >&2
    read -rs token
    printf '\n' >&2
  fi
  if [ -z "$token" ]; then
    print_fail "Empty token — nothing stored."
    return 1
  fi

  # VERIFY BEFORE STORING. A secret that cannot read protection turns today's
  # honest WARN into tomorrow's hard FAIL, which is strictly worse than the
  # state we started in — so the walkthrough proves the token works first.
  if [ "$skip_verify" -eq 0 ]; then
    local probe
    if probe=$(GH_TOKEN="$token" gh api "repos/$owner_repo/branches/main/protection" 2>&1); then
      print_ok "Token verified — it can read branch protection on $owner_repo."
    else
      print_fail "That token could NOT read branch protection on $owner_repo — refusing to store it (a stored-but-powerless token converts the current WARN into a hard FAIL)."
      echo "  GitHub said: $(printf '%s' "$probe" | head -2 | tr '\n' ' ')"
      echo "  Most likely: the fine-grained token is missing 'Administration: Read-only', or it does not include this repository."
      echo "  If branch protection is genuinely not configured yet, fix that first: scripts/check-gate.sh --repair"
      echo "  To store anyway (you accept the risk): scripts/check-gate.sh --setup-ci-token --skip-verify"
      return 1
    fi
  fi

  # The value goes in on STDIN, never on argv — an argv secret is visible to
  # every other process on the box via `ps`.
  if ! printf '%s' "$token" | gh secret set "$secret_name" --repo "$owner_repo" >/dev/null 2>&1; then
    print_fail "Could not set the Actions secret '$secret_name' on $owner_repo (does your gh login have repo admin?)"
    return 1
  fi
  # -qxF: whole-line, FIXED string. An anchored regex would both mis-handle a
  # name containing regex metacharacters and match a longer secret that merely
  # starts with this one.
  if gh secret list --repo "$owner_repo" 2>/dev/null | cut -f1 | grep -qxF -- "$secret_name"; then
    print_ok "Actions secret '$secret_name' is set on $owner_repo."
  else
    print_warn "Secret write reported success but '$secret_name' is not listed — check Settings > Secrets and variables > Actions."
  fi

  # The last links in the chain, and BOTH are required before this command may
  # claim the check now enforces (adversarial review R-1):
  #   (a) the workflow READS the secret — a secret nothing reads is a silent
  #       no-op wearing a success message;
  #   (b) the gate's EXIT CODE still decides the step. Generated projects
  #       scaffolded before this shipped ran the gate as
  #         bash scripts/check-phase-gate.sh 2>/dev/null || echo "…skipping"
  #       which throws the verdict away: the gate can print [FAIL] and exit 1
  #       while the step grades GREEN, and the "not found" message is a lie
  #       (the script was found; its verdict failed). Under that shape a
  #       correctly-scoped token changes NOTHING, so saying "the next push
  #       enforces" would be false.
  #
  # F-015 (Karl, 2026-08-09 — "Harden it"): this test is an ALLOWLIST. It used
  # to enumerate FORBIDDEN shapes — `\|\|[[:space:]]*(echo|true|:)` — and the
  # sibling pin in bl147 was proven by mutation to let `|| exit 0` through for
  # exactly that reason (BUG-009 confirm review, R-C1). A pipe, a trailing `&`,
  # an `if !` wrapper, an interpreter swap and a command appended after the
  # invocation all walked through it too, each earning the "the next push
  # enforces the check" claim while the verdict went in the bin. Blacklists lose
  # to creativity.
  #
  # So: an executable line naming the gate script may be the bare invocation or
  # the existence guard the emitted templates wrap it in, and NOTHING else.
  # Normalization is limited to what cannot change what bash runs — indentation,
  # a YAML sequence dash, the `run:` key of an inline scalar, trailing blanks —
  # which is why an older project whose step is `run: bash scripts/…` on one
  # line still reads as honest. Whole-line comments are dropped because they are
  # inert; a `#` on the invocation line is not, and makes the line deviate.
  local wf=".github/workflows/ci.yml"
  local wf_maps=0 wf_swallows=0
  if [ -f "$wf" ]; then
    grep -q "secrets.$secret_name" "$wf" && wf_maps=1
    if grep -v '^[[:space:]]*#' "$wf" \
         | grep -F 'scripts/check-phase-gate.sh' \
         | sed -e 's/^[[:space:]]*//' -e 's/^-[[:space:]]*//' \
               -e 's/^run:[[:space:]]*//' -e 's/[[:space:]]*$//' \
         | grep -qvxF -e 'bash scripts/check-phase-gate.sh' \
                      -e 'if [ ! -f scripts/check-phase-gate.sh ]; then'; then
      wf_swallows=1   # F-015-PROJECT-ALLOWLIST-VERDICT
    fi
  fi
  if [ "$wf_maps" -eq 1 ] && [ "$wf_swallows" -eq 0 ]; then
    print_ok "$wf maps $secret_name into the phase-gate step AND lets the gate's exit code decide it. The next push enforces the check."
  elif [ "$wf_maps" -eq 1 ] && [ "$wf_swallows" -eq 1 ]; then
    print_warn "$wf maps $secret_name, but its phase-gate step DISCARDS the gate's exit code, so the token cannot enforce anything. Replace the swallowing 'run:' line with:"
    echo "        run: |"
    echo "          if [ ! -f scripts/check-phase-gate.sh ]; then"
    echo "            echo \"::error::Phase gate check script missing. Framework integrity compromised.\""
    echo "            exit 1"
    echo "          fi"
    echo "          bash scripts/check-phase-gate.sh"
  else
    print_warn "$wf does not map $secret_name yet — the secret would be stored but unread. Add these lines to the 'Governance - Phase gate check' step:"
    echo "        env:"
    echo "          GH_TOKEN: \${{ secrets.$secret_name }}"
  fi
  echo ""
  print_info "Verify locally any time with: scripts/check-gate.sh --preflight"
  return 0
}
# WALK-ISSUE-006-SETUP-CI-TOKEN-END

# WALK-ISSUE-016-RELEASE-ENV-POLICY-BEGIN
# Walk 2026-08-02, ISSUE-016 (Major): the documented happy path — "release is
# triggered by version tags: git tag v1.0.0 && git push --tags" — HARD-FAILS on
# a fresh GitHub Pages repo, opaquely. Enabling Pages auto-creates a
# `github-pages` deployment environment whose default branch policy admits the
# DEFAULT BRANCH ONLY, so a run triggered from a TAG is rejected by the
# environment's protection rules BEFORE any step executes: an empty step list,
# no readable error in `gh run view`, and no doc anywhere connecting the two.
#
# WHY THIS LIVES IN A SCRIPT AND NOT IN release.yml: a run that the environment
# rejects never starts a job, so an in-workflow preflight step is unreachable by
# construction. The check has to run somewhere that CAN execute — here, from the
# workstation, before the tag is pushed.
#
# Dry-run by default (report + exact commands, exit 1 when tag deploys would be
# rejected); `--fix` applies. Non-github hosts are NOT APPLICABLE, not failures:
# GitLab protected environments and Bitbucket deployment permissions are
# different mechanisms and neither auto-creates a default-branch-only policy on
# a fresh repo.
cmd_release_env_policy() {
  _require_manifest || return 1

  local env_name="github-pages" tag_pattern="v*" do_fix=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --fix)         do_fix=1 ;;
      --env)         shift; env_name="${1:-github-pages}" ;;
      --env=*)       env_name="${1#--env=}" ;;
      --tag-pattern) shift; tag_pattern="${1:-v*}" ;;
      --tag-pattern=*) tag_pattern="${1#--tag-pattern=}" ;;
      *) print_fail "--release-env-policy: unknown flag '$1'"; return 1 ;;
    esac
    shift || true
  done

  local host
  host=$(jq -r '.host // empty' .claude/manifest.json 2>/dev/null || echo "")
  if [ "$host" != "github" ]; then
    print_info "Release environment policy: NOT APPLICABLE for host='${host:-unset}' — the default-branch-only deployment policy that rejects tag deploys is a GitHub environments behavior. (GitLab protected environments / Bitbucket deployment permissions are opt-in and are not auto-created.)"
    return 0
  fi
  if ! command -v gh >/dev/null 2>&1; then
    print_fail "Release environment policy: \`gh\` CLI not found — install it and re-run (this check is a GitHub API read)."
    return 1
  fi

  # shellcheck disable=SC1090
  source "$SCRIPT_DIR/lib/host.sh"
  host_load_driver || {
    print_fail "Dispatcher load failed — check manifest host field (scripts/check-gate.sh --backfill-host)"
    return 1
  }
  local owner_repo
  owner_repo=$(_github_parse_origin) || {
    print_fail "Could not parse a GitHub owner/repo from 'origin'"
    return 1
  }

  print_step "Release environment policy: $owner_repo environment '$env_name'"

  local env_json
  if ! env_json=$(gh api "repos/$owner_repo/environments/$env_name" 2>&1); then
    if printf '%s' "$env_json" | grep -q 'Not Found'; then
      print_ok "Environment '$env_name' does not exist yet — nothing can reject a tag deploy. Re-run this check AFTER you enable Pages (or first create the environment); GitHub creates it with a default-branch-only policy."
      return 0
    fi
    print_fail "Could not read environment '$env_name': $(printf '%s' "$env_json" | head -2 | tr '\n' ' ')"
    return 1
  fi

  local protected custom
  protected=$(printf '%s' "$env_json" | jq -r '.deployment_branch_policy.protected_branches // false' 2>/dev/null || echo false)
  custom=$(printf '%s' "$env_json" | jq -r '.deployment_branch_policy.custom_branch_policies // false' 2>/dev/null || echo false)

  if [ "$protected" != "true" ] && [ "$custom" != "true" ]; then
    print_ok "Environment '$env_name' has no deployment branch policy — every branch AND tag may deploy. Tag-triggered releases are fine."
    return 0
  fi

  local post_cmd="gh api -X POST repos/$owner_repo/environments/$env_name/deployment-branch-policies -f name='$tag_pattern' -f type='tag'"

  if [ "$protected" = "true" ]; then
    # protected_branches:true admits protected BRANCHES only and refuses
    # custom policies outright — a tag can never deploy until the env is
    # switched to custom policies.
    print_fail "Environment '$env_name' allows PROTECTED BRANCHES only — a tag-triggered release ('$tag_pattern') is rejected before any step runs (that is the empty-step-list failure with no readable error)."
    echo "  Switch the environment to custom policies, then admit the tag pattern:"
    echo "    gh api -X PUT repos/$owner_repo/environments/$env_name --input - <<'JSON'"
    echo "    {\"deployment_branch_policy\":{\"protected_branches\":false,\"custom_branch_policies\":true}}"
    echo "    JSON"
    echo "    $post_cmd"
    if [ "$do_fix" -eq 1 ]; then
      printf '{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}' \
        | gh api -X PUT "repos/$owner_repo/environments/$env_name" --input - >/dev/null || {
          print_fail "Could not switch '$env_name' to custom branch policies"; return 1; }
    else
      return 1
    fi
  fi

  local pol_json
  if ! pol_json=$(gh api "repos/$owner_repo/environments/$env_name/deployment-branch-policies" 2>&1); then
    print_fail "Could not list deployment branch policies for '$env_name': $(printf '%s' "$pol_json" | head -2 | tr '\n' ' ')"
    return 1
  fi
  # Adversarial review R-3: matching by literal string equality false-failed a
  # correctly-configured repo — an existing `v*` policy plainly admits a
  # `--tag-pattern v1.0.0` release, but `"v*" = "v1.0.0"` is false. The POLICY
  # is a glob and the requested pattern is the subject, which gets all four
  # cases right:
  #   policy v*      vs request v*      -> match (glob `v*` matches "v*")
  #   policy v*      vs request v1.0.0  -> match (the policy admits that tag)
  #   policy v1.0.0  vs request v*      -> NO match, correctly: a single-tag
  #                                        policy does not admit the whole class
  #   policy *       vs request anything-> match
  # The policy name is repo-controlled data, so it is used as the unquoted RHS
  # of `[[ == ]]` (bash's pattern position) and never spliced into `case` syntax.
  local have_tag=0 _pol
  while IFS= read -r _pol; do
    [ -n "$_pol" ] || continue
    # shellcheck disable=SC2053
    if [ "$_pol" = "$tag_pattern" ] || [[ $tag_pattern == $_pol ]]; then
      have_tag=1
      break
    fi
  done <<EOF
$(printf '%s' "$pol_json" | jq -r '.branch_policies[]? | select(.type=="tag") | .name' 2>/dev/null || true)
EOF

  if [ "$have_tag" -gt 0 ]; then
    print_ok "Environment '$env_name' admits tag deployments matching '$tag_pattern' — tag-triggered releases will run."
    return 0
  fi

  print_fail "Environment '$env_name' has NO tag deployment policy — 'git push --tags' will be rejected by the environment before any step runs (empty step list, no readable error in \`gh run view\`)."
  echo "  Admit the release tag pattern:"
  echo "    $post_cmd"
  echo "  Or apply it now:  scripts/check-gate.sh --release-env-policy --fix"
  if [ "$do_fix" -eq 1 ]; then
    gh api -X POST "repos/$owner_repo/environments/$env_name/deployment-branch-policies" \
      -f "name=$tag_pattern" -f 'type=tag' >/dev/null || {
        print_fail "Could not add the '$tag_pattern' tag deployment policy"; return 1; }
    print_ok "Added tag deployment policy '$tag_pattern' to '$env_name' — re-run the failed release workflow."
    return 0
  fi
  return 1
}
# WALK-ISSUE-016-RELEASE-ENV-POLICY-END

ASSUME_YES=0
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --yes|-y) ASSUME_YES=1 ;;
    *)        ARGS+=("$arg") ;;
  esac
done
set -- ${ARGS[@]+"${ARGS[@]}"}

case "${1:-}" in
  --preflight)     shift || true; cmd_preflight "$@" ;;
  --repair)        shift || true; cmd_repair "$@" ;;
  --backfill-host) shift || true; cmd_backfill_host "$@" ;;
  --release-env-policy) shift || true; cmd_release_env_policy "$@" ;;
  --setup-ci-token)     shift || true; cmd_setup_ci_token "$@" ;;
  -h|--help|"")    usage; exit 0 ;;
  *)               echo "Unknown subcommand: $1" >&2; usage; exit 1 ;;
esac
