#!/usr/bin/env bash
# tests/test-bl089-doc-foundations.sh — BL-089 + BL-091 (Pantheon feedback A+C,
# Karl-approved 2026-07-20): the documentation foundations ship at project
# birth, and the builders-guide carries the documentation-rules doctrine.
#
# THE DEFECT CLASS (Pantheon's month, verbatim)
#   Identifier-namespace collisions (four unrelated "D" schemes), a ghost
#   "ADR-0003" cited for three weeks, unmarked superseded docs. The framework
#   scaffolded NO doc map, NO identifier registry, NO archive convention —
#   and the guide had no documentation rules to violate.
#
# WHAT THIS PINS (text-derived — no init.sh run, so unit-lane eligible)
#   T1  the three templates exist with their load-bearing grammar:
#       doc-index.tmpl (authority order + conventions), identifiers.tmpl
#       (the APPROVED pre-seed: TM-/ADR-/BUG-/UAT-/SEV + three rules),
#       archive-readme.tmpl (move-with-banner + pointer-stub convention).
#   T2  init.sh ships AND instantiates all three (cp-line derivation, the
#       ship-closure test's textual idiom) inside the # BL-089-DOC-FOUNDATIONS
#       fence.
#   T3  builders-guide "Documentation Rules" section carries all seven rules'
#       anchors (corrections-above, ledger-vs-living, premise-carrying
#       absolutes, single-home, enforcement banners, fail-closed loudness,
#       non-operator attribution).
#   T4  project-bible.tmpl's TM-001 row is the REAL standing silently-
#       degraded-subsystem threat (rule 6b: a gate, not prose — the Phase-3
#       threat-model scanner already demands validation of every TM row;
#       bracket-placeholder content made that demand vacuous at birth).
#       Scanner-count-neutral by construction: TM-001 token before and after.
#   T5  fence-excision mutant — cutting the init.sh fence removes ALL
#       instantiation lines (the fence is load-bearing; vacuity-guarded).
#
# The REAL-init companion case (T-scaffold-doc-foundations in
# tests/test-scaffold-tdd-block-real.sh) proves the artifacts land on disk in
# a real scaffold — this suite pins content and wiring text.
#
# REGISTRATION: no init.sh RUN (text greps only) → BOTH lists. Hermetic.
# bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TPL="$REPO_ROOT/templates/generated"

# ── T1: the three templates exist with their load-bearing grammar ────────────
echo "=== T1-templates-exist-with-grammar ==="
t1_ok=true
for f in doc-index.tmpl identifiers.tmpl archive-readme.tmpl; do
  if [ ! -f "$TPL/$f" ]; then t1_ok=false; echo "  missing: templates/generated/$f"; fi
done
if [ "$t1_ok" = true ]; then
  grep -q 'canon > dated design docs > archive' "$TPL/doc-index.tmpl" || { t1_ok=false; echo "  doc-index: authority order absent"; }
  grep -qi 'conventions' "$TPL/doc-index.tmpl" || { t1_ok=false; echo "  doc-index: conventions section absent"; }
  for prefix in 'TM-' 'ADR-' 'BUG-' 'UAT-' 'SEV-1'; do
    grep -q "\`$prefix" "$TPL/identifiers.tmpl" || { t1_ok=false; echo "  identifiers: $prefix row absent"; }
  done
  grep -qi 'one prefix, one meaning' "$TPL/identifiers.tmpl" || { t1_ok=false; echo "  identifiers: rule 1 absent"; }
  grep -qi 'IDs are permanent' "$TPL/identifiers.tmpl" || { t1_ok=false; echo "  identifiers: rule 2 absent"; }
  grep -qi 'register here first' "$TPL/identifiers.tmpl" || { t1_ok=false; echo "  identifiers: rule 3 absent"; }
  grep -qi 'pointer stub' "$TPL/archive-readme.tmpl" || { t1_ok=false; echo "  archive-readme: pointer-stub rule absent"; }
  grep -qi 'status banner' "$TPL/archive-readme.tmpl" || { t1_ok=false; echo "  archive-readme: status-banner rule absent"; }
fi
if [ "$t1_ok" = true ]; then
  pass "T1-templates-exist-with-grammar"
else
  fail_ "T1-templates-exist-with-grammar" "see lines above"
fi

