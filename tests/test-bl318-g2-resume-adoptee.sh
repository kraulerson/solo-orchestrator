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
#     that file, so an adoptee built with an older Solo still has its own and
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
#     project whose PRODUCT_MANIFESTO.md is still byte-identical to the one in
#     the commit adoption was anchored on (the stamp's adoptedAtCommit) has not
#     started Phase 0, so it gets Section 13. current_phase stays 0 for all of
#     Phase 0 (review round 1, R-G2-1: the first cut keyed on the stamp alone and
#     sent EVERY adoptee back to "run Phase 0 from the beginning" at every
#     session). A manifesto Phase 0 wrote, or rewrote, resumes as the classic
#     prompt, as for a greenfield project. `# BL-318-G2-ANCHOR` guards an empty
#     anchor (which would read the index). An adoptee not yet assessed never
#     reaches it: the assessment branch (`# BL-242-RESUME-ASSESSMENT`) exits
#     first (A2 pins that order).
#   - `# BL-318-G2-FIELD-LABEL`: a field is read only from a "Label:" line, the
#     shape the CLI setup addendum's "## Current State" bullets use.
#   - `# BL-318-G2-FIELD-OMIT`, `# BL-318-G2-FIELDS-NONE`: a field CLAUDE.md
#     does not record is left out; when none is recorded, one plain line says
#     so — or, when CLAUDE.md has a "Current State" section holding them in
#     another shape, a pointer to it (`# BL-318-G2-FIELDS-IN-SECTION`).
#     `# BL-318-G2-NO-CLAUDE-FIELDS` / `# BL-318-G2-NO-CLAUDE-CLOSING` cover a
#     project with no CLAUDE.md at all.
#   - `# BL-318-G2-CURRENT-STATE`: the "Current State section is stale"
#     sentence is printed only when CLAUDE.md has such a HEADING.
# AND THE SESSION-START HOOK (scripts/session-intake-check.sh), which used the
# same manifesto test: an adoptee whose assessment is pending is pointed at the
# assessment prompt resume.sh prints (`# BL-318-G2-HOOK-ASSESSMENT`), and one
# whose brought manifesto is untouched is told Phase 0 has not started
# (`# BL-318-G2-HOOK-BROUGHT`). Greenfield output is pinned to the bytes it had
# before (HG1-HG3: digests measured from the hook at f5b1671).
#
# FIXTURES. Two REAL adoptions (scripts/adopt-project.sh) of tiny projects — one
# that carries its own PRODUCT_MANIFESTO.md and an old-style CLAUDE.md, one
# that carries none — then the REAL Act 4 finisher on a hand-written record, the
# route tests/test-brownfield-wp12a-assessment.sh takes, so the state is what
# adoption writes, not a guess at it. Greenfield fixtures are hand-built (no
# init.sh, so this suite stays in the unit lane). Every resume.sh run installs
# the script under test as the fixture's own scripts/resume.sh and runs it as a
# user does; check-versions.sh is made non-executable in the adopted fixtures,
# so no run reaches the network. The hook is standalone and runs from its path.
#
# CASES (resume.sh)
#   A1  adoptee, assessed, its own manifesto untouched -> its Section 13 verbatim
#   A2  adoptee, NOT assessed, its own manifesto -> the assessment prompt (unchanged)
#   A3  adoptee, assessed, no manifesto brought or written -> Section 13 (unchanged)
#   A4  A3 after Phase 0 drafted and committed a manifesto -> the classic prompt
#   A5  A1 after Phase 0 edited the brought manifesto -> the classic prompt
#   A6  A4 with a stamp that carries no anchor -> the classic prompt (never the index)
#   A7  A3 with a drafted manifesto git cannot read -> the classic prompt (skipped as root)
#   A8  A1 with a stamp that says adopted: false -> the classic prompt
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
#   C5  a "## Current State" holding its fields as a table and nested bullets:
#       a pointer to the section, never "does not record" (review R-G2-3)
#   C6  two "Known issues:" lines (the first, trailing spaces trimmed), a bare
#       "Last session:" line, and "current state" in prose with no heading
#       (review R-G2-4)
# CASES (the hook)
#   H1  an adoptee not yet assessed, with and without a manifesto -> the
#       assessment, never "READY FOR PHASE 0"
#   H2  A1's state -> READY FOR PHASE 0, naming the untouched brought manifesto
#   H3  A3's state -> READY FOR PHASE 0 as before
#   H4-H8  the A4, A5, A6, A7, A8 states -> silent, as before
#   HG1-HG3  greenfield: unfinished intake, ready, manifesto present — the
#       decoded output equal to the pre-change hook's, plain and startup
#   M*, X*, HM*  a mutant for every guard, each killed by a named case
set -uo pipefail
# The adoption driver's MCP step can ask a question and run `claude mcp add`;
# this suite pipes answers written without it (`# BL-311-MCP-SEAM`).
export SOIF_ADOPT_MCP=off

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT="$REPO_ROOT/scripts/resume.sh"
HOOK="$REPO_ROOT/scripts/session-intake-check.sh"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

