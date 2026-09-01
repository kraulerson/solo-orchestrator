#!/usr/bin/env bash
# tests/test-brownfield-wp4-driver.sh
#
# Brownfield adoption WP4 — THE DRIVER: its skeleton, the scenario chooser,
# scenario placement, and reverse intake. Design:
# docs/designs/2026-08-02-brownfield-adoption-v1.md §8.1 (the driver, and why
# it is not a mode of init), §4.1 (the chooser, in Karl's exact words), §4.2
# (the scanner OFFERS evidence and does not decide), §4.3/§4.4 (S1 and S2
# landing, and THE FLOOR RULE), §4.5 (what both scenarios share), §8.3 (reverse
# intake), §8.4 (the fail-safe state-creation ORDER), §8.5 (explicit staging
# and the adoption stamp), §5.5 (a run that does not complete must be SAFE),
# §10-WP4.
#
# ── WHAT THIS FILE ASSERTS ON ───────────────────────────────────────────────
# EXIT CODES, never printed labels. In check-phase-gate.sh the `[WARN]`/`[FAIL]`
# text is cosmetic — the exit predicate is `if [ $issues -eq 0 ]`, so an
# exemption is the ABSENCE of an `issues` increment and a block is its
# presence. Printed strings appear here only as PATH DISCRIMINATORS: they prove
# WHICH path produced a code, never that a verdict was reached.
#
# ── BLOCKED FOR THE RIGHT REASON ────────────────────────────────────────────
# `pre-commit-gate.sh --emit-blocked-gate` distinguishes its two message gates
# by exit code: 3 is the BL-072 TDD-ordering block and 4 is the BL-006
# Build-Loop message check. T4 asserts 3, not "non-zero" — a post-adoption
# commit that blocked because of the Build-Loop gate would prove nothing about
# the adoption bound this WP's stamp feeds.
#
# ── MUTATION HARNESS STANDARD (all mandatory, all learned in this wave) ─────
#   • anchored end-of-line markers, excised with `s|^.*MARKER$|…|`;
#   • the anchor asserted at sites==1 in its OWN shipped source;
#   • exactly one line changed (a substitution is 2 diff lines);
#   • EVERY mutant additionally asserts `bash -n` — a mutation that lands
#     mid-continuation produces a mangled parse that reads as "caught";
#   • a MODE-PRESERVING in-place edit (a scratch `chmod` silently changed a
#     tracked file's mode twice this wave);
#   • a FRESH fixture per scenario, from `mktemp -d` and never a counter inside
#     a command substitution (a counter never survives the subshell, so every
#     scenario lands in the same directory — that is how one proof came to pass
#     against a NEIGHBOURING suite's fixture);
#   • a STRUCTURAL DISCRIMINATOR wherever the expected mutant result is an
#     ABSENCE, because "the arm did not fire" and "the mutant died" share one
#     downstream silence.
#
# ── WHY THE MUTANTS RUN AGAINST A FRAMEWORK MIRROR ──────────────────────────
# The driver is invoked from a framework clone, so a mutation cannot be made in
# a fixture-local copy the way WP3 mutated a gate script it had installed. Each
# mutation therefore copies `scripts/` and the installer into a scratch MIRROR,
# mutates the mirror, and runs the mirror's driver. The tree under test is
# never edited: a failure here cannot leave this repository mutated.
#
# Hermetic: temp dirs only, no network, no remote creation. The one thing that
# executes outside the fixture is scripts/scout.sh, which is read-only by
# construction (its own suite hashes a whole tree before and after).
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRIVER="$REPO_ROOT/scripts/adopt-project.sh"
LIB_DIR="$REPO_ROOT/scripts/lib/adopt"
L_INTAKE="$LIB_DIR/adopt-intake.sh"
L_STATE="$LIB_DIR/adopt-state.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }

_mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || printf '?\n'; }

_sed_inplace() {
  local file="$1" expr="$2" tmp mode
  mode="$(_mode_of "$file")"
  tmp="$(mktemp)"
  sed "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
  [ "$mode" != "?" ] && chmod "$mode" "$file" 2>/dev/null
  return 0
}

_changed_lines() {
  local n
  n=$(diff "$1" "$2" 2>/dev/null | grep -c '^[<>]')
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s\n' "$n"
}

_num() { case "$1" in ''|null|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac }
_parses() { bash -n "$1" >/dev/null 2>&1 && printf '1\n' || printf '0\n'; }

# _sites FILE MARKER — occurrences of an END-OF-LINE-anchored marker.
_sites() { local n; n=$(grep -c "$2\$" "$1" 2>/dev/null); _num "$n"; }

if [ ! -f "$DRIVER" ]; then
  echo "  [FAIL] setup — $DRIVER not found (WP4 deliverable 1 missing)"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

# ── The fixture ─────────────────────────────────────────────────────────────
# An adoptee that is a real git repository with real history and enough written
# down that Scout's ladder reaches rung 2 — the shape the floor rule needs, one
# rung of headroom in each direction.
mk_adoptee() {
  local p="$1"
  mkdir -p "$p/src" "$p/docs" || return 1
  ( cd "$p" \
      && git init -q . \
      && git config user.email "wp4@test.invalid" \
      && git config user.name  "WP4 Test" ) >/dev/null 2>&1 || return 1
  printf '{"name":"acme-api","scripts":{"test":"npm test"}}\n' > "$p/package.json"
  printf '# acme-api\n' > "$p/README.md"
  printf '# What this is for\n\nInvoice reconciliation for small firms.\n' > "$p/docs/product.md"
  printf '# Architecture\n\nA node service and a postgres database.\n' > "$p/docs/architecture.md"
  ( cd "$p" && git add -A && git commit -q -m "chore: their own history" ) >/dev/null 2>&1 || return 1
  return 0
}

# ── The scan report ─────────────────────────────────────────────────────────
# Produced ONCE by the real scripts/scout.sh against a template adoptee, so the
# driver is exercised against the genuine §8.2 schema and the genuine WP2
# prefill table rather than a hand-written stand-in of either. The placement
# scenarios then override `phaseMap.suggestedPhase` with jq so the floor rule
# is asserted against a KNOWN scanned rung instead of whatever the host's
# toolchain happens to make the ladder report today.
TEMPLATE="$(newtmp)/template"
REPORT=""
REPORT_OK=0
if mk_adoptee "$TEMPLATE"; then
  if bash "$REPO_ROOT/scripts/scout.sh" --root "$TEMPLATE" --out "$TOPTMP/scan" >/dev/null 2>&1; then
    REPORT="$TOPTMP/scan/scout-report.json"
    [ -s "$REPORT" ] && REPORT_OK=1
  fi
fi
if [ "$REPORT_OK" -ne 1 ]; then
  echo "  [FAIL] setup — scripts/scout.sh produced no report; WP4 consumes it and cannot be tested without one"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

# report_with_phase N — the same report with a chosen scanned rung.
report_with_phase() {
  local n="$1" out="$2"
  jq --argjson n "$n" '.phaseMap.suggestedPhase = $n' "$REPORT" > "$out" 2>/dev/null
}

