#!/usr/bin/env bash
# tests/test-process-checklist-reset-phase1.sh — code-process-checklist-3.
#
# reset_process must accept every key that get_steps_for_process accepts
# (including phase1_architecture). reset_all's template must seed every
# such key. ensure_state_file's initial template must do the same. An
# invariant self-test (--invariant-check) confirms this consistency to
# prevent recurrence: adding a new phase to PHASE*_STEPS without wiring
# reset/template support will trip the check.
#
# Note on reset_process tests (T1/T2): reset_process / reset_all gate on
# `[ -t 0 ]` AND prompt_yes_no, both of which refuse in non-interactive
# contexts. We assert the case arm exists via grep on the script and via
# the invariant-check tool. End-to-end reset behaviour is covered by the
# invariant-check (T4) — if the case were missing it would flag a gap.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/process-checklist.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup_project() {
  TMP=$(mktemp -d)
  (
    cd "$TMP"
    git init -q
    git config user.email "test@test.local"
    git config user.name "test"
    mkdir -p .claude
    cat > .claude/phase-state.json <<'JSON'
{"current_phase":1,"track":"light","deployment":"personal","phases":{}}
JSON
  )
}
teardown_project() { rm -rf "$TMP"; }

# T1: --reset phase1_architecture is no longer "Unknown process". The
# non-interactive TTY guard stops us with a different error, so we
# assert the "Unknown process" message is ABSENT from stderr. Pre-fix,
# the * arm fired before the TTY guard? No — the TTY guard fires first
# (lines 999-1004), and the case statement is unreachable from
# non-interactive callers. So we instead assert via script grep that
# the case arm is present. This is structural; T4 is the behavioural
# guarantee.
echo "T1: case arm 'phase1_architecture)' present in reset_process"
# Find the reset_process function body and check for the case arm.
if awk '/^reset_process\(\)/,/^}/' "$SCRIPT" | grep -qE '^[[:space:]]*phase1_architecture\)'; then
  pass "T1: reset_process has phase1_architecture) arm"
else
  fail_ "T1" "reset_process body does not contain a 'phase1_architecture)' case arm"
fi

# T2: reset_all template seeds phase1_architecture. Same TTY-guard
# reason: assert via script grep that the heredoc contains the key.
echo "T2: reset_all template seeds phase1_architecture"
if awk '/^reset_all\(\)/,/^}/' "$SCRIPT" | grep -q '"phase1_architecture"'; then
  pass "T2: reset_all heredoc includes \"phase1_architecture\""
else
  fail_ "T2" "reset_all heredoc missing \"phase1_architecture\" key"
fi

# T3: ensure_state_file initial template seeds phase1_architecture.
# Trigger ensure_state_file via --status with no pre-existing state.
echo "T3: ensure_state_file initial template seeds phase1_architecture"
setup_project
out=$(cd "$TMP" && "$SCRIPT" --status 2>&1) || true
if [ ! -f "$TMP/.claude/process-state.json" ]; then
  fail_ "T3" "ensure_state_file did not create the file: $out"
else
  has=$(jq 'has("phase1_architecture")' "$TMP/.claude/process-state.json")
  if [ "$has" = "true" ]; then
    pass "T3: ensure_state_file initial template includes phase1_architecture"
  else
    fail_ "T3" "phase1_architecture key absent from initial template"
  fi
fi
teardown_project

# T4: invariant self-test. --invariant-check prints OK and exits 0 when
# every key in get_steps_for_process has a matching reset_process case
# arm AND is seeded in both ensure_state_file and reset_all templates.
# Fails (rc=1) if any gap.
echo "T4: --invariant-check passes on healthy script"
out=$("$SCRIPT" --invariant-check 2>&1) ; rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "invariant-check: all processes wired"; then
  pass "T4: invariant-check passes (every process has reset arm + template entry)"
else
  fail_ "T4" "rc=$rc out=$out"
fi

# T5: invariant self-test detects a missing reset arm. We copy the
# entire scripts/ tree to a tmpdir, surgically delete the
# phase1_architecture arm from reset_process in the copy, run
# --invariant-check on the copy, and confirm it fails with a
# phase1_architecture-specific gap message. The full scripts/ copy is
# needed because invariant_check is invoked via SCRIPT_DIR-relative
# helpers.sh sourcing.
echo "T5: --invariant-check detects a missing reset arm"
TMPDIR_T5=$(mktemp -d)
cp -R "$REPO_ROOT/scripts" "$TMPDIR_T5/scripts"
TMPSCRIPT="$TMPDIR_T5/scripts/process-checklist.sh"
python3 - "$TMPSCRIPT" <<'PY'
import sys, re
path = sys.argv[1]
s = open(path).read()
m = re.search(r"reset_process\(\) \{.*?\n\}\n", s, re.DOTALL)
assert m, "could not locate reset_process body"
body = m.group(0)
# Remove the phase1_architecture case arm. The arm spans:
#   "    phase1_architecture)\n"
#   "      jq '...' ... && mv ...\n"
#   "      ;;\n"
new_body = re.sub(
    r"\n[ \t]+phase1_architecture\)\n[ \t]+jq[^\n]*\n[ \t]+'[^']*'[^\n]*\n[ \t]+;;\n",
    "\n",
    body,
    count=1,
)
if new_body == body:
    # Fallback: simpler multi-line strip.
    new_body = re.sub(
        r"\n[ \t]+phase1_architecture\)\n(?:[ \t]+[^\n]*\n)+?[ \t]+;;\n",
        "\n",
        body,
        count=1,
    )
assert new_body != body, "phase1_architecture arm not found / not removed"
open(path, 'w').write(s.replace(body, new_body))
PY
chmod +x "$TMPSCRIPT"
out=$("$TMPSCRIPT" --invariant-check 2>&1) ; rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q "phase1_architecture"; then
  pass "T5: invariant-check fails (rc=$rc) and names the missing arm"
else
  fail_ "T5" "expected non-zero rc citing phase1_architecture, got rc=$rc out=$out"
fi
rm -rf "$TMPDIR_T5"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
