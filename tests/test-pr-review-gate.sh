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
run()  { ( cd "$1" && bash "$CHECK" 2>&1 ); }
rc_of(){ ( cd "$1" && bash "$CHECK" >/dev/null 2>&1 ); echo $?; }

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
if [ "$c_rc" -ne 0 ] && printf '%s' "$c_out" | grep -q 'DIFFERENT commit' \
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
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
