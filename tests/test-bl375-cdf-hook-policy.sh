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
#   P11 absent vs present the other way: a generator without onFailure (an
#       older Claude Code) removes it from an entry that has it, keeps timeout
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
    | (if $shape == "current" then $pol30 else {} end) as $p30 | (if $shape == "current" then $pol600 else {} end) as $p600
    | {
      permissions: {allow: ["Bash(git status)"], deny: ["Edit(/.claude/settings.json)"]},
      hooks: ({
        SessionStart: [{hooks: [{type: "command", command: "bash \"$CLAUDE_PROJECT_DIR\"/scripts/session-version-check.sh"}]}],
        PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: "bash \"$CLAUDE_PROJECT_DIR\"/scripts/pre-commit-gate.sh", timeout: 5}]}],
        UserPromptSubmit: [{hooks: [{type: "command", command: "echo mine"}]}]
      } + (if $shape == "fresh" then {} else {
        SessionStart: [{hooks: [{type: "command", command: ($p + "session-start.sh")},
                                {type: "command", command: "bash \"$CLAUDE_PROJECT_DIR\"/scripts/session-version-check.sh"}]}],
        PreToolUse: [{matcher: "Bash", hooks: [({type: "command", command: ($p + "enforce-evaluate.sh"), note: "keep"} + $p30)]},
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
  line_f "$REG_OUT" "  ~ PreToolUse (Bash): ${CMDP}enforce-evaluate.sh timeout=30 onFailure=block" || { CASE_DETAIL="enforce-evaluate's refresh is not named as specified: $REG_OUT"; return 1; }
  line_f "$REG_OUT" "  ~ PreToolUse (Bash|Write|Edit|NotebookEdit): ${CMDP}config-guard.sh timeout=30 onFailure=block" || { CASE_DETAIL="config-guard's refresh is not named: $REG_OUT"; return 1; }
  line_f "$REG_OUT" "  ~ PreToolUse (Bash): bash .claude/framework/hooks/verification-gate.sh timeout=600 onFailure=block" || { CASE_DETAIL="the differently spelled entry is not named as the file spells it: $REG_OUT"; return 1; }
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
  line_f "$RG_OUT" "       ~ PreToolUse (Bash): ${CMDP}enforce-evaluate.sh timeout=30 onFailure=block" || { CASE_DETAIL="the refresh is not shown: $(printf '%s\n' "$RG_OUT" | command grep -F 'settings' | tr '\n' '|' | cut -c1-400)"; return 1; }
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
  line_f "$RG_OUT" "       ~ PreToolUse (Bash): ${CMDP}enforce-evaluate.sh timeout=30 onFailure=none" || { CASE_DETAIL="the timeout-only refresh is not shown: $RG_OUT"; return 1; }
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
  has_f "$out" "[WARN] $GR: 4.6.0, but 3 of its hook registrations in .claude/settings.json are without its failure policy (" \
    || { CASE_DETAIL="no refresh row: $(printf '%s' "$out" | command grep -F "$GR" | tr '\n' '|' | cut -c1-400)"; return 1; }
  has_f "$out" "enforce-evaluate" && has_f "$out" "config-guard" && has_f "$out" "verification-gate" || { CASE_DETAIL="the row does not name the three"; return 1; }
  has_f "$out" "  $GR: bash scripts/refresh-guardrails.sh" || { CASE_DETAIL="the refresh is not offered"; return 1; }
  has_f "$out" "missing from .claude/settings.json" && { CASE_DETAIL="a registered entry is called missing: $(printf '%s' "$out" | command grep -F "$GR" | tr '\n' '|')"; return 1; }
  # a missing entry beside the refreshes: each gets its own clause
  d="$(newtmp)/p"; cv_proj "$d" old norecord || { CASE_DETAIL="fixture 2"; return 1; }
  out="$(cv "$1" "$d")"
  has_f "$out" "[WARN] $GR: 4.6.0, but 1 of its hook registrations is missing from .claude/settings.json (record-approval), and 3 in it are without its failure policy (" \
    || { CASE_DETAIL="no combined row: $(printf '%s' "$out" | command grep -F "$GR" | tr '\n' '|' | cut -c1-400)"; return 1; }
  # current: no row at all
  d="$(newtmp)/p"; cv_proj "$d" current || { CASE_DETAIL="fixture 3"; return 1; }
  out="$(cv "$1" "$d")"
  has_f "$out" "[WARN] $GR" && { CASE_DETAIL="a current project gets a row: $(printf '%s' "$out" | command grep -F "$GR" | tr '\n' '|')"; return 1; }
  has_f "$out" "$GR: 4.6.0 — up to date" || { CASE_DETAIL="no up-to-date row: $(printf '%s' "$out" | command grep -F "$GR" | tr '\n' '|')"; return 1; }
}
case_P11() {  # absent vs present the other way: onFailure removed where the generator no longer emits it
  local t d c before
  t="$(newtmp)"; d="$t/p"; c="$t/clone"
  proj "$d" current && mk_clone "$c" 4.6.0 || { CASE_DETAIL="fixture"; return 1; }
  knob "$c" policy timeout-only
  before="$(jq -c . "$d/.claude/settings.json")"
  reg "$1" "$d" "$c"
  [ "$REG_RC" -eq 0 ] || { CASE_DETAIL="rc=$REG_RC: $(last3 "$REG_OUT")"; return 1; }
  same_but "$d/.claude/settings.json" "$before" 'del(.hooks.PreToolUse[0].hooks[0].onFailure, .hooks.PreToolUse[1].hooks[0].onFailure, .hooks.PreToolUse[3].hooks[0].onFailure)' || return 1
  line_f "$REG_OUT" "  ~ PreToolUse (Bash): ${CMDP}enforce-evaluate.sh timeout=30 onFailure=none" || { CASE_DETAIL="the removal is not named: $REG_OUT"; return 1; }
  [ "$(count_f "$REG_OUT" "  ~ ")" = 3 ] || { CASE_DETAIL="expected 3 refreshes named: $REG_OUT"; return 1; }
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
check "P11: a generator without onFailure removes it from entries that have it and keeps the timeout" case_P11

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

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
