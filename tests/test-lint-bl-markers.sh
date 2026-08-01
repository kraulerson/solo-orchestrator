#!/usr/bin/env bash
# tests/test-lint-bl-markers.sh
#
# Behavior tests for scripts/lint-bl-markers.sh — the BL-196 marker-citation
# backstop. Each case stages a hermetic tmpdir tree (a fake code surface, a
# fake backlog, fake prose), points the lint at it with --root, and asserts
# on exit code + diagnostics.
#
# CORE COVERAGE (the defect class BL-196 files)
#   • T2 (negative): prose cites a marker that exists nowhere in the code
#       surface -> exit 1, and the diagnostic NAMES the cite and where.
#   • T13 (mutation): excise the BL-196-PROSE-CITE fence from a copy of the
#       lint and T2's fixture PASSES -> the fence carries the whole check.
#
# SURROUNDING COVERAGE
#   • T1  clean tree -> exit 0
#   • T3  marker in code whose BL-NNN has no `## BL-NNN:` entry -> exit 1
#   • T4  FAMILY resolution: prose cites the fence family, code carries
#         -BEGIN/-END -> exit 0
#   • T5  glob form `# BL-...-*` resolves the same way -> exit 0
#   • T6  a TRUNCATION typo does NOT get rescued by the family rule
#   • T7  false-positive guards: bare prose hyphenation and the literal
#         `# BL-NNN-…` placeholder are not citations
#   • T8  frozen surfaces (Reports/, docs/handoffs/archive/) are out of scope
#   • T9  inline allow with a reason suppresses; an EMPTY reason fails
#   • T10 --list emits the STATUS table including the FAIL row
#   • T11 unknown flag -> exit 2
#   • T12 vacuity floor -> exit 2 (pass c)
#   • T-REPO / T-REPO-LIST: the real tree passes, and the script-level
#         allowlist is live (>=1 rendered allowlist row)
#
# A NOTE ON THIS SUITE'S OWN TEXT, because it is a real hazard here.
# This file lives under tests/, which IS the lint's code surface — every
# marker-shaped token written below becomes a marker DEFINITION on the real
# tree. Two consequences are designed around:
#   1. Fixture markers use the `BL-196-FIXTURE-*` family, so pass (a) on the
#      real tree resolves them to the existing `## BL-196:` entry.
#   2. The no-entry id for T3 is BUILT BY CONCATENATION and never appears
#      here as a literal. Writing it out would mint a marker on the real
#      tree naming an entry that does not exist, and this suite would red
#      the repo it is meant to guard.
# For the same reason no fixture cites a token that the real backlog also
# cites: a fixture literal would silently satisfy a real broken citation.
#
# Style mirrors tests/test-lint-doc-anchors.sh: set -uo pipefail, mktemp
# fixtures, pass/fail counters, teardown after each case.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINTER="$REPO_ROOT/scripts/lint-bl-markers.sh"

if [ ! -f "$LINTER" ]; then
  echo "FATAL: linter not found at $LINTER" >&2
  exit 2
fi

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# ── Fixture builder ─────────────────────────────────────────────────────
# A minimal tree with the shapes the lint cares about: one code dir, a
# backlog carrying two entry headers, and an empty docs/ ready for prose.
setup_fixture() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/scripts" "$TMP/docs"
  cat > "$TMP/solo-orchestrator-backlog.md" <<'MD'
# fixture backlog

## BL-196: fixture entry the fixture markers hang off

**Status:** Open

---

## BL-042: second fixture entry

**Status:** Closed — PR #1

---
MD
  cat > "$TMP/scripts/thing.sh" <<'SH'
#!/usr/bin/env bash
# BL-196-FIXTURE-LIVE: a marker that really is in the code surface.
echo live
# BL-196-FIXTURE-FENCE-BEGIN
echo fenced
# BL-196-FIXTURE-FENCE-END
SH
}
teardown_fixture() { rm -rf "$TMP"; }

run_fixture() { bash "$LINTER" --root "$TMP" 2>&1; return $?; }

