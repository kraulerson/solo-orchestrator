#!/usr/bin/env bash
# tests/test-bl141-commitmsg-repair.sh — BL-141 (Dogfood-3 wave verifier B1/B2):
# verify-install must detect + repair a missing commit-msg TDD gate hook, and
# the sync must WARN when it declines to install one on a project that has the
# pre-commit hook.
#
# THE DEFECT (verifier census)
#   BL-139 moved the terminal-path feat/Build-Loop rule to the COMMIT-MSG
#   surface. That backstop is population-conditional: fresh scaffolds get the
#   hook (BL-107), but `verify-install --auto-fix` checked/repaired ONLY
#   .git/hooks/pre-commit (no commit-msg detection anywhere), and a piped
#   --sync-framework without --install-hooks leaves it "not installed
#   (declined)" — quietly. A legacy/declined strict-tier project ends up with
#   NO terminal-path feat gate at all, on exactly the tiers where the docs
#   call the block non-bypassable.
#
# THE FIX
#   # BL-141-COMMITMSG-VERIFY in verify-install.sh: check_git detects an
#   absent/unmarked/non-executable commit-msg hook (marker = SOIF_TDD_OPEN,
#   the managed-block contract) as auto-fixable; fix_commitmsg_hook repairs
#   via the SINGLE SOURCE (hook-templates.sh emitters — the BL-118 doctrine:
#   never inline a hook body), composing with an existing user hook and
#   idempotent on the marker.
#   # BL-141-SYNC-WARN in upgrade-project.sh: the declined-install arm WARNs
#   when .git/hooks/pre-commit exists but commit-msg does not — the exact
#   asymmetry that silently strips the backstop — naming the repair commands.
#
# REGISTRATION: no init.sh, not an aggregator -> BOTH lists. Hermetic (hooks
# emitted from hook-templates.sh, real git commits in mktemp fixtures, the
# sync runs against this checkout with CDF_HOME pointed at a void). bash-3.2
# safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

unset GITHUB_BASE_REF 2>/dev/null || true

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq required"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

TDD_OPEN='# >>> SOIF BL-072 TDD gate (commit-msg) — managed by init.sh'

# mk_proj <dir> — strict-tier phase-2 project: git repo, framework scripts
# copied project-local (verify-install's repair reads the PROJECT-LOCAL
# hook-templates.sh first), REAL pre-commit + framework-gate installed via
# install-filesystem-gates.sh, NO commit-msg hook — the BL-141 population.
mk_proj() {
  local d="$1"
  rm -rf "$d"
  mkdir -p "$d/.claude" "$d/scripts/lib" "$d/src"
  ( cd "$d" && git init -q && git config user.email t@t.invalid && git config user.name t \
      && echo "# scratch" > README.md && git add README.md && git commit -q -m "chore: init" ) || return 1
  cat > "$d/.claude/manifest.json" <<'JSON'
{"frameworkVersion":"test","host":"other","mode":"personal","deployment":"personal","enforcement_level":"strict"}
JSON
  cat > "$d/.claude/phase-state.json" <<'JSON'
{"current_phase":2,"track":"light","deployment":"personal","poc_mode":null,"phases":{}}
JSON
  cat > "$d/.claude/process-state.json" <<'JSON'
{"phase2_init":{"steps_completed":["remote_repo_created","pushed_initial"],"verified":true},"build_loop":{"feature":null,"step":0,"steps_completed":[]},"uat_session":{},"phase3_validation":{},"phase4_release":{}}
JSON
  cp "$REPO_ROOT/scripts/process-checklist.sh" \
     "$REPO_ROOT/scripts/pre-commit-gate.sh" \
     "$REPO_ROOT/scripts/install-filesystem-gates.sh" \
     "$REPO_ROOT/scripts/verify-install.sh" "$d/scripts/"
  cp "$REPO_ROOT/scripts/lib/helpers.sh" \
     "$REPO_ROOT/scripts/lib/helpers-core.sh" \
     "$REPO_ROOT/scripts/lib/helpers-full.sh" \
     "$REPO_ROOT/scripts/lib/tdd-classify.sh" \
     "$REPO_ROOT/scripts/lib/hook-templates.sh" \
     "$REPO_ROOT/scripts/lib/enforcement-level.sh" "$d/scripts/lib/" 2>/dev/null
  chmod +x "$d/scripts/"*.sh
  bash "$REPO_ROOT/scripts/install-filesystem-gates.sh" --install "$d" >/dev/null 2>&1
  rm -f "$d/.git/hooks/commit-msg"
}

