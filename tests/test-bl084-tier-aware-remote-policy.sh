#!/usr/bin/env bash
# tests/test-bl084-tier-aware-remote-policy.sh — BL-084 regression suite.
#
# BL-084 (Karl-approved, tier-aware): `init.sh --git-host other` (the
# documented bring-your-own-host path) must NOT be a blanket silent success
# on a failed initial push (a prior draft made every 'other'-host push
# failure return 0 — that re-opened the project's #1 defect class, BL-064
# silent-success). Instead the policy is keyed on the ACTUAL project TIER.
#
# VERIFIER FOLLOW-UP (the load-bearing fix this suite pins): eligibility is
# keyed on `deployment` + `poc_mode`, NOT on `track`. `track=light` can be set
# non-interactively on a POC-Sponsored / Production project (the interactive
# force-upgrade at init.sh:561-573 does not run in --non-interactive mode), so
# trusting `track` would let a sponsored/production project bypass a failed
# push with NO code uploaded. Tier:
#   BYPASSABLE     (Personal / POC-Personal): deployment=personal AND
#                  poc_mode≠sponsored_poc.
#   NON-bypassable (POC-Sponsored / Production): deployment=organizational
#                  OR poc_mode=sponsored_poc.
# init.sh (_bl084_tier_bypassable) and check-phase-gate.sh (bl084_bypassable)
# compute the IDENTICAL predicate so the two enforcement points agree.
#
#   • NON-bypassable + push fail → HARD FAIL (init exits non-zero,
#     "Setup INCOMPLETE"); NO flag helps, EVEN with track=light.
#   • BYPASSABLE + push fail → real failure by default, but the operator MAY
#     proceed with an EXPLICIT, on-the-record ack (never a silent pass):
#       --accept-local-only-risk → records local_only_acknowledged.
#       --defer-remote-push      → records push_deferred_acknowledged; the
#                                  Phase 1→2 gate WILL block until pushed.
#
# Part 3 backstop: scripts/check-phase-gate.sh adds a Phase 1→2 remote
# PUSH-verification (host=other only) — `git ls-remote --heads origin`,
# hermetic against a LOCAL bare repo, never gh (BL-076). Same tier keying:
#   • NON-bypassable without a verified remote → FAIL (no ack bypasses, even
#     a recorded local_only_acknowledged — a sponsored/production project
#     cannot opt out).
#   • BYPASSABLE with local_only_acknowledged → PASS; with a deferred ack but
#     no verified push → FAIL (the deferral does NOT let you advance).
#   • verified remote present → PASS.
#
# Part 1: scripts/verify-install.sh routes the 'other'-host CI/release
# pipeline absence to a non-blocking WARNING (excluded from the issue total).
#
# THREE mutation proofs are documented at the tail (RED targets:
# `# BL-084-TIER-GATE`, `# BL-084-PUSH-VERIFY`, `# BL-084-TIER-KEY`).
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

