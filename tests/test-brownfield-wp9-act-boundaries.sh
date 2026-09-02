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
#
# AND THAT COUPLING HAS A COST A FUTURE READER MUST BE TOLD ABOUT. N4 kills its
# mutant by STARVATION, so what it strictly pins is "Act 2 consumes exactly
# five answers", not "Act 2 asks no judgment questions". A later package that
# legitimately adds one confirmation row will fail N4 for the wrong reason, and
# the obvious repair — lengthening this function — silently RETIRES the proof.
# **If you lengthen it, re-derive N4 against the new length or replace it.**
# N1's report-derived deferral count is the semantic half and has no such
# coupling; between them the property is pinned twice, by different means.
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

# A FRAMEWORK ROOT IS NOT `scripts/` PLUS `init.sh`. `templates/` is part of
# it: since WP9b the driver renders APPROVAL_LOG.md from
# `$ADOPT_FRAMEWORK_ROOT/templates/generated/approval-log-*.tmpl` (A4), and a
# mirror without it makes every adoption run against that mirror REFUSE — which
# is the right behaviour on a real incomplete checkout and a silent wrecking
# ball on an incomplete test double. Mirror the templates too.
mk_mirror() {
  local m="$1"
  mkdir -p "$m" || return 1
  cp -Rp "$REPO_ROOT/scripts" "$m/" || return 1
  cp -Rp "$REPO_ROOT/templates" "$m/" || return 1
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

# C2 — §4.2's completion check, WIDENED TWICE AFTER IT MISSED SOMETHING.
#
# It began as `grep -rlF` over `scripts/`. Adversarial review found a FOURTH
# occurrence the design had never counted and this check structurally could not
# see: `workflow.html`, the non-engineer walkthrough README links from its ninth
# line, where the sentence is LINE-WRAPPED inside a `<p>`. A single-line `-F`
# search cannot match a wrapped literal, and the surface was the wrong one
# anyway — the question was never confined to `scripts/`.
#
# So this now sweeps EVERY TRACKED FILE with whitespace NORMALISED (`tr -s`
# collapses newlines and runs of spaces to one space, which is exactly the
# transform that makes a wrapped occurrence findable). Two files are allowed to
# carry it, each for a stated reason, and the allowlist is spelled here rather
# than implied by a path filter:
#   • the SUPERSEDED v1 design — a frozen artifact, stamped to the tree it was
#     written against, and out of scope by the same rule CLAUDE.md applies to
#     Reports/ and archived handoffs;
#   • THIS SUITE, which must spell the sentence to search for it.
# Untracked trees (worktrees, scratch) are excluded by using `git ls-files`,
# not by a directory denylist that would need maintaining.
# LC_ALL=C IS LOAD-BEARING, NOT DECORATION. Under a UTF-8 locale `tr` stops at
# the first byte that is invalid in that locale and emits what it had — so a
# file with any such byte is read PARTIALLY and the loop below records it as
# clean, with no signal. Measured on a tracked `.DS_Store`: 3,131 bytes under
# the ambient locale against 8,190 under LC_ALL=C, and a sentence planted past
# the truncation point is found only by the second. "A search that structurally
# cannot see part of its surface and reports clean" is verbatim the failure this
# whole check exists to prevent, so it must not be the check's own behaviour.
_normalise() { LC_ALL=C tr -s '[:space:]' ' ' < "$1"; }
c2_hits=""
while IFS= read -r f; do
  case "$f" in
    docs/designs/2026-08-02-brownfield-adoption-v1.md) continue ;;
    tests/test-brownfield-wp9-act-boundaries.sh)       continue ;;
  esac
  [ -f "$REPO_ROOT/$f" ] || continue
  if _normalise "$REPO_ROOT/$f" | grep -qF -- "$CHOOSER_LITERAL" 2>/dev/null; then
    c2_hits="$c2_hits $f"
  fi
done <<C2FILES
$( cd "$REPO_ROOT" && git ls-files )
C2FILES
if [ -z "$c2_hits" ]; then
  pass "C2: Karl's chooser sentence occurs in NO tracked file — whitespace-normalised, so a LINE-WRAPPED copy cannot hide from it, and across the whole tree rather than scripts/ alone"
