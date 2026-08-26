#!/usr/bin/env bash
# tests/test-pr-review-gate.sh
#
# The push-time adversarial-review gate (Karl's decision, 2026-08-23).
# scripts/check-pr-review.sh refuses a push unless a review VERDICT is on record
# for exactly the HEAD being pushed; scripts/record-pr-review.sh writes it.
#
# WHAT THIS SUITE REFUSES TO ASSERT. It does not test that a review happened —
# nothing can. The gate verifies a RECORD, and an agent that writes the record
# dishonestly defeats it (`# BL-112-SAST-NOTRUN` is this repo's settled posture
# for that class). What is testable, and is tested here, is that every arm says
# the RIGHT THING: absent, stale and refused are three different situations with
# three different remedies, and collapsing them sends the operator to fix the
# wrong problem.
#
# Hermetic: temp git repos only, no remotes, no network. bash 3.2 safe.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$REPO_ROOT/scripts/check-pr-review.sh"
RECORD="$REPO_ROOT/scripts/record-pr-review.sh"

PASSED=0; FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
[ -n "$TOPTMP" ] && [ -d "$TOPTMP" ] || {
  echo "FATAL: mktemp -d failed — refusing to create fixtures in $PWD." >&2
  echo "  bash 3.2's \`cd \"\"\` returns 0 WITHOUT changing directory, so an unguarded" >&2
  echo "  fixture path runs git init/add/commit in the launch directory. Measured." >&2
  exit 1
}
trap 'chmod -R u+rwX "$TOPTMP" 2>/dev/null; rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { local _d; _d="$(mktemp -d "$TOPTMP/gXXXXXX")"; [ -n "$_d" ] && [ -d "$_d" ] || { echo "FATAL: newtmp failed" >&2; exit 1; }; printf '%s' "$_d"; }

for f in "$CHECK" "$RECORD"; do
  [ -f "$f" ] || { echo "missing $f"; exit 1; }
done

echo "=== M. the bit the whole feature hangs on ==="

# M-1: THE BL-244 CONTROL, AUTOMATED. Re-invokes this suite with a PATH stub
# whose mktemp always fails, from a canary directory, and requires the FATAL
# refusal. `SOIF_MKTEMP_CONTROL` stops the child recursing.
if [ -z "${SOIF_MKTEMP_CONTROL:-}" ]; then
  _m1_stub="$TOPTMP/mkstub"; mkdir -p "$_m1_stub"
  printf '#!/bin/sh\nexit 1\n' > "$_m1_stub/mktemp"; chmod +x "$_m1_stub/mktemp"
  _m1_canary="$TOPTMP/canary"; mkdir -p "$_m1_canary"
  _m1_out="$( cd "$_m1_canary" && SOIF_MKTEMP_CONTROL=1 PATH="$_m1_stub:$PATH" \
                bash "$SCRIPT_DIR/$(basename "$0")" </dev/null 2>&1 )"
  _m1_left="$(ls -A "$_m1_canary" 2>/dev/null | wc -l | tr -d ' ')"
  if printf '%s' "$_m1_out" | grep -q 'FATAL: mktemp -d failed' && [ "$_m1_left" = "0" ]; then
    pass "M-1: with mktemp denied the suite REFUSES and leaves the launch directory untouched — the ## BL-244: control, automated rather than asserted"
  else
    fail_ "M-1" "denied mktemp did not refuse cleanly (canary entries=$_m1_left): $(printf '%s' "$_m1_out" | head -1)"
  fi
fi
for f in "$CHECK" "$RECORD"; do
  if [ -x "$f" ]; then
    pass "M0: $(basename "$f") ships EXECUTABLE — the hook degrades open on this bit, so 644 is every push silently ungated"
  else
    fail_ "M0" "$(basename "$f") is not executable; the pre-push hook will shrug and let every push through"
  fi
done

mk() {   # mk DIR — a project with one commit
  local d="$1"
  [ -n "$d" ] && [ -d "$d" ] || { echo "FATAL: mk called with an empty or missing dir ('$d')" >&2; exit 1; }
  mkdir -p "$d/.claude"
  ( cd "$d" || exit 1
    unset GITHUB_BASE_REF
    git init -q -b main . >/dev/null 2>&1
    git config user.email t@e.x; git config user.name "T O"
    echo x > a.txt; git add -A >/dev/null 2>&1; git commit -qm "feat: a" >/dev/null 2>&1 )
}
run()  { ( cd "$1" && bash "$CHECK" </dev/null 2>&1 ); }
rc_of(){ ( cd "$1" && bash "$CHECK" </dev/null >/dev/null 2>&1 ); echo $?; }
# push_out / push_rc DIR REFLINE... — drive the gate the way git does.
push_out(){ local d="$1"; shift; ( cd "$d" && printf '%s\n' "$@" | bash "$CHECK" 2>&1 ); }
push_rc() { local d="$1"; shift; ( cd "$d" && printf '%s\n' "$@" | bash "$CHECK" >/dev/null 2>&1 ); echo $?; }
ZERO=0000000000000000000000000000000000000000

echo "=== A. absent, present, stale, refused — four situations, four messages ==="

A="$(newtmp)"; mk "$A"
a_out="$(run "$A")"; a_rc="$(rc_of "$A")"
if [ "$a_rc" -ne 0 ] && printf '%s' "$a_out" | grep -q 'no review has ever been recorded'; then
  pass "A1: with no record at all the push is BLOCKED and says the review is absent"
else
  fail_ "A1" "rc=$a_rc out: $(printf '%s' "$a_out" | head -2 | tr '\n' '|')"
fi

# THE TL;DR FORMAT IS PART OF THE REQUIREMENT, not decoration — a gate that
# stops someone owes them a decision they can act on.
a_tldr=0
for _need in "Plain English" "What it means for you" "Options:" "Recommendation" "If you do nothing"; do
  printf '%s' "$a_out" | grep -q "$_need" || { fail_ "A2" "refusal is missing the '$_need' section"; a_tldr=1; break; }
done
[ "$a_tldr" -eq 0 ] && pass "A2: the refusal carries the full TL;DR format — plain English, options, a recommendation, and the cost of doing nothing"

B="$(newtmp)"; mk "$B"
( cd "$B" && bash "$RECORD" --verdict approve >/dev/null 2>&1 )
b_rc="$(rc_of "$B")"
if [ "$b_rc" -eq 0 ]; then
  pass "B1: an approve recorded against THIS head lets the push through"
else
  fail_ "B1" "a recorded approve did not pass the gate (rc=$b_rc): $(run "$B" | head -2 | tr '\n' '|')"
fi

# STALE IS NOT ABSENT. Telling the operator "no review found" when one exists
# sends them to run a second review instead of re-reviewing what they changed.
C="$(newtmp)"; mk "$C"
( cd "$C" && bash "$RECORD" --verdict approve >/dev/null 2>&1
  echo y >> a.txt; git add -A >/dev/null 2>&1; git commit -qm "feat: b" >/dev/null 2>&1 )
c_out="$(run "$C")"; c_rc="$(rc_of "$C")"
if [ "$c_rc" -ne 0 ] && printf '%s' "$c_out" | grep -q 'does not cover what you are pushing' \
   && printf '%s' "$c_out" | grep -q 'Recorded against:' \
   && ! printf '%s' "$c_out" | grep -q 'no review has ever been recorded'; then
  pass "C1: a review of an EARLIER commit blocks and is named as stale, not as missing — the remedy differs"
else
  fail_ "C1" "rc=$c_rc out: $(printf '%s' "$c_out" | grep BLOCKED | head -1)"
fi

# A REFUSED REVIEW IS NOT A MISSING ONE EITHER.
D="$(newtmp)"; mk "$D"
( cd "$D" && bash "$RECORD" --verdict block >/dev/null 2>&1 )
d_out="$(run "$D")"; d_rc="$(rc_of "$D")"
if [ "$d_rc" -ne 0 ] && printf '%s' "$d_out" | grep -q "a review that said no"; then
  pass "D1: a recorded 'block' verdict blocks the push and is named as a refusal, not an absence"
else
  fail_ "D1" "rc=$d_rc out: $(printf '%s' "$d_out" | grep BLOCKED | head -1)"
fi

E="$(newtmp)"; mk "$E"
( cd "$E" && bash "$RECORD" --verdict minor_concerns >/dev/null 2>&1 )
if [ "$(rc_of "$E")" -eq 0 ]; then
  pass "E1: minor_concerns passes — the rubric blocks at major_concerns and above, and the gate agrees with it"
else
  fail_ "E1" "minor_concerns was treated as blocking"
fi

echo ""
echo "=== F. the attested escape — recorded, or refused ==="

F="$(newtmp)"; mk "$F"
f_out=$( cd "$F" && SOLO_PR_REVIEW_ATTESTED=1 bash "$CHECK" 2>&1 )
f_rc=$( cd "$F" && SOLO_PR_REVIEW_ATTESTED=1 bash "$CHECK" >/dev/null 2>&1; echo $? )
if [ "$f_rc" -ne 0 ] && printf '%s' "$f_out" | grep -q 'with no reason'; then
  pass "F1: an attestation with no reason is REFUSED — a justification-free escape is the gate off with extra steps"
