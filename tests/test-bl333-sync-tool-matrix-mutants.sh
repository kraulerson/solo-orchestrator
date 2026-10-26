#!/usr/bin/env bash
# tests/test-bl333-sync-tool-matrix-mutants.sh — `## BL-333:`'s MUTATION PROOFS,
# split out of tests/test-bl333-sync-tool-matrix.sh (R-BL333-14) so the cases and
# the mutants each run on a unit-shard leg of their own (.github/workflows/tests.yml,
# `pin_adopt` and `pin_lint_scan`). As one file, unpinned in `rest`, they would
# have taken that leg (566s on main run 39629060444) past BL-350's 576s line.
#
# THIS FILE OWNS NO CASE. It SOURCES tests/test-bl333-sync-tool-matrix.sh, which,
# sourced rather than run, defines its stubs, fixtures and cases and returns
# before running any (`# BL-333-MUTANTS-SPLIT`; the precedent is
# `# BL-311-MCP-SPLIT`). Each mutant below changes ONE marked line in a fresh
# COPY of the framework, asserts the change landed by its literal text and still
# parses, and re-runs the case that must now fail. The tree under test is never
# edited.
#
# IT CANNOT PASS HAVING PROVED NOTHING. Each of these is a FAIL: the cases file is
# not beside this one; loading it did not define the counters and the cases, or
# counted an outcome (it ran cases); this file declares no mutant (a line that
# starts `mutant M`, `mutant_in M`, `mutant_add M` or `mutant_fd M`); or the
# mutants judged are not the mutants declared — each ends in exactly one [PASS]
# or [FAIL], so a different count means one never ran. Run as root it FAILS:
# a 555 directory stays writable, and three killers (S8, S12, U4) rest on one.
set -uo pipefail

_BL333_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BL333_CASES="$_BL333_DIR/test-bl333-sync-tool-matrix.sh"
_BL333_SELF="$_BL333_DIR/$(basename "${BASH_SOURCE[0]}")"
echo "== BL-333 — mutation proofs: --sync-framework and templates/tool-matrix/ =="
if [ ! -f "$_BL333_CASES" ]; then
  echo "  [FAIL] loading the cases — $_BL333_CASES is not there, so no mutant can be judged"
  echo ""; echo "Results: 0 passed, 1 failed"; exit 1
fi
. "$_BL333_CASES"
if [ -z "${PASSED+x}" ] || [ -z "${FAILED+x}" ] \
   || ! declare -F pass fail_ mk_fw case_P2 case_S2 case_U1 case_H4 case_L2 >/dev/null 2>&1; then   # BL-333-MUTANTS-LOADED
  echo "  [FAIL] loading the cases — it did not define the counters, pass/fail_, mk_fw and the cases (# BL-333-MUTANTS-SPLIT above them?), so no mutant can be judged"
  echo ""; echo "Results: 0 passed, 1 failed"; exit 1
fi
if [ $((PASSED + FAILED)) -ne 0 ]; then
  echo "  [FAIL] loading the cases — $((PASSED + FAILED)) outcome(s) were counted while sourcing it: it ran cases, not only their definitions (# BL-333-MUTANTS-SPLIT)"
  echo ""; echo "Results: $PASSED passed, $((FAILED + 1)) failed"; exit 1
fi
if [ "$(id -u)" = 0 ]; then
  fail_ "running as root" "a 555 directory stays writable, so the killers built on one (S8, S12, U4) would kill their mutants for the wrong reason — run as a normal user"
fi
_BL333_N0=$((PASSED + FAILED))

