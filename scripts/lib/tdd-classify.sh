# scripts/lib/tdd-classify.sh — BL-072 shared file-classification core.
#
# The TDD-ordering detector (Phase C1, WARN mode) must classify a set of
# changed paths into "implementation files" vs "test files" the SAME way in
# two places:
#   - the LIVE pre-commit gate    (scripts/pre-commit-gate.sh), fed by
#                                  `git diff --cached --name-only`
#   - the dogfood REPLAY tool     (tests/test-helpers/dogfood-bl072-replay.sh),
#                                  fed by `git diff-tree --no-commit-id
#                                  --name-only -r <sha>`
#
# Factoring the classifier into this one sourced library is a hard BL-072
# requirement: live and replay MUST agree byte-for-byte, otherwise the
# measured false-block rate would not describe the gate that would actually
# ship. Both callers source this file and call `_bl072_classify_paths`.
#
# IMPORTANT — the classifier is a pure function of the PATH SET only. It does
# NOT read diff content. This is deliberate: the replay's per-commit view
# (`git diff-tree`) is path-only, so a content-aware rule (e.g. a
# "pure-comment-only change" carve-out) could not be applied identically in
# both places. Pure-comment-only detection is therefore a documented C1
# limitation (see BL-072 in the backlog and the dogfood report). Because C1
# is WARN-only — the gate never blocks — over-counting comment-only commits
# is safe and simply shows up as false positives in the dogfood, which is the
# whole point of the measurement.
#
# shellcheck shell=bash
# bash-3.2 safe: no associative arrays, no mapfile, no ${var,,}, no ((x++)).

