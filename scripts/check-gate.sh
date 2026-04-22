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
}

usage() {
  cat <<'EOM'
Usage: check-gate.sh <subcommand>

Subcommands:
  --preflight       Dry-run: check current protection status without modifying anything.
                    Exits 0 if ready to cross Phase 1→2, non-zero if blocked.
  --repair          Re-run repo setup from last successful step (idempotent).
  --backfill-host   Infer host from git remote URL and write to manifest.
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
  read -rp "Confirm this is correct? [y/N]: " yn
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

case "${1:-}" in
  --preflight)     shift || true; cmd_preflight "$@" ;;
  --repair)        shift || true; cmd_repair "$@" ;;
  --backfill-host) shift || true; cmd_backfill_host "$@" ;;
  -h|--help|"")    usage; exit 0 ;;
  *)               echo "Unknown subcommand: $1" >&2; usage; exit 1 ;;
esac
