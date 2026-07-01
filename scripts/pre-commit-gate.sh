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

# BL-030: --terminal-mode invocation from .git/hooks/framework-gate.sh.
# Reads commit message from .git/COMMIT_EDITMSG instead of stdin JSON;
# reads staged files from `git diff --cached` instead of tool-input;
# emits human-readable diagnostics to stderr instead of JSON to stdout.
TERMINAL_MODE=0
for arg in "$@"; do
  case "$arg" in
    --terminal-mode) TERMINAL_MODE=1 ;;
  esac
done

if [ "$TERMINAL_MODE" -eq 1 ]; then
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "[FAIL] not a git repo" >&2; exit 1; }
  cd "$PROJECT_ROOT"
  COMMIT_MSG=$(cat .git/COMMIT_EDITMSG 2>/dev/null || echo "")

  # Reuse process-checklist.sh's classifier.
  if [ -x "scripts/process-checklist.sh" ]; then
    if ! bash scripts/process-checklist.sh --check-commit-message "$COMMIT_MSG" 2>&1 >&2; then
      # shellcheck disable=SC1091
      if [ -f "$PROJECT_ROOT/scripts/lib/gate-principles.sh" ]; then
        source "$PROJECT_ROOT/scripts/lib/gate-principles.sh"
      fi
      echo "" >&2
      echo "[FRAMEWORK GATE — strict mode]" >&2
      echo "" >&2
      echo "Block reason: commit message classifier rejected the message under current Phase / Build Loop state." >&2
      echo "" >&2
      echo "Why this rule exists:" >&2
      if command -v principle_for >/dev/null 2>&1; then
        principle_for "commit-classifier" >&2
      else
        echo "  See docs/user-guide.md commit-classifier section." >&2
      fi
      echo "" >&2
      echo "To proceed:" >&2
      echo "  Open a Build Loop:  scripts/process-checklist.sh --start-feature \"<name>\"" >&2
      echo "  Complete steps:     scripts/process-checklist.sh --complete-step build_loop:tests_written" >&2
      echo "  ...then commit again." >&2
      echo "" >&2
      echo "To bypass anyway (recorded in .claude/bypass-audit.json):" >&2
      echo "  git commit --no-verify ..." >&2
      echo "" >&2
      echo "To downgrade enforcement permanently:" >&2
      echo "  scripts/reconfigure-project.sh --enforcement-level light" >&2
      exit 1
    fi
  fi

  # --- Cycle-8 slot-5: operator-side lint promotion (terminal-mode) ---
  # All four CI lints fire on user-terminal commits too:
  #   - counter-antipattern        (PR #72)
  #   - backlog-references         (PR #76)
  #   - fix-functions-stderr       (cycle-8 wave-3 slot-5, this PR)
  #   - raw-read-prompt            (cycle-8 wave-3 slot-5, this PR)
  # SKIP_LINT=1 escape mirrors the PreToolUse path.
  if [ "${SKIP_LINT:-0}" = "1" ]; then
    echo "[pre-commit-gate] SKIP_LINT=1 set — bypassing all four pre-commit lints (counter-antipattern, backlog-references, fix-functions-stderr, raw-read-prompt)" >&2
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

    BR_LINT=""
    for cand in "$PROJECT_ROOT/scripts/lint-backlog-references.sh" \
                "$SCRIPT_DIR/lint-backlog-references.sh"; do
      [ -f "$cand" ] && { BR_LINT="$cand"; break; }
    done
    if [ -n "$BR_LINT" ] && [ -n "$COMMIT_MSG" ]; then
      if ! br_out=$(printf '%s' "$COMMIT_MSG" | bash "$BR_LINT" --pre-commit-mode 2>&1); then
        echo "[FRAMEWORK GATE — strict mode] backlog-references lint failed:" >&2
        echo "$br_out" >&2
        echo "" >&2
        echo "To bypass anyway:  SKIP_LINT=1 git commit ..." >&2
        exit 1
      fi
    fi

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
    echo "[pre-commit-gate] SKIP_LINT=1 set — bypassing counter-antipattern + backlog-references + fix-functions-stderr + raw-read-prompt + tests-registered lints" >&2
    return 0
  fi

  # Prefer the project-local copy of each lint (upgrade-project.sh
  # installs the lints into the project's scripts/ dir alongside
  # pre-commit-gate.sh). Fall back to the framework copy so the gate
  # still self-checks when run from the framework repo's own working
  # tree. Project root = `git rev-parse --show-toplevel` from the
  # current cwd, since Claude Code invokes the hook from the project.
  local proj_root ca_lint="" br_lint="" ff_lint="" rr_lint="" tr_lint=""
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
