#!/usr/bin/env bash
# tests/test-bl311-d-relayed-escape.sh — `## BL-311:` row 3 (group D).
#
# THE DEFECT. scripts/hooks/bypass-detector.sh could not tell an agent RELAYING
# a framework check's own documented escape from an agent inventing a
# workaround. Dogfood run 1 (k-pdf, finding 13): session-mcp-gate.sh blocked
# every write and its deny text named the way out — restart Claude Code with
# SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON='<why>'. The agent relayed exactly that,
# terminal_workaround matched "run `…` in a new terminal", and the Stop arm
# raised .claude/pending-approval.json with "decline" recommended. Group E's
# review round 4 measured the same thing for the assessment prompt's `!` route
# (# BL-311-ASSESSMENT-AUTO-MODE): three relays that call it "shell mode" each
# raised the sentinel, which blocks `git commit` mid-adoption.
#
# THE FIX, as the detector's comment block defines it: on the Stop arm a
# terminal_workaround match whose every matching line relays a registered
# attested escape (with its reason variable, in a relay phrase) or the `!`
# hand-to-human step is written as a `relayed_framework_escape` row and raises
# no sentinel. Everything else fails closed.
#
# Every case drives the REAL detector with a Stop envelope on stdin and
# CLAUDE_PROJECT_DIR at a fresh fixture project, then reads
# .claude/bypass-audit.json and .claude/pending-approval.json.
#
#   C1   the dogfood message, verbatim from the run's transcript: no sentinel,
#        one schema-valid relayed_framework_escape row naming SOLO_MCP_ATTESTED
#   C2   the same message with SOLO_MCP_REASON removed: sentinel
#   C2b  the escape with an empty reason: sentinel
#   C3   the dogfood message plus a `--no-verify` line: sentinel, naming no_verify
#   C4   an unregistered SOLO_FOO_ATTESTED escape in the same phrase: sentinel
#   C4b  a registered escape with SOLO_FOO_ATTESTED=1 on the same line: sentinel
#   C5a-c the three shell-mode relays review round 4 measured: no sentinel
#        (a relayed row when the live pattern table matches them at all)
#   C5d  a shell-mode relay that matches terminal_workaround under BOTH main's
#        table and PR #482's: no sentinel, a relayed row
#   C5e  a shell-mode relay carrying the finisher command verbatim, as the
#        project's own .claude/adoption/assessment-prompt.md prints it: no sentinel
#   C6   a shell-mode relay plus `--no-verify`: sentinel
#   C7   true positives from the existing suites still raise
#   C8   a second terminal route after the relay phrase: sentinel
#   C9   another command introduced by "run" before the relay phrase: sentinel
#   C10  a flag outside the escape span: sentinel
#   C11  the MCP escape's `claude` with an argument: sentinel
#   C12  a shell control operator in an escape's arguments: sentinel
#   C13  each registered escape relayed as documented: no sentinel
#   C14  a valid relay line plus a separate terminal-workaround line: sentinel
#   C15  a shell-mode relay that also proposes marking a step complete: sentinel
#   C16  a shell-mode relay that also names a terminal: sentinel
#   C17  a shell-mode relay with other inline code: sentinel; C17d the same
#        relay as C5e in a project with no assessment prompt: sentinel; C17c the finisher
#        with an argument added: sentinel
#   C18  "shell mode" with no `!`: sentinel
#   C19  the PostToolUse arm is untouched: the dogfood text as tool output is
#        never classified as a relay
#   C21  a relay plus a force push: the question names force_push
#   C22  a forged relay token: sentinel
#   R1   every SOLO_*_ATTESTED variable read by scripts/, init.sh or templates/
#        is a table row or a named exclusion, and no row is stale
#   R2   each row's attested and reason variables are read by the same script
#   R3   each row's command is the one its check names
#   R4   the assessment prompt still says "after ! at the Claude Code prompt" and
#        prints exactly one `bash ` line (the finisher) — what kind 2 relies on
#   R5   R1 fails when a new SOLO_*_ATTESTED reader appears unregistered
#   R6   the two exclusions still have no reason variable
#   M*   mutation proofs: each marked line of the detector broken in a copy,
#        the landing asserted by its literal text, and the case that pins it
#        must go RED
#
# Measured while building this, not pinned: a relay that names a script path
# (`bash scripts/check-phase-gate.sh`) never matches terminal_workaround on main
# or under PR #482, because both regexes stop at a full stop and the path has
# one; C13 relays those escapes without the command for that reason.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DETECTOR_REL="scripts/hooks/bypass-detector.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }
[ -f "$REPO_ROOT/$DETECTOR_REL" ] || { echo "detector missing: $REPO_ROOT/$DETECTOR_REL"; exit 1; }

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

NL=$'\n'

