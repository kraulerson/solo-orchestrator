#!/usr/bin/env bash
# tests/test-bl333-sync-tool-matrix.sh
#
# `## BL-333:` `upgrade-project.sh --sync-framework` never refreshed
# `templates/tool-matrix/`. init.sh copies the matrix into every project and
# `scripts/check-versions.sh` reads the project's copy first, so a floor raised
# upstream (gitleaks 8.18.0 -> 8.19.0, `7578fb9`) never reached a project that
# already existed.
#
# The fix, as Karl ruled it (2026-10-25, option A, and 2026-10-26 on R-BL333-10):
#   P  the sync's set is DERIVED from init.sh's own cp line
#      (`soif_parse_shipped_tool_matrix`); P2 executes that line to prove the
#      two agree, and fails on any other init.sh line that puts files there.
#   U  a copy whose bytes equal ANY version of that file in the framework's own
#      git history is replaced on every sync — a copy the project restored on
#      purpose, its own .bak included (U8) — with a dated .bak and a line naming
#      the commit that has those bytes, so check-versions enforces the new floor;
#      `--dry-run` only previews it; a second run changes nothing; bytes another
#      shipped FILE had are not a match (U9); a backup or a write that does not
#      land is a [FAIL] and a non-zero exit, with the project's bytes in place.
#   H  a framework with no history this sync can read (not a git checkout of its
#      own, or one with no commits), or a shallow clone that does not reach the
#      copy's version, cannot decide, so the copy is kept and the sync says why;
#      an exported GIT_DIR does not swap the project's history in (G1).
#   S  a copy whose bytes match no shipped version is the project's own, and keeps
#      the reference documents' treatment (`_bl099_process_doc`): reported with
#      its diff and applied only when the run declares it (`--apply-doc-updates
#      sidecar|overwrite`, overwrite also needing `--confirm-doc-overwrite` and
#      keeping a dated .bak). A file missing from a vendored matrix is copied
#      verbatim; `--dry-run` writes nothing; a second run changes nothing; a copy
#      or an apply that does not land is a [FAIL] and a non-zero exit, leaves no
#      fragment (S13), and the files after it are still visited; an interactive
#      apply reads the operator's answer, not the loop's list (S9); a framework
#      that ships no matrix is a warning, not an exit under `set -e`; a failed
#      script copy fails the run while the matrix step still runs (S14).
#   L  a matrix file that is a symbolic link, dangling or live, is never written
#      through: a [FAIL] naming it, rc 1, and nothing lands outside (L1, L2).
#   V  a project with NO vendored matrix (an adopted one) gets none, and the sync
#      names the copy check-versions reads through .claude/orchestrator-source.json:
#      this framework's (S7), another checkout's (V1), or none it can read (V2).
#
# THE MUTATION PROOFS ARE tests/test-bl333-sync-tool-matrix-mutants.sh, which
# sources this file for its fixtures and cases (`# BL-333-MUTANTS-SPLIT`), so the
# two run on separate unit-shard legs (R-BL333-14). Run directly, this file runs
# every case and no mutant.
#
# HERMETIC: the framework under test is a mirror with a two-file matrix written
# here (gitleaks only) and committed twice in the mirror's own git history —
# first at OLD_FLOOR, then raised to NEW_FLOOR — so check-versions runs one row.
# gitleaks, curl and brew are stubs on PATH, and so is cp in the cases that make
# a write lie; CDF_HOME and HOME point into the fixture; no network, no remote.
# init.sh is READ (P2 runs its two matrix lines, nothing else) and never executed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
#   old-shipped — both files as the framework's FIRST commit shipped them
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
      old-shipped)
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
#     prefix  write the source's first 5 bytes, exit 1 (a disk that fills mid-copy)
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
        prefix) printf '%s\n' '    head -c 5 "$src" > "$dst"; printf "%s\n" "$dst" >> "$HITS"; exit 1 ;;' ;;
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
  if has "a version the framework shipped (committed in"; then v="$v shipped"; fi
  if has "match no version the framework shipped"; then v="$v own"; fi
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
  has "templates/tool-matrix/common.json: its bytes match no version the framework shipped" || { CASE_DETAIL="$CASE_DETAIL; no line saying why it was kept"; return 1; }
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