else
  fail_ "F1" "rc=$f_rc out: $(printf '%s' "$f_out" | head -1)"
fi

G="$(newtmp)"; mk "$G"
g_rc=$( cd "$G" && SOLO_PR_REVIEW_ATTESTED=1 SOLO_PR_REVIEW_ATTESTED_REASON="live outage hotfix" bash "$CHECK" >/dev/null 2>&1; echo $? )
g_rec=$( cd "$G" && jq -r '.pr_review_attestations[0].reason // ""' .claude/process-state.json 2>/dev/null )
if [ "$g_rc" -eq 0 ] && [ "$g_rec" = "live outage hotfix" ]; then
  pass "G1: an attested push passes AND the reason is durably recorded — an escape that leaves no trace is not an escape"
else
  fail_ "G1" "rc=$g_rc recorded='$g_rec'"
fi

# THE REFUSE-IF-UNRECORDABLE ARM. BL-072's shape, reused by BL-233: if the trace
# cannot be written, the escape is refused rather than allowed silently.
H="$(newtmp)"; mk "$H"
printf '{"broken"' > "$H/.claude/process-state.json"
chmod 444 "$H/.claude/process-state.json" 2>/dev/null
h_rc=$( cd "$H" && SOLO_PR_REVIEW_ATTESTED=1 SOLO_PR_REVIEW_ATTESTED_REASON="x" bash "$CHECK" >/dev/null 2>&1; echo $? )
chmod 644 "$H/.claude/process-state.json" 2>/dev/null
if [ "$h_rc" -ne 0 ]; then
  pass "H1: an attestation that cannot be recorded is REFUSED, not waved through"
else
  fail_ "H1" "an unrecordable attestation passed the gate"
fi

echo ""
echo "=== I. the recorder's own guards ==="

I1="$(newtmp)"; mk "$I1"
i1_rc=$( cd "$I1" && bash "$RECORD" --verdict definitely-fine >/dev/null 2>&1; echo $? )
if [ "$i1_rc" -ne 0 ]; then
  pass "I1: an invented verdict is rejected — the rubric is a closed set"
else
  fail_ "I1" "an arbitrary verdict string was accepted"
fi

# THE SUMMARY IS SANITISED AT INGEST. It is model-supplied text that the gate
# later prints to a terminal; `## BL-233:` spent eight recurrences on values
# cleaned at the display site instead of where they enter. The backslash matters:
# `echo -e` manufactures a real newline from the two-character `\n`.
I2="$(newtmp)"; mk "$I2"
printf 'line one\\n  [OK] FORGED VERDICT\n' > "$I2/sum.txt"
( cd "$I2" && bash "$RECORD" --verdict approve --summary-file sum.txt >/dev/null 2>&1 )
i2_sum=$( cd "$I2" && jq -r '.pr_review.summary // ""' .claude/process-state.json 2>/dev/null )
case "$i2_sum" in
  *'\'*) fail_ "I2" "a backslash survived into the record: '$i2_sum'" ;;
  "")   fail_ "I2" "the summary was not recorded at all, so the strip proves nothing" ;;
  *)    pass "I2: a summary is stripped of control characters AND backslashes where it ENTERS, so no later display site can be tricked into forging a line" ;;
esac

echo ""
echo "=== J. the two arms a mutation battery found UNCOVERED ==="

# J1. THE GATE'S OWN unknown-verdict ARM. I1 below covers the RECORDER refusing
# an invented verdict, which is a different arm in a different script — a state
# file can be hand-edited, or written by an older recorder. With no assertion
# here, flipping the gate's `*)` arm to `exit 0` passed the whole suite.
J1="$(newtmp)"; mk "$J1"
( cd "$J1" && printf '{"pr_review":{"head":"%s","verdict":"lgtm"}}\n' "$(git rev-parse HEAD)" > .claude/process-state.json )
j1_out="$(run "$J1")"; j1_rc="$(rc_of "$J1")"
if [ "$j1_rc" -ne 0 ] && printf '%s' "$j1_out" | grep -q 'not one this gate understands'; then
  pass "J1: a verdict the gate does not recognise BLOCKS — 'could not classify' is not 'approved'"
else
  fail_ "J1" "rc=$j1_rc out: $(printf '%s' "$j1_out" | grep BLOCKED | head -1)"
fi

# J2. THE UNTOOLED ARM. The header calls this one of the situations that get
# their own message, and it had no assertion at all — flipping it to `exit 0`
# also passed the whole suite. A stub PATH holding only `git` reaches it,
# because the jq probe precedes every other external tool on the non-attested
# path.
J2="$(newtmp)"; mk "$J2"
j2_stub="$J2/stub"; mkdir -p "$j2_stub"
ln -s "$(command -v git)" "$j2_stub/git" 2>/dev/null
if [ -x "$j2_stub/git" ]; then
  j2_out="$( cd "$J2" && PATH="$j2_stub" "$(command -v bash)" "$CHECK" </dev/null 2>&1 )"
  j2_rc="$( cd "$J2" && PATH="$j2_stub" "$(command -v bash)" "$CHECK" </dev/null >/dev/null 2>&1; echo $? )"
  if [ "$j2_rc" -ne 0 ] && printf '%s' "$j2_out" | grep -q 'jq is not installed'; then
    pass "J2: with jq unavailable the gate BLOCKS and names the TOOLING fault — 'could not check' is never 'nothing to check'"
  else
    fail_ "J2" "rc=$j2_rc out: $(printf '%s' "$j2_out" | head -2 | tr '\n' '|')"
  fi
else
  fail_ "J2" "could not build a git-only PATH stub, so the untooled arm went unmeasured"
fi

echo ""
echo "=== K. a push does not have to push HEAD (BL-243-PUSHED-REFS) ==="

# K1 IS THE REGRESSION PIN FOR A REAL FAIL-OPEN. The first cut read only
# `git rev-parse HEAD`, so with an approve on record for HEAD, pushing ANY other
# branch shipped never-reviewed commits while the gate printed [OK]. Ordinary
# git usage, no dishonesty, no trace.
K="$(newtmp)"; mk "$K"
# Build the second branch FIRST and stage only the file it adds. Recording
# before this, with `git add -A`, swept the untracked state file into the other
# branch's commit — so checking back out to main deleted the record and every
# case here read as "never reviewed", which would have made K1 pass for the
# wrong reason.
( cd "$K" && git checkout -q -b other && echo z > z.txt && git add z.txt >/dev/null 2>&1 \
  && git commit -qm "feat: unreviewed" >/dev/null 2>&1 && git checkout -q main )
k_other="$( cd "$K" && git rev-parse other )"
( cd "$K" && bash "$RECORD" --verdict approve >/dev/null 2>&1 )
k_head="$( cd "$K" && git rev-parse HEAD )"

k1_out="$(push_out "$K" "refs/heads/other $k_other refs/heads/other $ZERO")"
k1_rc="$(push_rc  "$K" "refs/heads/other $k_other refs/heads/other $ZERO")"
if [ "$k1_rc" -ne 0 ] && printf '%s' "$k1_out" | grep -q 'does not cover what you are pushing'; then
  pass "K1: an approve on record for HEAD does NOT let an unreviewed branch be pushed — the gate reads the refs git hands it, not HEAD"
else
  fail_ "K1" "rc=$k1_rc — unreviewed commits would ship: $(printf '%s' "$k1_out" | grep -E '\[OK\]|BLOCKED' | head -1)"
fi

k2_rc="$(push_rc "$K" "refs/heads/main $k_head refs/heads/main $ZERO")"
if [ "$k2_rc" -eq 0 ]; then
  pass "K2: pushing the reviewed commit still passes — closing the fail-open did not close the honest path"
else
  fail_ "K2" "the REVIEWED commit was blocked (rc=$k2_rc): $(push_out "$K" "refs/heads/main $k_head refs/heads/main $ZERO" | grep BLOCKED | head -1)"
fi

# A DELETION SHIPS NO CODE. Blocking `git push --delete` on an unreviewed HEAD
# was fail-closed for nothing, and `## BL-149:` is the standing rule about gates
# people cannot satisfy honestly.
k3_out="$(push_out "$K" "(delete) $ZERO refs/heads/gone $k_other")"
k3_rc="$(push_rc  "$K" "(delete) $ZERO refs/heads/gone $k_other")"
if [ "$k3_rc" -eq 0 ] && printf '%s' "$k3_out" | grep -q 'deletion-only'; then
  pass "K3: a deletion-only push passes and says why — no commits leave the machine, so there is nothing a review could have covered"
else
  fail_ "K3" "rc=$k3_rc out: $(printf '%s' "$k3_out" | head -1)"
fi

# THE ESCAPE MUST REACH THE NEW REFUSAL. `## BL-233:` shipped guards that failed
# closed AHEAD of the attested escape, leaving an honest operator no way past.
k4_out="$( cd "$K" && printf '%s\n' "refs/heads/other $k_other refs/heads/other $ZERO" \
  | SOLO_PR_REVIEW_ATTESTED=1 SOLO_PR_REVIEW_ATTESTED_REASON="pinning that the escape reaches the ref check" bash "$CHECK" 2>&1 )"
