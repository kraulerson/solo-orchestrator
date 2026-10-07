#!/usr/bin/env bash
# tests/test-bl322-s2-project-rules.sh — `## BL-322:` S2, dogfood run 3's
# findings 2, 8 and 9: after adoption, the project's own CLAUDE.md rules must
# not silently stop loading.
#
# THE DEFECT. Adoption replaced k-pdf's 146-line CLAUDE.md with the framework's
# (`# BL-242-DOCS-STAGE`). Its `@` imports of PROJECT_BIBLE.md,
# PRODUCT_MANIFESTO.md, CONTRIBUTING.md and the intake, all still in the tree
# and untouched, vanished with it, so the next session lost the colour-alone
# HARD CONSTRAINT, the architecture rules and the never-do list (the Bible holds
# all three) until the assessment folded them back in. Nothing warned. Scout had
# said CLAUDE.md "yours stays"; the archive summary said files were "moved" that
# were only copied.
#
# THE FIX (Karl, 2026-10-07). Adoption carries the original's relative `@`
# imports of regular in-repo files it did not write into a marked "Carried over
# from your CLAUDE.md" section of the new CLAUDE.md, names every import it did
# not carry with the reason (`~/` and absolute imports are named only, never
# carried), and warns that the rules written inside the old file load again only
# once the assessment folds them in. The archive's disclosure and MANIFEST.md say
# per file whether it was replaced, composed or only copied, with no restore line
# for a file adoption did not change; a framework script adoption replaced is
# recorded `replaced`, not `kept`. Scout's rows for the documents adoption
# replaces say so.
#
# CASES
#   U1  the import parser, against what Claude Code imports (checked with a
#       replica of its extractor): code (fenced, nested, indented, in a quote,
#       after a setext heading), code spans of any width, HTML comments (on one
#       line, across lines, the short forms), HTML blocks (a tag to the blank
#       line; script/PI/declaration/CDATA to their end), a reference definition,
#       a word@word, a quoted path and a duplicate are not imports; an escaped
#       space, a paragraph's tab-led line, a no-break space, emphasis and link
#       text, a `#…` cut and a trailing backslash are; and a CRLF file reads
#       like an LF one (review round 1: R-S2-2, R-S2-3, R-S2-4 B, R-S2-5)
#   U2  the carry decision: each kind of import carried (normalised, once) or
#       named with its reason, including `./` spellings, another case of a
#       replaced file's name, a composed file and a control character (review
#       round 1: R-S2-4 A, D, E, R-S2-8, R-S2-9, R-S2-10)
#   U2b an archive record that cannot be read fails closed (R-S2-10 a)
#   U3  the archive disclosure says replaced / composed / only copied, and gives
#       no restore line for a file adoption did not change
#   U4  MANIFEST.md says the same, and has no `cp` for a kept row
#   U5  "Next: the assessment" says the old file's rules do not load yet — only
#       when CLAUDE.md was replaced
#   U6  the assessment prompt's step 8 names the carried section; its reading
#       list no longer says adoption replaced every archived document
#   U7  every reason a run gives for not carrying an import (R-S2-4 C)
#   S1  Scout's rows for the documents adoption replaces say "kept a copy, then
#       replaced", and are exactly adoption's set; CHANGELOG.md stays theirs
#   A1  a real adoption: the carried section holds exactly the two imports that
#       qualify, the inline rule text is not carried, the imported files are
#       untouched, TL;DR's section is intact, and the run names the carried and
#       not-carried imports, the archived original and the warning
#   A2  the same run's archive: the Bible "only copied" with no restore line,
#       CLAUDE.md replaced with one, and a framework script it replaced recorded
#       `replaced` (it was `kept`)
#   A3  the same run's assessment prompt names the carried section
#   A4  no CLAUDE.md: no section, no warning
#   A5  a CLAUDE.md with no imports: no section; the warning says nothing was
#       carried
#   A6  a symlinked CLAUDE.md is left alone: no section, no warning
#   M   mutants: each rewrites ONE marked line (or deletes one exact line) in a
#       mirror, checks the edit landed and still parses, and needs a named case
#       to go RED
#
# Hermetic: temp dirs only, no network, no Guardrails clone (adoption runs with
# a seam that points at an empty folder), no MCP step. bash 3.2 safe.
set -uo pipefail
unset GITHUB_BASE_REF 2>/dev/null || true
export SOIF_ADOPT_MCP=off   # BL-311-MCP-SEAM

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

for t in jq git; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bl322s2.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT INT TERM
newtmp() { mktemp -d "$WORK/tXXXXXX"; }
CASE_DETAIL=""
TAB="$(printf '\t')"
BEGIN_MARK='<!-- SOIF-CARRIED-IMPORTS-BEGIN (BL-322) -->'
END_MARK='<!-- SOIF-CARRIED-IMPORTS-END -->'
WARN_LINE='YOUR OWN CLAUDE.md IS NO LONGER WHAT CLAUDE CODE LOADS.'
gitq() { git -C "$1" "${@:2}" >/dev/null 2>&1; }

# in_lib FW SCRIPT — run SCRIPT (a string) in a subshell that has sourced the
# adoption core and the module under test from FW.
in_lib() {
  ( set +u
    . "$1/scripts/lib/adopt/adopt-core.sh" || exit 90
    . "$1/scripts/lib/adopt/adopt-docs.sh" || exit 91
    . "$1/scripts/lib/adopt/adopt-archive.sh" || exit 92
    . "$1/scripts/lib/adopt/adopt-act4.sh" || exit 93
    eval "$2" )
}

