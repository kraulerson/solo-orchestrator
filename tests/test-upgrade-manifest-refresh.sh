#!/usr/bin/env bash
# tests/test-upgrade-manifest-refresh.sh — BL-061 regression.
#
# BL-061 (adversarial cert pass S-4, 2026-06-29): scripts/upgrade-project.sh
# refreshed phase-state.json but left .claude/manifest.json's tier snapshot
# (deployment, poc_mode) pointing at the pre-upgrade state. That two-source
# split invites future gate bugs — a downstream reader that consults
# manifest.json rather than phase-state.json will gate the wrong tier.
#
# Fix (upgrade-project.sh section 2b): after the phase-state.json write and
# inside the same atomic snapshot/trap block, update manifest.json fields
# deployment + poc_mode from the resolved target state. manifest.json is
# added to _UPGRADE_MUTATED_FILES so the pre-mutation snapshot captures it
# and the SIGINT/TERM/ERR trap rolls it back alongside phase-state.json.
#
# Test scenarios:
#   T1 — personal→organizational refreshes manifest.json::deployment AND
#        phase-state.json::deployment together (two-source parity).
#   T2 — Sponsored POC→production clears poc_mode in BOTH manifest.json
#        AND phase-state.json.
#   T3 — Atomic rollback: python3 stub fails mid-mutation → manifest.json
#        is byte-for-byte restored from the pre-mutation snapshot.
#   T4 — Idempotence: two consecutive upgrades to the same tier leave
#        manifest.json byte-for-byte identical after the second run
#        (no torn write on a no-op).
#   T5 — Mutation proof: with section 2b commented out, T1 fails RED
#        (manifest.json.deployment stays "personal"). Exercised via a
#        temp copy of upgrade-project.sh with the jq write neutralized.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
UPGRADE="$REPO_ROOT/scripts/upgrade-project.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Same phase-state schema as tests/test-upgrade-paths.sh:make_phase_state,
# plus a manifest.json fixture with the pre-upgrade tier snapshot. Callers
# provide track / deployment / poc_mode (as JSON literal: "value" or null).
make_project() {
  local dir="$1" track="$2" deployment="$3" poc_json="$4"
  mkdir -p "$dir/.claude"
  cat > "$dir/.claude/phase-state.json" <<JSON
{
  "project": "test",
  "framework_version": "1.0",
  "current_phase": 0,
  "track": "$track",
  "deployment": "$deployment",
  "poc_mode": $poc_json,
  "compliance_ready": false,
  "gates": {"phase_0_to_1": null, "phase_1_to_2": null, "phase_3_to_4": null}
}
JSON
  # BL-030 backfill guard: manifest.json carries .enforcement_level after
  # BL-030, and upgrade-project.sh's backfill block bails early when the
  # field is already present (line 295). Seed it here so the backfill
  # doesn't rewrite manifest.json in a way that would confuse the T1
  # deployment assertion (the backfill would set deployment from the
  # PRE-upgrade phase-state.json, giving a false negative if the section
  # 2b refresh silently regressed).
  cat > "$dir/.claude/manifest.json" <<JSON
{
  "host": "github",
  "mode": "personal",
  "remote_url": "",
  "deployment": "$deployment",
  "poc_mode": $poc_json,
  "enforcement_level": "strict"
}
JSON
  # tier-crosscheck-6 gate: personal→organizational upgrades refuse
  # unless phase1_artifacts.data_classification is set. Seed with a
  # value so BL-061's T1 gets past that gate.
  cat > "$dir/.claude/process-state.json" <<'JSON'
{"phase1_artifacts":{"data_classification":"internal","zdr_attested":true,"zdr_attestation_reason":""}}
JSON
  ( cd "$dir" && git init -q && git config user.email t@t.l && git config user.name t \
      && git add -A && git commit -q -m "init" ) >/dev/null 2>&1
}

