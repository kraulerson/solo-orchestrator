#!/usr/bin/env bash
# tests/test-scaffold-source-closure.sh
#
# BL-088 CLASS KILLER — scaffold source-closure check.
#
# THE DEFECT CLASS
#   init.sh ships a CURATED list of scripts/ files to every scaffolded
#   project (the `cp "$SCRIPT_DIR/scripts/..."` block). When a shipped gate
#   script grows a new `source`/`.`/`bash "$SCRIPT_DIR/<sibling>"` dependency
#   but the copy list is NOT updated, the sibling is absent downstream and the
#   feature breaks silently: a silently-skipping source loop no-ops the gate
#   (BL-072 tdd-classify.sh — a test-less feat: commit was ALLOWED in a real
#   Sponsored-POC scaffold), an unguarded source crashes the path
#   (check-gate.sh → phase2-state.sh), or an exec pass-path points the operator
#   at a script that does not exist (check-phase-gate.sh → run-phase3-validation.sh).
#   Every BL-072 test masked this by copying tdd-classify.sh into its own
#   fixture — the fixture supplied the dependency the real scaffold lacked.
#
# THE CHECK (this file)
#   1. Derive the SHIPPED SET mechanically from init.sh's cp lines (never a
#      hardcoded copy of the list — that would drift). Expands the
#      host-drivers/*.sh glob against the real scripts/ tree.
#   2. For every shipped scripts/**.sh, extract each reference to a sibling
#      script under scripts/ expressed via "$SCRIPT_DIR/<subpath>.sh" (the
#      script's own install directory). Full-line comments are stripped so a
#      usage-example comment is not mistaken for a dependency edge.
#   3. Assert every such sibling is ALSO in the shipped set — UNLESS it is
#      explicitly degrade-safe: a target the corpus ALSO references via a
#      project-root-preferred prefix ($PROJECT_ROOT/$PROJECT_DIR/$REPO_ROOT/
#      $proj_root) is an author-wired optional (the pre-commit lint idiom:
#      prefer-project-local, clean-skip-if-absent) and is excluded.
#
#   This catches (a) the two shipped gaps this PR fixes AND (b) any future
#   sourced-but-unshipped sibling. The load-bearing comparison carries the
#   marker # BL-088-CLOSURE.
#
# Hermetic + fast: pure static analysis, no init.sh execution, bash-3.2 safe
# (no `case ... )` inside $(...); temp files instead of associative arrays).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# BL-099: the ship-set parser is factored into a shared lib so the sync path
# (scripts/upgrade-project.sh --sync-framework) and this closure check derive
# the shipped set from ONE source of truth. Both must stay green.
# shellcheck source=/dev/null
. "$REPO_ROOT/scripts/lib/scaffold-shipped-set.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# closure_check <init_file> <scripts_dir>
#   Prints one "GAP: ..." line per shipped script that sources/execs an
#   unshipped, non-optional sibling. Returns 0 iff closed (no gaps).
#   Also prints a "SHIPPED_COUNT n" line so callers can assert the parser
#   actually derived a set (tamper-evidence against a silent-empty parse).
closure_check() {
  local init_file="$1" scripts_dir="$2"
  local work ship opt rel base f sdir refs sub target
  work="$(mktemp -d)"
  ship="$work/ship"; opt="$work/opt"; : > "$ship"; : > "$opt"

  # 1) Shipped set from init.sh cp lines — via the shared BL-099 parser
  #    (soif_parse_shipped_scripts) so the closure check and the sync-mode
  #    script sync can never disagree about what init.sh ships.
  soif_parse_shipped_scripts "$init_file" "$scripts_dir" > "$ship"

  # 2) Optional set: any sibling the corpus references via a project-root
  #    prefix (degrade-safe, author-wired optional). Comments stripped.
  while IFS= read -r rel; do
    case "$rel" in *.sh) : ;; *) continue ;; esac
    f="$scripts_dir/${rel#scripts/}"
    [ -f "$f" ] || continue
    grep -vE '^[[:space:]]*#' "$f" \
      | grep -oE '\$(PROJECT_ROOT|PROJECT_DIR|REPO_ROOT|proj_root)/scripts/(lib/|hooks/|host-drivers/)?[A-Za-z0-9_.-]+\.sh' 2>/dev/null \
      | sed -E 's#^\$[A-Za-z_]+/##' >> "$opt"
  done < "$ship"
  sort -u "$opt" -o "$opt"

  # 3) Closure: every $SCRIPT_DIR sibling reference must be shipped-or-optional.
  echo "SHIPPED_COUNT $(grep -c . "$ship")"
  while IFS= read -r rel; do
    case "$rel" in *.sh) : ;; *) continue ;; esac
    f="$scripts_dir/${rel#scripts/}"
    [ -f "$f" ] || continue
    sdir="scripts/$(dirname "${rel#scripts/}")"
    sdir="${sdir%/.}"
    refs="$(grep -vE '^[[:space:]]*#' "$f" \
              | grep -oE '\$SCRIPT_DIR/(lib/|hooks/|host-drivers/)?[A-Za-z0-9_.-]+\.sh' 2>/dev/null \
              | sed -E 's#^\$SCRIPT_DIR/##' | sort -u)"
    [ -n "$refs" ] || continue
    printf '%s\n' "$refs" | while IFS= read -r sub; do
      [ -n "$sub" ] || continue
      target="$sdir/$sub"
      grep -qxF "$target" "$opt" && continue
      # BL-088-CLOSURE: a "$SCRIPT_DIR" sibling reference in a shipped script
      # must itself be shipped by init.sh, or the dependency breaks downstream.
      grep -qxF "$target" "$ship" && continue
      printf 'GAP: %s sources/execs %s but init.sh does not ship it\n' "$rel" "$target"
    done
  done < "$ship" | sort -u

  local rc=0
  rm -rf "$work"
  return "$rc"
}

