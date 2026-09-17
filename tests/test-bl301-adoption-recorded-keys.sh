#!/usr/bin/env bash
# tests/test-bl301-adoption-recorded-keys.sh
#
# `## BL-301:` (issue #418) — THE BROWNFIELD ADOPTION DRIVER RECORDS INTAKE
# ROWS UNDER KEYS THE WIZARD DOES NOT OWN, AND THE WIZARD'S AMEND ROUTE
# (`--set-answer`, `## BL-282:`) REFUSED THEM. `test_command`, `timeline`,
# `mvp_features` and the rest exist in `.claude/intake-progress.json` only
# because `scripts/lib/adopt/adopt-intake.sh` wrote them, so the tool that
# wrote the row could not amend it and the tool that amends could not see it.
#
# The maintainer's decision on #418 (option 3, the wizard half): the amend
# route ACCEPTS any key already present in the progress file's `answers`,
# the recorded amendment NOTES that the key is adoption-recorded, and the
# refusal is KEPT for a key that exists nowhere. The adoption-driver half is
# ADOPT-002-ARCH v2.2 and is not built or tested here.
#
# Every case drives the REAL wizard from an ADOPTED-shape project fixture —
# the shape `adopt_render_intake_progress` writes (`source:
# "adopt-project.sh"`, `last_section: 0`, Scout's fifteen prefill fields) —
# with stdin closed. The wizard runs under the SAME interpreter as this suite
# (`$BASH`), so a run under /bin/bash 3.2 exercises the wizard under 3.2.
#
# RED/GREEN shape. At the parent commit the route does not exist, so the A,
# D, F, I2 and M cases are red there. C1, G1, R1, R2, N1, N2 and I1 are green
# at the parent BY DESIGN and are what prove the fixture works: C1/R1/R2 are
# the no-regression pins for wizard-owned keys, G1 is the vacuous-pass guard
# (it proves the keys under test are NOT wizard-owned, so an A-case pass can
# only come from the new route), N1/N2/I1 are refusals that must survive.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WIZARD="$REPO_ROOT/scripts/intake-wizard.sh"
RUN_BASH="${BASH:-bash}"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
# A mutant that cannot be APPLIED is a stale proof, not a killed mutant. It
# still fails the suite, but under its own label and its own count, so a red
# that comes from a sed no longer matching is never read as a behavioural kill.
SETUP_FAILED=0
fail_setup() { echo "  [FAIL] $1 SETUP — NOT A BEHAVIOURAL KILL — $2"; FAILED=$((FAILED + 1)); SETUP_FAILED=$((SETUP_FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }
_changed_lines() { local n; n=$(diff "$1" "$2" 2>/dev/null | grep -c '^[<>]'); case "$n" in ''|*[!0-9]*) n=0 ;; esac; printf '%s\n' "$n"; }
_syntax_ok() { "$RUN_BASH" "-n" "$1" 2>/dev/null; }
strip_ansi() { sed 's/\x1b\[[0-9;]*m//g' "$1"; }
_cksum() { cksum < "$1" | cut -d' ' -f1; }

[ -f "$WIZARD" ] || { echo "  [FAIL] setup — $WIZARD not found"; echo ""; echo "Results: 0 passed, 1 failed"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "  [FAIL] setup — python3 is required (the wizard's state writes go through it)"; echo ""; echo "Results: 0 passed, 1 failed"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "  [FAIL] setup — jq is required (render_intake_file and the assertions use it)"; echo ""; echo "Results: 0 passed, 1 failed"; exit 1; }

echo "interpreter: $RUN_BASH ($("$RUN_BASH" -c 'printf %s "$BASH_VERSION"'))"

OLD_CMD='pnmp test:unit'
NEW_CMD='pnpm test:unit'
ODD_KEY='odd.key"$HOME[0]'
# Three recorded keys the Answers TABLE cannot carry raw: a pipe opens a
# column, a newline splits the row, a backtick closes the code span.
PIPE_KEY='pipe|key'
NL_KEY="$(printf 'line\nkey')"
TICK_KEY='tick`key'
BODY_LINE='- **test_command** (scan-derived): pnmp test:unit'

# mk_adopted <dir> [wizard-file] — a project as adoption leaves it, with a
# COPY of the wizard and its helpers so nothing here touches the checkout.
# `answers` carries Scout's fifteen prefill fields (scout-prefill.sh's
# table): A7 placeholders blank, `test_command` with the transcription slip
# from the issue, plus one key with shell- and jq-special characters.
mk_adopted() {
  local d="$1" bin="${2:-$WIZARD}"
  mkdir -p "$d/.claude" "$d/scripts/lib" || return 1
  cp "$bin" "$d/scripts/intake-wizard.sh" || return 1
  cp "$REPO_ROOT"/scripts/lib/helpers*.sh "$d/scripts/lib/" 2>/dev/null || return 1
  printf '{"project":"P","current_phase":0,"track":"full","deployment":"personal","poc_mode":null}\n' \
    > "$d/.claude/phase-state.json"
  printf '{}\n' > "$d/.claude/process-state.json"
  jq -n --arg odd "$ODD_KEY" --arg cmd "$OLD_CMD" --arg pk "$PIPE_KEY" --arg nk "$NL_KEY" --arg tk "$TICK_KEY" '
    {version: 1, started_at: "2026-09-01T00:00:00Z", last_section: 0, completed_sections: [],
     source: "adopt-project.sh",
     project_name: "P", platform: "", track: "full", deployment: "personal",
     language: "", description: "",
     answers: ({project_name: "P", repo_remote_configured: "yes", problem_statement: "",
       timeline: "", mvp_features: "", data_classification: "", competency_matrix: "",
       revenue_model: "", governance: "", accessibility: "", uptime: "99.0",
       known_risks: "", test_command: $cmd, tooling: "pnpm",
       agent_init_prompt: "generated"} + {($odd): "odd-old", ($pk): "p-old", ($nk): "n-old", ($tk): "t-old"})}' \
    > "$d/.claude/intake-progress.json" || return 1
  {
    printf '# Project Intake\n\nRecorded during adoption on 2026-09-01.\n\n'
    printf '## Testing & Bug Tracking\n\n%s\n  - Source: stack.testCommand\n' "$BODY_LINE"
  } > "$d/PROJECT_INTAKE.md"
  jq empty "$d/.claude/intake-progress.json" 2>/dev/null || return 1
  return 0
}

# wiz <dir> <args…> — the real wizard, stdin closed, output to run.out.
wiz() {
  local d="$1"; shift
  ( cd "$d" && "$RUN_BASH" scripts/intake-wizard.sh "$@" ) >"$d/run.raw" 2>&1 </dev/null
  WIZ_RC=$?
  strip_ansi "$d/run.raw" > "$d/run.out"
  return 0
}

PROG=".claude/intake-progress.json"
jq_answer()  { jq -r --arg k "$1" '.answers[$k] // "<<unset>>"' "$2/$PROG" 2>/dev/null; }
jq_amend_n() { jq -r '(.amendments // []) | length' "$1/$PROG" 2>/dev/null; }
jq_amend()   { jq -r --argjson i "$1" --arg f "$2" '.amendments[$i][$f] // "<<unset>>"' "$3/$PROG" 2>/dev/null; }
# others_sum <dir> <key> → a checksum of every answer EXCEPT <key>.
others_sum() { jq -S -c --arg k "$2" '.answers | del(.[$k])' "$1/$PROG" 2>/dev/null | cksum | cut -d' ' -f1; }
rendered_row() { awk -F'|' -v k=" \`$2\` " '$2 == k { gsub(/^ +| +$/, "", $3); print $3; exit }' "$1/PROJECT_INTAKE.md"; }
# body_sum <dir> → checksum of PROJECT_INTAKE.md above the wizard's appendix,
# trailing blank lines dropped (the renderer normalises those itself).
body_sum() {
  awk '$0 == "<!-- INTAKE_ANSWERS_BEGIN -->" { exit } { print }' "$1/PROJECT_INTAKE.md" \
    | awk '/^$/ { b++; next } { while (b-- > 0) print ""; b = 0; print }' | cksum | cut -d' ' -f1
}
_pwned() { find "$TOPTMP" -name 'PWNED*' 2>/dev/null | head -1; }

echo "=== C/G — controls and the vacuous-pass guard (green at the parent too) ==="

# C1 — the BL-282 route works in THIS fixture: a wizard-owned key that
# adoption also recorded (`uptime`) is amended.
C1="$(newtmp)/proj"
if ! mk_adopted "$C1"; then
  fail_ "C1 setup" "could not build the fixture"
else
  wiz "$C1" --set-answer uptime "99.9"
  got="$(jq_answer uptime "$C1")"
  if [ "$WIZ_RC" -eq 0 ] && [ "$got" = "99.9" ]; then
    pass "C1 (control) — a wizard-owned key is amended in the adopted-shape fixture (rc=$WIZ_RC)"
  else
    fail_ "C1 (control)" "rc=$WIZ_RC answers.uptime=[$got], want [99.9] — the BL-282 route or the fixture is broken"
  fi
fi

# G1 — THE VACUOUS-PASS GUARD. A wizard-owned key is accepted even when it
# was never answered (BL-282's H9), so a key that is REFUSED once it is
# removed from answers/ is provably not wizard-owned. Without this, an
# A-case could pass through BL-282's own route — `competency_matrix` does
# exactly that (it shape-matches the `competency_$key` family) — and prove
# nothing about this fix.
for gk in test_command timeline competency_matrix; do
  G1="$(newtmp)/proj"
  if ! mk_adopted "$G1"; then
    fail_ "G1 setup" "could not build the fixture"
    continue
  fi
  jq --arg k "$gk" 'del(.answers[$k])' "$G1/$PROG" > "$G1/p.tmp" && mv "$G1/p.tmp" "$G1/$PROG"
  before_p="$(_cksum "$G1/$PROG")"
  wiz "$G1" --set-answer "$gk" "x"
  after_p="$(_cksum "$G1/$PROG")"
  if [ "$WIZ_RC" -eq 1 ] && [ "$before_p" = "$after_p" ]; then
    pass "G1 (guard) — '$gk' removed from answers/ is refused (rc=$WIZ_RC), so it is not a wizard-owned key"
  else
    fail_ "G1 (guard)" "'$gk' absent from answers/ gave rc=$WIZ_RC (want 1), progress $([ "$before_p" = "$after_p" ] && echo unchanged || echo CHANGED) — the key is wizard-owned and every A-case using it is vacuous"
  fi
done

echo "=== A — an adoption-recorded key is accepted, written, and noted ==="

A="$(newtmp)/proj"
if ! mk_adopted "$A"; then
  fail_ "A setup" "could not build the fixture"
else
  others_before="$(others_sum "$A" test_command)"
  wiz "$A" --set-answer test_command "$NEW_CMD" --reason "transcription slip in package.json"

  # A1 — exit 0 and the value is written.
  got="$(jq_answer test_command "$A")"
  if [ "$WIZ_RC" -eq 0 ] && [ "$got" = "$NEW_CMD" ]; then
    pass "A1 — --set-answer test_command (adoption-recorded, not wizard-owned) writes the new value (rc=$WIZ_RC)"
  else
    fail_ "A1" "rc=$WIZ_RC answers.test_command=[$got], want [$NEW_CMD]: $(tail -2 "$A/run.out" | tr '\n' ' ')"
  fi

  # A2 — every other answer is untouched (non-vacuous: needs the write).
  others_after="$(others_sum "$A" test_command)"
  if [ "$WIZ_RC" -eq 0 ] && [ "$others_before" = "$others_after" ]; then
    pass "A2 — the other $(( $(jq -r '.answers | length' "$A/$PROG") - 1 )) recorded answers are unchanged"
  else
    fail_ "A2" "rc=$WIZ_RC; other answers $([ "$others_before" = "$others_after" ] && echo unchanged || echo CHANGED)"
  fi

  # A3 — the amendment carries BL-282's five fields AND the note.
  n="$(jq_amend_n "$A")"
  a_key="$(jq_amend 0 key "$A")"; a_old="$(jq_amend 0 old "$A")"; a_new="$(jq_amend 0 new "$A")"
  a_reason="$(jq_amend 0 reason "$A")"; a_at="$(jq_amend 0 at "$A")"; a_note="$(jq_amend 0 note "$A")"
  if [ "$n" = "1" ] && [ "$a_key" = "test_command" ] && [ "$a_old" = "$OLD_CMD" ] && [ "$a_new" = "$NEW_CMD" ] \
     && [ "$a_reason" = "transcription slip in package.json" ] \
     && printf '%s' "$a_at" | grep -q -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' \
     && printf '%s' "$a_note" | grep -q 'adoption-recorded'; then
    pass "A3 — amendments[0] carries key/old/new/reason/at and note=[$a_note]"
  else
    fail_ "A3" "amendments=$n key=[$a_key] old=[$a_old] new=[$a_new] reason=[$a_reason] at=[$a_at] note=[$a_note]"
  fi

  # A4 — the operator-visible line says so too.
  if grep -F "[OK] test_command: \"$OLD_CMD\" -> \"$NEW_CMD\"" "$A/run.out" | grep -q 'adoption-recorded'; then
    pass "A4 — the [OK] line names the key as adoption-recorded"
  else
    fail_ "A4" "no [OK] … adoption-recorded line: $(grep -m1 'test_command' "$A/run.out" || echo '<none>')"
  fi

  # D1 — BL-282's route re-renders EVERY key in answers/ (render_intake_file
  # walks `.answers | to_entries`), so the adoption-recorded row is rendered
  # and carries the marker.
  day="$(printf '%s' "$a_at" | cut -c1-10)"
  got="$(rendered_row "$A" test_command)"
  if [ -n "$day" ] && [ "$got" = "$NEW_CMD (amended $day)" ]; then
    pass "D1 — PROJECT_INTAKE.md's Answers row reads [$got]"
  else
    fail_ "D1" "rendered test_command row is [$got], want [$NEW_CMD (amended $day)]"
  fi

  # A6 — a second correction appends, and is noted as well.
  wiz "$A" --set-answer test_command "pnpm run test:unit"
  n="$(jq_amend_n "$A")"; a_old="$(jq_amend 1 old "$A")"; a_note="$(jq_amend 1 note "$A")"
  if [ "$WIZ_RC" -eq 0 ] && [ "$n" = "2" ] && [ "$a_old" = "$NEW_CMD" ] && printf '%s' "$a_note" | grep -q 'adoption-recorded'; then
    pass "A6 — a second correction appends amendments[1] (old=[$a_old]) with the note"
  else
    fail_ "A6" "rc=$WIZ_RC amendments=$n old=[$a_old] note=[$a_note]"
  fi
fi

# A5 — an A7 placeholder (blank, "left blank by adoption") is amended; the
# old value is recorded as the empty string it was, not as null.
A5="$(newtmp)/proj"
if ! mk_adopted "$A5"; then
  fail_ "A5 setup" "could not build the fixture"
else
  wiz "$A5" --set-answer timeline "MVP by 2026-12-01"
  got="$(jq_answer timeline "$A5")"
  a_old_json="$(jq -c '.amendments[0].old' "$A5/$PROG" 2>/dev/null)"
  if [ "$WIZ_RC" -eq 0 ] && [ "$got" = "MVP by 2026-12-01" ] && [ "$a_old_json" = '""' ]; then
    pass "A5 — a blank A7 placeholder (timeline) is amended; amendments[0].old is \"\" (rc=$WIZ_RC)"
  else
    fail_ "A5" "rc=$WIZ_RC timeline=[$got] old=$a_old_json (want \"\")"
  fi
fi

# D2 — the amend route owns the appendix and nothing above it: adoption's own
# prose, including its `- **test_command** …` line, is preserved byte for
# byte. (That line therefore still shows the old value — a residual the entry
# names; the appendix row is the amended record.) Conditioned on rc=0 so it
# cannot pass on a refusal that wrote nothing.
D2="$(newtmp)/proj"
if ! mk_adopted "$D2"; then
  fail_ "D2 setup" "could not build the fixture"
else
  body_before="$(body_sum "$D2")"
  wiz "$D2" --set-answer test_command "$NEW_CMD"
  body_after="$(body_sum "$D2")"
  if [ "$WIZ_RC" -eq 0 ] && [ "$body_before" = "$body_after" ] && grep -q -F -x -- "$BODY_LINE" "$D2/PROJECT_INTAKE.md" \
     && grep -q -F -x '<!-- INTAKE_ANSWERS_BEGIN -->' "$D2/PROJECT_INTAKE.md"; then
    pass "D2 — everything above the appendix is byte-identical; adoption's own line is not rewritten"
  else
    fail_ "D2" "rc=$WIZ_RC; body $([ "$body_before" = "$body_after" ] && echo unchanged || echo CHANGED); appendix $(grep -q -F -x '<!-- INTAKE_ANSWERS_BEGIN -->' "$D2/PROJECT_INTAKE.md" && echo present || echo missing)"
  fi
fi

# A8 — `competency_matrix` reaches THIS route now. At `91b5066` it rode
# BL-282's `competency_$key` family (any `competency_*` was accepted and
# minted); `# BL-282-COMPETENCY-DOMAINS` (e151dc0) bounds that family to the
# wizard's nine domains, so the adoption-recorded `competency_matrix` is now
# accepted here, with the note (A8), and `competency_zzz`, recorded nowhere,
# is refused with nothing written (N4). G1 guards the first half: if the
# family ever widens again, `competency_matrix` is accepted with answers/
# emptied and G1 says A8 has gone vacuous.
A8="$(newtmp)/proj"
if ! mk_adopted "$A8"; then
  fail_ "A8 setup" "could not build the fixture"
else
  wiz "$A8" --set-answer competency_matrix "Backend strong, UX weak"
  got="$(jq_answer competency_matrix "$A8")"; a_note="$(jq_amend 0 note "$A8")"
  if [ "$WIZ_RC" -eq 0 ] && [ "$got" = "Backend strong, UX weak" ] && printf '%s' "$a_note" | grep -q 'adoption-recorded' \
     && grep -F '[OK] competency_matrix:' "$A8/run.out" | grep -q 'adoption-recorded'; then
    pass "A8 — competency_matrix, once BL-282's family key, is now amended through this route with note=[$a_note] (rc=$WIZ_RC)"
  else
    fail_ "A8" "rc=$WIZ_RC competency_matrix=[$got] note=[$a_note]: $(grep -m1 'competency_matrix' "$A8/run.out" || echo '<none>')"
  fi
  before_p="$(_cksum "$A8/$PROG")"
  wiz "$A8" --set-answer competency_zzz "minted"
  after_p="$(_cksum "$A8/$PROG")"
  if [ "$WIZ_RC" -eq 1 ] && [ "$before_p" = "$after_p" ]; then
    pass "N4 (control) — competency_zzz, recorded nowhere, is refused (rc=$WIZ_RC), nothing written: BL-282's family no longer mints it"
  else
    fail_ "N4 (control)" "rc=$WIZ_RC (want 1); progress $([ "$before_p" = "$after_p" ] && echo unchanged || echo CHANGED) — BL-282's competency family is minting again"
  fi
fi

# A7 — the flag's help says which keys it takes.
A7="$(newtmp)/proj"
if ! mk_adopted "$A7"; then
  fail_ "A7 setup" "could not build the fixture"
else
  wiz "$A7" --help
  if [ "$WIZ_RC" -eq 0 ] && grep -q -- '--set-answer KEY VALUE' "$A7/run.out" && grep -q 'adoption' "$A7/run.out"; then
    pass "A7 — --help still lists --set-answer and names adoption-recorded keys"
  else
    fail_ "A7" "rc=$WIZ_RC; --set-answer $(grep -q -- '--set-answer KEY VALUE' "$A7/run.out" && echo listed || echo missing); adoption $(grep -q 'adoption' "$A7/run.out" && echo named || echo 'not named')"
  fi
fi

echo "=== R — a wizard-owned key behaves exactly as under BL-282 ==="

R1="$(newtmp)/proj"
if ! mk_adopted "$R1"; then
  fail_ "R1 setup" "could not build the fixture"
else
  wiz "$R1" --set-answer uptime "99.9" --reason "r"
  shape="$(jq -c '.amendments[0] | keys' "$R1/$PROG" 2>/dev/null)"
  if [ "$WIZ_RC" -eq 0 ] && [ "$shape" = '["at","key","new","old","reason"]' ] \
     && grep -q -F -x '  [OK] uptime: "99.0" -> "99.9" (amended, recorded)' "$R1/run.out"; then
    pass "R1 (control) — a wizard-owned key's amendment has exactly BL-282's five fields, no note, and BL-282's [OK] line"
  else
    fail_ "R1 (control)" "rc=$WIZ_RC amendment keys=$shape; line=[$(grep -m1 'uptime' "$R1/run.out" || echo '<none>')]"
  fi
fi

R2="$(newtmp)/proj"
if ! mk_adopted "$R2"; then
  fail_ "R2 setup" "could not build the fixture"
else
  wiz "$R2" --set-answer hard_deadline "2026-12-01"
  shape="$(jq -c '.amendments[0] | keys' "$R2/$PROG" 2>/dev/null)"; a_old="$(jq -c '.amendments[0].old' "$R2/$PROG" 2>/dev/null)"
  if [ "$WIZ_RC" -eq 0 ] && [ "$(jq_answer hard_deadline "$R2")" = "2026-12-01" ] && [ "$a_old" = "null" ] \
     && [ "$shape" = '["at","key","new","old","reason"]' ]; then
    pass "R2 (control) — a wizard-owned key never answered is still accepted (old=null) and carries no note"
  else
    fail_ "R2 (control)" "rc=$WIZ_RC hard_deadline=[$(jq_answer hard_deadline "$R2")] old=$a_old keys=$shape"
  fi
fi

echo "=== N — a key that exists nowhere is still refused, nothing written ==="

N1="$(newtmp)/proj"
if ! mk_adopted "$N1"; then
  fail_ "N1 setup" "could not build the fixture"
else
  before_p="$(_cksum "$N1/$PROG")"; before_i="$(_cksum "$N1/PROJECT_INTAKE.md")"
  wiz "$N1" --set-answer test_commandd "$NEW_CMD"
  after_p="$(_cksum "$N1/$PROG")"; after_i="$(_cksum "$N1/PROJECT_INTAKE.md")"
  if [ "$WIZ_RC" -eq 1 ] && grep -q 'nothing written' "$N1/run.out" \
     && [ "$before_p" = "$after_p" ] && [ "$before_i" = "$after_i" ]; then
    pass "N1 (control) — a key in neither the wizard's set nor answers/ is refused (rc=$WIZ_RC), nothing is written"
  else
    fail_ "N1 (control)" "rc=$WIZ_RC (want 1); progress $([ "$before_p" = "$after_p" ] && echo unchanged || echo CHANGED); intake $([ "$before_i" = "$after_i" ] && echo unchanged || echo CHANGED)"
  fi
fi

# N2 — presence means presence IN answers/. `source` is a top-level key of
# the progress file (adoption writes it) and is not an answer.
N2="$(newtmp)/proj"
if ! mk_adopted "$N2"; then
  fail_ "N2 setup" "could not build the fixture"
else
  before_p="$(_cksum "$N2/$PROG")"
  wiz "$N2" --set-answer source "x"
  after_p="$(_cksum "$N2/$PROG")"
  if [ "$WIZ_RC" -eq 1 ] && [ "$before_p" = "$after_p" ]; then
    pass "N2 (control) — a key present only at the progress file's top level (source) is refused (rc=$WIZ_RC), nothing written"
  else
    fail_ "N2 (control)" "rc=$WIZ_RC (want 1); progress $([ "$before_p" = "$after_p" ] && echo unchanged || echo CHANGED)"
  fi
fi

# N3 — MEMBERSHIP IS EXACT, and N1's one typo did not prove it (review
# R-294-1: four single-line mutants minted a key with the suite green). Each
# key below is a NEAR-MISS of something recorded — a prefix, a substring, a
# case variant, the key with a space either side, and a recorded VALUE
# (`tooling` is "pnpm") offered as a key. Every one must be refused at exit 1
# with the progress file byte-identical. MA8–MA11 are what each one stops.
N3="$(newtmp)/proj"
if ! mk_adopted "$N3"; then
  fail_ "N3 setup" "could not build the fixture"
else
  before_p="$(_cksum "$N3/$PROG")"; bad=""; n3_n=0
  for nk in 'test_comman' 'est_comm' 'TEST_COMMAND' 'Test_Command' 'test_command ' ' test_command' 'pnpm' 'pnmp test:unit'; do
    n3_n=$((n3_n + 1))
    wiz "$N3" --set-answer "$nk" "MINTED"
    [ "$WIZ_RC" -eq 1 ] || bad="$bad [rc=$WIZ_RC for '$nk']"
    [ "$(_cksum "$N3/$PROG")" = "$before_p" ] || { bad="$bad [progress CHANGED by '$nk']"; before_p="$(_cksum "$N3/$PROG")"; }
  done
  if [ -z "$bad" ]; then
    pass "N3 (control) — $n3_n near-misses of recorded keys (prefix, substring, case, padded, a recorded value) are each refused (rc=1), progress file byte-identical"
  else
    fail_ "N3 (control)" "membership is not exact:$bad"
  fi
fi

echo "=== F — a missing or malformed answers object fails closed ==="

# f_case <id> <label> <jq-filter | RAW:text> <message-regex>
f_case() {
  local id="$1" label="$2" shape="$3" want="$4" d before_p after_p
  d="$(newtmp)/proj"
  if ! mk_adopted "$d"; then fail_ "$id setup" "could not build the fixture"; return 0; fi
  case "$shape" in
    RAW:*) printf '%s\n' "${shape#RAW:}" > "$d/$PROG" ;;
    *)     jq "$shape" "$d/$PROG" > "$d/p.tmp" && mv "$d/p.tmp" "$d/$PROG" ;;
  esac
  before_p="$(_cksum "$d/$PROG")"
  wiz "$d" --set-answer test_command "$NEW_CMD"
  after_p="$(_cksum "$d/$PROG")"
  # Exactly ONE [FAIL] line: the route stops at its own diagnosis and never
  # goes on to attempt the write (MA7 is what a second line looks like).
  local n_fail
  n_fail="$(grep -c -F '[FAIL]' "$d/run.out")"; case "$n_fail" in ''|*[!0-9]*) n_fail=0 ;; esac
  if [ "$WIZ_RC" -eq 1 ] && [ "$before_p" = "$after_p" ] && grep -q -E "$want" "$d/run.out" && ! grep -q -F '[OK]' "$d/run.out" \
     && [ "$n_fail" -eq 1 ]; then
    pass "$id — $label: refused (rc=$WIZ_RC), progress file byte-identical, one refusal line, and it says why"
  else
    fail_ "$id" "$label: rc=$WIZ_RC (want 1); progress $([ "$before_p" = "$after_p" ] && echo unchanged || echo CHANGED); [FAIL] lines=$n_fail (want 1); reason $(grep -q -E "$want" "$d/run.out" && echo given || echo "missing (/$want/)"): $(grep -m1 -E 'FAIL|OK' "$d/run.out" || echo '<none>')"
  fi
}
f_case F1 "answers absent"                        'del(.answers)'                'no usable answers object'
f_case F2 "answers is an ARRAY naming the key"    '.answers = ["test_command"]'  'no usable answers object'
f_case F3 "answers is a STRING equal to the key"  '.answers = "test_command"'    'no usable answers object'
f_case F4 "answers is null"                       '.answers = null'              'no usable answers object'
f_case F5 "the progress file is not JSON"         'RAW:{ "answers": { "test_command": ' 'could not read'

