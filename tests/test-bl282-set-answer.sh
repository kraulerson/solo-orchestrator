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

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }
_changed_lines() { local n; n=$(diff "$1" "$2" 2>/dev/null | grep -c '^[<>]'); case "$n" in ''|*[!0-9]*) n=0 ;; esac; printf '%s\n' "$n"; }
_syntax_ok() { bash "-n" "$1" 2>/dev/null; }
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
  ( cd "$d" && bash scripts/intake-wizard.sh "$@" ) >"$d/run.raw" 2>&1 </dev/null
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
  before_p="$(_cksum "$N3/.claude/intake-progress.json")"
  wiz "$N3" --set-answer competency_zzz "minted"
  after_p="$(_cksum "$N3/.claude/intake-progress.json")"
  got="$(jq_answer competency_zzz "$N3")"
  if [ "$WIZ_RC" -eq 1 ] && [ "$got" = "<<unset>>" ] && [ "$before_p" = "$after_p" ]; then
    pass "N3 — competency_zzz is refused (rc=$WIZ_RC), mints nothing, file byte-identical"
  else
    fail_ "N3" "rc=$WIZ_RC (want 1); competency_zzz=[$got] (want unset); file $([ "$before_p" = "$after_p" ] && echo unchanged || echo CHANGED)"
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

echo "=== M — mutation proofs on a mirror ==="

for mark in BL-282-SET-ANSWER-BEGIN BL-282-SET-ANSWER-END BL-282-KEY-REFUSE BL-282-RERENDER BL-282-HINT-COUNT BL-282-WRITE-STATUS BL-282-COMPETENCY-DOMAINS; do
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

# MP4 — discard the write's status again: the guard becomes `|| true`. The
# no-answers fixture then reports success while writing no answer, which is
# the defect as it was found in the field. S1 is what stops it.
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
      if [ "$WIZ_RC" -eq 0 ] && [ "$ok_n" -ge 1 ] && [ "$got_ans" = "<<unset>>" ]; then
        pass "MP4 (MUTATION) — with the write's status discarded the wizard reports [OK] and exits 0 while no answer was written: S1 is what stops it"
      else
        fail_ "MP4 (MUTATION)" "rc=$WIZ_RC ok_lines=$ok_n answer=[$got_ans] — discarding the status changed nothing S1 can see"
      fi
    fi
  fi
fi

# MP5 — widen the family again: the competency arm stops matching, so the
# generic `$key` template admits any competency_* key. N3 is what stops it.
MP5="$(newtmp)/fw"
if ! mkdir -p "$MP5" || ! cp -Rp "$REPO_ROOT/scripts" "$MP5/"; then
  fail_ "MP5 setup" "could not mirror scripts/"
else
  tgt5="$MP5/scripts/intake-wizard.sh"; before5="$(mktemp)"; cp "$tgt5" "$before5"
  d_ln="$(grep -n 'BL-282-COMPETENCY-DOMAINS' "$before5" | head -1 | cut -d: -f1)"
  sed -e 's/^\([[:space:]]*\)competency_\*)\([[:space:]]*# BL-282-COMPETENCY-DOMAINS\)$/\1competency_NEVERMATCHES_*)\2/' "$before5" > "$tgt5"
  h_ln5="$(_hunk_line "$before5" "$tgt5")"
  if [ -z "$d_ln" ] || ! _syntax_ok "$tgt5" \
     || [ "$(_changed_lines "$before5" "$tgt5")" -ne 2 ] || [ "$h_ln5" != "$d_ln" ] \
     || ! sed -n "${d_ln}p" "$tgt5" | grep -q 'NEVERMATCHES'; then
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

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] && exit 0
exit 1
