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

# ── BL-346: an init run spelled through an interpreter WORD ─────────────
# Found reviewing PR #478 (2026-10-09). Its suite ran
#   OUT="$( cd "$REPO_ROOT" && "$BASH" ./init.sh --non-interactive \ … )"
# and the lint did not see an init.sh EXECUTION there at all, so deleting
# --no-remote-creation still gave rc 0. Before BL-346 only the literal word
# `bash` (or an `env …` prefix) counted as an interpreter in front of an
# init token. Every spelling below gets a PAIR, and each half asserts the
# --list ROW as well as the exit code: an UNRECOGNISED run also exits 0 —
# that is the blind spot — so "guard present => rc 0" proves nothing unless
# a `PASS hermetic-token` row shows the lint saw the run.

ROW_HERMETIC="$(printf 'PASS\thermetic-token')"
ROW_LIVE="$(printf 'FAIL\tlive-remote-reachable')"

# assert_lint_row NAME EXPECT_RC EXPECT_ROWS BODY — EXPECT_ROWS is the exact
# set of STATUS<TAB>DETAIL rows (the FILE:LINE column dropped); "" = no row.
assert_lint_row() {
  local name="$1" expect="$2" want="$3" body="$4"
  local dir="" rc=0 got=""
  dir=$(mktemp -d)
  printf '%s\n' "$body" > "$dir/fixture.sh"
  got=$(bash "$LINT" --list --dir "$dir" 2>/dev/null) || rc=$?
  got=$(printf '%s\n' "$got" | awk -F'\t' '$1 == "PASS" || $1 == "FAIL" { print $1 "\t" $3 }')
  if [ "$rc" = "$expect" ] && [ "$got" = "$want" ]; then
    pass "$name (rc=$rc)"
  else
    fail_ "$name" "expected rc=$expect rows=[$want], got rc=$rc rows=[$got]"
  fi
  rm -rf "$dir"
}

# assert_interp_pair ID SPELLING — SPELLING is everything in front of the
# first flag. The fixture names --git-host github and puts the guard on its
# own continuation line, as PR #478's suite does.
assert_interp_pair() {
  local id="$1" spelling="$2"
  local head='#!/usr/bin/env bash
INIT="$REPO_ROOT/init.sh"'
  assert_lint_row "$id: $spelling + --no-remote-creation is seen and hermetic" 0 "$ROW_HERMETIC" \
"$head
$spelling --non-interactive --project x --git-host github \\
  --no-remote-creation \\
  --project-dir \"\$P\""
  assert_lint_row "$id: $spelling with the guard deleted is flagged" 1 "$ROW_LIVE" \
"$head
$spelling --non-interactive --project x --git-host github \\
  --project-dir \"\$P\""
}

# Recognised before BL-346 — pinned so the fix cannot lose them.
assert_interp_pair N15 'bash ./init.sh'
assert_interp_pair N16 'env "$BASH" ./init.sh'
assert_interp_pair N17 '/bin/bash ./init.sh'
assert_interp_pair N18 '/usr/bin/env bash ./init.sh'
assert_interp_pair N19 'command bash ./init.sh'
assert_interp_pair N20 'exec bash ./init.sh'
assert_interp_pair N21 './init.sh'
assert_interp_pair N22 '"$INIT"'

# Not recognised before BL-346: the shell-path VARIABLE in every quoting and
# brace form (`# BL-346-INTERP-VAR`) and the shell name `sh`
# (`# BL-346-INTERP-NAME`).
assert_interp_pair N23 '"$BASH" ./init.sh'
assert_interp_pair N24 '"${BASH}" ./init.sh'
assert_interp_pair N25 '$BASH ./init.sh'
assert_interp_pair N26 '${BASH} "$INIT"'
assert_interp_pair N27 '"$BASH" "$INIT"'
assert_interp_pair N28 '"$SHELL" ./init.sh'
assert_interp_pair N29 '"${SHELL}" "$INIT"'
assert_interp_pair N30 'sh ./init.sh'
assert_interp_pair N31 '/bin/sh "$INIT"'

# N32: PR #478's suite shape, near verbatim — inside $( ), after `cd … &&`.
assert_lint_row "N32: PR #478 shape with --no-remote-creation is seen and hermetic" 0 "$ROW_HERMETIC" \
'#!/usr/bin/env bash
OUT="$( cd "$REPO_ROOT" && "$BASH" ./init.sh --non-interactive \
          --project bl308-posture --platform web --git-host github \
          --project-dir "$P" \
          --no-remote-creation 2>&1 )" || RC=$?'
