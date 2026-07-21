#!/usr/bin/env bash
# tests/test-bl137-ci-tools-scope.sh — BL-137 (Dogfood-3 F-DF3-002, High):
# the phase-gate "Tools needed" arm must not block on a CI runner.
#
# WHY THIS EXISTS
#   The generated project's CI runs check-phase-gate.sh as its governance
#   job. The required-tools contract names DEV-WORKSTATION tools (Semgrep
#   CLI, Snyk CLI, Claude Code) that no CI runner carries — CI does SAST via
#   the semgrep container and never holds Snyk auth or an interactive
#   CLI. The arm's install PROMPTS already hard-N under $CI, but the
#   `issues+1` BLOCK had no CI awareness: every generated project shipped
#   with a permanently red governance check (the documented-but-impossible
#   class — Dogfood 3 proved it verbatim on a real repo while the identical
#   command exited 0 locally).
#
# THE CONTRACT (# BL-137-CI-TOOLS-SCOPE)
#   On a CI runner ($CI non-empty): the missing-tools LIST still prints
#   (visibility) + an explicit [note] that the contract binds on the dev
#   workstation — and the gate does NOT count it as an issue.
#   Locally (CI unset, TTY or not): the block is UNCHANGED — missing
#   required tools still fail the gate. Keyed STRICTLY on $CI, not on TTY:
#   scripted local runs must keep blocking.
#
# FIXTURE MECHANICS: check-phase-gate.sh resolves PROJECT_ROOT from its own
# location, so a fixture copy reads the FIXTURE's templates/tool-matrix —
# a one-tool mini-matrix makes the resolver fast and deterministic (no
# BL-134-class full-matrix walk). Baseline fixture = the proven rc=0
# phase-0 shape (phase-state + APPROVAL_LOG stub).
#
# REGISTRATION: no init.sh, not an aggregator → BOTH lists. Hermetic.
# bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq required (tool resolution + fixtures)"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# mk_proj <dir> <check_command> — phase-0 project whose mini-matrix carries
# ONE required tool; <check_command> decides whether it reads as installed
# ("true") or missing ("false").
mk_proj() {
  local d="$1" chk="$2"
  rm -rf "$d"
  mkdir -p "$d/.claude" "$d/scripts/lib" "$d/templates/tool-matrix"
  ( cd "$d" && git init -q && git config user.email t@t.invalid && git config user.name t \
      && echo x > seed && git add seed && git commit -q -m "chore: init" ) || return 1
  cat > "$d/.claude/phase-state.json" <<'JSON'
{"current_phase":0,"track":"standard","deployment":"personal","poc_mode":null,"gates":{}}
JSON
  printf '# Approval Log\n' > "$d/APPROVAL_LOG.md"
  cat > "$d/.claude/tool-preferences.json" <<'JSON'
{"context":{"dev_os":"darwin","platform":"web","language":"typescript","track":"standard"}}
JSON
  cat > "$d/templates/tool-matrix/common.json" <<EOF
{
  "tools": [
    {
      "name": "SentinelTool",
      "category": "Security",
      "description": "bl137 fixture tool",
      "check_command": "$chk",
      "required": true,
      "phase": 0,
      "auto_install": false,
      "instructions": "install SentinelTool"
    }
  ]
}
EOF
  cp "$REPO_ROOT/scripts/check-phase-gate.sh" "$d/scripts/"
  cp "$REPO_ROOT/scripts/resolve-tools.sh"    "$d/scripts/"
  cp "$REPO_ROOT/scripts/lib/"*.sh "$d/scripts/lib/"
  chmod +x "$d/scripts/check-phase-gate.sh" "$d/scripts/resolve-tools.sh"
}

run_gate() {  # run_gate <dir> [CI-value]
  local d="$1" ci="${2:-}"
  if [ -n "$ci" ]; then
    ( cd "$d" && env CI="$ci" bash scripts/check-phase-gate.sh </dev/null 2>&1 )
  else
    ( cd "$d" && env -u CI bash scripts/check-phase-gate.sh </dev/null 2>&1 )
  fi
}

