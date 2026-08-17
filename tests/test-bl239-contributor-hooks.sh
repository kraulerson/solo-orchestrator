#!/usr/bin/env bash
# tests/test-bl239-contributor-hooks.sh
#
# BL-239 — `scripts/install-contributor-hooks.sh` installed a NO-OP and said
# otherwise. It did `cp scripts/pre-commit-gate.sh .git/hooks/pre-commit` and
# printed "Local commits now face the same gates CI runs". They faced nothing:
# `pre-commit-gate.sh` is a PreToolUse hook whose contract is "no output =
# ALLOW", and git runs a pre-commit hook with no arguments and no stdin JSON, so
# every commit took the allow path and exited 0 silently.
#
# ── WHAT THIS SUITE ASSERTS, AND WHY IT IS BEHAVIOURAL ──────────────────────
# A hook that EXISTS, is EXECUTABLE, and exits 0 without running anything is
# indistinguishable from a healthy one by every structural check this repo has —
# which is precisely why the defect survived. `verify-install.sh` and the
# currency manifest both record hook PRESENCE (`pre-commit: present`), not hook
# BEHAVIOUR. So presence is not asserted here at all; every case runs a REAL
# COMMIT through the installed hook and requires it to EMIT something
# attributable to a known arm.
#
# A1 is the control that makes the rest mean anything: it reproduces the OLD
# install and requires it to produce ZERO gate output. Without A1 a green A2
# could mean "the hook works" or "this fixture cannot tell the difference".
#
# Hermetic: a throwaway git repo under a temp dir, `git init` with an explicit
# branch name (# BL-234-FIXTURE-BARE-HEAD's sibling rule), a configured
# identity, no remotes, no network. bash 3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLER="$REPO_ROOT/scripts/install-contributor-hooks.sh"
TEMPLATES="$REPO_ROOT/scripts/lib/hook-templates.sh"
GATE="$REPO_ROOT/scripts/pre-commit-gate.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'chmod -R u+rwX "$TOPTMP" 2>/dev/null; rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/caseXXXXXX"; }

_num() { case "$1" in ''|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac }

# ARM_RE — output only a hook that actually RAN its arms can produce. Kept
# deliberately broad across the arms rather than pinned to one tool's wording,
# because the point is "something ran", not "semgrep in particular said X".
ARM_RE='gitleaks|[Ss]emgrep|SAST|\[WARN\]|\[BLOCKED\]|NOT ENFORCED'

# mk_repo <dir> — a throwaway repo with one staged file and a git identity.
# The branch is NAMED: an unnamed default differs between this host and an
# ubuntu runner, and a fixture that depends on which one you get is broken on
# exactly one of them.
mk_repo() {
  local d="$1"
  mkdir -p "$d/scripts/lib"
  ( cd "$d" && git init --quiet --initial-branch=main . 2>/dev/null || git init --quiet . )
  ( cd "$d" && git symbolic-ref HEAD refs/heads/main 2>/dev/null )
  ( cd "$d" && git config user.email t@example.invalid && git config user.name "Fixture" )
  cp "$GATE" "$d/scripts/pre-commit-gate.sh"
  cp "$TEMPLATES" "$d/scripts/lib/hook-templates.sh"
  printf 'echo hi\n' > "$d/a.sh"
  ( cd "$d" && git add -A )
}

# commit_arm_lines <dir> <msg> — commit, echo "<rc> <arm-output-line-count>".
commit_arm_lines() {
  local d="$1" msg="$2" out rc=0 n
  out="$( cd "$d" && git commit -m "$msg" 2>&1 )" || rc=$?
  n=$(printf '%s\n' "$out" | grep -cE "$ARM_RE")
  printf '%s %s\n' "$rc" "$(_num "$n")"
}

echo "=== A — the installed hook must actually RUN, not merely exist ==="

# ── A1 (CONTROL): the OLD install produces ZERO gate output.
# This is the case that makes A2 meaningful. If this ever starts producing
# output, the fixture has stopped discriminating and A2 proves nothing.
A1="$(newtmp)"; mk_repo "$A1"
cp "$A1/scripts/pre-commit-gate.sh" "$A1/.git/hooks/pre-commit"
chmod +x "$A1/.git/hooks/pre-commit"
a1=$(commit_arm_lines "$A1" "feat: the old install faced no gate")
a1_rc="${a1%% *}"; a1_n="${a1##* }"
if [ "$a1_rc" -eq 0 ] && [ "$a1_n" -eq 0 ]; then
  pass "A1 (control): copying pre-commit-gate.sh as the hook lets the commit through with ZERO lines of gate output — git passes no arguments and no stdin JSON, so its 'no output = allow' path runs. This is the defect, reproduced"
