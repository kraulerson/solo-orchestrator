#!/usr/bin/env bash
# tests/test-lint-backlog-references.sh
#
# Tests for scripts/lint-backlog-references.sh — the cycle-7 Slot-5
# CI backstop that catches drift between commits and the backlog
# entries they close. Sibling to PR #72's counter-antipattern lint.
#
# Each test stages an isolated mock-repo with a tiny backlog.md and
# a tiny git history, then runs the linter from inside that repo via
# a copied script. T9 is the merge gate: it runs the linter against
# the REAL repo at HEAD with `--base origin/main` and requires exit 0.
#
# Style mirrors tests/test-lint-counter-antipattern.sh (PR #72): set
# -uo pipefail, mktemp fixtures, pass/fail counters, teardown after
# each case.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINTER="$REPO_ROOT/scripts/lint-backlog-references.sh"

if [ ! -f "$LINTER" ]; then
  echo "FATAL: linter not found at $LINTER" >&2
  exit 2
fi

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# setup() builds a per-test mock repo at $PROJ with:
#   • a copy of the linter at scripts/lint-backlog-references.sh
#   • an empty git repo (so `git log BASE..HEAD` works)
#   • an empty backlog file the test then writes
# The mock's BASE ref is the initial empty-tree commit at branch
# `base`; HEAD progresses on `main` so BASE..HEAD captures the
# test-added commits.
setup() {
  TMP=$(mktemp -d)
  PROJ="$TMP/repo"
  mkdir -p "$PROJ/scripts"
  cp "$LINTER" "$PROJ/scripts/lint-backlog-references.sh"
  chmod +x "$PROJ/scripts/lint-backlog-references.sh"

  (
    cd "$PROJ"
    git init -q -b main
    git config user.email "test@example.com"
    git config user.name "Test"
    : > solo-orchestrator-backlog.md
    git add solo-orchestrator-backlog.md
    git commit -q -m "chore: seed"
    git branch base
  )
}
teardown() { rm -rf "$TMP"; }

# Run the fixture-local linter against the local `base` ref.
run_lint() {
  ( cd "$PROJ" && bash scripts/lint-backlog-references.sh --base base 2>&1 )
  return $?
}

# Append a commit with a free-form message; no file change needed —
# use --allow-empty.
commit_msg() {
  ( cd "$PROJ" && git commit --allow-empty -q -m "$1" )
}