# ── U1: an old shipped copy is replaced on a plain non-interactive sync: a
#        dated .bak of it, the line saying why — naming the commit that HAS those
#        bytes, the fixture's first, not the one that replaced them — how to keep
#        an older floor, and the new floor enforced ────────────────────────────
case_U1() {
  local fw="$1" p="" m="" old="" at="" fl=""
  p="$(newtmp)/p"; mk_project "$p" "$fw" old-shipped; m="$p/templates/tool-matrix"
  old="$(cksum < "$m/common.json")"
  at="$(git -C "$fw" rev-parse --short HEAD~1 2>/dev/null)"
  run_sync "$p" "$fw"
  fl="$(floor_line "$p")"
  CASE_DETAIL="rc=$RC check-versions='$fl'"
  [ "$RC" = 0 ] || return 1
  cmp -s "$fw/templates/tool-matrix/common.json" "$m/common.json" && cmp -s "$fw/templates/tool-matrix/web.json" "$m/web.json" \
    || { CASE_DETAIL="$CASE_DETAIL; the matrix is not the framework's"; return 1; }
  [ -f "$m/common.json.bak.$TODAY" ] && [ "$(cksum < "$m/common.json.bak.$TODAY")" = "$old" ] \
    || { CASE_DETAIL="$CASE_DETAIL; no dated .bak holding the old bytes"; return 1; }
  has "templates/tool-matrix/common.json: updated (backup: " \
    && has "its bytes matched a version the framework shipped (committed in $at)" \
    && has "templates/tool-matrix/web.json: updated (backup: " \
    || { CASE_DETAIL="$CASE_DETAIL; no 'updated' line naming $at, the commit with those bytes"; return 1; }
  has "every sync replaces such a copy, even one restored on purpose" \
    && has "To keep an older floor, change the file so its bytes match no shipped version" \
    || { CASE_DETAIL="$CASE_DETAIL; the line does not say every sync does this, or how to keep an older floor"; return 1; }
  ! has "until it is applied" || { CASE_DETAIL="$CASE_DETAIL; still says the old floor stays in force"; return 1; }
  printf '%s\n' "$fl" | command grep -F "(min: $NEW_FLOOR) — BELOW MINIMUM" >/dev/null
}

# ── U2: --dry-run previews the update and writes nothing ─────────────────────
case_U2() {
  local fw="$1" p="" before=""
  p="$(newtmp)/p"; mk_project "$p" "$fw" old-shipped
  before="$(fingerprint "$p/templates/tool-matrix")"
  run_sync "$p" "$fw" --dry-run
  CASE_DETAIL="rc=$RC"
  [ "$RC" = 0 ] || return 1
  [ "$(fingerprint "$p/templates/tool-matrix")" = "$before" ] || { CASE_DETAIL="$CASE_DETAIL; --dry-run WROTE into the matrix"; return 1; }
  has "[would update] templates/tool-matrix/common.json — its bytes match a version the framework shipped (committed in" \
    || { CASE_DETAIL="$CASE_DETAIL; no would-update line"; return 1; }
}

# ── U3: after the update, a second run changes nothing ───────────────────────
case_U3() {
  local fw="$1" p="" after1=""
  p="$(newtmp)/p"; mk_project "$p" "$fw" old-shipped
  run_sync "$p" "$fw"
  [ "$RC" = 0 ] && has "templates/tool-matrix/common.json: updated" || { CASE_DETAIL="first run rc=$RC, no update"; return 1; }
  after1="$(fingerprint "$p/templates/tool-matrix")"
  run_sync "$p" "$fw"
  CASE_DETAIL="second run rc=$RC"
  [ "$RC" = 0 ] && [ "$(fingerprint "$p/templates/tool-matrix")" = "$after1" ] \
    && has "templates/tool-matrix/common.json: up to date" && has "templates/tool-matrix/web.json: up to date" \
    && ! has ": updated (backup: " && ! has "until it is applied"
}