assert_lint_row "N32: PR #478 shape with the guard deleted is flagged" 1 "$ROW_LIVE" \
'#!/usr/bin/env bash
OUT="$( cd "$REPO_ROOT" && "$BASH" ./init.sh --non-interactive \
          --project bl308-posture --platform web --git-host github \
          --project-dir "$P" 2>&1 )" || RC=$?'

# N33: the `sh` that ends a FILENAME is not the interpreter `sh`. In
# `cp ./init.sh "$T/init.sh"` the first path's `sh` is followed by a space
# and an init token; copying is not a run. Pins the `.` in
# `# BL-346-INTERP-NAME`'s left boundary.
assert_lint_row "N33: the sh of a .sh filename is not an interpreter" 0 "" \
'#!/usr/bin/env bash
INIT="$REPO_ROOT/init.sh"
cp ./init.sh "$T/init.sh"'

# N34: a syntax check through the variable stays ignored, as `bash -n` does
# in N10 — `-n` reads init.sh without running it.
assert_lint_row "N34: \"\$BASH\" -n of init.sh is not a run" 0 "" \
'#!/usr/bin/env bash
INIT="$REPO_ROOT/init.sh"
"$BASH" -n "$INIT"
"$SHELL" -n ./init.sh'

# ── BL-346 review round 1 ────────────────────────────────────────────────
# RV-1: the left boundary of `# BL-346-INTERP-NAME` is a negated class, so
# every character it admits is an atom a one-character edit can drop, and
# N15–N31 all start at column 0 — they pin only `^`, space and `/`. Excluding
# `(` from the class kept this suite at 52/0 and the live tree at rc 0 while
# it hid the six `e*=$(bash "$REPO_DIR/init.sh"` runs in
# tests/edge-cases-pre-init.sh. One pair per character a run is realistically
# written right behind: `(` and `'` (live-tree rows sit behind both), a
# backtick, a double quote and a tab.
# assert_boundary_pair ID LABEL LEFT RIGHT — the run is `bash ./init.sh …`,
# written as LEFT<run>RIGHT.
assert_boundary_pair() {
  local id="$1" label="$2" left="$3" right="$4"
  local run='bash ./init.sh --non-interactive --project x --git-host github'
  assert_lint_row "$id: $label + --no-remote-creation is seen and hermetic" 0 "$ROW_HERMETIC" \
"#!/usr/bin/env bash
${left}${run} --no-remote-creation --project-dir /tmp/p${right}"
  assert_lint_row "$id: $label with the guard deleted is flagged" 1 "$ROW_LIVE" \
"#!/usr/bin/env bash
${left}${run} --project-dir /tmp/p${right}"
}

assert_boundary_pair N35 'OUT=$(bash ./init.sh …)' 'OUT=$(' ' 2>&1)'
assert_boundary_pair N36 "sh -c 'bash ./init.sh …'" "sh -c '" "'"
assert_boundary_pair N37 'OUT=`bash ./init.sh …`' 'OUT=`' '`'
assert_boundary_pair N38 'sh -c "bash ./init.sh …"' 'sh -c "' '"'
assert_boundary_pair N39 'a TAB-indented bash ./init.sh' "$(printf '\t')" ''

# RV-3: option flags between the interpreter and init.sh. Before round 1 any
# flag hid the run (`bash -e ./init.sh` got no row) so that `bash -n` stays a
# syntax check. Now a flag cluster counts unless it carries `n` (no
# execution) — and `-D`, which implies `-n`, is not admitted at all. `-o`/`-O`
# and a cluster ending in them take the next word; `--` ends the options.
assert_interp_pair N40 'bash -e ./init.sh'
assert_interp_pair N41 'bash -eu "$INIT"'
assert_interp_pair N42 '"$BASH" -e -o pipefail ./init.sh'
assert_interp_pair N43 'bash -euo pipefail ./init.sh'
assert_interp_pair N44 'bash -O inherit_errexit "$INIT"'
assert_interp_pair N45 'bash -- ./init.sh'

# N46: `-n` anywhere in a cluster, a later `-n`, and `-D` (which implies -n)
# are syntax checks, not runs. No line carries a guard, so any one of them
# read as a run turns this case red.
assert_lint_row "N46: -n in any cluster or position, and -D, are not runs" 0 "" \
'#!/usr/bin/env bash
INIT="$REPO_ROOT/init.sh"
bash -en ./init.sh --non-interactive --project x
bash -ne "$INIT" --non-interactive --project x
bash -e -n ./init.sh --non-interactive --project x
"$BASH" -xn "$INIT" --non-interactive --project x
bash -D ./init.sh --non-interactive --project x'

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