else
  fail_ "C2: the chooser sentence survives" "in:$c2_hits"
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
# C4 (MUTATION) — AND IT INJECTS THE HARD CASE, NOT THE EASY ONE.
#
# The first version of this mutant appended the sentence as a single-line shell
# comment and proved the recipe found it. That certified the half that never
# escaped: the occurrence adversarial review actually found was WRAPPED across
# three lines of HTML prose, which the then-current single-line `grep -F` could
# not match at all. A mutant that only exercises the case the check already
# handles would have stayed green through the real defect.
#
# The fixture is therefore a PROSE file wrapped the way `workflow.html` wraps —
# continuation lines with leading indentation and NO per-line prefix — rather
# than a shell file, because a wrapped shell comment carries a `#` into the
# middle of the sentence and stops being the case under test. (That is not
# hypothetical: it is what the first draft of this mutant did, and it failed
# for that reason rather than for a real one.)
#
# BOTH recipes run against it, in opposite directions: the naive single-line
# one must MISS it — proving the wrapping is a genuine hazard and not a
# hypothetical — and C2's normalised one must FIND it.
C4M="$(newtmp)"
c4_target="$C4M/wrapped-prose.html"
cat > "$c4_target" <<'C4HTML'
    <div class="mod-card">
      <h4>The one question the scan cannot answer</h4>
      <p>The scan's findings are shown first as evidence, each line
      carrying its own confidence. Then, verbatim: <em>"Is the project built out and needs to be able to be
      supported (i.e. bug fixes, maintenance, new features add), or are you still in the process of building
      your project?"</em></p>
    </div>
C4HTML
c4_naive=$(grep -clF -- "$CHOOSER_LITERAL" "$c4_target" 2>/dev/null); c4_naive=$(_num "$c4_naive")
c4_norm=0
_normalise "$c4_target" | grep -qF -- "$CHOOSER_LITERAL" && c4_norm=1
# The fixture must genuinely SPAN lines, or "the naive recipe missed it" would
# be true for an uninteresting reason.
c4_span=$(grep -c 'Is the project built out' "$c4_target" 2>/dev/null); c4_span=$(_num "$c4_span")
if [ "$c4_naive" -eq 0 ] && [ "$c4_norm" -eq 1 ] && [ "$c4_span" -eq 1 ]; then
  pass "C4 (MUTATION): a LINE-WRAPPED occurrence is INVISIBLE to a single-line grep and VISIBLE to C2's normalised recipe — which is the exact shape that escaped into workflow.html and the exact shape the old check could not see"
else
  fail_ "C4 (MUTATION): the wrapped fixture did not discriminate the two recipes" "single-line-found=$c4_naive (want 0) normalised-found=$c4_norm (want 1) sentence-starts-on-one-line=$c4_span (want 1)"
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
# THE ORDERING IS THE PROPERTY, AND IT NEEDS A FIXTURE THAT CAN SEE IT. The
# guard's comment says it sits BEFORE the jq/manifest no-op arms deliberately —
# those return 0 for "this host cannot stamp" while this one returns 1 for
# "this CALL is wrong", and a caller that cannot tell them apart treats a
# malformed stamp as a host limitation. On the fixture above BOTH jq and a
# manifest exist, so swapping the order changes nothing there. A MISSING
# manifest discriminates: shipped refuses (rc 1), an order-swapped guard
# no-ops (rc 0).
e5_order=0
( cd "$E5" && soif_adoption_stamp "no-such-manifest.json" "" ) || e5_order=1

# AND THE JQ ARM, which the manifest probe alone cannot see. There are TWO
# no-op arms — `command -v jq || return 0` and `[ -f "$manifest" ] || return 0`
# — and a guard moved below the FIRST one still refuses on a missing manifest,
# so that probe passes while a jq-less host gets rc 0 ("this host cannot
# stamp") for a malformed call. Probed with jq removed from PATH, and the
# isolated PATH is asserted to genuinely lack it before the measurement is
# trusted (`# BL-233-WPB` learned that a safety-net PATH defeats its own probe).
# RUN IN A FRESH SHELL, NOT A SUBSHELL — and this cost a debugging round, so it
# is written down. bash CACHES command locations in a hash table, and
# `command -v` consults that cache: inside this suite's own process, jq has
# already been run many times, so `PATH=<empty-dir> command -v jq` STILL FINDS
# IT and the probe silently measured nothing. A `bash -c` starts with an empty
# hash table. The isolated PATH is asserted to genuinely lack jq before the
# measurement is trusted, for the same reason `# BL-233-WPB` records: a probe
# that cannot see the condition it isolates reports the happy answer.
e5_nojq_path="$E5/nojq"
mkdir -p "$e5_nojq_path"
# PATH IS SET INSIDE THE FRESH SHELL, NOT AS ITS PREFIX — the second half of
# the same lesson. `PATH=<empty-dir> bash -c …` cannot find `bash`, so the
# probe failed to launch and its `|| e5_order_jq=1` fired on the LAUNCH
# failure, reporting a refusal that never happened. Two ways to measure
# nothing, one after the other; both reported the happy answer.
e5_jq_gone=0
bash -c 'PATH="$1"; command -v jq' _ "$e5_nojq_path" >/dev/null 2>&1 || e5_jq_gone=1
e5_order_jq=0
if [ "$e5_jq_gone" -eq 1 ]; then
  ( cd "$E5" && bash -c '. "$1" >/dev/null 2>&1; PATH="$2"; soif_adoption_stamp "manifest.json" ""' _ "$L_STAMP" "$e5_nojq_path" ) || e5_order_jq=1
