#!/usr/bin/env bash
# tests/test-bl282-set-answer.sh
#
# `## BL-282:` — ONCE A SECTION IS COMPLETE THERE WAS NO ROUTE TO CORRECT A
# RECORDED ANSWER. `--resume` skips completed sections, `reconfigure-project.sh
# --field` knows seven fields, and the wizard's own flag surface had three
# targeted setters and no generic write. Operators hand-edited the JSON, and
# PROJECT_INTAKE.md stayed stale until the next save_section.
#
# The fix is `scripts/intake-wizard.sh --set-answer KEY VALUE [--reason TEXT]`
# (`# BL-282-SET-ANSWER-BEGIN` … `# BL-282-SET-ANSWER-END`): KEY must be one
# the wizard itself records (derived from its own save_answer call sites at
# runtime — `# BL-282-KEY-REFUSE` is the refusal), the progress file must
# already exist, the write goes through save_answer, the amendment is
# appended to an `amendments` array, and PROJECT_INTAKE.md is re-rendered
# (`# BL-282-RERENDER`) with a visible "(amended YYYY-MM-DD)" marker.
#
# Every case drives the REAL wizard from a project fixture with stdin closed.
# On main the flag is unknown and falls through to the non-TTY refusal, so
# every H/K/P/W case is red there for the right reason; C1 and C2 exercise
# flags that already exist and are green at base, which is what proves the
# fixture works and a RED run is the defect, not the harness.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WIZARD="$REPO_ROOT/scripts/intake-wizard.sh"
# The wizard runs under the suite's own interpreter, so a run under
# /bin/bash 3.2 exercises the wizard's `[[ =~ ]]` and `case` under 3.2.
RUN_BASH="${BASH:-bash}"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

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

OLD_BUDGET='3'
NEW_BUDGET='$50-500/month'
CTL_ANSWER='BL282-CONTROL-ANSWER'

