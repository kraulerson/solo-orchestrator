#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — PreToolUse hook for commit gating
# Blocks git commit and gh pr create when process checklist is incomplete.
# Registered as a PreToolUse hook on Bash tool calls.
#
# Input: Claude Code passes tool input JSON on stdin
# Output:
#   - No output = allow
#   - JSON with permissionDecision: "deny" = block

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# BL-072 Phase C1: shared TDD file-classification core. Sourced (not
# re-implemented) so the live gate below and the dogfood replay
# (tests/test-helpers/dogfood-bl072-replay.sh) classify changed paths
# identically. Absent (e.g. an older installed project) -> the detector
# no-ops, which is safe because C1 is WARN-only. Prefer the project-local
# copy, fall back to the framework copy.
for _tdd_lib in "$SCRIPT_DIR/lib/tdd-classify.sh"; do
  if [ -f "$_tdd_lib" ]; then
    # shellcheck source=scripts/lib/tdd-classify.sh
    . "$_tdd_lib"
    break
  fi
done
unset _tdd_lib

# ── BL-072 Phase C2: tier-keyed TDD-ordering hard block ──────────────
# C1 (PR #163) shipped the detector in WARN-only measurement mode. C2 makes it
# a real gate whose severity is keyed on the project TIER:
#   • BYPASSABLE tier (Personal / Private-POC): WARN only; the bypass is LOGGED
#     to .claude/tdd-warn-ledger.jsonl (that log IS the audit trail).
#   • NON-bypassable tier (Sponsored-POC / Production): HARD BLOCK, unless the
#     operator attests the exception (SOLO_TDD_ATTESTED=1) — which is RECORDED
#     to .claude/process-state.json::tdd_attestations[] (attested, not silenced
#     — BL-032/071 lineage).
# The hard block is emitted on the git COMMIT-MSG hook surface, reached via
# `pre-commit-gate.sh --terminal-mode --tdd-only` (a non-zero exit aborts the
# commit). commit-msg is the only git-hook point where .git/COMMIT_EDITMSG holds
# the CURRENT commit message — a pre-commit hook sees a STALE message (git
# writes it after pre-commit), which is why the message-scoped gate cannot live
# there. The PreToolUse path keeps its C1 WARN detector as a pre-execution
# measurement heads-up (it reads the subject from the Bash command, not the
# hook file); the commit-msg hook is the enforcement point for both agent and
# human commits. These helpers are defined up here so the --terminal-mode block
# below (which runs and exits before the PreToolUse body) can call them.

# _bl072_tier_bypassable
# BL-084-TIER-KEY. SYNC SIBLINGS — keep these three semantically identical:
#   init.sh::_bl084_tier_bypassable  ·  scripts/check-phase-gate.sh Phase 1->2
#   push gate  ·  this predicate. Bypass-eligibility is the ACTUAL project tier
#   (deployment + poc_mode from .claude/phase-state.json), NEVER `track`:
#   BL-084 proved `track` is spoofable (--track light on a sponsored/production
#   project). This reads the file directly (the siblings read shell/local vars
#   they already hold); the SEMANTICS — not the read mechanism — must match.
#
# MOTHERSHIP SAFETY (hard requirement): a missing .claude/phase-state.json OR a
# missing/empty deployment key => BYPASSABLE (WARN-only). solo-orchestrator
# itself runs this hook on every commit and is NOT a framework-scaffolded
# project; C2 must NEVER hard-block a repo that has no scaffolded tier.
#
# Returns 0 (BYPASSABLE) iff deployment != organizational AND
# poc_mode != sponsored_poc. Returns 1 (NON-bypassable) otherwise.
_bl072_tier_bypassable() {
  local ps=".claude/phase-state.json"
  local deployment="" poc_mode=""
  if [ -f "$ps" ] && command -v jq >/dev/null 2>&1; then
    deployment=$(jq -r '.deployment // ""' "$ps" 2>/dev/null || echo "")
    poc_mode=$(jq -r '.poc_mode // ""' "$ps" 2>/dev/null || echo "")
    [ "$deployment" = "null" ] && deployment=""
    [ "$poc_mode" = "null" ] && poc_mode=""
  fi
  # Mothership safety: no scaffolded tier -> bypassable (never hard-block).
  [ -z "$deployment" ] && return 0
  if [ "$deployment" = "organizational" ] || [ "$poc_mode" = "sponsored_poc" ]; then  # BL-084-TIER-KEY
    return 1
  fi
  return 0
}

# _tdd_triggers <subject> <staged_name_status>
# Returns 0 iff the commit should TRIGGER the TDD gate:
#   • subject is a feat/fix/refactor Conventional-Commit,
#   • the staged set (git name-status) has >=1 implementation file and 0 test
#     files (deletions / *.md / lockfiles already excluded by the classifier),
#   • AND no test rode earlier on the branch (git diff <base>...HEAD).
# Pure detection, mode-independent: both the PreToolUse WARN path and the
# --terminal-mode enforcement call it (single source of truth). set -e safe.
_tdd_triggers() {
  local subject="$1" staged="$2"
  echo "$subject" | grep -qE '^(feat|fix|refactor)(\([^)]*\))?!?:' || return 1
  command -v _bl072_classify_status >/dev/null 2>&1 || return 1
  local counts n_impl n_test
  counts=$(printf '%s\n' "$staged" | _bl072_classify_status)
  n_impl=${counts#IMPL:}; n_impl=${n_impl%% *}
  n_test=${counts##*TEST:}
  [ "${n_impl:-0}" -gt 0 ] 2>/dev/null || return 1
  [ "${n_test:-0}" -eq 0 ] 2>/dev/null || return 1
  local base=""
  if git rev-parse --verify --quiet main >/dev/null 2>&1; then
    base="main"
  elif git rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
    base="origin/main"
  fi
  if [ -n "$base" ]; then
    local branch_status bcounts b_test
    branch_status=$(git diff --name-status "$base"...HEAD 2>/dev/null || true)
    bcounts=$(printf '%s\n' "$branch_status" | _bl072_classify_status)
    b_test=${bcounts##*TEST:}
    [ "${b_test:-0}" -gt 0 ] 2>/dev/null && return 1
  fi
  return 0
}

# tdd_ledger_row_ext <subject> <impl_files> <status>
# Append one tier-aware row to .claude/tdd-warn-ledger.jsonl. status ∈
# bypassed|attested|blocked. Keeps would_block:true for C1 continuity and adds
# deployment/poc_mode + the disposition flags. Never fails the caller.
tdd_ledger_row_ext() {
  local subject="$1" files="$2" status="$3"
  command -v jq >/dev/null 2>&1 || return 0
  local ledger=".claude/tdd-warn-ledger.jsonl"
  [ -d .claude ] || mkdir -p .claude 2>/dev/null || return 0
  local files_json
  files_json=$(printf '%s\n' "$files" | grep -v '^[[:space:]]*$' | jq -R . 2>/dev/null | jq -s . 2>/dev/null) || return 0
  [ -n "$files_json" ] || files_json='[]'
  local dep="" poc=""
  if [ -f .claude/phase-state.json ]; then
    dep=$(jq -r '.deployment // ""' .claude/phase-state.json 2>/dev/null || echo "")
    poc=$(jq -r '.poc_mode // ""' .claude/phase-state.json 2>/dev/null || echo "")
    [ "$dep" = "null" ] && dep=""
    [ "$poc" = "null" ] && poc=""
  fi
  local bypassed=false attested=false blocked=false
  case "$status" in
    bypassed) bypassed=true ;;
    attested) attested=true ;;
    blocked)  blocked=true ;;
  esac
  local row
  row=$(jq -cn \
    --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg subject "$subject" \
    --arg deployment "$dep" \
    --arg poc_mode "$poc" \
    --argjson files "$files_json" \
    --argjson bypassed "$bypassed" \
    --argjson attested "$attested" \
    --argjson blocked "$blocked" \
    '{date:$date, subject:$subject, files:$files, would_block:true, deployment:$deployment, poc_mode:$poc_mode, bypassed:$bypassed, attested:$attested, blocked:$blocked}' 2>/dev/null) || return 0
  printf '%s\n' "$row" >> "$ledger" 2>/dev/null || return 0
  return 0
}

