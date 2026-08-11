#!/usr/bin/env bash
# scripts/lib/adopt/adopt-test-debt.sh — the TEST-DEBT LEDGER and its TIER
# RATCHET: kind (c)'s forward equivalent.
#
# SPEC: docs/designs/2026-08-02-brownfield-adoption-v1.md §5.4 (the ledger, the
# two arms, the three honest limits), §5 (the per-gate mapping: TDD ordering on
# pre-adoption commits is kind (c) — impossible to re-run — so what is enforced
# instead is this), §10-WP5b. The standing module rules are
# docs/module-contract.md.
#
# ─────────────────────────────────────────────────────────────────────────────
# WHAT THIS IS FOR, IN ONE PARAGRAPH.
#
# An adopted project's history was written before the framework existed, so the
# TDD-ordering gate cannot judge it: there is no re-runnable fact about whether
# a 2023 commit put its test first. Bare grandfathering would stop there and
# exempt the code forever. Instead the adoption measures the debt ONCE — the
# set of source files that have no test — writes it down, and from that day
# enforces two things that ARE about the future: the set may not GROW, and a
# file in the set that you TOUCH must leave it.
#
# ─────────────────────────────────────────────────────────────────────────────
# M1/M3 — THIS IS MODULE CODE AND IT ADDS NO ENTRY SCRIPT.
#
# The adopt module's one entry script is still scripts/adopt-project.sh, which
# sources this file. No path outside scripts/lib/adopt/ names it, so M3's
# `core -> module` prohibition holds by construction and
# scripts/lint-module-dependencies.sh stays rc 0 — the ratchet is therefore NOT
# reachable from scripts/pre-commit-gate.sh, and that is deliberate rather than
# incidental. It runs FROM the framework clone against an adoptee, the same way
# Scout and the driver do:
#
#   bash /path/to/solo-orchestrator/scripts/lib/adopt/adopt-test-debt.sh \
#        --check --root /path/to/their-project
#
# WHAT THAT LEAVES UNDONE, SAID PLAINLY: nothing yet CALLS this on every
# commit. §10 gives WP7 the commit-time hook and names no owner for the
# fallback pre-commit hook on the adoption path (see adopt_stub_hooks), so
# until that lands the arms are a command an operator or a CI step runs, not an
# automatic gate. The alternative — reaching into scripts/pre-commit-gate.sh —
# is the exact edge M3 exists to make red, and severability is not worth
# trading for one convenience call.
#
# ─────────────────────────────────────────────────────────────────────────────
# THE TIER READ FAILS CLOSED, AND `## BL-221:` IS THE REASON IT IS SPELLED THIS
# WAY.
#
# The tier is READ, never re-derived: `# BL-084-TIER-KEY` is a sync-sibling
# predicate already spelled four times (pre-commit-gate.sh, check-phase-gate.sh,
# init.sh, scripts/lib/enforcement-level.sh) and a fifth spelling would be a
# defect the moment it landed. So this consumes the two existing accessors:
#
#   read_enforcement_level  — fails CLOSED: a missing manifest, an unparseable
#                             one, a missing key or a value off the ladder all
#                             return `strict`.
#   assert_choosable        — fails OPEN, and that is the live bug `## BL-221:`
#                             filed: `jq -r '.deployment // "personal"'` makes
#                             an ABSENT key resolve to the CHOOSABLE tier, and
#                             an adopted manifest has no `deployment` key at
#                             all.
#
# The composition is RAISE-ONLY: assert_choosable can push the tier UP to
# strict and can never pull it down. A false "choosable" therefore buys
# nothing, because the tier it would have permitted is whatever
# read_enforcement_level already returned — and that reader fails closed. On
# top of that, a `choosable` verdict is only allowed to stand when the key it
# is derived from is actually PRESENT (`# BF-TD-TIER-KEY-PRESENT`); an absent
# or null `deployment` is treated as a tier we cannot trust, which is strict.
# This is a guard on absent data, not a re-implementation of the predicate: the
# deployment/poc_mode question is still answered entirely by assert_choosable.
#
# ─────────────────────────────────────────────────────────────────────────────
# THE TIER FLOOR IS CONSULTED FIRST, AND THAT ORDER IS LOAD-BEARING.
#
# A gate that fires at the lenient tier is as wrong as one that never fires. A
# ratchet that blocks a `poc_mode` project is not a stricter ratchet, it is a
# broken one, and it is the shape that teaches an operator to disable the whole
# framework (the false-FAIL doctrine this repo already paid for in
# BL-122/BL-149). So `no` returns before anything can refuse — before the git
# check, before the missing-ledger refusal, before either arm.
#
# The `[WARN]` label is cosmetic in this framework: check-phase-gate.sh's exit
# predicate is `if [ $issues -eq 0 ]`, so a "WARN" arm that increments `issues`
# blocks. The `light` tier here prints WARN lines and returns 0, and the tests
# assert the CODE, never the label.
#
# EXIT CODES — the two arms are distinguishable, the way
# pre-commit-gate.sh --emit-blocked-gate distinguishes its two message gates:
#
#   0  clean, or a tier that does not block
#   2  unusable — no ledger to ratchet against, no git repository, no jq
#   3  BLOCKED by NON-GROWTH   (the untested set gained a member)
#   4  BLOCKED by TOUCH-REPAYS (a ledgered file was modified without a test)
#
# When both arms fire the code is 3 and BOTH lists are printed: the code names
# the first arm, the transcript names everything.
#
# A MISSING LEDGER AT `strict` IS rc 2, NOT A PASS. §5.4 limit 2 concedes that
# the ledger is a committed file and can be edited — "you can route around the
# block, not around the record". Deleting it outright is not a quiet route
# around the block; it is a loud one, and it gets the same posture WP3 gave the
# adoption stamp's loss detection. At `light` the same absence warns; at `no`
# it is silent, because the floor was consulted first.
#
# ─────────────────────────────────────────────────────────────────────────────
# NO awk ANYWHERE IN THIS FILE, DELIBERATELY. `bash -n` does not syntax-check
# an embedded program, so a dead one emits an empty result and empty reads as
# "nothing wrong" — a mutant can then pass every harness check while doing
# nothing. grep, sed, tr and shell only; the failure mode is removed rather
# than defended against, and the suite pins the property.
#
# ─────────────────────────────────────────────────────────────────────────────
# THREE BEHAVIOURS THAT ARE DECISIONS, NOT ACCIDENTS. Each is pinned by a test,
# because an undocumented edge in a blocking gate becomes a bug report about
# the framework rather than about the edge.
#
# 1. `git -c core.quotePath=false` ON EVERY GIT READ. Without it git renders a
#    non-ASCII path as `"src/caf\303\251.js"` — quotes included — and that
#    string has no recognised source extension, so the file drops out of the
#    census silently and neither arm can ever see it. Measured on a fixture
#    before the flag was added: `src/café.js` was untested and absent from the
#    ledger. Paths containing a literal TAB or NEWLINE are still beyond this
#    (the name-status reader splits on tabs), the same bound the BL-072 gate
#    has.
#
# 2. A PURE RENAME (`R100`) OF A LEDGERED FILE PASSES, WITH A `[NOTE]`. Neither
#    arm's rule is met — the set gained no member and nothing was modified — and
#    an earlier cut that blocked it produced a trap worth recording: the block
#    fired as non-growth on the new path, re-baselining then put the new path in
#    the ledger, and the SAME staged rename immediately blocked again as
#    touch-repays. There was no way out of that loop except writing a test for a
#    file the operator had only moved, which is exactly the false-FAIL that
#    teaches people to switch a gate off. It also blocked renames of TESTED
#    files, because the new stem stopped matching the test's name. So the rename
#    passes — and, because a rename is the one way debt can leave the ledger
#    without being paid, the run says so and tells you to re-baseline. A rename
#    that ALSO changes content (`R090`) is a modification and does owe a test,
#    at the new path.
#
# 3. THE INLINE-TEST PROBE READS THE WORKING TREE, not the staged blob. For the
#    census that is the only file there is. For the arms it means a `.rs` file
#    staged WITH its `#[cfg(test)]` block and then stripped in the worktree
#    reads as tested. The gate's own copy of the probe reads the staged diff;
#    this one cannot, because the same function serves a census that has no
#    diff to read.
#
# bash-3.2 safe: no ${var,,}, no associative arrays, no mapfile, no nullglob,
# no ((x++)) (this file may be sourced into a caller running under errexit).
# shellcheck shell=bash

