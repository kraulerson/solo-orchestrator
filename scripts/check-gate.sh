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

# shellcheck disable=SC1090
source "$SCRIPT_DIR/lib/helpers.sh" 2>/dev/null || {
  # Minimal fallback if helpers not available (e.g., pre-init migration scenario)
  print_step() { echo "[STEP] $*"; }
  print_ok()   { echo "  [OK] $*"; }
  print_fail() { echo "[FAIL] $*" >&2; }
  print_info() { echo "[INFO] $*"; }
  print_warn() { echo "[WARN] $*"; }
  log_line()   { :; }
  # Wave-3 raw-read sweep: prompt_yes_no fallback honors the same
  # non-interactive hard-N contract as the helpers.sh version. Reached
  # only in pre-init migration scenarios where lib/helpers.sh is
  # absent; behavior must match the canonical helper so the manifest
  # mutation in --backfill-host below stays consistent.
  prompt_yes_no() {
    local message="$1" default_answer="${2:-N}"
    if [ ! -t 0 ] || [ -n "${CI:-}" ] || [ -n "${SOIF_NONINTERACTIVE:-}" ]; then
      echo "[WARN] Non-interactive context: skipping prompt (\"$message\") — defaulting to 'N' (caller default '$default_answer' ignored)." >&2
      return 1
    fi
    local reply
    read -rp "${message}: " reply # lint-raw-read-prompt: allow fallback prompt_yes_no defined inline when lib/helpers.sh is absent (pre-init migration scenario); semantically equivalent to lib/helpers.sh::prompt_yes_no
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
  # shellcheck disable=SC1090
  source "$SCRIPT_DIR/lib/host.sh"
  host_load_driver || {
    print_fail "Dispatcher load failed — run --backfill-host first"
    return 1
  }
  local mode
  mode=$(jq -r '.mode // "personal"' .claude/manifest.json)

  # Step order: create (skip if exists) → register → push → configure → verify
  if ! git remote get-url origin >/dev/null 2>&1; then
    local name visibility
    if [ -f .claude/intake-progress.json ]; then
      name=$(jq -r '.answers.project_name // empty' .claude/intake-progress.json)
      visibility=$(jq -r '.answers.repo_visibility // "private"' .claude/intake-progress.json)
    fi
    name="${name:-$(basename "$(pwd)")}"
    visibility="${visibility:-private}"
    print_info "No origin configured — creating $visibility repo '$name' on $(host_name)..."
    local url
    url=$(host_create_repo "$name" "$visibility") || { print_fail "Repo creation failed"; return 1; }
    host_register_remote "$url"
    host_push_initial main 2>/dev/null || host_push_initial master || {
      print_fail "Push failed — see driver error above"
      return 1
    }
    print_ok "Remote created and pushed at $url"
  fi

  print_info "Re-applying protection for $mode mode..."
  host_configure_protection main "$mode" 2>/dev/null || host_configure_protection master "$mode" \
    || { print_fail "Protection config failed"; return 1; }
  # Short retry for API lag
  if ! host_verify_protection main "$mode" 2>/dev/null && ! host_verify_protection master "$mode"; then
    sleep 5
    host_verify_protection main "$mode" 2>/dev/null || host_verify_protection master "$mode" \
      || { print_fail "Verification still failing — check host UI"; return 1; }
  fi
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
