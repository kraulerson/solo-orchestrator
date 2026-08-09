#!/usr/bin/env bash
# tests/test-f015-tamper-pin-allowlist.sh — the detector-of-the-detector for
# F-015 (Karl, 2026-08-09: "Harden it" — option (a)).
#
# WHY THIS EXISTS
#   BUG-009 shipped ten correct, execution-verified CI templates: each runs the
#   phase gate with a BARE invocation, so the gate's exit code decides the step.
#   The regression detector meant to keep it that way — Cw6-strict in
#   tests/test-bl147-ci-template-integrity.sh — matched swallow shapes with a
#   BLACKLIST, `(\|\||;)\s*(echo|true|:)`. BUG-009's confirm review (finding
#   R-C1) proved by mutation that
#       bash scripts/check-phase-gate.sh || exit 0
#   walks straight through the entire bl147 suite: `exit` is simply not in the
#   alternation. Blacklists lose to creativity.
#
#   Cw6-strict is now an ALLOWLIST: the phase-gate step's `run:` body must be
#   the known-good script VERBATIM (indentation, blank lines and whole-line
#   comments normalized away — the only three edits that cannot change what
#   bash executes). Anything else fails, including shapes nobody enumerated.
#
# WHAT THIS SUITE PROVES — and the reason it is a separate file: the claim is
#   about the DETECTOR's behaviour under tampering, which can only be measured
#   by running the real bl147 suite against tampered copies of the real
#   templates. Asserting it inside bl147 would be the pin grading itself.
#     G1  the ten SHIPPED templates still pass — the real suite, the real tree.
#         A hardened pin that reds correct templates is worse than the
#         blacklist it replaced, so this case comes first.
#     G2  the fixture mirror is faithful (baseline copy passes identically).
#     G3  the allowlist tolerates edits that cannot change execution (a comment
#         inside the run body) — it is strict, not superstitious.
#     M1  `|| exit 0`            — the shape R-C1 proved the blacklist missed.
#     M2  `| cat`                — pipe; the pipeline's status is cat's.
#     M3  `&`                    — background; the step exits 0 immediately.
#     M4  `if ! …; then …; fi`   — wrapper; the compound returns 0.
#     M5  a trailing command AFTER the invocation — last command wins. This one
#         is invisible to ANY pin scoped to the invocation LINE, which is why
#         the allowlist is over the whole body.
#     M6  `sh …; exit 0`         — a different interpreter. The old pin's
#         pre-filter was `bash scripts/check-phase-gate\.sh`, so this shape was
#         never even selected for inspection.
#     M7  `continue-on-error: true` — the Actions-native swallow, plus the new
#         step-KEY allowlist that catches its unimagined siblings.
#    M10  `if: false` — the swallow that leaves the run: body byte-identical and
#         the key set untouched. A step that never runs discards the verdict
#         more completely than `|| true` ever could, so the if: VALUE is
#         allowlisted too, and this is the only case that can see it.
#     M8  DUAL DIRECTION: neuter the allowlist verdict in the pin itself and the
#         M1 tamper sails through — the pin, not something else, is what caught
#         it.
#     M9  the vacuity discriminator earns its place: neuter the scope filter so
#         zero templates are examined, and Cw6-strict-scope goes red while
#         Cw6-strict would otherwise pass over an empty set.
#    M11  DUAL DIRECTION for M10: with the if: verdict neutered, `if: false`
#         passes the ENTIRE suite — body allowlist, key allowlist, floor and
#         all. That is M10's watched-RED, made permanent.
#
# R-F015-1 (review, 2026-08-09) — THE SAME DEFECT ONE LEVEL UP. A step-scoped
#   pin cannot see a JOB that never runs or a WORKFLOW that never triggers, and
#   those discard the verdict exactly as completely as `if: false` on the step
#   did. Measured before the fix: job-level `if: false` passed all 82 checks at
#   rc=0, and `on:` gutted to `workflow_dispatch` only passed all 82 at rc=0.
#     A/RA  job-level `if: false`
#     C/RC  job-level `if: ${{ github.event_name == 'never' }}` — before the fix
#           this was caught only INCIDENTALLY, by an unrelated pin that objects
#           to `${{ }}` (Cg8-env-indirection). RC therefore asserts the
#           Cw6-strict-job verdict BY NAME: an incidental catch is not a pin.
#     B/RB  `on:` reduced to `workflow_dispatch:` — the workflow stops running
#           on push and pull_request, so the gate never executes on any change.
#     RA2/RB2  dual direction for each new verdict line.
#
# MUTATION-HARNESS STANDARD (all asserted, none assumed): anchored end-of-line
#   target patterns; sites==1; exactly-N-lines-changed; every mutant is checked
#   with `bash -n` (for a YAML template, the extracted run: body is what gets
#   parsed — a mutant that merely breaks the shell proves nothing); a FRESH
#   fixture per mutant, named after the mutant and never after a counter; and
#   the harness never chmods, never writes, and never copies over anything in
#   the tracked tree — the mirror is symlinks plus one copy of templates/.
#
# REGISTRATION: no init.sh, not an aggregator -> BOTH the aggregator
# (tests/full-project-test-suite.sh) and the tests.yml unit list.
# Hermetic: reads tracked files, writes only under mktemp -d. bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BL147_REL="tests/test-bl147-ci-template-integrity.sh"
BL147="$REPO_ROOT/$BL147_REL"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 - $2"; FAILED=$((FAILED + 1)); }

