#!/usr/bin/env bash
# scripts/hooks/record-claude-commit.sh — BL-030 PostToolUse hook.
#
# Records the SHA of every successful git commit issued by Claude into
# .claude/claude-commits.jsonl. Always-on, regardless of enforcement_level.
# The ledger is the substrate the out-of-band detector uses to distinguish
# Claude-issued commits from user-terminal commits.
#
# Stdin: JSON envelope from Claude Code's PostToolUse hook contract. For the
# Bash tool:
#   { "hook_event_name": "PostToolUse", "tool_input": {"command": "..."},
#     "tool_response": { "stdout", "stderr", "interrupted", "isImage",
#                        "noOutputExpected",
#                        "gitOperation": {"commit": {"sha", "kind", "branch"}} } }
#
# `## BL-324:` WHAT SAYS A COMMIT WAS MADE, AND WHICH ONE. This hook used to
# read tool_response.exit_code and treat its absence as a failure. Claude Code
# sends no exit code for Bash, so it never wrote a row, and the out-of-band
# detector labelled every agent commit a terminal commit. PostToolUse fires only
# for a call that succeeded (a failed one fires PostToolUseFailure, measured for
# `## BL-233:`), but a call can succeed while the commit in it failed
# (`git commit -m x; true`, or `|| true`), and then HEAD is a commit the call did
# not make: possibly the user's own, which recording would hide from the
# detector. So the commit recorded is the one the host names:
# tool_response.gitOperation.commit.sha, which Claude Code sets when git printed
# the summary line of a commit it made ("[main 1a2b3c4] subject"), checked to be
# a commit object in this repository and recorded by its full SHA.
#
# A `-q` commit prints no summary line, so the host names nothing (251 of the
# 382 agent commits measured for BL-324). For those the commits are proved from
# HEAD's reflog (_reflog_commits): a `commit`, `commit (amend)` or
# `commit (initial)` entry written in the last REFLOG_WINDOW seconds whose
# subject is in the command's own text, when the command gives its message
# inline (-m / --message, or -F - with a heredoc) and not from a file. A commit
# that failed writes no entry, so `git commit -q -m x; true` leaves only older
# entries, which are outside the window or carry another subject.
#
# No-op conditions:
#   - .claude/ doesn't exist (project not initialized)
#   - tool_input.command isn't a `git commit` invocation
#   - the call was interrupted
#   - tool_response.exit_code is present and not 0 (a host that sends one)
#   - the host names something that is not a commit in this repository
#   - the host names no commit, and HEAD's reflog proves none (above): a message
#     from -F <file> or an editor, a subject the command does not contain, a
#     commit more than REFLOG_WINDOW seconds before the hook runs, or a commit in
#     another worktree or repository. The detector reports such a commit as out
#     of band, as it reported every commit before BL-324.
#   - jq isn't installed (silent — never block Claude on missing infrastructure)

set -uo pipefail

# Locate project root (CLAUDE_PROJECT_DIR is set by Claude Code; fall back to git).
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "")}"
[ -z "$PROJECT_ROOT" ] && exit 0
[ ! -d "$PROJECT_ROOT/.claude" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Read envelope.
INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

# Filter: must be a `git commit` (not `git commit-tree`, etc.) and must have succeeded.
#
# Audit finding `specs-plans-bl029-bl030-5` (sibling of BL-020 on the
# pre-commit-gate side): the previous naive substring match
# `case "$CMD" in *"git commit"*)` false-positives on innocuous commands
# whose argv or output happens to contain the literal string `git commit`
# (e.g., `echo "see git commit later"`, `rg "git commit" docs/`,
# `cat scripts/pre-commit-gate.sh | grep "git commit"`). Each false-positive
# polluted the BL-029 ledger with a spurious entry mapped to whatever the
# current HEAD happened to be, which the out-of-band detector then trusted.
#
# Tightened classifier (verbatim from `scripts/pre-commit-gate.sh:81-93`):
#   `commit` must come immediately after `git` (separated only by whitespace),
#   and `git` must NOT be preceded by a quote — so `rg "git commit"` is rejected
#   while `cd /tmp && git commit ...` (preceded by whitespace) is accepted.
#
# --amend semantics (option C from the audit response): no special-casing.
# `git commit --amend` runs the normal flow — the amended commit is recorded
# as a fresh ledger entry under its new HEAD SHA. The pre-amend entry remains
# as an orphan SHA in the append-only ledger; this is acceptable because the
# out-of-band detector matches against ledger membership, so the amended SHA
# is correctly classified as Claude-issued rather than user-terminal. (The host
# names an amended commit with kind "amended" and its new SHA.)
_is_git_commit() {
  echo "$1" | grep -qE '(^|[^"'\''])git[[:space:]]+commit\b'
}
_is_git_commit "$CMD" || exit 0
echo "$CMD" | grep -qE '(^|[^"'\''])git[[:space:]]+commit-tree\b' && exit 0

