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
# attested escape (with its reason variable, and only the arguments its check
# documents, in a relay phrase) or the `!` hand-to-human step (carrying nothing
# but the pinned finisher) is written as a `relayed_framework_escape` row and
# raises no sentinel. A backstop refuses any line carrying a destructive shape.
# Everything else fails closed.
#
# Every case drives the REAL detector with a Stop envelope on stdin and
# CLAUDE_PROJECT_DIR at a fresh fixture project, then reads
# .claude/bypass-audit.json and .claude/pending-approval.json.
#
#   C1   the dogfood message, verbatim from the run's transcript: no sentinel,
#        one schema-valid relayed_framework_escape row naming SOLO_MCP_ATTESTED
#   C2   the same message with SOLO_MCP_REASON removed: sentinel
#   C2b  the escape with an empty single-quoted reason: sentinel; C2c an empty
#        bare reason; C2d an empty double-quoted reason
#   C2e  a reason a shell expands — "$(…)", $(…), or a bare word carrying `;`: sentinel
#   C3   the dogfood message plus a `--no-verify` line: sentinel, naming no_verify
#   C4   an unregistered SOLO_FOO_ATTESTED escape in the same phrase: sentinel
#   C4b  a registered escape with SOLO_FOO_ATTESTED=1 on the same line: sentinel
#   C5a-c the three shell-mode relays review round 4 measured: no sentinel
#        (a relayed row when the live pattern table matches them at all)
#   C5d  a shell-mode relay that matches terminal_workaround under BOTH main's
#        table and PR #482's: no sentinel, a relayed row
#   C5e  a shell-mode relay carrying the finisher verbatim: no sentinel
#   C5f  a shell-mode relay with `!` itself as inline code: no sentinel
#   C6   a shell-mode relay plus `--no-verify`: sentinel
#   C7   true positives from the existing suites still raise
#   C8   a second terminal route after the relay phrase: sentinel
#   C9   another command introduced by "run" before the relay phrase: sentinel
#   C10  a flag outside the escape span (one the backstop does not list): sentinel;
#        C10b a single-dash flag outside it
#   C11  the MCP escape's `claude` with an argument: sentinel
#   C12  a shell control operator in an escape's arguments: sentinel
#   C13  each registered escape relayed as documented: no sentinel (and
#        `git push` with a plain remote and branch)
#   C14  a valid relay line plus a separate terminal-workaround line: sentinel
#   C15  a shell-mode relay that also proposes marking a step complete: sentinel
#   C16  a shell-mode relay that also names a terminal (C16b: a "shell window"): sentinel
#   C17  a shell-mode relay with other inline code: sentinel; C17c the finisher
#        with an argument added: sentinel; C17d the finisher relay in a project
#        with no assessment prompt: no sentinel (no project file is read);
#        C17e a command the project's own (edited) prompt prints: sentinel
#   C17f a shell-mode relay with a single-dash flag: sentinel
#   C18  "shell mode" with no `!`: sentinel; C18b no "Claude Code prompt": sentinel
#   C19  the PostToolUse arm is untouched: the dogfood text as tool output is
#        never classified as a relay
#   C21  a relay plus a force push: the question names force_push
#   C22  a forged relay token: sentinel
#   C23  REVIEW R1-1: an attested escape whose command carries what its check does
#        not document — git push --force / -f / +refspec / :refspec / --delete /
#        -d / --mirror / --prune, git commit --amend / -n / a flag other than -m /
#        anything after the message / a message a shell expands — sentinel each
#   C24  a row whose argument grammar the detector does not define relays nothing
#   C25  an empty escape table relays nothing, and prints nothing on stderr
#   L1/L2 the two layers each hold alone: every C23 probe raises with the
#        backstop disabled (the grammars alone), and every probe the backstop
#        names raises with the grammars widened to anything (the backstop alone)
#   R1   every SOLO_*_ATTESTED variable read by scripts/, init.sh or templates/
#        is a table row or a named exclusion, and no row is stale
#   R2   each row's attested and reason variables are read by the same script
#   R3   each row's command is the one its check names
#   R4   the generated assessment prompt still says "after ! at the Claude Code
#        prompt" and prints exactly one `bash ` line (the finisher)
#   R5   R1 fails when a new SOLO_*_ATTESTED reader appears unregistered
#   R6   the two exclusions still have no reason variable
#   R7   the detector's finisher pin is the SHA-256 of the finisher line the
#        module's own writer generates, and its comment carries that line
#   R8   R7 fails when the module's finisher line changes (RED as designed)
#   M*   mutation proofs: each marked line of the detector broken in a copy,
#        the landing asserted by its literal text, and the case that pins it
#        must go RED. A guard behind a second, redundant layer is broken in a
#        copy with that layer disabled — the grammars on the no-backstop tree,
#        the backstop on the widened tree — or its mutant could not die.
#
# Measured while building this, not pinned: a relay that names a script path
# (`bash scripts/check-phase-gate.sh`) never matches terminal_workaround on main
# or under PR #482, because both regexes stop at a full stop and the path has
# one; C13 relays those escapes without the command for that reason.
# Not pinned by a mutant, by design: # BL-311-RELAY-TABLE-NONEMPTY (with it
# removed, only bash 3.2 differs — an unbound-variable line on stderr — so a
# mutant would die on this Mac and survive on the runner); and the `|| continue`
# after a grammar the detector does not define (without it the span ERE is empty,
# which matches everywhere and never terminates — a hang, not a RED).
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

