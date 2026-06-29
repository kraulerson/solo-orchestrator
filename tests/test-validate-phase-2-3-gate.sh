#!/usr/bin/env bash
# tests/test-validate-phase-2-3-gate.sh —
# code-test-gate-track-resume-validate-1.
#
# validate.sh's Approval Log section had checks for Phase 0→1, 1→2, and
# 3→4 gates but was missing the symmetric 2→3 check. A project at
# Phase 3+ with no `Phase 2 → Phase 3` entry (or one without a date)
# slipped past validation. The fix mirrors the 1→2 block at phase>=3.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATE="$REPO_ROOT/scripts/validate.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Build a minimal Phase 3+ project with various APPROVAL_LOG.md states
# and assert validate.sh reports the 2→3 gate correctly.
setup_project() {
  TMP=$(mktemp -d)
  PROJ="$TMP/p"
  mkdir -p "$PROJ/.claude" "$PROJ/docs/reference"
  (
    cd "$PROJ"
    git init -q
    git config user.email "test@test.local"
    git config user.name "test"
    # Minimal framework files validate.sh expects
    cat > CLAUDE.md <<'MD'
- **Project:** test
- **Platform:** cli
- **Track:** light
- **Primary Language:** typescript
MD
    cat > PROJECT_INTAKE.md <<'MD'
intake
MD
    cat > "docs/reference/builders-guide.md" <<'MD'
guide
MD
    cat > "docs/reference/user-guide.md" <<'MD'
user
MD
    cat > "docs/reference/governance-framework.md" <<'MD'
gov
MD
    cat > "docs/reference/cli-setup-addendum.md" <<'MD'
cli
MD
    touch .gitignore
    cat > .claude/phase-state.json <<'JSON'
{"current_phase":3}
JSON
    mkdir -p .github/workflows
    cat > .github/workflows/ci.yml <<'YML'
name: ci
on: push
YML
  )
}
teardown_project() { rm -rf "$TMP"; }

# T1: phase=3, APPROVAL_LOG.md has Phase 2 → Phase 3 with DATED entry.
# validate.sh should print an OK line for the 2→3 gate.
echo "T1: dated 2→3 gate yields print_ok"
setup_project
cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
### Phase 0 → Phase 1
- Date: 2026-01-01
- Approver: alice
### Phase 1 → Phase 2
- Date: 2026-02-01
### Phase 2 → Phase 3
- Date: 2026-03-01
- Approver: alice
MD
out=$(cd "$PROJ" && bash "$VALIDATE" 2>&1) || true
if echo "$out" | grep -qE "Phase 2.*3.*gate.*dated|Phase 2.*3.*gate: dated"; then
  pass "T1: validate.sh OK-line for dated 2→3 gate present"
else
  fail_ "T1" "expected '2→3 gate: dated entry found' OK line; got:
$out"
fi
teardown_project

# T2: phase=3, APPROVAL_LOG.md has Phase 2 → Phase 3 header but NO date.
# validate.sh should warn.
echo "T2: undated 2→3 gate yields warn"
setup_project
cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
### Phase 0 → Phase 1
- Date: 2026-01-01
### Phase 1 → Phase 2
- Date: 2026-02-01
### Phase 2 → Phase 3
- Approver: alice
MD
out=$(cd "$PROJ" && bash "$VALIDATE" 2>&1) || true
if echo "$out" | grep -qE "Phase 2.*3.*gate.*no date"; then
  pass "T2: validate.sh WARN for undated 2→3 gate present"
else
  fail_ "T2" "expected '2→3 gate: no date recorded' warning; got:
$out"
fi
teardown_project

# T3: phase=3, APPROVAL_LOG.md has 2→3 header with an invalid date format
# (must match YYYY-MM-DD). Should warn.
echo "T3: malformed 2→3 date yields warn"
setup_project
cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
### Phase 0 → Phase 1
- Date: 2026-01-01
### Phase 1 → Phase 2
- Date: 2026-02-01
### Phase 2 → Phase 3
- Date: March 1, 2026
MD
out=$(cd "$PROJ" && bash "$VALIDATE" 2>&1) || true
if echo "$out" | grep -qE "Phase 2.*3.*gate.*no date"; then
  pass "T3: validate.sh WARN for malformed 2→3 date present"
else
  fail_ "T3" "expected warning for malformed date; got:
$out"
fi
teardown_project

# T4: phase=2 (not yet past 2→3 boundary). Block should NOT fire — no
# OK and no WARN for 2→3.
echo "T4: phase<3 does NOT emit 2→3 line"
setup_project
cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{"current_phase":2}
JSON
cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
### Phase 0 → Phase 1
- Date: 2026-01-01
### Phase 1 → Phase 2
- Date: 2026-02-01
MD
out=$(cd "$PROJ" && bash "$VALIDATE" 2>&1) || true
if echo "$out" | grep -qE "Phase 2.*3.*gate"; then
  fail_ "T4" "2→3 gate line emitted at phase=2; got:
$out"
else
  pass "T4: no 2→3 line when phase<3"
fi
teardown_project

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
