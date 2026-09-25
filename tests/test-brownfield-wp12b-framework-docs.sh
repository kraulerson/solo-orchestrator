#!/usr/bin/env bash
# tests/test-brownfield-wp12b-framework-docs.sh — WP12b: the framework
# documents an adopted project receives.
#
# SPEC: `## BL-242:` D3 and its 2026-08-31 reach ruling — an adopted project
# gets the framework's documents, the originals are archived and never
# deleted, and adoption NAMES each replaced one to the operator with an
# invitation to retrieve content from the archive.
#
# Two real adoptions, not a stubbed renderer: the defect this package closes
# was an adopted project with no CLAUDE.md, and only a real run shows whether
# one is there, rendered, committed, and consistent with the archive's record.
#
# WHAT EACH CASE OWNS.
#   D1     CLAUDE.md is written, fully rendered, and committed
#   D2     the six templates and the reference guides are written and committed
#   D3     a replaced original is archived as `replaced` and NAMED on screen
#          with the archive's location — D3's informing half
#   D4     a SYMLINKED document is left alone: link intact, target untouched,
#          archive row `kept`, named on screen
#   D5     a READ-ONLY document is left alone, row `kept`, named on screen
#   D6     a HARDLINKED document is replaced without writing through the
#          shared inode
#   D7     a reference guide the project already has is not overwritten
#   D8     the stage sits after `manifest` and before `adoption_record`
#   D9     the stub is retired, not merely silent
#   D10    the tier reaches the render: organizational gets the branch-
#          protection section, personal does not
#   D11    a document inside a SYMLINKED FOLDER is left alone — the folder's
#          real contents outside the project survive, adoption completes, and
#          the archive row says `kept` (found by review: the first cut wrote
#          through `docs -> /elsewhere`, even during the rehearsal)
#   D12    an intake value carrying a newline cannot reach the renderer's sed
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

echo "== WP12b — the framework documents an adopted project receives =="

for t in git jq; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done

WORK="$(mktemp -d)" || exit 1
# chmod first: D5's read-only fixture would otherwise survive the cleanup.
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

# _adoptee DIR — a small real project with its own history.
_adoptee() {
  local p="$1"
  mkdir -p "$p/src" "$p/docs" || return 1
  ( cd "$p" && git init -q . \
      && git config user.email wp12b@test.invalid \
      && git config user.name "WP12b Test" ) >/dev/null 2>&1 || return 1
  printf '{"name":"acme","scripts":{"test":"exit 0"}}\n' > "$p/package.json"
  printf '# acme\n' > "$p/README.md"
  ( cd "$p" && git add package.json README.md \
      && git commit -q -m "chore: their own history" ) >/dev/null 2>&1 || return 1
}

# _adopt DIR TAG AUDIENCE — a real adoption. AUDIENCE is the first answer:
# 1 personal, 2 organizational.
_adopt() {
  local p="$1" tag="$2" aud="$3"
  printf '%s\n1\n1\n1\n1\n' "$aud" > "$WORK/ans-$tag"
  ( cd "$p" && bash "$REPO_ROOT/scripts/adopt-project.sh" \
      --scan-report "$WORK/scan/scout-report.json" < "$WORK/ans-$tag" ) \
    > "$WORK/$tag.out" 2> "$WORK/$tag.err"
}