fi
if [ "$e5_rc" -eq 1 ] && [ "$e5_written" -eq 0 ] && [ "$e5_marker" -eq 1 ] && [ "$e5_order" -eq 1 ] \
   && [ "$e5_jq_gone" -eq 1 ] && [ "$e5_order_jq" -eq 1 ]; then
  pass "E5: an EMPTY evidence hash is refused by the stamp itself (rc $e5_rc, nothing written), and refused BEFORE BOTH no-op arms — a missing manifest AND a host with no jq each still yield a refusal rather than the rc 0 that means 'this host cannot stamp'"
else
  fail_ "E5: the stamp accepted an empty evidence hash, or checked it too late" "rc=$e5_rc block-written=$e5_written marker-sites=$e5_marker refuses-before-the-manifest-arm=$e5_order (want 1) jq-genuinely-absent=$e5_jq_gone (want 1) refuses-before-the-jq-arm=$e5_order_jq (want 1)"
fi

echo "=== V — A6: the evidence block survives, re-worded ==="

v1_signals=0
for s in "Deployment:" "Release tags:" "Recent work:" "Changelog:"; do
  grep -qF "$s" "$CTL_OUT" 2>/dev/null && v1_signals=$((v1_signals + 1))
done
v1_conf=$(grep -c "Confidence:" "$CTL_OUT" 2>/dev/null); v1_conf=$(_num "$v1_conf")
v1_stale=0; grep -qF "overrides all of it" "$CTL_OUT" 2>/dev/null && v1_stale=1
v1_phase0=0; grep -qF "starts at phase 0" "$CTL_OUT" 2>/dev/null && v1_phase0=1
# THE "USERS" LINE IS ASSERTED HERE BECAUSE IT WAS NEARLY LOST IN TRANSIT. The
# WP4 suite's deleted E1 checked three things; two were re-homed above and this
# third — the block declaring that the scan CANNOT measure whether anyone uses
# the project — was not, so for one review round the code still printed it and
# nothing pinned it. It is the block's only claim about its own LIMITS, which
# makes it the line most worth keeping honest.
v1_users=0; grep -qF "the scan cannot measure" "$CTL_OUT" 2>/dev/null && v1_users=1
if [ "$v1_signals" -eq 4 ] && [ "$v1_conf" -ge 4 ] && [ "$v1_stale" -eq 0 ] \
   && [ "$v1_phase0" -eq 1 ] && [ "$v1_users" -eq 1 ]; then
  pass "V1 (A6): all four evidence signals are still offered with confidence tiers ($v1_conf lines), 'users' is still declared unmeasurable, the sentence pointing at the deleted question is gone, and the block says the project starts at phase 0 regardless"
else
  fail_ "V1 (A6): the evidence block is not in its re-worded shape" "signals=$v1_signals confidence-lines=$v1_conf stale-sentence=$v1_stale phase0-line=$v1_phase0 users-unmeasurable=$v1_users"
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
# THE LIVE HALF. The two greps above search for literals belonging to DELETED
# functions, so against this tree they can only ever be 0 — they are revert
# canaries, not discriminators, and a suite leaning on them alone would assert
# nothing. This one is derived from the REPORT: every judgment and
# non-skippable row Scout emits must appear in the transcript as deferred, and
# the count must MATCH. It moves if the report's shape moves, which is the
# property actually worth pinning.
n1_deferrable=$(jq -r '[.intakePrefill.sections[] | select(.kind == "judgment" or .kind == "non-skippable")] | length' "$REPORT" 2>/dev/null)
n1_deferrable=$(_num "$n1_deferrable")
n1_deferred=$(grep -c "asked in the assessment" "$CTL_OUT" 2>/dev/null); n1_deferred=$(_num "$n1_deferred")
if [ "$n1_confirms" -ge 4 ] && [ "$n1_judgment" -eq 0 ] && [ "$n1_dc" -eq 0 ] && [ "$CTL_RC" -eq 0 ] \
   && [ "$n1_deferrable" -gt 0 ] && [ "$n1_deferred" -eq "$n1_deferrable" ]; then
  pass "N1 (A7): the run completed (rc $CTL_RC) having asked $n1_confirms scan-derived confirmations, and every one of the report's $n1_deferrable judgment/non-skippable rows was DEFERRED BY NAME rather than asked or dropped — a count derived from the report, not from literals of deleted functions"
else
  fail_ "N1 (A7): Act 2's question set is not confirmations-only" "confirmations=$n1_confirms judgment-asked=$n1_judgment classification-asked=$n1_dc rc=$CTL_RC deferrable-rows=$n1_deferrable deferred-in-transcript=$n1_deferred"
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

echo "=== R — the three routes A7's deferral DEPENDS ON, each executed ==="

# A7 defers the data classification to Act 4, and what makes that acceptable is
# not the deferral — it is that the operator still MEETS the question. That
# conjunct was asserted by nobody and was FALSE ON ALL THREE ROUTES when
# adversarial review executed them: `resume.sh` pointed at a section the intake
# did not label, `intake-wizard.sh --resume` raised a swallowed KeyError and
# resumed PAST the classification, and the escape hatch the ZDR block names in
# its own FAIL text died on a file adoption never wrote. All three are asserted
# here, by running them, because a claim about a route is worth exactly what an
# execution of it says.

