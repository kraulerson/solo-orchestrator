#!/usr/bin/env bash
# tests/test-bl333-sync-tool-matrix.sh
#
# `## BL-333:` `upgrade-project.sh --sync-framework` never refreshed
# `templates/tool-matrix/`. init.sh copies the matrix into every project and
# `scripts/check-versions.sh` reads the project's copy first, so a floor raised
# upstream (gitleaks 8.18.0 -> 8.19.0, `7578fb9`) never reached a project that
# already existed.
#
# The fix gives the matrix the reference documents' treatment (`_bl099_process_doc`):
#   P  the sync's set is DERIVED from init.sh's own cp line
#      (`soif_parse_shipped_tool_matrix`), and P2 executes that line to prove the
#      two agree.
#   S  a file missing from a vendored matrix is copied verbatim; a drifted one is
#      reported with its diff and applied only when the run declares it
#      (`--apply-doc-updates sidecar|overwrite`, overwrite also needing
#      `--confirm-doc-overwrite` and keeping a dated .bak); `--dry-run` writes
#      nothing; a second run changes nothing; a project with NO vendored matrix
#      (an adopted one: check-versions reads the framework's copy through
#      .claude/orchestrator-source.json) is left without one; a copy that does not
#      land is a [FAIL] and a non-zero exit; an interactive apply reads the
#      operator's answer, not the loop's list (S9); a framework that ships no
#      matrix is a warning, not an exit under `set -e` (S10).
#   M  every BL-333 marker is mutation-proven against a mirror; the tree under
#      test is never edited. Each mutant asserts it LANDED by literal text.
#
# HERMETIC: the framework under test is a mirror with a two-file matrix written
# here (gitleaks only), so check-versions runs one row. gitleaks, curl and brew are
# stubs on PATH; CDF_HOME and HOME point into the fixture; no network, no remote.
# init.sh is READ (P2 runs its two matrix lines, nothing else) and never executed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "  [FAIL] setup — jq is required"; echo ""; echo "Results: 0 passed, 1 failed"; exit 1
fi

TOPTMP="$(mktemp -d)"
trap 'chmod -R u+w "$TOPTMP" 2>/dev/null; rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }

# The two floors are synthetic on purpose: this suite proves the sync carries
# whatever the framework says. The real gitleaks floor is `## BL-289:`'s to pin.
OLD_FLOOR="8.0.0"
NEW_FLOOR="9.0.0"
STUB_VERSION="8.5.0"     # passes OLD_FLOOR, fails NEW_FLOOR
TODAY="$(date -u +%Y-%m-%d)"

STUBS="$TOPTMP/stubs"; mkdir -p "$STUBS"
printf '#!/bin/sh\n[ "${1:-}" = version ] && echo %s\nexit 0\n' "$STUB_VERSION" > "$STUBS/gitleaks"
printf '#!/bin/sh\nexit 1\n' > "$STUBS/curl"    # check-versions: "Network unavailable"
printf '#!/bin/sh\nexit 1\n' > "$STUBS/brew"    # no brew prefix ahead of the stubs
chmod +x "$STUBS/gitleaks" "$STUBS/curl" "$STUBS/brew"

mk_mirror() {
  mkdir -p "$2" && cp -Rp "$1/scripts" "$1/templates" "$1/init.sh" "$2/"
}

# Replace a mirror's matrix with the suite's own two files: common.json holds the
# REAL gitleaks row at NEW_FLOOR, web.json holds nothing.
use_test_matrix() {
  local fw="$1"
  rm -f "$fw/templates/tool-matrix/"*.json
  jq --arg v "$NEW_FLOOR" '{tools: [.tools[] | select(.name == "gitleaks") | .min_version = $v]}' \
    "$REPO_ROOT/templates/tool-matrix/common.json" > "$fw/templates/tool-matrix/common.json" || return 1
  printf '{"tools": []}\n' > "$fw/templates/tool-matrix/web.json"
}

mk_fw() {   # mk_fw <dst> [source-tree]: a mirror carrying the suite's matrix
  mk_mirror "${2:-$REPO_ROOT}" "$1" && use_test_matrix "$1"
}

