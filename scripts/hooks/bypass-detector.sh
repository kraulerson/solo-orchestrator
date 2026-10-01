#!/usr/bin/env bash
# scripts/hooks/bypass-detector.sh — BL-029 bypass-shape detector.
#
# Wires into Claude Code's PostToolUse and Stop hooks. Reads the JSON
# envelope from stdin (per https://code.claude.com/docs/en/hooks),
# extracts the relevant text (tool_response.{stdout,stderr,output,content}
# for PostToolUse; last_assistant_message for Stop), scans against
# bypass-patterns.sh, and writes a claude_bypass_proposal row to
# bypass-audit.json on match. Stop passes with .stop_hook_active == true
# are skipped to avoid re-entrant double-scanning.
#
# No-op conditions:
#   - .claude/ doesn't exist
#   - jq isn't installed
#   - envelope can't be parsed
#   - text contains no bypass-shaped language
#
# The hook is silent on the no-op paths. The audit-log writer (lib) is
# the framework's voice for matches; this script does not print anything
# to stdout (which would inject text into Claude's view).

set -uo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "")}"
[ -z "$PROJECT_ROOT" ] && exit 0
[ ! -d "$PROJECT_ROOT/.claude" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Locate libraries: prefer project's own scripts/lib/ (post-init layout),
# fall back to framework repo's scripts/lib/ (running on the framework itself).
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$HOOK_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPTS_DIR/lib/bypass-patterns.sh"
# shellcheck disable=SC1091
source "$SCRIPTS_DIR/lib/bypass-audit.sh"

# ── BL-311 row 3: A RELAYED FRAMEWORK ESCAPE IS NOT A BYPASS PROPOSAL ─────────
#
# The framework's checks print their own escapes. session-mcp-gate.sh's deny
# text says "EXIT and restart the session with the attestation exported:
# SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON='<why>' claude". An agent that relays that
# to the person it works for — the right move, since it cannot restart its own
# session — writes "run `…` in a new terminal", terminal_workaround matches, and
# the operator is asked to approve a "bypass proposal" with "decline"
# recommended: the check's sanctioned route, reported as a workaround of that
# same check (dogfood run 1, finding 13). The assessment prompt's step 10
# (# BL-311-ASSESSMENT-AUTO-MODE) has the same shape: it tells the agent to hand
# the finisher to the human, typed after `!` at the Claude Code prompt, which
# Claude Code's documentation calls "shell mode" — so a relay that names the
# route by that name matches too.
#
# So, on the Stop arm only, a terminal_workaround match whose every matching
# line RELAYS one of these is written as a `relayed_framework_escape` row: the
# record is kept, and no pending-approval sentinel is raised for it. A line
# relays when it is one of two kinds, each defined narrowly:
#
#   1. AN ATTESTED ESCAPE AS ITS CHECK DOCUMENTS IT (_soif_relay_escape_line).
#      An inline code span that is exactly a row of the table below — the
#      attested variable set to 1, then its reason variable set to a non-empty
#      value, then nothing or the documented command (`claude` with no
#      arguments for the MCP escape; the other commands' arguments carry no
#      shell control operator) — inside a relay phrase: a verb right before the
#      span, "in/from/on/at/… <up to four words> terminal|shell" right after it.
#   2. THE DOCUMENTED HAND-TO-HUMAN STEP (_soif_relay_handoff_line). A line that
#      names `!` and the Claude Code prompt, whose only terminal/shell words are
#      Claude Code's name for that route ("shell mode", "shell command(s)"), and
#      whose only inline code is `!` or a command exactly as this project's own
#      .claude/adoption/assessment-prompt.md prints it (a line that begins
#      `bash `: the finisher). The command is read from the prompt file,
#      not written here: core may not name the adoption module
#      (lint-module-dependencies.sh), and the prompt is what the agent was given.
#      It is also a file the session can write, so editing it would widen what
#      passes; recorded on `## BL-311:`.
#
# THE THREAT: AN AGENT QUOTING A SANCTIONED ESCAPE AS COVER for a real proposal
# in the same message. That is why the exemption is per pattern and per line,
# never per message: only terminal_workaround can be exempt — every other
# pattern names a bypass mechanism (--no-verify, SOIF_FORCE_STEP=, a force push,
# marking a step complete) that no documented escape contains, so it raises
# whatever else the message says; EVERY line terminal_workaround matches must
# qualify, or the pattern raises; and on a qualifying line nothing may ride
# along — no other environment assignment (an invented variable, an attested
# variable without its reason, an unregistered SOLO_*_ATTESTED), no option-like
# token outside the escape, no second terminal route once the relay phrase is
# cut out, and no other inline code introduced by run/do/execute earlier in the
# same sentence. tests/test-bl311-d-relayed-escape.sh pins each condition.
#
# LIMITS. Every condition fails CLOSED: a line that misses one raises the
# sentinel exactly as before. Not separated, and recorded on `## BL-311:`: a
# proposal in plain words (no code, no flag, no variable) that shares the relay
# phrase's own terminal word; an escape relayed in a fenced block (fences are
# stripped before the scan, so the lead-in line carries no escape and raises).
# The PostToolUse arm is untouched: `## BL-277:` owns it.
#
# THE ESCAPE TABLE is the single source of truth. One row per exempt escape:
# attested variable | reason variable | documented command | "args" when that
# command may take arguments. Every SOLO_*_ATTESTED variable that a script,
# init.sh or a template reads is either a row here or a name in
# SOIF_RELAY_NOT_EXEMPT, with the reason; the suite's R1 fails otherwise, so a
# check cannot add an escape without someone deciding which list it joins.
# BL-311-RELAY-ESCAPES-BEGIN
SOIF_RELAY_ESCAPES=(
  # session-mcp-gate.sh's deny text; reason mandatory; recorded to process-state.json::mcp_attestations[] (or .claude/mcp-attestations.jsonl), refused if neither can be written.
  'SOLO_MCP_ATTESTED|SOLO_MCP_REASON|claude|'
  # check-phase-gate.sh's accumulation FAIL; reason mandatory; recorded to process-state.json, refused if it cannot be.
  'SOLO_MCP_ACCUM_ATTESTED|SOLO_MCP_ACCUM_ATTESTED_REASON|bash scripts/check-phase-gate.sh|args'
  # pre-commit-gate.sh's BL-072 FAIL block; recorded to process-state.json::tdd_attestations[], refused if it cannot be.
  'SOLO_TDD_ATTESTED|SOLO_TDD_REASON|git commit|args'
  # check-phase-gate.sh's Phase 3→4 review FAIL; reason mandatory; recorded to process-state.json::phase3.attestations.reviewers.
  'SOLO_REVIEWERS_ATTESTED|SOLO_REVIEWERS_ATTESTED_REASON|bash scripts/check-phase-gate.sh|args'
  # check-pr-review.sh's refusal; reason mandatory; recorded to process-state.json::pr_review_attestations[], refused if it cannot be.
  'SOLO_PR_REVIEW_ATTESTED|SOLO_PR_REVIEW_ATTESTED_REASON|git push|args'
  # process-checklist.sh's results_received hint; recorded to process-state.json::uat_session.solo_attestations[], refused if it cannot be.
  'SOLO_UAT_SOLO_ATTESTED|SOLO_UAT_REASON|bash scripts/process-checklist.sh|args'
  # run-phase3-validation.sh's license deny (docs/security-scan-guide.md); recorded to phase3.license_exceptions[], FAIL if it cannot be.
  'SOLO_LICENSE_ATTESTED|SOLO_LICENSE_REASON|bash scripts/run-phase3-validation.sh|args'
)
SOIF_RELAY_NOT_EXEMPT=(
  # check-gate.sh --repair: no reason variable, and the check's own hint names the flag --branch-protection-attested, not this variable.
  'SOLO_BP_ATTESTED'
  # init.sh exports it from --approvals-attested for the GitLab driver: no reason variable, and no check prints it as a way past a block.
  'SOLO_APPROVALS_ATTESTED'
)
# BL-311-RELAY-ESCAPES-END

# The first matched pattern that IS a proposal; set by the row loop below.
RAISE_PATTERN=""

# _soif_relay_strip TEXT LITERAL — TEXT with every occurrence of LITERAL removed.
# Split on the literal rather than ${var//pat/rep}: no pattern characters, and no
# replacement text for bash 5.2's `&` rule to reinterpret.
_soif_relay_strip() {
  local t="$1" lit="$2" out=""
  while :; do
    case "$t" in
      *"$lit"*) out="$out${t%%"$lit"*}"; t="${t#*"$lit"}" ;;
      *) break ;;
    esac
  done
  printf '%s' "$out$t"
}

