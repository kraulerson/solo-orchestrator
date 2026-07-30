#!/usr/bin/env bash
# tests/test-bl199-quickstart-from-clone.sh — BL-199 closer.
#
# THE DEFECT
#   README § Quick Start told the operator to `git clone`, `cd solo-orchestrator`
#   and run `./init.sh`. init.sh's early block called
#   guard_not_in_framework "$_early_target", whose FIRST arm is an
#   UNCONDITIONAL cwd check — so from inside the clone init.sh refused before
#   any prompt, even with --project-dir pointing at a benign external path
#   (measured rc=1). The only invocation that worked from the clone was
#   --dry-run. No test ever executed the README's literal sequence:
#   tests/edge-cases-pre-init.sh E8b hit the same wall and the BL-041 fix
#   reordered preflight-before-guard to get the TEST past it (see the BL-041
#   comment block in init.sh and preflight_target_writable's docstring in
#   scripts/lib/helpers-core.sh) without ever questioning the user path.
#
# THE CONTRACT (Karl, 2026-07-29) — what this suite pins
#   1. Running init.sh FROM INSIDE the clone is the SUPPORTED flow.
#   2. It must still FAIL when the operation would write ONTO the framework
#      itself: target == framework root, target INSIDE the framework tree, or
#      target is another framework clone (signature match).
#   3. `./init.sh --project-dir <bare-name>` creates the project ONE LEVEL UP
#      from the framework clone. The anchor is the PARENT OF THE DIRECTORY
#      CONTAINING init.sh (SCRIPT_DIR/..), NOT the cwd. Absolute paths pass
#      through unchanged.
#   4. README Quick Start documents that activation.
#
# Implementation markers under test:
#   # BL-199-SIBLING-RESOLVE  (soif_resolve_target_dir, helpers-core.sh)
#   # BL-199-TARGET-GUARD     (guard_target_not_in_framework, helpers-core.sh)
#   # BL-199-SIBLING-ANCHOR   (soif_sibling_anchor, init.sh)
#
# Test matrix — each case asserts on rc AND output AND filesystem.
#   T1  README-literal: cd clone && ./init.sh --project-dir testproject
#       → rc=0, scaffold at $TMP/testproject (SIBLING of the clone), and
#       NOT at $TMP/clone/testproject.                    [RED before the fix]
#   T2  anchor-is-script-not-cwd: cwd is a THIRD directory ($TMP/elsewhere),
#       init invoked by full path → scaffold lands beside the CLONE
#       ($TMP/tp2), not beside the cwd.                   [RED before the fix]
#       NOTE — deliberate strengthening of the brief's T2. The brief said
#       `cd "$TMP"` + `"$TMP/clone/init.sh"`, but $TMP is BOTH the cwd and
#       SCRIPT_DIR/.., so that invocation cannot distinguish the two anchors
#       and mutation M1 (anchor := cwd) would survive it. Running from
#       $TMP/elsewhere makes the two anchors differ, which is the only way
#       M1 can be a real proof.
#   T3  inside-target refused: --project-dir "$TMP/clone/sub" → rc!=0, refusal
#       names the framework, and $TMP/clone/sub does NOT exist (the guard
#       fired before mkdir).                              [RED before the fix:
#       today the cwd is $TMP so the cwd arm passes, and the target-signature
#       arm does not look at subdirectories — init scaffolds INSIDE the clone]
#   T4  target-is-THIS-clone's-root refused. NOTE: this shape is satisfied by
#       arms (a) and (b) jointly and cannot isolate either — it is a
#       back-compat pin, not an arm pin. T7 and T8 below are the isolating
#       shapes. [GREEN before the fix]
#   T5  absolute external target from the clone cwd → rc=0, created at the
#       absolute path.                                    [RED before the fix]
#   T6  no-contamination: `find "$TMP/clone" | sort` is byte-identical before
#       and after T1.
#
# Added 2026-07-29 after adversarial review of fe2d045 (findings R-199-1,
# R-199-2, R-199-7):
#   T7  ARM (b) ISOLATION — target IS the framework root, against a fixture
#       framework whose templates/generated is deliberately ABSENT so the
#       signature arm (a) cannot see it. Arm (c) starts at the target's PARENT
#       and so never matches the target itself. Only arm (b) can refuse this.
#   T8  ARM (a) ISOLATION — the real security-audits-1 S3 vector: --project-dir
#       pointing at a SECOND, DIFFERENT framework clone, from a benign cwd.
#       Neither (b) nor (c) can see it. Before this test, init.sh's S3 coverage
#       was zero: test-platform-security-bugs-closer.sh::T3a still exercises the
#       OLD guard_not_in_framework, which init.sh no longer calls.
#   T9  CASE-VARIANT target (R-199-1, the blocker). On a case-INSENSITIVE
#       filesystem `$TMP/CLONE/injected` names the same directory as
#       `$TMP/clone/injected`, but every byte-wise string comparison misses it.
#       Measured pre-fix: rc=0, 400 files scaffolded inside the framework.
#       SKIPPED on case-sensitive filesystems, where those really are two
#       different directories and refusing would be wrong.
#   T10 SYMLINKED target — `ln -s "$CLONE" "$TMP/lnk"`, target "$TMP/lnk/sub".
#   T11 OVER-REFUSAL GUARD — a genuine sibling whose name has the framework's
#       as a PREFIX (`clone-2`) must still be ALLOWED. Pins that nobody "fixes"
#       the prefix match by dropping the "/" separator.
#   M1  mutation — anchor := cwd instead of SCRIPT_DIR/.. → T2 must fail.
#   M2  mutation — drop the inside-framework arm of
#       guard_target_not_in_framework → T3 must fail.
#   M3  mutation — disable the signature arm (a) → T8 must fail. (This is the
#       reviewer's MX4, run in-suite.)
#   M4  mutation — disable the identity walk's comparison → T9 must fail, which
#       is what proves dev+inode identity is doing work no string can do.
#   M5  mutation — remove BOTH `pwd -P` resolutions → T10 must fail (R-199-7:
#       physicalization was load-bearing but unpinned).
#   M6  mutation — remove arm (b) entirely → T7 must fail. (The reviewer's MX5,
#       which SURVIVED 8/8 against fe2d045 for want of an isolating shape.)
#
# Added 2026-07-29 after round-2 review (finding R2-1):
#   T12 ESCAPE SYMLINK — a symlink that lives INSIDE the framework and points
#       OUTSIDE it (`ln -s "$TMP/outside" "$CLONE/escape"`), target
#       "$CLONE/escape/proj". REFUSED, deliberately — see the DECISION block in
#       guard_target_not_in_framework. Physically nothing would be written into
#       the framework, so this is a real judgement call, not an obvious one:
#       the contract is stated over the path the OPERATOR SUPPLIES, and letting
#       framework CONTENTS (which symlinks happen to exist) decide whether a
#       target is accepted would be unpredictable.
#   M7  mutation — remove the as-given comparison in arm (c) → T12 must fail.
#
# WHAT IS *NOT* PINNED, stated rather than papered over — and corrected in
# round 2. THREE of the four string comparisons in arms (b) and (c) are strict
# subsets of the identity check beside them: deleting one alone changes no
# behaviour and no test goes red. Same for `_bl199_physical_path`'s `pwd -P`
# while `_bl199_dir_id` does its own resolution, which is why M5 must remove
# both to turn T10 red. That much is deliberate over-determination on the cheap
# path.
#
# The FOURTH atom is NOT a subset, and round-1's blanket claim that it was is
# FALSE. `_bl199_path_is_inside "$abs_target" "$fw_root"` uniquely catches the
# T12 escape-symlink shape — identity and the physicalized string both say
# "outside", because the bytes really do land elsewhere. Measured: removing it
# flips "$FW/escape/proj" from REFUSE to allow. T12 + M7 now pin it.
#
# The reviewer's MX5 ("arm (b)'s string equality removed") still SURVIVES by
# design; the behaviour it guards is pinned by T7 against the whole arm.
#
# Hermetic: builds its own framework clone by tarring the repo (minus .git,
# .claude/worktrees, node_modules) into a mktemp workdir. No network, no
# remote creation (--no-remote-creation on every invocation), no writes
# outside the workdir. Mutations are applied to the FIXTURE CLONE, never to
# the repo's own source.
#
# Self-verify (must exit 0 after the fix):
#   bash tests/test-bl199-quickstart-from-clone.sh
set -uo pipefail

