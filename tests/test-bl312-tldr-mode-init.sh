#!/usr/bin/env bash
# tests/test-bl312-tldr-mode-init.sh — `## BL-312:` TL;DR mode, init.sh's half.
#
# init.sh's --config takes a `tldr_mode` key: a JSON boolean, off when absent,
# and anything else is refused in init.sh's uniform [FAIL] shape. A real
# scaffold with it on writes `tldr_mode: true`, appends CLAUDE.md's TL;DR Mode
# section, ships the hook and its lib, and registers the hook in the Stop group
# beside the Development Guardrails' stop-checklist, the Qdrant reminder and the
# bypass detector — all measured here, not assumed. Without the key: `false` is
# written, no section, and the hook is still registered (it reads the key).
#
# THIS FILE RUNS init.sh, so it lives in the full lane (CLAUDE.md's membership
# rule); tests/test-bl312-tldr-mode.sh carries the unit-lane cases, including
# init.sh's question and seed BY STRUCTURE.
#
# I1-I4  --validate-only: true, absent, false, a string.
# I5     a real scaffold, on — end to end, including the shipped hook and the
#        project's own reconfigure-project.sh switching it off.
# I6     a real scaffold, no key.
# I7     the interactive setup with PIPED stdin (tests/test-bl180-interactive-
#        enforcement.sh's fed sequence plus a spare `y`): the question is NOT
#        asked, so it takes no line meant for a later prompt, and it is off.
# I8     the interactive setup over a real pty (expect; skipped loudly without
#        it), --dry-run: `y` is on; Enter and a stray `1` are off.
# MI1-3  mutants of the three init.sh marked lines (MI2 scaffolds from a mirror).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

echo "== BL-312 — TL;DR mode through init.sh =="
for t in git jq; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done
WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT
newtmp() { mktemp -d "$WORK/tXXXXXX"; }
CASE_DETAIL=""
check() {
  local label="$1" fn="$2"; shift 2
  CASE_DETAIL=""
  if "$fn" "$@"; then pass "$label"; else fail_ "$label" "$CASE_DETAIL"; fi
}

# _cfg DIR EXTRA_JQ — a config for a project at DIR/proj, with EXTRA_JQ merged in.
_cfg() {
  jq -n --arg d "$1/proj" '{project:"tl-probe", platform:"web", deployment:"personal", language:"typescript", git_host:"github", project_dir:$d}' \
    | jq "$2" > "$1/cfg.json"
}
# _validate ROOT DIR — init.sh --validate-only on DIR/cfg.json. Sets VRC, VJSON, VALL.
VRC=0; VJSON=""; VALL=""
_validate() {
  ( cd "$2" && bash "$1/init.sh" --non-interactive --config "$2/cfg.json" --validate-only ) > "$2/v.out" 2> "$2/v.err"
  VRC=$?
  VJSON="$(sed -n '/^{/,/^}/p' "$2/v.out")"
  VALL="$(cat "$2/v.out" "$2/v.err")"
}
case_I1() {   # tldr_mode true → resolved true, and the key is not "unknown"
  local d; d="$(newtmp)"; _cfg "$d" '. + {tldr_mode: true}'; _validate "$1" "$d"
  CASE_DETAIL="rc=$VRC tldr_mode=$(printf '%s' "$VJSON" | jq -c .tldr_mode 2>/dev/null) unknown-warning=$(printf '%s' "$VALL" | command grep -c 'unknown config field: tldr_mode')"
  [ "$VRC" -eq 0 ] && [ "$(printf '%s' "$VJSON" | jq -c .tldr_mode)" = "true" ] \
    && ! printf '%s' "$VALL" | command grep -q 'unknown config field: tldr_mode'
}
case_I2() {   # no key → false
  local d; d="$(newtmp)"; _cfg "$d" '.'; _validate "$1" "$d"
  CASE_DETAIL="rc=$VRC tldr_mode=$(printf '%s' "$VJSON" | jq -c .tldr_mode 2>/dev/null)"
  [ "$VRC" -eq 0 ] && [ "$(printf '%s' "$VJSON" | jq -c .tldr_mode)" = "false" ]
}
case_I3() {   # false → false
  local d; d="$(newtmp)"; _cfg "$d" '. + {tldr_mode: false}'; _validate "$1" "$d"
  CASE_DETAIL="rc=$VRC tldr_mode=$(printf '%s' "$VJSON" | jq -c .tldr_mode 2>/dev/null)"
  [ "$VRC" -eq 0 ] && [ "$(printf '%s' "$VJSON" | jq -c .tldr_mode)" = "false" ]
}
case_I4() {   # a string is refused in the uniform shape, naming the field
  local d; d="$(newtmp)"; _cfg "$d" '. + {tldr_mode: "yes"}'; _validate "$1" "$d"
  CASE_DETAIL="rc=$VRC out=$(printf '%s' "$VALL" | command grep -m2 -E 'FAIL|Reason' | tr '\n' '|')"
  [ "$VRC" -ne 0 ] && printf '%s' "$VALL" | command grep -qF '[FAIL] init.sh non-interactive: invalid config field tldr_mode' \
    && printf '%s' "$VALL" | command grep -q 'found a string'
}

