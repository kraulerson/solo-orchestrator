#!/usr/bin/env bash
# tests/test-upgrade-sync-framework.sh — BL-099 SLICE-A regression suite.
#
# Covers scripts/upgrade-project.sh --sync-framework (same-tier refresh of the
# vendored gate scripts / helper libs / hooks / framework docs from the FRAMEWORK
# copy being run) and its --dry-run / --install-hooks / --apply-doc-updates /
# --confirm-doc-overwrite modifiers.
#
# CONSENT IS DRIVEN BY FLAGS, NOT BY A TTY (review round 1). Every run here is
# non-interactive, so the doc-apply consent path is exercised through the DECLARED
# CLI flags — --apply-doc-updates <skip|sidecar|overwrite> chooses the action and
# --confirm-doc-overwrite answers the destructive second consent — exactly the
# channel real scripted operators use. That is what lets T-doc-overwrite-confirm-
# declined / -accepted pin the # BL-099-CONFIRM gate without a pty, and what
# T-mutation-confirm mutates. The production guard is unchanged for real
# terminals: with a tty the gate still prompts via prompt_yes_no (default N).
#
# HERMETICITY: every run pins CDF_HOME to a nonexistent path (BL-001 CDF refresh
# gracefully skips — no clone, no network), configures a git identity in each
# fixture, unsets GITHUB_BASE_REF, feeds </dev/null + SOIF_NONINTERACTIVE=1 so no
# prompt is reachable, and creates NO real remotes. bash-3.2 safe. The suite
# READS the real init.sh (to derive the shipped set) but never EXECUTES it, so it
# stays fast-lane eligible (mirrors tests/test-scaffold-source-closure.sh).
#
# FAST-LANE JUSTIFICATION: registered in BOTH tests/full-project-test-suite.sh
# and the tests.yml `unit` list. It drives the real upgrade-project.sh against
# the real framework tree (a few file copies + a graceful CDF skip) and does NOT
# invoke init.sh — so it honours the no-init fast-lane invariant.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/upgrade-project.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Portable md5 of a single file (macOS `md5 -q`, Linux `md5sum`).
_md5file() {
  if command -v md5 >/dev/null 2>&1; then md5 -q "$1"
  else md5sum "$1" | awk '{print $1}'; fi
}

# ── MUTATION HARNESS (review round 2) ───────────────────────────────────────
# Round 1's mutation tests excised the marker LINE. That is fine when the marker
# rides on the load-bearing statement, but it proves nothing about a marker that
# rides on a comment — and a test that only asserts "the marker string is present"
# is a tautology. Round 2 therefore attacks the FUNCTION BODY and leaves the
# marker string in place: every mutation below verifies the marker still greps in
# the mutant, then proves behaviour broke anyway.
#
# _neuter_fn <file> <fn> <body> — replace fn's whole body with <body>, keeping the
# signature (and every marker comment in the file) untouched. bash-3.2 / BSD-awk
# safe; matches a `<fn>() {` header at column 0 and the closing `}` at column 0.
_neuter_fn() {
  local file="$1" fn="$2" body="$3" tmp
  tmp="$(mktemp)"
  awk -v fn="$fn" -v body="$body" '
    !mutated && index($0, fn "() {") == 1 { print; print "  " body; skip = 1; next }
    skip && $0 == "}" { print; skip = 0; mutated = 1; next }
    skip { next }
    { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
  chmod +x "$file"
}

# _extract_fn <file> <fn> — print fn's source (signature..closing brace) so a probe
# can exercise the REAL production function in isolation.
_extract_fn() {
  awk -v fn="$2" '
    index($0, fn "() {") == 1 { p = 1 }
    p { print }
    p && $0 == "}" { exit }
  ' "$1"
}

# True iff <file> still contains <marker> (used to prove the mutation attacked
# BEHAVIOUR, not the marker text — the anti-tautology check).
_has_marker() { grep -qF "$2" "$1"; }

# ── SILENT-SUCCESS `cp` STUB (review round 3) ───────────────────────────────
# WHY THIS EXISTS. _bl099_write_ok is `[ "$1" -eq 0 ] && cmp -s "$2" "$3"` — a
# status check AND a byte re-read. Round 2's two write-failure fixtures make the
# destination unwritable with `chmod`, so `cp` EXITS NON-ZERO and the status half
# alone already catches them: the round-3 verifier deleted the `cmp -s` half and
# all 28 tests stayed green. The byte re-read — the whole reason the function is
# belt-and-braces — was pinned by nothing.
#
# The hole that leaves is REACHABLE: a `cp` that RETURNS 0 WITHOUT LANDING THE
# BYTES. Short write, ENOSPC, a destination that swallows writes, a shadowed `cp`
# earlier on PATH. Status-only would print [OK] and exit 0 for a doc that was never
# written — this repo's canonical silent-success defect class. `chmod` cannot
# produce that state (an unwritable target makes cp FAIL, loudly), so no fixture
# built out of file modes can ever pin the byte re-read. A lying `cp` can.
#
# MECHANISM (chosen over the alternatives, and deliberately surgical). The house
# mock-CLI pattern (tests/host-drivers/mock-cli.sh) is "PATH-prepend a stub binary",
# and that is what this is — but a blanket `cp` stub is too blunt: upgrade-project.sh
# also cp's the whole vendored script set and the BL-088 skill files, so a global
# no-op cp would sabotage half the sync and the assertions would no longer be about
# doc-apply. So the stub is keyed on its DESTINATION: it lies about exactly one
# target and delegates to the REAL cp for every other destination, leaving the rest
# of the sync genuinely functional.
#
# Keyed on a destination GLOB, not an absolute path, on purpose: on macOS `mktemp -d`
# hands back /var/folders/… while the script's own PROJECT_ROOT resolves through the
# /private/var/… symlink, so an absolute-path equality test would silently never
# match and the test would pass vacuously. The `.hits` witness file below is the
# backstop for that entire class of mis-wiring — every test asserts the stub was
# ACTUALLY exercised, so a stub that failed to take effect fails the test instead of
# quietly making it green.
#
# HERMETIC + SCOPED: the stub directory is only ever prepended to PATH inside the
# sync subshell (_run_sync_stubcp). The test harness's own file operations —
# make_fake_framework's `cp -R`, the fixtures, _md5file — run in the parent shell
# with the untouched PATH and are completely unaffected.
#
# _mk_silent_cp <bindir> <destination-glob>
_mk_silent_cp() {
  local bindir="$1" glob="$2" real_cp
  real_cp="$(command -v cp)"
  mkdir -p "$bindir"
  {
    printf '%s\n'  '#!/usr/bin/env bash'
    printf '%s\n'  '# TEST STUB (BL-099 review round 3): a `cp` that reports SUCCESS (exit 0)'
    printf '%s\n'  '# while writing NOTHING, for one destination only. Real cp for all others.'
    printf 'REAL_CP=%q\n'     "$real_cp"
    printf 'VICTIM_GLOB=%q\n' "$glob"
    printf 'HITS=%q\n'        "$bindir/.hits"
    printf '%s\n'  'dst=""; for a in "$@"; do dst="$a"; done   # last positional = destination (bash-3.2 safe)'
    printf '%s\n'  'case "$dst" in'
    printf '%s\n'  '  $VICTIM_GLOB) printf "%s\n" "$dst" >> "$HITS"; exit 0 ;;   # <- the lie: rc=0, zero bytes'
    printf '%s\n'  'esac'
    printf '%s\n'  'exec "$REAL_CP" "$@"'
  } > "$bindir/cp"
  chmod +x "$bindir/cp"
}

# True iff the silent-success stub actually intercepted a write (guards against a
# vacuous pass — see the mis-wiring note above).
_silent_cp_fired() { [ -s "$1/.hits" ]; }

# Run a sync with the silent-success `cp` stub first on PATH, against an explicit
# script (so the mutation test can point at a mutated framework copy).
# _run_sync_stubcp <projdir> <script> <stub-bindir> [args...]
_run_sync_stubcp() {
  local proj="$1" script="$2" bindir="$3"; shift 3
  ( cd "$proj" && unset GITHUB_BASE_REF; PATH="$bindir:$PATH" CDF_HOME="$proj/.no-such-cdf" SOIF_NONINTERACTIVE=1 \
      "$script" --sync-framework "$@" </dev/null 2>&1 )
}

# Every CLAUDE.md* / PROJECT_INTAKE.md* entry in the project root, one per line.
# The rendered-doc fence promises this set never grows.
_rendered_artifacts() {
  ( cd "$1" && ls -1 2>/dev/null | grep -E '^(CLAUDE\.md|PROJECT_INTAKE\.md)' | LC_ALL=C sort ) || true
}

# Portable octal file mode (GNU-first, BSD fallback) — house portability rule.
_file_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || echo "?"
}

# Deterministic fingerprint of every file under a dir (relpath + content md5,
# LC_ALL=C sorted). "(absent)" when the dir is missing. Detects content
# changes, additions AND deletions.
_tree_fingerprint() {
  local d="$1"
  [ -d "$d" ] || { echo "(absent)"; return; }
  ( cd "$d" && find . -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
      printf '%s:%s\n' "$f" "$(_md5file "$f")"
    done )
}

# Fingerprint the FULL mutated surface a sync could touch (BL-099 plan):
# scripts/ docs/reference/ CLAUDE.md PROJECT_INTAKE.md .claude/ .git/hooks/.
_surface_fp() {
  local p="$1"
  echo "== scripts =="   ; _tree_fingerprint "$p/scripts"
  echo "== docsref =="   ; _tree_fingerprint "$p/docs/reference"
  echo "== dotclaude ==" ; _tree_fingerprint "$p/.claude"
  echo "== githooks =="  ; _tree_fingerprint "$p/.git/hooks"
  echo "== claudemd =="  ; [ -f "$p/CLAUDE.md" ] && _md5file "$p/CLAUDE.md" || echo "(absent)"
  echo "== intake =="    ; [ -f "$p/PROJECT_INTAKE.md" ] && _md5file "$p/PROJECT_INTAKE.md" || echo "(absent)"
}

# ── Fixture: a minimal, current-vintage upgradeable project. ────────────────
# $1 = dir, $2 = language (default python). Manifest HAS enforcement_level so the
# BL-030 backfill is a no-op (keeps the fixture stable across a real sync).
mk_project() {
  local dir="$1" lang="${2:-python}"
  mkdir -p "$dir/.claude" "$dir/scripts/lib" "$dir/docs/reference"
  printf '%s\n' '{"track":"light","deployment":"personal","poc_mode":null,"current_phase":1,"phases":{}}' > "$dir/.claude/phase-state.json"
  printf '%s\n' '{"frameworkVersion":"1.0.0","host":"github","mode":"personal","deployment":"personal","poc_mode":null,"enforcement_level":"strict"}' > "$dir/.claude/manifest.json"
  printf '%s\n' "{\"context\":{\"track\":\"light\",\"platform\":\"web\",\"language\":\"$lang\"}}" > "$dir/.claude/tool-preferences.json"
  ( cd "$dir" && git init -q && git config user.email t@t.local && git config user.name T \
      && unset GITHUB_BASE_REF && git add -A && git commit -q -m init ) >/dev/null 2>&1
}

# Run a sync from within a project against the REAL framework tree.
# Usage: run_sync <projdir> [extra-args...]
run_sync() {
  local proj="$1"; shift
  ( cd "$proj" && unset GITHUB_BASE_REF; CDF_HOME="$proj/.no-such-cdf" SOIF_NONINTERACTIVE=1 \
      "$SCRIPT" --sync-framework "$@" </dev/null 2>&1 )
}

# Build a self-contained fake FRAMEWORK checkout (real files, own git history)
# so pin/-dirty and marker-mutation tests are deterministic and don't touch the
# real repo. Copies the subset a sync reads: init.sh, scripts/, docs/,
# templates/generated/, templates/project-intake.md.
make_fake_framework() {
  local fw="$1"
  mkdir -p "$fw/templates"
  cp "$REPO_ROOT/init.sh" "$fw/init.sh"
  cp -R "$REPO_ROOT/scripts" "$fw/scripts"
  cp -R "$REPO_ROOT/docs" "$fw/docs"
  cp -R "$REPO_ROOT/templates/generated" "$fw/templates/generated"
  cp "$REPO_ROOT/templates/project-intake.md" "$fw/templates/project-intake.md"
  ( cd "$fw" && git init -q && git config user.email fw@t.local && git config user.name FW \
      && unset GITHUB_BASE_REF && git add -A && git commit -q -m "fake framework HEAD" ) >/dev/null 2>&1
}

