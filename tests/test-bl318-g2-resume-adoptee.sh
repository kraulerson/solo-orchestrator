#!/usr/bin/env bash
# tests/test-bl318-g2-resume-adoptee.sh — `## BL-318:` G2.
#
# THE DEFECT (dogfood run 2, finding 24). After k-pdf was adopted and assessed,
# `bash scripts/resume.sh` printed the CLASSIC resume prompt instead of the
# Phase 0 prompt docs/adoption.md promises, and its fields were garbage: the
# framework CLAUDE.md's Context Health Check paragraph three times, then
# "Last session: (not found in CLAUDE.md)".
#   - Routing: `## BL-202:` branch 2 (the project's own Section 13, verbatim)
#     required `[ ! -f PRODUCT_MANIFESTO.md ]`. Adoption never writes or removes
#     that file, so every adoptee built with an older Solo still has one and
#     fell through to the classic prompt.
#   - Garbage: the classic prompt took a field from ANY line containing its
#     words. The framework CLAUDE.md has no "Features built:" lines, but its
#     Context Health Check bullet says "Summarize features built, features
#     remaining, current data model, and known issues". That one line matched
#     three fields; the sed that strips "Label:" found no colon and stripped
#     nothing, so the whole paragraph became each field.
#
# THE FIX (scripts/resume.sh):
#   - `# BL-318-G2-ADOPTEE-PHASE0`: at phase 0, with the intake done, an ADOPTED
#     project (the adoption stamp, `.adoption.adopted == true` in
#     .claude/manifest.json) gets Section 13 whether or not it has a manifesto.
#     An adoptee that is not yet assessed never reaches it: the assessment
#     branch (`# BL-242-RESUME-ASSESSMENT`) exits first (A2 pins that order).
#   - `# BL-318-G2-FIELD-LABEL`: a field is read only from a "Label:" line, the
#     shape the CLI setup addendum's "## Current State" bullets use.
#   - `# BL-318-G2-FIELD-OMIT`, `# BL-318-G2-FIELDS-NONE`: a field CLAUDE.md
#     does not record is left out; when none is recorded, one plain line says
#     so. `# BL-318-G2-NO-CLAUDE-FIELDS` / `# BL-318-G2-NO-CLAUDE-CLOSING` do the
#     same when there is no CLAUDE.md at all.
#   - `# BL-318-G2-CURRENT-STATE`: the "Current State section is stale"
#     sentence is printed only when CLAUDE.md has such a section.
#
# FIXTURES. The adoptee is a REAL adoption (scripts/adopt-project.sh) of a tiny
# project that carries its own PRODUCT_MANIFESTO.md and an old-style CLAUDE.md,
# then the REAL Act 4 finisher run on a hand-written record — the same route
# tests/test-brownfield-wp12a-assessment.sh takes, so the state is what
# adoption writes, not a guess at it. Greenfield fixtures are hand-built (no
# init.sh, so this suite stays in the unit lane). Every run installs the script
# under test as the fixture's own scripts/resume.sh and runs it as a user does.
# check-versions.sh is made non-executable in every fixture: resume.sh skips it
# then, so no run reaches the network.
#
# CASES
#   A1  adoptee, assessed, its own manifesto, phase 0 -> its Section 13 verbatim
#   A2  adoptee, NOT assessed, its own manifesto -> the assessment prompt (unchanged)
#   A3  adoptee, assessed, no manifesto -> Section 13 (unchanged)
#   G1  greenfield, intake done, manifesto -> the classic prompt (unchanged routing)
#   G2  greenfield, intake done, no manifesto -> Section 13 (unchanged)
#   G3  greenfield, intake unfinished -> the intake first message (unchanged)
#   C1  classic prompt on the framework CLAUDE.md (a real adoptee at phase 1):
#       no Context Health Check paragraph, no "(not found in CLAUDE.md)", no
#       field lines, one plain line, no "Current State" sentence
#   C2  classic prompt on the addendum's "## Current State" format: each field
#       clean (no stray "**"), "Last session summary:" read, the sentence kept
#   C3  one field only, bold closed before the colon: that field, nothing else
#   C4  no CLAUDE.md: one plain line, never "Read CLAUDE.md"
#   M*  a mutant for every guard, each killed by a named case
set -uo pipefail
# The adoption driver's MCP step can ask a question and run `claude mcp add`;
# this suite pipes answers written without it (`# BL-311-MCP-SEAM`).
export SOIF_ADOPT_MCP=off

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT="$REPO_ROOT/scripts/resume.sh"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

