#!/usr/bin/env bash
# tests/test-bl124-pending-ratchet.sh — BL-124: a PENDING promotion marker must
# BLOCK the Phase 3→4 gate.
#
# WHY THIS EXISTS (Dogfood-2 finding F-DF2-014, High — the central question)
#   upgrade-project.sh rewrites the Light-track "SKIPPED" markers on
#   PRODUCT_MANIFESTO.md Appendix A (Revenue Model) and Appendix C (Trademark
#   & Legal) to "PENDING — required by track upgrade light → full on <date>".
#   NOTHING then read that marker: a project reached a tagged production
#   release with the re-demanded obligations still literally saying PENDING.
#   The framework visibly performed the re-demand and enforced none of it —
#   which reads to an auditor as a working ratchet.
#
#   The fix (# BL-124-PENDING-RATCHET in check-phase-gate.sh) FAILs the Phase
#   3→4 gate while the manifesto carries the writer's marker. Keyed on the
#   MARKER, not on track: track is spoofable (BL-084), and Light-track
#   projects carry SKIPPED — never PENDING — so they are naturally unaffected.
#
# CASES
#   T-writer-reader-wired     the gate's grep pattern and upgrade-project.sh's
#                             writer string are THE SAME literal — the tool
#                             that writes PENDING and the gate that reads it
#                             cannot drift apart silently.
#   T-pending-blocks          fixture manifesto with a writer-shaped PENDING
#                             line → `--gate phase_3_to_4` exits non-zero AND
#                             emits the BL-124 [FAIL] naming the marker.
#   T-skipped-not-blocked     the same fixture with Light-track SKIPPED text →
#                             the BL-124 arm stays silent.
#   T-filled-not-blocked      appendix filled in (no marker) → arm silent.
#   T-mutation-bl124          delete the marked check from a COPY of the gate →
#                             the PENDING fixture no longer trips it (proves
#                             the marked line is load-bearing).
#
# REGISTRATION: no init.sh, not an aggregator → BOTH
# tests/full-project-test-suite.sh AND the tests.yml unit lane.
# Fixture shape adapted from tests/test-bl104-gate-scoring.sh (the known-good
# drivable check-phase-gate project). Hermetic: mktemp, no git, no network.
# bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-phase-gate.sh"
UPGRADE="$REPO_ROOT/scripts/upgrade-project.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# The wired marker prefix. The writer (upgrade-project.sh) emits
# "PENDING — required by track upgrade {old} → {new} on {date}"; the gate
# greps this prefix. Both sides are asserted against this one constant below.
MARKER='PENDING — required by track upgrade'

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# ── T-writer-reader-wired ────────────────────────────────────────────────────
echo "=== T-writer-reader-wired ==="
if ! grep -qF "$MARKER" "$UPGRADE"; then
  fail_ "T-writer-reader-wired" "upgrade-project.sh no longer writes the literal '$MARKER' — the writer moved; move the gate's reader (and this test) IN SYNC"
elif ! grep -qF "$MARKER" "$SCRIPT"; then
  fail_ "T-writer-reader-wired" "check-phase-gate.sh does not read the literal '$MARKER' — the gate cannot see what upgrade-project.sh writes (BL-124: the ratchet asks but does not check)"
else
  pass "T-writer-reader-wired"
fi

# ── Fixture (adapted from test-bl104-gate-scoring.sh's known-good project) ───
# appendix_kind: pending | skipped | filled
build_project() {
  local appendix_kind="$1"
  PROJ="$TOPTMP/p-$appendix_kind"
  rm -rf "$PROJ"
  mkdir -p "$PROJ/.claude" "$PROJ/docs/test-results" "$PROJ/docs/eval-results"

  cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{
  "project": "bl124",
  "current_phase": 3,
  "track": "full",
  "deployment": "personal",
  "gates": {
    "phase_0_to_1": "2026-02-01",
    "phase_1_to_2": "2026-03-01",
    "phase_2_to_3": "2026-04-01",
    "phase_3_to_4": null
  }
}
JSON
  cat > "$PROJ/.claude/process-state.json" <<'JSON'
{
  "phase1_artifacts": { "data_classification": "public" },
  "phase2_init": { "attestations": { "branch_protection": { "reason": "github_free_tier" } } },
  "phase3_validation": { "steps_completed": [] }
}
JSON
  cat > "$PROJ/.claude/manifest.json" <<'JSON'
{ "host": "github", "mode": "personal" }
JSON
  cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# Approval Log

## Phase Gate: Phase 0 → Phase 1
| Field | Value |
|---|---|
| Approver | Alice Signer |
| Date | 2026-02-01 |

## Phase Gate: Phase 1 → Phase 2
| Field | Value |
|---|---|
| Approver | Alice Signer |
| Date | 2026-03-01 |

## Phase Gate: Phase 2 → Phase 3
| Field | Value |
|---|---|
| Approver | Alice Signer |
| Date | 2026-04-01 |
MD

  local appendix_a
  case "$appendix_kind" in
    pending) appendix_a="**Revenue Model & Unit Economics:** ${MARKER} light → full on 2026-07-15" ;;
    skipped) appendix_a="**Revenue Model & Unit Economics:** SKIPPED — Light track (internal tool)" ;;
    filled)  appendix_a="**Revenue Model & Unit Economics:** subscription, 3 tiers; unit costs documented below." ;;
  esac
  {
    local n
    for n in 1 2 3 4 5 6 7 8; do
      echo "## ${n}. Section ${n}"
      echo "Substantive content for section ${n} that is not a template placeholder."
      echo ""
    done
    echo "## Appendix A: Revenue Model"
    echo "$appendix_a"
    echo ""
    echo "## Appendix C: Trademark & Legal"
    echo "Cleared 2026-03-02 (no conflicts found)."
  } > "$PROJ/PRODUCT_MANIFESTO.md"

  printf '# Features\n\n## Feature One\nImplemented.\n' > "$PROJ/FEATURES.md"
  {
    echo "# Project Bible"
    local b
    for b in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
      echo "## ${b}. Section ${b}"
      echo "Content for bible section ${b}."
      echo ""
    done
  } > "$PROJ/PROJECT_BIBLE.md"
  echo "# Changelog" > "$PROJ/CHANGELOG.md"
  printf '# Bugs\n\nNo open bugs.\n' > "$PROJ/BUGS.md"
}

