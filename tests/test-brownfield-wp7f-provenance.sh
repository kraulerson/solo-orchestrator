#!/usr/bin/env bash
# tests/test-brownfield-wp7f-provenance.sh — WP7: the provenance header on the
# document adoption reconstructs, and the check that tells it from a near-miss.
#
# SPEC: ADOPT-002-ARCH v1 §8.6 (carried by v2): every document adoption writes
# that describes WHAT ALREADY EXISTED opens with a fenced provenance header;
# a forward-looking document carries none; "a near-miss header is worse than
# none", so the check is exact. Backlog: `## BL-242:`.
#
# WHY A TEST AND NOT A scripts/lint-*.sh: the Adoption Record's reason
# (tests/test-brownfield-wp7-adoption-record.sh's header) — a core lint may not
# source the adoption module. The enforcement is the module's own: the header
# is checked where it is written and again by the Act 4 finisher.
#
# WHAT EACH CASE OWNS.
#   V1  a real adoption's PROJECT_INTAKE.md opens with a well-formed header
#       naming the commit it was reconstructed from
#   V2  no forward-looking document adoption writes carries one
#   V3  the check accepts the genuine article and rejects each near-miss
#   V4  the Act 4 finisher refuses a PROJECT_INTAKE.md whose header the
#       conversation broke, and writes nothing
#   V5  the stub is retired
#   V6  a malformed header refuses the write itself
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

echo "== WP7 — provenance headers =="
for t in git jq; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done
WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT

_check() {   # _check FILE [COMMIT] — the shipped checker's output
  ( set +u; . "$REPO_ROOT/scripts/lib/adopt/adopt-intake.sh" >/dev/null 2>&1; adopt_provenance_errors "$1" "${2:-}" )
}