TD_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TD_CORE_LIB_DIR="$(cd "$TD_SELF_DIR/.." && pwd)"
TD_FRAMEWORK_ROOT="$(cd "$TD_CORE_LIB_DIR/../.." && pwd)"

# M3 direction: module -> core, which is permitted. Sourced defensively so the
# file works both ways — the driver declares all three libs in its own M2 header
# and sources them first, and a direct invocation from a framework clone has to
# bring them in itself.
if ! command -v read_enforcement_level >/dev/null 2>&1; then
  # shellcheck disable=SC1090
  [ -f "$TD_CORE_LIB_DIR/enforcement-level.sh" ] && . "$TD_CORE_LIB_DIR/enforcement-level.sh"
fi
if ! command -v _bl072_is_impl_file >/dev/null 2>&1; then
  # shellcheck disable=SC1090
  [ -f "$TD_CORE_LIB_DIR/tdd-classify.sh" ] && . "$TD_CORE_LIB_DIR/tdd-classify.sh"
fi
if ! command -v soif_parse_shipped_scripts >/dev/null 2>&1; then
  # shellcheck disable=SC1090
  [ -f "$TD_CORE_LIB_DIR/scaffold-shipped-set.sh" ] && . "$TD_CORE_LIB_DIR/scaffold-shipped-set.sh"
fi

TD_LEDGER_REL=".claude/test-debt.json"
TD_TMP=""

# TD_GIT — EVERY git read in this file goes through these two `-c` settings, and
# both of them are load-bearing rather than tidy. A user's own `.gitconfig` is
# input to this tool, and a fix a user's config can silently disable is not a
# fix.
#
#   core.quotePath=false   without it git renders a non-ASCII path as
#                          `"src/caf\303\251.js"` — quotes included — which has
#                          no recognised source extension, so the file drops out
#                          of the census in silence.
#   diff.renames=true      `diff.renames=copies` made a COPIED untested file
#                          arrive as `C100` and enter the working set at rc 0
#                          with zero output (the silent-bypass class);
#                          `diff.renames=false` made a pure rename arrive as
#                          `D`+`A` and resurrected the rename loop verbatim
#                          (rc 3, re-baseline, rc 4). Both measured. Pinning to
#                          `true` forces rename detection ON and copy detection
#                          OFF, which is why nothing below matches a `C` status:
#                          under this pin git cannot emit one, and a branch no
#                          fixture can reach is pinned by nothing.
#
# `-c` on the command line outranks repo, global and system config, so this
# cannot be overridden from the adoptee's side.
TD_GIT_CONF="-c core.quotePath=false -c diff.renames=true"

