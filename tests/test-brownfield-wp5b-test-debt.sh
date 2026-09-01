#!/usr/bin/env bash
# tests/test-brownfield-wp5b-test-debt.sh
#
# Brownfield adoption WP5b — THE TEST-DEBT LEDGER AND ITS TIER RATCHET.
# Design: docs/designs/2026-08-02-brownfield-adoption-v1.md §5.4 (the ledger,
# the two arms, the three honest limits), §5 (kind (c)'s forward equivalent),
# §10-WP5b (the acceptance rows), §3.3 / docs/module-contract.md (this is
# MODULE code: no core file may name it and the boundary lint must stay rc 0).
#
# ── WHAT THIS FILE ASSERTS ON ───────────────────────────────────────────────
# EXIT CODES, never printed labels. The `[WARN]`/`[FAIL]` text in this
# framework's gate scripts is cosmetic — check-phase-gate.sh's exit predicate
# is `if [ $issues -eq 0 ]`, so a "WARN" arm that increments `issues` BLOCKS
# and two arms printing identical text can have opposite outcomes. That
# mismatch hid two real scoring inversions in this repo, so printed strings
# appear here only as PATH DISCRIMINATORS: they prove WHICH path produced a
# code, never that a verdict was reached.
#
# ── BLOCKED FOR THE RIGHT REASON ────────────────────────────────────────────
# The ratchet distinguishes its two arms by exit code, the way
# `pre-commit-gate.sh --emit-blocked-gate` distinguishes its two message gates
# (3 = TDD ordering, 4 = Build Loop):
#
#   0  clean, or a tier that does not block
#   2  unusable: no ledger to ratchet against, or not a git repository
#   3  BLOCKED by NON-GROWTH   (the untested set gained a member)
#   4  BLOCKED by TOUCH-REPAYS (a ledgered file was modified without a test)
#
# Every blocking case below asserts 3 or 4, never "non-zero". A touch-repays
# fixture that blocked because the non-growth arm also fired would prove
# nothing about the arm under test.
#
# ── THE TWO NON-BLOCKING OUTCOMES ARE NOT THE SAME OUTCOME ──────────────────
# `light` warns and `no` is silent, and BOTH exit 0. Exit code alone therefore
# cannot tell them apart — nor can it tell either of them from an arm that
# never ran. So every non-blocking case carries a STRUCTURAL DISCRIMINATOR:
# `no` asserts ZERO BYTES on stdout and stderr combined, `light` asserts a
# WARN line that NAMES the offending path. "Silent" and "warned" are then
# distinguishable by bytes, not by hope.
#
# ── MUTATION HARNESS STANDARD (all mandatory, all learned in this wave) ─────
#   • anchored end-of-line markers, excised with `s|^.*MARKER$|…|`;
#   • the anchor asserted at sites==1 in its OWN shipped source;
#   • exactly-N-lines-changed asserted (a substitution is 2 diff lines);
#   • EVERY mutant additionally asserts `bash -n` — a mutation that lands
#     mid-continuation produces a mangled parse that reads as "caught";
#   • a MODE-PRESERVING in-place edit;
#   • a FRESH fixture per mutant, from `mktemp -d`, never a counter inside a
#     command substitution (a counter never survives the subshell, so every
#     scenario lands in the same directory — that is how one proof in this
#     wave came to pass against a NEIGHBOURING suite's fixture);
#   • a CONTROL beside every mutant: the same fixture against the UNMUTATED
#     mirror, asserted GREEN in the same run. A mutant killed with no control
#     cannot distinguish "the mutation broke the arm" from "the fixture never
#     worked";
#   • NO BACKSLASH ESCAPES IN A REPLACEMENT STRING. `\n` in the RHS of `s///`
#     is a newline to GNU sed and a literal `n` to BSD sed, so the same mutant
#     would change one line on macOS and two on Linux — and the
#     exactly-N-lines-changed assertion would then be a platform test. Every
#     replacement below is plain text.
#
# ── NO awk IN THE CODE UNDER TEST, DELIBERATELY ─────────────────────────────
# `bash -n` does not syntax-check awk: a dead awk program emits an empty
# result and empty reads as "nothing wrong", so an awk mutant can pass every
# harness check while doing nothing. scripts/lib/adopt/adopt-test-debt.sh
# drives no awk at all — grep, sed and shell only — which removes the failure
# mode rather than defending against it. M8 pins that property, so a later
# edit that introduces an awk pipeline has to argue with a test.
#
# Hermetic: temp dirs only, no network, no remote creation, no `--no-verify`.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/adopt/adopt-test-debt.sh"
DRIVER="$REPO_ROOT/scripts/adopt-project.sh"
CORE_ENF="$REPO_ROOT/scripts/lib/enforcement-level.sh"
CORE_TDD="$REPO_ROOT/scripts/lib/tdd-classify.sh"
CORE_SHIPPED="$REPO_ROOT/scripts/lib/scaffold-shipped-set.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }

_mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || printf '?\n'; }

_sed_inplace() {
  local file="$1" expr="$2" tmp mode
  mode="$(_mode_of "$file")"
  tmp="$(mktemp)"
  sed "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
  [ "$mode" != "?" ] && chmod "$mode" "$file" 2>/dev/null
  return 0
}

_changed_lines() {
  local n
  n=$(diff "$1" "$2" 2>/dev/null | grep -c '^[<>]')
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s\n' "$n"
}

_num() { case "$1" in ''|null|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac }
_parses() { bash -n "$1" >/dev/null 2>&1 && printf '1\n' || printf '0\n'; }

# _sites FILE MARKER — occurrences of an END-OF-LINE-anchored marker.
_sites() { local n; n=$(grep -c "$2\$" "$1" 2>/dev/null); _num "$n"; }

if [ ! -f "$LIB" ]; then
  echo "  [FAIL] setup — $LIB not found (WP5b deliverable 1 missing)"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

# ── The adoptee fixture ─────────────────────────────────────────────────────
# A real git repository with real history. `src/paid.js` HAS a test (the test
# file's name carries its stem) and `src/debt.js` does NOT, so a census has one
# of each and a proof that finds "everything untested" or "nothing untested" is
# distinguishable from a correct one.
#
# git identity is configured and GITHUB_BASE_REF is unset in every fixture git
# op: a CI environment that exports it changes what `git diff` resolves.
mk_repo() {
  local p="$1"
  mkdir -p "$p/src" "$p/tests" || return 1
  (
    unset GITHUB_BASE_REF
    cd "$p" \
      && git init -q . \
      && git config user.email "wp5b@test.invalid" \
      && git config user.name  "WP5b Test" \
      && git config commit.gpgsign false
  ) >/dev/null 2>&1 || return 1
  printf 'export function paid() { return 1; }\n' > "$p/src/paid.js"
  printf 'export function debt() { return 2; }\n' > "$p/src/debt.js"
  printf 'test("paid", () => {});\n'              > "$p/tests/paid.test.js"
  printf '{"name":"fixture"}\n'                   > "$p/package.json"
  printf '# fixture\n'                            > "$p/README.md"
  ( unset GITHUB_BASE_REF; cd "$p" && git add -A && git commit -q -m "chore: their own history" ) >/dev/null 2>&1 || return 1
  return 0
}

# gitq DIR ARGS… — a fixture git op with the environment neutralised.
gitq() { local d="$1"; shift; ( unset GITHUB_BASE_REF; cd "$d" && git "$@" ) >/dev/null 2>&1; }

# set_tier DIR JSON — write .claude/manifest.json verbatim.
set_tier() {
  local d="$1" json="$2"
  mkdir -p "$d/.claude" || return 1
  printf '%s\n' "$json" > "$d/.claude/manifest.json"
}

# ledger_of DIR — write the ledger by running the shipped writer.
LEDGER_RC=0
write_ledger() { local d="$1" lib="${2:-$LIB}"; LEDGER_RC=0; ( unset GITHUB_BASE_REF; cd "$d" && bash "$lib" --write --root "$d" ) >/dev/null 2>&1 || LEDGER_RC=$?; return 0; }

# check_in DIR [LIB] — run the ratchet. Sets CHK_RC and CHK_OUT (a FILE path,
# beside the fixture and never inside it: a scratch file in the repository
# would appear in the very `git status` the staged-set arms read).
#
# Called DIRECTLY, never inside `$( … )`: a command substitution is a subshell,
# so a helper that returns its transcript path through a global loses it on the
# way out and every later grep runs against an empty variable — which greps the
# wrong file, fails, and reads as a genuine assertion failure.
CHK_RC=0; CHK_OUT=""
check_in() {
  local d="$1" lib="${2:-$LIB}"
  CHK_RC=0
  CHK_OUT="$TOPTMP/chk-$$-$RANDOM"
  ( unset GITHUB_BASE_REF; cd "$d" && bash "$lib" --check --root "$d" ) > "$CHK_OUT" 2>&1 || CHK_RC=$?
  return 0
}

_bytes() { local n; n=$(wc -c < "$1" 2>/dev/null | tr -d ' '); _num "$n"; }

echo "=== A — the ledger (§5.4: the set of source files with no test) ==="

# A1/A2/A3/A4 share one census so the fixture is built once and read four ways.
A1D="$(newtmp)/p"
if ! mk_repo "$A1D"; then
  fail_ "A" "fixture setup failed"
else
  write_ledger "$A1D"
  a_rc=$LEDGER_RC
  a_file="$A1D/.claude/test-debt.json"
  a_json=0; [ -s "$a_file" ] && jq -e . "$a_file" >/dev/null 2>&1 && a_json=1
  a_debt=$(jq -r '[.files[] | select(. == "src/debt.js")] | length' "$a_file" 2>/dev/null)
  a_paid=$(jq -r '[.files[] | select(. == "src/paid.js")] | length' "$a_file" 2>/dev/null)
  a_pkg=$(jq -r '[.files[] | select(. == "package.json")] | length' "$a_file" 2>/dev/null)
  a_readme=$(jq -r '[.files[] | select(. == "README.md")] | length' "$a_file" 2>/dev/null)
  a_count=$(jq -r '.count // -1' "$a_file" 2>/dev/null)
  a_len=$(jq -r '.files | length' "$a_file" 2>/dev/null)
  if [ "$a_rc" -eq 0 ] && [ "$a_json" -eq 1 ] \
     && [ "$(_num "$a_debt")" -eq 1 ] && [ "$(_num "$a_paid")" -eq 0 ] \
     && [ "$(_num "$a_count")" = "$(_num "$a_len")" ]; then
    pass "A1: the ledger is written, is valid JSON, and records the untested file WITHOUT recording the tested one (count agrees with the array's length)"
  else
    fail_ "A1" "rc=$a_rc valid_json=$a_json debt_listed=$a_debt (want 1) paid_listed=$a_paid (want 0) count=$a_count files_len=$a_len"
  fi

  # A2 — the SOURCE-EXTENSION gate. `_bl072_is_impl_file` classifies a DIFF,
  # where a changed package.json is legitimately implementation that shipped.
  # This is a CENSUS OF A TREE, and in a census a manifest is not source: a
  # ledger that counted it would make the untested figure a number about
  # manifests, and the non-growth arm would then block on `npm init`.
  if [ "$(_num "$a_pkg")" -eq 0 ] && [ "$(_num "$a_readme")" -eq 0 ]; then
    pass "A2: the census gates on a SOURCE EXTENSION — package.json and README.md are not ledgered, so the ratchet cannot block a manifest edit"
  else
    fail_ "A2" "package.json_listed=$a_pkg (want 0) README.md_listed=$a_readme (want 0)"
  fi

  # A3 — the honest-limit sentence is IN THE ARTEFACT, not only in a design
  # document nobody opens at 2am. §5.4 limit 1: "has a test" is not "is tested".
  a_method=$(jq -r '.method // ""' "$a_file" 2>/dev/null)
  a_says=0
  case "$a_method" in *"not coverage"*|*"not a coverage"*) a_says=1 ;; esac
  if [ -n "$a_method" ] && [ "$a_says" -eq 1 ]; then
    pass "A3: the ledger carries its own method sentence and that sentence says it is not coverage (§5.4 limit 1, stated where the number is read)"
  else
    fail_ "A3" "method='$a_method' disclaims_coverage=$a_says (want 1)"
  fi

  # A4 — §5.4 limit 2: a ledger mutation writes an audit row. Re-running the
  # writer after the debt changes must leave a trail, not a silent overwrite.
  printf 'export function extra() { return 3; }\n' > "$A1D/src/extra.js"
  gitq "$A1D" add src/extra.js
  gitq "$A1D" commit -q -m "chore: one more untested file"
  write_ledger "$A1D"
  a4_rows=$(jq -r '.audit | length' "$a_file" 2>/dev/null)
  a4_prev=$(jq -r '.audit[-1].previousCount // -1' "$a_file" 2>/dev/null)
  a4_now=$(jq -r '.audit[-1].count // -1' "$a_file" 2>/dev/null)
  a4_count=$(jq -r '.count // -1' "$a_file" 2>/dev/null)
  if [ "$(_num "$a4_rows")" -eq 2 ] && [ "$(_num "$a4_prev")" -eq 1 ] \
     && [ "$(_num "$a4_now")" -eq 2 ] && [ "$(_num "$a4_count")" -eq 2 ]; then
    pass "A4: re-writing the ledger APPENDS an audit row carrying the count it replaced (§5.4 limit 2 — you can route around the block, not around the record)"
  else
    fail_ "A4" "audit_rows=$a4_rows (want 2) previousCount=$a4_prev (want 1) row_count=$a4_now (want 2) ledger_count=$a4_count (want 2)"
  fi