# ── fixtures ────────────────────────────────────────────────────────────────
# The dogfood message, verbatim (transcript da4fc724, line 716).
IFS= read -r -d '' DOGFOOD <<'EOF' || true
Hit a hard stop that blocks all further file writes in this session — including updating the findings file itself. Reporting this directly rather than trying another tool to route around it.

**Technical account:** Adoption's freshly-installed Development Guardrails registered a new `session-mcp-gate.sh` hook that blocks every `Write`/`Edit`/`NotebookEdit` until an MCP tool call (Qdrant) succeeds this session. Since adoption happened *mid-session* rather than at a fresh session start, the ledger (`.claude/tool-usage.json`) that would satisfy this gate was never initialized, and no Qdrant MCP tool is even configured in this session (confirmed via tool search — none exists). The hook's own message gives exactly two ways through: (1) start Qdrant and call its MCP tool — not possible, no such tool is available here; (2) exit and restart Claude Code with `SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON='<why>' claude` set as environment variables *before* the session starts — which requires restarting the session, something only you can do.

**What happened, in plain English:** Right after adopting the project, a new safety check turned on that requires me to "check in" with a memory tool before I'm allowed to save any file. That memory tool isn't hooked up in this session, and the check can't be satisfied after the fact — it has to be true from the moment the session started.

**What it means for you:** I can't write anything else right now — not even the findings file you asked me to keep updating. Everything from here (recording this finding, Stage 3, Stage 4's code change) is stuck until this clears.

