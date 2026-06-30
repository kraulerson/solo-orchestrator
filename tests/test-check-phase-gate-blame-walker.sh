#!/usr/bin/env bash
# tests/test-check-phase-gate-blame-walker.sh
#
# Regression tests for code-check-gates-7-followup (cycle-7 PR #87
# verifier major #4):
#   scripts/check-phase-gate.sh::validate_approval_fields used
#   `git log -n 1 --format=%an -- APPROVAL_LOG.md` to resolve the
#   commit author for the self-approval check. That returns whoever
#   most recently TOUCHED the file — NOT who added the specific
#   gate's Approver row. The result was an exploitable false-negative:
#
#     Alice commits her own approval row at gate A (real self-approval
#     — should FAIL).
#     Bob later commits a typo fix to gate B's row.
#     Pre-fix: git log -1 returns Bob → Alice's self-approval silently
#     passes the check.
#
# Fix: resolve the line number of the active gate section's Approver
# row, then use `git blame -L<N>,<N> --line-porcelain` to extract
# the author of that specific line's most recent change. Compare
# THAT author against the approver name.
#
# Tests:
#   T-blame-1: Alice approves gate 0→1 in commit C1; Bob later commits
#              a typo fix to gate 1→2 row. check-phase-gate.sh MUST
#              still FAIL on Alice's self-approval at gate 0→1.
#              (Pre-fix this PASSED silently — RED on origin/main.)
#   T-blame-2: Alice's row exists in working tree only (uncommitted).
#              Behavior matches PR #87's WARN: "cannot verify."
#   T-blame-3: Bob commits Alice's approval row on her behalf
#              (legitimate organizational approval — Alice is the
#              approver, Bob is the committer). MUST NOT FAIL.
#   T-blame-4: Malformed APPROVAL_LOG.md (gate header is `### ` h3
#              instead of canonical `## ` h2). The PR #116 awk walker
#              fails to match, and the pre-followup code silently fell
#              back to file-level `git log -1 -- APPROVAL_LOG.md` — re-
#              introducing the very evasion the per-line walker closes.
#              The follow-up MUST WARN ("gate section not found") and
#              MUST NOT silently fall back. Confirms the silent-pass
#              class is closed for non-canonical files.

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
  ( cd "$PROJ" && git init -q && git config user.email "ambient@example.com" \
                              && git config user.name  "Ambient" \
                              && git config commit.gpgsign false )
}
teardown() { rm -rf "$TMP"; }

# Phase state — current_phase=2 so BOTH gates (0→1 and 1→2) are checked.
write_phase_state_org_phase2() {
  cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":2,"deployment":"organizational","gates":{"phase_0_to_1":"2026-02-01","phase_1_to_2":"2026-02-15"}}
JSON
}

# Phase state — current_phase=1 (single-gate scenarios).
write_phase_state_org_phase1() {
  cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":1,"deployment":"organizational","gates":{"phase_0_to_1":"2026-02-01"}}
JSON
}

# APPROVAL_LOG with two phase-gate sections. The 0→1 section's Approver
# is supplied; the 1→2 section's Approver is fixed to "Carol".
write_two_gate_log() {
  local approver_01="$1"
  cat > "$PROJ/APPROVAL_LOG.md" <<MD
# APPROVAL_LOG

## Phase Gate: Phase 0 → Phase 1
| Field | Value |
|---|---|
| **Gate** | Phase 0 → Phase 1 |
| **Approver** | $approver_01 |
| **Date** | 2026-02-01 |

---

## Phase Gate: Phase 1 → Phase 2
| Field | Value |
|---|---|
| **Gate** | Phase 1 → Phase 2 |
| **Approver** | Carol Approver |
| **Date** | 2026-02-15 |
MD
}

# Single-gate log (0→1) for T-blame-2.
write_single_gate_log() {
  local approver_01="$1"
  cat > "$PROJ/APPROVAL_LOG.md" <<MD
# APPROVAL_LOG

## Phase Gate: Phase 0 → Phase 1
| Field | Value |
|---|---|
| **Gate** | Phase 0 → Phase 1 |
| **Approver** | $approver_01 |
| **Date** | 2026-02-01 |
MD
}

