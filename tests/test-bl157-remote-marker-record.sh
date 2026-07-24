#!/usr/bin/env bash
# tests/test-bl157-remote-marker-record.sh — BL-157: check-gate.sh --repair
# must RECONCILE the remote-setup markers (remote_repo_created / pushed_initial)
# from a GENUINELY-present remote during its preflight, so a single
# `--repair --branch-protection-attested` recovers a free-tier project whose
# operator scaffolded with `--no-remote-creation` and wired `origin` by hand —
# WITHOUT re-opening the BL-123 refusal for truly remote-less projects.
#
# WHY THIS EXISTS (Dogfood-4 F-DF4-003)
#   `init.sh --no-remote-creation` skips the API-create path that records
#   remote_repo_created / pushed_initial. An operator who then wires `origin`
#   and pushes has a real remote but no markers on record. The BL-123 post-hoc
#   attestation path (check-gate.sh --repair --branch-protection-attested)
#   REFUSES until those two markers exist, so the operator was forced into an
#   undocumented two-step: a plain `--repair` (records the markers via Steps
#   1-2, then re-hits the free-tier 403) and only THEN the attestation flag.
#   BL-157 records the markers in the repair PREFLIGHT — but only when the
#   configured `origin` genuinely answers `git ls-remote` AND carries the
#   pushed branch — so the two-step collapses to one WITHOUT weakening BL-123.
#
# CASES
#   T-single-shot-attest      genuine local-bare remote + pushed main, NO
#                             markers/attestation → ONE `--repair
#                             --branch-protection-attested` records both markers
#                             + the github_free_tier attestation (recorded_via
#                             check-gate-repair) + rc 0. The attested
#                             short-circuit fires BEFORE host_load_driver, so
#                             the markers can ONLY have come from the BL-157
#                             preflight reconciler (Steps 1-2 never run). RED
#                             pre-fix: the BL-123 precondition refuses.
#   T-preflight-records-markers  same genuine remote but a manifest with NO
#                             host field → plain `--repair` records both markers
#                             in the preflight EVEN THOUGH host_load_driver then
#                             fails (missing host). Isolates the reconciler from
#                             the legacy Step-1/2 recording (which needs a
#                             loadable driver). RED pre-fix: markers absent.
#   T-no-origin-refused       (BL-123 GUARD, b1) NO `origin` at all → the
#                             attestation flag still REFUSES, nothing recorded.
#   T-empty-remote-refused    (BL-123 GUARD, b2) `origin` exists but carries NO
#                             pushed branch → remote_repo_created may be
#                             reconciled but pushed_initial is NOT, so the
#                             attestation still REFUSES (no laundered gate).
#   T-idempotent              a second `--repair --branch-protection-attested`
#                             on the recovered project is a no-op: markers not
#                             duplicated, attestation unchanged, rc 0.
#   T-mutation-fence-excision excise the BL-157 fence → T-single-shot regresses
#                             to a refusal (the reconciler is load-bearing).
#   T-mutation-unconditional  break the GENUINE detection so it records
#                             unconditionally → T-empty-remote (b2) flips: an
#                             attestation IS written on an unpushed remote,
#                             proving the detection guard protects BL-123.
#
# REGISTRATION: no init.sh, not an aggregator → BOTH lists (full-project +
# tests.yml unit lane).
# HERMETIC: the "remote" is a LOCAL bare repo (git init --bare + file:// +
# push) — no network, no host API, nothing real created. bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CG="$REPO_ROOT/scripts/check-gate.sh"

unset GITHUB_BASE_REF SOLO_BP_ATTESTED 2>/dev/null || true

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq required"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP" "$TOPTMP".*.remote.git 2>/dev/null || true' EXIT

