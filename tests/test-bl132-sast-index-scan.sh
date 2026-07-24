#!/usr/bin/env bash
# tests/test-bl132-sast-index-scan.sh — BL-132: the pre-commit SAST arm must scan
# the STAGED CONTENT (the bytes being committed), not the WORKTREE bytes.
#
# WHY THIS EXISTS (BL-118 adversarial verification, PR #199)
#   The armed pre-commit SAST arm handed semgrep the staged PATHNAMES
#   (`git diff --cached --name-only`), so semgrep read whatever was on DISK — which
#   need not be the staged bytes. Repro: `git add app.ts` (containing the XSS),
#   overwrite the worktree app.ts with a clean version, `git commit` -> the commit
#   LANDS with the `[OK]` receipt while `git show HEAD:app.ts` still holds the
#   vulnerable innerHTML. `git add -p` / stage-then-edit share the hole in the
#   benign direction (a false block on unstaged edits). The fix materializes the
#   staged blobs into a temp tree (# BL-132-INDEX-SCAN in scripts/lib/hook-
#   templates.sh) and points semgrep there, mapping finding paths back.
#
# CASES
#   T-index-blocks-staged-vuln    live — stage innerHTML XSS, overwrite the worktree
#                                 copy CLEAN, commit -> REFUSED (the STAGED bytes are
#                                 scanned), HEAD unmoved, [BLOCKED], and the real
#                                 path app.ts appears (temp-prefix mapping).
#                                 RED pre-fix: commit LANDS with [OK].
#   T-index-no-false-block        live — stage CLEAN, overwrite the worktree copy
#                                 with the vuln, commit -> LANDS (the unstaged vuln
#                                 is not the committed bytes; no false block).
#   T-notrun-contract-intact      live — semgrep shimmed OFF the PATH -> the commit
#                                 LANDS and the operator is told LOUDLY that SAST did
#                                 not run ([WARN] semgrep not found + SAST NOT
#                                 ENFORCED). The refactor must not disturb the
#                                 # BL-112-SAST-NOTRUN contract.
#   T-mutation-index-scan         live — revert the emitted hook's scan target to the
#                                 worktree paths (the pre-BL-132 behaviour) ->
#                                 T-index-blocks-staged-vuln goes RED (the clean
#                                 worktree scans clean, vuln commits) -> restore ->
#                                 GREEN. Proves the index snapshot is load-bearing.
#
#   The live cases talk to the semgrep registry (owasp/browser config fetch). A host
#   where that fails yields LOUD SKIPs, never silent passes. The blocking vuln here
#   (innerHTML) is caught by the registry browser pack, so this suite exercises the
#   index-scan PLUMBING independently of the BL-131 custom ruleset — but the emitted
#   hook references that ruleset, so the fixture ships it (.semgrep/soif-dom-sinks.yml).
#
# REGISTRATION: never runs init.sh, not an aggregator -> registered in BOTH
# tests/full-project-test-suite.sh AND the tests.yml unit fast lane.
# Hermetic: mktemp workdirs, local git identity, GITHUB_BASE_REF unset, no remote.
# bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

unset GITHUB_BASE_REF 2>/dev/null || true

PASSED=0
FAILED=0
SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip_() { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

HOOK_SRC="$REPO_ROOT/scripts/lib/hook-templates.sh"
RULESET_SRC="$REPO_ROOT/templates/semgrep/soif-dom-sinks.yml"
EMITTED="$TOPTMP/emitted-hook"

if [ ! -f "$HOOK_SRC" ]; then
  echo "SKIP: scripts/lib/hook-templates.sh missing"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi
# shellcheck source=/dev/null
. "$HOOK_SRC"
soif_write_precommit_hook "$EMITTED"

# ── The semgrep predicate, stated LOUDLY (a silent security skip is the BL-112 lie) ─
HAVE_SEMGREP=0
if command -v semgrep >/dev/null 2>&1; then
  HAVE_SEMGREP=1
else
  echo ""
  echo "#################################################################"
  echo "## semgrep IS NOT INSTALLED ON THIS HOST.                      ##"
  echo "## The index-scan live cases are SKIPPED, NOT PASSED.          ##"
  echo "## Install semgrep to exercise them: brew install semgrep      ##"
  echo "#################################################################"
  echo ""
fi

XSS_TS='export function render(pane: HTMLElement, userText: string) {
  pane.innerHTML = userText;
}'
SAFE_TS='export function render(pane: HTMLElement, userText: string) {
  pane.textContent = userText;
}'