# _soif_relay_span_ere ATT REASON CMD ARGS — the ERE for one escape's inline code span.
_soif_relay_span_ere() {
  local att="$1" reason="$2" cmd="$3" args="$4" bt='`' val="" tail=""
  # BL-311-RELAY-REASON-VALUE — non-empty: single- or double-quoted, or one bare word.
  val="('[^'${bt}]+'|\"[^\"${bt}]+\"|[^[:space:]'\"${bt}]+)"
  cmd="${cmd//./[.]}"
  cmd="${cmd// /[[:space:]]+}"
  # BL-311-RELAY-ARGS — where the command takes arguments, none is a shell control operator.
  [ "$args" = "args" ] && tail="([[:space:]]+[^;&|<>\$\\${bt}]*)?"
  # BL-311-RELAY-REASON-REQUIRED — the attested variable AND its reason variable, in the documented order.
  printf '%s' "${bt}${att}=1[[:space:]]+${reason}=${val}([[:space:]]+${cmd}${tail})?[[:space:]]*${bt}"
}

# _soif_relay_escape_line LINE TW — rc 0, with the relayed variable names on
# stdout, iff LINE relays a registered escape (kind 1 above) and nothing else on
# it could be a proposal. TW is the live terminal_workaround regex. Each valid
# span is replaced by a printable token before the phrase checks (a control
# byte is not safe: bash uses \001 internally and drops it from =~ patterns),
# so a line that already carries the token is refused rather than trusted.
_soif_relay_escape_line() {
  local line="$1" tw="$2" tok='@@soif-relay@@' bt='`' rest="" low="" found="" row="" att="" reason="" cmd="" args="" ere="" m=""
  local env_ere="" opt_ere="" prefix_ere="" phrase_ere=""
  low=$(printf '%s' "$line" | LC_ALL=C tr 'A-Z' 'a-z')
  # BL-311-RELAY-TOKEN-FORGE — a token the line already carries was not put there by this function.
  case "$low" in *"$tok"*) return 1 ;; esac
  rest="$line"
  for row in "${SOIF_RELAY_ESCAPES[@]}"; do
    IFS='|' read -r att reason cmd args <<EOF