echo "=== I — shell-special and jq-special keys cannot inject ==="

# I1 — hostile keys that are NOT recorded: refused, nothing written, and no
# payload ran (each would create a PWNED file under $TOPTMP).
I1="$(newtmp)/proj"
if ! mk_adopted "$I1"; then
  fail_ "I1 setup" "could not build the fixture"
else
  before_p="$(_cksum "$I1/$PROG")"; bad=""
  for hk in \
    'x$(touch PWNED_a)' \
    'x`touch PWNED_b`' \
    'x"; touch PWNED_c; "' \
    "x'; touch PWNED_d; '" \
    'x"]|= (input_filename | halt_error) | .["' \
    "x' in answers or __import__('os').system('touch PWNED_e') or '" \
    "x\$(touch $TOPTMP/PWNED_f)" \
    '-n' \
    '$key' ; do
    wiz "$I1" --set-answer "$hk" "v"
    [ "$WIZ_RC" -eq 1 ] || bad="$bad [rc=$WIZ_RC for $hk]"
    [ "$(_cksum "$I1/$PROG")" = "$before_p" ] || bad="$bad [progress CHANGED by $hk]"
  done
  pw="$(_pwned)"
  if [ -z "$bad" ] && [ -z "$pw" ]; then
    pass "I1 (control) — nine hostile unrecorded keys are each refused (rc=1), nothing written, no payload ran"
  else
    fail_ "I1 (control)" "${bad:-no rc/cksum fault}; payload file: ${pw:-none}"
  fi
