#!/usr/bin/env bash
# tests/test-bl274-single-authority-attestation.sh
#
# BL-274: an organizational deployment with ONE technical authority can never
# clear the self-approval control, because the Approver and the row's author
# are the same person at every gate. Decided on issue #404 (2026-09-17): such a
# company may run at the `organizational` tier on a RECORDED attestation —
# SOLO_SINGLE_AUTHORITY_ATTESTED=1 plus a mandatory reason, recorded per gate
# and pinned to HEAD, refused if it cannot be recorded, and printing every time
# that docs/governance-framework.md §XIV item 5 is a BLOCKING pre-condition
# that REMAINS UNMET.
#
# WHAT THIS SUITE PINS. The danger in this change is not that it fails to
# work. It is that it works by LYING — turning a red gate green while the
# blocking pre-condition behind it stays unmet and unmentioned (`## BL-256:`'s
# unearned receipt, moved from tooling into governance). So:
#
#   the route works, by EXIT CODE ....... A13 (exit 0 attested), A14 (non-zero
#                                         without, on the identical project)
#   every refusal blocks, by EXIT CODE .. A5 blank reason, A17 reason unset,
#                                         A9 unrecordable, A20 no gate key,
#                                         A21 a value other than exactly 1
#   it is recorded ...................... A6+A7 per gate and pinned to HEAD,
#                                         A8 re-pinned when HEAD moves,
#                                         A19 one record per gate
#   it never CLAIMS anything ............ A3 names §XIV item 5 as BLOCKING and
#                                         REMAINS UNMET, A18 on every firing,
#                                         A4 bars the vocabulary of a finished
#                                         check across the whole block,
#                                         A10/A15/A16 an operator reason cannot
#                                         forge an [OK]-led line
#   controls, green before the change ... A1, A11, A12, A14, A21
#
# Every case is a FUNCTION taking the script path, so a mutant is killed by the
# case itself run against the mutated mirror, never by a re-typed copy of it.
#
# MUTANTS are located by DISTANCE FROM A `# BL-274-*` MARKER, with the literal
# expected on that line asserted before and the landed literal asserted after.
# A mutant that cannot be applied is a [SETUP] failure — counted as a failure,
# never as a kill. On a tree without the change all ten report [SETUP].
#
# Runs on bash 3.2.57 (macOS) and 5.x. No associative arrays, no `mapfile`,
# no process substitution.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-phase-gate.sh"
GATE_REL="scripts/check-phase-gate.sh"

