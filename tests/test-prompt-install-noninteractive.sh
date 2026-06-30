#!/usr/bin/env bash
# tests/test-prompt-install-noninteractive.sh
#
# Regression test for the PR-#96 adversarial-verifier MAJOR finding:
#
#   scripts/lib/helpers.sh::prompt_install (line ~292) called
#     read -rp "Install $tool now? [Y/n]: " response
#     [[ "$response" =~ ^[Nn] ]] && return 1
#     eval "$install_cmd"
#
#   With no `[ -t 0 ]` / `${CI:-}` / `${SOIF_NONINTERACTIVE:-}`
#   short-circuit, an EOF / piped-stdin invocation caused `read` to
#   return nonzero with `response=""`, the regex check evaluated
#   false, and `eval "$install_cmd"` fired UNATTENDED. prompt_install
#   is invoked from 16 sites in init.sh for `sudo apt install ...`,
#   Docker daemon install (`usermod -aG docker $USER`), etc. — i.e.
#   precisely the auto-Y'd side-effectful actions the PR-#96 contract
#   is supposed to prevent.
#
#   The `scripts/lint-raw-read-prompt.sh` lint cannot catch this
#   because helpers.sh is the only file EXEMPT from that lint (the
#   prompt helpers themselves must call `read -rp`). That makes a
#   runtime regression test (this file) the only safety net.
#
# Expected behavior after the fix:
#   prompt_install MUST short-circuit and return 1 (decline install,
#   do NOT call `eval`) whenever ANY of:
#     - stdin is not a TTY (`! [ -t 0 ]`)
#     - $CI is set to a non-empty value
#     - $SOIF_NONINTERACTIVE is set to a non-empty value
#
# Verification strategy:
#   Source helpers.sh in a harness, mock `eval` as a function that
#   creates a marker file when called, invoke prompt_install with a
#   destructive-looking command, then assert (a) the marker is ABSENT
#   and (b) prompt_install returned nonzero. The marker mechanism
#   means T1/T2/T3 RED on PR-#96 HEAD (current bug fires `eval`,
#   creating the marker) and GREEN after the fix (short-circuit
#   returns 1, eval untouched).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPERS="$REPO_ROOT/scripts/lib/helpers.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Build a harness script that:
#   1. Sources scripts/lib/helpers.sh.
#   2. Overrides `eval` so that ANY call creates $MARKER (proving the
#      install command would have fired).
#   3. Calls prompt_install with a destructive-looking command.
#   4. Exits with prompt_install's rc.
#
# Args: $1 = marker path, $2 = harness path.
build_harness() {
  local marker="$1" harness="$2"
  cat > "$harness" <<HARNESS
#!/usr/bin/env bash
set -uo pipefail
# Disable color escapes so output is greppable.
YELLOW=""; BOLD=""; NC=""; CYAN=""; GREEN=""; RED=""; BLUE=""
# Source the real helpers.
source "$HELPERS"
# BL-037 closure: before sourcing helpers.sh, the prompt_install
# invocation below would resolve to "command not found" (bash rc=127)
# if helpers.sh (a) silently failed to source or (b) ever drops the
# prompt_install function definition. The pre-fix oracle asserted
# rc != 0 only, which silently accepted 127 as the "decline" code —
# meaning a regression that removed prompt_install entirely PASSed
# T1/T2/T3 vacuously. Guard with a hard precondition: prompt_install
# MUST be defined as a function in the sourced helpers.sh.
# Note: this comment intentionally avoids backticks because the heredoc
# is unquoted (<<HARNESS) and bash would treat \`...\` as command
# substitution during expansion, executing the wrapped tokens.
if ! type prompt_install 2>/dev/null | grep -qE '^prompt_install is a function'; then
  echo "HARNESS_PRECONDITION_FAIL: prompt_install is not a function after sourcing helpers.sh — exit 99 (this rules out the bash 127 case the pre-fix oracle accepted as success)"
  exit 99
fi
# Replace eval with a function stub that records the install attempt.
# Bash resolves user-defined functions before builtins, so this stub
# takes precedence inside prompt_install's body. We CANNOT use
# command substitution to capture args without re-entering eval —
# just touch the marker and return success so the calling logic
# proceeds as if install succeeded (irrelevant to the assertion).
eval() {
  touch "$marker"
  return 0
}
prompt_install "TestTool" "rm -rf /nonexistent-test-target"
rc=\$?
exit "\$rc"
HARNESS
  chmod +x "$harness"
}