SUITE_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SUITE_DIR/.." && pwd)"

PASSED=0
FAILED=0
SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
# R2-3: skips must be COUNTED, not just printed. run_child_suite in the
# aggregator captures a child's output only when the child FAILS, so on a
# case-sensitive filesystem the two skipped cases (T9, M4) would otherwise
# leave no trace at all in a green run — two cases silently not executed.
# Putting the count in the tally line puts it in the captured log and in
# anything that ever parses these lines. (BL-197's class, in miniature.)
skip_() { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

# House rule: hermetic fixtures configure their own git identity and drop
# GITHUB_BASE_REF so fixture git ops don't inherit a PR context.
export GIT_AUTHOR_NAME="BL199 Fixture"
export GIT_AUTHOR_EMAIL="bl199@example.invalid"
export GIT_COMMITTER_NAME="BL199 Fixture"
export GIT_COMMITTER_EMAIL="bl199@example.invalid"
unset GITHUB_BASE_REF 2>/dev/null || true

TMP="$(mktemp -d)"
CLONE="$TMP/clone"
cleanup() {
  chmod -R u+w "$TMP" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

echo "== tests/test-bl199-quickstart-from-clone.sh =="
echo "  workdir: $TMP"

# --- Fixture: a framework clone that is NOT the repo under test -----------
# init.sh needs its whole templates/scripts/docs tree beside it, so copy the
# working tree (not `git archive` — the fix under test is uncommitted while
# this suite is being developed). .git is excluded so the fixture is not a
# git checkout; init.sh handles that (it skips the soloFrameworkCommit birth
# stamp with a printed note).
build_clone() {
  mkdir -p "$CLONE" || return 1
  ( cd "$REPO_ROOT" && tar \
      --exclude='./.git' --exclude='./.git/*' \
      --exclude='./.claude/worktrees' --exclude='./.claude/worktrees/*' \
      --exclude='./node_modules' --exclude='./node_modules/*' \
      -cf - . ) | ( cd "$CLONE" && tar -xf - )
}

if ! build_clone; then
  echo "  [FAIL] fixture — could not build the framework clone under $TMP"
  echo ""
  echo "== Total: 1 | Passed: 0 | Failed: 1 =="
  exit 1
fi

# Sanity: the fixture must actually look like a framework clone, otherwise
# every refusal assertion below would pass for the wrong reason.
if [ ! -x "$CLONE/init.sh" ] || [ ! -d "$CLONE/templates/generated" ] \
   || ! grep -q "Solo Orchestrator — Project Initialization Script" "$CLONE/init.sh"; then
  echo "  [FAIL] fixture — $CLONE does not carry the framework signature"
  echo ""
  echo "== Total: 1 | Passed: 0 | Failed: 1 =="
  exit 1
fi

# --- Shared helpers -------------------------------------------------------
# The working non-interactive flag recipe, cribbed from
# tests/edge-cases-pre-init.sh E8b.
RC=0
OUT=""
run_init() {
  # run_init <cwd> <init-command> <project-name> [extra args...]
  local cwd="$1"; shift
  local initcmd="$1"; shift
  local proj="$1"; shift
  RC=0
  OUT="$( cd "$cwd" && "$initcmd" --non-interactive \
            --project "$proj" \
            --platform web \
            --deployment personal \
            --language typescript \
            --git-host github \
            --visibility private \
            --no-remote-creation "$@" 2>&1 )" || RC=$?
}

scaffold_ok() { [ -f "$1/CLAUDE.md" ] && [ -d "$1/.claude" ]; }

REFUSAL_RE='Refusing to operate'
# Unique to the BL-199 target guard — the old cwd guard cannot print this, and
# neither can the non-interactive "already exists" check. T7/T8 need it because
# their targets EXIST, so a guard that failed to fire would still exit non-zero
# via the existence check and a bare rc!=0 assertion would pass vacuously.
GUARD_RE='Refusing to operate on the Solo Orchestrator framework itself'
EXISTS_RE='project directory already exists'

# --- Auxiliary fixtures for the arm-isolating shapes ----------------------
# other-fw: a SECOND framework clone. Minimal but signature-complete —
#   _soif_dir_is_framework needs init.sh carrying the header string plus a
#   templates/generated directory, nothing else.
# nosig:   a FULL copy of the clone with templates/generated removed — the one
#   difference that makes _soif_dir_is_framework return false for it. That is
#   what isolates arm (b). It has to be a full copy, not a minimal stub: with
#   only init.sh + scripts/lib the run dies at `invalid --platform 'web'`
#   (no docs/platform-modules/) long before the existence check, so the M6
#   mutant would exit non-zero for an unrelated reason and the proof would be
#   measuring the wrong thing.
# clone-2: a genuine sibling whose name has the clone's as a prefix.
# lnk:     a symlink to the clone.
build_aux_fixtures() {
  mkdir -p "$TMP/other-fw/templates/generated" || return 1
  cp "$CLONE/init.sh" "$TMP/other-fw/init.sh" || return 1

  cp -R "$CLONE" "$TMP/nosig" || return 1
  rm -rf "$TMP/nosig/templates/generated" || return 1
  chmod +x "$TMP/nosig/init.sh" || return 1
  # The fixture is only meaningful if the signature probe really does miss it.
  [ ! -d "$TMP/nosig/templates/generated" ] || return 1
  [ -f "$TMP/nosig/init.sh" ] || return 1

  mkdir -p "$TMP/clone-2" || return 1
  ln -s "$CLONE" "$TMP/lnk" || return 1

  # escape: a symlink that lives INSIDE the framework and points OUTSIDE it.
  # Created HERE, before T6's pre-image `find`, so it is present in both
  # snapshots and cannot show up as contamination. `find` does not follow
  # symlinks without -L, so it lists the link and never descends.
  mkdir -p "$TMP/outside" || return 1
  ln -s "$TMP/outside" "$CLONE/escape" || return 1
}

if ! build_aux_fixtures; then
  echo "  [FAIL] fixture — could not build the auxiliary fixtures under $TMP"
  echo ""
  echo "== Total: 1 | Passed: 0 | Failed: 1 =="
  exit 1
fi

# Is the workdir's filesystem case-insensitive? Decides whether T9 and M4 are
# meaningful here (macOS APFS default: yes; Linux ext4: no).
#
# SOIF_BL199_ASSUME_CASE_SENSITIVE=1 forces the case-SENSITIVE branch on any
# host. It exists so the skip path can be exercised and its tally verified from
# a macOS box, where the alternative is "trust that the Linux branch works".
# It does NOT simulate a case-sensitive filesystem — it only takes the branch,
# which is what the SKIP accounting depends on. Never set it in CI.
mkdir -p "$TMP/.casetest"
if [ -n "${SOIF_BL199_ASSUME_CASE_SENSITIVE:-}" ]; then
  FS_CASE_INSENSITIVE=no
  echo "  note: SOIF_BL199_ASSUME_CASE_SENSITIVE set — taking the case-SENSITIVE branch by request"
elif [ -d "$TMP/.CASETEST" ]; then
  FS_CASE_INSENSITIVE=yes
else
  FS_CASE_INSENSITIVE=no
fi
rmdir "$TMP/.casetest" 2>/dev/null || true

# --- T6 pre-image (captured before T1 runs) -------------------------------
find "$CLONE" | sort > "$TMP/clone-before.txt"

# --- T1: the README's literal sequence ------------------------------------
t1_readme_literal() {
  # `cd solo-orchestrator && ./init.sh --project-dir testproject` — the exact
  # shape README § Quick Start now documents.
  RC=0
  OUT="$( cd "$CLONE" && ./init.sh --non-interactive \
            --project testproject \
            --platform web \
            --deployment personal \
            --language typescript \
            --git-host github \
            --visibility private \
            --project-dir testproject \
            --no-remote-creation 2>&1 )" || RC=$?

  if [ "$RC" -ne 0 ]; then
    fail_ "T1" "README-literal run from inside the clone should succeed; got rc=$RC; tail: $(echo "$OUT" | tail -8)"
    return
  fi
  if echo "$OUT" | grep -q "$REFUSAL_RE"; then
    fail_ "T1" "framework refusal fired on the supported flow; tail: $(echo "$OUT" | tail -8)"
    return
  fi
  if [ -e "$CLONE/testproject" ]; then
    fail_ "T1" "project was created INSIDE the clone at $CLONE/testproject (must be a sibling)"
    return
  fi
  if ! scaffold_ok "$TMP/testproject"; then
    fail_ "T1" "no scaffold at the sibling path $TMP/testproject (CLAUDE.md + .claude/ expected); ls: $(ls -a "$TMP" 2>/dev/null | tr '\n' ' ')"
    return
  fi
  # NB: keep a literal init.sh invocation OUT of this string —
  # scripts/lint-no-live-remote-in-tests.sh scans executed lines and reads one
  # in a message as a real (non-hermetic) run.
  pass "T1: README-literal run from inside the clone scaffolds the SIBLING $TMP/testproject"
}

# --- T6: the clone is byte-identical after T1 -----------------------------
t6_no_contamination() {
  find "$CLONE" | sort > "$TMP/clone-after.txt"
  if ! diff -u "$TMP/clone-before.txt" "$TMP/clone-after.txt" > "$TMP/clone-diff.txt" 2>&1; then
    fail_ "T6" "init.sh contaminated the framework clone; diff head: $(head -20 "$TMP/clone-diff.txt" | tr '\n' ' ')"
    return
  fi
  pass "T6: the framework clone's file list is unchanged by the T1 run (no contamination)"
}

# --- T2: the anchor is SCRIPT_DIR/.., not the cwd -------------------------
t2_anchor_is_script_dir_not_cwd() {
  # Third directory as cwd so cwd != SCRIPT_DIR/.. — see the NOTE in the
  # header. Karl's decision example invokes init.sh by full path.
  mkdir -p "$TMP/elsewhere"
  run_init "$TMP/elsewhere" "$CLONE/init.sh" tp2 --project-dir tp2

  if [ "$RC" -ne 0 ]; then
    fail_ "T2" "expected rc=0; got rc=$RC; tail: $(echo "$OUT" | tail -8)"
    return
  fi
  if [ -e "$TMP/elsewhere/tp2" ]; then
    fail_ "T2" "bare name resolved against the CWD ($TMP/elsewhere/tp2 exists) — the anchor must be SCRIPT_DIR/.."
    return
  fi
  if ! scaffold_ok "$TMP/tp2"; then
    fail_ "T2" "no scaffold beside the clone at $TMP/tp2; ls: $(ls -a "$TMP" 2>/dev/null | tr '\n' ' ')"
    return
  fi
  pass "T2: bare --project-dir anchors on SCRIPT_DIR/.. (scaffold at $TMP/tp2, cwd was $TMP/elsewhere)"
}

# --- T3: a target INSIDE the framework tree is refused --------------------
t3_inside_target_refused() {
  run_init "$TMP" "$CLONE/init.sh" tp3 --project-dir "$CLONE/sub"

  local created="no"
  [ -e "$CLONE/sub" ] && created="yes"
  # Clean up whatever a regression scaffolded before asserting, so a RED run
  # does not poison the later cases.
  case "$CLONE" in
    "$TMP"/*) rm -rf "$CLONE/sub" ;;
  esac

  if [ "$RC" -eq 0 ]; then
    fail_ "T3" "expected a refusal for a target inside the framework tree; got rc=0 (created=$created)"
    return
  fi
  if ! echo "$OUT" | grep -q "$REFUSAL_RE"; then
    fail_ "T3" "non-zero exit but no refusal message; tail: $(echo "$OUT" | tail -10)"
    return
  fi
  if ! echo "$OUT" | grep -Fq "$CLONE"; then
    fail_ "T3" "refusal did not name the framework root ($CLONE); tail: $(echo "$OUT" | tail -10)"
    return
  fi
  if [ "$created" = "yes" ]; then
    fail_ "T3" "guard fired AFTER mkdir — $CLONE/sub was created"
    return
  fi
  pass "T3: --project-dir inside the framework tree is refused before any mkdir"
}

# --- T4: the target IS a framework clone (signature) ----------------------
t4_target_is_clone_root_refused() {
  run_init "$TMP" "$CLONE/init.sh" tp4 --project-dir "$CLONE"

  if [ "$RC" -eq 0 ]; then
    fail_ "T4" "expected a refusal when --project-dir IS the framework clone; got rc=0"
    return
  fi
  if ! echo "$OUT" | grep -q "$REFUSAL_RE"; then
    fail_ "T4" "non-zero exit but no refusal message; tail: $(echo "$OUT" | tail -10)"
    return
  fi
  pass "T4: --project-dir pointing AT this framework's root is refused (arms (a)+(b) jointly)"
}

# --- T7: ARM (b) ISOLATION — target IS the framework root, signature absent ---
t7_arm_b_target_is_root() {
  run_init "$TMP" "$TMP/nosig/init.sh" tp7 --project-dir "$TMP/nosig"

  if [ "$RC" -eq 0 ]; then
    fail_ "T7" "expected a refusal when the target IS the framework root; got rc=0"
    return
  fi
  if ! echo "$OUT" | grep -q "$GUARD_RE"; then
    fail_ "T7" "arm (b) did not fire — no target-guard refusal (rc=$RC). With (a) blinded by the fixture and (c) starting at the parent, only arm (b) can refuse this; tail: $(echo "$OUT" | tail -10)"
    return
  fi
  if echo "$OUT" | grep -q "$EXISTS_RE"; then
    fail_ "T7" "the existence check refused instead of the guard — the guard must fire first; tail: $(echo "$OUT" | tail -10)"
    return
  fi
  pass "T7: target IS the framework root is refused by arm (b) alone (signature deliberately absent)"
}

# --- T8: ARM (a) ISOLATION — the security-audits-1 S3 vector ---
t8_arm_a_second_framework_clone() {
  run_init "$TMP" "$CLONE/init.sh" tp8 --project-dir "$TMP/other-fw"

  if [ "$RC" -eq 0 ]; then
    fail_ "T8" "expected a refusal when --project-dir is a DIFFERENT framework clone (S3); got rc=0"
    return
  fi
  if ! echo "$OUT" | grep -q "$GUARD_RE"; then
    fail_ "T8" "arm (a) did not fire — no target-guard refusal (rc=$RC). The target is outside this framework, so only the signature arm can refuse it; tail: $(echo "$OUT" | tail -10)"
    return
  fi
  if ! echo "$OUT" | grep -q "signature match"; then
    fail_ "T8" "refused, but not by the signature arm; tail: $(echo "$OUT" | tail -10)"
    return
  fi
  if echo "$OUT" | grep -q "$EXISTS_RE"; then
    fail_ "T8" "the existence check refused instead of the guard; tail: $(echo "$OUT" | tail -10)"
    return
  fi
  pass "T8: --project-dir at a SECOND framework clone is refused by arm (a) alone (security-audits-1 S3)"
}

# --- T9: case-variant target (R-199-1) ---
t9_case_variant_target_refused() {
  if [ "$FS_CASE_INSENSITIVE" != "yes" ]; then
    skip_ "T9" "workdir filesystem is case-SENSITIVE — \$TMP/CLONE is genuinely a different directory here, so refusing it would be wrong"
    return
  fi
  # $TMP/clone spelled $TMP/CLONE: the same directory, a different string.
  local variant="$TMP/CLONE/injected"
  run_init "$TMP" "$CLONE/init.sh" tp9 --project-dir "$variant"

  local created="no"
  [ -e "$CLONE/injected" ] && created="yes"
  case "$CLONE" in
    "$TMP"/*) rm -rf "$CLONE/injected" ;;
  esac

  if [ "$RC" -eq 0 ]; then
    fail_ "T9" "case-variant spelling of the framework path was ALLOWED (rc=0, scaffolded=$created) — byte-wise comparison missed a directory it names"
    return
  fi
  if ! echo "$OUT" | grep -q "$GUARD_RE"; then
    fail_ "T9" "non-zero exit but no target-guard refusal; tail: $(echo "$OUT" | tail -10)"
    return
  fi
  if [ "$created" = "yes" ]; then
    fail_ "T9" "guard fired AFTER mkdir — $CLONE/injected was created"
    return
  fi
  pass "T9: a case-variant spelling of the framework path is refused (device+inode identity)"
}

# --- T10: symlinked target (R-199-7) ---
t10_symlinked_target_refused() {
  run_init "$TMP" "$CLONE/init.sh" tp10 --project-dir "$TMP/lnk/sub"

  local created="no"
  [ -e "$CLONE/sub" ] && created="yes"
  case "$CLONE" in
    "$TMP"/*) rm -rf "$CLONE/sub" ;;
  esac

  if [ "$RC" -eq 0 ]; then
    fail_ "T10" "a symlink into the framework was ALLOWED (rc=0, scaffolded=$created)"
    return
  fi
  if ! echo "$OUT" | grep -q "$GUARD_RE"; then
    fail_ "T10" "non-zero exit but no target-guard refusal; tail: $(echo "$OUT" | tail -10)"
    return
  fi
  if [ "$created" = "yes" ]; then
    fail_ "T10" "guard fired AFTER mkdir — $CLONE/sub was created through the symlink"
    return
  fi
  pass "T10: a target reached through a symlink to the framework is refused"
}

# --- T11: OVER-REFUSAL GUARD — prefix sibling must still be allowed ---
t11_prefix_sibling_allowed() {
  # "$CLONE-2" has the framework's path as a strict string prefix. It is a
  # genuine, unrelated sibling and MUST be allowed. --validate-only is enough:
  # it runs the early-block guard (the same function create_project calls) and
  # exits 0 before scaffolding, so this costs a second instead of a minute.
  run_init "$TMP" "$CLONE/init.sh" tp11 --validate-only --project-dir "$TMP/clone-2/proj"

  if [ "$RC" -ne 0 ]; then
    fail_ "T11" "a genuine sibling whose name merely PREFIX-matches the framework was refused (rc=$RC) — the guard is over-refusing; tail: $(echo "$OUT" | tail -10)"
    return
  fi
  if echo "$OUT" | grep -q "$REFUSAL_RE"; then
    fail_ "T11" "exit 0 but a refusal was printed; tail: $(echo "$OUT" | tail -10)"
    return
  fi
  pass "T11: a prefix-sibling target (clone-2) is still ALLOWED — no over-refusal"
}

# --- T12: escape symlink — inside the framework, pointing outside (R2-1) ---
# Pins a DELIBERATE judgement call, not an obvious invariant. `$CLONE/escape`
# resolves to `$TMP/outside`, so nothing would physically be written into the
# framework and the no-contamination invariant would survive. It is refused
# anyway: the contract is stated over the path the OPERATOR SUPPLIES, and
# letting framework CONTENTS decide whether a target is accepted would make
# acceptance unpredictable and silently changeable. See the DECISION block in
# guard_target_not_in_framework. Uniquely caught by the AS-GIVEN string
# comparison in arm (c) — identity and the physicalized string both say
# "outside" — which is why round 1's "every string comparison is a subset"
# claim was false and why M7 exists.
t12_escape_symlink_refused() {
  run_init "$TMP" "$CLONE/init.sh" tp12 --project-dir "$CLONE/escape/proj"

  local created="no"
  [ -e "$TMP/outside/proj" ] && created="yes"
  rm -rf "$TMP/outside/proj"

  if [ "$RC" -eq 0 ]; then
    fail_ "T12" "a path lexically inside the framework was ALLOWED because a symlink redirects it outside (rc=0, scaffolded=$created) — acceptance must not depend on framework contents"
    return
  fi
  if ! echo "$OUT" | grep -q "$GUARD_RE"; then
    fail_ "T12" "non-zero exit but no target-guard refusal; tail: $(echo "$OUT" | tail -10)"
    return
  fi
  if [ "$created" = "yes" ]; then
    fail_ "T12" "guard fired AFTER mkdir — $TMP/outside/proj was created through the escape symlink"
    return
  fi
  pass "T12: a symlink inside the framework pointing outside is refused (deliberate — see DECISION in the guard)"
}

# --- T5: an absolute external target from the clone cwd -------------------
t5_absolute_external_from_clone_cwd() {
  RC=0
  OUT="$( cd "$CLONE" && ./init.sh --non-interactive \
            --project tp5 \
            --platform web \
            --deployment personal \
            --language typescript \
            --git-host github \
            --visibility private \
            --project-dir "$TMP/abs-external" \
            --no-remote-creation 2>&1 )" || RC=$?

  if [ "$RC" -ne 0 ]; then
    fail_ "T5" "absolute external target from the clone cwd should succeed; got rc=$RC; tail: $(echo "$OUT" | tail -8)"
    return
  fi
  if echo "$OUT" | grep -q "$REFUSAL_RE"; then
    fail_ "T5" "framework refusal fired for an absolute target outside the framework; tail: $(echo "$OUT" | tail -8)"
    return
  fi
  if ! scaffold_ok "$TMP/abs-external"; then
    fail_ "T5" "no scaffold at the absolute target $TMP/abs-external"
    return
  fi
  pass "T5: absolute --project-dir outside the framework works from the clone cwd"
}

# --- Mutation harness -----------------------------------------------------
# Mutations are applied to the FIXTURE CLONE, never to the repo source.
# `cat > "$f"` (not `mv`) so the file keeps its mode — $CLONE/init.sh must
# stay executable for `./init.sh`.
MUT_BACKUP=""
mutate_file() {
  # mutate_file <file> <sed-expr> <label>
  local f="$1" expr="$2" label="$3"
  MUT_BACKUP="$TMP/.mut-backup"
  cp "$f" "$MUT_BACKUP" || return 1
  sed "$expr" "$f" > "$TMP/.mut-new" || return 1
  if cmp -s "$MUT_BACKUP" "$TMP/.mut-new"; then
    echo "    [mutation] $label: sed matched NOTHING — the marked line is missing or was renamed"
    return 1
  fi
  cat "$TMP/.mut-new" > "$f" || return 1
  if ! bash -n "$f" 2>"$TMP/.mut-parse"; then
    echo "    [mutation] $label: mutant does not parse — $(cat "$TMP/.mut-parse")"
    cat "$MUT_BACKUP" > "$f"
    return 1
  fi
  return 0
}
restore_file() {
  local f="$1"
  [ -n "$MUT_BACKUP" ] || return 0
  cat "$MUT_BACKUP" > "$f"
  rm -f "$MUT_BACKUP" "$TMP/.mut-new" "$TMP/.mut-parse"
  MUT_BACKUP=""
}

# --- M1: anchor := cwd → T2 must fail -------------------------------------
m1_anchor_mutation() {
  local f="$CLONE/init.sh"
  echo "  M1: mutating the # BL-199-SIBLING-ANCHOR base from \$SCRIPT_DIR/.. to the cwd"
  if ! mutate_file "$f" 's|^  local _anchor_base="\$SCRIPT_DIR/\.\."$|  local _anchor_base="."|' "M1"; then
    fail_ "M1" "could not apply the anchor mutation (see [mutation] line above)"
    return
  fi

  # Same shape as T2, distinct names so it cannot collide with T2's output.
  mkdir -p "$TMP/elsewhere-m1"
  run_init "$TMP/elsewhere-m1" "$CLONE/init.sh" tp2m --project-dir tp2m
  local mutant_wrong="no"
  [ -e "$TMP/elsewhere-m1/tp2m" ] && mutant_wrong="yes"
  local mutant_right="no"
  scaffold_ok "$TMP/tp2m" && mutant_right="yes"
  rm -rf "$TMP/elsewhere-m1" "$TMP/tp2m"

  restore_file "$f"

  if [ "$mutant_wrong" != "yes" ] || [ "$mutant_right" = "yes" ]; then
    fail_ "M1" "mutant survived: expected the scaffold beside the CWD (got cwd-sibling=$mutant_wrong, clone-sibling=$mutant_right) — T2 is not load-bearing"
    return
  fi
  echo "    [mutation] M1 RED confirmed: with anchor:=cwd the project landed at \$TMP/elsewhere-m1/tp2m (T2's assertion fails)"

  # GREEN direction: restored source must put it beside the clone again.
  mkdir -p "$TMP/elsewhere-m1g"
  run_init "$TMP/elsewhere-m1g" "$CLONE/init.sh" tp2g --project-dir tp2g
  local restored_ok="no"
  if [ "$RC" -eq 0 ] && scaffold_ok "$TMP/tp2g" && [ ! -e "$TMP/elsewhere-m1g/tp2g" ]; then
    restored_ok="yes"
  fi
  rm -rf "$TMP/elsewhere-m1g" "$TMP/tp2g"
  if [ "$restored_ok" != "yes" ]; then
    fail_ "M1" "restore did not return the source to GREEN (rc=$RC)"
    return
  fi
  echo "    [mutation] M1 GREEN confirmed: restored source scaffolds beside the clone again"
  pass "M1: the SCRIPT_DIR/.. anchor is load-bearing (mutant RED, restored GREEN)"
}

# --- M2: drop the inside-framework arm → T3 must fail ---------------------
m2_inside_arm_mutation() {
  local f="$CLONE/scripts/lib/helpers-core.sh"
  echo "  M2: neutralizing the inside-framework arm of guard_target_not_in_framework"
  if ! mutate_file "$f" 's|^  if _bl199_path_is_inside .*$|  if false; then|' "M2"; then
    fail_ "M2" "could not apply the inside-arm mutation (see [mutation] line above)"
    return
  fi

  run_init "$TMP" "$CLONE/init.sh" tp3m --project-dir "$CLONE/sub-m2"
  local mutant_rc="$RC"
  local mutant_created="no"
  [ -e "$CLONE/sub-m2" ] && mutant_created="yes"
  case "$CLONE" in
    "$TMP"/*) rm -rf "$CLONE/sub-m2" ;;
  esac

  restore_file "$f"

  if [ "$mutant_rc" -ne 0 ] && [ "$mutant_created" = "no" ]; then
    fail_ "M2" "mutant survived: the inside-framework target was still refused (rc=$mutant_rc) — T3 is not pinned by that arm"
    return
  fi
  echo "    [mutation] M2 RED confirmed: without the inside arm init.sh wrote INTO the clone (rc=$mutant_rc, created=$mutant_created) — T3's assertion fails"

  # GREEN direction: restored source must refuse again, before any mkdir.
  run_init "$TMP" "$CLONE/init.sh" tp3g --project-dir "$CLONE/sub-m2g"
  local restored_rc="$RC"
  local restored_created="no"
  [ -e "$CLONE/sub-m2g" ] && restored_created="yes"
  case "$CLONE" in
    "$TMP"/*) rm -rf "$CLONE/sub-m2g" ;;
  esac
  if [ "$restored_rc" -eq 0 ] || [ "$restored_created" = "yes" ]; then
    fail_ "M2" "restore did not return the guard to GREEN (rc=$restored_rc, created=$restored_created)"
    return
  fi
  echo "    [mutation] M2 GREEN confirmed: restored guard refuses again with nothing created"
  pass "M2: the inside-framework arm is load-bearing (mutant RED, restored GREEN)"
}

# --- M3: disable the signature arm (a) → T8 must fail ---
# This is the reviewer's MX4. Under the mutant the S3 target is no longer seen
# as a framework, so init.sh proceeds to the existence check and refuses with a
# DIFFERENT message — which is exactly why T8 asserts on the guard's own text
# and not merely on rc!=0.
m3_signature_arm_mutation() {
  local f="$CLONE/scripts/lib/helpers-core.sh"
  echo "  M3: disabling the signature arm (a) of guard_target_not_in_framework"
  if ! mutate_file "$f" 's|^  if _soif_dir_is_framework "\$abs_target"; then$|  if false; then|' "M3"; then
    fail_ "M3" "could not apply the signature-arm mutation (see [mutation] line above)"
    return
  fi

  run_init "$TMP" "$CLONE/init.sh" tp8m --project-dir "$TMP/other-fw"
  local mutant_guarded="no"
  echo "$OUT" | grep -q "$GUARD_RE" && mutant_guarded="yes"
  # R2-5: assert the fallback rather than merely print it. Without this, M3's
  # RED message claimed "existence check only" while checking nothing of the
  # sort — the one proof of the six that asserted less than it announced.
  local mutant_fellthrough="no"
  echo "$OUT" | grep -q "$EXISTS_RE" && mutant_fellthrough="yes"
  local mutant_rc="$RC"

  restore_file "$f"

  if [ "$mutant_guarded" = "yes" ]; then
    fail_ "M3" "mutant survived: the S3 target was still refused by the guard — T8 does not isolate arm (a)"
    return
  fi
  if [ "$mutant_fellthrough" != "yes" ]; then
    fail_ "M3" "mutant exited without the guard AND without reaching the existence check (rc=$mutant_rc) — the run is dying earlier than believed, so this proves nothing"
    return
  fi
  echo "    [mutation] M3 RED confirmed: with arm (a) off the second clone drew no guard refusal and fell through to the existence check (rc=$mutant_rc) — T8's assertion fails"

  run_init "$TMP" "$CLONE/init.sh" tp8g --project-dir "$TMP/other-fw"
  if [ "$RC" -eq 0 ] || ! echo "$OUT" | grep -q "signature match"; then
    fail_ "M3" "restore did not return arm (a) to GREEN (rc=$RC)"
    return
  fi
  echo "    [mutation] M3 GREEN confirmed: restored signature arm refuses the second clone again"
  pass "M3: the signature arm (a) is load-bearing (mutant RED, restored GREEN)"
}

# --- M4: disable the identity walk's comparison → T9 must fail ---
# Leaves both string comparisons in arm (c) intact, so this isolates exactly
# the work dev+inode identity does that no string can.
m4_identity_walk_mutation() {
  if [ "$FS_CASE_INSENSITIVE" != "yes" ]; then
    skip_ "M4" "needs the case-insensitive workdir that T9 needs"
    return
  fi
  local f="$CLONE/scripts/lib/helpers-core.sh"
  echo "  M4: disabling the device+inode comparison inside _bl199_ancestor_is_framework"
  if ! mutate_file "$f" 's|^      if \[ -n "\$id" \] && \[ "\$id" = "\$fw_id" \]; then$|      if false; then|' "M4"; then
    fail_ "M4" "could not apply the identity-walk mutation (see [mutation] line above)"
    return
  fi

  run_init "$TMP" "$CLONE/init.sh" tp9m --project-dir "$TMP/CLONE/injected"
  local mutant_rc="$RC"
  local mutant_created="no"
  [ -e "$CLONE/injected" ] && mutant_created="yes"
  case "$CLONE" in
    "$TMP"/*) rm -rf "$CLONE/injected" ;;
  esac

  restore_file "$f"

  if [ "$mutant_rc" -ne 0 ] && [ "$mutant_created" = "no" ]; then
    fail_ "M4" "mutant survived: the case-variant target was still refused (rc=$mutant_rc) — the identity walk is not what catches it"
    return
  fi
  echo "    [mutation] M4 RED confirmed: without the identity comparison the case-variant spelling wrote INTO the clone (rc=$mutant_rc, created=$mutant_created) — T9's assertion fails"

  run_init "$TMP" "$CLONE/init.sh" tp9g --project-dir "$TMP/CLONE/injected"
  local restored_rc="$RC"
  local restored_created="no"
  [ -e "$CLONE/injected" ] && restored_created="yes"
  case "$CLONE" in
    "$TMP"/*) rm -rf "$CLONE/injected" ;;
  esac
  if [ "$restored_rc" -eq 0 ] || [ "$restored_created" = "yes" ]; then
    fail_ "M4" "restore did not return the identity walk to GREEN (rc=$restored_rc, created=$restored_created)"
    return
  fi
  echo "    [mutation] M4 GREEN confirmed: restored identity walk refuses the case variant again"
  pass "M4: the device+inode identity walk is load-bearing (mutant RED, restored GREEN)"
}

# --- M5: remove BOTH pwd -P resolutions → T10 must fail ---
# R-199-7. Symlink handling is over-determined: _bl199_physical_path resolves
# for the string comparisons and _bl199_dir_id resolves again for identity.
# Either alone survives its own removal, so the mutation must take both.
m5_physicalization_mutation() {
  local f="$CLONE/scripts/lib/helpers-core.sh"
  echo "  M5: removing BOTH pwd -P resolutions (_bl199_physical_path and _bl199_dir_id)"
  if ! mutate_file "$f" \
      's|^  phys="\$(cd "\$probe" 2>/dev/null \&\& pwd -P)"$|  phys="$probe"|; s|^  p="\$(cd "\$d" 2>/dev/null \&\& pwd -P)" \|\| return 1$|  p="$d"|' \
      "M5"; then
    fail_ "M5" "could not apply the physicalization mutation (see [mutation] line above)"
    return
  fi

  run_init "$TMP" "$CLONE/init.sh" tp10m --project-dir "$TMP/lnk/sub"
  local mutant_rc="$RC"
  local mutant_created="no"
  [ -e "$CLONE/sub" ] && mutant_created="yes"
  case "$CLONE" in
    "$TMP"/*) rm -rf "$CLONE/sub" ;;
  esac

  restore_file "$f"

  if [ "$mutant_rc" -ne 0 ] && [ "$mutant_created" = "no" ]; then
    fail_ "M5" "mutant survived: the symlinked target was still refused (rc=$mutant_rc) — physicalization is not what catches it"
    return
  fi
  echo "    [mutation] M5 RED confirmed: with neither pwd -P the symlink wrote INTO the clone (rc=$mutant_rc, created=$mutant_created) — T10's assertion fails"

  run_init "$TMP" "$CLONE/init.sh" tp10g --project-dir "$TMP/lnk/sub"
  local restored_rc="$RC"
  local restored_created="no"
  [ -e "$CLONE/sub" ] && restored_created="yes"
  case "$CLONE" in
    "$TMP"/*) rm -rf "$CLONE/sub" ;;
  esac
  if [ "$restored_rc" -eq 0 ] || [ "$restored_created" = "yes" ]; then
    fail_ "M5" "restore did not return physicalization to GREEN (rc=$restored_rc, created=$restored_created)"
    return
  fi
  echo "    [mutation] M5 GREEN confirmed: restored resolution refuses the symlinked target again"
  pass "M5: pwd -P physicalization is load-bearing (mutant RED, restored GREEN)"
}

# --- M6: remove arm (b) entirely → T7 must fail ---
# The reviewer's MX5. Against fe2d045 this mutant SURVIVED at 8/8 because no
# test shape could distinguish arm (b) from arm (a). T7 is that shape.
m6_root_arm_mutation() {
  # MUTATE THE COPY THAT ACTUALLY RUNS. T7 invokes "$TMP/nosig/init.sh", which
  # sources "$TMP/nosig/scripts/lib/helpers-core.sh" — a SEPARATE FILE from the
  # clone's. The first version of this proof mutated the clone's copy and the
  # mutant "survived" for that reason alone; the suite caught it, which is the
  # whole point of running the mutation rather than asserting it.
  local f="$TMP/nosig/scripts/lib/helpers-core.sh"
  echo "  M6: removing the target-IS-root arm (b) of guard_target_not_in_framework"
  if ! mutate_file "$f" 's|^  if \[ "\$tgt_phys" = "\$fw_phys" \] .*_bl199_target_is_framework_root .*then$|  if false; then|' "M6"; then
    fail_ "M6" "could not apply the root-arm mutation (see [mutation] line above)"
    return
  fi

  run_init "$TMP" "$TMP/nosig/init.sh" tp7m --project-dir "$TMP/nosig"
  local mutant_guarded="no"
  echo "$OUT" | grep -q "$GUARD_RE" && mutant_guarded="yes"
  local mutant_fellthrough="no"
  echo "$OUT" | grep -q "$EXISTS_RE" && mutant_fellthrough="yes"
  local mutant_rc="$RC"

  restore_file "$f"

  if [ "$mutant_guarded" = "yes" ]; then
    fail_ "M6" "mutant survived: the framework root was still refused by the guard — T7 does not isolate arm (b)"
    return
  fi
  # Verify the fallback rather than assume it: the mutant must reach the
  # existence check, which proves the guard fell silent rather than the run
  # dying earlier for an unrelated reason (an incomplete nosig fixture used to
  # die at `invalid --platform` and would have "proved" nothing).
  if [ "$mutant_fellthrough" != "yes" ]; then
    fail_ "M6" "mutant exited non-zero without the guard AND without reaching the existence check (rc=$mutant_rc) — the fixture is failing early, so this proves nothing"
    return
  fi
  echo "    [mutation] M6 RED confirmed: with arm (b) off the framework root drew no guard refusal and fell through to the existence check (rc=$mutant_rc) — T7's assertion fails"

  run_init "$TMP" "$TMP/nosig/init.sh" tp7g --project-dir "$TMP/nosig"
  if [ "$RC" -eq 0 ] || ! echo "$OUT" | grep -q "$GUARD_RE"; then
    fail_ "M6" "restore did not return arm (b) to GREEN (rc=$RC)"
    return
  fi
  echo "    [mutation] M6 GREEN confirmed: restored arm (b) refuses the framework root again"
  pass "M6: the target-IS-root arm (b) is load-bearing (mutant RED, restored GREEN)"
}

# --- M7: remove the as-given comparison in arm (c) → T12 must fail ---
# The atom round 1 wrongly called a subset. Identity and the physicalized
# string both resolve the escape symlink to OUTSIDE the framework, so this
# comparison is the only thing that sees the target as inside.
m7_asgiven_comparison_mutation() {
  local f="$CLONE/scripts/lib/helpers-core.sh"
  echo "  M7: removing the as-given _bl199_path_is_inside comparison from arm (c)"
  if ! mutate_file "$f" 's|^  if _bl199_path_is_inside "\$tgt_phys" "\$fw_phys" .*then$|  if _bl199_path_is_inside "$tgt_phys" "$fw_phys" \|\| _bl199_ancestor_is_framework "$tgt_phys" "$fw_id"; then|' "M7"; then
    fail_ "M7" "could not apply the as-given-comparison mutation (see [mutation] line above)"
    return
  fi

  run_init "$TMP" "$CLONE/init.sh" tp12m --project-dir "$CLONE/escape/proj"
  local mutant_rc="$RC"
  local mutant_created="no"
  [ -e "$TMP/outside/proj" ] && mutant_created="yes"
  rm -rf "$TMP/outside/proj"

  restore_file "$f"

  if [ "$mutant_rc" -ne 0 ] && [ "$mutant_created" = "no" ]; then
    fail_ "M7" "mutant survived: the escape-symlink target was still refused (rc=$mutant_rc) — the as-given comparison is NOT what catches it, so round 2's correction is itself wrong"
    return
  fi
  echo "    [mutation] M7 RED confirmed: without the as-given comparison the escape symlink was allowed and scaffolded to \$TMP/outside/proj (rc=$mutant_rc, created=$mutant_created) — T12's assertion fails"

  run_init "$TMP" "$CLONE/init.sh" tp12g --project-dir "$CLONE/escape/proj"
  local restored_rc="$RC"
  local restored_created="no"
  [ -e "$TMP/outside/proj" ] && restored_created="yes"
  rm -rf "$TMP/outside/proj"
  if [ "$restored_rc" -eq 0 ] || [ "$restored_created" = "yes" ]; then
    fail_ "M7" "restore did not return the as-given comparison to GREEN (rc=$restored_rc, created=$restored_created)"
    return
  fi
  echo "    [mutation] M7 GREEN confirmed: restored comparison refuses the escape symlink again"
  pass "M7: the as-given comparison in arm (c) is load-bearing — NOT a subset (mutant RED, restored GREEN)"
}

t1_readme_literal
t6_no_contamination
t2_anchor_is_script_dir_not_cwd
t3_inside_target_refused
t4_target_is_clone_root_refused
t5_absolute_external_from_clone_cwd
t7_arm_b_target_is_root
t8_arm_a_second_framework_clone
t9_case_variant_target_refused
t10_symlinked_target_refused
t11_prefix_sibling_allowed
t12_escape_symlink_refused
m1_anchor_mutation
m2_inside_arm_mutation
m3_signature_arm_mutation
m4_identity_walk_mutation
m5_physicalization_mutation
m6_root_arm_mutation
m7_asgiven_comparison_mutation

echo ""
echo "== Total: $((PASSED + FAILED + SKIPPED)) | Passed: $PASSED | Failed: $FAILED | Skipped: $SKIPPED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
