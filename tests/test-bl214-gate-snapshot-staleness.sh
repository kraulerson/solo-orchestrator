#!/usr/bin/env bash
# tests/test-bl214-gate-snapshot-staleness.sh — BL-214.
#
# THE DEFECT, IN ONE SENTENCE: a PASSING phase gate plants the seed of its own
# next failure.
#
# `check-phase-gate.sh::create_gate_snapshot` writes into `docs/snapshots/` at
# PASS time. `_cpg_scoped_dirty` — the scoped porcelain that BL-082's freshness
# check reads to decide whether a Phase 3 summary is still fresh — excluded
# `.claude/` and the results directory but NOT `docs/snapshots/`. So on any
# project where `docs/snapshots/` is not gitignored, gate run 1 exits 0 and
# prints `[OK] Phase gate snapshot created: docs/snapshots/phase-N-to-M_<date>`,
# `git status` then shows `?? docs/snapshots/`, and gate run 2 reports
# `[STALE] … there are uncommitted changes since this summary was generated`
# and FAILs when auto-regeneration is off or unavailable. The operator eats a
# spurious stale-fail, or a costly re-validation, until they commit the
# snapshot the gate itself made.
#
# THE FIX IS ONE PATHSPEC IN TWO PLACES, AND THE TWO ARE SYNC SIBLINGS.
# `_cpg_scoped_dirty` (scripts/check-phase-gate.sh) and `_p3_scoped_dirty`
# (scripts/run-phase3-validation.sh) are kept TEXTUALLY IDENTICAL, and each
# one's own comment says so about the other. `# BL-214-SNAPSHOT-EXCLUDE` marks
# both. B1 below is the pin that makes "textually identical" a checked property
# rather than a hope: it extracts both function bodies and compares them modulo
# the function name, so a future edit to one alone goes RED here even if the
# behaviour rows all still pass on the file that was edited.
#
# ═════════════════════════════════════════════════════════════════════════════
# WHY THE FIXTURE PATH IS DERIVED AND NOT RETYPED
#
# The row that matters is "the directory the gate ITSELF writes at PASS time no
# longer stales the next run". A test that hard-codes `docs/snapshots/foo` is
# asserting something weaker — that some path under that prefix is excluded —
# and would stay green if `create_gate_snapshot` were later changed to write
# somewhere else. So B2 reads the `snapshot_dir=` assignment out of
# check-phase-gate.sh, expands it against a real phase pair and today's date,
# and dirties THAT. If the two ever part company the fixture stops being about
# the gate and the extraction guard says so.
#
# ═════════════════════════════════════════════════════════════════════════════
# BOTH DIRECTIONS, ALWAYS
#
# An exclusion is only correct if it excludes the right thing AND still catches
# everything else. Every behaviour row below is paired: snapshot-only dirt
# answers "no", real dirt answers "yes", and the four mutants each remove the
# new pathspec from exactly one call site and are killed by the "no" side while
# the "yes" side stays green — which is what shows the mutant broke the fix and
# not the whole predicate.
#
# EXIT CODES / VALUES, NEVER LABELS. These two functions do not print a banner;
# they echo `yes` or `no`, and that string is the predicate under test.
#
# LANE: registered in tests/full-project-test-suite.sh AND in the tests.yml
# `unit-shard` list. Its executed lines never name the init script.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v git >/dev/null 2>&1; then
  echo "git is required for tests/test-bl214-gate-snapshot-staleness.sh" >&2
  exit 2
fi

GATE="$REPO_ROOT/scripts/check-phase-gate.sh"
DRIVER="$REPO_ROOT/scripts/run-phase3-validation.sh"

# ── Extraction ──────────────────────────────────────────────────────────────
# The two predicates live inside scripts that run top to bottom when sourced,
# so they cannot simply be sourced. They are lifted out by name — from the
# `name() {` line to the first `}` at column zero — and the lift is VERIFIED,
# because an extraction that silently produced nothing would make every row
# below pass against an empty function.
_extract_fn() {   # <file> <fn-name>
  awk -v fn="$2" '
    $0 ~ "^" fn "\\(\\) \\{" { on = 1 }
    on { print }
    on && /^\}$/ { exit }
  ' "$1"
}

# _harness <file> <fn-name> <out> — a runnable one-function script.
_harness() {
  local file="$1" fn="$2" out="$3" body
  body="$(_extract_fn "$file" "$fn")"
  case "$body" in
    *"git status --porcelain"*) : ;;
    *) echo "  [FIXTURE] could not extract $fn from $file — the harness would test nothing" >&2
       FAILED=$((FAILED + 1)); return 1 ;;
  esac
  {
    echo '#!/usr/bin/env bash'
    echo 'set -uo pipefail'
    printf '%s\n' "$body"
    printf '%s "$@"\n' "$fn"
  } > "$out"
  chmod +x "$out"
  return 0
}