# ── The membership predicate ────────────────────────────────────────────────

# _td_is_source_ext PATH — THE ONE NARROWING over the BL-072 classifier, and
# the same one Scout's census makes for the same reason.
#
# `_bl072_is_impl_file` classifies a DIFF, where a changed package.json or a
# regenerated lockfile is legitimately implementation that shipped. This is a
# census of a TREE, and in a census a manifest is not source: counting it would
# make the untested figure a number about manifests, and then the non-growth
# arm would refuse `npm init`. The extension set is carried from the language
# table Scout's stack section counts languages with, so the ledger and the scan
# report cannot disagree about what a source file is.
#
# THE ARMS USE THIS TOO, not only the census. If the two disagreed about
# membership, adding a lockfile would block a strict project against a set the
# ledger never had it in.
_td_is_source_ext() {
  local base ext
  base="${1##*/}"
  case "$base" in *.*) ;; *) return 1 ;; esac
  ext="$(printf '%s' "${base##*.}" | tr 'A-Z' 'a-z')"
  case "$ext" in
    ts|tsx|mts|cts|js|jsx|mjs|cjs)      return 0 ;;
    py|rb|go|rs|java|kt|kts|swift)      return 0 ;;
    c|h|cc|cpp|cxx|hpp|hh|cs|php|scala) return 0 ;;
    sh|bash|zsh|lua|dart)               return 0 ;;
    ex|exs|erl|hs|clj|cljs)             return 0 ;;
    m|mm|r|pl|pm|sql|vue|svelte|tf)     return 0 ;;
  esac
  return 1
}

# ── The framework's own installed inventory ─────────────────────────────────
# _td_shipped_init — write the set of paths the adoption INSTALLS into an
# adoptee, DERIVED from init.sh's own `cp` lines through the shared parser
# (soif_parse_shipped_scripts) rather than duplicated here. Returns non-zero if
# it cannot be derived.
#
# WHY THIS EXISTS AND WHAT IT REPLACED. The first cut of this module kept the
# framework's ~60 scripts out of the ledger by TIMING: the census reads
# `git ls-files`, and at adoption time those files were copied but not yet
# tracked. That is not a defence, it is a coincidence with a schedule — and
# every write AFTER the adoption commit was exposed. Worse, this tool actively
# instructs the operator to perform one (the rename [NOTE] and the rc-2 refusal
# both print `--write --root .`). Measured on a real driver run: the ledger held
# 1 entry and 0 framework scripts at adoption, and 58 entries with 57 of the
# framework's own scripts after running the advertised command — after which
# touch-repays demanded tests for check-gate.sh and check-phase-gate.sh on any
# framework sync. The tool told the user to break themselves.
#
# The exclusion is applied in _td_is_candidate, so it binds the CENSUS and BOTH
# ARMS from one place. A later framework sync that adds a script is therefore
# not growth either.
#
# HONEST COST: an adoptee that legitimately owns a file at a framework path
# (their own `scripts/validate.sh`, say) has it excluded from their debt. That
# path is a COLLISION and belongs to WP6; the driver already refuses to
# overwrite it. The trade is a small under-count against a large false-FAIL, and
# it is taken in the direction that does not teach an operator to switch the
# gate off.
# EACH OF THE THREE GUARDS BELOW IS A REFUSAL, AND EACH HAS ITS OWN FIXTURE.
# A reviewer flipped `|| return 1` to `|| return 0` on the init.sh guard — one
# character — and the whole suite stayed at 50/0, because no fixture ever ran
# this module from an incomplete clone. The mutant WROTE a ledger with the
# exclusion silently inert, which is precisely the guessing the fix that
# introduced these lines advertised as foreclosed. The lesson is the one this
# file already states twice about matcher atoms, turned on the refusal itself:
# a branch no fixture can reach is pinned by nothing. Section R's rows reach all
# three, and no repo lint executes this module, so a test is the only backstop.
_td_shipped_init() {
  : > "$TD_TMP/shipped"
  command -v soif_parse_shipped_scripts >/dev/null 2>&1 || return 1   # BF-TD-SHIPPED-PARSER
  [ -f "$TD_FRAMEWORK_ROOT/init.sh" ] || return 1                     # BF-TD-SHIPPED-REQUIRED
  soif_parse_shipped_scripts "$TD_FRAMEWORK_ROOT/init.sh" "$TD_FRAMEWORK_ROOT/scripts" > "$TD_TMP/shipped" 2>/dev/null
  [ -s "$TD_TMP/shipped" ] || return 1                                # BF-TD-SHIPPED-NONEMPTY
  return 0
}

# _td_is_framework_path PATH — is this one of the files the adoption installs?
_td_is_framework_path() {
  [ -s "$TD_TMP/shipped" ] || return 1
  grep -qxF -- "$1" "$TD_TMP/shipped" 2>/dev/null
}

# _td_is_candidate PATH — a file the ledger and both arms can be about.
_td_is_candidate() {
  _bl072_is_impl_file "$1" || return 1
  _td_is_source_ext "$1"  || return 1
  _td_is_framework_path "$1" && return 1   # BF-TD-FRAMEWORK-EXCLUDE
  return 0
}

