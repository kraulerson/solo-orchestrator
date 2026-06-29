#!/usr/bin/env bash
# tests/test-tier-crosscheck-6-followup-atomicity-and-jq.sh
#
# Regression suite for the PR #105 adversarial-verifier follow-up. Two
# defects the verifier surfaced that the original suite did not catch:
#
#   F1 (atomicity) — scripts/reconfigure-project.sh's
#       data_classification|zdr_attested|zdr_attestation_reason handler
#       claimed to install an INT/TERM/ERR trap and subshell-wrap the
#       mutation block but did neither. A SIGINT arriving between the
#       process-state.json rewrite and the APPROVAL_LOG.md append left
#       process-state.json mutated, the audit row missing, and the
#       snapshot tempdir leaked. F1 mirrors PR #57's `finalize_and_commit`
#       crash-safety contract on the same script.
#
#   F2 (silent jq failure) — scripts/intake-wizard.sh's --data-classification
#       / --zdr-attested non-interactive path AND persist_phase1_artifacts()
#       did `jq ... > tmp && mv tmp pstate` followed by an unconditional
#       success line + exit 0, regardless of whether jq+mv succeeded.
#       Feeding a malformed process-state.json reproduced: jq prints a
#       parse error to stderr, success message prints to stdout, file is
#       unchanged, operator is told the write succeeded.
#
# Both fixtures construct minimal project scaffolds, exercise the
# defective code path, and assert the post-fix invariants.

