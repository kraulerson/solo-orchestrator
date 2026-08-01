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
#   • The shape, or the reporter's NAME, appearing inside a STRING —
#     `echo "never write: cmd >/dev/null 2>&1 || fail_ 'x'"` and
#     `… || echo "note: call fail_ 'x' first"`. Quoted spans are blanked
#     before matching (see code_skeleton), and the reporter must be at the
#     HEAD of a `||` arm, not merely somewhere in it. Both were live false
#     positives until R-BL197-1's battery fixture caught them.
#
# ── DOCUMENTED BLIND SPOTS (pinned as controls in the battery fixture) ───
#   These ARE the class and this lint does NOT catch them. They are listed
#   so they stay deliberate rather than drifting into "we thought it was
#   covered", and each is pinned by a control line in T19 so a future
#   widening is a visible test change:
#   • a `||` arm whose reporter is on the NEXT line (`… || {` newline
#     `fail_ …`) — the predicate is single-line by design, which is what
#     keeps it free of cross-line false positives;
#   • `if ! cmd >/dev/null 2>&1; then fail_ …; fi` on one line — same
#     class, but the reporter is not in a `||` arm. Widening to `if !`
#     was measured at 58 same-shape sites across the tree, most of them
#     legitimate, so it stays out;
#   • a bare `echo "[FAIL] …"` as the reporter — measured to add zero hits
#     on this tree, so the reporter set stays the four named functions;
#   • `exec 2>/dev/null` silencing a LATER line — no dataflow analysis.
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
#   2 — invocation error, unusable tempfile, failed grep, or an empty
#       scannable file set. A scan that could not run must never be
#       reported as a clean one — that is the silent-success sibling of
#       the very class this lint polices (# BL-197-IO-HARD-FAIL).
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

# (2)+(3) A `||` after the silencer, then a failure reporter AT THE HEAD of
#     that arm. The `||` requirement is what separates "the command failed
#     and its words were destroyed" from "the command succeeded"; the
#     HEAD anchoring is what separates a reporter that RUNS from a reporter
#     merely NAMED in a string (`|| echo "call fail_ 'x' first"` is not a
#     failure report). Matched against each `||` arm in turn — see
#     arm_reports_failure().
# BL-197-DD1-FAILARM
REPORTER_HEAD_RE='^[[:space:]]*(\{[[:space:]]*)?(![[:space:]]*)?(fail_|fail|print_fail|record_init_failure)[[:space:]]+["'"'"']'

# Presence-probe carve-out. ANCHORED against the LAST simple command of the
# head segment (the text before the silencer, after its final command
# separator) — unanchored, `grep -w type config.txt 2>/dev/null || fail_ …`
# was read as a `type` probe and silently blessed, though `type` there is
# just an argument.
# BL-197-DD1-PROBE-CARVEOUT
PROBE_RE='^[[:space:]]*(![[:space:]]*)?(command[[:space:]]+-[vV]|type|hash|which)([[:space:]]|$)'

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

