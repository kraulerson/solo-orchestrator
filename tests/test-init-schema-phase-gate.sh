#!/usr/bin/env bash
# tests/test-init-schema-phase-gate.sh
#
# Regression: init.sh:2185-2186 (heredoc body written into
# .git/hooks/pre-commit) used the antipattern
#   CURRENT_PHASE=$(grep -o '"current_phase"...' \
#     "$PHASE_STATE" | grep -o '[0-9][0-9]*' || echo "0")
# spread over TWO lines. The cycle 5 single-line counter-sanitizer
# audit regex matched only same-line `cmd ... || echo "0"` captures,
# so this multiline pipeline was missed (PR #53 sister site).
#
# Bug class is identical to PR #53: when phase-state.json content is
# malformed or the inner grep matches zero times, the inner grep can
# print nothing and exit non-zero, the outer pipeline's `|| echo "0"`
# fires, and CURRENT_PHASE picks up "0". So far so good — but when
# the file contains a stray "current_phase" header without a numeric
# value, the first grep matches a line, the second grep emits an
# empty string (and exits non-zero), and `|| echo "0"` appends "0".
# Result: CURRENT_PHASE = "" or "\n0" or "0\n0" depending on shell.
# The subsequent `[ "$CURRENT_PHASE" -ge 2 ]` then errors with
# `integer expression expected` and (under set -e in the hook) the
# arithmetic test returns non-zero — flipping the gate into the
# wrong branch and silently bypassing the schema-migration warning.
#
# This is the SAME defect class PR #53 fixed in scripts/check-phase-gate.sh.
# The fix is identical: capture into the variable, then sanitize via
#   case "$CURRENT_PHASE" in ''|*[!0-9]*) CURRENT_PHASE=0 ;; esac
# on the line immediately after the capture (works for single- or
# multi-line pipelines).
#
# Test strategy: run init.sh ONCE to bootstrap a project (heavy step),
# then for each scenario rewrite .claude/phase-state.json and invoke
# the generated .git/hooks/pre-commit directly. Re-running the hook
# is fast — the heaviness is only in the one-time init.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SH="$REPO_ROOT/init.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# ─── One-time project bootstrap ─────────────────────────────────────
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PROJ="$TMP/proj"

echo "== tests/test-init-schema-phase-gate.sh =="
echo "Bootstrapping init.sh project (one-time setup; ~30-60s)..."

# cd to TMP so the framework-self-guard accepts the cwd.
( cd "$TMP" && "$INIT_SH" --non-interactive \
    --project test-schema-gate \
    --platform web \
    --deployment personal \
    --language typescript \
    --git-host github \
    --visibility private \
    --project-dir "$PROJ" \
    --no-remote-creation \
    >"$TMP/init.out" 2>"$TMP/init.err" ) || {
  echo "  [FATAL] init.sh bootstrap failed; rc=$?"
  echo "  stderr tail:"
  tail -20 "$TMP/init.err" | sed 's/^/    /'
  exit 1
}

HOOK="$PROJ/.git/hooks/pre-commit"
if [ ! -f "$HOOK" ]; then
  echo "  [FATAL] pre-commit hook not generated at $HOOK"
  exit 1
fi
if [ ! -x "$HOOK" ]; then
  echo "  [FATAL] pre-commit hook not executable: $HOOK"
  exit 1
fi
echo "  [setup OK] pre-commit hook generated"
echo ""

# ─── Helper: write phase-state.json then run the hook ──────────────
# Stages a benign no-op (an empty README diff) so the hook actually
# runs to completion — it short-circuits if there's nothing staged.
run_hook_with_phase_state() {
  local content="$1"
  printf '%s' "$content" > "$PROJ/.claude/phase-state.json"
  # Force a schema-shaped staged file so the [CURRENT_PHASE -ge 2]
  # branch is actually entered and exercised when the phase is 2+.
  ( cd "$PROJ" && {
      mkdir -p prisma
      echo "model X {}" > prisma/schema.prisma
      git add prisma/schema.prisma 2>/dev/null
    } )
  # Run the hook from the project root. Capture stdout+stderr.
  ( cd "$PROJ" && bash "$HOOK" 2>&1 )
  local rc=$?
  # Clean staged file so the next scenario starts fresh.
  ( cd "$PROJ" && git rm -f --cached prisma/schema.prisma >/dev/null 2>&1 || true
    rm -f prisma/schema.prisma )
  return $rc
}

