#!/usr/bin/env bash
# tests/test-bl107-tdd-all-languages.sh — BL-107: every language gets a TDD
# gate, and idiomatic inline Rust tests count as tests.
#
# WHY THIS EXISTS (BL-107, High)
#   init.sh installed the BL-072/BL-010 commit-msg gate ONLY for languages
#   whose soif_lang_test_pattern was non-empty — Rust (inline #[cfg(test)]
#   tests, empty by design) and the `*)` catch-all (`other`) received NO
#   commit-msg hook at all, including on organizational/sponsored tiers where
#   the docs advertise the TDD block as non-bypassable. The sync path and the
#   Currency manifest replicated the skip (absent-intentional /
#   absent-unavailable).
#
#   The fix installs the gate for EVERY language. That is only CORRECT with a
#   content probe (# BL-107-RUST-INLINE-TESTS in _tdd_triggers): a staged .rs
#   diff that ADDS `#[test]` / `#[cfg(test)]` is test evidence — without the
#   probe, an idiomatically-TDD'd inline-test Rust commit would be FALSELY
#   BLOCKED the moment the hook exists. `other` languages rely on the
#   classifier's generic conventions (tests/ trees + cross-language filename
#   table), which is the conservative any-test-file heuristic BL-107 asks for.
#
# CASES
#   T-rust-inline-test-not-blocked   sponsored-POC (hard-block tier), staged
#                                    lib.rs adding impl AND #[cfg(test)] mod →
#                                    --tdd-only must ALLOW (the probe sees the
#                                    inline test). THE false-block RED.
#   T-rust-impl-only-blocked         staged lib.rs adding impl only → HARD
#                                    BLOCK (regression pin: the gate fires for
#                                    rust like any language).
#   T-other-impl-only-blocked        unknown-extension impl file only → HARD
#                                    BLOCK (the `other` axis is gated).
#   T-other-generic-test-allows      unknown-extension impl + tests/-tree file
#                                    → ALLOW (generic conventions serve as the
#                                    conservative heuristic).
#   T-currency-hook-state-present    soif_currency_hook_state commit-msg ×
#                                    {rust, other} → "present" (the manifest
#                                    predicate mirrors the universal install).
#
#   The INSTALL half of BL-107 (real scaffolds get the hook file) is proven by
#   the init.sh-driven fidelity test (test-scaffold-tdd-block-real.sh rust/
#   other cases) — aggregator lane; this suite is the fast hermetic half.
#
# REGISTRATION: no init.sh, not an aggregator → BOTH lists.
# Hermetic: mktemp fixtures, local git identity, no network. bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

unset GITHUB_BASE_REF 2>/dev/null || true

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# Sponsored-POC scratch project: the NON-bypassable tier, so a firing TDD gate
# HARD-BLOCKS (exit 1) rather than warns. current_phase=1 keeps the BL-006
# message check short-circuited (< 2) so the TDD arm alone decides.
mk_proj() {
  local d="$1"
  rm -rf "$d"
  mkdir -p "$d/.claude" "$d/scripts/lib"
  ( cd "$d" \
      && git init -q \
      && git config user.email "bl107@test.invalid" \
      && git config user.name  "BL-107 Test" \
      && echo "# scratch" > README.md \
      && git add README.md \
      && git commit -q -m "chore: init" ) || return 1
  cat > "$d/.claude/manifest.json" <<'EOF'
{"frameworkVersion":"test","host":"other","mode":"personal","deployment":"organizational","enforcement_level":"strict"}
EOF
  cat > "$d/.claude/phase-state.json" <<'EOF'
{"current_phase":1,"track":"full","deployment":"organizational","poc_mode":"sponsored_poc","phases":{}}
EOF
  cat > "$d/.claude/process-state.json" <<'EOF'
{"phase2_init":{"steps_completed":[],"verified":false},"build_loop":{"feature":null,"step":0,"steps_completed":[]},"uat_session":{},"phase3_validation":{},"phase4_release":{}}
EOF
  cp "$REPO_ROOT/scripts/pre-commit-gate.sh"   "$d/scripts/"
  cp "$REPO_ROOT/scripts/process-checklist.sh" "$d/scripts/"
  cp "$REPO_ROOT/scripts/lib/helpers.sh" \
     "$REPO_ROOT/scripts/lib/helpers-core.sh" \
     "$REPO_ROOT/scripts/lib/helpers-full.sh" \
     "$REPO_ROOT/scripts/lib/tdd-classify.sh" "$d/scripts/lib/"
  chmod +x "$d/scripts/pre-commit-gate.sh" "$d/scripts/process-checklist.sh"
}

