#!/usr/bin/env bash
# scripts/lint-runner-label.sh — every job in tests.yml and lint.yml runs on the
# one image the unit lane was measured on, named, never `ubuntu-latest`
# (`## BL-358:`, "The runner label"; CLAUDE.md, CANONICAL COMMANDS), and no
# workflow file beside them goes unread (`## BL-376:`).
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
# THE TWO LISTS, WHICH EVERY WORKFLOW FILE IS HELD AGAINST
#   With no arguments the lint enumerates .github/workflows/*.yml and *.yaml
#   and holds each file, by name, against two lists carried below, one entry
#   per line between a marked `cat <<'EOF'` and its EOF:
#   CHECKED  the files whose runs-on lines are read: tests.yml and lint.yml.
#            A new workflow whose jobs carry runs-on lines goes here, a
#            reusable `on: workflow_call` workflow included.
#   EXEMPT   `<file>  <reason>`, the files with no runs-on line to read. The
#            one shape that belongs here is a caller-only workflow, every job
#            a `jobs.<id>.uses` call, which GitHub gives no runs-on key. It
#            is empty today.
#   A file in neither list fails by name, and the message names both lists.
#   An EXEMPT file that holds a runs-on line fails too, because the exemption
#   no longer describes it, and so does an EXEMPT entry with no reason. A job
#   on another image is not an exemption: RUNNER_LABEL is one label, so such
#   a job needs a change to this lint, not an entry.
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
# `rest`) runs it with no arguments, over every workflow file.
#
# Usage:
#   bash scripts/lint-runner-label.sh                    # every workflow file, by the two lists
#   bash scripts/lint-runner-label.sh <workflow.yml>...  # these files only: no lists, no enumeration
# Exit: 0 every line passes; 1 a line fails, a workflow has no runs-on line, or
# a workflow file is in neither list, is EXEMPT and holds a runs-on line, or is
# EXEMPT with no reason; 2 an unknown option, or a workflow that cannot be read.
set -uo pipefail

RUNNER_LABEL="ubuntu-26.04"   # BL-358-LABEL-VALUE
MARKER="BL-358-RUNNER-LABEL"

# The two lists (THE TWO LISTS, above): one entry per line between the `cat`
# and its EOF, and nothing else, since the first word of every line is read as
# a file name.
checked_set() {
  cat <<'EOF'   # BL-376-CHECKED-BEGIN
tests.yml
lint.yml
EOF
}
exempt_list() {   # <file>  <reason>
  cat <<'EOF'   # BL-376-EXEMPT-BEGIN
EOF
}

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WF_DIR="$REPO_ROOT/.github/workflows"

case "${1:-}" in
  -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;   # BL-358-LABEL-HELP
  -*) echo "[FAIL] lint-runner-label: unknown option '$1' (try --help)" >&2; exit 2 ;;   # BL-358-LABEL-OPTION
esac

# scan <workflow> <shown name> — reads one workflow: sets n to the count of its
# runs-on lines (every non-comment line that mentions runs-on, whatever its
# shape) and bad to its faults, one `[FAIL]` line each, or empty. A workflow
# that cannot be read ends the run at rc 2.
scan() {
  local out="" st=0
  # One V line per fault, then the count of runs-on lines read, as `N <count>`.
  out="$(awk -v label="$RUNNER_LABEL" -v marker="$MARKER" -v f="$2" '
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
  ' "$1" 2>&1)"
  st=$?
  n="$(printf '%s\n' "$out" | sed -n 's/^N \([0-9][0-9]*\)$/\1/p')"
  if [ "$st" -ne 0 ] || [ -z "$n" ]; then   # BL-358-LABEL-READ
    echo "[FAIL] lint-runner-label: could not read the runs-on lines of $2 (awk rc $st): $out" >&2
    exit 2
  fi
  bad="$(printf '%s\n' "$out" | sed -n 's/^V /[FAIL] lint-runner-label: /p')"
}

failed=0
scope_failed=0
exempt_note=""
if [ $# -eq 0 ]; then
  # CHECKED becomes the arguments, as the two names were before the lint
  # enumerated, so a listed file that is missing still ends rc 2 at the read
  # check. Then every other workflow file is held against the two lists.
  while read -r base _; do
    [ -n "$base" ] && set -- "$@" "$WF_DIR/$base"
  done <<EOF
$(checked_set)
EOF
  exempt=0
  for wf in "$WF_DIR"/*.yml "$WF_DIR"/*.yaml; do   # BL-376-ENUMERATE
    # bash 3.2 has no nullglob: a pattern that matches nothing is its own text.
    [ -e "$wf" ] || continue   # BL-376-NULLGLOB
    base="${wf##*/}"
    show="${wf#"$REPO_ROOT"/}"   # BL-376-SHOW
    checked_set | awk -v b="$base" '$1 == b { hit = 1 } END { exit !hit }' && continue   # BL-376-CHECKED-MATCH
    entry="$(exempt_list | awk -v b="$base" '$1 == b && !hit { hit = 1; print }')"   # BL-376-EXEMPT-MATCH
    reason="$(printf '%s\n' "$entry" | sed 's/^[^[:space:]]*[[:space:]]*//; s/[[:space:]]*$//')"   # BL-376-REASON-TRIM
    if [ -n "$reason" ]; then   # BL-376-EXEMPT-OK
      scan "$wf" "$show"
      if [ "$n" -ne 0 ]; then   # BL-376-EXEMPT-RUNS-ON
        echo "[FAIL] lint-runner-label: $show holds $n runs-on line(s) but is EXEMPT ($reason): the exemption no longer describes it, so move the file to CHECKED, or drop the word from the file" >&2
        # Its fault lines, if any: a line that is no runs-on key would fail the shape rule once CHECKED.
        [ -z "$bad" ] || printf '%s\n' "$bad" >&2
        scope_failed=1
      else
        exempt=$((exempt + 1))
      fi
    elif [ -n "$entry" ]; then   # BL-376-EXEMPT-REASON
      echo "[FAIL] lint-runner-label: $show is EXEMPT with no reason: an EXEMPT line reads \`<file>  <reason>\`" >&2
      scope_failed=1
    else   # BL-376-UNKNOWN
      echo "[FAIL] lint-runner-label: $show is in neither list of scripts/lint-runner-label.sh: add it to CHECKED when its jobs carry runs-on lines, or to EXEMPT with a reason when every job is a jobs.<id>.uses call" >&2
      scope_failed=1
    fi
  done
  exempt_note="; $exempt workflow(s) exempt"
fi

total=0
files=0
for wf in "$@"; do
  show="${wf#"$REPO_ROOT"/}"
  scan "$wf" "$show"
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
[ "$scope_failed" -eq 0 ] || exit 1   # BL-376-EXIT

echo "OK: $total runs-on line(s) in $files workflow(s) name $RUNNER_LABEL with # $MARKER$exempt_note."
exit 0