fi

# A5 — `# BL-107-RUST-INLINE-TESTS` parity. Idiomatic Rust unit tests live
# INSIDE the implementation file and are invisible to any path-only
# classifier. Dropping the probe here would report every inline-tested Rust
# file as untested — a large, confident, wrong number — and then the
# touch-repays arm would block every edit to a correctly-tested file.
A5D="$(newtmp)/p"
if ! mk_repo "$A5D"; then
  fail_ "A5" "fixture setup failed"
else
  mkdir -p "$A5D/rs"
  printf 'pub fn a() -> u8 { 1 }\n\n#[cfg(test)]\nmod t { #[test] fn works() { assert!(true); } }\n' > "$A5D/rs/inline.rs"
  printf 'pub fn b() -> u8 { 2 }\n' > "$A5D/rs/bare.rs"
  gitq "$A5D" add rs
  gitq "$A5D" commit -q -m "chore: rust"
  write_ledger "$A5D"
  a5_inline=$(jq -r '[.files[] | select(. == "rs/inline.rs")] | length' "$A5D/.claude/test-debt.json" 2>/dev/null)
  a5_bare=$(jq -r '[.files[] | select(. == "rs/bare.rs")] | length' "$A5D/.claude/test-debt.json" 2>/dev/null)
  if [ "$(_num "$a5_inline")" -eq 0 ] && [ "$(_num "$a5_bare")" -eq 1 ]; then
    pass "A5: the # BL-107-RUST-INLINE-TESTS content probe is carried — a file whose only tests are #[cfg(test)] is NOT ledgered, and its bare sibling is"
  else
    fail_ "A5" "inline_tested_listed=$a5_inline (want 0) bare_listed=$a5_bare (want 1)"
  fi
fi

echo ""
echo "=== B — the tier read (## BL-221: this must not fail OPEN) ==="

# The whole of section B is one fixture read many ways: the ratchet's verdict
# on an IDENTICAL staged change under different manifests. Everything that
# varies is the manifest, so a difference in outcome can only be the tier.
_b_fixture() {
  local p="$1"
  mk_repo "$p" || return 1
  write_ledger "$p"
  printf 'export function fresh() { return 9; }\n' > "$p/src/fresh.js"
  gitq "$p" add src/fresh.js
  return 0
}

# B1 — no manifest at all.
B1D="$(newtmp)/p"
if ! _b_fixture "$B1D"; then fail_ "B1" "fixture setup failed"; else
  check_in "$B1D"
  if [ "$CHK_RC" -eq 3 ]; then
    pass "B1: with NO manifest the tier is unreadable and the arm BLOCKS (rc 3) — absent data reads as strict, the direction the rest of this framework fails in"
  else
    fail_ "B1" "rc=$CHK_RC (want 3) out=$(head -3 "$CHK_OUT" | tr '\n' '|')"
  fi
fi

# B2 — a manifest with no enforcement_level key. This is EXACTLY the shape
# `scripts/adopt-project.sh` writes today: `## BL-221:` measured `deployment`,
# `poc_mode` and `enforcement_level` all absent from an adopted manifest.
B2D="$(newtmp)/p"
if ! _b_fixture "$B2D"; then fail_ "B2" "fixture setup failed"; else
  set_tier "$B2D" '{"host":"github","mode":"personal","remote_url":""}'
  check_in "$B2D"
  if [ "$CHK_RC" -eq 3 ]; then
    pass "B2: an ADOPTED manifest (no enforcement_level, no deployment — the shape ## BL-221: measured) blocks at rc 3 rather than defaulting permissive"
  else
    fail_ "B2" "rc=$CHK_RC (want 3) out=$(head -3 "$CHK_OUT" | tr '\n' '|')"
  fi
fi

# B3 — a manifest that is not JSON at all.
B3D="$(newtmp)/p"
if ! _b_fixture "$B3D"; then fail_ "B3" "fixture setup failed"; else
  set_tier "$B3D" 'this is not json {{{'
  check_in "$B3D"
  if [ "$CHK_RC" -eq 3 ]; then
    pass "B3: an UNPARSEABLE manifest blocks at rc 3 — an unreadable tier is strict, not silent"
  else
    fail_ "B3" "rc=$CHK_RC (want 3) out=$(head -3 "$CHK_OUT" | tr '\n' '|')"
  fi
fi

# B4 — a manifest whose enforcement_level is a value the ladder does not know.
B4D="$(newtmp)/p"
if ! _b_fixture "$B4D"; then fail_ "B4" "fixture setup failed"; else
  set_tier "$B4D" '{"deployment":"personal","poc_mode":"production","enforcement_level":"relaxed"}'
  check_in "$B4D"
  if [ "$CHK_RC" -eq 3 ]; then
    pass "B4: an enforcement_level OFF the ladder ('relaxed') blocks at rc 3 — an unrecognised tier is strict"
  else
    fail_ "B4" "rc=$CHK_RC (want 3) out=$(head -3 "$CHK_OUT" | tr '\n' '|')"
  fi
fi

# B5 — the BL-221 SHAPE ITSELF, and the reason this suite exists. The manifest
# names a lenient tier but carries NO `deployment` key. `assert_choosable`
# resolves an absent key to "personal" — the CHOOSABLE tier — which is the
# live fail-open. This ratchet must not inherit it: a choosable verdict is
# only allowed to stand when the key it is derived from is actually present.
B5D="$(newtmp)/p"
if ! _b_fixture "$B5D"; then fail_ "B5" "fixture setup failed"; else
  set_tier "$B5D" '{"host":"github","enforcement_level":"no"}'
  check_in "$B5D"
  if [ "$CHK_RC" -eq 3 ]; then
    pass "B5 (## BL-221: NOT INHERITED): a lenient enforcement_level with an ABSENT deployment key does NOT buy silence — rc 3, because a tier derived from a missing key is not a tier"
  else
    fail_ "B5" "rc=$CHK_RC (want 3) out=$(head -3 "$CHK_OUT" | tr '\n' '|')"
  fi
fi

# B6 — organizational. `assert_choosable` returns 1, so the tier is forced to
# strict no matter what the file says. The accessor is consumed, never
# re-derived: a fifth spelling of the # BL-084-TIER-KEY predicate is a defect
# the moment it lands.
B6D="$(newtmp)/p"
if ! _b_fixture "$B6D"; then fail_ "B6" "fixture setup failed"; else
  set_tier "$B6D" '{"deployment":"organizational","poc_mode":"production","enforcement_level":"no"}'
  check_in "$B6D"
  if [ "$CHK_RC" -eq 3 ]; then
    pass "B6: an ORGANIZATIONAL project cannot buy silence with enforcement_level:no — assert_choosable refuses and the tier is raised to strict (rc 3)"
  else
    fail_ "B6" "rc=$CHK_RC (want 3) out=$(head -3 "$CHK_OUT" | tr '\n' '|')"
  fi
fi

# B7 — the CONTROL for all of B, and the one that stops this section from
# being a test that cannot fail. A COMPLETE personal manifest at `no` must be
# SILENT. Without this row every B case above would also pass on a ratchet
# that blocks unconditionally.
B7D="$(newtmp)/p"
if ! _b_fixture "$B7D"; then fail_ "B7" "fixture setup failed"; else
  set_tier "$B7D" '{"deployment":"personal","poc_mode":"production","enforcement_level":"no"}'
  check_in "$B7D"
  b7_bytes=$(_bytes "$CHK_OUT")
  if [ "$CHK_RC" -eq 0 ] && [ "$b7_bytes" -eq 0 ]; then
    pass "B7 (control): a COMPLETE personal manifest at 'no' is silent and rc 0 — B1-B6 refuse a tier they cannot trust, they do not refuse everything"
  else
    fail_ "B7" "rc=$CHK_RC (want 0) output_bytes=$b7_bytes (want 0) out=$(head -3 "$CHK_OUT" | tr '\n' '|')"
  fi
fi

echo ""
echo "=== C — the NON-GROWTH arm (§10-WP5b: block at strict, warn at light, silent at no) ==="

_c_fixture() {
  local p="$1" level="$2"
  mk_repo "$p" || return 1
  write_ledger "$p"
  set_tier "$p" "{\"deployment\":\"personal\",\"poc_mode\":\"production\",\"enforcement_level\":\"$level\"}"
  printf 'export function fresh() { return 9; }\n' > "$p/src/fresh.js"
  gitq "$p" add src/fresh.js
  return 0
}

C1D="$(newtmp)/p"
if ! _c_fixture "$C1D" strict; then fail_ "C1" "fixture setup failed"; else
  check_in "$C1D"
  c1_named=0; grep -q 'src/fresh\.js' "$CHK_OUT" && c1_named=1
  if [ "$CHK_RC" -eq 3 ] && [ "$c1_named" -eq 1 ]; then
    pass "C1: adding an untested file BLOCKS at strict — rc 3 (the non-growth arm, not some other refusal) and the offending path is named"
  else
    fail_ "C1" "rc=$CHK_RC (want 3) path_named=$c1_named (want 1) out=$(head -5 "$CHK_OUT" | tr '\n' '|')"
  fi
fi

C2D="$(newtmp)/p"
if ! _c_fixture "$C2D" light; then fail_ "C2" "fixture setup failed"; else
  check_in "$C2D"
  c2_warn=0; grep -qi 'warn' "$CHK_OUT" && c2_warn=1
  c2_named=0; grep -q 'src/fresh\.js' "$CHK_OUT" && c2_named=1
  if [ "$CHK_RC" -eq 0 ] && [ "$c2_warn" -eq 1 ] && [ "$c2_named" -eq 1 ]; then
    pass "C2: the same commit WARNS at light and exits 0 — the warn arm does not increment anything that blocks, and it still names the file (the [WARN] trap, asserted as a code and a byte string, never as a label)"
  else
    fail_ "C2" "rc=$CHK_RC (want 0) warned=$c2_warn (want 1) path_named=$c2_named (want 1) out=$(head -5 "$CHK_OUT" | tr '\n' '|')"
  fi
fi

C3D="$(newtmp)/p"
if ! _c_fixture "$C3D" no; then fail_ "C3" "fixture setup failed"; else
  check_in "$C3D"
  c3_bytes=$(_bytes "$CHK_OUT")
  if [ "$CHK_RC" -eq 0 ] && [ "$c3_bytes" -eq 0 ]; then
    pass "C3: the same commit is SILENT at no — rc 0 AND zero bytes of output, which is what distinguishes 'silent' from 'warned' (both exit 0)"
  else
    fail_ "C3" "rc=$CHK_RC (want 0) output_bytes=$c3_bytes (want 0) out=$(head -5 "$CHK_OUT" | tr '\n' '|')"
  fi