# mk_project <dir> [wizard-file] — a project the wizard accepts, with a COPY
# of the wizard and its helpers so nothing here touches the checkout. The
# progress file carries a completed Section 3 with the mis-recorded budget
# from the entry and one untouched control answer.
mk_project() {
  local d="$1" bin="${2:-$WIZARD}"
  mkdir -p "$d/.claude" "$d/scripts/lib" || return 1
  cp "$bin" "$d/scripts/intake-wizard.sh" || return 1
  cp "$REPO_ROOT"/scripts/lib/helpers*.sh "$d/scripts/lib/" 2>/dev/null || return 1
  printf '{"project":"P","current_phase":0,"track":"full","deployment":"personal","poc_mode":null}\n' \
    > "$d/.claude/phase-state.json"
  printf '{}\n' > "$d/.claude/process-state.json"
  cat > "$d/.claude/intake-progress.json" <<PROG
{ "version": 1, "last_section": 4, "completed_sections": [1, 2, 3, 4],
  "project_name": "P", "platform": "web", "track": "full",
  "deployment": "personal", "language": "typescript",
  "description": "f", "poc_mode": null,
  "answers": { "problem_statement": "$CTL_ANSWER", "monthly_budget": "$OLD_BUDGET" } }
PROG
  printf '# Project Intake\n' > "$d/PROJECT_INTAKE.md"
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

jq_answer()   { jq -r --arg k "$1" '.answers[$k] // "<<unset>>"' "$2/.claude/intake-progress.json" 2>/dev/null; }
jq_amend_n()  { jq -r '(.amendments // []) | length' "$1/.claude/intake-progress.json" 2>/dev/null; }
jq_amend()    { jq -r --argjson i "$1" --arg f "$2" '.amendments[$i][$f] // "<<unset>>"' "$3/.claude/intake-progress.json" 2>/dev/null; }
# rendered_row <dir> <key> → the Value cell of that Answers-table row
rendered_row() { awk -F'|' -v k=" \`$2\` " '$2 == k { gsub(/^ +| +$/, "", $3); print $3; exit }' "$1/PROJECT_INTAKE.md"; }
# _hint_count <run.out> → how many keys the "Did you mean:" hint names (0 if none).
_hint_count() {
  local n
  n="$(awk -F'Did you mean: ' '/Did you mean: /{c=split($2, a, /[[:space:]]+/); k=0; for (i = 1; i <= c; i++) if (a[i] != "") k++; print k; exit}' "$1" 2>/dev/null)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s\n' "$n"
}

echo "=== C — controls that hold at base (existing flags, untouched) ==="

# C1 — the three tier-crosscheck-6 setters still write process-state.json.
C1="$(newtmp)/proj"
if ! mk_project "$C1"; then
  fail_ "C1 setup" "could not build the fixture"
else
  wiz "$C1" --data-classification pii --zdr-attested --zdr-attestation-reason "BL282-CTL-REASON"
  got="$(jq -r '[.phase1_artifacts.data_classification, (.phase1_artifacts.zdr_attested|tostring), .phase1_artifacts.zdr_attestation_reason] | join("/")' "$C1/.claude/process-state.json" 2>/dev/null)"
  if [ "$WIZ_RC" -eq 0 ] && [ "$got" = "pii/true/BL282-CTL-REASON" ]; then
    pass "C1 (control) — --data-classification / --zdr-attested / --zdr-attestation-reason still write process-state.json (rc=$WIZ_RC)"
  else
    fail_ "C1 (control)" "rc=$WIZ_RC phase1_artifacts=[$got] — the existing setters changed, or the fixture is broken"
  fi
fi

# C2 — --help still exits 0.
C2="$(newtmp)/proj"
if ! mk_project "$C2"; then
  fail_ "C2 setup" "could not build the fixture"
else
  wiz "$C2" --help
  if [ "$WIZ_RC" -eq 0 ] && grep -q -- '--data-classification VALUE' "$C2/run.out"; then
    pass "C2 (control) — --help exits 0 and still lists the existing setters"
  else
    fail_ "C2 (control)" "rc=$WIZ_RC; --data-classification $(grep -q -- '--data-classification VALUE' "$C2/run.out" && echo listed || echo missing)"
  fi
fi

echo "=== H — the happy path: a recorded answer is corrected, recorded and re-rendered ==="

# H0 — the flag is documented where the maintainer curates the surface.
if [ -d "${C2:-}" ] && grep -q -- '--set-answer KEY VALUE' "$C2/run.out"; then
  pass "H0 — --help lists --set-answer KEY VALUE"
else
  fail_ "H0" "--help does not list --set-answer"
fi

H1="$(newtmp)/proj"
if ! mk_project "$H1"; then
  fail_ "H1 setup" "could not build the fixture"
else
  wiz "$H1" --set-answer monthly_budget "$NEW_BUDGET" --reason "typed the list number, not the range"

  # H1 — exit 0 and the value is written through to answers/.
  got="$(jq_answer monthly_budget "$H1")"
  if [ "$WIZ_RC" -eq 0 ] && [ "$got" = "$NEW_BUDGET" ]; then
    pass "H1 — --set-answer monthly_budget writes the new value (rc=$WIZ_RC)"
  else
    fail_ "H1" "rc=$WIZ_RC answers.monthly_budget=[$got], want [$NEW_BUDGET]: $(tail -2 "$H1/run.out" | tr '\n' ' ')"
  fi

  # H2 — the untouched answer is untouched.
  got="$(jq_answer problem_statement "$H1")"
  if [ "$got" = "$CTL_ANSWER" ]; then
    pass "H2 — the other recorded answer is unchanged"
  else
    fail_ "H2" "problem_statement=[$got], want [$CTL_ANSWER]"
  fi

  # H3 — the amendment is recorded: {key, old, new, reason, at}.
  n="$(jq_amend_n "$H1")"
  a_key="$(jq_amend 0 key "$H1")"; a_old="$(jq_amend 0 old "$H1")"; a_new="$(jq_amend 0 new "$H1")"
  a_reason="$(jq_amend 0 reason "$H1")"; a_at="$(jq_amend 0 at "$H1")"
  if [ "$n" = "1" ] && [ "$a_key" = "monthly_budget" ] && [ "$a_old" = "$OLD_BUDGET" ] && [ "$a_new" = "$NEW_BUDGET" ] \
     && [ "$a_reason" = "typed the list number, not the range" ] \
     && printf '%s' "$a_at" | grep -q -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
    pass "H3 — amendments[0] carries key/old/new/reason and an ISO-8601 UTC timestamp ($a_at)"
  else
    fail_ "H3" "amendments=$n key=[$a_key] old=[$a_old] new=[$a_new] reason=[$a_reason] at=[$a_at]"
  fi

  # H4 — PROJECT_INTAKE.md is re-rendered and the row carries the marker.
  day="$(printf '%s' "$a_at" | cut -c1-10)"
  got="$(rendered_row "$H1" monthly_budget)"
  if [ -n "$day" ] && [ "$got" = "$NEW_BUDGET (amended $day)" ]; then
    pass "H4 — PROJECT_INTAKE.md row reads [$got]"
  else
    fail_ "H4" "rendered monthly_budget row is [$got], want [$NEW_BUDGET (amended $day)]"
  fi

  # H5 — an unamended row carries no marker.
  got="$(rendered_row "$H1" problem_statement)"
  if [ "$got" = "$CTL_ANSWER" ]; then
    pass "H5 — the unamended row renders without a marker"
  else
    fail_ "H5" "rendered problem_statement row is [$got], want [$CTL_ANSWER]"
  fi

  # H6 — the operator-visible line.
  if grep -q -F "[OK] monthly_budget: \"$OLD_BUDGET\" -> \"$NEW_BUDGET\" (amended, recorded)" "$H1/run.out"; then
    pass "H6 — prints [OK] monthly_budget: \"$OLD_BUDGET\" -> \"$NEW_BUDGET\" (amended, recorded)"
  else
    fail_ "H6" "no [OK] line: $(grep -m1 'monthly_budget' "$H1/run.out" || echo '<none>')"
  fi

  # H7 — a second correction APPENDS; the render shows the latest.
  wiz "$H1" --set-answer monthly_budget '$500+/month'
  n="$(jq_amend_n "$H1")"; a_old="$(jq_amend 1 old "$H1")"; a_reason="$(jq_amend 1 reason "$H1")"
  got="$(rendered_row "$H1" monthly_budget)"
  if [ "$WIZ_RC" -eq 0 ] && [ "$n" = "2" ] && [ "$a_old" = "$NEW_BUDGET" ] && [ "$a_reason" = "" ] \
     && [ "$got" = "\$500+/month (amended $day)" ]; then
    pass "H7 — a second correction appends amendments[1] (old=[$a_old], reason empty) and re-renders"
  else
    fail_ "H7" "rc=$WIZ_RC amendments=$n old=[$a_old] reason=[$a_reason] row=[$got]"
  fi
fi

# H8 — a loop-generated key (input_${i}_name) is one the wizard records.
H8="$(newtmp)/proj"
if ! mk_project "$H8"; then
  fail_ "H8 setup" "could not build the fixture"
else
  wiz "$H8" --set-answer input_2_name "Order form"
  got="$(jq_answer input_2_name "$H8")"
  if [ "$WIZ_RC" -eq 0 ] && [ "$got" = "Order form" ]; then
    pass "H8 — a loop-generated key (input_2_name) is accepted (rc=$WIZ_RC)"
  else
    fail_ "H8" "rc=$WIZ_RC input_2_name=[$got]: $(tail -1 "$H8/run.out")"
  fi
fi

# H8N — H8's negative twin: the index is bounded to DIGITS, so a letter in
# its place mints nothing (`# BL-282-INDEX-DIGITS`; MP7 widens it).
H8N="$(newtmp)/proj"
if ! mk_project "$H8N"; then
  fail_ "H8N setup" "could not build the fixture"
else
  before_p="$(_cksum "$H8N/.claude/intake-progress.json")"; bad=""
  # The last two differ from input_1_name only outside the shape, so they
  # pin the `^`…`$` anchors of `# BL-282-FAMILY-WHOLE` directly.
  for nk in input_x_name input_1a_name input_1_namex xinput_1_name; do
    wiz "$H8N" --set-answer "$nk" "minted"
    [ "$WIZ_RC" -eq 1 ] || bad="$bad [rc=$WIZ_RC for $nk]"
  done
  after_p="$(_cksum "$H8N/.claude/intake-progress.json")"
  if [ -z "$bad" ] && [ "$before_p" = "$after_p" ]; then
    pass "H8N — a non-digit index (input_x_name, input_1a_name) and a key outside the shape (input_1_namex, xinput_1_name) are refused (rc=1), file byte-identical"
  else
    fail_ "H8N" "${bad:-rc fine}; file $([ "$before_p" = "$after_p" ] && echo unchanged || echo CHANGED)"
  fi
fi

# H9 — a literal key never answered: old is null, the line says (unset).
H9="$(newtmp)/proj"
if ! mk_project "$H9"; then
  fail_ "H9 setup" "could not build the fixture"
else
  wiz "$H9" --set-answer hard_deadline "2026-12-01"
  got="$(jq_answer hard_deadline "$H9")"; a_old="$(jq -r '.amendments[0].old' "$H9/.claude/intake-progress.json" 2>/dev/null)"
  if [ "$WIZ_RC" -eq 0 ] && [ "$got" = "2026-12-01" ] && [ "$a_old" = "null" ] \
     && grep -q -F '[OK] hard_deadline: (unset) -> "2026-12-01" (amended, recorded)' "$H9/run.out"; then
    pass "H9 — a key with no prior answer records old=null and prints (unset)"
  else
    fail_ "H9" "rc=$WIZ_RC hard_deadline=[$got] old=[$a_old]: $(grep -m1 'hard_deadline' "$H9/run.out" || echo '<none>')"
  fi
fi

echo "=== K — refusals: an unknown key, a missing value ==="

K1="$(newtmp)/proj"
if ! mk_project "$K1"; then
  fail_ "K1 setup" "could not build the fixture"
else
  before_p="$(_cksum "$K1/.claude/intake-progress.json")"; before_i="$(_cksum "$K1/PROJECT_INTAKE.md")"
  wiz "$K1" --set-answer monthly_budgett "$NEW_BUDGET"
  after_p="$(_cksum "$K1/.claude/intake-progress.json")"; after_i="$(_cksum "$K1/PROJECT_INTAKE.md")"
  if [ "$WIZ_RC" -eq 1 ] && grep -q -F 'monthly_budgett' "$K1/run.out" && grep -q -E '(^|[^a-z_])monthly_budget([^a-z_]|$)' "$K1/run.out" \
     && [ "$before_p" = "$after_p" ] && [ "$before_i" = "$after_i" ]; then
    pass "K1 — an unknown key is refused (rc=$WIZ_RC), the hint names monthly_budget, nothing is written"
  else
    fail_ "K1" "rc=$WIZ_RC (want 1); hint $(grep -q -E '(^|[^a-z_])monthly_budget([^a-z_]|$)' "$K1/run.out" && echo present || echo missing); progress $([ "$before_p" = "$after_p" ] && echo unchanged || echo CHANGED); intake $([ "$before_i" = "$after_i" ] && echo unchanged || echo CHANGED)"
  fi
fi

K2="$(newtmp)/proj"
if ! mk_project "$K2"; then
  fail_ "K2 setup" "could not build the fixture"
else
  before_p="$(_cksum "$K2/.claude/intake-progress.json")"
  wiz "$K2" --set-answer monthly_budget
  after_p="$(_cksum "$K2/.claude/intake-progress.json")"
  if [ "$WIZ_RC" -eq 1 ] && grep -q -i 'usage' "$K2/run.out" && [ "$before_p" = "$after_p" ]; then
    pass "K2 — --set-answer without a VALUE is refused (rc=$WIZ_RC) and nothing is written"
  else
    fail_ "K2" "rc=$WIZ_RC (want 1); usage $(grep -q -i usage "$K2/run.out" && echo shown || echo missing); progress $([ "$before_p" = "$after_p" ] && echo unchanged || echo CHANGED)"
  fi
fi

# K3 — the hint names exactly three nearest keys (`# BL-282-HINT-COUNT`).
# Without this the `head -3` was an unasserted constant: MP3 flips it to
# `head -1` and only this count catches it.
K3="$(newtmp)/proj"
if ! mk_project "$K3"; then
  fail_ "K3 setup" "could not build the fixture"
else
  wiz "$K3" --set-answer monthly_budgett "$NEW_BUDGET"
  hint_n="$(_hint_count "$K3/run.out")"
  if [ "$WIZ_RC" -eq 1 ] && [ "$hint_n" -eq 3 ]; then
    pass "K3 — the refusal's hint names exactly three nearest keys"
  else
    fail_ "K3" "rc=$WIZ_RC; hint names $hint_n key(s), want 3: $(grep -m1 'Did you mean' "$K3/run.out" || echo '<no hint>')"
  fi
fi

# K4, K5 — the option parser's two refusals: `--reason` with no value, and
# an argument it does not know. Each prints the usage and writes nothing.
for kc in 'K4|--reason|--reason needs a value' 'K5|--bogus|unexpected argument'; do
  kid="${kc%%|*}"; rest="${kc#*|}"; karg="${rest%%|*}"; kwant="${rest#*|}"
  KD="$(newtmp)/proj"
  if ! mk_project "$KD"; then fail_ "$kid setup" "could not build the fixture"; continue; fi
  before_p="$(_cksum "$KD/.claude/intake-progress.json")"
  wiz "$KD" --set-answer monthly_budget "$NEW_BUDGET" "$karg"
  if [ "$WIZ_RC" -eq 1 ] && grep -q -F -- "$kwant" "$KD/run.out" && grep -q -i 'usage' "$KD/run.out" \
     && [ "$before_p" = "$(_cksum "$KD/.claude/intake-progress.json")" ]; then
    pass "$kid — '$karg' after KEY VALUE is refused (rc=$WIZ_RC) with '$kwant' and the usage; nothing written"
  else
    fail_ "$kid" "rc=$WIZ_RC (want 1); message $(grep -q -F -- "$kwant" "$KD/run.out" && echo present || echo missing); progress $([ "$before_p" = "$(_cksum "$KD/.claude/intake-progress.json")" ] && echo unchanged || echo CHANGED)"
  fi
done

# H10 — the `--reason=TEXT` spelling records the reason as `--reason TEXT` does.
H10="$(newtmp)/proj"
if ! mk_project "$H10"; then
  fail_ "H10 setup" "could not build the fixture"
else
  wiz "$H10" --set-answer monthly_budget "$NEW_BUDGET" "--reason=typed the list number"
  if [ "$WIZ_RC" -eq 0 ] && [ "$(jq_amend 0 reason "$H10")" = "typed the list number" ]; then
    pass "H10 — --reason=TEXT records amendments[0].reason (rc=$WIZ_RC)"
  else
    fail_ "H10" "rc=$WIZ_RC reason=[$(jq_amend 0 reason "$H10")]"
  fi
fi

echo "=== P — no progress file: refuse, do not create one ==="

P1="$(newtmp)/proj"
if ! mk_project "$P1"; then
  fail_ "P1 setup" "could not build the fixture"
else
  rm -f "$P1/.claude/intake-progress.json"
  wiz "$P1" --set-answer monthly_budget "$NEW_BUDGET"
  if [ "$WIZ_RC" -eq 1 ] && grep -q -i 'run the wizard first' "$P1/run.out" && [ ! -e "$P1/.claude/intake-progress.json" ]; then
    pass "P1 — without intake-progress.json the flag refuses (rc=$WIZ_RC), says to run the wizard first, creates nothing"
  else
    fail_ "P1" "rc=$WIZ_RC (want 1); message $(grep -q -i 'run the wizard first' "$P1/run.out" && echo present || echo missing); file $([ -e "$P1/.claude/intake-progress.json" ] && echo CREATED || echo absent)"
  fi
fi

echo "=== S — a failed write is a refusal, never an [OK] ==="

# mk_project_noanswers <dir> — the fixture from the field: a progress file
# with NO `answers` object at all. The old-value read defaults it to {} and
# succeeds, so only save_answer's own status can catch this.
mk_project_noanswers() {
  local d="$1"
  mk_project "$d" || return 1
  python3 - "$d/.claude/intake-progress.json" <<'PYNA' || return 1
import io, json, sys
p = sys.argv[1]
d = json.load(io.open(p, encoding="utf-8"))
d.pop("answers", None)
io.open(p, "w", encoding="utf-8").write(json.dumps(d, indent=2))
PYNA
  return 0
}

# S1 — answers absent: refuse, write nothing, record nothing, say so.
S1="$(newtmp)/proj"
if ! mk_project_noanswers "$S1"; then
  fail_ "S1 setup" "could not build the no-answers fixture"
else
  before_p="$(_cksum "$S1/.claude/intake-progress.json")"
  wiz "$S1" --set-answer monthly_budget "$NEW_BUDGET"
  after_p="$(_cksum "$S1/.claude/intake-progress.json")"
  n="$(jq_amend_n "$S1")"; case "$n" in ''|*[!0-9]*) n=0 ;; esac
  ok_n="$(grep -c '\[OK\]' "$S1/run.out")"; case "$ok_n" in ''|*[!0-9]*) ok_n=0 ;; esac
  if [ "$WIZ_RC" -ne 0 ] && [ "$n" -eq 0 ] && [ "$before_p" = "$after_p" ] && [ "$ok_n" -eq 0 ] \
     && grep -q -i 'could not write' "$S1/run.out"; then
    pass "S1 — with no answers object the write fails, so --set-answer refuses (rc=$WIZ_RC), appends nothing and leaves the file byte-identical"
  else
    fail_ "S1" "rc=$WIZ_RC (want non-zero); amendments=$n (want 0); file $([ "$before_p" = "$after_p" ] && echo unchanged || echo CHANGED); [OK] lines=$ok_n (want 0); refusal $(grep -q -i 'could not write' "$S1/run.out" && echo present || echo missing)"
  fi
