#!/usr/bin/env bash
# tests/test-bl145-hook-symlink-hookspath.sh — BL-145 (Dogfood-3 SHOULD-fix
# wave, consolidated verifier S3): verify-install's hook repairs must never
# write THROUGH a symlinked hook, and its hook checks must not be blind to
# `core.hooksPath`.
#
# THE DEFECT (as executed by the verifier)
#   (1) SYMLINK WRITE-THROUGH. With .git/hooks/commit-msg symlinked to a
#       shared out-of-tree file (a dotfiles-managed hook), `verify-install
#       --auto-fix` appended the managed BL-072 block into the symlink
#       TARGET — the link was kept, the operator's shared file was mutated.
#       fix_precommit_hook is worse: soif_write_precommit_hook opens the
#       path with `>`, so a symlinked (or DANGLING) pre-commit hook meant a
#       full clobber of — or a surprise file creation at — whatever the link
#       pointed at. `--auto-fix` is a NO-CONSENT surface, so this is the arm
#       that has to refuse.
#   (2) core.hooksPath BLINDNESS. Both hook checks read `.git/hooks/`
#       literally. git consults `core.hooksPath` INSTEAD when it is set, so a
#       project using it got a green PASS for hooks git never runs, and an
#       "auto-fixed" repair written into the inert `.git/hooks/` directory.
#
# THE FIX (scripts/verify-install.sh)
#   # BL-145-SYMLINK-GUARD — a hook path that is a symlink is NEVER repaired.
#     check_git registers it as MANUAL naming the resolved target, and the
#     repair halves (fix_precommit_hook / fix_commitmsg_hook) refuse loudly
#     to stderr as defense in depth. Repairing a shared file needs a human.
#   # BL-145-HOOKSPATH — `git config core.hooksPath` is consulted. When set,
#     the CHECKS look where git actually looks (honored), and the REPAIRS
#     refuse loudly (a core.hooksPath directory can be shared across repos or
#     tracked in the project — writing into it is the same no-consent write
#     as the symlink case, and writing into `.git/hooks` instead would be an
#     inert "repair" that reports success).
#
# REGISTRATION: no init.sh, not an aggregator -> BOTH lists (aggregator +
# tests.yml unit array).
#
# PORTABILITY: bash 3.2; every path quoted; symlink targets resolved with a
# GUARDED `readlink` WITHOUT `-f` (BSD/macOS readlink has no -f) — a relative
# link value is anchored to the link's own directory by string manipulation,
# which is identical on macOS and Linux. Hermetic: mktemp fixtures, local git
# identity, GITHUB_BASE_REF unset, no remotes. Hook bytes come from the REAL
# emitter (scripts/lib/hook-templates.sh), sourced in a SUBSHELL so its
# top-level assignments cannot touch this suite's counters.

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

# HOST DEPENDENCY, NAMED RATHER THAN HIDDEN (the BL-135 lesson). Fixtures are
# `git init`-ed under mktemp, so they inherit GLOBAL/SYSTEM git config. A host
# that sets core.hooksPath there puts every fixture on the hooksPath arm of the
# guard, and the symlink cases below would report a refusal that names the
# directory instead of the link — a host-shaped RED, not a defect. Detect it
# and SKIP LOUDLY. (Neutralizing it would need GIT_CONFIG_GLOBAL, which is
# git >= 2.32 only, or an $HOME move, which would send check_framework off to
# clone the framework for real — neither is worth it for a config almost
# nobody sets.)
_inherited_hookspath="$(git config --global --get core.hooksPath 2>/dev/null || true)"
if [ -z "$_inherited_hookspath" ]; then
  _inherited_hookspath="$(git config --system --get core.hooksPath 2>/dev/null || true)"
fi
if [ -n "$_inherited_hookspath" ]; then
  echo "SKIP: this host sets core.hooksPath in global/system git config ('$_inherited_hookspath'), so a fresh fixture repo cannot exercise the .git/hooks symlink arm. Unset it (git config --global --unset core.hooksPath) to run this suite."
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