k4_rc="$( cd "$K" && printf '%s\n' "refs/heads/other $k_other refs/heads/other $ZERO" \
  | SOLO_PR_REVIEW_ATTESTED=1 SOLO_PR_REVIEW_ATTESTED_REASON="pinning that the escape reaches the ref check" bash "$CHECK" >/dev/null 2>&1; echo $? )"
k4_rec="$( cd "$K" && jq -r '.pr_review_attestations[-1].pushed // ""' .claude/process-state.json 2>/dev/null )"
if [ "$k4_rc" -eq 0 ] && [ "$k4_rec" = "$k_other" ]; then
  pass "K4: the attested escape reaches the new ref check AND records the sha actually being pushed, not HEAD"
else
  fail_ "K4" "rc=$k4_rc recorded-pushed='$k4_rec' expected='$k_other'"
fi

echo ""
echo "=== L. the guard that could not fire (BL-243-REVPARSE-VERIFY) ==="

# BARE `git rev-parse HEAD` ON AN UNBORN BRANCH ECHOES THE LITERAL STRING
# "HEAD" TO STDOUT and exits 128, so `|| printf ''` never fires and the
# emptiness guard both scripts advertise could never fire either. Measured, not
# reasoned: without --verify a full green loop runs in a repo with ZERO commits,
# recording an approve against the word "HEAD" and passing the gate on it.
L="$(newtmp)"
( cd "$L" && unset GITHUB_BASE_REF && git init -q -b main . >/dev/null 2>&1
  git config user.email t@e.x; git config user.name "T O"; mkdir -p .claude )
l_out="$(run "$L")"; l_rc="$(rc_of "$L")"
if [ "$l_rc" -ne 0 ] && printf '%s' "$l_out" | grep -qi 'unborn\|does not resolve\|nothing resolves'; then
  pass "L1: with no commits at all the gate REFUSES instead of resolving HEAD to the literal string 'HEAD'"
else
  fail_ "L1" "rc=$l_rc out: $(printf '%s' "$l_out" | head -1)"
fi

l2_rc="$( cd "$L" && bash "$RECORD" --verdict approve >/dev/null 2>&1; echo $? )"
l2_rec="$( cd "$L" && jq -r '.pr_review.head // "<none>"' .claude/process-state.json 2>/dev/null || printf '<none>' )"
if [ "$l2_rc" -ne 0 ] && [ "$l2_rec" != "HEAD" ]; then
  pass "L2: the recorder refuses too, so no verdict is ever written against the word 'HEAD'"
else
  fail_ "L2" "rc=$l2_rc recorded-head='$l2_rec'"
fi

# --head BINDS THE RECORD TO WHAT WAS REVIEWED. A review takes minutes; a commit
# landing during one would otherwise be laundered under its verdict, because the
# recorder binds to HEAD-at-record-time.
L3="$(newtmp)"; mk "$L3"
l3_first="$( cd "$L3" && git rev-parse HEAD )"
( cd "$L3" && echo w >> a.txt && git add a.txt >/dev/null 2>&1 && git commit -qm "feat: landed during the review" >/dev/null 2>&1 )
( cd "$L3" && bash "$RECORD" --verdict approve --head "$l3_first" >/dev/null 2>&1 )
l3_rec="$( cd "$L3" && jq -r '.pr_review.head // ""' .claude/process-state.json 2>/dev/null )"
l3_rc="$(rc_of "$L3")"
if [ "$l3_rec" = "$l3_first" ] && [ "$l3_rc" -ne 0 ]; then
  pass "L3: --head records the REVIEWED sha, so a commit that landed mid-review trips the stale arm instead of inheriting the verdict"
else
  fail_ "L3" "recorded='$l3_rec' expected='$l3_first' gate-rc=$l3_rc (expected non-zero)"
fi

l4_rc="$( cd "$L3" && bash "$RECORD" --verdict approve --head deadbeefdeadbeefdeadbeefdeadbeefdeadbeef >/dev/null 2>&1; echo $? )"
if [ "$l4_rc" -ne 0 ]; then
  pass "L4: --head with a sha not in this repository is refused at record time, not left as an unmatchable record that later reads as a stale review"
else
  fail_ "L4" "a nonexistent sha was accepted as the reviewed head"
fi

echo ""
echo "=== S. arms a second mutation battery found unpinned ==="

# S1a/S1b. A1 pins the NO-FILE variant only. Every real generated project HAS a
# state file — `## BL-233:`'s accumulation writes one — so the arm that actually
# fires in the field was unpinned, and `exit 0` at the top of it survived the
# whole suite.
S1="$(newtmp)"; mk "$S1"
( cd "$S1" && printf '{}' > .claude/process-state.json )
s1_out="$(run "$S1")"; s1_rc="$(rc_of "$S1")"
if [ "$s1_rc" -ne 0 ] && printf '%s' "$s1_out" | grep -q 'no review has ever been recorded'; then
  pass "S1a: a state file that EXISTS but carries no review still blocks — the field case, not just the pristine one"
else
  fail_ "S1a" "rc=$s1_rc out: $(printf '%s' "$s1_out" | grep BLOCKED | head -1)"
fi

S1b="$(newtmp)"; mk "$S1b"
( cd "$S1b" && printf '{"pr_review":{"verdict":"approve"}}' > .claude/process-state.json )
s1b_out="$(run "$S1b")"; s1b_rc="$(rc_of "$S1b")"
if [ "$s1b_rc" -ne 0 ] && printf '%s' "$s1b_out" | grep -q 'INCOMPLETE'; then
  pass "S1b: a verdict with no sha reads as INCOMPLETE, not as 'never reviewed' — a record exists, it just cannot be checked"
else
  fail_ "S1b" "rc=$s1b_rc out: $(printf '%s' "$s1b_out" | grep BLOCKED | head -1)"
fi

# S2. K1 pushes ONE unreviewed ref. A `break` after the first stdin line
# resurrects the original fail-open for every multi-ref push — `git push origin
# main other`, `--tags`, `--all` — and survived the suite.
S2="$(newtmp)"; mk "$S2"
( cd "$S2" && git checkout -q -b other && echo z > z.txt && git add z.txt >/dev/null 2>&1 \
  && git commit -qm "feat: unreviewed" >/dev/null 2>&1 && git checkout -q main )
s2_other="$( cd "$S2" && git rev-parse other )"
( cd "$S2" && bash "$RECORD" --verdict approve >/dev/null 2>&1 )
s2_head="$( cd "$S2" && git rev-parse HEAD )"
s2_rc="$(push_rc "$S2" "refs/heads/main $s2_head refs/heads/main $ZERO" "refs/heads/other $s2_other refs/heads/other $ZERO")"
s2_ok="$(push_rc "$S2" "refs/heads/main $s2_head refs/heads/main $ZERO" "refs/heads/dup $s2_head refs/heads/dup $ZERO")"
if [ "$s2_rc" -ne 0 ] && [ "$s2_ok" -eq 0 ]; then
  pass "S2: EVERY ref in a multi-ref push is checked, not just the first — reviewed+unreviewed blocks, reviewed+reviewed passes"
else
  fail_ "S2" "reviewed+unreviewed rc=$s2_rc (want non-zero), reviewed+reviewed rc=$s2_ok (want 0)"
fi

# S3. D1 pins `block` and E1 pins `minor_concerns` passing; the BOUNDARY between
# them was unpinned, so moving major_concerns into the passing case survived.
S3="$(newtmp)"; mk "$S3"
( cd "$S3" && bash "$RECORD" --verdict major_concerns >/dev/null 2>&1 )
s3_out="$(run "$S3")"; s3_rc="$(rc_of "$S3")"
if [ "$s3_rc" -ne 0 ] && printf '%s' "$s3_out" | grep -q "major_concerns"; then
  pass "S3: major_concerns BLOCKS and is named — the rubric's boundary is 'major_concerns and above', and the gate has to agree with it"
else
  fail_ "S3" "rc=$s3_rc out: $(printf '%s' "$s3_out" | grep BLOCKED | head -1)"
fi

echo ""
echo "=== T. an annotated tag is not a commit (BL-149) ==="

# `git tag -a v1.0.0 && git push origin v1.0.0` hands the hook the TAG OBJECT's
# sha, which can never equal a recorded COMMIT sha — and the recorder peels
# `^{commit}`, so no honest record could ever satisfy it. That made a standard
# release flow permanently attestation-only: a gate people cannot satisfy
# honestly, which `## BL-149:` says gets deleted.
T="$(newtmp)"; mk "$T"
( cd "$T" && bash "$RECORD" --verdict approve >/dev/null 2>&1
  git tag -a v1.0.0 -m "release" >/dev/null 2>&1 )
t_reviewed="$( cd "$T" && git rev-parse HEAD )"
t_tag="$( cd "$T" && git rev-parse v1.0.0 )"
t1_rc="$(push_rc "$T" "refs/tags/v1.0.0 $t_tag refs/tags/v1.0.0 $ZERO")"
if [ "$t_tag" != "$t_reviewed" ] && [ "$t1_rc" -eq 0 ]; then
  pass "T1: an annotated tag OF the reviewed commit passes — the tag object sha differs from the commit sha, and refusing it forever was a gate nobody could satisfy"