fi

# S2 — answers present but not an object: same refusal, nothing written.
S2="$(newtmp)/proj"
if ! mk_project "$S2"; then
  fail_ "S2 setup" "could not build the fixture"
else
  python3 - "$S2/.claude/intake-progress.json" <<'PYNO' || true
import io, json, sys
p = sys.argv[1]
d = json.load(io.open(p, encoding="utf-8"))
d["answers"] = None
io.open(p, "w", encoding="utf-8").write(json.dumps(d, indent=2))
PYNO
  before_p="$(_cksum "$S2/.claude/intake-progress.json")"
  wiz "$S2" --set-answer monthly_budget "$NEW_BUDGET"
  after_p="$(_cksum "$S2/.claude/intake-progress.json")"
  n="$(jq_amend_n "$S2")"; case "$n" in ''|*[!0-9]*) n=0 ;; esac
  ok_n="$(grep -c '\[OK\]' "$S2/run.out")"; case "$ok_n" in ''|*[!0-9]*) ok_n=0 ;; esac
  if [ "$WIZ_RC" -ne 0 ] && [ "$n" -eq 0 ] && [ "$before_p" = "$after_p" ] && [ "$ok_n" -eq 0 ]; then
    pass "S2 — a non-object answers is refused (rc=$WIZ_RC), nothing appended, file byte-identical"
  else
    fail_ "S2" "rc=$WIZ_RC (want non-zero); amendments=$n (want 0); file $([ "$before_p" = "$after_p" ] && echo unchanged || echo CHANGED); [OK] lines=$ok_n (want 0)"
  fi
fi

# S3 — the write fails for a reason that is not the JSON's shape: a
# read-only progress file. Nothing about `answers` is wrong here, so only
# save_answer's status distinguishes success from failure.
S3="$(newtmp)/proj"
if ! mk_project "$S3"; then
  fail_ "S3 setup" "could not build the fixture"
elif [ "$(id -u)" = "0" ]; then
  echo "  [SKIP] S3 — running as root, a read-only file would still be writable"
else
  chmod 0444 "$S3/.claude/intake-progress.json"
  before_p="$(_cksum "$S3/.claude/intake-progress.json")"
  wiz "$S3" --set-answer monthly_budget "$NEW_BUDGET"
  chmod 0644 "$S3/.claude/intake-progress.json" 2>/dev/null
  after_p="$(_cksum "$S3/.claude/intake-progress.json")"
  ok_n="$(grep -c '\[OK\]' "$S3/run.out")"; case "$ok_n" in ''|*[!0-9]*) ok_n=0 ;; esac
  # The message must match what happened. "answer written but the amendment
  # could not be recorded" would be false here: nothing was written.
  said_written="$(grep -c 'answer written but' "$S3/run.out")"; case "$said_written" in ''|*[!0-9]*) said_written=0 ;; esac
  if [ "$WIZ_RC" -ne 0 ] && [ "$before_p" = "$after_p" ] && [ "$ok_n" -eq 0 ] \
     && grep -q -i 'could not write' "$S3/run.out" && [ "$said_written" -eq 0 ]; then
    pass "S3 — an unwritable progress file is refused (rc=$WIZ_RC), file byte-identical, no [OK], and the message says nothing was recorded rather than claiming the answer was written"
  else
    fail_ "S3" "rc=$WIZ_RC (want non-zero); file $([ "$before_p" = "$after_p" ] && echo unchanged || echo CHANGED); [OK] lines=$ok_n (want 0); refusal $(grep -q -i 'could not write' "$S3/run.out" && echo present || echo missing); false-written-claim=$said_written (want 0)"
  fi
fi

# wiz_paused <dir> <args…> — the real wizard with its pause sentinel already
# present. save_answer returns 0 WITHOUT writing when that file exists, and
# the file is named by the wizard's PID, so the sentinel is created by a
# shell that then `exec`s the wizard under the same PID.
wiz_paused() {
  local d="$1" pid; shift
  ( cd "$d" && "$RUN_BASH" -c 'printf %s "$$" > wiz.pid; : > "/tmp/.solo-intake-pause-$$"; exec "$0" scripts/intake-wizard.sh "$@"' "$RUN_BASH" "$@" ) \
    >"$d/run.raw" 2>&1 </dev/null
  WIZ_RC=$?
  strip_ansi "$d/run.raw" > "$d/run.out"
  pid="$(cat "$d/wiz.pid" 2>/dev/null)"
  case "$pid" in ''|*[!0-9]*) ;; *) rm -f "/tmp/.solo-intake-pause-$pid" ;; esac
  return 0
}

# S4 — a save that returns 0 without writing (`# BL-282-READ-BACK`): the
# answer must read back before an amendment is logged. The unchanged answer
# is what proves the pause engaged; the refusal is what the read-back adds.
S4="$(newtmp)/proj"
if ! mk_project "$S4"; then
  fail_ "S4 setup" "could not build the fixture"
else
  wiz_paused "$S4" --set-answer monthly_budget "$NEW_BUDGET"
  got="$(jq_answer monthly_budget "$S4")"
  n="$(jq_amend_n "$S4")"; case "$n" in ''|*[!0-9]*) n=0 ;; esac
  ok_n="$(grep -c '\[OK\]' "$S4/run.out")"; case "$ok_n" in ''|*[!0-9]*) ok_n=0 ;; esac
  if [ "$WIZ_RC" -eq 1 ] && [ "$got" = "$OLD_BUDGET" ] && [ "$n" -eq 0 ] && [ "$ok_n" -eq 0 ] \
     && grep -q 'does not read back' "$S4/run.out"; then
    pass "S4 — a paused save that wrote nothing is refused (rc=$WIZ_RC): answer still [$got], no amendment, no [OK]"
  else
    fail_ "S4" "rc=$WIZ_RC (want 1); monthly_budget=[$got] (want [$OLD_BUDGET]); amendments=$n (want 0); [OK] lines=$ok_n (want 0); refusal $(grep -q 'does not read back' "$S4/run.out" && echo present || echo missing)"
  fi
fi

# ok_lines <dir> → how many [OK] lines the run printed.
ok_lines() { local n; n="$(grep -c '\[OK\]' "$1/run.out")"; case "$n" in ''|*[!0-9]*) n=0 ;; esac; printf '%s\n' "$n"; }

# path_without <dir> <glob> — a PATH directory linking every command on the
# current PATH except those whose name matches <glob>.
path_without() {
  local dir="$1" pat="$2" p f n
  mkdir -p "$dir" || return 1
  local IFS=:
  for p in $PATH; do
    [ -d "$p" ] || continue
    for f in "$p"/*; do
      n="${f##*/}"
      # shellcheck disable=SC2254
      case "$n" in $pat) continue ;; esac
      [ -x "$f" ] && [ ! -e "$dir/$n" ] && ln -s "$f" "$dir/$n" 2>/dev/null
    done
  done
  return 0
}

# S5 — no python3: every state write goes through it, so refuse up front.
S5="$(newtmp)/proj"
if ! mk_project "$S5"; then
  fail_ "S5 setup" "could not build the fixture"
else
  NOPY="$(newtmp)/nopy"; path_without "$NOPY" 'python3*'
  before_p="$(_cksum "$S5/.claude/intake-progress.json")"
  PATH="$NOPY" wiz "$S5" --set-answer monthly_budget "$NEW_BUDGET"
  if [ -e "$NOPY/jq" ] && [ ! -e "$NOPY/python3" ] && [ "$WIZ_RC" -eq 1 ] && grep -q 'needs python3' "$S5/run.out" \
     && [ "$before_p" = "$(_cksum "$S5/.claude/intake-progress.json")" ] && [ "$(ok_lines "$S5")" -eq 0 ]; then
    pass "S5 — with no python3 on PATH the flag refuses (rc=$WIZ_RC), says why, and writes nothing"
  else
    fail_ "S5" "rc=$WIZ_RC (want 1); jq linked $([ -e "$NOPY/jq" ] && echo yes || echo NO); python3 absent $([ ! -e "$NOPY/python3" ] && echo yes || echo NO); refusal $(grep -q 'needs python3' "$S5/run.out" && echo present || echo missing)"
  fi
fi

# S6 — the amendment append fails after the answer landed: refuse, and say
# the answer was written. A python3 wrapper fails only that one program.
S6="$(newtmp)/proj"
if ! mk_project "$S6"; then
  fail_ "S6 setup" "could not build the fixture"
else
  S6BIN="$(newtmp)"; real_py="$(command -v python3)"
  printf '#!/bin/sh\ncase "$*" in *setdefault\\(\\"amendments\\"*) exit 1 ;; esac\nexec "%s" "$@"\n' "$real_py" > "$S6BIN/python3"
  chmod +x "$S6BIN/python3"
  if ! "$S6BIN/python3" -c 'pass' || "$S6BIN/python3" -c 'd={}; d.setdefault("amendments", [])'; then
    fail_ "S6 setup" "the python3 wrapper does not fail exactly the amendment program"
  else
  PATH="$S6BIN:$PATH" wiz "$S6" --set-answer monthly_budget "$NEW_BUDGET"
  got="$(jq_answer monthly_budget "$S6")"; n="$(jq_amend_n "$S6")"; case "$n" in ''|*[!0-9]*) n=0 ;; esac
  if [ "$WIZ_RC" -eq 1 ] && [ "$got" = "$NEW_BUDGET" ] && [ "$n" -eq 0 ] && [ "$(ok_lines "$S6")" -eq 0 ] \
     && grep -q 'answer written but the amendment could not be recorded' "$S6/run.out"; then
    pass "S6 — a failed amendment append refuses (rc=$WIZ_RC) and says the answer was written; no amendment, no [OK]"
  else
    fail_ "S6" "rc=$WIZ_RC (want 1); answer=[$got] (want [$NEW_BUDGET]); amendments=$n (want 0); [OK] lines=$(ok_lines "$S6"); message $(grep -q 'amendment could not be recorded' "$S6/run.out" && echo present || echo missing)"
  fi
  fi
fi

# S7 — the render fails after the answer landed. Since `# BL-265-RENDER-STATUS`
# render_intake_file returns non-zero and writes nothing when a jq step fails;
# `completed_sections` as a string makes the Project Context jq fail (the
# fixture of tests/test-bug010-intake-silent-paths.sh R5). Through this route
# the refusal must say the render is what failed, with no [OK], and
# PROJECT_INTAKE.md must be left byte-identical (`# BL-282-RERENDER`).
S7="$(newtmp)/proj"
if ! mk_project "$S7"; then
  fail_ "S7 setup" "could not build the fixture"
