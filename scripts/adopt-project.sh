#!/usr/bin/env bash
# scripts/adopt-project.sh — the brownfield ADOPTION DRIVER.
#
# Point it at a project that already exists and it walks the operator through
# bringing that project under the framework: it reads Scout's survey, asks the
# one question only a person can answer, confirms the facts the scan already
# found, insists on the ones the scan can never find, writes the project's
# state, stamps the adoption, and commits — exactly the files it wrote and
# nothing else.
#
#   cd /path/to/their-project
#   bash /path/to/solo-orchestrator/scripts/adopt-project.sh
#
#   --root DIR            the project to adopt (default: the current directory)
#   --scan-report FILE    a Scout JSON report to consume instead of running one
#   --version / --help
#
# SPEC: docs/designs/2026-08-02-brownfield-adoption-v1.md §8.1 (the driver, and
# why it is NOT a mode of init.sh), §4.1 (the chooser, in Karl's exact words),
# §4.2 (the scanner OFFERS evidence, it does not decide), §4.3/§4.4 (S1 and S2
# landing, and the FLOOR rule), §4.5 (what both scenarios share), §8.3 (reverse
# intake), §8.4 (the fail-safe state-creation ORDER), §8.5 (explicit staging
# and the adoption stamp), §5.5 ("adoption does not complete" must be SAFE),
# §10-WP4. The standing module rules are docs/module-contract.md.
#
# ─────────────────────────────────────────────────────────────────────────────
# WHY THIS IS A SEPARATE SCRIPT AND NOT `init.sh --brownfield` (§8.1, §1.2)
#
# init.sh's interactive path has NO existence check at all and twelve of its
# write sites are unguarded overwrites. A `--brownfield` flag would mean
# auditing every one of those sites for a mode that must never reach them; a
# separate driver makes them unreachable BY CONSTRUCTION. This driver therefore
# never calls create_project(), and reuses init's work only BY EXTRACTION.
#
# ─────────────────────────────────────────────────────────────────────────────
# M2 — THE DECLARED CORE DEPENDENCIES (docs/module-contract.md)
#
# This module is SEVERABLE, not isolated: unlike Scout it may source core, and
# the complete list of core libs it is permitted to source is:
#
#   scripts/lib/helpers-core.sh          print_* and guard_not_in_framework
#   scripts/lib/adoption-stamp.sh        the WP3 in-core enabling arms — the
#                                        `adopted` accessor and the stamp. THIS
#                                        DRIVER IS THE STAMP'S ONE CALL SITE.
#   scripts/lib/scaffold-shipped-set.sh  soif_parse_shipped_scripts, so the set
#                                        of framework scripts an adoptee
#                                        receives is DERIVED from init.sh's own
#                                        copy list rather than duplicated here
#
# Direction (M3) holds in one direction only: this module sources core, and no
# core file names this module. That is why `init.sh` does NOT ship
# `adopt-project.sh` — see the SHIPPING note at the bottom of this header.
#
# ─────────────────────────────────────────────────────────────────────────────
# THE GUARD FIRES BEFORE ARGUMENT PARSING, DELIBERATELY (§8.1)
#
# process-checklist.sh and reconfigure-project.sh both call
# guard_not_in_framework at source time, before parsing, so even `--help` exits
# 1 inside the framework repo. This driver carries the same posture rather than
# a politer one, because the failure it prevents is writing framework state
# into the framework. Its tests therefore run in fixtures, never in-tree.
#
# ─────────────────────────────────────────────────────────────────────────────
# `set -e` IS DELIBERATELY ABSENT, and the alternative is stated rather than
# assumed. The driver is a long interactive sequence whose FALSE branches are
# ordinary data (no CHANGELOG, no tags, an operator who answers "change it").
# Under errexit each of those is an abort unless individually suppressed, and a
# missed suppression aborts a WRITER halfway with no message. Instead: nounset
# and pipefail are on, EVERY write goes through adopt_write_* which checks its
# own result and refuses loudly, and the exit code is set explicitly.
#
# ─────────────────────────────────────────────────────────────────────────────
# SHIPPING: THIS SCRIPT IS NOT SHIPPED INTO SCAFFOLDED PROJECTS, ON PURPOSE.
# `init.sh` is CORE and `scripts/adopt-project.sh` is MODULE, so a `cp` line for
# this file in init.sh is exactly the `core -> module` edge M3 forbids and
# scripts/lint-module-dependencies.sh rejects (T1 on the basename, T2 on the
# path token). Nothing shipped references this driver, so
# tests/test-scaffold-source-closure.sh has nothing to say about it either. The
# driver runs FROM the framework clone against an adoptee, the same way Scout
# does. What the ADOPTEE receives is the ordinary shipped script set, installed
# by this driver from init.sh's own copy list (see adopt_install_framework).
set -uo pipefail