# run_tdd <proj> <subject> — stage is caller's job; runs the commit-msg surface.
run_tdd() {
  local d="$1" subject="$2"
  printf '%s\n' "$subject" > "$d/.git/COMMIT_EDITMSG"
  ( cd "$d" && bash scripts/pre-commit-gate.sh --terminal-mode --tdd-only 2>&1 )
}

# ── T-rust-inline-test-not-blocked ───────────────────────────────────────────
echo "=== T-rust-inline-test-not-blocked ==="
P="$TOPTMP/rust-tdd"
if ! mk_proj "$P"; then
  fail_ "T-rust-inline-test-not-blocked" "fixture setup failed"
else
  mkdir -p "$P/src"
  cat > "$P/src/lib.rs" <<'RS'
pub fn add(a: i32, b: i32) -> i32 {
    a + b
}

#[cfg(test)]
mod tests {
    use super::add;

    #[test]
    fn adds() {
        assert_eq!(add(2, 2), 4);
    }
}
RS
  ( cd "$P" && git add src/lib.rs )
  out=$(run_tdd "$P" "feat: add with inline tests"); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "T-rust-inline-test-not-blocked"
  else
    fail_ "T-rust-inline-test-not-blocked" "an idiomatically-TDD'd Rust commit (impl + inline #[cfg(test)] in the SAME staged diff) was BLOCKED (rc=$rc) — the gate cannot see inline tests, so installing it for rust would false-block: $(printf '%s' "$out" | grep -E 'FAIL|BLOCK' | head -1)"
  fi
fi

# ── T-rust-attr-family-not-blocked ───────────────────────────────────────────
# Verifier finding 1: the probe must also recognize the non-std test-attribute
# family — #[tokio::test] foremost (async Rust's default), plus rstest/
# wasm_bindgen_test/quickcheck/proptest and cfg(all(test,…))/cfg(any(test,…)).
# A miss here FALSE-BLOCKS an idiomatic commit on the non-bypassable tier.
echo "=== T-rust-attr-family-not-blocked ==="
P="$TOPTMP/rust-attr"
if ! mk_proj "$P"; then
  fail_ "T-rust-attr-family-not-blocked" "fixture setup failed"
else
  mkdir -p "$P/src"
  cat > "$P/src/lib.rs" <<'RS'
pub async fn fetch(x: u32) -> u32 {
    x + 1
}

#[cfg(all(test, feature = "net"))]
mod tests {
    #[tokio::test]
    async fn fetches() {
        assert_eq!(super::fetch(1).await, 2);
    }
}
RS
  ( cd "$P" && git add src/lib.rs )
  out=$(run_tdd "$P" "feat: async fetch with tokio test"); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "T-rust-attr-family-not-blocked"
  else
    fail_ "T-rust-attr-family-not-blocked" "a #[tokio::test]/cfg(all(test,…)) commit was BLOCKED (rc=$rc) — the probe regex misses the non-std attribute family: $(printf '%s' "$out" | grep -E 'FAIL|BLOCK' | head -1)"
  fi
fi

# ── T-rust-ext-diff-immune ───────────────────────────────────────────────────
# Verifier finding 2: `git config diff.external …` (difftastic-style setups)
# replaces porcelain diff output and blinds a probe that forgets --no-ext-diff
# — EVERY inline-test rust commit then false-fires. The probe must read git's
# own patch, not the operator's viewer.
echo "=== T-rust-ext-diff-immune ==="
P="$TOPTMP/rust-extdiff"
if ! mk_proj "$P"; then
  fail_ "T-rust-ext-diff-immune" "fixture setup failed"
else
  mkdir -p "$P/src"
  cat > "$P/src/lib.rs" <<'RS'
