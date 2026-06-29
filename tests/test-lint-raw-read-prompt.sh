#!/usr/bin/env bash
# tests/test-lint-raw-read-prompt.sh
#
# Tests for scripts/lint-raw-read-prompt.sh — the cycle-8 wave-3 CI
# backstop that bans bare `read -rp` (and `read -p`) outside the
# canonical centralized prompt helpers in scripts/lib/helpers.sh.
#
# Defect class:
#   Scripts call `read -rp "..." var` directly. Under unattended
#   invocation (CI, AI-agent driven runs, piped input that under-feeds
#   the prompt) `read` blocks indefinitely on EOF or reads an empty
#   string into `var`, then proceeds with side-effectful code that
#   should have been gated on operator confirmation. The remediation
#   is `prompt_input` / `prompt_yes_no` in scripts/lib/helpers.sh,
#   which both respect `! -t 0` / `CI=true` / `SOIF_NONINTERACTIVE=true`
#   and return safe defaults.
#
# Same harness pattern as tests/test-lint-fix-functions-stderr.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINTER="$REPO_ROOT/scripts/lint-raw-read-prompt.sh"

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
  mkdir -p "$PROJ/scripts/lib"
  cp "$LINTER" "$PROJ/scripts/lint-raw-read-prompt.sh"
  chmod +x "$PROJ/scripts/lint-raw-read-prompt.sh"
}
teardown() { rm -rf "$TMP"; }

run_lint() {
  ( cd "$PROJ" && bash scripts/lint-raw-read-prompt.sh 2>&1 )
  return $?
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: clean fixture (no read -rp) → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/clean.sh" <<'SH'
#!/usr/bin/env bash
result=$(prompt_input "Your name" "anon")
echo "Hello, $result"
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T1: clean fixture exits 0"
else
  fail_ "T1" "expected exit 0, got $rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: bare 'read -rp' outside lib/ → exit 1, names file:line ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/bad.sh" <<'SH'
#!/usr/bin/env bash
read -rp "Proceed? [y/N]: " yn
if [ "$yn" = "y" ]; then echo "ok"; fi
SH
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] \
   && echo "$out" | grep -q "scripts/bad.sh:2" \
   && echo "$out" | grep -qi "prompt_input\|prompt_yes_no"; then
  pass "T2: bare 'read -rp' flagged with migration hint"
else
  fail_ "T2" "expected exit 1 + file:line + migration hint; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: bare 'read -p' (no -r) outside lib/ → exit 1 ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/dashp.sh" <<'SH'
#!/usr/bin/env bash
read -p "Proceed? " yn
SH
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q "scripts/dashp.sh:2"; then
  pass "T3: 'read -p' (without -r) is also flagged"
else
  fail_ "T3" "expected exit 1; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T4: 'read -rp' INSIDE lib/helpers.sh → exit 0 (canonical helper home) ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/lib/helpers.sh" <<'SH'
#!/usr/bin/env bash
prompt_input() {
  local prompt="$1"
  read -rp "$prompt: " result
  echo "$result"
}
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T4: 'read -rp' inside scripts/lib/helpers.sh is allowed (canonical home)"
else
  fail_ "T4" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T5: 'read -rp' in a COMMENT line → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/commented.sh" <<'SH'
#!/usr/bin/env bash
# Previously this used: read -rp "Choice: " reply
result=$(prompt_input "Choice" "default")
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T5: 'read -rp' in a comment is correctly NOT flagged"
else
  fail_ "T5" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T6: 'read -r' WITHOUT -p → exit 0 (no-prompt form, valid for stdin-stream parsing) ==="
# ════════════════════════════════════════════════════════════════════
# `read -r line` reading from stdin (e.g. inside a `while IFS= read -r`
# loop) is the correct portable form for line-by-line file parsing —
# we do NOT want to flag it. Only the prompt forms `-p` / `-rp` are
# in scope.
setup
cat > "$PROJ/scripts/parser.sh" <<'SH'
#!/usr/bin/env bash
while IFS= read -r line || [ -n "$line" ]; do
  echo "got: $line"
done < some-input.txt
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T6: 'read -r' (no -p) is correctly out of scope"
else
  fail_ "T6" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T7: allowlist marker WITH reason → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
cat > "$PROJ/scripts/allowed.sh" <<'SH'
#!/usr/bin/env bash
read -rp "Proceed? " yn # lint-raw-read-prompt: allow interactive-only wizard path, gated by upstream TTY check
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
cat > "$PROJ/scripts/empty.sh" <<'SH'
#!/usr/bin/env bash
read -rp "Proceed? " yn # lint-raw-read-prompt: allow
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
# Wave-3 acceptance criterion: every in-tree raw `read -rp` outside
# scripts/lib/helpers.sh has either been migrated to prompt_input /
# prompt_yes_no OR carries an allowlist marker with reason. CI fails
# the merge if a future PR reintroduces an unmarked site.
out=$(bash "$LINTER" 2>&1); rc=$?
if [ $rc -eq 0 ]; then
  pass "T9: current repo HEAD is lint-clean (sweep verified)"
else
  fail_ "T9" "current repo HEAD has unmarked raw read -rp sites; rc=$rc; output:\n$out"
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T10: skip-paths — bare read -rp in Reports/ → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
mkdir -p "$PROJ/Reports"
cat > "$PROJ/Reports/sample.sh" <<'SH'
#!/usr/bin/env bash
read -rp "Choice: " reply
SH
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T10: bare read -rp under Reports/ is correctly skipped"
else
  fail_ "T10" "expected exit 0 (Reports/ should be skipped); rc=$rc; output:\n$out"
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
