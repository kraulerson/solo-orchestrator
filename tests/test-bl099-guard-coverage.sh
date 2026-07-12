#!/usr/bin/env bash
# tests/test-bl099-guard-coverage.sh — SYSTEMATIC guard-coverage harness for the
# BL-099 --sync-framework code paths (scripts/upgrade-project.sh).
#
# WHY THIS EXISTS (round 4). Four consecutive adversarial reviews each found a
# DIFFERENT surviving mutation in this safety-critical code (it rewrites files inside
# live user projects). Each round pinned the one guard the reviewer named; the next
# reviewer found the next unpinned guard. That is whack-a-mole. This harness makes
# guard coverage SYSTEMATIC and SELF-ENFORCING: it holds an explicit REGISTRY of
# every load-bearing guard, and for each one it NEUTERS a throwaway copy of the real
# script and proves the BL-099 regression suite goes RED — then restores and proves
# it goes GREEN. A guard with no killing test cannot be added to the registry, and a
# guard that is silently un-pinned makes THIS harness fail. Round 5 cannot find a
# survivor that this registry does not already enumerate.
#
# HOW EACH ROW IS CHECKED (the anti-cheat rules, all enforced per row):
#   1. copy the REAL scripts/upgrade-project.sh into a mutant framework tree;
#   2. apply the neuter (a literal sed/awk transform — flip a dry-run test, gut a
#      function body, delete/replace one line);
#   3. assert the mutant DIFFERS from pristine (a neuter that changed nothing is a
#      mis-targeted string — hard fail, never a vacuous pass);
#   4. assert the named marker comment is STILL present (a neuter that removed the
#      marker would let a marker-grep test pass vacuously — we attack BEHAVIOUR);
#   5. assert `bash -n` still passes (a syntax-broken mutant proves nothing);
#   6. run the BL-099 suite (JUST the named killing test, via BL099_ONLY) against the
#      mutant tree (via BL099_REPO_OVERRIDE) and assert it EXITS NON-ZERO — RED;
#   7. restore pristine and assert the same test EXITS ZERO — GREEN. This proves the
#      RED was caused by the neuter, not by the environment.
#
# The suite it drives (tests/test-upgrade-sync-framework.sh) exposes two hooks used
# ONLY here: BL099_REPO_OVERRIDE re-points its framework tree at the mutant, and
# BL099_ONLY runs a single named test. A bare `bash tests/…` run ignores both.
#
# FAST-LANE: NOT in the tests.yml `unit` list ON PURPOSE. It neuters the script and
# runs the suite ~2x per registry row (~25 rows), so it is minutes, not seconds —
# an aggregator-only test (registered in tests/full-project-test-suite.sh). It does
# NOT invoke init.sh. lint-tests-registered.sh is satisfied by the aggregator entry.
#
# CITATION: guards are neutered by a grep-able marker / function name / literal
# construct, never a bare file:line (the repo's CITATION RULE). bash-3.2 safe;
# hermetic (CDF_HOME pinned nowhere by the driven suite); no real remotes.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PRISTINE="$REPO_ROOT/scripts/upgrade-project.sh"
SUITE="$REPO_ROOT/tests/test-upgrade-sync-framework.sh"