pub fn add(a: i32, b: i32) -> i32 {
    a + b
}

#[cfg(test)]
mod tests {
    #[test]
    fn adds() {
        assert_eq!(super::add(2, 2), 4);
    }
}
RS
  ( cd "$P" && git config diff.external /usr/bin/true && git add src/lib.rs )
  out=$(run_tdd "$P" "feat: add with inline tests under ext-diff"); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "T-rust-ext-diff-immune"
  else
    fail_ "T-rust-ext-diff-immune" "with diff.external configured, an inline-test commit was BLOCKED (rc=$rc) — the probe is reading the external diff driver's output instead of git's patch (--no-ext-diff missing)"
  fi
fi

# ── T-rust-impl-only-blocked ─────────────────────────────────────────────────
echo "=== T-rust-impl-only-blocked ==="
P="$TOPTMP/rust-impl"
if ! mk_proj "$P"; then
  fail_ "T-rust-impl-only-blocked" "fixture setup failed"
else
  mkdir -p "$P/src"
  printf 'pub fn add(a: i32, b: i32) -> i32 { a + b }\n' > "$P/src/lib.rs"
  ( cd "$P" && git add src/lib.rs )
  out=$(run_tdd "$P" "feat: add impl only"); rc=$?
  if [ "$rc" -ne 0 ]; then
    pass "T-rust-impl-only-blocked"
  else
    fail_ "T-rust-impl-only-blocked" "a test-less rust feat: commit PASSED the non-bypassable tier — the TDD gate does not fire for rust"
  fi
fi

# ── T-other-impl-only-blocked ────────────────────────────────────────────────
echo "=== T-other-impl-only-blocked ==="
P="$TOPTMP/other-impl"
if ! mk_proj "$P"; then
  fail_ "T-other-impl-only-blocked" "fixture setup failed"
else
  mkdir -p "$P/src"
  printf 'fn main = print "hi"\n' > "$P/src/main.xyz"
  ( cd "$P" && git add src/main.xyz )
  out=$(run_tdd "$P" "feat: other-language impl only"); rc=$?
  if [ "$rc" -ne 0 ]; then
    pass "T-other-impl-only-blocked"
  else
    fail_ "T-other-impl-only-blocked" "a test-less other-language feat: commit PASSED the non-bypassable tier"
  fi
fi

# ── T-other-generic-test-allows ──────────────────────────────────────────────
echo "=== T-other-generic-test-allows ==="
P="$TOPTMP/other-test"
if ! mk_proj "$P"; then
  fail_ "T-other-generic-test-allows" "fixture setup failed"
else
  mkdir -p "$P/src" "$P/tests"
  printf 'fn main = print "hi"\n' > "$P/src/main.xyz"
  printf 'assert main == "hi"\n' > "$P/tests/main.xyz"
  ( cd "$P" && git add src/main.xyz tests/main.xyz )
  out=$(run_tdd "$P" "feat: other-language with test"); rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "T-other-generic-test-allows"
  else
    fail_ "T-other-generic-test-allows" "an other-language commit WITH a tests/-tree file was blocked (rc=$rc) — the generic conventions are not serving as the heuristic: $(printf '%s' "$out" | grep -E 'FAIL|BLOCK' | head -1)"
  fi
fi

# ── T-currency-hook-state-present ────────────────────────────────────────────
echo "=== T-currency-hook-state-present ==="
# shellcheck source=/dev/null
. "$REPO_ROOT/scripts/lib/hook-templates.sh"
# shellcheck source=/dev/null
. "$REPO_ROOT/scripts/lib/currency-manifest.sh"
rust_state="$(soif_currency_hook_state commit-msg rust)"
other_state="$(soif_currency_hook_state commit-msg other)"
if [ "$rust_state" = "present" ] && [ "$other_state" = "present" ]; then
  pass "T-currency-hook-state-present"
else
  fail_ "T-currency-hook-state-present" "commit-msg expectation is rust='$rust_state' other='$other_state', want present/present — the manifest predicate still encodes the BL-107 skip, so freshness checks would flag (or excuse) the universally-installed hook"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