# Hook may exit non-zero for other (unrelated) gitleaks/semgrep
# reasons; we only care about (a) the schema-migration WARN text and
# (b) the absence of 'integer expression expected' leakage.

# ─── T1: valid current_phase=0 → gate FALSE → no WARN ──────────────
echo "T1: valid current_phase=0 → schema gate FALSE → no schema WARN"
out=$(run_hook_with_phase_state '{"current_phase":0,"deployment":"personal"}' || true)
if echo "$out" | grep -q "Direct schema file changes detected"; then
  fail_ "T1" "schema WARN fired at phase 0 (should only fire at phase ≥ 2); out:\n$(echo "$out" | grep -i schema)"
elif echo "$out" | grep -q "integer expression expected"; then
  fail_ "T1" "'integer expression expected' leaked at phase 0; out:\n$(echo "$out" | grep -i integer)"
else
  pass "T1: phase 0 → schema-migration gate correctly skipped"
fi

# ─── T2: valid current_phase=2 → gate TRUE → WARN fires ────────────
echo "T2: valid current_phase=2 + staged prisma/schema.prisma → schema WARN fires"
out=$(run_hook_with_phase_state '{"current_phase":2,"deployment":"personal"}' || true)
if echo "$out" | grep -q "Direct schema file changes detected (Phase 2)"; then
  pass "T2: phase 2 → schema-migration WARN fires for staged prisma/schema.prisma"
elif echo "$out" | grep -q "integer expression expected"; then
  fail_ "T2" "'integer expression expected' leaked at phase 2; out:\n$(echo "$out" | grep -i integer)"
else
  fail_ "T2" "expected 'Direct schema file changes detected (Phase 2)'; out:\n$(echo "$out" | tail -30)"
fi

# ─── T3: MALFORMED phase-state.json → sanitized to 0, no leak ──────
# These three scenarios test the inner grep emitting nothing → outer
# `|| echo "0"` fires cleanly. These already pass pre-fix; they are
# regression guards that the sanitizer doesn't break the easy cases.

echo "T3a: phase-state.json with 'current_phase' header but NO digits → sanitize to 0, no leak"
malformed_a='{"current_phase":"abc","deployment":"personal"}'
out=$(run_hook_with_phase_state "$malformed_a" || true)
if echo "$out" | grep -q "integer expression expected"; then
  fail_ "T3a" "'integer expression expected' leaked; out:\n$(echo "$out" | grep -i integer)"
elif echo "$out" | grep -q "Direct schema file changes detected"; then
  fail_ "T3a" "schema WARN fired on garbage input (should sanitize to 0 → gate false); out:\n$(echo "$out" | grep -i schema)"
else
  pass "T3a: 'current_phase':'abc' → sanitized to 0, gate correctly skipped, no stderr leak"
fi

echo "T3b: phase-state.json with no current_phase field at all → sanitize to 0, no leak"
malformed_b='{"deployment":"personal","other":"data"}'
out=$(run_hook_with_phase_state "$malformed_b" || true)
if echo "$out" | grep -q "integer expression expected"; then
  fail_ "T3b" "'integer expression expected' leaked; out:\n$(echo "$out" | grep -i integer)"
elif echo "$out" | grep -q "Direct schema file changes detected"; then
  fail_ "T3b" "schema WARN fired on no-field input; out:\n$(echo "$out" | grep -i schema)"
else
  pass "T3b: missing current_phase → defaults to 0, gate skipped, no stderr leak"
fi

echo "T3c: phase-state.json is empty file → sanitize to 0, no leak"
out=$(run_hook_with_phase_state '' || true)
if echo "$out" | grep -q "integer expression expected"; then
  fail_ "T3c" "'integer expression expected' leaked; out:\n$(echo "$out" | grep -i integer)"