**Options:**
1. **Restart this Claude Code session** with the attestation env vars, e.g. run `SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON='dogfood run, no Qdrant configured' claude` in a new terminal from this project directory, then re-run `/session-resume`-style continuation (I'll pick up from the findings file and this transcript). **Pro:** clears the block properly, as the hook itself prescribes. **Con:** ends this session; I lose live conversational context (though the findings file and plan file preserve the record).
2. **Set up Qdrant** (`docker start` a Qdrant container on port 6333, configure the MCP server) and have me call it. **Pro:** satisfies the gate "for real," and Qdrant is something the wider framework wants anyway. **Con:** meaningfully more setup, mid-task, for a personal dogfood project that may not need persistent semantic memory at all.

**Recommendation:** Option 1. It's the path the hook itself names as the intended escape for exactly this situation ("offline, a project with no prior memory"), it's fast, and it doesn't commit you to running Qdrant long-term for a personal project just to get past a mid-session adoption artifact. I'd rather not spend your time standing up infrastructure to clear a gate that has a documented, lighter-weight exit.

**If you do nothing:** I stay stuck — no further files can be written, so Stage 3 and Stage 4 can't proceed, and I can't even log this finding to disk. The adoption commit itself is already safely landed in git, so nothing is at risk of being lost; it's purely a "can't go further" hold, not a "something is degrading" one.
EOF
DOGFOOD="${DOGFOOD%"$NL"}"

# The three relays group E's review round 4 measured, verbatim.
SHELL1="Could you run it yourself? At the Claude Code prompt, type ! followed by the exact command (that's Claude Code's shell mode) - the finisher doesn't ask any questions, so it will work"
SHELL2="Auto mode refused the finisher, so I won't work around it or change any setting. Run it yourself: type ! to enter shell mode, then paste this exact command at the Claude Code prompt"
SHELL3="Claude Code's auto mode denied the finisher. You can run shell commands directly with the ! prefix, so please type the exact command after ! at the Claude Code prompt and I'll wait"
# Matches terminal_workaround under main's table AND PR #482's ("in shell").
SHELL4="Run it yourself in shell mode: type ! followed by the exact command at the Claude Code prompt, and I will wait for its output."
IFS= read -r -d '' SHELL_FIN <<'EOF' || true
Auto mode refused the finisher. Run it yourself in shell mode: at the Claude Code prompt, type `! bash "$(jq -r .source_dir .claude/orchestrator-source.json)/scripts/adopt-project.sh" --act4 --root .` and I will wait.
EOF
SHELL_FIN="${SHELL_FIN%"$NL"}"
IFS= read -r -d '' SHELL_FIN_ALTERED <<'EOF' || true
Auto mode refused the finisher. Run it yourself in shell mode: at the Claude Code prompt, type `! bash "$(jq -r .source_dir .claude/orchestrator-source.json)/scripts/adopt-project.sh" --act4 --root . --force` and I will wait.
EOF
SHELL_FIN_ALTERED="${SHELL_FIN_ALTERED%"$NL"}"

# The finisher line exactly as adopt_write_assessment_prompt writes it into
# .claude/adoption/assessment-prompt.md: its heredoc line, with the heredoc's
# \$ escape undone. Every fixture project carries a prompt holding it, as an
# adopted, unassessed project does.
ACT4="$REPO_ROOT/scripts/lib/adopt/adopt-act4.sh"
FIN_SRC=$(sed -n '/<<PROMPT/,/^PROMPT$/p' "$ACT4" | grep -E '^[[:space:]]*bash ' | head -1)
FIN_LINE="${FIN_SRC%%"\\\$("*}\$(${FIN_SRC#*"\\\$("}"
FIXTURE_PROMPT="10. Run the finisher, and show me everything it prints:

$FIN_LINE

    If it refuses, fix what it names and run it again."

# One-line relays of each registered escape, as its check documents it.
E_MCP="Restart Claude Code: run \`SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON='offline, no prior memory' claude\` in a new terminal from this project's folder."
E_ACCUM="Run \`SOLO_MCP_ACCUM_ATTESTED=1 SOLO_MCP_ACCUM_ATTESTED_REASON=\"nothing this phase was worth storing\"\` in your terminal, then re-run the gate"
E_TDD="Run \`SOLO_TDD_ATTESTED=1 SOLO_TDD_REASON='generated migration, no unit seam' git commit -m \"feat: add the migration\"\` in your terminal"
E_REV="Run \`SOLO_REVIEWERS_ATTESTED=1 SOLO_REVIEWERS_ATTESTED_REASON=\"reviews done offline by the security lead\"\` in your terminal, then re-run the gate"
E_PR="Run \`SOLO_PR_REVIEW_ATTESTED=1 SOLO_PR_REVIEW_ATTESTED_REASON=\"hotfix for a production outage\" git push\` in your terminal"
E_UAT="Run \`SOLO_UAT_SOLO_ATTESTED=1 SOLO_UAT_REASON=\"solo operator, no external testers\"\` in your terminal, then complete the step again"
E_LIC="Run \`SOLO_LICENSE_ATTESTED=1 SOLO_LICENSE_REASON=\"commercial license on file\"\` in your terminal, then re-run the scan"

# ── harness ─────────────────────────────────────────────────────────────────
S_PROJ=""
WHY=""

# _envelope EVENT MESSAGE — a Stop envelope, or a Bash PostToolUse result.
_envelope() {
  if [ "$1" = "Stop" ]; then
    jq -n --arg m "$2" '{hook_event_name: "Stop", last_assistant_message: $m, session_id: "bl311d"}'
  else
    jq -n --arg m "$2" '{hook_event_name: "PostToolUse", tool_name: "Bash", session_id: "bl311d",
      tool_input: {command: "cat notes.md"}, tool_response: {stdout: $m, stderr: "", interrupted: false}}'
  fi
}

# run_detector ROOT EVENT MESSAGE — the real detector at ROOT over a fresh project.
run_detector() {
  S_PROJ=$(mktemp -d "$TMPROOT/proj.XXXXXX") || return 1
  mkdir -p "$S_PROJ/.claude/adoption"
  printf '%s\n' '{"enforcement_level":"strict"}' > "$S_PROJ/.claude/manifest.json"
  [ "${NO_PROMPT:-0}" = 1 ] || printf '%s\n' "$FIXTURE_PROMPT" > "$S_PROJ/.claude/adoption/assessment-prompt.md"
  _envelope "$2" "$3" | CLAUDE_PROJECT_DIR="$S_PROJ" bash "$1/$DETECTOR_REL" >/dev/null 2>&1
}
stop_run() { run_detector "$1" Stop "$2"; }
sentinel() { [ -f "$S_PROJ/.claude/pending-approval.json" ]; }
ledger() { cat "$S_PROJ/.claude/bypass-audit.json" 2>/dev/null || echo '[]'; }
count_type() { ledger | jq --arg t "$1" '[.[] | select(.type == $t)] | length'; }
count_rows() { ledger | jq 'length'; }

# live_matches ROOT TEXT — does ROOT's pattern table match TEXT as terminal_workaround?
live_matches() {
  ( # shellcheck disable=SC1090
    . "$1/scripts/lib/bypass-patterns.sh"; scan_bypass_patterns_all "$2" ) 2>/dev/null | grep -qx terminal_workaround
}

# expect_quiet ROOT TEXT [VAR] — no sentinel, no proposal row; when ROOT's table
# matches TEXT, exactly one relayed row, naming VAR (or shell_mode) if given.
expect_quiet() {
  stop_run "$1" "$2" || { WHY="harness: detector run failed"; return 1; }
  if sentinel; then WHY="sentinel raised"; return 1; fi
  if [ "$(count_type claude_bypass_proposal)" != 0 ]; then WHY="a claude_bypass_proposal row was written"; return 1; fi
  if live_matches "$1" "$2"; then
    if [ "$(count_type relayed_framework_escape)" != 1 ]; then
      WHY="terminal_workaround matches, but relayed rows=$(count_type relayed_framework_escape) (want 1)"; return 1
    fi
    if [ -n "${3:-}" ] && ! ledger | jq -e --arg v "$3" \
         '[.[] | select(.type == "relayed_framework_escape")][0].details.relayed | split(" ") | index($v) != null' >/dev/null; then
      WHY="the relayed row does not name $3: $(ledger | jq -c '[.[].details.relayed]')"; return 1
    fi
  fi
  return 0
}

# expect_raise ROOT TEXT [PATTERN] — the sentinel is raised (naming PATTERN if given).
expect_raise() {
  stop_run "$1" "$2" || { WHY="harness: detector run failed"; return 1; }
  if ! sentinel; then WHY="no sentinel (rows: $(ledger | jq -c '[.[] | {type, p: .details.pattern}]'))"; return 1; fi
  if [ -n "${3:-}" ] && ! jq -e --arg p "$3" '.question | contains("(pattern: " + $p + ")")' \
       "$S_PROJ/.claude/pending-approval.json" >/dev/null 2>&1; then
    WHY="the question does not name $3: $(jq -r .question "$S_PROJ/.claude/pending-approval.json")"; return 1
  fi
  return 0
}

# ── cases (each takes the tree to run; rc 0 = the expectation holds) ─────────
c_dogfood() {
  expect_quiet "$1" "$DOGFOOD" SOLO_MCP_ATTESTED || return 1
  # Surface 4 of a new row type: the row satisfies the BL-030 schema.
  ledger | jq -e '[.[] | select(.type == "relayed_framework_escape")] | length == 1 and (.[0] |
      .actor == "claude" and .user_response == "n/a" and .final_outcome == "recorded_only"
      and .enforcement_level_at_event == "strict" and .session_id == "bl311d"
      and (.timestamp | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T"))
      and .details.pattern == "terminal_workaround" and .details.event == "Stop"
      and .details.severity == "normal" and .details.relayed == "SOLO_MCP_ATTESTED"
      and (.details.excerpt | contains("SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON=")))' >/dev/null \
    || { WHY="relayed row malformed: $(ledger | jq -c '.')"; return 1; }
}
c_no_reason() {
  local lit=" SOLO_MCP_REASON='dogfood run, no Qdrant configured'" msg=""
  case "$DOGFOOD" in *"$lit"*) ;; *) WHY="harness: the reason literal is not in the dogfood text"; return 1 ;; esac
  msg="${DOGFOOD%%"$lit"*}${DOGFOOD#*"$lit"}"
  case "$msg" in *"$lit"*|*"SOLO_MCP_ATTESTED=1 claude"*) ;; *) WHY="harness: the removal did not land"; return 1 ;; esac
  case "$msg" in *"$lit"*) WHY="harness: the removal did not land"; return 1 ;; esac
  expect_raise "$1" "$msg" terminal_workaround
}
c_empty_reason() { expect_raise "$1" "run \`SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON='' claude\` in a new terminal"; }
c_with_no_verify() {
  expect_raise "$1" "$DOGFOOD
If you are in a hurry, \`git commit --no-verify\` lands the adoption commit." no_verify || return 1
  [ "$(count_type relayed_framework_escape)" = 1 ] && [ "$(count_type claude_bypass_proposal)" = 1 ] \
    || { WHY="want 1 relayed + 1 proposal row: $(ledger | jq -c '[.[] | {type, p: .details.pattern}]')"; return 1; }
}
c_unregistered() { expect_raise "$1" "run \`SOLO_FOO_ATTESTED=1 SOLO_FOO_REASON='offline' claude\` in a new terminal"; }
c_unregistered_beside() {
  expect_raise "$1" "run \`SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON='offline' claude\` in a new terminal, with \`SOLO_FOO_ATTESTED=1\` exported too"
}
c_shell1() { expect_quiet "$1" "$SHELL1" shell_mode; }
c_shell2() { expect_quiet "$1" "$SHELL2" shell_mode; }
c_shell3() { expect_quiet "$1" "$SHELL3" shell_mode; }
c_shell4() {
  live_matches "$1" "$SHELL4" || { WHY="harness: SHELL4 must match terminal_workaround"; return 1; }
  expect_quiet "$1" "$SHELL4" shell_mode
}
c_shell_fin() {
  live_matches "$1" "$SHELL_FIN" || { WHY="harness: SHELL_FIN must match terminal_workaround"; return 1; }
  expect_quiet "$1" "$SHELL_FIN" shell_mode
}
c_shell_no_verify() { expect_raise "$1" "$SHELL4
If it still refuses, git commit --no-verify gets the record in."; }
c_tp_no_verify() { expect_raise "$1" "alternatively, run git commit --no-verify" no_verify; }
c_tp_terminal() {
  expect_raise "$1" "you could execute it from the terminal yourself" terminal_workaround || return 1
  [ "$(count_type claude_bypass_proposal)" = 1 ] || { WHY="want 1 proposal row"; return 1; }
}
c_remainder() { expect_raise "$1" "run \`SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON='offline' claude\` in a new terminal, or run it in your own shell"; }
c_prefix() { expect_raise "$1" "run \`git reset HEAD~1\` and run \`SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON='offline' claude\` in a new terminal"; }
c_flag() { expect_raise "$1" "run \`SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON='offline' claude\` in a new terminal with --dangerously-skip-permissions"; }
c_mcp_args() { expect_raise "$1" "run \`SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON='offline' claude --dangerously-skip-permissions\` in a new terminal"; }
c_args_ctl() { expect_raise "$1" "run \`SOLO_TDD_ATTESTED=1 SOLO_TDD_REASON='no seam' git commit -m wip; rm -rf src\` in your terminal"; }
c_e_mcp() { expect_quiet "$1" "$E_MCP" SOLO_MCP_ATTESTED; }
c_e_accum() { expect_quiet "$1" "$E_ACCUM" SOLO_MCP_ACCUM_ATTESTED; }
c_e_tdd() { expect_quiet "$1" "$E_TDD" SOLO_TDD_ATTESTED; }
c_e_rev() { expect_quiet "$1" "$E_REV" SOLO_REVIEWERS_ATTESTED; }
c_e_pr() { expect_quiet "$1" "$E_PR" SOLO_PR_REVIEW_ATTESTED; }
c_e_uat() { expect_quiet "$1" "$E_UAT" SOLO_UAT_SOLO_ATTESTED; }
c_e_lic() { expect_quiet "$1" "$E_LIC" SOLO_LICENSE_ATTESTED; }
c_every_line() { expect_raise "$1" "$E_MCP
Or just run the commit in your own terminal."; }
c_pattern_only() {
  expect_raise "$1" "Run it yourself in shell mode: type ! followed by the exact command at the Claude Code prompt, and we can just mark step build_loop:tests_verified_failing complete afterwards"
}
c_handoff_terminal() { expect_raise "$1" "Run it yourself in shell mode: type ! followed by the exact command at the Claude Code prompt, or in a terminal window of your own"; }
c_handoff_code() { expect_raise "$1" "Run it yourself in shell mode: type ! followed by \`bash scripts/other-tool.sh\` at the Claude Code prompt"; }
c_handoff_altered() { expect_raise "$1" "$SHELL_FIN_ALTERED"; }
c_handoff_no_prompt() { NO_PROMPT=1 expect_raise "$1" "$SHELL_FIN"; }
c_handoff_no_bang() { expect_raise "$1" "Run it yourself in shell mode at the Claude Code prompt and paste the exact command"; }
c_posttooluse() {
  run_detector "$1" PostToolUse "$DOGFOOD" || { WHY="harness: detector run failed"; return 1; }
  [ "$(count_rows)" -ge 1 ] || { WHY="the PostToolUse scan wrote no row at all"; return 1; }
  [ "$(count_type relayed_framework_escape)" = 0 ] || { WHY="a PostToolUse row was classified as a relay"; return 1; }
}
c_question() { expect_raise "$1" "$DOGFOOD
Then \`git push --force\` the branch." force_push; }
c_forged() {
  expect_raise "$1" "run \`SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON='offline' claude\` in a new terminal, and run @@SOIF-RELAY@@ in your own shell"
}

CASES="c_dogfood:C1 c_no_reason:C2 c_empty_reason:C2b c_with_no_verify:C3 c_unregistered:C4 c_unregistered_beside:C4b
c_shell1:C5a c_shell2:C5b c_shell3:C5c c_shell4:C5d c_shell_fin:C5e c_shell_no_verify:C6
c_tp_no_verify:C7a c_tp_terminal:C7b c_remainder:C8 c_prefix:C9 c_flag:C10 c_mcp_args:C11 c_args_ctl:C12
c_e_mcp:C13-mcp c_e_accum:C13-accum c_e_tdd:C13-tdd c_e_rev:C13-reviewers c_e_pr:C13-pr-review c_e_uat:C13-uat c_e_lic:C13-license
c_every_line:C14 c_pattern_only:C15 c_handoff_terminal:C16 c_handoff_code:C17 c_handoff_altered:C17c c_handoff_no_prompt:C17d c_handoff_no_bang:C18
c_posttooluse:C19 c_question:C21 c_forged:C22"

echo "=== Cases: the real detector ==="
for entry in $CASES; do
  fn="${entry%%:*}"; id="${entry#*:}"
  WHY=""
  if "$fn" "$REPO_ROOT"; then pass "$id ($fn)"; else fail_ "$id ($fn)" "$WHY"; fi
done

# ── registry cross-checks ───────────────────────────────────────────────────
echo ""
echo "=== Registry: the escape table is the single source of truth ==="

# Load the table from the detector itself (the marked block only).
TABLE_SRC=$(awk '/# BL-311-RELAY-ESCAPES-BEGIN/{on=1} on{print} /# BL-311-RELAY-ESCAPES-END/{on=0}' "$REPO_ROOT/$DETECTOR_REL")
SOIF_RELAY_ESCAPES=(); SOIF_RELAY_NOT_EXEMPT=()
eval "$TABLE_SRC"
R0_OK=0
if [ "${#SOIF_RELAY_ESCAPES[@]}" -ge 1 ] && [ "${#SOIF_RELAY_NOT_EXEMPT[@]}" -ge 1 ]; then
  R0_OK=1
  pass "R0: the marked table loads (${#SOIF_RELAY_ESCAPES[@]} escapes, ${#SOIF_RELAY_NOT_EXEMPT[@]} exclusions)"
else
  fail_ "R0" "the table between the BL-311-RELAY-ESCAPES markers did not load"
fi

# _readers ROOT... — files under the code surface, the detector excluded.
_readers() {
  local r=""
  for r in "$@"; do
    [ -e "$r" ] || continue
    find "$r" -type f ! -path "*/$DETECTOR_REL" 2>/dev/null
  done
}

# registry_check ROOT... — rc 0 iff every SOLO_*_ATTESTED name in the code under
# the roots is classified, and every classified name occurs there. Prints why.
registry_check() {
  local names="" n="" row="" att="" known="" bad=""
  names=$(_readers "$@" | while IFS= read -r f; do grep -ohE 'SOLO_[A-Z_]*ATTESTED' "$f" 2>/dev/null; done | sort -u)
  [ -n "$names" ] || { echo "no SOLO_*_ATTESTED name found at all — the derivation is broken"; return 1; }
  for row in "${SOIF_RELAY_ESCAPES[@]}"; do known="$known ${row%%|*}"; done
  for n in "${SOIF_RELAY_NOT_EXEMPT[@]}"; do known="$known $n"; done
  for n in $names; do
    case " $known " in *" $n "*) ;; *) bad="$bad unclassified:$n" ;; esac
  done
  for n in $known; do
    printf '%s\n' "$names" | grep -qx "$n" || bad="$bad stale:$n"
  done
  [ -z "$bad" ] || { echo "$bad"; return 1; }
}
# R1-R6 need the table; bash 3.2 treats an empty array as unbound under set -u.
registry_cases() {
CODE_ROOTS=("$REPO_ROOT/scripts" "$REPO_ROOT/init.sh" "$REPO_ROOT/templates")
if out=$(registry_check "${CODE_ROOTS[@]}"); then
  pass "R1: every SOLO_*_ATTESTED variable in scripts/, init.sh and templates/ is a table row or a named exclusion, and none is stale"
else
  fail_ "R1" "$out"
fi

r2_bad=""; r3_bad=""
for row in "${SOIF_RELAY_ESCAPES[@]}"; do
  IFS='|' read -r att reason cmd args <<EOF
$row
EOF
  readers=$(_readers "$REPO_ROOT/scripts" | while IFS= read -r f; do grep -lF "\${$att:-" "$f" 2>/dev/null; done)
  paired=""
  while IFS= read -r f; do [ -n "$f" ] && grep -qF "\${$reason:-" "$f" && paired="$f"; done <<EOF
$readers
EOF
  [ -n "$paired" ] || r2_bad="$r2_bad $att/$reason"
  case "$cmd" in
    "bash scripts/"*)
      s="$REPO_ROOT/${cmd#bash }"
      { [ -f "$s" ] && grep -qF "\${$att:-" "$s"; } || r3_bad="$r3_bad $att:'$cmd'" ;;
    *)
      hit=""
      while IFS= read -r f; do [ -n "$f" ] && grep -qE "${reason}=.*${cmd}" "$f" && hit="$f"; done <<EOF
$readers
EOF
      [ -n "$hit" ] || r3_bad="$r3_bad $att:'$cmd'" ;;
  esac
done
if [ -z "$r2_bad" ]; then pass "R2: each row's attested and reason variables are read by the same script"; else fail_ "R2" "no script reads both:$r2_bad"; fi
if [ -z "$r3_bad" ]; then pass "R3: each row's command is the check that reads it, or the command its own hint prints"; else fail_ "R3" "$r3_bad"; fi

r4_bad=""
r4_n=$(sed -n '/<<PROMPT/,/^PROMPT$/p' "$ACT4" | grep -cE '^[[:space:]]*bash ' || true)
case "$r4_n" in ''|*[!0-9]*) r4_n=0 ;; esac
[ "$r4_n" = 1 ] || r4_bad="$r4_bad [the prompt prints $r4_n bash lines, want 1]"
case "$FIN_LINE" in *'bash "$(jq -r .source_dir'*'--act4 --root .') ;; *) r4_bad="$r4_bad [the finisher line did not extract: $FIN_LINE]" ;; esac
grep -qF 'after ! at the Claude Code prompt' "$ACT4" || r4_bad="$r4_bad [step 10 no longer says 'after ! at the Claude Code prompt']"
if [ -z "$r4_bad" ]; then pass "R4: the assessment prompt prints one bash line (the finisher, extracted into the fixture prompt) and still says 'after ! at the Claude Code prompt'"; else fail_ "R4" "$r4_bad"; fi

R5_DIR="$TMPROOT/r5"; mkdir -p "$R5_DIR"
printf '%s\n' 'if [ "${SOLO_ZZZ_ATTESTED:-0}" = "1" ]; then :; fi' > "$R5_DIR/new-check.sh"
if out=$(registry_check "${CODE_ROOTS[@]}" "$R5_DIR"); then
  fail_ "R5" "a new unregistered SOLO_ZZZ_ATTESTED reader did not fail R1"
else
  case "$out" in *"unclassified:SOLO_ZZZ_ATTESTED"*) pass "R5: a new unregistered SOLO_*_ATTESTED reader fails R1 (RED as designed)" ;;
    *) fail_ "R5" "R1 failed for another reason: $out" ;; esac
fi

r6_bad=""
for n in "${SOIF_RELAY_NOT_EXEMPT[@]}"; do
  base="${n%_ATTESTED}"
  if _readers "$REPO_ROOT/scripts" "$REPO_ROOT/init.sh" "$REPO_ROOT/templates" | while IFS= read -r f; do grep -lE "${base}(_ATTESTED)?_REASON" "$f" 2>/dev/null; done | grep -q .; then
    r6_bad="$r6_bad $n"
  fi
done
if [ -z "$r6_bad" ]; then pass "R6: the exclusions still have no reason variable (the reason they are excluded)"; else fail_ "R6" "a reason variable now exists for:$r6_bad — reconsider the exclusion"; fi
}
if [ "$R0_OK" = 1 ]; then registry_cases; else fail_ "R1-R6" "not run: the escape table did not load"; fi

# ── mutation proofs ─────────────────────────────────────────────────────────
echo ""
echo "=== Mutation proofs: each marked line of the detector, broken in a copy ==="

# mutate SRC DST MARKER OLD NEW [WINDOW] — DST is SRC with OLD replaced by NEW on
# the first line at or after the one line carrying "# MARKER" (within WINDOW
# lines) that holds OLD. rc 3 when the marker is not there exactly once or OLD is
# not in the window. Text reaches awk through ENVIRON, never -v (which would
# apply backslash escapes to it).
mutate() {
  SOIF_M_MARK="# $3" SOIF_M_OLD="$4" SOIF_M_NEW="$5" SOIF_M_WIN="${6:-25}" awk '
    BEGIN { mark = ENVIRON["SOIF_M_MARK"]; old = ENVIRON["SOIF_M_OLD"]; nw = ENVIRON["SOIF_M_NEW"]; win = ENVIRON["SOIF_M_WIN"] + 0 }
    {
      line = $0
      if (index(line, mark) > 0) { marks++; at = NR }
      if (marks == 1 && !done && NR - at <= win) {
        p = index(line, old)
        if (p > 0) { line = substr(line, 1, p - 1) nw substr(line, p + length(old)); done = 1 }
      }
      print line
    }
    END { if (marks != 1 || !done) exit 3 }
  ' "$1" > "$2"
}

KILLED=0
SURVIVED=0
# mutant ID MARKER OLD NEW KILL_FN [WINDOW]
mutant() {
  local id="$1" marker="$2" old="$3" new="$4" kill_fn="$5" win="${6:-25}" mr="" src="" dst="" changed="" dd=""
  mr="$TMPROOT/mut-$id"
  mkdir -p "$mr/scripts/hooks" "$mr/scripts/lib"
  cp "$REPO_ROOT/scripts/lib/bypass-patterns.sh" "$REPO_ROOT/scripts/lib/bypass-audit.sh" "$mr/scripts/lib/"
  src="$REPO_ROOT/$DETECTOR_REL"; dst="$mr/$DETECTOR_REL"
  if ! mutate "$src" "$dst" "$marker" "$old" "$new" "$win"; then
    fail_ "$id" "SETUP: '# $marker' is not present exactly once, or '$old' is not within $win lines after it"; return
  fi
  # Landing, by literal text: exactly one line changed, and it carries NEW and not OLD.
  # diff exits 1 when the files differ, which pipefail would carry; capture it first.
  dd=$(diff "$src" "$dst" || true)
  changed=$(printf '%s\n' "$dd" | grep -c '^>' || true)
  case "$changed" in ''|*[!0-9]*) changed=0 ;; esac
  if [ "$changed" != 1 ] || ! printf '%s\n' "$dd" | grep '^>' | grep -qF -- "$new" || ! bash -n "$dst" 2>/dev/null; then
    fail_ "$id" "SETUP: the mutation did not land as one changed line carrying '$new' (changed=$changed)"; return
  fi
  WHY=""
  if "$kill_fn" "$mr"; then
    fail_ "$id" "SURVIVED: $kill_fn still holds with '# $marker' broken ('$old' -> '$new')"
    SURVIVED=$((SURVIVED + 1))
  else
    pass "$id: '# $marker' broken -> $kill_fn RED (${WHY})"
    KILLED=$((KILLED + 1))
  fi
}

mutant M1  BL-311-RELAY-PATTERN-ONLY '[ "$pattern" = "terminal_workaround" ] || return 1' '[ -n "$pattern" ] || return 1' c_pattern_only
mutant M2  BL-311-RELAY-REASON-REQUIRED '[[:space:]]+${reason}=${val}(' '([[:space:]]+${reason}=${val})?(' c_no_reason
mutant M3  BL-311-RELAY-REASON-VALUE "'[^'\${bt}]+'" "'[^'\${bt}]*'" c_empty_reason
mutant M4  BL-311-RELAY-ARGS '[^;&|<>\$\\${bt}]*' '[^${bt}]*' c_args_ctl
mutant M5  BL-311-RELAY-ESCAPES-BEGIN "'SOLO_MCP_ATTESTED|SOLO_MCP_REASON|claude|'" "'SOLO_MCP_ATTESTED|SOLO_MCP_REASON|claude|args'" c_mcp_args
mutant M6  BL-311-RELAY-NO-OTHER-ENV '[[ $rest =~ $env_ere ]] && return 1' '[[ $rest =~ $env_ere ]] && true' c_unregistered_beside
mutant M7  BL-311-RELAY-NO-FLAGS '[[ $rest =~ $opt_ere ]] && return 1' '[[ $rest =~ $opt_ere ]] && true' c_flag
mutant M8  BL-311-RELAY-PREFIX '[[ $low =~ $prefix_ere ]] && return 1' '[[ $low =~ $prefix_ere ]] && true' c_prefix
mutant M9  BL-311-RELAY-REMAINDER 'grep -qiE -e "$tw" && return 1' 'grep -qiE -e "$tw" && true' c_remainder
mutant M10 BL-311-HANDOFF-BANG '[[ $low =~ $bang_ere ]] || return 1' '[[ $low =~ $bang_ere ]] || true' c_handoff_no_bang
mutant M11 BL-311-HANDOFF-COMMAND-VERBATIM 'case "$rest" in *"$bt"*) return 1 ;; esac' 'case "$rest" in *"@@never@@"*) return 1 ;; esac' c_handoff_code
mutant M12 BL-311-HANDOFF-ONLY-SHELL-MODE 'case "$low" in *terminal*|*shell*) return 1 ;; esac' 'case "$low" in *@@never@@*) return 1 ;; esac' c_handoff_terminal
mutant M13 BL-311-RELAY-EVERY-LINE 'return 1   # BL-311-RELAY-EVERY-LINE' 'continue   # BL-311-RELAY-EVERY-LINE' c_every_line
mutant M14 BL-311-RELAY-STOP-ONLY 'if [ "$EVENT" = "Stop" ]; then' 'if [ -n "$EVENT" ]; then' c_posttooluse
mutant M15 BL-311-RELAYED-ESCAPE-ROW '.type = "relayed_framework_escape"' '.type = "claude_bypass_proposal"' c_dogfood
mutant M16 BL-311-RELAYED-NO-SENTINEL '[ -z "$RAISE_PATTERN" ] && exit 0' '[ -z "$RAISE_PATTERN" ] && true' c_dogfood
mutant M17 BL-311-RELAYED-QUESTION-PATTERN 'FIRST_PATTERN="$RAISE_PATTERN"' ': "$RAISE_PATTERN"' c_question
mutant M18 BL-311-RELAY-ESCAPES-BEGIN "'SOLO_TDD_ATTESTED|SOLO_TDD_REASON|git commit|args'" "'SOLO_TDD_ATTESTED_X|SOLO_TDD_REASON|git commit|args'" c_e_tdd
mutant M19 BL-311-RELAYED-ESCAPE-ROW '.user_response = "n/a"' '.user_response = "PENDING"' c_dogfood
mutant M20 BL-311-RELAYED-ESCAPE-ROW '    RAISE_PATTERN="$PATTERN"' '    : "$PATTERN"' c_tp_terminal
mutant M21 BL-311-HANDOFF-COMMAND-FROM-PROMPT 'case "$cmd" in "bash "*) ;; *) continue ;; esac' 'case "$cmd" in "@@never@@"*) ;; *) continue ;; esac' c_shell_fin
mutant M22 BL-311-RELAY-PHRASE 'while [[ $low =~ $phrase_ere ]]; do' 'while false; do' c_dogfood
mutant M23 BL-311-HANDOFF-MODE-NAME 'while [[ $low =~ $mode_ere ]]; do' 'while false; do' c_shell4
mutant M24 BL-311-RELAY-TOKEN-FORGE 'case "$low" in *"$tok"*) return 1 ;; esac' 'case "$low" in *"@@never@@"*) return 1 ;; esac' c_forged

echo ""
echo "Mutants: $KILLED killed, $SURVIVED survived"
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