# mk_manual_remote_world <dir> <host_or_empty> — a project scaffolded as if via
# --no-remote-creation and then hand-wired: a LOCAL bare repo stands in for the
# remote, `origin` points at it (file://), main is pushed, but NO phase2_init
# markers and NO attestation are on record. If <host_or_empty> is empty the
# manifest omits the host field (used to isolate the preflight reconciler).
mk_manual_remote_world() {
  local d="$1" host="$2"
  rm -rf "$d"
  mkdir -p "$d/.claude"
  local bare="$d.remote.git"
  rm -rf "$bare"
  git init --bare -q "$bare" >/dev/null 2>&1 || return 1
  ( cd "$d" \
      && git init -q \
      && git config user.email "bl157@test.invalid" \
      && git config user.name  "BL-157 Test" \
      && git symbolic-ref HEAD refs/heads/main \
      && echo "# x" > README.md && git add README.md && git commit -q -m "chore: init" \
      && git remote add origin "file://$bare" \
      && git push -q -u origin main ) >/dev/null 2>&1 || return 1
  if [ -n "$host" ]; then
    printf '{"frameworkVersion":"test","host":"%s","mode":"personal","deployment":"organizational","enforcement_level":"strict"}\n' "$host" > "$d/.claude/manifest.json"
  else
    printf '{"frameworkVersion":"test","mode":"personal","deployment":"organizational","enforcement_level":"strict"}\n' > "$d/.claude/manifest.json"
  fi
  jq -n '{phase2_init:{steps_completed:[],verified:false},build_loop:{feature:null,step:0,steps_completed:[]}}' > "$d/.claude/process-state.json"
}

# mk_no_remote_world <dir> <host> — a truly remote-less project: committed, but
# NO `origin` at all. The BL-123 refusal MUST stay for this (b1).
mk_no_remote_world() {
  local d="$1" host="$2"
  rm -rf "$d"
  mkdir -p "$d/.claude"
  ( cd "$d" \
      && git init -q \
      && git config user.email t@t.invalid && git config user.name t \
      && git symbolic-ref HEAD refs/heads/main \
      && echo x > README.md && git add README.md && git commit -q -m "chore: init" ) >/dev/null 2>&1 || return 1
  printf '{"frameworkVersion":"test","host":"%s","mode":"personal","deployment":"organizational","enforcement_level":"strict"}\n' "$host" > "$d/.claude/manifest.json"
  jq -n '{phase2_init:{steps_completed:[],verified:false},build_loop:{feature:null,step:0,steps_completed:[]}}' > "$d/.claude/process-state.json"
}

# mk_empty_remote_world <dir> <host> — `origin` is configured to a real bare
# remote that exists but carries NO pushed branch (nothing was pushed). The
# BL-123 refusal MUST stay: remote_repo_created is genuine but pushed_initial
# is not (b2 — the mutation-sensitive case).
mk_empty_remote_world() {
  local d="$1" host="$2"
  rm -rf "$d"
  mkdir -p "$d/.claude"
  local bare="$d.remote.git"
  rm -rf "$bare"
  git init --bare -q "$bare" >/dev/null 2>&1 || return 1
  ( cd "$d" \
      && git init -q \
      && git config user.email t@t.invalid && git config user.name t \
      && git symbolic-ref HEAD refs/heads/main \
      && echo x > README.md && git add README.md && git commit -q -m "chore: init" \
      && git remote add origin "file://$bare" ) >/dev/null 2>&1 || return 1
  # Deliberately NO push — origin answers ls-remote but has no head refs.
  printf '{"frameworkVersion":"test","host":"%s","mode":"personal","deployment":"organizational","enforcement_level":"strict"}\n' "$host" > "$d/.claude/manifest.json"
  jq -n '{phase2_init:{steps_completed:[],verified:false},build_loop:{feature:null,step:0,steps_completed:[]}}' > "$d/.claude/process-state.json"
}

attest_reason() { jq -r '.phase2_init.attestations.branch_protection.reason // ""' "$1/.claude/process-state.json" 2>/dev/null; }
recorded_via()  { jq -r '.phase2_init.attestations.branch_protection.recorded_via // ""' "$1/.claude/process-state.json" 2>/dev/null; }
step_recorded() { jq -e --arg s "$2" '.phase2_init.steps_completed | index($s) != null' "$1/.claude/process-state.json" >/dev/null 2>&1; }
step_count()    { jq --arg s "$2" '[.phase2_init.steps_completed[] | select(. == $s)] | length' "$1/.claude/process-state.json" 2>/dev/null; }

# ── T-single-shot-attest ─────────────────────────────────────────────────────
echo "=== T-single-shot-attest ==="
P="$TOPTMP/p-single"
mk_manual_remote_world "$P" github || { fail_ "T-single-shot-attest" "fixture setup failed"; }
out=$( cd "$P" && bash "$CG" --repair --branch-protection-attested 2>&1 ); rc=$?
if [ "$(attest_reason "$P")" != "github_free_tier" ]; then
  fail_ "T-single-shot-attest" "a single --repair --branch-protection-attested did NOT record the attestation (rc=$rc) — the BL-157 preflight reconciler is not satisfying the BL-123 precondition from the genuine remote: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
