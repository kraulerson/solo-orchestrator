#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Maintenance Cadence Check
#
# SPEC: docs/designs/2026-08-02-delta-track-v1.md §8.3 (the CALENDAR-based
# re-fire trigger — the threshold table, the three notes, the author-proposed
# `exit 2`, and the two enforcement points), §0.3-C1 (this script ALREADY
# SHIPS: WP6 wires its invocation and does not re-ship it), §0.3-C2 (the
# script/guide split), §7.2 (the `cadence` policy keys), §11-WP6, §13-R14 (the
# honest evidence residual, restated below rather than quietly dropped).
# Closes BL-213.
#
# (No `# BL-NNN-…` marker anywhere in the delta track on purpose — no backlog
# entry exists for this build, and minting one would red
# scripts/lint-bl-markers.sh, whose first pass resolves every marker to a real
# `## BL-NNN:` entry. The design-doc path above is the citation, per the WP1-WP5
# precedent. The grep-able `CADENCE-*` markers below are this file's citation
# primitive and its mutation addresses. BL-213 is named in prose because it is
# the BUG this file closes, not a code marker.)
#
# Usage: bash scripts/check-maintenance.sh
#
# ═════════════════════════════════════════════════════════════════════════════
# THE EXIT CONTRACT — WRITTEN FOR WP7, READ IT BEFORE CHANGING AN ARM
#
#   0  every APPLICABLE cadence was MEASURED and is current
#   1  one or more cadences are OVERDUE
#   2  one or more cadences COULD NOT BE MEASURED, and none is overdue
#
# WP7's release cut (§9.2) REFUSES ON 1 AND ON 2. Unmeasurable is not a pass:
# a cadence nobody could read must not be silently satisfiable at a tag. 2 is
# deliberately the ZERO-OVERDUE code — when both are true the answer is 1, so a
# real overdue is never hidden behind an unreadable date; the unmeasurable ones
# are still named in the report either way.
#
# ═════════════════════════════════════════════════════════════════════════════
# WHY 2 EXISTS AT ALL — BL-213, AND THE DEFECT THIS FILE USED TO BE
#
# Until WP6 every verdict here sat inside `if [ "$last_epoch" -gt 0 ]`, and
# `last_epoch` came from a `date -j -f … || date -d … || echo "0"` tail. A date
# neither parser accepted therefore resolved to 0, the guard was false, and THE
# WHOLE ARM WAS SKIPPED IN SILENCE: no print, no counter — and the script closed
# with "All maintenance cadences current." at exit 0 over evidence it had never
# read. §14-V13 logs the executed run (an untracked CHANGELOG.md plus a lone
# `2026-13-45_semgrep_pass.txt`): one INFO line, nothing at all for the security
# arm, rc 0. The docblock advertised a "2 — could not determine" that no code
# path produced.
#
# THE DIRECTION IS THE POINT. That was fail-OPEN: an unreadable signal was
# indistinguishable from a fresh one. A design reviewer proposed the opposite
# mechanism — an unparseable date falling through into a huge `days_since` and
# exiting 1 — and the `-gt 0` guard refutes it. A fail-CLOSED checker would have
# over-blocked a release cut (annoying, safe); the fail-OPEN one that shipped
# would have let a release pass a cadence that was never really measured.
#
# The repair has three parts and all three are load-bearing:
#   1. `cadence_epoch` returns NON-ZERO AND PRINTS NOTHING when neither parser
#      accepts its input. There is no default and no third answer — a
#      `|| echo "0"` tail is the exact shape that manufactured the sentinel.
#   2. Every arm that cannot date its signal calls `mark_undetermined`, which
#      holds the ONLY line that moves the counter (`# CADENCE-UNDETERMINED-COUNTER`).
#      tests/test-delta-wp6-cadence.sh::m2 removes that one line and asserts the
#      unparseable fixture reports "All maintenance cadences current" at rc 0
#      again — on the EXIT CODE, never on the sentence.
#   3. The closing verdict reports the counter as exit 2.
#
# ═════════════════════════════════════════════════════════════════════════════
# APPLICABLE vs UNMEASURABLE — ONE RULE, STATED ONCE
#
#   A signal surface that DOES NOT EXIST is NOT APPLICABLE. A project with no
#   CHANGELOG.md, no sbom.json or no docs/test-results/ is told so, and no
#   counter moves. Absence of an artefact is a legitimate project shape and the
#   framework does not invent a verdict for it.
#
#   A signal surface that EXISTS but cannot be DATED is UNDETERMINED. A
#   CHANGELOG.md or sbom.json with no git history, a docs/test-results/ holding
#   no scan artefact at all (the policy-expected-but-missing signal), an
#   artefact whose filename carries no date, and a date no parser accepts are
#   all the same answer — "I could not measure this" — and all of them reach
#   exit 2.
#
#   RESIDUAL, STATED RATHER THAN HIDDEN: a project that has never produced ANY
#   of the three surfaces still exits 0. This checker measures a CADENCE; it
#   does not audit whether a maintenance practice exists. Widening that would
#   make every pre-Phase-3 tree unmeasurable and is a design change, not a
#   tweak — tests/test-delta-wp6-cadence.sh::E8 pins the boundary so it can only
#   move deliberately.
#
# ═════════════════════════════════════════════════════════════════════════════
# WHAT THE SIGNALS ACTUALLY PROVE (§13-R14) — DO NOT OVERSELL THIS
#
#   The deep-scan cadence reads a DATE PARSED OUT OF A FILENAME in
#   docs/test-results/. A file named with today's date and containing nothing
#   satisfies it completely. Tightening the clock (185 -> 95 days, and 35 -> 14
#   on the routine arms) makes the SCHEDULE stricter; it does NOT make the
#   EVIDENCE stronger, and nothing here should be read as a security
#   improvement. The one honest evidence gain in WP6 is negative: a filename
#   whose date nobody can read is no longer reported as fresh.
#
#   THREE SHAPES OF THAT RESIDUAL, MEASURED BY THE WP6 REVIEW AND NAMED HERE SO
#   THE DISCLOSURE IS NOT NARROWER THAN THE BEHAVIOUR. Filed as backlog lines;
#   none is changed by this WP, and the glob set is inherited verbatim from the
#   pre-WP6 script:
#     • SUBSTRING BREADTH (R-WP6-4). `*dep*` matches far more than a dependency
#       audit — `deployment-notes-<date>.md` satisfies the cadence completely.
#       The fold raises the stakes: one stray match now satisfies the WHOLE
#       deep-security clock, which is what the release cut reads.
#     • NON-FILE ARTEFACTS (R-WP6-7). A fresh-dated empty DIRECTORY, or a
#       dangling symlink, satisfies it too — `ls` supplies the name and the date
#       is read off the name. One shape wider than "a dated empty file".
#     • CROSS-HOST DATE DIVERGENCE (R-WP6-5). `2026-13-45` is refused by both
#       parsers, but an in-range impossibility like `2026-02-30` NORMALISES on
#       BSD (to 2026-03-02) and is refused by GNU. Both answers refuse a release
#       cut — measured or undetermined — so neither host skips anything
#       silently. Recorded so nobody later "fixes" the divergence by loosening
#       the fail-closed side.
#
# ═════════════════════════════════════════════════════════════════════════════
# THE THRESHOLDS ARE POLICY, NOT CONSTANTS (§8.3 note 3, §7.2)
#
#   routine_review_days  (default 14)  CHANGELOG.md and sbom.json — both were
#                                      35 before D5 tightened them.
#   deep_security_days   (default 95)  the quarterly deep security scan, WITH
#                                      THE DEPENDENCY AUDIT FOLDED IN (§8.3's
#                                      table: the separate 95-day dependency row
#                                      and the 185-day biannual row become ONE
#                                      cadence at 95).
#
#   WHAT "FOLDED IN" COSTS, SAID OUT LOUD: one cadence means one clock over the
#   UNION of the two artefact families (`*snyk*`/`*dep*`/`*audit*` and
#   `*semgrep*`/`*sast*`), so a fresh artefact of either family satisfies it.
#   That is weaker than two independent clocks were at spotting a stale
#   dependency scan behind a fresh SAST run. The alternative — requiring BOTH
#   families — would permanently exit 2 for every project that legitimately
#   attests a skipped dependency scanner under run-phase3-validation.sh's
#   attest-on-skip contract, which is a worse failure than the one it fixes.
#
#   THE READ ROUTES THROUGH THE ONE SEAM, and that is not a style choice. This
#   script is CORE. The post-1.0 track is a SEVERABLE MODULE (D1) and
#   scripts/lint-delta-boundary.sh forbids every core file from naming a module
#   path on an executed line (§3.3 clause 2, tier T1 — NOT inline-waivable),
#   with a file-level seam allowlist whose cardinality is asserted at exactly
#   ONE. So the obvious implementations — a `jq` straight at the policy JSON, or
#   sourcing the module's policy lib — are both unavailable. The read delegates
#   core -> core through the ONE seam, exactly as scripts/upgrade-project.sh's
#   policy notice and scripts/validate.sh's era assertion already do; this is
#   the THIRD instance of that waived routing. The residue is the one waived
#   line below: reaching the seam means naming a seam ACTION FLAG, every seam
#   action carries the `delta-` prefix by design (§3.1), and that prefix is what
#   tier T2 scans for. T2 exists WITH a reason-required inline waiver for
#   exactly this case. Do not rename the action to hide the prefix — that evades
#   the scan below the prefix boundary (§13-R15) and buys nothing.
#
#   ABSENT POLICY — AND AN ABSENT MODULE — MEAN THE FRAMEWORK DEFAULTS. A
#   project that never opened a post-release change still gets a working
#   checker: the seam may be missing, may be an older vendored copy that does
#   not know the action, or may refuse outright, and every one of those falls
#   back to the constants below. The checker does not require the delta module,
#   and today's `init.sh` does not ship it.
#
# ═════════════════════════════════════════════════════════════════════════════
# THE DATE LAYER IS A DELIBERATE DUPLICATE, AND THE REASON IS THE BOUNDARY
#
#   scripts/lib/delta-cadence.sh's `delta_cadence_epoch` is the same idiom with
#   the same no-default contract, and reusing it would be the better
#   engineering. It is a MODULE file, so naming it from here is a tier-T1
#   violation and T1 is not waivable — routing a date parse through the seam
#   instead would make basic arithmetic depend on an optional module and would
#   still need this fallback anyway. The duplication is the price of
#   severability, recorded here so the next reader does not "fix" it by adding a
#   core -> module edge. If the two ever disagree they are wrong together.
#
#   BOTH normalise a bare `YYYY-MM-DD` to `T00:00:00Z` BEFORE either parser sees
#   it, and that is a real bug fix, not tidiness: BSD's `date -j -f` fills fields
#   the format did not specify FROM THE CURRENT TIME, so the pre-WP6 spelling in
#   this file answered a different number on every call and a different number
#   from GNU's answer for the same input. The two hosts now agree exactly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# BL-046: uses print_info / print_ok / print_warn only — source core subset.
source "$SCRIPT_DIR/lib/helpers-core.sh"