fi

# C4 — the arm's CONTROL: an added file that DOES arrive with a test must
# pass at strict. Without this the arm could be "block on any addition" and
# every case above would still be green.
C4D="$(newtmp)/p"
if ! _c_fixture "$C4D" strict; then fail_ "C4" "fixture setup failed"; else
  printf 'test("fresh", () => {});\n' > "$C4D/tests/fresh.test.js"
  gitq "$C4D" add tests/fresh.test.js
  check_in "$C4D"
  if [ "$CHK_RC" -eq 0 ]; then
    pass "C4 (control): the SAME added file with its test in the SAME commit passes at strict (rc 0) — the arm blocks untested growth, not growth"
  else
    fail_ "C4" "rc=$CHK_RC (want 0) out=$(head -5 "$CHK_OUT" | tr '\n' '|')"
  fi
fi

# C5 — a NON-SOURCE addition. The census gates on a source extension (A2), and
# the arm must gate identically or the two disagree about what the untested
# set is: adding a lockfile would then block a strict project forever.
C5D="$(newtmp)/p"
if ! _c_fixture "$C5D" strict; then fail_ "C5" "fixture setup failed"; else
  gitq "$C5D" reset -q
  printf '{"lockfileVersion":3}\n' > "$C5D/package-lock.json"
  printf 'FROM scratch\n' > "$C5D/Dockerfile"
  gitq "$C5D" add package-lock.json Dockerfile
  check_in "$C5D"
  if [ "$CHK_RC" -eq 0 ]; then
    pass "C5: adding a lockfile and a Dockerfile does NOT block at strict — the arm's membership predicate is the census's, so the two cannot disagree about the untested set"
  else
    fail_ "C5" "rc=$CHK_RC (want 0) out=$(head -5 "$CHK_OUT" | tr '\n' '|')"
  fi
fi

# C6 — a DELETION is not growth. `_bl072_status_effective_path` already
# carves pure deletions out of the TDD gate for the same reason: removing a
# source file is not shipping implementation.
C6D="$(newtmp)/p"
if ! _c_fixture "$C6D" strict; then fail_ "C6" "fixture setup failed"; else
  gitq "$C6D" reset -q
  gitq "$C6D" rm -q src/debt.js
  check_in "$C6D"
  if [ "$CHK_RC" -eq 0 ]; then
    pass "C6: DELETING the ledgered untested file passes at strict (rc 0) — paying debt down by removal is not growth, and not a touch that owes a test"
  else
    fail_ "C6" "rc=$CHK_RC (want 0) out=$(head -5 "$CHK_OUT" | tr '\n' '|')"
  fi
fi

# C7 — a PURE RENAME (git reports R100) of a ledgered untested file. Neither
# arm's rule is met: the set gained no member and nothing was modified. An
# earlier cut of this module blocked it as non-growth on the new path, and the
# result was a TRAP worth pinning against: re-baselining put the new path in
# the ledger, and the same staged rename immediately blocked again as
# touch-repays — no way out but writing a test for a file that had only moved.
#
# So the rename passes, and because a rename is the one way debt can leave the
# ledger unpaid, the run must SAY the ledger is now stale. The pin asserts all
# three: rc 0, the note naming both paths, and — after re-baselining — that the
# debt FOLLOWED the file instead of evaporating.
C7D="$(newtmp)/p"
if ! _c_fixture "$C7D" strict; then fail_ "C7" "fixture setup failed"; else
  gitq "$C7D" reset -q
  gitq "$C7D" mv src/debt.js src/renamed-debt.js
  check_in "$C7D"; c7_rc=$CHK_RC
  c7_noted=0; grep -q 'src/debt\.js -> src/renamed-debt\.js' "$CHK_OUT" && c7_noted=1
  write_ledger "$C7D"
  c7_carried=$(jq -r '[.files[] | select(. == "src/renamed-debt.js")] | length' "$C7D/.claude/test-debt.json" 2>/dev/null)
  c7_rows=$(jq -r '.audit | length' "$C7D/.claude/test-debt.json" 2>/dev/null)
  if [ "$c7_rc" -eq 0 ] && [ "$c7_noted" -eq 1 ] \
     && [ "$(_num "$c7_carried")" -eq 1 ] && [ "$(_num "$c7_rows")" -eq 2 ]; then
    pass "C7: a PURE rename of a ledgered untested file passes (rc 0) and is NOTED with both paths; re-baselining carries the debt to the new path and leaves a second audit row — the move is not growth, not a modification, and not a silent way out"
  else
    fail_ "C7" "rc=$c7_rc (want 0) stale_ledger_noted=$c7_noted (want 1) debt_carried_to_new_path=$c7_carried (want 1) audit_rows=$c7_rows (want 2)"
  fi
fi

# C9 — the same rename WITH a content change (git reports R090 here). Now it IS
# a modification, so the obligation follows the file to its new path. Without
# this row, `git mv` plus an edit would be a one-commit way to shed the
# obligation entirely — a bigger hole than the false block C7 removed. The
# control is C7 itself: identical fixture, identical rename, no edit, rc 0.
C9D="$(newtmp)/p"
if ! mk_repo "$C9D"; then fail_ "C9" "fixture setup failed"; else
  # A file big enough for git to score the rename instead of reporting A+D.
  : > "$C9D/src/wide.js"
  for c9_i in 1 2 3 4 5 6 7 8 9 10; do
    printf 'export function f%s() { return %s; }\n' "$c9_i" "$c9_i" >> "$C9D/src/wide.js"
  done
  gitq "$C9D" add src/wide.js
  gitq "$C9D" commit -q -m "chore: a wide untested file"
  write_ledger "$C9D"
  set_tier "$C9D" '{"deployment":"personal","poc_mode":"production","enforcement_level":"strict"}'
  gitq "$C9D" mv src/wide.js src/wider.js
  printf 'export function added() { return 99; }\n' >> "$C9D/src/wider.js"
  gitq "$C9D" add src/wider.js
  c9_status=$( unset GITHUB_BASE_REF; cd "$C9D" && git -c core.quotePath=false diff --cached --name-status 2>/dev/null | cut -f1 )
  check_in "$C9D"
  c9_named=0; grep -q 'src/wider\.js' "$CHK_OUT" && c9_named=1
  case "$c9_status" in R100|A) c9_shape=0 ;; R*) c9_shape=1 ;; *) c9_shape=0 ;; esac
  if [ "$CHK_RC" -eq 4 ] && [ "$c9_named" -eq 1 ] && [ "$c9_shape" -eq 1 ]; then
    pass "C9: a rename that ALSO changes content ($c9_status) owes a test at the NEW path — rc 4, touch-repays, so `git mv` plus an edit is not a way to shed the obligation"
  else
    fail_ "C9" "rc=$CHK_RC (want 4) new_path_named=$c9_named (want 1) git_status='$c9_status' partial_rename_shape=$c9_shape (want 1; a plain A or R100 would mean the fixture stopped testing what it names)"
  fi
fi

# C8 — a NON-ASCII path must not vanish. git renders it as "src/caf\303\251.js"
# — quotes included — unless core.quotePath is off, and that string has no
# recognised source extension, so the file drops out of the census in silence
# and neither arm can ever see it. Measured on a fixture before the flag was
# added: absent from the ledger. A silent exclusion from a blocking gate is
# worse than a noisy one, so it gets its own row.
C8D="$(newtmp)/p"
if ! mk_repo "$C8D"; then fail_ "C8" "fixture setup failed"; else
  printf 'export function cafe() { return 1; }\n' > "$C8D/src/café.js"
  gitq "$C8D" add "src/café.js"
  gitq "$C8D" commit -q -m "chore: a non-ascii path"
  write_ledger "$C8D"
  c8_listed=$(jq -r '[.files[] | select(. == "src/café.js")] | length' "$C8D/.claude/test-debt.json" 2>/dev/null)
  c8_quoted=$(jq -r '[.files[] | select(startswith("\""))] | length' "$C8D/.claude/test-debt.json" 2>/dev/null)
  if [ "$(_num "$c8_listed")" -eq 1 ] && [ "$(_num "$c8_quoted")" -eq 0 ]; then
    pass "C8: a non-ASCII source path is ledgered under its REAL name — core.quotePath is off on every git read, so the file cannot drop out of the census as an unrecognised extension"
  else
    fail_ "C8" "unicode_path_listed=$c8_listed (want 1) quoted_paths_in_ledger=$c8_quoted (want 0) files=$(jq -c '.files' "$C8D/.claude/test-debt.json" 2>/dev/null)"
  fi
fi

echo ""
echo "=== D — the TOUCH-REPAYS arm (§5.4: a modified ledgered file must leave the set) ==="

_d_fixture() {
  local p="$1" level="$2"
  mk_repo "$p" || return 1
  write_ledger "$p"
  set_tier "$p" "{\"deployment\":\"personal\",\"poc_mode\":\"production\",\"enforcement_level\":\"$level\"}"
  printf 'export function debt() { return 22; }\n' > "$p/src/debt.js"
  gitq "$p" add src/debt.js
  return 0
}

D1D="$(newtmp)/p"
if ! _d_fixture "$D1D" strict; then fail_ "D1" "fixture setup failed"; else
  check_in "$D1D"
  d1_named=0; grep -q 'src/debt\.js' "$CHK_OUT" && d1_named=1
  if [ "$CHK_RC" -eq 4 ] && [ "$d1_named" -eq 1 ]; then
    pass "D1: modifying a ledgered file with no test BLOCKS at strict with rc 4 — the TOUCH-REPAYS code, not the non-growth code, so the block is attributable to the arm under test"
  else
    fail_ "D1" "rc=$CHK_RC (want 4, NOT 3) path_named=$d1_named (want 1) out=$(head -5 "$CHK_OUT" | tr '\n' '|')"
  fi
fi

D2D="$(newtmp)/p"
if ! _d_fixture "$D2D" light; then fail_ "D2" "fixture setup failed"; else
  check_in "$D2D"
  d2_warn=0; grep -qi 'warn' "$CHK_OUT" && d2_warn=1
  d2_named=0; grep -q 'src/debt\.js' "$CHK_OUT" && d2_named=1
  if [ "$CHK_RC" -eq 0 ] && [ "$d2_warn" -eq 1 ] && [ "$d2_named" -eq 1 ]; then
    pass "D2: the same touch WARNS at light and exits 0, naming the file"
  else
    fail_ "D2" "rc=$CHK_RC (want 0) warned=$d2_warn (want 1) path_named=$d2_named (want 1) out=$(head -5 "$CHK_OUT" | tr '\n' '|')"
  fi
fi

D3D="$(newtmp)/p"
if ! _d_fixture "$D3D" no; then fail_ "D3" "fixture setup failed"; else
  check_in "$D3D"
  d3_bytes=$(_bytes "$CHK_OUT")
  if [ "$CHK_RC" -eq 0 ] && [ "$d3_bytes" -eq 0 ]; then
    pass "D3: the same touch is SILENT at no — rc 0 and zero bytes"
  else
    fail_ "D3" "rc=$CHK_RC (want 0) output_bytes=$d3_bytes (want 0) out=$(head -5 "$CHK_OUT" | tr '\n' '|')"
  fi
fi

D4D="$(newtmp)/p"
if ! _d_fixture "$D4D" strict; then fail_ "D4" "fixture setup failed"; else
  printf 'test("debt", () => {});\n' > "$D4D/tests/debt.test.js"
  gitq "$D4D" add tests/debt.test.js
  check_in "$D4D"
  if [ "$CHK_RC" -eq 0 ]; then
    pass "D4 (control): the same touch WITH a test added in the same commit passes at strict (rc 0) — the debt is repaid and the arm says so"
  else
    fail_ "D4" "rc=$CHK_RC (want 0) out=$(head -5 "$CHK_OUT" | tr '\n' '|')"
  fi
fi

