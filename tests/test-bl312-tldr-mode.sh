#!/usr/bin/env bash
# tests/test-bl312-tldr-mode.sh — `## BL-312:` opt-in TL;DR mode.
#
# THE FEATURE. A project's user can choose that every reply the agent gives ends
# with exactly one plain-English TL;DR carrying eight parts (what happened, what
# it means for them, next steps, what is waiting on them, the options, pros and
# cons of each, a recommendation with its reasoning, what happens if they do
# nothing) plus every command they must run in a fenced block. The choice is
# `tldr_mode` in `.claude/manifest.json`; a Stop hook enforces PRESENCE and the
# generated CLAUDE.md states the CONTENT.
#
# WHAT THIS FILE PINS (the unit lane; tests/test-bl312-tldr-mode-init.sh runs
# init.sh itself and lives in the full lane):
#   H  the hook — block, allow, the fence rule, never twice a turn, off/absent/
#      unreadable = off, no jq = off with one stderr line, its own project root.
#   B  the bypass detector beside it: a compliant TL;DR raises nothing, and a
#      control proves the detector was live in the same fixture; three TL;DRs
#      it flagged, reworded under the section's rule, raise nothing.
#   W  the wiring: the shared roster registers it in the Stop group the
#      framework's other Stop hooks use, once, in both modes, beside theirs; and
#      init.sh's copy list ships the hook and its lib.
#   C  the CLAUDE.md section: on, again, off restores the bytes, damaged
#      markers are refused; the [y/N] reader; its command rule names the
#      detector's own words.
#   S  init.sh by structure (its behaviour is the init suite's).
#   A  adoption: yes, no, end of input, a stray `1`, the number `2`, an answer
#      that is not offered — and where the question sits.
#   R  reconfigure-project.sh --tldr-mode on|off, run from an adopted project:
#      the switch, its refusals, its rollback, a section rewritten and said.
#   U  an upgrade keeps the key.
#   G  a Guardrails-only manifest carrying `tldr_mode` is not Guardrails-only.
#   P  the Currency System's three-way merge of CLAUDE.md: with the mode on,
#      both render legs carry the section, so it is common ground, not a
#      conflict with the template's last lines.
#   M  mutants: each rewrites ONE marked line in a mirror (or in a fixture's
#      own copy), asserts the edit landed by its literal text, and requires a
#      named case to go RED.
set -uo pipefail
# The adoption driver's MCP step can ask a question and run `claude mcp add` on
# a machine that has `claude` and is missing a server (`# BL-311-MCP-SEAM`).
export SOIF_ADOPT_MCP=off

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

echo "== BL-312 — opt-in TL;DR mode =="
for t in git jq awk; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done
WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT
NOCLONE="$WORK/no-guardrails-clone"   # never created: no real Guardrails clone runs here
# mktemp, not a counter: almost every caller is inside `$( … )`, a subshell, so
# a counter would never advance and every case would share one directory.
newtmp() { mktemp -d "$WORK/tXXXXXX"; }

# check LABEL CASE [ARGS…] — run a case against the real tree and report it.
CASE_DETAIL=""
check() {
  local label="$1" fn="$2"; shift 2
  CASE_DETAIL=""
  if "$fn" "$@"; then pass "$label"; else fail_ "$label" "$CASE_DETAIL"; fi
}

# ════════════════════════════════════════════════════════════════════════════
# H — the hook
# ════════════════════════════════════════════════════════════════════════════
MSG_NONE=$'Fixed the parser and added a test.\n\n```\n$ bash tests/test-parser.sh\nResults: 12 passed, 0 failed\n```'
MSG_IN_BACKTICK_FENCE=$'Fixed it.\n\n```\nTL;DR: the parser is fixed\n```'
MSG_IN_TILDE_FENCE=$'Fixed it.\n\n~~~\nTL;DR: the parser is fixed\n~~~'
# A fence nested in a list item is indented — the shape a TL;DR's own part 4
# gives a command. Its opening line does not start in column 0.
MSG_IN_NESTED_FENCE=$'Fixed it.\n\n4. Waiting on you:\n   ```\n   TL;DR: run it\n   ```'
MSG_FILENAME_ONLY=$'Notes are in tl;dr.md and docs/tldr.txt now.'
MSG_AFTER_FENCE=$'Fixed it.\n\n```\nbash tests/test-parser.sh\n```\n\nTL;DR: the parser is fixed; nothing waits on you.'
# Each spelling a reply might use for the label, outside any fence.
TLDR_SPELLINGS='**TL;DR** — the parser is fixed.
## TL;DR
TLDR: the parser is fixed.
tl;dr - the parser is fixed.
- **TL;DR:** the parser is fixed.'

# _proj DIR MANIFEST — a project whose manifest holds MANIFEST ("" = no manifest).
_proj() { mkdir -p "$1/.claude" || return 1; [ -z "$2" ] || printf '%s\n' "$2" > "$1/.claude/manifest.json"; }
ON='{"host":"github","tldr_mode":true}'
# _env MESSAGE [ACTIVE] — a Stop envelope.
_env() { jq -nc --arg m "$1" --argjson a "${2:-false}" '{session_id:"bl312", hook_event_name:"Stop", stop_hook_active:$a, last_assistant_message:$m}'; }
# _hook HOOK DIR ENVELOPE [PATH] — run the hook; sets HRC, HOUT, HERR.
HRC=0; HOUT=""; HERR=""
_hook() {
  local h="$1" d="$2" e="$3" p="${4:-$PATH}"
  printf '%s' "$e" | CLAUDE_PROJECT_DIR="$d" PATH="$p" /bin/bash "$h" > "$WORK/h.out" 2> "$WORK/h.err"
  HRC=$?; HOUT="$(cat "$WORK/h.out")"; HERR="$(cat "$WORK/h.err")"
}
_blocked() { printf '%s' "$HOUT" | jq -e '.decision == "block" and (.reason | type == "string" and length > 0)' >/dev/null 2>&1; }

