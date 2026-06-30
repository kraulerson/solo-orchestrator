#!/usr/bin/env bash
# tests/test-verify-install-fix-functions.sh
#
# Coverage for three S3 audit findings against scripts/verify-install.sh:
#
#   - code-verify-reconfigure-9  fix_claude_md emits a stub missing the
#                                pending-approval-sentinel bullet, deployment
#                                context, Build-Loop / persona / CDF guidance,
#                                and (for organizational deployments) the
#                                Branch Protection appendix that init.sh
#                                appends. The regenerated stub should be at
#                                template parity with init.sh:generate_claude_md.
#
#   - code-verify-reconfigure-11 check_hooks reports a green PASS when
#                                .claude/settings.json references a hook
#                                command but the on-disk script is deleted
#                                or non-executable. The hook will then fail
#                                at first PreToolUse invocation despite
#                                verify-install reporting "healthy". Behavior
#                                must be: settings reference + on-disk
#                                presence + +x bit are all required for PASS.
#
#   - code-verify-reconfigure-14 fix_tool_install passes resolver-supplied
#                                strings to `eval "$install_cmd" 2>/dev/null`.
#                                A compromised templates/tool-matrix/*.json or
#                                MITM resolver-output stream yields arbitrary
#                                code execution with operator privileges, and
#                                the 2>/dev/null mask hides the evidence.
#                                Fix: structured dispatch over a small allowlist
#                                of package-manager argv shapes (no `bash -c`
#                                on the structured path); deprecated string
#                                path retained for back-compat with an added
#                                metachar gate that REFUSES `; | ` ` $( < > \n`
#                                in the payload; never silence stderr.
#                                T11b covers the chained-injection bypass
#                                that motivated this rewrite.
#
# Test harness conventions match tests/test-verify-install-bl030-coverage.sh.
# Each test scenario is isolated in its own setup/teardown so failures in one
# scenario do not cascade into the others.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT="$REPO_ROOT/init.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

cd /tmp

setup_clean_project() {
  local deployment="${1:-personal}"
  TMP=$(mktemp -d); PROJ="$TMP/p"
  # init.sh REQUIRES --gov-mode when --deployment=organizational, and
  # baseline §2.5 forbids private_poc on organizational deployments
  # ("Private POC is always a personal deployment"). Use sponsored_poc
  # — the smallest set of side-effects on the organizational path —
  # and remember: the Branch Protection block is appended for ALL
  # organizational deployments regardless of gov_mode. (Bash 'set -u'
  # makes empty-array expansion unsafe, so we branch the invocation
  # rather than build an array.)
  if [ "$deployment" = "organizational" ]; then
    bash "$INIT" --non-interactive --project x --project-dir "$PROJ" --no-remote-creation \
      --platform web --language typescript --track light --deployment "$deployment" \
      --gov-mode sponsored_poc \
      >/dev/null 2>&1
  else
    bash "$INIT" --non-interactive --project x --project-dir "$PROJ" --no-remote-creation \
      --platform web --language typescript --track light --deployment "$deployment" \
      >/dev/null 2>&1
  fi
  VERIFY="$PROJ/scripts/verify-install.sh"
}
teardown() { rm -rf "$TMP"; }

run_verify_autofix() {
  ( cd "$PROJ" && bash "$VERIFY" --auto-fix 2>&1 ) || true
}

run_verify_check() {
  ( cd "$PROJ" && bash "$VERIFY" --check-only 2>&1 ) || true
}

# ============================================================
# code-verify-reconfigure-9 — fix_claude_md must produce a stub at
# template parity with init.sh:generate_claude_md.
# ============================================================

echo "T1: fix_claude_md regenerates CLAUDE.md with pending-approval-sentinel bullet"
setup_clean_project personal
rm -f "$PROJ/CLAUDE.md"
run_verify_autofix >/dev/null
if [ ! -f "$PROJ/CLAUDE.md" ]; then
  fail_ "T1" "verify-install did not regenerate CLAUDE.md"