echo "== BL-318 G2 — resume.sh and the session-start hook after an adoption, and the classic prompt's fields =="

for t in git jq; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done

WORK="$(mktemp -d)" || exit 1
trap 'chmod -R u+rwX "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

# Root reads a mode-000 file, so A7 cannot be built as root.
IS_ROOT=""; [ "$(id -u)" = "0" ] && IS_ROOT=1

# The plain lines the fix prints. Spelled once here so a case and its mutant
# read the same text.
NONE_LINE='CLAUDE.md does not record what has been built, what remains, the known issues or where the last session stopped'
IN_SECTION_LINE='CLAUDE.md has a "Current State" section: read it for what has been built'
NO_CLAUDE_LINE='There is no CLAUDE.md in this project'
CS_SENTENCE='If CLAUDE.md'"'"'s "Current State" section is stale or incomplete'
CHC_LINE='Summarize features built, features remaining, current data model, and known issues'
S13_MARK='THIS PROJECT WAS ADOPTED, NOT SCAFFOLDED'
CLASSIC_MARK='We are resuming work on this project'

# ── fixtures ─────────────────────────────────────────────────────────────────
# _adopt DIR yes|no — a real adoption; "yes" brings a manifesto and an
# old-style CLAUDE.md, as a project built with an older Solo does.
_adopt() {
  local p="$1" brought="$2" files="package.json README.md"
  mkdir -p "$p/src" || return 1
  ( cd "$p" && git init -q . && git config user.email g2@test.invalid && git config user.name "G2 Test" ) >/dev/null 2>&1 || return 1
  printf '{"name":"acme","scripts":{"test":"exit 0"}}\n' > "$p/package.json"
  printf '# acme\n' > "$p/README.md"
  if [ "$brought" = "yes" ]; then
    printf '# Product Manifesto — acme\n\n## 1. Product Intent\n\nWritten with an older Solo, before adoption.\n' > "$p/PRODUCT_MANIFESTO.md"
    printf '# CLAUDE.md — acme\n\n## Current State\n- **Features built:** the parser\n- **Last session summary:** shipped 1.2\n' > "$p/CLAUDE.md"
    files="$files PRODUCT_MANIFESTO.md CLAUDE.md"
  fi
  # shellcheck disable=SC2086
  ( cd "$p" && git add $files && git commit -q --no-verify -m "chore: their history" ) >/dev/null 2>&1 || return 1
  printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n' > "$WORK/ans"
  ( cd "$p" && bash "$REPO_ROOT/scripts/adopt-project.sh" < "$WORK/ans" ) > "$WORK/adopt.out" 2>&1 || return 1
  chmod -x "$p/scripts/check-versions.sh" 2>/dev/null || true
  return 0
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
# _draft DIR commit|nocommit — Phase 0 writes PRODUCT_MANIFESTO.md.
_draft() {
  printf '# Product Manifesto — acme\n\n## 1. Product Intent\n\nDrafted in Phase 0.\n' > "$1/PRODUCT_MANIFESTO.md"
  [ "$2" = "commit" ] || return 0
  ( cd "$1" && git add PRODUCT_MANIFESTO.md && git commit -q --no-verify -m "docs: draft the manifesto" ) >/dev/null 2>&1
}
# _stamp DIR JQ — edit the adoption stamp (states no adoption writes; A6, A8).
_stamp() { jq "$2" "$1/.claude/manifest.json" > "$WORK/m.json" && mv "$WORK/m.json" "$1/.claude/manifest.json"; }
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
# _hook SCRIPT DIR [ENVELOPE] — run the session-start hook. Sets OUT and RC.
_hook() {
  if [ -n "${3:-}" ]; then
    OUT="$( cd "$2" && printf '%s' "$3" | bash "$1" 2>&1 )"; RC=$?
  else
    OUT="$( cd "$2" && bash "$1" </dev/null 2>&1 )"; RC=$?
  fi
  return 0
}
_ctx()    { printf '%s\n' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }
_msg()    { printf '%s\n' "$OUT" | jq -r '.hookSpecificOutput.initialUserMessage // empty' 2>/dev/null; }
_digest() { printf '%s\n' "$OUT" | jq -r '.hookSpecificOutput | (keys | join(",")), .additionalContext, (.initialUserMessage // "-")' 2>/dev/null | shasum -a 256 | cut -c1-64; }
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
ADOPTED="$WORK/brought"            # A1: brought a manifesto, assessed, untouched
UNASSESSED="$WORK/brought-unassessed"
EDITED="$WORK/brought-edited"      # A5
FALSE_STAMP="$WORK/brought-adopted-false"   # A8
PHASE1="$WORK/brought-phase1"      # C1
BARE="$WORK/bare"                  # A3: brought none, assessed
BARE_UNASSESSED="$WORK/bare-unassessed"
DRAFTED="$WORK/bare-drafted"       # A4
NO_ANCHOR="$WORK/bare-drafted-no-anchor"    # A6
UNREADABLE="$WORK/bare-drafted-unreadable"  # A7
SETUP_OK=1
_setup_fail() { fail_ "setup" "$1"; SETUP_OK=0; }
if ! _adopt "$ADOPTED" yes || ! jq -e '.adoption.adopted == true' "$ADOPTED/.claude/manifest.json" >/dev/null 2>&1; then
  _setup_fail "the adoption that brings a manifesto did not complete: $(tail -3 "$WORK/adopt.out" | tr '\n' '|')"
elif ! { cp -R "$ADOPTED" "$UNASSESSED" && _assess "$ADOPTED" \
         && jq -e '.adoption.assessment != null' "$ADOPTED/.claude/manifest.json" >/dev/null 2>&1; }; then
  _setup_fail "the Act 4 finisher did not record the assessment: $(tail -3 "$WORK/act4.out" | tr '\n' '|')"
fi
if [ "$SETUP_OK" -eq 1 ]; then
  # The k-pdf shape: the anchor holds the manifesto adoption found, and the file
  # is still that one. Checked, so A1 cannot pass by accident.
  a_anchor="$(jq -r '.adoption.adoptedAtCommit' "$ADOPTED/.claude/manifest.json")"
  [ -n "$(cd "$ADOPTED" && git rev-parse -q --verify "${a_anchor}:PRODUCT_MANIFESTO.md" 2>/dev/null)" ] \
    || _setup_fail "adoptedAtCommit ($a_anchor) does not hold the brought PRODUCT_MANIFESTO.md"
  [ -f "$ADOPTED/PRODUCT_MANIFESTO.md" ] || _setup_fail "adoption removed the project's own PRODUCT_MANIFESTO.md"
  cp -R "$ADOPTED" "$EDITED";      printf '\nEdited in Phase 0.\n' >> "$EDITED/PRODUCT_MANIFESTO.md"
  cp -R "$ADOPTED" "$FALSE_STAMP"; _stamp "$FALSE_STAMP" '.adoption.adopted = false'
  cp -R "$ADOPTED" "$PHASE1";      jq '.current_phase = 1' "$PHASE1/.claude/phase-state.json" > "$WORK/ps.json" && mv "$WORK/ps.json" "$PHASE1/.claude/phase-state.json"
fi
if ! _adopt "$BARE" no || ! jq -e '.adoption.adopted == true' "$BARE/.claude/manifest.json" >/dev/null 2>&1; then
  _setup_fail "the adoption that brings no manifesto did not complete: $(tail -3 "$WORK/adopt.out" | tr '\n' '|')"
elif ! { cp -R "$BARE" "$BARE_UNASSESSED" && _assess "$BARE" \
         && jq -e '.adoption.assessment != null' "$BARE/.claude/manifest.json" >/dev/null 2>&1; }; then
  _setup_fail "the Act 4 finisher did not record the second assessment: $(tail -3 "$WORK/act4.out" | tr '\n' '|')"
else
  cp -R "$BARE" "$DRAFTED";    _draft "$DRAFTED" commit || _setup_fail "could not commit the drafted manifesto"
  cp -R "$DRAFTED" "$NO_ANCHOR"; _stamp "$NO_ANCHOR" 'del(.adoption.adoptedAtCommit)'
  cp -R "$BARE" "$UNREADABLE"; _draft "$UNREADABLE" nocommit; chmod 000 "$UNREADABLE/PRODUCT_MANIFESTO.md"
fi

GF_MAN="$WORK/gf-manifesto";      _greenfield "$GF_MAN" yes 0
GF_NOMAN="$WORK/gf-no-manifesto"; _greenfield "$GF_NOMAN" no 0
GF_INTAKE="$WORK/gf-intake";      _greenfield "$GF_INTAKE" no 25
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
C5D="$WORK/c5"; _greenfield "$C5D" yes 0
# A "## Current State" whose fields are a table and nested bullets: no
# "Label: value" line to read (a label with its value on the next line reads as
# empty), so nothing is printed as a field.
{
  printf '# CLAUDE.md — demo\n\n## Current State\n\n'
  printf '| Field | Value |\n|---|---|\n| Features built | parser, exporter |\n| Known issues | none |\n\n'
  printf -- '- **Features remaining:**\n  - search\n- **Last session**\n  - wrote the exporter\n'
} > "$C5D/CLAUDE.md"
C6D="$WORK/c6"; _greenfield "$C6D" yes 0
{
  printf '# CLAUDE.md — demo\n\nKeep the current state of the work in BUGS.md and FEATURES.md.\n\n'
  printf -- '- **Known issues:** flaky export   \n'
  printf -- '- **Known issues:** a second, older line\n'
  printf -- '- **Last session:** wrote the exporter\n'
} > "$C6D/CLAUDE.md"

# ── the cases: each takes the script under test, sets WHY, returns 0 iff clean ─
WHY=""
_expect_s13() {   # DIR — the project's Section 13, verbatim, and nothing else
  local exp="" act=""
  exp="$(_s13 "$1")"
  [ -n "$exp" ] || WHY="$WHY [the fixture's Section 13 is empty — the case would prove nothing]"
  act="$(_block)"
  [ "$act" = "$exp" ] || WHY="$WHY [the printed block is not the project's Section 13 verbatim: $(printf '%s' "$act" | head -1)]"
  _has "$CLASSIC_MARK" && WHY="$WHY [the classic prompt fired]"
  _has 'You are running its ASSESSMENT' && WHY="$WHY [the assessment prompt fired after the assessment]"
  [ "$RC" -eq 0 ] || WHY="$WHY [rc $RC]"
  return 0
}
_expect_classic() {   # the classic prompt, not Section 13
  _has "$CLASSIC_MARK" || WHY="$WHY [not the classic prompt: $(_block | head -1)]"
  _has "$S13_MARK" && WHY="$WHY [Section 13 fired: Phase 0 would start again from the beginning]"
  [ "$RC" -eq 0 ] || WHY="$WHY [rc $RC]"
  return 0
}
case_A1() {
  WHY=""; _resume "$1" "$ADOPTED"
  _s13 "$ADOPTED" | grep -qF "$S13_MARK" || WHY="$WHY [the fixture's Section 13 is not adoption's]"
  _expect_s13 "$ADOPTED"; [ -z "$WHY" ]
}
case_A2() {
  WHY=""; _resume "$1" "$UNASSESSED"
  _has 'You are running its ASSESSMENT' || WHY="$WHY [not the assessment prompt]"
  _has "$S13_MARK" && WHY="$WHY [Section 13 fired before the assessment]"
  _has "$CLASSIC_MARK" && WHY="$WHY [the classic prompt fired]"
  [ -z "$WHY" ]
}
case_A3() { WHY=""; _resume "$1" "$BARE"; _expect_s13 "$BARE"; [ -z "$WHY" ]; }
case_A4() { WHY=""; _resume "$1" "$DRAFTED"; _expect_classic; [ -z "$WHY" ]; }
case_A5() { WHY=""; _resume "$1" "$EDITED"; _expect_classic; [ -z "$WHY" ]; }
case_A6() { WHY=""; _resume "$1" "$NO_ANCHOR"; _expect_classic; [ -z "$WHY" ]; }
case_A7() { WHY=""; _resume "$1" "$UNREADABLE"; _expect_classic; [ -z "$WHY" ]; }
case_A8() { WHY=""; _resume "$1" "$FALSE_STAMP"; _expect_classic; [ -z "$WHY" ]; }
case_G1() {
  WHY=""; _resume "$1" "$GF_MAN"
  _has "$CLASSIC_MARK" || WHY="$WHY [the classic prompt did not fire]"
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
  _has "$CLASSIC_MARK" || WHY="$WHY [not the classic prompt]"
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
  _line '**Features built:** none yet'            || WHY="$WHY [Features built not clean]"
  _line '**Features remaining:** see MVP Cutline' || WHY="$WHY [Features remaining not clean]"
  _line '**Known issues:** none'                  || WHY="$WHY [Known issues not clean]"
  _line '**Last session:** wrote the parser'      || WHY="$WHY [Last session summary not read]"
  _has ':** **' && WHY="$WHY [a stray ** was left after a label]"
  _has 'Context Health Check' && WHY="$WHY [the Context Health Check paragraph was printed]"
  _has "$CS_SENTENCE" || WHY="$WHY [the Current State sentence is gone though the section exists]"
  _has "$NONE_LINE" && WHY="$WHY [the plain none-recorded line fired with four fields recorded]"
  _has "$IN_SECTION_LINE" && WHY="$WHY [the section pointer fired with four fields read]"
  _has '(not found in CLAUDE.md)' && WHY="$WHY [filler]"
  [ -z "$WHY" ]
}
case_C3() {
  local l=""
  WHY=""; _resume "$1" "$C3D"
  _line '**Known issues:** flaky export' || WHY="$WHY [the one recorded field was not read]"
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
case_C5() {
  WHY=""; _resume "$1" "$C5D"
  [ "$(_count "$IN_SECTION_LINE")" -eq 1 ] || WHY="$WHY [the pointer to the Current State section was printed $(_count "$IN_SECTION_LINE") time(s), not once]"
  _has "$NONE_LINE" && WHY="$WHY [it says CLAUDE.md does not record the fields its Current State section holds]"
  _has "$CS_SENTENCE" || WHY="$WHY [the Current State sentence is gone though the section exists]"
  _classic_labels_absent
  [ -z "$WHY" ]
}
case_C6() {
  WHY=""; _resume "$1" "$C6D"
  _line '**Known issues:** flaky export' || WHY="$WHY [Known issues is not the first line's value, trimmed]"
  _has 'a second, older line' && WHY="$WHY [a second Known issues line was printed]"
  _line '**Last session:** wrote the exporter' || WHY="$WHY [a bare 'Last session:' line was not read]"
  _has "$CS_SENTENCE" && WHY="$WHY [the Current State sentence fired for the words in prose, with no heading]"
  _has "$IN_SECTION_LINE" && WHY="$WHY [the section pointer fired with no such section]"
  _has "$NONE_LINE" && WHY="$WHY [the none-recorded line fired with fields recorded]"
  [ -z "$WHY" ]
}

# The hook. HG digests: the decoded output of scripts/session-intake-check.sh at
# f5b1671 (before this change) on these exact greenfield fixtures.
HG1_PLAIN=fad9a54f6c2bb35a58e47e70516bcaa04a4600a38f5a72941fc49f0522e421eb
HG1_START=c5cdeb67cb376898d9b2b9da72bd41e30d4f3a216dbff5b1dafb85dc9f56e250
HG2_PLAIN=a6c6fe5f7a0235bad3f5a846893e6a7a4849a09a0c717839213bd6827d2d1887
HG2_START=db5d675646ec6f1e1034ee7b8acae8980d28aa73eacb9cc89dbb6ec0b7c313cf
STARTUP='{"source":"startup"}'
case_H1() {
  local d=""
  WHY=""
  for d in "$UNASSESSED" "$BARE_UNASSESSED"; do
    _hook "$1" "$d" "$STARTUP"
    _ctx | grep -qF 'ADOPTION ASSESSMENT PENDING' || WHY="$WHY [$(basename "$d"): not pointed at the assessment: $(_ctx | head -1)]"
    _ctx | grep -qF 'READY FOR PHASE 0' && WHY="$WHY [$(basename "$d"): told Phase 0 is ready before the assessment]"
    _msg | grep -qF 'assessment prompt' || WHY="$WHY [$(basename "$d"): the first message does not ask for the assessment prompt]"
  done
  [ -z "$WHY" ]
}
case_H2() {
  WHY=""; _hook "$1" "$ADOPTED" "$STARTUP"
  _ctx | grep -qF 'READY FOR PHASE 0' || WHY="$WHY [silent or wrong for an untouched brought manifesto: $(printf '%s' "$OUT" | head -c 120)]"
  _ctx | grep -qF 'still the one the project had when it was adopted' || WHY="$WHY [the reason does not name the brought manifesto]"
  _msg | grep -qF 'Phase 0 first prompt' || WHY="$WHY [no Phase 0 first message]"
  [ -z "$WHY" ]
}
case_H3() {
  WHY=""; _hook "$1" "$BARE" "$STARTUP"
  _ctx | grep -qF 'Phase 0 has not started yet (no PRODUCT_MANIFESTO.md)' || WHY="$WHY [not the unchanged READY text: $(_ctx | head -1)]"
  [ -z "$WHY" ]
}
_hook_silent() {   # SCRIPT DIR
  WHY=""; _hook "$1" "$2" "$STARTUP"
  [ -z "$OUT" ] || WHY="$WHY [spoke where Phase 0 has started: $(printf '%s' "$OUT" | head -c 160)]"
  [ "$RC" -eq 0 ] || WHY="$WHY [rc $RC]"
  [ -z "$WHY" ]
}
case_H4() { _hook_silent "$1" "$DRAFTED"; }
case_H5() { _hook_silent "$1" "$EDITED"; }
case_H6() { _hook_silent "$1" "$NO_ANCHOR"; }
case_H7() { _hook_silent "$1" "$UNREADABLE"; }
case_H8() { _hook_silent "$1" "$FALSE_STAMP"; }
case_HG1() {
  WHY=""
  _hook "$1" "$GF_INTAKE";            [ "$(_digest)" = "$HG1_PLAIN" ] || WHY="$WHY [plain differs: $(_ctx | head -1)]"
  _hook "$1" "$GF_INTAKE" "$STARTUP"; [ "$(_digest)" = "$HG1_START" ] || WHY="$WHY [startup differs: $(_msg)]"
  [ -z "$WHY" ]
}
case_HG2() {
  WHY=""
  _hook "$1" "$GF_NOMAN";            [ "$(_digest)" = "$HG2_PLAIN" ] || WHY="$WHY [plain differs: $(_ctx | sed -n 3p)]"
  _hook "$1" "$GF_NOMAN" "$STARTUP"; [ "$(_digest)" = "$HG2_START" ] || WHY="$WHY [startup differs: $(_ctx | sed -n 3p)]"
  [ -z "$WHY" ]
}
case_HG3() {
  WHY=""
  _hook "$1" "$GF_MAN";            [ -z "$OUT" ] || WHY="$WHY [plain: spoke]"
  _hook "$1" "$GF_MAN" "$STARTUP"; [ -z "$OUT" ] || WHY="$WHY [startup: spoke]"
  [ -z "$WHY" ]
}

_needs_root_free() { case "$1" in A7|H7) [ -n "$IS_ROOT" ] ;; *) false ;; esac; }
_needs_adoption()  { case "$1" in A*|C1|H[1-8]) true ;; *) false ;; esac; }
_run() {   # _run NAME SCRIPT LABEL — the case against the real script
  if _needs_root_free "$1"; then skip "$1 $3" "running as root, which reads a mode-000 file"; return; fi
  if [ "$SETUP_OK" -ne 1 ] && _needs_adoption "$1"; then fail_ "$1 $3" "the adoption fixtures were not built"; return; fi
  if "case_$1" "$2"; then pass "$1 $3"; else fail_ "$1 $3" "$WHY"; fi
}

