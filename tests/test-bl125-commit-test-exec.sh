#!/usr/bin/env bash
# tests/test-bl125-commit-test-exec.sh — BL-125 (Dogfood-2 F-DF2-009):
# the commit path must RUN the project's tests — a commit whose own tests
# are RED cannot land.
#
# THE DEFECT (walk-proven)
#   No gate executed the project's test suite: a commit landed while
#   `npm test` was 5 failed | 54 passed, and the four failing tests were
#   the adversarial fixtures PROVING the staged code was an exploitable
#   XSS. The one control that actually saw the code run was consulted by
#   no gate. BL-118 (SAST) and BL-120 (audit verdict) are the siblings —
#   WP-A2's defense-in-depth trio on the same real XSS.
#
# THE FIX (# BL-125-TEST-EXEC emitter fence -> # BL-125-COMMIT-TESTS in
# the emitted hook): a test-execution arm in the fallback pre-commit hook,
# under the SAST arm's honesty contract — not-runnable (no command
# configured/detected, or exit 127) => LOUD "NOT ENFORCED" warn, never a
# silent pass; a suite that RAN and failed => [BLOCKED], commit refused.
# Changed-file-aware fast lane: source staged => run; docs-only => skip
# with a receipt. Resolution: .claude/test-command -> stack detect
# (npm placeholder excluded) -> loud warn.
#
# HERMETIC: the hook is emitted directly from scripts/lib/hook-templates.sh
# (the SINGLE SOURCE init.sh and the sync path both consume — byte-identical
# by design), real `git commit`s inside mktemp fixtures, and a PATH mirror
# strips semgrep+gitleaks so the sibling arms take their (loud) absent
# no-ops: offline, fast, and only the BL-125 arm decides. No init.sh, not
# an aggregator -> BOTH lists. bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Registry hooks (tests/test-bl099-guard-coverage.sh; ignored by a bare run):
#   BL125_REPO_OVERRIDE=<framework-tree>  emit the hook from a MUTANT tree's lib
#   BL125_ONLY="T1 T8"                    run only the named cases
FRAMEWORK="${BL125_REPO_OVERRIDE:-$REPO_ROOT}"
HOOKLIB="$FRAMEWORK/scripts/lib/hook-templates.sh"
ONLY="${BL125_ONLY:-}"

unset GITHUB_BASE_REF 2>/dev/null || true