else
  fail_ "T1" "tag=$t_tag reviewed=$t_reviewed rc=$t1_rc (annotated tag must differ and must pass)"
fi

( cd "$T" && git checkout -q -b unrev && echo q > q.txt && git add q.txt >/dev/null 2>&1 \
  && git commit -qm "feat: unreviewed" >/dev/null 2>&1 && git tag -a v2.0.0 -m "bad" >/dev/null 2>&1 && git checkout -q main )
t_badtag="$( cd "$T" && git rev-parse v2.0.0 )"
t2_rc="$(push_rc "$T" "refs/tags/v2.0.0 $t_badtag refs/tags/v2.0.0 $ZERO")"
if [ "$t2_rc" -ne 0 ]; then
  pass "T2: an annotated tag of an UNREVIEWED commit still blocks — peeling resolves what the tag actually ships, it does not wave tags through"
else
  fail_ "T2" "a tag of an unreviewed commit was allowed through (rc=$t2_rc)"
fi

# T3. WHAT THE GATE CANNOT RESOLVE, IT MUST NOT WAVE THROUGH. The peel's first
# cut fell back to the raw sha when `^{commit}` failed — so "I could not work
# out what this ships" was answered by comparing the unresolvable thing. A
# mutation returning the RECORDED sha from that fallback passed all 29
# assertions, which is the definition of an unpinned arm.
t3_rc="$(push_rc "$T" "refs/heads/ghost 1234567890abcdef1234567890abcdef12345678 refs/heads/ghost $ZERO")"
t3_out="$(push_out "$T" "refs/heads/ghost 1234567890abcdef1234567890abcdef12345678 refs/heads/ghost $ZERO")"
if [ "$t3_rc" -ne 0 ] && printf '%s' "$t3_out" | grep -q 'does not resolve to a commit'; then
  pass "T3: a ref the gate cannot resolve to a commit BLOCKS and says so — could-not-check is never nothing-to-check"
else
  fail_ "T3" "rc=$t3_rc out: $(printf '%s' "$t3_out" | grep BLOCKED | head -1)"
fi

echo ""
echo "=== W. the emitted hook — delegation and loud degrade are BEHAVIOUR, not presence ==="

# THE ONE LINE THE WHOLE FEATURE HANGS ON HAD NOTHING WATCHING IT. Round three
# deleted both WARN printfs from the template (silent-open) and replaced the
# `exec` with `exit 0` (feature off in every future install), and BOTH mutants
# passed the ENTIRE PR-blocking check set. `tests/test-bl239-contributor-hooks.sh`
# already states the rule this violates: presence checks cannot distinguish a
# no-op hook, so drive the EMITTED hook the way git does.
W="$(newtmp)"; mk "$W"
( cd "$W" && mkdir -p scripts && cp "$CHECK" scripts/check-pr-review.sh && chmod +x scripts/check-pr-review.sh )
( . "$REPO_ROOT/scripts/lib/hook-templates.sh" && soif_write_prepush_hook "$W/.git/hooks/pre-push" )
# STDIN FROM A FILE, NOT A PIPE. The degrade arms exit 0 without draining stdin,
# so the writing `printf` takes SIGPIPE — and this suite runs under
# `set -o pipefail`, which then promotes 141 over the hook's real 0 and the
# assertion measures the harness instead of the hook. git itself writes the ref
# list into the hook's stdin and does not care that it goes unread.
printf '%s\n' "refs/heads/main $( cd "$W" && git rev-parse HEAD ) refs/heads/main $ZERO" > "$W/refline"
w_line(){ ( cd "$W" && .git/hooks/pre-push < refline 2>&1 ); }
w_rc(){   ( cd "$W" && .git/hooks/pre-push < refline >/dev/null 2>&1 ); echo $?; }

if [ -x "$W/.git/hooks/pre-push" ]; then
  pass "W0: the emitter produces an EXECUTABLE hook — git silently ignores a non-executable one"
else
  fail_ "W0" "the emitted hook is not executable; git would ignore it and every push would be ungated"
fi

w1_out="$(w_line)"; w1_rc="$(w_rc)"
if [ "$w1_rc" -ne 0 ] && printf '%s' "$w1_out" | grep -q 'no review has ever been recorded'; then
  pass "W1: the EMITTED hook DELEGATES — an unreviewed push driven through the hook itself is blocked by the gate, not waved through"
else
  fail_ "W1" "rc=$w1_rc out: $(printf '%s' "$w1_out" | head -1)"
fi

( cd "$W" && chmod -x scripts/check-pr-review.sh )
w2_out="$(w_line)"; w2_rc="$(w_rc)"
if [ "$w2_rc" -eq 0 ] && printf '%s' "$w2_out" | grep -q 'PUSHING UNGATED'; then
  pass "W2: script present but unusable -> the hook degrades OPEN and SAYS SO — silent-open is exactly what shipped to this repo and went unnoticed"
else
  fail_ "W2" "rc=$w2_rc out: $(printf '%s' "$w2_out" | head -1)"
fi

( cd "$W" && rm -f scripts/check-pr-review.sh )
w3_out="$(w_line)"; w3_rc="$(w_rc)"
if [ "$w3_rc" -eq 0 ] && printf '%s' "$w3_out" | grep -q 'PUSHING UNGATED'; then
  pass "W3: script ABSENT -> degrades open and says so too — could-not-check is never nothing-to-check"
else
  fail_ "W3" "rc=$w3_rc out: $(printf '%s' "$w3_out" | head -1)"
fi

echo ""
echo "=== N. arms a THIRD mutation battery found unpinned ==="

# Every fixture's `mk` pre-creates `.claude/`, so round two's "the attest arm can
# now create it" fix was pinned by nothing — deleting the mkdir passed 30/30.
N1="$(newtmp)"
( cd "$N1" && unset GITHUB_BASE_REF && git init -q -b main . >/dev/null 2>&1
  git config user.email t@e.x; git config user.name "T O"
  echo x > a.txt; git add -A >/dev/null 2>&1; git commit -qm "feat: a" >/dev/null 2>&1 )
n1_rc="$( cd "$N1" && SOLO_PR_REVIEW_ATTESTED=1 SOLO_PR_REVIEW_ATTESTED_REASON="no .claude yet" bash "$CHECK" </dev/null >/dev/null 2>&1; echo $? )"
if [ "$n1_rc" -eq 0 ] && [ -f "$N1/.claude/process-state.json" ]; then
  pass "N1: an attestation in a project with no .claude/ yet is RECORDED, not misdiagnosed as a missing tool"
else
  fail_ "N1" "rc=$n1_rc state-file-exists=$([ -f "$N1/.claude/process-state.json" ] && echo yes || echo no)"
fi

N2="$(newtmp)"
( cd "$N2" && unset GITHUB_BASE_REF && git init -q -b main . >/dev/null 2>&1
  git config user.email t@e.x; git config user.name "T O"
  echo x > a.txt; git add -A >/dev/null 2>&1; git commit -qm "feat: a" >/dev/null 2>&1 )
n2_rc="$( cd "$N2" && bash "$RECORD" --verdict approve >/dev/null 2>&1; echo $? )"
if [ "$n2_rc" -eq 0 ] && [ -f "$N2/.claude/process-state.json" ]; then
  pass "N2: the recorder creates .claude/ too — the first review of a fresh project must not need a directory made by hand"
else
  fail_ "N2" "rc=$n2_rc state-file-exists=$([ -f "$N2/.claude/process-state.json" ] && echo yes || echo no)"
fi

# I2 pins the BACKSLASH half of the sanitizer. Narrowing `tr -d '\000-\037\\'`
# to drop only the backslash passed 30/30 — the control-character half, which is
# what a raw newline forgery actually needs, was unpinned.
N4="$(newtmp)"; mk "$N4"
printf 'line one\033[2K\007\177  [OK] FORGED\n' > "$N4/sum.txt"
( cd "$N4" && bash "$RECORD" --verdict approve --summary-file sum.txt >/dev/null 2>&1 )
n4_sum="$( cd "$N4" && jq -r '.pr_review.summary // ""' .claude/process-state.json 2>/dev/null )"
case "$n4_sum" in
  "") fail_ "N4" "the summary was not recorded at all, so the strip proves nothing" ;;
  *[[:cntrl:]]*) fail_ "N4" "a control character survived into the record" ;;
  *) pass "N4: CONTROL CHARACTERS are stripped at ingest as well as backslashes — the half a terminal-forgery actually needs" ;;
esac

# Deleting the unparsable-state arm silently reclassifies a corrupt file as
# "never reviewed" — still blocking, but the wrong remedy, which is the exact
# message-collapse this gate legislates against everywhere else.
N6="$(newtmp)"; mk "$N6"
( cd "$N6" && printf 'not json at all {{{' > .claude/process-state.json )
n6_out="$(run "$N6")"; n6_rc="$(rc_of "$N6")"
if [ "$n6_rc" -ne 0 ] && printf '%s' "$n6_out" | grep -q 'does not parse' \
   && ! printf '%s' "$n6_out" | grep -q 'no review has ever been recorded'; then
  pass "N6: a CORRUPT state file is named as unreadable, not as never-reviewed — the remedy is to fix the file, not to run a review"