# D5 — the arm is LEDGER-SCOPED. Touching a file that already had a test is
# not a repayment obligation, and an arm that fired here would be a coverage
# mandate the design explicitly did not write (§5.4 limit 3).
D5D="$(newtmp)/p"
if ! _d_fixture "$D5D" strict; then fail_ "D5" "fixture setup failed"; else
  gitq "$D5D" reset -q
  printf 'export function paid() { return 11; }\n' > "$D5D/src/paid.js"
  gitq "$D5D" add src/paid.js
  check_in "$D5D"
  if [ "$CHK_RC" -eq 0 ]; then
    pass "D5: touching an ALREADY-TESTED file passes at strict (rc 0) — touch-repays is scoped to the ledger, not to every edit"
  else
    fail_ "D5" "rc=$CHK_RC (want 0) out=$(head -5 "$CHK_OUT" | tr '\n' '|')"
  fi
fi

echo ""
echo "=== E — no ledger, and the order the tier is consulted in ==="

# E1 — a strict project with no ledger. A ratchet with no baseline is not a
# ratchet, and passing silently would be the fail-open shape this whole WP is
# the forward equivalent of.
E1D="$(newtmp)/p"
if ! mk_repo "$E1D"; then fail_ "E1" "fixture setup failed"; else
  set_tier "$E1D" '{"deployment":"personal","poc_mode":"production","enforcement_level":"strict"}'
  printf 'export function fresh() { return 9; }\n' > "$E1D/src/fresh.js"
  gitq "$E1D" add src/fresh.js
  check_in "$E1D"
  if [ "$CHK_RC" -eq 2 ]; then
    pass "E1: at strict with NO ledger the ratchet refuses with rc 2 — it does not pass silently, and it does not claim an arm fired"
  else
    fail_ "E1" "rc=$CHK_RC (want 2) out=$(head -5 "$CHK_OUT" | tr '\n' '|')"
  fi
fi

# E2 — THE ORDER. The same missing ledger at `no` must be silent, because the
# tier floor is consulted BEFORE anything can refuse. A gate that fires at the
# lenient tier is as wrong as one that never fires, and "your project is
# missing a file you never asked for" is exactly the false-FAIL that teaches
# an operator to disable the framework (BL-122 / BL-149).
E2D="$(newtmp)/p"
if ! mk_repo "$E2D"; then fail_ "E2" "fixture setup failed"; else
  set_tier "$E2D" '{"deployment":"personal","poc_mode":"production","enforcement_level":"no"}'
  printf 'export function fresh() { return 9; }\n' > "$E2D/src/fresh.js"
  gitq "$E2D" add src/fresh.js
  check_in "$E2D"
  e2_bytes=$(_bytes "$CHK_OUT")
  if [ "$CHK_RC" -eq 0 ] && [ "$e2_bytes" -eq 0 ]; then
    pass "E2: the SAME missing ledger at 'no' is silent (rc 0, zero bytes) — the tier floor is read before the refusal, so a poc project is never blocked by a ratchet it did not opt into"
  else
    fail_ "E2" "rc=$CHK_RC (want 0) output_bytes=$e2_bytes (want 0) out=$(head -5 "$CHK_OUT" | tr '\n' '|')"
  fi
fi

# E3 — not a git repository at all.
E3D="$(newtmp)/p"
mkdir -p "$E3D"
set_tier "$E3D" '{"deployment":"personal","poc_mode":"production","enforcement_level":"strict"}'
check_in "$E3D"
if [ "$CHK_RC" -eq 2 ]; then
  pass "E3: a target that is not a git repository is rc 2 (unusable), never a silent pass"
else
  fail_ "E3" "rc=$CHK_RC (want 2) out=$(head -5 "$CHK_OUT" | tr '\n' '|')"
fi

echo ""
echo "=== F — the module contract (docs/module-contract.md M1/M3) ==="

f1_rc=0
bash "$REPO_ROOT/scripts/lint-module-dependencies.sh" >/dev/null 2>&1 || f1_rc=$?
if [ "$f1_rc" -eq 0 ]; then
  pass "F1: scripts/lint-module-dependencies.sh is rc 0 with the new module file present"
else
  fail_ "F1" "rc=$f1_rc (want 0)"
fi

# F2 — M3 from the other direction, asserted directly rather than trusted to
# the lint: the lint's CORE set is a glob list, and a file it does not scan
# cannot red, which is exactly how `## BL-215:`'s missing fifth glob survived
# from WP0. This greps the whole tree for the new file's basename and then
# subtracts the module's own inventory.
#
# The inventory is READ FROM THE LINT'S OWN MANIFEST FENCE, not spelled again
# here. Hardcoding it would mean an edit that moved a module path could widen
# this exclusion silently — and `scripts/adopt-project.sh` is precisely such a
# path: it is the module's ENTRY SCRIPT, so it is module code by the manifest's
# own definition even though it lives beside core scripts.
f2_hits="$TOPTMP/f2-hits"
f2_mods="$TOPTMP/f2-modules"
grep -rl 'adopt-test-debt' "$REPO_ROOT/init.sh" "$REPO_ROOT/scripts" 2>/dev/null > "$f2_hits"
sed -n '/MODULE-DEPS-MANIFEST-BEGIN/,/MODULE-DEPS-MANIFEST-END/p' "$REPO_ROOT/scripts/lint-module-dependencies.sh" \
  | grep -o '"adopt|[^"]*"' | sed 's/^"adopt|//; s/"$//' > "$f2_mods"
f2_total=$(grep -c . "$f2_hits"); f2_total=$(_num "$f2_total")
f2_modrows=$(grep -c . "$f2_mods"); f2_modrows=$(_num "$f2_modrows")
f2_core=0
f2_names=""
while IFS= read -r f2_hit; do
  [ -n "$f2_hit" ] || continue
  f2_rel="${f2_hit#"$REPO_ROOT"/}"
  f2_is_module=0
  while IFS= read -r f2_mp; do
    [ -n "$f2_mp" ] || continue
    case "$f2_rel" in "$f2_mp"|"$f2_mp"*) f2_is_module=1 ;; esac
  done < "$f2_mods"
  if [ "$f2_is_module" -eq 0 ]; then
    f2_core=$((f2_core + 1))
    f2_names="$f2_names $f2_rel"
  fi
done < "$f2_hits"
# The vacuity floor: "no core file names it" must not be reachable by scanning
# nothing. The module's own files DO name it, so a zero total is a broken probe.
if [ "$f2_core" -eq 0 ] && [ "$f2_total" -gt 0 ] && [ "$f2_modrows" -gt 0 ]; then
  pass "F2 (M3): every file that names adopt-test-debt is in the adopt module's own manifest inventory ($f2_total naming files, $f2_modrows manifest rows) — core -> module stays unreachable by grep as well as by lint"
else
  fail_ "F2" "core files naming adopt-test-debt: $f2_core (want 0):$f2_names | total_naming_files=$f2_total (want >0) manifest_rows=$f2_modrows (want >0)"
fi

# F3 — M2: the entry script's declared core-lib list must actually name the
# two libs this module now sources. M2 is enforced by review, and a review
# needs the list to be true.
f3_enf=0; f3_tdd=0
grep -q 'enforcement-level\.sh' "$DRIVER" && f3_enf=1
grep -q 'tdd-classify\.sh' "$DRIVER" && f3_tdd=1
if [ "$f3_enf" -eq 1 ] && [ "$f3_tdd" -eq 1 ]; then
  pass "F3 (M2): the driver's declared core-lib set names enforcement-level.sh and tdd-classify.sh — the two core libs the ledger consumes"
else
  fail_ "F3" "enforcement-level_declared=$f3_enf tdd-classify_declared=$f3_tdd (want 1 1)"
fi

echo ""
echo "=== G — the driver writes the ledger (the stub is retired) ==="

# One scout run and one driver run for the whole section: the driver consumes
# the genuine §8.2 schema rather than a hand-written stand-in of it, and this
# suite runs in the fast unit lane, so it buys that fidelity exactly once.
G_OK=0
GTEMPLATE="$(newtmp)/template"
if mk_repo "$GTEMPLATE"; then
  printf '# What this is for\n\nInvoice reconciliation.\n' > "$GTEMPLATE/PRODUCT.md"
  gitq "$GTEMPLATE" add PRODUCT.md
  gitq "$GTEMPLATE" commit -q -m "docs: product"
  if bash "$REPO_ROOT/scripts/scout.sh" --root "$GTEMPLATE" --out "$TOPTMP/scan" >/dev/null 2>&1; then
    [ -s "$TOPTMP/scan/scout-report.json" ] && G_OK=1
  fi
fi

if [ "$G_OK" -ne 1 ]; then
  fail_ "G" "scripts/scout.sh produced no report; the driver consumes one and cannot be exercised without it"
else
  GD="$(newtmp)"
  if ! mk_repo "$GD/p"; then
    fail_ "G1" "fixture setup failed"
  else
    jq '.phaseMap.suggestedPhase = 2' "$TOPTMP/scan/scout-report.json" > "$GD/report.json" 2>/dev/null
    # WP9: five answers — the tier question (2 = organizational, the tier this
    # suite's ratchet arms are written against) and the four scan-derived
    # confirmations. The chooser, the ladder, the nine judgment sections and
    # the classification are no longer asked here (D4, D10, A7).
    cat > "$GD/answers" <<'ANS'
2
1
1
1
1
ANS
    g_rc=0
    ( unset GITHUB_BASE_REF; cd "$GD/p" && bash "$DRIVER" --scan-report "$GD/report.json" ) \
      < "$GD/answers" > "$GD/out" 2> "$GD/err" || g_rc=$?
    g_file="$GD/p/.claude/test-debt.json"
    g_exists=0; [ -s "$g_file" ] && g_exists=1
    g_committed=$( unset GITHUB_BASE_REF; cd "$GD/p" && git show --name-only --format= HEAD 2>/dev/null )
    g_staged=$(printf '%s\n' "$g_committed" | grep -c '^\.claude/test-debt\.json$'); g_staged=$(_num "$g_staged")
    g_debt=$(jq -r '[.files[] | select(. == "src/debt.js")] | length' "$g_file" 2>/dev/null)
    # The STUB must be gone — and gone is an ABSENCE, so it is asserted
    # alongside a positive: the run must also SAY what it recorded.
    g_stub=0; grep -q 'NOT DONE — the test-debt ledger' "$GD/out" && g_stub=1
    g_said=0; grep -qi 'test-debt' "$GD/out" && g_said=1
    if [ "$g_rc" -eq 0 ] && [ "$g_exists" -eq 1 ] && [ "$g_staged" -eq 1 ] \
       && [ "$(_num "$g_debt")" -eq 1 ] && [ "$g_stub" -eq 0 ] && [ "$g_said" -eq 1 ]; then
      pass "G1: a real adoption WRITES .claude/test-debt.json, COMMITS it, records the untested file, and no longer prints the WP5b 'NOT DONE' stub — it reports what it recorded instead"
    else
      fail_ "G1" "rc=$g_rc ledger_exists=$g_exists ledger_committed=$g_staged (want 1) debt_listed=$g_debt (want 1) stub_still_printed=$g_stub (want 0) run_mentions_ledger=$g_said (want 1) err=$(head -3 "$GD/err" | tr '\n' '|')"
    fi

    # G2 — the ledger must be about THEIR code. The driver installs ~60
    # framework scripts into the adoptee; a census taken over the working tree
    # after that install would file every one of them as the adoptee's
    # untested debt, and the touch-repays arm would then demand tests for the
    # framework's own gate scripts.
    g2_fw=$(jq -r '[.files[] | select(startswith("scripts/"))] | length' "$g_file" 2>/dev/null)
    g2_count=$(jq -r '.count // -1' "$g_file" 2>/dev/null)
    if [ "$(_num "$g2_fw")" -eq 0 ]; then
      pass "G2: the ledger contains NONE of the framework scripts the adoption installed — the census is of the adoptee's own tracked source, not of the tree the driver leaves behind"
    else
      fail_ "G2" "framework scripts ledgered: $g2_fw (want 0)"
    fi

    # G3 — THE SECOND WRITE, and the reason this row exists at all.
    #
    # G2 above passes for a reason that is NOT a defence: at adoption time the
    # framework's scripts are copied but not yet TRACKED, and the census reads
    # `git ls-files`. That is timing, not exclusion — and a defence that works
    # by timing is a coincidence with a schedule. Every write after the
    # adoption commit is exposed, and this tool ACTIVELY INSTRUCTS the operator
    # to perform one: the rename [NOTE] and the rc-2 refusal both print
    # `--write --root .`.
    #
    # Measured before the fix, on exactly this fixture: count 1 / 0 framework
    # entries at adoption, then count 58 / 57 framework entries after running
    # the advertised command — after which touch-repays demanded tests for
    # check-gate.sh and check-phase-gate.sh on any framework sync. The tool
    # told the user to break themselves.
    #
    # A THIRD assertion is here on purpose: the audit row count. "Unchanged" and
    # "the write never ran" are the same bytes on disk, and only the audit row
    # tells them apart.
    write_ledger "$GD/p"
    g3_fw=$(jq -r '[.files[] | select(startswith("scripts/"))] | length' "$g_file" 2>/dev/null)
    g3_count=$(jq -r '.count // -1' "$g_file" 2>/dev/null)
    g3_rows=$(jq -r '.audit | length' "$g_file" 2>/dev/null)
    if [ "$(_num "$g3_fw")" -eq 0 ] && [ "$(_num "$g3_count")" = "$(_num "$g2_count")" ] \
       && [ "$(_num "$g3_rows")" -eq 2 ]; then
      pass "G3: running the re-baseline command the tool itself advertises, AFTER the adoption commit, still ledgers zero framework scripts and the same count ($g3_count) — and the second audit row proves the write actually ran"
    else
      fail_ "G3" "framework scripts after re-baseline: $g3_fw (want 0) count=$g3_count (want $g2_count) audit_rows=$g3_rows (want 2 — 1 means the write never happened and this row proves nothing)"
    fi
  fi
