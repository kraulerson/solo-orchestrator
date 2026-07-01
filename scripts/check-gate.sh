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
  --backfill-host   Infer host from git remote URL and write to manifest.

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
  local attest_reason=""
  if [ -f .claude/process-state.json ]; then
    attest_reason=$(jq -r '.phase2_init.attestations.branch_protection.reason // ""' \
                       .claude/process-state.json 2>/dev/null || echo "")
  fi
  if [ "$attest_reason" = "github_free_tier" ]; then
    print_ok "Ready: branch protection attested (reason: github_free_tier — upgrade to GitHub Pro to enable API enforcement)"
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
      || { print_fail "Protection config failed"; return 1; }
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
  -h|--help|"")    usage; exit 0 ;;
  *)               echo "Unknown subcommand: $1" >&2; usage; exit 1 ;;
esac