# _td_has_inline_tests FILE — `# BL-107-RUST-INLINE-TESTS`, re-aimed from a
# staged diff to file content.
#
# SYNC SIBLINGS — the attribute family below is now spelled in THREE places and
# they must change together, the same hazard `# BL-084-TIER-KEY` names:
#   scripts/pre-commit-gate.sh          `_bl107_attr_re` — the original, over a
#                                       staged .rs diff's ADDED lines
#   scripts/lib/scout/scout-testsbaseline.sh  `_scout_has_inline_tests` — over
#                                       file content, M5 forbids sourcing
#   this file                           `_td_has_inline_tests` — over file
#                                       content, because a census has no diff
# Grep `BL-107-RUST-INLINE-TESTS` to find all three. A family that gains a macro
# in one copy and not the others reports a correctly-tested file as untested,
# and the touch-repays arm then blocks every edit to it.
#
# CARRIED, NOT SOURCED, and the copy is disclosed rather than hidden: the
# gate's version lives in scripts/pre-commit-gate.sh (not in the classifier
# lib, which is contractually a pure function of the path set) and greps the
# ADDED lines of a staged .rs diff. There is no diff to read when taking a
# census, so this asks the same question of the file itself — the same shape
# Scout's scanner arrived at independently. The attribute family is carried
# unchanged: std #[test] / #[cfg(test)] / #![cfg(test)] / cfg(all(test,…)) /
# cfg(any(test,…)), the runtime family (anything ::test] — tokio, async_std,
# actix_rt, googletest) and the popular harness macros.
#
# Dropping it would report every inline-tested Rust file as untested — a large,
# confident, wrong number — and the touch-repays arm would then block every
# edit to a correctly-tested file.
_td_has_inline_tests() {
  case "$1" in *.rs) ;; *) return 1 ;; esac
  grep -qE '#!?\[(test|cfg\((all\(|any\()?test|([A-Za-z_][A-Za-z0-9_]*::)+test\]|rstest|wasm_bindgen_test|quickcheck|proptest)' \
    "$1" 2>/dev/null
}

# _td_test_names ROOT — the basename of every test file in the INDEX.
#
# `git ls-files` reads the index, not the working tree, so a test file STAGED
# in the commit under review is already in this set. That is what lets the arms
# accept "the file arrived with its test in the same commit" without a second,
# differently-spelled lookup over the staged diff.
_td_test_names() {
  local p
  ( cd "$1" 2>/dev/null && git $TD_GIT_CONF ls-files 2>/dev/null ) | while IFS= read -r p; do
    [ -n "$p" ] || continue
    _bl072_is_test_file "$p" && printf '%s\n' "${p##*/}"
  done
  return 0
}

# _td_has_test ROOT PATH NAMESFILE — the name-match heuristic, stated as such.
#
# §5.4 limit 1: "has a test" is not "is tested". This answers a filename /
# inline-marker question, not a coverage question, and a file with an empty
# test file satisfies it. That is deliberate — the framework has no coverage
# instrumentation in any language — and the ledger carries the sentence saying
# so, in the artefact, where the number is read.
_td_has_test() {
  local root="$1" p="$2" names="$3" base stem
  _td_has_inline_tests "$root/$p" && return 0
  base="${p##*/}"
  stem="${base%.*}"
  [ -n "$stem" ] || return 1
  [ -s "$names" ] || return 1
  grep -qF -- "$stem" "$names" 2>/dev/null && return 0
  return 1
}

# _td_in_ledger PATH FILE — exact whole-line membership, never a substring.
_td_in_ledger() {
  [ -s "$2" ] || return 1
  grep -qxF -- "$1" "$2" 2>/dev/null
}

# ── The census ──────────────────────────────────────────────────────────────
# _td_census ROOT NAMESFILE — every untested candidate in the INDEX, sorted.
#
# The population is `git ls-files`, i.e. TRACKED files, not the working tree.
# Two reasons, both measured rather than assumed: a working-tree walk would
# sweep node_modules and build output into the adoptee's "debt", and the
# adoption driver copies ~60 framework scripts into the project before it
# commits — a tree census taken after that install would file the framework's
# own gate scripts as the adoptee's untested code, and the touch-repays arm
# would then demand tests for them.
_td_census() {
  local root="$1" names="$2" p
  ( cd "$root" 2>/dev/null && git $TD_GIT_CONF ls-files 2>/dev/null ) > "$TD_TMP/all"
  : > "$TD_TMP/untested"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    _td_is_candidate "$p" || continue    # BF-TD-CENSUS-CANDIDATE
    _td_has_test "$root" "$p" "$names" && continue
    printf '%s\n' "$p" >> "$TD_TMP/untested"
  done < "$TD_TMP/all"
  sort "$TD_TMP/untested"
  return 0
}

# adopt_test_debt_method — the sentence that keeps the number honest, written
# INTO the artefact rather than into a design document nobody opens at 2am.
adopt_test_debt_method() {
  printf '%s' "A source file counts as untested when no test file's NAME contains its basename stem and it carries no inline test attribute. This is a name-match heuristic, not coverage: it cannot see a test that exercises a file without naming it, and it will call a file tested on a coincidental name match. An empty test file satisfies it. The framework has no coverage instrumentation in any language, and this ledger does not pretend otherwise."
}

# ── The tier ────────────────────────────────────────────────────────────────

# _td_severity TIER — the ladder, spelled ONCE, as data.
#
# Spelled once ON PURPOSE. Two copies of a tier ladder is the
# `# BL-084-TIER-KEY` sync-sibling trap in miniature, so the second mutation
# direction for the second arm is proved by a second FIXTURE, not by a second
# line. The `*` row is the fail-closed default and is reachable: an unknown
# tier is strict.
_td_severity() {
  case "$1" in
    no)     echo silent ;;   # BF-TD-FLOOR-NO
    light)  echo warn ;;     # BF-TD-FLOOR-LIGHT
    strict) echo block ;;    # BF-TD-FLOOR-STRICT
    *)      echo block ;;    # BF-TD-FLOOR-CLOSED
  esac
}

