#!/usr/bin/env bash
# scripts/lib/scout/scout-core.sh — Scout's primitives: version, JSON encoding,
# portable file/stat/git reads, and the pruned file walk every other Scout lib
# builds on.
#
# SPEC: docs/designs/2026-08-02-brownfield-adoption-v1.md §3.1 (Scout is the
# read-only scanner, packaged as a standalone tool) and §3.3 M1/M5. The
# standing rules are transcribed in docs/module-contract.md.
#
# M5 IS LAW AND THIS FILE IS WHERE IT COSTS SOMETHING. Scout sources NOTHING.
# It may not reach for scripts/lib/*.sh — not the shared printers, not the
# soif_read_* state readers, not the host drivers — because Scout has to run in
# a clone that has never had the scaffolder applied to it. Everything below is
# a deliberate re-implementation of a small subset of what core already has.
# §8.2 specifies the reuse as reuse-by-EXTRACTION: copy the predicate, never
# the dependency. That duplication is the price of a survey tool that costs
# nothing to run.
#
# M1 APPLIES TOO: everything Scout owns lives under this directory, with
# scripts/scout.sh as its single entry script. No Scout code belongs anywhere
# else in the tree.
#
# NOT EVEN jq. Scout emits JSON by hand. jq is not on a stock mac, and a
# scanner whose first act is "install a tool" is not a tool you can point at a
# stranger's repository. bash 3.2 is the floor: no associative arrays, no
# `mapfile`, no `${var,,}`, no `nullglob`. Intermediate results are staged in
# tab-separated files under a work directory the entry script owns.

# scout_module_version — the module's own version marker.
#
# Scout reports the version of the scanner that produced a report, and it has
# to do so without reading .claude/manifest.json or any framework state: at
# scan time there may be no framework installed at all. A literal here is the
# whole mechanism.
#
# The `-wp2` suffix is load-bearing information, not decoration: this build
# emits all seven of §8.2's sections, where `-wp1` emitted three. A consumer
# holding an older report must be able to tell "this scanner had not been
# taught to look yet" from "it looked and found nothing" — and within the
# secrets section that same distinction is carried at finer grain by `status`,
# because "gitleaks was not installed" is not a clean bill of health.
scout_module_version() {
  printf '%s\n' "0.3.0-wp2"
}

# ── JSON encoding ───────────────────────────────────────────────────────────

# scout_json_escape STRING — the string's JSON-escaped BODY (no quotes).
#
# Backslash first, then the double quote: reversing that order double-escapes
# every quote. Control characters are dropped and tabs folded to spaces rather
# than escaped, which keeps the encoder to two sed expressions and costs
# nothing real — every value Scout emits is a path, a shell command, or a
# sentence. Embedded newlines survive as `\n` via the awk join.
scout_json_escape() {
  printf '%s' "$1" \
    | tr -d '\000-\010\013\014\016-\037\177' \
    | tr '\011' ' ' \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
    | awk '{ if (NR > 1) printf "\\n"; printf "%s", $0 }'
}

# scout_json_str STRING — a complete JSON string literal.
scout_json_str() {
  printf '"%s"' "$(scout_json_escape "$1")"
}

# scout_json_str_or_null STRING — a JSON string, or the literal `null` when the
# value is empty.
#
# `null` and `""` are different claims and the schema uses both. An absent test
# command is `null`; a test command that is genuinely the empty string would be
# a bug worth seeing.
scout_json_str_or_null() {
  if [ -z "$1" ]; then printf 'null'; else scout_json_str "$1"; fi
}

