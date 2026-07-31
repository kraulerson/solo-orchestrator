#!/usr/bin/env bash
# tests/test-bl200-syntax-detector.sh — BL-200: the token-stream-break blind spot.
#
# WHY THIS EXISTS (BL-200, split out of BL-198 v2 review R-1)
#   A pure-ASCII source file with a syntax break beside a sink passes every
#   byte-level check the hook has (BL-198 included) and semgrep misses the sink
#   DETERMINISTICALLY: measured on 1.157.0, `p.innerHTML = window.name` alone is
#   rc=1/1 finding; add `function ((( broken $$$` on the next line and the same
#   scan is rc=0/0 findings. The only known detector is `--verbose`'s
#   `[WARN] Syntax error at line <target>:N` line (count 1 vs 0; never anchor on
#   the `Partially analyzed…` header — it prints on EVERY verbose scan).
#   Admissibility terms from the entry: the detector is REPORT-DEPENDENT, so it
#   may only ever FORFEIT receipts, never grant one; an upstream respelling must
#   degrade to today's behaviour (under-detect => status quo), and the exact
#   spelling is pinned by a framework-side canary
#   (tests/test-bl200-syntax-canary.sh) so drift reds OUR lane first.
#   PREFILTER FACT (measured, load-bearing): semgrep only PARSES a file some
#   rule's literal prefilter admits, so the warning only exists for files that
#   textually contain a rule token — which is every file hiding a sink, i.e.
#   exactly the threat model. A sinkless broken file may go undetected; it also
#   has nothing to hide.
#
# CASES
#   T-break-forfeits-receipt   live — stage sink+break, commit -> LANDS (the
#                              detector warns, it does not block — the BL-192
#                              decision blocks rule a report-dependent gate out
#                              of the blocking path) but the [OK] receipt is
#                              FORFEITED and the warn names the token-stream
#                              break. RED pre-fix: [OK] over the hidden sink.
#   T-clean-still-receipts     live control — a clean sinkless file still earns
#                              [OK], now with the `scanner: semgrep <v>` line
#                              (BL-201's deferred receipt debuggability, landed
#                              here). No cry-wolf.
#   T-sink-still-blocks        live — a clean sink file is still REFUSED
#                              ([BLOCKED] path undisturbed by --verbose), and
#                              the blocked report carries the scanner line too.
#   T-stub-respell-degrades    stub + own control — a RESPELLED warning earns
#                              the receipt (degrade-to-today under upstream
#                              drift); the EXACT spelling forfeits it. Proves
#                              the atom is decisive, in both directions.
#   T-stub-version-unknown     stub — `semgrep --version` failing must not cost
#                              the receipt: [OK] still prints, scanner line says
#                              the version is unknown rather than lying.
#   T-mutation-verbose-flag    live — strip `--verbose` from the invocation ->
#                              the warning never exists and the broken commit
#                              buys [OK] again (RED) -> intact hook forfeits
#                              (GREEN). The flag is load-bearing, not hygiene.
#   T-mutation-syntax-clause   live — drop the `soif_sg_syntax` conjunct from
#                              the coverage conjunction -> [OK] over the break
#                              (RED) -> intact forfeits (GREEN). The clause
#                              carries its own weight (T-mutation-rule-timeout's
#                              discipline, third clause).
#
# The live cases talk to the semgrep registry (the emitted hook's config set).
# No semgrep, or a failed registry preflight => LOUD SKIP, never a silent pass.
#
# REGISTRATION: never runs init.sh, not an aggregator -> registered in BOTH
# tests/full-project-test-suite.sh AND the tests.yml unit fast lane (sast shard:
# the live cases need semgrep on the host).
# Hermetic: mktemp workdirs, local git identity, GITHUB_BASE_REF unset, no
# remote. bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

unset GITHUB_BASE_REF 2>/dev/null || true