case_H1() {   # on + no TL;DR → ONE block whose reason names all eight parts and the command rule
  local h="$1/scripts/hooks/tldr-check.sh" d r miss="" p
  d="$(newtmp)"; _proj "$d" "$ON"
  _hook "$h" "$d" "$(_env "$MSG_NONE")"
  r="$(printf '%s' "$HOUT" | jq -r '.reason // ""' 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  for p in "what happened" "what it means for them" "next steps" "what is waiting on them" "the options" \
           "pros and cons of each option" "recommendation, with its reasoning" "what happens if they do nothing" \
           "fenced code block" "restated in full" "tl;dr"; do
    case "$r" in *"$p"*) : ;; *) miss="$miss [$p]" ;; esac
  done
  CASE_DETAIL="rc=$HRC objects=$(printf '%s' "$HOUT" | jq -s 'length' 2>/dev/null) missing:${miss:-none} out=${HOUT:0:160}"
  [ "$HRC" -eq 0 ] && _blocked && [ -z "$miss" ] && [ "$(printf '%s' "$HOUT" | jq -s 'length' 2>/dev/null)" = "1" ]
}
case_H2() {   # on + a TL;DR outside every fence → allow, in every spelling
  local h="$1/scripts/hooks/tldr-check.sh" d s bad=""
  d="$(newtmp)"; _proj "$d" "$ON"
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    _hook "$h" "$d" "$(_env "$MSG_NONE"$'\n\n'"$s")"
    { [ "$HRC" -eq 0 ] && [ -z "$HOUT" ]; } || bad="$bad [$s → rc=$HRC out=${HOUT:0:60}]"
  done <<SPELLINGS
$TLDR_SPELLINGS
SPELLINGS
  _hook "$h" "$d" "$(_env "$MSG_AFTER_FENCE")"
  { [ "$HRC" -eq 0 ] && [ -z "$HOUT" ]; } || bad="$bad [a TL;DR after a closed fence was not seen]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}
case_H3() {   # on + "TL;DR" only inside a fence (``` or ~~~, at column 0 or indented in a list) → block
  local h="$1/scripts/hooks/tldr-check.sh" d a="" b="" c=""
  d="$(newtmp)"; _proj "$d" "$ON"
  _hook "$h" "$d" "$(_env "$MSG_IN_BACKTICK_FENCE")"; _blocked && a=1
  _hook "$h" "$d" "$(_env "$MSG_IN_TILDE_FENCE")"; _blocked && b=1
  _hook "$h" "$d" "$(_env "$MSG_IN_NESTED_FENCE")"; _blocked && c=1
  CASE_DETAIL="backtick-fence blocked=${a:-0} tilde-fence blocked=${b:-0} list-nested-fence blocked=${c:-0}"
  [ "$a" = "1" ] && [ "$b" = "1" ] && [ "$c" = "1" ]
}
case_H4() {   # a filename that contains the token is not a TL;DR
  local h="$1/scripts/hooks/tldr-check.sh" d
  d="$(newtmp)"; _proj "$d" "$ON"
  _hook "$h" "$d" "$(_env "$MSG_FILENAME_ONLY")"
  CASE_DETAIL="rc=$HRC out=${HOUT:0:80}"
  _blocked
}
case_H5() {   # stop_hook_active → allow at once: a reply is sent back at most once a turn
  local h="$1/scripts/hooks/tldr-check.sh" d
  d="$(newtmp)"; _proj "$d" "$ON"
  _hook "$h" "$d" "$(_env "$MSG_NONE" true)"
  CASE_DETAIL="rc=$HRC out=${HOUT:0:80}"
  [ "$HRC" -eq 0 ] && [ -z "$HOUT" ]
}
case_H6() {   # off, absent, a string "true", not JSON, not an object, no manifest → allow (off)
  local h="$1/scripts/hooks/tldr-check.sh" d m bad="" i=0
  for m in '{"tldr_mode":false}' '{"host":"github"}' '{"tldr_mode":"true"}' '{ not json' '[{"tldr_mode":true}]' ''; do
    i=$((i + 1)); d="$(newtmp)"; _proj "$d" "$m"
    _hook "$h" "$d" "$(_env "$MSG_NONE")"
    { [ "$HRC" -eq 0 ] && [ -z "$HOUT" ]; } || bad="$bad [manifest#$i '${m:-<none>}' → rc=$HRC out=${HOUT:0:60}]"
  done
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}
case_H7() {   # no jq → allow, and exactly one stderr line that names jq
  local h="$1/scripts/hooks/tldr-check.sh" d
  d="$(newtmp)"; _proj "$d" "$ON"; mkdir -p "$WORK/nojq-bin"
  PATH="$WORK/nojq-bin" command -v jq >/dev/null 2>&1 && { CASE_DETAIL="jq still resolvable on the narrowed PATH"; return 1; }
  _hook "$h" "$d" "$(_env "$MSG_NONE")" "$WORK/nojq-bin"
  CASE_DETAIL="rc=$HRC out=${HOUT:0:60} err=[$HERR] err-lines=$(printf '%s\n' "$HERR" | awk 'NF' | wc -l | tr -d ' ')"
  [ "$HRC" -eq 0 ] && [ -z "$HOUT" ] && [ "$(printf '%s\n' "$HERR" | awk 'NF' | wc -l | tr -d ' ')" = "1" ] \
    && printf '%s' "$HERR" | command grep -q 'jq'
}
case_H8() {   # no last_assistant_message, or an empty one → allow
  local h="$1/scripts/hooks/tldr-check.sh" d a="" b=""
  d="$(newtmp)"; _proj "$d" "$ON"
  _hook "$h" "$d" '{"hook_event_name":"Stop","stop_hook_active":false}'; { [ "$HRC" -eq 0 ] && [ -z "$HOUT" ]; } && a=1
  _hook "$h" "$d" "$(_env "")"; { [ "$HRC" -eq 0 ] && [ -z "$HOUT" ]; } && b=1
  CASE_DETAIL="field-absent allowed=${a:-0} empty allowed=${b:-0}"
  [ "$a" = "1" ] && [ "$b" = "1" ]
}
case_H9() {   # without CLAUDE_PROJECT_DIR the hook finds the project from its own place
  local d
  d="$(newtmp)"; _proj "$d" "$ON"; mkdir -p "$d/scripts/hooks"
  cp "$1/scripts/hooks/tldr-check.sh" "$d/scripts/hooks/" || { CASE_DETAIL="copy"; return 1; }
  printf '%s' "$(_env "$MSG_NONE")" | ( cd / && env -u CLAUDE_PROJECT_DIR /bin/bash "$d/scripts/hooks/tldr-check.sh" ) > "$WORK/h9.out" 2>&1
  HOUT="$(cat "$WORK/h9.out")"
  CASE_DETAIL="out=${HOUT:0:80}"
  _blocked
}

echo
echo "=== H — the TL;DR-mode Stop hook ==="
check "H1 on, no TL;DR: one block, whose reason names all eight parts, the full-restatement rule and the fenced-command rule" case_H1 "$REPO_ROOT"
check "H2 on, a TL;DR outside every fence (five spellings, and after a closed fence): allowed" case_H2 "$REPO_ROOT"
check "H3 on, TL;DR only inside a \`\`\` or ~~~ fence — at column 0, or indented under a list item: blocked" case_H3 "$REPO_ROOT"
check "H4 on, the token only inside a filename (tl;dr.md, tldr.txt): blocked" case_H4 "$REPO_ROOT"
check "H5 stop_hook_active true: allowed at once, so it sends a reply back at most once a turn" case_H5 "$REPO_ROOT"
check "H6 off, key absent, the string \"true\", not JSON, not an object, no manifest: all allowed" case_H6 "$REPO_ROOT"
check "H7 no jq: allowed, with exactly one stderr line naming jq" case_H7 "$REPO_ROOT"
check "H8 no last_assistant_message, or an empty one: allowed" case_H8 "$REPO_ROOT"
check "H9 CLAUDE_PROJECT_DIR unset: the hook reads the manifest of the project it sits in" case_H9 "$REPO_ROOT"

# ════════════════════════════════════════════════════════════════════════════
# B — the bypass detector beside it (measured on the Stop arm)
# ════════════════════════════════════════════════════════════════════════════
# A TL;DR as the CLAUDE.md section asks for one: options that name a check, a
# recommendation, and the commands in a ``` fence (the detector strips those).
TLDR_COMPLIANT=$'Added a retry to the upload step, with a test.\n\n```\n$ bash tests/test-upload.sh\nResults: 6 passed, 0 failed\n```\n\n**TL;DR**\n- **What happened:** uploads that hit a network hiccup now try again instead of failing.\n- **What it means for you:** fewer failed uploads; nothing changes on your side.\n- **Next steps:** I commit it; the commit check runs the tests first.\n- **Waiting on you:** one decision — whether downloads get the same retry.\n- **Options:** (A) retry downloads too; (B) leave downloads as they are; (C) attest past the download check for now and record why.\n- **Pros and cons:** A is more reliable and about an hour of work. B costs nothing now, but downloads still fail on a bad connection. C unblocks today and leaves a written reason the phase gate will show.\n- **Recommendation:** A — the same hiccup hits downloads, and the fix has the same shape.\n- **If you do nothing:** uploads stay fixed; downloads keep failing now and then.\n- **Commands** — to see the change yourself:\n\n```\ngit log -1 --stat\nbash tests/test-upload.sh\n```'
TLDR_CONTROL="$TLDR_COMPLIANT"$'\n\nOr run `git commit --no-verify` in your terminal to get past the check.'
_detect() {   # _detect ROOT DIR MESSAGE — the bypass detector's Stop arm on MESSAGE
  jq -nc --arg m "$3" '{session_id:"bl312", hook_event_name:"Stop", stop_hook_active:false, last_assistant_message:$m}' \
    | CLAUDE_PROJECT_DIR="$2" bash "$1/scripts/hooks/bypass-detector.sh" >/dev/null 2>&1
}
case_B1() {   # a compliant TL;DR: the TL;DR hook allows it, the detector writes no row and no sentinel
  local d rows
  d="$(newtmp)"; _proj "$d" "$ON"
  _hook "$1/scripts/hooks/tldr-check.sh" "$d" "$(_env "$TLDR_COMPLIANT")"
  _detect "$1" "$d" "$TLDR_COMPLIANT"
  rows="$(jq 'length' "$d/.claude/bypass-audit.json" 2>/dev/null)"
  CASE_DETAIL="tldr-hook rc=$HRC out=${HOUT:0:60} audit-rows=${rows:-none} sentinel=$([ -f "$d/.claude/pending-approval.json" ] && echo yes || echo no)"
  [ "$HRC" -eq 0 ] && [ -z "$HOUT" ] && [ ! -f "$d/.claude/pending-approval.json" ] && { [ -z "$rows" ] || [ "$rows" = "0" ]; }
}
case_B2() {   # the control: the same reply plus a prose escape → the detector was live
  local d
  d="$(newtmp)"; _proj "$d" "$ON"
  _detect "$1" "$d" "$TLDR_CONTROL"
  CASE_DETAIL="patterns=$(jq -r '[.[].details.pattern] | join(",")' "$d/.claude/bypass-audit.json" 2>/dev/null) sentinel=$([ -f "$d/.claude/pending-approval.json" ] && echo yes || echo no)"
  jq -e '[.[].details.pattern] | index("no_verify") != null' "$d/.claude/bypass-audit.json" >/dev/null 2>&1 \
    && [ -f "$d/.claude/pending-approval.json" ]
}
# THREE TL;DRs THE OLD WORDING RULE ALLOWED AND THE DETECTOR STILL FLAGGED (BL-312
# review round 1). terminal_workaround is `(run|do|execute) [^.]*(terminal|shell)`:
# a substring match, per line, that stops only at a full stop — so "do (a) — in a
# nutshell", "now run shellcheck" and "do nothing: every payment terminal" all
# match. Each pair is the flagged line and the same line under the CLAUDE.md
# section's rule (neither word, nor any word holding one, anywhere in the TL;DR).
B3_BODY=$'**TL;DR**\n1. What happened: the nightly backup job now retries twice before giving up.\n2. What it means for you: fewer false alarms in the morning.\n3. Next steps: none from me on this.\n4. What is waiting on you: nothing.\n5. Options: (a) keep it; (b) roll it back.\n6. Pros and cons: (a) fewer alarms, slightly slower failure reports; (b) the old noise.'
B3_OLD_1="$B3_BODY"$'\n7. Recommendation: do (a) — in a nutshell, it is the smaller risk.\n8. If you do nothing: it stays as it is now, which is fine.'
B3_NEW_1="$B3_BODY"$'\n7. Recommendation: do (a) — in short, it is the smaller risk.\n8. If you do nothing: it stays as it is now, which is fine.'
B3_OLD_2=$'**TL;DR**\n1. What happened: the commit checks now run shellcheck, so script mistakes are caught early.\n8. If you do nothing: nothing changes.'
B3_NEW_2=$'**TL;DR**\n1. What happened: the commit checks now run a script linter, so script mistakes are caught early.\n8. If you do nothing: nothing changes.'
B3_OLD_3="$B3_BODY"$'\n7. Recommendation: (a), so a real shop proves it first.\n8. If you do nothing: every payment terminal on the new firmware keeps crashing at start-up.'
B3_NEW_3="$B3_BODY"$'\n7. Recommendation: (a), so a real shop proves it first.\n8. If you do nothing: every payment card reader on the new firmware keeps crashing at start-up.'
case_B3() {   # each reworded TL;DR: allowed by the TL;DR hook, no row and no sentinel; its original raises terminal_workaround
  local i="" old="" new="" d="" bad=""
  for i in 1 2 3; do
    case "$i" in
      1) old="$B3_OLD_1"; new="$B3_NEW_1" ;;
      2) old="$B3_OLD_2"; new="$B3_NEW_2" ;;
      *) old="$B3_OLD_3"; new="$B3_NEW_3" ;;
    esac
    d="$(newtmp)"; _proj "$d" "$ON"
    _detect "$1" "$d" "$old"
    { [ -f "$d/.claude/pending-approval.json" ] \
        && jq -e '[.[].details.pattern] | index("terminal_workaround") != null' "$d/.claude/bypass-audit.json" >/dev/null 2>&1; } \
      || bad="$bad [pair $i: the original did not raise terminal_workaround, so this pair proves nothing]"
    d="$(newtmp)"; _proj "$d" "$ON"
    _hook "$1/scripts/hooks/tldr-check.sh" "$d" "$(_env "$new")"
    { [ "$HRC" -eq 0 ] && [ -z "$HOUT" ]; } || bad="$bad [pair $i: the TL;DR hook sent the reworded reply back]"
    _detect "$1" "$d" "$new"
    { [ ! -f "$d/.claude/pending-approval.json" ] && [ ! -s "$d/.claude/bypass-audit.json" ]; } \
      || bad="$bad [pair $i: the reworded TL;DR raised $(jq -r '[.[].details.pattern] | join(",")' "$d/.claude/bypass-audit.json" 2>/dev/null)]"
  done
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}
echo
echo "=== B — beside the bypass detector ==="
check "B1 a compliant TL;DR (options naming checks, commands fenced): the TL;DR hook allows it; the bypass detector writes no row and no sentinel" case_B1 "$REPO_ROOT"
check "B2 control: the same reply plus 'run \`git commit --no-verify\` in your terminal' — the detector records it and raises the sentinel" case_B2 "$REPO_ROOT"
check "B3 three TL;DRs the detector flagged ('in a nutshell', 'run shellcheck', 'payment terminal'), reworded with neither word: the TL;DR hook allows them; no row, no sentinel" case_B3 "$REPO_ROOT"

