#!/usr/bin/env bash
# tests/test-bl320-approval-schema2.sh — `## BL-320:` Solo's side of the
# Development Guardrails (CDF) 4.4.0 "approval design B".
#
# THE DEFECT. Guardrails 4.4.0 approves a commit only when the USER answers a
# question recorded in .claude/pending-approval.json with an option id, twice
# (record-approval.sh, a UserPromptSubmit hook, renders the staged change, then
# takes the pick). Solo wrote that question in schema 1 (`"A1: text"` strings),
# which 4.4.0 cannot take an answer to; so did the bypass detector; Solo's own
# commit check rendered a schema-2 question as "malformed — rm it"; a project
# brought to 4.4.0 by `refresh-guardrails.sh` / `upgrade-project.sh` never got
# record-approval.sh registered in .claude/settings.json; and init.sh pulled
# the shared clone without asking.
#
# CASES
#   W  the writer (pending-approval.sh, escalate-to-user.sh): schema 2, ids,
#      a "none" option, stage-then-ask, both schemas read, --resolve/--clear
#      cleanup, bypass decisions read from .claude/approvals.jsonl
#   D  the bypass detector's question: schema 2, answered by option id, its
#      audit rows bound to the question's sha256
#   G  pre-commit-gate.sh's hold: both schemas rendered, the answer route by
#      Guardrails version; upgrade-project.sh's hold (U1)
#   R  registering the Guardrails hook entries a project is missing (c2):
#      soif_cdf_register_hooks, refresh-guardrails.sh, upgrade-project.sh
#   V  the session start: the 4.4.0 minimum, and a missing registration
#   O  the out-of-band detector: matched=false is recorded once
#   I  init.sh's clone update: ask first (Enter = yes) at a terminal, never
#      without one; adoption's minimum note (A1)
#   E  the dogfood approval round trip (rows 20/21/23/29/30) against the REAL
#      Guardrails hooks — SKIPPED with a reason where no 4.4.0+ clone exists
#      (CI has none)
#   M  mutants: each rewrites ONE marked line in a mirror of the tree, checks
#      the edit landed and still parses, and needs a named case to go RED
#
# Hermetic: temp dirs only; fake clones and a local bare repository (never
# contacted over a network). The real-clone cases copy the clone's hooks into a
# fixture and never write to the clone. The Guardrails hooks keep their state
# in /tmp/.claude_*_<hash of the fixture path>; the EXIT trap removes exactly
# the files named for this run's fixtures. bash 3.2 safe.
set -uo pipefail
unset GITHUB_BASE_REF CDF_HOME SOIF_NONINTERACTIVE CI 2>/dev/null || true

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

for t in jq git; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done

# The real Guardrails clone, read BEFORE any case fakes HOME.
CDF_CLONE="${BL320_CDF_CLONE:-$HOME/.claude-dev-framework}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bl320.XXXXXX")"
HASHES=""
cleanup() {
  local h
  for h in $HASHES; do
    rm -f "/tmp/.claude_evaluated_$h" "/tmp/.claude_approval_shown_$h" "/tmp/.claude_eval_log_$h" \
          "/tmp/.claude_last_head_$h" "/tmp/.claude_superpowers_$h" "/tmp/.claude_plan_active_$h"
  done
  rm -rf "$WORK"
}
trap cleanup EXIT
newtmp() { mktemp -d "$WORK/tXXXXXX"; }
CASE_DETAIL=""

sha256_of() { { sha256sum "$1" 2>/dev/null || shasum -a 256 "$1"; } | awk '{print $1; exit}'; }
count_f() { printf '%s\n' "$1" | command grep -cF -- "$2"; }
has_f() { [ "$(count_f "$1" "$2")" -ge 1 ]; }
last3() { printf '%s\n' "$1" | tail -3 | tr '\n' '|'; }