# mutate_in <file> <marker> <from> <to>: on the ONE line ending in <marker>,
# replace the ONE occurrence of the literal <from> with <to>. The marker stays, so
# this is the mutant a whole-line edit cannot express: the line keeps its job and
# loses one part of it. Proves the new line landed, the old one is gone, and the
# file still parses. Split, not ${var/pat/rep}: an `&` in <to> is literal here on
# every bash.
mutate_in() {
  local f="$1" mark="$2" from="$3" to="$4" line="" new=""
  [ -f "$f" ] || { echo "no such file: $f"; return 1; }
  line="$(MARK="$mark" awk 'BEGIN{m=ENVIRON["MARK"]} length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m' "$f")"
  [ -n "$line" ] && [ "$(printf '%s\n' "$line" | wc -l | tr -d ' ')" = 1 ] \
    || { echo "marker '$mark' does not end exactly one line of $f"; return 1; }
  case "$line" in *"$from"*) ;; *) echo "'$from' is not on the marked line"; return 1 ;; esac
  case "${line#*"$from"}" in *"$from"*) echo "'$from' occurs more than once on the marked line"; return 1 ;; esac
  new="${line%%"$from"*}$to${line#*"$from"}"
  LINE="$line" NEW="$new" awk '{ if ($0 == ENVIRON["LINE"]) print ENVIRON["NEW"]; else print }' "$f" > "$f.mut" \
    && cat "$f.mut" > "$f" && rm -f "$f.mut"
  [ "$(command grep -cxF -- "$new" "$f")" = 1 ] || { echo "the mutated line did not land"; return 1; }
  ! command grep -qxF -- "$line" "$f" || { echo "the original line is still there"; return 1; }
  bash -n "$f" 2>/dev/null || { echo "mutant does not parse"; return 1; }
  return 0
}

# mutate_add <file> <marker> <line>: insert <line> after the ONE line ending in
# <marker>, which stays. Proves the new line landed and the file still parses.
mutate_add() {
  local f="$1" mark="$2" add="$3" n=""
  [ -f "$f" ] || { echo "no such file: $f"; return 1; }
  n="$(MARK="$mark" awk 'BEGIN{c=0; m=ENVIRON["MARK"]} length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m {c++} END{print c}' "$f")"
  [ "$n" = "1" ] || { echo "marker '$mark' ends $n line(s) of $f (need 1)"; return 1; }
  MARK="$mark" ADD="$add" awk '{ m=ENVIRON["MARK"]; print
      if (length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m) print ENVIRON["ADD"] }' \
    "$f" > "$f.mut" && cat "$f.mut" > "$f" && rm -f "$f.mut"
  [ "$(command grep -cxF -- "$add" "$f")" -ge 1 ] || { echo "the added line did not land"; return 1; }
  bash -n "$f" 2>/dev/null || { echo "mutant does not parse"; return 1; }
  return 0
}

# Each builds a fresh mirror — the suite's matrix and history, or (real-matrix)
# the repository's own templates — applies ONE mutant, and runs the case that
# must now fail.
mutant_mirror() {   # mutant_mirror <dst> [real-matrix]
  if [ "${2:-}" = real-matrix ]; then mk_mirror "$REPO_ROOT" "$1"; else mk_fw "$1"; fi
}
judge() {   # judge <id> <killer-case> <mirror> <what>
  CASE_DETAIL=""
  if "$2" "$3"; then
    fail_ "$1" "$4 — SURVIVED: ${2#case_} still passes against the mutant ($CASE_DETAIL)"
  else
    pass "$1 (MUTATION) — $4: killed by ${2#case_} ($CASE_DETAIL)"
  fi
}
mutant() {   # mutant <id> <rel-file> <marker> <replacement> <killer-case> <what> [real-matrix]
  local m="" why=""
  m="$(newtmp)/mirror"
  mutant_mirror "$m" "${7:-}" || { fail_ "$1" "could not build a mirror"; return; }
  why="$(mutate "$m/$2" "$3" "$4")" || { fail_ "$1" "mutant did not land: $why"; return; }
  judge "$1" "$5" "$m" "$6"
}
mutant_in() {   # mutant_in <id> <rel-file> <marker> <from> <to> <killer-case> <what> [real-matrix]
  local m="" why=""
  m="$(newtmp)/mirror"
  mutant_mirror "$m" "${8:-}" || { fail_ "$1" "could not build a mirror"; return; }
  why="$(mutate_in "$m/$2" "$3" "$4" "$5")" || { fail_ "$1" "mutant did not land: $why"; return; }
  judge "$1" "$6" "$m" "$7"
}
mutant_add() {   # mutant_add <id> <rel-file> <marker> <line> <killer-case> <what> [real-matrix]
  local m="" why=""
  m="$(newtmp)/mirror"
  mutant_mirror "$m" "${7:-}" || { fail_ "$1" "could not build a mirror"; return; }
  why="$(mutate_add "$m/$2" "$3" "$4")" || { fail_ "$1" "mutant did not land: $why"; return; }
  judge "$1" "$5" "$m" "$6"
}
# mutant_fd <id> <what> — the list back on stdin is TWO edits (the read AND the
# redirect), so it is spelled out rather than routed through `mutant`.
mutant_fd() {
  local m="" why=""
  m="$(newtmp)/mirror"
  mk_fw "$m" || { fail_ "$1" "could not build a mirror"; return; }
  why="$(mutate "$m/$U" '# BL-333-MATRIX-OWN-FD' '  while IFS= read -r rel; do')" || { fail_ "$1" "mutant did not land: $why"; return; }
  why="$(mutate "$m/$U" '  done 3<<EOF' '  done <<EOF')" || { fail_ "$1" "mutant did not land: $why"; return; }
  judge "$1" case_S9 "$m" "$2"
}

