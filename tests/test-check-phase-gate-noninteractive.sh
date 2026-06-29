#!/usr/bin/env bash
# tests/test-check-phase-gate-noninteractive.sh
#
# Regression tests for code-check-gates-7 (audit v2 S3):
#   scripts/check-phase-gate.sh contains two `read -rp` prompts:
#     :549 — "Install now? [Y/n]"
#     :573 — "Start Qdrant container and register MCP? [Y/n]"
#   In CI / non-TTY contexts, `read` reads EOF → empty string →
#   `[[ ! "" =~ ^[Nn] ]]` is TRUE → the script proceeds to `eval`
#   auto-install commands. The script header (lines 8-9) advertises
#   CI use and baseline §5 invariant #6 confirms it runs unattended.
#
# Fix: wrap both prompts with a `prompt_yes_no` helper that returns
# the default ("N" — do not install) when stdin is not a TTY, or when
# CI / SOIF_NONINTERACTIVE env vars are set. Print a [WARN] block
# listing the missing tools instead of prompting.
#
# This test invokes check-phase-gate.sh with stdin closed and CI=true
# against a fixture that would otherwise trigger the install prompt,
# and asserts (a) the script exits cleanly without hanging,
# (b) no `eval` of install commands fires, (c) a [WARN] block is
# emitted naming the missing tool(s).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-phase-gate.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# ---------------------------------------------------------------------
# T1: source-level check — both `read -rp` sites are gated by a
# non-interactive guard. The acceptable shapes are:
#   - direct `[ -t 0 ]` / `${CI:-}` / `${SOIF_NONINTERACTIVE:-}` guard
#     immediately wrapping the prompt, OR
#   - a `prompt_yes_no` (or similarly named) helper used in place of
#     `read -rp`.
# ---------------------------------------------------------------------
echo "T1: both read -rp prompts are guarded against non-interactive contexts"
read_count=$(grep -cE '^[[:space:]]*read -rp' "$SCRIPT" || true)
case "$read_count" in ''|*[!0-9]*) read_count=0 ;; esac

if [ "$read_count" -eq 0 ]; then
  # No raw `read -rp` lines at all — must be routed through a helper.
  if grep -qE 'prompt_yes_no|prompt_interactive|prompt_or_default' "$SCRIPT"; then
    pass "T1: no raw 'read -rp' lines — routed through a helper"
  else
    fail_ "T1" "no read -rp and no prompt helper detected"
  fi
else
  # Each raw read -rp must be inside an `if` block that references
  # `-t 0`, `CI`, or `SOIF_NONINTERACTIVE` somewhere in the file's
  # surrounding 10 lines.
  guarded=true
  while IFS=: read -r lineno _; do
    start=$((lineno - 10)); [ "$start" -lt 1 ] && start=1
    end=$((lineno + 2))
    region=$(awk "NR>=${start} && NR<=${end}" "$SCRIPT")
    if ! echo "$region" | grep -qE '\[ -t 0 \]|\$\{CI:-\}|\$\{SOIF_NONINTERACTIVE:-\}'; then
      guarded=false
      echo "    line $lineno: no TTY/CI guard in surrounding region"
    fi
  done < <(grep -nE '^[[:space:]]*read -rp' "$SCRIPT")
  if [ "$guarded" = "true" ]; then
    pass "T1: all raw read -rp sites have nearby TTY/CI guards"
  else
    fail_ "T1" "at least one read -rp lacks a TTY/CI guard"
  fi
fi

# ---------------------------------------------------------------------
# Portable bounded-time runner. The cycle-7 PR-#87 verifier flagged
# the previous T2 for invoking `timeout 20` directly — macOS does not
# ship coreutils' `timeout(1)` by default, so the command vanished into
# rc=127 / elapsed=0s and the test PASSED vacuously on every Darwin
# runner. This helper backgrounds the command and kills it after
# $1 seconds; rc=124 signals the timeout fired (matches GNU `timeout`).
run_bounded() {
  local secs="$1"; shift
  local outfile="$1"; shift
  local pid deadline rc
  ( "$@" ) >"$outfile" 2>&1 </dev/null &
  pid=$!
  deadline=$(( $(date +%s) + secs ))
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
  done
  wait "$pid"; rc=$?
  return "$rc"
}

