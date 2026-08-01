#!/usr/bin/env bash
# scripts/lint-diagnostic-destruction.sh — BL-197 structural backstop.
#
# THE DEFECT CLASS (diagnostic destruction)
#   *A diagnostic that discards, truncates or blurs the evidence needed to
#   act on the failure it is reporting.* It is the sibling of the
#   silent-success class (print `[FAIL]`, then `exit 0`): there the VERDICT
#   lies; here the verdict is correct and the EVIDENCE is destroyed. In all
#   three measured instances the information was PRESENT and thrown away at
#   the last step — a `>/dev/null 2>&1`, a `tail -N`, an `echo` naming a
#   symptom rather than a number. See solo-orchestrator-backlog.md
#   `## BL-197:` for the three instances and their measured cost (BL-184's
#   cost BL-135 eight days across two ~3h full-lane runs).
#
#   The review question the entry states, which this lint mechanizes for
#   exactly one shape:
#     "When this arm fires, does its output contain what the reader needs
#      to act — and was the underlying evidence available at that point?"
#
# ── WHAT GATES (DD1): silenced-diagnostic failure reports ────────────────
#   A violation is the conjunction of THREE things on ONE line:
#     (1) a command whose diagnostic stream goes to /dev/null —
#         `>/dev/null 2>&1`, `1>/dev/null 2>&1`, `>/dev/null 2>/dev/null`
#         (either order), `&>/dev/null`, `>&/dev/null`, bare `2>/dev/null`,
#         or `2>&-`;
#     (2) a `||` short-circuit AFTER that silencer;
#     (3) a failure reporter invoked in that arm — `fail_`, `fail`,
#         `print_fail` or `record_init_failure` followed by whitespace and
#         a quote.
#   Read together: the command FAILED, its own words were thrown away, and
#   the sentence that replaces them is all the reader gets. That is the
#   class, mechanized, with no cross-line inference.
#
# ── WHAT DOES NOT GATE, AND WHY (each carve-out was MEASURED) ────────────
#   Counts below are from the tree of 2026-07-31 over the scanned globs.
#
#   • PRESENCE PROBES — `command -v X &>/dev/null && print_ok || fail
#     "X not found"`. A probe emits no diagnostic; its non-zero status IS
#     the whole message, so nothing is destroyed. 10 of 19 raw hits were
#     this shape (all in scripts/validate.sh). Carved out by the head
#     segment (text before the silencer) naming `command -v|-V`, `type`,
#     `hash` or `which`. This is the "probing for optional tools" case
#     BL-197 names as legitimate.
#   • `2>&1 >/dev/null` — NOT a silencer. Order is load-bearing: this
#     spelling points stderr at the PRIOR stdout (usually a capture) and
#     only stdout at /dev/null, so the diagnostic SURVIVES. It is the
#     repo's own evidence-preserving idiom; flagging it would be the
#     cry-wolf failure mode BL-197 warns against. Every spelling in (1)
#     above sends stderr to /dev/null; this one does not, and it is the
#     only near-miss spelling in the repo.
#   • A failure reporter reached by `&&` rather than `||` — there the
#     command SUCCEEDED, so it had no diagnostic to destroy (e.g.
#     `ls "$D"/*.tmp 2>/dev/null && { fail_ "leftover tmpfile"; }`, where
#     the offending filenames reach stdout unsilenced).
#   • Pure-comment lines, and the shape appearing inside a TRAILING
#     comment (trailing comments are stripped, quote-aware, before the
#     shape is matched — but the exemption marker is read from the raw
#     line).
#
# ── WHAT IS ADVISORY, NOT GATING (DD2): truncated evidence ───────────────
#   BL-197's second candidate shape is `tail -N` / `head -N` inside a
#   failure-reporting expansion (`fail_ "…" "$(… tail -N …)"`) — instance
#   2's `tail -8` that landed past the SAST section it was meant to show.
#   The entry says this shape must "render its hits for review … rather
#   than block outright", and the measurement says the same, louder:
#     489 sites on today's tree; 216 even after narrowing to "the
#     truncating expansion is the message's ONLY interpolation".
#   Those are dominated by the legitimate idiom where the message already
#   states the expectation and the observed value in words and the tail is
#   supplementary context. A 216-row roster nobody reads would itself be
#   diagnostic destruction. So DD2 renders ON DEMAND under `--census`,
#   never gates, and is deliberately kept OUT of the `--list` roster so
#   the reviewable roster stays reviewable.
#
#   SCOPE DECISION, stated plainly: BL-197's third instance (a message
#   naming a symptom — "absent or unreadable" — instead of the number the
#   operator needs) is NOT mechanized here. It is not structurally
#   decidable: the candidate population is 1120 failure messages with no
#   interpolation at all, most of which are correct. It stays a review
#   question, and BL-197 stays open for it.
#
# ── SCOPE ────────────────────────────────────────────────────────────────
#   Walks init.sh, scripts/*.sh, scripts/{lib,hooks,host-drivers}/*.sh,
#   tests/*.sh, tests/{host-drivers,test-helpers}/*.sh — the operator- AND
#   verification-facing surfaces. BL-197's accurate gap statement is that
#   lint-fix-functions-stderr.sh covers `fix_*` functions on the operator
#   surface while all three instances lived where it does not look: a test
#   aggregator's delegates, a test case's failure message, and a
#   heredoc-emitted hook body.
#
#   HEREDOC BODIES ARE SCANNED — the deliberate opposite of
#   lint-fix-functions-stderr.sh, which skips them. Instance 3 lived in a
#   heredoc-emitted hook body, so skipping them would exclude a third of
#   the recorded class by construction.
#
#   Not scanned: docs/, Reports/, templates/, evaluation-prompts/ (that
#   tree has its own lint, lint-evalprompts-portability.sh), this script,
#   and its own behavior suite (whose fixtures are the class by design).
#
# ── EXEMPTION ────────────────────────────────────────────────────────────
#   Append `# lint-diag-ok: <reason>` to the offending line. The reason is
#   REQUIRED — an empty reason fails the lint, matching the allowlist
#   semantics of lint-fix-functions-stderr.sh and
#   lint-fail-emit-exit-status.sh. Use it where the suppression is real
#   and justified, e.g. a first-attempt retry whose decisive second
#   attempt is unsilenced.
#
# EXIT CODES
#   0 — no violations (or --census, which never gates)
#   1 — one or more violations found
#   2 — invocation / I/O error
#
# USAGE
#   bash scripts/lint-diagnostic-destruction.sh            # quiet pass/fail
#   bash scripts/lint-diagnostic-destruction.sh --list     # PASS/FAIL roster
#   bash scripts/lint-diagnostic-destruction.sh --census   # advisory DD2 rows
#
# PORTABILITY
#   bash-3.2 safe: no associative arrays, no ${var,,}, no nullglob. Runs
#   under `set -uo pipefail` (never `-e`: the scan must reach its summary).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF_PATH="$REPO_ROOT/scripts/lint-diagnostic-destruction.sh"
OWN_SUITE_BASENAME="test-lint-diagnostic-destruction.sh"

