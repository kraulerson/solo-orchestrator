#!/usr/bin/env bash
# tests/test-bl202-session-intake-check.sh — BL-202: a fresh Claude Code
# session in a generated project dead-airs — nothing tells the user what to
# type, and nothing tells Claude the intake is unfinished.
#
# THE FIX UNDER TEST: scripts/session-intake-check.sh (a SessionStart hook,
# modeled on session-test-gate-check.sh: silent when healthy, output the agent
# RELAYS) plus scripts/resume.sh becoming the single state-aware first-message
# generator. Detection is MODE-AGNOSTIC (blank-table-cell count — the
# validate.sh predicate; .claude/intake-progress.json is written by main-menu
# mode 1 only, so it can corroborate but never decide).
#
# HERMETIC: hand-rolled fixtures, direct hook/script invocation, stdin closed
# everywhere. No scaffolding. bash-3.2 safe. Registered in BOTH lanes.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/scripts/session-intake-check.sh"
RESUME="$REPO_ROOT/scripts/resume.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# mk_proj <dir> <blank-cells> <phase> — minimal generated-project state.
# <blank-cells> unfilled table rows go into PROJECT_INTAKE.md alongside a few
# filled ones; <phase> lands in phase-state.json.
mk_proj() {
  local d="$1" blanks="$2" phase="$3" i
  mkdir -p "$d/.claude" "$d/scripts"
  printf '{"current_phase": "%s"}\n' "$phase" > "$d/.claude/phase-state.json"
  {
    printf '# Project Intake\n\n## 1. Basics\n\n'
    printf '| **Project name** | demo |\n'
    printf '| **Description** | a demo |\n'
    i=0
    while [ "$i" -lt "$blanks" ]; do
      printf '| **Field %s** | |\n' "$i"
      i=$((i + 1))
    done
    printf '\n## 13. Agent Initialization Prompt\n\n```\nBL202-S13-SENTINEL: read the intake, then begin Phase 0.\n```\n'
  } > "$d/PROJECT_INTAKE.md"
}

run_hook() {  # <dir> <log>
  ( cd "$1" && bash "$HOOK" </dev/null ) > "$2" 2>"$2.err"
}

# ── H1: incomplete intake -> loud relay naming the wizard and the ack ────────
echo "=== H1-incomplete-intake-loud ==="
D="$TOPTMP/h1"; mk_proj "$D" 25 0
if run_hook "$D" "$TOPTMP/h1.log" && grep -q 'INTAKE INCOMPLETE' "$TOPTMP/h1.log" \
   && grep -q 'intake-wizard.sh' "$TOPTMP/h1.log" \
   && grep -q 'proceed_without_intake_acknowledged' "$TOPTMP/h1.log" \
   && ! [ -s "$TOPTMP/h1.log.err" ]; then
  pass "H1-incomplete-intake-loud (25 blank cells at phase 0 -> the agent is told, offered continue-vs-proceed, clean stderr)"
else
  fail_ "H1-incomplete-intake-loud" "rc/content wrong: $(head -2 "$TOPTMP/h1.log" 2>/dev/null | tr '\n' '|') err=$(head -1 "$TOPTMP/h1.log.err" 2>/dev/null)"
fi

# ── H2: intake filled, Phase 0 never started -> stranded relay ───────────────
echo "=== H2-stranded-before-phase0 ==="
D="$TOPTMP/h2"; mk_proj "$D" 3 0
if run_hook "$D" "$TOPTMP/h2.log" && grep -q 'READY FOR PHASE 0' "$TOPTMP/h2.log" \
   && grep -q 'resume.sh' "$TOPTMP/h2.log"; then
  pass "H2-stranded-before-phase0 (filled intake + no PRODUCT_MANIFESTO.md -> points at resume.sh — the state modes 1 and 2 land in by construction)"
else
  fail_ "H2-stranded-before-phase0" "$(head -2 "$TOPTMP/h2.log" 2>/dev/null | tr '\n' '|')"
fi

# ── H3: acknowledged proceed-without-intake -> permanently silent ────────────
echo "=== H3-acked-silent ==="
D="$TOPTMP/h3"; mk_proj "$D" 25 0
printf '{"intake": {"proceed_without_intake_acknowledged": true}}\n' > "$D/.claude/process-state.json"
if run_hook "$D" "$TOPTMP/h3.log" && ! [ -s "$TOPTMP/h3.log" ]; then
  pass "H3-acked-silent (the operator chose to proceed once — the hook never nags again)"
else
  fail_ "H3-acked-silent" "hook spoke over an acknowledged choice: $(head -1 "$TOPTMP/h3.log" 2>/dev/null)"
fi

# ── H4: healthy states are silent (manifesto present; later phase) ───────────
echo "=== H4-healthy-silent ==="
D="$TOPTMP/h4a"; mk_proj "$D" 3 0
printf '# manifesto\n' > "$D/PRODUCT_MANIFESTO.md"
D2="$TOPTMP/h4b"; mk_proj "$D2" 25 2
H4_OK=1
run_hook "$D" "$TOPTMP/h4a.log" && [ ! -s "$TOPTMP/h4a.log" ] || H4_OK=0
run_hook "$D2" "$TOPTMP/h4b.log" && [ ! -s "$TOPTMP/h4b.log" ] || H4_OK=0
if [ "$H4_OK" -eq 1 ]; then
  pass "H4-healthy-silent (Phase 0 underway, and past-Phase-0 projects, are both left alone — even with blank cells)"
