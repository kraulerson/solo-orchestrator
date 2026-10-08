#!/usr/bin/env bash
# tests/test-bl322-s4-wording.sh — `## BL-322:` S4: dogfood run 3's wording
# findings (11, 14, 17, 18), the Development Guardrails 4.4.1 follow-ups, and two
# S2 review residuals (R-S2-6, R-S2-7).
#
# WHAT RUN 3 HIT, AND WHAT IS PINNED HERE.
#   11  The session start said "blocked until you call: qdrant-find, context7". The
#       technician called resolve-library-id, and the first edit was refused: the
#       check counts only a Context7 query-docs that returned (session-mcp-gate.sh).
#   14  The lone-commit rule under an approval (`git commit -m "subject" -m "body"`,
#       nothing before or after it, no -a, no paths) was learned from refusals; the
#       docs the technician read before committing did not have it. A message that
#       names a Guardrails protected path (and, from 4.4.1, one of their hook scripts
#       that write approvals) is refused too; `git commit -F <file>` is the route.
#   17  The assessment prompt pre-filled adoptedAtCommit with the commit before the
#       adoption commit, unexplained, and its `answers` keys had nowhere for
#       availability and exposure.
#   18  RELEASE_NOTES.md is the template; the project's release tags were not
#       carried, and nothing said so.
#   4.4.1  The user's override asks for a code typed back at a real terminal.
#   R-S2-6  After replacing a framework script, the run still printed "NOT DONE …
#       LEFT ALONE … yours, kept: scripts/validate.sh".
#   R-S2-7  Scout said "kept a copy, then replaced" for files adoption only copies
#       (.mcp.json, settings.local.json, other git hooks) or composes (settings.json),
#       and for files adoption never touches.
#
# CASES
#   G1  the session start names what satisfies the MCP check: a qdrant-find that
#       returned (empty counts) and Context7's query-docs (resolve-library-id alone
#       does not)
#   G2  a server that is not configured is not listed
#   O1  `pending-approval.sh --offer` (Guardrails 4.4.0+) states the lone-commit rule
#       and the `git commit -F` route for a question that can approve a commit, and
#       only for one
#   H1  the commit check's hold message says the same
#   F1  every spelling of `git commit -F`/`--file`, quoted or not, reaches the
#       Build-Loop message check; F2 the TDD warn detector and F3 the
#       backlog-references lint read a quoted message file; F4 all four readers
#       in pre-commit-gate.sh share _commit_msg_file; F5 the checklist's subject
#       reads one (review R-S4-1). F1 also holds a cluster that ends at an
#       option taking an attached value: `-S0xC -F`, `-Sabc -F`, `-tc -F`
#       (`## BL-322:` S5, review R2-1), and `-uno -sF`; and a path with git's
#       `:(optional)` prefix (review R-S5-5)
#   P1  the assessment prompt explains adoptedAtCommit and where availability and
#       exposure live
#   P2  the assessment prompt says the release history was not carried
#   D1  docs/adoption.md §7: the lone-commit rule, the -F route, the override's code
#   D2  the CLAUDE.md template and the Builder's Guide: the lone-commit rule, -F
#   D3  the User Guide links section 7 by URL: it ships without adoption.md
#   R1  a real adoption that replaces a framework script does not say it left it
#       alone (R-S2-6)
#   S1  Scout's bucket for every path is what a real adoption of the same tree does
#       to it: replaced, composed, or only copied / not touched, measured on disk
#       and in the archive's MANIFEST (R-S2-7)
#   S2  .claude/phase-state.json: Scout says it stays and that adoption stops;
#       adoption stops and leaves it unchanged
#   S3  the uncommitted-work row says adoption commits only what it writes
#   M   mutants: each edits ONE marked line (or one exact line) in a mirror, checks
#       the edit landed and still parses, and needs a named case to go RED
#
# Hermetic: temp dirs only, no network, no Guardrails clone (adoption runs with
# a seam that points at an empty folder), no MCP step, CLAUDE_CONFIG_DIR pointed
# at an empty folder. bash 3.2 safe.
set -uo pipefail
unset GITHUB_BASE_REF 2>/dev/null || true
export SOIF_ADOPT_MCP=off   # BL-311-MCP-SEAM

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

for t in jq git; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bl322s4.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT INT TERM
newtmp() { mktemp -d "$WORK/tXXXXXX"; }
CASE_DETAIL=""
TAB="$(printf '\t')"
gitq() { git -C "$1" "${@:2}" >/dev/null 2>&1; }
has() { grep -qF -- "$2" <<< "$1"; }

# ── G: the session start's MCP line ─────────────────────────────────────────
# FW SERVERS — the SessionStart hook's output in a project whose settings
# register SERVERS (a JSON object of names), with the user config pointed at an
# empty folder so nothing on this machine is read.
GATE_TEXT=""
session_start() {
  local d="" cfg=""
  d="$(newtmp)"; cfg="$(newtmp)"
  mkdir -p "$d/.claude" && printf '{"mcpServers": %s}\n' "$2" > "$d/.claude/settings.json"
  GATE_TEXT="$( cd "$d" && printf '{"source":"startup"}' | CLAUDE_CONFIG_DIR="$cfg" bash "$1/scripts/session-test-gate-check.sh" 2>&1 )"
}
case_G1() {   # both servers: each line says what counts
  session_start "$1" '{"context7": {}, "qdrant": {}}'
  has "$GATE_TEXT" "MCP CHECK ACTIVE: Write/Edit operations are blocked until each call below has returned successfully in this session:" \
    || { CASE_DETAIL="no header: $GATE_TEXT"; return 1; }
  has "$GATE_TEXT" "MCP GATE" && { CASE_DETAIL="the line still calls it a gate (a word kept for phase transitions)"; return 1; }
  has "$GATE_TEXT" "  - qdrant-find. An empty result counts; a call that errors does not." \
    || { CASE_DETAIL="the qdrant line does not say what counts"; return 1; }
  has "$GATE_TEXT" "query-docs (mcp__context7__query-docs)" \
    || { CASE_DETAIL="the Context7 line does not name query-docs"; return 1; }
  has "$GATE_TEXT" "resolve-library-id alone does not count" \
    || { CASE_DETAIL="the Context7 line does not say resolve-library-id alone does not count"; return 1; }
  has "$GATE_TEXT" "until you call: qdrant-find, context7" && { CASE_DETAIL="the old line is still printed"; return 1; }
  return 0
}
case_G2() {   # one server each way: the other is not listed
  session_start "$1" '{"qdrant": {}}'
  has "$GATE_TEXT" "  - qdrant-find." || { CASE_DETAIL="qdrant only: no qdrant line"; return 1; }
  has "$GATE_TEXT" "query-docs" && { CASE_DETAIL="qdrant only: a Context7 line"; return 1; }
  session_start "$1" '{"context7": {}}'
  has "$GATE_TEXT" "query-docs (mcp__context7__query-docs)" || { CASE_DETAIL="Context7 only: no Context7 line"; return 1; }
  has "$GATE_TEXT" "  - qdrant-find." && { CASE_DETAIL="Context7 only: a qdrant line"; return 1; }
  session_start "$1" '{}'
  has "$GATE_TEXT" "MCP CHECK ACTIVE" && { CASE_DETAIL="no server: the check is announced"; return 1; }
  return 0
}