fi

echo ""
echo "=== P — the adoptee's own git config must not be able to switch the arms off ==="

# A fix a user's .gitconfig can silently disable is not a fix. Both rows below
# were REPRODUCED before being fixed, and both carry a structural discriminator
# proving the fixture really is running under the hostile config — without it a
# green row would only mean "the config had no effect here".

# P1 — `diff.renames=copies`. Staging a copy of a TESTED file plus a touch of
# its source made git report `C100 src/paid.js src/clone.js`, and src/clone.js —
# an untested source file — ENTERED the working set at rc 0 with zero bytes of
# output. That is the silent-bypass class: no refusal, no warning, no trace.
P1D="$(newtmp)/p"
if ! mk_repo "$P1D"; then fail_ "P1" "fixture setup failed"; else
  write_ledger "$P1D"
  set_tier "$P1D" '{"deployment":"personal","poc_mode":"production","enforcement_level":"strict"}'
  gitq "$P1D" config diff.renames copies
  cp "$P1D/src/paid.js" "$P1D/src/clone.js"
  printf 'export function paid() { return 2; }\n' > "$P1D/src/paid.js"
  gitq "$P1D" add -A
  # The discriminator: git's OWN reading of this index, with nothing pinned.
  p1_raw=$( unset GITHUB_BASE_REF; cd "$P1D" && git diff --cached --name-status 2>/dev/null | grep -c '^C' )
  p1_raw=$(_num "$p1_raw")
  check_in "$P1D"
  p1_named=0; grep -q 'src/clone\.js' "$CHK_OUT" && p1_named=1
  if [ "$CHK_RC" -eq 3 ] && [ "$p1_named" -eq 1 ] && [ "$p1_raw" -ge 1 ]; then
    pass "P1: under the adoptee's own diff.renames=copies the copied untested file still BLOCKS at strict (rc 3, named) — the read pins diff.renames=true, so a config that makes git say C100 cannot make the arm say nothing"
  else
    fail_ "P1" "rc=$CHK_RC (want 3) clone_named=$p1_named (want 1) unpinned_git_reports_C_rows=$p1_raw (want >=1; 0 means the fixture is not exercising the hostile config and this row proves nothing)"
  fi
fi

# P2 — `diff.renames=false`. The rename loop the previous commit is named after
# comes back VERBATIM: git reports D+A instead of R100, non-growth blocks at
# rc 3, re-baselining puts the new path in the ledger, and the same staged
# rename blocks again at rc 4. Reproduced before the fix.
P2D="$(newtmp)/p"
if ! mk_repo "$P2D"; then fail_ "P2" "fixture setup failed"; else
  write_ledger "$P2D"
  set_tier "$P2D" '{"deployment":"personal","poc_mode":"production","enforcement_level":"strict"}'
  gitq "$P2D" config diff.renames false
  gitq "$P2D" mv src/debt.js src/debt2.js
  p2_raw=$( unset GITHUB_BASE_REF; cd "$P2D" && git diff --cached --name-status 2>/dev/null | grep -c '^D' )
  p2_raw=$(_num "$p2_raw")
  check_in "$P2D"
  p2_noted=0; grep -q 'src/debt\.js -> src/debt2\.js' "$CHK_OUT" && p2_noted=1
  if [ "$CHK_RC" -eq 0 ] && [ "$p2_noted" -eq 1 ] && [ "$p2_raw" -ge 1 ]; then
    pass "P2: under the adoptee's own diff.renames=false the pure rename is still seen as a rename — rc 0 with the stale-ledger note, not the rc 3 -> re-baseline -> rc 4 loop the config resurrected"
  else
    fail_ "P2" "rc=$CHK_RC (want 0) rename_noted=$p2_noted (want 1) unpinned_git_reports_D_rows=$p2_raw (want >=1; 0 means the fixture is not exercising the hostile config)"
  fi
fi

echo ""
echo "=== Q — status atoms every fixture can actually reach ==="

# Q1 — a staged MODIFICATION of a file that is NEITHER ledgered NOR tested.
#
# This row exists because a reviewer's mutation survived a 42/0 suite: widening
# the non-growth match from `A` to `A|M` — which REVERSES the documented
# "additions only" decision and turns the arm into the coverage mandate §5.4
# limit 3 declines to write — changed nothing, because every other fixture's
# staged `M` row is either ledgered (skipped by the ledger check) or tested
# (skipped by the test check). The `M` branch was unreachable, so it was pinned
# by nothing.
#
# The fixture reaches it by deleting the test AFTER baselining: src/paid.js is
# then unledgered (it had a test when the ledger was written) and untested (the
# test is gone), which is the one combination that lands in the `M` branch.
Q1D="$(newtmp)/p"
if ! mk_repo "$Q1D"; then fail_ "Q1" "fixture setup failed"; else
  write_ledger "$Q1D"
  set_tier "$Q1D" '{"deployment":"personal","poc_mode":"production","enforcement_level":"strict"}'
  gitq "$Q1D" rm -q tests/paid.test.js
  gitq "$Q1D" commit -q -m "chore: the test goes away"
  printf 'export function paid() { return 3; }\n' > "$Q1D/src/paid.js"
  gitq "$Q1D" add src/paid.js
  # Three discriminators, because a green row here must not be reachable by a
  # fixture that drifted into some other shape.
  q1_status=$( unset GITHUB_BASE_REF; cd "$Q1D" && git diff --cached --name-status 2>/dev/null | cut -f1 | tr -d '\n' )
  q1_ledgered=$(jq -r '[.files[] | select(. == "src/paid.js")] | length' "$Q1D/.claude/test-debt.json" 2>/dev/null)
  q1_tested=0; [ -e "$Q1D/tests/paid.test.js" ] && q1_tested=1
  check_in "$Q1D"
  if [ "$CHK_RC" -eq 0 ] && [ "$q1_status" = "M" ] \
     && [ "$(_num "$q1_ledgered")" -eq 0 ] && [ "$q1_tested" -eq 0 ]; then
    pass "Q1: a staged M of an UNLEDGERED, UNTESTED file passes at strict (rc 0) — non-growth is additions-only, and this is the only fixture shape that can reach the branch which says so"
  else
    fail_ "Q1" "rc=$CHK_RC (want 0) staged_status='$q1_status' (want M) ledgered=$q1_ledgered (want 0) test_file_still_present=$q1_tested (want 0)"
  fi
fi

# Q2 — a MODE-ONLY change. `chmod +x` on a ledgered file reads as `M` and used
# to block at rc 4, although git's own raw output shows the SAME blob SHA on
# both sides. That is the identical fact the R100 carve-out rests on, so the
# two postures were inconsistent, and inconsistent in the false-FAIL direction.
# The control is the same file with its CONTENT changed: that must still block,
# or this row would be pinning "touch-repays never fires".
Q2D="$(newtmp)/p"
if ! mk_repo "$Q2D"; then fail_ "Q2" "fixture setup failed"; else
  write_ledger "$Q2D"
  set_tier "$Q2D" '{"deployment":"personal","poc_mode":"production","enforcement_level":"strict"}'
  chmod +x "$Q2D/src/debt.js"
  gitq "$Q2D" add src/debt.js
  q2_same=$( unset GITHUB_BASE_REF; cd "$Q2D" && git diff --cached --raw --abbrev=40 2>/dev/null \
             | sed -n 's/^:[0-7]* [0-7]* \([0-9a-f]*\) \([0-9a-f]*\) .*/\1 \2/p' \
             | while read -r a b; do [ "$a" = "$b" ] && echo same; done | grep -c 'same' )
  q2_same=$(_num "$q2_same")
  check_in "$Q2D"; q2_mode_rc=$CHK_RC
  printf 'export function debt() { return 77; }\n' > "$Q2D/src/debt.js"
  gitq "$Q2D" add src/debt.js
  check_in "$Q2D"; q2_content_rc=$CHK_RC
  if [ "$q2_mode_rc" -eq 0 ] && [ "$q2_content_rc" -eq 4 ] && [ "$q2_same" -ge 1 ]; then
    pass "Q2: a mode-only chmod +x on a ledgered file passes (rc 0) because git reports identical blob SHAs — the same fact R100 rests on — while a real content change on the SAME file still blocks at rc 4"
  else
    fail_ "Q2" "mode_only_rc=$q2_mode_rc (want 0) content_change_rc=$q2_content_rc (want 4) git_reports_identical_blobs=$q2_same (want >=1; 0 means the fixture never made a mode-only change)"
  fi
fi

echo ""
echo "=== M — mutations (both arms, both directions) ==="

# Every mutant runs against a MIRROR of the module plus the two core libs it
# sources. The tree under test is never edited: a failure here cannot leave
# this repository mutated.
#
# LANE NOTE. The line below NAMES init.sh, which is the exemption predicate
# `# BL-181-UNIT-LANE-PREDICATE` reads — but this suite only COPIES that file so
# the shipped-set parser has something to parse; it never runs it. The suite
# belongs in the fast unit lane and is registered there. The lint says so
# itself: "an exempted file that is in the unit list anyway decided nothing and
# is not rendered". Spelling the name plainly and registering the suite is the
# honest combination; dodging the predicate with a glob would hide the decision.
#
# init.sh and scaffold-shipped-set.sh are in the mirror because the module now
# REFUSES when it cannot derive the framework's own installed inventory. A
# mirror without them is an incomplete clone, and the module is supposed to say
# so rather than fall back to a census that ledgers the framework.
#
# The optional VARIANT makes a mirror INCOMPLETE in exactly one way, so each of
# the three guards in _td_shipped_init has a fixture that reaches it:
#   (default)  a complete clone
#   noinit     no init.sh                    -> the BF-TD-SHIPPED-REQUIRED guard
#   emptyinit  an init.sh with no copy lines -> the BF-TD-SHIPPED-NONEMPTY guard
#   noparser   no scaffold-shipped-set.sh    -> the BF-TD-SHIPPED-PARSER guard
mk_mirror() {
  local m="$1" variant="${2:-full}"
  mkdir -p "$m/scripts/lib/adopt" || return 1
  cp -p "$CORE_ENF" "$m/scripts/lib/" || return 1
  cp -p "$CORE_TDD" "$m/scripts/lib/" || return 1
  [ "$variant" = "noparser" ] || cp -p "$CORE_SHIPPED" "$m/scripts/lib/" || return 1
  case "$variant" in
    noinit)    ;;
    # NO SHEBANG IN THIS STUB, and the omission is load-bearing rather than
    # tidy: with `#!/usr/bin/env bash` in it, lint-no-live-remote-in-tests.sh
    # reds this very line as "init.sh run can reach LIVE remote creation". Its
    # rule-B alternation carries `env[[:space:]][^;&|]*`, which the SHEBANG
    # STRING satisfies, and the redirect target then reads as a command word.
    # The stub is never executed — it exists only to be parsed for copy lines,
    # of which it has none — so dropping the shebang removes a false positive
    # without spelling around a real check. Filed as `## BL-224:`.
    emptyinit) printf '# a clone whose copy list is empty\n' > "$m/init.sh" || return 1 ;;
    *)         cp -p "$REPO_ROOT/init.sh" "$m/" || return 1 ;;
  esac
  cp -p "$LIB" "$m/scripts/lib/adopt/" || return 1
  return 0
}