# R1 — the route WP9a's own handoff advertises.
r1_prompt="$TOPTMP/r1-resume"
( cd "$CTL/p" && bash scripts/resume.sh ) > "$r1_prompt" 2>&1 || true
r1_fallback=1; grep -qF "Section 13 is your initialization prompt" "$r1_prompt" 2>/dev/null && r1_fallback=0
r1_heading=$(grep -c '^## 13\.' "$CTL/p/PROJECT_INTAKE.md" 2>/dev/null); r1_heading=$(_num "$r1_heading")
# ONE HEADING, COUNTED BY TITLE RATHER THAN BY NUMBER. Counting `^## 13\.`
# reads 1 whether or not the ledger's own `## Agent Initialization Prompt` row
# is also emitted five lines above it — which is the double-heading defect,
# and restoring it was green until this line existed. The first of the two
# headings was false twice over (it attributed the prompt to
# `intake-wizard.sh`'s `run_section_13`, which never runs during an adoption).
r1_titles=$(grep -c 'Agent Initialization Prompt' "$CTL/p/PROJECT_INTAKE.md" 2>/dev/null); r1_titles=$(_num "$r1_titles")

# EVERY LOAD-BEARING SENTENCE OF THE PROMPT, NOT TWO OF THEM.
#
# This block used to grep for two strings out of a ~50-line prompt that
# adoption SHIPS INTO EVERY ADOPTED PROJECT as an agent's standing
# instructions. Adversarial review inverted three of the unpinned ones — the
# phase-0 statement to "PHASE 3 and three gates have been crossed", the
# false-attachment disclaimer deleted outright, and the anti-skip rule flipped
# to "Feel free to suggest that any gate be skipped" — and every PR-blocking
# check stayed GREEN. The last of those is the exact reasoning the sentence
# beside it says "adoption exists to refuse".
#
# So the pin is a SET, and each member is here because inverting it would ship
# a specific untruth to an agent:
#   the adoption statement      — or the agent treats it as scaffolded
#   the phase-0 / no-gate line  — or D10's whole promise is reversed in prose
#   the grandfathering clause   — the sentence four words later, and round 3
#                                 inverted it while the pinned one stayed put
#   the DELIBERATELY BLANK line — or the blank cells read as answered
#   the two artifact PATHS      — a typo'd path is a dead pointer, silently
#   the "not evidence that anything was DONE PROPERLY" line — the survey's own limit
#   the test-debt "must not grow" line — or the baseline becomes a permission
#   WHAT YOU DO NOT HAVE       — the false-attachment guard
#   "Do not infer them from"    — or the agent answers the questions itself,
#                                 from the code, which is the one source §4.3
#                                 says cannot answer them
#   the classification line     — the requirement A7 defers
#   "Then run Phase 0 … from the beginning" — D10's promise as an INSTRUCTION,
#                                 distinct from the phase-0 statement of fact.
#                                 Round 3 flipped it to "run Phase 2 … from
#                                 where the project already is" at 29/0
#   "open questions, not permissions" — or every blank cell reads as consent
#   the anti-skip rule          — the one an inversion turns into permission
#
# ROUND 3 WROTE TEN MUTANTS AGAINST THIS PROMPT AND SIX SURVIVED THE FIRST
# LIST. The list is per-sentence rather than a digest for a stated reason, and
# the cost of that choice is exactly this: it must be EXTENDED when the prompt
# gains a load-bearing sentence, and nothing enforces that it was. Said plainly
# so the next reader does not assume completeness.
# A digest over the whole heredoc was the alternative and is worse: it fails on
# every innocent re-wording and tells a reader nothing about WHICH line matters.
# MATCHED AGAINST THE NORMALISED PROMPT, for the reason C2 exists: the prompt
# is WRAPPED at ~78 columns, so half these sentences straddle a newline and a
# line-oriented `grep -F` cannot see them. The first draft of this list learned
# that immediately — "nothing about it has been grandfathered" broke across two
# lines and read as missing. Same transform, same LC_ALL=C, same reason.
r1_norm="$TOPTMP/r1-prompt-normalised"
_normalise "$r1_prompt" > "$r1_norm" 2>/dev/null || : > "$r1_norm"
r1_missing=""
while IFS= read -r phrase; do
  [ -n "$phrase" ] || continue
  grep -qF -- "$phrase" "$r1_norm" 2>/dev/null || r1_missing="$r1_missing [$phrase]"