else
  python3 - "$S7/.claude/intake-progress.json" <<'PYCS' || true
import io, json, sys
p = sys.argv[1]
d = json.load(io.open(p, encoding="utf-8"))
d["completed_sections"] = "1, 2"
io.open(p, "w", encoding="utf-8").write(json.dumps(d, indent=2))
PYCS
  before_i="$(_cksum "$S7/PROJECT_INTAKE.md")"
  wiz "$S7" --set-answer monthly_budget "$NEW_BUDGET"
  if [ "$WIZ_RC" -eq 1 ] && [ "$(ok_lines "$S7")" -eq 0 ] && grep -q 'could not be re-rendered' "$S7/run.out" \
     && [ "$(jq_answer monthly_budget "$S7")" = "$NEW_BUDGET" ] && [ "$before_i" = "$(_cksum "$S7/PROJECT_INTAKE.md")" ]; then
    pass "S7 — a render that fails after the write refuses (rc=$WIZ_RC) with 'could not be re-rendered', no [OK], PROJECT_INTAKE.md byte-identical"
  else
    fail_ "S7" "rc=$WIZ_RC (want 1); [OK] lines=$(ok_lines "$S7") (want 0); refusal $(grep -q 'could not be re-rendered' "$S7/run.out" && echo present || echo missing); intake $([ "$before_i" = "$(_cksum "$S7/PROJECT_INTAKE.md")" ] && echo unchanged || echo CHANGED)"
  fi
fi

# W2 — no jq: the answer and amendment are recorded, the render is skipped,
# and a [WARN] says PROJECT_INTAKE.md was not re-rendered.
W2="$(newtmp)/proj"
if ! mk_project "$W2"; then
  fail_ "W2 setup" "could not build the fixture"
else
  NOJQ="$(newtmp)/nojq"; path_without "$NOJQ" 'jq'
  before_i="$(_cksum "$W2/PROJECT_INTAKE.md")"
  PATH="$NOJQ" wiz "$W2" --set-answer monthly_budget "$NEW_BUDGET"
  n="$(jq_amend_n "$W2")"
  if [ ! -e "$NOJQ/jq" ] && [ "$WIZ_RC" -eq 0 ] && [ "$(jq_answer monthly_budget "$W2")" = "$NEW_BUDGET" ] && [ "$n" = "1" ] \
     && grep -q 'jq not found' "$W2/run.out" && [ "$before_i" = "$(_cksum "$W2/PROJECT_INTAKE.md")" ]; then
    pass "W2 — with no jq the answer and amendment are recorded (rc=$WIZ_RC), PROJECT_INTAKE.md is left alone, and a [WARN] says so"
  else
    fail_ "W2" "rc=$WIZ_RC; amendments=$n; warn $(grep -q 'jq not found' "$W2/run.out" && echo present || echo missing); intake $([ "$before_i" = "$(_cksum "$W2/PROJECT_INTAKE.md")" ] && echo unchanged || echo CHANGED)"
  fi
fi

echo "=== N — the competency family is bounded by the wizard's own domain list ==="

# The wizard asks nine fixed domains and derives each key from that list.
# `competency_$key` widened to `competency_[a-z0-9_]+` would let --set-answer
# MINT a key the wizard records nowhere, which is the one thing the refusal
# exists to prevent (`# BL-282-COMPETENCY-DOMAINS`).

# N1 — a real domain key is accepted.
N1="$(newtmp)/proj"
if ! mk_project "$N1"; then
  fail_ "N1 setup" "could not build the fixture"
else
  wiz "$N1" --set-answer competency_security "No"
  got="$(jq_answer competency_security "$N1")"
  if [ "$WIZ_RC" -eq 0 ] && [ "$got" = "No" ]; then
    pass "N1 — competency_security, a key the wizard's own domain list yields, is accepted (rc=$WIZ_RC)"
  else
    fail_ "N1" "rc=$WIZ_RC competency_security=[$got], want [No]: $(tail -1 "$N1/run.out")"
  fi
fi

# N2 — the tooling half of the same family is accepted.
N2="$(newtmp)/proj"
if ! mk_project "$N2"; then
  fail_ "N2 setup" "could not build the fixture"
else
  wiz "$N2" --set-answer competency_devops_infrastructure_tooling "tflint + checkov"
  got="$(jq_answer competency_devops_infrastructure_tooling "$N2")"
  if [ "$WIZ_RC" -eq 0 ] && [ "$got" = "tflint + checkov" ]; then
    pass "N2 — competency_devops_infrastructure_tooling is accepted (rc=$WIZ_RC)"
  else
    fail_ "N2" "rc=$WIZ_RC value=[$got]: $(tail -1 "$N2/run.out")"
  fi
fi

# N3 — an invented domain is refused and nothing is written.
N3="$(newtmp)/proj"
if ! mk_project "$N3"; then
  fail_ "N3 setup" "could not build the fixture"
else
  # competency_sec is a SUBSTRING of a real domain key: membership is of the
  # whole line (`grep -x`), never a match inside one.
  before_p="$(_cksum "$N3/.claude/intake-progress.json")"; bad=""
  for nk in competency_zzz competency_sec; do
    wiz "$N3" --set-answer "$nk" "minted"
    [ "$WIZ_RC" -eq 1 ] && [ "$(jq_answer "$nk" "$N3")" = "<<unset>>" ] || bad="$bad [rc=$WIZ_RC for $nk]"
  done
  after_p="$(_cksum "$N3/.claude/intake-progress.json")"
  if [ -z "$bad" ] && [ "$before_p" = "$after_p" ]; then
    pass "N3 — competency_zzz and competency_sec are refused (rc=1), mint nothing, file byte-identical"
  else
    fail_ "N3" "${bad:- rc fine}; file $([ "$before_p" = "$after_p" ] && echo unchanged || echo CHANGED)"
  fi
fi

# N4 — competency_matrix is an ADOPTION-recorded key, not a wizard key, so
# this route refuses it. The stacked follow-up accepts it with its own note.
N4="$(newtmp)/proj"
if ! mk_project "$N4"; then
  fail_ "N4 setup" "could not build the fixture"
else
  before_p="$(_cksum "$N4/.claude/intake-progress.json")"
  wiz "$N4" --set-answer competency_matrix "adoption row"
  after_p="$(_cksum "$N4/.claude/intake-progress.json")"
  got="$(jq_answer competency_matrix "$N4")"
  if [ "$WIZ_RC" -eq 1 ] && [ "$got" = "<<unset>>" ] && [ "$before_p" = "$after_p" ]; then
    pass "N4 — competency_matrix is refused by this route (rc=$WIZ_RC), file byte-identical"
  else
    fail_ "N4" "rc=$WIZ_RC (want 1); competency_matrix=[$got] (want unset); file $([ "$before_p" = "$after_p" ] && echo unchanged || echo CHANGED)"
  fi
fi

# N5 — the helper must not be the first line a neighbouring suite's scan
# finds. tests/test-intake-wizard-fixes.sh T5b takes the FIRST line matching
# /local domains=\(/ and counts the quoted strings on it; a helper carrying
# that literal inside its own grep pattern answers for the real array and
# T5b reads 1 domain instead of 9. This runs T5b's own awk, verbatim.
n_dom="$(awk '
  /local domains=\(/ {
    line=$0
    sub(/.*domains=\(/, "", line)
    sub(/\).*/, "", line)
    n=gsub(/"[^"]*"/, "&", line)
    print n; exit
  }
' "$WIZARD")"
case "$n_dom" in ''|*[!0-9]*) n_dom=0 ;; esac
if [ "$n_dom" -eq 9 ]; then
  pass "N5 — T5b's own scan still finds the 9-domain array first (found $n_dom)"
else
  fail_ "N5" "T5b's scan finds $n_dom domain(s), want 9 — a line above the real array matches /local domains=\\(/ and answers for it"
fi

# N6 — a carriage return in a value cannot split the rendered row. Reachable
# from a progress file edited outside the wizard; cmark-gfm treats a lone CR
# as a line break, so an unneutralised CR ends the table row early.
N6="$(newtmp)/proj"
if ! mk_project "$N6"; then
  fail_ "N6 setup" "could not build the fixture"
else
  python3 - "$N6/.claude/intake-progress.json" <<'PYCR' || true
import io, json, sys
p = sys.argv[1]
d = json.load(io.open(p, encoding="utf-8"))
d.setdefault("answers", {})["problem_statement"] = "before\rafter"
io.open(p, "w", encoding="utf-8").write(json.dumps(d, indent=2))
PYCR
  wiz "$N6" --set-answer monthly_budget "$NEW_BUDGET"
  # The row must be ONE physical line carrying both halves and closing with |.
  row_lines="$(awk '/^\| `problem_statement` \|/{c++} END{print c+0}' "$N6/PROJECT_INTAKE.md")"
  row="$(awk '/^\| `problem_statement` \|/{print; exit}' "$N6/PROJECT_INTAKE.md")"
  stray_cr="$(printf '%s' "$row" | tr -cd '\r' | wc -c | tr -d ' ')"
  if [ "$WIZ_RC" -eq 0 ] && [ "$row_lines" = "1" ] && [ "$stray_cr" = "0" ] \
     && printf '%s' "$row" | grep -q 'before' && printf '%s' "$row" | grep -q 'after' \
     && printf '%s' "$row" | grep -q '|$'; then
    pass "N6 — a carriage return in a value renders as one intact row, both halves present, no stray CR"
  else
    fail_ "N6" "rc=$WIZ_RC rows=$row_lines stray_cr=$stray_cr row=[$row]"
  fi
fi

echo "=== N — gate_, infra_ and escalation_ are bounded by their own arrays; keys match whole ==="

# refuse_all <id> <label> <key…> — each key refused at exit 1, and the
# progress file AND PROJECT_INTAKE.md byte-identical, so no appendix row.
refuse_all() {
  local id="$1" label="$2" d before_p before_i bad="" k; shift 2
  d="$(newtmp)/proj"
  if ! mk_project "$d"; then fail_ "$id setup" "could not build the fixture"; return 0; fi
  before_p="$(_cksum "$d/.claude/intake-progress.json")"; before_i="$(_cksum "$d/PROJECT_INTAKE.md")"
  for k in "$@"; do
    wiz "$d" --set-answer "$k" "minted"
    [ "$WIZ_RC" -eq 1 ] || bad="$bad [rc=$WIZ_RC for $(printf '%s' "$k" | tr '\n' '/')]"
  done
  if [ -z "$bad" ] && [ "$before_p" = "$(_cksum "$d/.claude/intake-progress.json")" ] \
     && [ "$before_i" = "$(_cksum "$d/PROJECT_INTAKE.md")" ]; then
    pass "$id — $label: $# keys each refused (rc=1), progress file and PROJECT_INTAKE.md byte-identical"
  else
    fail_ "$id" "$label:${bad:- rc fine}; progress $([ "$before_p" = "$(_cksum "$d/.claude/intake-progress.json")" ] && echo unchanged || echo CHANGED); intake $([ "$before_i" = "$(_cksum "$d/PROJECT_INTAKE.md")" ] && echo unchanged || echo CHANGED)"
  fi
}

