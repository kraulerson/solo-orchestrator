#!/usr/bin/env bash
# tests/test-brownfield-dispositions-template.sh — the secrets stop has a way
# through it that an operator can actually take.
#
# SPEC: docs/designs/2026-08-23-brownfield-adoption-v2.md §6.1 (the tier table)
# and §6.3 (the dispositions file and its binding to one scan). Backlog:
# `## BL-242:`. Marker: `# BL-242-DISPOSITIONS-TEMPLATE`.
#
# THE DEFECT THIS PINS. An organizational adoption whose history holds a single
# credential finding STOPS, correctly, and tells the operator to "record one
# [disposition] per finding … and pass the file with --dispositions". The file
# the validator accepts must carry each finding's gitleaks FINGERPRINT and the
# scan's own `head` and `commitsScanned` — and no line of the run printed any of
# the three, while the scan report sat in a temporary directory the run deletes
# on exit. The stop was right and the way through it did not exist: nobody who
# had not read the validator's source could complete such an adoption.
#
# So the stop now PRINTS a ready-to-fill file, built by `jq` from the same report
# the validator reads. This suite proves the whole round trip on a real adoption:
# stop → template → fill → complete, with the decision in the Adoption Record.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

echo "== the secrets stop's dispositions template =="

for t in git jq gitleaks; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH — the round trip needs a real scan"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done

WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT
P="$WORK/proj"

# An adoptee whose HISTORY holds a key gitleaks matches. Assembled at runtime so
# this source file carries none (the `HOOK_PLANT` idiom in the wp6 suite).
mkdir -p "$P/src"
( cd "$P" && git init -q . && git config user.email disp@test.invalid && git config user.name "Disp Test" ) >/dev/null 2>&1
printf '{"name":"acme","scripts":{"test":"exit 0"}}\n' > "$P/package.json"
printf '# acme\n' > "$P/README.md"
printf 'aws_access_key_id = %s\n' "AKIA3XN7QW5Z""TBMR2VKD" > "$P/src/config.py"
( cd "$P" && git add package.json README.md src/config.py \
    && git commit -q --no-verify -m "chore: their history, with a leaked key" ) >/dev/null 2>&1

# 2 = "A company, a client, or people who are paying for it" — organizational.
printf '2\n1\n1\n1\n1\n' > "$WORK/ans"
_run() {   # _run TAG [--dispositions FILE]
  local tag="$1"; shift
  ( cd "$P" && bash "$REPO_ROOT/scripts/adopt-project.sh" "$@" < "$WORK/ans" ) \
    > "$WORK/$tag.out" 2> "$WORK/$tag.err"
  RUN_RC=$?
}
_template_from() {  # the JSON the run printed: 6-space-indented lines after the prompt
  sed -n '/ready to fill in/,$p' "$1" | grep '^      ' | sed 's/^      //'
}

_run first

# ═══════════════════════════════════════════════════════════════════════════
t1() {
  local label="T1 an organizational stop prints a template bound to THIS scan, and writes nothing"
  local bad="" tpl="$WORK/tpl.json" head n_fp
  [ "$RUN_RC" -eq 1 ] || bad="$bad [rc $RUN_RC, not 1 — the stop did not fire, so nothing below is under test]"
  [ "$(cd "$P" && git status --porcelain | grep -c .)" -eq 0 ] || bad="$bad [the refused run left changes in the project]"
  _template_from "$WORK/first.out" > "$tpl"
  local jqerr
  jqerr="$(jq -e . "$tpl" 2>&1 >/dev/null)" \
    || { fail_ "$label" "$bad [no valid JSON template was printed — jq: ${jqerr:-no output}; captured: $(head -c 200 "$tpl" | tr '\n' ' ')]"; return; }
  # BOUND BY CONSTRUCTION: the head is the commit the scan read, and there is one
  # row per finding, each carrying a fingerprint.
  head="$(cd "$P" && git rev-parse HEAD)"
  [ "$(jq -r '.scan.head' "$tpl")" = "$head" ] || bad="$bad [scan.head is not the commit the scan read]"
  [ "$(jq -r '.scan.commitsScanned' "$tpl")" = "1" ] || bad="$bad [scan.commitsScanned is not 1]"
  n_fp="$(jq '[.dispositions[] | select((.fingerprint // "") != "")] | length' "$tpl")"
  [ "$n_fp" -ge 1 ] || bad="$bad [no fingerprint to disposition]"
  # AND NEVER THE SECRET. A fingerprint names where a match is, not what it is.
  grep -q 'TBMR2VKD' "$WORK/first.out" && bad="$bad [the matched value reached the run's output]"
  [ -z "$bad" ] && pass "$label ($n_fp finding(s))" || fail_ "$label" "$bad"
}