# ── allowlisted_tokens: the lint's SCRIPT-LEVEL allowlist, read out of the
# lint at runtime. Deliberately not hard-coded: writing an allowlisted token
# into this file would mint it in tests/, the real tree's code surface, and
# the real backlog's broken citations would then resolve EXACT off this
# suite — masking the very thing the allowlist documents.
allowlisted_tokens() {
  sed -n '/BL-196-ALLOWLIST-BEGIN/,/BL-196-ALLOWLIST-END/p' "${1:-$LINTER}" \
    | grep -E '^BL-[0-9]+[a-z]?-[A-Za-z][A-Za-z0-9_-]*\|' \
    | sed -e 's/|.*//'
}

# ── unaccounted_allowlist_tokens: the T-REPO-LIST predicate, factored out so
# T17 can run it against a deliberately-corrupted allowlist. Scans the REAL
# tree with the given lint and echoes one line per allowlisted token that has
# NEITHER its own `allowlist:` row NOR its own `resolved (EXACT)` row.
#
# PER-TOKEN, not a global disjunction. An earlier draft short-circuited on
# "at least one row rendered anywhere", which let a bogus or stale allowlist
# entry ride along green behind the real rows — the accounting has to be owed
# by each token individually or it accounts for nothing.
unaccounted_allowlist_tokens() {
  local lint="${1:-$LINTER}" root="${2:-}" out t
  if [ -n "$root" ]; then
    out=$(bash "$lint" --root "$root" --list 2>&1)
  else
    out=$(bash "$lint" --list 2>&1)
  fi
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    printf '%s\n' "$out" | grep -qF "$(printf '\t%s\tresolved (EXACT)' "$t")" && continue
    printf '%s\n' "$out" | grep -qF "$(printf '\t%s\tallowlist: ' "$t")" && continue
    printf '%s\n' "$t"
  done <<EOF
$(allowlisted_tokens "$lint")
EOF
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: prose cite that resolves exactly -> exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

The live arm is marked `# BL-196-FIXTURE-LIVE` — grep for it.
MD
out=$(run_fixture); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "OK:"; then
  pass "T1: resolving citation exits 0"
else
  fail_ "T1" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: prose cites a marker that exists nowhere -> exit 1, named ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

The live arm is marked `# BL-196-FIXTURE-LIVE` — grep for it.
The renamed arm is marked `# BL-196-FIXTURE-GHOST`, which no longer exists.
MD
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -q 'CLAUDE\.md:4' \
   && echo "$out" | grep -q 'BL-196-FIXTURE-GHOST'; then
  pass "T2: broken citation exits 1 naming the token AND file:line"
else
  fail_ "T2" "expected exit 1 + 'CLAUDE.md:4' + the ghost token; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: code marker whose BL-NNN has no backlog entry -> exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# The id is assembled at runtime so this suite's own text never mints a
# marker naming a nonexistent entry on the real tree (see header note).
setup_fixture
NOENT_ID="BL-9""97"
{
  printf '#!/usr/bin/env bash\n'
  printf '# %s-NO-SUCH-ENTRY: minted against an id nobody filed.\n' "$NOENT_ID"
  printf 'echo orphan\n'
} > "$TMP/scripts/orphan.sh"
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

The live arm is marked `# BL-196-FIXTURE-LIVE`.
MD
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -q 'scripts/orphan\.sh:2' \
   && echo "$out" | grep -q "no '## ${NOENT_ID}:' entry"; then
  pass "T3: marker naming a nonexistent entry exits 1 naming the site"
else
  fail_ "T3" "expected exit 1 + orphan.sh:2 + missing-entry text; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T4: FAMILY resolution — prose cites the fence family -> exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

The fenced arm is `# BL-196-FIXTURE-FENCE` (BEGIN/END in the code).
MD
out=$(run_fixture); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "OK:"; then
  pass "T4: family cite resolves against the -BEGIN/-END pair"
else
  fail_ "T4" "expected exit 0 for the family cite; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T5: glob form '# BL-...-*' resolves the same way -> exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

Per the fenced-arm template (`# BL-196-FIXTURE-FENCE-*`, no issues++).
MD
out=$(run_fixture); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "OK:"; then
  pass "T5: glob-suffixed family cite resolves"
else
  fail_ "T5" "expected exit 0 for the glob cite; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T6: a TRUNCATION typo is NOT rescued by the family rule ==="
# ════════════════════════════════════════════════════════════════════
# The family rule appends a HYPHEN before the prefix test, so a token that
# is merely a character-prefix of a live marker still fails. Without that
# hyphen this whole lint would accept any truncation.
setup_fixture
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

The fenced arm is `# BL-196-FIXTURE-FENC` — one character short.
MD
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'BL-196-FIXTURE-FENC'; then
  pass "T6: truncation typo still fails (family rule requires the hyphen)"
else
  fail_ "T6" "expected exit 1 for the truncated cite; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T7: bare prose hyphenation and the NNN placeholder are not cites ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

Cite code by a grep-able `# BL-NNN-…` marker comment, never a file:line.
This is the BL-042-family of entries, and the BL-042-class of defects;
the BL-042-correct reading is the one below. None of those is a citation.
MD
out=$(run_fixture); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "OK:"; then
  pass "T7: bare hyphenation + '# BL-NNN-…' placeholder produce zero hits"
else
  fail_ "T7" "a non-citation shape was flagged; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T8: frozen surfaces (Reports/, docs/handoffs/archive/) out of scope ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
mkdir -p "$TMP/Reports/2026-01-01-run" "$TMP/docs/handoffs/archive"
cat > "$TMP/Reports/2026-01-01-run/LEDGER.md" <<'MD'
# Frozen run artifact

Stamped at its own tree: `# BL-196-FIXTURE-GONE-FROM-MAIN`.
MD
cat > "$TMP/docs/handoffs/archive/2026-01-01-old.md" <<'MD'
# Superseded handoff

Also stamped: `# BL-196-FIXTURE-ALSO-GONE`.
MD
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

The live arm is marked `# BL-196-FIXTURE-LIVE`.
MD
out=$(run_fixture); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "OK:"; then
  pass "T8: frozen dated artifacts are not scanned"
else
  fail_ "T8" "a frozen surface was scanned; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T9a: inline allow WITH a reason suppresses the violation ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

The withdrawn arm was `# BL-196-FIXTURE-GHOST`. <!-- lint-bl-markers: allow lives on an unmerged branch -->
MD
out=$(run_fixture); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "OK:"; then
  pass "T9a: inline allow with a reason suppresses the broken cite"
else
  fail_ "T9a" "expected exit 0 under the inline allow; rc=$rc; output:\n$out"
fi
teardown_fixture

echo ""
echo "=== T9b: inline allow with an EMPTY reason still fails ==="
setup_fixture
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

The withdrawn arm was `# BL-196-FIXTURE-GHOST`. <!-- lint-bl-markers: allow -->
MD
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'EMPTY allowlist reason'; then
  pass "T9b: empty allowlist reason is itself a violation"
else
  fail_ "T9b" "expected exit 1 + empty-reason diagnostic; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T10: --list emits a STATUS table carrying the FAIL row ==="
# ════════════════════════════════════════════════════════════════════
setup_fixture
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

The renamed arm is `# BL-196-FIXTURE-GHOST`.
MD
out=$(bash "$LINTER" --root "$TMP" --list 2>&1); rc=$?
if [ "$rc" -eq 1 ] \
   && echo "$out" | grep -q 'STATUS' \
   && echo "$out" | grep -q 'FAIL.*BL-196-FIXTURE-GHOST.*broken citation' \
   && echo "$out" | grep -q 'INFO.*population'; then
  pass "T10: --list prints the STATUS table, the FAIL row and the population line"
else
  fail_ "T10" "expected --list header + FAIL row + INFO row; rc=$rc; output:\n$out"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T11: unknown flag -> exit 2 + usage ==="
# ════════════════════════════════════════════════════════════════════
out=$(bash "$LINTER" --bogus-flag 2>&1); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -q "Usage:"; then
  pass "T11: unknown flag rejected with exit 2 + usage"
else
  fail_ "T11" "expected exit 2 + usage; rc=$rc; output:\n$out"
fi

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T12: vacuity floor (pass c) -> exit 2, not a silent pass ==="
# ════════════════════════════════════════════════════════════════════
# The fixture is clean, so without the floor this run would exit 0. With a
# floor above the fixture's population it must exit 2 instead — that is the
# whole point: a collapsed scan must never read as a pass.
setup_fixture
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

The live arm is marked `# BL-196-FIXTURE-LIVE`.
MD
out=$(bash "$LINTER" --root "$TMP" 2>&1); rc_clean=$?
out2=$(bash "$LINTER" --root "$TMP" --min-cites 999 2>&1); rc=$?
if [ "$rc_clean" -eq 0 ] && [ "$rc" -eq 2 ] && echo "$out2" | grep -q 'VACUOUS SCAN'; then
  pass "T12: population below the floor exits 2 where the same tree otherwise exits 0"
else
  fail_ "T12" "expected clean rc=0 then floored rc=2 + VACUOUS SCAN; rc_clean=$rc_clean rc=$rc; output:\n$out2"
fi
teardown_fixture

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T13 (MUTATION): excise the BL-196-PROSE-CITE fence -> T2 passes ==="
# ════════════════════════════════════════════════════════════════════
# The decisive check for BL-196's core defect class lives entirely inside
# the fence. Delete the fence and the broken-citation fixture must sail
# through — if it still fails, the check is not (only) where the comment
# says it is, and the mutation proves nothing.
m=$(grep -c 'BL-196-PROSE-CITE' "$LINTER") || m=0
case "$m" in ''|*[!0-9]*) m=0 ;; esac
MUTDIR=$(mktemp -d)
MUTL="$MUTDIR/lint.mut.sh"
sed '/BL-196-PROSE-CITE-BEGIN/,/BL-196-PROSE-CITE-END/d' "$LINTER" > "$MUTL"
l=$(grep -c 'BL-196-PROSE-CITE' "$MUTL") || l=0
case "$l" in ''|*[!0-9]*) l=0 ;; esac
setup_fixture
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

