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
L_CHOOSER="$LIB_DIR/adopt-chooser.sh"
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

# ── Answer scripts ──────────────────────────────────────────────────────────
# Every line is one answer, in the order the driver asks. A BLANK line is an
# unanswered question, which is exactly what an operator who walked away
# produces; running OUT of lines is an EOF, which the driver treats the same
# way. Both are supposed to reach a mandatory guard, never a default.
_ans_s1() {
  cat <<'ANS'
1
2
1
1
we reconcile vendor invoices by hand
six weeks and no budget
it invoices people and chases the late ones
internal
yes
typescript and postgres are settled
subscription billing
just me approves things
anyone with a login, including screen readers
aws, for our own staff
it pages me on my phone
my colleague dana
github actions on a tag
losing the database
1
1
ANS
}

# _ans_s2 LADDER-CHOICE [DATA-CLASSIFICATION] [ZDR-ANSWER]
#
# `${2-public}` and not `${2:-public}`: an explicitly EMPTY classification is a
# case under test (an operator who skipped the question), and `:-` would
# silently answer it.
#
# ZDR-ANSWER is the answer to the attestation question, which is asked for any
# classification ABOVE public. It is supplied for the SKIPPED-classification
# cases too, and deliberately: the control refuses at the classification and
# never reads it, while the mutant — which accepts the empty answer — does. One
# answer file, two code paths, two outcomes; the inputs are provably identical
# because they are literally the same bytes.
_ans_s2() {
  local ladder="$1" dc="${2-public}" zdr="${3-}"
  cat <<ANS
2
$ladder
2
1
1
we reconcile vendor invoices by hand
six weeks and no budget
invoices only; no reporting in the first version
$dc
ANS
  [ -n "$zdr" ] && printf '%s\n' "$zdr"
  cat <<'ANS'
typescript and postgres are settled
subscription billing
just me approves things
anyone with a login
aws
losing the database
1
1
ANS
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

echo "=== Q — the chooser's wording (§4.1: a decision, not a phrasing) ==="

# The sentence, spelled here ONCE and independently of the source, so the pin
# is a genuine STRING EQUALITY against Karl's words and not a tautology.
CHOOSER_LITERAL="Is the project built out and needs to be able to be supported (i.e. bug fixes, maintenance, new features add), or are you still in the process of building your project?"

q1_sites=$(grep -cF -- "$CHOOSER_LITERAL" "$L_CHOOSER" 2>/dev/null); q1_sites=$(_num "$q1_sites")
q1_var=""
# shellcheck source=/dev/null
q1_var="$( . "$L_CHOOSER" >/dev/null 2>&1; printf '%s' "$ADOPT_CHOOSER_QUESTION" )"
if [ "$q1_sites" -eq 1 ] && [ "$q1_var" = "$CHOOSER_LITERAL" ]; then
  pass "Q1: the chooser is Karl's sentence VERBATIM — one site in adopt-chooser.sh, and the variable is string-equal to it"
else
  fail_ "Q1" "sites=$q1_sites (want 1); variable=[$q1_var]"
fi

# Non-developer register: no phase numbers, no framework vocabulary.
q3_bad="$(printf '%s' "$CHOOSER_LITERAL" | grep -oiE 'phase|mvp|gate|scaffold|framework|intake|poc|repo|commit|artifact' | tr '\n' ' ')"
if [ -z "$q3_bad" ]; then
  pass "Q3: the question is in a non-developer register — no phase number and no framework vocabulary"
else
  fail_ "Q3" "the question names framework vocabulary: $q3_bad"
fi

# It asks about the project's SITUATION, not its artifacts.
q4_bad="$(printf '%s' "$CHOOSER_LITERAL" | grep -oiE 'readme|changelog|test|ci|pipeline|tag|branch|file' | tr '\n' ' ')"
if [ -z "$q4_bad" ] && printf '%s' "$CHOOSER_LITERAL" | grep -q 'the project'; then
  pass "Q4: the question asks about the project's situation and names no artifact"
else
  fail_ "Q4" "artifact words present: [$q4_bad]"
fi

Q2D="$(newtmp)"
if ! mk_adoptee "$Q2D/p"; then
  fail_ "Q2" "fixture setup failed"
  fail_ "Q5" "fixture setup failed"
else
  report_with_phase 2 "$Q2D/report.json"
  _ans_s2 4 > "$Q2D/answers"
  run_adopt "$Q2D/p" "$Q2D/answers" "$Q2D/report.json"; q2_rc=$RUN_RC
  if grep -qxF -- "$CHOOSER_LITERAL" "$RUN_OUT"; then
    pass "Q2: the driver asks it VERBATIM — the transcript carries the sentence as a whole line (run rc $q2_rc)"
  else
    fail_ "Q2" "the verbatim sentence is not a line of the transcript"
  fi

  # ── Q5 — NOT PREFILLED (§4.2's rejected alternative) ──────────────────────
  # Two halves. Behaviourally: with the answer withheld the driver STOPS rather
  # than choosing. Structurally: nothing around the question offers a default,
  # so there is no guess for a tired operator to accept without reading.
  Q5D="$(newtmp)"
  if mk_adoptee "$Q5D/p"; then
    report_with_phase 2 "$Q5D/report.json"
    : > "$Q5D/answers"      # the operator walked away before answering
    run_adopt "$Q5D/p" "$Q5D/answers" "$Q5D/report.json"; q5_rc=$RUN_RC
    q5_refused=0
    grep -q "This question has no default and no skip" "$RUN_ERR" && q5_refused=1
    q5_untouched=1
    [ -e "$Q5D/p/.claude/phase-state.json" ] && q5_untouched=0
    [ -e "$Q5D/p/.claude/manifest.json" ] && q5_untouched=0
    q5_nodefault=1
    grep -qiE 'suggested|recommended|\[default|press enter to accept' "$RUN_OUT" && q5_nodefault=0
    if [ "$q5_rc" -ne 0 ] && [ "$q5_refused" -eq 1 ] && [ "$q5_untouched" -eq 1 ] && [ "$q5_nodefault" -eq 1 ]; then
      pass "Q5: the chooser is NOT prefilled — withheld, it stops the run (rc $q5_rc) with nothing written, and no default is offered anywhere in the transcript"
    else
      fail_ "Q5" "rc=$q5_rc (want non-zero) refused=$q5_refused untouched=$q5_untouched no_default_offered=$q5_nodefault"
    fi
  else
    fail_ "Q5" "fixture setup failed"
  fi
fi

# ── E — the evidence the scanner offers (§4.2) ──────────────────────────────
E1D="$(newtmp)"
if ! mk_adoptee "$E1D/p"; then
  fail_ "E1" "fixture setup failed"
else
  report_with_phase 2 "$E1D/report.json"
  _ans_s2 3 > "$E1D/answers"
  run_adopt "$E1D/p" "$E1D/answers" "$E1D/report.json"
  e1_conf=$(grep -c 'Confidence: ' "$RUN_OUT"); e1_conf=$(_num "$e1_conf")
  e1_override=0
  grep -q 'overrides all of it' "$RUN_OUT" && e1_override=1
  e1_users=0
  grep -q 'the scan cannot measure' "$RUN_OUT" && e1_users=1
  if [ "$e1_conf" -ge 4 ] && [ "$e1_override" -eq 1 ] && [ "$e1_users" -eq 1 ]; then
    pass "E1: the scan OFFERS evidence — $e1_conf signals each with a confidence tier, an explicit 'your answer overrides all of it', and 'users' declared unmeasurable"
  else
    fail_ "E1" "confidence_lines=$e1_conf (want >=4) override_stated=$e1_override users_declared_unmeasurable=$e1_users"
  fi
fi

echo ""
echo "=== P — scenario placement and THE FLOOR RULE (§4.3, §4.4) ==="

P1D="$(newtmp)"
if ! mk_adoptee "$P1D/p"; then
  fail_ "P1" "fixture setup failed"
else
  report_with_phase 2 "$P1D/report.json"
  _ans_s1 > "$P1D/answers"
  run_adopt "$P1D/p" "$P1D/answers" "$P1D/report.json"; p1_rc=$RUN_RC
  p1_phase=$(jq -r '.current_phase // "MISSING"' "$P1D/p/.claude/phase-state.json" 2>/dev/null)
  p1_adopted=$(jq -r '.adoption.adopted // "MISSING"' "$P1D/p/.claude/manifest.json" 2>/dev/null)
  p1_scen=$(jq -r '.adoption.scenario // "MISSING"' "$P1D/p/.claude/manifest.json" 2>/dev/null)
  if [ "$p1_rc" -eq 0 ] && [ "$p1_phase" = "4" ] && [ "$p1_adopted" = "true" ] && [ "$p1_scen" = "completed" ]; then
    pass "P1: S1 (\"built out\") lands at phase 4, adopted — regardless of what the artifacts scored"
  else
    fail_ "P1" "rc=$p1_rc phase=$p1_phase (want 4) adopted=$p1_adopted scenario=$p1_scen"
  fi
fi

P2D="$(newtmp)"
if ! mk_adoptee "$P2D/p"; then
  fail_ "P2" "fixture setup failed"
else
  report_with_phase 2 "$P2D/report.json"
  _ans_s2 3 > "$P2D/answers"        # option 3 == rung 2 == what the scan found
  run_adopt "$P2D/p" "$P2D/answers" "$P2D/report.json"; p2_rc=$RUN_RC
  p2_phase=$(jq -r '.current_phase // "MISSING"' "$P2D/p/.claude/phase-state.json" 2>/dev/null)
  p2_scen=$(jq -r '.adoption.scenario // "MISSING"' "$P2D/p/.claude/manifest.json" 2>/dev/null)
  if [ "$p2_rc" -eq 0 ] && [ "$p2_phase" = "2" ] && [ "$p2_scen" = "in-flight" ]; then
    pass "P2: S2 lands at Scout's REACHED rung (2) when the interview agrees"
  else
    fail_ "P2" "rc=$p2_rc phase=$p2_phase (want 2) scenario=$p2_scen"
  fi
fi

P3D="$(newtmp)"
if ! mk_adoptee "$P3D/p"; then
  fail_ "P3" "fixture setup failed"
else
  report_with_phase 2 "$P3D/report.json"
  _ans_s2 5 > "$P3D/answers"        # option 5 == rung 4 — HIGHER than the scan
  run_adopt "$P3D/p" "$P3D/answers" "$P3D/report.json"; p3_rc=$RUN_RC
  p3_phase=$(jq -r '.current_phase // "MISSING"' "$P3D/p/.claude/phase-state.json" 2>/dev/null)
  if [ "$p3_rc" -eq 0 ] && [ "$p3_phase" = "2" ]; then
    pass "P3 (floor, direction 1): the interview claimed rung 4 and the placement STAYED at the scanned 2 — the interview cannot raise it"
  else
    fail_ "P3" "rc=$p3_rc phase=$p3_phase (want 2 — the interview must not raise the placement)"
  fi
fi

P4D="$(newtmp)"
if ! mk_adoptee "$P4D/p"; then
  fail_ "P4" "fixture setup failed"
else
  report_with_phase 2 "$P4D/report.json"
  _ans_s2 2 > "$P4D/answers"        # option 2 == rung 1 — LOWER than the scan
  run_adopt "$P4D/p" "$P4D/answers" "$P4D/report.json"; p4_rc=$RUN_RC
  p4_phase=$(jq -r '.current_phase // "MISSING"' "$P4D/p/.claude/phase-state.json" 2>/dev/null)
  if [ "$p4_rc" -eq 0 ] && [ "$p4_phase" = "1" ]; then
    pass "P4 (floor, direction 2): the interview claimed rung 1 and the placement LOWERED to 1 — the safer number wins"
  else
    fail_ "P4" "rc=$p4_rc phase=$p4_phase (want 1)"
  fi
fi

# ── P5 — MUTATION: neuter the floor rule ────────────────────────────────────
P5R="$(newtmp)"
if ! mk_adoptee "$P5R/p" || ! mk_mirror "$P5R/fw"; then
  fail_ "P5" "fixture setup failed"
else
  report_with_phase 2 "$P5R/report.json"
  _ans_s2 5 > "$P5R/answers"
  MUT5="$P5R/fw/scripts/lib/adopt/adopt-chooser.sh"
  floor_sites=$(_sites "$L_CHOOSER" 'BF-ADOPT-FLOOR')
  cp "$L_CHOOSER" "$P5R/orig.ref"
  _sed_inplace "$MUT5" 's|^.*BF-ADOPT-FLOOR$|  printf '"'"'%s'"'"' "$claimed"   # BF-ADOPT-FLOOR|'
  chg5=$(_changed_lines "$P5R/orig.ref" "$MUT5")
  p5_parses=$(_parses "$MUT5")
  run_adopt "$P5R/p" "$P5R/answers" "$P5R/report.json" "" "$P5R/fw"; p5_rc=$RUN_RC
  p5_phase=$(jq -r '.current_phase // "MISSING"' "$P5R/p/.claude/phase-state.json" 2>/dev/null)
  if [ "$p5_phase" = "4" ] && [ "$chg5" -eq 2 ] && [ "$floor_sites" -eq 1 ] && [ "$p5_parses" -eq 1 ]; then
    pass "P5 (MUTATION): with the floor neutered (1 line, mutant still parses), the SAME interview raises the placement from 2 to 4 — the floor is load-bearing"
  else
    fail_ "P5" "landed=$p5_phase (want 4 under the mutant) run_rc=$p5_rc changed_lines=$chg5 (want 2) floor_sites=$floor_sites (want 1) parses=$p5_parses (want 1)"
  fi
fi

echo ""
echo "=== I — reverse intake (§8.3) ==="

I1D="$(newtmp)"
if ! mk_adoptee "$I1D/p"; then
  fail_ "I1" "fixture setup failed"
else
  report_with_phase 2 "$I1D/report.json"
  _ans_s2 3 > "$I1D/answers"
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
  # Same script as _ans_s2 3, but section 1 answers "change it" and then gives
  # the real answer — one extra line, at exactly that point.
  {
    printf '2\n3\n2\n'
    printf '2\nledger-service\n'
    printf '1\n'
    printf 'we reconcile vendor invoices by hand\nsix weeks and no budget\ninvoices only\npublic\n'
    printf 'typescript is settled\nsubscription billing\njust me\nanyone with a login\naws\nlosing the database\n'
    printf '1\n1\n'
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

I3D="$(newtmp)"
if ! mk_adoptee "$I3D/p"; then
  fail_ "I3" "fixture setup failed"
else
  report_with_phase 2 "$I3D/report.json"
  # Answers run out exactly at the first JUDGMENT question (section 2).
  printf '2\n3\n2\n1\n1\n' > "$I3D/answers"
  run_adopt "$I3D/p" "$I3D/answers" "$I3D/report.json"; i3_rc=$RUN_RC
  i3_refused=0; i3_asked=0; i3_untouched=1
  grep -q "This question has no default and no skip" "$RUN_ERR" && i3_refused=1
  grep -q 'What problem does this project solve' "$RUN_OUT" && i3_asked=1
  [ -e "$I3D/p/.claude/phase-state.json" ] && i3_untouched=0
  [ -e "$I3D/p/PROJECT_INTAKE.md" ] && i3_untouched=0
  if [ "$i3_rc" -ne 0 ] && [ "$i3_refused" -eq 1 ] && [ "$i3_asked" -eq 1 ] && [ "$i3_untouched" -eq 1 ]; then
    pass "I3: a judgment section REFUSES to proceed unattended — the question was asked (rc $i3_rc), no answer was invented, and nothing was written"
  else
    fail_ "I3" "rc=$i3_rc (want non-zero) refusal_printed=$i3_refused question_was_asked=$i3_asked project_untouched=$i3_untouched"
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

# ── I5/I6/I7 — data classification cannot be skipped, IN EITHER SCENARIO ────
# The assertion is made through the gate that makes it a mechanical necessity:
# check-phase-gate.sh's Phase 1->2 ZDR backstop. APPROVAL_LOG.md is created by
# the TEST because the Adoption Record is WP7's and the gate exits at its
# absence BEFORE the ZDR arm is reached — without it these three cases would be
# asserting the wrong refusal.
seed_approval_log() {
  printf '# Approval Log\n\n## Phase Gate: Phase 0 to Phase 1\n\n  Date: 2026-01-01\n  Approved by: test\n' > "$1/APPROVAL_LOG.md"
}

I5D="$(newtmp)"
if ! mk_adoptee "$I5D/p"; then
  fail_ "I5" "fixture setup failed"
else
  report_with_phase 2 "$I5D/report.json"
  # The classification question is left BLANK, and the attestation answer that
  # only a run which ACCEPTED the blank would ever reach is supplied anyway —
  # I6 reuses this identical file against the mutated driver.
  _ans_s2 3 "" yes > "$I5D/answers"
  run_adopt "$I5D/p" "$I5D/answers" "$I5D/report.json"; i5_rc=$RUN_RC
  i5_refused=0; i5_untouched=1
  grep -q 'no default, no guess and no skip' "$RUN_ERR" && i5_refused=1
  [ -e "$I5D/p/.claude/phase-state.json" ] && i5_untouched=0
  if [ "$i5_rc" -ne 0 ] && [ "$i5_refused" -eq 1 ] && [ "$i5_untouched" -eq 1 ]; then
    pass "I5 (control): an unanswered data classification STOPS the adoption (rc $i5_rc) — no default, no inference, nothing written"
  else
    fail_ "I5" "rc=$i5_rc (want non-zero) refusal_named_the_question=$i5_refused untouched=$i5_untouched"
  fi
fi

I7D="$(newtmp)"
if ! mk_adoptee "$I7D/p"; then
  fail_ "I7" "fixture setup failed"
else
  report_with_phase 2 "$I7D/report.json"
  # `internal` is above `public`, so the attestation arm is exercised too.
  _ans_s2 3 internal yes > "$I7D/answers"
  run_adopt "$I7D/p" "$I7D/answers" "$I7D/report.json"; i7_rc=$RUN_RC
  i7_class=$(jq -r '.phase1_artifacts.data_classification // "MISSING"' "$I7D/p/.claude/process-state.json" 2>/dev/null)
  seed_approval_log "$I7D/p"
  gate_in "$I7D/p" --gate phase_1_to_2; i7_gate=$GATE_RC
  i7_zdr_ok=0; i7_zdr_fail=0
  grep -q "ZDR gate: data_classification=" "$GATE_OUT" && i7_zdr_ok=1
  grep -q "data_classification not set" "$GATE_OUT" && i7_zdr_fail=1
  if [ "$i7_rc" -eq 0 ] && [ "$i7_class" = "internal" ] && [ "$i7_zdr_ok" -eq 1 ] && [ "$i7_zdr_fail" -eq 0 ]; then
    pass "I7 (positive control): an ANSWERED classification lands in process-state.json and the Phase 1->2 ZDR arm reports OK — so I6's failure cannot be vacuous"
  else
    fail_ "I7" "rc=$i7_rc classification=$i7_class gate_rc=$i7_gate zdr_ok_line=$i7_zdr_ok zdr_notset_line=$i7_zdr_fail (want 0)"
  fi
fi

# ── I6 — MUTATION: neuter data classification's non-skippability ────────────
I6R="$(newtmp)"
if ! mk_adoptee "$I6R/p" || ! mk_mirror "$I6R/fw"; then
  fail_ "I6" "fixture setup failed"
else
  report_with_phase 2 "$I6R/report.json"
  _ans_s2 3 "" yes > "$I6R/answers"   # byte-identical to I5's file
  MUT6="$I6R/fw/scripts/lib/adopt/adopt-intake.sh"
  dc_sites=$(_sites "$L_INTAKE" 'BF-ADOPT-DC-MANDATORY')
  cp "$L_INTAKE" "$I6R/orig.ref"
  _sed_inplace "$MUT6" 's|^.*BF-ADOPT-DC-MANDATORY$|    dc="$dc"   # BF-ADOPT-DC-MANDATORY|'
  chg6=$(_changed_lines "$I6R/orig.ref" "$MUT6")
  i6_parses=$(_parses "$MUT6")
  run_adopt "$I6R/p" "$I6R/answers" "$I6R/report.json" "" "$I6R/fw"; i6_rc=$RUN_RC
  i6_completed=0
  [ -f "$I6R/p/.claude/manifest.json" ] && i6_completed=1
  seed_approval_log "$I6R/p"
  gate_in "$I6R/p" --gate phase_1_to_2; i6_gate=$GATE_RC
  i6_zdr_fail=0
  grep -q "data_classification not set" "$GATE_OUT" && i6_zdr_fail=1
  if [ "$i6_rc" -eq 0 ] && [ "$i6_completed" -eq 1 ] && [ "$i6_gate" -ne 0 ] && [ "$i6_zdr_fail" -eq 1 ] \
     && [ "$chg6" -eq 2 ] && [ "$dc_sites" -eq 1 ] && [ "$i6_parses" -eq 1 ]; then
    pass "I6 (MUTATION): with non-skippability neutered (1 line, mutant still parses) the run COMPLETES without a classification — and the resulting project FAILS its own Phase 1->2 ZDR gate (rc $i6_gate) for exactly that reason"
  else
    fail_ "I6" "run_rc=$i6_rc (want 0) adoption_completed=$i6_completed gate_rc=$i6_gate (want non-zero) zdr_notset_line=$i6_zdr_fail (want 1) changed_lines=$chg6 (want 2) dc_sites=$dc_sites (want 1) parses=$i6_parses (want 1)"
  fi
fi

echo ""
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
  _ans_s2 3 > "$S2D/answers"
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
  _ans_s2 3 > "$S3D/answers"
  run_adopt "$S3D/p" "$S3D/answers" "$S3D/report.json" phase_state
  _assert_safe_row "S3 (interruption after phase-state)" "$S3D/p"
fi

S4D="$(newtmp)"
if ! mk_adoptee "$S4D/p"; then
  fail_ "S4" "fixture setup failed"
else
  report_with_phase 2 "$S4D/report.json"
  _ans_s2 3 > "$S4D/answers"
  run_adopt "$S4D/p" "$S4D/answers" "$S4D/report.json" intake
  _assert_safe_row "S4 (interruption after intake)" "$S4D/p"
fi

# ── S5 — MUTATION: reverse the order, and the unsafe row becomes reachable ──
S5R="$(newtmp)"
if ! mk_adoptee "$S5R/p" || ! mk_mirror "$S5R/fw"; then
  fail_ "S5" "fixture setup failed"
else
  report_with_phase 2 "$S5R/report.json"
  _ans_s2 3 > "$S5R/answers"
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
  _ans_s2 2 > "$T1D/answers"        # lands at 1, which keeps the BL-006
                                    # message gate short-circuited so the TDD
                                    # arm alone decides T4's verdict
  run_adopt "$T1D/p" "$T1D/answers" "$T1D/report.json"; t1_rc=$RUN_RC
  t1_anchor=$(jq -r '.adoption.adoptedAtCommit // "MISSING"' "$T1D/p/.claude/manifest.json" 2>/dev/null)
  t1_parent=$( cd "$T1D/p" && git rev-parse HEAD^ 2>/dev/null )
  t1_blocks=$(jq -r '[.. | objects | select(has("adopted"))] | length' "$T1D/p/.claude/manifest.json" 2>/dev/null)
  t1_scen=$(jq -r '.adoption.scenario // "MISSING"' "$T1D/p/.claude/manifest.json" 2>/dev/null)
  t1_landed=$(jq -r '.adoption.landedPhase // "MISSING"' "$T1D/p/.claude/manifest.json" 2>/dev/null)
  if [ "$t1_rc" -eq 0 ] && [ -n "$t1_parent" ] && [ "$t1_anchor" = "$t1_parent" ] \
     && [ "$(_num "$t1_blocks")" -eq 1 ] && [ "$t1_scen" = "in-flight" ] && [ "$t1_landed" = "1" ]; then
    pass "T1: the stamp lands ONCE and adoptedAtCommit is the PRE-adoption tip — the parent the adoption commit landed on"
  else
    fail_ "T1" "rc=$t1_rc anchor=$t1_anchor parent=$t1_parent adoption_blocks=$t1_blocks (want 1) scenario=$t1_scen landed=$t1_landed"
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
  _ans_s2 2 > "$T3D/answers"
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
  _ans_s2 3 > "$G1D/answers"
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
  _ans_s2 3 > "$G2R/answers"
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
echo "=== W — the honest stubs (§10: WP5/WP5b/WP6/WP7 are NOT built here) ==="

W1D="$(newtmp)"
if ! mk_adoptee "$W1D/p"; then
  fail_ "W1" "fixture setup failed"
else
  report_with_phase 2 "$W1D/report.json"
  _ans_s2 3 > "$W1D/answers"
  run_adopt "$W1D/p" "$W1D/answers" "$W1D/report.json"; w1_rc=$RUN_RC
  w1_cert=0; w1_record=0; w1_empty_named=0
  grep -q 'NOT DONE — the certification pass' "$RUN_OUT" && w1_cert=1
  grep -q 'NOT DONE — the Adoption Record' "$RUN_OUT" && w1_record=1
  grep -q "means 'not measured', not 'measured and clean'" "$RUN_OUT" && w1_empty_named=1
  w1_kinds=$(jq -r '[.adoption.certification.kindA, .adoption.certification.kindB, .adoption.certification.kindC] | map(length) | add' "$W1D/p/.claude/manifest.json" 2>/dev/null)
  if [ "$w1_rc" -eq 0 ] && [ "$w1_cert" -eq 1 ] && [ "$w1_record" -eq 1 ] && [ "$w1_empty_named" -eq 1 ] && [ "$(_num "$w1_kinds")" -eq 0 ]; then
    pass "W1: the unbuilt packages announce themselves — the certification lists in the stamp are empty AND the run says an empty list means 'not measured', not 'measured and clean'"
  else
    fail_ "W1" "rc=$w1_rc certification_stub=$w1_cert adoption_record_stub=$w1_record empty_means_unmeasured_stated=$w1_empty_named certification_entries=$w1_kinds (want 0)"
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