# ── U: units ─────────────────────────────────────────────────────────────────
# U1's fixture and its expected list were checked against a replica of Claude
# Code 2.1.292's own import extractor (review round 1's oracle, a Markdown lexer
# plus its regex): every name below is what Claude Code imports from this file,
# and every IN_/STILL_ name is one it does not.
case_U1() {   # the import parser
  local d want got
  d="$(newtmp)"
  { printf '# Project rules\n\n'
    printf '@ALPHA.md\n\n'
    printf -- '- see @docs/beta.md and @Design\\ Docs/gamma.md too\n\n'
    printf 'Contact: karl@example.com\n'
    printf 'Inline `see @IN_SPAN.md` stays literal, and so does `` a ` @IN_DBL.md ``.\n'
    printf '\t@TABBED.md\n'
    printf 'x\302\240@NBSP.md y\n'
    printf '*@EMPH.md* and [@LINKED.md](https://x.invalid) and @FRAG.md#section and @TRAIL\\\n'
    printf '@"Quoted File.md" and @~foo and @ALPHA.md\n'
    printf '\n```text\n@IN_FENCE.md\n```\n'
    printf '~~~\n@IN_TILDE.md\n~~~\n'
    printf '  ```\n  @IN_INDENTED_FENCE.md\n  ```\n'
    printf '````md\n```\n@IN_NESTED.md\n```\n````\n'
    printf '\n    @IN_INDENTED_CODE.md\n'
    printf '\n>     @IN_QUOTE_CODE.md\n'
    printf '\nTitle\n=====\n    @IN_SETEXT_CODE.md\n'
    printf '\n[r]: @IN_REFDEF.md\n'
    printf '\n<!-- @IN_COMMENT.md (retired) -->\n'
    printf '<!--\n@IN_MULTI_COMMENT.md\n-->\n'
    printf '<!--> @AFTER_SHORT.md\n'
    printf '<!---> @AFTER_SHORT2.md\n'
    printf '<!-- c --> *@RAW_EMPH.md*\n'
    printf '\n<details>\n@IN_DETAILS.md\n</details>\n'
    printf '\n<script>\n@IN_SCRIPT.md\n\n@STILL_SCRIPT.md\n</script>\n'
    printf '\n<?php @IN_PI.md\n\n@STILL_PI.md ?>\n'
    printf '\n<!DOCTYPE @IN_DECL.md\n\n@STILL_DECL.md>\n'
    printf '\n<![CDATA[ @IN_CDATA.md\n\n@STILL_CDATA.md ]]>\n'
    printf '\n@OMEGA.md\n'
  } > "$d/CLAUDE.md"
  want="$(printf '%s\n' ALPHA.md docs/beta.md 'Design\ Docs/gamma.md' TABBED.md NBSP.md EMPH.md LINKED.md FRAG.md TRAIL \
          AFTER_SHORT.md AFTER_SHORT2.md OMEGA.md)"
  got="$(in_lib "$1" '_adopt_claude_md_import_tokens "'"$d"'/CLAUDE.md"' 2>&1)"
  [ "$got" = "$want" ] || { CASE_DETAIL="got [$(printf '%s' "$got" | tr '\n' '|')] want [$(printf '%s' "$want" | tr '\n' '|')]"; return 1; }
  # A CRLF file (review round 1, R-S2-3): before, it carried nothing, and with a
  # commented-out import above them the result inverted.
  printf '# R\r\n\r\n<!-- @COMMENTED.md -->\r\n@LIVE.md\r\n@SECOND.md\r\n' > "$d/crlf.md"
  got="$(in_lib "$1" '_adopt_claude_md_import_tokens "'"$d"'/crlf.md"' 2>&1)"
  [ "$got" = "$(printf 'LIVE.md\nSECOND.md')" ] || { CASE_DETAIL="CRLF: got [$(printf '%s' "$got" | od -c | tr -s ' \n' ' ' | cut -c1-120)]"; return 1; }
}

# u2_root T — the carry decision's fixture project in T/root, its archive record,
# and a write ledger padded past a pipe's buffer.
u2_root() {
  local t="$1" r="$1/root" i=0
  mkdir -p "$r/docs" "$r/Design Docs" "$r/ARC" || return 1
  for f in PROJECT_BIBLE.md docs/arch.md "Design Docs/rules.md" FEATURES.md COMPOSED.md KEPT.md WRITTEN.md NORM.md; do printf 'x\n' > "$r/$f"; done
  printf 'outside\n' > "$t/outside.md"
  ln -s PROJECT_BIBLE.md "$r/link.md" && ln -s docs "$r/linkdir" || return 1
  { printf 'WRITTEN.md\n'; while [ "$i" -lt 5000 ]; do printf 'scripts/pad-%05d.sh\n' "$i"; i=$((i + 1)); done; } > "$t/ledger"
}

case_U2() {   # the carry decision
  local t r want got
  t="$(newtmp)"; r="$t/root"
  u2_root "$t" || { CASE_DETAIL="fixture"; return 1; }
  jq -n '{entries: [{originalPath: "FEATURES.md", disposition: "replaced"}, {originalPath: "COMPOSED.md", disposition: "composed"},
                    {originalPath: "KEPT.md", disposition: "kept"}, {originalPath: "CLAUDE.md", disposition: "replaced"}]}' > "$r/ARC/MANIFEST.json"
  { printf '@PROJECT_BIBLE.md\n@docs/arch.md\n@Design\\ Docs/rules.md\n@KEPT.md\n@./NORM.md\n@./KEPT.md\n'
    printf '@~/home.md\n@%s/PROJECT_BIBLE.md\n@../outside.md\n@link.md\n@linkdir/arch.md\n' "$r"
    printf '@GONE.md\n@docs\n@FEATURES.md\n@./FEATURES.md\n@features.md\n@claude.md\n@COMPOSED.md\n@WRITTEN.md\n@./WRITTEN.md\n'
    printf '@CTRL\033.md\n'
  } > "$r/CLAUDE.md"
  # Another name for a file adoption replaces: the same file on a case-insensitive
  # file system (this Mac), a hard link on a case-sensitive one (the runner).
  [ -e "$r/features.md" ] || ln "$r/FEATURES.md" "$r/features.md" || { CASE_DETAIL="fixture: features.md"; return 1; }
  [ -e "$r/claude.md" ] || ln "$r/CLAUDE.md" "$r/claude.md" || { CASE_DETAIL="fixture: claude.md"; return 1; }
  want="$(printf 'carry\t%s\n' PROJECT_BIBLE.md docs/arch.md 'Design\ Docs/rules.md' KEPT.md NORM.md
          printf 'skip\t%s\thome\n' '~/home.md' "$r/PROJECT_BIBLE.md"
          printf 'skip\t../outside.md\toutside\nskip\tlink.md\tlink\nskip\tlinkdir/arch.md\tlink\n'
          printf 'skip\tGONE.md\tmissing\nskip\tdocs\tnot-a-file\n'
          printf 'skip\t%s\tarchived\n' FEATURES.md ./FEATURES.md features.md claude.md COMPOSED.md
          printf 'skip\t%s\twritten\n' WRITTEN.md ./WRITTEN.md
          printf 'skip\tCTRL?.md\tcontrol\n')"
  got="$(in_lib "$1" 'ADOPT_WRITTEN_LEDGER="'"$t"'/ledger"; ADOPT_ARCHIVE_DIR=ARC; _adopt_claude_md_carry "'"$r"'" "'"$r"'/CLAUDE.md"' 2>&1)"
  [ "$got" = "$want" ] || { CASE_DETAIL="got [$(printf '%s' "$got" | tr '\n\t' '|:')] want [$(printf '%s' "$want" | tr '\n\t' '|:')]"; return 1; }
}

