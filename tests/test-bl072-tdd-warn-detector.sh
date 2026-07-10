#!/usr/bin/env bash
# tests/test-bl072-tdd-warn-detector.sh
#
# BL-072 Phase C1 regression: scripts/pre-commit-gate.sh must WARN — never
# block — when a feat/fix/refactor commit ships implementation files with no
# matching test in the same commit AND no test earlier on the branch. The
# detector:
#   • fires only on feat/fix/refactor Conventional-Commit subjects,
#   • reuses the BL-006 derivative-commit filters (amend/merge/revert/
#     cherry-pick pass through untouched),
#   • prints a [WARN] would-block explanation and appends a JSON row to
#     .claude/tdd-warn-ledger.jsonl,
#   • ALWAYS leaves the exit code at 0 (WARN-only measurement mode — the
#     hard block is Phase C2 and is deliberately NOT implemented yet).
#
# Cases:
#   T-feat-no-tests-warns    feat + impl, no test        → [WARN], rc=0, ledger+1
#   T-feat-with-tests-silent feat + impl + test          → silent, ledger unchanged
#   T-refactor-no-tests-warns refactor + impl, no test   → [WARN], rc=0
#   T-docs-only-silent       docs: touching only docs/   → silent
#   T-branch-diff-tests-count test earlier on the branch → silent (allowance)
#   T-derivative-commits-pass amend / merge-in-progress / cherry-pick chain → silent
#   T-ledger-row-shape       jq-validate {date,subject,files[],would_block:true}
#   T-mutation               excise # BL-072-TDD-DETECT → T-feat-no-tests goes
#                            RED (WARN gone); un-mutated → GREEN (WARN present)
#
# Hermetic: mktemp fixture repos (git init + local identity + a fake origin
# pointer only — no real remote is ever contacted); GITHUB_BASE_REF unset so
# CI's own env cannot leak into fixture git ops; SKIP_LINT=1 so the unrelated
# operator-side lints (which resolve REPO_ROOT to the framework tree) don't
# run — the detector executes BEFORE lints_check, so this does not affect it.
# scripts/lint-no-live-remote-in-tests.sh passes: no init.sh execution here.
#
# bash-3.2 safe: no associative arrays, no mapfile, no ${var,,}, no ((x++)).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE="$REPO_ROOT/scripts/pre-commit-gate.sh"
TDD_LIB="$REPO_ROOT/scripts/lib/tdd-classify.sh"
PC="$REPO_ROOT/scripts/process-checklist.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] jq not available — the BL-072 detector ledger requires jq."
  exit 0
fi

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# ── Fixture scaffolding ──────────────────────────────────────────────
# A minimal git repo on `main` with a fake origin pointer. No phase-state
# file → process-checklist enforcement is inert (phase defaults to 0), so
# the ONLY observable behavior under test is the TDD WARN detector.
setup() {
  TMP=$(mktemp -d)
  PROJ="$TMP/proj"
  mkdir -p "$PROJ"
  (
    cd "$PROJ"
    unset GITHUB_BASE_REF
    git init -q -b main
    git config user.email "t@example.invalid"
    git config user.name "tdd-test"
    git remote add origin "https://example.invalid/x.git"
    mkdir -p src
    echo "seed" > README.md
    git add README.md
    git commit -q -m "chore: seed"
  )
}
teardown() { rm -rf "$TMP"; }

# Stage a file (creating parent dirs) without committing.
stage() {
  local path="$1" content="${2:-x}"
  mkdir -p "$PROJ/$(dirname "$path")"
  printf '%s\n' "$content" > "$PROJ/$path"
  ( cd "$PROJ" && git add "$path" )
}

# Number of rows currently in the ledger (0 if absent).
ledger_rows() {
  local f="$PROJ/.claude/tdd-warn-ledger.jsonl"
  if [ -f "$f" ]; then
    wc -l < "$f" | tr -d ' '
  else
    echo 0
  fi
}

# Pipe a JSON tool_input.command into the gate (PreToolUse path).
# Echoes "rc|<single-line stdout+stderr>". SKIP_LINT=1 keeps the unrelated
# lints out of the way; the detector runs before them regardless.
run_hook() {
  local cmd="$1" input out rc=0
  input=$(jq -n --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}')
  out=$( cd "$PROJ" && unset GITHUB_BASE_REF; export SKIP_LINT=1; \
         printf '%s' "$input" | bash "$GATE" 2>&1 ) || rc=$?
  echo "$rc|$(printf '%s' "$out" | tr '\n' ' ')"
}

has_warn() { case "$1" in *'[WARN] BL-072 TDD ordering'*) return 0 ;; *) return 1 ;; esac; }

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-feat-no-tests-warns: feat + impl, no test → [WARN], rc=0, ledger+1 ==="
# ════════════════════════════════════════════════════════════════════
setup
before=$(ledger_rows)
stage "src/foo.py" "def foo(): pass"
res=$(run_hook 'git commit -m "feat: add foo"')
rc="${res%%|*}"; body="${res#*|}"
after=$(ledger_rows)
if has_warn "$body"; then
  pass "T-feat-no-tests-warns: [WARN] emitted"
