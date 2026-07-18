#!/usr/bin/env bash
# tests/test-bl130-attest-fail-guard.sh — BL-130 (Dogfood-2 F-DF2-013):
# `--attest` must REFUSE a scanner whose last REAL verdict is FAIL.
#
# WHY THIS EXISTS
#   An attestation covers a scan that COULD NOT RUN (SKIP) — never one that
#   ran and FAILED. The driver already refuses to HONOR a FAIL-masking
#   attestation (BL-113's no-launder carry), but `--attest` still RECORDED it
#   and printed `[OK] Attested skip … recorded` — inviting the operator to
#   believe the FAIL was cleared, and leaving a misleading "attested" row
#   against a failing scanner. The guard refuses at WRITE time, pointing at
#   BL-113's rule: a FAIL must be fixed or re-run, not attested.
#
# WHAT THIS PROVES
#   T-attest-on-fail-refused   newest summary says `RESULT <s> FAIL` (an OLDER
#                              summary says PASS — newest-wins is part of the
#                              claim) → --attest exits 2, says REFUSED, and
#                              writes NO attestation into the state file.
#   T-attest-skip-still-works  last verdict SKIP (no PASS/FAIL row) → the
#                              legitimate path still records (rc=0, [OK],
#                              state row present with the reason).
#   T-mutation-fence-excision  `sed '/BL-130-ATTEST-FAIL-GUARD-BEGIN/,/END/d'`
#                              on a mutant COPY → the refusal disappears
#                              (attest-on-FAIL succeeds again) → the guard is
#                              load-bearing, not decorative.
#
# REGISTRATION: no init.sh, not an aggregator → BOTH tests/full-project-test-
# suite.sh AND the tests.yml unit list. Hermetic (mktemp, local paths only).
# bash-3.2 safe. run-phase3-validation.sh is self-contained (no scripts/lib
# sourcing — verified 2026-07-17), so a bare copy is a runnable mutant (the
# bl104 vacuous-mutant trap does not apply, and T-mutation asserts a POSITIVE
# outcome — rc=0 + [OK] — so a crashed mutant cannot vacuously pass).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRIVER="$REPO_ROOT/scripts/run-phase3-validation.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq required (the attestation write surface is jq-structured)"
  exit 0
fi

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# mk_fix <dir> <fail|skip> — results dir + empty state; newest summary carries
# the requested verdict for semgrep-full-tree (a registered scanner name).
mk_fix() {
  local d="$1" kind="$2"
  mkdir -p "$d/rd"
  echo '{"phase3":{"attestations":{}}}' > "$d/st.json"
  # Older summary always says PASS — T1 additionally proves newest-wins.
  cat > "$d/rd/summary-2000-01-01T00-00-00Z.md" <<'EOF'
# Phase 3 summary (older)
RESULT semgrep-full-tree PASS
EOF
  case "$kind" in
    fail)
      cat > "$d/rd/summary-2001-01-01T00-00-00Z.md" <<'EOF'
# Phase 3 summary (newest)
RESULT semgrep-full-tree FAIL
EOF
      ;;
    skip)
      cat > "$d/rd/summary-2001-01-01T00-00-00Z.md" <<'EOF'
# Phase 3 summary (newest)
RESULT semgrep-full-tree SKIP
EOF
      # SKIP is not a REAL verdict; wipe the older PASS too so the scanner
      # reads as never-really-run — the canonical attestable state.
      rm -f "$d/rd/summary-2000-01-01T00-00-00Z.md"
      ;;
  esac
}

# run_attest <driver> <fixdir> — attest semgrep-full-tree against the fixture.
run_attest() {
  local drv="$1" d="$2"
  ( cd "$d" && bash "$drv" --attest semgrep-full-tree --reason "tool unavailable in CI" \
      --results-dir rd --state st.json 2>&1 )
}

# ── T1: attest over a REAL FAIL is refused, and nothing is written ───────────
echo "=== T-attest-on-fail-refused ==="
F1="$TOPTMP/f1"; mk_fix "$F1" fail
out=$(run_attest "$DRIVER" "$F1"); rc=$?
wrote=$(jq -r '.phase3.attestations["semgrep-full-tree"] // empty' "$F1/st.json" 2>/dev/null)
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "REFUSED" && [ -z "$wrote" ]; then
  pass "T-attest-on-fail-refused"
else
  fail_ "T-attest-on-fail-refused" "rc=$rc wrote='$wrote' — a scanner whose NEWEST real verdict is FAIL was attested ([OK] on a failing scanner, F-DF2-013): $(printf '%s' "$out" | tail -1)"
fi

# ── T2: the legitimate SKIP-attest path still records ────────────────────────
echo "=== T-attest-skip-still-works ==="
F2="$TOPTMP/f2"; mk_fix "$F2" skip
out=$(run_attest "$DRIVER" "$F2"); rc=$?
wrote=$(jq -r '.phase3.attestations["semgrep-full-tree"].reason // empty' "$F2/st.json" 2>/dev/null)
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "\[OK\]" && [ "$wrote" = "tool unavailable in CI" ]; then
  pass "T-attest-skip-still-works"
else
  fail_ "T-attest-skip-still-works" "rc=$rc reason='$wrote' — the guard broke the LEGITIMATE attest path (a SKIP must stay attestable): $(printf '%s' "$out" | tail -1)"
fi

# ── T3: fence excision resurrects the bug → the guard is load-bearing ────────
echo "=== T-mutation-fence-excision ==="
MUT="$TOPTMP/mutant.sh"
sed '/# BL-130-ATTEST-FAIL-GUARD-BEGIN/,/# BL-130-ATTEST-FAIL-GUARD-END/d' "$DRIVER" > "$MUT"
if grep -q "BL-130-ATTEST-FAIL-GUARD" "$MUT"; then
  fail_ "T-mutation-fence-excision" "the fence excision did not remove the guard — BEGIN/END markers malformed"
else
  F3="$TOPTMP/f3"; mk_fix "$F3" fail
  out=$(run_attest "$MUT" "$F3"); rc=$?
  wrote=$(jq -r '.phase3.attestations["semgrep-full-tree"] // empty' "$F3/st.json" 2>/dev/null)
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "\[OK\]" && [ -n "$wrote" ]; then
    pass "T-mutation-fence-excision (guardless mutant records the FAIL-masking attestation — the fence is what refuses)"
  else
    fail_ "T-mutation-fence-excision" "rc=$rc — the guardless mutant did NOT reproduce the original bug; either the mutant crashed (vacuous) or the refusal lives outside the fence: $(printf '%s' "$out" | tail -1)"
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