# ── T1: --check-only DETECTS the missing commit-msg gate, touches nothing ────
echo "=== T1-check-only-detects ==="
P="$TOPTMP/p1"; mk_proj "$P"
out=$( cd "$P" && bash scripts/verify-install.sh --check-only </dev/null 2>&1 ) || true
if printf '%s' "$out" | grep -qi 'commit-msg.*\(missing\|absent\)' && [ ! -f "$P/.git/hooks/commit-msg" ]; then
  pass "T1-check-only-detects (the absence is a named finding, and check-only stays non-destructive)"
else
  fail_ "T1-check-only-detects" "verify-install --check-only says nothing about the absent commit-msg gate (B1): $(printf '%s' "$out" | grep -i 'hook' | head -3 | tr '\n' ' ')"
fi

# ── T2: --auto-fix INSTALLS it, and the BL-139 backstop is REAL again ────────
echo "=== T2-autofix-restores-backstop ==="
P="$TOPTMP/p2"; mk_proj "$P"
( cd "$P" && bash scripts/verify-install.sh --auto-fix </dev/null >/dev/null 2>&1 ) || true
if [ ! -x "$P/.git/hooks/commit-msg" ] || ! grep -qF "$TDD_OPEN" "$P/.git/hooks/commit-msg" 2>/dev/null; then
  fail_ "T2-autofix-restores-backstop" "--auto-fix did not install a marked, executable commit-msg hook (B1)"
else
  # End-to-end (the bl139-T4 shape): a loop-less feat commit must DIE at the
  # commit-msg surface — the exact enforcement the absent hook was losing.
  ( cd "$P" && printf 'export const x = 1;\n' > src/widget.ts && git add src/widget.ts )
  H0=$( cd "$P" && git rev-parse HEAD )
  ( cd "$P" && git commit -m "feat: widget with no loop" </dev/null ) >"$P/commit.log" 2>&1
  rc=$?
  H1=$( cd "$P" && git rev-parse HEAD )
  if [ "$rc" -ne 0 ] && [ "$H0" = "$H1" ]; then
    pass "T2-autofix-restores-backstop (hook installed AND a loop-less feat: commit dies at commit-msg again)"
  else
    fail_ "T2-autofix-restores-backstop" "rc=$rc — the repaired hook did not block the loop-less feat commit: $(tail -3 "$P/commit.log" | tr '\n' ' ')"
  fi
fi

# ── T3: compose + idempotence — a user's existing hook is preserved ──────────
echo "=== T3-compose-preserves-user-hook ==="
P="$TOPTMP/p3"; mk_proj "$P"
printf '%s\n%s\n' '#!/usr/bin/env bash' 'echo user-owned-line' > "$P/.git/hooks/commit-msg"
chmod +x "$P/.git/hooks/commit-msg"
( cd "$P" && bash scripts/verify-install.sh --auto-fix </dev/null >/dev/null 2>&1 ) || true
( cd "$P" && bash scripts/verify-install.sh --auto-fix </dev/null >/dev/null 2>&1 ) || true
n=$(grep -cF "$TDD_OPEN" "$P/.git/hooks/commit-msg" 2>/dev/null) || n=0
case "$n" in ''|*[!0-9]*) n=0 ;; esac
if grep -qF 'user-owned-line' "$P/.git/hooks/commit-msg" && [ "$n" -eq 1 ]; then
  pass "T3-compose-preserves-user-hook (user bytes kept; managed block appended exactly once across two runs)"
else
  fail_ "T3-compose-preserves-user-hook" "marker count=$n, user line $(grep -qF 'user-owned-line' "$P/.git/hooks/commit-msg" && echo kept || echo LOST) — repair must compose, not clobber"
fi

# ── T4: sync declines non-interactively -> the WARN names the lost backstop ──
echo "=== T4-sync-declined-warns ==="
P="$TOPTMP/p4"; mk_proj "$P"
out=$( cd "$P" && unset GITHUB_BASE_REF; CDF_HOME="$P/.no-such-cdf" SOIF_NONINTERACTIVE=1 \
        bash "$REPO_ROOT/scripts/upgrade-project.sh" --sync-framework </dev/null 2>&1 ) || true
if printf '%s' "$out" | grep -q 'not installed (declined)' \
   && printf '%s' "$out" | grep -q 'BL-141'; then
  pass "T4-sync-declined-warns (the decline is no longer quiet: the WARN names the missing backstop + the repair)"
else
  fail_ "T4-sync-declined-warns" "non-interactive sync left the commit-msg gate absent with no BL-141 WARN (B2): $(printf '%s' "$out" | grep -i 'commit-msg' | head -3 | tr '\n' ' ')"
