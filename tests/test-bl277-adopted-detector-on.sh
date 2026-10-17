#!/usr/bin/env bash
# tests/test-bl277-adopted-detector-on.sh
#
# `## BL-277:` residual 5 — THE BYPASS DETECTOR IS ON IN ADOPTED PROJECTS.
#
# PR #454 made scripts/hooks/bypass-detector.sh judge only text the agent
# wrote: its replies (Stop) and the files it writes or edits (PostToolUse on
# Write, Edit, MultiEdit) raise the question; a tool's output is recorded under
# `tool_output` and raises nothing. Adoption had kept the PostToolUse arm off
# "until BL-277 closes" (`# BL-242-SETTINGS-BL277`). Karl ruled on 2026-10-17
# to turn it on: an adopted project gets the detector exactly as a new one.
#
# WHAT EACH CASE OWNS
#   N1  a fresh adoption registers the detector exactly as a new project gets
#       it: the PostToolUse group holding it equals the one the shared roster
#       writes in init.sh's mode (derived from the roster, never a literal),
#       once; its Stop arm once, with init.sh's command; committed.
#   N2  an adoption into a project with its own .claude/settings.json hooks:
#       every hook of theirs stays in its group, matcher unchanged, theirs
#       first and in order; the detector is added once, as in N1.
#   N3  re-running: a second adoption is refused and leaves settings.json
#       byte-identical; the roster run again on the adopted file adds nothing.
#   N3s upgrade-project.sh --sync-framework on an adopted project leaves ONE
#       detector registration.
#   N4  end to end: the adopted project's own settings.json, dispatched as
#       Claude Code dispatches PostToolUse (every group whose matcher matches
#       the tool's name), through the hook command as registered: a Write and
#       an Edit carrying a proposal the agent wrote each write a `claude` row,
#       PENDING, and raise the question; the same text as a Bash result writes
#       a `tool_output` row and raises nothing; a Read result reaches no
#       detector at all.
#   N5  the adoption transcript says the detector is on, and no longer says it
#       waits for BL-277.
#   N6  a settings.json whose PostToolUse the roster cannot extend (a string):
#       the run does not say the hooks are registered.
#   N7  a project adopted before this change (the detector's PostToolUse group
#       absent): the one command docs/adoption.md gives adds it exactly as N1,
#       and run again changes nothing. What --sync-framework does to such a
#       project is MEASURED and printed (INFO), not asserted.
#   M*  mutants, each in a COPY of the framework: location proved by distance
#       from its marker, landing proved by its own text and `bash -n`; one that
#       cannot be applied is a SETUP failure, never a kill. Each names the case
#       that must kill it and a case that must survive it.
#
# WHY NO PATTERN APPEARS LITERALLY IN THIS FILE: as in
# tests/test-bl277-detector-authorship.sh, the proposal is assembled from split
# literals, so the contiguous text exists only at run time.
#
# HERMETIC: temp trees, the real adoption driver with its MCP step off and no
# Guardrails clone (SOIF_ADOPT_GUARDRAILS_DIR names an empty path), the sync
# with CDF_HOME and HOME pointed into the temp tree. No network.
set -uo pipefail
# The adoption driver's MCP step can run `claude mcp add`; off here, as in
# tests/test-brownfield-wp9c-session-layer.sh (`# BL-311-MCP-SEAM`).
export SOIF_ADOPT_MCP=off

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }
_done() { echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; [ "$FAILED" -eq 0 ]; exit $?; }

echo "== BL-277 residual 5 — the bypass detector is on in adopted projects =="
for t in git jq; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; _done; }
done
WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT
newtmp() { mktemp -d "$WORK/fixXXXXXX"; }

DET="bypass-detector.sh"
PROPOSAL="alternatively, use --no-""verify to get past it"

