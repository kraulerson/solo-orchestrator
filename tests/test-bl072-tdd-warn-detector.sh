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
# Phase C2 (tier-keyed HARD BLOCK on the --terminal-mode git-hook surface):
#   T-hard-block-{feat,fix,refactor}  sponsored_poc + impl no test → rc=1 [FAIL]
#   T-exempt-docs                     docs: prefix → allowed
#   T-attested-escape                 SOLO_TDD_ATTESTED=1 → rc=0 + attestation
#                                     row in process-state.json + ledger attested:true
#   T-tier-personal-warns             personal → rc=0 [WARN] + ledger bypassed:true
#   T-spoof-track-light               sponsored_poc + track=light → STILL rc=1 (load-bearing)
#   T-no-phase-state-warns            no phase-state.json → rc=0 WARN (mothership safety)
#   T-md-excluded                     feat touching only *.md → silent
#   T-deletion-excluded               feat that only deletes a source file → silent
#   T-tier-promotion-flips            personal WARN → promoted state → identical commit rc=1
#   T-mutation-detector               excise # BL-072-TDD-DETECT → hard block RED; restore GREEN
#   T-mutation-tier-key               revert tier predicate to trust track →
#                                     T-spoof-track-light RED; restore GREEN
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
  fail_ "T-feat-with-tests-silent" "expected silent+unchanged; rc=$rc ledger $before->$after; body: $body"
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
  fail_ "T-docs-only-silent" "expected silent; rc=$rc ledger $before->$after; body: $body"
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
  fail_ "T-branch-diff-tests-count" "expected silent (branch allowance); rc=$rc ledger $before->$after; body: $body"
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

# ════════════════════════════════════════════════════════════════════
# ════════════════════════════════════════════════════════════════════
# BL-072 Phase C2 — tier-keyed TDD HARD BLOCK (terminal-mode enforcement)
# ════════════════════════════════════════════════════════════════════
# The C2 hard block lives on the git-hook / --terminal-mode surface (a non-zero
# exit aborts the commit). The tests below drive `pre-commit-gate.sh
# --terminal-mode --tdd-only` with hermetic fixtures that carry a
# .claude/phase-state.json tier + a .git/COMMIT_EDITMSG subject. All C1 cases
# above continue to exercise the PreToolUse WARN surface unchanged.
# ════════════════════════════════════════════════════════════════════

has_fail() { case "$1" in *'[FAIL] BL-072 TDD ordering'*) return 0 ;; *) return 1 ;; esac; }

# Write a phase-state.json tier into the fixture. poc_mode "null" => JSON null.
# args: deployment  poc_mode(null|private_poc|sponsored_poc)  [track=standard]
write_tier() {
  local dep="$1" poc="$2" track="${3:-standard}" poc_json='null'
  mkdir -p "$PROJ/.claude"
  [ "$poc" != "null" ] && poc_json="\"$poc\""
  cat > "$PROJ/.claude/phase-state.json" <<EOF
{"current_phase":2,"deployment":"$dep","poc_mode":$poc_json,"track":"$track"}
EOF
}

# Set the prospective commit subject (terminal-mode reads .git/COMMIT_EDITMSG).
set_subject() { printf '%s\n' "$1" > "$PROJ/.git/COMMIT_EDITMSG"; }

# Run the gate in --terminal-mode --tdd-only from the fixture. Any args are
# passed as env KEY=VAL to the invocation. Echoes "rc|<single-line out>".
run_term() {
  local out rc=0
  out=$( cd "$PROJ" && unset GITHUB_BASE_REF; env "$@" bash "$GATE" --terminal-mode --tdd-only 2>&1 ) || rc=$?
  printf '%s|%s' "$rc" "$(printf '%s' "$out" | tr '\n' ' ')"
}

