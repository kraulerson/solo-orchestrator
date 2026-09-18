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
#                                         A9 unrecordable path, A22 no jq on
#                                         PATH, A23 read-only state file,
#                                         A20 no gate key, A21 a value other
#                                         than exactly 1
#   it is recorded ...................... A6+A7 per gate and pinned to HEAD,
#                                         with the SANITISED reason,
#                                         A8 re-pinned when HEAD moves,
#                                         A19 one record per gate
#   it never CLAIMS anything ............ A3 names §XIV item 5 as BLOCKING and
#                                         REMAINS UNMET, A18 on every firing,
#                                         A4 bars the vocabulary of a finished
#                                         check across the whole block AND any
#                                         [OK]/[PASS]-led line of the code's
#                                         own about the attestation,
#                                         A10/A15/A16 an operator reason cannot
#                                         forge an [OK]-led line
#   controls, green before the change ... A1, A11, A12, A14, A21
#
# The record is an audit trail and an idempotence key. Nothing reads the head
# pin back to decide anything: the attestation must be supplied on every
# invocation, and a run without it refuses exactly as before (A1, A14).
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

# The attestation's own block: from its label to the line citing the entry,
# PLUS the line after it, so a receipt appended to the block is inside the
# window a case inspects (RV1 in the pre-merge review appended one and the
# earlier window, which ended at the citation, never saw it).
att_block() {
  printf '%s\n' "$OUT" | awk '/\[ATTESTED\]/{f=1} f{print; if (done) exit} f && /See ## BL-274:/{done=1}'
}
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
  # No verdict LABEL of the code's own either. `[ATTESTED]` is the block's
  # label; an `[OK]`- or `[PASS]`-led line inside it, or anywhere in the
  # transcript about the attestation, is `## BL-256:`'s receipt for a check
  # that never happened, printed by the mechanism rather than the operator.
  if printf '%s\n' "$b" | grep -qE '^[[:space:]]*(.\[[0-9;]*m)?[[:space:]]*\[(OK|PASS)\]'; then
    WHY="the block carries a verdict-labelled line: $(printf '%s\n' "$b" | grep -E '\[(OK|PASS)\]' | head -1)"; return 1
  fi
  if printf '%s\n' "$OUT" | grep -E '^[[:space:]]*(.\[[0-9;]*m)?[[:space:]]*\[(OK|PASS)\]' | grep -qiE 'attest|single-authority'; then
    WHY="an [OK]/[PASS]-led line about the attestation appears in the transcript: $(printf '%s\n' "$OUT" | grep -E '\[(OK|PASS)\]' | grep -iE 'attest|single-authority' | head -1)"; return 1
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

# The reason supplied carries a tab and a backslash-n; what must be recorded is
# the SANITISED text, the same bytes the transcript shows. Recording the raw
# variable instead is `accum_oneline`'s "a stored value reaches the transcript"
# class waiting for a reader.
DIRTY_REASON=$'Example Ltd has one\ttechnical director\\n who is both STA and Orchestrator.'
CLEAN_REASON=$(printf '%s' "$DIRTY_REASON" | LC_ALL=C tr -d '\000-\037\\')
case_A6A7() { # recorded per gate, pinned to the commit it excuses, sanitised
  [ "$have_jq" -eq 1 ] || { WHY="jq is not installed — a case that cannot run must not pass"; return 1; }
  [ "$DIRTY_REASON" != "$CLEAN_REASON" ] || { WHY="fixture invalid — the dirty reason has nothing to strip"; return 1; }
  setup_minimal organizational "$SOLO_NAME" "$SOLO_NAME" "$SOLO_MAIL"
  attested "$1" "$DIRTY_REASON"
  local head_sha r=0
  head_sha=$( cd "$PROJ" && git rev-parse HEAD )
  [ "$(state_field "$ST.phase_0_to_1.reason")" = "$CLEAN_REASON" ] || { WHY="the recorded reason is not the sanitised text (got: $(state_field "$ST.phase_0_to_1.reason" | od -c | head -2 | tr -s ' ' | tr '\n' ' '))"; r=1; }
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

# A PATH that mirrors the real one minus jq, built once. An allow-list of "the
# tools the gate needs" is a guess; excluding the one tool under test is a fact
# (the shape `tests/test-bl233-wpb-accumulation.sh` A6 arrived at).
NOJQ=""
build_nojq() {
  [ -z "$NOJQ" ] || return 0
  NOJQ=$(mktemp -d)/bin; mkdir -p "$NOJQ"
  local _ifs="$IFS" _p _x _n
  IFS=:
  for _p in $PATH; do
    IFS="$_ifs"
    if [ -d "$_p" ]; then
      for _x in "$_p"/*; do
        [ -x "$_x" ] || continue
        _n="${_x##*/}"
        [ "$_n" = "jq" ] && continue
        [ -e "$NOJQ/$_n" ] && continue
        ln -s "$_x" "$NOJQ/$_n" 2>/dev/null
      done
    fi
    IFS=:
  done
  IFS="$_ifs"
}
case_A22() {  # jq absent → the record cannot be written → refused, BLOCKS
  build_nojq
  if PATH="$NOJQ" command -v jq >/dev/null 2>&1; then WHY="the isolated PATH still resolves jq — the fixture would measure nothing"; return 3; fi
  # PREMISE under the same PATH: an independent approver must still exit 0,
  # or the non-zero below is not attributable to the refusal.
  setup_clean "Alice Approver" "Bob Other" "bob@x.test"
  run_gate "$1" "PATH=$NOJQ"; teardown
  [ "$RC" -eq 0 ] || { WHY="without jq the clean project with an INDEPENDENT approver exits $RC, so the exit code below would not be attributable"; return 3; }
  setup_clean "$SOLO_NAME" "$SOLO_NAME" "$SOLO_MAIL"
  run_gate "$1" "PATH=$NOJQ" SOLO_SINGLE_AUTHORITY_ATTESTED=1 "SOLO_SINGLE_AUTHORITY_ATTESTED_REASON=$REASON"
  local r=0
  printf '%s\n' "$OUT" | grep -q 'COULD NOT BE RECORDED' || { WHY="without jq the attestation was not refused as unrecordable"; r=1; }
  [ "$RC" -ne 0 ] || { WHY="without jq the gate exited 0 — an attestation accepted with no record"; r=1; }
  if printf '%s\n' "$OUT" | grep -q '\[ATTESTED\]'; then WHY="without jq the attestation was ACCEPTED"; r=1; fi
  teardown; return $r
}

