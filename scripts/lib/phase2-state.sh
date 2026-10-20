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
# record, so the gate refused the push and the new remote stayed empty. A branch
# that is init's scaffold and nothing else holds no operator code to review, so
# its push takes the gate's own attested escape with a fixed reason, which
# check-pr-review.sh writes to .claude/process-state.json::pr_review_attestations[]
# with the date and the pushed commit. The pair is set on the push command alone
# and never exported, so no later push inherits it; the gate never counts an
# attestation as a review, so the next ordinary push still needs one. A branch
# that holds anything else is pushed as ordinary work (`_phase2_scaffold_only`).
#
# BL-323-FIRST-ERROR: neither attempt is silenced. The `main` attempt's stderr
# used to go to /dev/null, so a refusal reached the operator as the `master`
# fallback's unrelated "src refspec master does not match any".
_phase2_push_scaffold() {
  local branch=""
  if _phase2_push_attempt main "$@"; then
    return 0
  fi
  echo "[INFO] Pushing 'main' did not work (git's message is above); trying 'master'..." >&2
  if _phase2_push_attempt master "$@"; then
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

# _phase2_push_attempt <branch> <push-command…> — one attempt of the above. The
# attested pair goes on the push only when the branch is init's scaffold and
# nothing else; any other branch is pushed without it, after a plain sentence
# saying why the review check will want a review.
_phase2_push_attempt() {
  local b="$1" reason="initial scaffold push: framework-generated files only, no operator code to review"
  shift
  if _phase2_scaffold_only "$b"; then
    SOLO_PR_REVIEW_ATTESTED=1 SOLO_PR_REVIEW_ATTESTED_REASON="$reason" "$@" "$b"
    return $?
  fi
  # A branch that does not exist fails at git's refspec check, before any hook:
  # nothing to explain.
  if git rev-parse -q --verify "refs/heads/$b" >/dev/null 2>&1; then
    if git rev-parse -q --verify "$_PHASE2_SCAFFOLD_REF" >/dev/null 2>&1; then
      echo "[INFO] '$b' holds commits init.sh did not make (work since init, or history from before it), so it is pushed as ordinary work: the pre-push review check needs a review on record for it." >&2
    else
      echo "[INFO] This project has no record of init's scaffold commit ($_PHASE2_SCAFFOLD_REF: init found the directory already in use, the project predates that record, or this is a clone), so '$b' is pushed as ordinary work: the pre-push review check needs a review on record for it." >&2
    fi
    echo "  Record the review:  scripts/record-pr-review.sh --verdict <the reviewer's verdict>   then push:  scripts/check-gate.sh --repair" >&2
    echo "  (Or attest with your own reason; the check's own message below says how.)" >&2
  fi
  "$@" "$b"
}

# BL-323-SCAFFOLD-REF: init's scaffold commit, as a local ref. A ref, not a field in
# a tracked file: writing it changes no tracked file (a --no-remote-creation
# scaffold stays one clean commit), it is never pushed with a branch, and a clone
# does not carry it, so a copy of the project elsewhere fails closed.
_PHASE2_SCAFFOLD_REF="refs/solo-orchestrator/scaffold"

# _phase2_record_scaffold — called by init.sh right after its scaffold commit, and
# only when init created the project directory or found it empty. Records HEAD
# when it is a root commit; returns 1 and records nothing otherwise.
_phase2_record_scaffold() {
  local sha=""
  sha="$(git rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null || printf '')"
  [ -n "$sha" ] || return 1
  [ "$(git rev-list --parents -n 1 "$sha" 2>/dev/null)" = "$sha" ] || return 1
  git update-ref "$_PHASE2_SCAFFOLD_REF" "$sha"
}

# _phase2_scaffold_only <branch> — 0 when everything on <branch> is init's: its tip
# is the recorded scaffold commit, or one commit on it that changes only the two
# state files init's finalize commit writes. Anything else — no record, a record
# that is not a root commit (history under the scaffold), more commits, a merge,
# any other file — is 1. BL-323-SCAFFOLD-ONLY: this is what keeps the fixed
# reason true; measured, the branch alone (with no such check) carried operator
# commits under it through --repair and through init --allow-existing-dir.
_phase2_scaffold_only() {
  local b="$1" rec="" tip="" f=""
  rec="$(git rev-parse -q --verify "$_PHASE2_SCAFFOLD_REF^{commit}" 2>/dev/null || printf '')"
  tip="$(git rev-parse -q --verify "refs/heads/$b^{commit}" 2>/dev/null || printf '')"
  [ -n "$rec" ] && [ -n "$tip" ] || return 1
  [ "$(git rev-list --parents -n 1 "$rec" 2>/dev/null)" = "$rec" ] || return 1
  [ "$tip" = "$rec" ] && return 0
  [ "$(git rev-list --parents -n 1 "$tip" 2>/dev/null)" = "$tip $rec" ] || return 1
  while IFS= read -r f; do
    case "$f" in
      .claude/manifest.json|.claude/process-state.json) ;;
      *) return 1 ;;
    esac
  done <<EOF
$(git diff-tree --no-commit-id --name-only -r "$tip" 2>/dev/null)
EOF
  return 0
}
