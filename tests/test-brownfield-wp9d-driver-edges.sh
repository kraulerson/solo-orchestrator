#!/usr/bin/env bash
# tests/test-brownfield-wp9d-driver-edges.sh
#
# WP9d — the shipped adoption driver's edges, per ADOPT-002-ARCH v2.2 §10-WP9d.
# This file pins items (1), (2), (3) and (6): the step-0 placement refusals R1
# rules, the hooks directory resolved through git, the DERIVED "gates are live"
# sentence, and the preconditions. Items (4), (5) and (7) — the window, the
# labels, the rehearsal bound — are pinned in their own file.
#
# WHAT R1 RULES (Karl, 2026-09-17, §0.1a). Adoption REFUSES at step 0 — before
# any question and before any write — when git will not run the hook this driver
# installs, or when the hook would land somewhere this repository does not own:
#   * `core.hooksPath` is configured and does not resolve to the repository's
#     own hooks directory
#   * `--root` is not the repository top level (a linked worktree, a submodule,
#     a sub-directory of a repository)
#   * the resolved hooks path is a SYMLINK (extended 2026-09-17, after the
#     independent review measured the case no write test can catch)
# Author-proposed beside it: a REGULAR FILE at the resolved hooks path takes the
# same refusal (M16), and a hooksPath resolving to the repository's OWN hooks
# directory is IN SCOPE (M1, a narrowing of the ruling's "configured").
#
# WHY A SHAPE RULE AND NOT A STRONGER WRITE TEST (§13-V48). `.git/hooks` as a
# symlink to a writable directory outside the repository passes `-L`, `-d` AND
# `-w`; the write succeeds; and `git rev-parse --git-path hooks` reports the
# LINK's own path, so item (3)'s re-resolution follows the link, finds the hook
# it just wrote, and prints the live sentence TRUTHFULLY about a hook this
# repository does not own. Only asking "is this path a symlink" answers it —
# and the guard must ask it of the DIRECTORY, never of a leaf hook file, which
# is what `# BL-145-SYMLINK-GUARD-BEGIN`'s header records.
#
# NON-ROOT REQUIRED for the 555 case: as root every mode is writable and case
# W2 is vacuous. The suite says so rather than passing quietly.
#
# Hermetic: throwaway repositories under one temp dir, named branches, no
# remotes, no network. bash 3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRIVER="$REPO_ROOT/scripts/adopt-project.sh"