U=scripts/upgrade-project.sh
# The visit, the vendored check and the missing-file copy.
mutant M1 "$U" '# BL-333-MATRIX-SYNC' ':' case_S1 \
  "the sync never visits the tool matrix"
mutant M2 "$U" '# BL-333-MATRIX-VENDORED' ':' case_S7 \
  "a project with no vendored matrix is treated as one"
mutant M3 "$U" '# BL-333-MATRIX-DRYRUN' ':' case_S5 \
  "--dry-run copies a missing matrix file"
mutant M4 "$U" '# BL-333-MATRIX-WRITE-STATUS' ':' case_S8 \
  "a copy that did not land is reported as copied"
mutant_in M12 "$U" '# BL-333-MATRIX-WRITE-STATUS' '_bl099_write_ok "$rc" "$src" "$dst"' '[ "$rc" -eq 0 ]' case_S11 \
  "a copy is judged by cp's exit status alone, the bytes never re-read"
mutant_in M49 "$U" '# BL-333-MATRIX-WRITE-STATUS' '[ -L "$dst" ] || rm -f "$dst" 2>/dev/null || true; ' '' case_S13 \
  "a failed copy leaves its fragment, which every later sync then keeps as the project's own"
mutant M53 "$U" '# BL-333-MATRIX-NO-LINK-NEW' ':' case_L1 \
  "a missing file is copied through a dangling link"
mutant M55 "$U" '# BL-333-MATRIX-LINK-SAY' ':' case_L1 \
  "a refused link is not named"
mutant M11 "$U" '# BL-333-MATRIX-EMPTY-SET' \
  '  shipped="$(soif_parse_shipped_tool_matrix "$ORCHESTRATOR_ROOT/init.sh" "$ORCHESTRATOR_ROOT")"' case_S10 \
  "an empty matrix set ends the whole sync under set -e"
mutant M52 "$U" '# BL-333-SYNC-GIT-ENV' ':' case_G1 \
  "an exported GIT_DIR swaps the project's history in for the framework's"
# A copy whose bytes match no shipped version: the reference documents' treatment.
mutant M5 "$U" '# BL-333-MATRIX-DRIFT' '    cp "$src" "$dst"' case_S2 \
  "a drifted matrix is overwritten silently, the project's own values lost"
mutant M6 "$U" '# BL-333-MATRIX-DRIFT' ':' case_S3 \
  "a drifted matrix is neither reported nor applied"
mutant_in M13 "$U" '# BL-333-MATRIX-DRIFT' ' || DOC_APPLY_FAILED=true' '' case_S12 \
  "a failed apply ends the sync under set -e, the files after it never visited"
mutant M7 "$U" '# BL-333-MATRIX-KEPT-NOTE' ':' case_S2 \
  "an unapplied drift no longer says which floors stay in force"
mutant_in M14 "$U" '# BL-333-MATRIX-KEPT-NOTE' 'if ! cmp -s "$src" "$dst"; then ' 'if true; then ' case_S6 \
  "an up-to-date matrix is still said to keep its old floors"
# A copy whose bytes match a shipped version: found in the framework's history, and replaced.
mutant M15 "$U" '# BL-333-MATRIX-DIFFERS' '    if true; then' case_U3 \
  "the history is consulted for a file already up to date, and it is updated again"
mutant M16 "$U" '# BL-333-MATRIX-LOOKUP' '      hrc=0; at=""' case_S2 \
  "every differing copy is taken for a shipped one, the project's own values replaced"
mutant M17 "$U" '# BL-333-MATRIX-SHIPPED' ':' case_U1 \
  "an old shipped copy is reported and kept, its old floor still in force"