# ── fixtures ────────────────────────────────────────────────────────────────
_base() {   # _base DIR — a small TypeScript project with its own history
  local p="$1"
  mkdir -p "$p/src" "$p/.claude" || return 1
  ( cd "$p" && git init -q . && git config user.email bl277@test.invalid && git config user.name "BL277 Test" ) >/dev/null 2>&1
  printf '{"name":"acme","scripts":{"test":"exit 0"}}\n' > "$p/package.json"
  printf 'export const x = 1;\n' > "$p/src/index.ts"
}
_commit() { ( cd "$1" && git add -- "${@:2}" && git commit -q --no-verify -m "chore: their history" ) >/dev/null 2>&1; }
_adopt() {  # _adopt FW DIR OUT — the real driver of the framework at FW; sets RUN_RC
  local fw="$1" p="$2" out="$3"
  ( cd "$p" && printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n' \
      | env SOIF_ADOPT_QDRANT=no SOIF_ADOPT_GUARDRAILS_DIR="$WORK/no-guardrails" bash "$fw/scripts/adopt-project.sh" ) > "$out" 2>&1
  RUN_RC=$?
}

# _greenfield FW — the settings.json the shared roster writes in init.sh's
# mode, on init.sh's template, in a clean subshell: the reference every
# "exactly as a new project" comparison reads. Prints its path.
_greenfield() {
  local d
  d="$(newtmp)" || return 1
  mkdir -p "$d/.claude" || return 1
  ( cd "$d" && . "$1/scripts/lib/claude-settings.sh" && soif_claude_settings_json typescript > .claude/settings.json \
      && soif_register_hook_roster .claude/settings.json ) >/dev/null 2>&1 || return 1
  printf '%s' "$d/.claude/settings.json"
}
# _det_groups FILE EVENT — the EVENT groups that hold the detector, sorted keys.
_det_groups() { jq -S -c --arg e "$2" --arg d "$DET" '[.hooks[$e][]? | select(any(.hooks[]?; (.command // "") | contains($d)))]' "$1" 2>/dev/null || printf 'ERR'; }
# _det_count FILE EVENT — detector hook entries under EVENT, in any group.
_det_count() { jq -r --arg e "$2" --arg d "$DET" '[.hooks[$e][]? | .hooks[]? | select((.command // "") | contains($d))] | length' "$1" 2>/dev/null || printf 'ERR'; }
# _det_like_new FILE FW — empty when FILE holds the detector exactly as a new
# project of FW does (both events), else the reason.
_det_like_new() {
  local f="$1" g want got
  g="$(_greenfield "$2")" || { printf 'the greenfield roster could not be built'; return; }
  want="$(_det_groups "$g" PostToolUse)"; got="$(_det_groups "$f" PostToolUse)"
  [ "$(_det_count "$g" PostToolUse)" = 1 ] || { printf 'the greenfield roster holds %s PostToolUse detectors — the derivation is broken' "$(_det_count "$g" PostToolUse)"; return; }
  [ "$(_det_count "$f" PostToolUse)" = 1 ] || { printf 'PostToolUse detector entries: %s, want 1' "$(_det_count "$f" PostToolUse)"; return; }
  [ "$got" = "$want" ] || { printf 'the PostToolUse detector group is %s, a new project has %s' "$got" "$want"; return; }
  [ "$(_det_count "$f" Stop)" = 1 ] || { printf 'Stop detector entries: %s, want 1' "$(_det_count "$f" Stop)"; return; }
  want="$(jq -r --arg d "$DET" '[.hooks.Stop[]?.hooks[]? | select((.command // "") | contains($d)) | .command] | first' "$g")"
  got="$(jq -r --arg d "$DET" '[.hooks.Stop[]?.hooks[]? | select((.command // "") | contains($d)) | .command] | first' "$f")"
  [ "$got" = "$want" ] || { printf 'the Stop detector command is %s, a new project has %s' "$got" "$want"; return; }
}

# _plain FW — one plain adoption per framework copy, reused (copied) by the
# cases that need it. Sets PLAIN (the adopted project) and PLAIN_OUT.
_PLAIN_FW=""; PLAIN=""; PLAIN_OUT=""; PLAIN_RC=1
_plain() {
  [ "$_PLAIN_FW" = "$1" ] && return "$PLAIN_RC"
  _PLAIN_FW="$1"; PLAIN="$(newtmp)/plain"; PLAIN_OUT="$PLAIN.out"
  _base "$PLAIN"; _commit "$PLAIN" package.json src/index.ts
  _adopt "$1" "$PLAIN" "$PLAIN_OUT"; PLAIN_RC=$RUN_RC
  return "$PLAIN_RC"
}
_copy_plain() { local d; d="$(newtmp)/p"; cp -Rp "$PLAIN" "$d" && printf '%s' "$d"; }

# ── checks: each takes the framework copy as $1, prints a reason and returns 1
# on failure. The cases call them on the real tree; the mutants call the SAME
# functions on a mutated copy. ────────────────────────────────────────────────
chk_fresh() {
  local why
  _plain "$1" || { echo "adoption rc $PLAIN_RC: $(grep -E 'BLOCKED|REFUSED' "$PLAIN_OUT" | head -1)"; return 1; }
  why="$(_det_like_new "$PLAIN/.claude/settings.json" "$1")"
  [ -z "$why" ] || { echo "$why"; return 1; }
  ( cd "$PLAIN" && git diff --quiet HEAD -- .claude/settings.json ) || { echo "settings.json differs from the commit"; return 1; }
  [ "$(cd "$PLAIN" && git show HEAD:.claude/settings.json | jq -r --arg d "$DET" '[.hooks.PostToolUse[]? | .hooks[]? | select((.command // "") | contains($d))] | length' 2>/dev/null)" = 1 ] \
    || { echo "the committed settings.json does not carry the PostToolUse detector"; return 1; }
  return 0
}

chk_own_hooks() {
  local p why
  p="$(newtmp)/own"; _base "$p"
  printf '%s\n' '{"permissions":{"allow":["Bash(make *)"]},"hooks":{"PostToolUse":[{"hooks":[{"type":"command","command":"echo THEIR-POST-ANY"}]},{"matcher":"Write","hooks":[{"type":"command","command":"echo THEIR-POST-WRITE"}]}],"Stop":[{"hooks":[{"type":"command","command":"echo THEIR-STOP"}]}],"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo THEIR-PRE-BASH"}]}]},"theirKey":1}' > "$p/.claude/settings.json"
  cp "$p/.claude/settings.json" "$p.orig.json"
  _commit "$p" package.json src/index.ts .claude/settings.json
  _adopt "$1" "$p" "$p.out"
  [ "$RUN_RC" -eq 0 ] || { echo "adoption rc $RUN_RC: $(grep -E 'BLOCKED|REFUSED' "$p.out" | head -1)"; return 1; }
  jq -e --slurpfile o "$p.orig.json" '
      . as $n | $o[0].hooks | to_entries | all(.key as $e | .value | to_entries
        | all(.key as $i | .value as $g
              | ($n.hooks[$e][$i].matcher == $g.matcher)
                and ($n.hooks[$e][$i].hooks[0:($g.hooks | length)] == $g.hooks)))' "$p/.claude/settings.json" >/dev/null 2>&1 \
    || { echo "a hook of theirs moved, changed or went: $(jq -c .hooks "$p/.claude/settings.json" 2>/dev/null | cut -c1-300)"; return 1; }
  jq -e '.theirKey == 1 and .permissions.allow[0] == "Bash(make *)"' "$p/.claude/settings.json" >/dev/null 2>&1 || { echo "their key or rule was lost"; return 1; }
  why="$(_det_like_new "$p/.claude/settings.json" "$1")"
  [ -z "$why" ] || { echo "$why"; return 1; }
  return 0
}

chk_rerun() {
  local p added
  _plain "$1" || { echo "adoption rc $PLAIN_RC"; return 1; }
  p="$(_copy_plain)" || { echo "could not copy the adopted project"; return 1; }
  cp "$p/.claude/settings.json" "$p.before.json"
  _adopt "$1" "$p" "$p.again.out"
  [ "$RUN_RC" -ne 0 ] && grep -q 'already been adopted' "$p.again.out" || { echo "a second adoption was not refused as already adopted (rc $RUN_RC)"; return 1; }
  cmp -s "$p.before.json" "$p/.claude/settings.json" || { echo "the refused second adoption changed settings.json"; return 1; }
  added="$( ( . "$1/scripts/lib/claude-settings.sh" >/dev/null 2>&1 && soif_register_hook_roster "$p/.claude/settings.json" >/dev/null 2>&1; printf '%s' "${SOIF_ROSTER_ADDED:-unset}" ) )"
  [ "$added" = false ] || { echo "the roster run again on the adopted file reported added=$added; PostToolUse detectors now $(_det_count "$p/.claude/settings.json" PostToolUse)"; return 1; }
  cmp -s "$p.before.json" "$p/.claude/settings.json" || { echo "the roster run again changed the adopted settings.json"; return 1; }
  return 0
}

# _sync DIR — the framework sync, from the project folder, non-interactive,
# with no Guardrails clone and a HOME of its own. Sets SYNC_RC.
_sync() {
  local h; h="$(newtmp)"
  ( cd "$1" && env HOME="$h" CDF_HOME="$h/no-cdf" SOIF_NONINTERACTIVE=1 bash "$REPO_ROOT/scripts/upgrade-project.sh" --sync-framework ) </dev/null > "$1.sync.out" 2>&1
  SYNC_RC=$?
}
chk_sync() {
  local p
  _plain "$REPO_ROOT" || { echo "adoption rc $PLAIN_RC"; return 1; }
  p="$(_copy_plain)" || { echo "could not copy the adopted project"; return 1; }
  _sync "$p"
  [ "$SYNC_RC" -eq 0 ] || { echo "the sync exited $SYNC_RC: $(grep -E 'FAIL' "$p.sync.out" | head -1)"; return 1; }
  [ "$(_det_count "$p/.claude/settings.json" PostToolUse)" = 1 ] && [ "$(_det_count "$p/.claude/settings.json" Stop)" = 1 ] \
    || { echo "after the sync: PostToolUse detectors $(_det_count "$p/.claude/settings.json" PostToolUse), Stop $(_det_count "$p/.claude/settings.json" Stop), want 1 and 1"; return 1; }
  return 0
}

# _dispatch PROJECT ENVELOPE — Claude Code's PostToolUse routing, for the
# detector: every hook in a PostToolUse group whose matcher is absent, empty or
# "*", or names tool_name (a matcher of letters, digits, `_` and `|` is a list
# of exact names; any other is a regular expression over the whole name), and
# whose command runs the detector, is run as registered (`bash -c` with
# CLAUDE_PROJECT_DIR set), the envelope on stdin. Sets DISPATCHED to how many
# ran.
_matches() {   # _matches MATCHER TOOL
  [ "$1" = "*" ] && return 0
  case "$1" in
    *[!A-Za-z0-9_\|]*) printf '%s' "$2" | grep -qE "^($1)\$"; return ;;
  esac
  case "|$1|" in
    *"|$2|"*) return 0 ;;
  esac
  return 1
}
_dispatch() {
  local p="$1" env="$2" tool="" m="" cmd="" routes=""
  DISPATCHED=0
  tool="$(printf '%s' "$env" | jq -r '.tool_name')"
  routes="$(jq -r '.hooks.PostToolUse[]? | ((.matcher // "") | if . == "" then "*" else . end) as $m | .hooks[]? | "\($m)\t\(.command // "")"' "$p/.claude/settings.json" 2>/dev/null)"
  while IFS="$(printf '\t')" read -r m cmd; do
    case "$cmd" in *"$DET"*) ;; *) continue ;; esac
    _matches "$m" "$tool" || continue
    ( cd "$p" && printf '%s' "$env" | CLAUDE_PROJECT_DIR="$p" bash -c "$cmd" ) >/dev/null 2>&1
    DISPATCHED=$((DISPATCHED + 1))
  done <<EOF
