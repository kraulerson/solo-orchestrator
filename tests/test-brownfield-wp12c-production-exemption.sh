#!/usr/bin/env bash
# tests/test-brownfield-wp12c-production-exemption.sh — WP12c: the
# adopted-in-production exemption (R2, Karl 2026-09-17).
#
# SPEC: ADOPT-002-ARCH v2.2 §3.6, §8.5 and §10-WP12c. An adopted project whose
# assessment records `inProduction: true` may open a delta below phase 4, with
# the exemption written into the delta record and into process-state, so a live
# incident keeps its hotfix retro. Nobody else is loosened, and no phase gate is
# touched. Backlog: `## BL-242:`.
#
# FIXTURES (§10-WP12c's): F1 adopted, assessed in production, phase 0; F2 the
# same, NOT in production; F2b assessed before the question existed (no key);
# F3 in production recorded but NOT adopted; F4 not adopted, at phase 4.
#
# WHAT EACH CASE OWNS.
#   E1  (a)+(d)+(h) F1 opens a hotfix: the exemption is in the delta record AND
#       in process-state, and the retro is still booked
#   E2  (b) F2, F2b and F3 are refused with exit 3, exactly as before
#   E3  (c) F4 opens with NO exemption field
#   E4  (e) resume: F1 with an open delta gets the resume-that-work prompt and
#       not the Phase 0 entry; F1 with nothing open gets a Phase 0 entry and
#       never the post-release greeting
#   E5  (f) validate: no "one of the two records is wrong" under the exemption,
#       an INFO naming it instead
#   E6  (g) the phase gate's output is byte-identical before and after the open
#   E7  (i) the delta boundary lint is green
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

echo "== WP12c — the adopted-in-production exemption =="
for t in git jq; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done
WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT
S="$REPO_ROOT/scripts"

# _proj DIR PHASE MANIFEST_JSON — a project directory with the state files the
# delta track and the readers use.
_proj() {
  local d="$1"
  mkdir -p "$d/.claude"
  ( cd "$d" && git init -q . && git config user.email wp12c@test.invalid && git config user.name "WP12c Test" ) >/dev/null 2>&1
  printf '{"track":"light","deployment":"personal","poc_mode":null,"current_phase":%s,"phases":{}}\n' "$2" > "$d/.claude/phase-state.json"
  printf '%s\n' "$3" > "$d/.claude/manifest.json"
  printf '{}\n' > "$d/.claude/process-state.json"
  printf '# BUGS\n\n| # | Severity | Title |\n|---|---|---|\n' > "$d/BUGS.md"
  printf '# Changelog\n\n## [Unreleased]\n\n### Fixed\n' > "$d/CHANGELOG.md"
  printf '# CLAUDE.md\n' > "$d/CLAUDE.md"   # validate.sh stops at once without one
}
_open() {   # _open DIR — open a hotfix; echo the rc
  ( cd "$1" && unset GITHUB_BASE_REF; bash "$S/delta.sh" --open --describe "checkout is down in production right now" \
      --class hotfix --slug checkout --confirm </dev/null ) > "$1.open.out" 2>&1
  printf '%s' "$?"
}
_state() { ( cd "$1" && bash "$S/process-checklist.sh" --delta-state-read </dev/null 2>/dev/null ); }

ADOPTED_PROD='{"host":"github","adoption":{"adopted":true,"adoptedAtCommit":"abc","assessment":{"verdict":"keep","inProduction":true}}}'
ADOPTED_NOTPROD='{"host":"github","adoption":{"adopted":true,"adoptedAtCommit":"abc","assessment":{"verdict":"keep","inProduction":false}}}'
ADOPTED_NOKEY='{"host":"github","adoption":{"adopted":true,"adoptedAtCommit":"abc","assessment":{"verdict":"keep"}}}'
LOOSE_TYPES='{"host":"github","adoption":{"adopted":"true","adoptedAtCommit":"abc","assessment":{"verdict":"keep","inProduction":1}}}'
NOT_ADOPTED_PROD='{"host":"github","adoption":{"assessment":{"inProduction":true}}}'
PLAIN='{"host":"github"}'

F1="$WORK/f1"; _proj "$F1" 0 "$ADOPTED_PROD"
( cd "$F1" && bash "$S/check-phase-gate.sh" </dev/null 2>&1 ) | sed 's/\x1b\[[0-9;]*m//g' > "$WORK/gate-before.txt"
F1RC="$(_open "$F1")"

