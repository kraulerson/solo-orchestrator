#!/usr/bin/env bash
# tests/test-bl339-bl334-protection.sh — the two callers of the org-mode
# protection check that can record an attestation (the Phase 1→2 backstop in
# scripts/check-phase-gate.sh and `verify_init` in scripts/process-checklist.sh),
# checked against the right branch (`## BL-334:`) and honouring `## BL-274:`'s
# single-authority attestation for the one rule it can excuse (`## BL-339:`).
#
# THE DEFECTS.
#   BL-334  Both callers ran `host_verify_protection "main"`, and the push check
#           (`# BL-084-PUSH-VERIFY`) looked only for `main` or `master` on the
#           remote, so a project whose `.integration_branch` is `develop` had
#           `main` checked: a protected main passed while develop was
#           unprotected, and a protected develop failed on an unprotected main.
#   BL-339  host_verify_protection failed org mode on a required approving-review
#           count of 0, which a one-person organisation has to set (GitHub does
#           not count an author's approval of their own pull request), even with
#           the BL-274 attestation supplied.
#
# THE DECISIONS (Karl, 2026-10-08). BL-334: read `.integration_branch // "main"`
# in all three places, today's behaviour when the key is absent, and keep the
# push check's `master` fallback. BL-339: accept a count of 0 only while the
# attestation stands, as a new `branch_protection.reason` tied to it; without
# it the check fails as today; every other protection rule is unchanged.
# "Stands" is defined in scripts/lib/host.sh above host_single_authority_reason:
# the pair is in the environment of this run with a reason that is not blank.
#
# WHAT THIS FILE PINS
#   B  the branch (BL-334)
#      B1 develop protected, main not: both callers pass       (red before)
#      B2 develop not protected, main is: both callers fail    (red before)
#      B3 key absent, or empty: main is checked, as before     (control)
#      Push check (supervisor decision 2026-10-20): key absent → main or master
#      on the remote, as before; key set → that branch only, no fallback.
#      B4 develop keyed, develop on the remote: pushed          (red before)
#      B5 key absent, master only: pushed                       (control)
#      B5m key absent, main only: pushed                        (control)
#      B6 develop keyed, main only on the remote: not pushed    (red before)
#      B8 develop keyed, master only on the remote: not pushed
#      B9 `dev` keyed, only `feature/dev` on the remote: not pushed
#      B9m key absent, only `feature/main` on the remote: not pushed
#      B7 a key that is not a branch name (`dev*`) is refused by both callers,
#         and the push check does not let it match develop as a glob
#   S  the single-authority attestation (BL-339), org mode, count 0
#      S1 attested: both callers accept it and record the reason  (red before)
#      S2 unattested: fails exactly as before, nothing recorded   (control)
#      S3 SOLO_SINGLE_AUTHORITY_ATTESTED=1 with a blank reason: refused
#      S4 SOLO_SINGLE_AUTHORITY_ATTESTED=yes is not an attestation (control)
#      S5 attested, but no status check: still fails (other rules unchanged)
#      S6 count 1, attested: verified as before, nothing recorded
#      S7 personal mode, count 0, attested: nothing to excuse, nothing recorded
#      S8 attested, the state file read-only: refused, file unchanged
#      S9 attested, the slot holds another attestation: refused, not overwritten
#      S9b the same when the slot holds something that is not an object
#      S15 attested with no state file yet: the record creates it
#      S10 the backstop and --verify-init reach the same verdict on S1-S4
#      S11 the record is never read back: a later unattested run fails
#      S12 the record is idempotent at one HEAD and re-pinned at a new one
#      S12b at one HEAD, a new reason or a new branch rewrites it
#      S16 no pull-request rule at all (not a count of 0): fails, attested or not
#      S13 a reason carrying a real newline cannot forge an [OK] line
#      S14 the accepted block names §XIV item 5 as BLOCKING and REMAINS UNMET,
#          and says nothing that reads as a finished check
#   D  the gitlab and bitbucket drivers excuse the same rule the same way:
#      D1 gitlab, D2 bitbucket — attested accepted and recorded, unattested fails
#      D3 gitlab, D4 bitbucket — direct pushes allowed (their pull-request
#         requirement) still fail under the attestation, nothing recorded
#   M  mutants, located by distance from a `# BL-334-*` / `# BL-339-*` marker,
#      one per new guard line, each with its killer named.
#
# Hermetic: `gh`, `glab` and `curl` are PATH stubs, the push remote is a local
# bare repository, and every fixture is under one mktemp -d.
# Runs on bash 3.2.57 (macOS) and 5.x: no associative arrays, no mapfile.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
WHY=""
pass()   { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_()  { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
setup_() { echo "  [SETUP] $1 — $2"; FAILED=$((FAILED + 1)); }

echo "  suite shell: ${BASH_VERSION}   subject shell: $(bash -c 'echo $BASH_VERSION')"

command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }

TOPTMP=$(mktemp -d "${TMPDIR:-/tmp}/bl339.XXXXXX")
trap 'chmod -R u+w "$TOPTMP" 2>/dev/null; rm -rf "$TOPTMP"' EXIT

REASON="Example Ltd has one technical director, who is both Senior Technical Authority and Orchestrator."
BP='.phase2_init.attestations.branch_protection'
NP=0
P=""

# ── fixtures ──────────────────────────────────────────────────────────
# mk_proj <root> <host> <mode> <integration_branch | - for absent> [init|none]
#   A Phase-2 project the gate otherwise clears (the walk006 fixture's shape),
#   with the host driver copied from <root> so a mutated driver is the one
#   loaded. `init` records the first-class push at init, so the BL-084/BL-116
#   push check is out of the way; `none` leaves it to apply.
mk_proj() {
  local root="$1" host="$2" mode="$3" ib="$4" push="${5:-init}" steps=""
  NP=$((NP + 1)); P="$TOPTMP/p$NP"
  mkdir -p "$P/.claude" "$P/docs/phase-0" "$P/scripts/host-drivers" "$P/bin" "$P/protect"
  printf 'frd\n'      > "$P/docs/phase-0/frd.md"
  printf 'journey\n'  > "$P/docs/phase-0/user-journey.md"
  printf 'contract\n' > "$P/docs/phase-0/data-contract.md"
  if [ "$ib" = "-" ]; then
    jq -n --arg h "$host" --arg m "$mode" '{frameworkVersion:"test", host:$h, mode:$m}' > "$P/.claude/manifest.json"
  else
    jq -n --arg h "$host" --arg m "$mode" --arg ib "$ib" \
      '{frameworkVersion:"test", host:$h, mode:$m, integration_branch:$ib}' > "$P/.claude/manifest.json"
  fi
  printf '{"current_phase":2,"deployment":"personal","gates":{"phase_0_to_1":"2026-01-01","phase_1_to_2":"2026-02-01"}}\n' \
    > "$P/.claude/phase-state.json"
  [ "$push" = init ] && steps='"remote_repo_created","pushed_initial"'
  printf '{"phase2_init":{"steps_completed":[%s]},"phase1_artifacts":{"data_classification":"public","zdr_attested":false}}\n' "$steps" \
    > "$P/.claude/process-state.json"
  cat > "$P/APPROVAL_LOG.md" <<'MD'
# APPROVAL_LOG

## Phase 0 → Phase 1
| Field | Value |
|---|---|
| Approver | Alice Signer |
| Date | 2026-01-01 |

## Phase 1 → Phase 2
| Field | Value |
|---|---|
| Approver | Alice Signer |
| Date | 2026-02-01 |
MD
  { echo "# PRODUCT_MANIFESTO"; echo ""
    for i in 1 2 3 4 5 6 7 8; do echo "## ${i}. Section ${i}"; echo "Filled content for section ${i}."; echo ""; done
  } > "$P/PRODUCT_MANIFESTO.md"
  { echo "# PROJECT_BIBLE"; echo ""
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do echo "## ${i}. Section ${i}"; echo "Content."; echo ""; done
  } > "$P/PROJECT_BIBLE.md"
  cp "$root/scripts/host-drivers/$host.sh" "$P/scripts/host-drivers/"
  ( cd "$P" && git init -q && git config user.email t@t.invalid && git config user.name "Test Operator" \
      && git config commit.gpgsign false && git add -A && git commit -qm init \
      && git remote add origin "https://github.com/example/repo.git" ) || return 1
  # The `gh` stub serves $P/protect/<branch>.json for that branch's protection,
  # and 404 for a branch with no file: the only network surface the driver has.
  cat > "$P/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"/protection"*)
    a="$*"; b="${a#*branches/}"; b="${b%%/protection*}"
    f="$(dirname "$0")/../protect/$b.json"
    if [ -f "$f" ]; then cat "$f"; exit 0; fi
    echo '{"message":"Branch not protected","status":"404"}' >&2; exit 1 ;;
esac
exit 0
STUB
  chmod +x "$P/bin/gh"
}

# protect <branch> <review-count> [status: yes|no]
protect() {
  local sc='"required_status_checks":{"strict":true,"contexts":["ci"]},'
  [ "${3:-yes}" = yes ] || sc=''
  printf '{"enforce_admins":{"enabled":true},"allow_force_pushes":{"enabled":false},%s"required_pull_request_reviews":{"required_approving_review_count":%s}}\n' \
    "$sc" "$2" > "$P/protect/$1.json"
}

# protect_nopr <branch> — every org rule except a pull-request rule: no
# required_pull_request_reviews object at all, so direct pushes are allowed
protect_nopr() {
  printf '{"enforce_admins":{"enabled":true},"allow_force_pushes":{"enabled":false},"required_status_checks":{"strict":true,"contexts":["ci"]}}\n' \
    > "$P/protect/$1.json"
}

_CLEAN_ENV="-u CI -u GH_TOKEN -u GITHUB_TOKEN -u SOLO_SINGLE_AUTHORITY_ATTESTED -u SOLO_SINGLE_AUTHORITY_ATTESTED_REASON"

# run_gate <root> [VAR=value ...] → OUT, RC, ISSUES
run_gate() {
  local root="$1"; shift
  # shellcheck disable=SC2086
  OUT=$(cd "$P" && PATH="$P/bin:$PATH" env $_CLEAN_ENV "$@" bash "$root/scripts/check-phase-gate.sh" </dev/null 2>&1); RC=$?
  ISSUES=$(printf '%s\n' "$OUT" | sed 's/^/ /' | sed -n 's/^.*[^0-9]\([0-9][0-9]*\) inconsistency(ies) found.*$/\1/p' | head -1)
  [ -n "$ISSUES" ] || { [ "$RC" -eq 0 ] && ISSUES=0; }
  [ -n "$ISSUES" ] || ISSUES="?"
}
# run_vi <root> [VAR=value ...] → VOUT, VRC
run_vi() {
  local root="$1"; shift
  # shellcheck disable=SC2086
  VOUT=$(cd "$P" && PATH="$P/bin:$PATH" env $_CLEAN_ENV "$@" bash "$root/scripts/process-checklist.sh" --verify-init </dev/null 2>&1); VRC=$?
}

# One-letter verdicts: A attested, F failed, O verified, - none of them.
bs_verdict() {
  printf '%s\n' "$OUT" | awk '/\[ATTESTED\].*Phase 1.*backstop:/ {print "A"; exit}
                              /\[FAIL\].*Phase 1.*backstop:/     {print "F"; exit}
                              /\[OK\].*Phase 1.*backstop: repo protection verified/ {print "O"; exit}' | grep . || echo "-"
}
vi_verdict() {
  printf '%s\n' "$VOUT" | awk '/\[ATTESTED\] branch_protection_configured/ {print "A"; exit}
                               /\[FAIL\].*branch_protection_configured/   {print "F"; exit}
                               /\[OK\].*branch_protection_configured/     {print "O"; exit}' | grep . || echo "-"
}
push_verdict() {
  printf '%s\n' "$OUT" | awk '/\[OK\].*push gate: remote has the branch/ {print "O"; exit}
                              /\[FAIL\].*push gate:/ {print "F"; exit}' | grep . || echo "-"
}
state() { jq -r "$1 // \"\"" "$P/.claude/process-state.json" 2>/dev/null || printf '<unreadable>'; }
step_marked() { jq -e '.phase2_init.steps_completed | index("branch_protection_configured") != null' "$P/.claude/process-state.json" >/dev/null 2>&1; }
cksum_state() { cksum < "$P/.claude/process-state.json"; }
lines() { printf '%s\n' "$1" | grep -E "$2" | tr '\n' ' ' | cut -c1-400; }

# local bare remote with the named branches, wired as origin
remote_with() {
  local r="$P.remote.git" b
  git init -q --bare "$r" || return 1
  ( cd "$P" && git remote set-url origin "$r" ) || return 1
  for b in "$@"; do ( cd "$P" && git push -q origin "HEAD:refs/heads/$b" ) || return 1; done
}

# ── B: the integration branch (BL-334) ────────────────────────────────
case_B1() {   # develop protected, main not
  mk_proj "$1" github personal develop; protect develop 1
  run_gate "$1"; local b; b=$(bs_verdict)
  run_vi "$1"; local v; v=$(vi_verdict)
  [ "$b" = O ] && [ "$RC" -eq 0 ] && [ "$v" = O ] && step_marked && return 0
  WHY="backstop=$b rc=$RC verify-init=$v: $(lines "$OUT$VOUT" 'backstop|branch_protection_configured')"; return 1
}
case_B2() {   # develop not protected, main is
  mk_proj "$1" github personal develop; protect main 1
  run_gate "$1"; local b; b=$(bs_verdict)
  run_vi "$1"; local v; v=$(vi_verdict)
  [ "$b" = F ] && [ "$RC" -ne 0 ] && [ "$v" = F ] && ! step_marked && return 0
  WHY="backstop=$b rc=$RC verify-init=$v: $(lines "$OUT$VOUT" 'backstop|branch_protection_configured')"; return 1
}
case_B3() {   # CONTROL: key absent, or empty — main is checked
  local k b1 b2
  for k in - ""; do
    mk_proj "$1" github personal "$k"; protect main 1; protect develop 1
    run_gate "$1"; b1=$(bs_verdict)
    mk_proj "$1" github personal "$k"; protect develop 1
    run_gate "$1"; b2=$(bs_verdict)
    [ "$b1" = O ] && [ "$b2" = F ] || { WHY="key '${k}': main protected → $b1 (want O); main unprotected → $b2 (want F)"; return 1; }
  done
  return 0
}
case_B4() {   # push check, develop on the remote
  mk_proj "$1" github personal develop none; remote_with develop || { WHY="remote setup"; return 3; }
  run_gate "$1"; local v; v=$(push_verdict)
  [ "$v" = O ] && return 0
  WHY="push gate=$v: $(lines "$OUT" 'push gate')"; return 1
}
case_B5() {   # CONTROL: key absent, master only on the remote
  mk_proj "$1" github personal - none; remote_with master || { WHY="remote setup"; return 3; }
  run_gate "$1"; local v; v=$(push_verdict)
  [ "$v" = O ] && return 0
  WHY="push gate=$v: $(lines "$OUT" 'push gate')"; return 1
}
case_B5m() {   # CONTROL: key absent, main only on the remote
  mk_proj "$1" github personal - none; remote_with main || { WHY="remote setup"; return 3; }
  run_gate "$1"; local v; v=$(push_verdict)
  [ "$v" = O ] && return 0
  WHY="push gate=$v: $(lines "$OUT" 'push gate')"; return 1
}
case_B8() {   # develop keyed, master only on the remote: no fallback once the key is set
  mk_proj "$1" github personal develop none; remote_with master || { WHY="remote setup"; return 3; }
  run_gate "$1"; local v; v=$(push_verdict)
  [ "$v" = F ] && return 0
  WHY="push gate=$v: $(lines "$OUT" 'push gate')"; return 1
}
case_B9() {   # `dev` keyed, only `feature/dev` on the remote: not pushed
  mk_proj "$1" github personal dev none; remote_with feature/dev || { WHY="remote setup"; return 3; }
  run_gate "$1"; local v; v=$(push_verdict)
  [ "$v" = F ] && return 0
  WHY="push gate=$v: $(lines "$OUT" 'push gate')"; return 1
}
case_B9m() {   # key absent, only `feature/main` on the remote: not pushed
  mk_proj "$1" github personal - none; remote_with feature/main || { WHY="remote setup"; return 3; }
  run_gate "$1"; local v; v=$(push_verdict)
  [ "$v" = F ] && return 0
  WHY="push gate=$v: $(lines "$OUT" 'push gate')"; return 1
}
case_B6() {   # develop keyed, main only on the remote
  mk_proj "$1" github personal develop none; remote_with main || { WHY="remote setup"; return 3; }
  run_gate "$1"; local v; v=$(push_verdict)
  [ "$v" = F ] && return 0
  WHY="push gate=$v: $(lines "$OUT" 'push gate')"; return 1
}
case_B7() {   # a key that is not a branch name
  local b v p
  mk_proj "$1" github personal 'dev*'; protect main 1
  run_gate "$1"; b=$(bs_verdict)
  printf '%s\n' "$OUT" | grep -q 'backstop: .integration_branch in .claude/manifest.json is not a branch name' \
    || { WHY="backstop=$b, no not-a-branch-name line: $(lines "$OUT" 'backstop')"; return 1; }
  [ "$b" = F ] && [ "$RC" -ne 0 ] || { WHY="backstop=$b rc=$RC"; return 1; }
  run_vi "$1"; v=$(vi_verdict)
  printf '%s\n' "$VOUT" | grep -q 'branch_protection_configured — .integration_branch in .claude/manifest.json is not a branch name' \
    && [ "$v" = F ] && ! step_marked || { WHY="verify-init=$v: $(lines "$VOUT" 'branch_protection')"; return 1; }
  mk_proj "$1" github personal 'dev*' none; remote_with develop || { WHY="remote setup"; return 3; }
  run_gate "$1"; p=$(push_verdict)
  [ "$p" = F ] && printf '%s\n' "$OUT" | grep -q 'push gate: .integration_branch in .claude/manifest.json is not a branch name' \
    || { WHY="push gate=$p with 'dev*' keyed and develop on the remote: $(lines "$OUT" 'push gate')"; return 1; }
  return 0
}

# ── S: the single-authority attestation (BL-339) ──────────────────────
# org mode, main protected with every org rule except a review count of 0
org_zero() { mk_proj "$1" github org -; protect main 0; }
att_block() { printf '%s\n' "$1" | awk '/\[ATTESTED\]/{f=1} f{print} f && /## BL-339:/{exit}'; }

case_S1() {   # attested: both callers accept it and record the reason
  local head b v
  org_zero "$1"; head=$(cd "$P" && git rev-parse HEAD)
  run_gate "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON"; b=$(bs_verdict)
  [ "$b" = A ] && [ "$RC" -eq 0 ] || { WHY="backstop=$b rc=$RC issues=$ISSUES: $(lines "$OUT" 'backstop|BLOCKED|ATTESTED')"; return 1; }
  [ "$(state "$BP.reason")" = single_authority_approvals ] \
    && [ "$(state "$BP.single_authority_reason")" = "$REASON" ] \
    && [ "$(state "$BP.branch")" = main ] && [ "$(state "$BP.head")" = "$head" ] \
    && [ "$(state "$BP.recorded_via")" = check-phase-gate ] \
    || { WHY="record after the backstop: $(jq -c "$BP" "$P/.claude/process-state.json" 2>&1)"; return 1; }
  org_zero "$1"
  run_vi "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON"; v=$(vi_verdict)
  [ "$v" = A ] && step_marked && [ "$(state "$BP.reason")" = single_authority_approvals ] \
    && [ "$(state "$BP.recorded_via")" = verify-init ] \
    && ! printf '%s\n' "$VOUT" | grep -q '\[OK\].*branch_protection_configured' \
    || { WHY="verify-init=$v: $(lines "$VOUT" 'branch_protection|ATTESTED|BLOCKED') record: $(jq -c "$BP" "$P/.claude/process-state.json" 2>&1)"; return 1; }
  return 0
}
case_S2() {   # CONTROL: unattested — fails exactly as before; one issue more than count 1
  local b base
  mk_proj "$1" github org -; protect main 1
  run_gate "$1"; base=$ISSUES
  org_zero "$1"
  run_gate "$1"; b=$(bs_verdict)
  [ "$b" = F ] && [ "$RC" -ne 0 ] && [ "$ISSUES" = "$((base + 1))" ] && [ "$(state "$BP.reason")" = "" ] \
    && ! printf '%s\n' "$OUT" | grep -qE '\[ATTESTED\]|\[BLOCKED\]' && return 0
  WHY="backstop=$b rc=$RC issues=$ISSUES (count-1 control: $base) record='$(state "$BP.reason")'"; return 1
}
case_S3() {   # attested with a blank reason: refused
  local b v
  org_zero "$1"
  run_gate "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=   "; b=$(bs_verdict)
  [ "$b" = F ] && [ "$RC" -ne 0 ] && [ "$(state "$BP.reason")" = "" ] \
    && printf '%s\n' "$OUT" | grep -q '\[BLOCKED\] Phase 1→2 backstop: .*SOLO_SINGLE_AUTHORITY_ATTESTED=1 was set with no reason' \
    && printf '%s\n' "$OUT" | grep -q 'Set SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=' \
    || { WHY="backstop=$b rc=$RC record='$(state "$BP.reason")': $(lines "$OUT" 'backstop|BLOCKED|REASON')"; return 1; }
  org_zero "$1"
  run_vi "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON="; v=$(vi_verdict)
  [ "$v" = F ] && ! step_marked && [ "$(state "$BP.reason")" = "" ] \
    && printf '%s\n' "$VOUT" | grep -q '\[BLOCKED\] branch_protection_configured: .*no reason' \
    || { WHY="verify-init=$v: $(lines "$VOUT" 'branch_protection|BLOCKED')"; return 1; }
  return 0
}
case_S4() {   # CONTROL: =yes is not an attestation
  local b
  org_zero "$1"
  run_gate "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=yes "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON"; b=$(bs_verdict)
  [ "$b" = F ] && [ "$RC" -ne 0 ] && [ "$(state "$BP.reason")" = "" ] \
    && ! printf '%s\n' "$OUT" | grep -qE '\[ATTESTED\]|\[BLOCKED\]' && return 0
  WHY="backstop=$b rc=$RC record='$(state "$BP.reason")'"; return 1
}
case_S5() {   # attested, but no status check: still fails
  local b
  mk_proj "$1" github org -; protect main 0 no
  run_gate "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON"; b=$(bs_verdict)
  [ "$b" = F ] && [ "$RC" -ne 0 ] && [ "$(state "$BP.reason")" = "" ] \
    && ! printf '%s\n' "$OUT" | grep -q '\[ATTESTED\]' && return 0
  WHY="backstop=$b rc=$RC record='$(state "$BP.reason")'"; return 1
}
case_S6() {   # count 1, attested: verified as before, nothing recorded
  local b
  mk_proj "$1" github org -; protect main 1
  run_gate "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON"; b=$(bs_verdict)
  [ "$b" = O ] && [ "$RC" -eq 0 ] && [ "$(state "$BP.reason")" = "" ] && return 0
  WHY="backstop=$b rc=$RC record='$(state "$BP.reason")'"; return 1
}
case_S7() {   # personal mode, count 0, attested: nothing to excuse
  local b
  mk_proj "$1" github personal -; protect main 0
  run_gate "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON"; b=$(bs_verdict)
  [ "$b" = O ] && [ "$RC" -eq 0 ] && [ "$(state "$BP.reason")" = "" ] && return 0
  WHY="backstop=$b rc=$RC record='$(state "$BP.reason")'"; return 1
}
case_S8() {   # attested, the state file read-only: refused, unchanged
  local b v before
  org_zero "$1"; chmod 444 "$P/.claude/process-state.json"; before=$(cksum_state)
  if [ -w "$P/.claude/process-state.json" ]; then WHY="a 0444 file is writable here (running as root?)"; return 4; fi
  run_gate "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON"; b=$(bs_verdict)
  [ "$RC" -ne 0 ] && [ "$(cksum_state)" = "$before" ] \
    && printf '%s\n' "$OUT" | grep -q '\[FAIL\] Phase 1→2 backstop: a single-authority attestation was supplied but COULD NOT BE RECORDED' \
    && ! printf '%s\n' "$OUT" | grep -qE '\[ATTESTED\]|backstop: repo protection verified|backstop: protection verification failed' \
    || { WHY="backstop=$b rc=$RC changed=$([ "$(cksum_state)" = "$before" ] && echo no || echo yes): $(lines "$OUT" 'backstop|ATTESTED|RECORDED')"; return 1; }
  run_vi "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON"; v=$(vi_verdict)
  [ "$(cksum_state)" = "$before" ] && ! step_marked \
    && printf '%s\n' "$VOUT" | grep -q 'branch_protection_configured: a single-authority attestation was supplied but COULD NOT BE RECORDED' \
    && ! printf '%s\n' "$VOUT" | grep -qE '\[ATTESTED\]|protection verification failed' \
    || { WHY="verify-init=$v: $(lines "$VOUT" 'branch_protection|RECORDED')"; return 1; }
  return 0
}
case_S9() {   # attested, the slot holds another attestation: refused, not overwritten
  local before
  org_zero "$1"
  jq "$BP = {attested_by:\"orchestrator\", at:\"2026-01-01T00:00:00Z\"}" "$P/.claude/process-state.json" > "$P/s.tmp" \
    && mv "$P/s.tmp" "$P/.claude/process-state.json"
  before=$(cksum_state)
  run_gate "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON"
  [ "$RC" -ne 0 ] && [ "$(cksum_state)" = "$before" ] \
    && printf '%s\n' "$OUT" | grep -q 'COULD NOT BE RECORDED.*already holds another attestation' && return 0
  WHY="rc=$RC changed=$([ "$(cksum_state)" = "$before" ] && echo no || echo yes): $(lines "$OUT" 'backstop|RECORDED')"; return 1
}
case_S9b() {   # attested, the slot holds something that is not an object: refused, not overwritten
  local before
  org_zero "$1"
  jq "$BP = \"hand-written\"" "$P/.claude/process-state.json" > "$P/s.tmp" && mv "$P/s.tmp" "$P/.claude/process-state.json"
  before=$(cksum_state)
  run_gate "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON"
  [ "$RC" -ne 0 ] && [ "$(cksum_state)" = "$before" ] \
    && printf '%s\n' "$OUT" | grep -q 'COULD NOT BE RECORDED.*not a JSON object' && return 0
  WHY="rc=$RC changed=$([ "$(cksum_state)" = "$before" ] && echo no || echo yes): $(lines "$OUT" 'backstop|RECORDED')"; return 1
}
case_S15() {   # attested, no state file yet: the record creates it
  local b
  org_zero "$1"; rm -f "$P/.claude/process-state.json"
  run_gate "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON"; b=$(bs_verdict)
  [ "$b" = A ] && [ "$(state "$BP.reason")" = single_authority_approvals ] && return 0
  WHY="backstop=$b record='$(state "$BP.reason")': $(lines "$OUT" 'backstop|RECORDED')"; return 1
}
case_S10() {   # the two callers agree
  local e b v got=""
  for e in attested blank yes none; do
    org_zero "$1"
    case "$e" in
      attested) run_gate "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON" ;;
      blank)    run_gate "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON= " ;;
      yes)      run_gate "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=yes "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON" ;;
      none)     run_gate "$1" ;;
    esac
    b=$(bs_verdict)
    org_zero "$1"
    case "$e" in
      attested) run_vi "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON" ;;
      blank)    run_vi "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON= " ;;
      yes)      run_vi "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=yes "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON" ;;
      none)     run_vi "$1" ;;
    esac
    v=$(vi_verdict)
    got="$got $e:$b/$v"
  done
  [ "$got" = " attested:A/A blank:F/F yes:F/F none:F/F" ] && return 0
  WHY="backstop/verify-init verdicts:$got (want attested:A/A blank:F/F yes:F/F none:F/F)"; return 1
}
case_S11() {   # never read back: a later unattested run fails as before
  local b
  org_zero "$1"
  run_gate "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON"
  [ "$(state "$BP.reason")" = single_authority_approvals ] || { WHY="premise: the attested run recorded nothing"; return 3; }
  run_gate "$1"; b=$(bs_verdict)
  [ "$b" = F ] && [ "$RC" -ne 0 ] && return 0
  WHY="a run without the attestation, after one with it: backstop=$b rc=$RC"; return 1
}
case_S12b() {   # at one HEAD, a new reason or a new branch rewrites the record
  local h
  org_zero "$1"; protect develop 0; h=$(cd "$P" && git rev-parse HEAD)
  run_gate "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON"
  [ "$(state "$BP.single_authority_reason")" = "$REASON" ] || { WHY="premise: nothing recorded"; return 3; }
  run_gate "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=A second, corrected reason."
  [ "$(state "$BP.single_authority_reason")" = "A second, corrected reason." ] \
    || { WHY="a new reason at the same HEAD kept '$(state "$BP.single_authority_reason")'"; return 1; }
  jq '.integration_branch = "develop"' "$P/.claude/manifest.json" > "$P/m.tmp" && mv "$P/m.tmp" "$P/.claude/manifest.json"
  run_gate "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=A second, corrected reason."
  [ "$(state "$BP.branch")" = develop ] && [ "$(state "$BP.head")" = "$h" ] && return 0
  WHY="a new branch at the same HEAD left branch='$(state "$BP.branch")' head='$(state "$BP.head")'"; return 1
}
case_S16() {   # no pull-request rule: fails, attested or not, and nothing is recorded
  local b v
  mk_proj "$1" github org -; protect_nopr main
  run_gate "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON"; b=$(bs_verdict)
  [ "$b" = F ] && [ "$RC" -ne 0 ] && [ "$(state "$BP.reason")" = "" ] \
    || { WHY="backstop=$b rc=$RC record='$(state "$BP.reason")': $(lines "$OUT" 'backstop|ATTESTED')"; return 1; }
  run_vi "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON"; v=$(vi_verdict)
  [ "$v" = F ] && ! step_marked && [ "$(state "$BP.reason")" = "" ] \
    || { WHY="verify-init=$v: $(lines "$VOUT" 'branch_protection|ATTESTED')"; return 1; }
  OUT=$(cd "$P" && PATH="$P/bin:$PATH" env $_CLEAN_ENV SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON" \
        bash -c '. "$1/scripts/lib/host.sh" && host_load_driver && host_verify_protection_attested U main org unit' _ "$1" </dev/null 2>&1)
  printf '%s\n' "$OUT" | grep -q 'pull requests are not required on main' && return 0
  WHY="the driver does not name the missing pull-request rule: $(lines "$OUT" '.')"; return 1
}
case_S12() {   # idempotent at one HEAD, re-pinned at a new one
  local h1 h2 before
  org_zero "$1"; h1=$(cd "$P" && git rev-parse HEAD)
  run_vi "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON"
  [ "$(state "$BP.recorded_via")" = verify-init ] || { WHY="premise: verify-init recorded nothing"; return 3; }
  before=$(jq -c "$BP" "$P/.claude/process-state.json")
  run_gate "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON"
  [ "$(jq -c "$BP" "$P/.claude/process-state.json")" = "$before" ] \
    || { WHY="a repeat at the same HEAD rewrote the record: $before → $(jq -c "$BP" "$P/.claude/process-state.json")"; return 1; }
  ( cd "$P" && git commit -q --allow-empty -m next ); h2=$(cd "$P" && git rev-parse HEAD)
  run_gate "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON"
  [ "$(state "$BP.head")" = "$h2" ] && [ "$h1" != "$h2" ] && return 0
  WHY="after a new commit the head is '$(state "$BP.head")', want $h2"; return 1
}
case_S13() {   # a real newline in the reason cannot forge a line
  local nl
  nl=$(printf 'x\n[OK] Phase 1→2 backstop: repo protection verified (forged)')
  org_zero "$1"
  run_gate "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$nl"
  printf '%s\n' "$OUT" | grep -q '\[ATTESTED\]' || { WHY="premise: not accepted: $(lines "$OUT" 'backstop')"; return 3; }
  if printf '%s\n' "$OUT" | grep -qE '^[[:space:]]*\[OK\].*forged'; then WHY="a forged [OK] line reached the transcript"; return 1; fi
  case "$(state "$BP.single_authority_reason")" in *"
"*) WHY="the record kept the newline"; return 1 ;; esac
  return 0
}
case_S14() {   # honesty of the accepted block
  local blk
  org_zero "$1"
  run_gate "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON"
  blk=$(att_block "$OUT")
  [ -n "$blk" ] || { WHY="no [ATTESTED] block"; return 1; }
  printf '%s\n' "$blk" | grep -q 'XIV item 5.*BLOCKING pre-condition and REMAINS UNMET' \
    || { WHY="the block does not name §XIV item 5 as a BLOCKING pre-condition that REMAINS UNMET"; return 1; }
  printf '%s\n' "$blk" | grep -q 'builders-guide.md § "Single-Authority Attestation"' \
    || { WHY="the block does not cite the shipped guide section"; return 1; }
  printf '%s\n' "$blk" | grep -qiE 'verified|satisfied|passed|complete' \
    && { WHY="the block uses the vocabulary of a finished check: $(printf '%s\n' "$blk" | grep -iE 'verified|satisfied|passed|complete' | head -1)"; return 1; }
  printf '%s\n' "$OUT" | grep -qE '\[OK\].*backstop' \
    && { WHY="an [OK]-led backstop line sits beside the attestation"; return 1; }
  return 0
}

# ── D: the gitlab and bitbucket drivers ───────────────────────────────
# drv_dir <root> <host> → $P: a repo with that origin, the driver from <root>, and stubs
drv_dir() {   # <root> <host> [push-open]
  local root="$1" host="$2" gl_push='[{"access_level":0}]' bb_push='{"kind":"push"},'
  [ "${3:-}" = push-open ] && { gl_push='[{"access_level":40}]'; bb_push=''; }
  NP=$((NP + 1)); P="$TOPTMP/d$NP"
  mkdir -p "$P/.claude" "$P/bin"
  printf '{}\n' > "$P/.claude/process-state.json"
  ( cd "$P" && git init -q && git config user.email t@t.invalid && git config user.name t \
      && git config commit.gpgsign false && git commit -q --allow-empty -m init ) || return 1
  case "$host" in
    gitlab)
      ( cd "$P" && git remote add origin https://gitlab.com/u/p.git )
      cat > "$P/bin/glab" <<STUB
#!/usr/bin/env bash
case "\$*" in
  *"protected_branches/main"*) echo '{"name":"main","allow_force_push":false,"push_access_levels":$gl_push}' ;;
  *"approval_rules"*)          echo '[]' ;;
  *"-X GET projects/"*)        echo '{"only_allow_merge_if_pipeline_succeeds":true}' ;;