else
  fail_ "N6" "rc=$n6_rc out: $(printf '%s' "$n6_out" | grep BLOCKED | head -1)"
fi

echo ""
echo "=== X. an operator hook that drains stdin (BL-243-HOOK-STDIN-DRAINED) ==="

# PROVEN WITH REAL PUSHES IN ROUND SIX: appending the gate to an existing hook
# that READS the ref list leaves this gate with empty stdin. It falls back to
# HEAD — and with an approve on record for the branch you are standing on, it
# printed a GREEN [OK] while a DIFFERENT unreviewed branch shipped.
X="$(newtmp)"; mk "$X"
( cd "$X" && bash "$RECORD" --verdict approve >/dev/null 2>&1 )
x_out="$( cd "$X" && bash "$CHECK" --from-hook < /dev/null 2>&1 )"
x_rc="$( cd "$X" && bash "$CHECK" --from-hook < /dev/null >/dev/null 2>&1; echo $? )"
if printf '%s' "$x_out" | grep -q 'no refs arrived on stdin' \
   && printf '%s' "$x_out" | grep -q 'up-to-date push still runs this hook' \
   && printf '%s' "$x_out" | grep -q 'CONSUMED the list'; then
  pass "X1: invoked from a hook with NO ref list, the gate SAYS it fell back to HEAD and names BOTH causes — an up-to-date push (harmless) and a drained stdin (a pass for the wrong tree)"
else
  fail_ "X1" "rc=$x_rc — the fallback to HEAD was silent: $(printf '%s' "$x_out" | head -1)"
fi

# It must stay a WARN, not a block: HEAD is frequently the right answer and
# refusing every such hook is `## BL-149:`'s deleted gate.
if [ "$x_rc" -eq 0 ]; then
  pass "X2: the warning does not block — HEAD is usually right, and refusing every stdin-reading hook would be a gate people route around"
else
  fail_ "X2" "the fallback warning turned into a refusal (rc=$x_rc)"
fi

# A HAND RUN MUST STAY QUIET. Warning on every manual invocation is how an audit
# line gets ignored — the gate warns only when a ref list was DUE.
x3_out="$( cd "$X" && bash "$CHECK" < /dev/null 2>&1 )"
if ! printf '%s' "$x3_out" | grep -q 'no refs arrived on stdin'; then
  pass "X3: without --from-hook the same invocation is SILENT — the warning fires only when a ref list was actually due"
else
  fail_ "X3" "a plain manual run cried wolf about missing refs"
fi

# The emitted hook must actually pass the flag, or X1 can never fire in the field.
( . "$REPO_ROOT/scripts/lib/hook-templates.sh" && soif_write_prepush_hook "$X/emitted-hook" )
if grep -qF -- '--from-hook' "$X/emitted-hook"; then
  pass "X4: the emitted hook declares itself with --from-hook, so the drained-stdin warning can fire where it matters"
else
  fail_ "X4" "the emitted hook does not pass --from-hook; the X1 warning would never fire in a real hook"
fi

# R-GATE6-3: the mirror of S1b. A sha with no verdict is INCOMPLETE, not an
# alien verdict — the message-collapse class this gate legislates against.
X5="$(newtmp)"; mk "$X5"
( cd "$X5" && printf '{"pr_review":{"head":"%s"}}' "$(git rev-parse HEAD)" > .claude/process-state.json )
x5_out="$(run "$X5")"; x5_rc="$(rc_of "$X5")"
if [ "$x5_rc" -ne 0 ] && printf '%s' "$x5_out" | grep -q 'INCOMPLETE' \
   && ! printf '%s' "$x5_out" | grep -q 'not one this gate understands'; then
  pass "X5: a commit with NO verdict reads as INCOMPLETE, not as an unrecognised verdict — the mirror of S1b, same remedy"
else
  fail_ "X5" "rc=$x5_rc out: $(printf '%s' "$x5_out" | grep BLOCKED | head -1)"
fi

# X6. AN UNRECOGNISED ARGUMENT MUST SAY SO. It is warned, not rejected: a
# legitimate wiring may forward git's <remote-name> <remote-url>, and refusing
# those would be a gate people route around.
X6="$(newtmp)"; mk "$X6"
( cd "$X6" && bash "$RECORD" --verdict approve >/dev/null 2>&1 )
x6_out="$( cd "$X6" && bash "$CHECK" --form-hook < /dev/null 2>&1 )"
x6_rc="$( cd "$X6" && bash "$CHECK" --form-hook < /dev/null >/dev/null 2>&1; echo $? )"
if printf '%s' "$x6_out" | grep -q "ignoring unrecognized option '--form-hook'" && [ "$x6_rc" -eq 0 ]; then
  pass "X6: a typo'd flag is NAMED rather than swallowed — --form-hook silently disabled the drained-stdin warning, which is one keystroke from a green fail-open"
else
  fail_ "X6" "rc=$x6_rc out: $(printf '%s' "$x6_out" | head -1)"
fi

x7_out="$( cd "$X6" && bash "$CHECK" --from-hook origin "file:///tmp/x" < /dev/null 2>&1 )"
if ! printf '%s' "$x7_out" | grep -q 'ignoring unrecognized option' \
   && printf '%s' "$x7_out" | grep -q 'no refs arrived on stdin'; then
  pass "X7: git's own <remote-name> <remote-url> arguments are accepted without complaint — a wiring that forwards \"\$@\" must not be nagged"
else
  fail_ "X7" "forwarded git args were treated as typos: $(printf '%s' "$x7_out" | head -1)"
fi

echo ""
echo "=== Y. the unsafe COMPOSITION is invisible at run time and visible statically ==="

# A partly-consumed ref list is indistinguishable from a genuinely shorter one,
# so the gate cannot catch it while running. `# BL-243-VERIFY-HOOK-STDIN` catches
# the COMPOSITION instead — before it costs anyone a shipped commit.
VI="$REPO_ROOT/scripts/verify-install.sh"
y_row() {  # y_row <hook-body> — the pre-push row verify-install reports
  local body="$1" Q
  Q="$(newtmp)"; mkdir -p "$Q/scripts" "$Q/.claude"
  cp "$CHECK" "$Q/scripts/check-pr-review.sh"; chmod +x "$Q/scripts/check-pr-review.sh"
  ( cd "$Q" && unset GITHUB_BASE_REF && git init -q -b main . ) >/dev/null 2>&1
  printf '%s\n' "$body" > "$Q/.git/hooks/pre-push"; chmod +x "$Q/.git/hooks/pre-push"
  ( cd "$Q" && SOURCE_DIR="$REPO_ROOT" bash "$VI" 2>&1 | grep -i 'pre-push' | head -1 )
}

y1="$(y_row "$(printf '#!/usr/bin/env bash\nread -r a b c d\nbash scripts/check-pr-review.sh --from-hook || exit 1\n')")"
# THE ROW'S CLASS IS THE POINT, NOT ITS WORDING. `register_manual` puts the row
# in MANUAL, and MANUAL is what makes verify-install exit non-zero;
# `register_pass` with identical text does not. That is CLAUDE.md's `[WARN]`
# trap — read the effect, not the label — and flipping this one call survived
# all 63 assertions while turning the auditor's own warning into a pass.
if printf '%s' "$y1" | grep -q 'ALSO READS STDIN' && printf '%s' "$y1" | grep -qF '(manual)'; then
  pass "Y1: a hook that delegates AND reads stdin is reported as unsafe AND AS AN ACTION ITEM — the row class is what carries verify-install's exit code, and the wording alone carries nothing"
else
  fail_ "Y1" "the unsafe composition was not reported as an action item: ${y1:-<no pre-push row>}"
fi

y2="$(y_row "$(printf '#!/usr/bin/env bash\nrefs="$(cat)"\nprintf "%%s\\n" "$refs" | while read -r a b c d; do :; done\nprintf "%%s\\n" "$refs" | bash scripts/check-pr-review.sh --from-hook || exit 1\n')")"
if ! printf '%s' "$y2" | grep -q 'ALSO READS STDIN'; then
  pass "Y2: the capture-and-replay wiring is NOT flagged — the detector must not nag the very shape the recipe tells people to build"
else
  fail_ "Y2" "the correct wiring was reported as unsafe: $y2"
fi

# Y3. THE CAPTURE EXCLUSION MUST BE LOAD-BEARING. Deleting it left the whole
# PR-blocking set green, because Y2's `while read`s sit mid-pipeline so the
# anchored read-regex never fires and the exclusion is never consulted. This
# shape has a LINE-ANCHORED read AND a capture, so only the exclusion keeps it
# quiet.
y3="$(y_row "$(printf '#!/usr/bin/env bash\nrefs="$(cat)"\nwhile read -r a b c d; do :; done <<EOF\n$refs\nEOF\nprintf "%%s\\n" "$refs" | bash scripts/check-pr-review.sh --from-hook\n')")"
if ! printf '%s' "$y3" | grep -q 'ALSO READS STDIN'; then
  pass "Y3: a line-anchored read that IS preceded by a capture stays quiet — the capture exclusion is load-bearing, not decoration"
