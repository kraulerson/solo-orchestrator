#!/usr/bin/env bash
# tests/test-bl123-bp-attestation-recovery.sh — BL-123/BL-111/BL-126: the
# branch-protection attestation must be RECORDABLE post-hoc, and honored by
# all three of its consumers.
#
# WHY THIS EXISTS (Dogfood-2 F-DF2-002 + BL-111 + F-DF2-005)
#   The `github_free_tier` attestation was writable ONLY inside init.sh's
#   in-flight 403 fallback. A non-interactive first run that met the 403
#   WITHOUT the flag pre-set was unrecoverable: `check-gate.sh --repair`
#   re-hit the 403 and recommended `--branch-protection-attested` — a flag
#   check-gate did not accept — and re-running init.sh died on "Name already
#   exists". Only destroy-and-recreate escaped (BL-123; BL-111 is the
#   hermetic-path sibling). Separately, `process-checklist.sh --verify-init`
#   was the ONE consumer of three that ignored a recorded attestation and
#   FAILed an honestly-attested free-tier scaffold (BL-126).
#
# CASES
#   T-repair-records-flag      unattested 403-world fixture + `--repair
#                              --branch-protection-attested` → the attestation
#                              is RECORDED (host-keyed reason) + both bp steps
#                              marked + rc 0 via the attested short-circuit.
#   T-repair-records-env       same via SOLO_BP_ATTESTED=1.
#   T-repair-no-silent-default plain `--repair` (no flag/env) must NOT write an
#                              attestation — explicit only, never inferred.
#   T-repair-idempotent        flag on an ALREADY-attested fixture → no-op
#                              notice, attestation unchanged (no double-write).
#   T-gitlab-reason            gitlab-host fixture + flag → reason
#                              gitlab_free_tier_approvals (host-keyed, matching
#                              the BL-032 short-circuit's expectations).
#   T-verify-init-honors       (BL-126) an ATTESTED github fixture →
#                              `--verify-init` reports branch protection [OK]
#                              via the attestation WITHOUT any host API probe
#                              (hermetically provable: no gh/network exists
#                              here, so reaching the API probe FAILs).
#   T-mutation-*               excise each marker fence from a COPY → its case
#                              regresses (recorder gone → nothing recorded;
#                              consult gone → verify-init FAILs the attested
#                              fixture).
#
# REGISTRATION: no init.sh, not an aggregator → BOTH lists.
# Hermetic: mktemp fixtures, fake remote URL never contacted, no host API
# reachable (that unreachability IS the assertion medium). bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CG="$REPO_ROOT/scripts/check-gate.sh"
PC="$REPO_ROOT/scripts/process-checklist.sh"

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
trap 'rm -rf "$TOPTMP"' EXIT

# mk_403_world <dir> <host> [attested] — a project that created+pushed its
# remote and then hit the tier 403: remote_repo_created + pushed_initial are
# recorded, branch protection is NOT, and no attestation exists (unless
# "attested" is passed, simulating a recorded github_free_tier).
mk_403_world() {
  local d="$1" host="$2" attested="${3:-}"
  rm -rf "$d"
  mkdir -p "$d/.claude"
  ( cd "$d" \
      && git init -q \
      && git config user.email "bl123@test.invalid" \
      && git config user.name  "BL-123 Test" \
      && echo "# x" > README.md && git add README.md && git commit -q -m "chore: init" \
      && git remote add origin "https://example.invalid/x.git" ) || return 1
  printf '{"frameworkVersion":"test","host":"%s","mode":"personal","deployment":"organizational","enforcement_level":"strict"}\n' "$host" > "$d/.claude/manifest.json"
  if [ -n "$attested" ]; then
    jq -n '{phase2_init:{steps_completed:["remote_repo_created","pushed_initial","branch_protection_configured","branch_protection_verified"],attestations:{branch_protection:{attested_by:"orchestrator",at:"2026-07-15T00:00:00Z",reason:"github_free_tier"}},verified:false},build_loop:{feature:null,step:0,steps_completed:[]}}' > "$d/.claude/process-state.json"
  else
    jq -n '{phase2_init:{steps_completed:["remote_repo_created","pushed_initial"],verified:false},build_loop:{feature:null,step:0,steps_completed:[]}}' > "$d/.claude/process-state.json"
  fi
}