# _scaffold ROOT DIR EXTRA_JQ — a real init.sh run, no remote. Sets SRC.
SRC=0
_scaffold() {
  _cfg "$2" "$3"
  ( cd "$2" && bash "$1/init.sh" --non-interactive --config "$2/cfg.json" --no-remote-creation ) > "$2/s.out" 2> "$2/s.err"
  SRC=$?
}
_env() { jq -nc --arg m "$1" '{session_id:"bl312", hook_event_name:"Stop", stop_hook_active:false, last_assistant_message:$m}'; }
case_I5() {   # on: key, section at the END, shipped hook + lib, wired beside every other Stop hook; the hook works; reconfigure turns it off
  local d p bad="" g0 last out
  d="$(newtmp)"; p="$d/proj"
  _scaffold "$1" "$d" '. + {tldr_mode: true}'
  [ "$SRC" -eq 0 ] || { CASE_DETAIL="init rc $SRC: $(tail -5 "$d/s.err" | tr '\n' '|')"; return 1; }
  [ "$(jq -c .tldr_mode "$p/.claude/manifest.json" 2>/dev/null)" = "true" ] || bad="$bad [manifest tldr_mode=$(jq -c .tldr_mode "$p/.claude/manifest.json" 2>/dev/null)]"
  [ "$(command grep -cxF '<!-- tldr-mode:begin -->' "$p/CLAUDE.md")" = "1" ] || bad="$bad [section count]"
  last="$(tail -n 1 "$p/CLAUDE.md")"
  [ "$last" = "<!-- tldr-mode:end -->" ] || bad="$bad [the section is not at the end: last line '$last']"
  [ -x "$p/scripts/hooks/tldr-check.sh" ] || bad="$bad [hook not shipped executable]"
  [ -f "$p/scripts/lib/tldr-mode.sh" ] || bad="$bad [lib not shipped]"
  g0="$(jq -r '[.hooks.Stop[0].hooks[]?.command] | join(" | ")' "$p/.claude/settings.json" 2>/dev/null)"
  case "$g0" in *bypass-detector.sh*tldr-check.sh*) : ;; *) bad="$bad [Stop group 0: $g0]" ;; esac
  [ "$(jq '[.hooks.Stop[]?.hooks[]? | select(.command | contains("tldr-check.sh"))] | length' "$p/.claude/settings.json")" = "1" ] || bad="$bad [wired more than once]"
  out="$(printf '%s' "$(_env 'Done. Tests: 3 passed, 0 failed.')" | CLAUDE_PROJECT_DIR="$p" bash "$p/scripts/hooks/tldr-check.sh" 2>/dev/null)"
  printf '%s' "$out" | jq -e '.decision == "block"' >/dev/null 2>&1 || bad="$bad [the shipped hook did not block a reply with no TL;DR]"
  out="$(printf '%s' "$(_env $'Done.\n\n**TL;DR** — fixed; nothing waits on you.')" | CLAUDE_PROJECT_DIR="$p" bash "$p/scripts/hooks/tldr-check.sh" 2>/dev/null)"
  [ -z "$out" ] || bad="$bad [the shipped hook blocked a reply that has a TL;DR]"
  ( cd "$p" && bash scripts/reconfigure-project.sh --tldr-mode off ) > "$d/r.out" 2>&1 || bad="$bad [reconfigure off rc $?: $(tail -2 "$d/r.out" | tr '\n' '|')]"
  [ "$(jq -c .tldr_mode "$p/.claude/manifest.json")" = "false" ] || bad="$bad [reconfigure off left tldr_mode=$(jq -c .tldr_mode "$p/.claude/manifest.json")]"
  [ "$(command grep -cxF '<!-- tldr-mode:begin -->' "$p/CLAUDE.md")" = "0" ] || bad="$bad [reconfigure off left the section]"
  CASE_DETAIL="Stop group 0: [$g0]${bad:+ —$bad}"
  [ -z "$bad" ]
}
case_I6() {   # no key: false written, no section, the hook still registered
  local d p bad=""
  d="$(newtmp)"; p="$d/proj"
  _scaffold "$1" "$d" '.'
  [ "$SRC" -eq 0 ] || { CASE_DETAIL="init rc $SRC: $(tail -5 "$d/s.err" | tr '\n' '|')"; return 1; }
  [ "$(jq -c .tldr_mode "$p/.claude/manifest.json" 2>/dev/null)" = "false" ] || bad="$bad [manifest tldr_mode=$(jq -c .tldr_mode "$p/.claude/manifest.json" 2>/dev/null)]"
  [ "$(command grep -c 'tldr-mode:begin' "$p/CLAUDE.md")" = "0" ] || bad="$bad [a section was written]"
  [ "$(jq '[.hooks.Stop[]?.hooks[]? | select(.command | contains("tldr-check.sh"))] | length' "$p/.claude/settings.json")" = "1" ] || bad="$bad [the hook is not registered once]"
  CASE_DETAIL="${bad:-}"
  [ -z "$bad" ]
}

