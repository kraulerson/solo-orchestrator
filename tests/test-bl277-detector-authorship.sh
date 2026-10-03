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
#   S*  Stop: a `claude` row, PENDING, and the sentinel, whose question does
#       not tell the model how to close it as a false positive.
#   L*  the ledger read back as tool output mints no `claude` row.
#   K*  the shipped CLAUDE.md template read as tool output.
#   G*  the pre-commit gate: the verify-skipping commit is still denied; a
#       ledger holding only tool-output rows does not block; an authored match
#       does.
#   D*  the third disposition of scripts/pending-approval.sh, which is
#       operator-only: refused without a terminal on stdin, then confirmed at a
#       [y/N] prompt, the same two steps as `test-gate.sh --unrecord-feature`
#       and `process-checklist.sh --reset`. The operator's side runs under a
#       pseudo-terminal from script(1) and types its answer; P0 proves the
#       pseudo-terminal is real, so D5's refusal is the guard's.
#   X*  malformed hook input.
#   R5  the hook roster (scripts/lib/claude-settings.sh) in adoption mode
#       still registers no PostToolUse detector: the maintainer's
#       `# BL-242-SETTINGS-BL277` guard, unchanged.
#   R6  the roster run twice in greenfield mode: one detector, under matcher
#       Bash|Write and nowhere else.
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
trap 'rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }
# mirror_scripts — a copy of scripts/ for a mutant or a stub install to change.
mirror_scripts() { local d; d="$(newtmp)/fw"; mkdir -p "$d" && cp -Rp "$REPO_ROOT/scripts" "$d/" && printf '%s' "$d"; }

for need in "$HOOK" "$GATE" "$PA" "$LIB" "$ROSTER" "$TEMPLATE"; do
  [ -f "$need" ] || { echo "  [FAIL] setup — $need not found"; echo ""; echo "Results: 0 passed, 1 failed"; exit 1; }
done
command -v jq >/dev/null 2>&1 || { echo "  [FAIL] setup — jq is required"; echo ""; echo "Results: 0 passed, 1 failed"; exit 1; }

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

