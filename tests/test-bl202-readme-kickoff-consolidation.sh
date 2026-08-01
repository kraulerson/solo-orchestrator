#!/usr/bin/env bash
# tests/test-bl202-readme-kickoff-consolidation.sh — BL-202 residual 2.
#
# THE DEFECT THIS PINS SHUT
#   BL-202 established scripts/resume.sh as the SINGLE state-aware generator of
#   "what do I paste into Claude Code" (three branches: intake prompt / the
#   project's own PROJECT_INTAKE.md Section 13 block verbatim / the classic
#   resume prompt). Every print in the wizard and in the initialization script
#   was converged onto that one sentence. README.md § Quick Start was NOT: it
#   kept a hand-maintained VERBATIM copy of a kickoff paste block — a fourth
#   magic phrase, maintained by hand, already diverging from Section 13.
#   BL-202's own filing says the fix must CONSOLIDATE, not add a fourth.
#
#   Drift of exactly this kind is the BL-199 defect class: the README made a
#   claim about the product that nothing executed and nothing checked, and it
#   was wrong. BL-199 closed the half where the DOCUMENTED COMMAND could not
#   run; nothing closed the half where the DOCUMENTED PROMPT goes stale.
#
# WHY THIS SUITE EXISTS AT ALL (and why it is not "just a docs change")
#   tests/test-bl199-quickstart-from-clone.sh pins the quick-start CONTRACT by
#   BEHAVIOUR — it runs the documented sequence against a fixture clone. Its
#   T1 comment says "the exact shape README § Quick Start now documents", but
#   the suite never opens README.md, so nothing detects the README drifting
#   away from the shape that suite proves. T4 below closes that specific gap.
#
# THE PREDICATES — all six must hold, four of them scoped to § Quick Start
#   T1  § Quick Start names the generator (`bash scripts/resume.sh`).
#   T2  Nowhere in the README is there a hand-maintained kickoff copy. Three
#       literal signatures are forbidden: the old block's opening line, its
#       phase-state bullet, and the opening line of Section 13's prompt (which
#       is what a well-meaning "let's show them the real one" edit would paste
#       in).
#   T2b STRUCTURAL backstop for a REWORDED re-introduction, which no literal
#       can catch: every fenced code block inside § Quick Start must OPEN with
#       an info string (```bash and friends). The stale kickoff block was a
#       BARE ``` fence wrapping prose addressed to the agent, and a prose paste
#       block is what that shape is for. Deliberately a little strict — a
#       legitimate bare fence in this one section has to earn its place — and
#       the failure message says so. M5 proves it does work T2 cannot.
#       OPENERS ONLY: closing fences are bare by construction, so a naive
#       `grep -Eq '^```$'` flags every healthy ```bash block. It did, on this
#       suite's first run. The predicate tracks fence state instead.
#   T3  HONESTY. The README is read by people who have not generated a project
#       yet, and scripts/resume.sh exists ONLY inside a generated project. A
#       pointer that sends a pre-init reader to a script they do not have is a
#       NEW defect, not a fix, so § Quick Start must say so in as many words.
#   T4  The BL-199 activation the sibling suite executes is still the activation
#       the README documents: a BARE project name via --project-dir, which is
#       what makes the sibling-anchor contract (SCRIPT_DIR/.., not the cwd)
#       visible to a reader.
#   T5  BL-202's user-facing reassurance survives: a blank Claude Code screen
#       means ready and waiting, not stuck. That sentence is the whole point of
#       the dead-air entry, and resume.sh prints it on both first-message
#       branches.
#
# MUTATION PROOFS — every predicate is shown load-bearing against a MUTATED
# COPY in a tempdir. The repo's own README is never written to.
#   M1  strip the generator pointer            -> T1 red
#   M2  re-insert the historical kickoff block -> T2 red AND T2b red
#   M3  strip the honesty sentence             -> T3 red
#   M4  reduce --project-dir to a flag with no bare name -> T4 red
#   M5  re-introduce a paste block with ZERO shared literals -> T2 stays
#       GREEN (stated, not papered over: literals cannot see a reword) while
#       T2b goes red. This is the proof that the structural net is not
#       redundant with the literal one.
#
# Hermetic: reads README.md, writes only under its own mktemp -d.
# No init-script invocation, no network, no remote creation.
#
# Self-verify: bash tests/test-bl202-readme-kickoff-consolidation.sh
set -uo pipefail

SUITE_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SUITE_DIR/.." && pwd)"
README="$REPO_ROOT/README.md"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "== tests/test-bl202-readme-kickoff-consolidation.sh =="