$routes
EOF
}
_rows() { jq -r --arg a "$2" '[.[] | select(.type == "claude_bypass_proposal" and .actor == $a)] | length' "$1/.claude/bypass-audit.json" 2>/dev/null || printf 'ERR'; }
_pending() { jq -r '[.[] | select(.type == "claude_bypass_proposal" and .user_response == "PENDING")] | length' "$1/.claude/bypass-audit.json" 2>/dev/null || printf 'ERR'; }
_env() {   # _env TOOL — a PostToolUse envelope as Claude Code sends it, carrying $PROPOSAL where that tool carries text
  case "$1" in
    Write) jq -nc --arg t "$PROPOSAL" '{session_id:"bl277r5", hook_event_name:"PostToolUse", tool_name:"Write",
             tool_input:{file_path:"NEXT_STEPS.md", content:$t}, tool_response:{type:"create", filePath:"NEXT_STEPS.md"}}' ;;
    Edit)  jq -nc --arg t "$PROPOSAL" '{session_id:"bl277r5", hook_event_name:"PostToolUse", tool_name:"Edit",
             tool_input:{file_path:"NEXT_STEPS.md", old_string:"todo", new_string:$t, replace_all:false},
             tool_response:{filePath:"NEXT_STEPS.md", oldString:"todo", newString:$t, originalFile:"todo\n", structuredPatch:[], userModified:false, replaceAll:false}}' ;;
    Bash)  jq -nc --arg t "$PROPOSAL" '{session_id:"bl277r5", hook_event_name:"PostToolUse", tool_name:"Bash",
             tool_input:{command:"cat NEXT_STEPS.md"}, tool_response:{stdout:$t, stderr:"", interrupted:false, isImage:false, noOutputExpected:false}}' ;;
    Read)  jq -nc --arg t "$PROPOSAL" '{session_id:"bl277r5", hook_event_name:"PostToolUse", tool_name:"Read",
             tool_input:{file_path:"NEXT_STEPS.md"}, tool_response:{type:"text", file:{filePath:"NEXT_STEPS.md", content:$t, numLines:1, startLine:1, totalLines:1}}}' ;;
  esac
}
chk_e2e() {
  local tool p
  _plain "$1" || { echo "adoption rc $PLAIN_RC"; return 1; }
  for tool in Write Edit; do
    p="$(_copy_plain)" || { echo "could not copy the adopted project"; return 1; }
    _dispatch "$p" "$(_env "$tool")"
    [ "$DISPATCHED" = 1 ] || { echo "$tool: $DISPATCHED detector hooks ran, want 1"; return 1; }
    [ "$(_rows "$p" claude)" = 1 ] && [ "$(_pending "$p")" = 1 ] || { echo "$tool: claude rows $(_rows "$p" claude), PENDING $(_pending "$p"), want 1 and 1"; return 1; }
    [ -f "$p/.claude/pending-approval.json" ] || { echo "$tool: no question raised"; return 1; }
  done
  p="$(_copy_plain)" || { echo "could not copy the adopted project"; return 1; }
  _dispatch "$p" "$(_env Bash)"
  [ "$DISPATCHED" = 1 ] || { echo "Bash: $DISPATCHED detector hooks ran, want 1"; return 1; }
  [ "$(_rows "$p" tool_output)" = 1 ] && [ "$(_rows "$p" claude)" = 0 ] || { echo "Bash: tool_output rows $(_rows "$p" tool_output), claude rows $(_rows "$p" claude), want 1 and 0"; return 1; }
  [ ! -e "$p/.claude/pending-approval.json" ] || { echo "Bash: tool output raised a question"; return 1; }
  p="$(_copy_plain)" || { echo "could not copy the adopted project"; return 1; }
  _dispatch "$p" "$(_env Read)"
  [ "$DISPATCHED" = 0 ] && [ "$(_rows "$p" claude)" = 0 ] && [ "$(_rows "$p" tool_output)" = 0 ] && [ ! -e "$p/.claude/pending-approval.json" ] \
    || { echo "Read: $DISPATCHED detector hooks ran, claude rows $(_rows "$p" claude), tool_output rows $(_rows "$p" tool_output), want none"; return 1; }
  return 0
}