# N7 (control) — a real key from each array is accepted, derived the way the
# wizard derives it: `SSO / Identity Provider` → `sso___identity_provider`,
# `Level 1 (first escalation)` → `level_1__first_escalation_`.
N7="$(newtmp)/proj"
if ! mk_project "$N7"; then
  fail_ "N7 setup" "could not build the fixture"
else
  bad=""
  for k in gate_phase_0_to_phase_1 gate_phase_3_to_phase_4 infra_sso___identity_provider infra_ci_cd_platform \
           escalation_level_1__first_escalation_ escalation_level_2; do
    wiz "$N7" --set-answer "$k" "v-$k"
    [ "$WIZ_RC" -eq 0 ] && [ "$(jq_answer "$k" "$N7")" = "v-$k" ] || bad="$bad [rc=$WIZ_RC for $k]"
  done
  if [ -z "$bad" ]; then
    pass "N7 (control) — six keys the gates, infra_items and levels arrays yield are accepted and written"
  else
    fail_ "N7 (control)" "a real array key was refused:$bad"
  fi
fi

# N8 — the review's four (a typo of a real gate key among them) and two
# near-misses: each was accepted and minted by the `$key` widening.
refuse_all N8 "gate_, infra_ and escalation_ keys no array yields" \
  gate_phase_0_phase_1 gate_zzz infra_typo escalation_nonsense gate_phase_0_to_phase_1_x infra_monitoring_tooling \
  gate_phase_0 infra_sso escalation_level

# N9 — keys carrying a line break, each with one line a valid key would
# match. Matching is of the WHOLE string (`# BL-282-KEY-CHARSET`,
# `# BL-282-FAMILY-WHOLE`), never line by line.
refuse_all N9 "keys with a line break" \
  "$(printf 'NOT A KEY\ngate_q')" "$(printf 'NOT A KEY\ninput_1_name')" \
  "$(printf 'gate_phase_0_to_phase_1\nNOT')" "$(printf 'competency_security\nNOT')" \
  "$(printf 'monthly_budget\nNOT')" "input_1_name
"

# N11 — `# BL-282-KEY-CHARSET` alone refuses an upper-case or accented key,
# in a UTF-8 locale too. On bash 3.2 a `[a-z]` range collates, so `M` and `é`
# fall inside it; the class is spelled out letter by letter. A mirror makes
# every check after the charset accept, so only the charset can refuse here;
# the lower-case control proves the mirror accepts past it.
N11FW="$(newtmp)/fw"
# Without the locale, bash falls back to C, where both spellings agree, so
# the case would pass while testing less than it says.
if ! locale -a 2>/dev/null | grep -i -x -E 'en_GB\.utf-?8' >/dev/null; then
  echo "  [SKIP] N11 — en_GB.UTF-8 is not installed (locale -a), so this host cannot tell a collating [a-z] from the spelled-out class"
elif ! mkdir -p "$N11FW" || ! cp -Rp "$REPO_ROOT/scripts" "$N11FW/"; then
  fail_ "N11 setup" "could not mirror scripts/"
else
  n11t="$N11FW/scripts/intake-wizard.sh"
  awk '{ print } /# BL-282-KEY-CHARSET$/ { print "  return 0" }' "$n11t" > "$n11t.new" && mv "$n11t.new" "$n11t"
  N11="$(newtmp)/proj"
  if ! _syntax_ok "$n11t" || [ "$(grep -A1 '# BL-282-KEY-CHARSET$' "$n11t" | sed -n 2p)" != "  return 0" ] \
     || ! mk_project "$N11" "$n11t"; then
    fail_ "N11 setup" "could not build the charset-only mirror"
  else
    LC_ALL=en_GB.UTF-8 wiz "$N11" --set-answer zz_not_a_key "ctl"; rc_ctl=$WIZ_RC
    bad=""
    for nk in Monthly_budget "$(printf 'monthly_budg\303\251t')" GATE_ZZZ; do
      LC_ALL=en_GB.UTF-8 wiz "$N11" --set-answer "$nk" "minted"
      [ "$WIZ_RC" -eq 1 ] || bad="$bad [rc=$WIZ_RC for $nk]"
    done
    if [ "$rc_ctl" -eq 0 ] && [ -z "$bad" ]; then
      pass "N11 — with every later check accepting, the charset alone refuses Monthly_budget, monthly_budgét and GATE_ZZZ under LC_ALL=en_GB.UTF-8 (control accepted, rc=$rc_ctl)"
    else
      fail_ "N11" "control rc=$rc_ctl (want 0);${bad:- keys refused}"
    fi
  fi
fi

# N10 — a `$key` family with no bound of its own is refused, not widened: a
# mirror whose wizard carries one extra `save_answer "probe_$key"` call site.
N10FW="$(newtmp)/fw"
if ! mkdir -p "$N10FW" || ! cp -Rp "$REPO_ROOT/scripts" "$N10FW/"; then
  fail_ "N10 setup" "could not mirror scripts/"
else
  printf '%s\n' '_bl282_probe_family() { save_answer "probe_$key" "x"; }' >> "$N10FW/scripts/intake-wizard.sh"
  N10="$(newtmp)/proj"
  if ! _syntax_ok "$N10FW/scripts/intake-wizard.sh" || ! mk_project "$N10" "$N10FW/scripts/intake-wizard.sh"; then
    fail_ "N10 setup" "could not build the probe-family fixture"
  else
    before_p="$(_cksum "$N10/.claude/intake-progress.json")"
    wiz "$N10" --set-answer probe_anything "minted"
    if [ "$WIZ_RC" -eq 1 ] && [ "$before_p" = "$(_cksum "$N10/.claude/intake-progress.json")" ]; then
      pass "N10 — probe_anything, from an unbounded probe_\$key call site, is refused (rc=$WIZ_RC), nothing written"
    else
      fail_ "N10" "rc=$WIZ_RC (want 1) — an unbounded \$key family is still widened to any suffix"
    fi
  fi
fi

echo "=== A — an abort inside run_set_answer must fail CLOSED ==="

# `if run_set_answer "$@"; then` puts the function in a condition, which
# disarms errexit for its whole body. An abort inside any command
# substitution there is then survivable: execution walks on to `return 0`
# and the wizard reports success. This is not shell-version-specific; it
# reads the same under bash 3.2 and bash 5.
# _mirror_with_abort <dir> → a wizard copy whose run_set_answer aborts on
# its first line, before anything is written.
_mirror_with_abort() {
  local fw="$1" tgt
  mkdir -p "$fw" || return 1
  cp -Rp "$REPO_ROOT/scripts" "$fw/" || return 1
  tgt="$fw/scripts/intake-wizard.sh"
  awk '
    /^run_set_answer\(\) \{$/ && !done {
      print
      print "  _bl282_forced_abort=\"$(printf %s \"$BL282_NO_SUCH_VAR\")\""
      done = 1
      next
    }
    { print }
  ' "$tgt" > "$tgt.new" || return 1
  mv "$tgt.new" "$tgt" || return 1
  chmod +x "$tgt" 2>/dev/null
  _syntax_ok "$tgt" || return 1
  grep -q 'BL282_NO_SUCH_VAR' "$tgt" || return 1
  printf '%s\n' "$tgt"
}

A1FW="$(newtmp)/fw"
A1TGT="$(_mirror_with_abort "$A1FW")"
if [ -z "${A1TGT:-}" ]; then
  fail_ "A1 setup" "could not build the aborting mirror"
else
  A1="$(newtmp)/proj"
  if ! mk_project "$A1" "$A1TGT"; then
    fail_ "A1 setup" "could not build the fixture"
  else
    before_p="$(_cksum "$A1/.claude/intake-progress.json")"
    wiz "$A1" --set-answer monthly_budget "$NEW_BUDGET"
    after_p="$(_cksum "$A1/.claude/intake-progress.json")"
    got="$(jq_answer monthly_budget "$A1")"
    n="$(jq_amend_n "$A1")"; case "$n" in ''|*[!0-9]*) n=0 ;; esac
    if [ "$WIZ_RC" -ne 0 ] && [ "$got" = "$OLD_BUDGET" ] && [ "$n" -eq 0 ] && [ "$before_p" = "$after_p" ]; then
      pass "A1 — an abort inside run_set_answer exits non-zero (rc=$WIZ_RC), writes nothing and appends no amendment"
    else
      fail_ "A1" "rc=$WIZ_RC (want non-zero); monthly_budget=[$got] (want [$OLD_BUDGET]); amendments=$n (want 0); file $([ "$before_p" = "$after_p" ] && echo unchanged || echo CHANGED)"
    fi
  fi
fi

echo "=== W — a key with a second home is written here and the other home is named ==="

W1="$(newtmp)/proj"
if ! mk_project "$W1"; then
  fail_ "W1 setup" "could not build the fixture"
else
  before_s="$(_cksum "$W1/.claude/process-state.json")"
  wiz "$W1" --set-answer data_classification pii
  after_s="$(_cksum "$W1/.claude/process-state.json")"
  got="$(jq_answer data_classification "$W1")"
  if [ "$WIZ_RC" -eq 0 ] && [ "$got" = "pii" ] && grep -q -- '--data-classification' "$W1/run.out" \
     && grep -q 'process-state.json' "$W1/run.out" && [ "$before_s" = "$after_s" ]; then
    pass "W1 — data_classification is written to answers/ and the [WARN] names process-state.json and --data-classification; that file is untouched"
  else
    fail_ "W1" "rc=$WIZ_RC answers.data_classification=[$got]; warn $(grep -q -- '--data-classification' "$W1/run.out" && echo present || echo missing); process-state $([ "$before_s" = "$after_s" ] && echo unchanged || echo CHANGED)"
  fi
fi

# W3 — testing_interval's enforced copy lives in build-progress.json; the
# [WARN] names it and the setter for it, and that file is not created here.
W3="$(newtmp)/proj"
if ! mk_project "$W3"; then
  fail_ "W3 setup" "could not build the fixture"