# ── O, H: the approval guidance ─────────────────────────────────────────────
# A project with Guardrails at the minimum (the reply route), one commit, a
# staged change. The helpers are tests/test-bl320-approval-schema2.sh's.
fx() {
  local d="$1" v="${2:-4.4.0}"
  mkdir -p "$d/.claude" || return 1
  ( cd "$d" && git init -q && git config user.email t@t.local && git config user.name T \
      && git remote add origin "$d/../not-a-remote.git" \
      && printf 'seed\n' > seed.txt && git add seed.txt && git commit -q --no-verify -m seed ) >/dev/null 2>&1 || return 1
  jq -n --arg v "$v" '{frameworkVersion: $v, enforcement_level: "strict", activeHooks: ["enforce-evaluate"]}' \
    > "$d/.claude/manifest.json" || return 1
  printf '[]\n' > "$d/.claude/bypass-audit.json"
}
stage() { printf 'change\n' > "$1/a.txt" && git -C "$1" add a.txt; }
case_O1() {   # the offer's own output
  local d="" out="" rc=0
  d="$(newtmp)/p"; fx "$d" || { CASE_DETAIL="fixture"; return 1; }
  stage "$d"
  out="$( cd "$d" && bash "$1/scripts/pending-approval.sh" --offer "Commit the fix?" --options "A1: Commit the staged fix" "A2: Hold - do not commit" --approves A1 --recommendation A1 </dev/null 2>&1 )" || rc=$?
  [ "$rc" -eq 0 ] || { CASE_DETAIL="rc=$rc: $out"; return 1; }
  has "$out" 'commit with one lone command: git commit -m "subject" -m "body"' || { CASE_DETAIL="no lone-commit rule: $out"; return 1; }
  has "$out" "nothing before it, not even cd <folder> &&; nothing after it; no -a, no paths" || { CASE_DETAIL="the rule does not say what is refused"; return 1; }
  has "$out" "then: git commit -F <that file>" || { CASE_DETAIL="no -F route"; return 1; }
  has "$out" "mark-evaluated.sh, record-approval.sh" || { CASE_DETAIL="the -F route does not name the hook scripts"; return 1; }
  has "$out" "or a path they protect, such as" || { CASE_DETAIL="the protected paths read as a complete list (review R-S4-4)"; return 1; }
  # A question that approves nothing (a scope cut) is not about a commit.
  d="$(newtmp)/p"; fx "$d" || { CASE_DETAIL="fixture 2"; return 1; }
  out="$( cd "$d" && bash "$1/scripts/pending-approval.sh" --offer "Cut the scope?" --options "A1: Cut it" "A2: Keep it" --recommendation A1 </dev/null 2>&1 )" || rc=$?
  [ "$rc" -eq 0 ] || { CASE_DETAIL="rc=$rc: $out"; return 1; }
  has "$out" "git commit" && { CASE_DETAIL="a question that approves nothing gets the commit rule: $out"; return 1; }
  return 0
}
case_H1() {   # the commit check's hold, while the question waits
  local d="" out="" r=""
  d="$(newtmp)/p"; fx "$d" || { CASE_DETAIL="fixture"; return 1; }
  jq -n '{schema: 2, question: "Commit the fix?",
          options: [{id: "A1", text: "Commit the staged fix", approves: "commit"},
                    {id: "A2", text: "Hold - do not commit", approves: "none"}],
          recommendation: "A1", offered_at: "2026-10-08T00:00:00Z"}' > "$d/.claude/pending-approval.json"
  out="$( cd "$d" && jq -nc --arg c "$d" '{session_id:"s4", hook_event_name:"PreToolUse", cwd:$c, tool_name:"Bash", tool_input:{command:"git commit -m \"fix: x\""}}' \
          | SKIP_LINT=1 bash "$1/scripts/pre-commit-gate.sh" 2>/dev/null )"
  r="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"
  has "$r" "pending user decision" || { CASE_DETAIL="not held: $out"; return 1; }
  has "$r" 'commit with a lone git commit -m "subject" -m "body"' || { CASE_DETAIL="no lone-commit rule: $r"; return 1; }
  has "$r" "not even cd <folder> &&" || { CASE_DETAIL="does not say a cd before it is refused: $r"; return 1; }
  has "$r" "git commit -F <that file>" || { CASE_DETAIL="no -F route: $r"; return 1; }
  has "$r" "or a path they protect, such as" || { CASE_DETAIL="the protected paths read as a complete list: $r"; return 1; }
  return 0
}

# ── F: the message file of `git commit -F` ──────────────────────────────────
# Review round 1, R-S4-1. S4 tells the agent to commit with `git commit -F
# <file>` in five places, and pre-commit-gate.sh read that file at four sites
# with `s/.*-F[[:space:]]+([^ ]+).*/\1/p`: a QUOTED path (agents quote paths by
# habit) or `--file` was never read, so the PreToolUse message checks saw no
# message — a feat: commit with no Build Loop was allowed there and refused only
# later by the commit-msg hook. The four sites now share _commit_msg_file.
#
# A phase-2 project with no Build Loop: a feat: subject is refused by the
# Build-Loop message check (bl006_check), a fix: subject on a source file with no
# test leaves a row in the TDD warn ledger (_tdd_extract_subject), and an unknown
# BL id is refused by the backlog-references lint (extract_commit_message). The
# fourth site, COMMIT_SUBJECT, feeds --check-commit-ready, which refuses a feat:
# subject only when a source file is staged and bl006_check has not refused it
# first. So F1 stages a document only (the checklist exempts it; bl006_check alone
# decides) and F5 puts the message file in a folder named merge, which makes
# bl006_check stand aside (its derivative-commit filter) and leaves the checklist
# alone deciding. F4 pins all four by structure.
MSG_DIR="$WORK/msg"; SP_DIR="$WORK/sp ace"
mkdir -p "$MSG_DIR" "$SP_DIR"
for k in feat fix docs; do
  case $k in feat) t="feat: add a thing" ;; fix) t="fix: a thing" ;; docs) t="docs: typo (BL-999)" ;; esac
  printf '%s\n\nbody\n' "$t" > "$MSG_DIR/$k.txt"; cp "$MSG_DIR/$k.txt" "$SP_DIR/$k.txt"