PASSED=0
FAILED=0
SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip_() { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

TOPTMP="$(mktemp -d)"
# chmod -R BEFORE rm: case W2 leaves a 555 directory, and the rehearsal copies
# it, so without this the cleanup cannot remove its own temp tree (§13-U(v2.2)).
trap 'chmod -R u+rwX "$TOPTMP" 2>/dev/null; rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }

AM_ROOT=0
[ "$(id -u)" -eq 0 ] && AM_ROOT=1

# ── fixtures ────────────────────────────────────────────────────────────────
# mk_adoptee — the wp9b shape: an ordinary repository with its own history.
mk_adoptee() {
  local p="$1"
  mkdir -p "$p/src" "$p/docs" || return 1
  ( cd "$p" \
      && git init -q --initial-branch=main . 2>/dev/null || git init -q . ) || return 1
  ( cd "$p" && git symbolic-ref HEAD refs/heads/main 2>/dev/null
    git -C "$p" config user.email "wp9d@test.invalid"
    git -C "$p" config user.name  "WP9d Test"
    git -C "$p" config core.excludesFile /dev/null ) >/dev/null 2>&1
  printf '{"name":"acme-api","scripts":{"test":"npm test"}}\n' > "$p/package.json"
  printf '# acme-api\n' > "$p/README.md"
  printf '# What this is for\n\nInvoice reconciliation for small firms.\n' > "$p/docs/product.md"
  printf '# Architecture\n\nA node service and a postgres database.\n' > "$p/docs/architecture.md"
  ( cd "$p" && git add -A && git commit -q -m "chore: their own history" ) >/dev/null 2>&1 || return 1
  return 0
}

TEMPLATE="$(newtmp)/template"
REPORT=""
if mk_adoptee "$TEMPLATE" \
   && bash "$REPO_ROOT/scripts/scout.sh" --root "$TEMPLATE" --out "$TOPTMP/scan" >/dev/null 2>&1 \
   && [ -s "$TOPTMP/scan/scout-report.json" ]; then
  REPORT="$TOPTMP/scan/scout-report.json"
else
  echo "  [FAIL] setup — scripts/scout.sh produced no report"
  echo ""
  echo "Results: 0 passed, 1 failed, 0 skipped"
  exit 1
fi

# _ans — the tier answer plus the four confirmations.
_ans() { local tier="${1:-1}"; printf '%s\n1\n1\n1\n1\n' "$tier"; }

RUN_RC=0; RUN_OUT=""; RUN_ERR=""
# run_adopt <cwd> <root-args...> — drives the shipped driver, capturing rc and output.
run_adopt() {
  local dir="$1"; shift
  local ansf="$TOPTMP/ans.$$.$RANDOM"
  _ans 1 > "$ansf"
  RUN_RC=0
  RUN_OUT="$TOPTMP/out.$$.$RANDOM"
  RUN_ERR="$TOPTMP/err.$$.$RANDOM"
  ( cd "$dir" && bash "$DRIVER" --scan-report "$REPORT" "$@" ) \
    < "$ansf" > "$RUN_OUT" 2> "$RUN_ERR" || RUN_RC=$?
  return 0
}

# asked_anything — did the run reach the FIRST question? A step-0 refusal has
# not. Anchored on the tier question's own text, which the driver holds in
# ADOPT_AUDIENCE_Q.
asked_anything() { grep -qF "Who is this project for?" "$RUN_OUT" 2>/dev/null; }
# wrote_anything — did anything land in the adoptee? Step 0 precedes every write.
wrote_anything() { [ -e "$1/.claude" ] || [ -e "$1/PROJECT_INTAKE.md" ] || [ -e "$1/APPROVAL_LOG.md" ]; }
committed() { [ "$(git -C "$1" rev-list --count HEAD 2>/dev/null || echo 0)" -gt 1 ]; }
says_live() { grep -qF "message gates are live" "$RUN_OUT" 2>/dev/null; }
# The gate's own marker, read from the emitter rather than transcribed.
SOIF_TDD_OPEN_PROBE="$( . "$REPO_ROOT/scripts/lib/hook-templates.sh" >/dev/null 2>&1; printf '%s' "${SOIF_TDD_OPEN:-SOIF BL-072 TDD gate (commit-msg)}" )"

# refused_at_step0 <label> <root> — the whole R1 shape in one assertion.
refused_at_step0() {
  local label="$1" root="$2" want="$3"
  local why=""
  [ "$RUN_RC" -ne 0 ] || why="$why rc=$RUN_RC(want non-zero)"
  ! asked_anything || why="$why asked-a-question"
  ! wrote_anything "$root" || why="$why wrote-into-the-adoptee"
  ! committed "$root" || why="$why made-a-commit"
  ! says_live || why="$why printed-the-live-sentence"
  if [ -n "$want" ] && ! grep -qiE "$want" "$RUN_OUT" "$RUN_ERR" 2>/dev/null; then
    why="$why message-does-not-name:/$want/"
  fi
  if [ -z "$why" ]; then
    pass "$label: refused at step 0 — no question asked, nothing written, no commit, no live sentence"
  else
    fail_ "$label" "$why | first line: $(grep -m1 -E '^\[(REFUSED|BLOCKED)\]' "$RUN_OUT" "$RUN_ERR" 2>/dev/null | head -1)"
  fi
}

echo "=== P — R1's placement refusals (item 1) ==="

# P1. --root at a sub-directory of a repository.
P1="$(newtmp)"; mk_adoptee "$P1" && mkdir -p "$P1/sub" && : > "$P1/sub/f.txt"
run_adopt "$P1/sub"
refused_at_step0 "P1 sub-directory root" "$P1/sub" "top level|toplevel|sub-directory|subdirectory"

# P2. A linked worktree.
P2="$(newtmp)"; mk_adoptee "$P2"

P2WT="$(newtmp)/wt"
( cd "$P2" && git worktree add -q "$P2WT" -b wt-branch ) >/dev/null 2>&1
if [ -e "$P2WT/.git" ]; then
  run_adopt "$P2WT"
  refused_at_step0 "P2 linked worktree" "$P2WT" "worktree|top level|toplevel|\.git is a file|gitfile"
else
  fail_ "P2 linked worktree" "could not create the worktree fixture"
fi

# P3. core.hooksPath configured elsewhere.
P3="$(newtmp)"; mk_adoptee "$P3"; P3HP="$(newtmp)/hp"; mkdir -p "$P3HP"
( cd "$P3" && git config core.hooksPath "$P3HP" )
run_adopt "$P3"
refused_at_step0 "P3 core.hooksPath elsewhere" "$P3" "hookspath"

# P4. POSITIVE CONTROL — hooksPath resolving to the repository's OWN hooks dir
# is IN SCOPE (M1, author-proposed narrowing). Without this case the refusal
# could be "any hooksPath at all" and P3 would not notice.
P4="$(newtmp)"; mk_adoptee "$P4"
( cd "$P4" && git config core.hooksPath "$P4/.git/hooks" )
run_adopt "$P4"
if [ "$RUN_RC" -eq 0 ] && committed "$P4" && [ -f "$P4/.git/hooks/commit-msg" ]; then
  pass "P4: a hooksPath resolving to the repository's OWN hooks directory ADOPTS — the narrowing is live, so P3 refuses a REDIRECTION and not the setting"
else
  fail_ "P4" "rc=$RUN_RC committed=$(committed "$P4" && echo 1 || echo 0) hook=$([ -f "$P4/.git/hooks/commit-msg" ] && echo 1 || echo 0)"
fi

echo "=== S — the hooks path's SHAPE (R1's symlink extension, ruled 2026-09-17; and M16) ==="

# S1. A symlink to a writable directory OUTSIDE the repository. The case no
# write test can catch: -L, -d and -w all pass and the write lands outside.
S1="$(newtmp)"; mk_adoptee "$S1"; S1OUT="$(newtmp)/shared"; mkdir -p "$S1OUT"
rm -rf "$S1/.git/hooks" && ln -s "$S1OUT" "$S1/.git/hooks"
run_adopt "$S1"
refused_at_step0 "S1 hooks dir is a symlink to an outside directory" "$S1" "symlink|symbolic link"
if [ -z "$(ls -A "$S1OUT" 2>/dev/null)" ]; then
  pass "S1b: the outside directory is UNTOUCHED — nothing of this repository's was written where it does not belong"
else
  fail_ "S1b" "the outside directory holds: $(ls -A "$S1OUT" | tr '\n' ' ')"
fi

# S2. A DANGLING symlink. Today this takes the parent arm of the write test and
# fails at mkdir AFTER the adoption commit.
S2="$(newtmp)"; mk_adoptee "$S2"
rm -rf "$S2/.git/hooks" && ln -s /nonexistent/wp9d-target "$S2/.git/hooks"
run_adopt "$S2"
refused_at_step0 "S2 hooks dir is a dangling symlink" "$S2" "symlink|symbolic link"

# S3. A REGULAR FILE at the hooks path (M16, author-proposed).
S3="$(newtmp)"; mk_adoptee "$S3"
rm -rf "$S3/.git/hooks" && printf 'not a directory\n' > "$S3/.git/hooks"
run_adopt "$S3"
refused_at_step0 "S3 hooks path is a regular file" "$S3" "not a directory|regular file|directory"

# S4. THE GUARD TESTS THE DIRECTORY, NOT A LEAF. A repository whose
# .git/hooks/commit-msg is itself a symlink (common: a shared hook file) is
# ORDINARY — the directory is real and this repository owns it. If the guard
# were written as `-L "$hooks/commit-msg"` this case would be wrongly refused,
# which is the mistake `# BL-145-SYMLINK-GUARD-BEGIN`'s header records.
S4="$(newtmp)"; mk_adoptee "$S4"; S4SRC="$(newtmp)/shared-hook"
printf '#!/usr/bin/env bash\nexit 0\n' > "$S4SRC"; chmod +x "$S4SRC"
mkdir -p "$S4/.git/hooks" && ln -s "$S4SRC" "$S4/.git/hooks/commit-msg"
run_adopt "$S4"
if [ "$RUN_RC" -eq 0 ] && committed "$S4"; then
  pass "S4: a symlinked LEAF hook does not trip the guard — the DIRECTORY is what the shape rule asks about"
else
  fail_ "S4" "rc=$RUN_RC committed=$(committed "$S4" && echo 1 || echo 0) — a leaf-level -L test would refuse this ordinary repository"
fi

# S5. THE COMPOSITION. `core.hooksPath` pointed at an outside directory AND
# `.git/hooks` symlinked to that same directory. Each rule alone stands aside:
# the same-directory exception (M1) sees the two physical paths MATCH — because
# the repository's own hooks path is the link — and `--git-path hooks` reports
# the hooksPath value, a real directory, so the shape rule finds no link either.
# Measured before the fix: rc 0, no refusal, and the hook in the outside
# directory. R1's extension defeated by composition with R1's own narrowing.
S5="$(newtmp)"; mk_adoptee "$S5"; S5OUT="$(newtmp)/shared"; mkdir -p "$S5OUT"
rm -rf "$S5/.git/hooks" && ln -s "$S5OUT" "$S5/.git/hooks"
( cd "$S5" && git config core.hooksPath "$S5OUT" )
run_adopt "$S5"
refused_at_step0 "S5 hooksPath and the hooks directory both pointing outside" "$S5" "symlink|symbolic link|hookspath"
if [ -z "$(ls -A "$S5OUT" 2>/dev/null)" ]; then
  pass "S5b: the outside directory is UNTOUCHED — the narrowing cannot be used to launder a link out of the repository"
else
  fail_ "S5b" "the outside directory holds: $(ls -A "$S5OUT" | tr '\n' ' ')"
fi

echo "=== W — the write test (item 6): a CONDITIONAL, never a disjunction ==="

# W1. POSITIVE CONTROL — a repository whose git template carried no hooks/, so
# .git/hooks does not exist. The parent is writable and adoption creates the
# directory as it always has. A bare `[ -w ]` on the absent directory refuses
# here, which is the false refusal this case exists to prevent.
W1="$(newtmp)"; EMPTYT="$(newtmp)/empty-template"; mkdir -p "$EMPTYT/info"
W1P="$W1/p"; mkdir -p "$W1P"
( cd "$W1P" && GIT_TEMPLATE_DIR="$EMPTYT" git init -q --initial-branch=main . 2>/dev/null \
    || GIT_TEMPLATE_DIR="$EMPTYT" git init -q . ) >/dev/null 2>&1
( git -C "$W1P" config user.email "wp9d@test.invalid"
  git -C "$W1P" config user.name "WP9d Test"
  git -C "$W1P" config core.excludesFile /dev/null ) >/dev/null 2>&1
printf '{"name":"acme-api","scripts":{"test":"npm test"}}\n' > "$W1P/package.json"
printf '# acme-api\n' > "$W1P/README.md"
mkdir -p "$W1P/docs" && printf '# What this is for\n\nInvoices.\n' > "$W1P/docs/product.md"
( cd "$W1P" && git add -A && git commit -q -m "chore: their own history" ) >/dev/null 2>&1
if [ -d "$W1P/.git/hooks" ]; then
  skip_ "W1 no-hooks-directory control" "this git created .git/hooks despite an empty template — the condition cannot be built here"
else
  run_adopt "$W1P"
  if [ "$RUN_RC" -eq 0 ] && committed "$W1P" && [ -f "$W1P/.git/hooks/commit-msg" ]; then
    pass "W1: a repository with NO .git/hooks adopts and the directory is created — the write test's parent arm is live, and a bare [ -w ] on the absent directory would have refused every such machine"
  else
    fail_ "W1" "rc=$RUN_RC committed=$(committed "$W1P" && echo 1 || echo 0) hook=$([ -f "$W1P/.git/hooks/commit-msg" ] && echo 1 || echo 0)"
  fi
fi

# W2. An EXISTING .git/hooks at mode 555 → refused at step 0, before the commit.
if [ "$AM_ROOT" -eq 1 ]; then
  skip_ "W2 unwritable hooks directory" "running as root — every mode is writable and this case cannot discriminate"
else
  W2="$(newtmp)"; mk_adoptee "$W2"; chmod 555 "$W2/.git/hooks"
  run_adopt "$W2"
  refused_at_step0 "W2 unwritable hooks directory" "$W2" "writ"
  chmod 755 "$W2/.git/hooks" 2>/dev/null
fi

echo "=== I — the identity precondition (item 6) ==="

# I1. No git identity git can resolve. Today this surfaces AFTER the stamp, as
# the adoption window; the oracle is the one `git commit` itself consults.
I1="$(newtmp)"; mk_adoptee "$I1"
( git -C "$I1" config --unset user.email; git -C "$I1" config --unset user.name ) >/dev/null 2>&1
I1ANS="$TOPTMP/i1ans"; _ans 1 > "$I1ANS"
RUN_RC=0; RUN_OUT="$TOPTMP/i1out"; RUN_ERR="$TOPTMP/i1err"
# CLAUDE.md's recipe for forcing a git-config condition: unsetting the LOCAL
# identity is not enough — measured, `git var GIT_COMMITTER_IDENT` still resolves
# from ~/.gitconfig, and useConfigOnly only stops the gecos guess.
( cd "$I1" && GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.useConfigOnly GIT_CONFIG_VALUE_0=true \
    bash "$DRIVER" --scan-report "$REPORT" ) < "$I1ANS" > "$RUN_OUT" 2> "$RUN_ERR" || RUN_RC=$?
i1_stamped=0
grep -q '"adopted"[[:space:]]*:[[:space:]]*true' "$I1/.claude/manifest.json" 2>/dev/null && i1_stamped=1
if [ "$RUN_RC" -ne 0 ] && ! asked_anything && ! wrote_anything "$I1" && [ "$i1_stamped" -eq 0 ]; then
  pass "I1: no resolvable git identity is refused at step 0 — nothing written and no stamp, where today the failure surfaces after the stamp as the window"
else
  fail_ "I1" "rc=$RUN_RC asked=$(asked_anything && echo 1 || echo 0) wrote=$(wrote_anything "$I1" && echo 1 || echo 0) stamped=$i1_stamped"
fi

echo "=== H — the hooks directory resolved through git (item 2), and the derived sentence (item 3) ==="

# H1. One spelling, used by the installer AND the archive's git-hook class (I21).
H1=0
grep -q '_adopt_hooks_dir' "$REPO_ROOT/scripts/lib/adopt/adopt-state.sh" 2>/dev/null && H1=1
# EXECUTED lines only — the comments above these functions name the literal
# path in order to explain why it is wrong, which is not a second spelling.
h1_literal=$(cat "$REPO_ROOT/scripts/lib/adopt/adopt-state.sh" "$REPO_ROOT/scripts/lib/adopt/adopt-archive.sh" 2>/dev/null | sed 's/[[:space:]]*#.*//' | grep -c 'root/\.git/hooks')
if [ "$H1" -eq 1 ] && [ "$h1_literal" -eq 0 ]; then
  pass "H1: the hooks directory is resolved once through git (_adopt_hooks_dir) and no literal \$root/.git/hooks survives in the installer or the archive"
else
  fail_ "H1" "_adopt_hooks_dir present=$H1 literal-\$root/.git/hooks sites=$h1_literal (want 0) — I21 requires ONE resolution shared by the installer and the archive's git-hook class"
fi

# H2. The live sentence is DERIVED: with the hook write faulted, the run must
# NOT print it, and must end as a block saying the commit HAD landed.
H2="$(newtmp)"; mk_adoptee "$H2"
H2ANS="$TOPTMP/h2ans"; _ans 1 > "$H2ANS"
RUN_RC=0; RUN_OUT="$TOPTMP/h2out"; RUN_ERR="$TOPTMP/h2err"
( cd "$H2" && SOIF_ADOPT_FAIL_HOOK_WRITE=1 bash "$DRIVER" --scan-report "$REPORT" ) \
  < "$H2ANS" > "$RUN_OUT" 2> "$RUN_ERR" || RUN_RC=$?
h2_hook=0; [ -f "$H2/.git/hooks/commit-msg" ] && h2_hook=1
if [ "$RUN_RC" -ne 0 ] && committed "$H2" && [ "$h2_hook" -eq 0 ] && ! says_live \
   && grep -qE '^\[BLOCKED\]' "$RUN_OUT" "$RUN_ERR" 2>/dev/null; then
  pass "H2: with the hook write faulted the live sentence is ABSENT and the run ends [BLOCKED] — the sentence is derived from the hook that is there, not from having tried"
else
  fail_ "H2" "rc=$RUN_RC committed=$(committed "$H2" && echo 1 || echo 0) hook=$h2_hook says_live=$(says_live && echo 1 || echo 0) blocked=$(grep -cE '^\[BLOCKED\]' "$RUN_OUT" "$RUN_ERR" 2>/dev/null | awk -F: '{s+=$1} END{print s+0}')"
fi

# H3. POSITIVE CONTROL — the ordinary fixture still adopts, installs the hook,
# and prints the sentence. Without this H2 could pass against a driver that
# never prints it at all.
H3="$(newtmp)"; mk_adoptee "$H3"
run_adopt "$H3"
if [ "$RUN_RC" -eq 0 ] && committed "$H3" && [ -f "$H3/.git/hooks/commit-msg" ] && says_live; then
  pass "H3: the ordinary fixture adopts, the hook is installed, and the live sentence IS printed"
else
  fail_ "H3" "rc=$RUN_RC committed=$(committed "$H3" && echo 1 || echo 0) hook=$([ -f "$H3/.git/hooks/commit-msg" ] && echo 1 || echo 0) says_live=$(says_live && echo 1 || echo 0)"
fi

# H4. THE SENTENCE IS DERIVED, NOT EARNED BY THE INSTALLER RETURNING 0. H2's
# fault seam aborts the installer, so the handoff is never reached and H2 would
# pass against a driver that prints the sentence unconditionally. This case
# lets the install SUCCEED and takes the hook away underneath it: the receipt
# must then be withheld and the run must block.
H4="$(newtmp)"; mk_adoptee "$H4"
H4ANS="$TOPTMP/h4ans"; _ans 1 > "$H4ANS"
RUN_RC=0; RUN_OUT="$TOPTMP/h4out"; RUN_ERR="$TOPTMP/h4err"
( cd "$H4" && SOIF_ADOPT_HOOK_VANISH=1 bash "$DRIVER" --scan-report "$REPORT" ) \
  < "$H4ANS" > "$RUN_OUT" 2> "$RUN_ERR" || RUN_RC=$?
if [ "$RUN_RC" -ne 0 ] && committed "$H4" && ! says_live \
   && grep -qE 'NOT installed where git will look' "$RUN_OUT" "$RUN_ERR" 2>/dev/null; then
  pass "H4: when the gate is not where git looks, the live sentence is WITHHELD and the run blocks naming the directory — the receipt is derived from the hook, not from the installer's exit code"
else
  fail_ "H4" "rc=$RUN_RC committed=$(committed "$H4" && echo 1 || echo 0) says_live=$(says_live && echo 1 || echo 0) named=$(grep -c 'NOT installed where git will look' "$RUN_OUT" "$RUN_ERR" 2>/dev/null | awk -F: '{s+=$1} END{print s+0}')"
fi

# H5/H6 — THE OTHER TWO CONJUNCTS OF THE LIVE DERIVATION.
# `_adopt_hooks_live` asserts three facts and its own header says each is
# necessary. Before these cases only the first had a fixture: H2 removes the
# file (so `[ -f ]` already fails), H3 is all-true, and H4's seam short-circuits
# AFTER all three. An independent review deleted the `-x` conjunct and then the
# marker conjunct, one at a time, and both suites stayed green — two thirds of
# the check was decorative. Neither state has a natural route (the owner's own
# `chmod +x` succeeds; the marker is appended whenever absent), so the installer
# produces them through a named seam and the derivation observes them for real.
H5="$(newtmp)"; mk_adoptee "$H5"
H5ANS="$TOPTMP/h5ans"; _ans 1 > "$H5ANS"
RUN_RC=0; RUN_OUT="$TOPTMP/h5out"; RUN_ERR="$TOPTMP/h5err"
( cd "$H5" && SOIF_ADOPT_HOOK_FAULT=noexec bash "$DRIVER" --scan-report "$REPORT" ) \
  < "$H5ANS" > "$RUN_OUT" 2> "$RUN_ERR" || RUN_RC=$?
h5_present=0; [ -f "$H5/.git/hooks/commit-msg" ] && h5_present=1
h5_exec=0; [ -x "$H5/.git/hooks/commit-msg" ] && h5_exec=1
if [ "$RUN_RC" -ne 0 ] && [ "$h5_present" -eq 1 ] && [ "$h5_exec" -eq 0 ] && ! says_live \
   && grep -q 'NOT installed where git will look' "$RUN_OUT" "$RUN_ERR" 2>/dev/null; then
  pass "H5: a commit-msg that EXISTS and carries the marker but is NOT EXECUTABLE withholds the live sentence — git would not run it, and the receipt says so"
else
  fail_ "H5" "rc=$RUN_RC hook-present=$h5_present (want 1) executable=$h5_exec (want 0) says_live=$(says_live && echo 1 || echo 0) withheld=$(grep -c 'NOT installed where git will look' "$RUN_OUT" "$RUN_ERR" 2>/dev/null | awk -F: '{s+=$1} END{print s+0}')"
fi

H6="$(newtmp)"; mk_adoptee "$H6"
H6ANS="$TOPTMP/h6ans"; _ans 1 > "$H6ANS"
RUN_RC=0; RUN_OUT="$TOPTMP/h6out"; RUN_ERR="$TOPTMP/h6err"
( cd "$H6" && SOIF_ADOPT_HOOK_FAULT=nomark bash "$DRIVER" --scan-report "$REPORT" ) \
  < "$H6ANS" > "$RUN_OUT" 2> "$RUN_ERR" || RUN_RC=$?
h6_present=0; [ -x "$H6/.git/hooks/commit-msg" ] && h6_present=1
h6_marked=0; grep -qF "$SOIF_TDD_OPEN_PROBE" "$H6/.git/hooks/commit-msg" 2>/dev/null && h6_marked=1
if [ "$RUN_RC" -ne 0 ] && [ "$h6_present" -eq 1 ] && [ "$h6_marked" -eq 0 ] && ! says_live \
   && grep -q 'NOT installed where git will look' "$RUN_OUT" "$RUN_ERR" 2>/dev/null; then
  pass "H6: an executable commit-msg with NO gate in it withholds the live sentence — the receipt is about the gate being there, not about a file being there"
else
  fail_ "H6" "rc=$RUN_RC hook-executable=$h6_present (want 1) carries-marker=$h6_marked (want 0) says_live=$(says_live && echo 1 || echo 0) withheld=$(grep -c 'NOT installed where git will look' "$RUN_OUT" "$RUN_ERR" 2>/dev/null | awk -F: '{s+=$1} END{print s+0}')"
fi

# H7 — THE LABEL'S OTHER DIRECTION. §10-WP9d item (5) requires both: the window
# arm is a BLOCK (a check ran) and arm 1's generic already-adopted refusal is a
# REFUSAL (the tool would not begin, and nothing of this run is on disk). With
# only one direction pinned, collapsing the two primitives into one would pass.
H7="$(newtmp)"; mk_adoptee "$H7"
run_adopt "$H7"                       # a complete, landed adoption
if [ "$RUN_RC" -eq 0 ]; then
  run_adopt "$H7"                     # and now a second run
  if [ "$RUN_RC" -ne 0 ] \
     && grep -q '^\[REFUSED\]' "$RUN_OUT" "$RUN_ERR" 2>/dev/null \
     && ! grep -q '^\[BLOCKED\]' "$RUN_OUT" "$RUN_ERR" 2>/dev/null \
     && grep -q 'already been adopted' "$RUN_OUT" "$RUN_ERR" 2>/dev/null; then
    pass "H7: re-running a LANDED adoption is [REFUSED], not [BLOCKED] — the other direction of the label, so the two primitives cannot be collapsed into one"
  else
    fail_ "H7" "rc=$RUN_RC refused=$(grep -c '^\[REFUSED\]' "$RUN_OUT" "$RUN_ERR" 2>/dev/null | awk -F: '{s+=$1} END{print s+0}') blocked=$(grep -c '^\[BLOCKED\]' "$RUN_OUT" "$RUN_ERR" 2>/dev/null | awk -F: '{s+=$1} END{print s+0}')"
  fi
else
  fail_ "H7 setup" "the first adoption did not land (rc=$RUN_RC)"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
