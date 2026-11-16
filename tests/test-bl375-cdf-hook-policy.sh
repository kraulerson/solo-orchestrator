#!/usr/bin/env bash
# tests/test-bl375-cdf-hook-policy.sh — `## BL-375:` (issue #535) the Guardrails
# hook registration carries each generated entry whole, keeps the generator's
# stderr, refreshes the failure policy of the entries already registered, and
# the refresh script and the session start say so.
#
# THE DEFECT. Development Guardrails 4.5.0 (CDF PR #50) makes its blocking
# hooks fail closed: generate_settings_json writes "timeout" (30; 600 for
# verification-gate) and "onFailure":"block" on each blocking PreToolUse entry.
# soif_cdf_register_hooks (`## BL-320:` c2) lost all of it: it ran the
# generator with 2>/dev/null, so the WARNING that the policy was not written
# and the ERROR of a refusal went nowhere, and a refusal surfaced as the
# generic "could not generate"; it extracted {event, matcher, command} and
# rebuilt {type: "command", command}, so a newly registered entry never
# carried the policy; and an entry already present (matched by command name)
# was never rewritten, so an upgraded project kept its 4.4.x entries. Measured
# in the 4.5.0 review: entries carrying timeout or onFailure after Solo's
# rebuild: 0.
#
# CASES
#   P1  a 4.5.0-shaped generator: each registered entry equals the generated
#       object (jq ==), appended as its own group; everything else unchanged
#   P2  a key the generator does not emit today survives
#   P3  the generator's WARNING is shown, prefixed; registration proceeds
#   P4  the generator's ERROR and non-zero return: refused on the [FAIL] line
#       with its message, settings.json byte-identical, never "none missing"
#   P5  upgrade: 4.4.x-shaped CDF entries gain timeout/onFailure in place,
#       other keys and positions intact, Solo's and the user's entries (and
#       the user's own timeout) untouched; each refresh printed
#   P6  entries already carrying the policy: file byte-identical, no refresh
#       printed, "none missing"
#   P7  check mode lists additions (the name) and refreshes (the name and the
#       policy it would get) and writes nothing
#   P8  a refresh that did not land is a [FAIL]: the receipt re-reads the file
#   P9  refresh-guardrails.sh prints each refresh (relayed under its [OK] line,
#       indented as the additions are), and (P9b) the generator's WARNING
#   P10 check-versions.sh: the row names the entries without the policy and
#       offers the refresh; a missing entry and a refresh each get a clause
#   P11 a generator without onFailure (an older Claude Code) KEEPS a registered
#       onFailure=block: the refresh adds or strengthens a policy, never
#       loosens one (review round 3); P11b the same over a stale timeout —
#       the timeout is refreshed, the line shows before->after and the kept
#       field; P12 the reviewer's scenario (WARNING "Claude Code not found on
#       PATH", no onFailure emitted): nothing loosened
#   P13 a generator that refuses at session start is a row, never silence
#   P14 below the floor with work to do: one row with both halves, the
#       refresh offered
#   H   the two floors (Karl's ruling B): SOIF_GUARDRAILS_MIN 4.6.0 is what the
#       framework requires and SOIF_GUARDRAILS_PICK_MIN 4.4.0 is where the
#       answer by option id arrived — a 4.5.0 project is below the floor and
#       still routed pick (H1), 4.6.0 is at it (H2), 4.3.7 is legacy (H3), a
#       4.5.0 clone over an old writer is still a refused mixed install (H4)
#   M   mutants: each rewrites ONE marked line in a mirror of the tree, checks
#       the edit landed and still parses, and needs a named case to go RED
#
# Hermetic: temp dirs only. The clone is a fake whose scripts/_shared.sh
# generator reads knob files beside it (the policy shape, a stderr text, a
# return code, extra keys), never the real clone, so the host's Guardrails
# version does not matter. bash 3.2 safe; needs jq and git.
set -uo pipefail
unset GITHUB_BASE_REF CDF_HOME SOIF_NONINTERACTIVE CI CLAUDECODE 2>/dev/null || true

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

for t in jq git; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bl375.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
newtmp() { mktemp -d "$WORK/tXXXXXX"; }
CASE_DETAIL=""
# count_f TEXT NEEDLE — fixed-string line count; drained, never grep -q (#435).
count_f() { printf '%s\n' "$1" | command grep -cF -- "$2"; }
has_f()   { [ "$(count_f "$1" "$2")" -ge 1 ]; }
# line_f TEXT LINE — LINE is a whole line of TEXT.
line_f()  { [ "$(printf '%s\n' "$1" | command grep -cxF -- "$2")" -ge 1 ]; }
last3()   { printf '%s\n' "$1" | tail -3 | tr '\n' '|'; }

CMDP='"$CLAUDE_PROJECT_DIR"/.claude/framework/hooks/'
HOOKS="session-start config-guard enforce-evaluate verification-gate stop-checklist record-approval"

# ── the fake clone ───────────────────────────────────────────────────────────
# Its generator is CDF 4.5.0's in shape (scripts/_shared.sh generate_settings_json,
# PR #50): blocking hooks get a timeout and, with gen.policy "full",
# "onFailure":"block"; record-approval rides with enforce-evaluate without a
# policy. Knob files beside it, read at each call:
#   gen.policy   full (default) | timeout-only | none (the 4.4.x shape)
#   gen.stderr   printed to stderr, verbatim, before anything else
#   gen.rc       returned after the stderr text, before any output, when not 0
#   gen.extra    a JSON object merged into every blocking entry
mk_clone() {   # DIR VERSION
  mkdir -p "$1/hooks" "$1/scripts" || return 1
  printf '%s\n' "$2" > "$1/FRAMEWORK_VERSION"
  cat > "$1/scripts/_shared.sh" <<'SH'
generate_settings_json() {
  local d="" p='"$CLAUDE_PROJECT_DIR"/.claude/framework/hooks/' e="" h="" ev="" m="" t="" pol="" rc="" extra="" onfail=""
  d="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  pol="$(cat "$d/gen.policy" 2>/dev/null || echo full)"
  rc="$(cat "$d/gen.rc" 2>/dev/null || echo 0)"
  extra="$(cat "$d/gen.extra" 2>/dev/null || echo '{}')"
  [ ! -f "$d/gen.stderr" ] || cat "$d/gen.stderr" >&2
  [ "$rc" = 0 ] || return "$rc"
  onfail='{}'; [ "$pol" != full ] || onfail='{"onFailure":"block"}'
  for h in "$@"; do
    t=null
    case "$h" in
      session-start)     ev=SessionStart m="" ;;
      config-guard)      ev=PreToolUse   m="Bash|Write|Edit|NotebookEdit" t=30 ;;
      enforce-evaluate)  ev=PreToolUse   m=Bash t=30 ;;
      verification-gate) ev=PreToolUse   m=Bash t=600 ;;
      stop-checklist)    ev=Stop         m="" ;;
      *) continue ;;
    esac
    [ "$pol" != none ] || t=null
    e="$e$(jq -nc --arg e "$ev" --arg m "$m" --arg c "$p$h.sh" --argjson t "$t" '{event:$e,matcher:$m,command:$c,timeout:$t}')
"
    if [ "$h" = enforce-evaluate ]; then
      e="$e$(jq -nc --arg c "${p}record-approval.sh" '{event:"UserPromptSubmit",matcher:"",command:$c,timeout:null}')