else
  fail_ "T-feat-no-tests-warns" "expected a [WARN]; got: $res"
fi
if [ "$rc" -eq 0 ]; then
  pass "T-feat-no-tests-warns: rc=0 (WARN never blocks)"
else
  fail_ "T-feat-no-tests-warns" "expected rc=0; got rc=$rc"
fi
if [ "$after" -eq $((before + 1)) ]; then
  pass "T-feat-no-tests-warns: exactly one ledger row appended ($before → $after)"
else
  fail_ "T-feat-no-tests-warns" "ledger rows $before → $after (expected +1)"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-feat-with-tests-silent: feat + impl + test → silent, ledger unchanged ==="
# ════════════════════════════════════════════════════════════════════
setup
before=$(ledger_rows)
stage "src/bar.py" "def bar(): pass"
stage "tests/bar_test.py" "def test_bar(): pass"
res=$(run_hook 'git commit -m "feat: add bar with test"')
rc="${res%%|*}"; body="${res#*|}"
after=$(ledger_rows)
if ! has_warn "$body" && [ "$rc" -eq 0 ] && [ "$after" -eq "$before" ]; then
  pass "T-feat-with-tests-silent: no WARN, rc=0, ledger unchanged (test rides along)"
else
  fail_ "T-feat-with-tests-silent" "expected silent+unchanged; rc=$rc ledger $before→$after; body: $body"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-refactor-no-tests-warns: refactor + impl, no test → [WARN], rc=0 ==="
# ════════════════════════════════════════════════════════════════════
setup
stage "src/baz.py" "def baz(): return 1"
res=$(run_hook 'git commit -m "refactor: rework baz"')
rc="${res%%|*}"; body="${res#*|}"
if has_warn "$body" && [ "$rc" -eq 0 ]; then
  pass "T-refactor-no-tests-warns: refactor prefix triggers the WARN (rc=0)"
else
  fail_ "T-refactor-no-tests-warns" "expected WARN + rc=0; got: $res"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-docs-only-silent: docs: touching only docs/ → silent ==="
# ════════════════════════════════════════════════════════════════════
setup
before=$(ledger_rows)
stage "docs/notes.md" "# notes"
res=$(run_hook 'git commit -m "docs: update notes"')
rc="${res%%|*}"; body="${res#*|}"
after=$(ledger_rows)
if ! has_warn "$body" && [ "$after" -eq "$before" ]; then
  pass "T-docs-only-silent: docs-only commit is silent, ledger unchanged"
else
  fail_ "T-docs-only-silent" "expected silent; rc=$rc ledger $before→$after; body: $body"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-branch-diff-tests-count: test earlier on the branch satisfies → silent ==="
# ════════════════════════════════════════════════════════════════════
# A test committed earlier on this feature branch (present in
# `git diff main...HEAD`) satisfies TDD ordering even though THIS commit
# adds only implementation. Proves the branch allowance.
setup
(
  cd "$PROJ"
  unset GITHUB_BASE_REF
  git checkout -q -b feature
  mkdir -p tests
  echo "def test_new(): pass" > tests/new_test.py
  git add tests/new_test.py
  git commit -q -m "test: new_test first (TDD)"
)
before=$(ledger_rows)
stage "src/new.py" "def new(): pass"
res=$(run_hook 'git commit -m "feat: implement new (test landed earlier)"')
rc="${res%%|*}"; body="${res#*|}"
after=$(ledger_rows)
if ! has_warn "$body" && [ "$after" -eq "$before" ]; then
  pass "T-branch-diff-tests-count: earlier-branch test satisfies the gate (silent)"
else
  fail_ "T-branch-diff-tests-count" "expected silent (branch allowance); rc=$rc ledger $before→$after; body: $body"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-derivative-commits-pass: amend / merge-in-progress / cherry-pick chain → silent ==="
# ════════════════════════════════════════════════════════════════════
# amend: the gate's --amend block short-circuits before the detector.
setup
stage "src/amend.py" "def a(): pass"
res=$(run_hook 'git commit --amend -m "feat: reword amend"')
body="${res#*|}"
if ! has_warn "$body"; then
  pass "T-derivative-commits-pass: --amend passes through (no WARN)"
else
  fail_ "T-derivative-commits-pass(amend)" "amend produced a WARN; got: $res"
fi
teardown

# merge in progress: MERGE_HEAD present → detector filter passes it through.
setup
stage "src/merge.py" "def m(): pass"
( cd "$PROJ" && printf '%s\n' "$(git rev-parse HEAD)" > .git/MERGE_HEAD )
res=$(run_hook 'git commit -m "feat: finish the merge"')
body="${res#*|}"
if ! has_warn "$body"; then
  pass "T-derivative-commits-pass: merge-in-progress (MERGE_HEAD) passes through (no WARN)"
else
  fail_ "T-derivative-commits-pass(merge)" "merge-in-progress produced a WARN; got: $res"
fi
teardown

# cherry-pick chain: command mentions cherry-pick → detector word filter.
setup
stage "src/pick.py" "def p(): pass"
res=$(run_hook 'git cherry-pick deadbeef && git commit -m "feat: pick"')
body="${res#*|}"
if ! has_warn "$body"; then
  pass "T-derivative-commits-pass: cherry-pick chain passes through (no WARN)"