esac
exit 0
STUB
      ;;
    bitbucket)
      ( cd "$P" && git remote add origin https://bitbucket.org/ws/repo.git )
      cat > "$P/bin/curl" <<STUB
#!/usr/bin/env bash
case "\$*" in
  *"branch-restrictions"*) echo '{"values":[{"kind":"force"},{"kind":"delete"},$bb_push{"kind":"require_passing_builds_to_merge","value":1}]}' ;;
esac
exit 0
STUB
      ;;
  esac
  chmod +x "$P/bin/"*
}
# drv_run <root> <host> [VAR=value ...] → OUT, RC (the wrapper's), from a shell
# that sources host.sh and the driver from <root>
drv_run() {
  local root="$1" host="$2"; shift 2
  # shellcheck disable=SC2086
  OUT=$(cd "$P" && PATH="$P/bin:$PATH" env $_CLEAN_ENV BITBUCKET_USER=u BITBUCKET_APP_PASSWORD=p BITBUCKET_WORKSPACE=ws "$@" \
        bash -c '. "$1/scripts/lib/host.sh" && . "$1/scripts/host-drivers/$2.sh" || exit 9
                 host_verify_protection_attested "Unit" main org unit; rc=$?
                 echo "rc=$rc state=${HOST_SA_STATE:-}"; exit $rc' _ "$root" "$host" </dev/null 2>&1); RC=$?
}
case_D() {   # <host> <the driver's unattested failure text>
  local root="$1" host="$2" msg="$3"
  drv_dir "$root" "$host"
  drv_run "$root" "$host"
  [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "$msg" && [ "$(state "$BP.reason")" = "" ] \
    || { WHY="unattested: rc=$RC: $(lines "$OUT" '.')"; return 1; }
  drv_run "$root" "$host" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON"
  [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q '\[ATTESTED\] Unit:' \
    && [ "$(state "$BP.reason")" = single_authority_approvals ] && [ "$(state "$BP.recorded_via")" = unit ] \
    || { WHY="attested: rc=$RC record='$(state "$BP.reason")': $(lines "$OUT" '.')"; return 1; }
  return 0
}
case_D_open() {   # <host> <the push failure text>: pull requests not required → fails even attested
  local root="$1" host="$2" msg="$3"
  drv_dir "$root" "$host" push-open
  drv_run "$root" "$host" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON"
  [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "$msg" && [ "$(state "$BP.reason")" = "" ] \
    && ! printf '%s\n' "$OUT" | grep -q '\[ATTESTED\]' && return 0
  WHY="attested, pushes open: rc=$RC record='$(state "$BP.reason")': $(lines "$OUT" '.')"; return 1
}
case_D3() { case_D_open "$1" gitlab 'push_access_level=40 on main'; }
case_D4() { case_D_open "$1" bitbucket 'push not restricted'; }
case_D1() { case_D "$1" gitlab 'no approval rule requires >= 1 approval'; }
case_D2() { case_D "$1" bitbucket 'approvals not required on PRs'; }

# ── run the cases against the tree ────────────────────────────────────
run_case() {   # <id> <function> <description>
  local rc=0
  WHY=""
  "$2" "$REPO_ROOT" || rc=$?
  case "$rc" in
    0) pass "$1 $3" ;;
    3|4) setup_ "$1" "$WHY" ;;
    *) fail_ "$1 $3" "$WHY" ;;
  esac
}
echo "B — the integration branch (BL-334)"
run_case B1 case_B1 "develop keyed and protected, main not: the backstop and --verify-init pass"
run_case B2 case_B2 "develop keyed, unprotected; main protected: both fail"
run_case B3 case_B3 "CONTROL — key absent or empty: main is checked"
run_case B4 case_B4 "push check: develop keyed and on the remote"
run_case B5 case_B5 "CONTROL — push check: key absent, master only on the remote"
run_case B5m case_B5m "CONTROL — push check: key absent, main only on the remote"
run_case B6 case_B6 "push check: develop keyed, only main on the remote"
run_case B8 case_B8 "push check: develop keyed, only master on the remote — no fallback once keyed"
run_case B9 case_B9 "push check: dev keyed, only feature/dev on the remote — an exact ref, not a tail"
run_case B9m case_B9m "push check: key absent, only feature/main on the remote — an exact ref, not a tail"
run_case B7 case_B7 "a key that is not a branch name is refused, and never matched as a glob"
echo "S — the single-authority attestation (BL-339)"
run_case S1  case_S1  "org, count 0, attested: both callers accept and record it"
run_case S2  case_S2  "CONTROL — org, count 0, unattested: fails as before, one issue"
run_case S3  case_S3  "attested with a blank reason: refused by both callers"
run_case S4  case_S4  "CONTROL — SOLO_SINGLE_AUTHORITY_ATTESTED=yes is not an attestation"
run_case S5  case_S5  "attested, no status check: still fails"
run_case S6  case_S6  "count 1, attested: verified, nothing recorded"
run_case S7  case_S7  "personal, count 0, attested: nothing to excuse"
run_case S8  case_S8  "attested, read-only state file: refused, unchanged"
run_case S9  case_S9  "attested, the slot holds another attestation: refused, unchanged"
run_case S9b case_S9b "attested, the slot holds a non-object: refused, unchanged"
run_case S15 case_S15 "attested, no state file yet: the record creates it"
run_case S10 case_S10 "the backstop and --verify-init agree on attested/blank/yes/none"
run_case S11 case_S11 "the record is never read back"
run_case S12 case_S12 "idempotent at one HEAD, re-pinned at the next"
run_case S12b case_S12b "at one HEAD, a new reason or branch rewrites the record"
run_case S16 case_S16 "no pull-request rule: fails attested, nothing recorded"
run_case S13 case_S13 "a real newline in the reason forges no line"
run_case S14 case_S14 "the accepted block keeps §XIV item 5 UNMET and claims no check"
echo "D — the gitlab and bitbucket drivers"
run_case D1 case_D1 "gitlab: count 0 accepted only under the attestation"
run_case D2 case_D2 "bitbucket: count 0 accepted only under the attestation"
run_case D3 case_D3 "gitlab: direct pushes allowed still fail under the attestation"
run_case D4 case_D4 "bitbucket: direct pushes allowed still fail under the attestation"

# ── MUTANTS ───────────────────────────────────────────────────────────
M=""
mirror()   { M=$(mktemp -d "$TOPTMP/m.XXXXXX"); cp -R "$REPO_ROOT/scripts" "$M/scripts"; }
unmirror() { [ -n "$M" ] && rm -rf "$M"; M=""; }

# mutate_at <file under scripts/> <anchor-literal> <offset> <from-literal> <to-literal>
#   The anchor must occur on exactly one line; the line at anchor+offset must
#   hold <from>; afterwards it holds <to> and not <from>, every other line is
#   byte-identical, and the file still parses. Otherwise return 3 with WHY set:
#   a [SETUP] failure, never a kill.
mutate_at() {
  local f="$M/scripts/$1" anchor="$2" off="$3" from="$4" to="$5" n aline target cur before after
  [ -f "$f" ] || { WHY="no $1 in the mirror"; return 3; }
  n=$(grep -c -F -- "$anchor" "$f" || true)
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  [ "$n" -eq 1 ] || { WHY="anchor '$anchor' occurs on $n lines of $1, need exactly 1"; return 3; }
  aline=$(grep -n -F -- "$anchor" "$f" | cut -d: -f1)
  target=$((aline + off))
  cur=$(sed -n "${target}p" "$f")
  case "$cur" in *"$from"*) ;; *) WHY="$1 anchor${off} does not hold '$from' (found: $cur)"; return 3 ;; esac
  before=$(sed "${target}d" "$f" | cksum)
  MT_LINE="$target" MT_FROM="$from" MT_TO="$to" \
    perl -pi -e 'if ($. == $ENV{MT_LINE}) { s/\Q$ENV{MT_FROM}\E/$ENV{MT_TO}/ }' "$f"
  cur=$(sed -n "${target}p" "$f")
  after=$(sed "${target}d" "$f" | cksum)
  case "$cur" in *"$to"*) ;; *) WHY="the mutation did not land: $cur"; return 3 ;; esac
  case "$to" in *"$from"*) ;; *) case "$cur" in *"$from"*) WHY="the original literal is still on the line"; return 3 ;; esac ;; esac
  [ "$before" = "$after" ] || { WHY="a line other than the target changed"; return 3; }
  bash -n "$f" 2>/dev/null || { WHY="the mutant does not parse"; return 3; }
}

