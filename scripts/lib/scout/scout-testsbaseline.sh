#!/usr/bin/env bash
# scripts/lib/scout/scout-testsbaseline.sh — §8.2's `testsBaseline` section:
# what the adoptee's tests do today, and how much of its source has none.
#
# SPEC: docs/designs/2026-08-02-brownfield-adoption-v1.md §8.2 (the schema, and
# the reuse-by-EXTRACTION rule), §10-WP2, §5.4 (the test-debt ledger this
# section's count later feeds).
#
# M5: sources no CORE library. It does use its own module's sibling
# (`_scout_lang_table` from scout-stack.sh), which is the same program.
#
# ─────────────────────────────────────────────────────────────────────────────
# THIS IS THE ONLY PLACE SCOUT EXECUTES PROJECT CODE, AND IT IS OPT-IN.
#
# A scanner you point at a stranger's repository must not run that repository's
# `npm test` because it felt like knowing the answer. Default: `commandRan` is
# false and the reason says so. With `--run-tests`, and only then, the detected
# command runs — bounded by SCOUT_TEST_TIMEOUT (default 300s) and with its
# output DISCARDED rather than captured, because test output is exactly the
# kind of free text that carries a credential and §6.2's rule does not stop
# being true one section further down the report.
#
# ─────────────────────────────────────────────────────────────────────────────
# REUSE BY EXTRACTION, AND AN HONEST LEDGER OF WHAT CHANGED (§8.2).
#
# The classifier below is lifted from the shared BL-072 file-classification
# core — copied, not sourced, because Scout has to run in a clone that has
# never had the framework applied to it. Copying a predicate creates a drift
# risk, and the only defence against a silent one is to say plainly what was
# carried and what was altered. The report itself carries that ledger, in
# `classifierParity`, so the person reading the number can see the shape of it.
# `# BL-107-RUST-INLINE-TESTS` is the interesting row: idiomatic Rust unit
# tests live INSIDE the implementation file, invisible to any path-only
# classifier, and the original gate carries a content probe for exactly that.
# Dropping it here would report every inline-tested Rust file as untested — a
# large, confident, wrong number.

# _scout_is_test_file PATH — extracted verbatim from the BL-072 classifier's
# test-file predicate. Path-only, deliberately: a content-aware rule could not
# be applied identically by the original's two callers, and the copy keeps the
# property so the two stay comparable.
_scout_is_test_file() {
  local p="$1" base
  base="${p##*/}"
  case "$p" in
    tests/*|*/tests/*)         return 0 ;;
    test/*|*/test/*)           return 0 ;;
    __tests__/*|*/__tests__/*) return 0 ;;
    spec/*|*/spec/*)           return 0 ;;
  esac
  case "$base" in
    *_test.go)                                            return 0 ;;
    *.test.ts|*.test.tsx|*.test.js|*.test.jsx|*.test.mjs) return 0 ;;
    *.spec.ts|*.spec.tsx|*.spec.js|*.spec.jsx)            return 0 ;;
    test_*.py|*_test.py)                                  return 0 ;;
    *Test.kt|*Test.java|*Tests.kt|*Tests.java)            return 0 ;;
    *Spec.kt|*Spec.groovy|*Spec.scala)                    return 0 ;;
    *_test.rb|*_spec.rb)                                  return 0 ;;
    *_test.rs)                                            return 0 ;;
    *_test.sh|*-test.sh|test-*.sh)                        return 0 ;;
  esac
  return 1
}

# _scout_is_impl_file PATH — extracted from the BL-072 implementation
# predicate: not a test, and not under one of the exempt trees or shapes.
_scout_is_impl_file() {
  local p="$1" base
  base="${p##*/}"
  _scout_is_test_file "$p" && return 1
  case "$p" in
    docs/*|*/docs/*)       return 1 ;;
    .github/*)             return 1 ;;
    .claude/*|*/.claude/*) return 1 ;;
    Reports/*)             return 1 ;;
    templates/*)           return 1 ;;
    scripts/lint-*.sh)     return 1 ;;
    *.md)                  return 1 ;;
  esac
  case "$base" in
    package-lock.json)   return 1 ;;
    yarn.lock)           return 1 ;;
    *.lock)              return 1 ;;
  esac
  return 0
}

# _scout_is_source_ext PATH — THE ONE NARROWING, AND WHY IT IS HERE.
#
# The original classifies a DIFF, where a changed `package.json` or a
# regenerated lockfile is legitimately implementation that shipped. This
# section takes a CENSUS OF A TREE, and in a census `package.json`,
# `pnpm-lock.yaml` and `Cargo.toml` are not source files — counting them would
# inflate `totalSourceFiles` and make `untestedSourceFiles` a number about
# manifests. A file is source here only if its extension names a programming
# language, which is the same table the `stack` section counts languages with,
# so the two sections cannot disagree about what a source file is.
_scout_is_source_ext() {
  local base ext
  base="${1##*/}"
  case "$base" in *.*) ext=$(printf '%s' "${base##*.}" | tr 'A-Z' 'a-z') ;; *) return 1 ;; esac
  _scout_lang_table | grep -q "^$ext " 2>/dev/null
}