PASSED=0
FAILED=0
SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip_() { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

# Selected? (empty BL125_ONLY = run everything)
want() {
  [ -z "$ONLY" ] && return 0
  case " $ONLY " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# ── PATH mirror: semgrep AND gitleaks off the PATH (bl112's technique) ───────
# Every PATH entry holding either scanner is replaced by a symlink mirror
# minus the scanners; everything else resolves byte-identically. On a host
# without them this is a pure no-op. Keeps the suite offline + fast and makes
# the BL-125 arm the only decider in every case below.
NOSCAN_PATH=""
build_noscan_path() {
  [ -n "$NOSCAN_PATH" ] && return 0
  local mirrors="$TOPTMP/noscan-mirrors" n=0 d np="" entry base
  rm -rf "$mirrors"; mkdir -p "$mirrors"
  printf '%s' "$PATH" | tr ':' '\n' > "$mirrors/.pathlist"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    if [ -x "$d/semgrep" ] || [ -x "$d/gitleaks" ]; then
      n=$((n + 1))
      mkdir -p "$mirrors/$n"
      for entry in "$d"/*; do
        [ -e "$entry" ] || continue           # bash 3.2 has no nullglob
        base="${entry##*/}"
        [ "$base" = "semgrep" ] && continue
        [ "$base" = "gitleaks" ] && continue
        ln -sf "$entry" "$mirrors/$n/$base" 2>/dev/null || true
      done
      np="${np:+$np:}$mirrors/$n"
    else
      np="${np:+$np:}$d"
    fi
  done < "$mirrors/.pathlist"
  NOSCAN_PATH="$np"
}
build_noscan_path
if PATH="$NOSCAN_PATH" command -v semgrep >/dev/null 2>&1 \
   || PATH="$NOSCAN_PATH" command -v gitleaks >/dev/null 2>&1; then
  # Verifier S3: exit NON-zero — the CI unit lane installs semgrep, so this
  # mirror is load-bearing on every PR; a mirror regression greening the
  # lane with zero cases run is exactly the silent-skip class BL-125 fights.
  echo "FAIL: could not shim the scanners off the PATH — suite would be non-hermetic"
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

# ── Fixture: repo with the REAL emitted hook installed ───────────────────────
# mk_proj <dir> [templates-lib] — git repo, one seed commit, fallback
# pre-commit hook emitted by soif_write_precommit_hook from <templates-lib>
# (default: the repo's real scripts/lib/hook-templates.sh).
mk_proj() {
  local d="$1" lib="${2:-$HOOKLIB}"
  rm -rf "$d"
  mkdir -p "$d/.claude" "$d/src" "$d/docs"
  ( cd "$d" && git init -q && git config user.email t@t.invalid && git config user.name t \
      && echo x > seed && git add seed && git commit -q -m "chore: init" ) || return 1
  ( source "$lib" && soif_write_precommit_hook "$d/.git/hooks/pre-commit" ) || return 1
  chmod +x "$d/.git/hooks/pre-commit"
}

head_of()   { ( cd "$1" && git rev-parse HEAD 2>/dev/null ); }
stage_src() { ( cd "$1" && printf 'export const x = 1;\n' > src/widget.ts && git add src/widget.ts ); }

# mk_proj_typechange <dir> [templates-lib] — mk_proj, then land a SYMLINK at
# src/lib.ts BEFORE the hook is armed, then arm it. The caller replaces src/lib.ts
# with a REGULAR source file, which git reports as a status-T TYPE CHANGE — an
# ordinary de-symlinking refactor, and the shape R-274R-2 showed was invisible to
# this arm while its filter read ACMDR.
# Returns non-zero when this host cannot produce the shape (no symlink support, or
# core.symlinks=false storing the seed as a plain blob), so the cases LOUD-SKIP
# instead of degrading into an ordinary `M` that proves nothing about the T.
mk_proj_typechange() {
  local d="$1" lib="${2:-$HOOKLIB}"
  mk_proj "$d" "$lib" || return 1
  rm -f "$d/.git/hooks/pre-commit"
  ( cd "$d" && ln -s ../seed src/lib.ts ) 2>/dev/null || return 1
  [ -L "$d/src/lib.ts" ] || return 1
  ( cd "$d" && git add -- src/lib.ts \
      && PATH="$NOSCAN_PATH" git commit -q -m "chore: seed symlink" </dev/null ) || return 1
  # The seeded INDEX entry must really be mode 120000; on a checkout where git stored
  # the symlink as a regular file the later replacement is an `M`, not a `T`.
  ( cd "$d" && git ls-files -s -- ":(literal)src/lib.ts" 2>/dev/null ) | grep -q '^120000 ' || return 1
  ( source "$lib" && soif_write_precommit_hook "$d/.git/hooks/pre-commit" ) || return 1
  chmod +x "$d/.git/hooks/pre-commit"
}

# stage_typechange <dir> — replace the seeded symlink with a REGULAR .ts source file
# and stage it. Non-zero unless git really reports the staged entry as T.
stage_typechange() {
  local d="$1"
  rm -f "$d/src/lib.ts"
  printf 'export const lib = 1;\n' > "$d/src/lib.ts"
  ( cd "$d" && git add -- src/lib.ts ) || return 1
  ( cd "$d" && git diff --cached --name-status | grep -q '^T' ) || return 1
}

# try_commit <proj> <subject> <log> → echoes LANDED | REFUSED
try_commit() {
  local proj="$1" subj="$2" log="$3"
  if ( cd "$proj" && PATH="$NOSCAN_PATH" git commit -m "$subj" </dev/null ) >"$log" 2>&1; then
    echo "LANDED"
  else
    echo "REFUSED"
  fi
}

# set_testcmd <proj> <rc> — .claude/test-command -> a script exiting <rc>
set_testcmd() {
  local proj="$1" rc="$2"
  printf '#!/bin/sh\necho "fixture test suite (exit %s)"\nexit %s\n' "$rc" "$rc" > "$proj/testcmd.sh"
  chmod +x "$proj/testcmd.sh"
  printf './testcmd.sh\n' > "$proj/.claude/test-command"
}

# ── T1 (the walk's repro): RED tests + staged source -> commit REFUSED ───────
if want T1; then
echo "=== T1-red-tests-block-commit ==="
P="$TOPTMP/p1"; mk_proj "$P"
set_testcmd "$P" 1
stage_src "$P"
H0=$(head_of "$P")
V=$(try_commit "$P" "chore: add widget" "$P/commit.log")
H1=$(head_of "$P")
if [ "$V" = "REFUSED" ] && [ "$H0" = "$H1" ] && grep -qF '[BLOCKED] project tests FAILED' "$P/commit.log"; then
  pass "T1-red-tests-block-commit (git refused it, HEAD unmoved, [BLOCKED] printed)"
else
  fail_ "T1-red-tests-block-commit" "verdict=$V (expected REFUSED) — a commit whose own tests are RED landed (F-DF2-009): $(tail -3 "$P/commit.log" | tr '\n' ' ')"
fi

# ── T2: GREEN tests -> commit LANDS and the arm provably RAN ─────────────────
fi

if want T2; then
echo "=== T2-green-tests-commit-lands ==="
P="$TOPTMP/p2"; mk_proj "$P"
set_testcmd "$P" 0
stage_src "$P"
V=$(try_commit "$P" "chore: add widget" "$P/commit.log")
if [ "$V" = "LANDED" ] && grep -qF "[OK] project tests: './testcmd.sh' PASSED" "$P/commit.log"; then
  pass "T2-green-tests-commit-lands (and the [OK] receipt proves the arm RAN — not vacuous)"
else
  fail_ "T2-green-tests-commit-lands" "verdict=$V — green tests blocked, or no receipt (silent pass = the BL-112 class): $(tail -3 "$P/commit.log" | tr '\n' ' ')"
fi

# ── T3: nothing configured/detected -> LOUD not-enforced, commit LANDS ───────
fi

if want T3; then
echo "=== T3-unconfigured-warns-not-blocks ==="
P="$TOPTMP/p3"; mk_proj "$P"
stage_src "$P"
V=$(try_commit "$P" "chore: add widget" "$P/commit.log")
if [ "$V" = "LANDED" ] && grep -qF 'PROJECT TESTS NOT ENFORCED' "$P/commit.log"; then
  pass "T3-unconfigured-warns-not-blocks (lands, and the operator is TOLD nothing ran)"
else
  fail_ "T3-unconfigured-warns-not-blocks" "verdict=$V — unconfigured project blocked, or the skip was SILENT: $(tail -3 "$P/commit.log" | tr '\n' ' ')"
fi

# ── T4: runner not found (exit 127) -> LOUD not-enforced, commit LANDS ───────
fi

if want T4; then
echo "=== T4-runner-127-warns-not-blocks ==="
P="$TOPTMP/p4"; mk_proj "$P"
printf 'soif-no-such-test-runner-xyz\n' > "$P/.claude/test-command"
stage_src "$P"
V=$(try_commit "$P" "chore: add widget" "$P/commit.log")
if [ "$V" = "LANDED" ] && grep -qF 'PROJECT TESTS NOT ENFORCED' "$P/commit.log" \
   && grep -qF 'exit 127' "$P/commit.log"; then
  pass "T4-runner-127-warns-not-blocks (tool-shaped failure = the not-runnable arm, loudly)"
else
  fail_ "T4-runner-127-warns-not-blocks" "verdict=$V — a missing runner blocked, or the skip was silent: $(tail -3 "$P/commit.log" | tr '\n' ' ')"
fi

# ── T5: docs-only staged + RED tests -> fast lane skips, commit LANDS ────────
fi

if want T5; then
echo "=== T5-docs-only-fast-lane ==="
P="$TOPTMP/p5"; mk_proj "$P"
set_testcmd "$P" 1
( cd "$P" && printf '# notes\n' > docs/NOTES.md && git add docs/NOTES.md )
V=$(try_commit "$P" "docs: notes" "$P/commit.log")
if [ "$V" = "LANDED" ] && grep -qF 'no source files staged' "$P/commit.log"; then
  pass "T5-docs-only-fast-lane (docs-only commit skips the suite WITH a receipt)"
else
  fail_ "T5-docs-only-fast-lane" "verdict=$V — docs-only commit ran/blocked on tests, or skipped silently: $(tail -3 "$P/commit.log" | tr '\n' ' ')"
fi

# ── T6: npm PLACEHOLDER test script is not a real suite -> warn, LANDS ───────
fi

if want T6; then
echo "=== T6-npm-placeholder-not-detected ==="
P="$TOPTMP/p6"; mk_proj "$P"
cat > "$P/package.json" <<'EOF'
{"name":"fixture","version":"0.0.1","scripts":{"test":"echo \"Error: no test specified\" && exit 1"}}
EOF
stage_src "$P"
V=$(try_commit "$P" "chore: add widget" "$P/commit.log")
if [ "$V" = "LANDED" ] && grep -qF 'PROJECT TESTS NOT ENFORCED' "$P/commit.log"; then
  pass "T6-npm-placeholder-not-detected (a scaffold with no tests is not bricked — BL-137 class avoided)"
else
  fail_ "T6-npm-placeholder-not-detected" "verdict=$V — the npm placeholder bricked the commit, or passed silently: $(tail -3 "$P/commit.log" | tr '\n' ' ')"
fi

# ── T7: real npm test script detected with NO config -> RED blocks ───────────
fi

if want T7; then
echo "=== T7-npm-detect-red-blocks ==="
if ! command -v npm >/dev/null 2>&1; then
  skip_ "T7-npm-detect-red-blocks" "npm ABSENT on this host — the npm-detect arm is UNPROVEN here (skip, NOT a pass)"
else
  P="$TOPTMP/p7"; mk_proj "$P"
  cat > "$P/package.json" <<'EOF'
{"name":"fixture","version":"0.0.1","scripts":{"test":"exit 1"}}
EOF
  stage_src "$P"
  H0=$(head_of "$P")
  V=$(try_commit "$P" "chore: add widget" "$P/commit.log")
  H1=$(head_of "$P")
  if [ "$V" = "REFUSED" ] && [ "$H0" = "$H1" ] && grep -qF '[BLOCKED] project tests FAILED' "$P/commit.log"; then
    pass "T7-npm-detect-red-blocks (stack detection reaches the same [BLOCKED] arm)"
  else
    fail_ "T7-npm-detect-red-blocks" "verdict=$V — detected npm suite RED but the commit landed: $(tail -3 "$P/commit.log" | tr '\n' ' ')"
  fi
fi

# ── T8: fence-excision mutant -> the arm vanishes, RED tests LAND again ──────
fi

if want T8; then
echo "=== T8-fence-excision-mutant ==="
MUTLIB="$TOPTMP/hook-templates.mut.sh"
markers=$(grep -c 'BL-125-TEST-EXEC' "$HOOKLIB") || markers=0
case "$markers" in ''|*[!0-9]*) markers=0 ;; esac
sed '/# BL-125-TEST-EXEC-BEGIN/,/# BL-125-TEST-EXEC-END/d' \
  "$HOOKLIB" > "$MUTLIB"