# ── The snapshot path the GATE ITSELF writes ────────────────────────────────
# Lifted from create_gate_snapshot's own assignment rather than retyped.
SNAP_TEMPLATE="$(grep -m1 'snapshot_dir=' "$GATE" | sed -e 's/^[[:space:]]*//' -e 's/^local[[:space:]]*//' -e 's/^snapshot_dir=//' -e 's/^"//' -e 's/"$//')"
SNAP_DIR="$(printf '%s' "$SNAP_TEMPLATE" \
  | sed -e 's/\${from_phase}/3/' -e 's/\${to_phase}/4/' -e "s|\\\$(date +%Y-%m-%d)|$(date +%Y-%m-%d)|")"

echo "== tests/test-bl214-gate-snapshot-staleness.sh =="
echo ""

case "$SNAP_DIR" in
  docs/snapshots/phase-3-to-4_[0-9][0-9][0-9][0-9]-*)
    pass "B0: the fixture path is derived from check-phase-gate.sh's own create_gate_snapshot assignment, not retyped — '$SNAP_DIR'"
    ;;
  *)
    fail_ "B0" "could not derive the snapshot directory from the gate (got '$SNAP_DIR' from template '$SNAP_TEMPLATE') — every row below would be testing a path the gate does not write"
    ;;
esac

# ── B1: the SYNC-SIBLING pin ────────────────────────────────────────────────
CPG_BODY="$(_extract_fn "$GATE" _cpg_scoped_dirty | sed -e 's/_cpg_scoped_dirty/_SIBLING_/')"
P3_BODY="$(_extract_fn "$DRIVER" _p3_scoped_dirty | sed -e 's/_p3_scoped_dirty/_SIBLING_/')"
b1_len="$(printf '%s\n' "$CPG_BODY" | grep -c . || true)"
case "$b1_len" in ''|*[!0-9]*) b1_len=0 ;; esac
if [ "$b1_len" -gt 5 ] && [ "$CPG_BODY" = "$P3_BODY" ]; then
  pass "B1: _cpg_scoped_dirty and _p3_scoped_dirty are byte-identical modulo their names ($b1_len lines) — their own comments claim it, and BL-214 exists because a change to one alone is the failure mode. This row makes the claim checkable"
else
  fail_ "B1" "the two sync siblings have diverged ($b1_len lines lifted). Diff:
$(diff <(printf '%s\n' "$CPG_BODY") <(printf '%s\n' "$P3_BODY") || true)"
fi

# ── Fixtures ────────────────────────────────────────────────────────────────
mk_repo() {
  local d="$1"
  mkdir -p "$d"
  (
    cd "$d" && unset GITHUB_BASE_REF
    git init -q .
    git config user.email "bl214@example.invalid"
    git config user.name "BL-214 Fixture"
    git config commit.gpgsign false
    mkdir -p docs/test-results .claude src
    printf 'seed\n' > README.md
    printf 'seed\n' > "src/app.js"
    mkdir -p "$1/$SNAP_DIR" 2>/dev/null || true
    git add README.md src/app.js
    git commit -q -m "chore: seed"
  ) >/dev/null 2>&1
}

# run_pred <harness> <project-dir> [results-dir] -> echoes yes/no
run_pred() {
  local h="$1" p="$2" rd="${3:-}"
  ( cd "$p" && unset GITHUB_BASE_REF; bash "$h" "$rd" </dev/null 2>/dev/null )
}

TD=$(mktemp -d)
H_CPG="$TD/h-cpg.sh"
H_P3="$TD/h-p3.sh"
_harness "$GATE" _cpg_scoped_dirty "$H_CPG" || true
_harness "$DRIVER" _p3_scoped_dirty "$H_P3" || true

# ── B2: the gate's OWN PASS-time write no longer stales the next run ────────
# Untracked (`?? docs/snapshots/`) is exactly what the backlog's reproduction
# recorded after gate run 1.
P="$TD/snapshot-dirt"; mk_repo "$P"
mkdir -p "$P/$SNAP_DIR"
printf 'snapshot copy\n' > "$P/$SNAP_DIR/PRODUCT_MANIFESTO.md"
b2_cpg_rd="$(run_pred "$H_CPG" "$P" docs/test-results)"
b2_cpg_no="$(run_pred "$H_CPG" "$P" "")"
b2_p3_rd="$(run_pred "$H_P3" "$P" docs/test-results)"
b2_p3_no="$(run_pred "$H_P3" "$P" "")"
if [ "$b2_cpg_rd" = no ] && [ "$b2_cpg_no" = no ] && [ "$b2_p3_rd" = no ] && [ "$b2_p3_no" = no ]; then
  pass "B2: with ONLY the gate's own snapshot directory dirty, both predicates answer 'no' on both call shapes (with a results dir and without) — a passing gate no longer plants its own next stale-fail"