else
  wiz "$W3" --set-answer testing_interval 7
  if [ "$WIZ_RC" -eq 0 ] && [ "$(jq_answer testing_interval "$W3")" = "7" ] \
     && grep -q 'build-progress.json::test_interval' "$W3/run.out" && grep -q -- '--field test_interval' "$W3/run.out" \
     && [ ! -e "$W3/.claude/build-progress.json" ]; then
    pass "W3 — testing_interval is written to answers/ and the [WARN] names build-progress.json and --field test_interval; that file is not created"
  else
    fail_ "W3" "rc=$WIZ_RC testing_interval=[$(jq_answer testing_interval "$W3")]; warn $(grep -q 'build-progress.json::test_interval' "$W3/run.out" && echo present || echo missing)"
  fi
fi

echo "=== M — mutation proofs on a mirror ==="

for mark in BL-282-SET-ANSWER-BEGIN BL-282-SET-ANSWER-END BL-282-KEY-REFUSE BL-282-RERENDER BL-282-HINT-COUNT BL-282-WRITE-STATUS BL-282-COMPETENCY-DOMAINS BL-282-ARM-FAILCLOSED \
            BL-282-KEY-CHARSET BL-282-GATE-KEYS BL-282-INFRA-KEYS BL-282-ESCALATION-KEYS BL-282-INDEX-DIGITS BL-282-FAMILY-WHOLE BL-282-READ-BACK; do
  n="$(grep -c "$mark" "$WIZARD" 2>/dev/null)"; case "$n" in ''|*[!0-9]*) n=0 ;; esac
  [ "$n" = "1" ] \
    && pass "M0 — '$mark' occurs exactly once in intake-wizard.sh" \
    || fail_ "M0" "'$mark' occurs $n times in intake-wizard.sh (need exactly 1)"
done

# _hunk_line <before> <after> → the first line number in <before> that diff
# reports as changed ('' when diff is empty). The location proof: the only
# changed line must be the marker line, not some other `return 1` elsewhere.
_hunk_line() { diff "$1" "$2" 2>/dev/null | grep -m1 -E '^[0-9]+' | sed -E 's/^([0-9]+).*/\1/'; }

# MP1 — neuter the key check: the refusal line becomes `return 0`. K1's
# scenario must then ACCEPT the unknown key; H1's scenario must still work
# (the mutant changed the guard, not the write).
MP1="$(newtmp)/fw"
if ! mkdir -p "$MP1" || ! cp -Rp "$REPO_ROOT/scripts" "$MP1/"; then
  fail_ "MP1 setup" "could not mirror scripts/"
else
  tgt="$MP1/scripts/intake-wizard.sh"; before="$(mktemp)"; cp "$tgt" "$before"
  m_ln="$(grep -n 'BL-282-KEY-REFUSE' "$before" | head -1 | cut -d: -f1)"
  sed -e 's/^\([[:space:]]*\)return 1\([[:space:]]*# BL-282-KEY-REFUSE\)$/\1return 0\2/' "$before" > "$tgt"
  h_ln="$(_hunk_line "$before" "$tgt")"
  if [ -z "$m_ln" ] || ! _syntax_ok "$tgt" \
     || [ "$(_changed_lines "$before" "$tgt")" -ne 2 ] || [ "$h_ln" != "$m_ln" ] \
     || ! sed -n "${m_ln}p" "$tgt" | grep -q 'return 0'; then
    fail_ "MP1 setup" "the key-check mutation did not land on the marker line (marker=$m_ln hunk=$h_ln changed=$(_changed_lines "$before" "$tgt"))"
  else
    PDM="$(newtmp)/proj"
    if ! mk_project "$PDM" "$tgt"; then
      fail_ "MP1 setup" "could not build the mutant's fixture"
    else
      wiz "$PDM" --set-answer monthly_budgett "$NEW_BUDGET"
      rc_bad=$WIZ_RC; got_bad="$(jq_answer monthly_budgett "$PDM")"
      wiz "$PDM" --set-answer monthly_budget "$NEW_BUDGET"
      rc_ok=$WIZ_RC
      if [ "$rc_bad" -eq 0 ] && [ "$got_bad" = "$NEW_BUDGET" ] && [ "$rc_ok" -eq 0 ]; then
        pass "MP1 (MUTATION) — with the refusal neutered an unknown key is ACCEPTED (rc=$rc_bad, written) while a valid key still works: K1 is what stops it"
      else
        fail_ "MP1 (MUTATION)" "unknown-key rc=$rc_bad written=[$got_bad]; valid-key rc=$rc_ok — the mutation changed nothing K1 can see"
      fi
    fi
  fi
fi

# MP2 — delete the re-render: the JSON write still lands (control inside the
# mutant) but PROJECT_INTAKE.md never learns the new value. H4 is what stops it.
MP2="$(newtmp)/fw"
if ! mkdir -p "$MP2" || ! cp -Rp "$REPO_ROOT/scripts" "$MP2/"; then
  fail_ "MP2 setup" "could not mirror scripts/"
else
  tgt2="$MP2/scripts/intake-wizard.sh"; before2="$(mktemp)"; cp "$tgt2" "$before2"
  r_ln="$(grep -n 'BL-282-RERENDER' "$before2" | head -1 | cut -d: -f1)"
  if [ -z "$r_ln" ]; then
    fail_ "MP2 setup" "could not locate the re-render line"
  else
    { head -n $((r_ln - 1)) "$before2"; tail -n +$((r_ln + 1)) "$before2"; } > "$tgt2"
    h_ln2="$(_hunk_line "$before2" "$tgt2")"
    if ! _syntax_ok "$tgt2" || [ "$(_changed_lines "$before2" "$tgt2")" -ne 1 ] \
       || [ "$h_ln2" != "$r_ln" ] || grep -q 'BL-282-RERENDER' "$tgt2"; then
      fail_ "MP2 setup" "the re-render deletion did not land on the marker line (marker=$r_ln hunk=$h_ln2)"
    else
      PDM2="$(newtmp)/proj"
      if ! mk_project "$PDM2" "$tgt2"; then
        fail_ "MP2 setup" "could not build the mutant's fixture"
      else
        wiz "$PDM2" --set-answer monthly_budget "$NEW_BUDGET"
        got_json="$(jq_answer monthly_budget "$PDM2")"
        got_row="$(rendered_row "$PDM2" monthly_budget)"
        if [ "$got_json" = "$NEW_BUDGET" ] && [ "$got_row" != "$NEW_BUDGET (amended $(date -u +%Y-%m-%d))" ]; then
          pass "MP2 (MUTATION) — without the re-render the JSON carries the new value but the rendered row is [$got_row]: H4 is what stops it"
        else
          fail_ "MP2 (MUTATION)" "json=[$got_json] row=[$got_row] — deleting the re-render changed nothing H4 can see"
        fi
      fi
    fi
  fi
fi

# MP3 — narrow the hint: `head -3` becomes `head -1` on the marked line. The
# refusal still refuses (control inside the mutant), so ONLY K3's count sees it.
MP3="$(newtmp)/fw"
if ! mkdir -p "$MP3" || ! cp -Rp "$REPO_ROOT/scripts" "$MP3/"; then
  fail_ "MP3 setup" "could not mirror scripts/"
else
  tgt3="$MP3/scripts/intake-wizard.sh"; before3="$(mktemp)"; cp "$tgt3" "$before3"
  c_ln="$(grep -n 'BL-282-HINT-COUNT' "$before3" | head -1 | cut -d: -f1)"
  sed -e 's/^\(.*\)head -3\(.*# BL-282-HINT-COUNT.*\)$/\1head -1\2/' "$before3" > "$tgt3"
  h_ln3="$(_hunk_line "$before3" "$tgt3")"
  if [ -z "$c_ln" ] || ! _syntax_ok "$tgt3" \
     || [ "$(_changed_lines "$before3" "$tgt3")" -ne 2 ] || [ "$h_ln3" != "$c_ln" ] \
     || ! sed -n "${c_ln}p" "$tgt3" | grep -q 'head -1'; then
    fail_ "MP3 setup" "the hint-count mutation did not land on the marker line (marker=$c_ln hunk=$h_ln3 changed=$(_changed_lines "$before3" "$tgt3"))"
  else
    PDM3="$(newtmp)/proj"
    if ! mk_project "$PDM3" "$tgt3"; then
      fail_ "MP3 setup" "could not build the mutant's fixture"
    else
      wiz "$PDM3" --set-answer monthly_budgett "$NEW_BUDGET"
      n_bad="$(_hint_count "$PDM3/run.out")"
      if [ "$WIZ_RC" -eq 1 ] && [ "$n_bad" -eq 1 ]; then
        pass "MP3 (MUTATION) — narrowed to head -1 the hint names $n_bad key while the refusal still refuses (rc=$WIZ_RC): K3 is what stops it"
      else
        fail_ "MP3 (MUTATION)" "rc=$WIZ_RC hint names $n_bad key(s) — narrowing the hint changed nothing K3 can see"
      fi
    fi
  fi
fi

# MP4 — discard the write's status again: the guard becomes `|| true`. In
# the first cut the no-answers fixture then reported [OK] at exit 0 with no
# answer written. `# BL-282-READ-BACK` now refuses that run too, so the
# verdict is held twice and this mutant is DIAGNOSIS-ONLY: the refusal says
# "does not read back" instead of "could not write". S1's reason assertion
# is what sees it; S4 is the case the read-back alone holds.
MP4="$(newtmp)/fw"
if ! mkdir -p "$MP4" || ! cp -Rp "$REPO_ROOT/scripts" "$MP4/"; then
  fail_ "MP4 setup" "could not mirror scripts/"
else
  tgt4="$MP4/scripts/intake-wizard.sh"; before4="$(mktemp)"; cp "$tgt4" "$before4"
  w_ln="$(grep -n 'BL-282-WRITE-STATUS' "$before4" | head -1 | cut -d: -f1)"
  sed -e 's/^\(.*save_answer "\$key" "\$value" \)|| {.*}\( *# BL-282-WRITE-STATUS\)$/\1|| true\2/' "$before4" > "$tgt4"
  h_ln4="$(_hunk_line "$before4" "$tgt4")"
  if [ -z "$w_ln" ] || ! _syntax_ok "$tgt4" \
     || [ "$(_changed_lines "$before4" "$tgt4")" -ne 2 ] || [ "$h_ln4" != "$w_ln" ] \
     || ! sed -n "${w_ln}p" "$tgt4" | grep -q '|| true'; then
    fail_ "MP4 setup" "the write-status mutation did not land on the marker line (marker=$w_ln hunk=$h_ln4 changed=$(_changed_lines "$before4" "$tgt4"))"
  else
    PDM4="$(newtmp)/proj"
    if ! mk_project_noanswers "$PDM4" || ! cp "$tgt4" "$PDM4/scripts/intake-wizard.sh"; then
      fail_ "MP4 setup" "could not build the mutant's no-answers fixture"
    else
      wiz "$PDM4" --set-answer monthly_budget "$NEW_BUDGET"
      got_ans="$(jq_answer monthly_budget "$PDM4")"
      ok_n="$(grep -c '\[OK\]' "$PDM4/run.out")"; case "$ok_n" in ''|*[!0-9]*) ok_n=0 ;; esac
      if [ "$WIZ_RC" -eq 1 ] && [ "$ok_n" -eq 0 ] && [ "$got_ans" = "<<unset>>" ] \
         && ! grep -q 'could not write' "$PDM4/run.out" && grep -q 'does not read back' "$PDM4/run.out"; then
        pass "MP4 (MUTATION, DIAGNOSIS-ONLY) — with the write's status discarded the read-back still refuses (rc=$WIZ_RC, no [OK], no answer) but says 'does not read back': S1's reason assertion is what sees it"
      else
        fail_ "MP4 (MUTATION)" "rc=$WIZ_RC ok_lines=$ok_n answer=[$got_ans] reason=[$(grep -m1 'FAIL' "$PDM4/run.out" || echo '<none>')] — not the diagnosis-only outcome this proof records"
      fi
    fi
  fi