# mk_repo <dir> <hookfile>: fresh repo w/ local identity + one benign commit landed
# BEFORE the hook is installed, then the given hook installed as pre-commit and the
# BL-131 ruleset placed at .semgrep/ (the emitted hook references it by --config).
mk_repo() {
  local d="$1" hook="$2"
  mkdir -p "$d/.semgrep"
  ( cd "$d" \
      && git init -q \
      && git config user.email "bl132@test.invalid" \
      && git config user.name  "BL-132 Test" \
      && echo "# bl132" > README.md \
      && git add README.md \
      && git commit -q -m "chore: init" ) || return 1
  [ -f "$RULESET_SRC" ] && cp "$RULESET_SRC" "$d/.semgrep/soif-dom-sinks.yml"
  cp "$hook" "$d/.git/hooks/pre-commit"
  chmod +x "$d/.git/hooks/pre-commit"
}

head_of() { ( cd "$1" && git rev-parse HEAD 2>/dev/null ) || echo none; }
not_enforced() { grep -q "SAST NOT ENFORCED" "$1"; }

# stage_then_overwrite <repo> <staged-content> <worktree-content> <log>
#   Stage app.ts with <staged-content>, then overwrite the worktree copy with
#   <worktree-content> WITHOUT re-staging, then attempt the commit. Echoes
#   COMMITTED|REFUSED, git rc in the log.
stage_then_overwrite() {
  local d="$1" staged="$2" worktree="$3" log="$4"
  printf '%s\n' "$staged"   > "$d/app.ts"
  ( cd "$d" && git add app.ts )
  printf '%s\n' "$worktree" > "$d/app.ts"     # worktree now DIVERGES from the index
  if ( cd "$d" && git commit -m "feat: app" ) >"$log" 2>&1; then echo "COMMITTED"; else echo "REFUSED"; fi
}

# ── T-index-blocks-staged-vuln ───────────────────────────────────────────────
echo "=== T-index-blocks-staged-vuln ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-index-blocks-staged-vuln" "semgrep ABSENT — index-scan blocking UNPROVEN (skip, not pass)"
else
  R1="$TOPTMP/blk"
  if ! mk_repo "$R1" "$EMITTED"; then
    fail_ "T-index-blocks-staged-vuln" "repo setup failed"
  else
    H0="$(head_of "$R1")"
    V="$(stage_then_overwrite "$R1" "$XSS_TS" "$SAFE_TS" "$TOPTMP/o1")"
    H1="$(head_of "$R1")"
    if [ "$V" = "COMMITTED" ]; then
      if not_enforced "$TOPTMP/o1"; then
        skip_ "T-index-blocks-staged-vuln" "scanner did not run (registry unreachable?) — blocking UNPROVEN here"
      else
        fail_ "T-index-blocks-staged-vuln" "staged innerHTML XSS COMMITTED CLEAN — the WORKTREE (clean) was scanned, not the index (BL-132): $(grep -E '\[OK\]|\[BLOCKED\]' "$TOPTMP/o1" | head -1)"
      fi
    elif ! grep -q "\[BLOCKED\]" "$TOPTMP/o1"; then
      fail_ "T-index-blocks-staged-vuln" "refused but without [BLOCKED] (wrong reason): $(tail -3 "$TOPTMP/o1" | tr '\n' '|')"
    elif [ "$H0" != "$H1" ]; then
      fail_ "T-index-blocks-staged-vuln" "non-zero exit but HEAD MOVED"
    elif ! grep -q "app.ts" "$TOPTMP/o1"; then
      fail_ "T-index-blocks-staged-vuln" "blocked, but the finding did not name the real path app.ts — temp-prefix mapping missing"
    else
      pass "T-index-blocks-staged-vuln: STAGED bytes scanned, commit refused, HEAD unmoved, real path shown"
    fi
  fi
