#!/usr/bin/env bash
# scripts/session-cadence-check.sh — the SessionStart NAG arm of §8.3's
# calendar re-fire trigger.
#
# SPEC: docs/designs/2026-08-02-delta-track-v1.md §8.3 ("Two enforcement points
# (D5) … At session start — nag. A new arm reports overdue cadences once."),
# §11-WP6. It is the SOFT half of the pair; the hard half is WP7's release cut,
# which refuses on the same two exit codes.
#
# (No `# BL-NNN-…` marker on purpose: no backlog entry exists for the delta
# build and minting one would red scripts/lint-bl-markers.sh. The design-doc
# path above is the citation, per the WP1-WP5 precedent.)
#
# ═════════════════════════════════════════════════════════════════════════════
# THE HOUSE CONTRACT FOR EVERY SessionStart HOOK THE FRAMEWORK SHIPS
#
#   • SILENT WHEN NOTHING IS WRONG — zero bytes on stdout AND stderr. A hook
#     that "only prints a little" when healthy is a hook every session learns
#     to skim past, and the one time it matters it is buried.
#   • FAIL-OPEN — exit 0 under EVERY failure mode. A broken checker must never
#     brick a session. That guarantee is a LINE, not a promise in a header:
#     `# CADENCE-NAG-FAILOPEN` below, and tests/test-delta-wp6-cadence.sh::m4
#     neuters it and asserts the crash reaches SessionStart.
#   • ZERO NETWORK — ever. Everything it reads is local: a git log, a directory
#     listing, and a JSON file. The WP6 suite asserts this by SHADOWING
#     curl/wget/nc/ping/ssh in PATH rather than by reading this source.
#
# It joins session-version-check.sh, session-test-gate-check.sh,
# session-freshness-check.sh, session-intake-check.sh and
# detect-out-of-band-commits.sh in `.hooks.SessionStart`, injected by the same
# idempotent `jq` merge init.sh already uses for all five.
#
# ═════════════════════════════════════════════════════════════════════════════
# WHY IT REPORTS TWO CODES AND NOT ONE
#
# scripts/check-maintenance.sh answers 0 current / 1 overdue / 2 UNMEASURABLE.
# The third code is BL-213's repair: before WP6 a date neither parser accepted
# was skipped in silence and reported as current at rc 0. A nag that only spoke
# for rc 1 would inherit exactly that blind spot at the surface where a human
# might have caught it, so 2 gets its own sentence — and it says why it is not
# the same as "fine".
#
# ═════════════════════════════════════════════════════════════════════════════
# THE NAG IS A POST-LAUNCH SURFACE, AND THAT GATE IS WHY DAY ZERO IS SILENT
#
# A maintenance cadence is a property of a SHIPPED product. The whole post-1.0
# track lives at phase 4 (D7's era invariant), and §8.3's two enforcement points
# are a release cut and this nag — both after launch.
#
# It is not a theoretical tidiness. `init.sh` creates `docs/test-results/` at
# birth, so a brand-new project has the evidence SURFACE with nothing in it,
# which the checker correctly reports as unmeasurable (exit 2). Measured on a
# real scaffold: an ungated nag printed 354 bytes at the first SessionStart of
# every generated project, about a security scan a phase-0 project has no
# business having run. A noisy day zero is what the freshness hook's day-zero
# silence rule exists to prevent, and a hook nobody reads is worth less than no
# hook at all.
#
# The gate is on the NAG, never on the checker: `check-maintenance.sh` still
# answers honestly at any phase, and WP7's release cut — which calls it
# directly, at phase 4 by construction — is untouched. An unreadable or absent
# phase record is SILENT, which is the same fail-open direction as everything
# else here; the hard refusal lives at the cut, not at a session greeting.
#
# NOT under `set -e` — fail-open is the whole point; a mid-check error must
# degrade to exit 0, not abort the shell.

set -uo pipefail   # deliberately NO -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
[ -n "$SCRIPT_DIR" ] || exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)" || PROJECT_DIR=""
fi
[ -n "$PROJECT_DIR" ] || exit 0
[ -d "$PROJECT_DIR" ] || exit 0

checker="$SCRIPT_DIR/check-maintenance.sh"
[ -f "$checker" ] || exit 0

# The era gate — see the block above. jq when it is there, a digit scrape when
# it is not, and silence when neither can produce a phase.
phase=""
if [ -f "$PROJECT_DIR/.claude/phase-state.json" ]; then
  if command -v jq >/dev/null 2>&1; then
    phase="$(jq -r '.current_phase // ""' "$PROJECT_DIR/.claude/phase-state.json" 2>/dev/null)" || phase=""
  else
    phase="$(awk -F'"current_phase"' 'NF > 1 { s = $2; gsub(/[^0-9]/, " ", s); split(s, a, " "); for (i in a) if (a[i] != "") { print a[i]; exit } }' \
      "$PROJECT_DIR/.claude/phase-state.json" 2>/dev/null)" || phase=""
  fi
fi
case "$phase" in ''|*[!0-9]*) exit 0 ;; esac
[ "$phase" -ge 4 ] || exit 0                                                   # CADENCE-NAG-ERA-GATE

out=""
rc=0
out="$( cd "$PROJECT_DIR" 2>/dev/null && bash "$checker" </dev/null 2>/dev/null )" || rc=$?

headline=""
case "$rc" in
  0) exit 0 ;;
  1) headline="[maintenance] a cadence is OVERDUE. A release cut will refuse until it is cleared." ;;
  2) headline="[maintenance] a cadence COULD NOT BE MEASURED. Unmeasurable is not current — a release cut refuses on this too." ;;
  *) exit 0 ;;                                                                 # CADENCE-NAG-FAILOPEN
esac

# The verdict lines the headline is ABOUT — built BEFORE anything is printed, and
# capped so a pathological tree cannot flood a session's opening context. awk
# drains its input rather than `head` closing the pipe early (the SIGPIPE trap).
body="$(printf '%s\n' "$out" \
  | awk '/OVERDUE|CANNOT MEASURE|COULD NOT BE MEASURED/ { if (n < 10) { print "  " $0; n = n + 1 } }')"

# NO EVIDENCE, NO HEADLINE (R-WP6-3).
#
# rc 1 is also what a shell hands back when it aborts under `set -e`, so a
# checker that DIED is indistinguishable from one that measured an overdue —
# by the exit code alone. A crash that printed nothing therefore used to produce
# "a cadence is OVERDUE" with nothing underneath it: a claim this hook cannot
# support, at the surface where a human forms their first impression of the
# project's health. Fail-open held (it still exited 0) but the sentence was
# false, which is the same disease as the one this whole WP exists to close,
# one surface up.
#
# So the verdict lines are the evidence, and no evidence means the silent
# fail-open path rather than a louder guess. It costs nothing real: the checker
# prints at least one OVERDUE line whenever it means 1 and at least one CANNOT
# MEASURE line whenever it means 2, so a healthy refusal always carries its
# reason with it. H8 pins both directions and m6 is its mutant.
[ -n "$body" ] || exit 0                                                       # CADENCE-NAG-EVIDENCE

printf '%s\n' "$headline"
printf '%s\n' "$body"
printf '%s\n' "  Run: bash scripts/check-maintenance.sh"
exit 0