$row
EOF
    ere=$(_soif_relay_span_ere "$att" "$reason" "$cmd" "$args")
    while [[ $rest =~ $ere ]]; do
      m="${BASH_REMATCH[0]}"
      rest="${rest%%"$m"*}${tok}${rest#*"$m"}"
      case " $found " in *" $att "*) ;; *) found="${found:+$found }$att" ;; esac
    done
  done
  [ -n "$found" ] || return 1
  # BL-311-RELAY-NO-OTHER-ENV — no assignment survives outside the registered spans.
  env_ere="(^|[[:space:]${bt}\"'(])[A-Za-z_][A-Za-z0-9_]*="
  [[ $rest =~ $env_ere ]] && return 1
  # BL-311-RELAY-NO-FLAGS — no option-like token outside them either.
  opt_ere="(^|[[:space:](])--?[A-Za-z]"
  [[ $rest =~ $opt_ere ]] && return 1
  low=$(printf '%s' "$rest" | LC_ALL=C tr 'A-Z' 'a-z')
  # BL-311-RELAY-PREFIX — no run/do/execute earlier in the sentence introduces other inline code.
  prefix_ere="(^|[^a-z])(run|do|execute)[[:space:]][^.]*${bt}[^${bt}]*${bt}[^.]*${tok}"
  [[ $low =~ $prefix_ere ]] && return 1
  # BL-311-RELAY-PHRASE — a verb right before the span, the place right after it;
  # each such phrase is cut out, leaving a sentence break.
  phrase_ere="(^|[^a-z])(re-?run|run|execute|launch|start|type|paste|enter|use|with)[[:space:]]+${tok}[[:space:],]+(in|from|on|at|inside|within|using|via|through)[[:space:]]+([a-z][a-z'-]*[[:space:]]+){0,4}(terminal|shell)([^a-z0-9_]|$)"
  while [[ $low =~ $phrase_ere ]]; do
    m="${BASH_REMATCH[0]}"
    low="${low%%"$m"*}${BASH_REMATCH[1]}.${BASH_REMATCH[6]}${low#*"$m"}"
  done
  # BL-311-RELAY-REMAINDER — with each relay phrase cut out, no terminal route is left.
  printf '%s\n' "$low" | grep -qiE -e "$tw" && return 1
  printf '%s' "$found"
}