elif ! grep -q "pending-approval sentinel" "$PROJ/CLAUDE.md"; then
  fail_ "T1" "regenerated CLAUDE.md missing the pending-approval-sentinel bullet"
else
  pass "T1: regenerated CLAUDE.md contains pending-approval-sentinel bullet"
fi
teardown

echo "T2: fix_claude_md substitutes project name + platform + track + language"
setup_clean_project personal
rm -f "$PROJ/CLAUDE.md"
run_verify_autofix >/dev/null
if [ ! -f "$PROJ/CLAUDE.md" ]; then
  fail_ "T2" "verify-install did not regenerate CLAUDE.md"
else
  missing=""
  grep -q "^- \*\*Project:\*\* x"               "$PROJ/CLAUDE.md" || missing="$missing project"
  grep -q "^- \*\*Platform:\*\* web"            "$PROJ/CLAUDE.md" || missing="$missing platform"
  grep -q "^- \*\*Track:\*\* light"             "$PROJ/CLAUDE.md" || missing="$missing track"
  grep -q "^- \*\*Primary Language:\*\* typescript" "$PROJ/CLAUDE.md" || missing="$missing language"
  if [ -n "$missing" ]; then
    fail_ "T2" "missing substituted identity fields:$missing"
  else
    pass "T2: identity fields substituted (project/platform/track/language)"
  fi
fi
teardown

echo "T3: fix_claude_md leaves no __PLACEHOLDER__ tokens in the regenerated file"
setup_clean_project personal
rm -f "$PROJ/CLAUDE.md"
run_verify_autofix >/dev/null
if grep -q '__[A-Z_]*__' "$PROJ/CLAUDE.md" 2>/dev/null; then
  fail_ "T3" "regenerated CLAUDE.md contains unsubstituted template tokens"
else
  pass "T3: no unsubstituted __TOKEN__ placeholders remain"
fi
teardown

echo "T4: organizational deployment appends Branch Protection block"
setup_clean_project organizational
rm -f "$PROJ/CLAUDE.md"
run_verify_autofix >/dev/null
if grep -q "Branch Protection" "$PROJ/CLAUDE.md" 2>/dev/null; then
  pass "T4: organizational Branch Protection block appended"
else
  fail_ "T4" "organizational regenerated CLAUDE.md missing Branch Protection block"
fi
teardown

echo "T5: fix_claude_md refuses to write CLAUDE.md (no half-write) when source template unavailable"
setup_clean_project personal
# Strip the orchestrator-source reference AND remove $HOME fallback paths by
# pointing source_dir at a non-existent directory, AND remove the in-project
# template copy so the self-bootstrap fallback also misses. The post-fix
# code path under test: fix_claude_md returns 1, leaves CLAUDE.md absent,
# and the failure surfaces as a register_fixable row (not a silently-empty
# success). Pre-fix code path on main: fix_claude_md ALWAYS writes a stub
# (the bash heredoc) regardless of template availability, so CLAUDE.md
# would exist after auto-fix. THIS is the distinguishing oracle the
# verifier asked for (replace the vacuous `__TOKEN__` check, which both
# pre- and post-fix code paths trivially satisfy).
rm -f "$PROJ/CLAUDE.md"
rm -f "$PROJ/templates/generated/claude-md.tmpl"
echo '{"source_dir": "/nonexistent/orchestrator/source"}' > "$PROJ/.claude/orchestrator-source.json"
# Also relocate $HOME for this invocation so the $HOME/.solo-orchestrator
# and $HOME/solo-orchestrator fallbacks don't resolve to the developer's
# real orchestrator clone.
FAKE_HOME=$(mktemp -d)
out=$( cd "$PROJ" && HOME="$FAKE_HOME" bash "$VERIFY" --auto-fix 2>&1 || true )
rm -rf "$FAKE_HOME"
t5_failed=""
if [ -f "$PROJ/CLAUDE.md" ]; then
  t5_failed="CLAUDE.md was written despite no canonical template available (this distinguishes the safe-refusal fix from main's heredoc stub which ALWAYS writes)"
