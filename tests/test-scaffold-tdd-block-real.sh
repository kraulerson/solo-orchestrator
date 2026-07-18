#!/usr/bin/env bash
# tests/test-scaffold-tdd-block-real.sh
#
# BL-088 scaffold-fidelity + backfill regression (init.sh-driven, hermetic).
#
# THE BUG (empirically proven, PR #173 adversarial review)
#   init.sh shipped a CURATED scripts/ copy list that was never updated when
#   BL-072 C2 added scripts/lib/tdd-classify.sh (sourced by pre-commit-gate.sh
#   via a silently-skipping loop). In a REAL scaffolded Sponsored-POC project,
#   a test-less feat: commit was therefore ALLOWED (rc=0) — the flagship TDD
#   hard block silently no-op'd. Same class: scripts/run-phase3-validation.sh
#   (the Phase-3→4 driver) was likewise unshipped.
#
# WHY THE BL-072 SUITE MISSED IT
#   Every BL-072 test copies tdd-classify.sh into its OWN fixture
#   (test-bl072-tdd-warn-detector.sh :311/:391 `cp "$REPO_ROOT"/scripts/lib/*.sh
#   ...`) — the fixture supplied the dependency the real scaffold lacked. This
#   test refuses to hand-copy: the fixture's scripts/ tree is byte-derived from
#   INIT.SH'S OWN copy mechanism (a full hermetic `--no-remote-creation` init),
#   so it fails whenever the SHIPPED SCAFFOLD carries the gap. Note the scope
#   (PR #175 verifier): init.sh's terminal `verify-install.sh --auto-fix` also
#   backfills these files, so a copy-list-only regression self-heals and does
#   NOT fail this test — tests/test-scaffold-source-closure.sh (PR-CI lane)
#   is the check that pins the copy list itself.
#
# Cases:
#   T-scaffold-ships-deps        the scaffold contains the four previously-
#                                omitted sourced deps (run-phase3 executable).
#   T-scaffold-tdd-block-real    deployment=organizational + poc_mode=
#                                sponsored_poc + init's commit-msg hook; a
#                                test-less feat: commit is BLOCKED (rc=1 +
#                                [FAIL]). RED on pre-BL-088 main (rc=0).
#   T-scaffold-phase3-driver-present  run-phase3-validation.sh present + exec.
#   T-backfill-upgrade           OLD-list project (4 files deleted) → repo
#                                upgrade-project.sh --backfill-only → files
#                                restored AND the TDD block now enforces (rc=1).
#   T-backfill-verify            OLD-list project → verify-install --auto-fix →
#                                files restored.
#
# Hermetic: mktemp, git identity set locally, GITHUB_BASE_REF unset, init.sh
# run with --no-remote-creation (the blessed no-live-remote path). bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT="$REPO_ROOT/init.sh"
UPGRADE="$REPO_ROOT/scripts/upgrade-project.sh"
VERIFY="$REPO_ROOT/scripts/verify-install.sh"

unset GITHUB_BASE_REF 2>/dev/null || true

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# Dependency guard — init.sh needs jq + git.
if ! command -v jq >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  echo "SKIP: jq/git required for the init.sh-driven scaffold test"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

# ── One hermetic init: build the canonical scaffold ONCE (byte-derived) ─────
SCAFFOLD="$TOPTMP/scaffold"
echo "=== Scaffolding a Sponsored-POC project via real init.sh (hermetic) ==="
init_err="$TOPTMP/init.err"
( cd "$TOPTMP" && "$INIT" --non-interactive \
    --project bl088-scaffold \
    --platform web \
    --deployment organizational \
    --gov-mode sponsored_poc \
    --language typescript \
    --git-host github \
    --visibility private \
    --project-dir "$SCAFFOLD" \
    --no-remote-creation ) >"$TOPTMP/init.out" 2>"$init_err"
init_rc=$?
if [ "$init_rc" -ne 0 ]; then
  fail_ "scaffold-init" "init.sh exited $init_rc; stderr tail: $(tail -8 "$init_err" | tr '\n' '|')"
  echo "Results: $PASSED passed, $FAILED failed"
  exit 1
fi