# The menu ordinals, derived from the same globs collect_project_info reads —
# the derivation tests/test-bl180-interactive-enforcement.sh uses, taking the root.
derive_platform_index() {
  local root="$1" want="$2" idx=0 seen="" f p
  for f in "$root/docs/platform-modules/"*.md "$root/templates/pipelines/release/github/"*.yml; do
    [ -f "$f" ] || continue
    p="$(basename "$f")"; p="${p%.md}"; p="${p%.yml}"
    case " $seen " in *" $p "*) continue ;; esac
    seen="$seen $p"; idx=$((idx + 1))
    [ "$p" = "$want" ] && { echo "$idx"; return 0; }
  done
  return 1
}
derive_language_index() {
  local root="$1" want="$2" platform="$3" idx=0 f l marker csv
  for f in "$root/templates/pipelines/ci/github/"*.yml; do
    [ -f "$f" ] || continue
    l="$(basename "$f" .yml)"; [ "$l" = "other" ] && continue
    marker="$(head -1 "$f")"; csv=""
    case "$marker" in *"# solo-orchestrator: platforms="*) csv="${marker#*platforms=}" ;; esac
    if [ -n "$csv" ]; then case ",$csv," in *",$platform,"*) : ;; *) continue ;; esac; fi
    idx=$((idx + 1))
    [ "$l" = "$want" ] && { echo "$idx"; return 0; }
  done
  return 1
}
case_I7() {   # piped stdin: not asked, no line taken, off — the fed sequence still reaches "Continue?"
  local pi li out
  pi="$(derive_platform_index "$1" web)"; li="$(derive_language_index "$1" typescript web)"
  [ -n "$pi" ] && [ -n "$li" ] || { CASE_DETAIL="could not derive ordinals (platform=$pi language=$li)"; return 1; }
  out="$( cd "$WORK" && printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "$pi" 2 1 2 "$li" Y y | bash "$1/init.sh" --dry-run 2>&1 )"
  CASE_DETAIL="tldr=[$(printf '%s\n' "$out" | command grep -o 'TL;DR mode: o[nf]*' | head -1)] combo=$(printf '%s\n' "$out" | command grep -c 'Platform: web | Track: standard | Language: typescript') enforcement=$(printf '%s\n' "$out" | command grep -c '^  Enforcement: strict$') skipped-note=$(printf '%s\n' "$out" | command grep -c 'TL;DR mode question was not asked')"
  printf '%s\n' "$out" | command grep -q 'TL;DR mode: off' \
    && printf '%s\n' "$out" | command grep -q 'Platform: web | Track: standard | Language: typescript' \
    && printf '%s\n' "$out" | command grep -q '^  Enforcement: strict$' \
    && printf '%s\n' "$out" | command grep -q 'TL;DR mode question was not asked'
}
# _pty ROOT ANSWER — the interactive --dry-run over a pty, answering the TL;DR
# question with ANSWER. Prints the transcript.
_pty() {
  cat > "$WORK/drive.exp" <<'EXPEOF'
set timeout 90
set initsh [lindex $argv 0]
set tl     [lindex $argv 1]
set ans ""
spawn bash $initsh --dry-run
expect {
    -re {Project name}                  { send -- "tlprobe\r";                exp_continue }
    -re {One-sentence description}      { send -- "probe\r";                  exp_continue }
    -re {Project directory}             { send -- "/tmp/bl312-pty-never\r";   exp_continue }
    -re {plain-English summary of what happened} { send -- "$tl\r";           exp_continue }
    -re {Platform type:}                { set ans 1;                          exp_continue }
    -re {Project track:}                { set ans 2;                          exp_continue }
    -re {Personal or organizational\?}  { set ans 1;                          exp_continue }
    -re {Governance mode:}              { set ans 2;                          exp_continue }
    -re {Primary language:}             { set ans 1;                          exp_continue }
    -re {Select \[1-[0-9]+\]}           { send -- "$ans\r";                   exp_continue }
    -re {Continue\? \[Y/n\]}            { send -- "Y\r";                      exp_continue }
    timeout { puts "\nBL312-PTY: TIMEOUT"; puts $expect_out(buffer); exit 3 }
    eof
}
EXPEOF
  ( cd "$WORK" && expect -f "$WORK/drive.exp" "$1/init.sh" "$2" ) 2>&1 | tr -d '\r'
}
case_I8() {   # at a terminal: y → on; Enter → off; a stray 1 → off
  local a b c
  a="$(_pty "$1" y | command grep -o 'TL;DR mode: o[nf]*' | head -1)"
  b="$(_pty "$1" "" | command grep -o 'TL;DR mode: o[nf]*' | head -1)"
  c="$(_pty "$1" 1 | command grep -o 'TL;DR mode: o[nf]*' | head -1)"
  CASE_DETAIL="y=[$a] enter=[$b] 1=[$c]"
  [ "$a" = "TL;DR mode: on" ] && [ "$b" = "TL;DR mode: off" ] && [ "$c" = "TL;DR mode: off" ]
}

