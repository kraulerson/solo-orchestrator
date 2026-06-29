#!/usr/bin/env bash
# tests/test-lint-fix-functions-stderr.sh
#
# Tests for scripts/lint-fix-functions-stderr.sh — the cycle-8 wave-3
# CI backstop that bans `2>/dev/null` (and `2>&-`) inside any function
# body whose name starts with `fix_` across the scripts/ tree.
#
# Defect class:
#   fix_*() auto-fix functions in scripts/verify-install.sh and friends
#   silenced stderr from their internal commands. When the fix itself
#   failed (auth prompt, missing dep, hostile DNS) the operator saw a
#   "fix returned non-zero" with NO diagnostic — making the issue
#   un-actionable. See PR #92's scrub of fix_framework_clone /
#   fix_framework_manifest / fix_superpowers for the precedent.
#
# Same test-harness convention as tests/test-lint-counter-antipattern.sh:
# build per-case fixtures under a tmpdir, copy the linter in, run from
# the fixture root, assert on exit code and stderr.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINTER="$REPO_ROOT/scripts/lint-fix-functions-stderr.sh"

if [ ! -f "$LINTER" ]; then
  echo "FATAL: linter not found at $LINTER" >&2
  exit 2
fi

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup() {
  TMP=$(mktemp -d)
  PROJ="$TMP/repo"
  mkdir -p "$PROJ/scripts"
  cp "$LINTER" "$PROJ/scripts/lint-fix-functions-stderr.sh"
  chmod +x "$PROJ/scripts/lint-fix-functions-stderr.sh"
}
teardown() { rm -rf "$TMP"; }

run_lint() {
  ( cd "$PROJ" && bash scripts/lint-fix-functions-stderr.sh 2>&1 )
  return $?
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: clean fixture (fix_* with no stderr silencer) → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/clean.sh" <<'SH'
#!/usr/bin/env bash
fix_thing() {
  git clone -q https://example.invalid/repo.git target
}
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T1: clean fix_*() body exits 0"
else
  fail_ "T1" "expected exit 0, got $rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: fix_*() with 2>/dev/null → exit 1, names file:line + func ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/bad.sh" <<'SH'
#!/usr/bin/env bash
fix_silent_clone() {
  git clone -q https://example.invalid/repo.git target 2>/dev/null
}
SH
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] \
   && echo "$out" | grep -q "scripts/bad.sh:3" \
   && echo "$out" | grep -q "fix_silent_clone"; then
  pass "T2: bare 2>/dev/null inside fix_*() body is flagged with file:line + func"
else
  fail_ "T2" "expected exit 1 + file:line:func; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: fix_*() with 2>&- → exit 1 ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/closefd.sh" <<'SH'
#!/usr/bin/env bash
fix_closed_fd() {
  bash some-installer.sh 2>&-
}
SH
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] \
   && echo "$out" | grep -q "scripts/closefd.sh:3" \
   && echo "$out" | grep -q "fix_closed_fd"; then
  pass "T3: 2>&- (close-fd) inside fix_*() body is also flagged"
else
  fail_ "T3" "expected exit 1 for 2>&-; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T4: NON-fix_*() function with 2>/dev/null → exit 0 (out of scope) ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/check.sh" <<'SH'
#!/usr/bin/env bash
check_something() {
  # Read-only probe; legitimate 2>/dev/null suppression.
  git rev-parse --git-dir 2>/dev/null
}
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T4: non-fix_*() functions are out of scope"
else
  fail_ "T4" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T5: 2>/dev/null inside fix_*() but in a COMMENT → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/commented.sh" <<'SH'
#!/usr/bin/env bash
fix_explained() {
  # Drop `2>/dev/null` per the same rationale as fix_framework_clone.
  git clone -q https://example.invalid/repo.git target
}
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T5: 2>/dev/null in a comment line is correctly NOT flagged"
else
  fail_ "T5" "expected exit 0 for commented occurrence; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T6: 2>/dev/null inside fix_*() but in a HEREDOC body → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# fix_precommit_hook writes a pre-commit script via heredoc; the
# generated script's `2>/dev/null` inside `gitleaks ... 2>/dev/null`
# lives in the .git/hooks/pre-commit file at runtime, NOT in the
# fix function's own logic. The lint must not flag heredoc bodies.
setup
cat > "$PROJ/scripts/heredoc.sh" <<'SH'
#!/usr/bin/env bash
fix_precommit_hook() {
  mkdir -p .git/hooks
  cat > .git/hooks/pre-commit << 'HOOKEOF'
#!/usr/bin/env bash
if ! gitleaks git --staged 2>/dev/null; then
  echo "[BLOCKED]"
fi
HOOKEOF
  chmod +x .git/hooks/pre-commit
}
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T6: 2>/dev/null inside a heredoc body is correctly NOT flagged"
else
  fail_ "T6" "expected exit 0 for heredoc body; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T7: allowlist marker WITH reason → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/allowed.sh" <<'SH'
#!/usr/bin/env bash
fix_with_reason() {
  # The diagnostic is captured separately above; intentional silence here.
  some-command 2>/dev/null # lint-fix-functions-stderr: allow diagnostic already captured upstream
}
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T7: allowlist marker with reason passes"
else
  fail_ "T7" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T8: allowlist marker WITHOUT reason → exit 1 ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/empty-allow.sh" <<'SH'
#!/usr/bin/env bash
fix_empty_reason() {
  some-command 2>/dev/null # lint-fix-functions-stderr: allow
}
SH
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -qi "empty\|reason"; then
  pass "T8: empty-reason allowlist marker fails (justification required)"
else
  fail_ "T8" "expected exit 1 with reason-required diagnostic; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T9: MERGE GATE — run linter against current repo HEAD → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# Wave-3 acceptance criterion: PR #92 scrubbed every known fix_*()
# stderr silencer (fix_framework_clone, fix_framework_manifest,
# fix_superpowers). This test enforces the sweep stays clean.
out=$(bash "$LINTER" 2>&1); rc=$?
if [ $rc -eq 0 ]; then
  pass "T9: current repo HEAD is lint-clean (wave-3 sweep verified)"
else
  fail_ "T9" "current repo HEAD has unsilenced fix_*() stderr sites; rc=$rc; output:\n$out"
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T10: skip-paths — bad fix_*() in Reports/ → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
mkdir -p "$PROJ/Reports"
cat > "$PROJ/Reports/sample.sh" <<'SH'
#!/usr/bin/env bash
fix_ignored() {
  git clone https://x 2>/dev/null
}
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T10: bad fix_*() under Reports/ is correctly skipped"
else
  fail_ "T10" "expected exit 0 (Reports/ should be skipped); rc=$rc; output:\n$out"
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