# ════════════════════════════════════════════════════════════════════════════
# W — the wiring
# ════════════════════════════════════════════════════════════════════════════
GR_STOP='{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/stop-checklist.sh"}]}]}}'
_roster() {   # _roster ROOT FILE MODE — the shared roster, in a subshell; prints SOIF_ROSTER_ADDED
  ( . "$1/scripts/lib/claude-settings.sh" >/dev/null 2>&1 || exit 3
    soif_register_hook_roster "$2" "$3" >/dev/null 2>&1; printf '%s' "${SOIF_ROSTER_ADDED:-}" )
}
_stopcmds() { jq -r '[.hooks.Stop[]?.hooks[]?.command] | join("\n")' "$1" 2>/dev/null; }
_count_in() { printf '%s\n' "$1" | command grep -cF -- "$2"; }
case_W1() {   # init mode: in Stop group 0 beside the bypass detector, once; a second run adds nothing
  local f c n_tl n_bd g0 again
  f="$(newtmp)/settings.json"; printf '{}\n' > "$f"
  _roster "$1" "$f" init >/dev/null
  c="$(_stopcmds "$f")"; n_tl="$(_count_in "$c" 'scripts/hooks/tldr-check.sh')"; n_bd="$(_count_in "$c" 'scripts/hooks/bypass-detector.sh')"
  g0="$(jq -r '[.hooks.Stop[0].hooks[]?.command] | join(" ")' "$f" 2>/dev/null)"
  again="$(_roster "$1" "$f" init)"
  CASE_DETAIL="tldr=$n_tl bypass=$n_bd group0=[$g0] second-run-added=$again after-second=$(_count_in "$(_stopcmds "$f")" 'tldr-check.sh')"
  [ "$n_tl" = "1" ] && [ "$n_bd" = "1" ] && case "$g0" in *tldr-check.sh*) true ;; *) false ;; esac \
    && [ "$again" = "false" ] && [ "$(_count_in "$(_stopcmds "$f")" 'tldr-check.sh')" = "1" ] \
    && [ "$(jq -r '[.hooks.Stop[]?.hooks[]? | select(.command | contains("tldr-check.sh")) | .command] | first' "$f")" = 'bash "$CLAUDE_PROJECT_DIR"/scripts/hooks/tldr-check.sh' ]
}
case_W2() {   # adoption mode registers it too, beside a Guardrails Stop hook already there
  local f g0
  f="$(newtmp)/settings.json"; printf '%s\n' "$GR_STOP" > "$f"
  _roster "$1" "$f" adoption >/dev/null
  g0="$(jq -r '[.hooks.Stop[0].hooks[]?.command] | join(" | ")' "$f" 2>/dev/null)"
  CASE_DETAIL="group0=[$g0] groups=$(jq '.hooks.Stop | length' "$f")"
  case "$g0" in *stop-checklist.sh*bypass-detector.sh*tldr-check.sh*) true ;; *) false ;; esac \
    && [ "$(jq '.hooks.Stop | length' "$f")" = "1" ]
}
case_W3() {   # init.sh's copy list ships the hook and its lib (adoption and --sync-framework read the same list)
  local set
  set="$( . "$1/scripts/lib/scaffold-shipped-set.sh" && soif_parse_shipped_scripts "$1/init.sh" "$1/scripts" )"
  CASE_DETAIL="hook=$(_count_in "$set" 'scripts/hooks/tldr-check.sh') lib=$(_count_in "$set" 'scripts/lib/tldr-mode.sh') executable=$([ -x "$1/scripts/hooks/tldr-check.sh" ] && echo yes || echo no)"
  [ "$(_count_in "$set" 'scripts/hooks/tldr-check.sh')" = "1" ] && [ "$(_count_in "$set" 'scripts/lib/tldr-mode.sh')" = "1" ] \
    && [ -x "$1/scripts/hooks/tldr-check.sh" ]
}
echo
echo "=== W — the wiring ==="
check "W1 the shared roster registers it in Stop group 0 beside the bypass detector, once, with the framework's command spelling; a re-run adds nothing" case_W1 "$REPO_ROOT"
check "W2 adoption mode registers it too — in the SAME group as a Guardrails stop-checklist already there, after theirs" case_W2 "$REPO_ROOT"
check "W3 init.sh's copy list ships scripts/hooks/tldr-check.sh (executable) and scripts/lib/tldr-mode.sh" case_W3 "$REPO_ROOT"