echo "== tests/test-upgrade-sync-framework.sh =="

# ── T-sync-refreshes-stale-script ───────────────────────────────────────────
t_sync_refreshes_stale_script() {
  local T; T=$(mktemp -d); local P="$T/proj"; mk_project "$P"
  printf '#!/usr/bin/env bash\necho OLD-STALE\n' > "$P/scripts/check-phase-gate.sh"
  chmod +x "$P/scripts/check-phase-gate.sh"
  local out; out=$(run_sync "$P")
  if [ "$(grep -c 'OLD-STALE' "$P/scripts/check-phase-gate.sh")" = "0" ] \
     && cmp -s "$REPO_ROOT/scripts/check-phase-gate.sh" "$P/scripts/check-phase-gate.sh"; then
    pass "T-sync-refreshes-stale-script: stale vendored script refreshed to framework content"
  else
    fail_ "T-sync-refreshes-stale-script" "check-phase-gate.sh not refreshed; tail:\n$(echo "$out" | tail -6)"
  fi
  rm -rf "$T"
}

# ── T-exec-bit-probe: modes mirrored (exe→+x, lib→not +x) ───────────────────
t_exec_bit_probe() {
  local T; T=$(mktemp -d); local P="$T/proj"; mk_project "$P"
  # Remove a shipped executable + a shipped lib so both are freshly synced.
  rm -f "$P/scripts/check-phase-gate.sh" "$P/scripts/lib/helpers-core.sh"
  run_sync "$P" >/dev/null
  local exe_ok=n lib_ok=n
  [ -x "$P/scripts/check-phase-gate.sh" ] && exe_ok=y
  [ -f "$P/scripts/lib/helpers-core.sh" ] && [ ! -x "$P/scripts/lib/helpers-core.sh" ] && lib_ok=y
  if [ "$exe_ok" = y ] && [ "$lib_ok" = y ]; then
    pass "T-exec-bit-probe: newly-shipped executable landed +x; sourced lib stayed non-executable (mode mirrored)"
  else
    fail_ "T-exec-bit-probe" "exe_ok=$exe_ok (check-phase-gate should be +x); lib_ok=$lib_ok (helpers-core should NOT be +x)"
  fi
  rm -rf "$T"
}

# ── T-sync-self-copy-refused: project's OWN copy refuses, zero mutation ──────
t_sync_self_copy_refused() {
  local T; T=$(mktemp -d); local P="$T/proj"; mk_project "$P"
  # Give the project its own (new) upgrade-project.sh + libs, then run THAT copy.
  cp -R "$REPO_ROOT/scripts/." "$P/scripts/"
  local pre; pre=$(_surface_fp "$P")
  local out rc=0
  out=$( cd "$P" && unset GITHUB_BASE_REF; CDF_HOME="$P/.no-such-cdf" SOIF_NONINTERACTIVE=1 \
         "$P/scripts/upgrade-project.sh" --sync-framework </dev/null 2>&1 ) || rc=$?
  local post; post=$(_surface_fp "$P")
  if [ "$rc" = "0" ]; then
    fail_ "T-sync-self-copy-refused" "expected non-zero exit when run from the project's own scripts/ copy; rc=$rc"; rm -rf "$T"; return
  fi
  if ! echo "$out" | grep -qiF "must run from the FRAMEWORK checkout"; then
    fail_ "T-sync-self-copy-refused" "missing framework-copy refusal message; tail:\n$(echo "$out" | tail -8)"; rm -rf "$T"; return
  fi
  if [ "$pre" != "$post" ]; then
    fail_ "T-sync-self-copy-refused" "self-copy sync mutated the project surface (must be zero-mutation before the source-check)"; rm -rf "$T"; return
  fi
  pass "T-sync-self-copy-refused: project's own copy refused with framework-copy guidance; zero mutation"
  rm -rf "$T"
}

# ── T-sentinel-freezes-sync: sentinel present → block, full surface frozen ──
t_sentinel_freezes_sync() {
  local T; T=$(mktemp -d); local P="$T/proj"; mk_project "$P"
  printf '#!/usr/bin/env bash\necho OLD-STALE\n' > "$P/scripts/check-phase-gate.sh"
  printf '%s\n' 'stale CLAUDE' > "$P/CLAUDE.md"
  printf '%s\n' 'stale intake' > "$P/PROJECT_INTAKE.md"
  printf '%s\n' 'stale guide' > "$P/docs/reference/user-guide.md"
  printf '%s\n' '{"question":"Adopt sponsored POC?","offered_at":"2026-06-28T12:00:00Z","options":["yes","no"]}' > "$P/.claude/pending-approval.json"
  local pre; pre=$(_surface_fp "$P")
  local out rc=0; out=$(run_sync "$P") || rc=$?
  local post; post=$(_surface_fp "$P")
  if [ "$rc" = "0" ]; then
    fail_ "T-sentinel-freezes-sync" "expected non-zero exit with a pending-approval sentinel; rc=$rc"; rm -rf "$T"; return
  fi
  if ! echo "$out" | grep -qF "upgrade blocked — pending user decision"; then
    fail_ "T-sentinel-freezes-sync" "missing BL-015 sentinel deny message; tail:\n$(echo "$out" | tail -8)"; rm -rf "$T"; return
  fi
  if [ "$pre" != "$post" ]; then
    fail_ "T-sentinel-freezes-sync" "sentinel-blocked sync mutated the full surface (scripts/docs/CLAUDE.md/PROJECT_INTAKE.md/.claude/.git/hooks must all be byte-identical)"; rm -rf "$T"; return
  fi
  pass "T-sentinel-freezes-sync: pending-approval sentinel freezes the sync; full mutated surface byte-identical"
  rm -rf "$T"
}

# ── T-dry-run-mutates-nothing: old-vintage fixture, full surface frozen ──────
t_dry_run_mutates_nothing() {
  local T; T=$(mktemp -d); local P="$T/proj"; mk_project "$P"
  # OLD-VINTAGE: strip BL-030 manifest fields, drop last-checked-commit, remove
  # hooks, back-date a script — so a REAL sync's backfill WOULD mutate; dry-run
  # must not (exercises backfill-suppression).
  printf '%s\n' '{"frameworkVersion":"1.0.0","host":"github","mode":"personal"}' > "$P/.claude/manifest.json"
  rm -f "$P/.claude/last-checked-commit.txt"
  rm -rf "$P/.git/hooks"; mkdir -p "$P/.git/hooks"
  printf '#!/usr/bin/env bash\necho OLD-STALE\n' > "$P/scripts/check-phase-gate.sh"
  printf '%s\n' 'stale guide' > "$P/docs/reference/user-guide.md"
  ( cd "$P" && unset GITHUB_BASE_REF && git add -A && git commit -q -m vintage ) >/dev/null 2>&1
  local pre; pre=$(_surface_fp "$P")
  local out rc=0; out=$(run_sync "$P" --dry-run) || rc=$?
  local post; post=$(_surface_fp "$P")
  if [ "$rc" != "0" ]; then
    fail_ "T-dry-run-mutates-nothing" "dry-run exited non-zero; rc=$rc tail:\n$(echo "$out" | tail -8)"; rm -rf "$T"; return
  fi
  if [ "$pre" != "$post" ]; then
    fail_ "T-dry-run-mutates-nothing" "dry-run mutated the surface (must write NOTHING, incl. no backfill on the old-vintage fixture)"; rm -rf "$T"; return
  fi
  if ! echo "$out" | grep -qF "would sync"; then
    fail_ "T-dry-run-mutates-nothing" "dry-run did not report the drift it would apply (expected '[would sync]' lines)"; rm -rf "$T"; return
  fi
  # No stray tmp files left behind anywhere in the project.
  if find "$P" -name '*.tmp' 2>/dev/null | grep -q .; then
    fail_ "T-dry-run-mutates-nothing" "dry-run left .tmp files behind"; rm -rf "$T"; return
  fi
  pass "T-dry-run-mutates-nothing: --dry-run reports drift, writes nothing (old-vintage backfill suppressed), leaves no tmp files"
  rm -rf "$T"
}

# ── T-hook-refused-noninteractive-without-flag ──────────────────────────────
t_hook_refused_noninteractive_without_flag() {
  local T; T=$(mktemp -d); local P="$T/proj"; mk_project "$P" python
  run_sync "$P" >/dev/null   # no --install-hooks
  if [ -f "$P/.git/hooks/commit-msg" ]; then
    fail_ "T-hook-refused-noninteractive-without-flag" "commit-msg hook installed non-interactively WITHOUT --install-hooks (consent bypassed)"; rm -rf "$T"; return
  fi
  if [ -f "$P/.git/hooks/pre-commit" ]; then
    fail_ "T-hook-refused-noninteractive-without-flag" "pre-commit hook installed non-interactively WITHOUT --install-hooks"; rm -rf "$T"; return
  fi
  pass "T-hook-refused-noninteractive-without-flag: no hook installed non-interactively absent --install-hooks"
  rm -rf "$T"
}

# ── T-hook-backfill-consented: --install-hooks installs both hooks ──────────
t_hook_backfill_consented() {
  local T; T=$(mktemp -d); local P="$T/proj"; mk_project "$P" python
  run_sync "$P" --install-hooks >/dev/null
  local cm=n pc=n
  [ -f "$P/.git/hooks/commit-msg" ] && grep -qF "SOIF BL-072 TDD gate" "$P/.git/hooks/commit-msg" && cm=y
  [ -f "$P/.git/hooks/pre-commit" ] && grep -qF "SOIF pre-commit fallback" "$P/.git/hooks/pre-commit" && pc=y
  if [ "$cm" = y ] && [ "$pc" = y ]; then
    pass "T-hook-backfill-consented: --install-hooks installed the marked commit-msg + pre-commit hooks"
  else
    fail_ "T-hook-backfill-consented" "commit-msg=$cm pre-commit=$pc (both should be y)"
  fi
  rm -rf "$T"
}

# ── T-rust-no-hook-expected: rust language → no commit-msg hook, no prompt ───
t_rust_no_hook_expected() {
  local T; T=$(mktemp -d); local P="$T/proj"; mk_project "$P" rust
  local out; out=$(run_sync "$P" --install-hooks)
  if [ -f "$P/.git/hooks/commit-msg" ]; then
    fail_ "T-rust-no-hook-expected" "commit-msg hook installed for rust (empty test_pattern → must be skipped, matching init.sh's gate)"; rm -rf "$T"; return
  fi
  if ! echo "$out" | grep -qiF "not applicable"; then
    fail_ "T-rust-no-hook-expected" "expected a 'not applicable' notice for rust; tail:\n$(echo "$out" | tail -8)"; rm -rf "$T"; return
  fi
  pass "T-rust-no-hook-expected: rust (empty test_pattern) gets no commit-msg hook and no prompt"
  rm -rf "$T"
}

# ── T-hook-block-refresh-preserves-user-lines ───────────────────────────────
t_hook_block_refresh_preserves_user_lines() {
  local T; T=$(mktemp -d); local P="$T/proj"; mk_project "$P" python
  # Install a commit-msg hook with a STALE managed block + user lines outside it.
  mkdir -p "$P/.git/hooks"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' '# USER-CUSTOM-BEFORE line 1'
    printf '%s\n' ''
    printf '%s\n' '# >>> SOIF BL-072 TDD gate (commit-msg) — managed by init.sh'
    printf '%s\n' '# STALE-OLD-MANAGED-CONTENT (must be replaced)'
    printf '%s\n' '# <<< SOIF BL-072 TDD gate'
    printf '%s\n' '# USER-CUSTOM-AFTER line 2'
  } > "$P/.git/hooks/commit-msg"
  chmod +x "$P/.git/hooks/commit-msg"
  run_sync "$P" --install-hooks >/dev/null
  local hook="$P/.git/hooks/commit-msg"
  local before_ok=n after_ok=n stale_gone=n body_ok=n
  grep -qxF '# USER-CUSTOM-BEFORE line 1' "$hook" && before_ok=y
  grep -qxF '# USER-CUSTOM-AFTER line 2' "$hook" && after_ok=y
  grep -qF 'STALE-OLD-MANAGED-CONTENT' "$hook" || stale_gone=y
  grep -qF 'scripts/pre-commit-gate.sh --terminal-mode --tdd-only' "$hook" && body_ok=y
  if [ "$before_ok" = y ] && [ "$after_ok" = y ] && [ "$stale_gone" = y ] && [ "$body_ok" = y ]; then
    pass "T-hook-block-refresh-preserves-user-lines: stale managed block refreshed; user lines outside markers byte-preserved"
  else
    fail_ "T-hook-block-refresh-preserves-user-lines" "before=$before_ok after=$after_ok stale_gone=$stale_gone body=$body_ok"
  fi
  rm -rf "$T"
}