mk_proj() {
  local d="$1"
  mkdir -p "$d/.claude" || return 1
  printf '%s\n' '{"frameworkVersion":"test","host":"other","mode":"personal","deployment":"personal","enforcement_level":"strict"}' \
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
seed_pending() {
  local d="$1"
  mk_proj "$d" || return 1
  jq -nc '[{timestamp:"2026-09-18T00:00:00Z", session_id:"bl277", type:"claude_bypass_proposal", actor:"claude",
            enforcement_level_at_event:"strict", details:{pattern:"no_verify", event:"Stop", excerpt:"x", severity:"normal"},
            user_response:"PENDING", final_outcome:"recorded_only"}]' > "$(ledger "$d")" || return 1
  jq -nc '{question:"bl277 q", options:["A1: yes","A2: decline"], recommendation:"A2", offered_at:"2026-09-18T00:00:00Z"}' \
    > "$(sentinel "$d")" || return 1
  return 0
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
chk_fp_closes() {
  local pa="$1" d ur fo why
  d="$(newtmp)"; seed_pending "$d" || { echo "fixture"; return 1; }
  run_pa_tty "$pa" "$d" --resolve --decision false-positive --reason "$REASON_FP"
  ur="$(q "$d" '.[0].user_response')"; fo="$(q "$d" '.[0].final_outcome')"; why="$(q "$d" '.[0].details.false_positive_reason')"
  [ "$PA_RC" = "0" ] || { echo "rc=$PA_RC, want 0"; return 1; }
  [ ! -e "$(sentinel "$d")" ] || { echo "the sentinel is still present"; return 1; }
  [ "$ur" = "false_positive" ] || { echo "user_response=$ur, want false_positive"; return 1; }
  [ "$fo" = "recorded_only" ] || { echo "final_outcome=$fo, want recorded_only"; return 1; }
  [ "$why" = "$REASON_FP" ] || { echo "the reason was not recorded on the row (got '$why')"; return 1; }
  return 0
}
# D2 runs on the operator's side, so the refusal it sees is the reason guard's
# and not the terminal guard's.
chk_fp_refuses_empty_reason() {
  local pa="$1" d shape tab nl
  tab="$(printf '\t')"; nl="
"
  for shape in missing empty blank tab newline; do
    d="$(newtmp)"; seed_pending "$d" || { echo "fixture"; return 1; }
    case "$shape" in
      missing) run_pa_tty "$pa" "$d" --resolve --decision false-positive ;;
      empty)   run_pa_tty "$pa" "$d" --resolve --decision false-positive --reason "" ;;
      blank)   run_pa_tty "$pa" "$d" --resolve --decision false-positive --reason "   " ;;
      tab)     run_pa_tty "$pa" "$d" --resolve --decision false-positive --reason "$tab" ;;
      newline) run_pa_tty "$pa" "$d" --resolve --decision false-positive --reason "$nl" ;;
    esac
    case "$PA_RC" in ''|NORUN|*[!0-9]*) echo "$shape reason: the command did not run (rc=$PA_RC)"; return 1 ;; 0) echo "$shape reason: rc=0, want a refusal"; return 1 ;; esac
    [ -f "$(sentinel "$d")" ] || { echo "$shape reason: the sentinel was removed by a refused close"; return 1; }
    [ "$(q "$d" '.[0].user_response')" = "PENDING" ] || { echo "$shape reason: the row was closed by a refused close"; return 1; }
  done
  return 0
}
# D5 — the agent's side: a well-formed close with a reason, refused because
# stdin is not a terminal. Nothing moves.
chk_fp_needs_terminal() {
  local pa="$1" d
  d="$(newtmp)"; seed_pending "$d" || { echo "fixture"; return 1; }
  run_pa "$pa" "$d" --resolve --decision false-positive --reason "$REASON_FP"
  [ "$PA_RC" -ne 0 ] || { echo "rc=0: the false-positive close ran with no terminal on stdin"; return 1; }
  [ -f "$(sentinel "$d")" ] || { echo "the sentinel was removed by a refused close"; return 1; }
  [ "$(q "$d" '.[0].user_response')" = "PENDING" ] || { echo "the row was closed by a refused close"; return 1; }
  [ "$(q "$d" '.[0].details | has("false_positive_reason")')" = "false" ] || { echo "a reason was written by a refused close"; return 1; }
  return 0
}
# D8 — a stub install (no scripts/lib/helpers-core.sh, the fallback at the top
# of the script): the operator's well-formed close cannot be confirmed, so it
# is refused and says why. <script> is the copy whose helpers are removed.
chk_fp_stub_refuses() {
  local pa="$1" d
  d="$(newtmp)"; seed_pending "$d" || { echo "fixture"; return 1; }
  run_pa_tty "$pa" "$d" --resolve --decision false-positive --reason "$REASON_FP"
  case "$PA_RC" in ''|NORUN|*[!0-9]*) echo "the command did not run (rc=$PA_RC)"; return 1 ;; 0) echo "rc=0, want a refusal"; return 1 ;; esac
  [ -f "$(sentinel "$d")" ] || { echo "the sentinel was removed"; return 1; }
  [ "$(q "$d" '.[0].user_response')" = "PENDING" ] || { echo "the row was closed"; return 1; }
  grep -q 'helpers-core.sh' "$TTY_OUT" 2>/dev/null || { echo "the refusal does not name helpers-core.sh"; return 1; }
  if grep -q 'command not found' "$TTY_OUT" 2>/dev/null; then echo "the script ran a command it does not define"; return 1; fi
  return 0
}
stub_mirror() { local md; md="$(mirror_scripts)" && rm -f "$md/scripts/lib/helpers-core.sh" && printf '%s' "$md"; }

# D7 — the operator's side, well-formed, but the operator answers no, or just
# presses Enter (the default is N). Cancelled as --unrecord-feature and --reset
# cancel: rc 0, nothing moves.
chk_fp_operator_declines() {
  local pa="$1" d ans
  for ans in n "$RUN_TTY_ENTER"; do
    d="$(newtmp)"; seed_pending "$d" || { echo "fixture"; return 1; }
    PA_ANSWER="$ans" run_pa_tty "$pa" "$d" --resolve --decision false-positive --reason "$REASON_FP"
    [ "$PA_RC" = "0" ] || { echo "answer '$ans': rc=$PA_RC, want 0 (cancelled)"; return 1; }
    [ -f "$(sentinel "$d")" ] || { echo "answer '$ans': the sentinel was removed"; return 1; }
    [ "$(q "$d" '.[0].user_response')" = "PENDING" ] || { echo "answer '$ans': the row was closed"; return 1; }
    [ "$(q "$d" '.[0].details | has("false_positive_reason")')" = "false" ] || { echo "answer '$ans': a reason was written"; return 1; }
  done
  return 0
}
# The library guard on its own: scripts/pending-approval.sh refuses first, so
# without this case the library's refusal is never reached by any test.
chk_lib_refuses_empty_reason() {
  local lib="$1" d rc shape why
  for shape in blank tab newline; do
    case "$shape" in blank) why="  " ;; tab) why="$(printf '\t')" ;; newline) why="