mutant_in M18 "$U" '# BL-333-MATRIX-SHIPPED' ' || DOC_APPLY_FAILED=true' '' case_U4 \
  "a failed update ends the sync under set -e, the files after it never visited"
mutant M19 "$U" '# BL-333-MATRIX-WHY' ':' case_S2 \
  "a kept copy no longer says why it was not updated"
mutant_in M20 "$U" '# BL-333-MATRIX-WHY' 'if [ "$hrc" -eq 1 ]; then' 'if [ "$hrc" -ne 1 ]; then' case_H1 \
  "a framework with no history is reported as having no such version"
mutant_in M47 "$U" '# BL-333-MATRIX-WHY' 'elif [ "$hrc" -eq 3 ]; then' 'elif false; then' case_H4 \
  "a shallow clone is reported as no history at all, with no way to fix it named"
mutant M21 "$U" '# BL-333-MATRIX-HISTORY-ROOT' ':' case_H2 \
  "a framework inside some other repository reads that repository's history as its own"
mutant_in M22 "$U" '# BL-333-MATRIX-HISTORY-ROOT' '[ "$top" -ef "$ORCHESTRATOR_ROOT" ]' 'true' case_H2 \
  "any enclosing repository counts as the framework's history"
mutant_in M23 "$U" '# BL-333-MATRIX-HISTORY-READ' ' || return 2' '' case_H3 \
  "a log git cannot read is taken for a history with no such version"
mutant_in M48 "$U" '# BL-333-MATRIX-HISTORY-READ' ' -- "$rel"' '' case_U9 \
  "bytes the framework shipped as another file count as this file's version"
mutant M24 "$U" '# BL-333-MATRIX-HISTORY-MISS' ':' case_S2 \
  "a copy with no match in the history is taken for a shipped one"
mutant_in M46 "$U" '# BL-333-MATRIX-HISTORY-MISS' \
  '[ "$(git -C "$ORCHESTRATOR_ROOT" rev-parse --is-shallow-repository 2>/dev/null)" = true ] && return 3; ' '' case_H4 \
  "a shallow clone's missing history is taken for proof the copy is the project's own"
mutant M25 "$U" '# BL-333-MATRIX-HISTORY-SAY' ':' case_U1 \
  "the update no longer names a commit"
mutant_in M51 "$U" '# BL-333-MATRIX-HISTORY-SAY' 'sed -n 1p' "sed -n '\$p'" case_U1 \
  "the update names the commit that REPLACED those bytes, not the one that has them"
mutant M54 "$U" '# BL-333-UPDATE-NO-LINK' ':' case_L2 \
  "an old shipped copy is updated through a live link, outside the project"
mutant M26 "$U" '# BL-333-UPDATE-BAK' '  bak="$dst.bak"' case_U1 \
  "the backup loses its date"
mutant M27 "$U" '# BL-333-UPDATE-DRYRUN' ':' case_U2 \
  "--dry-run replaces a shipped copy"
mutant M28 "$U" '# BL-333-UPDATE-COPY-OLD' ':' case_U1 \
  "the backup is never written, so every update is refused"
mutant M29 "$U" '# BL-333-UPDATE-VERIFY-BAK' ':' case_U4 \
  "a shipped copy is replaced with no verified backup"
mutant_in M30 "$U" '# BL-333-UPDATE-VERIFY-BAK' '_bl099_write_ok "$rc" "$dst" "$bak"' '[ "$rc" -eq 0 ]' case_U5 \
  "a backup is judged by cp's exit status alone, the bytes never re-read"
mutant_in M50 "$U" '# BL-333-UPDATE-VERIFY-BAK' 'then print_fail' 'then rm -f "$bak"; print_fail' case_U5 \
  "a backup that did not verify is deleted"
mutant M31 "$U" '# BL-333-UPDATE-COPY-NEW' ':' case_U1 \
  "the framework's file is never written"
mutant M32 "$U" '# BL-333-UPDATE-VERIFY-NEW' ':' case_U1 \
  "a landed update is undone and reported as failed"
mutant_in M33 "$U" '# BL-333-UPDATE-VERIFY-NEW' '_bl099_write_ok "$rc" "$src" "$dst"' '[ "$rc" -eq 0 ]' case_U6 \
  "an update is judged by cp's exit status alone, the bytes never re-read"