case_A23() {  # a read-only state file → refused, BLOCKS, file untouched
  [ "$(id -u)" -ne 0 ] || { WHY="running as root — a read-only file is writable to root, so this case cannot measure"; return 3; }
  setup_clean "$SOLO_NAME" "$SOLO_NAME" "$SOLO_MAIL"
  printf '{"note":"pre-existing"}\n' > "$PROJ/.claude/process-state.json"
  chmod 0444 "$PROJ/.claude/process-state.json"
  local before after r=0
  before=$(cksum < "$PROJ/.claude/process-state.json")
  attested "$1" "$REASON"
  after=$(cksum < "$PROJ/.claude/process-state.json")
  printf '%s\n' "$OUT" | grep -q 'COULD NOT BE RECORDED' || { WHY="a read-only state file was not refused as unrecordable"; r=1; }
  [ "$RC" -ne 0 ] || { WHY="a read-only state file and the gate exited 0"; r=1; }
  if printf '%s\n' "$OUT" | grep -q '\[ATTESTED\]'; then WHY="the attestation was ACCEPTED over a read-only state file"; r=1; fi
  [ "$before" = "$after" ] || { WHY="the read-only state file was replaced"; r=1; }
  chmod 0644 "$PROJ/.claude/process-state.json" 2>/dev/null
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
  local rc=0
  echo "$1: $3"
  WHY=""
  "$2" "$SCRIPT" || rc=$?
  case "$rc" in 0) pass "$1" ;; 3) setup_ "$1" "$WHY" ;; *) fail_ "$1" "$WHY" ;; esac
}

run_case A1    case_A1    "CONTROL — no attestation: the self-approval FAIL still fires"
run_case A2    case_A2    "attested with a reason: the FAIL is replaced by an [ATTESTED] block"
run_case A3    case_A3    "the block names §XIV item 5 as a BLOCKING pre-condition that REMAINS UNMET, and cites BL-274"
run_case A4    case_A4    "the block says NOT applied and never uses the vocabulary of a finished check"
run_case A5    case_A5    "whitespace-only reason: refused by name, exit non-zero, nothing recorded"
run_case A17   case_A17   "reason variable unset: refused by name, exit non-zero, nothing recorded"
run_case A6+A7 case_A6A7  "recorded under the gate's key with the SANITISED reason, date, actor, pinned to git rev-parse HEAD"
run_case A8    case_A8    "same reason at a NEW head: the pin is refreshed"
run_case A9    case_A9    "the record cannot be written: refused, exit non-zero"
run_case A22   case_A22   "jq absent from PATH: refused as unrecordable, exit non-zero, no [ATTESTED]"
run_case A23   case_A23   "read-only state file: refused as unrecordable, exit non-zero, file untouched"
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