# _td_tier_trusted ROOT — may a `choosable` verdict stand?
#
# Only when the key it is derived from is PRESENT. assert_choosable resolves an
# absent `deployment` to "personal" (`## BL-221:`), and an adopted manifest has
# no `deployment` key, so without this the whole ladder would be decided by a
# default. The deployment/poc_mode question itself is still answered entirely
# by assert_choosable — this adds a presence check, not a fifth spelling.
_td_tier_trusted() {
  local root="$1" manifest="$root/.claude/manifest.json" deployment
  command -v jq >/dev/null 2>&1 || return 1
  command -v assert_choosable >/dev/null 2>&1 || return 1
  deployment="$(jq -r '.deployment // ""' "$manifest" 2>/dev/null)"
  case "$deployment" in ''|null) return 1 ;; esac
  assert_choosable "$root" >/dev/null 2>&1 || return 1
  return 0
}

# adopt_test_debt_tier ROOT — the effective tier: no | light | strict.
adopt_test_debt_tier() {
  local root="$1" tier
  if ! command -v read_enforcement_level >/dev/null 2>&1; then
    echo strict
    return 0
  fi
  tier="$(read_enforcement_level "$root")"
  if [ ! -f "$root/.claude/manifest.json" ]; then
    echo strict
    return 0
  fi
  # RAISE-ONLY: this branch can only make the tier stricter.
  if ! _td_tier_trusted "$root"; then   # BF-TD-TIER-KEY-PRESENT
    tier="strict"
  fi
  echo "$tier"
  return 0
}

# ── The ledger ──────────────────────────────────────────────────────────────

_td_write_body() {
  local root="$1"
  local ledger="$root/$TD_LEDGER_REL"
  local names count files_json prev audit action now sha json

  command -v jq >/dev/null 2>&1 || { echo "test-debt: jq is required to write the ledger." >&2; return 2; }
  ( cd "$root" 2>/dev/null && git rev-parse --verify --quiet HEAD >/dev/null 2>&1 ) || {
    echo "test-debt: '$root' is not a git repository with at least one commit." >&2
    return 2
  }

  # FAIL CLOSED AND LOUD. If the framework's own inventory cannot be derived,
  # the census cannot tell the adoptee's code from the framework's — and the
  # failure mode it prevents is a ledger full of the framework's gate scripts,
  # which then demands tests for them. Refusing is the only honest answer; the
  # previous version had no answer at all because it relied on timing.
  if ! _td_shipped_init; then
    echo "test-debt: could not derive the framework's installed inventory from $TD_FRAMEWORK_ROOT/init.sh." >&2
    echo "  Without it the census cannot tell your source from the framework's, and a ledger that" >&2
    echo "  names the framework's own scripts would demand tests for them. Run this from a complete clone." >&2
    return 2
  fi

  names="$TD_TMP/names"
  _td_test_names "$root" > "$names"
  _td_census "$root" "$names" > "$TD_TMP/ledgered"

  count="$(grep -c . "$TD_TMP/ledgered" 2>/dev/null)"
  case "$count" in ''|*[!0-9]*) count=0 ;; esac
  files_json="$(jq -R . < "$TD_TMP/ledgered" 2>/dev/null | jq -s . 2>/dev/null)"
  [ -n "$files_json" ] || files_json='[]'

  # §5.4 limit 2: the ledger is a committed file and can be edited — the same
  # property enforcement_level has. You can route around the block, not around
  # the record, so every write leaves a row carrying the count it replaced.
  prev="null"; audit="[]"; action="created"
  if [ -f "$ledger" ]; then
    prev="$(jq -r '.count // "null"' "$ledger" 2>/dev/null)"
    case "$prev" in ''|*[!0-9]*) prev="null" ;; esac
    audit="$(jq -c '.audit // []' "$ledger" 2>/dev/null)"
    [ -n "$audit" ] || audit="[]"
    action="rewritten"
  fi

  now="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"
  sha="$( cd "$root" 2>/dev/null && git rev-parse HEAD 2>/dev/null )"

  json="$(jq -n \
    --argjson files "$files_json" \
    --argjson audit "$audit" \
    --argjson prev  "$prev" \
    --argjson count "$count" \
    --arg now "$now" --arg sha "$sha" --arg action "$action" \
    --arg method "$(adopt_test_debt_method)" \
    '{schema: "test-debt/v1",
      writtenAt: $now,
      atCommit: $sha,
      method: $method,
      count: $count,
      files: $files,
      audit: ($audit + [{at: $now, action: $action, atCommit: $sha, previousCount: $prev, count: $count}])}' \
    2>/dev/null)"
  [ -n "$json" ] || { echo "test-debt: could not build the ledger." >&2; return 2; }

  # adopt_write_file records the path in the driver's write ledger, which is
  # what gets staged — explicitly, one file at a time, never `git add -A`. When
  # this runs standalone that function does not exist and the write is plain.
  if command -v adopt_write_file >/dev/null 2>&1; then
    printf '%s\n' "$json" | adopt_write_file "$root" "$TD_LEDGER_REL" || return 1
  else
    mkdir -p "$root/.claude" 2>/dev/null || { echo "test-debt: could not create $root/.claude" >&2; return 2; }
    printf '%s\n' "$json" > "$ledger" || { echo "test-debt: could not write $ledger" >&2; return 2; }
  fi
  TD_LAST_COUNT="$count"
  return 0
}