P="$WORK/p"
mkdir -p "$P/src"
( cd "$P" && git init -q . && git config user.email wp7f@test.invalid && git config user.name "WP7f Test" ) >/dev/null 2>&1
printf '{"name":"acme","scripts":{"test":"exit 0"}}\n' > "$P/package.json"
( cd "$P" && git add package.json && git commit -q --no-verify -m "chore: their history" ) >/dev/null 2>&1
PRE="$(cd "$P" && git rev-parse --short=12 HEAD)"
( cd "$P" && printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n' | bash "$REPO_ROOT/scripts/adopt-project.sh" ) > "$WORK/adopt.out" 2>&1
ARC=$?

v1() {
  local label="V1 PROJECT_INTAKE.md opens with a well-formed header naming the commit it was reconstructed from" bad="" errs
  [ "$ARC" -eq 0 ] || { fail_ "$label" "the adoption did not complete: $(tail -3 "$WORK/adopt.out" | tr '\n' ' ')"; return; }
  errs="$(_check "$P/PROJECT_INTAKE.md")"
  [ -z "$errs" ] || bad="$bad [the checker rejects it: $errs]"
  [ "$(head -1 "$P/PROJECT_INTAKE.md")" = "<!-- SOIF-PROVENANCE-BEGIN" ] || bad="$bad [it is not the first line]"
  grep -qxF "source: existing codebase at $PRE + adoption survey" "$P/PROJECT_INTAKE.md" || bad="$bad [it does not name the pre-adoption commit $PRE]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

v2() {
  local label="V2 no forward-looking document adoption writes carries a header" bad="" f
  for f in CLAUDE.md FEATURES.md BUGS.md RELEASE_NOTES.md docs/INDEX.md docs/IDENTIFIERS.md APPROVAL_LOG.md .claude/adoption/assessment-prompt.md; do
    [ -f "$P/$f" ] || { bad="$bad [$f was not written — the case cannot check it]"; continue; }
    # The OPENING LINE, not the word: the assessment prompt tells the model to
    # keep the header, and names it to do so.
    grep -qxF '<!-- SOIF-PROVENANCE-BEGIN' "$P/$f" && bad="$bad [$f carries one]"
  done
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

v3() {
  local label="V3 the check accepts the genuine header and rejects each near-miss" bad="" good="$WORK/good.md" name e
  cp "$P/PROJECT_INTAKE.md" "$good"
  [ -z "$(_check "$good")" ] || bad="$bad [the genuine article is rejected]"
  while IFS='|' read -r name e; do
    [ -n "$name" ] || continue
    sed "$e" "$good" > "$WORK/near.md"
    cmp -s "$good" "$WORK/near.md" && { bad="$bad [$name: the near-miss fixture did not change the file]"; continue; }
    [ -n "$(_check "$WORK/near.md")" ] || bad="$bad [$name accepted]"
  done <<NEAR
no closing line|/^SOIF-PROVENANCE-END -->$/d
renamed key|s/^reconstructed-by:/reconstructed_by:/
date not a date|s/^reconstructed-at: .*/reconstructed-at: today/
no commit|s/^source: existing codebase at [0-9a-f]* /source: existing codebase at HEAD /
status reworded|s/^status: describes/status: Describes/
opening misspelled|s/^<!-- SOIF-PROVENANCE-BEGIN$/<!-- SOIF_PROVENANCE-BEGIN/
NEAR
  awk '{print} /^status:/{print "extra: field"}' "$good" > "$WORK/extra.md"
  [ -n "$(_check "$WORK/extra.md")" ] || bad="$bad [a fifth field accepted]"
  { printf '# Title first\n\n'; cat "$good"; } > "$WORK/late.md"
  # And for the RIGHT reason: without that arm the file is still rejected, but
  # as "line 1 of the header is not reconstructed-at …" and "more than four
  # fields" — which sends the operator to fix the wrong thing.
  _check "$WORK/late.md" | grep -q 'first content' || bad="$bad [a header that is not the first content is not rejected as such]"
  # MEANING, not only shape: a date that is not a day, and a commit that is not
  # this project's (review: both passed a shape-only check).
  sed 's/^reconstructed-at: .*/reconstructed-at: 2026-02-30/' "$good" > "$WORK/feb30.md"
  [ -n "$(_check "$WORK/feb30.md")" ] || bad="$bad [2026-02-30 accepted]"
  [ -n "$(_check "$good" "0000000000000000000000000000000000000000")" ] || bad="$bad [a header naming another commit accepted]"
  [ -z "$(_check "$good" "$(cd "$P" && git rev-parse HEAD~1)")" ] || bad="$bad [the header naming THIS project's commit rejected]"
  # AN EDITOR'S RE-SAVE IS TOLERATED: CRLF, a byte-order mark, trailing space.
  sed 's/$/\r/' "$good" > "$WORK/crlf.md"
  [ -z "$(_check "$WORK/crlf.md")" ] || bad="$bad [CRLF line endings rejected: $(_check "$WORK/crlf.md" | head -1)]"
  { printf '\357\273\277'; cat "$good"; } > "$WORK/bom.md"
  [ -z "$(_check "$WORK/bom.md")" ] || bad="$bad [a byte-order mark rejected]"
  sed 's/^SOIF-PROVENANCE-END -->$/& /' "$good" > "$WORK/trail.md"
  [ -z "$(_check "$WORK/trail.md")" ] || bad="$bad [trailing space rejected]"
  sed '1,/^SOIF-PROVENANCE-END -->$/d' "$good" > "$WORK/none.md"
  [ -n "$(_check "$WORK/none.md")" ] || bad="$bad [a file with no header accepted]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

v4() {
  local label="V4 the finisher refuses a PROJECT_INTAKE.md whose header was broken, and writes nothing" bad="" commit before
  commit="$(jq -r '.adoption.adoptedAtCommit' "$P/.claude/manifest.json")"
  jq -n --arg c "$commit" '{schemaVersion:1, assessedAt:"2026-09-25T00:00:00Z", adoptedAtCommit:$c,
    interview:{users:"3",availability:"a",exposure:"e",scalability:"s",dataClassification:"internal",
               zdrAttested:true,zdrReason:"",inProduction:true,operations:{},answers:{}},
    evaluators:[], fitness:{verdict:"keep",findings:[]}, plan:{path:"p",summary:"s"},
    verdictArtifact:".claude/adoption/verdict.md"}' > "$P/.claude/adoption/assessment-record.json"
  printf '# V\n\nFits.\n\n## Plain English\n\nRecommendation: keep.\nReason: fits.\n' > "$P/.claude/adoption/verdict.md"
  cp "$P/PROJECT_INTAKE.md" "$WORK/intake.bak"
  sed '/^SOIF-PROVENANCE-END -->$/d' "$WORK/intake.bak" > "$P/PROJECT_INTAKE.md"
  before="$(cat "$P/.claude/manifest.json" "$P/.claude/process-state.json" | shasum -a 256)"
  ( cd "$P" && bash "$REPO_ROOT/scripts/adopt-project.sh" --act4 --root . ) > "$WORK/v4.out" 2>&1
  [ "$?" -ne 0 ] || bad="$bad [rc 0 with a broken header]"
  grep -q 'PROJECT_INTAKE.md: the header' "$WORK/v4.out" || bad="$bad [the refusal does not name the header's defect]"
  grep -qE 'git show [0-9a-f]+:PROJECT_INTAKE.md \| sed -n 1,6p' "$WORK/v4.out" || bad="$bad [the refusal gives no way to restore the header]"
  grep -q 'Fix .claude/adoption/assessment-record.json' "$WORK/v4.out" && bad="$bad [the refusal sends the operator to the record, not the intake]"
  [ "$(cat "$P/.claude/manifest.json" "$P/.claude/process-state.json" | shasum -a 256)" = "$before" ] || bad="$bad [something was written]"
  cp "$WORK/intake.bak" "$P/PROJECT_INTAKE.md"
  ( cd "$P" && bash "$REPO_ROOT/scripts/adopt-project.sh" --act4 --root . ) > "$WORK/v4b.out" 2>&1
  [ "$?" -eq 0 ] || bad="$bad [the same record with the header intact was refused: $(grep -- '- ' "$WORK/v4b.out" | head -2 | tr '\n' ' ')]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

v5() {
  local label="V5 the provenance stub is retired, not merely silent" bad=""
  grep -q 'NOT DONE — the provenance headers' "$WORK/adopt.out" && bad="$bad [the run still announces it]"
  grep -rqE '^[[:space:]]*adopt_stub_provenance_headers[[:space:]]*$' "$REPO_ROOT/scripts" && bad="$bad [it is still called]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

v6() {
  local label="V6 a malformed header refuses the WRITE — the adoption does not land with it" bad="" q="$WORK/fault"
  mkdir -p "$q"
  ( cd "$q" && git init -q . && git config user.email wp7f@test.invalid && git config user.name "WP7f Test" ) >/dev/null 2>&1
  printf '{"name":"acme","scripts":{"test":"exit 0"}}\n' > "$q/package.json"
  ( cd "$q" && git add package.json && git commit -q --no-verify -m "chore: their history" ) >/dev/null 2>&1
  ( cd "$q" && printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n' | SOIF_ADOPT_PROVENANCE_FAULT=noend bash "$REPO_ROOT/scripts/adopt-project.sh" ) > "$WORK/v6.out" 2>&1
  [ "$?" -ne 0 ] || bad="$bad [rc 0 with a malformed header]"
  grep -q "provenance header is malformed" "$WORK/v6.out" || bad="$bad [the refusal does not name the header]"
  [ "$(cd "$q" && git log --oneline | grep -c .)" -eq 1 ] || bad="$bad [an adoption commit landed]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

v1; v2; v3; v4; v5; v6
echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