mutant M34 "$U" '# BL-333-UPDATE-PUT-BACK' ':' case_U6 \
  "a failed update leaves the half-written file in place"
mutant M35 "$U" '# BL-333-UPDATE-SAY-FAIL' ':' case_U6 \
  "a failed update prints no [FAIL] line"
mutant_in M36 "$U" '# BL-333-UPDATE-SAY-FAIL' 'if _bl099_write_ok "$rrc" "$bak" "$dst"; then' 'if true; then' case_U7 \
  "a putting-back that failed is reported as done"
# No vendored matrix: the copy check-versions reads, as found.
mutant M37 "$U" '# BL-333-MATRIX-NONE-READ' '  where=""' case_S7 \
  "the copy check-versions reads is never looked up"
mutant_in M38 "$U" '# BL-333-MATRIX-NONE-READ' ' && [ -d "$s/templates/tool-matrix" ]' '' case_V2 \
  "a source_dir with no matrix in it is named as the copy check-versions reads"
mutant M39 "$U" '# BL-333-MATRIX-NONE-UNREAD' ':' case_V2 \
  "a project whose check-versions has no matrix to read is not told so"
mutant M40 "$U" '# BL-333-MATRIX-NONE-OWN' ':' case_S7 \
  "the framework's own copy is reported as another checkout's"
mutant_in M41 "$U" '# BL-333-MATRIX-NONE-OWN' '[ "$where" -ef "$ORCHESTRATOR_ROOT" ]' 'true' case_V1 \
  "another checkout's copy is reported as this framework's own"
mutant M42 "$U" '# BL-333-MATRIX-NONE-OTHER' ':' case_V1 \
  "a project reading another checkout's floors is not told so"
# The derived set, and init.sh's own lines.
mutant M8 scripts/lib/scaffold-shipped-set.sh '# BL-333-MATRIX-PARSER' \
  '        for f in "$fw_dir"/templates/tool-matrix/common.json; do' case_P1 \
  "the parser becomes a hand-kept list" real-matrix
mutant_in M9 init.sh '# BL-333-MATRIX-SHIP' '"$SCRIPT_DIR/templates/tool-matrix/"*.json' \
  '"$SCRIPT_DIR/templates/tool-matrix/"common.json "$SCRIPT_DIR/templates/tool-matrix/"web.json' case_P2 \
  "init.sh ships two files from one cp line the parser reads as one" real-matrix
mutant_add M43 init.sh '# BL-333-MATRIX-SHIP' '  cp -p "$SCRIPT_DIR/templates/tool-matrix/"*.json templates/tool-matrix/' case_P2 \
  "a second copy line, cp -p, that the parser never reads" real-matrix
mutant_add M44 init.sh '# BL-333-MATRIX-SHIP' '  cp $SCRIPT_DIR/templates/tool-matrix/*.json templates/tool-matrix/' case_P2 \
  "a second copy line with its path unquoted, that the parser never reads" real-matrix
mutant_add M45 init.sh '# BL-333-MATRIX-SHIP' '  install -m 0644 "$SCRIPT_DIR/templates/tool-matrix/common.json" templates/tool-matrix/' case_P2 \
  "a second copy line, install -m, that the parser never reads" real-matrix
mutant_fd M10 "the matrix list is read on stdin again"

# ── the count ───────────────────────────────────────────────────────────────
# Every mutant above ends in exactly one [PASS] or [FAIL], so the outcomes since
# loading are the mutants judged; the declared ones are this file's own lines that
# start `mutant M`, `mutant_in M`, `mutant_add M` or `mutant_fd M`. Zero declared
# is a FAIL, and so is any difference: a mutant that never ran is not one killed.
_BL333_JUDGED=$((PASSED + FAILED - _BL333_N0))
_BL333_DECLARED="$(command grep -cE '^(mutant|mutant_in|mutant_add|mutant_fd) M[0-9]+ ' "$_BL333_SELF")"
if [ "$_BL333_DECLARED" -lt 1 ]; then
  fail_ "the count" "$_BL333_SELF declares no mutant — nothing was proved"
elif [ "$_BL333_JUDGED" -ne "$_BL333_DECLARED" ]; then
  fail_ "the count" "$_BL333_DECLARED mutant(s) declared, $_BL333_JUDGED judged"
else
  echo "  ($_BL333_JUDGED of $_BL333_DECLARED declared mutants judged)"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
