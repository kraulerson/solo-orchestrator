#!/usr/bin/env bash
# tests/test-brownfield-wp12a-assessment.sh — WP12a: Act 3's prompt and Act 4's
# shell finisher.
#
# SPEC: ADOPT-002-ARCH v2 §8.3 (the record and its refusals), §8.5 (the resume
# branch), §5.2/§5.3/§5.5 and §10-WP12a. Backlog: `## BL-242:`.
#
# EVERY PROOF DRIVES THE FINISHER WITH A HAND-WRITTEN RECORD ON A REAL ADOPTED
# FIXTURE — the model is never in the loop (§10-WP12a). What a model would write
# is exactly what these fixtures write by hand.
#
# WHAT EACH CASE OWNS.
#   K1  resume.sh on an adopted, unassessed project prints the ASSESSMENT
#       prompt — naming the record's path and the finisher command — and not
#       the intake, kickoff or classic prompt
#   K2  a valid record: the assessment merges into the stamp, the
#       classification reaches process-state THROUGH adopt_persist_phase1_artifacts,
#       the answers land under wizard keys, an audit row is written, and the
#       project is still at phase 0
#   K3  each of §8.3's refusals refuses AND writes nothing
#   K4  a second run is refused: the assessment is recorded once
#   K5  after the assessment, resume.sh opens a Phase-0 entry — never the
#       assessment prompt again, never the classic resume prompt
#   K6  a halt after `verdict` leaves no assessment block, and resume.sh
#       offers the assessment again (the merge is LAST)
#   K7  the stage order is data, and the intake write needs a classification
#   K8  every wizard key the prompt names resolves in intake-wizard.sh
#   K9  the core merge refuses a second assessment and an unadopted project
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

echo "== WP12a — the assessment prompt and the Act 4 finisher =="

for t in git jq; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done

WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT

# _adopted DIR — a real adoption of a small project, personal tier.
_adopted() {
  local p="$1"
  mkdir -p "$p/src" || return 1
  ( cd "$p" && git init -q . && git config user.email wp12a@test.invalid && git config user.name "WP12a Test" ) >/dev/null 2>&1 || return 1
  printf '{"name":"acme","scripts":{"test":"exit 0"}}\n' > "$p/package.json"
  printf '# acme\n' > "$p/README.md"
  ( cd "$p" && git add package.json README.md && git commit -q --no-verify -m "chore: their history" ) >/dev/null 2>&1 || return 1
  printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n' > "$WORK/ans"
  ( cd "$p" && bash "$REPO_ROOT/scripts/adopt-project.sh" < "$WORK/ans" ) > "$WORK/adopt.out" 2>&1
}
# _record DIR [JQ-EDIT] — a valid hand-written record and verdict, then edited.
_record() {
  local p="$1" edit="${2:-.}" commit
  commit="$(jq -r '.adoption.adoptedAtCommit' "$p/.claude/manifest.json")"
  jq -n --arg c "$commit" '{
    schemaVersion: 1, assessedAt: "2026-09-24T12:00:00Z", adoptedAtCommit: $c,
    interview: { users: "three people in one office", availability: "office hours",
                 exposure: "internal network only", scalability: "none expected",
                 dataClassification: "internal", zdrAttested: true, zdrReason: "",
                 inProduction: true, operations: {},
                 answers: { users_launch: "3", uptime: "business hours", accessibility_target: "WCAG 2.1 AA" } },
    evaluators: [],
    fitness: { verdict: "keep",
               findings: [ { id: "F1", requirementRef: "interview.users", severity: "SEV-4",
                             evidence: "package.json", reasoning: "three users need no more" } ] },
    plan: { path: "docs/phase-0/adoption-plan.md", summary: "continue from phase 0" },
    verdictArtifact: ".claude/adoption/verdict.md" }' | jq "$edit" > "$p/.claude/adoption/assessment-record.json"
  cat > "$p/.claude/adoption/verdict.md" <<'V'