PASSED=0
FAILED=0
SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip_() { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

echo "== tests/test-bl099-guard-coverage.sh =="

# ── Build the MUTANT framework tree ONCE (scripts/, docs/, templates/, init.sh —
# everything the sync reads from ORCHESTRATOR_ROOT). Only scripts/upgrade-project.sh
# is ever mutated; every row resets it from PRISTINE.
#
# It IS a git checkout, deliberately: the real framework the suite drives is a git
# repo, and _bl099_stamp_pin only writes soloFrameworkCommit when it can resolve the
# framework HEAD. A non-git tree let the manifest-pin dry-run guard SURVIVE the matrix
# (the pin silently no-ops, so flipping its guard mutates nothing) — this harness
# caught exactly that. A single commit gives the pin a HEAD to stamp, so flipping the
# pin dry-run guard writes the manifest and the matrix sees it. ────────────────────
ROOT_TMP="$(mktemp -d)"
MUTANT_TREE="$ROOT_TMP/framework"
mkdir -p "$MUTANT_TREE"
cp -R "$REPO_ROOT/scripts"    "$MUTANT_TREE/scripts"
cp -R "$REPO_ROOT/docs"       "$MUTANT_TREE/docs"
cp -R "$REPO_ROOT/templates"  "$MUTANT_TREE/templates"
cp    "$REPO_ROOT/init.sh"    "$MUTANT_TREE/init.sh"
( cd "$MUTANT_TREE" && git init -q && git config user.email fw@t.local && git config user.name FW \
    && unset GITHUB_BASE_REF && git add -A && git commit -q -m "mutant framework HEAD" ) >/dev/null 2>&1
MUT="$MUTANT_TREE/scripts/upgrade-project.sh"
cleanup() { rm -rf "$ROOT_TMP" 2>/dev/null || true; }
trap cleanup EXIT

# ── THE PER-SECTION TARGET (BL-113, 2026-07-12) ────────────────────────────────
# The registry originally pinned exactly one script (upgrade-project.sh) with one
# killing suite. The BL-113 anti-laundering guards live in DIFFERENT scripts and
# are killed by a DIFFERENT suite, so three knobs are now section-scoped:
#   PRISTINE      the real script a row mutates (the neuter primitives all edit $MUT)
#   MUT           its copy inside $MUTANT_TREE
#   GUARD_RUNNER  the function that runs the named killing test against $MUTANT_TREE
# Every existing row keeps the BL-099 defaults below — nothing about them changes.
GUARD_RUNNER=_run_killing

# Reset the mutant script to pristine (cp preserves the +x mode).
_reset_mutant() { cp "$PRISTINE" "$MUT"; chmod +x "$MUT"; }

# Point the registry at a different script + killing suite for the rows that follow.
# use_target <pristine-path> <mutant-path> <runner-fn>
use_target() { PRISTINE="$1"; MUT="$2"; GUARD_RUNNER="$3"; }

# ── NEUTER PRIMITIVES ───────────────────────────────────────────────────────────
# Each rewrites $MUT in place, chmods +x (mv from mktemp drops the exec bit — the
# executed script would 126/Permission-denied and give a FALSE red), and returns
# non-zero on a MIS-TARGET (anchor/string absent, or not exactly one occurrence) so
# check_guard can hard-fail rather than silently produce a no-op mutant.

# Flip the nearest `[ "$DRY_RUN" = true ]` test AT OR BEFORE <anchor>'s line to
# `= false`, so that dry-run guard never fires and the write it suppressed escapes.
# Literal index/substr matching (no regex) — the anchor and the test carry $ " [ ].
_neu_flip() {
  local anchor="$1" tmp; tmp="$(mktemp)"
  awk -v anchor="$anchor" '
    { line[NR]=$0 }
    END {
      aln=0; for(i=1;i<=NR;i++){ if(index(line[i],anchor)>0){aln=i;break} }
      if(aln==0){ exit 3 }
      tgt=0; for(i=1;i<=aln;i++){ if(index(line[i],"[ \"$DRY_RUN\" = true ]")>0) tgt=i }
      if(tgt==0){ exit 3 }
      for(i=1;i<=NR;i++){
        if(i==tgt){ s=line[i]; p=index(s,"[ \"$DRY_RUN\" = true ]");
          print substr(s,1,p-1) "[ \"$DRY_RUN\" = false ]" substr(s,p+length("[ \"$DRY_RUN\" = true ]")) }
        else print line[i]
      }
    }' "$MUT" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$MUT"; chmod +x "$MUT"
}

# Gut <fn>'s body to <body>, keeping the signature and every marker comment in the
# file. Matches `<fn>() {` at column 0 and the closing `}` at column 0 (bash-3.2 /
# BSD-awk safe) — the same shape as the suite's own _neuter_fn.
_neu_fnbody() {
  local fn="$1" body="$2" tmp; tmp="$(mktemp)"
  awk -v fn="$fn" -v body="$body" '
    !done && index($0, fn "() {")==1 { print; print "  " body; skip=1; hit=1; next }
    skip && $0=="}" { print; skip=0; done=1; next }
    skip { next }
    { print }
    END { if(!hit) exit 3 }
  ' "$MUT" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$MUT"; chmod +x "$MUT"
}

# Replace EXACTLY ONE occurrence of literal <old> with <new> (literal index/substr,
# so glob/regex metachars in the strings are inert). Non-zero unless it hit once.
_neu_subline() {
  local old="$1" new="$2" tmp; tmp="$(mktemp)"
  awk -v old="$old" -v new="$new" '
    { p=index($0, old); if(p>0){ $0=substr($0,1,p-1) new substr($0,p+length(old)); c++ } print }
    END { if(c!=1) exit 3 }
  ' "$MUT" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$MUT"; chmod +x "$MUT"
}

# Delete EXACTLY ONE line containing literal <needle>. Non-zero unless it hit once.
_neu_delline() {
  local needle="$1" tmp; tmp="$(mktemp)"
  awk -v needle="$needle" '
    index($0, needle)>0 { c++; next } { print }
    END { if(c!=1) exit 3 }
  ' "$MUT" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$MUT"; chmod +x "$MUT"
}

# The mode-preservation guard is genuinely two lines (restore-known-mode / fallback).
# Neuter BOTH restore chmods in _bl099_replace_region to no-ops, so a refreshed hook
# keeps the mktemp 0600 (+ the caller's chmod +x → 0700, not 0755).
_neu_modepreserve() {
  local tmp; tmp="$(mktemp)"
  awk '
    { line=$0
      p=index(line, "chmod \"$mode\" \"$file\" 2>/dev/null || true");
      if(p>0){ line=substr(line,1,p-1) ": # neutered" substr(line,p+length("chmod \"$mode\" \"$file\" 2>/dev/null || true")); c1++ }
      p=index(line, "chmod 755 \"$file\" 2>/dev/null || true");
      if(p>0){ line=substr(line,1,p-1) ": # neutered" substr(line,p+length("chmod 755 \"$file\" 2>/dev/null || true")); c2++ }
      print line }
    END { if(c1!=1 || c2!=1) exit 3 }
  ' "$MUT" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$MUT"; chmod +x "$MUT"
}

# Neuter EVERY CODE line carrying literal <marker> to `: # <marker> (NEUTERED)` —
# the marker survives (rule 4) and the decision body is gone. Comment-only lines
# are left intact. Non-zero unless it hit at least once. This is the primitive for
# guards whose decision is spread over more than one marked statement (BL-113).
_neu_markerline() {
  local marker="$1" tmp; tmp="$(mktemp)"
  awk -v marker="$marker" '
    {
      line=$0
      # leading-whitespace-only-then-# => a comment line; never neuter it.
      s=line; sub(/^[ \t]+/, "", s)
      if (substr(s,1,1)=="#") { print line; next }
      if (index(line, marker)>0) {
        n=match(line, /^[ \t]*/); ind=substr(line, 1, RLENGTH)
        print ind ": # " marker " (NEUTERED)"
        c++
        next
      }
      print line
    }
    END { if(c<1) exit 3 }
  ' "$MUT" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$MUT"; chmod +x "$MUT"
}

_apply_neuter() {
  local kind="$1" a1="$2" a2="$3"
  case "$kind" in
    flip)         _neu_flip "$a1" ;;
    fnbody)       _neu_fnbody "$a1" "$a2" ;;
    subline)      _neu_subline "$a1" "$a2" ;;
    delline)      _neu_delline "$a1" ;;
    markerline)   _neu_markerline "$a1" ;;
    modepreserve) _neu_modepreserve ;;
    *) return 2 ;;
  esac
}