else
  fail_ "H4-healthy-silent" "a healthy state produced output: a=$(head -1 "$TOPTMP/h4a.log" 2>/dev/null) b=$(head -1 "$TOPTMP/h4b.log" 2>/dev/null)"
fi

# ── H5: not a generated project -> silent ────────────────────────────────────
echo "=== H5-not-a-project-silent ==="
D="$TOPTMP/h5"; mkdir -p "$D"
if run_hook "$D" "$TOPTMP/h5.log" && [ ! -s "$TOPTMP/h5.log" ]; then
  pass "H5-not-a-project-silent (no phase-state, no intake -> not ours, stay quiet)"
else
  fail_ "H5-not-a-project-silent" "$(head -1 "$TOPTMP/h5.log" 2>/dev/null)"
fi

# ── H6: excision mutation — the detection fence is load-bearing ──────────────
# Negative control included (R-BL203-13's lesson): the mutant must be RUNNABLE
# (empty stderr is the proof it reached the code), and an INTACT copy must
# fail this case's excised-expectation.
echo "=== H6-mutation-detect-fence ==="
MUT="$TOPTMP/hook.mut.sh"
MB=$(grep -c '# BL-202-INTAKE-DETECT-BEGIN' "$HOOK" 2>/dev/null) || MB=0
ME=$(grep -c '# BL-202-INTAKE-DETECT-END' "$HOOK" 2>/dev/null) || ME=0
sed '/# BL-202-INTAKE-DETECT-BEGIN/,/# BL-202-INTAKE-DETECT-END/d' "$HOOK" > "$MUT" 2>/dev/null || true
if [ "$MB" -ne 1 ] || [ "$ME" -ne 1 ]; then
  fail_ "H6-mutation-detect-fence" "fence not present exactly once (begin=$MB end=$ME) — retarget this mutation in lockstep"
elif ! bash -n "$MUT" 2>/dev/null; then
  fail_ "H6-mutation-detect-fence" "mutant has a syntax error — a broken mutant proves nothing"
else
  D="$TOPTMP/h6"; mk_proj "$D" 25 0
  ( cd "$D" && bash "$MUT" </dev/null ) > "$TOPTMP/h6.log" 2>"$TOPTMP/h6.err" || true
  if [ -s "$TOPTMP/h6.err" ]; then
    fail_ "H6-mutation-detect-fence" "the mutant errored before reaching the code ($(head -1 "$TOPTMP/h6.err")) — an unrunnable mutant proves nothing"
  elif grep -q 'INTAKE INCOMPLETE' "$TOPTMP/h6.log"; then
    fail_ "H6-mutation-detect-fence" "excising the detection fence did NOT silence the incomplete arm — the fence is not cutting what it claims"
  else
    # Negative control (the R-BL203-13 lesson, run rather than claimed): the
    # INTACT hook on the same fixture must still speak, or this case cannot
    # tell an excision from a hook that never fires.
    ( cd "$D" && bash "$HOOK" </dev/null ) > "$TOPTMP/h6-intact.log" 2>/dev/null || true
    if grep -q 'INTAKE INCOMPLETE' "$TOPTMP/h6-intact.log"; then
      pass "H6-mutation-detect-fence (excised -> dark, intact -> speaks, mutant runnable — the fence is load-bearing and the case discriminates)"
    else
      fail_ "H6-mutation-detect-fence" "NEGATIVE CONTROL FAILED — the intact hook did not fire on the incomplete fixture, so this case cannot discriminate"
    fi
  fi
fi

# ── H7: the predicate against the REAL template (review R-BL202-1) ───────────
# The suite's hand-rolled fixtures could not see the shipped predicate counting
# EVERY table row (constant 258, filled or not). Pin discrimination against the
# artifact that matters: the shipped template must read INCOMPLETE, and the same
# file with every blank cell filled must read complete.
echo "=== H7-template-predicate-discriminates ==="
TPL="$REPO_ROOT/templates/project-intake.md"
if [ ! -f "$TPL" ]; then
  fail_ "H7-template-predicate-discriminates" "template missing at $TPL"