case_U2b() {   # an archive record that cannot be read fails closed
  local t r want got
  t="$(newtmp)"; r="$t/root"
  u2_root "$t" || { CASE_DETAIL="fixture"; return 1; }
  printf '{"entries": [ not json\n' > "$r/ARC/MANIFEST.json"
  printf '@PROJECT_BIBLE.md\n@GONE.md\n' > "$r/CLAUDE.md"
  want="$(printf 'skip\tPROJECT_BIBLE.md\tunchecked\nskip\tGONE.md\tmissing\n')"
  got="$(in_lib "$1" 'ADOPT_WRITTEN_LEDGER="'"$t"'/ledger"; ADOPT_ARCHIVE_DIR=ARC; _adopt_claude_md_carry "'"$r"'" "'"$r"'/CLAUDE.md"' 2>&1)"
  [ "$got" = "$want" ] || { CASE_DETAIL="got [$(printf '%s' "$got" | tr '\n\t' '|:')] want [$(printf '%s' "$want" | tr '\n\t' '|:')]"; return 1; }
}

case_U7() {   # every reason, as a person reads it
  local code want got bad=""
  while IFS='|' read -r code want; do
    got="$(in_lib "$1" '_adopt_carry_reason '"$code" 2>&1)"
    [ "$got" = "$want" ] || bad="$bad [$code: $got]"
  done <<REASONS
control|its name carries a control character (shown as ?), so it was not read as a path
home|in your home folder, or an absolute path: named only, never carried — it may not exist on another machine
outside|outside this project
link|a symlink, or inside a symlinked folder
missing|no such file in this project
not-a-file|not a file
unchecked|the archive's record could not be read, so whether adoption replaces it is unknown
archived|adoption replaced or changed that file, so it no longer holds what you imported; yours is in the archive
written|adoption wrote that file; it is not one of yours
REASONS
  [ -z "$bad" ] || { CASE_DETAIL="$bad"; return 1; }
}

# mk_archive_mj FILE — a MANIFEST.json with one row of each disposition.
mk_archive_mj() {
  jq -n '{archiveDir: "ARC", secretsScan: {status: "scanned", findingCount: 0, note: "n"}, advisory: "a",
          entries: [
            {originalPath: "CLAUDE.md", archivedPath: "CLAUDE.md", disposition: "replaced", stagedForCommit: true, withheldReason: "", description: "", restore: "cp ARC/CLAUDE.md CLAUDE.md"},
            {originalPath: ".claude/settings.json", archivedPath: ".claude/settings.json", disposition: "composed", stagedForCommit: true, withheldReason: "", description: "", restore: "cp ARC/.claude/settings.json .claude/settings.json"},
            {originalPath: "PROJECT_BIBLE.md", archivedPath: "PROJECT_BIBLE.md", disposition: "kept", stagedForCommit: true, withheldReason: "", description: "", restore: "cp ARC/PROJECT_BIBLE.md PROJECT_BIBLE.md"}]}' > "$1"
}
# row_block OUT PATH — the disclosure's lines for one file.
row_block() { awk -v p="   yours: $2" '$0 == p {f=1; print; next} f && /^   yours: / {exit} f && /^$/ {exit} f {print}' "$1"; }

case_U3() {   # the disclosure, per disposition
  local d out b
  d="$(newtmp)"; mk_archive_mj "$d/MANIFEST.json"; out="$d/out"
  in_lib "$1" '_adopt_archive_disclose "'"$d"'" ARC "'"$d"'/MANIFEST.json"' > "$out" 2>&1
  grep -qF 'moved to ensure the framework operates properly' "$out" || { CASE_DETAIL="the design sentence is gone"; return 1; }
  b="$(row_block "$out" PROJECT_BIBLE.md)"
  grep -qF 'only copied: yours is still in place, unchanged' <<< "$b" || { CASE_DETAIL="the kept row does not say it was only copied: [$(tr '\n' '|' <<< "$b")]"; return 1; }
  grep -qF 'put it back' <<< "$b" && { CASE_DETAIL="the kept row has a restore line: [$(tr '\n' '|' <<< "$b")]"; return 1; }
  b="$(row_block "$out" CLAUDE.md)"
  grep -qF "replaced: the framework's version is in its place" <<< "$b" || { CASE_DETAIL="the replaced row does not say so: [$(tr '\n' '|' <<< "$b")]"; return 1; }
  grep -qF 'put it back: cp ARC/CLAUDE.md CLAUDE.md' <<< "$b" || { CASE_DETAIL="the replaced row lost its restore line"; return 1; }
  b="$(row_block "$out" .claude/settings.json)"
  grep -qF "composed: yours is in place, with the framework's additions beside it" <<< "$b" || { CASE_DETAIL="the composed row does not say so: [$(tr '\n' '|' <<< "$b")]"; return 1; }
  grep -qF 'put it back: cp' <<< "$b" || { CASE_DETAIL="the composed row lost its restore line"; return 1; }
}

case_U4() {   # MANIFEST.md, per disposition
  local d md row
  d="$(newtmp)"; mk_archive_mj "$d/MANIFEST.json"; md="$d/MANIFEST.md"
  in_lib "$1" '_adopt_archive_manifest_md "'"$d"'/MANIFEST.json"' > "$md" 2>&1
  row="$(grep -F '| `PROJECT_BIBLE.md` |' "$md")"
  [ -n "$row" ] || { CASE_DETAIL="no row for the kept file"; return 1; }
  grep -qF 'cp ' <<< "$row" && { CASE_DETAIL="the kept row has a cp: $row"; return 1; }
  grep -qF 'Nothing to put back: yours was not changed.' <<< "$row" || { CASE_DETAIL="the kept row does not say why there is no restore: $row"; return 1; }
  grep -qF 'only copied' <<< "$row" || { CASE_DETAIL="the kept row does not say it was only copied: $row"; return 1; }
  row="$(grep -F '| `CLAUDE.md` |' "$md")"
  grep -qF '`cp ARC/CLAUDE.md CLAUDE.md`' <<< "$row" || { CASE_DETAIL="the replaced row lost its cp: $row"; return 1; }
  grep -qF 'replaced' <<< "$row" || { CASE_DETAIL="the replaced row does not say replaced: $row"; return 1; }
}

case_U5() {   # "Next: the assessment"
  local on off
  on="$(in_lib "$1" 'ADOPT_CLAUDE_MD_REPLACED=1; adopt_act3_next' 2>&1)"
  off="$(in_lib "$1" 'ADOPT_CLAUDE_MD_REPLACED=0; adopt_act3_next' 2>&1)"
  grep -qF 'the rules written in your old CLAUDE.md do not load' <<< "$on" || { CASE_DETAIL="no line when CLAUDE.md was replaced: [$(tr '\n' '|' <<< "$on")]"; return 1; }
  grep -qF 'CLAUDE.md' <<< "$off" && { CASE_DETAIL="the line appears when CLAUDE.md was not replaced"; return 1; }
  return 0
}