# _soif_relay_handoff_line LINE — rc 0 iff LINE relays the documented
# hand-to-human step (kind 2 above) and nothing else on it could be a proposal.
_soif_relay_handoff_line() {
  local line="$1" bt='`' rest="" low="" cmd="" m="" pl=""
  local bang_ere="" prompt_ere="" env_ere="" opt_ere="" mode_ere=""
  local prompt_file="${PROJECT_ROOT:-}/.claude/adoption/assessment-prompt.md"
  low=$(printf '%s' "$line" | LC_ALL=C tr 'A-Z' 'a-z')
  # BL-311-HANDOFF-BANG — it names Claude Code's `!` prefix and the Claude Code prompt.
  bang_ere="(^|[[:space:](${bt}\"'])!([[:space:])${bt}\"',.:]|$)"
  prompt_ere="claude code[^[:space:]]* prompt"
  [[ $low =~ $bang_ere ]] || return 1
  [[ $low =~ $prompt_ere ]] || return 1
  rest="$line"
  # BL-311-HANDOFF-COMMAND-FROM-PROMPT — the commands this project's assessment
  # prompt prints, verbatim: its lines that begin `bash ` once trimmed.
  if [ -f "$prompt_file" ]; then
    while IFS= read -r pl || [ -n "$pl" ]; do
      cmd="${pl#"${pl%%[![:space:]]*}"}"
      cmd="${cmd%"${cmd##*[![:space:]]}"}"
      case "$cmd" in "bash "*) ;; *) continue ;; esac
      rest=$(_soif_relay_strip "$rest" "${bt}! ${cmd}${bt}")
      rest=$(_soif_relay_strip "$rest" "${bt}${cmd}${bt}")
    done < "$prompt_file"
  fi
  rest=$(_soif_relay_strip "$rest" "${bt}!${bt}")
  # BL-311-HANDOFF-COMMAND-VERBATIM — no other inline code, no variable, no flag.
  case "$rest" in *"$bt"*) return 1 ;; esac
  env_ere="(^|[[:space:]\"'(])[A-Za-z_][A-Za-z0-9_]*="
  [[ $rest =~ $env_ere ]] && return 1
  opt_ere="(^|[[:space:](])--?[A-Za-z]"
  [[ $rest =~ $opt_ere ]] && return 1
  low=$(printf '%s' "$rest" | LC_ALL=C tr 'A-Z' 'a-z')
  # BL-311-HANDOFF-MODE-NAME — Claude Code's own name for the `!` route.
  mode_ere="shell[[:space:]]+(mode|commands?)"
  while [[ $low =~ $mode_ere ]]; do
    m="${BASH_REMATCH[0]}"
    low="${low%%"$m"*} ${low#*"$m"}"
  done
  # BL-311-HANDOFF-ONLY-SHELL-MODE — no terminal, and no shell but that route's own name.
  case "$low" in *terminal*|*shell*) return 1 ;; esac
  return 0
}

# soif_relayed_escape PATTERN TEXT — rc 0, with what was relayed on stdout (the
# attested variable names, and/or "shell_mode"), iff PATTERN is terminal_workaround
# and EVERY line of TEXT it matches is a relay. Anything else, a failure included,
# is rc 1, and the caller treats the match as a proposal, as before.
soif_relayed_escape() {
  local pattern="$1" text="$2" tw="" matches="" line="" k="" w="" kinds=""
  # BL-311-RELAY-PATTERN-ONLY — every other pattern names a bypass no documented escape contains.
  [ "$pattern" = "terminal_workaround" ] || return 1
  tw=$(pattern_regex_for terminal_workaround) || return 1
  [ -n "$tw" ] || return 1
  matches=$(printf '%s\n' "$text" | grep -iE -e "$tw") || return 1
  while IFS= read -r line; do
    if k=$(_soif_relay_escape_line "$line" "$tw"); then
      :
    elif _soif_relay_handoff_line "$line"; then
      k="shell_mode"
    else
      return 1   # BL-311-RELAY-EVERY-LINE — one line that is not a relay and the pattern raises.
    fi
    for w in $k; do
      case " $kinds " in *" $w "*) ;; *) kinds="${kinds:+$kinds }$w" ;; esac
    done
  done <<EOF
