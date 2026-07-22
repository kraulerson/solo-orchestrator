#!/usr/bin/env bash
# tests/test-bl155-phase2-init-transition-commit.sh — BL-155 (Dogfood-4 S0 F1).
#
# The phase2-init-verified block in check_commit_ready used to sit ABOVE the
# staged-file classification, so at current_phase=2 with
# phase2_init.verified=false it blocked EVERY commit — including the
# docs/state-only Phase 1→2 transition commit that the generated CLAUDE.md
# step 3 instructs ("Commit both files together"). Chicken-and-egg: the
# commit that records entering Phase 2 required Phase-2 construction setup
# first. The fix moves the block AFTER the docs/dep-manifest exemption:
#   - docs/state-only and dep-manifest-only commits land (T1, T4)
#   - ANY commit staging non-exempt files still requires verified init
#     (T2 source, T3 mixed) — the T-strict-gate-blocks-unverified surface
#     in tests/test-bl112-commit-enforcement.sh is unchanged
#   - the verified path is unaffected (T5)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/process-checklist.sh"

unset GITHUB_BASE_REF

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Phase 2 fixture with phase2_init UNVERIFIED (the transition moment:
# current_phase was just flipped to 2, init has not been run yet).
setup_project() {
  TMP=$(mktemp -d)
  (
    cd "$TMP"
    git init -q
    git config user.email "test@test.local"
    git config user.name "test"
    mkdir -p .claude src
    cat > .claude/phase-state.json <<'JSON'
{"current_phase":2,"track":"standard","deployment":"personal","phases":{}}
JSON
    cat > .claude/process-state.json <<'JSON'
{"phase2_init":{"verified":false,"steps_completed":[]},"build_loop":{"feature":null,"step":0,"steps_completed":[],"started_at":null},"uat_session":{"started_at":null,"steps_completed":[]}}
JSON
  )
}
teardown_project() { rm -rf "$TMP"; }

# T1: the transition commit itself — docs/state-only staged files must land
# with init unverified. This is the exact Dogfood-4 S0 F1 repro.
echo "T1: docs/state-only transition commit allowed before init verified"
setup_project
(
  cd "$TMP"
  echo "# Project Bible" > PROJECT_BIBLE.md
  git add .claude/phase-state.json PROJECT_BIBLE.md
)
out=$(cd "$TMP" && "$SCRIPT" --check-commit-ready 2>&1) ; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T1: transition commit allowed (rc=0)"
else
  fail_ "T1" "expected rc=0, got rc=$rc out=$out"
fi
teardown_project

# T2: a SOURCE commit with init unverified must still be blocked, with the
# canonical message. Pins the enforcement the relocation must not weaken.
echo "T2: source commit still blocked before init verified"
setup_project
(
  cd "$TMP"
  echo "console.log(1)" > src/foo.ts
  git add src/foo.ts
)
out=$(cd "$TMP" && "$SCRIPT" --check-commit-ready 2>&1) ; rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -qF "Phase 2 initialization not verified"; then
  pass "T2: source commit blocked (rc=$rc) with init message"
else
  fail_ "T2" "expected rc!=0 + init message, got rc=$rc out=$out"
fi
teardown_project

# T3: mixed docs + source staged — source present, so the block still fires.
echo "T3: mixed docs+source commit still blocked before init verified"
setup_project
(
  cd "$TMP"
  echo "# notes" > NOTES.md
  echo "console.log(1)" > src/foo.ts
  git add NOTES.md src/foo.ts
)
out=$(cd "$TMP" && "$SCRIPT" --check-commit-ready 2>&1) ; rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -qF "Phase 2 initialization not verified"; then
  pass "T3: mixed commit blocked (rc=$rc) with init message"
else
  fail_ "T3" "expected rc!=0 + init message, got rc=$rc out=$out"
fi
teardown_project

# T4: dep-manifest-only commit (go.sum — no exempt extension, classified by
# _is_dep_manifest) — exemption parity with the docs arm.
echo "T4: dep-manifest-only commit allowed before init verified"
setup_project
(
  cd "$TMP"
  echo "example.com/mod v1.0.0 h1:abc=" > go.sum
  git add go.sum
)
out=$(cd "$TMP" && "$SCRIPT" --check-commit-ready 2>&1) ; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T4: dep-manifest commit allowed (rc=0)"
else
  fail_ "T4" "expected rc=0, got rc=$rc out=$out"
fi
teardown_project

# T5: verified init + source commit, no subject — the relocated block must
# not disturb the verified path (BL-139 subjectless default => non-feat).
echo "T5: verified init + source commit passes"
setup_project
(
  cd "$TMP"
  cat > .claude/process-state.json <<'JSON'
{"phase2_init":{"verified":true,"steps_completed":["project_scaffolded"]},"build_loop":{"feature":null,"step":0,"steps_completed":[],"started_at":null},"uat_session":{"started_at":null,"steps_completed":[]}}
JSON
  echo "console.log(1)" > src/foo.ts
  git add src/foo.ts
)
out=$(cd "$TMP" && "$SCRIPT" --check-commit-ready 2>&1) ; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T5: verified-path source commit allowed (rc=0)"
else
  fail_ "T5" "expected rc=0, got rc=$rc out=$out"
fi
teardown_project

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