# tdd_record_attestation <subject> <impl_files> <reason>
# Atomically append {date,subject,reason,files} to
# .claude/process-state.json::tdd_attestations[] (tmp+mv, BL-071 lineage).
# Returns 0 on a durable write, 1 on ANY failure — the caller MUST be loud and
# REFUSE the commit on failure (attested, never silently passed).
tdd_record_attestation() {
  local subject="$1" files="$2" reason="$3"
  command -v jq >/dev/null 2>&1 || return 1
  [ -d .claude ] || mkdir -p .claude 2>/dev/null || return 1
  local ps=".claude/process-state.json"
  if [ ! -f "$ps" ]; then
    printf '%s\n' '{}' > "$ps" 2>/dev/null || return 1
  fi
  local files_json
  files_json=$(printf '%s\n' "$files" | grep -v '^[[:space:]]*$' | jq -R . 2>/dev/null | jq -s . 2>/dev/null) || return 1
  [ -n "$files_json" ] || files_json='[]'
  local tmp="$ps.tmp.$$"
  if jq \
      --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg subject "$subject" \
      --arg reason "$reason" \
      --argjson files "$files_json" \
      '.tdd_attestations = ((.tdd_attestations // []) + [{date:$date, subject:$subject, reason:$reason, files:$files}])' \
      "$ps" > "$tmp" 2>/dev/null && mv "$tmp" "$ps" 2>/dev/null; then
    return 0
  fi
  rm -f "$tmp" 2>/dev/null || true
  return 1
}

# tdd_emit_warn_term <subject> <impl_files>  — bypassable-tier WARN (stderr).
tdd_emit_warn_term() {
  local subject="$1" files="$2" type
  type=$(printf '%s' "$subject" | sed -nE 's/^(feat|fix|refactor).*/\1/p')
  {
    echo "[WARN] BL-072 TDD ordering: '$type:' commit ships implementation without a matching test."
    echo "[WARN]   Subject: $subject"
    echo "[WARN]   Tier is BYPASSABLE (personal / private POC) — allowing, but the bypass is LOGGED"
    echo "[WARN]   to .claude/tdd-warn-ledger.jsonl. On a sponsored-POC / production tier this commit"
    echo "[WARN]   WOULD BE BLOCKED. Impl files with no accompanying test (none earlier on the branch):"
    printf '%s\n' "$files" | grep -v '^[[:space:]]*$' | sed 's/^/[WARN]     - /' || true
  } >&2
}

# tdd_emit_fail_term <subject> <impl_files>  — non-bypassable-tier BLOCK (stderr).
tdd_emit_fail_term() {
  local subject="$1" files="$2" type
  type=$(printf '%s' "$subject" | sed -nE 's/^(feat|fix|refactor).*/\1/p')
  {
    echo "[FAIL] BL-072 TDD ordering: '$type:' commit ships implementation without a matching test."
    echo "[FAIL]   Subject: $subject"
    echo "[FAIL]   Tier is NON-bypassable (sponsored POC / production) — test-first ordering is ENFORCED."
    echo "[FAIL]   Impl files with no accompanying test (none earlier on the branch):"
    printf '%s\n' "$files" | grep -v '^[[:space:]]*$' | sed 's/^/[FAIL]     - /' || true
    echo "[FAIL]   Write the failing test first (test-driven), then re-commit."
    echo "[FAIL]   To attest a legitimate exception (RECORDED to tdd_attestations[], not silenced):"
    echo "[FAIL]     SOLO_TDD_ATTESTED=1 SOLO_TDD_REASON='<why a same-commit test is impractical>' git commit ..."
    echo "[FAIL]   The commit is BLOCKED."
  } >&2
}

# tdd_terminal_enforce  — the tier-keyed gate, invoked from the generated
# COMMIT-MSG hook via `--terminal-mode --tdd-only`. Reads the prospective
# subject from COMMIT_MSG (from .git/COMMIT_EDITMSG, which is CURRENT at
# commit-msg time) and the staged name-status from git. Returns 0 to ALLOW
# (silent / WARN / attested), 1 to BLOCK (caller exits 1 -> git aborts commit).
tdd_terminal_enforce() {
  # Derivative commit: a merge in progress is not a TDD-authoring event.
  [ -f .git/MERGE_HEAD ] && return 0
  command -v _tdd_triggers >/dev/null 2>&1 || return 0   # classifier absent -> no-op (safe)

  local subject staged_status
  subject=$(printf '%s\n' "${COMMIT_MSG:-}" | head -n 1)
  staged_status=$(git diff --cached --name-status 2>/dev/null || true)

  local _fire=0
  _tdd_triggers "$subject" "$staged_status" && _fire=1   # BL-072-TDD-DETECT
  [ "$_fire" = "1" ] || return 0

  local impl_files
  impl_files=$(printf '%s\n' "$staged_status" | _bl072_impl_files)

  if _bl072_tier_bypassable; then
    tdd_emit_warn_term "$subject" "$impl_files"
    tdd_ledger_row_ext "$subject" "$impl_files" bypassed
    return 0
  fi

  # NON-bypassable tier — attested escape or hard block.  # BL-072-TDD-ENFORCE
  if [ "${SOLO_TDD_ATTESTED:-0}" = "1" ]; then
    local reason="${SOLO_TDD_REASON:-unspecified - attested via SOLO_TDD_ATTESTED}"
    if tdd_record_attestation "$subject" "$impl_files" "$reason"; then
      tdd_ledger_row_ext "$subject" "$impl_files" attested
      echo "[OK] BL-072 TDD ordering: NON-bypassable tier, but the exception was ATTESTED and RECORDED to .claude/process-state.json::tdd_attestations[] (reason: $reason). Commit allowed (recorded, not silenced)." >&2
      return 0
    fi
    # LOUD failure — an attested escape MUST be on the record; never a silent pass.
    echo "[FAIL] BL-072 TDD ordering: SOLO_TDD_ATTESTED=1 but the attestation could NOT be recorded to .claude/process-state.json (jq/write failure). REFUSING the commit — an attested escape must be durably logged. Fix the write error (disk/permissions/jq) and retry, or add the missing test." >&2
    return 1
  fi

  tdd_emit_fail_term "$subject" "$impl_files"
  tdd_ledger_row_ext "$subject" "$impl_files" blocked
  return 1   # BL-072-TDD-ENFORCE (hard block)
}
# ── end BL-072 Phase C2 block ────────────────────────────────────────