# _bl072_is_test_file <path>
# Returns 0 (true) if <path> is a test file — anything under a tests/ tree or
# matching a per-language test-file naming convention. Returns 1 otherwise.
_bl072_is_test_file() {
  local p="$1" base
  base="${p##*/}"
  case "$p" in
    tests/*|*/tests/*)         return 0 ;;
    test/*|*/test/*)           return 0 ;;
    __tests__/*|*/__tests__/*) return 0 ;;
    spec/*|*/spec/*)           return 0 ;;
  esac
  case "$base" in
    *_test.go)                                 return 0 ;;
    *.test.ts|*.test.tsx|*.test.js|*.test.jsx|*.test.mjs) return 0 ;;
    *.spec.ts|*.spec.tsx|*.spec.js|*.spec.jsx) return 0 ;;
    test_*.py|*_test.py)                        return 0 ;;
    *Test.kt|*Test.java|*Tests.kt|*Tests.java) return 0 ;;
    *Spec.kt|*Spec.groovy|*Spec.scala)         return 0 ;;
    *_test.rb|*_spec.rb)                        return 0 ;;
    *_test.rs)                                  return 0 ;;
    *_test.sh|*-test.sh|test-*.sh)             return 0 ;;
  esac
  return 1
}

# _bl072_is_impl_file <path>
# Returns 0 (true) if <path> is an implementation file: a modified/added file
# that is NOT a test file and NOT under one of the exempt trees
# (docs/, .github/, Reports/, templates/) and is NOT one of the exempt
# script shapes (scripts/lint-*.sh). Everything else counts as
# implementation — the classifier is deliberately broad; the dogfood measures
# how broad is too broad.
#
# BL-072 Phase C2 tightening (kills the measured false-positive classes from
# Reports/2026-07-10-bl072-warn-dogfood.md before the classifier can hard-block):
#   - ALL *.md anywhere (backlog, README, HANDOFF, CHANGELOG, notes …) are
#     documentation, never implementation — the C1 dogfood's single biggest FP
#     class was repo-root markdown misclassified as impl.
#   - lockfiles / generated dependency manifests (package-lock.json, *.lock,
#     yarn.lock) are machine-generated, not authored implementation.
# Pure-DELETION exclusion is NOT here (a path alone cannot say "deleted"); it
# lives in _bl072_classify_status, which reads git name-status.
_bl072_is_impl_file() {
  local p="$1" base
  base="${p##*/}"
  _bl072_is_test_file "$p" && return 1
  case "$p" in
    docs/*|*/docs/*)     return 1 ;;
    .github/*)           return 1 ;;
    Reports/*)           return 1 ;;
    templates/*)         return 1 ;;
    scripts/lint-*.sh)   return 1 ;;
    *.md)                return 1 ;;   # BL-072 C2: all markdown, anywhere
  esac
  case "$base" in
    package-lock.json)   return 1 ;;   # BL-072 C2: npm lockfile (generated)
    yarn.lock)           return 1 ;;   # BL-072 C2: yarn lockfile (generated)
    *.lock)              return 1 ;;   # BL-072 C2: Cargo.lock/poetry.lock/… (generated)
  esac
  return 0
}

# _bl072_classify_paths  (C1 back-compat entry point — path-list input)
# Reads a newline-separated changed-paths list on stdin and echoes a single
# line "IMPL:<n_impl> TEST:<n_test>" — the count of implementation files and
# the count of test files in the set. Blank lines are ignored.
#
# NOTE: a bare path list cannot express deletions, so this entry point cannot
# apply the pure-deletion carve-out. It is retained for backward compatibility
# (older callers that only have `--name-only`); the live gate and the replay
# both feed name-status via _bl072_classify_status below to get the C2
# deletion exclusion.
_bl072_classify_paths() {
  local line n_impl=0 n_test=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if _bl072_is_test_file "$line"; then
      n_test=$((n_test + 1))
    elif _bl072_is_impl_file "$line"; then
      n_impl=$((n_impl + 1))
    fi
  done
  printf 'IMPL:%s TEST:%s\n' "$n_impl" "$n_test"
}

# _bl072_status_effective_path <status> <path> <extra>
# Given one `git diff --name-status` record split on tabs, returns the path
# that should be classified, or empty for a pure deletion.
#   A<TAB>f / M<TAB>f          -> f
#   D<TAB>f  (or D100…)        -> ""   (pure deletion: no impl shipped)
#   R100<TAB>old<TAB>new       -> new  (the surviving file)
#   C100<TAB>old<TAB>new       -> new
# bash-3.2 safe.
_bl072_status_effective_path() {
  local status="$1" path="$2" extra="$3"
  case "$status" in
    D|D[0-9]*)   printf '' ; return 0 ;;
    R*|C*)       [ -n "$extra" ] && path="$extra" ;;
  esac
  printf '%s' "$path"
}

# _bl072_classify_status  (C2 primary entry point — name-status input)
# Reads `git diff --name-status` lines (STATUS<TAB>path[<TAB>newpath]) on stdin
# and echoes "IMPL:<n_impl> TEST:<n_test>". Pure DELETIONS (status D) are
# ignored — removing a source file is not shipping implementation, so a
# deletion-only commit must not trip the gate (a measured C1 false-positive
# class). Renames/copies classify the surviving (new) path.
_bl072_classify_status() {
  local status path extra eff n_impl=0 n_test=0
  while IFS="$(printf '\t')" read -r status path extra; do
    [ -z "$status" ] && continue
    eff=$(_bl072_status_effective_path "$status" "$path" "$extra")
    [ -z "$eff" ] && continue
    if _bl072_is_test_file "$eff"; then
      n_test=$((n_test + 1))
    elif _bl072_is_impl_file "$eff"; then
      n_impl=$((n_impl + 1))
    fi
  done
  printf 'IMPL:%s TEST:%s\n' "$n_impl" "$n_test"
}

# _bl072_impl_files  (name-status input)
# Reads `git diff --name-status` lines on stdin and echoes the effective path
# of every NON-deleted implementation file, one per line. Used to build the
# WARN/FAIL listing and the ledger `files` array — always clean paths (never
# STATUS-prefixed, never deleted paths).
_bl072_impl_files() {
  local status path extra eff
  while IFS="$(printf '\t')" read -r status path extra; do
    [ -z "$status" ] && continue
    eff=$(_bl072_status_effective_path "$status" "$path" "$extra")
    [ -z "$eff" ] && continue
    _bl072_is_impl_file "$eff" && printf '%s\n' "$eff"
  done
  return 0   # never let the loop's last non-impl `&&` leak a non-zero rc (set -e)
}
