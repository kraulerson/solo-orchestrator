#!/usr/bin/env bash
# tests/test-bl112-commit-enforcement.sh — BL-112 scaffold-fidelity test.
#
# WHY THIS EXISTS (the fixture-hides-gap class, again)
#   Two "blocking" commit-time gates shipped into every generated project were
#   HOLLOW for months, and every existing test passed the whole time — because
#   no test ever ran a REAL `git commit` through a REAL scaffold's hooks:
#
#   • F9 / # BL-112-SAST-ERROR — the generated .git/hooks/pre-commit invoked
#     `semgrep scan --config=p/owasp-top-ten --quiet` WITHOUT `--error`. Semgrep
#     exits 0 on findings unless --error is passed, so the hook's `[BLOCKED]`
#     branch was unreachable dead code: an `eval(req.query.code)` Express RCE was
#     detected, PRINTED, and committed clean.
#
#   • F8 / # BL-112-STRICT-GATE — the same hook ran an UNCONDITIONAL
#     `exit $FAILED` BEFORE the `# >>> SOIF framework gate (BL-030)` block that
#     install-filesystem-gates.sh appends, so .git/hooks/framework-gate.sh
#     (-> process-checklist.sh --check-commit-ready) NEVER RAN. The
#     phase2-init-verified, UAT-in-progress and build-loop-state gates therefore
#     had NO git-hook backstop — they fired only via the AI-session PreToolUse
#     hook, and any human/script/terminal commit walked straight through.
#
#   Both were found by an end-to-end validation walk, not by the suite. This test
#   is the missing shape: REAL init.sh scaffold -> REAL `git commit` -> assert the
#   commit is REFUSED BY GIT and HEAD did not move.
#
# CASES
#   T-sast-blocks-real-commit      planted eval(req.query.code) -> commit REFUSED
#                                  by git, [BLOCKED] printed, HEAD unmoved.
#                                  (SKIPS LOUDLY if semgrep is absent.)
#   T-sast-clean-commits           a clean source file still commits (no FP) AND
#                                  the SAST arm is proven to have RUN (the hook's
#                                  [OK] receipt). Without that second half the case
#                                  passes VACUOUSLY on a semgrep-less host, where a
#                                  clean file commits precisely because nothing
#                                  scanned it. (SKIPS LOUDLY if semgrep is absent.)
#   T-sast-absent-warns-not-blocks the semgrep-ABSENT contract, pinned at last: with
#                                  semgrep shimmed OFF the PATH of a REAL `git
#                                  commit`, a planted RCE COMMITS and the operator is
#                                  told LOUDLY that SAST did not run. The contract was
#                                  claimed in the PR body with no test behind it —
#                                  which is the same class of lie as a [BLOCKED] that
#                                  never blocks.
#   T-mutation-sast-absent-arm     the other direction: make the absent arm BLOCK ->
#                                  the contract test goes RED -> restore -> GREEN.
#   T-sast-toolfail-warns-not-blocks  semgrep shimmed to exit 2 (broken ruleset /
#                                  unreachable registry) -> DECLARED behaviour: the
#                                  commit LANDS, and the operator sees an unmissable
#                                  "SAST NOT ENFORCED" line plus the real diagnostic.
#                                  This is a security DECISION and it is pinned, not
#                                  asserted (rationale: # BL-112-SAST-NOTRUN).
#   T-mutation-sast-toolfail-arm   the other direction: make the rc>=2 arm BLOCK ->
#                                  the declared behaviour goes RED -> restore -> GREEN.
#   T-strict-gate-blocks-unverified phase2_init.verified=false + real source
#                                  commit -> REFUSED BY GIT (the F8 proof).
#   T-strict-gate-blocks-mid-uat   UAT started, <9 steps, build loop SATISFIED so
#                                  the UAT arm is the only thing that can block ->
#                                  real source commit REFUSED BY GIT.
#   T-clean-commit-still-works     everything satisfied -> real commit SUCCEEDS,
#                                  and a terminal_commit_passed audit row proves
#                                  the gate actually RAN (not that it is missing).
#   T-tdd-gate-no-regression       the BL-072 wrong-order (test-less feat:) commit
#                                  is still blocked by the commit-msg hook.
#   T-mutation-sast-error          strip `--error` from the scaffold's hook ->
#                                  T-sast-blocks-real-commit goes RED (the flaw
#                                  commits) -> restore -> GREEN.
#   T-mutation-strict-gate         restore the unconditional `exit $FAILED` (i.e.
#                                  put the gate invocation back AFTER a terminal
#                                  exit) -> T-strict-gate-blocks-unverified goes
#                                  RED -> restore -> GREEN.
#
# AGGREGATOR-ONLY. It runs the REAL init.sh and REAL `git commit`s, so it is
# registered ONLY in tests/full-project-test-suite.sh (SUITE_SKIP_AGGREGATORS-
# gated) and NEVER in the tests.yml unit fast lane.
#
# HOOKS FOR tests/test-bl099-guard-coverage.sh (ignored by a bare run):
#   BL112_REPO_OVERRIDE=<framework-tree>  scaffold from a MUTANT framework tree
#   BL112_ONLY="T-a T-b"                  run only the named cases
#
# Hermetic: mktemp, git identity set locally, GITHUB_BASE_REF unset, init.sh run
# with --no-remote-creation (the blessed no-live-remote path). No live remote is
# ever contacted. bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FRAMEWORK="${BL112_REPO_OVERRIDE:-$REPO_ROOT}"
INIT="$FRAMEWORK/init.sh"
ONLY="${BL112_ONLY:-}"

unset GITHUB_BASE_REF 2>/dev/null || true

