#!/usr/bin/env bash
# tests/test-bl333-sync-tool-matrix.sh
#
# `## BL-333:` `upgrade-project.sh --sync-framework` never refreshed
# `templates/tool-matrix/`. init.sh copies the matrix into every project and
# `scripts/check-versions.sh` reads the project's copy first, so a floor raised
# upstream (gitleaks 8.18.0 -> 8.19.0, `7578fb9`) never reached a project that
# already existed.
#
# The fix, as Karl ruled it (2026-10-25, option A):
#   P  the sync's set is DERIVED from init.sh's own cp line
#      (`soif_parse_shipped_tool_matrix`); P2 executes that line to prove the
#      two agree, and fails on any other init.sh line that puts files there.
#   U  a copy byte-identical to a version in the framework's own git history of
#      that file is the framework's, untouched: a plain sync replaces it, keeps a
#      dated .bak and says "your copy was the framework's own version", so
#      check-versions enforces the new floor; `--dry-run` only previews it; a
#      second run changes nothing; a backup or a write that does not land is a
#      [FAIL] and a non-zero exit, with the project's bytes left in place.
#   H  a framework with no history this sync can read (not a git checkout of its
#      own, or one with no commits) cannot tell an untouched copy from an edited
#      one, so the copy is kept and the sync says that is why.
#   S  a copy the project edited keeps the reference documents' treatment
#      (`_bl099_process_doc`): reported with its diff and applied only when the
#      run declares it (`--apply-doc-updates sidecar|overwrite`, overwrite also
#      needing `--confirm-doc-overwrite` and keeping a dated .bak). A file missing
#      from a vendored matrix is copied verbatim; `--dry-run` writes nothing; a
#      second run changes nothing; a copy or an apply that does not land is a
#      [FAIL] and a non-zero exit, and the files after it are still visited; an
#      interactive apply reads the operator's answer, not the loop's list (S9); a
#      framework that ships no matrix is a warning, not an exit under `set -e`.
#   V  a project with NO vendored matrix (an adopted one) gets none, and the sync
#      names the copy check-versions reads through .claude/orchestrator-source.json:
#      this framework's (S7), another checkout's (V1), or none it can read (V2).
#   M  every BL-333 marker is mutation-proven against a mirror; the tree under
#      test is never edited. Each mutant asserts it LANDED by literal text, and
#      the marker-keeping ones (mutant_in / mutant_add) change one literal span.
#
# HERMETIC: the framework under test is a mirror with a two-file matrix written
# here (gitleaks only) and committed twice in the mirror's own git history —
# first at OLD_FLOOR, then raised to NEW_FLOOR — so check-versions runs one row.
# gitleaks, curl and brew are stubs on PATH, and so is cp in the cases that make
# a write lie; CDF_HOME and HOME point into the fixture; no network, no remote.
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
# web.json as the framework's first commit shipped it, and as it ships it now.
OLD_WEB='{"rev": 1, "tools": []}'
NEW_WEB='{"tools": []}'

STUBS="$TOPTMP/stubs"; mkdir -p "$STUBS"
printf '#!/bin/sh\n[ "${1:-}" = version ] && echo %s\nexit 0\n' "$STUB_VERSION" > "$STUBS/gitleaks"
printf '#!/bin/sh\nexit 1\n' > "$STUBS/curl"    # check-versions: "Network unavailable"
printf '#!/bin/sh\nexit 1\n' > "$STUBS/brew"    # no brew prefix ahead of the stubs
chmod +x "$STUBS/gitleaks" "$STUBS/curl" "$STUBS/brew"

mk_mirror() {
  mkdir -p "$2" && cp -Rp "$1/scripts" "$1/templates" "$1/init.sh" "$2/"
}

# matrix_common <floor>: a common.json holding only the REAL gitleaks row, at <floor>.
matrix_common() {
  jq --arg v "$1" '{tools: [.tools[] | select(.name == "gitleaks") | .min_version = $v]}' \
    "$REPO_ROOT/templates/tool-matrix/common.json"
}

# Replace a mirror's matrix with the suite's own two files, in a history of two
# commits: the first ships common.json at OLD_FLOOR and OLD_WEB, the second
# raises the floor to NEW_FLOOR and ships NEW_WEB. Only the matrix is tracked.
# A project holding the first commit's bytes holds versions the framework
# shipped and nobody edited.
use_test_matrix() {
  local fw="$1" m="$1/templates/tool-matrix"
  rm -f "$m/"*.json
  matrix_common "$OLD_FLOOR" > "$m/common.json" && printf '%s\n' "$OLD_WEB" > "$m/web.json" || return 1
  ( cd "$fw" && unset GITHUB_BASE_REF && git init -q && git config user.email t@t.local && git config user.name T \
      && git add templates/tool-matrix && git commit -q -m "matrix at $OLD_FLOOR" ) >/dev/null 2>&1 || return 1
  matrix_common "$NEW_FLOOR" > "$m/common.json" && printf '%s\n' "$NEW_WEB" > "$m/web.json" || return 1
  ( cd "$fw" && unset GITHUB_BASE_REF && git add templates/tool-matrix \
      && git commit -q -m "raise the floor to $NEW_FLOOR" ) >/dev/null 2>&1
}

mk_fw() {   # mk_fw <dst> [source-tree]: a mirror carrying the suite's matrix and its history
  mk_mirror "${2:-$REPO_ROOT}" "$1" && use_test_matrix "$1"
}

