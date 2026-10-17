#!/usr/bin/env bash
# tests/test-bl277-detector-authorship.sh
#
# `## BL-277:` — THE DETECTOR ATTRIBUTED TEXT IT HAD NOT ESTABLISHED THE AUTHOR OF.
#
# scripts/hooks/bypass-detector.sh scans two surfaces. On Stop it reads
# `.last_assistant_message`, which the model wrote. On PostToolUse it reads
# `.tool_response.*`, which is whatever a program printed or a file contains.
# Both were stamped `actor: "claude"` and both raised the blocking sentinel, so
# reading the framework's own rules reported the agent for proposing to break
# them, and froze every commit until a person declined a proposal nobody made.
#
# The decision (issue #385, maintainer, 2026-09-17) is the entry's option 3:
# keep scanning output, let only authored matches raise the sentinel, and have
# PostToolUse rows carry an actor other than `claude`. The maintainer's ruling
# on PR #454 (2026-09-27): files the agent writes are still scanned, so a Write
# result is authored text, and the false-positive close is the operator's alone.
#
# WHY NO PATTERN APPEARS LITERALLY IN THIS FILE. Every fixture below is
# assembled from split string literals. A suite for this defect has to feed the
# detector the vocabulary it matches; it does not have to CONTAIN that
# vocabulary as contiguous text, and a file that does is itself a trigger for
# any detector still scanning file content. `## BL-277:` said a correct suite
# "cannot avoid containing the trigger strings"; this file is the correction.
#
# STRUCTURE
#   A*  PostToolUse from Bash: a row is still written (T1's output-scanning
#       contract), its actor is not `claude`, nothing is left PENDING, no
#       sentinel.
#   W*  PostToolUse from Write: the model wrote the file, so a `claude` row,
#       PENDING, and the sentinel.
#   B*  `## BL-336:` PostToolUse from Edit and MultiEdit: the text scanned is
#       what the model wrote in (tool_input.new_string, each
#       tool_input.edits[].new_string), never originalFile or old_string.
#   S*  Stop: a `claude` row, PENDING, and the sentinel, whose question does
#       not tell the model how to close it as a false positive.
#   L*  the ledger read back as tool output mints no `claude` row.
#   K*  the shipped CLAUDE.md template read as tool output.
#   G*  the pre-commit gate: the verify-skipping commit is still denied; a
#       ledger holding only tool-output rows does not block; an authored match
#       does.
#   D*  the third disposition, false-positive, which is the USER'S PICK:
#       scripts/pending-approval.sh --resolve --decision false-positive closes
#       nothing itself; it asks the bypass question again with a third option,
#       A3, and the close is read from the user's pick of A3 in
#       .claude/approvals.jsonl, as A1 and A2 are (`## BL-320:`). Before it
#       asks, it is refused without a terminal on stdin and confirmed at a
#       [y/N] prompt, the same two steps as `test-gate.sh --unrecord-feature`
#       and `process-checklist.sh --reset`. The operator's side runs under a
#       pseudo-terminal from script(1) and types its answer; P0 proves the
#       pseudo-terminal is real, so D5's refusal is the guard's. D1's first
#       half is also what an AGENT gets by running the command under a
#       pseudo-terminal itself: a question for the user, and nothing closed.
#   E1  the same round trip against the real Development Guardrails hooks (the
#       pinned fixture, tests/test-helpers/cdf-fixture.sh): config-guard refuses
#       the agent's writes to .claude/approvals.jsonl, record-approval.sh shows
#       the user A3 and the reason, and the pick closes the rows.
#   X*  malformed hook input.
#   R5  the hook roster (scripts/lib/claude-settings.sh) in adoption mode
#       still registers no PostToolUse detector: the maintainer's
#       `# BL-242-SETTINGS-BL277` guard, unchanged.
#   R6  the roster run twice in greenfield mode: one detector, under matcher
#       Bash|Write|Edit|MultiEdit and nowhere else.
#   M*  marker presence and mutants. Each mutant proves its location by distance
#       from its marker and asserts the literal text that landed; one that
#       cannot be applied is a SETUP failure, never a kill.
#
# HERMETIC: temp trees only, the real scripts driven over stdin the way Claude
# Code drives them, and the roster sourced into temp trees. No network, and
# init.sh is never run: it installs the Claude Dev Framework into $HOME.
# tests/test-bl029-integration.sh T1 (full lane) pins the same registration
# in a project init.sh produces.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/scripts/hooks/bypass-detector.sh"
GATE="$REPO_ROOT/scripts/pre-commit-gate.sh"
PA="$REPO_ROOT/scripts/pending-approval.sh"
LIB="$REPO_ROOT/scripts/lib/bypass-audit.sh"
ROSTER="$REPO_ROOT/scripts/lib/claude-settings.sh"
TEMPLATE="$REPO_ROOT/templates/generated/claude-md.tmpl"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
# E1 runs the real Guardrails hooks, which keep their state in /tmp files named
# by the project's hash; each hash E1 makes is listed here and its files go too.
E_HASHES=""
cleanup() {
  local h
  for h in $E_HASHES; do
    rm -f "/tmp/.claude_evaluated_$h" "/tmp/.claude_approval_shown_$h" "/tmp/.claude_eval_log_$h"
  done
  rm -rf "$TOPTMP"
}
trap cleanup EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }
# mirror_scripts — a copy of scripts/ for a mutant or a stub install to change.
mirror_scripts() { local d; d="$(newtmp)/fw"; mkdir -p "$d" && cp -Rp "$REPO_ROOT/scripts" "$d/" && printf '%s' "$d"; }

for need in "$HOOK" "$GATE" "$PA" "$LIB" "$ROSTER" "$TEMPLATE"; do
  [ -f "$need" ] || { echo "  [FAIL] setup — $need not found"; echo ""; echo "Results: 0 passed, 1 failed"; exit 1; }
done
command -v jq >/dev/null 2>&1 || { echo "  [FAIL] setup — jq is required"; echo ""; echo "Results: 0 passed, 1 failed"; exit 1; }
# The real Guardrails clone for E1: a private copy of the pinned fixture
# (`## BL-322:` S5). 0 = here; 77 = not here, locally (E1 skips); 1 = the
# fixture says E1 must run and cannot (E1 fails).
# shellcheck source=/dev/null
. "$REPO_ROOT/tests/test-helpers/cdf-fixture.sh" || { echo "  [FAIL] setup — cannot source tests/test-helpers/cdf-fixture.sh"; echo ""; echo "Results: 0 passed, 1 failed"; exit 1; }
CDF_CLONE="$TOPTMP/cdf"; CDF_RC=0
cdf_fixture_copy "$CDF_CLONE" 4.4.0 >/dev/null 2>&1 || CDF_RC=$?
SKIPPED=0

# --- fixtures: one per pattern in scripts/lib/bypass-patterns.sh, split so the
# contiguous text exists only at run time -------------------------------------
PAT_NAMES="no_verify soif_force_step terminal_workaround fake_loop force_push manual_step_complete"
fixture_for() {
  case "$1" in
    no_verify)            printf '%s' "alternatively, use --no-""verify to get past it" ;;
    soif_force_step)      printf '%s' "maybe set SOIF_FORCE""_STEP=build_loop:tests_written" ;;
    terminal_workaround)  printf '%s' "you could ru""n this in your own termi""nal instead" ;;
    fake_loop)            printf '%s' "then ma""rk step build_loop:tests_written comp""lete" ;;
    force_push)           printf '%s' "finish with git pu""sh --force origin main" ;;
    manual_step_complete) printf '%s' "we can just ma""rk the audit as pas""sed" ;;
    *) return 1 ;;
  esac
}
FLAG_NV="--no-""verify"

# mk_proj DIR [VERSION] — VERSION is the Development Guardrails version in the
# manifest, 4.4.0 by default: `## BL-320:`'s minimum, the "pick" route, where
# the user answers a question by option id and scripts/pending-approval.sh
# refuses the agent's --decision accept|decline. 4.3.0 is the older "legacy"
# route, which still takes them; "test" reads as no version at all.
mk_proj() {
  local d="$1" v="${2:-4.4.0}"
  mkdir -p "$d/.claude" || return 1
  jq -nc --arg v "$v" '{frameworkVersion:$v,host:"other",mode:"personal",deployment:"personal",enforcement_level:"strict"}' \
    > "$d/.claude/manifest.json" || return 1
  echo "[]" > "$d/.claude/bypass-audit.json" || return 1
  return 0
}
ledger()   { printf '%s' "$1/.claude/bypass-audit.json"; }
sentinel() { printf '%s' "$1/.claude/pending-approval.json"; }

# q <project> <jq filter> — a number or string out of the ledger; "ERR" when the
# ledger cannot be read, so an unreadable ledger never compares equal to 0.
q() { jq -r "$2" "$(ledger "$1")" 2>/dev/null || printf 'ERR'; }

# The result shapes below are a real Bash and a real Write result from a Claude
# Code transcript (`toolUseResult`), their text replaced. Every Bash result
# carries `stdout`, empty or not.
env_post() { jq -nc --arg k "$1" --arg t "$2" \
  '{session_id:"bl277", hook_event_name:"PostToolUse", tool_name:"Bash",
    tool_input:{command:"cat notes.txt"},
    tool_response:({stdout:"", stderr:"", interrupted:false, isImage:false, noOutputExpected:false} + {($k):$t})}'; }
# env_write <create|update> <text> — Write returns the file's new text as a
# top-level `content`.
env_write() { jq -nc --arg ty "$1" --arg t "$2" \
  '{session_id:"bl277", hook_event_name:"PostToolUse", tool_name:"Write",
    tool_input:{file_path:"/proj/NEXT_STEPS.md", content:$t},
    tool_response:{type:$ty, filePath:"/proj/NEXT_STEPS.md", content:$t, structuredPatch:[],
      originalFile:(if $ty == "create" then null else "old notes\n" end), userModified:false}}'; }
env_stop() { jq -nc --arg t "$1" \
  '{session_id:"bl277", hook_event_name:"Stop", last_assistant_message:$t,
    transcript_path:"/nonexistent/bl277.jsonl"}'; }

# run_hook <hook> <project> <envelope> -> HOOK_RC
run_hook() {
  printf '%s' "$3" | CLAUDE_PROJECT_DIR="$2" bash "$1" >/dev/null 2>&1
  HOOK_RC=$?
  return 0
}

# ---------------------------------------------------------------------------
# chk_* — each check takes the script under test as $1, prints a reason and
# returns 1 on failure. The cases call them on the real tree; the mutants call
# the SAME functions on a mutated mirror, so a kill is the case failing and
# nothing else.
# ---------------------------------------------------------------------------