case_U6() {   # the assessment prompt
  local r p
  r="$(newtmp)"; mkdir -p "$r/.claude"
  jq -n '{adoption: {adoptedAtCommit: "0123456789abcdef0123456789abcdef01234567"}}' > "$r/.claude/manifest.json"
  in_lib "$1" 'adopt_write_assessment_prompt "'"$r"'"' >/dev/null 2>&1
  p="$r/.claude/adoption/assessment-prompt.md"
  [ -s "$p" ] || { CASE_DETAIL="no prompt written"; return 1; }
  grep -qF 'If CLAUDE.md has a section "Carried over from your CLAUDE.md"' "$p" || { CASE_DETAIL="step 8 does not name the carried section"; return 1; }
  grep -qF 'Adoption replaced them and merged nothing' "$p" && { CASE_DETAIL="the reading list still says every archived document was replaced"; return 1; }
  return 0
}

# ── S: Scout ─────────────────────────────────────────────────────────────────
case_S1() {
  local p out j want got md row
  p="$(newtmp)/p"; out="$(dirname "$p")/scan"
  mkdir -p "$p/docs/archive" && gitq "$p" init -q . && gitq "$p" config user.email s@t.invalid && gitq "$p" config user.name S || { CASE_DETAIL="fixture"; return 1; }
  for f in CLAUDE.md PROJECT_INTAKE.md FEATURES.md BUGS.md RELEASE_NOTES.md CHANGELOG.md docs/INDEX.md docs/IDENTIFIERS.md docs/archive/README.md; do printf '# theirs\n' > "$p/$f"; done
  gitq "$p" add -A && gitq "$p" commit -q --no-verify -m "chore: theirs" || { CASE_DETAIL="fixture commit"; return 1; }
  bash "$1/scripts/scout.sh" --root "$p" --out "$out" </dev/null >/dev/null 2>&1
  j="$out/scout-report.json"; md="$out/scout-report.md"
  [ -s "$j" ] || { CASE_DETAIL="Scout wrote no report"; return 1; }
  want="$( { printf 'CLAUDE.md\nPROJECT_INTAKE.md\n'; in_lib "$1" '_adopt_doc_copies' | cut -f2; } | LC_ALL=C sort)"
  got="$(jq -r '.collisions.entries[] | select(.bucket == "archive-and-replace" and (.class == "framework-doc" or .class == "project-doc")) | .path' "$j" | LC_ALL=C sort)"
  [ "$got" = "$want" ] || { CASE_DETAIL="replaced-document rows [$(tr '\n' ' ' <<< "$got")] want adoption's set [$(tr '\n' ' ' <<< "$want")]"; return 1; }
  [ "$(jq -r '.collisions.entries[] | select(.path == "CHANGELOG.md") | .bucket' "$j")" = "keep-theirs" ] || { CASE_DETAIL="CHANGELOG.md is no longer keep-theirs"; return 1; }
  jq -r '.collisions.entries[] | select(.path == "CLAUDE.md") | .note' "$j" | grep -qF 'imports of files still in the project are carried' \
    || { CASE_DETAIL="the CLAUDE.md row does not say its imports are carried"; return 1; }
  row="$(grep -F '| `CLAUDE.md` |' "$md")"
  grep -qF 'kept a copy, then replaced' <<< "$row" || { CASE_DETAIL="the report's CLAUDE.md row: $row"; return 1; }
  grep -qF 'yours stays' <<< "$row" && { CASE_DETAIL="the report still says yours stays: $row"; return 1; }
  return 0
}

# ── A: real adoptions ────────────────────────────────────────────────────────
# A small node project (the answers of tests/test-bl253-adoption-state-parity.sh:
# the tier, the track, four confirmations), then TL;DR on. The scanner probe is
# pinned to `sh` and the Guardrails seam to an empty folder.
mk_base() {
  local p="$1"
  mkdir -p "$p/src" "$p/docs" || return 1
  gitq "$p" init -q . && gitq "$p" config user.email bl322@test.invalid && gitq "$p" config user.name "BL322 Test" \
    && gitq "$p" config core.excludesFile /dev/null || return 1
  printf '{"name":"acme-api","scripts":{"test":"npm test"}}\n' > "$p/package.json"
  printf '# acme-api\n' > "$p/README.md"
  printf 'node_modules/\n*.log\n' > "$p/.gitignore"
}
commit_base() { gitq "$1" add -A && gitq "$1" commit -q --no-verify -m "chore: their own history"; }
RUN_RC=0; RUN_OUT=""
run_adopt() {   # FW DIR
  local scan
  RUN_RC=0; RUN_OUT="$(dirname "$2")/adopt.out"; scan="$(dirname "$2")/scan"
  bash "$REPO_ROOT/scripts/scout.sh" --root "$2" --out "$scan" </dev/null >/dev/null 2>&1
  [ -s "$scan/scout-report.json" ] || { RUN_RC=99; echo "Scout produced no report" > "$RUN_OUT"; return 0; }
  ( cd "$2" && printf '1\nstandard\n1\n1\n1\n1\n2\n' | env SOIF_ADOPT_SCANNER_BIN=sh SOIF_ADOPT_QDRANT=no \
      SOIF_ADOPT_GUARDRAILS_DIR="$WORK/no-guardrails" bash "$1/scripts/adopt-project.sh" --scan-report "$scan/scout-report.json" ) \
    > "$RUN_OUT" 2>&1 || RUN_RC=$?
}
adopt_ok() { [ "$RUN_RC" -eq 0 ] || { CASE_DETAIL="adoption rc $RUN_RC: $(grep -E 'BLOCKED|REFUSED|FAIL' "$RUN_OUT" | head -1)"; return 1; }; }
# section FILE — the carried section's lines, markers included.
section() { awk -v b="$BEGIN_MARK" -v e="$END_MARK" '$0 == b {f=1} f {print} $0 == e {f=0}' "$1"; }
arc_of() { find "$1/.claude/adoption-archive" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1; }

