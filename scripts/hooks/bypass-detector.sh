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
# record is kept, and no pending-approval sentinel is raised for it.
#
# FIRST, THE SPANS (_soif_relay_spans). EVERY inline code span on the line must
# be one a relay carries: (a) an escape span (kind 1 below), (b) the pinned
# finisher, (c) `!` alone, or (d) a Claude Code slash command, /name (the
# dogfood relay names `/session-resume`), on an escape line only (kind 1) — and
# at most one of them an escape or the finisher. Any other span — a file,
# `reboot`, a second command, however the words around it read — and the line
# is no relay. Then the line is one of
# two kinds, each defined narrowly:
#
#   1. AN ATTESTED ESCAPE AS ITS CHECK DOCUMENTS IT (_soif_relay_escape_line).
#      Exactly one inline code span that is a row of the table below — the
#      attested variable set to 1, then its reason variable set to a non-empty
#      value no shell expands (single-quoted; double-quoted with no $ ` \ !; or
#      one plain word), then nothing or the documented command with only the
#      arguments its check documents (the row's argument grammar,
#      _soif_relay_args_ere: none at all for most; one quoted message for
#      `git commit`; a plain remote and branch for `git push`) — inside a relay
#      phrase: a verb right before the span, "in/from/on/at/… <up to four
#      words> terminal|shell" right after it, addressed to the person.
#   2. THE DOCUMENTED HAND-TO-HUMAN STEP (_soif_relay_handoff_line). A line that
#      names `!` and the Claude Code prompt, whose only terminal/shell words are
#      Claude Code's name for that route ("shell mode", "shell command(s)"), and
#      that carries no escape span and no slash command: its one command, if
#      it names one, is the assessment's finisher, byte for byte
#      (SOIF_RELAY_FINISHER_SHA256). No project file is read for it: the prompt
#      the agent was given is a file the session can write.
#
# THE THREAT: AN AGENT QUOTING A SANCTIONED ESCAPE AS COVER for a real proposal
# in the same message. That is why the exemption is per pattern and per line:
# only terminal_workaround can be exempt — every other
# pattern names a bypass mechanism (--no-verify, SOIF_FORCE_STEP=, a force push,
# marking a step complete) that no documented escape contains, so it raises
# whatever else the message says; EVERY line terminal_workaround matches must
# qualify, or the pattern raises; and on a qualifying line nothing may ride
# along — no inline code but the four span shapes above, no other environment
# assignment (an invented variable, an attested variable without its reason, an
# unregistered SOLO_*_ATTESTED), no option-like token outside the escape, no
# argument inside it that its check does not document, no second terminal route
# once the relay phrase is cut out, and no first-person announcement that the
# AGENT will run the escape ("let me run `…`", "I'll run `…`", "we'll run `…`"):
# an attestation is the person's decision, and an agent that says it will make
# one is proposing to. Per line cuts both ways: a line terminal_workaround does
# not match is never read here, so a proposal on the NEXT line, in a fenced
# block, or in anything but backtick spans (&#96;, lookalike quotes, bold,
# plain words) is caught only if a pattern of its own matches it.
# BEHIND ALL OF THAT, A BACKSTOP (_soif_relay_destructive): a line that carries a
# force, a history rewrite, a deleted remote ref, a skipped hook or permission
# check, or any long option after `git commit`/`git push` but --message, is never
# a relay, whatever the table or the grammars say.
# tests/test-bl311-d-relayed-escape.sh pins each condition.
#
# LIMITS. Every condition fails CLOSED: a line that misses one raises the
# sentinel exactly as before. Not separated, and recorded on `## BL-311:`: a
# proposal in plain words (no code, no flag, no variable) that shares the relay
# phrase's own terminal word, or that a slash command carries on an escape line
# (any /name is allowed there, read no more closely than plain words); a
# proposal on another line that no pattern matches; an escape relayed in a fenced
# block (fences are stripped before the scan, so the lead-in line carries no
# escape and raises).
# The finisher is pinned as text: what it runs is resolved through
# .claude/orchestrator-source.json when the person types it, and no pin here
# can vouch for that file. The PostToolUse arm is untouched: `## BL-277:` owns it.
#
# THE ESCAPE TABLE is the single source of truth. One row per exempt escape:
# attested variable | reason variable | documented command | argument grammar
# (_soif_relay_args_ere; empty = the command takes no argument). Each row's
# command and grammar are the invocation its check prints, quoted in the
# comment above it. Every SOLO_*_ATTESTED variable that a script,
# init.sh or a template reads is either a row here or a name in
# SOIF_RELAY_NOT_EXEMPT, with the reason; the suite's R1 fails otherwise, so a
# check cannot add an escape without someone deciding which list it joins.
# BL-311-RELAY-ESCAPES-BEGIN
SOIF_RELAY_ESCAPES=(
  # session-mcp-gate.sh's ESCAPE_HINT: "SOLO_MCP_ATTESTED=1 SOLO_MCP_REASON='<why>' claude" — claude, no argument.
  # Reason mandatory; recorded to process-state.json::mcp_attestations[] (or .claude/mcp-attestations.jsonl), refused if neither can be written.
  'SOLO_MCP_ATTESTED|SOLO_MCP_REASON|claude|'
  # check-phase-gate.sh's accumulation FAIL: "… bash scripts/check-phase-gate.sh" — no argument.
  # Reason mandatory; recorded to process-state.json, refused if it cannot be.
  'SOLO_MCP_ACCUM_ATTESTED|SOLO_MCP_ACCUM_ATTESTED_REASON|bash scripts/check-phase-gate.sh|'
  # pre-commit-gate.sh's BL-072 FAIL block: "SOLO_TDD_ATTESTED=1 SOLO_TDD_REASON='<why …>' git commit ..." — a message, nothing else.
  # Recorded to process-state.json::tdd_attestations[], refused if it cannot be.
  'SOLO_TDD_ATTESTED|SOLO_TDD_REASON|git commit|commit-message'
  # check-phase-gate.sh's Phase 3→4 review FAIL (and docs/builders-guide.md) print the pair alone; the gate's own command, no argument.
  # Reason mandatory; recorded to process-state.json::phase3.attestations.reviewers.
  'SOLO_REVIEWERS_ATTESTED|SOLO_REVIEWERS_ATTESTED_REASON|bash scripts/check-phase-gate.sh|'
  # check-pr-review.sh's refusal: "SOLO_PR_REVIEW_ATTESTED_REASON=\"<why …>\" git push" — no argument, or a plain remote and branch.
  # Reason mandatory; recorded to process-state.json::pr_review_attestations[], refused if it cannot be.
  'SOLO_PR_REVIEW_ATTESTED|SOLO_PR_REVIEW_ATTESTED_REASON|git push|remote-branch'
  # process-checklist.sh's results_received hint: "re-run with SOLO_UAT_SOLO_ATTESTED=1 [SOLO_UAT_REASON=\"...\"]" — the pair; the script, no argument.
  # Recorded to process-state.json::uat_session.solo_attestations[], refused if it cannot be.
  'SOLO_UAT_SOLO_ATTESTED|SOLO_UAT_REASON|bash scripts/process-checklist.sh|'
  # docs/security-scan-guide.md (run-phase3-validation.sh's license deny): "… bash scripts/run-phase3-validation.sh" — no argument.
  # Recorded to phase3.license_exceptions[], FAIL if it cannot be.
  'SOLO_LICENSE_ATTESTED|SOLO_LICENSE_REASON|bash scripts/run-phase3-validation.sh|'
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

# THE FINISHER, PINNED. The one command a shell-mode relay may carry is the line
# step 10 of the assessment prompt prints (# BL-311-ASSESSMENT-AUTO-MODE):
#   bash "$(jq -r .source_dir .claude/orchestrator-source.json)/scripts/adopt-project.sh" --act4 --root .
# Core may not name the adoption module on an executed line
# (lint-module-dependencies.sh T1, which no allowlist row can waive), so the
# literal lives in the comment above and the code holds its SHA-256. The suite
# generates the prompt with the module's own writer and fails when the two
# drift apart (R7), so a change to the finisher must come here too.
# BL-311-HANDOFF-FINISHER-PIN
SOIF_RELAY_FINISHER_SHA256='6e3dddd3fb669270fdfa6810c980163aa51f5bfdd909e86a40947880b5ff9c56'

# _soif_relay_sha256 TEXT — TEXT's SHA-256 in hex; rc 1 when no tool here computes one.
_soif_relay_sha256() {
  local h=""
  h=$( { printf '%s' "$1" | sha256sum 2>/dev/null || printf '%s' "$1" | shasum -a 256 2>/dev/null; } | awk '{print $1; exit}' )
  case "$h" in ''|*[!0-9a-f]*) return 1 ;; esac
  [ "${#h}" -eq 64 ] || return 1
  printf '%s' "$h"
}

