#!/usr/bin/env bash
# tests/test-bl084-tier-aware-remote-policy.sh — BL-084 regression suite.
#
# BL-084 (Karl-approved, tier-aware): `init.sh --git-host other` (the
# documented bring-your-own-host path) must NOT be a blanket silent success
# on a failed initial push (a prior draft made every 'other'-host push
# failure return 0 — that re-opened the project's #1 defect class, BL-064
# silent-success). Instead the policy is keyed on `track`:
#
#   • track=standard|full (POC-Sponsored / Production): a working remote is
#     MANDATORY. A failed push is a NON-bypassable hard failure — init exits
#     non-zero with a "Setup INCOMPLETE" banner; NO flag helps.
#   • track=light (Personal / POC-Personal): the operator MAY proceed, but
#     ONLY with an EXPLICIT, on-the-record acknowledgment (never a silent
#     pass):
#       --accept-local-only-risk → keep the project local, accept data-loss
#         risk; recorded as phase2_init.remote.local_only_acknowledged.
#       --defer-remote-push → push manually later; recorded as
#         phase2_init.remote.push_deferred_acknowledged; the Phase 1→2 gate
#         WILL block until the remote actually has the branch.
#     Absent a flag, a light-tier push failure is STILL a real failure.
#
# Part 3 backstop: scripts/check-phase-gate.sh adds a Phase 1→2 remote
# PUSH-verification (host=other only) — `git ls-remote --heads origin`,
# hermetic against a LOCAL bare repo, never gh (BL-076). Tier-aware:
#   • standard|full without a verified remote → FAIL (non-bypassable).
#   • light with local_only_acknowledged → PASS.
#   • light with push_deferred_acknowledged but no verified remote → FAIL
#     (the deferral does NOT let you advance — the load-bearing guarantee).
#   • verified remote present → PASS.
#
# Part 1: scripts/verify-install.sh routes the 'other'-host CI/release
# pipeline absence to a non-blocking WARNING (excluded from the issue total),
# so it does not spuriously fail the check (BL-064 preserved for supported
# hosts). Proven here by V1 + implicitly by the light+ack init exiting 0.
#
# TWO mutation proofs are documented at the tail of this file (RED targets:
# `# BL-084-TIER-GATE` in init.sh and `# BL-084-PUSH-VERIFY` in
# check-phase-gate.sh).
#
# Hermetic (BL-076): every init runs --git-host other against a FAKE url so
# the push fails by design and NO real remote is ever created; gate fixtures
# point origin at a LOCAL bare repo. `gh`/`glab` are never invoked.
set -uo pipefail
export GIT_TERMINAL_PROMPT=0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SH="$REPO_ROOT/init.sh"
GATE_SH="$REPO_ROOT/scripts/check-phase-gate.sh"
VERIFY_SH="$REPO_ROOT/scripts/verify-install.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

FAKE_URL="https://example.invalid/bl084-fake.git"

# run_init <projdir> <flags...> — real init.sh on the 'other' host with a
# fake URL (push fails by design). Echoes the exit code; leaves the project
# tree at <projdir> for the caller to inspect. Never touches a real remote.
run_init() {
  local proj="$1"; shift
  local parent rc=0
  parent="$(dirname "$proj")"
  mkdir -p "$parent"
  ( cd "$parent" && "$INIT_SH" --non-interactive \
      --project bl084 --platform web --language typescript \
      --project-dir "$proj" \
      --git-host other --remote-url "$FAKE_URL" --branch-protection-attested \
      --visibility private "$@" >"$proj.initlog" 2>&1 ) || rc=$?
  echo "$rc"
}