fi

# MP5 — widen the family again: the competency arm's membership test
# becomes `return 0`, so any competency_* key is admitted. N3 is what stops it.
MP5="$(newtmp)/fw"
if ! mkdir -p "$MP5" || ! cp -Rp "$REPO_ROOT/scripts" "$MP5/"; then
  fail_ "MP5 setup" "could not mirror scripts/"
else
  tgt5="$MP5/scripts/intake-wizard.sh"; before5="$(mktemp)"; cp "$tgt5" "$before5"
  d_ln="$(grep -n 'BL-282-COMPETENCY-DOMAINS' "$before5" | head -1 | cut -d: -f1)"
  sed -e 's/^\([[:space:]]*\)_bl282_array_keys domains .*\(  # BL-282-COMPETENCY-DOMAINS\)$/\1return 0\2/' "$before5" > "$tgt5"
  h_ln5="$(_hunk_line "$before5" "$tgt5")"
  if [ -z "$d_ln" ] || ! _syntax_ok "$tgt5" \
     || [ "$(_changed_lines "$before5" "$tgt5")" -ne 2 ] || [ "$h_ln5" != "$d_ln" ] \
     || ! sed -n "${d_ln}p" "$tgt5" | grep -q 'return 0  # BL-282-COMPETENCY-DOMAINS'; then
    fail_ "MP5 setup" "the competency-widening mutation did not land on the marker line (marker=$d_ln hunk=$h_ln5 changed=$(_changed_lines "$before5" "$tgt5"))"
  else
    PDM5="$(newtmp)/proj"
    if ! mk_project "$PDM5" "$tgt5"; then
      fail_ "MP5 setup" "could not build the mutant's fixture"
    else
      wiz "$PDM5" --set-answer competency_zzz "minted"
      rc_bad=$WIZ_RC; got_bad="$(jq_answer competency_zzz "$PDM5")"
      wiz "$PDM5" --set-answer competency_security "No"
      rc_ok=$WIZ_RC
      if [ "$rc_bad" -eq 0 ] && [ "$got_bad" = "minted" ] && [ "$rc_ok" -eq 0 ]; then
        pass "MP5 (MUTATION) — with the family widened again competency_zzz is MINTED (rc=$rc_bad) while a real domain key still works: N3 is what stops it"
      else
        fail_ "MP5 (MUTATION)" "invented-key rc=$rc_bad written=[$got_bad]; real-key rc=$rc_ok — widening the family changed nothing N3 can see"
      fi
    fi
  fi
fi

# MP6 — restore the old arm: the call goes back inside an `if`, which disarms
# errexit for the whole function body. The same forced abort then walks on to
# `return 0` and the wizard reports success. A1 is what stops it.
MP6="$(newtmp)/fw"
MP6TGT="$(_mirror_with_abort "$MP6")"
if [ -z "${MP6TGT:-}" ]; then
  fail_ "MP6 setup" "could not build the aborting mirror"
else
  before6="$(mktemp)"; cp "$MP6TGT" "$before6"
  a_ln="$(grep -n 'BL-282-ARM-FAILCLOSED' "$before6" | head -1 | cut -d: -f1)"
  sed -e 's/^\([[:space:]]*\)run_set_answer "\$@".*# BL-282-ARM-FAILCLOSED.*$/\1if run_set_answer "$@"; then exit 0; fi  # BL-282-ARM-FAILCLOSED/' "$before6" > "$MP6TGT"
  h_ln6="$(_hunk_line "$before6" "$MP6TGT")"
  if [ -z "$a_ln" ] || ! _syntax_ok "$MP6TGT" \
     || [ "$(_changed_lines "$before6" "$MP6TGT")" -ne 2 ] || [ "$h_ln6" != "$a_ln" ] \
     || ! sed -n "${a_ln}p" "$MP6TGT" | grep -q 'if run_set_answer'; then
    fail_ "MP6 setup" "the arm mutation did not land on the marker line (marker=$a_ln hunk=$h_ln6 changed=$(_changed_lines "$before6" "$MP6TGT"))"
  else
    PDM6="$(newtmp)/proj"
    if ! mk_project "$PDM6" "$MP6TGT"; then
      fail_ "MP6 setup" "could not build the mutant's fixture"
    else
      wiz "$PDM6" --set-answer monthly_budget "$NEW_BUDGET"
      got6="$(jq_answer monthly_budget "$PDM6")"
      n6="$(jq_amend_n "$PDM6")"; case "$n6" in ''|*[!0-9]*) n6=0 ;; esac
      if [ "$WIZ_RC" -eq 0 ] && [ "$got6" = "$NEW_BUDGET" ] && [ "$n6" -eq 1 ]; then
        pass "MP6 (MUTATION) — with the call back inside a condition the same abort is survived: rc=$WIZ_RC, answer written, amendment appended. A1 is what stops it"
      else
        fail_ "MP6 (MUTATION)" "rc=$WIZ_RC answer=[$got6] amendments=$n6 — restoring the old arm changed nothing A1 can see"
      fi
    fi
  fi
fi