# ── U4: an unwritable matrix directory: no verified backup, so BOTH updates are
#        refused, nothing changes, and the sync still reaches its pin step and
#        its summary, rc 1 ─────────────────────────────────────────────────────
case_U4() {
  local fw="$1" p="" before=""
  p="$(newtmp)/p"; mk_project "$p" "$fw" old-shipped
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
  p="$(newtmp)/p"; mk_project "$p" "$fw" old-shipped; m="$p/templates/tool-matrix"
  old="$(cksum < "$m/common.json")"
  bin="$(newtmp)/bin"; mk_cp_stub "$bin" empty '*' '*/templates/tool-matrix/common.json.bak.*'
  run_sync_path "$bin" "$p" "$fw"
  CASE_DETAIL="rc=$RC stub=$(stub_state "$bin")"
  [ -s "$bin/.hits" ] && [ "$RC" = 1 ] || return 1
  has "REFUSING to update templates/tool-matrix/common.json" || { CASE_DETAIL="$CASE_DETAIL; no REFUSING line"; return 1; }
  ! has "templates/tool-matrix/common.json: updated" || { CASE_DETAIL="$CASE_DETAIL; reported as updated"; return 1; }
  [ "$(cksum < "$m/common.json")" = "$old" ] || { CASE_DETAIL="$CASE_DETAIL; common.json was replaced with no verified backup"; return 1; }
  # A backup that did not verify is left where it is, never deleted (R-BL333-16).
  [ -e "$m/common.json.bak.$TODAY" ] && [ ! -s "$m/common.json.bak.$TODAY" ] \
    || { CASE_DETAIL="$CASE_DETAIL; the unverified (empty) .bak is not where the stub left it"; return 1; }
}

# ── U6: an update cp reports as done but left the file empty: caught by
#        re-reading it, the project's bytes put back, the backup kept ─────────
case_U6() {
  local fw="$1" p="" m="" old="" bin=""
  p="$(newtmp)/p"; mk_project "$p" "$fw" old-shipped; m="$p/templates/tool-matrix"
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
  p="$(newtmp)/p"; mk_project "$p" "$fw" old-shipped; m="$p/templates/tool-matrix"
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
  p="$(newtmp)/p"; mk_project "$p" "$i" old-shipped
  before="$(fingerprint "$p/templates/tool-matrix")"
  run_sync "$p" "$i"
  fl="$(floor_line "$p")"
  CASE_DETAIL="rc=$RC verdicts:$(verdicts) check-versions='$fl'"
  [ "$RC" = 0 ] || return 1
  [ "$(fingerprint "$p/templates/tool-matrix")" = "$before" ] || { CASE_DETAIL="$CASE_DETAIL; the matrix CHANGED"; return 1; }
  has "templates/tool-matrix/common.json: the framework at" && has "has no git history this sync can read" \
    || { CASE_DETAIL="$CASE_DETAIL; no line saying the history cannot be read"; return 1; }
  ! has "a version the framework shipped (committed in" && ! has "match no version the framework shipped" \
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
  p="$(newtmp)/p"; mk_project "$p" "$i" old-shipped
  run_sync "$p" "$i"
  CASE_DETAIL="rc=$RC verdicts:$(verdicts)"
  [ "$RC" = 0 ] && has "has no git history this sync can read" && ! has "match no version the framework shipped" \
    && ! has "a version the framework shipped (committed in"
}