if [ ! -f "$BL147" ]; then
  echo "  [FAIL] F0-target-present - $BL147_REL is missing; every case below would be vacuous"
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# The exact case-line greps. `Cw6-strict-scope` contains `Cw6-strict` as a
# prefix, so every predicate below matches the case name plus the SPACE that
# separates it from fail_()'s em dash.
FAIL_STRICT='^[[:space:]]*\[FAIL\] Cw6-strict[[:space:]]'
PASS_STRICT='^[[:space:]]*\[PASS\] Cw6-strict[[:space:]]'
FAIL_SCOPE='^[[:space:]]*\[FAIL\] Cw6-strict-scope[[:space:]]'
PASS_SCOPE='^[[:space:]]*\[PASS\] Cw6-strict-scope[[:space:]]'
FAIL_COE='^[[:space:]]*\[FAIL\] Cw6-strict-no-coe[[:space:]]'
FAIL_KEYS='^[[:space:]]*\[FAIL\] Cw6-strict-keys[[:space:]]'
PASS_KEYS='^[[:space:]]*\[PASS\] Cw6-strict-keys[[:space:]]'
PASS_GATING='^[[:space:]]*\[PASS\] Cw6-strict-gating[[:space:]]'
FAIL_JOB='^[[:space:]]*\[FAIL\] Cw6-strict-job[[:space:]]'
PASS_JOB='^[[:space:]]*\[PASS\] Cw6-strict-job[[:space:]]'
FAIL_TRIGGER='^[[:space:]]*\[FAIL\] Cw6-strict-trigger[[:space:]]'
PASS_TRIGGER='^[[:space:]]*\[PASS\] Cw6-strict-trigger[[:space:]]'

# ── The fixture mirror ──────────────────────────────────────────────────────
# bl147 derives every path from REPO_ROOT = the parent of its own directory, so
# a mirror is just a directory whose children look like the repo's. Everything
# except templates/ and tests/ is SYMLINKED: no copy means no mode to get wrong
# and no tracked byte at risk (a scratch script's hard chmod silently changed a
# tracked file's mode twice this wave). templates/ is a real copy because the
# mutants edit it; tests/ holds a copy of the pin suite because M8 and M9 edit
# the SUITE.
mk_fix() {  # mk_fix <name> -> sets MK_FIX to the fixture root
  local name="$1"
  MK_FIX="$TOPTMP/fx-$name"
  rm -rf "$MK_FIX"
  mkdir -p "$MK_FIX/tests" || return 1
  local e base
  for e in "$REPO_ROOT"/* "$REPO_ROOT"/.github; do
    base="${e##*/}"
    case "$base" in templates|tests) continue ;; esac
    [ -e "$e" ] || continue
    ln -s "$e" "$MK_FIX/$base" || return 1
  done
  cp -R "$REPO_ROOT/templates" "$MK_FIX/templates" || return 1
  cp "$BL147" "$MK_FIX/$BL147_REL" || return 1
  return 0
}

run_pin() {  # run_pin <fixture-root> -> stdout is the suite's output; rc is its exit code
  bash "$1/$BL147_REL" 2>&1
}

