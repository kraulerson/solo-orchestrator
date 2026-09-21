#!/usr/bin/env bash
# WP10b part 2 — §6.1's TEN-CELL TIER TABLE, and the dispositions that lift a stop.
#
# WHAT THIS SUITE IS FOR, AND HOW IT DIFFERS FROM ITS SIBLING.
# `tests/test-brownfield-wp10b-own-scan.sh` proves the SCAN — that the real
# gitleaks, invoked the way adoption invokes it, is not suppressible by
# anything the adoptee controls. It runs the real tool because that is the
# only thing that can prove a tool's semantics.
#
# This suite proves the DECISION, which is adoption's own logic, so it drives
# the scanner through a SEAM (`SOIF_ADOPT_OWN_SCAN_BIN`) and a canned report.
# Using the real scanner here would make twenty-odd cases depend on a host tool
# to answer a question the host tool has no part in — and would make the suite
# slow enough that people stop running it.
#
# THE TABLE IS TWO TIERS x FIVE STATUSES AND EVERY CELL IS ASSERTED IN BOTH
# DIRECTIONS. A cell asserted only one way is vacuous against a collapsed
# implementation: `return 0` everywhere satisfies every "proceeds" case, and
# `return 1` everywhere satisfies every "stops" case. Each status therefore has
# a stop case AND a proceed case, and the two not-scanned statuses are checked
# to be SEPARATE code paths (§6.1a says they must not be folded together —
# `personal` + `scan-failed` carries on with no acknowledgement, `personal` +
# `tool-unavailable` stops until one is recorded).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
TMPS=""

pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip_() { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

cleanup() { for d in $TMPS; do rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT
newtmp() { local d; d=$(mktemp -d); TMPS="$TMPS $d"; printf '%s\n' "$d"; }

command -v jq >/dev/null 2>&1 || { echo "  [FAIL] jq is required"; echo "Results: 0 passed, 1 failed, 0 skipped"; exit 1; }

# ── A report in the shape the own scan produces ─────────────────────────────
# `scannedBy`/`rulesSource` are what WP10b/1 adds, and the decision reads a
# report that carries them; a report without them is the survey's and must not
# reach the stop (asserted by D-INPUT below).
mk_report() {
  local out="$1" status="$2" count="$3" scope="${4:-full-history}" commits="${5:-3}"
  local findings="[]"
  if [ "$count" -gt 0 ]; then
    findings="$(jq -n --argjson n "$count" '[range($n) | {
      ruleId: "aws-access-token",
      file: ("secrets\(.).txt"),
      commit: ("deadbeef\(.)"),
      fingerprint: ("deadbeef\(.):secrets\(.).txt:aws-access-token:1"),
      startLine: 1, date: "2026-01-01", description: "AWS Access Token" }]')"
  fi
  jq -n --arg st "$status" --argjson c "$count" --arg sc "$scope" \
        --argjson cm "$commits" --argjson f "$findings" \
    '{schemaVersion: 2,
      secrets: {tool: "gitleaks", status: $st, scope: $sc, findingCount: $c,
                commitsScanned: $cm, findings: $f,
                scannedBy: "adoption", rulesSource: "framework",
                head: "0000000000000000000000000000000000000000"}}' > "$out"
}