fi
# A CLAUDE.md remediation row must surface in verify output so the
# operator knows what to fix. The pre-fix code on main writes the
# stub and registers a PASS, never emitting a CLAUDE.md fail line.
if ! echo "$out" | grep -qE "CLAUDE\.md.*(auto-fixable|missing|manual|REFUSED)"; then
  t5_failed="${t5_failed:+$t5_failed; }no CLAUDE.md remediation row registered in verify output"
fi
if [ -n "$t5_failed" ]; then
  fail_ "T5" "$t5_failed"
else
  pass "T5: safe-refusal — CLAUDE.md absent and remediation row registered"
fi
teardown

# ============================================================
# code-verify-reconfigure-11 — check_hooks must verify on-disk presence
# and executable bit of the hook scripts referenced in settings.json.
# ============================================================

# BL-037 closure (T6-T10): the pre-fix oracles were negative-only
# (`! grep -qE "[OK] <hook>"`). If verify-install.sh crashed before
# the hook-check section, or changed the [OK] label format, the
# absence-of-OK still satisfied the negation — T6-T10 silently PASSed.
# Mirror T5's tightened oracle: require a POSITIVE remediation row for
# the affected hook (via register_manual, which print_warn-emits the
# string `[WARN] <hook> ... (manual)`).
#
# verify-install.sh's _check_hooks_hook_pair (scripts/verify-install.sh:393)
# emits register_manual with one of:
#   "<label> registered but on-disk script missing (<path>)"
#   "<label> registered but on-disk script not executable (<path>)"
# All three patterns are valid remediation rows; we accept any of them.

# Convenience pattern: positive hook-remediation row for a given basename
# script. Mirrors T5's auto-fixable|missing|manual|REFUSED phrasing.
_hook_remediation_re='(missing|not executable|REFUSED|auto-fixable|registered but on-disk script)'

echo "T6: missing on-disk pre-commit-gate.sh is reported despite intact settings.json"
setup_clean_project personal
# Settings reference is intact; the on-disk file is gone.
rm -f "$PROJ/scripts/pre-commit-gate.sh"
out=$(run_verify_check)
t6_failed=""
# Negative: must not report green OK for the missing-script hook.
if echo "$out" | grep -qE "\[OK\] PreToolUse hook: pre-commit-gate\.sh"; then
  t6_failed="verify reported green OK for hook despite missing on-disk script"
fi
# Positive: must emit a [WARN] remediation row that names pre-commit-gate.sh
# and the (manual) suffix register_manual adds. This is the assertion
# that flips RED if verify-install crashes before hook-check runs.
if ! echo "$out" | grep -qE "\[WARN\].*pre-commit-gate\.sh.*${_hook_remediation_re}.*\(manual\)"; then
  t6_failed="${t6_failed:+$t6_failed; }no positive [WARN] (manual) remediation row for pre-commit-gate.sh"
fi
if [ -n "$t6_failed" ]; then
  fail_ "T6" "$t6_failed"
else
  pass "T6: missing pre-commit-gate.sh produces [WARN] (manual) remediation row AND no green OK"
fi
teardown

echo "T7: non-executable pre-commit-gate.sh on disk is reported"
setup_clean_project personal
chmod -x "$PROJ/scripts/pre-commit-gate.sh"
out=$(run_verify_check)
t7_failed=""
if echo "$out" | grep -qE "\[OK\] PreToolUse hook: pre-commit-gate\.sh"; then
  t7_failed="verify reported green OK for hook despite non-executable on-disk script"
fi
if ! echo "$out" | grep -qE "\[WARN\].*pre-commit-gate\.sh.*${_hook_remediation_re}.*\(manual\)"; then
  t7_failed="${t7_failed:+$t7_failed; }no positive [WARN] (manual) remediation row for non-executable pre-commit-gate.sh"
fi
if [ -n "$t7_failed" ]; then
  fail_ "T7" "$t7_failed"