echo "== BL-318 G2 — resume.sh after an adoption's assessment, and the classic prompt's fields =="

for t in git jq; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done

WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT

# The plain lines the fix prints. Spelled once here so a case and its mutant
# read the same text.
NONE_LINE='CLAUDE.md does not record what has been built, what remains, the known issues or where the last session stopped'
NO_CLAUDE_LINE='There is no CLAUDE.md in this project'
CS_SENTENCE='If CLAUDE.md'"'"'s "Current State" section is stale or incomplete'
CHC_LINE='Summarize features built, features remaining, current data model, and known issues'

# ── fixtures ─────────────────────────────────────────────────────────────────
# _adopt DIR — a real adoption of a project built with an older Solo.
_adopt() {
  local p="$1"
  mkdir -p "$p/src" || return 1
  ( cd "$p" && git init -q . && git config user.email g2@test.invalid && git config user.name "G2 Test" ) >/dev/null 2>&1 || return 1
  printf '{"name":"acme","scripts":{"test":"exit 0"}}\n' > "$p/package.json"
  printf '# acme\n' > "$p/README.md"
  printf '# Product Manifesto — acme\n\n## 1. Product Intent\n\nWritten with an older Solo, before adoption.\n' > "$p/PRODUCT_MANIFESTO.md"
  printf '# CLAUDE.md — acme\n\n## Current State\n- **Features built:** the parser\n- **Last session summary:** shipped 1.2\n' > "$p/CLAUDE.md"
  ( cd "$p" && git add package.json README.md PRODUCT_MANIFESTO.md CLAUDE.md \
      && git commit -q --no-verify -m "chore: their history" ) >/dev/null 2>&1 || return 1
  printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n' > "$WORK/ans"
  ( cd "$p" && bash "$REPO_ROOT/scripts/adopt-project.sh" < "$WORK/ans" ) > "$WORK/adopt.out" 2>&1
}
# _assess DIR — a hand-written record and verdict, then the real Act 4 finisher.
_assess() {
  local p="$1" commit=""
  commit="$(jq -r '.adoption.adoptedAtCommit' "$p/.claude/manifest.json")"
  jq -n --arg c "$commit" '{
    schemaVersion: 1, assessedAt: "2026-10-05T12:00:00Z", adoptedAtCommit: $c,
    interview: { users: "one person", availability: "none needed",
                 exposure: "offline desktop", scalability: "none expected",
                 dataClassification: "internal", zdrAttested: true, zdrReason: "",
                 inProduction: false, operations: {},
                 answers: { users_launch: "1", uptime: "not required" } },
    evaluators: [],
    fitness: { verdict: "keep",
               findings: [ { id: "F1", requirementRef: "interview.users", severity: "SEV-4",
                             evidence: "package.json", reasoning: "one user needs no more" } ] },
    plan: { path: "docs/phase-0/adoption-plan.md", summary: "continue from phase 0" },
    verdictArtifact: ".claude/adoption/verdict.md" }' > "$p/.claude/adoption/assessment-record.json"
  cat > "$p/.claude/adoption/verdict.md" <<'V'
# Adoption verdict

The stack fits the stated requirements: one user, offline.

## Plain English

What happened: the project was assessed.
Recommendation: keep it.
Reason: it does what one person needs.
If you do nothing: it stays at phase 0.
V
  ( cd "$p" && bash "$REPO_ROOT/scripts/adopt-project.sh" --act4 --root . ) > "$WORK/act4.out" 2>&1
}
# _greenfield DIR MANIFESTO(yes|no) BLANKS — the state a scaffolded project has
# at phase 0: phase-state, a manifest with no adoption block, an intake whose
# Section 13 carries a sentinel, and the script's one library.
_greenfield() {
  local d="$1" man="$2" blanks="$3" i=0
  mkdir -p "$d/.claude" "$d/scripts/lib" || return 1
  cp "$REPO_ROOT/scripts/lib/helpers-core.sh" "$d/scripts/lib/" || return 1
  printf '{"current_phase": 0}\n' > "$d/.claude/phase-state.json"
  printf '{"frameworkVersion": "4.3.7", "files": {}}\n' > "$d/.claude/manifest.json"
  {
    printf '# Project Intake\n\n## 1. Basics\n\n'
    printf '| **Project name** | demo |\n| **Description** | a demo |\n'
    while [ "$i" -lt "$blanks" ]; do printf '| **Field %s** | |\n' "$i"; i=$((i + 1)); done
    printf '\n## 13. Agent Initialization Prompt\n\n```\nG2-GREENFIELD-S13-SENTINEL: read the intake, then begin Phase 0.\n```\n'
  } > "$d/PROJECT_INTAKE.md"
  [ "$man" = "yes" ] && printf '# Product Manifesto — demo\n' > "$d/PRODUCT_MANIFESTO.md"
  return 0
}