t2() {
  local label="T2 the template UNFILLED does not lift the stop"
  # Otherwise printing it would be a one-step bypass: copy, paste, adopted.
  _run unfilled --dispositions "$WORK/tpl.json"
  if [ "$RUN_RC" -eq 1 ] && [ "$(cd "$P" && git log --oneline | grep -c .)" -eq 1 ]; then
    pass "$label"
  else
    fail_ "$label" "rc $RUN_RC and $(cd "$P" && git log --oneline | grep -c .) commit(s) — an empty template lifted an organizational stop"
  fi
}

t3() {
  local label="T3 the template FILLED completes the adoption, and the Record carries the decision"
  local bad=""
  jq '.dispositions |= map(.disposition="rotated" | .by="Jane Ops" | .reason="key revoked at the provider" | .date="2026-09-24")' \
    "$WORK/tpl.json" > "$WORK/filled.json"
  _run filled --dispositions "$WORK/filled.json"
  [ "$RUN_RC" -eq 0 ] || bad="$bad [rc $RUN_RC — a correctly filled template did not lift the stop: $(grep -E 'dispositions file|BLOCKED' "$WORK/filled.out" "$WORK/filled.err" | head -2 | tr '\n' ' ')]"
  grep -q 'Every finding carries a recorded disposition' "$WORK/filled.out" || bad="$bad [the run never said the dispositions were accepted]"
  grep -q '| rotated | Jane Ops |' "$P/APPROVAL_LOG.md" 2>/dev/null || bad="$bad [the Adoption Record does not carry the decision]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# T4 — the ACKNOWLEDGEMENT arms (personal tier: no scanner, or a shallow clone)
# print their own shape. Unit level, against the shipped validator, because
# producing "no scanner" in a real adoption means hiding gitleaks from PATH,
# which this suite's other cases need.
# ═══════════════════════════════════════════════════════════════════════════
t4() {
  local label="T4 the acknowledgement template, filled, satisfies the validator; unfilled, it does not"
  local bad="" r="$WORK/ack-report.json" k out
  for k in tool-unavailable scanned-partial; do
    if [ "$k" = tool-unavailable ]; then
      printf '{"secrets":{"status":"tool-unavailable","head":"abc123","commitsScanned":null,"findingCount":0}}\n' > "$r"
    else
      printf '{"secrets":{"status":"scanned-partial","head":"abc123","commitsScanned":7,"findingCount":0}}\n' > "$r"
    fi
    out="$(
      set +u
      . "$REPO_ROOT/scripts/lib/adopt/adopt-core.sh" >/dev/null 2>&1
      . "$REPO_ROOT/scripts/lib/adopt/adopt-secrets.sh" >/dev/null 2>&1
      _adopt_secrets_disposition_template "$r" "$k" | sed -n '/ready to fill in/,$p' | grep '^      ' | sed 's/^      //'
    )"
    printf '%s\n' "$out" > "$WORK/ack-$k.json"
    jq -e --arg k "$k" '.acknowledgements[0].kind == $k' "$WORK/ack-$k.json" >/dev/null 2>&1 \
      || { bad="$bad [$k: no acknowledgement of the right kind]"; continue; }
    jq '.acknowledgements[0] |= (.by="Karl" | .reason="accepted for a personal repo" | .date="2026-09-24")' \
      "$WORK/ack-$k.json" > "$WORK/ack-$k-filled.json"
    ( set +u
      . "$REPO_ROOT/scripts/lib/adopt/adopt-core.sh" >/dev/null 2>&1
      . "$REPO_ROOT/scripts/lib/adopt/adopt-secrets.sh" >/dev/null 2>&1
      adopt_dispositions_satisfy "$r" "$WORK/ack-$k-filled.json" "$k" >/dev/null 2>&1 ) \
      || bad="$bad [$k: the FILLED template is refused by the validator]"
    ( set +u
      . "$REPO_ROOT/scripts/lib/adopt/adopt-core.sh" >/dev/null 2>&1
      . "$REPO_ROOT/scripts/lib/adopt/adopt-secrets.sh" >/dev/null 2>&1
      adopt_dispositions_satisfy "$r" "$WORK/ack-$k.json" "$k" >/dev/null 2>&1 ) \
      && bad="$bad [$k: the UNFILLED template is accepted — a one-step bypass]"
  done
  [ -z "$bad" ] && pass "$label (tool-unavailable, scanned-partial)" || fail_ "$label" "$bad"
}

t1; t2; t3; t4

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