# ── The answer script, and why it is FIVE lines ─────────────────────────────
# Every line is one answer, in the order the driver asks. A BLANK line is an
# unanswered question, which is exactly what an operator who walked away
# produces; running OUT of lines is an EOF, which the driver treats the same
# way. Both are supposed to reach a mandatory guard, never a default.
#
# WP9 SHORTENED THIS FROM EIGHTEEN LINES TO FIVE, and the arithmetic is the
# whole of A7 and D4: Act 2 now asks the TIER question and the four askable
# scan-derived confirmations, and nothing else. The scenario chooser, the S2
# ladder, the nine judgment sections and the data classification were all
# asked here and are asked here no longer — the first two are deleted (D4,
# D10) and the rest belong to Act 3's interview (§5.2).
#
# THE LENGTH IS LOAD-BEARING, not incidental: it is exactly long enough, so
# any mutant that puts a question back runs the run out of answers and it
# refuses. tests/test-brownfield-wp9-act-boundaries.sh N4 is built on that.
# THE DEFAULT IS 2 — ORGANIZATIONAL — AND THAT IS NOT ARBITRARY. Every fixture
# in this suite answered the audience question "2" before WP9 (it was the third
# line of the old eighteen-line script), so the tier every downstream assertion
# was written against is `organizational`. T4 and H1 in particular assert that
# the TDD arm BLOCKS rather than warns, which is a tier-dependent verdict
# (`# BL-084-TIER-KEY`): flipping the default to personal turns both green-by-
# accident into a warn and the block they exist to prove never fires.
_ans() {
  local tier="${1:-2}"
  printf '%s\n1\n1\n1\n1\n' "$tier"
}

# run_adopt DIR ANSWERFILE REPORT [HALT] [FRAMEWORK]
#
# Sets RUN_RC, RUN_OUT and RUN_ERR, and is therefore CALLED DIRECTLY, never
# inside `$( … )`. A command substitution is a subshell, so a helper that
# "returns" its transcript paths through globals loses them on the way out and
# every later grep runs against an empty variable — which greps the wrong file,
# fails, and reads as a genuine assertion failure. Measured here: fourteen
# cases failed that way on the first run.
RUN_RC=0; RUN_OUT=""; RUN_ERR=""
run_adopt() {
  local dir="$1" answers="$2" report="$3" halt="${4:-}" fw="${5:-$REPO_ROOT}"
  RUN_RC=0
  # The transcripts live BESIDE the fixture, never inside it: a scratch file in
  # the adoptee would appear in the very `git status` the staging cases read.
  RUN_OUT="$(dirname "$answers")/run-out"
  RUN_ERR="$(dirname "$answers")/run-err"
  ( cd "$dir" && SOIF_ADOPT_HALT_AFTER="$halt" bash "$fw/scripts/adopt-project.sh" \
      --scan-report "$report" ) < "$answers" > "$RUN_OUT" 2> "$RUN_ERR" || RUN_RC=$?
  return 0
}

# mk_mirror — a scratch framework the driver can be run from and mutated in.
# The installer is copied because the driver DERIVES the set of framework
# scripts an adoptee receives from init.sh's own copy list rather than
# duplicating it.
#
# LANE NOTE. The line below NAMES init.sh, which is the exemption predicate
# `# BL-181-UNIT-LANE-PREDICATE` reads — but this suite only READS that file,
# it never runs it, so it belongs in the fast unit lane and is registered
# there. The lint says so itself: "an exempted file that is in the unit list
# anyway decided nothing and is not rendered". Spelling the name plainly and
# registering the suite is the honest combination; dodging the predicate with
# a glob would hide the decision instead of making it.
mk_mirror() {
  local m="$1"
  mkdir -p "$m" || return 1
  cp -Rp "$REPO_ROOT/scripts" "$m/" || return 1
  cp -p "$REPO_ROOT/init.sh" "$m/" || return 1
  return 0
}

# gate_in DIR ARGS... — run the ADOPTEE'S OWN copy of the phase gate, from
# inside the adoptee. Sets GATE_RC and GATE_OUT; called directly, never in a
# command substitution, for the reason spelled out above run_adopt.
GATE_RC=0; GATE_OUT=""
gate_in() {
  local dir="$1"; shift
  GATE_RC=0
  # OUTSIDE the adoptee: a scratch file inside it would show up in the very
  # `git status` a staging assertion reads.
  GATE_OUT="$TOPTMP/gate-out"
  if [ ! -f "$dir/scripts/check-phase-gate.sh" ]; then
    ( cd "$dir" && bash "$REPO_ROOT/scripts/check-phase-gate.sh" "$@" ) > "$GATE_OUT" 2>&1 || GATE_RC=$?
  else
    ( cd "$dir" && bash scripts/check-phase-gate.sh "$@" ) > "$GATE_OUT" 2>&1 || GATE_RC=$?
  fi
  return 0
}

# ── Q, E AND P ARE GONE, AND THIS NOTE IS WHY ──────────────────────────────
# Q pinned Karl's chooser sentence by string equality, E pinned the evidence
# block's wording, and P pinned scenario placement and the floor rule. **D4 deleted the question and D10 deleted the
# idea of computing an answer in its place**, so both blocks asserted
# behaviour that no longer exists — and a suite that keeps them keeps a red
# check that is right about the code and wrong about the decision.
#
# THE ASSERTIONS DID NOT DISAPPEAR, THEY INVERTED. Q's string-equality pin is
# now an ABSENCE pin (the sentence occurs in no file under scripts/), and P's
# placement pin is now a landing pin (every adoption lands at phase 0, mutation
# proved). E's wording pin inverted too — the sentence it asserted was present
# ("your answer overrides all of it") is the one A6 removed, and its replacement
# asserts the four signals AND the new closing sentence AND that the old one is
# gone, with a mutation. All three live in
# tests/test-brownfield-wp9-act-boundaries.sh, sections C, E and V. This suite
# keeps everything WP4 shipped that WP9 did not overturn.

echo "=== I — reverse intake (§8.3) ==="

I1D="$(newtmp)"
if ! mk_adoptee "$I1D/p"; then
  fail_ "I1" "fixture setup failed"
else
  report_with_phase 2 "$I1D/report.json"
  _ans > "$I1D/answers"
  run_adopt "$I1D/p" "$I1D/answers" "$I1D/report.json"; i1_rc=$RUN_RC
  i1_value=0; i1_prov=0; i1_keep=0; i1_recorded=0
  grep -q 'The scan found: acme-api' "$RUN_OUT" && i1_value=1
  grep -q 'Where that came from: package.json name' "$RUN_OUT" && i1_prov=1
  grep -q "Keep 'acme-api' as the answer?" "$RUN_OUT" && i1_keep=1
  grep -q 'acme-api' "$I1D/p/PROJECT_INTAKE.md" 2>/dev/null && i1_recorded=1
  if [ "$i1_rc" -eq 0 ] && [ "$i1_value" -eq 1 ] && [ "$i1_prov" -eq 1 ] && [ "$i1_keep" -eq 1 ] && [ "$i1_recorded" -eq 1 ]; then
    pass "I1: a scan-derived answer is disclosed on TWO lines — the value AND its provenance — then offered keep-it / change-it, and 'keep it' records it"
  else
    fail_ "I1" "rc=$i1_rc value_line=$i1_value provenance_line=$i1_prov keep_change=$i1_keep recorded=$i1_recorded"
  fi
fi

I2D="$(newtmp)"
if ! mk_adoptee "$I2D/p"; then
  fail_ "I2" "fixture setup failed"
