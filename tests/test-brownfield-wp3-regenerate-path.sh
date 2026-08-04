#!/usr/bin/env bash
# tests/test-brownfield-wp3-regenerate-path.sh
#
# Brownfield adoption WP3 — THE REGENERATE-PATH PROOF. Design
# docs/designs/2026-08-02-brownfield-adoption-v1.md §10-WP3 and §12-12.
#
# ── WHY THIS SUITE EXISTS, AND WHY IT IS AIMED WHERE IT IS ──────────────────
# The design's v1.0 regression proof for WP3 was "run fix_phase_state(), assert
# the adoption stamp survives". It was REFUTED as trivially green and
# worthless: that function never touches .claude/manifest.json, so it could not
# have failed. v1.1 (R-BF-1) re-aimed it at the path that actually erases the
# stamp:
#
#   .claude/manifest.json goes missing
#     -> verify-install.sh registers fix_framework_manifest as the repair
#     -> fix_framework_manifest delegates to the UPSTREAM framework installer
#     -> that installer rewrites the manifest WHOLESALE from a hardcoded key
#        set carrying no Solo keys at all
#     -> the adoption stamp and the `adopted` flag are gone.
#
# THE LOSS CANNOT BE PREVENTED. The writer lives in a different repository and
# is outside this design's control. So the deliverable is not prevention — it
# is that the loss is DETECTED AND REPORTED LOUDLY, and that removing the
# detection makes a project SILENTLY UN-ADOPT. That is the honest shape: the
# design cannot stop the erasure, so it must refuse to be quiet about it.
#
# ── Verdicts are EXIT CODES ────────────────────────────────────────────────
# check-phase-gate.sh's [WARN]/[FAIL] labels are cosmetic — the exit predicate
# is `if [ $issues -eq 0 ]`, so an exemption is the ABSENCE of an increment.
# Every verdict below is an exit code; printed text is only ever a path
# discriminator.
#
# ── Scenarios ──────────────────────────────────────────────────────────────
#   R1  WIRING PIN. The repair really is reachable from the repair tool, and it
#       really is MISSING-FILE-GATED — §12-12's narrow, load-bearing
#       assumption. Registration and delegation each pinned at sites==1.
#   R2  THE UPSTREAM WRITER, MEASURED. The REAL fix_framework_manifest,
#       extracted from the shipped script, is executed against a fixture whose
#       committed manifest carried a real adoption stamp. Assert the manifest
#       comes back, comes back from the upstream key set, and comes back
#       carrying NONE of this framework's keys. R2 is the NON-VACUITY GATE for
#       R3/R4: if the regeneration did not happen, a missing manifest would
#       make the detector fire for the wrong reason and R3 would pass having
#       proved nothing.
#   R3  DETECTION. On that REAL regenerated manifest the gate exits NON-ZERO
#       and names the loss.
#   R4  MUTATION. Remove the detection (one line) and the same fixture exits 0
#       — the project silently un-adopts.
#
# ── Why this is a separate suite from test-brownfield-wp3-adoption-arms.sh ──
# It EXECUTES the upstream installer, so it is legitimately unit-lane exempt
# and belongs to the aggregator only. Everything provable without the installer
# lives in the sibling suite and stays in the fast lane. It also SKIPS cleanly
# (exit 0) when the upstream clone is absent, so a runner without it is not a
# false red.
#
# HERMETICITY: fixtures are temp dirs; the installer writes only inside them;
# no network and no remote creation (it copies from the existing local clone).
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/adoption-stamp.sh"
GATE="$REPO_ROOT/scripts/check-phase-gate.sh"
VERIFY="$REPO_ROOT/scripts/verify-install.sh"
CDF_CLONE="${SOIF_CDF_CLONE:-$HOME/.claude-dev-framework}"

PASSED=0
FAILED=0
SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1"; SKIPPED=$((SKIPPED + 1)); }

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

if [ ! -f "$LIB" ]; then
  echo "  [FAIL] setup — $LIB not found (WP3 library missing)"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi
# shellcheck source=/dev/null
. "$LIB"