# Run ONE (or more, space-separated) BL-099 suite test(s) against the mutant tree.
# Prints the suite output; returns the suite's exit code (non-zero = a named test
# FAILED, because BL099_ONLY runs only those tests).
_run_killing() {
  BL099_REPO_OVERRIDE="$MUTANT_TREE" BL099_ONLY="$1" bash "$SUITE" 2>&1
}

# BL-113 runner: drive tests/test-bl113-sast-honesty.sh against the mutant tree's
# scripts/. The suite scaffolds a real project with the REAL init.sh and then swaps
# in the (possibly neutered) scripts via BL113_SCRIPTS_OVERRIDE; BL113_ONLY narrows
# it to the anti-laundering arms so each row costs two scaffolds, not six.
_run_killing_bl113() {
  BL113_SCRIPTS_OVERRIDE="$MUTANT_TREE/scripts" BL113_ONLY="$1" \
    bash "$REPO_ROOT/tests/test-bl113-sast-honesty.sh" 2>&1
}

# ── THE REGISTRY PIPELINE ────────────────────────────────────────────────────────
# check_guard <name> <marker|-> <killing_test_fn> <kind> [arg1] [arg2]
GUARD_ROWS=""   # accumulated "STATUS<TAB>name<TAB>killing-test" for the summary table
check_guard() {
  local name="$1" marker="$2" tests="$3" kind="$4" a1="$5" a2="$6"
  _reset_mutant
  if ! _apply_neuter "$kind" "$a1" "$a2"; then
    fail_ "$name" "neuter MIS-TARGETED (kind=$kind) — the anchor/string was absent or not unique in the current script; update the registry row"
    GUARD_ROWS="${GUARD_ROWS}MISTARGET\t${name}\t${tests}\n"; _reset_mutant; return
  fi
  if cmp -s "$PRISTINE" "$MUT"; then
    fail_ "$name" "neuter produced an IDENTICAL file — nothing was mutated (kind=$kind)"
    GUARD_ROWS="${GUARD_ROWS}NOOP\t${name}\t${tests}\n"; _reset_mutant; return
  fi
  if [ "$marker" != "-" ] && ! grep -qF "$marker" "$MUT"; then
    fail_ "$name" "the neuter removed the marker '$marker' — a marker-grep test could pass vacuously; the neuter must attack behaviour, not the marker text"
    GUARD_ROWS="${GUARD_ROWS}MARKERGONE\t${name}\t${tests}\n"; _reset_mutant; return
  fi
  if ! bash -n "$MUT" 2>/dev/null; then
    fail_ "$name" "the mutant has a bash syntax error — a syntax-broken mutant proves nothing (kind=$kind)"
    GUARD_ROWS="${GUARD_ROWS}SYNTAX\t${name}\t${tests}\n"; _reset_mutant; return
  fi
  local mout mrc=0; mout=$("$GUARD_RUNNER" "$tests") || mrc=$?
  if echo "$mout" | grep -qF "running as root"; then
    _reset_mutant
    skip_ "$name" "killing test [$tests] short-circuits under root (mode bits do not restrict root) — cannot pin here on this host"
    GUARD_ROWS="${GUARD_ROWS}SKIP-root\t${name}\t${tests}\n"; return
  fi
  if [ "$mrc" = "0" ]; then
    _reset_mutant
    fail_ "$name" "SURVIVED — killing test [$tests] stayed GREEN against the neutered guard. The guard is NOT pinned by that test.\nmutant PASS/FAIL lines:\n$(echo "$mout" | grep -E '\[PASS\]|\[FAIL\]' | head -4)"
    GUARD_ROWS="${GUARD_ROWS}SURVIVED\t${name}\t${tests}\n"; return
  fi
  # RED confirmed. Restore and prove GREEN so the RED is attributable to the neuter.
  _reset_mutant
  local gout grc=0; gout=$("$GUARD_RUNNER" "$tests") || grc=$?
  if [ "$grc" != "0" ]; then
    fail_ "$name" "killing test [$tests] FAILS even against the RESTORED pristine script — the RED was not caused by the neuter (environment/flake?).\nrestored PASS/FAIL lines:\n$(echo "$gout" | grep -E '\[PASS\]|\[FAIL\]' | head -4)"
    GUARD_ROWS="${GUARD_ROWS}FLAKY\t${name}\t${tests}\n"; return
  fi
  pass "$name → RED under neuter ($kind), GREEN restored | killing: $tests"
  GUARD_ROWS="${GUARD_ROWS}PINNED\t${name}\t${tests}\n"
}