# Run the harness with a bounded timeout, stdin redirected per kind,
# and the supplied env_prefix exported. Records pass/fail by examining
# (rc, marker presence) — only when the harness short-circuits (no
# marker AND rc=1) is the test considered PASS.
#
# Args:
#   $1 = test name (T1/T2/T3)
#   $2 = env prefix (e.g. "CI=true" or "")
#   $3 = stdin kind: "closed" (</dev/null) | "piped" (empty file)
run_t() {
  local name="$1" env_prefix="$2" stdin_kind="$3"
  local TMP MARKER HARNESS OUT rc
  TMP=$(mktemp -d)
  MARKER="$TMP/install-fired"
  HARNESS="$TMP/harness.sh"
  OUT="$TMP/out.log"
  build_harness "$MARKER" "$HARNESS"

  local INFILE="/dev/null"
  if [ "$stdin_kind" = "piped" ]; then
    INFILE="$TMP/in"
    : > "$INFILE"
  fi

  # Inline bounded-time runner. macOS lacks GNU `timeout(1)`; emulate
  # via background-PID polling. Same pattern as
  # tests/test-check-phase-gate-noninteractive.sh::run_bounded.
  ( env $env_prefix bash "$HARNESS" <"$INFILE" >"$OUT" 2>&1 ) &
  local pid=$! deadline=$(( $(date +%s) + 15 ))
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      fail_ "$name" "harness hung past 15s — prompt_install blocked on read instead of short-circuiting"
      rm -rf "$TMP"
      return
    fi
    sleep 1
  done
  wait "$pid"; rc=$?

  local failed=false
  if [ -e "$MARKER" ]; then
    fail_ "$name" "install command fired (marker exists) — eval was reached despite non-interactive context"
    failed=true
  fi
  # BL-037 closure: tighten `rc != 0` (which silently accepted bash's
  # 127 "command not found" — the exact failure mode of a regression
  # that removed prompt_install entirely) to `rc == 1` — the documented
  # decline-install return code. Combined with the harness's
  # type-check (which would have exit-99'd before reaching this assert
  # if prompt_install was undefined), this gives us a precise refusal
  # contract: function exists, was invoked, and returned the
  # documented decline rc.
  if [ "$rc" = "99" ]; then
    fail_ "$name" "harness precondition failed (prompt_install not defined in helpers.sh) — see HARNESS_PRECONDITION_FAIL line in $OUT"
    failed=true
  fi
  if [ "$rc" != "1" ]; then
    fail_ "$name" "prompt_install rc=$rc; required rc==1 (documented decline-install return code). rc=0 means install ran; rc=127 means function missing; any other rc means an unrelated failure path."
    failed=true
  fi
  if [ "$failed" = "false" ]; then
    pass "$name: prompt_install short-circuited cleanly (function defined, rc=1 decline, no marker, no hang)"
  fi
  rm -rf "$TMP"
}

# ---------------------------------------------------------------------
# T1: CI=true + piped stdin → MUST refuse install (no eval).
# ---------------------------------------------------------------------
echo "T1: CI=true + piped (non-TTY) stdin — prompt_install MUST refuse install"
run_t "T1" "CI=true" "piped"

# ---------------------------------------------------------------------
# T2: stdin closed (EOF, ! -t 0) → MUST refuse install (no eval).
# ---------------------------------------------------------------------
echo "T2: stdin closed (EOF, ! -t 0) — prompt_install MUST refuse install"
run_t "T2" "" "closed"

# ---------------------------------------------------------------------
# T3: SOIF_NONINTERACTIVE=1 → MUST refuse install (no eval).
# ---------------------------------------------------------------------
echo "T3: SOIF_NONINTERACTIVE=1 — prompt_install MUST refuse install"
run_t "T3" "SOIF_NONINTERACTIVE=1" "piped"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