echo "=== R1 — the repair is wired, and it is missing-file-gated (§12-12) ==="

REG_ANCHOR='register_fixable "Development Guardrails manifest missing" "fix_framework_manifest"'
# The allow marker is the sanctioned escape and the reason is load-bearing, so
# state it precisely rather than string-splitting the token to duck the lint
# (that trick is the very hole CLAUDE.md records against the unit-lane
# predicate). This line is a GREP ANCHOR, not an execution. The suite DOES run
# the upstream installer later, via the extracted repair function — and that
# installer has NO host-API or remote-creation path at all: measured, it
# contains no `gh`, no `glab`, no `curl`, and no `git remote add`. Its single
# `git push` sits in the profile-detector's "type 'new' to create a profile"
# branch, which is unreachable here twice over: the fixture carries a
# detectable profile signal so the no-signal branch never opens, and the suite
# feeds "y" rather than "new".
DEL_ANCHOR='bash "$FRAMEWORK_CLONE/scripts/init.sh"'   # lint-no-live-remote: allow grep anchor, not a run; the upstream installer it names has no host-API or remote-creation path (no gh/glab/curl/git remote add)
r1_reg=$(grep -cF -- "$REG_ANCHOR" "$VERIFY" 2>/dev/null); r1_reg=$(_num "$r1_reg")
r1_del=$(grep -cF -- "$DEL_ANCHOR" "$VERIFY" 2>/dev/null); r1_del=$(_num "$r1_del")
r1_fn=$(grep -c '^fix_framework_manifest() {$' "$VERIFY" 2>/dev/null); r1_fn=$(_num "$r1_fn")
# Missing-file-gated: the registration must sit in the ELSE arm of a bare
# `[ -f ".claude/manifest.json" ]` test. §12-12's real assumption is exactly
# this — that the upstream writer is only ever reached when the file is already
# gone, so it never DESTROYS a stamp that was present. If this gate ever
# disappears, every adopted project un-adopts on the next repair run.
r1_gated=0
grep -B 3 -F -- "$REG_ANCHOR" "$VERIFY" 2>/dev/null \
  | grep -q 'if \[ -f "\.claude/manifest\.json" \]; then' && r1_gated=1
if [ "$r1_reg" -eq 1 ] && [ "$r1_del" -eq 1 ] && [ "$r1_fn" -eq 1 ] && [ "$r1_gated" -eq 1 ]; then
  pass "R1: the missing-manifest repair is registered exactly once, delegates to the upstream installer exactly once, and is MISSING-FILE-GATED — it can never destroy a stamp that is present"
else
  fail_ "R1" "registration_sites=$r1_reg (want 1) delegation_sites=$r1_del (want 1) function_sites=$r1_fn (want 1) missing_file_gated=$r1_gated (want 1)"
fi

# ── Extract the REAL repair function ────────────────────────────────────────
# The whole repair tool is NOT run: under --auto-fix its other registered fixes
# include package-manager installs, which is a real side effect on whoever runs
# the suite and is not something a hermetic test may trigger. So the ONE
# function under test is lifted verbatim from the shipped script and executed
# for real, with R1 above pinning that it is genuinely the function the tool
# dispatches for a missing manifest.
FIXSRC="$TOPTMP/fix_framework_manifest.sh"
awk '/^fix_framework_manifest\(\) \{$/{f=1} f{print} f&&/^\}$/{exit}' "$VERIFY" > "$FIXSRC"
r_extract_ok=0
if [ -s "$FIXSRC" ] && grep -qF -- "$DEL_ANCHOR" "$FIXSRC" && bash -n "$FIXSRC" 2>/dev/null; then
  r_extract_ok=1
fi

echo ""
echo "=== R2 — the upstream writer, measured against a real adoption stamp ==="

CDF_OK=1
[ -d "$CDF_CLONE/.git" ] || CDF_OK=0
[ -f "$CDF_CLONE/scripts/init.sh" ] || CDF_OK=0