else
  report_with_phase 2 "$I2D/report.json"
  # Same script as _ans, but section 1 answers "change it" and then gives the
  # real answer — one extra line, at exactly that point.
  {
    printf '2\n'                    # the tier question
    printf '2\nledger-service\n'    # section 1: change it, then the answer
    printf '1\n1\n1\n'              # the three remaining confirmations
  } > "$I2D/answers"
  run_adopt "$I2D/p" "$I2D/answers" "$I2D/report.json"; i2_rc=$RUN_RC
  i2_fallthrough=0; i2_new=0; i2_old=0
  grep -q 'what is the right answer?' "$RUN_OUT" && i2_fallthrough=1
  grep -q 'ledger-service' "$I2D/p/PROJECT_INTAKE.md" 2>/dev/null && i2_new=1
  grep -q 'the scan had offered' "$I2D/p/PROJECT_INTAKE.md" 2>/dev/null && i2_old=1
  if [ "$i2_rc" -eq 0 ] && [ "$i2_fallthrough" -eq 1 ] && [ "$i2_new" -eq 1 ] && [ "$i2_old" -eq 1 ]; then
    pass "I2: 'change it' falls through to the ORDINARY question, records the new answer, and keeps a note of what the scan had offered"
  else
    fail_ "I2" "rc=$i2_rc fell_through=$i2_fallthrough new_value_recorded=$i2_new provenance_of_change=$i2_old"
  fi
fi

# ── I4 — the prefill read keeps the shape §8.3 warns about ──────────────────
i4_sites=$(_sites "$L_INTAKE" 'BF-ADOPT-PREFILL-READ')
i4_guard=0
grep -B1 'BF-ADOPT-PREFILL-READ$' "$L_INTAKE" 2>/dev/null | grep -qE '^[[:space:]]*:([[:space:]]|$|#)' && i4_guard=1
I4D="$(newtmp)"
cp "$L_INTAKE" "$I4D/excised.sh"
_sed_inplace "$I4D/excised.sh" 's|^.*BF-ADOPT-PREFILL-READ$||'
i4_parses=$(_parses "$I4D/excised.sh")
if [ "$i4_sites" -eq 1 ] && [ "$i4_guard" -eq 1 ] && [ "$i4_parses" -eq 1 ]; then
  pass "I4: the prefill read keeps §8.3's shape — one end-of-line-anchored marker, a bare ':' above it, and the block still parses once the marked line is excised"
else
  fail_ "I4" "marker_sites=$i4_sites (want 1) bare_colon_above=$i4_guard (want 1) parses_when_excised=$i4_parses (want 1)"
fi

# ── I3, I5, I6 AND I7 ARE GONE (A7) ────────────────────────────────────────
# I3 proved a JUDGMENT section refuses to proceed unattended; I5/I6/I7 proved
# the data classification was non-skippable, with a mutation and a positive
# control. **Act 2 asks neither class any more** (v2 §8.2 step 7): judgment
# rows are Act 3's interview and the classification is re-anchored to Act 4's
# Phase 0 intake write (§5.2).
#
# THE CLASSIFICATION PIN IS THE ONE TO ACCOUNT FOR HONESTLY, because deleting a
# guard is not the same as moving one. Its Act-2 mandate rested on a mechanical
# claim this file's sibling used to state — "an S1 adoption lands at 4, i.e.
# above the ZDR threshold on its FIRST commit" — and **D10 deleted the
# landing**. Nothing lands above phase 0, so the threshold is not in reach and
# the requirement is asserted where it now bites: WP12a's proof that the Phase 0
# intake write REFUSES without a recorded classification. Until WP12a lands,
# an adoption records no classification at all and this suite says so rather
# than pretending a deleted check still runs; the direction is fail-closed
# (phase 0, and the only route up crosses the backstop itself).
#
# What survives here is I1, I2 and I4 — the scan-derived confirmation arm and
# the prefill read's shape — which A7 did not touch.

echo "=== S — the fail-safe state-creation order (§8.4, §5.5) ==="

s1_order="$( . "$L_STATE" >/dev/null 2>&1; _adopt_state_order | tr '\n' ' ' )"
s1_sites=$(_sites "$L_STATE" 'BF-ADOPT-STATE-ORDER')
if [ "$s1_order" = "phase_state intake manifest " ] && [ "$s1_sites" -eq 1 ]; then
  pass "S1: the order is §8.4's, spelled once as data — phase_state, intake, manifest"
else
  fail_ "S1" "order=[$s1_order] (want 'phase_state intake manifest ') sites=$s1_sites (want 1)"
fi

# _assert_safe_row LABEL DIR — §8.4's TOP row: phase-state present, manifest
# absent => the gate BLOCKS and the tier ladder reads `strict`. Both halves,
# because C4's correction says the single flat claim is not true of both.
_assert_safe_row() {
  local label="$1" dir="$2"
  local rc has_ps has_mf lvl why=0
  gate_in "$dir"; rc=$GATE_RC
  has_ps=0; [ -f "$dir/.claude/phase-state.json" ] && has_ps=1
  has_mf=0; [ -f "$dir/.claude/manifest.json" ] && has_mf=1
  grep -q 'APPROVAL_LOG.md not found but' "$GATE_OUT" && why=1
  lvl="$( . "$REPO_ROOT/scripts/lib/enforcement-level.sh" >/dev/null 2>&1; read_enforcement_level "$dir" )"
  if [ "$rc" -ne 0 ] && [ "$has_ps" -eq 1 ] && [ "$has_mf" -eq 0 ] && [ "$why" -eq 1 ] && [ "$lvl" = "strict" ]; then
    pass "$label: the safe row — phase-state present, manifest absent; the gate BLOCKS (rc $rc) for that reason and the tier ladder reads strict"
  else
    fail_ "$label" "gate_rc=$rc (want non-zero) phase_state=$has_ps (want 1) manifest=$has_mf (want 0) blocked_for_that_reason=$why enforcement_level=$lvl (want strict)"
  fi
}

S2D="$(newtmp)"
if ! mk_adoptee "$S2D/p"; then
  fail_ "S2" "fixture setup failed"
else
  report_with_phase 2 "$S2D/report.json"
  _ans > "$S2D/answers"
  run_adopt "$S2D/p" "$S2D/answers" "$S2D/report.json" install; s2_rc=$RUN_RC
  s2_ps=0; [ -e "$S2D/p/.claude/phase-state.json" ] && s2_ps=1
  s2_mf=0; [ -e "$S2D/p/.claude/manifest.json" ] && s2_mf=1
  gate_in "$S2D/p"; s2_gate=$GATE_RC
  if [ "$s2_rc" -ne 0 ] && [ "$s2_ps" -eq 0 ] && [ "$s2_mf" -eq 0 ] && [ "$s2_gate" -eq 0 ]; then
    pass "S2 (interruption before any state): neither state file exists, so the project is exactly as enforced as it was before adoption began — the UNSAFE row needs a manifest and there is none"
  else
    fail_ "S2" "run_rc=$s2_rc phase_state=$s2_ps (want 0) manifest=$s2_mf (want 0) gate_rc=$s2_gate"
  fi
fi

S3D="$(newtmp)"
if ! mk_adoptee "$S3D/p"; then
  fail_ "S3" "fixture setup failed"