ADOPT_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
ADOPT_FRAMEWORK_ROOT="$(cd "$ADOPT_SELF_DIR/.." && pwd)"
ADOPT_LIB_DIR="$ADOPT_SELF_DIR/lib/adopt"
ADOPT_CORE_LIB_DIR="$ADOPT_SELF_DIR/lib"

# ── Core libs (M2's declared set) ───────────────────────────────────────────
for _core in helpers-core.sh adoption-stamp.sh scaffold-shipped-set.sh; do
  if [ ! -f "$ADOPT_CORE_LIB_DIR/$_core" ]; then
    echo "adopt-project: missing $ADOPT_CORE_LIB_DIR/$_core — run this from a complete framework clone." >&2
    exit 2
  fi
  # shellcheck disable=SC1090
  . "$ADOPT_CORE_LIB_DIR/$_core"
done

# THE GUARD, BEFORE ARGUMENT PARSING — see the header. Sibling posture, kept.
guard_not_in_framework || exit 1

for _part in adopt-core adopt-chooser adopt-intake adopt-state adopt-stubs; do
  if [ ! -f "$ADOPT_LIB_DIR/$_part.sh" ]; then
    echo "adopt-project: missing $ADOPT_LIB_DIR/$_part.sh — the driver needs its own lib directory." >&2
    exit 2
  fi
  # shellcheck disable=SC1090
  . "$ADOPT_LIB_DIR/$_part.sh"
done

usage() {
  cat <<'USAGE'
adopt-project — bring an existing project under the framework.

  cd /path/to/their-project
  bash /path/to/solo-orchestrator/scripts/adopt-project.sh [options]

  --root DIR          the project to adopt (default: the current directory)
  --scan-report FILE  consume this Scout report instead of running a new scan
  --version           print the driver's version and exit
  --help              print this and exit

What it does, in order: reads the survey, offers what the survey found as
EVIDENCE, asks you the one question the survey cannot answer, confirms the
answers it already has and insists on the ones it does not, writes the
project's state, records the adoption, and commits exactly the files it wrote.

If it stops partway — because you stopped it, or because a question had no
answer — it stops in the SAFE direction: the project ends up more strictly
gated than it was, never less.

Exit codes: 0 adoption completed; 1 adoption did not complete (a refusal, a
blocker, or a halt); 2 bad usage or an unusable target.
USAGE
}

ADOPT_ROOT="."
ADOPT_REPORT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)          [ "$#" -ge 2 ] || { echo "adopt-project: --root needs a directory" >&2; exit 2; }; ADOPT_ROOT="$2"; shift 2 ;;
    --root=*)        ADOPT_ROOT="${1#--root=}"; shift ;;
    --scan-report)   [ "$#" -ge 2 ] || { echo "adopt-project: --scan-report needs a file" >&2; exit 2; }; ADOPT_REPORT="$2"; shift 2 ;;
    --scan-report=*) ADOPT_REPORT="${1#--scan-report=}"; shift ;;
    --version)       adopt_module_version; exit 0 ;;
    -h|--help)       usage; exit 0 ;;
    *)               echo "adopt-project: unrecognised option '$1'" >&2; echo "" >&2; usage >&2; exit 2 ;;
  esac
done

ADOPT_ROOT_ABS="$(cd "$ADOPT_ROOT" 2>/dev/null && pwd)"
if [ -z "$ADOPT_ROOT_ABS" ]; then
  echo "adopt-project: '$ADOPT_ROOT' is not a directory this can read." >&2
  exit 2
fi
# The target arm of the same guard: --root must not point at a framework clone
# either (the security-audits-1 vector that the cwd-only check missed).
guard_not_in_framework "$ADOPT_ROOT_ABS" || exit 1

adopt_main "$ADOPT_ROOT_ABS" "$ADOPT_REPORT"
exit $?