# mk_adopted_project DIR — a committed, genuinely adopted project the upstream
# installer will accept: a git repo with a profile signal it can detect.
mk_adopted_project() {
  local d="$1"
  mkdir -p "$d/.claude" "$d/scripts/lib"
  ( cd "$d" \
      && git init -q \
      && git config user.email "wp3r@test.invalid" \
      && git config user.name  "WP3 Regen Test" ) || return 1
  printf '%s\n' '{"current_phase":0,"track":"light","deployment":"personal","poc_mode":null,"gates":{}}' > "$d/.claude/phase-state.json"
  printf '%s\n' '# Approval Log' > "$d/APPROVAL_LOG.md"
  printf '%s\n' '{"name":"fixture","dependencies":{"express":"^4"}}' > "$d/package.json"
  printf '%s\n' '{"frameworkVersion":"test","host":"other","mode":"personal","deployment":"personal"}' > "$d/.claude/manifest.json"
  cp "$GATE" "$d/scripts/"
  cp "$REPO_ROOT/scripts/lib/helpers.sh" \
     "$REPO_ROOT/scripts/lib/helpers-core.sh" \
     "$REPO_ROOT/scripts/lib/helpers-full.sh" \
     "$LIB" "$d/scripts/lib/"
  chmod +x "$d/scripts/check-phase-gate.sh"
  ( cd "$d" && soif_adoption_stamp ".claude/manifest.json" "completed" 0 '[]' '[]' '["tdd-ordering"]' '[]' "reportsha" ) || return 1
  ( cd "$d" && git add -A && git commit -q -m "chore: adopt project" ) || return 1
}

run_gate() { ( cd "$1" && bash scripts/check-phase-gate.sh 2>&1 ); }

R2D=""
R2_READY=0
if [ "$CDF_OK" -eq 0 ]; then
  skip "R2 — upstream framework clone not found at $CDF_CLONE (set SOIF_CDF_CLONE to override); the regenerate path cannot be exercised"
elif [ "$r_extract_ok" -eq 0 ]; then
  fail_ "R2" "could not extract a runnable fix_framework_manifest from $VERIFY"
else
  R2D="$(newtmp)/p"
  if ! mk_adopted_project "$R2D"; then
    fail_ "R2" "fixture setup failed"
  else
    # NON-VACUITY, asserted before anything else: the fixture really is adopted
    # and the stamp really is committed, so the witness R3 depends on exists.
    pre_adopted=0
    soif_adoption_adopted "$R2D/.claude/manifest.json" && pre_adopted=1
    pre_witness=0
    ( cd "$R2D" && git show "HEAD:.claude/manifest.json" | jq -e '.adoption.adopted == true' ) >/dev/null 2>&1 && pre_witness=1

    rm -f "$R2D/.claude/manifest.json"
    regen_rc=0
    ( cd "$R2D" && . "$FIXSRC" && printf 'y\n' | fix_framework_manifest ) >"$TOPTMP/regen.log" 2>&1 || regen_rc=$?

    regen_exists=0
    [ -f "$R2D/.claude/manifest.json" ] && regen_exists=1
    regen_upstream=0
    jq -e '.frameworkRepo and .profile and .activeHooks' "$R2D/.claude/manifest.json" >/dev/null 2>&1 && regen_upstream=1
    # The measurement the design rests on: the upstream key set carries NONE of
    # this framework's keys.
    solo_keys_left=0
    jq -e '.adoption' "$R2D/.claude/manifest.json" >/dev/null 2>&1 && solo_keys_left=$((solo_keys_left + 1))
    jq -e '.host'     "$R2D/.claude/manifest.json" >/dev/null 2>&1 && solo_keys_left=$((solo_keys_left + 1))
    jq -e '.deployment' "$R2D/.claude/manifest.json" >/dev/null 2>&1 && solo_keys_left=$((solo_keys_left + 1))

    if [ "$pre_adopted" -eq 1 ] && [ "$pre_witness" -eq 1 ] && [ "$regen_exists" -eq 1 ] \
       && [ "$regen_upstream" -eq 1 ] && [ "$solo_keys_left" -eq 0 ]; then
      R2_READY=1
      pass "R2: the REAL repair function regenerated the manifest from the upstream key set, and every one of this framework's keys — adoption, host, deployment — is GONE. The stamp's loss is real, upstream, and unpreventable from here"
    else
      fail_ "R2" "pre_adopted=$pre_adopted (want 1) committed_witness=$pre_witness (want 1) regen_rc=$regen_rc manifest_regenerated=$regen_exists (want 1) is_upstream_keyset=$regen_upstream (want 1) solo_keys_surviving=$solo_keys_left (want 0) — see $TOPTMP/regen.log"
    fi
  fi
