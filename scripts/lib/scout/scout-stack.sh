#!/usr/bin/env bash
# scripts/lib/scout/scout-stack.sh — §8.2's `stack` section: what the adoptee
# is written in, what builds it, what tests it, and where its CI lives.
#
# SPEC: docs/designs/2026-08-02-brownfield-adoption-v1.md §8.2 (the `stack`
# object is normative) and §4.2 (every signal is offered WITH ITS OWN
# CONFIDENCE, and the scanner decides nothing).
#
# M5: sources nothing. See scripts/lib/scout/scout-core.sh's header.
#
# EVERYTHING HERE IS EVIDENCE, NOT A VERDICT. §4.2's rule is that the scanner
# offers signals and the operator's answer overrides all of them. That is why a
# language count carries a tier rather than a boolean, why `testCommand` names
# the file and key it came from, and why an absent signal is `null` instead of
# a guess.

# _scout_lang_table — `<extension> <language>` rows.
#
# Extension-to-language is a heuristic and two rows are knowingly ambiguous:
# `.h` is claimed by C (a C++ project will still read as majority `cpp` from
# its `.cpp`/`.hpp` files) and `.m` by Objective-C (MATLAB projects will
# misread). Both are visible in the report as a named language with a count an
# operator can dispute, which is the §4.2 posture: a labelled heuristic beats a
# hidden one.
_scout_lang_table() {
  cat <<'LANGTABLE'
ts typescript
tsx typescript
mts typescript
cts typescript
js javascript
jsx javascript
mjs javascript
cjs javascript
py python
rb ruby
go go
rs rust
java java
kt kotlin
kts kotlin
swift swift
c c
h c
cc cpp
cpp cpp
cxx cpp
hpp cpp
hh cpp
cs csharp
php php
scala scala
sh shell
bash shell
zsh shell
lua lua
dart dart
ex elixir
exs elixir
erl erlang
hs haskell
clj clojure
cljs clojure
m objective-c
mm objective-c
r r
pl perl
pm perl
sql sql
vue vue
svelte svelte
tf terraform
LANGTABLE
}

# _scout_confidence FILES TOTAL — §4.2's tier for one language.
#
#   high    at least 10 files AND at least a fifth of the counted corpus
#   medium  at least 3 files, OR at least a fifth of the corpus
#   low     anything else
#
# Two factors, because either alone lies. Share alone calls a two-file
# repository "high confidence typescript"; count alone calls a stray vendored
# Perl script in a 4000-file Java monolith a first-class language. The
# thresholds are round numbers chosen to be arguable, and they are stated here
# rather than buried so that arguing with them is cheap.
_scout_confidence() {
  local files="$1" total="$2" share=0
  case "$files" in ''|*[!0-9]*) files=0 ;; esac
  case "$total" in ''|*[!0-9]*) total=0 ;; esac
  [ "$total" -gt 0 ] && share=$(( files * 100 / total ))
  if [ "$files" -ge 10 ] && [ "$share" -ge 20 ]; then
    printf 'high\n'
  elif [ "$files" -ge 3 ] || [ "$share" -ge 20 ]; then
    printf 'medium\n'
  else
    printf 'low\n'
  fi
}

# _scout_pkg_json_script FILE KEY — the value of package.json's
# `.scripts.<KEY>`, or empty.
#
# Hand-parsed, because M5 forbids sourcing anything and jq is not on a stock
# mac. The parse is deliberately narrow rather than clever: buffer the file,
# find the `"scripts"` key, walk braces (respecting string literals and
# backslash escapes) to isolate that object EXACTLY, and only then look for the
# key inside it. Scoping to the object first is what stops a `"test-utils"`
# dependency or a `"pretest"` sibling from being read as the test command — a
# whole-file grep for `"test"` gets that wrong on most real package.json files.
_scout_pkg_json_script() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 0
  awk -v key="$key" '
    { buf = buf $0 "\n" }
    END {
      i = index(buf, "\"scripts\"")
      if (i == 0) exit
      rest = substr(buf, i)
      j = index(rest, "{")
      if (j == 0) exit
      s = substr(rest, j + 1)
      depth = 1; instr = 0; esc = 0; obj = ""
      n = length(s)
      for (k = 1; k <= n; k++) {
        ch = substr(s, k, 1)
        if (esc) { esc = 0; obj = obj ch; continue }
        if (ch == "\\") { esc = 1; obj = obj ch; continue }
        if (ch == "\"") { instr = !instr; obj = obj ch; continue }
        if (!instr) {
          if (ch == "{") depth++
          else if (ch == "}") { depth--; if (depth == 0) break }
        }
        obj = obj ch
      }
      pat = "\"" key "\"[ \t\r\n]*:[ \t\r\n]*\""
      if (!match(obj, pat)) exit
      v = substr(obj, RSTART + RLENGTH)
      out = ""; esc = 0
      m = length(v)
      for (k = 1; k <= m; k++) {
        ch = substr(v, k, 1)
        if (esc) { out = out ch; esc = 0; continue }
        if (ch == "\\") { esc = 1; continue }
        if (ch == "\"") break
        out = out ch
      }
      print out
    }
  ' "$file"
}