else
  D="$TOPTMP/h7"; mkdir -p "$D/.claude"
  printf '{"current_phase": "0"}\n' > "$D/.claude/phase-state.json"
  cp "$TPL" "$D/PROJECT_INTAKE.md"
  run_hook "$D" "$TOPTMP/h7a.log"
  sed 's/|[[:space:]]*|$/| filled |/' "$TPL" > "$D/PROJECT_INTAKE.md"
  H7_BLANKS=$(grep -cE '\| *\|$' "$D/PROJECT_INTAKE.md" || true)  # lint-counter-antipattern: allow — sanitized on the next line to 1, not 0: zero is this assertion's PASS value, so the fail-safe default must be nonzero
  case "$H7_BLANKS" in ''|*[!0-9]*) H7_BLANKS=1 ;; esac
  run_hook "$D" "$TOPTMP/h7b.log"
  if grep -q 'INTAKE INCOMPLETE' "$TOPTMP/h7a.log" \
     && [ "${H7_BLANKS:-1}" = "0" ] \
     && ! grep -q 'INTAKE INCOMPLETE' "$TOPTMP/h7b.log"; then
    pass "H7-template-predicate-discriminates (the SHIPPED template reads incomplete; the same file fully filled reads complete — the predicate discriminates on the real artifact)"
  else
    fail_ "H7-template-predicate-discriminates" "unfilled-fires=$(grep -c 'INTAKE INCOMPLETE' "$TOPTMP/h7a.log") filled-blanks=$H7_BLANKS filled-fires=$(grep -c 'INTAKE INCOMPLETE' "$TOPTMP/h7b.log") — the predicate does not discriminate on the shipped template (R-BL202-1)"
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# BL-202 FOLLOW-UP — the SessionStart JSON envelope and initialUserMessage.
#
# The original fix could only put text in CLAUDE'S context; the screen still
# stayed blank until the operator typed something. The follow-up emits the
# documented SessionStart JSON instead of plain stdout, so it can ALSO seed the
# first user turn (`initialUserMessage`) on a genuinely fresh conversation.
#
# WHAT THESE CASES PIN, and why each is load-bearing:
#   • ONE form per run. Mixing plain stdout and JSON from a single hook is
#     UNDEFINED per the hook docs, so every speaking path must emit exactly one
#     compact JSON document (J1) and the silent paths must emit nothing at all
#     (J8) — not an empty envelope.
#   • additionalContext is the PARITY field (J2/J3). Whatever the client does
#     with initialUserMessage, the pre-follow-up behaviour must still hold, so
#     the full instruction text has to survive the round trip byte-for-byte —
#     including the multi-line body and the remedy line's shell punctuation.
#     That is why the escaping must be jq's, never hand-rolled (M2).
#   • initialUserMessage is SOURCE-GATED (J4/J5 present; J6/J7 absent).
#     `source` is startup|resume|clear|compact (plus fork variants). Injecting a
#     synthetic user turn on resume/compact would corrupt a REAL, in-flight
#     conversation, so the gate fails CLOSED on everything it does not
#     positively recognise — including an absent, truncated or garbage
#     envelope. Uncertainty must never auto-message.
# HERMETIC: fixtures only, stdin supplied explicitly on every run.
# ═══════════════════════════════════════════════════════════════════════════

# run_hook_stdin <dir> <log> <envelope> — run_hook, but feeding a SessionStart
# envelope on stdin instead of closing it.
run_hook_stdin() {
  ( cd "$1" && printf '%s' "$3" | bash "$HOOK" ) > "$2" 2>"$2.err"
}
# jget <log> <filter> — decoded field; empty string on any parse failure.
jget() { jq -r "$2" "$1" 2>/dev/null || true; }
# has_ium <log> — rc 0 iff hookSpecificOutput.initialUserMessage is present.
has_ium() { jq -e '.hookSpecificOutput | has("initialUserMessage")' "$1" >/dev/null 2>&1; }
# raw_lines <file> — physical line count of the EMITTED document.
raw_lines() { wc -l < "$1" | tr -d ' '; }

JA="$TOPTMP/ja"; mk_proj "$JA" 25 0    # state 1: INTAKE INCOMPLETE
JB="$TOPTMP/jb"; mk_proj "$JB" 3 0     # state 2: READY FOR PHASE 0

# ── J1: a speaking run emits exactly ONE valid compact JSON document ─────────
echo "=== J1-json-envelope-shape ==="
run_hook_stdin "$JA" "$TOPTMP/ja-startup.log" '{"hook_event_name":"SessionStart","source":"startup"}'
run_hook_stdin "$JB" "$TOPTMP/jb-startup.log" '{"hook_event_name":"SessionStart","source":"startup"}'
J1_OK=1; J1_WHY=""
for f in "$TOPTMP/ja-startup.log" "$TOPTMP/jb-startup.log"; do
  jq -e . "$f" >/dev/null 2>&1 || { J1_OK=0; J1_WHY="$J1_WHY [$(basename "$f"):unparseable]"; }
  [ "$(jget "$f" '.hookSpecificOutput.hookEventName')" = "SessionStart" ] \
    || { J1_OK=0; J1_WHY="$J1_WHY [$(basename "$f"):hookEventName]"; }
  [ "$(raw_lines "$f")" = "1" ] || { J1_OK=0; J1_WHY="$J1_WHY [$(basename "$f"):not-one-line]"; }
  if [ -s "$f.err" ]; then J1_OK=0; J1_WHY="$J1_WHY [$(basename "$f"):stderr]"; fi
done
if [ "$J1_OK" -eq 1 ]; then
  pass "J1-json-envelope-shape (both live states emit one compact parseable document with hookEventName=SessionStart and clean stderr — never a mix of plain text and JSON)"
else
  fail_ "J1-json-envelope-shape" "$J1_WHY first-bytes-a=$(head -c 100 "$TOPTMP/ja-startup.log" 2>/dev/null) first-bytes-b=$(head -c 100 "$TOPTMP/jb-startup.log" 2>/dev/null)"
fi

# ── J2: additionalContext carries the pre-follow-up text in BOTH states ──────
echo "=== J2-additionalcontext-both-states ==="
J2A=$(jget "$TOPTMP/ja-startup.log" '.hookSpecificOutput.additionalContext')
J2B=$(jget "$TOPTMP/jb-startup.log" '.hookSpecificOutput.additionalContext')
if printf '%s\n' "$J2A" | grep -q 'INTAKE INCOMPLETE' \
   && printf '%s\n' "$J2A" | grep -q 'bash scripts/intake-wizard.sh' \
   && printf '%s\n' "$J2A" | grep -q 'proceed_without_intake_acknowledged' \
   && printf '%s\n' "$J2B" | grep -q 'READY FOR PHASE 0' \
   && printf '%s\n' "$J2B" | grep -q 'bash scripts/resume.sh'; then
  pass "J2-additionalcontext-both-states (the full instruction text still reaches Claude's context in both actionable states — the graceful-degradation path if initialUserMessage is ignored)"
else
  fail_ "J2-additionalcontext-both-states" "incomplete-ctx=$(printf '%s' "$J2A" | head -1) ready-ctx=$(printf '%s' "$J2B" | head -1)"