# adopt_test_debt_write ROOT — measure the debt and write .claude/test-debt.json.
#
# The temp directory is created and removed HERE rather than by a trap: this
# file is sourced into a driver that already owns an EXIT trap for its own work
# directory, and a second `trap … EXIT` would replace it and leak that
# directory.
TD_LAST_COUNT=0
adopt_test_debt_write() {
  local rc=0
  TD_TMP="$(mktemp -d "${TMPDIR:-/tmp}/td-write.XXXXXXXX" 2>/dev/null)" || return 2
  _td_write_body "$@" || rc=$?
  rm -rf "$TD_TMP"
  TD_TMP=""
  return $rc
}

# ── The ratchet ─────────────────────────────────────────────────────────────

# _td_unchanged_blobs ROOT — every staged path whose CONTENT did not change.
#
# git's raw format carries the pre- and post-image blob names, so an entry whose
# two SHAs are equal changed something OTHER than content — in practice a file
# mode. `chmod +x` on a ledgered file arrives as a plain `M` and used to owe a
# test, while `R100` — which rests on exactly the same fact, git saying the
# content is identical — did not. Two postures for one fact, and the `M` one was
# in the false-FAIL direction, so they are reconciled here rather than argued
# about in a comment.
#
# `--abbrev=40` because the default raw output abbreviates, and comparing two
# abbreviations is comparing prefixes.
_td_unchanged_blobs() {
  local root="$1" line meta path oldsha newsha st
  ( cd "$root" 2>/dev/null && git $TD_GIT_CONF diff --cached --raw --abbrev=40 2>/dev/null ) \
  | while IFS= read -r line; do
      case "$line" in :*) ;; *) continue ;; esac
      meta="${line%%	*}"
      path="${line#*	}"
      set -- $meta
      [ "$#" -ge 5 ] || continue
      oldsha="$3"; newsha="$4"; st="$5"
      # Renames carry TWO paths after the tab and are the other carve-out's
      # business; only same-path entries are read here.
      case "$st" in M|M[0-9]*|T|T[0-9]*) ;; *) continue ;; esac
      [ "$oldsha" = "$newsha" ] && printf '%s\n' "$path"
    done
  return 0
}

# _td_owes_repayment STATUS OLDPATH EFFPATH — is this staged entry a TOUCH of a
# ledgered file?
#
# `R100` is git's own statement that the content is byte-identical, so it is a
# MOVE and not a modification: the design's arm is "a file in the set that is
# MODIFIED must leave it", and a move modifies nothing. Below 100 the content
# did change, and then the obligation follows the file to its new path —
# otherwise `git mv` plus an edit would be a one-commit way to shed the
# obligation entirely, which is a worse hole than the one this closes.
#
# There is no `C` branch, and its ABSENCE is the pin: every git read in this
# file goes through `-c diff.renames=true`, which forces copy detection off, so
# git cannot emit a `C` status here. A branch no fixture can reach is pinned by
# nothing, and the config pin is what makes the reachable set small enough to
# pin completely.
_td_owes_repayment() {
  local status="$1" old="$2" eff="$3"
  case "$status" in
    R100) return 1 ;;
    R*)
      _td_in_ledger "$old" "$TD_TMP/ledgered" && return 0
      _td_in_ledger "$eff" "$TD_TMP/ledgered" && return 0
      return 1
      ;;
  esac
  # A mode-only change is not a modification — same fact as R100, same answer.
  _td_in_ledger "$eff" "$TD_TMP/unchanged" && return 1   # BF-TD-MODE-ONLY
  _td_in_ledger "$eff" "$TD_TMP/ledgered"
}