TDD_OPEN='# >>> SOIF BL-072 TDD gate (commit-msg) — managed by init.sh'

# mk_proj <dir> — the BL-141 fixture shape: a strict-tier phase-2 project with
# the framework scripts copied PROJECT-LOCAL (verify-install's repair reads the
# project-local hook-templates.sh first), a REAL pre-commit + framework-gate
# installed via install-filesystem-gates.sh, and no commit-msg hook.
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

# mk_shared_hook <path> <mode> — a user's out-of-tree, dotfiles-managed hook
# plus a pristine copy at <path>.pristine for byte comparison.
mk_shared_hook() {
  local p="$1" mode="${2:-exec}"
  mkdir -p "$(dirname "$p")"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' '# dotfiles-managed hook shared by every repo I own'
    printf '%s\n' 'echo "user-owned hook ran"'
  } > "$p"
  [ "$mode" = "exec" ] && chmod +x "$p"
  cp "$p" "$p.pristine"
}

# emit_real_hooks <dir> — the REAL emitted artifacts, from the single emitter.
emit_real_hooks() {
  local hd="$1"
  mkdir -p "$hd"
  (
    # shellcheck source=/dev/null
    . "$REPO_ROOT/scripts/lib/hook-templates.sh"
    soif_write_precommit_hook "$hd/pre-commit"
    printf '%s\n' '#!/usr/bin/env bash' > "$hd/commit-msg"
    soif_emit_tdd_commitmsg_block >> "$hd/commit-msg"
  ) || return 1
  chmod +x "$hd/commit-msg"
}

run_autofix() {  # run_autofix <projdir> [script-override]
  local p="$1" s="${2:-scripts/verify-install.sh}"
  ( cd "$p" && bash "$s" --auto-fix </dev/null 2>&1 ) || true
}

# ── T1: commit-msg symlink — the verifier's executed repro ───────────────────
# Today: the managed block is APPENDED INTO THE TARGET (target mutated, link
# kept). Required: the target is byte-identical afterwards and the refusal
# NAMES it.
#
# The link value here is deliberately RELATIVE (R-BL145-2). `readlink` without
# `-f` prints the RAW value, which is meaningless from the project root, so
# _bl145_symlink_target anchors it to the LINK's own directory
# (# BL-145-RELATIVE-ANCHOR). Asserting the ANCHORED spelling pins that atom's
# width: delete the anchoring arm and this assertion goes RED (T6c re-proves it
# mechanically). T2 keeps an ABSOLUTE link so both spellings stay covered.
echo "=== T1-commitmsg-symlink-target-preserved ==="
P="$TOPTMP/p1"; mk_proj "$P"
SH1="$TOPTMP/dotfiles1/commit-msg"; mk_shared_hook "$SH1" exec
REL1="../../../dotfiles1/commit-msg"
# The anchored spelling as the guard PRINTS it: check_git passes the hook path
# as `.git/hooks/<hook>`, and verify-install always runs from the project root,
# so `.git/hooks/../../../dotfiles1/commit-msg` resolves for the operator while
# the raw readlink value does not.
ANCHORED1=".git/hooks/$REL1"
ln -s "$REL1" "$P/.git/hooks/commit-msg"
[ -e "$P/.git/hooks/commit-msg" ] || fail_ "T1-setup" "the relative link does not resolve — fixture is wrong, not the code"
out=$(run_autofix "$P")
if ! cmp -s "$SH1" "$SH1.pristine"; then
  fail_ "T1-commitmsg-symlink-target-preserved" "--auto-fix wrote THROUGH the symlink: the shared target $SH1 was mutated ($(grep -cF "$TDD_OPEN" "$SH1" 2>/dev/null || echo 0) managed block(s) appended)"
elif [ ! -L "$P/.git/hooks/commit-msg" ]; then
  fail_ "T1-commitmsg-symlink-target-preserved" "the symlink itself was replaced — the operator's link is gone"