else
  fail_ "Y3" "a correct capture-and-replay wiring was flagged unsafe: $y3"
fi

# Y4. THE READ FAMILY, NOT TWO SPELLINGS OF IT. `if read`, `IFS= read`,
# `while IFS= read` and `mapfile` all walked past the first regex, and one of
# them was proven to ship an unreviewed commit in silence. Buffered readers
# (`head -1`, `sed 1q`, `awk NR==1`) are deliberately NOT here: measured, they
# consume the WHOLE small ref list, so the runtime NOTE announces them. Shell
# `read` is the only byte-exact partial reader, which is why its family is the
# static target.
y4_missed=""
for _spell in 'if read -r a b c d; then :; fi' 'IFS= read -r line' 'while IFS= read -r l; do :; done' 'mapfile -t refs'; do
  _y="$(y_row "$(printf '#!/usr/bin/env bash\n%s\nbash scripts/check-pr-review.sh --from-hook || exit 1\n' "$_spell")")"
  printf '%s' "$_y" | grep -q 'ALSO READS STDIN' || y4_missed="$y4_missed [$_spell]"
done
if [ -z "$y4_missed" ]; then
  pass "Y4: if-read, IFS=-read, while-IFS=-read and mapfile are all seen — two spellings was not the family"
else
  fail_ "Y4" "undetected stdin-consuming spellings:$y4_missed"
fi

y10="$(y_row "$(printf '#!/usr/bin/env bash\nread -r a b c d\nbanner="$(cat /etc/hosts)"\n: "$banner"\nbash scripts/check-pr-review.sh --from-hook || exit 1\n')")"
if printf '%s' "$y10" | grep -q 'ALSO READS STDIN'; then
  pass "Y10: an unrelated \$(cat FILE) does NOT excuse a consumer — the exclusion is about capturing STDIN, and hook-wide excuse-matching let one everyday line disarm the whole check"
else
  fail_ "Y10" "a file-cat disarmed the consumer detector: ${y10:-<no row>}"
fi

y11_missed=""
for _body in 'while read -r a b c d; do :; done </dev/stdin' 'perl -ne "print; last"'; do
  _y="$(y_row "$(printf '#!/usr/bin/env bash\n%s\nbash scripts/check-pr-review.sh --from-hook || exit 1\n' "$_body")")"
  printf '%s' "$_y" | grep -q 'ALSO READS STDIN' || y11_missed="$y11_missed [$_body]"
done
if [ -z "$y11_missed" ]; then
  pass "Y11: the no-space '</dev/stdin' spelling and perl are seen — the spaced twin was already pinned, and perl is the same partial-reader class as dd and python"
else
  fail_ "Y11" "still undetected:$y11_missed"
fi

# Y12. A HEREDOC-FED CAT IS NOT A STDIN CAPTURE. `cat > f <<EOF` is the everyday
# file-write idiom — this repo's shipped scripts use it 26 times, including
# `soif_write_prepush_hook` itself — and it matched the temp-file excuse while
# consuming nothing, disarming the consumer detector hook-wide. The round-ten
# finding's class, inside the round-ten fix.
y12_missed=""
for _body in 'cat > .git/push-note <<NOTE
pushed
NOTE' 'cat > .git/copy < .git/config' 'concat > .git/merged'; do
  _y="$(y_row "$(printf '#!/usr/bin/env bash\nread -r a b c d\n%s\nbash scripts/check-pr-review.sh --from-hook || exit 1\n' "$_body")")"
  printf '%s' "$_y" | grep -q 'ALSO READS STDIN' || y12_missed="$y12_missed [${_body%%$'\n'*}]"
done
if [ -z "$y12_missed" ]; then
  pass "Y12: a heredoc-fed cat, a file-fed cat, and 'concat' do NOT excuse a consumer — the excuse is about capturing STDIN, and only that"
else
  fail_ "Y12" "these excused a live consumer while capturing nothing:$y12_missed"
fi

# Y13. THE EXCUSE SIDE READS THE STRIPPED HOOK. Replacing `_bl243_live` with a
# raw grep on the excuse conjunct survived the entire PR-blocking set — so a
# capture living only in a COMMENT would excuse a live consumer, with nothing
# red. The consumer side's strip was pinned; this half was not.
y13="$(y_row "$(printf '#!/usr/bin/env bash\nread -r a b c d\n# capture disabled: refs="$(cat)"\nbash scripts/check-pr-review.sh --from-hook || exit 1\n')")"
if printf '%s' "$y13" | grep -q 'ALSO READS STDIN'; then
  pass "Y13: a capture that lives only in a COMMENT does not excuse — the excuse conjunct reads the stripped hook, and nothing pinned that half"
else
  fail_ "Y13" "a commented-out capture excused a live consumer: ${y13:-<no row>}"
fi

# Y7. THE CAPTURE EXCLUSION, PINNED ON A SHAPE THE REDIRECT FILTER DOES NOT
# TOUCH. Y3's read line carries `<<EOF`, so the redirect filter drops it and the
# capture conjunct is never reached — deleting that conjunct passed the whole
# suite. This shape has no `<` on the consuming line.
y7="$(y_row "$(printf '#!/usr/bin/env bash\nt=$(mktemp)\ncat > "$t"\nbash scripts/check-pr-review.sh --from-hook < "$t" || exit 1\n')")"
if ! printf '%s' "$y7" | grep -q 'ALSO READS STDIN'; then
  pass "Y7: the temp-file capture-and-replay recipe stays quiet — the capture exclusion is load-bearing again, on a line the redirect filter cannot mask"
else
  fail_ "Y7" "the temp-file recipe was flagged unsafe: $y7"
fi

# Y8. THE REDIRECT EXCLUSION, PINNED ON ITS OWN. A read redirected from a FILE
# reads that file, not the ref list.
y8="$(y_row "$(printf '#!/usr/bin/env bash\nwhile read -r l; do :; done < .git/config\nbash scripts/check-pr-review.sh --from-hook || exit 1\n')")"
if ! printf '%s' "$y8" | grep -q 'ALSO READS STDIN'; then
  pass "Y8: a file-redirected read is not flagged — the redirect exclusion is load-bearing, and nagging a correct wiring is how a real warning gets tuned out"
else
  fail_ "Y8" "a file-redirected read was flagged as consuming the ref list: $y8"
fi

# Y9. THE TWO SHAPES THE REDIRECT FILTER BLINDED. A trailing comment carrying
# git's own field description — `<local ref> <local sha> …` — is the natural
# thing to paste beside a read, and `done < /dev/stdin` IS the ref list.
y9_missed=""
for _body in 'read -r a b c d # fields: <lref> <lsha> <rref> <rsha>' 'while read -r a b c d; do :; done < /dev/stdin'; do
  _y="$(y_row "$(printf '#!/usr/bin/env bash\n%s\nbash scripts/check-pr-review.sh --from-hook || exit 1\n' "$_body")")"
  printf '%s' "$_y" | grep -q 'ALSO READS STDIN' || y9_missed="$y9_missed [$_body]"
done
if [ -z "$y9_missed" ]; then
  pass "Y9: a trailing comment containing '<', and an explicit '< /dev/stdin', do not blind the detector — the crude '-v <' filter regressed both"
else
  fail_ "Y9" "still blinded:$y9_missed"
fi

# Y5b. THE MISSING-HOOK ROW HAS ITS OWN CLASS TO KEEP. Y5's fixture HAS a hook,
# so it exercises the does-not-delegate row; a project with no pre-push hook at
# all takes a different branch, and flipping THAT one to a pass survived the
# suite. A project with no gate must read as an action item, not as a pass.
y5b_dir="$(newtmp)"; mkdir -p "$y5b_dir/scripts" "$y5b_dir/.claude"
cp "$CHECK" "$y5b_dir/scripts/check-pr-review.sh"; chmod +x "$y5b_dir/scripts/check-pr-review.sh"
( cd "$y5b_dir" && unset GITHUB_BASE_REF && git init -q -b main . ) >/dev/null 2>&1
rm -f "$y5b_dir/.git/hooks/pre-push"
y5b="$( cd "$y5b_dir" && SOURCE_DIR="$REPO_ROOT" bash "$VI" 2>&1 | grep -i 'pre-push' | head -1 )"
if printf '%s' "$y5b" | grep -qF '(manual)' && printf '%s' "$y5b" | grep -q 'NOT gated'; then
  pass "Y5b: a project with NO pre-push hook reads as an action item — 'pushes are NOT gated' as a pass would be the auditor lying about the thing it exists to report"
else
  fail_ "Y5b" "the missing-hook row was not an action item: ${y5b:-<no row>}"
fi