# mk_project <dir> <fw> <matrix-state>
#   current  — the framework's matrix, byte-identical
#   missing  — common.json current, web.json absent
#   edited   — common.json at OLD_FLOOR with a tool the project added; web.json current
#   both     — edited + missing
#   none     — no templates/tool-matrix/ at all, .claude/orchestrator-source.json -> fw
mk_project() {
  local p="$1" fw="$2" state="$3" m
  m="$p/templates/tool-matrix"
  mkdir -p "$p/.claude" "$p/scripts"
  printf '%s\n' '{"track":"light","deployment":"personal","poc_mode":null,"current_phase":1,"phases":{}}' > "$p/.claude/phase-state.json"
  printf '%s\n' '{"frameworkVersion":"1.0.0","host":"github","mode":"personal","deployment":"personal","poc_mode":null,"enforcement_level":"strict"}' > "$p/.claude/manifest.json"
  printf '%s\n' '{"context":{"track":"light","platform":"web","language":"python"}}' > "$p/.claude/tool-preferences.json"
  if [ "$state" = none ]; then
    jq -n --arg d "$fw" '{source_dir: $d}' > "$p/.claude/orchestrator-source.json"
  else
    mkdir -p "$m"
    cp "$fw/templates/tool-matrix/common.json" "$fw/templates/tool-matrix/web.json" "$m/"
    case "$state" in
      edited|both)
        jq --arg v "$OLD_FLOOR" '.tools |= (map(if .name == "gitleaks" then .min_version = $v else . end)
            + [{"category":"lint","name":"acme-lint","required":false,"phase":2,"tracks":["light"],
                "dev_os":["darwin","linux"],"platforms":["all"],"languages":["all"]}])' \
          "$fw/templates/tool-matrix/common.json" > "$m/common.json" ;;
    esac
    case "$state" in missing|both) rm -f "$m/web.json" ;; esac
  fi
  ( cd "$p" && git init -q && git config user.email t@t.local && git config user.name T \
      && unset GITHUB_BASE_REF && git add -A && git commit -q -m init ) >/dev/null 2>&1
}

OUT=""; RC=0
run_sync() {   # run_sync <proj> <fw> [args...]
  local p="$1" fw="$2"; shift 2
  RC=0
  OUT="$( cd "$p" && unset GITHUB_BASE_REF; HOME="$p/.home" CDF_HOME="$p/.no-such-cdf" SOIF_NONINTERACTIVE=1 \
      bash "$fw/scripts/upgrade-project.sh" --sync-framework "$@" </dev/null 2>&1 )" || RC=$?
}

# The floor check-versions enforces in <proj>, read from its own output.
floor_line() {
  ( cd "$1" && HOME="$1/.home" PATH="$STUBS:$PATH" bash scripts/check-versions.sh </dev/null 2>&1 ) \
    | command grep -F "gitleaks: $STUB_VERSION" | head -1
}

fingerprint() {   # every file under <dir>, path + bytes; "(absent)" when missing
  [ -d "$1" ] || { echo "(absent)"; return; }
  ( cd "$1" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do
      printf '%s %s\n' "$f" "$(cksum < "$f")"; done )
}

has() { printf '%s\n' "$OUT" | command grep -F -- "$1" >/dev/null; }

CASE_DETAIL=""

# mutate <file> <marker> <replacement>: replace the ONE line ending in <marker>,
# then prove the edit landed by its own literal text and still parses.
mutate() {
  local f="$1" mark="$2" repl="$3" n
  [ -f "$f" ] || { echo "no such file: $f"; return 1; }
  n="$(MARK="$mark" awk 'BEGIN{c=0; m=ENVIRON["MARK"]} length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m {c++} END{print c}' "$f")"
  [ "$n" = "1" ] || { echo "marker '$mark' ends $n line(s) of $f (need 1)"; return 1; }
  MARK="$mark" REPL="$repl" awk '{ m=ENVIRON["MARK"]
      if (length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m) print ENVIRON["REPL"]; else print }' \
    "$f" > "$f.mut" && cat "$f.mut" > "$f" && rm -f "$f.mut"
  command grep -qF -- "$mark" "$f" && { echo "marker still present after the edit"; return 1; }
  [ "$(command grep -cxF -- "$repl" "$f")" -ge 1 ] || { echo "replacement did not land"; return 1; }
  bash -n "$f" 2>/dev/null || { echo "mutant does not parse"; return 1; }
  return 0
}

