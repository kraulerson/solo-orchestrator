#!/usr/bin/env bash
# tests/test-brownfield-wp9-act-boundaries.sh
#
# Brownfield adoption WP9a — THE CHOOSER DELETION AND THE ACT BOUNDARIES.
# Design: docs/designs/2026-08-23-brownfield-adoption-v2.md §4.2 (the deletion's
# blast radius), §4.3 (nothing replaces it — D10), §6.5 (the audience question
# survives as a TIER question — D9), §8.2 (Act 2's order), §8.3 (the stamp's v2
# shape), §8.3a-A5..A8, §10-WP9.
#
# ── WHAT THIS FILE ASSERTS ON ───────────────────────────────────────────────
# A VERDICT by exit code; a STATE CHANGE by reading the state; CONTENT by the
# content — §10's preamble, in its corrected form. Never a printed label.
#
# ── EVERY SECTION HERE ASSERTS AN ABSENCE, AND THAT IS THE HAZARD ───────────
# WP9 is mostly a deletion, so most of its assertions are of the form "X is no
# longer there" — and "the feature was removed" and "the run died before
# reaching it" produce the same silence. Every absence assertion below is
# therefore paired with a POSITIVE CONTROL in the same fixture: the run
# completed (rc 0), the state files exist, and the surviving half of the same
# surface is present. An absence with no control is a test that cannot fail.
#
# ── MUTATION HARNESS STANDARD (inherited from the WP4 suite) ────────────────
#   • anchored end-of-line markers, excised with `s|^.*MARKER$|…|`;
#   • the anchor asserted at sites==1 in its OWN shipped source;
#   • every mutant additionally asserts `bash -n`;
#   • a MODE-PRESERVING in-place edit;
#   • a FRESH fixture per scenario, from mktemp -d;
#   • mutants run against a framework MIRROR — the tree under test is never
#     edited, so a failure here cannot leave this repository mutated.
#
# Hermetic: temp dirs only, no network, no remote creation.
#
# LANE NOTE. mk_mirror below NAMES init.sh, which is the exemption predicate
# `# BL-181-UNIT-LANE-PREDICATE` reads — but this suite only READS that file,
# never runs it, so it belongs in the fast unit lane and is registered there.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRIVER="$REPO_ROOT/scripts/adopt-project.sh"
LIB_DIR="$REPO_ROOT/scripts/lib/adopt"
L_EVIDENCE="$LIB_DIR/adopt-evidence.sh"
L_STATE="$LIB_DIR/adopt-state.sh"
L_INTAKE="$LIB_DIR/adopt-intake.sh"
L_STAMP="$REPO_ROOT/scripts/lib/adoption-stamp.sh"
L_GATE="$REPO_ROOT/scripts/check-phase-gate.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }

_mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || printf '?\n'; }
_num() { case "$1" in ''|null|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac }
_parses() { bash -n "$1" >/dev/null 2>&1 && printf '1\n' || printf '0\n'; }
_sites() { local n; n=$(grep -c "$2\$" "$1" 2>/dev/null); _num "$n"; }

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

if [ ! -f "$DRIVER" ]; then
  echo "  [FAIL] setup — $DRIVER not found"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

# ── The fixture ─────────────────────────────────────────────────────────────
mk_adoptee() {
  local p="$1"
  mkdir -p "$p/src" "$p/docs" || return 1
  ( cd "$p" \
      && git init -q . \
      && git config user.email "wp9@test.invalid" \
      && git config user.name  "WP9 Test" ) >/dev/null 2>&1 || return 1
  printf '{"name":"acme-api","scripts":{"test":"npm test"}}\n' > "$p/package.json"
  printf '# acme-api\n' > "$p/README.md"
  printf '# What this is for\n\nInvoice reconciliation for small firms.\n' > "$p/docs/product.md"
  printf '# Architecture\n\nA node service and a postgres database.\n' > "$p/docs/architecture.md"
  ( cd "$p" && git add -A && git commit -q -m "chore: their own history" ) >/dev/null 2>&1 || return 1
  return 0
}

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
  echo "  [FAIL] setup — scripts/scout.sh produced no report"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

# ── The answer script, and why it is FIVE lines ─────────────────────────────
# Under A7 Act 2 asks the tier question and the scan-derived confirmations and
# NOTHING ELSE. This fixture's report carries four askable scan-derived rows
# (sections 1, 1_repo_setup, 11_5, 12; section 13 is disclosed, never asked),
# so a complete run needs exactly 1 + 4 answers. THE LENGTH IS LOAD-BEARING:
# every mutant that puts a question back runs OUT of answers and refuses, which
# is what makes those mutations discriminate.
_ans() {
  local tier="${1:-1}"
  printf '%s\n1\n1\n1\n1\n' "$tier"
}

RUN_RC=0; RUN_OUT=""; RUN_ERR=""
run_adopt() {
  local dir="$1" answers="$2" report="$3" fw="${4:-$REPO_ROOT}"
  RUN_RC=0
  RUN_OUT="$(dirname "$answers")/run-out"
  RUN_ERR="$(dirname "$answers")/run-err"
  ( cd "$dir" && bash "$fw/scripts/adopt-project.sh" --scan-report "$report" ) \
    < "$answers" > "$RUN_OUT" 2> "$RUN_ERR" || RUN_RC=$?
  return 0
}