# Y5c. THE FOURTH MANUAL ROW. Round thirteen fixed three and said "all three";
# the block has FOUR, so the correction was again one row short. This one covers
# a delegating hook at mode 644 — exactly what the missing-hook row's own remedy
# produces when the operator writes the hook and forgets chmod — and git ignores
# a non-executable hook SILENTLY, which is why the row exists at all.
y5c_dir="$(newtmp)"; mkdir -p "$y5c_dir/scripts" "$y5c_dir/.claude"
cp "$CHECK" "$y5c_dir/scripts/check-pr-review.sh"; chmod +x "$y5c_dir/scripts/check-pr-review.sh"
( cd "$y5c_dir" && unset GITHUB_BASE_REF && git init -q -b main . ) >/dev/null 2>&1
printf '#!/usr/bin/env bash\nexec bash scripts/check-pr-review.sh --from-hook\n' > "$y5c_dir/.git/hooks/pre-push"
chmod 644 "$y5c_dir/.git/hooks/pre-push"
y5c="$( cd "$y5c_dir" && SOURCE_DIR="$REPO_ROOT" bash "$VI" 2>&1 | grep -i 'pre-push' | head -1 )"
if printf '%s' "$y5c" | grep -qF '(manual)' && printf '%s' "$y5c" | grep -q 'NOT executable'; then
  pass "Y5c: a delegating hook git will not run reads as an action item — 'git ignores it silently' printed as a pass is the [WARN] trap on the fourth row"
else
  fail_ "Y5c" "the not-executable row was not an action item: ${y5c:-<no row>}"
fi

# Y5d. PRESENCE IS NOT SUFFICIENCY. The libs loop passes on `[ -f ]`, and
# init.sh has vendored hook-templates.sh into every generated project since
# 2026-07-11 — so the COMMON state is not "absent" but "present at a vintage
# without soif_emit_prepush_preamble". The lib-absent half was fixed one round
# ago; against a stale copy the backfilled recipe still exits 2 while the row
# read `[OK] hook-templates lib present`.
y5d_dir="$(newtmp)"; mkdir -p "$y5d_dir/scripts/lib" "$y5d_dir/.claude" "$y5d_dir/docs/reference"
printf '%s\n' '{"track":"light","deployment":"personal","poc_mode":null,"current_phase":1,"phases":{}}' > "$y5d_dir/.claude/phase-state.json"
printf '%s\n' '{"frameworkVersion":"1.0.0","host":"github","mode":"personal","deployment":"personal","poc_mode":null,"enforcement_level":"strict"}' > "$y5d_dir/.claude/manifest.json"
# A lib that exists but predates the recipe — the vendored vintage, in one line.
printf '#!/usr/bin/env bash\nsoif_write_precommit_hook() { :; }\n' > "$y5d_dir/scripts/lib/hook-templates.sh"
( cd "$y5d_dir" && unset GITHUB_BASE_REF && git init -q -b main . ) >/dev/null 2>&1
# ALL hook-templates rows, not the first: one file must produce exactly one row,
# and an [OK] alongside the warning would be the auditor answering twice.
y5d_all="$( cd "$y5d_dir" && HOME="$y5d_dir" bash "$VI" 2>&1 )"
# STATUS lines only — the summary section echoes each row again, and the remedy
# prints a third time, so a naive grep counts one row as three.
y5d="$(printf '%s' "$y5d_all" | grep -E '^[[:space:]]*\[(OK|WARN|FAIL)\]' | grep -i 'hook-templates')"
y5d_rows="$(printf '%s' "$y5d" | grep -c .)"
# THE CLASS, NOT THE TEXT — the lesson from Y1/Y5b/Y5c, applied here because I
# made the same mistake a third time: demoting this row to `register_pass` with
# identical wording passed until this conjunct was added. `(manual)` and
# `(auto-fixable)` are the action-item suffixes; a bare `[OK]` is neither.
if printf '%s' "$y5d" | grep -q 'predates the pre-push recipe' \
   && printf '%s' "$y5d" | grep -qF '(manual)' \
   && ! printf '%s' "$y5d" | grep -q 'lib present' \
   && [ "$y5d_rows" = "1" ]; then
  pass "Y5d: a hook-templates lib that PREDATES the recipe is reported — presence passed the [ -f ] check while the recipe it feeds exits 2, which is the auditor asserting health against its own broken remedy"
else
  fail_ "Y5d" "stale lib rows=$y5d_rows (want exactly 1, as an ACTION ITEM): ${y5d:-<no row>}"
fi

# Y5d2. THE FOURTH ARM: ABSENT AND UNFIXABLE. The decision has four outcomes —
# {absent, stale} x {source reachable, not} — and each needed its own fixture,
# because a mutant can only die where its arm actually executes. This one is
# absent-without-source; Y5d is stale-without-source, Y5e stale-with, Y5f
# absent-with.
rm -f "$y5d_dir/scripts/lib/hook-templates.sh"
y5d2="$( cd "$y5d_dir" && HOME="$y5d_dir" bash "$VI" 2>&1 | grep -E '^[[:space:]]*\[(OK|WARN|FAIL)\]' | grep -i 'hook-templates' | head -1 )"
if printf '%s' "$y5d2" | grep -qF '(manual)' \
   && printf '%s' "$y5d2" | grep -q 'missing'; then
  pass "Y5d2: an absent lib with NO reachable source is still an action item — unfixable is not the same as fine, and it is the arm a project cut off from its orchestrator lands on"
else
  fail_ "Y5d2" "absent-unfixable lib was not an action item: ${y5d2:-<no row>}"
fi

# Y5e. THE FIXABLE ARM, AND THE REPAIR IT PROMISES. Y5d's fixture has no
# reachable source, so it can only ever take the manual arm — demoting the
# FIXABLE arm to a pass survived it. This fixture points at a real source, so
# the row must be an action item AND `--auto-fix` must actually leave a lib the
# recipe can run: a repair row that does not repair is the auditor's own remedy
# failing where it says it will work.
y5e_dir="$(newtmp)"; mkdir -p "$y5e_dir/scripts/lib" "$y5e_dir/.claude" "$y5e_dir/docs/reference"
printf '%s\n' '{"track":"light","deployment":"personal","poc_mode":null,"current_phase":1,"phases":{}}' > "$y5e_dir/.claude/phase-state.json"
printf '%s\n' '{"frameworkVersion":"1.0.0","host":"github","mode":"personal","deployment":"personal","poc_mode":null,"enforcement_level":"strict"}' > "$y5e_dir/.claude/manifest.json"
printf '{"source_dir":"%s"}\n' "$REPO_ROOT" > "$y5e_dir/.claude/orchestrator-source.json"
printf '#!/usr/bin/env bash\nsoif_write_precommit_hook() { :; }\n' > "$y5e_dir/scripts/lib/hook-templates.sh"
cp "$REPO_ROOT/scripts/print-prepush-recipe.sh" "$y5e_dir/scripts/"; chmod +x "$y5e_dir/scripts/print-prepush-recipe.sh"
( cd "$y5e_dir" && unset GITHUB_BASE_REF && git init -q -b main . ) >/dev/null 2>&1

y5e_row="$( cd "$y5e_dir" && bash "$VI" 2>&1 | grep -E '^[[:space:]]*\[(OK|WARN|FAIL)\]' | grep -i 'hook-templates' | head -1 )"
( cd "$y5e_dir" && bash "$VI" --auto-fix >/dev/null 2>&1 )
y5e_has="$(grep -c 'soif_emit_prepush_preamble' "$y5e_dir/scripts/lib/hook-templates.sh" 2>/dev/null || printf '0')"
y5e_rc="$( cd "$y5e_dir" && bash scripts/print-prepush-recipe.sh >/dev/null 2>&1; echo $? )"
if printf '%s' "$y5e_row" | grep -qE '\((manual|auto-fixable)\)' \
   && [ "$y5e_has" != "0" ] && [ "$y5e_rc" -eq 0 ]; then
  pass "Y5e: with a reachable source the stale lib is an action item AND --auto-fix genuinely repairs it — the refreshed lib carries the emitter and the recipe exits 0"
else
  fail_ "Y5e" "row='$y5e_row' emitter_after_fix=$y5e_has (want non-zero) recipe_rc=$y5e_rc (want 0)"
fi

# Y5f. THE ABSENT-WITH-SOURCE ARM. Y5d covers absent-without-source and Y5e
# covers stale-with-source; nothing covered absent-WITH-source, so demoting that
# arm to a pass survived. Same fixture, lib removed.
rm -f "$y5e_dir/scripts/lib/hook-templates.sh"
y5f_row="$( cd "$y5e_dir" && bash "$VI" 2>&1 | grep -E '^[[:space:]]*\[(OK|WARN|FAIL)\]' | grep -i 'hook-templates' | head -1 )"
( cd "$y5e_dir" && bash "$VI" --auto-fix >/dev/null 2>&1 )
y5f_has="$(grep -c 'soif_emit_prepush_preamble' "$y5e_dir/scripts/lib/hook-templates.sh" 2>/dev/null || printf '0')"
if printf '%s' "$y5f_row" | grep -qE '\((manual|auto-fixable)\)' && [ "$y5f_has" != "0" ]; then
  pass "Y5f: an ABSENT lib with a reachable source is an action item and is genuinely delivered — the third arm of one decision, and the only one nothing was watching"
else
  fail_ "Y5f" "row='$y5f_row' emitter_after_fix=$y5f_has (want non-zero)"
fi

