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

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$SKIPPED" -gt 0 ] && echo "($SKIPPED skipped — see [SKIP] lines)"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