elif echo "$out" | grep -q "Direct schema file changes detected"; then
  fail_ "T3c" "schema WARN fired on empty input; out:\n$(echo "$out" | grep -i schema)"
else
  pass "T3c: empty phase-state.json → defaults to 0, gate skipped, no stderr leak"
fi

# ─── T3d/T3e: MULTI-MATCH — the actual exploit path ─────────────────
# When phase-state.json contains MORE than one "current_phase" key
# (e.g. hand-edited with a history block, or merged from two state
# files), the multi-line capture collects ALL of them — yielding
# CURRENT_PHASE = "2\n3" (or similar). Subsequent
# `[ "$CURRENT_PHASE" -ge 2 ]` errors with "integer expression
# expected" and (under `set -e` in the hook) returns non-zero —
# silently FLIPPING the gate into the wrong branch.
#
# Pre-fix these BOTH leak the bash error AND mis-route the gate.
# Post-fix the sanitizer collapses any non-numeric value to 0, so
# the gate consistently skips (safe-default), and the bash error
# never leaks. NB: the safer post-fix behavior is "skip the WARN
# rather than fire it on garbage" — a missed warning is recoverable;
# a leaked integer-expression-expected error is operator-confusing.

echo "T3d: duplicate current_phase keys (multi-match) → sanitize, no integer leak"
# Realistic scenario: phase-state.json with a `_history` sub-object
# that records prior `current_phase` values. Both keys match the
# outer regex; the inner grep emits "0\n2"; pre-fix the gate breaks.
multi_match_a='{"current_phase":0,"deployment":"personal","_history":{"current_phase":2}}'
out=$(run_hook_with_phase_state "$multi_match_a" || true)
if echo "$out" | grep -q "integer expression expected"; then
  fail_ "T3d" "'integer expression expected' leaked on multi-match input; out:\n$(echo "$out" | grep -i integer)"
else
  pass "T3d: duplicate current_phase keys → no 'integer expression expected' leak"
fi

echo "T3e: two current_phase keys both >=2 (multi-match) → sanitize, no integer leak"
# This is the 'silently bypass' case — the live current_phase is 2
# (gate SHOULD fire), but the multi-line capture produces "2\n3"
# which fails the integer test and (under set -e) flips to FALSE,
# silently bypassing the schema-migration warning.
multi_match_b='{"current_phase":2,"deployment":"personal","_history":{"current_phase":3}}'
out=$(run_hook_with_phase_state "$multi_match_b" || true)
if echo "$out" | grep -q "integer expression expected"; then
  fail_ "T3e" "'integer expression expected' leaked when current_phase=2 with history; out:\n$(echo "$out" | grep -i integer)"
else
  pass "T3e: current_phase=2 + history block → no 'integer expression expected' leak"
fi

# ─── T4: missing phase-state.json → CURRENT_PHASE stays default 0 ──
echo "T4: phase-state.json missing → CURRENT_PHASE defaults to 0, no leak"
rm -f "$PROJ/.claude/phase-state.json"
( cd "$PROJ" && {
    mkdir -p prisma
    echo "model X {}" > prisma/schema.prisma
    git add prisma/schema.prisma 2>/dev/null
  } )
out=$( cd "$PROJ" && bash "$HOOK" 2>&1 || true )
( cd "$PROJ" && git rm -f --cached prisma/schema.prisma >/dev/null 2>&1 || true
  rm -f prisma/schema.prisma )
if echo "$out" | grep -q "integer expression expected"; then
  fail_ "T4" "'integer expression expected' leaked when phase-state.json absent; out:\n$(echo "$out" | grep -i integer)"
elif echo "$out" | grep -q "Direct schema file changes detected"; then
  fail_ "T4" "schema WARN fired when phase-state.json absent (should default to 0); out:\n$(echo "$out" | grep -i schema)"
else
  pass "T4: missing phase-state.json → CURRENT_PHASE defaults to 0 cleanly"
fi

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