# ── The mutation applier ────────────────────────────────────────────────────
# prep_mutant <name> <relpath> <target-ERE> <transform-fn> <exp-removed> <exp-added>
# On success sets MK_FIX to a fresh, mutated fixture and returns 0. On failure
# sets MUT_WHY and returns 1 — the caller reports it as a FAILED case, never as
# a skip: an unapplied mutant proves nothing, and silence would look like a pass.
MUT_WHY=""
prep_mutant() {
  local name="$1" rel="$2" ere="$3" fn="$4" exp_rm="$5" exp_add="$6"
  MUT_WHY=""
  mk_fix "$name" || { MUT_WHY="could not build the fixture mirror"; return 1; }
  local tgt="$MK_FIX/$rel"
  local orig="$TOPTMP/orig-$name"
  [ -f "$tgt" ] || { MUT_WHY="$rel is not in the fixture"; return 1; }
  cp "$tgt" "$orig" || { MUT_WHY="could not snapshot $rel"; return 1; }

  # sites==1: an anchored pattern that matches twice would mutate two places,
  # and one that matches zero times would mutate nothing while the case still
  # ran.
  local sites
  sites=$(grep -Ec "$ere" "$orig")
  if [ "$sites" -ne 1 ]; then
    MUT_WHY="sites==$sites for /$ere/ in $rel (expected exactly 1) — the mutant is ambiguous or vacuous"
    return 1
  fi

  # Write THROUGH the existing inode (cat >) rather than replacing it, so the
  # fixture file keeps its mode.
  "$fn" < "$orig" > "$TOPTMP/new-$name" || { MUT_WHY="the transform failed"; return 1; }
  cat "$TOPTMP/new-$name" > "$tgt" || { MUT_WHY="could not write the mutant"; return 1; }

  local n_rm n_add
  n_rm=$(diff "$orig" "$tgt" | grep -c '^<')
  n_add=$(diff "$orig" "$tgt" | grep -c '^>')
  if [ "$n_rm" -ne "$exp_rm" ] || [ "$n_add" -ne "$exp_add" ]; then
    MUT_WHY="the edit changed $n_rm removed / $n_add added lines (expected $exp_rm / $exp_add) — not the single-line mutation this case describes"
    return 1
  fi

  # `bash -n` on every mutant. For a .sh that is the file; for a CI template it
  # is the phase-gate step's run: body, dedented — the actual shell the runner
  # would execute. A mutant that is not valid shell proves nothing.
  local bn="$TOPTMP/bn-$name"
  case "$rel" in
    *.sh)
      if ! bash -n "$tgt" 2>"$bn"; then
        MUT_WHY="the mutated $rel is not valid bash: $(tr '\n' ' ' < "$bn")"
        return 1
      fi
      ;;
    *.yml)
      awk '
        /^      - name: Governance - Phase gate check$/ { inside = 1; next }
        inside && /^      - name: / { exit }
        inside && /^[[:space:]]*run:[[:space:]]*\|/ { body = 1; next }
        body { print }
      ' "$tgt" | sed 's/^[[:space:]]*//' > "$TOPTMP/body-$name.sh"
      if [ ! -s "$TOPTMP/body-$name.sh" ]; then
        MUT_WHY="the mutant left no extractable run: body — the case would measure the extraction, not the pin"
        return 1
      fi
      if ! bash -n "$TOPTMP/body-$name.sh" 2>"$bn"; then
        MUT_WHY="the mutated run: body is not valid bash, so the tamper is a typo rather than a swallow: $(tr '\n' ' ' < "$bn")"
        return 1
      fi
      ;;
  esac
  return 0
}

# The one line every template shares, anchored at both ends.
INV_ERE='^          bash scripts/check-phase-gate\.sh$'

# ── G1: the SHIPPED templates, the REAL suite, the REAL tree ────────────────
# First, because the whole risk of hardening a pin is that it reds the correct
# thing. This is not a fixture: it is the tracked tree as it will be merged.
echo "=== G1-shipped-templates-still-pass ==="
g1_out=$(bash "$BL147" 2>&1); g1_rc=$?
if [ "$g1_rc" -eq 0 ] \
   && printf '%s\n' "$g1_out" | grep -Eq "$PASS_STRICT" \
   && printf '%s\n' "$g1_out" | grep -Eq "$PASS_SCOPE" \
   && printf '%s\n' "$g1_out" | grep -Eq "$PASS_KEYS" \
   && printf '%s\n' "$g1_out" | grep -Eq "$PASS_GATING" \
   && printf '%s\n' "$g1_out" | grep -Eq "$PASS_JOB" \
   && printf '%s\n' "$g1_out" | grep -Eq "$PASS_TRIGGER"; then
  pass "G1-shipped-templates-still-pass (the real bl147 suite is green on the tracked templates; the allowlist passes all ten)"
else
  fail_ "G1-shipped-templates-still-pass" "rc=$g1_rc — the hardened pin reds the SHIPPED templates, which is worse than the blacklist it replaced: $(printf '%s\n' "$g1_out" | grep -E '\[FAIL\]' | tr '\n' ' ')"
fi

# ── G2: the mirror is faithful ──────────────────────────────────────────────
echo "=== G2-fixture-mirror-is-faithful ==="
if mk_fix baseline; then
  g2_out=$(run_pin "$MK_FIX"); g2_rc=$?
  if [ "$g2_rc" -eq 0 ] && printf '%s\n' "$g2_out" | grep -Eq "$PASS_STRICT"; then
    pass "G2-fixture-mirror-is-faithful (an untampered mirror reproduces the real green run — every M-case's signal is the tamper)"
  else
    fail_ "G2-fixture-mirror-is-faithful" "rc=$g2_rc — the mirror is not green before tampering, so no mutant below is attributable: $(printf '%s\n' "$g2_out" | grep -E '\[FAIL\]' | tr '\n' ' ')"
  fi