# ── BL-010: BL-006 Build-Loop commit-message check at the commit-msg surface ──
# BL-006 (PR #15) enforces "a feat: commit requires an active, sufficiently
# complete Build Loop". Until now it ran ONLY on the AI-tooling PreToolUse
# surface (bl006_check, far below). Editor-opened commits (`git commit` with no
# -m) and human-terminal commits never faced it — the residual BL-010 closes.
# This function runs the SAME policy subcommand
# (process-checklist.sh --check-commit-message) at COMMIT-MSG time, where
# .git/COMMIT_EDITMSG holds the CURRENT message, so it reaches exactly those two
# populations. It is invoked from the --tdd-only commit-msg surface (the
# generated commit-msg hook) alongside the C2 TDD gate.
#
# SEMANTIC PARITY with the PreToolUse bl006_check: identical delegate, identical
# message (first line / subject), identical block conditions and remediation.
# Derivative commits that the PreToolUse path passes through via command-string
# filters are passed through here via their commit-msg-time git sentinels
# (MERGE_HEAD / CHERRY_PICK_HEAD / REVERT_HEAD). MOTHERSHIP SAFETY: two layers —
# (1) no-op when the project has no scripts/process-checklist.sh (a repo that
# predates BL-006, or the framework repo itself, which is NOT a scaffolded
# project); (2) check_commit_message phase-gates (current_phase < 2 -> exit 0).
# Returns 0 to ALLOW, non-zero to BLOCK (caller exits 1 -> git aborts commit).
bl006_terminal_enforce() {
  # Derivative commits: git writes these sentinels at commit-msg time. Mirrors
  # the PreToolUse bl006_check merge/revert/cherry-pick pass-throughs (the
  # PreToolUse path detects them from the command string; at commit-msg time the
  # sentinel files are the equivalent, current signal).
  [ -f .git/MERGE_HEAD ] && return 0
  [ -f .git/CHERRY_PICK_HEAD ] && return 0
  [ -f .git/REVERT_HEAD ] && return 0
  # BL-087-MOTHERSHIP-PASS — the framework repo is NOT a scaffolded project,
  # but it DOES contain scripts/process-checklist.sh, so the "no checklist ->
  # no-op" layer below cannot protect it: the delegate would hard-refuse via
  # guard_not_in_framework (rc=1) and, with a commit-msg hook installed in the
  # framework repo itself, every feat:/fix: commit would brick. Detect the
  # framework root with the guard's OWN signature (keep in sync with
  # helpers-core.sh::guard_not_in_framework::_gnif_dir_is_framework) and pass
  # GRACEFULLY — with a receipt, because a silent pass is indistinguishable
  # from a gate that never ran.
  if [ -f init.sh ] \
     && grep -q "Solo Orchestrator — Project Initialization Script" init.sh 2>/dev/null \
     && [ -d templates/generated ]; then
    echo "[note] BL-006 message gate: framework repo detected (not a scaffolded project) — Build-Loop message enforcement not applicable here. Commit allowed." >&2
    return 0
  fi
  # No project checklist -> nothing to enforce (safe no-op). CWD-relative on
  # purpose: the commit-msg hook runs from the project root, and this must NOT
  # resolve to the framework's own copy for a repo that has no scaffolded state.
  [ -x scripts/process-checklist.sh ] || return 0
  local subject rc=0
  subject=$(printf '%s\n' "${COMMIT_MSG:-}" | head -n 1)
  # Delegate the policy decision to the SAME subcommand the PreToolUse surface
  # uses (identical block conditions + Case A/B remediation). Fold the delegate's
  # stdout into stderr so its whole message reaches the terminal (git hooks
  # ignore stdout). A non-zero exit propagates -> the caller aborts the commit.
  bash scripts/process-checklist.sh --check-commit-message "$subject" >&2 || rc=$?   # BL-010-COMMITMSG-BL006
  return "$rc"
}
# ── end BL-010 block ─────────────────────────────────────────────────

# BL-030: --terminal-mode invocation from .git/hooks/framework-gate.sh.
# Reads commit message from .git/COMMIT_EDITMSG instead of stdin JSON;
# reads staged files from `git diff --cached` instead of tool-input;
# emits human-readable diagnostics to stderr instead of JSON to stdout.
TERMINAL_MODE=0
# --tdd-only (BL-072 C2 + BL-010): scope a --terminal-mode invocation to the
# two MESSAGE-SCOPED commit-msg gates — the tier-keyed TDD-ordering gate
# (BL-072) AND the BL-006 Build-Loop commit-message check (BL-010) — while
# skipping the full process-checklist + operator-side lints that plain
# --terminal-mode runs. The generated commit-msg hook uses
# `--terminal-mode --tdd-only`, so it runs both real gates WITHOUT newly pulling
# the full checklist/lint stack into a hook that never carried them. The flag
# name is retained (rather than renamed) for backward-compat with commit-msg
# hooks already installed by init.sh: those keep working and pick up the added
# BL-006 enforcement as soon as their scripts/pre-commit-gate.sh is refreshed.
TDD_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --terminal-mode) TERMINAL_MODE=1 ;;
    --tdd-only)      TDD_ONLY=1 ;;
  esac
done

if [ "$TERMINAL_MODE" -eq 1 ]; then
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "[FAIL] not a git repo" >&2; exit 1; }
  cd "$PROJECT_ROOT"
  COMMIT_MSG=$(cat .git/COMMIT_EDITMSG 2>/dev/null || echo "")

  # BL-072 Phase C2: tier-keyed TDD-ordering gate. Runs ONLY under --tdd-only,
  # which is how the generated COMMIT-MSG hook invokes the gate. commit-msg time
  # is the ONLY git-hook point where .git/COMMIT_EDITMSG holds the CURRENT commit
  # message (a pre-commit hook sees a STALE message — git writes it AFTER
  # pre-commit runs), and the staged index is still intact there. Plain
  # --terminal-mode (strict-mode framework-gate.sh, chained into .git/hooks/
  # pre-commit) is deliberately left untouched — running the message-scoped TDD
  # gate there would misread the subject. Called in an `if` condition so a
  # non-zero return means "hard block" without set -e aborting mid-function.
  if [ "$TDD_ONLY" -eq 1 ]; then
    if ! tdd_terminal_enforce; then
      exit 1
    fi
    # BL-010: the commit-msg surface ALSO runs the BL-006 Build-Loop
    # commit-message check (bl006_terminal_enforce, defined above), extending
    # BL-006 enforcement to editor-opened and human-terminal commits. Same
    # policy as the PreToolUse surface; a non-zero return aborts the commit.
    if ! bl006_terminal_enforce; then
      exit 1
    fi
    exit 0
  fi

  # BL-119-NO-MSG-AT-PRECOMMIT — plain --terminal-mode deliberately runs NO
  # commit-message check. Its only call site is framework-gate.sh at PRE-COMMIT
  # time, where .git/COMMIT_EDITMSG still holds a PREVIOUS commit's subject
  # (git writes the new message AFTER pre-commit runs). Classifying by that
  # stale subject bricked a strict repo (Dogfood-2 F-DF2-006): after any landed
  # feat: commit, EVERY subsequent commit — docs:, chore:, test:, pure
  # Markdown — was blocked as "'feat(...)' — no Build Loop active", and the
  # gate's own printed remedies are refused/forbidden on the strict tiers. The
  # message-scoped gates (BL-072 TDD ordering + BL-006 Build-Loop check) run
  # at the COMMIT-MSG surface (--tdd-only above), the only git-hook point where
  # the message is CURRENT. Message-independent gates still run at pre-commit:
  # process-checklist --check-commit-ready (framework-gate step 1) and the
  # operator-side lints below. Do not "restore" a message check here — any
  # message this path can read is the wrong one.

  # --- Cycle-8 slot-5: operator-side lint promotion (terminal-mode) ---
  # All four CI lints fire on user-terminal commits too:
  #   - counter-antipattern        (PR #72)
  #   - backlog-references         (PR #76)
  #   - fix-functions-stderr       (cycle-8 wave-3 slot-5, this PR)
  #   - raw-read-prompt            (cycle-8 wave-3 slot-5, this PR)
  # SKIP_LINT=1 escape mirrors the PreToolUse path.
  if [ "${SKIP_LINT:-0}" = "1" ]; then
    echo "[pre-commit-gate] SKIP_LINT=1 set — bypassing all pre-commit lints (counter-antipattern, backlog-references, fix-functions-stderr, raw-read-prompt, tests-registered, no-live-remote-in-tests)" >&2
  else
    # Counter-antipattern: prefer project-local copy (framework installs
    # the script alongside pre-commit-gate.sh in scripts/), fall back to
    # the framework's own copy when running from the framework repo.
    CA_LINT=""
    for cand in "$PROJECT_ROOT/scripts/lint-counter-antipattern.sh" \
                "$SCRIPT_DIR/lint-counter-antipattern.sh"; do
      [ -f "$cand" ] && { CA_LINT="$cand"; break; }
    done
    if [ -n "$CA_LINT" ]; then
      if ! ca_out=$(bash "$CA_LINT" 2>&1); then
        echo "[FRAMEWORK GATE — strict mode] counter-antipattern lint failed:" >&2
        echo "$ca_out" >&2
        echo "" >&2
        echo "To bypass anyway:  SKIP_LINT=1 git commit ..." >&2
        exit 1
      fi
    fi

    # BL-119-NO-MSG-AT-PRECOMMIT (part 2, BL-133): the backlog-references lint
    # used to run here in --pre-commit-mode, fed from $COMMIT_MSG — the SAME
    # stale previous-commit subject the removed classifier read. A previous
    # commit citing a since-renumbered/bogus BL id blocked the CURRENT innocent
    # commit (adversarial-verifier repro, 2026-07-17). Message-scoped BR
    # checking survives on the PreToolUse surface, which parses the CURRENT
    # message from the command. Do not re-add a message consumer to this path.

    # fix-functions-stderr: full-tree scan, no message dependency.
    FF_LINT=""
    for cand in "$PROJECT_ROOT/scripts/lint-fix-functions-stderr.sh" \
                "$SCRIPT_DIR/lint-fix-functions-stderr.sh"; do
      [ -f "$cand" ] && { FF_LINT="$cand"; break; }
    done
    if [ -n "$FF_LINT" ]; then
      if ! ff_out=$(bash "$FF_LINT" 2>&1); then
        echo "[FRAMEWORK GATE — strict mode] fix-functions-stderr lint failed:" >&2
        echo "$ff_out" >&2
        echo "" >&2
        echo "To bypass anyway:  SKIP_LINT=1 git commit ..." >&2
        exit 1
      fi
    fi

    # raw-read-prompt: full-tree scan, no message dependency.
    RR_LINT=""
    for cand in "$PROJECT_ROOT/scripts/lint-raw-read-prompt.sh" \
                "$SCRIPT_DIR/lint-raw-read-prompt.sh"; do
      [ -f "$cand" ] && { RR_LINT="$cand"; break; }
    done
    if [ -n "$RR_LINT" ]; then
      if ! rr_out=$(bash "$RR_LINT" 2>&1); then
        echo "[FRAMEWORK GATE — strict mode] raw-read-prompt lint failed:" >&2
        echo "$rr_out" >&2
        echo "" >&2
        echo "To bypass anyway:  SKIP_LINT=1 git commit ..." >&2
        exit 1
      fi
    fi

    # tests-registered (BL-038): every tests/test-*.sh must be invoked
    # by an aggregator (or carry an EXEMPT marker). Full-tree scan, no
    # message dependency. See scripts/lint-tests-registered.sh header.
    TR_LINT=""
    for cand in "$PROJECT_ROOT/scripts/lint-tests-registered.sh" \
                "$SCRIPT_DIR/lint-tests-registered.sh"; do
      [ -f "$cand" ] && { TR_LINT="$cand"; break; }
    done
    if [ -n "$TR_LINT" ]; then
      if ! tr_out=$(bash "$TR_LINT" 2>&1); then
        echo "[FRAMEWORK GATE — strict mode] tests-registered lint failed:" >&2
        echo "$tr_out" >&2
        echo "" >&2
        echo "To bypass anyway:  SKIP_LINT=1 git commit ..." >&2
        exit 1
      fi
    fi

    # no-live-remote-in-tests (BL-076): every init.sh run under tests/ must be
    # provably hermetic (--no-remote-creation / --dry-run / --validate-only /
    # --git-host other, or a mocked host CLI) so the suite can never create a
    # REAL repo on an authenticated host (the kraulerson/foo leak, 2026-07-06).
    # Full-tree scan, no message dependency. See
    # scripts/lint-no-live-remote-in-tests.sh header.
    NR_LINT=""
    for cand in "$PROJECT_ROOT/scripts/lint-no-live-remote-in-tests.sh" \
                "$SCRIPT_DIR/lint-no-live-remote-in-tests.sh"; do
      [ -f "$cand" ] && { NR_LINT="$cand"; break; }
    done
    if [ -n "$NR_LINT" ]; then
      if ! nr_out=$(bash "$NR_LINT" 2>&1); then
        echo "[FRAMEWORK GATE — strict mode] no-live-remote-in-tests lint failed:" >&2
        echo "$nr_out" >&2
        echo "" >&2
        echo "To bypass anyway:  SKIP_LINT=1 git commit ..." >&2
        exit 1
      fi
    fi
  fi
  # --- end cycle-8 slot-5 terminal-mode block ---

  exit 0