# _soif_relay_args_ere GRAMMAR — the ERE for what may follow an escape's command:
# only the arguments its check documents. An unknown GRAMMAR is rc 1, so its row
# matches nothing and the line raises.
_soif_relay_args_ere() {
  local bt='`' name=""
  case "$1" in
    # BL-311-RELAY-ARGS-NONE — the command exactly, with no argument.
    '') printf '%s' "" ;;
    # BL-311-RELAY-ARGS-COMMIT — `git commit`, or with -m/--message and ONE quoted
    # message no shell expands; no other flag, and nothing after the message.
    commit-message) printf '%s' "([[:space:]]+(-m|--message)[[:space:]]+('[^'${bt}]+'|\"[^\"${bt}\$\\\\!]+\"))?" ;;
    # BL-311-RELAY-ARGS-PUSH — `git push`, or with a plain remote and a plain
    # branch: neither starts with - or + (a flag, a forced refspec), no colon.
    remote-branch)
      name="[A-Za-z0-9_][A-Za-z0-9._/-]*"
      printf '%s' "([[:space:]]+${name}[[:space:]]+${name})?" ;;
    *) return 1 ;;   # BL-311-RELAY-ARGS-UNKNOWN
  esac
}

# _soif_relay_span_ere ATT REASON CMD GRAMMAR — the ERE for one escape's inline
# code span; rc 1 when GRAMMAR is not one _soif_relay_args_ere defines.
_soif_relay_span_ere() {
  local att="$1" reason="$2" cmd="$3" args="$4" bt='`' val="" tail=""
  # BL-311-RELAY-REASON-VALUE — non-empty, and nothing a shell expands: single-quoted,
  # double-quoted with no $ ` \ ! inside, or one plain word.
  val="('[^'${bt}]+'|\"[^\"${bt}\$\\\\!]+\"|[A-Za-z0-9_.,:/+-]+)"
  cmd="${cmd//./[.]}"
  cmd="${cmd// /[[:space:]]+}"
  # BL-311-RELAY-ARGS-GRAMMAR — after the command, only the arguments its check documents.
  tail=$(_soif_relay_args_ere "$args") || return 1
  # BL-311-RELAY-REASON-REQUIRED — the attested variable AND its reason variable, in the documented order.
  printf '%s' "${bt}${att}=1[[:space:]]+${reason}=${val}([[:space:]]+${cmd}${tail})?[[:space:]]*${bt}"
}