fi

# I2 — a recorded key that carries shell- and jq-special characters is
# matched EXACTLY and written under exactly that key: no sibling changes, no
# new key appears, `$HOME` stays literal.
I2="$(newtmp)/proj"
if ! mk_adopted "$I2"; then
  fail_ "I2 setup" "could not build the fixture"
else
  others_before="$(others_sum "$I2" "$ODD_KEY")"; n_before="$(jq -r '.answers | length' "$I2/$PROG")"
  wiz "$I2" --set-answer "$ODD_KEY" 'odd-new $(touch PWNED_g)'
  others_after="$(others_sum "$I2" "$ODD_KEY")"; n_after="$(jq -r '.answers | length' "$I2/$PROG")"
  got="$(jq_answer "$ODD_KEY" "$I2")"; pw="$(_pwned)"
  if [ "$WIZ_RC" -eq 0 ] && [ "$got" = 'odd-new $(touch PWNED_g)' ] && [ "$others_before" = "$others_after" ] \
     && [ "$n_before" = "$n_after" ] && [ -z "$pw" ] && [ "$(jq_amend 0 key "$I2")" = "$ODD_KEY" ]; then
    pass "I2 — a recorded key with quote/dollar/bracket/dot characters is amended under exactly that key ($n_after answers before and after), nothing ran"
  else
    fail_ "I2" "rc=$WIZ_RC value=[$got] siblings $([ "$others_before" = "$others_after" ] && echo unchanged || echo CHANGED) answers $n_before->$n_after payload=${pw:-none}"
  fi
