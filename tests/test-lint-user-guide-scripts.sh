#!/usr/bin/env bash
# tests/test-lint-user-guide-scripts.sh — pins scripts/lint-user-guide-scripts.sh
# (`## BL-254:`): the user guide's script table must match the shipped set in
# both directions, scoped to the one table, top-level scripts only.
#
# Fixture-driven: a scratch init.sh with literal cp lines, a scratch scripts/
# tree, and a scratch guide — the lint takes all three as flags so no case
# reads the real repo. Two mutants on a COPY of the lint, keyed to its two
# end-of-line-anchored markers.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINT="$REPO_ROOT/scripts/lint-user-guide-scripts.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }
_num() { case "$1" in ''|null|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac }
_sites() { local n; n=$(grep -c "$2\$" "$1" 2>/dev/null); _num "$n"; }

[ -f "$LINT" ] || { echo "  [FAIL] setup — $LINT not found"; echo ""; echo "Results: 0 passed, 1 failed"; exit 1; }

# mk_fixture <dir> — ships a.sh and b.sh (top-level) and lib/c.sh; the guide
# has rows for a.sh and b.sh inside the section, plus a decoy row for
# elsewhere.sh in a DIFFERENT section that must be ignored.
mk_fixture() {
  local d="$1"
  mkdir -p "$d/scripts/lib" || return 1
  printf '#!/usr/bin/env bash\n' > "$d/scripts/a.sh"
  printf '#!/usr/bin/env bash\n' > "$d/scripts/b.sh"
  printf '#!/usr/bin/env bash\n' > "$d/scripts/lib/c.sh"
  cat > "$d/init.sh" <<'INIT'
#!/usr/bin/env bash
  cp "$SCRIPT_DIR/scripts/a.sh" scripts/
  cp "$SCRIPT_DIR/scripts/b.sh" scripts/
  cp "$SCRIPT_DIR/scripts/lib/c.sh" scripts/lib/
INIT
  cat > "$d/user-guide.md" <<'GUIDE'
# Guide

## Something Else

| Script | Purpose |
|---|---|
| `elsewhere.sh` | a decoy row in another section |

## Quick Reference — Scripts

| Script | Purpose | Invocation | Phase |
|---|---|---|---|
| `a.sh` | does a | `bash scripts/a.sh` | Any |
| `b.sh` | does b | `bash scripts/b.sh` | Any |

## After
GUIDE
  return 0
}

run_lint() {   # run_lint <fixture> [lint-path] → sets RC, OUT
  local d="$1" l="${2:-$LINT}"
  OUT="$(bash "$l" --init "$d/init.sh" --scripts-dir "$d/scripts" --guide "$d/user-guide.md" 2>&1)"; RC=$?
  return 0
}

echo "=== U — the lint on fixtures ==="

U1="$(newtmp)"; mk_fixture "$U1"
run_lint "$U1"
[ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "^OK:" \
  && pass "U1 — a table that matches the shipped set exits 0 with an OK line" \
  || fail_ "U1" "rc=$RC out=$(printf '%s' "$OUT" | head -2 | tr '\n' ' ')"

U2="$(newtmp)"; mk_fixture "$U2"
printf '| `ghost.sh` | never shipped | Automatic (CI) | 2+ |\n' >> "$U2/user-guide.md"
# the row must be INSIDE the section: move the trailing '## After' below it
python3 - "$U2/user-guide.md" <<'PY' 2>/dev/null || {
import sys, io
p=sys.argv[1]; s=io.open(p,encoding="utf-8").read()
s=s.replace("\n## After\n","\n",1).rstrip("\n")+"\n\n## After\n"
io.open(p,"w",encoding="utf-8").write(s)
PY
  true; }
run_lint "$U2"
if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q "phantom: ghost.sh"; then
  pass "U2 — a row naming an unshipped script exits 1 and names it as a phantom"
else
  fail_ "U2" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-160)"
fi

U3="$(newtmp)"; mk_fixture "$U3"
printf '  cp "$SCRIPT_DIR/scripts/d.sh" scripts/\n' >> "$U3/init.sh"
printf '#!/usr/bin/env bash\n' > "$U3/scripts/d.sh"
run_lint "$U3"
if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q "missing: d.sh"; then
  pass "U3 — a shipped top-level script with no row exits 1 and names it as missing"
else
  fail_ "U3" "rc=$RC out=$(printf '%s' "$OUT" | tr '\n' ' ' | cut -c1-160)"
fi

U4="$(newtmp)"; mk_fixture "$U4"
run_lint "$U4"
printf '%s' "$OUT" | grep -q "missing: lib/c.sh\|missing: c.sh" \
  && fail_ "U4" "a lib/ script was demanded as a row — internals are out of scope" \
  || pass "U4 — shipped lib/ scripts are not demanded as rows (internals are out of scope)"