elif ! printf '%s' "$out" | grep -qi 'symlink'; then
  fail_ "T1-commitmsg-symlink-target-preserved" "target intact but the refusal is SILENT — no 'symlink' in the report: $(printf '%s' "$out" | grep -i 'commit-msg' | head -2 | tr '\n' ' ')"
elif ! printf '%s' "$out" | grep -qF "$ANCHORED1"; then
  fail_ "T1-commitmsg-symlink-target-preserved" "the refusal does not NAME the target it declined to clobber, ANCHORED to the link's own directory ($ANCHORED1) — a raw '$REL1' cannot be acted on from the project root: $(printf '%s' "$out" | grep -i 'symlink' | head -2 | tr '\n' ' ')"
else
  pass "T1-commitmsg-symlink-target-preserved (target byte-identical, link kept, refusal names the RELATIVE link's target anchored to its own directory)"
fi

# ── T2: pre-commit symlink — the FULL-CLOBBER half ───────────────────────────
# The target is non-executable, so `[ -x ]` fails and the repair is dispatched;
# soif_write_precommit_hook opens the path with `>` and overwrites the target.
echo "=== T2-precommit-symlink-target-preserved ==="
P="$TOPTMP/p2"; mk_proj "$P"
SH2="$TOPTMP/dotfiles2/pre-commit"; mk_shared_hook "$SH2" noexec
rm -f "$P/.git/hooks/pre-commit"
ln -s "$SH2" "$P/.git/hooks/pre-commit"
out=$(run_autofix "$P")
if ! cmp -s "$SH2" "$SH2.pristine"; then
  fail_ "T2-precommit-symlink-target-preserved" "--auto-fix CLOBBERED the shared target $SH2 through the symlink (soif_write_precommit_hook's '>' followed the link)"
elif [ ! -L "$P/.git/hooks/pre-commit" ]; then
  fail_ "T2-precommit-symlink-target-preserved" "the symlink itself was replaced — the operator's link is gone"
elif ! printf '%s' "$out" | grep -qi 'symlink' || ! printf '%s' "$out" | grep -qF "$SH2"; then
  fail_ "T2-precommit-symlink-target-preserved" "target intact but the refusal does not name it loudly: $(printf '%s' "$out" | grep -i 'pre-commit' | head -2 | tr '\n' ' ')"
else
  pass "T2-precommit-symlink-target-preserved (target byte-identical, link kept, refusal names it)"
fi

# ── T2b: the HOOKS DIRECTORY itself is a symlink (R-BL145-1, the BLOCK) ──────
# `ln -s ~/.githooks .git/hooks` is the classic idiom, and it defeats a LEAF
# `-L` test completely: .git/hooks/pre-commit is a regular file INSIDE the
# shared directory, so the guard saw nothing and --auto-fix clobbered a 3-line
# shared hook into the full SOIF hook AND created a second file (commit-msg) in
# the operator's shared directory. Required: refuse, naming the DIRECTORY's
# resolved target, and leave the shared directory byte-for-byte as it was.
echo "=== T2b-hooksdir-symlink-target-preserved ==="
P="$TOPTMP/p2b"; mk_proj "$P"
SHD="$TOPTMP/dotfiles-hooksdir"
mkdir -p "$SHD"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' '# dotfiles-managed hooks DIRECTORY shared by every repo I own'
  printf '%s\n' 'echo "user-owned hook ran"'
} > "$SHD/pre-commit"
PRIS2B="$TOPTMP/pristine-hooksdir-pre-commit"
cp "$SHD/pre-commit" "$PRIS2B"
rm -rf "$P/.git/hooks"
ln -s "$SHD" "$P/.git/hooks"
out=$(run_autofix "$P")
t2berr=""
cmp -s "$SHD/pre-commit" "$PRIS2B" || t2berr="$t2berr CLOBBERED-the-shared-hook($(wc -l < "$SHD/pre-commit" | tr -d ' ')-lines-now)"
[ -e "$SHD/commit-msg" ] && t2berr="$t2berr CREATED-commit-msg-in-the-shared-dir"
n2b=$(ls -1 "$SHD" | wc -l | tr -d ' ')
[ "$n2b" = "1" ] || t2berr="$t2berr shared-dir-now-has-$n2b-entries"
[ -L "$P/.git/hooks" ] || t2berr="$t2berr the-operators-directory-link-was-replaced"
printf '%s' "$out" | grep -qi 'symlink' || t2berr="$t2berr refusal-is-silent"
printf '%s' "$out" | grep -qF "$SHD" || t2berr="$t2berr refusal-does-not-name-the-DIRECTORY-target"
if [ -n "$t2berr" ]; then
  fail_ "T2b-hooksdir-symlink-target-preserved" "a symlinked .git/hooks defeats a leaf-only guard:$t2berr"