fi

echo "=== D3–D5 — a recorded key the table cannot carry raw is rendered ESCAPED ==="

# This route is what makes such keys reachable (I2), so D1's "every accepted
# key is rendered" has to hold for them too (review R-294-5). The value cell
# was already escaped; the key cell was not. One case per character, each
# asserting the exact row AND that the table still has one row per answer.
# d_case <id> <label> <key> <new-value> <expected key cell>
d_case() {
  local id="$1" label="$2" key="$3" val="$4" cell="$5" d day want rows n_ans
  d="$(newtmp)/proj"
  if ! mk_adopted "$d"; then fail_ "$id setup" "could not build the fixture"; return 0; fi
  wiz "$d" --set-answer "$key" "$val"
  day="$(jq -r '.amendments[0].at // "" | .[0:10]' "$d/$PROG" 2>/dev/null)"
  want="| $cell | $val (amended $day) |"
  n_ans="$(jq -r '.answers | length' "$d/$PROG" 2>/dev/null)"
  rows="$(awk '$0 == "### Answers" { t = 1; next } t && /^<!-- INTAKE_ANSWERS_END -->$/ { t = 0 } t && /^\|/ { n++ } END { print n + 0 }' "$d/PROJECT_INTAKE.md")"
  if [ "$WIZ_RC" -eq 0 ] && [ -n "$day" ] && grep -q -F -x -- "$want" "$d/PROJECT_INTAKE.md" && [ "$rows" -eq $((n_ans + 2)) ]; then
    pass "$id — $label: the row reads [$want] and the table has $rows lines for $n_ans answers"
  else
    fail_ "$id" "$label: rc=$WIZ_RC; want row [$want] $(grep -q -F -x -- "$want" "$d/PROJECT_INTAKE.md" && echo present || echo MISSING); table lines=$rows (want $((n_ans + 2)))"
  fi
}
d_case D3 "a PIPE in the key"     "$PIPE_KEY" "p-new" '`pipe\|key`'
d_case D4 "a NEWLINE in the key"  "$NL_KEY"   "n-new" '`line key`'
d_case D5 "a BACKTICK in the key" "$TICK_KEY" "t-new" '`` tick`key ``'