# ════════════════════════════════════════════════════════════════════════════
# C — the CLAUDE.md section and the [y/N] reader
# ════════════════════════════════════════════════════════════════════════════
_lib() { ( . "$1/scripts/lib/tldr-mode.sh" >/dev/null 2>&1 || exit 3; shift; "$@" ); }
case_C1() {   # on adds it once; on again changes nothing; off restores the bytes; off with none changes nothing
  local d f orig on1 n p miss=""
  d="$(newtmp)"; f="$d/CLAUDE.md"
  printf '# CLAUDE.md — demo\n\n## Project Identity\n- x\n\n### UAT Test Sessions\n- y\n' > "$f"; cp "$f" "$d/orig"
  _lib "$1" soif_tldr_apply_claude_md "$f" on || { CASE_DETAIL="on rc=$?"; return 1; }
  cp "$f" "$d/on1"
  n="$(command grep -cxF '<!-- tldr-mode:begin -->' "$f")"
  for p in "### TL;DR Mode" "what happened" "what it means for them" "next steps" "what is waiting on them" \
           "the options" "pros and cons of each option" "recommendation, with its reasoning" \
           "what happens if they do nothing" "fenced code block" "--tldr-mode off"; do
    command grep -qiF -- "$p" "$f" || miss="$miss [$p]"
  done
  _lib "$1" soif_tldr_apply_claude_md "$f" on || { CASE_DETAIL="second on rc=$?"; return 1; }
  cmp -s "$f" "$d/on1" || { CASE_DETAIL="a second 'on' changed the file"; return 1; }
  _lib "$1" soif_tldr_apply_claude_md "$f" off || { CASE_DETAIL="off rc=$?"; return 1; }
  cmp -s "$f" "$d/orig" || { CASE_DETAIL="'off' did not restore the original bytes: $(diff "$d/orig" "$f" | head -5 | tr '\n' '|')"; return 1; }
  _lib "$1" soif_tldr_apply_claude_md "$f" off || { CASE_DETAIL="off-on-absent rc=$?"; return 1; }
  CASE_DETAIL="begin-markers=$n missing:${miss:-none}"
  cmp -s "$f" "$d/orig" && [ "$n" = "1" ] && [ -z "$miss" ]
}
case_C2() {   # damaged markers (an opener alone; two sections) are refused and the file is left alone
  local d f bad=""
  d="$(newtmp)"; f="$d/CLAUDE.md"
  printf '# x\n\n<!-- tldr-mode:begin -->\n### TL;DR Mode (on)\nkept text\n' > "$f"; cp "$f" "$d/o1"
  _lib "$1" soif_tldr_apply_claude_md "$f" off && bad="$bad [opener alone: off returned 0]"
  cmp -s "$f" "$d/o1" || bad="$bad [opener alone: file changed]"
  _lib "$1" soif_tldr_apply_claude_md "$f" on && bad="$bad [opener alone: on returned 0]"
  cmp -s "$f" "$d/o1" || bad="$bad [opener alone: file changed by on]"
  printf '# x\n<!-- tldr-mode:begin -->\na\n<!-- tldr-mode:end -->\n<!-- tldr-mode:begin -->\nb\n<!-- tldr-mode:end -->\n' > "$f"; cp "$f" "$d/o2"
  _lib "$1" soif_tldr_apply_claude_md "$f" off && bad="$bad [two sections: off returned 0]"
  cmp -s "$f" "$d/o2" || bad="$bad [two sections: file changed]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}
case_C3() {   # init.sh's [y/N] reader: y / Y / yes are yes; empty, n, no, 1, 2, "sure" are no
  local a bad=""
  for a in y Y yes Yes; do _lib "$1" soif_tldr_yes "$a" || bad="$bad [$a → no]"; done
  for a in "" n N no 1 2 sure; do _lib "$1" soif_tldr_yes "$a" && bad="$bad ['$a' → yes]"; done
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}
case_C4() {   # the section's wording rule matches the detector: neither of ITS words anywhere, ``` fences only, and the section itself trips nothing
  local sec="" words="" w="" miss="" hits=""
  sec="$(_lib "$1" soif_tldr_claude_md_section)" || { CASE_DETAIL="no section"; return 1; }
  # The words come from the detector's own pattern — its last group — so a word
  # added there and not here is a failure, not a quiet gap.
  words="$( . "$1/scripts/lib/bypass-patterns.sh" >/dev/null 2>&1 && pattern_regex_for terminal_workaround \
    | sed -n 's/.*(\([a-z|]*\))$/\1/p' | tr '|' '\n' )"
  [ -n "$words" ] || { CASE_DETAIL="could not read the words from terminal_workaround"; return 1; }
  for w in $words; do
    printf '%s' "$sec" | command grep -qF "\"$w\"" || miss="$miss [\"$w\" not named]"
  done
  for w in "PowerShell" "shellcheck" "nutshell" 'say "the command line" instead' "anywhere in the TL;DR" \
           'opened with ``` (not ~~~)' "it skips only \`\`\` blocks"; do
    printf '%s' "$sec" | command grep -qF -- "$w" || miss="$miss [$w]"
  done
  printf '%s' "$sec" | command grep -qF 'out of any sentence' && miss="$miss [the old sentence-scoped rule is still there]"
  hits="$( . "$1/scripts/lib/bypass-patterns.sh" >/dev/null 2>&1 && scan_bypass_patterns_all "$sec" | tr '\n' ' ' )"
  CASE_DETAIL="words=[$(printf '%s' "$words" | tr '\n' ' ')] missing:${miss:-none} the section itself matches:[${hits:-nothing}]"
  [ -z "$miss" ] && [ -z "$hits" ]
}
echo
echo "=== C — the CLAUDE.md section and the reader ==="
check "C1 'on' adds the section once (eight parts, the command rule, the way off); 'on' again changes nothing; 'off' restores the exact bytes" case_C1 "$REPO_ROOT"
check "C2 damaged markers — an opener alone, or two sections — are refused, and CLAUDE.md is left as it was" case_C2 "$REPO_ROOT"
check "C3 the [y/N] reader: y, Y, yes, Yes are yes; empty, n, N, no, 1, 2, 'sure' are no" case_C3 "$REPO_ROOT"
check "C4 the section's command rule: never the detector's own words (read from terminal_workaround) nor PowerShell/shellcheck/nutshell anywhere in the TL;DR, 'the command line' instead, \`\`\` fences not ~~~; the section trips no detector pattern" case_C4 "$REPO_ROOT"

# ════════════════════════════════════════════════════════════════════════════
# S — init.sh, by structure (tests/test-bl312-tldr-mode-init.sh runs it)
# ════════════════════════════════════════════════════════════════════════════
case_S1() {   # the interactive question is asked with [y/N] and read by soif_tldr_yes
  local body
  body="$(awk '/^collect_project_info\(\) \{/{f=1} f{print} f&&/^}/{exit}' "$1/init.sh")"
  CASE_DETAIL="question=$(_count_in "$body" 'SOIF_TLDR_QUESTION') yN=$(_count_in "$body" '[y/N]') reader=$(_count_in "$body" 'soif_tldr_yes')"
  printf '%s\n' "$body" | command grep -F 'SOIF_TLDR_QUESTION' | command grep -qF '[y/N]' \
    && [ "$(_count_in "$body" 'soif_tldr_yes "$')" -ge 1 ]
}
case_S2() {   # all four manifest seed writes carry tldr_mode, and the config key is known and documented
  local body n
  body="$(awk '/^prepare_initial_state_for_commit\(\) \{/{f=1} f{print} f&&/^}/{exit}' "$1/init.sh")"
  n="$(_count_in "$body" 'tldr_mode:$tl')"
  CASE_DETAIL="seed-writes-with-tldr_mode=$n known-field=$(command grep -c 'known_fields=.* tldr_mode' "$1/init.sh") help=$(command grep -c '"tldr_mode": false' "$1/init.sh")"
  [ "$n" = "4" ] && command grep -q 'known_fields=.* tldr_mode' "$1/init.sh" && command grep -q '"tldr_mode": false' "$1/init.sh"
}
case_S3() {   # the one top-level default is false: a flags-only non-interactive run (no --config) reads nothing else
  local lines
  lines="$(command grep -nE '^TLDR_MODE=' "$1/init.sh")"
  CASE_DETAIL="top-level assignments: [$(printf '%s' "$lines" | tr '\n' '|')]"
  [ "$(printf '%s\n' "$lines" | awk 'NF' | wc -l | tr -d ' ')" = "1" ] \
    && printf '%s' "$lines" | command grep -qE '^[0-9]+:TLDR_MODE=false[[:space:]]+# BL-312-INIT-DEFAULT$'
}
echo
echo "=== S — init.sh, by structure ==="
check "S1 init.sh's interactive setup asks the TL;DR question with [y/N] and reads the answer with soif_tldr_yes" case_S1 "$REPO_ROOT"
check "S2 all four manifest seed writes carry tldr_mode; the --config key is known and in the --help-non-interactive example" case_S2 "$REPO_ROOT"
check "S3 init.sh has one top-level TLDR_MODE assignment, and it is false (# BL-312-INIT-DEFAULT) — the only thing that keeps a flags-only --non-interactive run off" case_S3 "$REPO_ROOT"

# ════════════════════════════════════════════════════════════════════════════
# A — adoption
# ════════════════════════════════════════════════════════════════════════════
TLQ='Do you want every reply to end with a plain-English summary of what happened, your options and a recommendation?'
_base() {   # a small Python project, committed
  local p="$1"
  mkdir -p "$p/src" || return 1
  ( cd "$p" && git init -q . && git config user.email bl312@test.invalid && git config user.name "BL312 Test" ) >/dev/null 2>&1
  printf '[project]\nname = "kp"\nversion = "0.1.0"\n' > "$p/pyproject.toml"
  printf 'x = 1\n' > "$p/src/app.py"
  ( cd "$p" && git add -- pyproject.toml src/app.py && git commit -q --no-verify -m "chore: their history" ) >/dev/null 2>&1
}
GR_MANIFEST='{"frameworkVersion":"4.3.0","frameworkRepo":"kraulerson/claude-dev-framework","profile":"desktop-app","activeHooks":["session-start","stop-checklist"],"frameworkCommit":"0396a1a"}'
_gr() {   # _gr DIR [MANIFEST] — the Development Guardrails' own .claude/, committed (adoption keeps it)
  local p="$1" m="${2:-$GR_MANIFEST}"
  _base "$p" || return 1
  mkdir -p "$p/.claude/framework/hooks" || return 1
  printf '%s\n' "$m" > "$p/.claude/manifest.json"
  printf '%s\n' "$GR_STOP" | jq . > "$p/.claude/settings.json"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$p/.claude/framework/hooks/stop-checklist.sh"
  ( cd "$p" && git add -- .claude/manifest.json .claude/settings.json .claude/framework && git commit -q --no-verify -m "chore: guardrails" ) >/dev/null 2>&1
}
# _adopt ROOT DIR TAG ANSWERS — ANSWERS is a printf format. Sets RUN_RC.
RUN_RC=0
_adopt() {
  local root="$1" p="$2" tag="$3" ans="$4"
  # shellcheck disable=SC2059
  ( cd "$p" && printf "$ans" | SOIF_ADOPT_QDRANT=no SOIF_ADOPT_GUARDRAILS_DIR="$NOCLONE" \
      bash "$root/scripts/adopt-project.sh" ) > "$WORK/$tag.out" 2>&1
  RUN_RC=$?
}
_mode() { jq -c '.tldr_mode' "$1/.claude/manifest.json" 2>/dev/null; }
_section() { command grep -cxF '<!-- tldr-mode:begin -->' "$1/CLAUDE.md" 2>/dev/null; }
# THE ANSWERS. The tier, the track, then the four scan-derived confirmations —
# exactly as long as this fixture's questions; the TL;DR question comes LAST.
ANS='1\nstandard\n1\n1\n1\n1\n'
case_AY() {   # "yes": on, the CLAUDE.md section, the hook wired, all committed; the question is LAST
  local p bad="" q last_keep inst
  p="$(newtmp)/p"; _base "$p" || { CASE_DETAIL="fixture"; return 1; }
  _adopt "$1" "$p" ay "${ANS}yes\n"
  [ "$RUN_RC" -eq 0 ] || bad="$bad [rc $RUN_RC: $(command grep -m1 -E 'REFUSED|BLOCKED' "$WORK/ay.out")]"
  [ "$(_mode "$p")" = "true" ] || bad="$bad [tldr_mode=$(_mode "$p")]"
  [ "$(_section "$p")" = "1" ] || bad="$bad [section markers=$(_section "$p")]"
  [ "$(_count_in "$(_stopcmds "$p/.claude/settings.json")" 'scripts/hooks/tldr-check.sh')" = "1" ] || bad="$bad [hook not wired once]"
  [ "$( cd "$p" && git show HEAD:.claude/manifest.json 2>/dev/null | jq -c .tldr_mode)" = "true" ] || bad="$bad [the committed manifest is not on]"
  ( cd "$p" && git show HEAD:CLAUDE.md 2>/dev/null ) | command grep -qxF '<!-- tldr-mode:begin -->' || bad="$bad [the committed CLAUDE.md has no section]"
  [ -f "$p/scripts/hooks/tldr-check.sh" ] && [ -f "$p/scripts/lib/tldr-mode.sh" ] || bad="$bad [hook or lib not installed]"
  [ "$(command grep -cF "$TLQ" "$WORK/ay.out")" = "1" ] || bad="$bad [the question printed $(command grep -cF "$TLQ" "$WORK/ay.out") time(s)]"
  q="$(command grep -nF "$TLQ" "$WORK/ay.out" | head -1 | cut -d: -f1)"
  last_keep="$(command grep -nF 'as the answer?' "$WORK/ay.out" | tail -1 | cut -d: -f1)"
  inst="$(command grep -nE '^   Installed [0-9]+ framework script' "$WORK/ay.out" | head -1 | cut -d: -f1)"
  { [ -n "$q" ] && [ -n "$last_keep" ] && [ -n "$inst" ] && [ "$q" -gt "$last_keep" ] && [ "$q" -lt "$inst" ]; } \
    || bad="$bad [position: question@${q:-?} last-confirmation@${last_keep:-?} first-install-line@${inst:-?}]"
  command grep -A2 -F "$TLQ" "$WORK/ay.out" | command grep -q '1) no' || bad="$bad [option 1 is not 'no']"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}
case_AN() {   # "no" on a Guardrails project: false WRITTEN, no section, the hook wired beside theirs
  local p="$2" bad="" g0
  _gr "$p" || { CASE_DETAIL="fixture"; return 1; }
  _adopt "$1" "$p" an "${ANS}no\n"
  [ "$RUN_RC" -eq 0 ] || bad="$bad [rc $RUN_RC: $(command grep -m1 -E 'REFUSED|BLOCKED' "$WORK/an.out")]"
  [ "$(_mode "$p")" = "false" ] || bad="$bad [tldr_mode=$(_mode "$p"), want false written]"
  [ "$(_section "$p")" = "0" ] || bad="$bad [a section was written]"
  g0="$(jq -r '[.hooks.Stop[0].hooks[]?.command] | join(" | ")' "$p/.claude/settings.json" 2>/dev/null)"
  case "$g0" in *stop-checklist.sh*bypass-detector.sh*tldr-check.sh*) : ;; *) bad="$bad [Stop group 0: $g0]" ;; esac
  jq -e '.frameworkVersion == "4.3.0" and .profile == "desktop-app"' "$p/.claude/manifest.json" >/dev/null 2>&1 || bad="$bad [their Guardrails keys changed]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}
case_AE() {   # end of input at the question: off, written as false, and said
  local p bad=""
  p="$(newtmp)/p"; _base "$p" || { CASE_DETAIL="fixture"; return 1; }
  _adopt "$1" "$p" ae "$ANS"
  [ "$RUN_RC" -eq 0 ] || bad="$bad [rc $RUN_RC: $(command grep -m1 -E 'REFUSED|BLOCKED' "$WORK/ae.out")]"
  [ "$(_mode "$p")" = "false" ] || bad="$bad [tldr_mode=$(_mode "$p")]"
  command grep -qF 'No answer — TL;DR mode is off.' "$WORK/ae.out" || bad="$bad [end of input was not said]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}
case_A1() {   # a stray `1` — the padding older answer sequences carry — cannot turn it on
  local p bad=""
  p="$(newtmp)/p"; _base "$p" || { CASE_DETAIL="fixture"; return 1; }
  _adopt "$1" "$p" a1 "${ANS}1\n1\n1\n1\n"
  [ "$RUN_RC" -eq 0 ] || bad="$bad [rc $RUN_RC: $(command grep -m1 -E 'REFUSED|BLOCKED' "$WORK/a1.out")]"
  [ "$(_mode "$p")" = "false" ] || bad="$bad [tldr_mode=$(_mode "$p")]"
  [ "$(_section "$p")" = "0" ] || bad="$bad [a section was written]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}
case_A2() {   # `2` is the number offered for yes
  local p
  p="$(newtmp)/p"; _base "$p" || { CASE_DETAIL="fixture"; return 1; }
  _adopt "$1" "$p" a2 "${ANS}2\n"
  CASE_DETAIL="rc=$RUN_RC tldr_mode=$(_mode "$p") section=$(_section "$p")"
  [ "$RUN_RC" -eq 0 ] && [ "$(_mode "$p")" = "true" ] && [ "$(_section "$p")" = "1" ]
}
case_AR() {   # an answer that is not offered refuses before anything is written
  local p bad="" head0
  p="$(newtmp)/p"; _base "$p" || { CASE_DETAIL="fixture"; return 1; }
  head0="$( cd "$p" && git rev-parse HEAD )"
  _adopt "$1" "$p" ar "${ANS}maybe\n"
  [ "$RUN_RC" -eq 1 ] || bad="$bad [rc $RUN_RC]"
  command grep -qF "[REFUSED] 'maybe' is not one of the answers offered for: TL;DR mode" "$WORK/ar.out" || bad="$bad [no refusal naming the question]"
  [ ! -e "$p/.claude/manifest.json" ] || bad="$bad [a manifest was written]"
  [ ! -e "$p/scripts/hooks/tldr-check.sh" ] || bad="$bad [framework scripts were installed]"
  [ "$( cd "$p" && git rev-parse HEAD )" = "$head0" ] || bad="$bad [a commit landed]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}
echo
echo "=== A — adoption asks it last, and only 'yes' turns it on ==="
AN_P="$WORK/an-project"
check "AY 'yes': manifest tldr_mode true, CLAUDE.md section, hook wired, all committed; asked once, after the last confirmation, before any install" case_AY "$REPO_ROOT"
check "AN 'no' on a Guardrails project: tldr_mode false WRITTEN, no section, the hook wired in their Stop group after stop-checklist and the bypass detector" case_AN "$REPO_ROOT" "$AN_P"
check "AE end of input at the question: off — false written — and the run says so" case_AE "$REPO_ROOT"
check "A1 a stray '1' (the padding older answer sequences carry): off — option 1 is 'no'" case_A1 "$REPO_ROOT"
check "A2 '2', the number offered for yes: on" case_A2 "$REPO_ROOT"
check "AR an answer not offered ('maybe'): REFUSED naming the question; no manifest, no scripts, no commit" case_AR "$REPO_ROOT"

# ════════════════════════════════════════════════════════════════════════════
# R — reconfigure-project.sh --tldr-mode, from the adopted project's own copy
# ════════════════════════════════════════════════════════════════════════════
# RECONF DIR ARGS… — run the project's own reconfigure from inside it. Sets RC_RC.
RC_RC=0
_reconf() { local d="$1"; shift; ( cd "$d" && bash scripts/reconfigure-project.sh "$@" ) > "$WORK/reconf.out" 2>&1; RC_RC=$?; }
# Reconfigure cases take the PROJECT (a copy of AN's), not a framework root.
_rproj() {   # _rproj — a fresh copy of the adopted, off project, with the TL;DR hook UNWIRED
  local d
  d="$(newtmp)/p"; cp -Rp "$AN_P" "$d" || return 1
  jq '.hooks.Stop |= map(.hooks |= map(select(.command | contains("tldr-check.sh") | not)))' "$d/.claude/settings.json" > "$d/s.tmp" \
    && mv "$d/s.tmp" "$d/.claude/settings.json"
  printf '%s\n' "$d"
}
case_R1() {   # on → off → on: key, section and wiring follow; off restores CLAUDE.md; on again repeats on exactly
  local d="$1" bad="" n
  cp "$d/CLAUDE.md" "$d/../claude.orig"
  _reconf "$d" --tldr-mode on
  [ "$RC_RC" -eq 0 ] || bad="$bad [on: rc $RC_RC: $(tail -3 "$WORK/reconf.out" | tr '\n' '|')]"
  [ "$(_mode "$d")" = "true" ] || bad="$bad [on: tldr_mode=$(_mode "$d")]"
  [ "$(_section "$d")" = "1" ] || bad="$bad [on: section=$(_section "$d")]"
  n="$(_count_in "$(_stopcmds "$d/.claude/settings.json")" 'scripts/hooks/tldr-check.sh')"
  [ "$n" = "1" ] || bad="$bad [on: the hook is wired $n time(s)]"
  cp "$d/CLAUDE.md" "$d/../claude.on"
  _reconf "$d" --tldr-mode off
  [ "$RC_RC" -eq 0 ] || bad="$bad [off: rc $RC_RC]"
  [ "$(_mode "$d")" = "false" ] || bad="$bad [off: tldr_mode=$(_mode "$d")]"
  cmp -s "$d/CLAUDE.md" "$d/../claude.orig" || bad="$bad [off: CLAUDE.md is not what it was before 'on']"
  _reconf "$d" --tldr-mode on
  [ "$RC_RC" -eq 0 ] || bad="$bad [on again: rc $RC_RC]"
  [ "$(_mode "$d")" = "true" ] || bad="$bad [on again: tldr_mode=$(_mode "$d")]"
  cmp -s "$d/CLAUDE.md" "$d/../claude.on" || bad="$bad [on again: CLAUDE.md differs from the first 'on']"
  [ "$(_count_in "$(_stopcmds "$d/.claude/settings.json")" 'tldr-check.sh')" = "1" ] || bad="$bad [on again: wired twice]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}
case_R2() {   # a value that is not on/off refuses and changes nothing
  local d="$1" m c s
  m="$(cat "$d/.claude/manifest.json")"; c="$(cat "$d/CLAUDE.md")"; s="$(cat "$d/.claude/settings.json")"
  _reconf "$d" --tldr-mode maybe
  CASE_DETAIL="rc=$RC_RC out=$(tail -2 "$WORK/reconf.out" | tr '\n' '|')"
  [ "$RC_RC" -eq 1 ] && [ "$m" = "$(cat "$d/.claude/manifest.json")" ] && [ "$c" = "$(cat "$d/CLAUDE.md")" ] \
    && [ "$s" = "$(cat "$d/.claude/settings.json")" ]
}
case_R3() {   # 'on' without the hook script installed refuses and changes nothing
  local d="$1" m
  m="$(cat "$d/.claude/manifest.json")"
  mv "$d/scripts/hooks/tldr-check.sh" "$d/../hook.away"
  _reconf "$d" --tldr-mode on
  mv "$d/../hook.away" "$d/scripts/hooks/tldr-check.sh"
  CASE_DETAIL="rc=$RC_RC out=$(tail -3 "$WORK/reconf.out" | tr '\n' '|')"
  [ "$RC_RC" -eq 1 ] && [ "$m" = "$(cat "$d/.claude/manifest.json")" ] && [ "$(_section "$d")" = "0" ] \
    && command grep -q 'tldr-check.sh' "$WORK/reconf.out"
}
case_R4() {   # --help names the option
  local d="$1"
  _reconf "$d" --help
  CASE_DETAIL="rc=$RC_RC"
  [ "$RC_RC" -eq 0 ] && command grep -qF -- '--tldr-mode <on|off>' "$WORK/reconf.out"
}
case_R5() {   # a write that fails part-way (CLAUDE.md read-only): rc 1, the [FAIL] said, every file as before, no backup left
  local d="$1" bad="" t="" left=""
  t="$(newtmp)"
  cp -p "$d/.claude/manifest.json" "$d/../m.before"; cp -p "$d/.claude/settings.json" "$d/../s.before"; cp -p "$d/CLAUDE.md" "$d/../c.before"
  chmod 444 "$d/CLAUDE.md"
  ( cd "$d" && TMPDIR="$t" bash scripts/reconfigure-project.sh --tldr-mode on ) > "$WORK/reconf.out" 2>&1; RC_RC=$?
  chmod 644 "$d/CLAUDE.md"
  [ "$RC_RC" -eq 1 ] || bad="$bad [rc $RC_RC]"
  command grep -F '[FAIL]' "$WORK/reconf.out" | command grep -qF 'TL;DR mode was not changed: CLAUDE.md could not be edited' \
    || bad="$bad [no [FAIL] line naming CLAUDE.md: $(tail -2 "$WORK/reconf.out" | tr '\n' '|')]"
  cmp -s "$d/../m.before" "$d/.claude/manifest.json" || bad="$bad [the manifest was not put back: tldr_mode=$(_mode "$d")]"
  cmp -s "$d/../s.before" "$d/.claude/settings.json" || bad="$bad [settings.json was not put back]"
  cmp -s "$d/../c.before" "$d/CLAUDE.md" || bad="$bad [CLAUDE.md changed]"
  left="$(ls -A "$t"; ls -A "$d" "$d/.claude" | command grep -E 'tldr-mode\.|\.tmp$')"
  [ -z "$left" ] || bad="$bad [left behind: $(printf '%s' "$left" | tr '\n' ' ')]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}
case_R6() {   # 'on' when already on rewrites a hand-edited section to the current wording, and says so; a current one is said to be current
  local d="$1" bad=""
  _reconf "$d" --tldr-mode on
  [ "$RC_RC" -eq 0 ] || { CASE_DETAIL="first on: rc $RC_RC"; return 1; }
  command grep -qF 'CLAUDE.md: the TL;DR Mode section was added' "$WORK/reconf.out" || bad="$bad [first on: not said to be added: $(command grep -F 'CLAUDE.md:' "$WORK/reconf.out")]"
  cp "$d/CLAUDE.md" "$d/../c.current"
  awk '{ print } $0 == "<!-- tldr-mode:begin -->" { print "My own note, inside the markers." }' "$d/../c.current" > "$d/CLAUDE.md"
  _reconf "$d" --tldr-mode on
  [ "$RC_RC" -eq 0 ] || bad="$bad [second on: rc $RC_RC]"
  command grep -qF 'CLAUDE.md: the TL;DR Mode section was rewritten with the current wording' "$WORK/reconf.out" \
    || bad="$bad [second on: not said to be rewritten: $(command grep -F 'CLAUDE.md:' "$WORK/reconf.out")]"
  cmp -s "$d/CLAUDE.md" "$d/../c.current" || bad="$bad [second on: the section is not the current wording]"
  _reconf "$d" --tldr-mode on
  command grep -qF 'CLAUDE.md: the TL;DR Mode section is already there, as current' "$WORK/reconf.out" \
    || bad="$bad [third on: not said to be current: $(command grep -F 'CLAUDE.md:' "$WORK/reconf.out")]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}
case_R7() {   # --tldr-mode with another change (either order) is refused, naming it; nothing changed
  local d="$1" bad="" m=""
  m="$(cat "$d/.claude/manifest.json")"
  _reconf "$d" --tldr-mode off --enforcement-level light --confirm-pitfalls
  [ "$RC_RC" -eq 1 ] || bad="$bad [tldr first: rc $RC_RC]"
  command grep -F '[FAIL]' "$WORK/reconf.out" | command grep -F 'cannot be combined with' | command grep -qF -- '--enforcement-level' \
    || bad="$bad [tldr first: no refusal naming --enforcement-level: $(tail -2 "$WORK/reconf.out" | tr '\n' '|')]"
  _reconf "$d" --enforcement-level light --confirm-pitfalls --tldr-mode on
  [ "$RC_RC" -eq 1 ] || bad="$bad [tldr last: rc $RC_RC]"
  command grep -F '[FAIL]' "$WORK/reconf.out" | command grep -qF 'cannot be combined with' || bad="$bad [tldr last: no refusal]"
  [ "$m" = "$(cat "$d/.claude/manifest.json")" ] || bad="$bad [the manifest changed]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}
echo
echo "=== R — reconfigure-project.sh --tldr-mode ==="
if [ -f "$AN_P/.claude/manifest.json" ] && [ -f "$AN_P/scripts/reconfigure-project.sh" ]; then
  check "R1 on → off → on from an adopted project: the key, the section and the wiring follow; off restores CLAUDE.md; the second on equals the first" case_R1 "$(_rproj)"
  check "R2 --tldr-mode maybe: refused (rc 1); manifest, CLAUDE.md and settings untouched" case_R2 "$(_rproj)"
  check "R3 'on' with scripts/hooks/tldr-check.sh missing: refused, naming the hook; nothing changed" case_R3 "$(_rproj)"
  check "R4 --help lists --tldr-mode <on|off>" case_R4 "$(_rproj)"
  if [ "$(id -u)" = "0" ]; then
    skip "R5" "running as root, which writes a read-only CLAUDE.md anyway, so the failed write cannot be staged"
  else
    check "R5 'on' with CLAUDE.md read-only: rc 1, the [FAIL] line printed, manifest, settings.json and CLAUDE.md byte-identical to before, no backup or temp file left" case_R5 "$(_rproj)"
  fi
  check "R6 'on' when already on: a hand edit between the markers is rewritten to the current wording and the run says so; a current section is said to be current" case_R6 "$(_rproj)"
  check "R7 --tldr-mode with --enforcement-level (either order): refused, naming the other option; the manifest unchanged" case_R7 "$(_rproj)"
else
  fail_ "R1-R7" "no adopted project to run reconfigure in (AN did not complete)"
fi

# ════════════════════════════════════════════════════════════════════════════
# U — an upgrade keeps the key (scripts/upgrade-project.sh's manifest refresh)
# ════════════════════════════════════════════════════════════════════════════
_uproj() {   # _uproj DIR TLDR — tests/test-upgrade-manifest-refresh.sh's fixture, plus tldr_mode
  local dir="$1" tl="$2"
  mkdir -p "$dir/.claude"
  printf '{"project":"test","framework_version":"1.0","current_phase":0,"track":"standard","deployment":"personal","poc_mode":null,"compliance_ready":false,"gates":{"phase_0_to_1":null,"phase_1_to_2":null,"phase_3_to_4":null}}\n' > "$dir/.claude/phase-state.json"
  printf '{"host":"github","mode":"personal","remote_url":"","deployment":"personal","poc_mode":null,"enforcement_level":"strict","tldr_mode":%s}\n' "$tl" > "$dir/.claude/manifest.json"
  printf '{"phase1_artifacts":{"data_classification":"internal","zdr_attested":true,"zdr_attestation_reason":""}}\n' > "$dir/.claude/process-state.json"
  ( cd "$dir" && git init -q && git config user.email t@t.l && git config user.name t && git add -A && git commit -q -m init ) >/dev/null 2>&1
}
case_U1() {   # personal → organizational rewrites the manifest's tier, and keeps tldr_mode (true and false)
  local tl d bad=""
  for tl in true false; do
    d="$(newtmp)/p"; _uproj "$d" "$tl"
    ( cd "$d" && bash "$1/scripts/upgrade-project.sh" --deployment organizational --non-interactive ) > "$WORK/u-$tl.out" 2>&1 \
      || bad="$bad [$tl: rc $?: $(tail -3 "$WORK/u-$tl.out" | tr '\n' '|')]"
    [ "$(jq -r '.deployment' "$d/.claude/manifest.json")" = "organizational" ] || bad="$bad [$tl: the refresh did not run]"
    [ "$(_mode "$d")" = "$tl" ] || bad="$bad [$tl: tldr_mode is now $(_mode "$d")]"
  done
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}
echo
echo "=== U — an upgrade keeps the choice ==="
check "U1 upgrade-project.sh --deployment organizational rewrites the manifest's tier and keeps tldr_mode, true and false" case_U1 "$REPO_ROOT"

# ════════════════════════════════════════════════════════════════════════════
# G — tldr_mode is one of this framework's manifest keys (# BL-311-SOLO-KEYS)
# ════════════════════════════════════════════════════════════════════════════
case_G1() {   # the predicate: a Guardrails manifest plus tldr_mode is NOT Guardrails-only; without it, it is
  local p with=0 without=0
  p="$(newtmp)/p"; mkdir -p "$p/.claude/framework/hooks"
  printf '%s\n' "$GR_MANIFEST" | jq -c '. + {tldr_mode: false}' > "$p/.claude/manifest.json"
  ( . "$1/scripts/lib/adopt/adopt-state.sh" >/dev/null 2>&1; _adopt_guardrails_only "$p" ) && with=1
  printf '%s\n' "$GR_MANIFEST" > "$p/.claude/manifest.json"
  ( . "$1/scripts/lib/adopt/adopt-state.sh" >/dev/null 2>&1; _adopt_guardrails_only "$p" ) && without=1
  CASE_DETAIL="guardrails-only with tldr_mode=$with (want 0), without=$without (want 1)"
  [ "$with" = "0" ] && [ "$without" = "1" ]
}
case_G2() {   # end to end: adopting that tree refuses as framework-managed, and writes nothing
  local p bad=""
  p="$(newtmp)/p"; _gr "$p" "$(printf '%s' "$GR_MANIFEST" | jq -c '. + {tldr_mode: true}')" || { CASE_DETAIL="fixture"; return 1; }
  cp "$p/.claude/manifest.json" "$p/../m.orig"
  _adopt "$1" "$p" g2 "${ANS}"
  [ "$RUN_RC" -eq 1 ] || bad="$bad [rc $RUN_RC]"
  command grep -qF '[REFUSED] this project already looks framework-managed: .claude/manifest.json is present' "$WORK/g2.out" || bad="$bad [not the managed refusal: $(command grep -m1 -E 'REFUSED|BLOCKED' "$WORK/g2.out")]"
  cmp -s "$p/../m.orig" "$p/.claude/manifest.json" || bad="$bad [the manifest changed]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}
echo
echo "=== G — tldr_mode marks a manifest as this framework's ==="
check "G1 _adopt_guardrails_only: a Guardrails manifest carrying tldr_mode is not Guardrails-only; the same manifest without it is" case_G1 "$REPO_ROOT"
check "G2 adopting a Guardrails tree whose manifest carries tldr_mode refuses as framework-managed, and changes nothing" case_G2 "$REPO_ROOT"

# ════════════════════════════════════════════════════════════════════════════
# P — an upgrade's three-way merge of CLAUDE.md treats the section as common ground
# ════════════════════════════════════════════════════════════════════════════
case_P1() {   # tldr on: both render legs carry the section, so a change to the template's LAST line merges clean
  local d rc
  d="$(newtmp)"; mkdir -p "$d/p/.claude"
  printf '{"project":"demo","track":"standard","deployment":"personal"}\n' > "$d/p/.claude/phase-state.json"
  printf '# CLAUDE.md — __PROJECT_NAME__\n\n### UAT Test Sessions\n- Archive each session under docs/test-results/.\n' > "$d/then.tmpl"
  printf '# CLAUDE.md — __PROJECT_NAME__\n\n### UAT Test Sessions\n- Archive each session under docs/test-results/, one file per session.\n' > "$d/now.tmpl"
  rc="$(
    . "$1/scripts/lib/plan-staging.sh" >/dev/null 2>&1 || { echo src; exit 0; }
    # The live file as init.sh leaves it: the render, then the section.
    printf '{"tldr_mode":false}\n' > "$d/p/.claude/manifest.json"
    _soif_plan_recover_and_render "$d/p" CLAUDE.md "$d/then.tmpl" "$d/p/CLAUDE.md"
    [ "$(command grep -c 'tldr-mode:begin' "$d/p/CLAUDE.md")" = "0" ] || { echo off-leg-has-section; exit 0; }
    soif_tldr_apply_claude_md "$d/p/CLAUDE.md" on || { echo apply; exit 0; }
    printf '{"tldr_mode":true}\n' > "$d/p/.claude/manifest.json"
    _soif_plan_recover_and_render "$d/p" CLAUDE.md "$d/then.tmpl" "$d/then.out"
    _soif_plan_recover_and_render "$d/p" CLAUDE.md "$d/now.tmpl" "$d/now.out"
    git merge-file -p "$d/p/CLAUDE.md" "$d/then.out" "$d/now.out" > "$d/cand" 2>/dev/null; echo "$?"
  )"
  CASE_DETAIL="merge-file rc=$rc markers=$(command grep -c '^<<<<<<<' "$d/cand" 2>/dev/null) section=$(command grep -cxF '<!-- tldr-mode:begin -->' "$d/cand" 2>/dev/null) new-line=$(command grep -c 'one file per session' "$d/cand" 2>/dev/null)"
  [ "$rc" = "0" ] && [ "$(command grep -cxF '<!-- tldr-mode:begin -->' "$d/cand")" = "1" ] \
    && command grep -q 'one file per session' "$d/cand"
}
echo
echo "=== P — the Currency System's three-way merge of CLAUDE.md ==="
check "P1 tldr on: both render legs carry the section, so the template's last line changing merges clean and keeps one section (off: no section in the leg)" case_P1 "$REPO_ROOT"

# ════════════════════════════════════════════════════════════════════════════
# M — mutants
# ════════════════════════════════════════════════════════════════════════════
echo
echo "=== M — every BL-312 marker is load-bearing ==="
mk_mirror() {
  mkdir -p "$2" && cp -Rp "$1/scripts" "$1/templates" "$1/init.sh" "$1/README.md" "$2/"
}
# mutate FILE MARKER REPLACEMENT — 0 iff exactly one line ends in MARKER, it now
# reads REPLACEMENT exactly, and the file still parses.
mutate() {
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
# mutant ID REL MARKER REPLACEMENT KILLER WHAT [ARG] — in a mirror of the tree.
mutant() {
  local id="$1" rel="$2" mark="$3" repl="$4" killer="$5" what="$6" m why
  m="$(newtmp)/mirror"
  mk_mirror "$REPO_ROOT" "$m" || { fail_ "$id" "could not build a mirror"; return; }
  why="$(mutate "$m/$rel" "$mark" "$repl")" || { fail_ "$id" "mutant did not land: $why"; return; }
  CASE_DETAIL=""
  if "$killer" "$m" "$(newtmp)/p"; then
    fail_ "$id" "$what — SURVIVED: ${killer#case_} still passes against the mutant ($CASE_DETAIL)"
  else
    pass "$id (MUTATION) — $what: killed by ${killer#case_}"
  fi
}
# rmutant ID MARKER REPLACEMENT KILLER WHAT — in an adopted project's own reconfigure.
rmutant() {
  local id="$1" mark="$2" repl="$3" killer="$4" what="$5" d why
  d="$(_rproj)" || { fail_ "$id" "no project"; return; }
  why="$(mutate "$d/scripts/reconfigure-project.sh" "$mark" "$repl")" || { fail_ "$id" "mutant did not land: $why"; return; }
  CASE_DETAIL=""
  if "$killer" "$d"; then
    fail_ "$id" "$what — SURVIVED: ${killer#case_} still passes against the mutant ($CASE_DETAIL)"
  else
    pass "$id (MUTATION) — $what: killed by ${killer#case_}"
  fi
}
H=scripts/hooks/tldr-check.sh
L=scripts/lib/tldr-mode.sh
AS=scripts/lib/adopt/adopt-state.sh
mutant MH1 "$H" '# BL-312-TLDR-ONCE' ':' case_H5 "the stop_hook_active exit is gone"
mutant MH2 "$H" '# BL-312-TLDR-OFF' ':' case_H6 "the off/absent/unreadable exit is gone"
mutant MH3 "$H" '# BL-312-TLDR-FENCE' '  l ~ /^[[:space:]]*```/ { fence = !fence; next }' case_H3 "only \`\`\` fences are skipped"
mutant MH8 "$H" '# BL-312-TLDR-FENCE' '  l ~ /^(```|~~~)/ { fence = !fence; next }' case_H3 "a fence indented under a list item is not a fence (review round 1's X2c)"
mutant MH4 "$H" '# BL-312-TLDR-TOKEN' '    tlre = "(^|[^a-z0-9_/.-])tl;dr([^a-z0-9_.-]|$)"' case_H2 "the token no longer accepts TLDR without the semicolon"
mutant MH5 "$H" '# BL-312-TLDR-BLOCK' ':' case_H1 "the block is never printed"
mutant MH6 "$H" '# BL-312-TLDR-NOJQ' ':' case_H7 "no jq is no longer said"
mutant MH7 "$H" '# BL-312-TLDR-ROOT' ':' case_H9 "the project root is not derived when CLAUDE_PROJECT_DIR is unset"
mutant ML1 scripts/lib/claude-settings.sh '# BL-312-TLDR-ROSTER' ':' case_W1 "the roster does not register the hook"
mutant MS1 init.sh '# BL-312-SHIP-HOOK' ':' case_W3 "init.sh does not ship the hook"
mutant MS2 init.sh '# BL-312-SHIP-LIB' ':' case_W3 "init.sh does not ship the lib"
mutant MS3 init.sh '# BL-312-INIT-DEFAULT' 'TLDR_MODE=true' case_S3 "the default is on (review round 1's X4; tests/test-bl312-tldr-mode-init.sh MI4 runs it)"
mutant MP1 scripts/lib/plan-staging.sh '# BL-312-PLAN-TLDR-LEGS' '        :' case_P1 "the render legs carry no section"
mutant ML2 "$L" '# BL-312-TLDR-HELD-BLANK' '      $0 == b { skip = 1; next }' case_C1 "'off' leaves the blank line 'on' added"
mutant ML3 "$L" '# BL-312-TLDR-DAMAGED' ':' case_C2 "damaged markers are no longer refused"
mutant ML4 "$L" '# BL-312-TLDR-YES' '  case "${1:-}" in [YyNn]*) return 0 ;; esac' case_C3 "the reader takes 'n' as yes"
mutant MA1 "$AS" '# BL-312-ADOPT-TLDR-RESOLVE-ORDER' '    ans="$(adopt_resolve_choice "$raw" "$ADOPT_TLDR_YES" "$ADOPT_TLDR_NO")"' case_A1 "a stray 1 resolves to yes"
mutant MA2 "$AS" '# BL-312-ADOPT-TLDR-OFFER-ORDER' '  adopt_offer_choice "$SOIF_TLDR_QUESTION (No answer means no.)" "$ADOPT_TLDR_YES" "$ADOPT_TLDR_NO"' case_AY "the question shows 'yes' as option 1"
mutant MA3 "$AS" '# BL-312-ADOPT-TLDR-EOF' '  if false; then' case_AE "end of input refuses instead of meaning no"
mutant MA4 "$AS" '# BL-312-ADOPT-TLDR-YES' ':' case_AY "'yes' does not turn it on"
mutant MA5 "$AS" '# BL-312-ADOPT-TLDR-CALL' ':' case_AY "the question is never asked"
mutant MA6 "$AS" '# BL-312-ADOPT-TLDR-MANIFEST' '  :' case_AN "the manifest gets no tldr_mode (merge arm, a Guardrails project)"
mutant MA7 "$AS" '# BL-312-ADOPT-TLDR-MANIFEST' '  :' case_AY "the manifest gets no tldr_mode (create arm, a plain project)"
mutant MA8 scripts/lib/adopt/adopt-docs.sh '# BL-312-ADOPT-TLDR-DOCS' ':' case_AY "the CLAUDE.md section is not written"
mutant MA9 "$AS" '# BL-311-SOLO-KEYS' "ADOPT_SOLO_MANIFEST_KEYS='[\"host\",\"mode\",\"remote_url\",\"deployment\",\"poc_mode\",\"enforcement_level\",\"soloFrameworkCommit\",\"currency\",\"adoption\",\"mcp\"]'" case_G1 "tldr_mode is off the Solo key list"
if [ -f "$AN_P/scripts/reconfigure-project.sh" ]; then
  rmutant MR1 '# BL-312-RECONF-MANIFEST' ':' case_R1 "reconfigure does not write the key"
  rmutant MR2 '# BL-312-RECONF-WIRE' ':' case_R1 "reconfigure does not wire the hook"
  rmutant MR3 '# BL-312-RECONF-CLAUDE-MD' ':' case_R1 "reconfigure does not edit CLAUDE.md"
  rmutant MR4 '# BL-312-RECONF-HOOK-REQUIRED' '  if false; then' case_R3 "reconfigure turns it on with no hook script"
  rmutant MR5 '# BL-312-RECONF-VALUE' '    *)   _tl=true ;;' case_R2 "a value that is not on/off is accepted"
  if [ "$(id -u)" = "0" ]; then
    skip "MR6-MR7" "running as root (R5 cannot stage a failed write)"
  else
    rmutant MR6 '# BL-312-RECONF-ROLLBACK' '    :' case_R5 "the rollback does not put the manifest back (review round 1's X1)"
    rmutant MR7 '# BL-312-RECONF-PUT-BACK' '  _tl_put_back() { cp -p "$1" "$2"; }' case_R5 "the rollback copies over a file this run never changed"
  fi
  rmutant MR8 '# BL-312-RECONF-REWRITTEN' '      tl_md_note="the TL;DR Mode section is already there, as current"' case_R6 "a rewritten section is reported as current"
  rmutant MR9 '# BL-312-RECONF-ALONE' '  if false; then' case_R7 "--tldr-mode beside another change is not refused"
else
  fail_ "MR1-MR9" "no adopted project (AN did not complete)"
fi

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