# sha256_of TEXT — hex SHA-256 of TEXT, by the tools the detector uses.
sha256_of() {
  { printf '%s' "$1" | sha256sum 2>/dev/null || printf '%s' "$1" | shasum -a 256 2>/dev/null; } | awk '{print $1; exit}'
}

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

# The assessment prompt, GENERATED by the module's own writer
# (adopt_write_assessment_prompt), and its finisher line. Every fixture project
# carries the generated prompt, as an adopted, unassessed project does.
ACT4="$REPO_ROOT/scripts/lib/adopt/adopt-act4.sh"
# gen_prompt ACT4_FILE ROOT — write ROOT/.claude/adoption/assessment-prompt.md with ACT4_FILE's writer.
gen_prompt() {
  mkdir -p "$2/.claude" || return 1
  printf '%s\n' '{"adoption":{"adoptedAtCommit":"0123456789abcdef0123456789abcdef01234567"}}' > "$2/.claude/manifest.json"
  ( . "$REPO_ROOT/scripts/lib/adopt/adopt-core.sh" && . "$1" && adopt_write_assessment_prompt "$2" ) >/dev/null 2>&1 || return 1
  [ -s "$2/.claude/adoption/assessment-prompt.md" ]
}
# finisher_of PROMPT_FILE — its lines that begin `bash ` once trimmed (the finisher).
finisher_of() {
  local l=""
  grep -E '^[[:space:]]*bash ' "$1" | while IFS= read -r l; do
    l="${l#"${l%%[![:space:]]*}"}"; printf '%s\n' "${l%"${l##*[![:space:]]}"}"
  done
}
GEN_ROOT="$TMPROOT/gen"
GEN_PROMPT="$GEN_ROOT/.claude/adoption/assessment-prompt.md"
gen_prompt "$ACT4" "$GEN_ROOT" || { echo "harness: the module's writer did not generate the assessment prompt"; exit 1; }
FIN_LINE=$(finisher_of "$GEN_PROMPT" | sed -n '1p')

# A prompt the session has edited: the finisher, plus two commands it added.
INJECTED_PROMPT="$TMPROOT/injected-prompt.md"
{ cat "$GEN_PROMPT"; printf '%s\n' '    bash -c "git push origin +main"' '    bash tools/release-everything'; } > "$INJECTED_PROMPT"

# One-line relays of each registered escape, as its check documents it.
E_MCP="Restart Claude Code: run \`SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON='offline, no prior memory' claude\` in a new terminal from this project's folder."
E_ACCUM="Run \`SOLO_MCP_ACCUM_ATTESTED=1 SOLO_MCP_ACCUM_ATTESTED_REASON=\"nothing this phase was worth storing\"\` in your terminal, then re-run the gate"
E_TDD="Run \`SOLO_TDD_ATTESTED=1 SOLO_TDD_REASON='generated migration, no unit seam' git commit -m \"feat: add the migration\"\` in your terminal"
E_REV="Run \`SOLO_REVIEWERS_ATTESTED=1 SOLO_REVIEWERS_ATTESTED_REASON=\"reviews done offline by the security lead\"\` in your terminal, then re-run the gate"
E_PR="Run \`SOLO_PR_REVIEW_ATTESTED=1 SOLO_PR_REVIEW_ATTESTED_REASON=\"hotfix for a production outage\" git push\` in your terminal"
E_PR_REF="Run \`SOLO_PR_REVIEW_ATTESTED=1 SOLO_PR_REVIEW_ATTESTED_REASON=\"hotfix for a production outage\" git push origin main\` in your terminal"
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

# run_detector ROOT EVENT MESSAGE — the real detector at ROOT over a fresh project
# carrying the generated prompt (PROMPT_SRC overrides it; NO_PROMPT=1 omits it).
# The detector's stderr is kept in $S_PROJ/detector.stderr.
run_detector() {
  S_PROJ=$(mktemp -d "$TMPROOT/proj.XXXXXX") || return 1
  mkdir -p "$S_PROJ/.claude/adoption"
  printf '%s\n' '{"enforcement_level":"strict"}' > "$S_PROJ/.claude/manifest.json"
  [ "${NO_PROMPT:-0}" = 1 ] || cp "${PROMPT_SRC:-$GEN_PROMPT}" "$S_PROJ/.claude/adoption/assessment-prompt.md"
  _envelope "$2" "$3" | CLAUDE_PROJECT_DIR="$S_PROJ" bash "$1/$DETECTOR_REL" >/dev/null 2>"$S_PROJ/detector.stderr"
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

# expect_tw_proposal ROOT TEXT — the terminal_workaround row is a proposal, not a
# relay. For lines another pattern raises anyway (--no-verify), where the
# sentinel alone cannot tell whether the relay rule accepted the line.
expect_tw_proposal() {
  expect_raise "$1" "$2" || return 1
  ledger | jq -e '[.[] | select(.details.pattern == "terminal_workaround")] | length == 1 and .[0].type == "claude_bypass_proposal"' >/dev/null \
    || { WHY="the terminal_workaround row is not a proposal: $(ledger | jq -c '[.[] | {type, p: .details.pattern}]')"; return 1; }
}

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

# derive SRC_TREE DST_TREE MARKER OLD NEW [WINDOW] — DST_TREE is SRC_TREE's
# detector (and its two libs) with OLD replaced by NEW near MARKER; rc 1 unless
# exactly one line changed and it carries NEW.
derive() {
  local dd="" changed=""
  mkdir -p "$2/scripts/hooks" "$2/scripts/lib" || return 1
  cp "$1/scripts/lib/bypass-patterns.sh" "$1/scripts/lib/bypass-audit.sh" "$2/scripts/lib/" || return 1
  mutate "$1/$DETECTOR_REL" "$2/$DETECTOR_REL" "$3" "$4" "$5" "${6:-25}" || return 1
  dd=$(diff "$1/$DETECTOR_REL" "$2/$DETECTOR_REL" || true)
  changed=$(printf '%s\n' "$dd" | grep -c '^>' || true)
  case "$changed" in ''|*[!0-9]*) changed=0 ;; esac
  [ "$changed" = 1 ] && printf '%s\n' "$dd" | grep '^>' | grep -qF -- "$5" && bash -n "$2/$DETECTOR_REL" 2>/dev/null
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
c_bare_empty_reason() { expect_raise "$1" "run \`SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON= claude\` in a new terminal"; }
c_dq_empty_reason() { expect_raise "$1" "run \`SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON=\"\" claude\` in a new terminal"; }
c_reason_cmdsub() { expect_raise "$1" "run \`SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON=\"\$(reboot)\" claude\` in a new terminal"; }
c_reason_bare_cmdsub() { expect_raise "$1" "run \`SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON=\$(reboot) claude\` in a new terminal"; }
c_reason_bare_semicolon() { expect_raise "$1" "run \`SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON=x;reboot; claude\` in a new terminal"; }
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
  case "$SHELL_FIN" in *"\`! $FIN_LINE\`"*) ;; *) WHY="harness: SHELL_FIN does not carry the generated finisher"; return 1 ;; esac
  expect_quiet "$1" "$SHELL_FIN" shell_mode
}
c_shell_bang_code() { expect_quiet "$1" "Run it yourself in shell mode: type \`!\` followed by the exact command at the Claude Code prompt, and I will wait." shell_mode; }
c_shell_no_verify() { expect_raise "$1" "$SHELL4
If it still refuses, git commit --no-verify gets the record in."; }
c_tp_no_verify() { expect_raise "$1" "alternatively, run git commit --no-verify" no_verify; }
c_tp_terminal() {
  expect_raise "$1" "you could execute it from the terminal yourself" terminal_workaround || return 1
  [ "$(count_type claude_bypass_proposal)" = 1 ] || { WHY="want 1 proposal row"; return 1; }
}
c_remainder() { expect_raise "$1" "run \`SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON='offline' claude\` in a new terminal, or run it in your own shell"; }
c_prefix() { expect_raise "$1" "run \`git reset HEAD~1\` and run \`SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON='offline' claude\` in a new terminal"; }
c_flag() { expect_raise "$1" "run \`SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON='offline' claude\` in a new terminal with --permission-mode bypassPermissions"; }
c_single_dash_flag() { expect_raise "$1" "run \`SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON='offline' claude\` in a new terminal, adding -f"; }
c_mcp_args() { expect_raise "$1" "run \`SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON='offline' claude --dangerously-skip-permissions\` in a new terminal"; }
c_args_ctl() { expect_raise "$1" "run \`SOLO_TDD_ATTESTED=1 SOLO_TDD_REASON='no seam' git commit -m wip; rm -rf src\` in your terminal"; }
c_e_mcp() { expect_quiet "$1" "$E_MCP" SOLO_MCP_ATTESTED; }
c_e_accum() { expect_quiet "$1" "$E_ACCUM" SOLO_MCP_ACCUM_ATTESTED; }
c_e_tdd() { expect_quiet "$1" "$E_TDD" SOLO_TDD_ATTESTED; }
c_e_rev() { expect_quiet "$1" "$E_REV" SOLO_REVIEWERS_ATTESTED; }
c_e_pr() { expect_quiet "$1" "$E_PR" SOLO_PR_REVIEW_ATTESTED; }
c_e_pr_ref() { expect_quiet "$1" "$E_PR_REF" SOLO_PR_REVIEW_ATTESTED; }
c_e_uat() { expect_quiet "$1" "$E_UAT" SOLO_UAT_SOLO_ATTESTED; }
c_e_lic() { expect_quiet "$1" "$E_LIC" SOLO_LICENSE_ATTESTED; }
c_every_line() { expect_raise "$1" "$E_MCP
Or just run the commit in your own terminal."; }
c_pattern_only() {
  expect_raise "$1" "Run it yourself in shell mode: type ! followed by the exact command at the Claude Code prompt, and we can just mark step build_loop:tests_verified_failing complete afterwards"
}
c_handoff_terminal() { expect_raise "$1" "Run it yourself in shell mode: type ! followed by the exact command at the Claude Code prompt, or in a terminal window of your own"; }
c_handoff_shell_window() { expect_raise "$1" "Run it yourself in shell mode: type ! followed by the exact command at the Claude Code prompt, or in a shell window of your own"; }
c_handoff_code() { expect_raise "$1" "Run it yourself in shell mode: type ! followed by \`bash scripts/other-tool.sh\` at the Claude Code prompt"; }
c_handoff_altered() { expect_raise "$1" "$SHELL_FIN_ALTERED"; }
c_handoff_no_prompt() { NO_PROMPT=1 expect_quiet "$1" "$SHELL_FIN" shell_mode; }
c_injected_prompt() {
  grep -qF 'bash tools/release-everything' "$INJECTED_PROMPT" || { WHY="harness: the injected prompt lacks its line"; return 1; }
  PROMPT_SRC="$INJECTED_PROMPT" expect_raise "$1" "Run it yourself in shell mode: at the Claude Code prompt, type \`! bash tools/release-everything\` and I will wait." || return 1
  PROMPT_SRC="$INJECTED_PROMPT" expect_raise "$1" "Run it yourself in shell mode: at the Claude Code prompt, type \`! bash -c \"git push origin +main\"\` and I will wait."
}
c_handoff_single_dash() { expect_raise "$1" "Run it yourself in shell mode: type ! followed by the exact command at the Claude Code prompt, with -f"; }
c_handoff_no_bang() { expect_raise "$1" "Run it yourself in shell mode at the Claude Code prompt and paste the exact command"; }
c_handoff_no_prompt_words() { expect_raise "$1" "Run it yourself in shell mode: type ! followed by the exact command, and I will wait for its output"; }
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

# C23 — review R1-1's probes, and their siblings. PR = the PR-review escape, TDD
# = the TDD escape; each must raise the sentinel.
PR_PFX="run \`SOLO_PR_REVIEW_ATTESTED=1 SOLO_PR_REVIEW_ATTESTED_REASON=\"hotfix\" git push"
TDD_PFX="run \`SOLO_TDD_ATTESTED=1 SOLO_TDD_REASON='no seam' git commit"
c_push_force()   { expect_raise "$1" "$PR_PFX origin main --force\` in your terminal"; }
c_push_f()       { expect_raise "$1" "$PR_PFX origin main -f\` in your terminal"; }
c_push_plus()    { expect_raise "$1" "$PR_PFX origin +main\` in your terminal"; }
c_push_colon()   { expect_raise "$1" "$PR_PFX origin :release\` in your terminal"; }
c_push_delete()  { expect_raise "$1" "$PR_PFX --delete origin release\` in your terminal"; }
c_push_d()       { expect_raise "$1" "$PR_PFX -d origin release\` in your terminal"; }
c_push_mirror()  { expect_raise "$1" "$PR_PFX --mirror origin\` in your terminal"; }
c_push_prune()   { expect_raise "$1" "$PR_PFX --prune origin main\` in your terminal"; }
c_commit_amend() { expect_raise "$1" "$TDD_PFX --amend --no-edit\` in your terminal"; }
c_commit_n()     { expect_raise "$1" "$TDD_PFX -m wip -n\` in your terminal"; }
c_commit_author() { expect_raise "$1" "$TDD_PFX --author 'Mallory <m@example>'\` in your terminal"; }
c_commit_trailing() { expect_raise "$1" "$TDD_PFX -m 'wip' -n\` in your terminal"; }
c_commit_cmdsub() { expect_raise "$1" "$TDD_PFX -m \"\$(reboot)\"\` in your terminal"; }
c_commit_no_verify_long() { expect_tw_proposal "$1" "$TDD_PFX -m 'wip' --no-verify\` in your terminal"; }

# C24 — derive a tree from $1 whose PR-review row names a grammar the detector
# does not define; the plain documented relay must then raise.
c_unknown_grammar() {
  local t=""
  t=$(mktemp -d "$TMPROOT/ug.XXXXXX") || return 1
  derive "$1" "$t" BL-311-RELAY-ESCAPES-BEGIN "|git push|remote-branch'" "|git push|remote-branch-undefined'" 40 \
    || { WHY="harness: the grammar rename did not land"; return 1; }
  expect_raise "$t" "$E_PR"
}
# C25 — derive a tree from $1 with no row in the escape table: nothing relays,
# and the detector says nothing on stderr.
c_empty_table() {
  local t=""
  t=$(mktemp -d "$TMPROOT/et.XXXXXX") || return 1
  mkdir -p "$t/scripts/hooks" "$t/scripts/lib"
  cp "$1/scripts/lib/bypass-patterns.sh" "$1/scripts/lib/bypass-audit.sh" "$t/scripts/lib/"
  awk '/^SOIF_RELAY_ESCAPES=\(/ { print; on = 1; next } on && /^\)/ { on = 0 } !on { print }' \
    "$1/$DETECTOR_REL" > "$t/$DETECTOR_REL"
  if grep -qE "^[[:space:]]*'SOLO_[A-Z_]*ATTESTED\|" "$t/$DETECTOR_REL" || ! bash -n "$t/$DETECTOR_REL" 2>/dev/null; then
    WHY="harness: the table was not emptied"; return 1
  fi
  expect_raise "$t" "$E_MCP" || return 1
  [ ! -s "$S_PROJ/detector.stderr" ] || { WHY="stderr: $(head -c 300 "$S_PROJ/detector.stderr")"; return 1; }
}

CASES="c_dogfood:C1 c_no_reason:C2 c_empty_reason:C2b c_bare_empty_reason:C2c c_dq_empty_reason:C2d
c_reason_cmdsub:C2e-dq c_reason_bare_cmdsub:C2e-bare c_reason_bare_semicolon:C2e-semicolon c_with_no_verify:C3
c_unregistered:C4 c_unregistered_beside:C4b
c_shell1:C5a c_shell2:C5b c_shell3:C5c c_shell4:C5d c_shell_fin:C5e c_shell_bang_code:C5f c_shell_no_verify:C6
c_tp_no_verify:C7a c_tp_terminal:C7b c_remainder:C8 c_prefix:C9 c_flag:C10 c_single_dash_flag:C10b c_mcp_args:C11 c_args_ctl:C12
c_e_mcp:C13-mcp c_e_accum:C13-accum c_e_tdd:C13-tdd c_e_rev:C13-reviewers c_e_pr:C13-pr-review c_e_pr_ref:C13-pr-review-ref c_e_uat:C13-uat c_e_lic:C13-license
c_every_line:C14 c_pattern_only:C15 c_handoff_terminal:C16 c_handoff_shell_window:C16b c_handoff_code:C17 c_handoff_altered:C17c
c_handoff_no_prompt:C17d c_injected_prompt:C17e c_handoff_single_dash:C17f c_handoff_no_bang:C18 c_handoff_no_prompt_words:C18b
c_posttooluse:C19 c_question:C21 c_forged:C22
c_push_force:C23-push-force c_push_f:C23-push-f c_push_plus:C23-push-plus-refspec c_push_colon:C23-push-colon-refspec
c_push_delete:C23-push-delete c_push_d:C23-push-d c_push_mirror:C23-push-mirror c_push_prune:C23-push-prune
c_commit_amend:C23-commit-amend c_commit_n:C23-commit-n c_commit_author:C23-commit-other-flag
c_commit_trailing:C23-commit-after-message c_commit_cmdsub:C23-commit-message-expands c_commit_no_verify_long:C23-commit-no-verify
c_unknown_grammar:C24 c_empty_table:C25"

echo "=== Cases: the real detector ==="
for entry in $CASES; do
  fn="${entry%%:*}"; id="${entry#*:}"
  WHY=""
  if "$fn" "$REPO_ROOT"; then pass "$id ($fn)"; else fail_ "$id ($fn)" "$WHY"; fi
done

# ── the two layers, each alone ──────────────────────────────────────────────
echo ""
echo "=== Layers: the argument grammars and the backstop each hold alone ==="
# NOBACK: the backstop's call disabled — only the grammars stand.
NOBACK="$TMPROOT/tree-noback"
# WIDE: every grammar widened to "anything but a backtick" — only the backstop stands.
WIDE="$TMPROOT/tree-wide"
LAYERS_OK=1
if derive "$REPO_ROOT" "$NOBACK" BL-311-RELAY-BACKSTOP-CALL '_soif_relay_destructive "$line" && return 1' 'false && return 1'; then
  pass "L0a: the no-backstop tree derives (the backstop call disabled, landing asserted)"
else
  fail_ "L0a" "SETUP: the no-backstop tree did not derive"; LAYERS_OK=0
fi
if derive "$REPO_ROOT" "$WIDE" BL-311-RELAY-ARGS-GRAMMAR 'tail=$(_soif_relay_args_ere "$args") || return 1' 'tail="([[:space:]]+[^${bt}]*)?"'; then
  pass "L0b: the widened tree derives (every grammar widened, landing asserted)"
else
  fail_ "L0b" "SETUP: the widened tree did not derive"; LAYERS_OK=0
fi
GRAMMAR_PROBES="c_push_force c_push_f c_push_plus c_push_colon c_push_delete c_push_d c_push_mirror c_push_prune
c_commit_amend c_commit_n c_commit_author c_commit_trailing c_commit_cmdsub c_commit_no_verify_long c_mcp_args c_args_ctl"
BACKSTOP_PROBES="c_push_force c_push_f c_push_plus c_push_colon c_push_delete c_push_d c_push_mirror c_push_prune
c_commit_amend c_commit_n c_commit_no_verify_long c_mcp_args"
# layer ID TREE PROBES — every probe holds on TREE.
layer() {
  local id="$1" tree="$2" fn="" bad=""
  for fn in $3; do WHY=""; "$fn" "$tree" || bad="$bad $fn(${WHY})"; done
  if [ -z "$bad" ]; then pass "$id"; else fail_ "$id" "did not hold:$bad"; fi
}
if [ "$LAYERS_OK" = 1 ]; then
  layer "L1: with the backstop disabled, the grammars alone raise every C23 probe" "$NOBACK" "$GRAMMAR_PROBES"
  layer "L2: with every grammar widened, the backstop alone raises every probe it names" "$WIDE" "$BACKSTOP_PROBES"
  WHY=""
  if c_e_tdd "$WIDE"; then pass "L3: the widened tree still relays a documented escape (the widening did not break the relay path)"
  else fail_ "L3" "$WHY"; fi
else
  fail_ "L1-L3" "not run: a layer tree did not derive"
fi

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

# finisher_pin_check ACT4_FILE — rc 0 iff the finisher line ACT4_FILE's writer
# generates hashes to the detector's pin, and the detector's comment carries it.
finisher_pin_check() {
  local root="" fin="" n="" pin="" got=""
  root=$(mktemp -d "$TMPROOT/fp.XXXXXX") || return 1
  gen_prompt "$1" "$root" || { echo "the writer in $(basename "$1") generated no prompt"; return 1; }
  n=$(finisher_of "$root/.claude/adoption/assessment-prompt.md" | grep -c . || true)
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  [ "$n" = 1 ] || { echo "the generated prompt prints $n bash lines, want 1"; return 1; }
  fin=$(finisher_of "$root/.claude/adoption/assessment-prompt.md" | sed -n '1p')
  pin=$(sed -n "s/^SOIF_RELAY_FINISHER_SHA256='\([0-9a-f]*\)'\$/\1/p" "$REPO_ROOT/$DETECTOR_REL")
  got=$(sha256_of "$fin")
  [ "${#pin}" = 64 ] || { echo "the detector carries no 64-hex SOIF_RELAY_FINISHER_SHA256 ('$pin')"; return 1; }
  [ "${#got}" = 64 ] || { echo "no sha256sum/shasum here to hash the finisher"; return 1; }
  [ "$got" = "$pin" ] || { echo "the generated finisher hashes to $got, the detector pins $pin: $fin"; return 1; }
  grep -qF -- "#   $fin" "$REPO_ROOT/$DETECTOR_REL" || { echo "the detector's comment does not carry the finisher line: $fin"; return 1; }
}

# R1-R8 need the table; bash 3.2 treats an empty array as unbound under set -u.
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
r4_n=$(finisher_of "$GEN_PROMPT" | grep -c . || true)
case "$r4_n" in ''|*[!0-9]*) r4_n=0 ;; esac
[ "$r4_n" = 1 ] || r4_bad="$r4_bad [the generated prompt prints $r4_n bash lines, want 1]"
case "$FIN_LINE" in 'bash "$(jq -r .source_dir'*'--act4 --root .') ;; *) r4_bad="$r4_bad [the finisher line is not the expected shape: $FIN_LINE]" ;; esac
tr '\n' ' ' < "$GEN_PROMPT" | tr -s ' ' | grep -qF 'after ! at the Claude Code prompt' \
  || r4_bad="$r4_bad [step 10 no longer says 'after ! at the Claude Code prompt']"