if [ ! -f "$README" ]; then
  echo "  [FAIL] fixture — README.md not found at $README"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

# --- Section extraction ---------------------------------------------------
# § Quick Start runs from its own `## Quick Start` heading to the next
# top-level `## ` heading. Emitted to a file so every predicate reads the same
# bytes and a mutated copy can be sectioned identically.
quick_start_section() {
  # quick_start_section <readme-path> <out-path>
  awk '/^## Quick Start[[:space:]]*$/ {f=1; next} f && /^## / {exit} f' "$1" > "$2"
  [ -s "$2" ]
}

QS="$TMP/quickstart.md"
if ! quick_start_section "$README" "$QS"; then
  echo "  [FAIL] fixture — could not extract a non-empty '## Quick Start' section from README.md"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

# --- Predicates -----------------------------------------------------------
# Each returns 0 when the README is HEALTHY. Each takes the README path and
# sections it itself, so a mutated copy goes through the identical code path.

# The three literal signatures of a hand-maintained kickoff copy.
STALE_SIG_1='Read the following files in order'
STALE_SIG_2='.claude/phase-state.json (current phase)'
STALE_SIG_3='You are the AI execution layer'

p1_names_generator() {
  local qs="$TMP/.p1.md"
  quick_start_section "$1" "$qs" || return 1
  grep -Fq 'bash scripts/resume.sh' "$qs"
}

p2_no_stale_copy() {
  local f="$1"
  grep -Fq "$STALE_SIG_1" "$f" && return 1
  grep -Fq "$STALE_SIG_2" "$f" && return 1
  grep -Fq "$STALE_SIG_3" "$f" && return 1
  return 0
}

# Every fence OPENER in § Quick Start must name a language. A bare ``` opener
# there is the shape a prose paste block takes.
#
# Openers only, deliberately: a CLOSING fence is bare by definition, so the
# obvious one-line `grep -Eq '^```$'` reports every well-formed ```bash block
# in the section as a violation. It did exactly that on the first run of this
# suite. Fence state has to be tracked.
p2b_no_bare_fence_in_quickstart() {
  local qs="$TMP/.p2b.md"
  quick_start_section "$1" "$qs" || return 1
  awk '
    /^[[:space:]]*```/ {
      if (open) { open = 0; next }
      open = 1
      info = $0
      sub(/^[[:space:]]*```[[:space:]]*/, "", info)
      if (info == "") bare = 1
      next
    }
    END { exit (bare ? 1 : 0) }
  ' "$qs"
}

p3_states_generator_is_downstream_only() {
  local qs="$TMP/.p3.md"
  quick_start_section "$1" "$qs" || return 1
  grep -Fq 'does not exist in this framework repo' "$qs"
}

# The BL-199 activation, spelled without naming the initialization script, so
# this suite stays a unit-lane citizen (the lint's exemption predicate greps
# executed lines for that filename — see CLAUDE.md HOUSE RULES DIGEST).
p4_documents_bare_name_activation() {
  local qs="$TMP/.p4.md"
  quick_start_section "$1" "$qs" || return 1
  grep -Fq -- '--project-dir my-project' "$qs"
}

p5_blank_screen_reassurance() {
  local qs="$TMP/.p5.md"
  quick_start_section "$1" "$qs" || return 1
  grep -Fq 'ready and waiting, not stuck' "$qs"
}

# --- T-cases: the real README ---------------------------------------------
t1_names_generator() {
  if p1_names_generator "$README"; then
    pass "T1: README § Quick Start points at the single generator (bash scripts/resume.sh)"
  else
    fail_ "T1" "§ Quick Start does not name 'bash scripts/resume.sh' — the post-init step must point at the generator, not carry its own prompt"
  fi
}

t2_no_stale_copy() {
  if p2_no_stale_copy "$README"; then
    pass "T2: no hand-maintained kickoff paste block anywhere in README.md (three literal signatures absent)"
  else
    fail_ "T2" "README.md carries a hand-maintained kickoff copy. Forbidden signatures: '$STALE_SIG_1' / '$STALE_SIG_2' / '$STALE_SIG_3'. Point at bash scripts/resume.sh instead — BL-202 consolidated on one generator precisely so a second copy cannot drift"
  fi
}

t2b_no_bare_fence() {
  if p2b_no_bare_fence_in_quickstart "$README"; then
    pass "T2b: every fenced block in § Quick Start carries an info string (no prose paste block)"
  else
    fail_ "T2b" "§ Quick Start contains a BARE \`\`\` fence. That is the shape a hand-written agent paste block takes, and BL-202 removed the last one. If this fence is genuinely showing command OUTPUT and not a prompt, give it a language tag (\`\`\`text) and say why in the commit message"
  fi
}