fi

# ── J3: escaping is jq's, proven on the REAL message text ────────────────────
# The message is multi-line and its remedy line carries shell punctuation
# ('  >  &&  =). A hand-rolled encoder emits raw newlines and dies here.
echo "=== J3-json-string-escaping-real-text ==="
J3_REMEDY="     jq '.intake.proceed_without_intake_acknowledged = true' .claude/process-state.json > .claude/process-state.json.tmp && mv .claude/process-state.json.tmp .claude/process-state.json"
J3_DECODED_LINES=$(printf '%s\n' "$J2A" | wc -l | tr -d ' ')
case "$J3_DECODED_LINES" in ''|*[!0-9]*) J3_DECODED_LINES=0 ;; esac
if grep -qF '\n' "$TOPTMP/ja-startup.log" \
   && [ "$(raw_lines "$TOPTMP/ja-startup.log")" = "1" ] \
   && [ "$J3_DECODED_LINES" -ge 8 ] \
   && printf '%s\n' "$J2A" | grep -qxF "$J3_REMEDY"; then
  pass "J3-json-string-escaping-real-text (the emitted doc is one physical line carrying escaped \\n, and decodes back to a >=8-line body whose remedy line round-trips byte-for-byte)"
else
  fail_ "J3-json-string-escaping-real-text" "raw-lines=$(raw_lines "$TOPTMP/ja-startup.log") decoded-lines=$J3_DECODED_LINES remedy-roundtrip=$(printf '%s\n' "$J2A" | grep -cxF "$J3_REMEDY" 2>/dev/null || echo 0)"
fi

# ── J4: initialUserMessage present on source=startup, in BOTH states ─────────
echo "=== J4-initialusermessage-on-startup ==="
J4A=$(jget "$TOPTMP/ja-startup.log" '.hookSpecificOutput.initialUserMessage')
J4B=$(jget "$TOPTMP/jb-startup.log" '.hookSpecificOutput.initialUserMessage')
J4A_LINES=$(printf '%s\n' "$J4A" | wc -l | tr -d ' ')
J4B_LINES=$(printf '%s\n' "$J4B" | wc -l | tr -d ' ')
if has_ium "$TOPTMP/ja-startup.log" && has_ium "$TOPTMP/jb-startup.log" \
   && [ -n "$J4A" ] && [ -n "$J4B" ] \
   && [ "$J4A_LINES" = "1" ] && [ "$J4B_LINES" = "1" ] \
   && [ "${#J4A}" -le 200 ] && [ "${#J4B}" -le 200 ] \
   && printf '%s\n' "$J4A" | grep -qi 'intake' \
   && printf '%s\n' "$J4B" | grep -q 'scripts/resume.sh'; then
  pass "J4-initialusermessage-on-startup (a fresh startup seeds a short one-line user-voiced first turn in both states — the incomplete one asks about the intake, the ready one asks for the Phase 0 prompt via resume.sh)"
else
  fail_ "J4-initialusermessage-on-startup" "incomplete-msg='$J4A' (lines=$J4A_LINES len=${#J4A}) ready-msg='$J4B' (lines=$J4B_LINES len=${#J4B})"
fi

# ── J5: source=clear is a fresh conversation too ─────────────────────────────
echo "=== J5-initialusermessage-on-clear ==="
run_hook_stdin "$JA" "$TOPTMP/ja-clear.log" '{"source":"clear"}'
run_hook_stdin "$JB" "$TOPTMP/jb-clear.log" '{"source":"clear"}'
if has_ium "$TOPTMP/ja-clear.log" && has_ium "$TOPTMP/jb-clear.log" \
   && [ "$(jget "$TOPTMP/ja-clear.log" '.hookSpecificOutput.initialUserMessage')" = "$J4A" ] \
   && [ "$(jget "$TOPTMP/jb-clear.log" '.hookSpecificOutput.initialUserMessage')" = "$J4B" ]; then
  pass "J5-initialusermessage-on-clear (/clear starts a genuinely new conversation, so it seeds the same first turn as startup — in both states)"
else
  fail_ "J5-initialusermessage-on-clear" "a=$(head -c 160 "$TOPTMP/ja-clear.log" 2>/dev/null) b=$(head -c 160 "$TOPTMP/jb-clear.log" 2>/dev/null)"
fi

# ── J6: every NON-fresh source keeps context and withholds the user turn ─────
# resume/compact are mid-conversation refreshes; an unrecognised value (a future
# fork variant) must be treated the same way. Context parity is unconditional.
echo "=== J6-no-initialusermessage-on-resume-compact ==="
# `fork` is a REAL source value in the documented enum (startup|resume|clear|
# compact|fork) and the one place withholding is a genuine DECISION rather than
# a fall-through: the docs say initialUserMessage applies to startup/fork, but a
# fork INHERITS a real conversation's history, so seeding a synthetic first turn
# there would talk over live context. We fail closed on it deliberately —
# additionalContext still fires, so a forked session loses nothing but the
# auto-start. `resume_fork` stays alongside as an unrecognised-value probe.
J6_ENVS=( '{"source":"resume"}' '{"source":"compact"}' '{"source":"fork"}' '{"source":"resume_fork"}' '{"source":""}' '{"session_id":"abc"}' )
J6_OK=1; J6_WHY=""; j6i=0
while [ "$j6i" -lt "${#J6_ENVS[@]}" ]; do
  j6env="${J6_ENVS[$j6i]}"; j6log="$TOPTMP/j6-$j6i.log"
  run_hook_stdin "$JA" "$j6log" "$j6env"
  jq -e . "$j6log" >/dev/null 2>&1 || { J6_OK=0; J6_WHY="$J6_WHY [$j6env:unparseable]"; }
  [ -n "$(jget "$j6log" '.hookSpecificOutput.additionalContext')" ] \
    || { J6_OK=0; J6_WHY="$J6_WHY [$j6env:no-additionalContext]"; }
  if has_ium "$j6log"; then J6_OK=0; J6_WHY="$J6_WHY [$j6env:LEAKED-initialUserMessage]"; fi
  j6i=$((j6i + 1))