# Adoption verdict

The stack fits the stated requirements: three users, office hours, internal only.

## Plain English

What happened: the project was assessed.
Recommendation: keep it.
Reason: it does what three people need.
If you do nothing: it stays at phase 0.
V
}
_finish() {   # _finish DIR TAG — sets RUN_RC
  ( cd "$1" && bash "$REPO_ROOT/scripts/adopt-project.sh" --act4 --root . ) > "$WORK/$2.out" 2>&1
  RUN_RC=$?
}
_resume() { ( cd "$1" && bash scripts/resume.sh 2>&1 ) | sed 's/\x1b\[[0-9;]*m//g'; }
_state() {  # a fingerprint of everything the finisher may write
  ( cd "$1" && cat .claude/manifest.json .claude/process-state.json .claude/intake-progress.json .claude/bypass-audit.json 2>/dev/null ) | shasum -a 256 | cut -c1-64
}

P="$WORK/p"
_adopted "$P" || { fail_ "setup" "the adoption did not complete: $(tail -3 "$WORK/adopt.out")"; }

k1() {
  local label="K1 resume on adopted-unassessed prints the ASSESSMENT prompt" out bad=""
  out="$(_resume "$P")"
  printf '%s\n' "$out" | grep -q 'You are running its ASSESSMENT' || bad="$bad [not the assessment prompt]"
  printf '%s\n' "$out" | grep -qF '.claude/adoption/assessment-record.json' || bad="$bad [the record's path is not named]"
  printf '%s\n' "$out" | grep -qF -- '--act4 --root .' || bad="$bad [the finisher command is not named]"
  printf '%s\n' "$out" | grep -q 'We are resuming work on this project' && bad="$bad [the classic prompt fired]"
  printf '%s\n' "$out" | grep -q 'begin Phase 0 from it\|walk me$' && bad="$bad [a Phase-0 entry fired before the assessment]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

k3() {
  local label="K3 each §8.3 refusal refuses and writes nothing" bad="" before e name
  while IFS='|' read -r name e; do
    [ -n "$name" ] || continue
    _record "$P" "$e"
    before="$(_state "$P")"
    _finish "$P" "k3"
    [ "$RUN_RC" -ne 0 ] || bad="$bad [$name: rc 0]"
    [ "$(_state "$P")" = "$before" ] || bad="$bad [$name: something was written]"
  done <<CASES
no requirementRef|.fitness.findings[0] |= del(.requirementRef)
requirementRef names no axis|.fitness.findings[0].requirementRef = "taste"
wrong commit|.adoptedAtCommit = "0000000000000000000000000000000000000000"
schemaVersion not 1|.schemaVersion = 2
verdictArtifact elsewhere|.verdictArtifact = "verdict.md"
verdict not keep or rebuild|.fitness.verdict = "maybe"
findings not a list|.fitness.findings = "none"
evaluators not a list|.evaluators = "none"
classification an array|.interview.dataClassification = ["pii","financial"]
internal with no ZDR attestation or reason|.interview.zdrAttested = false
requirementRef with a trailing newline|.fitness.findings[0].requirementRef = "interview.users\n"
answer key a gate reads|.interview.answers.project_name = "evil-name"
answer key outside the allowlist|.interview.answers.not_a_wizard_key = "z"
answer value not a string|.interview.answers.uptime = 99
inProduction absent|.interview |= del(.inProduction)
inProduction not boolean|.interview.inProduction = "yes"
classification outside taxonomy|.interview.dataClassification = "secret"
CASES
  # An EMPTY record: jq reads no document and exits 0.
  _record "$P"; : > "$P/.claude/adoption/assessment-record.json"
  before="$(_state "$P")"; _finish "$P" "k3e"
  { [ "$RUN_RC" -ne 0 ] && [ "$(_state "$P")" = "$before" ]; } || bad="$bad [an empty record was accepted]"
  # Two records in one file.
  _record "$P"; cat "$P/.claude/adoption/assessment-record.json" "$P/.claude/adoption/assessment-record.json" > "$WORK/two.json"
  cp "$WORK/two.json" "$P/.claude/adoption/assessment-record.json"
  before="$(_state "$P")"; _finish "$P" "k3d"
  { [ "$RUN_RC" -ne 0 ] && [ "$(_state "$P")" = "$before" ]; } || bad="$bad [two concatenated records were accepted]"
  # The verdict's two halves.
  _record "$P"; printf '# Only a technical account\n\nIt fits.\n' > "$P/.claude/adoption/verdict.md"
  before="$(_state "$P")"; _finish "$P" "k3v1"
  { [ "$RUN_RC" -ne 0 ] && [ "$(_state "$P")" = "$before" ]; } || bad="$bad [a verdict with no Plain English half was accepted]"
  _record "$P"; sed -i.bak '/^Reason:/d' "$P/.claude/adoption/verdict.md"; rm -f "$P/.claude/adoption/verdict.md.bak"
  before="$(_state "$P")"; _finish "$P" "k3v2"
  { [ "$RUN_RC" -ne 0 ] && [ "$(_state "$P")" = "$before" ]; } || bad="$bad [a recommendation with no reason was accepted]"
  _record "$P"; sed -i.bak '/^Recommendation:/d' "$P/.claude/adoption/verdict.md"; rm -f "$P/.claude/adoption/verdict.md.bak"
  before="$(_state "$P")"; _finish "$P" "k3v3"
  { [ "$RUN_RC" -ne 0 ] && [ "$(_state "$P")" = "$before" ]; } || bad="$bad [a reason with no recommendation was accepted]"
  _record "$P"; printf '## Plain English\n\nRecommendation: keep it.\nReason: it fits.\n' > "$P/.claude/adoption/verdict.md"
  before="$(_state "$P")"; _finish "$P" "k3v4"
  { [ "$RUN_RC" -ne 0 ] && [ "$(_state "$P")" = "$before" ]; } || bad="$bad [a verdict with no technical account was accepted]"
  # An intake file the prefill could not edit is caught BEFORE any write.
  _record "$P"; cp "$P/.claude/intake-progress.json" "$WORK/ip.bak"; printf '[]\n' > "$P/.claude/intake-progress.json"
  before="$(_state "$P")"; _finish "$P" "k3i"
  { [ "$RUN_RC" -ne 0 ] && [ "$(_state "$P")" = "$before" ]; } || bad="$bad [a non-object intake-progress.json let the classification be written first]"
  cp "$WORK/ip.bak" "$P/.claude/intake-progress.json"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

k6() {
  local label="K6 a halt after 'verdict' merges nothing, and resume re-offers the assessment" bad=""
  _record "$P"
  ( cd "$P" && SOIF_ADOPT_ACT4_HALT_AFTER=verdict bash "$REPO_ROOT/scripts/adopt-project.sh" --act4 --root . ) > "$WORK/k6.out" 2>&1
  jq -e '.adoption.assessment == null' "$P/.claude/manifest.json" >/dev/null 2>&1 || bad="$bad [an assessment block exists after a halt before merge]"
  _resume "$P" | grep -q 'You are running its ASSESSMENT' || bad="$bad [resume did not re-offer the assessment]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

k2() {
  local label="K2 a valid record is merged, classified, pre-filled and audited; phase stays 0" bad=""
  _record "$P"
  _finish "$P" "k2"
  [ "$RUN_RC" -eq 0 ] || { fail_ "$label" "rc $RUN_RC: $(tail -5 "$WORK/k2.out" | tr '\n' ' ')"; return; }
  jq -e '.adoption.assessment.verdict == "keep" and .adoption.assessment.inProduction == true and .adoption.adopted == true' \
    "$P/.claude/manifest.json" >/dev/null 2>&1 || bad="$bad [the assessment block is not in the manifest]"
  [ "$(jq -r '.phase1_artifacts.data_classification' "$P/.claude/process-state.json")" = "internal" ] || bad="$bad [the classification did not reach process-state]"
  jq -e '.answers.users_launch == "3" and .answers.accessibility_target == "WCAG 2.1 AA" and .answers.data_classification == "internal"' \
    "$P/.claude/intake-progress.json" >/dev/null 2>&1 || bad="$bad [the answers are not in intake-progress under wizard keys]"
  jq -e '[.[] | select(.type == "adoption_event" and .details.event == "assessment")] | length == 1' \
    "$P/.claude/bypass-audit.json" >/dev/null 2>&1 || bad="$bad [no assessment audit row]"
  [ "$(jq -r '.current_phase' "$P/.claude/phase-state.json")" = "0" ] || bad="$bad [current_phase moved]"
  [ ! -e "$P/PRODUCT_MANIFESTO.md" ] || bad="$bad [PRODUCT_MANIFESTO.md was written]"
  # THE CALL, not a mention: a comment naming the function would satisfy a
  # plain grep while an inline re-implementation did the writing.
  grep -qE '^[[:space:]]*adopt_persist_phase1_artifacts "\$root"' "$REPO_ROOT/scripts/lib/adopt/adopt-act4.sh" \
    || bad="$bad [the classification is not written through adopt_persist_phase1_artifacts]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

k4() {
  local label="K4 a second run is refused — the assessment is recorded once" before
  before="$(jq -c .adoption.assessment "$P/.claude/manifest.json")"
  _finish "$P" "k4"
  if [ "$RUN_RC" -ne 0 ] && [ "$(jq -c .adoption.assessment "$P/.claude/manifest.json")" = "$before" ]; then pass "$label"
  else fail_ "$label" "rc $RUN_RC"; fi
}

k5() {
  local label="K5 after the assessment, resume opens a Phase-0 entry" out bad=""
  out="$(_resume "$P")"
  printf '%s\n' "$out" | grep -q 'You are running its ASSESSMENT' && bad="$bad [the assessment prompt fired again]"
  printf '%s\n' "$out" | grep -q 'We are resuming work on this project' && bad="$bad [the classic prompt fired]"
  printf '%s\n' "$out" | grep -qiE 'intake|phase 0' || bad="$bad [no Phase-0 entry]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

k7() {
  local label="K7 the order is data, and the intake write needs a classification" bad="" order q="$WORK/nodc"
  order="$( ( set +u; . "$REPO_ROOT/scripts/lib/adopt/adopt-act4.sh" >/dev/null 2>&1; _adopt_act4_order ) | tr '\n' ' ')"
  [ "$order" = "validate_record classification prefill_intake verdict documents merge " ] || bad="$bad [order is: $order]"
  mkdir -p "$q/.claude/adoption"
  printf '{}\n' > "$q/.claude/process-state.json"
  printf '{"interview":{"answers":{"uptime":"x"}}}\n' > "$q/.claude/adoption/assessment-record.json"
  ( set +u
    for l in adopt-core adopt-act4; do . "$REPO_ROOT/scripts/lib/adopt/$l.sh" >/dev/null 2>&1; done
    _adopt_act4_prefill "$q" ) >/dev/null 2>&1 && bad="$bad [the intake write ran with no classification on record]"
  [ ! -e "$q/.claude/intake-progress.json" ] || bad="$bad [intake-progress.json was written]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

k8() {
  local label="K8 the answer allowlist is what the prompt names, and every key resolves in intake-wizard.sh" bad="" k keys
  keys="$( ( set +u; . "$REPO_ROOT/scripts/lib/adopt/adopt-act4.sh" >/dev/null 2>&1; printf '%s' "$ADOPT_ACT4_ANSWER_KEYS" ) )"
  [ -n "$keys" ] || { fail_ "$label" "no allowlist"; return; }
  grep -qF "$keys" "$P/.claude/adoption/assessment-prompt.md" || bad="$bad [the prompt does not list the allowlist verbatim]"
  for k in $keys; do
    grep -qE "save_answer +\"$k\"" "$REPO_ROOT/scripts/intake-wizard.sh" || bad="$bad [$k is not a wizard key]"
  done
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

k9() {
  local label="K9 the core merge itself records once, and never for an unadopted project" bad="" m="$WORK/m.json"
  # The finisher refuses a second run before it reaches the merge, so K4 alone
  # would pass with the merge's own guard deleted. This drives the core writer.
  printf '{"adoption":{"adopted":true,"adoptedAtCommit":"abc"}}\n' > "$m"
  ( . "$REPO_ROOT/scripts/lib/adoption-stamp.sh"; soif_adoption_assess "$m" '{"verdict":"keep"}' ) || bad="$bad [the first merge was refused]"
  ( . "$REPO_ROOT/scripts/lib/adoption-stamp.sh"; soif_adoption_assess "$m" '{"verdict":"rebuild"}' ) && bad="$bad [a second merge was accepted]"
  [ "$(jq -r '.adoption.assessment.verdict' "$m")" = "keep" ] || bad="$bad [the first verdict was overwritten]"
  printf '{"project":"x"}\n' > "$m"
  ( . "$REPO_ROOT/scripts/lib/adoption-stamp.sh"; soif_adoption_assess "$m" '{"verdict":"keep"}' ) && bad="$bad [an unadopted project was assessed]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

k10() {
  local label="K10 inProduction false is accepted, and a refusal after a write says what was written" bad="" q="$WORK/q"
  _adopted "$q" || { fail_ "$label" "setup"; return; }
  # A halt after the classification stage: something WAS written, and the
  # refusal must not say "did not begin" (review: it did, over a changed file).
  _record "$q" '.interview.inProduction = false'
  ( cd "$q" && SOIF_ADOPT_ACT4_HALT_AFTER=classification bash "$REPO_ROOT/scripts/adopt-project.sh" --act4 --root . ) > "$WORK/k10h.out" 2>&1
  grep -q 'did not begin' "$WORK/k10h.out" && bad="$bad [a refusal after the classification write claims nothing was written]"
  grep -q 'already written' "$WORK/k10h.out" || bad="$bad [the refusal does not say what was written]"
  _finish "$q" "k10"
  [ "$RUN_RC" -eq 0 ] || bad="$bad [inProduction false was refused: $(grep -- '- ' "$WORK/k10.out" | head -2 | tr '\n' ' ')]"
  jq -e '.adoption.assessment.inProduction == false' "$q/.claude/manifest.json" >/dev/null 2>&1 || bad="$bad [inProduction false is not recorded as false]"
  [ "$(jq -r '.answers.data_classification' "$q/.claude/intake-progress.json")" = "internal" ] \
    || bad="$bad [the recorded classification is not in the intake answers]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

k11() {
  local label="K11 past phase 0, an unassessed adoptee is NOT sent back to the assessment" q="$WORK/q4"
  # Nothing makes the assessment a precondition for the gates, so an adoptee can
  # move on without one; at phase 4 this branch would replace the shipped-
  # product greeting with "before starting Phase 0" for good (review).
  _adopted "$q" || { fail_ "$label" "setup"; return; }
  jq '.current_phase = 4' "$q/.claude/phase-state.json" > "$q/ps.tmp" && mv "$q/ps.tmp" "$q/.claude/phase-state.json"
  if _resume "$q" | grep -q 'You are running its ASSESSMENT'; then fail_ "$label" "the assessment prompt fired at phase 4"
  else pass "$label"; fi
}

k1; k3; k6; k2; k4; k5; k7; k8; k9; k10; k11

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
