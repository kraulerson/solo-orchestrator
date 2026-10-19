#!/usr/bin/env bash
# tests/test-bl354-state-jsonl-exempt.sh — BL-354.
#
# A commit that stages only framework state files (.claude/*.json plus the
# Development Guardrails' .claude/approvals.jsonl) was classified as source
# work by two checks, because both exempt `.json` and neither `.jsonl`:
#   - check_commit_ready's docs-only exemption in scripts/process-checklist.sh
#     (# BL-354-DOCS-JSONL), so the Phase 2 init block and, for a feat subject,
#     the Build Loop block fired on a state-only commit (J1-J3);
#   - _ACCUM_EXEMPT_RE in scripts/lib/accumulation.sh (# BL-233-WPB-EXEMPT-SET),
#     so the phase gate's memory-accumulation check counted it as source (A1).
# Guards that must not move: a .jsonl beside a real source file still blocks
# (J4), and accumulation keeps its .claude/ scope (A3).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
unset GITHUB_BASE_REF

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bl354.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# _ready ROOT VERIFIED SUBJECT FILE... — stage FILEs in a fresh Phase 2 project
# and run ROOT's check_commit_ready; sets RC and OUT.
_ready() {
  local root="$1" verified="$2" subject="$3" p=""
  shift 3
  p="$(mktemp -d "$WORK/pXXXXXX")"
  (
    cd "$p" || exit 1
    git init -q && git config user.email t@t.local && git config user.name t
    mkdir -p .claude src
    echo '{"current_phase":2,"track":"standard","deployment":"personal","phases":{}}' > .claude/phase-state.json
    printf '{"phase2_init":{"verified":%s,"steps_completed":[]},"build_loop":{"feature":null,"step":0,"steps_completed":[],"started_at":null},"uat_session":{"started_at":null,"steps_completed":[]}}\n' "$verified" > .claude/process-state.json
    for f in "$@"; do mkdir -p "$(dirname "$f")"; [ -f "$f" ] || echo '{"x":1}' > "$f"; git add "$f"; done
  )
  if [ -n "$subject" ]; then
    OUT="$(cd "$p" && "$root/scripts/process-checklist.sh" --check-commit-ready --subject "$subject" 2>&1)"; RC=$?
  else
    OUT="$(cd "$p" && "$root/scripts/process-checklist.sh" --check-commit-ready 2>&1)"; RC=$?
  fi
}

# _accum ROOT PATHS — 0 iff ROOT's accum_paths_have_source calls PATHS source.
_accum() { ( . "$1/scripts/lib/accumulation.sh" && accum_paths_have_source "$2" ); }

case_J1() {   # init unverified: the state-only commit lands
  _ready "$1" false "" .claude/process-state.json .claude/approvals.jsonl
  [ "$RC" -eq 0 ] || { DETAIL="rc=$RC $(echo "$OUT" | grep -E 'FAIL' | head -1)"; return 1; }
}
case_J2() {   # a feat subject over state files only needs no Build Loop, as with .json alone
  _ready "$1" true "feat: x" .claude/process-state.json .claude/approvals.jsonl
  [ "$RC" -eq 0 ] || { DETAIL="rc=$RC $(echo "$OUT" | grep -E 'FAIL' | head -1)"; return 1; }
}
case_J3() {   # the other framework ledgers, init unverified
  _ready "$1" false "" .claude/tdd-warn-ledger.jsonl .claude/mcp-attestations.jsonl
  [ "$RC" -eq 0 ] || { DETAIL="rc=$RC $(echo "$OUT" | grep -E 'FAIL' | head -1)"; return 1; }
}
case_J4() {   # a .jsonl beside a source file still blocks
  _ready "$1" false "" .claude/approvals.jsonl src/a.ts
  [ "$RC" -ne 0 ] && echo "$OUT" | grep -qF "Phase 2 initialization not verified" \
    || { DETAIL="rc=$RC $(echo "$OUT" | head -1)"; return 1; }
}
case_A1() {   # accumulation: the approvals ledger is not source
  if _accum "$1" ".claude/approvals.jsonl"; then DETAIL="called source"; return 1; fi
}
case_A2() {   # accumulation: beside a source file the window still has source
  _accum "$1" ".claude/approvals.jsonl
src/a.py" || { DETAIL="not called source"; return 1; }
}
case_A3() {   # accumulation keeps its .claude/ scope: a project's own .jsonl is source
  _accum "$1" "data/events.jsonl" || { DETAIL="not called source"; return 1; }
}