if [ -z "$r4_bad" ]; then pass "R4: the generated assessment prompt prints one bash line (the finisher) and still says 'after ! at the Claude Code prompt'"; else fail_ "R4" "$r4_bad"; fi

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

if out=$(finisher_pin_check "$ACT4"); then
  pass "R7: the detector's finisher pin is the SHA-256 of the line adopt_write_assessment_prompt generates, and its comment carries that line"
else
  fail_ "R7" "$out"
fi

R8_ACT4="$TMPROOT/r8-adopt-act4.sh"
if mutate "$ACT4" "$R8_ACT4" BL-311-ASSESSMENT-AUTO-MODE '--act4 --root .' '--act4 --root . --yes' 80 \
   && [ "$(diff "$ACT4" "$R8_ACT4" | grep -c '^>' || true)" = 1 ] && grep -qF -- '--act4 --root . --yes' "$R8_ACT4"; then
  if out=$(finisher_pin_check "$R8_ACT4"); then
    fail_ "R8" "a changed finisher line in adopt-act4.sh did not fail R7"
  else
    case "$out" in *"hashes to"*) pass "R8: a changed finisher line in adopt-act4.sh fails R7 (RED as designed)" ;;
      *) fail_ "R8" "R7 failed for another reason: $out" ;; esac
  fi
