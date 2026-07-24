#!/usr/bin/env bash
# tests/test-bl166-gate-scope.sh
#
# BL-166 + BL-158 (residuals wave, Dogfood-4 S3): scripts/check-phase-gate.sh
# --gate <name> must scope its exit code / summary count to the NAMED gate's
# checks and must label the FORCED phase distinctly.
#
# BL-166 (gate semantics): `--gate phase_2_to_3` forces current_phase=3 so the
# 2→3 gate's checks fire, but the Phase 3→4 readiness blocks are guarded by
# `current_phase -ge 3` — the SAME threshold — so they fired too. A project that
# legitimately clears every 2→3 requirement still exited 1 with "N
# inconsistency(ies) — blocking", every one a not-yet-creatable 3→4 deliverable
# (HANDOFF.md, sbom.json, docs/test-results/, review manifest, …). The fix
# (# BL-166-GATE-SCOPE) confines the count to the named gate: when --gate names a
# gate whose TARGET is below 4, the 3→4 readiness region is announced as ONE
# non-counted [NEXT] line and its block-counting checks do not run.
#
# BL-158 (header label): under a --gate override the header printed
# "Current phase: <forced>" — reading like recorded state on an audit trail even
# when phase-state.json records a different phase. The fix (# BL-158-GATE-LABEL)
# prints "Checking gate: <name> (as-if phase <forced>; recorded current_phase:
# <recorded>)" under --gate, and leaves the bare header unchanged.
#
# Cases:
#   (a) --gate phase_2_to_3 on a project meeting 2→3 with NO 3→4 deliverables
#       → exit 0 (RED against pre-fix code = exit 1).
#   (b) --gate phase_2_to_3 on a project FAILING a real 2→3 requirement
#       (FEATURES.md removed) → still exit 1 (named-gate enforcement intact).
#   (c) --gate phase_0_to_1 while phase-state records current_phase=0 → header
#       shows the distinct "as-if" label and NOT "Current phase: 1" (BL-158).
#   (d) A bare run (no --gate) is byte-unchanged: exit + "Current phase:" header,
#       and NO [NEXT] readiness line.
#   (e) T-mutation: neutering the `skip_later_gate=1` decision line in a copy of
#       the script re-includes the 3→4 checks in the --gate count → (a) flips to
#       exit 1.

set -uo pipefail
unset GITHUB_BASE_REF 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-phase-gate.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP=$(mktemp -d)
cleanup() { rm -rf "$TOPTMP"; }
trap cleanup EXIT

