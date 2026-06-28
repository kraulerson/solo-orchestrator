#!/usr/bin/env bash
# tests/test-test-gate-counter-sanitizer.sh
#
# Regression: scripts/test-gate.sh used the antipattern
#   var=$(cmd_that_may_exit_nonzero || echo "0")
# where `cmd_that_may_exit_nonzero` was either `grep -c` (exits 1 on zero
# matches) or `sed ... | grep -cE` (likewise). When the trailing grep
# exited 1 it had already printed "0\n" — the `||` then appended a
# second "0" and the variable held the two-line string "0\n0".
# Subsequent `[ "$var" -gt 0 ]` errored with "integer expression
# expected" and (under `set -euo pipefail`) the arithmetic test returned
# non-zero, which silently bypassed at least one hard gate.
#
# Sites in scripts/test-gate.sh (check_phase_gate function):
#
# EXPLOITABLE (no armor, fed real Phase 2→3 gate):
#   373  feature_count=$(grep -cE '^#{2,3} ' FEATURES.md ... || echo "0")
#   375  feature_count=$(grep -cE '^#{2,3} [^#]' ... | head -1 || echo "0")
#   395  cutline_items=$(sed ... | grep -cE '^\s*-\s*\*\*' || echo "0")
#        ↑ this fed `if [ "$cutline_items" -gt 0 ] && [ "$recorded_features" -gt 0 ]`
#          — when cutline_items held "0\n0" the integer test errored and
#          the whole MVP-cutline comparison block was silently skipped:
#          no WARN about "MVP cutline items missing", which is exactly
#          the Phase 2→3 cutline gate.
#
# LATENT (currently armored by `tr -d '[:space:]'` reducing "0\n0" → "00";
#         arithmetic comparisons still treat "00" as 0; sanitizer is
#         defense-in-depth so any future maintainer who drops the `tr`
#         doesn't silently re-introduce the bypass):
#   293  sev1_count=$(grep -c 'SEV-1.*Open' "BUGS.md" ... | tr -d '[:space:]' || echo "0")
#   294  sev2_open=$(grep -c 'SEV-2.*Open' ...)
#   295  sev2_deferred=$(grep -c 'SEV-2.*Deferred' ...)
#   296  sev3_open=$(grep -c 'SEV-3.*Open' ...)
#   302-305  gh_sev1..gh_sev3=$(gh issue list ... | jq 'length' | tr -d '[:space:]' || echo "0")
#
# REDUNDANT (jq with `// 0` default; the `|| echo "0"` never fires when
#            jq succeeds; sanitizer is purely cosmetic for consistency):
#   380  recorded_features=$(jq '.features_completed | length' ... || echo "0")
#   416  untested=$(jq '.features_since_last_test // 0' ... || echo "0")
#
# Fix (verbatim from PR #53, canonical in scripts/process-checklist.sh:45-46):
#   case "$var" in ''|*[!0-9]*) var=0 ;; esac
# placed on the line immediately after the capture.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/test-gate.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup() {
  TMP=$(mktemp -d)
  PROJ="$TMP/p"
  mkdir -p "$PROJ/.claude"
}
teardown() { rm -rf "$TMP"; }