fi

# Read the tool input from stdin
INPUT=$(cat)

# Extract the bash command from the JSON input.
# Claude Code passes (verified against /anthropics/claude-code docs 2026-04-25):
#   {"session_id": "...", "tool_name": "Bash", "tool_input": {"command": "..."}, ...}
# Fall back to the legacy ".command" path so older test fixtures and any
# manual JSON invocations continue to work.
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // .command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# BL-020: classify a Bash command as an actual `git commit` invocation.
# The previous pattern `\bgit\b.*\bcommit\b` over-matched any command line
# containing both substrings as words — false-positives on read-only git
# operations against files whose paths include the word `commit`
# (e.g., `git diff scripts/pre-commit-gate.sh`, `git log -- scripts/check-commit-message.sh`).
# Tightened classifier:
#   - `commit` must come immediately after `git` (separated only by whitespace),
#     ruling out `git diff <commit-named-path>` etc.
#   - `git` must NOT be preceded by a quote, ruling out search strings like
#     `rg "git commit" docs/`. Start-of-line is allowed.
_is_git_commit() {
  echo "$1" | grep -qE '(^|[^"'\''])git[[:space:]]+commit\b'
}

# tests-precommit-process-2: classify a Bash command as an actual
# `git push --force` (or `-f`) invocation. The previous pattern
# `\bgit\b.*\bpush\b.*(-f|--force)` over-matched any command line
# containing all three substrings — false-positives on quoted search
# strings (`rg "git push --force" docs/`) and read-only git operations
# against files whose paths embed the phrase
# (`git diff docs/git-push-force-recovery.md`). Tightened classifier
# mirrors the BL-020 shape:
#   - `push` must come immediately after `git` (separated only by
#     whitespace), ruling out `git diff <push-named-path>`.
#   - `git` must NOT be preceded by a quote, ruling out search strings.
#     Start-of-line and shell separators (`;`/`&&`/`|`) are allowed.
#   - `-f` / `--force` must appear AFTER `git push` and must not itself
#     be inside a quoted string. We accept any token starting with `-f`
#     (catches `-f`, `--force`, `--force-with-lease`) provided it is
#     preceded by whitespace.
_is_git_push_force() {
  # Combined single-pattern classifier (cycle-9 follow-up to verifier
  # finding #2). The previous two-step split — anchor `git push` in
  # step 1, then independently scan the WHOLE command line for `-f` /
  # `--force` in step 2 — created a false-positive surface when a
  # non-force `git push` was chained with a downstream command whose
  # argument contained `--force`:
  #     git push origin main && echo "use --force carefully"
  # Step 2's whole-line scan picked up the quoted `--force` from the
  # downstream `echo`, denying the safe push. The combined pattern
  # below requires the `-f`/`--force` token to appear AFTER `git push`
  # and BEFORE any shell separator (`;`, `&&`, `||`, `|`) that ends the
  # push command, eliminating the cross-command bleed:
  #   (^|[^"']) git push [^;&|]* <whitespace> (-f<break> | --force...)
  # The leading anti-quote anchor still rules out the principal false-
  # positives (quoted `rg "git push --force" docs/` and `git diff` on
  # files whose paths embed the phrase — the latter starts with
  # `git diff`, not `git push`, so the anchor rejects it naturally).
  # We still accept `--force` as a prefix so `--force-with-lease[=...]`
  # is blocked, matching the original BL-020-predecessor behavior.
  # T11a/T11b pin the quoted-string + path-name surface; T9/T10 pin the
  # positive path including chained `cd ... && git push -f` invocations.
  echo "$1" | grep -qE '(^|[^"'\''])git[[:space:]]+push[^;&|]*[[:space:]](-f([[:space:]]|$)|--force)'
}

# tests-precommit-process-3: classify a Bash command as an actual
# `gh pr create` invocation. The previous pattern
# `\bgh\b.*\bpr\b.*\bcreate\b` over-matched any command line containing
# all three substrings — same defect class as BL-020. Tightened to
# require `pr` immediately after `gh` and `create` immediately after
# `pr`, and to reject leading-quote contexts.
_is_gh_pr_create() {
  echo "$1" | grep -qE '(^|[^"'\''])gh[[:space:]]+pr[[:space:]]+create\b'
}

# Block agent-initiated SOIF_FORCE_STEP bypass (match assignment, not diagnostic reads)
if echo "$COMMAND" | grep -qE 'SOIF_FORCE_STEP='; then
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "SOIF_FORCE_STEP bypasses artifact checks and requires Orchestrator authorization. The Orchestrator must run this command directly in their terminal."}}
HOOKEOF
  exit 0
fi

# Block agent-initiated enforcement override variables
if echo "$COMMAND" | grep -qE 'SOIF_PHASE_GATES=|SOIF_STRICT_CHANGELOG=|SOIF_STRICT_SESSION='; then
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "SOIF_PHASE_GATES modifies enforcement level and requires Orchestrator authorization. The Orchestrator must set this in their environment directly."}}
HOOKEOF
  exit 0
fi