LIST_MODE=0
CENSUS_MODE=0
case "${1:-}" in
  "") : ;;
  --list)   LIST_MODE=1 ;;
  --census) CENSUS_MODE=1 ;;
  *)
    echo "Usage: $0 [--list|--census]" >&2
    exit 2
    ;;
esac

TARGET_GLOBS=(
  "$REPO_ROOT/init.sh"
  "$REPO_ROOT/scripts"/*.sh
  "$REPO_ROOT/scripts/lib"/*.sh
  "$REPO_ROOT/scripts/hooks"/*.sh
  "$REPO_ROOT/scripts/host-drivers"/*.sh
  "$REPO_ROOT/tests"/*.sh
  "$REPO_ROOT/tests/host-drivers"/*.sh
  "$REPO_ROOT/tests/test-helpers"/*.sh
)

# ── DD1 atoms ────────────────────────────────────────────────────────────
# (1) The silencer. Every alternative sends the command's DIAGNOSTIC to
#     /dev/null. `2>&1 >/dev/null` matches NONE of them by construction:
#     its `2>` is followed by `&1`, its `>/dev/null` is not followed by a
#     `2>`, and neither `&>` nor `>&` appears — see the header.
# BL-197-DD1-SILENCER
SILENCER_RE='(^|[[:space:](;&|])(1?>[[:space:]]*/dev/null[[:space:]]+2>[[:space:]]*(&1|/dev/null)|2>[[:space:]]*/dev/null[[:space:]]+1?>[[:space:]]*/dev/null|&>[[:space:]]*/dev/null|>&[[:space:]]*/dev/null|2>[[:space:]]*/dev/null|2>&-)'