else
  report_with_phase 2 "$S3D/report.json"
  _ans > "$S3D/answers"
  run_adopt "$S3D/p" "$S3D/answers" "$S3D/report.json" phase_state
  _assert_safe_row "S3 (interruption after phase-state)" "$S3D/p"
fi

S4D="$(newtmp)"
if ! mk_adoptee "$S4D/p"; then
  fail_ "S4" "fixture setup failed"
else
  report_with_phase 2 "$S4D/report.json"
  _ans > "$S4D/answers"
  run_adopt "$S4D/p" "$S4D/answers" "$S4D/report.json" intake
  _assert_safe_row "S4 (interruption after intake)" "$S4D/p"
fi

# ── S5 — MUTATION: reverse the order, and the unsafe row becomes reachable ──
S5R="$(newtmp)"
if ! mk_adoptee "$S5R/p" || ! mk_mirror "$S5R/fw"; then
  fail_ "S5" "fixture setup failed"
else
  report_with_phase 2 "$S5R/report.json"
  _ans > "$S5R/answers"
  MUT_S="$S5R/fw/scripts/lib/adopt/adopt-state.sh"
  order_sites=$(_sites "$L_STATE" 'BF-ADOPT-STATE-ORDER')
  cp "$L_STATE" "$S5R/orig.ref"
  _sed_inplace "$MUT_S" 's|^.*BF-ADOPT-STATE-ORDER$|  printf '"'"'%s\\n'"'"' manifest intake phase_state   # BF-ADOPT-STATE-ORDER|'
  chgS=$(_changed_lines "$S5R/orig.ref" "$MUT_S")
  s5_parses=$(_parses "$MUT_S")
  # Halt after the FIRST stage of the reversed order.
  run_adopt "$S5R/p" "$S5R/answers" "$S5R/report.json" manifest "$S5R/fw"; s5_rc=$RUN_RC
  s5_ps=0; [ -e "$S5R/p/.claude/phase-state.json" ] && s5_ps=1
  s5_mf=0; [ -e "$S5R/p/.claude/manifest.json" ] && s5_mf=1
  gate_in "$S5R/p"; s5_gate=$GATE_RC
  s5_why=0
  grep -q 'skipping phase gate check' "$GATE_OUT" && s5_why=1
  if [ "$s5_gate" -eq 0 ] && [ "$s5_mf" -eq 1 ] && [ "$s5_ps" -eq 0 ] && [ "$s5_why" -eq 1 ] \
     && [ "$chgS" -eq 2 ] && [ "$order_sites" -eq 1 ] && [ "$s5_parses" -eq 1 ]; then
    pass "S5 (MUTATION): with the order reversed (1 line, mutant still parses) an interrupted run leaves a manifest and NO phase-state — the gate skips entirely (rc 0) and the UNSAFE row is reachable"
  else
    fail_ "S5" "gate_rc=$s5_gate (want 0) manifest=$s5_mf (want 1) phase_state=$s5_ps (want 0) gate_skipped_for_that_reason=$s5_why run_rc=$s5_rc changed_lines=$chgS (want 2) order_sites=$order_sites (want 1) parses=$s5_parses (want 1)"
  fi
fi

echo ""
echo "=== T — the stamp, and the WP3 bound it feeds, end to end (§8.5) ==="