t3_honesty() {
  if p3_states_generator_is_downstream_only "$README"; then
    pass "T3: § Quick Start states the generator is downstream-only ('does not exist in this framework repo')"
  else
    fail_ "T3" "§ Quick Start points at scripts/resume.sh without telling a pre-init reader it only exists inside a GENERATED project. Sending someone to run a script they do not have yet is a new defect, not a consolidation"
  fi
}

t4_bl199_activation_still_documented() {
  if p4_documents_bare_name_activation "$README"; then
    pass "T4: § Quick Start still documents the BL-199 activation with a BARE project name (--project-dir my-project)"
  else
    fail_ "T4" "§ Quick Start no longer documents a bare-name --project-dir activation. tests/test-bl199-quickstart-from-clone.sh T1 executes that exact shape and calls it 'what README § Quick Start now documents' — but it never opens README.md, so only this assertion notices when the two part company"
  fi
}

t5_blank_screen() {
  if p5_blank_screen_reassurance "$README"; then
    pass "T5: § Quick Start carries the blank-screen reassurance ('ready and waiting, not stuck')"
  else
    fail_ "T5" "§ Quick Start dropped the blank-screen reassurance. The dead-air BL-202 exists for is a user staring at an empty prompt; resume.sh prints this line on both first-message branches and the README must not be quieter than the script"
  fi
}

# --- Mutation harness -----------------------------------------------------
# Mutations are applied to a COPY under $TMP. The repo's README is read-only
# throughout.
mutant_path() { echo "$TMP/README.$1.md"; }

# The historical block, reproduced here as the mutation payload. This is the
# ONLY place it survives in the tree, and it is data for a proof — not
# documentation anyone is asked to follow.
write_historical_block() {
  cat <<'HISTORICAL'
4. Start Claude Code **from inside your generated project directory** and give
   it the full project context (the paths below exist in your generated
   project — not in this framework repo):
   ```
   Read the following files in order, then confirm what you understand about
   this project before taking any action:
   1. CLAUDE.md (your instructions and constraints)
   2. PROJECT_INTAKE.md (the product definition)
   3. docs/reference/builders-guide.md (the phase-gate methodology)
   4. docs/platform-modules/<your-platform>.md (platform-specific guidance)
   5. .claude/phase-state.json (current phase)
   After reading, summarize: the project goal, your constraints, the current
   phase, and what tools/MCP servers are available to you. Then begin Phase 0.
   Ask me only for clarifying questions.
   ```
HISTORICAL
}

# A REWORDED paste block: same job, zero literals in common with the three
# forbidden signatures. This is what a future well-meaning edit looks like.
write_reworded_block() {
  cat <<'REWORDED'
4. Give the agent its bearings with this opening message:
   ```
   Before doing anything, open the project instructions, the product
   definition, the methodology reference and the recorded phase, then tell me
   what you found and start the first phase.
   ```
REWORDED
}

# Insert a payload just before the § Quick Start section's closing `---`
# separator so it lands INSIDE the section for the section-scoped predicates.
insert_into_quickstart() {
  # insert_into_quickstart <src> <dst> <payload-writer>
  local src="$1" dst="$2" writer="$3"
  "$writer" > "$TMP/.payload"
  awk -v payload="$TMP/.payload" '
    /^## Quick Start[[:space:]]*$/ { inqs = 1 }
    inqs && /^## / && !/^## Quick Start[[:space:]]*$/ {
      while ((getline line < payload) > 0) print line
      close(payload)
      inqs = 0
    }
    { print }
  ' "$src" > "$dst"
  [ -s "$dst" ]
}

m1_strip_generator_pointer() {
  local m; m="$(mutant_path m1)"
  grep -Fv 'bash scripts/resume.sh' "$README" > "$m"
  if cmp -s "$README" "$m"; then
    fail_ "M1" "mutation matched nothing — 'bash scripts/resume.sh' is not in README.md at all, so T1 cannot be load-bearing"
    return
  fi
  if p1_names_generator "$m"; then
    fail_ "M1" "mutant survived: T1 still passes with every 'bash scripts/resume.sh' line removed"
    return
  fi
  if ! p1_names_generator "$README"; then
    fail_ "M1" "GREEN direction failed: the unmutated README does not satisfy T1"
    return
  fi
  echo "    [mutation] M1 RED confirmed: with the generator pointer stripped, T1 fails; unmutated README passes"
  pass "M1: the generator pointer is load-bearing for T1 (mutant RED, source GREEN)"
}