else
  pass "T2b-hooksdir-symlink-target-preserved (shared dir untouched: 1 entry, byte-identical; link kept; refusal names the directory's target)"
fi

# ── T3: DANGLING symlink must not conjure a file at the far end ──────────────
echo "=== T3-dangling-symlink-creates-nothing ==="
P="$TOPTMP/p3"; mk_proj "$P"
SH3="$TOPTMP/dotfiles3/pre-commit"; mkdir -p "$(dirname "$SH3")"
rm -f "$P/.git/hooks/pre-commit"
ln -s "$SH3" "$P/.git/hooks/pre-commit"
out=$(run_autofix "$P")
if [ -e "$SH3" ]; then
  fail_ "T3-dangling-symlink-creates-nothing" "--auto-fix CREATED $SH3 by writing through a dangling link"
elif ! printf '%s' "$out" | grep -qi 'symlink'; then
  fail_ "T3-dangling-symlink-creates-nothing" "nothing created, but the refusal is silent: $(printf '%s' "$out" | grep -i 'pre-commit' | head -2 | tr '\n' ' ')"
else
  pass "T3-dangling-symlink-creates-nothing (no file conjured at the far end; refusal is loud)"
fi

# ── T4: core.hooksPath is HONORED by the checks ──────────────────────────────
# Real, correctly-installed hooks live in .githooks and git runs them from
# there. Today the checks read .git/hooks literally: they report both hooks
# missing and "repair" into the inert .git/hooks directory.
echo "=== T4-hookspath-honored-by-checks ==="
P="$TOPTMP/p4"; mk_proj "$P"
emit_real_hooks "$P/.githooks" || fail_ "T4-setup" "could not emit real hooks"
rm -f "$P/.git/hooks/pre-commit" "$P/.git/hooks/commit-msg"
( cd "$P" && git config core.hooksPath .githooks )
out=$(run_autofix "$P")
t4err=""
[ -e "$P/.git/hooks/pre-commit" ] && t4err="$t4err inert-write:.git/hooks/pre-commit"
[ -e "$P/.git/hooks/commit-msg" ] && t4err="$t4err inert-write:.git/hooks/commit-msg"
printf '%s' "$out" | grep -qi 'pre-commit hook missing' && t4err="$t4err false-missing:pre-commit"
printf '%s' "$out" | grep -qi 'commit-msg TDD gate hook missing' && t4err="$t4err false-missing:commit-msg"
printf '%s' "$out" | grep -q 'core.hooksPath' || t4err="$t4err never-says-hookspath-is-set"
if [ -n "$t4err" ]; then
  fail_ "T4-hookspath-honored-by-checks" "checks are blind to core.hooksPath:$t4err"
else
  pass "T4-hookspath-honored-by-checks (hooks in the configured dir are SEEN; .git/hooks left untouched; the setting is named)"
fi