# _dispo DIR REL — the archive MANIFEST's disposition for REL.
_dispo() {
  jq -r --arg r "$2" '.entries[] | select(.originalPath == $r) | .disposition' \
    "$1"/.claude/adoption-archive/*/MANIFEST.json 2>/dev/null
}

if ! _adoptee "$WORK/template" || \
   ! bash "$REPO_ROOT/scripts/scout.sh" --root "$WORK/template" --out "$WORK/scan" >/dev/null 2>&1 || \
   [ ! -s "$WORK/scan/scout-report.json" ]; then
  skip "every case" "scripts/scout.sh produced no report; adoption consumes one and cannot be tested without it"
  echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0
fi

# ── P1: organizational, owning documents in every shape the writer must handle
P1="$WORK/owns"
_adoptee "$P1" || fail_ "setup" "could not build the owning adoptee"
printf '# THEIR-CLAUDE-MARKER\n' > "$P1/CLAUDE.md"
printf '# THEIR-BUGS-MARKER\n' > "$P1/BUGS.md"
printf 'SHARED-TARGET-MARKER\n' > "$WORK/shared-features.md"
ln -s "$WORK/shared-features.md" "$P1/FEATURES.md"
printf 'THEIR-READONLY-MARKER\n' > "$P1/RELEASE_NOTES.md"
chmod 444 "$P1/RELEASE_NOTES.md"
printf 'THEIR-HARDLINK-MARKER\n' > "$P1/docs/INDEX.md"
ln "$P1/docs/INDEX.md" "$WORK/other-name-for-index.md"
mkdir -p "$P1/docs/reference"
printf 'THEIR-GUIDE-MARKER\n' > "$P1/docs/reference/user-guide.md"
P1_COMMIT="$( ( cd "$P1" && git add CLAUDE.md BUGS.md FEATURES.md RELEASE_NOTES.md docs/INDEX.md docs/reference/user-guide.md \
    && git commit -q -m "docs: their own documents" ) 2>&1 )" || fail_ "setup" "could not commit P1's documents: $P1_COMMIT"
_adopt "$P1" owns 2; RC1=$?
[ "$RC1" -eq 0 ] || fail_ "setup" "the owning adoption did not complete (rc $RC1): $(tail -3 "$WORK/owns.err")"

# ── P2: personal, owning none of them
P2="$WORK/plain"
_adoptee "$P2" || fail_ "setup" "could not build the plain adoptee"
_adopt "$P2" plain 1; RC2=$?
[ "$RC2" -eq 0 ] || fail_ "setup" "the plain adoption did not complete (rc $RC2): $(tail -3 "$WORK/plain.err")"

# ── P3: `docs` is an ABSOLUTE symlink to a folder outside the project. Left
# untracked: a symlink cannot be staged past this repo's own add guard, and the
# writer reads the working tree, not the index.
P3="$WORK/linkeddocs"
_adoptee "$P3" || fail_ "setup" "could not build the linked-docs adoptee"
mkdir -p "$WORK/shared-docs"
printf 'SHARED-INDEX-ORIGINAL\n' > "$WORK/shared-docs/INDEX.md"
ln -s "$WORK/shared-docs" "$P3/docs.tmp" && rm -rf "$P3/docs" && mv "$P3/docs.tmp" "$P3/docs"
_adopt "$P3" linked 1; RC3=$?

# ═══════════════════════════════════════════════════════════════════════════
d1() {
  local label="D1 CLAUDE.md is written, fully rendered, and committed" bad="" p
  for p in "$P1" "$P2"; do
    [ -s "$p/CLAUDE.md" ] || { bad="$bad [$(basename "$p"): no CLAUDE.md]"; continue; }
    grep -q '__[A-Z_]*__' "$p/CLAUDE.md" && bad="$bad [$(basename "$p"): an unrendered placeholder survives]"
    grep -qF "**Project:** $(basename "$p")" "$p/CLAUDE.md" || bad="$bad [$(basename "$p"): the project name is not rendered in]"
    grep -q 'THEIR-CLAUDE-MARKER' "$p/CLAUDE.md" && bad="$bad [$(basename "$p"): still the operator's file]"
    ( cd "$p" && git diff --quiet HEAD -- CLAUDE.md && git ls-files --error-unmatch CLAUDE.md ) >/dev/null 2>&1 \
      || bad="$bad [$(basename "$p"): CLAUDE.md is not in the adoption commit]"
  done
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

d2() {
  local label="D2 the six templates and the reference guides are written and committed" bad="" rel
  for rel in FEATURES.md BUGS.md RELEASE_NOTES.md docs/INDEX.md docs/IDENTIFIERS.md docs/archive/README.md \
             docs/reference/builders-guide.md docs/reference/messaging-standard.md docs/reference/uat-authoring-guide.md; do
    [ -s "$P2/$rel" ] || { bad="$bad [$rel absent]"; continue; }
    ( cd "$P2" && git ls-files --error-unmatch "$rel" ) >/dev/null 2>&1 || bad="$bad [$rel not committed]"
  done
  cmp -s "$P2/BUGS.md" "$REPO_ROOT/templates/generated/bugs.tmpl" || bad="$bad [BUGS.md is not the framework's template]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

d3() {
  local label="D3 a replaced original is archived as \`replaced\` and NAMED with the archive's location" bad="" rel
  for rel in CLAUDE.md BUGS.md; do
    [ "$(_dispo "$P1" "$rel")" = "replaced" ] || bad="$bad [$rel row reads '$(_dispo "$P1" "$rel")']"
  done
  grep -q 'THEIR-CLAUDE-MARKER' "$P1"/.claude/adoption-archive/*/CLAUDE.md 2>/dev/null || bad="$bad [the archived CLAUDE.md is not theirs]"
  awk '/These replaced documents of yours:/{f=1;next} f&&/^   [^ ]/{exit} f' "$WORK/owns.out" > "$WORK/named"
  for rel in CLAUDE.md BUGS.md docs/INDEX.md; do
    grep -qxF "     $rel" "$WORK/named" || bad="$bad [$rel is not named as replaced]"
  done
  grep -qF "Your originals are in .claude/adoption-archive/" "$WORK/owns.out" || bad="$bad [the archive's location is not given]"
  grep -q 'copy across anything you' "$WORK/owns.out" || bad="$bad [no invitation to retrieve content]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

d4() {
  local label="D4 a SYMLINKED document is left alone, recorded \`kept\`, and named" bad=""
  [ -L "$P1/FEATURES.md" ] || bad="$bad [the link was replaced]"
  [ "$(cat "$WORK/shared-features.md")" = "SHARED-TARGET-MARKER" ] || bad="$bad [the link's target was written through]"
  [ "$(_dispo "$P1" FEATURES.md)" = "kept" ] || bad="$bad [row reads '$(_dispo "$P1" FEATURES.md)']"
  grep -q 'FEATURES.md — a symlink' "$WORK/owns.out" || bad="$bad [not named as left alone]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

d5() {
  local label="D5 a READ-ONLY document is left alone, recorded \`kept\`, and named" bad=""
  [ "$(cat "$P1/RELEASE_NOTES.md")" = "THEIR-READONLY-MARKER" ] || bad="$bad [it was overwritten]"
  [ "$(_dispo "$P1" RELEASE_NOTES.md)" = "kept" ] || bad="$bad [row reads '$(_dispo "$P1" RELEASE_NOTES.md)']"
  grep -q 'RELEASE_NOTES.md — read-only' "$WORK/owns.out" || bad="$bad [not named as left alone]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

d6() {
  local label="D6 a HARDLINKED document is replaced without writing through the shared inode" bad=""
  [ "$(cat "$WORK/other-name-for-index.md")" = "THEIR-HARDLINK-MARKER" ] || bad="$bad [the other name now reads the framework's file]"
  cmp -s "$P1/docs/INDEX.md" "$REPO_ROOT/templates/generated/doc-index.tmpl" || bad="$bad [docs/INDEX.md was not replaced]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

d7() {
  local label="D7 a reference guide the project already has is not overwritten" bad=""
  [ "$(cat "$P1/docs/reference/user-guide.md")" = "THEIR-GUIDE-MARKER" ] || bad="$bad [it was overwritten]"
  [ -s "$P1/docs/reference/builders-guide.md" ] || bad="$bad [the absent guides were not written beside it]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

d8() {
  local label="D8 the stage sits after \`manifest\` and before \`adoption_record\`" order
  order="$( ( set +u; . "$REPO_ROOT/scripts/lib/adopt/adopt-state.sh" >/dev/null 2>&1; _adopt_state_order ) | tr '\n' ' ')"
  case "$order" in
    *"manifest framework_docs ci session_layer assessment_prompt adoption_record"*) pass "$label" ;;   # WP7's `ci` stage sits between them since §7.4 landed
    *) fail_ "$label" "order is: $order" ;;
  esac
}

d9() {
  local label="D9 the project-docs stub is retired, not merely silent" bad=""
  grep -rq '^[[:space:]]*adopt_stub_project_docs[[:space:]]*$' "$REPO_ROOT/scripts" && bad="$bad [it is still called]"
  grep -q 'are NOT written' "$WORK/owns.out" && bad="$bad [its notice is still printed]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

d10() {
  local label="D10 the tier reaches the render: organizational gets the branch-protection section" bad=""
  grep -q 'Branch Protection (Organizational Deployments)' "$P1/CLAUDE.md" || bad="$bad [organizational lacks it]"
  grep -q 'Branch Protection (Organizational Deployments)' "$P2/CLAUDE.md" && bad="$bad [personal carries it]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

d11() {
  local label="D11 a document inside a SYMLINKED FOLDER is left alone, and adoption completes" bad="" n
  [ "$RC3" -eq 0 ] || bad="$bad [adoption refused (rc $RC3): $(tail -2 "$WORK/linked.err" | tr '\n' ' ')]"
  [ "$(cat "$WORK/shared-docs/INDEX.md")" = "SHARED-INDEX-ORIGINAL" ] || bad="$bad [the folder's INDEX.md outside the project was overwritten]"
  n="$(ls -A "$WORK/shared-docs" | tr '\n' ' ')"
  [ "$n" = "INDEX.md " ] || bad="$bad [files were written into the linked folder: $n]"
  [ -L "$P3/docs" ] || bad="$bad [the docs link was replaced]"
  [ "$(_dispo "$P3" docs/INDEX.md)" = "kept" ] || bad="$bad [docs/INDEX.md row reads '$(_dispo "$P3" docs/INDEX.md)']"
  grep -q 'docs/INDEX.md — a symlink, or inside a symlinked folder' "$WORK/linked.out" || bad="$bad [not named as left alone]"
  [ -s "$P3/CLAUDE.md" ] || bad="$bad [CLAUDE.md, outside the link, was not written]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

d12() {
  local label="D12 an intake value carrying a newline falls back instead of reaching sed" got
  # Built by jq, not printf: a raw newline in a hand-written JSON string is
  # INVALID JSON, jq then reads nothing, and the fallback fires for the wrong
  # reason — which is how the first cut of this case passed with the guard
  # deleted.
  jq -n '{platform: "web\nw /tmp/soif-d12\nweb"}' > "$WORK/ip.json"
  [ "$(jq -r .platform "$WORK/ip.json" | wc -l | tr -d ' ')" = "3" ] \
    || { fail_ "$label" "fixture: the value is not three lines"; return; }
  got="$( ( set +u; . "$REPO_ROOT/scripts/lib/adopt/adopt-docs.sh" >/dev/null 2>&1
            _adopt_doc_value "$WORK/ip.json" .platform undecided '^[a-z_]+$' ) )"
  [ "$got" = "undecided" ] && pass "$label" || fail_ "$label" "got [$got]"
}

d1; d2; d3; d4; d5; d6; d7; d8; d9; d10; d11; d12

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
