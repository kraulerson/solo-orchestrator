#!/usr/bin/env bash
# tests/test-bl167-claude-classifier.sh — BL-167 (Dogfood-4 S3, F-DF4-014):
# the BL-072 TDD-ordering classifier counted `.claude/*` framework STATE files
# (phase-state.json, process-state.json, …) as "implementation files with no
# accompanying test". A `fix:`/`refactor:` commit staging real source PLUS
# `.claude/phase-state.json` warned that `.claude/phase-state.json` was an impl
# file lacking a test. Framework state files are never implementation.
#
# THE FIX (# BL-167-CLAUDE-EXCLUDE in scripts/lib/tdd-classify.sh):
# `_bl072_is_impl_file` excludes `.claude/` paths (both `.claude/*` and any
# `*/.claude/*`). The exclusion is scoped to `.claude/` ONLY — real source
# under src/lib/app must still classify as implementation.
#
# Cases:
#   T1-claude-not-listed  fix: staging src/app.ts + .claude/phase-state.json →
#                         the BL-072 WARN impl listing contains `- src/app.ts`
#                         but NOT `.claude/phase-state.json`.
#   T2-src-still-impl     fix: staging ONLY src/app.ts → still listed as impl
#                         (the exclusion did not over-reach onto real source).
#   T3-classifier-direct  source tdd-classify.sh: _bl072_impl_files over a
#                         name-status stream emits src/app.ts (and src/lib/x.ts)
#                         but NOT .claude/phase-state.json; _bl072_is_impl_file
#                         returns impl for src/*, non-impl for .claude/*.
#   T4-mutation           excise # BL-167-CLAUDE-EXCLUDE from a gate copy →
#                         `.claude/phase-state.json` reappears in the WARN
#                         listing (RED); the real classifier omits it (GREEN).
#
# REGISTRATION: no init.sh, not an aggregator → BOTH lists (tests.yml unit
# list + full-project-test-suite.sh). Hermetic (mktemp fixtures, no remote;
# GITHUB_BASE_REF unset; SKIP_LINT=1 as in the BL-072 detector suite — the
# detector runs before lints_check regardless).
# bash-3.2 safe: no associative arrays, no mapfile, no ${var,,}, no ((x++)).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE="$REPO_ROOT/scripts/pre-commit-gate.sh"
TDD_LIB="$REPO_ROOT/scripts/lib/tdd-classify.sh"
PC="$REPO_ROOT/scripts/process-checklist.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] jq not available — the BL-072 detector ledger requires jq."
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TAB=$(printf '\t')

# ── Fixture scaffolding (mirrors the BL-072 detector suite) ──────────────
setup() {
  TMP=$(mktemp -d)
  PROJ="$TMP/proj"
  mkdir -p "$PROJ"
  (
    cd "$PROJ"
    unset GITHUB_BASE_REF
    git init -q -b main
    git config user.email "t@example.invalid"
    git config user.name "bl167-test"
    git remote add origin "https://example.invalid/x.git"
    mkdir -p src
    echo "seed" > README.md
    git add README.md
    git commit -q -m "chore: seed"
  )
}
teardown() { rm -rf "$TMP"; }

stage() {
  local path="$1" content="${2:-x}"
  mkdir -p "$PROJ/$(dirname "$path")"
  printf '%s\n' "$content" > "$PROJ/$path"
  ( cd "$PROJ" && git add "$path" )
}

# Pipe a JSON tool_input.command into the gate; echo "rc|<single-line output>".
run_hook_gate() {
  local gate="$1" cmd="$2" input out rc=0
  input=$(jq -n --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}')
  out=$( cd "$PROJ" && unset GITHUB_BASE_REF; export SKIP_LINT=1; \
         printf '%s' "$input" | bash "$gate" 2>&1 ) || rc=$?
  echo "$rc|$(printf '%s' "$out" | tr '\n' ' ')"
}
run_hook() { run_hook_gate "$GATE" "$1"; }