# insert_after <anchor-literal> <offset> <expected-literal> <new-line>
#   Same contract as mutate_at, for a mutation that ADDS a line: the target
#   line must hold <expected>, the file must grow by exactly one line, the new
#   line must sit at target+1, and the file must still parse.
insert_after() {
  local anchor="$1" off="$2" expect="$3" newline="$4" n aline target cur n1 n2
  n=$(grep -c -F -- "$anchor" "$MG" || true)
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  [ "$n" -eq 1 ] || { WHY="anchor '$anchor' occurs on $n lines, need exactly 1"; return 3; }
  aline=$(grep -n -F -- "$anchor" "$MG" | cut -d: -f1)
  target=$((aline + off))
  cur=$(sed -n "${target}p" "$MG")
  case "$cur" in *"$expect"*) ;; *) WHY="line anchor${off} does not hold the expected literal '$expect' (found: $cur)"; return 3 ;; esac
  n1=$(wc -l < "$MG")
  BL274_LINE="$target" BL274_NEW="$newline" \
    perl -pi -e 'if ($. == $ENV{BL274_LINE}) { $_ .= $ENV{BL274_NEW} . "\n" }' "$MG"
  n2=$(wc -l < "$MG")
  [ "$((n1 + 1))" -eq "$n2" ] || { WHY="line count moved by $((n2 - n1)), not 1"; return 3; }
  [ "$(sed -n "$((target + 1))p" "$MG")" = "$newline" ] || { WHY="the inserted line is not at target+1"; return 3; }
  bash -n "$MG" 2>/dev/null || { WHY="the mutant does not parse"; return 3; }
}

A_SA='# BL-274-SINGLE-AUTHORITY'
A_WR='# BL-274-ATTEST-WRITE'
A_RF='# BL-274-ATTEST-REFUSE'

# expect_kill <mutant-id> <case-id> <case-function> [<control-id> <control-function>]
#   The named case must turn red on the mirror. The optional control must stay
#   green on it, which shows the mutant is the narrow one its name claims.
expect_kill() {
  local rc=0
  WHY=""
  "$3" "$MG" || rc=$?
  if [ "$rc" -eq 0 ]; then
    fail_ "$1" "SURVIVED — $2 stays green on the mutant"
    return
  elif [ "$rc" -eq 3 ]; then
    setup_ "$1" "$2 could not run on the mutant: $WHY"
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

echo "MT3: idempotence made reason-only (ATTEST-WRITE -32) → A8"
mirror
if mutate_at "$A_WR" -32 '[ "$_sa_cur_reason" = "$_sa_reason" ] && [ "$_sa_cur_head" = "$_sa_head" ]' '[ "$_sa_cur_reason" = "$_sa_reason" ]'; then
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

echo "MT11: an [OK]-led receipt of the code's own appended to the block (SINGLE-AUTHORITY +41, insertion) → A4"
mirror
# The pre-merge review's RV1: the block stays word-perfect and a fifth line
# says [OK]. Nothing an operator supplies; the mechanism's own receipt.
if insert_after "$A_SA" 41 'Recorded to .claude/process-state.json' '    echo "  [OK] $_sa_label: single-authority attestation recorded"'; then
  expect_kill MT11 A4 case_A4 A3 case_A3
else setup_ MT11 "$WHY"; fi
unmirror

echo "MT12: the recorder returns 0 instead of 2 when jq is absent (ATTEST-WRITE -59) → A22"
mirror
# The pre-merge review's RV8: with jq absent the recorder would report
# success without writing, and a clean project would exit 0 with no record.
if mutate_at "$A_WR" -59 'command -v jq >/dev/null 2>&1 || return 2' 'command -v jq >/dev/null 2>&1 || return 0'; then
  expect_kill MT12 A22 case_A22 A13 case_A13
else setup_ MT12 "$WHY"; fi
unmirror

echo "MT13: the RAW environment variable recorded instead of the sanitised reason (SINGLE-AUTHORITY +28) → A6+A7"
mirror
# The pre-merge review's RV11.
if mutate_at "$A_SA" 28 'if _cpg_record_single_authority_attestation "$_sa_gate" "$_sa_reason"; then' 'if _cpg_record_single_authority_attestation "$_sa_gate" "$SOLO_SINGLE_AUTHORITY_ATTESTED_REASON"; then'; then
  expect_kill MT13 A6+A7 case_A6A7 A13 case_A13
else setup_ MT13 "$WHY"; fi
unmirror

echo "MT14: the read-only guard on the state file removed (ATTEST-WRITE -53) → A23"
mirror
if mutate_at "$A_WR" -53 '[ -w "$file" ] || return 2' ': # MUTANT: writability not checked'; then
  expect_kill MT14 A23 case_A23 A13 case_A13
else setup_ MT14 "$WHY"; fi
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