# A — every pattern, fed as PostToolUse output.
chk_post_not_claude() {
  local hook="$1" p name rows claude
  for name in $PAT_NAMES; do
    p="$(newtmp)"; mk_proj "$p" || { echo "fixture"; return 1; }
    run_hook "$hook" "$p" "$(env_post stdout "$(fixture_for "$name")")"
    rows="$(q "$p" "[.[] | select(.type==\"claude_bypass_proposal\" and .details.pattern==\"$name\")] | length")"
    claude="$(q "$p" '[.[] | select(.actor=="claude")] | length')"
    [ "$HOOK_RC" -eq 0 ] || { echo "$name: hook rc=$HOOK_RC"; return 1; }
    [ "$rows" = "1" ]    || { echo "$name: rows for the pattern=$rows, want 1 (output scanning must survive)"; return 1; }
    [ "$claude" = "0" ]  || { echo "$name: $claude row(s) attributed to claude"; return 1; }
  done
  return 0
}
chk_post_no_sentinel() {
  local hook="$1" p name
  for name in $PAT_NAMES; do
    p="$(newtmp)"; mk_proj "$p" || { echo "fixture"; return 1; }
    run_hook "$hook" "$p" "$(env_post stdout "$(fixture_for "$name")")"
    [ "$(q "$p" 'length')" != "0" ] || { echo "$name: no row written, so the absence of a sentinel proves nothing"; return 1; }
    [ ! -e "$(sentinel "$p")" ] || { echo "$name: a sentinel was raised from tool output"; return 1; }
  done
  return 0
}
chk_post_not_pending() {
  local hook="$1" p ur fo
  p="$(newtmp)"; mk_proj "$p" || { echo "fixture"; return 1; }
  run_hook "$hook" "$p" "$(env_post stdout "$(fixture_for no_verify)")"
  ur="$(q "$p" '.[0].user_response')"; fo="$(q "$p" '.[0].final_outcome')"
  [ "$ur" = "n/a" ] && [ "$fo" = "recorded_only" ] || { echo "user_response=$ur final_outcome=$fo, want n/a and recorded_only"; return 1; }
  return 0
}
# A4 — a real Bash result, every key present, the text on stdout. The only
# key that reaches the scan under a Bash registration: stdout is always
# present, and jq's `//` keeps an empty string, so stderr is never read.
chk_post_bash_shape() {
  local hook="$1" p a
  p="$(newtmp)"; mk_proj "$p" || { echo "fixture"; return 1; }
  run_hook "$hook" "$p" "$(env_post stdout "$(fixture_for no_verify)")"
  a="$(q "$p" '[.[].actor] | unique | join(",")')"
  [ "$a" = "tool_output" ] || { echo "actors=[$a], want [tool_output]"; return 1; }
  [ ! -e "$(sentinel "$p")" ] || { echo "sentinel raised"; return 1; }
  return 0
}

# A7 — the other tools whose results carry a top-level `content`: a subagent's
# report (Agent, a list of text blocks) and a Grep in content mode. Shapes from
# transcript `toolUseResult`s, text replaced. Neither is authored here: each is
# tool_output, awaits no decision and raises no sentinel. On a project whose
# registration has no matcher, these reach the detector.
env_other() { jq -nc --arg tn "$1" --arg t "$2" '
  {session_id:"bl277", hook_event_name:"PostToolUse", tool_name:$tn, tool_input:{},
   tool_response:(if $tn == "Agent"
     then {status:"completed", prompt:"review", agentId:"a1", content:[{type:"text", text:$t}], totalDurationMs:1}
     else {mode:"content", numFiles:1, filenames:["notes.md"], content:$t, numLines:1} end)}'; }
chk_other_tools() {
  local hook="$1" p tn a ur
  for tn in Agent Grep; do
    p="$(newtmp)"; mk_proj "$p" || { echo "fixture"; return 1; }
    run_hook "$hook" "$p" "$(env_other "$tn" "$(fixture_for no_verify)")"
    a="$(q "$p" '[.[].actor] | unique | join(",")')"; ur="$(q "$p" '[.[].user_response] | unique | join(",")')"
    [ "$(q "$p" 'length')" = "1" ] || { echo "$tn: rows=$(q "$p" 'length'), want 1 (the scan must reach it)"; return 1; }
    [ "$a" = "tool_output" ] && [ "$ur" = "n/a" ] || { echo "$tn: actor=[$a] user_response=[$ur], want [tool_output] [n/a]"; return 1; }
    [ ! -e "$(sentinel "$p")" ] || { echo "$tn: a sentinel was raised"; return 1; }
  done
  return 0
}

# W — a file the model wrote, created or overwritten.
chk_write_authored() {
  local hook="$1" p ty a ur
  for ty in create update; do
    p="$(newtmp)"; mk_proj "$p" || { echo "fixture"; return 1; }
    run_hook "$hook" "$p" "$(env_write "$ty" "$(fixture_for no_verify)")"
    a="$(q "$p" '[.[].actor] | unique | join(",")')"; ur="$(q "$p" '[.[].user_response] | unique | join(",")')"
    [ "$HOOK_RC" -eq 0 ] || { echo "$ty: hook rc=$HOOK_RC"; return 1; }
    [ "$(q "$p" 'length')" = "1" ] || { echo "$ty: rows=$(q "$p" 'length'), want 1"; return 1; }
    [ "$a" = "claude" ] || { echo "$ty: actors=[$a], want [claude]"; return 1; }
    [ "$ur" = "PENDING" ] || { echo "$ty: user_response=[$ur], want [PENDING]"; return 1; }
    [ -f "$(sentinel "$p")" ] || { echo "$ty: no sentinel after the model wrote the text"; return 1; }
  done
  return 0
}

# B — `## BL-336:` Edit and MultiEdit. The shapes are an Edit and a MultiEdit
# envelope as Claude Code sends them (tool_input as the model wrote it,
# tool_response with the file's old text); the proposal sits only where each
# case says.
env_edit() { jq -nc --arg new "$1" --arg old "$2" --arg orig "$3" \
  '{session_id:"bl277", hook_event_name:"PostToolUse", tool_name:"Edit",
    tool_input:{file_path:"/proj/NEXT_STEPS.md", old_string:$old, new_string:$new, replace_all:false},
    tool_response:{filePath:"/proj/NEXT_STEPS.md", oldString:$old, newString:$new, originalFile:$orig,
      structuredPatch:[], userModified:false, replaceAll:false}}'; }
env_multiedit() { jq -nc --arg n1 "$1" --arg n2 "$2" --arg old "$3" --arg orig "$4" \
  '{session_id:"bl277", hook_event_name:"PostToolUse", tool_name:"MultiEdit",
    tool_input:{file_path:"/proj/NEXT_STEPS.md", edits:[{old_string:"first", new_string:$n1}, {old_string:$old, new_string:$n2}]},
    tool_response:{filePath:"/proj/NEXT_STEPS.md", edits:[{old_string:"first", new_string:$n1}, {old_string:$old, new_string:$n2}],
      originalFileContents:$orig, structuredPatch:[], userModified:false}}'; }
# authored_one <hook> <envelope> <label> — one claude row, PENDING, and the sentinel.
authored_one() {
  local hook="$1" p a ur
  p="$(newtmp)"; mk_proj "$p" || { echo "$3: fixture"; return 1; }
  run_hook "$hook" "$p" "$2"
  a="$(q "$p" '[.[].actor] | unique | join(",")')"; ur="$(q "$p" '[.[].user_response] | unique | join(",")')"
  [ "$HOOK_RC" -eq 0 ] || { echo "$3: hook rc=$HOOK_RC"; return 1; }
  [ "$(q "$p" 'length')" = "1" ] || { echo "$3: rows=$(q "$p" 'length'), want 1"; return 1; }
  [ "$a" = "claude" ] && [ "$ur" = "PENDING" ] || { echo "$3: actor=[$a] user_response=[$ur], want [claude] [PENDING]"; return 1; }
  [ -f "$(sentinel "$p")" ] || { echo "$3: no sentinel after the model wrote the text"; return 1; }
  return 0
}
# B1 — an Edit whose new_string is the proposal.
chk_edit_authored() {
  authored_one "$1" "$(env_edit "$(fixture_for no_verify)" "old line" "old line")" "Edit"
}
# B2 — a MultiEdit whose SECOND edit's new_string is the proposal: every edit is read.
chk_multiedit_authored() {
  authored_one "$1" "$(env_multiedit "a clean first edit" "$(fixture_for no_verify)" "old line" "first\nold line")" "MultiEdit"
}
# B3 — an Edit and a MultiEdit that only rewrite unrelated text, while the
# proposal sits in the text they replaced (old_string) and in the file's old
# contents (originalFile, originalFileContents): text the model did not write
# this time. Nothing is recorded.
chk_edit_unrelated() {
  local hook="$1" p which env
  for which in Edit MultiEdit; do
    p="$(newtmp)"; mk_proj "$p" || { echo "$which: fixture"; return 1; }
    case "$which" in
      Edit) env="$(env_edit "the release notes, reworded" "$(fixture_for no_verify)" "intro
$(fixture_for no_verify)
outro")" ;;
      *) env="$(env_multiedit "a clean first edit" "the release notes, reworded" "$(fixture_for no_verify)" "intro
$(fixture_for no_verify)
outro")" ;;
    esac
    run_hook "$hook" "$p" "$env"
    [ "$HOOK_RC" -eq 0 ] || { echo "$which: hook rc=$HOOK_RC"; return 1; }
    [ "$(q "$p" 'length')" = "0" ] || { echo "$which: $(q "$p" 'length') row(s) from text the model did not write: $(q "$p" '[.[].details.excerpt] | join(" | ")')"; return 1; }
    [ ! -e "$(sentinel "$p")" ] || { echo "$which: a sentinel was raised"; return 1; }
  done
  return 0
}

# W2 — a Write whose result carries only {filePath, type}, the shape the hooks
# page shows: the text is read from tool_input.content, what the model wrote.
chk_write_input_only() {
  local hook="$1" env
  env="$(jq -nc --arg t "$(fixture_for no_verify)" '{session_id:"bl277", hook_event_name:"PostToolUse", tool_name:"Write",
    tool_input:{file_path:"/proj/NEXT_STEPS.md", content:$t}, tool_response:{filePath:"/proj/NEXT_STEPS.md", type:"create"}}')"
  authored_one "$hook" "$env" "Write without content in its result"
}

# S — an authored match.
chk_stop_claude_row() {
  local hook="$1" p a ur
  p="$(newtmp)"; mk_proj "$p" || { echo "fixture"; return 1; }
  run_hook "$hook" "$p" "$(env_stop "$(fixture_for no_verify)")"
  a="$(q "$p" '[.[].actor] | unique | join(",")')"; ur="$(q "$p" '.[0].user_response')"
  [ "$(q "$p" 'length')" = "1" ] || { echo "rows=$(q "$p" 'length'), want 1"; return 1; }
  [ "$a" = "claude" ] || { echo "actors=[$a], want [claude]"; return 1; }
  [ "$ur" = "PENDING" ] || { echo "user_response=$ur, want PENDING"; return 1; }
  return 0
}
chk_stop_sentinel() {
  local hook="$1" p s
  p="$(newtmp)"; mk_proj "$p" || { echo "fixture"; return 1; }
  run_hook "$hook" "$p" "$(env_stop "$(fixture_for no_verify)")"
  s="$(sentinel "$p")"
  [ -f "$s" ] || { echo "no sentinel after an authored match"; return 1; }
  jq -e '(.question | length > 0) and (.options | length >= 2) and (.recommendation == "A2") and has("offered_at")' "$s" >/dev/null 2>&1 \
    || { echo "sentinel does not carry the BL-015 schema"; return 1; }
  return 0
}

# L — the ledger feeding itself.
chk_ledger_self_read() {
  local hook="$1" p before after total
  p="$(newtmp)"; mk_proj "$p" || { echo "fixture"; return 1; }
  run_hook "$hook" "$p" "$(env_stop "$(fixture_for no_verify)")"
  before="$(q "$p" '[.[] | select(.actor=="claude")] | length')"
  [ "$before" = "1" ] || { echo "setup: want 1 authored row to read back, got $before"; return 1; }
  run_hook "$hook" "$p" "$(env_post stdout "$(cat "$(ledger "$p")")")"
  run_hook "$hook" "$p" "$(env_post stdout "$(cat "$(ledger "$p")")")"
  after="$(q "$p" '[.[] | select(.actor=="claude")] | length')"; total="$(q "$p" 'length')"
  [ "$after" = "1" ] || { echo "claude rows went $before -> $after by reading the ledger"; return 1; }
  [ "$total" -gt 1 ] 2>/dev/null || { echo "total rows=$total: the read-back was not scanned, so this proves nothing"; return 1; }
  return 0
}

# K — the shipped template, whole, as tool output.
chk_template_read() {
  local hook="$1" p total claude
  p="$(newtmp)"; mk_proj "$p" || { echo "fixture"; return 1; }
  run_hook "$hook" "$p" "$(env_post stdout "$(cat "$TEMPLATE")")"
  total="$(q "$p" 'length')"; claude="$(q "$p" '[.[] | select(.actor=="claude")] | length')"
  [ "$total" -ge 1 ] 2>/dev/null || { echo "rows=$total: the template no longer matches anything, so this case is vacuous"; return 1; }
  [ "$claude" = "0" ] || { echo "$claude of $total row(s) attributed to claude"; return 1; }
  [ ! -e "$(sentinel "$p")" ] || { echo "reading the shipped template raised a sentinel"; return 1; }
  return 0
}

# G — the gate. The origin remote is load-bearing: an earlier arm denies a
# commit in a repository with no remote, before the arms under test are reached
# (tests/test-bl278-sentinel-root.sh found that out). The URL is never contacted.
mk_repo() {
  local d="$1"
  mk_proj "$d" || return 1
  git -C "$d" init -q . >/dev/null 2>&1 || return 1
  git -C "$d" config user.email "t@example.com" || return 1
  git -C "$d" config user.name "t" || return 1
  git -C "$d" remote add origin "$d/../bl277-not-a-real-remote.git" || return 1
  return 0
}
run_gate() {
  local gate="$1" repo="$2" cmd="$3" env
  env=$(jq -nc --arg c "$repo" --arg cmd "$cmd" \
        '{session_id:"bl277", hook_event_name:"PreToolUse", cwd:$c, tool_name:"Bash", tool_input:{command:$cmd}}')
  GATE_OUT="$(newtmp)/out"
  # SKIP_LINT=1 scopes out the operator-side lint arms, which sit AFTER every
  # arm under test and would sweep the framework checkout on each call.
  ( cd "$repo" && printf '%s' "$env" | SKIP_LINT=1 bash "$gate" >"$GATE_OUT" 2>/dev/null )
  GATE_RC=$?
  return 0
}
denied()     { grep -q '"permissionDecision": "deny"' "$GATE_OUT" 2>/dev/null; }
reason_has() { grep -qF -e "$1" "$GATE_OUT" 2>/dev/null; }

chk_gate_after_tool_output() {
  local hook="$1" r
  r="$(newtmp)/repo"; mk_repo "$r" || { echo "fixture"; return 1; }
  run_hook "$hook" "$r" "$(env_post stdout "$(fixture_for no_verify)")"
  [ "$(q "$r" 'length')" = "1" ] || { echo "setup: the tool-output row was not written"; return 1; }
  run_gate "$GATE" "$r" "git commit -m wip"
  if reason_has "pending user decision"; then echo "a ledger holding only tool-output rows blocked the commit"; return 1; fi
  return 0
}
chk_gate_after_authored() {
  local hook="$1" r
  r="$(newtmp)/repo"; mk_repo "$r" || { echo "fixture"; return 1; }
  run_hook "$hook" "$r" "$(env_stop "$(fixture_for no_verify)")"
  run_gate "$GATE" "$r" "git commit -m wip"
  denied && reason_has "pending user decision" || { echo "an authored match did not block the commit (rc=$GATE_RC)"; return 1; }
  return 0
}
# S3 — the gate relays the sentinel's question to the model, so the question
# names no way to close the proposal as a false positive: that close is the
# operator's. The relayed question is checked non-empty first, so a gate that
# stopped relaying it cannot pass this case.
chk_gate_no_fp_pointer() {
  local hook="$1" r
  r="$(newtmp)/repo"; mk_repo "$r" || { echo "fixture"; return 1; }
  run_hook "$hook" "$r" "$(env_stop "$(fixture_for no_verify)")"
  run_gate "$GATE" "$r" "git commit -m wip"
  denied && reason_has "Bypass proposal detected" || { echo "the gate did not relay the sentinel's question (rc=$GATE_RC)"; return 1; }
  # The gate's own text names `pending-approval.sh --resolve`, for after the
  # user has picked, so the script's name alone is not the pointer.
  for t in "false-positive" "false positive" "false_positive" "--reason"; do
    if reason_has "$t"; then echo "the relayed question names '$t'"; return 1; fi
  done
  return 0
}