# ── T5: core.hooksPath set + NO hooks there — the false PASS + refuse-to-write
# .git/hooks still holds a real pre-commit hook (git ignores it entirely).
echo "=== T5-hookspath-no-false-pass ==="
P="$TOPTMP/p5"; mk_proj "$P"
mkdir -p "$P/.githooks"
( cd "$P" && git config core.hooksPath .githooks )
chk=$( cd "$P" && bash scripts/verify-install.sh --check-only </dev/null 2>&1 ) || true
out=$(run_autofix "$P")
t5err=""
printf '%s' "$chk" | grep -q 'core.hooksPath' || t5err="$t5err check-only-never-mentions-hookspath"
printf '%s' "$chk" | grep -qi 'pre-commit hook installed' && t5err="$t5err false-PASS-on-inert-.git/hooks-hook"
[ -e "$P/.githooks/pre-commit" ] && t5err="$t5err no-consent-write-into-hookspath-dir"
[ -e "$P/.githooks/commit-msg" ] && t5err="$t5err no-consent-write-into-hookspath-dir(commit-msg)"
if [ -n "$t5err" ]; then
  fail_ "T5-hookspath-no-false-pass" "$t5err | report: $(printf '%s' "$chk" | grep -i 'hook' | head -3 | tr '\n' ' ') | autofix: $(printf '%s' "$out" | grep -i 'hooksPath' | head -2 | tr '\n' ' ')"
else
  pass "T5-hookspath-no-false-pass (an inert .git/hooks hook is no longer a PASS, and --auto-fix does NOT write into the configured dir)"
fi

# ── T7: core.hooksPath set to the EMPTY STRING (R-BL145-4) ───────────────────
# `git config core.hooksPath ""` reads back as rc=0 with EMPTY output, so a
# guard keyed on output emptiness calls it unset and reproduces the original
# false PASS. It is not benign: measured on git 2.50.1, a repo with
# hooksPath set-empty does NOT run .git/hooks/pre-commit (the control below
# proves the same hook fires once the key is unset). "Set" must therefore be
# read off the EXIT STATUS.
echo "=== T7-hookspath-empty-string ==="
P="$TOPTMP/p7"; mk_proj "$P"
printf '%s\n%s\n' '#!/usr/bin/env bash' 'touch "$PWD/HOOK-RAN"' > "$P/.git/hooks/pre-commit"
chmod +x "$P/.git/hooks/pre-commit"
( cd "$P" && git config core.hooksPath "" )
# Premise probe (evidence, not an oracle — reported in the verdict text).
( cd "$P" && printf 'x\n' > probe.txt && git add probe.txt && git commit -q -m "chore: probe" ) >/dev/null 2>&1
if [ -e "$P/HOOK-RAN" ]; then t7probe="git DID run .git/hooks/pre-commit"; else t7probe="git did NOT run .git/hooks/pre-commit"; fi
chk=$( cd "$P" && bash scripts/verify-install.sh --check-only </dev/null 2>&1 ) || true
t7err=""
printf '%s' "$chk" | grep -q 'core.hooksPath' || t7err="$t7err never-mentions-the-set-but-empty-hooksPath"
printf '%s' "$chk" | grep -qi 'pre-commit hook installed' && t7err="$t7err false-PASS-on-a-hook-git-will-not-run"
if [ -n "$t7err" ]; then
  fail_ "T7-hookspath-empty-string" "set-but-empty is read as unset:$t7err (probe: $t7probe)"
else
  pass "T7-hookspath-empty-string (set-but-empty is SET — no false PASS, and the report names it; probe: $t7probe)"
fi

# ── T8: DEGENERATE core.hooksPath=.git/hooks (R-BL145-3b) ────────────────────
# The configured directory IS the default one, so any claim that git "ignores
# .git/hooks" here is simply false. The hook that is installed is the one git
# runs, so it must still PASS.
echo "=== T8-hookspath-degenerate-no-false-claims ==="
P="$TOPTMP/p8"; mk_proj "$P"
( cd "$P" && git config core.hooksPath .git/hooks )
chk=$( cd "$P" && bash scripts/verify-install.sh --check-only </dev/null 2>&1 ) || true
t8err=""
printf '%s' "$chk" | grep -qi 'ignores .git/hooks' && t8err="$t8err false-claim:'ignores .git/hooks'"
printf '%s' "$chk" | grep -qi 'pre-commit hook installed' || t8err="$t8err lost-the-legitimate-PASS"
if [ -n "$t8err" ]; then
  fail_ "T8-hookspath-degenerate-no-false-claims" "$t8err | $(printf '%s' "$chk" | grep -i 'hooksPath' | head -2 | tr '\n' ' ')"