chk_transcript() {
  _plain "$1" || { echo "adoption rc $PLAIN_RC"; return 1; }
  grep -qF "The bypass detector runs on both of its" "$PLAIN_OUT" || { echo "the transcript does not say the detector is on: $(grep -i 'bypass detector' "$PLAIN_OUT" | head -2 | tr '\n' ' ')"; return 1; }
  ! grep -qF "until BL-277 closes" "$PLAIN_OUT" || { echo "the transcript still says the detector waits for BL-277"; return 1; }
  return 0
}

chk_unregistrable() {
  local p
  p="$(newtmp)/str"; _base "$p"
  printf '%s\n' '{"hooks":{"PostToolUse":"not-a-list"}}' > "$p/.claude/settings.json"
  _commit "$p" package.json src/index.ts .claude/settings.json
  _adopt "$1" "$p" "$p.out"
  [ "$RUN_RC" -eq 0 ] || { echo "adoption rc $RUN_RC: $(grep -E 'BLOCKED|REFUSED' "$p.out" | head -1)"; return 1; }
  [ "$(_det_count "$p/.claude/settings.json" PostToolUse)" = 0 ] || { echo "the fixture took the detector after all — it no longer exercises the receipt"; return 1; }
  ! grep -qF "Registered the framework's session hooks" "$p.out" || { echo "the run says the hooks are registered, and the detector is not"; return 1; }
  grep -qF "were NOT all registered" "$p.out" || { echo "the run does not say the hooks were not all registered: $(grep -i 'session hooks' "$p.out" | head -2 | tr '\n' ' ')"; return 1; }
  return 0
}