# ── T-legacy-unmarked-precommit-sidecar ─────────────────────────────────────
t_legacy_unmarked_precommit_sidecar() {
  local T; T=$(mktemp -d); local P="$T/proj"; mk_project "$P" python
  mkdir -p "$P/.git/hooks"
  printf '#!/usr/bin/env bash\n# my hand-rolled hook\nexit 0\n' > "$P/.git/hooks/pre-commit"
  chmod +x "$P/.git/hooks/pre-commit"
  local pre_md5; pre_md5=$(_md5file "$P/.git/hooks/pre-commit")
  run_sync "$P" --install-hooks >/dev/null
  local post_md5; post_md5=$(_md5file "$P/.git/hooks/pre-commit")
  if [ "$pre_md5" != "$post_md5" ]; then
    fail_ "T-legacy-unmarked-precommit-sidecar" "legacy UNMARKED pre-commit hook was overwritten in place (must never be)"; rm -rf "$T"; return
  fi
  if [ ! -f "$P/.git/hooks/pre-commit.new" ] || ! grep -qF 'SOIF pre-commit fallback' "$P/.git/hooks/pre-commit.new"; then
    fail_ "T-legacy-unmarked-precommit-sidecar" "expected a pre-commit.new sidecar carrying the managed hook"; rm -rf "$T"; return
  fi
  pass "T-legacy-unmarked-precommit-sidecar: legacy unmarked hook left byte-identical; managed hook offered as .new sidecar"
  rm -rf "$T"
}

# ── T-doc-apply-sidecar (reference doc) ─────────────────────────────────────
# Review round 1 (MAJOR-2): the apply channel is the DECLARED CLI flag
# --apply-doc-updates; the undeclared SOLO_SYNC_DOC_APPLY env var is gone.
t_doc_apply_sidecar() {
  local T; T=$(mktemp -d); local P="$T/proj"; mk_project "$P" python
  printf '%s\n' 'my customized user guide' > "$P/docs/reference/user-guide.md"
  local pre_md5; pre_md5=$(_md5file "$P/docs/reference/user-guide.md")
  run_sync "$P" --apply-doc-updates sidecar >/dev/null
  local post_md5; post_md5=$(_md5file "$P/docs/reference/user-guide.md")
  if [ "$pre_md5" != "$post_md5" ]; then
    fail_ "T-doc-apply-sidecar" "sidecar apply modified the original doc (must stay untouched)"; rm -rf "$T"; return
  fi
  if [ ! -f "$P/docs/reference/user-guide.md.new" ] || ! cmp -s "$REPO_ROOT/docs/user-guide.md" "$P/docs/reference/user-guide.md.new"; then
    fail_ "T-doc-apply-sidecar" "expected user-guide.md.new sidecar matching framework upstream"; rm -rf "$T"; return
  fi
  pass "T-doc-apply-sidecar: '--apply-doc-updates sidecar' writes <doc>.new; original untouched"
  rm -rf "$T"
}

# ── T-doc-noninteractive-no-flag-applies-nothing ────────────────────────────
# The approved spec's rule: a bare non-interactive sync NOTICES doc drift and
# applies NOTHING — no overwrite, no sidecar, no .bak.
t_doc_noninteractive_no_flag_applies_nothing() {
  local T; T=$(mktemp -d); local P="$T/proj"; mk_project "$P" python
  printf '%s\n' 'my customized user guide' > "$P/docs/reference/user-guide.md"
  local pre_md5; pre_md5=$(_md5file "$P/docs/reference/user-guide.md")
  local out; out=$(run_sync "$P")            # no --apply-doc-updates at all
  local post_md5; post_md5=$(_md5file "$P/docs/reference/user-guide.md")
  if [ "$pre_md5" != "$post_md5" ]; then
    fail_ "T-doc-noninteractive-no-flag-applies-nothing" "bare non-interactive sync MUTATED a drifted reference doc (must be notice-only)"; rm -rf "$T"; return
  fi
  if ls "$P/docs/reference/"user-guide.md.new "$P/docs/reference/"user-guide.md.bak.* >/dev/null 2>&1; then
    fail_ "T-doc-noninteractive-no-flag-applies-nothing" "bare non-interactive sync wrote a .new/.bak artifact (must apply nothing)"; rm -rf "$T"; return
  fi
  if ! echo "$out" | grep -qF "notice only — not applied"; then
    fail_ "T-doc-noninteractive-no-flag-applies-nothing" "expected the notice-only line naming --apply-doc-updates; tail:\n$(echo "$out" | tail -8)"; rm -rf "$T"; return
  fi
  pass "T-doc-noninteractive-no-flag-applies-nothing: bare non-interactive sync notices drift and applies nothing (no flag, no env var)"
  rm -rf "$T"
}

# ── T-doc-overwrite-confirm-declined (MAJOR-1) ──────────────────────────────
# Confirm answered N (overwrite requested, consent NOT given): the doc must stay
# byte-identical, no .bak may be written, and a clear 'skipped' line is printed.
# This is the test the shipped double-confirm had NONE of — the verifier deleted
# the confirm and every test stayed green.
t_doc_overwrite_confirm_declined() {
  local T; T=$(mktemp -d); local P="$T/proj"; mk_project "$P" python
  printf '%s\n' 'my customized user guide' > "$P/docs/reference/user-guide.md"
  local pre_md5; pre_md5=$(_md5file "$P/docs/reference/user-guide.md")
  # overwrite REQUESTED, consent WITHHELD (no --confirm-doc-overwrite) → declined.
  local out rc=0; out=$(run_sync "$P" --apply-doc-updates overwrite) || rc=$?
  local post_md5; post_md5=$(_md5file "$P/docs/reference/user-guide.md")
  if [ "$rc" != "0" ]; then
    fail_ "T-doc-overwrite-confirm-declined" "a declined overwrite must not fail the sync; rc=$rc tail:\n$(echo "$out" | tail -8)"; rm -rf "$T"; return
  fi
  if [ "$pre_md5" != "$post_md5" ]; then
    fail_ "T-doc-overwrite-confirm-declined" "UNCONFIRMED overwrite mutated the doc (the # BL-099-CONFIRM consent gate did not hold)"; rm -rf "$T"; return
  fi
  if ls "$P/docs/reference/"user-guide.md.bak.* >/dev/null 2>&1; then
    fail_ "T-doc-overwrite-confirm-declined" "a .bak was written for a declined overwrite (nothing may be touched)"; rm -rf "$T"; return
  fi
  if ! echo "$out" | grep -qF "skipped user-guide.md — in-place overwrite NOT confirmed"; then
    fail_ "T-doc-overwrite-confirm-declined" "expected an explicit 'skipped … overwrite NOT confirmed' line; tail:\n$(echo "$out" | tail -8)"; rm -rf "$T"; return
  fi
  pass "T-doc-overwrite-confirm-declined: consent withheld → doc byte-identical, no .bak, explicit 'skipped … NOT confirmed' line"
  rm -rf "$T"
}

# ── T-doc-overwrite-confirm-accepted (MAJOR-1) ──────────────────────────────
# Confirm answered Y (--confirm-doc-overwrite): the doc IS replaced with upstream
# AND a dated .bak holds the exact pre-overwrite bytes. (Supersedes the shipped
# T-doc-apply-overwrite-backs-up, whose assertions are a subset of these.)
t_doc_overwrite_confirm_accepted() {
  local T; T=$(mktemp -d); local P="$T/proj"; mk_project "$P" python
  printf '%s\n' 'my customized user guide' > "$P/docs/reference/user-guide.md"
  local old_md5; old_md5=$(_md5file "$P/docs/reference/user-guide.md")
  run_sync "$P" --apply-doc-updates overwrite --confirm-doc-overwrite >/dev/null
  local bak; bak=$(ls "$P/docs/reference/"user-guide.md.bak.* 2>/dev/null | head -1)
  if ! cmp -s "$REPO_ROOT/docs/user-guide.md" "$P/docs/reference/user-guide.md"; then
    fail_ "T-doc-overwrite-confirm-accepted" "confirmed overwrite did not replace the doc with framework upstream"; rm -rf "$T"; return
  fi
  if [ -z "$bak" ] || [ "$(_md5file "$bak")" != "$old_md5" ]; then
    fail_ "T-doc-overwrite-confirm-accepted" "expected a .bak.<date> holding the exact pre-overwrite bytes"; rm -rf "$T"; return
  fi
  case "$bak" in
    *.bak.[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) : ;;
    *) fail_ "T-doc-overwrite-confirm-accepted" "backup '$bak' is not a dated .bak.<YYYY-MM-DD>"; rm -rf "$T"; return ;;
  esac
  pass "T-doc-overwrite-confirm-accepted: consent given → doc updated to upstream AND dated .bak preserves the prior bytes"
  rm -rf "$T"
}

# ── T-doc-overwrite-backup-refusal (MAJOR-2c: never overwrite unbacked) ─────
# The backup MUST land before the original is touched. A read-only docs/reference
# still permits truncating the EXISTING doc, so this is the real hazard: cp of the
# .bak fails, and a naive implementation would overwrite anyway. Expect: loud
# refusal, doc untouched, no .bak, non-zero exit.
t_doc_overwrite_backup_refusal() {
  if [ "$(id -u)" = "0" ]; then
    pass "T-doc-overwrite-backup-refusal: skipped (running as root — mode bits do not restrict root)"; return
  fi
  local T; T=$(mktemp -d); local P="$T/proj"; mk_project "$P" python
  printf '%s\n' 'my customized user guide' > "$P/docs/reference/user-guide.md"
  local pre_md5; pre_md5=$(_md5file "$P/docs/reference/user-guide.md")
  chmod 500 "$P/docs/reference"     # no new files may be created; the doc itself stays writable
  local out rc=0
  out=$(run_sync "$P" --apply-doc-updates overwrite --confirm-doc-overwrite) || rc=$?
  local post_md5; post_md5=$(_md5file "$P/docs/reference/user-guide.md")
  chmod 755 "$P/docs/reference"
  if [ "$pre_md5" != "$post_md5" ]; then
    fail_ "T-doc-overwrite-backup-refusal" "doc was overwritten even though its backup could NOT be written (never overwrite unbacked)"; rm -rf "$T"; return
  fi
  if ls "$P/docs/reference/"user-guide.md.bak.* >/dev/null 2>&1; then
    fail_ "T-doc-overwrite-backup-refusal" "a .bak exists — the fixture did not actually block backup creation"; rm -rf "$T"; return
  fi
  if ! echo "$out" | grep -qF "REFUSING to overwrite"; then
    fail_ "T-doc-overwrite-backup-refusal" "expected a loud 'REFUSING to overwrite' line; tail:\n$(echo "$out" | tail -8)"; rm -rf "$T"; return
  fi
  if [ "$rc" = "0" ]; then
    fail_ "T-doc-overwrite-backup-refusal" "sync exited 0 after refusing an overwrite — the refusal must never be silent"; rm -rf "$T"; return
  fi
  pass "T-doc-overwrite-backup-refusal: unwritable backup → doc untouched, no .bak, loud REFUSING line, non-zero exit"
  rm -rf "$T"
}