# _scout_has_inline_tests FILE — `# BL-107-RUST-INLINE-TESTS`, re-aimed from a
# staged diff to file content.
#
# The gate's version greps the ADDED lines of a staged `.rs` diff for a test
# attribute; there is no diff at scan time, so the copy asks the same question
# of the file itself. The attribute family is carried across unchanged: std
# `#[test]` / `#[cfg(test)]` / `#![cfg(test)]` / `cfg(all(test,…))` /
# `cfg(any(test,…))`, the runtime family (anything `::test]` — tokio, async_std,
# actix_rt, googletest), and the popular harness macros.
_scout_has_inline_tests() {
  case "$1" in *.rs) ;; *) return 1 ;; esac
  grep -qE '#!?\[(test|cfg\((all\(|any\()?test|([A-Za-z_][A-Za-z0-9_]*::)+test\]|rstest|wasm_bindgen_test|quickcheck|proptest)' \
    "$1" 2>/dev/null
}

# _scout_run_test_command ROOT WORK CMD — run it, bounded. Writes testrc,
# testdur and (on expiry) testtimedout into WORK.
#
# THE BOUND IS HAND-ROLLED ON PURPOSE. There is no portable `timeout` binary —
# it is absent from a stock macOS, and wrapping a command in one that does not
# exist yields a command-not-found that reads exactly like a real timeout. So
# the command is backgrounded in its own PROCESS GROUP (`set -m`), a sentinel
# file records its exit status the moment it finishes, and the group is
# signalled on expiry. The sentinel is what makes completion detectable: a
# finished-but-unreaped child still answers `kill -0`, so polling liveness
# alone would wait out the full timeout on every fast test suite.
#
# HONEST LIMIT: the group kill reaches the processes the command started, not
# anything it deliberately detached. A test suite that daemonises something is
# beyond a scanner's reach, and this bound does not claim otherwise.
_scout_run_test_command() {
  local root="$1" work="$2" cmd="$3"
  local _to _start _end _pid _waited
  _to="${SCOUT_TEST_TIMEOUT:-300}"
  case "$_to" in ''|*[!0-9]*) _to=300 ;; esac
  rm -f "$work/testrc" "$work/testtimedout" 2>/dev/null
  _start=$(date +%s)

  set -m 2>/dev/null
  ( cd "$root" 2>/dev/null || { printf '127\n' > "$work/testrc"; exit 127; }
    sh -c "$cmd" >/dev/null 2>&1
    printf '%s\n' "$?" > "$work/testrc" ) >/dev/null 2>&1 &
  _pid=$!
  set +m 2>/dev/null

  _waited=0
  while [ ! -f "$work/testrc" ]; do
    if [ "$_waited" -ge "$_to" ]; then
      kill -TERM -"$_pid" 2>/dev/null || kill -TERM "$_pid" 2>/dev/null
      sleep 1
      kill -KILL -"$_pid" 2>/dev/null || kill -KILL "$_pid" 2>/dev/null
      printf '1\n' > "$work/testtimedout"
      break
    fi
    kill -0 "$_pid" 2>/dev/null || break
    sleep 1
    _waited=$((_waited + 1))
  done
  wait "$_pid" 2>/dev/null
  _end=$(date +%s)
  printf '%s\n' "$((_end - _start))" > "$work/testdur"
  return 0
}