# The command docs/adoption.md gives for a project adopted before this change,
# read from the document, never restated here.
BACKFILL_CMD=""
_backfill_cmd() {
  local n
  n="$(grep -cF "soif_register_hook_roster .claude/settings.json'" "$REPO_ROOT/docs/adoption.md")"
  [ "$n" = 1 ] || return 1
  BACKFILL_CMD="$(grep -F "soif_register_hook_roster .claude/settings.json'" "$REPO_ROOT/docs/adoption.md" | sed 's/^[[:space:]]*//')"
  case "$BACKFILL_CMD" in "bash -c '. ~/solo-orchestrator/scripts/lib/claude-settings.sh && "*) return 0 ;; *) return 1 ;; esac
}
chk_backfill() {
  local p h before after why
  _backfill_cmd || { echo "docs/adoption.md does not give exactly one backfill command of the expected shape (found: '${BACKFILL_CMD:-none}')"; return 1; }
  _plain "$REPO_ROOT" || { echo "adoption rc $PLAIN_RC"; return 1; }
  p="$(_copy_plain)" || { echo "could not copy the adopted project"; return 1; }
  jq --arg d "$DET" '.hooks.PostToolUse |= map(select(any(.hooks[]?; (.command // "") | contains($d)) | not))' "$p/.claude/settings.json" > "$p.old.json" \
    && mv "$p.old.json" "$p/.claude/settings.json" || { echo "could not make the pre-change fixture"; return 1; }
  [ "$(_det_count "$p/.claude/settings.json" PostToolUse)" = 0 ] || { echo "the pre-change fixture still holds the detector"; return 1; }
  before="$(_det_count "$p/.claude/settings.json" PostToolUse)"
  _sync "$p"; after="$(_det_count "$p/.claude/settings.json" PostToolUse)"
  echo "  [INFO] measured: --sync-framework on a project adopted without the PostToolUse detector (rc $SYNC_RC): PostToolUse detector entries $before -> $after" >&2
  h="$(newtmp)"; ln -s "$REPO_ROOT" "$h/solo-orchestrator" || { echo "could not link the framework into a temp HOME"; return 1; }
  ( cd "$p" && HOME="$h" bash -c "$BACKFILL_CMD" ) >/dev/null 2>&1 || { echo "the documented command failed"; return 1; }
  why="$(_det_like_new "$p/.claude/settings.json" "$REPO_ROOT")"
  [ -z "$why" ] || { echo "after the documented command: $why"; return 1; }
  cp "$p/.claude/settings.json" "$p.once.json"
  ( cd "$p" && HOME="$h" bash -c "$BACKFILL_CMD" ) >/dev/null 2>&1 || { echo "the documented command failed the second time"; return 1; }
  cmp -s "$p.once.json" "$p/.claude/settings.json" || { echo "the documented command run again changed settings.json"; return 1; }
  return 0
}