# Replace the backlog file in $PROJ with the heredoc body, then
# commit it. The lint walks the file as-of HEAD.
write_backlog() {
  local body="$1"
  printf '%s' "$body" > "$PROJ/solo-orchestrator-backlog.md"
  ( cd "$PROJ" && git add solo-orchestrator-backlog.md \
                && git commit -q -m "chore: update backlog" )
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: clean backlog + commit referencing real BL → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
write_backlog '## BL-001: real entry

**Status:** Resolved (2026-01-01, PR #1)

Body.
'
commit_msg "fix: do something (BL-001)"
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T1: real BL reference resolves cleanly"
else
  fail_ "T1" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: commit references BL-999 (unknown) → exit 1 ==="
# ════════════════════════════════════════════════════════════════════
setup
write_backlog '## BL-001: real entry

**Status:** Resolved (2026-01-01, PR #1)

Body.
'
commit_msg "fix: typo'd reference (BL-999)"
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q "unknown BL reference 'BL-999'"; then
  pass "T2: unknown BL-999 reference is rejected"
else
  fail_ "T2" "expected exit 1 + unknown-ref diagnostic; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: entry marked Closed without PR# or SHA → exit 1 ==="
# ════════════════════════════════════════════════════════════════════
setup
write_backlog '## BL-005: missing citation

**Status:** Closed

Body without any PR cite or commit SHA.
'
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q "BL-005 marked Closed/Resolved but no PR#"; then
  pass "T3: Closed entry without citation is flagged"
else
  fail_ "T3" "expected exit 1 + uncited-closure diagnostic; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T4: entry marked Closed WITH PR #42 citation → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
write_backlog '## BL-006: cited via PR number

**Status:** Closed — shipped 2026-01-02 (PR #42)

Body.
'
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T4: PR# citation in Status line is accepted"
else
  fail_ "T4" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T5: entry marked Closed WITH backticked SHA citation → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
write_backlog '## BL-020: cited via commit SHA

**Status:** Closed
**Closed:** 2026-01-03 — commit `b9c4c4c` ("fix: ...").

Body.
'
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T5: backticked-SHA citation is accepted"
else
  fail_ "T5" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T6: entry marked Open (no citation required) → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
write_backlog '## BL-007: still open

**Status:** Open

Body without any citation — that is fine because the entry is open.
'
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T6: Open entry passes without citation"
else
  fail_ "T6" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T7: allowlist marker WITH reason suppresses citation check → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
setup
write_backlog '## BL-099: legacy pre-convention close

**Status:** Closed <!-- lint-backlog-references: allow closed before citation convention existed -->

Body has no PR# or SHA, but the allowlist marker carries justification.
'
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T7: allowlist with reason suppresses uncited-closure"
else
  fail_ "T7" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T8: case-insensitive match — 'bl-031' in commit subject ==="
# ════════════════════════════════════════════════════════════════════
setup
write_backlog '## BL-031: real entry

**Status:** Resolved (2026-01-01, PR #1)

Body.
'
commit_msg "fix(init): host-agnostic flow (bl-031)"
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T8: lower-case bl-031 resolves to BL-031"
else
  fail_ "T8" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# Bonus: branch-scoped commit-message allowlist. A later commit's
# `lint-backlog-references-ignore:` footer retroactively exempts an
# earlier commit's prose mention of a placeholder token. Scope is
# branch-wide (mirrors how this PR itself uses the footer to suppress
# its own BL-099 fixture mention).
echo ""
echo "=== T8b: branch-scoped ignore footer suppresses prose mention → exit 0 ==="
setup
write_backlog '## BL-007: real entry

**Status:** Resolved (2026-01-01, PR #1)

Body.
'
commit_msg "docs: describe sample diagnostic (mentions BL-099 in prose)"
commit_msg "$(printf 'chore: clean up\n\nlint-backlog-references-ignore: BL-099')"
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T8b: branch-scoped ignore footer exempts BL-099 across BASE..HEAD"
else
  fail_ "T8b" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# Bonus: also verify that empty allowlist reason FAILS (mirrors PR #72
# allowlist semantics — reason is REQUIRED to keep reviewers honest).
echo ""
echo "=== T7b: allowlist marker WITHOUT reason → exit 1 (justification required) ==="
setup
write_backlog '## BL-088: legacy entry with empty allow

**Status:** Closed <!-- lint-backlog-references: allow -->

Body.
'
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q "empty allowlist reason"; then
  pass "T7b: empty-reason allowlist marker fails"
else
  fail_ "T7b" "expected exit 1 + empty-reason diagnostic; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T10: --pre-commit-mode with VALID BL via --message → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# Slot-5 / cycle-8 contract: pre-commit-gate.sh invokes the lint at
# commit time, supplying the prospective commit message. No git log
# walk happens; the lint scans the message tokens against the backlog
# header set.
setup
write_backlog '## BL-031: real entry
**Status:** Resolved (2026-01-01, PR #1)
Body.
'
out=$( cd "$PROJ" && bash scripts/lint-backlog-references.sh --pre-commit-mode \
        --message "feat(init): host-agnostic flow (BL-031)" 2>&1 ); rc=$?
if [ $rc -eq 0 ]; then
  pass "T10: --pre-commit-mode --message with valid BL passes"
else
  fail_ "T10" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T11: --pre-commit-mode with UNKNOWN BL-999 via --message → exit 1 ==="
# ════════════════════════════════════════════════════════════════════
setup
write_backlog '## BL-031: real entry
**Status:** Resolved (2026-01-01, PR #1)
Body.
'
out=$( cd "$PROJ" && bash scripts/lint-backlog-references.sh --pre-commit-mode \
        --message "fix: typo (BL-999)" 2>&1 ); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q "unknown BL reference 'BL-999' in prospective commit message"; then
  pass "T11: --pre-commit-mode --message with unknown BL is rejected"
else
  fail_ "T11" "expected exit 1 + prospective-message diagnostic; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T12: --pre-commit-mode reads message from stdin → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# Mirrors the --terminal-mode invocation path: pre-commit-gate.sh pipes
# .git/COMMIT_EDITMSG into the lint over stdin.
setup
write_backlog '## BL-042: real entry
**Status:** Resolved (2026-01-01, PR #1)
Body.
'
out=$( cd "$PROJ" && printf 'fix: thing (BL-042)\n' \
        | bash scripts/lint-backlog-references.sh --pre-commit-mode 2>&1 ); rc=$?
if [ $rc -eq 0 ]; then
  pass "T12: --pre-commit-mode reads stdin and accepts valid BL"
else
  fail_ "T12" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T13: --pre-commit-mode still flags uncited Closed entries in backlog → exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# Step 3 (backlog block scan) MUST keep running in pre-commit mode —
# it's structural on the file, independent of git history. Otherwise
# the operator-side enforcement would have a blind spot vs CI.
setup
write_backlog '## BL-005: missing citation
**Status:** Closed
Body without any PR cite or commit SHA.
'
out=$( cd "$PROJ" && bash scripts/lint-backlog-references.sh --pre-commit-mode \
        --message "chore: unrelated change" 2>&1 ); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q "BL-005 marked Closed/Resolved but no PR#"; then
  pass "T13: --pre-commit-mode still runs Step 3 backlog block scan"
else
  fail_ "T13" "expected exit 1 + uncited-closure diagnostic; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
# BL-207 — entry-header UNIQUENESS (Step 4, `# BL-207-HEADER-UNIQUENESS`)
#
# T14..T19 pin the arm that fails when the same `BL-NNN` owns more than
# one `^## BL-NNN:` header. T14 is the reviewer's own mutant verbatim
# (a duplicate `## BL-187:` header appended to the backlog, which passed
# the lint with rc=0 before this arm existed). T15 is the negative
# control. T16 pins the deliberate NO-exemption decision for preserved
# `Original entry (pre-close` blocks. T17 pins the `[a-z]?` sub-ID
# grammar (a narrowing to `^## BL-[0-9]+:` goes blind to `BL-003a`, and
# a suffix-stripping extraction would conflate BL-003/003a/003b). T18
# pins mode parity with Step 3. T19 pins the --list row.
# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T14: duplicate '## BL-187:' entry header → exit 1 naming BOTH line numbers ==="
setup
write_backlog '## BL-186: first entry

**Status:** Open

Body.

## BL-187: original entry

**Status:** Open

Body.

## BL-188: another entry

**Status:** Open

Body.

## BL-187: duplicate header appended in the reviewer mutation lab

**Status:** Open

Body.
'
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] \
   && echo "$out" | grep -q "duplicate entry header 'BL-187'" \
   && echo "$out" | grep -q "lines 7, 19"; then
  pass "T14: duplicate BL-187 header is rejected, both line numbers named"
else
  fail_ "T14" "expected exit 1 + duplicate-header diagnostic naming lines 7, 19; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T15: unique headers + prose mentions + indented lookalike → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# Negative control for T14, and it pins HEADERS-ONLY scope: repeated
# prose mentions of an ID are normal (cross-references), and an indented
# sample header inside an entry body is not an entry header — only the
# anchored `^## BL-NNN:` form counts.
setup
write_backlog '## BL-001: first entry

**Status:** Open

Cross-references BL-001, BL-001 and BL-002 in prose. A sample header,
indented so it is body text rather than a real entry header:

    ## BL-001: sample header quoted inside the entry body

## BL-002: second entry

**Status:** Open

Body.
'
out=$(run_lint); rc=$?
if [ $rc -eq 0 ]; then
  pass "T15: unique headers pass; prose mentions and indented lookalikes are not headers"
else
  fail_ "T15" "expected exit 0; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T16: duplicate header INSIDE a preserved 'Original entry (pre-close' block → exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# Deliberate decision (see `# BL-207-HEADER-UNIQUENESS` in the lint):
# preserved audit-trail blocks get NO exemption. Step 3's block splitter
# already treats any `^## BL-NNN:` line as an entry header, so an
# un-indented header inside a preserved block really does truncate the
# enclosing block and open a second one for the same ID. Exempting it
# here would make the uniqueness arm disagree with the splitter it is
# meant to protect. The fix is to indent/fence the quoted header, which
# T15 shows already passes.
setup
write_backlog '## BL-050: closed entry with a preserved original block

**Status:** Closed — shipped 2026-01-02 (PR #42)

Original entry (pre-close, kept for audit trail):

## BL-050: closed entry with a preserved original block

**Status:** Open

Body.
'
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] \
   && echo "$out" | grep -q "duplicate entry header 'BL-050'" \
   && echo "$out" | grep -q "lines 1, 7"; then
  pass "T16: preserved audit-trail blocks get no exemption from the uniqueness arm"
else
  fail_ "T16" "expected exit 1 + duplicate-header diagnostic naming lines 1, 7; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T17: sub-ID grammar — duplicate '## BL-003a:' flagged, BL-003/003a/003b not conflated ==="
# ════════════════════════════════════════════════════════════════════
setup
write_backlog '## BL-003: parent entry

**Status:** Open

Body.

## BL-003a: gitlab split

**Status:** Open

Body.

## BL-003b: bitbucket split

**Status:** Open

Body.

## BL-003a: duplicated split

**Status:** Open

Body.
'
out=$(run_lint); rc=$?
if [ $rc -eq 1 ] \
   && echo "$out" | grep -q "duplicate entry header 'BL-003a'" \
   && echo "$out" | grep -q "lines 7, 19" \
   && ! echo "$out" | grep -q "duplicate entry header 'BL-003'"; then
  pass "T17: BL-003a duplicate flagged; BL-003 / BL-003a / BL-003b stay distinct IDs"
else
  fail_ "T17" "expected exit 1, duplicate 'BL-003a' at lines 7, 19, and no 'BL-003' duplicate; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T18: --pre-commit-mode also runs the uniqueness arm → exit 1 ==="
# ════════════════════════════════════════════════════════════════════
# Mode parity with T13: Step 4 is structural on the backlog file, so an
# operator committing a duplicate header is blocked at commit time, not
# only in CI.
setup
write_backlog '## BL-042: first

**Status:** Open

Body.

## BL-042: second

**Status:** Open

Body.
'
out=$( cd "$PROJ" && bash scripts/lint-backlog-references.sh --pre-commit-mode \
        --message "chore: unrelated change" 2>&1 ); rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -q "duplicate entry header 'BL-042'"; then
  pass "T18: --pre-commit-mode runs the header-uniqueness arm"
else
  fail_ "T18" "expected exit 1 + duplicate-header diagnostic; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T19: --list renders the header-uniqueness verdict for review ==="
# ════════════════════════════════════════════════════════════════════
# House pattern: a decisive judgement must be renderable, not merely
# silent-on-pass. The PASS row carries the header count so a reviewer
# can see the arm actually looked at something.
setup
write_backlog '## BL-001: first

**Status:** Open

Body.

## BL-002: second

**Status:** Open

Body.
'
out=$( cd "$PROJ" && bash scripts/lint-backlog-references.sh --base base --list 2>&1 ); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q "header-uniqueness" \
   && echo "$out" | grep -q "2 BL header(s), all unique"; then
  pass "T19: --list shows the header-uniqueness PASS row with the header count"
else
  fail_ "T19" "expected exit 0 + header-uniqueness list row with count 2; rc=$rc; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T20: TWO duplicated IDs are reported in FIRST-HEADER order ==="
# ════════════════════════════════════════════════════════════════════
# Pins the `order[]` index against a `for (k in seen)` regression: awk's
# in-iteration order is UNSPECIFIED, so a for-in implementation emits
# duplicates in hash order and diagnostics reshuffle between runs/hosts.
# Every earlier case has at most ONE duplicated ID, where any ordering
# looks identical — the reviewer's for-in mutant survived 21/0 for
# exactly that reason.
#
# ID choice is empirical, not arbitrary. Under this host's awk
# (BSD awk, bash 3.2.57) `for (k in seen)` yields BL-050 BEFORE BL-005,
# i.e. the reverse of first-header order, so the mutant is visible. The
# pair the review suggested (BL-001/BL-100 with BL-001 first) hashes in
# the same order as first-header order and would NOT have exposed it —
# verified with a probe before choosing.
#
# The ASSERTION is implementation-independent: first-header order is the
# specified contract and `order[]` satisfies it on any awk. Only the
# MUTANT's visibility depends on the host's hash order, which is the
# normal limit of mutation testing against unspecified behaviour.
#
# The fixture also separates "first-header order" from "order of the
# SECOND occurrence": BL-050's duplicate (line 13) precedes BL-005's
# duplicate (line 19), so an implementation keyed on the later header
# would also emit BL-050 first and fail here.
setup
write_backlog '## BL-005: first entry, duplicated last

**Status:** Open

Body.

## BL-050: second entry, duplicated first

**Status:** Open

Body.

## BL-050: duplicate of the SECOND id

**Status:** Open

Body.

## BL-005: duplicate of the FIRST id

**Status:** Open

Body.
'
out=$(run_lint); rc=$?
dup_order=$(printf '%s\n' "$out" \
  | grep -o "duplicate entry header '[^']*'" \
  | sed "s/.*'\([^']*\)'/\1/" \
  | tr '\n' ' ')
if [ $rc -eq 1 ] \
   && [ "$dup_order" = "BL-005 BL-050 " ] \
   && echo "$out" | grep -q "'BL-005': 2 headers at lines 1, 19" \
   && echo "$out" | grep -q "'BL-050': 2 headers at lines 7, 13"; then
  pass "T20: both duplicated IDs reported, ordered by first header (BL-005 then BL-050)"
else
  fail_ "T20" "expected exit 1 and dup order 'BL-005 BL-050 '; got rc=$rc order='$dup_order'; output:\n$out"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T9: MERGE GATE — run linter against current repo HEAD vs origin/main → exit 0 ==="
# ════════════════════════════════════════════════════════════════════
# Wave-2 acceptance criterion (mirrors PR #72 T9): proves the lint
# rules align with the current real backlog + commit history. If this
# fails locally, EITHER the lint is too strict (revise here) OR the
# backlog has uncited closures (backfill citations or allowlist them
# IN THIS PR before merging).
out=$(bash "$LINTER" --base origin/main 2>&1); rc=$?
if [ $rc -eq 0 ]; then
  pass "T9: current repo HEAD passes the backlog-references lint"
else
  fail_ "T9" "current repo HEAD fails the lint; rc=$rc; output:\n$out"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