# ── H3: a framework checkout with no commits: git cannot read its log, and
#        that is not the same as finding no such version ─────────────────────
case_H3() {
  local fw="$1" i="" p=""
  i="$(newtmp)/fw"; mk_mirror "$fw" "$i" || { CASE_DETAIL="mirror"; return 1; }
  ( cd "$i" && git init -q ) >/dev/null 2>&1 || { CASE_DETAIL="git init"; return 1; }
  p="$(newtmp)/p"; mk_project "$p" "$i" old-shipped
  run_sync "$p" "$i"
  CASE_DETAIL="rc=$RC verdicts:$(verdicts)"
  [ "$RC" = 0 ] && has "has no git history this sync can read" && ! has "match no version the framework shipped" \
    && ! has "a version the framework shipped (committed in"
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
  p="$(newtmp)/p"; mk_project "$p" "$i" old-shipped
  before="$(fingerprint "$p/templates/tool-matrix")"
  run_sync "$p" "$i"
  CASE_DETAIL="rc=$RC verdicts:$(verdicts)"
  [ "$RC" = 0 ] && [ "$(fingerprint "$p/templates/tool-matrix")" = "$before" ] \
    && has "templates/tool-matrix/common.json: not in the framework clone's history, but that clone is shallow" \
    && ! has "match no version the framework shipped" && ! has "a version the framework shipped (committed in"
}

# ── U8: a copy the project restored ON PURPOSE — its own .bak, an older shipped
#        version — is replaced again on the next sync. Karl's ruling on
#        R-BL333-10: the bytes decide, and the sync says so ──────────────────
case_U8() {
  local fw="$1" p="" m="" fl=""
  p="$(newtmp)/p"; mk_project "$p" "$fw" old-shipped; m="$p/templates/tool-matrix"
  run_sync "$p" "$fw"
  [ "$RC" = 0 ] && [ -f "$m/common.json.bak.$TODAY" ] || { CASE_DETAIL="first run rc=$RC, no .bak"; return 1; }
  cp "$m/common.json.bak.$TODAY" "$m/common.json"
  run_sync "$p" "$fw"
  fl="$(floor_line "$p")"
  CASE_DETAIL="second run rc=$RC check-versions='$fl'"
  [ "$RC" = 0 ] && cmp -s "$fw/templates/tool-matrix/common.json" "$m/common.json" \
    && has "templates/tool-matrix/common.json: updated (backup: " \
    && printf '%s\n' "$fl" | command grep -F "(min: $NEW_FLOOR) — BELOW MINIMUM" >/dev/null
}

# ── U9: bytes the framework shipped as ANOTHER file are no match: common.json
#        holding web.json's first-commit bytes is the project's own, and kept ──
case_U9() {
  local fw="$1" p="" before=""
  p="$(newtmp)/p"; mk_project "$p" "$fw" current
  printf '%s\n' "$OLD_WEB" > "$p/templates/tool-matrix/common.json"
  before="$(fingerprint "$p/templates/tool-matrix")"
  run_sync "$p" "$fw"
  CASE_DETAIL="rc=$RC verdicts:$(verdicts)"
  [ "$RC" = 0 ] && [ "$(fingerprint "$p/templates/tool-matrix")" = "$before" ] \
    && has "templates/tool-matrix/common.json: its bytes match no version the framework shipped"
}

# ── G1: with GIT_DIR exported — a git hook exports it, and in a linked worktree
#        it names the PROJECT's git directory — the history read and the commit
#        pinned are still the framework's. The project's own history holds its
#        edited copy, so reading it would replace that copy ──────────────────
case_G1() {
  local fw="$1" p="" before="" want="" pin=""
  p="$(newtmp)/p"; mk_project "$p" "$fw" edited
  before="$(fingerprint "$p/templates/tool-matrix")"
  want="$(git -C "$fw" rev-parse HEAD 2>/dev/null)"
  RC=0
  OUT="$( cd "$p" && unset GITHUB_BASE_REF; GIT_DIR="$p/.git" HOME="$p/.home" CDF_HOME="$p/.no-such-cdf" SOIF_NONINTERACTIVE=1 \
      bash "$fw/scripts/upgrade-project.sh" --sync-framework </dev/null 2>&1 )" || RC=$?
  pin="$(jq -r '.soloFrameworkCommit // ""' "$p/.claude/manifest.json" 2>/dev/null)"
  CASE_DETAIL="rc=$RC verdicts:$(verdicts) pinned=${pin:0:8} framework=${want:0:8}"
  [ "$RC" = 0 ] && [ "$(fingerprint "$p/templates/tool-matrix")" = "$before" ] \
    && has "templates/tool-matrix/common.json: its bytes match no version the framework shipped" \
    && [ -n "$want" ] && [ "$pin" = "$want" ]
}