echo "=== M — mutation proofs on a mirror, each located by distance from the BL-301 anchor ==="

ANCHOR='BL-301-ADOPTION-RECORDED-BEGIN'
for mark in "$ANCHOR" BL-301-ADOPTION-RECORDED-END BL-301-ANSWERS-READ BL-301-ANSWERS-IS-OBJECT BL-301-IN-ANSWERS \
            BL-301-NOTE-DEFAULT BL-301-RECORDED-CHECK BL-301-NOTE BL-301-UNUSABLE-REFUSE BL-301-UNREADABLE-REFUSE \
            BL-301-KEY-ESCAPE-PIPE BL-301-KEY-ESCAPE-NEWLINE BL-301-KEY-ESCAPE-TICK; do
  n="$(grep -c "# $mark\$" "$WIZARD" 2>/dev/null)"; case "$n" in ''|*[!0-9]*) n=0 ;; esac
  [ "$n" = "1" ] \
    && pass "M0 — '# $mark' ends exactly one line of intake-wizard.sh" \
    || fail_ "M0" "'# $mark' ends $n lines of intake-wizard.sh (need exactly 1)"
done

_hunk_line() { diff "$1" "$2" 2>/dev/null | grep -m1 -E '^[0-9]+' | sed -E 's/^([0-9]+).*/\1/'; }