done
run_hook_stdin "$JB" "$TOPTMP/j6-ready-resume.log" '{"source":"resume"}'
if has_ium "$TOPTMP/j6-ready-resume.log"; then J6_OK=0; J6_WHY="$J6_WHY [ready/resume:LEAKED-initialUserMessage]"; fi
if [ "$J6_OK" -eq 1 ]; then
  pass "J6-no-initialusermessage-on-resume-compact (resume, compact, an unrecognised fork-style value, an empty source and a source-less envelope all keep additionalContext and withhold the synthetic user turn — a mid-conversation refresh is never hijacked)"
else
  fail_ "J6-no-initialusermessage-on-resume-compact" "$J6_WHY"
fi

# ── J7: an unusable envelope is treated as NOT-fresh (fail closed) ───────────
echo "=== J7-unreadable-stdin-fails-closed ==="
run_hook "$JA" "$TOPTMP/j7-closed.log"
run_hook_stdin "$JA" "$TOPTMP/j7-garbage.log" 'this is not json at all {{{'
run_hook_stdin "$JA" "$TOPTMP/j7-truncated.log" '{"source":"startup"'
J7_OK=1; J7_WHY=""
for f in "$TOPTMP/j7-closed.log" "$TOPTMP/j7-garbage.log" "$TOPTMP/j7-truncated.log"; do
  jq -e . "$f" >/dev/null 2>&1 || { J7_OK=0; J7_WHY="$J7_WHY [$(basename "$f"):unparseable-output]"; }
  [ -n "$(jget "$f" '.hookSpecificOutput.additionalContext')" ] \
    || { J7_OK=0; J7_WHY="$J7_WHY [$(basename "$f"):no-additionalContext]"; }
  if has_ium "$f"; then J7_OK=0; J7_WHY="$J7_WHY [$(basename "$f"):LEAKED-initialUserMessage]"; fi
  if [ -s "$f.err" ]; then J7_OK=0; J7_WHY="$J7_WHY [$(basename "$f"):stderr]"; fi
done
if [ "$J7_OK" -eq 1 ]; then
  pass "J7-unreadable-stdin-fails-closed (closed stdin, garbage, and a TRUNCATED envelope that literally contains the word startup all degrade to context-only — uncertainty never auto-messages, and the hook still speaks)"
else
  fail_ "J7-unreadable-stdin-fails-closed" "$J7_WHY"
fi

# ── J8: the silent states stay COMPLETELY silent, envelope or not ────────────
echo "=== J8-silent-states-emit-nothing ==="
J8_OK=1; J8_WHY=""
D="$TOPTMP/j8-ack"; mk_proj "$D" 25 0
printf '{"intake": {"proceed_without_intake_acknowledged": true}}\n' > "$D/.claude/process-state.json"
D2="$TOPTMP/j8-phase"; mk_proj "$D2" 25 2
D3="$TOPTMP/j8-noproj"; mkdir -p "$D3"
D4="$TOPTMP/j8-healthy"; mk_proj "$D4" 3 0; printf '# manifesto\n' > "$D4/PRODUCT_MANIFESTO.md"
for d in "$D" "$D2" "$D3" "$D4"; do
  j8log="$TOPTMP/$(basename "$d").log"
  run_hook_stdin "$d" "$j8log" '{"source":"startup"}'
  if [ -s "$j8log" ]; then J8_OK=0; J8_WHY="$J8_WHY [$(basename "$d"):SPOKE:$(head -c 80 "$j8log")]"; fi
  if [ -s "$j8log.err" ]; then J8_OK=0; J8_WHY="$J8_WHY [$(basename "$d"):stderr]"; fi
done
if [ "$J8_OK" -eq 1 ]; then
  pass "J8-silent-states-emit-nothing (acked, past-Phase-0, not-a-project and healthy all print NOTHING even on a startup envelope — no empty JSON shell, no seeded turn)"
else
  fail_ "J8-silent-states-emit-nothing" "$J8_WHY"
fi

# ── J9: no jq -> silent exit 0 (the encoder's own guard) ─────────────────────
echo "=== J9-no-jq-silent ==="
J9_BIN="$TOPTMP/nojq-bin"; mkdir -p "$J9_BIN"
J9_RC=0
( cd "$JA" && PATH="$J9_BIN" /bin/bash "$HOOK" </dev/null ) > "$TOPTMP/j9.log" 2>"$TOPTMP/j9.err" || J9_RC=$?
if [ "$J9_RC" -ne 0 ]; then
  fail_ "J9-no-jq-silent" "hook exited $J9_RC without jq — fail-open is absolute, every path exits 0"
elif [ -s "$TOPTMP/j9.log" ] || [ -s "$TOPTMP/j9.err" ]; then
  fail_ "J9-no-jq-silent" "spoke without jq: out=$(head -c 80 "$TOPTMP/j9.log" 2>/dev/null) err=$(head -c 80 "$TOPTMP/j9.err" 2>/dev/null)"