# _resume SCRIPT DIR — install SCRIPT as DIR's own scripts/resume.sh, run it as a
# user does. Sets OUT and RC.
OUT=""; RC=0
_resume() {
  cp "$1" "$2/scripts/resume.sh" || { OUT="(could not install the script)"; RC=99; return 0; }
  OUT="$( cd "$2" && bash scripts/resume.sh </dev/null 2>&1 )"; RC=$?
  return 0
}
_has()    { printf '%s\n' "$OUT" | grep -qF -- "$1"; }
_count()  { printf '%s\n' "$OUT" | grep -cF -- "$1"; }
_line()   { printf '%s\n' "$OUT" | grep -qxF -- "$1"; }
_lead()   { printf '%s\n' "$OUT" | grep -q "^$1"; }
_block()  { printf '%s\n' "$OUT" | awk '/^--- Copy everything below/{f=1; next} /^--- End/{f=0} f' | sed '/./,$!d'; }
_s13()    { awk '/^## 13\./{s=1} s && /^```/{c++; next} s && c==1' "$1/PROJECT_INTAKE.md"; }
_classic_labels_absent() {   # none of the four field lines is printed
  local l=""
  for l in 'Features built' 'Features remaining' 'Known issues' 'Last session'; do
    _lead "\*\*$l:\*\*" && WHY="$WHY [a '$l' line was printed]"
  done
  return 0
}

# ── build the fixtures ───────────────────────────────────────────────────────
ADOPTED="$WORK/adopted"
UNASSESSED="$WORK/unassessed"
NOMAN="$WORK/assessed-no-manifesto"
PHASE1="$WORK/assessed-phase1"
SETUP_OK=1
if ! _adopt "$ADOPTED" || ! jq -e '.adoption.adopted == true' "$ADOPTED/.claude/manifest.json" >/dev/null 2>&1; then
  fail_ "setup" "the adoption did not complete: $(tail -3 "$WORK/adopt.out" | tr '\n' '|')"; SETUP_OK=0
else
  chmod -x "$ADOPTED/scripts/check-versions.sh" 2>/dev/null || true
  cp -R "$ADOPTED" "$UNASSESSED"
  if ! _assess "$ADOPTED" || ! jq -e '.adoption.assessment != null' "$ADOPTED/.claude/manifest.json" >/dev/null 2>&1; then
    fail_ "setup" "the Act 4 finisher did not record the assessment: $(tail -3 "$WORK/act4.out" | tr '\n' '|')"; SETUP_OK=0
  else
    # The k-pdf shape: adopted, assessed, phase 0, and its own manifesto still there.
    [ -f "$ADOPTED/PRODUCT_MANIFESTO.md" ] || { fail_ "setup" "adoption removed the project's own PRODUCT_MANIFESTO.md — the fixture no longer has the k-pdf shape"; SETUP_OK=0; }
    cp -R "$ADOPTED" "$NOMAN"; rm -f "$NOMAN/PRODUCT_MANIFESTO.md"
    cp -R "$ADOPTED" "$PHASE1"
    jq '.current_phase = 1' "$PHASE1/.claude/phase-state.json" > "$WORK/ps.json" && mv "$WORK/ps.json" "$PHASE1/.claude/phase-state.json"
  fi
fi

GF_MAN="$WORK/gf-manifesto";    _greenfield "$GF_MAN" yes 0
GF_NOMAN="$WORK/gf-no-manifesto"; _greenfield "$GF_NOMAN" no 0
GF_INTAKE="$WORK/gf-intake";    _greenfield "$GF_INTAKE" no 25
C2D="$WORK/c2"; _greenfield "$C2D" yes 0
# The addendum's format (docs/cli-setup-addendum.md "## Current State"), appended
# AFTER the framework's own Context Health Check bullet, as a user following the
# addendum would: the first line that names the words is the wrong one.
{
  printf '# CLAUDE.md — demo\n\n## Operating Instructions\n\n'
  printf -- '- **Context Health Check:** Run it on signal. %s, then verify that summary against PROJECT_BIBLE.md.\n\n' "$CHC_LINE"
  printf '## Current State\n- **Project:** demo\n- **Phase:** 2\n'
  printf -- '- **Features built:** none yet\n- **Features remaining:** see MVP Cutline\n'
  printf -- '- **Known issues:** none\n- **Last session summary:** wrote the parser\n\n'
  printf 'Update this section at the end of every session.\n'
} > "$C2D/CLAUDE.md"
C3D="$WORK/c3"; _greenfield "$C3D" yes 0
printf '# CLAUDE.md — demo\n\n- **Known issues**: flaky export\n' > "$C3D/CLAUDE.md"
C4D="$WORK/c4"; _greenfield "$C4D" yes 0   # no CLAUDE.md at all

