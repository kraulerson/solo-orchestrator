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

# _phase2_push_scaffold <push-command…> — `## BL-323:` the scaffold push, the one
# owner for init.sh (both host branches) and check-gate.sh --repair. Runs
# "<push-command…> main", then "<push-command…> master" when that fails;
# returns 0 when either lands.
#
# BL-323-SCAFFOLD-ATTEST: init.sh installs the pre-push review gate
# (`# BL-243-HOOK-TEMPLATE`) before this push, and a new project has no review on
# record, so the gate refused the push and the new remote stayed empty. The
# scaffold holds no operator code to review, so each attempt takes the gate's
# own attested escape with a fixed reason, which check-pr-review.sh writes to
# .claude/process-state.json::pr_review_attestations[] with the date and the
# pushed commit. The pair is set on the push command alone and never exported,
# so no later push inherits it; the gate never counts an attestation as a
# review, so the next ordinary push still needs one. The reason is true of
# init.sh's push, which carries only the scaffold commit; --repair pushes the
# branch as it stands, which can hold commits made after init (`## BL-323:`
# records that residual).
#
# BL-323-FIRST-ERROR: neither attempt is silenced. The `main` attempt's stderr
# used to go to /dev/null, so a refusal reached the operator as the `master`
# fallback's unrelated "src refspec master does not match any".
_phase2_push_scaffold() {
  local reason="initial scaffold push: framework-generated files only, no operator code to review"
  local branch=""
  if SOLO_PR_REVIEW_ATTESTED=1 SOLO_PR_REVIEW_ATTESTED_REASON="$reason" "$@" main; then
    return 0
  fi
  echo "[INFO] Pushing 'main' did not work (git's message is above); trying 'master'..." >&2
  if SOLO_PR_REVIEW_ATTESTED=1 SOLO_PR_REVIEW_ATTESTED_REASON="$reason" "$@" master; then
    return 0
  fi
  if git rev-parse -q --verify refs/heads/main >/dev/null 2>&1; then
    echo "  Why: the push of 'main' failed. git's own words are the FIRST error above; the 'master' attempt after it is only the fallback for a project whose branch is 'master'." >&2
  elif git rev-parse -q --verify refs/heads/master >/dev/null 2>&1; then
    echo "  Why: the push of 'master' failed. git's own words are the LAST error above; this project has no 'main', so the first attempt could not work." >&2
  else
    branch="$(git symbolic-ref --short -q HEAD 2>/dev/null || printf '')"
    if [ -n "$branch" ]; then branch="branch '$branch'"; else branch="a detached HEAD"; fi
    echo "  Why: this project has neither a 'main' nor a 'master' branch (it is on $branch), so there was nothing to push." >&2
  fi
  return 1
}