echo
echo "=== I — init.sh ==="
check "I1 --config tldr_mode true: resolved true, and init.sh no longer calls the key unknown" case_I1 "$REPO_ROOT"
check "I2 --config without tldr_mode: resolved false (off)" case_I2 "$REPO_ROOT"
check "I3 --config tldr_mode false: resolved false" case_I3 "$REPO_ROOT"
check "I4 --config tldr_mode \"yes\": refused in init.sh's [FAIL] shape, naming the field and the type found" case_I4 "$REPO_ROOT"
check "I5 a real scaffold with tldr_mode true: key, section at the end of CLAUDE.md, hook + lib shipped, one registration after the bypass detector; the shipped hook blocks and allows; reconfigure turns it off" case_I5 "$REPO_ROOT"
check "I6 a real scaffold without the key: tldr_mode false written, no section, the hook still registered once" case_I6 "$REPO_ROOT"
check "I7 the interactive setup with piped stdin: the question is not asked and takes no line — the fed sequence still reaches Continue, strict, web/standard/typescript — and it is off, said on stderr" case_I7 "$REPO_ROOT"
if command -v expect >/dev/null 2>&1; then
  check "I8 the interactive setup at a terminal (expect, --dry-run): 'y' turns it on; Enter and a stray '1' leave it off" case_I8 "$REPO_ROOT"
