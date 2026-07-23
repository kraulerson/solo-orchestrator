#!/usr/bin/env bash
# tests/test-bl163-blocked-ledger.sh — BL-163 (Dogfood-4 F-DF4-009):
# a commit REFUSED by a blocking arm of the emitted pre-commit hook must leave a
# terminal_commit_blocked row in .claude/bypass-audit.json.
#
# THE DEFECT (walk-proven)
#   The emitted fallback hook's blocking arms (gitleaks secrets, semgrep SAST,
#   BL-125 project-tests) each set FAILED=1 and the hook exits non-zero at its
#   terminal `exit "$FAILED"` — BEFORE .git/hooks/framework-gate.sh runs, and
#   framework-gate is the ONLY writer of terminal_commit_blocked rows. Net: in
#   Dogfood-4 S2 two real dishonest commit attempts (an innerHTML XSS sink and a
#   red-tests commit) were correctly REFUSED yet appended NOTHING to the ledger —
#   the enforcement record understated the attempted violations.
#
# THE FIX (# BL-163-LEDGER-EMIT emitter fence -> # BL-163-BLOCKED-LEDGER in the
# emitted bytes): a soif_ledger_blocked() helper in the emitted hook appends a
# terminal_commit_blocked row (details.gate names the arm: gitleaks / semgrep /
# bl125_tests) via scripts/lib/bypass-audit.sh, right where each arm sets
# FAILED=1. The append is BEST-EFFORT: a missing/unreadable lib, an absent jq, or
# a failed write prints a one-line [note] and returns 0 — the block is NEVER
# weakened. The row schema mirrors framework-gate's own row
# (install-filesystem-gates.sh record_audit_row).
#
# HERMETIC: the hook is emitted directly from scripts/lib/hook-templates.sh (the
# SINGLE SOURCE init.sh and the sync path both consume), real `git commit`s inside
# mktemp fixtures, a PATH mirror strips the real semgrep+gitleaks so only the
# fake scanners this suite installs decide, and a project-local copy of
# bypass-audit.sh is the append library the emitted hook resolves. No init.sh, not
# an aggregator -> registered in BOTH lists. bash-3.2 safe.
#
# HOOKS FOR tests/test-bl099-guard-coverage.sh (ignored by a bare run):
#   BL163_REPO_OVERRIDE=<framework-tree>  emit the hook from a MUTANT tree's lib
#   BL163_ONLY="T1 T5"                    run only the named cases

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FRAMEWORK="${BL163_REPO_OVERRIDE:-$REPO_ROOT}"
HOOKLIB="$FRAMEWORK/scripts/lib/hook-templates.sh"
AUDITLIB="$FRAMEWORK/scripts/lib/bypass-audit.sh"
ONLY="${BL163_ONLY:-}"

unset GITHUB_BASE_REF 2>/dev/null || true

