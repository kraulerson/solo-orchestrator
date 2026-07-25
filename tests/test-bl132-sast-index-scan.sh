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
# A DOM-sink caught by the LOCAL ruleset (soif-insert-adjacent-html), valid as both
# .ts and .js so it can be staged under .min.js. Used by the ignored-paths regression.
IA_SINK='function render(el, u) {
  el.insertAdjacentHTML("beforeend", u);
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
    elif grep -qE '/var/folders/|/tmp/tmp\.' "$TOPTMP/o1"; then
      fail_ "T-index-blocks-staged-vuln" "the raw mktemp temp-tree prefix leaked into the operator-facing output — the path-mapping sed did not run (F3); a bare 'app.ts' grep passes anyway because the temp path contains the basename"
    else
      pass "T-index-blocks-staged-vuln: STAGED bytes scanned, commit refused, HEAD unmoved, real repo-relative path shown (no temp prefix)"
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

# ── T-index-ignored-paths-scanned (verifier F1 regression) ───────────────────
# Staged sinks under semgrep's default-ignored paths (tests/ dist/ *.min.js) MUST be
# scanned. Pointing semgrep at the materialized DIRECTORY re-engaged its built-in
# .semgrepignore and silently skipped them (F1); FIX B (explicit file targets)
# restores coverage. RED (pre-FIX-B, directory scan): these COMMIT with [OK].
echo "=== T-index-ignored-paths-scanned ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-index-ignored-paths-scanned" "semgrep ABSENT — skip, not pass"
else
  R4="$TOPTMP/ignored"
  if ! mk_repo "$R4" "$EMITTED"; then
    fail_ "T-index-ignored-paths-scanned" "repo setup failed"
  else
    mkdir -p "$R4/tests" "$R4/dist"
    printf '%s\n' "$IA_SINK" > "$R4/tests/vuln.ts"
    printf '%s\n' "$IA_SINK" > "$R4/dist/payload.ts"
    printf '%s\n' "$IA_SINK" > "$R4/lib.min.js"
    H0="$(head_of "$R4")"
    if ( cd "$R4" && git add tests/vuln.ts dist/payload.ts lib.min.js && git commit -m "feat: ignored-path sinks" ) >"$TOPTMP/o4" 2>&1; then V=COMMITTED; else V=REFUSED; fi
    H1="$(head_of "$R4")"
    if [ "$V" = "COMMITTED" ]; then
      if not_enforced "$TOPTMP/o4"; then
        skip_ "T-index-ignored-paths-scanned" "scanner did not run (registry unreachable?) — coverage UNPROVEN here"
      else
        fail_ "T-index-ignored-paths-scanned" "sinks under tests/ dist/ *.min.js COMMITTED CLEAN — default .semgrepignore silently skipped them (verifier F1 regression): $(grep -E '\[OK\]|\[BLOCKED\]' "$TOPTMP/o4" | head -1)"
      fi
    elif ! grep -q "\[BLOCKED\]" "$TOPTMP/o4"; then
      fail_ "T-index-ignored-paths-scanned" "refused but without [BLOCKED] (wrong reason): $(tail -3 "$TOPTMP/o4" | tr '\n' '|')"
    elif [ "$H0" != "$H1" ]; then
      fail_ "T-index-ignored-paths-scanned" "non-zero exit but HEAD MOVED"
    elif ! grep -q 'tests/vuln.ts' "$TOPTMP/o4" || ! grep -q 'dist/payload.ts' "$TOPTMP/o4" || ! grep -q 'lib.min.js' "$TOPTMP/o4"; then
      fail_ "T-index-ignored-paths-scanned" "blocked, but not all three ignored-path sinks were NAMED — one was still skipped (found $(grep -cE 'tests/vuln\.ts|dist/payload\.ts|lib\.min\.js' "$TOPTMP/o4") of 3 refs)"
    elif grep -qE '/var/folders/|/tmp/tmp\.' "$TOPTMP/o4"; then
      fail_ "T-index-ignored-paths-scanned" "raw mktemp temp-tree prefix leaked into output (F3)"
    else
      pass "T-index-ignored-paths-scanned: sinks under tests/ dist/ *.min.js are ALL scanned + REFUSED (F1 regression closed)"
    fi
  fi
  # control: a src/ sink is REFUSED both before and after FIX B — anchors that the
  # hook DOES block when it sees a sink (so the ignored-path RED is meaningful).
  R4c="$TOPTMP/ignored-ctrl"
  if mk_repo "$R4c" "$EMITTED"; then
    mkdir -p "$R4c/src"
    printf '%s\n' "$IA_SINK" > "$R4c/src/ctrl.ts"
    if ( cd "$R4c" && git add src/ctrl.ts && git commit -m "feat: src sink" ) >"$TOPTMP/o4c" 2>&1; then Vc=COMMITTED; else Vc=REFUSED; fi
    if not_enforced "$TOPTMP/o4c"; then
      skip_ "T-index-ignored-paths-control" "scanner did not run — control vacuous here"
    elif [ "$Vc" = "REFUSED" ] && grep -q "\[BLOCKED\]" "$TOPTMP/o4c"; then
      pass "T-index-ignored-paths-control: a src/ sink is REFUSED (the hook blocks when it sees a sink)"
    else
      fail_ "T-index-ignored-paths-control" "src/ sink verdict=$Vc (want REFUSED): $(tail -3 "$TOPTMP/o4c" | tr '\n' '|')"
    fi
  fi
