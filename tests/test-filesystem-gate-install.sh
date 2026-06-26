#!/usr/bin/env bash
# tests/test-filesystem-gate-install.sh — BL-030 filesystem-gate installer tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLER="$REPO_ROOT/scripts/install-filesystem-gates.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup() {
  TMP=$(mktemp -d)
  ( cd "$TMP"
    git init -q
    git config user.email "t@t.l"
    git config user.name "t"
  )
  mkdir -p "$TMP/.git/hooks"
  # Pre-existing pre-commit with mock gitleaks block.
  cat > "$TMP/.git/hooks/pre-commit" <<'EOF'
#!/bin/sh
# >>> gitleaks
echo "running gitleaks"
# <<< gitleaks
EOF
  chmod +x "$TMP/.git/hooks/pre-commit"
  mkdir -p "$TMP/.claude"
}
teardown() { rm -rf "$TMP"; }

# T1: install adds the marked block.
echo "T1: install adds SOIF marker block"
setup
if [ ! -f "$INSTALLER" ]; then
  fail_ "T1" "installer missing (RED)"
else
  bash "$INSTALLER" --install "$TMP" >/dev/null 2>&1
  if grep -q ">>> SOIF framework gate" "$TMP/.git/hooks/pre-commit"; then pass "T1"; else fail_ "T1" "marker not found"; fi
fi
teardown

# T2: install is idempotent — second run does not duplicate.
echo "T2: install is idempotent"
setup
if [ ! -f "$INSTALLER" ]; then
  fail_ "T2" "installer missing"
else
  bash "$INSTALLER" --install "$TMP" >/dev/null 2>&1
  bash "$INSTALLER" --install "$TMP" >/dev/null 2>&1
  count=$(grep -c ">>> SOIF framework gate" "$TMP/.git/hooks/pre-commit")
  if [ "$count" = "1" ]; then pass "T2"; else fail_ "T2" "expected 1 marker, got $count"; fi
fi
teardown

# T3: install preserves existing gitleaks block.
echo "T3: install preserves pre-existing content"
setup
if [ ! -f "$INSTALLER" ]; then
  fail_ "T3" "installer missing"
else
  bash "$INSTALLER" --install "$TMP" >/dev/null 2>&1
  if grep -q "running gitleaks" "$TMP/.git/hooks/pre-commit"; then pass "T3"; else fail_ "T3" "gitleaks block lost"; fi
fi
teardown

# T4: uninstall removes only the marked block.
echo "T4: uninstall removes SOIF marker block but leaves rest"
setup
if [ ! -f "$INSTALLER" ]; then
  fail_ "T4" "installer missing"
else
  bash "$INSTALLER" --install "$TMP" >/dev/null 2>&1
  bash "$INSTALLER" --uninstall "$TMP" >/dev/null 2>&1
  if ! grep -q ">>> SOIF framework gate" "$TMP/.git/hooks/pre-commit" \
     && grep -q "running gitleaks" "$TMP/.git/hooks/pre-commit"; then pass "T4"; else fail_ "T4" "uninstall left wrong state"; fi
fi
teardown

# T5: install creates pre-commit if it didn't exist.
echo "T5: install creates pre-commit hook from scratch"
setup
rm -f "$TMP/.git/hooks/pre-commit"
if [ ! -f "$INSTALLER" ]; then
  fail_ "T5" "installer missing"
else
  bash "$INSTALLER" --install "$TMP" >/dev/null 2>&1
  if [ -x "$TMP/.git/hooks/pre-commit" ] && grep -q ">>> SOIF framework gate" "$TMP/.git/hooks/pre-commit"; then pass "T5"; else fail_ "T5" "hook not created or marker missing"; fi
fi
teardown

# T6: install also drops framework-gate.sh into .git/hooks/.
echo "T6: install drops framework-gate.sh"
setup
if [ ! -f "$INSTALLER" ]; then
  fail_ "T6" "installer missing"
else
  bash "$INSTALLER" --install "$TMP" >/dev/null 2>&1
  if [ -x "$TMP/.git/hooks/framework-gate.sh" ]; then pass "T6"; else fail_ "T6" "framework-gate.sh not installed"; fi
fi
teardown

# T7: uninstall does NOT delete framework-gate.sh (defense in depth — script self-no-ops on level change).
echo "T7: uninstall preserves framework-gate.sh"
setup
if [ ! -f "$INSTALLER" ]; then
  fail_ "T7" "installer missing"
else
  bash "$INSTALLER" --install "$TMP" >/dev/null 2>&1
  bash "$INSTALLER" --uninstall "$TMP" >/dev/null 2>&1
  if [ -f "$TMP/.git/hooks/framework-gate.sh" ]; then pass "T7"; else fail_ "T7" "framework-gate.sh deleted"; fi
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