_td_check_body() {
  local root="$1"
  local ledger="$root/$TD_LEDGER_REL"
  local tier sev staged names status path extra eff n_grow n_touch n_moved moved_row

  tier="$(adopt_test_debt_tier "$root")"
  sev="$(_td_severity "$tier")"
  # THE FLOOR, FIRST. Everything below can refuse; at `no` nothing may.
  [ "$sev" = "silent" ] && return 0

  ( cd "$root" 2>/dev/null && git rev-parse --verify --quiet HEAD >/dev/null 2>&1 ) || {
    if [ "$sev" = "block" ]; then
      echo "[BLOCKED] test-debt: '$root' is not a git repository with a commit, so there is no staged set to judge."
      return 2
    fi
    echo "[WARN] test-debt: '$root' is not a git repository with a commit — the ratchet did not run."
    return 0
  }

  if [ ! -f "$ledger" ]; then
    if [ "$sev" = "block" ]; then
      echo "[BLOCKED] test-debt: $TD_LEDGER_REL is missing. A ratchet with no baseline is not a ratchet."
      echo "          Write one:  bash <framework>/scripts/lib/adopt/adopt-test-debt.sh --write --root ."
      return 2
    fi
    echo "[WARN] test-debt: $TD_LEDGER_REL is missing, so neither arm could run."
    return 0
  fi

  if ! _td_shipped_init; then
    if [ "$sev" = "block" ]; then
      echo "[BLOCKED] test-debt: the framework's own installed inventory could not be derived from init.sh,"
      echo "          so the census cannot tell your code from the framework's. Run this from a complete clone."
      return 2
    fi
    echo "[WARN] test-debt: the framework's installed inventory could not be derived — the arms did not run."
    return 0
  fi

  jq -r '.files[]? // empty' "$ledger" 2>/dev/null > "$TD_TMP/ledgered"
  names="$TD_TMP/names"
  _td_test_names "$root" > "$names"
  _td_unchanged_blobs "$root" > "$TD_TMP/unchanged"
  staged="$( cd "$root" 2>/dev/null && git $TD_GIT_CONF diff --cached --name-status 2>/dev/null )"   # BF-TD-STAGED-READ

  : > "$TD_TMP/grow"
  : > "$TD_TMP/touch"
  : > "$TD_TMP/moved"

  # ── Arm 1: NON-GROWTH — the untested set may not GAIN a member ────────────
  # ADDITIONS ONLY, and the word is the design's. A rename does not create a
  # member — the file was already in the repository under another name — so
  # R/C statuses are the other arm's business, and were measured producing two
  # false blocks here before this narrowing: renaming an untested file read as
  # growth, and renaming a TESTED file read as growth too, because the new
  # stem no longer matched its test's name. A pure deletion is carved out
  # upstream by _bl072_status_effective_path.
  #
  # `C` (copy) genuinely WOULD create a member — and the reason it is not
  # matched is the config pin, not an assumption. An earlier version of this
  # comment claimed git emits `C` only under `-C`; that is refuted:
  # `diff.renames=copies` in the adoptee's own .gitconfig makes porcelain emit
  # `C100`, and `git diff --cached` is porcelain. Measured — a copied untested
  # file entered the working set at rc 0 with zero output. Every read here is
  # now pinned to `-c diff.renames=true`, which forces copy detection OFF, so a
  # copy arrives as `A` and this arm catches it.
  #
  # `A[0-9]*` is NOT matched: git scores only `R` and `C`, so an `A` with a
  # score cannot occur and the branch would be unreachable — which is the very
  # shape a reviewer's `A|M` mutation exploited to survive a green suite.
  while IFS="$(printf '\t')" read -r status path extra; do
    [ -n "$status" ] || continue
    eff="$(_bl072_status_effective_path "$status" "$path" "$extra")"
    [ -z "$eff" ] && continue
    case "$status" in A) ;; *) continue ;; esac   # BF-TD-NONGROWTH-ADDITIONS-ONLY
    _td_is_candidate "$eff" || continue
    _td_in_ledger "$eff" "$TD_TMP/ledgered" && continue
    _td_has_test "$root" "$eff" "$names" && continue
    printf '%s\n' "$eff" >> "$TD_TMP/grow"    # BF-TD-NONGROWTH-ARM
  done <<TD_STAGED_ADDS
$staged
TD_STAGED_ADDS

  # ── Arm 2: TOUCH-REPAYS — a ledgered file that is modified must leave ─────
  # LEDGER-SCOPED, deliberately. Firing on every edit would be a coverage
  # mandate, and §5.4 limit 3 declines to write one: a burn-down rate is a
  # business decision, and a rate the operator cannot meet teaches them to
  # disable the gate.
  while IFS="$(printf '\t')" read -r status path extra; do
    [ -n "$status" ] || continue
    eff="$(_bl072_status_effective_path "$status" "$path" "$extra")"
    [ -z "$eff" ] && continue
    case "$status" in
      R*) _td_in_ledger "$path" "$TD_TMP/ledgered" && printf '%s -> %s\n' "$path" "$eff" >> "$TD_TMP/moved" ;;
    esac
    _td_owes_repayment "$status" "$path" "$eff" || continue
    _td_has_test "$root" "$eff" "$names" && continue
    printf '%s\n' "$eff" >> "$TD_TMP/touch"   # BF-TD-TOUCH-ARM
  done <<TD_STAGED_TOUCHES
$staged
TD_STAGED_TOUCHES

  n_grow="$(grep -c . "$TD_TMP/grow" 2>/dev/null)";  case "$n_grow"  in ''|*[!0-9]*) n_grow=0 ;;  esac
  n_touch="$(grep -c . "$TD_TMP/touch" 2>/dev/null)"; case "$n_touch" in ''|*[!0-9]*) n_touch=0 ;; esac
  n_moved="$(grep -c . "$TD_TMP/moved" 2>/dev/null)"; case "$n_moved" in ''|*[!0-9]*) n_moved=0 ;; esac

  # The stale-ledger NOTE, and why it is not a block. A pure rename of a
  # ledgered file is the one way debt can leave the ledger without being paid:
  # the recorded path stops existing and the new one was never recorded, so
  # touch-repays will never see that file again. Blocking would be wrong — the
  # design says the set may not GAIN a member and that a MODIFIED member must
  # leave, and a move is neither. Staying silent would be worse: it is a
  # laundering route with no trace. So it is said, and the run still passes.
  if [ "$n_moved" -gt 0 ]; then
    echo "[NOTE] test-debt: $n_moved ledgered file(s) were renamed. The ledger still names the old path(s):"
    while IFS= read -r moved_row; do [ -n "$moved_row" ] && echo "          $moved_row"; done < "$TD_TMP/moved"
    echo "          Re-baseline so the debt follows the file:  --write --root ."
  fi

  [ "$n_grow" -eq 0 ] && [ "$n_touch" -eq 0 ] && return 0

  _td_report "$sev" "$n_grow" "$n_touch"
  [ "$sev" = "block" ] || return 0
  [ "$n_grow" -gt 0 ] && return 3
  return 4
}