else
  fail_ "T-derivative-commits-pass(cherry-pick)" "cherry-pick chain produced a WARN; got: $res"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-ledger-row-shape: {date,subject,files[],would_block:true} jq-valid ==="
# ════════════════════════════════════════════════════════════════════
setup
stage "src/shape.py" "def s(): pass"
run_hook 'git commit -m "feat: shape check"' >/dev/null
LED="$PROJ/.claude/tdd-warn-ledger.jsonl"
if [ -f "$LED" ]; then
  row=$(tail -n 1 "$LED")
  ok=1
  echo "$row" | jq -e 'has("date") and has("subject") and has("files") and has("would_block")' >/dev/null 2>&1 || ok=0
  echo "$row" | jq -e '.would_block == true' >/dev/null 2>&1 || ok=0
  echo "$row" | jq -e '.files | type == "array"' >/dev/null 2>&1 || ok=0
  echo "$row" | jq -e '.subject == "feat: shape check"' >/dev/null 2>&1 || ok=0
  echo "$row" | jq -e '.files | index("src/shape.py") != null' >/dev/null 2>&1 || ok=0
  echo "$row" | jq -e '.date | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")' >/dev/null 2>&1 || ok=0
  if [ "$ok" -eq 1 ]; then
    pass "T-ledger-row-shape: row has date/subject/files[]/would_block=true with correct values"
  else
    fail_ "T-ledger-row-shape" "row failed schema/value validation: $row"
  fi
else
  fail_ "T-ledger-row-shape" "ledger file was not created"
fi
teardown

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T-mutation: excise # BL-072-TDD-DETECT → WARN disappears (RED→GREEN proof) ==="
# ════════════════════════════════════════════════════════════════════
# Copy the gate + its deps into a mutation tree, excise every line carrying
# the BL-072-TDD-DETECT marker (the load-bearing emit_tdd_warn call), and
# re-run the T-feat-no-tests fixture. With the trigger removed the detector
# must go quiet — proving the marked line is what makes the detector fire.
setup
stage "src/mut.py" "def mut(): pass"

MUT="$TMP/mut"
mkdir -p "$MUT/scripts/lib"
cp "$GATE" "$MUT/scripts/pre-commit-gate.sh"
cp "$TDD_LIB" "$MUT/scripts/lib/tdd-classify.sh"
# Copy process-checklist + the helpers chain so the ONLY difference between
# the real and mutated gate is the excised marker (bl006_check delegates to
# process-checklist.sh; without it the mutated run would diverge on an
# unrelated missing-file error).
cp "$PC" "$MUT/scripts/process-checklist.sh" 2>/dev/null || true
cp "$REPO_ROOT"/scripts/lib/*.sh "$MUT/scripts/lib/" 2>/dev/null || true
grep -v 'BL-072-TDD-DETECT' "$MUT/scripts/pre-commit-gate.sh" > "$MUT/scripts/pre-commit-gate.sh.tmp"
mv "$MUT/scripts/pre-commit-gate.sh.tmp" "$MUT/scripts/pre-commit-gate.sh"
chmod +x "$MUT/scripts/pre-commit-gate.sh"

MUT_INPUT=$(jq -n --arg c 'git commit -m "feat: add mut"' '{tool_name:"Bash", tool_input:{command:$c}}')

if ! grep -q 'BL-072-TDD-DETECT' "$GATE"; then
  fail_ "T-mutation" "BL-072-TDD-DETECT marker missing from the REAL gate — nothing to mutate"
elif grep -q 'BL-072-TDD-DETECT' "$MUT/scripts/pre-commit-gate.sh"; then
  fail_ "T-mutation" "marker still present after excision — mutation did not apply"
else
  # RED: mutated gate must NOT warn.
  mut_out=$( cd "$PROJ" && unset GITHUB_BASE_REF; export SKIP_LINT=1; \
             printf '%s' "$MUT_INPUT" | bash "$MUT/scripts/pre-commit-gate.sh" 2>&1 ) || true
  mut_out_1=$(printf '%s' "$mut_out" | tr '\n' ' ')
  if has_warn "$mut_out_1"; then
    fail_ "T-mutation" "mutated gate STILL warned — marker is not load-bearing; out: $mut_out_1"
  else
    pass "T-mutation (RED): excising BL-072-TDD-DETECT removes the WARN"
  fi
  # GREEN: the real gate DOES warn on the same fixture.
  real_out=$( cd "$PROJ" && unset GITHUB_BASE_REF; export SKIP_LINT=1; \
              printf '%s' "$MUT_INPUT" | bash "$GATE" 2>&1 ) || true
  real_out_1=$(printf '%s' "$real_out" | tr '\n' ' ')
  if has_warn "$real_out_1"; then
    pass "T-mutation (GREEN): the un-mutated gate warns on the same fixture (contrast holds)"
  else
    fail_ "T-mutation" "the real gate did NOT warn on the mutation fixture — contrast broken; out: $real_out_1"
  fi
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