else
  pass "T7: non-executable pre-commit-gate.sh produces [WARN] (manual) remediation row AND no green OK"
fi
teardown

echo "T8: missing on-disk track-tool-usage.sh is reported"
setup_clean_project personal
rm -f "$PROJ/scripts/track-tool-usage.sh"
out=$(run_verify_check)
t8_failed=""
if echo "$out" | grep -qE "\[OK\] PostToolUse hook: track-tool-usage\.sh"; then
  t8_failed="verify reported green OK for hook despite missing track-tool-usage.sh"
fi
if ! echo "$out" | grep -qE "\[WARN\].*track-tool-usage\.sh.*${_hook_remediation_re}.*\(manual\)"; then
  t8_failed="${t8_failed:+$t8_failed; }no positive [WARN] (manual) remediation row for track-tool-usage.sh"
fi
if [ -n "$t8_failed" ]; then
  fail_ "T8" "$t8_failed"
else
  pass "T8: missing track-tool-usage.sh produces [WARN] (manual) remediation row AND no green OK"
fi
teardown

echo "T9: missing on-disk session-version-check.sh is reported"
setup_clean_project personal
rm -f "$PROJ/scripts/session-version-check.sh"
out=$(run_verify_check)
# The SessionStart row covers two scripts together — both must be on disk.
# Per scripts/verify-install.sh:488, the WARN message format is
# "SessionStart hooks registered but on-disk scripts incomplete: <list>".
t9_failed=""
if echo "$out" | grep -qE "\[OK\] SessionStart hooks: version check \+ test gate"; then
  t9_failed="verify reported green OK for SessionStart hooks despite missing session-version-check.sh"
fi
if ! echo "$out" | grep -qE "\[WARN\].*SessionStart.*session-version-check\.sh.*(missing|not executable|incomplete).*\(manual\)"; then
  t9_failed="${t9_failed:+$t9_failed; }no positive [WARN] (manual) remediation row naming session-version-check.sh"
fi
if [ -n "$t9_failed" ]; then
  fail_ "T9" "$t9_failed"
else
  pass "T9: missing session-version-check.sh produces [WARN] (manual) SessionStart row AND no green OK"
fi
teardown

echo "T10: missing on-disk session-end-qdrant-reminder.sh is reported"
setup_clean_project personal
rm -f "$PROJ/scripts/session-end-qdrant-reminder.sh"
out=$(run_verify_check)
t10_failed=""
if echo "$out" | grep -qE "\[OK\] Stop hook: session-end-qdrant-reminder\.sh"; then
  t10_failed="verify reported green OK for Stop hook despite missing on-disk script"
fi
if ! echo "$out" | grep -qE "\[WARN\].*session-end-qdrant-reminder\.sh.*${_hook_remediation_re}.*\(manual\)"; then
  t10_failed="${t10_failed:+$t10_failed; }no positive [WARN] (manual) remediation row for session-end-qdrant-reminder.sh"
fi
if [ -n "$t10_failed" ]; then
  fail_ "T10" "$t10_failed"
else
  pass "T10: missing session-end-qdrant-reminder.sh produces [WARN] (manual) Stop-hook row AND no green OK"
fi
teardown

# ============================================================
# code-verify-reconfigure-14 — fix_tool_install must NOT pass
# JSON-supplied strings to eval. Allowed dispatch is over a small
# allowlist of package-manager argv shapes (brew, apt, dnf, pacman,
# npm, pip3, pipx, cargo). Anything else is refused, the command is
# echoed to stderr (visible), and no side-effect file is created.
# ============================================================

