#!/usr/bin/env bash
# tests/test-bl102-market-signal-warn.sh — BL-102: the Market Signal DECISION
# GATE gets a home (Appendix D) and a WARN-first Phase 1→2 check.
#
# WHY THIS EXISTS (Dogfood-2 central-question evidence + BL-102's four proofs)
#   builders-guide Step 1.1.5 declares "at least one documented market signal
#   before committing to architecture" (Required on Standard/Full, DECISION
#   GATE on no-signal) — and no script enforced it, the appendix it names was
#   never shipped, and the framework's own eval predicted the skip. The fix
#   ships PRODUCT_MANIFESTO Appendix D (Market Signal & Go/No-Go Evidence) in
#   the template and adds a WARN-FIRST arm to check-phase-gate.sh
#   (# BL-102-MARKET-SIGNAL): on track != light, a missing or placeholder
#   Appendix D WARNs — it does NOT increment `issues` (gate-credibility
#   discipline per BL-073's grandfather clause: never hard-block on a slot
#   existing projects don't have; escalate later). The [WARN] trap (BL-104)
#   makes that increment the ACTUAL verdict — so this suite pins the
#   NON-blocking property by exit-code parity, not by trusting the label.
#
# CASES
#   T-template-ships-appendix-d   the generated manifesto template carries the
#                                 Appendix D section + the evidence-tag grammar.
#   T-standard-missing-warns      standard track, no Appendix D → the BL-102
#                                 WARN is emitted.
#   T-warn-does-not-block         exit-code PARITY: the same fixture with and
#                                 without Appendix D exits IDENTICALLY — the
#                                 WARN adds no `issues` increment. (The label
#                                 says WARN; this proves the increment agrees.)
#   T-light-track-silent          light track, no Appendix D → arm silent.
#   T-placeholder-warns           Appendix D present but still template
#                                 placeholder text → WARN (existence is not
#                                 evidence — the hollow-gate class).
#   T-filled-ok                   filled Appendix D → the arm's [OK] receipt.
#   T-mutation-bl102-blocking     the INVERSE trap: add an `issues` increment
#                                 to a COPY's WARN arm → the parity case goes
#                                 RED (proves the parity pin bites); excise the
#                                 arm → the WARN case goes RED.
#
# REGISTRATION: no init.sh, not an aggregator → BOTH lists.
# Fixture adapted from tests/test-bl104-gate-scoring.sh. Hermetic. bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-phase-gate.sh"
TEMPLATE="$REPO_ROOT/templates/generated/product-manifesto.tmpl"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# ── T-template-ships-appendix-d ──────────────────────────────────────────────
echo "=== T-template-ships-appendix-d ==="
if ! grep -q "## Appendix D: Market Signal" "$TEMPLATE"; then
  fail_ "T-template-ships-appendix-d" "product-manifesto.tmpl ships no Appendix D — the gate names a home the scaffold never ships (BL-088 class)"
elif ! grep -q 'seen it' "$TEMPLATE" || ! grep -q 'hunch' "$TEMPLATE"; then
  fail_ "T-template-ships-appendix-d" "Appendix D lacks the evidence-tag grammar (seen it / hunch / guess)"
else
  pass "T-template-ships-appendix-d"
fi