# ── T-doc-overwrite-write-failure-is-loud (round 2, MAJOR-A) ────────────────
# The backup lands, and THEN the write fails (the doc itself is read-only, its
# directory is not). Round 1's `cp "$src" "$pfile"` was unchecked and the driver
# ran each doc as `… || true`, so this printed "[OK] overwrote user-guide.md" and
# exited 0 — the operator was told a doc was updated when it was not. Expect: a
# loud [FAIL] naming the doc, the ORIGINAL byte-intact, the dated backup KEPT, no
# [OK] "overwrote" line, and a non-zero exit.
t_doc_overwrite_write_failure_is_loud() {
  if [ "$(id -u)" = "0" ]; then
    pass "T-doc-overwrite-write-failure-is-loud: skipped (running as root — mode bits do not restrict root)"; return
  fi
  local T; T=$(mktemp -d); local P="$T/proj"; mk_project "$P" python
  local doc="$P/docs/reference/user-guide.md"
  printf '%s\n' 'my customized user guide' > "$doc"
  local pre_md5; pre_md5=$(_md5file "$doc")
  chmod 444 "$doc"                     # dir writable (backup CAN be taken); file unwritable (write CANNOT land)
  local out rc=0
  out=$(run_sync "$P" --apply-doc-updates overwrite --confirm-doc-overwrite) || rc=$?
  local post_md5; post_md5=$(_md5file "$doc")
  local bak; bak=$(ls "$P/docs/reference/"user-guide.md.bak.* 2>/dev/null | head -1)
  chmod 644 "$doc" 2>/dev/null || true
  if [ "$pre_md5" != "$post_md5" ]; then
    fail_ "T-doc-overwrite-write-failure-is-loud" "the original was modified by a FAILED overwrite (it must be left byte-intact)"; rm -rf "$T"; return
  fi
  if ! echo "$out" | grep -qF "FAILED to overwrite user-guide.md"; then
    fail_ "T-doc-overwrite-write-failure-is-loud" "no loud [FAIL] line naming the doc + the operation; tail:\n$(echo "$out" | tail -10)"; rm -rf "$T"; return
  fi
  if echo "$out" | grep -qF "overwrote user-guide.md"; then
    fail_ "T-doc-overwrite-write-failure-is-loud" "printed an [OK] 'overwrote' line for a write that never landed (silent success)"; rm -rf "$T"; return
  fi
  if [ -z "$bak" ] || [ "$(_md5file "$bak")" != "$pre_md5" ]; then
    fail_ "T-doc-overwrite-write-failure-is-loud" "the dated backup taken before the failed write must remain, holding the original bytes (got '$bak')"; rm -rf "$T"; return
  fi
  if [ "$rc" = "0" ]; then
    fail_ "T-doc-overwrite-write-failure-is-loud" "sync exited 0 after a doc write FAILED — the failure must reach the summary AND the exit code"; rm -rf "$T"; return
  fi
  pass "T-doc-overwrite-write-failure-is-loud: unwritable destination → loud [FAIL], original byte-intact, backup kept, no [OK], non-zero exit"
  rm -rf "$T"
}

# ── T-doc-sidecar-write-failure-is-loud (round 2, MAJOR-A) ──────────────────
# The sidecar `cp` was unchecked too: an unwritable target printed "[OK] wrote
# sidecar …" for a file that does not exist, and the run exited 0.
t_doc_sidecar_write_failure_is_loud() {
  if [ "$(id -u)" = "0" ]; then
    pass "T-doc-sidecar-write-failure-is-loud: skipped (running as root — mode bits do not restrict root)"; return
  fi
  local T; T=$(mktemp -d); local P="$T/proj"; mk_project "$P" python
  local doc="$P/docs/reference/user-guide.md"
  printf '%s\n' 'my customized user guide' > "$doc"
  local pre_md5; pre_md5=$(_md5file "$doc")
  chmod 500 "$P/docs/reference"        # no NEW file may be created here → the .new sidecar cannot land
  local out rc=0
  out=$(run_sync "$P" --apply-doc-updates sidecar) || rc=$?
  chmod 755 "$P/docs/reference"
  local post_md5; post_md5=$(_md5file "$doc")
  if [ "$pre_md5" != "$post_md5" ]; then
    fail_ "T-doc-sidecar-write-failure-is-loud" "the original doc was modified by a failed SIDECAR write (it must never be touched)"; rm -rf "$T"; return
  fi
  if [ -f "$doc.new" ]; then
    fail_ "T-doc-sidecar-write-failure-is-loud" "a .new sidecar exists — the fixture did not actually block sidecar creation"; rm -rf "$T"; return
  fi
  if ! echo "$out" | grep -qF "FAILED to write the sidecar"; then
    fail_ "T-doc-sidecar-write-failure-is-loud" "no loud [FAIL] line for the failed sidecar write; tail:\n$(echo "$out" | tail -10)"; rm -rf "$T"; return
  fi
  if echo "$out" | grep -qF "wrote sidecar"; then
    fail_ "T-doc-sidecar-write-failure-is-loud" "printed an [OK] 'wrote sidecar' line for a sidecar that does not exist (silent success)"; rm -rf "$T"; return
  fi
  if [ "$rc" = "0" ]; then
    fail_ "T-doc-sidecar-write-failure-is-loud" "sync exited 0 after the sidecar write FAILED — the failure must reach the summary AND the exit code"; rm -rf "$T"; return
  fi
  pass "T-doc-sidecar-write-failure-is-loud: unwritable sidecar target → loud [FAIL], original untouched, no [OK], non-zero exit"
  rm -rf "$T"
}

# ── T-doc-overwrite-write-silently-fails-is-caught (round 3, MAJOR) ─────────
# THE FIXTURE THE ROUND-2 SUITE WAS MISSING. Both round-2 write-failure tests use
# `chmod` to make the destination unwritable, so `cp` exits NON-ZERO and the
# `[ "$1" -eq 0 ]` half of _bl099_write_ok catches them on its own. This one drives
# a `cp` that EXITS 0 AND COPIES NOTHING — the short-write / ENOSPC / shadowed-cp
# shape — where the status is a lie and the byte re-read (`cmp -s`) is the ONLY
# thing between the operator and a false "[OK] your doc was updated".
#
# Both mutating branches are exercised, because they fail through different code:
#   (a) sidecar   — `cp src → <doc>.new` lies; nothing lands; must refuse loudly.
#   (b) overwrite — the BACKUP uses the real cp (it lands and verifies), and then
#       `cp src → <doc>` lies. The restore-from-backup cp is stubbed too, which is
#       realistic and harmless: the doc was never written, so it still holds the
#       operator's original bytes and the code's own `cmp -s "$bak" "$pfile"`
#       confirms it and says so.
# In BOTH: loud [FAIL] naming the doc, non-zero exit, NO [OK] line for that doc,
# and the operator's original left byte-intact.
t_doc_overwrite_write_silently_fails_is_caught() {
  local T; T=$(mktemp -d)

  # ── (a) SIDECAR: the `.new` write reports success and lands nothing. ──
  local Ps="$T/ps"; mk_project "$Ps" python
  local sdoc="$Ps/docs/reference/user-guide.md"
  printf '%s\n' 'my customized user guide' > "$sdoc"
  local spre; spre=$(_md5file "$sdoc")
  local sbin="$T/bin-sidecar"; _mk_silent_cp "$sbin" '*/user-guide.md.new'
  local sout src=0
  sout=$(_run_sync_stubcp "$Ps" "$SCRIPT" "$sbin" --apply-doc-updates sidecar) || src=$?

  if ! _silent_cp_fired "$sbin"; then
    fail_ "T-doc-overwrite-write-silently-fails-is-caught" "(sidecar) the silent-success cp stub was never invoked — the fixture did not actually shadow cp, so this test would have passed vacuously"; rm -rf "$T"; return
  fi
  if [ -f "$sdoc.new" ]; then
    fail_ "T-doc-overwrite-write-silently-fails-is-caught" "(sidecar) a .new sidecar exists — the stub was supposed to write nothing"; rm -rf "$T"; return
  fi
  if [ "$(_md5file "$sdoc")" != "$spre" ]; then
    fail_ "T-doc-overwrite-write-silently-fails-is-caught" "(sidecar) the operator's original doc was modified by a failed sidecar write"; rm -rf "$T"; return
  fi
  if ! echo "$sout" | grep -qF "FAILED to write the sidecar"; then
    fail_ "T-doc-overwrite-write-silently-fails-is-caught" "(sidecar) cp exited 0 with nothing on disk and the run did NOT complain — the byte re-read in _bl099_write_ok is not catching a lying cp; tail:\n$(echo "$sout" | tail -10)"; rm -rf "$T"; return
  fi
  if echo "$sout" | grep -qF "wrote sidecar"; then
    fail_ "T-doc-overwrite-write-silently-fails-is-caught" "(sidecar) printed an [OK] 'wrote sidecar' line for a sidecar that does not exist (silent success)"; rm -rf "$T"; return
  fi
  if [ "$src" = "0" ]; then
    fail_ "T-doc-overwrite-write-silently-fails-is-caught" "(sidecar) sync exited 0 after a write that never landed"; rm -rf "$T"; return
  fi

  # ── (b) OVERWRITE: backup lands for real; the in-place write reports success
  #        and lands nothing. ──
  local Po="$T/po"; mk_project "$Po" python
  local odoc="$Po/docs/reference/user-guide.md"
  printf '%s\n' 'my customized user guide' > "$odoc"
  local opre; opre=$(_md5file "$odoc")
  local obin="$T/bin-overwrite"; _mk_silent_cp "$obin" '*/user-guide.md'
  local oout orc=0
  oout=$(_run_sync_stubcp "$Po" "$SCRIPT" "$obin" --apply-doc-updates overwrite --confirm-doc-overwrite) || orc=$?
  local obak; obak=$(ls "$Po/docs/reference/"user-guide.md.bak.* 2>/dev/null | head -1)

  if ! _silent_cp_fired "$obin"; then
    fail_ "T-doc-overwrite-write-silently-fails-is-caught" "(overwrite) the silent-success cp stub was never invoked — fixture mis-wired, the test would have passed vacuously"; rm -rf "$T"; return
  fi
  if [ "$(_md5file "$odoc")" != "$opre" ]; then
    fail_ "T-doc-overwrite-write-silently-fails-is-caught" "(overwrite) the operator's original doc changed — the stub wrote nothing, so it must be byte-identical"; rm -rf "$T"; return
  fi
  if [ -z "$obak" ] || [ "$(_md5file "$obak")" != "$opre" ]; then
    fail_ "T-doc-overwrite-write-silently-fails-is-caught" "(overwrite) the dated backup must exist and hold the original bytes (the backup cp is NOT stubbed — it must have really landed); got '$obak'"; rm -rf "$T"; return
  fi
  if ! echo "$oout" | grep -qF "FAILED to overwrite user-guide.md"; then
    fail_ "T-doc-overwrite-write-silently-fails-is-caught" "(overwrite) cp exited 0 with nothing on disk and the run did NOT complain — the byte re-read in _bl099_write_ok is not catching a lying cp; tail:\n$(echo "$oout" | tail -10)"; rm -rf "$T"; return
  fi
  if echo "$oout" | grep -qF "overwrote user-guide.md"; then
    fail_ "T-doc-overwrite-write-silently-fails-is-caught" "(overwrite) printed an [OK] 'overwrote' line for a write that never landed (silent success)"; rm -rf "$T"; return
  fi
  if [ "$orc" = "0" ]; then
    fail_ "T-doc-overwrite-write-silently-fails-is-caught" "(overwrite) sync exited 0 after a write that never landed"; rm -rf "$T"; return
  fi

  pass "T-doc-overwrite-write-silently-fails-is-caught: a cp that EXITS 0 AND WRITES NOTHING is caught in BOTH the sidecar and the overwrite branch — loud [FAIL] naming the doc, no [OK], original byte-intact, backup kept, non-zero exit. Only the byte re-read (cmp -s) can see this; the exit-status check cannot."
  rm -rf "$T"
}