left=$(grep -c 'BL-125-TEST-EXEC' "$MUTLIB") || left=0
case "$left" in ''|*[!0-9]*) left=0 ;; esac
if [ "$markers" -lt 2 ] || [ "$left" -ne 0 ]; then
  fail_ "T8-fence-excision-mutant" "excision vacuous (markers before=$markers after=$left) — fence absent or sed missed it"
else
  P="$TOPTMP/p8"; mk_proj "$P" "$MUTLIB"
  set_testcmd "$P" 1
  stage_src "$P"
  V=$(try_commit "$P" "chore: add widget" "$P/commit.log")
  if [ "$V" = "LANDED" ] && ! grep -qF 'BL-125' "$P/commit.log"; then
    pass "T8-fence-excision-mutant (excised emitter -> no arm in the hook, RED tests land — the fence is load-bearing)"
  else
    fail_ "T8-fence-excision-mutant" "verdict=$V — mutant hook still carries/blocks on the arm: $(tail -3 "$P/commit.log" | tr '\n' ' ')"
  fi
fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# Verifier-battery cases (adversarial verification 2026-07-18): M1 (fast-lane
# under-count with a FALSE receipt), M2 (no-op command certified as PASSED),
# S1/S4 (scripts-scoped npm detection), S2 (unreadable config must not crash),
# S6 (comment/CRLF handling).
# ═════════════════════════════════════════════════════════════════════════════