PASSED=0
FAILED=0
SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip_() { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

HOOK_SRC="$REPO_ROOT/scripts/lib/hook-templates.sh"
RULESET_SRC="$REPO_ROOT/templates/semgrep/soif-dom-sinks.yml"
EMITTED="$TOPTMP/emitted-hook"

if [ ! -f "$HOOK_SRC" ]; then
  echo "SKIP: scripts/lib/hook-templates.sh missing"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi
# shellcheck source=/dev/null
. "$HOOK_SRC"
soif_write_precommit_hook "$EMITTED"

# ── Fixtures (the BL-200 measurement, verbatim) ─────────────────────────────
# The break sits AFTER the sink so the sink is textually present (prefilter
# passes, the parse is attempted) and syntactically unreachable (the parse
# fails, the finding is lost). That ordering IS the attack.
BROKEN_TS='export function r(p){ p.innerHTML = window.name; }
function ((( broken $$$'
SINK_TS='export function render(pane, userText) {
  pane.innerHTML = userText;
}'
CLEAN_TS='export function render(pane, userText) {
  pane.textContent = userText;
}'

# ── Live preflight: semgrep + registry, stated LOUDLY ───────────────────────
HAVE_LIVE=0
if command -v semgrep >/dev/null 2>&1; then
  if semgrep scan --config=r/javascript.browser.security.insecure-document-method \
       --severity=ERROR "$TOPTMP" >/dev/null 2>&1; then
    HAVE_LIVE=1
  else
    echo ""
    echo "#################################################################"
    echo "## semgrep is installed but the REGISTRY PREFLIGHT FAILED.     ##"
    echo "## The live BL-200 cases are SKIPPED, NOT PASSED.              ##"
    echo "#################################################################"
    echo ""
  fi
else
  echo ""
  echo "#################################################################"
  echo "## semgrep IS NOT INSTALLED ON THIS HOST.                      ##"
  echo "## The live BL-200 cases are SKIPPED, NOT PASSED.              ##"
  echo "## Install semgrep to exercise them: brew install semgrep      ##"
  echo "#################################################################"
  echo ""
fi

# ── Harness (the bl132 shapes, self-contained) ──────────────────────────────
mk_repo() {
  local d="$1" hook="$2"
  mkdir -p "$d/.semgrep"
  ( cd "$d" \
      && git init -q \
      && git config user.email "bl200@test.invalid" \
      && git config user.name  "BL-200 Test" \
      && echo "# bl200" > README.md \
      && git add README.md \
      && git commit -q -m "chore: init" ) || return 1
  [ -f "$RULESET_SRC" ] && cp "$RULESET_SRC" "$d/.semgrep/soif-dom-sinks.yml"
  cp "$hook" "$d/.git/hooks/pre-commit"
  chmod +x "$d/.git/hooks/pre-commit"
}

# _commit_file <hookfile> <content> <log> [pathprefix-dir-for-stub-PATH]
#   -> COMMITTED|REFUSED|SETUPFAIL. One staged file, so accepted>=1 satisfies
#   the selection clause and only the clause under test can move the verdict.
_commit_file() {
  local d rc=COMMITTED
  d="$(mktemp -d)"
  mk_repo "$d" "$1" >/dev/null 2>&1 || { rm -rf "$d"; echo SETUPFAIL; return; }
  printf '%s\n' "$2" > "$d/app.ts"
  ( cd "$d" && git add -- app.ts ) >/dev/null 2>&1
  if [ -n "${4:-}" ]; then
    ( cd "$d" && PATH="$4:$PATH" git commit -m "feat: add the renderer" ) >"$3" 2>&1 || rc=REFUSED
  else
    ( cd "$d" && git commit -m "feat: add the renderer" ) >"$3" 2>&1 || rc=REFUSED
  fi
  rm -rf "$d"
  echo "$rc"
}

# _mut_n <src> <dst> <old> <new> <want>: literal replace, exactly <want> times.
# OLD/NEW ride ENVIRON, not -v, DELIBERATELY: awk processes escape sequences in
# -v values, and this suite's '--verbose \' literal ends in a lone backslash —
# BSD awk keeps it (local pass), mawk/gawk mangle it (the CI sast shard failed
# exactly T-mutation-verbose-flag as MIS-TARGETED on an emitted hook that was
# fine). ENVIRON passes bytes untouched on every awk. want is numeric — -v safe.
_mut_n() {
  SOIF_MUT_OLD="$3" SOIF_MUT_NEW="$4" awk -v want="$5" '
    { out = ""; rest = $0
      while ((p = index(rest, ENVIRON["SOIF_MUT_OLD"])) > 0) {
        out = out substr(rest, 1, p-1) ENVIRON["SOIF_MUT_NEW"]
        rest = substr(rest, p + length(ENVIRON["SOIF_MUT_OLD"]))
        c++
      }
      print out rest }
    END { if (c != want) exit 3 }
  ' "$1" > "$2"
}

# mk_stub <dir> <syntax-line-or-empty> <version-rc> <version-out> [stdout]: a
# PATH semgrep whose scan arm prints a well-formed banner on stderr (selection
# satisfied at 1>=1) plus an optional column-0 warning line — on stderr by
# default, on STDOUT when the fifth argument says so (the hook reads the
# CONCATENATED streams precisely because BL-193 measured routing as
# frontend-dependent; T-stub-warn-on-stdout pins that width). Exit 0 (clean
# scan); the --version arm is configurable. Every stub case carries its own
# control — a stub that broke the arm outright would make "the receipt was
# forfeited" pass vacuously.
mk_stub() {
  mkdir -p "$1"
  { printf '#!/bin/sh\n'
    printf 'if [ "${1:-}" = "--version" ]; then\n'
    printf '  [ "%s" -eq 0 ] && printf "%%s\\n" "%s"\n' "$3" "$4"
    printf '  exit %s\n' "$3"
    printf 'fi\n'
    printf 'cat >&2 <<SOIFSTUBEOF\n'
    printf '  Scanning 1 file with 174 Code rules:\n'
    if [ -n "$2" ] && [ "${5:-}" != "stdout" ]; then printf '%s\n' "$2"; fi
    printf 'SOIFSTUBEOF\n'
    if [ -n "$2" ] && [ "${5:-}" = "stdout" ]; then
      printf 'cat <<SOIFSTUBOUTEOF\n'
      printf '%s\n' "$2"
      printf 'SOIFSTUBOUTEOF\n'
    fi
    printf 'exit 0\n'
  } > "$1/semgrep"
  chmod +x "$1/semgrep"
}

# ── T-break-forfeits-receipt ────────────────────────────────────────────────
echo "=== T-break-forfeits-receipt ==="
if [ "$HAVE_LIVE" -ne 1 ]; then
  skip_ "T-break-forfeits-receipt" "no live semgrep/registry on this host"
else
  V="$(_commit_file "$EMITTED" "$BROKEN_TS" "$TOPTMP/bf.log")"
  if [ "$V" = "SETUPFAIL" ]; then
    fail_ "T-break-forfeits-receipt" "fixture setup failed"
  elif [ "$V" != "COMMITTED" ]; then
    fail_ "T-break-forfeits-receipt" "the broken-file commit was REFUSED — the detector must warn and forfeit, never block (BL-192 decision blocks): $(tail -6 "$TOPTMP/bf.log" | tr '\n' '|')"
  elif grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/bf.log"; then
    fail_ "T-break-forfeits-receipt" "the [OK] receipt was printed over a token-stream break hiding a sink — the exact BL-200 false attestation: $(tail -6 "$TOPTMP/bf.log" | tr '\n' '|')"
  elif ! grep -qF 'token-stream break' "$TOPTMP/bf.log"; then
    fail_ "T-break-forfeits-receipt" "the receipt was withheld but the operator was never told WHY (no token-stream-break warn line): $(tail -8 "$TOPTMP/bf.log" | tr '\n' '|')"
  else
    pass "T-break-forfeits-receipt: sink+break LANDS without the [OK] receipt and the warn names the break"
  fi
fi

# ── T-clean-still-receipts ──────────────────────────────────────────────────
echo "=== T-clean-still-receipts ==="
if [ "$HAVE_LIVE" -ne 1 ]; then
  skip_ "T-clean-still-receipts" "no live semgrep/registry on this host"
else
  V="$(_commit_file "$EMITTED" "$CLEAN_TS" "$TOPTMP/cr.log")"
  if [ "$V" = "SETUPFAIL" ]; then
    fail_ "T-clean-still-receipts" "fixture setup failed"
  elif [ "$V" != "COMMITTED" ]; then
    fail_ "T-clean-still-receipts" "a clean commit was refused: $(tail -6 "$TOPTMP/cr.log" | tr '\n' '|')"
  elif ! grep -qF '[OK] semgrep: SAST ran on 1 staged file(s)' "$TOPTMP/cr.log"; then
    fail_ "T-clean-still-receipts" "the clean control lost its receipt — the detector cries wolf: $(tail -6 "$TOPTMP/cr.log" | tr '\n' '|')"
  elif ! grep -qE 'scanner: semgrep [0-9]' "$TOPTMP/cr.log"; then
    fail_ "T-clean-still-receipts" "no 'scanner: semgrep <version>' line beside the receipt — the image floats (BL-201) and the hook is unpinned, so the log is the ONLY record of what scanned this commit: $(tail -6 "$TOPTMP/cr.log" | tr '\n' '|')"
  else
    pass "T-clean-still-receipts: clean file earns [OK] + the scanner-version line"
  fi
fi

# ── T-sink-still-blocks ─────────────────────────────────────────────────────
echo "=== T-sink-still-blocks ==="
if [ "$HAVE_LIVE" -ne 1 ]; then
  skip_ "T-sink-still-blocks" "no live semgrep/registry on this host"
else
  V="$(_commit_file "$EMITTED" "$SINK_TS" "$TOPTMP/sb.log")"
  if [ "$V" = "SETUPFAIL" ]; then
    fail_ "T-sink-still-blocks" "fixture setup failed"
  elif [ "$V" != "REFUSED" ]; then
    fail_ "T-sink-still-blocks" "a parseable staged sink COMMITTED — --verbose disturbed the blocking path: $(tail -6 "$TOPTMP/sb.log" | tr '\n' '|')"
  elif ! grep -qF '[BLOCKED] Semgrep detected security issues' "$TOPTMP/sb.log"; then
    fail_ "T-sink-still-blocks" "refused without the [BLOCKED] report: $(tail -6 "$TOPTMP/sb.log" | tr '\n' '|')"
  elif ! grep -qE 'scanner: semgrep [0-9]' "$TOPTMP/sb.log"; then
    fail_ "T-sink-still-blocks" "the blocked report carries no scanner-version line — a blocked operator debugging a finding needs to know WHICH semgrep found it (BL-193): $(tail -8 "$TOPTMP/sb.log" | tr '\n' '|')"
  else
    pass "T-sink-still-blocks: the blocking path is undisturbed and names the scanner version"
  fi
fi

# ── T-stub-respell-degrades ─────────────────────────────────────────────────
# The degrade-to-today contract, both directions: a RESPELLED warning must be
# invisible (receipt earned — under-detection is the agreed failure mode) and
# the EXACT spelling must forfeit (the control that proves the stub pair can
# detect at all). The spelling atom is `[WARN] Syntax error at line ` at
# column 0 — the canary suite pins it against the real semgrep.
echo "=== T-stub-respell-degrades ==="
STUB_RESPELL="$TOPTMP/stub-respell"
STUB_EXACT="$TOPTMP/stub-exact"
mk_stub "$STUB_RESPELL" '[WARN] Syntax problem at line app.ts:1:' 0 '9.99.9-stub'
mk_stub "$STUB_EXACT"   '[WARN] Syntax error at line app.ts:1:'   0 '9.99.9-stub'
VR="$(_commit_file "$EMITTED" "$CLEAN_TS" "$TOPTMP/rs.log" "$STUB_RESPELL")"
VE="$(_commit_file "$EMITTED" "$CLEAN_TS" "$TOPTMP/ex.log" "$STUB_EXACT")"
if [ "$VR" = "SETUPFAIL" ] || [ "$VE" = "SETUPFAIL" ]; then
  fail_ "T-stub-respell-degrades" "fixture setup failed"
elif [ "$VR" != "COMMITTED" ] || ! grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/rs.log"; then
  fail_ "T-stub-respell-degrades" "a RESPELLED warning cost the receipt — the detector must under-detect on drift (status quo), never over-fire on words it was not built for: $(tail -6 "$TOPTMP/rs.log" | tr '\n' '|')"
elif [ "$VE" != "COMMITTED" ]; then
  fail_ "T-stub-respell-degrades" "the exact-spelling control was REFUSED — the warn arm must not block: $(tail -6 "$TOPTMP/ex.log" | tr '\n' '|')"
elif grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/ex.log"; then
  fail_ "T-stub-respell-degrades" "the EXACT spelling still earned the receipt — the detector reads nothing and the respell half was passing vacuously: $(tail -6 "$TOPTMP/ex.log" | tr '\n' '|')"
elif ! grep -qF 'token-stream break' "$TOPTMP/ex.log"; then
  fail_ "T-stub-respell-degrades" "the exact spelling forfeited the receipt but never told the operator why: $(tail -8 "$TOPTMP/ex.log" | tr '\n' '|')"
else
  pass "T-stub-respell-degrades: respelled warning -> receipt (today's behaviour); exact spelling -> forfeited + named"
fi

# ── T-stub-version-unknown ──────────────────────────────────────────────────
echo "=== T-stub-version-unknown ==="
STUB_NOVER="$TOPTMP/stub-nover"
mk_stub "$STUB_NOVER" '' 1 ''
V="$(_commit_file "$EMITTED" "$CLEAN_TS" "$TOPTMP/nv.log" "$STUB_NOVER")"
if [ "$V" = "SETUPFAIL" ]; then
  fail_ "T-stub-version-unknown" "fixture setup failed"
elif [ "$V" != "COMMITTED" ] || ! grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/nv.log"; then
  fail_ "T-stub-version-unknown" "a failing 'semgrep --version' cost the receipt — the version line is debuggability, never a gate: $(tail -6 "$TOPTMP/nv.log" | tr '\n' '|')"
elif ! grep -qF 'scanner: semgrep (version unknown)' "$TOPTMP/nv.log"; then
  fail_ "T-stub-version-unknown" "no honest 'version unknown' scanner line — silence here is indistinguishable from the feature not existing: $(tail -6 "$TOPTMP/nv.log" | tr '\n' '|')"
else
  pass "T-stub-version-unknown: version-capture failure degrades to an honest 'version unknown', receipt intact"
fi

# ── T-stub-anchor-indent (review R-BL200-1: the ^ atom pinned by WIDTH) ─────
# Drop the anchor from the hook's detector grep and THIS is the case that goes
# red: an INDENTED exact-spelling warning must NOT count. Semgrep prints the
# real warning at column 0 (canary C1 pins that against the live scanner);
# the `^` exists so indented/nested occurrences — echoed content, quoted
# mentions — never move the count. The forfeit-direction control is
# T-stub-respell-degrades' exact-spelling half. Pin the atom's WIDTH, not just
# its presence (the BL-181 doctrine).
echo "=== T-stub-anchor-indent ==="
STUB_INDENT="$TOPTMP/stub-indent"
mk_stub "$STUB_INDENT" '  [WARN] Syntax error at line app.ts:1:' 0 '9.99.9-stub'
V="$(_commit_file "$EMITTED" "$CLEAN_TS" "$TOPTMP/ai.log" "$STUB_INDENT")"
if [ "$V" = "SETUPFAIL" ]; then
  fail_ "T-stub-anchor-indent" "fixture setup failed"
elif [ "$V" != "COMMITTED" ] || ! grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/ai.log"; then
  fail_ "T-stub-anchor-indent" "an INDENTED warning moved the count — the ^ anchor has been widened or dropped; indented/nested occurrences would now inflate the forfeit count: $(tail -6 "$TOPTMP/ai.log" | tr '\n' '|')"
else
  pass "T-stub-anchor-indent: an indented exact-spelling warning does not count — the column-0 anchor carries width, not decoration (R-BL200-1)"
fi

# ── T-stub-warn-on-stdout (confirm-round mutant C: the both-streams read) ───
# BL-193's measured lesson: which stream semgrep's status text lands on is
# frontend ROUTING, not contract (the Scan Status header is stderr on this
# host and stdout on the GitHub runner). The detector reads the CONCATENATED
# status file for exactly that reason — and the reviewer's mutant C, swapping
# that read to the stderr file alone, survived every case while C5's literal
# stayed byte-identical. This pins the width: the exact warning arriving on
# STDOUT (banner still on stderr) must still forfeit.
echo "=== T-stub-warn-on-stdout ==="
STUB_WOUT="$TOPTMP/stub-warn-stdout"
mk_stub "$STUB_WOUT" '[WARN] Syntax error at line app.ts:1:' 0 '9.99.9-stub' stdout
V="$(_commit_file "$EMITTED" "$CLEAN_TS" "$TOPTMP/wo.log" "$STUB_WOUT")"
if [ "$V" = "SETUPFAIL" ]; then
  fail_ "T-stub-warn-on-stdout" "fixture setup failed"
elif [ "$V" != "COMMITTED" ]; then
  fail_ "T-stub-warn-on-stdout" "the warn arm must not block: $(tail -6 "$TOPTMP/wo.log" | tr '\n' '|')"
elif grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/wo.log"; then
  fail_ "T-stub-warn-on-stdout" "a stdout-routed exact warning earned the receipt — the detector's read has narrowed to one stream (reviewer mutant C); BL-193 measured routing as frontend-dependent, so this under-detects on real hosts: $(tail -6 "$TOPTMP/wo.log" | tr '\n' '|')"
elif ! grep -qF 'token-stream break' "$TOPTMP/wo.log"; then
  fail_ "T-stub-warn-on-stdout" "forfeited without naming the break: $(tail -8 "$TOPTMP/wo.log" | tr '\n' '|')"
else
  pass "T-stub-warn-on-stdout: a stdout-routed exact warning still forfeits — the concatenated both-streams read carries width (confirm-round mutant C killed)"
fi

# ── T-mutation-verbose-flag ─────────────────────────────────────────────────
echo "=== T-mutation-verbose-flag ==="
if [ "$HAVE_LIVE" -ne 1 ]; then
  skip_ "T-mutation-verbose-flag" "no live semgrep/registry on this host"
else
  MUTV="$TOPTMP/mut-no-verbose"
  if ! _mut_n "$EMITTED" "$MUTV" '--verbose \' '\' 1; then
    fail_ "T-mutation-verbose-flag" "MIS-TARGETED — the '--verbose \\' continuation line is not present exactly once in the emitted hook"
  elif ! bash -n "$MUTV" 2>/dev/null; then
    fail_ "T-mutation-verbose-flag" "mutated hook has a syntax error — a broken mutant proves nothing"
  else
    VM="$(_commit_file "$MUTV" "$BROKEN_TS" "$TOPTMP/mv.log")"
    if [ "$VM" = "SETUPFAIL" ]; then
      fail_ "T-mutation-verbose-flag" "mutation fixture setup failed"
    elif ! grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/mv.log"; then
      fail_ "T-mutation-verbose-flag" "without --verbose the broken commit did NOT buy the receipt back — this case is not measuring the flag it names: $(tail -6 "$TOPTMP/mv.log" | tr '\n' '|')"
    elif ! { V2="$(_commit_file "$EMITTED" "$BROKEN_TS" "$TOPTMP/mv2.log")" && [ "$V2" = "COMMITTED" ] && ! grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/mv2.log"; }; then
      fail_ "T-mutation-verbose-flag" "the INTACT control did not forfeit — the mutant half is meaningless without it: $(tail -6 "$TOPTMP/mv2.log" | tr '\n' '|')"
    else
      pass "T-mutation-verbose-flag: stripping --verbose blinds the detector (RED); intact hook forfeits (GREEN) — the flag is load-bearing"
    fi
  fi
fi

# ── T-mutation-syntax-clause ────────────────────────────────────────────────
echo "=== T-mutation-syntax-clause ==="
if [ "$HAVE_LIVE" -ne 1 ]; then
  skip_ "T-mutation-syntax-clause" "no live semgrep/registry on this host"
else
  MUTC="$TOPTMP/mut-no-clause"
  if ! _mut_n "$EMITTED" "$MUTC" '&& [ "$soif_sg_syntax" -eq 0 ]' '' 1; then
    fail_ "T-mutation-syntax-clause" "MIS-TARGETED — the syntax conjunct is not present exactly once in the emitted hook"
  elif ! bash -n "$MUTC" 2>/dev/null; then
    fail_ "T-mutation-syntax-clause" "mutated hook has a syntax error — a broken mutant proves nothing"
  else
    VM="$(_commit_file "$MUTC" "$BROKEN_TS" "$TOPTMP/mc.log")"
    if [ "$VM" = "SETUPFAIL" ]; then
      fail_ "T-mutation-syntax-clause" "mutation fixture setup failed"
    elif ! grep -qF '[OK] semgrep: SAST ran' "$TOPTMP/mc.log"; then
      fail_ "T-mutation-syntax-clause" "dropping the syntax conjunct did NOT buy the receipt back — selection or timeout moved instead; this case is not isolating its clause: $(tail -6 "$TOPTMP/mc.log" | tr '\n' '|')"
    else
      pass "T-mutation-syntax-clause: the third conjunct carries its own weight — dropped, the break buys [OK] (RED); the intact GREEN half is T-break-forfeits-receipt"
    fi
  fi
fi

echo ""
if [ "${SKIPPED:-0}" -gt 0 ]; then
  echo "!! ${SKIPPED} case(s) SKIPPED — skipped != passed."
fi
echo "Results: $PASSED passed, $FAILED failed${SKIPPED:+ (${SKIPPED} skipped)}"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