# Block agent-initiated process resets
if echo "$COMMAND" | grep -qE 'process-checklist\.sh.*--reset'; then
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Process reset requires Orchestrator authorization. Ask the Orchestrator to run this command directly in their terminal."}}
HOOKEOF
  exit 0
fi

# --- Early guard (spec 2026-04-21 host-aware repo gate) ---
# Block git commit if no remote is configured. Solo Orchestrator requires a
# created-and-protected remote from init onward; commits without a remote
# indicate either a pre-fix project or drift that needs remediation.
if _is_git_commit "$COMMAND" && ! echo "$COMMAND" | grep -qE 'git.*remote'; then
  # Only check if we're in a git repo with no remote
  if git rev-parse --git-dir >/dev/null 2>&1; then
    if ! git remote get-url origin >/dev/null 2>&1; then
      cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "pre-commit gate: no git remote configured. Solo Orchestrator requires a created-and-protected remote from project init onward. Run: scripts/check-gate.sh --backfill-host (if manifest missing host), then scripts/check-gate.sh --repair (to recreate remote and protection). See docs/builders-guide.md § Repository Setup."}}
HOOKEOF
      exit 0
    fi
  fi
fi

# Block --no-verify flag on git commit (bypasses security hooks)
if _is_git_commit "$COMMAND" && echo "$COMMAND" | grep -qE -- '--no-verify'; then
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "The --no-verify flag bypasses security hooks (gitleaks, Semgrep). Remove --no-verify and commit normally."}}
HOOKEOF
  exit 0
fi

# --- BL-015: pending-approval sentinel reader ---
# Blocks git commit and gh pr create when .claude/pending-approval.json exists.
# Runs after security gates (SOIF_*, no-remote, --no-verify) but before
# workflow gates (--amend, bl006_check, --check-commit-ready) so pending
# approval preempts workflow concerns without hiding security violations.
# See docs/builders-guide.md "Structured Decision Points" for the contract.

build_pa_rich_reason() {
  local sentinel="$1" action_label="$2"
  local question options recommendation offered_at
  question=$(jq -er '.question' "$sentinel") || return 1
  options=$(jq -er '.options | map("  " + .) | join("\n")' "$sentinel") || return 1
  recommendation=$(jq -er '.recommendation' "$sentinel") || return 1
  offered_at=$(jq -er '.offered_at' "$sentinel") || return 1
  cat <<EOF
pre-commit gate: $action_label blocked — pending user decision.

Pending question: "$question"
Options:
$options
Recommendation: $recommendation
Offered at: $offered_at

Wait for the user to pick one, then:
  scripts/pending-approval.sh --resolve
EOF
}

build_pa_malformed_reason() {
  local sentinel="$1" action_label="$2"
  cat <<EOF
pre-commit gate: $action_label blocked — pending user decision.

The sentinel file $sentinel exists but is malformed.
Treated as "in flight" per the CDF 4.2.3 contract.

If this is a stale file from a crashed session, remove it manually:
  rm $sentinel
EOF
}

pa_check() {
  # Only applies to git commit or gh pr create. Other commands fall through.
  local is_commit=false is_pr=false
  _is_git_commit "$COMMAND" && is_commit=true
  _is_gh_pr_create "$COMMAND" && is_pr=true
  [ "$is_commit" = false ] && [ "$is_pr" = false ] && return 0

  local sentinel=".claude/pending-approval.json"
  [ -f "$sentinel" ] || return 0

  local action_label="commit"
  [ "$is_pr" = true ] && action_label="PR creation"

  local reason
  if reason=$(build_pa_rich_reason "$sentinel" "$action_label" 2>/dev/null); then
    :
  else
    reason=$(build_pa_malformed_reason "$sentinel" "$action_label")
  fi

  local escaped
  escaped=$(echo "$reason" | tr '\n' ' ' | sed 's/"/\\"/g')
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "$escaped"}}
HOOKEOF
  exit 0
}

pa_check
# --- end BL-015 block ---

# Warn on git commit --amend (rewrites commit history, bypasses build loop for amended content)
if _is_git_commit "$COMMAND" && echo "$COMMAND" | grep -qE -- '--amend'; then
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "permissionDecisionReason": "WARNING: git commit --amend rewrites the previous commit. Ensure the amended content has been through the full Build Loop. If this amend adds new source code, consider a new commit instead."}}
HOOKEOF
  exit 0
fi

# --- BL-072 Phase C1: TDD-ordering detector (WARN mode, measurement) ---
# Fires on feat/fix/refactor commits that add/modify implementation files
# with NO test file in the same commit AND no test file earlier on the branch
# (git diff main...HEAD). On trigger it prints a [WARN] would-block
# explanation to stderr and appends a JSON row to
# .claude/tdd-warn-ledger.jsonl. It is measurement-only: it NEVER denies and
# NEVER changes the exit code (the hook still exits 0). Phase C2 (the hard
# block) is deliberately NOT implemented here — it ships only after Karl
# reviews the measured false-block rate from the dogfood replay.
#
# The file-classification core (_bl072_classify_paths) lives in
# scripts/lib/tdd-classify.sh and is shared verbatim with the replay tool.
# Known C1 limitation: classification is path-based only, so a feat/fix/
# refactor commit that changes ONLY comments in an implementation file still
# counts as implementation and will WARN. WARN-only makes that safe; the
# dogfood surfaces it as a false positive.