elif ! step_recorded "$P" remote_repo_created || ! step_recorded "$P" pushed_initial; then
  fail_ "T-single-shot-attest" "attestation recorded but the two remote markers were not — the preflight must record BOTH from the genuine remote"
elif [ "$(recorded_via "$P")" != "check-gate-repair" ]; then
  fail_ "T-single-shot-attest" "provenance recorded_via='$(recorded_via "$P")', want 'check-gate-repair'"
elif [ "$rc" -ne 0 ]; then
  fail_ "T-single-shot-attest" "everything recorded but rc=$rc (the attested short-circuit did not fire): $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
else
  pass "T-single-shot-attest"
fi

# ── T-preflight-records-markers ──────────────────────────────────────────────
# Isolates the preflight reconciler: a manifest with NO host field makes
# host_load_driver fail, so the legacy Step-1/2 recording can never run — the
# ONLY code that can record the markers is the BL-157 preflight. Plain --repair
# still exits non-zero (dispatcher load fails), but the markers must be on
# record from the genuine remote before that failure.
echo "=== T-preflight-records-markers ==="
P="$TOPTMP/p-preflight"
mk_manual_remote_world "$P" "" || { fail_ "T-preflight-records-markers" "fixture setup failed"; }
out=$( cd "$P" && bash "$CG" --repair 2>&1 ) || true
if step_recorded "$P" remote_repo_created && step_recorded "$P" pushed_initial; then
  pass "T-preflight-records-markers (both reconciled in the preflight, before host_load_driver)"
else
  fail_ "T-preflight-records-markers" "the preflight did not reconcile both markers from the genuine remote (remote=$(step_recorded "$P" remote_repo_created && echo y || echo n) pushed=$(step_recorded "$P" pushed_initial && echo y || echo n)): $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── T-no-origin-refused (BL-123 GUARD, b1) ───────────────────────────────────
echo "=== T-no-origin-refused ==="
P="$TOPTMP/p-noorigin"
mk_no_remote_world "$P" github || { fail_ "T-no-origin-refused" "fixture setup failed"; }
out=$( cd "$P" && bash "$CG" --repair --branch-protection-attested 2>&1 ); rc=$?
if [ -n "$(attest_reason "$P")" ]; then
  fail_ "T-no-origin-refused" "a remote-less project (no origin) got an attestation RECORDED — BL-157 weakened the BL-123 guard: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
elif step_recorded "$P" remote_repo_created || step_recorded "$P" pushed_initial; then
  fail_ "T-no-origin-refused" "no origin, yet a remote marker was reconciled — the ls-remote probe must gate on a configured, answering origin"
elif ! printf '%s' "$out" | grep -qi "precondition\|no pushed remote branch\|remote_repo_created"; then
  fail_ "T-no-origin-refused" "refused, but without naming the unmet preconditions / recovery: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
else
  pass "T-no-origin-refused"
fi

# ── T-empty-remote-refused (BL-123 GUARD, b2) ────────────────────────────────
echo "=== T-empty-remote-refused ==="
P="$TOPTMP/p-empty"
mk_empty_remote_world "$P" github || { fail_ "T-empty-remote-refused" "fixture setup failed"; }
out=$( cd "$P" && bash "$CG" --repair --branch-protection-attested 2>&1 ); rc=$?
if [ -n "$(attest_reason "$P")" ]; then
  fail_ "T-empty-remote-refused" "an origin with NO pushed branch got an attestation RECORDED — pushed_initial must be reconciled only from a real branch head (laundered gate): $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
elif step_recorded "$P" pushed_initial; then
  fail_ "T-empty-remote-refused" "pushed_initial was recorded for a remote that carries no branch — the branch-head detection is not genuine"
else
  pass "T-empty-remote-refused"
fi