else
  skip "I8" "expect is not on PATH, so the question cannot be answered over a real terminal here; I7 and tests/test-bl312-tldr-mode.sh C3/S1 still pin it"
fi

echo
echo "=== MI — the init.sh marked lines are load-bearing ==="
# A mirror of every top-level entry but .git and .claude: init.sh copies from docs/, templates/, scripts/ …
mk_mirror() {
  local e
  mkdir -p "$2" || return 1
  for e in "$1"/* "$1"/.github "$1"/.gitignore; do
    [ -e "$e" ] || continue
    cp -Rp "$e" "$2/" || return 1
  done
}
mutate() {   # mutate FILE MARKER REPLACEMENT — exactly one line, landed by its literal text, still parses
  local f="$1" mark="$2" repl="$3" n=""
  n="$(MARK="$mark" awk 'BEGIN{c=0; m=ENVIRON["MARK"]} length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m {c++} END{print c}' "$f")"
  [ "$n" = "1" ] || { echo "marker '$mark' ends $n line(s) (need 1)"; return 1; }
  MARK="$mark" REPL="$repl" awk '{ m=ENVIRON["MARK"]
      if (length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m) print ENVIRON["REPL"]; else print }' \
    "$f" > "$f.mut" && cat "$f.mut" > "$f" && rm -f "$f.mut"
  command grep -qF -- "$mark" "$f" && { echo "marker still present"; return 1; }
  [ "$(command grep -cxF -- "$repl" "$f")" -ge 1 ] || { echo "replacement did not land"; return 1; }
  bash -n "$f" 2>/dev/null || { echo "mutant does not parse"; return 1; }
}
mutant() {   # mutant ID MARKER REPLACEMENT KILLER WHAT
  local id="$1" mark="$2" repl="$3" killer="$4" what="$5" m why
  m="$(newtmp)/mirror"
  mk_mirror "$REPO_ROOT" "$m" || { fail_ "$id" "could not build a mirror"; return; }
  why="$(mutate "$m/init.sh" "$mark" "$repl")" || { fail_ "$id" "mutant did not land: $why"; return; }
  CASE_DETAIL=""
  if "$killer" "$m"; then fail_ "$id" "$what — SURVIVED: ${killer#case_} still passes ($CASE_DETAIL)"
  else pass "$id (MUTATION) — $what: killed by ${killer#case_}"; fi
}
mutant MI1 '# BL-312-INIT-CONFIG' '      boolean) TLDR_MODE=false ;;' case_I1 "a true tldr_mode in --config is read as false"
mutant MI2 '# BL-312-INIT-CLAUDE-MD' '    :' case_I5 "the CLAUDE.md section is not added at birth"
mutant MI3 '# BL-312-INIT-TTY-ONLY' '  if true; then' case_I7 "the question reads piped stdin"

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
