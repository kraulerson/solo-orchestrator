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

# T8: pass-arm coverage — a CLEAN commit through the installed gate writes the
# .claude/last-gate-pass.txt receipt (BL-161) and appends NO row to the tracked
# .claude/bypass-audit.json. Before T8 this installer suite was BLIND to the PASS
# terminal: it stayed green under both BL-161 receipt mutations, so it could not
# catch a regression in the clean-pass receipt path. Fixture mirrors
# tests/test-bl161-ledger-real-events-only.sh T1 — the REAL installer + generated
# framework-gate, with process-checklist / pre-commit-gate STUBS whose exit 0 is
# the PASS verdict. The generated gate re-invokes the project's OWN
# scripts/install-filesystem-gates.sh __record_pass, so the fixture copies it in.
echo "T8: clean commit writes last-gate-pass.txt receipt, no tracked-ledger row"
if [ ! -f "$INSTALLER" ]; then
  fail_ "T8" "installer missing"
elif ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] T8 — jq required for the strict-gate pass path"
else
  TMP=$(mktemp -d)
  mkdir -p "$TMP/.claude" "$TMP/scripts" "$TMP/src"
  printf '{"frameworkVersion":"test","enforcement_level":"strict"}\n' > "$TMP/.claude/manifest.json"
  printf '[]\n' > "$TMP/.claude/bypass-audit.json"
  cp "$INSTALLER" "$TMP/scripts/install-filesystem-gates.sh"
  chmod +x "$TMP/scripts/install-filesystem-gates.sh"
  printf '#!/bin/sh\nexit 0\n' > "$TMP/scripts/process-checklist.sh"
  printf '#!/bin/sh\nexit 0\n' > "$TMP/scripts/pre-commit-gate.sh"
  chmod +x "$TMP/scripts/process-checklist.sh" "$TMP/scripts/pre-commit-gate.sh"
  ( cd "$TMP" && git init -q && git config user.email t@t.l && git config user.name t \
      && git add -A && git commit -q -m "chore: seed" ) >/dev/null 2>&1
  bash "$INSTALLER" --install "$TMP" >/dev/null 2>&1
  printf 'export const x = 1;\n' > "$TMP/src/widget.ts"
  ( cd "$TMP" && git add src/widget.ts ) >/dev/null 2>&1
  ledger_before=$(cat "$TMP/.claude/bypass-audit.json")
  if ( cd "$TMP" && git commit -q -m "chore: land widget" ) >/dev/null 2>&1; then
    receipt=no
    if [ -s "$TMP/.claude/last-gate-pass.txt" ]; then receipt=yes; fi
    passrows=$(jq '[.[] | select(.type=="terminal_commit_passed")] | length' "$TMP/.claude/bypass-audit.json" 2>/dev/null || echo ERR)
    ledger_after=$(cat "$TMP/.claude/bypass-audit.json")
    lu=no
    if [ "$ledger_before" = "$ledger_after" ]; then lu=yes; fi
    if [ "$receipt" = yes ] && [ "$passrows" = 0 ] && [ "$lu" = yes ]; then
      pass "T8 (receipt written, 0 terminal_commit_passed rows, tracked ledger byte-unchanged)"
    else
      fail_ "T8" "receipt=$receipt terminal_commit_passed_rows=$passrows tracked_ledger_unchanged=$lu (want yes/0/yes)"
    fi
  else
    fail_ "T8" "clean commit REFUSED — the gate should PASS with exit-0 stubs"
  fi
  rm -rf "$TMP"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