elif ! [ -s "$TOPTMP/ja-startup.log" ]; then
  fail_ "J9-no-jq-silent" "NEGATIVE CONTROL FAILED — the same fixture is silent WITH jq too, so this case cannot discriminate"
else
  pass "J9-no-jq-silent (jq missing -> exit 0, zero bytes on both streams; the same fixture speaks when jq is present, so the guard is what silences it)"
fi

# ── S1/S2: the stdin read must be unreachable from EVERY silent state ────────
# R-BL202FU-1. The hook has FIVE silent states, not four — the fifth is a
# FALL-THROUGH, which is why it was missed: Phase 0 + intake filled (<=20 blank
# cells) + PRODUCT_MANIFESTO.md present clears every early guard and only exits
# at the last `if`. An EAGER stdin read placed before that `if` therefore runs
# in a silent state, and `cat` cannot see EOF while any writer holds the pipe
# open — so a hook that has nothing to say can BLOCK SessionStart indefinitely.
# The fix is a LAZY read inside emit_state(): reached only on a speaking call.
# S1 pins the structure (one read site, inside the function); S2 pins the
# behaviour against a real held-open pipe. Structure alone would pass a hoisted
# copy; behaviour alone would pass a version that happens not to block today.
echo "=== S1-stdin-read-is-lazy ==="
S1_START=$(grep -n '^emit_state() {' "$HOOK" 2>/dev/null | head -1 | cut -d: -f1)
case "${S1_START:-}" in ''|*[!0-9]*) S1_START=0 ;; esac
S1_END=0
if [ "$S1_START" -gt 0 ]; then
  S1_END=$(awk -v s="$S1_START" 'NR>=s && /^}$/{print NR; exit}' "$HOOK" 2>/dev/null)
  case "${S1_END:-}" in ''|*[!0-9]*) S1_END=0 ;; esac
fi
S1_N=$(grep -c 'ENVELOPE=\$(cat' "$HOOK" 2>/dev/null) || S1_N=0
case "$S1_N" in ''|*[!0-9]*) S1_N=0 ;; esac
S1_READ=$(grep -n 'ENVELOPE=\$(cat' "$HOOK" 2>/dev/null | head -1 | cut -d: -f1)
case "${S1_READ:-}" in ''|*[!0-9]*) S1_READ=0 ;; esac
# The marker must sit ON the read line — a file-wide count would also be
# satisfied by the header's citation of it, which is a cite, not the anchor.
S1_MARKED=0
if [ "$S1_READ" -gt 0 ]; then
  S1_MARKED=$(awk -v n="$S1_READ" 'NR==n' "$HOOK" 2>/dev/null | grep -c 'BL-202-LAZY-STDIN') || S1_MARKED=0
  case "$S1_MARKED" in ''|*[!0-9]*) S1_MARKED=0 ;; esac
fi
S1_INSIDE=no
if [ "$S1_START" -gt 0 ] && [ "$S1_END" -gt "$S1_START" ] \
   && [ "$S1_READ" -gt "$S1_START" ] && [ "$S1_READ" -lt "$S1_END" ]; then
  S1_INSIDE=yes
fi
if [ "$S1_N" -eq 1 ] && [ "$S1_INSIDE" = "yes" ] && [ "$S1_MARKED" -eq 1 ]; then
  pass "S1-stdin-read-is-lazy (exactly one stdin read, and it sits inside emit_state's body — so no silent state can reach it)"
else
  fail_ "S1-stdin-read-is-lazy" "read-sites=$S1_N read-line=$S1_READ emit_state-body=$S1_START..$S1_END inside=$S1_INSIDE marker-on-read-line=$S1_MARKED — expected exactly ONE stdin read, INSIDE emit_state's body, carrying the # BL-202-LAZY-STDIN marker; an eager read outside emit_state is reachable from all five silent states and blocks on a held-open pipe"
fi

# fifo_probe <tag> <runner> — run <runner> with a FIFO on stdin that a writer
# holds OPEN while sending nothing (the exact shape that starves `cat` of EOF),
# and wait a BOUNDED 3s. No timeout(1) on this host, so the bound is a poll
# loop over a done-file. Sets FP_HUNG / FP_RC / FP_OUT / FP_ERR. rc 2 = no mkfifo.
FP_HUNG=0; FP_RC=""; FP_OUT=""; FP_ERR=""
fifo_probe() {
  # One name per `local`: a single `local` expands ALL its words before it
  # assigns any of them, so a later word referencing an earlier name reads it
  # as unset — an "unbound variable" abort under set -u.
  local tag="$1"
  local runner="$2"
  local fifo="$TOPTMP/$tag.fifo"
  local done_f="$TOPTMP/$tag.done"
  local wpid=""
  local hpid=""
  local w=0
  FP_OUT="$TOPTMP/$tag.out"; FP_ERR="$TOPTMP/$tag.err"; FP_HUNG=0; FP_RC=""
  rm -f "$fifo" "$done_f" "$FP_OUT" "$FP_ERR"
  mkfifo "$fifo" 2>/dev/null || return 2
  # Writer holds the pipe open for 6s — longer than the 3s bound, so a real
  # block cannot be masked by the writer closing early.
  ( exec 9>"$fifo"; sleep 6 ) >/dev/null 2>&1 &
  wpid=$!
  ( bash "$runner" <"$fifo" > "$FP_OUT" 2> "$FP_ERR"; printf '%s\n' "$?" > "$done_f" ) >/dev/null 2>&1 &
  hpid=$!
  while [ ! -f "$done_f" ] && [ "$w" -lt 30 ]; do sleep 0.1; w=$((w + 1)); done
  [ -f "$done_f" ] || FP_HUNG=1
  kill "$wpid" 2>/dev/null || true
  kill "$hpid" 2>/dev/null || true
  wait "$wpid" 2>/dev/null || true
  wait "$hpid" 2>/dev/null || true
  FP_RC=$(cat "$done_f" 2>/dev/null || true)
  return 0
}