# Reduce a raw line to its CODE SKELETON in one quote-aware scan:
#   • drop a trailing ` #...` comment (the `#` must be outside quotes and
#     at column 0 or preceded by whitespace), and
#   • BLANK the contents of every quoted span, keeping the quote characters
#     themselves.
# The second half is load-bearing, not cosmetic. Without it a line that
# merely NAMES the shape inside a string — `echo "never write: cmd
# >/dev/null 2>&1 || fail_ 'x'"` — matched as if it were code, and so did
# `|| echo "note: call fail_ 'x' first"`. Keeping the quote characters is
# what lets the reporter regex still require its `"` argument delimiter:
# a real `|| fail_ "T2" "msg"` reduces to `|| fail_ "" ""`, which still
# matches, while the string cases reduce to `echo ""`, which does not.
# BL-197-CODE-SKELETON
code_skeleton() {
  local line="$1"
  local out="" in_squote=0 in_dquote=0 prev="" i ch
  local len=${#line}
  for (( i=0; i<len; i++ )); do
    ch="${line:i:1}"
    if [ "$in_squote" = "1" ]; then
      if [ "$ch" = "'" ]; then
        in_squote=0
        out="${out}'"
        prev="$ch"
      fi
      continue
    fi
    if [ "$in_dquote" = "1" ]; then
      if [ "$ch" = '"' ]; then
        in_dquote=0
        out="${out}\""
        prev="$ch"
      fi
      continue
    fi
    if [ "$ch" = "#" ]; then
      if [ -z "$prev" ] || [[ "$prev" =~ [[:space:]] ]]; then
        break
      fi
    fi
    if [ "$ch" = "'" ]; then
      in_squote=1
    elif [ "$ch" = '"' ]; then
      in_dquote=1
    fi
    out="${out}${ch}"
    prev="$ch"
  done
  printf '%s' "$out"
}

# True iff some `||` arm of "$1" STARTS with a failure-reporter invocation.
# Walking the arms (rather than searching the whole tail) is what keeps a
# reporter named inside a string, or a lookalike like `test_fail`, from
# counting as a failure report.
arm_reports_failure() {
  local t="$1"
  while [ "${t#*||}" != "$t" ]; do
    t="${t#*||}"
    if [[ "$t" =~ $REPORTER_HEAD_RE ]]; then
      return 0
    fi
  done
  return 1
}

# The LAST simple command of a head segment: everything after its final
# command separator. Successive strips converge on "after the last
# separator of any kind" because each strip only ever shortens the string.
last_simple_command() {
  local t="$1"
  t="${t##*;}"
  t="${t##*&}"
  t="${t##*|}"
  t="${t##*(}"
  t="${t##*\{}"
  t="${t##*\}}"
  t="${t##*!}"
  printf '%s' "$t"
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

# ── SINGLE-PASS SCAN ─────────────────────────────────────────────────────
# One grep over the WHOLE file list, not one grep + one mktemp per file.
# The per-file shape cost 12.5s on this tree for ~200 files; this is the
# same predicate over the same candidate lines in one exec.
#
# `/dev/null` is prepended to the file list so grep ALWAYS prefixes its
# output with a filename — with a single-element list it would otherwise
# print bare `lineno:content` and every path would parse as a line number.
# /dev/null is empty, so it contributes nothing else.
FILES=()
for entry in "${TARGET_GLOBS[@]}"; do
  # bash 3.2 has no nullglob: an unmatched pattern survives literally.
  [ -f "$entry" ] || continue
  should_skip_file "$entry" && continue
  FILES+=("$entry")
done

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "lint-diagnostic-destruction: no scannable files found under $REPO_ROOT — refusing to report a clean scan of nothing" >&2
  exit 2
fi

# BL-197-IO-HARD-FAIL: an unusable tempfile or a failed grep must NOT
# degrade into "OK: no violations". That silent skip is the exact
# silent-success sibling of the class this lint polices, and the previous
# `tmp="$(mktemp)" || return 0` exempted a whole file that way.
SCAN_TMP="$(mktemp)" || {
  echo "lint-diagnostic-destruction: mktemp failed — refusing to report a scan it could not run" >&2
  exit 2
}
trap 'rm -f "$SCAN_TMP"' EXIT

if [ "$CENSUS_MODE" -eq 1 ]; then
  SCAN_RE="$REPORTER_LINE_RE"
else
  SCAN_RE="$SILENCER_RE"
fi

# grep's OWN stderr is deliberately left unsilenced — a lint about
# destroyed diagnostics must not destroy its own. rc 0 = matches,
# 1 = none, >=2 = a real I/O error that must not pass for "clean".
grep -nE "$SCAN_RE" /dev/null "${FILES[@]}" > "$SCAN_TMP"
scan_rc=$?
if [ "$scan_rc" -gt 1 ]; then
  echo "lint-diagnostic-destruction: grep failed (rc=$scan_rc) — refusing to report a scan it could not complete" >&2
  exit 2
fi

if [ "$CENSUS_MODE" -eq 1 ]; then
  while IFS= read -r hit || [ -n "$hit" ]; do
    [ -n "$hit" ] || continue
    stripped="${hit#"$REPO_ROOT"/}"
    rel="${stripped%%:*}"
    after="${stripped#*:}"
    lineno="${after%%:*}"
    raw="${after#*:}"
    case "${raw#"${raw%%[![:space:]]*}"}" in '#'*) continue ;; esac
    case "$raw" in *'$('*) : ;; *) continue ;; esac
    [[ "$raw" =~ $TRUNCATOR_RE ]] || continue
    CENSUS_COUNT=$((CENSUS_COUNT + 1))
    CENSUS_ROWS="${CENSUS_ROWS}REVIEW\t${rel}:${lineno}\n"
  done < "$SCAN_TMP"
else
  while IFS= read -r hit || [ -n "$hit" ]; do
    [ -n "$hit" ] || continue
    stripped="${hit#"$REPO_ROOT"/}"
    rel="${stripped%%:*}"
    after="${stripped#*:}"
    lineno="${after%%:*}"
    raw="${after#*:}"

    # Pure-comment line: nothing executes, nothing is destroyed.
    case "${raw#"${raw%%[![:space:]]*}"}" in '#'*) continue ;; esac

    code="$(code_skeleton "$raw")"
    [[ "$code" =~ $SILENCER_RE ]] || continue
    head_seg="${code%%"${BASH_REMATCH[0]}"*}"
    tail_seg="${code#*"${BASH_REMATCH[0]}"}"

    arm_reports_failure "$tail_seg" || continue

    last_cmd="$(last_simple_command "$head_seg")"
    if [[ "$last_cmd" =~ $PROBE_RE ]]; then
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
  done < "$SCAN_TMP"
fi

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
