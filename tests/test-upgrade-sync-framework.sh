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
# Round 1 (MAJOR-2b): assert the # BL-099-DOC-GUARD holds under the MOST
# destructive flag combination too — overwrite + confirm must STILL never touch
# a rendered doc.
t_rendered_doc_never_applied() {
  local T; T=$(mktemp -d); local P="$T/proj"; mk_project "$P" python
  printf '%s\n' '# My heavily customized CLAUDE.md — DO NOT OVERWRITE' > "$P/CLAUDE.md"
  printf '%s\n' '# My heavily customized PROJECT_INTAKE.md' > "$P/PROJECT_INTAKE.md"
  local pre_md5 pre_intake
  pre_md5=$(_md5file "$P/CLAUDE.md"); pre_intake=$(_md5file "$P/PROJECT_INTAKE.md")
  local out; out=$(run_sync "$P" --install-hooks --apply-doc-updates overwrite --confirm-doc-overwrite)
  local post_md5 post_intake
  post_md5=$(_md5file "$P/CLAUDE.md"); post_intake=$(_md5file "$P/PROJECT_INTAKE.md")
  if [ "$pre_md5" != "$post_md5" ] || [ "$pre_intake" != "$post_intake" ]; then
    fail_ "T-rendered-doc-never-applied" "a RENDERED doc was mutated under '--apply-doc-updates overwrite --confirm-doc-overwrite' — the guard must hold under EVERY flag combination"; rm -rf "$T"; return
  fi
  if ls "$P/"CLAUDE.md.bak.* "$P/"CLAUDE.md.new >/dev/null 2>&1; then
    fail_ "T-rendered-doc-never-applied" "the sync wrote a .bak/.new for CLAUDE.md — rendered docs are notice-only"; rm -rf "$T"; return
  fi
  if ! echo "$out" | grep -qF "RENDERED from a template"; then
    fail_ "T-rendered-doc-never-applied" "expected the rendered-doc template notice for CLAUDE.md; tail:\n$(echo "$out" | tail -10)"; rm -rf "$T"; return
  fi
  pass "T-rendered-doc-never-applied: CLAUDE.md + PROJECT_INTAKE.md byte-identical even under overwrite+confirm; template notice emitted (assisted apply deferred to BL-101)"
  rm -rf "$T"
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

  # Mutant: excise the marked script-sync dispatch line from the framework copy.
  grep -vF "$TARGET_TOKEN" "$FW/scripts/upgrade-project.sh" > "$FW/scripts/upgrade-project.sh.mut"
  mv "$FW/scripts/upgrade-project.sh.mut" "$FW/scripts/upgrade-project.sh"
  chmod +x "$FW/scripts/upgrade-project.sh"
  local Pm="$T/pm"; mk_project "$Pm" python
  printf '#!/usr/bin/env bash\necho OLD-STALE\n' > "$Pm/scripts/check-phase-gate.sh"
  ( cd "$Pm" && unset GITHUB_BASE_REF; CDF_HOME="$Pm/.no" SOIF_NONINTERACTIVE=1 \
      "$FW/scripts/upgrade-project.sh" --sync-framework </dev/null 2>&1 ) >/dev/null || true
  local mutant_stale=n; [ "$(grep -c OLD-STALE "$Pm/scripts/check-phase-gate.sh")" = "1" ] && mutant_stale=y

  if [ "$control_refreshed" = y ] && [ "$mutant_stale" = y ]; then
    pass "T-mutation-sync: real script refreshes stale vendored scripts; excising '# BL-099-SYNC' leaves them stale (dispatch is load-bearing)"
  else
    fail_ "T-mutation-sync" "control_refreshed=$control_refreshed (expect y); mutant_stale=$mutant_stale (expect y — refresh must NOT happen without the marker)"
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

  if [ "$control_untouched" = y ] && [ "$mutant_clobbered" = y ]; then
    pass "T-mutation-confirm: consent gate holds an unconfirmed overwrite; excising '# BL-099-CONFIRM' clobbers the doc unconfirmed (the gate is load-bearing)"
  else
    fail_ "T-mutation-confirm" "control_untouched=$control_untouched (expect y — no consent, no write); mutant_clobbered=$mutant_clobbered (expect y — without the marker the overwrite must land)"
  fi
  rm -rf "$T"
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
t_doc_apply_flag_usage_errors
t_rendered_doc_never_applied
t_pin_stamped
t_mutation_sync
t_mutation_doc_guard
t_mutation_confirm

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