else
  fail_ "G2-fixture-mirror-is-faithful" "could not build the mirror"
fi

# ── G3: strict, not superstitious ───────────────────────────────────────────
# A comment line inside the run: body cannot change what bash executes, so the
# allowlist must accept it. Without this case, "the pin is an allowlist" and
# "the pin forbids all edits" are indistinguishable.
t_g3() { awk '/^          bash scripts\/check-phase-gate\.sh$/ { print "          # a note for the next reader" } { print }'; }
echo "=== G3-inert-comment-tolerated ==="
if prep_mutant g3 templates/pipelines/ci/github/other.yml "$INV_ERE" t_g3 0 1; then
  g3_out=$(run_pin "$MK_FIX"); g3_rc=$?
  if [ "$g3_rc" -eq 0 ] && printf '%s\n' "$g3_out" | grep -Eq "$PASS_STRICT"; then
    pass "G3-inert-comment-tolerated (a comment in the run: body is not a deviation — the allowlist normalizes exactly what cannot execute)"
  else
    fail_ "G3-inert-comment-tolerated" "rc=$g3_rc — the pin reds on an inert comment; it is a freeze, not an allowlist: $(printf '%s\n' "$g3_out" | grep -E '\[FAIL\]' | tr '\n' ' ')"
  fi
else
  fail_ "G3-inert-comment-tolerated" "$MUT_WHY"
fi

# ── The tamper cases ────────────────────────────────────────────────────────
# assert_caught <case> <fixture-root> <template-suffix> <human-why>
# Caught for the RIGHT REASON: rc non-zero is not enough (the suite has ~40
# other cases). The Cw6-strict FAIL line itself must name the tampered
# template, and Cw6-strict-scope must still be green — a red scope case would
# mean the pin examined nothing and the FAIL came from the vacuity guard.
assert_caught() {
  local case_name="$1" fx="$2" tmpl="$3" why="$4"
  local out rc
  out=$(run_pin "$fx"); rc=$?
  local line
  line=$(printf '%s\n' "$out" | grep -E "$FAIL_STRICT")
  if [ "$rc" -ne 0 ] \
     && [ -n "$line" ] \
     && printf '%s\n' "$line" | grep -Fq "$tmpl" \
     && printf '%s\n' "$out" | grep -Eq "$PASS_SCOPE"; then
    pass "$case_name ($why — Cw6-strict names $tmpl)"
  else
    fail_ "$case_name" "rc=$rc; Cw6-strict FAIL line=[${line:-<none>}]; scope-case=[$(printf '%s\n' "$out" | grep -E 'Cw6-strict-scope' | tr '\n' ' ')] — the tamper was not caught by the allowlist for the right reason"
  fi
}

t_m1() { sed 's#^          bash scripts/check-phase-gate\.sh$#          bash scripts/check-phase-gate.sh || exit 0#'; }
echo "=== M1-unenumerated-or-exit ==="
if prep_mutant m1 templates/pipelines/ci/github/swift.yml "$INV_ERE" t_m1 1 1; then
  assert_caught M1-unenumerated-or-exit "$MK_FIX" github/swift.yml \
    "\`|| exit 0\` — the exact shape R-C1 proved the blacklist let through"
else
  fail_ "M1-unenumerated-or-exit" "$MUT_WHY"
fi

t_m2() { sed 's#^          bash scripts/check-phase-gate\.sh$#          bash scripts/check-phase-gate.sh | cat#'; }
echo "=== M2-unenumerated-pipe ==="
if prep_mutant m2 templates/pipelines/ci/github/python.yml "$INV_ERE" t_m2 1 1; then
  assert_caught M2-unenumerated-pipe "$MK_FIX" github/python.yml \
    "a pipe — the pipeline reports cat's status, never the gate's"
else
  fail_ "M2-unenumerated-pipe" "$MUT_WHY"
fi

# `&` is the whole match in a sed replacement, hence the backslash.
t_m3() { sed 's#^          bash scripts/check-phase-gate\.sh$#          bash scripts/check-phase-gate.sh \&#'; }
echo "=== M3-unenumerated-background ==="
if prep_mutant m3 templates/pipelines/ci/github/go.yml "$INV_ERE" t_m3 1 1; then
  assert_caught M3-unenumerated-background "$MK_FIX" github/go.yml \
    "a trailing \`&\` — the gate is backgrounded and the step exits 0 before it decides anything"
else
  fail_ "M3-unenumerated-background" "$MUT_WHY"
fi

t_m4() { sed 's#^          bash scripts/check-phase-gate\.sh$#          if ! bash scripts/check-phase-gate.sh; then echo "::warning::phase gate soft-failed"; fi#'; }
echo "=== M4-unenumerated-wrapper ==="
if prep_mutant m4 templates/pipelines/ci/github/rust.yml "$INV_ERE" t_m4 1 1; then
  assert_caught M4-unenumerated-wrapper "$MK_FIX" github/rust.yml \
    "an \`if !\` wrapper — the compound command succeeds however the gate votes"