# code-upgrade-project-8: seed APPROVAL_LOG.md with all 6 Pre-Phase-0 rows
# dated so --to-production passes the deferred-pre-condition gate.
seed_approval_log_org_filled() {
  local dir="$1"
  cat > "$dir/APPROVAL_LOG.md" <<'EOF'
---
project: test
deployment: organizational
created: 2026-06-27
---

## Pre-Phase 0: Organizational Pre-Conditions

| # | Pre-Condition | Approver | Role | Date | Method | Reference | Notes |
|---|---|---|---|---|---|---|---|
| 1 | AI deployment path approved | Sec Lead | IT Security | 2026-06-27 | Email | TKT-1 | |
| 2 | Insurance coverage confirmed | Broker | Insurance | 2026-06-27 | Email | TKT-2 | |
| 3 | Liability entity designated | Legal | Legal | 2026-06-27 | Email | TKT-3 | |
| 4 | Project sponsor assigned | Sponsor | Exec | 2026-06-27 | Email | TKT-4 | |
| 5 | Backup maintainer designated | Backup | Tech Lead | 2026-06-27 | Email | TKT-5 | |
| 6 | ITSM project registered | PMO | ITSM | 2026-06-27 | Email | TKT-6 | |

## Approval History

| Date | Gate / Event | Decision | Notes |
|---|---|---|---|
| | | | |
EOF
}

snapshot_file_sha() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: personal→organizational refreshes manifest.json::deployment ==="
# ════════════════════════════════════════════════════════════════════
#
# The exact BL-061 reproduction from the backlog entry:
#   1. Init personal project
#   2. Upgrade to organizational
#   3. Assert manifest.json::deployment AND phase-state.json::deployment
#      both read "organizational" (two-source parity restored).

T=$(mktemp -d); P="$T/p"
make_project "$P" "standard" "personal" 'null'

( cd "$P" && bash "$UPGRADE" --deployment organizational --non-interactive ) > "$T/log" 2>&1
rc=$?

ps_dep=$(jq -r '.deployment // empty' "$P/.claude/phase-state.json" 2>/dev/null)
mf_dep=$(jq -r '.deployment // empty' "$P/.claude/manifest.json" 2>/dev/null)

if [ "$rc" = "0" ] && [ "$ps_dep" = "organizational" ] && [ "$mf_dep" = "organizational" ]; then
  pass "T1: manifest.json::deployment and phase-state.json::deployment BOTH read 'organizational'"
else
  fail_ "T1" "rc=$rc phase_state.deployment='$ps_dep' manifest.deployment='$mf_dep' (expected both='organizational'). Log tail: $(tail -8 "$T/log" 2>/dev/null | tr '\n' '|')"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: Sponsored POC→production clears poc_mode in manifest.json ==="
# ════════════════════════════════════════════════════════════════════
#
# Second tier-tracked field: poc_mode. Sponsored POC → production must
# clear .poc_mode in BOTH files (pre-fix: phase-state.json cleared,
# manifest.json still read "sponsored_poc").

T=$(mktemp -d); P="$T/p"
make_project "$P" "standard" "organizational" '"sponsored_poc"'
seed_approval_log_org_filled "$P"
( cd "$P" && git add APPROVAL_LOG.md && git commit -q -m "seed approval log" ) >/dev/null 2>&1

( cd "$P" && bash "$UPGRADE" --to-production --non-interactive ) > "$T/log" 2>&1
rc=$?

ps_pm=$(jq -r '.poc_mode' "$P/.claude/phase-state.json" 2>/dev/null)
mf_pm=$(jq -r '.poc_mode' "$P/.claude/manifest.json" 2>/dev/null)
ps_dep=$(jq -r '.deployment' "$P/.claude/phase-state.json" 2>/dev/null)
mf_dep=$(jq -r '.deployment' "$P/.claude/manifest.json" 2>/dev/null)