INIT="$REPO_ROOT/init.sh"
SCRIPTS="$REPO_ROOT/scripts"

# ── T-parser-nonempty: the ship-set parser must actually derive a set ──────
# Guards the silent-success failure mode: a broken regex that yields an empty
# shipped set would scan nothing and vacuously report zero gaps.
echo "=== T-parser-nonempty: init.sh cp-list parse yields a real shipped set ==="
out="$(closure_check "$INIT" "$SCRIPTS")"
shipped_n="$(printf '%s\n' "$out" | sed -n 's/^SHIPPED_COUNT //p')"
if [ -n "$shipped_n" ] && [ "$shipped_n" -ge 30 ]; then
  pass "T-parser-nonempty: derived $shipped_n shipped scripts from init.sh"
else
  fail_ "T-parser-nonempty" "parser derived only '${shipped_n:-0}' shipped scripts (expected >=30) — cp-line regex likely drifted"
fi

# Sentinel: known-shipped load-bearing files must be present in the set.
echo "=== T-parser-sentinels: known-shipped gate files are in the derived set ==="
sentinels_ok=1
# Re-derive the ship list directly for the sentinel assertion.
ship_probe="$(grep -E 'cp[[:space:]]+"\$SCRIPT_DIR/scripts/' "$INIT" \
  | sed -n 's#.*cp[[:space:]]*"\$SCRIPT_DIR/\(scripts/[^"]*\)".*#\1#p')"
for want in scripts/pre-commit-gate.sh scripts/check-phase-gate.sh scripts/lib/helpers-core.sh; do
  printf '%s\n' "$ship_probe" | grep -qxF "$want" || sentinels_ok=0
done
if [ "$sentinels_ok" -eq 1 ]; then
  pass "T-parser-sentinels: pre-commit-gate.sh, check-phase-gate.sh, helpers-core.sh all in the shipped set"
else
  fail_ "T-parser-sentinels" "a known-shipped sentinel file was missing from the derived set — parser broken"
fi

# ── T-closure-green: the REAL tree is closed (post-BL-088 fix) ─────────────
echo "=== T-closure-green: every shipped script's \$SCRIPT_DIR deps are shipped ==="
gaps="$(closure_check "$INIT" "$SCRIPTS" | grep '^GAP:' || true)"
if [ -z "$gaps" ]; then
  pass "T-closure-green: source-closure holds — no shipped script sources an unshipped sibling"
else
  fail_ "T-closure-green" "open source-closure gap(s):
$gaps"
fi

# ── T-closure-catches-tdd-classify (mutation): re-open the ORIGINAL bug ─────
# Remove init.sh's tdd-classify.sh cp line from a COPY. pre-commit-gate.sh
# still sources "$SCRIPT_DIR/lib/tdd-classify.sh" -> the check MUST go RED.
echo "=== T-closure-catches-tdd-classify: drop the tdd-classify cp line → RED ==="
mut_init="$(mktemp)"
grep -v 'cp "\$SCRIPT_DIR/scripts/lib/tdd-classify.sh"' "$INIT" > "$mut_init"
mut_gaps="$(closure_check "$mut_init" "$SCRIPTS" | grep '^GAP:' || true)"
if printf '%s\n' "$mut_gaps" | grep -q 'scripts/lib/tdd-classify.sh'; then
  pass "T-closure-catches-tdd-classify: removing the cp line makes the check flag tdd-classify.sh"
else
  fail_ "T-closure-catches-tdd-classify" "mutant init.sh (no tdd-classify cp) did NOT flag the gap — check not load-bearing; got:
$mut_gaps"
fi
rm -f "$mut_init"

# ── T-closure-catches-generic (mutation): a DIFFERENT unshipped sibling ─────
# Remove the check-versions.sh cp line; session-version-check.sh execs
# "$SCRIPT_DIR/check-versions.sh" -> the check MUST flag it. Proves the check
# is general (not special-cased to the two known gaps).
echo "=== T-closure-catches-generic: drop the check-versions cp line → RED ==="
mut_init2="$(mktemp)"
grep -v 'cp "\$SCRIPT_DIR/scripts/check-versions.sh"' "$INIT" > "$mut_init2"
mut_gaps2="$(closure_check "$mut_init2" "$SCRIPTS" | grep '^GAP:' || true)"
if printf '%s\n' "$mut_gaps2" | grep -q 'scripts/check-versions.sh'; then
  pass "T-closure-catches-generic: removing the cp line makes the check flag check-versions.sh"
else
  fail_ "T-closure-catches-generic" "mutant init.sh (no check-versions cp) did NOT flag the gap; got:
$mut_gaps2"
fi
rm -f "$mut_init2"

# ── T-closure-excludes-optional: the lint idiom is NOT flagged ──────────────
# The pre-commit lints (lint-tests-registered.sh, ...) are exec'd via a
# prefer-project-local candidate loop with a clean skip. They are intentionally
# NOT shipped by init.sh; the check must NOT flag them.
echo "=== T-closure-excludes-optional: degrade-safe lint deps are not flagged ==="
opt_leak="$(closure_check "$INIT" "$SCRIPTS" | grep '^GAP:' | grep -E 'lint-(tests-registered|counter-antipattern|backlog-references|fix-functions-stderr|raw-read-prompt|no-live-remote-in-tests)\.sh' || true)"
if [ -z "$opt_leak" ]; then
  pass "T-closure-excludes-optional: project-local-preferred lint deps correctly excluded"
else
  fail_ "T-closure-excludes-optional" "check wrongly flagged a degrade-safe optional:
$opt_leak"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