else
  fail_ "B2" "cpg: results-dir='$b2_cpg_rd' bare='$b2_cpg_no'; p3: results-dir='$b2_p3_rd' bare='$b2_p3_no'; all four want 'no'"
fi

# ── B3: REAL dirt still stales (the other direction) ────────────────────────
P="$TD/real-dirt"; mk_repo "$P"
mkdir -p "$P/$SNAP_DIR"
printf 'snapshot copy\n' > "$P/$SNAP_DIR/PRODUCT_MANIFESTO.md"
printf 'changed\n' >> "$P/src/app.js"
b3_cpg="$(run_pred "$H_CPG" "$P" docs/test-results)"
b3_p3="$(run_pred "$H_P3" "$P" docs/test-results)"
P2="$TD/real-dirt-untracked"; mk_repo "$P2"
printf 'new\n' > "$P2/src/new-feature.js"
b3_cpg_u="$(run_pred "$H_CPG" "$P2" docs/test-results)"
b3_p3_u="$(run_pred "$H_P3" "$P2" docs/test-results)"
if [ "$b3_cpg" = yes ] && [ "$b3_p3" = yes ] && [ "$b3_cpg_u" = yes ] && [ "$b3_p3_u" = yes ]; then
  pass "B3: real source dirt still stales a summary, both modified-tracked ('$b3_cpg'/'$b3_p3') and untracked ('$b3_cpg_u'/'$b3_p3_u') — the exclusion narrowed the scope by one directory and not by more"
else
  fail_ "B3" "modified: cpg='$b3_cpg' p3='$b3_p3'; untracked: cpg='$b3_cpg_u' p3='$b3_p3_u'; all four want 'yes'"
fi

# ── B4: the two PRE-EXISTING exclusions are untouched ───────────────────────
P="$TD/claude-dirt"; mk_repo "$P"
printf '{}\n' > "$P/.claude/phase-state.json"
b4_claude="$(run_pred "$H_CPG" "$P" docs/test-results)"
P="$TD/results-dirt"; mk_repo "$P"
printf 'summary\n' > "$P/docs/test-results/phase3-summary.md"
b4_results="$(run_pred "$H_CPG" "$P" docs/test-results)"
b4_results_bare="$(run_pred "$H_CPG" "$P" "")"
if [ "$b4_claude" = no ] && [ "$b4_results" = no ] && [ "$b4_results_bare" = yes ]; then
  pass "B4: BL-082's original exclusions still behave — .claude/ dirt answers 'no', results-dir dirt answers 'no' WHEN the results dir is passed and 'yes' when it is not ('$b4_results' / '$b4_results_bare'), which is the parameterised half working as designed"
else
  fail_ "B4" ".claude='$b4_claude' (want no); results-dir='$b4_results' (want no); results-dir with no argument='$b4_results_bare' (want yes)"
fi

# ── B5: a TRACKED, MODIFIED snapshot file is excluded too ───────────────────
# The pathspec excludes a path, not an untracked state, and a re-run of the gate
# on a day a snapshot already exists MODIFIES it rather than creating it.
P="$TD/tracked-snapshot"; mk_repo "$P"
mkdir -p "$P/$SNAP_DIR"
printf 'snapshot copy\n' > "$P/$SNAP_DIR/PRODUCT_MANIFESTO.md"
( cd "$P" && unset GITHUB_BASE_REF; git add "$SNAP_DIR" && git commit -q -m "chore: commit the snapshot" ) >/dev/null 2>&1
printf 'regenerated\n' > "$P/$SNAP_DIR/PRODUCT_MANIFESTO.md"
b5_cpg="$(run_pred "$H_CPG" "$P" docs/test-results)"
b5_p3="$(run_pred "$H_P3" "$P" docs/test-results)"
if [ "$b5_cpg" = no ] && [ "$b5_p3" = no ]; then
  pass "B5: a COMMITTED snapshot that the gate then rewrites is excluded too ('$b5_cpg'/'$b5_p3') — the fix is a pathspec, so it covers the second-run-same-day shape as well as the first-ever-run shape"
else
  fail_ "B5" "cpg='$b5_cpg' p3='$b5_p3', both want 'no'"
fi