# phase-state.json deletes poc_mode via `del data["poc_mode"]` (heredoc
# in section 2), so `.poc_mode` in jq returns "null" for absent keys.
# manifest.json section 2b sets it explicitly to JSON null. Both count.
ps_pm_ok=$( { [ "$ps_pm" = "null" ] || [ "$ps_pm" = "" ]; } && echo y || echo n )
mf_pm_ok=$( { [ "$mf_pm" = "null" ] || [ "$mf_pm" = "" ]; } && echo y || echo n )

if [ "$rc" = "0" ] && [ "$ps_pm_ok" = "y" ] && [ "$mf_pm_ok" = "y" ] \
   && [ "$ps_dep" = "organizational" ] && [ "$mf_dep" = "organizational" ]; then
  pass "T2: Sponsored POC → production clears poc_mode in BOTH files; deployment stays organizational in BOTH"
else
  fail_ "T2" "rc=$rc phase_state(pm='$ps_pm' dep='$ps_dep') manifest(pm='$mf_pm' dep='$mf_dep'). Log tail: $(tail -8 "$T/log" 2>/dev/null | tr '\n' '|')"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: python3 failure mid-mutation → manifest.json is rolled back ==="
# ════════════════════════════════════════════════════════════════════
#
# Failure-path coverage: BL-061's atomic-rollback requirement. Pre-fix
# (even in the world where manifest is refreshed) a mid-run failure
# would leave manifest.json in the new state while phase-state.json
# was reverted, re-creating the two-source split from the other side.
# The fix: MANIFEST_JSON is in _UPGRADE_MUTATED_FILES so it's snapshotted
# and rolled back by the ERR trap.
#
# Uses the same python3 stub technique as test-upgrade-project-atomic.sh.
# The stub forwards N calls to real python3, then exits 1 on call N+1 —
# triggering set -e ERR trap → _upgrade_rollback.

T=$(mktemp -d); P="$T/p"; STUB="$T/stub"
make_project "$P" "standard" "personal" 'null'

mkdir -p "$STUB"
echo "0" > "$STUB/counter"
real_python3=$(command -v python3)
# Fixture has no tool-preferences.json, no intake-progress.json, no
# CLAUDE.md, no PROJECT_INTAKE.md, and no APPROVAL_LOG.md — so the only
# python3 heredocs that run for --deployment organizational are:
#   #1 phase-state.json (heredoc, section 2)
#   #2 APPROVAL_LOG.md generation (heredoc, section 6 "No existing
#      APPROVAL_LOG.md — generating organizational format" branch)
# Section 2b uses jq, not python3, and runs BETWEEN #1 and #2. Set
# pass_count=1 so #1 succeeds (phase-state advances), section 2b jq
# refreshes manifest.json, then #2 fails → rollback restores BOTH.
cat > "$STUB/python3" <<STUB_EOF
#!/usr/bin/env bash
set -e
counter_file="$STUB/counter"
n=\$(cat "\$counter_file" 2>/dev/null || echo 0)
n=\$((n + 1))
echo "\$n" > "\$counter_file"
if [ "\$n" -le 1 ]; then
  exec "$real_python3" "\$@"
fi
echo "stub-python3: simulated failure on call \$n" >&2
exit 1
STUB_EOF
chmod +x "$STUB/python3"

# Snapshot pre-mutation SHA of manifest.json + phase-state.json.
sha_mf_pre=$(snapshot_file_sha "$P/.claude/manifest.json")
sha_ps_pre=$(snapshot_file_sha "$P/.claude/phase-state.json")

( cd "$P" && PATH="$STUB:$PATH" bash "$UPGRADE" --deployment organizational --non-interactive ) > "$T/log" 2>&1
rc=$?

sha_mf_post=$(snapshot_file_sha "$P/.claude/manifest.json")
sha_ps_post=$(snapshot_file_sha "$P/.claude/phase-state.json")