# expect_kill <mutant-id> <case-id> <case-function>
expect_kill() {
  local rc=0
  WHY=""
  "$3" "$M" || rc=$?
  case "$rc" in
    0)   fail_ "$1" "SURVIVED — $2 stays green on the mutant" ;;
    3|4) setup_ "$1" "$2 could not run on the mutant: $WHY" ;;
    *)   pass "$1 killed by $2 ($(printf '%s' "$WHY" | cut -c1-160))" ;;
  esac
}

# mutant <id> <killer-id> <killer-fn> <file> <anchor> <offset> <from> <to>
mutant() {
  local id="$1" kid="$2" kfn="$3"; shift 3
  echo "$id: $1 ${2} ${3}: '$4' → '$5'  (killer $kid)"
  mirror
  if mutate_at "$@"; then expect_kill "$id" "$kid" "$kfn"; else setup_ "$id" "$WHY"; fi
  unmirror
}

H=lib/helpers-core.sh; G=check-phase-gate.sh; C=process-checklist.sh; L=lib/host.sh
echo "M — mutants"
# BL-334: the reader
mutant M1  B1 case_B1 "$H" '# BL-334-READ'    0 '.integration_branch // ""' '.no_such_key // ""'
mutant M2  B3 case_B3 "$H" '# BL-334-DEFAULT' 0 'ib="main"' 'ib="master"'
mutant M3  B7 case_B7 "$H" '# BL-334-REFNAME' 0 'git check-ref-format "refs/heads/$ib" 2>/dev/null || return 1' 'true'
# BL-334: the three places
mutant M4  B2 case_B2 "$G" '# BL-334-BACKSTOP-BRANCH' 4 '"$backstop_branch" "$mode"' '"main" "$mode"'
mutant M5  B7 case_B7 "$G" '# BL-334-BACKSTOP-BRANCH' 2 'issues=$((issues + 1))' ':'
mutant M6  B4 case_B4 "$G" '# BL-334-PUSH-KEYED' 0 '_bl084_brs="$bl084_ib"' ':'
mutant M7  B5 case_B5 "$G" '# BL-334-PUSH-KEYLESS' 0 '_bl084_brs="main master"' '_bl084_brs="main"'
mutant M41 B5m case_B5m "$G" '# BL-334-PUSH-KEYLESS' 0 '_bl084_brs="main master"' '_bl084_brs="master"'
mutant M39 B8 case_B8 "$G" '# BL-334-PUSH-KEYED' 0 '_bl084_brs="$bl084_ib"' '_bl084_brs="$bl084_ib master"'
mutant M40 B6 case_B6 "$G" '# BL-334-PUSH-KEYED' 0 '_bl084_brs="$bl084_ib"' '_bl084_brs="$bl084_ib main"'
mutant M8  B7 case_B7 "$G" '# BL-334-PUSH-BRANCH' 1 'is not a branch name' 'is fine'
mutant M9  B2 case_B2 "$C" '# BL-334-VERIFY-INIT-BRANCH' 5 '"$bp_branch" "$mode"' '"main" "$mode"'
mutant M10 B7 case_B7 "$C" '# BL-334-VERIFY-INIT-BRANCH' 1 'is not a branch name' 'is fine'
# BL-339: the predicate
mutant M11 S4 case_S4 "$L" '# BL-339-SA-OFFERED'  0 '= "1" ]' '!= "" ]'
TRLIT="| LC_ALL=C tr -d '\\000-\\037\\\\'"
mutant M12 S13 case_S13 "$L" '# BL-339-SA-SANITISE' 0 "$TRLIT" ''
mutant M13 S3 case_S3 "$L" '# BL-339-SA-REASON'   0 '[ -n "$_r" ] || return 1' 'true'
mutant M32 S3 case_S3 "$L" '# BL-339-SA-TRIM'      0 "| sed 's/^[[:space:]]*//;s/[[:space:]]*\$//'" '| cat'
# BL-339: the wrapper
mutant M14 S2 case_S2 "$L" '# BL-339-SA-ONLY-WHEN-STANDS' 0 'if [ "$_src" -eq 0 ]; then' 'if true; then'
mutant M15 S3 case_S3 "$L" '# BL-339-SA-REFUSED' 0 'HOST_SA_STATE="refused"' 'return "$_rc"'
mutant M16 S8 case_S8 "$L" '# BL-339-SA-UNRECORDED' 0 'return 3' 'return 0'
mutant M17 S5 case_S5 "$L" '# BL-339-SA-ACCEPT-ONLY-ON-PASS' 0 '[ "$_rc" -eq 0 ] || return "$_rc"' 'true'
mutant M35 S6 case_S6 "$L" '# BL-339-SA-NOTHING-TO-EXCUSE' 0 '[ -n "$HOST_VERIFY_APPROVALS_ZERO" ] || return "$_rc"' 'true'
mutant M36 S14 case_S14 "$L" '# BL-339-SA-ACCEPTED' 0 'HOST_SA_STATE="accepted"' 'HOST_SA_STATE=""'
# BL-339: the recorder
mutant M33 S15 case_S15 "$L" '# BL-339-RECORD-CREATE' 0 "printf '{}\\n' > \"\$_f\" 2>/dev/null" 'false'
mutant M34 S9b case_S9b "$L" '# BL-339-RECORD-READ' 0 'return 1; }' ': ; }'
mutant M18 S8 case_S8 "$L" '# BL-339-RECORD-WRITABLE' 0 '[ ! -w "$_f" ]' 'false'
mutant M19 S9 case_S9 "$L" '# BL-339-RECORD-FOREIGN'  -1 '*)' '*-never-)'
mutant M20 S12 case_S12 "$L" '# BL-339-RECORD-SAME'   0 'return 0' ':'
mutant M21 S1 case_S1 "$L" '# BL-339-RECORD-WRITE'    0 '&& mv "$_tmp" "$_f"' '&& rm -f "$_tmp"'
# BL-339: the callers
mutant M22 S14 case_S14 "$G" '# BL-339-NOT-VERIFIED' -1 '[ "$HOST_SA_STATE" = "accepted" ] \' 'false \'
mutant M23 S8 case_S8 "$G" '# BL-339-UNRECORDED' 0 'issues=$((issues + 1))' ':'
mutant M24 S8 case_S8 "$C" '# BL-339-VI-UNRECORDED' 0 '[ "$bp_rc" -eq 0 ]' '[ "$bp_rc" -eq 0 ] || [ "$bp_rc" -eq 3 ]'
mutant M25 S1 case_S1 "$C" '# BL-339-VI-NOT-VERIFIED' -1 '[ "$HOST_SA_STATE" = "accepted" ] \' 'false \'
mutant M37 S8 case_S8 "$G" '# BL-339-UNRECORDED' -1 'elif [ "$backstop_rc" -eq 3 ]; then' 'elif false; then'
mutant M38 S8 case_S8 "$C" '# BL-339-VI-NOT-VERIFIED' 1 'elif [ "$bp_rc" -ne 3 ]; then' 'elif true; then'
mutant M43 S12b case_S12b "$L" '# BL-339-RECORD-SAME' -2 '.single_authority_reason == $r and ' ''
mutant M44 S12b case_S12b "$L" '# BL-339-RECORD-SAME' -2 '.branch == $b and ' ''
mutant M45 B9 case_B9 "$G" '# BL-334-PUSH-EXACT' 0 '"refs/heads/$_bl084_br"' '"$_bl084_br"'
mutant M46 B9m case_B9m "$G" '# BL-334-PUSH-EXACT' 0 '"refs/heads/$_bl084_br"' '"$_bl084_br"'
# BL-339: the drivers
mutant M42 S16 case_S16 host-drivers/github.sh '# BL-339-PR-RULE' -1 'if [ "$val" = "absent" ]; then' 'if false; then'
mutant M47 S16 case_S16 host-drivers/github.sh '# BL-339-PR-RULE' -2 '.required_pull_request_reviews | if type == "object" then (.required_approving_review_count // 0 | tostring) else "absent" end' '.required_pull_request_reviews.required_approving_review_count // 0'
mutant M26 S1 case_S1 host-drivers/github.sh '# BL-339-APPROVALS-ZERO' 0 'HOST_VERIFY_APPROVALS_ZERO=1' ':'
mutant M27 S2 case_S2 host-drivers/github.sh '# BL-339-WAIVE' -1 '[ "${3:-}" = "single-authority" ]' 'true'
mutant M28 D1 case_D1 host-drivers/gitlab.sh '# BL-339-APPROVALS-ZERO' 0 'HOST_VERIFY_APPROVALS_ZERO=1' ':'
mutant M29 D1 case_D1 host-drivers/gitlab.sh '# BL-339-WAIVE' -1 '[ "${3:-}" = "single-authority" ]' 'true'
mutant M30 D2 case_D2 host-drivers/bitbucket.sh '# BL-339-APPROVALS-ZERO' 0 'HOST_VERIFY_APPROVALS_ZERO=1' ':'
mutant M31 D2 case_D2 host-drivers/bitbucket.sh '# BL-339-WAIVE' -1 '[ "${3:-}" = "single-authority" ]' 'true'

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