# build_gate_fixture <projdir> <track> <verified:true|false> <ack:none|local_only|deferred>
# Constructs a hermetic Phase-2 host=other project whose ONLY variable is the
# push-gate input. A fresh branch-protection attestation + data_classification
# =public keep the sibling protection/ZDR backstops green so the push-gate
# signal is isolated. origin points at a LOCAL bare repo; when verified=true
# we push main to it, otherwise it stays empty.
build_gate_fixture() {
  local proj="$1" track="$2" verified="$3" ack="$4"
  local bare="$proj.bare.git"
  mkdir -p "$proj/.claude"
  git init -q --bare "$bare"

  local now; now="$(date -u +%FT%TZ)"

  cat > "$proj/.claude/manifest.json" <<JSON
{"frameworkVersion":"test","host":"other","mode":"personal","remote_url":"$bare"}
JSON

  cat > "$proj/.claude/phase-state.json" <<JSON
{"current_phase":2,"deployment":"personal","track":"$track","gates":{"phase_0_to_1":"2026-01-01","phase_1_to_2":"2026-02-01"}}
JSON

  # Acknowledgment record (BL-084 remote escape hatches).
  local remote_json="{}"
  case "$ack" in
    local_only) remote_json="{\"local_only_acknowledged\":{\"risk_accepted\":true,\"reason\":\"test\",\"date\":\"$now\",\"by\":\"tester\"}}" ;;
    deferred)   remote_json="{\"push_deferred_acknowledged\":{\"risk_accepted\":true,\"reason\":\"test\",\"date\":\"$now\",\"by\":\"tester\"}}" ;;
  esac

  cat > "$proj/.claude/process-state.json" <<JSON
{"phase2_init":{"steps_completed":[],"attestations":{"branch_protection":{"attested_by":"orchestrator","at":"$now"}},"remote":$remote_json},
 "phase1_artifacts":{"data_classification":"public","zdr_attested":false}}
JSON

  cat > "$proj/APPROVAL_LOG.md" <<'MD'
# APPROVAL_LOG

## Phase 0 → Phase 1
Approved 2026-01-01

## Phase 1 → Phase 2
Approved 2026-02-01
MD

  {
    echo "# PRODUCT_MANIFESTO"; echo ""
    for i in 1 2 3 4 5 6 7 8; do echo "## ${i}. Section ${i}"; echo "Filled content for section ${i}."; echo ""; done
  } > "$proj/PRODUCT_MANIFESTO.md"

  {
    echo "# PROJECT_BIBLE"; echo ""
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do echo "## ${i}. Section ${i}"; echo "Content."; echo ""; done
  } > "$proj/PROJECT_BIBLE.md"

  ( cd "$proj" \
      && git init -q \
      && git config user.email t@t.test && git config user.name tester \
      && git add -A && git commit -q -m "init" \
      && git branch -M main \
      && git remote add origin "$bare" )

  if [ "$verified" = "true" ]; then
    ( cd "$proj" && git push -q origin main )
  fi
}

run_gate() { ( cd "$1" && bash "$GATE_SH" 2>&1 ); }

echo "== tests/test-bl084-tier-aware-remote-policy.sh =="
echo ""

TOP=$(mktemp -d)

# ════════════════════════════════════════════════════════════════════
# PART 2 — init.sh tier-aware push-failure policy
# ════════════════════════════════════════════════════════════════════
echo "-- Part 2: init.sh tier-aware push-fail --"

# I1: Sponsored POC (track=standard) + push fail → HARD FAIL, even WITH an
# escape flag (the flag must NOT help at this tier).
I1P="$TOP/i1/proj"
rc=$(run_init "$I1P" --track standard --deployment organizational --gov-mode sponsored_poc --accept-local-only-risk)
if [ "$rc" -eq 0 ]; then
  fail_ "I1" "Sponsored (standard) + push fail must be non-bypassable; got rc=0 (log: $I1P.initlog)"
elif grep -q "Setup INCOMPLETE" "$I1P.initlog" && grep -q "MANDATORY for track=standard" "$I1P.initlog"; then
  pass "I1: Sponsored (standard) + push fail → hard FAIL, --accept-local-only-risk does not help (rc=$rc)"
else
  fail_ "I1" "expected 'Setup INCOMPLETE' + 'MANDATORY for track=standard'; tail:\n$(tail -8 "$I1P.initlog")"
fi

# I2: Production (track=full) + push fail → HARD FAIL, even WITH --defer-remote-push.
I2P="$TOP/i2/proj"
rc=$(run_init "$I2P" --track full --deployment organizational --gov-mode production --defer-remote-push)
if [ "$rc" -eq 0 ]; then
  fail_ "I2" "Production (full) + push fail must be non-bypassable; got rc=0 (log: $I2P.initlog)"