# Commit currently-staged files with a specific author identity.
git_add_and_commit_as() {
  local name="$1" email="$2" msg="$3"
  ( cd "$PROJ" \
      && git add -A \
      && GIT_AUTHOR_NAME="$name" GIT_AUTHOR_EMAIL="$email" \
         GIT_COMMITTER_NAME="$name" GIT_COMMITTER_EMAIL="$email" \
         git commit -qm "$msg" )
}

run_gate() {
  ( cd "$PROJ" && bash "$SCRIPT" 2>&1 ) || true
}

# ---------------------------------------------------------------------
# T-blame-1: Alice commits her own approval row at gate 0→1 (real
# self-approval — MUST FAIL). Bob later commits a typo fix to gate 1→2
# row. Pre-fix `git log -1 -- APPROVAL_LOG.md` returns Bob, and the
# self-approval check silently passes (false-negative). The blame-
# walker fix MUST keep the FAIL on Alice at gate 0→1.
# ---------------------------------------------------------------------
echo "T-blame-1: Alice self-approves gate 0→1, Bob later edits gate 1→2 → MUST still FAIL Alice"
setup
write_phase_state_org_phase2
# C0 (Bootstrap): scaffolds the APPROVAL_LOG.md with `[Name]` placeholders
# for BOTH gates. Authored by a third identity ("Bootstrap"). This
# tailoring tightening (PR #116 verifier minor #1) ensures every line
# in the file is initially blamed to Bootstrap — NOT to Alice — so a
# wrong fix like `git blame -L 1,1` would return Bootstrap, fail to
# match approver "Alice Approver", and the test correctly FAILs RED.
# Without this commit, Alice's C1 would author the entire file and
# `-L 1,1` would coincidentally produce the expected FAIL.
write_two_gate_log "[Name]"
git_add_and_commit_as "Bootstrap" "bootstrap@example.com" "scaffold approval log"
# C1: Alice rewrites HER OWN approver row only (gate 0→1). The single
# changed line is blamed to Alice; every other line stays Bootstrap.
write_two_gate_log "Alice Approver"
git_add_and_commit_as "Alice Approver" "alice@example.com" "alice self-approves gate 0->1"
# C2: Bob fixes a typo in gate 1→2 only (changes "Carol Approver" → "Carol M. Approver").
sed -i.bak 's/Carol Approver/Carol M. Approver/' "$PROJ/APPROVAL_LOG.md" && rm -f "$PROJ/APPROVAL_LOG.md.bak"
git_add_and_commit_as "Bob Editor" "bob@example.com" "typo fix in gate 1->2 row"
out=$(run_gate)
# The 0→1 self-approval FAIL must appear in the output. Be strict:
# require the substring "self-approval" inline with a FAIL marker that
# clearly cites Phase 0→1.
if echo "$out" | grep -E "FAIL.*Phase 0.*1.*self-approval|FAIL.*self-approval.*Phase 0" >/dev/null \
   || echo "$out" | awk '/Phase 0/{ctx=1} ctx && /FAIL.*self-approval/{print; found=1} END{exit !found}' >/dev/null; then
  pass "T-blame-1: per-line blame correctly fails Alice's self-approval despite Bob's later edit"
else
  fail_ "T-blame-1" "expected FAIL on Alice's self-approval at gate 0→1 (per-line blame); output:
$(echo "$out" | grep -E 'Phase 0|self-approval|FAIL|WARN' | head -20)"
fi
teardown

# ---------------------------------------------------------------------
# T-blame-2: Alice's row exists in the working tree only (never
# committed). `git blame` on an uncommitted line returns the Not
# Committed Yet pseudo-author. Behavior MUST match PR #87's WARN:
# "cannot verify commit author … not yet committed".
# ---------------------------------------------------------------------
echo "T-blame-2: approver row uncommitted → WARN 'cannot verify'"
setup
write_phase_state_org_phase1
# Pre-existing commit with a placeholder log (no approver yet).
write_single_gate_log "[Name]"
git_add_and_commit_as "Bootstrap" "bootstrap@example.com" "initial empty approval log"
# Now mutate working tree to add Alice's approver, WITHOUT committing.
write_single_gate_log "Alice Approver"
out=$(run_gate)
if echo "$out" | grep -qE "\[WARN\].*Phase 0.*1.*cannot verify commit author"; then
  pass "T-blame-2: uncommitted approver row → WARN 'cannot verify commit author'"