# ── T-scaffold-ships-deps ───────────────────────────────────────────────────
echo "=== T-scaffold-ships-deps: the four sourced gate deps are present ==="
deps_ok=1
for rel in scripts/lib/tdd-classify.sh scripts/lib/phase2-state.sh \
           scripts/lib/cdf-refresh.sh scripts/run-phase3-validation.sh; do
  [ -f "$SCAFFOLD/$rel" ] || { deps_ok=0; echo "    missing: $rel"; }
done
if [ "$deps_ok" -eq 1 ]; then
  pass "T-scaffold-ships-deps: tdd-classify, phase2-state, cdf-refresh, run-phase3-validation all shipped"
else
  fail_ "T-scaffold-ships-deps" "init.sh omitted one or more sourced deps (the BL-088 gap)"
fi

# ── T-scaffold-phase3-driver-present ────────────────────────────────────────
echo "=== T-scaffold-phase3-driver-present: driver present + executable ==="
if [ -x "$SCAFFOLD/scripts/run-phase3-validation.sh" ]; then
  pass "T-scaffold-phase3-driver-present: scripts/run-phase3-validation.sh is executable"
else
  fail_ "T-scaffold-phase3-driver-present" "run-phase3-validation.sh missing or not executable (Phase-3→4 pass-path unreachable)"
fi

# feat_commit_blocks <project_dir> <label> — stage a test-less feat: impl and
# attempt a commit; echoes "BLOCKED" (rc=1) or "ALLOWED" (rc=0).
feat_commit_blocks() {
  local proj="$1" tag="$2" rc=0
  ( cd "$proj"
    git config user.email bl088@test.invalid
    git config user.name  bl088-test
    mkdir -p "src_$tag"
    printf 'export const add_%s = (a: number, b: number): number => a + b;\n' "$tag" > "src_$tag/widget.ts"
    git add "src_$tag/widget.ts"
    git commit -m "feat: add widget $tag without a test" >"$proj/commit.$tag.log" 2>&1 )
  rc=$?
  [ "$rc" -eq 0 ] && echo "ALLOWED" || echo "BLOCKED"
}

# ── T-scaffold-tdd-block-real ───────────────────────────────────────────────
echo "=== T-scaffold-tdd-block-real: test-less feat: commit is BLOCKED (rc=1) ==="
BLK="$TOPTMP/blk"
cp -r "$SCAFFOLD" "$BLK"
# Confirm init installed the commit-msg hook the way it ships it.
if ! grep -q 'tdd-only' "$BLK/.git/hooks/commit-msg" 2>/dev/null; then
  fail_ "T-scaffold-tdd-block-real" "init.sh did not install the --tdd-only commit-msg hook"
else
  verdict="$(feat_commit_blocks "$BLK" main)"
  if [ "$verdict" = "BLOCKED" ] && grep -q 'BL-072 TDD ordering' "$BLK/commit.main.log"; then
    pass "T-scaffold-tdd-block-real: sponsored-POC scaffold blocks the test-less feat: commit"
  else
    fail_ "T-scaffold-tdd-block-real" "expected BLOCKED+[FAIL]; got $verdict; log: $(tail -3 "$BLK/commit.main.log" | tr '\n' '|')"
  fi
fi

# ── T-backfill-upgrade ──────────────────────────────────────────────────────
# Simulate a pre-BL-088 project: delete the four files, then heal via the repo
# upgrade-project.sh --backfill-only (source-closure backfill, after the BL-015
# sentinel guard). Assert restore AND that the TDD block then enforces.
echo "=== T-backfill-upgrade: OLD-list project → upgrade --backfill-only heals ==="
BFU="$TOPTMP/bf-upgrade"
cp -r "$SCAFFOLD" "$BFU"
rm -f "$BFU/scripts/lib/tdd-classify.sh" "$BFU/scripts/lib/phase2-state.sh" \
      "$BFU/scripts/lib/cdf-refresh.sh"  "$BFU/scripts/run-phase3-validation.sh"
( cd "$BFU" && bash "$UPGRADE" --backfill-only ) >"$TOPTMP/bf-upgrade.log" 2>&1
bfu_rc=$?
bfu_ok=1
for rel in scripts/lib/tdd-classify.sh scripts/lib/phase2-state.sh \
           scripts/lib/cdf-refresh.sh scripts/run-phase3-validation.sh; do
  [ -f "$BFU/$rel" ] || { bfu_ok=0; echo "    not restored: $rel"; }