The renamed arm is `# BL-196-FIXTURE-GHOST`, which no longer exists.
MD
if [ "$m" -lt 2 ] || [ "$l" -ne 0 ]; then
  fail_ "T13" "excision vacuous (fence markers before=$m after=$l) — the fence is absent"
else
  out=$(bash "$MUTL" --root "$TMP" 2>&1); rc=$?
  if [ "$rc" -eq 0 ] && ! echo "$out" | grep -q 'BL-196-FIXTURE-GHOST'; then
    pass "T13: fence-excised mutant misses the broken cite — the fence carries the check"
  else
    fail_ "T13" "mutant still caught it (or broke, rc=$rc) — check does not live only in the fence:\n$out"
  fi
fi
teardown_fixture
rm -rf "$MUTDIR"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-REPO: the real tree passes -> exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# The merge gate. If this fails, either a new broken citation landed or a
# marker was renamed without updating the prose that points at it.
out=$(bash "$LINTER" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "T-REPO: every live citation on the real tree resolves"
else
  fail_ "T-REPO" "the real tree has broken marker citations; rc=$rc; output:\n$out"
fi

echo ""
echo "=== T-REPO-LIST: the script-level allowlist mechanism is accounted for ==="
# DO NOT tighten this back to "at least one allowlist row". Rows render only
# on a MISS, so the moment fix/bl112-sast-scan-coverage merges and the BL-186
# markers come back, a row-count assertion reds the required unit lane with
# zero edits to BL-196 — and deleting the allowlist rows does not rescue it
# either.
#
# The predicate is PER-TOKEN, not a global disjunction. Each allowlisted token,
# read out of the lint at runtime, must own EITHER its own reasoned
# `allowlist:` row (today: the markers are still gone) OR its own
# `resolved (EXACT)` row (post-merge: the markers are back and the row is
# merely stale). Every ordering of {merge, delete the rows} is green, and an
# empty allowlist is vacuously satisfied — which is what makes "delete the
# rows" a valid move.
#
# WHY PER-TOKEN AND NOT `rows >= 1 OR all-EXACT`: that disjunction
# SHORT-CIRCUITS. With the real rows rendering, `rows >= 1` was true and no
# token was ever checked individually, so a bogus or stale allowlist entry
# rode along green — the accounting has to be owed by each token or it
# accounts for nothing. T17 pins exactly that.
out=$(bash "$LINTER" --list 2>&1); rc=$?
rows=$(printf '%s\n' "$out" | grep -c 'allowlist: ') || rows=0
case "$rows" in ''|*[!0-9]*) rows=0 ;; esac
tok_total=$(allowlisted_tokens | grep -c .) || tok_total=0
case "$tok_total" in ''|*[!0-9]*) tok_total=0 ;; esac
unaccounted=""
while IFS= read -r t; do
  [ -n "$t" ] || continue
  unaccounted="$unaccounted $t"
