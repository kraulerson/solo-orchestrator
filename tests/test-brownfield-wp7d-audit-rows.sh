#!/usr/bin/env bash
# tests/test-brownfield-wp7d-audit-rows.sh — WP7's audit rows and §6.3's join
# table: what adoption writes down about the scan and about itself.
#
# SPEC: ADOPT-002-ARCH v2 §6.3 (the two records: the committed join table
# `.claude/adoption/secrets-dispositions.json`, and one `adoption_event` row per
# accepted risk and per acknowledgement, refused if it cannot be written) and
# §8.9 (the `adoption` event). Backlog: `## BL-242:`.
#
# WHAT EACH CASE OWNS.
#   R1  an organizational adoption with two findings commits the join table,
#       bound to the scan, carrying both decisions — and never a value
#   R2  exactly ONE `secrets_disposition` row, for the accepted risk; the
#       rotated one accepts nothing and writes nothing
#   R3  an acknowledgement the operator's file carries that this run did not
#       accept (a `tool-unavailable` row on a fully scanned run) is NOT written
#       down. A stranger FINGERPRINT never gets this far: the validator refuses
#       it as stale (§6.3), which the dispositions-template suite pins.
#   R4  every adoption writes the `adoption` row, naming the tier and the
#       commit it was adopted at, and the ledger is committed
#   R5  a clean personal adoption still writes the join table, with its scan
#       block and empty lists (§6.3: "required even at findingCount 0")
#   R6  a personal adoption with NO scanner records its acknowledgement in the
#       join table AND as a row
#   R7  an acknowledgement that cannot be recorded BLOCKS the run: rc 1,
#       nothing committed
#   R8  the stage sits after `intake` and before `manifest`
#   R10 a project that already carries a ledger is adopted: the ledger is
#       appended to, never counted as an overwrite (review: every such project
#       was blocked by the overwrite-inventory check)
#   R11 a file bound to ANOTHER scan contributes nothing (§6.3's staleness)
#   R9  on a PERSONAL run with findings — where the validator does not insist
#       on dispositions, so nothing upstream filters the file — an incomplete
#       disposition (no name) is not written down as a decision
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

echo "== WP7 — the audit rows and the dispositions join table =="

for t in git jq gitleaks; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH — the findings need a real scan"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done

WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT

_base() {   # _base DIR — a project with its own history
  local p="$1"
  mkdir -p "$p/src" || return 1
  ( cd "$p" && git init -q . && git config user.email wp7d@test.invalid && git config user.name "WP7d Test" ) >/dev/null 2>&1 || return 1
  printf '{"name":"acme","scripts":{"test":"exit 0"}}\n' > "$p/package.json"
  printf '# acme\n' > "$p/README.md"
  ( cd "$p" && git add package.json README.md && git commit -q --no-verify -m "chore: their history" ) >/dev/null 2>&1
}
_run() {    # _run DIR TAG AUDIENCE [args...] — sets RUN_RC
  local p="$1" tag="$2" aud="$3"; shift 3
  printf '%s\n1\n1\n1\n1\n' "$aud" > "$WORK/ans-$tag"
  ( cd "$p" && bash "$REPO_ROOT/scripts/adopt-project.sh" "$@" < "$WORK/ans-$tag" ) \
    > "$WORK/$tag.out" 2> "$WORK/$tag.err"
  RUN_RC=$?
}
_rows() {   # _rows DIR EVENT — the ledger's rows of one event, compact
  jq -c --arg e "$2" '.[] | select(.type == "adoption_event" and .details.event == $e)' \
    "$1/.claude/bypass-audit.json" 2>/dev/null
}
JT=".claude/adoption/secrets-dispositions.json"

# ── O: organizational, two leaked keys ──────────────────────────────────────
O="$WORK/org"
_base "$O"
printf 'aws_access_key_id = %s\n' "AKIA3XN7QW5Z""TBMR2VKD" > "$O/src/config.py"
printf 'aws_access_key_id = %s\n' "AKIA7ZQ2WX4Y""KLMN3PQR" > "$O/src/deploy.py"
( cd "$O" && git add src/config.py src/deploy.py && git commit -q --no-verify -m "chore: two leaked keys" ) >/dev/null 2>&1
_run "$O" org-stop 2
sed -n '/ready to fill in/,$p' "$WORK/org-stop.out" | grep '^      ' | sed 's/^      //' > "$WORK/tpl.json"
FP1="$(jq -r '.dispositions[0].fingerprint // ""' "$WORK/tpl.json")"
FP2="$(jq -r '.dispositions[1].fingerprint // ""' "$WORK/tpl.json")"
jq --arg a "$FP1" '
    .dispositions |= map(if .fingerprint == $a
        then .disposition="accepted-risk" | .by="Jane Ops" | .reason="test key, never deployed" | .date="2026-09-24"
        else .disposition="rotated" | .by="Jane Ops" | .reason="revoked at the provider" | .date="2026-09-24" end)
    | .acknowledgements = [{kind:"tool-unavailable", by:"Stale", reason:"from another run", date:"2026-09-24"}]' \
  "$WORK/tpl.json" > "$WORK/filled.json"