else
  fail_ "M4-unenumerated-wrapper" "$MUT_WHY"
fi

t_m5() { awk '{ print } /^          bash scripts\/check-phase-gate\.sh$/ { print "          echo \"phase gate step complete\"" }'; }
echo "=== M5-unenumerated-trailing-command ==="
if prep_mutant m5 templates/pipelines/ci/github/typescript.yml "$INV_ERE" t_m5 0 1; then
  assert_caught M5-unenumerated-trailing-command "$MK_FIX" github/typescript.yml \
    "a command AFTER the invocation — the script's status is the LAST command's, and no pin scoped to the invocation line can see this"
else
  fail_ "M5-unenumerated-trailing-command" "$MUT_WHY"
fi

t_m6() { sed 's#^          bash scripts/check-phase-gate\.sh$#          sh scripts/check-phase-gate.sh; exit 0#'; }
echo "=== M6-unenumerated-interpreter-swap ==="
if prep_mutant m6 templates/pipelines/ci/github/dart.yml "$INV_ERE" t_m6 1 1; then
  assert_caught M6-unenumerated-interpreter-swap "$MK_FIX" github/dart.yml \
    "a different interpreter plus \`exit 0\` — the old pin's pre-filter required the literal \`bash \`, so it never even inspected this line"
else
  fail_ "M6-unenumerated-interpreter-swap" "$MUT_WHY"
fi

# ── M7: the Actions-native swallow and the step-KEY allowlist ───────────────
# `continue-on-error: true` grades a red step GREEN without touching the shell
# at all. The named pin catches that one key; the key allowlist catches the
# ones nobody has thought of, because only `if`, `env` and `run` are permitted.
t_m7() { awk '{ print } /^      - name: Governance - Phase gate check$/ { print "        continue-on-error: true" }'; }
echo "=== M7-actions-native-swallow ==="
if prep_mutant m7 templates/pipelines/ci/github/java.yml \
     '^      - name: Governance - Phase gate check$' t_m7 0 1; then
  m7_out=$(run_pin "$MK_FIX"); m7_rc=$?
  if [ "$m7_rc" -ne 0 ] \
     && printf '%s\n' "$m7_out" | grep -E "$FAIL_COE" | grep -Fq github/java.yml \
     && printf '%s\n' "$m7_out" | grep -E "$FAIL_KEYS" | grep -Fq 'continue-on-error'; then
    pass "M7-actions-native-swallow (the named pin AND the step-key allowlist both red — an unimagined step key would be caught by the second even if the first never learns its name)"
  else
    fail_ "M7-actions-native-swallow" "rc=$m7_rc coe=[$(printf '%s\n' "$m7_out" | grep -E 'Cw6-strict-no-coe' | tr '\n' ' ')] keys=[$(printf '%s\n' "$m7_out" | grep -E 'Cw6-strict-keys' | tr '\n' ' ')]"
  fi
else
  fail_ "M7-actions-native-swallow" "$MUT_WHY"
fi

# ── M10: the swallow that leaves the body untouched ─────────────────────────
# A key allowlist alone would have missed this: `if:` is a PERMITTED key, and
# the run: body is byte-identical to the allowlisted script. A step that never
# runs discards the verdict more completely than `|| true` ever could, so the
# if: VALUE is allowlisted too.
t_m10() { sed "s#^        if: hashFiles('\.claude/phase-state\.json') != ''\$#        if: false#"; }
echo "=== M10-unenumerated-step-never-runs ==="
if prep_mutant m10 templates/pipelines/ci/github/kotlin.yml \
     "^        if: hashFiles\('\.claude/phase-state\.json'\) != ''\$" t_m10 1 1; then
  m10_out=$(run_pin "$MK_FIX"); m10_rc=$?
  if [ "$m10_rc" -ne 0 ] \
     && printf '%s\n' "$m10_out" | grep -E '^[[:space:]]*\[FAIL\] Cw6-strict-gating[[:space:]]' | grep -Fq github/kotlin.yml \
     && printf '%s\n' "$m10_out" | grep -Eq "$PASS_STRICT"; then
    pass "M10-unenumerated-step-never-runs (\`if: false\` leaves the allowlisted body intact and is still caught — by the if: allowlist, which is the only case that can see it)"
  else
    fail_ "M10-unenumerated-step-never-runs" "rc=$m10_rc gating=[$(printf '%s\n' "$m10_out" | grep -E 'Cw6-strict-gating' | tr '\n' ' ')] — a step that never runs was graded as enforcing"
  fi
else
  fail_ "M10-unenumerated-step-never-runs" "$MUT_WHY"
fi

