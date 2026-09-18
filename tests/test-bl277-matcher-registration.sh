#!/usr/bin/env bash
# tests/test-bl277-matcher-registration.sh
#
# `## BL-277:` — the scoped registration, pinned against a project init.sh
# actually produces. FULL LANE ONLY: this suite runs `init.sh --non-interactive`
# (twice: once on the tree, once on a mutated mirror), and init.sh installs the
# Claude Dev Framework from `~/.claude-dev-framework`, cloning it from GitHub
# when it is absent and pulling it when it is present. That is not hermetic, so
# per CLAUDE.md's membership rule it stays out of the tests.yml unit lane; the
# thirty hermetic cases for this entry live in
# tests/test-bl277-detector-authorship.sh, which also pins the registration's
# idempotence probe statically (R4) so the unit lane covers the jq filter
# without running the scaffolder.
#
# Cases: R1 the detector's PostToolUse registration sits under matcher Bash and
# nowhere else; R2 the Stop registration is present once; R3 the tool tracker
# and the commit recorder stay unscoped. M0 the marker is present once; M7 a
# mutant that writes the group without its matcher, proven by distance from the
# marker and by the literal text that landed, killed by R1.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT="$REPO_ROOT/init.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }

[ -f "$INIT" ] || { echo "  [FAIL] setup — $INIT not found"; echo ""; echo "Results: 0 passed, 1 failed"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "  [FAIL] setup — jq is required"; echo ""; echo "Results: 0 passed, 1 failed"; exit 1; }