done <<'R1PHRASES'
THIS PROJECT WAS ADOPTED, NOT SCAFFOLDED
It is at PHASE 0 and no gate has been crossed
nothing about it has been grandfathered
nothing in this document may be treated as an approval
DELIBERATELY BLANK
It is not evidence that anything was DONE PROPERLY
.claude/adoption/scout-report.json
.claude/test-debt.json
a baseline that must not grow, not a list of things to ignore
WHAT YOU DO NOT HAVE
Do not act as though a process reference is attached
Do not infer them from
Data classification is NOT OPTIONAL and has no default
cross its Phase 1 to 2 gate without it, and adoption did not ask for it
Then run Phase 0 as the framework defines it, from the beginning
blank cells are open questions, not permissions
Do not suggest that any gate be skipped
That is the exact reasoning adoption exists to refuse
R1PHRASES
if [ -z "$r1_missing" ] && [ "$r1_fallback" -eq 1 ] && [ "$r1_heading" -eq 1 ] && [ "$r1_titles" -eq 1 ]; then
  pass "R1: scripts/resume.sh — the command Act 2's handoff prints — extracts a REAL prompt from the adopted intake's own '## 13.' section, and the sentences pinned below are present: adopted-not-scaffolded, phase 0 with no gate crossed, the blank cells, the survey's limit, the false-attachment disclaimer, the classification, and the anti-skip rule"
else
  fail_ "R1: the advertised route does not deliver the prompt it must" "missing-sentences:${r1_missing:- none} escaped-the-fallback=$r1_fallback section-13-headings=$r1_heading (want 1) prompt-titles=$r1_titles (want 1)"
fi

# R1b — the archive item is CONDITIONAL, asserted in BOTH directions, because a
# one-sided check passes against a writer that always omits it and against one
# that always names it.
R1BD="$(newtmp)"; mkdir -p "$R1BD/p"
r1b_with="?"; r1b_without=$(grep -c 'adoption-archive/ — anything of yours' "$CTL/p/PROJECT_INTAKE.md" 2>/dev/null); r1b_without=$(_num "$r1b_without")
if mk_adoptee "$R1BD/p"; then
  mkdir -p "$R1BD/p/.claude"
  printf '{"permissions":{}}\n' > "$R1BD/p/.claude/settings.json"
  ( cd "$R1BD/p" && git add -A && git commit -q -m "chore: their ai layer" ) >/dev/null 2>&1
  _ans 1 > "$R1BD/answers"
  run_adopt "$R1BD/p" "$R1BD/answers" "$REPORT"
  r1b_with=$(grep -c 'adoption-archive/ — anything of yours' "$R1BD/p/PROJECT_INTAKE.md" 2>/dev/null); r1b_with=$(_num "$r1b_with")
fi
if [ "$r1b_without" -eq 0 ] && [ "$r1b_with" = "1" ]; then
  pass "R1b: the prompt names .claude/adoption-archive/ ONLY when the adoption actually created one — absent on a collision-free adoptee, present on one whose AI layer collided. Naming a directory that is not there is the false-attachment class the prompt's own disclaimer exists to avoid"
else
  fail_ "R1b: the archive item is not conditional in both directions" "collision-free=$r1b_without (want 0) collided=$r1b_with (want 1)"
fi

# R2 — the wizard's resume path. Asserted as the KEY SET load_progress()
# SUBSCRIPTS, plus the resume POINT, because those are two independent defects
# and fixing either alone leaves the route broken: without the keys it raises
# KeyError, and with last_section 13 it resumes at Section 14 — PAST Section 5,
# the classification.
r2_missing=""
for k in last_section project_name platform track deployment language description; do
  jq -e --arg k "$k" 'has($k)' "$CTL/p/.claude/intake-progress.json" >/dev/null 2>&1 || r2_missing="$r2_missing $k"
done
r2_last=$(jq -r '.last_section // "MISSING"' "$CTL/p/.claude/intake-progress.json" 2>/dev/null)

# `last_section` IS NOT THE ONLY SKIP MECHANISM, and pinning it alone left the
# original defect reachable through a second door. `run_script_mode` also
# consults `is_section_complete`, which reads **completed_sections** — so a
# progress file with `last_section: 0` and `completed_sections: [1..13]`
# resumes at Section 1 and then prints `[OK] Section 5 — already complete`
# before reporting "Intake Complete!" at rc 0. That is the SAME failure §8.3a-A7
# records against the pre-fix tree, reached by a key this case did not watch.
r2_done=$(jq -r '.completed_sections | length' "$CTL/p/.claude/intake-progress.json" 2>/dev/null)
r2_done=$(_num "$r2_done")