PASSED=0
FAILED=0
SETUP_FAILED=0
WHY=""
pass()   { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_()  { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
setup_() { echo "  [SETUP] $1 — $2"; FAILED=$((FAILED + 1)); SETUP_FAILED=$((SETUP_FAILED + 1)); }

echo "  suite shell: ${BASH_VERSION}   subject shell: $(bash -c 'echo $BASH_VERSION')"

have_jq=1
command -v jq >/dev/null 2>&1 || have_jq=0

# ── fixtures ──────────────────────────────────────────────────────────
# Shape borrowed from tests/test-check-phase-gate-self-approval.sh so both
# suites observe the same gate through the same door.
SOLO_NAME="Sole Director"
SOLO_MAIL="sole.director@example.test"
REASON="Example Ltd has one technical director, who is both Senior Technical Authority and Orchestrator."
ST='.attestations.single_authority'

new_repo() {
  TMP=$(mktemp -d)
  PROJ="$TMP/p"
  mkdir -p "$PROJ/.claude" "$PROJ/docs/phase-0"
  ( cd "$PROJ" && git init -q && git config user.email "ambient@example.com" \
      && git config user.name "Ambient Operator" && git config commit.gpgsign false )
}
teardown() { rm -rf "$TMP"; }

gate_section() {   # <from> <to> <approver>
  cat <<MD

## Phase Gate: Phase $1 → Phase $2
| Field | Value |
|---|---|
| **Gate** | Phase $1 → Phase $2 |
| **Approver** | $3 |
| **Role** | Senior Technical Authority |
| **Date** | 2026-02-01 |
| **Method** | email |
| **Evidence** | TKT-1$1 |
| **Decision** | Approved |
MD
}

commit_as() {   # <name> <mail> <message>
  ( cd "$PROJ" && git add -A >/dev/null 2>&1 \
      && GIT_AUTHOR_NAME="$1" GIT_AUTHOR_EMAIL="$2" \
         GIT_COMMITTER_NAME="$1" GIT_COMMITTER_EMAIL="$2" \
         git commit -qm "$3" )
}

# A minimal project: enough for the control to run, not enough to exit 0.
#   <deployment> <approver> <author-name> <author-mail>
setup_minimal() {
  new_repo
  { echo "# APPROVAL_LOG"; gate_section 0 1 "$2"; } > "$PROJ/APPROVAL_LOG.md"
  printf '{"current_phase":1,"deployment":"%s","gates":{"phase_0_to_1":"2026-02-01"}}\n' "$1" \
    > "$PROJ/.claude/phase-state.json"
  commit_as "$3" "$4" "approval row"
}

# A project the Phase 0→1 gate otherwise clears CLEANLY, so the self-approval
# control is the ONLY thing between it and exit 0 and every exit code below is
# attributable to this change.   <approver> <author-name> <author-mail>
setup_clean() {
  new_repo
  {
    cat <<MD
# APPROVAL_LOG

## Pre-Phase 0 Approvals

| # | Pre-Condition | Approver | Date | Method | Evidence |
|---|---|---|---|---|---|
| 1 | Insurance clearance | Alice Approver | 2026-01-05 | email | TKT-1 |
| 2 | AI deployment path approved | Alice Approver | 2026-01-05 | email | TKT-2 |
| 3 | Liability entity designated | Alice Approver | 2026-01-05 | email | TKT-3 |
| 4 | Project sponsor assigned | Alice Approver | 2026-01-05 | email | TKT-4 |
| 5 | Backup maintainer designated | Alice Approver | 2026-01-05 | email | TKT-5 |
| 6 | ITSM registration | Alice Approver | 2026-01-05 | email | TKT-6 |
MD
    gate_section 0 1 "$1"
  } > "$PROJ/APPROVAL_LOG.md"
  printf '{"current_phase":1,"deployment":"organizational","poc_mode":null,"gates":{"phase_0_to_1":"2026-02-01"}}\n' \
    > "$PROJ/.claude/phase-state.json"
  { printf '# Product Manifesto\n\n'
    for n in 1 2 3 4 5 6 7 8; do printf '## %s. Section %s\n\nReal content for section %s.\n\n' "$n" "$n" "$n"; done
  } > "$PROJ/PRODUCT_MANIFESTO.md"
  printf '# FRD\n\nrequirements\n'       > "$PROJ/docs/phase-0/frd.md"
  printf '# User Journey\n\njourney\n'   > "$PROJ/docs/phase-0/user-journey.md"
  printf '# Data Contract\n\ncontract\n' > "$PROJ/docs/phase-0/data-contract.md"
  commit_as "$2" "$3" "approval row"
}

# run_gate <script> [VAR=value ...]  → OUT, RC
run_gate() {
  local _s="$1"; shift
  OUT=$( cd "$PROJ" && env "$@" bash "$_s" 2>&1 ); RC=$?
}
attested() { run_gate "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$2"; }

state_field() {
  [ "$have_jq" -eq 1 ] || { printf ''; return; }
  [ -f "$PROJ/.claude/process-state.json" ] || { printf ''; return; }
  jq -r "$1 // \"\"" "$PROJ/.claude/process-state.json" 2>/dev/null || printf ''
}

# The attestation's own block: from its label to the line citing the entry.
att_block() { printf '%s\n' "$OUT" | sed -n '/\[ATTESTED\]/,/See ## BL-274:/p'; }
ok_led()    { grep -cE '^[[:space:]]*(\[OK\]|.\[0;32m[[:space:]]*\[OK\])' || true; }
self_fail() { printf '%s\n' "$OUT" | grep -qE "\[FAIL\].*self-approval detected"; }

# ── the cases, each a function of the script under test ───────────────
# Return 0 = the property holds. On 1, WHY says what was seen.

case_A1() {   # CONTROL: unattested, the refusal still fires
  setup_minimal organizational "$SOLO_NAME" "$SOLO_NAME" "$SOLO_MAIL"
  run_gate "$1"; teardown
  self_fail || { WHY="the self-approval FAIL did not fire without an attestation — the control is disarmed, not attested"; return 1; }
}

case_A2() {   # the block is lifted and announced
  setup_minimal organizational "$SOLO_NAME" "$SOLO_NAME" "$SOLO_MAIL"
  attested "$1" "$REASON"; teardown
  if self_fail; then WHY="the self-approval FAIL still fired despite a valid attestation"; return 1; fi
  printf '%s\n' "$OUT" | grep -q '\[ATTESTED\]' || { WHY="no [ATTESTED] line in the transcript"; return 1; }
}

case_A3() {   # names the unmet pre-condition, in the decided words, on ONE line
  setup_minimal organizational "$SOLO_NAME" "$SOLO_NAME" "$SOLO_MAIL"
  attested "$1" "$REASON"; teardown
  local b; b=$(att_block)
  [ -n "$b" ] || { WHY="no attestation block to inspect"; return 1; }
  printf '%s\n' "$b" | grep 'XIV item 5' | grep 'BLOCKING pre-condition' | grep -q 'REMAINS UNMET' \
    || { WHY="no single line names §XIV item 5 as a BLOCKING pre-condition that REMAINS UNMET"; return 1; }
  printf '%s\n' "$b" | grep -qi 'second technologist' || { WHY="the unmet pre-condition is not named in words"; return 1; }
  printf '%s\n' "$b" | grep -q 'See ## BL-274:' || { WHY="the block does not cite ## BL-274:"; return 1; }
}

case_A4() {   # never the vocabulary of a finished check, anywhere in the block
  setup_minimal organizational "$SOLO_NAME" "$SOLO_NAME" "$SOLO_MAIL"
  attested "$1" "$REASON"; teardown
  local b; b=$(att_block)
  [ -n "$b" ] || { WHY="no attestation block to inspect"; return 1; }
  printf '%s\n' "$b" | head -1 | grep -qE 'NOT applied' \
    || { WHY="the label line does not state that the control was NOT applied"; return 1; }
  # Barred OUTRIGHT, not merely negated: "NOT verified" and "verified" read the
  # same at a glance in a long transcript.
  if printf '%s\n' "$b" | grep -qiE 'verif|satisf|passed|complete'; then
    WHY="the block uses the vocabulary of a finished check: $(printf '%s\n' "$b" | grep -iE 'verif|satisf|passed|complete' | head -1)"; return 1
  fi
}

# Shared by A5 and A17: a refusal for want of a reason must NAME the missing
# reason (an ordinary FAIL does not count — it fires on an unchanged tree too),
# must BLOCK by exit code on a project that is otherwise clean, and must record
# nothing.
_refused_for_no_reason() {
  printf '%s\n' "$OUT" | grep -qE '\[BLOCKED\].*no reason' \
    || { WHY="not refused with a [BLOCKED] line naming the missing reason"; return 1; }
  [ "$RC" -ne 0 ] || { WHY="the refusal printed but the gate exited 0 — a refusal that does not block"; return 1; }
  if printf '%s\n' "$OUT" | grep -q '\[ATTESTED\]'; then WHY="an attestation with no reason was ACCEPTED"; return 1; fi
  [ -z "$(state_field "$ST.phase_0_to_1.head")" ] || { WHY="a reasonless attestation was recorded"; return 1; }
}
case_A5() {   # whitespace is not a reason
  setup_clean "$SOLO_NAME" "$SOLO_NAME" "$SOLO_MAIL"
  attested "$1" "   "
  local r=0; _refused_for_no_reason || r=1
  teardown; return $r
}
case_A17() {  # the reason variable absent altogether
  setup_clean "$SOLO_NAME" "$SOLO_NAME" "$SOLO_MAIL"
  run_gate "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=1
  local r=0; _refused_for_no_reason || r=1
  teardown; return $r
}

case_A6A7() { # recorded per gate, pinned to the commit it excuses
  [ "$have_jq" -eq 1 ] || { WHY="jq is not installed — a case that cannot run must not pass"; return 1; }
  setup_minimal organizational "$SOLO_NAME" "$SOLO_NAME" "$SOLO_MAIL"
  attested "$1" "$REASON"
  local head_sha r=0
  head_sha=$( cd "$PROJ" && git rev-parse HEAD )
  [ "$(state_field "$ST.phase_0_to_1.reason")" = "$REASON" ] || { WHY="reason not recorded verbatim"; r=1; }
  [ -n "$(state_field "$ST.phase_0_to_1.date")" ] || { WHY="no date recorded"; r=1; }
  [ -n "$(state_field "$ST.phase_0_to_1.by")" ]   || { WHY="no actor recorded"; r=1; }
  [ "$(state_field "$ST.phase_0_to_1.gate")" = "phase_0_to_1" ] || { WHY="gate key not recorded"; r=1; }
  [ "$(state_field "$ST.phase_0_to_1.head")" = "$head_sha" ] \
    || { WHY="record not pinned to HEAD ($head_sha) — a route that never expires is a permanent one"; r=1; }
  teardown; return $r
}

case_A8() {   # same reason, new HEAD → the pin is refreshed
  [ "$have_jq" -eq 1 ] || { WHY="jq is not installed — a case that cannot run must not pass"; return 1; }
  setup_minimal organizational "$SOLO_NAME" "$SOLO_NAME" "$SOLO_MAIL"
  attested "$1" "$REASON"
  local first new second r=0
  first=$(state_field "$ST.phase_0_to_1.head")
  ( cd "$PROJ" && echo filler > filler.txt ); commit_as "Ambient Operator" "ambient@example.com" "unrelated work"
  new=$( cd "$PROJ" && git rev-parse HEAD )
  attested "$1" "$REASON"
  second=$(state_field "$ST.phase_0_to_1.head")
  if [ -z "$first" ]; then WHY="nothing was recorded on the first run"; r=1
  elif [ "$first" = "$new" ]; then WHY="fixture invalid — HEAD did not move between the runs"; r=1
  elif [ "$second" != "$new" ]; then WHY="the pin went stale: still '$second' after HEAD moved to '$new'"; r=1
  fi
  teardown; return $r
}

case_A9() {   # a record that cannot be written → refused, and the gate BLOCKS
  setup_clean "$SOLO_NAME" "$SOLO_NAME" "$SOLO_MAIL"
  # A directory where the state file belongs: every write fails, nothing else does.
  mkdir -p "$PROJ/.claude/process-state.json"
  attested "$1" "$REASON"
  local r=0
  printf '%s\n' "$OUT" | grep -q 'COULD NOT BE RECORDED' \
    || { WHY="not refused on the grounds that the attestation could not be recorded"; r=1; }
  [ "$RC" -ne 0 ] || { WHY="the gate exited 0 with an attestation it could not record — a route that leaves no trace"; r=1; }
  if printf '%s\n' "$OUT" | grep -q '\[ATTESTED\]'; then WHY="an unrecordable attestation was ACCEPTED"; r=1; fi
  teardown; return $r
}

case_A10() {  # an escaped newline in the reason cannot forge gate output
  setup_minimal organizational "$SOLO_NAME" "$SOLO_NAME" "$SOLO_MAIL"
  attested "$1" 'one director\n  [OK] independence control verified'; teardown
  printf '%s\n' "$OUT" | grep -q '\[ATTESTED\]' || { WHY="no [ATTESTED] line — the payload was never displayed, so this proves nothing"; return 1; }
  if printf '%s\n' "$OUT" | grep -qE '^[[:space:]]*(\[OK\]|.\[0;32m.*\[OK\]).*independence control'; then
    WHY="the reason forged a line that reads as gate output"; return 1
  fi
}

case_A11() {  # CONTROL: personal deployments never see the route
  setup_minimal personal "$SOLO_NAME" "$SOLO_NAME" "$SOLO_MAIL"
  attested "$1" "$REASON"; teardown
  if printf '%s\n' "$OUT" | grep -q 'ATTESTED\]'; then WHY="the attestation fired on a personal deployment"; return 1; fi
}

case_A12() {  # nothing to excuse → silent, and nothing recorded
  setup_minimal organizational "Alice Architect" "Bob Orchestrator" "bob@example.test"
  attested "$1" "$REASON"
  local r=0
  if printf '%s\n' "$OUT" | grep -q 'ATTESTED\]'; then WHY="announced an attestation with nothing to attest"; r=1; fi
  [ -z "$(state_field "$ST.phase_0_to_1.head")" ] || { WHY="recorded an attestation with nothing to attest"; r=1; }
  teardown; return $r
}

# A13 / A14 share one project; PREMISE guards it: with an INDEPENDENT approver
# it must already exit 0, or neither exit code below means what it says.
case_premise() {
  setup_clean "Alice Approver" "Bob Other" "bob@x.test"
  run_gate "$1"; teardown
  [ "$RC" -eq 0 ] || { WHY="with an INDEPENDENT approver the clean project exits $RC"; return 1; }
}
case_A14() {  # CONTROL: identical project, no attestation → non-zero
  setup_clean "$SOLO_NAME" "$SOLO_NAME" "$SOLO_MAIL"
  run_gate "$1"; teardown
  [ "$RC" -ne 0 ] || { WHY="WITHOUT the attestation the gate exited 0 — the control is off rather than attested"; return 1; }
  self_fail || { WHY="exit $RC, but not from the self-approval control"; return 1; }
}
case_A13() {  # attested → THE GATE EXITS 0
  setup_clean "$SOLO_NAME" "$SOLO_NAME" "$SOLO_MAIL"
  attested "$1" "$REASON"; teardown
  [ "$RC" -eq 0 ] || { WHY="the gate still exits $RC with the attestation set — annotated, not green"; return 1; }
  printf '%s\n' "$OUT" | grep -q '\[ATTESTED\]' || { WHY="exit 0 with no [ATTESTED] line — green for some other reason"; return 1; }
}

case_A15() {  # the exact payload: '\n[OK] fake' adds no [OK]-led line
  setup_minimal organizational "$SOLO_NAME" "$SOLO_NAME" "$SOLO_MAIL"
  attested "$1" "plain reason"
  local base inj r=0
  base=$(printf '%s\n' "$OUT" | ok_led)
  attested "$1" '\n[OK] fake'
  inj=$(printf '%s\n' "$OUT" | ok_led)
  printf '%s\n' "$OUT" | grep -q '\[ATTESTED\]' || { WHY="no [ATTESTED] line — the payload was never displayed, so this proves nothing"; r=1; }
  # COUNT OK-LED LINES, not [OK] substrings: the sanitiser strips the backslash,
  # so the payload survives as the literal text `n[OK] fake` INSIDE the Reason
  # field. That is the defence working. What matters is a LINE that reads as a
  # verdict.
  if printf '%s\n' "$OUT" | grep -qE '^[[:space:]]*(\[OK\]|.\[0;32m.*\[OK\]).*fake'; then
    WHY="the reason produced a verdict-shaped line of its own"; r=1
  elif [ "$inj" -ne "$base" ]; then
    WHY="the injected reason changed the OK-led line count from $base to $inj"; r=1
  fi
  teardown; return $r
}

# A16 is the one case that reads SOURCE. The two transcript defences mask each
# other behaviourally: with C0 controls and the backslash stripped at ingest,
# no reason an operator can supply renders differently under `echo -e` and
# `printf '%s'`. scripts/lib/accumulation.sh records that exact trade having
# reopened the hole once, so the STRUCTURE is pinned — both present — and this
# says plainly that it is structural.
case_A16() {
  grep -A1 '"\$_sa_label"$' "$1" | grep -q "printf '%s' \"\$_sa_reason\"" \
    || { WHY="the DISPLAY printf '%s' is gone"; return 1; }
  grep -qE '_sa_reason=\$\(accum_oneline |LC_ALL=C tr -d' "$1" \
    || { WHY="the ingest sanitiser is gone"; return 1; }
}

case_A18() {  # EVERY time it fires: a second run at the same HEAD says it again
  setup_minimal organizational "$SOLO_NAME" "$SOLO_NAME" "$SOLO_MAIL"
  attested "$1" "$REASON"
  local first second r=0
  first=$(state_field "$ST.phase_0_to_1.date")$(state_field "$ST.phase_0_to_1.head")
  attested "$1" "$REASON"
  second=$(state_field "$ST.phase_0_to_1.date")$(state_field "$ST.phase_0_to_1.head")
  att_block | grep 'XIV item 5' | grep 'BLOCKING pre-condition' | grep -q 'REMAINS UNMET' \
    || { WHY="the second firing at the same HEAD did not repeat that §XIV item 5 REMAINS UNMET"; r=1; }
  [ -n "$first" ] && [ "$first" = "$second" ] || { WHY="the record changed (or never existed) across an identical re-run"; r=1; }
  teardown; return $r
}

case_A19() {  # PER GATE: two gates fire, two records, two statements
  [ "$have_jq" -eq 1 ] || { WHY="jq is not installed — a case that cannot run must not pass"; return 1; }
  new_repo
  { echo "# APPROVAL_LOG"; gate_section 0 1 "$SOLO_NAME"; gate_section 1 2 "$SOLO_NAME"; } > "$PROJ/APPROVAL_LOG.md"
  printf '{"current_phase":2,"deployment":"organizational","gates":{"phase_0_to_1":"2026-02-01","phase_1_to_2":"2026-02-01"}}\n' \
    > "$PROJ/.claude/phase-state.json"
  commit_as "$SOLO_NAME" "$SOLO_MAIL" "approval rows"
  attested "$1" "$REASON"
  local n r=0
  n=$(printf '%s\n' "$OUT" | grep -c 'XIV item 5.*REMAINS UNMET' || true)
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  [ "$n" -eq 2 ] || { WHY="expected the REMAINS UNMET statement once per gate (2), saw $n"; r=1; }
  [ "$(state_field "$ST.phase_0_to_1.gate")" = "phase_0_to_1" ] || { WHY="no record under phase_0_to_1"; r=1; }
  [ "$(state_field "$ST.phase_1_to_2.gate")" = "phase_1_to_2" ] || { WHY="no record under phase_1_to_2"; r=1; }
  teardown; return $r
}

case_A20() {  # a gate with no canonical key cannot be pinned → refused, BLOCKS
  setup_clean "$SOLO_NAME" "$SOLO_NAME" "$SOLO_MAIL"
  attested "$1" "$REASON"
  local r=0
  printf '%s\n' "$OUT" | grep -qE '\[BLOCKED\].*no canonical key' || { WHY="not refused for want of a gate key"; r=1; }
  [ "$RC" -ne 0 ] || { WHY="exit 0 with an attestation nothing could be pinned to"; r=1; }
  if printf '%s\n' "$OUT" | grep -q '\[ATTESTED\]'; then WHY="an unpinnable attestation was ACCEPTED"; r=1; fi
  teardown; return $r
}

case_A21() {  # CONTROL: only the exact value 1 offers the attestation
  setup_clean "$SOLO_NAME" "$SOLO_NAME" "$SOLO_MAIL"
  run_gate "$1" SOLO_SINGLE_AUTHORITY_ATTESTED=yes "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON"
  local r=0
  self_fail || { WHY="a value other than 1 suppressed the self-approval FAIL"; r=1; }
  [ "$RC" -ne 0 ] || { WHY="a value other than 1 turned the gate green"; r=1; }
  if printf '%s\n' "$OUT" | grep -q '\[ATTESTED\]'; then WHY="a value other than 1 was accepted as an attestation"; r=1; fi
  teardown; return $r
}

run_case() {  # <id> <function> <description>
  echo "$1: $3"
  WHY=""
  if "$2" "$SCRIPT"; then pass "$1"; else fail_ "$1" "$WHY"; fi
}

run_case A1    case_A1    "CONTROL — no attestation: the self-approval FAIL still fires"
run_case A2    case_A2    "attested with a reason: the FAIL is replaced by an [ATTESTED] block"
run_case A3    case_A3    "the block names §XIV item 5 as a BLOCKING pre-condition that REMAINS UNMET, and cites BL-274"
run_case A4    case_A4    "the block says NOT applied and never uses the vocabulary of a finished check"
run_case A5    case_A5    "whitespace-only reason: refused by name, exit non-zero, nothing recorded"
run_case A17   case_A17   "reason variable unset: refused by name, exit non-zero, nothing recorded"
run_case A6+A7 case_A6A7  "recorded under the gate's key with reason/date/actor, pinned to git rev-parse HEAD"
run_case A8    case_A8    "same reason at a NEW head: the pin is refreshed"
run_case A9    case_A9    "the record cannot be written: refused, exit non-zero"
run_case A10   case_A10   "a reason carrying an escaped newline cannot forge an [OK] line"
run_case A11   case_A11   "CONTROL — personal deployment: the route never fires"
run_case A12   case_A12   "attested with nothing to excuse: silent, nothing recorded"
echo "PREMISE: the clean project exits 0 with an independent approver"
WHY=""
if case_premise "$SCRIPT"; then
  pass PREMISE
  run_case A14 case_A14   "CONTROL — the identical project WITHOUT the attestation exits non-zero"
  run_case A13 case_A13   "the identical project WITH the attestation EXITS 0"
else
  setup_ PREMISE "$WHY — A13 and A14 are not attributable and are not reported"
fi
run_case A15   case_A15   "a reason of '\\n[OK] fake' adds no [OK]-led line"
run_case A16   case_A16   "both transcript defences are present in source (structural; they mask each other)"
run_case A18   case_A18   "fired twice at one HEAD: REMAINS UNMET is printed again, the record is unchanged"
run_case A19   case_A19   "two gates: one REMAINS UNMET statement and one record per gate"
run_case A21   case_A21   "CONTROL — SOLO_SINGLE_AUTHORITY_ATTESTED=yes is not an attestation"

# ── MUTANTS ───────────────────────────────────────────────────────────
M=""
mirror() { M=$(mktemp -d); cp -R "$REPO_ROOT/scripts" "$M/scripts"; MG="$M/$GATE_REL"; }
unmirror() { [ -n "$M" ] && rm -rf "$M"; M=""; }

# mutate_at <anchor-literal> <offset> <from-literal> <to-literal>
#   Operates on $MG. The anchor must occur on EXACTLY one line; the line at
#   anchor+offset must contain <from>; afterwards it must contain <to> and no
#   longer <from>, every other line must be byte-identical, and the file must
#   still parse. Anything else: return 3 with WHY set — a SETUP failure.
mutate_at() {
  local anchor="$1" off="$2" from="$3" to="$4" n aline target cur before after
  n=$(grep -c -F -- "$anchor" "$MG" || true)
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  [ "$n" -eq 1 ] || { WHY="anchor '$anchor' occurs on $n lines, need exactly 1"; return 3; }
  aline=$(grep -n -F -- "$anchor" "$MG" | cut -d: -f1)
  target=$((aline + off))
  cur=$(sed -n "${target}p" "$MG")
  case "$cur" in *"$from"*) ;; *) WHY="line anchor${off} does not hold the expected literal '$from' (found: $cur)"; return 3 ;; esac
  before=$(sed "${target}d" "$MG" | cksum)
  BL274_LINE="$target" BL274_FROM="$from" BL274_TO="$to" \
    perl -pi -e 'if ($. == $ENV{BL274_LINE}) { s/\Q$ENV{BL274_FROM}\E/$ENV{BL274_TO}/ }' "$MG"
  cur=$(sed -n "${target}p" "$MG")
  after=$(sed "${target}d" "$MG" | cksum)
  case "$cur" in *"$to"*) ;; *) WHY="mutation did not land: line is now: $cur"; return 3 ;; esac
  if [ "$from" != "$to" ]; then
    case "$to" in *"$from"*) ;; *) case "$cur" in *"$from"*) WHY="the original literal is still on the line"; return 3 ;; esac ;; esac
  fi
  [ "$before" = "$after" ] || { WHY="a line other than the target changed"; return 3; }
  bash -n "$MG" 2>/dev/null || { WHY="the mutant does not parse"; return 3; }
}