# mk_repo_fw DIR — mk_repo plus a TRACKED file at a framework path, so that a
# ledger written by a module whose exclusion has gone inert is visibly wrong
# rather than merely one entry larger.
mk_repo_fw() {
  mk_repo "$1" || return 1
  mkdir -p "$1/scripts" || return 1
  printf '#!/usr/bin/env bash\necho gate\n' > "$1/scripts/check-gate.sh" || return 1
  gitq "$1" add scripts/check-gate.sh
  gitq "$1" commit -q -m "chore: a framework path, tracked"
  return 0
}

# write_via MIRROR DIR — run the mirror's writer; sets LEDGER_RC.
write_via() { write_ledger "$2" "$(_mlib "$1")"; }

# _mutate MIRROR MARKER REPLACEMENT — one anchored, end-of-line-marked line,
# excised and replaced. Echoes "sites changed parses" for the caller to assert.
#
# TWO SED METACHARACTERS IN THE REPLACEMENT, BOTH LEARNED THE HARD WAY IN THIS
# FILE. `|` was the delimiter, so a replacement containing one — `case $status
# in A|M)`, the exact widening a reviewer used to survive a green suite —
# terminated the expression, sed errored, and the mutant was NOT APPLIED. `&` in
# a replacement means THE WHOLE MATCH, so `cmd_a && cmd_b` spliced the original
# line back in twice and produced a mutant nobody had designed. The delimiter is
# now `%` (no marker or replacement in this file contains one) and `&` is
# escaped.
#
# WHICH CHECK CAUGHT WHICH — corrected, because the first version of this
# comment credited the wrong layer and a future author would then trust the
# wrong thing:
#
#   • the DELIMITER defect was caught by the exactly-N-lines-changed assertion.
#     sed exits 1, the file is untouched, `changed_lines=0`. Meta-assertion,
#     working exactly as intended.
#   • the `&`-SPLICE defect was NOT. Measured under the old semantics: the
#     splice yields `changed_lines=2` AND `bash -n` PASSES, so every
#     meta-assertion here stays green. What caught it was M11's FUNCTIONAL
#     assertion — the spliced module dies at runtime (`bad substitution: no
#     closing ')'`), rc 1 and 564 bytes against a wanted rc 0 / 0 bytes.
#
# So the meta-assertions are NOT the defence against `&`-class accidents; the
# CONTROL plus the functional assertion is. Note the generalisation, because it
# is this wave's "bash -n does not syntax-check awk" one step further in:
# **`bash -n` accepts a file bash rejects at runtime.** A parse check is not an
# execution check, and only a mutant that RUNS proves anything.
#
# RESIDUAL, stated rather than left to be discovered: backslash sequences in a
# replacement are the remaining unhandled metacharacter class. `\n` fails LOUD
# (`changed=3`, since GNU sed turns it into a newline), but a `\.`-style escape
# would substitute silently wrong. Nothing enforces their absence — it is header
# convention only. `%` is verified safe today (no call site carries one) and a
# `%`-bearing replacement would fail loud for the same reason `|` did.
_mutate() {
  local m="$1" marker="$2" repl="$3"
  local f="$m/scripts/lib/adopt/adopt-test-debt.sh"
  local before sites changed parses safe
  safe="${repl//&/\\&}"
  before="$(mktemp)"
  cp -p "$f" "$before"
  sites=$(_sites "$f" "$marker")
  _sed_inplace "$f" "s%^.*${marker}\$%${safe}%"
  changed=$(_changed_lines "$before" "$f")
  parses=$(_parses "$f")
  rm -f "$before"
  printf '%s %s %s\n' "$sites" "$changed" "$parses"
}

_mlib() { printf '%s/scripts/lib/adopt/adopt-test-debt.sh\n' "$1"; }

# ── M1: neuter the NON-GROWTH arm → the untested set grows silently ─────────
M1D="$(newtmp)"
if ! _c_fixture "$M1D/p" strict || ! mk_mirror "$M1D/m"; then
  fail_ "M1" "fixture setup failed"
else
  check_in "$M1D/p" "$(_mlib "$M1D/m")"; m1_ctl=$CHK_RC
  m1_meta=$(_mutate "$M1D/m" '# BF-TD-NONGROWTH-ARM' '    continue')
  set -- $m1_meta; m1_sites=$1; m1_changed=$2; m1_parses=$3
  check_in "$M1D/p" "$(_mlib "$M1D/m")"; m1_mut=$CHK_RC
  m1_bytes=$(_bytes "$CHK_OUT")
  if [ "$m1_ctl" -eq 3 ] && [ "$m1_mut" -ne 3 ] && [ "$m1_bytes" -eq 0 ] \
     && [ "$m1_sites" -eq 1 ] && [ "$m1_changed" -eq 2 ] && [ "$m1_parses" -eq 1 ]; then
    pass "M1 (direction 1, non-growth): control blocks with rc 3; with the arm neutered the SAME added untested file passes with NO output — the set grew silently, which is the failure this arm exists to prevent"
  else
    fail_ "M1" "control_rc=$m1_ctl (want 3) mutant_rc=$m1_mut (want != 3) mutant_output_bytes=$m1_bytes (want 0) sites=$m1_sites (want 1) changed_lines=$m1_changed (want 2) parses=$m1_parses (want 1)"
  fi
fi

# ── M2: neuter the TOUCH-REPAYS arm ────────────────────────────────────────
M2D="$(newtmp)"
if ! _d_fixture "$M2D/p" strict || ! mk_mirror "$M2D/m"; then
  fail_ "M2" "fixture setup failed"
else
  check_in "$M2D/p" "$(_mlib "$M2D/m")"; m2_ctl=$CHK_RC
  m2_meta=$(_mutate "$M2D/m" '# BF-TD-TOUCH-ARM' '    continue')
  set -- $m2_meta; m2_sites=$1; m2_changed=$2; m2_parses=$3
  check_in "$M2D/p" "$(_mlib "$M2D/m")"; m2_mut=$CHK_RC
  m2_bytes=$(_bytes "$CHK_OUT")
  if [ "$m2_ctl" -eq 4 ] && [ "$m2_mut" -ne 4 ] && [ "$m2_bytes" -eq 0 ] \
     && [ "$m2_sites" -eq 1 ] && [ "$m2_changed" -eq 2 ] && [ "$m2_parses" -eq 1 ]; then
    pass "M2 (direction 1, touch-repays): control blocks with rc 4; with the arm neutered the SAME modification of a ledgered file passes with no output"
  else
    fail_ "M2" "control_rc=$m2_ctl (want 4) mutant_rc=$m2_mut (want != 4) mutant_output_bytes=$m2_bytes (want 0) sites=$m2_sites (want 1) changed_lines=$m2_changed (want 2) parses=$m2_parses (want 1)"
  fi
fi

# ── M3: neuter the TIER FLOOR → the non-growth arm blocks at `no` ──────────
# THE SECOND DIRECTION, and the one that usually gets skipped. A gate that
# fires at the lenient tier is as wrong as one that never fires: a ratchet
# that blocks a poc_mode project is not a stricter ratchet, it is a broken
# one, and it is the shape that makes people disable the whole framework.
M3D="$(newtmp)"
if ! _c_fixture "$M3D/p" no || ! mk_mirror "$M3D/m"; then
  fail_ "M3" "fixture setup failed"
else
  check_in "$M3D/p" "$(_mlib "$M3D/m")"; m3_ctl=$CHK_RC
  m3_ctl_bytes=$(_bytes "$CHK_OUT")
  m3_meta=$(_mutate "$M3D/m" '# BF-TD-FLOOR-NO' "    no)     echo block ;;")
  set -- $m3_meta; m3_sites=$1; m3_changed=$2; m3_parses=$3
  check_in "$M3D/p" "$(_mlib "$M3D/m")"; m3_mut=$CHK_RC
  if [ "$m3_ctl" -eq 0 ] && [ "$m3_ctl_bytes" -eq 0 ] && [ "$m3_mut" -eq 3 ] \
     && [ "$m3_sites" -eq 1 ] && [ "$m3_changed" -eq 2 ] && [ "$m3_parses" -eq 1 ]; then
    pass "M3 (direction 2, non-growth): control is silent at 'no'; with the floor's 'no' row raised to block the SAME commit is refused with rc 3 — the tier floor is load-bearing, not decorative"
  else
    fail_ "M3" "control_rc=$m3_ctl (want 0) control_bytes=$m3_ctl_bytes (want 0) mutant_rc=$m3_mut (want 3) sites=$m3_sites (want 1) changed_lines=$m3_changed (want 2) parses=$m3_parses (want 1)"
  fi
fi

# ── M4: the same floor mutation, observed through the OTHER arm ────────────
# One site, two independent observations. A floor spelled once is the correct
# architecture (a second spelling is the # BL-084-TIER-KEY sync-sibling trap),
# so the second direction for the second arm is proved by a second FIXTURE,
# not by a second line.
M4D="$(newtmp)"
if ! _d_fixture "$M4D/p" no || ! mk_mirror "$M4D/m"; then
  fail_ "M4" "fixture setup failed"
else
  check_in "$M4D/p" "$(_mlib "$M4D/m")"; m4_ctl=$CHK_RC
  m4_ctl_bytes=$(_bytes "$CHK_OUT")
  m4_meta=$(_mutate "$M4D/m" '# BF-TD-FLOOR-NO' "    no)     echo block ;;")
  set -- $m4_meta; m4_sites=$1; m4_changed=$2; m4_parses=$3
  check_in "$M4D/p" "$(_mlib "$M4D/m")"; m4_mut=$CHK_RC
  if [ "$m4_ctl" -eq 0 ] && [ "$m4_ctl_bytes" -eq 0 ] && [ "$m4_mut" -eq 4 ] \
     && [ "$m4_sites" -eq 1 ] && [ "$m4_changed" -eq 2 ] && [ "$m4_parses" -eq 1 ]; then
    pass "M4 (direction 2, touch-repays): control is silent at 'no'; the same one-line floor mutation makes the touch-repays arm refuse a poc project with rc 4"
  else
    fail_ "M4" "control_rc=$m4_ctl (want 0) control_bytes=$m4_ctl_bytes (want 0) mutant_rc=$m4_mut (want 4) sites=$m4_sites (want 1) changed_lines=$m4_changed (want 2) parses=$m4_parses (want 1)"
  fi
fi

# ── M5: the `light` row of the floor — the [WARN] trap, mutated ────────────
M5D="$(newtmp)"
if ! _c_fixture "$M5D/p" light || ! mk_mirror "$M5D/m"; then
  fail_ "M5" "fixture setup failed"
