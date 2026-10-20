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
#   # BL-324-NAMED-EXISTS     drop the check    -> T11b RED
#   # BL-324-NAMED-SHA        record HEAD again -> T11b, T15 RED
#   the classifier (_is_git_commit) dropped     -> T6, T7 RED
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

# T12: a failed call fires PostToolUseFailure (no tool_response at all).
echo "T12: a PostToolUseFailure envelope is not recorded"
setup
cd "$TMP"
jq -nc '{session_id:"bl324", hook_event_name:"PostToolUseFailure", tool_name:"Bash",
  tool_input:{command:"git commit -m x"}, tool_use_id:"toolu_bl324",
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

# T13: end to end, through the hook commands a project's settings.json
# registers (soif_register_hook_roster, which init.sh and adoption share): the
# agent's commit, recorded from its real envelope, is the agent's; a commit
# made with no envelope (a terminal) is still out of band.
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
CLAUDE_PROJECT_DIR="$P" bash -c "$DET_CMD" </dev/null >/dev/null 2>&1 || true
oob() { jq -r --arg s "$1" '[.[] | select(.type == "out_of_band_commit" and .details.commit_sha == $s)] | length' "$P/.claude/bypass-audit.json" 2>/dev/null || echo ERR; }
a=$(oob "$AGENT"); t=$(oob "$TERM_SHA")
if [ -n "$REC_CMD" ] && [ -n "$DET_CMD" ] && [ "$a" = "0" ] && [ "$t" = "1" ]; then
  pass "T13"
else
  fail_ "T13" "out_of_band rows: agent commit $a (want 0), terminal commit $t (want 1); recorder '$REC_CMD', detector '$DET_CMD'"
fi
cd "$REPO_ROOT"; rm -rf "$P"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