# AND PRESENCE IS NOT VALUE. `jq -e 'has($k)'` is TRUE for an explicit null,
# and python's `shlex.quote(None)` returns '' rather than raising, so a null
# value resumes with a silently blanked field past every has()-check.
#
# NOTE THE ASYMMETRY, because the strings here used to overstate it:
# `deployment` and `track` are compared to expected VALUES; `project_name` is
# only checked NON-EMPTY, because it is the fixture directory's basename and
# pinning it would couple this case to `newtmp`'s template. A mutant writing a
# constant there survives — a known limit, stated, rather than a claim.
#
# ADOPTION KNOWS **THREE** OF THE SEVEN, NOT ONE, and the miscount here was
# load-bearing: this comment said "the one key adoption genuinely knows", which
# is why only `project_name` was asserted by value and why `deployment` and
# `track` could both be blanked at 29/0. All three are asserted by value now;
# `platform`, `language` and `description` stay empty by design and are not.
r2_pn=$(jq -r '.project_name // ""' "$CTL/p/.claude/intake-progress.json" 2>/dev/null)
r2_dep=$(jq -r '.deployment // ""' "$CTL/p/.claude/intake-progress.json" 2>/dev/null)
r2_trk=$(jq -r '.track // ""' "$CTL/p/.claude/intake-progress.json" 2>/dev/null)

if [ -z "$r2_missing" ] && [ "$r2_last" = "0" ] && [ "$r2_done" -eq 0 ] \
   && [ -n "$r2_pn" ] && [ "$r2_dep" = "personal" ] && [ "$r2_trk" = "full" ]; then
  pass "R2: .claude/intake-progress.json carries all seven keys intake-wizard.sh's load_progress() subscripts a non-empty project_name and the expected values for deployment and track, last_section is 0 AND completed_sections is empty — so --resume starts at Section 1 and WALKS Section 5 rather than skipping it by either of the two mechanisms that can"
else
  fail_ "R2: the progress file cannot be resumed from" "missing-keys:${r2_missing:- none} last_section=$r2_last (want 0) completed_sections=$r2_done (want 0) project_name='$r2_pn' (want non-empty) deployment='$r2_dep' (want personal) track='$r2_trk' (want full)"
fi

# R3 — THE ESCAPE HATCH, executed. `check-phase-gate.sh`'s Phase 1->2 ZDR block
# names `reconfigure-project.sh` in its own FAIL text; this runs it and reads
# the value back out of the file the gate reads.
#
# ON ITS OWN FIXTURE, deliberately: this case WRITES into the project, and the
# control fixture above is shared by every read-only assertion in this file. A
# case that mutates a shared fixture makes every later assertion depend on the
# order they happen to run in.
R3D="$(newtmp)"; mkdir -p "$R3D/p"
r3_src=0; r3_val="?"; r3_staged=0
if mk_adoptee "$R3D/p"; then
  _ans 1 > "$R3D/answers"
  run_adopt "$R3D/p" "$R3D/answers" "$REPORT"
  [ -s "$R3D/p/.claude/orchestrator-source.json" ] && r3_src=1
  # AND IT MUST BE IN THE ADOPTION COMMIT. A raw `>` redirect would produce the
  # file and skip `adopt_write_file` entirely — with it `adopt_touched_disk`
  # (`# BL-225-TOUCHED-DISK`), the mkdir, both refusal arms, and
  # `adopt_record_write`, which is what puts the path in the explicit staging
  # list. An unstaged hatch file is one `git checkout` from gone, so "the file
  # exists" is the weaker half of this assertion.
  r3_staged=$( cd "$R3D/p" && git show --name-only --format= HEAD 2>/dev/null | grep -c '^\.claude/orchestrator-source\.json$' )
  r3_staged=$(_num "$r3_staged")
  ( cd "$R3D/p" && bash scripts/reconfigure-project.sh --field data_classification --old "" --new internal ) >"$TOPTMP/r3-out" 2>&1 || true
  r3_val=$(jq -r '.phase1_artifacts.data_classification // "ABSENT"' "$R3D/p/.claude/process-state.json" 2>/dev/null)
fi
if [ "$r3_src" -eq 1 ] && [ "$r3_staged" -eq 1 ] && [ "$r3_val" = "internal" ]; then
  pass "R3: the escape hatch the ZDR block names in its own FAIL text WORKS on an adopted project — reconfigure-project.sh resolves .claude/orchestrator-source.json and writes the classification the gate reads"
else
  fail_ "R3: the gate names an escape hatch that does not reach an adopted project" "orchestrator-source-written=$r3_src committed=$r3_staged (want 1) classification-after=$r3_val (want internal); output: $(head -3 "$TOPTMP/r3-out" 2>/dev/null | tr '\n' '|')"
fi