# Build a mutation tree so a single classifier excision is the ONLY difference.
build_mut_tree() {
  local mut="$1"
  mkdir -p "$mut/scripts/lib"
  cp "$GATE" "$mut/scripts/pre-commit-gate.sh"
  cp "$TDD_LIB" "$mut/scripts/lib/tdd-classify.sh"
  cp "$PC" "$mut/scripts/process-checklist.sh" 2>/dev/null || true
  cp "$REPO_ROOT"/scripts/lib/*.sh "$mut/scripts/lib/" 2>/dev/null || true
  chmod +x "$mut/scripts/pre-commit-gate.sh"
}

has_warn()  { case "$1" in *'[WARN] BL-072 TDD ordering'*) return 0 ;; *) return 1 ;; esac; }
# Is <path> present as a `- <path>` line in the WARN impl listing?
listed()    { case "$2" in *"- $1"*) return 0 ;; *) return 1 ;; esac; }

# ── T1: .claude/phase-state.json must NOT be listed as an impl file ───────────
echo "=== T1-claude-not-listed ==="
setup
stage "src/app.ts" "export const app = () => 1"
stage ".claude/phase-state.json" '{"current_phase":2}'
res=$(run_hook 'git commit -m "fix: patch app and bump phase state"')
body="${res#*|}"
ok=1
has_warn "$body" || ok=0                          # the WARN must fire (src/app.ts is impl, no test)
listed "src/app.ts" "$body" || ok=0               # real source IS listed
listed ".claude/phase-state.json" "$body" && ok=0 # framework state is NOT listed
if [ "$ok" -eq 1 ]; then
  pass "T1-claude-not-listed: src/app.ts listed, .claude/phase-state.json excluded from the impl listing"
else
  fail_ "T1-claude-not-listed" "body: $body"
fi
teardown

# ── T2: real source alone still classifies as impl (no over-reach) ───────────
echo "=== T2-src-still-impl ==="
setup
stage "src/app.ts" "export const app = () => 2"
res=$(run_hook 'git commit -m "fix: patch app"')
body="${res#*|}"
if has_warn "$body" && listed "src/app.ts" "$body"; then
  pass "T2-src-still-impl: a lone src/*.ts still warns + is listed (the .claude exclusion did not over-reach)"
else
  fail_ "T2-src-still-impl" "expected WARN listing src/app.ts; body: $body"
fi
teardown

# ── T3: direct classifier assertions (deterministic, sourced) ────────────────
echo "=== T3-classifier-direct ==="
# shellcheck source=/dev/null
. "$TDD_LIB"
name_status="A${TAB}src/app.ts
A${TAB}src/lib/util.ts
A${TAB}.claude/phase-state.json
M${TAB}.claude/process-state.json"
impl_out=$(printf '%s\n' "$name_status" | _bl072_impl_files)
ok=1
case "
$impl_out" in *"
src/app.ts"*) : ;; *) ok=0 ;; esac
case "
$impl_out" in *"
src/lib/util.ts"*) : ;; *) ok=0 ;; esac
case "$impl_out" in *'.claude/'*) ok=0 ;; esac
_bl072_is_impl_file "src/app.ts"            || ok=0   # 0 = impl
_bl072_is_impl_file "src/lib/util.ts"       || ok=0   # 0 = impl
_bl072_is_impl_file ".claude/phase-state.json"   && ok=0   # 1 = NOT impl (expected)
_bl072_is_impl_file "pkg/.claude/state.json"     && ok=0   # nested .claude also excluded
if [ "$ok" -eq 1 ]; then
  pass "T3-classifier-direct: _bl072_impl_files emits src/* only; .claude/* classifies non-impl (both top-level and nested)"
else
  fail_ "T3-classifier-direct" "impl_out=[$(printf '%s' "$impl_out" | tr '\n' ',')]"
fi

# ── T4: mutation — excise the exclusion → .claude reappears in the listing ───
echo "=== T4-mutation-exclusion-load-bearing ==="
setup
stage "src/app.ts" "export const app = () => 4"
stage ".claude/phase-state.json" '{"current_phase":2}'
MUT="$TMP/mut"
build_mut_tree "$MUT"
grep -v 'BL-167-CLAUDE-EXCLUDE' "$MUT/scripts/lib/tdd-classify.sh" > "$MUT/scripts/lib/tdd-classify.sh.tmp"
mv "$MUT/scripts/lib/tdd-classify.sh.tmp" "$MUT/scripts/lib/tdd-classify.sh"
if ! grep -q 'BL-167-CLAUDE-EXCLUDE' "$TDD_LIB"; then
  fail_ "T4-mutation-exclusion-load-bearing" "BL-167-CLAUDE-EXCLUDE marker missing from the REAL classifier — nothing to mutate"
elif grep -q 'BL-167-CLAUDE-EXCLUDE' "$MUT/scripts/lib/tdd-classify.sh"; then
  fail_ "T4-mutation-exclusion-load-bearing" "marker still present after excision — mutation did not apply"
elif ! bash -n "$MUT/scripts/lib/tdd-classify.sh" 2>/dev/null; then
  fail_ "T4-mutation-exclusion-load-bearing" "mutant tdd-classify.sh not syntactically valid after excision"
else
  # RED: without the exclusion, .claude/phase-state.json is listed as impl.
  mres=$(run_hook_gate "$MUT/scripts/pre-commit-gate.sh" 'git commit -m "fix: patch app and bump phase state"')
  mbody="${mres#*|}"
  if has_warn "$mbody" && listed ".claude/phase-state.json" "$mbody"; then
    pass "T4-mutation (RED): excising BL-167-CLAUDE-EXCLUDE relists .claude/phase-state.json as impl"
  else
    fail_ "T4-mutation (RED)" "mutant did NOT relist .claude state — exclusion not load-bearing; mbody: $mbody"
  fi
  # GREEN: the real classifier omits it on the same fixture.
  rres=$(run_hook 'git commit -m "fix: patch app and bump phase state"')
  rbody="${rres#*|}"
  if has_warn "$rbody" && ! listed ".claude/phase-state.json" "$rbody"; then
    pass "T4-mutation (GREEN): the real classifier keeps .claude/phase-state.json out of the impl listing (contrast holds)"
  else
    fail_ "T4-mutation (GREEN)" "real classifier listed .claude state — contrast broken; rbody: $rbody"
  fi
fi
teardown

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
