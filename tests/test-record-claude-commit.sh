#!/usr/bin/env bash
# tests/test-record-claude-commit.sh — BL-030 Claude-commit recorder tests.
#
# `## BL-324:` THE ENVELOPES ARE THE HOST'S. Until BL-324 every case fed
# {"tool_response":{"exit_code":0}}, a shape Claude Code never sends, so the
# suite passed while the recorder never wrote a row. Claude Code's Bash result
# carries stdout, stderr, interrupted, isImage and noOutputExpected and no exit
# code; when git printed the summary line of a commit it made, it also carries
# gitOperation.commit {sha (abbreviated), kind ("committed" | "amended"),
# branch}. env_bash builds that: the hook-input fields of Claude Code's
# documented PostToolUse contract around a tool_response whose shape is copied
# from a real transcript (dogfood run 3, commit d77fc1b, Claude Code 2.1.292),
# its stdout replaced by the fixture commit's own git output and gitOperation
# naming that commit. T3 keeps one explicit exit_code, for a host that sends
# one. T12's PostToolUseFailure shape is the one `## BL-233:` measured.
#
# Mutation proofs (each mutant applied to scripts/hooks/record-claude-commit.sh
# by its marker; the killer named):
#   # BL-324-NOT-INTERRUPTED  drop the check    -> T10 RED
#   # BL-324-EXIT-CODE        drop the check    -> T3 RED
#   # BL-324-NAMED-HEX        drop the check    -> T14 RED
#   # BL-324-NAMED-SHA        record HEAD again -> T11b, T15 RED
#     (its `rev-parse --verify` is the existence check: empty, nothing written)
#   the classifier (_is_git_commit) dropped     -> T6, T7 RED
# The commits the host does not name (`-q`, no summary line), proved from
# HEAD's reflog instead (T16-T25, T26-T31 from the review of ab785e26, T32-T52
# from the review of 829928a8). A reflog subject counts only when it EQUALS the
# first line of a message a `git commit` invocation in the command supplies
# (-m / --message, or a `-F -` heredoc), as the awk program _RC_AWK reads them.
#   # BL-324-EVENT            drop the check    -> T12 RED
#   # BL-324-REFLOG-WINDOW    drop the check    -> T18, T28 RED
#   # BL-324-WINDOW-SECONDS   30 -> 100, 86400, 31536000 -> T42 (and T28) RED
#   # BL-324-REFLOG-ACTION    any action counts -> T20 RED
#   # BL-324-REFLOG-SUBJECT   equality -> substring / stand-alone substring
#                                                -> T32-T37 RED
#   # BL-324-LEDGER-ONCE      drop the check    -> T24 RED
#   # BL-324-NO-SHOW-SIGNATURE  drop the flag   -> T31 RED (needs ssh-keygen)
#   In _RC_AWK:
#   # BL-324-AWK-DRYRUN       drop              -> T30 RED
#   # BL-324-AWK-STDIN        drop              -> T17 RED
#   # BL-324-AWK-HEREDOC      bodies to the first heredoc's command -> T41 RED
#   # BL-324-AWK-HEREDOC      unquoted $ body taken -> T48 RED
#   # BL-324-AWK-CATHEREDOC   drop the idiom    -> T43 RED
#   # BL-324-AWK-DYNMSG       drop              -> T44 RED
#   # BL-324-AWK-DYNAMIC      drop              -> T52 RED
#   # BL-324-AWK-COMMENT      drop              -> T45 RED
#   # BL-324-AWK-CLUSTER      first letter only -> T46 RED
#   # BL-324-AWK-TABS         drop              -> T47 RED
#   # BL-324-AWK-LONGEQ       drop              -> T40 RED
#   # BL-324-AWK-SQUEEZE      drop              -> T49 RED
#   # BL-324-AWK-PREFIX       drop              -> T50, T51 RED
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/scripts/hooks/record-claude-commit.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/.claude"
  ( cd "$TMP"
    git init -q
    git config user.email "test@test.local"
    git config user.name "test"
    echo "first" > f.txt && git add f.txt && git commit -qm "first" 2>/dev/null
  )
  SHA=$(cd "$TMP" && git rev-parse HEAD)
}
teardown() { rm -rf "$TMP"; }