# R4 (MUTATION) — and it asserts on the HATCH, not on the file. A missing file
# and a broken hatch look identical if you only check the file.
R4M="$(newtmp)"
if mk_mirror "$R4M/fw"; then
  # MARKER-BASED, and the delimiter is `/` rather than `|` ON PURPOSE. The
  # line being mutated contains `||`, and CLAUDE.md records that a `|`-delimited
  # sed whose expression carries `||` either errors or — worse — terminates
  # early and leaves the file UNCHANGED while reporting success. The changed-
  # line assertion below is the second half of that defence.
  r4_shipped=$(_sites "$L_STATE" 'BL-242-ORCH-SOURCE')
  cp -p "$R4M/fw/scripts/lib/adopt/adopt-state.sh" "$R4M/pre.sh"
  _sed_inplace "$R4M/fw/scripts/lib/adopt/adopt-state.sh" 's/^.*BL-242-ORCH-SOURCE$/  :   # BL-242-ORCH-SOURCE/'
  r4_changed=$(_changed_lines "$R4M/pre.sh" "$R4M/fw/scripts/lib/adopt/adopt-state.sh")
  r4_parse=$(_parses "$R4M/fw/scripts/lib/adopt/adopt-state.sh")
  mkdir -p "$R4M/p"; r4_val="?"
  if mk_adoptee "$R4M/p"; then
    _ans 1 > "$R4M/answers"
    run_adopt "$R4M/p" "$R4M/answers" "$REPORT" "$R4M/fw"
    ( cd "$R4M/p" && bash scripts/reconfigure-project.sh --field data_classification --old "" --new internal ) >/dev/null 2>&1 || true
    r4_val=$(jq -r '.phase1_artifacts.data_classification // "ABSENT"' "$R4M/p/.claude/process-state.json" 2>/dev/null)
  fi
  if [ "$r4_shipped" -eq 1 ] && [ "$r4_changed" -eq 2 ] && [ "$r4_parse" -eq 1 ] && [ "$r4_val" = "ABSENT" ]; then
    pass "R4 (MUTATION): drop the orchestrator-source write (1 line, mutant still parses) and the escape hatch goes DEAD — the classification stays ABSENT after running the very command the gate tells the operator to run"
  else
    fail_ "R4 (MUTATION): dropping the orchestrator-source write changed nothing observable" "shipped-sites=$r4_shipped changed=$r4_changed parses=$r4_parse classification-after=$r4_val (want ABSENT)"
  fi
else
  fail_ "R4 (MUTATION): mirror setup" "mk_mirror failed"
fi

# R5 (MUTATION) — A FAILED WRITE MUST NOT REPORT SUCCESS, and R4 does not
# cover that. R4 removes the CALL; this degrades the call's error handling from
# `|| return 1` to `|| true`, which is the shape a well-meaning "make it
# non-fatal" edit takes. The adoption then COMPLETES (rc 0) while the escape
# hatch is dead — adoption reporting success with the file the ZDR block's
# remediation depends on missing, which is the exact silent-success state R3
# and R4 exist to prevent, arriving by a door neither of them watches.
R5M="$(newtmp)"
if mk_mirror "$R5M/fw"; then
  # THE SHIPPED SPELLING IS ASSERTED POSITIVELY, AND THAT IS THIS CASE'S WHOLE
  # LESSON. R5's first version discriminated only by `_changed_lines -eq 2`
  # after its own sed rewrote the marked line to a canonical `|| true`. Against
  # a tree ALREADY carrying `|| true` in a different spelling — one space before
  # the comment instead of three — the sed still "changed" two lines, so the
  # conjunct held, and the mutant's behavioural half (`rc 0`, file absent) is
  # what the mutant produces anyway. The escape hatch was dead in the shipped
  # tree and this proof passed. **A mutation proof whose only discriminator is
  # its own edit landing proves that sed works, not that the property holds.**
  r5_shipped_refuses=$(grep -c 'BL-242-ORCH-SOURCE$' "$L_STATE" 2>/dev/null); r5_shipped_refuses=$(_num "$r5_shipped_refuses")
  r5_shipped_spelling=0
  grep -E '^[[:space:]]*adopt_write_orchestrator_source "\$root" \|\| return 1[[:space:]]+# BL-242-ORCH-SOURCE$' "$L_STATE" >/dev/null 2>&1 && r5_shipped_spelling=1

  # AND THE FUNCTION ITSELF MUST REFUSE — ASSERTED BY CALLING IT, NOT BY
  # GREPPING IT. The line above pins the CALL SITE, and a swallow moved ONE
  # LINE DOWN into the function's own writer (`| adopt_write_file … || true`)
  # leaves that call site byte-identical: the adoption then completes at rc 0
  # with a zero-byte hatch file and `reconfigure-project.sh` dead. There are
  # TWO DOORS and a textual pin on one of them cannot stand in for the
  # property, which is what a textual pin has now failed to do twice.
  #
  # So: source the lib in a subshell, stub `adopt_write_file` to fail, and
  # require the function to return non-zero. Behaviour, not spelling.
  r5_fn_refuses=0
  (
    # shellcheck source=/dev/null
    . "$REPO_ROOT/scripts/lib/adopt/adopt-core.sh" >/dev/null 2>&1
    # shellcheck source=/dev/null
    . "$L_STATE" >/dev/null 2>&1
    adopt_write_file() { return 1; }
    ADOPT_FRAMEWORK_ROOT="$REPO_ROOT"
    adopt_write_orchestrator_source "$R5M" >/dev/null 2>&1
  ) || r5_fn_refuses=1
  cp -p "$R5M/fw/scripts/lib/adopt/adopt-state.sh" "$R5M/pre.sh"
  _sed_inplace "$R5M/fw/scripts/lib/adopt/adopt-state.sh" \
    's/^.*BL-242-ORCH-SOURCE$/  adopt_write_orchestrator_source "$root" || true   # BL-242-ORCH-SOURCE/'
  r5_changed=$(_changed_lines "$R5M/pre.sh" "$R5M/fw/scripts/lib/adopt/adopt-state.sh")
  r5_parse=$(_parses "$R5M/fw/scripts/lib/adopt/adopt-state.sh")
  # Make the write ITSELF fail, so the neutered handler is what decides the
  # outcome: a read-only .claude/ defeats the writer without touching it.
  mkdir -p "$R5M/p"; r5_rc="?"; r5_src="?"
  if mk_adoptee "$R5M/p"; then
    _ans 1 > "$R5M/answers"
    _sed_inplace "$R5M/fw/scripts/lib/adopt/adopt-state.sh" \
      "s|jq -n --arg s \"\$ADOPT_FRAMEWORK_ROOT\" '{source_dir: \$s}'|false|"
    run_adopt "$R5M/p" "$R5M/answers" "$REPORT" "$R5M/fw"
    r5_rc="$RUN_RC"
    r5_src=0; [ -s "$R5M/p/.claude/orchestrator-source.json" ] && r5_src=1
  fi
  if [ "$r5_shipped_refuses" -eq 1 ] && [ "$r5_shipped_spelling" -eq 1 ] && [ "$r5_fn_refuses" -eq 1 ] \
     && [ "$r5_changed" -eq 2 ] && [ "$r5_parse" -eq 1 ] && [ "$r5_rc" = "0" ] && [ "$r5_src" = "0" ]; then
    pass "R5 (MUTATION): the SHIPPED call refuses on a failed hatch write (asserted positively, independent of this case's own edit), and with that failure swallowed the adoption COMPLETES at rc $r5_rc with the escape-hatch file ABSENT"
  else
    fail_ "R5 (MUTATION): the shipped call does not refuse, or swallowing its failure produced no silent success" "shipped-marker-sites=$r5_shipped_refuses (want 1) call-site-refuses=$r5_shipped_spelling (want 1) FUNCTION-refuses-when-its-write-fails=$r5_fn_refuses (want 1) changed=$r5_changed parses=$r5_parse rc=$r5_rc (want 0) source-file-present=$r5_src (want 0)"
  fi