$matches
EOF
  [ -n "$kinds" ] || return 1
  printf '%s' "$kinds"
}

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null)

# Re-entrancy guard: when a Stop hook itself triggers further model
# activity (e.g. blocking with a follow-up), Claude Code re-invokes the
# Stop hook with .stop_hook_active == true. Skip those passes so we
# don't double-scan the same assistant turn and emit duplicate audit
# rows / pending-approval sentinels.
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$STOP_HOOK_ACTIVE" = "true" ] && exit 0

# Extract scannable text by event type.
TEXT=""
case "$EVENT" in
  PostToolUse)
    # Claude Code envelope: .tool_response. For Bash, .stdout/.stderr/.exit_code/.interrupted;
    # for Read/Edit/Write, .output or .content (or a string). Cover all
    # known shapes; missing field returns "" and the next guard exits.
    TEXT=$(echo "$INPUT" | jq -r '.tool_response.stdout // .tool_response.stderr // .tool_response.output // .tool_response.content // ""' 2>/dev/null)
    ;;
  Stop)
    # Claude Code Stop envelope: .last_assistant_message (Claude's final
    # turn) and .transcript_path (path to session JSONL, optional). We
    # scan the inline message — the file is only consulted as a fallback.
    TEXT=$(echo "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null)
    if [ -z "$TEXT" ]; then
      TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)
      if [ -n "$TRANSCRIPT_PATH" ] && [ -r "$TRANSCRIPT_PATH" ]; then
        TEXT=$(tail -n 50 "$TRANSCRIPT_PATH" 2>/dev/null \
          | jq -r 'select(.role=="assistant" or .type=="assistant") | (.content // .message.content // "")' 2>/dev/null \
          | tail -n 5)
      fi
    fi
    ;;
  *)
    # Unknown event — skip (defense against schema changes).
    exit 0
    ;;
esac

[ -z "$TEXT" ] && exit 0