done <<EOF
$(unaccounted_allowlist_tokens)
EOF
if [ "$rc" -eq 0 ] && [ -z "$unaccounted" ]; then
  pass "T-REPO-LIST: all $tok_total allowlisted token(s) individually accounted for ($rows row(s) rendered)"
else
  fail_ "T-REPO-LIST" "rc=$rc; rendered rows=$rows; allowlisted token(s) owning neither an allowlist row nor an EXACT row:$unaccounted"
fi

echo ""
echo "=== T17 (RF-3): a BOGUS allowlist token is caught even while real rows render ==="
# The regression this pins is the SHORT-CIRCUIT, so the mutant must be built in
# the regime where the old predicate was satisfied: the real rows ARE
# rendering. A `rows >= 1` test passes here; the per-token test must not.
#
# The mutant lives OUTSIDE the repo and is pointed at the real tree with
# --root, so it never joins the code surface and cannot mint its own bogus
# token. (The literal below is minted in tests/, which is harmless: accounting
# is about --list ROWS, and rows exist only for prose CITATIONS. Nothing cites
# it, so it can own no row by either route — which is the point.)
BOGUS_TOK="BL-196-BOGUS-ALLOWLIST-PROBE"
T17DIR=$(mktemp -d)
T17L="$T17DIR/lint.bogus.sh"
# Splice one bogus row in immediately after the fence opener. Built with sed,
# not `awk -v`: the repo's portability rule is ENVIRON-or-nothing for passing
# shell values into awk, and here neither is needed.
{
  sed -n '1,/BL-196-ALLOWLIST-BEGIN/p' "$LINTER"
  printf '%s|deliberately bogus row, T17 probe\n' "$BOGUS_TOK"
  sed -n '/BL-196-ALLOWLIST-BEGIN/,$p' "$LINTER" | sed '1d'
} > "$T17L"
# The mutant lives outside the repo, so it must be pointed at the real tree
# explicitly — otherwise its REPO_ROOT resolves to the temp dir, it exits 2
# with no backlog, and every token reads "unaccounted" for the wrong reason.
# The mut_rows>=1 arm below is what refuses that false positive.
ctl_unacc=$(unaccounted_allowlist_tokens "$LINTER" "$REPO_ROOT" | grep -c .) || ctl_unacc=0
case "$ctl_unacc" in ''|*[!0-9]*) ctl_unacc=0 ;; esac
mut_unacc=$(unaccounted_allowlist_tokens "$T17L" "$REPO_ROOT") || mut_unacc=""
mut_rows=$(bash "$T17L" --root "$REPO_ROOT" --list 2>&1 | grep -c 'allowlist: ') || mut_rows=0
case "$mut_rows" in ''|*[!0-9]*) mut_rows=0 ;; esac
if [ "$ctl_unacc" -eq 0 ] \
   && [ "$mut_rows" -ge 1 ] \
   && printf '%s\n' "$mut_unacc" | grep -qxF "$BOGUS_TOK"; then
  pass "T17: bogus allowlist token reported unaccounted while $mut_rows real row(s) still render (short-circuit is gone)"