done
if [ "$bfu_ok" -eq 1 ] && [ -x "$BFU/scripts/run-phase3-validation.sh" ] && [ "$bfu_rc" -eq 0 ]; then
  verdict="$(feat_commit_blocks "$BFU" bf)"
  if [ "$verdict" = "BLOCKED" ]; then
    pass "T-backfill-upgrade: --backfill-only restored all four deps; TDD block now enforces"
  else
    fail_ "T-backfill-upgrade" "files restored but the TDD block did NOT engage (got $verdict)"
  fi
else
  fail_ "T-backfill-upgrade" "backfill rc=$bfu_rc; restore incomplete or driver not executable"
fi

# ── T-backfill-verify ───────────────────────────────────────────────────────
echo "=== T-backfill-verify: OLD-list project → verify-install --auto-fix heals ==="
BFV="$TOPTMP/bf-verify"
cp -r "$SCAFFOLD" "$BFV"
rm -f "$BFV/scripts/lib/tdd-classify.sh" "$BFV/scripts/lib/phase2-state.sh" \
      "$BFV/scripts/lib/cdf-refresh.sh"  "$BFV/scripts/run-phase3-validation.sh"
# Ensure the fixup source resolves to the framework under test.
mkdir -p "$BFV/.claude"
printf '{"source_dir":"%s"}\n' "$REPO_ROOT" > "$BFV/.claude/orchestrator-source.json"
( cd "$BFV" && bash "$VERIFY" --auto-fix ) >"$TOPTMP/bf-verify.log" 2>&1
bfv_ok=1
for rel in scripts/lib/tdd-classify.sh scripts/lib/phase2-state.sh \
           scripts/lib/cdf-refresh.sh scripts/run-phase3-validation.sh; do
  [ -f "$BFV/$rel" ] || { bfv_ok=0; echo "    not restored: $rel"; }
done
if [ "$bfv_ok" -eq 1 ] && [ -x "$BFV/scripts/run-phase3-validation.sh" ]; then
  pass "T-backfill-verify: verify-install --auto-fix restored all four deps"
else
  fail_ "T-backfill-verify" "verify --auto-fix did not restore all four deps (see bf-verify.log)"
fi

# ── BL-107: the language axis — rust + `other` scaffolds get the gate too ───
# Before BL-107 these two languages received NO commit-msg hook at all (the
# empty-test-pattern skip), so the flagship TDD hard block did not exist for
# them on any tier. Each case runs its own REAL hermetic init.

echo "=== T-scaffold-rust-tdd (BL-107): rust scaffold blocks test-less feat:, allows inline #[cfg(test)] ==="
RUSTS="$TOPTMP/rust-scaffold"
( cd "$TOPTMP" && "$INIT" --non-interactive \
    --project bl107-rust \
    --platform web \
    --deployment organizational \
    --gov-mode sponsored_poc \
    --language rust \
    --git-host github \
    --visibility private \
    --project-dir "$RUSTS" \
    --no-remote-creation ) >"$TOPTMP/init-rust.out" 2>"$TOPTMP/init-rust.err"
if [ $? -ne 0 ]; then
  fail_ "T-scaffold-rust-tdd" "rust init.sh failed: $(tail -5 "$TOPTMP/init-rust.err" | tr '\n' '|')"
elif ! grep -q 'tdd-only' "$RUSTS/.git/hooks/commit-msg" 2>/dev/null; then
  fail_ "T-scaffold-rust-tdd" "rust scaffold has NO --tdd-only commit-msg hook — BL-107's universal install regressed (whole language unprotected)"