# BL-029.1 fix S3 (2026-05-04): strip fenced code blocks before scanning.
# Documentation / CHANGELOG / docstring text wrapping a bypass pattern in
# ```...``` is descriptive, not advisory — earlier behavior false-positived
# on changelog entries that named the patterns. Inline backtick code
# (`--no-verify`) is preserved because Claude typesets active proposals
# with inline backticks too. This handles the common doc-FP class without
# suppressing legitimate proposals.
TEXT=$(printf '%s\n' "$TEXT" | awk '
  BEGIN { in_fence = 0 }
  /^[[:space:]]*```/ { in_fence = !in_fence; next }
  !in_fence { print }
')

[ -z "$TEXT" ] && exit 0

# BL-029 + 2026-04-29 calibration fix S1: scan for ALL matched patterns
# and emit one audit row per match. Without this, an earlier-table
# normal-severity pattern silently masked refuse_to_recommend severity
# rows for higher-impact bypasses appearing later in the same proposal.
PATTERNS=$(scan_bypass_patterns_all "$TEXT" || true)
[ -z "$PATTERNS" ] && exit 0

# Build the rows.
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Audit fix code-hooks-bypass-detector-3 (2026-06-28): the Claude Code
# hook envelope carries .session_id as a documented top-level field;
# CLAUDE_SESSION_ID is NOT exported by Claude Code, so the previous
# env-only read landed every row with session_id="unknown" and broke
# the W7 successor-handoff correlation. Read the envelope first; fall
# back to $CLAUDE_SESSION_ID (belt-and-suspenders for unexpected
# envelope shapes), then to "unknown".
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
LEVEL=$(jq -r '.enforcement_level // "strict"' "$PROJECT_ROOT/.claude/manifest.json" 2>/dev/null)
FIRST_PATTERN=""

while IFS= read -r PATTERN; do
  [ -z "$PATTERN" ] && continue
  [ -z "$FIRST_PATTERN" ] && FIRST_PATTERN="$PATTERN"

  # Refuse-to-recommend severity for fake-loop class patterns. Per agent-5
  # spec: framework should not rely on Claude's good taste alone.
  SEVERITY="normal"
  case "$PATTERN" in
    fake_loop|manual_step_complete) SEVERITY="refuse_to_recommend" ;;
  esac

  # Look up the original regex for excerpt extraction (per BL-029 plan
  # amendment — using the pattern name as a regex via tr was broken).
  REGEX=$(pattern_regex_for "$PATTERN" 2>/dev/null || echo "$PATTERN")

  # Trim excerpt to the line containing the match.
  EXCERPT=$(echo "$TEXT" | grep -iE -e "$REGEX" 2>/dev/null | head -1 | head -c 500)

  ROW=$(jq -nc \
    --arg ts "$TS" \
    --arg sid "$SESSION_ID" \
    --arg lvl "$LEVEL" \
    --arg pat "$PATTERN" \
    --arg evt "$EVENT" \
    --arg ex "$EXCERPT" \
    --arg sev "$SEVERITY" \
    '{
      timestamp: $ts,
      session_id: $sid,
      type: "claude_bypass_proposal",
      actor: "claude",
      enforcement_level_at_event: $lvl,
      details: {pattern: $pat, event: $evt, excerpt: $ex, severity: $sev},
      user_response: "PENDING",
      final_outcome: "recorded_only"
    }')

  # BL-311-RELAYED-ESCAPE-ROW — a relay of a check's own escape is recorded as
  # what it is: no decision is awaited, and it raises nothing. Stop arm only
  # (the PostToolUse arm is `## BL-277:`'s). A failed rewrite keeps the
  # proposal row, and the pattern raises the sentinel as before.
  RELAYED=""
  RELAY_ROW=""
  if [ "$EVENT" = "Stop" ]; then   # BL-311-RELAY-STOP-ONLY
    RELAYED=$(export LC_ALL=C; soif_relayed_escape "$PATTERN" "$TEXT") || RELAYED=""
  fi
  if [ -n "$RELAYED" ]; then
    RELAY_ROW=$(printf '%s' "$ROW" | jq -c --arg r "$RELAYED" \
      '.type = "relayed_framework_escape" | .user_response = "n/a" | .details.relayed = $r' 2>/dev/null) || RELAY_ROW=""
  fi
  if [ -n "$RELAY_ROW" ]; then
    ROW="$RELAY_ROW"
  elif [ -z "$RAISE_PATTERN" ]; then
    RAISE_PATTERN="$PATTERN"
  fi

  bypass_audit_append "$PROJECT_ROOT" "$ROW" || true
done <<< "$PATTERNS"

# BL-311-RELAYED-NO-SENTINEL — the pending approval asks the operator about a
# proposal. When every pattern this message matched was a relayed framework
# escape there is none: the rows above are the record, and nothing is asked.
[ -z "$RAISE_PATTERN" ] && exit 0
# BL-311-RELAYED-QUESTION-PATTERN — the question names the first pattern that IS
# a proposal, not a relay that happened to match first.
FIRST_PATTERN="$RAISE_PATTERN"

# BL-029: write pending-approval sentinel iff one isn't already pending.
# Forces non-trivial confirmation phrase to accept (defends against generic
# 'OK' / 'yes' / 'proceed' acceptance, per agent-5 spec). One sentinel
# covers all matched patterns from this proposal.
#
# S5 fix (2026-05-04): the confirmation phrase is NO LONGER embedded in the
# question text. Earlier behavior let Claude/user reading the sentinel
# copy-paste the phrase out of compliance — defeating the defense. The
# phrase remains in options[0] (structurally required for matching), and
# the question instructs the user to read options[0] verbatim.
SENTINEL="$PROJECT_ROOT/.claude/pending-approval.json"
if [ ! -f "$SENTINEL" ]; then
  CONFIRM_PHRASE="I have read the proposal at .claude/bypass-audit.json and accept the bypass"
  jq -nc \
    --arg q "Bypass proposal detected (pattern: $FIRST_PATTERN). Review .claude/bypass-audit.json before deciding. To accept, type option A1 verbatim. To decline, say 'decline' or describe what you want instead." \
    --arg phrase "$CONFIRM_PHRASE" \
    --arg ts "$TS" \
    '{
      question: $q,
      options: [
        ("A1: " + $phrase),
        "A2: decline"
      ],
      recommendation: "A2",
      offered_at: $ts
    }' > "$SENTINEL"
fi

exit 0