"
    fi
  done
  printf '%s' "$e" | jq -s --argjson onfail "$onfail" --argjson extra "$extra" '
    group_by(.event + "\u0000" + .matcher)
    | map({event: .[0].event, matcher: .[0].matcher,
           hooks: map({type: "command", command: .command} + (if .timeout then {timeout: .timeout} + $onfail + $extra else {} end))})
    | group_by(.event) | map({key: .[0].event, value: map(if .matcher != "" then {matcher, hooks} else {hooks} end)})
    | from_entries | {hooks: ., permissions: {deny: []}}'
}
SH
  local h; for h in $HOOKS; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$1/hooks/$h.sh"; chmod +x "$1/hooks/$h.sh"
  done
  ( cd "$1" && git init -q && git config user.email t@t.local && git config user.name T && git add -A && git commit -q -m clone ) >/dev/null 2>&1
}
knob() { printf '%s' "$3" > "$1/gen.$2"; }   # CLONE KEY VALUE
# generated CLONE — what the fake generator emits for the project's activeHooks.
generated() { ( . "$1/scripts/_shared.sh" >/dev/null 2>&1; generate_settings_json session-start config-guard enforce-evaluate verification-gate stop-checklist 2>/dev/null ); }

# ── the project ──────────────────────────────────────────────────────────────
# proj DIR SHAPE [norecord] — a git repo with .claude/manifest.json (activeHooks:
# the five above), the hook files, and a settings.json that interleaves Solo's
# and the user's entries with the Guardrails':
#   fresh    no Guardrails entry at all (a project registering for the first time)
#   old      the 4.4.x shape: {type, command} only; enforce-evaluate carries a
#            key of the user's own ("note"); verification-gate is spelled
#            another way (bash .claude/framework/hooks/…); the user's own
#            pre-commit-gate entry has its own timeout (5), which is theirs
#   current  the old shape plus the 4.5.0 policy on the three blocking entries
#   stale    current, but enforce-evaluate carries timeout 5 (a value the
#            Guardrails now set to 30) beside its onFailure block
# "norecord" leaves record-approval unregistered (one addition beside refreshes).
proj() {
  local d="$1" shape="$2" rec="${3:-}" h
  mkdir -p "$d/.claude/framework/hooks" || return 1
  ( cd "$d" && git init -q && git config user.email t@t.local && git config user.name T \
      && printf 'seed\n' > seed.txt && git add seed.txt && git commit -q -m seed ) >/dev/null 2>&1 || return 1
  for h in $HOOKS; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$d/.claude/framework/hooks/$h.sh"; chmod +x "$d/.claude/framework/hooks/$h.sh"
  done
  jq -n '{frameworkVersion: "4.6.0", enforcement_level: "strict",
          activeHooks: ["session-start", "config-guard", "enforce-evaluate", "verification-gate", "stop-checklist"]}' > "$d/.claude/manifest.json"
  jq -n --arg p "$CMDP" --arg shape "$shape" --arg rec "$rec" '
    ({timeout: 30, onFailure: "block"}) as $pol30 | ({timeout: 600, onFailure: "block"}) as $pol600
    | (if $shape == "current" or $shape == "stale" then $pol30 else {} end) as $p30 | (if $shape == "current" or $shape == "stale" then $pol600 else {} end) as $p600
    | (if $shape == "stale" then {timeout: 5, onFailure: "block"} else $p30 end) as $pee
    | {
      permissions: {allow: ["Bash(git status)"], deny: ["Edit(/.claude/settings.json)"]},
      hooks: ({
        SessionStart: [{hooks: [{type: "command", command: "bash \"$CLAUDE_PROJECT_DIR\"/scripts/session-version-check.sh"}]}],
        PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: "bash \"$CLAUDE_PROJECT_DIR\"/scripts/pre-commit-gate.sh", timeout: 5}]}],
        UserPromptSubmit: [{hooks: [{type: "command", command: "echo mine"}]}]
      } + (if $shape == "fresh" then {} else {
        SessionStart: [{hooks: [{type: "command", command: ($p + "session-start.sh")},
                                {type: "command", command: "bash \"$CLAUDE_PROJECT_DIR\"/scripts/session-version-check.sh"}]}],
        PreToolUse: [{matcher: "Bash", hooks: [({type: "command", command: ($p + "enforce-evaluate.sh"), note: "keep"} + $pee)]},
                     {matcher: "Bash|Write|Edit|NotebookEdit", hooks: [({type: "command", command: ($p + "config-guard.sh")} + $p30)]},
                     {matcher: "Bash", hooks: [{type: "command", command: "bash \"$CLAUDE_PROJECT_DIR\"/scripts/pre-commit-gate.sh", timeout: 5}]},
                     {matcher: "Bash", hooks: [({type: "command", command: "bash .claude/framework/hooks/verification-gate.sh"} + $p600)]}],
        Stop: [{hooks: [{type: "command", command: ($p + "stop-checklist.sh")}]}],
        UserPromptSubmit: ([{hooks: [{type: "command", command: "echo mine"}]}]
                           + (if $rec == "norecord" then [] else [{hooks: [{type: "command", command: ($p + "record-approval.sh")}]}] end))
      } end)),
      model: "keep-me"
    }' > "$d/.claude/settings.json"
}
REG_OUT=""; REG_RC=0
reg() {   # ROOT DIR CLONE [check]
  REG_RC=0
  REG_OUT="$( ( . "$1/scripts/lib/guardrails.sh" && soif_cdf_register_hooks "$2" "$3" ${4:+"$4"} ) 2>&1 )" || REG_RC=$?
}
# same_but FILE BEFORE JQ-EDIT — FILE's JSON equals BEFORE with JQ-EDIT applied
# (jq -c on both: key order counts, so "in place" and "appended" are checked).
same_but() {
  local want
  want="$(printf '%s' "$2" | jq -c "$3")" || { CASE_DETAIL="could not build the expectation"; return 1; }
  [ "$(jq -c . "$1")" = "$want" ] || { CASE_DETAIL="the file is not the expected edit of the original: $(jq -c .hooks "$1" | cut -c1-600)"; return 1; }
}
POL='.hooks.PreToolUse[0].hooks[0] += {timeout: 30, onFailure: "block"} | .hooks.PreToolUse[1].hooks[0] += {timeout: 30, onFailure: "block"} | .hooks.PreToolUse[3].hooks[0] += {timeout: 600, onFailure: "block"}'

