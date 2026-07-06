# scripts/lib/cdf-refresh.sh — Solo-side thin wrapper around CDF's
# canonical refresh_cdf_assets (BL-001).
#
# THE PROBLEM (BL-001)
#   Development Guardrails (CDF) ships hooks/rules/gates into a project's
#   .claude/framework/ subtree at first install (init.sh). Before this
#   wiring, scripts/upgrade-project.sh performed NO CDF sync — a project
#   that ran the documented upgrade stayed frozen at its install-time CDF
#   version, silently missing upstream .claude/framework/ hook/rule/gate
#   fixes.
#
# THE FIX (cross-repo split, Karl 2026)
#   The refresh LOGIC lives UPSTREAM in the CDF clone at
#   $CDF_HOME/scripts/cdf-refresh.sh (refresh_cdf_assets), so CDF-only
#   projects can use it standalone. Solo carries only THIS thin call-site
#   wrapper, which:
#     1. Locates the CDF clone (default $HOME/.claude-dev-framework;
#        overridable via CDF_HOME for hermetic/testable invocation).
#     2. Sources the clone's scripts/cdf-refresh.sh and delegates to
#        refresh_cdf_assets "$PROJECT_ROOT" "$CDF_HOME" "$NON_INTERACTIVE".
#
# GRACEFUL DEGRADATION (critical — never hard-fail the upgrade)
#   If the CDF clone or its scripts/cdf-refresh.sh is absent, emit a clear
#   [WARN] to stderr and return 0. The upgrade keeps the project's existing
#   .claude/framework/ assets and proceeds. The upstream refresh_cdf_assets
#   itself extends this contract:
#     • missing clone + non-interactive → warn + return 0 (no prompt);
#     • `git pull --ff-only` failure     → warn + proceed with current tree.
#
# Usage (sourced):
#   source "$SCRIPT_DIR/lib/cdf-refresh.sh"
#   solo_refresh_cdf "$PROJECT_ROOT" "$NON_INTERACTIVE"
#
# shellcheck shell=bash

# Print to stderr. Mirrors the upstream cdf-refresh.sh `[WARN]`/`[INFO]`
# style so the two layers read as one voice, without depending on
# helpers.sh being sourced (this wrapper may run before/without it).
_solo_cdf_warn() { echo "  [WARN] $*" >&2; }
_solo_cdf_info() { echo "  [INFO] $*" >&2; }

# solo_refresh_cdf PROJECT_ROOT [NON_INTERACTIVE]
#   PROJECT_ROOT     — directory containing .claude/framework/.
#   NON_INTERACTIVE  — "true" or "false" (default "false"); passed through
#                      to refresh_cdf_assets so it can skip prompts.
# Returns 0 on success OR graceful skip. The caller must treat any
# non-zero return as non-fatal (the CDF sync is an ADDITION to the
# upgrade, never a gate on it).
solo_refresh_cdf() {
  local project_root="$1"
  local non_interactive="${2:-false}"

  # CDF clone location. CDF_HOME override keeps the refresh hermetic and
  # testable (point it at a fake clone); default is the canonical clone.
  local cdf_home="${CDF_HOME:-$HOME/.claude-dev-framework}"
  local upstream="$cdf_home/scripts/cdf-refresh.sh"

  # Graceful skip: no upstream implementation to source. This covers both
  # "clone entirely missing" and "clone present but lacks the refresh
  # script" — in either case there is nothing to sync from, so warn and
  # return 0 rather than aborting the upgrade.
  if [ ! -f "$upstream" ]; then
    _solo_cdf_warn "CDF refresh script not found at $upstream — skipping CDF asset refresh."
    _solo_cdf_info "Your project keeps its existing .claude/framework/ hooks/rules/gates."
    _solo_cdf_info "To enable CDF sync: git clone https://github.com/kraulerson/claude-dev-framework.git $cdf_home"
    return 0
  fi

  # Source the canonical upstream implementation. `if !` disables the
  # caller's `set -e` for this command so a source failure degrades
  # gracefully instead of aborting the upgrade.
  # shellcheck source=/dev/null
  if ! . "$upstream"; then
    _solo_cdf_warn "Failed to source CDF refresh script at $upstream — skipping CDF asset refresh."
    return 0
  fi

  # Defensive: the sourced file should define refresh_cdf_assets. If a
  # future upstream rename breaks the contract, skip loudly rather than
  # erroring under set -e.
  if ! command -v refresh_cdf_assets >/dev/null 2>&1; then
    _solo_cdf_warn "refresh_cdf_assets not defined after sourcing $upstream — skipping CDF asset refresh."
    return 0
  fi

  # Delegate to the canonical implementation. It handles the copy of
  # hooks/rules/gates, chmod +x, manifest frameworkVersion/frameworkCommit
  # bump, and its own graceful-skip contract (missing .git, pull failure).
  refresh_cdf_assets "$project_root" "$cdf_home" "$non_interactive"
}
