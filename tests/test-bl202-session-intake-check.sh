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