# ── P: the registration ──────────────────────────────────────────────────────
# whole_entries DIR CLONE BEFORE — every generated entry is in the file, equal as
# a whole object, under its event and matcher, appended after the original
# groups, which are unchanged; nothing outside .hooks changed.
whole_entries() {
  local d="$1" c="$2" before="$3" gen line ev m g n
  gen="$(generated "$c")" || { CASE_DETAIL="the fake generator failed"; return 1; }
  n=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    ev="$(jq -r .event <<< "$line")"; m="$(jq -r .matcher <<< "$line")"; g="$(jq -c .entry <<< "$line")"
    jq -e --arg e "$ev" --arg m "$m" --argjson g "$g" 'any(.hooks[$e][]?; (.matcher // "") == $m and any(.hooks[]?; . == $g))' "$d/.claude/settings.json" >/dev/null 2>&1 \
      || { CASE_DETAIL="not registered whole under $ev ($m): $g; file has $(jq -c --arg e "$ev" '.hooks[$e]' "$d/.claude/settings.json" | cut -c1-400)"; return 1; }
    n=$((n + 1))
  done < <(jq -c '.hooks | to_entries[] | .key as $e | .value[] | (.matcher // "") as $m | .hooks[] | {event: $e, matcher: $m, entry: .}' <<< "$gen")
  [ "$n" -ge 6 ] || { CASE_DETAIL="the fake generator emitted $n entries, expected 6"; return 1; }
  # the original groups, in order, first; then only the generated groups
  jq -e --argjson b "$before" --argjson g "$gen" '. as $a
      | ($b.hooks | to_entries | all(.[]; .key as $e | .value as $v | ($g.hooks[$e] // []) as $add | ($a.hooks[$e] // []) as $av | ($v | length) as $o
           | if ($e | in($g.hooks)) then ($av[:$o] == $v and $av[$o:] == $add) else ($av == $v) end))
      and ($g.hooks | keys | all(.[]; . as $e | ($e | in($b.hooks)) or (($a.hooks[$e] // []) == $g.hooks[$e])))
      and (($a.hooks | keys) == ((($b.hooks | keys) + ($g.hooks | keys)) | unique))
      and (($a | del(.hooks)) == ($b | del(.hooks)))' "$d/.claude/settings.json" >/dev/null 2>&1 \
    || { CASE_DETAIL="the original groups moved, or something outside .hooks changed: $(jq -c . "$d/.claude/settings.json" | cut -c1-600)"; return 1; }
}
case_P1() {   # (a) a 4.5.0-shaped generator: each entry registered whole, equal to the generated object
  local t d c before
  t="$(newtmp)"; d="$t/p"; c="$t/clone"
  proj "$d" fresh && mk_clone "$c" 4.6.0 || { CASE_DETAIL="fixture"; return 1; }
  before="$(jq -c . "$d/.claude/settings.json")"
  reg "$1" "$d" "$c"
  [ "$REG_RC" -eq 0 ] || { CASE_DETAIL="rc=$REG_RC: $(last3 "$REG_OUT")"; return 1; }
  whole_entries "$d" "$c" "$before" || return 1
  jq -e --arg c "${CMDP}enforce-evaluate.sh" 'any(.hooks.PreToolUse[]?.hooks[]?; .command == $c and .timeout == 30 and .onFailure == "block")' "$d/.claude/settings.json" >/dev/null 2>&1 \
    || { CASE_DETAIL="enforce-evaluate carries no policy: $(jq -c '.hooks.PreToolUse' "$d/.claude/settings.json")"; return 1; }
  jq -e --arg c "${CMDP}verification-gate.sh" 'any(.hooks.PreToolUse[]?.hooks[]?; .command == $c and .timeout == 600 and .onFailure == "block")' "$d/.claude/settings.json" >/dev/null 2>&1 \
    || { CASE_DETAIL="verification-gate carries no 600s policy: $(jq -c '.hooks.PreToolUse' "$d/.claude/settings.json")"; return 1; }
  [ "$(count_f "$REG_OUT" "  + ")" = 6 ] || { CASE_DETAIL="expected 6 additions named: $REG_OUT"; return 1; }
  has_f "$REG_OUT" "  ~ " && { CASE_DETAIL="a refresh named on a fresh project: $REG_OUT"; return 1; }
  has_f "$REG_OUT" "+ PreToolUse (Bash): ${CMDP}enforce-evaluate.sh" || { CASE_DETAIL="the addition is not named with its matcher: $REG_OUT"; return 1; }
}
case_P2() {   # (b) a key the generator does not emit today survives
  local t d c before
  t="$(newtmp)"; d="$t/p"; c="$t/clone"
  proj "$d" fresh && mk_clone "$c" 4.6.0 || { CASE_DETAIL="fixture"; return 1; }
  knob "$c" extra '{"policy": {"version": 2, "retry": false}, "future": "kept"}'
  before="$(jq -c . "$d/.claude/settings.json")"
  reg "$1" "$d" "$c"
  [ "$REG_RC" -eq 0 ] || { CASE_DETAIL="rc=$REG_RC: $(last3 "$REG_OUT")"; return 1; }
  whole_entries "$d" "$c" "$before" || return 1
  jq -e --arg c "${CMDP}config-guard.sh" 'any(.hooks.PreToolUse[]?.hooks[]?; .command == $c and .future == "kept" and .policy == {version: 2, retry: false})' "$d/.claude/settings.json" >/dev/null 2>&1 \
    || { CASE_DETAIL="the future keys were dropped: $(jq -c '.hooks.PreToolUse' "$d/.claude/settings.json")"; return 1; }
}
WARN_LINE='WARNING: Claude Code 2.1.200; fail-closed hooks need Claude Code 2.1.295 or later. Until then the guard hooks will not fail closed when they time out, crash or cannot start: the action they guard goes ahead. Fix: run `claude update`, then re-run sync.sh in this project.'
case_P3() {   # (c) the generator's WARNING is shown, prefixed; registration proceeds without onFailure
  local t d c before
  t="$(newtmp)"; d="$t/p"; c="$t/clone"
  proj "$d" fresh && mk_clone "$c" 4.6.0 || { CASE_DETAIL="fixture"; return 1; }
  knob "$c" policy timeout-only; knob "$c" stderr "$WARN_LINE"$'\n'
  before="$(jq -c . "$d/.claude/settings.json")"
  reg "$1" "$d" "$c"
  [ "$REG_RC" -eq 0 ] || { CASE_DETAIL="rc=$REG_RC: $(last3 "$REG_OUT")"; return 1; }
  line_f "$REG_OUT" "Guardrails generator: $WARN_LINE" || { CASE_DETAIL="the WARNING is not shown with its origin: $(last3 "$REG_OUT")"; return 1; }
  whole_entries "$d" "$c" "$before" || return 1
  jq -e --arg c "${CMDP}enforce-evaluate.sh" 'any(.hooks.PreToolUse[]?.hooks[]?; .command == $c and .timeout == 30 and (has("onFailure") | not))' "$d/.claude/settings.json" >/dev/null 2>&1 \
    || { CASE_DETAIL="the timeout-only entry is not as generated: $(jq -c '.hooks.PreToolUse' "$d/.claude/settings.json")"; return 1; }
}
ERR_LINE='ERROR: claude is not on this shell'"'"'s PATH or prints no version (an alias or an app-bundled Claude Code is not visible to scripts), yet this runs inside a Claude Code session. Nothing was written. Run init.sh or sync.sh from a terminal outside Claude Code, with claude on PATH.'
case_P4() {   # (d) the generator's ERROR and rc 1: refused with its message on the [FAIL] line, nothing written
  local t d c s
  t="$(newtmp)"; d="$t/p"; c="$t/clone"
  proj "$d" fresh && mk_clone "$c" 4.6.0 || { CASE_DETAIL="fixture"; return 1; }
  knob "$c" rc 1; knob "$c" stderr "$ERR_LINE"$'\n'
  s="$(cksum < "$d/.claude/settings.json")"
  reg "$1" "$d" "$c"
  [ "$REG_RC" -ne 0 ] || { CASE_DETAIL="rc=0: $REG_OUT"; return 1; }
  [ "$(cksum < "$d/.claude/settings.json")" = "$s" ] || { CASE_DETAIL="settings.json changed"; return 1; }
  has_f "$REG_OUT" "none missing" && { CASE_DETAIL="a refusal reads as nothing missing: $REG_OUT"; return 1; }
  [ "$(printf '%s\n' "$REG_OUT" | command grep -F '[FAIL]' | command grep -cF -- "$ERR_LINE")" -ge 1 ] \
    || { CASE_DETAIL="the [FAIL] line does not carry the generator's message: $(printf '%s\n' "$REG_OUT" | command grep -F '[FAIL]' | cut -c1-300)"; return 1; }
  line_f "$REG_OUT" "Guardrails generator: $ERR_LINE" || { CASE_DETAIL="the ERROR is not shown with its origin: $(last3 "$REG_OUT")"; return 1; }
}
case_P5() {   # (e) upgrade: 4.4.x-shaped entries gain the policy in place; nothing else moves
  local t d c before
  t="$(newtmp)"; d="$t/p"; c="$t/clone"
  proj "$d" old && mk_clone "$c" 4.6.0 || { CASE_DETAIL="fixture"; return 1; }
  before="$(jq -c . "$d/.claude/settings.json")"
  reg "$1" "$d" "$c"
  [ "$REG_RC" -eq 0 ] || { CASE_DETAIL="rc=$REG_RC: $(last3 "$REG_OUT")"; return 1; }
  same_but "$d/.claude/settings.json" "$before" "$POL" || return 1
  [ "$(count_f "$REG_OUT" "  ~ ")" = 3 ] || { CASE_DETAIL="expected 3 refreshes named: $REG_OUT"; return 1; }
  has_f "$REG_OUT" "  + " && { CASE_DETAIL="an addition named where every entry is registered: $REG_OUT"; return 1; }
  line_f "$REG_OUT" "  ~ PreToolUse (Bash): ${CMDP}enforce-evaluate.sh timeout=none->30 onFailure=none->block" || { CASE_DETAIL="enforce-evaluate's refresh is not named before->after: $REG_OUT"; return 1; }
  line_f "$REG_OUT" "  ~ PreToolUse (Bash|Write|Edit|NotebookEdit): ${CMDP}config-guard.sh timeout=none->30 onFailure=none->block" || { CASE_DETAIL="config-guard's refresh is not named: $REG_OUT"; return 1; }
  line_f "$REG_OUT" "  ~ PreToolUse (Bash): bash .claude/framework/hooks/verification-gate.sh timeout=none->600 onFailure=none->block" || { CASE_DETAIL="the differently spelled entry is not named as the file spells it: $REG_OUT"; return 1; }
  has_f "$REG_OUT" "registrations refreshed in .claude/settings.json" || { CASE_DETAIL="no heading says what happened: $(printf '%s\n' "$REG_OUT" | head -1)"; return 1; }
}
case_P6() {   # (f) entries already carrying the policy: byte-identical, nothing refreshed
  local t d c s
  t="$(newtmp)"; d="$t/p"; c="$t/clone"
  proj "$d" current && mk_clone "$c" 4.6.0 || { CASE_DETAIL="fixture"; return 1; }
  s="$(cksum < "$d/.claude/settings.json")"
  reg "$1" "$d" "$c"
  [ "$REG_RC" -eq 0 ] || { CASE_DETAIL="rc=$REG_RC: $(last3 "$REG_OUT")"; return 1; }
  [ "$(cksum < "$d/.claude/settings.json")" = "$s" ] || { CASE_DETAIL="the file was rewritten: $REG_OUT"; return 1; }
  has_f "$REG_OUT" "  ~ " && { CASE_DETAIL="a refresh named where the policy is already right: $REG_OUT"; return 1; }
  has_f "$REG_OUT" "  + " && { CASE_DETAIL="an addition named: $REG_OUT"; return 1; }
  has_f "$REG_OUT" "none missing" || { CASE_DETAIL="does not say none is missing: $REG_OUT"; return 1; }
}
case_P7() {   # (g) check mode: additions as names, refreshes as name + policy; nothing written
  local t d c s
  t="$(newtmp)"; d="$t/p"; c="$t/clone"
  proj "$d" old norecord && mk_clone "$c" 4.6.0 || { CASE_DETAIL="fixture"; return 1; }
  s="$(cksum < "$d/.claude/settings.json")"
  reg "$1" "$d" "$c" check
  [ "$REG_RC" -eq 0 ] || { CASE_DETAIL="rc=$REG_RC: $(last3 "$REG_OUT")"; return 1; }
  [ "$(cksum < "$d/.claude/settings.json")" = "$s" ] || { CASE_DETAIL="check mode wrote the file"; return 1; }
  line_f "$REG_OUT" "record-approval" || { CASE_DETAIL="the addition is not listed by name: $REG_OUT"; return 1; }
  line_f "$REG_OUT" "enforce-evaluate timeout=30 onFailure=block" && line_f "$REG_OUT" "config-guard timeout=30 onFailure=block" \
    && line_f "$REG_OUT" "verification-gate timeout=600 onFailure=block" || { CASE_DETAIL="the refreshes are not listed with their policy: $REG_OUT"; return 1; }
  [ "$(printf '%s\n' "$REG_OUT" | command grep -c .)" = 4 ] || { CASE_DETAIL="expected exactly 4 lines: $REG_OUT"; return 1; }
}
case_P8() {   # the receipt: a refresh that never landed is a [FAIL], never "refreshed"
  local t d c stub real s
  t="$(newtmp)"; d="$t/p"; c="$t/clone"
  proj "$d" old && mk_clone "$c" 4.6.0 || { CASE_DETAIL="fixture"; return 1; }
  stub="$(newtmp)"; real="$(command -v mv)"
  printf '#!/bin/sh\ncase "$*" in *settings.json*) exit 0 ;; esac\nexec "%s" "$@"\n' "$real" > "$stub/mv"; chmod +x "$stub/mv"
  s="$(cksum < "$d/.claude/settings.json")"
  REG_RC=0
  REG_OUT="$( ( PATH="$stub:$PATH"; . "$1/scripts/lib/guardrails.sh" && soif_cdf_register_hooks "$d" "$c" ) 2>&1 )" || REG_RC=$?
  [ "$(cksum < "$d/.claude/settings.json")" = "$s" ] || { CASE_DETAIL="the stub let the write through"; return 1; }
  [ "$REG_RC" -ne 0 ] && has_f "$REG_OUT" "[FAIL]" || { CASE_DETAIL="a refresh that never landed reported as: rc=$REG_RC $REG_OUT"; return 1; }
  has_f "$REG_OUT" "did not land" && has_f "$REG_OUT" "enforce-evaluate.sh" || { CASE_DETAIL="the receipt does not name what did not land: $REG_OUT"; return 1; }
  has_f "$REG_OUT" "refreshed in" && { CASE_DETAIL="it still claims the refresh: $REG_OUT"; return 1; }
  return 0
}
# rg DIR CLONE — refresh-guardrails.sh in DIR, HOME set so CLONE is found. Sets RG_OUT, RG_RC.
RG_OUT=""; RG_RC=0
rg_proj() {   # DIR CLONE — an old-shape project at 4.5.0 and a 4.6.0 clone whose cdf-refresh.sh copies the hooks
  proj "$1" old && mk_clone "$2" 4.6.0 || return 1
  jq '.frameworkVersion = "4.5.0"' "$1/.claude/manifest.json" > "$1/m" && mv "$1/m" "$1/.claude/manifest.json"
  cat > "$2/scripts/cdf-refresh.sh" <<'UP'
refresh_cdf_assets() {
  local f; for f in "$2"/hooks/*.sh; do cp "$f" "$1/.claude/framework/hooks/"; done
  chmod +x "$1"/.claude/framework/hooks/*.sh
  jq --arg v "$(tr -d '[:space:]' < "$2/FRAMEWORK_VERSION")" '.frameworkVersion = $v' "$1/.claude/manifest.json" > "$1/.claude/m.tmp" \
    && mv "$1/.claude/m.tmp" "$1/.claude/manifest.json"
}
UP
  ( cd "$2" && git add -A && git commit -q -m up ) >/dev/null 2>&1
}
rg() {
  RG_RC=0
  RG_OUT="$( cd "$2" && HOME="$3" bash "$1/scripts/refresh-guardrails.sh" </dev/null 2>&1 )" || RG_RC=$?
}
case_P9() {   # refresh-guardrails.sh prints each refresh it made
  local t d c before
  t="$(newtmp)"; d="$t/p"; c="$t/home/.claude-dev-framework"
  rg_proj "$d" "$c" || { CASE_DETAIL="fixture"; return 1; }
  before="$(jq -c . "$d/.claude/settings.json")"
  rg "$1" "$d" "$t/home"
  [ "$RG_RC" -eq 0 ] || { CASE_DETAIL="rc=$RG_RC: $(last3 "$RG_OUT")"; return 1; }
  has_f "$RG_OUT" "[OK] Development Guardrails in this project updated: 4.5.0 -> 4.6.0" || { CASE_DETAIL="no [OK]: $(last3 "$RG_OUT")"; return 1; }
  same_but "$d/.claude/settings.json" "$before" "$POL" || return 1
  line_f "$RG_OUT" "       ~ PreToolUse (Bash): ${CMDP}enforce-evaluate.sh timeout=none->30 onFailure=none->block" || { CASE_DETAIL="the refresh is not shown before->after: $(printf '%s\n' "$RG_OUT" | command grep -F '~' | tr '\n' '|' | cut -c1-400)"; return 1; }
  [ "$(count_f "$RG_OUT" "       ~ ")" = 3 ] || { CASE_DETAIL="expected 3 refresh lines: $RG_OUT"; return 1; }
  has_f "$RG_OUT" "settings.json was not changed" && { CASE_DETAIL="claims settings.json was not changed"; return 1; }
  has_f "$RG_OUT" "Guardrails hook registrations refreshed in .claude/settings.json" || { CASE_DETAIL="the heading is not relayed: $RG_OUT"; return 1; }
}
case_P9b() {  # refresh-guardrails.sh shows the generator's WARNING, which it would otherwise swallow
  local t d c
  t="$(newtmp)"; d="$t/p"; c="$t/home/.claude-dev-framework"
  rg_proj "$d" "$c" || { CASE_DETAIL="fixture"; return 1; }
  knob "$c" policy timeout-only; knob "$c" stderr "$WARN_LINE"$'\n'
  rg "$1" "$d" "$t/home"
  [ "$RG_RC" -eq 0 ] || { CASE_DETAIL="rc=$RG_RC: $(last3 "$RG_OUT")"; return 1; }
  line_f "$RG_OUT" "     Guardrails generator: $WARN_LINE" || { CASE_DETAIL="the WARNING is swallowed: $(printf '%s\n' "$RG_OUT" | tail -8 | tr '\n' '|' | cut -c1-500)"; return 1; }
  line_f "$RG_OUT" "       ~ PreToolUse (Bash): ${CMDP}enforce-evaluate.sh timeout=none->30 onFailure=none" || { CASE_DETAIL="the timeout-only refresh is not shown: $RG_OUT"; return 1; }
}
GR='Development Guardrails in this project'
STUBBIN="$WORK/stub-bin"; mkdir -p "$STUBBIN"
for t in brew curl; do printf '#!/bin/sh\nexit 1\n' > "$STUBBIN/$t"; chmod +x "$STUBBIN/$t"; done
cv_proj() {   # DIR SHAPE [norecord] — a project with a one-row tool matrix and the clone at DIR/home
  proj "$1" "$2" ${3:+"$3"} && mk_clone "$1/home/.claude-dev-framework" 4.6.0 || return 1
  mkdir -p "$1/templates/tool-matrix"
  jq -n '{description:"fixture", schema_version:1, scope:"common", tools:[{"name":"Probe","category":"version_control","phase":0,"required":false,"check_command":"true","version_command":"echo 1.0.0","min_version":null,"latest_check":null}]}' \
    > "$1/templates/tool-matrix/common.json"
}
cv() { ( cd "$2" && HOME="$2/home" PATH="$STUBBIN:$PATH" bash "$1/scripts/check-versions.sh" </dev/null 2>&1 ); }
case_P10() {  # check-versions.sh names the entries without the policy and offers the refresh
  local d out
  d="$(newtmp)/p"; cv_proj "$d" old || { CASE_DETAIL="fixture"; return 1; }
  out="$(cv "$1" "$d")"
  has_f "$out" "[WARN] $GR: 4.6.0, but 3 of its hook registrations in .claude/settings.json carry a stale failure policy (timeout or onFailure) (" \
    || { CASE_DETAIL="no refresh row: $(printf '%s' "$out" | command grep -F "$GR" | tr '\n' '|' | cut -c1-400)"; return 1; }
  has_f "$out" "enforce-evaluate" && has_f "$out" "config-guard" && has_f "$out" "verification-gate" || { CASE_DETAIL="the row does not name the three"; return 1; }
  has_f "$out" "  $GR: bash scripts/refresh-guardrails.sh" || { CASE_DETAIL="the refresh is not offered"; return 1; }
  has_f "$out" "missing from .claude/settings.json" && { CASE_DETAIL="a registered entry is called missing: $(printf '%s' "$out" | command grep -F "$GR" | tr '\n' '|')"; return 1; }
  # a missing entry beside the refreshes: each gets its own clause
  d="$(newtmp)/p"; cv_proj "$d" old norecord || { CASE_DETAIL="fixture 2"; return 1; }
  out="$(cv "$1" "$d")"
  has_f "$out" "[WARN] $GR: 4.6.0, but 1 of its hook registrations is missing from .claude/settings.json (record-approval), and 3 in it carry a stale failure policy (" \
    || { CASE_DETAIL="no combined row: $(printf '%s' "$out" | command grep -F "$GR" | tr '\n' '|' | cut -c1-400)"; return 1; }
  # current: no row at all
  d="$(newtmp)/p"; cv_proj "$d" current || { CASE_DETAIL="fixture 3"; return 1; }
  out="$(cv "$1" "$d")"
  has_f "$out" "[WARN] $GR" && { CASE_DETAIL="a current project gets a row: $(printf '%s' "$out" | command grep -F "$GR" | tr '\n' '|')"; return 1; }
  has_f "$out" "$GR: 4.6.0 — up to date" || { CASE_DETAIL="no up-to-date row: $(printf '%s' "$out" | command grep -F "$GR" | tr '\n' '|')"; return 1; }
}
case_P11() {  # a generator without onFailure (an older Claude Code) KEEPS a registered onFailure: nothing to refresh, file byte-identical
  local t d c s
  t="$(newtmp)"; d="$t/p"; c="$t/clone"
  proj "$d" current && mk_clone "$c" 4.6.0 || { CASE_DETAIL="fixture"; return 1; }
  knob "$c" policy timeout-only
  s="$(cksum < "$d/.claude/settings.json")"
  reg "$1" "$d" "$c"
  [ "$REG_RC" -eq 0 ] || { CASE_DETAIL="rc=$REG_RC: $(last3 "$REG_OUT")"; return 1; }
  [ "$(cksum < "$d/.claude/settings.json")" = "$s" ] || { CASE_DETAIL="the file was rewritten: $REG_OUT"; return 1; }
  jq -e '[.hooks.PreToolUse[0,1,3].hooks[0].onFailure] == ["block", "block", "block"]' "$d/.claude/settings.json" >/dev/null 2>&1 \
    || { CASE_DETAIL="a registered onFailure=block was loosened: $(jq -c '.hooks.PreToolUse' "$d/.claude/settings.json")"; return 1; }
  has_f "$REG_OUT" "  ~ " && { CASE_DETAIL="a refresh named where the generator carries nothing newer: $REG_OUT"; return 1; }
  has_f "$REG_OUT" "none to refresh" || { CASE_DETAIL="does not say none to refresh: $REG_OUT"; return 1; }
}
case_P11b() { # the same generator over a stale timeout: the timeout is refreshed, onFailure=block is KEPT and the line says so
  local t d c before
  t="$(newtmp)"; d="$t/p"; c="$t/clone"
  proj "$d" stale && mk_clone "$c" 4.6.0 || { CASE_DETAIL="fixture"; return 1; }
  knob "$c" policy timeout-only
  before="$(jq -c . "$d/.claude/settings.json")"
  reg "$1" "$d" "$c"
  [ "$REG_RC" -eq 0 ] || { CASE_DETAIL="rc=$REG_RC: $(last3 "$REG_OUT")"; return 1; }
  same_but "$d/.claude/settings.json" "$before" '.hooks.PreToolUse[0].hooks[0].timeout = 30' || return 1
  line_f "$REG_OUT" "  ~ PreToolUse (Bash): ${CMDP}enforce-evaluate.sh timeout=5->30 onFailure=block (kept onFailure=block: the generator emitted none)" \
    || { CASE_DETAIL="the refresh does not show before->after and the kept field: $REG_OUT"; return 1; }
  [ "$(count_f "$REG_OUT" "  ~ ")" = 1 ] || { CASE_DETAIL="expected exactly 1 refresh named: $REG_OUT"; return 1; }
}
case_P12() {  # the reviewer's scenario: the 4.5.0 generator under an old Claude Code — WARNING, no onFailure — loosens nothing
  local t d c s
  t="$(newtmp)"; d="$t/p"; c="$t/clone"
  proj "$d" current && mk_clone "$c" 4.6.0 || { CASE_DETAIL="fixture"; return 1; }
  knob "$c" policy timeout-only; knob "$c" stderr 'WARNING: Claude Code not found on PATH; fail-closed hooks need Claude Code 2.1.295 or later. Until then the guard hooks will not fail closed when they time out, crash or cannot start: the action they guard goes ahead. Fix: install Claude Code 2.1.295 or later (https://claude.com/claude-code) so that `claude` is on PATH, then re-run sync.sh in this project.'$'\n'
  s="$(cksum < "$d/.claude/settings.json")"
  reg "$1" "$d" "$c"
  [ "$REG_RC" -eq 0 ] || { CASE_DETAIL="rc=$REG_RC: $(last3 "$REG_OUT")"; return 1; }
  has_f "$REG_OUT" "Guardrails generator: WARNING: Claude Code not found on PATH" || { CASE_DETAIL="the WARNING is not shown: $(last3 "$REG_OUT")"; return 1; }
  [ "$(cksum < "$d/.claude/settings.json")" = "$s" ] || { CASE_DETAIL="the file was rewritten under an old Claude Code: $REG_OUT"; return 1; }
  jq -e '[.hooks.PreToolUse[0,1,3].hooks[0].onFailure] == ["block", "block", "block"]' "$d/.claude/settings.json" >/dev/null 2>&1 \
    || { CASE_DETAIL="onFailure=block was removed: $(jq -c '.hooks.PreToolUse' "$d/.claude/settings.json")"; return 1; }
  has_f "$REG_OUT" "onFailure=none" && { CASE_DETAIL="a refresh to onFailure=none was made: $REG_OUT"; return 1; }
  return 0
}
case_P13() {  # a generator that refuses at session start is a row, never silence
  local d out
  d="$(newtmp)/p"; cv_proj "$d" current || { CASE_DETAIL="fixture"; return 1; }
  knob "$d/home/.claude-dev-framework" rc 1; knob "$d/home/.claude-dev-framework" stderr "$ERR_LINE"$'\n'
  out="$(cv "$1" "$d")"
  has_f "$out" "[WARN] $GR: hook registrations could not be checked: Guardrails generator: ERROR: claude is not on this shell's PATH" \
    || { CASE_DETAIL="no row for the refused check: $(printf '%s' "$out" | command grep -F "$GR" | tr '\n' '|' | cut -c1-400)"; return 1; }
  out="$(sv "$1" "$d")"
  has_f "$out" "GUARDRAILS NOTICE" && has_f "$out" "hook registrations could not be checked" || { CASE_DETAIL="the session start is silent about a check that did not run: $(last3 "$out")"; return 1; }
}
case_P14() {  # below the floor AND work to do: one row with both halves, and the refresh offered
  local d out
  d="$(newtmp)/p"; cv_proj "$d" old norecord || { CASE_DETAIL="fixture"; return 1; }
  jq '.frameworkVersion = "4.5.0"' "$d/.claude/manifest.json" > "$d/m" && mv "$d/m" "$d/.claude/manifest.json"
  printf '4.5.0\n' > "$d/home/.claude-dev-framework/FRAMEWORK_VERSION"; ( cd "$d/home/.claude-dev-framework" && git add -A && git commit -q -m v450 ) >/dev/null 2>&1
  out="$(cv "$1" "$d")"
  has_f "$out" "[WARN] $GR: 4.5.0 $FLOOR_ROW; and 1 of its hook registrations is missing from .claude/settings.json (record-approval), and 3 in it carry a stale failure policy (" \
    || { CASE_DETAIL="the floor row does not carry the registration check: $(printf '%s' "$out" | command grep -F "$GR" | tr '\n' '|' | cut -c1-500)"; return 1; }
  has_f "$out" "  $GR: bash scripts/refresh-guardrails.sh" || { CASE_DETAIL="the refresh is not offered below the floor"; return 1; }
  out="$(sv "$1" "$d")"
  has_f "$out" "GUARDRAILS UPDATE OFFER" && has_f "$out" "bash scripts/refresh-guardrails.sh" || { CASE_DETAIL="the session start does not offer the refresh: $(last3 "$out")"; return 1; }
}

# ── H: the two floors (Karl's ruling B, 2026-11-16) ──────────────────────────
# SOIF_GUARDRAILS_MIN (4.6.0) is what the framework REQUIRES — the fail-closed
# hook policy and the runaway scan — and names a project or clone below it.
# SOIF_GUARDRAILS_PICK_MIN (4.4.0) is where answering by option id arrived and
# drives the route, the mixed-install refusal and pending-approval.sh's
# messages. Measured before the split: one constant raised to 4.6.0 routed a
# 4.5.0 project to `legacy`, where the agent's own --decision is accepted.
h_proj() {   # DIR PROJECT-VERSION CLONE-VERSION — a current-shape project and its clone at those versions
  cv_proj "$1" current || return 1
  jq --arg v "$2" '.frameworkVersion = $v' "$1/.claude/manifest.json" > "$1/m" && mv "$1/m" "$1/.claude/manifest.json" || return 1
  printf '%s\n' "$3" > "$1/home/.claude-dev-framework/FRAMEWORK_VERSION"
  ( cd "$1/home/.claude-dev-framework" && git add -A && git commit -q -m version ) >/dev/null 2>&1
  printf '[]\n' > "$1/.claude/bypass-audit.json"
}
sv() { ( cd "$2" && HOME="$2/home" PATH="$STUBBIN:$PATH" bash "$1/scripts/session-version-check.sh" </dev/null 2>&1 ); }
route() { ( . "$1/scripts/lib/guardrails.sh" >/dev/null 2>&1 && soif_gr_route "$2" ); }
clone_warn() {   # ROOT CLONE — init.sh's clone update with no one to ask (soif_guardrails_clone_update)
  ( . "$1/scripts/lib/helpers-core.sh" >/dev/null 2>&1; . "$1/scripts/lib/guardrails.sh" >/dev/null 2>&1; soif_guardrails_clone_update "$2" true ) </dev/null 2>&1
}
v2_sentinel() {
  jq -n '{schema: 2, question: "Commit the fix?",
          options: [{id: "A1", text: "Commit the staged fix", approves: "commit"},
                    {id: "A2", text: "Hold - do not commit", approves: "none"}],
          recommendation: "A1", offered_at: "2026-11-16T00:00:00Z"}' > "$1/.claude/pending-approval.json"
}
v1_sentinel() {   # the pre-BL-320 shape, which only Guardrails below the pick floor can take an answer to
  jq -n '{question: "old style", options: ["A1: foo", "A2: bar"], recommendation: "A1", offered_at: "2026-10-01T00:00:00Z"}' > "$1/.claude/pending-approval.json"
}
PA_OUT=""; PA_RC=0
pa() {   # ROOT DIR ARGS… — ROOT's pending-approval.sh, run in DIR
  local r="$1" d="$2"; shift 2
  PA_RC=0
  PA_OUT="$( cd "$d" && bash "$r/scripts/pending-approval.sh" "$@" </dev/null 2>&1 )" || PA_RC=$?
}
FLOOR_ROW='is below 4.6.0, the minimum for this framework'"'"'s fail-closed hook policy and runaway scan: until it is updated, a guard that hangs, crashes or cannot start lets the action it guards through'
case_H1() {   # 4.5.0: below the floor (the row, the notice, the clone warning) and still answering by option id
  local d out r
  d="$(newtmp)/p"; h_proj "$d" 4.5.0 4.5.0 || { CASE_DETAIL="fixture"; return 1; }
  out="$(cv "$1" "$d")"
  has_f "$out" "[WARN] $GR: 4.5.0 $FLOOR_ROW" || { CASE_DETAIL="no floor row: $(printf '%s' "$out" | command grep -F "$GR" | tr '\n' '|' | cut -c1-400)"; return 1; }
  has_f "$out" "BELOW MINIMUM" && { CASE_DETAIL="worded as BELOW MINIMUM, which makes the session start URGENT"; return 1; }
  has_f "$out" "approval questions" && { CASE_DETAIL="the row still blames approval questions, which 4.5.0 answers: $(printf '%s' "$out" | command grep -F "$GR" | tr '\n' '|')"; return 1; }
  out="$(sv "$1" "$d")"
  has_f "$out" "GUARDRAILS NOTICE" && has_f "$out" "4.5.0 is below 4.6.0" && has_f "$out" "the clone itself needs updating first" \
    || { CASE_DETAIL="not told as a below-floor notice: $(last3 "$out")"; return 1; }
  has_f "$out" "GUARDRAILS UPDATE OFFER" && { CASE_DETAIL="offers an update the clone cannot give"; return 1; }
  r="$(route "$1" "$d")"; [ "$r" = pick ] || { CASE_DETAIL="route is '$r', not pick: 4.5.0 answers by option id"; return 1; }
  v2_sentinel "$d"
  pa "$1" "$d" --resolve --decision accept
  [ "$PA_RC" -ne 0 ] && has_f "$PA_OUT" "--decision is not used here" && [ -f "$d/.claude/pending-approval.json" ] \
    || { CASE_DETAIL="the agent's own --decision was taken at 4.5.0: rc=$PA_RC $(last3 "$PA_OUT")"; return 1; }
  has_f "$PA_OUT" "older than 4.4.0" || { CASE_DETAIL="the refusal does not name the 4.4.0 pick floor: $(last3 "$PA_OUT")"; return 1; }
  v1_sentinel "$d"
  pa "$1" "$d" --validate
  [ "$PA_RC" -ne 0 ] && has_f "$PA_OUT" "schema 1 — the Development Guardrails 4.4.0 and later cannot take an answer to it" \
    || { CASE_DETAIL="a schema-1 question at 4.5.0 is not refused naming the 4.4.0 pick floor: rc=$PA_RC $(last3 "$PA_OUT")"; return 1; }
  out="$(clone_warn "$1" "$d/home/.claude-dev-framework")"
  has_f "$out" "older than 4.6.0, the minimum for this framework's fail-closed hook policy" || { CASE_DETAIL="the clone-update warning does not name the floor: $(last3 "$out")"; return 1; }
}
case_H2() {   # 4.6.0: at the floor — no row, silent session start, answering by option id
  local d out r
  d="$(newtmp)/p"; h_proj "$d" 4.6.0 4.6.0 || { CASE_DETAIL="fixture"; return 1; }
  out="$(cv "$1" "$d")"
  has_f "$out" "[WARN] $GR" && { CASE_DETAIL="a project at the floor gets a row: $(printf '%s' "$out" | command grep -F "$GR" | tr '\n' '|')"; return 1; }
  has_f "$out" "$GR: 4.6.0 — up to date" || { CASE_DETAIL="no up-to-date row: $(printf '%s' "$out" | command grep -F "$GR" | tr '\n' '|')"; return 1; }
  out="$(sv "$1" "$d")"
  [ -z "$out" ] || { CASE_DETAIL="the session start spoke at the floor: $(last3 "$out")"; return 1; }
  r="$(route "$1" "$d")"; [ "$r" = pick ] || { CASE_DETAIL="route is '$r', not pick"; return 1; }
}
case_H3() {   # 4.3.7: below both floors — routed legacy, the row names the 4.6.0 floor, the messages name the 4.4.0 pick floor
  local d out r
  d="$(newtmp)/p"; h_proj "$d" 4.3.7 4.3.7 || { CASE_DETAIL="fixture"; return 1; }
  r="$(route "$1" "$d")"; [ "$r" = legacy ] || { CASE_DETAIL="route is '$r': 4.3.7 predates the answer by option id"; return 1; }
  out="$(cv "$1" "$d")"
  has_f "$out" "[WARN] $GR: 4.3.7 $FLOOR_ROW" || { CASE_DETAIL="no floor row: $(printf '%s' "$out" | command grep -F "$GR" | tr '\n' '|' | cut -c1-400)"; return 1; }
  v1_sentinel "$d"
  pa "$1" "$d" --validate
  [ "$PA_RC" -eq 0 ] && ! has_f "$PA_OUT" "Schema error" \
    || { CASE_DETAIL="a schema-1 question is refused where the Guardrails record no pick (the pick floor moved): rc=$PA_RC $(last3 "$PA_OUT")"; return 1; }
}
case_H4() {   # the mixed install is still refused at 4.5.0: a clone below the floor but at the pick floor, over an old writer
  local t d c
  t="$(newtmp)"; d="$t/p"; c="$t/home/.claude-dev-framework"
  rg_proj "$d" "$c" || { CASE_DETAIL="fixture"; return 1; }
  printf '4.5.0\n' > "$c/FRAMEWORK_VERSION"; ( cd "$c" && git add -A && git commit -q -m v450 ) >/dev/null 2>&1
  jq '.frameworkVersion = "4.4.0"' "$d/.claude/manifest.json" > "$d/m" && mv "$d/m" "$d/.claude/manifest.json"
  mkdir -p "$d/scripts" && printf '#!/usr/bin/env bash\n# scripts/pending-approval.sh (before BL-320)\nset -euo pipefail\n' > "$d/scripts/pending-approval.sh"
  rg "$1" "$d" "$t/home"
  [ "$RG_RC" -ne 0 ] || { CASE_DETAIL="rc=0: 4.5.0 was installed beside a writer it cannot answer"; return 1; }
  has_f "$RG_OUT" "older approval question" && has_f "$RG_OUT" "Guardrails 4.5.0 cannot take an answer" \
    || { CASE_DETAIL="the refusal does not name the mixed install: $(last3 "$RG_OUT")"; return 1; }
  [ "$(jq -r .frameworkVersion "$d/.claude/manifest.json")" = 4.4.0 ] || { CASE_DETAIL="the manifest moved"; return 1; }
}

# ── runner ───────────────────────────────────────────────────────────────────
check() {   # LABEL CASE
  local rc=0
  CASE_DETAIL=""
  "$2" "$REPO_ROOT" || rc=$?
  case "$rc" in
    0)  pass "$1" ;;
    *)  fail_ "$1" "$CASE_DETAIL" ;;
  esac
}
echo "=== P — the registration carries the policy ==="
check "P1: a 4.5.0-shaped generator — each entry registered whole and equal to the generated object, appended; nothing else moved" case_P1
check "P2: a key the generator does not emit today survives" case_P2
check "P3: the generator's WARNING is shown as 'Guardrails generator: …' and the entries land without onFailure" case_P3
check "P4: the generator's ERROR and rc 1 — refused on the [FAIL] line with its message, file byte-identical, never 'none missing'" case_P4
check "P5: upgrade — 4.4.x-shaped entries gain timeout/onFailure in place; keys, positions, Solo's and the user's entries intact; each named" case_P5
check "P6: entries already carrying the policy — byte-identical, nothing refreshed, 'none missing'" case_P6
check "P7: check mode lists the addition by name and each refresh with its policy, and writes nothing" case_P7
check "P8: the receipt — a refresh that never landed is a [FAIL], not 'refreshed'" case_P8
check "P9: refresh-guardrails.sh prints each refresh and the heading, not 'was not changed'" case_P9
check "P9b: refresh-guardrails.sh shows the generator's WARNING" case_P9b
check "P10: check-versions.sh — the row names the entries without the policy, a missing entry gets its own clause, a current project gets none" case_P10
check "P11: a generator without onFailure (an older Claude Code) keeps a registered onFailure=block — nothing to refresh, file byte-identical" case_P11
check "P11b: the same generator over a stale timeout — timeout 5->30 refreshed, onFailure=block kept and said so" case_P11b
check "P12: the reviewer's scenario — WARNING 'Claude Code not found on PATH' shown, no onFailure emitted, nothing loosened" case_P12
check "P13: a generator that refuses at session start — a 'could not be checked' row and notice, never silence" case_P13
check "P14: below the floor with a missing registration and stale policy — one row with both halves, the refresh offered" case_P14
echo "=== H — the two floors: 4.6.0 required, 4.4.0 for the answer by option id ==="
check "H1: 4.5.0 — below the floor in the row, the notice and the clone warning; routed pick; the agent's --decision refused, naming 4.4.0" case_H1
check "H2: 4.6.0 — at the floor: no row, silent session start, routed pick" case_H2
check "H3: 4.3.7 — routed legacy; the row names the 4.6.0 floor, the message names the 4.4.0 pick floor" case_H3
check "H4: a 4.5.0 clone over an old question writer is still refused as a mixed install" case_H4

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
  local id="$1" rel="$2" mark="$3" repl="$4" killer="$5" what="$6" m why rc=0
  m="$(newtmp)/mirror"
  mk_mirror "$REPO_ROOT" "$m" || { fail_ "$id" "could not build a mirror"; return; }
  why="$(mutate "$m/$rel" "$mark" "$repl")" || { fail_ "$id" "mutant did not land: $why"; return; }
  CASE_DETAIL=""
  "$killer" "$m" || rc=$?
  case "$rc" in
    0)  fail_ "$id" "$what — SURVIVED: ${killer#case_} still passes against the mutant" ;;
    *)  pass "$id (MUTATION) — $what: killed by ${killer#case_} ($(printf '%s' "$CASE_DETAIL" | cut -c1-160))" ;;
  esac
}
echo "=== M — mutants ==="
GL=scripts/lib/guardrails.sh
mutant M1  "$GL" '# BL-375-ENTRY-WHOLE' "  done < <(jq -c '.hooks | to_entries[] | .key as \$e | .value[]? | (.matcher // \"\") as \$m | .hooks[]? | select(type == \"object\") | {event: \$e, matcher: \$m, entry: {type: \"command\", command: .command}}' <<< \"\$gen\")" case_P1 "a registered entry is rebuilt as {type, command}: the policy is dropped"
mutant M2  "$GL" '# BL-375-GEN-STDERR' "            generate_settings_json \"\${active[@]}\" ) 2>/dev/null )\" || gen_rc=\$?" case_P3 "the generator's stderr goes nowhere"
mutant M3  "$GL" '# BL-375-GEN-SHOW' '  :' case_P3 "the generator's stderr is captured and never shown"
mutant M4  "$GL" '# BL-375-GEN-RC' '  if false; then' case_P4 "a refusal is read as a generator that printed nothing"
mutant M5  "$GL" '# BL-375-POLICY-DIFF' '      true' case_P6 "every registered entry is rewritten on every run"
mutant M6  "$GL" '# BL-375-POLICY-REFRESH' '  prog="$prog"' case_P5 "the policy is never written to a registered entry"
mutant M7  "$GL" '# BL-375-REFRESH-RECEIPT' '    rlost=""' case_P8 "a refresh that never landed is reported as done"
mutant M8  "$GL" '# BL-375-CHECK-REFRESH' '    :' case_P7 "check mode hides the refreshes"
mutant M9  scripts/check-versions.sh '# BL-375-CV-REFRESH' '    :' case_P10 "the session start never names an entry without the policy"
mutant M10 scripts/refresh-guardrails.sh '# BL-375-RG-REFRESH-LINES' "  printf '%s\\n' \"\$REG_OUT\" | grep '^  + ' | sed 's/^/     /'" case_P9 "the refresh script hides the refreshes it made"
mutant M11 scripts/refresh-guardrails.sh '# BL-375-RG-GEN-LINES' ':' case_P9b "the refresh script swallows the generator's WARNING"
# Review round 3: the refresh that loosened (del restored), the silent refused check, the floor row that stopped early.
mutant M12 "$GL" '# BL-375-POLICY-REFRESH' "  prog=\"\$prog\"' | reduce \$ref[] as \$r (.; .hooks[\$r.event] |= map(if (.hooks | type) == \"array\" then .hooks |= map(if ((.command // \"\") | tostring | contains(\$r.name)) then (if (\$r.entry | has(\"timeout\")) then .timeout = \$r.entry.timeout else del(.timeout) end | if (\$r.entry | has(\"onFailure\")) then .onFailure = \$r.entry.onFailure else del(.onFailure) end) else . end) else . end))'" case_P11b "a field the generator lacks is deleted: onFailure=block loosened under an old Claude Code"
mutant M13 scripts/check-versions.sh '# BL-375-CV-GEN-ERR' '    :' case_P13 "a generator that refuses at session start is silence"
mutant M14 scripts/check-versions.sh '# BL-375-CV-FLOOR-WORK' '    :' case_P14 "the floor row hides what is unregistered or stale"
# The two floors: each constant's consumer swapped to the other constant.
mutant MM1 "$GL" '# BL-375-MIN-460' 'SOIF_GUARDRAILS_MIN="4.4.0"' case_H1 "the required floor is still 4.4.0: a 4.5.0 project is not told"
mutant MM2 "$GL" '# BL-375-FLOOR-BELOW' '  soif_gr_xyz_valid "${1:-}" && [ "$(soif_gr_xyz_cmp "$1" "$SOIF_GUARDRAILS_PICK_MIN")" = lt ]' case_H1 "below-minimum reads the pick floor: a 4.5.0 project is not told"
mutant MM3 "$GL" '# BL-375-PICK-MIN' 'SOIF_GUARDRAILS_PICK_MIN="4.6.0"' case_H1 "the pick floor follows the required floor: 4.5.0 is routed legacy and the agent's own --decision is taken"
mutant MM4 "$GL" '# BL-375-PICK-ROUTE' '  c="$(soif_gr_xyz_cmp "$v" "$SOIF_GUARDRAILS_MIN")"' case_H1 "the route reads the required floor: 4.5.0 is legacy"
mutant MM5 "$GL" '# BL-375-PICK-MIXED' '  soif_gr_xyz_valid "${2:-}" && ! soif_gr_below_min "$2" || return 1' case_H4 "the mixed install reads the required floor: 4.5.0 lands beside an old writer"
mutant MM6 "$GL" '# BL-375-PICK-BELOW' '  soif_gr_xyz_valid "${1:-}" && [ "$(soif_gr_xyz_cmp "$1" "$SOIF_GUARDRAILS_MIN")" = lt ]' case_H4 "below-pick-minimum reads the required floor: 4.5.0 lands beside an old writer"
mutant MM7 scripts/pending-approval.sh '# BL-375-PICK-PA' 'PA_PICK_MIN="${SOIF_GUARDRAILS_MIN:-4.4.0}"' case_H1 "the messages name the required floor, not the version that records a pick"
mutant MM8 scripts/session-version-check.sh '# BL-375-SVC-MIN' "  if printf '%s\\n' \"\$GR_NOTICE\" | grep -qF \", the minimum for this framework's approval questions\"; then" case_H1 "the session notice no longer recognises the below-floor row"

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