# ════════════════════════════════════════════════════════════════════════════
# R-F015-1 — the class one level up: the JOB and the WORKFLOW
# ════════════════════════════════════════════════════════════════════════════
# The step allowlist is necessary and not sufficient. A step that runs perfectly
# inside a job that never starts, or a workflow that never triggers on a change,
# discards the verdict as completely as `|| true` ever did — and by exactly the
# argument that earned Cw6-strict-gating its place at the step level.
#
# assert_caught_by <case> <fixture> <FAIL-ere> <case-label> <template> <why>
# Same "right reason" discipline as assert_caught, parameterised on which of the
# new verdicts must be the one that fires.
assert_caught_by() {
  local case_name="$1" fx="$2" fail_ere="$3" label="$4" tmpl="$5" why="$6"
  local out rc line
  out=$(run_pin "$fx"); rc=$?
  line=$(printf '%s\n' "$out" | grep -E "$fail_ere")
  if [ "$rc" -ne 0 ] \
     && [ -n "$line" ] \
     && printf '%s\n' "$line" | grep -Fq "$tmpl" \
     && printf '%s\n' "$out" | grep -Eq "$PASS_SCOPE"; then
    pass "$case_name ($why — $label names $tmpl)"
  else
    fail_ "$case_name" "rc=$rc; $label FAIL line=[${line:-<none>}]; scope=[$(printf '%s\n' "$out" | grep -E 'Cw6-strict-scope' | tr '\n' ' ')] — not caught by $label for the right reason"
  fi
}

# The job header the tamper attaches to. Anchored, and `test:` is the job that
# holds the phase-gate step in all ten templates (RA0 proves that rather than
# assuming it).
JOB_ERE='^  test:$'

t_ra() { awk '{ print } /^  test:$/ { print "    if: false" }'; }
echo "=== RA-job-level-if-false ==="
if prep_mutant ra templates/pipelines/ci/github/python.yml "$JOB_ERE" t_ra 0 1; then
  assert_caught_by RA-job-level-if-false "$MK_FIX" "$FAIL_JOB" Cw6-strict-job github/python.yml \
    'reviewer case A: the JOB never runs, so a perfectly-allowlisted step never executes'
else
  fail_ "RA-job-level-if-false" "$MUT_WHY"
fi

# Reviewer case C. Before the fix this was caught only incidentally, by a pin
# that objects to `${{ }}` appearing where it does not belong — so the assertion
# here is deliberately on Cw6-strict-job BY NAME. An incidental catch is not a
# pin: it moves the moment the incidental pin changes.
t_rc() { awk '{ print } /^  test:$/ { print "    if: ${{ github.event_name == '\''never'\'' }}" }'; }
echo "=== RC-job-level-if-expression ==="
if prep_mutant rc templates/pipelines/ci/github/csharp.yml "$JOB_ERE" t_rc 0 1; then
  assert_caught_by RC-job-level-if-expression "$MK_FIX" "$FAIL_JOB" Cw6-strict-job github/csharp.yml \
    'reviewer case C: an always-false job condition, caught on the job allowlist rather than incidentally on a ${{ }} pin'
else
  fail_ "RC-job-level-if-expression" "$MUT_WHY"
fi