check() {
  local name="$1" fn="$2"
  DETAIL=""
  if "$fn" "$REPO_ROOT"; then pass "$name"; else fail_ "$name" "$DETAIL"; fi
}

echo "=== J — check_commit_ready ==="
check "J1 init unverified: .claude/*.json + approvals.jsonl lands" case_J1
check "J2 feat subject over state files only: no Build Loop needed" case_J2
check "J3 tdd-warn-ledger.jsonl + mcp-attestations.jsonl land" case_J3
check "J4 a .jsonl beside src/a.ts still blocks on init" case_J4
echo "=== A — accumulation ==="
check "A1 .claude/approvals.jsonl is not source work" case_A1
check "A2 .claude/approvals.jsonl + src/a.py is source work" case_A2
check "A3 data/events.jsonl outside .claude/ is source work" case_A3

# --- mutation proofs: each edit lands in a mirror of scripts/, and its killer fails.
# mutate FILE OLD NEW — replace the one line containing OLD (fixed string) by NEW.
mutate() {
  local f="$1" old="$2" new="$3" n=""
  n="$(grep -cF -- "$old" "$f")"
  [ "$n" = "1" ] || { echo "'$old' is on $n lines of $f (need 1)"; return 1; }
  OLD="$old" NEW="$new" awk 'index($0, ENVIRON["OLD"]) { print ENVIRON["NEW"]; next } { print }' "$f" > "$f.mut" \
    && cat "$f.mut" > "$f" && rm -f "$f.mut"
  grep -qxF -- "$new" "$f" || { echo "replacement did not land"; return 1; }
  bash -n "$f" 2>/dev/null || { echo "mutant does not parse"; return 1; }
}
mutant() {   # mutant ID FILE OLD NEW KILLER WHAT
  local id="$1" rel="$2" old="$3" new="$4" killer="$5" what="$6" m="" why=""
  m="$(mktemp -d "$WORK/mXXXXXX")"
  cp -Rp "$REPO_ROOT/scripts" "$m/" || { fail_ "$id" "could not build a mirror"; return; }
  why="$(mutate "$m/$rel" "$old" "$new")" || { fail_ "$id" "mutant did not land: $why"; return; }
  DETAIL=""
  if "$killer" "$m"; then fail_ "$id" "$what — SURVIVED: ${killer#case_} passes against the mutant"
  else pass "$id (MUTATION) — $what: killed by ${killer#case_}"; fi
}
echo "=== M — mutation proofs ==="
mutant M1 scripts/process-checklist.sh '# BL-354-DOCS-JSONL' \
  "      if echo \"\$file\" | grep -qE '\\.(md|json|yml|yaml|toml|tmpl)\$'; then" \
  case_J1 "check_commit_ready without jsonl"
mutant M2 scripts/process-checklist.sh '# BL-354-DOCS-JSONL' \
  "      if echo \"\$file\" | grep -qE '\\.(md|json|yml|yaml|toml|tmpl)\$'; then" \
  case_J2 "check_commit_ready without jsonl (feat subject)"
_acc_line="$(grep -F '# BL-233-WPB-EXEMPT-SET' "$REPO_ROOT/scripts/lib/accumulation.sh")"
_acc_nojsonl="$(printf '%s' "$_acc_line" | sed 's#\\\.claude/\[^/\]\*\\\.jsonl?\$#\\.claude/[^/]*\\.json$#')"
_acc_anyjsonl="$(printf '%s' "$_acc_line" | sed 's#(^|/)\\\.claude/\[^/\]\*\\\.jsonl?\$#\\.jsonl$#')"
if [ "$_acc_nojsonl" = "$_acc_line" ] || [ "$_acc_anyjsonl" = "$_acc_line" ]; then
  fail_ "M3/M4" "could not derive the accumulation mutants (the .claude jsonl arm is not on the marked line)"
else
  mutant M3 scripts/lib/accumulation.sh '# BL-233-WPB-EXEMPT-SET' "$_acc_nojsonl" case_A1 "accumulation without jsonl"
  mutant M4 scripts/lib/accumulation.sh '# BL-233-WPB-EXEMPT-SET' "$_acc_anyjsonl" case_A3 "accumulation exempts any .jsonl, not only .claude/'s"
fi

echo
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