mk_mirror() {
  local m="$1"
  mkdir -p "$m" || return 1
  cp -Rp "$REPO_ROOT/scripts" "$m/" || return 1
  cp -p "$REPO_ROOT/init.sh" "$m/" || return 1
  return 0
}

GATE_RC=0; GATE_OUT=""
gate_in() {
  local dir="$1"; shift
  GATE_RC=0
  GATE_OUT="$TOPTMP/gate-out-$$-$RANDOM"
  ( cd "$dir" && bash scripts/check-phase-gate.sh "$@" ) > "$GATE_OUT" 2>&1 || GATE_RC=$?
  return 0
}

# ── ONE CONTROL RUN, reused by every read-only assertion ────────────────────
# Built once because the adoption is slow and none of the assertions below
# mutates it. Every mutation case builds its own fresh fixture.
CTL="$(newtmp)"
mkdir -p "$CTL/p"
CTL_OK=0
if mk_adoptee "$CTL/p"; then
  _ans 1 > "$CTL/answers"
  run_adopt "$CTL/p" "$CTL/answers" "$REPORT"
  [ "$RUN_RC" -eq 0 ] && CTL_OK=1
fi
CTL_OUT="$RUN_OUT"; CTL_ERR="$RUN_ERR"; CTL_RC="$RUN_RC"

if [ "$CTL_OK" -ne 1 ]; then
  echo "  [FAIL] setup — the control adoption did not complete (rc $CTL_RC); every assertion below depends on it"
  sed -n '1,40p' "$CTL_ERR" 2>/dev/null | sed 's/^/        /'
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

echo "=== C — the chooser is GONE (D4), and the file it lived in is renamed (A5) ==="

CHOOSER_LITERAL="Is the project built out and needs to be able to be supported (i.e. bug fixes, maintenance, new features add), or are you still in the process of building your project?"

# C1 — A5's rename, with a STRUCTURAL DISCRIMINATOR. "adopt-chooser.sh is
# absent" and "the driver no longer sources anything" look identical from the
# outside, so the source loop and `bash -n` are asserted too.
c1_old=0; [ -f "$LIB_DIR/adopt-chooser.sh" ] && c1_old=1
c1_new=0; [ -f "$L_EVIDENCE" ] && c1_new=1
c1_loop_new=$(grep -c 'for _part in .*adopt-evidence' "$DRIVER" 2>/dev/null); c1_loop_new=$(_num "$c1_loop_new")
c1_loop_old=$(grep -c 'adopt-chooser' "$DRIVER" 2>/dev/null); c1_loop_old=$(_num "$c1_loop_old")
c1_parse=$(_parses "$DRIVER")
if [ "$c1_old" -eq 0 ] && [ "$c1_new" -eq 1 ] && [ "$c1_loop_new" -eq 1 ] && [ "$c1_loop_old" -eq 0 ] && [ "$c1_parse" -eq 1 ]; then
  pass "C1 (A5): adopt-chooser.sh is gone, adopt-evidence.sh is in its place, the driver's source loop names the new file and only the new file, and the driver still parses"
else
  fail_ "C1 (A5): the rename is incomplete" "old-file=$c1_old new-file=$c1_new loop-new=$c1_loop_new loop-old=$c1_loop_old parses=$c1_parse"
fi

# C2 — §4.2's completion check: the verbatim question occurs NOWHERE under
# scripts/. This is the assertion the whole deletion is measured by.
c2_hits=$(grep -rlF -- "$CHOOSER_LITERAL" "$REPO_ROOT/scripts" 2>/dev/null | wc -l | tr -d ' ')
c2_hits=$(_num "$c2_hits")
if [ "$c2_hits" -eq 0 ]; then
  pass "C2: Karl's chooser sentence occurs in NO file under scripts/ — §4.2's completion check for WP9"
else
  fail_ "C2: the chooser sentence survives under scripts/" "$c2_hits file(s): $(grep -rlF -- "$CHOOSER_LITERAL" "$REPO_ROOT/scripts" 2>/dev/null | tr '\n' ' ')"
fi