# mk_project <dir> <fw> <matrix-state> [source-dir]
#   current    — the framework's matrix, byte-identical
#   missing    — common.json current, web.json absent
#   untouched  — both files as the framework's FIRST commit shipped them
#   edited     — common.json at OLD_FLOOR with a tool the project added; web.json current
#   edited2    — edited, and web.json carries a key the project added
#   both       — edited + missing
#   none       — no templates/tool-matrix/ at all; .claude/orchestrator-source.json
#                names [source-dir] (default <fw>)
mk_project() {
  local p="$1" fw="$2" state="$3" srcdir="${4:-$2}" m="$1/templates/tool-matrix"
  mkdir -p "$p/.claude" "$p/scripts"
  printf '%s\n' '{"track":"light","deployment":"personal","poc_mode":null,"current_phase":1,"phases":{}}' > "$p/.claude/phase-state.json"
  printf '%s\n' '{"frameworkVersion":"1.0.0","host":"github","mode":"personal","deployment":"personal","poc_mode":null,"enforcement_level":"strict"}' > "$p/.claude/manifest.json"
  printf '%s\n' '{"context":{"track":"light","platform":"web","language":"python"}}' > "$p/.claude/tool-preferences.json"
  if [ "$state" = none ]; then
    jq -n --arg d "$srcdir" '{source_dir: $d}' > "$p/.claude/orchestrator-source.json"
  else
    mkdir -p "$m"
    cp "$fw/templates/tool-matrix/common.json" "$fw/templates/tool-matrix/web.json" "$m/"
    case "$state" in
      edited|edited2|both)
        jq --arg v "$OLD_FLOOR" '.tools |= (map(if .name == "gitleaks" then .min_version = $v else . end)
            + [{"category":"lint","name":"acme-lint","required":false,"phase":2,"tracks":["light"],
                "dev_os":["darwin","linux"],"platforms":["all"],"languages":["all"]}])' \
          "$fw/templates/tool-matrix/common.json" > "$m/common.json" ;;
      untouched)
        matrix_common "$OLD_FLOOR" > "$m/common.json" && printf '%s\n' "$OLD_WEB" > "$m/web.json" ;;
    esac
    case "$state" in edited2) printf '%s\n' '{"local": true, "tools": []}' > "$m/web.json" ;; esac
    case "$state" in missing|both) rm -f "$m/web.json" ;; esac
  fi
  ( cd "$p" && git init -q && git config user.email t@t.local && git config user.name T \
      && unset GITHUB_BASE_REF && git add -A && git commit -q -m init ) >/dev/null 2>&1
}

OUT=""; RC=0
run_sync() {   # run_sync <proj> <fw> [args...]
  local p="$1" fw="$2"; shift 2
  run_sync_path "" "$p" "$fw" "$@"
}

# run_sync_path <bin-dir|""> <proj> <fw> [args...]: run_sync with <bin-dir> first
# on the SYNC's PATH only — the suite's own file operations never see it.
run_sync_path() {
  local bin="$1" p="$2" fw="$3"; shift 3
  RC=0
  OUT="$( cd "$p" && unset GITHUB_BASE_REF; PATH="${bin:+$bin:}$PATH" HOME="$p/.home" CDF_HOME="$p/.no-such-cdf" SOIF_NONINTERACTIVE=1 \
      bash "$fw/scripts/upgrade-project.sh" --sync-framework "$@" </dev/null 2>&1 )" || RC=$?
}

# mk_cp_stub <bin-dir> <action> <src-glob> <dst-glob> [<action> <src-glob> <dst-glob> ...]
#   A `cp` for run_sync_path. A two-argument copy whose source and destination
#   match a rule's globs gets that rule's action instead of a copy:
#     silent  exit 0, write nothing       empty  write an empty file, exit 0
#     fail    write nothing, exit 1       real   the real cp (an exemption)
#   The first matching rule wins; anything unmatched is the real cp. Every action
#   but `real` logs to <bin-dir>/.hits, and each case asserts it fired, so a stub
#   that never matched cannot make a case pass. Globs, not absolute paths: the
#   sync's paths and the suite's may spell the same directory differently.
mk_cp_stub() {
  local bin="$1" real=""; shift
  real="$(command -v cp)"
  mkdir -p "$bin"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf 'REAL=%q\nHITS=%q\n' "$real" "$bin/.hits"
    printf '%s\n' 'src="${1:-}"; dst=""; for a in "$@"; do dst="$a"; done'
    printf '%s\n' 'if [ "$#" -eq 2 ]; then'
    while [ "$#" -ge 3 ]; do
      printf '  case "$src" in %s) case "$dst" in %s)\n' "$2" "$3"
      case "$1" in
        silent) printf '%s\n' '    printf "%s\n" "$dst" >> "$HITS"; exit 0 ;;' ;;
        empty)  printf '%s\n' '    : > "$dst"; printf "%s\n" "$dst" >> "$HITS"; exit 0 ;;' ;;
        fail)   printf '%s\n' '    printf "%s\n" "$dst" >> "$HITS"; exit 1 ;;' ;;
        real)   printf '%s\n' '    exec "$REAL" "$@" ;;' ;;
      esac
      printf '%s\n' '  esac ;; esac'
      shift 3
    done
    printf '%s\n' 'fi'
    printf '%s\n' 'exec "$REAL" "$@"'
  } > "$bin/cp"
  chmod +x "$bin/cp"
}
stub_state() { if [ -s "$1/.hits" ]; then echo fired; else echo NEVER-FIRED; fi; }