# _scout_pkg_managers ROOT WORK — the package managers in evidence, deduped,
# most-specific-first (a lockfile outranks the manifest that generated it).
#
# THIS TABLE IS A CURRENCY SURFACE and it decays quietly. A missing spelling
# does not error — it reports an empty `packageManagers` on a project that
# obviously has one, in the false-negative direction, with no clue as to why.
# Spellings are confirmed against each tool's own documentation, never from
# memory: Bun made the TEXT `bun.lock` its default at 1.2 and `bun.lockb` is
# the pre-1.2 binary form (both still in the wild, so both rows stay); uv
# writes `uv.lock` beside pyproject.toml; pdm writes `pdm.lock`; Deno creates
# `deno.lock` automatically. Adding a spelling here means adding it to the
# `project_scaffolded` list in scripts/lib/scout/scout-reality.sh too — S4 in
# tests/test-brownfield-wp1-scout.sh asserts BOTH surfaces for every row,
# because a spelling added to one and forgotten in the other is the shape this
# defect actually takes.
_scout_pkg_managers() {
  local root="$1" work="$2" row f m
  : > "$work/pkgmgr"
  cat <<'PMTABLE' > "$work/pmtable"
pnpm-lock.yaml pnpm
yarn.lock yarn
package-lock.json npm
bun.lock bun
bun.lockb bun
deno.lock deno
uv.lock uv
poetry.lock poetry
pdm.lock pdm
Pipfile.lock pipenv
Pipfile pipenv
requirements.txt pip
setup.py setuptools
Cargo.lock cargo
Cargo.toml cargo
go.sum go-modules
go.mod go-modules
Gemfile.lock bundler
Gemfile bundler
composer.lock composer
composer.json composer
pom.xml maven
gradle.lockfile gradle
build.gradle gradle
build.gradle.kts gradle
Package.resolved swiftpm
Package.swift swiftpm
pubspec.lock pub
pubspec.yaml pub
packages.lock.json nuget
mix.lock hex
PMTABLE
  while read -r f m; do
    [ -n "$f" ] || continue
    [ -e "$root/$f" ] || continue
    grep -qx "$m" "$work/pkgmgr" 2>/dev/null && continue
    printf '%s\n' "$m" >> "$work/pkgmgr"
  done < "$work/pmtable"
}

# _scout_build_files ROOT WORK — the build/manifest files actually present.
_scout_build_files() {
  local root="$1" work="$2" f
  : > "$work/buildfiles"
  for f in package.json pyproject.toml setup.py requirements.txt Cargo.toml \
           go.mod pom.xml build.gradle build.gradle.kts Gemfile composer.json \
           Package.swift pubspec.yaml mix.exs Makefile CMakeLists.txt \
           Dockerfile docker-compose.yml; do
    [ -f "$root/$f" ] && printf '%s\n' "$f" >> "$work/buildfiles"
  done
  return 0
}

