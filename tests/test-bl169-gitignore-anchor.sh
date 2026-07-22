#!/usr/bin/env bash
# tests/test-bl169-gitignore-anchor.sh — BL-169 (Dogfood-4 S4 F2).
#
# The scaffold gitignore's unanchored `test-results/` also matched
# docs/test-results/ — the Phase-3 evidence directory the Phase 3→4 gate
# REQUIRES — so every generated project's gate passed locally (files in
# the working tree) but failed on a fresh CI checkout. Pins:
#   T1  the template carries the root-anchored /test-results/ line
#   T2  no unanchored `test-results/` pattern remains
#   T3  the transient scanner workdir docs/test-results/phase3/ is ignored
#   T4  BEHAVIORAL: under a real `git check-ignore`, docs/test-results/
#       evidence is TRACKED while test-results/ and the phase3 workdir
#       are ignored — the pin that matters survives any rewrite of the
#       template's comment/pattern style.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMPL="$REPO_ROOT/templates/generated/gitignore-base.tmpl"

unset GITHUB_BASE_REF

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

echo "T1: template carries root-anchored /test-results/"
if grep -qE '^/test-results/$' "$TMPL"; then
  pass "T1: /test-results/ present"
else
  fail_ "T1" "no root-anchored /test-results/ line in gitignore-base.tmpl"
fi

echo "T2: no unanchored test-results/ pattern remains"
if grep -qE '^test-results/$' "$TMPL"; then
  fail_ "T2" "unanchored 'test-results/' still present — re-hides docs/test-results/"
else
  pass "T2: unanchored form absent"
fi

echo "T3: transient scanner workdir ignored"
if grep -qE '^docs/test-results/phase3/$' "$TMPL"; then
  pass "T3: docs/test-results/phase3/ ignored"
else
  fail_ "T3" "docs/test-results/phase3/ not ignored — validation runs dirty the tree"
fi

echo "T4: behavioral check-ignore semantics"
TMP=$(mktemp -d)
(
  cd "$TMP"
  git init -q
  git config user.email "test@test.local"
  git config user.name "test"
  cp "$TMPL" .gitignore
)
ev="$TMP/docs/test-results/2026-01-01_evidence.md"
rootres="$TMP/test-results/report.xml"
p3="$TMP/docs/test-results/phase3/summary.md"
mkdir -p "$TMP/docs/test-results/phase3" "$TMP/test-results"
touch "$ev" "$rootres" "$p3"
ok=true
( cd "$TMP" && git check-ignore -q "docs/test-results/2026-01-01_evidence.md" ) && ok=false
( cd "$TMP" && git check-ignore -q "test-results/report.xml" ) || ok=false
( cd "$TMP" && git check-ignore -q "docs/test-results/phase3/summary.md" ) || ok=false
if [ "$ok" = true ]; then
  pass "T4: evidence tracked; runner output + phase3 workdir ignored"
else
  fail_ "T4" "check-ignore semantics wrong: evidence_ignored=$(cd "$TMP" && git check-ignore -q 'docs/test-results/2026-01-01_evidence.md' && echo yes || echo no) rootres_ignored=$(cd "$TMP" && git check-ignore -q 'test-results/report.xml' && echo yes || echo no) phase3_ignored=$(cd "$TMP" && git check-ignore -q 'docs/test-results/phase3/summary.md' && echo yes || echo no)"
fi
rm -rf "$TMP"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