# ── Framework defaults (§7.2). A project overrides these in ITS policy file,
# never by editing this script. ────────────────────────────────────────────────
ROUTINE_DEFAULT_DAYS=14                                                        # CADENCE-DEFAULT-ROUTINE
DEEP_DEFAULT_DAYS=95                                                           # CADENCE-DEFAULT-DEEP

overdue=0
undetermined=0
UNMEASURED=""
now_epoch="$(date -u +%s)"

# cadence_policy_days <cadence-key> <framework-default>
#   The project's threshold for one cadence, or the framework default when the
#   policy, the key, the module or the seam is absent. Fail-soft in every
#   direction — see the seam block in this file's header for why the read is a
#   delegation and not a `jq`.
cadence_policy_days() {
  local key="$1" def="$2" seam="$SCRIPT_DIR/process-checklist.sh" v=""
  if [ -f "$seam" ]; then
    v="$( bash "$seam" --delta-policy-get "cadence.$key" </dev/null 2>/dev/null )" || v=""   # CADENCE-POLICY-READ  # lint-delta-boundary: allow core->core delegation to the ONE declared seam — this names the seam's action FLAG, never a module path (T1 is clean) and the seam allowlist stays at cardinality 1 (§3.1/§3.3)
  fi
  # A non-numeric, empty or multi-line answer is not a threshold. It falls back
  # rather than reaching the arithmetic below, where it would abort the script
  # under `set -e` and take every remaining cadence with it.
  case "$v" in ''|*[!0-9]*) v="$def" ;; esac
  printf '%s\n' "$v"
}