fi

echo ""
echo "=== R3 — the loss is DETECTED and REPORTED LOUDLY ==="

if [ "$R2_READY" -eq 0 ]; then
  skip "R3 — no real regenerated manifest to judge (R2 skipped or failed); asserting on a fixture that was never regenerated would prove nothing"
else
  r3_out=$(run_gate "$R2D"); r3_rc=$?
  r3_named=0
  printf '%s' "$r3_out" | grep -q 'Adoption stamp LOST' && r3_named=1
  r3_repair=0
  printf '%s' "$r3_out" | grep -q 'REPAIR' && r3_repair=1
  if [ "$r3_rc" -ne 0 ] && [ "$r3_named" -eq 1 ] && [ "$r3_repair" -eq 1 ]; then
    pass "R3: after the REAL upstream regeneration the gate exits NON-ZERO (rc $r3_rc), names the lost stamp and prints a concrete repair — detected and loud, not prevented"
  else
    fail_ "R3" "rc=$r3_rc (want non-zero) loss_named=$r3_named (want 1) repair_printed=$r3_repair (want 1)"
  fi
fi

echo ""
echo "=== R4 — MUTATION: remove the detection, the project silently un-adopts ==="

if [ "$R2_READY" -eq 0 ]; then
  skip "R4 — no real regenerated manifest to mutate against (R2 skipped or failed)"
else
  MUT="$R2D/scripts/lib/adoption-stamp.sh"
  det_sites=$(grep -c 'BF-ADOPT-LOSS-DETECT$' "$LIB" 2>/dev/null); det_sites=$(_num "$det_sites")
  REF="$TOPTMP/orig-lib.ref"
  cp "$LIB" "$REF"
  _sed_inplace "$MUT" 's|^.*BF-ADOPT-LOSS-DETECT$|  return 1   # BF-ADOPT-LOSS-DETECT|'
  chg=$(_changed_lines "$REF" "$MUT")
  p=$(_parses "$MUT")
  r4_out=$(run_gate "$R2D"); r4_rc=$?
  # Structural discriminators. The expected mutant result is an ABSENCE, and
  # several unrelated edits share that silence: a gate that died early is also
  # silent, and so is a library that failed to load. Both are excluded here.
  d_ran=0
  printf '%s' "$r4_out" | grep -q 'Phase gates consistent' && d_ran=1
  d_load=0
  ( . "$MUT" && ! soif_adoption_adopted "$R2D/.claude/manifest.json" ) >/dev/null 2>&1 && d_load=1
  d_quiet=1
  printf '%s' "$r4_out" | grep -q 'Adoption stamp LOST' && d_quiet=0
  if [ "$r4_rc" -eq 0 ] && [ "$chg" -eq 2 ] && [ "$det_sites" -eq 1 ] && [ "$p" -eq 1 ] \
     && [ "$d_ran" -eq 1 ] && [ "$d_load" -eq 1 ] && [ "$d_quiet" -eq 1 ]; then
    pass "R4 (mutation): with the post-regeneration detection removed (1 line, mutant parses and still loads), the SAME really-regenerated project passes the gate (rc 0) in silence — it has silently un-adopted, and every gate arm now reads the flag as false. R3 is the control"
  else
    fail_ "R4" "rc=$r4_rc (want 0) changed_lines=$chg (want 2) detect_anchor_sites=$det_sites (want 1) mutant_parses=$p (want 1) gate_ran_to_verdict=$d_ran (want 1) mutant_lib_loads=$d_load (want 1) report_suppressed=$d_quiet (want 1)"
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