# ── P1: the sync's set is init.sh's matrix copy, derived, never a list ───────
case_P1() {
  local fw="$1" got want
  . "$fw/scripts/lib/scaffold-shipped-set.sh"
  got="$(soif_parse_shipped_tool_matrix "$fw/init.sh" "$fw")"
  want="$( cd "$fw" && ls templates/tool-matrix/*.json | LC_ALL=C sort )"
  CASE_DETAIL="parser=[$(printf '%s' "$got" | tr '\n' ' ')] framework=[$(printf '%s' "$want" | tr '\n' ' ')]"
  [ -n "$got" ] && [ "$got" = "$want" ]
}

# ── P2: running init.sh's own matrix lines lands exactly the parser's set ────
case_P2() {
  local fw="$1" d lines got want
  d="$(newtmp)"
  lines="$(command grep -E '^[[:space:]]*(mkdir -p templates/tool-matrix|cp "\$SCRIPT_DIR/templates/tool-matrix/)' "$fw/init.sh")"
  [ "$(printf '%s\n' "$lines" | command grep -c '^[[:space:]]*cp ')" -ge 1 ] \
    || { CASE_DETAIL="init.sh has no tool-matrix cp line to execute"; return 1; }
  ( cd "$d" && SCRIPT_DIR="$fw" bash -c "$lines" ) >/dev/null 2>&1 || { CASE_DETAIL="init.sh's matrix lines failed"; return 1; }
  got="$( cd "$d" && find templates/tool-matrix -type f | LC_ALL=C sort )"
  . "$fw/scripts/lib/scaffold-shipped-set.sh"
  want="$(soif_parse_shipped_tool_matrix "$fw/init.sh" "$fw")"
  CASE_DETAIL="init.sh copied=[$(printf '%s' "$got" | tr '\n' ' ')] sync set=[$(printf '%s' "$want" | tr '\n' ' ')]"
  [ -n "$got" ] && [ "$got" = "$want" ]
}

# ── S1: a file missing from a vendored matrix is copied verbatim ─────────────
case_S1() {
  local fw="$1" p
  p="$(newtmp)/p"; mk_project "$p" "$fw" missing
  run_sync "$p" "$fw"
  CASE_DETAIL="rc=$RC web.json=$([ -f "$p/templates/tool-matrix/web.json" ] && echo present || echo ABSENT)"
  [ "$RC" = 0 ] && cmp -s "$fw/templates/tool-matrix/web.json" "$p/templates/tool-matrix/web.json" \
    && has "templates/tool-matrix/web.json: copied"
}

# ── S2: a locally edited matrix is reported and KEPT on a bare run ───────────
case_S2() {
  local fw="$1" p before fl
  p="$(newtmp)/p"; mk_project "$p" "$fw" edited
  before="$(fingerprint "$p/templates/tool-matrix")"
  run_sync "$p" "$fw"
  fl="$(floor_line "$p")"
  CASE_DETAIL="rc=$RC check-versions='$fl'"
  [ "$RC" = 0 ] || return 1
  [ "$(fingerprint "$p/templates/tool-matrix")" = "$before" ] || { CASE_DETAIL="$CASE_DETAIL; the project's matrix CHANGED"; return 1; }
  has "templates/tool-matrix/common.json: differs from framework" || { CASE_DETAIL="$CASE_DETAIL; no drift report"; return 1; }
  has "\"min_version\": \"$NEW_FLOOR\"" || { CASE_DETAIL="$CASE_DETAIL; the diff does not show the new floor"; return 1; }
  has "notice only — not applied" || { CASE_DETAIL="$CASE_DETAIL; no notice-only line"; return 1; }
  has "check-versions.sh and the phase gate keep reading your copy" || { CASE_DETAIL="$CASE_DETAIL; no consequence line"; return 1; }
  printf '%s\n' "$fl" | command grep -F "(min: $OLD_FLOOR)" >/dev/null
}

# ── S3: a declared overwrite lands the framework's bytes, with a backup ──────
case_S3() {
  local fw="$1" p old fl
  p="$(newtmp)/p"; mk_project "$p" "$fw" edited
  old="$(cksum < "$p/templates/tool-matrix/common.json")"
  run_sync "$p" "$fw" --apply-doc-updates overwrite --confirm-doc-overwrite
  fl="$(floor_line "$p")"
  CASE_DETAIL="rc=$RC check-versions='$fl'"
  [ "$RC" = 0 ] || return 1
  cmp -s "$fw/templates/tool-matrix/common.json" "$p/templates/tool-matrix/common.json" \
    || { CASE_DETAIL="$CASE_DETAIL; common.json is not the framework's"; return 1; }
  [ -f "$p/templates/tool-matrix/common.json.bak.$TODAY" ] \
    && [ "$(cksum < "$p/templates/tool-matrix/common.json.bak.$TODAY")" = "$old" ] \
    || { CASE_DETAIL="$CASE_DETAIL; no dated .bak holding the project's bytes"; return 1; }
  has "overwrote templates/tool-matrix/common.json" || { CASE_DETAIL="$CASE_DETAIL; no overwrite line"; return 1; }
  printf '%s\n' "$fl" | command grep -F "(min: $NEW_FLOOR) — BELOW MINIMUM" >/dev/null
}