else
  fail_ "R8" "SETUP: the finisher line of the adopt-act4.sh copy was not changed"
fi
}
if [ "$R0_OK" = 1 ]; then registry_cases; else fail_ "R1-R8" "not run: the escape table did not load"; fi

# ── mutation proofs ─────────────────────────────────────────────────────────
echo ""
echo "=== Mutation proofs: each marked line of the detector, broken in a copy ==="

KILLED=0
SURVIVED=0
# MBASE is the tree each mutant is cut from: the real detector, or a layer tree
# when the guard sits behind a second, redundant one.
MBASE="$REPO_ROOT"
MBASE_NAME="real"
# mutant ID MARKER OLD NEW KILL_FN [WINDOW]
mutant() {
  local id="$1" marker="$2" old="$3" new="$4" kill_fn="$5" win="${6:-25}" mr=""
  mr="$TMPROOT/mut-$id"
  if ! derive "$MBASE" "$mr" "$marker" "$old" "$new" "$win"; then
    fail_ "$id" "SETUP ($MBASE_NAME tree): '# $marker' is not present exactly once, '$old' is not within $win lines after it, or the mutation did not land as one changed line carrying '$new'"; return
  fi
  WHY=""
  if "$kill_fn" "$mr"; then
    fail_ "$id" "SURVIVED ($MBASE_NAME tree): $kill_fn still holds with '# $marker' broken ('$old' -> '$new')"
    SURVIVED=$((SURVIVED + 1))
  else
    pass "$id [$MBASE_NAME]: '# $marker' broken -> $kill_fn RED (${WHY})"
    KILLED=$((KILLED + 1))
  fi
}