done
fx2() {   # DIR — phase 2, initialised, no Build Loop; the lint suite's project
  local d="$1" l=""
  mkdir -p "$d/.claude" "$d/src" "$d/scripts/lib" || return 1
  ( cd "$d" && git init -q && git config user.email t@t.local && git config user.name T \
      && git remote add origin "$d/../not-a-remote.git" ) >/dev/null 2>&1 || return 1
  for l in lint-counter-antipattern lint-backlog-references lint-fix-functions-stderr lint-raw-read-prompt; do
    cp "$REPO_ROOT/scripts/$l.sh" "$d/scripts/" || return 1
  done
  printf '{"frameworkVersion":"4.4.0","host":"other","mode":"personal","deployment":"personal","enforcement_level":"strict"}\n' > "$d/.claude/manifest.json"
  printf '{"current_phase":2,"track":"light","deployment":"personal","poc_mode":null,"phases":{}}\n' > "$d/.claude/phase-state.json"
  printf '%s\n' '{"phase2_init":{"verified":true,"steps_completed":["remote_repo_created","branch_protection_configured","ci_pipeline_configured","project_scaffolded","pre_commit_hooks_installed","data_model_applied","initialization_verified"]},"build_loop":{"feature":null,"step":0,"steps_completed":[]},"uat_session":{},"phase3_validation":{},"phase4_release":{}}' > "$d/.claude/process-state.json"
  printf '## BL-001: seed\n**Status:** Closed — shipped 2026-01-01 (PR #1)\nBody.\n' > "$d/solo-orchestrator-backlog.md"
}
GATE_REASON=""
gate_on() {   # FW DIR CMD [lint] — the PreToolUse decision's reason, or empty for an allow
  local skip=1
  [ "${4:-}" = lint ] && skip=0
  GATE_REASON="$( cd "$2" && jq -nc --arg c "$2" --arg cmd "$3" '{session_id:"s4", hook_event_name:"PreToolUse", cwd:$c, tool_name:"Bash", tool_input:{command:$cmd}}' \
                 | SKIP_LINT=$skip bash "$1/scripts/pre-commit-gate.sh" 2>/dev/null \
                 | jq -r 'select(.hookSpecificOutput.permissionDecision == "deny") | .hookSpecificOutput.permissionDecisionReason' 2>/dev/null )"
}
case_F1() {   # every spelling of the message file reaches the Build-Loop message check
  local d="" form="" cmd="" bad="" n=0
  d="$(newtmp)/p"; fx2 "$d" || { CASE_DETAIL="fixture"; return 1; }
  printf '# tweak\n' > "$d/README.md" && git -C "$d" add README.md
  cp "$MSG_DIR/feat.txt" "$d/msg.txt"
  while IFS= read -r form; do
    [ -n "$form" ] || continue
    cmd="git commit $form"; n=$((n + 1))
    gate_on "$1" "$d" "$cmd"
    has "$GATE_REASON" "no Build Loop active" || bad="$bad [$cmd: allowed]"
  done <<FORMS
-F $MSG_DIR/feat.txt
-F '$MSG_DIR/feat.txt'
-F "$MSG_DIR/feat.txt"
-F "$SP_DIR/feat.txt"
-F '$SP_DIR/feat.txt'
--file $MSG_DIR/feat.txt
--file "$SP_DIR/feat.txt"
--file=$MSG_DIR/feat.txt
--file="$SP_DIR/feat.txt"
-F$MSG_DIR/feat.txt
-sF "$SP_DIR/feat.txt"
-q --file "$MSG_DIR/feat.txt"
-F msg.txt
-F "msg.txt"
-S0xC -F $MSG_DIR/feat.txt
-Sabc -F "$SP_DIR/feat.txt"
-uno -sF $MSG_DIR/feat.txt
-tc -F $MSG_DIR/feat.txt
-F ':(optional)$MSG_DIR/feat.txt'
--file=":(optional)$SP_DIR/feat.txt"
FORMS
  [ "$n" -eq 20 ] || bad="$bad [ran $n forms, want 20]"
  # The value of an option that takes one is not an option: here -m's value is
  # the word -F, and the message file is the --file after it.
  gate_on "$1" "$d" "git commit -m -F --file \"$MSG_DIR/feat.txt\""
  has "$GATE_REASON" "no Build Loop active" || bad="$bad [-m's value was read as -F]"
  # Not a message file: another command's -F before the commit, and an -m
  # message that mentions -F.
  gate_on "$1" "$d" "grep -F \"$MSG_DIR/feat.txt\" README.md; git commit"
  [ -z "$GATE_REASON" ] || bad="$bad [grep's -F was read as the commit's: $GATE_REASON]"
  gate_on "$1" "$d" "git commit -m \"fix: -F $MSG_DIR/feat.txt\""
  [ -z "$GATE_REASON" ] || bad="$bad [an -m message naming -F was read as the file: $GATE_REASON]"
  [ -z "$bad" ] || { CASE_DETAIL="$bad"; return 1; }
  return 0
}
case_F2() {   # the TDD warn detector reads a quoted message file
  local d=""
  d="$(newtmp)/p"; fx2 "$d" || { CASE_DETAIL="fixture"; return 1; }
  printf 'console.log(1)\n' > "$d/src/a.js" && git -C "$d" add src/a.js
  gate_on "$1" "$d" "git commit -F \"$SP_DIR/fix.txt\""
  [ -f "$d/.claude/tdd-warn-ledger.jsonl" ] && [ "$(grep -c . "$d/.claude/tdd-warn-ledger.jsonl")" = 1 ] \
    || { CASE_DETAIL="no TDD warn row for a fix: commit with no test, message from a quoted -F"; return 1; }
  grep -qF '"fix: a thing"' "$d/.claude/tdd-warn-ledger.jsonl" || { CASE_DETAIL="the row does not carry the subject: $(cat "$d/.claude/tdd-warn-ledger.jsonl")"; return 1; }
  return 0
}
case_F3() {   # the backlog-references lint reads a quoted message file
  local d=""
  d="$(newtmp)/p"; fx2 "$d" || { CASE_DETAIL="fixture"; return 1; }
  printf '# tweak\n' > "$d/README.md" && git -C "$d" add README.md
  gate_on "$1" "$d" "git commit -F \"$SP_DIR/docs.txt\"" lint
  has "$GATE_REASON" "lint-backlog-references" && has "$GATE_REASON" "BL-999" \
    || { CASE_DETAIL="an unknown BL id in a quoted -F message was not refused: [$GATE_REASON]"; return 1; }
  return 0
}
case_F5() {   # the checklist's subject reads a quoted message file
  local d="" mf=""
  d="$(newtmp)/p"; fx2 "$d" || { CASE_DETAIL="fixture"; return 1; }
  mf="$(dirname "$d")/merge notes"; mkdir -p "$mf" && cp "$MSG_DIR/feat.txt" "$mf/feat.txt"
  printf 'console.log(1)\n' > "$d/src/a.js" && git -C "$d" add src/a.js
  gate_on "$1" "$d" "git commit -F \"$mf/feat.txt\""
  has "$GATE_REASON" "no Build Loop active" \
    || { CASE_DETAIL="--check-commit-ready did not get the feat: subject from a quoted -F: [$GATE_REASON]"; return 1; }
  return 0
}
case_F4() {   # every site reads the file through the one helper
  local g="$1/scripts/pre-commit-gate.sh" n=""
  n="$(grep -c '"$(_commit_msg_file)"' "$g")"
  [ "$n" = 4 ] || { CASE_DETAIL="$n site(s) call _commit_msg_file, want 4"; return 1; }
  n="$(grep -c 's/\.\*-F\[\[:space:\]\]' "$g")"
  [ "$n" = 0 ] || { CASE_DETAIL="$n site(s) still parse -F with the old sed"; return 1; }
  return 0
}

# ── P: the assessment prompt ────────────────────────────────────────────────
PROMPT_COMMIT="0123456789abcdef0123456789abcdef01234567"
prompt_of() {   # FW — writes the prompt into a fresh folder; prints its path
  local r=""
  r="$(newtmp)"; mkdir -p "$r/.claude"
  jq -n --arg c "$PROMPT_COMMIT" '{adoption: {adoptedAtCommit: $c}}' > "$r/.claude/manifest.json"
  ( set +u
    . "$1/scripts/lib/adopt/adopt-core.sh" || exit 90
    . "$1/scripts/lib/adopt/adopt-act4.sh" || exit 91
    adopt_write_assessment_prompt "$r" ) >/dev/null 2>&1
  printf '%s\n' "$r/.claude/adoption/assessment-prompt.md"
}
case_P1() {   # step 9: the anchor, and where availability and exposure live
  local p="" t=""
  p="$(prompt_of "$1")"; [ -s "$p" ] || { CASE_DETAIL="no prompt written"; return 1; }
  t="$(cat "$p")"
  has "$t" "\"adoptedAtCommit\": \"$PROMPT_COMMIT\"" || { CASE_DETAIL="the shape does not pre-fill the anchor"; return 1; }
  has "$t" '"adoptedAtCommit" is already filled in: it is the commit this project was at just before the' \
    || { CASE_DETAIL="the prompt does not explain the pre-filled adoptedAtCommit"; return 1; }
  has "$t" "adoption commit, which adoption recorded as its anchor, not the adoption commit itself." \
    || { CASE_DETAIL="the prompt does not say it is not the adoption commit"; return 1; }
  has "$t" "Exposure has no intake wizard key: it lives only in" \
    || { CASE_DETAIL="the prompt does not say exposure has no answers key"; return 1; }
  has "$t" "interview.exposure. Availability lives in interview.availability; the wizard's uptime key is the" \
    || { CASE_DETAIL="the prompt does not say where availability lives, or that uptime is the intake's question"; return 1; }
  has "$t" "Availability and exposure have no intake wizard key" && { CASE_DETAIL="the prompt still says availability has no wizard key (uptime asks it)"; return 1; }
  return 0
}
case_P2() {   # step 8: the release history
  local p="" t=""
  p="$(prompt_of "$1")"; [ -s "$p" ] || { CASE_DETAIL="no prompt written"; return 1; }
  t="$(cat "$p")"
  has "$t" "RELEASE_NOTES.md is the framework's blank template: adoption did not carry this project's" \
    || { CASE_DETAIL="step 8 does not say the release history was not carried"; return 1; }
  has "$t" "release history into it. List the releases with git tag (and CHANGELOG.md, if there is one)," \
    || { CASE_DETAIL="step 8 does not say where the release history is"; return 1; }
  return 0
}