# build_gate_fixture <projdir> <deployment> <poc_mode:null|private_poc|sponsored_poc> <track> <verified:true|false> <ack:none|local_only|deferred>
# Constructs a hermetic Phase-2 host=other project. The tier is set via
# deployment + poc_mode (the fields the gate keys on); `track` is written into
# phase-state.json verbatim so the DANGEROUS combos (organizational +
# track=light) are exercised — the gate MUST ignore track. A fresh branch-
# protection attestation + data_classification=public keep the sibling
# protection/ZDR backstops green so only the push-gate signal varies. origin
# points at a LOCAL bare repo; verified=true pushes main to it.
build_gate_fixture() {
  local proj="$1" deployment="$2" poc_mode="$3" track="$4" verified="$5" ack="$6"
  local bare="$proj.bare.git"
  mkdir -p "$proj/.claude"
  git init -q --bare "$bare"

  local now; now="$(date -u +%FT%TZ)"

  cat > "$proj/.claude/manifest.json" <<JSON
{"frameworkVersion":"test","host":"other","mode":"personal","remote_url":"$bare"}
JSON

  local poc_json="null"
  [ "$poc_mode" != "null" ] && poc_json="\"$poc_mode\""
  cat > "$proj/.claude/phase-state.json" <<JSON
{"current_phase":2,"deployment":"$deployment","poc_mode":$poc_json,"track":"$track","gates":{"phase_0_to_1":"2026-01-01","phase_1_to_2":"2026-02-01"}}
JSON

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
# PART 2 — init.sh tier-aware push-failure policy (keyed on tier, not track)
# ════════════════════════════════════════════════════════════════════
echo "-- Part 2: init.sh tier-aware push-fail --"

# I1: POC-Sponsored (organizational + sponsored_poc, track=standard) + push
# fail → HARD FAIL, even WITH an escape flag.
I1P="$TOP/i1/proj"
rc=$(run_init "$I1P" --track standard --deployment organizational --gov-mode sponsored_poc --accept-local-only-risk)
if [ "$rc" -eq 0 ]; then
  fail_ "I1" "Sponsored + push fail must be non-bypassable; got rc=0 (log: $I1P.initlog)"
elif grep -q "Setup INCOMPLETE" "$I1P.initlog" && grep -q "MANDATORY for POC-Sponsored" "$I1P.initlog"; then
  pass "I1: POC-Sponsored + push fail → hard FAIL, --accept-local-only-risk does not help (rc=$rc)"
else
  fail_ "I1" "expected 'Setup INCOMPLETE' + 'MANDATORY for POC-Sponsored'; tail:\n$(tail -8 "$I1P.initlog")"
fi

# I2: Production (organizational + production, track=full) + push fail → HARD
# FAIL, even WITH --defer-remote-push.
I2P="$TOP/i2/proj"
rc=$(run_init "$I2P" --track full --deployment organizational --gov-mode production --defer-remote-push)
if [ "$rc" -eq 0 ]; then
  fail_ "I2" "Production + push fail must be non-bypassable; got rc=0 (log: $I2P.initlog)"
elif grep -q "Setup INCOMPLETE" "$I2P.initlog" && grep -q "MANDATORY for POC-Sponsored / Production" "$I2P.initlog"; then
  pass "I2: Production + push fail → hard FAIL, --defer-remote-push does not help (rc=$rc)"
else
  fail_ "I2" "expected 'Setup INCOMPLETE' + non-bypassable message; tail:\n$(tail -8 "$I2P.initlog")"
fi

# I3: Personal (track=light) + push fail + NO flag → real FAIL (default).
I3P="$TOP/i3/proj"
rc=$(run_init "$I3P" --track light --deployment personal)
if [ "$rc" -eq 0 ]; then
  fail_ "I3" "personal + push fail + no flag must FAIL by default; got rc=0 (log: $I3P.initlog)"
elif grep -q "Setup INCOMPLETE" "$I3P.initlog" && grep -q -- "--accept-local-only-risk" "$I3P.initlog"; then
  pass "I3: Personal + push fail + no flag → real FAIL; remediation names the escape flags (rc=$rc)"
else
  fail_ "I3" "expected 'Setup INCOMPLETE' + escape-flag hint; tail:\n$(tail -8 "$I3P.initlog")"
fi

# I4: Personal (track=light) + --accept-local-only-risk → rc0 + ack recorded.
I4P="$TOP/i4/proj"
rc=$(run_init "$I4P" --track light --deployment personal --accept-local-only-risk)
lo=$(jq -r '.phase2_init.remote.local_only_acknowledged.risk_accepted // "-"' "$I4P/.claude/process-state.json" 2>/dev/null || echo "noPS")
if [ "$rc" -eq 0 ] && [ "$lo" = "true" ] && grep -q "Setup Complete" "$I4P.initlog"; then
  pass "I4: Personal + --accept-local-only-risk → rc0 + 'Setup Complete' + local_only_acknowledged recorded"
else
  fail_ "I4" "expected rc0 + local_only_acknowledged=true; got rc=$rc ack=$lo; tail:\n$(tail -8 "$I4P.initlog")"
fi

# I5: Personal (track=light) + --defer-remote-push → rc0 + deferral recorded.
I5P="$TOP/i5/proj"
rc=$(run_init "$I5P" --track light --deployment personal --defer-remote-push)
df=$(jq -r '.phase2_init.remote.push_deferred_acknowledged.risk_accepted // "-"' "$I5P/.claude/process-state.json" 2>/dev/null || echo "noPS")
if [ "$rc" -eq 0 ] && [ "$df" = "true" ] && grep -q "Setup Complete" "$I5P.initlog"; then
  pass "I5: Personal + --defer-remote-push → rc0 + 'Setup Complete' + push_deferred_acknowledged recorded"
else
  fail_ "I5" "expected rc0 + push_deferred_acknowledged=true; got rc=$rc defer=$df; tail:\n$(tail -8 "$I5P.initlog")"
fi

# I6 [DANGEROUS-CASE, load-bearing]: POC-Sponsored carrying --track light +
# --accept-local-only-risk → HARD FAIL. track=light must NOT unlock the
# bypass on a sponsored project (the exact hole the verifier flagged).
I6P="$TOP/i6/proj"
rc=$(run_init "$I6P" --track light --deployment organizational --gov-mode sponsored_poc --accept-local-only-risk)
lo=$(jq -r '.phase2_init.remote.local_only_acknowledged.risk_accepted // "-"' "$I6P/.claude/process-state.json" 2>/dev/null || echo "noPS")
if [ "$rc" -ne 0 ] && grep -q "MANDATORY for POC-Sponsored" "$I6P.initlog" && [ "$lo" != "true" ]; then
  pass "I6: Sponsored + --track light + --accept-local-only-risk → hard FAIL, NO ack recorded [tier≠track, load-bearing]"
else
  fail_ "I6" "sponsored+track=light must NOT bypass; got rc=$rc ack=$lo; tail:\n$(tail -8 "$I6P.initlog")"
fi

# I7 [DANGEROUS-CASE]: Production carrying --track light + --accept-local-only-
# risk → HARD FAIL.
I7P="$TOP/i7/proj"
rc=$(run_init "$I7P" --track light --deployment organizational --gov-mode production --accept-local-only-risk)
if [ "$rc" -ne 0 ] && grep -q "MANDATORY for POC-Sponsored / Production" "$I7P.initlog"; then
  pass "I7: Production + --track light + --accept-local-only-risk → hard FAIL [tier≠track]"
else
  fail_ "I7" "production+track=light must NOT bypass; got rc=$rc; tail:\n$(tail -8 "$I7P.initlog")"
fi

# I8 [BENIGN-FIX]: plain Personal (NO --track → defaults to track=standard) +
# --accept-local-only-risk → BYPASSABLE (rc0, ack). Confirms Personal now gets
# its intended local-only option despite the non-interactive default track.
I8P="$TOP/i8/proj"
rc=$(run_init "$I8P" --deployment personal --accept-local-only-risk)
lo=$(jq -r '.phase2_init.remote.local_only_acknowledged.risk_accepted // "-"' "$I8P/.claude/process-state.json" 2>/dev/null || echo "noPS")
tr=$(jq -r '.track // "-"' "$I8P/.claude/phase-state.json" 2>/dev/null || echo "-")
if [ "$rc" -eq 0 ] && [ "$lo" = "true" ] && [ "$tr" = "standard" ]; then
  pass "I8: plain Personal (default track=$tr) + --accept-local-only-risk → BYPASSABLE (rc0, ack) [Personal gets its option]"
else
  fail_ "I8" "personal must be bypassable regardless of default track; got rc=$rc ack=$lo track=$tr; tail:\n$(tail -8 "$I8P.initlog")"
fi

# I9 [BENIGN]: POC-Personal (private_poc, NO --track) + --accept-local-only-risk
# → BYPASSABLE (rc0, ack).
I9P="$TOP/i9/proj"
rc=$(run_init "$I9P" --deployment personal --gov-mode private_poc --accept-local-only-risk)
lo=$(jq -r '.phase2_init.remote.local_only_acknowledged.risk_accepted // "-"' "$I9P/.claude/process-state.json" 2>/dev/null || echo "noPS")
if [ "$rc" -eq 0 ] && [ "$lo" = "true" ]; then
  pass "I9: POC-Personal (private_poc) + --accept-local-only-risk → BYPASSABLE (rc0, ack)"
else
  fail_ "I9" "private_poc must be bypassable; got rc=$rc ack=$lo; tail:\n$(tail -8 "$I9P.initlog")"
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
echo "-- Part 3: check-phase-gate.sh Phase 1→2 push verification (tier, not track) --"

# G1: NON-bypassable (organizational production) carrying track=light, no
# verified remote, no ack → FAIL (mandatory). track=light must not soften it.
G1P="$TOP/g1/proj"; build_gate_fixture "$G1P" organizational null light false none
out=$(run_gate "$G1P"); rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q "requires a VERIFIED remote"; then
  pass "G1: organizational/production + track=light + no verified remote → gate FAIL (non-bypassable)"
else
  fail_ "G1" "expected mandatory FAIL; rc=$rc; grep:\n$(echo "$out" | grep -i 'push gate')"
fi

# G2: NON-bypassable (organizational sponsored_poc) carrying track=light, no
# remote, no ack → FAIL (mandatory).
G2P="$TOP/g2/proj"; build_gate_fixture "$G2P" organizational sponsored_poc light false none
out=$(run_gate "$G2P"); rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q "requires a VERIFIED remote"; then
  pass "G2: organizational/sponsored_poc + track=light + no verified remote → gate FAIL (non-bypassable)"
else
  fail_ "G2" "expected mandatory FAIL; rc=$rc; grep:\n$(echo "$out" | grep -i 'push gate')"
fi

# G3: BYPASSABLE (personal) + local_only_acknowledged, no remote → PASS.
G3P="$TOP/g3/proj"; build_gate_fixture "$G3P" personal null light false local_only
out=$(run_gate "$G3P"); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "push gate: local-only acknowledged"; then
  pass "G3: Personal + local_only_acknowledged → gate PASS"
else
  fail_ "G3" "expected PASS 'local-only acknowledged'; rc=$rc; grep:\n$(echo "$out" | grep -iE 'push gate|inconsistenc')"
fi

# G4 [load-bearing]: BYPASSABLE (personal) + push_deferred_acknowledged but NO
# verified remote → FAIL. The deferral must NOT let the operator advance.
G4P="$TOP/g4/proj"; build_gate_fixture "$G4P" personal null light false deferred
out=$(run_gate "$G4P"); rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q "push was DEFERRED"; then
  pass "G4: Personal + deferred-but-not-pushed → gate FAIL (the gate WILL block you until pushed) [load-bearing]"
else
  fail_ "G4" "expected FAIL 'push was DEFERRED'; rc=$rc; grep:\n$(echo "$out" | grep -i 'push gate')"
fi

# G5: verified remote present (local bare repo, main pushed) → PASS.
G5P="$TOP/g5/proj"; build_gate_fixture "$G5P" organizational sponsored_poc light true none
out=$(run_gate "$G5P"); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "push gate: remote has the branch"; then
  pass "G5: verified remote present → gate PASS (even organizational/sponsored)"
else
  fail_ "G5" "expected PASS 'remote has the branch'; rc=$rc; grep:\n$(echo "$out" | grep -iE 'push gate|inconsistenc')"
fi

# G6 [DANGEROUS-CASE, load-bearing]: NON-bypassable (organizational
# sponsored_poc) carrying track=light WITH local_only_acknowledged recorded +
# no verified remote → FAIL. A sponsored/production project CANNOT opt out via
# a local-only ack — this is the gate half of the tier≠track guarantee.
G6P="$TOP/g6/proj"; build_gate_fixture "$G6P" organizational sponsored_poc light false local_only
out=$(run_gate "$G6P"); rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q "requires a VERIFIED remote"; then
  pass "G6: Sponsored + track=light + local_only_acknowledged → gate FAIL (ack does NOT bypass non-bypassable tier) [load-bearing]"
else
  fail_ "G6" "sponsored+local_only_ack must still FAIL; rc=$rc; grep:\n$(echo "$out" | grep -i 'push gate')"
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
#     In init.sh, negate the `! _bl084_tier_bypassable` guard on the
#     `# BL-084-TIER-GATE` line so non-bypassable tiers fall through to the
#     permissive path → I1/I2 (Sponsored/Production hard-fail) flip RED.
#     Restore → GREEN.
# (c) tier-not-track keying is load-bearing [verifier follow-up]:
#     Revert the eligibility to trust `track` — in init.sh make
#     `_bl084_tier_bypassable` (marker `# BL-084-TIER-KEY`) return 0 iff
#     `[ "$TRACK" = light ]`, AND in check-phase-gate.sh set
#     `bl084_bypassable=true` iff `[ "$track" = light ]` (marker
#     `# BL-084-TIER-KEY`) → I6/I7 (sponsored/production + --track light
#     bypass) and G6 (sponsored + local_only ack) flip RED. Restore → GREEN.