# scout_json_array_from_file FILE — a JSON array of strings, one per line.
scout_json_array_from_file() {
  local file="$1" first=1 line
  printf '['
  if [ -f "$file" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      [ "$first" -eq 1 ] || printf ', '
      scout_json_str "$line"
      first=0
    done < "$file"
  fi
  printf ']'
}

# scout_json_array_from_words WORDS — a JSON array from a space-separated list.
scout_json_array_from_words() {
  local first=1 w
  printf '['
  for w in $1; do
    [ "$first" -eq 1 ] || printf ', '
    scout_json_str "$w"
    first=0
  done
  printf ']'
}

# ── Portable reads ──────────────────────────────────────────────────────────

# scout_now_utc — the scan timestamp, ISO-8601 UTC to the second.
scout_now_utc() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# scout_abs PATH — PATH made absolute, or empty if it is not a directory.
scout_abs() {
  ( cd "$1" 2>/dev/null && pwd ) || printf ''
}

# scout_have_git — whether a git binary is callable at all.
#
# Checked rather than assumed. On a machine without the Xcode command line
# tools, invoking `git` pops a GUI installer prompt; a read-only scanner must
# not do that to somebody who only asked it to look at a directory.
scout_have_git() {
  command -v git >/dev/null 2>&1
}

# scout_head_commit ROOT — the enclosing repository's HEAD, or empty.
scout_head_commit() {
  scout_have_git || return 0
  git -C "$1" rev-parse HEAD 2>/dev/null || printf ''
}

# scout_file_nonempty PATH — a regular file with at least one byte.
#
# Emptiness matters throughout the ladder: an empty README.md is a scaffolding
# artifact, not a product description, and treating it as evidence is exactly
# the kind of false confidence §4.4 warns the placement must not manufacture.
scout_file_nonempty() {
  [ -f "$1" ] && [ -s "$1" ]
}

# scout_count_entries PATH — how many entries a directory holds, EXCLUDING
# hidden ones (0 if absent).
#
# Hidden entries are excluded because on the ladder the question is always
# "is there CONTENT here", and a dot-file in a content directory is
# scaffolding: `.gitkeep`, `.DS_Store`, an editor lock. None of them is an
# archived test result or a design document.
scout_count_entries() {
  local n
  n=$(ls -1 "$1" 2>/dev/null | grep -c '')
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s\n' "$n"
}

# scout_dir_has_entries PATH — the directory holds at least one non-hidden
# entry.
#
# EXPRESSED IN TERMS OF THE COUNTER, and that is the entire reason this
# function exists rather than an inline test. The first cut of this file had a
# separate `ls -A` predicate sitting beside the `ls -1` count above, and the
# two disagreed on exactly one input: a directory kept alive by a `.gitkeep`.
# That input is not a corner case. **Git cannot track an empty directory**, so
# a placeholder is how every emptied directory in every real repository
# actually looks — including the "since-emptied docs/test-results/" that §4.4
# correction 2 is written about. On it, rung 3 read the predicate as "there
# are archived results" and printed "0 archived result files" as its evidence
# in the same breath, and the design's own scenario reported 4: the exact
# number the correction exists to remove, resurrected by a one-byte file.
#
# One measurement, two spellings of it. They cannot drift apart again, and
# every ladder arm that asks "is there content here" now asks it the same way.
scout_dir_has_entries() {
  [ -d "$1" ] || return 1
  [ "$(scout_count_entries "$1")" -gt 0 ]
}

# ── The file walk ───────────────────────────────────────────────────────────

# scout_walk_files ROOT — every regular file under ROOT, relative, one per
# line, with the usual dependency and artifact directories pruned.
#
# Pruning is what makes the language counts mean anything: a project with 40
# TypeScript files and a populated node_modules is 99% "javascript" by raw file
# count, and reporting that would be worse than reporting nothing. `.git` is
# pruned for the same reason and one better — Scout has no business reading the
# object store to guess a language.
#
# `out/` and `env/` are deliberately NOT pruned despite being common artifact
# names: both are also common source directory names, and a false prune loses
# real evidence silently, while a false include shows up as a visible count an
# operator can argue with.
scout_walk_files() {
  local root="$1"
  ( cd "$root" 2>/dev/null || return 0
    find . \
      \( -name .git -o -name node_modules -o -name bower_components -o -name vendor \
         -o -name dist -o -name build -o -name target -o -name .venv -o -name venv \
         -o -name __pycache__ -o -name .tox -o -name .mypy_cache -o -name .pytest_cache \
         -o -name .ruff_cache -o -name .next -o -name .nuxt -o -name .svelte-kit \
         -o -name coverage -o -name .terraform -o -name Pods -o -name .gradle \
         -o -name .idea -o -name .cache -o -name .parcel-cache \) -prune -o \
      -type f -print 2>/dev/null ) | sed -e 's|^\./||'
}

# scout_first_nonempty_file ROOT PATH... — the first listed path that exists as
# a non-empty file under ROOT, relative. Empty output means none matched.
scout_first_nonempty_file() {
  local root="$1" p
  shift
  for p in "$@"; do
    if scout_file_nonempty "$root/$p"; then printf '%s\n' "$p"; return 0; fi
  done
  return 1
}