# mutate <id> <marker> <expected-distance> <sed-expr> <must-now-match>
# Mirrors scripts/, applies <sed-expr> to the ONE line ending in `# <marker>`,
# and proves where it landed: the marker line sits EXACTLY <expected-distance>
# lines below the BL-301 anchor, the only changed line is that line, the
# result parses, and the mutated text is on it. Sets MUT_TGT; returns 1 (after
# reporting) when any proof fails, so a mutant that landed on another arm can
# never be scored as killed.
MUT_TGT=""
mutate() {
  local id="$1" marker="$2" want_d="$3" expr="$4" now="$5" fw tgt before a_ln m_ln h_ln d
  MUT_TGT=""
  fw="$(newtmp)/fw"
  if ! mkdir -p "$fw" || ! cp -Rp "$REPO_ROOT/scripts" "$fw/"; then fail_setup "$id" "could not mirror scripts/"; return 1; fi
  tgt="$fw/scripts/intake-wizard.sh"; before="$fw/before.sh"; cp "$tgt" "$before"
  a_ln="$(grep -n "# $ANCHOR\$" "$before" | head -1 | cut -d: -f1)"
  m_ln="$(grep -n "# $marker\$" "$before" | head -1 | cut -d: -f1)"
  if [ -z "$a_ln" ] || [ -z "$m_ln" ]; then fail_setup "$id" "anchor or marker '$marker' not found (anchor=$a_ln marker=$m_ln)"; return 1; fi
  d=$((m_ln - a_ln))
  sed -e "${m_ln}${expr}" "$before" > "$tgt"
  h_ln="$(_hunk_line "$before" "$tgt")"
  if [ "$d" -ne "$want_d" ] || ! _syntax_ok "$tgt" || [ "$(_changed_lines "$before" "$tgt")" -ne 2 ] \
     || [ "$h_ln" != "$m_ln" ] || ! sed -n "${m_ln}p" "$tgt" | grep -q -F -- "$now" \
     || ! sed -n "${m_ln}p" "$tgt" | grep -q "# $marker\$"; then
    fail_setup "$id" "the mutation did not land where it must (if the sed no longer matches, the marked line was edited): marker '$marker' is anchor+$d (want anchor+$want_d), hunk at line $h_ln vs marker line $m_ln, changed=$(_changed_lines "$before" "$tgt"), syntax $(_syntax_ok "$tgt" && echo ok || echo BROKEN)"
    return 1
  fi
  MUT_TGT="$tgt"; MUT_D="$d"
  return 0
}

# Distances (lines below `# BL-301-ADOPTION-RECORDED-BEGIN`) are part of the
# proof: if the block is edited, re-measure and update them deliberately.
# The three KEY-ESCAPE markers are in render_intake_file, ABOVE the anchor,
# so their distances are negative.
D_ESC_PIPE=-130
D_ESC_NL=-129
D_ESC_TICK=-128
D_ANSWERS_READ=16
D_UNREADABLE=67
D_IS_OBJECT=17
D_IN_ANSWERS=18
D_NOTE_DEFAULT=49
D_RECORDED_CHECK=51
D_NOTE=53
D_UNUSABLE=63

# MA1 — THE OLD VERDICT REINSTATED: the recorded-key check always says
# "absent". A1's scenario must then be REFUSED; a wizard-owned key still works.
if mutate MA1 BL-301-RECORDED-CHECK "$D_RECORDED_CHECK" 's/^\([[:space:]]*\).*\(  # BL-301-RECORDED-CHECK\)$/\1rec_rc=1\2/' 'rec_rc=1'; then
  PD="$(newtmp)/proj"
  if ! mk_adopted "$PD" "$MUT_TGT"; then fail_setup "MA1" "could not build the mutant's fixture"; else
    wiz "$PD" --set-answer test_command "$NEW_CMD"; rc_a=$WIZ_RC; got_a="$(jq_answer test_command "$PD")"
    wiz "$PD" --set-answer uptime "99.9"; rc_w=$WIZ_RC
    if [ "$rc_a" -eq 1 ] && [ "$got_a" = "$OLD_CMD" ] && [ "$rc_w" -eq 0 ]; then
      pass "MA1 (MUTATION, anchor+$MUT_D) — with the check forced to 'absent' the adoption-recorded key is REFUSED again (rc=$rc_a) while a wizard key still works: A1 is what stops it"
    else
      fail_ "MA1 (MUTATION)" "adoption key rc=$rc_a value=[$got_a]; wizard key rc=$rc_w — the mutation changed nothing A1 can see"
    fi
  fi
fi

# MA2 — THE REFUSAL NEUTERED: the check always says "present". N1's scenario
# must then ACCEPT a key that exists nowhere.
if mutate MA2 BL-301-RECORDED-CHECK "$D_RECORDED_CHECK" 's/^\([[:space:]]*\).*\(  # BL-301-RECORDED-CHECK\)$/\1rec_rc=0\2/' 'rec_rc=0'; then
  PD="$(newtmp)/proj"
  if ! mk_adopted "$PD" "$MUT_TGT"; then fail_setup "MA2" "could not build the mutant's fixture"; else
    wiz "$PD" --set-answer test_commandd "$NEW_CMD"; got="$(jq_answer test_commandd "$PD")"
    if [ "$WIZ_RC" -eq 0 ] && [ "$got" = "$NEW_CMD" ]; then
      pass "MA2 (MUTATION, anchor+$MUT_D) — with the check forced to 'present' a key that exists nowhere is ACCEPTED and minted (rc=$WIZ_RC): N1 is what stops it"
    else
      fail_ "MA2 (MUTATION)" "unknown key rc=$WIZ_RC written=[$got] — the mutation changed nothing N1 can see"
    fi
  fi
fi

# MA3 — THE OBJECT CHECK REMOVED: an `answers` ARRAY that names the key then
# counts as "present" and the route ACCEPTS it. THE VERDICT DOES NOT MOVE, and
# this proof says so rather than implying otherwise: BL-282's own read of the
# old value (`data.get("answers", {}).get(key)`) raises on every non-object
# shape, so the run still ends rc=1 with nothing written. What the object check
# buys is the DIAGNOSIS — "no usable answers object" instead of "could not
# read" — and F2's reason assertion is the only thing that sees it. A mutant
# killed on text alone is a weaker kill than MA1/2/4/5/6's, and is scored as one.
if mutate MA3 BL-301-ANSWERS-IS-OBJECT "$D_IS_OBJECT" 's/if not isinstance(answers, dict):/if False:/' 'if False:'; then
  PD="$(newtmp)/proj"
  if ! mk_adopted "$PD" "$MUT_TGT"; then fail_setup "MA3" "could not build the mutant's fixture"; else
    jq '.answers = ["test_command"]' "$PD/$PROG" > "$PD/p.tmp" && mv "$PD/p.tmp" "$PD/$PROG"
    before_p="$(_cksum "$PD/$PROG")"
    wiz "$PD" --set-answer test_command "$NEW_CMD"
    after_p="$(_cksum "$PD/$PROG")"
    if [ "$WIZ_RC" -eq 1 ] && [ "$before_p" = "$after_p" ] && ! grep -q 'no usable answers object' "$PD/run.out" \
       && grep -q 'could not read' "$PD/run.out"; then
      pass "MA3 (MUTATION, anchor+$MUT_D, DIAGNOSIS-ONLY) — without the object check an answers ARRAY naming the key is accepted by the route and stopped by BL-282's old-value read instead (rc=$WIZ_RC, nothing written, 'could not read'): F2's reason assertion is what sees it; the verdict is held twice"
    else
      fail_ "MA3 (MUTATION)" "rc=$WIZ_RC, progress $([ "$before_p" = "$after_p" ] && echo unchanged || echo CHANGED), reason=[$(grep -m1 -E 'FAIL|OK' "$PD/run.out" || echo '<none>')] — not the diagnosis-only outcome this proof records"
    fi
  fi