else
  fail_ "R5 (MUTATION): mirror setup" "mk_mirror failed"
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
# AND WHAT THE LINE STILL CARRIES, not only what it lost. Asserting the absence
# of `scenario:` is satisfied by a line that reports nothing at all — stripping
# `(adopted: …)` too was green. A8 retired ONE field; the rest of the report is
# the reason the line exists.
g1_at=0; grep -F "Adoption stamp present and intact" "$GATE_OUT" 2>/dev/null | grep -qE 'adopted: [0-9]{4}-[0-9]{2}-[0-9]{2}T' && g1_at=1
if [ "$g1_line" -eq 1 ] && [ "$g1_scen" -eq 0 ] && [ "$g1_at" -eq 1 ]; then
  pass "G1 (A8): the adoptee's own gate reports the stamp intact, that line NAMES NO SCENARIO — a field the v2 record does not carry — and it STILL reports the adoption date, so the fix removed one field rather than gutting the line"
else
  fail_ "G1 (A8): the gate's stamp line is wrong" "line-present=$g1_line names-scenario=$g1_scen (want 0) reports-adoptedAt=$g1_at (want 1) (gate rc $GATE_RC)"
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
# A8's THIRD deliverable, which nothing pinned: the framework-documents notice
# used to print "unassigned — §10 names no owner", which is false against v2 —
# D3 gives them to WP11 (archive) and WP12b (write). Reverting it was green.
h1_docowner=0; grep -qF "WP11 archives them, WP12b writes them (D3)" "$CTL_OUT" 2>/dev/null && h1_docowner=1
h1_stale_owner=0; grep -qF "unassigned — §10 names no owner" "$CTL_OUT" 2>/dev/null && h1_stale_owner=1
if [ "$h1_act2" -eq 1 ] && [ "$h1_phase0" -eq 1 ] && [ "$h1_resume" -eq 1 ] && [ "$h1_owner" -eq 1 ] \
   && [ "$h1_stale" -eq 0 ] && [ "$h1_docowner" -eq 1 ] && [ "$h1_stale_owner" -eq 0 ]; then
  pass "H1: the run ends by saying Act 2 completed, naming the phase-0 standing and scripts/resume.sh, and announcing the assessment as WP12a's — and it no longer announces the RETIRED certification pass"
else
  fail_ "H1: the handoff block is not in its v2 shape" "act2=$h1_act2 phase0=$h1_phase0 resume=$h1_resume wp12a=$h1_owner retired-stub-still-printed=$h1_stale docs-owner-named=$h1_docowner (want 1) stale-owner-printed=$h1_stale_owner (want 0)"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