# ── D: the docs a technician reads ──────────────────────────────────────────
section7() {   # FW — docs/adoption.md's "### 7. Your first change", to the next ---
  awk '/^### 7\. Your first change/{f=1} f&&/^---$/{exit} f' "$1/docs/adoption.md"
}
case_D1() {
  local s=""
  s="$(section7 "$1")"; [ -n "$s" ] || { CASE_DETAIL="no section 7"; return 1; }
  has "$s" '**The commit is one lone command.** After your approving pick, the agent' || { CASE_DETAIL="no lone-commit paragraph"; return 1; }
  has "$s" 'commits with exactly `git commit -m "subject" -m "body"`: one `-m` per' || { CASE_DETAIL="the rule's command is missing"; return 1; }
  has "$s" 'paragraph, nothing before it (not even `cd … &&`), nothing after it (no' || { CASE_DETAIL="the rule does not say a cd before it is refused"; return 1; }
  has "$s" 'the agent writes the message to a file outside the project with the Write tool and commits with `git commit -F <that file>`' \
    || { CASE_DETAIL="no -F route"; return 1; }
  has "$s" 'also asks you to type a code back at that terminal.' || { CASE_DETAIL="the override's typed code is not described"; return 1; }
  has "$s" 'A terminal driver such as `expect` can, so what stops the agent' || { CASE_DETAIL="§7 does not say a terminal driver can answer the code (review R-S4-3)"; return 1; }
  has "$s" 'so a script cannot answer it' && { CASE_DETAIL="§7 still says a script cannot answer the code"; return 1; }
  has "$s" 'names a path the Guardrails protect, such as' || { CASE_DETAIL="§7's protected paths read as a complete list (review R-S4-4)"; return 1; }
  has "$s" '`Type 418093 and press Enter to approve (anything else cancels):` with a' || { CASE_DETAIL="the override's prompt line is not shown"; return 1; }
  return 0
}
case_D2() {
  local t="" b=""
  t="$(cat "$1/templates/generated/claude-md.tmpl")"
  has "$t" 'a lone `git commit -m "subject" -m "body"` — nothing before it (not even `cd … &&`) and nothing after it' \
    || { CASE_DETAIL="the CLAUDE.md template's commit rule"; return 1; }
  has "$t" 'commit with `git commit -F <that file>`' || { CASE_DETAIL="the CLAUDE.md template has no -F route"; return 1; }
  b="$(cat "$1/docs/builders-guide.md")"
  has "$b" 'nothing before it (not even `cd … &&`)' || { CASE_DETAIL="the Builder's Guide's commit rule"; return 1; }
  has "$b" 'commits with `git commit -F <that file>`' || { CASE_DETAIL="the Builder's Guide has no -F route"; return 1; }
  has "$t" 'or a path they protect, such as' || { CASE_DETAIL="the CLAUDE.md template's protected paths read as a complete list"; return 1; }
  has "$b" 'names a path they protect, such as' || { CASE_DETAIL="the Builder's Guide's protected paths read as a complete list"; return 1; }
  return 0
}
# D3 — review R-S4-2. init.sh and adoption copy docs/user-guide.md into a
# project's docs/reference/ and never copy adoption.md, so a relative link to it
# is dead there; the guide's own convention is the framework's GitHub URL.
case_D3() {
  local u=""
  u="$(cat "$1/docs/user-guide.md")"
  grep -qE '\]\(adoption\.md' <<< "$u" && { CASE_DETAIL="docs/user-guide.md links adoption.md relatively: $(grep -nE '\]\(adoption\.md' <<< "$u" | head -1 | cut -c1-120)"; return 1; }
  has "$u" "(https://github.com/kraulerson/solo-orchestrator/blob/main/docs/adoption.md#7-your-first-change)" \
    || { CASE_DETAIL="the override sentence does not link section 7 by its GitHub URL"; return 1; }
  return 0
}

# ── R, S: real adoptions ────────────────────────────────────────────────────
# The rich adoptee: every surface Scout has a collision row for that an adoption
# can complete on, plus a framework script it already had. Their hooks go in
# after the commit (git never tracks .git/). The answers are
# tests/test-bl322-s2-project-rules.sh's: the tier, the track, four
# confirmations, TL;DR on.
mk_rich() {
  local p="$1"
  mkdir -p "$p/src" "$p/scripts" "$p/.claude/skills/session-handoff" "$p/.claude-backup/old" "$p/.github/workflows" || return 1
  gitq "$p" init -q . && gitq "$p" config user.email s4@test.invalid && gitq "$p" config user.name "S4 Test" \
    && gitq "$p" config core.excludesFile /dev/null || return 1
  printf '{"name":"acme-api","scripts":{"test":"npm test"}}\n' > "$p/package.json"
  printf '# acme-api\n' > "$p/README.md"
  printf 'node_modules/\n' > "$p/.gitignore"
  printf '{"permissions":{"allow":["Bash(ls:*)"]}}\n' > "$p/.claude/settings.json"
  printf '{"permissions":{"allow":["Bash(pwd:*)"]}}\n' > "$p/.claude/settings.local.json"
  printf '{"mcpServers":{}}\n' > "$p/.mcp.json"
  printf -- '---\nname: session-handoff\n---\nTHEIRS-SKILL\n' > "$p/.claude/skills/session-handoff/SKILL.md"
  printf 'their backup\n' > "$p/.claude-backup/old/x.txt"
  printf 'name: ci\non: [push]\njobs:\n  t:\n    runs-on: ubuntu-latest\n    steps:\n      - run: npm test\n' > "$p/.github/workflows/ci.yml"
  printf '# Changelog\n' > "$p/CHANGELOG.md"
  printf '# Our features\n' > "$p/FEATURES.md"
  printf '#!/usr/bin/env bash\n# THEIRS-VALIDATE\n' > "$p/scripts/validate.sh"; chmod +x "$p/scripts/validate.sh"
  gitq "$p" add -A && gitq "$p" commit -q --no-verify -m "chore: their own history" || return 1
  printf '#!/bin/sh\n# THEIRS-PRECOMMIT\nexit 0\n' > "$p/.git/hooks/pre-commit"
  printf '#!/bin/sh\n# THEIRS-COMMITMSG\nexit 0\n' > "$p/.git/hooks/commit-msg"
  printf '#!/bin/sh\n# THEIRS-PREPUSH\nexit 0\n' > "$p/.git/hooks/pre-push"
  chmod +x "$p/.git/hooks/pre-commit" "$p/.git/hooks/commit-msg" "$p/.git/hooks/pre-push"
  ls "$p/.git/hooks/"*.sample >/dev/null 2>&1 || printf '#!/bin/sh\n' > "$p/.git/hooks/pre-rebase.sample"
}
# sums DIR — "<sha> ./path" for every file under DIR, .git/objects aside.
sums() {
  ( cd "$1" && find . -path ./.git/objects -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do
      printf '%s %s\n' "$(git hash-object "$f")" "$f"; done )
}
RUN_RC=0; RUN_OUT=""; RUN_SCAN=""
run_adopt() {   # FW DIR — Scout, then adoption, both from FW
  RUN_RC=0; RUN_OUT="$(dirname "$2")/adopt.out"; RUN_SCAN="$(dirname "$2")/scan"
  bash "$1/scripts/scout.sh" --root "$2" --out "$RUN_SCAN" </dev/null >/dev/null 2>&1
  [ -s "$RUN_SCAN/scout-report.json" ] || { RUN_RC=99; echo "Scout produced no report" > "$RUN_OUT"; return 0; }
  ( cd "$2" && printf '1\nstandard\n1\n1\n1\n1\n2\n' | env SOIF_ADOPT_SCANNER_BIN=sh SOIF_ADOPT_QDRANT=no \
      SOIF_ADOPT_GUARDRAILS_DIR="$WORK/no-guardrails" CLAUDE_CONFIG_DIR="$WORK/no-claude-config" \
      bash "$1/scripts/adopt-project.sh" --scan-report "$RUN_SCAN/scout-report.json" ) \
    > "$RUN_OUT" 2>&1 || RUN_RC=$?
}
adopt_ok() { [ "$RUN_RC" -eq 0 ] || { CASE_DETAIL="adoption rc $RUN_RC: $(grep -E 'BLOCKED|REFUSED|FAIL' "$RUN_OUT" | head -1)"; return 1; }; }