fi

# MA4 — THE NOTE DROPPED: the key is accepted but the amendment does not say
# it was adoption-recorded. A3 and A4 are what stop it.
if mutate MA4 BL-301-NOTE "$D_NOTE" 's/adoption_note="[^"]*"/adoption_note=""/' 'adoption_note=""'; then
  PD="$(newtmp)/proj"
  if ! mk_adopted "$PD" "$MUT_TGT"; then fail_setup "MA4" "could not build the mutant's fixture"; else
    wiz "$PD" --set-answer test_command "$NEW_CMD"
    a_note="$(jq_amend 0 note "$PD")"
    if [ "$WIZ_RC" -eq 0 ] && [ "$(jq_answer test_command "$PD")" = "$NEW_CMD" ] && ! printf '%s' "$a_note" | grep -q 'adoption-recorded' \
       && ! grep -F '[OK] test_command' "$PD/run.out" | grep -q 'adoption-recorded'; then
      pass "MA4 (MUTATION, anchor+$MUT_D) — with the note dropped the write still lands (rc=$WIZ_RC) but note=[$a_note] and the [OK] line is silent: A3 and A4 are what stop it"
    else
      fail_ "MA4 (MUTATION)" "rc=$WIZ_RC note=[$a_note] — dropping the note changed nothing A3/A4 can see"
    fi
  fi
fi

# MA5 — THE NOTE ON EVERYTHING: a wizard-owned key's amendment is labelled
# adoption-recorded. R1 is what stops it.
if mutate MA5 BL-301-NOTE-DEFAULT "$D_NOTE_DEFAULT" 's/adoption_note=""/adoption_note="adoption-recorded key"/' 'adoption_note="adoption-recorded key"'; then
  PD="$(newtmp)/proj"
  if ! mk_adopted "$PD" "$MUT_TGT"; then fail_setup "MA5" "could not build the mutant's fixture"; else
    wiz "$PD" --set-answer uptime "99.9"
    shape="$(jq -c '.amendments[0] | keys' "$PD/$PROG" 2>/dev/null)"
    if [ "$WIZ_RC" -eq 0 ] && [ "$shape" != '["at","key","new","old","reason"]' ]; then
      pass "MA5 (MUTATION, anchor+$MUT_D) — with the note defaulted on, a wizard-owned key's amendment becomes $shape: R1 is what stops it"
    else
      fail_ "MA5 (MUTATION)" "rc=$WIZ_RC amendment keys=$shape — defaulting the note changed nothing R1 can see"
    fi
  fi
fi

# MA6 — MEMBERSHIP AGAINST THE WHOLE FILE: `in answers` becomes `in data`, so
# a top-level key (`source`) counts as recorded. N2 is what stops it.
if mutate MA6 BL-301-IN-ANSWERS "$D_IN_ANSWERS" 's/ in answers else / in data else /' ' in data else '; then
  PD="$(newtmp)/proj"
  if ! mk_adopted "$PD" "$MUT_TGT"; then fail_setup "MA6" "could not build the mutant's fixture"; else
    wiz "$PD" --set-answer source "x"
    if [ "$WIZ_RC" -eq 0 ] && [ "$(jq_answer source "$PD")" = "x" ]; then
      pass "MA6 (MUTATION, anchor+$MUT_D) — tested against the whole file, the top-level key 'source' is ACCEPTED and minted into answers/ (rc=$WIZ_RC): N2 is what stops it"
    else
      fail_ "MA6 (MUTATION)" "rc=$WIZ_RC answers.source=[$(jq_answer source "$PD")] — the mutation changed nothing N2 can see"
    fi
  fi
fi

# MA7 — THE FAIL-CLOSED RETURN REMOVED: the unusable-answers arm falls through
# to the write. THE VERDICT NO LONGER MOVES, and this proof says so. Before
# `# BL-282-WRITE-STATUS` the fall-through ended exit 0 with an amendment
# appended and no answer written, and F1's exit code killed this mutant. With
# the write's status checked, the failed write refuses downstream ("could not
# write"), so the run still ends rc=1 with nothing written and the verdict is
# held twice. ON EXIT CODE AND FILE STATE THIS MUTANT IS NOW EQUIVALENT. The
# one observable difference is that the route no longer STOPS at its own
# diagnosis: it prints "no usable answers object", goes on to attempt the
# write, and prints a second refusal. F1's one-refusal-line assertion is what
# sees that — a text-level kill, weaker than MA3's even, and scored as one.
if mutate MA7 BL-301-UNUSABLE-REFUSE "$D_UNUSABLE" 's/^\([[:space:]]*\)return 1\(  # BL-301-UNUSABLE-REFUSE\)$/\1:\2/' ':  # BL-301'; then
  PD="$(newtmp)/proj"
  if ! mk_adopted "$PD" "$MUT_TGT"; then fail_setup "MA7" "could not build the mutant's fixture"; else
    jq 'del(.answers)' "$PD/$PROG" > "$PD/p.tmp" && mv "$PD/p.tmp" "$PD/$PROG"
    before_p="$(_cksum "$PD/$PROG")"
    wiz "$PD" --set-answer test_command "$NEW_CMD"
    after_p="$(_cksum "$PD/$PROG")"
    n_fail="$(grep -c -F '[FAIL]' "$PD/run.out")"; case "$n_fail" in ''|*[!0-9]*) n_fail=0 ;; esac
    if [ "$WIZ_RC" -eq 1 ] && [ "$before_p" = "$after_p" ] && [ "$n_fail" -eq 2 ] \
       && grep -q 'could not write' "$PD/run.out" && ! grep -q -F '[OK]' "$PD/run.out"; then
      pass "MA7 (MUTATION, anchor+$MUT_D, TEXT-ONLY) — with the refusal's return removed an absent answers object falls through to the write and is stopped by BL-282's write-status check (rc=$WIZ_RC, nothing written, $n_fail refusal lines): equivalent on exit code and state; F1's one-refusal-line assertion is what sees it"
    else
      fail_ "MA7 (MUTATION)" "rc=$WIZ_RC, progress $([ "$before_p" = "$after_p" ] && echo unchanged || echo CHANGED), reason=[$(grep -m1 -E 'FAIL|OK' "$PD/run.out" || echo '<none>')] — not the diagnosis-only outcome this proof records"
    fi
  fi
fi

