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

_check() {   # _check FILE — the shipped checker's output
  ( set +u; . "$REPO_ROOT/scripts/lib/adopt/adopt-intake.sh" >/dev/null 2>&1; adopt_provenance_errors "$1" )
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
  # And for the RIGHT reason: rejected as "never closed" it would still be
  # rejected, but the operator would be sent to fix the wrong thing.
  _check "$WORK/late.md" | grep -q 'first content' || bad="$bad [a header that is not the first content is not rejected as such]"
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
  grep -q 'PROJECT_INTAKE.md: ' "$WORK/v4.out" || bad="$bad [the refusal does not name the header]"
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

v1; v2; v3; v4; v5
echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