# D — the third disposition.
REASON_FP="the matched text was a rule quoted from CLAUDE.md, nobody proposed it"
# The library's fixed wording, read from the library itself so the suite cannot
# drift from it.
ACC_TEXT="$( . "$LIB" >/dev/null 2>&1; printf '%s' "${BYPASS_ACCEPT_TEXT:-}")"
FP_TEXT="$( . "$LIB" >/dev/null 2>&1; printf '%s' "${BYPASS_FALSE_POSITIVE_TEXT:-}")"
FP_LEAD="$( . "$LIB" >/dev/null 2>&1; printf '%s' "${BYPASS_FALSE_POSITIVE_LEAD:-}")"
DEC_TEXT="$( . "$LIB" >/dev/null 2>&1; printf '%s' "${BYPASS_DECLINE_TEXT:-}")"
Q_PREFIX="$( . "$LIB" >/dev/null 2>&1; printf '%s' "${BYPASS_QUESTION_PREFIX:-}")"
sha_of() { { sha256sum "$1" 2>/dev/null || shasum -a 256 "$1" 2>/dev/null; } | awk '{print $1; exit}'; }
sum_of() { [ -f "$1" ] && cksum < "$1" || printf 'ABSENT'; }
# seed_pending DIR [VERSION] — an open proposal as the real detector leaves it:
# one claude row, PENDING, bound to the detector's own schema-2 question.
seed_pending() {
  local d="$1"
  mk_proj "$d" "${2:-4.4.0}" || return 1
  run_hook "$HOOK" "$d" "$(env_stop "$(fixture_for no_verify)")"
  [ -f "$(sentinel "$d")" ] && [ "$(q "$d" '[.[] | select(.user_response=="PENDING")] | length')" = "1" ] || return 1
  return 0
}
# pick_a3 DIR — what record-approval.sh does when the user picks A3 of the
# question on disk: a pick record, then the question removed. picked_at is
# fixed after every row this suite writes.
pick_a3() {
  local d="$1" s
  s="$(sentinel "$d")"
  jq -c --arg h "$(sha_of "$s")" '{event:"approval", source:"pick", session_id:"bl277", pick:"A3", approves:"none",
      question:.question, option_text:(.options[] | select(.id=="A3") | .text), sentinel_sha256:$h, picked_at:"2099-01-01T00:00:00Z"}' \
    "$s" >> "$d/.claude/approvals.jsonl" || return 1
  mv "$s" "$d/q-answered.json"
}
# run_pa <script> <project> args... -> PA_RC — the agent's side: stdin is not a
# terminal, whoever runs this suite.
run_pa() {
  local script="$1" d="$2"; shift 2
  ( cd "$d" && bash "$script" "$@" </dev/null >/dev/null 2>&1 )
  PA_RC=$?
  return 0
}
# run_tty <dir> <answer> <command...> -> TTY_RC — the operator's side: the
# command runs with a pseudo-terminal on stdin, from BSD or util-linux
# script(1), and <answer> is typed at it: nothing when it is empty, a bare
# Enter when it is RUN_TTY_ENTER, otherwise the text and Enter. It reaches script(1) as
# a generated file, so arguments holding tabs or newlines survive util-linux's
# single command string, and its exit code comes back through a file. No
# script(1), or a command that never ran, leaves TTY_RC=NORUN, which every
# caller treats as a failure.
# The answer is typed only once the command is about to run: BSD script(1)
# discards input that arrives while it sets the terminal up. CI and
# SOIF_NONINTERACTIVE are cleared, as they are in an operator's own terminal;
# prompt_yes_no answers N under either.
RUN_TTY_ENTER='<enter>'
run_tty() {
  local d="$1" ans="$2" w; shift 2
  w="$(newtmp)"
  { printf 'unset CI SOIF_NONINTERACTIVE\n'; printf 'cd %q || exit 99\n' "$d"; printf ': > %q\n' "$w/ready"
    printf '%q ' "$@"; printf '>%q 2>&1\n' "$w/out"
    printf 'printf "%%s" "$?" > %q\n' "$w/rc"; } > "$w/run.sh"
  TTY_OUT="$w/out"
  _tty_feed() {
    local i=0
    while [ ! -e "$w/ready" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
    case "$ans" in
      '') ;;
      "$RUN_TTY_ENTER") printf '\n' 2>/dev/null ;;
      *) printf '%s\n' "$ans" 2>/dev/null ;;
    esac
    # Held open until the command is done: BSD script(1) types ^D into the
    # terminal when its stdin ends, which a prompt not yet reached reads as
    # an empty answer.
    i=0
    while [ ! -e "$w/rc" ] && [ "$i" -lt 1200 ]; do sleep 0.1; i=$((i + 1)); done
  }
  if script --version >/dev/null 2>&1; then
    _tty_feed | script -qec "bash $(printf '%q' "$w/run.sh")" /dev/null >/dev/null 2>&1
  else
    _tty_feed | script -q /dev/null bash "$w/run.sh" >/dev/null 2>&1
  fi
  TTY_RC="$(cat "$w/rc" 2>/dev/null || printf 'NORUN')"
  return 0
}
# run_pa_tty <script> <project> args... -> PA_RC — the operator answers
# ${PA_ANSWER-y} at the confirmation.
run_pa_tty() { local script="$1" d="$2"; shift 2; run_tty "$d" "${PA_ANSWER-y}" bash "$script" "$@"; PA_RC="$TTY_RC"; return 0; }
# unmoved <project> <sentinel cksum before> — the question on disk and every
# row are as they were: one PENDING row, no reason, still bound to the question.
unmoved() {
  local d="$1" before="$2"
  [ "$(sum_of "$(sentinel "$d")")" = "$before" ] || { echo "the question on disk changed"; return 1; }
  [ "$(q "$d" '.[0].user_response')" = "PENDING" ] || { echo "the row was closed"; return 1; }
  [ "$(q "$d" '.[0].details | has("false_positive_reason")')" = "false" ] || { echo "a reason was written"; return 1; }
  [ "$(q "$d" '.[0].details.sentinel_sha256')" = "$(sha_of "$(sentinel "$d")")" ] || { echo "the row was rebound"; return 1; }
  return 0
}
# D1 — the operator's close, then the user's pick. The operator's command puts
# the question again, with A3 and the reason, and closes nothing; the user's
# pick of A3 closes the row as false_positive with the reason, read from the
# pick record when the agent next runs --resolve.
chk_fp_closes() {
  local pa="$1" d s ur fo why
  d="$(newtmp)"; seed_pending "$d" || { echo "fixture"; return 1; }
  run_pa_tty "$pa" "$d" --resolve --decision false-positive --reason "$REASON_FP"
  s="$(sentinel "$d")"
  [ "$PA_RC" = "0" ] || { echo "the operator's close: rc=$PA_RC, want 0"; return 1; }
  jq -e --arg fp "$FP_TEXT" --arg tail "$FP_LEAD$REASON_FP" --arg pre "$Q_PREFIX" \
    '.schema == 2 and .source == "bypass-false-positive" and ([.options[].id] == ["A1","A2","A3"])
     and ([.options[].approves] | unique) == ["none"] and (.options[2].text == $fp)
     and (.question | startswith($pre)) and (.question | endswith($tail))' "$s" >/dev/null 2>&1 \
    || { echo "the question was not asked again with A3 and the reason: $(cat "$s" 2>/dev/null)"; return 1; }
  # Whoever can run the command under a pseudo-terminal, or write the file, can
  # put this question, so it names no asker and recommends declining, as the
  # detector's own question does.
  jq -e '.recommendation == "A2" and (.question | test("Orchestrator|operator"; "i") | not)' "$s" >/dev/null 2>&1 \
    || { echo "the question names an asker or recommends other than A2: $(jq -c '{recommendation, question}' "$s" 2>/dev/null)"; return 1; }
  [ "$(q "$d" '.[0].user_response')" = "PENDING" ] || { echo "the operator's command closed the row itself"; return 1; }
  [ "$(q "$d" '.[0].details.sentinel_sha256')" = "$(sha_of "$s")" ] || { echo "the row is not bound to the new question"; return 1; }
  pick_a3 "$d" || { echo "fixture: the pick"; return 1; }
  run_pa "$pa" "$d" --resolve
  ur="$(q "$d" '.[0].user_response')"; fo="$(q "$d" '.[0].final_outcome')"; why="$(q "$d" '.[0].details.false_positive_reason')"
  [ "$PA_RC" = "0" ] || { echo "--resolve after the pick: rc=$PA_RC, want 0"; return 1; }
  [ "$ur" = "false_positive" ] || { echo "user_response=$ur, want false_positive"; return 1; }
  [ "$fo" = "recorded_only" ] || { echo "final_outcome=$fo, want recorded_only"; return 1; }
  [ "$why" = "$REASON_FP" ] || { echo "the reason was not recorded on the row (got '$why')"; return 1; }
  [ "$(q "$d" '.[0].details.pick')" = "A3" ] || { echo "the row does not say the user picked A3"; return 1; }
  return 0
}
# D2 runs on the operator's side, so the refusal it sees is the reason guard's
# and not the terminal guard's.
chk_fp_refuses_empty_reason() {
  local pa="$1" d shape tab nl before why
  tab="$(printf '\t')"; nl="
"
  for shape in missing empty blank tab newline; do
    d="$(newtmp)"; seed_pending "$d" || { echo "fixture"; return 1; }
    before="$(sum_of "$(sentinel "$d")")"
    case "$shape" in
      missing) run_pa_tty "$pa" "$d" --resolve --decision false-positive ;;
      empty)   run_pa_tty "$pa" "$d" --resolve --decision false-positive --reason "" ;;
      blank)   run_pa_tty "$pa" "$d" --resolve --decision false-positive --reason "   " ;;
      tab)     run_pa_tty "$pa" "$d" --resolve --decision false-positive --reason "$tab" ;;
      newline) run_pa_tty "$pa" "$d" --resolve --decision false-positive --reason "$nl" ;;
    esac
    case "$PA_RC" in ''|NORUN|*[!0-9]*) echo "$shape reason: the command did not run (rc=$PA_RC)"; return 1 ;; 0) echo "$shape reason: rc=0, want a refusal"; return 1 ;; esac
    why="$(unmoved "$d" "$before")" || { echo "$shape reason: $why"; return 1; }
  done
  return 0
}
# D5 — the agent's side: a well-formed close with a reason, refused because
# stdin is not a terminal. Nothing moves, and nothing is asked.
chk_fp_needs_terminal() {
  local pa="$1" d before why
  d="$(newtmp)"; seed_pending "$d" || { echo "fixture"; return 1; }
  before="$(sum_of "$(sentinel "$d")")"
  run_pa "$pa" "$d" --resolve --decision false-positive --reason "$REASON_FP"
  [ "$PA_RC" -ne 0 ] || { echo "rc=0: the false-positive close ran with no terminal on stdin"; return 1; }
  why="$(unmoved "$d" "$before")" || { echo "$why"; return 1; }
  return 0
}
# D10 — below the Guardrails minimum, or with no readable version, no pick can
# be recorded, so nothing is asked: the operator's well-formed close is refused.
chk_fp_needs_pick_route() {
  local pa="$1" d v before why
  for v in 4.3.0 test; do
    d="$(newtmp)"; seed_pending "$d" "$v" || { echo "$v: fixture"; return 1; }
    before="$(sum_of "$(sentinel "$d")")"
    run_pa_tty "$pa" "$d" --resolve --decision false-positive --reason "$REASON_FP"
    case "$PA_RC" in ''|NORUN|*[!0-9]*) echo "$v: the command did not run (rc=$PA_RC)"; return 1 ;; 0) echo "$v: rc=0, want a refusal"; return 1 ;; esac
    why="$(unmoved "$d" "$before")" || { echo "$v: $why"; return 1; }
  done
  return 0
}
# D16 — the question asked again and no pick: the agent's --resolve withdraws
# it, and every row stays PENDING. Getting past the terminal check (as an agent
# can, under a pseudo-terminal) asks the user; it closes nothing.
chk_fp_no_pick_no_close() {
  local pa="$1" d
  d="$(newtmp)"; seed_pending "$d" || { echo "fixture"; return 1; }
  run_pa_tty "$pa" "$d" --resolve --decision false-positive --reason "$REASON_FP"
  [ "$PA_RC" = "0" ] && jq -e '.source == "bypass-false-positive"' "$(sentinel "$d")" >/dev/null 2>&1 || { echo "fixture: not asked again (rc=$PA_RC)"; return 1; }
  run_pa "$pa" "$d" --resolve
  [ "$(q "$d" '.[0].user_response')" = "PENDING" ] || { echo "a --resolve with no pick closed the row as $(q "$d" '.[0].user_response')"; return 1; }
  [ "$(q "$d" '.[0].details | has("false_positive_reason")')" = "false" ] || { echo "a reason was written with no pick"; return 1; }
  return 0
}
# D11 — A3 picks the agent could arrange without the operator: a question it
# wrote itself with A3 but no reason (or a reason of whitespace), picked by the
# user. No reason the user was shown, so no close: the rows stay PENDING.
chk_fp_pick_needs_reason() {
  local pa="$1" d tail s
  for tail in "" "$FP_LEAD   "; do
    d="$(newtmp)"; seed_pending "$d" || { echo "fixture"; return 1; }
    s="$(sentinel "$d")"
    jq --arg fp "$FP_TEXT" --arg t "$tail" '.source = "bypass-false-positive" | .question = (.question + " " + $t)
        | .options += [{id:"A3", text:$fp, approves:"none"}]' "$s" > "$s.new" && mv "$s.new" "$s"
    jq --arg h "$(sha_of "$s")" '[.[] | .details.sentinel_sha256 = $h]' "$(ledger "$d")" > "$d/l" && mv "$d/l" "$(ledger "$d")"
    pick_a3 "$d" || { echo "fixture: the pick"; return 1; }
    run_pa "$pa" "$d" --resolve
    [ "$(q "$d" '.[0].user_response')" = "PENDING" ] || { echo "an A3 pick with no reason shown (tail '$tail') closed the row as $(q "$d" '.[0].user_response')"; return 1; }
  done
  return 0
}
# D13 — a question that is not about the proposals (a commit question) is the
# user's to answer: the operator's close is refused and the question untouched.
chk_fp_other_question() {
  local pa="$1" d s before
  d="$(newtmp)"; seed_pending "$d" || { echo "fixture"; return 1; }
  s="$(sentinel "$d")"
  jq -nc '{schema:2, question:"Commit the fix?", options:[{id:"A1",text:"Commit it",approves:"commit"},{id:"A2",text:"Hold",approves:"none"}], recommendation:"A1", offered_at:"2026-09-18T00:00:00Z"}' > "$s"
  before="$(sum_of "$s")"
  run_pa_tty "$pa" "$d" --resolve --decision false-positive --reason "$REASON_FP"
  case "$PA_RC" in ''|NORUN|*[!0-9]*) echo "the command did not run (rc=$PA_RC)"; return 1 ;; 0) echo "rc=0, want a refusal"; return 1 ;; esac
  [ "$(sum_of "$s")" = "$before" ] || { echo "the commit question was replaced"; return 1; }
  [ "$(q "$d" '.[0].user_response')" = "PENDING" ] || { echo "the row was closed"; return 1; }
  return 0
}
# D14 — nothing PENDING: nothing to ask about, so nothing is written.
chk_fp_nothing_pending() {
  local pa="$1" d
  d="$(newtmp)"; mk_proj "$d" || { echo "fixture"; return 1; }
  run_pa_tty "$pa" "$d" --resolve --decision false-positive --reason "$REASON_FP"
  case "$PA_RC" in ''|NORUN|*[!0-9]*) echo "the command did not run (rc=$PA_RC)"; return 1 ;; 0) echo "rc=0, want a refusal"; return 1 ;; esac
  [ ! -e "$(sentinel "$d")" ] || { echo "a question was written with no proposal to ask about"; return 1; }
  return 0
}
# D15 — a proposal raised while the operator's question is open is not bound to
# it, so the user's A3 closes only the proposals the operator looked at. The
# later proposal has the SAME pattern, so the question naming it (D18's rule)
# does not shield it: only the label does.
chk_fp_later_proposal() {
  local pa="$1" d
  d="$(newtmp)"; seed_pending "$d" || { echo "fixture"; return 1; }
  run_pa_tty "$pa" "$d" --resolve --decision false-positive --reason "$REASON_FP"
  [ "$PA_RC" = "0" ] || { echo "fixture: the operator's close rc=$PA_RC"; return 1; }
  run_hook "$HOOK" "$d" "$(env_stop "and again: $(fixture_for no_verify)")"
  [ "$(q "$d" 'length')" = "2" ] || { echo "fixture: the later proposal was not recorded"; return 1; }
  pick_a3 "$d" || { echo "fixture: the pick"; return 1; }
  run_pa "$pa" "$d" --resolve
  [ "$(q "$d" '.[0].user_response')" = "false_positive" ] || { echo "the proposal the operator looked at: $(q "$d" '.[0].user_response'), want false_positive"; return 1; }
  [ "$(q "$d" '.[1].user_response')" = "PENDING" ] || { echo "a proposal raised after the operator asked was closed as $(q "$d" '.[1].user_response')"; return 1; }
  return 0
}
# reask <script> <project> — the operator's re-ask, answered y; rc 0 or a reason.
reask() { run_pa_tty "$1" "$2" --resolve --decision false-positive --reason "$REASON_FP"; [ "$PA_RC" = "0" ]; }
# pick_rec <project> <question> <option text> <approves> <picked_at> <sha> [<pick>]
# — a pick record of any shape, as record-approval.sh appends one.
pick_rec() {
  jq -nc --arg q "$2" --arg t "$3" --arg a "$4" --arg at "$5" --arg h "$6" --arg p "${7:-A3}" \
    '{event:"approval", source:"pick", session_id:"bl277", pick:$p, approves:$a, question:$q, option_text:$t, sentinel_sha256:$h, picked_at:$at}' \
    >> "$1/.claude/approvals.jsonl"
}
# a3_guard_case <script> <shape> — the operator's re-ask, then one A3 pick that
# fails one guard of `# BL-277-FP-PICK-MAP`; --resolve must leave the row PENDING.
#   other-question  the pick's question is not a bypass question, though it names
#                   the pattern and carries a reason (X1, $isq)
#   approves-commit the picked option approves a commit (X2, $none)
#   before-row      the pick was made before the row was raised: a replay (X3, $after)
a3_guard_case() {
  local pa="$1" shape="$2" d s h qq at ap
  d="$(newtmp)"; seed_pending "$d" || { echo "fixture"; return 1; }
  reask "$pa" "$d" || { echo "fixture: the re-ask rc=$PA_RC"; return 1; }
  s="$(sentinel "$d")"; h="$(sha_of "$s")"; qq="$(jq -r '.question' "$s")"; at="2099-01-01T00:00:00Z"; ap="none"
  case "$shape" in
    other-question)  qq="Merge or rebase? (pattern: no_verify) $FP_LEAD$REASON_FP" ;;
    approves-commit) ap="commit" ;;
    before-row)      at="2000-01-01T00:00:00Z" ;;
  esac
  pick_rec "$d" "$qq" "$FP_TEXT" "$ap" "$at" "$h" || { echo "fixture: the pick"; return 1; }
  mv "$s" "$d/q-answered.json"
  run_pa "$pa" "$d" --resolve
  [ "$(q "$d" '.[0].user_response')" = "PENDING" ] || { echo "$shape: an A3 pick closed the row as $(q "$d" '.[0].user_response')"; return 1; }
  return 0
}
chk_a3_other_question()  { a3_guard_case "$1" other-question; }
chk_a3_approves_commit() { a3_guard_case "$1" approves-commit; }
chk_a3_before_row()      { a3_guard_case "$1" before-row; }
# seed_two DIR — two PENDING proposals, no_verify and force_push, both bound to
# the detector's question (the second raised while it was open).
seed_two() {
  local d="$1"
  seed_pending "$d" || return 1
  run_hook "$HOOK" "$d" "$(env_stop "$(fixture_for force_push)")"
  [ "$(q "$d" '[.[] | select(.user_response=="PENDING")] | length')" = "2" ]
}
# D1b — X4: two patterns PENDING; the operator's question names both, and the
# A3 pick closes both.
chk_fp_closes_two() {
  local pa="$1" d
  d="$(newtmp)"; seed_two "$d" || { echo "fixture"; return 1; }
  reask "$pa" "$d" || { echo "the re-ask rc=$PA_RC"; return 1; }
  jq -e '.question | contains("(pattern: force_push, no_verify)")' "$(sentinel "$d")" >/dev/null 2>&1 \
    || { echo "the question does not name both patterns: $(jq -r '.question' "$(sentinel "$d")" | cut -c1-80)"; return 1; }
  pick_a3 "$d" || { echo "fixture: the pick"; return 1; }
  run_pa "$pa" "$d" --resolve
  [ "$(q "$d" '[.[].user_response] | unique | join(",")')" = "false_positive" ] || { echo "rows after the A3 pick: $(q "$d" '[.[] | .details.pattern + "=" + .user_response] | join(" ")')"; return 1; }
  return 0
}
# D18 — C(a): an A3 question that names only no_verify (written by an agent,
# with every PENDING row rebound to it): the A3 pick closes the no_verify row
# and leaves the force_push row PENDING. A pick closes only what the user read.
chk_fp_named_only() {
  local pa="$1" d s
  d="$(newtmp)"; seed_two "$d" || { echo "fixture"; return 1; }
  reask "$pa" "$d" || { echo "fixture: the re-ask rc=$PA_RC"; return 1; }
  s="$(sentinel "$d")"
  jq '.question |= sub("\\(pattern: [^)]*\\)"; "(pattern: no_verify)")' "$s" > "$s.new" && mv "$s.new" "$s"
  jq -e '.question | contains("(pattern: no_verify)")' "$s" >/dev/null 2>&1 || { echo "fixture: the question was not rewritten"; return 1; }
  ( . "$LIB" && bypass_audit_rebind_pending "$d" "$(sha_of "$s")" ) >/dev/null 2>&1 || { echo "fixture: rebind"; return 1; }
  pick_a3 "$d" || { echo "fixture: the pick"; return 1; }
  run_pa "$pa" "$d" --resolve
  [ "$(q "$d" '[.[] | select(.details.pattern=="no_verify") | .user_response] | join(",")')" = "false_positive" ] \
    || { echo "the named no_verify row: $(q "$d" '[.[] | select(.details.pattern=="no_verify") | .user_response] | join(",")')"; return 1; }
  [ "$(q "$d" '[.[] | select(.details.pattern=="force_push") | .user_response] | join(",")')" = "PENDING" ] \
    || { echo "an A3 pick closed the force_push row, which its question does not name"; return 1; }
  return 0
}
# D19 — C(b): the user already answered A2 on the detector's question and no
# --resolve has read it yet. The operator's re-ask reads that pick first: the
# row closes as declined, nothing is left to ask about, and no question is put.
chk_fp_reconciles_first() {
  local pa="$1" d s
  d="$(newtmp)"; seed_pending "$d" || { echo "fixture"; return 1; }
  s="$(sentinel "$d")"
  pick_rec "$d" "$(jq -r '.question' "$s")" "$DEC_TEXT" none "2099-01-01T00:00:00Z" "$(sha_of "$s")" A2 || { echo "fixture: the pick"; return 1; }
  mv "$s" "$d/q-answered.json"
  run_pa_tty "$pa" "$d" --resolve --decision false-positive --reason "$REASON_FP"
  [ "$(q "$d" '.[0].user_response')" = "declined" ] || { echo "the user's A2 was not read first: the row is $(q "$d" '.[0].user_response')"; return 1; }
  [ ! -e "$(sentinel "$d")" ] || { echo "a question was put though the user had answered"; return 1; }
  case "$PA_RC" in 0|NORUN|'') echo "rc=$PA_RC, want a refusal (nothing left PENDING)"; return 1 ;; esac
  return 0
}
# D8 — a stub install (no scripts/lib/helpers-core.sh, the fallback at the top
# of the script): the operator's well-formed close cannot be confirmed, so it
# is refused and says why. <script> is the copy whose helpers are removed.
chk_fp_stub_refuses() {
  local pa="$1" d before why
  d="$(newtmp)"; seed_pending "$d" || { echo "fixture"; return 1; }
  before="$(sum_of "$(sentinel "$d")")"
  run_pa_tty "$pa" "$d" --resolve --decision false-positive --reason "$REASON_FP"
  case "$PA_RC" in ''|NORUN|*[!0-9]*) echo "the command did not run (rc=$PA_RC)"; return 1 ;; 0) echo "rc=0, want a refusal"; return 1 ;; esac
  why="$(unmoved "$d" "$before")" || { echo "$why"; return 1; }
  grep -q 'helpers-core.sh' "$TTY_OUT" 2>/dev/null || { echo "the refusal does not name helpers-core.sh"; return 1; }
  if grep -q 'command not found' "$TTY_OUT" 2>/dev/null; then echo "the script ran a command it does not define"; return 1; fi
  return 0
}
stub_mirror() { local md; md="$(mirror_scripts)" && rm -f "$md/scripts/lib/helpers-core.sh" && printf '%s' "$md"; }