# cadence_epoch <stamp>
#   `YYYY-MM-DD` or `YYYY-MM-DDTHH:MM:SSZ` -> UTC epoch seconds on stdout, rc 0.
#   rc 1 AND NOTHING ON STDOUT when neither parser accepts it.
#
#   The `case` gate is a SHAPE check, not a validity check: it rejects inputs
#   that are not date-shaped at all (empty, `banana`, a stamp with a numeric
#   offset instead of `Z`) and passes date-SHAPED nonsense like `2026-13-45`
#   through to the real parser, which is what must refuse it. A gate that tried
#   to validate month and day ranges here would be a second, worse date library.
cadence_epoch() {
  local s="${1:-}" e=""
  case "$s" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
      s="${s}T00:00:00Z" ;;                                                    # CADENCE-BARE-DATE
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z)
      : ;;
    *) return 1 ;;
  esac
  e="$(date -u -d "$s" +%s 2>/dev/null)" || e=""
  if [ -z "$e" ]; then
    e="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$s" +%s 2>/dev/null)" || e=""
  fi
  case "$e" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s\n' "$e"
  return 0
}

# mark_undetermined <cadence-label> <why>
#   THE ONLY PLACE THE UNDETERMINED COUNTER MOVES. This is BL-213's repair: with
#   the marked line removed the arm still prints, and the script still closes
#   with "All maintenance cadences current." at rc 0 — a clean bill of health
#   over evidence nobody read. That mutant is m2 in the WP6 suite and it asserts
#   on the exit code, because the printed label and the exit predicate are
#   exactly the pair CLAUDE.md's `[WARN]` trap warns can disagree.
mark_undetermined() {
  undetermined=$((undetermined + 1))                                           # CADENCE-UNDETERMINED-COUNTER
  UNMEASURED="${UNMEASURED}  - $1: $2
"
  print_warn "$1 — CANNOT MEASURE: $2"
}