attest_reason() { jq -r '.phase2_init.attestations.branch_protection.reason // ""' "$1/.claude/process-state.json"; }
step_recorded()  { jq -e --arg s "$2" '.phase2_init.steps_completed | index($s) != null' "$1/.claude/process-state.json" >/dev/null 2>&1; }

# ── T-repair-records-flag ────────────────────────────────────────────────────
echo "=== T-repair-records-flag ==="
P="$TOPTMP/p-flag"
mk_403_world "$P" github
out=$( cd "$P" && bash "$CG" --repair --branch-protection-attested 2>&1 ); rc=$?
if [ "$(attest_reason "$P")" != "github_free_tier" ]; then
  fail_ "T-repair-records-flag" "no github_free_tier attestation recorded (rc=$rc) — the documented --repair remediation still cannot record it (BL-123's circle): $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
elif ! step_recorded "$P" branch_protection_configured || ! step_recorded "$P" branch_protection_verified; then
  fail_ "T-repair-records-flag" "attestation recorded but the two bp steps were not (init.sh records both — --repair must match)"
elif [ "$rc" -ne 0 ]; then
  fail_ "T-repair-records-flag" "attestation recorded but --repair still exited $rc (the attested short-circuit did not fire): $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
else
  pass "T-repair-records-flag"
fi

# ── T-repair-records-env ─────────────────────────────────────────────────────
echo "=== T-repair-records-env ==="
P="$TOPTMP/p-env"
mk_403_world "$P" github
out=$( cd "$P" && SOLO_BP_ATTESTED=1 bash "$CG" --repair 2>&1 ); rc=$?
if [ "$(attest_reason "$P")" = "github_free_tier" ] && [ "$rc" -eq 0 ]; then
  pass "T-repair-records-env"
else
  fail_ "T-repair-records-env" "reason='$(attest_reason "$P")' rc=$rc — SOLO_BP_ATTESTED=1 not honored"
fi

# ── T-no-steps-refused ───────────────────────────────────────────────────────
# Verifier finding A: the recorder must mirror the sibling short-circuit's
# preconditions — remote_repo_created AND pushed_initial recorded — before
# writing. Without the guard, a project whose remote creation actually FAILED
# could record a github_free_tier attestation that 3 of 4 consumers then
# honor (a laundered green Phase 1→2 gate on a repo-less project).
echo "=== T-no-steps-refused ==="
P="$TOPTMP/p-nosteps"
rm -rf "$P"
mkdir -p "$P/.claude"
( cd "$P" && git init -q && git config user.email t@t.invalid && git config user.name t \
    && echo x > README.md && git add README.md && git commit -q -m "chore: init" ) || true
printf '{"frameworkVersion":"test","host":"github","mode":"personal","deployment":"organizational","enforcement_level":"strict"}\n' > "$P/.claude/manifest.json"
jq -n '{phase2_init:{steps_completed:[],verified:false},build_loop:{feature:null,step:0,steps_completed:[]}}' > "$P/.claude/process-state.json"
out=$( cd "$P" && bash "$CG" --repair --branch-protection-attested 2>&1 ); rc=$?
if [ -n "$(attest_reason "$P")" ]; then
  fail_ "T-no-steps-refused" "an attestation was RECORDED on a project with no remote_repo_created/pushed_initial on record — the laundering hole (verifier finding A): $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
elif ! printf '%s' "$out" | grep -qi "precondition\|remote_repo_created"; then
  fail_ "T-no-steps-refused" "refused, but without naming the unmet preconditions: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
else
  pass "T-no-steps-refused"
fi

# ── T-provenance-recorded ────────────────────────────────────────────────────
# Verifier finding B: a post-hoc attestation must be DISTINGUISHABLE from
# init's witnessed-at-403 write — an auditor reading process-state should see
# where it came from.
echo "=== T-provenance-recorded ==="
P="$TOPTMP/p-prov"
mk_403_world "$P" github
( cd "$P" && bash "$CG" --repair --branch-protection-attested ) >/dev/null 2>&1
prov=$(jq -r '.phase2_init.attestations.branch_protection.recorded_via // ""' "$P/.claude/process-state.json")
if [ "$prov" = "check-gate-repair" ]; then
  pass "T-provenance-recorded"