run_gate() { ( cd "$PROJ" && bash "${1:-$SCRIPT}" --gate phase_3_to_4 2>&1 ); }

# ── T-pending-blocks ─────────────────────────────────────────────────────────
echo "=== T-pending-blocks ==="
build_project pending
out=$(run_gate); rc=$?
if [ "$rc" -eq 0 ]; then
  fail_ "T-pending-blocks" "gate exited 0 with a PENDING promotion marker in the manifesto (the ratchet asks but does not check)"
elif ! echo "$out" | grep -q "BL-124"; then
  fail_ "T-pending-blocks" "gate blocked (rc=$rc) but without the BL-124 arm's diagnostic — blocked by something else, the PENDING check is absent: $(echo "$out" | grep -E '\[FAIL\]' | head -2 | tr '\n' ' ')"
else
  pass "T-pending-blocks"
fi

# ── T-skipped-not-blocked ────────────────────────────────────────────────────
echo "=== T-skipped-not-blocked ==="
build_project skipped
out=$(run_gate); rc=$?
if echo "$out" | grep -q "BL-124: PRODUCT_MANIFESTO.md still carries"; then
  fail_ "T-skipped-not-blocked" "Light-track SKIPPED text tripped the PENDING arm — the marker key must not match SKIPPED"
else
  pass "T-skipped-not-blocked"
fi

# ── T-filled-not-blocked ─────────────────────────────────────────────────────
echo "=== T-filled-not-blocked ==="
build_project filled
out=$(run_gate); rc=$?
if echo "$out" | grep -q "BL-124: PRODUCT_MANIFESTO.md still carries"; then
  fail_ "T-filled-not-blocked" "a filled appendix tripped the PENDING arm"
else
  pass "T-filled-not-blocked"
fi

# ── T-mutation-bl124 ─────────────────────────────────────────────────────────
# bl104-style: copy the gate, excise the marked check, prove the PENDING
# fixture then sails through the arm — the marked line is load-bearing.
echo "=== T-mutation-bl124 ==="
MUTDIR="$TOPTMP/mut"
mkdir -p "$MUTDIR/scripts/lib"
# The gate sources scripts/lib/*.sh relative to its OWN path — without the
# libs beside the mutant it dies on startup and the crash's silence would
# masquerade as "arm removed" (vacuous pass). Same trap bl104's harness
# documents.
cp "$REPO_ROOT"/scripts/lib/*.sh "$MUTDIR/scripts/lib/" 2>/dev/null || true
if ! grep -q "# BL-124-PENDING-RATCHET" "$SCRIPT"; then
  fail_ "T-mutation-bl124" "no '# BL-124-PENDING-RATCHET' marker in check-phase-gate.sh — nothing to mutate (fix not in place)"
else
  sed '/# BL-124-PENDING-RATCHET-BEGIN/,/# BL-124-PENDING-RATCHET-END/d' "$SCRIPT" > "$MUTDIR/scripts/check-phase-gate.sh"
  chmod +x "$MUTDIR/scripts/check-phase-gate.sh"
  if ! bash -n "$MUTDIR/scripts/check-phase-gate.sh" 2>/dev/null; then
    fail_ "T-mutation-bl124" "excising the BEGIN..END region broke the script's syntax — keep the arm inside its own marker fence"
  else
    build_project pending
    out=$(run_gate "$MUTDIR/scripts/check-phase-gate.sh"); rc=$?
    if echo "$out" | grep -q "BL-124: PRODUCT_MANIFESTO.md still carries"; then
      fail_ "T-mutation-bl124" "BL-124 diagnostic still emitted with the arm excised — the mutation did not remove what the test thinks it removed"
    else
      pass "T-mutation-bl124"
    fi
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