# ── the cases: each takes the script under test, sets WHY, returns 0 iff clean ─
WHY=""
case_A1() {
  local exp="" act=""
  WHY=""; _resume "$1" "$ADOPTED"
  exp="$(_s13 "$ADOPTED")"
  [ -n "$exp" ] && printf '%s\n' "$exp" | grep -qF 'THIS PROJECT WAS ADOPTED, NOT SCAFFOLDED' \
    || WHY="$WHY [the fixture's Section 13 is not adoption's — the case would prove nothing]"
  act="$(_block)"
  [ "$act" = "$exp" ] || WHY="$WHY [the printed block is not the project's Section 13 verbatim: $(printf '%s' "$act" | head -1)]"
  _has 'We are resuming work on this project' && WHY="$WHY [the classic prompt fired]"
  _has 'You are running its ASSESSMENT' && WHY="$WHY [the assessment prompt fired after the assessment]"
  [ "$RC" -eq 0 ] || WHY="$WHY [rc $RC]"
  [ -z "$WHY" ]
}
case_A2() {
  WHY=""; _resume "$1" "$UNASSESSED"
  _has 'You are running its ASSESSMENT' || WHY="$WHY [not the assessment prompt]"
  _has 'THIS PROJECT WAS ADOPTED, NOT SCAFFOLDED' && WHY="$WHY [Section 13 fired before the assessment]"
  _has 'We are resuming work on this project' && WHY="$WHY [the classic prompt fired]"
  [ -z "$WHY" ]
}
case_A3() {
  local exp=""
  WHY=""; _resume "$1" "$NOMAN"
  exp="$(_s13 "$NOMAN")"
  [ -n "$exp" ] && [ "$(_block)" = "$exp" ] || WHY="$WHY [not the project's Section 13 verbatim]"
  [ -z "$WHY" ]
}
case_G1() {
  WHY=""; _resume "$1" "$GF_MAN"
  _has 'We are resuming work on this project' || WHY="$WHY [the classic prompt did not fire]"
  _has 'G2-GREENFIELD-S13-SENTINEL' && WHY="$WHY [Section 13 fired for a greenfield project that has its manifesto]"
  [ -z "$WHY" ]
}
case_G2() {
  WHY=""; _resume "$1" "$GF_NOMAN"
  [ "$(_block)" = 'G2-GREENFIELD-S13-SENTINEL: read the intake, then begin Phase 0.' ] || WHY="$WHY [not Section 13 verbatim]"
  [ -z "$WHY" ]
}
case_G3() {
  WHY=""; _resume "$1" "$GF_INTAKE"
  _has "Help me finish this project's intake" || WHY="$WHY [not the intake first message]"
  _has 'G2-GREENFIELD-S13-SENTINEL' && WHY="$WHY [Section 13 fired over an unfinished intake]"
  [ -z "$WHY" ]
}
case_C1() {
  WHY=""
  grep -qF "$CHC_LINE" "$PHASE1/CLAUDE.md" \
    || WHY="$WHY [the framework CLAUDE.md no longer carries the line that caused the defect — this case would be vacuous]"
  _resume "$1" "$PHASE1"
  _has 'We are resuming work on this project' || WHY="$WHY [not the classic prompt]"
  [ "$(_count 'Context Health Check')" -eq 0 ] || WHY="$WHY [the Context Health Check paragraph was printed $(_count 'Context Health Check') time(s)]"
  _has 'Summarize features built' && WHY="$WHY [part of the Context Health Check line was printed as a field]"
  _has '(not found in CLAUDE.md)' && WHY="$WHY [filler: (not found in CLAUDE.md)]"
  _classic_labels_absent
  [ "$(_count "$NONE_LINE")" -eq 1 ] || WHY="$WHY [the plain line was printed $(_count "$NONE_LINE") time(s), not once]"
  _has 'Current State' && WHY="$WHY [the prompt names a Current State section CLAUDE.md does not have]"
  [ -z "$WHY" ]
}
case_C2() {
  WHY=""; _resume "$1" "$C2D"
  _line '**Features built:** none yet'         || WHY="$WHY [Features built not clean]"
  _line '**Features remaining:** see MVP Cutline' || WHY="$WHY [Features remaining not clean]"
  _line '**Known issues:** none'               || WHY="$WHY [Known issues not clean]"
  _line '**Last session:** wrote the parser'   || WHY="$WHY [Last session summary not read]"
  _has ':** **' && WHY="$WHY [a stray ** was left after a label]"
  _has 'Context Health Check' && WHY="$WHY [the Context Health Check paragraph was printed]"
  _has "$CS_SENTENCE" || WHY="$WHY [the Current State sentence is gone though the section exists]"
  _has "$NONE_LINE" && WHY="$WHY [the plain none-recorded line fired with four fields recorded]"
  _has '(not found in CLAUDE.md)' && WHY="$WHY [filler]"
  [ -z "$WHY" ]
}
case_C3() {
  WHY=""; _resume "$1" "$C3D"
  _line '**Known issues:** flaky export' || WHY="$WHY [the one recorded field was not read]"
  local l=""
  for l in 'Features built' 'Features remaining' 'Last session'; do
    _lead "\*\*$l:\*\*" && WHY="$WHY [an unrecorded '$l' line was printed]"
  done
  _has "$NONE_LINE" && WHY="$WHY [the none-recorded line fired with one field recorded]"
  _has '(not found in CLAUDE.md)' && WHY="$WHY [filler]"
  _has "$CS_SENTENCE" && WHY="$WHY [the Current State sentence fired with no such section]"
  [ -z "$WHY" ]
}
case_C4() {
  WHY=""; _resume "$1" "$C4D"
  [ "$RC" -eq 0 ] || WHY="$WHY [rc $RC]"
  _has 'End of resume prompt' || WHY="$WHY [the prompt's tail is missing]"
  [ "$(_count "$NO_CLAUDE_LINE")" -eq 1 ] || WHY="$WHY [the no-CLAUDE.md line was printed $(_count "$NO_CLAUDE_LINE") time(s), not once]"
  _has "$NONE_LINE" && WHY="$WHY [it says CLAUDE.md records nothing, as if there were one]"
  _has 'Read CLAUDE.md for full project context' && WHY="$WHY [it tells the agent to read a CLAUDE.md that does not exist]"
  _has '(not found in CLAUDE.md)' && WHY="$WHY [filler]"
  _classic_labels_absent
  [ -z "$WHY" ]
}