# cadence_verdict <label> <threshold-days> <date-string>
#   One arm's whole answer. An unreadable date is UNDETERMINED, never skipped —
#   the arm that used to disappear here is the defect.
cadence_verdict() {
  local label="$1" limit="$2" d="$3" e days
  if ! e="$(cadence_epoch "$d")"; then                                         # CADENCE-FAIL-CLOSED-DATE
    mark_undetermined "$label" "the recorded date '$d' is not one any date parser on this host accepts"
    return 0
  fi
  days=$(( (now_epoch - e) / 86400 ))
  if [ "$days" -gt "$limit" ]; then
    print_warn "$label OVERDUE: last signal $days days ago (threshold: $limit days)"
    overdue=$((overdue + 1))
  else
    print_ok "$label current: last signal $days days ago (threshold: $limit days)"
  fi
  return 0
}

# cadence_git_date <path>
#   The `YYYY-MM-DD` of the newest commit that touched <path>, or the EMPTY
#   STRING when there is no history to read (untracked file, or not a repo).
#   Empty is not a date and the caller turns it into UNDETERMINED — which is the
#   whole difference from the shipped behaviour, where it became an INFO line
#   and an unchanged verdict.
cadence_git_date() {
  local p="$1" line=""
  line="$(git log -1 --format='%ai' -- "$p" 2>/dev/null)" || line=""
  printf '%s\n' "$line" | awk '{ print $1 }'
}

echo -e "${BOLD}Maintenance Cadence Check${NC}"
echo ""

ROUTINE_DAYS="$(cadence_policy_days routine_review_days "$ROUTINE_DEFAULT_DAYS")"
DEEP_DAYS="$(cadence_policy_days deep_security_days "$DEEP_DEFAULT_DAYS")"

signal_date=""
latest_scan=""

# --- Routine review: CHANGELOG.md (§8.3, was 35 days) ------------------------
if [ -f "CHANGELOG.md" ]; then
  signal_date="$(cadence_git_date CHANGELOG.md)"
  if [ -n "$signal_date" ]; then
    cadence_verdict "Routine review (CHANGELOG.md)" "$ROUTINE_DAYS" "$signal_date"
  else
    mark_undetermined "Routine review (CHANGELOG.md)" \
      "the file is present but has no git history, so its age cannot be read"
  fi
else
  print_info "No CHANGELOG.md — the routine-review cadence has no signal here (not applicable)"
fi