# ── B6: not a git repository -> conservative 'yes' ──────────────────────────
P="$TD/not-a-repo"; mkdir -p "$P/docs/test-results"
b6_cpg="$(run_pred "$H_CPG" "$P" docs/test-results)"
b6_p3="$(run_pred "$H_P3" "$P" docs/test-results)"
if [ "$b6_cpg" = yes ] && [ "$b6_p3" = yes ]; then
  pass "B6: outside a git work tree both predicates still answer 'yes' ('$b6_cpg'/'$b6_p3') — the conservative direction, unchanged by this fix"
else
  fail_ "B6" "cpg='$b6_cpg' p3='$b6_p3', both want 'yes'"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== M — mutation proofs (each mutant is BUILT and RUN here) ==="
# ════════════════════════════════════════════════════════════════════════════

_mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || echo "?"; }

_sed_inplace() {
  local file="$1" expr="$2" tmp mode
  mode="$(stat -c '%a' "$file" 2>/dev/null || stat -f '%Lp' "$file" 2>/dev/null || echo "")"
  tmp="$(mktemp)"
  sed -e "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
  [ -n "$mode" ] && chmod "$mode" "$file" 2>/dev/null
  return 0
}

# _mutate <name> <source-file> <fn> <anchor> <sed-expr> <results-dir-arg>
#   Copy the product file, strip the new pathspec from ONE call site, re-lift
#   the function, and re-run B2's and B3's fixtures against the mutant. The
#   report is printed either way: a mutation that changed nothing is a green row
#   that proved nothing.
_mutate() {
  local name="$1" src="$2" fn="$3" anchor="$4" expr="$5" rdarg="$6"
  local copy="$TD/$name.sh" harness="$TD/$name-h.sh" sites lines mode_b mode_a got_dirt got_real
  cp "$src" "$copy"
  mode_b="$(_mode_of "$copy")"
  sites="$(grep -c "$anchor" "$src" || true)"
  case "$sites" in ''|*[!0-9]*) sites=0 ;; esac
  _sed_inplace "$copy" "$expr"
  mode_a="$(_mode_of "$copy")"
  lines="$(diff "$src" "$copy" | grep -c '^[<>]' || true)"
  case "$lines" in ''|*[!0-9]*) lines=0 ;; esac
  local rep="anchor sites=$sites, diff-lines=$lines, mode $mode_b -> $mode_a"
  if [ "$sites" -ne 1 ] || [ "$lines" -ne 2 ] || [ "$mode_b" != "$mode_a" ]; then
    fail_ "$name (harness)" "the mutation is not anchored/single-line/mode-preserving: $rep"
    return 0
  fi
  _harness "$copy" "$fn" "$harness" || return 0
  got_dirt="$(run_pred "$harness" "$TD/snapshot-dirt" "$rdarg")"
  got_real="$(run_pred "$harness" "$TD/real-dirt" "$rdarg")"
  if [ "$got_dirt" = yes ] && [ "$got_real" = yes ]; then
    pass "$name: with the snapshot pathspec removed from that one call site, the gate's own snapshot dirt stales again ('$got_dirt') while real dirt is unchanged ('$got_real') — B2 sees it and B3 does not, which is what shows the mutant broke the FIX and not the predicate. $rep"
  else
    fail_ "$name" "snapshot-only dirt -> '$got_dirt' (want yes, i.e. B2 goes RED) and real dirt -> '$got_real' (want yes). $rep"
  fi
}

# The two call sites inside each function are distinguishable by what follows
# the new pathspec: the bare arm ends it with `2>`, the results-dir arm follows
# it with the `$rdir` exclusion.
_mutate m1-cpg-results "$GATE"   _cpg_scoped_dirty \
  "':(exclude)docs/snapshots' \":(exclude)" \
  "s|':(exclude)docs/snapshots' \":(exclude)\$rdir\"|\":(exclude)\$rdir\"|" \
  docs/test-results
_mutate m2-cpg-bare "$GATE"   _cpg_scoped_dirty \
  "':(exclude)docs/snapshots' 2>" \
  "s|':(exclude).claude' ':(exclude)docs/snapshots' 2>|':(exclude).claude' 2>|" \
  ""
_mutate m3-p3-results "$DRIVER" _p3_scoped_dirty \
  "':(exclude)docs/snapshots' \":(exclude)" \
  "s|':(exclude)docs/snapshots' \":(exclude)\$rdir\"|\":(exclude)\$rdir\"|" \
  docs/test-results
_mutate m4-p3-bare "$DRIVER" _p3_scoped_dirty \
  "':(exclude)docs/snapshots' 2>" \
  "s|':(exclude).claude' ':(exclude)docs/snapshots' 2>|':(exclude).claude' 2>|" \
  ""

rm -rf "$TD"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
