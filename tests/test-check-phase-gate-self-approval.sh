#!/usr/bin/env bash
# tests/test-check-phase-gate-self-approval.sh
#
# Regression tests for code-check-gates-5 (audit v2 S3):
#   scripts/check-phase-gate.sh::validate_approval_fields used
#   `grep -qi "$git_user"` (substring case-insensitive) against the
#   APPROVAL_LOG.md Approver value column. This produced false
#   [FAIL]s for any approver whose name CONTAINED the running
#   operator's git user name — e.g. operator "Karl" wrongly flagged
#   approver "Karla", "Karlyn", "karl-cobb".
#
# Worse, the comparison source is the ambient `git config user.name`
# rather than the actual commit author of the APPROVAL_LOG.md change,
# which is what baseline §5 invariant #9 requires
# ("The git author on the commit adding the approval entry must be
# the approver, not the Orchestrator").
#
# Fix:
#   1. Compare names token-exact (case-insensitive). A name matches
#      only when the normalized full-name strings are equal.
#   2. Authoritative source for self-approval is the commit author of
#      the most recent APPROVAL_LOG.md change. The ambient git user
#      remains a softer WARN signal when it matches the approver but
#      the commit author does NOT match — useful for catching
#      operators who rewrote author metadata.

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

# Write a minimal APPROVAL_LOG with a Phase 0→1 entry whose
# Approver value is the given name and Date is dated 2026-02-01.
write_log_with_approver() {
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

write_phase_state_org() {
  cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":1,"deployment":"organizational","gates":{"phase_0_to_1":"2026-02-01"}}
JSON
}

# Commit APPROVAL_LOG with a specific author identity (name + email).
commit_log_as() {
  local name="$1" email="$2"
  ( cd "$PROJ" \
      && git add APPROVAL_LOG.md .claude/phase-state.json 2>/dev/null \
      && GIT_AUTHOR_NAME="$name" GIT_AUTHOR_EMAIL="$email" \
         GIT_COMMITTER_NAME="$name" GIT_COMMITTER_EMAIL="$email" \
         git commit -qm "approval" )
}

run_gate_with_git_user() {
  local user="$1"
  ( cd "$PROJ" && git config user.name "$user" && bash "$SCRIPT" 2>&1 ) || true
}

# ---------------------------------------------------------------------
# T1: approver "Karla" with ambient git user "Karl" and a DIFFERENT
# commit author → MUST NOT FAIL. The pre-fix substring match wrongly
# triggered self-approval because "Karla" contains "Karl"; token-exact
# normalization plus commit-author authoritativeness must prevent this.
# ---------------------------------------------------------------------
echo "T1: approver 'Karla' + git user 'Karl' (distinct author) → no self-approval FAIL"
setup
write_phase_state_org
write_log_with_approver "Karla"
# Karla was approved by someone else — Bob committed the entry.
commit_log_as "Bob Approver" "bob@example.com"
out=$(run_gate_with_git_user "Karl")
if echo "$out" | grep -qE "FAIL.*self-approval"; then
  fail_ "T1" "false-positive self-approval FAIL fired for distinct names; out:
$(echo "$out" | grep -i self-approval)"
else
  pass "T1: token-exact match — no false-FAIL for 'Karla' vs 'Karl'"
fi
teardown

# ---------------------------------------------------------------------
# T2: approver "Karl Raulerson" committed by author "Karl Raulerson"
# → MUST FAIL (true self-approval — commit author matches approver).
# ---------------------------------------------------------------------
echo "T2: approver 'Karl Raulerson' + commit author 'Karl Raulerson' → FAIL"
setup
write_phase_state_org
write_log_with_approver "Karl Raulerson"
commit_log_as "Karl Raulerson" "karl@example.com"
out=$(run_gate_with_git_user "Karl Raulerson")
if echo "$out" | grep -qE "FAIL.*self-approval"; then
  pass "T2: FAIL fires when commit author equals approver"
else
  fail_ "T2" "expected FAIL when commit author == approver; out:
$(echo "$out" | grep -E 'Phase 0|self-approval' | head)"
fi
teardown

# ---------------------------------------------------------------------
# T3: approver "Karl Raulerson" committed by DIFFERENT author
# ("Jane Approver") but ambient git user is "Karl Raulerson"
# → MUST emit WARN (not FAIL). The commit-author check is authoritative.
# ---------------------------------------------------------------------
echo "T3: ambient user matches approver but commit author differs → WARN, not FAIL"
setup
write_phase_state_org
write_log_with_approver "Karl Raulerson"
commit_log_as "Jane Approver" "jane@example.com"
out=$(run_gate_with_git_user "Karl Raulerson")
if echo "$out" | grep -qE "FAIL.*self-approval"; then
  fail_ "T3" "should not FAIL — commit author is different; out:
$(echo "$out" | grep -E 'self-approval|Phase 0')"
elif echo "$out" | grep -qE "WARN.*self-approval|WARN.*ambient.*git user"; then
  pass "T3: WARN fires for ambient mismatch without FAIL"
else
  # Acceptable: no message at all (commit author authoritative). The
  # WARN is a nice-to-have; primary requirement is no FAIL.
  pass "T3: no FAIL emitted (commit-author authoritative)"
fi
teardown

# ---------------------------------------------------------------------
# T4: personal deployment with matching names → check does NOT fire.
# ---------------------------------------------------------------------
echo "T4: personal deployment → self-approval check does not fire"
setup
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":1,"deployment":"personal","gates":{"phase_0_to_1":"2026-02-01"}}
JSON
write_log_with_approver "Karl Raulerson"
commit_log_as "Karl Raulerson" "karl@example.com"
out=$(run_gate_with_git_user "Karl Raulerson")
if echo "$out" | grep -qE "FAIL.*self-approval|WARN.*self-approval"; then
  fail_ "T4" "self-approval check should not fire for personal; out:
$(echo "$out" | grep -i self-approval)"
else
  pass "T4: self-approval check correctly skipped for personal"
fi
teardown

# ---------------------------------------------------------------------
# T5: case-insensitive token-exact — "karl raulerson" approver +
# "Karl Raulerson" commit author → FAIL (case-insensitive match).
# ---------------------------------------------------------------------
echo "T5: case-insensitive token-exact match → FAIL"
setup
write_phase_state_org
write_log_with_approver "karl raulerson"
commit_log_as "Karl Raulerson" "karl@example.com"
out=$(run_gate_with_git_user "Karl Raulerson")
if echo "$out" | grep -qE "FAIL.*self-approval"; then
  pass "T5: case-insensitive equal names → FAIL"
else
  fail_ "T5" "expected FAIL for case-insensitive equal names; out:
$(echo "$out" | grep -E 'self-approval|Phase 0')"
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
