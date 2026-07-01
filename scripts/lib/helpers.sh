#!/usr/bin/env bash
# Solo Orchestrator — Shared Script Helpers (backwards-compat shim)
#
# BL-046 (PR #<N>, 2026-06-30): helpers.sh was split into two files
# to give short-lived callers (check-versions.sh, check-updates.sh,
# check-changelog.sh, check-session-state.sh, validate.sh,
# check-gate.sh, ...) a smaller parse cost per invocation:
#   - scripts/lib/helpers-core.sh — print_*, prompt_*, log_line,
#     run_with_timeout, guard_not_in_framework (the minimum set
#     every caller uses).
#   - scripts/lib/helpers-full.sh — init_log/finalize_log +
#     MCP-detection helpers (only long-running init.sh /
#     upgrade-project.sh / intake-wizard.sh /
#     reconfigure-project.sh / verify-install.sh need these).
#
# This shim exists so every existing caller that sources
# `scripts/lib/helpers.sh` — including third-party / user scripts,
# pinned CDF installs, and older cached copies — continues to
# receive the FULL API without any code change. Short-lived callers
# were migrated in the same PR to source helpers-core.sh directly.
#
# Do NOT add new function definitions here. Add them to
# helpers-core.sh (if they're small + universally used) or
# helpers-full.sh (if they're heavy or narrowly needed).

# Idempotent-source guard (in addition to the guards in core+full).
if [ -n "${_SOIF_HELPERS_SHIM_LOADED:-}" ]; then
  return 0
fi
_SOIF_HELPERS_SHIM_LOADED=1

# Fast-path dirname via parameter expansion (no subshell / no dirname fork).
# ${BASH_SOURCE[0]%/*} strips the trailing "/helpers.sh". If BASH_SOURCE
# has no slash (unlikely — happens only when sourced by exact filename
# from cwd), fall back to "." which resolves against the caller's cwd.
_SOIF_HELPERS_SHIM_DIR="${BASH_SOURCE[0]%/*}"
[ "$_SOIF_HELPERS_SHIM_DIR" = "${BASH_SOURCE[0]}" ] && _SOIF_HELPERS_SHIM_DIR="."
# shellcheck source=./helpers-full.sh
source "$_SOIF_HELPERS_SHIM_DIR/helpers-full.sh"