if want T9; then
echo "=== T9-deletion-and-rename-run-tests ==="
P="$TOPTMP/p9"; mk_proj "$P"
( cd "$P" && printf 'export const s = 1;\n' > src/sanitizer.ts && git add src/sanitizer.ts && PATH="$NOSCAN_PATH" git commit -q -m "chore: seed sanitizer" </dev/null )
set_testcmd "$P" 1
( cd "$P" && git rm -q src/sanitizer.ts )
H0=$(head_of "$P")
V=$(try_commit "$P" "chore: drop sanitizer" "$P/commit.log")
H1=$(head_of "$P")
if [ "$V" = "REFUSED" ] && [ "$H0" = "$H1" ] && grep -qF '[BLOCKED] project tests FAILED' "$P/commit.log"; then
  pass "T9a-deletion-runs-tests (deleting the sanitizer is exactly the regression the arm exists to stop)"
else
  fail_ "T9a-deletion-runs-tests" "verdict=$V — a source DELETION skipped the RED suite (verifier M1): $(tail -3 "$P/commit.log" | tr '\n' ' ')"
fi
P="$TOPTMP/p9b"; mk_proj "$P"
( cd "$P" && printf 'export const s = 1;\n' > src/sanitizer.ts && git add src/sanitizer.ts && PATH="$NOSCAN_PATH" git commit -q -m "chore: seed sanitizer" </dev/null )
set_testcmd "$P" 1
( cd "$P" && git mv src/sanitizer.ts src/zap.ts )
V=$(try_commit "$P" "chore: rename sanitizer" "$P/commit.log")
if [ "$V" = "REFUSED" ] && grep -qF '[BLOCKED] project tests FAILED' "$P/commit.log"; then
  pass "T9b-rename-runs-tests"
else
  fail_ "T9b-rename-runs-tests" "verdict=$V — a staged RENAME (R100) skipped the RED suite (verifier M1): $(tail -3 "$P/commit.log" | tr '\n' ' ')"
fi
fi

if want T10; then
echo "=== T10-mts-extension-counts ==="
P="$TOPTMP/p10"; mk_proj "$P"
set_testcmd "$P" 1
( cd "$P" && printf 'export const x = 1;\n' > src/widget.mts && git add src/widget.mts )
V=$(try_commit "$P" "chore: add widget" "$P/commit.log")
if [ "$V" = "REFUSED" ] && grep -qF '[BLOCKED] project tests FAILED' "$P/commit.log"; then
  pass "T10-mts-extension-counts (.mts is first-class typescript — the SAST and test arms agree on what was staged)"
else
  fail_ "T10-mts-extension-counts" "verdict=$V — a staged .mts source file skipped the RED suite (verifier M1): $(tail -3 "$P/commit.log" | tr '\n' ' ')"
fi
fi

if want T11; then
echo "=== T11-comment-and-blank-config-lines ==="
P="$TOPTMP/p11"; mk_proj "$P"
printf '#!/bin/sh\nexit 1\n' > "$P/testcmd.sh"; chmod +x "$P/testcmd.sh"
printf '# our test lane\n\n./testcmd.sh\n' > "$P/.claude/test-command"
stage_src "$P"
V=$(try_commit "$P" "chore: add widget" "$P/commit.log")
if [ "$V" = "REFUSED" ] && grep -qF '[BLOCKED] project tests FAILED' "$P/commit.log"; then
  pass "T11a-comment-header-skipped-to-real-command (a comment line is config authoring, not the command)"
else
  fail_ "T11a-comment-header-skipped-to-real-command" "verdict=$V — a leading comment line became the 'suite' and no-op passed (verifier M2): $(tail -3 "$P/commit.log" | tr '\n' ' ')"
fi
P="$TOPTMP/p11b"; mk_proj "$P"
printf '   \n' > "$P/.claude/test-command"
stage_src "$P"
V=$(try_commit "$P" "chore: add widget" "$P/commit.log")
if [ "$V" = "LANDED" ] && grep -qF 'PROJECT TESTS NOT ENFORCED' "$P/commit.log" \
   && ! grep -qF 'PASSED' "$P/commit.log"; then
  pass "T11b-whitespace-config-is-loud-not-PASSED (a no-op is never certified as a green run)"
else
  fail_ "T11b-whitespace-config-is-loud-not-PASSED" "verdict=$V — a whitespace-only config printed a false PASSED receipt or blocked (verifier M2): $(tail -3 "$P/commit.log" | tr '\n' ' ')"
fi
fi

if want T12; then
echo "=== T12-dependency-named-test-no-brick ==="
P="$TOPTMP/p12"; mk_proj "$P"
cat > "$P/package.json" <<'EOF'
{"name":"fixture","version":"0.0.1","dependencies":{"test":"^3.3.0"}}
EOF
stage_src "$P"
V=$(try_commit "$P" "chore: add widget" "$P/commit.log")
if [ "$V" = "LANDED" ] && grep -qF 'PROJECT TESTS NOT ENFORCED' "$P/commit.log"; then
  pass "T12-dependency-named-test-no-brick (only a scripts-block test key is a suite — BL-137 class avoided)"
else
  fail_ "T12-dependency-named-test-no-brick" "verdict=$V — a dependency literally named 'test' triggered npm detection and bricked/skipped silently (verifier S1): $(tail -3 "$P/commit.log" | tr '\n' ' ')"
fi
fi

if want T13; then
echo "=== T13-unreadable-config-warns-not-crashes ==="
if [ "$(id -u)" -eq 0 ]; then
  skip_ "T13-unreadable-config-warns-not-crashes" "running as root — mode bits do not restrict root, the unreadable shape cannot be built here"
else
P="$TOPTMP/p13"; mk_proj "$P"
printf './testcmd.sh\n' > "$P/.claude/test-command"
chmod 000 "$P/.claude/test-command"
stage_src "$P"
V=$(try_commit "$P" "chore: add widget" "$P/commit.log")
chmod 644 "$P/.claude/test-command"
if [ "$V" = "LANDED" ] && grep -qF 'PROJECT TESTS NOT ENFORCED' "$P/commit.log"; then
  pass "T13-unreadable-config-warns-not-crashes (a permissions accident is a loud skip, not an undiagnosed crash)"