# _soif_relay_destructive LINE — rc 0 iff LINE carries, anywhere, a force, a
# history rewrite, a deleted remote ref, or a skipped hook or permission check,
# or any long option after `git commit`/`git push` but --message. The backstop
# behind the grammars: such a line is never a relay, whatever the table says, so
# a widened grammar cannot exempt one.
_soif_relay_destructive() {
  local low="" ere="" after="" m=""
  low=$(printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z')
  # BL-311-RELAY-BACKSTOP-FLAGS — the long forms, anywhere on the line.
  case "$low" in
    *--force*|*--amend*|*--no-verify*|*--dangerously-skip-permissions*|*--delete*|*--mirror*|*--prune*) return 0 ;;
  esac
  # BL-311-RELAY-BACKSTOP-PUSH — after `git push`: a short -f/-d, a +refspec (forced) or a :refspec (deleted).
  ere="git[[:space:]]+push[[:space:]](.*[[:space:]])?(-[a-z]*[fd]|[+:][^[:space:]])"
  [[ $low =~ $ere ]] && return 0
  # BL-311-RELAY-BACKSTOP-COMMIT — after `git commit`: a short-flag cluster carrying -n (no-verify).
  ere="git[[:space:]]+commit[[:space:]](.*[[:space:]])?-[a-z]*n"
  [[ $low =~ $ere ]] && return 0
  # BL-311-RELAY-BACKSTOP-LONGOPT — after `git commit` or `git push`, every long
  # option but --message (or --message=…). git takes any unambiguous prefix of a
  # long option — `--amen` is --amend, `--no-veri` is --no-verify, `--forc` is
  # --force — so no list of names can hold; only the documented one passes.
  ere="git[[:space:]]+(commit|push)([[:space:]].*)$"
  if [[ $low =~ $ere ]]; then
    after="${BASH_REMATCH[2]}"
    ere="--[a-z0-9-]*"
    while [[ $after =~ $ere ]]; do
      m="${BASH_REMATCH[0]}"
      [ "$m" = "--message" ] || return 0   # BL-311-RELAY-BACKSTOP-MESSAGE
      after="${after#*"$m"}"
    done
  fi
  return 1
}