RICH_FW=""; RICH_P=""; RICH_RC=0; RICH_OUT=""; RICH_SCAN=""; RICH_PRISTINE=""
rich() {   # FW — the rich adoptee, adopted once per framework root
  local p=""
  [ "$RICH_FW" = "$1" ] && { RUN_RC="$RICH_RC"; RUN_OUT="$RICH_OUT"; RUN_SCAN="$RICH_SCAN"; return 0; }
  p="$(newtmp)/p"; mk_rich "$p" || return 1
  cp -Rp "$p" "$(dirname "$p")/pristine" || return 1
  sums "$p" > "$(dirname "$p")/before.sums"
  run_adopt "$1" "$p"
  sums "$p" > "$(dirname "$p")/after.sums"
  RICH_FW="$1"; RICH_P="$p"; RICH_RC="$RUN_RC"; RICH_OUT="$RUN_OUT"; RICH_SCAN="$RUN_SCAN"; RICH_PRISTINE="$(dirname "$p")/pristine"
}
# changed PATH — yes when any file at PATH (a file, a folder ending in /, or a
# `*.sample` glob) changed or went away in the rich adoptee; no otherwise.
changed() {
  local d=""
  d="$(dirname "$RICH_P")"
  P="$1" awk 'function hit(f, p) {
                if (p ~ /\/$/) return index(f, "./" p) == 1
                if (p ~ /\*\.sample$/) { sub(/\*\.sample$/, "", p); return index(f, "./" p) == 1 && f ~ /\.sample$/ }
                return f == "./" p }
              NR == FNR { if (hit($2, ENVIRON["P"])) after[$2] = $1; next }
              hit($2, ENVIRON["P"]) { n++; if (!($2 in after) || after[$2] != $1) c = 1 }
              END { print (n == 0 ? "absent" : (c ? "yes" : "no")) }' "$d/after.sums" "$d/before.sums"
}

case_R1() {   # R-S2-6: a replaced framework script is not reported as left alone
  rich "$1" || { CASE_DETAIL="fixture"; return 1; }
  adopt_ok || return 1
  grep -qF "THEIRS-VALIDATE" "$RICH_P/scripts/validate.sh" && { CASE_DETAIL="their validate.sh is still at the path (fixture drift)"; return 1; }
  grep -qF "replaced by the framework's version; your copy of each is in the archive:" "$RUN_OUT" \
    || { CASE_DETAIL="the run does not say it replaced the script"; return 1; }
  grep -qxF "     scripts/validate.sh" "$RUN_OUT" || { CASE_DETAIL="the run does not name scripts/validate.sh"; return 1; }
  grep -qF "yours, kept:" "$RUN_OUT" && { CASE_DETAIL="the run still says: $(grep -F 'yours, kept:' "$RUN_OUT" | head -1)"; return 1; }
  grep -qF "colliding script(s)" "$RUN_OUT" && { CASE_DETAIL="the run still prints the NOT DONE block for colliding scripts"; return 1; }
  grep -qF "were LEFT ALONE, which is" "$RUN_OUT" && { CASE_DETAIL="the run still says the scripts were left alone"; return 1; }
  # Review R-S4-8: no stub is called any more, so no NOT DONE line of any wording.
  grep -qF "NOT DONE" "$RUN_OUT" && { CASE_DETAIL="the run prints: $(grep -F 'NOT DONE' "$RUN_OUT" | head -1)"; return 1; }
  return 0
}

# Scout runs from the root under test, on an untouched copy of the tree; the
# adoption it is held to is this checkout's own, run once. Its mutants mutate
# Scout, so the adoption half need not run again for each.
case_S1() {   # R-S2-7: Scout's bucket per path is adoption's disposition on the same tree
  local t="" j="" md="" man="" path="" bucket="" dispo="" ch="" n=0 seen="" row="" bad=""
  rich "$REPO_ROOT" || { CASE_DETAIL="fixture"; return 1; }
  adopt_ok || return 1
  t="$(newtmp)"; cp -Rp "$RICH_PRISTINE" "$t/p" || { CASE_DETAIL="could not copy the tree"; return 1; }
  bash "$1/scripts/scout.sh" --root "$t/p" --out "$t/scan" </dev/null >/dev/null 2>&1
  j="$t/scan/scout-report.json"; md="$t/scan/scout-report.md"
  man="$(ls "$RICH_P"/.claude/adoption-archive/*/MANIFEST.json 2>/dev/null | head -1)"
  [ -s "$j" ] && [ -s "$md" ] && [ -n "$man" ] || { CASE_DETAIL="no Scout report or no archive MANIFEST"; return 1; }
  while IFS="$TAB" read -r path bucket; do
    [ -n "$path" ] || continue
    [ "$path" = "(uncommitted working tree)" ] && { bad="$bad [the fixture has uncommitted work]"; continue; }
    n=$((n + 1)); seen="$seen $bucket"
    dispo="$(jq -r --arg p "$path" '[.entries[] | select(.originalPath == $p) | .disposition] | first // "none"' "$man")"
    ch="$(changed "$path")"
    [ "$ch" = absent ] && { bad="$bad [$path: Scout has a row, the tree has no such file]"; continue; }
    case "$bucket" in
      archive-and-replace) [ "$dispo" = replaced ] && [ "$ch" = yes ] || bad="$bad [$path: Scout '$bucket', adoption '$dispo', changed $ch]" ;;
      marker-composed)     [ "$dispo" = composed ] && [ "$ch" = yes ] || bad="$bad [$path: Scout '$bucket', adoption '$dispo', changed $ch]" ;;
      keep-theirs)         { [ "$dispo" = none ] || [ "$dispo" = kept ]; } && [ "$ch" = no ] || bad="$bad [$path: Scout '$bucket', adoption '$dispo', changed $ch]" ;;
      audit-only)          [ "$dispo" = none ] && [ "$ch" = no ] || bad="$bad [$path: Scout '$bucket', adoption '$dispo', changed $ch]" ;;
      *)                   bad="$bad [$path: bucket '$bucket']" ;;
    esac
  done <<ROWS
$(jq -r '.collisions.entries[] | [.path, .bucket] | @tsv' "$j")
ROWS
  # Composed means theirs is still there.
  grep -qF 'Bash(ls:*)' "$RICH_P/.claude/settings.json" || bad="$bad [settings.json lost their rule]"
  grep -qF 'THEIRS-COMMITMSG' "$RICH_P/.git/hooks/commit-msg" || bad="$bad [commit-msg lost their hook]"
  # Not vacuous: every bucket is exercised, and the rows this fixture plants are all there.
  for bucket in archive-and-replace marker-composed keep-theirs audit-only; do
    case " $seen " in *" $bucket "*) ;; *) bad="$bad [no row in bucket $bucket]" ;; esac
  done
  [ "$n" -ge 13 ] || bad="$bad [only $n rows, want 13]"
  # Every note describes adoption, not init.sh (review R-S4-6), and the local
  # settings note says what that file holds (review R-S4-5).
  row="$(jq -r '.collisions.entries[] | "\(.path): \(.note)"' "$j" | grep -iE 'scaffolder|OVERWRITTEN|today' | head -1)"
  [ -z "$row" ] || bad="$bad [a note describes init.sh, not adoption: $row]"
  has "$(jq -r '.collisions.entries[] | select(.path == "CHANGELOG.md") | .note' "$j")" "Adoption never writes it" \
    || bad="$bad [the CHANGELOG.md note does not say adoption never writes it]"
  row="$(jq -r '.collisions.entries[] | select(.path == ".claude/settings.local.json") | .note' "$j")"
  has "$row" "It usually holds your personal permissions" || bad="$bad [the settings.local.json note: $row]"
  has "$row" "MCP" && bad="$bad [the settings.local.json note still calls it the MCP roster's home]"
  # The report a person reads says the same.
  row="$(grep -F '| `.mcp.json` |' "$md")"
  has "$row" "| yours stays |" || bad="$bad [the .mcp.json row reads: $row]"
  row="$(grep -F '| `.claude/settings.json` |' "$md")"
  has "$row" "| kept a copy; yours stays, and the framework adds to it |" || bad="$bad [the settings.json row reads: $row]"
  [ -z "$bad" ] || { CASE_DETAIL="$bad"; return 1; }
  return 0
}