_run A1 "$SUT" "an assessed adoptee whose brought manifesto is untouched gets its Section 13 (the Phase 0 prompt)"
_run A2 "$SUT" "an adoptee not yet assessed still gets the assessment prompt"
_run A3 "$SUT" "an assessed adoptee with no manifesto still gets its Section 13"
_run A4 "$SUT" "an adoptee whose Phase 0 drafted a manifesto resumes with the classic prompt"
_run A5 "$SUT" "an adoptee whose Phase 0 edited its brought manifesto resumes with the classic prompt"
_run A6 "$SUT" "a stamp with no anchor is never compared against the index"
_run A7 "$SUT" "a manifesto git cannot read is not taken for the brought one"
_run A8 "$SUT" "a stamp that says adopted: false is not an adoptee"
_run G1 "$SUT" "a greenfield project with its manifesto still gets the classic prompt"
_run G2 "$SUT" "a greenfield project without a manifesto still gets its Section 13"
_run G3 "$SUT" "a greenfield project with an unfinished intake still gets the intake first message"
_run C1 "$SUT" "the classic prompt on the framework CLAUDE.md: no repeated paragraph, no filler, one plain line"
_run C2 "$SUT" "the classic prompt reads the addendum's Current State fields cleanly"
_run C3 "$SUT" "one recorded field is printed and the others are left out"
_run C4 "$SUT" "no CLAUDE.md: said once, and the agent is not told to read it"
_run C5 "$SUT" "a Current State section in another shape is pointed at, not called empty"
_run C6 "$SUT" "the first of two lines, trimmed; a bare Last session line; prose is not a heading"
_run H1 "$HOOK" "the hook points an unassessed adoptee at the assessment, with or without a manifesto"
_run H2 "$HOOK" "the hook says Phase 0 is ready for an untouched brought manifesto"
_run H3 "$HOOK" "the hook is unchanged for an assessed adoptee with no manifesto"
_run H4 "$HOOK" "the hook is silent once Phase 0 has drafted a manifesto"
_run H5 "$HOOK" "the hook is silent once Phase 0 has edited the brought manifesto"
_run H6 "$HOOK" "the hook never compares against the index for a stamp with no anchor"
_run H7 "$HOOK" "the hook does not take an unreadable manifesto for the brought one"
_run H8 "$HOOK" "the hook does not treat adopted: false as an adoptee"
_run HG1 "$HOOK" "greenfield, unfinished intake: the hook's output is what it was"
_run HG2 "$HOOK" "greenfield, ready for Phase 0: the hook's output is what it was"
_run HG3 "$HOOK" "greenfield, manifesto present: the hook is still silent"