fi

# ── T-index-no-false-block ───────────────────────────────────────────────────
echo "=== T-index-no-false-block ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-index-no-false-block" "semgrep ABSENT — skip, not pass"
else
  R2="$TOPTMP/nofalse"
  if ! mk_repo "$R2" "$EMITTED"; then
    fail_ "T-index-no-false-block" "repo setup failed"
  else
    H0="$(head_of "$R2")"
    V="$(stage_then_overwrite "$R2" "$SAFE_TS" "$XSS_TS" "$TOPTMP/o2")"
    H1="$(head_of "$R2")"
    if not_enforced "$TOPTMP/o2"; then
      skip_ "T-index-no-false-block" "scanner did not run — case vacuous here"
    elif [ "$V" = "REFUSED" ]; then
      fail_ "T-index-no-false-block" "CLEAN staged content was BLOCKED because the hook scanned the UNSTAGED worktree vuln (false block): $(grep -E '\[BLOCKED\]' "$TOPTMP/o2" | head -1)"
    elif [ "$H0" = "$H1" ]; then
      fail_ "T-index-no-false-block" "committed verdict but HEAD did not move"
    elif ! grep -q "\[OK\] semgrep: SAST ran" "$TOPTMP/o2"; then
      fail_ "T-index-no-false-block" "landed but no [OK] receipt — cannot prove the scan RAN on the clean staged bytes"
    else
      pass "T-index-no-false-block: unstaged worktree vuln ignored, clean staged bytes scanned + landed"
    fi
  fi
fi