# ---------------------------------------------------------------------
# T2: drive the exact `prompt_yes_no … && eval install_command`
# interaction surfaced by the cycle-7 PR-#87 verifier. Sourcing the
# helper from check-phase-gate.sh (rather than reconstructing it) means
# this test breaks the moment a future edit re-introduces the
# "supplied default honored in CI" bug. Asserts (a) bounded runtime,
# (b) MARKER_FILE does NOT exist (so `eval "$cmd"` did not fire), and
# (c) a [WARN] line was printed.
# ---------------------------------------------------------------------
echo "T2: CI=true reaches install branch — eval is NOT invoked"
TMP=$(mktemp -d)
MARKER="$TMP/install-fired"
OUTFILE="$TMP/out.log"
HELPER="$TMP/prompt_yes_no.sh"
HARNESS="$TMP/harness.sh"

# Pre-extract the prompt_yes_no helper from the live script into a
# standalone file (process-substitution + heredoc-quoting interact
# poorly with `set -u` on macOS bash 3.2, so we use a plain file).
# Slicing the live script (rather than re-implementing the helper)
# means this test FAILS the moment a future edit re-introduces the
# "supplied default honored in CI" bug — true regression coverage.
awk '/^prompt_yes_no\(\) \{/,/^\}/' "$SCRIPT" > "$HELPER"
if ! grep -q 'prompt_yes_no()' "$HELPER"; then
  fail_ "T2" "could not extract prompt_yes_no helper from $SCRIPT (awk slice empty)"
  rm -rf "$TMP"
else
  # Exercise the exact call shape used at scripts/check-phase-gate.sh:743
  # / :769 — `prompt_yes_no "..." Y` followed by `eval "$cmd"`. The fix
  # returns 1 in CI regardless of the supplied default; a regression
  # returns 0 and fires `$cmd`, creating $MARKER.
  cat > "$HARNESS" <<HARNESS
#!/usr/bin/env bash
set -uo pipefail
YELLOW=""; BOLD=""; NC=""
source "$HELPER"
cmd="touch '$MARKER'"
if prompt_yes_no "Install now? [Y/n]" Y; then
  eval "\$cmd"
fi
exit 0
HARNESS
  chmod +x "$HARNESS"

  # Run under CI=true + stdin closed with a portable bounded-time guard.
  start=$(date +%s)
  CI=true run_bounded 20 "$OUTFILE" bash "$HARNESS"
  rc=$?
  end=$(date +%s)
  elapsed=$((end - start))

  t2_failed=false
  if [ "$rc" = "124" ]; then
    fail_ "T2" "harness hung past 20s under CI=true + stdin closed"
    t2_failed=true
  fi
  if [ -e "$MARKER" ]; then
    fail_ "T2" "install command fired despite CI=true — prompt_yes_no honored the supplied 'Y' default (regression of PR-#87 verifier blocker #1)"
    t2_failed=true
  fi
  if ! grep -qE 'WARN.*[Nn]on-interactive|WARN.*skip' "$OUTFILE" 2>/dev/null; then
    fail_ "T2" "harness produced no [WARN] line — prompt_yes_no did not announce the skip"
    t2_failed=true
  fi
  if [ "$t2_failed" = "false" ]; then
    pass "T2: install branch reached, eval suppressed, WARN emitted (${elapsed}s, rc=$rc)"
  fi
  rm -rf "$TMP"
fi

# ---------------------------------------------------------------------
# T3: the install-now block, when reached non-interactively, must
# emit a [WARN] line referencing manual install (not silently skip).
# We check this at source level since wiring an end-to-end resolver
# hit is brittle.
# ---------------------------------------------------------------------
echo "T3: non-interactive branch emits a WARN explaining the skip"
if grep -qE 'WARN.*[Nn]on-interactive|WARN.*skip.*install' "$SCRIPT"; then
  pass "T3: non-interactive WARN message present in script"
else
  fail_ "T3" "no non-interactive WARN message found in $SCRIPT"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