# init_project <init.sh> <dest>; init.sh refuses to run from inside the
# framework checkout, so it is started from the temp tree.
init_project() {
  ( cd "$TOPTMP" && bash "$1" --non-interactive --project x --project-dir "$2" --no-remote-creation \
      --platform web --language typescript --track light --deployment personal >/dev/null 2>&1 )
  [ -f "$2/.claude/settings.json" ]
}
DET='select((.command // "") | contains("bypass-detector.sh"))'
chk_matcher_scoped() {
  local settings="$1/.claude/settings.json" scoped unscoped
  scoped="$(jq -r "[.hooks.PostToolUse[]? | select(.matcher == \"Bash\") | .hooks[]? | $DET] | length" "$settings" 2>/dev/null || printf 'ERR')"
  unscoped="$(jq -r "[.hooks.PostToolUse[]? | select((.matcher // \"\") != \"Bash\") | .hooks[]? | $DET] | length" "$settings" 2>/dev/null || printf 'ERR')"
  [ "$scoped" = "1" ] || { echo "detector registrations under matcher Bash=$scoped, want 1"; return 1; }
  [ "$unscoped" = "0" ] || { echo "detector registrations outside matcher Bash=$unscoped, want 0"; return 1; }
  return 0
}

# Text reaches awk through ENVIRON, never -v: -v applies backslash escapes, and
# the operative below contains \".
count_lit() { S="$2" awk 'index($0, ENVIRON["S"]){c++} END{print c+0}' "$1"; }
lines_lit() { S="$2" awk 'index($0, ENVIRON["S"]){print NR}' "$1"; }
mutate() {
  local f="$1" marker="$2" op="$3" rep="$4" maxd="$5" ml ol n_op n_rep_before n_rep_after removed added landed
  ml="$(lines_lit "$f" "$marker" | head -1)"
  [ -n "$ml" ] || { echo "marker '$marker' not found"; return 1; }
  n_op="$(count_lit "$f" "$op")"
  [ "$n_op" = "1" ] || { echo "operative text occurs $n_op times, want exactly 1"; return 1; }
  ol="$(lines_lit "$f" "$op")"
  [ "$ol" -gt "$ml" ] && [ $((ol - ml)) -le "$maxd" ] || { echo "operative line is $((ol - ml)) lines from the marker, want 1..$maxd"; return 1; }
  n_rep_before="$(count_lit "$f" "$rep")"
  MUT_BEFORE="$(newtmp)/before"; cp "$f" "$MUT_BEFORE" || { echo "could not snapshot"; return 1; }
  OP="$op" REP="$rep" awk '{ i = index($0, ENVIRON["OP"]); if (i) print substr($0, 1, i - 1) ENVIRON["REP"] substr($0, i + length(ENVIRON["OP"])); else print }' \
    "$MUT_BEFORE" > "$f" || { echo "awk failed"; return 1; }
  n_op="$(count_lit "$f" "$op")"
  n_rep_after="$(count_lit "$f" "$rep")"
  landed="$(sed -n "${ol}p" "$f" | S="$rep" awk 'index($0, ENVIRON["S"]){print "yes"}')"
  removed="$(diff "$MUT_BEFORE" "$f" | grep -c '^<')"; added="$(diff "$MUT_BEFORE" "$f" | grep -c '^>')"
  [ "$n_op" = "0" ] && [ "$n_rep_after" = "$((n_rep_before + 1))" ] && [ "$landed" = "yes" ] && [ "$removed" = "1" ] && [ "$added" = "1" ] \
    || { echo "did not land cleanly (operative left=$n_op, replacement $n_rep_before->$n_rep_after, on the operative line=${landed:-no}, removed=$removed, added=$added)"; return 1; }
  bash -n "$f" 2>/dev/null || { echo "the mutated file does not parse"; return 1; }
  return 0
}

echo "=== R — the registration in a fresh project ==="
PROJ="$TOPTMP/fresh"
if ! init_project "$INIT" "$PROJ"; then
  fail_ "R setup" "init.sh did not produce a project with a settings file (needs ~/.claude-dev-framework, node, and a git identity)"
else
  if why="$(chk_matcher_scoped "$PROJ")"; then pass "R1 — the detector's PostToolUse registration sits under matcher Bash and nowhere else"
  else fail_ "R1" "$why"; fi
  n_stop="$(jq -r "[.hooks.Stop[]? | .hooks[]? | $DET] | length" "$PROJ/.claude/settings.json" 2>/dev/null)"
  if [ "$n_stop" = "1" ]; then pass "R2 (control) — the Stop registration is present once"
  else fail_ "R2" "Stop registrations=$n_stop, want 1"; fi
  n_trk="$(jq -r '[.hooks.PostToolUse[]? | select(has("matcher") | not) | .hooks[]? | select((.command // "") | contains("track-tool-usage.sh"))] | length' "$PROJ/.claude/settings.json" 2>/dev/null)"
  n_rec="$(jq -r '[.hooks.PostToolUse[]? | select(has("matcher") | not) | .hooks[]? | select((.command // "") | contains("record-claude-commit.sh"))] | length' "$PROJ/.claude/settings.json" 2>/dev/null)"
  if [ "$n_trk" = "1" ] && [ "$n_rec" = "1" ]; then pass "R3 (control) — the tool tracker and the commit recorder stay unscoped: only the detector moved"
  else fail_ "R3" "unscoped tracker=$n_trk recorder=$n_rec, want 1 and 1"; fi
fi

echo "=== M — marker and mutant ==="
n="$(count_lit "$INIT" "# BL-277-MATCHER")"
if [ "$n" = "1" ]; then pass "M0 — '# BL-277-MATCHER' occurs once in init.sh"
else fail_ "M0" "'# BL-277-MATCHER' occurs $n times in init.sh, want 1"; fi

# M7 — the registration appended without its matcher. Killed by R1. Needs a
# mirror init.sh can run from: everything but .git, tests and Reports.
MI="$(newtmp)/fw"; mkdir -p "$MI"
for e in "$REPO_ROOT"/* "$REPO_ROOT"/.[!.]*; do
  b="$(basename "$e")"
  case "$b" in .git|tests|Reports|.semgrep) continue ;; esac
  cp -Rp "$e" "$MI/" 2>/dev/null
done
if [ ! -f "$MI/init.sh" ]; then fail_ "M7 setup" "could not mirror the framework"
elif why="$(mutate "$MI/init.sh" "# BL-277-MATCHER" \
       '.hooks.PostToolUse += [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/bypass-detector.sh"}]}]' \
       '.hooks.PostToolUse += [{"hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/scripts/hooks/bypass-detector.sh"}]}]' 5)"; then
  MPROJ="$TOPTMP/mutant-fresh"
  if ! init_project "$MI/init.sh" "$MPROJ"; then fail_ "M7 setup" "the mutated init.sh did not produce a project"
  elif chk_matcher_scoped "$MPROJ" >/dev/null 2>&1; then fail_ "M7 (MUTATION)" "dropping the matcher survived R1"
  elif [ "$(jq -r "[.hooks.PostToolUse[]? | .hooks[]? | $DET] | length" "$MPROJ/.claude/settings.json" 2>/dev/null)" != "1" ]; then
    fail_ "M7 (MUTATION)" "the mutant lost the registration entirely, so the kill proves nothing about the matcher"
  else pass "M7 (MUTATION) — the detector registered without a matcher: R1 kills it, the registration itself survives"; fi
else fail_ "M7 setup" "$why"; fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] && exit 0
exit 1
