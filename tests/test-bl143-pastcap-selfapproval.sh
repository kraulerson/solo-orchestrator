#!/usr/bin/env bash
# tests/test-bl143-pastcap-selfapproval.sh — BL-143 (Dogfood-3 wave verifier
# C3): the anti-self-approval control must not silently skip when the
# Approver row lies past the capped pre-extraction window.
#
# THE DEFECT
#   validate_approval_fields' permissive pre-extraction is `grep -A 20`
#   capped: when a gate entry's Approver row sits more than 20 lines below
#   the last gate-name mention (filler/annotation rows — BL-138's bounding
#   made the edge reachable), `approver_name` comes back EMPTY and the
#   `[ -n "$approver_name" ]` guard skipped the ENTIRE control with no
#   output — even though the blame walker's own H2-strict scan is UNCAPPED
#   (walks to the next `## ` / `---`) and would locate the row. A crafted
#   or merely verbose APPROVAL_LOG evades self-approval detection.
#
# THE FIX (# BL-143-PASTCAP-RECOVERY): when the pre-extraction yields no
# usable name, locate the Approver row with the walker's own scan and take
# the name from the located line — the control then RUNS (blame and all).
# A log with truly NO Approver row anywhere keeps the pre-BL-138 status
# quo (nothing to verify, silent) — that boundary is pinned, not changed.
#
# REGISTRATION: no init.sh, not an aggregator -> BOTH lists. Hermetic
# (mktemp fixtures, local commits only). bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-phase-gate.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup() {
  TMP=$(mktemp -d)
  PROJ="$TMP/p"
  mkdir -p "$PROJ/.claude"
  ( cd "$PROJ" && git init -q && git config user.email "ambient@example.com" )
}
teardown() { rm -rf "$TMP"; }

write_phase_state_org() {
  cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":1,"deployment":"organizational","gates":{"phase_0_to_1":"2026-02-01"}}
JSON
}

# The PAST-CAP shape: 22 benign filler rows sit between the last gate-name
# mention (the | **Gate** | row) and the Approver row, so every `grep -A 20`
# window ends before the Approver row while the walker's uncapped
# section scan still reaches it. Fillers carry no 'Approver'/'Role' tokens
# and no template placeholders.
write_log_pastcap_approver() {
  local approver_name="$1" i
  {
    echo "# APPROVAL_LOG"
    echo ""
    echo "## Phase Gate: Phase 0 → Phase 1"
    echo "| Field | Value |"
    echo "|---|---|"
    echo "| **Gate** | Phase 0 → Phase 1 |"
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22; do
      echo "| **Note $i** | supporting detail row $i |"
    done
    echo "| **Approver** | $approver_name |"
    echo "| **Date** | 2026-02-01 |"
  } > "$PROJ/APPROVAL_LOG.md"
}

# Within-cap twin (the sibling suite's canonical shape) — parity pin.
write_log_withincap_approver() {
  local approver_name="$1"
  cat > "$PROJ/APPROVAL_LOG.md" <<MD
# APPROVAL_LOG

## Phase Gate: Phase 0 → Phase 1
| Field | Value |
|---|---|
| **Gate** | Phase 0 → Phase 1 |
| **Approver** | $approver_name |
| **Date** | 2026-02-01 |
MD
}

# No Approver row at all — the declared nothing-to-verify boundary.
write_log_no_approver() {
  cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# APPROVAL_LOG

## Phase Gate: Phase 0 → Phase 1
| Field | Value |
|---|---|
| **Gate** | Phase 0 → Phase 1 |
| **Date** | 2026-02-01 |
MD
}

commit_log_as() {
  local name="$1" email="$2"
  ( cd "$PROJ" \
      && git add APPROVAL_LOG.md .claude/phase-state.json 2>/dev/null \
      && GIT_AUTHOR_NAME="$name" GIT_AUTHOR_EMAIL="$email" \
         GIT_COMMITTER_NAME="$name" GIT_COMMITTER_EMAIL="$email" \
         git commit -qm "approval" )
}

run_gate_with_git_user() {  # [script-override]
  local user="$1" script="${2:-$SCRIPT}"
  ( cd "$PROJ" && git config user.name "$user" && bash "$script" 2>&1 ) || true
}