# check-versions' whole output in <proj>, and the floor it enforces there.
cv_out() {
  ( cd "$1" && HOME="$1/.home" PATH="$STUBS:$PATH" bash scripts/check-versions.sh </dev/null 2>&1 )
}
floor_line() {
  cv_out "$1" | command grep -F "gitleaks: $STUB_VERSION" | head -1
}

fingerprint() {   # every file under <dir>, path + bytes; "(absent)" when missing
  [ -d "$1" ] || { echo "(absent)"; return; }
  ( cd "$1" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do
      printf '%s %s\n' "$f" "$(cksum < "$f")"; done )
}

has() { printf '%s\n' "$OUT" | command grep -F -- "$1" >/dev/null; }

# Which of the sync's three verdicts on a differing matrix file the last run printed.
verdicts() {
  local v=""
  if has "your copy was the framework's own version"; then v="$v own-version"; fi
  if has "not a version the framework shipped"; then v="$v edited"; fi
  if has "has no git history this sync can read"; then v="$v no-history"; fi
  if has "but that clone is shallow"; then v="$v shallow"; fi
  printf '%s\n' "${v:- none}"
}

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

# ── P1: the sync's set is init.sh's matrix copy, derived, never a list ───────
case_P1() {
  local fw="$1" got want
  . "$fw/scripts/lib/scaffold-shipped-set.sh"
  got="$(soif_parse_shipped_tool_matrix "$fw/init.sh" "$fw")"
  want="$( cd "$fw" && ls templates/tool-matrix/*.json | LC_ALL=C sort )"
  CASE_DETAIL="parser=[$(printf '%s' "$got" | tr '\n' ' ')] framework=[$(printf '%s' "$want" | tr '\n' ' ')]"
  [ -n "$got" ] && [ "$got" = "$want" ]
}

# init_matrix_lines <framework-dir> — init.sh's mkdir + cp lines for the matrix,
# as written there. (Takes the directory: lint-no-live-remote-in-tests.sh reads
# a variable assigned an init.sh path as an init.sh run once it reaches bash -c.)
init_matrix_lines() {
  command grep -E '^[[:space:]]*(mkdir -p templates/tool-matrix|cp "\$SCRIPT_DIR/templates/tool-matrix/)' "$1/init.sh"
}

# matrix_stray_lines <framework-dir> — every executed init.sh line that names
# templates/tool-matrix and is NOT one of the three shapes this suite knows: the
# mkdir, the `# BL-333-MATRIX-SHIP` copy, a --matrix-dir read. A whole-line
# comment is not executed; anything else is a way of putting files there that
# the sync's parser does not read.
matrix_stray_lines() {
  command grep -n 'templates/tool-matrix' "$1/init.sh" \
    | command grep -vE '^[0-9]+:[[:space:]]*#' \
    | command grep -vE '^[0-9]+:[[:space:]]*mkdir -p templates/tool-matrix[[:space:]]*$' \
    | command grep -vE '# BL-333-MATRIX-SHIP$' \
    | command grep -vE '^[0-9]+:[[:space:]]*--matrix-dir "\$SCRIPT_DIR/templates/tool-matrix"([[:space:]]|$)'
}