# ── cases ───────────────────────────────────────────────────────────────────
echo "=== N — the adopted project's session layer ==="
# One plain adoption, made here in the main shell so every case below (each
# runs in a command substitution) reuses it instead of adopting again.
_plain "$REPO_ROOT"
if why="$(chk_fresh "$REPO_ROOT")"; then pass "N1 a fresh adoption registers the detector exactly as a new project gets it: the same PostToolUse group, once; the Stop arm once; committed"
else fail_ "N1" "$why"; fi
if why="$(chk_own_hooks "$REPO_ROOT")"; then pass "N2 an adoption into a project with its own hooks keeps every one of them in place and adds the detector once"
else fail_ "N2" "$why"; fi
if why="$(chk_rerun "$REPO_ROOT")"; then pass "N3 a second adoption is refused and changes nothing; the roster run again on the adopted file adds nothing"
else fail_ "N3" "$why"; fi
if why="$(chk_sync "$REPO_ROOT")"; then pass "N3s --sync-framework on an adopted project leaves one detector registration on each arm"
else fail_ "N3s" "$why"; fi
if why="$(chk_e2e "$REPO_ROOT")"; then pass "N4 end to end through the adopted settings: Write and Edit proposals raise a claude row and the question; Bash output records tool_output and raises nothing; Read reaches no detector"
else fail_ "N4" "$why"; fi
if why="$(chk_transcript "$REPO_ROOT")"; then pass "N5 the adoption transcript says the detector is on and no longer waits for BL-277"
else fail_ "N5" "$why"; fi
if why="$(chk_unregistrable "$REPO_ROOT")"; then pass "N6 a PostToolUse the roster cannot extend: the run does not say the hooks are registered"
else fail_ "N6" "$why"; fi
if why="$(chk_backfill "$REPO_ROOT")"; then pass "N7 a project adopted before this change: the command docs/adoption.md gives adds the detector as N1, and again changes nothing"
else fail_ "N7" "$why"; fi