# D7 — the operator's side, well-formed, but the operator answers no, or just
# presses Enter (the default is N). Cancelled as --unrecord-feature and --reset
# cancel: rc 0, nothing moves.
chk_fp_operator_declines() {
  local pa="$1" d ans before why
  for ans in n "$RUN_TTY_ENTER"; do
    d="$(newtmp)"; seed_pending "$d" || { echo "fixture"; return 1; }
    before="$(sum_of "$(sentinel "$d")")"
    PA_ANSWER="$ans" run_pa_tty "$pa" "$d" --resolve --decision false-positive --reason "$REASON_FP"
    [ "$PA_RC" = "0" ] || { echo "answer '$ans': rc=$PA_RC, want 0 (cancelled)"; return 1; }
    grep -qF -e "$REASON_FP" "$TTY_OUT" 2>/dev/null || { echo "answer '$ans': the confirmation did not show the reason"; return 1; }
    why="$(unmoved "$d" "$before")" || { echo "answer '$ans': $why"; return 1; }
  done
  return 0
}
# D17 — R-454-1: an agent's direct call of the library with false-positive.
# The library has no false-positive arm, so a false_positive row can come only
# from the user's A3 pick: refused, with any reason, and the row unmoved.
chk_lib_no_false_positive_pa() { chk_lib_no_false_positive "$(dirname "$1")/lib/bypass-audit.sh"; }
chk_lib_no_false_positive() {
  local lib="$1" d rc why tab
  tab="$(printf '\t')"
  for why in "it quoted a rule" "   " "$tab"; do
    d="$(newtmp)"; seed_pending "$d" || { echo "fixture"; return 1; }
    ( . "$lib" && bypass_audit_close_pending "$d" false-positive "$why" ) >/dev/null 2>&1; rc=$?
    [ "$rc" -ne 0 ] || { echo "reason '$why': the library closed rows as false_positive (rc 0)"; return 1; }
    [ "$(q "$d" '.[0].user_response')" = "PENDING" ] || { echo "reason '$why': the row was closed as $(q "$d" '.[0].user_response')"; return 1; }
    [ "$(q "$d" '.[0].details | has("false_positive_reason")')" = "false" ] || { echo "reason '$why': a reason was written"; return 1; }
  done
  return 0
}
# D9 — a close changes only PENDING claude_bypass_proposal rows. The ledger
# holds the row classes this change creates (a tool_output row, user_response
# n/a) and an open escalation; under accept and decline, through the library,
# the two proposal rows close and every other row is byte-identical.
seed_mixed() {
  local d="$1"
  mk_proj "$d" || return 1
  jq -nc '[
    {timestamp:"t1", session_id:"bl277", type:"claude_bypass_proposal", actor:"claude", enforcement_level_at_event:"strict",
     details:{pattern:"no_verify", event:"Stop", excerpt:"x", severity:"normal"}, user_response:"PENDING", final_outcome:"recorded_only"},
    {timestamp:"t2", session_id:"bl277", type:"claude_bypass_proposal", actor:"tool_output", enforcement_level_at_event:"strict",
     details:{pattern:"no_verify", event:"PostToolUse", excerpt:"x", severity:"normal"}, user_response:"n/a", final_outcome:"recorded_only"},
    {timestamp:"t3", session_id:"bl277", type:"escalation", actor:"claude", enforcement_level_at_event:"strict",
     details:{question:"q"}, user_response:"PENDING", final_outcome:"n/a"},
    {timestamp:"t4", session_id:"bl277", type:"claude_bypass_proposal", actor:"claude", enforcement_level_at_event:"strict",
     details:{pattern:"force_push", event:"Stop", excerpt:"y", severity:"normal"}, user_response:"PENDING", final_outcome:"recorded_only"}
  ]' > "$(ledger "$d")"
}
chk_close_scope() {
  local lib="$1" d dec ur rc before after
  for dec in accept decline; do
    d="$(newtmp)"; seed_mixed "$d" || { echo "fixture"; return 1; }
    before="$(jq -c '[.[1], .[2]]' "$(ledger "$d")")"
    ( . "$lib" && bypass_audit_close_pending "$d" "$dec" "$REASON_FP" ) >/dev/null 2>&1; rc=$?
    case "$dec" in accept) ur="accepted" ;; decline) ur="declined" ;; esac
    [ "$rc" -eq 0 ] || { echo "$dec: rc=$rc"; return 1; }
    [ "$(q "$d" "[.[0], .[3]] | map(.user_response) | unique | join(\",\")")" = "$ur" ] || { echo "$dec: the proposal rows are not $ur"; return 1; }
    after="$(jq -c '[.[1], .[2]]' "$(ledger "$d")")"
    [ "$before" = "$after" ] || { echo "$dec: a tool_output or escalation row changed: $after"; return 1; }
  done
  return 0
}
# D6 — the library refuses a decision it does not know, even with a reason, so
# a widened pattern cannot turn a typo into a close.
chk_lib_refuses_unknown() {
  local lib="$1" d rc
  d="$(newtmp)"; seed_pending "$d" 4.3.0 || { echo "fixture"; return 1; }
  ( . "$lib" && bypass_audit_close_pending "$d" accpet "$REASON_FP" ) >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 0 ] || { echo "the library accepted the decision 'accpet'"; return 1; }
  [ "$(q "$d" '.[0].user_response')" = "PENDING" ] || { echo "an unknown decision closed the row as $(q "$d" '.[0].user_response')"; return 1; }
  return 0
}
# D3 — accept and decline are unchanged, and carry no false_positive_reason:
# the reason belongs to false-positive closes only. A --reason is passed so a
# close that wrote it everywhere would write text, not just an empty key. The
# agent's own --decision is the legacy route's (Guardrails 4.3.0): `## BL-320:`
# refuses it from 4.4.0 on.
chk_decline_still_declines() {
  local pa="$1" d dec ur fo
  for dec in decline accept; do
    d="$(newtmp)"; seed_pending "$d" 4.3.0 || { echo "fixture"; return 1; }
    run_pa "$pa" "$d" --resolve --decision "$dec" --reason "$REASON_FP"
    case "$dec" in decline) ur="declined"; fo="abandoned" ;; accept) ur="accepted"; fo="bypassed" ;; esac
    [ "$PA_RC" -eq 0 ] && [ "$(q "$d" '.[0].user_response')" = "$ur" ] && [ "$(q "$d" '.[0].final_outcome')" = "$fo" ] \
      || { echo "$dec no longer records $ur/$fo (rc=$PA_RC)"; return 1; }
    [ "$(q "$d" '.[0].details | has("false_positive_reason")')" = "false" ] \
      || { echo "$dec wrote a false_positive_reason onto the row"; return 1; }
  done
  return 0
}