else
  pass "T8-hookspath-degenerate-no-false-claims (hooksPath=.git/hooks: still a PASS, and no false 'git ignores .git/hooks' claim)"
fi

# ── T9: a PRESENT but UNMARKED hook in the hooksPath dir (R-BL145-3c) ────────
# The hook exists and git runs it — it just is not the managed SOIF block. The
# row must say so, not claim nothing is installed.
echo "=== T9-hookspath-unmarked-hook-wording ==="
P="$TOPTMP/p9"; mk_proj "$P"
mkdir -p "$P/.githooks"
printf '%s\n%s\n' '#!/usr/bin/env bash' 'echo user-owned commit-msg hook' > "$P/.githooks/commit-msg"
chmod +x "$P/.githooks/commit-msg"
( cd "$P" && git config core.hooksPath .githooks )
chk=$( cd "$P" && bash scripts/verify-install.sh --check-only </dev/null 2>&1 ) || true
t9err=""
printf '%s' "$chk" | grep -qi 'not the managed hook' || t9err="$t9err never-says-'not the managed hook'"
printf '%s' "$chk" | grep -qi 'commit-msg TDD gate hook is not installed' && t9err="$t9err says-'not installed'-about-a-hook-that-IS-installed"
if [ -n "$t9err" ]; then
  fail_ "T9-hookspath-unmarked-hook-wording" "$t9err | $(printf '%s' "$chk" | grep -i 'commit-msg' | head -2 | tr '\n' ' ')"
else
  pass "T9-hookspath-unmarked-hook-wording (an unmarked hook in the hooksPath dir is reported as 'not the managed hook', not as absent)"
fi

# ── T6: fence-excision mutants — both guards are load-bearing ────────────────
echo "=== T6-fence-excision-mutants ==="

mutate() {  # mutate <marker-stem> <outfile>  -> 0 if the excision was real
  local stem="$1" out="$2" before after
  before=$(grep -c "$stem" "$REPO_ROOT/scripts/verify-install.sh") || before=0
  case "$before" in ''|*[!0-9]*) before=0 ;; esac
  sed "/# ${stem}-BEGIN/,/# ${stem}-END/d" "$REPO_ROOT/scripts/verify-install.sh" > "$out"
  after=$(grep -c "$stem" "$out") || after=0
  case "$after" in ''|*[!0-9]*) after=0 ;; esac
  [ "$before" -ge 2 ] && [ "$after" -eq 0 ]
}

MUT_SL="$TOPTMP/verify-install.symlink-mutant.sh"
if ! mutate "BL-145-SYMLINK-GUARD" "$MUT_SL"; then
  fail_ "T6a-symlink-guard-mutant" "excision vacuous — the BL-145-SYMLINK-GUARD fences did not bracket the guard"
elif ! bash -n "$MUT_SL"; then
  fail_ "T6a-symlink-guard-mutant" "mutant does not parse — the fence does not bracket a self-contained unit"
else
  P="$TOPTMP/p6a"; mk_proj "$P"
  SH6="$TOPTMP/dotfiles6/commit-msg"; mk_shared_hook "$SH6" exec
  ln -s "$SH6" "$P/.git/hooks/commit-msg"
  cp "$MUT_SL" "$P/scripts/verify-install.sh"; chmod +x "$P/scripts/verify-install.sh"
  run_autofix "$P" >/dev/null
  if ! cmp -s "$SH6" "$SH6.pristine"; then
    pass "T6a-symlink-guard-mutant (excised guard -> --auto-fix writes through the link again: the guard is load-bearing)"
  else
    fail_ "T6a-symlink-guard-mutant" "mutant still refused — the symlink protection does not (only) live in the fence"
  fi