# ── mutation proofs ──────────────────────────────────────────────────────────
# _mutant FILE NAME OLD NEW — $WORK/mut/NAME.sh is FILE with the ONE occurrence
# of OLD replaced by NEW. Split on the literal, never `${v/p/r}` (an `&` in the
# replacement is the whole match on bash 5.2 and literal on 3.2 — CLAUDE.md
# ENVIRONMENT TRAPS), and the edit is proved to have LANDED by its own text.
mkdir -p "$WORK/mut"
MUT=""; MUT_WHY=""
_occurs() { OCC="$1" awk 'BEGIN { s = ENVIRON["OCC"]; n = 0 }
  { l = $0; while ((i = index(l, s)) > 0) { n++; l = substr(l, i + length(s)) } } END { print n }' "$2"; }
_mutant() {
  local file="$1" name="$2" old="$3" new="$4" src="" lhs="" rhs=""
  MUT="$WORK/mut/$name.sh"; MUT_WHY=""
  [ "$(_occurs "$old" "$file")" = "1" ] || { MUT_WHY="the text to mutate occurs $(_occurs "$old" "$file") time(s) in $(basename "$file"), not once: $old"; return 1; }
  src="$(cat "$file"; printf x)"; src="${src%x}"
  lhs="${src%%"$old"*}"; rhs="${src#*"$old"}"
  printf '%s%s%s' "$lhs" "$new" "$rhs" > "$MUT"
  if [ -n "$new" ]; then
    [ "$(_occurs "$new" "$MUT")" -ge 1 ] || { MUT_WHY="the mutation did not land"; return 1; }
  fi
  [ "$(_occurs "$old" "$MUT")" = "0" ] || { MUT_WHY="the original text is still there"; return 1; }
  bash -n "$MUT" 2>/dev/null || { MUT_WHY="the mutant does not parse — an unrunnable mutant proves nothing"; return 1; }
  return 0
}
_kill() {   # _kill FILE NAME KILLER OLD NEW WHAT
  local file="$1" name="$2" killer="$3" old="$4" new="$5" what="$6"
  if _needs_root_free "$killer"; then skip "$name $what" "its killer $killer cannot run as root"; return; fi
  if [ "$SETUP_OK" -ne 1 ]; then fail_ "$name $what" "the adoption fixtures were not built"; return; fi
  if ! _mutant "$file" "$name" "$old" "$new"; then fail_ "$name $what" "$MUT_WHY"; return; fi
  if "case_$killer" "$MUT"; then
    fail_ "$name $what" "SURVIVED: $killer still passes against the mutant"
  else
    pass "$name $what — killed by $killer:$WHY"
  fi
}

# resume.sh — the route
_kill "$SUT" M1 A1 'if [ ! -f "PRODUCT_MANIFESTO.md" ] || [ -n "$bl318_adoptee" ]; then' \
                   'if [ ! -f "PRODUCT_MANIFESTO.md" ]; then' \
                   "the adoptee route removed (# BL-318-G2-ADOPTEE-PHASE0)"
_kill "$SUT" M2 G1 'bl318_adoptee=""' 'bl318_adoptee=1' \
                   "every project treated as an adoptee that has not started"
_kill "$SUT" M3 A4 '"${bl318_anchor}:PRODUCT_MANIFESTO.md"' '"HEAD:PRODUCT_MANIFESTO.md"' \
                   "compared with HEAD, not the adoption anchor: a committed draft reads as untouched"
_kill "$SUT" M3b A5 '[ "$bl318_then" = "$bl318_now" ]' 'true' \
                   "the manifesto's content not compared: an edited brought manifesto reads as untouched"
_kill "$SUT" M3c A6 'if [ -n "$bl318_anchor" ]; then' 'if true; then' \
                   "the empty-anchor guard removed (# BL-318-G2-ANCHOR): the index is read"
_kill "$SUT" M3d A7 '[ -n "$bl318_then" ] && ' '' \
                   "nothing-brought not required: two empty ids compare equal"
_kill "$SUT" M3e A8 "'if .adoption.adopted == true then (.adoption.adoptedAtCommit // \"\") else \"\" end'" "'(.adoption.adoptedAtCommit // \"\")'" \
                   "the adopted flag not read: a stamp that says adopted: false still counts"
# resume.sh — the classic prompt's fields
_kill "$SUT" M4 C1 '"[*_]*[ \t]*:[*_]*[ \t]*"' '"[*_]*[ \t]*:?[*_]*[ \t]*"' \
                   "a field read from a line with no colon after its label (# BL-318-G2-FIELD-LABEL)"
_kill "$SUT" M5 C2 '"[*_]*[ \t]*:[*_]*[ \t]*"' '"[*_]*[ \t]*:[ \t]*"' \
                   "the bold closer after the colon kept in the value"
_kill "$SUT" M6 C3 '"[*_]*[ \t]*:[*_]*[ \t]*"' '"[ \t]*:[*_]*[ \t]*"' \
                   "a label bolded before its colon not read"
_kill "$SUT" M7 C2 "'last session( summary)?'" "'last session'" \
                   "'Last session summary:' not read"
_kill "$SUT" M8 C3 '[ -n "$2" ] || return 0' ':' \
                   "an unrecorded field printed empty (# BL-318-G2-FIELD-OMIT)"
_kill "$SUT" M9 C1 'elif [ -z "$STATE_FIELDS" ]; then' 'elif false; then' \
                   "the one plain line when nothing is recorded removed (# BL-318-G2-FIELDS-NONE)"
_kill "$SUT" M10 C4 'if [ ! -f "CLAUDE.md" ]; then   # BL-318-G2-NO-CLAUDE-FIELDS' 'if false; then   # BL-318-G2-NO-CLAUDE-FIELDS' \
                   "no CLAUDE.md: the plain line removed"
_kill "$SUT" M11 C4 'if [ ! -f "CLAUDE.md" ]; then   # BL-318-G2-NO-CLAUDE-CLOSING' 'if false; then   # BL-318-G2-NO-CLAUDE-CLOSING' \
                   "no CLAUDE.md: the agent told to read it anyway"
_kill "$SUT" M12 C1 'CS_SECTION=""' 'CS_SECTION=1' \
                   "a Current State section assumed where there is none (# BL-318-G2-CURRENT-STATE)"
_kill "$SUT" M13 C2 "grep -qiE '^#+[[:space:]]*current state' CLAUDE.md 2>/dev/null" 'false' \
                   "a Current State section never found"
_kill "$SUT" M14 C5 'elif [ -z "$STATE_FIELDS" ] && [ -n "$CS_SECTION" ]; then' 'elif false; then' \
                   "a section in another shape called empty (# BL-318-G2-FIELDS-IN-SECTION)"
# review round 1's survivors (R-G2-4), now killed on behaviour
_kill "$SUT" X1 C6 'print v; exit' 'print v' \
                   "every matching line printed, not the first"
_kill "$SUT" X2 C6 'sub(/[ \t]+$/, "", v); ' '' \
                   "trailing spaces kept in a value"
_kill "$SUT" X3 C6 "'^#+[[:space:]]*current state'" "'current state'" \
                   "the words in prose taken for a Current State heading"
_kill "$SUT" X4 C6 "'last session( summary)?'" "'last session summary'" \
                   "a bare 'Last session:' line not read"
# the hook
_kill "$HOOK" HM1 H1 '.adoption.adopted == true and .adoption.assessment == null' 'false' \
                   "the assessment-pending check removed (# BL-318-G2-HOOK-ASSESSMENT)"
_kill "$HOOK" HM2 H2 'if [ -n "$sic_then" ] && [ "$sic_then" = "$sic_now" ]; then   # BL-318-G2-HOOK-BROUGHT' 'if false; then   # BL-318-G2-HOOK-BROUGHT' \
                   "the untouched-brought-manifesto check removed (# BL-318-G2-HOOK-BROUGHT)"
_kill "$HOOK" HM3 H4 '"${sic_anchor}:PRODUCT_MANIFESTO.md"' '"HEAD:PRODUCT_MANIFESTO.md"' \
                   "compared with HEAD, not the adoption anchor"
_kill "$HOOK" HM4 H5 '[ "$sic_then" = "$sic_now" ]' 'true' \
                   "the manifesto's content not compared"
_kill "$HOOK" HM5 H6 'if [ -n "$sic_anchor" ]; then' 'if true; then' \
                   "the empty-anchor guard removed (# BL-318-G2-HOOK-ANCHOR)"
_kill "$HOOK" HM6 H7 '[ -n "$sic_then" ] && ' '' \
                   "nothing-brought not required"
_kill "$HOOK" HM7 H8 "'if .adoption.adopted == true then (.adoption.adoptedAtCommit // \"\") else \"\" end'" "'(.adoption.adoptedAtCommit // \"\")'" \
                   "the adopted flag not read"
_kill "$HOOK" HM8 HG2 'local why="${1:-no PRODUCT_MANIFESTO.md}"' 'local why="${1:-the PRODUCT_MANIFESTO.md here is still the one the project had when it was adopted}"' \
                   "the greenfield reason replaced by the adoptee's"

echo ""
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
