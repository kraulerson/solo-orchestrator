#!/usr/bin/env bash
# scripts/scout.sh — Scout: a read-only look at a codebase.
#
# Point it at a project you are thinking about adopting. It reads, it reports,
# and it changes nothing. You do not have to install anything, decide anything,
# or run the framework first — that is the whole idea. A survey that requires
# installing the thing it is surveying is not a survey.
#
#   bash scripts/scout.sh                       # JSON report for the current directory
#   bash scripts/scout.sh --root ../their-app   # …for somewhere else
#   bash scripts/scout.sh --markdown            # the same findings, written for a person
#   bash scripts/scout.sh --out ./scan          # write both files into ./scan
#   bash scripts/scout.sh --help
#
# SPEC: docs/designs/2026-08-02-brownfield-adoption-v1.md §3.1 (Scout's home
# and its standalone packaging), §3.3 M1/M5, §4.1 (the operator-facing
# register), §4.2, §4.4, §8.2 (the report schema is normative), §10-WP1. The
# standing module rules are in docs/module-contract.md.
#
# ─────────────────────────────────────────────────────────────────────────────
# THE TWO PROPERTIES EVERYTHING ELSE SERVES
#
# READ-ONLY. Scout writes nothing into the tree it is pointed at. Not a cache,
# not a state file, not a marker. Its only writes are (a) a private working
# directory under $TMPDIR, removed on exit, and (b) the two report files, and
# only when you ask for them with `--out`. The proof is not this paragraph: it
# is tests/test-brownfield-wp1-scout.sh R1/R2, which hash every path, mode and
# byte of a fixture — `.git/` included — before and after a scan and require
# them to be identical. R3 proves that instrument can register a change, and X2
# re-introduces a state write and requires R1/R2 to go red on it.
#
# ZERO DEPENDENCY (M5). Scout sources no core library, calls no other script in
# this repository, and does not need jq. `scripts/scout.sh` plus
# `scripts/lib/scout/` is the entire program. H1 copies exactly those files
# into an otherwise empty directory and runs a full scan there; H2 takes a
# whole copy of `scripts/`, moves every core lib AND every other entry script
# aside, and requires the scan to still work — that second half is the WP0
# review's carry-forward (R-WP0-3), because the module lint's M5 arm forbids
# core LIB basenames only, so a Scout file that shelled out to a core entry
# script would pass the lint clean.
#
# WHAT IT REPORTS
# This build emits all seven of §8.2's sections: `stack`, `phaseMap`,
# `reality`, `secrets`, `collisions`, `testsBaseline`, `intakePrefill`.
# `sectionsNotEmitted` survives as an empty array rather than being deleted,
# because "we have not looked yet" and "we looked and it was clean" are
# different claims and a consumer must keep being able to tell them apart —
# for the secrets section that difference has a credential behind it. Within
# `secrets` the same distinction is carried by `status`, which is
# `tool-unavailable` when nobody looked and `scanned` when somebody did.
#
# THE ONE PLACE SCOUT RUNS PROJECT CODE is `--run-tests`, and it is opt-in for
# that reason. Without it `testsBaseline.commandRan` is false and the report
# says why.
#
# ─────────────────────────────────────────────────────────────────────────────
# `set -e` IS DELIBERATELY ABSENT, and this is the one place worth arguing.
# Scout is almost entirely predicates whose FALSE is data: no remote, no
# lockfile, no architecture document. Under `errexit` each of those becomes an
# abort unless it is individually suppressed, and the failure mode of a missed
# suppression is a scan that stops halfway and reports a partial tree as a
# complete one — silent, and in the direction of false confidence. `nounset`
# and `pipefail` are on, every write is checked at its site, and the exit code
# is set explicitly at the end.
set -uo pipefail

SCOUT_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SCOUT_LIB_DIR="$SCOUT_SELF_DIR/lib/scout"

for _part in scout-core scout-stack scout-phasemap scout-reality \
             scout-secrets scout-collisions scout-testsbaseline scout-prefill \
             scout-report; do
  if [ ! -f "$SCOUT_LIB_DIR/$_part.sh" ]; then
    echo "scout: missing $SCOUT_LIB_DIR/$_part.sh — Scout needs its own lib directory beside it." >&2
    exit 2
  fi
  # shellcheck disable=SC1090
  . "$SCOUT_LIB_DIR/$_part.sh"
done