PASSED=0
FAILED=0
SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip_() { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

want() {
  [ -z "$ONLY" ] && return 0
  case " $ONLY " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

if ! command -v jq >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  echo "SKIP: jq/git required"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# ── PATH mirror: the REAL semgrep AND gitleaks off the PATH (bl125's technique) ─
# Every PATH entry holding either scanner is replaced by a symlink mirror minus
# the scanners; everything else resolves byte-identically. This suite installs
# its OWN fake scanners per case, so only they decide.
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
  echo "FAIL: could not shim the real scanners off the PATH — suite would be non-hermetic"
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

# fake_scanner <name> <rc> — a dir holding a `<name>` that ignores its args and
# exits <rc>. Prepended to NOSCAN_PATH it becomes the ONLY resolvable scanner of
# that name, so the arm's decision is fully deterministic and offline.
fake_scanner() {
  local name="$1" rc="$2"
  local dir="$TOPTMP/fake-$name-$rc"
  mkdir -p "$dir"
  printf '#!/bin/sh\nexit %s\n' "$rc" > "$dir/$name"
  chmod +x "$dir/$name"
  echo "$dir"
}

# mk_proj <dir> [templates-lib] [with_auditlib=1] — git repo, one seed commit,
# manifest.json (enforcement_level=strict), the emitted fallback pre-commit hook,
# and (by default) a project-local scripts/lib/bypass-audit.sh — the append
# library the emitted hook resolves via `git rev-parse --show-toplevel`.
mk_proj() {
  local d="$1" lib="${2:-$HOOKLIB}" with_lib="${3:-1}"
  rm -rf "$d"
  mkdir -p "$d/.claude" "$d/src"
  printf '{"frameworkVersion":"test","enforcement_level":"strict"}\n' > "$d/.claude/manifest.json"
  if [ "$with_lib" = "1" ]; then
    mkdir -p "$d/scripts/lib"
    cp "$AUDITLIB" "$d/scripts/lib/bypass-audit.sh"
  fi
  ( cd "$d" && git init -q && git config user.email t@t.invalid && git config user.name t \
      && echo x > seed && git add seed && git commit -q -m "chore: init" ) || return 1
  ( source "$lib" && soif_write_precommit_hook "$d/.git/hooks/pre-commit" ) || return 1
  chmod +x "$d/.git/hooks/pre-commit"
}

head_of()   { ( cd "$1" && git rev-parse HEAD 2>/dev/null ); }
stage_src() { ( cd "$1" && printf 'export const x = 1;\n' > src/widget.ts && git add src/widget.ts ); }

# set_testcmd <proj> <rc> — .claude/test-command -> a script exiting <rc>
set_testcmd() {
  local proj="$1" rc="$2"
  printf '#!/bin/sh\necho "fixture test suite (exit %s)"\nexit %s\n' "$rc" "$rc" > "$proj/testcmd.sh"
  chmod +x "$proj/testcmd.sh"
  printf './testcmd.sh\n' > "$proj/.claude/test-command"
}

# try_commit <proj> <subject> <log> <PATH> → echoes LANDED | REFUSED
try_commit() {
  local proj="$1" subj="$2" log="$3" p="$4"
  if ( cd "$proj" && PATH="$p" git commit -m "$subj" </dev/null ) >"$log" 2>&1; then
    echo "LANDED"
  else
    echo "REFUSED"
  fi
}

# ledger counts (absent file == 0)
blocked_rows() { # <proj>
  local f="$1/.claude/bypass-audit.json"
  [ -f "$f" ] || { echo 0; return 0; }
  jq '[.[] | select(.type=="terminal_commit_blocked")] | length' "$f" 2>/dev/null || echo 0
}
# rows_for_gate <proj> <gate> — count of terminal_commit_blocked rows whose
# details.gate matches AND whose actor is user_terminal (schema pin).
rows_for_gate() {
  local f="$1/.claude/bypass-audit.json" g="$2"
  [ -f "$f" ] || { echo 0; return 0; }
  jq --arg g "$g" '[.[] | select(.type=="terminal_commit_blocked" and .actor=="user_terminal" and .details.gate==$g)] | length' "$f" 2>/dev/null || echo 0
}
emitted_marker_count() { # <hook-file>
  grep -c '# BL-163-BLOCKED-LEDGER' "$1" 2>/dev/null || echo 0
}

# ── T1 (case a): semgrep-block appends details.gate=semgrep, commit REFUSED ─────
if want T1; then
echo "=== T1-semgrep-block-appends-row ==="
P="$TOPTMP/p1"; mk_proj "$P"
FAKE=$(fake_scanner semgrep 1)      # semgrep "found blocking findings"
stage_src "$P"
H0=$(head_of "$P")
V=$(try_commit "$P" "chore: add widget" "$P/commit.log" "$FAKE:$NOSCAN_PATH")
H1=$(head_of "$P")
N=$(blocked_rows "$P"); NG=$(rows_for_gate "$P" semgrep)
if [ "$V" = "REFUSED" ] && [ "$H0" = "$H1" ] && grep -qF '[BLOCKED] Semgrep' "$P/commit.log" \
   && [ "$N" -eq 1 ] && [ "$NG" -eq 1 ]; then
  pass "T1-semgrep-block-appends-row (REFUSED, HEAD unmoved, 1 terminal_commit_blocked row gate=semgrep)"
else
  fail_ "T1-semgrep-block-appends-row" "verdict=$V blocked_rows=$N gate_semgrep=$NG (want REFUSED/1/1) — the SAST block is invisible to the ledger (F-DF4-009): $(tail -3 "$P/commit.log" | tr '\n' ' ')"
fi
fi

# ── T2 (case b): BL-125 red-tests block appends details.gate=bl125_tests ────────
if want T2; then
echo "=== T2-bl125-block-appends-row ==="
P="$TOPTMP/p2"; mk_proj "$P"
set_testcmd "$P" 1                  # project tests RED
stage_src "$P"
H0=$(head_of "$P")
V=$(try_commit "$P" "chore: add widget" "$P/commit.log" "$NOSCAN_PATH")
H1=$(head_of "$P")
N=$(blocked_rows "$P"); NG=$(rows_for_gate "$P" bl125_tests)
if [ "$V" = "REFUSED" ] && [ "$H0" = "$H1" ] && grep -qF '[BLOCKED] project tests FAILED' "$P/commit.log" \
   && [ "$N" -eq 1 ] && [ "$NG" -eq 1 ]; then
  pass "T2-bl125-block-appends-row (REFUSED, HEAD unmoved, 1 terminal_commit_blocked row gate=bl125_tests)"
else
  fail_ "T2-bl125-block-appends-row" "verdict=$V blocked_rows=$N gate_bl125=$NG (want REFUSED/1/1): $(tail -3 "$P/commit.log" | tr '\n' ' ')"
fi
fi

# ── T3 (case c): a CLEAN commit appends NO blocked row (no false entries) ───────
if want T3; then
echo "=== T3-clean-commit-no-row ==="
P="$TOPTMP/p3"; mk_proj "$P"
set_testcmd "$P" 0                  # tests GREEN
stage_src "$P"
FAKE0=$(fake_scanner semgrep 0)     # semgrep clean
H0=$(head_of "$P")
V=$(try_commit "$P" "chore: add widget" "$P/commit.log" "$FAKE0:$NOSCAN_PATH")
H1=$(head_of "$P")
N=$(blocked_rows "$P")
if [ "$V" = "LANDED" ] && [ "$H0" != "$H1" ] && [ "$N" -eq 0 ]; then
  pass "T3-clean-commit-no-row (LANDED, HEAD moved, zero terminal_commit_blocked rows — no false ledger entries)"
else
  fail_ "T3-clean-commit-no-row" "verdict=$V blocked_rows=$N (want LANDED/0) — a clean commit wrote a phantom block row: $(tail -3 "$P/commit.log" | tr '\n' ' ')"
fi
fi

# ── T4 (case d): NON-FATAL — remove the append lib, the block is UNWEAKENED ─────
# Requirement 2's own mutation-proofed case: the mutant of T1 with the append
# library removed. The commit must STILL be REFUSED (the property under test),
# with at most a one-line non-fatal [note] and no row written.
if want T4; then
echo "=== T4-nonfatal-missing-lib-still-refuses ==="
P="$TOPTMP/p4"; mk_proj "$P"
rm -f "$P/scripts/lib/bypass-audit.sh"   # break the append library
FAKE=$(fake_scanner semgrep 1)
stage_src "$P"
H0=$(head_of "$P")
V=$(try_commit "$P" "chore: add widget" "$P/commit.log" "$FAKE:$NOSCAN_PATH")
H1=$(head_of "$P")
N=$(blocked_rows "$P")
if [ "$V" = "REFUSED" ] && [ "$H0" = "$H1" ] && grep -qF '[BLOCKED] Semgrep' "$P/commit.log" \
   && grep -qF '[note] BL-163' "$P/commit.log" && [ "$N" -eq 0 ]; then
  pass "T4-nonfatal-missing-lib-still-refuses (append lib gone -> commit STILL REFUSED, one-line [note], no row — the block is never weakened by ledger trouble)"
else
  fail_ "T4-nonfatal-missing-lib-still-refuses" "verdict=$V blocked_rows=$N note=$(grep -cF '[note] BL-163' "$P/commit.log") (want REFUSED/0/>=1) — a ledger failure must not change the refusal: $(tail -3 "$P/commit.log" | tr '\n' ' ')"
fi
fi

# ── T5 (case e): fence-excision mutant -> rows STOP, refusal UNCHANGED ──────────
# Strip the emitted # BL-163-BLOCKED-LEDGER block (helper BEGIN..END + every
# tagged call site) from the template, emit the mutant hook: the arm still blocks
# (FAILED=1 -> terminal exit) but writes NO row. Proves the ledger mechanism —
# and nothing else — is what records the block.
if want T5; then
echo "=== T5-fence-excision-mutant ==="
REALHOOK="$TOPTMP/real-hook"
( source "$HOOKLIB" && soif_write_precommit_hook "$REALHOOK" ) && chmod +x "$REALHOOK"
before=$(emitted_marker_count "$REALHOOK")
case "$before" in ''|*[!0-9]*) before=0 ;; esac
MUTLIB="$TOPTMP/hook-templates.mut.sh"
sed -e '/# BL-163-BLOCKED-LEDGER-BEGIN/,/# BL-163-BLOCKED-LEDGER-END/d' \
    -e '/# BL-163-BLOCKED-LEDGER$/d' "$HOOKLIB" > "$MUTLIB"
MUTHOOK="$TOPTMP/mut-hook"
( source "$MUTLIB" && soif_write_precommit_hook "$MUTHOOK" ) && chmod +x "$MUTHOOK"
after=$(emitted_marker_count "$MUTHOOK")
case "$after" in ''|*[!0-9]*) after=0 ;; esac
still_calls=$(grep -c 'soif_ledger_blocked' "$MUTHOOK" 2>/dev/null) || still_calls=0
case "$still_calls" in ''|*[!0-9]*) still_calls=0 ;; esac
if [ "$before" -lt 4 ] || [ "$after" -ne 0 ] || [ "$still_calls" -ne 0 ] || ! bash -n "$MUTHOOK" 2>/dev/null; then
  fail_ "T5-fence-excision-mutant" "excision vacuous or broke the hook (markers before=$before after=$after residual_calls=$still_calls) — fence absent, sed missed it, or the mutant is not valid bash"
