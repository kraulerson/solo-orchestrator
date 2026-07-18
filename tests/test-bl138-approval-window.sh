#!/usr/bin/env bash
# tests/test-bl138-approval-window.sh — BL-138 (Dogfood-3 F-DF3-001):
# validate_approval_fields must not self-collide with the template.
#
# THE DEFECT (walk-proven on a FULLY-FILLED gate entry)
#   `grep -A 20 "$gate_name"` re-anchors on the `| **Gate** | Phase 0 → 1 |`
#   ROW and bleeds past the section into the BL-105/115 UAT/Attorney
#   PLACEHOLDER rows below; and the predicate's any-bracket arm
#   (`(Approver|Reviewer).*\[.*\]`) plus its BARE `YYYY-MM-DD` arm flag
#   legitimate content — the dogfood-required `[SIMULATED]` annotation and
#   date-format prose. Result: the FIRST gate refused while following the
#   template's own conventions, diagnostic naming the wrong fix. Same
#   window-bleed class killed twice already (verifier SF#1 in
#   _cpg_gate_has_evidence; E1b Claim-C in # BL-115-ATTORNEY-ENTRY) — this
#   was the missed arm.
#
# THE CONTRACT (# BL-138-APPROVAL-WINDOW)
#   Window = H2-header-anchored (`^## ` + the gate regex), stop at the next
#   `^## `, cap +20 — table rows can no longer anchor or extend the scan.
#   Predicate = TEMPLATE-LITERAL placeholders only: `[YYYY-MM-DD]` and
#   `[Name`-prefixed brackets (the shapes the shipped templates carry).
#   `[SIMULATED]` and bare date-format prose are NOT placeholders.
#
# ISOLATION: twin fixtures (annotated+downstream-placeholders vs plain) must
# produce IDENTICAL rc — the arm's verdict is measured by the WARN line and
# rc PARITY, not by a golden all-green fixture.
#
# REGISTRATION: no init.sh, not an aggregator → BOTH lists. Hermetic.
# bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq required"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

WARN_RE="placeholder values"

# mk_proj <dir> <gate-section-extra> <downstream>  — phase-1 project with a
# dated 0→1 gate; the APPROVAL_LOG's 0→1 section is FILLED (template shape),
# optionally annotated/extended, optionally followed by placeholder-bearing
# downstream sections (the template's UAT/Attorney scaffolding).
mk_proj() {
  local d="$1" extra="$2" downstream="$3"
  rm -rf "$d"
  mkdir -p "$d/.claude" "$d/scripts/lib" "$d/docs/phase-0"
  ( cd "$d" && git init -q && git config user.email t@t.invalid && git config user.name t \
      && echo x > seed && git add seed && git commit -q -m "chore: init" ) || return 1
  cat > "$d/.claude/phase-state.json" <<'JSON'
{"current_phase":1,"track":"standard","deployment":"personal","poc_mode":null,"gates":{"phase_0_to_1":"2026-07-18"}}
JSON
  printf 'frd\n' > "$d/docs/phase-0/frd.md"
  printf 'journey\n' > "$d/docs/phase-0/user-journey.md"
  printf 'contract\n' > "$d/docs/phase-0/data-contract.md"
  {
    echo "# PRODUCT_MANIFESTO"
    for i in 1 2 3 4 5 6 7 8; do
      echo "## ${i}. Section ${i}"
      echo "Real content for section ${i}."
      echo ""
    done
  } > "$d/PRODUCT_MANIFESTO.md"
  {
    echo "# Approval Log"
    echo ""
    echo "## Phase Gate: Phase 0 → Phase 1"
    echo ""
    echo "| Field | Value |"
    echo "|---|---|"
    echo "| **Gate** | Phase 0 → Phase 1 |"
    echo "| **Reviewer** | Karl Raulerson${extra} |"
    echo "| **Date** | 2026-07-18 |"
    echo "| **Decision** | Approved |"
    echo ""
    if [ -n "$downstream" ]; then
      echo "---"
      echo ""
      echo "## UAT Sign-off (if applicable)"
      echo ""
      echo "| Field | Value |"
      echo "|---|---|"
      echo "| **Signed off by** | [Name — the accepting stakeholder] |"
      echo "| **Date** | [YYYY-MM-DD] |"
      echo ""
      echo "## Attorney / Legal Review (if applicable)"
      echo ""
      echo "| Field | Value |"
      echo "|---|---|"
      echo "| **Reviewer** | [Attorney / firm name] |"
      echo "| **Date** | [YYYY-MM-DD] |"
    fi
  } > "$d/APPROVAL_LOG.md"
  cp "$REPO_ROOT/scripts/check-phase-gate.sh" "$d/scripts/"
  cp "$REPO_ROOT/scripts/lib/"*.sh "$d/scripts/lib/"
  chmod +x "$d/scripts/check-phase-gate.sh"
}

run_gate() { ( cd "$1" && bash scripts/check-phase-gate.sh </dev/null 2>&1 ); }

# ── T1 (the walk's repro): [SIMULATED] + downstream template placeholders ────
# must NOT trip the 0→1 placeholder warn, and rc must equal the plain twin's.
echo "=== T1-filled-gate-not-flagged ==="
PA="$TOPTMP/pa"; mk_proj "$PA" " [SIMULATED]" "yes"
PB="$TOPTMP/pb"; mk_proj "$PB" "" ""
outA=$(run_gate "$PA"); rcA=$?
outB=$(run_gate "$PB"); rcB=$?
if ! printf '%s' "$outA" | grep -qi "$WARN_RE" && [ "$rcA" -eq "$rcB" ]; then
  pass "T1-filled-gate-not-flagged (annotated + downstream placeholders ≡ plain twin, rc=$rcA)"