# mk_dispositions OUT KIND [FINGERPRINT] — a join table in §6.3's shape.
mk_dispositions() {
  local out="$1" kind="$2" fp="${3:-}" commits="${4:-3}"
  mkdir -p "$(dirname "$out")"
  case "$kind" in
    ack-tool|ack-partial)
      local k="tool-unavailable"; [ "$kind" = "ack-partial" ] && k="scanned-partial"
      jq -n --arg k "$k" --argjson cm "$commits" '{schemaVersion: 1,
        scan: {head: "0000000000000000000000000000000000000000", commitsScanned: $cm,
               scope: "full-history", status: "scanned"},
        dispositions: [],
        acknowledgements: [{kind: $k, by: "Karl Raulerson", reason: "accepted for this run",
                            date: "2026-09-19", scope: "full-history", commitsScanned: $cm,
                            head: "0000000000000000000000000000000000000000"}]}' > "$out" ;;
    rotated|accepted-risk|false-alarm)
      jq -n --arg d "$kind" --arg fp "$fp" '{schemaVersion: 1,
        scan: {head: "0000000000000000000000000000000000000000", commitsScanned: 3,
               scope: "full-history", status: "scanned"},
        dispositions: [{fingerprint: $fp, disposition: $d, by: "Karl Raulerson",
                        reason: "rotated at the source of truth", date: "2026-09-19"}],
        acknowledgements: []}' > "$out" ;;
    no-signer)
      jq -n --arg fp "$fp" '{schemaVersion: 1,
        scan: {head: "0000000000000000000000000000000000000000", commitsScanned: 3,
               scope: "full-history", status: "scanned"},
        dispositions: [{fingerprint: $fp, disposition: "accepted-risk", by: "",
                        reason: "because", date: "2026-09-19"}],
        acknowledgements: []}' > "$out" ;;
  esac
}

# decide TIER REPORT [DISPOSITIONS] — run the decision in a subshell and
# publish rc and transcript through files, never through a $( ) capture: a
# helper called in a subshell loses its counters, which is `## BL-233:`'s
# learning (2) and has bitten this repo's harnesses before.
DEC_RC=0; DEC_OUT=""
decide() {
  local tier="$1" report="$2" disp="${3:-}"
  local T; T="$(mktemp -d)"; TMPS="$TMPS $T"
  ( . "$REPO_ROOT/scripts/lib/adopt/adopt-core.sh"    >/dev/null 2>&1
    . "$REPO_ROOT/scripts/lib/adopt/adopt-secrets.sh" >/dev/null 2>&1
    ADOPT_DEPLOYMENT="$tier"
    ADOPT_DISPOSITIONS_FILE="$disp"
    ADOPT_WORK="$T/work"; mkdir -p "$ADOPT_WORK"
    adopt_secrets_decide "$report" ) >"$T/out" 2>&1
  DEC_RC=$?
  DEC_OUT="$(cat "$T/out" 2>/dev/null)"
}

# _has PATTERN — case-insensitive presence in the last transcript.
_has() { printf '%s' "$DEC_OUT" | grep -qiE "$1"; }

echo "== WP10b/2 — the ten-cell tier table (§6.1) =="