else
  fail_ "T-provenance-recorded" "recorded_via='$prov', want 'check-gate-repair' — the post-hoc write is indistinguishable from init's in-flight one"
fi

# ── T-other-attested-noop ────────────────────────────────────────────────────
# Verifier finding C: init.sh's 'other'-host attestation is REASONLESS
# (attested_by + at only). The flag on such an already-attested healthy
# project must be a NO-OP (idempotency keyed on the attestation's presence,
# not on .reason) — not a host-keyed refusal.
echo "=== T-other-attested-noop ==="
P="$TOPTMP/p-other"
rm -rf "$P"
mkdir -p "$P/.claude"
( cd "$P" && git init -q && git config user.email t@t.invalid && git config user.name t \
    && echo x > README.md && git add README.md && git commit -q -m "chore: init" \
    && git remote add origin "https://example.invalid/x.git" ) || true
printf '{"frameworkVersion":"test","host":"other","mode":"personal","deployment":"personal","enforcement_level":"light"}\n' > "$P/.claude/manifest.json"
jq -n '{phase2_init:{steps_completed:["remote_repo_created","pushed_initial","branch_protection_configured","branch_protection_verified"],attestations:{branch_protection:{attested_by:"orchestrator",at:"2026-07-10T00:00:00Z"}},verified:false},build_loop:{feature:null,step:0,steps_completed:[]}}' > "$P/.claude/process-state.json"
before=$(jq -c '.phase2_init.attestations' "$P/.claude/process-state.json")
out=$( cd "$P" && bash "$CG" --repair --branch-protection-attested 2>&1 ); rc=$?
after=$(jq -c '.phase2_init.attestations' "$P/.claude/process-state.json")
if [ "$before" = "$after" ] && ! printf '%s' "$out" | grep -q "host-keyed"; then
  pass "T-other-attested-noop"
else
  fail_ "T-other-attested-noop" "an already-attested 'other'-host project got the host-keyed refusal (rc=$rc) or a rewrite — idempotency must key on the attestation's presence, not .reason: $(printf '%s' "$out" | tail -1)"
fi

# ── T-repair-no-silent-default ───────────────────────────────────────────────
echo "=== T-repair-no-silent-default ==="
P="$TOPTMP/p-plain"
mk_403_world "$P" github
out=$( cd "$P" && bash "$CG" --repair 2>&1 ); rc=$?
if [ -n "$(attest_reason "$P")" ]; then
  fail_ "T-repair-no-silent-default" "a plain --repair (no flag, no env) WROTE an attestation — attestations must be explicit, never inferred"
else
  pass "T-repair-no-silent-default (rc=$rc, attestation untouched)"
fi

# ── T-repair-idempotent ──────────────────────────────────────────────────────
echo "=== T-repair-idempotent ==="
P="$TOPTMP/p-idem"
mk_403_world "$P" github attested
before=$(jq -c '.phase2_init.attestations' "$P/.claude/process-state.json")
out=$( cd "$P" && bash "$CG" --repair --branch-protection-attested 2>&1 ); rc=$?
after=$(jq -c '.phase2_init.attestations' "$P/.claude/process-state.json")
if [ "$before" = "$after" ] && [ "$rc" -eq 0 ]; then
  pass "T-repair-idempotent"
else
  fail_ "T-repair-idempotent" "attestation changed on re-run (before=$before after=$after rc=$rc)"
fi

# ── T-gitlab-reason ──────────────────────────────────────────────────────────
echo "=== T-gitlab-reason ==="
P="$TOPTMP/p-gitlab"
mk_403_world "$P" gitlab
out=$( cd "$P" && bash "$CG" --repair --branch-protection-attested 2>&1 ); rc=$?
if [ "$(attest_reason "$P")" = "gitlab_free_tier_approvals" ] && [ "$rc" -eq 0 ]; then
  pass "T-gitlab-reason"