else
  fail_ "T-blame-2" "expected [WARN] 'cannot verify commit author' for uncommitted approver row; output:
$(echo "$out" | grep -E 'WARN|FAIL|Phase 0' | head -10)"
fi
teardown

# ---------------------------------------------------------------------
# T-blame-3: Bob legitimately commits Alice's approval row on her
# behalf (Alice is approver, Bob is committer). Commit author differs
# from approver — that's the design. MUST NOT FAIL with self-approval.
# ---------------------------------------------------------------------
echo "T-blame-3: Bob commits Alice's approval on her behalf → MUST NOT FAIL"
setup
write_phase_state_org_phase1
write_single_gate_log "Alice Approver"
git_add_and_commit_as "Bob Committer" "bob@example.com" "bob commits alice's approval"
out=$(run_gate)
if echo "$out" | grep -qE "FAIL.*self-approval"; then
  fail_ "T-blame-3" "self-approval FAIL should NOT fire when committer differs from approver; output:
$(echo "$out" | grep -E 'FAIL|self-approval' | head -10)"
else
  pass "T-blame-3: distinct committer + approver → no self-approval FAIL"
fi
teardown

# ---------------------------------------------------------------------
# T-blame-4: Malformed APPROVAL_LOG.md uses `### ` h3 instead of the
# canonical `## ` h2 for the gate header. PR #116's awk walker only
# matches `^## `, so it returns no line number, and the silent-fallback
# branch ran `git log -1 -- APPROVAL_LOG.md` — which returned Bob (the
# latest committer, unrelated to Alice's self-approval row). Alice's
# true self-approval silently passed.
#
# Follow-up requirement: WARN + return — never silently fall back.
# Operator MUST see "cannot verify" (or equivalent) so the malformed
# file becomes an audit signal instead of an exploit surface.
# ---------------------------------------------------------------------
echo "T-blame-4: malformed APPROVAL_LOG.md (h3 header) → MUST WARN, not silently pass"
setup
write_phase_state_org_phase1
# Inline the malformed file — gate name appears in prose AND under an
# `### ` h3 header (not `## ` h2). grep -A 20 still finds it (so the
# approver_name extraction sees "Alice Approver"), but the awk walker
# requires `^## ` and returns no line number.
cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
# APPROVAL_LOG

This log records approvals for Phase 0 → Phase 1 transitions.

### Phase 0 → Phase 1
| Field | Value |
|---|---|
| **Gate** | Phase 0 → Phase 1 |
| **Approver** | Alice Approver |
| **Date** | 2026-02-01 |
MD
# C1: Alice commits her own approval row (true self-approval).
git_add_and_commit_as "Alice Approver" "alice@example.com" "alice self-approves (malformed log)"
# C2: Bob commits an unrelated prose-line typo fix. With pre-followup
# code, `git log -1` returns Bob → no name match → silent pass.
sed -i.bak 's/records approvals/records the approvals/' "$PROJ/APPROVAL_LOG.md" \
  && rm -f "$PROJ/APPROVAL_LOG.md.bak"
git_add_and_commit_as "Bob Editor" "bob@example.com" "prose typo fix"
out=$(run_gate)
# Operator-visible audit signal: either a self-approval FAIL (caught
# Alice via some other path) OR a WARN that explicitly cites the
# malformed/non-canonical gate section. The forbidden outcome is a
# silent pass — no FAIL and no WARN about commit-author/gate-section.
if echo "$out" | grep -qE "\[WARN\].*Phase 0.*1.*(cannot verify|gate section not found|no '## '|malformed)"; then
  pass "T-blame-4: malformed APPROVAL_LOG.md surfaces WARN — silent-fallback closed"
elif echo "$out" | grep -qE "FAIL.*Phase 0.*1.*self-approval"; then
  pass "T-blame-4: malformed APPROVAL_LOG.md still caught self-approval via FAIL"
else
  fail_ "T-blame-4" "silent-pass: expected [WARN] (cannot verify | gate section not found) or FAIL self-approval; output:
$(echo "$out" | grep -E 'WARN|FAIL|Phase 0' | head -10)"
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