# mint_mutant <id> <marker> <distance> <sed-expr> <must-now-match> <near-miss key> <what it is>
# MA8–MA11 are the review's four survivors (R-294-1): each WIDENS membership
# by one line, each minted a key that exists nowhere with this suite green,
# and each is now stopped by N3. The proof runs the near-miss key through the
# mutant and requires the mint (rc=0, the key written) — so a pass here means
# "this mutant is live and N3's assertion on that key is what catches it".
mint_mutant() {
  local id="$1" marker="$2" dist="$3" expr="$4" now="$5" key="$6" what="$7" pd got
  mutate "$id" "$marker" "$dist" "$expr" "$now" || return 0
  pd="$(newtmp)/proj"
  if ! mk_adopted "$pd" "$MUT_TGT"; then fail_setup "$id" "could not build the mutant's fixture"; return 0; fi
  wiz "$pd" --set-answer "$key" "MINTED"
  got="$(jq_answer "$key" "$pd")"
  if [ "$WIZ_RC" -eq 0 ] && [ "$got" = "MINTED" ]; then
    pass "$id (MUTATION, anchor+$MUT_D) — $what: the near-miss key [$key] is ACCEPTED and minted (rc=$WIZ_RC): N3 is what stops it"
  else
    fail_ "$id (MUTATION)" "$what: key [$key] gave rc=$WIZ_RC written=[$got] — the mutation changed nothing N3 can see"
  fi
}
mint_mutant MA8 BL-301-IN-ANSWERS "$D_IN_ANSWERS" \
  's/sys\.argv\[1\] in answers/sys.argv[1].strip() in answers/' 'sys.argv[1].strip() in answers' \
  'test_command ' "the argument is stripped before the test"
mint_mutant MA9 BL-301-ANSWERS-READ "$D_ANSWERS_READ" \
  's/ else None  # BL-301-ANSWERS-READ$/ else None; answers = dict((p, 1) for k in answers for p in (k, k[:-1])) if isinstance(answers, dict) else answers  # BL-301-ANSWERS-READ/' 'k[:-1]' \
  'test_comman' "every recorded key's prefix counts as recorded"
mint_mutant MA10 BL-301-ANSWERS-READ "$D_ANSWERS_READ" \
  's/ else None  # BL-301-ANSWERS-READ$/ else None; answers = dict((p, 1) for k in answers for p in (k, k.upper())) if isinstance(answers, dict) else answers  # BL-301-ANSWERS-READ/' 'k.upper()' \
  'TEST_COMMAND' "every recorded key's upper-case form counts as recorded"
mint_mutant MA11 BL-301-ANSWERS-READ "$D_ANSWERS_READ" \
  's/ else None  # BL-301-ANSWERS-READ$/ else None; answers = dict([(k, 1) for k in answers] + [(v, 1) for v in answers.values() if isinstance(v, str)]) if isinstance(answers, dict) else answers  # BL-301-ANSWERS-READ/' 'answers.values()' \
  'pnpm' "every recorded string VALUE counts as a recorded key"

# MA12 — THE UNREADABLE-FILE ARM'S RETURN REMOVED (review R-294-2). Like MA7,
# EQUIVALENT ON EXIT CODE AND FILE STATE: the fall-through reaches BL-282's
# old-value read, which cannot parse the file either and refuses. The verdict
# is held twice; the one observable difference is a second refusal line, and
# F5's one-refusal-line assertion is what sees it. A text-only kill.
if mutate MA12 BL-301-UNREADABLE-REFUSE "$D_UNREADABLE" 's/^\([[:space:]]*\)return 1\(  # BL-301-UNREADABLE-REFUSE\)$/\1:\2/' ':  # BL-301'; then
  PD="$(newtmp)/proj"
  if ! mk_adopted "$PD" "$MUT_TGT"; then fail_setup "MA12" "could not build the mutant's fixture"; else
    printf '%s\n' '{ "answers": { "test_command": ' > "$PD/$PROG"
    before_p="$(_cksum "$PD/$PROG")"
    wiz "$PD" --set-answer test_command "$NEW_CMD"
    after_p="$(_cksum "$PD/$PROG")"
    n_fail="$(grep -c -F '[FAIL]' "$PD/run.out")"; case "$n_fail" in ''|*[!0-9]*) n_fail=0 ;; esac
    if [ "$WIZ_RC" -eq 1 ] && [ "$before_p" = "$after_p" ] && [ "$n_fail" -eq 2 ] && ! grep -q -F '[OK]' "$PD/run.out"; then
      pass "MA12 (MUTATION, anchor+$MUT_D, TEXT-ONLY) — with the unreadable arm's return removed a non-JSON file falls through and is refused again by BL-282's old-value read (rc=$WIZ_RC, nothing written, $n_fail refusal lines): equivalent on exit code and state; F5's one-refusal-line assertion is what sees it"
    else
      fail_ "MA12 (MUTATION)" "rc=$WIZ_RC, progress $([ "$before_p" = "$after_p" ] && echo unchanged || echo CHANGED), [FAIL] lines=$n_fail — not the text-only outcome this proof records"
    fi
  fi
fi

# render_mutant <id> <marker> <distance> <sed-expr> <must-now-match> <key> <expected cell> <killer>
# MA13–MA15 remove one key-cell escape each. The amend still lands; the
# exact row D3/D4/D5 asserts is what goes missing.
render_mutant() {
  local id="$1" marker="$2" dist="$3" expr="$4" now="$5" key="$6" cell="$7" killer="$8" pd day want
  mutate "$id" "$marker" "$dist" "$expr" "$now" || return 0
  pd="$(newtmp)/proj"
  if ! mk_adopted "$pd" "$MUT_TGT"; then fail_setup "$id" "could not build the mutant's fixture"; return 0; fi
  wiz "$pd" --set-answer "$key" "x-new"
  day="$(jq -r '.amendments[0].at // "" | .[0:10]' "$pd/$PROG" 2>/dev/null)"
  want="| $cell | x-new (amended $day) |"
  if [ "$WIZ_RC" -eq 0 ] && [ "$(jq_answer "$key" "$pd")" = "x-new" ] && ! grep -q -F -x -- "$want" "$pd/PROJECT_INTAKE.md"; then
    pass "$id (MUTATION, anchor$MUT_D) — with that escape removed the amend still lands (rc=$WIZ_RC) but the row [$want] is no longer rendered: $killer is what stops it"
  else
    fail_ "$id (MUTATION)" "rc=$WIZ_RC; escaped row $(grep -q -F -x -- "$want" "$pd/PROJECT_INTAKE.md" && echo 'STILL PRESENT' || echo missing) — removing the escape changed nothing $killer can see"
  fi
}
render_mutant MA13 BL-301-KEY-ESCAPE-PIPE "$D_ESC_PIPE" 's/gsub("\\\\|"; "\\\\|")/./' '.  # BL-301-KEY-ESCAPE-PIPE' "$PIPE_KEY" '`pipe\|key`' D3
render_mutant MA14 BL-301-KEY-ESCAPE-NEWLINE "$D_ESC_NL" 's/gsub("\\n"; " ")/./' '| .  # BL-301-KEY-ESCAPE-NEWLINE' "$NL_KEY" '`line key`' D4
render_mutant MA15 BL-301-KEY-ESCAPE-TICK "$D_ESC_TICK" 's#max // 0#0#' '| 0) as $n' "$TICK_KEY" '`` tick`key ``' D5

echo ""
if [ "$SETUP_FAILED" -gt 0 ]; then
  echo "NOTE: $SETUP_FAILED of the failures below are mutant SETUP failures — a mutation that could not be"
  echo "      applied where its proof requires (marker moved, line edited, mirror not built). That is the"
  echo "      proof going stale, NOT a behavioural kill and NOT evidence about the wizard."
fi
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] && exit 0
exit 1
