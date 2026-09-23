#!/usr/bin/env bash
# BL-296 / `## BL-147:` — SOLO'S OWN HOOK ROSTER MUST NOT DEPEND ON A NETWORK CLONE.
#
# THE DEFECT. `init.sh` registers hooks that run TWELVE scripts, every one of
# which belongs to Solo Orchestrator and to nothing else. Derived, not counted
# by eye — an earlier draft of this header said "seven" and then listed ten:
#
#   sed -n '2011,2190p' init.sh | grep -oE 'scripts/(hooks/)?[a-z0-9-]+\.sh' \
#     | LC_ALL=C sort -u
#
#   scripts/detect-out-of-band-commits.sh   scripts/session-freshness-check.sh
#   scripts/hooks/bypass-detector.sh        scripts/session-intake-check.sh
#   scripts/hooks/record-claude-commit.sh   scripts/session-mcp-gate.sh
#   scripts/pre-commit-gate.sh              scripts/session-test-gate-check.sh
#   scripts/session-cadence-check.sh        scripts/session-version-check.sh
#   scripts/session-end-qdrant-reminder.sh  scripts/track-tool-usage.sh
#
# Every one of them runs from the project's OWN `scripts/` directory. None of
# them needs the Development Guardrails, which live in a separate clone at
# `~/.claude-dev-framework`.
#
# They were nonetheless registered INSIDE `if [ "$framework_valid" = true ]` —
# the branch that only runs when that clone succeeded. The clone is two attempts
# over the network, and on failure `init.sh` prints a warning and carries on. So
# a project scaffolded on a bad connection got NO session hooks at all, and the
# run said "Session hooks installed" nowhere and nothing else either. A gate a
# transient failure switches off, silently, leaving something that looks
# installed — `## BL-147:`'s class exactly.
#
# WHY THIS IS A STRUCTURAL PIN AND NOT A BEHAVIOURAL ONE, SAID PLAINLY.
# Proving it by execution means running `init.sh` with the clone forced to fail,
# which means faking a network failure and a three-minute scaffold. This file
# instead checks the STRUCTURE: that the roster is outside the branch, and that
# nothing in it reads the branch's variable. That is weaker than execution and
# it is what this file claims, no more.
#
# IT RUNS IN THE UNIT LANE, AND THE HEADER USED TO SAY THE OPPOSITE. An earlier
# draft justified itself with "it invokes `init.sh`, so `lint-tests-registered.sh`
# exempts it from the unit array". It does NOT invoke `init.sh` — it greps it,
# in 39 milliseconds — and the exemption it was relying on is
# `## BL-181:`'s documented hole: the lint's predicate is *names `init.sh` on an
# executed line*, which the `INIT=` assignment satisfies while invoking nothing.
# So the lint stayed green and the suite ran in no PR-gating lane at all. It is
# in `.github/workflows/tests.yml`'s `tests=(` array now. CLAUDE.md's own
# membership rule — "a test belongs there iff it does not invoke `init.sh` and
# is not an aggregator" — always said so; the exempt row was a claim, not a
# verdict.
#
# WHAT AN ADVERSARIAL REVIEW GOT PAST THE FIRST DRAFT, recorded because each
# one is a shape the next positional pin will meet:
#   M2/M3  re-added the dependency without moving a line — `if [ "$framework_valid"
#          = true ] && [ -f … ]` on the marker line, and a `[ "$framework_valid"
#          = true ] || return 0` guard as the block's first statement. Both left
#          the marker after the `fi`, so R1 passed. R4 is the answer: a
#          POSITIONAL pin cannot see a DATA-FLOW defect, so the data flow is
#          pinned separately.
#   M4     put a `fi` inside a heredoc body between the branch's `if` and its
#          `fi`. `_branch_close` collapsed the span to three lines and R1 passed
#          with the roster genuinely back inside the branch. Two answers: the
#          helper now skips heredoc bodies, and R1 asserts the span is PLAUSIBLE
#          — an absurd span is a broken measurement, not a pass.
#   M5     renamed `scripts/hooks/bypass-detector.sh` to a file that does not
#          exist. R2's `scripts/[a-z0-9-]+\.sh` cannot match a second path
#          segment, so it never looked at either `scripts/hooks/` script.
#   M6     lifted the `settings.json` write into a function nobody calls. R3
#          compares LINE NUMBERS and passed while the file was never written.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