fi

# ── T5: fence-excision mutants — both fences are load-bearing ────────────────
echo "=== T5-fence-excision-mutants ==="
MUTVI="$TOPTMP/verify-install.mut.sh"
m1=$(grep -c 'BL-141-COMMITMSG-VERIFY' "$REPO_ROOT/scripts/verify-install.sh") || m1=0
case "$m1" in ''|*[!0-9]*) m1=0 ;; esac
sed '/# BL-141-COMMITMSG-VERIFY-BEGIN/,/# BL-141-COMMITMSG-VERIFY-END/d' \
  "$REPO_ROOT/scripts/verify-install.sh" > "$MUTVI"
l1=$(grep -c 'BL-141-COMMITMSG-VERIFY' "$MUTVI") || l1=0
case "$l1" in ''|*[!0-9]*) l1=0 ;; esac
if [ "$m1" -lt 2 ] || [ "$l1" -ne 0 ]; then
  fail_ "T5a-verify-fence-mutant" "excision vacuous (markers before=$m1 after=$l1)"
else
  P="$TOPTMP/p5"; mk_proj "$P"
  cp "$MUTVI" "$P/scripts/verify-install.sh"; chmod +x "$P/scripts/verify-install.sh"
  ( cd "$P" && bash scripts/verify-install.sh --auto-fix </dev/null >/dev/null 2>&1 ) || true
  if [ ! -f "$P/.git/hooks/commit-msg" ]; then
    pass "T5a-verify-fence-mutant (excised fence -> auto-fix ignores the hook again — the fence is load-bearing)"
  else
    fail_ "T5a-verify-fence-mutant" "mutant verify-install still installed the hook; the repair does not live (only) in the fence"
  fi
fi
# The mutant must run from a faithful FRAMEWORK TREE (upgrade-project.sh
# resolves its framework root from its own location) — the sync-suite's
# make_fake_framework shape, with the fence excised inside the copy.
FWMUT="$TOPTMP/fwmut"
mkdir -p "$FWMUT/templates"
cp "$REPO_ROOT/init.sh" "$FWMUT/init.sh"
cp -R "$REPO_ROOT/scripts" "$FWMUT/scripts"
cp -R "$REPO_ROOT/docs" "$FWMUT/docs"
cp -R "$REPO_ROOT/templates/generated" "$FWMUT/templates/generated"
cp "$REPO_ROOT/templates/project-intake.md" "$FWMUT/templates/project-intake.md"
( cd "$FWMUT" && git init -q && git config user.email fw@t.invalid && git config user.name FW \
    && unset GITHUB_BASE_REF && git add -A && git commit -q -m "mutant framework HEAD" ) >/dev/null 2>&1
MUTUP="$FWMUT/scripts/upgrade-project.sh"
m2=$(grep -c 'BL-141-SYNC-WARN' "$REPO_ROOT/scripts/upgrade-project.sh") || m2=0
case "$m2" in ''|*[!0-9]*) m2=0 ;; esac
sed '/# BL-141-SYNC-WARN-BEGIN/,/# BL-141-SYNC-WARN-END/d' \
  "$REPO_ROOT/scripts/upgrade-project.sh" > "$MUTUP.tmp" && mv "$MUTUP.tmp" "$MUTUP"
l2=$(grep -c 'BL-141-SYNC-WARN' "$MUTUP") || l2=0
case "$l2" in ''|*[!0-9]*) l2=0 ;; esac
if [ "$m2" -lt 2 ] || [ "$l2" -ne 0 ]; then
  fail_ "T5b-sync-fence-mutant" "excision vacuous (markers before=$m2 after=$l2)"
else
  chmod +x "$MUTUP"
  P="$TOPTMP/p5b"; mk_proj "$P"
  out=$( cd "$P" && unset GITHUB_BASE_REF; CDF_HOME="$P/.no-such-cdf" SOIF_NONINTERACTIVE=1 \
          bash "$MUTUP" --sync-framework </dev/null 2>&1 ) || true
  if printf '%s' "$out" | grep -q 'not installed (declined)' \
     && ! printf '%s' "$out" | grep -q 'BL-141'; then
    pass "T5b-sync-fence-mutant (excised fence -> the decline is quiet again — the WARN is load-bearing)"
  else
    fail_ "T5b-sync-fence-mutant" "mutant sync still warned (or the declined arm vanished): $(printf '%s' "$out" | grep -i 'commit-msg' | head -2 | tr '\n' ' ')"
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