fi

# ── T-mutation-content-guard (F2: empty/partial materialize -> loud NOTRUN) ───
# The F2 size check turns an empty/partial materialization into a LOUD NOTRUN
# instead of scanning an empty file and passing [OK]. The GREEN direction fires
# BEFORE semgrep runs (no registry needed): force the materialization to write
# empty/partial dests and the content check must NOTRUN. The RED direction removes
# F2 so the empty scan passes [OK] silently (needs the registry, LOUD-SKIP if down).
echo "=== T-mutation-content-guard ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-mutation-content-guard" "semgrep ABSENT — skip, not pass"
else
  _idx_mutate() { awk -v old="$2" -v new="$3" '{p=index($0,old); if(p>0){$0=substr($0,1,p-1) new substr($0,p+length(old)); c++} print} END{if(c!=1) exit 3}' "$1"; }
  _cg_commit() {  # <hookfile> <log>
    local d; d="$(mktemp -d)"
    mk_repo "$d" "$1" >/dev/null 2>&1 || { rm -rf "$d"; return 9; }
    printf '%s\n' "$XSS_TS" > "$d/app.ts"
    ( cd "$d" && git add app.ts && git commit -m "feat: app" ) >"$2" 2>&1 || true
    rm -rf "$d"
  }
  cg_setup=1
  MEMPTY="$TOPTMP/cg-empty"
  _idx_mutate "$EMITTED" 'git cat-file blob ":$soif_p" > "$soif_idx_tree/$soif_p"' ': > "$soif_idx_tree/$soif_p"' > "$MEMPTY" || cg_setup=0
  MPART="$TOPTMP/cg-part"
  _idx_mutate "$EMITTED" 'git cat-file blob ":$soif_p" > "$soif_idx_tree/$soif_p"' 'git cat-file blob ":$soif_p" | head -c 3 > "$soif_idx_tree/$soif_p"' > "$MPART" || cg_setup=0
  # F2-removed variant of M-empty: drop exactly the three F2 CHECK lines (keep the
  # soif_idx_files+= collection), so the empty dest is scanned and passes [OK].
  MEMPTY_NOF2="$TOPTMP/cg-empty-nof2"
  awk '/soif_idx_want=/ {next} /soif_idx_got=/ {next} /soif_idx_ok=0; break; fi/ {next} {print}' "$MEMPTY" > "$MEMPTY_NOF2"
  if [ "$cg_setup" != "1" ]; then
    fail_ "T-mutation-content-guard" "MIS-TARGETED — the materialization anchor is not present exactly once"
  elif ! bash -n "$MEMPTY" 2>/dev/null || ! bash -n "$MPART" 2>/dev/null || ! bash -n "$MEMPTY_NOF2" 2>/dev/null; then
    fail_ "T-mutation-content-guard" "a content-guard mutant has a syntax error — a broken mutant proves nothing"
  elif grep -qF 'soif_idx_want=' "$MEMPTY_NOF2"; then
    fail_ "T-mutation-content-guard" "the F2-removal awk did not drop the content-check lines"
  else
    _cg_commit "$MEMPTY" "$TOPTMP/cg1"
    _cg_commit "$MPART" "$TOPTMP/cg2"
    _cg_commit "$MEMPTY_NOF2" "$TOPTMP/cg3"
    if ! not_enforced "$TOPTMP/cg1"; then
      fail_ "T-mutation-content-guard" "M-empty materialize did NOT go loud NOTRUN with F2 present — F2 is not catching the empty dest: $(tail -3 "$TOPTMP/cg1" | tr '\n' '|')"
    elif ! not_enforced "$TOPTMP/cg2"; then
      fail_ "T-mutation-content-guard" "M-partial materialize did NOT go loud NOTRUN with F2 present: $(tail -3 "$TOPTMP/cg2" | tr '\n' '|')"
    elif grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/cg3"; then
      pass "T-mutation-content-guard: empty+partial materialize -> loud NOTRUN WITH F2 (GREEN); F2 removed -> the empty scan passes [OK] silently (RED) — F2 is load-bearing"
    elif not_enforced "$TOPTMP/cg3"; then
      skip_ "T-mutation-content-guard" "F2 GREEN held (empty+partial -> NOTRUN); the F2-removed RED is unprovable here (scanner did not run on the empty-scan variant — registry unreachable?)"
    else
      fail_ "T-mutation-content-guard" "F2-removed empty materialize neither passed [OK] nor NOTRUN: $(tail -3 "$TOPTMP/cg3" | tr '\n' '|')"
    fi
  fi