# ── Fixture ──────────────────────────────────────────────────────────────────
# track: standard | light      appendix_d: none | placeholder | filled
build_project() {
  local track="$1" appendix_d="$2"
  PROJ="$TOPTMP/p"
  rm -rf "$PROJ"
  mkdir -p "$PROJ/.claude"

  # The parity pin (T-warn-does-not-block) is only sharp on a fixture whose
  # BASELINE is issues=0 / exit 0: the gate's exit is the binary
  # `[ $issues -eq 0 ]`, so on a fixture with any other failing arm both
  # variants exit 1 and the parity proves nothing. This shape reaches exit 0
  # at --gate phase_1_to_2 (empirically derived; dated 1→2 gate + approval
  # row, ZDR data_classification, branch-protection attestation, 16-section
  # bible).
  cat > "$PROJ/.claude/phase-state.json" <<JSON
{
  "project": "bl102",
  "current_phase": 1,
  "track": "$track",
  "deployment": "personal",
  "gates": {
    "phase_0_to_1": "2026-02-01",
    "phase_1_to_2": "2026-03-01",
    "phase_2_to_3": null,
    "phase_3_to_4": null
  }
}
JSON
  cat > "$PROJ/.claude/process-state.json" <<'JSON'
{
  "phase1_artifacts": { "data_classification": "public" },
  "phase2_init": { "steps_completed": ["remote_repo_created","pushed_initial"], "attestations": { "branch_protection": { "reason": "github_free_tier" } } }
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
MD
  {
    echo "# Project Bible"
    local b
    for b in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
      echo "## ${b}. Section ${b}"
      echo "Content for bible section ${b}."
      echo ""
    done
  } > "$PROJ/PROJECT_BIBLE.md"

  {
    local n
    for n in 1 2 3 4 5 6 7 8; do
      echo "## ${n}. Section ${n}"
      echo "Substantive content for section ${n} that is not a template placeholder."
      echo ""
    done
    case "$appendix_d" in
      none) : ;;
      placeholder)
        echo "## Appendix D: Market Signal & Go/No-Go Evidence"
        echo "| 1 | [e.g. \"solo operators want X\"] | [customer interview / letter of intent] | [URL or artifact path] | [\`seen it\` / \`hunch\` / \`guess\`] | [re-fetched YYYY-MM-DD] |"
        echo "- **Decision:** [GO / NO-GO] — [date]"
        ;;
      filled)
        echo "## Appendix D: Market Signal & Go/No-Go Evidence"
        # The Source cell deliberately uses a markdown LINK LABEL beginning
        # "[customer interview" — a legitimately-filled appendix must NOT trip
        # the placeholder heuristic on it (verifier finding: the pattern must
        # anchor to the template's placeholder syntax "[customer interview /",
        # not to any bracket-prefixed mention).
        echo "| 1 | solo operators want offline readers | customer interview | [customer interview notes](docs/interviews/2026-06-30-reader.md) | seen it | re-fetched 2026-07-01: text-match OK |"
        echo "**Verification counts:** checked: 3 · failed: 0 · dropped: 0"
        echo "- **Decision:** GO — 2026-07-02"
        echo "- **Decided by:** Karl Raulerson"
        echo "- **Rationale:** three independent interviews requested the same core flow."
        ;;
    esac
  } > "$PROJ/PRODUCT_MANIFESTO.md"
}

run_gate() { ( cd "$PROJ" && bash "${1:-$SCRIPT}" --gate phase_1_to_2 2>&1 ); }

# ── T-standard-missing-warns ─────────────────────────────────────────────────
echo "=== T-standard-missing-warns ==="
build_project standard none
out=$(run_gate); rc_none=$?
if echo "$out" | grep -q "BL-102"; then
  pass "T-standard-missing-warns"
else
  fail_ "T-standard-missing-warns" "standard track with no Appendix D emitted no BL-102 warn — Step 1.1.5 is still enforced by nothing"
fi

# ── T-warn-does-not-block ────────────────────────────────────────────────────
echo "=== T-warn-does-not-block ==="
build_project standard filled
out=$(run_gate); rc_filled=$?
if [ "${rc_none:-99}" -eq "${rc_filled:-98}" ]; then
  pass "T-warn-does-not-block (exit $rc_none with and without Appendix D — WARN carries no issues increment)"
else
  fail_ "T-warn-does-not-block" "exit differs with (rc=$rc_filled) vs without (rc=$rc_none) Appendix D — the 'WARN' increments issues, i.e. it BLOCKS (the BL-104 [WARN] trap; BL-102 mandates WARN-first)"
fi

# ── T-light-track-silent ─────────────────────────────────────────────────────
echo "=== T-light-track-silent ==="
build_project light none
out=$(run_gate)
if echo "$out" | grep -q "BL-102"; then
  fail_ "T-light-track-silent" "light track tripped the market-signal arm — Step 1.1.5 is SKIP on Light"