else
  fail_ "T17" "expected control 0 unaccounted, mutant rows>=1 AND the bogus token unaccounted; ctl=$ctl_unacc mut_rows=$mut_rows mut_unaccounted:[$mut_unacc]"
fi
rm -rf "$T17DIR"

echo ""
echo "=== T14 (R-BL196-2): an EMPTY entry-id set exits 2, never a false OK ==="
# The NR==FNR trap. With an empty first file the idiom stays true for every
# record of the SECOND file, so pass (a) swallowed every marker site into the
# entry set and printed `OK: ...` over a completely unchecked tree. Two
# independent fixes are pinned here and by T15: this guard, and the switch to
# FILENAME discrimination.
setup_fixture
printf '# fixture backlog with no entry headers\n\nnothing here\n' \
  > "$TMP/solo-orchestrator-backlog.md"
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

The live arm is marked `# BL-196-FIXTURE-LIVE`.
MD
out=$(run_fixture); rc=$?
if [ "$rc" -eq 2 ] \
   && echo "$out" | grep -q 'EMPTY ENTRY SET' \
   && ! echo "$out" | grep -q '^OK:'; then
  pass "T14: empty entry set exits 2 naming the cause, and prints no OK verdict"
else
  fail_ "T14" "expected exit 2 + EMPTY ENTRY SET and NO OK line; rc=$rc; output:\n$out"