case_S2() {   # .claude/phase-state.json: adoption stops, and Scout says so
  local p="" j="" before="" note=""
  p="$(newtmp)/p"; mkdir -p "$p/.claude" "$p/src"
  gitq "$p" init -q . && gitq "$p" config user.email s4@test.invalid && gitq "$p" config user.name "S4 Test" || { CASE_DETAIL="fixture"; return 1; }
  printf '{"name":"acme-api"}\n' > "$p/package.json"
  printf '{"current_phase": 1}\n' > "$p/.claude/phase-state.json"
  gitq "$p" add -A && gitq "$p" commit -q --no-verify -m "chore: theirs" || { CASE_DETAIL="fixture commit"; return 1; }
  before="$(git hash-object "$p/.claude/phase-state.json")"
  run_adopt "$1" "$p"
  j="$RUN_SCAN/scout-report.json"
  [ "$(jq -r '.collisions.entries[] | select(.path == ".claude/phase-state.json") | .bucket' "$j")" = keep-theirs ] \
    || { CASE_DETAIL="Scout's phase-state row is not keep-theirs"; return 1; }
  note="$(jq -r '.collisions.entries[] | select(.path == ".claude/phase-state.json") | .note' "$j")"
  has "$note" "Adoption stops on a project that has this file" || { CASE_DETAIL="the row does not say adoption stops: $note"; return 1; }
  [ "$RUN_RC" -ne 0 ] || { CASE_DETAIL="adoption did not stop"; return 1; }
  grep -qF "this project already looks framework-managed: .claude/phase-state.json is present" "$RUN_OUT" \
    || { CASE_DETAIL="adoption stopped for another reason: $(grep -E 'BLOCKED|REFUSED' "$RUN_OUT" | head -1)"; return 1; }
  [ "$(git hash-object "$p/.claude/phase-state.json")" = "$before" ] || { CASE_DETAIL="the file changed"; return 1; }
  return 0
}

case_S3() {   # the uncommitted-work row says what adoption does with it
  local p="" t="" note=""
  t="$(newtmp)"; p="$t/p"; mkdir -p "$p/src"
  gitq "$p" init -q . && gitq "$p" config user.email s4@test.invalid && gitq "$p" config user.name "S4 Test" || { CASE_DETAIL="fixture"; return 1; }
  printf 'a\n' > "$p/src/a.js" && gitq "$p" add src/a.js && gitq "$p" commit -q --no-verify -m "chore: theirs" || { CASE_DETAIL="fixture commit"; return 1; }
  printf 'b\n' > "$p/src/a.js"
  bash "$1/scripts/scout.sh" --root "$p" --out "$t/scan" </dev/null >/dev/null 2>&1
  note="$(jq -r '.collisions.entries[] | select(.path == "(uncommitted working tree)") | .note' "$t/scan/scout-report.json" 2>/dev/null)"
  [ -n "$note" ] || { CASE_DETAIL="no uncommitted-work row"; return 1; }
  has "$note" "Adoption commits only the files it writes" || { CASE_DETAIL="the row does not say what adoption does: $note"; return 1; }
  grep -qiE 'scaffolder|BYPASSED' <<< "$note" && { CASE_DETAIL="the row describes init.sh: $note"; return 1; }
  return 0
}

check() {   # LABEL CASE
  CASE_DETAIL=""
  if "$2" "$REPO_ROOT"; then pass "$1"; else fail_ "$1" "${CASE_DETAIL:-failed}"; fi
}

echo "=== G — the session start's MCP line ==="
check "G1: the session start names what satisfies the check: a qdrant-find that returned, Context7's query-docs" case_G1
check "G2: a server that is not configured is not listed" case_G2
echo "=== O, H — the approval guidance ==="
check "O1: --offer states the lone-commit rule and the git commit -F route" case_O1
check "H1: the commit check's hold message states the same" case_H1
echo "=== F — the message file of git commit -F (review R-S4-1) ==="
check "F1: every spelling of -F/--file, quoted or not, reaches the Build-Loop message check" case_F1
check "F2: the TDD warn detector reads a quoted message file" case_F2
check "F3: the backlog-references lint reads a quoted message file" case_F3
check "F4: all four sites read the file through _commit_msg_file" case_F4
check "F5: the checklist's subject (COMMIT_SUBJECT) reads a quoted message file" case_F5
echo "=== P — the assessment prompt ==="
check "P1: it explains the pre-filled adoptedAtCommit and where availability and exposure live" case_P1
check "P2: it says the release history was not carried into RELEASE_NOTES.md" case_P2
echo "=== D — the docs ==="
check "D1: docs/adoption.md §7 has the lone-commit rule, the -F route and the override's typed code" case_D1
check "D2: the CLAUDE.md template and the Builder's Guide have the lone-commit rule and the -F route" case_D2
check "D3: the User Guide, copied into projects without adoption.md, links section 7 by its GitHub URL" case_D3
echo "=== R, S — real adoptions ==="
check "R1: a replaced framework script is not reported as left alone (R-S2-6)" case_R1
check "S1: Scout's bucket for every path is what adoption does to it on the same tree (R-S2-7)" case_S1
check "S2: .claude/phase-state.json — Scout says it stays and adoption stops; adoption stops, the file unchanged" case_S2
check "S3: the uncommitted-work row says adoption commits only what it writes" case_S3

# ── M: mutants ───────────────────────────────────────────────────────────────
mk_mirror() {   # SRC DST — scripts, templates, init.sh and the three guides the D cases read
  mkdir -p "$2/docs" && cp -Rp "$1/scripts" "$1/templates" "$1/init.sh" "$2/" \
    && cp -p "$1/docs/adoption.md" "$1/docs/builders-guide.md" "$1/docs/user-guide.md" "$2/docs/"
}
ends_in() {   # FILE MARKER — how many lines of FILE end in MARKER
  MARK="$2" awk 'BEGIN{c=0; m=ENVIRON["MARK"]} length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m {c++} END{print c}' "$1"
}
mutate() {   # FILE MARKER REPLACEMENT — exactly one line ends in MARKER; it now reads REPLACEMENT; still parses
  local f="$1" mark="$2" repl="$3"
  [ -f "$f" ] || { echo "no such file: $f"; return 1; }
  [ "$(ends_in "$f" "$mark")" = 1 ] || { echo "marker '$mark' ends $(ends_in "$f" "$mark") line(s) of $f (need 1)"; return 1; }
  MARK="$mark" REPL="$repl" awk '{ m=ENVIRON["MARK"]
      if (length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m) print ENVIRON["REPL"]; else print }' \
    "$f" > "$f.mut" && cat "$f.mut" > "$f" && rm -f "$f.mut"
  [ "$(ends_in "$f" "$mark")" = 0 ] || { echo "a line still ends in the marker after the edit"; return 1; }
  [ "$(grep -cxF -- "$repl" "$f")" -ge 1 ] || { echo "replacement did not land"; return 1; }
  case "$f" in *.sh) bash -n "$f" 2>/dev/null || { echo "mutant does not parse"; return 1; } ;; esac
  return 0
}
drop_line() {   # FILE LINE — exactly one line equals LINE; it is deleted
  local f="$1" line="$2"
  [ "$(grep -cxF -- "$line" "$f")" = 1 ] || { echo "'$line' is not exactly one line of $f"; return 1; }
  LINE="$line" awk '$0 != ENVIRON["LINE"]' "$f" > "$f.mut" && cat "$f.mut" > "$f" && rm -f "$f.mut"
  [ "$(grep -cxF -- "$line" "$f")" = 0 ] || { echo "the line is still there"; return 1; }
  case "$f" in *.sh) bash -n "$f" 2>/dev/null || { echo "mutant does not parse"; return 1; } ;; esac
  return 0
}
run_mutant() {   # ID WHAT KILLER MIRROR
  local rc=0
  CASE_DETAIL=""
  "$3" "$4" || rc=$?
  if [ "$rc" -eq 0 ]; then fail_ "$1" "$2 — SURVIVED: ${3#case_} still passes against the mutant"
  else pass "$1 (MUTATION) — $2: killed by ${3#case_} (${CASE_DETAIL:-failed})"; fi
}
mutant() {   # ID FILE MARKER REPLACEMENT KILLER WHAT
  local m="" why=""
  m="$(newtmp)/mirror"
  mk_mirror "$REPO_ROOT" "$m" || { fail_ "$1" "could not build a mirror"; return; }
  why="$(mutate "$m/$2" "$3" "$4")" || { fail_ "$1" "mutant did not land: $why"; return; }
  run_mutant "$1" "$6" "$5" "$m"
}
cut_text() {   # FILE OLD NEW — exactly one line holds OLD; its first OLD becomes NEW
  local f="$1" old="$2" new="$3" n="" d=""
  n="$(grep -cF -- "$old" "$f")"
  [ "$n" = 1 ] || { echo "'$old' is on $n line(s) of $f (need 1)"; return 1; }
  cp "$f" "$f.orig" || return 1
  OLD="$old" NEW="$new" awk '{ if (!done && (i = index($0, ENVIRON["OLD"]))) { $0 = substr($0, 1, i - 1) ENVIRON["NEW"] substr($0, i + length(ENVIRON["OLD"])); done = 1 } print }' "$f.orig" > "$f"
  d="$(diff "$f.orig" "$f" | grep -c '^>')"
  rm -f "$f.orig"
  [ "$d" = 1 ] || { echo "changed $d line(s), want 1"; return 1; }
  [ "$(grep -cF -- "$old" "$f")" = 0 ] || { echo "the text is still there"; return 1; }
  case "$f" in *.sh) bash -n "$f" 2>/dev/null || { echo "mutant does not parse"; return 1; } ;; esac
  return 0
}
mutant_cut() {   # ID FILE OLD NEW KILLER WHAT
  local m="" why=""
  m="$(newtmp)/mirror"
  mk_mirror "$REPO_ROOT" "$m" || { fail_ "$1" "could not build a mirror"; return; }
  why="$(cut_text "$m/$2" "$3" "$4")" || { fail_ "$1" "mutant did not land: $why"; return; }
  run_mutant "$1" "$6" "$5" "$m"
}
mutant_insert_after() {   # ID FILE MARKER LINE KILLER WHAT — LINE goes in after the one line ending in MARKER
  local m="" f=""
  m="$(newtmp)/mirror"
  mk_mirror "$REPO_ROOT" "$m" || { fail_ "$1" "could not build a mirror"; return; }
  f="$m/$2"
  [ "$(ends_in "$f" "$3")" = 1 ] || { fail_ "$1" "the anchor line is not exactly one line"; return; }
  MARK="$3" ADD="$4" awk '{ print; m=ENVIRON["MARK"]
      if (length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m) print ENVIRON["ADD"] }' "$f" > "$f.mut" && cat "$f.mut" > "$f" && rm -f "$f.mut"
  [ "$(grep -cxF -- "$4" "$f")" = 1 ] && bash -n "$f" || { fail_ "$1" "mutant did not land"; return; }
  run_mutant "$1" "$6" "$5" "$m"
}
mutant_drop() {   # ID FILE LINE KILLER WHAT
  local m="" why=""
  m="$(newtmp)/mirror"
  mk_mirror "$REPO_ROOT" "$m" || { fail_ "$1" "could not build a mirror"; return; }
  why="$(drop_line "$m/$2" "$3")" || { fail_ "$1" "mutant did not land: $why"; return; }
  run_mutant "$1" "$5" "$4" "$m"
}