# ══════════════════════════════════════════════════════════════════════════════════
# THE GUARD REGISTRY — one row per load-bearing guard in the BL-099 code paths.
# Column meaning: NAME | MARKER (grep-able, or - if the killing test is behavioural)
#                 | KILLING TEST (in tests/test-upgrade-sync-framework.sh) | NEUTER.
# Every dry-run guard is neutered by FLIPPING its own `[ "$DRY_RUN" = true ]` test to
# false (the write it suppressed then escapes) and is killed by the full-surface
# dry-run matrix. Behaviour guards are gutted / line-edited and killed by the
# behavioural test that asserts the property.
# ══════════════════════════════════════════════════════════════════════════════════

# ── (A) DRY-RUN PURITY — every write suppressed under --dry-run (BLOCK-1) ─────────
check_guard "dryrun/backfill+CDF"            "-" t_dry_run_pure_under_all_flags flip '[dry-run] would run idempotent'
check_guard "dryrun/script-sync"             "-" t_dry_run_pure_under_all_flags flip '[would sync]'
check_guard "dryrun/commit-msg-hook-refresh" "-" t_dry_run_pure_under_all_flags flip '[would refresh] commit-msg TDD gate'
check_guard "dryrun/commit-msg-hook-install" "-" t_dry_run_pure_under_all_flags flip '[would install] commit-msg TDD gate'
check_guard "dryrun/pre-commit-hook-install" "-" t_dry_run_pure_under_all_flags flip '[would install] pre-commit fallback hook'
check_guard "dryrun/pre-commit-hook-refresh" "-" t_dry_run_pure_under_all_flags flip '[would refresh] pre-commit fallback managed region'
check_guard "dryrun/pre-commit-hook-legacy"  "-" t_dry_run_pure_under_all_flags flip '[would write sidecar] legacy'
check_guard "dryrun/doc-apply"               "-" t_dry_run_pure_under_all_flags flip '[dry-run] notice only'
check_guard "dryrun/manifest-pin"            "-" t_dry_run_pure_under_all_flags flip '[dry-run] would stamp'