# `## BL-324:` the success test, and the commit. Anything jq cannot read as
# `false` / `0` is not a success.
INTERRUPTED=$(echo "$INPUT" | jq -r '.tool_response.interrupted // false' 2>/dev/null)
[ "$INTERRUPTED" = "false" ] || exit 0   # BL-324-NOT-INTERRUPTED
EXIT=$(echo "$INPUT" | jq -r '.tool_response.exit_code // 0' 2>/dev/null)
[ "$EXIT" = "0" ] || exit 0   # BL-324-EXIT-CODE

# The window, in seconds, between a commit's reflog entry and this hook. Measured
# over 173 agent commits in Claude Code transcripts (BL-324): the result came
# 2.4 s after the entry at the median, 10.7 s at the 95th percentile, and within
# 30 s for 167 of them; the rest ran a long command after the commit.
REFLOG_WINDOW=30

# _reflog_commits — the commits this call made, proved from HEAD's reflog, one
# SHA per line (see the header). Nothing when the message is not inline.
_reflog_commits() {
  local now="" h="" sel="" gs="" t="" subj=""
  echo "$CMD" | grep -qE '(^|[[:space:]])(-[a-zA-Z]*F|--file)[[:space:]=]*[^-=[:space:]]' && return 0   # BL-324-REFLOG-NOFILE
  echo "$CMD" | grep -qE '(^|[[:space:]])(-[a-zA-Z]*m|--message)([[:space:]=]|["'\'']|$)|(^|[[:space:]])(-[a-zA-Z]*F[[:space:]]*-|--file[=[:space:]]-)([[:space:]]|$)' || return 0   # BL-324-REFLOG-INLINE
  now=$(date +%s)
  (cd "$PROJECT_ROOT" && git log -g -n 50 --format='%H%x09%gd%x09%gs' --date=unix HEAD 2>/dev/null) \
    | while IFS=$'\t' read -r h sel gs; do
        t="${sel##*@\{}"; t="${t%\}}"
        case "$t" in ''|*[!0-9]*) break ;; esac
        [ "$t" -ge $((now - REFLOG_WINDOW)) ] || break   # BL-324-REFLOG-WINDOW
        case "$gs" in
          "commit: "*) subj="${gs#"commit: "}" ;;
          "commit (amend): "*) subj="${gs#"commit (amend): "}" ;;
          "commit (initial): "*) subj="${gs#"commit (initial): "}" ;;
          *) continue ;;   # BL-324-REFLOG-ACTION
        esac
        [ -n "$subj" ] || continue
        case "$CMD" in *"$subj"*) printf '%s\n' "$h" ;; esac   # BL-324-REFLOG-SUBJECT
      done
}

NAMED=$(echo "$INPUT" | jq -r '.tool_response.gitOperation.commit.sha // "" | strings' 2>/dev/null)
if [ -n "$NAMED" ]; then
  case "$NAMED" in *[!0-9a-f]*) exit 0 ;; esac   # BL-324-NAMED-HEX
  # Empty unless NAMED is a commit object in this repository: nothing is written.
  SHAS=$(cd "$PROJECT_ROOT" && git rev-parse --verify --quiet "${NAMED}^{commit}" 2>/dev/null)   # BL-324-NAMED-SHA
else
  SHAS=$(_reflog_commits)
fi

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"

LEDGER="$PROJECT_ROOT/.claude/claude-commits.jsonl"
for SHA in $SHAS; do
  grep -qF "\"sha\":\"$SHA\"" "$LEDGER" 2>/dev/null && continue   # BL-324-LEDGER-ONCE
  jq -nc \
    --arg sha "$SHA" \
    --arg ts "$TS" \
    --arg sid "$SESSION_ID" \
    '{sha: $sha, timestamp: $ts, session_id: $sid, gate: "passed"}' >> "$LEDGER"
done

exit 0