else
  ( cd "$RUSTS"
    git config user.email bl107@test.invalid
    git config user.name  bl107-test
    mkdir -p src
    printf 'pub fn add(a: i32, b: i32) -> i32 { a + b }\n' > src/widget.rs
    git add src/widget.rs
    git commit -m "feat: rust widget without a test" >"$RUSTS/commit.rust-impl.log" 2>&1 )
  rust_impl_rc=$?
  ( cd "$RUSTS"
    printf 'pub fn add(a: i32, b: i32) -> i32 { a + b }\n\n#[cfg(test)]\nmod tests {\n    #[test]\n    fn adds() { assert_eq!(super::add(2, 2), 4); }\n}\n' > src/widget.rs
    git add src/widget.rs
    git commit -m "feat: rust widget with inline tests" >"$RUSTS/commit.rust-inline.log" 2>&1 )
  rust_inline_rc=$?
  if [ "$rust_impl_rc" -eq 0 ]; then
    fail_ "T-scaffold-rust-tdd" "test-less rust feat: commit LANDED on the sponsored-POC scaffold: $(tail -2 "$RUSTS/commit.rust-impl.log" | tr '\n' '|')"
  elif ! grep -q 'BL-072 TDD ordering' "$RUSTS/commit.rust-impl.log"; then
    fail_ "T-scaffold-rust-tdd" "blocked, but not by the BL-072 arm: $(tail -3 "$RUSTS/commit.rust-impl.log" | tr '\n' '|')"
  elif [ "$rust_inline_rc" -ne 0 ]; then
    fail_ "T-scaffold-rust-tdd" "an inline-#[cfg(test)] rust commit was BLOCKED (false block — the content probe is not reaching the scaffold): $(tail -3 "$RUSTS/commit.rust-inline.log" | tr '\n' '|')"
  else
    pass "T-scaffold-rust-tdd: rust scaffold blocks test-less feat: and allows inline-test commits"
  fi
fi

echo "=== T-scaffold-other-tdd (BL-107): other-language scaffold blocks test-less feat:, allows tests/-tree ==="
OTHERS="$TOPTMP/other-scaffold"
( cd "$TOPTMP" && "$INIT" --non-interactive \
    --project bl107-other \
    --platform web \
    --deployment organizational \
    --gov-mode sponsored_poc \
    --language other \
    --git-host github \
    --visibility private \
    --project-dir "$OTHERS" \
    --no-remote-creation ) >"$TOPTMP/init-other.out" 2>"$TOPTMP/init-other.err"
if [ $? -ne 0 ]; then
  fail_ "T-scaffold-other-tdd" "other init.sh failed: $(tail -5 "$TOPTMP/init-other.err" | tr '\n' '|')"
elif ! grep -q 'tdd-only' "$OTHERS/.git/hooks/commit-msg" 2>/dev/null; then
  fail_ "T-scaffold-other-tdd" "other-language scaffold has NO --tdd-only commit-msg hook — the catch-all axis is unprotected again"
else
  ( cd "$OTHERS"
    git config user.email bl107@test.invalid
    git config user.name  bl107-test
    mkdir -p src
    printf 'fn main = print "hi"\n' > src/widget.xyz
    git add src/widget.xyz
    git commit -m "feat: other widget without a test" >"$OTHERS/commit.other-impl.log" 2>&1 )
  other_impl_rc=$?
  ( cd "$OTHERS"
    mkdir -p tests
    printf 'assert widget == "hi"\n' > tests/widget.xyz
    git add tests/widget.xyz
    git commit -m "feat: other widget with a test" >"$OTHERS/commit.other-test.log" 2>&1 )
  other_test_rc=$?
  if [ "$other_impl_rc" -eq 0 ]; then
    fail_ "T-scaffold-other-tdd" "test-less other-language feat: commit LANDED: $(tail -2 "$OTHERS/commit.other-impl.log" | tr '\n' '|')"
  elif ! grep -q 'BL-072 TDD ordering' "$OTHERS/commit.other-impl.log"; then
    fail_ "T-scaffold-other-tdd" "blocked, but not by the BL-072 arm: $(tail -3 "$OTHERS/commit.other-impl.log" | tr '\n' '|')"
  elif [ "$other_test_rc" -ne 0 ]; then
    fail_ "T-scaffold-other-tdd" "a tests/-tree other-language commit was BLOCKED (the generic heuristic is not serving): $(tail -3 "$OTHERS/commit.other-test.log" | tr '\n' '|')"
  else
    pass "T-scaffold-other-tdd: other-language scaffold blocks test-less feat: and allows tests/-tree commits"
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