# env_bash <command> <stdout> [gitOperation JSON] [interrupted] — a PostToolUse
# envelope for a Bash call, as Claude Code sends it. No exit_code.
env_bash() {
  jq -nc --arg c "$1" --arg o "$2" --argjson g "${3:-null}" --argjson i "${4:-false}" --arg cwd "$PWD" \
    '{session_id:"bl324", transcript_path:"/tmp/bl324.jsonl", cwd:$cwd, permission_mode:"default",
      hook_event_name:"PostToolUse", tool_name:"Bash", tool_input:{command:$c, description:"Commit"},
      tool_response:({stdout:$o, stderr:"", interrupted:$i, isImage:false, noOutputExpected:false}
        + (if $g == null then {} else {gitOperation:$g} end)),
      tool_use_id:"toolu_bl324"}'
}
# git_op <dir> [kind] — the gitOperation the host reports for <dir>'s HEAD.
git_op() {
  jq -nc --arg s "$(git -C "$1" rev-parse --short HEAD)" --arg k "${2:-committed}" \
    --arg b "$(git -C "$1" symbolic-ref --short HEAD)" '{commit:{sha:$s, kind:$k, branch:$b}}'
}
# run_hook — the hook as Claude Code runs it, from the project directory.
run_hook() { CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" >/dev/null 2>&1; }
rows() { if [ -f "$TMP/.claude/claude-commits.jsonl" ]; then wc -l < "$TMP/.claude/claude-commits.jsonl" | tr -d ' '; else echo 0; fi; }
# shas — the ledger's SHAs on one line, space-separated; empty with no ledger.
shas() { { jq -r '.sha' "$TMP/.claude/claude-commits.jsonl" 2>/dev/null || true; } | tr '\n' ' '; }

# T1: hook records a successful git commit, once, by its full SHA.
echo "T1: PostToolUse hook records the SHA of a successful git commit (real envelope, no exit_code)"
setup
cd "$TMP"
echo second > g.txt && git add g.txt
OUT=$(git commit -m 'feat: x' 2>&1)
NEW=$(git rev-parse HEAD)
env_bash "git commit -m 'feat: x'" "$OUT" "$(git_op "$TMP")" | run_hook || true
if [ "$(rows)" = "1" ] && \
   jq -e --arg sha "$NEW" '.sha == $sha' < "$TMP/.claude/claude-commits.jsonl" >/dev/null 2>&1; then
  pass "T1"
else
  fail_ "T1" "want 1 row with sha $NEW; got $(rows) row(s): $(cat "$TMP/.claude/claude-commits.jsonl" 2>/dev/null)"
fi
cd "$REPO_ROOT"; teardown

# T2: hook does NOT record a non-git-commit tool call.
echo "T2: PostToolUse hook ignores non-commit Bash calls"
setup
cd "$TMP"
env_bash "ls -la" "$(ls -la)" | run_hook || true
if [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then
  pass "T2"
else
  fail_ "T2" "ledger should not exist for ls call"
fi
cd "$REPO_ROOT"; teardown

# T3: an explicit non-zero exit_code, from a host that sends one, is a failure
# even when the commit is named.
echo "T3: PostToolUse hook honours an explicit non-zero exit_code"
setup
cd "$TMP"
echo second > g.txt && git add g.txt
OUT=$(git commit -m 'feat: x' 2>&1)
env_bash "git commit -m 'feat: x'" "$OUT" "$(git_op "$TMP")" \
  | jq -c '.tool_response.exit_code = 1' | run_hook || true
if [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then
  pass "T3"
else
  fail_ "T3" "ledger should not exist when the host reports exit_code 1"
fi
cd "$REPO_ROOT"; teardown

# T4: hook is append-only — second commit appends a row.
echo "T4: PostToolUse hook appends to existing ledger"
setup
cd "$TMP"
echo second > g.txt && git add g.txt
OUT=$(git commit -m 'second' 2>&1); S2=$(git rev-parse HEAD)
env_bash "git commit -m 'second'" "$OUT" "$(git_op "$TMP")" | run_hook || true
echo third > h.txt && git add h.txt
OUT=$(git commit -m 'third' 2>&1); S3=$(git rev-parse HEAD)
env_bash "git commit -m 'third'" "$OUT" "$(git_op "$TMP")" | run_hook || true
got=$(shas)
if [ "$got" = "$S2 $S3 " ]; then pass "T4"; else fail_ "T4" "want rows '$S2 $S3 ', got '$got'"; fi
cd "$REPO_ROOT"; teardown

# T5: hook is silent on missing .claude/ (project not initialized).
echo "T5: PostToolUse hook is a no-op when .claude/ does not exist"
TMP=$(mktemp -d)
( cd "$TMP" && git init -q && git config user.email "t@t.l" && git config user.name "t"
  echo x > x && git add x && git commit -qm x )
cd "$TMP"
echo y > y && git add y
OUT=$(git commit -m 'x' 2>&1)
env_bash "git commit -m 'x'" "$OUT" "$(git_op "$TMP")" | run_hook || true
if [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then
  pass "T5"
else
  fail_ "T5" "ledger created in uninitialized project"
fi
cd "$REPO_ROOT"; rm -rf "$TMP"

# T6-T9: BL-020 sibling — audit finding `specs-plans-bl029-bl030-5`.
# Pre-fix the classifier used a naive substring match (`*"git commit"*`),
# which false-positives on innocuous commands whose argv contains the
# literal `git commit` (echo strings, grep search patterns, etc.). Each
# false-positive polluted the ledger with HEAD-at-the-time as a spurious
# Claude-issued entry. Mirrors the BL-020 fix that landed in PR #53 for
# `scripts/pre-commit-gate.sh`. T6 and T7 carry a gitOperation naming HEAD,
# so the classifier is the only thing standing between them and a row.

# T6: quote-preceded false-positive must NOT record. The literal `git commit`
# appears immediately after a `"` in a grep search pattern (the regex
# `[^"']` rejects quote-preceded matches; start-of-line is the only other
# anchor and doesn't apply here).
echo "T6: PostToolUse hook ignores 'git commit' inside a quoted grep pattern (piped)"
setup
cd "$TMP"
env_bash 'cat scripts/pre-commit-gate.sh | grep "git commit"' "" "$(git_op "$TMP")" | run_hook || true
if [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then
  pass "T6"
else
  fail_ "T6" "ledger created for 'grep \"git commit\"' (quote-preceded false-positive)"
fi
cd "$REPO_ROOT"; teardown

# T7: grep search-string false-positive must NOT record.
echo "T7: PostToolUse hook ignores 'git commit' inside a grep/rg search pattern"
setup
cd "$TMP"
env_bash 'rg "git commit" docs/' "" "$(git_op "$TMP")" | run_hook || true
if [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then
  pass "T7"
else
  fail_ "T7" "ledger created for 'rg \"git commit\" docs/' (search-string false-positive)"
fi
cd "$REPO_ROOT"; teardown

# T8: cross-cmd-chain happy path — preceded by `&&`, not at line start.
echo "T8: PostToolUse hook DOES record a chained 'cd foo && git commit ...'"
setup
cd "$TMP"
OUT=$(cd "$TMP" && git commit --allow-empty -m 'chained' 2>&1)
NEW=$(git rev-parse HEAD)
env_bash "cd $TMP && git commit --allow-empty -m 'chained'" "$OUT" "$(git_op "$TMP")" | run_hook || true
if [ "$(rows)" = "1" ] && \
   jq -e --arg sha "$NEW" '.sha == $sha' < "$TMP/.claude/claude-commits.jsonl" >/dev/null 2>&1; then
  pass "T8"
else
  fail_ "T8" "chained 'cd && git commit' should have been recorded as $NEW; got: $(cat "$TMP/.claude/claude-commits.jsonl" 2>/dev/null)"
fi
cd "$REPO_ROOT"; teardown

# T9: --amend handling — option C: record amended commits as a fresh entry.
# Rationale: keeping the original entry as an orphan SHA is fine (the ledger
# is append-only). Recording the new HEAD ensures the out-of-band detector
# sees the amended SHA in the ledger and classifies it as Claude-issued
# rather than user-terminal. The host names the amended commit with kind
# "amended" and its new SHA.
echo "T9: PostToolUse hook records 'git commit --amend' as a fresh ledger entry (option C)"
setup
cd "$TMP"
echo second > g.txt && git add g.txt
OUT=$(git commit -m 'second' 2>&1); ORIG_SHA=$(git rev-parse HEAD)
env_bash "git commit -m 'second'" "$OUT" "$(git_op "$TMP")" | run_hook || true
OUT=$(git commit --amend -m 'second, amended' 2>&1); AMENDED_SHA=$(git rev-parse HEAD)
env_bash "git commit --amend -m 'second, amended'" "$OUT" "$(git_op "$TMP" amended)" | run_hook || true
got=$(shas)
if [ "$ORIG_SHA" != "$AMENDED_SHA" ] && [ "$got" = "$ORIG_SHA $AMENDED_SHA " ]; then
  pass "T9"
else
  fail_ "T9" "expected 2 entries (original + amended SHAs '$ORIG_SHA $AMENDED_SHA '); got: '$got'"
fi
cd "$REPO_ROOT"; teardown

# ── `## BL-324:` what PostToolUse alone does not prove ──────────────────────

# T10: an interrupted call is not recorded, even with the commit named.
echo "T10: PostToolUse hook ignores an interrupted call"
setup
cd "$TMP"
echo second > g.txt && git add g.txt
OUT=$(git commit -m 'feat: x' 2>&1)
env_bash "git commit -m 'feat: x' && sleep 600" "$OUT" "$(git_op "$TMP")" true | run_hook || true
if [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then
  pass "T10"
else
  fail_ "T10" "ledger created for an interrupted call"
fi
cd "$REPO_ROOT"; teardown

# T11: a commit that failed inside a chain that still exits 0 (PostToolUse
# fires) made nothing new: git printed no summary, so the host names no
# commit, and HEAD is a commit this call did not make.
echo "T11: PostToolUse hook ignores a git commit that failed inside a chain exiting 0"
setup
cd "$TMP"
OUT=$( { git commit -m 'feat: nothing staged' 2>&1 || true; } )
env_bash "git commit -m 'feat: nothing staged'; true" "$OUT" | run_hook || true
if [ "$(git rev-parse HEAD)" = "$SHA" ] && [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then
  pass "T11"
else
  fail_ "T11" "ledger created for a commit that did not happen (HEAD $SHA): $(cat "$TMP/.claude/claude-commits.jsonl" 2>/dev/null)"
fi
cd "$REPO_ROOT"; teardown

# T11b: the commit the host names is not in this repository (the agent
# committed in another one) — HEAD here is not what that call made.
echo "T11b: PostToolUse hook ignores a named commit this repository does not have"
setup
OTHER=$(mktemp -d)
( cd "$OTHER" && git init -q && git config user.email t@t.l && git config user.name t \
    && echo o > o && git add o && git commit -qm "other repo" )
OUT=$(cd "$OTHER" && git commit --allow-empty -m 'feat: elsewhere' 2>&1)
cd "$TMP"
env_bash "cd $OTHER && git commit --allow-empty -m 'feat: elsewhere'" "$OUT" "$(git_op "$OTHER")" | run_hook || true
if [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then
  pass "T11b"
else
  fail_ "T11b" "ledger created for a commit made in another repository: $(cat "$TMP/.claude/claude-commits.jsonl" 2>/dev/null)"
fi
cd "$REPO_ROOT"; rm -rf "$OTHER"; teardown

# T12: a failed call fires PostToolUseFailure (no tool_response at all). Its
# command names HEAD's own recent subject, so only the event stops a row.
echo "T12: a PostToolUseFailure envelope is not recorded"
setup
cd "$TMP"
jq -nc '{session_id:"bl324", hook_event_name:"PostToolUseFailure", tool_name:"Bash",
  tool_input:{command:"git commit -q -m '"'"'first'"'"'"}, tool_use_id:"toolu_bl324",
  error:"Exit code 1\nnothing to commit, working tree clean", is_interrupt:false}' | run_hook || true
if [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then
  pass "T12"
else
  fail_ "T12" "ledger created for a PostToolUseFailure envelope"
fi
cd "$REPO_ROOT"; teardown

# T14: a gitOperation that names something other than a hash (here HEAD) is
# not taken as a commit.
echo "T14: PostToolUse hook ignores a gitOperation whose sha is not a hash"
setup
cd "$TMP"
env_bash "git commit -m 'feat: x'" "" '{"commit":{"sha":"HEAD","kind":"committed","branch":"main"}}' | run_hook || true
if [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then
  pass "T14"
else
  fail_ "T14" "ledger created from a gitOperation naming 'HEAD'"
fi
cd "$REPO_ROOT"; teardown

# T15: the row carries the commit the host named, not HEAD: a call that commits
# and then moves HEAD elsewhere records the commit it made.
echo "T15: PostToolUse hook records the named commit even when HEAD moved after it"
setup
cd "$TMP"
git checkout -q -b side
echo s > s.txt && git add s.txt
OUT=$(git commit -m 'feat: on side' 2>&1); MADE=$(git rev-parse HEAD); OP=$(git_op "$TMP")
git checkout -q -
env_bash "git commit -m 'feat: on side' && git checkout -" "$OUT" "$OP" | run_hook || true
if [ "$(rows)" = "1" ] && \
   jq -e --arg sha "$MADE" '.sha == $sha' < "$TMP/.claude/claude-commits.jsonl" >/dev/null 2>&1; then
  pass "T15"
else
  fail_ "T15" "want 1 row with sha $MADE (HEAD is now $(git rev-parse HEAD)); got: $(cat "$TMP/.claude/claude-commits.jsonl" 2>/dev/null)"
fi
cd "$REPO_ROOT"; teardown

# ── `## BL-324:` a commit the host does not name ────────────────────────────
# A `-q` commit prints no summary line, so the envelope has no gitOperation.
# The recorder then takes, from HEAD's reflog, each `commit` / `commit (amend)`
# / `commit (initial)` entry written in the last 30 seconds whose subject is
# in the command's own text, when the command supplies its message inline
# (-m / --message, or -F - with a heredoc) and not from a file.

# setup_old <subject> — like setup, but the one commit is dated 2020, so its
# reflog entry is far outside the recorder's window.
setup_old() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/.claude"
  ( cd "$TMP" && git init -q && git config user.email t@t.l && git config user.name t
    echo old > o.txt && git add o.txt \
      && GIT_COMMITTER_DATE="2020-01-01T00:00:00Z" GIT_AUTHOR_DATE="2020-01-01T00:00:00Z" git commit -qm "$1" )
  SHA=$(cd "$TMP" && git rev-parse HEAD)
}

# T16: a -q commit with -m is recorded, once, by its full SHA.
echo "T16: a -q commit (no gitOperation) is recorded from HEAD's reflog"
setup
cd "$TMP"
echo q > q.txt && git add q.txt
CMDQ="git commit -q -m 'feat: a quiet commit'"
OUT=$(eval "$CMDQ" 2>&1); NEW=$(git rev-parse HEAD)
env_bash "$CMDQ" "$OUT" | run_hook || true
if [ "$(shas)" = "$NEW " ]; then pass "T16"; else fail_ "T16" "want '$NEW ', got '$(shas)'"; fi
cd "$REPO_ROOT"; teardown

# T17: the message from a heredoc on stdin (-F -) is in the command too.
echo "T17: a -q commit whose message is a heredoc on stdin (-F -) is recorded"
setup
cd "$TMP"
echo h > h.txt && git add h.txt
CMDH="git commit -q -F - <<'MSG'
feat: from a heredoc

The body.
MSG"
OUT=$(eval "$CMDH" 2>&1); NEW=$(git rev-parse HEAD)
env_bash "$CMDH" "$OUT" | run_hook || true
if [ "$(shas)" = "$NEW " ]; then pass "T17"; else fail_ "T17" "want '$NEW ', got '$(shas)'"; fi
cd "$REPO_ROOT"; teardown

# T18: the commit fails inside `; true`; HEAD's newest entry has the subject the
# command supplied but is from 2020: outside the window, so nothing is recorded.
echo "T18: a failed -q commit is not recorded when HEAD's matching entry is old"
setup_old 'feat: same subject'
cd "$TMP"
CMDF="git commit -q -m 'feat: same subject'; true"
OUT=$(eval "$CMDF" 2>&1)
env_bash "$CMDF" "$OUT" | run_hook || true
if [ "$(git rev-parse HEAD)" = "$SHA" ] && [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then
  pass "T18"
else
  fail_ "T18" "a commit that did not happen was recorded: $(shas)"
fi
cd "$REPO_ROOT"; teardown

# T19: the commit fails inside `; true`; HEAD's newest entry is recent, but its
# subject is not the message the command supplied.
echo "T19: a failed -q commit is not recorded when HEAD's recent entry has another subject"
setup
cd "$TMP"
CMDF="git commit -q -m 'feat: never made'; true"
OUT=$(eval "$CMDF" 2>&1)
env_bash "$CMDF" "$OUT" | run_hook || true
if [ "$(git rev-parse HEAD)" = "$SHA" ] && [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then
  pass "T19"
else
  fail_ "T19" "HEAD's own commit was recorded for a commit that failed: $(shas)"
fi
cd "$REPO_ROOT"; teardown

# T20: a recent reflog entry with the command's subject that is not a commit
# (a cherry-pick from another worktree) is not taken; the command's own commit
# failed.
echo "T20: a recent cherry-pick entry with the same subject is not recorded"
setup
WT=$(mktemp -d)/wt
( cd "$TMP" && git worktree add -q -b side "$WT" >/dev/null 2>&1 )
( cd "$WT" && echo p > p.txt && git add p.txt && git commit -qm 'feat: picked' )
( cd "$TMP" && git cherry-pick "$(git -C "$WT" rev-parse HEAD)" >/dev/null 2>&1 )
cd "$TMP"
CMDF="git commit -q -m 'feat: picked'; true"
OUT=$(eval "$CMDF" 2>&1)
env_bash "$CMDF" "$OUT" | run_hook || true
if git log -g -1 --format=%gs HEAD | grep -q '^cherry-pick: feat: picked$' && [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then
  pass "T20"
else
  fail_ "T20" "want a cherry-pick entry and no row; HEAD@{0} '$(git log -g -1 --format=%gs HEAD)', rows: $(shas)"
fi
cd "$REPO_ROOT"; rm -rf "$(dirname "$WT")"; teardown

# T21: a message from a file (-F <file>) is not taken, even when the file is
# written by the same command and another -m (git log's) is in it.
echo "T21: a -q commit with -F <file> is not recorded"
setup
cd "$TMP"
echo f > f.txt && git add f.txt
CMDFILE="printf '%s\n' 'feat: from a file' > m.txt && git commit -q -F m.txt && git log -1 -m --format=%s"
OUT=$(eval "$CMDFILE" 2>&1)
env_bash "$CMDFILE" "$OUT" | run_hook || true
if git log -1 --format=%s | grep -q '^feat: from a file$' && [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then
  pass "T21"
else
  fail_ "T21" "want the commit made and no row; rows: $(shas)"
fi
cd "$REPO_ROOT"; teardown

# T22: no message supplied (--amend --no-edit); the subject stands alone in the
# command only inside a comment.
echo "T22: a -q commit with no inline message is not recorded"
setup
cd "$TMP"
CMDNE="git commit -q --amend --no-edit # 'first'"
OUT=$(eval "$CMDNE" 2>&1)
env_bash "$CMDNE" "$OUT" | run_hook || true
if git log -g -1 --format=%gs HEAD | grep -q '^commit (amend): first$' && [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then
  pass "T22"
else
  fail_ "T22" "want an amend entry and no row; HEAD@{0} '$(git log -g -1 --format=%gs HEAD)', rows: $(shas)"
fi
cd "$REPO_ROOT"; teardown

# T23: two -q commits in one call: both are proved, both are recorded.
echo "T23: two -q commits in one call are both recorded"
setup
cd "$TMP"
CMD2="echo 1 > one.txt && git add one.txt && git commit -q -m 'feat: one' && echo 2 > two.txt && git add two.txt && git commit -q -m 'feat: two'"
OUT=$(eval "$CMD2" 2>&1)
TWO=$(git rev-parse HEAD); ONE=$(git rev-parse HEAD~1)
env_bash "$CMD2" "$OUT" | run_hook || true
got=$(shas)
if [ "$(rows)" = "2" ] && case " $got" in *" $ONE "*) true ;; *) false ;; esac && case " $got" in *" $TWO "*) true ;; *) false ;; esac; then
  pass "T23"
else
  fail_ "T23" "want '$ONE' and '$TWO', got '$got'"
fi
cd "$REPO_ROOT"; teardown

# T24: a commit already in the ledger is not written twice: the agent's -q
# commit, then the same command again failing inside `; true`, within the window.
echo "T24: a failed repeat of a recorded -q commit adds no row"
setup
cd "$TMP"
echo q > q.txt && git add q.txt
CMDQ="git commit -q -m 'feat: a quiet commit'"
OUT=$(eval "$CMDQ" 2>&1); NEW=$(git rev-parse HEAD)
env_bash "$CMDQ" "$OUT" | run_hook || true
CMDF="git commit -q -m 'feat: a quiet commit'; true"
OUT=$(eval "$CMDF" 2>&1)
env_bash "$CMDF" "$OUT" | run_hook || true
if [ "$(shas)" = "$NEW " ]; then pass "T24"; else fail_ "T24" "want one row '$NEW ', got '$(shas)'"; fi
cd "$REPO_ROOT"; teardown

# T25: the project is a linked worktree; its HEAD has its own reflog.
echo "T25: a -q commit is recorded when the project is a linked worktree"
setup
WT=$(mktemp -d)/wt
( cd "$TMP" && git worktree add -q -b wtb "$WT" >/dev/null 2>&1 )
mkdir -p "$WT/.claude"
cd "$WT"
echo w > w.txt && git add w.txt
CMDQ="git commit -q -m 'feat: in a worktree'"
OUT=$(eval "$CMDQ" 2>&1); NEW=$(git rev-parse HEAD)
env_bash "$CMDQ" "$OUT" | CLAUDE_PROJECT_DIR="$WT" bash "$HOOK" >/dev/null 2>&1 || true
got=$({ jq -r '.sha' "$WT/.claude/claude-commits.jsonl" 2>/dev/null || true; } | tr '\n' ' ')
if [ "$got" = "$NEW " ]; then pass "T25"; else fail_ "T25" "want '$NEW ', got '$got'"; fi
cd "$REPO_ROOT"; rm -rf "$(dirname "$WT")"; teardown

# ── review of ab785e26: someone else's commit in the window ─────────────────
# user_commit <subject> [age-seconds] — a commit in $TMP that the agent did not
# make (a terminal), its reflog entry <age> seconds old (default 0).
user_commit() {
  local when=""
  [ -n "${2:-}" ] && when="@$(( $(date +%s) - $2 )) +0000"
  ( cd "$TMP" && echo "$1" >> user.txt && git add user.txt \
      && if [ -n "$when" ]; then GIT_COMMITTER_DATE="$when" GIT_AUTHOR_DATE="$when" git commit -qm "$1"; else git commit -qm "$1"; fi )
}

# T26: the user's subject `fix` is a prefix of the agent's `fix(x): y`; the
# agent's commit fails. Not recorded: the subject must stand alone.
echo "T26: a user's 'fix' is not taken for an agent's 'fix(x): y' that failed"
setup
user_commit fix
cd "$TMP"
CMDF="git commit -q -m 'fix(x): y'; true"
OUT=$(eval "$CMDF" 2>&1)
env_bash "$CMDF" "$OUT" | run_hook || true
if [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then pass "T26"; else fail_ "T26" "the user's commit was recorded: $(shas)"; fi
cd "$REPO_ROOT"; teardown

# T27: the user's `wip` sits at the end of the agent's `chore: wip` (and inside
# `chore: wipe the cache`); both agent commits fail. Not recorded.
echo "T27: a user's 'wip' is not taken for an agent's 'chore: wip' or 'chore: wipe the cache' that failed"
setup
user_commit wip
cd "$TMP"
for CMDF in "git commit -q -m 'chore: wip'; true" "git commit -q -m 'chore: wipe the cache'; true"; do
  OUT=$(eval "$CMDF" 2>&1)
  env_bash "$CMDF" "$OUT" | run_hook || true
done
if [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then pass "T27"; else fail_ "T27" "the user's commit was recorded: $(shas)"; fi
cd "$REPO_ROOT"; teardown

# T28: an entry 120 seconds old with the exact subject; the agent's commit
# fails. Outside the 30 s window: not recorded.
echo "T28: a matching entry 120 seconds old is not recorded"
setup
user_commit 'feat: two minutes ago' 120
cd "$TMP"
CMDF="git commit -q -m 'feat: two minutes ago'; true"
OUT=$(eval "$CMDF" 2>&1)
env_bash "$CMDF" "$OUT" | run_hook || true
if [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then pass "T28"; else fail_ "T28" "a 120 s old entry was recorded: $(shas)"; fi
cd "$REPO_ROOT"; teardown

# T29: a call that only writes about `git commit -m` into a notes file; the
# user's recent subject is `notes`. No commit, no row.
echo "T29: a heredoc that only mentions 'git commit -m' records nothing"
setup
user_commit notes
cd "$TMP"
mkdir -p docs
CMDN="cat >> docs/notes.md <<'EOF'
run git commit -m before you push
EOF"
OUT=$(eval "$CMDN" 2>&1)
env_bash "$CMDN" "$OUT" | run_hook || true
if [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then pass "T29"; else fail_ "T29" "recorded: $(shas)"; fi
cd "$REPO_ROOT"; teardown

# T30: --dry-run commits nothing; the user's recent commit has the same
# subject. Not recorded.
echo "T30: a --dry-run commit records nothing"
setup
user_commit 'feat: dry'
cd "$TMP"
echo d > d.txt && git add d.txt
CMDD="git commit --dry-run -q -m 'feat: dry'"
OUT=$( { eval "$CMDD" 2>&1 || true; } )
env_bash "$CMDD" "$OUT" | run_hook || true
if [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then pass "T30"; else fail_ "T30" "recorded: $(shas)"; fi
cd "$REPO_ROOT"; teardown

# T31: log.showSignature=true prints a signature line before a signed commit's
# reflog line; the recorder reads the reflog with --no-show-signature. Needs
# ssh-keygen (an SSH signing key made here, in the temp folder).
echo "T31: a signed -q commit is recorded with log.showSignature=true"
if command -v ssh-keygen >/dev/null 2>&1; then
  setup
  cd "$TMP"
  ssh-keygen -q -t ed25519 -N '' -C bl324 -f "$TMP/.k" >/dev/null 2>&1
  git config gpg.format ssh && git config user.signingkey "$TMP/.k.pub" && git config log.showSignature true
  echo s > s.txt && git add s.txt
  CMDS="git commit -q -S -m 'feat: signed'"
  OUT=$(eval "$CMDS" 2>&1); NEW=$(git rev-parse HEAD)
  env_bash "$CMDS" "$OUT" | run_hook || true
  if [ "$(shas)" = "$NEW " ]; then pass "T31"; else fail_ "T31" "want '$NEW ', got '$(shas)'"; fi
  cd "$REPO_ROOT"; teardown
else
  echo "  [SKIP] T31 — ssh-keygen not installed"
fi

# ── review of 829928a8: only the messages the commit itself supplies ────────
# agent_shape <id> <user-subject> <command> — the user commits <subject> in the
# window; the agent's command copies that word somewhere that is not a commit
# message and makes its own -q commit, which must be the only row.
agent_shape() {
  local id="$1" usr="$2" cmd="$3" ag="" out=""
  setup
  user_commit "$usr"
  cd "$TMP"
  echo "$id" > "s-$id.txt" && git add "s-$id.txt"
  out=$(eval "$cmd" 2>&1); ag=$(git rev-parse HEAD)
  env_bash "$cmd" "$out" | run_hook || true
  if [ "$(git log -1 --format=%s)" != "$usr" ] && [ "$(shas)" = "$ag " ]; then
    pass "$id"
  else
    fail_ "$id" "want only the agent's '$ag ', got '$(shas)' (HEAD subject '$(git log -1 --format=%s)')"
  fi
  cd "$REPO_ROOT"; teardown
}
NL='
'
echo "T32: a user's 'wip' echoed by the agent's command is not taken; the agent's -q commit is"
agent_shape T32 wip 'echo "wip"; git commit -q -m "chore: x"'
echo "T33: a user's 'fix' as a grep pattern is not taken"
agent_shape T33 fix 'grep -q "fix" b.txt; git commit -q -m "chore: y"'
echo "T34: a user's 'docs' as a git add path is not taken"
agent_shape T34 docs "mkdir -p docs && echo d > docs/d.txt && git add \"docs\"; git commit -q -m \"chore: z\""
echo "T35: a user's 'tmp' as a touch argument is not taken"
agent_shape T35 tmp "touch 'tmp'; git commit -q -m \"chore: t\""
echo "T36: a user's 'x' as a --format value is not taken"
agent_shape T36 x "git log -1 --format='x' >/dev/null; git commit -q -m \"chore: f\""
echo "T37: a user's 'wip' as a line of an unrelated heredoc is not taken"
agent_shape T37 wip "cat > n.txt <<'END'${NL}wip${NL}END${NL}git commit -q -m \"chore: h\""

# rec_case <id> <command> — the agent's command makes one -q commit; it must be
# recorded by its SHA.
rec_case() {
  local id="$1" cmd="$2" out="" new=""
  setup
  cd "$TMP"
  echo "$id" > "r-$id.txt" && git add "r-$id.txt"
  out=$(eval "$cmd" 2>&1); new=$(git rev-parse HEAD)
  env_bash "$cmd" "$out" | run_hook || true
  if [ "$new" != "$SHA" ] && [ "$(shas)" = "$new " ]; then pass "$id"; else fail_ "$id" "want '$new ', got '$(shas)' (out: $out)"; fi
  cd "$REPO_ROOT"; teardown
}
echo "T38: a multi-line -m is matched by its first line"
rec_case T38 "git commit -q -m 'feat: line one${NL}line two'"
echo "T39: -m=X gives git the message '=X', and that is what is matched"
rec_case T39 "git commit -q -m='feat: eq'"
echo "T40: --message=X is a message"
rec_case T40 "git commit -q --message='feat: long eq'"

# T41: two heredocs on one line; the first (cat's) carries the user's 'wip',
# the second is the agent's -F - message. Only the agent's commit is recorded.
echo "T41: a heredoc is matched only to its own command"
agent_shape T41 wip "cat > a.txt <<'A' && git commit -q -F - <<'MSG'${NL}wip${NL}A${NL}feat: second heredoc${NL}MSG"

# T42: an entry 45 seconds old with the agent's exact message; the agent's
# commit fails. Outside 30 s: not recorded (a 100 s window would take it).
echo "T42: a matching entry 45 seconds old is not recorded"
setup
user_commit 'feat: forty-five seconds ago' 45
cd "$TMP"
CMDF="git commit -q -m 'feat: forty-five seconds ago'; true"
OUT=$(eval "$CMDF" 2>&1)
env_bash "$CMDF" "$OUT" | run_hook || true
if [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then pass "T42"; else fail_ "T42" "a 45 s old entry was recorded: $(shas)"; fi
cd "$REPO_ROOT"; teardown

echo "T43: -m \"\$(cat <<'EOF' ... EOF)\" is matched by the heredoc's first line"
rec_case T43 "git commit -q -m \"\$(cat <<'END'${NL}feat: idiom${NL}${NL}A body (with parens) and \"quotes\".${NL}END${NL})\""

# no_case <id> <user-subject> <command> — the agent's command fails to commit
# (nothing staged); nothing may be recorded although the user's commit is in
# the window.
no_case() {
  local id="$1" usr="$2" cmd="$3" out=""
  setup
  user_commit "$usr"
  cd "$TMP"
  out=$(eval "$cmd" 2>&1)
  env_bash "$cmd" "$out" | run_hook || true
  if [ ! -f "$TMP/.claude/claude-commits.jsonl" ]; then pass "$id"; else fail_ "$id" "the user's commit was recorded: $(shas)"; fi
  cd "$REPO_ROOT"; teardown
}
echo "T44: a message with an expansion in it (-m \"wip\$X\") is not read as 'wip'"
no_case T44 wip 'X=""; git commit -q -m "wip$X"; true'

echo "T45: a comment with an apostrophe before the commit does not hide its message"
rec_case T45 "# don't skip this${NL}git commit -q -m 'feat: after a comment'"
echo "T46: -qm (a cluster of short options) carries the message"
rec_case T46 "git commit -qm 'feat: cluster'"
echo "T47: a <<- heredoc has its tabs removed"
rec_case T47 "git commit -q -F - <<-MSG${NL}	feat: tabbed${NL}	MSG"

echo "T48: an unquoted heredoc that expands \$X is not read literally"
no_case T48 'feat: $X' "X=''; git commit -q -F - <<MSG${NL}feat: \$X${NL}MSG${NL}true"

echo "T49: runs of spaces are squeezed, as git's reflog does"
rec_case T49 "git commit -q -m 'feat:  two  spaces'"
echo "T50: a leading NAME=value assignment does not hide the commit"
rec_case T50 "GIT_AUTHOR_NAME=bl324 git commit -q -m 'feat: env'"
echo "T51: a leading 'if' does not hide the commit"
rec_case T51 "if git commit -q -m 'feat: in an if'; then :; fi"
echo "T52: -m \"feat: \$X\" is an expansion, not the literal text"
no_case T52 'feat: $X' 'X=""; git commit -q -m "feat: $X"; true'

# T13: end to end, through the hook commands a project's settings.json
# registers (soif_register_hook_roster, which init.sh and adoption share): the
# agent's commit, recorded from its real envelope, is the agent's; a commit
# made with no envelope (a terminal) is still out of band. The agent's second
# commit is a -q one, made after the terminal commit and within its window.
echo "T13: end to end through the registered hooks: the agent's commit is not out of band; a terminal commit is"
P=$(mktemp -d)
mkdir -p "$P/.claude" "$P/scripts/hooks" "$P/scripts/lib"
cp "$REPO_ROOT/scripts/hooks/record-claude-commit.sh" "$P/scripts/hooks/"
cp "$REPO_ROOT/scripts/detect-out-of-band-commits.sh" "$P/scripts/"
cp "$REPO_ROOT/scripts/lib/enforcement-level.sh" "$REPO_ROOT/scripts/lib/bypass-audit.sh" "$P/scripts/lib/"
printf '{"enforcement_level":"light"}\n' > "$P/.claude/manifest.json"
echo '{}' > "$P/.claude/settings.json"
( . "$REPO_ROOT/scripts/lib/claude-settings.sh" && soif_register_hook_roster "$P/.claude/settings.json" )
REC_CMD=$(jq -r '[.hooks.PostToolUse[]?.hooks[]?.command | strings | select(contains("record-claude-commit.sh"))] | first // ""' "$P/.claude/settings.json")
DET_CMD=$(jq -r '[.hooks.SessionStart[]?.hooks[]?.command | strings | select(contains("detect-out-of-band-commits.sh"))] | first // ""' "$P/.claude/settings.json")
cd "$P"
git init -q && git config user.email t@t.l && git config user.name t
echo base > base.txt && git add base.txt && git commit -qm "chore: base"
CLAUDE_PROJECT_DIR="$P" bash -c "$DET_CMD" </dev/null >/dev/null 2>&1 || true
echo a > a.txt && git add a.txt
OUT=$(git commit -m "feat: the agent's commit" 2>&1); AGENT=$(git rev-parse HEAD)
env_bash "git commit -m \"feat: the agent's commit\"" "$OUT" "$(git_op "$P")" \
  | CLAUDE_PROJECT_DIR="$P" bash -c "$REC_CMD" >/dev/null 2>&1 || true
echo t > t.txt && git add t.txt && git commit -qm "chore: typed in a terminal"; TERM_SHA=$(git rev-parse HEAD)
echo q > q.txt && git add q.txt
CMDQ="git commit -q -m 'feat: the agent, quietly'"
OUT=$(eval "$CMDQ" 2>&1); QUIET=$(git rev-parse HEAD)
env_bash "$CMDQ" "$OUT" | CLAUDE_PROJECT_DIR="$P" bash -c "$REC_CMD" >/dev/null 2>&1 || true
CLAUDE_PROJECT_DIR="$P" bash -c "$DET_CMD" </dev/null >/dev/null 2>&1 || true
oob() { jq -r --arg s "$1" '[.[] | select(.type == "out_of_band_commit" and .details.commit_sha == $s)] | length' "$P/.claude/bypass-audit.json" 2>/dev/null || echo ERR; }
a=$(oob "$AGENT"); q=$(oob "$QUIET"); t=$(oob "$TERM_SHA")
if [ -n "$REC_CMD" ] && [ -n "$DET_CMD" ] && [ "$a" = "0" ] && [ "$q" = "0" ] && [ "$t" = "1" ]; then
  pass "T13"
else
  fail_ "T13" "out_of_band rows: agent commit $a (want 0), agent -q commit $q (want 0), terminal commit $t (want 1); recorder '$REC_CMD', detector '$DET_CMD'"
fi
cd "$REPO_ROOT"; rm -rf "$P"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