else
  fail_ "T13-unreadable-config-warns-not-crashes" "verdict=$V — an unreadable .claude/test-command crashed the hook or passed silently (verifier S2): $(tail -3 "$P/commit.log" | tr '\n' ' ')"
fi
fi
fi

if want T14; then
echo "=== T14-crlf-config-line-runs ==="
P="$TOPTMP/p14"; mk_proj "$P"
printf '#!/bin/sh\nexit 0\n' > "$P/testcmd.sh"; chmod +x "$P/testcmd.sh"
printf './testcmd.sh\r\n' > "$P/.claude/test-command"
stage_src "$P"
V=$(try_commit "$P" "chore: add widget" "$P/commit.log")
if [ "$V" = "LANDED" ] && grep -qF "PASSED" "$P/commit.log"; then
  pass "T14-crlf-config-line-runs (a Windows-edited config still resolves to the real command)"
else
  fail_ "T14-crlf-config-line-runs" "verdict=$V — a CRLF line ending turned the command into exit-127 noise (verifier S6): $(tail -3 "$P/commit.log" | tr '\n' ' ')"
fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# R-274R-2 — the FOURTH --diff-filter, and the one PR #274 left behind
# ═════════════════════════════════════════════════════════════════════════════
# Commit 405d691 added T to the SAST arm's filter (# BL-179-STAGED-FILTER, ACM ->
# ACMRT) and did not touch this arm's sibling read, which stayed ACMDR. A staged
# TYPE CHANGE of a real source file — symlink replaced by a regular file, index
# mode 100644, an ordinary de-symlinking refactor — was therefore invisible here:
# the suite never ran and the arm printed
#   [OK] BL-125: no source files staged — project tests not required for this commit.
# which is verbatim the failure the "Verifier M1" comment says the filter exists to
# stop. Filter -> ACMDRT at # BL-179-TESTARM-FILTER.
#   These two cases are the FIRST type-change coverage this suite has ever had
#   (`grep -n "typechange\|120000"` returned nothing before them), which is exactly
#   why the hole survived a suite that was 16/16 green.

if want T15; then
echo "=== T15-typechange-runs-tests ==="
P="$TOPTMP/p15"
if ! mk_proj_typechange "$P"; then
  skip_ "T15-typechange-runs-tests" "this host could not seed a mode-120000 symlink (no symlink support / core.symlinks=false) — the T shape is UNPROVEN here (skip, NOT a pass)"
else
  set_testcmd "$P" 1
  if ! stage_typechange "$P"; then
    skip_ "T15-typechange-runs-tests" "git did not report the staged entry as a TYPE CHANGE on this host — UNPROVEN here"
  else
    H0=$(head_of "$P")
    V=$(try_commit "$P" "refactor: materialize the symlink" "$P/commit.log")
    H1=$(head_of "$P")
    if [ "$V" = "REFUSED" ] && [ "$H0" = "$H1" ] && grep -qF '[BLOCKED] project tests FAILED' "$P/commit.log"; then
      pass "T15-typechange-runs-tests (a staged TYPE CHANGE of source RUNS the suite — an always-failing suite refuses the commit)"
    elif grep -qF 'no source files staged' "$P/commit.log"; then
      fail_ "T15-typechange-runs-tests" "the arm printed the FALSE receipt 'no source files staged' over a staged source TYPE CHANGE — --diff-filter is missing T, so the RED suite never ran and the commit LANDED (R-274R-2); verdict=$V"
    else
      fail_ "T15-typechange-runs-tests" "verdict=$V — a staged source type change did not reach the RED suite: $(tail -3 "$P/commit.log" | tr '\n' ' ')"
    fi
  fi
fi
fi

if want T16; then
echo "=== T16-mutation-typechange-filter ==="
# Revert exactly the T, ACMDRT -> ACMDR (the value PR #274 left here), at the LIB
# level — this arm's filter lives in the emitter, and mk_proj emits the hook from
# whichever lib it is handed, so a lib mutant is the honest analogue of the emitted-
# hook mutants the SAST suite uses.
#   THE RED ASSERTION IS THE FALSE RECEIPT, NOT MERELY THE LANDING. "It committed"
#   would also be satisfied by a loud not-enforced WARN, which is honest; the defect
#   being pinned is the arm CLAIMING no source was staged while source was staged.
MUTLIB16="$TOPTMP/hook-templates.acmdr.sh"
n16=$(grep -c -- '--diff-filter=ACMDRT \\' "$HOOKLIB") || n16=0
n16=$(printf '%s' "$n16" | tr -d '[:space:]')
case "$n16" in ''|*[!0-9]*) n16=0 ;; esac
sed 's/--diff-filter=ACMDRT \\/--diff-filter=ACMDR \\/' "$HOOKLIB" > "$MUTLIB16"
if [ "$n16" -ne 1 ]; then
  fail_ "T16-mutation-typechange-filter" "MIS-TARGETED — the BL-125 staged-source filter '--diff-filter=ACMDRT' is not present exactly once in $HOOKLIB (found $n16); retarget this mutation in lockstep"
elif ! ( source "$MUTLIB16" && soif_write_precommit_hook "$TOPTMP/mut16-hook" ) >/dev/null 2>&1; then
  fail_ "T16-mutation-typechange-filter" "the mutant lib could not emit a hook — a broken mutant proves nothing"
elif ! bash -n "$TOPTMP/mut16-hook" 2>/dev/null; then
  fail_ "T16-mutation-typechange-filter" "mutated hook has a syntax error — a broken mutant proves nothing"