# R-S2-6's mutant is the stale stub coming back, exactly as it was at 7d12ba5:
# the function appended to adopt-stubs.sh and its call after the marked line.
STALE_STUB="$(cat <<'STUB'
adopt_stub_framework_script_collisions() {
  local n="${1:-0}" list="${2:-}" p
  [ "$n" -gt 0 ] || return 0
  adopt_stub_notice "installing the framework's version of $n colliding script(s)" \
    "unassigned — §10 gives this class to no work package" \
    "$n of your files sit where a framework SCRIPT would go. They were LEFT ALONE, which is"
  adopt_note "the safe direction, and it has a cost: the framework's version of each of those"
  adopt_note "files is NOT installed, so anything that depends on it is inert. The collision"
  adopt_note "ARCHIVE (WP6) covers your AI-layer settings and your git hooks; these are neither,"
  adopt_note "and replacing a script your own build may call is a decision nobody has made yet."
  if [ -n "$list" ]; then
    printf '%s\n' "$list" | head -20 | while IFS= read -r p; do
      [ -n "$p" ] && adopt_note "  yours, kept: $p"
    done
    [ "$n" -gt 20 ] && adopt_note "  ...and $((n - 20)) more."
  fi
  return 0
}
STUB
)"
mutant_stub_back() {   # ID KILLER WHAT
  local m="" st="" stubs=""
  m="$(newtmp)/mirror"
  mk_mirror "$REPO_ROOT" "$m" || { fail_ "$1" "could not build a mirror"; return; }
  st="$m/scripts/lib/adopt/adopt-state.sh"; stubs="$m/scripts/lib/adopt/adopt-stubs.sh"
  [ "$(ends_in "$st" '# BL-242-ORCH-SOURCE')" = 1 ] || { fail_ "$1" "the anchor line is not exactly one line"; return; }
  printf '\n%s\n' "$STALE_STUB" >> "$stubs"
  MARK='# BL-242-ORCH-SOURCE' awk '{ print; m=ENVIRON["MARK"]
      if (length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m) print "  adopt_stub_framework_script_collisions \"$n_collided\" \"$ADOPT_COLLISION_LIST\"" }' \
    "$st" > "$st.mut" && cat "$st.mut" > "$st" && rm -f "$st.mut"
  grep -qF 'adopt_stub_framework_script_collisions "$n_collided"' "$st" && bash -n "$st" && bash -n "$stubs" \
    || { fail_ "$1" "mutant did not land"; return; }
  run_mutant "$1" "$3" "$2" "$m"
}

echo "=== M — mutants ==="
GATE=scripts/session-test-gate-check.sh
mutant M1 "$GATE" '# BL-322-S4-GATE-C7' '    :' case_G1 "the Context7 line is not printed"
mutant M2 "$GATE" '# BL-322-S4-GATE-QDRANT' '    :' case_G1 "the qdrant line is not printed"
mutant M3 "$GATE" '# BL-322-S4-GATE-C7-IF' '  if true; then' case_G2 "the Context7 line is printed when Context7 is not configured"
mutant M4 "$GATE" '# BL-322-S4-GATE-QDRANT-IF' '  if true; then' case_G2 "the qdrant line is printed when Qdrant is not configured"
PA=scripts/pending-approval.sh
mutant M5 "$PA" '# BL-322-S4-OFFER-COMMIT' '    :' case_O1 "--offer does not state the lone-commit rule"
mutant M6 "$PA" '# BL-322-S4-OFFER-FILE' '    :' case_O1 "--offer does not give the -F route"
mutant M6b "$PA" '# BL-322-S4-OFFER-IF' '    if true; then' case_O1 "--offer gives the commit rule for a question that approves nothing"
mutant M7 scripts/pre-commit-gate.sh '# BL-322-S4-GATE-HINT' \
  '    hint="Stop and wait. The user answers by replying with the option id (for example: $recommendation), then again once the Development Guardrails have shown them the question and the staged change; the Guardrails then record the pick and remove this question. Do not remove it yourself. After a pick that approves the commit, commit with a lone git commit -m \"subject\" -m \"body\" (no -a, no paths, nothing else on the line). To withdraw the question instead: scripts/pending-approval.sh --clear"' \
  case_H1 "the hold message is the one before S4"