# (2)+(3) A `||` after the silencer, then a failure reporter in that arm.
#     The `||` requirement is what separates "the command failed and its
#     words were destroyed" from "the command succeeded" — see header.
# BL-197-DD1-FAILARM
FAIL_ARM_RE='\|\|.*[[:space:]{;(](fail_|fail|print_fail|record_init_failure)[[:space:]]+["'"'"']'

# Presence-probe carve-out, matched against the text BEFORE the silencer.
# BL-197-DD1-PROBE-CARVEOUT
PROBE_RE='(^|[[:space:](;&|!])(command[[:space:]]+-[vV]|type|hash|which)[[:space:]]'

EXEMPT_MARKER='# lint-diag-ok:'

# ── DD2 atoms (advisory census only) ─────────────────────────────────────
REPORTER_LINE_RE='(^|[[:space:]{;|&(])(fail_|fail|print_fail|record_init_failure)[[:space:]]+["'"'"']'
TRUNCATOR_RE='(^|[[:space:]|(])(tail|head)[[:space:]]+(-n[[:space:]]*)?-?[0-9]'

VIOLATIONS=0
LIST_ROWS=""
CENSUS_ROWS=""
CENSUS_COUNT=0

should_skip_file() {
  local f="$1"
  [ "$f" = "$SELF_PATH" ] && return 0
  [ "$(basename "$f")" = "$OWN_SUITE_BASENAME" ] && return 0
  return 1
}

# Strip a trailing ` #...` comment unless the `#` lives inside quotes.
# Same quote-aware scan as lint-fix-functions-stderr.sh — a line whose
# only occurrence of the shape is in a trailing comment must not fire.
strip_trailing_comment() {
  local line="$1"
  local out="" in_squote=0 in_dquote=0 prev="" i ch
  local len=${#line}
  for (( i=0; i<len; i++ )); do
    ch="${line:i:1}"
    if [ "$in_squote" = "0" ] && [ "$in_dquote" = "0" ] && [ "$ch" = "#" ]; then
      if [ -z "$prev" ] || [[ "$prev" =~ [[:space:]] ]]; then
        break
      fi
    fi
    if [ "$in_dquote" = "0" ] && [ "$ch" = "'" ]; then
      in_squote=$((1 - in_squote))
    elif [ "$in_squote" = "0" ] && [ "$ch" = '"' ]; then
      in_dquote=$((1 - in_dquote))
    fi
    out="${out}${ch}"
    prev="$ch"
  done
  printf '%s' "$out"
}

# Echo the exemption reason (possibly empty) if the marker is present;
# return 1 when there is no marker at all. Read from the RAW line.
exempt_reason() {
  local line="$1" reason
  case "$line" in
    *"$EXEMPT_MARKER"*) : ;;
    *) return 1 ;;
  esac
  reason="${line##*"$EXEMPT_MARKER"}"
  reason="${reason#"${reason%%[![:space:]]*}"}"
  reason="${reason%"${reason##*[![:space:]]}"}"
  printf '%s' "$reason"
  return 0
}