# ── T-notrun-contract-intact (semgrep OFF the PATH) ──────────────────────────
# Mirror bl112's honest shim: replace every PATH entry holding semgrep with a
# symlink mirror of all its OTHER entries, so semgrep — and only semgrep — is gone.
echo "=== T-notrun-contract-intact ==="
NOSEMGREP_PATH=""
build_nosemgrep_path() {
  local mirrors="$TOPTMP/nosemgrep" n=0 d np="" entry base
  rm -rf "$mirrors"; mkdir -p "$mirrors"
  printf '%s' "$PATH" | tr ':' '\n' > "$mirrors/.pathlist"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    if [ -x "$d/semgrep" ]; then
      n=$((n + 1)); mkdir -p "$mirrors/$n"
      for entry in "$d"/*; do
        [ -e "$entry" ] || continue
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
build_nosemgrep_path
if PATH="$NOSEMGREP_PATH" command -v semgrep >/dev/null 2>&1; then
  fail_ "T-notrun-contract-intact" "PATH shim failed — semgrep still resolves; contract UNPROVEN"
elif ! PATH="$NOSEMGREP_PATH" command -v git >/dev/null 2>&1; then
  fail_ "T-notrun-contract-intact" "PATH shim removed git too — would prove nothing"
else
  R3="$TOPTMP/notrun"
  if ! mk_repo "$R3" "$EMITTED"; then
    fail_ "T-notrun-contract-intact" "repo setup failed"
  else
    H0="$(head_of "$R3")"
    printf '%s\n' "$XSS_TS" > "$R3/app.ts"
    ( cd "$R3" && git add app.ts )
    if ( cd "$R3" && PATH="$NOSEMGREP_PATH" git commit -m "feat: app (no semgrep)" ) >"$TOPTMP/o3" 2>&1; then V=COMMITTED; else V=REFUSED; fi
    H1="$(head_of "$R3")"
    if [ "$V" = "COMMITTED" ] && [ "$H0" != "$H1" ] \
       && grep -qF '[WARN] semgrep not found' "$TOPTMP/o3" \
       && grep -qF 'SAST NOT ENFORCED' "$TOPTMP/o3" \
       && ! grep -qF '[BLOCKED]' "$TOPTMP/o3"; then
      pass "T-notrun-contract-intact: semgrep absent -> commit LANDS, SAST NOT ENFORCED shown, never blocked"
    else
      fail_ "T-notrun-contract-intact" "verdict=$V warn=$(grep -cF '[WARN] semgrep not found' "$TOPTMP/o3") loud=$(grep -cF 'SAST NOT ENFORCED' "$TOPTMP/o3") blocked=$(grep -cF '[BLOCKED]' "$TOPTMP/o3"); log: $(tail -4 "$TOPTMP/o3" | tr '\n' '|')"
    fi
  fi
fi

# ── T-mutation-index-scan ────────────────────────────────────────────────────
# Revert exactly the index-scan: point semgrep back at the worktree paths
# ("${soif_staged[@]}") instead of the temp index tree. The staged-vuln/clean-
# worktree commit must then LAND (RED) — the clean worktree scans clean. Restore
# the temp-tree target and the same commit is REFUSED (GREEN).
echo "=== T-mutation-index-scan ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-mutation-index-scan" "semgrep ABSENT — mutation UNPROVEN (skip, not pass)"
else
  MUT="$TOPTMP/mut-hook"
  # shellcheck disable=SC2016
  sed 's#--severity=ERROR --error "\$soif_idx_tree"#--severity=ERROR --error "\${soif_staged[@]}"#' "$EMITTED" > "$MUT"
  if ! grep -qF '# BL-132-INDEX-SCAN' "$MUT"; then
    fail_ "T-mutation-index-scan" "mutation removed the marker — it must attack BEHAVIOUR, not the marker"
  elif diff -q "$EMITTED" "$MUT" >/dev/null 2>&1; then
    fail_ "T-mutation-index-scan" "MIS-TARGETED — the temp-tree scan target anchor is not present exactly as expected"
  elif ! bash -n "$MUT" 2>/dev/null; then
    fail_ "T-mutation-index-scan" "mutated hook has a syntax error — a broken mutant proves nothing"
  else
    RM="$TOPTMP/mut-repo"
    if ! mk_repo "$RM" "$MUT"; then
      fail_ "T-mutation-index-scan" "mut repo setup failed"
    else
      H0="$(head_of "$RM")"
      RED="$(stage_then_overwrite "$RM" "$XSS_TS" "$SAFE_TS" "$TOPTMP/red")"
      # restore: same fixture, real (temp-tree) hook.
      RG="$TOPTMP/mut-repo-green"
      mk_repo "$RG" "$EMITTED"
      GREEN="$(stage_then_overwrite "$RG" "$XSS_TS" "$SAFE_TS" "$TOPTMP/green")"
      if not_enforced "$TOPTMP/red" || not_enforced "$TOPTMP/green"; then
        skip_ "T-mutation-index-scan" "scanner did not run (registry unreachable?) — mutation direction unprovable here"
      elif [ "$RED" = "COMMITTED" ] && [ "$GREEN" = "REFUSED" ]; then
        pass "T-mutation-index-scan: worktree-scan LANDS the staged vuln (RED); index-scan REFUSES it (GREEN)"
      else
        fail_ "T-mutation-index-scan" "expected RED=COMMITTED/GREEN=REFUSED; got RED=$RED GREEN=$GREEN; red: $(tail -3 "$TOPTMP/red" | tr '\n' '|'); green: $(tail -3 "$TOPTMP/green" | tr '\n' '|')"
      fi
    fi
  fi
fi

echo ""
if [ "$SKIPPED" -gt 0 ]; then echo "!! $SKIPPED case(s) SKIPPED — skipped != passed."; fi
echo "Results: $PASSED passed, $FAILED failed ($SKIPPED skipped)"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