fi

MUT_HP="$TOPTMP/verify-install.hookspath-mutant.sh"
if ! mutate "BL-145-HOOKSPATH" "$MUT_HP"; then
  fail_ "T6b-hookspath-mutant" "excision vacuous — the BL-145-HOOKSPATH fences did not bracket the guard"
elif ! bash -n "$MUT_HP"; then
  fail_ "T6b-hookspath-mutant" "mutant does not parse — the fence does not bracket a self-contained unit"
else
  P="$TOPTMP/p6b"; mk_proj "$P"
  emit_real_hooks "$P/.githooks" || true
  rm -f "$P/.git/hooks/pre-commit" "$P/.git/hooks/commit-msg"
  ( cd "$P" && git config core.hooksPath .githooks )
  cp "$MUT_HP" "$P/scripts/verify-install.sh"; chmod +x "$P/scripts/verify-install.sh"
  out=$(run_autofix "$P")
  if [ -e "$P/.git/hooks/pre-commit" ] && ! printf '%s' "$out" | grep -q 'core.hooksPath'; then
    pass "T6b-hookspath-mutant (excised guard -> the blind, inert .git/hooks repair returns: the guard is load-bearing)"
  else
    fail_ "T6b-hookspath-mutant" "mutant stayed hooksPath-aware (inert-write=$([ -e "$P/.git/hooks/pre-commit" ] && echo yes || echo no)) — the awareness does not (only) live in the fence"
  fi
fi

# T6c: the RELATIVE-ANCHOR atom (R-BL145-2). Deleting the single marked line
# that anchors a relative link value to the link's own directory survived the
# suite before this pin; now it must not.
MUT_AN="$TOPTMP/verify-install.anchor-mutant.sh"
an_before=$(grep -c 'BL-145-RELATIVE-ANCHOR' "$REPO_ROOT/scripts/verify-install.sh") || an_before=0
case "$an_before" in ''|*[!0-9]*) an_before=0 ;; esac
sed '/# BL-145-RELATIVE-ANCHOR/d' "$REPO_ROOT/scripts/verify-install.sh" > "$MUT_AN"
an_after=$(grep -c 'BL-145-RELATIVE-ANCHOR' "$MUT_AN") || an_after=0
case "$an_after" in ''|*[!0-9]*) an_after=0 ;; esac
if [ "$an_before" -lt 1 ] || [ "$an_after" -ne 0 ]; then
  fail_ "T6c-relative-anchor-atom" "excision vacuous — no '# BL-145-RELATIVE-ANCHOR' line to delete (before=$an_before after=$an_after); the anchoring atom is unpinned"
elif ! bash -n "$MUT_AN"; then
  fail_ "T6c-relative-anchor-atom" "mutant does not parse — the marker is not on a self-contained line"
else
  P="$TOPTMP/p6c"; mk_proj "$P"
  SH6C="$TOPTMP/dotfiles6c/commit-msg"; mk_shared_hook "$SH6C" exec
  REL6C="../../../dotfiles6c/commit-msg"
  ANCHORED6C=".git/hooks/$REL6C"
  ln -s "$REL6C" "$P/.git/hooks/commit-msg"
  cp "$MUT_AN" "$P/scripts/verify-install.sh"; chmod +x "$P/scripts/verify-install.sh"
  out=$(run_autofix "$P")
  if printf '%s' "$out" | grep -qF "$ANCHORED6C"; then
    fail_ "T6c-relative-anchor-atom" "the mutant still printed the anchored path — the anchoring does not (only) live on the marked line, so the atom is not pinned"
  elif ! printf '%s' "$out" | grep -qi 'symlink'; then
    fail_ "T6c-relative-anchor-atom" "mutant stopped refusing altogether — the deletion changed more than the anchoring"
  else
    pass "T6c-relative-anchor-atom (excised anchor -> the refusal degrades to the raw, unactionable link value: the atom is load-bearing)"
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