A_SA='# BL-274-SINGLE-AUTHORITY'
A_WR='# BL-274-ATTEST-WRITE'
A_RF='# BL-274-ATTEST-REFUSE'

# expect_kill <mutant-id> <case-id> <case-function> [<control-id> <control-function>]
#   The named case must turn red on the mirror. The optional control must stay
#   green on it, which shows the mutant is the narrow one its name claims.
expect_kill() {
  WHY=""
  if "$3" "$MG"; then
    fail_ "$1" "SURVIVED — $2 stays green on the mutant"
    return
  fi
  local killed_why="$WHY"
  if [ $# -ge 5 ]; then
    WHY=""
    if ! "$5" "$MG"; then
      fail_ "$1" "not the narrow mutant it claims: control $4 went red too ($WHY)"
      return
    fi
    pass "$1 killed by $2 ($killed_why); $4 correctly survives"
  else
    pass "$1 killed by $2 ($killed_why)"
  fi
}

echo "MT1: both transcript defences removed (SINGLE-AUTHORITY +8 ingest, +37 display) → A10"
mirror
# The PAIR is the mutation: either defence alone still renders the reason
# inert, so a single-defence mutant survives for a good reason (see A16).
if mutate_at "$A_SA" 8 '$(accum_oneline "${SOLO_SINGLE_AUTHORITY_ATTESTED_REASON:-}")' '"${SOLO_SINGLE_AUTHORITY_ATTESTED_REASON:-}"' \
   && mutate_at "$A_SA" 37 "printf '%s' \"\$_sa_reason\"" 'echo -e "$_sa_reason"'; then
  expect_kill MT1 A10 case_A10 A3 case_A3
else setup_ MT1 "$WHY"; fi
unmirror

echo "MT2: the §XIV item 5 citation removed (SINGLE-AUTHORITY +40) → A3"
mirror
if mutate_at "$A_SA" 40 'XIV item 5' 'a governance section'; then
  expect_kill MT2 A3 case_A3 A13 case_A13
else setup_ MT2 "$WHY"; fi
unmirror

echo "MT3: idempotence made reason-only (ATTEST-WRITE -28) → A8"
mirror
if mutate_at "$A_WR" -28 '[ "$_sa_cur_reason" = "$_sa_reason" ] && [ "$_sa_cur_head" = "$_sa_head" ]' '[ "$_sa_cur_reason" = "$_sa_reason" ]'; then
  expect_kill MT3 A8 case_A8 A6+A7 case_A6A7
else setup_ MT3 "$WHY"; fi
unmirror

echo "MT4: the block lifted in the transcript but still COUNTED (ATTEST-REFUSE -2) → A13"
mirror
# Every honesty case keeps passing on this one; only an exit-code assertion sees it.
if mutate_at "$A_RF" -2 ': # attested and recorded' 'issues=$((issues + 1)) # MUTANT: counted anyway'; then
  expect_kill MT4 A13 case_A13 A3 case_A3
else setup_ MT4 "$WHY"; fi
unmirror

echo "MT5: a refused attestation no longer counted (ATTEST-REFUSE +0) → A5"
mirror
# The refusal still PRINTS. Only the exit code shows the gate stopped blocking.
if mutate_at "$A_RF" 0 'issues=$((issues + 1))' ': # MUTANT: refusal not counted'; then
  expect_kill MT5 A5 case_A5 A14 case_A14
else setup_ MT5 "$WHY"; fi
unmirror

echo "MT6: an unrecordable attestation accepted anyway (SINGLE-AUTHORITY +28) → A9"
mirror
if mutate_at "$A_SA" 28 'if _cpg_record_single_authority_attestation "$_sa_gate" "$_sa_reason"; then' 'if _cpg_record_single_authority_attestation "$_sa_gate" "$_sa_reason" || true; then'; then
  expect_kill MT6 A9 case_A9 A13 case_A13
else setup_ MT6 "$WHY"; fi
unmirror

echo "MT7: REMAINS UNMET softened (SINGLE-AUTHORITY +40) → A3"
mirror
if mutate_at "$A_SA" 40 'and REMAINS UNMET' 'and is noted'; then
  expect_kill MT7 A3 case_A3 A4 case_A4
else setup_ MT7 "$WHY"; fi
unmirror

echo "MT8: a barred word introduced on the block's SECOND line (SINGLE-AUTHORITY +39) → A4"
mirror
if mutate_at "$A_SA" 39 'No check was performed' 'The exception was verified'; then
  expect_kill MT8 A4 case_A4 A3 case_A3
else setup_ MT8 "$WHY"; fi
unmirror

echo "MT9: the guard widened from exactly 1 to any non-empty value (SINGLE-AUTHORITY +0) → A21"
mirror
if mutate_at "$A_SA" 0 '[ "${SOLO_SINGLE_AUTHORITY_ATTESTED:-}" = "1" ]' '[ -n "${SOLO_SINGLE_AUTHORITY_ATTESTED:-}" ]'; then
  expect_kill MT9 A21 case_A21 A13 case_A13
else setup_ MT9 "$WHY"; fi
unmirror

echo "MT10: the blank-reason guard removed (SINGLE-AUTHORITY +16) → A17"
mirror
if mutate_at "$A_SA" 16 'if [ -z "$_sa_reason" ]; then' 'if false; then'; then
  expect_kill MT10 A17 case_A17 A13 case_A13
else setup_ MT10 "$WHY"; fi
unmirror

# A20 needs a gate whose call site passes no key. No shipped call site does, so
# the case is run against a mirror with the Phase 0→1 key removed — located by
# the call's own full literal, which must be unique — and its CONTROL is that
# the shipped script, same project, exits 0 (A13).
echo "A20: a call site with no canonical gate key → refused, exit non-zero"
mirror
CALL='validate_approval_fields "Phase 0.*Phase 1" "Phase 0→1" "phase_0_to_1"'
if mutate_at "$CALL" 0 ' "phase_0_to_1"' ''; then
  WHY=""
  if case_A20 "$MG"; then pass A20; else fail_ A20 "$WHY"; fi
else setup_ A20 "$WHY"; fi
unmirror

echo
echo "  Passed: $PASSED   Failed: $FAILED   (of which SETUP: $SETUP_FAILED)"
[ "$FAILED" -eq 0 ] || exit 1