echo "=== S2-silent-state-never-blocks-on-stdin ==="
SH="$TOPTMP/silent-healthy"; mk_proj "$SH" 3 0
printf '# manifesto\n' > "$SH/PRODUCT_MANIFESTO.md"   # the FIFTH silent state: the fall-through
S2_RUNNER="$TOPTMP/s2-runner.sh"
{ printf '#!/usr/bin/env bash\n'
  printf 'cd %s || exit 99\n' "$(printf '%q' "$SH")"
  printf 'exec bash %s\n' "$(printf '%q' "$HOOK")"; } > "$S2_RUNNER"
S2_CTRL="$TOPTMP/s2-ctrl.sh"
printf '#!/usr/bin/env bash\nexec cat >/dev/null\n' > "$S2_CTRL"
if ! fifo_probe s2ctrl "$S2_CTRL"; then
  fail_ "S2-silent-state-never-blocks-on-stdin" "mkfifo unavailable — this case cannot run, so it must not report a pass"
elif [ "$FP_HUNG" -ne 1 ]; then
  # POSITIVE CONTROL for the DETECTOR: a reader that provably blocks on this
  # pipe must be flagged. If it is not, the probe cannot detect a hang at all
  # and a green S2 would be meaningless.
  fail_ "S2-silent-state-never-blocks-on-stdin" "DETECTOR CONTROL FAILED — a plain blocking \`cat\` on the same held-open pipe was NOT flagged as hung, so this probe cannot detect a block"
else
  fifo_probe s2real "$S2_RUNNER"
  S2_OUT_B=$(wc -c < "$FP_OUT" 2>/dev/null | tr -d ' '); case "${S2_OUT_B:-}" in ''|*[!0-9]*) S2_OUT_B=-1 ;; esac
  S2_ERR_B=$(wc -c < "$FP_ERR" 2>/dev/null | tr -d ' '); case "${S2_ERR_B:-}" in ''|*[!0-9]*) S2_ERR_B=-1 ;; esac
  if [ "$FP_HUNG" -ne 0 ]; then
    fail_ "S2-silent-state-never-blocks-on-stdin" "the healthy/silent state BLOCKED on a held-open empty pipe (>3s) — an eager stdin read is reachable from a state that has nothing to say, and it stalls SessionStart"
  elif [ "$FP_RC" != "0" ]; then
    fail_ "S2-silent-state-never-blocks-on-stdin" "exit=$FP_RC on the silent fall-through — fail-open is absolute, every path exits 0"
  elif [ "$S2_OUT_B" != "0" ] || [ "$S2_ERR_B" != "0" ]; then
    fail_ "S2-silent-state-never-blocks-on-stdin" "the silent fall-through spoke: stdout=${S2_OUT_B}B stderr=${S2_ERR_B}B"
  else
    pass "S2-silent-state-never-blocks-on-stdin (the fifth silent state — intake filled, manifesto present — returns immediately with exit 0 and zero bytes even while a writer holds stdin open sending nothing; the same probe does flag a genuinely blocking reader)"
  fi
fi

# ── M1: mutation — the source gate's arm list is what withholds the turn ─────
echo "=== M1-mutation-source-gate ==="
M1MUT="$TOPTMP/hook.srcgate.mut.sh"
M1N=$(grep -c 'BL-202-SOURCE-GATE' "$HOOK" 2>/dev/null) || M1N=0
sed 's/startup|clear) FRESH_SESSION=true/startup|clear|resume|compact) FRESH_SESSION=true/' "$HOOK" > "$M1MUT" 2>/dev/null || true
run_hook_stdin "$JA" "$TOPTMP/m1-intact-resume.log" '{"source":"resume"}'
if [ "$M1N" -ne 1 ]; then
  fail_ "M1-mutation-source-gate" "the BL-202-SOURCE-GATE marker is not present exactly once (n=$M1N) — retarget this mutation in lockstep"
elif cmp -s "$M1MUT" "$HOOK"; then
  fail_ "M1-mutation-source-gate" "the sed was a no-op (its target moved) — a mutant identical to the original proves nothing"
elif ! bash -n "$M1MUT" 2>/dev/null; then
  fail_ "M1-mutation-source-gate" "mutant has a syntax error — a broken mutant proves nothing"
else
  ( cd "$JA" && printf '%s' '{"source":"resume"}' | bash "$M1MUT" ) > "$TOPTMP/m1.log" 2>"$TOPTMP/m1.err" || true
  if [ -s "$TOPTMP/m1.err" ]; then
    fail_ "M1-mutation-source-gate" "the mutant errored before reaching the code ($(head -1 "$TOPTMP/m1.err")) — an unrunnable mutant proves nothing"
  elif ! has_ium "$TOPTMP/m1.log"; then
    fail_ "M1-mutation-source-gate" "widening the arm list to resume/compact did NOT leak initialUserMessage — that case arm is not what decides"
  elif has_ium "$TOPTMP/m1-intact-resume.log"; then
    fail_ "M1-mutation-source-gate" "NEGATIVE CONTROL FAILED — the INTACT hook already emits initialUserMessage on resume"
  elif ! has_ium "$TOPTMP/ja-startup.log"; then
    fail_ "M1-mutation-source-gate" "NEGATIVE CONTROL FAILED — the INTACT hook emits nothing on startup either, so this case cannot discriminate"
  else
    pass "M1-mutation-source-gate (adding resume|compact to the gate's arm list leaks the synthetic turn onto a mid-conversation refresh; intact stays closed on resume and open on startup — the arm list is load-bearing)"
  fi