# Reviewer case B. The `on:` block is replaced wholesale, so the site count is
# taken on the block opener and the delta is the whole stanza — declared
# explicitly rather than waved at.
t_rb() { awk '
  /^on:$/ { print; print "  workflow_dispatch:"; skip = 1; next }
  skip && (/^[^[:space:]]/ || $0 == "") { skip = 0 }
  skip { next }
  { print }
'; }
echo "=== RB-workflow-never-triggers ==="
if prep_mutant rb templates/pipelines/ci/github/go.yml '^on:$' t_rb 4 1; then
  assert_caught_by RB-workflow-never-triggers "$MK_FIX" "$FAIL_TRIGGER" Cw6-strict-trigger github/go.yml \
    'reviewer case B: the WORKFLOW no longer runs on push or pull_request, so the gate never executes on any change'
else
  fail_ "RB-workflow-never-triggers" "$MUT_WHY"
fi

# ── RA2 / RB2: DUAL DIRECTION for each new verdict ──────────────────────────
t_ra2() { sed 's@^\([[:space:]]*\)\[ "\$_w6_jobkeys" = "\$W6_EXPECTED_JOBKEYS" \].*# F-015-JOB-ALLOWLIST-VERDICT$@\1:@'; }
echo "=== RA2-neutered-job-allowlist-lets-a-dead-job-through ==="
if prep_mutant ra2 "$BL147_REL" \
     '^[[:space:]]*\[ "\$_w6_jobkeys" = "\$W6_EXPECTED_JOBKEYS" \].*# F-015-JOB-ALLOWLIST-VERDICT$' \
     t_ra2 1 1; then
  ra2_tmpl="$MK_FIX/templates/pipelines/ci/github/python.yml"
  ra2_sites=$(grep -Ec "$JOB_ERE" "$ra2_tmpl")
  t_ra < "$ra2_tmpl" > "$TOPTMP/ra2-tampered"
  cat "$TOPTMP/ra2-tampered" > "$ra2_tmpl"
  ra2_out=$(run_pin "$MK_FIX"); ra2_rc=$?
  if [ "$ra2_sites" -eq 1 ] \
     && grep -Fq '    if: false' "$ra2_tmpl" \
     && [ "$ra2_rc" -eq 0 ] \
     && printf '%s\n' "$ra2_out" | grep -Eq "$PASS_SCOPE"; then
    pass "RA2-neutered-job-allowlist-lets-a-dead-job-through (with the job verdict gone, a job that never runs passes the ENTIRE suite — reproducing the pre-fix measurement exactly)"
  else
    fail_ "RA2-neutered-job-allowlist-lets-a-dead-job-through" "sites=$ra2_sites rc=$ra2_rc — the neutered pin did not go quiet: $(printf '%s\n' "$ra2_out" | grep -E '\[FAIL\]' | tr '\n' ' ')"
  fi
else
  fail_ "RA2-neutered-job-allowlist-lets-a-dead-job-through" "$MUT_WHY"
fi

t_rb2() { sed 's@^\([[:space:]]*\)\[ "\$_w6_on" = "\$W6_EXPECTED_ON" \].*# F-015-TRIGGER-ALLOWLIST-VERDICT$@\1:@'; }
echo "=== RB2-neutered-trigger-allowlist-lets-a-dead-workflow-through ==="
if prep_mutant rb2 "$BL147_REL" \
     '^[[:space:]]*\[ "\$_w6_on" = "\$W6_EXPECTED_ON" \].*# F-015-TRIGGER-ALLOWLIST-VERDICT$' \
     t_rb2 1 1; then
  rb2_tmpl="$MK_FIX/templates/pipelines/ci/github/go.yml"
  rb2_sites=$(grep -Ec '^on:$' "$rb2_tmpl")
  t_rb < "$rb2_tmpl" > "$TOPTMP/rb2-tampered"
  cat "$TOPTMP/rb2-tampered" > "$rb2_tmpl"
  rb2_out=$(run_pin "$MK_FIX"); rb2_rc=$?
  if [ "$rb2_sites" -eq 1 ] \
     && ! grep -q '^  push:$' "$rb2_tmpl" \
     && [ "$rb2_rc" -eq 0 ] \
     && printf '%s\n' "$rb2_out" | grep -Eq "$PASS_SCOPE"; then
    pass "RB2-neutered-trigger-allowlist-lets-a-dead-workflow-through (with the trigger verdict gone, a workflow that never runs on push passes the ENTIRE suite — reproducing the pre-fix measurement exactly)"
  else
    fail_ "RB2-neutered-trigger-allowlist-lets-a-dead-workflow-through" "sites=$rb2_sites rc=$rb2_rc — the neutered pin did not go quiet: $(printf '%s\n' "$rb2_out" | grep -E '\[FAIL\]' | tr '\n' ' ')"
  fi
else
  fail_ "RB2-neutered-trigger-allowlist-lets-a-dead-workflow-through" "$MUT_WHY"
fi

# ── M8: DUAL DIRECTION — neuter the pin, the tamper sails through ───────────
# Everything above shows tampers going red. This shows WHY: remove the
# allowlist's verdict line from the pin and M1's tamper stops being detected.
# Without this leg, "the tamper is caught" and "something else in the suite is
# red" are the same observation.
t_m8() { sed 's@^\([[:space:]]*\)if \[ "\$_w6_body" != "\$W6_EXPECTED_BODY" \]; then.*# F-015-BODY-ALLOWLIST-VERDICT$@\1if false; then@'; }
echo "=== M8-neutered-pin-lets-the-tamper-through ==="
if prep_mutant m8 "$BL147_REL" \
     '^[[:space:]]*if \[ "\$_w6_body" != "\$W6_EXPECTED_BODY" \]; then.*# F-015-BODY-ALLOWLIST-VERDICT$' \
     t_m8 1 1; then
  # Apply M1's tamper on top of the neutered pin, in the SAME fixture.
  m8_tmpl="$MK_FIX/templates/pipelines/ci/github/swift.yml"
  m8_sites=$(grep -Ec "$INV_ERE" "$m8_tmpl")
  t_m1 < "$m8_tmpl" > "$TOPTMP/m8-tampered"
  cat "$TOPTMP/m8-tampered" > "$m8_tmpl"
  m8_out=$(run_pin "$MK_FIX"); m8_rc=$?
  if [ "$m8_sites" -eq 1 ] \
     && grep -Fq 'bash scripts/check-phase-gate.sh || exit 0' "$m8_tmpl" \
     && printf '%s\n' "$m8_out" | grep -Eq "$PASS_STRICT" \
     && printf '%s\n' "$m8_out" | grep -Eq "$PASS_SCOPE"; then
    pass "M8-neutered-pin-lets-the-tamper-through (with the verdict line gone the \`|| exit 0\` tamper passes — the allowlist is load-bearing, exactly as the blacklist was not)"
  else
    fail_ "M8-neutered-pin-lets-the-tamper-through" "sites=$m8_sites rc=$m8_rc strict=[$(printf '%s\n' "$m8_out" | grep -E 'Cw6-strict[[:space:]]' | tr '\n' ' ')] — the neutered pin did not go quiet, so the M-cases above may be measuring something else"
  fi
else
  fail_ "M8-neutered-pin-lets-the-tamper-through" "$MUT_WHY"
fi

# ── M11: DUAL DIRECTION for the if: allowlist ───────────────────────────────
# The other half of M10, and its watched-RED made permanent: with the if:
# verdict neutered, `if: false` passes the whole suite — body allowlist, key
# allowlist, count floor and all. Nothing else in bl147 can see it.
t_m11() { sed 's@^\([[:space:]]*\)\[ "\$_w6_if" = "\$W6_EXPECTED_IF" \].*# F-015-IF-ALLOWLIST-VERDICT$@\1:@'; }
echo "=== M11-neutered-if-allowlist-lets-a-dead-step-through ==="
if prep_mutant m11 "$BL147_REL" \
     '^[[:space:]]*\[ "\$_w6_if" = "\$W6_EXPECTED_IF" \].*# F-015-IF-ALLOWLIST-VERDICT$' \
     t_m11 1 1; then
  m11_tmpl="$MK_FIX/templates/pipelines/ci/github/kotlin.yml"
  m11_sites=$(grep -Ec "^        if: hashFiles\('\.claude/phase-state\.json'\) != ''\$" "$m11_tmpl")
  t_m10 < "$m11_tmpl" > "$TOPTMP/m11-tampered"
  cat "$TOPTMP/m11-tampered" > "$m11_tmpl"
  m11_out=$(run_pin "$MK_FIX"); m11_rc=$?
  if [ "$m11_sites" -eq 1 ] \
     && grep -Fq '        if: false' "$m11_tmpl" \
     && [ "$m11_rc" -eq 0 ] \
     && printf '%s\n' "$m11_out" | grep -Eq "$PASS_SCOPE"; then
    pass "M11-neutered-if-allowlist-lets-a-dead-step-through (with the if: verdict gone, a step that never runs passes the ENTIRE suite — the if: allowlist is the only thing standing between the tree and that swallow)"
  else
    fail_ "M11-neutered-if-allowlist-lets-a-dead-step-through" "sites=$m11_sites rc=$m11_rc — the neutered pin did not go quiet, so M10 may be measuring another case: $(printf '%s\n' "$m11_out" | grep -E '\[FAIL\]' | tr '\n' ' ')"
  fi
else
  fail_ "M11-neutered-if-allowlist-lets-a-dead-step-through" "$MUT_WHY"
fi

# ── M9: the absence-discriminator earns its place ───────────────────────────
# Cw6-strict's green is an ABSENCE (no template deviated), and an absence is
# also what an empty candidate set produces. Neuter the scope filter so every
# template is skipped: Cw6-strict still passes over nothing, and only
# Cw6-strict-scope tells the truth.
t_m9() { sed 's@^\([[:space:]]*\)grep -Eq .*# F-015-STRICT-SCOPE-FILTER$@\1continue@'; }
echo "=== M9-scope-floor-catches-the-empty-set ==="
if prep_mutant m9 "$BL147_REL" \
     '^[[:space:]]*grep -Eq .*# F-015-STRICT-SCOPE-FILTER$' t_m9 1 1; then
  m9_out=$(run_pin "$MK_FIX"); m9_rc=$?
  if [ "$m9_rc" -ne 0 ] \
     && printf '%s\n' "$m9_out" | grep -Eq "$FAIL_SCOPE" \
     && printf '%s\n' "$m9_out" | grep -Eq "$PASS_STRICT"; then
    pass "M9-scope-floor-catches-the-empty-set (examining nothing makes Cw6-strict pass vacuously and Cw6-strict-scope red — the floor is what distinguishes clean from empty)"
  else
    fail_ "M9-scope-floor-catches-the-empty-set" "rc=$m9_rc scope=[$(printf '%s\n' "$m9_out" | grep -E 'Cw6-strict-scope' | tr '\n' ' ')] strict=[$(printf '%s\n' "$m9_out" | grep -E 'Cw6-strict[[:space:]]' | tr '\n' ' ')]"
  fi
else
  fail_ "M9-scope-floor-catches-the-empty-set" "$MUT_WHY"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