# ── T-doc-apply-flag-usage-errors (MAJOR-2a: declared, hard-validated) ──────
t_doc_apply_flag_usage_errors() {
  local T; T=$(mktemp -d); local P="$T/proj"; mk_project "$P" python
  local bad_val=n bare_flag=n no_sync_apply=n no_sync_confirm=n rc

  rc=0; local o1; o1=$(run_sync "$P" --apply-doc-updates clobber) || rc=$?
  [ "$rc" != "0" ] && echo "$o1" | grep -qiF "invalid --apply-doc-updates value" && bad_val=y

  rc=0; local o2; o2=$(run_sync "$P" --apply-doc-updates) || rc=$?
  [ "$rc" != "0" ] && echo "$o2" | grep -qiF "invalid --apply-doc-updates value" && bare_flag=y

  # sync-only: both flags must be rejected on the tier-change path.
  rc=0; local o3
  o3=$( cd "$P" && unset GITHUB_BASE_REF; CDF_HOME="$P/.no" SOIF_NONINTERACTIVE=1 \
        "$SCRIPT" --track standard --apply-doc-updates overwrite </dev/null 2>&1 ) || rc=$?
  [ "$rc" != "0" ] && echo "$o3" | grep -qiF "only valid with --sync-framework" && no_sync_apply=y

  rc=0; local o4
  o4=$( cd "$P" && unset GITHUB_BASE_REF; CDF_HOME="$P/.no" SOIF_NONINTERACTIVE=1 \
        "$SCRIPT" --track standard --confirm-doc-overwrite </dev/null 2>&1 ) || rc=$?
  [ "$rc" != "0" ] && echo "$o4" | grep -qiF "only valid with --sync-framework" && no_sync_confirm=y

  if [ "$bad_val" = y ] && [ "$bare_flag" = y ] && [ "$no_sync_apply" = y ] && [ "$no_sync_confirm" = y ]; then
    pass "T-doc-apply-flag-usage-errors: unknown/missing --apply-doc-updates value is a hard usage error; both doc flags are refused without --sync-framework"
  else
    fail_ "T-doc-apply-flag-usage-errors" "bad_val=$bad_val bare_flag=$bare_flag no_sync_apply=$no_sync_apply no_sync_confirm=$no_sync_confirm (all should be y)"
  fi
  rm -rf "$T"
}

# ── T-rendered-doc-never-applied (guards Karl's edge) ───────────────────────
# Round 1 (MAJOR-2b) asserted the # BL-099-DOC-GUARD holds under overwrite+confirm.
# Round 2 (MAJOR-B) found the hole that assertion missed: `--apply-doc-updates
# sidecar` reached the RENDERED docs through the notice and wrote
# <doc>.upstream-template.new BESIDE them, contradicting --help and the user guide
# ("notice-only under EVERY flag combination"). So the fence is now asserted under
# EVERY apply flag, and on the whole NAMESPACE — not just the two files: after a
# sync, no file whose name begins with CLAUDE.md / PROJECT_INTAKE.md may exist
# that did not exist before (no .new, no .bak, no .upstream-template.new).
t_rendered_doc_never_applied() {
  local combos_desc combo ok=y detail=""
  for combo in "sidecar" "overwrite" "overwrite --confirm-doc-overwrite"; do
    local T; T=$(mktemp -d); local P="$T/proj"; mk_project "$P" python
    printf '%s\n' '# My heavily customized CLAUDE.md — DO NOT OVERWRITE' > "$P/CLAUDE.md"
    printf '%s\n' '# My heavily customized PROJECT_INTAKE.md' > "$P/PROJECT_INTAKE.md"
    local pre_md5 pre_intake pre_ls
    pre_md5=$(_md5file "$P/CLAUDE.md"); pre_intake=$(_md5file "$P/PROJECT_INTAKE.md")
    pre_ls=$(_rendered_artifacts "$P")
    # shellcheck disable=SC2086
    local out; out=$(run_sync "$P" --install-hooks --apply-doc-updates $combo)
    local post_md5 post_intake post_ls
    post_md5=$(_md5file "$P/CLAUDE.md"); post_intake=$(_md5file "$P/PROJECT_INTAKE.md")
    post_ls=$(_rendered_artifacts "$P")
    if [ "$pre_md5" != "$post_md5" ] || [ "$pre_intake" != "$post_intake" ]; then
      ok=n; detail="a RENDERED doc was MUTATED under '--apply-doc-updates $combo'"
    elif [ "$pre_ls" != "$post_ls" ]; then
      ok=n; detail="'--apply-doc-updates $combo' created a new CLAUDE.md*/PROJECT_INTAKE.md* artifact — rendered docs are notice-only, nothing may be written beside them. before:[$(echo "$pre_ls" | tr '\n' ' ')] after:[$(echo "$post_ls" | tr '\n' ' ')]"
    elif ! echo "$out" | grep -qF "RENDERED from a template"; then
      ok=n; detail="'--apply-doc-updates $combo': missing the rendered-doc template notice; tail:\n$(echo "$out" | tail -10)"
    fi
    rm -rf "$T"
    [ "$ok" = y ] || break
  done
  combos_desc="sidecar / overwrite / overwrite+confirm"
  if [ "$ok" = y ]; then
    pass "T-rendered-doc-never-applied: under $combos_desc, CLAUDE.md + PROJECT_INTAKE.md are byte-identical AND no new CLAUDE.md*/PROJECT_INTAKE.md* artifact appears; template notice still emitted (assisted apply is BL-101)"
  else
    fail_ "T-rendered-doc-never-applied" "$detail"
  fi
}

# ── T-hook-mode-preserved (MINOR-3) ─────────────────────────────────────────
# _bl099_replace_region rewrites through mktemp (0600) + mv, so without an
# explicit mode restore a 755 hook silently narrows (observed 755 → 711 after the
# caller's chmod +x). init.sh ships hooks 755 — a refresh must keep them 755, and
# a fresh install must land 755.
t_hook_mode_preserved() {
  local T; T=$(mktemp -d); local P="$T/proj"; mk_project "$P" python
  mkdir -p "$P/.git/hooks"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' '# >>> SOIF BL-072 TDD gate (commit-msg) — managed by init.sh'
    printf '%s\n' '# STALE-OLD-MANAGED-CONTENT (must be replaced)'
    printf '%s\n' '# <<< SOIF BL-072 TDD gate'
  } > "$P/.git/hooks/commit-msg"
  chmod 755 "$P/.git/hooks/commit-msg"
  run_sync "$P" --install-hooks >/dev/null
  local refreshed_mode; refreshed_mode=$(_file_mode "$P/.git/hooks/commit-msg")
  # Fresh install (both hooks absent) must land 755 as well.
  rm -f "$P/.git/hooks/commit-msg" "$P/.git/hooks/pre-commit"
  run_sync "$P" --install-hooks >/dev/null
  local fresh_cm fresh_pc
  fresh_cm=$(_file_mode "$P/.git/hooks/commit-msg")
  fresh_pc=$(_file_mode "$P/.git/hooks/pre-commit")
  if [ "$refreshed_mode" = "755" ] && [ "$fresh_cm" = "755" ] && [ "$fresh_pc" = "755" ]; then
    pass "T-hook-mode-preserved: managed-block refresh keeps a 755 hook at 755; fresh installs land 755 (no mktemp 0600 narrowing)"
  else
    fail_ "T-hook-mode-preserved" "refreshed commit-msg=$refreshed_mode (expect 755); fresh commit-msg=$fresh_cm pre-commit=$fresh_pc (expect 755)"
  fi
  rm -rf "$T"
}

# ── T-pin-stamped (+ CDF-preexists + dirty probe + init.sh birth-stamp) ─────
t_pin_stamped() {
  local T; T=$(mktemp -d)

  # (a) basic + CDF-manifest-preexists: soloFrameworkCommit added, CDF's
  #     frameworkCommit left intact and distinct.
  local Pc="$T/cdf"; mk_project "$Pc" python
  printf '%s\n' '{"frameworkVersion":"1.0.0","host":"github","mode":"personal","deployment":"personal","poc_mode":null,"enforcement_level":"strict","frameworkCommit":"CDFPIN0000"}' > "$Pc/.claude/manifest.json"
  local FWc="$T/fw-clean"; make_fake_framework "$FWc"
  ( cd "$Pc" && unset GITHUB_BASE_REF; CDF_HOME="$Pc/.no-such-cdf" SOIF_NONINTERACTIVE=1 \
      "$FWc/scripts/upgrade-project.sh" --sync-framework </dev/null 2>&1 ) >/dev/null
  local solo cdf clean_head
  solo=$(jq -r '.soloFrameworkCommit // ""' "$Pc/.claude/manifest.json")
  cdf=$(jq -r '.frameworkCommit // ""' "$Pc/.claude/manifest.json")
  clean_head=$(git -C "$FWc" rev-parse HEAD)
  if [ "$solo" != "$clean_head" ]; then
    fail_ "T-pin-stamped" "soloFrameworkCommit ('$solo') != clean framework HEAD ('$clean_head')"; rm -rf "$T"; return
  fi
  if [ "$cdf" != "CDFPIN0000" ]; then
    fail_ "T-pin-stamped" "CDF's frameworkCommit was clobbered ('$cdf') — the two pins must stay distinct"; rm -rf "$T"; return
  fi

  # (b) dirty-clone probe: framework has an uncommitted change → pin is -dirty.
  local Pd="$T/dirty"; mk_project "$Pd" python
  local FWd="$T/fw-dirty"; make_fake_framework "$FWd"
  printf '\n# dirtying the framework clone\n' >> "$FWd/init.sh"   # tracked-file edit, uncommitted
  ( cd "$Pd" && unset GITHUB_BASE_REF; CDF_HOME="$Pd/.no-such-cdf" SOIF_NONINTERACTIVE=1 \
      "$FWd/scripts/upgrade-project.sh" --sync-framework </dev/null 2>&1 ) >/dev/null
  local dpin; dpin=$(jq -r '.soloFrameworkCommit // ""' "$Pd/.claude/manifest.json")
  case "$dpin" in
    *-dirty) : ;;
    *) fail_ "T-pin-stamped" "dirty framework clone did not produce a '-dirty' pin (got '$dpin')"; rm -rf "$T"; return ;;
  esac

  # (c) init.sh birth-stamp probe (STATIC — no init.sh execution): the
  #     soloFrameworkCommit jq write exists AFTER the manifest heredoc (outside
  #     both branches of the if/else).
  if ! grep -qF '.soloFrameworkCommit = $c' "$REPO_ROOT/init.sh"; then
    fail_ "T-pin-stamped" "init.sh has no soloFrameworkCommit birth-stamp"; rm -rf "$T"; return
  fi
  if ! awk '/^MANIFESTEOF$/{seen=1} seen && /\.soloFrameworkCommit = \$c/{print "OK"; exit}' "$REPO_ROOT/init.sh" | grep -qx OK; then
    fail_ "T-pin-stamped" "init.sh soloFrameworkCommit stamp is not positioned after the manifest if/else"; rm -rf "$T"; return
  fi

  pass "T-pin-stamped: sync pins soloFrameworkCommit (clean HEAD; CDF frameworkCommit untouched), '-dirty' on a dirty clone, and init.sh birth-stamps it after the manifest if/else"
  rm -rf "$T"
}