PASSED=0
FAILED=0
SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip_() { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

# Selected? (empty BL112_ONLY = run everything)
want() {
  [ -z "$ONLY" ] && return 0
  case " $ONLY " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

if ! command -v jq >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  echo "SKIP: jq/git required for the init.sh-driven commit-enforcement test"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

# ── The semgrep predicate, stated LOUDLY ─────────────────────────────────────
# A silently-skipped security test is the same class of lie BL-112 is about. If
# semgrep is not on this host we say so in a way nobody can miss, and we still
# run every non-SAST case.
HAVE_SEMGREP=0
if command -v semgrep >/dev/null 2>&1; then
  HAVE_SEMGREP=1
else
  echo ""
  echo "##############################################################"
  echo "## semgrep IS NOT INSTALLED ON THIS HOST.                   ##"
  echo "## The three semgrep-REQUIRING cases are SKIPPED, NOT PASSED:##"
  echo "##   T-sast-blocks-real-commit                               ##"
  echo "##   T-sast-clean-commits                                    ##"
  echo "##   T-mutation-sast-error                                   ##"
  echo "## The pre-commit SAST *blocking* arm is UNPROVEN here.      ##"
  echo "## (The tool-ABSENT and tool-FAILED contracts are still      ##"
  echo "##  fully proven below — they do not need a real semgrep.)   ##"
  echo "## Install semgrep to exercise them: brew install semgrep    ##"
  echo "##############################################################"
  echo ""
fi

# ── Scaffold ONE real project (hermetic) ─────────────────────────────────────
# organizational + sponsored_poc: forces enforcement_level=strict (so
# framework-gate.sh is installed and does not self-no-op) AND the BL-072 hard
# TDD block (needed by T-tdd-gate-no-regression). typescript gives semgrep a
# language its OWASP rules actually cover.
echo "=== Scaffolding a real sponsored-POC project via init.sh (hermetic) ==="
BASE="$TOPTMP/base"
if ! ( cd "$TOPTMP" && "$INIT" --non-interactive \
        --project bl112 \
        --platform web \
        --deployment organizational \
        --gov-mode sponsored_poc \
        --language typescript \
        --git-host github \
        --visibility private \
        --project-dir "$BASE" \
        --no-remote-creation ) >"$TOPTMP/init.out" 2>"$TOPTMP/init.err"; then
  fail_ "scaffold-init" "init.sh exited non-zero; stderr tail: $(tail -8 "$TOPTMP/init.err" | tr '\n' '|')"
  echo "Results: $PASSED passed, $FAILED failed"
  exit 1
fi

# ── Preconditions: the surface under test actually shipped ───────────────────
HOOK="$BASE/.git/hooks/pre-commit"
precond_ok=1
[ -x "$HOOK" ] || { fail_ "precond-hook" "no executable .git/hooks/pre-commit in the scaffold"; precond_ok=0; }
[ -x "$BASE/.git/hooks/framework-gate.sh" ] || { fail_ "precond-gate" "framework-gate.sh not installed (strict expected)"; precond_ok=0; }
if [ "$(jq -r '.enforcement_level // "missing"' "$BASE/.claude/manifest.json" 2>/dev/null)" != "strict" ]; then
  fail_ "precond-strict" "manifest enforcement_level is not strict"; precond_ok=0
fi
# Grep the appended block's LOAD-BEARING LINE, not its marker comment: a comment
# is cheap to satisfy and would let this precondition pass vacuously.
GATE_CALL='bash "$(git rev-parse --show-toplevel)/.git/hooks/framework-gate.sh"'
if ! grep -qF "$GATE_CALL" "$HOOK"; then
  fail_ "precond-gate-block" "the pre-commit hook never invokes framework-gate.sh"; precond_ok=0
fi
if ! grep -qF '# BL-112-SAST-ERROR' "$HOOK"; then
  fail_ "precond-sast-marker" "the scaffolded hook is missing the # BL-112-SAST-ERROR marker"; precond_ok=0
fi
if ! grep -qF '# BL-112-STRICT-GATE' "$HOOK"; then
  fail_ "precond-gate-marker" "the scaffolded hook is missing the # BL-112-STRICT-GATE marker"; precond_ok=0
fi
if [ "$precond_ok" -eq 1 ]; then
  pass "precond: strict scaffold ships a pre-commit hook with BOTH BL-112 markers + the BL-030 gate block"
fi

# ── Helpers ──────────────────────────────────────────────────────────────────
# A pristine working copy of the scaffold, per case (full isolation incl. .git).
fresh() {
  local w="$TOPTMP/$1"
  rm -rf "$w"
  cp -R "$BASE" "$w"
  git -C "$w" config user.email bl112@test.invalid
  git -C "$w" config user.name  bl112-test
  echo "$w"
}

# The OWASP flaw the walk used: Express request data flowing into eval().
plant_flaw() {
  mkdir -p "$1/src"
  cat > "$1/src/probe.ts" <<'TS'
import express from 'express';
const app = express();
app.get('/run', (req, res) => {
  eval(req.query.code);
  res.send('ok');
});
export default app;
TS
  git -C "$1" add src/probe.ts
}

plant_clean() {
  mkdir -p "$1/src"
  printf 'export const add = (a: number, b: number): number => a + b;\n' > "$1/src/$2.ts"
  git -C "$1" add "src/$2.ts"
}

# try_commit <proj> <subject> <logfile> — echoes "REFUSED" or "COMMITTED".
# HEAD movement is asserted separately by the caller (a hook that exits non-zero
# but still moved HEAD would be a different, worse bug).
try_commit() {
  local proj="$1" subj="$2" log="$3" rc=0
  ( cd "$proj" && git commit -m "$subj" ) >"$log" 2>&1
  rc=$?
  [ "$rc" -eq 0 ] && echo "COMMITTED" || echo "REFUSED"
}

head_of() { git -C "$1" rev-parse HEAD 2>/dev/null || echo none; }

# try_commit_path <proj> <subject> <logfile> <PATH> — try_commit under a custom
# PATH. The hook decides with `command -v semgrep`, so PATH is the ONLY honest
# lever for exercising the tool-absent / tool-broken contracts against a REAL hook
# and a REAL `git commit`. git inherits our environment, so the hook sees this PATH.
try_commit_path() {
  local proj="$1" subj="$2" log="$3" p="$4" rc=0
  ( cd "$proj" && PATH="$p" git commit -m "$subj" ) >"$log" 2>&1
  rc=$?
  [ "$rc" -eq 0 ] && echo "COMMITTED" || echo "REFUSED"
}

# ── Shimming semgrep OFF the PATH, honestly ──────────────────────────────────
# We do NOT just delete the PATH entry that holds semgrep: on a Homebrew host that
# is /opt/homebrew/bin, which ALSO holds gitleaks (and much else the hook and the
# BL-030 gate shell out to). Deleting it would change several variables at once and
# the test would prove nothing about semgrep.
#
# Instead: every PATH entry that contains an executable `semgrep` is replaced by a
# MIRROR directory of symlinks to all of its entries EXCEPT semgrep. Everything else
# on the host resolves byte-identically; semgrep, and only semgrep, is gone. On a
# host with no semgrep at all this is a pure no-op and the cases run natively — so
# the absent-contract cases are exercised on EVERY host, not just this one.
NOSEMGREP_PATH=""
build_nosemgrep_path() {
  [ -n "$NOSEMGREP_PATH" ] && return 0
  local mirrors="$TOPTMP/nosemgrep-mirrors" n=0 d np="" entry base
  rm -rf "$mirrors"; mkdir -p "$mirrors"
  printf '%s' "$PATH" | tr ':' '\n' > "$mirrors/.pathlist"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    if [ -x "$d/semgrep" ]; then
      n=$((n + 1))
      mkdir -p "$mirrors/$n"
      for entry in "$d"/*; do
        [ -e "$entry" ] || continue           # bash 3.2 has no nullglob
        base="${entry##*/}"
        [ "$base" = "semgrep" ] && continue
        ln -sf "$entry" "$mirrors/$n/$base" 2>/dev/null || true
      done
      np="${np:+$np:}$mirrors/$n"
    else
      np="${np:+$np:}$d"
    fi
  done < "$mirrors/.pathlist"
  NOSEMGREP_PATH="$np"
}

# The shim's own integrity check: semgrep must be gone AND everything the hook and
# the gate depend on must still be there. A shim that removed too much would make
# the contract cases pass for the wrong reason.
nosemgrep_path_sane() {
  PATH="$NOSEMGREP_PATH" command -v semgrep >/dev/null 2>&1 && return 1
  local t
  for t in git jq bash sed grep awk mktemp; do
    PATH="$NOSEMGREP_PATH" command -v "$t" >/dev/null 2>&1 || return 2
  done
  return 0
}

# make_semgrep_shim <dir> <rc> — a `semgrep` that FAILS like the real one does when
# its ruleset cannot be loaded: real diagnostics on stderr, exit <rc>. Prepended to
# PATH it shadows any real semgrep, so the tool-failure contract is exercised on
# every host regardless of whether semgrep is installed.
make_semgrep_shim() {
  mkdir -p "$1"
  cat > "$1/semgrep" <<SHIMEOF
#!/bin/sh
echo "[ERROR] Failed to download config from https://semgrep.dev/c/p/owasp-top-ten: HTTP 404" >&2
echo "[ERROR] invalid configuration file found (1 configs were invalid)" >&2
exit $2
SHIMEOF
  chmod +x "$1/semgrep"
}

# Put a project into a legitimate Phase-2 "commit-ready" state, driving the REAL
# process-checklist.sh for everything it can express. current_phase is set with
# jq: the legitimate 1->2 gate needs a live remote to attest branch protection
# (BL-111/F5), which a hermetic test may not create — the same seeding pattern
# tests/test-pre-commit-gate-classifier.sh uses.
phase2_ready() {
  local w="$1"
  jq '.current_phase = 2' "$w/.claude/phase-state.json" > "$w/.claude/ps.tmp" \
    && mv "$w/.claude/ps.tmp" "$w/.claude/phase-state.json"
  jq '.phase2_init.verified = true' "$w/.claude/process-state.json" > "$w/.claude/pr.tmp" \
    && mv "$w/.claude/pr.tmp" "$w/.claude/process-state.json"
}

# Complete the 5 build-loop steps --check-commit-ready requires. framework-gate.sh
# calls --check-commit-ready with NO --subject, so subject_is_feat defaults true
# and the build-loop arm applies to EVERY Phase-2 source commit — this is what a
# real operator must satisfy, and it must be satisfied here or the build-loop arm
# would shadow the UAT arm we are actually testing.
complete_build_loop() {
  local w="$1" feat="$2"
  ( cd "$w"
    mkdir -p docs/security-audits
    # BL-120: the security_audit step now READS the verdict (template
    # grammar) — the fixture must carry a passing one, not just exist.
    printf '# security audit: %s\n\n| Open | 0 |\n\n**All findings resolved:** Yes\n' "$feat" > "docs/security-audits/${feat}-security-audit.md"
    scripts/process-checklist.sh --start-feature "$feat"
    for s in tests_written tests_verified_failing implemented security_audit documentation_updated; do
      scripts/process-checklist.sh --complete-step "build_loop:$s"
    done ) >"$w/loop.log" 2>&1
}

# ═════════════════════════════════════════════════════════════════════════════
# T-sast-blocks-real-commit — the F9 proof.
# ═════════════════════════════════════════════════════════════════════════════
if want T-sast-blocks-real-commit; then
  echo "=== T-sast-blocks-real-commit: planted eval(req.query.code) -> REFUSED BY GIT ==="
  if [ "$HAVE_SEMGREP" -eq 0 ]; then
    skip_ "T-sast-blocks-real-commit" "semgrep ABSENT on this host — the pre-commit SAST gate is UNPROVEN here (this is a skip, NOT a pass)"
  else
    W="$(fresh sast)"
    H0="$(head_of "$W")"
    plant_flaw "$W"
    V="$(try_commit "$W" "chore: add probe route" "$W/commit.log")"
    H1="$(head_of "$W")"
    if [ "$V" = "REFUSED" ] && [ "$H0" = "$H1" ] && grep -qF '[BLOCKED]' "$W/commit.log"; then
      pass "T-sast-blocks-real-commit: git refused the commit, HEAD unmoved, [BLOCKED] printed"
    else
      fail_ "T-sast-blocks-real-commit" "verdict=$V head_moved=$( [ "$H0" = "$H1" ] && echo no || echo YES) blocked_line=$(grep -cF '[BLOCKED]' "$W/commit.log"); log: $(tail -6 "$W/commit.log" | tr '\n' '|')"
    fi
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# T-sast-clean-commits — no false positive on a clean file, AND the arm RAN.
#
# "A clean file commits" is TRIVIALLY true on a host with no semgrep, where the
# SAST arm is skipped entirely — so on its own that assertion is vacuous and pins
# nothing. Two halves make it real: the case SKIPS LOUDLY when semgrep is absent,
# and when semgrep is present it asserts the hook's [OK] receipt, which is emitted
# only on the rc=0 path — i.e. only if the scan actually ran and came back clean.
# ═════════════════════════════════════════════════════════════════════════════
if want T-sast-clean-commits; then
  echo "=== T-sast-clean-commits: a clean file commits AND the SAST arm actually RAN ==="
  if [ "$HAVE_SEMGREP" -eq 0 ]; then
    skip_ "T-sast-clean-commits" "semgrep ABSENT on this host — a clean file commits here because NOTHING SCANNED IT; the case would pass vacuously (this is a skip, NOT a pass)"
  else
    W="$(fresh sastclean)"
    H0="$(head_of "$W")"
    plant_clean "$W" helper
    V="$(try_commit "$W" "chore: add a helper" "$W/commit.log")"
    H1="$(head_of "$W")"
    if [ "$V" = "COMMITTED" ] && [ "$H0" != "$H1" ] \
       && grep -qF '[OK] semgrep: SAST ran' "$W/commit.log" \
       && ! grep -qF 'SAST NOT ENFORCED' "$W/commit.log"; then
      pass "T-sast-clean-commits: clean file commits AND the scan RAN (the [OK] receipt is in the commit output) — not a brick, and not a no-op"
    else
      fail_ "T-sast-clean-commits" "verdict=$V ran_receipt=$(grep -cF '[OK] semgrep: SAST ran' "$W/commit.log") not_enforced=$(grep -cF 'SAST NOT ENFORCED' "$W/commit.log"); log: $(tail -8 "$W/commit.log" | tr '\n' '|')"
    fi
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# T-sast-absent-warns-not-blocks — THE SEMGREP-ABSENT CONTRACT, at last pinned.
#
# The hook's documented contract is that a MISSING semgrep WARNs and never blocks.
# That contract was claimed as "preserved and tested" with no test behind it
# anywhere in the repo — which is exactly the class of claim BL-112 exists to kill.
# Here it is, in the only shape that can prove it: a REAL scaffold, a REAL
# `git commit`, semgrep genuinely unresolvable on the PATH that commit runs under.
# ═════════════════════════════════════════════════════════════════════════════
if want T-sast-absent-warns-not-blocks; then
  echo "=== T-sast-absent-warns-not-blocks: semgrep OFF the PATH + planted RCE -> the commit LANDS (contract) ==="
  build_nosemgrep_path
  nosemgrep_path_sane; SANE=$?
  if [ "$SANE" -eq 1 ]; then
    fail_ "T-sast-absent-warns-not-blocks" "the PATH shim FAILED — semgrep still resolves; the contract is UNPROVEN (a failure, not a skip)"
  elif [ "$SANE" -ne 0 ]; then
    fail_ "T-sast-absent-warns-not-blocks" "the PATH shim removed more than semgrep (a required tool no longer resolves) — it would prove nothing"
  else
    W="$(fresh sastabsent)"
    H0="$(head_of "$W")"
    plant_flaw "$W"
    V="$(try_commit_path "$W" "chore: add probe route (no semgrep on PATH)" "$W/commit.log" "$NOSEMGREP_PATH")"
    H1="$(head_of "$W")"
    if [ "$V" = "COMMITTED" ] && [ "$H0" != "$H1" ] \
       && grep -qF '[WARN] semgrep not found' "$W/commit.log" \
       && grep -qF 'SAST NOT ENFORCED' "$W/commit.log" \
       && ! grep -qF '[BLOCKED]' "$W/commit.log"; then
      pass "T-sast-absent-warns-not-blocks: tool absent -> the RCE COMMITS (the contract), and the operator is told LOUDLY that SAST did not run"
    else
      fail_ "T-sast-absent-warns-not-blocks" "verdict=$V (want COMMITTED) warn_notfound=$(grep -cF '[WARN] semgrep not found' "$W/commit.log") loud=$(grep -cF 'SAST NOT ENFORCED' "$W/commit.log") blocked=$(grep -cF '[BLOCKED]' "$W/commit.log"); log: $(tail -8 "$W/commit.log" | tr '\n' '|')"
    fi
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# T-sast-toolfail-warns-not-blocks — THE rc>=2 (TOOL-FAILURE) ARM.
#
# This is a SECURITY DECISION, and it is declared, not assumed: a semgrep that
# FAILS (broken ruleset, unreachable registry, OOM) is treated exactly like a
# semgrep that is ABSENT — WARN, do not block. The full rationale lives on
# `soif_sast_not_enforced` (# BL-112-SAST-NOTRUN) in scripts/lib/hook-templates.sh;
# the short version is that blocking here buys no security (anyone who can break
# the scanner can more easily REMOVE it, and hit the absent arm) while bricking
# every commit of every offline developer, because p/owasp-top-ten is a REGISTRY
# ruleset with no local cache.
#
# What the decision DOES owe the operator is loudness, and that is what this pins:
# the commit lands, but nobody can mistake it for a clean scan, and the real
# diagnostic is on screen.
# ═════════════════════════════════════════════════════════════════════════════
if want T-sast-toolfail-warns-not-blocks; then
  echo "=== T-sast-toolfail-warns-not-blocks: semgrep exits 2 (broken ruleset) -> commit LANDS, LOUDLY ==="
  SHIM2="$TOPTMP/shim-rc2"
  make_semgrep_shim "$SHIM2" 2
  SHIM2PATH="$SHIM2:$PATH"
  if [ "$(PATH="$SHIM2PATH" command -v semgrep)" != "$SHIM2/semgrep" ]; then
    fail_ "T-sast-toolfail-warns-not-blocks" "the rc=2 shim did not shadow semgrep on PATH — the arm is UNPROVEN"
  else
    W="$(fresh sasttoolfail)"
    H0="$(head_of "$W")"
    plant_flaw "$W"
    V="$(try_commit_path "$W" "chore: add probe route (semgrep broken)" "$W/commit.log" "$SHIM2PATH")"
    H1="$(head_of "$W")"
    if [ "$V" = "COMMITTED" ] && [ "$H0" != "$H1" ] \
       && grep -qF 'semgrep could not complete (exit 2)' "$W/commit.log" \
       && grep -qF 'SAST NOT ENFORCED' "$W/commit.log" \
       && grep -qF 'invalid configuration file found' "$W/commit.log" \
       && ! grep -qF '[BLOCKED]' "$W/commit.log"; then
      pass "T-sast-toolfail-warns-not-blocks: rc=2 -> the DECLARED behaviour (commit lands), with 'SAST NOT ENFORCED' + the real diagnostic on screen"
    else
      fail_ "T-sast-toolfail-warns-not-blocks" "verdict=$V (want COMMITTED) rc2_line=$(grep -cF 'semgrep could not complete (exit 2)' "$W/commit.log") loud=$(grep -cF 'SAST NOT ENFORCED' "$W/commit.log") diag=$(grep -cF 'invalid configuration file found' "$W/commit.log") blocked=$(grep -cF '[BLOCKED]' "$W/commit.log"); log: $(tail -10 "$W/commit.log" | tr '\n' '|')"
    fi
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# T-strict-gate-blocks-unverified — the F8 proof (phase2_init.verified=false).
# ═════════════════════════════════════════════════════════════════════════════
if want T-strict-gate-blocks-unverified; then
  echo "=== T-strict-gate-blocks-unverified: verified=false + real source commit -> REFUSED BY GIT ==="
  W="$(fresh unverified)"
  phase2_ready "$W"
  jq '.phase2_init.verified = false' "$W/.claude/process-state.json" > "$W/.claude/x.tmp" \
    && mv "$W/.claude/x.tmp" "$W/.claude/process-state.json"
  H0="$(head_of "$W")"
  plant_clean "$W" feature
  V="$(try_commit "$W" "chore: touch source before init is verified" "$W/commit.log")"
  H1="$(head_of "$W")"
  if [ "$V" = "REFUSED" ] && [ "$H0" = "$H1" ] && grep -qF 'Phase 2 initialization not verified' "$W/commit.log"; then
    pass "T-strict-gate-blocks-unverified: GIT refused it (framework-gate.sh is reachable), HEAD unmoved"
  else
    fail_ "T-strict-gate-blocks-unverified" "verdict=$V head_moved=$( [ "$H0" = "$H1" ] && echo no || echo YES); log: $(tail -8 "$W/commit.log" | tr '\n' '|')"
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# T-strict-gate-blocks-mid-uat — the second F8 proof. The build loop is COMPLETE
# on purpose, so the build-loop arm cannot shadow the UAT arm: if the commit is
# refused here it is refused BECAUSE the UAT session is open.
# ═════════════════════════════════════════════════════════════════════════════
if want T-strict-gate-blocks-mid-uat; then
  echo "=== T-strict-gate-blocks-mid-uat: uat_completed<9 + real chore commit -> REFUSED BY GIT ==="
  W="$(fresh miduat)"
  phase2_ready "$W"
  complete_build_loop "$W" "widget"
  ( cd "$W" && scripts/process-checklist.sh --start-uat 1 ) >>"$W/loop.log" 2>&1
  uat_started="$(jq -r '.uat_session.started_at // "null"' "$W/.claude/process-state.json")"
  uat_done="$(jq '.uat_session.steps_completed | length' "$W/.claude/process-state.json")"
  H0="$(head_of "$W")"
  plant_clean "$W" midu
  V="$(try_commit "$W" "chore: tweak source mid-UAT" "$W/commit.log")"
  H1="$(head_of "$W")"
  if [ "$uat_started" = "null" ]; then
    fail_ "T-strict-gate-blocks-mid-uat" "--start-uat did not open a session (loop.log: $(tail -3 "$W/loop.log" | tr '\n' '|'))"
  elif [ "$V" = "REFUSED" ] && [ "$H0" = "$H1" ] && grep -qF 'UAT session in progress' "$W/commit.log"; then
    pass "T-strict-gate-blocks-mid-uat: GIT refused it on the UAT arm ($uat_done/9 steps), HEAD unmoved"
  else
    fail_ "T-strict-gate-blocks-mid-uat" "verdict=$V uat=$uat_done/9 head_moved=$( [ "$H0" = "$H1" ] && echo no || echo YES); log: $(tail -8 "$W/commit.log" | tr '\n' '|')"
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# T-clean-commit-still-works — the fix must not brick commits, AND the gate must
# be proven to have RUN (a terminal_commit_passed audit row), not merely absent.
# ═════════════════════════════════════════════════════════════════════════════
if want T-clean-commit-still-works; then
  echo "=== T-clean-commit-still-works: everything satisfied -> real commit SUCCEEDS ==="
  W="$(fresh clean)"
  phase2_ready "$W"
  complete_build_loop "$W" "gadget"
  H0="$(head_of "$W")"
  plant_clean "$W" gadget
  V="$(try_commit "$W" "chore: land the gadget" "$W/commit.log")"
  H1="$(head_of "$W")"
  passed_rows="$(jq '[.[] | select(.type == "terminal_commit_passed")] | length' "$W/.claude/bypass-audit.json" 2>/dev/null || echo 0)"
  if [ "$V" = "COMMITTED" ] && [ "$H0" != "$H1" ] && [ "$passed_rows" -ge 1 ]; then
    pass "T-clean-commit-still-works: commit landed AND the gate ran (terminal_commit_passed rows=$passed_rows)"
  else
    fail_ "T-clean-commit-still-works" "verdict=$V head_moved=$( [ "$H0" != "$H1" ] && echo yes || echo NO) terminal_commit_passed_rows=$passed_rows; log: $(tail -8 "$W/commit.log" | tr '\n' '|')"
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# T-tdd-gate-no-regression — the pre-commit reorder must not disturb BL-072,
# which lives in the COMMIT-MSG hook (a different hook, downstream of pre-commit).
# ═════════════════════════════════════════════════════════════════════════════
if want T-tdd-gate-no-regression; then
  echo "=== T-tdd-gate-no-regression: test-less feat: commit still blocked by BL-072 ==="
  W="$(fresh tdd)"
  H0="$(head_of "$W")"
  mkdir -p "$W/src"
  printf 'export const widget = (a: number): number => a * 2;\n' > "$W/src/widget.ts"
  git -C "$W" add src/widget.ts
  V="$(try_commit "$W" "feat: add widget without a test" "$W/commit.log")"
  H1="$(head_of "$W")"
  if [ "$V" = "REFUSED" ] && [ "$H0" = "$H1" ] && grep -qF 'BL-072 TDD ordering' "$W/commit.log"; then
    pass "T-tdd-gate-no-regression: BL-072 commit-msg gate still hard-blocks the wrong-order commit"
  else
    fail_ "T-tdd-gate-no-regression" "verdict=$V bl072_line=$(grep -cF 'BL-072 TDD ordering' "$W/commit.log"); log: $(tail -8 "$W/commit.log" | tr '\n' '|')"
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# MUTATION PROOFS — both against a REAL scaffold's REAL hook.
# ═════════════════════════════════════════════════════════════════════════════

# _mutate <hook> <old> <new> — literal one-occurrence substitution; non-zero on a
# mis-target (so a mutation proof can never pass vacuously against a stale anchor).
_mutate() {
  local hook="$1" old="$2" new="$3" tmp
  tmp="$(mktemp)"
  awk -v old="$old" -v new="$new" '
    { p = index($0, old); if (p > 0) { $0 = substr($0, 1, p-1) new substr($0, p+length(old)); c++ } print }
    END { if (c != 1) exit 3 }
  ' "$hook" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$hook"; chmod +x "$hook"
}

# T-mutation-sast-error: strip `--error` -> the planted flaw COMMITS (RED).
if want T-mutation-sast-error; then
  echo "=== T-mutation-sast-error: strip --error from the scaffold's hook -> RED, restore -> GREEN ==="
  if [ "$HAVE_SEMGREP" -eq 0 ]; then
    skip_ "T-mutation-sast-error" "semgrep ABSENT on this host — the --error mutation is UNPROVEN here (this is a skip, NOT a pass)"
  else
    W="$(fresh msast)"
    HK="$W/.git/hooks/pre-commit"
    if ! _mutate "$HK" '--severity=ERROR --error "${soif_staged[@]}"' '--severity=ERROR "${soif_staged[@]}"'; then
      fail_ "T-mutation-sast-error" "MIS-TARGETED — the semgrep invocation anchor is not present exactly once in the scaffolded hook"
    elif ! grep -qF '# BL-112-SAST-ERROR' "$HK"; then
      fail_ "T-mutation-sast-error" "the mutation removed the marker — it must attack BEHAVIOUR, not the marker text"
    elif ! bash -n "$HK" 2>/dev/null; then
      fail_ "T-mutation-sast-error" "the mutated hook has a syntax error — a broken mutant proves nothing"
    else
      H0="$(head_of "$W")"
      plant_flaw "$W"
      RED="$(try_commit "$W" "chore: add probe route (mutant)" "$W/red.log")"
      HR="$(head_of "$W")"
      # restore: put --error back, rewind, replay the SAME commit.
      _mutate "$HK" '--severity=ERROR "${soif_staged[@]}"' '--severity=ERROR --error "${soif_staged[@]}"' \
        || fail_ "T-mutation-sast-error" "restore mis-targeted"
      git -C "$W" reset -q --hard "$H0"
      plant_flaw "$W"
      GREEN="$(try_commit "$W" "chore: add probe route (restored)" "$W/green.log")"
      HG="$(head_of "$W")"
      if [ "$RED" = "COMMITTED" ] && [ "$H0" != "$HR" ] \
         && [ "$GREEN" = "REFUSED" ] && [ "$H0" = "$HG" ]; then
        pass "T-mutation-sast-error: without --error the RCE COMMITS (RED); with it restored the same commit is REFUSED (GREEN)"
      else
        fail_ "T-mutation-sast-error" "expected RED=COMMITTED/GREEN=REFUSED; got RED=$RED GREEN=$GREEN; red: $(tail -4 "$W/red.log" | tr '\n' '|'); green: $(tail -4 "$W/green.log" | tr '\n' '|')"
      fi
    fi
  fi
fi

# T-mutation-sast-absent-arm: pin the semgrep-ABSENT contract in the OTHER
# direction. A contract asserted only one way is half a contract: "the commit
# lands" would also be satisfied by a hook with no SAST arm at all. So invert the
# arm — make it BLOCK (FAILED=1) — and the contract case must go RED. Restore, and
# it must go GREEN. Now the arm's behaviour, not merely its existence, is pinned.
if want T-mutation-sast-absent-arm; then
  echo "=== T-mutation-sast-absent-arm: make the ABSENT arm block -> RED, restore -> GREEN ==="
  build_nosemgrep_path
  nosemgrep_path_sane; SANE=$?
  if [ "$SANE" -ne 0 ]; then
    fail_ "T-mutation-sast-absent-arm" "the PATH shim is not sane (rc=$SANE) — the mutation would prove nothing"
  else
    W="$(fresh msastabsent)"
    HK="$W/.git/hooks/pre-commit"
    if ! _mutate "$HK" '  soif_sast_not_enforced "semgrep not found' '  FAILED=1; soif_sast_not_enforced "semgrep not found'; then
      fail_ "T-mutation-sast-absent-arm" "MIS-TARGETED — the semgrep-absent arm's call is not present exactly once in the scaffolded hook"
    elif ! grep -qF '# BL-112-SAST-NOTRUN' "$HK"; then
      fail_ "T-mutation-sast-absent-arm" "the mutation removed the marker — it must attack BEHAVIOUR, not the marker text"
    elif ! bash -n "$HK" 2>/dev/null; then
      fail_ "T-mutation-sast-absent-arm" "the mutated hook has a syntax error — a broken mutant proves nothing"
    else
      H0="$(head_of "$W")"
      plant_flaw "$W"
      RED="$(try_commit_path "$W" "chore: probe route, absent arm mutated to block" "$W/red.log" "$NOSEMGREP_PATH")"
      HR="$(head_of "$W")"
      _mutate "$HK" '  FAILED=1; soif_sast_not_enforced "semgrep not found' '  soif_sast_not_enforced "semgrep not found' \
        || fail_ "T-mutation-sast-absent-arm" "restore mis-targeted"
      git -C "$W" reset -q --hard "$H0"
      plant_flaw "$W"
      GREEN="$(try_commit_path "$W" "chore: probe route, absent arm restored" "$W/green.log" "$NOSEMGREP_PATH")"
      HG="$(head_of "$W")"
      if [ "$RED" = "REFUSED" ] && [ "$H0" = "$HR" ] \
         && [ "$GREEN" = "COMMITTED" ] && [ "$H0" != "$HG" ]; then
        pass "T-mutation-sast-absent-arm: a blocking absent-arm REFUSES the commit (RED — contract violated); the shipped WARN arm lets it LAND (GREEN)"
      else
        fail_ "T-mutation-sast-absent-arm" "expected RED=REFUSED/GREEN=COMMITTED; got RED=$RED GREEN=$GREEN; red: $(tail -4 "$W/red.log" | tr '\n' '|'); green: $(tail -4 "$W/green.log" | tr '\n' '|')"
      fi
    fi
  fi
fi

# T-mutation-sast-toolfail-arm: the same both-directions pin for the rc>=2 arm. The
# DECISION to warn rather than block is the thing under test, so it is mutated to
# the road not taken (block) and must go RED.
if want T-mutation-sast-toolfail-arm; then
  echo "=== T-mutation-sast-toolfail-arm: make the rc>=2 arm block -> RED, restore -> GREEN ==="
  SHIM2M="$TOPTMP/shim-rc2-mut"
  make_semgrep_shim "$SHIM2M" 2
  SHIM2MPATH="$SHIM2M:$PATH"
  W="$(fresh msasttoolfail)"
  HK="$W/.git/hooks/pre-commit"
  if [ "$(PATH="$SHIM2MPATH" command -v semgrep)" != "$SHIM2M/semgrep" ]; then
    fail_ "T-mutation-sast-toolfail-arm" "the rc=2 shim did not shadow semgrep on PATH"
  elif ! _mutate "$HK" '      soif_sast_not_enforced "semgrep could not complete' '      FAILED=1; soif_sast_not_enforced "semgrep could not complete'; then
    fail_ "T-mutation-sast-toolfail-arm" "MIS-TARGETED — the rc>=2 arm's call is not present exactly once in the scaffolded hook"
  elif ! grep -qF '# BL-112-SAST-NOTRUN' "$HK"; then
    fail_ "T-mutation-sast-toolfail-arm" "the mutation removed the marker — it must attack BEHAVIOUR, not the marker text"
  elif ! bash -n "$HK" 2>/dev/null; then
    fail_ "T-mutation-sast-toolfail-arm" "the mutated hook has a syntax error — a broken mutant proves nothing"
  else
    H0="$(head_of "$W")"
    plant_flaw "$W"
    RED="$(try_commit_path "$W" "chore: probe route, toolfail arm mutated to block" "$W/red.log" "$SHIM2MPATH")"
    HR="$(head_of "$W")"
    _mutate "$HK" '      FAILED=1; soif_sast_not_enforced "semgrep could not complete' '      soif_sast_not_enforced "semgrep could not complete' \
      || fail_ "T-mutation-sast-toolfail-arm" "restore mis-targeted"
    git -C "$W" reset -q --hard "$H0"
    plant_flaw "$W"
    GREEN="$(try_commit_path "$W" "chore: probe route, toolfail arm restored" "$W/green.log" "$SHIM2MPATH")"
    HG="$(head_of "$W")"
    if [ "$RED" = "REFUSED" ] && [ "$H0" = "$HR" ] \
       && [ "$GREEN" = "COMMITTED" ] && [ "$H0" != "$HG" ]; then
      pass "T-mutation-sast-toolfail-arm: a blocking rc>=2 arm REFUSES the commit (RED — the road not taken); the DECLARED WARN arm lets it LAND (GREEN)"
    else
      fail_ "T-mutation-sast-toolfail-arm" "expected RED=REFUSED/GREEN=COMMITTED; got RED=$RED GREEN=$GREEN; red: $(tail -4 "$W/red.log" | tr '\n' '|'); green: $(tail -4 "$W/green.log" | tr '\n' '|')"
    fi
  fi
fi

# T-mutation-strict-gate: restore the unconditional `exit $FAILED` — i.e. put the
# framework-gate invocation back AFTER a terminal exit — and the unverified-state
# commit lands (RED).
if want T-mutation-strict-gate; then
  echo "=== T-mutation-strict-gate: unconditional exit (gate back below it) -> RED, restore -> GREEN ==="
  W="$(fresh mgate)"
  HK="$W/.git/hooks/pre-commit"
  phase2_ready "$W"
  jq '.phase2_init.verified = false' "$W/.claude/process-state.json" > "$W/.claude/x.tmp" \
    && mv "$W/.claude/x.tmp" "$W/.claude/process-state.json"
  if ! _mutate "$HK" 'if [ "$FAILED" -ne 0 ]; then' 'if true; then'; then
    fail_ "T-mutation-strict-gate" "MIS-TARGETED — the conditional-exit anchor is not present exactly once in the scaffolded hook"
  elif ! grep -qF '# BL-112-STRICT-GATE' "$HK"; then
    fail_ "T-mutation-strict-gate" "the mutation removed the marker — it must attack BEHAVIOUR, not the marker text"
  elif ! grep -qF "$GATE_CALL" "$HK"; then
    fail_ "T-mutation-strict-gate" "the mutation removed the gate invocation itself — that is not the mutation under test"
  elif ! bash -n "$HK" 2>/dev/null; then
    fail_ "T-mutation-strict-gate" "the mutated hook has a syntax error — a broken mutant proves nothing"
  else
    H0="$(head_of "$W")"
    plant_clean "$W" mfeature
    RED="$(try_commit "$W" "chore: touch source before init is verified (mutant)" "$W/red.log")"
    HR="$(head_of "$W")"
    _mutate "$HK" 'if true; then' 'if [ "$FAILED" -ne 0 ]; then' \
      || fail_ "T-mutation-strict-gate" "restore mis-targeted"
    git -C "$W" reset -q --hard "$H0"
    # .claude/{phase,process}-state.json are TRACKED, so the rewind above also
    # reverts the seeded state — re-seed, or the GREEN replay would be testing a
    # verified project and pass vacuously.
    phase2_ready "$W"
    jq '.phase2_init.verified = false' "$W/.claude/process-state.json" > "$W/.claude/x.tmp" \
      && mv "$W/.claude/x.tmp" "$W/.claude/process-state.json"
    plant_clean "$W" mfeature
    GREEN="$(try_commit "$W" "chore: touch source before init is verified (restored)" "$W/green.log")"
    HG="$(head_of "$W")"
    if [ "$RED" = "COMMITTED" ] && [ "$H0" != "$HR" ] \
       && [ "$GREEN" = "REFUSED" ] && [ "$H0" = "$HG" ]; then
      pass "T-mutation-strict-gate: with an unconditional exit the unverified commit LANDS (RED); with the conditional exit restored GIT refuses it (GREEN)"
    else
      fail_ "T-mutation-strict-gate" "expected RED=COMMITTED/GREEN=REFUSED; got RED=$RED GREEN=$GREEN; red: $(tail -4 "$W/red.log" | tr '\n' '|'); green: $(tail -4 "$W/green.log" | tr '\n' '|')"
    fi
  fi
fi

# ── Tally ────────────────────────────────────────────────────────────────────
echo ""
if [ "$SKIPPED" -gt 0 ]; then
  echo "!! $SKIPPED case(s) SKIPPED (see the banner above) — skipped != passed."
fi
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