# mp_mutate <id> <sed-script-file> <marker>… — mirrors scripts/, applies the
# sed script, and proves where it landed: exactly one changed line per named
# marker, every hunk on a marker's own line, each marker line now differing,
# and the result parses. Sets MP_TGT; returns 1 (after reporting) otherwise.
MP_TGT=""
mp_mutate() {
  local id="$1" script="$2" fw tgt before m ln hunks want_hunks=""; shift 2
  MP_TGT=""
  fw="$(newtmp)/fw"
  if ! mkdir -p "$fw" || ! cp -Rp "$REPO_ROOT/scripts" "$fw/"; then fail_ "$id setup" "could not mirror scripts/"; return 1; fi
  tgt="$fw/scripts/intake-wizard.sh"; before="$fw/before.sh"; cp "$tgt" "$before"
  sed -f "$script" "$before" > "$tgt"
  for m in "$@"; do
    ln="$(grep -n "# $m\$" "$before" | head -1 | cut -d: -f1)"
    if [ -z "$ln" ] || [ "$(sed -n "${ln}p" "$before")" = "$(sed -n "${ln}p" "$tgt")" ] || ! sed -n "${ln}p" "$tgt" | grep -q "# $m\$"; then
      fail_ "$id setup" "the mutation did not land on the '$m' line (line=${ln:-none})"; return 1
    fi
    want_hunks="$want_hunks $ln"
  done
  hunks="$(diff "$before" "$tgt" 2>/dev/null | grep -E '^[0-9]+' | sed -E 's/^([0-9]+).*/\1/' | tr '\n' ' ')"
  if ! _syntax_ok "$tgt" || [ "$(_changed_lines "$before" "$tgt")" -ne $((2 * $#)) ] || [ " ${hunks% }" != "$want_hunks" ]; then
    fail_ "$id setup" "the mutation landed elsewhere: hunks at [${hunks% }] want [${want_hunks# }], changed=$(_changed_lines "$before" "$tgt"), syntax $(_syntax_ok "$tgt" && echo ok || echo BROKEN)"
    return 1
  fi
  MP_TGT="$tgt"
  return 0
}
SEDS="$(newtmp)"

# MP7 — THE REVIEW'S MUTANT: the index bound `[0-9]+` widened to `[0-9a-z]+`.
# Both suites were green under it; H8N is what stops it now.
cat > "$SEDS/mp7.sed" <<'SED'
/# BL-282-INDEX-DIGITS$/s/\[0-9\]+/[0-9a-z]+/g
SED
if mp_mutate MP7 "$SEDS/mp7.sed" BL-282-INDEX-DIGITS; then
  PD="$(newtmp)/proj"
  if ! mk_project "$PD" "$MP_TGT"; then fail_ "MP7 setup" "could not build the mutant's fixture"; else
    wiz "$PD" --set-answer input_x_name "minted"; rc_bad=$WIZ_RC; got_bad="$(jq_answer input_x_name "$PD")"
    wiz "$PD" --set-answer input_2_name "ok"; rc_ok=$WIZ_RC
    if [ "$rc_bad" -eq 0 ] && [ "$got_bad" = "minted" ] && [ "$rc_ok" -eq 0 ]; then
      pass "MP7 (MUTATION) — with the index widened to [0-9a-z]+ input_x_name is MINTED (rc=$rc_bad) while input_2_name still works: H8N is what stops it"
    else
      fail_ "MP7 (MUTATION)" "input_x_name rc=$rc_bad written=[$got_bad]; input_2_name rc=$rc_ok — the widening changed nothing H8N can see"
    fi
  fi
fi

# MP8–MP10 — each array bound neutered: the arm's membership test becomes
# `return 0`, so any suffix is admitted. N8 is what stops each; the real key
# still working inside the mutant is the control.
# fam_mutant <id> <marker> <invented key> <real key>
fam_mutant() {
  local id="$1" marker="$2" bad_k="$3" ok_k="$4" pd rc_bad got_bad rc_ok
  printf '/# %s$/s/^\\([[:space:]]*\\)_bl282_array_keys .*\\(  # %s\\)$/\\1return 0\\2/\n' "$marker" "$marker" > "$SEDS/$id.sed"
  mp_mutate "$id" "$SEDS/$id.sed" "$marker" || return 0
  pd="$(newtmp)/proj"
  if ! mk_project "$pd" "$MP_TGT"; then fail_ "$id setup" "could not build the mutant's fixture"; return 0; fi
  wiz "$pd" --set-answer "$bad_k" "minted"; rc_bad=$WIZ_RC; got_bad="$(jq_answer "$bad_k" "$pd")"
  wiz "$pd" --set-answer "$ok_k" "ok"; rc_ok=$WIZ_RC
  if [ "$rc_bad" -eq 0 ] && [ "$got_bad" = "minted" ] && [ "$rc_ok" -eq 0 ]; then
    pass "$id (MUTATION) — with '$marker' neutered $bad_k is MINTED (rc=$rc_bad) while $ok_k still works: N8 is what stops it"
  else
    fail_ "$id (MUTATION)" "$bad_k rc=$rc_bad written=[$got_bad]; $ok_k rc=$rc_ok — neutering the bound changed nothing N8 can see"
  fi
}
fam_mutant MP8 BL-282-GATE-KEYS gate_zzz gate_phase_0_to_phase_1
fam_mutant MP9 BL-282-INFRA-KEYS infra_typo infra_ci_cd_platform
fam_mutant MP10 BL-282-ESCALATION-KEYS escalation_nonsense escalation_level_2

# MP11 — the `$key` widening restored on the index line: `s/\$key$/[a-z0-9_]+/`.
# The four bounded families return before the loop, so only a family with no
# bound shows it. N10's probe family is what stops it.
cat > "$SEDS/mp11.sed" <<'SED'
/# BL-282-INDEX-DIGITS$/s|\[0-9\]+/')"|[0-9]+/; s/\\$key$/[a-z0-9_]+/')"|
SED
if mp_mutate MP11 "$SEDS/mp11.sed" BL-282-INDEX-DIGITS; then
  printf '%s\n' '_bl282_probe_family() { save_answer "probe_$key" "x"; }' >> "$MP_TGT"
  PD="$(newtmp)/proj"
  if ! _syntax_ok "$MP_TGT" || ! mk_project "$PD" "$MP_TGT"; then fail_ "MP11 setup" "could not build the mutant's probe fixture"; else
    wiz "$PD" --set-answer probe_anything "minted"; got_bad="$(jq_answer probe_anything "$PD")"
    if [ "$WIZ_RC" -eq 0 ] && [ "$got_bad" = "minted" ]; then
      pass "MP11 (MUTATION) — with the \$key widening restored probe_anything is MINTED (rc=$WIZ_RC): N10 is what stops it"
    else
      fail_ "MP11 (MUTATION)" "probe_anything rc=$WIZ_RC written=[$got_bad] — restoring the widening changed nothing N10 can see"
    fi
  fi
fi

# MP12 — THE REVIEW'S LINE-BY-LINE CHARSET: the `case` becomes the old
# `grep -E '^[a-z0-9_]+$'`, which passes a key if any one line does. The
# arms test membership with grep, line by line, so a key whose FIRST line
# is a real key is minted. N9 is what stops it. The second key is the
# control: the loop's `[[ =~ ]]` still refuses it (MP13 is its proof).
cat > "$SEDS/mp12.sed" <<'SED'
/# BL-282-KEY-CHARSET$/s/^\([[:space:]]*\)case .*\(  # BL-282-KEY-CHARSET\)$/\1printf '%s' "$key" | grep -E '^[a-z0-9_]+$' >\/dev\/null || return 1\2/
SED
NL_ARM="$(printf 'competency_security\nNOT')"
NL_FAM="$(printf 'NOT A KEY\ninput_1_name')"
if mp_mutate MP12 "$SEDS/mp12.sed" BL-282-KEY-CHARSET; then
  PD="$(newtmp)/proj"
  if ! mk_project "$PD" "$MP_TGT"; then fail_ "MP12 setup" "could not build the mutant's fixture"; else
    wiz "$PD" --set-answer "$NL_ARM" "minted"; rc_bad=$WIZ_RC; got_bad="$(jq_answer "$NL_ARM" "$PD")"
    wiz "$PD" --set-answer "$NL_FAM" "minted"; rc_ctl=$WIZ_RC
    if [ "$rc_bad" -eq 0 ] && [ "$got_bad" = "minted" ] && [ "$rc_ctl" -eq 1 ]; then
      pass "MP12 (MUTATION) — with the charset matched line by line 'competency_security<LF>NOT' is MINTED (rc=$rc_bad) while the loop's whole-string match still refuses 'NOT A KEY<LF>input_1_name': N9 is what stops it"
    else
      fail_ "MP12 (MUTATION)" "arm key rc=$rc_bad written=[$got_bad]; family key rc=$rc_ctl (want 1) — the mutation changed nothing N9 can see"
    fi
  fi
fi

# MP13 — BOTH line-by-line matches restored: MP12's charset and the family's
# `grep -E "^${pat}\$"`. With the charset `case` in place a key that passes it
# is one line, so the family's `[[ =~ ]]` alone is held twice and its single
# mutant is EQUIVALENT; this double mutant is how it is shown live. N9 is
# what stops it, on the key MP12 could not mint.
cat "$SEDS/mp12.sed" > "$SEDS/mp13.sed"
cat >> "$SEDS/mp13.sed" <<'SED'
/# BL-282-FAMILY-WHOLE$/s/\[\[ \$key =~ \^\${pat}\$ \]\]/printf '%s' "$key" | grep -E "^${pat}\\$" >\/dev\/null/
SED
if mp_mutate MP13 "$SEDS/mp13.sed" BL-282-KEY-CHARSET BL-282-FAMILY-WHOLE; then
  PD="$(newtmp)/proj"
  if ! mk_project "$PD" "$MP_TGT"; then fail_ "MP13 setup" "could not build the mutant's fixture"; else
    wiz "$PD" --set-answer "$NL_FAM" "minted"; got_bad="$(jq_answer "$NL_FAM" "$PD")"
    if [ "$WIZ_RC" -eq 0 ] && [ "$got_bad" = "minted" ]; then
      pass "MP13 (MUTATION, DOUBLE) — with both matches line by line 'NOT A KEY<LF>input_1_name' is MINTED (rc=$WIZ_RC): N9 is what stops it"
    else
      fail_ "MP13 (MUTATION)" "family key rc=$WIZ_RC written=[$got_bad] — the double mutation changed nothing N9 can see"
    fi
  fi
fi

# MP14 — the read-back's refusal discarded (`|| true`). A paused save then
# logs an amendment that never landed and prints [OK]. S4 is what stops it.
cat > "$SEDS/mp14.sed" <<'SED'
/# BL-282-READ-BACK$/s/ || {.*}\(  # BL-282-READ-BACK\)$/ || true\1/
SED
if mp_mutate MP14 "$SEDS/mp14.sed" BL-282-READ-BACK; then
  PD="$(newtmp)/proj"
  if ! mk_project "$PD" "$MP_TGT"; then fail_ "MP14 setup" "could not build the mutant's fixture"; else
    wiz_paused "$PD" --set-answer monthly_budget "$NEW_BUDGET"
    got="$(jq_answer monthly_budget "$PD")"
    n="$(jq_amend_n "$PD")"; case "$n" in ''|*[!0-9]*) n=0 ;; esac
    if [ "$WIZ_RC" -eq 0 ] && [ "$got" = "$OLD_BUDGET" ] && [ "$n" -eq 1 ] && grep -q '\[OK\]' "$PD/run.out"; then
      pass "MP14 (MUTATION) — with the read-back discarded a paused save logs amendments[0] and prints [OK] (rc=$WIZ_RC) while the answer is still [$got]: S4 is what stops it"
    else
      fail_ "MP14 (MUTATION)" "rc=$WIZ_RC answer=[$got] amendments=$n — discarding the read-back changed nothing S4 can see"
    fi
  fi
fi

# MP15 — the re-render's refusal discarded (`|| true` on `# BL-282-RERENDER`):
# a failed render then ends in [OK] at exit 0. S7 is what stops it.
cat > "$SEDS/mp15.sed" <<'SED'
/# BL-282-RERENDER$/s/ || {.*}\(  # BL-282-RERENDER\)$/ || true\1/
SED
if mp_mutate MP15 "$SEDS/mp15.sed" BL-282-RERENDER; then
  PD="$(newtmp)/proj"
  if ! mk_project "$PD" "$MP_TGT"; then fail_ "MP15 setup" "could not build the mutant's fixture"; else
    python3 -c 'import io,json,sys; p=sys.argv[1]; d=json.load(io.open(p)); d["completed_sections"]="1, 2"; io.open(p,"w").write(json.dumps(d))' "$PD/.claude/intake-progress.json"
    wiz "$PD" --set-answer monthly_budget "$NEW_BUDGET"
    if [ "$WIZ_RC" -eq 0 ] && [ "$(ok_lines "$PD")" -ge 1 ] && ! grep -q -F "$NEW_BUDGET" "$PD/PROJECT_INTAKE.md"; then
      pass "MP15 (MUTATION) — with the re-render's refusal discarded a failed render prints [OK] at exit 0 and PROJECT_INTAKE.md never gains the row: S7 is what stops it"
    else
      fail_ "MP15 (MUTATION)" "rc=$WIZ_RC [OK] lines=$(ok_lines "$PD") — discarding the refusal changed nothing S7 can see"
    fi
  fi
fi

# MP16–MP19 — each array bound loosened from a whole-line match to a
# substring one: `grep -x --` becomes `grep --`, so a truncated real key such
# as gate_phase_0 is minted. N3 and N8's substring keys are what stop them.
# xdrop_mutant <id> <marker> <substring key> <real key>
xdrop_mutant() {
  local id="$1" marker="$2" bad_k="$3" ok_k="$4" pd rc_bad got_bad rc_ok
  printf '/# %s$/s/| grep -x -- /| grep -- /\n' "$marker" > "$SEDS/$id.sed"
  mp_mutate "$id" "$SEDS/$id.sed" "$marker" || return 0
  pd="$(newtmp)/proj"
  if ! mk_project "$pd" "$MP_TGT"; then fail_ "$id setup" "could not build the mutant's fixture"; return 0; fi
  wiz "$pd" --set-answer "$bad_k" "minted"; rc_bad=$WIZ_RC; got_bad="$(jq_answer "$bad_k" "$pd")"
  wiz "$pd" --set-answer "$ok_k" "ok"; rc_ok=$WIZ_RC
  if [ "$rc_bad" -eq 0 ] && [ "$got_bad" = "minted" ] && [ "$rc_ok" -eq 0 ]; then
    pass "$id (MUTATION) — with '$marker' matching substrings $bad_k is MINTED (rc=$rc_bad) while $ok_k still works: N3/N8 is what stops it"
  else
    fail_ "$id (MUTATION)" "$bad_k rc=$rc_bad written=[$got_bad]; $ok_k rc=$rc_ok — the substring match changed nothing N3/N8 can see"
  fi
}
xdrop_mutant MP16 BL-282-COMPETENCY-DOMAINS competency_sec competency_security
xdrop_mutant MP17 BL-282-GATE-KEYS gate_phase_0 gate_phase_0_to_phase_1
xdrop_mutant MP18 BL-282-INFRA-KEYS infra_sso infra_ci_cd_platform
xdrop_mutant MP19 BL-282-ESCALATION-KEYS escalation_level escalation_level_2

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] && exit 0
exit 1