# ═══════════════════════════════════════════════════════════════════════════
# CLEAN — the one cell both tiers share
# ═══════════════════════════════════════════════════════════════════════════
c_clean() {
  local T; T=$(newtmp); mk_report "$T/r.json" scanned 0
  local bad=""
  for tier in organizational personal; do
    decide "$tier" "$T/r.json"
    [ "$DEC_RC" -eq 0 ] || bad="$bad [$tier rc=$DEC_RC, want 0]"
  done
  [ -z "$bad" ] && pass "D1 a clean scan proceeds at BOTH tiers" \
                || fail_ "D1 a clean scan proceeds at BOTH tiers" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# FINDINGS — organizational STOPS until dispositioned; personal WARNS and goes
# ═══════════════════════════════════════════════════════════════════════════
c_findings() {
  local T; T=$(newtmp); mk_report "$T/r.json" scanned 1
  local fp="deadbeef0:secrets0.txt:aws-access-token:1"
  local bad=""

  decide organizational "$T/r.json"
  [ "$DEC_RC" -ne 0 ] || bad="$bad [org undispositioned: rc=0, want stop]"
  _has 'BLOCKED' || bad="$bad [org: no BLOCKED label]"

  mk_dispositions "$T/d.json" rotated "$fp"
  decide organizational "$T/r.json" "$T/d.json"
  [ "$DEC_RC" -eq 0 ] || bad="$bad [org dispositioned: rc=$DEC_RC, want proceed]"

  decide personal "$T/r.json"
  [ "$DEC_RC" -eq 0 ] || bad="$bad [personal: rc=$DEC_RC, want proceed]"
  _has 'aws-access-token' || bad="$bad [personal: the finding was not printed]"

  [ -z "$bad" ] && pass "D2 findings: org stops until dispositioned, personal warns and proceeds" \
                || fail_ "D2 findings: org stops until dispositioned, personal warns and proceeds" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# SCAN-FAILED — org stops with NO escape; personal carries on with NO
# acknowledgement, and must NOT render an empty findings list as a clean one
# ═══════════════════════════════════════════════════════════════════════════
c_scan_failed() {
  local T; T=$(newtmp); mk_report "$T/r.json" scan-failed 0
  local bad=""

  decide organizational "$T/r.json"
  [ "$DEC_RC" -ne 0 ] || bad="$bad [org: rc=0, want stop]"

  # NO ESCAPE at organizational: a valid acknowledgement must not lift it.
  mk_dispositions "$T/d.json" ack-tool
  decide organizational "$T/r.json" "$T/d.json"
  [ "$DEC_RC" -ne 0 ] || bad="$bad [org with an acknowledgement: rc=0, want stop anyway]"

  decide personal "$T/r.json"
  [ "$DEC_RC" -eq 0 ] || bad="$bad [personal: rc=$DEC_RC, want proceed]"
  _has 'nothing is known' || bad="$bad [personal: does not say nothing is known]"
  # THE FINDINGS TEMPLATE MUST NOT BE REUSED: a rendered findings list over a
  # scan that produced none is a clean bill of health issued by something that
  # did not happen. Assert on the TEMPLATE's own header, not on the word
  # "clean" — the correct message contains "not a clean result", and a first
  # draft of this assertion flagged that sentence as the defect it was written
  # to prevent.
  _has 'What the scan found' && bad="$bad [personal: rendered the findings template over a failed scan]"
  _has 'found nothing'       && bad="$bad [personal: claimed the scan found nothing]"

  [ -z "$bad" ] && pass "D3 scan-failed: org stops with no escape, personal carries on saying nothing is known" \
                || fail_ "D3 scan-failed: org stops with no escape, personal carries on saying nothing is known" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# TOOL-UNAVAILABLE — org hard refusal; personal stops UNLESS acknowledged
# ═══════════════════════════════════════════════════════════════════════════
c_tool_unavailable() {
  local T; T=$(newtmp); mk_report "$T/r.json" tool-unavailable 0
  local bad=""

  decide organizational "$T/r.json"
  [ "$DEC_RC" -ne 0 ] || bad="$bad [org: rc=0, want stop]"
  mk_dispositions "$T/d.json" ack-tool
  decide organizational "$T/r.json" "$T/d.json"
  [ "$DEC_RC" -ne 0 ] || bad="$bad [org with an acknowledgement: rc=0, want stop anyway]"

  decide personal "$T/r.json"
  [ "$DEC_RC" -ne 0 ] || bad="$bad [personal unacknowledged: rc=0, want stop]"

  decide personal "$T/r.json" "$T/d.json"
  [ "$DEC_RC" -eq 0 ] || bad="$bad [personal acknowledged: rc=$DEC_RC, want proceed]"

  # THE ACKNOWLEDGEMENT BRANCH HAS ITS OWN ROW RULES and they were pinned by
  # nothing either. `kind` was already covered; `by`, `reason` and `date` were
  # not.
  local _a
  for _a in 'del(.acknowledgements[0].date)|ack date absent' \
            '.acknowledgements[0].by = "  "|ack signer is whitespace' \
            '.acknowledgements[0].reason = ""|ack reason is empty'; do
    jq "${_a%%|*}" "$T/d.json" > "$T/d-bad.json" 2>/dev/null \
      || { bad="$bad [fixture jq failed for ${_a#*|}]"; continue; }
    decide personal "$T/r.json" "$T/d-bad.json"
    [ "$DEC_RC" -ne 0 ] || bad="$bad [${_a#*|}: accepted]"
  done

  # THE PRODUCER'S REAL SHAPE ON THIS CELL. `scout_secrets_scan` returns at the
  # `command -v` arm BEFORE `seccommits` is written, so a real
  # `tool-unavailable` section carries `commitsScanned: null` — not the `3`
  # this suite's `mk_report` hand-writes. The commit-count arm is now
  # unconditional, and this is what proves that did NOT make §6.4's escape
  # unreachable: an acknowledgement with no `scan.commitsScanned` is accepted,
  # one claiming a size the scan never had is refused, and the refusal names
  # both numbers so the operator can correct it.
  jq '.secrets.commitsScanned = null' "$T/r.json" > "$T/null-cm.json" 2>/dev/null
  jq 'del(.scan.commitsScanned) | del(.acknowledgements[0].commitsScanned)' \
     "$T/d.json" > "$T/ack-nocm.json" 2>/dev/null
  decide personal "$T/null-cm.json" "$T/ack-nocm.json"
  [ "$DEC_RC" -eq 0 ] || bad="$bad [the real tool-unavailable shape refused a valid acknowledgement, rc=$DEC_RC — §6.4's escape is unreachable]"
  decide personal "$T/null-cm.json" "$T/d.json"
  [ "$DEC_RC" -ne 0 ] || bad="$bad [an acknowledgement claiming a size this scan never had was accepted]"

  [ -z "$bad" ] && pass "D4 tool-unavailable: org refuses outright, personal stops unless acknowledged, and §6.4's escape stays reachable on the producer's real shape" \
                || fail_ "D4 tool-unavailable: org refuses outright, personal stops unless acknowledged, and §6.4's escape stays reachable on the producer's real shape" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# SCANNED-PARTIAL (ruled 2026-09-16) — org STOPS with no escape and names the
# unshallow remedy; personal stops unless acknowledged. Required even at
# findingCount 0, which is the whole point of the status.
# ═══════════════════════════════════════════════════════════════════════════
c_partial() {
  local T; T=$(newtmp)
  mk_report "$T/zero.json" scanned-partial 0 shallow-history 1
  mk_report "$T/one.json"  scanned-partial 1 shallow-history 1
  local bad=""

  decide organizational "$T/zero.json"
  [ "$DEC_RC" -ne 0 ] || bad="$bad [org: rc=0, want stop]"
  _has 'unshallow' || bad="$bad [org: the unshallow remedy is not printed]"
  # BOUND TO THE SCAN IT IS FOR: these fixtures are 1-commit shallow clones, so
  # an acknowledgement written against a 3-commit scan is STALE and must be
  # refused — which is D7's job, not this case's.
  mk_dispositions "$T/d.json" ack-partial "" 1
  decide organizational "$T/zero.json" "$T/d.json"
  [ "$DEC_RC" -ne 0 ] || bad="$bad [org acknowledged: rc=0, want stop anyway]"

  # AT ZERO FINDINGS AND AT PERSONAL, IT STILL STOPS WITHOUT AN ACKNOWLEDGEMENT.
  # This is the cell a "skip when the count is 0" shortcut would break.
  decide personal "$T/zero.json"
  [ "$DEC_RC" -ne 0 ] || bad="$bad [personal, 0 findings, unacknowledged: rc=0, want stop]"

  decide personal "$T/zero.json" "$T/d.json"
  [ "$DEC_RC" -eq 0 ] || bad="$bad [personal acknowledged: rc=$DEC_RC, want proceed]"

  # The reachable finding on a partial scan is printed, never withheld.
  decide organizational "$T/one.json"
  _has 'aws-access-token' || bad="$bad [org, 1 finding: the reachable finding was not printed]"
  # And the partial scope is stated in those words, never rendered as clean.
  _has 'part of' || bad="$bad [org: does not say the scan read part of the history]"

  [ -z "$bad" ] && pass "D5 scanned-partial: org stops with the remedy, personal stops unless acknowledged, even at 0 findings" \
                || fail_ "D5 scanned-partial: org stops with the remedy, personal stops unless acknowledged, even at 0 findings" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# THE TWO NOT-SCANNED STATUSES ARE SEPARATE PATHS (§6.1a)
# Routing both through one arm passes four of the five cells above; this is
# the case that refuses it.
# ═══════════════════════════════════════════════════════════════════════════
c_not_one_path() {
  local T; T=$(newtmp)
  mk_report "$T/failed.json" scan-failed 0
  mk_report "$T/unavail.json" tool-unavailable 0
  local bad=""
  decide personal "$T/failed.json";  local rc_failed=$DEC_RC
  decide personal "$T/unavail.json"; local rc_unavail=$DEC_RC
  # scan-failed carries on with NO acknowledgement; tool-unavailable does not.
  [ "$rc_failed" -eq 0 ] || bad="$bad [personal scan-failed rc=$rc_failed, want 0]"
  [ "$rc_unavail" -ne 0 ] || bad="$bad [personal tool-unavailable rc=0, want stop]"
  [ -z "$bad" ] && pass "D6 at personal, scan-failed and tool-unavailable are NOT one code path" \
                || fail_ "D6 at personal, scan-failed and tool-unavailable are NOT one code path" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# THE DISPOSITION FILE IS VALIDATED, NOT TRUSTED (§6.3)
# ═══════════════════════════════════════════════════════════════════════════
c_validate() {
  local T; T=$(newtmp); mk_report "$T/r.json" scanned 1
  local fp="deadbeef0:secrets0.txt:aws-access-token:1"
  local bad=""

  mk_dispositions "$T/nosign.json" no-signer "$fp"
  decide organizational "$T/r.json" "$T/nosign.json"
  [ "$DEC_RC" -ne 0 ] || bad="$bad [a blank signer was accepted]"

  # A fingerprint the stop's own scan never produced is STALE, not a pass.
  mk_dispositions "$T/alien.json" rotated "not-a-fingerprint-this-scan-produced"
  decide organizational "$T/r.json" "$T/alien.json"
  [ "$DEC_RC" -ne 0 ] || bad="$bad [a fingerprint absent from the scan was accepted]"

  # A file bound to a DIFFERENT scan is stale.
  jq '.scan.head = "1111111111111111111111111111111111111111"' "$T/nosign.json" > "$T/stale.json" 2>/dev/null
  jq '.dispositions[0].by = "Karl Raulerson"' "$T/stale.json" > "$T/stale2.json" 2>/dev/null
  decide organizational "$T/r.json" "$T/stale2.json"
  [ "$DEC_RC" -ne 0 ] || bad="$bad [a file bound to another HEAD was accepted]"

  # THE POSITIVE CONTROL, AND IT IS NOT OPTIONAL. Every assertion above is
  # "rc is non-zero", which a MISSING FUNCTION satisfies — measured: this case
  # passed 3/3 against a tree with no implementation at all, on rc 127. A valid
  # file must be ACCEPTED or the case proves nothing about validation.
  mk_dispositions "$T/good.json" accepted-risk "$fp"
  decide organizational "$T/r.json" "$T/good.json"
  [ "$DEC_RC" -eq 0 ] || bad="$bad [VACUITY FLOOR: a valid file was refused, rc=$DEC_RC]"

  # FAIL CLOSED WHEN THE SCAN RECORDED NO COMMIT. If `.secrets.head` is absent
  # the binding cannot be checked at all, and the first cut SKIPPED the check
  # in that case — which was every real run, because no producer emitted the
  # field. A sign-off from another repository was accepted. Refusing is the
  # only safe answer, and this is what pins it independent of the producer.
  # EACH OF §6.3'S ROW RULES, ONE AT A TIME, EACH ISOLATED. Review reverted
  # all five of these conjuncts at once and every PR-blocking check stayed
  # green (12/0, 11/0, 54/0, 16/16) while the mutant accepted a date-less row,
  # a `banana` disposition, a whitespace signer and a date-less
  # acknowledgement. The code was right and nothing defended it — the exact
  # shape the commit this suite belongs to was written to remove, committed
  # inside the fix for it. Each row below is a `jq` edit of a file that is
  # otherwise VALID, so a green here means that conjunct and no other.
  mk_dispositions "$T/row.json" accepted-risk "$fp"
  local _r
  for _r in 'del(.dispositions[0].date)|date absent' \
            '.dispositions[0].date = ""|date empty' \
            '.dispositions[0].disposition = "banana"|disposition out of vocabulary' \
            'del(.dispositions[0].disposition)|disposition absent' \
            '.dispositions[0].by = "   "|signer is whitespace' \
            '.dispositions[0].reason = "  "|reason is whitespace'; do
    jq "${_r%%|*}" "$T/row.json" > "$T/row-bad.json" 2>/dev/null \
      || { bad="$bad [fixture jq failed for ${_r#*|}]"; continue; }
    decide organizational "$T/r.json" "$T/row-bad.json"
    [ "$DEC_RC" -ne 0 ] || bad="$bad [${_r#*|}: accepted]"
  done
  # THE POSITIVE CONTROL for the loop: the unedited file must still be accepted,
  # or every row above passes against a validator that refuses everything.
  decide organizational "$T/r.json" "$T/row.json"
  [ "$DEC_RC" -eq 0 ] || bad="$bad [VACUITY FLOOR: the valid row was refused, rc=$DEC_RC]"

  # THE FILE'S OWN HEAD MUST BE EMPTY TOO, or this proves nothing: with a
  # populated `scan.head` the NEXT arm refuses the mismatch and the fail-closed
  # guard is masked. Measured — the first version of this arm passed whether or
  # not the guard was there. Both sides empty is the shape the old code let
  # through, because "" == "" compared equal.
  jq 'del(.secrets.head)' "$T/r.json" > "$T/nohead.json" 2>/dev/null
  mk_dispositions "$T/good2.json" accepted-risk "$fp"
  jq 'del(.scan.head)' "$T/good2.json" > "$T/nohead-disp.json" 2>/dev/null
  decide organizational "$T/nohead.json" "$T/nohead-disp.json"
  [ "$DEC_RC" -ne 0 ] || bad="$bad [a scan with no recorded commit accepted a sign-off anyway]"

  # FINDINGS WITH NO FINGERPRINT ARE NOT "ALL DISPOSITIONED". With nothing to
  # join on, both set differences are empty and the stop lifted on a file
  # carrying ZERO dispositions — measured. gitleaks always sets Fingerprint
  # today, so this is defence in depth against a schema that has already
  # changed once (`## BL-288:` took the status vocabulary 3 -> 4).
  jq '.secrets.findings = [{ruleId: "aws-access-token", file: "x.txt", startLine: 1}]' \
     "$T/r.json" > "$T/nofp.json" 2>/dev/null
  jq '.dispositions = []' "$T/good2.json" > "$T/empty-disp.json" 2>/dev/null
  decide organizational "$T/nofp.json" "$T/empty-disp.json"
  [ "$DEC_RC" -ne 0 ] || bad="$bad [findings with no fingerprint were treated as dispositioned]"

  [ -z "$bad" ] && pass "D7 the disposition file is validated: signer, fingerprint membership, and the scan it is bound to" \
                || fail_ "D7 the disposition file is validated: signer, fingerprint membership, and the scan it is bound to" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# THE STOP IS A BLOCK, NOT A REFUSAL (§8.1, WP9d's two primitives)
# ═══════════════════════════════════════════════════════════════════════════
c_label() {
  # EVERY STOPPING CELL, NOT ONE. A first cut exercised only
  # `organizational:scan-failed`, so routing any OTHER arm through
  # `adopt_refuse` left the suite green — measured, the review's MU7.
  local T; T=$(newtmp)
  mk_report "$T/failed.json"  scan-failed 0
  mk_report "$T/unavail.json" tool-unavailable 0
  mk_report "$T/partial.json" scanned-partial 0 shallow-history 1
  mk_report "$T/finds.json"   scanned 1
  mk_report "$T/weird.json"   some-status-from-the-future 0
  local bad="" cell tier rep
  for cell in "organizational failed" "personal tool:unavail" "organizational unavail" \
              "organizational partial" "personal partial" "organizational finds" \
              "organizational weird" "personal weird"; do
    set -- $cell; tier="$1"; rep="${2#*:}"
    decide "$tier" "$T/$rep.json"
    [ "$DEC_RC" -ne 0 ] || { bad="$bad [$tier/$rep did not stop]"; continue; }
    _has '\[BLOCKED\]' || bad="$bad [$tier/$rep: no BLOCKED]"
    _has '\[REFUSED\]' && bad="$bad [$tier/$rep: said REFUSED]"
  done
  [ -z "$bad" ] && pass "D8 EVERY secrets stop is [BLOCKED], never [REFUSED] — a named check ran" \
                || fail_ "D8 EVERY secrets stop is [BLOCKED], never [REFUSED] — a named check ran" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# THE DECISION READS THE STOP'S OWN SCAN, NOT A HANDED-IN SURVEY (§6.2b)
# ═══════════════════════════════════════════════════════════════════════════
c_input() {
  # THE FIXTURE IS CLEAN ON PURPOSE. A first draft used a 1-finding report,
  # which STOPS at organizational for an entirely different reason — so
  # disabling the witness check left this case green (measured: mutation M8
  # survived). With a clean report the ONLY thing that can stop it is the
  # missing witnesses, which is what this case claims to test.
  local T; T=$(newtmp); mk_report "$T/r.json" scanned 0
  # Strip WP10b/1's two witnesses: this is now a survey's section, not the
  # stop's, and the stop must refuse to decide on it rather than proceed.
  jq 'del(.secrets.scannedBy) | del(.secrets.rulesSource)' "$T/r.json" > "$T/survey.json" 2>/dev/null
  decide organizational "$T/survey.json"
  local rc_survey=$DEC_RC
  # THE POSITIVE CONTROL: the same report WITH the witnesses, and one clean
  # status, must be accepted. Without this, rc 127 from a missing function
  # passes this case — measured against the base tree before implementation.
  local T2; T2=$(newtmp); mk_report "$T2/own.json" scanned 0
  decide organizational "$T2/own.json"
  local rc_own=$DEC_RC
  # R-3: the two stops BEFORE the table — this one and the no-tier one — are
  # `adopt_block` sites that D8's loop cannot reach, because they fire before
  # a status matters. Their label is pinned here instead.
  decide organizational "$T/survey.json"
  _has '\[BLOCKED\]' || fail_ "D9 label" "the not-own-report stop is not [BLOCKED]"
  decide "" "$T2/own.json"
  _has '\[BLOCKED\]' || fail_ "D9 label" "the no-tier stop is not [BLOCKED]"
  if [ "$rc_survey" -ne 0 ] && [ "$rc_own" -eq 0 ]; then
    pass "D9 the decision refuses a report that is not the stop's own scan"
  else
    fail_ "D9 the decision refuses a report that is not the stop's own scan" \
      "survey rc=$rc_survey (want non-zero), own-scan rc=$rc_own (want 0)"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# (10) A STATUS THIS VERSION DOES NOT KNOW IS A STOP AT BOTH TIERS
#      NOT HYPOTHETICAL: Scout's vocabulary already went from three words to
#      four (`## BL-288:`) and bumped `schemaVersion` 1 -> 2 for that reason.
#      Nothing covered this arm, so making it `return 0` left every suite green.
# ═══════════════════════════════════════════════════════════════════════════
c_unknown() {
  local T; T=$(newtmp); mk_report "$T/r.json" some-status-from-the-future 0
  local bad=""
  for tier in organizational personal; do
    decide "$tier" "$T/r.json"
    [ "$DEC_RC" -ne 0 ] || bad="$bad [$tier proceeded on an unknown status]"
  done
  decide organizational "$T/r.json"
  _has 'does not understand' || bad="$bad [the refusal does not name the unknown status]"
  [ -z "$bad" ] && pass "D10 an unrecognised status stops at BOTH tiers (BL-147: a check that cannot run must not pass)" \
                || fail_ "D10 an unrecognised status stops at BOTH tiers (BL-147: a check that cannot run must not pass)" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# (11) BOTH WITNESSES ARE REQUIRED, INDEPENDENTLY (§6.2b)
#      D9 strips BOTH, so it cannot see a predicate relaxed to one. Measured:
#      dropping the `rulesSource` half left every suite green while the stop
#      accepted a report claiming `rulesSource: "project"` — §6.2b's input 2,
#      the audited project's own scanner rules, unguarded.
# ═══════════════════════════════════════════════════════════════════════════
c_witnesses() {
  local T; T=$(newtmp); mk_report "$T/r.json" scanned 0
  local bad=""
  jq 'del(.secrets.scannedBy)'   "$T/r.json" > "$T/no-by.json"  2>/dev/null
  jq 'del(.secrets.rulesSource)' "$T/r.json" > "$T/no-src.json" 2>/dev/null
  jq '.secrets.rulesSource = "project"' "$T/r.json" > "$T/proj.json" 2>/dev/null
  for f in no-by no-src proj; do
    decide organizational "$T/$f.json"
    [ "$DEC_RC" -ne 0 ] || bad="$bad [$f was accepted as the stop's own scan]"
  done
  decide organizational "$T/r.json"
  [ "$DEC_RC" -eq 0 ] || bad="$bad [VACUITY FLOOR: the intact report was refused]"
  [ -z "$bad" ] && pass "D11 scannedBy AND rulesSource are each required — one alone is not the stop's scan" \
                || fail_ "D11 scannedBy AND rulesSource are each required — one alone is not the stop's scan" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# (12) THE ORDERING — a stopping adoption asks NOTHING and writes NOTHING
#      This drives the REAL driver, because the property is about where the
#      call sits in `adopt_main` and nothing smaller can observe that. It had
#      NO coverage anywhere: swapping the decide call back after the reverse
#      intake left wp10a 54/0 and this suite 9/0, over a transcript that ran
#      107 lines of interview before blocking.
# ═══════════════════════════════════════════════════════════════════════════
c_ordering() {
  local label="D12 an adoption stopped by the secrets check asks no interview question and writes nothing"
  command -v git >/dev/null 2>&1 || { skip_ "$label" "git absent"; return; }
  local T; T=$(newtmp)
  mkdir -p "$T/p/docs"
  local _git_out
  _git_out="$( ( cd "$T/p" && git init -q . \
      && git config user.email wp10b@test.invalid && git config user.name "WP10b Test" \
      && git config core.excludesFile /dev/null ) 2>&1 )" \
    || { fail_ "$label" "fixture init failed: $_git_out"; return; }
  printf '{"name":"acme"}\n' > "$T/p/package.json"
  printf '# acme\n'          > "$T/p/README.md"
  _git_out="$( ( cd "$T/p" && git add -A && git commit -q -m "their own history" ) 2>&1 )" \
    || { fail_ "$label" "fixture commit failed: $_git_out"; return; }

  local before after
  before="$(cd "$T/p" && git status --porcelain; cd "$T/p" && git rev-parse HEAD)"

  # No scanner => tool-unavailable => a stop at BOTH tiers (organizational has
  # no escape at all). `1` answers the tier question; the rest are never asked
  # if the ordering is right, which is the point.
  printf '1\n1\n1\n1\n1\n' > "$T/answers"
  jq -n '{schemaVersion: 2, secrets: {status: "scanned", findingCount: 0}}' > "$T/report.json"
  local rc=0
  ( cd "$T/p" && env SCOUT_GITLEAKS_BIN=gitleaks-does-not-exist-wp10b \
      bash "$REPO_ROOT/scripts/adopt-project.sh" --scan-report "$T/report.json" ) \
    < "$T/answers" > "$T/out" 2> "$T/err" || rc=$?

  after="$(cd "$T/p" && git status --porcelain; cd "$T/p" && git rev-parse HEAD)"
  local bad=""
  [ "$rc" -ne 0 ] || bad="$bad [rc=0, want a stop]"
  # THE INTERVIEW'S OWN HEADING must be absent — the decision runs before it.
  grep -qi 'The interview' "$T/out" "$T/err" 2>/dev/null && bad="$bad [the interview ran before the stop]"
  # THE POSITIVE CONTROL, the convention D7 and D9 already carry. Without it
  # this case cannot tell "the secrets check stopped before the interview" from
  # "the driver died before anything" — measured: a `return 2` inserted before
  # the tier question left this case GREEN. The label goes to stderr.
  grep -q 'no secrets scanner was available' "$T/err" 2>/dev/null \
    || bad="$bad [the run stopped, but not at the secrets check]"
  [ "$before" = "$after" ] || bad="$bad [the adoptee changed]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

c_clean; c_findings; c_scan_failed; c_tool_unavailable; c_partial
c_not_one_path; c_validate; c_label; c_input; c_unknown; c_witnesses; c_ordering

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