_run "$O" org 2 --dispositions "$WORK/filled.json"; ORC=$RUN_RC

# ── C: personal, clean ──────────────────────────────────────────────────────
C="$WORK/clean"
_base "$C"
_run "$C" clean 1; CRC=$RUN_RC

r1() {
  local label="R1 the join table is committed, bound to THIS scan, with both decisions and no value" bad="" head
  [ "$ORC" -eq 0 ] || { fail_ "$label" "the organizational adoption did not complete (rc $ORC): $(grep -E 'BLOCKED|REFUSED' "$WORK/org.out" "$WORK/org.err" | head -2 | tr '\n' ' ')"; return; }
  [ -n "$FP1" ] && [ -n "$FP2" ] || { fail_ "$label" "the fixture produced fewer than two fingerprints"; return; }
  ( cd "$O" && git ls-files --error-unmatch "$JT" ) >/dev/null 2>&1 || bad="$bad [$JT is not in the adoption commit]"
  head="$(cd "$O" && git rev-parse HEAD~1)"
  [ "$(jq -r '.scan.head' "$O/$JT")" = "$head" ] || bad="$bad [scan.head is not the commit the scan read]"
  [ "$(jq -r '.scan.commitsScanned' "$O/$JT")" = "2" ] || bad="$bad [scan.commitsScanned is not 2]"
  [ "$(jq -r '.scan.reportSha256' "$O/$JT")" = "$(shasum -a 256 "$O/.claude/adoption/scout-report.json" 2>/dev/null | cut -c1-64)" ] \
    || bad="$bad [scan.reportSha256 is not the sha256 of the committed scout-report.json]"
  [ "$(jq -r --arg a "$FP1" '.dispositions[] | select(.fingerprint == $a) | .disposition' "$O/$JT")" = "accepted-risk" ] || bad="$bad [the accepted risk is not recorded]"
  [ "$(jq -r --arg b "$FP2" '.dispositions[] | select(.fingerprint == $b) | .disposition' "$O/$JT")" = "rotated" ] || bad="$bad [the rotation is not recorded]"
  grep -q 'TBMR2VKD\|KLMN3PQR' "$O/$JT" "$O/.claude/bypass-audit.json" && bad="$bad [a matched value reached a record]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

r2() {
  local label="R2 exactly one secrets_disposition row — the accepted risk; the rotation writes none" bad="" rows
  rows="$(_rows "$O" secrets_disposition)"
  [ "$(printf '%s\n' "$rows" | grep -c .)" -eq 1 ] || bad="$bad [$(printf '%s\n' "$rows" | grep -c .) rows, not 1]"
  printf '%s\n' "$rows" | jq -e --arg a "$FP1" '.details.fingerprint == $a and .details.by == "Jane Ops" and .details.date == "2026-09-24" and .actor == "framework" and .final_outcome == "recorded_only"' >/dev/null 2>&1 \
    || bad="$bad [the row does not carry the accepted fingerprint, name and date: $rows]"
  ( cd "$O" && git ls-files --error-unmatch .claude/bypass-audit.json ) >/dev/null 2>&1 || bad="$bad [the ledger is not committed]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

r3() {
  local label="R3 a stray acknowledgement, never accepted by this run, is NOT written down" bad=""
  [ -f "$O/$JT" ] || { fail_ "$label" "no join table"; return; }
  grep -q 'Stale' "$O/$JT" "$O/.claude/bypass-audit.json" && bad="$bad [the stray acknowledgement's signer was recorded]"
  [ "$(jq '.acknowledgements | length' "$O/$JT")" = "0" ] || bad="$bad [a stray acknowledgement was recorded for a fully scanned run]"
  [ "$(jq '.dispositions | length' "$O/$JT")" = "2" ] || bad="$bad [$(jq '.dispositions | length' "$O/$JT") dispositions, not 2]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

r4() {
  local label="R4 every adoption writes the adoption row, naming the tier and the commit, committed" bad="" p row want
  for p in "$O:organizational" "$C:personal"; do
    row="$(_rows "${p%%:*}" adoption)"
    want="$(cd "${p%%:*}" && git rev-parse HEAD~1)"
    [ "$(printf '%s\n' "$row" | grep -c .)" -eq 1 ] || { bad="$bad [$(basename "${p%%:*}"): $(printf '%s\n' "$row" | grep -c .) adoption rows]"; continue; }
    printf '%s\n' "$row" | jq -e --arg t "${p#*:}" --arg c "$want" '.details.deployment == $t and .details.adoptedAtCommit == $c and .details.landedPhase == 0' >/dev/null 2>&1 \
      || bad="$bad [$(basename "${p%%:*}"): the row does not name the tier and commit: $row]"
    ( cd "${p%%:*}" && git ls-files --error-unmatch .claude/bypass-audit.json && git diff --quiet HEAD -- .claude/bypass-audit.json ) >/dev/null 2>&1 \
      || bad="$bad [$(basename "${p%%:*}"): the ledger is not committed as written]"
  done
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

r5() {
  local label="R5 a clean personal adoption still commits the join table, with its scan block" bad=""
  [ "$CRC" -eq 0 ] || { fail_ "$label" "rc $CRC"; return; }
  jq -e '.schemaVersion == 1 and .scan.status == "scanned" and (.scan.head | length) == 40 and .dispositions == [] and .acknowledgements == []' "$C/$JT" >/dev/null 2>&1 \
    || bad="$bad [the table is not the empty record of a clean scan: $(head -c 300 "$C/$JT" 2>/dev/null)]"
  ( cd "$C" && git ls-files --error-unmatch "$JT" ) >/dev/null 2>&1 || bad="$bad [not committed]"
  [ -z "$(_rows "$C" secrets_disposition)" ] || bad="$bad [a clean scan wrote a disposition row]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

# ── N: personal, no scanner on PATH ─────────────────────────────────────────
_nopath_run() {   # _nopath_run DIR TAG [args...]
  local p="$1" tag="$2"; shift 2
  # TEN answers, not five: the intake's confirmations come from Scout's report,
  # and how many there are depends on which tools the environment has. On the
  # ubuntu runner a narrowed PATH hides more than on macOS, and a "Tooling
  # Configuration" confirmation appears that five answers ran out before
  # (PR #446, R6/R7 red on CI only). Unread answers are harmless.
  printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n' > "$WORK/ans-$tag"
  ( cd "$p" && PATH=/usr/bin:/bin bash "$REPO_ROOT/scripts/adopt-project.sh" "$@" < "$WORK/ans-$tag" ) \
    > "$WORK/$tag.out" 2> "$WORK/$tag.err"
  RUN_RC=$?
}
_ack() {   # _ack DIR TAG — stop, fill the printed acknowledgement, re-run
  local p="$1" tag="$2"
  _nopath_run "$p" "$tag-stop"
  sed -n '/ready to fill in/,$p' "$WORK/$tag-stop.out" | grep '^      ' | sed 's/^      //' \
    | jq '.acknowledgements[0] |= (.by="Karl" | .reason="personal repo, scanner later" | .date="2026-09-24")
          | .acknowledgements += [(.acknowledgements[0] | .by="" | .reason="unsigned second" | .date="not-a-date")]' > "$WORK/$tag-ack.json" 2>/dev/null
  _nopath_run "$p" "$tag" --dispositions "$WORK/$tag-ack.json"
}

r6() {
  local label="R6 a personal no-scanner adoption records its acknowledgement in the table AND as a row" bad="" p="$WORK/noscan"
  command -v /usr/bin/jq >/dev/null 2>&1 || { skip "$label" "jq is not in /usr/bin, so PATH cannot be narrowed to hide the scanner"; return; }
  _base "$p"; _ack "$p" noscan
  [ "$RUN_RC" -eq 0 ] || { fail_ "$label" "rc $RUN_RC: $(grep -E 'BLOCKED|REFUSED' "$WORK/noscan.out" "$WORK/noscan.err" | head -2 | tr '\n' ' ')"; return; }
  jq -e '.acknowledgements | length == 1 and .[0].kind == "tool-unavailable" and .[0].by == "Karl"' "$p/$JT" >/dev/null 2>&1 || bad="$bad [the table does not hold exactly the one signed acknowledgement]"
  grep -q 'unsigned second\|not-a-date' "$p/$JT" "$p/.claude/bypass-audit.json" "$p/APPROVAL_LOG.md" && bad="$bad [an unsigned acknowledgement was recorded]"
  _rows "$p" secrets_disposition | jq -e '.details.kind == "tool-unavailable" and .details.by == "Karl"' >/dev/null 2>&1 || bad="$bad [no row for the acknowledgement]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

r7() {
  local label="R7 an acknowledgement that cannot be recorded BLOCKS the run, and nothing is committed" bad="" p="$WORK/badledger" before
  command -v /usr/bin/jq >/dev/null 2>&1 || { skip "$label" "jq is not in /usr/bin"; return; }
  _base "$p"
  mkdir -p "$p/.claude"; printf '{ not json\n' > "$p/.claude/bypass-audit.json"
  before="$(cd "$p" && git rev-parse HEAD)"
  _ack "$p" badledger
  [ "$RUN_RC" -eq 1 ] || bad="$bad [rc $RUN_RC, not 1]"
  grep -q 'could not be recorded' "$WORK/badledger.out" "$WORK/badledger.err" || bad="$bad [the block does not say the acceptance could not be recorded]"
  grep -qF 'jq . .claude/bypass-audit.json' "$WORK/badledger.out" "$WORK/badledger.err" || bad="$bad [the remedy never reached the operator]"
  # THE REHEARSAL'S OWN WRITE-STATE MUST NOT LEAK. It raised this block against
  # the COPY, and its "N file(s) were already written into this project" once
  # printed beneath the real run's "nothing was written to your project".
  grep -q 'file(s) were already written' "$WORK/badledger.out" "$WORK/badledger.err" && bad="$bad [the copy's write-state was reported as this project's]"
  [ "$(cd "$p" && git rev-parse HEAD)" = "$before" ] || bad="$bad [a commit landed]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

r8() {
  local label="R8 the dispositions stage sits after intake and before manifest" order
  order="$( ( set +u; . "$REPO_ROOT/scripts/lib/adopt/adopt-state.sh" >/dev/null 2>&1; _adopt_state_order ) | tr '\n' ' ')"
  case "$order" in
    *"intake dispositions manifest"*) pass "$label" ;;
    *) fail_ "$label" "order is: $order" ;;
  esac
}

r9() {
  local label="R9 personal, findings: an unsigned or out-of-scan disposition is recorded nowhere, the signed one everywhere" bad="" p="$WORK/personal-findings"
  _base "$p"
  printf 'aws_access_key_id = %s\n' "AKIA3XN7QW5Z""TBMR2VKD" > "$p/src/config.py"
  printf 'aws_access_key_id = %s\n' "AKIA7ZQ2WX4Y""KLMN3PQR" > "$p/src/deploy.py"
  ( cd "$p" && git add src/config.py src/deploy.py && git commit -q --no-verify -m "chore: two leaked keys" ) >/dev/null 2>&1
  # The organizational template of the SAME two findings, filled one complete
  # and one with no name, handed to a personal run.
  # Fingerprints carry the COMMIT, so this project's are its own: the
  # organizational template's, re-pointed at this history.
  local oc pc
  oc="$(cd "$O" && git rev-parse HEAD~1)"; pc="$(cd "$p" && git rev-parse HEAD)"
  sed "s/$oc/$pc/g" "$WORK/tpl.json" > "$WORK/tpl-p.json"
  jq --arg a "${FP1/$oc/$pc}" '.dispositions |= map(if .fingerprint == $a
        then .disposition="accepted-risk" | .by="Jane Ops" | .reason="test key" | .date="2026-09-24"
        else .disposition="accepted-risk" | .by="" | .reason="nobody signed this" | .date="2026-09-24" end)
      | .dispositions += [{fingerprint:"deadbeef:src/x.py:aws-access-token:1", disposition:"accepted-risk", by:"Mallory", reason:"alien row", date:"2026-09-24"}]
      | .acknowledgements = []' "$WORK/tpl-p.json" > "$WORK/half.json"
  _run "$p" personal-findings 1 --dispositions "$WORK/half.json"
  [ "$RUN_RC" -eq 0 ] || { fail_ "$label" "rc $RUN_RC: $(grep -E 'BLOCKED|REFUSED' "$WORK/personal-findings.out" "$WORK/personal-findings.err" | head -2 | tr '\n' ' ')"; return; }
  [ "$(jq '.dispositions | length' "$p/$JT")" = "1" ] || bad="$bad [$(jq '.dispositions | length' "$p/$JT") dispositions recorded, not 1]"
  grep -q 'nobody signed this' "$p/$JT" "$p/.claude/bypass-audit.json" "$p/APPROVAL_LOG.md" && bad="$bad [the unsigned disposition was recorded]"
  # A COMPLETE row for a fingerprint THIS scan never produced. On a personal run
  # no validator refuses it, so the filter is the only guard — and the record
  # must agree with the table (review: the record once printed both rows).
  grep -q 'Mallory\|deadbeef' "$p/$JT" "$p/.claude/bypass-audit.json" "$p/APPROVAL_LOG.md" && bad="$bad [a fingerprint from outside this scan was recorded]"
  grep -q '| accepted-risk | Jane Ops |' "$p/APPROVAL_LOG.md" || bad="$bad [the accepted decision is not in the Adoption Record]"
  [ "$(_rows "$p" secrets_disposition | grep -c .)" -eq 1 ] || bad="$bad [$(_rows "$p" secrets_disposition | grep -c .) rows, not 1]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

r10() {
  local label="R10 a project that already carries an audit ledger is adopted, and its rows survive" bad="" p="$WORK/ownledger"
  _base "$p"
  mkdir -p "$p/.claude"
  printf '[{"type":"escalation","details":{"theirs":"PRIOR-ROW-MARKER"}}]\n' > "$p/.claude/bypass-audit.json"
  ( cd "$p" && git add .claude/bypass-audit.json && git commit -q --no-verify -m "chore: their ledger" ) >/dev/null 2>&1
  _run "$p" ownledger 1
  [ "$RUN_RC" -eq 0 ] || { fail_ "$label" "rc $RUN_RC: $(grep -E 'BLOCKED|REFUSED' "$WORK/ownledger.out" "$WORK/ownledger.err" | head -2 | tr '\n' ' ')"; return; }
  grep -q 'PRIOR-ROW-MARKER' "$p/.claude/bypass-audit.json" || bad="$bad [the operator's own row was lost]"
  [ "$(_rows "$p" adoption | grep -c .)" -eq 1 ] || bad="$bad [no adoption row appended]"
  ( cd "$p" && git diff --quiet HEAD -- .claude/bypass-audit.json ) || bad="$bad [the appended ledger is not committed]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

r11() {
  local label="R11 a dispositions file bound to ANOTHER scan contributes nothing, on a personal run" bad="" p="$WORK/stale" pc
  _base "$p"
  printf 'aws_access_key_id = %s\n' "AKIA3XN7QW5Z""TBMR2VKD" > "$p/src/config.py"
  ( cd "$p" && git add src/config.py && git commit -q --no-verify -m "chore: a leaked key" ) >/dev/null 2>&1
  pc="$(cd "$p" && git rev-parse HEAD)"
  # Every row is complete and names a real finding of THIS history — only the
  # binding is wrong.
  jq -n --arg fp "$pc:src/config.py:aws-access-token:1" \
    '{scan: {head: "0000000000000000000000000000000000000000", commitsScanned: 99},
      dispositions: [{fingerprint: $fp, disposition: "accepted-risk", by: "Stale Sam", reason: "from another scan", date: "2026-09-24"}],
      acknowledgements: []}' > "$WORK/stale.json"
  _run "$p" stale 1 --dispositions "$WORK/stale.json"
  [ "$RUN_RC" -eq 0 ] || { fail_ "$label" "rc $RUN_RC"; return; }
  # DISCRIMINATING ONLY IF THE FINGERPRINT IS REAL: were it not one of this
  # scan's findings, the row would be dropped for that reason and this case
  # would pass without testing the binding at all.
  jq -e --arg fp "$pc:src/config.py:aws-access-token:1" '[.secrets.findings[]?.fingerprint] | index($fp)' \
    "$p/.claude/adoption/scout-report.json" >/dev/null 2>&1 \
    || { fail_ "$label" "fixture: the fingerprint is not one of this scan's — the case would not test the binding"; return; }
  grep -q 'Stale Sam' "$p/$JT" "$p/.claude/bypass-audit.json" "$p/APPROVAL_LOG.md" && bad="$bad [a stale file's decision was recorded as this scan's]"
  grep -q 'bound to another scan' "$p/APPROVAL_LOG.md" || bad="$bad [the record does not say why nothing is recorded]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

r1; r2; r3; r4; r5; r6; r7; r8; r9; r10; r11

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