# Run --check-phase-gate inside an isolated PROJ. We force `gh` and `jq`
# off the PATH so we exercise only the BUGS.md + filesystem code paths
# (no flake from the operator's real gh auth or jq absence). The real
# /usr/bin/sed and /usr/bin/grep stay available via the slim PATH.
run_gate() {
  ( cd "$PROJ" && PATH="/usr/bin:/bin" bash "$SCRIPT" --check-phase-gate 2>&1 ) || true
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Primary smoking gun: Phase 2→3 MVP-cutline gate ==="
# ════════════════════════════════════════════════════════════════════

# Fixtures shared across T1..T3: BUGS.md with zero open bugs (so the bug
# block prints all-clear and we don't get a FAIL exit before the cutline
# block runs).
seed_clean_bugs() {
  cat > "$PROJ/BUGS.md" <<'MD'
# BUGS.md

(no open bugs)
MD
}

# T1: PRODUCT_MANIFESTO.md exists but Must-Have section yields zero
# `- **` items. Pre-fix `cutline_items` captured "0\n0", the `[ -gt 0 ]`
# test errored, the && short-circuited, and the whole cutline comparison
# was silently skipped (no [WARN] about missing MVP items). Post-fix the
# integer comparison sees 0 cleanly and the comparison block runs.
#
# We also seed recorded_features=3 so when the block DOES run post-fix,
# we know the comparison would have fired had cutline_items been valid.
# The post-fix path takes the `cutline_items=0` branch which just skips
# the inner compare; the regression we assert is the absence of any
# "integer expression expected" leak — that's the true smoking gun.
echo "T1: zero-cutline-items + recorded_features=3 → no integer leak, no false [OK]"
setup
seed_clean_bugs
cat > "$PROJ/FEATURES.md" <<'MD'
# FEATURES

## Feature A
## Feature B
## Feature C
MD
cat > "$PROJ/PRODUCT_MANIFESTO.md" <<'MD'
# PRODUCT_MANIFESTO

## MVP Cutline

### Must-Have
(operator forgot to fill in the bulleted items)

### Should-Have
(later)
MD
cat > "$PROJ/.claude/build-progress.json" <<'JSON'
{"features_completed":["a","b","c"],"features_since_last_test":0,"test_interval":2}
JSON
out=$(run_gate)
if echo "$out" | grep -q "integer expression expected"; then
  fail_ "T1" "still leaks 'integer expression expected'; out:\n$(echo "$out" | grep -i integer)"
else
  pass "T1: zero-cutline-items no longer leaks 'integer expression expected'"
fi
teardown

# T2: Populated FEATURES.md + populated Must-Have section + recorded
# features less than cutline items. Post-fix the cutline-comparison
# WARN must fire ("Feature count (...) < MVP Cutline items (...)").
# Pre-fix the WARN never fired because the outer `if` short-circuited.
echo "T2: cutline=5, recorded=2 → WARN 'Feature count (2) < MVP Cutline items (5)'"
setup
seed_clean_bugs
cat > "$PROJ/FEATURES.md" <<'MD'
# FEATURES

## Feature A
## Feature B
MD
cat > "$PROJ/PRODUCT_MANIFESTO.md" <<'MD'
# PRODUCT_MANIFESTO

## MVP Cutline

### Must-Have
- **Feature A** — desc
- **Feature B** — desc
- **Feature C** — desc
- **Feature D** — desc
- **Feature E** — desc

### Should-Have
- (none)
MD
cat > "$PROJ/.claude/build-progress.json" <<'JSON'
{"features_completed":["a","b"],"features_since_last_test":0,"test_interval":2}
JSON
out=$(run_gate)
if echo "$out" | grep -qE "WARN.*Feature count \(2\) < MVP Cutline items \(5\)"; then
  pass "T2: cutline-comparison WARN fires (pre-fix was silently skipped)"
else
  fail_ "T2" "expected cutline WARN; out:\n$(echo "$out" | grep -iE 'cutline|feature count')"
fi
teardown

# T3: Matched cutline + matched features → [OK] "Feature count matches
# MVP Cutline (3 features)". Regression guard for the happy path.
echo "T3: cutline=3, recorded=3 → [OK] 'matches MVP Cutline'"
setup
seed_clean_bugs
cat > "$PROJ/FEATURES.md" <<'MD'
# FEATURES

## Feature A
## Feature B
## Feature C
MD
cat > "$PROJ/PRODUCT_MANIFESTO.md" <<'MD'
# PRODUCT_MANIFESTO

## MVP Cutline

### Must-Have
- **Feature A** — desc
- **Feature B** — desc
- **Feature C** — desc

### Should-Have
- (none)
MD
cat > "$PROJ/.claude/build-progress.json" <<'JSON'
{"features_completed":["a","b","c"],"features_since_last_test":0,"test_interval":2}
JSON
out=$(run_gate)
if echo "$out" | grep -qE "OK.*Feature count matches MVP Cutline \(3 features\)"; then
  pass "T3: happy-path [OK] still fires (regression guard)"
else
  fail_ "T3" "expected '[OK] matches MVP Cutline'; out:\n$(echo "$out" | grep -iE 'cutline|feature count')"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Latent sites: bug counters (currently armored, regression guard) ==="
# ════════════════════════════════════════════════════════════════════

# T4: BUGS.md has the table header text but zero matches for any SEV
# pattern → all four sev counters capture zero. Currently safe via the
# `tr -d '[:space:]'` armor ("0\n0" → "00", arithmetic OK). Post-fix
# the case-statement reduces "00" to "0" but the visible behavior must
# be unchanged: all four [OK] lines and exit 0.
echo "T4: zero bugs in BUGS.md → all four [OK] still fire (armor + sanitizer co-exist)"
setup
cat > "$PROJ/BUGS.md" <<'MD'
# BUGS.md

| # | Severity | Status | Feature | Description |
|---|----------|--------|---------|-------------|
| 1 | SEV-1    | Fixed  | foo     | something   |

(all open bugs resolved)
MD
out=$(run_gate)
ok_count=$(echo "$out" | grep -c 'No open SEV-1\|No open SEV-2 fix-now\|No deferred SEV-2\|No open SEV-3' || true)
case "$ok_count" in ''|*[!0-9]*) ok_count=0 ;; esac
if echo "$out" | grep -q "integer expression expected"; then
  fail_ "T4" "integer leak on zero-bug scenario; out:\n$(echo "$out" | grep -i integer)"
elif [ "$ok_count" -ge 4 ]; then
  pass "T4: all four bug-counter [OK] lines fire (latent sites still behave correctly)"
else
  fail_ "T4" "expected 4 [OK] bug lines, got $ok_count; out:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== Defect-class verification: no 'integer expression expected' ==="
# ════════════════════════════════════════════════════════════════════

# T5: Across the worst-case combination (BUGS.md present + zero matches,
# FEATURES.md present + zero matches, PRODUCT_MANIFESTO.md present + zero
# matches, build-progress.json with empty features_completed), the script
# must NOT print bash's 'integer expression expected' error to stderr at
# any point. Pre-fix this leaked from sites 373/375/395.
echo "T5: worst-case zero-match across all counter sites → no integer leak"
setup
cat > "$PROJ/BUGS.md" <<'MD'
# BUGS.md
(no matches)
MD
: > "$PROJ/FEATURES.md"
: > "$PROJ/PRODUCT_MANIFESTO.md"
cat > "$PROJ/.claude/build-progress.json" <<'JSON'
{"features_completed":[],"features_since_last_test":0,"test_interval":2}
JSON
out=$(run_gate)
if echo "$out" | grep -q "integer expression expected"; then
  fail_ "T5" "integer leak on worst-case zero-match; out:\n$(echo "$out" | grep -i integer)"
else
  pass "T5: no 'integer expression expected' across zero-match worst case"
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