U5="$(newtmp)"; mk_fixture "$U5"
run_lint "$U5"
printf '%s' "$OUT" | grep -q "phantom: elsewhere.sh" \
  && fail_ "U5" "a row in a DIFFERENT section was read as a claim about scripts/" \
  || pass "U5 — rows outside '## Quick Reference — Scripts' are ignored (the decoy row did not register)"

U6="$(newtmp)"; mk_fixture "$U6"
OUT="$(bash "$LINT" --init "$U6/init.sh" --scripts-dir "$U6/scripts" --guide "$U6/user-guide.md" --list 2>&1)"
printf '%s' "$OUT" | grep -q "rows in the table:" && printf '%s' "$OUT" | grep -q "  a.sh" \
  && pass "U6 — --list renders the rows and the shipped set" \
  || fail_ "U6" "--list did not render: $(printf '%s' "$OUT" | head -2 | tr '\n' ' ')"

U7="$(newtmp)"; mk_fixture "$U7"
sed 's/^## Quick Reference — Scripts$/## Renamed Heading/' "$U7/user-guide.md" > "$U7/g2.md" && mv "$U7/g2.md" "$U7/user-guide.md"
run_lint "$U7"
[ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q "no rows found" \
  && pass "U7 — a renamed heading is a loud refusal, not a clean pass (vacuity floor)" \
  || fail_ "U7" "rc=$RC out=$(printf '%s' "$OUT" | head -1)"

echo "=== M — mutation proofs on a copy of the lint ==="

M_PH="# BL-254-PHANTOM-ROW"
M_MI="# BL-254-MISSING-ROW"
for _m in "$M_PH" "$M_MI"; do
  _n="$(_sites "$LINT" "$_m")"
  [ "$_n" = "1" ] \
    && pass "M0 — '$_m' occurs exactly once at end-of-line in the lint" \
    || fail_ "M0" "'$_m' occurs $_n times (need exactly 1)"
done

# M1 — neuter the phantom derivation: U2's case must go green (i.e. the mutant survives U2 → U2 is what kills it)
M1="$(newtmp)"; cp "$LINT" "$M1/lint.sh"; cp -Rp "$REPO_ROOT/scripts/lib" "$M1/lib" 2>/dev/null
mkdir -p "$M1/scripts" && cp -Rp "$REPO_ROOT/scripts/lib" "$M1/scripts/lib"
sed "s|^phantom=.*$M_PH\$|phantom=\"\"   $M_PH|" "$M1/lint.sh" > "$M1/lint2.sh" && mv "$M1/lint2.sh" "$M1/scripts/lint.sh"
if ! bash -n "$M1/scripts/lint.sh" 2>/dev/null || ! grep -q '^phantom=""' "$M1/scripts/lint.sh"; then
  fail_ "M1 setup" "the phantom mutation did not apply cleanly"
else
  M1F="$(newtmp)"; mk_fixture "$M1F"
  printf '| `ghost.sh` | never shipped | Automatic (CI) | 2+ |\n' >> "$M1F/user-guide.md"
  run_lint "$M1F" "$M1/scripts/lint.sh"
  printf '%s' "$OUT" | grep -q "phantom: ghost.sh" \
    && fail_ "M1 (MUTATION)" "neutering the phantom derivation changed nothing — U2 may be passing for another reason" \
    || pass "M1 (MUTATION) — with the phantom derivation neutered the ghost row passes: U2 is what catches it"
fi

# M2 — neuter the missing derivation: U3's case must go green
M2="$(newtmp)"; mkdir -p "$M2/scripts" && cp -Rp "$REPO_ROOT/scripts/lib" "$M2/scripts/lib"
sed "s|^missing=.*$M_MI\$|missing=\"\"   $M_MI|" "$LINT" > "$M2/scripts/lint.sh"
if ! bash -n "$M2/scripts/lint.sh" 2>/dev/null || ! grep -q '^missing=""' "$M2/scripts/lint.sh"; then
  fail_ "M2 setup" "the missing mutation did not apply cleanly"
else
  M2F="$(newtmp)"; mk_fixture "$M2F"
  printf '  cp "$SCRIPT_DIR/scripts/d.sh" scripts/\n' >> "$M2F/init.sh"
  printf '#!/usr/bin/env bash\n' > "$M2F/scripts/d.sh"
  run_lint "$M2F" "$M2/scripts/lint.sh"
  printf '%s' "$OUT" | grep -q "missing: d.sh" \
    && fail_ "M2 (MUTATION)" "neutering the missing derivation changed nothing — U3 may be passing for another reason" \
    || pass "M2 (MUTATION) — with the missing derivation neutered the unlisted script passes: U3 is what catches it"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] && exit 0
exit 1