elif grep -q "Setup INCOMPLETE" "$I2P.initlog" && grep -q "MANDATORY for track=full" "$I2P.initlog"; then
  pass "I2: Production (full) + push fail → hard FAIL, --defer-remote-push does not help (rc=$rc)"
else
  fail_ "I2" "expected 'Setup INCOMPLETE' + 'MANDATORY for track=full'; tail:\n$(tail -8 "$I2P.initlog")"
fi

# I3: Personal light + push fail + NO flag → real FAIL (default = no silent success).
I3P="$TOP/i3/proj"
rc=$(run_init "$I3P" --track light --deployment personal)
if [ "$rc" -eq 0 ]; then
  fail_ "I3" "light + push fail + no flag must FAIL by default; got rc=0 (log: $I3P.initlog)"
elif grep -q "Setup INCOMPLETE" "$I3P.initlog" && grep -q -- "--accept-local-only-risk" "$I3P.initlog"; then
  pass "I3: light + push fail + no flag → real FAIL; remediation names the escape flags (rc=$rc)"
else
  fail_ "I3" "expected 'Setup INCOMPLETE' + escape-flag hint; tail:\n$(tail -8 "$I3P.initlog")"
fi

# I4: Personal light + --accept-local-only-risk → rc0 + local_only_acknowledged recorded.
I4P="$TOP/i4/proj"
rc=$(run_init "$I4P" --track light --deployment personal --accept-local-only-risk)
lo=$(jq -r '.phase2_init.remote.local_only_acknowledged.risk_accepted // "-"' "$I4P/.claude/process-state.json" 2>/dev/null || echo "noPS")
if [ "$rc" -eq 0 ] && [ "$lo" = "true" ] && grep -q "Setup Complete" "$I4P.initlog"; then
  pass "I4: light + --accept-local-only-risk → rc0 + 'Setup Complete' + local_only_acknowledged recorded"
else
  fail_ "I4" "expected rc0 + local_only_acknowledged=true; got rc=$rc ack=$lo; tail:\n$(tail -8 "$I4P.initlog")"
fi

# I5: Personal light + --defer-remote-push → rc0 + push_deferred_acknowledged recorded.
I5P="$TOP/i5/proj"
rc=$(run_init "$I5P" --track light --deployment personal --defer-remote-push)
df=$(jq -r '.phase2_init.remote.push_deferred_acknowledged.risk_accepted // "-"' "$I5P/.claude/process-state.json" 2>/dev/null || echo "noPS")
if [ "$rc" -eq 0 ] && [ "$df" = "true" ] && grep -q "Setup Complete" "$I5P.initlog"; then
  pass "I5: light + --defer-remote-push → rc0 + 'Setup Complete' + push_deferred_acknowledged recorded"
else
  fail_ "I5" "expected rc0 + push_deferred_acknowledged=true; got rc=$rc defer=$df; tail:\n$(tail -8 "$I5P.initlog")"
fi

# ════════════════════════════════════════════════════════════════════
# PART 1 — verify-install.sh non-blocking bring-your-own CI/CD warning
# ════════════════════════════════════════════════════════════════════
echo "-- Part 1: verify-install.sh non-blocking CI/CD warn (other host) --"

# V1: reuse the fully-created I4 project (host=other). verify-install must
# route the missing CI/release pipeline to the non-blocking WARNINGS bucket
# (never a blocking MANUAL that would drive a non-zero exit).
if [ -d "$I4P/.claude" ]; then
  vout=$( ( cd "$I4P" && bash "$VERIFY_SH" --check-only 2>&1 ) || true )
  if echo "$vout" | grep -q "CONFIGURE MANUALLY (non-blocking)" \
     && echo "$vout" | grep -q "CI pipeline: configure manually" \
     && ! echo "$vout" | grep -qE "CI pipeline missing.*\(manual\)"; then
    pass "V1: verify-install routes other-host CI/release absence to a non-blocking warning (not a blocking MANUAL)"
  else
    fail_ "V1" "expected non-blocking CI/CD warning section; grep:\n$(echo "$vout" | grep -iE 'ci pipeline|release pipeline|non-blocking' | head)"
  fi