# The rich adoptee, adopted once per framework root.
RICH_FW=""; RICH_P=""; RICH_RC=0; RICH_OUT=""
rich() {
  local p
  [ "$RICH_FW" = "$1" ] && { RUN_RC="$RICH_RC"; RUN_OUT="$RICH_OUT"; return 0; }
  p="$(newtmp)/p"; mk_base "$p" || return 1
  { printf '# Acme rules\n\nHARD CONSTRAINT: never rely on colour alone.\n\n'
    printf '@PROJECT_BIBLE.md\n@CONTRIBUTING.md\n@FEATURES.md\n@GONE.md\n@~/acme-notes.md\n'; } > "$p/CLAUDE.md"
  printf '# Bible\n\nViews never call services.\n' > "$p/PROJECT_BIBLE.md"
  printf '# Contributing\n\nTests first.\n' > "$p/CONTRIBUTING.md"
  printf '# Our features\n' > "$p/FEATURES.md"
  mkdir -p "$p/scripts" "$p/.claude"
  printf '#!/usr/bin/env bash\n# theirs\n' > "$p/scripts/validate.sh"; chmod +x "$p/scripts/validate.sh"
  printf '{"permissions":{"allow":["Bash(ls:*)"]}}\n' > "$p/.claude/settings.json"
  commit_base "$p" || return 1
  mkdir -p "$(dirname "$p")/orig" && cp "$p/PROJECT_BIBLE.md" "$p/CONTRIBUTING.md" "$(dirname "$p")/orig/"
  run_adopt "$1" "$p"
  RICH_FW="$1"; RICH_P="$p"; RICH_RC="$RUN_RC"; RICH_OUT="$RUN_OUT"
}

case_A1() {   # the carried section, the warning, the names
  local p s o arc
  rich "$1" || { CASE_DETAIL="fixture"; return 1; }
  adopt_ok || return 1
  p="$RICH_P"; o="$RICH_OUT"
  grep -qF 'TL;DR mode: on' "$o" || { CASE_DETAIL="the answers did not reach the TL;DR question (fixture drift)"; return 1; }
  [ "$(grep -cxF "$BEGIN_MARK" "$p/CLAUDE.md")" = 1 ] && [ "$(grep -cxF "$END_MARK" "$p/CLAUDE.md")" = 1 ] \
    || { CASE_DETAIL="the carried section's markers are not there exactly once"; return 1; }
  s="$(section "$p/CLAUDE.md")"
  [ "$(grep '^@' <<< "$s")" = "$(printf '@PROJECT_BIBLE.md\n@CONTRIBUTING.md')" ] \
    || { CASE_DETAIL="the section's imports: [$(grep '^@' <<< "$s" | tr '\n' '|')]"; return 1; }
  grep -qE '^@(FEATURES|GONE)\.md|^@~' "$p/CLAUDE.md" && { CASE_DETAIL="an import that does not qualify was carried"; return 1; }
  grep -qF 'HARD CONSTRAINT' "$p/CLAUDE.md" && { CASE_DETAIL="the inline rule text was copied into the new CLAUDE.md"; return 1; }
  [ "$(grep -c '^- \*\*Project:\*\*' "$p/CLAUDE.md")" = 1 ] || { CASE_DETAIL="the framework's identity line is not there once"; return 1; }
  [ "$(grep -cxF '<!-- tldr-mode:begin -->' "$p/CLAUDE.md")" = 1 ] && [ "$(grep -cxF '<!-- tldr-mode:end -->' "$p/CLAUDE.md")" = 1 ] \
    || { CASE_DETAIL="the TL;DR section's markers are not there exactly once"; return 1; }
  [ "$(awk -v b="$END_MARK" '$0 == b {e=NR} $0 == "<!-- tldr-mode:begin -->" {t=NR} END {print (e && t && e < t) ? "ok" : "no"}' "$p/CLAUDE.md")" = ok ] \
    || { CASE_DETAIL="the TL;DR section is not after the carried one"; return 1; }
  cmp -s "$p/PROJECT_BIBLE.md" "$(dirname "$p")/orig/PROJECT_BIBLE.md" && cmp -s "$p/CONTRIBUTING.md" "$(dirname "$p")/orig/CONTRIBUTING.md" \
    || { CASE_DETAIL="an imported file was changed"; return 1; }
  git -C "$p" diff --quiet HEAD -- CLAUDE.md || { CASE_DETAIL="the committed CLAUDE.md differs from the file"; return 1; }
  arc="$(arc_of "$p")"; arc="${arc#"$p"/}"
  grep -qF "$WARN_LINE" "$o" || { CASE_DETAIL="the run does not warn that the old CLAUDE.md is no longer loaded"; return 1; }
  grep -qF "Apart from your CLAUDE.md's imports (below), nothing in them was merged into" "$o" \
    && ! grep -qF 'Nothing in them was merged into the new files' "$o" \
    || { CASE_DETAIL="the run still says nothing was merged, beside imports it carried"; return 1; }
  grep -qF "$arc/CLAUDE.md" "$o" || { CASE_DETAIL="the run does not name the archived original ($arc/CLAUDE.md)"; return 1; }
  grep -qxF '     @PROJECT_BIBLE.md' "$o" && grep -qxF '     @CONTRIBUTING.md' "$o" || { CASE_DETAIL="the run does not list the carried imports"; return 1; }
  grep -qF '@FEATURES.md — adoption replaced or changed that file' "$o" || { CASE_DETAIL="@FEATURES.md is not named with its reason"; return 1; }
  grep -qF '@GONE.md — no such file in this project' "$o" || { CASE_DETAIL="@GONE.md is not named with its reason"; return 1; }
  grep -qF '@~/acme-notes.md — in your home folder, or an absolute path: named only, never carried' "$o" \
    || { CASE_DETAIL="@~/acme-notes.md is not named with its reason"; return 1; }
  awk '/^══ Next: the assessment/{f=1} f' "$o" | grep -qF 'the rules written in your old CLAUDE.md do not load' \
    || { CASE_DETAIL="'Next: the assessment' does not say the old rules do not load yet"; return 1; }
}

case_A2() {   # the same run's archive, per disposition
  local p o arc b
  rich "$1" || { CASE_DETAIL="fixture"; return 1; }
  adopt_ok || return 1
  p="$RICH_P"; o="$RICH_OUT"; arc="$(arc_of "$p")"
  [ "$(jq -r '.entries[] | select(.originalPath == "scripts/validate.sh") | .disposition' "$arc/MANIFEST.json")" = replaced ] \
    || { CASE_DETAIL="the framework script adoption replaced is not recorded replaced"; return 1; }
  grep -q '# theirs' "$p/scripts/validate.sh" && { CASE_DETAIL="precondition: scripts/validate.sh was not replaced"; return 1; }
  b="$(row_block "$o" PROJECT_BIBLE.md)"
  grep -qF 'only copied: yours is still in place, unchanged' <<< "$b" || { CASE_DETAIL="the Bible's row: [$(tr '\n' '|' <<< "$b")]"; return 1; }
  grep -qF 'put it back' <<< "$b" && { CASE_DETAIL="the Bible's row has a restore line"; return 1; }
  b="$(row_block "$o" scripts/validate.sh)"
  grep -qF "replaced: the framework's version is in its place" <<< "$b" || { CASE_DETAIL="the script's row: [$(tr '\n' '|' <<< "$b")]"; return 1; }
  b="$(row_block "$o" CLAUDE.md)"
  grep -qF 'put it back: cp' <<< "$b" || { CASE_DETAIL="CLAUDE.md's row lost its restore line"; return 1; }
  grep -F '| `PROJECT_BIBLE.md` |' "$arc/MANIFEST.md" | grep -qF 'cp ' && { CASE_DETAIL="MANIFEST.md gives the Bible a cp"; return 1; }
  return 0
}