usage() {
  cat <<'USAGE'
Scout — a read-only look at a codebase.

  bash scripts/scout.sh [--root DIR] [--markdown] [--out DIR]

  --root DIR    the project to look at (default: the current directory)
  --markdown    print the human-readable report instead of the JSON one
  --out DIR     write BOTH reports into DIR as scout-report.json and
                scout-report.md, and print where they went
  --run-tests   ALSO run the project's own test command, once, to record
                whether it passes today. This is the only thing Scout does
                that runs your code, so it is off unless you ask. Bounded by
                SCOUT_TEST_TIMEOUT seconds (default 300).
  --version     print Scout's version and exit
  --help        print this and exit

Scout never changes the project it looks at. Without --out it writes nothing
at all except its own output. It needs `gitleaks` for the secrets section; if
that is missing the section says so rather than reporting a clean scan.

Exit codes: 0 a scan completed (findings are not errors); 2 bad usage or an
unreadable target.
USAGE
}

ROOT="."
MODE="json"
OUTDIR=""
RUN_TESTS=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)      [ "$#" -ge 2 ] || { echo "scout: --root needs a directory" >&2; exit 2; }; ROOT="$2"; shift 2 ;;
    --root=*)    ROOT="${1#--root=}"; shift ;;
    --out)       [ "$#" -ge 2 ] || { echo "scout: --out needs a directory" >&2; exit 2; }; OUTDIR="$2"; shift 2 ;;
    --out=*)     OUTDIR="${1#--out=}"; shift ;;
    --markdown)  MODE="markdown"; shift ;;
    --json)      MODE="json"; shift ;;
    --run-tests) RUN_TESTS=1; shift ;;
    --version)   scout_module_version; exit 0 ;;
    -h|--help)   usage; exit 0 ;;
    *)           echo "scout: unrecognised option '$1'" >&2; echo "" >&2; usage >&2; exit 2 ;;
  esac
done

ROOT_ABS="$(scout_abs "$ROOT")"
if [ -z "$ROOT_ABS" ]; then
  echo "scout: '$ROOT' is not a directory Scout can read." >&2
  exit 2
fi

# The private work directory. Everything Scout computes is staged here as
# tab-separated files and removed on exit — bash 3.2 has no associative arrays,
# and staging beats trying to thread a dozen parallel arrays through five libs.
SCOUT_WORK="$(mktemp -d 2>/dev/null)" || {
  echo "scout: could not create a temporary working directory." >&2
  exit 2
}
trap 'rm -rf "$SCOUT_WORK"' EXIT INT TERM

# The file list is walked ONCE and reused. Two libs need it, and walking a
# large repository twice is the difference between a scan you run casually and
# one you schedule.
SCOUT_FILES_LIST="$SCOUT_WORK/files"
scout_walk_files "$ROOT_ABS" > "$SCOUT_FILES_LIST"

printf '%s\n' "$(scout_now_utc)"                 > "$SCOUT_WORK/scannedAt"
printf '%s\n' "$ROOT_ABS"                        > "$SCOUT_WORK/repoRoot"
printf '%s\n' "$(scout_head_commit "$ROOT_ABS")" > "$SCOUT_WORK/headCommit"

# Order matters in exactly one place: the phase ladder's third rung asks
# whether there is a test corpus THAT RUNS, so it needs the test command the
# stack scan discovers.
scout_stack_scan    "$ROOT_ABS" "$SCOUT_WORK"
scout_phasemap_scan "$ROOT_ABS" "$SCOUT_WORK"
scout_reality_probes "$ROOT_ABS" "$SCOUT_WORK"

# The WP2 sections, and their order is a dependency order too. `testsBaseline`
# reuses the test command the stack scan discovered rather than re-deriving it
# — two derivations of one fact are two chances to disagree about it — and
# `intakePrefill` reads both that and the reality probes' remote answer.
scout_secrets_scan       "$ROOT_ABS" "$SCOUT_WORK"
scout_collisions_scan    "$ROOT_ABS" "$SCOUT_WORK"
scout_testsbaseline_scan "$ROOT_ABS" "$SCOUT_WORK" "$RUN_TESTS"
scout_prefill_scan       "$ROOT_ABS" "$SCOUT_WORK"

if [ -n "$OUTDIR" ]; then
  if ! mkdir -p "$OUTDIR" 2>/dev/null; then
    echo "scout: could not create the output directory '$OUTDIR'." >&2
    exit 2
  fi
  OUT_ABS="$(scout_abs "$OUTDIR")"
  scout_emit_json     "$SCOUT_WORK" > "$OUT_ABS/scout-report.json" || {
    echo "scout: could not write $OUT_ABS/scout-report.json" >&2; exit 2; }
  scout_emit_markdown "$SCOUT_WORK" > "$OUT_ABS/scout-report.md" || {
    echo "scout: could not write $OUT_ABS/scout-report.md" >&2; exit 2; }
  printf 'Wrote %s\n' "$OUT_ABS/scout-report.json"
  printf 'Wrote %s\n' "$OUT_ABS/scout-report.md"
  exit 0
fi

if [ "$MODE" = "markdown" ]; then
  scout_emit_markdown "$SCOUT_WORK"
else
  scout_emit_json "$SCOUT_WORK"
fi
exit 0