# Extract the first line (subject) of the prospective commit message from the
# Bash command. Self-contained so the detector can run early, before the
# BL-006 block, and fire even for commits a later gate would deny.
_tdd_extract_subject() {
  local s=""
  if echo "$COMMAND" | grep -qE "<<'?EOF'?"; then
    s=$(printf '%s\n' "$COMMAND" | awk '
      /<<'"'"'?EOF'"'"'?/ { flag=1; next }
      /^EOF$/ { flag=0 }
      flag && !printed && NF>0 { print; printed=1; exit }
    ')
  fi
  if [ -z "$s" ]; then
    s=$(printf '%s' "$COMMAND" | sed -nE 's/.*-m "([^"]*)".*/\1/p' | head -n 1)
    if [ -z "$s" ]; then
      s=$(printf '%s' "$COMMAND" | sed -nE "s/.*-m '([^']*)'.*/\\1/p" | head -n 1)
    fi
    s=$(printf '%s\n' "$s" | head -n 1)
  fi
  if [ -z "$s" ] && echo "$COMMAND" | grep -qE '\-F[[:space:]]+[^ ]+'; then
    local f
    f=$(echo "$COMMAND" | sed -nE 's/.*-F[[:space:]]+([^ ]+).*/\1/p' | head -n 1)
    if [ -n "$f" ] && [ -r "$f" ]; then
      s=$(head -n 1 "$f")
    fi
  fi
  printf '%s' "$s"
}

# Append one row to the WARN ledger. Must NEVER fail the commit under set -e,
# hence every step is guarded with `|| return 0`.
append_tdd_ledger() {
  local subject="$1" files="$2"
  command -v jq >/dev/null 2>&1 || return 0
  local ledger=".claude/tdd-warn-ledger.jsonl"
  [ -d .claude ] || mkdir -p .claude 2>/dev/null || return 0
  local files_json
  files_json=$(printf '%s\n' "$files" | grep -v '^[[:space:]]*$' | jq -R . 2>/dev/null | jq -s . 2>/dev/null) || return 0
  [ -n "$files_json" ] || files_json='[]'
  local row
  row=$(jq -cn \
    --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg subject "$subject" \
    --argjson files "$files_json" \
    '{date:$date, subject:$subject, files:$files, would_block:true}' 2>/dev/null) || return 0
  printf '%s\n' "$row" >> "$ledger" 2>/dev/null || return 0
  return 0
}

# Emit the WARN diagnostic (stderr) + ledger row. rc is untouched.
emit_tdd_warn() {
  local subject="$1" files="$2" type
  type=$(printf '%s' "$subject" | sed -nE 's/^(feat|fix|refactor).*/\1/p')
  {
    echo "[WARN] BL-072 TDD ordering: '$type:' commit ships implementation without a matching test."
    echo "[WARN]   Subject: $subject"
    echo "[WARN]   Impl files (no test in this commit, none earlier on the branch):"
    printf '%s\n' "$files" | grep -v '^[[:space:]]*$' | sed 's/^/[WARN]     - /' || true
    echo "[WARN]   Under BL-072 Phase C2 (hard block) this commit WOULD BE BLOCKED."
    echo "[WARN]   Write the failing test first (test-driven), or — once C2 ships —"
    echo "[WARN]   attest the exception with SOLO_TDD_ATTESTED=1. This is a WARNING"
    echo "[WARN]   only: the commit is NOT blocked and is being recorded for measurement."
  } >&2
  # rc must stay 0 no matter what — this is measurement, never a block.
  append_tdd_ledger "$subject" "$files" || true
  return 0
}

tdd_warn_check() {
  _is_git_commit "$COMMAND" || return 0

  # Derivative-commit filters (same set as bl006_check): pass through.
  echo "$COMMAND" | grep -qE '\-\-amend\b' && return 0
  [ -f .git/MERGE_HEAD ] && return 0
  echo "$COMMAND" | grep -qE '\bgit\b.*\b(merge|revert|cherry-pick)\b' && return 0
  echo "$COMMAND" | grep -qE '\bgh\b.*\bpr\b.*\bmerge\b.*\-\-squash' && return 0

  # Detection is shared with the --terminal-mode enforcement via _tdd_triggers
  # (single source of truth). The staged set is fed as git NAME-STATUS so the
  # C2 classifier can exclude pure deletions (the C1 path-only reader could
  # not). Without the classifier lib, no-op (safe — C1 was WARN-only anyway).
  local subject staged_status
  subject=$(_tdd_extract_subject)
  command -v _bl072_classify_status >/dev/null 2>&1 || return 0
  staged_status=$(git diff --cached --name-status 2>/dev/null || true)

  local _fire=0
  _tdd_triggers "$subject" "$staged_status" && _fire=1   # BL-072-TDD-DETECT
  [ "$_fire" = "1" ] || return 0

  # TRIGGER — implementation shipped without tests. This PreToolUse surface is
  # WARN-only measurement (rc unchanged); the tier-keyed hard block lives on the
  # --terminal-mode git-hook surface (tdd_terminal_enforce).
  local impl_files
  impl_files=$(printf '%s\n' "$staged_status" | _bl072_impl_files || true)
  emit_tdd_warn "$subject" "$impl_files"
  return 0
}

tdd_warn_check
# --- end BL-072 Phase C1 block ---

# --- BL-006: commit-message-triggered Build Loop enforcement ---
# Scope: only fires on `git commit` authoring events (not merges, reverts,
# cherry-picks, squash-merges, or editor-case commits). Extracts the message
# from -m "..." / heredoc / -F file and delegates the policy decision to
# process-checklist.sh --check-commit-message.

bl006_check() {
  # Only apply to `git commit` subcommands.
  _is_git_commit "$COMMAND" || return 0

  # Derivative-commit filters: pass through.
  # --amend is already handled above (warns, exits). Belt-and-braces.
  echo "$COMMAND" | grep -qE '\-\-amend\b' && return 0
  # Merge in progress.
  [ -f .git/MERGE_HEAD ] && return 0
  # Other derivative commands that might embed feat: in their message.
  echo "$COMMAND" | grep -qE '\bgit\b.*\b(merge|revert|cherry-pick)\b' && return 0
  echo "$COMMAND" | grep -qE '\bgh\b.*\bpr\b.*\bmerge\b.*\-\-squash' && return 0

  # Extract the message subject.
  local msg=""

  # 1. Heredoc: look for -m "$(cat <<EOF or -m "$(cat <<'EOF'
  if echo "$COMMAND" | grep -qE "<<'?EOF'?"; then
    # awk: after the <<EOF or <<'EOF' marker, the first non-empty content line
    # before a standalone EOF is the subject.
    msg=$(printf '%s\n' "$COMMAND" | awk '
      /<<'"'"'?EOF'"'"'?/ { flag=1; next }
      /^EOF$/ { flag=0 }
      flag && !printed && NF>0 { print; printed=1; exit }
    ')
  fi

  # 2. Inline -m "..." (double or single quotes). Only if heredoc didn't match.
  if [ -z "$msg" ]; then
    # Try double-quoted first, then single-quoted. Capture up to the closing
    # quote. This is best-effort; exotic escaping falls through.
    msg=$(printf '%s' "$COMMAND" | sed -nE 's/.*-m "([^"]*)".*/\1/p' | head -n 1)
    if [ -z "$msg" ]; then
      msg=$(printf '%s' "$COMMAND" | sed -nE "s/.*-m '([^']*)'.*/\\1/p" | head -n 1)
    fi
    # Split on real newlines; take first line.
    msg=$(printf '%s\n' "$msg" | head -n 1)
  fi

  # 3. -F <file>. Only if no -m at all was seen.
  if [ -z "$msg" ] && echo "$COMMAND" | grep -qE '\-F[[:space:]]+[^ ]+'; then
    local f
    f=$(echo "$COMMAND" | sed -nE 's/.*-F[[:space:]]+([^ ]+).*/\1/p' | head -n 1)
    if [ -n "$f" ] && [ -r "$f" ]; then
      msg=$(head -n 1 "$f")
    fi
  fi

  # Empty: fall through (editor case or parse miss).
  [ -z "$msg" ] && return 0

  # Delegate to the subcommand. Capture both streams (print_fail uses stdout;
  # echo-to-stderr is used for remediation lines).
  local policy_err policy_exit=0
  policy_err=$("$SCRIPT_DIR/process-checklist.sh" --check-commit-message "$msg" 2>&1) || policy_exit=$?

  if [ "$policy_exit" -ne 0 ]; then
    local reason
    reason=$(echo "$policy_err" | tr '\n' ' ' | sed 's/"/\\"/g')
    cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "$reason"}}
HOOKEOF
    exit 0
  fi

  return 0
}

bl006_check
# --- end BL-006 block ---

# --- Cycle-8 slot-5: operator-side lint promotion ---
# Promotes the two CI lints (PR #72 counter-antipattern, PR #76
# backlog-references) from CI-only to ALSO running at commit time, so
# regressions are caught locally before reaching CI. Two integration
# points share the same enforcement:
#   • PreToolUse path (this function): re-extracts the prospective
#     commit message from the Bash command (same heuristics as
#     bl006_check) and pipes it to lint-backlog-references.sh
#     --pre-commit-mode. Counter-antipattern lint runs unconditionally
#     because it's a full-tree scan, not message-scoped.
#   • --terminal-mode branch (above): same two lints, reading the
#     message from .git/COMMIT_EDITMSG.
# SKIP_LINT=1 escape hatch: a misconfigured pre-commit-gate.sh or a
# transient lint regression must not strand the operator. The escape
# is logged via stderr so emergency use is visible. Pair with the
# bypass-audit ledger via the SessionStart detector — the bypass is
# still recorded as a recoverable signal.

# Extract a one-line subject from the prospective commit message (same
# heuristics as bl006_check). Returns the body too if heredoc was used.
extract_commit_message() {
  local msg=""
  # 1. Heredoc — return the full body between the EOF markers so the
  # backlog-references lint can scan tokens anywhere in the message.
  if echo "$COMMAND" | grep -qE "<<'?EOF'?"; then
    msg=$(printf '%s\n' "$COMMAND" | awk '
      /<<'"'"'?EOF'"'"'?/ { flag=1; next }
      /^EOF$/ { flag=0 }
      flag { print }
    ')
  fi
  # 2. Inline -m "..."
  if [ -z "$msg" ]; then
    msg=$(printf '%s' "$COMMAND" | sed -nE 's/.*-m "([^"]*)".*/\1/p' | head -n 1)
    if [ -z "$msg" ]; then
      msg=$(printf '%s' "$COMMAND" | sed -nE "s/.*-m '([^']*)'.*/\\1/p" | head -n 1)
    fi
  fi
  # 3. -F <file>
  if [ -z "$msg" ] && echo "$COMMAND" | grep -qE '\-F[[:space:]]+[^ ]+'; then
    local f
    f=$(echo "$COMMAND" | sed -nE 's/.*-F[[:space:]]+([^ ]+).*/\1/p' | head -n 1)
    if [ -n "$f" ] && [ -r "$f" ]; then
      msg=$(cat "$f")
    fi
  fi
  printf '%s' "$msg"
}

emit_lint_block() {
  local reason
  reason=$(echo "$1" | tr '\n' ' ' | sed 's/"/\\"/g')
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "$reason"}}
HOOKEOF
  exit 0
}

