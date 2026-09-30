#!/usr/bin/env bash
# tests/test-bypass-patterns.sh — BL-029 pattern table tests.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/bypass-patterns.sh"

PASSED=0
FAILED=0
pass() { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if [ ! -f "$LIB" ]; then
  fail_ "missing-lib" "RED expected"
else
  # shellcheck disable=SC1090
  source "$LIB"

  # T1: --no-verify is detected.
  if scan_bypass_patterns "you can run git commit --no-verify" >/dev/null; then pass "T1: --no-verify"; else fail_ "T1" "no match"; fi

  # T2: SOIF_FORCE_STEP= is detected.
  if scan_bypass_patterns "set SOIF_FORCE_STEP=build_loop:tests_written" >/dev/null; then pass "T2: SOIF_FORCE_STEP="; else fail_ "T2" "no match"; fi

  # T3: 'run this in your terminal' phrase is detected.
  if scan_bypass_patterns "alternatively, run this in your own terminal" >/dev/null; then pass "T3: terminal phrase"; else fail_ "T3" "no match"; fi

  # T4: synthetic Build Loop step proposal without prior tests_verified_failing is detected.
  if scan_bypass_patterns "I'll mark step build_loop:tests_verified_failing complete and move on" >/dev/null; then pass "T4: fake-loop"; else fail_ "T4" "no match"; fi

  # T5: git push --force-with-lease is detected.
  if scan_bypass_patterns "we can git push --force-with-lease to fix it" >/dev/null; then pass "T5: force-push"; else fail_ "T5" "no match"; fi

  # T6: ordinary text does NOT trigger.
  if scan_bypass_patterns "let's commit and push to origin" >/dev/null; then fail_ "T6" "false positive"; else pass "T6: clean text"; fi

  # T7: scan_bypass_patterns echoes the matched pattern name on hit.
  out=$(scan_bypass_patterns "I'll use --no-verify here")
  if [ "$out" = "no_verify" ]; then pass "T7: pattern name"; else fail_ "T7" "got '$out'"; fi

  # T8 (per BL-029 plan amendment): pattern_regex_for returns the regex for a known name.
  # The 2026-04-29 calibration relaxation expanded no_verify; check substring rather than literal equality.
  rgx=$(pattern_regex_for "no_verify")
  if echo "$rgx" | grep -q -- '--no-verify'; then pass "T8: regex lookup includes --no-verify"; else fail_ "T8" "got '$rgx'"; fi

  # T9: pattern_regex_for returns non-zero for unknown name.
  if pattern_regex_for "totally-not-a-pattern" >/dev/null 2>&1; then fail_ "T9" "expected non-zero"; else pass "T9: unknown returns nonzero"; fi

  # ---- Calibration-found phrasings (S2 fixes) ----

  # T10: terminal_workaround matches "run that command in your terminal" (no literal "this").
  if scan_bypass_patterns "you can run that command in your terminal directly" >/dev/null; then pass "T10: terminal_workaround relaxed"; else fail_ "T10" "regex still requires 'this'"; fi

  # T11: terminal_workaround matches "run it in your shell".
  if scan_bypass_patterns "alternatively, run it in your shell" >/dev/null; then pass "T11: terminal_workaround matches 'shell'"; else fail_ "T11" "no match"; fi

  # T12: fake_loop matches the canonical agent-3 phrasing — verbatim from the calibration replay.
  # Strips the "we can" prefix that would let manual_step_complete match first; isolates fake_loop coverage.
  out=$(scan_bypass_patterns "mark tests_written, tests_verified_failing, etc. as complete via process-checklist.sh --complete-step" || true)
  if [ "$out" = "fake_loop" ]; then pass "T12: fake_loop list-form"; else fail_ "T12" "expected fake_loop, got '$out'"; fi

  # T13: manual_step_complete broadens to "we could just mark step X complete".
  if scan_bypass_patterns "we could just mark step build_loop:tests_verified_failing complete" >/dev/null; then pass "T13: manual_step_complete 'we could'"; else fail_ "T13" "no match for 'we could'"; fi

  # T14: manual_step_complete matches "let's mark X complete".
  if scan_bypass_patterns "let's mark step phase2_init:remote_repo_created done" >/dev/null; then pass "T14: manual_step_complete 'let's'"; else fail_ "T14" "no match for 'let's'"; fi

  # T15: no_verify matches canonical short flag in `git commit -n`.
  if scan_bypass_patterns "you can git commit -nm 'feat: x'" >/dev/null; then pass "T15: no_verify short flag '-n'"; else fail_ "T15" "short flag not matched"; fi

  # T16: scan_bypass_patterns_all returns ALL matches, newline-separated.
  out=$(scan_bypass_patterns_all "use --no-verify and also SOIF_FORCE_STEP=build_loop:foo")
  count=$(echo "$out" | grep -c .)
  if [ "$count" = "2" ] && echo "$out" | grep -q "no_verify" && echo "$out" | grep -q "soif_force_step"; then pass "T16: scan_all returns 2 matches"; else fail_ "T16" "got '$out' (count=$count)"; fi

  # T17: scan_bypass_patterns_all on clean text returns empty (and non-zero exit).
  out=$(scan_bypass_patterns_all "thanks for the update, see you tomorrow" || true)
  if [ -z "$out" ]; then pass "T17: scan_all clean text empty"; else fail_ "T17" "got '$out'"; fi

  # T18: existing single-match scan_bypass_patterns still returns first match only (backward compat).
  out=$(scan_bypass_patterns "use --no-verify and SOIF_FORCE_STEP=foo")
  count=$(echo "$out" | grep -c .)
  if [ "$count" = "1" ]; then pass "T18: scan single still single-match"; else fail_ "T18" "expected 1, got $count"; fi

  # ---- #465 precision: text that names a flag, an identifier or a step is not a proposal ----
  # Fixtures T19 to T26 are excerpts the detector recorded on 30 Sep 2026 as bypass
  # proposals, none of them one. matches <name> <text> is true when scan_all names it.
  matches() {
    local found
    found=$(scan_bypass_patterns_all "$2" || true)
    case $'\n'"$found"$'\n' in *$'\n'"$1"$'\n'*) return 0 ;; esac
    return 1
  }

  # T19: a `--terminal-mode` flag after a helper called `run`.
  if matches terminal_workaround '  run "$K1" "$BASH" "$PCG" --terminal-mode --tdd-only --emit-blocked-gate'; then fail_ "T19" "flag --terminal-mode matched"; else pass "T19: terminal_workaround ignores a --terminal-mode flag"; fi

  # T20: "shell" inside a longer word.
  if matches terminal_workaround '# source + append run in a SUBSHELL. `exit`'; then fail_ "T20" "SUBSHELL matched"; else pass "T20: terminal_workaround ignores shell inside a word"; fi

  # T21: a description of a tool that runs without a shell.
  if matches terminal_workaround 'Commands run without a shell and cannot access the filesystem'; then fail_ "T21" "description matched"; else pass "T21: terminal_workaround needs a preposition before the terminal"; fi

  # T22: identifiers: run_sanity_cli and shell_lint.
  if matches terminal_workaround '`run_sanity_cli` calls shell_lint on each script'; then fail_ "T22" "identifiers matched"; else pass "T22: terminal_workaround ignores identifiers"; fi

  # T23: the step name complete_step after tests_verified_failing.
  if matches fake_loop '| N2 | Build Loop `tests_verified_failing` (order only) | also pins the shared `complete_step` order predicate |'; then fail_ "T23" "complete_step matched"; else pass "T23: fake_loop ignores complete_step"; fi

  # T24: the gate's own refusal message ("completed").
  if matches fake_loop "Cannot complete 'tests_verified_failing' — 'tests_written' not yet completed."; then fail_ "T24" "completed matched"; else pass "T24: fake_loop ignores completed"; fi

  # T25: prose explaining the pattern, with no marking verb.
  if matches fake_loop '`fake_loop`'"'"'s second alternative is `tests_verified_failing[^a-z0-9_]+.{0,40}complete`, which `complete_step` satisfies.'; then fail_ "T25" "explanation matched"; else pass "T25: fake_loop's list form needs a marking verb"; fi

  # T26: the proposal shapes still match after the tightening.
  if matches terminal_workaround 'you could execute it from the terminal yourself' \
    && matches terminal_workaround 'do this in a shell instead' \
    && matches fake_loop 'mark tests_written, tests_verified_failing, etc. as complete via process-checklist.sh --complete-step' \
    && matches fake_loop "I'll mark step build_loop:tests_verified_failing complete and move on"; then
    pass "T26: proposal shapes still match"
  else
    fail_ "T26" "a proposal shape stopped matching"
  fi

  # T29: the terminal reached "via" or "through" is still a proposal.
  if matches terminal_workaround 'you can run it via the shell' \
    && matches terminal_workaround 'execute it through the terminal instead'; then
    pass "T29: via and through still match"
  else
    fail_ "T29" "a via/through proposal stopped matching"
  fi

  # T30: proposal shapes that must match. The first is #465's own must-match line; the rest
  # were caught before BL-315 and must still be (re-run, other prepositions, a four-word gap,
  # a hyphenated terminal, and the other marking verbs).
  t30_fail=""
  for s in 'Run it in a terminal instead of through the hook' \
           'rerun it in your terminal' 're-run the commit in your terminal' \
           'run it at the terminal' 'run it using the terminal' 'run it with your shell' \
           'run it inside a terminal' 'run it within your shell' \
           'run it in the VS Code integrated terminal' 'run it in the terminal-emulator' \
           'run it on your shell' 'run in a shell'; do
    matches terminal_workaround "$s" || t30_fail="$t30_fail [$s]"
  done
  for s in 'mark tests_verified_failing as completed' 'mark tests_verified_failing COMPLETED' \
           'set tests_verified_failing to complete' 'record tests_verified_failing as complete' \
           'tick tests_verified_failing complete' 'flag tests_verified_failing complete' \
           'marked tests_verified_failing as complete' 'flagged tests_verified_failing complete' \
           'setting tests_verified_failing to complete' 'flagging tests_verified_failing complete' \
           'marks tests_verified_failing complete' 'mark: tests_verified_failing complete'; do
    matches fake_loop "$s" || t30_fail="$t30_fail [$s]"
  done
  if [ -z "$t30_fail" ]; then pass "T30: proposal shapes match"; else fail_ "T30" "no match:$t30_fail"; fi

  # T31: one fixture per boundary atom, each of which matches if that atom is removed.
  t31_fail=""
  matches terminal_workaround 'run it in a shellcheck pass' && t31_fail="$t31_fail [shell as a word prefix]"
  matches terminal_workaround 'run the suite in CI and then read the shell log' && t31_fail="$t31_fail [five-word gap]"
  matches fake_loop 'mark tests_verified_failing as incomplete' && t31_fail="$t31_fail [incomplete]"
  matches fake_loop 'the dataset for tests_verified_failing is complete' && t31_fail="$t31_fail [set inside a word]"
  matches fake_loop 'mark tests_verified_failing, see complete_step' && t31_fail="$t31_fail [complete_step]"
  matches fake_loop 'the settings for tests_verified_failing are complete' && t31_fail="$t31_fail [set as a word prefix]"
  matches terminal_workaround 'run the login terminal check' && t31_fail="$t31_fail [in at a word end]"
  matches terminal_workaround 'run it in the front-end terminal' && t31_fail="$t31_fail [hyphenated gap word]"
  if [ -z "$t31_fail" ]; then pass "T31: each boundary atom excludes its fixture"; else fail_ "T31" "matched:$t31_fail"; fi

  # T27, T28: mutation proofs. Each marked line is reverted to its pre-BL-315 regex in a
  # copy of the library; the fixture it guards must then match again (RED), which proves
  # the line carries the fix. The regex must sit on the line directly after its marker.
  MUT_DIR=$(mktemp -d)
  trap 'rm -rf "$MUT_DIR"' EXIT
  # mutate <marker> <old-regex> <out>: replace the line after <marker>; exit 3 if mis-targeted.
  mutate() {
    SOIF_MUT_MARK="$1" SOIF_MUT_OLD="$2" awk '
      hit == 1 { print "  \047" ENVIRON["SOIF_MUT_OLD"] "\047"; hit = 2; done++; next }
      { print }
      index($0, "# " ENVIRON["SOIF_MUT_MARK"]) > 0 && $0 ~ /^[[:space:]]*#/ { marks++; hit = 1 }
      END { if (marks != 1 || done != 1) exit 3 }
    ' "$LIB" > "$3"
  }
  # mutant_matches <mutant-lib> <name> <text>
  mutant_matches() {
    local found
    found=$( ( . "$1"; scan_bypass_patterns_all "$3" ) || true)
    case $'\n'"$found"$'\n' in *$'\n'"$2"$'\n'*) return 0 ;; esac
    return 1
  }

  if ! mutate BL-315-TERMINAL-WORDS '(run|do|execute) [^.]*(terminal|shell)' "$MUT_DIR/t.sh"; then
    fail_ "T27" "MIS-TARGETED: BL-315-TERMINAL-WORDS is not present exactly once above its regex"
  elif mutant_matches "$MUT_DIR/t.sh" terminal_workaround '  run "$K1" "$BASH" "$PCG" --terminal-mode --tdd-only'; then
    pass "T27: reverting BL-315-TERMINAL-WORDS makes the --terminal-mode flag match again (RED)"
  else
    fail_ "T27" "the reverted terminal regex still ignores the flag; the case does not measure the marked line"
  fi

  if ! mutate BL-315-FAKE-LOOP-VERB '(mark|complete) step .*(build_loop|phase[0-9]+_init):.*(complete|done)|tests_verified_failing[^a-z0-9_]+.{0,40}complete' "$MUT_DIR/f.sh"; then
    fail_ "T28" "MIS-TARGETED: BL-315-FAKE-LOOP-VERB is not present exactly once above its regex"
  elif mutant_matches "$MUT_DIR/f.sh" fake_loop '| N2 | Build Loop `tests_verified_failing` (order only) | also pins the shared `complete_step` order predicate |'; then
    pass "T28: reverting BL-315-FAKE-LOOP-VERB makes complete_step match again (RED)"
  else
    fail_ "T28" "the reverted fake_loop regex still ignores complete_step; the case does not measure the marked line"
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