# ── T1 (the filed edge): past-cap SELF-approval must be CAUGHT ───────────────
echo "T1: Approver row at section-line 29 (past every -A 20 window), commit author == approver → FAIL"
setup
write_phase_state_org
write_log_pastcap_approver "Karl Raulerson"
commit_log_as "Karl Raulerson" "karl@example.com"
out=$(run_gate_with_git_user "Karl Raulerson")
if echo "$out" | grep -qE "FAIL.*self-approval"; then
  pass "T1-pastcap-self-approval-caught (the control runs on the walker-located row — no silent skip)"
else
  fail_ "T1-pastcap-self-approval-caught" "a self-approval 29 lines into its own section was SILENTLY SKIPPED (C3): $(echo "$out" | grep -ci 'self-approval') self-approval line(s) in output"
fi
teardown

# ── T2: past-cap DISTINCT approver stays clean (no recovery false positive) ──
echo "T2: past-cap Approver 'Karla' committed by Bob → NO self-approval FAIL"
setup
write_phase_state_org
write_log_pastcap_approver "Karla"
commit_log_as "Bob Approver" "bob@example.com"
out=$(run_gate_with_git_user "Karl")
if echo "$out" | grep -qE "FAIL.*self-approval"; then
  fail_ "T2-pastcap-distinct-clean" "the recovery path invented a self-approval for distinct names: $(echo "$out" | grep -i self-approval | head -2 | tr '\n' ' ')"
else
  pass "T2-pastcap-distinct-clean"
fi
teardown

# ── T3: within-cap behavior byte-parity (the sibling suite's shape) ──────────
echo "T3: within-cap self-approval still FAILs (normal path undisturbed)"
setup
write_phase_state_org
write_log_withincap_approver "Karl Raulerson"
commit_log_as "Karl Raulerson" "karl@example.com"
out=$(run_gate_with_git_user "Karl Raulerson")
if echo "$out" | grep -qE "FAIL.*self-approval"; then
  pass "T3-withincap-unchanged"
else
  fail_ "T3-withincap-unchanged" "the normal within-cap self-approval detection regressed"
fi
teardown

# ── T4: NO Approver row anywhere → the declared silent boundary is PINNED ────
echo "T4: no Approver row at all → no self-approval output (nothing to verify — status quo)"
setup
write_phase_state_org
write_log_no_approver
commit_log_as "Bob Approver" "bob@example.com"
out=$(run_gate_with_git_user "Karl")
if echo "$out" | grep -qi "self-approval"; then
  fail_ "T4-absent-row-status-quo" "the fence changed the truly-absent-row boundary (it must stay with the walker's existing contracts): $(echo "$out" | grep -i self-approval | head -2 | tr '\n' ' ')"
else
  pass "T4-absent-row-status-quo (an entry with no Approver row anywhere stays out of scope, as declared)"
fi
teardown

# ── T5: fence-excision mutant — the silent skip must RETURN ──────────────────
echo "T5: excise # BL-143-PASTCAP-RECOVERY → T1's self-approval is silently skipped again"
setup
write_phase_state_org
write_log_pastcap_approver "Karl Raulerson"
commit_log_as "Karl Raulerson" "karl@example.com"
mkdir -p "$TMP/scripts"
cp -R "$REPO_ROOT/scripts/lib" "$TMP/scripts/lib"
m=$(grep -c 'BL-143-PASTCAP-RECOVERY' "$SCRIPT") || m=0
case "$m" in ''|*[!0-9]*) m=0 ;; esac
sed '/# BL-143-PASTCAP-RECOVERY-BEGIN/,/# BL-143-PASTCAP-RECOVERY-END/d' \
  "$SCRIPT" > "$TMP/scripts/check-phase-gate.sh"
l=$(grep -c 'BL-143-PASTCAP-RECOVERY' "$TMP/scripts/check-phase-gate.sh") || l=0
case "$l" in ''|*[!0-9]*) l=0 ;; esac
chmod +x "$TMP/scripts/check-phase-gate.sh"
if [ "$m" -lt 2 ] || [ "$l" -ne 0 ]; then
  fail_ "T5-fence-excision-mutant" "excision vacuous (markers before=$m after=$l) — fence absent or sed missed it"
else
  out=$(run_gate_with_git_user "Karl Raulerson" "$TMP/scripts/check-phase-gate.sh")
  if echo "$out" | grep -qE "FAIL.*self-approval"; then
    fail_ "T5-fence-excision-mutant" "mutant still caught the past-cap self-approval; the recovery does not live (only) inside the fence"
  else
    pass "T5-fence-excision-mutant (excision restores the silent skip exactly — the fence is load-bearing)"
  fi
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