# ── L1: a DANGLING link where a matrix file is missing: no copy is written
#        through it — a [FAIL] naming it, rc 1, nothing outside, the link kept ──
case_L1() {
  local fw="$1" p="" m="" out=""
  p="$(newtmp)/p"; mk_project "$p" "$fw" missing; m="$p/templates/tool-matrix"
  out="$(newtmp)"
  ln -s "$out/web.json" "$m/web.json"
  run_sync "$p" "$fw"
  CASE_DETAIL="rc=$RC outside=$([ -e "$out/web.json" ] && echo WRITTEN || echo absent) link=$([ -L "$m/web.json" ] && echo kept || echo GONE)"
  [ "$RC" = 1 ] && has "REFUSING to write templates/tool-matrix/web.json — it is a symbolic link" \
    && [ ! -e "$out/web.json" ] && [ -L "$m/web.json" ]
}

# ── L2: a LIVE link to an outside file holding an old shipped version: it is
#        not updated through the link — a [FAIL], rc 1, the outside file and the
#        link unchanged, no .bak — and the regular file beside it still is ───
case_L2() {
  local fw="$1" p="" m="" out="" old=""
  p="$(newtmp)/p"; mk_project "$p" "$fw" old-shipped; m="$p/templates/tool-matrix"
  out="$(newtmp)"
  matrix_common "$OLD_FLOOR" > "$out/common.json" && ln -sf "$out/common.json" "$m/common.json" \
    || { CASE_DETAIL="link setup"; return 1; }
  old="$(cksum < "$out/common.json")"
  run_sync "$p" "$fw"
  CASE_DETAIL="rc=$RC outside=$([ "$(cksum < "$out/common.json")" = "$old" ] && echo unchanged || echo OVERWRITTEN)"
  [ "$RC" = 1 ] && has "REFUSING to write templates/tool-matrix/common.json — it is a symbolic link" \
    && [ "$(cksum < "$out/common.json")" = "$old" ] && [ -L "$m/common.json" ] \
    && [ ! -e "$m/common.json.bak.$TODAY" ] && has "templates/tool-matrix/web.json: updated (backup: "
}

# ── S13: a missing-file copy that writes a prefix and then fails (a disk that
#         fills): no fragment is left — else every later sync keeps it as the
#         project's own, rc 0, while check-versions reads broken JSON — and the
#         next sync copies the file ─────────────────────────────────────────
case_S13() {
  local fw="$1" p="" m="" bin=""
  p="$(newtmp)/p"; mk_project "$p" "$fw" missing; m="$p/templates/tool-matrix"
  bin="$(newtmp)/bin"; mk_cp_stub "$bin" prefix '*' '*/templates/tool-matrix/web.json'
  run_sync_path "$bin" "$p" "$fw"
  CASE_DETAIL="rc=$RC stub=$(stub_state "$bin") web.json=$([ -e "$m/web.json" ] && echo "LEFT, $(wc -c < "$m/web.json" | tr -d ' ') bytes" || echo absent)"
  [ -s "$bin/.hits" ] && [ "$RC" = 1 ] && has "FAILED to copy templates/tool-matrix/web.json" && [ ! -e "$m/web.json" ] \
    || return 1
  run_sync "$p" "$fw"
  CASE_DETAIL="$CASE_DETAIL; next sync rc=$RC"
  [ "$RC" = 0 ] && cmp -s "$fw/templates/tool-matrix/web.json" "$m/web.json"
}