mutant M1  BL-311-RELAY-PATTERN-ONLY '[ "$pattern" = "terminal_workaround" ] || return 1' '[ -n "$pattern" ] || return 1' c_pattern_only
mutant M2  BL-311-RELAY-REASON-REQUIRED '[[:space:]]+${reason}=${val}(' '([[:space:]]+${reason}=${val})?(' c_no_reason
mutant M3  BL-311-RELAY-REASON-VALUE "'[^'\${bt}]+'" "'[^'\${bt}]*'" c_empty_reason
mutant M3b BL-311-RELAY-REASON-VALUE '[A-Za-z0-9_.,:/+-]+)"' '[A-Za-z0-9_.,:/+-]*)"' c_bare_empty_reason
mutant M3c BL-311-RELAY-REASON-VALUE '\$\\\\!]+\"|' '\$\\\\!]*\"|' c_dq_empty_reason
mutant M3d BL-311-RELAY-REASON-VALUE '\"[^\"${bt}\$\\\\!]+\"|' '\"[^\"${bt}]+\"|' c_reason_cmdsub
mutant M3e BL-311-RELAY-REASON-VALUE '[A-Za-z0-9_.,:/+-]+)"' "[^[:space:]'\\\"\${bt}]+)\"" c_reason_bare_semicolon
mutant M6  BL-311-RELAY-NO-OTHER-ENV '[[ $rest =~ $env_ere ]] && return 1' '[[ $rest =~ $env_ere ]] && true' c_unregistered_beside
mutant M7  BL-311-RELAY-NO-FLAGS '[[ $rest =~ $opt_ere ]] && return 1' '[[ $rest =~ $opt_ere ]] && true' c_flag
mutant M7b BL-311-RELAY-NO-FLAGS 'opt_ere="(^|[[:space:](])--?[A-Za-z]"' 'opt_ere="(^|[[:space:](])--[A-Za-z]"' c_single_dash_flag
mutant M8  BL-311-RELAY-PREFIX '[[ $low =~ $prefix_ere ]] && return 1' '[[ $low =~ $prefix_ere ]] && true' c_prefix
mutant M9  BL-311-RELAY-REMAINDER 'grep -qiE -e "$tw" && return 1' 'grep -qiE -e "$tw" && true' c_remainder
mutant M10 BL-311-HANDOFF-BANG '[[ $low =~ $bang_ere ]] || return 1' '[[ $low =~ $bang_ere ]] || true' c_handoff_no_bang
mutant M10b BL-311-HANDOFF-BANG 'prompt_ere="claude code[^[:space:]]* prompt"' 'prompt_ere="."' c_handoff_no_prompt_words
mutant M11 BL-311-HANDOFF-COMMAND-VERBATIM 'case "$rest" in *"$bt"*) return 1 ;; esac' 'case "$rest" in *"@@never@@"*) return 1 ;; esac' c_handoff_code
mutant M11b BL-311-HANDOFF-COMMAND-VERBATIM 'opt_ere="(^|[[:space:](])--?[A-Za-z]"' 'opt_ere="(^|[[:space:](])--[A-Za-z]"' c_handoff_single_dash
mutant M12 BL-311-HANDOFF-ONLY-SHELL-MODE 'case "$low" in *terminal*|*shell*) return 1 ;; esac' 'case "$low" in *@@never@@*) return 1 ;; esac' c_handoff_terminal
mutant M12b BL-311-HANDOFF-MODE-NAME '(mode|commands?)' '(mode|commands?|window)' c_handoff_shell_window
mutant M13 BL-311-RELAY-EVERY-LINE 'return 1   # BL-311-RELAY-EVERY-LINE' 'continue   # BL-311-RELAY-EVERY-LINE' c_every_line
mutant M14 BL-311-RELAY-STOP-ONLY 'if [ "$EVENT" = "Stop" ]; then' 'if [ -n "$EVENT" ]; then' c_posttooluse
mutant M15 BL-311-RELAYED-ESCAPE-ROW '.type = "relayed_framework_escape"' '.type = "claude_bypass_proposal"' c_dogfood
mutant M16 BL-311-RELAYED-NO-SENTINEL '[ -z "$RAISE_PATTERN" ] && exit 0' '[ -z "$RAISE_PATTERN" ] && true' c_dogfood
mutant M17 BL-311-RELAYED-QUESTION-PATTERN 'FIRST_PATTERN="$RAISE_PATTERN"' ': "$RAISE_PATTERN"' c_question
mutant M18 BL-311-RELAY-ESCAPES-BEGIN "'SOLO_TDD_ATTESTED|SOLO_TDD_REASON|git commit|commit-message'" "'SOLO_TDD_ATTESTED_X|SOLO_TDD_REASON|git commit|commit-message'" c_e_tdd
mutant M19 BL-311-RELAYED-ESCAPE-ROW '.user_response = "n/a"' '.user_response = "PENDING"' c_dogfood
mutant M20 BL-311-RELAYED-ESCAPE-ROW '    RAISE_PATTERN="$PATTERN"' '    : "$PATTERN"' c_tp_terminal
mutant M21 BL-311-HANDOFF-FINISHER-MATCH '[ "$(_soif_relay_sha256 "$body" || true)" = "$SOIF_RELAY_FINISHER_SHA256" ] && continue' '[ -n "$body" ] && continue' c_injected_prompt
mutant M21b BL-311-HANDOFF-FINISHER-MATCH '[ "$c" = "!" ] && continue' '[ "$c" = "@@never@@" ] && continue' c_shell_bang_code
mutant M21c BL-311-HANDOFF-FINISHER-PIN "SOIF_RELAY_FINISHER_SHA256='6e3dddd3" "SOIF_RELAY_FINISHER_SHA256='0e3dddd3" c_shell_fin
mutant M21d BL-311-HANDOFF-COMMAND-PINNED 'rest=$(_soif_relay_strip_handoff_code "$line")' 'rest="$line"' c_shell_fin
mutant M22 BL-311-RELAY-PHRASE 'while [[ $low =~ $phrase_ere ]]; do' 'while false; do' c_dogfood
mutant M23 BL-311-HANDOFF-MODE-NAME 'while [[ $low =~ $mode_ere ]]; do' 'while false; do' c_shell4
mutant M24 BL-311-RELAY-TOKEN-FORGE 'case "$low" in *"$tok"*) return 1 ;; esac' 'case "$low" in *"@@never@@"*) return 1 ;; esac' c_forged
mutant M25 BL-311-RELAY-ARGS-UNKNOWN '*) return 1 ;;' '*) printf '"'%s'"' "" ;;' c_unknown_grammar 0