case_A3() {   # the same run's assessment prompt
  rich "$1" || { CASE_DETAIL="fixture"; return 1; }
  adopt_ok || return 1
  grep -qF 'Carried over from your CLAUDE.md' "$RICH_P/.claude/adoption/assessment-prompt.md" \
    || { CASE_DETAIL="the prompt does not name the carried section"; return 1; }
}

case_A4() {   # no CLAUDE.md
  local p
  p="$(newtmp)/p"; mk_base "$p" && commit_base "$p" || { CASE_DETAIL="fixture"; return 1; }
  run_adopt "$1" "$p"; adopt_ok || return 1
  [ -f "$p/CLAUDE.md" ] || { CASE_DETAIL="no CLAUDE.md was written"; return 1; }
  grep -qF "$BEGIN_MARK" "$p/CLAUDE.md" && { CASE_DETAIL="a carried section with nothing to carry"; return 1; }
  grep -qF "$WARN_LINE" "$RUN_OUT" && { CASE_DETAIL="the warning, with no CLAUDE.md replaced"; return 1; }
  grep -qF 'old CLAUDE.md' "$RUN_OUT" && { CASE_DETAIL="the Next line, with no CLAUDE.md replaced"; return 1; }
  return 0
}

case_A5() {   # a CLAUDE.md with no imports
  local p
  p="$(newtmp)/p"; mk_base "$p" || { CASE_DETAIL="fixture"; return 1; }
  printf '# Acme\n\nNever log passwords.\n' > "$p/CLAUDE.md"
  commit_base "$p" || { CASE_DETAIL="fixture"; return 1; }
  run_adopt "$1" "$p"; adopt_ok || return 1
  grep -qF "$BEGIN_MARK" "$p/CLAUDE.md" && { CASE_DETAIL="a carried section with no imports"; return 1; }
  grep -qF "$WARN_LINE" "$RUN_OUT" || { CASE_DETAIL="no warning that the old rules stop loading"; return 1; }
  grep -qF 'It imported no files, so nothing was carried over.' "$RUN_OUT" || { CASE_DETAIL="the run does not say nothing was carried"; return 1; }
}

case_A6() {   # a symlinked CLAUDE.md
  local p before
  p="$(newtmp)/p"; mk_base "$p" || { CASE_DETAIL="fixture"; return 1; }
  printf '# notes\n\n@README.md\n' > "$p/docs/claude-notes.md"
  ln -s docs/claude-notes.md "$p/CLAUDE.md"
  commit_base "$p" || { CASE_DETAIL="fixture"; return 1; }
  before="$(newtmp)/notes"; cp "$p/docs/claude-notes.md" "$before"
  run_adopt "$1" "$p"; adopt_ok || return 1
  [ -L "$p/CLAUDE.md" ] || { CASE_DETAIL="the symlink was replaced"; return 1; }
  cmp -s "$before" "$p/docs/claude-notes.md" || { CASE_DETAIL="the link's target was written"; return 1; }
  grep -qF "$WARN_LINE" "$RUN_OUT" && { CASE_DETAIL="the warning, for a CLAUDE.md that was left alone"; return 1; }
  return 0
}

check() {   # LABEL CASE
  CASE_DETAIL=""
  if "$2" "$REPO_ROOT"; then pass "$1"; else fail_ "$1" "${CASE_DETAIL:-failed}"; fi
}

echo "=== U — units ==="
check "U1: the import parser reads what Claude Code would import, as written" case_U1
check "U2: each kind of import is carried (normalised, once), or named with its reason" case_U2
check "U2b: an archive record that cannot be read fails closed: nothing is carried on its say-so" case_U2b
check "U3: the archive disclosure says replaced / composed / only copied; no restore line for a kept file" case_U3
check "U4: MANIFEST.md says the same, with no cp for a kept row" case_U4
check "U5: 'Next: the assessment' says the old rules do not load yet, only when CLAUDE.md was replaced" case_U5
check "U6: the assessment prompt's step 8 names the carried section" case_U6
check "U7: every reason a run can give for not carrying an import reads as written" case_U7
echo "=== S — Scout ==="
check "S1: Scout's replaced-document rows are adoption's set and say so; CHANGELOG.md stays theirs" case_S1
echo "=== A — adoption ==="
check "A1: the carried section holds exactly the qualifying imports; the run names the rest and warns" case_A1
check "A2: the archive says only copied / replaced per file; a replaced framework script is recorded replaced" case_A2
check "A3: the assessment prompt names the carried section" case_A3
check "A4: no CLAUDE.md: no section, no warning" case_A4
check "A5: a CLAUDE.md with no imports: no section; the warning says nothing was carried" case_A5
check "A6: a symlinked CLAUDE.md is left alone: no section, no warning" case_A6