# _td_report SEVERITY N_GROW N_TOUCH — say what was found, once, in the tier's
# own voice. The label is presentation; the caller's exit code is the verdict.
_td_report() {
  local sev="$1" n_grow="$2" n_touch="$3" tag p
  if [ "$sev" = "block" ]; then tag="[BLOCKED]"; else tag="[WARN]"; fi
  if [ "$n_grow" -gt 0 ]; then
    echo "$tag test-debt (non-growth): $n_grow file(s) would ENTER the untested set."
    while IFS= read -r p; do [ -n "$p" ] && echo "          + $p"; done < "$TD_TMP/grow"
  fi
  if [ "$n_touch" -gt 0 ]; then
    echo "$tag test-debt (touch-repays): $n_touch ledgered file(s) were modified without gaining a test."
    while IFS= read -r p; do [ -n "$p" ] && echo "          ~ $p"; done < "$TD_TMP/touch"
  fi
  echo "          A test whose NAME carries the file's stem clears it; for Rust, inline #[cfg(test)] counts."
  if [ "$sev" = "block" ]; then
    echo "          This project's enforcement tier is strict, so this is a refusal, not a note."
  fi
  return 0
}

# adopt_test_debt_check ROOT — run both arms against the staged set.
adopt_test_debt_check() {
  local rc=0
  TD_TMP="$(mktemp -d "${TMPDIR:-/tmp}/td-check.XXXXXXXX" 2>/dev/null)" || return 2
  _td_check_body "$@" || rc=$?
  rm -rf "$TD_TMP"
  TD_TMP=""
  return $rc
}

# ── The driver's call site ──────────────────────────────────────────────────
# adopt_test_debt_record ROOT — write the ledger during an adoption and say
# what it recorded.
#
# It replaces a `NOT DONE` stub, so it is held to the standard that stub set:
# it states what was measured and what the number does NOT mean. An operator
# who reads "0 untested files" and hears "this project is covered" has been
# misled by the artefact, not by the heuristic.
adopt_test_debt_record() {
  local root="$1" rc=0
  if ! command -v adopt_head >/dev/null 2>&1; then
    adopt_test_debt_write "$root"
    return $?
  fi
  adopt_head "Measuring the test debt"
  adopt_test_debt_write "$root" || rc=$?
  if [ "$rc" -ne 0 ]; then
    adopt_note "The test-debt ledger could not be written; nothing has been recorded."
    return "$rc"
  fi
  adopt_note "$TD_LEDGER_REL records $TD_LAST_COUNT source file(s) with no test today."
  adopt_note "That set is the baseline: from here it may not grow, and a file in it that you"
  adopt_note "change has to leave it. It is a name-match count, not coverage — read the"
  adopt_note "'method' field in the file before you quote the number."
  return 0
}

# ── Direct invocation ───────────────────────────────────────────────────────
# The module's ENTRY SCRIPT is still scripts/adopt-project.sh; this block adds
# a command, not an entry point, and nothing in core reaches it. Until WP7's
# commit-time hook lands it is how the arms are actually run — the same posture
# adopt_stub_hooks takes for the checks that hook would carry ("run them by
# hand until it lands").
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -uo pipefail
  TD_MODE=""
  TD_ROOT="."
  TD_USAGE="Usage: adopt-test-debt.sh (--check | --write) [--root DIR]"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --check)   TD_MODE="check"; shift ;;
      --write)   TD_MODE="write"; shift ;;
      --root)    [ "$#" -ge 2 ] || { echo "$TD_USAGE" >&2; exit 2; }; TD_ROOT="$2"; shift 2 ;;
      --root=*)  TD_ROOT="${1#--root=}"; shift ;;
      -h|--help) echo "$TD_USAGE"; exit 0 ;;
      *)         echo "$TD_USAGE" >&2; exit 2 ;;
    esac
  done
  [ -n "$TD_MODE" ] || { echo "$TD_USAGE" >&2; exit 2; }
  TD_ROOT_ABS="$(cd "$TD_ROOT" 2>/dev/null && pwd)"
  [ -n "$TD_ROOT_ABS" ] || { echo "adopt-test-debt: '$TD_ROOT' is not a directory this can read." >&2; exit 2; }
  # THE TARGET GUARD, ON `--write` ONLY, and the asymmetry is deliberate.
  # `--write` creates a file in the target, and `--root .` run from a framework
  # clone would drop a ledger into the framework itself. `--check` writes
  # nothing, and running it from the mothership is legitimate, so it is not
  # guarded — the sibling entry scripts guard the CWD because they all write.
  # guard_target_not_in_framework (`# BL-199-TARGET-GUARD`) is the accessor that
  # checks the TARGET and ignores the cwd, which is exactly this shape; running
  # the tool FROM the clone against someone else's project is the documented
  # usage and must keep working.
  if [ "$TD_MODE" = "write" ]; then
    if [ -f "$TD_CORE_LIB_DIR/helpers-core.sh" ] && ! command -v guard_target_not_in_framework >/dev/null 2>&1; then
      # shellcheck disable=SC1090
      . "$TD_CORE_LIB_DIR/helpers-core.sh"
    fi
    if command -v guard_target_not_in_framework >/dev/null 2>&1; then
      guard_target_not_in_framework "$TD_ROOT_ABS" "$TD_FRAMEWORK_ROOT" || exit 1
    fi
  fi
  if [ "$TD_MODE" = "write" ]; then
    adopt_test_debt_write "$TD_ROOT_ABS"
    exit $?
  fi
  adopt_test_debt_check "$TD_ROOT_ABS"
  exit $?
fi