# The argument grammars, on the no-backstop tree (the backstop would otherwise
# catch every probe and no grammar mutant could die).
if [ "$LAYERS_OK" = 1 ]; then
MBASE="$NOBACK"; MBASE_NAME="no-backstop"
mutant M4  BL-311-RELAY-ARGS-GRAMMAR 'tail=$(_soif_relay_args_ere "$args") || return 1' 'tail="([[:space:]]+[^${bt}]*)?"' c_push_plus
mutant M5  BL-311-RELAY-ARGS-NONE "'') printf '%s' \"\" ;;" "'') printf '%s' \"([[:space:]]+[^\${bt}]*)?\" ;;" c_mcp_args
mutant M26 BL-311-RELAY-ARGS-PUSH 'name="[A-Za-z0-9_][A-Za-z0-9._/-]*"' 'name="[^[:space:]${bt}]+"' c_push_plus
mutant M27 BL-311-RELAY-ARGS-COMMIT '(-m|--message)' '(-[A-Za-z-]+)' c_commit_author
mutant M28 BL-311-RELAY-ARGS-COMMIT '\"))?" ;;' '\")([[:space:]]+[^${bt}]*)?)?" ;;' c_commit_trailing
mutant M29 BL-311-RELAY-ARGS-COMMIT '\"[^\"${bt}\$\\\\!]+\"))?' '\"[^\"${bt}\\\\!]+\"))?' c_commit_cmdsub