lints_check() {
  _is_git_commit "$COMMAND" || return 0

  # Derivative-commit filters: same as bl006_check.
  echo "$COMMAND" | grep -qE '\-\-amend\b' && return 0
  [ -f .git/MERGE_HEAD ] && return 0
  echo "$COMMAND" | grep -qE '\bgit\b.*\b(merge|revert|cherry-pick)\b' && return 0
  echo "$COMMAND" | grep -qE '\bgh\b.*\bpr\b.*\bmerge\b.*\-\-squash' && return 0

  # Escape hatch.
  if [ "${SKIP_LINT:-0}" = "1" ]; then
    echo "[pre-commit-gate] SKIP_LINT=1 set — bypassing counter-antipattern + backlog-references + fix-functions-stderr + raw-read-prompt + tests-registered + no-live-remote-in-tests lints" >&2
    return 0
  fi

  # Prefer the project-local copy of each lint (upgrade-project.sh
  # installs the lints into the project's scripts/ dir alongside
  # pre-commit-gate.sh). Fall back to the framework copy so the gate
  # still self-checks when run from the framework repo's own working
  # tree. Project root = `git rev-parse --show-toplevel` from the
  # current cwd, since Claude Code invokes the hook from the project.
  local proj_root ca_lint="" br_lint="" ff_lint="" rr_lint="" tr_lint="" nr_lint=""
  proj_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  for cand in "$proj_root/scripts/lint-counter-antipattern.sh" \
              "$SCRIPT_DIR/lint-counter-antipattern.sh"; do
    [ -n "$cand" ] && [ -f "$cand" ] && { ca_lint="$cand"; break; }
  done
  for cand in "$proj_root/scripts/lint-backlog-references.sh" \
              "$SCRIPT_DIR/lint-backlog-references.sh"; do
    [ -n "$cand" ] && [ -f "$cand" ] && { br_lint="$cand"; break; }
  done
  for cand in "$proj_root/scripts/lint-fix-functions-stderr.sh" \
              "$SCRIPT_DIR/lint-fix-functions-stderr.sh"; do
    [ -n "$cand" ] && [ -f "$cand" ] && { ff_lint="$cand"; break; }
  done
  for cand in "$proj_root/scripts/lint-raw-read-prompt.sh" \
              "$SCRIPT_DIR/lint-raw-read-prompt.sh"; do
    [ -n "$cand" ] && [ -f "$cand" ] && { rr_lint="$cand"; break; }
  done
  for cand in "$proj_root/scripts/lint-tests-registered.sh" \
              "$SCRIPT_DIR/lint-tests-registered.sh"; do
    [ -n "$cand" ] && [ -f "$cand" ] && { tr_lint="$cand"; break; }
  done
  for cand in "$proj_root/scripts/lint-no-live-remote-in-tests.sh" \
              "$SCRIPT_DIR/lint-no-live-remote-in-tests.sh"; do
    [ -n "$cand" ] && [ -f "$cand" ] && { nr_lint="$cand"; break; }
  done

  # Counter-antipattern: full repo-relative scan, fast.
  if [ -n "$ca_lint" ]; then
    local ca_out ca_exit=0
    ca_out=$(bash "$ca_lint" 2>&1) || ca_exit=$?
    if [ "$ca_exit" -ne 0 ]; then
      emit_lint_block "pre-commit gate: scripts/lint-counter-antipattern.sh failed. ${ca_out} Fix the antipattern or append '# lint-counter-antipattern: allow <reason>' to the capture line. Run 'SKIP_LINT=1 git commit ...' to bypass in an emergency (logged to .claude/bypass-audit.json)."
    fi
  fi

  # Backlog-references: needs the prospective commit message.
  if [ -n "$br_lint" ]; then
    local msg
    msg=$(extract_commit_message)
    # Empty message → editor case; skip the lint (the editor will
    # produce a message that the post-commit history will catch).
    if [ -n "$msg" ]; then
      local br_out br_exit=0
      br_out=$(printf '%s' "$msg" | bash "$br_lint" --pre-commit-mode 2>&1) || br_exit=$?
      if [ "$br_exit" -ne 0 ]; then
        emit_lint_block "pre-commit gate: scripts/lint-backlog-references.sh failed. ${br_out} Add the missing BL entry, fix the typo, or add the citation/allowlist marker. Run 'SKIP_LINT=1 git commit ...' to bypass in an emergency (logged to .claude/bypass-audit.json)."
      fi
    fi
  fi

  # fix-functions-stderr: full repo-relative scan, fast.
  if [ -n "$ff_lint" ]; then
    local ff_out ff_exit=0
    ff_out=$(bash "$ff_lint" 2>&1) || ff_exit=$?
    if [ "$ff_exit" -ne 0 ]; then
      emit_lint_block "pre-commit gate: scripts/lint-fix-functions-stderr.sh failed. ${ff_out} Surface the diagnostic (drop the 2>/dev/null) or append '# lint-fix-functions-stderr: allow <reason>' to the offending line. Run 'SKIP_LINT=1 git commit ...' to bypass in an emergency (logged to .claude/bypass-audit.json)."
    fi
  fi

  # raw-read-prompt: full repo-relative scan, fast.
  if [ -n "$rr_lint" ]; then
    local rr_out rr_exit=0
    rr_out=$(bash "$rr_lint" 2>&1) || rr_exit=$?
    if [ "$rr_exit" -ne 0 ]; then
      emit_lint_block "pre-commit gate: scripts/lint-raw-read-prompt.sh failed. ${rr_out} Migrate to prompt_input / prompt_yes_no (scripts/lib/helpers.sh) or append '# lint-raw-read-prompt: allow <reason>'. Run 'SKIP_LINT=1 git commit ...' to bypass in an emergency (logged to .claude/bypass-audit.json)."
    fi
  fi

  # tests-registered (BL-038): structural backstop for orphan tests.
  # Full repo-relative scan, fast.
  if [ -n "$tr_lint" ]; then
    local tr_out tr_exit=0
    tr_out=$(bash "$tr_lint" 2>&1) || tr_exit=$?
    if [ "$tr_exit" -ne 0 ]; then
      emit_lint_block "pre-commit gate: scripts/lint-tests-registered.sh failed. ${tr_out} Register the test in tests/full-project-test-suite.sh (or another aggregator) following the BL-034 cohort pattern, or add '# LINT_TEST_REGISTRATION_EXEMPT: <reason>' to the file header. Run 'SKIP_LINT=1 git commit ...' to bypass in an emergency (logged to .claude/bypass-audit.json)."
    fi
  fi

  # no-live-remote-in-tests (BL-076): every init.sh run under tests/ must be
  # provably hermetic so the suite can never create a REAL repo on an
  # authenticated host. Full repo-relative scan.
  if [ -n "$nr_lint" ]; then
    local nr_out nr_exit=0
    nr_out=$(bash "$nr_lint" 2>&1) || nr_exit=$?
    if [ "$nr_exit" -ne 0 ]; then
      emit_lint_block "pre-commit gate: scripts/lint-no-live-remote-in-tests.sh failed. ${nr_out} Make the init.sh run hermetic — add --no-remote-creation (or --git-host other + a fake --remote-url, or route gh/glab/curl through a mocked CLI). Run 'SKIP_LINT=1 git commit ...' to bypass in an emergency (logged to .claude/bypass-audit.json)."
    fi
  fi

  return 0
}

lints_check
# --- end cycle-8 slot-5 block ---

# Block git push --force (overwrites branch history).
# Uses _is_git_push_force (defined above) — tightened classifier that
# ignores quoted search strings and read-only git operations against
# files whose paths embed the phrase. See tests-precommit-process-2.
if _is_git_push_force "$COMMAND"; then
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Force push overwrites branch history and can destroy audit evidence. Use normal push. If you need to rewrite history, ask the Orchestrator."}}
HOOKEOF
  exit 0
fi

# Block gh repo create --push (bypasses branch-safety by pushing to a new remote without gate checks)
if echo "$COMMAND" | grep -qE '\bgh\b.*\brepo\b.*\bcreate\b.*--push'; then
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "gh repo create --push bypasses branch safety checks by pushing directly to a new remote. Create the repo without --push, then use git push after process checks pass."}}
HOOKEOF
  exit 0