# scout_testsbaseline_scan ROOT WORK RUN_TESTS — fills WORK with the section.
#
# Writes:
#   tbran      1|0        whether the command was executed
#   tbreason   the sentence explaining a 0
#   tbrc       the exit code, or empty
#   tbdur      seconds, or empty
#   tbtimeout  1|0
#   tbtotal / tbtests / tbuntested   the census
scout_testsbaseline_scan() {
  local root="$1" work="$2" run="$3"
  local cmd="" src total=0 ntest=0 nuntested=0 stem base tested

  : > "$work/tbreason"; : > "$work/tbrc"; : > "$work/tbdur"
  printf '0\n' > "$work/tbran"
  printf '0\n' > "$work/tbtimeout"
  scout_testsbaseline_parity carried    > "$work/tbcarried"
  scout_testsbaseline_parity simplified > "$work/tbsimplified"

  # The test command is REUSED, not re-derived: the stack section already
  # found it and recorded where it came from. Two derivations of one fact are
  # two chances to disagree about it.
  [ -s "$work/testcmd" ] && cmd=$(cut -f1 < "$work/testcmd")

  # ── The census ───────────────────────────────────────────────────────────
  : > "$work/tbimpl"
  : > "$work/tbtestnames"
  while IFS= read -r src; do
    [ -n "$src" ] || continue
    _scout_is_source_ext "$src" || continue
    if _scout_is_test_file "$src"; then
      base="${src##*/}"
      printf '%s\n' "$base" >> "$work/tbtestnames"
      ntest=$((ntest + 1))
    elif _scout_is_impl_file "$src"; then
      printf '%s\n' "$src" >> "$work/tbimpl"
      total=$((total + 1))
    fi
  done < "$work/files"

  while IFS= read -r src; do
    [ -n "$src" ] || continue
    if _scout_has_inline_tests "$root/$src"; then continue; fi
    base="${src##*/}"
    stem="${base%.*}"
    tested=0
    if [ -n "$stem" ] && [ -s "$work/tbtestnames" ]; then
      grep -qF -- "$stem" "$work/tbtestnames" 2>/dev/null && tested=1
    fi
    [ "$tested" -eq 0 ] && nuntested=$((nuntested + 1))
  done < "$work/tbimpl"

  printf '%s\n' "$total"     > "$work/tbtotal"
  printf '%s\n' "$ntest"     > "$work/tbtests"
  printf '%s\n' "$nuntested" > "$work/tbuntested"

  # ── The run, or the reason there wasn't one ──────────────────────────────
  if [ -z "$cmd" ]; then
    printf '%s\n' "No test command could be detected, so there was nothing to run. Scout looks for a declared command first (package.json scripts.test, a Makefile test target) and falls back to a language convention only when the project has not said." \
      > "$work/tbreason"
    return 0
  fi
  if [ "$run" != "1" ]; then
    printf '%s\n' "--run-tests was not given, so Scout did not execute anything. This is the only part of Scout that would run your project's own code, and it stays off until you ask for it: a scanner that runs an unknown repository's test command by default is a trap, not a convenience." \
      > "$work/tbreason"
    return 0
  fi

  _scout_run_test_command "$root" "$work" "$cmd"
  printf '1\n' > "$work/tbran"
  [ -f "$work/tbdur" ] || : > "$work/tbdur"
  [ -f "$work/testdur" ] && cp "$work/testdur" "$work/tbdur"
  if [ -f "$work/testtimedout" ]; then
    printf '1\n' > "$work/tbtimeout"
    printf '%s\n' "The command was still running after ${SCOUT_TEST_TIMEOUT:-300}s and was stopped, so there is no exit code to report. Raise SCOUT_TEST_TIMEOUT if this suite is legitimately that slow." \
      > "$work/tbreason"
  elif [ -f "$work/testrc" ]; then
    head -1 "$work/testrc" > "$work/tbrc"
    printf '%s\n' "Run once, with its output discarded rather than captured — test output is free text and free text is where a credential ends up." \
      > "$work/tbreason"
  fi
  return 0
}

# scout_testsbaseline_parity WHICH — the classifierParity ledger, one line per
# entry. WHICH is `carried` or `simplified`.
#
# DATA, NOT PROSE IN A COMMENT, because §8.2 asks for the statement to be IN
# THE REPORT: the person reading `untestedSourceFiles: 137` is the person who
# needs to know the classifier was copied and where the copy diverges.
scout_testsbaseline_parity() {
  case "$1" in
    carried)
      cat <<'CARRIED'
The path-only test-file predicate: the tests/, test/, __tests__/ and spec/ trees, plus the per-language naming conventions (*_test.go, *.test.ts, *.spec.js, test_*.py, *Test.java, *_spec.rb, *_test.rs, test-*.sh).
The implementation-file exclusions: docs/, .github/, .claude/, Reports/, templates/, scripts/lint-*.sh, every *.md anywhere, and generated lockfiles.
The BL-107 Rust inline-test attribute family, so a file whose only tests are #[cfg(test)] blocks is not reported as untested.
CARRIED
      ;;
    simplified)
      cat <<'SIMPLIFIED'
The git name-status entry point is gone: this is a census of a working tree, not a diff, so the pure-deletion carve-out and the rename/copy path have nothing to apply to.
The branch axis (a second look at base...HEAD for a test that rode earlier) is gone: there is no branch under review at scan time.
A source-extension gate was ADDED, which the original does not have: the original reads a diff, where package.json and a lockfile are legitimately implementation, and a tree census that counted them as source files would make the untested figure a number about manifests.
The BL-107 probe reads FILE CONTENT rather than the added lines of a staged diff, which is the same question asked of a tree instead of a change.
SIMPLIFIED
      ;;
  esac
}

# scout_testsbaseline_method — the sentence that keeps the number honest.
scout_testsbaseline_method() {
  printf '%s' "An implementation file counts as untested when no test file's NAME contains its basename stem and it carries no inline test attribute. This is a name-match heuristic, not coverage: it cannot see a test that exercises a file without naming it, and it will call a file tested on a coincidental name match. It is a starting figure for the interview, never a coverage number."
}