# ── Fixture: a personal project that cleanly clears 0→1, 1→2 and 2→3 but has
#    NONE of the Phase 3→4 deliverables. Empirically clean under the current
#    gate (all remaining inconsistencies are Phase 3→4 readiness items). ──────
build_clean_p3() {
  local d="$1"
  mkdir -p "$d/.claude" "$d/docs/phase-0"

  cat > "$d/.claude/phase-state.json" <<'JSON'
{"current_phase":3,"deployment":"personal","track":"light","poc_mode":null,"gates":{"phase_0_to_1":"2026-01-01","phase_1_to_2":"2026-02-01","phase_2_to_3":"2026-03-01"}}
JSON

  # public data_classification → ZDR gate satisfied without attestation;
  # local_only_acknowledged → BL-084 push gate satisfied without a remote.
  cat > "$d/.claude/process-state.json" <<'JSON'
{"phase1_artifacts":{"data_classification":"public"},"phase2_init":{"remote":{"local_only_acknowledged":{"risk_accepted":true}}}}
JSON

  cat > "$d/APPROVAL_LOG.md" <<'MD'
# APPROVAL_LOG

## Phase Gate: Phase 0 → Phase 1
| Field | Value |
| Approver | Alice |
| Date | 2026-01-01 |

## Phase Gate: Phase 1 → Phase 2
| Field | Value |
| Approver | Alice |
| Date | 2026-02-01 |

## Phase Gate: Phase 2 → Phase 3
| Field | Value |
| Approver | Alice |
| Date | 2026-03-01 |
MD

  cat > "$d/PRODUCT_MANIFESTO.md" <<'MD'
# Product Manifesto

## 1. Vision
We build a widget tracker for small teams.

## 2. Problem
Teams lose track of their widgets across spreadsheets.

## 3. Users
Small team leads who coordinate shared inventory.

## 4. Solution
A simple web application with create, list, and delete.

## 5. Scope
MVP delivers create, list, and delete of widget records.

## 6. Success Metrics
At least ten weekly active users within one month.

## 7. Risks
Adoption risk, mitigated by a guided onboarding flow.

## 8. Timeline
Ship the MVP within six weeks of kickoff.

## Appendix B: Competency Matrix
The founder covers product and engineering competencies.

## Appendix D: Market Signal & Go/No-Go Evidence
Interviewed five leads; a GO decision was recorded early.
MD

  # PROJECT_BIBLE.md — 16 numbered sections, no YYYY-MM-DD placeholders.
  {
    echo "# Project Bible"
    echo ""
    local i=1
    while [ "$i" -le 16 ]; do
      echo "## $i. Section $i"
      echo "Content for section $i describing the relevant decisions."
      echo ""
      i=$((i + 1))
    done
  } > "$d/PROJECT_BIBLE.md"

  cat > "$d/FEATURES.md" <<'MD'
# Features

## Widget CRUD
Create, list, and delete widgets. Implemented and verified.
MD

  cat > "$d/CHANGELOG.md" <<'MD'
# Changelog

## 0.1.0
Initial widget CRUD.
MD

  cat > "$d/BUGS.md" <<'MD'
# Bugs

No open bugs at this time.
MD

  echo "frd"      > "$d/docs/phase-0/frd.md"
  echo "journey"  > "$d/docs/phase-0/user-journey.md"
  echo "contract" > "$d/docs/phase-0/data-contract.md"
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== (a) --gate phase_2_to_3 on a clean-2→3 / no-3→4 project → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# WATCHED-RED: against pre-fix code this exits 1 (the 3→4 readiness checks are
# counted). The fix scopes the count to the named gate → exit 0.
PA="$TOPTMP/a"
build_clean_p3 "$PA"
out_a=$( cd "$PA" && bash "$SCRIPT" --gate phase_2_to_3 2>&1 ); rc_a=$?
if [ "$rc_a" -eq 0 ]; then
  pass "(a) --gate phase_2_to_3 exits 0 when only 3→4 deliverables are missing"
else
  fail_ "(a)" "expected exit 0, got $rc_a. Blocking lines: $(printf '%s' "$out_a" | grep -E '\[FAIL\]|\[WARN\].*Phase 3.4' | head -6 | tr '\n' '|')"
fi
# The 3→4 readiness must be surfaced as a non-counted [NEXT] line.
if printf '%s' "$out_a" | grep -q '\[NEXT\].*Phase 3.4 readiness'; then
  pass "(a) 3→4 readiness announced as a non-counted [NEXT] line"
else
  fail_ "(a-next)" "expected a [NEXT] Phase 3→4 readiness line under scope; out: $(printf '%s' "$out_a" | tail -4 | tr '\n' '|')"
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== (b) --gate phase_2_to_3 with a real 2→3 failure → still exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# Removing FEATURES.md trips the counted Phase 2→3 artifact check. Named-gate
# enforcement must remain intact (the scope narrows later gates, not this one).
PB="$TOPTMP/b"
build_clean_p3 "$PB"
rm -f "$PB/FEATURES.md"
out_b=$( cd "$PB" && bash "$SCRIPT" --gate phase_2_to_3 2>&1 ); rc_b=$?
if [ "$rc_b" -ne 0 ] && printf '%s' "$out_b" | grep -qE "Phase 2.3:.*FEATURES.md"; then
  pass "(b) a real 2→3 failure still blocks under --gate phase_2_to_3 (rc=$rc_b)"
else
  fail_ "(b)" "expected non-zero exit with a Phase 2→3 FEATURES.md diagnostic; rc=$rc_b out: $(printf '%s' "$out_b" | grep -E '\[FAIL\]|\[WARN\]' | head -4 | tr '\n' '|')"
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== (c) --gate phase_0_to_1 header shows the as-if label, not Current phase: 1 ==="
# ════════════════════════════════════════════════════════════════════
# BL-158: phase-state records current_phase=0; --gate forces the 0→1 gate to run
# as-if phase 1. The header must NOT read "Current phase: 1" (which would look
# like recorded state) and must name the recorded value distinctly.
PC="$TOPTMP/c"
mkdir -p "$PC/.claude"
cat > "$PC/.claude/phase-state.json" <<'JSON'
{"current_phase":0,"deployment":"personal"}
JSON
cat > "$PC/APPROVAL_LOG.md" <<'MD'
# APPROVAL_LOG
MD
out_c=$( cd "$PC" && bash "$SCRIPT" --gate phase_0_to_1 2>&1 ) || true
if printf '%s' "$out_c" | grep -qE "Checking gate: phase_0_to_1 .*as-if phase 1.*recorded current_phase: 0"; then
  if printf '%s' "$out_c" | grep -qE "^Current phase: 1$"; then
    fail_ "(c)" "the misleading 'Current phase: 1' header is still printed under --gate"
  else
    pass "(c) header labels the forced phase distinctly and omits 'Current phase: 1'"
  fi
else
  fail_ "(c)" "expected an 'as-if phase 1 / recorded current_phase: 0' header; got: $(printf '%s' "$out_c" | grep -iE 'phase' | head -3 | tr '\n' '|')"
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== (d) bare run (no --gate) is unchanged: exit 1 + Current phase header, no [NEXT] ==="
# ════════════════════════════════════════════════════════════════════
# The same clean-2→3 fixture at recorded phase 3 must behave EXACTLY as before a
# bare run: the 3→4 readiness checks still fire and block (exit 1), the header is
# the plain "Current phase: 3", and no [NEXT] scoping line appears.
PD="$TOPTMP/d"
build_clean_p3 "$PD"
out_d=$( cd "$PD" && bash "$SCRIPT" 2>&1 ); rc_d=$?
d_ok=1
if [ "$rc_d" -ne 1 ]; then
  fail_ "(d-exit)" "bare run should still exit 1 on missing 3→4 deliverables, got $rc_d"; d_ok=0
fi
if ! printf '%s' "$out_d" | grep -qE "^Current phase: 3$"; then
  fail_ "(d-header)" "bare header must be the plain 'Current phase: 3'"; d_ok=0
fi
if printf '%s' "$out_d" | grep -q '\[NEXT\]'; then
  fail_ "(d-next)" "the [NEXT] scoping line must NOT appear on a bare run"; d_ok=0
fi
[ "$d_ok" -eq 1 ] && pass "(d) bare run unchanged (exit 1, plain header, no [NEXT] line)"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== (e) T-mutation: neutering the skip decision re-includes 3→4 in the count ==="
# ════════════════════════════════════════════════════════════════════
# Copy the script + its lib into a sandbox, neuter the `skip_later_gate=1`
# decision line, and re-run case (a): the guard is load-bearing, so the mutant
# must flip (a) from exit 0 to exit 1 (the 3→4 readiness re-enters the count).
MUT="$TOPTMP/mut/scripts"
mkdir -p "$MUT/lib"
cp "$REPO_ROOT/scripts/check-phase-gate.sh" "$MUT/check-phase-gate.sh"
cp "$REPO_ROOT"/scripts/lib/*.sh "$MUT/lib/" 2>/dev/null || true
MUT_SCRIPT="$MUT/check-phase-gate.sh"

# Sanity: the copy itself must pass case (a) (exit 0) — proves the harness valid.
PE="$TOPTMP/e"
build_clean_p3 "$PE"
out_e0=$( cd "$PE" && bash "$MUT_SCRIPT" --gate phase_2_to_3 2>&1 ); rc_e0=$?

# Neuter the decision line: `skip_later_gate=1 ...` → `skip_later_gate=0 ...`.
# GNU-first, BSD fallback.
sed -i 's/skip_later_gate=1   # BL-166-GATE-SCOPE mutation target/skip_later_gate=0   # BL-166-GATE-SCOPE mutation target/' "$MUT_SCRIPT" 2>/dev/null \
  || sed -i '' 's/skip_later_gate=1   # BL-166-GATE-SCOPE mutation target/skip_later_gate=0   # BL-166-GATE-SCOPE mutation target/' "$MUT_SCRIPT"

out_e1=$( cd "$PE" && bash "$MUT_SCRIPT" --gate phase_2_to_3 2>&1 ); rc_e1=$?
if [ "$rc_e0" -eq 0 ] && [ "$rc_e1" -ne 0 ]; then
  pass "(e) mutation flips (a): clean copy exits 0, neutered copy exits $rc_e1 (guard is load-bearing)"
else
  fail_ "(e)" "expected clean-copy exit 0 + mutant non-zero; got clean=$rc_e0 mutant=$rc_e1"
fi

# ════════════════════════════════════════════════════════════════════
echo "=== (f) --gate phase_3_to_4 STILL enforces its own 3→4 items per-item (no skip) ==="
# ════════════════════════════════════════════════════════════════════
# The skip flag is set ONLY when the named gate's target is BELOW 4. Under
# --gate phase_3_to_4 (target 4) the four readiness blocks MUST run per-item —
# process-checklist.sh --start-phase4 consults exactly this invocation as a live
# gate, so a threshold slip (`-lt 4` → `-le 4`) that skipped them would
# authorize Phase 4 with everything unevaluated. Assert on CONTENT, not exit
# code: the 3→4 gate-date WARN keeps exit 1 regardless, so only the per-item
# diagnostic + the absence of a [NEXT] line discriminate.
PF="$TOPTMP/f"
build_clean_p3 "$PF"
out_f=$( cd "$PF" && bash "$SCRIPT" --gate phase_3_to_4 2>&1 )
f_ok=1
if ! printf '%s' "$out_f" | grep -qF 'Phase 3→4: HANDOFF.md not found'; then
  fail_ "(f-peritem)" "under --gate phase_3_to_4 the per-item 3→4 readiness check must run (expected 'Phase 3→4: HANDOFF.md not found'); out: $(printf '%s' "$out_f" | tail -4 | tr '\n' '|')"; f_ok=0
fi
if printf '%s' "$out_f" | grep -qF '[NEXT]'; then
  fail_ "(f-next)" "the [NEXT] skip line must NOT appear under --gate phase_3_to_4 (its own gate)"; f_ok=0
fi
[ "$f_ok" -eq 1 ] && pass "(f) --gate phase_3_to_4 enforces 3→4 per-item, no [NEXT] skip"

# ════════════════════════════════════════════════════════════════════
echo "=== (g) T-mutation: threshold -lt 4 → -le 4 must be caught by (f) ==="
# ════════════════════════════════════════════════════════════════════
# The verifier's surviving mutant: broadening the threshold makes --gate
# phase_3_to_4 ALSO skip its own blocks. Neuter it in a copy and re-run (f)'s
# probe — the per-item diagnostic must vanish (mutant caught).
MUTG="$TOPTMP/mutg/scripts"
mkdir -p "$MUTG/lib"
cp "$REPO_ROOT/scripts/check-phase-gate.sh" "$MUTG/check-phase-gate.sh"
cp "$REPO_ROOT"/scripts/lib/*.sh "$MUTG/lib/" 2>/dev/null || true
sed -i 's/\[ "\$gate_scope_target" -lt 4 \] && skip_later_gate=1/[ "$gate_scope_target" -le 4 ] \&\& skip_later_gate=1/' "$MUTG/check-phase-gate.sh" 2>/dev/null \
  || sed -i '' 's/\[ "\$gate_scope_target" -lt 4 \] && skip_later_gate=1/[ "$gate_scope_target" -le 4 ] \&\& skip_later_gate=1/' "$MUTG/check-phase-gate.sh"
PG="$TOPTMP/g"
build_clean_p3 "$PG"
out_g=$( cd "$PG" && bash "$MUTG/check-phase-gate.sh" --gate phase_3_to_4 2>&1 )
if printf '%s' "$out_g" | grep -qF 'Phase 3→4: HANDOFF.md not found'; then
  fail_ "(g)" "the -le 4 mutant did NOT skip the 3→4 blocks — (f) would not catch a threshold slip"
else
  pass "(g) threshold mutant (-le 4) skips its own 3→4 blocks → caught by (f)'s per-item assertion"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