# CDF's own reader of the question, copied from hooks/_helpers.sh
# pending_approval_info (4.4.0, aba947b). A schema-2 question Solo writes must
# leave .problems empty. The real reader is used too where a clone exists (W1).
CDF_INFO_JQ='
  def idok: type == "string" and test("^[A-Za-z][0-9]{1,2}$");
  if type == "object" and .schema == 2 then
    { schema: 2,
      question: (if (.question | type) == "string" then .question else "" end),
      opts: [ (.options // [])[]? | { id: (.id // "" | tostring),
                                       text: (if (.text | type) == "string" then .text else "" end),
                                       approves: (if .approves == "commit" then "commit" else "none" end) } ],
      rec: (.recommendation // "" | tostring) }
    | .problems = [ (if .question == "" then "the question is empty" else empty end),
                    (if (.opts | length) < 2 then "it has fewer than two options" else empty end),
                    (if any(.opts[]; (.id | idok) | not) then "an option id is not a letter and one or two digits (A1)" else empty end),
                    (if ([.opts[].id | ascii_upcase] | unique | length) != (.opts | length) then "option ids repeat" else empty end),
                    (if any(.opts[]; .approves == "none") | not then "no option approves nothing" else empty end) ]
  else { schema: (if type == "object" then (.schema // 1) else 0 end), opts: [], problems: ["it is not schema 2"] } end'
CDF_PROBLEMS=""
cdf_ok() {
  CDF_PROBLEMS="$(jq -r "$CDF_INFO_JQ"' | .problems | join("; ")' "$1" 2>/dev/null)" || { CDF_PROBLEMS="unreadable"; return 1; }
  [ -z "$CDF_PROBLEMS" ] || return 1
  if [ -f "$CDF_CLONE/hooks/_helpers.sh" ] && command grep -q 'pending_approval_info()' "$CDF_CLONE/hooks/_helpers.sh"; then
    CDF_PROBLEMS="$( ( . "$CDF_CLONE/hooks/_helpers.sh" >/dev/null 2>&1; pending_approval_info "$1" ) | jq -r '.problems | join("; ")' 2>/dev/null)"
    [ -z "$CDF_PROBLEMS" ] || { CDF_PROBLEMS="the real clone's reader: $CDF_PROBLEMS"; return 1; }
  fi
  return 0
}

# fx DIR [VERSION] — a project: a git repo with an origin remote (a local path,
# never contacted) and one commit; .claude/ with a manifest recording the
# Guardrails VERSION (NONE writes none) and an empty audit log.
fx() {
  local d="$1" v="${2:-4.4.0}"
  mkdir -p "$d/.claude" || return 1
  ( cd "$d" && git init -q && git config user.email t@t.local && git config user.name T \
      && git remote add origin "$d/../not-a-remote.git" \
      && printf 'seed\n' > seed.txt && git add seed.txt && git commit -q -m seed ) >/dev/null 2>&1 || return 1
  if [ "$v" != NONE ]; then
    jq -n --arg v "$v" '{frameworkVersion: $v, enforcement_level: "strict", activeHooks: ["enforce-evaluate"]}' \
      > "$d/.claude/manifest.json" || return 1
  fi
  printf '[]\n' > "$d/.claude/bypass-audit.json"
}
stage() { printf '%s\n' "${2:-change}" > "$1/${3:-a.txt}" && git -C "$1" add "${3:-a.txt}"; }
# pa ROOT DIR ARGS… — ROOT's pending-approval.sh, run in DIR. Sets PA_OUT, PA_RC.
PA_OUT=""; PA_RC=0
pa() {
  local r="$1" d="$2"; shift 2
  PA_RC=0
  PA_OUT="$( cd "$d" && bash "$r/scripts/pending-approval.sh" "$@" </dev/null 2>&1 )" || PA_RC=$?
}
SENT=".claude/pending-approval.json"
v1_sentinel() {
  jq -n '{question: "old style", options: ["A1: foo", "A2: bar"], recommendation: "A1", offered_at: "2026-10-01T00:00:00Z"}' > "$1/$SENT"
}
v2_sentinel() {
  jq -n '{schema: 2, question: "Commit the fix?",
          options: [{id: "A1", text: "Commit the staged fix", approves: "commit"},
                    {id: "A2", text: "Hold - do not commit", approves: "none"}],
          recommendation: "A1", offered_at: "2026-10-06T00:00:00Z"}' > "$1/$SENT"
}

# ── W: the writer ────────────────────────────────────────────────────────────
case_W1() {   # stage, then ask: schema 2, the approving option, CDF's reader accepts it
  local d f
  d="$(newtmp)/p"; fx "$d" || { CASE_DETAIL="fixture"; return 1; }
  stage "$d"
  pa "$1" "$d" --offer "Commit the fix?" --options "A1: Commit the staged fix" "A2: Hold - do not commit" --approves A1 --recommendation A1
  [ "$PA_RC" -eq 0 ] || { CASE_DETAIL="rc=$PA_RC: $(last3 "$PA_OUT")"; return 1; }
  f="$d/$SENT"
  jq -e '.schema == 2 and .question == "Commit the fix?" and .recommendation == "A1"
         and (.offered_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$"))
         and .options == [{"id":"A1","text":"Commit the staged fix","approves":"commit"},
                          {"id":"A2","text":"Hold - do not commit","approves":"none"}]' "$f" >/dev/null 2>&1 \
    || { CASE_DETAIL="shape: $(tr -d '\n' < "$f" 2>/dev/null)"; return 1; }
  cdf_ok "$f" || { CASE_DETAIL="CDF's reader rejects it: $CDF_PROBLEMS"; return 1; }
  has_f "$PA_OUT" "option id" || { CASE_DETAIL="the offer does not say how the user answers: $(last3 "$PA_OUT")"; return 1; }
}
case_W2() {   # a decision that approves nothing needs nothing staged
  local d
  d="$(newtmp)/p"; fx "$d" || { CASE_DETAIL="fixture"; return 1; }
  pa "$1" "$d" --offer "Merge or rebase?" --options "A1: Merge" "A2: Rebase" --recommendation A2
  [ "$PA_RC" -eq 0 ] || { CASE_DETAIL="rc=$PA_RC: $(last3 "$PA_OUT")"; return 1; }
  jq -e '.schema == 2 and ([.options[].approves] == ["none", "none"])' "$d/$SENT" >/dev/null 2>&1 \
    || { CASE_DETAIL="shape: $(tr -d '\n' < "$d/$SENT" 2>/dev/null)"; return 1; }
  cdf_ok "$d/$SENT" || { CASE_DETAIL="CDF's reader rejects it: $CDF_PROBLEMS"; return 1; }
}
# refused DIR WANT — the last pa run refused, wrote no question, and said WANT.
refused() {
  [ "$PA_RC" -ne 0 ] || { CASE_DETAIL="rc=0: $(last3 "$PA_OUT")"; return 1; }
  [ ! -e "$1/$SENT" ] || { CASE_DETAIL="a question was written: $(tr -d '\n' < "$1/$SENT")"; return 1; }
  has_f "$PA_OUT" "$2" || { CASE_DETAIL="does not say '$2': $(last3 "$PA_OUT")"; return 1; }
}
case_W3() {   # stage, then ask: an approving question with nothing staged is refused
  local d
  d="$(newtmp)/p"; fx "$d" || { CASE_DETAIL="fixture"; return 1; }
  pa "$1" "$d" --offer "Commit?" --options "A1: Commit" "A2: Hold" --approves A1 --recommendation A1
  refused "$d" "nothing is staged" || return 1
  printf 'unstaged\n' > "$d/b.txt"
  pa "$1" "$d" --offer "Commit?" --options "A1: Commit" "A2: Hold" --approves A1 --recommendation A1
  refused "$d" "nothing is staged" || { CASE_DETAIL="an unstaged change counted: $CASE_DETAIL"; return 1; }
}
case_W4() {   # at least one option must approve nothing
  local d
  d="$(newtmp)/p"; fx "$d" || { CASE_DETAIL="fixture"; return 1; }
  stage "$d"
  pa "$1" "$d" --offer "Commit?" --options "A1: Commit" "A2: Commit too" --approves A1 --approves A2 --recommendation A1
  refused "$d" "approves nothing"
}
case_W5() {   # an id must be a letter and one or two digits
  local d id
  for id in yes ok A A123 1A 'A 1' 'Á1'; do
    d="$(newtmp)/p"; fx "$d" || { CASE_DETAIL="fixture"; return 1; }
    pa "$1" "$d" --offer "Pick?" --options "$id: one" "B2: two" --recommendation B2
    refused "$d" "letter and one or two digits" || { CASE_DETAIL="id '$id': $CASE_DETAIL"; return 1; }
  done
  d="$(newtmp)/p"; fx "$d" || { CASE_DETAIL="fixture"; return 1; }
  pa "$1" "$d" --offer "Pick?" --options "Z99: one" "b2: two" --recommendation b2
  [ "$PA_RC" -eq 0 ] || { CASE_DETAIL="Z99/b2 refused: $(last3 "$PA_OUT")"; return 1; }
}
case_W6() {   # ids are unique ignoring case
  local d
  d="$(newtmp)/p"; fx "$d" || { CASE_DETAIL="fixture"; return 1; }
  pa "$1" "$d" --offer "Pick?" --options "A1: one" "a1: two" --recommendation A1
  refused "$d" "option ids repeat"
}
case_W7() {   # --approves must name an option
  local d
  d="$(newtmp)/p"; fx "$d" || { CASE_DETAIL="fixture"; return 1; }
  stage "$d"
  pa "$1" "$d" --offer "Commit?" --options "A1: Commit" "A2: Hold" --approves Z9 --recommendation A1
  refused "$d" "names no option"
}
case_W8() {   # --status reads both schemas, and says what each option does
  local d
  d="$(newtmp)/p"; fx "$d" || { CASE_DETAIL="fixture"; return 1; }
  v2_sentinel "$d"
  pa "$1" "$d" --status
  [ "$PA_RC" -eq 0 ] || { CASE_DETAIL="v2 rc=$PA_RC: $(last3 "$PA_OUT")"; return 1; }
  has_f "$PA_OUT" "A1 — Commit the staged fix [approves committing the staged change]" \
    && has_f "$PA_OUT" "A2 — Hold - do not commit [approves nothing]" \
    || { CASE_DETAIL="v2 options not rendered with their effect: $(printf '%s' "$PA_OUT" | tr '\n' '|')"; return 1; }
  v1_sentinel "$d"
  pa "$1" "$d" --status
  [ "$PA_RC" -eq 0 ] && has_f "$PA_OUT" "A1: foo" || { CASE_DETAIL="v1 not read: $(printf '%s' "$PA_OUT" | tr '\n' '|')"; return 1; }
}
case_W9() {   # --validate: schema 2 by CDF's rules; schema 1 only where the Guardrails can still take it
  local d
  d="$(newtmp)/p"; fx "$d" 4.4.0 || { CASE_DETAIL="fixture"; return 1; }
  v2_sentinel "$d"; pa "$1" "$d" --validate
  [ "$PA_RC" -eq 0 ] || { CASE_DETAIL="a valid schema-2 question fails: $(last3 "$PA_OUT")"; return 1; }
  jq '.options[0].id = "yes"' "$d/$SENT" > "$d/x" && mv "$d/x" "$d/$SENT"
  pa "$1" "$d" --validate
  [ "$PA_RC" -ne 0 ] || { CASE_DETAIL="a word id validates"; return 1; }
  v1_sentinel "$d"; pa "$1" "$d" --validate
  [ "$PA_RC" -ne 0 ] && has_f "$PA_OUT" "schema 1" || { CASE_DETAIL="schema 1 under Guardrails 4.4.0 validates: $(last3 "$PA_OUT")"; return 1; }
  d="$(newtmp)/p"; fx "$d" 4.3.7 || { CASE_DETAIL="fixture"; return 1; }
  v1_sentinel "$d"; pa "$1" "$d" --validate
  [ "$PA_RC" -eq 0 ] || { CASE_DETAIL="schema 1 under Guardrails 4.3.7 fails: $(last3 "$PA_OUT")"; return 1; }
}
case_W10() {  # --decision is the agent's word: refused where the Guardrails record the pick
  local d
  d="$(newtmp)/p"; fx "$d" 4.4.0 || { CASE_DETAIL="fixture"; return 1; }
  v2_sentinel "$d"
  pa "$1" "$d" --resolve --decision accept
  [ "$PA_RC" -ne 0 ] && [ -f "$d/$SENT" ] && has_f "$PA_OUT" "--decision is not used" \
    || { CASE_DETAIL="rc=$PA_RC sentinel=$([ -f "$d/$SENT" ] && echo kept || echo gone): $(last3 "$PA_OUT")"; return 1; }
  d="$(newtmp)/p"; fx "$d" 4.3.7 || { CASE_DETAIL="fixture"; return 1; }
  v1_sentinel "$d"
  pa "$1" "$d" --resolve --decision accept
  [ "$PA_RC" -eq 0 ] && [ ! -f "$d/$SENT" ] || { CASE_DETAIL="the 4.3.7 route broke: rc=$PA_RC $(last3 "$PA_OUT")"; return 1; }
  pa "$1" "$d" --clear
  [ "$PA_RC" -eq 0 ] || { CASE_DETAIL="--clear failed"; return 1; }
}
# audit_rows DIR — two bypass rows bound to sha S1, one to S2, one unbound.
audit_rows() {
  jq -n '[
    {timestamp:"2026-10-06T00:00:01Z", type:"claude_bypass_proposal", user_response:"PENDING", final_outcome:"recorded_only", details:{pattern:"p1", sentinel_sha256:"S1"}},
    {timestamp:"2026-10-06T00:00:01Z", type:"claude_bypass_proposal", user_response:"PENDING", final_outcome:"recorded_only", details:{pattern:"p2", sentinel_sha256:"S1"}},
    {timestamp:"2026-10-06T00:00:02Z", type:"claude_bypass_proposal", user_response:"PENDING", final_outcome:"recorded_only", details:{pattern:"p3", sentinel_sha256:"S2"}},
    {timestamp:"2026-10-06T00:00:03Z", type:"claude_bypass_proposal", user_response:"PENDING", final_outcome:"recorded_only", details:{pattern:"p4"}},
    {timestamp:"2026-10-06T00:00:04Z", type:"escalation", user_response:"PENDING", final_outcome:"escalated", details:{question:"q"}}
  ]' > "$1/.claude/bypass-audit.json"
}
pick_line() { jq -nc --arg s "$2" --arg p "$1" '{event:"approval", source:"pick", pick:$p, approves:"none", sentinel_sha256:$s, picked_at:"2026-10-06T00:01:00Z", question:"Bypass proposal detected", option_text:"x"}'; }
case_W11() {  # bypass decisions come from the user's pick in .claude/approvals.jsonl
  local d a
  d="$(newtmp)/p"; fx "$d" 4.4.0 || { CASE_DETAIL="fixture"; return 1; }
  audit_rows "$d"
  { pick_line A1 S1; printf 'not json\n'; } > "$d/.claude/approvals.jsonl"
  pa "$1" "$d" --resolve
  [ "$PA_RC" -eq 0 ] || { CASE_DETAIL="rc=$PA_RC: $(last3 "$PA_OUT")"; return 1; }
  a="$d/.claude/bypass-audit.json"
  jq -e '[.[] | select(.details.sentinel_sha256 == "S1") | [.user_response, .final_outcome]] == [["accepted","bypassed"],["accepted","bypassed"]]' "$a" >/dev/null 2>&1 \
    || { CASE_DETAIL="the A1 pick did not accept S1's rows: $(jq -c '[.[] | [.details.pattern, .user_response]]' "$a")"; return 1; }
  jq -e '[.[] | select(.details.pattern == "p3" or .details.pattern == "p4" or .type == "escalation") | .user_response] == ["PENDING","PENDING","PENDING"]' "$a" >/dev/null 2>&1 \
    || { CASE_DETAIL="rows of another question changed: $(jq -c '[.[] | [.details.pattern, .user_response]]' "$a")"; return 1; }
  pick_line A2 S2 >> "$d/.claude/approvals.jsonl"
  pa "$1" "$d" --resolve
  jq -e '[.[] | select(.details.pattern == "p3") | [.user_response, .final_outcome]] == [["declined","abandoned"]]' "$a" >/dev/null 2>&1 \
    || { CASE_DETAIL="the A2 pick did not decline S2's row: $(jq -c '[.[] | [.details.pattern, .user_response]]' "$a")"; return 1; }
}
case_W12() {  # escalate-to-user.sh: --approves passes through, after staging
  local d out rc=0
  d="$(newtmp)/p"; fx "$d" 4.4.0 || { CASE_DETAIL="fixture"; return 1; }
  stage "$d"
  out="$( cd "$d" && bash "$1/scripts/escalate-to-user.sh" --question "Commit as one?" --option "A1: One commit" --option "A2: Hold" \
           --approves A1 --recommendation A1 --rationale r </dev/null 2>&1 )" || rc=$?
  [ "$rc" -eq 0 ] || { CASE_DETAIL="rc=$rc: $(last3 "$out")"; return 1; }
  jq -e '.schema == 2 and .options[0].approves == "commit" and .options[1].approves == "none"' "$d/$SENT" >/dev/null 2>&1 \
    || { CASE_DETAIL="shape: $(tr -d '\n' < "$d/$SENT" 2>/dev/null)"; return 1; }
  jq -e '[.[] | select(.type == "escalation")][0].details.options[0] == {"id":"A1","text":"One commit","approves":"commit"}' \
    "$d/.claude/bypass-audit.json" >/dev/null 2>&1 || { CASE_DETAIL="the audit row: $(jq -c '.[-1].details.options' "$d/.claude/bypass-audit.json")"; return 1; }
}

# ── D: the bypass detector's question ────────────────────────────────────────
detect() {   # ROOT DIR — one PostToolUse with a bypass proposal through ROOT's detector
  printf '%s' '{"hook_event_name":"PostToolUse","session_id":"bl320","tool_name":"Bash","tool_input":{"command":"x"},"tool_response":{"stdout":"just use --no-verify to skip it"}}' \
    | CLAUDE_PROJECT_DIR="$2" bash "$1/scripts/hooks/bypass-detector.sh" >/dev/null 2>&1
}
case_D1() {   # schema 2, answered by id, rows bound to the question, the typed phrase retired
  local d s
  d="$(newtmp)/p"; fx "$d" 4.4.0 || { CASE_DETAIL="fixture"; return 1; }
  detect "$1" "$d"
  [ -f "$d/$SENT" ] || { CASE_DETAIL="no question raised"; return 1; }
  jq -e '.schema == 2 and .source == "bypass-detector" and ([.options[].id] == ["A1","A2"])
         and ([.options[].approves] == ["none","none"]) and .recommendation == "A2"
         and (.question | test("option id"))' "$d/$SENT" >/dev/null 2>&1 \
    || { CASE_DETAIL="shape: $(tr -d '\n' < "$d/$SENT")"; return 1; }
  command grep -q 'I have read the proposal' "$d/$SENT" && { CASE_DETAIL="the BL-029 typed phrase is still asked for"; return 1; }
  cdf_ok "$d/$SENT" || { CASE_DETAIL="CDF's reader rejects it: $CDF_PROBLEMS"; return 1; }
  s="$(sha256_of "$d/$SENT")"
  jq -e --arg s "$s" '[.[] | select(.type == "claude_bypass_proposal")] | length >= 1 and all(.details.sentinel_sha256 == $s)' \
    "$d/.claude/bypass-audit.json" >/dev/null 2>&1 || { CASE_DETAIL="rows not bound to $s: $(jq -c '[.[].details.sentinel_sha256]' "$d/.claude/bypass-audit.json")"; return 1; }
}
case_D2() {   # a second proposal while the detector's question is open: bound to that question
  local d s
  d="$(newtmp)/p"; fx "$d" 4.4.0 || { CASE_DETAIL="fixture"; return 1; }
  detect "$1" "$d"; s="$(sha256_of "$d/$SENT")"
  detect "$1" "$d"
  [ "$(sha256_of "$d/$SENT")" = "$s" ] || { CASE_DETAIL="the open question was rewritten"; return 1; }
  jq -e --arg s "$s" '[.[] | select(.type == "claude_bypass_proposal")] | length >= 2 and all(.details.sentinel_sha256 == $s)' \
    "$d/.claude/bypass-audit.json" >/dev/null 2>&1 || { CASE_DETAIL="rows: $(jq -c '[.[].details.sentinel_sha256]' "$d/.claude/bypass-audit.json")"; return 1; }
}
case_D3() {   # another question is open: the rows are not bound to it, and it is left alone
  local d s
  d="$(newtmp)/p"; fx "$d" 4.4.0 || { CASE_DETAIL="fixture"; return 1; }
  v2_sentinel "$d"; s="$(sha256_of "$d/$SENT")"
  detect "$1" "$d"
  [ "$(sha256_of "$d/$SENT")" = "$s" ] || { CASE_DETAIL="the open question was rewritten"; return 1; }
  jq -e '[.[] | select(.type == "claude_bypass_proposal")] | length >= 1 and all(.details.sentinel_sha256 == null)' \
    "$d/.claude/bypass-audit.json" >/dev/null 2>&1 || { CASE_DETAIL="rows bound to a commit question: $(jq -c '[.[].details.sentinel_sha256]' "$d/.claude/bypass-audit.json")"; return 1; }
}

# ── G: pre-commit-gate.sh's hold ─────────────────────────────────────────────
GATE_OUT=""
gate() {   # ROOT DIR — ROOT's commit check on a lone git commit, run in DIR
  GATE_OUT="$( cd "$2" && jq -nc --arg c "$2" '{session_id:"bl320", hook_event_name:"PreToolUse", cwd:$c, tool_name:"Bash", tool_input:{command:"git commit -m \"fix: x\""}}' \
               | SKIP_LINT=1 bash "$1/scripts/pre-commit-gate.sh" 2>/dev/null )"
}
reason() { printf '%s' "$GATE_OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null; }
case_G1() {   # schema 2 under 4.4.0: each option's effect; the user answers by id; no --resolve, no rm
  local d r
  d="$(newtmp)/p"; fx "$d" 4.4.0 || { CASE_DETAIL="fixture"; return 1; }
  v2_sentinel "$d"; gate "$1" "$d"; r="$(reason)"
  has_f "$r" "pending user decision" || { CASE_DETAIL="not held: $GATE_OUT"; return 1; }
  has_f "$r" "A1 — Commit the staged fix [approves committing the staged change]" || { CASE_DETAIL="options not rendered: $r"; return 1; }
  has_f "$r" "replying with the option id" || { CASE_DETAIL="does not say how the user answers: $r"; return 1; }
  has_f "$r" "--resolve" && { CASE_DETAIL="still tells the agent to run --resolve"; return 1; }
  has_f "$r" "rm " && { CASE_DETAIL="tells the agent to remove the question: $r"; return 1; }
  return 0
}
case_G2() {   # schema 1 under 4.4.0: cannot be answered; withdraw it and ask again
  local d r
  d="$(newtmp)/p"; fx "$d" 4.4.0 || { CASE_DETAIL="fixture"; return 1; }
  v1_sentinel "$d"; gate "$1" "$d"; r="$(reason)"
  has_f "$r" "older format" && has_f "$r" "--clear" || { CASE_DETAIL="$r"; return 1; }
}
case_G3() {   # under 4.3.7 the user answers in words and the agent clears it (the old route)
  local d r
  d="$(newtmp)/p"; fx "$d" 4.3.7 || { CASE_DETAIL="fixture"; return 1; }
  v2_sentinel "$d"; gate "$1" "$d"; r="$(reason)"
  has_f "$r" "A1 — Commit the staged fix" && has_f "$r" "scripts/pending-approval.sh --resolve" \
    || { CASE_DETAIL="$r"; return 1; }
  has_f "$r" "replying with the option id" && { CASE_DETAIL="the 4.4.0 route under 4.3.7"; return 1; }
  return 0
}
case_U1() {   # upgrade-project.sh's hold reads schema 2
  local d out rc=0
  d="$(newtmp)/p"; fx "$d" 4.4.0 || { CASE_DETAIL="fixture"; return 1; }
  printf '%s\n' '{"track":"light","deployment":"personal","poc_mode":null,"current_phase":1,"phases":{}}' > "$d/.claude/phase-state.json"
  v2_sentinel "$d"
  out="$( cd "$d" && bash "$1/scripts/upgrade-project.sh" --to-private-poc --non-interactive </dev/null 2>&1 )" || rc=$?
  [ "$rc" -ne 0 ] || { CASE_DETAIL="not held"; return 1; }
  has_f "$out" "A1 — Commit the staged fix [approves committing the staged change]" || { CASE_DETAIL="options: $(printf '%s' "$out" | command grep -A4 'Options' | tr '\n' '|')"; return 1; }
  has_f "$out" "cannot be added" && { CASE_DETAIL="jq error"; return 1; }
  return 0
}

# ── R: registering the Guardrails hook entries a project is missing ──────────
# A stub clone whose scripts/_shared.sh generates entries in CDF's shape
# (generate_settings_json, 4.4.0): record-approval rides with enforce-evaluate.
STUB_SHARED='generate_settings_json() {
  local p='"'"'"$CLAUDE_PROJECT_DIR"/.claude/framework/hooks/'"'"' e="" h ev m
  for h in "$@"; do
    case "$h" in
      session-start)    ev=SessionStart m="" ;;
      config-guard)     ev=PreToolUse   m="Bash|Write|Edit|NotebookEdit" ;;
      enforce-evaluate) ev=PreToolUse   m=Bash ;;
      stop-checklist)   ev=Stop         m="" ;;
      *) continue ;;
    esac
    e="$e$(jq -nc --arg e "$ev" --arg m "$m" --arg c "$p$h.sh" '"'"'{event:$e,matcher:$m,command:$c}'"'"')