# ── S14: a failed script copy fails the run, and the matrix step still runs —
#         it does not wait on the scripts step, so a row that calls the probe can
#         meet the project's old probe until a sync succeeds. `## BL-235:`'s
#         pointer says exactly this; the case holds it to that ───────────────
case_S14() {
  local fw="$1" p="" bin=""
  p="$(newtmp)/p"; mk_project "$p" "$fw" old-shipped
  bin="$(newtmp)/bin"; mk_cp_stub "$bin" fail '*' '*/scripts/probe-tool.sh'
  run_sync_path "$bin" "$p" "$fw"
  CASE_DETAIL="rc=$RC stub=$(stub_state "$bin") probe=$([ -e "$p/scripts/probe-tool.sh" ] && echo present || echo absent)"
  [ -s "$bin/.hits" ] && [ "$RC" = 1 ] && has "FAILED to sync scripts/probe-tool.sh" && [ ! -e "$p/scripts/probe-tool.sh" ] \
    && has "templates/tool-matrix/common.json: updated (backup: " \
    && cmp -s "$fw/templates/tool-matrix/common.json" "$p/templates/tool-matrix/common.json"
}

# ── the split: SOURCED, this file only defines ──────────────────────────────
# tests/test-bl333-sync-tool-matrix-mutants.sh sources this file for the
# fixtures and cases above, so the cases and the mutants run on separate
# unit-shard legs (R-BL333-14; the precedent is `# BL-311-MCP-SPLIT`). Sourced,
# this file returns HERE, before any case runs; run directly, it runs every case
# below and no mutant. BASH_SOURCE, not an environment variable, tells the two
# apart, so a variable left exported cannot turn a direct run into an empty one.
# The mutants file fails if loading this ran a case.
if [ "${BASH_SOURCE[0]}" != "$0" ]; then return 0; fi   # BL-333-MUTANTS-SPLIT

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
run_case case_S2 "$FW_REAL" "a matrix whose bytes match no shipped version is reported with its diff and why, and kept on a bare run"
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
run_case case_S13 "$FW_REAL" "a copy that writes a prefix and fails leaves no fragment, and the next sync copies the file"
run_case case_S14 "$FW_REAL" "a failed script copy fails the run, and the matrix step still runs"
run_case case_U1 "$FW_REAL" "an old shipped copy is replaced on a plain sync (dated .bak, the commit with those bytes, how to keep an older floor) and check-versions enforces the new floor"
run_case case_U2 "$FW_REAL" "--dry-run previews the update and writes nothing"
run_case case_U3 "$FW_REAL" "after the update, a second run changes nothing"
run_case_unprivileged case_U4 "$FW_REAL" "no verified backup: both updates refused, nothing changed, the sync reaches its pin and summary, rc 1"
run_case case_U5 "$FW_REAL" "a backup cp calls done but left empty: the update is refused, the copy unchanged, the empty .bak left in place"
run_case case_U6 "$FW_REAL" "an update cp calls done but left empty: a [FAIL], the copy put back, the backup kept"
run_case case_U7 "$FW_REAL" "the update and the putting-back both fail: the sync says the copy is not back, and where it is"
run_case case_U8 "$FW_REAL" "a copy restored on purpose to an older shipped version (its own .bak) is replaced again"
run_case case_U9 "$FW_REAL" "bytes the framework shipped as another file are no match: the copy is kept"
run_case case_H1 "$FW_REAL" "a framework that is not a git checkout: the old copy is kept, and the sync says why"
run_case case_H2 "$FW_REAL" "a framework inside another repository: that history is not the framework's"
run_case case_H3 "$FW_REAL" "a framework checkout with no commits: its log cannot be read, so the copy is kept, and the sync says why"
run_case case_H4 "$FW_REAL" "a shallow clone whose history stops before the copy's version: kept, and the sync says why"
run_case case_G1 "$FW_REAL" "with GIT_DIR exported, the history read and the commit pinned are still the framework's"
run_case case_L1 "$FW_REAL" "a dangling link where a matrix file is missing is refused, rc 1, nothing written outside"
run_case case_L2 "$FW_REAL" "a live link to an old shipped copy is refused, rc 1, the outside file unchanged"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