# ── T-idempotent (case c) ────────────────────────────────────────────────────
echo "=== T-idempotent ==="
P="$TOPTMP/p-idem"
mk_manual_remote_world "$P" github || { fail_ "T-idempotent" "fixture setup failed"; }
( cd "$P" && bash "$CG" --repair --branch-protection-attested ) >/dev/null 2>&1
before=$(jq -c '.phase2_init.attestations' "$P/.claude/process-state.json")
out=$( cd "$P" && bash "$CG" --repair --branch-protection-attested 2>&1 ); rc=$?
after=$(jq -c '.phase2_init.attestations' "$P/.claude/process-state.json")
if [ "$before" != "$after" ]; then
  fail_ "T-idempotent" "attestation changed on the second --repair (before=$before after=$after)"
elif [ "$(step_count "$P" remote_repo_created)" != "1" ] || [ "$(step_count "$P" pushed_initial)" != "1" ]; then
  fail_ "T-idempotent" "markers duplicated on re-run (remote_repo_created x$(step_count "$P" remote_repo_created), pushed_initial x$(step_count "$P" pushed_initial))"
elif [ "$rc" -ne 0 ]; then
  fail_ "T-idempotent" "second --repair exited $rc — a recovered project must stay a clean no-op"
else
  pass "T-idempotent"
fi

# ── T-mutation-fence-excision ────────────────────────────────────────────────
# Excise the BL-157 fence from a COPY → the single-shot attestation must
# regress to the BL-123 refusal (nothing reconciles the markers first).
echo "=== T-mutation-fence-excision ==="
MUT="$TOPTMP/mut"
mkdir -p "$MUT/scripts/lib"
cp "$REPO_ROOT"/scripts/lib/*.sh "$MUT/scripts/lib/" 2>/dev/null || true
if ! grep -q "BL-157-REMOTE-MARKER-BEGIN" "$CG"; then
  fail_ "T-mutation-fence-excision" "no BL-157-REMOTE-MARKER fence in check-gate.sh — fix not in place"
else
  sed '/# BL-157-REMOTE-MARKER-BEGIN/,/# BL-157-REMOTE-MARKER-END/d' "$CG" > "$MUT/scripts/check-gate.sh"
  chmod +x "$MUT/scripts/check-gate.sh"
  if ! bash -n "$MUT/scripts/check-gate.sh" 2>/dev/null; then
    fail_ "T-mutation-fence-excision" "excised mutant is syntactically broken — keep the reconciler inside its fence"
  else
    P="$TOPTMP/p-mut-excise"
    mk_manual_remote_world "$P" github || true
    ( cd "$P" && bash "$MUT/scripts/check-gate.sh" --repair --branch-protection-attested ) >/dev/null 2>&1 || true
    if [ -z "$(attest_reason "$P")" ]; then
      pass "T-mutation-fence-excision (reconciler removed → single-shot attest REFUSES again)"
    else
      fail_ "T-mutation-fence-excision" "fence excised but the attestation was still recorded — the fix is not contained by its fence"
    fi
  fi
fi

# ── T-mutation-unconditional ─────────────────────────────────────────────────
# Break the GENUINE detection so it fabricates a `main` head regardless of what
# the remote actually carries (records unconditionally). Against the b2 fixture
# (origin exists, NOTHING pushed) the mutant now records pushed_initial and the
# BL-123 attestation gets written on an unpushed remote — proving the detection
# guard is what protects the BL-123 precondition.
echo "=== T-mutation-unconditional ==="
if ! grep -q "git ls-remote --heads origin 2>/dev/null" "$CG"; then
  fail_ "T-mutation-unconditional" "BL-157 ls-remote detection probe not found — cannot mutate the guard"
else
  sed 's|git ls-remote --heads origin 2>/dev/null|printf "x refs/heads/main"|' "$CG" > "$MUT/scripts/check-gate.sh"
  chmod +x "$MUT/scripts/check-gate.sh"
  if ! bash -n "$MUT/scripts/check-gate.sh" 2>/dev/null; then
    fail_ "T-mutation-unconditional" "mutant is syntactically broken"
  else
    P="$TOPTMP/p-mut-uncond"
    mk_empty_remote_world "$P" github || true
    ( cd "$P" && bash "$MUT/scripts/check-gate.sh" --repair --branch-protection-attested ) >/dev/null 2>&1 || true
    if [ -n "$(attest_reason "$P")" ]; then
      pass "T-mutation-unconditional (unconditional detection re-opens the BL-123 hole on an unpushed remote → guard is load-bearing)"
    else
      fail_ "T-mutation-unconditional" "the unconditional mutant did NOT record an attestation on the unpushed remote — the genuine-detection guard is not the thing protecting BL-123"
    fi
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