# ── T-mutation-sync: excise # BL-099-SYNC → refresh RED; restore → GREEN ─────
t_mutation_sync() {
  local T; T=$(mktemp -d)
  local TARGET_TOKEN='# BL-099-SYNC'
  if ! grep -qF "$TARGET_TOKEN" "$SCRIPT"; then
    fail_ "T-mutation-sync" "marker '$TARGET_TOKEN' not found in $SCRIPT (test needs updating)"; rm -rf "$T"; return
  fi
  local FW="$T/fw"; make_fake_framework "$FW"

  # Control: unmutated fake framework refreshes a stale script.
  local Pc="$T/pc"; mk_project "$Pc" python
  printf '#!/usr/bin/env bash\necho OLD-STALE\n' > "$Pc/scripts/check-phase-gate.sh"
  ( cd "$Pc" && unset GITHUB_BASE_REF; CDF_HOME="$Pc/.no" SOIF_NONINTERACTIVE=1 \
      "$FW/scripts/upgrade-project.sh" --sync-framework </dev/null 2>&1 ) >/dev/null
  local control_refreshed=n; [ "$(grep -c OLD-STALE "$Pc/scripts/check-phase-gate.sh")" = "0" ] && control_refreshed=y

  # Mutant A (BODY NEUTER — round 2): gut _bl099_sync_scripts, leave the marked
  # dispatch line (and the marker text) exactly where it is. Behaviour must still
  # break — proving the test tracks the CODE, not the comment.
  local FWb="$T/fwb"; make_fake_framework "$FWb"
  _neuter_fn "$FWb/scripts/upgrade-project.sh" _bl099_sync_scripts 'return 0'
  local body_marker_kept=n
  _has_marker "$FWb/scripts/upgrade-project.sh" "$TARGET_TOKEN" && body_marker_kept=y
  local Pb="$T/pb"; mk_project "$Pb" python
  printf '#!/usr/bin/env bash\necho OLD-STALE\n' > "$Pb/scripts/check-phase-gate.sh"
  ( cd "$Pb" && unset GITHUB_BASE_REF; CDF_HOME="$Pb/.no" SOIF_NONINTERACTIVE=1 \
      "$FWb/scripts/upgrade-project.sh" --sync-framework </dev/null 2>&1 ) >/dev/null || true
  local body_stale=n; [ "$(grep -c OLD-STALE "$Pb/scripts/check-phase-gate.sh")" = "1" ] && body_stale=y

  # Mutant B (marker excision): the dispatch line itself is removed.
  grep -vF "$TARGET_TOKEN" "$FW/scripts/upgrade-project.sh" > "$FW/scripts/upgrade-project.sh.mut"
  mv "$FW/scripts/upgrade-project.sh.mut" "$FW/scripts/upgrade-project.sh"
  chmod +x "$FW/scripts/upgrade-project.sh"
  local Pm="$T/pm"; mk_project "$Pm" python
  printf '#!/usr/bin/env bash\necho OLD-STALE\n' > "$Pm/scripts/check-phase-gate.sh"
  ( cd "$Pm" && unset GITHUB_BASE_REF; CDF_HOME="$Pm/.no" SOIF_NONINTERACTIVE=1 \
      "$FW/scripts/upgrade-project.sh" --sync-framework </dev/null 2>&1 ) >/dev/null || true
  local mutant_stale=n; [ "$(grep -c OLD-STALE "$Pm/scripts/check-phase-gate.sh")" = "1" ] && mutant_stale=y

  if [ "$control_refreshed" = y ] && [ "$mutant_stale" = y ] && [ "$body_stale" = y ] && [ "$body_marker_kept" = y ]; then
    pass "T-mutation-sync: real script refreshes stale vendored scripts; neutering _bl099_sync_scripts' BODY (marker '# BL-099-SYNC' still present) leaves them stale, as does excising the marked dispatch line (the sync is load-bearing, the comment is not the test)"
  else
    fail_ "T-mutation-sync" "control_refreshed=$control_refreshed (expect y); body_stale=$body_stale (expect y — a gutted _bl099_sync_scripts must NOT refresh); body_marker_kept=$body_marker_kept (expect y — the mutation must not have removed the marker); mutant_stale=$mutant_stale (expect y)"
  fi
  rm -rf "$T"
}

# ── T-mutation-doc-guard-body (round 2, MAJOR-B) ────────────────────────────
# The fence's BODY is what protects the rendered docs — not the marker comment.
# Neuter _bl099_doc_is_rendered (→ `return 1`), leave '# BL-099-DOC-GUARD' in the
# file, and CLAUDE.md must fall straight through into the apply machinery: with
# `--apply-doc-updates sidecar` the mutant writes CLAUDE.md.new, and with
# overwrite+confirm it CLOBBERS CLAUDE.md with the unrendered template. The real
# script does neither. That is the proof round 1's excision-only test could not
# give (it merely asserted a notice line disappeared).
t_mutation_doc_guard_body() {
  local T; T=$(mktemp -d)
  local TARGET_TOKEN='# BL-099-DOC-GUARD'
  local FW="$T/fw"; make_fake_framework "$FW"

  # Control: real script, sidecar requested → nothing written beside CLAUDE.md.
  local Pc="$T/pc"; mk_project "$Pc" python
  printf '%s\n' '# custom CLAUDE.md' > "$Pc/CLAUDE.md"
  ( cd "$Pc" && unset GITHUB_BASE_REF; CDF_HOME="$Pc/.no" SOIF_NONINTERACTIVE=1 \
      "$FW/scripts/upgrade-project.sh" --sync-framework --apply-doc-updates sidecar </dev/null 2>&1 ) >/dev/null || true
  local control_clean=n
  [ ! -e "$Pc/CLAUDE.md.new" ] && [ ! -e "$Pc/CLAUDE.md.upstream-template.new" ] && control_clean=y

  # Mutant: gut the guard predicate's body; the marker stays in the file.
  _neuter_fn "$FW/scripts/upgrade-project.sh" _bl099_doc_is_rendered 'return 1'
  local marker_kept=n; _has_marker "$FW/scripts/upgrade-project.sh" "$TARGET_TOKEN" && marker_kept=y
  local syntax_ok=n; bash -n "$FW/scripts/upgrade-project.sh" 2>/dev/null && syntax_ok=y

  # (a) sidecar → the mutant writes CLAUDE.md.new (the guard was the only fence).
  local Pm="$T/pm"; mk_project "$Pm" python
  printf '%s\n' '# custom CLAUDE.md' > "$Pm/CLAUDE.md"
  ( cd "$Pm" && unset GITHUB_BASE_REF; CDF_HOME="$Pm/.no" SOIF_NONINTERACTIVE=1 \
      "$FW/scripts/upgrade-project.sh" --sync-framework --apply-doc-updates sidecar </dev/null 2>&1 ) >/dev/null || true
  local mutant_sidecar=n; [ -f "$Pm/CLAUDE.md.new" ] && mutant_sidecar=y

  # (b) overwrite+confirm → the mutant clobbers CLAUDE.md with the raw template.
  local Po="$T/po"; mk_project "$Po" python
  printf '%s\n' '# custom CLAUDE.md' > "$Po/CLAUDE.md"
  local opre; opre=$(_md5file "$Po/CLAUDE.md")
  ( cd "$Po" && unset GITHUB_BASE_REF; CDF_HOME="$Po/.no" SOIF_NONINTERACTIVE=1 \
      "$FW/scripts/upgrade-project.sh" --sync-framework --apply-doc-updates overwrite --confirm-doc-overwrite </dev/null 2>&1 ) >/dev/null || true
  local mutant_clobbered=n; [ "$(_md5file "$Po/CLAUDE.md")" != "$opre" ] && mutant_clobbered=y

  if [ "$control_clean" = y ] && [ "$syntax_ok" = y ] && [ "$marker_kept" = y ] \
     && [ "$mutant_sidecar" = y ] && [ "$mutant_clobbered" = y ]; then
    pass "T-mutation-doc-guard-body: neutering _bl099_doc_is_rendered's BODY (marker '# BL-099-DOC-GUARD' still in the file) lets sidecar write CLAUDE.md.new and overwrite+confirm clobber CLAUDE.md — the real guard prevents both, so the fence is behaviour, not a comment"
  else
    fail_ "T-mutation-doc-guard-body" "control_clean=$control_clean (expect y — real script writes nothing beside CLAUDE.md under sidecar); syntax_ok=$syntax_ok marker_kept=$marker_kept (both expect y); mutant_sidecar=$mutant_sidecar mutant_clobbered=$mutant_clobbered (expect y — without the guard the rendered doc MUST be reachable)"
  fi
  rm -rf "$T"
}

# ── T-mutation-apply-status (round 2, MAJOR-A) ──────────────────────────────
# _bl099_write_ok (# BL-099-APPLY-STATUS) is the ONE status check every mutating
# doc write goes through. Neuter its BODY (→ `return 0`, i.e. "the write is always
# fine") — marker text untouched — and the two write-failure fixtures must both go
# RED: the run prints [OK] and exits 0 while nothing landed on disk. Restore →
# GREEN (the failure tests themselves cover the restored path).
t_mutation_apply_status() {
  if [ "$(id -u)" = "0" ]; then
    pass "T-mutation-apply-status: skipped (running as root — mode bits do not restrict root)"; return
  fi
  local T; T=$(mktemp -d)
  local TARGET_TOKEN='# BL-099-APPLY-STATUS'
  if ! _has_marker "$SCRIPT" "$TARGET_TOKEN"; then
    fail_ "T-mutation-apply-status" "marker '$TARGET_TOKEN' not found in $SCRIPT (test needs updating)"; rm -rf "$T"; return
  fi
  local FW="$T/fw"; make_fake_framework "$FW"

  # Control: real script — sidecar target unwritable → loud, non-zero.
  local Pc="$T/pc"; mk_project "$Pc" python
  printf '%s\n' 'my customized user guide' > "$Pc/docs/reference/user-guide.md"
  chmod 500 "$Pc/docs/reference"
  local crc=0 cout
  cout=$( cd "$Pc" && unset GITHUB_BASE_REF; CDF_HOME="$Pc/.no" SOIF_NONINTERACTIVE=1 \
      "$FW/scripts/upgrade-project.sh" --sync-framework --apply-doc-updates sidecar </dev/null 2>&1 ) || crc=$?
  chmod 755 "$Pc/docs/reference"
  local control_loud=n
  [ "$crc" != "0" ] && echo "$cout" | grep -qF "FAILED to write the sidecar" && control_loud=y

  # Mutant: gut the status checker. The marker string stays in the file.
  _neuter_fn "$FW/scripts/upgrade-project.sh" _bl099_write_ok 'return 0'
  local marker_kept=n; _has_marker "$FW/scripts/upgrade-project.sh" "$TARGET_TOKEN" && marker_kept=y
  local syntax_ok=n; bash -n "$FW/scripts/upgrade-project.sh" 2>/dev/null && syntax_ok=y

  # (a) sidecar failure → mutant claims success and exits 0.
  local Ps="$T/ps"; mk_project "$Ps" python
  printf '%s\n' 'my customized user guide' > "$Ps/docs/reference/user-guide.md"
  chmod 500 "$Ps/docs/reference"
  local src=0 sout
  sout=$( cd "$Ps" && unset GITHUB_BASE_REF; CDF_HOME="$Ps/.no" SOIF_NONINTERACTIVE=1 \
      "$FW/scripts/upgrade-project.sh" --sync-framework --apply-doc-updates sidecar </dev/null 2>&1 ) || src=$?
  chmod 755 "$Ps/docs/reference"
  local mutant_sidecar_silent=n
  [ "$src" = "0" ] && echo "$sout" | grep -qF "wrote sidecar" && [ ! -f "$Ps/docs/reference/user-guide.md.new" ] \
    && mutant_sidecar_silent=y

  # (b) overwrite failure → mutant claims success and exits 0.
  local Po="$T/po"; mk_project "$Po" python
  local odoc="$Po/docs/reference/user-guide.md"
  printf '%s\n' 'my customized user guide' > "$odoc"
  local opre; opre=$(_md5file "$odoc")
  chmod 444 "$odoc"
  local orc=0 oout
  oout=$( cd "$Po" && unset GITHUB_BASE_REF; CDF_HOME="$Po/.no" SOIF_NONINTERACTIVE=1 \
      "$FW/scripts/upgrade-project.sh" --sync-framework --apply-doc-updates overwrite --confirm-doc-overwrite </dev/null 2>&1 ) || orc=$?
  chmod 644 "$odoc" 2>/dev/null || true
  local mutant_overwrite_silent=n
  [ "$orc" = "0" ] && echo "$oout" | grep -qF "overwrote user-guide.md" \
    && [ "$(_md5file "$odoc")" = "$opre" ] && mutant_overwrite_silent=y

  if [ "$control_loud" = y ] && [ "$syntax_ok" = y ] && [ "$marker_kept" = y ] \
     && [ "$mutant_sidecar_silent" = y ] && [ "$mutant_overwrite_silent" = y ]; then
    pass "T-mutation-apply-status: neutering _bl099_write_ok's BODY (marker '# BL-099-APPLY-STATUS' still in the file) makes BOTH failed writes print [OK] and exit 0 with nothing on disk — the real check is what turns a failed apply into a loud non-zero run"
  else
    fail_ "T-mutation-apply-status" "control_loud=$control_loud (expect y — real script is loud + non-zero); syntax_ok=$syntax_ok marker_kept=$marker_kept (both expect y); mutant_sidecar_silent=$mutant_sidecar_silent mutant_overwrite_silent=$mutant_overwrite_silent (expect y — without the check the failures must go silent)"
  fi
  rm -rf "$T"
}