# ── (B) REFUSE-TO-RUN GUARDS — freeze the surface before any mutation ─────────────
check_guard "sentinel/pending-approval" "-" t_sentinel_freezes_sync  subline 'if [ "$BACKFILL_ONLY" != true ]; then _bl015_sentinel_guard; fi' 'if [ "$BACKFILL_ONLY" != true ]; then :; fi'
check_guard "source-check/self-copy"    "-" t_sync_self_copy_refused subline 'if [ "$SCRIPT_DIR" -ef "$PROJECT_ROOT/scripts" ]; then' 'if false; then'

# ── (C) THE RENDERED-DOC FENCE (# BL-099-DOC-GUARD) ──────────────────────────────
check_guard "doc-guard/rendered-fence" "# BL-099-DOC-GUARD" t_rendered_doc_never_applied fnbody _bl099_doc_is_rendered 'return 1'

# ── (D) DESTRUCTIVE-OVERWRITE CONSENT (# BL-099-CONFIRM) + its non-interactive
#        fallback (a flag never auto-yeses a destructive overwrite) ───────────────
check_guard "confirm/overwrite-consent"    "# BL-099-CONFIRM" t_doc_overwrite_confirm_declined fnbody _bl099_overwrite_consent 'return 0'
check_guard "confirm/noninteractive-fallback" "-"             t_doc_overwrite_confirm_declined subline '  [ "$CONFIRM_DOC_OVERWRITE" = true ]' '  true'

# ── (E) THE WRITE-STATUS CHECK — BOTH halves of _bl099_write_ok (# BL-099-APPLY-STATUS)
check_guard "write-ok/status-half"   "# BL-099-APPLY-STATUS" t_doc_cp_reports_failure_is_caught            fnbody _bl099_write_ok 'cmp -s "$2" "$3"'
check_guard "write-ok/byteread-half" "# BL-099-APPLY-STATUS" t_doc_overwrite_write_silently_fails_is_caught fnbody _bl099_write_ok '[ "$1" -eq 0 ]'

# ── (F) THE OVERWRITE BACKUP + REPAIR CHAIN ──────────────────────────────────────
check_guard "overwrite/backup-before-write" "# BL-099-APPLY-STATUS" t_doc_overwrite_backup_refusal            subline 'if ! _bl099_write_ok "$rc" "$pfile" "$bak"; then' 'if false; then'
check_guard "overwrite/auto-restore"        "-"                     t_doc_overwrite_write_failure_restores_original delline 'cp "$bak" "$pfile" 2>/dev/null || true'
check_guard "overwrite/restore-message"     "-"                     t_doc_overwrite_write_failure_restores_original subline 'if cmp -s "$bak" "$pfile"; then' 'if ! cmp -s "$bak" "$pfile"; then'