INIT="$REPO_ROOT/init.sh"

# _branch_close FILE OPEN_LINE — the line of the `fi` that closes the `if`
# opening at OPEN_LINE, by counting block-opening and block-closing tokens.
#
# `if`/`fi` alone is not enough: `case … esac` and `for`/`while … done` nest
# inside this branch, and a naive count that ignored them would find the wrong
# `fi` and pass no matter where the roster sat. Every opener here is matched by
# its own closer, so the depth is exact.
#
# QUOTED STRINGS ARE STRIPPED FIRST, AND THAT IS NOT DEFENSIVE POLISH — IT IS
# THE BUG THIS HELPER SHIPPED WITH. `init.sh` line 1972 reads
# `print_ok "Development Guardrails for Claude Code installed and configured"`,
# and the word `for` inside that message counted as a `for … done` opener. The
# depth never returned to zero at the real `fi`, the helper walked on to the
# next unbalanced `fi` 200 lines later, and R1 reported the roster as INSIDE a
# branch it had already been moved out of. A false FAIL that time; the same
# miscount in the other direction is a false PASS.
_branch_close() {
  awk -v start="$2" '
    NR < start { next }
    {
      raw = $0
      # HEREDOC BODIES ARE NOT CODE. A `fi` inside one collapsed the span
      # computed here to three lines and made R1 pass with the roster back
      # inside the branch. `init.sh` carries heredocs a few lines above this
      # region (`PERMEOF`, the `LANGEOF` family), so the first draft survived
      # only because none of them sat between the branch opener and its `fi`.
      #
      # NO APOSTROPHES IN THIS awk PROGRAM, DELIBERATELY. It lives inside a
      # SINGLE-QUOTED shell string, so one apostrophe in a comment ends the
      # program and bash reports a syntax error on a LATER line that is
      # perfectly well formed. That is how this very paragraph broke twice.
      if (inhd) { if (raw ~ ("^[[:space:]]*" hdw "[[:space:]]*$")) inhd = 0; next }
      # `<<<` is a herestring, not a heredoc, and has no terminator to find.
      # The delimiter word is taken as everything up to the next space and then
      # reduced to its word characters, which removes the `<<`, the `-` and
      # either quote style without this program needing to CONTAIN either.
      if (raw !~ /^[[:space:]]*#/ && raw !~ /<<</ && match(raw, /<<-?[[:space:]]*[^[:space:]]+/)) {
        hdw = substr(raw, RSTART, RLENGTH)
        gsub(/[^A-Za-z0-9_]/, "", hdw)
        if (hdw != "") inhd = 1
      }
      line = raw
      # QUOTES FIRST, THEN COMMENTS. The other order truncates a line at a `#`
      # that lives inside a string, dropping real tokens after it.
      q = sprintf("%c", 39)
      gsub(/"[^"]*"/, "", line)
      gsub(q "[^" q "]*" q, "", line)
      sub(/#.*/, "", line)
      n = 0
      # openers
      n += gsub(/(^|[ \t;])if([ \t]|$)/,   "&", line)
      n += gsub(/(^|[ \t;])case([ \t]|$)/, "&", line)
      n += gsub(/(^|[ \t;])for([ \t]|$)/,  "&", line)
      n += gsub(/(^|[ \t;])while([ \t]|$)/,"&", line)
      depth += n
      c = 0
      c += gsub(/(^|[ \t;])fi([ \t;]|$)/,   "&", line)
      c += gsub(/(^|[ \t;])esac([ \t;]|$)/, "&", line)
      c += gsub(/(^|[ \t;])done([ \t;]|$)/, "&", line)
      depth -= c
      if (depth <= 0) { print NR; exit }
    }' "$1"
}

# _enclosing_func FILE LINE — the name of the function whose body contains
# LINE, by the nearest preceding `name() {` at column 0 or two. Approximate by
# design: it is used to compare TWO lines, so it is right whenever it is
# consistently wrong, and a file with no functions yields the same answer for
# both.
_enclosing_func() {
  awk -v want="$2" '
    NR > want { exit }
    /^[[:space:]]{0,2}[A-Za-z_][A-Za-z0-9_]*\(\)[[:space:]]*\{/ {
      f = $0
      sub(/\(\).*/, "", f)
      gsub(/[^A-Za-z0-9_]/, "", f)
    }
    END { print (f == "" ? "(top level)" : f) }' "$1"
}

echo "== BL-296 — the hook roster does not depend on the CDF clone =="

# ═══════════════════════════════════════════════════════════════════════════
# R1 — THE ROSTER IS OUTSIDE THE `framework_valid` BRANCH
# ═══════════════════════════════════════════════════════════════════════════
r1() {
  local label="R1 the orchestrator hook roster registers outside the CDF-success branch"
  local open close marker
  open="$(grep -n 'if \[ "\$framework_valid" = true \]; then' "$INIT" | head -1 | cut -d: -f1)"
  marker="$(grep -n 'BL-296-ROSTER-UNCONDITIONAL' "$INIT" | head -1 | cut -d: -f1)"
  if [ -z "$open" ];   then fail_ "$label" "could not find the framework_valid branch in init.sh"; return; fi
  if [ -z "$marker" ]; then fail_ "$label" "no BL-296-ROSTER-UNCONDITIONAL marker — the roster's guard is unmarked"; return; fi
  close="$(_branch_close "$INIT" "$open")"
  if [ -z "$close" ]; then fail_ "$label" "could not find the branch's closing fi"; return; fi
  # THE SPAN MUST BE PLAUSIBLE BEFORE IT IS USED. A miscounted span is a broken
  # MEASUREMENT, and a broken measurement that happens to satisfy the
  # comparison below is a PASS that means nothing. Adversarial review produced
  # exactly that: a `fi` planted in a heredoc collapsed the branch to
  # `1899-1901`, visibly absurd, and R1 went green with the roster genuinely
  # back inside it. The branch does real work — a clone, a platform `case`, a
  # jq merge, a manifest check — and has never been shorter than 80 lines.
  if [ "$((close - open))" -lt 50 ]; then
    fail_ "$label" "the branch measures $((close - open)) lines ($open-$close), which is not a real span — the opener/closer count is wrong and this case cannot decide anything"
    return
  fi
  if [ "$marker" -gt "$close" ]; then
    pass "$label (branch $open-$close, roster at $marker)"
  else
    fail_ "$label" "the roster is at line $marker, INSIDE the branch that spans $open-$close — a failed clone would register none of it"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# R2 — EVERY HOOK IN THE ROSTER IS SOLO'S OWN
#      The reason the roster may be unconditional is that none of it belongs to
#      the Development Guardrails. If a CDF-owned hook were ever added here,
#      moving the block out would register something whose script is absent.
# ═══════════════════════════════════════════════════════════════════════════
r2() {
  local label="R2 every script the roster registers ships in this repo's own scripts/"
  local open close bad="" s
  open="$(grep -n 'BL-296-ROSTER-UNCONDITIONAL' "$INIT" | head -1 | cut -d: -f1)"
  [ -n "$open" ] || { fail_ "$label" "no roster marker"; return; }
  close="$(_branch_close "$INIT" "$open")"
  [ -n "$close" ] || { fail_ "$label" "could not bound the roster block"; return; }
  # `(hooks/)?` IS LOAD-BEARING. The first draft matched `scripts/[a-z0-9-]+\.sh`,
  # which cannot cross a second path separator, so `scripts/hooks/bypass-detector.sh`
  # and `scripts/hooks/record-claude-commit.sh` were INVISIBLE to this case —
  # 10 of the 12 scripts checked, and adversarial review renamed one of the two
  # to a file that does not exist with this case still green.
  local rx='scripts/(hooks/)?[a-z0-9-]+\.sh'
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    [ -f "$REPO_ROOT/$s" ] || bad="$bad [$s is registered but not in this repo]"
  done <<SCRIPTS
$(sed -n "${open},${close}p" "$INIT" | grep -oE "$rx" | LC_ALL=C sort -u)
SCRIPTS
  # VACUITY FLOOR: the block must actually name the scripts, or an empty
  # extraction satisfies the loop above.
  #
  # THE FLOOR IS THE DISTINCT COUNT, NOT `grep -c`. The first draft printed and
  # floored on matching LINES (19), which is neither the number of scripts it
  # verified nor the number the roster registers — a reader took 19 as
  # coverage while two scripts went unchecked. Twelve is the roster as it
  # stands; adding a hook raises it and removing one is a deliberate act that
  # should have to edit this line.
  local n
  n=$(sed -n "${open},${close}p" "$INIT" | grep -oE "$rx" | LC_ALL=C sort -u | grep -c .)
  [ "$n" -ge 12 ] || bad="$bad [only $n DISTINCT scripts found in the block — the roster registers twelve, so the extraction is wrong or a hook was dropped]"
  [ -z "$bad" ] && pass "$label ($n distinct scripts)" || fail_ "$label" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# R3 — `.claude/settings.json` EXISTS BEFORE THE ROSTER RUNS
#      The roster's guard is `[ -f ".claude/settings.json" ]`. Moving it out of
#      the CDF branch is only safe because init.sh writes that file itself,
#      unconditionally, earlier. If CDF became its author the move would have
#      re-created the defect in a new shape.
# ═══════════════════════════════════════════════════════════════════════════
r3() {
  local label="R3 init.sh writes .claude/settings.json itself, before the roster's guard reads it"
  local writer marker
  writer="$(grep -n 'cat > \.claude/settings\.json' "$INIT" | head -1 | cut -d: -f1)"
  marker="$(grep -n 'BL-296-ROSTER-UNCONDITIONAL' "$INIT" | head -1 | cut -d: -f1)"
  if [ -z "$writer" ]; then
    fail_ "$label" "init.sh no longer writes .claude/settings.json directly — the roster's guard may never be satisfied without the CDF clone"
  elif [ "$writer" -ge "$marker" ]; then
    fail_ "$label" "settings.json is written at $writer, AFTER the roster at $marker"
  elif [ "$(_enclosing_func "$INIT" "$writer")" != "$(_enclosing_func "$INIT" "$marker")" ]; then
    # A LINE NUMBER IS NOT AN EXECUTION ORDER, and this arm is what makes the
    # difference. Adversarial review lifted the `cat >` into a function defined
    # near the top of the file and never called it: the write moved to line 116,
    # the comparison above still said "earlier", and `.claude/settings.json` was
    # never written at all while this case stayed green.
    fail_ "$label" "the write at $writer and the roster at $marker are in different functions ($(_enclosing_func "$INIT" "$writer") vs $(_enclosing_func "$INIT" "$marker")) — the earlier LINE does not mean the earlier EXECUTION"
  else
    pass "$label (written at $writer, read at $marker, both in $(_enclosing_func "$INIT" "$marker"))"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# R4 — THE ROSTER DOES NOT READ THE BRANCH'S VARIABLE
#      R1 is POSITIONAL and cannot see a DATA-FLOW defect. Two one-token
#      mutations put the dependency straight back while leaving the marker
#      after the `fi`, and R1 passed both:
#        if [ "$framework_valid" = true ] && [ -f ".claude/settings.json" ] …
#        [ "$framework_valid" = true ] || return 0     (as the block's first line)
#      Neither moves a line. This case is the one that kills them.
# ═══════════════════════════════════════════════════════════════════════════
r4() {
  local label="R4 nothing at or after the roster reads \$framework_valid"
  local marker hits
  marker="$(grep -n 'BL-296-ROSTER-UNCONDITIONAL' "$INIT" | head -1 | cut -d: -f1)"
  [ -n "$marker" ] || { fail_ "$label" "no roster marker"; return; }
  # EXECUTED LINES ONLY — the comment block above the roster explains the move
  # and names the variable four times, which is exactly right for a comment and
  # would be a false FAIL here. Whole-line and trailing comments both.
  hits="$(sed -n "${marker},\$p" "$INIT" | sed 's/#.*//' | grep -n 'framework_valid' | head -5)"
  if [ -z "$hits" ]; then
    pass "$label"
  else
    fail_ "$label" "the roster still reads the CDF-clone variable — a failed clone would register none of it: $(printf '%s' "$hits" | tr '\n' ';')"
  fi
}

r1; r2; r3; r4

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