# Helper: extract just the fix_tool_install function (and its allowlist
# + head helper + structured-dispatch helpers) from scripts/verify-install.sh
# into a temp file, source it alongside the print_* helpers, then invoke
# fix_tool_install with the supplied RESOLVER_OUTPUT payload. This avoids
# the guard_not_in_framework / set -euo pipefail / autorun-main complexity
# of sourcing the whole verify script.
#
# Verifier major-2 follow-up (PR #92 review): the prior extractor keyed
# on `^_TOOL_INSTALL_ALLOWED_HEADS=\(` — a symbol that does NOT exist on
# `origin/main`. Against main, extraction yielded an empty file and the
# function was undefined, so T11 PASSED vacuously without exercising
# main's vulnerable `eval` at all. The new extractor uses a TWO-PASS
# strategy:
#
#   Pass 1 — try the post-fix anchor (`_TOOL_INSTALL_ALLOWED_HEADS=(`).
#   Pass 2 — if pass 1 produced nothing, fall back to extracting the
#            BARE `fix_tool_install() { ... }` body. This is what main's
#            verify-install.sh has — a function that calls `eval
#            "$install_cmd"` directly. Sourcing that body and invoking
#            it with a RESOLVER_OUTPUT containing `touch $MARKER` causes
#            the marker file to be created on main, RED-stating T11.
_invoke_fix_tool_install() {
  local payload="$1"
  local extract
  extract=$(mktemp)
  # Pass 1: post-fix anchor (allowlist + head helper + structured
  # dispatch helpers + fix_tool_install body).
  awk '
    /^_TOOL_INSTALL_ALLOWED_HEADS=\(/ {flag=1}
    flag {print}
    flag && /^fix_tool_install\(\) \{/ {f=1}
    f && /^\}$/ {print "# end-of-block"; flag=0; f=0; exit}
  ' "$PROJ/scripts/verify-install.sh" > "$extract"

  # Pass 2 fallback: bare `fix_tool_install() {` body (matches main).
  if [ ! -s "$extract" ] || ! grep -q '^fix_tool_install()' "$extract"; then
    awk '
      /^fix_tool_install\(\) \{/ {flag=1}
      flag {print}
      flag && /^\}$/ {print "# end-of-block"; flag=0; exit}
    ' "$PROJ/scripts/verify-install.sh" > "$extract"
  fi

  ( env _TEST_PAYLOAD="$payload" _EXTRACT="$extract" bash -c '
      set +e
      # Minimal print helpers (real script sources scripts/lib/helpers.sh).
      print_fail() { echo "[FAIL] $*"; }
      print_info() { echo "[INFO] $*"; }
      print_warn() { echo "[WARN] $*"; }
      source "$_EXTRACT"
      RESOLVER_OUTPUT="$_TEST_PAYLOAD"
      fix_tool_install 0
      printf "EXIT=%s\n" "$?"
    ' 2>&1 )
  rm -f "$extract"
}

echo "T11: fix_tool_install refuses non-allowlisted install_cmd (no RCE)"
setup_clean_project personal
MARKER="$TMP/PWNED_MARKER"
rm -f "$MARKER"
PAYLOAD=$(jq -n --arg cmd "touch $MARKER; echo COMPROMISED" '
  {auto_install:[{name:"PWN", category:"x", install_cmd:$cmd, required:false, description:"x"}],
   already_installed:[], manual_install:[], deferred:[]}')
_invoke_fix_tool_install "$PAYLOAD" >/dev/null 2>&1 || true
if [ -e "$MARKER" ]; then
  fail_ "T11" "fix_tool_install executed an attacker-controlled install_cmd (marker file was created)"
else
  pass "T11: fix_tool_install did NOT execute attacker-controlled install_cmd"
fi
rm -f "$MARKER"
teardown

# Verifier blocker-1 follow-up (PR #92 review): the verifier proved
# that PR #92's first cut could be bypassed by leading with an
# allowlisted head and chaining via `;`. The fix adds a structured
# dispatch path (Layer 1) and a metachar-rejecting legacy path
# (Layer 2) that REFUSES `;`, `|`, backtick, `$(`, `<`, `>`, newline.
# T11b targets the exact bypass repro from the review.
echo "T11b: fix_tool_install refuses chained-injection payload (brew --version; touch \$MARKER)"
setup_clean_project personal
MARKER="$TMP/PWNED_CHAIN_MARKER"
rm -f "$MARKER"
PAYLOAD=$(jq -n --arg cmd "brew --version; touch $MARKER" '
  {auto_install:[{name:"jq", category:"x", install_cmd:$cmd, required:false, description:"x"}],
   already_installed:[], manual_install:[], deferred:[]}')
out=$(_invoke_fix_tool_install "$PAYLOAD" 2>&1 || true)
if [ -e "$MARKER" ]; then
  fail_ "T11b" "chained-injection payload was executed (marker file was created) — metachar gate is missing or ineffective"
elif ! echo "$out" | grep -qiE "refus|disallow|reject|metachar"; then
  fail_ "T11b" "chained-injection payload neither executed nor refused with a visible reason (output: $out)"
else
  pass "T11b: chained-injection payload REFUSED with visible reason"
fi
rm -f "$MARKER"
teardown

echo "T12: fix_tool_install surfaces a visible refusal reason (no silent failure)"
setup_clean_project personal
MARKER="$TMP/PWNED2"
PAYLOAD=$(jq -n --arg cmd "touch $MARKER && echo OWNED" '
  {auto_install:[{name:"PWN", category:"x", install_cmd:$cmd, required:false, description:"x"}],
   already_installed:[], manual_install:[], deferred:[]}')
out=$(_invoke_fix_tool_install "$PAYLOAD")
if echo "$out" | grep -qiE "refus|disallow|reject|not allowed|unsupported|disallowed"; then
  pass "T12: refusal reason emitted to stderr"
else
  fail_ "T12" "no visible refusal reason (output: $out)"
fi
teardown

echo "T13: fix_tool_install allows a well-formed brew install command shape"
setup_clean_project personal
PAYLOAD=$(jq -n '
  {auto_install:[{name:"jq", category:"x", install_cmd:"brew install fake-pkg-name-that-does-not-exist-abcxyz", required:false, description:"x"}],
   already_installed:[], manual_install:[], deferred:[]}')
# Use a PATH-isolated subshell with a no-op `brew` shim so we can
# confirm the dispatcher ACCEPTED (not refused) the shape WITHOUT
# actually invoking the real Homebrew on the host. The shim wins
# because the temp dir is FIRST on PATH.
SHIM_DIR=$(mktemp -d)
cat > "$SHIM_DIR/brew" <<'SHIM'
#!/usr/bin/env bash
echo "SHIM_BREW_CALLED:$*"
exit 0
SHIM
chmod +x "$SHIM_DIR/brew"
out=$( PATH="$SHIM_DIR:$PATH" _invoke_fix_tool_install "$PAYLOAD" )
rm -rf "$SHIM_DIR"
if echo "$out" | grep -qiE "refus|disallow|reject|not allowed|unsupported|disallowed"; then
  fail_ "T13" "fix_tool_install refused a legitimate brew install command (output: $out)"
elif echo "$out" | grep -q "SHIM_BREW_CALLED"; then
  pass "T13: allowlisted brew install shape is accepted (shim invoked)"
else
  fail_ "T13" "neither refusal nor shim invocation observed (output: $out)"
fi
teardown

echo "T14: fix_tool_install echoes the resolved command to stderr before executing"
setup_clean_project personal
# Use a leading-allowlisted-but-unlikely-to-side-effect command: `echo`.
# After the fix, `echo` is in the allowlist; we verify the command echo
# itself appears in stderr (audit trail), regardless of execution outcome.
PAYLOAD=$(jq -n '
  {auto_install:[{name:"x", category:"x", install_cmd:"echo AUDIT-TRAIL-MARKER", required:false, description:"x"}],
   already_installed:[], manual_install:[], deferred:[]}')
out=$(_invoke_fix_tool_install "$PAYLOAD")
if echo "$out" | grep -q "AUDIT-TRAIL-MARKER"; then
  pass "T14: command echoed to stderr before execution"
else
  fail_ "T14" "no audit-trail echo of resolved command (output: $out)"
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