# ── mutants ─────────────────────────────────────────────────────────────────
echo "=== M — mutants ==="
_mirror() { local m; m="$(newtmp)/fw"; mkdir -p "$m" && cp -Rp "$REPO_ROOT/scripts" "$REPO_ROOT/templates" "$REPO_ROOT/docs" "$m/" && cp -p "$REPO_ROOT/init.sh" "$m/" && printf '%s' "$m"; }
count_lit() { S="$2" awk 'index($0, ENVIRON["S"]){c++} END{print c+0}' "$1"; }
lines_lit() { S="$2" awk 'index($0, ENVIRON["S"]){print NR}' "$1"; }
# mutate FILE MARKER OPERATIVE REPLACEMENT MAX-DISTANCE — as in
# tests/test-bl277-detector-authorship.sh, except that the operative may sit ON
# the marker's line (distance 0): the operative text occurs exactly once, within
# MAX-DISTANCE lines after the marker; afterwards it is gone, the replacement is
# on that line and once more than before, one line changed, and the file parses.
# Text reaches awk through ENVIRON, never -v (which applies backslash escapes).
mutate() {
  local f="$1" marker="$2" op="$3" rep="$4" maxd="$5" ml="" ol="" n_op="" nb="" na="" removed="" added="" landed="" before=""
  ml="$(lines_lit "$f" "$marker" | head -1)"
  [ -n "$ml" ] || { echo "marker '$marker' not found"; return 1; }
  n_op="$(count_lit "$f" "$op")"
  [ "$n_op" = 1 ] || { echo "operative text occurs $n_op times, want exactly 1"; return 1; }
  ol="$(lines_lit "$f" "$op")"
  [ "$ol" -ge "$ml" ] && [ $((ol - ml)) -le "$maxd" ] || { echo "operative line is $((ol - ml)) lines from the marker, want 0..$maxd"; return 1; }
  nb="$(count_lit "$f" "$rep")"
  before="$f.before"; cp "$f" "$before" || { echo "could not snapshot"; return 1; }
  OP="$op" REP="$rep" awk '{ i = index($0, ENVIRON["OP"]); if (i) print substr($0, 1, i - 1) ENVIRON["REP"] substr($0, i + length(ENVIRON["OP"])); else print }' "$before" > "$f" || { echo "awk failed"; return 1; }
  n_op="$(count_lit "$f" "$op")"; na="$(count_lit "$f" "$rep")"
  landed="$(sed -n "${ol}p" "$f" | S="$rep" awk 'index($0, ENVIRON["S"]){print "yes"}')"
  removed="$(diff "$before" "$f" | grep -c '^<')"; added="$(diff "$before" "$f" | grep -c '^>')"
  [ "$n_op" = 0 ] && [ "$na" = "$((nb + 1))" ] && [ "$landed" = yes ] && [ "$removed" = 1 ] && [ "$added" = 1 ] \
    || { echo "did not land cleanly (operative left=$n_op, replacement $nb->$na, on the line=${landed:-no}, removed=$removed, added=$added)"; return 1; }
  bash -n "$f" 2>/dev/null || { echo "the mutated file does not parse"; return 1; }
  return 0
}
# judge ID WHAT REL MARKER OPERATIVE REPLACEMENT MAX KILLER SURVIVOR — mutate a
# copy, then KILLER must fail on it and SURVIVOR must pass, so the kill is the
# killer's and not a broken framework's.
judge() {
  local id="$1" what="$2" rel="$3" marker="$4" op="$5" rep="$6" maxd="$7" killer="$8" survivor="$9" m why
  m="$(_mirror)" || { fail_ "$id setup" "could not copy the framework"; return; }
  why="$(mutate "$m/$rel" "$marker" "$op" "$rep" "$maxd")" || { fail_ "$id setup" "$why"; return; }
  if "$killer" "$m" >/dev/null 2>&1; then fail_ "$id (MUTATION)" "$what survived $killer"
  elif ! "$survivor" "$m" >/dev/null 2>&1; then fail_ "$id (MUTATION)" "$what broke $survivor too, so the kill proves nothing about $killer"
  else pass "$id (MUTATION) — $what: $killer kills it, $survivor survives"; fi
}
# chk_greenfield FW — the survivor for a roster mutant aimed at adoption: a new
# project's roster still registers the detector, once, under a matcher.
chk_greenfield() {
  local g; g="$(_greenfield "$1")" || return 1
  [ "$(_det_count "$g" PostToolUse)" = 1 ] && [ "$(jq -r --arg d "$DET" '[.hooks.PostToolUse[]? | select(any(.hooks[]?; (.command // "") | contains($d))) | .matcher // ""] | first' "$g")" != "" ]
}