# Y6. BUFFERED READERS ARE PARTIAL READERS ONCE THE LIST IS BIG. An earlier cut
# excluded them, reasoning that they drain everything so the runtime NOTE
# announces them. Measured, that holds only below the stdio buffer: at 500 refs
# `head -1` leaves nothing, at 1000 (~114 KB) it leaves 424 lines, at 3000 it
# leaves 2855. `git push --all` on a many-branch repo clears that easily, and
# there nothing announces them at all.
y6_missed=""
for _spell in 'head -1 >/dev/null' 'sed 1q >/dev/null' 'tail -1 >/dev/null'; do
  _y="$(y_row "$(printf '#!/usr/bin/env bash\n%s\nbash scripts/check-pr-review.sh --from-hook || exit 1\n' "$_spell")")"
  printf '%s' "$_y" | grep -q 'ALSO READS STDIN' || y6_missed="$y6_missed [$_spell]"
done
if [ -z "$y6_missed" ]; then
  pass "Y6: buffered consumers are flagged too — above ~64 KB of ref list they stop draining and become byte-exact partial readers, which nothing announces"
else
  fail_ "Y6" "undetected buffered consumers:$y6_missed"
fi

# Y5. A COMMENTED-OUT DELEGATION IS NOT A DELEGATION. Commenting the line out is
# the ordinary way to disable something temporarily, and BOTH audit surfaces read
# it as installed while pushes ran ungated.
y5="$(y_row "$(printf '#!/usr/bin/env bash\n# temporarily disabled: bash scripts/check-pr-review.sh --from-hook\nexit 0\n')")"
if ! printf '%s' "$y5" | grep -qF '(manual)'; then
  fail_ "Y5" "a hook with no live delegation was not reported as an ACTION ITEM: ${y5:-<no row>}"
elif ! printf '%s' "$y5" | grep -q 'gate hook installed'; then
  pass "Y5: a hook whose delegation is COMMENTED OUT is not reported as installed — an auditor must not say the gate is on while pushes run ungated"
else
  fail_ "Y5" "a commented-out delegation was reported as installed: $y5"
fi

echo ""
echo "=== Z. the managed preamble — correctness by POSITION, not by recognition ==="

# THREE ROUNDS WERE SPENT NARROWING A REGEX over arbitrary shell, and the
# enumeration can never close. This block ends the class instead of chasing it:
# nothing runs before the capture, so it is safe for ANY hook body — including
# the byte-exact partial reader that no static check can see — and
# `exec < "$_soif_refs"` re-feeds the original list, so the operator edits
# nothing, which is what stops new spellings being authored at all.
Z="$(newtmp)"; mk "$Z"
( cd "$Z" && mkdir -p scripts && cp "$CHECK" scripts/check-pr-review.sh && chmod +x scripts/check-pr-review.sh )
( cd "$Z" && bash "$RECORD" --verdict approve >/dev/null 2>&1 )
z_head="$( cd "$Z" && git rev-parse HEAD )"
( cd "$Z" && git checkout -q -b unrev && echo q > q.txt && git add q.txt \
  && git commit -qm unreviewed >/dev/null 2>&1 && git checkout -q main )
z_unrev="$( cd "$Z" && git rev-parse unrev )"

z_hook() {   # z_hook <operator-body> — preamble + body, as the recipe instructs
  { printf '#!/usr/bin/env bash\n'
    bash "$REPO_ROOT/scripts/print-prepush-recipe.sh"
    printf '%s\n' "$1"
  } > "$Z/.git/hooks/pre-push"
  chmod +x "$Z/.git/hooks/pre-push"
}
z_run() {    # z_run <sha> — drive the hook the way git does
  ( cd "$Z" && printf 'refs/heads/x %s refs/heads/x %s\n' "$1" "$ZERO" > zrl \
    && .git/hooks/pre-push < zrl 2>&1 ); }
z_rc()  { ( cd "$Z" && printf 'refs/heads/x %s refs/heads/x %s\n' "$1" "$ZERO" > zrl \
    && .git/hooks/pre-push < zrl >/dev/null 2>&1 ); echo $?; }

z_bad=""
for _body in 'read -r a b c d; echo "BODY-SAW $a"' \
             'while read -r a b c d; do echo "BODY-SAW $a"; done' \
             'peek() { read -r a b c d; echo "BODY-SAW $a"; }; peek' \
             'head -1 | sed "s/^/BODY-SAW /"'; do
  z_hook "$_body"
  [ "$(z_rc "$z_unrev")" -ne 0 ] || z_bad="$z_bad [unreviewed-passed: ${_body%%;*}]"
  [ "$(z_rc "$z_head")"  -eq 0 ] || z_bad="$z_bad [reviewed-blocked: ${_body%%;*}]"
  printf '%s' "$(z_run "$z_head")" | grep -q 'BODY-SAW' || z_bad="$z_bad [body-starved: ${_body%%;*}]"
done
if [ -z "$z_bad" ]; then
  pass "Z1: in front of four hook bodies — including a single-read partial consumer no static check can recognise — the preamble blocks the unreviewed sha, passes the reviewed one, AND the untouched body still sees the ref list"
else
  fail_ "Z1" "preamble failed for:$z_bad"
fi

# The preamble must fail CLOSED if it cannot capture — `## BL-244:`'s posture.
z_stub="$Z/mkstub"; mkdir -p "$z_stub"
printf '#!/bin/sh\nexit 1\n' > "$z_stub/mktemp"; chmod +x "$z_stub/mktemp"
z_hook 'echo BODY-SAW'
z2_out="$( cd "$Z" && printf 'refs/heads/x %s refs/heads/x %s\n' "$z_head" "$ZERO" > zrl \
  && PATH="$z_stub:$PATH" .git/hooks/pre-push < zrl 2>&1 )"
z2_rc="$( cd "$Z" && printf 'refs/heads/x %s refs/heads/x %s\n' "$z_head" "$ZERO" > zrl \
  && PATH="$z_stub:$PATH" .git/hooks/pre-push < zrl >/dev/null 2>&1; echo $? )"
if [ "$z2_rc" -ne 0 ] && printf '%s' "$z2_out" | grep -q 'cannot capture the ref list'; then
  pass "Z2: if the capture itself fails the preamble REFUSES — a block that silently proceeds without the list is the gate switched off with extra steps"
else
  fail_ "Z2" "rc=$z2_rc out: $(printf '%s' "$z2_out" | head -1)"
fi

# Z2b. THE CAPTURE'S OWN FAILURE, NOT JUST mktemp'S. Z2 stubs `mktemp`, which
# pins the first guard and leaves the second unwatched — making the `cat`
# capture non-fatal passed all 62 assertions. A capture that reports failure and
# is ignored means the gate runs against an EMPTY file and the body against
# nothing, which is the gate switched off with extra steps.
z2b_stub="$Z/catstub"; mkdir -p "$z2b_stub"
printf '#!/bin/sh\nexit 1\n' > "$z2b_stub/cat"; chmod +x "$z2b_stub/cat"
z_hook 'echo BODY-SAW'
z2b_out="$( cd "$Z" && printf 'refs/heads/x %s refs/heads/x %s\n' "$z_head" "$ZERO" > zrl \
  && PATH="$z2b_stub:$PATH" .git/hooks/pre-push < zrl 2>&1 )"
z2b_rc="$( cd "$Z" && printf 'refs/heads/x %s refs/heads/x %s\n' "$z_head" "$ZERO" > zrl \
  && PATH="$z2b_stub:$PATH" .git/hooks/pre-push < zrl >/dev/null 2>&1; echo $? )"
z2b_orphans="$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'tmp.*' -newer "$Z/zrl" 2>/dev/null | wc -l | tr -d ' ')"
if [ "$z2b_rc" -ne 0 ] && printf '%s' "$z2b_out" | grep -q 'could not capture the ref list' \
   && [ "$z2b_orphans" = "0" ]; then
  pass "Z2b: a capture that REPORTS FAILURE stops the push AND leaves no orphaned temp file — the trap has to be armed before the capture, not after it"
else
  fail_ "Z2b" "rc=$z2b_rc out: $(printf '%s' "$z2b_out" | head -1)"
fi

# Z3. A REF LINE WITH NO SHA IS A MANGLED LIST, NOT A DELETION. It set
# _saw_refs=1, was skipped as fieldless, and an all-such list landed in the
# deletion-only arm printing [OK] with no record read at all. githooks(5)
# guarantees four fields, so git cannot send it — a hand-built replay that
# rewrites fields can, and hand-built replays are what the remedies once asked
# operators to write.
Z3="$(newtmp)"; mk "$Z3"
z3_out="$( cd "$Z3" && printf 'refs/heads/ghost\n' | bash "$CHECK" --from-hook 2>&1 )"
z3_rc="$( cd "$Z3" && printf 'refs/heads/ghost\n' | bash "$CHECK" --from-hook >/dev/null 2>&1; echo $? )"
if [ "$z3_rc" -ne 0 ] && printf '%s' "$z3_out" | grep -q 'NO sha'; then
  pass "Z3: a ref line with no sha REFUSES as malformed — it used to land in the deletion-only arm and print [OK] without reading the record at all"
else
  fail_ "Z3" "rc=$z3_rc out: $(printf '%s' "$z3_out" | head -1)"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