else
  pass "T-light-track-silent"
fi

# ── T-placeholder-warns ──────────────────────────────────────────────────────
echo "=== T-placeholder-warns ==="
build_project standard placeholder
out=$(run_gate)
if echo "$out" | grep -q "BL-102" && echo "$out" | grep -qi "placeholder"; then
  pass "T-placeholder-warns"
else
  fail_ "T-placeholder-warns" "placeholder Appendix D not flagged — existence-only is the hollow-gate class BL-102 exists to end"
fi

# ── T-filled-ok ──────────────────────────────────────────────────────────────
echo "=== T-filled-ok ==="
build_project standard filled
out=$(run_gate)
if echo "$out" | grep -q "BL-102" && echo "$out" | grep -qiE "\[OK\].*(market|Appendix D)"; then
  pass "T-filled-ok"
else
  fail_ "T-filled-ok" "filled Appendix D produced no [OK] receipt (a silent pass is indistinguishable from an absent gate)"
fi

# ── T-mutation-bl102-blocking ────────────────────────────────────────────────
echo "=== T-mutation-bl102-blocking ==="
MUTDIR="$TOPTMP/mut"
mkdir -p "$MUTDIR/scripts/lib"
# The gate sources scripts/lib/*.sh relative to its OWN path — without the
# libs beside the mutant it dies on startup with empty output and exit 1,
# which fakes both mutation directions (bl104's harness documents the trap).
cp "$REPO_ROOT"/scripts/lib/*.sh "$MUTDIR/scripts/lib/" 2>/dev/null || true
if ! grep -q "# BL-102-MARKET-SIGNAL" "$SCRIPT"; then
  fail_ "T-mutation-bl102-blocking" "no '# BL-102-MARKET-SIGNAL' marker in check-phase-gate.sh — fix not in place"
else
  # Direction 1: excise the arm → the WARN disappears.
  sed '/# BL-102-MARKET-SIGNAL-BEGIN/,/# BL-102-MARKET-SIGNAL-END/d' "$SCRIPT" > "$MUTDIR/scripts/check-phase-gate.sh"
  chmod +x "$MUTDIR/scripts/check-phase-gate.sh"
  build_project standard none
  out=$(run_gate "$MUTDIR/scripts/check-phase-gate.sh")
  if echo "$out" | grep -q "BL-102"; then
    fail_ "T-mutation-bl102-blocking" "arm excised but BL-102 output remains — mutation did not remove what the test thinks"
  else
    # Direction 2 (the inverse trap): inject an increment into the WARN arm →
    # exit parity must break, proving the parity pin would catch a future
    # editor who "promotes" the WARN into a block by adding the increment.
    sed '/# BL-102-MARKET-SIGNAL-WARNLINE/a\
    issues=$((issues + 1))' "$SCRIPT" > "$MUTDIR/scripts/check-phase-gate.sh"
    chmod +x "$MUTDIR/scripts/check-phase-gate.sh"
    if ! bash -n "$MUTDIR/scripts/check-phase-gate.sh" 2>/dev/null; then
      fail_ "T-mutation-bl102-blocking" "increment-injection mutant is syntactically broken — keep the WARNLINE marker on its own line"
    else
      build_project standard none
      out=$(run_gate "$MUTDIR/scripts/check-phase-gate.sh"); rc_mut_none=$?
      build_project standard filled
      out=$(run_gate "$MUTDIR/scripts/check-phase-gate.sh"); rc_mut_filled=$?
      if [ "$rc_mut_none" -ne "$rc_mut_filled" ]; then
        pass "T-mutation-bl102-blocking (excise → warn gone; increment-inject → parity breaks: both directions bite)"
      else
        fail_ "T-mutation-bl102-blocking" "injected increment did NOT break exit parity (none=$rc_mut_none filled=$rc_mut_filled) — the parity pin is not actually sensitive to the increment; filled-run verdict lines: $(echo "$out" | grep -E '\[FAIL\]|\[WARN\]|issue' | head -4 | tr '\n' ' | ')"
      fi
    fi
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