" ;; esac
    d="$(newtmp)"; seed_pending "$d" || { echo "fixture"; return 1; }
    ( . "$lib" && bypass_audit_close_pending "$d" false-positive "$why" ) >/dev/null 2>&1; rc=$?
    [ "$rc" -ne 0 ] || { echo "$shape reason: the library closed rows as false_positive"; return 1; }
    [ "$(q "$d" '.[0].user_response')" = "PENDING" ] || { echo "$shape reason: the row was closed by a refused close"; return 1; }
  done
  return 0
}
# D9 — a close changes only PENDING claude_bypass_proposal rows. The ledger
# holds the row classes this change creates (a tool_output row, user_response
# n/a) and an open escalation; under each decision, through the library, the two
# proposal rows close and every other row is byte-identical.
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
  for dec in accept decline false-positive; do
    d="$(newtmp)"; seed_mixed "$d" || { echo "fixture"; return 1; }
    before="$(jq -c '[.[1], .[2]]' "$(ledger "$d")")"
    ( . "$lib" && bypass_audit_close_pending "$d" "$dec" "$REASON_FP" ) >/dev/null 2>&1; rc=$?
    case "$dec" in accept) ur="accepted" ;; decline) ur="declined" ;; false-positive) ur="false_positive" ;; esac
    [ "$rc" -eq 0 ] || { echo "$dec: rc=$rc"; return 1; }
    [ "$(q "$d" "[.[0], .[3]] | map(.user_response) | unique | join(\",\")")" = "$ur" ] || { echo "$dec: the proposal rows are not $ur"; return 1; }
    after="$(jq -c '[.[1], .[2]]' "$(ledger "$d")")"
    [ "$before" = "$after" ] || { echo "$dec: a tool_output or escalation row changed: $after"; return 1; }
  done
  return 0
}
# D6 — the library refuses a decision it does not know, even with a reason, so
# a widened false-positive pattern cannot turn a typo into a false_positive close.
chk_lib_refuses_unknown() {
  local lib="$1" d rc
  d="$(newtmp)"; seed_pending "$d" || { echo "fixture"; return 1; }
  ( . "$lib" && bypass_audit_close_pending "$d" accpet "$REASON_FP" ) >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 0 ] || { echo "the library accepted the decision 'accpet'"; return 1; }
  [ "$(q "$d" '.[0].user_response')" = "PENDING" ] || { echo "an unknown decision closed the row as $(q "$d" '.[0].user_response')"; return 1; }
  return 0
}
# D3 — accept and decline are unchanged, and carry no false_positive_reason:
# the reason belongs to false-positive closes only. A --reason is passed so a
# close that wrote it everywhere would write text, not just an empty key.
chk_decline_still_declines() {
  local pa="$1" d dec ur fo
  for dec in decline accept; do
    d="$(newtmp)"; seed_pending "$d" || { echo "fixture"; return 1; }
    run_pa "$pa" "$d" --resolve --decision "$dec" --reason "$REASON_FP"
    case "$dec" in decline) ur="declined"; fo="abandoned" ;; accept) ur="accepted"; fo="bypassed" ;; esac
    [ "$PA_RC" -eq 0 ] && [ "$(q "$d" '.[0].user_response')" = "$ur" ] && [ "$(q "$d" '.[0].final_outcome')" = "$fo" ] \
      || { echo "$dec no longer records $ur/$fo (rc=$PA_RC)"; return 1; }
    [ "$(q "$d" '.[0].details | has("false_positive_reason")')" = "false" ] \
      || { echo "$dec wrote a false_positive_reason onto the row"; return 1; }
  done
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
# matcher Bash|Write and in no other group; Stop once; the tool tracker and the
# commit recorder still unscoped, so only the detector moved.
chk_roster_scoped() {
  local roster="$1" d s det scoped other stop trk rec
  d="$(newtmp)"; s="$d/.claude/settings.json"
  ( cd "$d" && . "$roster" && mkdir -p .claude && soif_claude_settings_json typescript > .claude/settings.json \
      && soif_register_hook_roster .claude/settings.json init && soif_register_hook_roster .claude/settings.json init ) >/dev/null 2>&1 \
    || { echo "the roster did not run twice"; return 1; }
  det='.hooks[]? | select((.command // "") | contains("bypass-detector.sh"))'
  scoped="$(jq -r "[.hooks.PostToolUse[]? | select(.matcher == \"Bash|Write\") | $det] | length" "$s" 2>/dev/null || printf 'ERR')"
  other="$(jq -r "[.hooks.PostToolUse[]? | select((.matcher // \"\") != \"Bash|Write\") | $det] | length" "$s" 2>/dev/null || printf 'ERR')"
  stop="$(jq -r "[.hooks.Stop[]? | $det] | length" "$s" 2>/dev/null || printf 'ERR')"
  trk="$(jq -r '[.hooks.PostToolUse[]? | select(has("matcher") | not) | .hooks[]? | select((.command // "") | contains("track-tool-usage.sh"))] | length' "$s" 2>/dev/null || printf 'ERR')"
  rec="$(jq -r '[.hooks.PostToolUse[]? | select(has("matcher") | not) | .hooks[]? | select((.command // "") | contains("record-claude-commit.sh"))] | length' "$s" 2>/dev/null || printf 'ERR')"
  [ "$scoped" = "1" ] && [ "$other" = "0" ] \
    || { echo "detector under matcher Bash|Write=$scoped, elsewhere=$other, want 1 and 0"; return 1; }
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
if why="$(chk_fp_closes "$PA")"; then pass "D1 — the operator's --decision false-positive closes the sentinel and records false_positive, recorded_only and the reason"
else fail_ "D1" "$why"; fi
if why="$(chk_fp_refuses_empty_reason "$PA")"; then pass "D2 — a missing, empty, blank, tab-only or newline-only reason is refused: non-zero, sentinel kept, row still PENDING"
else fail_ "D2" "$why"; fi
if why="$(chk_fp_needs_terminal "$PA")"; then pass "D5 — with no terminal on stdin a well-formed false-positive close is refused: non-zero, sentinel kept, row PENDING, no reason written"
else fail_ "D5" "$why"; fi
if why="$(chk_fp_operator_declines "$PA")"; then pass "D7 — the operator answers no, or presses Enter, at the confirmation: cancelled, rc 0, sentinel kept, row PENDING, no reason written"
else fail_ "D7" "$why"; fi
SM="$(stub_mirror)"
if [ -z "$SM" ] || [ -e "$SM/scripts/lib/helpers-core.sh" ]; then fail_ "D8 setup" "could not build a stub install"
elif why="$(chk_fp_stub_refuses "$SM/scripts/pending-approval.sh")"; then pass "D8 — on a stub install (no helpers-core.sh) the operator's close is refused, naming the missing file: non-zero, sentinel kept, row PENDING"
else fail_ "D8" "$why"; fi
if why="$(chk_lib_refuses_empty_reason "$LIB")"; then pass "D4 — bypass_audit_close_pending itself refuses a blank, tab-only or newline-only reason and closes nothing"
else fail_ "D4" "$why"; fi
if why="$(chk_lib_refuses_unknown "$LIB")"; then pass "D6 — bypass_audit_close_pending refuses an unknown decision given with a reason, and closes nothing"
else fail_ "D6" "$why"; fi
if why="$(chk_close_scope "$LIB")"; then pass "D9 — accept, decline and false-positive each close only the PENDING proposal rows; tool_output and escalation rows are byte-identical"
else fail_ "D9" "$why"; fi
if why="$(chk_decline_still_declines "$PA")"; then pass "D3 — decline and accept record what they did before, and write no false_positive_reason"
else fail_ "D3" "$why"; fi

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
if why="$(chk_roster_scoped "$ROSTER")"; then pass "R6 — the roster run twice: one detector, under matcher Bash|Write and nowhere else; Stop once; tracker and recorder unscoped"
else fail_ "R6" "$why"; fi

echo "=== M — markers and mutants ==="
# Each marker must be present exactly once in its file.
for spec in \
  "$HOOK|# BL-277-AUTHORSHIP" \
  "$HOOK|# BL-277-SENTINEL-AUTHORED" \
  "$LIB|# BL-277-FALSE-POSITIVE" \
  "$LIB|# BL-277-FP-RECORD" \
  "$PA|# BL-277-FP-REASON" \
  "$PA|# BL-277-FP-PASS" \
  "$PA|# BL-277-FP-OPERATOR" \
  "$PA|# BL-277-FP-CONFIRM" \
  "$PA|# BL-277-FP-STUB" \
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
if why="$(mutate "$MH" "# BL-277-SENTINEL-AUTHORED" 'if [ "$ACTOR" = "claude" ] && [ ! -f "$SENTINEL" ]; then' 'if [ ! -f "$SENTINEL" ]; then' 6)"; then
  if chk_post_no_sentinel "$MH" >/dev/null 2>&1 || chk_gate_after_tool_output "$MH" >/dev/null 2>&1; then
    fail_ "M3 (MUTATION)" "raising the sentinel from tool output survived A2 or G2"
  elif ! chk_post_not_claude "$MH" >/dev/null 2>&1; then fail_ "M3 (MUTATION)" "the mutant broke attribution too, so the kill proves nothing about the sentinel"
  else pass "M3 (MUTATION) — the authorship gate removed from the sentinel: A2 and G2 kill it, A1 survives"; fi
else fail_ "M3 setup" "$why"; fi

# M3b — the sentinel never raised. Killed by S2 and G3, which is what makes them controls rather than decoration.
MD="$(mirror_scripts)"; MH="$MD/scripts/hooks/bypass-detector.sh"
if why="$(mutate "$MH" "# BL-277-SENTINEL-AUTHORED" 'if [ "$ACTOR" = "claude" ] && [ ! -f "$SENTINEL" ]; then' 'if false; then' 6)"; then
  if chk_stop_sentinel "$MH" >/dev/null 2>&1 || chk_gate_after_authored "$MH" >/dev/null 2>&1; then
    fail_ "M3b (MUTATION)" "never raising the sentinel survived S2 or G3"
  elif ! chk_stop_claude_row "$MH" >/dev/null 2>&1; then fail_ "M3b (MUTATION)" "the mutant broke the Stop row too, so the kill proves nothing about the sentinel"
  else pass "M3b (MUTATION) — the sentinel never raised: S2 and G3 kill it, S1 survives"; fi
else fail_ "M3b setup" "$why"; fi

# M4 — false-positive recorded as a decline. Killed by D1.
MD="$(mirror_scripts)"; ML="$MD/scripts/lib/bypass-audit.sh"; MP="$MD/scripts/pending-approval.sh"
if why="$(mutate "$ML" "# BL-277-FALSE-POSITIVE" 'user_resp="false_positive"; final_out="recorded_only"' 'user_resp="declined"; final_out="abandoned"' 4)"; then
  if chk_fp_closes "$MP" >/dev/null 2>&1; then fail_ "M4 (MUTATION)" "recording a false positive as a decline survived D1"
  elif ! chk_decline_still_declines "$MP" >/dev/null 2>&1; then fail_ "M4 (MUTATION)" "the mutant broke decline too, so the kill proves nothing about D1"
  else pass "M4 (MUTATION) — false-positive written as declined/abandoned: D1 kills it, D3 survives"; fi
else fail_ "M4 setup" "$why"; fi

# M5 — the library accepts a blank reason. Killed by D4 (the script's own guard shields D2).
MD="$(mirror_scripts)"; ML="$MD/scripts/lib/bypass-audit.sh"
if why="$(mutate "$ML" "# BL-277-FALSE-POSITIVE" 'if [ -z "${reason//[[:space:]]/}" ]; then' 'if false; then' 5)"; then
  if chk_lib_refuses_empty_reason "$ML" >/dev/null 2>&1; then fail_ "M5 (MUTATION)" "the library taking a blank reason survived D4"
  else pass "M5 (MUTATION) — the library's reason guard removed: D4 kills it"; fi
else fail_ "M5 setup" "$why"; fi

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
REG='.hooks.PostToolUse += [{"matcher": "Bash|Write", "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/bypass-detector.sh"}]}]'
# M7 — the group written without its matcher: the detector runs after every tool.
roster_mutant M7 "$REG" '.hooks.PostToolUse += [{"hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/bypass-detector.sh"}]}]' 5 "the registration written without its matcher"
# M8 — the idempotence probe regressed to group [0]: with the detector in its
# own later group the second run never finds it and registers it twice.
roster_mutant M8 \
  ".hooks.PostToolUse[]? | .hooks[]? | select(.command | contains(\"bypass-detector.sh\"))" \
  ".hooks.PostToolUse[0].hooks[]? | select(.command | contains(\"bypass-detector.sh\"))" 4 \
  "the idempotence probe regressed to group [0]"
# M10 — the matcher widened back over Read, Edit and Write.
roster_mutant M10 "$REG" '.hooks.PostToolUse += [{"matcher": "Bash|Read|Edit|Write", "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/bypass-detector.sh"}]}]' 5 "the matcher widened to Bash|Read|Edit|Write"
# M12 — the matcher narrowed back to Bash: files the model writes go unscanned
# (the maintainer's ruling on PR #454).
roster_mutant M12 "$REG" '.hooks.PostToolUse += [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/bypass-detector.sh"}]}]' 5 "the matcher narrowed to Bash"

# M11 — Write results no longer authored: a proposal written into a file leaves
# a tool_output row and no sentinel. Killed by W1; S1 and A1 survive.
MD="$(mirror_scripts)"; MH="$MD/scripts/hooks/bypass-detector.sh"
if why="$(mutate "$MH" "# BL-277-AUTHORSHIP" 'if [ "$EVENT" = "Stop" ] || { [ "$EVENT" = "PostToolUse" ] && [ "$TOOL_NAME" = "Write" ]; }; then' 'if [ "$EVENT" = "Stop" ]; then' 10)"; then
  if chk_write_authored "$MH" >/dev/null 2>&1; then fail_ "M11 (MUTATION)" "Write results recorded as tool output survived W1"
  elif ! chk_stop_claude_row "$MH" >/dev/null 2>&1 || ! chk_post_not_claude "$MH" >/dev/null 2>&1; then fail_ "M11 (MUTATION)" "the mutant broke S1 or A1 too, so the kill proves nothing about W1"
  else pass "M11 (MUTATION) — Write no longer authored: W1 kills it, S1 and A1 survive"; fi
else fail_ "M11 setup" "$why"; fi

# M13 — the false-positive pointer put back into the relayed question. Killed by S3; S2 survives.
MD="$(mirror_scripts)"; MH="$MD/scripts/hooks/bypass-detector.sh"
if why="$(mutate "$MH" "# BL-277-SENTINEL-AUTHORED" "To decline, say 'decline' or describe what you want instead.\"" "To decline, say 'decline' or describe what you want instead. Or close it: scripts/pending-approval.sh --resolve --decision false-positive --reason WHY.\"" 8)"; then
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

# M17 — the library's reason guard narrowed to a space. Killed by D4.
MD="$(mirror_scripts)"; ML="$MD/scripts/lib/bypass-audit.sh"
if why="$(mutate "$ML" "# BL-277-FALSE-POSITIVE" 'if [ -z "${reason//[[:space:]]/}" ]; then' 'if [ -z "${reason// /}" ]; then' 5)"; then
  if chk_lib_refuses_empty_reason "$ML" >/dev/null 2>&1; then fail_ "M17 (MUTATION)" "the library's narrowed reason guard survived D4"
  else pass "M17 (MUTATION) — the library's reason guard narrowed to spaces: D4 kills it"; fi
else fail_ "M17 setup" "$why"; fi

# M18 — the library's false-positive pattern widened to catch every decision.
# Killed by D6; D1 survives.
MD="$(mirror_scripts)"; ML="$MD/scripts/lib/bypass-audit.sh"; MP="$MD/scripts/pending-approval.sh"
if why="$(mutate "$ML" "# BL-277-FALSE-POSITIVE" '    false-positive)' '    false-positive|*)' 3)"; then
  if chk_lib_refuses_unknown "$ML" >/dev/null 2>&1; then fail_ "M18 (MUTATION)" "the widened pattern survived D6"
  elif ! chk_fp_closes "$MP" >/dev/null 2>&1; then fail_ "M18 (MUTATION)" "the mutant broke D1 too, so the kill proves nothing about D6"
  else pass "M18 (MUTATION) — the library's false-positive pattern widened to every decision: D6 kills it, D1 survives"; fi
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
if why="$(mutate "$ML" "# BL-277-FP-RECORD" '.type == "claude_bypass_proposal" and' '(.type == "claude_bypass_proposal" or .type == "escalation") and' 2)"; then
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
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] && exit 0
exit 1