# --- Routine review: sbom.json (§8.3, was 35 days) ---------------------------
if [ -f "sbom.json" ]; then
  signal_date="$(cadence_git_date sbom.json)"
  if [ -n "$signal_date" ]; then
    cadence_verdict "Routine review (sbom.json)" "$ROUTINE_DAYS" "$signal_date"
  else
    mark_undetermined "Routine review (sbom.json)" \
      "the file is present but has no git history, so its age cannot be read"
  fi
else
  print_info "No sbom.json — the SBOM refresh cadence has no signal here (not applicable)"
fi

# --- Deep security scan, dependency audit FOLDED IN (§8.3, was 185 + 95) -----
# The date comes out of the FILENAME (§13-R14): a dated empty file satisfies
# this completely. `ls -t` is drained by awk rather than `head -1` on purpose —
# an early-exiting downstream stage SIGPIPEs the writer and `pipefail` promotes
# rc 141 into the substitution, which under `set -e` is an abort, not a verdict.
#
# AND `ls` IS EXPLICITLY ABSOLVED (`|| true`) RATHER THAN LEFT TO THE OUTER `||`.
# Five globs are passed and most projects match only one or two; the unmatched
# ones reach `ls` as literals and make it exit 1. With `pipefail` that promotes
# to the substitution, and an outer `|| latest_scan=""` would then WIPE a
# perfectly good filename — turning "one fresh scan, four families absent" into
# "no evidence at all", which is an exit 2 nobody could explain. Caught by E1
# going rc 2 on an all-current fixture.
if [ -d "docs/test-results" ]; then
  latest_scan="$( { ls -t docs/test-results/*snyk* docs/test-results/*dep* \
                         docs/test-results/*audit* docs/test-results/*semgrep* \
                         docs/test-results/*sast* 2>/dev/null || true; } \
                 | awk 'NR == 1 { r = $0 } END { if (r != "") print r }')" || latest_scan=""
  if [ -n "$latest_scan" ]; then
    signal_date="$(printf '%s\n' "$latest_scan" \
      | awk 'match($0, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) { print substr($0, RSTART, RLENGTH) }')" \
      || signal_date=""
    if [ -n "$signal_date" ]; then
      cadence_verdict "Deep security scan (dependency audit folded in)" "$DEEP_DAYS" "$signal_date"
    else
      mark_undetermined "Deep security scan (dependency audit folded in)" \
        "the newest artefact '$latest_scan' carries no date in its filename"
    fi
  else
    mark_undetermined "Deep security scan (dependency audit folded in)" \
      "docs/test-results/ exists but holds no dependency- or security-scan artefact"
  fi
else
  print_info "No docs/test-results/ — the deep-security cadence has no evidence surface here (not applicable)"
fi

echo ""
if [ "$undetermined" -gt 0 ]; then
  echo -e "${YELLOW}${BOLD}$undetermined maintenance cadence(s) COULD NOT BE MEASURED:${NC}"
  printf '%s' "$UNMEASURED"
  echo ""
fi

if [ "$overdue" -gt 0 ]; then
  echo -e "${YELLOW}${BOLD}$overdue maintenance cadence(s) overdue.${NC}"
  echo ""
  echo "Recommended actions:"
  echo "  Routine review (default every 14 days): dependency and security patches, SBOM refresh,"
  echo "    error-dashboard review, CHANGELOG entry"
  echo "  Deep security scan (default every 95 days): full dependency audit, Phase 3 re-run,"
  echo "    platform-requirement review"
  echo ""
  # The policy FILE is deliberately not named on this line: it is a module path,
  # and T1 (scripts/lint-delta-boundary.sh) is not waivable even for prose in a
  # string. The keys are enough for anyone who has the file, and a project
  # without the module has nothing to open anyway.
  echo "Both windows are policy, not constants: cadence.routine_review_days and"
  echo "cadence.deep_security_days in the project's post-1.0 policy file. After maintenance,"
  echo "commit with 'chore: routine maintenance [date]' so the timestamps move."
  exit 1
elif [ "$undetermined" -gt 0 ]; then                                           # CADENCE-EXIT-UNDETERMINED
  echo "Nothing above is overdue — but the cadences named there were never measured, so"
  echo "'current' is not something this check can claim. Give each one a signal it can read"
  echo "(commit the file, or re-run the scan so a correctly dated artefact lands in"
  echo "docs/test-results/) and run this again. A release cut refuses on this exit code."
  exit 2
else
  echo -e "${GREEN}${BOLD}All maintenance cadences current.${NC}"
  exit 0
fi