"
    if [ "$h" = enforce-evaluate ]; then
      e="$e$(jq -nc --arg c "${p}record-approval.sh" '"'"'{event:"UserPromptSubmit",matcher:"",command:$c}'"'"')
"
    fi
  done
  printf "%s" "$e" | jq -s '"'"'group_by(.event + "\u0000" + .matcher)
    | map({event: .[0].event, matcher: .[0].matcher, hooks: map({type: "command", command: .command})})
    | group_by(.event) | map({key: .[0].event, value: map(if .matcher != "" then {matcher, hooks} else {hooks} end)})
    | from_entries | {hooks: ., permissions: {deny: []}}'"'"'
}'
mk_stub_clone() {   # DIR VERSION
  mkdir -p "$1/hooks" "$1/scripts" || return 1
  printf '%s\n' "$2" > "$1/FRAMEWORK_VERSION"
  printf '%s\n' "$STUB_SHARED" > "$1/scripts/_shared.sh"
  local h; for h in session-start config-guard enforce-evaluate stop-checklist record-approval; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$1/hooks/$h.sh"
  done
  ( cd "$1" && git init -q && git config user.email t@t.local && git config user.name T && git add -A && git commit -q -m clone ) >/dev/null 2>&1
}
CMDP='"$CLAUDE_PROJECT_DIR"/.claude/framework/hooks/'
# reg_proj DIR — a Guardrails project as the installer left it, minus record-approval;
# plus Solo's own session hook and the user's own prompt hook.
reg_proj() {
  local d="$1" h
  fx "$d" 4.4.0 || return 1
  mkdir -p "$d/.claude/framework/hooks"
  for h in session-start config-guard enforce-evaluate stop-checklist record-approval; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$d/.claude/framework/hooks/$h.sh"; chmod +x "$d/.claude/framework/hooks/$h.sh"
  done
  jq '.activeHooks = ["session-start", "config-guard", "enforce-evaluate", "stop-checklist"]' "$d/.claude/manifest.json" > "$d/m" \
    && mv "$d/m" "$d/.claude/manifest.json"
  jq -n --arg p "$CMDP" '{
    permissions: {allow: ["Bash(git status)"], deny: ["Edit(/.claude/settings.json)"]},
    hooks: {
      SessionStart: [{hooks: [{type: "command", command: ($p + "session-start.sh")},
                              {type: "command", command: "bash \"$CLAUDE_PROJECT_DIR\"/scripts/session-version-check.sh"}]}],
      PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: ($p + "enforce-evaluate.sh")}]},
                   {matcher: "Bash|Write|Edit|NotebookEdit", hooks: [{type: "command", command: ($p + "config-guard.sh")}]},
                   {matcher: "Bash", hooks: [{type: "command", command: "bash \"$CLAUDE_PROJECT_DIR\"/scripts/pre-commit-gate.sh"}]}],
      Stop: [{hooks: [{type: "command", command: ($p + "stop-checklist.sh")}]}],
      UserPromptSubmit: [{hooks: [{type: "command", command: "echo mine"}]}]
    },
    model: "keep-me"
  }' > "$d/.claude/settings.json"
}
REG_OUT=""; REG_RC=0
reg() {   # ROOT DIR CLONE [check]
  REG_RC=0
  REG_OUT="$( ( . "$1/scripts/lib/guardrails.sh" && soif_cdf_register_hooks "$2" "$3" ${4:+"$4"} ) 2>&1 )" || REG_RC=$?
}
case_R1() {   # exactly the missing entry is added, appended; nothing else moves
  local t d c before
  t="$(newtmp)"; d="$t/p"; c="$t/clone"
  reg_proj "$d" && mk_stub_clone "$c" 4.4.0 || { CASE_DETAIL="fixture"; return 1; }
  before="$(jq -c . "$d/.claude/settings.json")"
  reg "$1" "$d" "$c"
  [ "$REG_RC" -eq 0 ] || { CASE_DETAIL="rc=$REG_RC: $(last3 "$REG_OUT")"; return 1; }
  jq -e --arg c "${CMDP}record-approval.sh" '.hooks.UserPromptSubmit[-1] == {hooks: [{type: "command", command: $c}]}' "$d/.claude/settings.json" >/dev/null 2>&1 \
    || { CASE_DETAIL="not appended: $(jq -c '.hooks.UserPromptSubmit' "$d/.claude/settings.json")"; return 1; }
  [ "$(jq -c 'del(.hooks.UserPromptSubmit[-1])' "$d/.claude/settings.json")" = "$before" ] \
    || { CASE_DETAIL="something else changed or moved"; return 1; }
  has_f "$REG_OUT" "+ UserPromptSubmit: ${CMDP}record-approval.sh" || { CASE_DETAIL="the addition is not named: $REG_OUT"; return 1; }
  [ "$(count_f "$REG_OUT" "+ ")" = "1" ] || { CASE_DETAIL="more than one addition named: $REG_OUT"; return 1; }
}
case_R2() {   # idempotent: a second run adds nothing and leaves the file byte-identical
  local t d c s
  t="$(newtmp)"; d="$t/p"; c="$t/clone"
  reg_proj "$d" && mk_stub_clone "$c" 4.4.0 || { CASE_DETAIL="fixture"; return 1; }
  reg "$1" "$d" "$c"; s="$(cksum < "$d/.claude/settings.json")"
  reg "$1" "$d" "$c"
  [ "$REG_RC" -eq 0 ] && [ "$(cksum < "$d/.claude/settings.json")" = "$s" ] || { CASE_DETAIL="second run changed it: $REG_OUT"; return 1; }
  has_f "$REG_OUT" "+ " && { CASE_DETAIL="second run names an addition: $REG_OUT"; return 1; }
  has_f "$REG_OUT" "none missing" || { CASE_DETAIL="does not say none is missing: $REG_OUT"; return 1; }
}
case_R3() {   # an entry whose hook file the project does not have is not added
  local t d c s
  t="$(newtmp)"; d="$t/p"; c="$t/clone"
  reg_proj "$d" && mk_stub_clone "$c" 4.4.0 || { CASE_DETAIL="fixture"; return 1; }
  rm -f "$d/.claude/framework/hooks/record-approval.sh"; s="$(cksum < "$d/.claude/settings.json")"
  reg "$1" "$d" "$c"
  [ "$REG_RC" -eq 0 ] && [ "$(cksum < "$d/.claude/settings.json")" = "$s" ] || { CASE_DETAIL="added an entry for a missing file: $REG_OUT"; return 1; }
}
case_R4() {   # the manifest's activeHooks decide; a removed entry of an active hook comes back (c2)
  local t d c
  t="$(newtmp)"; d="$t/p"; c="$t/clone"
  reg_proj "$d" && mk_stub_clone "$c" 4.4.0 || { CASE_DETAIL="fixture"; return 1; }
  jq '.activeHooks = ["session-start", "config-guard", "stop-checklist"]' "$d/.claude/manifest.json" > "$d/m" && mv "$d/m" "$d/.claude/manifest.json"
  jq 'del(.hooks.Stop)' "$d/.claude/settings.json" > "$d/s" && mv "$d/s" "$d/.claude/settings.json"
  reg "$1" "$d" "$c"
  [ "$REG_RC" -eq 0 ] || { CASE_DETAIL="rc=$REG_RC: $REG_OUT"; return 1; }
  has_f "$REG_OUT" "record-approval" && { CASE_DETAIL="registered a hook of an inactive one: $REG_OUT"; return 1; }
  jq -e --arg c "${CMDP}stop-checklist.sh" '.hooks.Stop == [{hooks: [{type: "command", command: $c}]}]' "$d/.claude/settings.json" >/dev/null 2>&1 \
    || { CASE_DETAIL="the removed stop-checklist entry did not come back: $(jq -c '.hooks.Stop' "$d/.claude/settings.json")"; return 1; }
}
# reg_refused DIR WANT FILE-CKSUM — refused loudly and nothing written.
reg_refused() {
  [ "$REG_RC" -ne 0 ] || { CASE_DETAIL="rc=0: $REG_OUT"; return 1; }
  has_f "$REG_OUT" "[FAIL]" && has_f "$REG_OUT" "$2" || { CASE_DETAIL="does not say '$2': $REG_OUT"; return 1; }
  [ "$(cksum < "$1")" = "$3" ] || { CASE_DETAIL="the file changed"; return 1; }
}
case_R5() {   # a symlinked settings.json is refused and the file it points to is untouched
  local t d c o s
  t="$(newtmp)"; d="$t/p"; c="$t/clone"; o="$t/outside.json"
  reg_proj "$d" && mk_stub_clone "$c" 4.4.0 || { CASE_DETAIL="fixture"; return 1; }
  mv "$d/.claude/settings.json" "$o" && ln -s "$o" "$d/.claude/settings.json"; s="$(cksum < "$o")"
  reg "$1" "$d" "$c"; reg_refused "$o" "symlink" "$s"
}
case_R6() {   # settings.json that is not JSON is refused, unchanged
  local t d c s
  t="$(newtmp)"; d="$t/p"; c="$t/clone"
  reg_proj "$d" && mk_stub_clone "$c" 4.4.0 || { CASE_DETAIL="fixture"; return 1; }
  printf '{"hooks": {,\n' > "$d/.claude/settings.json"; s="$(cksum < "$d/.claude/settings.json")"
  reg "$1" "$d" "$c"; reg_refused "$d/.claude/settings.json" "not a JSON object" "$s"
}
case_R7() {   # a hooks section that is not an object is refused, unchanged
  local t d c s
  t="$(newtmp)"; d="$t/p"; c="$t/clone"
  reg_proj "$d" && mk_stub_clone "$c" 4.4.0 || { CASE_DETAIL="fixture"; return 1; }
  printf '{"hooks": []}\n' > "$d/.claude/settings.json"; s="$(cksum < "$d/.claude/settings.json")"
  reg "$1" "$d" "$c"; reg_refused "$d/.claude/settings.json" "not a JSON object" "$s"
}
case_R8() {   # refresh-guardrails.sh: copies, then registers the missing entries and names them
  local t d c out rc=0
  t="$(newtmp)"; d="$t/p"; c="$t/home/.claude-dev-framework"
  reg_proj "$d" && mk_stub_clone "$c" 4.4.1 || { CASE_DETAIL="fixture"; return 1; }
  cat > "$c/scripts/cdf-refresh.sh" <<'UP'
refresh_cdf_assets() {
  local f; for f in "$2"/hooks/*.sh; do cp "$f" "$1/.claude/framework/hooks/"; done
  chmod +x "$1"/.claude/framework/hooks/*.sh
  jq --arg v "$(tr -d '[:space:]' < "$2/FRAMEWORK_VERSION")" '.frameworkVersion = $v' "$1/.claude/manifest.json" > "$1/.claude/m.tmp" \
    && mv "$1/.claude/m.tmp" "$1/.claude/manifest.json"
}
UP
  ( cd "$c" && git add -A && git commit -q -m up ) >/dev/null 2>&1
  out="$( cd "$d" && HOME="$t/home" bash "$1/scripts/refresh-guardrails.sh" </dev/null 2>&1 )" || rc=$?
  [ "$rc" -eq 0 ] || { CASE_DETAIL="rc=$rc: $(last3 "$out")"; return 1; }
  has_f "$out" "+ UserPromptSubmit: ${CMDP}record-approval.sh" || { CASE_DETAIL="the registration is not named: $(last3 "$out")"; return 1; }
  jq -e '.hooks.UserPromptSubmit | length == 2' "$d/.claude/settings.json" >/dev/null 2>&1 || { CASE_DETAIL="not registered"; return 1; }
  has_f "$out" "settings.json was not changed" && { CASE_DETAIL="claims settings.json was not changed"; return 1; }
  return 0
}
case_R9() {   # upgrade-project.sh registers too, right after its Guardrails refresh
  local body
  body="$(awk '/^_refresh_cdf_assets_solo\(\) \{/ { on = 1 } on { print } on && /^\}/ { exit }' "$1/scripts/upgrade-project.sh")"
  has_f "$body" "solo_refresh_cdf" && has_f "$body" "soif_cdf_register_hooks" \
    || { CASE_DETAIL="_refresh_cdf_assets_solo: $(printf '%s' "$body" | tr '\n' '|' | cut -c1-300)"; return 1; }
}
case_R10() {  # the real clone's entries (skipped without a 4.4.0+ clone)
  local t d s
  [ -f "$CDF_CLONE/scripts/_shared.sh" ] && [ -f "$CDF_CLONE/hooks/record-approval.sh" ] || { SKIP_WHY="no 4.4.0+ clone at $CDF_CLONE"; return 77; }
  t="$(newtmp)"; d="$t/p"
  fx "$d" 4.4.0 || { CASE_DETAIL="fixture"; return 1; }
  mkdir -p "$d/.claude/framework/hooks" && cp "$CDF_CLONE"/hooks/*.sh "$d/.claude/framework/hooks/"
  jq --arg p "$CMDP" -n '{hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: ($p + "enforce-evaluate.sh")}]}]}}' > "$d/.claude/settings.json"
  reg "$1" "$d" "$CDF_CLONE"
  [ "$REG_RC" -eq 0 ] || { CASE_DETAIL="rc=$REG_RC: $REG_OUT"; return 1; }
  jq -e --arg c "${CMDP}record-approval.sh" '[.hooks.UserPromptSubmit[]?.hooks[]?.command] == [$c]' "$d/.claude/settings.json" >/dev/null 2>&1 \
    || { CASE_DETAIL="$(jq -c .hooks "$d/.claude/settings.json")"; return 1; }
  s="$(cksum < "$d/.claude/settings.json")"; reg "$1" "$d" "$CDF_CLONE"
  [ "$(cksum < "$d/.claude/settings.json")" = "$s" ] || { CASE_DETAIL="not idempotent against the real clone"; return 1; }
}

# ── V: the session start ─────────────────────────────────────────────────────
GR='Development Guardrails in this project'
REFRESH_CMD='bash scripts/refresh-guardrails.sh'
STUBBIN="$WORK/stub-bin"; mkdir -p "$STUBBIN"
for t in brew curl; do printf '#!/bin/sh\nexit 1\n' > "$STUBBIN/$t"; chmod +x "$STUBBIN/$t"; done
vproj() {   # DIR INSTALLED CLONE-VERSION — a project with a one-row tool matrix, and a stub clone in DIR/home
  local d="$1"
  reg_proj "$d" && mk_stub_clone "$d/home/.claude-dev-framework" "$3" || return 1
  jq --arg v "$2" '.frameworkVersion = $v' "$d/.claude/manifest.json" > "$d/m" && mv "$d/m" "$d/.claude/manifest.json"
  mkdir -p "$d/templates/tool-matrix"
  jq -n '{description:"fixture", schema_version:1, scope:"common", tools:[{"name":"Probe","category":"version_control","phase":0,"required":false,"check_command":"true","version_command":"echo 1.0.0","min_version":null,"latest_check":null}]}' \
    > "$d/templates/tool-matrix/common.json"
}
cv() { ( cd "$2" && HOME="$2/home" PATH="$STUBBIN:$PATH" bash "$1/scripts/check-versions.sh" </dev/null 2>&1 ); }
sv() { ( cd "$2" && HOME="$2/home" PATH="$STUBBIN:$PATH" bash "$1/scripts/session-version-check.sh" </dev/null 2>&1 ); }
case_V1() {   # 4.3.7 behind 4.4.0: the minimum is named, beside the offer
  local d out
  d="$(newtmp)/p"; vproj "$d" 4.3.7 4.4.0 || { CASE_DETAIL="fixture"; return 1; }
  out="$(cv "$1" "$d")"
  has_f "$out" "[WARN] $GR: 4.3.7 is below 4.4.0, the minimum" || { CASE_DETAIL="no minimum row: $(printf '%s' "$out" | command grep -F "$GR" | tr '\n' '|')"; return 1; }
  has_f "$out" "BELOW MINIMUM" && { CASE_DETAIL="worded as BELOW MINIMUM, which makes the session start URGENT"; return 1; }
  out="$(sv "$1" "$d")"
  has_f "$out" "GUARDRAILS UPDATE OFFER" && has_f "$out" "4.3.7 is below 4.4.0" \
    || { CASE_DETAIL="the session offer does not carry the minimum: $(last3 "$out")"; return 1; }
}
case_V2() {   # 4.4.0 current, record-approval not registered: the refresh is offered, and says why
  local d out
  d="$(newtmp)/p"; vproj "$d" 4.4.0 4.4.0 || { CASE_DETAIL="fixture"; return 1; }
  out="$(cv "$1" "$d")"
  has_f "$out" "[WARN] $GR: 4.4.0, but 1 of its hook registrations is missing from .claude/settings.json (record-approval)" \
    || { CASE_DETAIL="no registration row: $(printf '%s' "$out" | command grep -F "$GR" | tr '\n' '|')"; return 1; }
  has_f "$out" "  $GR: $REFRESH_CMD" || { CASE_DETAIL="the refresh is not offered"; return 1; }
}
case_V3() {   # 4.4.0 current and registered: silent
  local d out
  d="$(newtmp)/p"; vproj "$d" 4.4.0 4.4.0 || { CASE_DETAIL="fixture"; return 1; }
  reg "$1" "$d" "$d/home/.claude-dev-framework"
  out="$(sv "$1" "$d")"
  [ -z "$out" ] || { CASE_DETAIL="spoke: $(last3 "$out")"; return 1; }
}
case_V4() {   # 4.3.7 and the clone at 4.3.7: a notice, no command
  local d out
  d="$(newtmp)/p"; vproj "$d" 4.3.7 4.3.7 || { CASE_DETAIL="fixture"; return 1; }
  out="$(sv "$1" "$d")"
  has_f "$out" "GUARDRAILS NOTICE" && has_f "$out" "4.3.7 is below 4.4.0" || { CASE_DETAIL="$(last3 "$out")"; return 1; }
  has_f "$out" "$REFRESH_CMD" && { CASE_DETAIL="offers a refresh that installs nothing newer"; return 1; }
  return 0
}

# ── X: the mixed install — 4.4.0 Guardrails with a pre-BL-320 question writer ──
# A project synced after BL-318 G5 (#497) but before this entry carries the G5
# refresh and a pending-approval.sh that writes schema 1. Installing 4.4.0
# alone there leaves no way to approve a commit by reply, so both halves must
# move together: the framework sync, not the Guardrails refresh. The project's
# own pending-approval.sh says which schema it writes (SOIF_APPROVAL_SCHEMA).
old_writer() {   # DIR — a pending-approval.sh from before BL-320: no schema line
  mkdir -p "$1/scripts" && printf '#!/usr/bin/env bash\n# scripts/pending-approval.sh (before BL-320)\nset -euo pipefail\n' > "$1/scripts/pending-approval.sh"
}
SYNC_CMD='bash ~/solo-orchestrator/scripts/upgrade-project.sh --sync-framework'
case_X1() {   # refresh-guardrails.sh refuses 4.4.0 over an old writer, changing nothing
  local t d c out rc=0 before
  t="$(newtmp)"; d="$t/p"; c="$t/home/.claude-dev-framework"
  reg_proj "$d" && mk_stub_clone "$c" 4.4.0 && old_writer "$d" || { CASE_DETAIL="fixture"; return 1; }
  jq '.frameworkVersion = "4.3.7"' "$d/.claude/manifest.json" > "$d/m" && mv "$d/m" "$d/.claude/manifest.json"
  printf 'refresh_cdf_assets() { cp "$2"/hooks/*.sh "$1/.claude/framework/hooks/"; }\n' > "$c/scripts/cdf-refresh.sh"
  ( cd "$c" && git add -A && git commit -q -m up ) >/dev/null 2>&1
  before="$(cd "$d" && find .claude -type f -exec cksum {} + | LC_ALL=C sort)"
  out="$( cd "$d" && HOME="$t/home" bash "$1/scripts/refresh-guardrails.sh" </dev/null 2>&1 )" || rc=$?
  [ "$rc" -ne 0 ] || { CASE_DETAIL="rc=0 over an old writer: $(last3 "$out")"; return 1; }
  has_f "$out" "$SYNC_CMD" && has_f "$out" "older approval question" || { CASE_DETAIL="the refusal does not name the sync: $(last3 "$out")"; return 1; }
  [ "$(cd "$d" && find .claude -type f -exec cksum {} + | LC_ALL=C sort)" = "$before" ] || { CASE_DETAIL="the project changed"; return 1; }
}
case_X2() {   # the session start names the sync and offers no Guardrails-only update
  local d out
  d="$(newtmp)/p"; vproj "$d" 4.3.7 4.4.0 && old_writer "$d" || { CASE_DETAIL="fixture"; return 1; }
  out="$(sv "$1" "$d")"
  has_f "$out" "GUARDRAILS NOTICE" && has_f "$out" "$SYNC_CMD" || { CASE_DETAIL="no notice naming the sync: $(last3 "$out")"; return 1; }
  has_f "$out" "$REFRESH_CMD" && { CASE_DETAIL="the Guardrails-only refresh is still offered"; return 1; }
  has_f "$out" "GUARDRAILS UPDATE OFFER" && { CASE_DETAIL="an update is offered"; return 1; }
  return 0
}
case_X3() {   # a project carrying this framework's own pending-approval.sh gets the plain offer
  local d out
  d="$(newtmp)/p"; vproj "$d" 4.3.7 4.4.0 || { CASE_DETAIL="fixture"; return 1; }
  mkdir -p "$d/scripts" && cp "$1/scripts/pending-approval.sh" "$d/scripts/pending-approval.sh"
  out="$(sv "$1" "$d")"
  has_f "$out" "GUARDRAILS UPDATE OFFER" && has_f "$out" "  $REFRESH_CMD" || { CASE_DETAIL="no plain offer: $(last3 "$out")"; return 1; }
  has_f "$out" "$SYNC_CMD" && { CASE_DETAIL="a current writer is called old"; return 1; }
  return 0
}

# ── O: the out-of-band detector ──────────────────────────────────────────────
case_O1() {   # matched=false is recorded once; matched=true is not
  local d n
  d="$(newtmp)/p"; fx "$d" 4.4.0 || { CASE_DETAIL="fixture"; return 1; }
  { jq -nc '{event:"commit", commit:"aaa111", approved_tree:"t1", committed_tree:"t2", matched:false, at:"2026-10-06T00:00:00Z"}'
    jq -nc '{event:"commit", commit:"bbb222", approved_tree:"t3", committed_tree:"t3", matched:true, at:"2026-10-06T00:00:00Z"}'; } > "$d/.claude/approvals.jsonl"
  bash "$1/scripts/detect-out-of-band-commits.sh" "$d" >/dev/null 2>&1
  bash "$1/scripts/detect-out-of-band-commits.sh" "$d" >/dev/null 2>&1
  n="$(jq '[.[] | select(.type == "approval_mismatch")] | length' "$d/.claude/bypass-audit.json")"
  [ "$n" = 1 ] || { CASE_DETAIL="$n approval_mismatch rows: $(jq -c '[.[] | .type]' "$d/.claude/bypass-audit.json")"; return 1; }
  jq -e '[.[] | select(.type == "approval_mismatch")][0].details | .commit == "aaa111" and .approved_tree == "t1" and .committed_tree == "t2"' \
    "$d/.claude/bypass-audit.json" >/dev/null 2>&1 || { CASE_DETAIL="details: $(jq -c '.[] | select(.type == "approval_mismatch")' "$d/.claude/bypass-audit.json")"; return 1; }
}
case_O2() {   # the session start also closes bypass rows from the user's pick
  local d
  d="$(newtmp)/p"; fx "$d" 4.4.0 || { CASE_DETAIL="fixture"; return 1; }
  audit_rows "$d"; pick_line A1 S1 > "$d/.claude/approvals.jsonl"
  bash "$1/scripts/detect-out-of-band-commits.sh" "$d" >/dev/null 2>&1
  jq -e '[.[] | select(.details.sentinel_sha256 == "S1") | .user_response] == ["accepted","accepted"]' "$d/.claude/bypass-audit.json" >/dev/null 2>&1 \
    || { CASE_DETAIL="$(jq -c '[.[] | [.details.pattern, .user_response]]' "$d/.claude/bypass-audit.json")"; return 1; }
}

# ── I: init.sh's clone update ────────────────────────────────────────────────
# upstream + clone: the clone at 4.3.7, its upstream one commit ahead at 4.4.0.
# The bare repository names its branch (# BL-234-FIXTURE-BARE-HEAD).
mk_upstream_pair() {   # DIR — sets UP, CL
  UP="$1/up.git"; CL="$1/clone"
  ( set -e
    git init -q --bare "$UP"; git -C "$UP" symbolic-ref HEAD refs/heads/main
    mkdir "$1/w"; cd "$1/w"; git init -q; git checkout -q -b main
    git config user.email t@t.local; git config user.name T
    printf '4.3.7\n' > FRAMEWORK_VERSION; mkdir -p scripts; printf '#\n' > scripts/init.sh
    git add -A; git commit -q -m v437; git push -q "$UP" main
    git clone -q "$UP" "$CL"; [ -f "$CL/FRAMEWORK_VERSION" ]
    printf '4.4.0\n' > FRAMEWORK_VERSION; git commit -q -am v440; git push -q "$UP" main
  ) >/dev/null 2>&1
}
UPD_OUT=""
# upd ROOT NONINTERACTIVE [ANSWER] — the update step; ANSWER fed through a pty.
upd() {
  local r="$1" ni="$2" ans="${3:-}" t
  t="$(newtmp)"
  cat > "$t/run.sh" <<RUN
. "$r/scripts/lib/helpers-core.sh"
. "$r/scripts/lib/guardrails.sh"
soif_guardrails_clone_update "$CL" "$ni"
RUN
  if [ -z "$ans" ]; then
    UPD_OUT="$(bash "$t/run.sh" </dev/null 2>&1)"
  else
    printf '%s\n' "$ans" > "$t/answers"
    [ "$ans" = ENTER ] && printf '\n' > "$t/answers"
    # The answer is written at once, and stdin is held open two seconds more:
    # BSD script(1) sends ^D to the pty when its stdin ends, and a ^D that
    # arrives before the prompt reads is taken as an empty answer (measured: an
    # "n" fed from a file was read as Enter, so the clone was pulled).
    if script -q /dev/null true </dev/null >/dev/null 2>&1; then
      UPD_OUT="$( { cat "$t/answers"; sleep 2; } | script -q /dev/null bash "$t/run.sh" 2>&1)"
    else
      UPD_OUT="$( { cat "$t/answers"; sleep 2; } | script -q -c "bash '$t/run.sh'" /dev/null 2>&1)"
    fi
  fi
}
head_of() { git -C "$1" rev-parse HEAD 2>/dev/null; }
have_pty() { command -v script >/dev/null 2>&1; }
case_I1() {   # no terminal: no pull, the command printed, and the minimum named
  local t h
  t="$(newtmp)"; mk_upstream_pair "$t" || { CASE_DETAIL="fixture"; return 1; }
  h="$(head_of "$CL")"
  upd "$1" false
  [ "$(head_of "$CL")" = "$h" ] || { CASE_DETAIL="the clone was pulled without asking"; return 1; }
  has_f "$UPD_OUT" "git -C \"$CL\" pull --ff-only" || { CASE_DETAIL="the command is not printed: $(last3 "$UPD_OUT")"; return 1; }
  has_f "$UPD_OUT" "4.3.7" && has_f "$UPD_OUT" "older than 4.4.0" || { CASE_DETAIL="the minimum is not named: $(last3 "$UPD_OUT")"; return 1; }
}
case_I2() {   # a terminal, Enter: yes — the clone is pulled; current and available both shown
  local t
  have_pty || { SKIP_WHY="no script(1) for a pty"; return 77; }
  t="$(newtmp)"; mk_upstream_pair "$t" || { CASE_DETAIL="fixture"; return 1; }
  upd "$1" false ENTER
  [ "$(head_of "$CL")" = "$(git -C "$UP" rev-parse main)" ] || { CASE_DETAIL="Enter did not update: $(last3 "$UPD_OUT")"; return 1; }
  has_f "$UPD_OUT" "4.3.7" && has_f "$UPD_OUT" "4.4.0" && has_f "$UPD_OUT" "[Y/n]" || { CASE_DETAIL="$(printf '%s' "$UPD_OUT" | tr '\n\r' '||')"; return 1; }
}
case_I3() {   # a terminal, n: kept
  local t h
  have_pty || { SKIP_WHY="no script(1) for a pty"; return 77; }
  t="$(newtmp)"; mk_upstream_pair "$t" || { CASE_DETAIL="fixture"; return 1; }
  h="$(head_of "$CL")"
  upd "$1" false n
  [ "$(head_of "$CL")" = "$h" ] || { CASE_DETAIL="'n' still pulled"; return 1; }
}
case_I4() {   # --non-interactive at a terminal: no question, no pull
  local t h
  have_pty || { SKIP_WHY="no script(1) for a pty"; return 77; }
  t="$(newtmp)"; mk_upstream_pair "$t" || { CASE_DETAIL="fixture"; return 1; }
  h="$(head_of "$CL")"
  upd "$1" true ENTER
  [ "$(head_of "$CL")" = "$h" ] || { CASE_DETAIL="--non-interactive pulled"; return 1; }
  has_f "$UPD_OUT" "[Y/n]" && { CASE_DETAIL="--non-interactive asked"; return 1; }
  return 0
}
case_I5() {   # init.sh asks through the lib, ships the lib, and no longer pulls on its own
  local i="$1/init.sh"
  command grep -qE '^[[:space:]]*soif_guardrails_clone_update "\$FRAMEWORK_CLONE" "\$NON_INTERACTIVE"' "$i" || { CASE_DETAIL="init.sh does not call the update step"; return 1; }
  command grep -qE '^[[:space:]]*(source|\.) "\$SCRIPT_DIR/scripts/lib/guardrails\.sh"' "$i" || { CASE_DETAIL="init.sh does not load the lib"; return 1; }
  command grep -qE 'pull --quiet' "$i" && { CASE_DETAIL="init.sh still pulls on its own"; return 1; }
  ( . "$1/scripts/lib/scaffold-shipped-set.sh" && soif_parse_shipped_scripts "$i" "$1/scripts" ) | command grep -qx 'scripts/lib/guardrails.sh' \
    || { CASE_DETAIL="the lib is not in init.sh's shipped set"; return 1; }
}
case_A1() {   # adoption keeps an adoptee's own Guardrails and says when they are below the minimum
  local d out
  d="$(newtmp)/p"; fx "$d" 4.3.0 || { CASE_DETAIL="fixture"; return 1; }
  mkdir -p "$d/.claude/framework/hooks"
  out="$( ( adopt_note() { printf '%s\n' "$*"; }; adopt_head() { printf '== %s\n' "$*"; }
            . "$1/scripts/lib/guardrails.sh"; . "$1/scripts/lib/adopt/adopt-guardrails.sh"
            adopt_guardrails_resolve "$d"; adopt_write_guardrails "$d" /dev/null; printf 'RESULT=%s\n' "$ADOPT_GUARDRAILS_RESULT" ) 2>&1 )"
  has_f "$out" "older than 4.4.0" || { CASE_DETAIL="no minimum note: $(last3 "$out")"; return 1; }
  has_f "$out" "RESULT=" && has_f "$(printf '%s' "$out" | command grep '^RESULT=')" "below the 4.4.0 minimum" \
    || { CASE_DETAIL="the Adoption Record does not say so: $(printf '%s' "$out" | command grep '^RESULT=')"; return 1; }
}

# ── E: the dogfood approval round trip, against the real Guardrails hooks ────
have_real() {
  [ -f "$CDF_CLONE/hooks/record-approval.sh" ] && [ -f "$CDF_CLONE/hooks/enforce-evaluate.sh" ] || return 1
  local v; v="$(tr -d '[:space:]' < "$CDF_CLONE/FRAMEWORK_VERSION" 2>/dev/null)"
  case "$v" in 4.[4-9].*|4.[1-9][0-9].*|[5-9].*) return 0 ;; esac
  return 1
}
E_D=""
hk() {   # HOOK — the fixture's copy of a real Guardrails hook, as Claude Code runs it (stdin = envelope)
  ( cd "$E_D" && env -u CLAUDECODE CLAUDE_PROJECT_DIR="$E_D" bash "$E_D/.claude/framework/hooks/$1" )
}
pre() { jq -nc --arg c "$1" --arg d "$E_D" '{session_id:"bl320-e", hook_event_name:"PreToolUse", cwd:$d, tool_name:"Bash", tool_input:{command:$c}}'; }
ups() { jq -nc --arg p "$1" --arg d "$E_D" --arg i "$2" '{session_id:"bl320-e", transcript_path:"/dev/null", cwd:$d, prompt_id:$i, permission_mode:"default", hook_event_name:"UserPromptSubmit", prompt:$p}'; }
E_LOG=""
elog() { E_LOG="${E_LOG}$1"$'\n'; }
case_E1() {
  local r="$1" out rc h
  have_real || { SKIP_WHY="no 4.4.0+ Guardrails clone at $CDF_CLONE (CI has none)"; return 77; }
  E_D="$(newtmp)/eproj"; fx "$E_D" 4.4.0 || { CASE_DETAIL="fixture"; return 1; }
  h="$(printf '%s' "$E_D" | shasum -a 256 | cut -c1-12)"; HASHES="$HASHES $h"
  mkdir -p "$E_D/.claude/framework/hooks" && cp "$CDF_CLONE"/hooks/* "$E_D/.claude/framework/hooks/" && chmod +x "$E_D"/.claude/framework/hooks/*.sh
  jq '.activeHooks = ["enforce-evaluate","stop-checklist","marker-tracker","config-guard"]' "$E_D/.claude/manifest.json" > "$E_D/m" && mv "$E_D/m" "$E_D/.claude/manifest.json"
  printf 'fixed\n' > "$E_D/src.txt"
  # row 20: an agent commit before approval is blocked, and the block says how to ask
  out="$(pre 'git commit -m "fix: x"' | hk enforce-evaluate.sh 2>&1)"; rc=$?
  elog "row 20 enforce-evaluate before approval: rc=$rc $(printf '%s' "$out" | head -1)"
  [ "$rc" -eq 2 ] && has_f "$out" "pending-approval.json" || { CASE_DETAIL="row 20: rc=$rc $(last3 "$out")"; return 1; }
  # row 23: the agent may stage the files, the manifest included
  out="$(pre 'git add src.txt .claude/manifest.json' | hk config-guard.sh 2>&1)"; rc=$?
  elog "row 23 config-guard on git add .claude/manifest.json: rc=$rc"
  [ "$rc" -eq 0 ] || { CASE_DETAIL="row 23: staging refused: $(last3 "$out")"; return 1; }
  git -C "$E_D" add src.txt .claude/manifest.json
  # stage, then ask — through Solo's writer
  pa "$r" "$E_D" --offer "Commit the fix and the manifest?" --options "A1: Commit the staged fix" "A2: Hold - do not commit" --approves A1 --recommendation A1
  elog "offer: rc=$PA_RC $(printf '%s' "$PA_OUT" | head -1)"
  [ "$PA_RC" -eq 0 ] || { CASE_DETAIL="offer: $(last3 "$PA_OUT")"; return 1; }
  # row 21: the stop check lets the agent stop and wait
  out="$(jq -nc --arg d "$E_D" '{session_id:"bl320-e", hook_event_name:"Stop", stop_hook_active:false, cwd:$d, last_assistant_message:"Question recorded."}' | hk stop-checklist.sh 2>&1)"; rc=$?
  elog "row 21 stop-checklist with the question recorded: rc=$rc block=$(has_f "$out" '"block"' && echo yes || echo no)"
  [ "$rc" -eq 0 ] && ! has_f "$out" '"decision":"block"' || { CASE_DETAIL="row 21: the stop check presses: $(last3 "$out")"; return 1; }
  # Solo's own hold, and its words
  gate "$r" "$E_D"
  elog "Solo pre-commit-gate while the question is open: $(reason | head -1)"
  has_f "$(reason)" "replying with the option id" || { CASE_DETAIL="Solo's hold: $(reason)"; return 1; }
  # the user's first reply renders and blocks
  out="$(ups "A1 — go ahead" p1 | hk record-approval.sh 2>&1)"
  elog "reply 1 'A1 — go ahead': $(printf '%s' "$out" | jq -r '.decision // "none"') — $(printf '%s' "$out" | jq -r '.reason // .hookSpecificOutput.additionalContext // ""' | head -1)"
  [ "$(printf '%s' "$out" | jq -r '.decision // empty')" = block ] && has_f "$(printf '%s' "$out" | jq -r .reason)" "src.txt" \
    || { CASE_DETAIL="reply 1 did not render: $out"; return 1; }
  # the second reply picks
  out="$(ups "A1" p2 | hk record-approval.sh 2>&1)"
  elog "reply 2 'A1': $(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // ""' | cut -c1-120)"
  has_f "$out" "approved committing the staged change" || { CASE_DETAIL="reply 2 did not approve: $out"; return 1; }
  [ -f "/tmp/.claude_evaluated_$h" ] && [ ! -f "$E_D/$SENT" ] || { CASE_DETAIL="marker/sentinel state wrong"; return 1; }
  jq -e 'select(.event == "approval") | .pick == "A1" and .source == "pick"' "$E_D/.claude/approvals.jsonl" >/dev/null 2>&1 \
    || { CASE_DETAIL="no pick record"; return 1; }
  gate "$r" "$E_D"
  has_f "$(reason)" "pending user decision" && { CASE_DETAIL="Solo still holds after the pick"; return 1; }
  # rows 29/30: the agent's lone commit passes, lands, and matches what was approved
  out="$(pre 'git commit -m "fix: x" -m "body"' | hk enforce-evaluate.sh 2>&1)"; rc=$?
  elog "rows 29/30 enforce-evaluate on the lone commit after the pick: rc=$rc"
  [ "$rc" -eq 0 ] || { CASE_DETAIL="rows 29/30: refused: $(last3 "$out")"; return 1; }
  git -C "$E_D" commit -q -m "fix: x" -m "body" || { CASE_DETAIL="the commit failed"; return 1; }
  jq -nc --arg d "$E_D" '{session_id:"bl320-e", hook_event_name:"PostToolUse", cwd:$d, tool_name:"Bash", tool_input:{command:"git commit -m \"fix: x\" -m \"body\""}, tool_response:{stdout:"", stderr:"", interrupted:false}}' \
    | hk marker-tracker.sh >/dev/null 2>&1
  elog "after the commit: $(command grep '"event":"commit"' "$E_D/.claude/approvals.jsonl" | jq -c '{matched}')"
  jq -e 'select(.event == "commit") | .matched == true' "$E_D/.claude/approvals.jsonl" >/dev/null 2>&1 || { CASE_DETAIL="no matched commit record"; return 1; }
  [ ! -f "/tmp/.claude_evaluated_$h" ] || { CASE_DETAIL="the marker outlived the commit"; return 1; }
}

# ── runner ───────────────────────────────────────────────────────────────────
SKIP_WHY=""
check() {   # LABEL CASE — a case returns 77 to say it could not run here (SKIP_WHY)
  local rc=0
  CASE_DETAIL=""; SKIP_WHY=""
  "$2" "$REPO_ROOT" || rc=$?
  case "$rc" in
    0)  pass "$1" ;;
    77) skip "$1" "$SKIP_WHY" ;;
    *)  fail_ "$1" "$CASE_DETAIL" ;;
  esac
}
echo "=== W — the writer ==="
check "W1: stage, then ask — schema 2, the approving option, CDF's reader accepts it, the user's answer route named" case_W1
check "W2: a question that approves nothing needs nothing staged" case_W2
check "W3: an approving question with nothing staged is refused (an unstaged change does not count)" case_W3
check "W4: a question whose every option approves is refused" case_W4
check "W5: ids are a letter and one or two digits (yes, ok, A, A123, 1A, 'A 1', Á1 refused; Z99, b2 kept)" case_W5
check "W6: ids repeat ignoring case -> refused" case_W6
check "W7: --approves naming no option -> refused" case_W7
check "W8: --status reads both schemas and says what each option does" case_W8
check "W9: --validate — schema 2 by CDF's rules; schema 1 only where the Guardrails can take it" case_W9
check "W10: --resolve --decision refused under 4.4.0 (the pick is recorded by the Guardrails); the 4.3.7 route kept" case_W10
check "W11: --resolve closes bypass rows from the user's pick in approvals.jsonl, bound by the question's sha256" case_W11
check "W12: escalate-to-user.sh passes --approves through; its audit row keeps the options" case_W12
echo "=== D — the bypass detector's question ==="
check "D1: schema 2, two options that approve nothing, answered by id, rows bound to it; the BL-029 typed phrase retired" case_D1
check "D2: a second proposal while it is open binds to it and leaves it alone" case_D2
check "D3: a commit question already open is left alone and does not take the bypass rows" case_D3
echo "=== G — the holds ==="
check "G1: pre-commit-gate, schema 2 under 4.4.0 — effects rendered, answered by option id, no --resolve, no rm" case_G1
check "G2: pre-commit-gate, schema 1 under 4.4.0 — older format, withdraw and ask again" case_G2
check "G3: pre-commit-gate under 4.3.7 — the old route (--resolve)" case_G3
check "U1: upgrade-project.sh's hold renders a schema-2 question" case_U1
echo "=== R — registering missing Guardrails hook entries ==="
check "R1: exactly the missing entry is appended and named; every other entry, Solo's and the user's, unchanged and in order" case_R1
check "R2: a second run adds nothing and leaves the file byte-identical" case_R2
check "R3: no entry for a hook file the project does not have" case_R3
check "R4: activeHooks decide; a removed entry of an active hook comes back" case_R4
check "R5: a symlinked settings.json -> refused loudly, its target untouched" case_R5
check "R6: settings.json that is not JSON -> refused, unchanged" case_R6
check "R7: a hooks section that is not an object -> refused, unchanged" case_R7
check "R8: refresh-guardrails.sh registers what is missing and names it" case_R8
check "R9: upgrade-project.sh registers right after its Guardrails refresh" case_R9
check "R10: against the real clone's generator: record-approval registered, idempotent" case_R10
echo "=== V — the session start ==="
check "V1: below 4.4.0 — named (not as BELOW MINIMUM), in the session offer too" case_V1
check "V2: 4.4.0 with record-approval unregistered — the refresh is offered and says why" case_V2
check "V3: 4.4.0, registered — silent" case_V3
check "V4: project and clone both 4.3.7 — a notice, no command" case_V4
echo "=== X — a mixed install (4.4.0 Guardrails, a pre-BL-320 writer) ==="
check "X1: refresh-guardrails.sh refuses 4.4.0 over an old question writer, names the framework sync, changes nothing" case_X1
check "X2: the session start names the framework sync and offers no Guardrails-only update" case_X2
check "X3: this framework's own pending-approval.sh is recognised as current — the plain offer" case_X3
echo "=== O — the out-of-band detector ==="
check "O1: matched=false recorded once as approval_mismatch; matched=true not" case_O1
check "O2: the session start closes bypass rows from the user's pick" case_O2
echo "=== I — init.sh's clone update; adoption ==="
check "I1: no terminal — no pull, the command printed, the minimum named" case_I1
check "I2: a terminal, Enter — yes: pulled; current and available shown" case_I2
check "I3: a terminal, n — kept" case_I3
check "I4: --non-interactive at a terminal — no question, no pull" case_I4
check "I5: init.sh asks through the lib, ships it, and no longer pulls on its own" case_I5
check "A1: adoption names a kept install below the minimum, in the Adoption Record too" case_A1
echo "=== E — the dogfood approval round trip (rows 20, 21, 23, 29, 30), real Guardrails hooks ==="
check "E1: blocked -> staged -> asked -> stop allowed -> A1 renders -> A1 picks -> lone commit passes -> matched" case_E1
[ -z "$E_LOG" ] || printf '%s' "$E_LOG" | sed 's/^/      /'

# ── M: mutants ───────────────────────────────────────────────────────────────
mk_mirror() { mkdir -p "$2" && cp -Rp "$1/scripts" "$1/init.sh" "$2/"; }
mutate() {   # FILE MARKER REPLACEMENT — exactly one line ends in MARKER; it now reads REPLACEMENT; still parses
  local f="$1" mark="$2" repl="$3" n=""
  [ -f "$f" ] || { echo "no such file: $f"; return 1; }
  n="$(MARK="$mark" awk 'BEGIN{c=0; m=ENVIRON["MARK"]} length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m {c++} END{print c}' "$f")"
  [ "$n" = "1" ] || { echo "marker '$mark' ends $n line(s) of $f (need 1)"; return 1; }
  MARK="$mark" REPL="$repl" awk '{ m=ENVIRON["MARK"]
      if (length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m) print ENVIRON["REPL"]; else print }' \
    "$f" > "$f.mut" && cat "$f.mut" > "$f" && rm -f "$f.mut"
  command grep -qF -- "$mark" "$f" && { echo "marker still present after the edit"; return 1; }
  [ "$(command grep -cxF -- "$repl" "$f")" -ge 1 ] || { echo "replacement did not land"; return 1; }
  bash -n "$f" 2>/dev/null || { echo "mutant does not parse"; return 1; }
  return 0
}
mutant() {   # ID FILE MARKER REPLACEMENT KILLER WHAT
  local id="$1" rel="$2" mark="$3" repl="$4" killer="$5" what="$6" m why
  m="$(newtmp)/mirror"
  mk_mirror "$REPO_ROOT" "$m" || { fail_ "$id" "could not build a mirror"; return; }
  why="$(mutate "$m/$rel" "$mark" "$repl")" || { fail_ "$id" "mutant did not land: $why"; return; }
  local rc=0
  CASE_DETAIL=""; SKIP_WHY=""
  "$killer" "$m" || rc=$?
  case "$rc" in
    0)  fail_ "$id" "$what — SURVIVED: ${killer#case_} still passes against the mutant" ;;
    77) skip "$id (MUTATION)" "${killer#case_} cannot run here: $SKIP_WHY" ;;
    *)  pass "$id (MUTATION) — $what: killed by ${killer#case_} ($CASE_DETAIL)" ;;
  esac
}
echo "=== M — mutants ==="
GL=scripts/lib/guardrails.sh
PAS=scripts/pending-approval.sh
mutant M1  "$GL"  '# BL-320-V2-ID' '      (if any(.opts[]; (.id | type) != "string") then "an option id is not a letter and one or two digits (A1)" else empty end),' case_W5 "any string is an id, so free text can pick"
mutant M2  "$GL"  '# BL-320-V2-UNIQUE' '      (if false then "option ids repeat" else empty end),' case_W6 "A1 and a1 both offered"
mutant M3  "$GL"  '# BL-320-V2-NONE' '      (if false then "no option approves nothing" else empty end)' case_W4 "every option approves a commit"
mutant M4  "$PAS" '# BL-320-OFFER-STAGED' '  :' case_W3 "an approving question with nothing staged"
mutant M5  "$PAS" '# BL-320-OFFER-APPROVES-ID' '      :' case_W7 "--approves naming no option is ignored"
mutant M6  "$PAS" '# BL-320-OFFER-SCHEMA' "  payload=\$(jq -n --arg q \"\$question\" --argjson opts \"\$options_json\" --arg rec \"\$recommendation\" --arg at \"\$now\" '{question: \$q, options: [\$opts[] | .id + \": \" + .text], recommendation: \$rec, offered_at: \$at}')" case_W1 "schema 1 is written again"
mutant M7  "$GL"  '# BL-320-PA-LINES' "  jq -r '(.options // [])[] | tostring' \"\$1\" 2>/dev/null" case_W8 "a schema-2 option is shown without its effect"
mutant M8  "$PAS" '# BL-320-VALIDATE-V1' '    :' case_W9 "schema 1 validates under 4.4.0"
mutant M9  "$PAS" '# BL-320-RESOLVE-DECISION' '    :' case_W10 "the agent's --decision closes bypass rows under 4.4.0"
mutant M10 scripts/lib/bypass-audit.sh '# BL-320-AUDIT-BIND' '        and ((.details.sentinel_sha256 | type) == "string")' case_W11 "a pick closes rows of any question"
mutant M11 scripts/lib/bypass-audit.sh '# BL-320-AUDIT-MAP' '          (if true then "accepted" else "declined" end) as $ur' case_W11 "every pick accepts the bypass"
mutant M12 scripts/hooks/bypass-detector.sh '# BL-320-DETECT-SCHEMA2' 'BD_Q_PROG='"'"'{question: $q, options: ["A1: accept", "A2: decline"], recommendation: "A2", offered_at: $ts}'"'"'' case_D1 "the detector asks in schema 1 again"
mutant M13 scripts/hooks/bypass-detector.sh '# BL-320-DETECT-BIND' '  COVER_SHA=""' case_D1 "rows are not bound to the question"
mutant M14 scripts/hooks/bypass-detector.sh '# BL-320-DETECT-COVER' '  COVER_SHA="$(soif_bd_sha256 "$SENTINEL")"' case_D3 "the bypass rows take a commit question's answer"
mutant M15 scripts/pre-commit-gate.sh '# BL-320-GATE-RENDER' "  options=\$(jq -er '.options | map(\"  \" + .) | join(\"\\n\")' \"\$sentinel\") || return 1" case_G1 "a schema-2 question is called malformed"
mutant M16 scripts/pre-commit-gate.sh '# BL-320-GATE-ROUTE' '  route=legacy' case_G1 "the agent is told to run --resolve under 4.4.0"
mutant M17 "$GL"  '# BL-320-ROUTE' '  [ "$c" = lt ] && { echo pick; return 0; }' case_G3 "the route is read backwards"
mutant M18 "$GL"  '# BL-320-REG-LINK' '  :' case_R5 "a symlinked settings.json is written through"
mutant M19 "$GL"  '# BL-320-REG-JSON' '  :' case_R6 "a file that is not JSON is rewritten"
mutant M19b "$GL" '# BL-320-REG-JSON' '  :' case_R7 "a hooks array is rewritten"
mutant M20 "$GL"  '# BL-320-REG-FILE' '      true' case_R3 "an entry is added for a hook file that does not exist"
mutant M21 "$GL"  '# BL-320-REG-HAVE' '      false' case_R2 "a second run adds the entries again"
mutant M22 "$GL"  '# BL-320-REG-APPEND' "  prog='.hooks = ((.hooks // {}) + \$add)'" case_R1 "an event's existing entries are replaced"
mutant M23 scripts/refresh-guardrails.sh '# BL-320-RG-REGISTER' ':' case_R8 "the refresh leaves the new hook unregistered"
mutant M24 scripts/upgrade-project.sh '# BL-320-UP-REGISTER' '    :' case_R9 "the upgrade leaves the new hook unregistered"
mutant M25 scripts/check-versions.sh '# BL-320-CV-MIN' '  :' case_V1 "a project below 4.4.0 is not told"
mutant M26 scripts/check-versions.sh '# BL-320-CV-REG' '  :' case_V2 "a missing registration is never offered"
mutant M27 scripts/detect-out-of-band-commits.sh '# BL-320-OOB-MISMATCH' ':' case_O1 "a commit that is not the approved change goes unrecorded"
mutant M28 scripts/detect-out-of-band-commits.sh '# BL-320-OOB-DEDUP' '    false' case_O1 "the mismatch is recorded at every session start"
mutant M29 scripts/detect-out-of-band-commits.sh '# BL-320-OOB-RECONCILE' ':' case_O2 "bypass rows stay PENDING after the pick"
mutant M30 "$GL"  '# BL-320-PULL-TTY' '  if [ "$ni" = true ]; then' case_I1 "the clone is pulled when no one can be asked"
mutant M31 "$GL"  '# BL-320-PULL-ASK' '    if prompt_yes_no "Update the shared clone now? Every project on this computer uses it [Y/n]" "N"; then' case_I2 "Enter means no"
mutant M32 "$GL"  '# BL-320-PULL-MIN' '  :' case_I1 "a clone below the minimum is not named"
mutant M33 init.sh '# BL-320-INIT-PULL' '      :' case_I5 "init.sh never offers the update"
mutant M34 init.sh '# BL-320-SHIP' '  :' case_I5 "the lib is not shipped"
mutant M35 scripts/escalate-to-user.sh '# BL-320-ESC-APPROVES' '    --approves) shift 2 ;;' case_W12 "an escalation cannot approve a commit"
mutant M36 scripts/lib/adopt/adopt-guardrails.sh '# BL-320-ADOPT-MIN' '  :' case_A1 "adoption keeps a 4.3.0 install without a word"
mutant M38 scripts/refresh-guardrails.sh '# BL-320-RG-MIXED' ':' case_X1 "4.4.0 is installed beside a writer it cannot answer"
mutant M39 scripts/check-versions.sh '# BL-320-CV-MIXED' '        :' case_X2 "the Guardrails-only update is offered to a mixed install"
mutant M40 "$PAS" '# BL-320-PA-SCHEMA-MARK' ':' case_X3 "this framework's own writer reads as an old one"
mutant M37 scripts/upgrade-project.sh '# BL-320-UP-SENTINEL-RENDER' "    jq -r '.options[]? // empty | \"    \" + .' \"\$PENDING_APPROVAL_FILE\" >&2" case_U1 "upgrade-project renders a schema-2 question as a jq error"

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