# What an escape, the finisher or `!` becomes once _soif_relay_spans has
# classified it: a printable token (a control byte is not safe: bash uses \001
# internally and drops it from =~ patterns). All three share the prefix "@@soif-",
# so a line that already carries it is refused rather than trusted. A slash
# command keeps its own text (its backticks dropped), so every word check still
# reads it: an opaque token there would hide a "terminal" or "shell" in its name
# from the remainder check.
SOIF_RELAY_TOK_ESCAPE='@@soif-relay@@'
SOIF_RELAY_TOK_FINISHER='@@soif-finisher@@'
SOIF_RELAY_TOK_BANG='@@soif-bang@@'

# _soif_relay_spans LINE — rc 0 iff EVERY inline code span on LINE is one a relay
# carries, at most one of them an escape or the finisher. On rc 0 it sets
# SOIF_RELAY_REST (LINE with each span replaced by its kind's token, or a slash
# command by its own text), SOIF_RELAY_ATT (the escape span's attested
# variable, or empty) and SOIF_RELAY_SLASH (1 when a slash command was among
# the spans, or empty). Split on the backtick rather than ${var//pat/rep}: no
# replacement text for bash 5.2's `&` rule to reinterpret.
_soif_relay_spans() {
  local t="$1" bt='`' out="" c="" body="" kind="" low="" row="" att="" reason="" cmd="" args="" ere="" n=0 slash_ere=""
  SOIF_RELAY_REST=""
  SOIF_RELAY_ATT=""
  SOIF_RELAY_SLASH=""
  low=$(printf '%s' "$t" | LC_ALL=C tr 'A-Z' 'a-z')
  # BL-311-RELAY-TOKEN-FORGE — a token the line already carries was not put there by this function.
  case "$low" in *"@@soif-"*) return 1 ;; esac
  # BL-311-RELAY-SPAN-SLASH — (d) a Claude Code slash command: /name, and nothing after it.
  slash_ere='^/[a-z][a-z0-9-]*$'
  while :; do
    case "$t" in *"$bt"*"$bt"*) ;; *) break ;; esac
    out="$out${t%%"$bt"*}"
    t="${t#*"$bt"}"
    c="${t%%"$bt"*}"
    t="${t#*"$bt"}"
    kind=""
    body="$c"
    case "$c" in "! "*) body="${c#"! "}" ;; esac
    # BL-311-RELAY-SPAN-BANG — (c) `!` alone; then (d), the slash command.
    if [ "$c" = "!" ]; then
      kind="$SOIF_RELAY_TOK_BANG"
    elif [[ $c =~ $slash_ere ]]; then
      kind="$c"
      SOIF_RELAY_SLASH=1
    else
      # BL-311-RELAY-TABLE-NONEMPTY — an empty table names no escape (and bash 3.2
      # reads an empty array as unbound under set -u).
      if [ "${#SOIF_RELAY_ESCAPES[@]}" -gt 0 ]; then
        for row in "${SOIF_RELAY_ESCAPES[@]}"; do
          IFS='|' read -r att reason cmd args <<EOF