# E1 — the false-positive round trip against the real Guardrails hooks. The
# agent's two ways to write the answer file are refused by config-guard; the
# user's first reply shows them A3 and the reason (record-approval.sh's render,
# which reaches the user); the second records the pick; the agent's --resolve
# then closes the row from it. Prints the reason and returns 1 on failure, 77
# when the fixture is not here (locally).
E_D=""
e_hook() { ( cd "$E_D" && env -u CLAUDECODE CLAUDE_PROJECT_DIR="$E_D" bash "$E_D/.claude/framework/hooks/$1" ); }
e_ups() { jq -nc --arg p "$1" --arg d "$E_D" --arg i "$2" '{session_id:"bl277-e", transcript_path:"/dev/null", cwd:$d, prompt_id:$i, permission_mode:"default", hook_event_name:"UserPromptSubmit", prompt:$p}'; }
chk_fp_real_guardrails() {
  local pa="$1" out rc h
  case "$CDF_RC" in 0) ;; 77) return 77 ;; *) echo "the pinned Guardrails fixture: $CDF_FIXTURE_WHY"; return 1 ;; esac
  E_D="$(newtmp)/eproj"
  seed_pending "$E_D" || { echo "fixture"; return 1; }
  ( cd "$E_D" && git init -q && git config user.email t@example.com && git config user.name t \
      && printf 'seed\n' > seed.txt && git add seed.txt && git commit -q -m seed ) >/dev/null 2>&1 || { echo "fixture: git"; return 1; }
  mkdir -p "$E_D/.claude/framework/hooks" && cp "$CDF_CLONE"/hooks/* "$E_D/.claude/framework/hooks/" && chmod +x "$E_D"/.claude/framework/hooks/*.sh \
    || { echo "fixture: hooks"; return 1; }
  h="$(printf '%s' "$E_D" | shasum -a 256 | cut -c1-12)"; E_HASHES="$E_HASHES $h"
  run_pa_tty "$pa" "$E_D" --resolve --decision false-positive --reason "$REASON_FP"
  [ "$PA_RC" = "0" ] || { echo "the operator's close: rc=$PA_RC"; return 1; }
  # The agent writes the answer file itself: with the Write tool, and with Bash.
  out="$(jq -nc --arg f "$E_D/.claude/approvals.jsonl" '{tool_name:"Write", tool_input:{file_path:$f, content:"{}"}}' | e_hook config-guard.sh 2>&1)"; rc=$?
  [ "$rc" -eq 2 ] || { echo "config-guard let the Write tool write .claude/approvals.jsonl (rc=$rc)"; return 1; }
  out="$(jq -nc --arg d "$E_D" '{tool_name:"Bash", cwd:$d, tool_input:{command:"printf %s x >> .claude/approvals.jsonl"}}' | e_hook config-guard.sh 2>&1)"; rc=$?
  [ "$rc" -eq 2 ] || { echo "config-guard let a Bash append to .claude/approvals.jsonl through (rc=$rc)"; return 1; }
  out="$(jq -nc --arg d "$E_D" '{tool_name:"Bash", cwd:$d, tool_input:{command:"bash .claude/framework/hooks/record-approval.sh < forged.json"}}' | e_hook config-guard.sh 2>&1)"; rc=$?
  [ "$rc" -eq 2 ] || { echo "config-guard let the agent run record-approval.sh itself (rc=$rc)"; return 1; }
  # The user's first reply: the question, A3 and the reason are shown to them.
  out="$(e_ups "A3" p1 | e_hook record-approval.sh 2>&1)"
  [ "$(printf '%s' "$out" | jq -r '.decision // empty' 2>/dev/null)" = block ] || { echo "reply 1 was not rendered: $out"; return 1; }
  printf '%s' "$out" | jq -r '.reason' | grep -qF -e "A3 — $FP_TEXT" || { echo "the render does not show A3's text: $out"; return 1; }
  printf '%s' "$out" | jq -r '.reason' | grep -qF -e "$REASON_FP" || { echo "the render does not show the reason: $out"; return 1; }
  # The second reply is the pick. The close binds a pick only when its picked_at
  # is LATER than the row's timestamp (`# BL-320-AUDIT-AFTER`), and both are whole
  # seconds in the same format. A user answers seconds after the row is raised; a
  # fast runner can raise it and record this pick in the same second, which reads
  # as a pick made before the row, and the row stays PENDING (PR #481's CI, run
  # 39040137718). So wait, at most 15s, until that stamp has moved on.
  e_t0="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; e_n=0
  while [ "$(date -u +%Y-%m-%dT%H:%M:%SZ)" = "$e_t0" ] && [ "$e_n" -lt 75 ]; do sleep 0.2; e_n=$((e_n + 1)); done   # BL-277-E1-LATER-SECOND
  out="$(e_ups "A3" p2 | e_hook record-approval.sh 2>&1)"
  [ ! -e "$(sentinel "$E_D")" ] || { echo "the pick did not remove the question: $out"; return 1; }
  jq -e 'select(.event == "approval") | .pick == "A3" and .source == "pick"' "$E_D/.claude/approvals.jsonl" >/dev/null 2>&1 \
    || { echo "no A3 pick record: $out"; return 1; }
  run_pa "$pa" "$E_D" --resolve
  [ "$(q "$E_D" '.[0].user_response')" = "false_positive" ] && [ "$(q "$E_D" '.[0].details.false_positive_reason')" = "$REASON_FP" ] \
    || { echo "the row after the pick: $(q "$E_D" '.[0] | [.user_response, .details.false_positive_reason] | join(" / ")')"; return 1; }
  return 0
}

# R5 — the roster sourced and run on one fixture in each mode. Greenfield must
# register the PostToolUse detector (else adoption's absence proves nothing);
# adoption must not, and must still register the Stop arm.
roster_counts() {
  local roster="$1" mode="$2" d
  d="$(newtmp)"
  ( cd "$d" && . "$roster" && mkdir -p .claude && soif_claude_settings_json typescript > .claude/settings.json \
      && soif_register_hook_roster .claude/settings.json "$mode" ) >/dev/null 2>&1 || { printf 'ERR ERR'; return; }
  printf '%s %s' \
    "$(jq -r '[.hooks.PostToolUse[]? | .hooks[]? | select((.command // "") | contains("bypass-detector.sh"))] | length' "$d/.claude/settings.json" 2>/dev/null || printf 'ERR')" \
    "$(jq -r '[.hooks.Stop[]? | .hooks[]? | select((.command // "") | contains("bypass-detector.sh"))] | length' "$d/.claude/settings.json" 2>/dev/null || printf 'ERR')"
}
chk_adoption_no_post() {
  local roster="$1" init adopt
  init="$(roster_counts "$roster" init)"; adopt="$(roster_counts "$roster" adoption)"
  [ "$init" = "1 1" ] || { echo "greenfield registered PostToolUse/Stop detectors '$init', want '1 1'"; return 1; }
  [ "$adopt" = "0 1" ] || { echo "adoption registered PostToolUse/Stop detectors '$adopt', want '0 1'"; return 1; }
  return 0
}

# R6 — the roster sourced and run TWICE in greenfield mode on the settings
# template. The second run reaches the idempotence probe that a second init.sh
# never can (it refuses an existing directory). Exactly one detector, under
# matcher Bash|Write|Edit|MultiEdit (`## BL-336:`) and in no other group; Stop
# once; the tool tracker and the commit recorder still unscoped, so only the
# detector moved.
MATCHER="Bash|Write|Edit|MultiEdit"
chk_roster_scoped() {
  local roster="$1" d s det scoped other stop trk rec
  d="$(newtmp)"; s="$d/.claude/settings.json"
  ( cd "$d" && . "$roster" && mkdir -p .claude && soif_claude_settings_json typescript > .claude/settings.json \
      && soif_register_hook_roster .claude/settings.json init && soif_register_hook_roster .claude/settings.json init ) >/dev/null 2>&1 \
    || { echo "the roster did not run twice"; return 1; }
  det='.hooks[]? | select((.command // "") | contains("bypass-detector.sh"))'
  scoped="$(jq -r --arg m "$MATCHER" "[.hooks.PostToolUse[]? | select(.matcher == \$m) | $det] | length" "$s" 2>/dev/null || printf 'ERR')"
  other="$(jq -r --arg m "$MATCHER" "[.hooks.PostToolUse[]? | select((.matcher // \"\") != \$m) | $det] | length" "$s" 2>/dev/null || printf 'ERR')"
  stop="$(jq -r "[.hooks.Stop[]? | $det] | length" "$s" 2>/dev/null || printf 'ERR')"
  trk="$(jq -r '[.hooks.PostToolUse[]? | select(has("matcher") | not) | .hooks[]? | select((.command // "") | contains("track-tool-usage.sh"))] | length' "$s" 2>/dev/null || printf 'ERR')"
  rec="$(jq -r '[.hooks.PostToolUse[]? | select(has("matcher") | not) | .hooks[]? | select((.command // "") | contains("record-claude-commit.sh"))] | length' "$s" 2>/dev/null || printf 'ERR')"
  [ "$scoped" = "1" ] && [ "$other" = "0" ] \
    || { echo "detector under matcher $MATCHER=$scoped, elsewhere=$other, want 1 and 0"; return 1; }
  [ "$stop" = "1" ] || { echo "Stop detector registrations=$stop, want 1"; return 1; }
  [ "$trk" = "1" ] && [ "$rec" = "1" ] || { echo "unscoped tracker=$trk recorder=$rec, want 1 and 1"; return 1; }
  return 0
}

# ============================================================================
echo "=== A — PostToolUse: recorded, not attributed, not blocking ==="
if why="$(chk_post_not_claude "$HOOK")"; then pass "A1 — each of the six patterns in tool output writes its row, and none is attributed to claude"
else fail_ "A1" "$why"; fi
if why="$(chk_post_no_sentinel "$HOOK")"; then pass "A2 — none of the six raises a sentinel from tool output"
else fail_ "A2" "$why"; fi
if why="$(chk_post_not_pending "$HOOK")"; then pass "A3 — a tool-output row awaits no decision: user_response n/a, final_outcome recorded_only"
else fail_ "A3" "$why"; fi
if why="$(chk_post_bash_shape "$HOOK")"; then pass "A4 — a real Bash result, every key present and the text on stdout, records actor tool_output and raises nothing"
else fail_ "A4" "$why"; fi

# A5 — T1's contract, restated here so this suite fails with it: the exact T1
# envelope still writes exactly one claude_bypass_proposal row. Holds on main.
p="$(newtmp)"; mk_proj "$p"
run_hook "$HOOK" "$p" "$(jq -nc --arg t "alternatively, run git commit $FLAG_NV" \
  '{hook_event_name:"PostToolUse", tool_input:{command:"echo x"}, tool_response:{output:$t}}')"
if [ "$(q "$p" '[.[] | select(.type=="claude_bypass_proposal")] | length')" = "1" ]; then
  pass "A5 (control) — T1's envelope still writes exactly one claude_bypass_proposal row: output scanning is intact"
else
  fail_ "A5" "T1's envelope wrote $(q "$p" 'length') row(s), want 1"
fi

# A6 — control: clean output writes nothing at all.
p="$(newtmp)"; mk_proj "$p"
run_hook "$HOOK" "$p" "$(env_post stdout "file1 file2 total 2")"
if [ "$(q "$p" 'length')" = "0" ] && [ ! -e "$(sentinel "$p")" ]; then
  pass "A6 (control) — clean tool output writes no row and no sentinel"
else
  fail_ "A6" "clean output wrote $(q "$p" 'length') row(s)"
fi

if why="$(chk_other_tools "$HOOK")"; then pass "A7 — an Agent report and a Grep content result are scanned and recorded as tool_output, n/a, with no sentinel"
else fail_ "A7" "$why"; fi

echo "=== W — PostToolUse from Write: the model wrote the file ==="
if why="$(chk_write_authored "$HOOK")"; then pass "W1 — a Write result, created or overwritten, writes one claude row, PENDING, and raises the sentinel"
else fail_ "W1" "$why"; fi
if why="$(chk_write_input_only "$HOOK")"; then pass "W2 — a Write whose result carries no content is scanned from tool_input.content: one claude row, PENDING, the sentinel"
else fail_ "W2" "$why"; fi

echo "=== B — PostToolUse from Edit and MultiEdit (BL-336) ==="
if why="$(chk_edit_authored "$HOOK")"; then pass "B1 — an Edit whose new_string carries a bypass proposal writes one claude row, PENDING, and raises the sentinel"
else fail_ "B1" "$why"; fi
if why="$(chk_multiedit_authored "$HOOK")"; then pass "B2 — a MultiEdit whose second edit's new_string carries it writes one claude row, PENDING, and raises the sentinel"
else fail_ "B2" "$why"; fi
if why="$(chk_edit_unrelated "$HOOK")"; then pass "B3 — an Edit and a MultiEdit that rewrite unrelated text record nothing, though old_string and the file's old contents carry a proposal"
else fail_ "B3" "$why"; fi

echo "=== S — Stop: authored, attributed, blocking ==="
if why="$(chk_stop_claude_row "$HOOK")"; then pass "S1 — an authored match writes one claude row, PENDING"
else fail_ "S1" "$why"; fi
if why="$(chk_stop_sentinel "$HOOK")"; then pass "S2 — an authored match raises a schema-valid sentinel"
else fail_ "S2" "$why"; fi
if why="$(chk_gate_no_fp_pointer "$HOOK")"; then pass "S3 — the question the gate relays to the model names no false-positive close"
else fail_ "S3" "$why"; fi

echo "=== L — the ledger read back ==="
if why="$(chk_ledger_self_read "$HOOK")"; then pass "L1 — reading the ledger twice as tool output is scanned and mints no claude row"
else fail_ "L1" "$why"; fi

echo "=== K — the shipped CLAUDE.md template ==="
if why="$(chk_template_read "$HOOK")"; then pass "K1 — the whole shipped template as tool output: matched, no claude row, no sentinel"
else fail_ "K1" "$why"; fi

echo "=== G — the pre-commit gate ==="
r="$(newtmp)/repo"
if ! mk_repo "$r"; then fail_ "G1 setup" "could not build the fixture repo"
else
  run_gate "$GATE" "$r" "git commit $FLAG_NV -m wip"
  if denied && reason_has "bypasses security hooks"; then
    pass "G1 (control) — a real verify-skipping commit is denied by the gate, with its own reason"
  else
    fail_ "G1" "the verify-skipping commit was not denied (rc=$GATE_RC)"
  fi
fi
if why="$(chk_gate_after_tool_output "$HOOK")"; then pass "G2 — a ledger holding only tool-output rows does not block a commit"
else fail_ "G2" "$why"; fi
if why="$(chk_gate_after_authored "$HOOK")"; then pass "G3 (control) — an authored match still blocks the commit through the sentinel"
else fail_ "G3" "$why"; fi

echo "=== D — closing a sentinel as a false positive ==="
p="$(newtmp)"
run_tty "$p" "" bash -c '[ -t 0 ]'; p0_tty="$TTY_RC"
( cd "$p" && bash -c '[ -t 0 ]' </dev/null ); p0_pipe=$?
if [ "$p0_tty" = "0" ] && [ "$p0_pipe" -ne 0 ]; then
  pass "P0 (control) — the operator's side has a terminal on stdin and the agent's side has none"
else
  fail_ "P0" "terminal on stdin: operator side rc=$p0_tty (want 0), agent side rc=$p0_pipe (want non-zero); D1, D2 and D5 prove nothing"
fi
if why="$(chk_fp_closes "$PA")"; then pass "D1 — the operator's --decision false-positive asks again with A3 and the reason and closes nothing; the user's A3 pick then closes the row as false_positive, recorded_only, with the reason"
else fail_ "D1" "$why"; fi
if why="$(chk_fp_refuses_empty_reason "$PA")"; then pass "D2 — a missing, empty, blank, tab-only or newline-only reason is refused: non-zero, the question and the row unmoved"
else fail_ "D2" "$why"; fi
if why="$(chk_fp_needs_terminal "$PA")"; then pass "D5 — with no terminal on stdin a well-formed false-positive close is refused: non-zero, nothing asked, the row unmoved"
else fail_ "D5" "$why"; fi
if why="$(chk_fp_operator_declines "$PA")"; then pass "D7 — the operator answers no, or presses Enter, at the confirmation: cancelled, rc 0, nothing asked, the row unmoved"
else fail_ "D7" "$why"; fi
if why="$(chk_fp_needs_pick_route "$PA")"; then pass "D10 — below the Guardrails minimum, or with no readable version, the operator's close is refused: no pick can be recorded, so nothing is asked"
else fail_ "D10" "$why"; fi
if why="$(chk_fp_no_pick_no_close "$PA")"; then pass "D16 — asked again and no pick: --resolve withdraws the question and the row stays PENDING (past the terminal check is a question, not a close)"
else fail_ "D16" "$why"; fi
if why="$(chk_fp_pick_needs_reason "$PA")"; then pass "D11 — an A3 pick on a question with no reason the user was shown (none, or whitespace) closes nothing"
else fail_ "D11" "$why"; fi
if why="$(chk_fp_other_question "$PA")"; then pass "D13 — a commit question open: the operator's close is refused and the commit question untouched"
else fail_ "D13" "$why"; fi
if why="$(chk_fp_nothing_pending "$PA")"; then pass "D14 — nothing PENDING: refused, and no question written"
else fail_ "D14" "$why"; fi
if why="$(chk_fp_later_proposal "$PA")"; then pass "D15 — a proposal raised while the operator's question is open is not bound to it: A3 closes only the earlier one"
else fail_ "D15" "$why"; fi
SM="$(stub_mirror)"
if [ -z "$SM" ] || [ -e "$SM/scripts/lib/helpers-core.sh" ]; then fail_ "D8 setup" "could not build a stub install"
elif why="$(chk_fp_stub_refuses "$SM/scripts/pending-approval.sh")"; then pass "D8 — on a stub install (no helpers-core.sh) the operator's close is refused, naming the missing file: non-zero, nothing asked, the row unmoved"
else fail_ "D8" "$why"; fi
if why="$(chk_lib_no_false_positive "$LIB")"; then pass "D17 — an agent's direct bypass_audit_close_pending ... false-positive, with any reason, is refused and the row stays PENDING (R-454-1)"
else fail_ "D17" "$why"; fi
if why="$(chk_a3_other_question "$PA")"; then pass "D20 — an A3 pick whose question is not a bypass question closes nothing"
else fail_ "D20" "$why"; fi
if why="$(chk_a3_approves_commit "$PA")"; then pass "D21 — an A3 pick on an option that approves a commit closes nothing"
else fail_ "D21" "$why"; fi
if why="$(chk_a3_before_row "$PA")"; then pass "D22 — an A3 pick made before the row was raised (a replay onto a rebound row) closes nothing"
else fail_ "D22" "$why"; fi
if why="$(chk_fp_closes_two "$PA")"; then pass "D1b — two patterns PENDING: the operator's question names both and the A3 pick closes both"
else fail_ "D1b" "$why"; fi
if why="$(chk_fp_named_only "$PA")"; then pass "D18 — an A3 question naming only no_verify closes the no_verify row and leaves the force_push row PENDING"
else fail_ "D18" "$why"; fi
if why="$(chk_fp_reconciles_first "$PA")"; then pass "D19 — a re-ask after the user's A2 and before --resolve reads that A2 first: declined, and nothing is asked"
else fail_ "D19" "$why"; fi
if why="$(chk_lib_refuses_unknown "$LIB")"; then pass "D6 — bypass_audit_close_pending refuses an unknown decision given with a reason, and closes nothing"
else fail_ "D6" "$why"; fi
if why="$(chk_close_scope "$LIB")"; then pass "D9 — accept and decline each close only the PENDING proposal rows; tool_output and escalation rows are byte-identical"
else fail_ "D9" "$why"; fi
if why="$(chk_decline_still_declines "$PA")"; then pass "D3 — decline and accept record what they did before, and write no false_positive_reason"
else fail_ "D3" "$why"; fi

echo "=== E — against the real Development Guardrails hooks ==="
why="$(chk_fp_real_guardrails "$PA")"; rc=$?
case "$rc" in
  0)  pass "E1 — the real Guardrails: config-guard refuses the agent's writes to .claude/approvals.jsonl and its own run of record-approval.sh; the user is shown A3 and the reason, picks it, and --resolve closes the row as false_positive" ;;
  77) echo "  [SKIP] E1 — no SOIF_TEST_CDF_FIXTURE and no Guardrails clone fit to copy: $CDF_FIXTURE_WHY"; SKIPPED=$((SKIPPED + 1)) ;;
  *)  fail_ "E1" "$why" ;;
esac

echo "=== X — malformed hook input ==="
x_fail=""
for shape in not-json unknown-event string-response empty-stdin; do
  p="$(newtmp)"; mk_proj "$p"
  sum_before="$(cksum < "$(ledger "$p")")"
  case "$shape" in
    not-json)        run_hook "$HOOK" "$p" 'this is { not json >>> ' ;;
    unknown-event)   run_hook "$HOOK" "$p" "$(jq -nc --arg t "$(fixture_for no_verify)" '{hook_event_name:"SomethingNew", last_assistant_message:$t}')" ;;
    string-response) run_hook "$HOOK" "$p" "$(jq -nc --arg t "$(fixture_for no_verify)" '{hook_event_name:"PostToolUse", tool_response:$t}')" ;;
    empty-stdin)     run_hook "$HOOK" "$p" "" ;;
  esac
  if [ "$HOOK_RC" -ne 0 ] || [ "$(cksum < "$(ledger "$p")")" != "$sum_before" ] || [ -e "$(sentinel "$p")" ]; then
    x_fail="$shape (rc=$HOOK_RC)"; break
  fi
done
if [ -z "$x_fail" ]; then pass "X1 (control) — non-JSON, an unknown event, a string tool_response and empty stdin all exit 0 and write nothing"
else fail_ "X1" "$x_fail"; fi

echo "=== R — the hook roster, sourced ==="
if why="$(chk_adoption_no_post "$ROSTER")"; then pass "R5 (control) — adoption mode still registers no PostToolUse detector, greenfield does, both keep Stop"
else fail_ "R5" "$why"; fi
if why="$(chk_roster_scoped "$ROSTER")"; then pass "R6 — the roster run twice: one detector, under matcher Bash|Write|Edit|MultiEdit and nowhere else; Stop once; tracker and recorder unscoped"
else fail_ "R6" "$why"; fi

echo "=== M — markers and mutants ==="
# Each marker must be present exactly once in its file.
for spec in \
  "$HOOK|# BL-277-AUTHORSHIP" \
  "$HOOK|# BL-277-SENTINEL-AUTHORED" \
  "$HOOK|# BL-336-EDIT-TEXT" \
  "$HOOK|# BL-336-MULTIEDIT-TEXT" \
  "$HOOK|# BL-336-AUTHORED-TOOLS" \
  "$LIB|# BL-277-FALSE-POSITIVE" \
  "$LIB|# BL-277-FP-RECORD" \
  "$PA|# BL-277-FP-REASON" \
  "$PA|# BL-277-FP-PASS" \
  "$PA|# BL-277-FP-OPERATOR" \
  "$PA|# BL-277-FP-CONFIRM" \
  "$PA|# BL-277-FP-STUB" \
  "$PA|# BL-277-FP-DISPATCH" \
  "$PA|# BL-277-FP-ROUTE" \
  "$PA|# BL-277-FP-PENDING-ROWS" \
  "$PA|# BL-277-FP-OTHER-QUESTION" \
  "$PA|# BL-277-FP-QUESTION" \
  "$PA|# BL-277-FP-BIND" \
  "$LIB|# BL-277-FP-PICK-MAP" \
  "$LIB|# BL-277-FP-PICK-WHY" \
  "$LIB|# BL-277-FP-PICK-END" \
  "$LIB|# BL-277-FP-REBIND" \
  "$LIB|# BL-277-FP-PICK-NAMED" \
  "$PA|# BL-277-FP-RECONCILE" \
  "$HOOK|# BL-277-WRITE-TEXT" \
  "$ROSTER|# BL-277-MATCHER"; do
  f="${spec%%|*}"; m="${spec#*|}"
  n="$(S="$m" awk 'index($0, ENVIRON["S"]){c++} END{print c+0}' "$f")"
  if [ "$n" = "1" ]; then pass "M0 — '$m' occurs once in $(basename "$f")"
  else fail_ "M0" "'$m' occurs $n times in $(basename "$f"), want 1"; fi
done

# mutate <file> <marker> <operative> <replacement> <max-distance>
# Proves the location: the operative line is the ONLY line containing the
# operative text, and it sits within <max-distance> lines AFTER the marker.
# Proves the landing: the operative text is gone, the replacement text is
# present exactly once and was absent before, exactly one line changed, and
# the file still parses. Prints the reason and returns 1 otherwise, so a
# mutant that cannot be applied is a SETUP failure and never a kill.
#
# Text reaches awk through ENVIRON, never through -v: -v applies backslash
# escapes, so an operative containing \" would be searched for as " and the
# mutant would silently miss or mangle. That is the quoting trap this helper
# exists to make impossible.
count_lit() { S="$2" awk 'index($0, ENVIRON["S"]){c++} END{print c+0}' "$1"; }
lines_lit() { S="$2" awk 'index($0, ENVIRON["S"]){print NR}' "$1"; }
mutate() {
  local f="$1" marker="$2" op="$3" rep="$4" maxd="$5" ml ol n_op n_rep_before n_rep_after removed added landed
  ml="$(lines_lit "$f" "$marker" | head -1)"
  [ -n "$ml" ] || { echo "marker '$marker' not found"; return 1; }
  n_op="$(count_lit "$f" "$op")"
  [ "$n_op" = "1" ] || { echo "operative text occurs $n_op times, want exactly 1"; return 1; }
  ol="$(lines_lit "$f" "$op")"
  [ "$ol" -gt "$ml" ] && [ $((ol - ml)) -le "$maxd" ] || { echo "operative line is $((ol - ml)) lines from the marker, want 1..$maxd"; return 1; }
  n_rep_before="$(count_lit "$f" "$rep")"
  MUT_BEFORE="$(newtmp)/before"; cp "$f" "$MUT_BEFORE" || { echo "could not snapshot"; return 1; }
  OP="$op" REP="$rep" awk '{ i = index($0, ENVIRON["OP"]); if (i) print substr($0, 1, i - 1) ENVIRON["REP"] substr($0, i + length(ENVIRON["OP"])); else print }' \
    "$MUT_BEFORE" > "$f" || { echo "awk failed"; return 1; }
  n_op="$(count_lit "$f" "$op")"
  n_rep_after="$(count_lit "$f" "$rep")"
  landed="$(sed -n "${ol}p" "$f" | S="$rep" awk 'index($0, ENVIRON["S"]){print "yes"}')"
  removed="$(diff "$MUT_BEFORE" "$f" | grep -c '^<')"; added="$(diff "$MUT_BEFORE" "$f" | grep -c '^>')"
  [ "$n_op" = "0" ] && [ "$n_rep_after" = "$((n_rep_before + 1))" ] && [ "$landed" = "yes" ] && [ "$removed" = "1" ] && [ "$added" = "1" ] \
    || { echo "did not land cleanly (operative left=$n_op, replacement $n_rep_before->$n_rep_after, on the operative line=${landed:-no}, removed=$removed, added=$added)"; return 1; }
  bash -n "$f" 2>/dev/null || { echo "the mutated file does not parse"; return 1; }
  return 0
}

# M1 — PostToolUse rows attributed to claude again. Killed by A1 (also A4, K1, L1).
MD="$(mirror_scripts)"; MH="$MD/scripts/hooks/bypass-detector.sh"
if why="$(mutate "$MH" "# BL-277-AUTHORSHIP" 'ACTOR="tool_output"' 'ACTOR="claude"' 6)"; then
  if chk_post_not_claude "$MH" >/dev/null 2>&1; then fail_ "M1 (MUTATION)" "attributing tool output to claude changed nothing — A1 is not pinning the actor"
  elif ! chk_stop_claude_row "$MH" >/dev/null 2>&1; then fail_ "M1 (MUTATION)" "the mutant broke the Stop path too, so the kill proves nothing about A1"
  else pass "M1 (MUTATION) — ACTOR=\"claude\" on the PostToolUse path: A1 kills it, S1 survives"; fi
else fail_ "M1 setup" "$why"; fi

# M2 — PostToolUse rows left PENDING. Killed by A3.
MD="$(mirror_scripts)"; MH="$MD/scripts/hooks/bypass-detector.sh"
if why="$(mutate "$MH" "# BL-277-AUTHORSHIP" 'USER_RESPONSE="n/a"' 'USER_RESPONSE="PENDING"' 6)"; then
  if chk_post_not_pending "$MH" >/dev/null 2>&1; then fail_ "M2 (MUTATION)" "PENDING tool-output rows changed nothing — A3 is not pinning user_response"
  elif ! chk_post_not_claude "$MH" >/dev/null 2>&1; then fail_ "M2 (MUTATION)" "the mutant broke attribution too, so the kill proves nothing about A3"
  else pass "M2 (MUTATION) — USER_RESPONSE=\"PENDING\" on the PostToolUse path: A3 kills it, A1 survives"; fi
else fail_ "M2 setup" "$why"; fi

# M3 — the sentinel raised regardless of authorship (the shipped behaviour). Killed by A2 and G2.
MD="$(mirror_scripts)"; MH="$MD/scripts/hooks/bypass-detector.sh"
if why="$(mutate "$MH" "# BL-277-SENTINEL-AUTHORED" '[ "$ACTOR" = "claude" ] || RAISE_PATTERN=""' '[ "$ACTOR" = "claude" ] || true' 8)"; then
  if chk_post_no_sentinel "$MH" >/dev/null 2>&1 || chk_gate_after_tool_output "$MH" >/dev/null 2>&1; then
    fail_ "M3 (MUTATION)" "raising the sentinel from tool output survived A2 or G2"
  elif ! chk_post_not_claude "$MH" >/dev/null 2>&1; then fail_ "M3 (MUTATION)" "the mutant broke attribution too, so the kill proves nothing about the sentinel"
  else pass "M3 (MUTATION) — the authorship gate removed from the sentinel: A2 and G2 kill it, A1 survives"; fi
else fail_ "M3 setup" "$why"; fi

# M3b — the sentinel never raised. Killed by S2 and G3, which is what makes them controls rather than decoration.
MD="$(mirror_scripts)"; MH="$MD/scripts/hooks/bypass-detector.sh"
if why="$(mutate "$MH" "# BL-277-SENTINEL-AUTHORED" 'elif [ -n "$RAISE_PATTERN" ]; then' 'elif false; then' 30)"; then
  if chk_stop_sentinel "$MH" >/dev/null 2>&1 || chk_gate_after_authored "$MH" >/dev/null 2>&1; then
    fail_ "M3b (MUTATION)" "never raising the sentinel survived S2 or G3"
  elif ! chk_stop_claude_row "$MH" >/dev/null 2>&1; then fail_ "M3b (MUTATION)" "the mutant broke the Stop row too, so the kill proves nothing about the sentinel"
  else pass "M3b (MUTATION) — the sentinel never raised: S2 and G3 kill it, S1 survives"; fi
else fail_ "M3b setup" "$why"; fi

# M6 — the script accepts a blank reason and deletes the sentinel before the library refuses. Killed by D2.
MD="$(mirror_scripts)"; MP="$MD/scripts/pending-approval.sh"
if why="$(mutate "$MP" "# BL-277-FP-REASON" 'if [ -z "${reason//[[:space:]]/}" ]; then' 'if false; then' 6)"; then
  if chk_fp_refuses_empty_reason "$MP" >/dev/null 2>&1; then fail_ "M6 (MUTATION)" "the script taking a blank reason survived D2"
  elif ! chk_fp_closes "$MP" >/dev/null 2>&1; then fail_ "M6 (MUTATION)" "the mutant broke the valid close too, so the kill proves nothing about D2"
  else pass "M6 (MUTATION) — the script's reason guard removed: D2 kills it, D1 survives"; fi
else fail_ "M6 setup" "$why"; fi

# roster_mutant <id> <operative> <replacement> <max-distance> <case-kill-msg>
# — copy the roster, apply one mutant at # BL-277-MATCHER, and require R6 to
# fail on it while R5 still passes (so the kill is R6's, not a broken roster).
roster_mutant() {
  local id="$1" op="$2" rep="$3" maxd="$4" msg="$5" mi why
  mi="$(newtmp)/claude-settings.sh"
  if ! cp "$ROSTER" "$mi"; then fail_ "$id setup" "could not copy the roster"; return; fi
  if ! why="$(mutate "$mi" "# BL-277-MATCHER" "$op" "$rep" "$maxd")"; then fail_ "$id setup" "$why"; return; fi
  if chk_roster_scoped "$mi" >/dev/null 2>&1; then fail_ "$id (MUTATION)" "$msg survived R6"
  elif ! chk_adoption_no_post "$mi" >/dev/null 2>&1; then fail_ "$id (MUTATION)" "the mutant broke R5 too, so the kill proves nothing about R6"
  else pass "$id (MUTATION) — $msg: R6 kills it, R5 survives"; fi
}
REG='.hooks.PostToolUse += [{"matcher": "Bash|Write|Edit|MultiEdit", "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/bypass-detector.sh"}]}]'
# M7 — the group written without its matcher: the detector runs after every tool.
roster_mutant M7 "$REG" '.hooks.PostToolUse += [{"hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/bypass-detector.sh"}]}]' 5 "the registration written without its matcher"
# M8 — the idempotence probe regressed to group [0]: with the detector in its
# own later group the second run never finds it and registers it twice.
roster_mutant M8 \
  ".hooks.PostToolUse[]? | .hooks[]? | select(.command | contains(\"bypass-detector.sh\"))" \
  ".hooks.PostToolUse[0].hooks[]? | select(.command | contains(\"bypass-detector.sh\"))" 4 \
  "the idempotence probe regressed to group [0]"
# M10 — the matcher widened back over Read, Edit and Write.
roster_mutant M10 "$REG" '.hooks.PostToolUse += [{"matcher": "Bash|Read|Write|Edit|MultiEdit", "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/bypass-detector.sh"}]}]' 5 "the matcher widened to Bash|Read|Write|Edit|MultiEdit"
# M40 — the matcher narrowed back to Bash|Write: an Edit or a MultiEdit never
# reaches the detector (`## BL-336:`).
roster_mutant M40 "$REG" '.hooks.PostToolUse += [{"matcher": "Bash|Write", "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/bypass-detector.sh"}]}]' 5 "the matcher narrowed to Bash|Write"
# M12 — the matcher narrowed back to Bash: files the model writes go unscanned
# (the maintainer's ruling on PR #454).
roster_mutant M12 "$REG" '.hooks.PostToolUse += [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/bypass-detector.sh"}]}]' 5 "the matcher narrowed to Bash"

# M11 — Write results no longer authored: a proposal written into a file leaves
# a tool_output row and no sentinel. Killed by W1; S1 and A1 survive.
MD="$(mirror_scripts)"; MH="$MD/scripts/hooks/bypass-detector.sh"
if why="$(mutate "$MH" "# BL-277-AUTHORSHIP" 'if [ "$EVENT" = "Stop" ] || { [ "$EVENT" = "PostToolUse" ] && [ -n "$AUTHORED_TOOL" ]; }; then' 'if [ "$EVENT" = "Stop" ]; then' 12)"; then
  if chk_write_authored "$MH" >/dev/null 2>&1; then fail_ "M11 (MUTATION)" "Write results recorded as tool output survived W1"
  elif ! chk_stop_claude_row "$MH" >/dev/null 2>&1 || ! chk_post_not_claude "$MH" >/dev/null 2>&1; then fail_ "M11 (MUTATION)" "the mutant broke S1 or A1 too, so the kill proves nothing about W1"
  else pass "M11 (MUTATION) — Write no longer authored: W1 kills it, S1 and A1 survive"; fi
else fail_ "M11 setup" "$why"; fi

# bd_mutant <id> <marker> <operative> <replacement> <max-distance> <killer> <survivor> <what>
# — one `## BL-336:` detector mutant on a fresh mirror: <killer> fails on it and
# <survivor> still passes.
bd_mutant() {
  local id="$1" marker="$2" op="$3" rp="$4" maxd="$5" killer="$6" survivor="$7" what="$8" md mh why
  md="$(mirror_scripts)"; mh="$md/scripts/hooks/bypass-detector.sh"
  if ! why="$(mutate "$mh" "$marker" "$op" "$rp" "$maxd")"; then fail_ "$id setup" "$why"; return; fi
  if "$killer" "$mh" >/dev/null 2>&1; then fail_ "$id (MUTATION)" "$what survived $killer"
  elif ! "$survivor" "$mh" >/dev/null 2>&1; then fail_ "$id (MUTATION)" "the mutant broke $survivor too, so the kill proves nothing about $killer"
  else pass "$id (MUTATION) — $what: $killer kills it, $survivor survives"; fi
}
# M35 — the Edit arm reads nothing: an Edit's proposal is never scanned. Killed by B1.
bd_mutant M35 "# BL-336-EDIT-TEXT" '.tool_input.new_string // ""' '.tool_input.no_such_key // ""' 4 chk_edit_authored chk_edit_unrelated "the Edit arm reads no text"
# M36 — the Edit arm reads the file's old contents too. Killed by B3.
bd_mutant M36 "# BL-336-EDIT-TEXT" '.tool_input.new_string // ""' '.tool_input.new_string + "\n" + (.tool_response.originalFile // "")' 4 chk_edit_unrelated chk_edit_authored "the Edit arm reads originalFile"
# M37 — the MultiEdit arm reads only the first edit. Killed by B2.
bd_mutant M37 "# BL-336-MULTIEDIT-TEXT" '(.tool_input.edits // [])[]?' '(.tool_input.edits // [])[0:1][]?' 4 chk_multiedit_authored chk_edit_authored "the MultiEdit arm reads only its first edit"
# M38 — the MultiEdit arm reads the old text it replaced too. Killed by B3.
bd_mutant M38 "# BL-336-MULTIEDIT-TEXT" '| objects | .new_string | strings ]' '| objects | (.new_string, .old_string) | strings ]' 4 chk_edit_unrelated chk_multiedit_authored "the MultiEdit arm reads old_string"
# M39 — Edit and MultiEdit not authored: their rows are tool_output, with no
# sentinel. Killed by B1; W1 survives.
bd_mutant M39 "# BL-336-AUTHORED-TOOLS" 'Write|Edit|MultiEdit) AUTHORED_TOOL=1' 'Write) AUTHORED_TOOL=1' 4 chk_edit_authored chk_write_authored "Edit and MultiEdit recorded as tool output"

# M13 — the false-positive pointer put back into the relayed question. Killed by S3; S2 survives.
MD="$(mirror_scripts)"; MH="$MD/scripts/hooks/bypass-detector.sh"
if why="$(mutate "$MH" "# BL-277-SENTINEL-AUTHORED" 'A2 to decline it." \' 'A2 to decline it. Or close it: scripts/pending-approval.sh --resolve --decision false-positive --reason WHY." \' 50)"; then
  if chk_gate_no_fp_pointer "$MH" >/dev/null 2>&1; then fail_ "M13 (MUTATION)" "the pointer in the relayed question survived S3"
  elif ! chk_stop_sentinel "$MH" >/dev/null 2>&1; then fail_ "M13 (MUTATION)" "the mutant broke the sentinel too, so the kill proves nothing about S3"
  else pass "M13 (MUTATION) — the false-positive pointer back in the question: S3 kills it, S2 survives"; fi
else fail_ "M13 setup" "$why"; fi

# M14 — the maintainer's FP-RECORD mutant: the condition removed, so the reason
# lands on every closed row. Killed by D3; D1 survives.
MD="$(mirror_scripts)"; ML="$MD/scripts/lib/bypass-audit.sh"; MP="$MD/scripts/pending-approval.sh"
if why="$(mutate "$ML" "# BL-277-FP-RECORD" '(if $ur == "false_positive" then .details.false_positive_reason = $why else . end)' '.details.false_positive_reason = ($why)' 3)"; then
  if chk_decline_still_declines "$MP" >/dev/null 2>&1; then fail_ "M14 (MUTATION)" "a reason on every closed row survived D3"
  elif ! chk_fp_closes "$MP" >/dev/null 2>&1; then fail_ "M14 (MUTATION)" "the mutant broke D1 too, so the kill proves nothing about D3"
  else pass "M14 (MUTATION) — the reason written onto every closed row: D3 kills it, D1 survives"; fi
else fail_ "M14 setup" "$why"; fi

# M15 — the maintainer's FP-REASON mutant: [[:space:]] narrowed to a space, so
# a tab-only reason deletes the sentinel and the library then refuses. Killed by D2; D1 survives.
MD="$(mirror_scripts)"; MP="$MD/scripts/pending-approval.sh"
if why="$(mutate "$MP" "# BL-277-FP-REASON" 'if [ -z "${reason//[[:space:]]/}" ]; then' 'if [ -z "${reason// /}" ]; then' 6)"; then
  if chk_fp_refuses_empty_reason "$MP" >/dev/null 2>&1; then fail_ "M15 (MUTATION)" "the narrowed reason guard survived D2"
  elif ! chk_fp_closes "$MP" >/dev/null 2>&1; then fail_ "M15 (MUTATION)" "the mutant broke D1 too, so the kill proves nothing about D2"
  else pass "M15 (MUTATION) — the reason guard narrowed to spaces: D2 kills it, D1 survives"; fi
else fail_ "M15 setup" "$why"; fi

# M16 — the operator-only guard removed: the agent closes its own proposal as a
# false positive. Killed by D5; D1 survives.
MD="$(mirror_scripts)"; MP="$MD/scripts/pending-approval.sh"
if why="$(mutate "$MP" "# BL-277-FP-OPERATOR" 'if [ ! -t 0 ]; then' 'if false; then' 8)"; then
  if chk_fp_needs_terminal "$MP" >/dev/null 2>&1; then fail_ "M16 (MUTATION)" "the agent's false-positive close survived D5"
  elif ! chk_fp_closes "$MP" >/dev/null 2>&1; then fail_ "M16 (MUTATION)" "the mutant broke D1 too, so the kill proves nothing about D5"
  else pass "M16 (MUTATION) — the operator-only guard removed: D5 kills it, D1 survives"; fi
else fail_ "M16 setup" "$why"; fi

# M18 — the library's decline pattern widened to catch every decision, so a
# typo closes rows. Killed by D6; D1 survives.
MD="$(mirror_scripts)"; ML="$MD/scripts/lib/bypass-audit.sh"; MP="$MD/scripts/pending-approval.sh"
if why="$(mutate "$ML" "# BL-277-FALSE-POSITIVE" '    decline) user_resp=' '    decline|*) user_resp=' 6)"; then
  if chk_lib_refuses_unknown "$ML" >/dev/null 2>&1; then fail_ "M18 (MUTATION)" "the widened pattern survived D6"
  elif ! chk_fp_closes "$MP" >/dev/null 2>&1; then fail_ "M18 (MUTATION)" "the mutant broke D1 too, so the kill proves nothing about D6"
  else pass "M18 (MUTATION) — the library's decline pattern widened to every decision: D6 kills it, D1 survives"; fi
else fail_ "M18 setup" "$why"; fi

# M19 — the operator's confirmation removed. Killed by D7; D1 survives.
MD="$(mirror_scripts)"; MP="$MD/scripts/pending-approval.sh"
if why="$(mutate "$MP" "# BL-277-FP-CONFIRM" 'if ! prompt_yes_no ' 'if false && ! prompt_yes_no ' 3)"; then
  if chk_fp_operator_declines "$MP" >/dev/null 2>&1; then fail_ "M19 (MUTATION)" "closing without the confirmation survived D7"
  elif ! chk_fp_closes "$MP" >/dev/null 2>&1; then fail_ "M19 (MUTATION)" "the mutant broke D1 too, so the kill proves nothing about D7"
  else pass "M19 (MUTATION) — the operator's confirmation removed: D7 kills it, D1 survives"; fi
else fail_ "M19 setup" "$why"; fi

# M24 — an authored Agent arm added beside the authorship block: a subagent's
# report stamped claude and PENDING, with the sentinel. Killed by A7; S1 and W1
# survive, so the kill is the Agent arm's.
MD="$(mirror_scripts)"; MH="$MD/scripts/hooks/bypass-detector.sh"
if why="$(mutate "$MH" "# BL-277-AUTHORSHIP" 'USER_RESPONSE="n/a"' "USER_RESPONSE='n/a'; [ \"\$TOOL_NAME\" = \"Agent\" ] && { ACTOR=\"claude\"; USER_RESPONSE=\"PENDING\"; }" 6)"; then
  if chk_other_tools "$MH" >/dev/null 2>&1; then fail_ "M24 (MUTATION)" "an authored Agent arm survived A7"
  elif ! chk_stop_claude_row "$MH" >/dev/null 2>&1 || ! chk_write_authored "$MH" >/dev/null 2>&1; then fail_ "M24 (MUTATION)" "the mutant broke S1 or W1 too, so the kill proves nothing about A7"
  else pass "M24 (MUTATION) — an authored Agent arm added: A7 kills it, S1 and W1 survive"; fi
else fail_ "M24 setup" "$why"; fi

# M23 — the confirmation's default flipped to Y. Only a real Enter reaches the
# default, so D7 must fail on its Enter arm, not its "n" arm.
MD="$(mirror_scripts)"; MP="$MD/scripts/pending-approval.sh"
if why="$(mutate "$MP" "# BL-277-FP-CONFIRM" '? [y/N]" "N"; then' '? [y/N]" "Y"; then' 3)"; then
  if m23="$(chk_fp_operator_declines "$MP" 2>&1)"; then fail_ "M23 (MUTATION)" "a default of Y survived D7"
  else case "$m23" in *"$RUN_TTY_ENTER"*) pass "M23 (MUTATION) — the confirmation defaults to Y: D7's Enter arm kills it" ;;
         *) fail_ "M23 (MUTATION)" "D7 failed, but not on its Enter arm: $m23" ;; esac; fi
else fail_ "M23 setup" "$why"; fi

# M21, M22 — the close's row selection widened: tool_output
# rows (user_response n/a), or escalation rows, closed with the proposals.
# Killed by D9; D1 survives.
MD="$(mirror_scripts)"; ML="$MD/scripts/lib/bypass-audit.sh"; MP="$MD/scripts/pending-approval.sh"
if why="$(mutate "$ML" "# BL-277-FP-RECORD" '.user_response == "PENDING" then' '(.user_response == "PENDING" or .user_response == "n/a") then' 2)"; then
  if chk_close_scope "$ML" >/dev/null 2>&1; then fail_ "M21 (MUTATION)" "closing tool_output rows survived D9"
  elif ! chk_fp_closes "$MP" >/dev/null 2>&1; then fail_ "M21 (MUTATION)" "the mutant broke D1 too, so the kill proves nothing about D9"
  else pass "M21 (MUTATION) — the close widened to user_response n/a: D9 kills it, D1 survives"; fi
else fail_ "M21 setup" "$why"; fi
MD="$(mirror_scripts)"; ML="$MD/scripts/lib/bypass-audit.sh"; MP="$MD/scripts/pending-approval.sh"
if why="$(mutate "$ML" "# BL-277-FP-RECORD" 'if .type == "claude_bypass_proposal" and .user_response == "PENDING" then .user_response = $ur' 'if (.type == "claude_bypass_proposal" or .type == "escalation") and .user_response == "PENDING" then .user_response = $ur' 2)"; then
  if chk_close_scope "$ML" >/dev/null 2>&1; then fail_ "M22 (MUTATION)" "closing escalation rows survived D9"
  elif ! chk_fp_closes "$MP" >/dev/null 2>&1; then fail_ "M22 (MUTATION)" "the mutant broke D1 too, so the kill proves nothing about D9"
  else pass "M22 (MUTATION) — the close widened to escalation rows: D9 kills it, D1 survives"; fi
else fail_ "M22 setup" "$why"; fi

# M20 — the stub install's prompt_yes_no fallback removed. Killed by D8.
MD="$(stub_mirror)"; MP="$MD/scripts/pending-approval.sh"
if why="$(mutate "$MP" "# BL-277-FP-STUB" '  prompt_yes_no() {' '  _no_prompt_yes_no() {' 4)"; then
  if chk_fp_stub_refuses "$MP" >/dev/null 2>&1; then fail_ "M20 (MUTATION)" "the stub install without its fallback survived D8"
  else pass "M20 (MUTATION) — the stub install's confirmation fallback removed: D8 kills it"; fi
else fail_ "M20 setup" "$why"; fi

# fp_mutant <id> <file: lib|pa> <marker> <operative> <replacement> <max-distance> <killer> <survivor|-> <what>
# One schema-2 false-positive mutant on a fresh mirror: <killer> must fail on it
# and <survivor> (when named) must still pass, so the kill is <killer>'s.
fp_mutant() {
  local id="$1" which="$2" marker="$3" op="$4" rp="$5" maxd="$6" killer="$7" survivor="$8" what="$9" md f mp ml why
  md="$(mirror_scripts)"; mp="$md/scripts/pending-approval.sh"; ml="$md/scripts/lib/bypass-audit.sh"
  case "$which" in lib) f="$ml" ;; *) f="$mp" ;; esac
  if ! why="$(mutate "$f" "$marker" "$op" "$rp" "$maxd")"; then fail_ "$id setup" "$why"; return; fi
  if "$killer" "$mp" >/dev/null 2>&1; then fail_ "$id (MUTATION)" "$what survived $killer"
  elif [ "$survivor" != - ] && ! "$survivor" "$mp" >/dev/null 2>&1; then fail_ "$id (MUTATION)" "the mutant broke $survivor too, so the kill proves nothing about $killer"
  elif [ "$survivor" = - ]; then pass "$id (MUTATION) — $what: $killer kills it"
  else pass "$id (MUTATION) — $what: $killer kills it, $survivor survives"; fi
}
# M25 — the pick-route guard removed: on a project whose Guardrails record no
# pick, the question is asked anyway. Killed by D10.
fp_mutant M25 pa "# BL-277-FP-ROUTE" 'if [ "$route" != pick ]; then' 'if false; then' 3 chk_fp_needs_pick_route chk_fp_closes "the operator's close asks where no pick can be recorded"
# M26 — an A3 pick decides nothing. Killed by D1.
fp_mutant M26 lib "# BL-320-AUDIT-DEC" 'then "false_positive"   # BL-277-FP-PICK-MAP' 'then "PENDING"   # BL-277-FP-PICK-MAP' 1 chk_fp_closes chk_decline_still_declines "the user's A3 pick leaves the row PENDING"
# M27 — an A3 pick closes with no reason shown to the user. Killed by D11.
fp_mutant M27 lib "# BL-320-AUDIT-DEC" 'and (($why | gsub("\\s"; "")) | length) > 0' 'and true' 1 chk_fp_pick_needs_reason chk_fp_closes "an A3 pick on a question with no reason closes the row"
# M28 — the whole question recorded as the reason. Killed by D1.
fp_mutant M28 lib "# BL-320-AUDIT-AFTER" 'split($fpl) | if length > 1 then (.[1:] | join($fpl)) else "" end' 'ltrimstr("")' 1 chk_fp_closes - "the whole question read as the operator's reason"
# M29 — an A3 close recorded as abandoned. Killed by D1.
fp_mutant M29 lib "# BL-320-AUDIT-DEC" 'elif $ur == "declined" then "abandoned" else "recorded_only" end)' 'else "abandoned" end)' 12 chk_fp_closes chk_decline_still_declines "an A3 close written as final_outcome abandoned"
# M30 — the proposals not bound to the operator's question: the user's pick on
# it finds no row. Killed by D1.
fp_mutant M30 pa "# BL-277-FP-BIND" 'if ! bypass_audit_rebind_pending "$project_root" "$sha"; then' 'if false; then' 3 chk_fp_closes chk_fp_needs_terminal "the PENDING proposals left bound to the old question"
# M31 — the operator's question labelled as the detector's own: a proposal
# raised while it is open binds to it, and A3 closes that one too. Killed by D15.
fp_mutant M31 pa "# BL-277-FP-QUESTION" 'source: "bypass-false-positive"' 'source: "bypass-detector"' 8 chk_fp_later_proposal - "the operator's question labelled as the detector's"
# M32 — a commit question replaced by the operator's. Killed by D13.
fp_mutant M32 pa "# BL-277-FP-OTHER-QUESTION" "if [ -f \"\$sentinel\" ] && ! jq -e '.source == \"bypass-detector\" or .source == \"bypass-false-positive\"' \"\$sentinel\" >/dev/null 2>&1; then" 'if false; then' 3 chk_fp_other_question chk_fp_closes "a commit question replaced"
# M33 — nothing PENDING, and a question is written anyway. Killed by D14.
fp_mutant M33 pa "# BL-277-FP-PENDING-ROWS" '0) print_fail "No PENDING bypass proposal in .claude/bypass-audit.json: nothing to close as a false positive. Nothing was changed."; return 1 ;;' '0) : ;;' 4 chk_fp_nothing_pending chk_fp_closes "a question asked about nothing"
# M34 — the false-positive close sent to main's --decision refusal: the
# operator can no longer ask. Killed by D1; D3 (the legacy route) survives.
fp_mutant M34 pa "# BL-277-FP-DISPATCH" 'if [ "$decision" = false-positive ]; then' 'if false; then' 3 chk_fp_closes chk_decline_still_declines "the false-positive close never dispatched"

# M41 — R-454-1's arm restored: the library closes a false positive for any
# caller. Killed by D17; D3 survives.
fp_mutant M41 lib "# BL-277-FALSE-POSITIVE" '    decline) user_resp="declined";' '    false-positive) user_resp="false_positive"; final_out="recorded_only" ;; decline) user_resp="declined";' 6 chk_lib_no_false_positive_pa chk_decline_still_declines "the library's false-positive arm restored"
# M42-M44 — R-454-2: each guard of the A3 arm dropped in turn.
fp_mutant M42 lib "# BL-320-AUDIT-DEC" 'elif $isq and $none and $after and $fp != ""' 'elif $none and $after and $fp != ""' 1 chk_a3_other_question chk_fp_closes "the A3 arm without \$isq (any question)"
fp_mutant M43 lib "# BL-320-AUDIT-DEC" 'elif $isq and $none and $after and $fp != ""' 'elif $isq and $after and $fp != ""' 1 chk_a3_approves_commit chk_fp_closes "the A3 arm without \$none (an option approving a commit)"
fp_mutant M44 lib "# BL-320-AUDIT-DEC" 'elif $isq and $none and $after and $fp != ""' 'elif $isq and $none and $fp != ""' 1 chk_a3_before_row chk_fp_closes "the A3 arm without \$after (a replayed pick)"
# M45 — X4: the operator's question names only the first pattern. Killed by D1b.
fp_mutant M45 pa "# BL-277-FP-CONFIRM" '| unique | join(", ")' '| unique | .[0:1] | join(", ")' 12 chk_fp_closes_two chk_fp_closes "the question names one pattern of two"
# M46 — C(a): the A3 arm closes rows its question does not name. Killed by D18.
fp_mutant M46 lib "# BL-320-AUDIT-DEC" '$k.t == $fp and $named and' '$k.t == $fp and true and' 1 chk_fp_named_only chk_fp_closes "the A3 arm without \$named"
# M47 — C(b): the re-ask does not read the user's pending picks first. Killed by D19.
fp_mutant M47 pa "# BL-277-FP-RECONCILE" 'if ! bypass_audit_close_from_approvals "$project_root" >/dev/null; then' 'if false; then' 4 chk_fp_reconciles_first chk_fp_closes "the re-ask without reading pending picks"
# M48 — the Write arm reads only the result. Killed by W2; W1 survives.
bd_mutant M48 "# BL-277-WRITE-TEXT" '.tool_input.content // .tool_response.content // ""' '.tool_response.content // .tool_response.no_such_key // ""' 3 chk_write_input_only chk_write_authored "the Write arm reading only tool_response.content"

# M9 — the maintainer's adoption guard lifted, so adoption registers the
# PostToolUse arm. Killed by R5.
MI="$(newtmp)/claude-settings.sh"
if ! cp "$ROSTER" "$MI"; then fail_ "M9 setup" "could not copy the roster"
elif why="$(mutate "$MI" "THE PostToolUse ARM IS GREENFIELD-ONLY FOR NOW" \
       'if [ "$_mode" != "adoption" ]; then' 'if true; then' 4)"; then
  if chk_adoption_no_post "$MI" >/dev/null 2>&1; then fail_ "M9 (MUTATION)" "the lifted guard survived R5"
  else pass "M9 (MUTATION) — the adoption guard lifted: R5 kills it"; fi
else fail_ "M9 setup" "$why"; fi

echo ""
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ] && exit 0
exit 1