else
  fail_ "A1" "rc=$a1_rc (want 0) arm_lines=$a1_n (want 0) — the control no longer reproduces the no-op install, so A2 below discriminates nothing"
fi

# ── A2: the installer's hook DOES run its arms.
A2="$(newtmp)"; mk_repo "$A2"
a2_install_rc=0
( cd "$A2" && bash "$INSTALLER" >/dev/null 2>&1 ) || a2_install_rc=$?
a2=$(commit_arm_lines "$A2" "feat: the fixed install faces a real gate")
a2_rc="${a2%% *}"; a2_n="${a2##* }"
if [ "$a2_install_rc" -eq 0 ] && [ "$a2_n" -ge 1 ]; then
  pass "A2: after the installer runs, the same commit produces $a2_n line(s) of gate output — the hook's arms execute instead of returning ALLOW without looking"
else
  fail_ "A2" "installer rc=$a2_install_rc (want 0) arm_lines=$a2_n (want >=1) — the installed hook produced nothing attributable to any arm, which is what a no-op looks like"
fi

# ── A3: BOTH hooks are installed. The commit-msg half — where the BL-072 TDD
# ordering gate and the BL-006 Build-Loop message check live — was never
# installed for contributors at all, only for generated projects.
A3="$(newtmp)"; mk_repo "$A3"
( cd "$A3" && bash "$INSTALLER" >/dev/null 2>&1 ) || true
a3_missing=""
for h in pre-commit commit-msg; do
  [ -x "$A3/.git/hooks/$h" ] || a3_missing="$a3_missing $h"
done
a3_tdd=0
grep -qF 'SOIF BL-072 TDD gate' "$A3/.git/hooks/commit-msg" 2>/dev/null && a3_tdd=1
if [ -z "$a3_missing" ] && [ "$a3_tdd" -eq 1 ]; then
  pass "A3: both hooks land executable, and commit-msg carries the BL-072 TDD block — the half that generated projects always got and contributors never did"
else
  fail_ "A3" "missing/not-executable:$a3_missing tdd_block_present=$a3_tdd (want 1)"
fi

# ── A4: idempotent. Re-running must refresh, not append a second TDD block.
A4="$(newtmp)"; mk_repo "$A4"
( cd "$A4" && bash "$INSTALLER" >/dev/null 2>&1 ) || true
( cd "$A4" && bash "$INSTALLER" >/dev/null 2>&1 ) || true
a4_blocks=$(_num "$(grep -cF 'SOIF BL-072 TDD gate (commit-msg)' "$A4/.git/hooks/commit-msg" 2>/dev/null)")
if [ "$a4_blocks" -eq 1 ]; then
  pass "A4: running the installer twice leaves exactly one TDD block in commit-msg — the same idempotence predicate init.sh uses, so a refresh cannot stack duplicates"
else
  fail_ "A4" "TDD open-marker count=$a4_blocks (want exactly 1)"
fi

echo "=== M — mutation proof ==="

# ── M1: restore the OLD install inside the installer and A2 must go dark.
# The mutant is the literal line the script used to carry.
M1="$(newtmp)"; mk_repo "$M1"
cp "$INSTALLER" "$M1/installer.sh"
m1_tmp="$(mktemp)"
m1_changed=$(awk -v n=0 '
  /^soif_write_precommit_hook "\$ROOT\/.git\/hooks\/pre-commit"/ {
    print "cp \"$ROOT/scripts/pre-commit-gate.sh\" \"$ROOT/.git/hooks/pre-commit\"; chmod +x \"$ROOT/.git/hooks/pre-commit\""
    n++; next }
  { print }
  END { print n+0 > "/dev/stderr" }
' "$M1/installer.sh" 2>&1 >"$m1_tmp")
mv "$m1_tmp" "$M1/installer.sh"
m1_changed=$(_num "$m1_changed")
m1_parses=0; bash -n "$M1/installer.sh" >/dev/null 2>&1 && m1_parses=1
( cd "$M1" && bash "$M1/installer.sh" >/dev/null 2>&1 ) || true
m1=$(commit_arm_lines "$M1" "feat: mutant restores the no-op install")
m1_n="${m1##* }"
if [ "$m1_changed" -eq 1 ] && [ "$m1_parses" -eq 1 ] && [ "$m1_n" -eq 0 ]; then
  pass "M1: with the old \`cp the gate\` line restored, the same commit falls back to ZERO lines of gate output — A2 is measuring that the hook RUNS, not that a file exists (changed=$m1_changed parses=$m1_parses)"
else
  fail_ "M1" "changed=$m1_changed (want 1 — 0 means the mutation never applied and this proves nothing) parses=$m1_parses (want 1) arm_lines=$m1_n (want 0)"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
