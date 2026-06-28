#!/usr/bin/env bash
# tests/test-lint-backlog-references.sh
#
# Tests for scripts/lint-backlog-references.sh — the cycle-7 Slot-5
# CI backstop that catches drift between commits and the backlog
# entries they close. Sibling to PR #72's counter-antipattern lint.
#
# Each test stages an isolated mock-repo with a tiny backlog.md and
# a tiny git history, then runs the linter from inside that repo via
# a copied script. T9 is the merge gate: it runs the linter against
# the REAL repo at HEAD with `--base origin/main` and requires exit 0.
#
# Style mirrors tests/test-lint-counter-antipattern.sh (PR #72): set
# -uo pipefail, mktemp fixtures, pass/fail counters, teardown after
# each case.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINTER="$REPO_ROOT/scripts/lint-backlog-references.sh"

if [ ! -f "$LINTER" ]; then
  echo "FATAL: linter not found at $LINTER" >&2
  exit 2
fi

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# setup() builds a per-test mock repo at $PROJ with:
#   • a copy of the linter at scripts/lint-backlog-references.sh
#   • an empty git repo (so `git log BASE..HEAD` works)
#   • an empty backlog file the test then writes
# The mock's BASE ref is the initial empty-tree commit at branch
# `base`; HEAD progresses on `main` so BASE..HEAD captures the
# test-added commits.
setup() {
  TMP=$(mktemp -d)
  PROJ="$TMP/repo"
  mkdir -p "$PROJ/scripts"
  cp "$LINTER" "$PROJ/scripts/lint-backlog-references.sh"
  chmod +x "$PROJ/scripts/lint-backlog-references.sh"

  (
    cd "$PROJ"
    git init -q -b main
    git config user.email "test@example.com"
    git config user.name "Test"
    : > solo-orchestrator-backlog.md
    git add solo-orchestrator-backlog.md
    git commit -q -m "chore: seed"
    git branch base
  )
}
teardown() { rm -rf "$TMP"; }

# Run the fixture-local linter against the local `base` ref.
run_lint() {
  ( cd "$PROJ" && bash scripts/lint-backlog-references.sh --base base 2>&1 )
  return $?
}

# Append a commit with a free-form message; no file change needed —
# use --allow-empty.
commit_msg() {
  ( cd "$PROJ" && git commit --allow-empty -q -m "$1" )
}