# ── T2: init.sh ships + instantiates all three, inside the fence ─────────────
echo "=== T2-init-ships-and-instantiates ==="
check_init_wiring() {  # <init-file> → 0 iff all six wiring lines present
  local f="$1"
  grep -q 'templates/generated/doc-index.tmpl" templates/generated/' "$f" \
    && grep -q 'templates/generated/identifiers.tmpl" templates/generated/' "$f" \
    && grep -q 'templates/generated/archive-readme.tmpl" templates/generated/' "$f" \
    && grep -q 'doc-index.tmpl" docs/INDEX.md' "$f" \
    && grep -q 'identifiers.tmpl" docs/IDENTIFIERS.md' "$f" \
    && grep -q 'archive-readme.tmpl" docs/archive/README.md' "$f"
}
if check_init_wiring "$REPO_ROOT/init.sh" \
   && grep -q '# BL-089-DOC-FOUNDATIONS-BEGIN' "$REPO_ROOT/init.sh" \
   && grep -q '# BL-089-DOC-FOUNDATIONS-END' "$REPO_ROOT/init.sh"; then
  pass "T2-init-ships-and-instantiates"
else
  fail_ "T2-init-ships-and-instantiates" "init.sh lacks the fenced cp/instantiate lines for the three foundations"
fi

# ── T3: builders-guide Documentation Rules section, all seven anchors ────────
echo "=== T3-guide-doc-rules-section ==="
G="$REPO_ROOT/docs/builders-guide.md"
t3_ok=true
grep -q '^## Documentation Rules' "$G" || { t3_ok=false; echo "  section header absent"; }
grep -qi 'Corrections appear ABOVE' "$G" || { t3_ok=false; echo "  rule 1 (corrections-above) absent"; }
grep -qi 'Ledgers append; living documents are rewritten' "$G" || { t3_ok=false; echo "  rule 2 (ledger vs living) absent"; }
grep -qi 'records the premise beside it' "$G" || { t3_ok=false; echo "  rule 3 (premise-carrying absolutes) absent"; }
grep -qi 'ONE canonical home' "$G" || { t3_ok=false; echo "  rule 4 (single-home) absent"; }
grep -qi 'gate scripts as canonical' "$G" || { t3_ok=false; echo "  rule 5 (enforcement banner) absent"; }
grep -qi 'silently degraded subsystem' "$G" || { t3_ok=false; echo "  rule 6 (fail-closed loudness) absent"; }
grep -qi 'attributed inline' "$G" || { t3_ok=false; echo "  rule 7 (non-operator attribution) absent"; }
if [ "$t3_ok" = true ]; then
  pass "T3-guide-doc-rules-section"
else
  fail_ "T3-guide-doc-rules-section" "see lines above"
fi

# ── T4: the Bible's TM-001 row is the REAL standing threat ───────────────────
echo "=== T4-bible-standing-threat-row ==="
B="$TPL/project-bible.tmpl"
tm_row=$(grep -E '^\| TM-001 \|' "$B" 2>/dev/null | head -1) || tm_row=""
if [ -n "$tm_row" ] \
   && printf '%s' "$tm_row" | grep -qi 'silently' \
   && ! printf '%s' "$tm_row" | grep -q '\[Specific threat\]'; then
  # Scanner-count neutrality: exactly the SAME TM-id set as before the change
  # (one id, TM-001) — the standing row REPLACED the placeholder, not joined it.
  n=$(grep -E '\|' "$B" | grep -oE 'TM-[0-9]{3,}' | sort -u | grep -c .) || n=0
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  if [ "$n" -eq 1 ]; then
    pass "T4-bible-standing-threat-row (TM-001 is real, and the scanner's id-set is unchanged)"
  else
    fail_ "T4-bible-standing-threat-row" "TM-id set changed (count=$n, expected 1) — scanner neutrality broken"
  fi
else
  fail_ "T4-bible-standing-threat-row" "TM-001 row is absent or still the bracket placeholder (rule 6b unimplemented)"
fi

# ── T5: fence-excision mutant on the init.sh wiring ──────────────────────────
echo "=== T5-fence-excision-mutant ==="
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
m=$(grep -c 'BL-089-DOC-FOUNDATIONS' "$REPO_ROOT/init.sh") || m=0
case "$m" in ''|*[!0-9]*) m=0 ;; esac
sed '/# BL-089-DOC-FOUNDATIONS-BEGIN/,/# BL-089-DOC-FOUNDATIONS-END/d' \
  "$REPO_ROOT/init.sh" > "$TMP/init.mut.sh"
l=$(grep -c 'BL-089-DOC-FOUNDATIONS' "$TMP/init.mut.sh") || l=0
case "$l" in ''|*[!0-9]*) l=0 ;; esac
if [ "$m" -lt 2 ] || [ "$l" -ne 0 ]; then
  fail_ "T5-fence-excision-mutant" "excision vacuous (markers before=$m after=$l)"
elif check_init_wiring "$TMP/init.mut.sh"; then
  fail_ "T5-fence-excision-mutant" "mutant init.sh still carries the wiring — the foundations do not live (only) inside the fence"
else
  pass "T5-fence-excision-mutant (excision removes the whole wiring — the fence is load-bearing)"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