fi

# ── T-mutation-index-scan ────────────────────────────────────────────────────
# Revert exactly the index-scan: point semgrep back at the worktree paths
# ("${soif_staged[@]}") instead of the EXPLICIT materialized index files. The
# staged-vuln/clean-worktree commit must then LAND (RED) — the clean worktree scans
# clean. Restore the index-files target and the same commit is REFUSED (GREEN).
# awk literal index()/substr() replace (not sed): the index-files target expansion
# ${soif_idx_files[@]+"${soif_idx_files[@]}"} is regex-hostile, so match it literally.
echo "=== T-mutation-index-scan ==="
if [ "$HAVE_SEMGREP" -eq 0 ]; then
  skip_ "T-mutation-index-scan" "semgrep ABSENT — mutation UNPROVEN (skip, not pass)"
else
  MUT="$TOPTMP/mut-hook"
  MUT_MIS=0
  awk -v old='--severity=ERROR --error ${soif_idx_files[@]+"${soif_idx_files[@]}"}' \
      -v new='--severity=ERROR --error "${soif_staged[@]}"' '
    { p=index($0, old); if(p>0){ $0=substr($0,1,p-1) new substr($0,p+length(old)); c++ } print }
    END { if(c!=1) exit 3 }
  ' "$EMITTED" > "$MUT" || MUT_MIS=1
  if [ "$MUT_MIS" = "1" ]; then
    fail_ "T-mutation-index-scan" "MIS-TARGETED — the index-files scan-target anchor is not present exactly once in the emitted hook"
  elif ! grep -qF '# BL-132-INDEX-SCAN' "$MUT"; then
    fail_ "T-mutation-index-scan" "mutation removed the marker — it must attack BEHAVIOUR, not the marker"
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