e1() {
  local label="E1 F1 (adopted, in production, phase 0) opens a hotfix, recorded twice, retro still booked" bad="" doc id
  [ "$F1RC" -eq 0 ] || { fail_ "$label" "rc $F1RC: $(tail -3 "$F1.open.out" | tr '\n' ' ')"; return; }
  doc="$(_state "$F1")"
  id="$(printf '%s\n' "$doc" | jq -r '.active_delta.id // ""')"
  [ -n "$id" ] || bad="$bad [no open delta]"
  [ "$(printf '%s\n' "$doc" | jq -r '.active_delta.exemption // ""')" = "adopted-in-production" ] || bad="$bad [the delta record lacks the exemption]"
  jq -e --arg id "$id" '.adoption_exemptions | length == 1 and .[0].delta_id == $id and .[0].kind == "adopted-in-production" and .[0].current_phase == 0' \
    "$F1/.claude/process-state.json" >/dev/null 2>&1 || bad="$bad [process-state does not record the exemption against $id]"
  printf '%s\n' "$doc" | jq -e --arg id "$id" '[.hotfix_retros[]? | select(.id == $id and .due_by != null)] | length == 1' >/dev/null 2>&1 \
    || bad="$bad [the hotfix retro was not booked]"
  grep -q 'adopted-in-production exemption' "$F1.open.out" || bad="$bad [the run does not say which exemption opened it]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

e2() {
  local label="E2 not in production, never asked, not adopted, or not booleans: refused with exit 3" bad="" d m rc
  # f5: truthy but NOT boolean values — "== true and nothing looser" (review:
  # a mutant reading them as truthy passed every case before this row).
  for d in f2:"$ADOPTED_NOTPROD" f2b:"$ADOPTED_NOKEY" f3:"$NOT_ADOPTED_PROD" f5:"$LOOSE_TYPES"; do
    m="${d#*:}"; d="$WORK/${d%%:*}"
    _proj "$d" 0 "$m"
    rc="$(_open "$d")"
    [ "$rc" -eq 3 ] || bad="$bad [$(basename "$d"): rc $rc, not 3]"
    [ -z "$(_state "$d" | jq -r '.active_delta.id // ""' 2>/dev/null)" ] || bad="$bad [$(basename "$d"): a delta is open]"
    jq -e '.adoption_exemptions == null' "$d/.claude/process-state.json" >/dev/null 2>&1 || bad="$bad [$(basename "$d"): an exemption was recorded]"
  done
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

e3() {
  local label="E3 F4 (phase 4, not adopted) opens with NO exemption field" bad="" d="$WORK/f4" rc
  _proj "$d" 4 "$PLAIN"
  rc="$(_open "$d")"
  [ "$rc" -eq 0 ] || { fail_ "$label" "rc $rc"; return; }
  [ "$(_state "$d" | jq -r '.active_delta | has("exemption")')" = "false" ] || bad="$bad [a phase-4 delta carries an exemption]"
  jq -e '.adoption_exemptions == null' "$d/.claude/process-state.json" >/dev/null 2>&1 || bad="$bad [an exemption was recorded]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

e4() {
  local label="E4 resume: an open exempt delta outranks Phase 0; with none, no post-release greeting" bad="" d="$WORK/f1b"
  ( cd "$F1" && bash "$S/resume.sh" 2>&1 ) | sed 's/\x1b\[[0-9;]*m//g' > "$WORK/r1.out"
  grep -q 'We are resuming a piece of post-release work' "$WORK/r1.out" || bad="$bad [F1 with an open delta did not get the resume-that-work prompt]"
  grep -q "$(_state "$F1" | jq -r .active_delta.id)" "$WORK/r1.out" || bad="$bad [the prompt does not name the delta]"
  _proj "$d" 0 "$ADOPTED_PROD"
  printf '# Project Intake\n\n## 13. Agent Initialization Prompt\n\n```\nStart Phase 0.\n```\n' > "$d/PROJECT_INTAKE.md"
  ( cd "$d" && bash "$S/resume.sh" 2>&1 ) | sed 's/\x1b\[[0-9;]*m//g' > "$WORK/r2.out"
  grep -q 'This product has shipped' "$WORK/r2.out" && bad="$bad [the post-release greeting fired below phase 4]"
  grep -q 'We are resuming a piece of post-release work' "$WORK/r2.out" && bad="$bad [a resume-that-work prompt with nothing open]"
  grep -q 'Start Phase 0.' "$WORK/r2.out" || bad="$bad [F1 with nothing open did not get its Phase 0 entry]"
  # And where the BL-202 branches FALL THROUGH — a manifesto exists — the
  # delta block is reached; below phase 4 with nothing open it must still not
  # greet (the fixture above never reaches it: its intake answers first).
  printf '# Product Manifesto\n' > "$d/PRODUCT_MANIFESTO.md"
  ( cd "$d" && bash "$S/resume.sh" 2>&1 ) | sed 's/\x1b\[[0-9;]*m//g' > "$WORK/r3.out"
  grep -q 'This product has shipped' "$WORK/r3.out" && bad="$bad [the post-release greeting fired below phase 4 once the manifesto exists]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

e5() {
  local label="E5 validate: an INFO naming the exemption, not 'one of the two records is wrong'" bad=""
  ( cd "$F1" && bash "$S/validate.sh" 2>&1 ) | sed 's/\x1b\[[0-9;]*m//g' > "$WORK/v.out"
  # REACHED, or the absence below proves nothing: validate stops at once in a
  # directory with no CLAUDE.md, and printed neither line then (first cut).
  grep -q 'Approval Log' "$WORK/v.out" || { fail_ "$label" "validate.sh never reached its later sections: $(head -3 "$WORK/v.out" | tr '\n' ' ')"; return; }
  grep -q 'One of the two records is wrong' "$WORK/v.out" && bad="$bad [the era warning fired under the exemption]"
  grep -q 'under the adopted-in-production exemption' "$WORK/v.out" || bad="$bad [no INFO names the exemption]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

e6() {
  local label="E6 the phase gate's output is byte-identical before and after the exempt open"
  ( cd "$F1" && bash "$S/check-phase-gate.sh" </dev/null 2>&1 ) | sed 's/\x1b\[[0-9;]*m//g' > "$WORK/gate-after.txt"
  if cmp -s "$WORK/gate-before.txt" "$WORK/gate-after.txt"; then pass "$label"
  else fail_ "$label" "$(diff "$WORK/gate-before.txt" "$WORK/gate-after.txt" | head -4 | tr '\n' ' ')"; fi
}

e7() {
  local label="E7 the delta boundary lint is green on the amended readers" out
  out="$(bash "$S/lint-delta-boundary.sh" 2>&1)"
  if [ "$?" -eq 0 ]; then pass "$label"; else fail_ "$label" "$(printf '%s' "$out" | tail -2 | tr '\n' ' ')"; fi
}

e1; e2; e3; e4; e5; e6; e7
echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