else
  fail_ "T1-filled-gate-not-flagged" "rcA=$rcA rcB=$rcB warn=$(printf '%s' "$outA" | grep -ci "$WARN_RE") — a FILLED gate entry was flagged as placeholder because of [SIMULATED] and/or the window bleeding into the template's downstream placeholder sections (F-DF3-001)"
fi

# ── T2: a REAL [YYYY-MM-DD] literal INSIDE the gate section still flags ──────
echo "=== T2-inline-date-placeholder-flagged ==="
PC="$TOPTMP/pc"; mk_proj "$PC" "" ""
python3 - "$PC/APPROVAL_LOG.md" <<'PYEOF' 2>/dev/null || sed -i.bak 's/| \*\*Date\*\* | 2026-07-18 |/| **Date** | [YYYY-MM-DD] |/' "$PC/APPROVAL_LOG.md"
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("| **Date** | 2026-07-18 |","| **Date** | [YYYY-MM-DD] |",1)
open(p,'w').write(s)
PYEOF
out=$(run_gate "$PC"); rc=$?
if printf '%s' "$out" | grep -qi "$WARN_RE"; then
  pass "T2-inline-date-placeholder-flagged"
else
  fail_ "T2-inline-date-placeholder-flagged" "rc=$rc — a literal [YYYY-MM-DD] in the gate's OWN Date cell escaped the detector (over-tightened): $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── T3: a [Name…] literal INSIDE the gate section still flags ────────────────
echo "=== T3-inline-name-placeholder-flagged ==="
PD="$TOPTMP/pd"; mk_proj "$PD" "" ""
python3 - "$PD/APPROVAL_LOG.md" <<'PYEOF' 2>/dev/null || sed -i.bak 's/| \*\*Reviewer\*\* | Karl Raulerson |/| **Reviewer** | [Name — the accepting operator] |/' "$PD/APPROVAL_LOG.md"
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("| **Reviewer** | Karl Raulerson |","| **Reviewer** | [Name — the accepting operator] |",1)
open(p,'w').write(s)
PYEOF
out=$(run_gate "$PD"); rc=$?
if printf '%s' "$out" | grep -qi "$WARN_RE"; then
  pass "T3-inline-name-placeholder-flagged"
else
  fail_ "T3-inline-name-placeholder-flagged" "rc=$rc — a literal [Name …] in the gate's OWN Reviewer cell escaped the detector: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── T4: bare date-format PROSE in the section is NOT a placeholder ───────────
echo "=== T4-bare-format-prose-not-flagged ==="
PE="$TOPTMP/pe"; mk_proj "$PE" "" ""
python3 - "$PE/APPROVAL_LOG.md" <<'PYEOF' 2>/dev/null || printf '| **Notes** | dates recorded in YYYY-MM-DD format |\n' >> "$PE/APPROVAL_LOG.md"
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("| **Decision** | Approved |","| **Decision** | Approved |\n| **Notes** | dates recorded in YYYY-MM-DD format |",1)
open(p,'w').write(s)
PYEOF
out=$(run_gate "$PE"); rc=$?
if ! printf '%s' "$out" | grep -qi "$WARN_RE"; then
  pass "T4-bare-format-prose-not-flagged"
else
  fail_ "T4-bare-format-prose-not-flagged" "prose mentioning the YYYY-MM-DD FORMAT tripped the placeholder detector — only the bracketed template literal is a placeholder"
fi

# ── T5: fence-excision mutant — the detector lives in the fence ──────────────
# Fixture uses the [Name…] REVIEWER shape with a REAL date: the BL-115
# date-evidence arm stays satisfied, so the ONLY thing standing between this
# fixture and rc=0 is the fenced placeholder detector (a [YYYY-MM-DD] date
# cell would also — correctly — trip the date-evidence arm and mask the
# mutant's verdict; first T5 draft proved that empirically).
echo "=== T5-fence-excision-mutant ==="
PF="$TOPTMP/pf"; mk_proj "$PF" "" ""
python3 - "$PF/APPROVAL_LOG.md" <<'PYEOF' 2>/dev/null || sed -i.bak 's/| \*\*Reviewer\*\* | Karl Raulerson |/| **Reviewer** | [Name — the accepting operator] |/' "$PF/APPROVAL_LOG.md"
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("| **Reviewer** | Karl Raulerson |","| **Reviewer** | [Name — the accepting operator] |",1)
open(p,'w').write(s)
PYEOF
sed '/# BL-138-APPROVAL-WINDOW-BEGIN/,/# BL-138-APPROVAL-WINDOW-END/d' \
  "$REPO_ROOT/scripts/check-phase-gate.sh" > "$PF/scripts/check-phase-gate.sh"
chmod +x "$PF/scripts/check-phase-gate.sh"
if grep -q "BL-138-APPROVAL-WINDOW" "$PF/scripts/check-phase-gate.sh"; then
  fail_ "T5-fence-excision-mutant" "excision left marker text — BEGIN/END malformed"
else
  out=$(run_gate "$PF"); rc=$?
  if ! printf '%s' "$out" | grep -qi "$WARN_RE" && [ "$rc" -eq 0 ]; then
    pass "T5-fence-excision-mutant (guardless mutant misses the in-section placeholder — the fence IS the detector)"
  else
    fail_ "T5-fence-excision-mutant" "rc=$rc warn=$(printf '%s' "$out" | grep -ci "$WARN_RE") — the excised mutant still detected (logic outside the fence) or crashed (vacuous): $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