m2_reinsert_historical_block() {
  local m; m="$(mutant_path m2)"
  if ! insert_into_quickstart "$README" "$m" write_historical_block; then
    fail_ "M2" "could not build the mutant — payload insertion produced nothing"
    return
  fi
  if p2_no_stale_copy "$m"; then
    fail_ "M2" "mutant survived: T2 still passes with the historical kickoff block re-inserted"
    return
  fi
  if p2b_no_bare_fence_in_quickstart "$m"; then
    fail_ "M2" "mutant survived the structural net: T2b still passes with a bare-fenced paste block inside § Quick Start"
    return
  fi
  if ! p2_no_stale_copy "$README" || ! p2b_no_bare_fence_in_quickstart "$README"; then
    fail_ "M2" "GREEN direction failed: the unmutated README does not satisfy T2 and T2b"
    return
  fi
  echo "    [mutation] M2 RED confirmed: re-inserting the historical block fails BOTH T2 (literals) and T2b (bare fence); unmutated README passes both"
  pass "M2: T2 and T2b both catch a verbatim re-introduction (mutant RED, source GREEN)"
}

m3_strip_honesty_sentence() {
  local m; m="$(mutant_path m3)"
  grep -Fv 'does not exist in this framework repo' "$README" > "$m"
  if cmp -s "$README" "$m"; then
    fail_ "M3" "mutation matched nothing — the honesty sentence is not in README.md, so T3 cannot be load-bearing"
    return
  fi
  if p3_states_generator_is_downstream_only "$m"; then
    fail_ "M3" "mutant survived: T3 still passes with the downstream-only statement removed"
    return
  fi
  if ! p3_states_generator_is_downstream_only "$README"; then
    fail_ "M3" "GREEN direction failed: the unmutated README does not satisfy T3"
    return
  fi
  echo "    [mutation] M3 RED confirmed: without the downstream-only sentence T3 fails; unmutated README passes"
  pass "M3: the downstream-only honesty sentence is load-bearing for T3 (mutant RED, source GREEN)"
}

m4_drop_bare_name_activation() {
  local m; m="$(mutant_path m4)"
  sed 's|--project-dir my-project|--project-dir|g' "$README" > "$m"
  if cmp -s "$README" "$m"; then
    fail_ "M4" "mutation matched nothing — '--project-dir my-project' is not in README.md, so T4 cannot be load-bearing"
    return
  fi
  if p4_documents_bare_name_activation "$m"; then
    fail_ "M4" "mutant survived: T4 still passes with the bare project name removed from the activation"
    return
  fi
  if ! p4_documents_bare_name_activation "$README"; then
    fail_ "M4" "GREEN direction failed: the unmutated README does not satisfy T4"
    return
  fi
  echo "    [mutation] M4 RED confirmed: dropping the bare project name fails T4; unmutated README passes"
  pass "M4: the bare-name activation is load-bearing for T4 (mutant RED, source GREEN)"
}

m5_reworded_paste_block() {
  local m; m="$(mutant_path m5)"
  if ! insert_into_quickstart "$README" "$m" write_reworded_block; then
    fail_ "M5" "could not build the mutant — payload insertion produced nothing"
    return
  fi
  # STATED, NOT PAPERED OVER: the literal net is BLIND here, by construction.
  # If it ever stops being blind the payload has accidentally picked up a
  # forbidden signature and M5 is no longer proving what it claims.
  if ! p2_no_stale_copy "$m"; then
    fail_ "M5" "the reworded payload tripped a literal signature — the mutant is not the reword it claims to be, so it proves nothing about T2b"
    return
  fi
  if p2b_no_bare_fence_in_quickstart "$m"; then
    fail_ "M5" "mutant survived: a reworded bare-fenced paste block passed T2b, so the structural net is doing no work the literals do not already do"
    return
  fi
  if ! p2b_no_bare_fence_in_quickstart "$README"; then
    fail_ "M5" "GREEN direction failed: the unmutated README does not satisfy T2b"
    return
  fi
  echo "    [mutation] M5 RED confirmed: a reworded paste block slips past T2's literals (as designed) and is caught by T2b alone; unmutated README passes"
  pass "M5: T2b catches a REWORDED re-introduction that no literal can (mutant RED, source GREEN)"
}

t1_names_generator
t2_no_stale_copy
t2b_no_bare_fence
t3_honesty
t4_bl199_activation_still_documented
t5_blank_screen
m1_strip_generator_pointer
m2_reinsert_historical_block
m3_strip_honesty_sentence
m4_drop_bare_name_activation
m5_reworded_paste_block

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