# ── S4: a declared sidecar writes <file>.new and leaves the project's copy ───
case_S4() {
  local fw="$1" p before
  p="$(newtmp)/p"; mk_project "$p" "$fw" edited
  before="$(cksum < "$p/templates/tool-matrix/common.json")"
  run_sync "$p" "$fw" --apply-doc-updates sidecar
  CASE_DETAIL="rc=$RC"
  [ "$RC" = 0 ] && [ "$(cksum < "$p/templates/tool-matrix/common.json")" = "$before" ] \
    && cmp -s "$fw/templates/tool-matrix/common.json" "$p/templates/tool-matrix/common.json.new"
}

# ── S5: --dry-run previews both actions and writes nothing ───────────────────
case_S5() {
  local fw="$1" p before
  p="$(newtmp)/p"; mk_project "$p" "$fw" both
  before="$(fingerprint "$p/templates/tool-matrix")"
  run_sync "$p" "$fw" --dry-run --apply-doc-updates overwrite --confirm-doc-overwrite --non-interactive
  CASE_DETAIL="rc=$RC"
  [ "$RC" = 0 ] || return 1
  [ "$(fingerprint "$p/templates/tool-matrix")" = "$before" ] || { CASE_DETAIL="$CASE_DETAIL; --dry-run WROTE into the matrix"; return 1; }
  has "[would copy] templates/tool-matrix/web.json (missing)" || { CASE_DETAIL="$CASE_DETAIL; no would-copy line"; return 1; }
  has "templates/tool-matrix/common.json: differs from framework" && has "[dry-run] notice only"
}

# ── S6: a second run changes nothing ─────────────────────────────────────────
case_S6() {
  local fw="$1" p after1
  p="$(newtmp)/p"; mk_project "$p" "$fw" both
  run_sync "$p" "$fw" --apply-doc-updates overwrite --confirm-doc-overwrite
  [ "$RC" = 0 ] || { CASE_DETAIL="first run rc=$RC"; return 1; }
  after1="$(fingerprint "$p/templates/tool-matrix")"
  run_sync "$p" "$fw" --apply-doc-updates overwrite --confirm-doc-overwrite
  CASE_DETAIL="second run rc=$RC"
  [ "$RC" = 0 ] && [ "$(fingerprint "$p/templates/tool-matrix")" = "$after1" ] \
    && has "templates/tool-matrix/common.json: up to date" && has "templates/tool-matrix/web.json: up to date"
}

# ── S7: no vendored matrix (adopted) -> none is created; the framework's floor
#        is what check-versions already enforces ─────────────────────────────
case_S7() {
  local fw="$1" p fl
  p="$(newtmp)/p"; mk_project "$p" "$fw" none
  run_sync "$p" "$fw"
  fl="$(floor_line "$p")"
  CASE_DETAIL="rc=$RC matrix=$([ -e "$p/templates/tool-matrix" ] && echo CREATED || echo absent) check-versions='$fl'"
  [ "$RC" = 0 ] && [ ! -e "$p/templates/tool-matrix" ] && has "no templates/tool-matrix/ in this project" \
    && printf '%s\n' "$fl" | command grep -F "(min: $NEW_FLOOR) — BELOW MINIMUM" >/dev/null
}

# ── S8: a copy that does not land is a [FAIL] and a non-zero exit ────────────
case_S8() {
  local fw="$1" p
  p="$(newtmp)/p"; mk_project "$p" "$fw" missing
  chmod 555 "$p/templates/tool-matrix"
  run_sync "$p" "$fw"
  chmod 755 "$p/templates/tool-matrix"
  CASE_DETAIL="rc=$RC"
  [ "$RC" != 0 ] && has "FAILED to copy templates/tool-matrix/web.json" \
    && ! has "templates/tool-matrix/web.json: copied"
}