# _scout_test_command ROOT WORK — `<command>\t<source>` into $work/testcmd, or
# an empty file.
#
# Ordered by how much the source ACTUALLY KNOWS. A declared `scripts.test` is
# the project telling you its test command in its own words; `go test ./...`
# inferred from a go.mod is Scout telling you the language's convention and
# hoping. The `source` field carries that difference to the operator instead of
# flattening it, which is §4.2's rule applied to a single field.
_scout_test_command() {
  local root="$1" work="$2" v
  : > "$work/testcmd"

  if [ -f "$root/package.json" ]; then
    v=$(_scout_pkg_json_script "$root/package.json" test)
    if [ -n "$v" ]; then
      printf '%s\t%s\n' "$v" "package.json scripts.test" > "$work/testcmd"
      return 0
    fi
  fi

  if [ -f "$root/Makefile" ] && grep -qE '^test[[:space:]]*:' "$root/Makefile" 2>/dev/null; then
    printf '%s\t%s\n' "make test" "Makefile target test" > "$work/testcmd"
    return 0
  fi

  if [ -f "$root/pytest.ini" ]; then
    printf '%s\t%s\n' "pytest" "pytest.ini present" > "$work/testcmd"
    return 0
  fi
  if [ -f "$root/tox.ini" ] && grep -q 'pytest' "$root/tox.ini" 2>/dev/null; then
    printf '%s\t%s\n' "pytest" "tox.ini names pytest" > "$work/testcmd"
    return 0
  fi
  if [ -f "$root/pyproject.toml" ] && grep -q 'tool.pytest' "$root/pyproject.toml" 2>/dev/null; then
    printf '%s\t%s\n' "pytest" "pyproject.toml [tool.pytest]" > "$work/testcmd"
    return 0
  fi
  if [ -f "$root/setup.cfg" ] && grep -q 'tool:pytest' "$root/setup.cfg" 2>/dev/null; then
    printf '%s\t%s\n' "pytest" "setup.cfg [tool:pytest]" > "$work/testcmd"
    return 0
  fi

  if [ -f "$root/Cargo.toml" ]; then
    printf '%s\t%s\n' "cargo test" "Cargo.toml present (cargo convention)" > "$work/testcmd"
    return 0
  fi
  if [ -f "$root/go.mod" ]; then
    printf '%s\t%s\n' "go test ./..." "go.mod present (go convention)" > "$work/testcmd"
    return 0
  fi
  if [ -f "$root/Gemfile" ] && grep -q 'rspec' "$root/Gemfile" 2>/dev/null; then
    printf '%s\t%s\n' "bundle exec rspec" "Gemfile names rspec" > "$work/testcmd"
    return 0
  fi
  return 0
}

# _scout_ci_host ROOT — `github` / `gitlab` / `bitbucket`, or empty.
_scout_ci_host() {
  local root="$1" f
  for f in "$root/.github/workflows"/*.yml "$root/.github/workflows"/*.yaml; do
    if [ -f "$f" ]; then printf 'github\n'; return 0; fi
  done
  [ -f "$root/.gitlab-ci.yml" ] && { printf 'gitlab\n'; return 0; }
  [ -f "$root/bitbucket-pipelines.yml" ] && { printf 'bitbucket\n'; return 0; }
  return 0
}

# scout_stack_scan ROOT WORK — fills $WORK with the stack section's data.
#
# Writes (all inside WORK, which the entry script owns and removes):
#   lang        `<language>\t<files>\t<confidence>`, most files first
#   pkgmgr      one package manager per line
#   buildfiles  one build/manifest file per line
#   testcmd     `<command>\t<source>`, or empty
#   cihost      one host name, or empty
scout_stack_scan() {
  local root="$1" work="$2" lname lcount ltotal
  local TAB
  TAB=$(printf '\t')

  _scout_lang_table > "$work/langtable"
  awk -v tbl="$work/langtable" '
    BEGIN { while ((getline line < tbl) > 0) { split(line, a, " "); map[a[1]] = a[2] } }
    {
      n = split($0, p, "/"); base = p[n]
      if (match(base, /\.[^.]+$/)) {
        ext = tolower(substr(base, RSTART + 1))
        if (ext in map) { c[map[ext]]++; total++ }
      }
    }
    END { for (l in c) printf "%s\t%d\t%d\n", l, c[l], total }
  ' "$work/files" | LC_ALL=C sort -t"$TAB" -k2,2nr -k1,1 > "$work/lang.raw"

  : > "$work/lang"
  while IFS="$TAB" read -r lname lcount ltotal; do
    [ -n "$lname" ] || continue
    printf '%s\t%s\t%s\n' "$lname" "$lcount" "$(_scout_confidence "$lcount" "$ltotal")" >> "$work/lang"
  done < "$work/lang.raw"

  _scout_pkg_managers "$root" "$work"
  _scout_build_files "$root" "$work"
  _scout_test_command "$root" "$work"
  _scout_ci_host "$root" > "$work/cihost"
  return 0
}