set -u
[[ "${BASH_VERSION:-}" ]] || { echo "bash required"; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --------------------------------------------------------------------
# Test scaffolding (mirrors the style of test-tier-crosscheck-6-zdr-gate.sh)
# --------------------------------------------------------------------
PASS=0
FAIL=0
FAILED_TESTS=()

pass() { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
fail_() {
  echo "  [FAIL] $1"
  echo "        $2"
  FAIL=$((FAIL + 1))
  FAILED_TESTS+=("$1")
}

# Always restore PATH between cases so the mv-shim from F1 doesn't bleed
# into subsequent fixtures.
ORIG_PATH="$PATH"

# ════════════════════════════════════════════════════════════════════
# F1: Signal mid-mutation in reconfigure-project.sh leaves NO torn state.
#
# Strategy: shim `mv` so that immediately AFTER the mv that commits
# process-state.json into place we send a SIGTERM to the script-bash
# parent. The mv shim then sleeps briefly so the signal has time to
# deliver before mv exits 0 (which would let the script continue to the
# APPROVAL_LOG append). SIGTERM rather than SIGINT because non-
# interactive bash absorbs externally-delivered SIGINT but exits on
# SIGTERM (and SIGTERM is part of the trap contract the PR body claims:
# INT/TERM/ERR). The atomicity defect is signal-class-agnostic.
#
# Verified RED on PR head (44ee984): pstate mutated, APPROVAL_LOG
# unchanged, snapshot dir leaked.
#
# Assertions on GREEN:
#   * process-state.json is byte-identical to the pre-mutation snapshot
#   * APPROVAL_LOG.md is byte-identical to the pre-mutation snapshot
#     (or both files mutated — strict atomicity)
#   * exit code is non-zero
# A torn state (post-fix violation) is pstate mutated AND approval not.
# ════════════════════════════════════════════════════════════════════
echo ""
echo "F1: signal mid-mutation in reconfigure-project.sh produces no torn state"
T1=$(mktemp -d); P1="$T1/p"

# Build minimal project that reconfigure-project.sh can operate on.
mkdir -p "$P1/.claude" "$P1/scripts/lib" "$T1/bin"
cp "$REPO_ROOT/scripts/reconfigure-project.sh" "$P1/scripts/reconfigure-project.sh"
cp "$REPO_ROOT/scripts/lib/helpers.sh" "$P1/scripts/lib/helpers.sh"
[ -f "$REPO_ROOT/scripts/lib/enforcement-level.sh" ] && cp "$REPO_ROOT/scripts/lib/enforcement-level.sh" "$P1/scripts/lib/enforcement-level.sh"

cat > "$P1/.claude/phase-state.json" <<'JSON'
{"project":"t","framework_version":"1.0","current_phase":1,"track":"light","deployment":"personal","poc_mode":null}
JSON
cat > "$P1/.claude/tool-preferences.json" <<'JSON'
{"context":{"project":"t","platform":"web","language":"javascript","track":"light"}}
JSON
cat > "$P1/.claude/orchestrator-source.json" <<JSON
{ "source_dir": "$REPO_ROOT" }
JSON
cat > "$P1/.claude/process-state.json" <<'JSON'
{"phase1_artifacts":{"existing":"value"}}
JSON
echo "# t — Operator Brief" > "$P1/CLAUDE.md"
echo "# Project Intake — t" > "$P1/PROJECT_INTAKE.md"
cat > "$P1/APPROVAL_LOG.md" <<'MD'
---
project: t
deployment: personal
---

# Approval Log — t

## Approval History
| Date | Gate / Event | Approver | Role | Decision | Reference |
|---|---|---|---|---|---|
MD

( cd "$P1" \
    && git init -q \
    && git config user.email t@t.l \
    && git config user.name t \
    && git add -A \
    && git commit -q -m "fixture" ) >/dev/null 2>&1

# Snapshot pre-state for byte-comparison after the signal.
cp "$P1/.claude/process-state.json" "$T1/pstate.pre"
cp "$P1/APPROVAL_LOG.md" "$T1/approval.pre"

# Shim `mv` to inject a signal into the script-bash parent right after
# committing the process-state.json move but before the script returns
# control to its caller — which would otherwise immediately append to
# APPROVAL_LOG.md.
#
# Sending the signal from *inside* the script's own process tree
# matters: bash absorbs SIGINT delivered from outside in non-interactive
# mode, but SIGTERM kills it regardless. The atomicity contract claims
# INT/TERM/ERR, so SIGTERM is a valid driver for the same trap path.
cat > "$T1/bin/mv" <<SHIM
#!/usr/bin/env bash
# Find the real mv (PATH was prepended for the shim).
real_mv=""
for cand in /bin/mv /usr/bin/mv; do
  if [ -x "\$cand" ]; then real_mv="\$cand"; break; fi
done
[ -z "\$real_mv" ] && { echo "shim: cannot find real mv" >&2; exit 1; }

"\$real_mv" "\$@"
rc=\$?

# Only wedge the SPECIFIC mv that commits process-state.json. Last
# argument is the destination — match the path tail.
dest="\${@: -1}"
if [[ "\$dest" == *".claude/process-state.json" ]] && [ "\$rc" -eq 0 ]; then
  : > "$T1/mv-done"
  # Signal the script-bash parent. PPID is the bash process that ran
  # the script via \`bash scripts/reconfigure-project.sh ...\`.
  kill -TERM \$PPID 2>/dev/null || true
  # Give the signal time to deliver before mv exits and the script
  # would otherwise resume execution.
  sleep 0.3
fi
exit \$rc
SHIM
chmod +x "$T1/bin/mv"

F1_LOG="$T1/f1.log"
# Run synchronously — the shim handles the wedge. Use `exec` inside the
# subshell so PPID inside the shim maps cleanly to the script-bash.
# `set +m` and the explicit redirect suppress bash's "Terminated: 15"
# job-control message that would otherwise leak to our stderr when the
# subshell dies from SIGTERM.
set +m
{
  ( cd "$P1" && PATH="$T1/bin:$ORIG_PATH" exec bash "$P1/scripts/reconfigure-project.sh" --field data_classification --new internal ) > "$F1_LOG" 2>&1
  F1_RC=$?
} 2>/dev/null

if [ ! -f "$T1/mv-done" ]; then
  fail_ "F1" "wedge marker never appeared — shim was not invoked. rc=$F1_RC, Log:\n$(cat "$F1_LOG")"
else
  pstate_now_sha=$(shasum "$P1/.claude/process-state.json" | awk '{print $1}')
  pstate_pre_sha=$(shasum "$T1/pstate.pre" | awk '{print $1}')
  approval_now_sha=$(shasum "$P1/APPROVAL_LOG.md" | awk '{print $1}')
  approval_pre_sha=$(shasum "$T1/approval.pre" | awk '{print $1}')

  pstate_changed="NO"; approval_changed="NO"
  [ "$pstate_now_sha"   != "$pstate_pre_sha"   ] && pstate_changed="YES"
  [ "$approval_now_sha" != "$approval_pre_sha" ] && approval_changed="YES"

  fail_reason=""
  # Atomicity contract: pstate and approval are either both pre-state
  # (rollback fired) or both committed (success). The torn state
  # (pstate changed AND approval unchanged) is what the verifier
  # reproduced on PR HEAD.
  if [ "$pstate_changed" = "YES" ] && [ "$approval_changed" = "NO" ]; then
    fail_reason="TORN state: process-state.json mutated but APPROVAL_LOG.md unchanged (rc=$F1_RC). pstate=${pstate_pre_sha}->${pstate_now_sha} approval=$approval_pre_sha (unchanged)"
  elif [ "$pstate_changed" = "NO" ] && [ "$approval_changed" = "YES" ]; then
    fail_reason="TORN state: APPROVAL_LOG.md mutated but process-state.json unchanged (rc=$F1_RC). approval=${approval_pre_sha}->${approval_now_sha}"
  fi

  if [ -z "$fail_reason" ]; then
    pass "F1: signal mid-mutation produced atomic outcome (rc=$F1_RC, pstate_changed=$pstate_changed approval_changed=$approval_changed)"
  else
    fail_ "F1" "$fail_reason. Log:\n$(cat "$F1_LOG")"
  fi
fi
rm -rf "$T1"

# ════════════════════════════════════════════════════════════════════
# F2: intake-wizard.sh non-interactive --data-classification refuses to
# print success when the underlying jq+mv chain failed.
# ════════════════════════════════════════════════════════════════════
echo ""
echo "F2: intake-wizard.sh --data-classification surfaces jq failure (no silent success)"
T2=$(mktemp -d); P2="$T2/p"

mkdir -p "$P2/.claude"
# Malformed process-state.json — jq will choke parsing this.
printf '%s' '{not valid json' > "$P2/.claude/process-state.json"
printf '%s' '{"project":"t","current_phase":1,"deployment":"personal"}' > "$P2/.claude/phase-state.json"
touch "$P2/PROJECT_INTAKE.md"

cp "$P2/.claude/process-state.json" "$T2/pstate.pre"

F2_STDOUT="$T2/stdout"
F2_STDERR="$T2/stderr"
( cd "$P2" && bash "$REPO_ROOT/scripts/intake-wizard.sh" \
    --data-classification internal --zdr-attested ) > "$F2_STDOUT" 2> "$F2_STDERR"
F2_RC=$?

# Assertions:
#   1. Exit code must be non-zero (the operator must know the write failed).
#   2. STDOUT must NOT contain the "Phase 1 artifacts updated" success line.
#   3. Some error indication must reach the operator (stderr OR stdout).
#   4. The file must be byte-identical to the pre-state (no partial write).
f2_fail=""
if [ "$F2_RC" -eq 0 ]; then
  f2_fail="exit code was 0 despite jq parse failure (silent success). STDOUT:\n$(cat "$F2_STDOUT")\nSTDERR:\n$(cat "$F2_STDERR")"
elif grep -q "Phase 1 artifacts updated" "$F2_STDOUT"; then
  f2_fail="stdout claims 'Phase 1 artifacts updated' but the write failed. STDOUT:\n$(cat "$F2_STDOUT")"
elif ! { grep -qi "error\|fail" "$F2_STDERR" || grep -qi "error\|fail\|\[FAIL\]" "$F2_STDOUT"; }; then
  f2_fail="no error indication surfaced to the operator. STDOUT:\n$(cat "$F2_STDOUT")\nSTDERR:\n$(cat "$F2_STDERR")"
elif ! cmp -s "$P2/.claude/process-state.json" "$T2/pstate.pre"; then
  f2_fail="process-state.json was partially mutated despite the jq parse failure."
fi

if [ -z "$f2_fail" ]; then
  pass "F2: jq failure surfaces as non-zero exit + no success line + file unchanged"
else
  fail_ "F2" "$f2_fail"
fi
rm -rf "$T2"

# ════════════════════════════════════════════════════════════════════
# F3: persist_phase1_artifacts() (the interactive-wizard helper used by
# section 5.5) must also surface jq failure. We exercise it by sourcing
# helpers.sh + the function directly and calling it against a malformed
# process-state.json.
# ════════════════════════════════════════════════════════════════════
echo ""
echo "F3: persist_phase1_artifacts() surfaces jq failure (no silent success)"
T3=$(mktemp -d); P3="$T3/p"

mkdir -p "$P3/.claude"
printf '%s' '{not valid json' > "$P3/.claude/process-state.json"
cp "$P3/.claude/process-state.json" "$T3/pstate.pre"

# Source the function out of intake-wizard.sh and call it. We extract
# just the function body via a small bash wrapper that sources the
# script's prelude (helpers.sh) and the function definition.
F3_STDOUT="$T3/stdout"
F3_STDERR="$T3/stderr"

# Run a tiny harness that loads helpers + extracts persist_phase1_artifacts
# from intake-wizard.sh and calls it. We don't source intake-wizard.sh in
# full because that would trigger its argv parsing.
cat > "$T3/harness.sh" <<HARNESS
#!/usr/bin/env bash
set -u
cd "$P3"
source "$REPO_ROOT/scripts/lib/helpers.sh"

# Pull the function definition out of intake-wizard.sh by sed-extracting
# the lines between 'persist_phase1_artifacts()' and the next top-level
# function start.
fn_src=\$(awk '
  /^persist_phase1_artifacts\(\) {/ { in_fn = 1 }
  in_fn { print }
  in_fn && /^}/ { exit }
' "$REPO_ROOT/scripts/intake-wizard.sh")
eval "\$fn_src"

PROJECT_ROOT="$P3"
persist_phase1_artifacts "internal" "true" ""
HARNESS

bash "$T3/harness.sh" > "$F3_STDOUT" 2> "$F3_STDERR"
F3_RC=$?

f3_fail=""
if [ "$F3_RC" -eq 0 ]; then
  f3_fail="exit code was 0 despite jq parse failure (silent success). STDOUT:\n$(cat "$F3_STDOUT")\nSTDERR:\n$(cat "$F3_STDERR")"
elif grep -q "Phase 1 artifacts persisted" "$F3_STDOUT"; then
  f3_fail="stdout claims 'Phase 1 artifacts persisted' but the write failed. STDOUT:\n$(cat "$F3_STDOUT")"
elif ! { grep -qi "error\|fail" "$F3_STDERR" || grep -qi "error\|fail\|\[FAIL\]" "$F3_STDOUT"; }; then
  f3_fail="no error indication surfaced to the operator. STDOUT:\n$(cat "$F3_STDOUT")\nSTDERR:\n$(cat "$F3_STDERR")"
elif ! cmp -s "$P3/.claude/process-state.json" "$T3/pstate.pre"; then
  f3_fail="process-state.json was partially mutated despite the jq parse failure."
fi

if [ -z "$f3_fail" ]; then
  pass "F3: persist_phase1_artifacts() surfaces jq failure"
else
  fail_ "F3" "$f3_fail"
fi
rm -rf "$T3"

# --------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------
echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "tier-crosscheck-6 follow-up suite: Passed: $PASS | Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "Failures: ${FAILED_TESTS[*]}"
  exit 1
fi
exit 0