# ── S9: interactively, the apply prompt reads the OPERATOR's answer ─────────
# The tty question cannot be faked without a pty, so the mirror's one-line seam
# `_bl099_stdin_is_tty` is made to answer yes (asserted landed) and the answer is
# piped in. The matrix loop iterates a list; when that list was the loop's stdin,
# prompt_choice read the next FILE NAME as the operator's answer, and every file
# after the first drifted one was never visited. prompt_yes_no returns at once on
# a non-tty stdin, so the single answer reaches the one prompt_choice.
case_S9() {
  local fw="$1" i p why
  i="$(newtmp)/fw"; mk_mirror "$fw" "$i" || { CASE_DETAIL="mirror"; return 1; }
  why="$(mutate "$i/scripts/upgrade-project.sh" '_bl099_stdin_is_tty() { [ -t 0 ]; }' '_bl099_stdin_is_tty() { true; }')" \
    || { CASE_DETAIL="tty seam did not land: $why"; return 1; }
  p="$(newtmp)/p"; mk_project "$p" "$i" edited
  RC=0
  OUT="$( cd "$p" && printf '2\n' | env -u CI -u SOIF_NONINTERACTIVE -u GITHUB_BASE_REF \
      HOME="$p/.home" CDF_HOME="$p/.no-such-cdf" bash "$i/scripts/upgrade-project.sh" --sync-framework 2>&1 )" || RC=$?
  CASE_DETAIL="rc=$RC sidecar=$([ -f "$p/templates/tool-matrix/common.json.new" ] && echo written || echo ABSENT) invalid-choice=$(printf '%s\n' "$OUT" | command grep -c 'Invalid choice')"
  [ "$RC" = 0 ] && cmp -s "$i/templates/tool-matrix/common.json" "$p/templates/tool-matrix/common.json.new" \
    && ! has "Invalid choice" && has "templates/tool-matrix/web.json: up to date"
}

# ── S10: a framework whose init.sh ships no matrix: a warning, and the sync
#         still finishes. The parser's grep exits 1 on no match, and this script
#         runs under `set -euo pipefail`. ──────────────────────────────────────
case_S10() {
  local fw="$1" i p why
  i="$(newtmp)/fw"; mk_mirror "$fw" "$i" || { CASE_DETAIL="mirror"; return 1; }
  why="$(mutate "$i/init.sh" '# BL-333-MATRIX-SHIP' '  :')" || { CASE_DETAIL="init.sh edit did not land: $why"; return 1; }
  p="$(newtmp)/p"; mk_project "$p" "$i" edited
  run_sync "$p" "$i"
  CASE_DETAIL="rc=$RC"
  [ "$RC" = 0 ] && has "ships no tool matrix that this sync can read" && has "Framework sync complete"
}

FW_REAL="$(newtmp)/fw"
mk_fw "$FW_REAL" || { echo "  [FAIL] setup — could not build the framework mirror"; exit 1; }

echo "== BL-333 — --sync-framework and templates/tool-matrix/ =="
run_case() {   # run_case <case> <framework> <label>
  CASE_DETAIL=""
  if "$1" "$2"; then pass "${1#case_} $3"; else fail_ "${1#case_} $3" "$CASE_DETAIL"; fi
}
run_case case_P1 "$REPO_ROOT" "the sync's matrix set is derived from init.sh and names every shipped file"
run_case case_P2 "$REPO_ROOT" "running init.sh's own matrix lines lands exactly the sync's set"
run_case case_S1 "$FW_REAL" "a file missing from a vendored matrix is copied verbatim"
run_case case_S2 "$FW_REAL" "a locally edited matrix is reported with its diff and kept on a bare run"
run_case case_S3 "$FW_REAL" "a declared overwrite lands the framework's matrix (dated .bak) and check-versions enforces the new floor"
run_case case_S4 "$FW_REAL" "a declared sidecar writes common.json.new and leaves the project's copy"
run_case case_S5 "$FW_REAL" "--dry-run with every write-unlocking flag previews and writes nothing"
run_case case_S6 "$FW_REAL" "a second run changes nothing"
run_case case_S7 "$FW_REAL" "a project with no vendored matrix gets none; check-versions reads the framework's floor"
if [ "$(id -u)" = 0 ]; then
  fail_ S8 "running as root: a 555 directory stays writable, so this case cannot measure anything — run as a normal user"
