#!/usr/bin/env bash
# tests/test-upgrade-sync-framework.sh — BL-099 SLICE-A regression suite.
#
# Covers scripts/upgrade-project.sh --sync-framework (same-tier refresh of the
# vendored gate scripts / helper libs / hooks / framework docs from the FRAMEWORK
# copy being run) and its --dry-run / --install-hooks modifiers.
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
t_doc_apply_sidecar() {
  local T; T=$(mktemp -d); local P="$T/proj"; mk_project "$P" python
  printf '%s\n' 'my customized user guide' > "$P/docs/reference/user-guide.md"
  local pre_md5; pre_md5=$(_md5file "$P/docs/reference/user-guide.md")
  ( cd "$P" && unset GITHUB_BASE_REF; CDF_HOME="$P/.no-such-cdf" SOIF_NONINTERACTIVE=1 SOLO_SYNC_DOC_APPLY=sidecar \
      "$SCRIPT" --sync-framework </dev/null 2>&1 ) >/dev/null
  local post_md5; post_md5=$(_md5file "$P/docs/reference/user-guide.md")
  if [ "$pre_md5" != "$post_md5" ]; then
    fail_ "T-doc-apply-sidecar" "sidecar apply modified the original doc (must stay untouched)"; rm -rf "$T"; return
  fi
  if [ ! -f "$P/docs/reference/user-guide.md.new" ] || ! cmp -s "$REPO_ROOT/docs/user-guide.md" "$P/docs/reference/user-guide.md.new"; then
    fail_ "T-doc-apply-sidecar" "expected user-guide.md.new sidecar matching framework upstream"; rm -rf "$T"; return
  fi
  pass "T-doc-apply-sidecar: drifted reference doc written as <doc>.new; original untouched"
  rm -rf "$T"
}

# ── T-doc-apply-overwrite-backs-up (reference doc) ──────────────────────────
t_doc_apply_overwrite_backs_up() {
  local T; T=$(mktemp -d); local P="$T/proj"; mk_project "$P" python
  printf '%s\n' 'my customized user guide' > "$P/docs/reference/user-guide.md"
  local old_md5; old_md5=$(_md5file "$P/docs/reference/user-guide.md")
  ( cd "$P" && unset GITHUB_BASE_REF; CDF_HOME="$P/.no-such-cdf" SOIF_NONINTERACTIVE=1 SOLO_SYNC_DOC_APPLY=overwrite \
      "$SCRIPT" --sync-framework </dev/null 2>&1 ) >/dev/null
  local bak; bak=$(ls "$P/docs/reference/"user-guide.md.bak.* 2>/dev/null | head -1)
  if ! cmp -s "$REPO_ROOT/docs/user-guide.md" "$P/docs/reference/user-guide.md"; then
    fail_ "T-doc-apply-overwrite-backs-up" "overwrite did not replace the doc with framework upstream"; rm -rf "$T"; return
  fi
  if [ -z "$bak" ] || [ "$(_md5file "$bak")" != "$old_md5" ]; then
    fail_ "T-doc-apply-overwrite-backs-up" "expected a .bak.<date> backup preserving the pre-overwrite content"; rm -rf "$T"; return
  fi
  pass "T-doc-apply-overwrite-backs-up: overwrite applied upstream + kept a dated .bak of the operator's prior copy"
  rm -rf "$T"
}

# ── T-rendered-doc-never-applied (guards Karl's edge) ───────────────────────
t_rendered_doc_never_applied() {
  local T; T=$(mktemp -d); local P="$T/proj"; mk_project "$P" python
  printf '%s\n' '# My heavily customized CLAUDE.md — DO NOT OVERWRITE' > "$P/CLAUDE.md"
  local pre_md5; pre_md5=$(_md5file "$P/CLAUDE.md")
  local out; out=$(run_sync "$P" --install-hooks)
  local post_md5; post_md5=$(_md5file "$P/CLAUDE.md")
  if [ "$pre_md5" != "$post_md5" ]; then
    fail_ "T-rendered-doc-never-applied" "CLAUDE.md (RENDERED doc) was mutated by the sync — must never be file-applied in this slice"; rm -rf "$T"; return
  fi
  if ! echo "$out" | grep -qF "RENDERED from a template"; then
    fail_ "T-rendered-doc-never-applied" "expected the rendered-doc template notice for CLAUDE.md; tail:\n$(echo "$out" | tail -10)"; rm -rf "$T"; return
  fi
  pass "T-rendered-doc-never-applied: drifted CLAUDE.md left byte-identical; template-level notice emitted (assisted apply deferred to BL-101)"
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

t_sync_refreshes_stale_script
t_exec_bit_probe
t_sync_self_copy_refused
t_sentinel_freezes_sync
t_dry_run_mutates_nothing
t_hook_refused_noninteractive_without_flag
t_hook_backfill_consented
t_rust_no_hook_expected
t_hook_block_refresh_preserves_user_lines
t_legacy_unmarked_precommit_sidecar
t_doc_apply_sidecar
t_doc_apply_overwrite_backs_up
t_rendered_doc_never_applied
t_pin_stamped
t_mutation_sync
t_mutation_doc_guard

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