else
  P="$TOPTMP/p5"; mk_proj "$P" "$MUTLIB"
  FAKE=$(fake_scanner semgrep 1)
  stage_src "$P"
  H0=$(head_of "$P")
  V=$(try_commit "$P" "chore: add widget" "$P/commit.log" "$FAKE:$NOSCAN_PATH")
  H1=$(head_of "$P")
  N=$(blocked_rows "$P")
  if [ "$V" = "REFUSED" ] && [ "$H0" = "$H1" ] && grep -qF '[BLOCKED] Semgrep' "$P/commit.log" && [ "$N" -eq 0 ]; then
    pass "T5-fence-excision-mutant (excised ledger -> the arm still REFUSES the commit but writes 0 rows — the # BL-163-BLOCKED-LEDGER block is load-bearing for the ledger, not the block)"
  else
    fail_ "T5-fence-excision-mutant" "verdict=$V blocked_rows=$N (want REFUSED/0) — the mutant either stopped blocking or still logged: $(tail -3 "$P/commit.log" | tr '\n' ' ')"
  fi
fi
fi

# ── T6: gitleaks (the third blocking arm) also appends details.gate=gitleaks ────
# Requirement 1: cover EVERY blocking arm found. gitleaks is the sibling arm.
if want T6; then
echo "=== T6-gitleaks-block-appends-row ==="
P="$TOPTMP/p6"; mk_proj "$P"
FAKE=$(fake_scanner gitleaks 1)     # gitleaks "detected secrets"
stage_src "$P"
H0=$(head_of "$P")
V=$(try_commit "$P" "chore: add widget" "$P/commit.log" "$FAKE:$NOSCAN_PATH")
H1=$(head_of "$P")
N=$(blocked_rows "$P"); NG=$(rows_for_gate "$P" gitleaks)
if [ "$V" = "REFUSED" ] && [ "$H0" = "$H1" ] && grep -qF '[BLOCKED] gitleaks' "$P/commit.log" \
   && [ "$N" -eq 1 ] && [ "$NG" -eq 1 ]; then
  pass "T6-gitleaks-block-appends-row (REFUSED, HEAD unmoved, 1 terminal_commit_blocked row gate=gitleaks)"
else
  fail_ "T6-gitleaks-block-appends-row" "verdict=$V blocked_rows=$N gate_gitleaks=$NG (want REFUSED/1/1): $(tail -3 "$P/commit.log" | tr '\n' ' ')"
fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$SKIPPED" -gt 0 ] && echo "($SKIPPED skipped — see [SKIP] lines)"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
