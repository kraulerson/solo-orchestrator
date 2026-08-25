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
trap 'chmod -R u+rwX "$TOPTMP" 2>/dev/null; rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/gXXXXXX"; }

for f in "$CHECK" "$RECORD"; do
  [ -f "$f" ] || { echo "missing $f"; exit 1; }
done

mk() {   # mk DIR — a project with one commit
  local d="$1"; mkdir -p "$d/.claude"
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
echo "=== K. a push does not have to push HEAD (BL-PRGATE-PUSHED-REFS) ==="

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
echo "=== L. the guard that could not fire (BL-PRGATE-REVPARSE-VERIFY) ==="

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
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
