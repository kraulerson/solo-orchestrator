#!/usr/bin/env bash
# scripts/lint-user-guide-scripts.sh — the user guide's "Quick Reference —
# Scripts" table must agree with what the scaffold actually ships.
#
# THE CONTRACT
#   docs/user-guide.md carries a hand-written table of scripts, their purpose
#   and how to invoke them. The set of scripts a generated project receives is
#   NOT hand-written: scripts/lib/scaffold-shipped-set.sh derives it from
#   init.sh's literal `cp "$SCRIPT_DIR/scripts/…"` lines, and that derivation is
#   what tests/test-scaffold-source-closure.sh, upgrade-project.sh
#   --sync-framework and the adoption writers all consume. The table was the
#   one surface that read the same truth from memory: at the 2026-09-07 review
#   it listed 19 of 39 shipped top-level scripts and two that were never
#   shipped at all, each marked "Automatic (CI)". `## BL-254:`.
#
# THE TWO DIRECTIONS
#   phantom  — a table row names a script the scaffold does not ship
#   missing  — a shipped TOP-LEVEL script has no row
#   Top-level means scripts/<name>.sh — scripts/lib/*, scripts/hooks/* and
#   scripts/host-drivers/* are internals no operator invokes and are out of
#   scope on purpose; a row for one of them is still checked as a phantom if
#   it is not shipped.
#
# SCOPE IS THE ONE TABLE. Rows are read only between the
# "## Quick Reference — Scripts" heading and the next "## " heading, so the
# evaluation-prompts table elsewhere in the guide (compose.sh, run-reviews.sh
# — which live under evaluation-prompts/, not scripts/) is not misread as a
# claim about scripts/.
#
# Usage:
#   bash scripts/lint-user-guide-scripts.sh            # lint the repo
#   bash scripts/lint-user-guide-scripts.sh --list     # print rows + shipped set
#   --init <init.sh> --scripts-dir <dir> --guide <user-guide.md>   (fixtures)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT="$REPO_ROOT/init.sh"
SCRIPTS_DIR="$REPO_ROOT/scripts"
GUIDE="$REPO_ROOT/docs/user-guide.md"
LIST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --init)        INIT="$2"; shift 2 ;;
    --scripts-dir) SCRIPTS_DIR="$2"; shift 2 ;;
    --guide)       GUIDE="$2"; shift 2 ;;
    --list)        LIST=1; shift ;;
    -h|--help)     sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "[FAIL] lint-user-guide-scripts: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
done

for f in "$INIT" "$GUIDE" "$SCRIPT_DIR/lib/scaffold-shipped-set.sh"; do
  [ -f "$f" ] || { echo "[FAIL] lint-user-guide-scripts: $f not found" >&2; exit 2; }
done
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib/scaffold-shipped-set.sh"

# The shipped set, top-level only: "scripts/<name>.sh" with no further slash.
shipped_top="$(soif_parse_shipped_scripts "$INIT" "$SCRIPTS_DIR" | sed -n 's#^scripts/\([^/]*\.sh\)$#\1#p' | LC_ALL=C sort -u)"
shipped_all="$(soif_parse_shipped_scripts "$INIT" "$SCRIPTS_DIR" | sed 's#^scripts/##' | LC_ALL=C sort -u)"
if [ -z "$shipped_top" ]; then
  echo "[FAIL] lint-user-guide-scripts: the derived shipped set is empty — refusing to claim a clean pass" >&2
  exit 1
fi

# The table's rows: first backticked cell of each row inside the one section.
rows="$(awk '
  /^## Quick Reference — Scripts/ { in_sec = 1; next }
  in_sec && /^## / { in_sec = 0 }
  in_sec && /^\| `[^`]+` \|/ { sub(/^\| `/, ""); sub(/`.*$/, ""); print }
' "$GUIDE" | LC_ALL=C sort -u)"
if [ -z "$rows" ]; then
  echo "[FAIL] lint-user-guide-scripts: no rows found under '## Quick Reference — Scripts' in $GUIDE — the heading or table shape has changed; refusing to claim a clean pass" >&2
  exit 1
fi

if [ "$LIST" -eq 1 ]; then
  echo "rows in the table:"; printf '%s\n' "$rows" | sed 's/^/  /'
  echo "shipped top-level:"; printf '%s\n' "$shipped_top" | sed 's/^/  /'
fi

phantom="$(LC_ALL=C comm -23 <(printf '%s\n' "$rows") <(printf '%s\n' "$shipped_all"))"   # BL-254-PHANTOM-ROW
missing="$(LC_ALL=C comm -13 <(printf '%s\n' "$rows") <(printf '%s\n' "$shipped_top"))"   # BL-254-MISSING-ROW

rc=0
if [ -n "$phantom" ]; then
  echo "[FAIL] lint-user-guide-scripts: the table names script(s) the scaffold does not ship (no cp line in init.sh):" >&2
  printf '%s\n' "$phantom" | sed 's/^/  phantom: /' >&2
  rc=1
fi
if [ -n "$missing" ]; then
  echo "[FAIL] lint-user-guide-scripts: shipped top-level script(s) with no row in the table:" >&2
  printf '%s\n' "$missing" | sed 's/^/  missing: /' >&2
  rc=1
fi
if [ "$rc" -ne 0 ]; then
  echo "  Fix: add or remove rows under '## Quick Reference — Scripts' in docs/user-guide.md; the shipped set is derived from init.sh's cp lines." >&2
  exit 1
fi

n_rows=$(printf '%s\n' "$rows" | grep -c .)
n_top=$(printf '%s\n' "$shipped_top" | grep -c .)
echo "OK: user-guide script table matches the shipped set — $n_rows row(s), $n_top shipped top-level script(s), no phantoms, none missing."
exit 0