# ── T1: locally (CI unset), a missing required tool BLOCKS (pin) ─────────────
echo "=== T1-local-missing-blocks ==="
P="$TOPTMP/p1"; mk_proj "$P" false
out=$(run_gate "$P"); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "SentinelTool"; then
  pass "T1-local-missing-blocks"
else
  fail_ "T1-local-missing-blocks" "rc=$rc — a missing REQUIRED tool must still block on the dev workstation (the arm's original, correct job): $(printf '%s' "$out" | grep -i tool | head -2 | tr '\n' ' ')"
fi

# ── T2: on a CI runner ($CI set), the SAME state must NOT block ──────────────
echo "=== T2-ci-informational ==="
P="$TOPTMP/p2"; mk_proj "$P" false
out=$(run_gate "$P" true); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "SentinelTool" && printf '%s' "$out" | grep -qi "BL-137"; then
  pass "T2-ci-informational (list still printed + note, no block)"
else
  fail_ "T2-ci-informational" "rc=$rc note=$(printf '%s' "$out" | grep -ci 'BL-137') — on a CI runner the governance job is STRUCTURALLY unpassable if this blocks (F-DF3-002); the list must stay visible and the note must name the scoping: $(printf '%s' "$out" | tail -3 | tr '\n' ' ')"
fi

# ── T3: CI set + tool PRESENT → clean pass, no note (arm not reached) ────────
echo "=== T3-ci-tools-present-clean ==="
P="$TOPTMP/p3"; mk_proj "$P" true
out=$(run_gate "$P" true); rc=$?
if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -qi "BL-137"; then
  pass "T3-ci-tools-present-clean"
else
  fail_ "T3-ci-tools-present-clean" "rc=$rc — with the tool installed the arm must not fire at all: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── T4: local + tool present → clean pass (baseline sanity) ──────────────────
echo "=== T4-local-tools-present-clean ==="
P="$TOPTMP/p4"; mk_proj "$P" true
out=$(run_gate "$P"); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T4-local-tools-present-clean"
else
  fail_ "T4-local-tools-present-clean" "rc=$rc — baseline fixture not clean; T1's block signal is unattributable: $(printf '%s' "$out" | tail -3 | tr '\n' ' ')"
fi

# ── T5: fence-excision mutant — the scoping fence is load-bearing ────────────
# Excising # BL-137-CI-TOOLS-SCOPE-BEGIN..END removes the CI branch AND the
# increment: the mutant must (a) no longer block LOCALLY on a missing tool
# (T1's protection gone — proves the increment lives inside the fence) and
# (b) print no BL-137 note under CI. Both asserted POSITIVELY on a
# lib-complete copy (the bl104 vacuous-mutant trap).
echo "=== T5-fence-excision-mutant ==="
P="$TOPTMP/p5"; mk_proj "$P" false
sed '/# BL-137-CI-TOOLS-SCOPE-BEGIN/,/# BL-137-CI-TOOLS-SCOPE-END/d' \
  "$REPO_ROOT/scripts/check-phase-gate.sh" > "$P/scripts/check-phase-gate.sh"
chmod +x "$P/scripts/check-phase-gate.sh"
if grep -q "BL-137-CI-TOOLS-SCOPE" "$P/scripts/check-phase-gate.sh"; then
  fail_ "T5-fence-excision-mutant" "excision left marker text — BEGIN/END malformed"
else
  out=$(run_gate "$P"); rc=$?
  out2=$(run_gate "$P" true); rc2=$?
  if [ "$rc" -eq 0 ] && [ "$rc2" -eq 0 ] && ! printf '%s' "$out2" | grep -qi "BL-137"; then
    pass "T5-fence-excision-mutant (guardless mutant neither blocks locally nor notes in CI — the fence carries both)"
  else
    fail_ "T5-fence-excision-mutant" "local rc=$rc ci rc=$rc2 — the excised mutant did not behave as fence-less; either the mutant crashed (vacuous) or logic lives outside the fence: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