# Copy the gate + its deps into a mutation tree so a mutation is the ONLY
# difference from the real gate.
build_mut_tree() {
  local mut="$1"
  mkdir -p "$mut/scripts/lib"
  cp "$GATE" "$mut/scripts/pre-commit-gate.sh"
  cp "$TDD_LIB" "$mut/scripts/lib/tdd-classify.sh"
  cp "$PC" "$mut/scripts/process-checklist.sh" 2>/dev/null || true
  cp "$REPO_ROOT"/scripts/lib/*.sh "$mut/scripts/lib/" 2>/dev/null || true
  chmod +x "$mut/scripts/pre-commit-gate.sh"
}

# Run an arbitrary gate path in --terminal-mode --tdd-only. Echoes "rc|out".
run_term_gate() {
  local gate="$1"; shift
  local out rc=0
  out=$( cd "$PROJ" && unset GITHUB_BASE_REF; env "$@" bash "$gate" --terminal-mode --tdd-only 2>&1 ) || rc=$?
  printf '%s|%s' "$rc" "$(printf '%s' "$out" | tr '\n' ' ')"
}

# ── T-hard-block-{feat,fix,refactor}: sponsored_poc → rc=1 + [FAIL] ──
for _pfx in feat fix refactor; do
  echo ""
  echo "=== T-hard-block-$_pfx: sponsored_poc + impl no test → rc=1 + [FAIL] ==="
  setup
  write_tier organizational sponsored_poc standard
  stage "src/$_pfx.py" "def x(): pass"
  set_subject "$_pfx: ship $_pfx without test"
  res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
  if [ "$rc" -eq 1 ] && has_fail "$body"; then
    pass "T-hard-block-$_pfx: rc=1 + [FAIL] (non-bypassable tier hard block)"
  else
    fail_ "T-hard-block-$_pfx" "expected rc=1 + [FAIL]; got rc=$rc body: $body"
  fi
  teardown
done

# ── T-exempt-docs: docs: prefix on a sponsored fixture → allowed ──
echo ""
echo "=== T-exempt-docs: docs: prefix (sponsored) → allowed, rc=0, no [FAIL] ==="
setup
write_tier organizational sponsored_poc standard
stage "docs/notes.md" "# notes"
set_subject "docs: update notes"
res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
if [ "$rc" -eq 0 ] && ! has_fail "$body"; then
  pass "T-exempt-docs: docs: prefix is out of scope even on a non-bypassable tier"
else
  fail_ "T-exempt-docs" "expected rc=0 + no [FAIL]; got rc=$rc body: $body"
fi
teardown

# ── T-attested-escape: SOLO_TDD_ATTESTED=1 → rc=0 + attestation + ledger ──
echo ""
echo "=== T-attested-escape: sponsored + SOLO_TDD_ATTESTED=1 → rc=0 + recorded ==="
setup
write_tier organizational sponsored_poc standard
stage "src/foo.py" "def foo(): pass"
set_subject "feat: add foo"
res=$(run_term SOLO_TDD_ATTESTED=1 SOLO_TDD_REASON="integration surface"); rc="${res%%|*}"; body="${res#*|}"
PS="$PROJ/.claude/process-state.json"
LED="$PROJ/.claude/tdd-warn-ledger.jsonl"
ok=1
[ "$rc" -eq 0 ] || ok=0
[ -f "$PS" ] && jq -e '.tdd_attestations | length == 1' "$PS" >/dev/null 2>&1 || ok=0
jq -e '.tdd_attestations[0].subject == "feat: add foo"' "$PS" >/dev/null 2>&1 || ok=0
jq -e '.tdd_attestations[0].reason == "integration surface"' "$PS" >/dev/null 2>&1 || ok=0
jq -e '.tdd_attestations[0].files | index("src/foo.py") != null' "$PS" >/dev/null 2>&1 || ok=0
[ -f "$LED" ] && tail -n 1 "$LED" | jq -e '.attested == true' >/dev/null 2>&1 || ok=0
if [ "$ok" -eq 1 ]; then
  pass "T-attested-escape: rc=0, attestation recorded to process-state.json, ledger attested:true"
else
  fail_ "T-attested-escape" "rc=$rc; PS=$(cat "$PS" 2>/dev/null); LED_tail=$(tail -n1 "$LED" 2>/dev/null); body: $body"
fi
teardown

# ── T-tier-personal-warns: personal → rc=0 + [WARN] + ledger bypassed ──
echo ""
echo "=== T-tier-personal-warns: personal + impl no test → rc=0 + [WARN] + bypassed row ==="
setup
write_tier personal null light
stage "src/foo.py" "def foo(): pass"
set_subject "feat: add foo (personal)"
res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
LED="$PROJ/.claude/tdd-warn-ledger.jsonl"
ok=1
[ "$rc" -eq 0 ] || ok=0
has_warn "$body" || ok=0
has_fail "$body" && ok=0
[ -f "$LED" ] && tail -n 1 "$LED" | jq -e '.bypassed == true' >/dev/null 2>&1 || ok=0
if [ "$ok" -eq 1 ]; then
  pass "T-tier-personal-warns: bypassable tier warns (rc=0) and logs bypassed:true"
else
  fail_ "T-tier-personal-warns" "rc=$rc LED_tail=$(tail -n1 "$LED" 2>/dev/null); body: $body"
fi
teardown

# ── T-spoof-track-light: sponsored_poc + track=light → STILL rc=1 (load-bearing) ──
echo ""
echo "=== T-spoof-track-light: sponsored_poc + track=light → STILL rc=1 + [FAIL] ==="
setup
write_tier organizational sponsored_poc light
stage "src/foo.py" "def foo(): pass"
set_subject "feat: sponsored project spoofing track=light"
res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
if [ "$rc" -eq 1 ] && has_fail "$body"; then
  pass "T-spoof-track-light: track=light does NOT unlock a bypass on a sponsored tier [load-bearing]"
else
  fail_ "T-spoof-track-light" "expected rc=1 + [FAIL] (tier keyed on deployment/poc_mode, not track); got rc=$rc body: $body"
fi
teardown

# ── T-no-phase-state-warns: no phase-state.json → rc=0, WARN only (mothership) ──
echo ""
echo "=== T-no-phase-state-warns: no phase-state.json → rc=0, WARN only (mothership safety) ==="
setup
# deliberately DO NOT write a phase-state.json.
stage "src/foo.py" "def foo(): pass"
set_subject "feat: add foo (unscaffolded repo)"
res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
if [ "$rc" -eq 0 ] && has_warn "$body" && ! has_fail "$body"; then
  pass "T-no-phase-state-warns: an unscaffolded repo is BYPASSABLE (WARN, never hard-block)"
else
  fail_ "T-no-phase-state-warns" "expected rc=0 + [WARN] + no [FAIL]; got rc=$rc body: $body"
fi
teardown

# ── T-md-excluded: feat touching only README.md → silent (no trigger) ──
echo ""
echo "=== T-md-excluded: feat + only README.md (sponsored) → silent, no trigger ==="
setup
write_tier organizational sponsored_poc standard
stage "README.md" "# changed docs"
set_subject "feat: doc-shaped feat touching only markdown"
res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
if [ "$rc" -eq 0 ] && ! has_fail "$body" && ! has_warn "$body"; then
  pass "T-md-excluded: markdown-only change is not implementation (silent even on a sponsored tier)"
else
  fail_ "T-md-excluded" "expected silent rc=0; got rc=$rc body: $body"
fi
teardown

# ── T-deletion-excluded: feat that only DELETES a source file → silent ──
echo ""
echo "=== T-deletion-excluded: feat that only deletes a source file (sponsored) → silent ==="
setup
write_tier organizational sponsored_poc standard
# Put a source file into HEAD, then stage its deletion.
( cd "$PROJ"
  mkdir -p src
  echo "def legacy(): pass" > src/legacy.py
  git add src/legacy.py
  git commit -q -m "chore: seed legacy source"
  git rm -q src/legacy.py
)
set_subject "feat: remove the legacy module"
res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
if [ "$rc" -eq 0 ] && ! has_fail "$body" && ! has_warn "$body"; then
  pass "T-deletion-excluded: a pure deletion ships no implementation (silent even on a sponsored tier)"
else
  fail_ "T-deletion-excluded" "expected silent rc=0; got rc=$rc body: $body"
fi
teardown

# ── T-tier-promotion-flips: personal WARN → promote to sponsored → rc=1 ──
echo ""
echo "=== T-tier-promotion-flips: personal WARNs → promoted state → identical commit rc=1 ==="
setup
write_tier personal private_poc light
stage "src/foo.py" "def foo(): pass"
set_subject "feat: add foo"
res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
before_ok=1
[ "$rc" -eq 0 ] || before_ok=0
has_warn "$body" || before_ok=0
# Promote exactly the way upgrade-project.sh --to-sponsored-poc writes it:
# deployment=organizational + poc_mode=sponsored_poc into phase-state.json.
write_tier organizational sponsored_poc light
res2=$(run_term); rc2="${res2%%|*}"; body2="${res2#*|}"
after_ok=1
[ "$rc2" -eq 1 ] || after_ok=0
has_fail "$body2" || after_ok=0
if [ "$before_ok" -eq 1 ] && [ "$after_ok" -eq 1 ]; then
  pass "T-tier-promotion-flips: enforcement flips WARN→BLOCK on tier promotion (same staged commit)"
else
  fail_ "T-tier-promotion-flips" "before rc=$rc (want 0+WARN); after rc=$rc2 (want 1+FAIL); body2: $body2"
fi
teardown

# ── T-mutation-detector: excise # BL-072-TDD-DETECT → T-hard-block-feat RED ──
echo ""
echo "=== T-mutation-detector: excise BL-072-TDD-DETECT → hard block disappears (RED→GREEN) ==="
setup
write_tier organizational sponsored_poc standard
stage "src/mut.py" "def mut(): pass"
set_subject "feat: mutation detector fixture"
MUT="$TMP/mut-detect"
build_mut_tree "$MUT"
grep -v 'BL-072-TDD-DETECT' "$MUT/scripts/pre-commit-gate.sh" > "$MUT/scripts/pre-commit-gate.sh.tmp"
mv "$MUT/scripts/pre-commit-gate.sh.tmp" "$MUT/scripts/pre-commit-gate.sh"
chmod +x "$MUT/scripts/pre-commit-gate.sh"
if ! grep -q 'BL-072-TDD-DETECT' "$GATE"; then
  fail_ "T-mutation-detector" "marker missing from the REAL gate — nothing to mutate"
elif grep -q 'BL-072-TDD-DETECT' "$MUT/scripts/pre-commit-gate.sh"; then
  fail_ "T-mutation-detector" "marker still present after excision — mutation did not apply"
else
  res=$(run_term_gate "$MUT/scripts/pre-commit-gate.sh"); rc="${res%%|*}"; body="${res#*|}"
  if [ "$rc" -eq 0 ] && ! has_fail "$body"; then
    pass "T-mutation-detector (RED): excising BL-072-TDD-DETECT removes the hard block (rc=0)"
  else
    fail_ "T-mutation-detector" "mutated gate STILL blocked — marker not load-bearing; rc=$rc body: $body"
  fi
  res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
  if [ "$rc" -eq 1 ] && has_fail "$body"; then
    pass "T-mutation-detector (GREEN): the un-mutated gate hard-blocks the same fixture (rc=1)"
  else
    fail_ "T-mutation-detector" "real gate did NOT block — contrast broken; rc=$rc body: $body"
  fi
fi
teardown

# ── T-mutation-tier-key: revert tier predicate to trust track → T-spoof RED ──
echo ""
echo "=== T-mutation-tier-key: revert tier predicate to trust track → spoof RED (RED→GREEN) ==="
# Rewrites _bl072_tier_bypassable to return BYPASSABLE iff track=light (the
# spoofable predicate BL-084 forbids). A sponsored project carrying track=light
# must then wrongly pass — proving the deployment/poc_mode keying is load-bearing.
mutate_trust_track() {
  awk '
    /^_bl072_tier_bypassable\(\) \{/ {
      print "_bl072_tier_bypassable() {"
      print "  local ps=\".claude/phase-state.json\" track=\"\""
      print "  [ -f \"$ps\" ] && command -v jq >/dev/null 2>&1 && track=$(jq -r \".track\" \"$ps\" 2>/dev/null)"
      print "  [ \"$track\" = \"light\" ] && return 0"
      print "  return 1"
      print "}"
      inbody=1; next
    }
    inbody==1 && /^}/ { inbody=0; next }
    inbody==1 { next }
    { print }
  ' "$1" > "$2"
}
setup
write_tier organizational sponsored_poc light
stage "src/foo.py" "def foo(): pass"
set_subject "feat: sponsored spoofing track=light"
MUT="$TMP/mut-tier"
build_mut_tree "$MUT"
mutate_trust_track "$GATE" "$MUT/scripts/pre-commit-gate.sh"
chmod +x "$MUT/scripts/pre-commit-gate.sh"
if ! grep -q 'BL-084-TIER-KEY' "$GATE"; then
  fail_ "T-mutation-tier-key" "BL-084-TIER-KEY marker missing from the REAL gate"
elif ! grep -q 'MUTATED\|track = "light"\|track" = "light"\|"light"' "$MUT/scripts/pre-commit-gate.sh"; then
  # Sanity: the mutated predicate must reference track (the spoof).
  fail_ "T-mutation-tier-key" "mutation did not rewrite the tier predicate to trust track"
else
  res=$(run_term_gate "$MUT/scripts/pre-commit-gate.sh"); rc="${res%%|*}"; body="${res#*|}"
  if [ "$rc" -eq 0 ] && ! has_fail "$body"; then
    pass "T-mutation-tier-key (RED): trusting track lets the sponsored+track=light spoof pass (rc=0)"
  else
    fail_ "T-mutation-tier-key" "mutated gate STILL blocked — tier-key not load-bearing; rc=$rc body: $body"
  fi
  res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
  if [ "$rc" -eq 1 ] && has_fail "$body"; then
    pass "T-mutation-tier-key (GREEN): the real (deployment/poc_mode-keyed) gate blocks the spoof (rc=1)"
  else
    fail_ "T-mutation-tier-key" "real gate did NOT block the spoof — contrast broken; rc=$rc body: $body"
  fi
fi
teardown

# ── T-attested-record-failure: attested escape but the durable write FAILS ──
echo ""
echo "=== T-attested-record-failure: SOLO_TDD_ATTESTED=1 + unwritable .claude → REFUSE rc=1, no partial write ==="
# C2 close-out gap: the attested-escape FAILURE path (pre-commit-gate.sh:254-255)
# was untested — the WP-C2 verifier found that mutating its loud-refuse
# `return 1` to `return 0` SURVIVED. tdd_record_attestation returns non-zero on
# any durable-write failure; the caller MUST then be LOUD and REFUSE the commit
# (an attested escape must be on the record, never a silent pass). We force the
# write to fail by removing write permission on .claude, restore it on EVERY
# exit path via a trap, and assert rc=1 + a loud [FAIL] + NO partial write
# (process-state.json absent). Then a gate COPY with the refuse flipped to
# `return 0` must go RED (rc=0).
setup
write_tier organizational sponsored_poc standard
stage "src/foo.py" "def foo(): pass"
set_subject "feat: add foo"
PS="$PROJ/.claude/process-state.json"
# Safety net + primary restore: the trap fires even if an assertion path exits.
trap 'chmod u+rwx "$PROJ/.claude" 2>/dev/null || true' EXIT
chmod 500 "$PROJ/.claude"
# Root/odd-FS guard: chmod 500 does not stop writes for root. Probe writability;
# if still writable the failure path is not exercisable here — record it and skip
# rather than emit a spurious RED.
if ( : > "$PROJ/.claude/.wprobe" ) 2>/dev/null; then
  rm -f "$PROJ/.claude/.wprobe" 2>/dev/null || true
  chmod u+rwx "$PROJ/.claude" 2>/dev/null || true
  pass "T-attested-record-failure: SKIPPED (running as root / .claude still writable) — durable-write-fail path not exercisable in this environment"
else
  res=$(run_term SOLO_TDD_ATTESTED=1 SOLO_TDD_REASON="integration surface"); rc="${res%%|*}"; body="${res#*|}"
  # (1) REFUSED with rc=1.
  if [ "$rc" -eq 1 ]; then
    pass "T-attested-record-failure: gate REFUSES the commit (rc=1) when the attestation cannot be durably recorded"
  else
    fail_ "T-attested-record-failure" "expected rc=1 (refuse); got rc=$rc body: $body"
  fi
  # (2) The refusal is loud AND is specifically the record-failure [FAIL].
  if has_fail "$body" && case "$body" in *'attestation could NOT be recorded'*) true ;; *) false ;; esac; then
    pass "T-attested-record-failure: loud [FAIL] naming the durable-record failure (not a silent pass)"
  else
    fail_ "T-attested-record-failure" "expected the record-failure [FAIL]; body: $body"
  fi
  # (3) No partial write — process-state.json must be ABSENT (the write never landed).
  if [ ! -f "$PS" ]; then
    pass "T-attested-record-failure: no partial write — process-state.json absent"
  else
    fail_ "T-attested-record-failure" "process-state.json was written despite the refusal: $(cat "$PS" 2>/dev/null)"
  fi
  # (4) MUTATION: flip the loud-refuse `return 1` → `return 0` in a gate COPY.
  # With .claude still unwritable, the mutant emits the [FAIL] but ALLOWS the
  # commit (rc=0) — the exact silent-escape defect. Real rc=1 vs mutant rc=0.
  MUT="$TMP/mut-attest-refuse"
  build_mut_tree "$MUT"
  awk '
    /attested escape must be durably logged/ { seen=1 }
    seen==1 && /^[[:space:]]*return 1[[:space:]]*$/ { sub(/return 1/, "return 0"); seen=0 }
    { print }
  ' "$GATE" > "$MUT/scripts/pre-commit-gate.sh"
  chmod +x "$MUT/scripts/pre-commit-gate.sh"
  if diff -q "$GATE" "$MUT/scripts/pre-commit-gate.sh" >/dev/null 2>&1; then
    fail_ "T-attested-record-failure-mut" "mutation did not apply — the refuse `return 1` was not flipped"
  elif ! bash -n "$MUT/scripts/pre-commit-gate.sh" 2>/dev/null; then
    fail_ "T-attested-record-failure-mut" "mutant gate not syntactically valid after the flip"
  else
    res=$(run_term_gate "$MUT/scripts/pre-commit-gate.sh" SOLO_TDD_ATTESTED=1 SOLO_TDD_REASON="x"); rc="${res%%|*}"; body="${res#*|}"
    if [ "$rc" -eq 0 ]; then
      pass "T-attested-record-failure-mut (RED): flipping the refuse to return 0 lets the un-recorded escape PASS (rc=0)"
    else
      fail_ "T-attested-record-failure-mut" "mutant STILL refused (rc=$rc) — the refuse is not load-bearing (mutation not proof); body: $body"
    fi
    res=$(run_term SOLO_TDD_ATTESTED=1 SOLO_TDD_REASON="x"); rc="${res%%|*}"; body="${res#*|}"
    if [ "$rc" -eq 1 ]; then
      pass "T-attested-record-failure-mut (GREEN): the real gate still refuses the same fixture (rc=1) — contrast holds"
    else
      fail_ "T-attested-record-failure-mut" "real gate did NOT refuse — contrast broken; rc=$rc body: $body"
    fi
  fi
  chmod u+rwx "$PROJ/.claude" 2>/dev/null || true
fi
trap - EXIT
teardown

# ── T-lockfile-excluded: sponsored feat touching only lockfiles → silent ──
echo ""
echo "=== T-lockfile-excluded: sponsored feat touching only package-lock.json + *.lock → silent, rc=0, no ledger ==="
# C2 close-out gap: the lockfile exclusion (tdd-classify.sh:85-89) was untested.
# Lockfiles are machine-generated, not authored implementation, so a commit that
# touches ONLY lockfiles must not trigger the gate — even on a non-bypassable
# tier. Mutation: strip the lockfile arms from a COPY of tdd-classify.sh →
# lockfiles reclassify as impl → the same fixture hard-blocks (RED).
setup
write_tier organizational sponsored_poc standard
stage "package-lock.json" '{"lockfileVersion":3}'
stage "Cargo.lock" "[[package]]"
set_subject "feat: bump dependencies (lockfiles only)"
before=$(ledger_rows)
res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
after=$(ledger_rows)
if [ "$rc" -eq 0 ] && ! has_fail "$body" && ! has_warn "$body" && [ "$after" -eq "$before" ]; then
  pass "T-lockfile-excluded: lockfile-only change is not implementation (silent, rc=0, no ledger row even on a sponsored tier)"
else
  fail_ "T-lockfile-excluded" "expected silent rc=0 + ledger unchanged; got rc=$rc ledger $before->$after body: $body"
fi
teardown

# ── T-lockfile-excluded-mut: strip the lockfile arms → the fixture hard-blocks ──
echo ""
echo "=== T-lockfile-excluded-mut: remove the lockfile arms from tdd-classify.sh → hard block (RED→GREEN) ==="
setup
write_tier organizational sponsored_poc standard
stage "package-lock.json" '{"lockfileVersion":3}'
stage "Cargo.lock" "[[package]]"
set_subject "feat: bump dependencies (lockfiles only)"
MUT="$TMP/mut-lock"
build_mut_tree "$MUT"
grep -vE '(package-lock\.json|yarn\.lock|\*\.lock)\)[[:space:]]+return 1' "$TDD_LIB" > "$MUT/scripts/lib/tdd-classify.sh"
if ! grep -qE '\*\.lock\)[[:space:]]+return 1' "$TDD_LIB"; then
  fail_ "T-lockfile-excluded-mut" "the lockfile arms are missing from the REAL tdd-classify.sh — nothing to mutate"
elif grep -qE '(package-lock\.json|yarn\.lock|\*\.lock)\)[[:space:]]+return 1' "$MUT/scripts/lib/tdd-classify.sh"; then
  fail_ "T-lockfile-excluded-mut" "lockfile arms still present after excision — mutation did not apply"
elif ! bash -n "$MUT/scripts/lib/tdd-classify.sh" 2>/dev/null; then
  fail_ "T-lockfile-excluded-mut" "mutant tdd-classify.sh not syntactically valid after excision"
else
  res=$(run_term_gate "$MUT/scripts/pre-commit-gate.sh"); rc="${res%%|*}"; body="${res#*|}"
  if [ "$rc" -eq 1 ] && has_fail "$body"; then
    pass "T-lockfile-excluded-mut (RED): removing the lockfile arms reclassifies lockfiles as impl → hard block (rc=1)"
  else
    fail_ "T-lockfile-excluded-mut" "mutant did NOT block — the lockfile arm is not load-bearing (mutation not proof); rc=$rc body: $body"
  fi
  res=$(run_term); rc="${res%%|*}"; body="${res#*|}"
  if [ "$rc" -eq 0 ] && ! has_fail "$body"; then
    pass "T-lockfile-excluded-mut (GREEN): the real (lockfile-excluding) classifier stays silent on the same fixture (rc=0)"
  else
    fail_ "T-lockfile-excluded-mut" "real gate did NOT stay silent — contrast broken; rc=$rc body: $body"
  fi
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