# Replace the backlog file in $PROJ with the heredoc body, then
# commit it. The lint walks the file as-of HEAD.
write_backlog() {
  local body="$1"
  printf '%s' "$body" > "$PROJ/solo-orchestrator-backlog.md"
  ( cd "$PROJ" && git add solo-orchestrator-backlog.md \
                && git commit -q -m "chore: update backlog" )
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: clean backlog + commit referencing real BL → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
write_backlog '## BL-001: real entry

**Status:** Resolved (2026-01-01, PR #1)

Body.
'
commit_msg "fix: do something (BL-001)"
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T1: real BL reference resolves cleanly"
else
  fail_ "T1" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: commit references BL-999 (unknown) → exit 1 ==="
# ════════════════════════════════════════════════════════════════════
setup
write_backlog '## BL-001: real entry

**Status:** Resolved (2026-01-01, PR #1)

Body.
'
commit_msg "fix: typo'd reference (BL-999)"
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q "unknown BL reference 'BL-999'"; then
  pass "T2: unknown BL-999 reference is rejected"
else
  fail_ "T2" "expected exit 1 + unknown-ref diagnostic; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: entry marked Closed without PR# or SHA → exit 1 ==="
# ════════════════════════════════════════════════════════════════════
setup
write_backlog '## BL-005: missing citation

**Status:** Closed

Body without any PR cite or commit SHA.
'
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q "BL-005 marked Closed/Resolved but no PR#"; then
  pass "T3: Closed entry without citation is flagged"
else
  fail_ "T3" "expected exit 1 + uncited-closure diagnostic; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T4: entry marked Closed WITH PR #42 citation → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
write_backlog '## BL-006: cited via PR number

**Status:** Closed — shipped 2026-01-02 (PR #42)

Body.
'
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T4: PR# citation in Status line is accepted"
else
  fail_ "T4" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T5: entry marked Closed WITH backticked SHA citation → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
write_backlog '## BL-020: cited via commit SHA

**Status:** Closed
**Closed:** 2026-01-03 — commit `b9c4c4c` ("fix: ...").

Body.
'
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T5: backticked-SHA citation is accepted"
else
  fail_ "T5" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T6: entry marked Open (no citation required) → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
write_backlog '## BL-007: still open

**Status:** Open

Body without any citation — that is fine because the entry is open.
'
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T6: Open entry passes without citation"
else
  fail_ "T6" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T7: allowlist marker WITH reason suppresses citation check → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
write_backlog '## BL-099: legacy pre-convention close

**Status:** Closed <!-- lint-backlog-references: allow closed before citation convention existed -->

Body has no PR# or SHA, but the allowlist marker carries justification.
'
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T7: allowlist with reason suppresses uncited-closure"
else
  fail_ "T7" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T8: case-insensitive match — 'bl-031' in commit subject ==="
# ════════════════════════════════════════════════════════════════════
setup
write_backlog '## BL-031: real entry

**Status:** Resolved (2026-01-01, PR #1)

Body.
'
commit_msg "fix(init): host-agnostic flow (bl-031)"
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T8: lower-case bl-031 resolves to BL-031"
else
  fail_ "T8" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# Bonus: branch-scoped commit-message allowlist. A later commit's
# `lint-backlog-references-ignore:` footer retroactively exempts an
# earlier commit's prose mention of a placeholder token. Scope is
# branch-wide (mirrors how this PR itself uses the footer to suppress
# its own BL-099 fixture mention).
echo ""
echo "=== T8b: branch-scoped ignore footer suppresses prose mention → exit 0 ==="
setup
write_backlog '## BL-007: real entry

**Status:** Resolved (2026-01-01, PR #1)

Body.
'
commit_msg "docs: describe sample diagnostic (mentions BL-099 in prose)"
commit_msg "$(printf 'chore: clean up\n\nlint-backlog-references-ignore: BL-099')"
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T8b: branch-scoped ignore footer exempts BL-099 across BASE..HEAD"
else
  fail_ "T8b" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# Bonus: also verify that empty allowlist reason FAILS (mirrors PR #72
# allowlist semantics — reason is REQUIRED to keep reviewers honest).
echo ""
echo "=== T7b: allowlist marker WITHOUT reason → exit 1 (justification required) ==="
setup
write_backlog '## BL-088: legacy entry with empty allow

**Status:** Closed <!-- lint-backlog-references: allow -->

Body.
'
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q "empty allowlist reason"; then
  pass "T7b: empty-reason allowlist marker fails"
else
  fail_ "T7b" "expected exit 1 + empty-reason diagnostic; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T10: --pre-commit-mode with VALID BL via --message → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# Slot-5 / cycle-8 contract: pre-commit-gate.sh invokes the lint at
# commit time, supplying the prospective commit message. No git log
# walk happens; the lint scans the message tokens against the backlog
# header set.
setup
write_backlog '## BL-031: real entry
**Status:** Resolved (2026-01-01, PR #1)
Body.
'
out=$( cd "$PROJ" && bash scripts/lint-backlog-references.sh --pre-commit-mode \
        --message "feat(init): host-agnostic flow (BL-031)" 2>&1 ); rc=$?
if [ $rc -eq 0 ]; then
  pass "T10: --pre-commit-mode --message with valid BL passes"
else
  fail_ "T10" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T11: --pre-commit-mode with UNKNOWN BL-999 via --message → exit 1 ==="
# ════════════════════════════════════════════════════════════════════
setup
write_backlog '## BL-031: real entry
**Status:** Resolved (2026-01-01, PR #1)
Body.
'
out=$( cd "$PROJ" && bash scripts/lint-backlog-references.sh --pre-commit-mode \
        --message "fix: typo (BL-999)" 2>&1 ); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q "unknown BL reference 'BL-999' in prospective commit message"; then
  pass "T11: --pre-commit-mode --message with unknown BL is rejected"
else
  fail_ "T11" "expected exit 1 + prospective-message diagnostic; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T12: --pre-commit-mode reads message from stdin → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# Mirrors the --terminal-mode invocation path: pre-commit-gate.sh pipes
# .git/COMMIT_EDITMSG into the lint over stdin.
setup
write_backlog '## BL-042: real entry
**Status:** Resolved (2026-01-01, PR #1)
Body.
'
out=$( cd "$PROJ" && printf 'fix: thing (BL-042)\n' \
        | bash scripts/lint-backlog-references.sh --pre-commit-mode 2>&1 ); rc=$?
if [ $rc -eq 0 ]; then
  pass "T12: --pre-commit-mode reads stdin and accepts valid BL"
else
  fail_ "T12" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T13: --pre-commit-mode still flags uncited Closed entries in backlog → exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# Step 3 (backlog block scan) MUST keep running in pre-commit mode —
# it's structural on the file, independent of git history. Otherwise
# the operator-side enforcement would have a blind spot vs CI.
setup
write_backlog '## BL-005: missing citation
**Status:** Closed
Body without any PR cite or commit SHA.
'
out=$( cd "$PROJ" && bash scripts/lint-backlog-references.sh --pre-commit-mode \
        --message "chore: unrelated change" 2>&1 ); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q "BL-005 marked Closed/Resolved but no PR#"; then
  pass "T13: --pre-commit-mode still runs Step 3 backlog block scan"
else
  fail_ "T13" "expected exit 1 + uncited-closure diagnostic; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T9: MERGE GATE — run linter against current repo HEAD vs origin/main → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# Wave-2 acceptance criterion (mirrors PR #72 T9): proves the lint
# rules align with the current real backlog + commit history. If this
# fails locally, EITHER the lint is too strict (revise here) OR the
# backlog has uncited closures (backfill citations or allowlist them
# IN THIS PR before merging).
out=$(bash "$LINTER" --base origin/main 2>&1); rc=$?
if [ $rc -eq 0 ]; then
  pass "T9: current repo HEAD passes the backlog-references lint"
else
  fail_ "T9" "current repo HEAD fails the lint; rc=$rc; output:\n$out"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