# C3a — every named symbol of §4.2's blast radius, checked against
# COMMENT-STRIPPED source. `## BL-242:` established the distinction the hard
# way when its own capability count came out wrong: COMMENTS ARE NOT CALLS.
# The deleted names are still discussed in the headers that explain why they
# went, and a check that could not tell prose from code would either force
# those explanations out of the tree or go permanently red.
_strip_comments() { sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#.*$//' "$1"; }
c3_bad=""
for sym in ADOPT_CHOOSER_QUESTION ADOPT_CHOOSER_ANSWER_BUILT ADOPT_CHOOSER_ANSWER_BUILDING \
           adopt_ask_scenario adopt_ask_ladder adopt_apply_floor adopt_decide_placement \
           ADOPT_LADDER_Q ADOPT_SCENARIO ADOPT_LANDED_PHASE; do
  n=0
  while IFS= read -r f; do
    _strip_comments "$f" | grep -q -- "$sym" && n=$((n + 1))
  done <<C3FILES
$(find "$REPO_ROOT/scripts" -name '*.sh' -type f | LC_ALL=C sort)
C3FILES
  [ "$n" -gt 0 ] && c3_bad="$c3_bad $sym($n)"
done
if [ -z "$c3_bad" ]; then
  pass "C3a: none of the ten chooser/placement symbols survives as CODE anywhere under scripts/ — comment-stripped, because comments are not calls"
else
  fail_ "C3a: chooser/placement symbols survive in executed lines" "$c3_bad"
fi

# C3b — the two MARKERS, checked against RAW source, and the split from C3a is
# the point: a marker lives in a comment by definition, so comment-stripping
# would make this check vacuous. Two checks, two domains, neither able to
# stand in for the other.
c3b_bad=""
for mk in BF-ADOPT-FLOOR BF-ADOPT-SCENARIO-ENUM; do
  n=$(grep -rl -- "$mk" "$REPO_ROOT/scripts" 2>/dev/null | wc -l | tr -d ' ')
  n=$(_num "$n")
  [ "$n" -gt 0 ] && c3b_bad="$c3b_bad $mk($n)"
done
if [ -z "$c3b_bad" ]; then
  pass "C3b: the floor and scenario-enum MARKERS are gone from the raw source too — checked unstripped, because a marker that only exists in a comment is invisible to C3a"
else
  fail_ "C3b: deleted markers survive" "$c3b_bad"
fi

# C4 (MUTATION) — C2's recipe is a grep, and a grep that matches nothing is
# indistinguishable from a grep that is wrong. Inject the literal into a MIRROR
# and re-run the identical recipe: it must find it.
C4M="$(newtmp)"
if mk_mirror "$C4M/fw"; then
  printf '\n# %s\n' "$CHOOSER_LITERAL" >> "$C4M/fw/scripts/lib/adopt/adopt-evidence.sh"
  c4_hits=$(grep -rlF -- "$CHOOSER_LITERAL" "$C4M/fw/scripts" 2>/dev/null | wc -l | tr -d ' ')
  c4_hits=$(_num "$c4_hits")
  c4_parse=$(_parses "$C4M/fw/scripts/lib/adopt/adopt-evidence.sh")
  if [ "$c4_hits" -eq 1 ] && [ "$c4_parse" -eq 1 ]; then
    pass "C4 (MUTATION): with the sentence re-injected into a mirror (mutant still parses), C2's identical recipe finds it — the absence assertion discriminates"
  else
    fail_ "C4 (MUTATION): C2's recipe did not find a re-injected sentence" "hits=$c4_hits parses=$c4_parse"
  fi
else
  fail_ "C4 (MUTATION): mirror setup" "mk_mirror failed"
fi

echo "=== D — D9's opposite pin: the TIER question survives, and its answer is consumed ==="

# D1 — the question is asked, verbatim, with both of Karl's answers.
d1_q=0; grep -qF "Who is this project for?" "$CTL_OUT" 2>/dev/null && d1_q=1
d1_a1=0; grep -qF "Just me, or me and a few people I know" "$CTL_OUT" 2>/dev/null && d1_a1=1
d1_a2=0; grep -qF "A company, a client, or people who are paying for it" "$CTL_OUT" 2>/dev/null && d1_a2=1
if [ "$d1_q" -eq 1 ] && [ "$d1_a1" -eq 1 ] && [ "$d1_a2" -eq 1 ]; then
  pass "D1 (D9): the audience question is still ASKED, verbatim, with both canned answers — D4 deleted the chooser and not this"
else
  fail_ "D1 (D9): the audience question is not asked as shipped" "q=$d1_q a1=$d1_a1 a2=$d1_a2"
fi

# D2 — BOTH DIRECTIONS. A one-sided assertion passes against a driver that
# hardcodes the tier, which is exactly the defect `# BL-221-ADOPT-TIER-KEYS`
# was filed for.
DORG="$(newtmp)"; mkdir -p "$DORG/p"
d2_org_ps=""; d2_org_mf=""
if mk_adoptee "$DORG/p"; then
  _ans 2 > "$DORG/answers"
  run_adopt "$DORG/p" "$DORG/answers" "$REPORT"
  d2_org_rc="$RUN_RC"
  d2_org_ps=$(jq -r '.deployment // "MISSING"' "$DORG/p/.claude/phase-state.json" 2>/dev/null)
  d2_org_mf=$(jq -r '.deployment // "MISSING"' "$DORG/p/.claude/manifest.json" 2>/dev/null)
fi
d2_per_ps=$(jq -r '.deployment // "MISSING"' "$CTL/p/.claude/phase-state.json" 2>/dev/null)
d2_per_mf=$(jq -r '.deployment // "MISSING"' "$CTL/p/.claude/manifest.json" 2>/dev/null)
if [ "$d2_per_ps" = "personal" ] && [ "$d2_per_mf" = "personal" ] \
   && [ "$d2_org_ps" = "organizational" ] && [ "$d2_org_mf" = "organizational" ]; then
  pass "D2 (D9): the answer lands as 'deployment' in BOTH phase-state.json and manifest.json, and it tracks the answer in BOTH directions (personal / organizational)"
else
  fail_ "D2 (D9): deployment does not track the answer in both files and both directions" "personal: ps=$d2_per_ps mf=$d2_per_mf | organizational: ps=$d2_org_ps mf=$d2_org_mf (org rc ${d2_org_rc:-?})"
fi

# D3 — the value is CONSUMED, not merely recorded. assert_choosable is the
# reader `# BL-221-ADOPT-TIER-KEYS` exists to keep honest.
# shellcheck source=/dev/null
. "$REPO_ROOT/scripts/lib/enforcement-level.sh" >/dev/null 2>&1
d3_per=1; assert_choosable "$CTL/p" >/dev/null 2>&1 && d3_per=0
d3_org=1; assert_choosable "$DORG/p" >/dev/null 2>&1 && d3_org=0
if [ "$d3_per" -eq 0 ] && [ "$d3_org" -eq 1 ]; then
  pass "D3 (D9): the recorded tier is CONSUMED — assert_choosable says choosable on the personal adoption (rc 0) and NOT choosable on the organizational one (rc 1)"
else
  fail_ "D3 (D9): assert_choosable does not discriminate the two adoptions" "personal rc=$d3_per (want 0) organizational rc=$d3_org (want 1)"
fi

# D4 (MUTATION) — drop the tier question's call. The mutant REPLACES the marked
# line with `:` rather than deleting it, so the answer script still has five
# lines for four questions; a trailing unread answer is ignored, so the run
# completes and the damage is visible in the STATE rather than in a refusal.
D4M="$(newtmp)"
if mk_mirror "$D4M/fw"; then
  d4_sites=$(_sites "$D4M/fw/scripts/lib/adopt/adopt-state.sh" 'BL-242-TIER-QUESTION')
  d4_shipped=$(_sites "$L_STATE" 'BL-242-TIER-QUESTION')
  cp -p "$D4M/fw/scripts/lib/adopt/adopt-state.sh" "$D4M/pre.sh"
  _sed_inplace "$D4M/fw/scripts/lib/adopt/adopt-state.sh" 's/^.*BL-242-TIER-QUESTION$/  :   # BL-242-TIER-QUESTION/'
  d4_changed=$(_changed_lines "$D4M/pre.sh" "$D4M/fw/scripts/lib/adopt/adopt-state.sh")
  d4_parse=$(_parses "$D4M/fw/scripts/lib/adopt/adopt-state.sh")
  mkdir -p "$D4M/p"
  d4_ps="?"; d4_mf="?"; d4_choosable="?"
  if mk_adoptee "$D4M/p"; then
    _ans 1 > "$D4M/answers"
    run_adopt "$D4M/p" "$D4M/answers" "$REPORT" "$D4M/fw"
    d4_rc="$RUN_RC"
    d4_ps=$(jq -r '.deployment // "MISSING"' "$D4M/p/.claude/phase-state.json" 2>/dev/null)
    d4_mf=$(jq -r '.deployment // "MISSING"' "$D4M/p/.claude/manifest.json" 2>/dev/null)
    d4_choosable=1; assert_choosable "$D4M/p" >/dev/null 2>&1 && d4_choosable=0
  fi
  if [ "$d4_shipped" -eq 1 ] && [ "$d4_sites" -eq 1 ] && [ "$d4_changed" -eq 2 ] && [ "$d4_parse" -eq 1 ] \
     && [ "$d4_ps" = "" ] && [ "$d4_mf" = "" ] && [ "$d4_choosable" -eq 1 ]; then
    pass "D4 (MUTATION): with the tier question's call neutered (1 line, mutant still parses), BOTH written files carry an EMPTY deployment and assert_choosable fail-closes — asserted on the value and the predicate, never on a refusal's wording"
  else
    fail_ "D4 (MUTATION): the neutered tier question did not produce an empty, fail-closed tier" "shipped-sites=$d4_shipped mirror-sites=$d4_sites changed=$d4_changed parses=$d4_parse ps='$d4_ps' mf='$d4_mf' choosable=$d4_choosable rc=${d4_rc:-?}"
  fi
else
  fail_ "D4 (MUTATION): mirror setup" "mk_mirror failed"
fi

echo "=== E — the phase-0 landing and the stamp's v2 shape (D10, §8.3) ==="

e1_phase=$(jq -r '.current_phase // "MISSING"' "$CTL/p/.claude/phase-state.json" 2>/dev/null)
e1_gates=$(jq -r '[.gates | to_entries[] | select(.value != null)] | length' "$CTL/p/.claude/phase-state.json" 2>/dev/null)
e1_gates=$(_num "$e1_gates")
if [ "$e1_phase" = "0" ] && [ "$e1_gates" -eq 0 ]; then
  pass "E1 (D10): the adoption lands at current_phase 0 with all four gate dates null — no rung is derived, by anyone"
else
  fail_ "E1 (D10): the adoption did not land at phase 0 with no gates crossed" "current_phase=$e1_phase non-null-gates=$e1_gates"
fi

# E2 (MUTATION) — the landing is a literal, and a literal is mutable. Land it
# at 3 and read the STATE back; the stamp carries no placement key to assert on
# (§8.3 removed it with D10), so phase-state is the only witness.
E2M="$(newtmp)"
if mk_mirror "$E2M/fw"; then
  e2_shipped=$(_sites "$L_STATE" 'BL-242-PHASE0-LANDING')
  cp -p "$E2M/fw/scripts/lib/adopt/adopt-state.sh" "$E2M/pre.sh"
  _sed_inplace "$E2M/fw/scripts/lib/adopt/adopt-state.sh" 's/^.*BL-242-PHASE0-LANDING$/  local adopt_landing=3   # BL-242-PHASE0-LANDING/'
  e2_changed=$(_changed_lines "$E2M/pre.sh" "$E2M/fw/scripts/lib/adopt/adopt-state.sh")
  e2_parse=$(_parses "$E2M/fw/scripts/lib/adopt/adopt-state.sh")
  mkdir -p "$E2M/p"; e2_phase="?"
  if mk_adoptee "$E2M/p"; then
    _ans 1 > "$E2M/answers"
    run_adopt "$E2M/p" "$E2M/answers" "$REPORT" "$E2M/fw"
    e2_phase=$(jq -r '.current_phase // "MISSING"' "$E2M/p/.claude/phase-state.json" 2>/dev/null)
  fi
  if [ "$e2_shipped" -eq 1 ] && [ "$e2_changed" -eq 2 ] && [ "$e2_parse" -eq 1 ] && [ "$e2_phase" = "3" ]; then
    pass "E2 (MUTATION): with the landing moved off 0 (1 line, mutant still parses) the fixture lands at phase $e2_phase — E1 reads a real decision, not a constant nobody sets"
  else
    fail_ "E2 (MUTATION): the moved landing did not show up in phase-state" "shipped-sites=$e2_shipped changed=$e2_changed parses=$e2_parse phase=$e2_phase"
  fi
else
  fail_ "E2 (MUTATION): mirror setup" "mk_mirror failed"
fi

# E3 — the stamp's shape, asserted as a KEY SET. Four separate "key is absent"
# assertions would each pass against a partial deletion; the set would not.
e3_keys=$(jq -r '.adoption | keys | join(",")' "$CTL/p/.claude/manifest.json" 2>/dev/null)
e3_want="adopted,adoptedAt,adoptedAtCommit,scannerReportSha256,schemaVersion"
e3_ver=$(jq -r '.adoption.schemaVersion // "MISSING"' "$CTL/p/.claude/manifest.json" 2>/dev/null)
if [ "$e3_keys" = "$e3_want" ] && [ "$e3_ver" = "2" ]; then
  pass "E3 (§8.3): the stamp's key set is exactly {adopted, adoptedAt, adoptedAtCommit, scannerReportSha256, schemaVersion} at schemaVersion 2 — scenario, landedPhase, certification and blockersAccepted are all gone, asserted as a SET"
else
  fail_ "E3 (§8.3): the stamp's v2 key set is wrong" "got '$e3_keys' (schemaVersion $e3_ver), want '$e3_want' at 2"
fi

# E4 — the restamp refusal is the property the enum deletion must not have
# taken with it. Exit-code asserted, and the file compared byte-for-byte.
E4="$(newtmp)"
# shellcheck source=/dev/null
. "$L_STAMP" >/dev/null 2>&1
( cd "$E4" && git init -q . && git config user.email s@t.invalid && git config user.name S ) >/dev/null 2>&1
printf '{"host":"github"}\n' > "$E4/manifest.json"
( cd "$E4" && git add -A && git commit -q -m x ) >/dev/null 2>&1
e4_first=0; ( cd "$E4" && soif_adoption_stamp "manifest.json" "deadbeef" ) || e4_first=$?
cp -p "$E4/manifest.json" "$E4/after-first.json"
e4_second=0; ( cd "$E4" && soif_adoption_stamp "manifest.json" "cafebabe" ) || e4_second=$?
e4_same=0; cmp -s "$E4/manifest.json" "$E4/after-first.json" && e4_same=1
if [ "$e4_first" -eq 0 ] && [ "$e4_second" -eq 1 ] && [ "$e4_same" -eq 1 ]; then
  pass "E4 (regression): the stamp still lands once and REFUSES the second (rc $e4_second), leaving the manifest byte-identical — the enum's deletion did not take the restamp refusal with it"
else
  fail_ "E4 (regression): stamp-once is not a property any more" "first-rc=$e4_first second-rc=$e4_second unchanged=$e4_same"
fi

# E5 — the guard that REPLACES the deleted enum. The old refusal kept a
# malformed durable record out; with no scenario to validate, the evidence hash
# is what is left to validate, and the stamp validates it itself rather than
# trusting its one caller to.
E5="$(newtmp)"
( cd "$E5" && git init -q . && git config user.email s@t.invalid && git config user.name S ) >/dev/null 2>&1
printf '{"host":"github"}\n' > "$E5/manifest.json"
( cd "$E5" && git add -A && git commit -q -m x ) >/dev/null 2>&1
e5_rc=0; ( cd "$E5" && soif_adoption_stamp "manifest.json" "" ) || e5_rc=$?
e5_written=0; jq -e '.adoption' "$E5/manifest.json" >/dev/null 2>&1 && e5_written=1
e5_marker=$(_sites "$L_STAMP" 'BL-242-STAMP-SHA-REQUIRED')
if [ "$e5_rc" -eq 1 ] && [ "$e5_written" -eq 0 ] && [ "$e5_marker" -eq 1 ]; then
  pass "E5: an EMPTY evidence hash is refused by the stamp itself (rc $e5_rc, nothing written) — the durable record never claims a hash it does not have"
else
  fail_ "E5: the stamp accepted an empty evidence hash" "rc=$e5_rc block-written=$e5_written marker-sites=$e5_marker"
fi

echo "=== V — A6: the evidence block survives, re-worded ==="

v1_signals=0
for s in "Deployment:" "Release tags:" "Recent work:" "Changelog:"; do
  grep -qF "$s" "$CTL_OUT" 2>/dev/null && v1_signals=$((v1_signals + 1))
done
v1_conf=$(grep -c "Confidence:" "$CTL_OUT" 2>/dev/null); v1_conf=$(_num "$v1_conf")
v1_stale=0; grep -qF "overrides all of it" "$CTL_OUT" 2>/dev/null && v1_stale=1
v1_phase0=0; grep -qF "starts at phase 0" "$CTL_OUT" 2>/dev/null && v1_phase0=1
if [ "$v1_signals" -eq 4 ] && [ "$v1_conf" -ge 4 ] && [ "$v1_stale" -eq 0 ] && [ "$v1_phase0" -eq 1 ]; then
  pass "V1 (A6): all four evidence signals are still offered with confidence tiers ($v1_conf lines), the sentence pointing at the deleted question is gone, and the block says the project starts at phase 0 regardless"
else
  fail_ "V1 (A6): the evidence block is not in its re-worded shape" "signals=$v1_signals confidence-lines=$v1_conf stale-sentence=$v1_stale phase0-line=$v1_phase0"
fi

# V2 (MUTATION) — the positive half of V1 is the load-bearing one: an assertion
# that the OLD sentence is gone passes against a driver that prints nothing.
V2M="$(newtmp)"
if mk_mirror "$V2M/fw"; then
  v2_shipped=$(_sites "$L_STATE" 'BL-242-EVIDENCE-CALL')
  cp -p "$V2M/fw/scripts/lib/adopt/adopt-state.sh" "$V2M/pre.sh"
  _sed_inplace "$V2M/fw/scripts/lib/adopt/adopt-state.sh" 's/^.*BL-242-EVIDENCE-CALL$/  :   # BL-242-EVIDENCE-CALL/'
  v2_changed=$(_changed_lines "$V2M/pre.sh" "$V2M/fw/scripts/lib/adopt/adopt-state.sh")
  v2_parse=$(_parses "$V2M/fw/scripts/lib/adopt/adopt-state.sh")
  mkdir -p "$V2M/p"; v2_signals="?"; v2_rc="?"
  if mk_adoptee "$V2M/p"; then
    _ans 1 > "$V2M/answers"
    run_adopt "$V2M/p" "$V2M/answers" "$REPORT" "$V2M/fw"
    v2_rc="$RUN_RC"
    v2_signals=0
    for s in "Deployment:" "Release tags:" "Recent work:" "Changelog:"; do
      grep -qF "$s" "$RUN_OUT" 2>/dev/null && v2_signals=$((v2_signals + 1))
    done
  fi
  if [ "$v2_shipped" -eq 1 ] && [ "$v2_changed" -eq 2 ] && [ "$v2_parse" -eq 1 ] \
     && [ "$v2_signals" = "0" ] && [ "$v2_rc" = "0" ]; then
    pass "V2 (MUTATION): with the evidence call neutered (1 line, mutant still parses) all four signals vanish while the run STILL COMPLETES (rc $v2_rc) — the absence is the deletion's, not a crash's"
  else
    fail_ "V2 (MUTATION): neutering the evidence call did not remove the signals from a completing run" "shipped-sites=$v2_shipped changed=$v2_changed parses=$v2_parse signals=$v2_signals rc=$v2_rc"
  fi
else
  fail_ "V2 (MUTATION): mirror setup" "mk_mirror failed"
fi

echo "=== N — A7: Act 2 asks the confirmations and NOTHING ELSE ==="

n1_confirms=$(grep -c "Where that came from:" "$CTL_OUT" 2>/dev/null); n1_confirms=$(_num "$n1_confirms")
n1_judgment=0
for q in "What problem does this project solve" "What constrains this work" "What worries you most"; do
  grep -qF "$q" "$CTL_OUT" 2>/dev/null && n1_judgment=1
done
n1_dc=0; grep -qF "highest classification of any data" "$CTL_OUT" 2>/dev/null && n1_dc=1
if [ "$n1_confirms" -ge 4 ] && [ "$n1_judgment" -eq 0 ] && [ "$n1_dc" -eq 0 ] && [ "$CTL_RC" -eq 0 ]; then
  pass "N1 (A7): the run completed (rc $CTL_RC) having asked $n1_confirms scan-derived confirmations and NO judgment question and NO data-classification question — the positive half is the control"
else
  fail_ "N1 (A7): Act 2's question set is not confirmations-only" "confirmations=$n1_confirms judgment-asked=$n1_judgment classification-asked=$n1_dc rc=$CTL_RC"
fi

# N2 — what Act 2 WRITES: the confirmed cells present, the judgment cells blank
# and marked as Act 3's rather than silently absent.
n2_confirmed=0; grep -qF "acme-api" "$CTL/p/PROJECT_INTAKE.md" 2>/dev/null && n2_confirmed=1
n2_deferred=$(grep -c "asked in the assessment" "$CTL/p/PROJECT_INTAKE.md" 2>/dev/null); n2_deferred=$(_num "$n2_deferred")
n2_scenario=0; grep -qE "^Scenario:" "$CTL/p/PROJECT_INTAKE.md" 2>/dev/null && n2_scenario=1
if [ "$n2_confirmed" -eq 1 ] && [ "$n2_deferred" -ge 8 ] && [ "$n2_scenario" -eq 0 ]; then
  pass "N2 (A7): PROJECT_INTAKE.md carries the confirmed cells, marks $n2_deferred judgment cells as the assessment's rather than dropping them, and no longer opens with a scenario line"
else
  fail_ "N2 (A7): the written intake is not in its Act-2 shape" "confirmed=$n2_confirmed deferred-rows=$n2_deferred scenario-line=$n2_scenario"
fi

# N3 — init-parity row 5: the process-state FILE survives A7 even though the
# .phase1_artifacts merge inside it moves to Act 4.
n3_file=0; [ -f "$CTL/p/.claude/process-state.json" ] && n3_file=1
n3_dc=$(jq -r '.phase1_artifacts.data_classification // "ABSENT"' "$CTL/p/.claude/process-state.json" 2>/dev/null)
if [ "$n3_file" -eq 1 ] && [ "$n3_dc" = "ABSENT" ]; then
  pass "N3 (A7): .claude/process-state.json is still created — init.sh writes one and an adoptee must have one — and it carries NO data classification, because Act 2 no longer asks for one"
else
  fail_ "N3 (A7): process-state is not in its post-A7 shape" "file=$n3_file classification=$n3_dc"
fi

# N4 (MUTATION) — put the questions back. The answer script is exactly long
# enough for the confirmations, so a driver that asks anything more runs OUT of
# answers and refuses: the mutant's damage is visible as a REFUSAL and an
# ABSENT phase-state, not as a wording change.
N4M="$(newtmp)"
if mk_mirror "$N4M/fw"; then
  n4_shipped=$(_sites "$L_INTAKE" 'BL-242-INTAKE-CONFIRM-ONLY')
  cp -p "$N4M/fw/scripts/lib/adopt/adopt-intake.sh" "$N4M/pre.sh"
  _sed_inplace "$N4M/fw/scripts/lib/adopt/adopt-intake.sh" \
    's/^.*BL-242-INTAKE-CONFIRM-ONLY$/            adopt_ask_free "$title" "$title?" || return 1   # BL-242-INTAKE-CONFIRM-ONLY/'
  n4_changed=$(_changed_lines "$N4M/pre.sh" "$N4M/fw/scripts/lib/adopt/adopt-intake.sh")
  n4_parse=$(_parses "$N4M/fw/scripts/lib/adopt/adopt-intake.sh")
  mkdir -p "$N4M/p"; n4_rc="?"; n4_state=1
  if mk_adoptee "$N4M/p"; then
    _ans 1 > "$N4M/answers"
    run_adopt "$N4M/p" "$N4M/answers" "$REPORT" "$N4M/fw"
    n4_rc="$RUN_RC"
    n4_state=0; [ -f "$N4M/p/.claude/phase-state.json" ] && n4_state=1
  fi
  if [ "$n4_shipped" -eq 1 ] && [ "$n4_changed" -eq 2 ] && [ "$n4_parse" -eq 1 ] \
     && [ "$n4_rc" = "1" ] && [ "$n4_state" -eq 0 ]; then
    pass "N4 (MUTATION): with Act 2 asking the judgment rows again (1 line, mutant still parses), the same five-answer script runs out and the adoption REFUSES (rc $n4_rc) with no phase-state written — asserted on the exit code and the absent state"
  else
    fail_ "N4 (MUTATION): restoring Act 2's judgment questions changed nothing observable" "shipped-sites=$n4_shipped changed=$n4_changed parses=$n4_parse rc=$n4_rc phase-state-written=$n4_state"
  fi
else
  fail_ "N4 (MUTATION): mirror setup" "mk_mirror failed"
fi

echo "=== G — A8: the gate stops naming a scenario it no longer records ==="

# THE FIXTURE IS HAND-STUBBED HERE, AND SAYING SO IS NOT OPTIONAL. As WP9a
# leaves it, an adopted tree has a `.claude/phase-state.json` and no
# `APPROVAL_LOG.md`, and `check-phase-gate.sh` REFUSES on that pairing in its
# precondition block — before it parses a phase and long before it reaches the
# adoption block this section is about. Measured, not assumed:
#
#   [FAIL] APPROVAL_LOG.md not found but .claude/phase-state.json exists.
#
# So A8's line is UNREACHABLE on an unstubbed WP9a fixture. The stub is one
# line and it is honest about what it stands in for: **A4 writes this file for
# real in WP9b**, and when it lands this helper should be deleted rather than
# kept. A review round on this design was already misled once by a scorecard
# produced against a fixture that hand-stubbed exactly this file without
# recording it.
_stub_approval_log() { printf '# Approval Log\n' > "$1/APPROVAL_LOG.md"; }

_stub_approval_log "$CTL/p"
gate_in "$CTL/p"
g1_line=0; grep -qF "Adoption stamp present and intact" "$GATE_OUT" 2>/dev/null && g1_line=1
g1_scen=0; grep -F "Adoption stamp present and intact" "$GATE_OUT" 2>/dev/null | grep -q "scenario:" && g1_scen=1
if [ "$g1_line" -eq 1 ] && [ "$g1_scen" -eq 0 ]; then
  pass "G1 (A8): the adoptee's own gate reports the stamp intact (the positive control) and that line NAMES NO SCENARIO — a field the v2 record does not carry"
else
  fail_ "G1 (A8): the gate's stamp line is wrong" "line-present=$g1_line names-scenario=$g1_scen (gate rc $GATE_RC)"
fi

G2M="$(newtmp)"
if mk_mirror "$G2M/fw"; then
  g2_shipped=$(_sites "$L_GATE" 'BL-242-GATE-OK-LINE')
  cp -p "$G2M/fw/scripts/check-phase-gate.sh" "$G2M/pre.sh"
  _sed_inplace "$G2M/fw/scripts/check-phase-gate.sh" \
    's/^.*BL-242-GATE-OK-LINE$/    echo -e "${GREEN}[OK]${NC} Adoption stamp present and intact (scenario: $(soif_adoption_read ".claude\/manifest.json" ".adoption.scenario \/\/ \\"unknown\\""), adopted: $cpg_adopt_at)"   # BL-242-GATE-OK-LINE/'
  g2_changed=$(_changed_lines "$G2M/pre.sh" "$G2M/fw/scripts/check-phase-gate.sh")
  g2_parse=$(_parses "$G2M/fw/scripts/check-phase-gate.sh")
  mkdir -p "$G2M/p"; g2_scen="?"
  if mk_adoptee "$G2M/p"; then
    _ans 1 > "$G2M/answers"
    run_adopt "$G2M/p" "$G2M/answers" "$REPORT" "$G2M/fw"
    _stub_approval_log "$G2M/p"
    gate_in "$G2M/p"
    g2_scen=0; grep -F "Adoption stamp present and intact" "$GATE_OUT" 2>/dev/null | grep -q "scenario: unknown" && g2_scen=1
  fi
  if [ "$g2_shipped" -eq 1 ] && [ "$g2_changed" -eq 2 ] && [ "$g2_parse" -eq 1 ] && [ "$g2_scen" = "1" ]; then
    pass "G2 (MUTATION): with the scenario read restored (1 line, mutant still parses) the gate prints 'scenario: unknown' on a correctly-stamped project — which is the exact misreport A8 removes"
  else
    fail_ "G2 (MUTATION): restoring the scenario read did not produce the misreport" "shipped-sites=$g2_shipped changed=$g2_changed parses=$g2_parse names-unknown=$g2_scen"
  fi
else
  fail_ "G2 (MUTATION): mirror setup" "mk_mirror failed"
fi

echo "=== H — Act 2 ends by handing off, and says what is NOT built (§8.1, §10) ==="

h1_act2=0; grep -qF "Act 2" "$CTL_OUT" 2>/dev/null && h1_act2=1
h1_phase0=0; grep -qF "phase 0" "$CTL_OUT" 2>/dev/null && h1_phase0=1
h1_resume=0; grep -qF "scripts/resume.sh" "$CTL_OUT" 2>/dev/null && h1_resume=1
h1_owner=0; grep -qF "WP12a" "$CTL_OUT" 2>/dev/null && h1_owner=1
h1_stale=0; grep -qF "the certification pass" "$CTL_OUT" 2>/dev/null && h1_stale=1
if [ "$h1_act2" -eq 1 ] && [ "$h1_phase0" -eq 1 ] && [ "$h1_resume" -eq 1 ] && [ "$h1_owner" -eq 1 ] && [ "$h1_stale" -eq 0 ]; then
  pass "H1: the run ends by saying Act 2 completed, naming the phase-0 standing and scripts/resume.sh, and announcing the assessment as WP12a's — and it no longer announces the RETIRED certification pass"
else
  fail_ "H1: the handoff block is not in its v2 shape" "act2=$h1_act2 phase0=$h1_phase0 resume=$h1_resume wp12a=$h1_owner retired-stub-still-printed=$h1_stale"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