# The backstop, on the widened tree (the grammars would otherwise refuse every
# probe and no backstop mutant could die).
MBASE="$WIDE"; MBASE_NAME="widened"
mutant M30 BL-311-RELAY-BACKSTOP-CALL '_soif_relay_destructive "$line" && return 1' '_soif_relay_destructive "$line" && true' c_push_plus
mutant M31 BL-311-RELAY-BACKSTOP-FLAGS '*--force*|' '' c_push_force
mutant M32 BL-311-RELAY-BACKSTOP-FLAGS '*--amend*|' '' c_commit_amend
mutant M33 BL-311-RELAY-BACKSTOP-FLAGS '*--no-verify*|' '' c_commit_no_verify_long
mutant M34 BL-311-RELAY-BACKSTOP-FLAGS '*--dangerously-skip-permissions*|' '' c_mcp_args
mutant M35 BL-311-RELAY-BACKSTOP-FLAGS '*--delete*|' '' c_push_delete
mutant M36 BL-311-RELAY-BACKSTOP-FLAGS '*--mirror*|' '' c_push_mirror
mutant M37 BL-311-RELAY-BACKSTOP-FLAGS '|*--prune*)' ')' c_push_prune
mutant M38 BL-311-RELAY-BACKSTOP-PUSH '(-[a-z]*[fd]|' '(-[a-z]*[d]|' c_push_f
mutant M39 BL-311-RELAY-BACKSTOP-PUSH '(-[a-z]*[fd]|' '(-[a-z]*[f]|' c_push_d
mutant M40 BL-311-RELAY-BACKSTOP-PUSH '[+:][^[:space:]]' '[:][^[:space:]]' c_push_plus
mutant M41 BL-311-RELAY-BACKSTOP-PUSH '[+:][^[:space:]]' '[+][^[:space:]]' c_push_colon
mutant M42 BL-311-RELAY-BACKSTOP-PUSH 'push[[:space:]](.*[[:space:]])?(' 'push[[:space:]](' c_push_f
mutant M43 BL-311-RELAY-BACKSTOP-COMMIT '-[a-z]*n"' '-[a-z]*@"' c_commit_n
else
  fail_ "M4-M43" "not run: a layer tree did not derive"
fi

echo ""
echo "Mutants: $KILLED killed, $SURVIVED survived"
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