CS="scripts/lib/claude-settings.sh"; AS="scripts/lib/adopt/adopt-session.sh"
PROBE='if ! jq -e '"'"'.hooks.PostToolUse[]? | .hooks[]? | select(.command | contains("bypass-detector.sh"))'"'"' "$_f" >/dev/null 2>&1; then'
# M1 — the adoption guard back: the roster skips the detector's PostToolUse arm
# when an adoption runs it (keyed on the driver's own variable, since adoption
# no longer passes a mode).
judge M1 "the PostToolUse arm skipped in an adoption" "$CS" "# BL-242-SETTINGS-BL277" "$PROBE" \
  'if [ -z "${ADOPT_FRAMEWORK_ROOT:-}" ] && ! jq -e '"'"'.hooks.PostToolUse[]? | .hooks[]? | select(.command | contains("bypass-detector.sh"))'"'"' "$_f" >/dev/null 2>&1; then' \
  12 chk_fresh chk_greenfield
# M2 — the receipt no longer asks for the detector: "registered" is said with
# the detector absent.
judge M2 "the receipt without its detector half" "$AS" "# BL-242-SESSION-ROSTER-RECEIPT" \
  ' and ([.hooks.PostToolUse[]?.hooks[]?.command] | any(test("bypass-detector.sh")))' ' and true' 0 chk_unregistrable chk_transcript
# M3 — the transcript says the old thing.
judge M3 "the transcript's old sentence" "$AS" "# BL-277-ADOPTED-ON" \
  "Registered the framework's session hooks. The bypass detector runs on both of its" \
  "Registered the framework's session hooks. The bypass detector's per-tool arm is" 3 chk_transcript chk_fresh
# M4 — the matcher narrowed to Bash: N1 compares adoption with the same
# roster's greenfield, so parity holds and only the end-to-end case can see it.
judge M4 "the matcher narrowed to Bash" "$CS" "# BL-277-MATCHER" '"matcher": "Bash|Write|Edit|MultiEdit"' '"matcher": "Bash"' 8 chk_e2e chk_fresh
# M5 — the idempotence probe regressed to group [0]: the adopted detector sits
# in a later group, so a second roster run adds it again.
judge M5 "the idempotence probe regressed to group [0]" "$CS" "# BL-242-SETTINGS-BL277" \
  '.hooks.PostToolUse[]? | .hooks[]? | select(.command | contains("bypass-detector.sh"))' \
  '.hooks.PostToolUse[0].hooks[]? | select(.command | contains("bypass-detector.sh"))' 12 chk_rerun chk_fresh

_done