else
  check_in "$M5D/p" "$(_mlib "$M5D/m")"; m5_ctl=$CHK_RC
  m5_ctl_warn=0; grep -qi 'warn' "$CHK_OUT" && m5_ctl_warn=1
  m5_meta=$(_mutate "$M5D/m" '# BF-TD-FLOOR-LIGHT' "    light)  echo block ;;")
  set -- $m5_meta; m5_sites=$1; m5_changed=$2; m5_parses=$3
  check_in "$M5D/p" "$(_mlib "$M5D/m")"; m5_mut=$CHK_RC
  if [ "$m5_ctl" -eq 0 ] && [ "$m5_ctl_warn" -eq 1 ] && [ "$m5_mut" -eq 3 ] \
     && [ "$m5_sites" -eq 1 ] && [ "$m5_changed" -eq 2 ] && [ "$m5_parses" -eq 1 ]; then
    pass "M5 (the [WARN] trap): control WARNS and exits 0; promoting the floor's 'light' row to block turns the identical warning into rc 3 — proof the warn arm's exit code is decided by the floor and not by the label it prints"
  else
    fail_ "M5" "control_rc=$m5_ctl (want 0) control_warned=$m5_ctl_warn (want 1) mutant_rc=$m5_mut (want 3) sites=$m5_sites (want 1) changed_lines=$m5_changed (want 2) parses=$m5_parses (want 1)"
  fi
fi

# ── M6: the ## BL-221: guard — the tier must not be trusted to a missing key ─
M6D="$(newtmp)"
if ! _c_fixture "$M6D/p" no || ! mk_mirror "$M6D/m"; then
  fail_ "M6" "fixture setup failed"
else
  set_tier "$M6D/p" '{"host":"github","enforcement_level":"no"}'
  check_in "$M6D/p" "$(_mlib "$M6D/m")"; m6_ctl=$CHK_RC
  m6_meta=$(_mutate "$M6D/m" '# BF-TD-TIER-KEY-PRESENT' '  if false; then')
  set -- $m6_meta; m6_sites=$1; m6_changed=$2; m6_parses=$3
  check_in "$M6D/p" "$(_mlib "$M6D/m")"; m6_mut=$CHK_RC
  m6_bytes=$(_bytes "$CHK_OUT")
  if [ "$m6_ctl" -eq 3 ] && [ "$m6_mut" -eq 0 ] && [ "$m6_bytes" -eq 0 ] \
     && [ "$m6_sites" -eq 1 ] && [ "$m6_changed" -eq 2 ] && [ "$m6_parses" -eq 1 ]; then
    pass "M6 (## BL-221:): control refuses a tier whose deployment key is absent (rc 3); removing the presence guard makes the SAME manifest buy silence — which is the live fail-open, reproduced here on purpose so it cannot come back unnoticed"
  else
    fail_ "M6" "control_rc=$m6_ctl (want 3) mutant_rc=$m6_mut (want 0) mutant_bytes=$m6_bytes (want 0) sites=$m6_sites (want 1) changed_lines=$m6_changed (want 2) parses=$m6_parses (want 1)"
  fi
fi

# ── M7: the census predicate — an empty ledger must not read as no debt ────
# The expected mutant result is an ABSENCE (nothing in the ledger), and "the
# census found nothing" and "the census never ran" share one downstream
# silence. So this asserts the ledger's BYTES: the file must still be valid
# JSON with count 0, and the CONTROL must have found the debt.
M7D="$(newtmp)"
if ! mk_repo "$M7D/p" || ! mk_mirror "$M7D/m"; then
  fail_ "M7" "fixture setup failed"
else
  write_ledger "$M7D/p" "$(_mlib "$M7D/m")"
  m7_ctl=$(jq -r '.count // -1' "$M7D/p/.claude/test-debt.json" 2>/dev/null)
  m7_meta=$(_mutate "$M7D/m" '# BF-TD-CENSUS-CANDIDATE' '    continue')
  set -- $m7_meta; m7_sites=$1; m7_changed=$2; m7_parses=$3
  rm -f "$M7D/p/.claude/test-debt.json"
  write_ledger "$M7D/p" "$(_mlib "$M7D/m")"
  m7_valid=0; jq -e . "$M7D/p/.claude/test-debt.json" >/dev/null 2>&1 && m7_valid=1
  m7_mut=$(jq -r '.count // -1' "$M7D/p/.claude/test-debt.json" 2>/dev/null)
  if [ "$(_num "$m7_ctl")" -eq 1 ] && [ "$m7_valid" -eq 1 ] && [ "$(_num "$m7_mut")" -eq 0 ] \
     && [ "$m7_sites" -eq 1 ] && [ "$m7_changed" -eq 2 ] && [ "$m7_parses" -eq 1 ]; then
    pass "M7 (the census): control ledgers 1 untested file; with the candidate predicate neutered the writer still emits VALID JSON with count 0 — an empty ledger is a real, reachable state and it is not the same fact as a clean tree"
  else
    fail_ "M7" "control_count=$m7_ctl (want 1) mutant_ledger_valid=$m7_valid (want 1) mutant_count=$m7_mut (want 0) sites=$m7_sites (want 1) changed_lines=$m7_changed (want 2) parses=$m7_parses (want 1)"
  fi
fi

# ── M9: the additions-only decision, pinned against the `M` widening ───────
# The mutation a reviewer landed on a 42/0 suite. Widening the non-growth
# status match to include `M` reverses the documented decision and turns the
# arm into a coverage mandate; Q1's fixture is the only shape that reaches the
# branch, so it is the only thing that can kill this.
M9D="$(newtmp)"
if ! mk_repo "$M9D/p" || ! mk_mirror "$M9D/m"; then
  fail_ "M9" "fixture setup failed"
else
  write_ledger "$M9D/p"
  set_tier "$M9D/p" '{"deployment":"personal","poc_mode":"production","enforcement_level":"strict"}'
  gitq "$M9D/p" rm -q tests/paid.test.js
  gitq "$M9D/p" commit -q -m "chore: the test goes away"
  printf 'export function paid() { return 3; }\n' > "$M9D/p/src/paid.js"
  gitq "$M9D/p" add src/paid.js
  check_in "$M9D/p" "$(_mlib "$M9D/m")"; m9_ctl=$CHK_RC
  m9_ctl_bytes=$(_bytes "$CHK_OUT")
  m9_meta=$(_mutate "$M9D/m" '# BF-TD-NONGROWTH-ADDITIONS-ONLY' '    case "$status" in A|M) ;; *) continue ;; esac')
  set -- $m9_meta; m9_sites=$1; m9_changed=$2; m9_parses=$3
  check_in "$M9D/p" "$(_mlib "$M9D/m")"; m9_mut=$CHK_RC
  if [ "$m9_ctl" -eq 0 ] && [ "$m9_ctl_bytes" -eq 0 ] && [ "$m9_mut" -eq 3 ] \
     && [ "$m9_sites" -eq 1 ] && [ "$m9_changed" -eq 2 ] && [ "$m9_parses" -eq 1 ]; then
    pass "M9 (additions-only): control passes a staged M of an unledgered untested file silently; widening the status match to A|M refuses it with rc 3 — the coverage mandate §5.4 limit 3 declines to write"
  else
    fail_ "M9" "control_rc=$m9_ctl (want 0) control_bytes=$m9_ctl_bytes (want 0) mutant_rc=$m9_mut (want 3) sites=$m9_sites (want 1) changed_lines=$m9_changed (want 2) parses=$m9_parses (want 1)"
  fi
fi

# ── M10: the framework-path exclusion, killed on the SECOND write ──────────
# The exclusion replaced a defence that worked by TIMING (the framework's
# scripts were merely untracked at adoption time). So the mutant is observed
# where the timing defence used to hold and no longer does: a repository that
# already TRACKS a framework path.
M10D="$(newtmp)"
if ! mk_repo "$M10D/p" || ! mk_mirror "$M10D/m"; then
  fail_ "M10" "fixture setup failed"
else
  mkdir -p "$M10D/p/scripts"
  printf '#!/usr/bin/env bash\necho gate\n' > "$M10D/p/scripts/check-gate.sh"
  gitq "$M10D/p" add scripts/check-gate.sh
  gitq "$M10D/p" commit -q -m "chore: the framework's own script, tracked"
  write_ledger "$M10D/p" "$(_mlib "$M10D/m")"
  m10_ctl=$(jq -r '[.files[] | select(. == "scripts/check-gate.sh")] | length' "$M10D/p/.claude/test-debt.json" 2>/dev/null)
  m10_meta=$(_mutate "$M10D/m" '# BF-TD-FRAMEWORK-EXCLUDE' '  :')
  set -- $m10_meta; m10_sites=$1; m10_changed=$2; m10_parses=$3
  write_ledger "$M10D/p" "$(_mlib "$M10D/m")"
  m10_valid=0; jq -e . "$M10D/p/.claude/test-debt.json" >/dev/null 2>&1 && m10_valid=1
  m10_mut=$(jq -r '[.files[] | select(. == "scripts/check-gate.sh")] | length' "$M10D/p/.claude/test-debt.json" 2>/dev/null)
  if [ "$(_num "$m10_ctl")" -eq 0 ] && [ "$m10_valid" -eq 1 ] && [ "$(_num "$m10_mut")" -eq 1 ] \
     && [ "$m10_sites" -eq 1 ] && [ "$m10_changed" -eq 2 ] && [ "$m10_parses" -eq 1 ]; then
    pass "M10 (the census exclusion): control keeps a TRACKED scripts/check-gate.sh out of the ledger; with the exclusion neutered the framework's own gate script becomes the adoptee's untested debt — asserted on ledger BYTES, because an absent entry and an absent write look the same"
  else
    fail_ "M10" "control_entry=$m10_ctl (want 0) mutant_ledger_valid=$m10_valid (want 1) mutant_entry=$m10_mut (want 1) sites=$m10_sites (want 1) changed_lines=$m10_changed (want 2) parses=$m10_parses (want 1)"
  fi
fi

# ── M11: the git-config pin on the staged read ────────────────────────────
# Deleting `-c diff.renames=true` restores the measured silent bypass: under
# the adoptee's own `diff.renames=copies` the copied untested file enters the
# working set at rc 0 with zero bytes. A fix a user's .gitconfig can disable is
# not a fix, and this is what proves the pin is load-bearing rather than
# decorative.
M11D="$(newtmp)"
if ! mk_repo "$M11D/p" || ! mk_mirror "$M11D/m"; then
  fail_ "M11" "fixture setup failed"
else
  write_ledger "$M11D/p" "$(_mlib "$M11D/m")"
  set_tier "$M11D/p" '{"deployment":"personal","poc_mode":"production","enforcement_level":"strict"}'
  gitq "$M11D/p" config diff.renames copies
  cp "$M11D/p/src/paid.js" "$M11D/p/src/clone.js"
  printf 'export function paid() { return 2; }\n' > "$M11D/p/src/paid.js"
  gitq "$M11D/p" add -A
  check_in "$M11D/p" "$(_mlib "$M11D/m")"; m11_ctl=$CHK_RC
  # The real line MINUS the diff.renames pin and nothing else — the `&&` is
  # carried verbatim, which is what proves _mutate's `&` escaping works.
  m11_meta=$(_mutate "$M11D/m" '# BF-TD-STAGED-READ' '  staged="$( cd "$root" 2>/dev/null && git -c core.quotePath=false diff --cached --name-status 2>/dev/null )"')
  set -- $m11_meta; m11_sites=$1; m11_changed=$2; m11_parses=$3
  check_in "$M11D/p" "$(_mlib "$M11D/m")"; m11_mut=$CHK_RC
  m11_bytes=$(_bytes "$CHK_OUT")
  if [ "$m11_ctl" -eq 3 ] && [ "$m11_mut" -eq 0 ] && [ "$m11_bytes" -eq 0 ] \
     && [ "$m11_sites" -eq 1 ] && [ "$m11_changed" -eq 2 ] && [ "$m11_parses" -eq 1 ]; then
    pass "M11 (the config pin): control blocks the copied untested file with rc 3; dropping -c diff.renames=true from the staged read makes the SAME commit pass with zero bytes — the silent-bypass class, reproduced on demand"
  else
    fail_ "M11" "control_rc=$m11_ctl (want 3) mutant_rc=$m11_mut (want 0) mutant_bytes=$m11_bytes (want 0) sites=$m11_sites (want 1) changed_lines=$m11_changed (want 2) parses=$m11_parses (want 1)"
  fi
fi