_run() {   # _run NAME LABEL — the case against the real script
  if [ "$SETUP_OK" -ne 1 ] && case "$1" in A*|C1) true ;; *) false ;; esac; then
    fail_ "$1 $2" "the adoption fixture was not built"; return
  fi
  if "case_$1" "$SUT"; then pass "$1 $2"; else fail_ "$1 $2" "$WHY"; fi
}

_run A1 "an assessed adoptee with its own manifesto gets its Section 13 (the Phase 0 prompt)"
_run A2 "an adoptee not yet assessed still gets the assessment prompt"
_run A3 "an assessed adoptee without a manifesto still gets its Section 13"
_run G1 "a greenfield project with its manifesto still gets the classic prompt"
_run G2 "a greenfield project without a manifesto still gets its Section 13"
_run G3 "a greenfield project with an unfinished intake still gets the intake first message"
_run C1 "the classic prompt on the framework CLAUDE.md: no repeated paragraph, no filler, one plain line"
_run C2 "the classic prompt reads the addendum's Current State fields cleanly"
_run C3 "one recorded field is printed and the others are left out"
_run C4 "no CLAUDE.md: said once, and the agent is not told to read it"

# ── mutation proofs ──────────────────────────────────────────────────────────
# _mutant NAME OLD NEW — $WORK/mut/NAME.sh is the script with the ONE occurrence
# of OLD replaced by NEW. Split on the literal, never `${v/p/r}` (an `&` in the
# replacement is the whole match on bash 5.2 and literal on 3.2 — CLAUDE.md
# ENVIRONMENT TRAPS), and the edit is proved to have LANDED by its own text.
mkdir -p "$WORK/mut"
MUT=""; MUT_WHY=""
_occurs() { OCC="$1" awk 'BEGIN { s = ENVIRON["OCC"]; n = 0 }
  { l = $0; while ((i = index(l, s)) > 0) { n++; l = substr(l, i + length(s)) } } END { print n }' "$2"; }
_mutant() {
  local name="$1" old="$2" new="$3" src="" lhs="" rhs=""
  MUT="$WORK/mut/$name.sh"; MUT_WHY=""
  [ "$(_occurs "$old" "$SUT")" = "1" ] || { MUT_WHY="the text to mutate occurs $(_occurs "$old" "$SUT") time(s) in scripts/resume.sh, not once: $old"; return 1; }
  src="$(cat "$SUT"; printf x)"; src="${src%x}"
  lhs="${src%%"$old"*}"; rhs="${src#*"$old"}"
  printf '%s%s%s' "$lhs" "$new" "$rhs" > "$MUT"
  [ "$(_occurs "$new" "$MUT")" -ge 1 ] && [ "$(_occurs "$old" "$MUT")" = "0" ] \
    || { MUT_WHY="the mutation did not land"; return 1; }
  bash -n "$MUT" 2>/dev/null || { MUT_WHY="the mutant does not parse — an unrunnable mutant proves nothing"; return 1; }
  return 0
}
_kill() {   # _kill NAME KILLER OLD NEW WHAT
  local name="$1" killer="$2" old="$3" new="$4" what="$5"
  if [ "$SETUP_OK" -ne 1 ]; then fail_ "$name $what" "the adoption fixture was not built"; return; fi
  if ! _mutant "$name" "$old" "$new"; then fail_ "$name $what" "$MUT_WHY"; return; fi
  if "case_$killer" "$MUT"; then
    fail_ "$name $what" "SURVIVED: $killer still passes against the mutant"
  else
    pass "$name $what — killed by $killer:$WHY"
  fi
}

_kill M1 A1 'if [ ! -f "PRODUCT_MANIFESTO.md" ] || [ -n "$bl318_adoptee" ]; then' \
            'if [ ! -f "PRODUCT_MANIFESTO.md" ]; then' \
            "the adoptee route removed (# BL-318-G2-ADOPTEE-PHASE0)"
_kill M2 G1 'bl318_adoptee=""' 'bl318_adoptee=1' \
            "every project treated as an adoptee"
_kill M3 G1 "jq -e '.adoption.adopted == true' .claude/manifest.json" "jq -e '.' .claude/manifest.json" \
            "the route keyed on the manifest's presence, not the adoption stamp"
_kill M4 C1 '"[*_]*[ \t]*:[*_]*[ \t]*"' '"[*_]*[ \t]*:?[*_]*[ \t]*"' \
            "a field read from a line with no colon after its label (# BL-318-G2-FIELD-LABEL)"
_kill M5 C2 '"[*_]*[ \t]*:[*_]*[ \t]*"' '"[*_]*[ \t]*:[ \t]*"' \
            "the bold closer after the colon kept in the value"
_kill M6 C3 '"[*_]*[ \t]*:[*_]*[ \t]*"' '"[ \t]*:[*_]*[ \t]*"' \
            "a label bolded before its colon not read"
_kill M7 C2 "'last session( summary)?'" "'last session'" \
            "'Last session summary:' not read"
_kill M8 C3 '[ -n "$2" ] || return 0' ':' \
            "an unrecorded field printed empty (# BL-318-G2-FIELD-OMIT)"
_kill M9 C1 'elif [ -z "$STATE_FIELDS" ]; then' 'elif false; then' \
            "the one plain line when nothing is recorded removed (# BL-318-G2-FIELDS-NONE)"
_kill M10 C4 'if [ ! -f "CLAUDE.md" ]; then   # BL-318-G2-NO-CLAUDE-FIELDS' 'if false; then   # BL-318-G2-NO-CLAUDE-FIELDS' \
            "no CLAUDE.md: the plain line removed"
_kill M11 C4 'if [ ! -f "CLAUDE.md" ]; then   # BL-318-G2-NO-CLAUDE-CLOSING' 'if false; then   # BL-318-G2-NO-CLAUDE-CLOSING' \
            "no CLAUDE.md: the agent told to read it anyway"
_kill M12 C1 "elif grep -qiE '^#+[[:space:]]*current state' CLAUDE.md 2>/dev/null; then" 'elif true; then' \
            "the Current State sentence printed with no such section (# BL-318-G2-CURRENT-STATE)"
_kill M13 C2 "elif grep -qiE '^#+[[:space:]]*current state' CLAUDE.md 2>/dev/null; then" 'elif false; then' \
            "the Current State sentence dropped though the section exists"

echo ""
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