else
  PR16="$TOPTMP/p16-red"; PG16="$TOPTMP/p16-green"
  RED16=SETUPFAIL; GRN16=SETUPFAIL
  if mk_proj_typechange "$PR16" "$MUTLIB16"; then
    set_testcmd "$PR16" 1
    stage_typechange "$PR16" && RED16=$(try_commit "$PR16" "refactor: materialize the symlink" "$PR16/commit.log")
  fi
  if mk_proj_typechange "$PG16"; then
    set_testcmd "$PG16" 1
    stage_typechange "$PG16" && GRN16=$(try_commit "$PG16" "refactor: materialize the symlink" "$PG16/commit.log")
  fi
  if [ "$RED16" = "SETUPFAIL" ] || [ "$GRN16" = "SETUPFAIL" ]; then
    skip_ "T16-mutation-typechange-filter" "this host could not produce a status-T staged entry — mutation UNPROVEN here"
  elif [ "$RED16" = "LANDED" ] && grep -qF 'no source files staged' "$PR16/commit.log" \
       && [ "$GRN16" = "REFUSED" ] && grep -qF '[BLOCKED] project tests FAILED' "$PG16/commit.log"; then
    pass "T16-mutation-typechange-filter: ACMDR hides the staged TYPE CHANGE and prints the FALSE 'no source files staged' receipt while the RED suite never runs (RED); ACMDRT runs it and REFUSES the commit (GREEN) — the T is load-bearing (R-274R-2)"
  else
    fail_ "T16-mutation-typechange-filter" "expected RED=LANDED+false-receipt / GREEN=REFUSED+[BLOCKED]; got RED=$RED16 (false_receipt=$(grep -cF 'no source files staged' "$PR16/commit.log")) GREEN=$GRN16 (blocked=$(grep -cF '[BLOCKED] project tests FAILED' "$PG16/commit.log")); red: $(tail -3 "$PR16/commit.log" | tr '\n' ' ')"
  fi
fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# BL-183 — the npm-detection predicates must survive a monorepo-sized scripts
# block. The old spelling (sed -n '/"scripts"…/,/}/p' package.json | grep -q …)
# inverts under the emitted hook's `set -euo pipefail`: grep -q exits on first
# match, sed dies of SIGPIPE writing the REST OF THE BLOCK (the range closes at
# the first `}`, so a big package.json with a small scripts block never fires —
# the trigger is the block, not the file), and pipefail promotes rc 141 into
# "no match". Measured deterministic on this fixture class: PIPESTATUS=141 0 —
# grep MATCHED and the pipeline still reported false. The detection site then
# reads a real suite as absent (the test gate silently stops running); the
# NEGATED placeholder site reads the other way (placeholder "absent" -> npm
# test adopted against a block the small-file semantics say is placeholder-
# bearing). Fix: single-process awk (soif_npm_scripts_has) — no pipe to break.
# ═════════════════════════════════════════════════════════════════════════════

# mk_bigpkg <dir> <shape> — package.json whose scripts block carries ~330 KB
# around the line the predicate matches on (>> the 64 KB pipe buffer and the
# ~110 KB determinism band measured in BL-183). One entry per line, and no `}`
# in any value — a `}` would close the sed range early and hide the defect.
#   test-first        "test": real failing suite FIRST, ~330 KB after it
#   placeholder-early 'no test specified' inside ANOTHER script's value first,
#                     real "test" key LAST (so old-spelling detection survives
#                     while the old placeholder check SIGPIPEs — the site-3
#                     inversion isolated)
#   test-last         no placeholder, "test" key LAST after ~330 KB (whole-
#                     block completeness: a truncating rewrite must not miss it)
mk_bigpkg() {
  local d="$1" shape="$2"
  awk -v shape="$shape" 'BEGIN{
    print "{"
    print "  \"name\": \"fixture\","
    print "  \"version\": \"0.0.1\","
    print "  \"scripts\": {"
    if (shape == "test-first")        print "    \"test\": \"exit 1\","
    if (shape == "placeholder-early") print "    \"lint\": \"echo no test specified here on purpose\","
    for (i = 0; i < 7000; i++) printf "    \"s%05d\": \"echo filler line number %05d\",\n", i, i
    if (shape == "test-first")        print "    \"zlast\": \"echo done\""
    else                              print "    \"test\": \"exit 1\""
    print "  }"
    print "}"
  }' > "$d/package.json"
}

# bigpkg_tail <dir> <needle> — bytes the sed producer still had to write after
# the first scripts-block line containing <needle>: the SIGPIPE exposure. Each
# case asserts this is large enough to force the race BEFORE asserting any
# behavior, so a future fixture edit cannot quietly turn the case vacuous.
bigpkg_tail() {
  awk -v needle="$2" '
    !f && index($0, needle) { f = 1; next }
    f && index($0, "}")     { exit }
    f                       { n += length($0) + 1 }
    END { print n + 0 }' "$1/package.json"
}

# bigpkg_lead <dir> <needle> — bytes between the scripts-block open and the
# first line containing <needle> (the exposure BEFORE a late match — what a
# truncating rewrite would fail to read).
bigpkg_lead() {
  awk -v needle="$2" '
    !s && index($0, "\"scripts\"") { s = 1; next }
    s && index($0, needle)          { print n + 0; exit }
    s                               { n += length($0) + 1 }' "$1/package.json"
}

if want T17; then
echo "=== T17-npm-detect-survives-big-scripts-block ==="
if ! command -v npm >/dev/null 2>&1; then
  skip_ "T17-npm-detect-survives-big-scripts-block" "npm ABSENT on this host — the npm-detect arm is UNPROVEN here (skip, NOT a pass)"