# ── (G) SCRIPT SYNC — dispatch (# BL-099-SYNC) + its new cp status check (MINOR-5) ─
check_guard "script-sync/dispatch"  "# BL-099-SYNC"         t_sync_refreshes_stale_script subline '  _bl099_sync_scripts        # BL-099-SYNC' '  :        # BL-099-SYNC'
check_guard "script-sync/cp-status" "# BL-099-APPLY-STATUS" t_scriptsync_cp_failure_is_loud subline 'if ! _bl099_write_ok "$rc" "$src" "$dst"; then    # BL-099-APPLY-STATUS' 'if false; then    # BL-099-APPLY-STATUS'

# ── (H) CONSENT-CONTEXT GUARDS — forcing predicate + hook consent fallback ────────
check_guard "consent/noninteractive-forcing" "-" t_non_interactive_flag_honored           fnbody  _bl099_forced_noninteractive 'return 1'
check_guard "consent/hook-install-fallback"  "-" t_hook_refused_noninteractive_without_flag subline '  [ "$INSTALL_HOOKS" = true ]' '  true'

# ── (I) HOOK MODE PRESERVATION (a refresh keeps the destination 0755) ────────────
check_guard "mode/hook-refresh-preservation" "-" t_hook_mode_preserved modepreserve

# ── (J) THE INTERACTIVE APPLY-PROMPT FALLBACK (# BL-099-PROMPT-FALLBACK, BLOCK-2) ──
check_guard "prompt/apply-fallback-is-skip" "# BL-099-PROMPT-FALLBACK" t_doc_prompt_default_is_skip subline '|| action="skip"  # BL-099-PROMPT-FALLBACK' '|| action="overwrite"  # BL-099-PROMPT-FALLBACK'

# ══════════════════════════════════════════════════════════════════════════════════
# (K) BL-113 — THE ANTI-LAUNDERING GUARDS (a different pair of scripts, a different
#     killing suite; same anti-cheat contract). Walk findings F14 + F15: the 3→4
#     gate's dirty-tree autorun ran the validation driver with `--offline`, which
#     rewrote a REAL semgrep FAIL into an attestable SKIP. Two defences, both
#     marked `# BL-113-NO-LAUNDER`, both pinned here:
#       driver — a SKIP never overwrites a prior REAL FAIL (carry-forward)
#       gate   — an offline-autorun SKIP for an INSTALLED tool is refused outright
#     The killing test is tests/test-bl113-sast-honesty.sh::T-no-launder-dirty-tree
#     (driven with BL113_ONLY=no-launder). Neutering EITHER marked decision must
#     turn it RED; restoring must turn it GREEN.
# ══════════════════════════════════════════════════════════════════════════════════
use_target "$REPO_ROOT/scripts/run-phase3-validation.sh" \
           "$MUTANT_TREE/scripts/run-phase3-validation.sh" _run_killing_bl113
check_guard "bl113/driver-carry-forward" "# BL-113-NO-LAUNDER" no-launder markerline '# BL-113-NO-LAUNDER'

use_target "$REPO_ROOT/scripts/check-phase-gate.sh" \
           "$MUTANT_TREE/scripts/check-phase-gate.sh" _run_killing_bl113
check_guard "bl113/gate-refuses-offline-skip" "# BL-113-NO-LAUNDER" no-launder markerline '# BL-113-NO-LAUNDER'

# Restore the BL-099 target for anything appended after this point.
use_target "$REPO_ROOT/scripts/upgrade-project.sh" \
           "$MUTANT_TREE/scripts/upgrade-project.sh" _run_killing

echo ""
echo "── Guard-coverage registry (STATUS  guard  killing-test) ──"
printf '%b' "$GUARD_ROWS" | sed 's/^/  /'
echo ""
echo "== Total: $((PASSED + FAILED + SKIPPED)) | Pinned: $PASSED | Failed: $FAILED | Skipped: $SKIPPED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