else
  fail_ "V1" "I4 project fixture missing — cannot run verify-install"
fi

# ════════════════════════════════════════════════════════════════════
# PART 3 — check-phase-gate.sh Phase 1→2 remote push verification
# ════════════════════════════════════════════════════════════════════
echo "-- Part 3: check-phase-gate.sh Phase 1→2 push verification --"

# G1: standard, no verified remote (empty bare origin), no ack → FAIL (mandatory).
G1P="$TOP/g1/proj"; build_gate_fixture "$G1P" "standard" "false" "none"
out=$(run_gate "$G1P"); rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q "track=standard requires a VERIFIED remote"; then
  pass "G1: standard + no verified remote → gate FAIL (non-bypassable)"
else
  fail_ "G1" "expected FAIL 'track=standard requires a VERIFIED remote'; rc=$rc; grep:\n$(echo "$out" | grep -i 'push gate')"
fi

# G2: full, no verified remote, no ack → FAIL (mandatory).
G2P="$TOP/g2/proj"; build_gate_fixture "$G2P" "full" "false" "none"
out=$(run_gate "$G2P"); rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q "track=full requires a VERIFIED remote"; then
  pass "G2: full + no verified remote → gate FAIL (non-bypassable)"
else
  fail_ "G2" "expected FAIL 'track=full requires a VERIFIED remote'; rc=$rc; grep:\n$(echo "$out" | grep -i 'push gate')"
fi

# G3: light + local_only_acknowledged (no remote) → PASS (operator opted out, on record).
G3P="$TOP/g3/proj"; build_gate_fixture "$G3P" "light" "false" "local_only"
out=$(run_gate "$G3P"); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "push gate: local-only acknowledged"; then
  pass "G3: light + local_only_acknowledged → gate PASS"
else
  fail_ "G3" "expected PASS 'local-only acknowledged'; rc=$rc; grep:\n$(echo "$out" | grep -iE 'push gate|inconsistenc')"
fi

# G4: light + push_deferred_acknowledged but NO verified remote → FAIL.
# LOAD-BEARING: the deferral must NOT let the operator advance — the gate
# WILL block until the push is actually verified.
G4P="$TOP/g4/proj"; build_gate_fixture "$G4P" "light" "false" "deferred"
out=$(run_gate "$G4P"); rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q "push was DEFERRED"; then
  pass "G4: light + deferred-but-not-pushed → gate FAIL (the gate WILL block you until pushed) [load-bearing]"
else
  fail_ "G4" "expected FAIL 'push was DEFERRED'; rc=$rc; grep:\n$(echo "$out" | grep -i 'push gate')"
fi

# G5: verified remote present (local bare repo, main pushed) → PASS.
G5P="$TOP/g5/proj"; build_gate_fixture "$G5P" "standard" "true" "none"
out=$(run_gate "$G5P"); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "push gate: remote has the branch"; then
  pass "G5: verified remote present → gate PASS (even at track=standard)"
else
  fail_ "G5" "expected PASS 'remote has the branch'; rc=$rc; grep:\n$(echo "$out" | grep -iE 'push gate|inconsistenc')"
fi

rm -rf "$TOP"

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1

# ════════════════════════════════════════════════════════════════════
# MUTATION PROOFS (run manually / captured in the PR description)
# ════════════════════════════════════════════════════════════════════
# (a) Gate push-verification is load-bearing:
#     In scripts/check-phase-gate.sh, force `bl084_remote_verified=true` on
#     the `# BL-084-PUSH-VERIFY` line → G4 (deferred-but-not-pushed) flips
#     RED (gate would PASS an un-pushed deferral). Restore → GREEN.
# (b) init tier gate is load-bearing:
#     In init.sh, delete the `standard|full)` branch on the
#     `# BL-084-TIER-GATE` line so standard/full falls through to the
#     permissive light path → I1 (Sponsored hard-fail) flips RED (init
#     would exit 0). Restore → GREEN.