# ── P2: running init.sh's own matrix lines lands exactly the parser's set, and
#        init.sh has no other line that writes there ──────────────────────────
case_P2() {
  local fw="$1" d="" lines="" got="" want="" stray=""
  stray="$(matrix_stray_lines "$fw")"
  [ -z "$stray" ] || { CASE_DETAIL="init.sh names templates/tool-matrix in a line this suite does not know: $(printf '%s' "$stray" | tr '\n' ' ')"; return 1; }
  d="$(newtmp)"
  lines="$(init_matrix_lines "$fw")"
  [ "$(printf '%s\n' "$lines" | command grep -c '^[[:space:]]*cp ')" -ge 1 ] \
    || { CASE_DETAIL="init.sh has no tool-matrix cp line to execute"; return 1; }
  ( cd "$d" && SCRIPT_DIR="$fw" bash -c "$lines" ) >/dev/null 2>&1 || { CASE_DETAIL="the extracted matrix lines failed"; return 1; }
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
  local fw="$1" p="" before="" fl=""
  p="$(newtmp)/p"; mk_project "$p" "$fw" edited
  before="$(fingerprint "$p/templates/tool-matrix")"
  run_sync "$p" "$fw"
  fl="$(floor_line "$p")"
  CASE_DETAIL="rc=$RC check-versions='$fl'"
  [ "$RC" = 0 ] || return 1
  [ "$(fingerprint "$p/templates/tool-matrix")" = "$before" ] || { CASE_DETAIL="$CASE_DETAIL; the project's matrix CHANGED"; return 1; }
  has "templates/tool-matrix/common.json: not a version the framework shipped" || { CASE_DETAIL="$CASE_DETAIL; no line saying why it was kept"; return 1; }
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

# ── S6: a second run changes nothing, and no longer says a floor is kept ─────
case_S6() {
  local fw="$1" p="" after1=""
  p="$(newtmp)/p"; mk_project "$p" "$fw" both
  run_sync "$p" "$fw" --apply-doc-updates overwrite --confirm-doc-overwrite
  [ "$RC" = 0 ] || { CASE_DETAIL="first run rc=$RC"; return 1; }
  after1="$(fingerprint "$p/templates/tool-matrix")"
  run_sync "$p" "$fw" --apply-doc-updates overwrite --confirm-doc-overwrite
  CASE_DETAIL="second run rc=$RC"
  [ "$RC" = 0 ] && [ "$(fingerprint "$p/templates/tool-matrix")" = "$after1" ] \
    && has "templates/tool-matrix/common.json: up to date" && has "templates/tool-matrix/web.json: up to date" \
    || return 1
  ! has "until it is applied" || { CASE_DETAIL="$CASE_DETAIL; an up-to-date matrix is still said to keep its old floors"; return 1; }
}

# ── S7: no vendored matrix (adopted) -> none is created; the sync names the
#        framework's own copy, which is what check-versions enforces ─────────
case_S7() {
  local fw="$1" p="" fl=""
  p="$(newtmp)/p"; mk_project "$p" "$fw" none
  run_sync "$p" "$fw"
  fl="$(floor_line "$p")"
  CASE_DETAIL="rc=$RC matrix=$([ -e "$p/templates/tool-matrix" ] && echo CREATED || echo absent) check-versions='$fl'"
  [ "$RC" = 0 ] && [ ! -e "$p/templates/tool-matrix" ] && has "no templates/tool-matrix/ in this project" \
    && has "check-versions.sh reads this framework's own copy" \
    && printf '%s\n' "$fl" | command grep -F "(min: $NEW_FLOOR) — BELOW MINIMUM" >/dev/null
}

# ── V1: no vendored matrix, and .claude/orchestrator-source.json names ANOTHER
#        checkout: the sync says so, and that checkout's floor is the one
#        check-versions enforces ─────────────────────────────────────────────
case_V1() {
  local fw="$1" o="" p="" fl=""
  o="$(newtmp)/other"; mk_mirror "$fw" "$o" || { CASE_DETAIL="mirror"; return 1; }
  matrix_common "$OLD_FLOOR" > "$o/templates/tool-matrix/common.json" || { CASE_DETAIL="other matrix"; return 1; }
  p="$(newtmp)/p"; mk_project "$p" "$fw" none "$o"
  run_sync "$p" "$fw"
  fl="$(floor_line "$p")"
  CASE_DETAIL="rc=$RC matrix=$([ -e "$p/templates/tool-matrix" ] && echo CREATED || echo absent) check-versions='$fl'"
  [ "$RC" = 0 ] && [ ! -e "$p/templates/tool-matrix" ] \
    && has "which is NOT the framework this sync runs from" && ! has "reads this framework's own copy" \
    && printf '%s\n' "$fl" | command grep -F "(min: $OLD_FLOOR)" >/dev/null
}

# ── V2: no vendored matrix, and source_dir names a directory with no matrix:
#        the sync says check-versions has nothing to read, and it has not ────
case_V2() {
  local fw="$1" e="" p="" cv=""
  e="$(newtmp)/no-matrix"; mkdir -p "$e"
  p="$(newtmp)/p"; mk_project "$p" "$fw" none "$e"
  run_sync "$p" "$fw"
  cv="$(cv_out "$p")"   # captured: check-versions exits 1 here, and pipefail would fail a pipe on that
  CASE_DETAIL="rc=$RC matrix=$([ -e "$p/templates/tool-matrix" ] && echo CREATED || echo absent) check-versions='$(printf '%s\n' "$cv" | command grep -F 'Tool matrix' | head -1)'"
  [ "$RC" = 0 ] && [ ! -e "$p/templates/tool-matrix" ] \
    && has "names no framework copy check-versions.sh can read" && ! has "check-versions.sh reads " \
    && printf '%s\n' "$cv" | command grep -F "Tool matrix not found" >/dev/null
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

# ── S11: a copy cp reports as done but never wrote is caught by re-reading the
#         bytes: cp's exit status alone would call it copied ───────────────────
case_S11() {
  local fw="$1" p="" bin=""
  p="$(newtmp)/p"; mk_project "$p" "$fw" missing
  bin="$(newtmp)/bin"; mk_cp_stub "$bin" silent '*' '*/templates/tool-matrix/web.json'
  run_sync_path "$bin" "$p" "$fw"
  CASE_DETAIL="rc=$RC stub=$(stub_state "$bin")"
  [ -s "$bin/.hits" ] && [ "$RC" != 0 ] && has "FAILED to copy templates/tool-matrix/web.json" \
    && ! has "templates/tool-matrix/web.json: copied"
}

# ── S12: two edited files whose declared sidecars cannot be written: BOTH are
#         reported, the sync still reaches its pin step and its summary, rc 1 ─
case_S12() {
  local fw="$1" p="" before=""
  p="$(newtmp)/p"; mk_project "$p" "$fw" edited2
  before="$(fingerprint "$p/templates/tool-matrix")"
  chmod 555 "$p/templates/tool-matrix"
  run_sync "$p" "$fw" --apply-doc-updates sidecar
  chmod 755 "$p/templates/tool-matrix"
  CASE_DETAIL="rc=$RC"
  [ "$RC" = 1 ] || return 1
  [ "$(fingerprint "$p/templates/tool-matrix")" = "$before" ] || { CASE_DETAIL="$CASE_DETAIL; the matrix CHANGED"; return 1; }
  has "templates/tool-matrix/common.json.new for templates/tool-matrix/common.json" \
    && has "templates/tool-matrix/web.json.new for templates/tool-matrix/web.json" \
    || { CASE_DETAIL="$CASE_DETAIL; not one FAILED line per file"; return 1; }
  has "[STEP] Framework pin" && has "or tool-matrix files could NOT be applied" \
    || { CASE_DETAIL="$CASE_DETAIL; the sync stopped before its pin step or its summary"; return 1; }
}

# ── U1: an untouched old copy is replaced on a plain non-interactive sync: a
#        dated .bak of it, the line saying why, and the new floor enforced ────
case_U1() {
  local fw="$1" p="" m="" old="" at="" fl=""
  p="$(newtmp)/p"; mk_project "$p" "$fw" untouched; m="$p/templates/tool-matrix"
  old="$(cksum < "$m/common.json")"
  at="$(git -C "$fw" rev-parse --short HEAD 2>/dev/null)"
  run_sync "$p" "$fw"
  fl="$(floor_line "$p")"
  CASE_DETAIL="rc=$RC check-versions='$fl'"
  [ "$RC" = 0 ] || return 1
  cmp -s "$fw/templates/tool-matrix/common.json" "$m/common.json" && cmp -s "$fw/templates/tool-matrix/web.json" "$m/web.json" \
    || { CASE_DETAIL="$CASE_DETAIL; the matrix is not the framework's"; return 1; }
  [ -f "$m/common.json.bak.$TODAY" ] && [ "$(cksum < "$m/common.json.bak.$TODAY")" = "$old" ] \
    || { CASE_DETAIL="$CASE_DETAIL; no dated .bak holding the old bytes"; return 1; }
  has "templates/tool-matrix/common.json: updated — your copy was the framework's own version (found in its git history at $at)" \
    && has "templates/tool-matrix/web.json: updated — your copy was the framework's own version" \
    || { CASE_DETAIL="$CASE_DETAIL; no 'framework's own version' line naming $at"; return 1; }
  ! has "until it is applied" || { CASE_DETAIL="$CASE_DETAIL; still says the old floor stays in force"; return 1; }
  printf '%s\n' "$fl" | command grep -F "(min: $NEW_FLOOR) — BELOW MINIMUM" >/dev/null
}

# ── U2: --dry-run previews the update and writes nothing ─────────────────────
case_U2() {
  local fw="$1" p="" before=""
  p="$(newtmp)/p"; mk_project "$p" "$fw" untouched
  before="$(fingerprint "$p/templates/tool-matrix")"
  run_sync "$p" "$fw" --dry-run
  CASE_DETAIL="rc=$RC"
  [ "$RC" = 0 ] || return 1
  [ "$(fingerprint "$p/templates/tool-matrix")" = "$before" ] || { CASE_DETAIL="$CASE_DETAIL; --dry-run WROTE into the matrix"; return 1; }
  has "[would update] templates/tool-matrix/common.json — your copy was the framework's own version" \
    || { CASE_DETAIL="$CASE_DETAIL; no would-update line"; return 1; }
}

# ── U3: after the update, a second run changes nothing ───────────────────────
case_U3() {
  local fw="$1" p="" after1=""
  p="$(newtmp)/p"; mk_project "$p" "$fw" untouched
  run_sync "$p" "$fw"
  [ "$RC" = 0 ] && has "templates/tool-matrix/common.json: updated" || { CASE_DETAIL="first run rc=$RC, no update"; return 1; }
  after1="$(fingerprint "$p/templates/tool-matrix")"
  run_sync "$p" "$fw"
  CASE_DETAIL="second run rc=$RC"
  [ "$RC" = 0 ] && [ "$(fingerprint "$p/templates/tool-matrix")" = "$after1" ] \
    && has "templates/tool-matrix/common.json: up to date" && has "templates/tool-matrix/web.json: up to date" \
    && ! has "updated — your copy" && ! has "until it is applied"
}

# ── U4: an unwritable matrix directory: no verified backup, so BOTH updates are
#        refused, nothing changes, and the sync still reaches its pin step and
#        its summary, rc 1 ─────────────────────────────────────────────────────
case_U4() {
  local fw="$1" p="" before=""
  p="$(newtmp)/p"; mk_project "$p" "$fw" untouched
  before="$(fingerprint "$p/templates/tool-matrix")"
  chmod 555 "$p/templates/tool-matrix"
  run_sync "$p" "$fw"
  chmod 755 "$p/templates/tool-matrix"
  CASE_DETAIL="rc=$RC"
  [ "$RC" = 1 ] || return 1
  [ "$(fingerprint "$p/templates/tool-matrix")" = "$before" ] || { CASE_DETAIL="$CASE_DETAIL; the matrix CHANGED with no backup"; return 1; }
  has "REFUSING to update templates/tool-matrix/common.json" && has "REFUSING to update templates/tool-matrix/web.json" \
    || { CASE_DETAIL="$CASE_DETAIL; not one REFUSING line per file"; return 1; }
  has "[STEP] Framework pin" && has "or tool-matrix files could NOT be applied" \
    || { CASE_DETAIL="$CASE_DETAIL; the sync stopped before its pin step or its summary"; return 1; }
}

# ── U5: a backup cp reports as done but left empty is caught by re-reading it:
#        the update is refused and the copy untouched ─────────────────────────
case_U5() {
  local fw="$1" p="" m="" old="" bin=""
  p="$(newtmp)/p"; mk_project "$p" "$fw" untouched; m="$p/templates/tool-matrix"
  old="$(cksum < "$m/common.json")"
  bin="$(newtmp)/bin"; mk_cp_stub "$bin" empty '*' '*/templates/tool-matrix/common.json.bak.*'
  run_sync_path "$bin" "$p" "$fw"
  CASE_DETAIL="rc=$RC stub=$(stub_state "$bin")"
  [ -s "$bin/.hits" ] && [ "$RC" = 1 ] || return 1
  has "REFUSING to update templates/tool-matrix/common.json" || { CASE_DETAIL="$CASE_DETAIL; no REFUSING line"; return 1; }
  ! has "templates/tool-matrix/common.json: updated" || { CASE_DETAIL="$CASE_DETAIL; reported as updated"; return 1; }
  [ "$(cksum < "$m/common.json")" = "$old" ] || { CASE_DETAIL="$CASE_DETAIL; common.json was replaced with no verified backup"; return 1; }
}

# ── U6: an update cp reports as done but left the file empty: caught by
#        re-reading it, the project's bytes put back, the backup kept ─────────
case_U6() {
  local fw="$1" p="" m="" old="" bin=""
  p="$(newtmp)/p"; mk_project "$p" "$fw" untouched; m="$p/templates/tool-matrix"
  old="$(cksum < "$m/common.json")"
  bin="$(newtmp)/bin"
  mk_cp_stub "$bin" real '*.bak.*' '*/templates/tool-matrix/common.json' empty '*' '*/templates/tool-matrix/common.json'
  run_sync_path "$bin" "$p" "$fw"
  CASE_DETAIL="rc=$RC stub=$(stub_state "$bin")"
  [ -s "$bin/.hits" ] && [ "$RC" = 1 ] || return 1
  has "FAILED to update templates/tool-matrix/common.json" && has "your copy is back as it was" \
    || { CASE_DETAIL="$CASE_DETAIL; no FAILED line saying the copy is back"; return 1; }
  [ "$(cksum < "$m/common.json")" = "$old" ] || { CASE_DETAIL="$CASE_DETAIL; common.json is not the project's bytes"; return 1; }
  [ "$(cksum < "$m/common.json.bak.$TODAY")" = "$old" ] || { CASE_DETAIL="$CASE_DETAIL; the backup was not kept"; return 1; }
}

# ── U7: the update and the putting-back both fail: the sync says the copy is
#        NOT back, and where its bytes are ─────────────────────────────────────
case_U7() {
  local fw="$1" p="" m="" old="" bin=""
  p="$(newtmp)/p"; mk_project "$p" "$fw" untouched; m="$p/templates/tool-matrix"
  old="$(cksum < "$m/common.json")"
  bin="$(newtmp)/bin"
  mk_cp_stub "$bin" fail '*.bak.*' '*/templates/tool-matrix/common.json' empty '*' '*/templates/tool-matrix/common.json'
  run_sync_path "$bin" "$p" "$fw"
  CASE_DETAIL="rc=$RC stub=$(stub_state "$bin")"
  [ -s "$bin/.hits" ] && [ "$RC" = 1 ] || return 1
  has "putting your copy back failed too" && has "Restore it by hand" && ! has "your copy is back as it was" \
    || { CASE_DETAIL="$CASE_DETAIL; the line does not say the copy is not back"; return 1; }
  [ "$(cksum < "$m/common.json.bak.$TODAY")" = "$old" ] || { CASE_DETAIL="$CASE_DETAIL; the backup does not hold the project's bytes"; return 1; }
}

# ── H1: a framework that is not a git checkout has no history to compare an old
#        copy against: it is kept, and the sync says that is why ────────────
case_H1() {
  local fw="$1" i="" p="" before="" fl=""
  i="$(newtmp)/fw"; mk_mirror "$fw" "$i" || { CASE_DETAIL="mirror"; return 1; }
  p="$(newtmp)/p"; mk_project "$p" "$i" untouched
  before="$(fingerprint "$p/templates/tool-matrix")"
  run_sync "$p" "$i"
  fl="$(floor_line "$p")"
  CASE_DETAIL="rc=$RC verdicts:$(verdicts) check-versions='$fl'"
  [ "$RC" = 0 ] || return 1
  [ "$(fingerprint "$p/templates/tool-matrix")" = "$before" ] || { CASE_DETAIL="$CASE_DETAIL; the matrix CHANGED"; return 1; }
  has "templates/tool-matrix/common.json: the framework at" && has "has no git history this sync can read" \
    || { CASE_DETAIL="$CASE_DETAIL; no line saying the history cannot be read"; return 1; }
  ! has "your copy was the framework's own version" && ! has "not a version the framework shipped" \
    || { CASE_DETAIL="$CASE_DETAIL; a verdict the sync had no history to reach"; return 1; }
  has "until it is applied" && printf '%s\n' "$fl" | command grep -F "(min: $OLD_FLOOR)" >/dev/null
}

# ── H2: a framework inside some OTHER repository is not a git checkout of its
#        own: that repository's history is not the framework's ──────────────
case_H2() {
  local fw="$1" e="" i="" p=""
  e="$(newtmp)/outer"; mkdir -p "$e"
  ( cd "$e" && unset GITHUB_BASE_REF && git init -q && git config user.email t@t.local && git config user.name T \
      && printf 'outer\n' > README && git add README && git commit -q -m outer ) >/dev/null 2>&1 \
    || { CASE_DETAIL="outer repository"; return 1; }
  i="$e/fw"; mk_mirror "$fw" "$i" || { CASE_DETAIL="mirror"; return 1; }
  p="$(newtmp)/p"; mk_project "$p" "$i" untouched
  run_sync "$p" "$i"
  CASE_DETAIL="rc=$RC verdicts:$(verdicts)"
  [ "$RC" = 0 ] && has "has no git history this sync can read" && ! has "not a version the framework shipped" \
    && ! has "your copy was the framework's own version"
}

# ── H3: a framework checkout with no commits: git cannot read its log, and
#        that is not the same as finding no such version ─────────────────────
case_H3() {
  local fw="$1" i="" p=""
  i="$(newtmp)/fw"; mk_mirror "$fw" "$i" || { CASE_DETAIL="mirror"; return 1; }
  ( cd "$i" && git init -q ) >/dev/null 2>&1 || { CASE_DETAIL="git init"; return 1; }
  p="$(newtmp)/p"; mk_project "$p" "$i" untouched
  run_sync "$p" "$i"
  CASE_DETAIL="rc=$RC verdicts:$(verdicts)"
  [ "$RC" = 0 ] && has "has no git history this sync can read" && ! has "not a version the framework shipped" \
    && ! has "your copy was the framework's own version"
}

# ── H4: a SHALLOW clone whose history stops before the copy's version cannot
#        tell either: the copy is kept, and the sync says why — never "not a
#        version the framework shipped" ─────────────────────────────────────
case_H4() {
  local fw="$1" i="" p="" before=""
  i="$(newtmp)/fw"
  git clone -q --depth 1 "file://$fw" "$i" >/dev/null 2>&1 || { CASE_DETAIL="shallow clone"; return 1; }
  # A clone's exit code is no proof it checked anything out (`# BL-234-FIXTURE-CLONE-RECEIPT`).
  [ "$(git -C "$i" rev-parse --is-shallow-repository 2>/dev/null)" = true ] && [ -f "$i/templates/tool-matrix/common.json" ] \
    || { CASE_DETAIL="the clone is not a shallow checkout of the matrix"; return 1; }
  mk_mirror "$fw" "$i" || { CASE_DETAIL="mirror"; return 1; }
  p="$(newtmp)/p"; mk_project "$p" "$i" untouched
  before="$(fingerprint "$p/templates/tool-matrix")"
  run_sync "$p" "$i"
  CASE_DETAIL="rc=$RC verdicts:$(verdicts)"
  [ "$RC" = 0 ] && [ "$(fingerprint "$p/templates/tool-matrix")" = "$before" ] \
    && has "templates/tool-matrix/common.json: not in the framework clone's history, but that clone is shallow" \
    && ! has "not a version the framework shipped" && ! has "your copy was the framework's own version"
}

FW_REAL="$(newtmp)/fw"
mk_fw "$FW_REAL" || { echo "  [FAIL] setup — could not build the framework mirror"; exit 1; }

echo "== BL-333 — --sync-framework and templates/tool-matrix/ =="
run_case() {   # run_case <case> <framework> <label>
  CASE_DETAIL=""
  if "$1" "$2"; then pass "${1#case_} $3"; else fail_ "${1#case_} $3" "$CASE_DETAIL"; fi
}
# A 555 directory stays writable for root, so the cases built on one measure nothing there.
run_case_unprivileged() {   # run_case_unprivileged <case> <framework> <label>
  if [ "$(id -u)" = 0 ]; then
    fail_ "${1#case_}" "running as root: a 555 directory stays writable, so this case cannot measure anything — run as a normal user"
  else
    run_case "$@"
  fi
}
run_case case_P1 "$REPO_ROOT" "the sync's matrix set is derived from init.sh and names every shipped file"
run_case case_P2 "$REPO_ROOT" "running init.sh's own matrix lines lands exactly the sync's set, and no other line writes there"
run_case case_S1 "$FW_REAL" "a file missing from a vendored matrix is copied verbatim"
run_case case_S2 "$FW_REAL" "a locally edited matrix is reported with its diff and why, and kept on a bare run"
run_case case_S3 "$FW_REAL" "a declared overwrite lands the framework's matrix (dated .bak) and check-versions enforces the new floor"
run_case case_S4 "$FW_REAL" "a declared sidecar writes common.json.new and leaves the project's copy"
run_case case_S5 "$FW_REAL" "--dry-run with every write-unlocking flag previews and writes nothing"
run_case case_S6 "$FW_REAL" "a second run changes nothing and no longer says a floor is kept"
run_case case_S7 "$FW_REAL" "a project with no vendored matrix gets none; the sync names the framework's own copy, whose floor check-versions enforces"
run_case case_V1 "$FW_REAL" "no vendored matrix and source_dir names another checkout: the sync says so, and that floor is enforced"
run_case case_V2 "$FW_REAL" "no vendored matrix and source_dir has none: the sync says check-versions has nothing to read"
run_case_unprivileged case_S8 "$FW_REAL" "a copy that does not land is a [FAIL] and a non-zero exit"
run_case case_S9 "$FW_REAL" "interactively, the apply prompt reads the operator's answer and every file is still visited"
run_case case_S10 "$FW_REAL" "a framework whose init.sh ships no matrix: a warning, and the sync still finishes"
run_case case_S11 "$FW_REAL" "a copy cp calls done but never wrote is a [FAIL] and a non-zero exit"
run_case_unprivileged case_S12 "$FW_REAL" "two declared sidecars that cannot be written: both reported, the sync reaches its pin and summary, rc 1"
run_case case_U1 "$FW_REAL" "an untouched old copy is replaced on a plain sync (dated .bak, says why) and check-versions enforces the new floor"
run_case case_U2 "$FW_REAL" "--dry-run previews the update and writes nothing"
run_case case_U3 "$FW_REAL" "after the update, a second run changes nothing"
run_case_unprivileged case_U4 "$FW_REAL" "no verified backup: both updates refused, nothing changed, the sync reaches its pin and summary, rc 1"
run_case case_U5 "$FW_REAL" "a backup cp calls done but left empty: the update is refused, the copy untouched"
run_case case_U6 "$FW_REAL" "an update cp calls done but left empty: a [FAIL], the copy put back, the backup kept"
run_case case_U7 "$FW_REAL" "the update and the putting-back both fail: the sync says the copy is not back, and where it is"
run_case case_H1 "$FW_REAL" "a framework that is not a git checkout: the old copy is kept, and the sync says why"
run_case case_H2 "$FW_REAL" "a framework inside another repository: that history is not the framework's"
run_case case_H3 "$FW_REAL" "a framework checkout with no commits: its log cannot be read, so the copy is kept, and the sync says why"
run_case case_H4 "$FW_REAL" "a shallow clone whose history stops before the copy's version: kept, and the sync says why"

# ── Mutation proofs ─────────────────────────────────────────────────────────
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
mutant M11 "$U" '# BL-333-MATRIX-EMPTY-SET' \
  '  shipped="$(soif_parse_shipped_tool_matrix "$ORCHESTRATOR_ROOT/init.sh" "$ORCHESTRATOR_ROOT")"' case_S10 \
  "an empty matrix set ends the whole sync under set -e"
# A copy the project edited: the reference documents' treatment.
mutant M5 "$U" '# BL-333-MATRIX-DRIFT' '    cp "$src" "$dst"' case_S2 \
  "a drifted matrix is overwritten silently, the project's edits lost"
mutant M6 "$U" '# BL-333-MATRIX-DRIFT' ':' case_S3 \
  "a drifted matrix is neither reported nor applied"
mutant_in M13 "$U" '# BL-333-MATRIX-DRIFT' ' || DOC_APPLY_FAILED=true' '' case_S12 \
  "a failed apply ends the sync under set -e, the files after it never visited"
mutant M7 "$U" '# BL-333-MATRIX-KEPT-NOTE' ':' case_S2 \
  "an unapplied drift no longer says which floors stay in force"
mutant_in M14 "$U" '# BL-333-MATRIX-KEPT-NOTE' 'if ! cmp -s "$src" "$dst"; then ' 'if true; then ' case_S6 \
  "an up-to-date matrix is still said to keep its old floors"
# An untouched copy: found in the framework's history, and replaced.
mutant M15 "$U" '# BL-333-MATRIX-DIFFERS' '    if true; then' case_U3 \
  "the history is consulted for a file already up to date, and it is updated again"
mutant M16 "$U" '# BL-333-MATRIX-LOOKUP' '      hrc=0; at=""' case_S2 \
  "every drifted copy is taken for an untouched one, the project's edits replaced"
mutant M17 "$U" '# BL-333-MATRIX-UNTOUCHED' ':' case_U1 \
  "an untouched old copy is reported and kept, its old floor still in force"
mutant_in M18 "$U" '# BL-333-MATRIX-UNTOUCHED' ' || DOC_APPLY_FAILED=true' '' case_U4 \
  "a failed update ends the sync under set -e, the files after it never visited"
mutant M19 "$U" '# BL-333-MATRIX-WHY' ':' case_S2 \
  "a kept copy no longer says why it was not updated"
mutant_in M20 "$U" '# BL-333-MATRIX-WHY' 'if [ "$hrc" -eq 1 ]; then' 'if [ "$hrc" -ne 1 ]; then' case_H1 \
  "a framework with no history is reported as a copy you edited"
mutant M21 "$U" '# BL-333-MATRIX-HISTORY-ROOT' ':' case_H2 \
  "a framework inside some other repository reads that repository's history as its own"
mutant_in M22 "$U" '# BL-333-MATRIX-HISTORY-ROOT' '[ "$top" -ef "$ORCHESTRATOR_ROOT" ]' 'true' case_H2 \
  "any enclosing repository counts as the framework's history"
mutant_in M23 "$U" '# BL-333-MATRIX-HISTORY-READ' ' || return 2' '' case_H3 \
  "a log git cannot read is taken for a history with no such version"
mutant M24 "$U" '# BL-333-MATRIX-HISTORY-MISS' ':' case_S2 \
  "a copy with no match in the history is taken for an untouched one"
mutant_in M46 "$U" '# BL-333-MATRIX-HISTORY-MISS' \
  '[ "$(git -C "$ORCHESTRATOR_ROOT" rev-parse --is-shallow-repository 2>/dev/null)" = true ] && return 3; ' '' case_H4 \
  "a shallow clone's missing history is taken for proof the copy was edited"
mutant_in M47 "$U" '# BL-333-MATRIX-WHY' 'elif [ "$hrc" -eq 3 ]; then' 'elif false; then' case_H4 \
  "a shallow clone is reported as no history at all, with no way to fix it named"
mutant M25 "$U" '# BL-333-MATRIX-HISTORY-SAY' ':' case_U1 \
  "the update no longer names the commit it matched"
mutant M26 "$U" '# BL-333-UPDATE-BAK' '  bak="$dst.bak"' case_U1 \
  "the backup loses its date"
mutant M27 "$U" '# BL-333-UPDATE-DRYRUN' ':' case_U2 \
  "--dry-run replaces an untouched copy"
mutant M28 "$U" '# BL-333-UPDATE-COPY-OLD' ':' case_U1 \
  "the backup is never written, so every update is refused"
mutant M29 "$U" '# BL-333-UPDATE-VERIFY-BAK' ':' case_U4 \
  "an untouched copy is replaced with no verified backup"
mutant_in M30 "$U" '# BL-333-UPDATE-VERIFY-BAK' '_bl099_write_ok "$rc" "$dst" "$bak"' '[ "$rc" -eq 0 ]' case_U5 \
  "a backup is judged by cp's exit status alone, the bytes never re-read"
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