# T2 — one call site in the WHOLE driver, per §8.5. A second stamp is a
# backfill wearing a birth stamp's name, and WP3 refuses one; the budget here
# is still one.
t2_sites=0
for f in "$DRIVER" "$LIB_DIR"/*.sh; do
  n=$(grep -c '^[^#]*soif_adoption_stamp ' "$f" 2>/dev/null); n=$(_num "$n")
  t2_sites=$((t2_sites + n))
done
t2_marked=$(_sites "$L_STATE" 'BF-ADOPT-STAMP-CALL')
if [ "$t2_sites" -eq 1 ] && [ "$t2_marked" -eq 1 ]; then
  pass "T2: soif_adoption_stamp has exactly ONE call site in the driver, and it is marked"
else
  fail_ "T2" "call_sites=$t2_sites (want 1) marked=$t2_marked (want 1)"
fi

T1D="$(newtmp)"
if ! mk_adoptee "$T1D/p"; then
  fail_ "T1" "fixture setup failed"
  fail_ "T4" "fixture setup failed"
else
  report_with_phase 2 "$T1D/report.json"
  _ans > "$T1D/answers"        # organizational, so T4's TDD arm BLOCKS
                               # rather than warns (`# BL-084-TIER-KEY`)
  run_adopt "$T1D/p" "$T1D/answers" "$T1D/report.json"; t1_rc=$RUN_RC
  t1_anchor=$(jq -r '.adoption.adoptedAtCommit // "MISSING"' "$T1D/p/.claude/manifest.json" 2>/dev/null)
  t1_parent=$( cd "$T1D/p" && git rev-parse HEAD^ 2>/dev/null )
  t1_blocks=$(jq -r '[.. | objects | select(has("adopted"))] | length' "$T1D/p/.claude/manifest.json" 2>/dev/null)
  # scenario and landedPhase are NOT read any more: §8.3 removed both from the
  # record (D4, D10). The v2 key set is asserted as a SET in
  # tests/test-brownfield-wp9-act-boundaries.sh E3, which is stronger than the
  # two absences this line used to check — a partial deletion passes an absence
  # pair and fails a set comparison.
  t1_ver=$(jq -r '.adoption.schemaVersion // "MISSING"' "$T1D/p/.claude/manifest.json" 2>/dev/null)
  # scannerReportSha256 must be the hash of the report the project actually
  # KEEPS, not merely non-empty: the field exists so a later reader can tell
  # whether the evidence beside it is the evidence the decision was made on.
  t1_sha=$(jq -r '.adoption.scannerReportSha256 // ""' "$T1D/p/.claude/manifest.json" 2>/dev/null)
  t1_real=$(shasum -a 256 "$T1D/p/.claude/adoption/scout-report.json" 2>/dev/null | awk '{print $1}')
  if [ "$t1_rc" -eq 0 ] && [ -n "$t1_parent" ] && [ "$t1_anchor" = "$t1_parent" ] \
     && [ "$(_num "$t1_blocks")" -eq 1 ] && [ "$t1_ver" = "2" ] \
     && [ -n "$t1_real" ] && [ "$t1_sha" = "$t1_real" ]; then
    pass "T1: the stamp lands ONCE at schemaVersion 2, adoptedAtCommit is the PRE-adoption tip, and scannerReportSha256 hashes the report the project kept"
  else
    fail_ "T1" "rc=$t1_rc anchor=$t1_anchor parent=$t1_parent adoption_blocks=$t1_blocks (want 1) schemaVersion=$t1_ver (want 2) report_sha=$t1_sha kept_report_sha=$t1_real"
  fi

  # T4 — a POST-adoption commit blocks, and blocks for the RIGHT REASON.
  mkdir -p "$T1D/p/src"
  printf 'export function add(a,b){return a+b;}\n' > "$T1D/p/src/add.js"
  ( cd "$T1D/p" && git add src/add.js ) >/dev/null 2>&1
  printf 'feat: work written after adoption day\n' > "$T1D/p/.git/COMMIT_EDITMSG"
  t4_rc=0
  t4_out=$( cd "$T1D/p" && bash scripts/pre-commit-gate.sh --terminal-mode --tdd-only --emit-blocked-gate 2>&1 ) || t4_rc=$?
  t4_own_copy=0; [ -f "$T1D/p/scripts/pre-commit-gate.sh" ] && [ -f "$T1D/p/scripts/lib/adoption-stamp.sh" ] && t4_own_copy=1
  if [ "$t4_rc" -eq 3 ] && [ "$t4_own_copy" -eq 1 ]; then
    pass "T4 (end to end): on the ADOPTED project, running its OWN installed gate, a post-adoption commit with no test is blocked by the BL-072 TDD arm specifically (exit 3, not merely non-zero)"
  else
    fail_ "T4" "rc=$t4_rc (want 3 = BL-072 TDD block) adoptee_has_its_own_gate_and_stamp_lib=$t4_own_copy. Output: $(printf '%s' "$t4_out" | tail -3 | tr '\n' ' ')"
  fi
fi

# T3 — the other direction: inside the adoption window, exempt.
T3D="$(newtmp)"
if ! mk_adoptee "$T3D/p"; then
  fail_ "T3" "fixture setup failed"
else
  report_with_phase 2 "$T3D/report.json"
  _ans > "$T3D/answers"
  run_adopt "$T3D/p" "$T3D/answers" "$T3D/report.json" manifest
  mkdir -p "$T3D/p/src"
  printf 'export function add(a,b){return a+b;}\n' > "$T3D/p/src/add.js"
  ( cd "$T3D/p" && git add src/add.js ) >/dev/null 2>&1
  printf 'feat: their pre-adoption work\n' > "$T3D/p/.git/COMMIT_EDITMSG"
  t3_rc=0
  t3_out=$( cd "$T3D/p" && bash scripts/pre-commit-gate.sh --terminal-mode --tdd-only --emit-blocked-gate 2>&1 ) || t3_rc=$?
  t3_announced=0
  printf '%s' "$t3_out" | grep -q 'PRE-ADOPTION commit' && t3_announced=1
  t3_stamped=$(jq -r '.adoption.adopted // "MISSING"' "$T3D/p/.claude/manifest.json" 2>/dev/null)
  if [ "$t3_rc" -eq 0 ] && [ "$t3_announced" -eq 1 ] && [ "$t3_stamped" = "true" ]; then
    pass "T3 (end to end): inside the adoption window the stamp WP4 wrote exempts the commit, and the exemption path announces itself — rc 0"
  else
    fail_ "T3" "rc=$t3_rc (want 0) exemption_path_announced=$t3_announced stamped=$t3_stamped"
  fi
fi

echo ""
echo "=== G — explicit staging (§8.5: never git add -A) ==="

# _dirty_adoptee DIR — one UNTRACKED file and one MODIFIED tracked file, both
# outside anything the driver writes. A blanket add sweeps both.
_dirty_adoptee() {
  local d="$1"
  mkdir -p "$d/src"
  printf 'half-finished work nobody asked to commit\n' > "$d/src/wip.js"
  printf '\nlocal edit in progress\n' >> "$d/README.md"
}

G1D="$(newtmp)"
if ! mk_adoptee "$G1D/p"; then
  fail_ "G1" "fixture setup failed"
else
  report_with_phase 2 "$G1D/report.json"
  _ans > "$G1D/answers"
  _dirty_adoptee "$G1D/p"
  run_adopt "$G1D/p" "$G1D/answers" "$G1D/report.json"; g1_rc=$RUN_RC
  g1_committed=$( cd "$G1D/p" && git show --name-only --format= HEAD 2>/dev/null )
  g1_wip_committed=$(printf '%s\n' "$g1_committed" | grep -c '^src/wip.js$'); g1_wip_committed=$(_num "$g1_wip_committed")
  g1_readme_committed=$(printf '%s\n' "$g1_committed" | grep -c '^README.md$'); g1_readme_committed=$(_num "$g1_readme_committed")
  # `-uall` and not the default: with `src/` entirely untracked git collapses
  # the whole directory to one `?? src/` row, and an assertion looking for the
  # FILE would read that as "the file is gone" — the wrong conclusion from the
  # right state.
  g1_still_dirty=$( cd "$G1D/p" && git status --porcelain -uall 2>/dev/null )
  g1_wip_untracked=0; printf '%s\n' "$g1_still_dirty" | grep -q '^?? src/wip.js' && g1_wip_untracked=1
  g1_readme_modified=0; printf '%s\n' "$g1_still_dirty" | grep -q '^ M README.md' && g1_readme_modified=1
  g1_state_committed=$(printf '%s\n' "$g1_committed" | grep -c '^.claude/phase-state.json$'); g1_state_committed=$(_num "$g1_state_committed")
  if [ "$g1_rc" -eq 0 ] && [ "$g1_wip_committed" -eq 0 ] && [ "$g1_readme_committed" -eq 0 ] \
     && [ "$g1_wip_untracked" -eq 1 ] && [ "$g1_readme_modified" -eq 1 ] && [ "$g1_state_committed" -eq 1 ]; then
    pass "G1: staging is explicit — the adoption commit carries the driver's own files and NOT the operator's dirty ones, which are still untracked and still modified afterwards"
  else
    fail_ "G1" "rc=$g1_rc wip_committed=$g1_wip_committed (want 0) readme_committed=$g1_readme_committed (want 0) wip_still_untracked=$g1_wip_untracked (want 1) readme_still_modified=$g1_readme_modified (want 1) adoption_state_committed=$g1_state_committed (want 1)"
  fi
fi

G2R="$(newtmp)"
if ! mk_adoptee "$G2R/p" || ! mk_mirror "$G2R/fw"; then
  fail_ "G2" "fixture setup failed"
else
  report_with_phase 2 "$G2R/report.json"
  _ans > "$G2R/answers"
  _dirty_adoptee "$G2R/p"
  MUT_G="$G2R/fw/scripts/lib/adopt/adopt-state.sh"
  stage_sites=$(_sites "$L_STATE" 'BF-ADOPT-STAGE-EXPLICIT')
  cp "$L_STATE" "$G2R/orig.ref"
  _sed_inplace "$MUT_G" 's|^.*BF-ADOPT-STAGE-EXPLICIT$|  ( cd "$root" \&\& git add -A ) \|\| {   # BF-ADOPT-STAGE-EXPLICIT|'
  chgG=$(_changed_lines "$G2R/orig.ref" "$MUT_G")
  g2_parses=$(_parses "$MUT_G")
  run_adopt "$G2R/p" "$G2R/answers" "$G2R/report.json" "" "$G2R/fw"; g2_rc=$RUN_RC
  g2_committed=$( cd "$G2R/p" && git show --name-only --format= HEAD 2>/dev/null )
  g2_wip=$(printf '%s\n' "$g2_committed" | grep -c '^src/wip.js$'); g2_wip=$(_num "$g2_wip")
  g2_state=$(printf '%s\n' "$g2_committed" | grep -c '^.claude/phase-state.json$'); g2_state=$(_num "$g2_state")
  if [ "$g2_rc" -eq 0 ] && [ "$g2_wip" -eq 1 ] && [ "$g2_state" -eq 1 ] \
     && [ "$chgG" -eq 2 ] && [ "$stage_sites" -eq 1 ] && [ "$g2_parses" -eq 1 ]; then
    pass "G2 (MUTATION): swapped for a blanket add (1 line, mutant still parses), the SAME run sweeps the operator's half-finished file into the adoption commit — G1's assertion is load-bearing"
  else
    fail_ "G2" "run_rc=$g2_rc wip_committed=$g2_wip (want 1 under the mutant) adoption_state_committed=$g2_state (want 1) changed_lines=$chgG (want 2) stage_sites=$stage_sites (want 1) parses=$g2_parses (want 1)"
  fi
fi

echo ""
echo "=== X — guard_not_in_framework (§8.1) ==="

# BOTH streams are read: the guard's refusal headline comes out of print_fail,
# which writes to stdout, while its remediation lines go to stderr. Reading one
# of them would pass or fail on a detail of the printer, not on the guard.
x1_rc=0
( cd "$REPO_ROOT" && bash scripts/adopt-project.sh --help ) >"$TOPTMP/x1.out" 2>&1 || x1_rc=$?
x1_named=0
grep -q 'Refusing to operate inside the Solo Orchestrator framework repo' "$TOPTMP/x1.out" && x1_named=1
if [ "$x1_rc" -ne 0 ] && [ "$x1_named" -eq 1 ]; then
  pass "X1: the guard fires BEFORE argument parsing — even --help exits non-zero ($x1_rc) inside the framework repo, naming the signature it matched"
else
  fail_ "X1" "rc=$x1_rc (want non-zero) refusal_named=$x1_named"
fi

X2D="$(newtmp)"
x2_rc=0
( cd "$X2D" && bash "$DRIVER" --root "$REPO_ROOT" ) >"$TOPTMP/x2.out" 2>&1 || x2_rc=$?
x2_named=0
grep -q 'Refusing to operate inside the Solo Orchestrator framework repo' "$TOPTMP/x2.out" && x2_named=1
if [ "$x2_rc" -ne 0 ] && [ "$x2_named" -eq 1 ]; then
  pass "X2: the TARGET arm fires too — --root pointing at a framework clone is refused from a benign cwd (rc $x2_rc)"
else
  fail_ "X2" "rc=$x2_rc (want non-zero) refusal_named=$x2_named"
fi

echo ""
echo "=== H — the gates are actually ON afterwards (§4.5: no forward exemption) ==="

# The run's closing line names two gates as live from the next commit onward.
# H1 makes git ITSELF prove that claim: in the adopted project, through its own
# installed hook, a test-less feature commit is refused. The pair matters — a
# hook that refused EVERYTHING would satisfy the blocking half on its own, and
# that is not a hypothetical: installing the framework's FALLBACK PRE-COMMIT
# hook here did exactly that, refusing an ordinary `docs:` commit, which is why
# the driver does not install it and says so instead.
H1D="$(newtmp)"
if ! mk_adoptee "$H1D/p"; then
  fail_ "H1" "fixture setup failed"
  fail_ "H2" "fixture setup failed"
else
  report_with_phase 2 "$H1D/report.json"
  _ans > "$H1D/answers"
  run_adopt "$H1D/p" "$H1D/answers" "$H1D/report.json"; h1_rc=$RUN_RC
  h1_hook=0
  [ -x "$H1D/p/.git/hooks/commit-msg" ] && h1_hook=1
  mkdir -p "$H1D/p/src"
  printf 'export function add(a,b){return a+b;}\n' > "$H1D/p/src/add.js"
  ( cd "$H1D/p" && git add src/add.js ) >/dev/null 2>&1
  h1_feat=0
  ( cd "$H1D/p" && git commit -q -m "feat: add without a test" ) >/dev/null 2>&1 || h1_feat=$?
  printf 'a note\n' > "$H1D/p/NOTES.md"
  ( cd "$H1D/p" && git add NOTES.md ) >/dev/null 2>&1
  h1_chore=0
  ( cd "$H1D/p" && git commit -q -m "docs: a note" ) >/dev/null 2>&1 || h1_chore=$?
  if [ "$h1_rc" -eq 0 ] && [ "$h1_hook" -eq 1 ] && [ "$h1_feat" -ne 0 ] && [ "$h1_chore" -eq 0 ]; then
    pass "H1: after adoption the project's OWN hooks are live — git itself refuses a test-less feature commit (rc $h1_feat) while an ordinary commit still lands"
  else
    fail_ "H1" "run_rc=$h1_rc commit_msg_hook_executable=$h1_hook feat_commit_rc=$h1_feat (want non-zero) ordinary_commit_rc=$h1_chore (want 0)"
  fi
fi

# H2 — an adoptee's own pre-commit hook is a §7 collision, not something to
# overwrite. The whole-file writer would destroy it, so it is not run.
H2D="$(newtmp)"
if ! mk_adoptee "$H2D/p"; then
  fail_ "H2" "fixture setup failed"
else
  report_with_phase 2 "$H2D/report.json"
  _ans > "$H2D/answers"
  mkdir -p "$H2D/p/.git/hooks"
  printf '#!/usr/bin/env bash\n# their own hook\nexit 0\n' > "$H2D/p/.git/hooks/pre-commit"
  chmod +x "$H2D/p/.git/hooks/pre-commit"
  h2_before=$(shasum -a 256 "$H2D/p/.git/hooks/pre-commit" 2>/dev/null | awk '{print $1}')
  run_adopt "$H2D/p" "$H2D/answers" "$H2D/report.json"; h2_rc=$RUN_RC
  h2_after=$(shasum -a 256 "$H2D/p/.git/hooks/pre-commit" 2>/dev/null | awk '{print $1}')
  h2_said=0
  grep -q 'LEFT ALONE' "$RUN_OUT" && h2_said=1
  # RE-AIMED WHEN WP6 LANDED. This case used to require the WP6 STUB to fire
  # ("NOT DONE — the collision archive"), which was the right assertion while
  # the archive did not exist and is the wrong one now: an honest stub for
  # delivered work is a false claim, so WP6 removed it. The property H2 was
  # always about — their hook is byte-for-byte untouched and the run says so —
  # is unchanged and still asserted. What replaces the stub check is the
  # STRONGER version of the same intent: the hook is now RECOVERABLE, so the
  # archive must hold a copy of it with a restore line.
  h2_arch=$( cd "$H2D/p" && find .claude/adoption-archive -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort | head -1 )
  h2_copy=""
  [ -n "$h2_arch" ] && h2_copy=$(shasum -a 256 "$H2D/p/$h2_arch/git-hooks/pre-commit" 2>/dev/null | awk '{print $1}')
  h2_restore=0
  [ -n "$h2_arch" ] && jq -e '[.entries[] | select(.originalPath == ".git/hooks/pre-commit") | select((.restore // "") != "")] | length == 1' \
    "$H2D/p/$h2_arch/MANIFEST.json" >/dev/null 2>&1 && h2_restore=1
  if [ "$h2_rc" -eq 0 ] && [ -n "$h2_before" ] && [ "$h2_before" = "$h2_after" ] && [ "$h2_said" -eq 1 ] \
     && [ -n "$h2_copy" ] && [ "$h2_copy" = "$h2_before" ] && [ "$h2_restore" -eq 1 ]; then
    pass "H2: an adoptee's existing pre-commit hook is byte-for-byte untouched, said out loud, AND archived byte-identically with a restore line (WP6) rather than overwritten"
  else
    fail_ "H2" "rc=$h2_rc sha_before=$h2_before sha_after=$h2_after said_left_alone=$h2_said archive=$h2_arch archived_copy_sha=$h2_copy restore_line_present=$h2_restore"
  fi
fi

# H3 — the omission is DISCLOSED, not silent. An adopted project without the
# commit-time scanners is a defensible state; one whose operator does not know
# it is not. The run must name what is not running and what to do instead.
H3D="$(newtmp)"
if ! mk_adoptee "$H3D/p"; then
  fail_ "H3" "fixture setup failed"
else
  report_with_phase 2 "$H3D/report.json"
  _ans > "$H3D/answers"
  run_adopt "$H3D/p" "$H3D/answers" "$H3D/report.json"; h3_rc=$RUN_RC
  h3_named=0; h3_remedy=0; h3_nooverclaim=0; h3_precommit=0
  grep -q 'NOT DONE — the commit-time scanners' "$RUN_OUT" && h3_named=1
  grep -q 'scripts/pre-commit-gate.sh --terminal-mode' "$RUN_OUT" && h3_remedy=1
  grep -q "the framework's two message gates are live" "$RUN_OUT" && h3_nooverclaim=1
  [ -e "$H3D/p/.git/hooks/pre-commit" ] && h3_precommit=1
  if [ "$h3_rc" -eq 0 ] && [ "$h3_named" -eq 1 ] && [ "$h3_remedy" -eq 1 ] \
     && [ "$h3_nooverclaim" -eq 1 ] && [ "$h3_precommit" -eq 0 ]; then
    pass "H3: the run claims only the gates it installed — it names the commit-time scanners as NOT running and gives the command to run them by hand"
  else
    fail_ "H3" "rc=$h3_rc scanners_named_absent=$h3_named remedy_given=$h3_remedy claim_is_narrow=$h3_nooverclaim pre_commit_hook_written=$h3_precommit (want 0)"
  fi
fi

# H4 — an adopted project's framework files are born the same way a scaffolded
# one's are. Modes included: a blanket `chmod +x` over the installed set would
# leave every sourced lib at 0755 downstream, a difference from a scaffolded
# project that nothing there would ever explain.
H4D="$(newtmp)"
if ! mk_adoptee "$H4D/p"; then
  fail_ "H4" "fixture setup failed"
else
  report_with_phase 2 "$H4D/report.json"
  _ans > "$H4D/answers"
  run_adopt "$H4D/p" "$H4D/answers" "$H4D/report.json"; h4_rc=$RUN_RC
  h4_lib_src=$(_mode_of "$REPO_ROOT/scripts/lib/helpers-core.sh")
  h4_lib_dst=$(_mode_of "$H4D/p/scripts/lib/helpers-core.sh")
  h4_gate_src=$(_mode_of "$REPO_ROOT/scripts/pre-commit-gate.sh")
  h4_gate_dst=$(_mode_of "$H4D/p/scripts/pre-commit-gate.sh")
  h4_stamp=0
  [ -f "$H4D/p/scripts/lib/adoption-stamp.sh" ] && h4_stamp=1
  if [ "$h4_rc" -eq 0 ] && [ "$h4_lib_src" = "$h4_lib_dst" ] && [ "$h4_gate_src" = "$h4_gate_dst" ] \
     && [ "$h4_lib_src" != "$h4_gate_src" ] && [ "$h4_stamp" -eq 1 ]; then
    pass "H4: the installed framework files keep their own modes (lib $h4_lib_dst, entry script $h4_gate_dst — genuinely different, so the comparison is not vacuous) and adoption-stamp.sh reaches the adoptee"
  else
    fail_ "H4" "rc=$h4_rc lib_mode $h4_lib_src->$h4_lib_dst entry_mode $h4_gate_src->$h4_gate_dst (the two source modes must differ, else this proves nothing) adoption_stamp_installed=$h4_stamp"
  fi
fi

echo ""
echo "=== R — the halted-run exits, and the record's evidence hash ==="

# R1 — a re-run of an adoption that already installed everything must NAME the
# real cause. This is the operator's most likely second move (something went
# wrong at the commit, fix it, run again) and the first cut answered it by
# blaming the clone — the one thing that was fine.
R1D="$(newtmp)"
if ! mk_adoptee "$R1D/p"; then
  fail_ "R1" "fixture setup failed"
else
  report_with_phase 2 "$R1D/report.json"
  _ans > "$R1D/answers"
  run_adopt "$R1D/p" "$R1D/answers" "$R1D/report.json"; r1_first=$RUN_RC
  run_adopt "$R1D/p" "$R1D/answers" "$R1D/report.json"; r1_second=$RUN_RC
  r1_true=0; r1_false=0; r1_resume=0
  grep -q 'every framework script is already present' "$RUN_ERR" && r1_true=1
  grep -q 'is this a complete clone' "$RUN_ERR" && r1_false=1
  grep -q 'RESUMING AN INTERRUPTED ADOPTION IS NOT BUILT YET' "$RUN_ERR" && r1_resume=1
  # …and the safe row still holds after the refused re-run.
  gate_in "$R1D/p"; r1_gate=$GATE_RC
  if [ "$r1_first" -eq 0 ] && [ "$r1_second" -ne 0 ] && [ "$r1_true" -eq 1 ] \
     && [ "$r1_false" -eq 0 ] && [ "$r1_resume" -eq 1 ] && [ "$r1_gate" -ne 0 ]; then
    pass "R1: a second run on an already-installed project refuses with the TRUE cause, never the clone misdiagnosis, says resuming is not built yet, and leaves the gate still blocking"
  else
    fail_ "R1" "first_rc=$r1_first second_rc=$r1_second (want non-zero) named_true_cause=$r1_true blamed_the_clone=$r1_false (want 0) said_resume_unbuilt=$r1_resume gate_rc=$r1_gate (want non-zero)"
  fi
fi

# R2/R3 — the stamp must never record an evidence hash it does not have.
#
# Driven at the FUNCTION level, with adopt_sha256 stubbed, because the real
# trigger is a host with neither `shasum` nor `sha256sum` and there is no
# honest way to manufacture that from a test without either shipping a
# test-only backdoor in the driver or rebuilding PATH around a guess at every
# tool the driver uses. The guard is what is under test; the tool probe itself
# is one `command -v` pair. Dual direction, so a guard that refused everything
# would fail R3.
_stamp_fixture() {
  local d="$1"
  mkdir -p "$d/.claude/adoption" || return 1
  ( cd "$d" && git init -q . && git config user.email r@t.invalid && git config user.name R \
      && echo x > f.txt && git add f.txt && git commit -q -m "chore: base" ) >/dev/null 2>&1 || return 1
  printf '%s\n' '{"stack":{"ciHost":"github"}}' > "$d/.claude/adoption/scout-report.json"
  return 0
}

# _run_write_manifest DIR STUB_EMPTY — source the module, set the globals
# adopt_write_manifest reads, optionally stub the hash, and call it. Echoes rc.
_run_write_manifest() {
  local d="$1" stub="$2"
  (
    # shellcheck source=/dev/null
    . "$REPO_ROOT/scripts/lib/adoption-stamp.sh"
    # shellcheck source=/dev/null
    . "$REPO_ROOT/scripts/lib/adopt/adopt-core.sh"
    # shellcheck source=/dev/null
    . "$REPO_ROOT/scripts/lib/adopt/adopt-state.sh"
    # shellcheck source=/dev/null
    . "$REPO_ROOT/scripts/lib/adopt/adopt-stubs.sh"
    adopt_ledger_init "$d/.ledger" >/dev/null 2>&1
    ADOPT_SCENARIO="in-flight"; ADOPT_LANDED_PHASE=1; ADOPT_DEPLOYMENT="personal"
    [ "$stub" = "empty" ] && adopt_sha256() { printf ''; }
    cd "$d" || exit 9
    adopt_write_manifest "$d" "$d/.claude/adoption/scout-report.json"
  ) >/dev/null 2>&1
  printf '%s\n' "$?"
}

R2D="$(newtmp)/p"
if ! _stamp_fixture "$R2D"; then
  fail_ "R2" "fixture setup failed"
  fail_ "R3" "fixture setup failed"
else
  r2_rc=$(_run_write_manifest "$R2D" empty)
  # Structural discriminator for an expected ABSENCE: the manifest exists (the
  # function ran and got past its first write) but carries NO adoption block,
  # so this is a refusal at the guard and not a crash before it.
  r2_manifest=0; [ -f "$R2D/.claude/manifest.json" ] && r2_manifest=1
  r2_block=1
  jq -e '.adoption' "$R2D/.claude/manifest.json" >/dev/null 2>&1 || r2_block=0
  r2_sites=$(_sites "$L_STATE" 'BF-ADOPT-SHA-REQUIRED')
  if [ "$r2_rc" -ne 0 ] && [ "$r2_manifest" -eq 1 ] && [ "$r2_block" -eq 0 ] && [ "$r2_sites" -eq 1 ]; then
    pass "R2: an unhashable scan report REFUSES the stamp (rc $r2_rc) — the manifest exists but carries no adoption block, so the record never claims an evidence hash it does not have"
  else
    fail_ "R2" "rc=$r2_rc (want non-zero) manifest_written=$r2_manifest (want 1) adoption_block_present=$r2_block (want 0) guard_sites=$r2_sites (want 1)"
  fi

  R3D="$(newtmp)/p"
  if ! _stamp_fixture "$R3D"; then
    fail_ "R3" "fixture setup failed"
  else
    r3_rc=$(_run_write_manifest "$R3D" real)
    r3_sha=$(jq -r '.adoption.scannerReportSha256 // ""' "$R3D/.claude/manifest.json" 2>/dev/null)
    r3_real=$(shasum -a 256 "$R3D/.claude/adoption/scout-report.json" 2>/dev/null | awk '{print $1}')
    if [ "$r3_rc" -eq 0 ] && [ -n "$r3_real" ] && [ "$r3_sha" = "$r3_real" ]; then
      pass "R3 (control): with a working hash the same call succeeds and records the real one — R2's guard refuses the empty case, not every case"
    else
      fail_ "R3" "rc=$r3_rc (want 0) recorded=$r3_sha real=$r3_real"
    fi
  fi
fi

echo ""
echo "=== W — the honest stubs (§10: WP5/WP5b/WP6/WP7 are NOT built here) ==="

W1D="$(newtmp)"
if ! mk_adoptee "$W1D/p"; then
  fail_ "W1" "fixture setup failed"
else
  report_with_phase 2 "$W1D/report.json"
  _ans > "$W1D/answers"
  run_adopt "$W1D/p" "$W1D/answers" "$W1D/report.json"; w1_rc=$RUN_RC
  # THE CERTIFICATION ROW INVERTED AT WP9, and the inversion is a decision
  # rather than a rename. v1-WP5's pass is RETIRED (§5.1) — with no claimed
  # rung there is nothing to certify against and under D10 no landed rung to
  # certify for — so announcing it as NOT DONE would promise work nobody will
  # ever do. What must be announced instead is the act that genuinely has not
  # run and genuinely will: the ASSESSMENT (WP12a). Asserted in both
  # directions, because the absence alone is satisfied by a driver that stopped
  # printing stubs altogether.
  w1_cert=1
  grep -q 'the certification pass' "$RUN_OUT" && w1_cert=0
  grep -q 'NOT DONE — the assessment (Act 3)' "$RUN_OUT" || w1_cert=0
  w1_record=0; w1_empty_named=0; w1_docs=0; w1_debt=0
  grep -q 'NOT DONE — the Adoption Record' "$RUN_OUT" && w1_record=1
  grep -q "NOT DONE — your project's framework documents" "$RUN_OUT" && w1_docs=1
  # WP5b RETIRED ITS STUB, so this row flipped: the test-debt notice must be
  # GONE and the thing it apologised for must be PRESENT. The absence alone
  # would also be satisfied by a driver that simply stopped printing it, so it
  # is asserted together with the artefact — the ledger has to exist on disk.
  # Its contents, its tier ratchet and both mutation directions belong to
  # tests/test-brownfield-wp5b-test-debt.sh; what W1 owns is the honesty
  # accounting, and a package that has shipped must not still announce itself
  # as NOT DONE.
  w1_debt=1
  grep -q 'NOT DONE — the test-debt ledger' "$RUN_OUT" && w1_debt=0
  [ -s "$W1D/p/.claude/test-debt.json" ] || w1_debt=0
  # The "empty means not measured" sentence went with the certification arrays
  # it described. §8.3 removed the arrays from the record entirely rather than
  # leaving them empty in it, which is the stronger answer to the same problem:
  # a field that is not there cannot be misread as a measurement.
  w1_empty_named=1
  w1_kinds=$(jq -r '[.adoption | keys[] | select(. == "certification" or . == "blockersAccepted")] | length' "$W1D/p/.claude/manifest.json" 2>/dev/null)
  # The CLAUDE.md half is asserted as an ABSENCE, so it carries a structural
  # discriminator: the file is not there AND the run said so. Either alone is
  # satisfied by a driver that simply forgot.
  w1_no_claude=1
  [ -e "$W1D/p/CLAUDE.md" ] && w1_no_claude=0
  if [ "$w1_rc" -eq 0 ] && [ "$w1_cert" -eq 1 ] && [ "$w1_record" -eq 1 ] && [ "$w1_debt" -eq 1 ] \
     && [ "$w1_docs" -eq 1 ] && [ "$w1_no_claude" -eq 1 ] \
     && [ "$w1_empty_named" -eq 1 ] && [ "$(_num "$w1_kinds")" -eq 0 ]; then
    pass "W1: every STILL-unbuilt package announces itself — the ASSESSMENT (WP12a), the Adoption Record and the project documents — the RETIRED certification pass is announced by nobody and its arrays are absent from the record rather than empty in it, and the one package that HAS shipped (WP5b's test-debt ledger) no longer announces itself as NOT DONE and left its artefact behind"
  else
    fail_ "W1" "rc=$w1_rc assessment_stub_replaced_certification=$w1_cert test_debt_retired_and_written=$w1_debt (want 1) adoption_record_stub=$w1_record project_docs_stub=$w1_docs claude_md_absent=$w1_no_claude retired_arrays_absent=$w1_empty_named certification_keys=$w1_kinds (want 0)"
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