else
  P="$TOPTMP/p17"; mk_proj "$P"
  mk_bigpkg "$P" test-first
  TAIL17=$(bigpkg_tail "$P" '"test"')
  case "$TAIL17" in ''|*[!0-9]*) TAIL17=0 ;; esac
  if [ "$TAIL17" -lt 150000 ]; then
    fail_ "T17-npm-detect-survives-big-scripts-block" "fixture too small to force the race (post-match block bytes=$TAIL17 < 150000) — the case is VACUOUS, fix mk_bigpkg"
  else
    stage_src "$P"
    H0=$(head_of "$P")
    V=$(try_commit "$P" "chore: add widget" "$P/commit.log")
    H1=$(head_of "$P")
    if [ "$V" = "REFUSED" ] && [ "$H0" = "$H1" ] \
       && grep -qF '[BLOCKED] project tests FAILED' "$P/commit.log" \
       && ! grep -qF 'PROJECT TESTS NOT ENFORCED' "$P/commit.log"; then
      pass "T17-npm-detect-survives-big-scripts-block (a real suite behind ~330 KB of sibling scripts is still detected — RED suite refuses the commit)"
    else
      fail_ "T17-npm-detect-survives-big-scripts-block" "verdict=$V — a real npm suite behind a big scripts block was not enforced (BL-183 SIGPIPE inversion: the test gate silently stopped running): $(tail -3 "$P/commit.log" | tr '\n' ' ')"
    fi
  fi
fi
fi

if want T18; then
echo "=== T18-placeholder-scope-survives-big-scripts-block ==="
# Pins the PRESERVED small-file semantics at scale, not an endorsement of the
# scope: 'no test specified' ANYWHERE in the scripts block reads as npm's
# placeholder and detection declines (T6's semantics — see the S1/S4 comment
# in the emitter). Old spelling on this fixture: detection survives (match is
# LATE, nothing left to write) while the negated placeholder check SIGPIPEs —
# `! rc141` reads TRUE, npm test is adopted, and the commit BLOCKS where the
# small-file predicate would have warned. npm is required so that pre-fix
# failure mode is the loud [BLOCKED], not a vacuously-landing exit 127.
if ! command -v npm >/dev/null 2>&1; then
  skip_ "T18-placeholder-scope-survives-big-scripts-block" "npm ABSENT on this host — the pre-fix failure mode is unreproducible here (skip, NOT a pass)"
else
  P="$TOPTMP/p18"; mk_proj "$P"
  mk_bigpkg "$P" placeholder-early
  TAIL18=$(bigpkg_tail "$P" 'no test specified')
  case "$TAIL18" in ''|*[!0-9]*) TAIL18=0 ;; esac
  if [ "$TAIL18" -lt 150000 ]; then
    fail_ "T18-placeholder-scope-survives-big-scripts-block" "fixture too small to force the race (post-placeholder block bytes=$TAIL18 < 150000) — the case is VACUOUS, fix mk_bigpkg"
  else
    stage_src "$P"
    V=$(try_commit "$P" "chore: add widget" "$P/commit.log")
    if [ "$V" = "LANDED" ] && grep -qF 'PROJECT TESTS NOT ENFORCED' "$P/commit.log" \
       && ! grep -qF '[BLOCKED] project tests FAILED' "$P/commit.log"; then
      pass "T18-placeholder-scope-survives-big-scripts-block (the placeholder read is size-independent — same verdict as T6 at ~330 KB)"
    else
      fail_ "T18-placeholder-scope-survives-big-scripts-block" "verdict=$V — the negated placeholder check inverted at scale (BL-183: '! rc141' read the placeholder as absent and adopted npm test): $(tail -3 "$P/commit.log" | tr '\n' ' ')"
    fi
  fi
fi
fi

if want T19; then
echo "=== T19-npm-detect-test-key-late ==="
# Both spellings pass this today (a LATE match leaves the producer nothing to
# write, so the old pipe survives too). It stands as the other direction of
# T17's coin: the fix must read the WHOLE block, so a rewrite that truncates
# (reads only the first N KB and misses a late "test" key) goes RED here
# instead of shipping. The vacuity guard is bigpkg_lead, not bigpkg_tail.
if ! command -v npm >/dev/null 2>&1; then
  skip_ "T19-npm-detect-test-key-late" "npm ABSENT on this host — the npm-detect arm is UNPROVEN here (skip, NOT a pass)"
else
  P="$TOPTMP/p19"; mk_proj "$P"
  mk_bigpkg "$P" test-last
  LEAD19=$(bigpkg_lead "$P" '"test"')
  case "$LEAD19" in ''|*[!0-9]*) LEAD19=0 ;; esac
  if [ "$LEAD19" -lt 150000 ]; then
    fail_ "T19-npm-detect-test-key-late" "fixture too small (pre-match block bytes=$LEAD19 < 150000) — the case is VACUOUS, fix mk_bigpkg"
  else
    stage_src "$P"
    V=$(try_commit "$P" "chore: add widget" "$P/commit.log")
    if [ "$V" = "REFUSED" ] && grep -qF '[BLOCKED] project tests FAILED' "$P/commit.log"; then
      pass "T19-npm-detect-test-key-late (a \"test\" key ~330 KB into the block is still read — the predicate consumes the whole block)"
    else
      fail_ "T19-npm-detect-test-key-late" "verdict=$V — a late \"test\" key was missed (truncating predicate?): $(tail -3 "$P/commit.log" | tr '\n' ' ')"
    fi
  fi
fi
fi

if want T20; then
echo "=== T20-mutation-npm-detect-pipe-respell ==="
# Re-spell each soif_npm_scripts_has call back to the exact pipeline BL-183
# replaced (the one-character-narrowing lesson of BL-181: a standing mutant,
# not a one-time proof). RED: the mutant lib re-acquires the inversion on the
# big-block fixtures. GREEN: the real lib does not. Both directions run HERE
# so `BL125_ONLY="T20"` is an honest standalone verdict, per T16's precedent.
if ! command -v npm >/dev/null 2>&1; then
  skip_ "T20-mutation-npm-detect-pipe-respell" "npm ABSENT on this host — the GREEN directions are unprovable here (skip, NOT a pass)"
