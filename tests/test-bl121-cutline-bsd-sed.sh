#!/usr/bin/env bash
# tests/test-bl121-cutline-bsd-sed.sh — BL-121: the MVP-Cutline counter must
# count the SAME 3 items on BSD and GNU text tools.
#
# WHY THIS EXISTS (Dogfood-2 finding F-DF2-011, High)
#   test-gate.sh counted cutline items with
#     sed -n '/Must-Have/,/Should-Have\|Will-Not-Have\|---/p'
#   `\|` is GNU-sed alternation; BSD/macOS sed treats it as the LITERAL two
#   characters, so the range terminator never matches and the range runs to
#   EOF — every `- **bold**` bullet in the whole manifesto is counted. On the
#   real Dogfood-2 project this reported 68 items against the true 3, the
#   `Feature count < MVP Cutline items` WARN fired, test-gate exited 2, and
#   check-phase-gate's bug-gate arm ran `issues+=1` on that exit — a hard
#   block of the production Phase 3→4 gate on every Mac, unpassable by any
#   honest means ([WARN] trap: the label says warn, the increment blocks).
#
#   The fix (# BL-121-CUTLINE-COUNT in scripts/test-gate.sh) replaces the sed
#   range with an awk range — awk range patterns take real POSIX EREs on both
#   platforms (`/Should-Have|Will-Not-Have|^---/`). The companion durable fix
#   extends lint-counter-antipattern.sh to flag basic-mode sed alternation so
#   the class cannot recur (see test-lint-counter-antipattern.sh T11/T12).
#
# HOW IT TESTS
#   Extracts the LIVE `cutline_items=$(…)` assignment from scripts/test-gate.sh
#   (asserting it is unique — the extraction is the same pipeline the gate
#   runs, so this cannot drift from the product code) and evaluates it against
#   a fixture manifesto that encodes the REAL template's trap structure:
#   "Must-Have" recurs inside the Section-5 cutline block (re-opening the
#   range), `---` rules terminate it, and bold decoy bullets sit in
#   Should-Have / Will-Not-Have / later sections. Correct count: 3. The
#   BSD-sed-runoff bug counts every bold bullet (8 here, 68 on the real walk).
#
#   NOTE ON PLATFORMS: the behavioural RED for the `\|` regression reproduces
#   on BSD sed (macOS — the dev platform). On GNU hosts the buggy line counts
#   correctly, so CI's guard for this class is the lint rule, which is
#   platform-independent. Both directions are covered; see the lint self-test.
#
# REGISTRATION: no init.sh, not an aggregator -> BOTH
# tests/full-project-test-suite.sh AND the tests.yml unit lane.
#
# Hermetic: mktemp fixture, no git, no network. bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

TG="$REPO_ROOT/scripts/test-gate.sh"

# ── Extract the live counting pipeline ───────────────────────────────────────
matches=$(grep -c 'cutline_items=\$(' "$TG")
if [ "$matches" -ne 1 ]; then
  fail_ "extraction" "expected exactly 1 cutline_items assignment in test-gate.sh, found $matches — update the extraction"
  echo ""
  echo "Results: $PASSED passed, $FAILED failed"
  exit 1
fi
ASSIGN=$(grep 'cutline_items=\$(' "$TG" | sed 's/^[[:space:]]*//')

# ── Fixture manifesto: 3 true cutline items + the template's trap structure ──
FIX="$TOPTMP/proj"
mkdir -p "$FIX"
cat > "$FIX/PRODUCT_MANIFESTO.md" <<'EOF'
# Product Manifesto — BL-121 fixture

## 2. Features

### Must-Have (MVP)

- **Open file:** If the user picks a file, the system must display it.
- **Find in doc:** If the user searches, the system must highlight matches.
- **Font size:** If the user clicks A+, the system must persist the size.

### Should-Have (v1.1)

- **Decoy one:** post-MVP enhancement.
- **Decoy two:** post-MVP enhancement.

### Will-Not-Have (Explicit Exclusions)

- **Decoy three:** never built.

## 5. MVP Cutline

**Above the line (MVP — ships first):**
- Open file (from Section 2 Must-Have list)
- Find in doc (from Section 2 Must-Have list)

---

**CUTLINE — nothing below this line is built in Phase 2 without approval**

---

**Below the line (Post-MVP):**
- Decoy from Should-Have list or deferred Must-Have

---

## 6. Post-MVP Backlog

- **Decoy four:** someday.
- **Decoy five:** maybe.
EOF

# ── T-counts-three ───────────────────────────────────────────────────────────
echo "=== T-counts-three ==="
count=$( cd "$FIX" && eval "$ASSIGN" && printf '%s' "$cutline_items" )
# Canonical sanitizer (same as the line following the assignment in the gate).
case "$count" in ''|*[!0-9]*) count=0 ;; esac
if [ "$count" -eq 3 ]; then
  pass "T-counts-three (cutline_items=3)"
else
  fail_ "T-counts-three" "cutline_items=$count, want 3 — with the GNU-only backslash-pipe alternation the terminator never matches on BSD and the range runs to EOF, counting every bold bullet (BL-121: 68 vs 3 on the real walk)"
fi

# ── T-no-cutline-counts-zero ─────────────────────────────────────────────────
echo "=== T-no-cutline-counts-zero ==="
FIX0="$TOPTMP/proj0"
mkdir -p "$FIX0"
printf '# Empty manifesto\n\nNo cutline here.\n' > "$FIX0/PRODUCT_MANIFESTO.md"
count0=$( cd "$FIX0" && eval "$ASSIGN" && printf '%s' "$cutline_items" )
case "$count0" in ''|*[!0-9]*) count0=0 ;; esac
if [ "$count0" -eq 0 ]; then
  pass "T-no-cutline-counts-zero"
else
  fail_ "T-no-cutline-counts-zero" "cutline_items=$count0, want 0"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