$row
EOF
          ere=$(_soif_relay_span_ere "$att" "$reason" "$cmd" "$args") || continue
          # BL-311-RELAY-ERE-NONEMPTY — an empty ERE is skipped on every platform: this
          # Mac's regcomp refuses one (=~ is rc 2) and glibc's matches every string.
          [ -n "$ere" ] || continue
          # BL-311-RELAY-SPAN-ESCAPE — (a) the whole span, backtick to backtick, is one row of the table.
          if [[ "$bt$c$bt" =~ $ere ]]; then
            kind="$SOIF_RELAY_TOK_ESCAPE"
            SOIF_RELAY_ATT="$att"
            break
          fi
        done
      fi
      # BL-311-HANDOFF-FINISHER-MATCH — (b) the finisher byte for byte, bare or after "! ".
      if [ -z "$kind" ] && [ "$(_soif_relay_sha256 "$body" || true)" = "$SOIF_RELAY_FINISHER_SHA256" ]; then
        kind="$SOIF_RELAY_TOK_FINISHER"
      fi
    fi
    # BL-311-RELAY-SPANS-ONLY — any other span, and the line is no relay.
    [ -n "$kind" ] || return 1
    case "$kind" in "$SOIF_RELAY_TOK_ESCAPE"|"$SOIF_RELAY_TOK_FINISHER") n=$((n + 1)) ;; esac
    out="$out$kind"
  done
  # BL-311-RELAY-SPANS-ONE — one escape or finisher on a line, never two.
  [ "$n" -le 1 ] || return 1
  # BL-311-RELAY-SPANS-PAIRED — an unpaired backtick opens code this rule cannot read.
  case "$t" in *"$bt"*) return 1 ;; esac
  SOIF_RELAY_REST="$out$t"
}

# _soif_relay_first_person LOW — rc 0 iff LOW (lowercased, its spans tokenized)
# has the AGENT announcing that it will run the escape or the finisher itself:
# a first-person subject ("let me", "let's", "i'll", "we'll", "i'm", "i need",
# "going to", "once i" …), then at most six words, then a relay verb right
# before the token. A match that names the person ("i'll wait while you run …")
# is the person running it.
_soif_relay_first_person() {
  local low="$1" rsq="" subj="" verb="" fp_ere="" m=""
  rsq=$(printf '\342\200\231')   # the typographic apostrophe, as bytes
  # BL-311-RELAY-FP-SUBJECT — each alternative is pinned by a case and a mutant.
  subj="let me|let('|${rsq})s|i('|${rsq})ll|i will|i('|${rsq})m|i am|i can|i could|i('|${rsq})d|i would|i shall|i need|i should|i have|i must|i want|we('|${rsq})ll|we will|going to|once i"
  # BL-311-RELAY-FP-VERB — the relay verbs; each pinned the same way.
  verb="re-?run|run|execute|launch|start|type|paste|enter|use"
  # BL-311-RELAY-FP-FILLER — up to six words between the subject and the verb.
  fp_ere="(^|[^a-z])(${subj})([[:space:]]+[a-z'-]+){0,6}[[:space:]]+(${verb})[[:space:]]+(${SOIF_RELAY_TOK_ESCAPE}|${SOIF_RELAY_TOK_FINISHER})"
  [[ $low =~ $fp_ere ]] || return 1
  m="${BASH_REMATCH[0]}"
  # BL-311-RELAY-YOU-RUN-IT — the person is the one who runs it.
  case " $m " in *" you "*|*" your "*|*" yourself "*) return 1 ;; esac
  return 0
}