fi
teardown_fixture

echo ""
echo "=== T15 (R-BL196-2): an EMPTY marker set still REPORTS the broken cite ==="
# The same trap on the other join. With zero marker tokens the citation list
# was consumed as if it were the token set, so every broken cite vanished and
# the lint passed. On the real tree the marker floor hides this; under --root,
# where the floors default to 0, it was a live false pass.
setup_fixture
printf '#!/usr/bin/env bash\necho no markers here at all\n' > "$TMP/scripts/thing.sh"
cat > "$TMP/CLAUDE.md" <<'MD'
# Fixture orientation

The renamed arm is `# BL-196-FIXTURE-GHOST`, which no longer exists.
MD
out=$(run_fixture); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'BL-196-FIXTURE-GHOST'; then
  pass "T15: zero-marker code surface still reports the broken citation"
else
  fail_ "T15" "expected exit 1 naming the ghost (the join must not swallow the cites); rc=$rc; output:\n$out"
fi
teardown_fixture

echo ""
echo "=== T16 (R-BL196-6): an arbitrarily-named COPY of the lint cannot mint tokens ==="
# Exact-path self-exclusion is defeated by `cp lint.sh scripts/zz-copy.sh`:
# the copy re-mints every token the lint names — including its own allowlist —
# so allowlisted citations resolve EXACT and the allowlist silently stops
# meaning anything. Layer 3 of the exclusion is a CONTENT sentinel, which
# travels with the bytes and so survives any rename.
#
# The sentinel is assembled at runtime. Written as a literal, this file would
# carry it and exclude ITSELF from the real tree's code surface — an
# unintended coverage hole in the fix's own test.
SENTINEL="BL-196-SELF-EXCLUDE""-SENTINEL"
# A structural marker that lives ONLY inside the lint, so the fixture's own
# files cannot supply it.
COPY_ONLY_TOKEN="BL-196-EMPTY-SET-GUARD"
setup_fixture
cp "$LINTER" "$TMP/scripts/zz-copy.sh"
{
  printf '# Fixture orientation\n\n'
  printf 'Cite: `# %s`\n' "$COPY_ONLY_TOKEN"
} > "$TMP/CLAUDE.md"
out=$(run_fixture); rc_excl=$?

# CONTROL: the same copy with the sentinel lines stripped IS a valid definer.
# Without this arm T16 would also pass if the fixture simply never carried the
# token — the classic vacuous-canary failure.
#
# The control is asserted on the CITATION verdict, not on the exit code. A
# de-sentinelled copy is a full copy of the lint, so its own header mints
# markers for a dozen unrelated entries that the small fixture backlog does
# not carry, and pass (a) reports those — a true finding about the fixture,
# and noise with respect to what this case measures. What must flip is
# exactly one thing: the copy-only token stops being reported as a broken
# citation, because the copy now supplies it.
sed "/${SENTINEL}/d" "$LINTER" > "$TMP/scripts/zz-copy.sh"
out_ctl=$(run_fixture); rc_ctl=$?
cite_broken_re="cites marker '# ${COPY_ONLY_TOKEN}'"

if [ "$rc_excl" -eq 1 ] && echo "$out" | grep -qF "$cite_broken_re" \
   && ! echo "$out_ctl" | grep -qF "$cite_broken_re"; then
  pass "T16: sentinel-bearing copy mints nothing; de-sentinelled control resolves the same token (rc_ctl=$rc_ctl on unrelated pass-(a) noise)"
else
  fail_ "T16" "expected the copy-only token reported broken WITH the sentinel and NOT reported without it; rc_excl=$rc_excl rc_ctl=$rc_ctl; output:\n$out\n--- control ---\n$out_ctl"
fi
teardown_fixture

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
