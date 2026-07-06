#!/usr/bin/env bash
# scripts/lib/phase2-state.sh — shared helpers for reading/writing
# .claude/process-state.json phase2_init state.
#
# Pre-existing context: init.sh's create_and_protect_remote used to define
# _record_phase2_step as an inner function, which made it inaccessible to
# scripts/check-gate.sh::cmd_repair. cmd_repair could read steps_completed
# (added in audit finding specs-plans-host-aware-11) but had no way to
# write back after a successful resume step — leaving the state file as a
# lying source of truth (verifier follow-up to PR #97).
#
# This file lifts the helper to a shared lib so both init.sh and
# check-gate.sh write through the exact same code path, giving us a single
# audit-grep surface for future drift.
#
# Resolves the process-state path relative to the caller's git repo root
# (or cwd if not in a git repo) so the helper works from any subdirectory.

_phase2_state_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

# _record_phase2_step <step_name>
# Appends step_name to phase2_init.steps_completed in process-state.json,
# creating the file (and .claude/) if missing. Idempotent — the unique
# filter keeps duplicates from accumulating on resumed runs. Writes
# atomically via a .tmp file + mv.
_record_phase2_step() {
  local step_name="${1:?_record_phase2_step: step name required}"
  local root
  root="$(_phase2_state_repo_root)"
  mkdir -p "$root/.claude"
  local ps="$root/.claude/process-state.json"
  if [ ! -f "$ps" ]; then
    echo '{"phase2_init":{"steps_completed":[],"attestations":{}}}' > "$ps"
  fi
  jq --arg s "$step_name" \
     '(.phase2_init.steps_completed // []) as $cur | .phase2_init.steps_completed = (($cur + [$s]) | unique)' \
     "$ps" > "$ps.tmp" \
     && mv "$ps.tmp" "$ps"
}