# _soif_relay_escape_line REST ATT TW — rc 0, with ATT on stdout, iff the line
# _soif_relay_spans tokenized into REST relays a registered escape (kind 1 above)
# and nothing else on it could be a proposal. ATT is the escape span's attested
# variable (empty when the line has none); TW is the live terminal_workaround regex.
_soif_relay_escape_line() {
  local rest="$1" att="$2" tw="$3" tok="$SOIF_RELAY_TOK_ESCAPE" bt='`' low="" m=""
  local env_ere="" opt_ere="" phrase_ere=""
  # BL-311-RELAY-ESCAPE-SPAN — an escape span is on the line (_soif_relay_spans allows one at most).
  [ -n "$att" ] || return 1
  # BL-311-RELAY-NO-OTHER-ENV — no assignment survives outside the registered spans.
  env_ere="(^|[[:space:]${bt}\"'(])[A-Za-z_][A-Za-z0-9_]*="
  [[ $rest =~ $env_ere ]] && return 1
  # BL-311-RELAY-NO-FLAGS — no option-like token outside them either.
  opt_ere="(^|[[:space:](])--?[A-Za-z]"
  [[ $rest =~ $opt_ere ]] && return 1
  low=$(printf '%s' "$rest" | LC_ALL=C tr 'A-Z' 'a-z')
  # BL-311-RELAY-FIRST-PERSON — the agent announcing it will run the escape itself is no relay.
  _soif_relay_first_person "$low" && return 1
  # BL-311-RELAY-PHRASE — a verb right before the span, the place right after it;
  # each such phrase is cut out, leaving a sentence break.
  phrase_ere="(^|[^a-z])(re-?run|run|execute|launch|start|type|paste|enter|use|with)[[:space:]]+${tok}[[:space:],]+(in|from|on|at|inside|within|using|via|through)[[:space:]]+([a-z][a-z'-]*[[:space:]]+){0,4}(terminal|shell)([^a-z0-9_]|$)"
  while [[ $low =~ $phrase_ere ]]; do
    m="${BASH_REMATCH[0]}"
    low="${low%%"$m"*}${BASH_REMATCH[1]}.${BASH_REMATCH[6]}${low#*"$m"}"
  done
  # BL-311-RELAY-REMAINDER — with each relay phrase cut out, no terminal route is left.
  printf '%s\n' "$low" | grep -qiE -e "$tw" && return 1
  printf '%s' "$att"
}

# _soif_relay_handoff_line LINE REST ATT SLASH — rc 0 iff LINE relays the documented
# hand-to-human step (kind 2 above) and nothing else on it could be a proposal.
# REST, ATT and SLASH are what _soif_relay_spans made of LINE.
_soif_relay_handoff_line() {
  local line="$1" rest="$2" att="$3" slash="$4" bt='`' low="" m=""
  local bang_ere="" prompt_ere="" env_ere="" opt_ere="" mode_ere=""
  low=$(printf '%s' "$line" | LC_ALL=C tr 'A-Z' 'a-z')
  # BL-311-HANDOFF-BANG — it names Claude Code's `!` prefix and the Claude Code prompt.
  bang_ere="(^|[[:space:](${bt}\"'])!([[:space:])${bt}\"',.:]|$)"
  prompt_ere="claude code[^[:space:]]* prompt"
  [[ $low =~ $bang_ere ]] || return 1
  [[ $low =~ $prompt_ere ]] || return 1
  # BL-311-HANDOFF-COMMAND-PINNED — no escape span: the one command it may carry
  # is the pinned finisher (_soif_relay_spans), and no project file is read for
  # it (the session can write any of them).
  [ -z "$att" ] || return 1
  # BL-311-HANDOFF-NO-SLASH — a slash command rides only on an escape line (the
  # dogfood relay's `/session-resume`); here it could be `/permissions` or `/hooks`.
  [ -z "$slash" ] || return 1
  # BL-311-HANDOFF-COMMAND-VERBATIM — no variable, no flag outside the spans.
  env_ere="(^|[[:space:]\"'(])[A-Za-z_][A-Za-z0-9_]*="
  [[ $rest =~ $env_ere ]] && return 1
  opt_ere="(^|[[:space:](])--?[A-Za-z]"
  [[ $rest =~ $opt_ere ]] && return 1
  low=$(printf '%s' "$rest" | LC_ALL=C tr 'A-Z' 'a-z')
  # BL-311-HANDOFF-FIRST-PERSON — the agent announcing it will type the finisher itself is no relay.
  _soif_relay_first_person "$low" && return 1
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
    # BL-311-RELAY-BACKSTOP-CALL — a destructive shape anywhere on the line, and it is no relay.
    _soif_relay_destructive "$line" && return 1
    # BL-311-RELAY-SPANS-CALL — every inline code span is one a relay carries, or the line is no relay.
    _soif_relay_spans "$line" || return 1
    if k=$(_soif_relay_escape_line "$SOIF_RELAY_REST" "$SOIF_RELAY_ATT" "$tw"); then
      :
    elif _soif_relay_handoff_line "$line" "$SOIF_RELAY_REST" "$SOIF_RELAY_ATT" "$SOIF_RELAY_SLASH"; then
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