else
  run_case case_S8 "$FW_REAL" "a copy that does not land is a [FAIL] and a non-zero exit"
fi
run_case case_S9 "$FW_REAL" "interactively, the apply prompt reads the operator's answer and every file is still visited"
run_case case_S10 "$FW_REAL" "a framework whose init.sh ships no matrix: a warning, and the sync still finishes"

# ── Mutation proofs ─────────────────────────────────────────────────────────
mutant() {   # mutant <id> <rel-file> <marker> <replacement> <killer-case> <what> [real-matrix]
  local id="$1" rel="$2" mark="$3" repl="$4" killer="$5" what="$6" m why
  m="$(newtmp)/mirror"
  if [ "${7:-}" = real-matrix ]; then mk_mirror "$REPO_ROOT" "$m"; else mk_fw "$m"; fi \
    || { fail_ "$id" "could not build a mirror"; return; }
  why="$(mutate "$m/$rel" "$mark" "$repl")" || { fail_ "$id" "mutant did not land: $why"; return; }
  CASE_DETAIL=""
  if "$killer" "$m"; then
    fail_ "$id" "$what — SURVIVED: ${killer#case_} still passes against the mutant ($CASE_DETAIL)"
  else
    pass "$id (MUTATION) — $what: killed by ${killer#case_} ($CASE_DETAIL)"
  fi
}

U=scripts/upgrade-project.sh
mutant M1 "$U" '# BL-333-MATRIX-SYNC' ':' case_S1 \
  "the sync never visits the tool matrix"
mutant M2 "$U" '# BL-333-MATRIX-VENDORED' ':' case_S7 \
  "a project with no vendored matrix is treated as one"
mutant M3 "$U" '# BL-333-MATRIX-DRYRUN' ':' case_S5 \
  "--dry-run copies a missing matrix file"
mutant M4 "$U" '# BL-333-MATRIX-WRITE-STATUS' ':' case_S8 \
  "a copy that did not land is reported as copied"
mutant M5 "$U" '# BL-333-MATRIX-DRIFT' '    cp "$src" "$dst"' case_S2 \
  "a drifted matrix is overwritten silently, the project's edits lost"
mutant M6 "$U" '# BL-333-MATRIX-DRIFT' ':' case_S3 \
  "a drifted matrix is neither reported nor applied"
mutant M7 "$U" '# BL-333-MATRIX-KEPT-NOTE' ':' case_S2 \
  "an unapplied drift no longer says which floors stay in force"
mutant M11 "$U" '# BL-333-MATRIX-EMPTY-SET' \
  '  shipped="$(soif_parse_shipped_tool_matrix "$ORCHESTRATOR_ROOT/init.sh" "$ORCHESTRATOR_ROOT")"' case_S10 \
  "an empty matrix set ends the whole sync under set -e"
mutant M8 scripts/lib/scaffold-shipped-set.sh '# BL-333-MATRIX-PARSER' \
  '        for f in "$fw_dir"/templates/tool-matrix/common.json; do' case_P1 \
  "the parser becomes a hand-kept list" real-matrix
mutant M9 init.sh '# BL-333-MATRIX-SHIP' \
  '  cp "$SCRIPT_DIR/templates/tool-matrix/"common.json "$SCRIPT_DIR/templates/tool-matrix/"web.json templates/tool-matrix/' case_P2 \
  "init.sh ships two files from one cp line the parser reads as one" real-matrix

# M10 is TWO edits — the list back on stdin is the read AND the redirect — so it
# is spelled out rather than routed through `mutant`.
m10() {
  local m why
  m="$(newtmp)/mirror"
  mk_fw "$m" || { fail_ M10 "could not build a mirror"; return; }
  why="$(mutate "$m/$U" '# BL-333-MATRIX-OWN-FD' '  while IFS= read -r rel; do')" || { fail_ M10 "mutant did not land: $why"; return; }
  why="$(mutate "$m/$U" '  done 3<<EOF' '  done <<EOF')" || { fail_ M10 "mutant did not land: $why"; return; }
  CASE_DETAIL=""
  if case_S9 "$m"; then
    fail_ M10 "the matrix list is read on stdin again — SURVIVED: S9 still passes against the mutant ($CASE_DETAIL)"
  else
    pass "M10 (MUTATION) — the matrix list is read on stdin again: killed by S9 ($CASE_DETAIL)"
  fi
}
m10

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
