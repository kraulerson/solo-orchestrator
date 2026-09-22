#!/usr/bin/env bash
# WP11 — THE `document` AND `state` ARCHIVE CLASSES, AND FRAMEWORK-WINS.
#
# THE DEFECT THIS CLOSES, MEASURED ON `main` BEFORE IT WAS WRITTEN.
# `grep -c "PROJECT_INTAKE\|intake-progress" scripts/lib/adopt/adopt-archive.sh`
# was **0**. Act 2 writes three paths an adoptee may already own —
# `PROJECT_INTAKE.md` (adopt-intake.sh), `.claude/intake-progress.json` and
# `.claude/orchestrator-source.json` — through `adopt_write_file`, which
# overwrites. None of the three was in `adopt_archive_inventory`, so a project
# that already tracked them had them REPLACED with:
#
#   * no archive directory,
#   * no MANIFEST row,
#   * no sentence anywhere in the transcript,
#
# while the same run's overview says *"nothing is moved silently"*. That is
# `## BL-292:` and §13-V34, and it is the reason this package outranks the rest
# of §10: it is the only live defect left that destroys an operator's own file.
#
# THE SECOND HALF IS THE OPPOSITE FAILURE. `adopt_install_framework` SKIPPED
# every colliding script (`[ -e "$dst" ]` → `continue`), which preserves the
# operator's bytes but leaves the framework half-installed — a project carrying
# its own `scripts/validate.sh` got everything EXCEPT the framework's version of
# it, silently, and the gates that call it then run the wrong file. D1 rules
# framework-wins: archive theirs, install ours, say so.
#
# I20 IS THE INVARIANT THAT WOULD HAVE CAUGHT BOTH. Every path the rehearsal
# plans to write that EXISTED before it must appear in the inventory. A new
# writer added without a matching archive row trips it at the boundary instead
# of being discovered by a reviewer a month later.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
TMPS=""

pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip_() { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

cleanup() { for d in $TMPS; do rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT
newtmp() { local d=""; d=$(mktemp -d); TMPS="$TMPS $d"; printf '%s\n' "$d"; }

command -v jq  >/dev/null 2>&1 || { echo "  [FAIL] jq is required";  echo "Results: 0 passed, 1 failed, 0 skipped"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "  [FAIL] git is required"; echo "Results: 0 passed, 1 failed, 0 skipped"; exit 1; }

# ── The inventory, driven directly ──────────────────────────────────────────
# `adopt_archive_inventory` emits `<originalPath>\t<class>\t<archivedPath>` and
# reads only the adoptee, so it can be exercised without a full adoption. That
# keeps these cases at a second each; the end-to-end consequences are E1/E2.
INV=""
inventory() {
  local root="$1"
  INV="$( . "$REPO_ROOT/scripts/lib/adopt/adopt-core.sh"    >/dev/null 2>&1
          . "$REPO_ROOT/scripts/lib/adopt/adopt-archive.sh" >/dev/null 2>&1
          ADOPT_FRAMEWORK_ROOT="$REPO_ROOT"
          adopt_archive_inventory "$root" 2>/dev/null )"
}
# row PATH -> "<class>\t<archivedPath>", empty when the path has no row.
row() { printf '%s\n' "$INV" | awk -F'\t' -v p="$1" '$1==p{print $2"\t"$3; exit}'; }

mk_adoptee() {
  local p="$1"
  mkdir -p "$p/.claude" "$p/scripts" || return 1
  local out=""
  out="$( ( cd "$p" && git init -q . \
      && git config user.email wp11@test.invalid \
      && git config user.name  "WP11 Test" \
      && git config core.excludesFile /dev/null ) 2>&1 )" \
    || { printf 'git init failed: %s\n' "$out" >&2; return 1; }
  printf '{"name":"acme"}\n' > "$p/package.json"
  printf '# acme\n'          > "$p/README.md"
  return 0
}
commit_all() {
  local p="$1" out=""
  out="$( ( cd "$p" && git add -A && git commit -qm "their own history" ) 2>&1 )" \
    || { printf 'git commit failed: %s\n' "$out" >&2; return 1; }
}

# mk_report DIR ROOT — a REAL Scout report for the fixture.
#
# A hand-made report is not enough: the driver refuses one with no
# `intakePrefill` section ("cannot invent one"), and inventing the rest of
# Scout's schema here would be a second, drifting copy of it. Scout is
# read-only, so running it on the fixture costs a second and cannot change it.
# The secrets section it produces is irrelevant — WP10b's stop overwrites that
# with its own scan — so these cases do not depend on gitleaks being present.
mk_report() {
  local out="$1" root="$2"
  bash "$REPO_ROOT/scripts/scout.sh" --root "$root" --out "$out" >/dev/null 2>&1 || return 1
  [ -f "$out/scout-report.json" ] || return 1
  return 0
}

echo "== WP11 — the document and state archive classes =="

# ═══════════════════════════════════════════════════════════════════════════
# A1 — THE THREE PATHS ACT 2 OVERWRITES EACH HAVE A ROW (`## BL-292:`)
# ═══════════════════════════════════════════════════════════════════════════
a1() {
  local label="A1 the three paths Act 2 writes over are each inventoried, with the right class"
  local T=""; T=$(newtmp)
  mk_adoptee "$T/p" || { fail_ "$label" "fixture failed"; return; }
  printf '# their intake\n'        > "$T/p/PROJECT_INTAKE.md"
  printf '{"theirs":true}\n'       > "$T/p/.claude/intake-progress.json"
  printf '{"source":"theirs"}\n'   > "$T/p/.claude/orchestrator-source.json"
  commit_all "$T/p" || { fail_ "$label" "commit failed"; return; }

  inventory "$T/p"
  local bad="" want got
  for want in "PROJECT_INTAKE.md|document" \
              ".claude/intake-progress.json|state" \
              ".claude/orchestrator-source.json|state"; do
    got="$(row "${want%%|*}" | cut -f1)"
    [ "$got" = "${want##*|}" ] || bad="$bad [${want%%|*}: class='$got', want '${want##*|}']"
  done
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# A2 — ONLY FILES THAT EXIST PRODUCE ROWS
#      §7.2's inherited property. Without this the new classes would invent
#      rows for files the operator never had, which teaches them the record is
#      fiction — worse than a missing row.
# ═══════════════════════════════════════════════════════════════════════════
a2() {
  local label="A2 a project owning none of those paths gets no rows for them"
  local T=""; T=$(newtmp)
  mk_adoptee "$T/p" || { fail_ "$label" "fixture failed"; return; }
  commit_all "$T/p" || { fail_ "$label" "commit failed"; return; }
  inventory "$T/p"
  local bad="" p
  for p in PROJECT_INTAKE.md .claude/intake-progress.json .claude/orchestrator-source.json \
           CLAUDE.md FEATURES.md PROJECT_BIBLE.md PRODUCT_MANIFESTO.md; do
    [ -z "$(row "$p")" ] || bad="$bad [$p has a row and the file does not exist]"
  done
  # POSITIVE CONTROL: the inventory still WORKS on this fixture — an empty
  # inventory would satisfy every assertion above.
  printf '# theirs\n' > "$T/p/CLAUDE.md"; commit_all "$T/p" >/dev/null 2>&1
  inventory "$T/p"
  [ -n "$(row CLAUDE.md)" ] || bad="$bad [VACUITY FLOOR: CLAUDE.md exists and still has no row]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# A3 — THE DOCUMENT SET IS A UNION, AND IT IS DATA
#      D3's documents are archived so Act 4 can reconstruct them. Act 2
#      archives and REPLACES NONE of them (except the intake, A1's row), so the
#      originals stay at their paths — this case pins membership only.
# ═══════════════════════════════════════════════════════════════════════════
a3() {
  local label="A3 every D3 document the project owns is inventoried under class 'document'"
  local T=""; T=$(newtmp)
  mk_adoptee "$T/p" || { fail_ "$label" "fixture failed"; return; }
  local d
  for d in CLAUDE.md FEATURES.md PROJECT_BIBLE.md PRODUCT_MANIFESTO.md; do
    printf '# theirs: %s\n' "$d" > "$T/p/$d"
  done
  commit_all "$T/p" || { fail_ "$label" "commit failed"; return; }
  inventory "$T/p"
  local bad="" got
  for d in CLAUDE.md FEATURES.md PROJECT_BIBLE.md PRODUCT_MANIFESTO.md; do
    got="$(row "$d" | cut -f1)"
    [ "$got" = "document" ] || bad="$bad [$d: class='$got', want 'document']"
  done
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# A4 — `CHANGELOG.md` IS KEPT BY RULE
#      Row 17 excludes it. Archiving it would be the opposite error to BL-292:
#      taking a copy of something adoption never touches.
# ═══════════════════════════════════════════════════════════════════════════
a4() {
  local label="A4 CHANGELOG.md is kept by rule — no row, not archived"
  local T=""; T=$(newtmp)
  mk_adoptee "$T/p" || { fail_ "$label" "fixture failed"; return; }
  printf '# changes\n' > "$T/p/CHANGELOG.md"
  printf '# theirs\n'  > "$T/p/CLAUDE.md"
  commit_all "$T/p" || { fail_ "$label" "commit failed"; return; }
  inventory "$T/p"
  local bad=""
  [ -z "$(row CHANGELOG.md)" ] || bad="$bad [CHANGELOG.md was inventoried]"
  # The control: a sibling document IS inventoried on the same fixture, so an
  # inventory that returned nothing cannot pass this case.
  [ -n "$(row CLAUDE.md)" ] || bad="$bad [VACUITY FLOOR: CLAUDE.md has no row either]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# A5 — A NAME CARRYING A NEWLINE, CR OR TAB IS REFUSED AT THE INVENTORY
#      The rows are TAB-separated and the MANIFEST is built from them, so such
#      a name splits a row in two. Refusing at the inventory is before any copy.
# ═══════════════════════════════════════════════════════════════════════════
a5() {
  local label="A5 a path carrying a newline or tab is refused at the inventory, before any copy"
  local T=""; T=$(newtmp)
  mk_adoptee "$T/p" || { fail_ "$label" "fixture failed"; return; }
  printf '# theirs\n' > "$T/p/CLAUDE.md"
  # A skill directory is the one inventoried surface whose NAME is arbitrary.
  # `$'\n'`, NOT `$(printf '\n')`. Command substitution strips trailing
  # newlines, so the latter is the EMPTY STRING and this fixture quietly built
  # a directory called `badname` — measured: the case passed nothing and the
  # guard it claimed to test was never reached. The same mistake, in the same
  # session, once in the product and once here.
  local nl weird
  nl=$'\n'
  weird="$T/p/.claude/skills/bad${nl}name"
  mkdir -p "$weird" 2>/dev/null || { skip_ "$label" "this filesystem refuses a newline in a path"; return; }
  printf 'x\n' > "$weird/SKILL.md" 2>/dev/null || { skip_ "$label" "could not create the fixture"; return; }
  commit_all "$T/p" >/dev/null 2>&1

  local rc=0
  ( . "$REPO_ROOT/scripts/lib/adopt/adopt-core.sh"    >/dev/null 2>&1
    . "$REPO_ROOT/scripts/lib/adopt/adopt-archive.sh" >/dev/null 2>&1
    ADOPT_FRAMEWORK_ROOT="$REPO_ROOT"
    adopt_archive_inventory "$T/p" ) >"$T/out" 2>"$T/err" || rc=$?
  if [ "$rc" -ne 0 ] && grep -qi 'newline\|control character\|cannot be recorded' "$T/out" "$T/err" 2>/dev/null; then
    pass "$label"
  else
    fail_ "$label" "rc=$rc and no refusal naming the character (a split row would reach the MANIFEST)"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# E1 — END TO END: THE INTAKE IS ARCHIVED, NOT SILENTLY REPLACED
#      This is `## BL-292:` itself, through the real driver.
# ═══════════════════════════════════════════════════════════════════════════
e1() {
  local label="E1 an adoptee's own PROJECT_INTAKE.md survives in the archive with its bytes"
  local T=""; T=$(newtmp)
  mk_adoptee "$T/p" || { fail_ "$label" "fixture failed"; return; }
  local marker="THEIR-INTAKE-DO-NOT-LOSE"
  printf '# their intake\n%s\n' "$marker" > "$T/p/PROJECT_INTAKE.md"
  printf '{"theirs":true,"marker":"%s"}\n' "$marker" > "$T/p/.claude/intake-progress.json"
  commit_all "$T/p" || { fail_ "$label" "commit failed"; return; }
  local before_sha
  before_sha=$(shasum -a 256 "$T/p/PROJECT_INTAKE.md" | cut -d' ' -f1)

  printf '1\n1\n1\n1\n1\n1\n' > "$T/answers"
  mk_report "$T/scan" "$T/p" || { fail_ "$label" "Scout could not survey the fixture"; return; }
  ( cd "$T/p" && bash "$REPO_ROOT/scripts/adopt-project.sh" --scan-report "$T/scan/scout-report.json" ) \
    < "$T/answers" > "$T/out" 2> "$T/err"

  local bad=""
  # THE ARCHIVE MUST HOLD THEIR BYTES. Not "a file exists" — the marker.
  if ! grep -rq "$marker" "$T/p/.claude/adoption-archive" 2>/dev/null; then
    bad="$bad [their intake is not in the archive]"
  fi
  # AND THE RECORD MUST NAME IT. An archive nobody is told about is the same
  # silence one directory over.
  local mj
  mj="$(find "$T/p/.claude/adoption-archive" -name MANIFEST.json 2>/dev/null | head -1)"
  if [ -z "$mj" ]; then
    bad="$bad [no MANIFEST.json]"
  else
    jq -e '[.entries[] | select(.originalPath == "PROJECT_INTAKE.md")] | length > 0' "$mj" >/dev/null 2>&1 \
      || bad="$bad [no MANIFEST row for PROJECT_INTAKE.md]"
    local rec
    rec="$(jq -r '[.entries[] | select(.originalPath == "PROJECT_INTAKE.md")][0].sha256 // ""' "$mj" 2>/dev/null)"
    [ "$rec" = "$before_sha" ] || bad="$bad [the recorded sha256 is not the original's]"
  fi
  # AND THE TRANSCRIPT MUST SAY SO.
  grep -q 'PROJECT_INTAKE.md' "$T/out" "$T/err" 2>/dev/null \
    || bad="$bad [the run never mentions PROJECT_INTAKE.md]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# E2 — FRAMEWORK-WINS: A COLLIDING SCRIPT IS ARCHIVED AND REPLACED
#      The opposite failure to E1. Skipping preserved their bytes and left the
#      framework half-installed, so the gates call the wrong file.
# ═══════════════════════════════════════════════════════════════════════════
e2() {
  local label="E2 a colliding framework script is archived and REPLACED, not skipped"
  local T=""; T=$(newtmp)
  mk_adoptee "$T/p" || { fail_ "$label" "fixture failed"; return; }
  local marker="THEIR-VALIDATE-SCRIPT"
  printf '#!/usr/bin/env bash\n# %s\n' "$marker" > "$T/p/scripts/validate.sh"
  chmod +x "$T/p/scripts/validate.sh"
  commit_all "$T/p" || { fail_ "$label" "commit failed"; return; }

  printf '1\n1\n1\n1\n1\n1\n' > "$T/answers"
  mk_report "$T/scan" "$T/p" || { fail_ "$label" "Scout could not survey the fixture"; return; }
  ( cd "$T/p" && bash "$REPO_ROOT/scripts/adopt-project.sh" --scan-report "$T/scan/scout-report.json" ) \
    < "$T/answers" > "$T/out" 2> "$T/err"

  local bad=""
  # THE FRAMEWORK'S BYTES ARE AT THE PATH.
  if grep -q "$marker" "$T/p/scripts/validate.sh" 2>/dev/null; then
    bad="$bad [their version is still at the path — the install skipped it]"
  fi
  # THEIRS ARE IN THE ARCHIVE.
  grep -rq "$marker" "$T/p/.claude/adoption-archive" 2>/dev/null \
    || bad="$bad [their version is not in the archive]"
  # AND THE PATH IS NAMED, not counted.
  grep -q 'scripts/validate.sh' "$T/out" "$T/err" 2>/dev/null \
    || bad="$bad [the run never names the path it replaced]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# E3 — I20: A PLANNED WRITE OVER A PRE-EXISTING PATH MUST BE INVENTORIED
#      The invariant, not an instance of it. A future writer added without an
#      archive row trips this at the boundary rather than being found by a
#      reviewer a month later — which is how BL-292 was found.
# ═══════════════════════════════════════════════════════════════════════════
e3() {
  local label="E3 I20 blocks when a planned write lands on a pre-existing path with no archive row"
  local T=""; T=$(newtmp)
  mk_adoptee "$T/p" || { fail_ "$label" "fixture failed"; return; }
  printf '# their intake\n' > "$T/p/PROJECT_INTAKE.md"
  commit_all "$T/p" || { fail_ "$label" "commit failed"; return; }

  printf '1\n1\n1\n1\n1\n1\n' > "$T/answers"
  mk_report "$T/scan" "$T/p" || { fail_ "$label" "Scout could not survey the fixture"; return; }
  # The seam drops a class from the inventory, which is exactly the shape of
  # "somebody added a writer and forgot the row".
  local rc=0
  ( cd "$T/p" && SOIF_ADOPT_INVENTORY_SKIP_CLASS=document \
      bash "$REPO_ROOT/scripts/adopt-project.sh" --scan-report "$T/scan/scout-report.json" ) \
    < "$T/answers" > "$T/out" 2> "$T/err" || rc=$?

  local bad=""
  [ "$rc" -ne 0 ] || bad="$bad [the run completed with an uninventoried overwrite]"
  grep -qi 'PROJECT_INTAKE.md' "$T/out" "$T/err" 2>/dev/null \
    || bad="$bad [the block does not name the path]"
  # THEIR FILE IS STILL THEIRS — the block happens before the write.
  grep -q 'their intake' "$T/p/PROJECT_INTAKE.md" 2>/dev/null \
    || bad="$bad [their file was overwritten before the block]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# E4 — THE RECEIPT CHECK: A ROW IS NOT A COPY
#      I20 catches a path with NO inventory row. This catches the different
#      failure it cannot see — a row that exists while the archived FILE does
#      not, i.e. a partial archive. Without this case the check in front of
#      every overwrite is unfalsifiable code.
# ═══════════════════════════════════════════════════════════════════════════
e4() {
  local label="E4 an overwrite is refused when the archive has a row but no copy on disk"
  local T=""; T=$(newtmp)
  mk_adoptee "$T/p" || { fail_ "$label" "fixture failed"; return; }
  local marker="THEIR-VALIDATE-SCRIPT-E4"
  printf '#!/usr/bin/env bash\n# %s\n' "$marker" > "$T/p/scripts/validate.sh"
  chmod +x "$T/p/scripts/validate.sh"
  commit_all "$T/p" || { fail_ "$label" "commit failed"; return; }
  mk_report "$T/scan" "$T/p" || { fail_ "$label" "Scout could not survey the fixture"; return; }

  printf '1\n1\n1\n1\n1\n1\n' > "$T/answers"
  local rc=0
  ( cd "$T/p" && SOIF_ADOPT_ARCHIVE_SKIP_COPY=scripts/validate.sh \
      bash "$REPO_ROOT/scripts/adopt-project.sh" --scan-report "$T/scan/scout-report.json" ) \
    < "$T/answers" > "$T/out" 2> "$T/err" || rc=$?

  local bad=""
  [ "$rc" -ne 0 ] || bad="$bad [the run completed and overwrote a file with no archived copy]"
  # THEIR BYTES ARE STILL THEIRS. This is the assertion that matters: the
  # refusal must come BEFORE the copy, not after it.
  grep -q "$marker" "$T/p/scripts/validate.sh" 2>/dev/null \
    || bad="$bad [their file was replaced anyway]"
  # THE REFUSAL IS THE REHEARSAL'S, AND THAT IS THE BETTER OUTCOME. Measured:
  # the rehearsal runs the same write phase over a copy, so the receipt check
  # fires THERE and the run stops before touching the real tree at all — the
  # transcript therefore carries the rehearsal's generic sentence rather than
  # the check's own. A first version of this case asserted the check's wording
  # and failed over a refusal that was working correctly and earlier than
  # expected. What is asserted is the property: refused, nothing replaced.
  grep -qi 'rehearsal did not complete\|not in the archive' "$T/out" "$T/err" 2>/dev/null \
    || bad="$bad [no refusal in the transcript]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

a1; a2; a3; a4; a5; e1; e2; e3; e4

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