fi

# ── M2: mutation — jq is what makes the output valid JSON ────────────────────
# Replace both encoder lines with the hand-rolled interpolation a reviewer might
# think is equivalent. The real message text is multi-line, so it emits raw
# control characters inside a JSON string and the document stops parsing.
echo "=== M2-mutation-json-encoder ==="
M2MUT="$TOPTMP/hook.encoder.mut.sh"
M2N=$(grep -c 'BL-202-JSON-ENCODE' "$HOOK" 2>/dev/null) || M2N=0
M2_NAIVE='    out="{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$ctx\"}}"'
export M2_NAIVE
awk 'BEGIN{r=ENVIRON["M2_NAIVE"]} index($0,"BL-202-JSON-ENCODE"){print r; next} {print}' "$HOOK" > "$M2MUT" 2>/dev/null || true
if [ "$M2N" -ne 2 ]; then
  fail_ "M2-mutation-json-encoder" "expected exactly 2 BL-202-JSON-ENCODE lines (one per gate branch), found $M2N — retarget this mutation in lockstep"
elif cmp -s "$M2MUT" "$HOOK"; then
  fail_ "M2-mutation-json-encoder" "the awk substitution was a no-op — a mutant identical to the original proves nothing"
elif ! bash -n "$M2MUT" 2>/dev/null; then
  fail_ "M2-mutation-json-encoder" "mutant has a syntax error — a broken mutant proves nothing"
else
  ( cd "$JA" && printf '%s' '{"source":"startup"}' | bash "$M2MUT" ) > "$TOPTMP/m2.log" 2>"$TOPTMP/m2.err" || true
  if [ -s "$TOPTMP/m2.err" ]; then
    fail_ "M2-mutation-json-encoder" "the mutant errored before reaching the code ($(head -1 "$TOPTMP/m2.err")) — an unrunnable mutant proves nothing"
  elif [ ! -s "$TOPTMP/m2.log" ]; then
    fail_ "M2-mutation-json-encoder" "the mutant emitted nothing — it never reached the encoder, so this case cannot discriminate"
  elif jq -e . "$TOPTMP/m2.log" >/dev/null 2>&1; then
    fail_ "M2-mutation-json-encoder" "hand-rolled interpolation still parsed as JSON — the encoder is not what makes the output valid"
  elif ! jq -e . "$TOPTMP/ja-startup.log" >/dev/null 2>&1; then
    fail_ "M2-mutation-json-encoder" "NEGATIVE CONTROL FAILED — the INTACT hook's output is not valid JSON on the same fixture"
  else
    pass "M2-mutation-json-encoder (swapping jq for hand-rolled interpolation emits raw newlines inside the string and the document stops parsing; intact parses on the same fixture — jq's encoding is load-bearing)"
  fi
fi

# ── R1: resume.sh, incomplete intake -> the intake first-message ─────────────
echo "=== R1-resume-intake-branch ==="
D="$TOPTMP/r1"; mk_proj "$D" 25 0
cp "$RESUME" "$D/scripts/resume.sh" 2>/dev/null || true
R1_OUT=$( cd "$D" && bash "$RESUME" </dev/null 2>/dev/null )
if printf '%s' "$R1_OUT" | grep -q 'intake' && printf '%s' "$R1_OUT" | grep -qi 'copy everything below'; then
  pass "R1-resume-intake-branch (an unfinished intake gets the intake first-message with the copy-delimiter convention)"
else
  fail_ "R1-resume-intake-branch" "resume.sh did not branch on an unfinished intake: $(printf '%s' "$R1_OUT" | head -2 | tr '\n' '|')"
fi

# ── R2: resume.sh, stranded -> §13's block verbatim ──────────────────────────
echo "=== R2-resume-stranded-branch ==="
D="$TOPTMP/r2"; mk_proj "$D" 3 0
R2_OUT=$( cd "$D" && bash "$RESUME" </dev/null 2>/dev/null )
if printf '%s' "$R2_OUT" | grep -q 'BL202-S13-SENTINEL'; then
  pass "R2-resume-stranded-branch (intake done + Phase 0 unstarted -> the project's own Section 13 prompt, verbatim)"
else
  fail_ "R2-resume-stranded-branch" "resume.sh did not surface the Section 13 block: $(printf '%s' "$R2_OUT" | head -2 | tr '\n' '|')"
fi

# ── R3: resume.sh, normal project -> today's behavior unchanged ──────────────
echo "=== R3-resume-normal-unchanged ==="
D="$TOPTMP/r3"; mk_proj "$D" 3 2
printf '# manifesto\n' > "$D/PRODUCT_MANIFESTO.md"
printf '# claude\n' > "$D/CLAUDE.md"
R3_OUT=$( cd "$D" && bash "$RESUME" </dev/null 2>/dev/null )
if printf '%s' "$R3_OUT" | grep -q 'We are resuming work'; then
  pass "R3-resume-normal-unchanged (a mid-flight project still gets the classic resume prompt)"
else
  fail_ "R3-resume-normal-unchanged" "the classic resume prompt is gone: $(printf '%s' "$R3_OUT" | head -2 | tr '\n' '|')"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