scan_file_dd1() {
  local file="$1" rel="$2"
  local tmp hit lineno raw code head_seg tail_seg reason
  tmp="$(mktemp)" || return 0
  # One grep per file, then per-candidate work in-process: the candidate
  # set is tiny (19 lines across ~200 files on today's tree).
  # grep's OWN stderr is deliberately left unsilenced — a lint about
  # destroyed diagnostics must not destroy its own.
  grep -nE "$SILENCER_RE" "$file" > "$tmp"
  while IFS= read -r hit || [ -n "$hit" ]; do
    [ -n "$hit" ] || continue
    lineno="${hit%%:*}"
    raw="${hit#*:}"

    # Pure-comment line: nothing executes, nothing is destroyed.
    case "${raw#"${raw%%[![:space:]]*}"}" in '#'*) continue ;; esac

    code="$(strip_trailing_comment "$raw")"
    [[ "$code" =~ $SILENCER_RE ]] || continue
    head_seg="${code%%"${BASH_REMATCH[0]}"*}"
    tail_seg="${code#*"${BASH_REMATCH[0]}"}"

    [[ "$tail_seg" =~ $FAIL_ARM_RE ]] || continue
    if [[ "$head_seg" =~ $PROBE_RE ]]; then
      LIST_ROWS="${LIST_ROWS}PASS\t${rel}:${lineno}\tpresence-probe (no diagnostic to destroy)\n"
      continue
    fi

    if reason="$(exempt_reason "$raw")"; then
      if [ -z "$reason" ]; then
        echo "${rel}:${lineno}: lint-diagnostic-destruction: exemption marker present but reason is empty" >&2
        VIOLATIONS=$((VIOLATIONS + 1))
        LIST_ROWS="${LIST_ROWS}FAIL\t${rel}:${lineno}\texemption-empty-reason\n"
      else
        LIST_ROWS="${LIST_ROWS}PASS\t${rel}:${lineno}\texempt: ${reason}\n"
      fi
      continue
    fi

    echo "${rel}:${lineno}: lint-diagnostic-destruction: the failed command's diagnostic is discarded and a failure is reported in its place — capture it (e.g. 'out=\$(cmd 2>&1)') and put it in the message, or append '# lint-diag-ok: <reason>'" >&2
    VIOLATIONS=$((VIOLATIONS + 1))
    LIST_ROWS="${LIST_ROWS}FAIL\t${rel}:${lineno}\tsilenced-diagnostic-failure-report\n"
  done < "$tmp"
  rm -f "$tmp"
}

scan_file_dd2() {
  local file="$1" rel="$2"
  local tmp hit lineno
  tmp="$(mktemp)" || return 0
  grep -nE "$REPORTER_LINE_RE" "$file" \
    | grep -vE '^[0-9]+:[[:space:]]*#' \
    | grep -F '$(' \
    | grep -E "$TRUNCATOR_RE" > "$tmp"
  while IFS= read -r hit || [ -n "$hit" ]; do
    [ -n "$hit" ] || continue
    lineno="${hit%%:*}"
    raw="${hit#*:}"
    CENSUS_COUNT=$((CENSUS_COUNT + 1))
    CENSUS_ROWS="${CENSUS_ROWS}REVIEW\t${rel}:${lineno}\n"
  done < "$tmp"
  rm -f "$tmp"
}

for entry in "${TARGET_GLOBS[@]}"; do
  # bash 3.2 has no nullglob: an unmatched pattern survives literally.
  [ -f "$entry" ] || continue
  should_skip_file "$entry" && continue
  rel="${entry#"$REPO_ROOT"/}"
  if [ "$CENSUS_MODE" -eq 1 ]; then
    scan_file_dd2 "$entry" "$rel"
  else
    scan_file_dd1 "$entry" "$rel"
  fi
done

if [ "$CENSUS_MODE" -eq 1 ]; then
  printf 'STATUS\tFILE:LINE\n'
  printf '%b' "$CENSUS_ROWS"
  echo "census: $CENSUS_COUNT truncated-evidence site(s) — ADVISORY (BL-197 DD2), never gating."
  echo "Ask of each: when this arm fires, does the message carry what the reader needs to act?"
  exit 0
fi

if [ "$LIST_MODE" -eq 1 ]; then
  printf 'STATUS\tFILE:LINE\tDETAIL\n'
  printf '%b' "$LIST_ROWS"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "" >&2
  echo "$VIOLATIONS violation(s) found. See scripts/lint-diagnostic-destruction.sh header for the fix pattern." >&2
  exit 1
fi

echo "OK: no silenced-diagnostic failure reports found."
echo "    (advisory truncated-evidence census: bash scripts/lint-diagnostic-destruction.sh --census)"
exit 0