# ── T-mutation-write-ok-byteread (round 3, MAJOR) ───────────────────────────
# THE MUTATION THAT SURVIVED ROUND 2. T-mutation-apply-status guts _bl099_write_ok
# WHOLESALE (`return 0`), which kills both halves at once — so it proves the
# function exists, not that BOTH of its halves are load-bearing. The round-2
# verifier deleted only the SECOND half:
#
#     _bl099_write_ok() { [ "$1" -eq 0 ]; }        # cmp -s dropped, marker intact
#
# …and all 28 tests stayed green. This test kills exactly that mutant. It is
# strictly finer-grained than T-mutation-apply-status and BOTH must stay: this one
# pins the byte re-read, that one pins the status check + the function's existence.
#
# The marker (# BL-099-APPLY-STATUS) rides on the three CALL SITES, not inside the
# function, so it survives the neutering untouched — the anti-tautology check below
# proves the mutation attacked BEHAVIOUR, not a comment.
t_mutation_write_ok_byteread() {
  local T; T=$(mktemp -d)
  local TARGET_TOKEN='# BL-099-APPLY-STATUS'
  if ! _has_marker "$SCRIPT" "$TARGET_TOKEN"; then
    fail_ "T-mutation-write-ok-byteread" "marker '$TARGET_TOKEN' not found in $SCRIPT (test needs updating)"; rm -rf "$T"; return
  fi
  local FW="$T/fw"; make_fake_framework "$FW"
  local FWS="$FW/scripts/upgrade-project.sh"

  # Sanity: the REAL function must contain the byte re-read we are about to remove.
  if ! _extract_fn "$FWS" _bl099_write_ok | grep -qF 'cmp -s'; then
    fail_ "T-mutation-write-ok-byteread" "_bl099_write_ok no longer contains a 'cmp -s' byte re-read — this test mutates a line that is gone (test needs updating)"; rm -rf "$T"; return
  fi

  # ── CONTROL: real script, lying cp → loud + non-zero (GREEN). ──
  local Pc="$T/pc"; mk_project "$Pc" python
  printf '%s\n' 'my customized user guide' > "$Pc/docs/reference/user-guide.md"
  local cbin="$T/bin-c"; _mk_silent_cp "$cbin" '*/user-guide.md.new'
  local cout crc=0
  cout=$(_run_sync_stubcp "$Pc" "$FWS" "$cbin" --apply-doc-updates sidecar) || crc=$?
  local control_loud=n
  _silent_cp_fired "$cbin" && [ "$crc" != "0" ] && echo "$cout" | grep -qF "FAILED to write the sidecar" && control_loud=y

  # ── MUTANT: drop ONLY the `cmp -s` half. Marker text stays in the file. ──
  _neuter_fn "$FWS" _bl099_write_ok '[ "$1" -eq 0 ]'
  local marker_kept=n; _has_marker "$FWS" "$TARGET_TOKEN" && marker_kept=y
  local syntax_ok=n;   bash -n "$FWS" 2>/dev/null && syntax_ok=y
  local cmp_gone=n;    _extract_fn "$FWS" _bl099_write_ok | grep -qF 'cmp -s' || cmp_gone=y
  local status_kept=n; _extract_fn "$FWS" _bl099_write_ok | grep -qF '-eq 0' && status_kept=y

  # (a) sidecar: the mutant believes the lying cp → [OK] + exit 0 + no file.
  local Ps="$T/ps"; mk_project "$Ps" python
  printf '%s\n' 'my customized user guide' > "$Ps/docs/reference/user-guide.md"
  local sbin="$T/bin-s"; _mk_silent_cp "$sbin" '*/user-guide.md.new'
  local sout src=0
  sout=$(_run_sync_stubcp "$Ps" "$FWS" "$sbin" --apply-doc-updates sidecar) || src=$?
  local mutant_sidecar_silent=n
  [ "$src" = "0" ] && echo "$sout" | grep -qF "wrote sidecar" && [ ! -f "$Ps/docs/reference/user-guide.md.new" ] \
    && mutant_sidecar_silent=y

  # (b) overwrite: same lie, in place. Mutant reports "overwrote" for a doc whose
  #     bytes never changed.
  local Po="$T/po"; mk_project "$Po" python
  local odoc="$Po/docs/reference/user-guide.md"
  printf '%s\n' 'my customized user guide' > "$odoc"
  local opre; opre=$(_md5file "$odoc")
  local obin="$T/bin-o"; _mk_silent_cp "$obin" '*/user-guide.md'
  local oout orc=0
  oout=$(_run_sync_stubcp "$Po" "$FWS" "$obin" --apply-doc-updates overwrite --confirm-doc-overwrite) || orc=$?
  local mutant_overwrite_silent=n
  [ "$orc" = "0" ] && echo "$oout" | grep -qF "overwrote user-guide.md" \
    && [ "$(_md5file "$odoc")" = "$opre" ] && mutant_overwrite_silent=y

  if [ "$control_loud" = y ] && [ "$syntax_ok" = y ] && [ "$marker_kept" = y ] \
     && [ "$cmp_gone" = y ] && [ "$status_kept" = y ] \
     && [ "$mutant_sidecar_silent" = y ] && [ "$mutant_overwrite_silent" = y ]; then
    pass "T-mutation-write-ok-byteread: dropping ONLY the 'cmp -s' byte re-read from _bl099_write_ok (status check kept, marker '# BL-099-APPLY-STATUS' still in the file, syntax valid) makes a cp that exits 0 without writing print [OK] and exit 0 in BOTH branches — the byte re-read is load-bearing on its own, not redundant with the status check"
  else
    fail_ "T-mutation-write-ok-byteread" "control_loud=$control_loud (expect y — real script refuses a lying cp); syntax_ok=$syntax_ok marker_kept=$marker_kept cmp_gone=$cmp_gone status_kept=$status_kept (all expect y — the mutation must remove ONLY the byte re-read); mutant_sidecar_silent=$mutant_sidecar_silent mutant_overwrite_silent=$mutant_overwrite_silent (expect y — without the byte re-read the lying cp must go silently 'successful'). If the mutant is still LOUD, the byte re-read is not what catches this and the test is wrong; if the CONTROL is quiet, production regressed."
  fi
  rm -rf "$T"
}

# ── T-mutation-doc-guard: excise # BL-099-DOC-GUARD → rendered-doc RED ───────
t_mutation_doc_guard() {
  local T; T=$(mktemp -d)
  local TARGET_TOKEN='# BL-099-DOC-GUARD'
  if ! grep -qF "$TARGET_TOKEN" "$SCRIPT"; then
    fail_ "T-mutation-doc-guard" "marker '$TARGET_TOKEN' not found in $SCRIPT (test needs updating)"; rm -rf "$T"; return
  fi
  local FW="$T/fw"; make_fake_framework "$FW"

  # Control: rendered-doc notice emitted; CLAUDE.md untouched.
  local Pc="$T/pc"; mk_project "$Pc" python
  printf '%s\n' '# custom CLAUDE.md' > "$Pc/CLAUDE.md"
  local cpre; cpre=$(_md5file "$Pc/CLAUDE.md")
  local cout; cout=$( cd "$Pc" && unset GITHUB_BASE_REF; CDF_HOME="$Pc/.no" SOIF_NONINTERACTIVE=1 \
      "$FW/scripts/upgrade-project.sh" --sync-framework </dev/null 2>&1 )
  local cpost; cpost=$(_md5file "$Pc/CLAUDE.md")
  local control_notice=n; echo "$cout" | grep -qF "RENDERED from a template" && control_notice=y
  local control_untouched=n; [ "$cpre" = "$cpost" ] && control_untouched=y

  # Mutant: excise the guard so rendered docs fall through to verbatim handling
  # (the rendered notice is no longer emitted).
  grep -vF "$TARGET_TOKEN" "$FW/scripts/upgrade-project.sh" > "$FW/scripts/upgrade-project.sh.mut"
  mv "$FW/scripts/upgrade-project.sh.mut" "$FW/scripts/upgrade-project.sh"
  chmod +x "$FW/scripts/upgrade-project.sh"
  local Pm="$T/pm"; mk_project "$Pm" python
  printf '%s\n' '# custom CLAUDE.md' > "$Pm/CLAUDE.md"
  local mout; mout=$( cd "$Pm" && unset GITHUB_BASE_REF; CDF_HOME="$Pm/.no" SOIF_NONINTERACTIVE=1 \
      "$FW/scripts/upgrade-project.sh" --sync-framework </dev/null 2>&1 ) || true
  local mutant_notice_gone=n; echo "$mout" | grep -qF "RENDERED from a template" || mutant_notice_gone=y

  if [ "$control_notice" = y ] && [ "$control_untouched" = y ] && [ "$mutant_notice_gone" = y ]; then
    pass "T-mutation-doc-guard: guard routes CLAUDE.md to a template notice (untouched); excising '# BL-099-DOC-GUARD' drops the rendered-doc notice (guard is load-bearing)"
  else
    fail_ "T-mutation-doc-guard" "control_notice=$control_notice control_untouched=$control_untouched mutant_notice_gone=$mutant_notice_gone"
  fi
  rm -rf "$T"
}

# ── T-mutation-confirm: excise # BL-099-CONFIRM → declined overwrite RED ────
# The proof MAJOR-1 demanded: with the marked consent line removed, an overwrite
# that was NOT confirmed goes through anyway (the doc is clobbered). With it, the
# doc is byte-identical. RED → restore → GREEN, on a scratch framework copy.
t_mutation_confirm() {
  local T; T=$(mktemp -d)
  local TARGET_TOKEN='# BL-099-CONFIRM'
  if [ "$(grep -cF "$TARGET_TOKEN" "$SCRIPT")" = "0" ]; then
    fail_ "T-mutation-confirm" "marker '$TARGET_TOKEN' not found in $SCRIPT (test needs updating)"; rm -rf "$T"; return
  fi
  local FW="$T/fw"; make_fake_framework "$FW"
  local doc_body='my customized user guide'

  # Control: overwrite requested but NOT confirmed → doc untouched, no .bak.
  local Pc="$T/pc"; mk_project "$Pc" python
  printf '%s\n' "$doc_body" > "$Pc/docs/reference/user-guide.md"
  local cpre; cpre=$(_md5file "$Pc/docs/reference/user-guide.md")
  ( cd "$Pc" && unset GITHUB_BASE_REF; CDF_HOME="$Pc/.no" SOIF_NONINTERACTIVE=1 \
      "$FW/scripts/upgrade-project.sh" --sync-framework --apply-doc-updates overwrite </dev/null 2>&1 ) >/dev/null || true
  local control_untouched=n
  [ "$(_md5file "$Pc/docs/reference/user-guide.md")" = "$cpre" ] \
    && ! ls "$Pc/docs/reference/"user-guide.md.bak.* >/dev/null 2>&1 && control_untouched=y

  # Mutant: excise the marked consent line → the unconfirmed overwrite lands.
  grep -vF "$TARGET_TOKEN" "$FW/scripts/upgrade-project.sh" > "$FW/scripts/upgrade-project.sh.mut"
  mv "$FW/scripts/upgrade-project.sh.mut" "$FW/scripts/upgrade-project.sh"
  chmod +x "$FW/scripts/upgrade-project.sh"
  local Pm="$T/pm"; mk_project "$Pm" python
  printf '%s\n' "$doc_body" > "$Pm/docs/reference/user-guide.md"
  local mpre; mpre=$(_md5file "$Pm/docs/reference/user-guide.md")
  ( cd "$Pm" && unset GITHUB_BASE_REF; CDF_HOME="$Pm/.no" SOIF_NONINTERACTIVE=1 \
      "$FW/scripts/upgrade-project.sh" --sync-framework --apply-doc-updates overwrite </dev/null 2>&1 ) >/dev/null || true
  local mutant_clobbered=n
  [ "$(_md5file "$Pm/docs/reference/user-guide.md")" != "$mpre" ] && mutant_clobbered=y

  # Mutant B (BODY NEUTER — round 2): gut _bl099_overwrite_consent (→ always yes),
  # leaving the marked call site AND the marker text exactly where they are. The
  # unconfirmed overwrite must still land — the consent is the FUNCTION, not the
  # comment.
  local FWb="$T/fwb"; make_fake_framework "$FWb"
  _neuter_fn "$FWb/scripts/upgrade-project.sh" _bl099_overwrite_consent 'return 0'
  local body_marker_kept=n
  _has_marker "$FWb/scripts/upgrade-project.sh" "$TARGET_TOKEN" && body_marker_kept=y
  local Pb="$T/pb"; mk_project "$Pb" python
  printf '%s\n' "$doc_body" > "$Pb/docs/reference/user-guide.md"
  local bpre; bpre=$(_md5file "$Pb/docs/reference/user-guide.md")
  ( cd "$Pb" && unset GITHUB_BASE_REF; CDF_HOME="$Pb/.no" SOIF_NONINTERACTIVE=1 \
      "$FWb/scripts/upgrade-project.sh" --sync-framework --apply-doc-updates overwrite </dev/null 2>&1 ) >/dev/null || true
  local body_clobbered=n
  [ "$(_md5file "$Pb/docs/reference/user-guide.md")" != "$bpre" ] && body_clobbered=y

  if [ "$control_untouched" = y ] && [ "$mutant_clobbered" = y ] \
     && [ "$body_clobbered" = y ] && [ "$body_marker_kept" = y ]; then
    pass "T-mutation-confirm: the consent gate holds an unconfirmed overwrite; neutering _bl099_overwrite_consent's BODY (marker '# BL-099-CONFIRM' still present) clobbers the doc unconfirmed, as does excising the marked call site (the gate is load-bearing)"
  else
    fail_ "T-mutation-confirm" "control_untouched=$control_untouched (expect y — no consent, no write); body_clobbered=$body_clobbered (expect y — a gutted consent must let the overwrite land); body_marker_kept=$body_marker_kept (expect y); mutant_clobbered=$mutant_clobbered (expect y)"
  fi
  rm -rf "$T"
}

