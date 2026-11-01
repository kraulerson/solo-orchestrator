#!/usr/bin/env bash
# scripts/lint-runner-label.sh — every job in tests.yml and lint.yml runs on the
# one image the unit lane was measured on, named, never `ubuntu-latest`
# (`## BL-358:`, "The runner label"; CLAUDE.md, CANONICAL COMMANDS).
#
# THE RULE
#   Every runs-on line in .github/workflows/tests.yml and lint.yml reads
#       runs-on: ubuntu-26.04   # BL-358-RUNNER-LABEL
#   A label resolves per job, so while GitHub moves `ubuntu-latest` one run
#   can hold legs of two images (run 39629060444's second attempt did). The
#   marker is how a reader finds every line the label is on.
#
# WHAT FAILS, NAMED BY FILE, LINE AND JOB
#   label   the line names anything but RUNNER_LABEL: `ubuntu-latest`, a
#           quoted label, a list, an expression, or nothing on the line
#           itself (a list or a group/labels mapping below it)
#   marker  `# BL-358-RUNNER-LABEL` is not the comment after the label
#   shape   a line that mentions runs-on but is not a plain `runs-on:` key
#           (a quoted key, a flow mapping, the word inside a script)
#   A workflow with no runs-on line fails too: a renamed key would otherwise
#   leave nothing to check and read as clean. Whole-line comments are skipped.
#
# MOVING TO A NEW IMAGE, ON PURPOSE
#   RUNNER_LABEL, below, is the only place this check reads the label from,
#   and tests/test-lint-runner-label.sh reads it from here too. Measure the
#   unit lane on the new image first: every suite's result, and every leg's
#   time against `## BL-350:`'s 576s line. Then, in a pull request of its own,
#   change RUNNER_LABEL and every runs-on line this lint names. Nothing else
#   has to change for this check or its suite to pass; prose that names the
#   old image goes stale, not red, so grep for it.
#
# CI: it has no lint.yml job; adding one, and making it a required check, are
# Karl's call. The unit lane runs it twice, so a failure turns the required
# `unit` check red: tests/test-run-lints.sh (leg `slow-misc`) runs every
# scripts/lint-*.sh over the tree, and tests/test-lint-runner-label.sh (leg
# `rest`) runs it over the two workflows.
#
# Usage:
#   bash scripts/lint-runner-label.sh                    # the two workflows
#   bash scripts/lint-runner-label.sh <workflow.yml>...  # fixtures
# Exit: 0 every line passes; 1 a line fails, or a workflow has no runs-on line;
# 2 an unknown option, or a workflow that cannot be read.
set -uo pipefail

RUNNER_LABEL="ubuntu-26.04"   # BL-358-LABEL-VALUE
MARKER="BL-358-RUNNER-LABEL"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

case "${1:-}" in
  -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;   # BL-358-LABEL-HELP
  -*) echo "[FAIL] lint-runner-label: unknown option '$1' (try --help)" >&2; exit 2 ;;   # BL-358-LABEL-OPTION
esac

if [ $# -eq 0 ]; then
  set -- "$REPO_ROOT/.github/workflows/tests.yml" "$REPO_ROOT/.github/workflows/lint.yml"
fi

failed=0
total=0
files=0
for wf in "$@"; do
  show="${wf#"$REPO_ROOT"/}"
  # One V line per fault, then the count of runs-on lines read, as `N <count>`.
  out="$(awk -v label="$RUNNER_LABEL" -v marker="$MARKER" -v f="$show" '
    /^  [^[:space:]#][^:]*:[[:space:]]*(#.*)?$/ { job = $1; sub(/:$/, "", job) }   # BL-358-LABEL-JOB
    /^[[:space:]]*#/ { next }   # BL-358-LABEL-COMMENT-SKIP
    index($0, "runs-on") == 0 { next }   # BL-358-LABEL-SCOPE
    {
      n++
      where = f ":" NR " (job " (job == "" ? "?" : job) ")"
      if ($1 != "runs-on:") { print "V " where ": mentions runs-on but is not a `runs-on:` line"; next }   # BL-358-LABEL-SHAPE
      rest = $0
      sub(/^[[:space:]]*runs-on:/, "", rest)
      v = rest; c = ""
      # YAML starts a comment only at a # that follows whitespace: `x#y` is all value.
      if (match(rest, /[[:space:]]#/)) { v = substr(rest, 1, RSTART - 1); c = substr(rest, RSTART + 1) }   # BL-358-LABEL-SPLIT
      sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
      if (v != label) print "V " where ": " (v == "" ? "names no label on this line" : "runs on `" v "`") ", not `" label "`"   # BL-358-LABEL-NAME
      if (split(c, w) < 2 || w[1] != "#" || w[2] != marker) print "V " where ": no `# " marker "` after the label"   # BL-358-LABEL-MARKER
    }
    END {
      if (n == 0) print "V " f ": no runs-on line, so nothing in it was checked"   # BL-358-LABEL-FLOOR
      print "N " (n + 0)
    }
  ' "$wf" 2>&1)"
  st=$?
  n="$(printf '%s\n' "$out" | sed -n 's/^N \([0-9][0-9]*\)$/\1/p')"
  if [ "$st" -ne 0 ] || [ -z "$n" ]; then   # BL-358-LABEL-READ
    echo "[FAIL] lint-runner-label: could not read the runs-on lines of $show (awk rc $st): $out" >&2
    exit 2
  fi
  bad="$(printf '%s\n' "$out" | sed -n 's/^V /[FAIL] lint-runner-label: /p')"
  if [ -n "$bad" ]; then printf '%s\n' "$bad" >&2; failed=1; fi   # BL-358-LABEL-FAIL
  total=$((total + n))   # BL-358-LABEL-TOTAL
  files=$((files + 1))
done

if [ "$failed" -ne 0 ]; then
  echo "  Each runs-on line reads:  runs-on: $RUNNER_LABEL   # $MARKER" >&2
  echo "  To move every job to another image on purpose, measure the unit lane on it first: every suite's result, and every leg's time against BL-350's 576s line (CLAUDE.md, CANONICAL COMMANDS)." >&2
  echo "  Then, in a pull request of its own, change RUNNER_LABEL in scripts/lint-runner-label.sh, the one place this check and its suite read the label from, and every runs-on line named above; nothing else has to change for either to pass." >&2   # BL-358-LABEL-HOW
  exit 1   # BL-358-LABEL-EXIT
fi

echo "OK: $total runs-on line(s) in $files workflow(s) name $RUNNER_LABEL with # $MARKER."
exit 0