else
  Q="'"
  # ── Mutant A: detection call -> old sed|grep -qE pipeline ──────────────────
  MUTA="$TOPTMP/hook-templates.pipeA.sh"
  nA=$(grep -cF "&& soif_npm_scripts_has ${Q}\"test\"" "$HOOKLIB") || nA=0
  case "$nA" in ''|*[!0-9]*) nA=0 ;; esac
  awk -v q="$Q" '
    index($0, "&& soif_npm_scripts_has " q "\"test\"") {
      print "       && sed -n " q "/\"scripts\"[[:space:]]*:/,/}/p" q " package.json | grep -qE " q "\"test\"[[:space:]]*:" q " \\"
      next
    }
    { print }' "$HOOKLIB" > "$MUTA"
  # ── Mutant B: placeholder call -> old negated sed|grep -q pipeline ─────────
  MUTB="$TOPTMP/hook-templates.pipeB.sh"
  nB=$(grep -cF "&& ! soif_npm_scripts_has ${Q}no test specified" "$HOOKLIB") || nB=0
  case "$nB" in ''|*[!0-9]*) nB=0 ;; esac
  awk -v q="$Q" '
    index($0, "&& ! soif_npm_scripts_has " q "no test specified") {
      print "       && ! sed -n " q "/\"scripts\"[[:space:]]*:/,/}/p" q " package.json | grep -q " q "no test specified" q "; then"
      next
    }
    { print }' "$HOOKLIB" > "$MUTB"
  if [ "$nA" -ne 1 ] || [ "$nB" -ne 1 ]; then
    fail_ "T20-mutation-npm-detect-pipe-respell" "MIS-TARGETED — expected each soif_npm_scripts_has call exactly once in $HOOKLIB (detection=$nA placeholder=$nB); retarget this mutation in lockstep"
  elif ! grep -qF "| grep -qE" "$MUTA" || grep -qF "&& soif_npm_scripts_has ${Q}\"test\"" "$MUTA" \
       || ! grep -qF "| grep -q ${Q}no test specified" "$MUTB" || grep -qF "&& ! soif_npm_scripts_has" "$MUTB"; then
    fail_ "T20-mutation-npm-detect-pipe-respell" "mutant construction vacuous — the old spelling did not land or the new call survived (A/B)"
  elif ! ( source "$MUTA" && soif_write_precommit_hook "$TOPTMP/mut20a-hook" ) >/dev/null 2>&1 \
       || ! bash -n "$TOPTMP/mut20a-hook" 2>/dev/null \
       || ! ( source "$MUTB" && soif_write_precommit_hook "$TOPTMP/mut20b-hook" ) >/dev/null 2>&1 \
       || ! bash -n "$TOPTMP/mut20b-hook" 2>/dev/null; then
    fail_ "T20-mutation-npm-detect-pipe-respell" "a mutant lib could not emit a syntactically valid hook — a broken mutant proves nothing"
  else
    RA=SETUPFAIL; GA=SETUPFAIL; RB=SETUPFAIL; GB=SETUPFAIL
    PRA="$TOPTMP/p20-redA"; if mk_proj "$PRA" "$MUTA"; then mk_bigpkg "$PRA" test-first; stage_src "$PRA"; RA=$(try_commit "$PRA" "chore: add widget" "$PRA/commit.log"); fi
    PGA="$TOPTMP/p20-greenA"; if mk_proj "$PGA"; then mk_bigpkg "$PGA" test-first; stage_src "$PGA"; GA=$(try_commit "$PGA" "chore: add widget" "$PGA/commit.log"); fi
    PRB="$TOPTMP/p20-redB"; if mk_proj "$PRB" "$MUTB"; then mk_bigpkg "$PRB" placeholder-early; stage_src "$PRB"; RB=$(try_commit "$PRB" "chore: add widget" "$PRB/commit.log"); fi
    PGB="$TOPTMP/p20-greenB"; if mk_proj "$PGB"; then mk_bigpkg "$PGB" placeholder-early; stage_src "$PGB"; GB=$(try_commit "$PGB" "chore: add widget" "$PGB/commit.log"); fi
    if [ "$RA" = "LANDED" ] && grep -qF 'PROJECT TESTS NOT ENFORCED' "$PRA/commit.log" \
       && [ "$GA" = "REFUSED" ] && grep -qF '[BLOCKED] project tests FAILED' "$PGA/commit.log" \
       && [ "$RB" = "REFUSED" ] && grep -qF '[BLOCKED] project tests FAILED' "$PRB/commit.log" \
       && [ "$GB" = "LANDED" ] && grep -qF 'PROJECT TESTS NOT ENFORCED' "$PGB/commit.log"; then
      pass "T20-mutation-npm-detect-pipe-respell: each re-piped predicate re-acquires its inversion (detection: real suite unenforced; placeholder: scaffold-shape bricked) and the awk spelling does not — both replacements are load-bearing (BL-183)"
    else
      fail_ "T20-mutation-npm-detect-pipe-respell" "expected redA=LANDED+warn/greenA=REFUSED+blocked/redB=REFUSED+blocked/greenB=LANDED+warn; got redA=$RA greenA=$GA redB=$RB greenB=$GB; redA: $(tail -2 "$PRA/commit.log" | tr '\n' ' ') redB: $(tail -2 "$PRB/commit.log" | tr '\n' ' ')"
    fi
  fi
fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$SKIPPED" -gt 0 ] && echo "($SKIPPED skipped — see [SKIP] lines)"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