PCG=scripts/pre-commit-gate.sh
OLD_F_SED='f=$(echo "$COMMAND" | sed -nE '"'"'s/.*-F[[:space:]]+([^ ]+).*/\1/p'"'"' | head -n 1)'
mutant MF1 "$PCG" '# BL-322-S4-MSGFILE-QUOTE' '        if (0) { q = c; have = 1; continue }' case_F1 "a quote opens nothing, so a quoted path keeps its quotes"
mutant MF2 "$PCG" '# BL-322-S4-MSGFILE-LONG' '        if (w == "-F") { if (k < n) print t[k + 1]; exit }' case_F1 "--file <path> is not read"
mutant MF3 "$PCG" '# BL-322-S4-MSGFILE-LONGEQ' '        if (0) { print substr(w, 8); exit }' case_F1 "--file=<path> is not read"
mutant MF4 "$PCG" '# BL-322-S4-MSGFILE-CLUSTER' '            if (0) { r = substr(w, j + 1); if (r != "") print r; else if (k < n) print t[k + 1]; exit }' case_F1 "-F<path> and -sF <path> are not read"
mutant MF5 "$PCG" '# BL-322-S4-MSGFILE-COMMIT' '      k = 0' case_F1 "an -F before git commit (another command's) is read as the message file"
mutant MF6 "$PCG" '# BL-322-S4-MSGFILE-SKIPVAL' '          k = k' case_F1 "an -m value that says -F is read as the file"
mutant MF7 "$PCG" '# BL-322-S4-MSGFILE-TDD' "    $OLD_F_SED" case_F2 "the TDD warn detector parses -F with the old sed"
mutant MF8 "$PCG" '# BL-322-S4-MSGFILE-BL006' "    $OLD_F_SED" case_F1 "the Build-Loop message check parses -F with the old sed"
mutant MF9 "$PCG" '# BL-322-S4-MSGFILE-LINT' "    $OLD_F_SED" case_F3 "the backlog-references lint parses -F with the old sed"
mutant MF10 "$PCG" '# BL-322-S4-MSGFILE-SUBJECT' "    F${OLD_F_SED#f}" case_F5 "COMMIT_SUBJECT parses -F with the old sed"
# `## BL-322:` S5, review R2-1: an attached value ends the cluster.
mutant MF11 "$PCG" '# BL-322-S5-MSGFILE-OPTVAL' '            if (0) break' case_F1 "the c or C of an attached -S key id is read as -c, which takes the -F as its value"
mutant MF12 "$PCG" '# BL-322-S5-MSGFILE-REQVAL' '            if (l == "m" || l == "c" || l == "C") {' case_F1 "-t's attached value is read as more options"
mutant MF13 "$PCG" '# BL-322-S5-MSGFILE-OPTIONAL' '    function fp(p) { return p }' case_F1 "a :(optional) prefix is read as part of the path (review R-S5-5)"
ACT=scripts/lib/adopt/adopt-act4.sh
mutant_drop M8 "$ACT" '   "adoptedAtCommit" is already filled in: it is the commit this project was at just before the' case_P1 "the prompt stops explaining adoptedAtCommit"
mutant_drop M9 "$ACT" "   interview.exposure. Availability lives in interview.availability; the wizard's uptime key is the" case_P1 "the prompt stops saying where availability lives"
mutant_drop M10 "$ACT" "   RELEASE_NOTES.md is the framework's blank template: adoption did not carry this project's" case_P2 "the prompt stops saying the release history was not carried"
mutant_cut M11 docs/adoption.md 'also asks you to type a code back at that terminal.' 'also asks you.' case_D1 "§7 stops describing the override's typed code"
mutant_cut M12 docs/adoption.md 'Write tool and commits with `git commit -F <that file>`' 'Write tool and commits' case_D1 "§7 stops giving the -F route"
mutant_cut M13 docs/adoption.md 'nothing before it (not even `cd … &&`), nothing after it' 'nothing after it' case_D1 "§7 stops saying a cd before the commit is refused"
mutant_stub_back M14 case_R1 "the stale NOT DONE block for a replaced script comes back"
mutant_insert_after M14b scripts/lib/adopt/adopt-state.sh '# BL-242-ORCH-SOURCE' '  adopt_note "NOT DONE: your $n_collided file(s) were kept as they were."' case_R1 "a reworded NOT DONE note for the collisions comes back (review R-S4-8, the reviewer's A2)"
SCO=scripts/lib/scout/scout-collisions.sh
mutant M15 "$SCO" '# BL-322-S4-SCOUT-SETTINGS' '  bucket="archive-and-replace"' case_S1 "Scout says settings.json is replaced"
mutant M16 "$SCO" '# BL-322-S4-SCOUT-LOCAL' '  bucket="archive-and-replace"' case_S1 "Scout says settings.local.json is replaced"
mutant M17 "$SCO" '# BL-322-S4-SCOUT-MCP' '  bucket="archive-and-replace"' case_S1 "Scout says .mcp.json is replaced"
mutant M18 "$SCO" '# BL-322-S4-SCOUT-HOOK-OTHER' '      bucket="archive-and-replace"' case_S1 "Scout says a hook other than pre-commit and commit-msg is replaced"
mutant M19 "$SCO" '# BL-322-S4-SCOUT-SAMPLE' '      bucket="archive-and-replace"' case_S1 "Scout says the sample hooks are replaced"
mutant M20 "$SCO" '# BL-322-S4-SCOUT-BACKUP' '  bucket="archive-and-replace"' case_S1 "Scout says .claude-backup/ is replaced"
mutant M21 "$SCO" '# BL-322-S4-SCOUT-GITIGNORE' '  bucket="marker-composed"' case_S1 "Scout says the framework adds to .gitignore"
mutant M22 "$SCO" '# BL-322-S4-SCOUT-PHASESTATE' '  bucket="archive-and-replace"' case_S2 "Scout says .claude/phase-state.json is replaced"
mutant M23 scripts/lib/scout/scout-report.sh '# BL-322-S4-SCOUT-COMPOSED-PHRASE' "    marker-composed)     printf 'left alone; the framework adds to it' ;;" case_S1 "the report says a composed file is left alone"
mutant_cut M24 templates/generated/claude-md.tmpl 'commit with `git commit -F <that file>`' 'commit' case_D2 "the CLAUDE.md template stops giving the -F route"
mutant_cut M25 templates/generated/claude-md.tmpl '(not even `cd … &&`) and nothing after it' 'and nothing after it' case_D2 "the CLAUDE.md template stops saying a cd before the commit is refused"
mutant_cut M26 docs/builders-guide.md 'commits with `git commit -F <that file>`' 'commits' case_D2 "the Builder's Guide stops giving the -F route"
mutant_cut M27 docs/adoption.md 'A terminal driver such as `expect` can, so what stops the agent' 'So what stops the agent' case_D1 "§7 stops saying a terminal driver can answer the override's code"
mutant_cut M28 docs/adoption.md 'names a path the Guardrails protect, such as' 'names one of their protected paths' case_D1 "§7's protected paths read as a complete list again"
mutant_cut M29 templates/generated/claude-md.tmpl 'or a path they protect, such as' 'or a protected path' case_D2 "the template's protected paths read as a complete list again"
mutant_cut M30 docs/builders-guide.md 'names a path they protect, such as' 'names one of their protected paths' case_D2 "the Builder's Guide's protected paths read as a complete list again"
mutant_cut M31 docs/user-guide.md '(https://github.com/kraulerson/solo-orchestrator/blob/main/docs/adoption.md#7-your-first-change)' '(adoption.md#7-your-first-change)' case_D3 "the User Guide links adoption.md relatively again"
mutant_cut M32 scripts/pending-approval.sh 'or a path they protect, such as' 'or a protected path' case_O1 "--offer's protected paths read as a complete list again"
mutant M33 "$SCO" '# BL-322-S4-SCOUT-CHANGELOG' '    "OVERWRITTEN from a template today. Under adoption it is treated as theirs: kept, and reconciled by the interview." ""' case_S1 "the CHANGELOG.md note describes init.sh again (review R-S4-6)"
mutant M34 "$SCO" '# BL-322-S4-SCOUT-LOCAL-NOTE' '    "Adoption copies it into its archive and leaves yours as it is. It is the usual home for a developer'"'"'s personal MCP roster, and it is usually untracked." ""' case_S1 "the settings.local.json note calls it the MCP roster's home again (review R-S4-5)"
mutant M35 "$SCO" '# BL-322-S4-SCOUT-UNCOMMITTED' '        "$n path(s) are uncommitted. The scaffolder sweeps existing uncommitted work into a '"'"'chore: initialize'"'"' commit WITH VERIFICATION BYPASSED. Commit or stash it yourself first — Scout will not touch it." ""' case_S3 "the uncommitted-work row describes init.sh again"
mutant M36 "$GATE" '# BL-322-S4-GATE-HEAD' '  echo "MCP GATE ACTIVE: Write/Edit operations are blocked until each call below has returned successfully in this session:"' case_G1 "the session start calls the MCP check a gate again"

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