# The stub advanced the counter past pass_count=2, so section 2 + 2b
# both ran (both wrote new state). Then heredoc #3 (intake-progress or
# CLAUDE.md, depending on which files exist) failed → rollback fires →
# both files restored byte-for-byte.
snapshot_count=$( find "$P/.claude/upgrade-snapshots" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ' )

if [ "$rc" != "0" ] \
   && [ "$sha_mf_pre" = "$sha_mf_post" ] \
   && [ "$sha_ps_pre" = "$sha_ps_post" ] \
   && [ "$snapshot_count" -ge 1 ]; then
  pass "T3: python3 failure post-manifest-write → manifest.json + phase-state.json BOTH restored; snapshot retained"
else
  mf_changed=$( [ "$sha_mf_pre" = "$sha_mf_post" ] && echo n || echo y )
  ps_changed=$( [ "$sha_ps_pre" = "$sha_ps_post" ] && echo n || echo y )
  fail_ "T3" "rc=$rc manifest_changed=$mf_changed phase_state_changed=$ps_changed snapshot_count=$snapshot_count. Log tail: $(tail -10 "$T/log" 2>/dev/null | tr '\n' '|')"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T4: idempotence — second run is a no-op, manifest.json unchanged ==="
# ════════════════════════════════════════════════════════════════════
#
# After a successful upgrade, running the SAME upgrade a second time
# must be a no-op. upgrade-project.sh's "No changes needed" guard
# (line 925) exits early, so section 2b is never reached — manifest.json
# stays byte-for-byte identical to the post-run-1 state (proving the
# no-op path doesn't accidentally rewrite the tier snapshot).

T=$(mktemp -d); P="$T/p"
make_project "$P" "standard" "personal" 'null'

# Run 1: personal → organizational.
( cd "$P" && bash "$UPGRADE" --deployment organizational --non-interactive ) > "$T/log1" 2>&1
rc1=$?
sha_mf_after_run1=$(snapshot_file_sha "$P/.claude/manifest.json")
mf_dep_after_run1=$(jq -r '.deployment' "$P/.claude/manifest.json" 2>/dev/null)

# Run 2: same target (should be a no-op).
( cd "$P" && bash "$UPGRADE" --deployment organizational --non-interactive ) > "$T/log2" 2>&1
rc2=$?
sha_mf_after_run2=$(snapshot_file_sha "$P/.claude/manifest.json")

if [ "$rc1" = "0" ] && [ "$rc2" = "0" ] \
   && [ "$mf_dep_after_run1" = "organizational" ] \
   && [ "$sha_mf_after_run1" = "$sha_mf_after_run2" ]; then
  pass "T4: idempotent second run leaves manifest.json byte-for-byte identical"
else
  fail_ "T4" "rc1=$rc1 rc2=$rc2 mf_dep_after_run1='$mf_dep_after_run1' sha_match=$([ "$sha_mf_after_run1" = "$sha_mf_after_run2" ] && echo y || echo n). Log tails: run1=$(tail -5 "$T/log1" 2>/dev/null | tr '\n' '|') | run2=$(tail -5 "$T/log2" 2>/dev/null | tr '\n' '|')"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T5: mutation proof — commenting out section 2b makes T1 fail RED ==="
# ════════════════════════════════════════════════════════════════════
#
# The BL-061 verification-loop requirement: prove that without the
# section 2b jq write, T1's assertion fails. This runs the exact same
# scenario as T1 against a copy of upgrade-project.sh whose section 2b
# jq write has been neutralized (replaced with a comment). The resulting
# manifest.json must still read deployment='personal' (the pre-upgrade
# tier), proving the section 2b write is what closes BL-061.

T=$(mktemp -d); P="$T/p"
make_project "$P" "standard" "personal" 'null'

# Stage a scripts/ dir under $T with lib/ symlinked to the real one, so
# the mutated upgrade-project.sh's `source "$SCRIPT_DIR/lib/helpers.sh"`
# and `ORCHESTRATOR_ROOT/scripts/...` resolutions still work.
MUTATED_DIR="$T/scripts"
mkdir -p "$MUTATED_DIR"
ln -s "$REPO_ROOT/scripts/lib" "$MUTATED_DIR/lib"
# Symlink the other framework scripts upgrade-project.sh may call
# (resolve-tools.sh, verify-install.sh, validate.sh, etc.) — most are
# guarded and won't fire in this test path, but linking makes SCRIPT_DIR
# behave like the real scripts/ tree.
for f in "$REPO_ROOT"/scripts/*.sh; do
  base=$(basename "$f")
  [ "$base" = "upgrade-project.sh" ] && continue
  ln -s "$f" "$MUTATED_DIR/$base"
done
MUTATED_UPGRADE="$MUTATED_DIR/upgrade-project.sh"
cp "$UPGRADE" "$MUTATED_UPGRADE"

# Also link templates/ so ORCHESTRATOR_ROOT/templates/... refs (skills
# sync at ~line 356, tool-matrix later) find their fixtures.
ln -s "$REPO_ROOT/templates" "$T/templates"

# Sanity guard on the mutation target: if future edits change section
# 2b's jq filter, this test fails LOUDLY (with a clear "pattern moved"
# message) rather than silently reporting a false pass.
if ! grep -q "'. + {deployment: \$dep, poc_mode: \$pm}'" "$MUTATED_UPGRADE"; then
  fail_ "T5" "mutation pattern not found in upgrade-project.sh — did section 2b's jq filter change? (test needs updating)"
  rm -rf "$T"
else
  # Neutralize the section 2b jq write: replace the multi-line pipeline
  # with a `:` (bash no-op) so nothing rewrites manifest.json. The awk
  # block matches from the `jq --arg dep "$TARGET_DEPLOYMENT"` line up
  # through the `mv "$_mf_tmp" "$MANIFEST_JSON"` line inclusive.
  awk '
    /^  jq --arg dep "\$TARGET_DEPLOYMENT" \\$/ { in_block=1; print "  : # mutation: section 2b jq write neutralized for T5"; next }
    in_block && /^    && mv "\$_mf_tmp" "\$MANIFEST_JSON"$/ { in_block=0; next }
    in_block { next }
    { print }
  ' "$MUTATED_UPGRADE" > "$T/tmp" && mv "$T/tmp" "$MUTATED_UPGRADE"

  if grep -q "'. + {deployment: \$dep, poc_mode: \$pm}'" "$MUTATED_UPGRADE"; then
    fail_ "T5" "mutation did not take effect — awk block didn't match. Section 2b still contains the jq filter."
    rm -rf "$T"
  else
    ( cd "$P" && bash "$MUTATED_UPGRADE" --deployment organizational --non-interactive ) > "$T/log" 2>&1
    rc=$?
    ps_dep=$(jq -r '.deployment // empty' "$P/.claude/phase-state.json" 2>/dev/null)
    mf_dep=$(jq -r '.deployment // empty' "$P/.claude/manifest.json" 2>/dev/null)

    # Expected mutation state: phase-state.json advanced (section 2 still
    # runs), manifest.json stays 'personal' (section 2b was neutralized).
    # This is the exact BL-061 bug shape the fix eliminates.
    if [ "$rc" = "0" ] && [ "$ps_dep" = "organizational" ] && [ "$mf_dep" = "personal" ]; then
      pass "T5: mutation confirmed — without section 2b, manifest.json.deployment stays 'personal' while phase-state.json advances (BL-061 bug shape)"
    else
      fail_ "T5" "mutation did not reproduce BL-061: rc=$rc phase_state.deployment='$ps_dep' manifest.deployment='$mf_dep' (expected rc=0 ps='organizational' mf='personal'). Log tail: $(tail -8 "$T/log" 2>/dev/null | tr '\n' '|')"
    fi
    rm -rf "$T"
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