fi

# Only gate git commit and gh pr create for process checklist enforcement
IS_COMMIT=false
IS_PR=false
if _is_git_commit "$COMMAND"; then
  IS_COMMIT=true
elif _is_gh_pr_create "$COMMAND"; then
  IS_PR=true
fi

if [ "$IS_COMMIT" = false ] && [ "$IS_PR" = false ]; then
  exit 0
fi

# code-process-checklist-5: extract the prospective commit subject (if
# this is a git commit) and pass it to --check-commit-ready. The
# subject lets the checklist short-circuit the Phase 2 source-commit
# Build Loop block for non-feat Conventional Commit subjects (chore,
# fix, refactor, docs, test, perf, style, build, ci, revert). Feat
# commits — with or without scope, with or without `!` — still trip
# the gate. PR-creation flow (IS_PR=true) has no commit subject; we
# pass an empty string, which preserves the pre-fix file-heuristic
# behaviour.
COMMIT_SUBJECT=""
if [ "$IS_COMMIT" = true ]; then
  # Reuse the same extraction helper used for the BL-006 commit-message
  # path (defined below). Inline a minimal subject-only extraction
  # rather than reordering the file: read first line only.
  RAW_MSG=""
  if echo "$COMMAND" | grep -qE "<<'?EOF'?"; then
    RAW_MSG=$(printf '%s\n' "$COMMAND" | awk '
      /<<'"'"'?EOF'"'"'?/ { flag=1; next }
      /^EOF$/ { flag=0 }
      flag && !printed && NF>0 { print; printed=1; exit }
    ')
  fi
  if [ -z "$RAW_MSG" ]; then
    RAW_MSG=$(printf '%s' "$COMMAND" | sed -nE 's/.*-m "([^"]*)".*/\1/p' | head -n 1)
    if [ -z "$RAW_MSG" ]; then
      RAW_MSG=$(printf '%s' "$COMMAND" | sed -nE "s/.*-m '([^']*)'.*/\\1/p" | head -n 1)
    fi
    RAW_MSG=$(printf '%s\n' "$RAW_MSG" | head -n 1)
  fi
  if [ -z "$RAW_MSG" ] && echo "$COMMAND" | grep -qE '\-F[[:space:]]+[^ ]+'; then
    F=$(echo "$COMMAND" | sed -nE 's/.*-F[[:space:]]+([^ ]+).*/\1/p' | head -n 1)
    if [ -n "$F" ] && [ -r "$F" ]; then
      RAW_MSG=$(head -n 1 "$F")
    fi
  fi
  COMMIT_SUBJECT="$RAW_MSG"
fi

# Run process checklist check
CHECKLIST_OUTPUT=""
CHECKLIST_EXIT=0
if [ -n "$COMMIT_SUBJECT" ]; then
  CHECKLIST_OUTPUT=$("$SCRIPT_DIR/process-checklist.sh" --check-commit-ready --subject "$COMMIT_SUBJECT" 2>&1) || CHECKLIST_EXIT=$?
else
  CHECKLIST_OUTPUT=$("$SCRIPT_DIR/process-checklist.sh" --check-commit-ready 2>&1) || CHECKLIST_EXIT=$?
fi

if [ "$CHECKLIST_EXIT" -ne 0 ]; then
  # Block the commit
  REASON=$(echo "$CHECKLIST_OUTPUT" | tr '\n' ' ' | sed 's/"/\\"/g')
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "$REASON"}}
HOOKEOF
  exit 0
fi

# For PR creation: additional checks
if [ "$IS_PR" = true ]; then
  # Check no UAT session in progress
  PROCESS_STATE=".claude/process-state.json"
  if [ -f "$PROCESS_STATE" ] && command -v jq &>/dev/null; then
    UAT_STARTED=$(jq -r '.uat_session.started_at // empty' "$PROCESS_STATE" 2>/dev/null)
    if [ -n "$UAT_STARTED" ]; then
      UAT_STEPS_DONE=$(jq -r '.uat_session.steps_completed | length' "$PROCESS_STATE" 2>/dev/null)
      if [ "$UAT_STEPS_DONE" -lt 9 ]; then
        cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "UAT session in progress with incomplete steps ($UAT_STEPS_DONE/9). Complete all UAT steps before creating a PR."}}
HOOKEOF
        exit 0
      fi
    fi

    # Check build_loop is at step 0 or steps 1–5 complete. Per baseline
    # invariant #14, the build/test/commit cycle is steps 1–5
    # (tests_written, tests_verified_failing, implemented, security_audit,
    # documentation_updated). Step 6 (feature_recorded) is bookkeeping
    # that runs AFTER the PR/merge via `test-gate.sh --record-feature`;
    # requiring it pre-PR is a process inversion that contradicts
    # invariant #14. Match the commit-side rule in
    # scripts/process-checklist.sh:require_build_loop_state_for_commit
    # (which already requires only the first 5 steps).
    BUILD_FEATURE=$(jq -r '.build_loop.feature // empty' "$PROCESS_STATE" 2>/dev/null)
    if [ -n "$BUILD_FEATURE" ]; then
      BUILD_STEPS_DONE=$(jq -r '.build_loop.steps_completed | length' "$PROCESS_STATE" 2>/dev/null)
      if [ "$BUILD_STEPS_DONE" -gt 0 ] && [ "$BUILD_STEPS_DONE" -lt 5 ]; then
        cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Feature '$BUILD_FEATURE' has incomplete Build Loop ($BUILD_STEPS_DONE/5 steps). Complete steps 1–5 (tests_written … documentation_updated) before creating a PR. Step 6 (feature_recorded) is post-PR bookkeeping — record it via scripts/test-gate.sh --record-feature after merge."}}
HOOKEOF
        exit 0
      fi
    fi
  fi
fi

# Process checklist passed. Now check tool usage (warnings only, not blocking).
TOOL_USAGE=".claude/tool-usage.json"
PHASE_STATE=".claude/phase-state.json"
WARNINGS=""

if [ "$IS_COMMIT" = true ] && [ -f "$TOOL_USAGE" ] && [ -f "$PHASE_STATE" ] && command -v jq &>/dev/null; then
  CURRENT_PHASE=$(jq -r '.current_phase // 0' "$PHASE_STATE" 2>/dev/null)

  if [ "$CURRENT_PHASE" = "2" ]; then
    # Check if this is a source commit (reuse staged file check)
    HAS_SOURCE=false
    STAGED=$(git diff --cached --name-only 2>/dev/null || true)
    if echo "$STAGED" | grep -qE '\.(py|ts|tsx|js|jsx|rs|go|cs|kt|java|dart|swift|c|cpp|h)$'; then
      HAS_SOURCE=true
    elif echo "$STAGED" | grep -qE '^(src|lib|app|pkg|internal|cmd)/'; then
      HAS_SOURCE=true
    fi

    if [ "$HAS_SOURCE" = true ]; then
      # Context7 check
      COMMITS_SINCE_CTX7=$(jq -r '.commits_since_last_context7 // 0' "$TOOL_USAGE" 2>/dev/null)
      if [ "$COMMITS_SINCE_CTX7" -ge 2 ] 2>/dev/null; then
        WARNINGS="${WARNINGS}Context7 has not been consulted for library documentation in the last $COMMITS_SINCE_CTX7 commits. Consider checking docs for libraries used in this change. "
      fi

      # Qdrant-find check (first commit of session only)
      QDRANT_FIND=$(jq -r '.qdrant_find_called // false' "$TOOL_USAGE" 2>/dev/null)
      if [ "$QDRANT_FIND" = "false" ]; then
        WARNINGS="${WARNINGS}No prior context retrieved from Qdrant this session. Consider checking for relevant architecture decisions and patterns. "
      fi
    fi
  fi
fi

if [ -n "$WARNINGS" ]; then
  # Output warnings as additional context (not blocking)
  ESCAPED_WARNINGS=$(echo "$WARNINGS" | sed 's/"/\\"/g')
  cat << HOOKEOF
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "permissionDecisionReason": "TOOL USAGE WARNINGS: $ESCAPED_WARNINGS"}}
HOOKEOF
fi

# If we reach here with no output, the commit is allowed silently
exit 0
