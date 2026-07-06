#!/usr/bin/env bash
# tests/test-lint-no-live-remote.sh — behavior suite for
# scripts/lint-no-live-remote-in-tests.sh (BL-076).
#
# The lint is the merge-time backstop that stops a test from executing
# init.sh in a shape that can create a REAL remote repo against an
# authenticated host (the `kraulerson/foo` leak, 2026-07-06). These
# cases pin its detection contract so a regression in the LINT itself
# (a false negative that lets a live-remote run through, or a false
# positive on a reporter string / static grep / mocked run) is caught.
#
# Each case writes a synthetic fixture into an isolated temp dir and
# points the lint at it with --dir, so the assertions never depend on
# the live tests/ tree.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINT="$REPO_ROOT/scripts/lint-no-live-remote-in-tests.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# run_case NAME EXPECT_RC <<'FIXTURE'  ... fixture body ...
# Writes the heredoc to $dir/fixture.sh and asserts the lint's exit code.
assert_lint() {
  local name="$1" expect="$2" body="$3"
  local dir rc=0
  dir=$(mktemp -d)
  printf '%s\n' "$body" > "$dir/fixture.sh"
  bash "$LINT" --dir "$dir" >/dev/null 2>&1 || rc=$?
  if [ "$rc" = "$expect" ]; then
    pass "$name (rc=$rc)"
  else
    fail_ "$name" "expected rc=$expect, got rc=$rc"
  fi
  rm -rf "$dir"
}

echo "== tests/test-lint-no-live-remote.sh =="

# N1: bare github/default-host init run, no hermetic token → VIOLATION.
assert_lint "N1: default-host init run without guard is flagged" 1 \
'#!/usr/bin/env bash
INIT="$REPO_ROOT/init.sh"
bash "$INIT" --non-interactive --project x --project-dir "$P" --platform web'

# N2: same run + --no-remote-creation → hermetic.
assert_lint "N2: --no-remote-creation clears the violation" 0 \
'#!/usr/bin/env bash
INIT="$REPO_ROOT/init.sh"
bash "$INIT" --non-interactive --project x --project-dir "$P" --no-remote-creation --platform web'

# N3: --git-host other (URL-paste path, no CLI) → hermetic.
assert_lint "N3: --git-host other is hermetic" 0 \
'#!/usr/bin/env bash
INIT="$REPO_ROOT/init.sh"
bash "$INIT" --non-interactive --project x --git-host other --remote-url https://example.com/x.git'

# N4: --dry-run → hermetic.
assert_lint "N4: --dry-run is hermetic" 0 \
'#!/usr/bin/env bash
printf "%s\n" "$IN" | bash "$REPO/init.sh" --dry-run'

# N5: --validate-only → hermetic (exits before scaffold).
assert_lint "N5: --validate-only is hermetic" 0 \
'#!/usr/bin/env bash
INIT_SH="$REPO_ROOT/init.sh"
"$INIT_SH" --non-interactive --validate-only --project p --platform web'

# N6: CRITICAL — multi-line continuation with the guard on the NEXT
# physical line (the real corpus shape). Must be treated as hermetic.
assert_lint "N6: guard on backslash-continuation line is honored" 0 \
'#!/usr/bin/env bash
INIT="$REPO_ROOT/init.sh"
bash "$INIT" --non-interactive \
  --project x --platform web \
  --no-remote-creation \
  --project-dir "$P"'

# N7: CRITICAL — multi-line continuation WITHOUT the guard anywhere in
# the joined command → VIOLATION (the unfixed mobile-test shape).
assert_lint "N7: multi-line run with no guard is flagged" 1 \
'#!/usr/bin/env bash
INIT_SH="$REPO_ROOT/init.sh"
out=$(cd "$cwd" && env "$e" "$INIT_SH" \
  --non-interactive \
  --platform mobile \
  --project foo \
  --project-dir "$P" </dev/null 2>&1)'

# N8: mock-driven file (write_mock_gh + $MOCK_DIR on PATH) → hermetic
# even though the run uses --git-host github with no --no-remote-creation.
assert_lint "N8: mocked-CLI file is exempt" 0 \
'#!/usr/bin/env bash
INIT="$REPO_ROOT/init.sh"
write_mock_gh() { :; }
write_mock_gh "$MOCK_DIR"
export PATH="$MOCK_DIR:$PATH"
bash "$INIT" --non-interactive --project x --git-host github --visibility private'

# N9: reporter strings that MENTION init.sh --non-interactive must NOT be
# flagged — they are not executions.
assert_lint "N9: reporter strings are not flagged" 0 \
'#!/usr/bin/env bash
section "init.sh --non-interactive honors AUTO_INSTALL_TOOLS"
echo "  Testing init.sh --non-interactive with read-only dir"
pass "init.sh --non-interactive tests (3/3)"'

# N10: static source analysis (grep / bash -n of init.sh) must NOT be
# flagged — no execution, no remote.
assert_lint "N10: static grep / bash -n of init.sh is not flagged" 0 \
'#!/usr/bin/env bash
INIT_SH="$REPO_ROOT/init.sh"
grep -q "get_available_platforms" "$INIT_SH" || exit 1
bash -n "$INIT_SH"
for f in "$INIT_SH"; do echo "$f"; done'

# N11: allowlist marker with a non-empty reason → hermetic.
assert_lint "N11: allow marker with reason passes" 0 \
'#!/usr/bin/env bash
INIT="$REPO_ROOT/init.sh"
bash "$INIT" --non-interactive --project x --platform web # lint-no-live-remote: allow drives a throwaway sandbox host'

# N12: allowlist marker with an EMPTY reason → still a VIOLATION.
assert_lint "N12: allow marker with empty reason fails" 1 \
'#!/usr/bin/env bash
INIT="$REPO_ROOT/init.sh"
bash "$INIT" --non-interactive --project x --platform web # lint-no-live-remote: allow'

# N13: gitlab / bitbucket first-class hosts with no guard are ALSO
# flagged (not just github) — any first-class host reaches a live CLI.
assert_lint "N13: gitlab host without guard is flagged" 1 \
'#!/usr/bin/env bash
INIT="$REPO_ROOT/init.sh"
bash "$INIT" --non-interactive --project x --git-host gitlab --platform web'

# N14: end-to-end — the REAL repo tree must currently pass clean.
real_rc=0
bash "$LINT" >/dev/null 2>&1 || real_rc=$?
if [ "$real_rc" = "0" ]; then
  pass "N14: live tests/ tree passes the lint (rc=0)"
else
  fail_ "N14" "live tests/ tree is non-hermetic (rc=$real_rc); run: bash scripts/lint-no-live-remote-in-tests.sh --list"
fi

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