# ── CONSENT PROBE HARNESS (round 2, MINOR-C + MINOR-D) ──────────────────────
# The interactive branch of the three BL-099 consent paths is unreachable without
# a pty, which is exactly why two bugs hid there: --non-interactive was ignored,
# and the overwrite prompt's default-N was unpinned (flip it to Y and all 22 tests
# stayed green). The probe EXTRACTS the real production functions and stubs ONLY
# `_bl099_stdin_is_tty` — the single thing a pty-less test cannot answer. The
# shipped guard is untouched (it still calls the real `[ -t 0 ]`); everything the
# probe asserts is production code.
#   $1 = value of NON_INTERACTIVE ("true" / "false")   → prints the run's output
_consent_probe() {
  local ni="$1" probe; probe="$(mktemp)"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' 'set -uo pipefail'
    printf '%s\n' 'BOLD=""; NC=""'
    printf '%s\n' 'INSTALL_HOOKS=false; CONFIRM_DOC_OVERWRITE=false; APPLY_DOC_UPDATES=""; DOC_APPLY_FAILED=false'
    printf '%s\n' "NON_INTERACTIVE=$ni"
    printf '%s\n' 'print_info() { echo "INFO $1"; }'
    printf '%s\n' 'print_ok()   { echo "OK $1"; }'
    printf '%s\n' 'print_warn() { echo "WARN $1"; }'
    printf '%s\n' 'print_fail() { echo "FAIL $1"; }'
    printf '%s\n' 'prompt_yes_no() { echo "PROMPTED[$1][default=$2]"; return 1; }'
    # Review round 3 (MINOR): _bl099_doc_apply's interactive branch used to do a raw
    # `printf` + `read -r`; it now goes through the shared prompt_choice helper
    # (scripts/lib/helpers-core.sh). The probe stubs it exactly like prompt_yes_no —
    # same reason, same pattern: capture the ARGUMENTS the production function hands
    # the helper (a pty-less test cannot drive the real one), then return non-zero to
    # simulate "operator gave no valid answer". Production must fall back to SKIP.
    # NOTE the `>&2`: it mirrors the real helper, and it is load-bearing. prompt_choice
    # writes its prompt + option list to STDERR and ONLY the chosen option to STDOUT,
    # precisely because callers read the answer through `$(…)` — a prompt on stdout
    # would be swallowed by the command substitution and returned as the "choice".
    # A stub that echoes to stdout does not reproduce production and hides the prompt.
    printf '%s\n' 'prompt_choice() { local p="$1"; shift; echo "PROMPTED-CHOICE[$p][options: $*]" >&2; return 1; }'
    _extract_fn "$SCRIPT" _bl099_forced_noninteractive
    _extract_fn "$SCRIPT" _bl099_interactive
    _extract_fn "$SCRIPT" _bl099_hook_consent
    _extract_fn "$SCRIPT" _bl099_overwrite_consent
    _extract_fn "$SCRIPT" _bl099_write_ok
    _extract_fn "$SCRIPT" _bl099_mirror_mode
    _extract_fn "$SCRIPT" _bl099_doc_apply
    # The ONLY stub: pretend stdin is a terminal. Production still asks [ -t 0 ].
    printf '%s\n' '_bl099_stdin_is_tty() { return 0; }'
    printf '%s\n' '_bl099_hook_consent "hook?" && echo "HOOK=yes" || echo "HOOK=no"'
    printf '%s\n' '_bl099_overwrite_consent "ovw?" && echo "OVW=yes" || echo "OVW=no"'
    printf '%s\n' '_bl099_doc_apply "user-guide.md" "/nonexistent/user-guide.md" "/nonexistent/src.md" || true'
  } > "$probe"
  if ! bash -n "$probe" 2>/dev/null; then echo "PROBE-SYNTAX-ERROR"; rm -f "$probe"; return 0; fi
  ( unset CI SOIF_NONINTERACTIVE; bash "$probe" </dev/null 2>&1 ) || true
  rm -f "$probe"
}

# ── T-non-interactive-flag-honored (round 2, MINOR-C) ───────────────────────
# --help promises --non-interactive "skips Y/N confirmations even on a tty", but
# the three BL-099 consent paths only looked at CI / SOIF_NONINTERACTIVE / [-t 0]
# and would have prompted a scripted operator anyway. With a terminal present:
# NON_INTERACTIVE=false must PROMPT all three; NON_INTERACTIVE=true must prompt
# NONE of them and fall back to the declared-flag channel.
t_non_interactive_flag_honored() {
  local inter forced
  inter=$(_consent_probe false)
  forced=$(_consent_probe true)
  local i_hook=n i_ovw=n i_doc=n f_quiet=n f_hook=n f_ovw=n f_doc=n

  echo "$inter" | grep -qF 'PROMPTED[hook?][default=Y]' && i_hook=y
  echo "$inter" | grep -qF 'PROMPTED[ovw?][default=N]' && i_ovw=y
  echo "$inter" | grep -qF 'Apply upstream user-guide.md' && i_doc=y

  echo "$forced" | grep -qF 'PROMPTED' || f_quiet=y
  echo "$forced" | grep -qF 'Apply upstream' || f_doc=y
  echo "$forced" | grep -qxF 'HOOK=no' && f_hook=y
  echo "$forced" | grep -qxF 'OVW=no' && f_ovw=y

  # Review round 3 (MINOR): the doc prompt must go through the SHARED prompt_choice
  # helper, not a raw `read`. Without this assertion, reverting the call site to
  # `printf … ; read -r action` would leave every other check above green (the raw
  # version printed a prompt too), so "routed through the helper" would be unpinned
  # — and scripts/lint-raw-read-prompt.sh cannot backstop it (it keys on `read -p` /
  # `read -rp`; a printf-then-bare-`read -r` slips straight through — that lint scope
  # gap is called out in PR #185). The option strings are pinned too: they are what
  # _bl099_doc_apply's `case` arms match (sidecar → n|new|sidecar, overwrite →
  # o|overwrite, skip → the safe `*` default), so renaming one silently turns a real
  # choice into a no-op skip.
  local i_choice=n i_opts=n
  echo "$inter" | grep -qF 'PROMPTED-CHOICE[' && i_choice=y
  echo "$inter" | grep -qF '[options: skip sidecar overwrite]' && i_opts=y

  if [ "$i_hook" = y ] && [ "$i_ovw" = y ] && [ "$i_doc" = y ] \
     && [ "$i_choice" = y ] && [ "$i_opts" = y ] \
     && [ "$f_quiet" = y ] && [ "$f_doc" = y ] && [ "$f_hook" = y ] && [ "$f_ovw" = y ]; then
    pass "T-non-interactive-flag-honored: on a terminal, all three BL-099 consent paths prompt by default (the doc prompt via the shared prompt_choice helper, offering exactly skip/sidecar/overwrite) and NONE of them prompt under --non-interactive (hook falls back to --install-hooks, overwrite to --confirm-doc-overwrite, doc-apply to --apply-doc-updates)"
  else
    fail_ "T-non-interactive-flag-honored" "interactive: hook=$i_hook ovw=$i_ovw doc=$i_doc via-prompt_choice=$i_choice options-skip/sidecar/overwrite=$i_opts (all expect y); NON_INTERACTIVE=true: no-prompt=$f_quiet no-doc-prompt=$f_doc hook-denied=$f_hook ovw-denied=$f_ovw (all expect y — the flag must force the declared-flag channel).\ninteractive out:\n$inter\nforced out:\n$forced"
  fi
}

# ── T-doc-prompt-default-is-skip (round 3, MINOR) ───────────────────────────
# prompt_choice returns non-zero with nothing on stdout when the operator gives no
# valid answer (EOF, or the retry cap). The raw `read` it replaced had the same
# safe fallback via `|| action=""`, and that MUST survive the migration: an operator
# who hits Ctrl-D at the apply prompt must get SKIP — never a sidecar, and above all
# never an in-place overwrite. The probe's prompt_choice stub returns 1 for exactly
# this reason, so this pins the fallback against the real production function.
t_doc_prompt_default_is_skip() {
  local out; out=$(_consent_probe false)
  local skipped=n wrote=n
  echo "$out" | grep -qF 'skipped user-guide.md' && skipped=y
  echo "$out" | grep -qE 'wrote sidecar|overwrote' && wrote=y
  if [ "$skipped" = y ] && [ "$wrote" = n ]; then
    pass "T-doc-prompt-default-is-skip: when the interactive apply prompt yields no valid answer (EOF / abort), the action defaults to SKIP — no sidecar, no overwrite, no write of any kind"
  else
    fail_ "T-doc-prompt-default-is-skip" "skipped=$skipped (expect y — the no-answer fallback must be skip) wrote=$wrote (expect n — nothing may be applied without an explicit choice). Probe output:\n$out"
  fi
}

# ── T-doc-overwrite-default-is-N (round 2, MINOR-D) ─────────────────────────
# The destructive prompt's default is documented as No. It lives in a tty-only
# branch, so flipping it to "Y" left all 22 round-1 tests green. This pins the
# actual value the production function hands prompt_yes_no.
t_doc_overwrite_default_is_n() {
  local out; out=$(_consent_probe false)
  local dflt; dflt=$(echo "$out" | sed -n 's/^PROMPTED\[ovw?\]\[default=\(.*\)\]$/\1/p' | head -1)
  if [ "$dflt" = "N" ]; then
    pass "T-doc-overwrite-default-is-N: the interactive in-place-overwrite prompt defaults to N (destructive → default no), pinned against the production function itself"
  else
    fail_ "T-doc-overwrite-default-is-N" "the overwrite prompt's default is '$dflt' — it MUST be 'N' (the user guide promises a [y/N] prompt defaulting to no). Probe output:\n$out"
  fi
}

t_sync_refreshes_stale_script
t_exec_bit_probe
t_sync_self_copy_refused
t_sentinel_freezes_sync
t_dry_run_mutates_nothing
t_hook_refused_noninteractive_without_flag
t_hook_backfill_consented
t_rust_no_hook_expected
t_hook_block_refresh_preserves_user_lines
t_hook_mode_preserved
t_legacy_unmarked_precommit_sidecar
t_doc_apply_sidecar
t_doc_noninteractive_no_flag_applies_nothing
t_doc_overwrite_confirm_declined
t_doc_overwrite_confirm_accepted
t_doc_overwrite_backup_refusal
t_doc_overwrite_write_failure_is_loud
t_doc_sidecar_write_failure_is_loud
t_doc_overwrite_write_silently_fails_is_caught
t_doc_apply_flag_usage_errors
t_doc_overwrite_default_is_n
t_doc_prompt_default_is_skip
t_non_interactive_flag_honored
t_rendered_doc_never_applied
t_pin_stamped
t_mutation_sync
t_mutation_doc_guard
t_mutation_doc_guard_body
t_mutation_confirm
t_mutation_apply_status
t_mutation_write_ok_byteread

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