# ── M8: no awk under this module ──────────────────────────────────────────
# `bash -n` does not syntax-check awk, so every mutant above would pass its
# parse check while a dead awk emitted an empty result that reads as "nothing
# wrong". The defence is structural: this module drives no awk. Pinned here so
# that introducing one has to argue with a test rather than slip in.
#
# Whole-line comments are stripped before counting, and only those: the module
# has to be able to EXPLAIN this rule in its own header, and a check that
# forbade the word would forbid the explanation. A trailing comment mentioning
# it would still count, which is the conservative direction — a false red on a
# comment costs a sentence, a false green on a live pipeline costs the
# property.
m8_awk=$(grep -v '^[[:space:]]*#' "$LIB" | grep -c '\bawk\b'); m8_awk=$(_num "$m8_awk")
if [ "$m8_awk" -eq 0 ]; then
  pass "M8: the module drives no awk — the 'a dead awk emits empty and empty reads as fine' failure mode is removed rather than defended against"
else
  fail_ "M8" "awk occurrences in $LIB: $m8_awk (want 0)"
fi

echo ""
echo "=== R — the refusal branches, which were the least-pinned code on this branch ==="

# WHY THIS SECTION EXISTS. The framework-exclusion fix introduced three
# refusals — refuse to write, block a check at strict, warn at light — and
# pinned NONE of them, because every mirror in this file was a complete clone.
# A reviewer flipped ONE character on the init.sh guard (`|| return 1` ->
# `|| return 0`) and the suite stayed at 50 passed, 0 failed: the mutant WROTE a
# ledger with the exclusion silently inert, which is exactly the guessing the
# fix advertised as foreclosed. The doctrine this file states twice about
# matcher atoms — a branch no fixture can reach is pinned by nothing — was not
# applied to the branch the fix was proudest of. No repo lint executes this
# module, so nothing else would have caught it either.

# R1 — --write from an incomplete clone: refuse, AND leave no file behind.
# Both halves, because "refused" and "wrote nothing" are separate facts and a
# writer that refuses after writing is the failure being prevented. The CONTROL
# is the same fixture against a COMPLETE mirror: without it this row is
# satisfied by any mirror too broken to run at all.
R1D="$(newtmp)"
if ! mk_repo_fw "$R1D/p" || ! mk_mirror "$R1D/m" noinit || ! mk_mirror "$R1D/full"; then
  fail_ "R1" "fixture setup failed"
else
  write_via "$R1D/m" "$R1D/p"; r1_rc=$LEDGER_RC
  r1_file=0; [ -e "$R1D/p/.claude/test-debt.json" ] && r1_file=1
  write_via "$R1D/full" "$R1D/p"; r1_ctl_rc=$LEDGER_RC
  r1_ctl_file=0; [ -s "$R1D/p/.claude/test-debt.json" ] && r1_ctl_file=1
  r1_ctl_fw=$(jq -r '[.files[] | select(. == "scripts/check-gate.sh")] | length' "$R1D/p/.claude/test-debt.json" 2>/dev/null)
  if [ "$r1_rc" -eq 2 ] && [ "$r1_file" -eq 0 ] \
     && [ "$r1_ctl_rc" -eq 0 ] && [ "$r1_ctl_file" -eq 1 ] && [ "$(_num "$r1_ctl_fw")" -eq 0 ]; then
    pass "R1: --write from a clone with no init.sh REFUSES at rc 2 and writes NO ledger; the same fixture against a complete mirror writes one (rc 0) that excludes the tracked framework path — refusal and silence are asserted separately"
  else
    fail_ "R1" "incomplete_clone_rc=$r1_rc (want 2) ledger_written_anyway=$r1_file (want 0) complete_clone_rc=$r1_ctl_rc (want 0) complete_clone_wrote=$r1_ctl_file (want 1) framework_path_in_control_ledger=$r1_ctl_fw (want 0)"
  fi
fi

# R2/R3 — the CHECK side of the same refusal, on both tiers that can speak.
# The ledger is written by the REAL module first, so the only thing the
# incomplete mirror changes is whether the arms can run at all.
R2D="$(newtmp)"
if ! mk_repo_fw "$R2D/p" || ! mk_mirror "$R2D/m" noinit; then
  fail_ "R2" "fixture setup failed"
else
  write_ledger "$R2D/p"
  set_tier "$R2D/p" '{"deployment":"personal","poc_mode":"production","enforcement_level":"strict"}'
  printf 'export function fresh() { return 9; }\n' > "$R2D/p/src/fresh.js"
  gitq "$R2D/p" add src/fresh.js
  check_in "$R2D/p" "$(_mlib "$R2D/m")"; r2_rc=$CHK_RC
  r2_said=0; grep -q 'inventory could not be derived' "$CHK_OUT" && r2_said=1
  if [ "$r2_rc" -eq 2 ] && [ "$r2_said" -eq 1 ]; then
    pass "R2: --check at strict from a clone with no init.sh is rc 2 (unusable), NOT rc 3 — it refuses to judge rather than judging with a census that cannot tell your code from the framework's"
  else
    fail_ "R2" "rc=$r2_rc (want 2, and specifically not 3) reason_stated=$r2_said (want 1)"
  fi

  set_tier "$R2D/p" '{"deployment":"personal","poc_mode":"production","enforcement_level":"light"}'
  check_in "$R2D/p" "$(_mlib "$R2D/m")"; r3_rc=$CHK_RC
  r3_warn=0; grep -q '^\[WARN\]' "$CHK_OUT" && r3_warn=1
  r3_block=0; grep -q 'BLOCKED' "$CHK_OUT" && r3_block=1
  if [ "$r3_rc" -eq 0 ] && [ "$r3_warn" -eq 1 ] && [ "$r3_block" -eq 0 ]; then
    pass "R3: the SAME incomplete clone at light WARNS and exits 0 — the refusal is tier-floored like everything else here, so an unusable clone cannot block a project that never asked for blocking"
  else
    fail_ "R3" "rc=$r3_rc (want 0) warned=$r3_warn (want 1) said_BLOCKED=$r3_block (want 0)"
  fi
fi

# R4 — an init.sh that exists but names no copy list at all. Reaches the
# NONEMPTY guard, which the noinit fixture short-circuits past.
R4D="$(newtmp)"
if ! mk_repo_fw "$R4D/p" || ! mk_mirror "$R4D/m" emptyinit; then
  fail_ "R4" "fixture setup failed"
else
  write_via "$R4D/m" "$R4D/p"; r4_rc=$LEDGER_RC
  r4_file=0; [ -e "$R4D/p/.claude/test-debt.json" ] && r4_file=1
  if [ "$r4_rc" -eq 2 ] && [ "$r4_file" -eq 0 ]; then
    pass "R4: an init.sh that parses to an EMPTY copy list is refused too (rc 2, no ledger) — an empty exclusion set is indistinguishable from no exclusion at all, and this is the guard that says so"
  else
    fail_ "R4" "rc=$r4_rc (want 2) ledger_written_anyway=$r4_file (want 0)"
  fi
fi

# R5 — the parser itself missing. Reaches the third guard.
R5D="$(newtmp)"
if ! mk_repo_fw "$R5D/p" || ! mk_mirror "$R5D/m" noparser; then
  fail_ "R5" "fixture setup failed"
else
  write_via "$R5D/m" "$R5D/p"; r5_rc=$LEDGER_RC
  r5_file=0; [ -e "$R5D/p/.claude/test-debt.json" ] && r5_file=1
  if [ "$r5_rc" -eq 2 ] && [ "$r5_file" -eq 0 ]; then
    pass "R5: a clone missing scaffold-shipped-set.sh is refused (rc 2, no ledger) — the third of three guards now has a fixture, so none of them is load-bearing on faith"
  else
    fail_ "R5" "rc=$r5_rc (want 2) ledger_written_anyway=$r5_file (want 0)"
  fi
fi

# ── M12: the reviewer's one-character mutant ──────────────────────────────
# `|| return 1` -> `|| return 0` on the init.sh guard. Verified to survive the
# 50/0 suite before R1-R5 existed. The mutant's expected result is a WRITE, so
# it is asserted on ledger BYTES: the file exists, it is valid JSON, and it
# names the framework path the exclusion should have removed.
M12D="$(newtmp)"
if ! mk_repo_fw "$M12D/p" || ! mk_mirror "$M12D/m" noinit; then
  fail_ "M12" "fixture setup failed"
else
  write_via "$M12D/m" "$M12D/p"; m12_ctl=$LEDGER_RC
  m12_ctl_file=0; [ -e "$M12D/p/.claude/test-debt.json" ] && m12_ctl_file=1
  m12_meta=$(_mutate "$M12D/m" '# BF-TD-SHIPPED-REQUIRED' '  [ -f "$TD_FRAMEWORK_ROOT/init.sh" ] || return 0')
  set -- $m12_meta; m12_sites=$1; m12_changed=$2; m12_parses=$3
  write_via "$M12D/m" "$M12D/p"; m12_mut=$LEDGER_RC
  m12_valid=0; jq -e . "$M12D/p/.claude/test-debt.json" >/dev/null 2>&1 && m12_valid=1
  m12_fw=$(jq -r '[.files[] | select(. == "scripts/check-gate.sh")] | length' "$M12D/p/.claude/test-debt.json" 2>/dev/null)
  if [ "$m12_ctl" -eq 2 ] && [ "$m12_ctl_file" -eq 0 ] && [ "$m12_mut" -eq 0 ] \
     && [ "$m12_valid" -eq 1 ] && [ "$(_num "$m12_fw")" -eq 1 ] \
     && [ "$m12_sites" -eq 1 ] && [ "$m12_changed" -eq 2 ] && [ "$m12_parses" -eq 1 ]; then
    pass "M12: control refuses an incomplete clone (rc 2, no file); flipping ONE character on the init.sh guard makes the module WRITE a ledger that names scripts/check-gate.sh — the exclusion silently inert, which is the guessing this guard exists to forbid"
  else
    fail_ "M12" "control_rc=$m12_ctl (want 2) control_wrote=$m12_ctl_file (want 0) mutant_rc=$m12_mut (want 0) mutant_ledger_valid=$m12_valid (want 1) framework_path_in_mutant_ledger=$m12_fw (want 1) sites=$m12_sites (want 1) changed_lines=$m12_changed (want 2) parses=$m12_parses (want 1)"
  fi
fi

# ── M13: the same flip on the NONEMPTY guard ──────────────────────────────
# The other reachable spelling of the same mistake, and the reason R4 exists:
# without an emptyinit fixture this guard would be exactly as unpinned as the
# init.sh one was.
M13D="$(newtmp)"
if ! mk_repo_fw "$M13D/p" || ! mk_mirror "$M13D/m" emptyinit; then
  fail_ "M13" "fixture setup failed"
else
  write_via "$M13D/m" "$M13D/p"; m13_ctl=$LEDGER_RC
  m13_meta=$(_mutate "$M13D/m" '# BF-TD-SHIPPED-NONEMPTY' '  [ -s "$TD_TMP/shipped" ] || return 0')
  set -- $m13_meta; m13_sites=$1; m13_changed=$2; m13_parses=$3
  write_via "$M13D/m" "$M13D/p"; m13_mut=$LEDGER_RC
  m13_fw=$(jq -r '[.files[] | select(. == "scripts/check-gate.sh")] | length' "$M13D/p/.claude/test-debt.json" 2>/dev/null)
  if [ "$m13_ctl" -eq 2 ] && [ "$m13_mut" -eq 0 ] && [ "$(_num "$m13_fw")" -eq 1 ] \
     && [ "$m13_sites" -eq 1 ] && [ "$m13_changed" -eq 2 ] && [ "$m13_parses" -eq 1 ]; then
    pass "M13: the same flip on the empty-inventory guard produces the same silent guess — asserted on the ledger's bytes, not on an exit code, because a written ledger is what makes it dangerous"
  else
    fail_ "M13" "control_rc=$m13_ctl (want 2) mutant_rc=$m13_mut (want 0) framework_path_in_mutant_ledger=$m13_fw (want 1) sites=$m13_sites (want 1) changed_lines=$m13_changed (want 2) parses=$m13_parses (want 1)"
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