# ── M: mutants ───────────────────────────────────────────────────────────────
mk_mirror() {   # SRC DST — scripts, templates and init.sh: enough for every case
  mkdir -p "$2" && cp -Rp "$1/scripts" "$1/templates" "$1/init.sh" "$2/"
}
mutate() {   # FILE MARKER REPLACEMENT — exactly one line ends in MARKER; it now reads REPLACEMENT; still parses
  local f="$1" mark="$2" repl="$3" n=""
  [ -f "$f" ] || { echo "no such file: $f"; return 1; }
  n="$(MARK="$mark" awk 'BEGIN{c=0; m=ENVIRON["MARK"]} length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m {c++} END{print c}' "$f")"
  [ "$n" = "1" ] || { echo "marker '$mark' ends $n line(s) of $f (need 1)"; return 1; }
  MARK="$mark" REPL="$repl" awk '{ m=ENVIRON["MARK"]
      if (length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m) print ENVIRON["REPL"]; else print }' \
    "$f" > "$f.mut" && cat "$f.mut" > "$f" && rm -f "$f.mut"
  # Ending in the marker, not containing it: `# BL-322-CARRY-HTML` is a prefix of
  # `# BL-322-CARRY-HTML-RAW`, and both lines stay in the file.
  n="$(MARK="$mark" awk 'BEGIN{c=0; m=ENVIRON["MARK"]} length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m {c++} END{print c}' "$f")"
  [ "$n" = "0" ] || { echo "a line still ends in the marker after the edit"; return 1; }
  [ "$(grep -cxF -- "$repl" "$f")" -ge 1 ] || { echo "replacement did not land"; return 1; }
  bash -n "$f" 2>/dev/null || { echo "mutant does not parse"; return 1; }
  return 0
}
drop_line() {   # FILE LINE — exactly one line equals LINE; it is deleted
  local f="$1" line="$2"
  [ "$(grep -cxF -- "$line" "$f")" = 1 ] || { echo "'$line' is not exactly one line of $f"; return 1; }
  LINE="$line" awk '$0 != ENVIRON["LINE"]' "$f" > "$f.mut" && cat "$f.mut" > "$f" && rm -f "$f.mut"
  [ "$(grep -cxF -- "$line" "$f")" = 0 ] || { echo "the line is still there"; return 1; }
}
run_mutant() {   # ID WHAT KILLER MIRROR
  local rc=0
  CASE_DETAIL=""
  "$3" "$4" || rc=$?
  if [ "$rc" -eq 0 ]; then fail_ "$1" "$2 — SURVIVED: ${3#case_} still passes against the mutant"
  else pass "$1 (MUTATION) — $2: killed by ${3#case_} (${CASE_DETAIL:-failed})"; fi
}
mutant() {   # ID FILE MARKER REPLACEMENT KILLER WHAT
  local m why
  m="$(newtmp)/mirror"
  mk_mirror "$REPO_ROOT" "$m" || { fail_ "$1" "could not build a mirror"; return; }
  why="$(mutate "$m/$2" "$3" "$4")" || { fail_ "$1" "mutant did not land: $why"; return; }
  run_mutant "$1" "$6" "$5" "$m"
}
mutant_drop() {   # ID FILE LINE KILLER WHAT
  local m why
  m="$(newtmp)/mirror"
  mk_mirror "$REPO_ROOT" "$m" || { fail_ "$1" "could not build a mirror"; return; }
  why="$(drop_line "$m/$2" "$3")" || { fail_ "$1" "mutant did not land: $why"; return; }
  run_mutant "$1" "$5" "$4" "$m"
}
# sub_line FILE MARKER OLD NEW — on the one line ending in MARKER, the fixed text
# OLD (its first occurrence) becomes NEW. Exactly one line changes; still parses.
# For a mutant that narrows a guard rather than removing it (review round 1).
sub_line() {
  local f="$1" mark="$2" old="$3" new="$4" n="" d=""
  n="$(MARK="$mark" OLD="$old" awk 'BEGIN{c=0; m=ENVIRON["MARK"]} length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m && index($0, ENVIRON["OLD"]) {c++} END{print c}' "$f")"
  [ "$n" = 1 ] || { echo "'$old' on a line ending '$mark': $n line(s) of $f (need 1)"; return 1; }
  cp "$f" "$f.orig" || return 1
  MARK="$mark" OLD="$old" NEW="$new" awk '{ m = ENVIRON["MARK"]
      if (length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m && (i = index($0, ENVIRON["OLD"]))) $0 = substr($0, 1, i - 1) ENVIRON["NEW"] substr($0, i + length(ENVIRON["OLD"]))
      print }' "$f.orig" > "$f"
  d="$(diff "$f.orig" "$f" | grep -c '^>')"
  [ "$d" = 1 ] || { echo "changed $d line(s), want 1"; return 1; }
  grep -qF -- "$new" "$f" || { echo "the new text did not land"; return 1; }
  bash -n "$f" 2>/dev/null || { echo "mutant does not parse"; return 1; }
}
mutant_sub() {   # ID FILE MARKER OLD NEW KILLER WHAT
  local m why
  m="$(newtmp)/mirror"
  mk_mirror "$REPO_ROOT" "$m" || { fail_ "$1" "could not build a mirror"; return; }
  why="$(sub_line "$m/$2" "$3" "$4" "$5")" || { fail_ "$1" "mutant did not land: $why"; return; }
  run_mutant "$1" "$7" "$6" "$m"
}
echo "=== M — mutants ==="
DOC=scripts/lib/adopt/adopt-docs.sh
# The parser (U1).
mutant_sub M1 "$DOC" '# BL-322-CARRY-FENCE' '^ ? ? ?(' '^(' case_U1 "a fence indented one to three spaces is not a fence (review R-S2-4 B)"
mutant_sub M2 "$DOC" '# BL-322-CARRY-FENCE' '(```|~~~)' '(```)' case_U1 "a ~~~ fence is not a fence"
mutant_sub M3 "$DOC" '# BL-322-CARRY-FENCE-LEN' 'n >= flen && ' '' case_U1 "a shorter fence closes a longer one"
mutant M4 "$DOC" '# BL-322-CARRY-SPAN' '        if (0) { out = out }' case_U1 "a code span is read for imports"
mutant M5 "$DOC" '# BL-322-CARRY-CRLF' '      line = line' case_U1 "a CRLF file keeps its CRs (review R-S2-3)"
mutant M6 "$DOC" '# BL-322-CARRY-INDENT' '      if (0) { incode = 1; next }' case_U1 "indented code is read for imports"
mutant M7 "$DOC" '# BL-322-CARRY-QUOTE-CODE' '      t = line' case_U1 "indented code in a quote is read for imports"
mutant M8 "$DOC" '# BL-322-CARRY-BREAK' '      if (0) { para = 0; next }' case_U1 "a setext underline continues a paragraph, so the code after it is read"
mutant M9 "$DOC" '# BL-322-CARRY-REFDEF' '      if (0) next' case_U1 "a link reference definition is read for imports"
mutant M10 "$DOC" '# BL-322-CARRY-HTML-RAW' '      if (0) rawend = ""' case_U1 "a <script> block ends at a blank line"
mutant M11 "$DOC" '# BL-322-CARRY-HTML-PI' '      else if (0) rawend = "?>"' case_U1 "a processing instruction is read for imports"
mutant M12 "$DOC" '# BL-322-CARRY-HTML-CDATA' '      else if (0) rawend = "]]>"' case_U1 "a CDATA block is read for imports"
mutant M13 "$DOC" '# BL-322-CARRY-HTML-DECL' '      else if (0) rawend = ">"' case_U1 "a declaration is read for imports"
mutant M14 "$DOC" '# BL-322-CARRY-HTML' '      if (0) { inhtml = 1; next }' case_U1 "an HTML block is read for imports (review R-S2-2)"
mutant M15 "$DOC" '# BL-322-CARRY-COMMENT' '        if (e) line = substr(line, 1, k - 1) " " substr(line, k + 4)' case_U1 "an HTML comment is read for imports (review R-S2-2)"
mutant M16 "$DOC" '# BL-322-CARRY-COMMENT-OPEN' '        else { line = substr(line, 1, k - 1) }' case_U1 "a comment across lines is read for imports (review R-S2-2)"
mutant M17 "$DOC" '# BL-322-CARRY-COMMENT-SHORT' '        if (0) { continue }' case_U1 "<!--> opens a comment instead of closing one"
mutant M18 "$DOC" '# BL-322-CARRY-COMMENT-SHORT2' '        if (0) { continue }' case_U1 "<!---> opens a comment instead of closing one"
mutant M19 "$DOC" '# BL-322-CARRY-RAW' '      if (0) raw = 1' case_U1 "the rest of a comment block's line is read as Markdown"
mutant M20 "$DOC" '# BL-322-CARRY-NBSP' '      line = line' case_U1 "a no-break space is not a space"
mutant M21 "$DOC" '# BL-322-CARRY-WS' '        if (1) kind = 1' case_U1 "an @ inside a word (an address) is read as an import"
mutant M22 "$DOC" '# BL-322-CARRY-EMPH' '          if (0) { kind = 2 }' case_U1 "an import that opens emphasis is missed"
mutant M23 "$DOC" '# BL-322-CARRY-LINKTEXT' '        } else if (0) { kind = 3 }' case_U1 "an import that opens a link's text is missed"
mutant M24 "$DOC" '# BL-322-CARRY-BACKSLASH' '          if (c == "\\") { if (substr(line, k + 1, 1) != " ") { tok = tok c; k++; continue }; tok = tok "\\ "; k += 2; continue }' case_U1 "a backslash that escapes no space stays in the path"
mutant M25 "$DOC" '# BL-322-CARRY-FRAGMENT' '        h = 0' case_U1 "the #… of an import stays in the path (review R-S2-5)"
mutant M26 "$DOC" '# BL-322-CARRY-PATHCHAR' '        if (0) continue' case_U1 "a quoted path is read as an import"
# The decision (U2, U2b).
mutant M27 "$DOC" '# BL-322-CARRY-HOME' '      :' case_U2 "a home-folder or absolute import is treated as a project file"
mutant M28 "$DOC" '# BL-322-CARRY-OUTSIDE' '      norm="$path"' case_U2 "an import outside the project is carried"
mutant M29 "$DOC" '# BL-322-CARRY-LINK' '      if false; then reason=link' case_U2 "a symlinked import is carried"
mutant M30 "$DOC" '# BL-322-CARRY-MISSING' '      elif false; then reason=missing' case_U2 "a missing import loses its reason"
mutant M31 "$DOC" '# BL-322-CARRY-NOTFILE' '      elif false; then reason=not-a-file' case_U2 "a directory import is carried"
mutant M32 "$DOC" '# BL-322-CARRY-ARCHIVED' '      elif false; then reason=archived' case_U2 "an import of a file adoption replaces is carried"
mutant M33 "$DOC" '# BL-322-CARRY-WRITTEN' '      elif false; then reason=written' case_U2 "an import of a file adoption wrote is carried"
mutant_sub M34 "$DOC" '# BL-322-CARRY-ARCHIVED' '"$root" "$norm"' '"$root" "$path"' case_U2 "the archive is asked about the import as written, so ./FEATURES.md is carried (review R-S2-4 A)"
mutant_sub M35 "$DOC" '# BL-322-CARRY-WRITTEN' '"$root" "$norm"' '"$root" "$path"' case_U2 "the ledger is asked about the import as written, so ./WRITTEN.md is carried (review R-S2-4 D)"
mutant_sub M36 "$DOC" '# BL-322-CARRY-FAILCLOSED' 'select(.disposition != "kept")' 'select(.disposition == "replaced")' case_U2 "a composed file is carried (review R-S2-4 E)"
mutant_sub M37 "$DOC" '# BL-322-CARRY-FAILCLOSED' ' || arch_bad=1' '' case_U2b "an unreadable archive record carries everything (review R-S2-10 a)"
mutant M38 "$DOC" '# BL-322-CARRY-CASE' '    :' case_U2 "another case of a replaced file's name is carried (review R-S2-9)"
mutant M39 "$DOC" '# BL-322-CARRY-CNTRL' '    :' case_U2 "a control character reaches the output (review R-S2-8)"
mutant M40 "$DOC" '# BL-322-CARRY-NORMWRITE' '    out="$tok"' case_U2 "the import is written as spelled, not normalised (review R-S2-10 b)"
mutant M41 "$DOC" '# BL-322-CARRY-DEDUPE' '    :' case_U2 "two spellings of one file are carried twice"
mutant_drop M42 "$DOC" "    written)    printf 'adoption wrote that file; it is not one of yours' ;;" case_U7 "a reason's text is lost (review R-S2-4 C)"
# The stage (real adoptions).
mutant M43 "$DOC" '# BL-322-CARRY-APPEND' '    :' case_A1 "the carried section is not written"
mutant M44 "$DOC" '# BL-322-CARRY-WARN' '    :' case_A1 "the warning is not printed"
mutant M45 "$DOC" '# BL-322-CARRY-ONLY-REPLACED' '  if true; then' case_A4 "the warning is printed when no CLAUDE.md was replaced"
mutant M46 "$DOC" '# BL-322-CARRY-FLAG' '    replaced) replaced="$replaced CLAUDE.md" ;;' case_A1 "replacing CLAUDE.md does not raise the flag the warnings read"
mutant M47 "$DOC" '# BL-322-CARRY-MERGED' '    if false; then' case_A1 "the run says nothing was merged beside the imports it carried (review R-S2-11)"
ARC=scripts/lib/adopt/adopt-archive.sh
mutant M48 "$ARC" '# BL-322-DISCLOSE-DISPO' '          *)        adopt_note "   moved" ;;' case_U3 "a kept file is not said to be only copied"
mutant M49 "$ARC" '# BL-322-DISCLOSE-KEPT' '        elif false; then :' case_U3 "a kept file gets a restore line"
mutant M50 "$ARC" '# BL-322-MANIFEST-KEPT' '                        elif false then "x"' case_U4 "MANIFEST.md gives a kept file a cp"
mutant M51 "$ARC" '# BL-322-ARCHIVE-DISPO-SCRIPT' '    :' case_A2 "a framework script adoption replaced is recorded kept"
ACT=scripts/lib/adopt/adopt-act4.sh
mutant M52 "$ACT" '# BL-322-ACT3-RULES' '  if false; then' case_U5 "'Next: the assessment' stops saying the old rules do not load"
mutant_drop M53 "$ACT" '   If CLAUDE.md has a section "Carried over from your CLAUDE.md": it keeps loading the files' case_U6 "step 8 stops naming the carried section"
SCO=scripts/lib/scout/scout-collisions.sh
mutant M54 "$SCO" '# BL-322-SCOUT-DOCS' '    bucket="keep-theirs"' case_S1 "Scout says a replaced document stays"

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