else
  fail_ "T-gitlab-reason" "reason='$(attest_reason "$P")' rc=$rc — the recorded reason must be host-keyed so the BL-032 short-circuit recognizes it"
fi

# ── T-verify-init-honors (BL-126) ────────────────────────────────────────────
echo "=== T-verify-init-honors ==="
P="$TOPTMP/p-vi"
mk_403_world "$P" github attested
cp -R "$REPO_ROOT/scripts" "$P/scripts" >/dev/null 2>&1 || true
out=$( cd "$P" && bash scripts/process-checklist.sh --verify-init 2>&1 ); rc=$?
if printf '%s' "$out" | grep -q "branch_protection_configured" \
   && printf '%s' "$out" | grep -qi "attested" \
   && ! printf '%s' "$out" | grep -qE "\[FAIL\].*branch_protection"; then
  pass "T-verify-init-honors"
else
  fail_ "T-verify-init-honors" "an honestly-attested free-tier scaffold is not honored by --verify-init (BL-126 — 2 of 3 consumers honored it; this is the third): $(printf '%s' "$out" | grep -iE 'branch' | head -2 | tr '\n' ' ')"
fi

# ── T-mutation-bl123 / T-mutation-bl126 ──────────────────────────────────────
echo "=== T-mutation-bl123 ==="
MUT="$TOPTMP/mut"
mkdir -p "$MUT/scripts/lib"
cp "$REPO_ROOT"/scripts/lib/*.sh "$MUT/scripts/lib/" 2>/dev/null || true
if ! grep -q "BL-123-BP-ATTEST-RECORD-BEGIN" "$CG"; then
  fail_ "T-mutation-bl123" "no BL-123-BP-ATTEST-RECORD marker fence in check-gate.sh — fix not in place"
else
  sed '/# BL-123-BP-ATTEST-RECORD-BEGIN/,/# BL-123-BP-ATTEST-RECORD-END/d' "$CG" > "$MUT/scripts/check-gate.sh"
  chmod +x "$MUT/scripts/check-gate.sh"
  if ! bash -n "$MUT/scripts/check-gate.sh" 2>/dev/null; then
    fail_ "T-mutation-bl123" "excised mutant is syntactically broken — keep the recorder inside its fence"
  else
    P="$TOPTMP/p-mut123"
    mk_403_world "$P" github
    out=$( cd "$P" && bash "$MUT/scripts/check-gate.sh" --repair --branch-protection-attested 2>&1 ) || true
    if [ -n "$(attest_reason "$P")" ]; then
      fail_ "T-mutation-bl123" "recorder excised but an attestation was still written — the fence does not contain the write"
    else
      pass "T-mutation-bl123"
    fi
  fi
fi

echo "=== T-mutation-bl126 ==="
if ! grep -q "BL-126-ATTEST-CONSULT-BEGIN" "$PC"; then
  fail_ "T-mutation-bl126" "no BL-126-ATTEST-CONSULT marker fence in process-checklist.sh — fix not in place"
else
  P="$TOPTMP/p-mut126"
  mk_403_world "$P" github attested
  cp -R "$REPO_ROOT/scripts" "$P/scripts" >/dev/null 2>&1 || true
  sed '/# BL-126-ATTEST-CONSULT-BEGIN/,/# BL-126-ATTEST-CONSULT-END/d' "$PC" > "$P/scripts/process-checklist.sh"
  chmod +x "$P/scripts/process-checklist.sh"
  if ! bash -n "$P/scripts/process-checklist.sh" 2>/dev/null; then
    fail_ "T-mutation-bl126" "excised mutant is syntactically broken"
  else
    out=$( cd "$P" && bash scripts/process-checklist.sh --verify-init 2>&1 ) || true
    if printf '%s' "$out" | grep -q "branch_protection_configured" && printf '%s' "$out" | grep -qi "attested"; then
      fail_ "T-mutation-bl126" "consult excised but verify-init still honors the attestation — the fence does not contain the consult"
    else
      pass "T-mutation-bl126"
    fi
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
