#!/usr/bin/env bash
# scripts/lib/adopt/adopt-state.sh — the framework install, the FAIL-SAFE
# state-creation order (§8.4), the adoption stamp's ONE call site (§8.5),
# explicit staging, and the run itself.
#
# SPEC: docs/designs/2026-08-02-brownfield-adoption-v1.md §8.4, §8.5, §5.5,
# §8.1, §4.3/§4.4.
#
# ─────────────────────────────────────────────────────────────────────────────
# §8.4 — WHY phase-state FIRST, AND WHY THE ORDER IS DATA
#
# The two failure directions are not symmetric, and that asymmetry is the whole
# reason there is an order at all. Verified by execution, per surface:
#
#   phase-state present, manifest absent
#     check-phase-gate.sh runs and exits 1; read_enforcement_level returns
#     `strict` (missing file => strict). Gates live at the strictest tier —
#     BLOCKED, which is the SAFE direction.
#
#   manifest present, phase-state absent
#     check-phase-gate.sh prints "No .claude/phase-state.json found — skipping
#     phase gate check." and exits 0. An adopted-LOOKING project with NO gate
#     enforcement at all. That row must never be reachable.
#
# Writing phase-state FIRST means every interruption lands in the top row. §5.5
# names the state this protects: "adoption does not complete" is a real state
# and it must be a SAFE one — an operator who abandons an adoption mid-way ends
# up with a blocked repository, not a silently degraded one.
#
# The honest qualification (§8.4's C4 correction, not restated as a flat
# claim): "missing manifest fails strict" is true of scripts/lib/enforcement-level.sh
# and FALSE inside check-phase-gate.sh, where the missing-manifest arm of the
# Phase 1->2 protection backstop is a `[WARN]` with NO `issues` increment. The
# ordering decision is unaffected — the tier ladder governs the commit-time
# gates and it fails closed — but the flat claim would be wrong.
#
# init.sh's create_project() uses the OPPOSITE order (manifest, intake,
# phase-state). That is not a counter-example: creation is one uninterrupted
# run ending in a commit, so no partial state is ever left behind. Adoption can
# legitimately halt at a blocker.

# _adopt_state_order — §8.4's order, spelled ONCE, as data, so that reversing
# it is a ONE-LINE edit and a mutation proof has a single site to hit.
# A4 PUTS `approval_log` FIRST, AND THE ORDER IS A SAFETY PROPERTY, NOT A
# PREFERENCE. Written LAST, every mid-step-7 death leaves the tree
# phase-state-present/log-absent — the gate's hard refusal, the one state an
# interrupted adoption must not rest in. Written FIRST, an interrupted run
# leaves at worst a log with no phase-state, which is INERT: with no
# phase-state the gate exits 0 and skips. Of the two orders only one has a safe
# failure mode.
_adopt_state_order() {
  printf '%s\n' approval_log   # BL-242-APPROVAL-LOG-FIRST
  printf '%s\n' phase_state intake manifest   # BF-ADOPT-STATE-ORDER
}

# ─────────────────────────────────────────────────────────────────────────────
# THE HALT HOOK IS A FAULT INJECTOR AND IT IS DELIBERATE.
#
# SOIF_ADOPT_HALT_AFTER=<stage> stops the run immediately after the named
# stage. It exists so the §8.4 table can be asserted at every interruption
# point by EXECUTION rather than by reasoning about one — the same kind of
# affordance as the bare `:` above the prefill read: not dead code, but the
# thing that makes the proof possible.
#
# It cannot weaken enforcement. Every value it accepts makes the run stop
# EARLIER, and stopping earlier is by construction the safe direction (§5.5) —
# there is no ordering of the stages under which halting produces the unsafe
# row unless the ORDER ITSELF is wrong, which is exactly what it is here to
# detect.
_adopt_halt_requested() {
  [ "${SOIF_ADOPT_HALT_AFTER:-}" = "$1" ]
}

# ── The framework install ───────────────────────────────────────────────────
# adopt_install_framework ROOT — put the framework's own scripts into the
# adoptee.
#
# The set is DERIVED from init.sh's `cp` lines through the shared parser
# (soif_parse_shipped_scripts), never duplicated here: a hand-kept second copy
# of that list is precisely the drift BL-088's source-closure check exists to
# catch, and a duplicate would drift the moment either list changed. It is also
# how scripts/lib/adoption-stamp.sh reaches the adoptee — WP3's own header
# warns that without it every enabling arm silently no-ops on exactly the
# projects they were built for.
#
# NON-DESTRUCTIVE, ALWAYS. An existing file at a framework path is a COLLISION
# and collisions belong to §7/WP6; this driver records them and refuses to
# overwrite. §1.2's measured problem with init.sh is unguarded overwrites, and
# a driver that reproduced them would have earned nothing by being separate.
#
# The collision LIST is kept in memory and PRINTED by the stub, not staged into
# the run's temp directory. An earlier cut wrote it to a file under $ADOPT_WORK,
# which the EXIT trap deletes — so the list evaporated unread and only the count
# was ever used (R-WP4-4). A seam that disappears before anything can consume it
# is not a seam; WP6 owns the durable archive and its MANIFEST, and until then
# the operator gets the paths on screen.
ADOPT_COLLISION_LIST=""
adopt_install_framework() {
  local root="$1"
  local rel src dst n_copied=0 n_collided=0
  ADOPT_COLLISION_LIST=""
  adopt_head "Installing the framework's own scripts"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    src="$ADOPT_FRAMEWORK_ROOT/$rel"
    dst="$root/$rel"
    # SYNC SIBLING — `_adopt_preflight_managed` must count THIS set, filtered
    # THIS way, or the two disagree about "is the framework here" and a design
    # sentence gets written on the strength of the wrong one (§0.3). BOTH
    # halves are needed for `n_copied -eq 0` to imply the preflight's
    # `n_present == n_total`; a draft called this one "the load-bearing half",
    # which understates the other. **`P6i`/`P6i2` in
    # `tests/test-brownfield-wp9b-preflight-approval.sh` pin THIS line** — an
    # incomplete root must still adopt a fresh project and must never emit
    # `could not install`; `P6h` pins the sibling.
    [ -f "$src" ] || continue   # BL-242-INSTALL-SET-KEY
    if [ -e "$dst" ]; then
      ADOPT_COLLISION_LIST="$ADOPT_COLLISION_LIST$rel
"
      n_collided=$((n_collided + 1))
      continue
    fi
    adopt_touched_disk   # BL-225-TOUCHED-DISK
    mkdir -p "$(dirname "$dst")" 2>/dev/null || { adopt_refuse "could not create $(dirname "$rel")"; return 1; }
    # `cp -p`, and NOT `cp` followed by `chmod +x`. The framework's own modes
    # are already right — entry scripts are 0755 and libs are 0644 — and a
    # blanket +x would land every sourced lib in the adoptee at 0755, a
    # difference from a scaffolded project that nothing downstream would ever
    # explain. Preserving the source mode keeps the two births identical.
    adopt_touched_disk   # BL-225-TOUCHED-DISK
    cp -p "$src" "$dst" 2>/dev/null || { adopt_refuse "could not install $rel"; return 1; }
    adopt_record_write "$rel"
    n_copied=$((n_copied + 1))
  done <<INSTALL_SET
$(soif_parse_shipped_scripts "$ADOPT_FRAMEWORK_ROOT/init.sh" "$ADOPT_FRAMEWORK_ROOT/scripts")
INSTALL_SET
  adopt_note "Installed $n_copied framework script(s); left $n_collided of your own file(s) untouched."
  if [ "$n_copied" -eq 0 ]; then
    # TWO CAUSES, AND THEY NEED DIFFERENT SENTENCES (R-WP4-2). The first cut
    # blamed the clone for both, which is a misdiagnosis in the commonest case:
    # a run that halted at the commit stage leaves every framework file already
    # present, so the operator's obvious next move — fix the problem, re-run —
    # met "is this a complete clone?" about the one thing that was fine. Name
    # the real state, and say plainly that resuming is not built yet rather
    # than implying a retry will work.
    if [ "$n_collided" -gt 0 ]; then
      adopt_refuse "every framework script is already present, so nothing was installed."
      {
        echo "          This project looks partly or fully adopted already — most likely an earlier"
        echo "          adoption ran and stopped before it finished."
        echo "          RESUMING AN INTERRUPTED ADOPTION IS NOT BUILT YET: collisions belong to WP6"
        echo "          and the adoption record to WP7, so re-running cannot pick up where it left"
        echo "          off, and the stamp refuses to be written twice by design."
        echo "          Meanwhile the project is in the SAFE state: the gates are live at the"
        echo "          strictest tier, so nothing slips through while this is unresolved."
      } >&2
      return 1
    fi
    adopt_refuse "no framework scripts could be installed and none were already there — is this a complete clone?"
    return 1
  fi
  adopt_write_orchestrator_source "$root" || return 1   # BL-242-ORCH-SOURCE
  adopt_stub_framework_script_collisions "$n_collided" "$ADOPT_COLLISION_LIST"
  return 0
}

# adopt_write_orchestrator_source ROOT — `.claude/orchestrator-source.json`,
# `{source_dir}`, the framework clone this install came from. `init.sh` writes
# it (one site, beside its own copy loop) and adoption never did.
#
# WHY THIS ONE INIT-PARITY ROW IS CLOSED HERE AND THE OTHER TWELVE ARE NOT.
# It is not the cheapest and it is not the biggest; it is the one **A7's own
# safety argument depends on**. A7 defers the data classification to Act 4, and
# the thing that makes that acceptable is that the operator still meets the
# question. The Phase 1->2 ZDR block names its escape hatch in its own FAIL
# text — `reconfigure-project.sh` — and on an adopted project that hatch DIED
# on a missing file:
#
#     [FAIL] Cannot find Solo Orchestrator source directory.
#     [INFO] Expected path in .claude/orchestrator-source.json
#
# Three shipped scripts an adoptee RECEIVES read it — `reconfigure-project.sh`,
# `verify-install.sh` and `check-versions.sh` — so the miss degraded three
# tools, not one. Closing a block while leaving the escape hatch it advertises
# unreachable is the pattern this repository has paid for before; the rest of
# §8.7a's unowned set has no such dependency and stays recorded rather than
# quietly absorbed here.
#
# It is written AFTER the install and BEFORE any state stage, because it is a
# fact about the install rather than about the project's phase.
#
# YES, IT RECORDS AN ABSOLUTE HOST PATH, AND YES, IT IS COMMITTED — and both are
# PARITY, not a new exposure this introduces. `init.sh` writes the same key from
# `$SCRIPT_DIR` and sweeps it in with `git add -A`, and the generated
# `.gitignore` excludes four `.claude/` paths (`cache/`, `last-checked-commit`
# `.txt`, `last-gate-pass.txt`, `tool-usage.json`) of which this is NOT one. So
# a scaffolded project already carries its author's clone path in history, and
# an adopted one now carries it identically. Diverging here — writing it
# unstaged, or ignoring it — would give the two birth paths different shapes for
# the three readers that consume it, which is the drift `# BL-221-ADOPT-TIER-`
# `KEYS` was filed about on a different key. If the exposure is ever judged
# unacceptable it is `init.sh`'s to change first, and both paths follow.
# NO `command -v jq || return 0` GUARD, and its absence is deliberate. The
# first draft carried one, copied from writers whose no-op-on-missing-jq is
# correct. It is UNREACHABLE — `adopt_main` refuses at "jq is required" (rc 2)
# before any writer runs — and if it ever became reachable it would skip the
# escape-hatch file and return SUCCESS, which is the silent-success shape this
# function exists to remove. Its sibling writers in this file carry no such
# guard either.
adopt_write_orchestrator_source() {
  local root="$1"
  jq -n --arg s "$ADOPT_FRAMEWORK_ROOT" '{source_dir: $s}' \
    | adopt_write_file "$root" ".claude/orchestrator-source.json" || return 1
  return 0
}

# ── §8.2 STEP 0 — THE RE-ADOPTION PREFLIGHT (A1) ────────────────────────────
#
# WHY IT IS BEFORE EVERY QUESTION AND EVERY WRITE. The obvious alternative —
# "let the second-stamp refusal handle it" — refuses at the MANIFEST stage,
# which is after `adopt_write_file` has `cat >`-overwritten `phase-state.json`
# and the intake. Under D10 the clobbered `current_phase` is GATE-EARNED: the
# operator crossed those boundaries with evidence, and no part of adoption can
# give them back. Refusing after the damage is not refusing.
#
# THE ARMS ARE THREE SEPARATE FUNCTIONS ON THREE MARKED CALL LINES, so each has
# exactly one thing a mutation proof can remove, and so that removing one
# leaves the other two spelled exactly as they ship.
adopt_preflight() {
  local root="$1"
  _adopt_preflight_adopted "$root" || return 1        # BL-242-PREFLIGHT-ARM1
  _adopt_preflight_prior_archive "$root" || return 1  # BL-242-PREFLIGHT-ARM2
  _adopt_preflight_managed "$root" || return 1        # BL-242-PREFLIGHT-ARM3
  _adopt_preflight_templates || return 1              # BL-242-PREFLIGHT-TEMPLATES
  _adopt_preflight_project_name "$root" || return 1   # BL-242-PREFLIGHT-NAME
  return 0
}

# ── THE PROJECT NAME IS UNTRUSTED INPUT AND REACHES A GOVERNANCE DOCUMENT ──
# `ADOPT_PROJECT_NAME` is `${root##*/}` — a directory basename — and A4 renders
# it into `APPROVAL_LOG.md`, which `check-phase-gate.sh` PARSES for approval
# evidence. A name containing a newline therefore injects arbitrary LINES into
# that document, and `_cpg_gate_has_evidence` looks for exactly one shape: a
# `## ` section header followed by a `| Date | YYYY-MM-DD |` row. A directory
# named so as to carry those two lines makes the gate find approval evidence
# nobody recorded — and `_cpg_record_gate_date` then SYNTHESISES that date into
# `phase-state.json`, against its own header's rule that "a project with no
# dated approval entry must NEVER get a date synthesized into phase-state.json".
# The approval trail forging itself out of a folder name.
#
# A COMMENT IN THIS FILE ALREADY CLAIMED THIS REFUSED ("an embedded newline
# still refuses loudly, which is correct"). IT DID NOT. What actually happened
# on such a tree was an unrelated death further in, reporting `the scan report
# classifies '' as ''` — a misleading message from a different mechanism, which
# is how an unverified claim survived being written down as measured.
#
# Refused at step 0, before anything is asked or written, because a name of
# this shape cannot be made safe by escaping at the render site alone: it also
# flows into the intake, the manifest and the commit subject.
_adopt_preflight_project_name() {
  local root="$1" n stripped bad=""
  n="${root##*/}"
  # NOT a `case` pattern with `$(printf '\n')` in it — bash 3.2 mis-parses that
  # construct and the resulting syntax error surfaces HUNDREDS OF LINES LATER,
  # naming an innocent function. Strip the characters and compare instead:
  # `tr -d` removes every newline and carriage return, so any name containing
  # one differs from its stripped form.
  stripped="$(printf '%s' "$n" | tr -d '\n\r')"
  if [ -z "$n" ]; then
    bad="it is empty"
  elif [ "$stripped" != "$n" ]; then
    bad="it contains a line break or carriage return"
  fi
  [ -n "$bad" ] || return 0
  adopt_refuse "this project's directory name cannot be used: $bad"
  adopt_note "Adoption writes the project's name into APPROVAL_LOG.md, PROJECT_INTAKE.md and"
  adopt_note "the adoption commit. APPROVAL_LOG.md is the file the phase gate reads to decide"
  adopt_note "whether a boundary was approved, so a name carrying line breaks could put rows"
  adopt_note "into it that nobody approved."
  adopt_blank
  adopt_note "Rename the directory and run adoption again. Nothing has been written."
  return 1
}

# NOT AN ARM — a precondition on the FRAMEWORK, not on the adoptee, and it is
# here for the reason stated three functions below: "Refusing after the damage
# is not refusing." Template presence is a static property of
# `$ADOPT_FRAMEWORK_ROOT`, knowable before anything is asked or written. A
# first cut checked it inside the state loop and MEASURED this on a checkout
# without `templates/`: the refusal was honest and loud, and it arrived after
# the archive was created and 74 files were on disk. The path is not
# hypothetical — three of this repo's own test mirrors hit it in one build.
#
# BOTH templates are checked, not the tier-matched one: the tier is answered
# after this point, so checking one would move the failure back into the state
# loop for the other half of the operators.
_adopt_preflight_templates() {
  local t missing=""
  # `-s`, NOT `-f`. A zero-byte template passes an existence check and then
  # dies in the state loop with "the approval log rendered empty" — after the
  # archive and 70 written files, which is precisely the failure this function
  # was added to move earlier. Measured.
  for t in approval-log-org approval-log-personal; do
    [ -s "$ADOPT_FRAMEWORK_ROOT/templates/generated/$t.tmpl" ] && continue
    # NEWLINE-DELIMITED, not space-delimited — see the loop that prints it.
    missing="$missing$ADOPT_FRAMEWORK_ROOT/templates/generated/$t.tmpl
"
  done
  [ -n "$missing" ] || return 0
  adopt_refuse "this framework checkout is missing an approval-log template"
  adopt_note "Adoption writes APPROVAL_LOG.md from a template shipped beside init.sh, and"
  adopt_note "without it the adopted project could not run its own phase gate. Missing:"
  # NOT `for t in $missing` — unquoted word-splitting breaks on the SPACE IN
  # THIS REPOSITORY'S OWN PATH ("Claude Projects"), printing two nonexistent
  # paths instead of one real one. CLAUDE.md's first environment trap, in a
  # diagnostic this package added.
  printf '%s' "$missing" | while IFS= read -r t; do
    [ -n "$t" ] || continue
    adopt_note "  $t"
  done
  adopt_note "Nothing has been written. Check out the framework completely and run again."
  return 1
}

# ARM 1 — already adopted. TWO WITNESSES, and the second is the point.
# `soif_adoption_adopted` reads the WORKING COPY, which a hand edit can blank;
# `_soif_adoption_head_copy_adopted` reads HEAD's copy, which it cannot. An
# operator who deletes the `.adoption` block to "start over" defeats the flag
# AND the restamp refusal together, and lands exactly in the case this arm
# exists for. Either witness refuses.
_adopt_preflight_adopted() {
  local root="$1"
  local witness=""
  ( cd "$root" && soif_adoption_adopted ".claude/manifest.json" ) && witness="the manifest"
  # ONE LINE, and deliberately not wrapped: a mutation proof replaces this
  # whole line with `:`, and a continuation would leave the mutant unparseable
  # and the proof reporting a setup failure instead of a result.
  if [ -z "$witness" ]; then
    ( cd "$root" && _soif_adoption_head_copy_adopted ".claude/manifest.json" ) && witness="the committed copy of the manifest (the working copy no longer says so)"   # BL-242-PREFLIGHT-WITNESS2
  fi
  [ -n "$witness" ] || return 0

  adopt_refuse "this project has already been adopted — $witness records it"
  adopt_note "Adoption is a one-time act. It archives your files, installs the framework and"
  adopt_note "lands the project at phase 0; running it again would overwrite state you have"
  adopt_note "since earned through the gates."
  adopt_blank
  adopt_note "What you probably want instead:"
  adopt_note "  bash scripts/resume.sh        — continue where this project actually is"
  adopt_note "  --re-add <path>               — put one archived file back"
  return 1
}

# ARM 2 — an unstamped tree carrying a PRIOR archive: a first run that died
# before the state stage. NAME THE DIRECTORY, because that archive's own
# MANIFEST carries the restore line for every file it holds, and a refusal
# that does not say where it is sends the operator hunting for it.
_adopt_preflight_prior_archive() {
  local root="$1" prior=""
  # THE STAMP-ABSENT CONJUNCT, and it is here for the same reason arm 3 carries
  # its own: a COMPLETED adoption necessarily leaves an adoption-archive behind,
  # so an arm 2 without this catches arm 1's whole population — and then
  # dropping arm 1 changes nothing observable and its mutation proof is green
  # forever. §8.2 spells this arm "stamp absent but a prior archive present";
  # the first cut of this function dropped the first half and the suite's PM1
  # caught it. An adopted tree is ARM 1's, and it says something different.
  ( cd "$root" && soif_adoption_adopted ".claude/manifest.json" ) && return 0
  ( cd "$root" && _soif_adoption_head_copy_adopted ".claude/manifest.json" ) && return 0
  [ -d "$root/.claude/adoption-archive" ] || return 0
  prior="$(cd "$root" && ls -d .claude/adoption-archive/*/ 2>/dev/null | head -1)"
  prior="${prior%/}"
  [ -n "$prior" ] || return 0

  adopt_refuse "this project already carries an adoption archive: $prior"
  adopt_note "That directory is what an earlier adoption wrote before it stopped. Adopting"
  adopt_note "again would archive the same files a second time, and the copies already there"
  adopt_note "are the ones with your original contents."
  adopt_blank
  adopt_note "Read what it holds, and restore anything you want back, from:"
  adopt_note "  $prior/MANIFEST.md"
  adopt_blank
  # ── WHAT TO SAY NEXT DEPENDS ON HOW FAR THE FIRST RUN GOT ────────────────
  # A first cut ended "Then move or delete $prior and run this again." — true
  # for a run that died between the archive and the install, and FALSE for the
  # larger population that died anywhere after it. Measured: move the archive
  # aside on a tree whose framework install completed and the re-run hits
  # `every framework script is already present ... RESUMING AN INTERRUPTED
  # ADOPTION IS NOT BUILT YET`. The operator followed the instruction exactly
  # and is stuck. Before A1 the tripwire answered first and told them that.
  # Derive which population this is instead of asserting one.
  # `scripts/check-phase-gate.sh`, AND THE PATH IS THE WHOLE POINT — a draft
  # tested `scripts/lib/adopt/`, which `adopt_install_framework` NEVER creates:
  # its set is `soif_parse_shipped_scripts`'s 68 entries and **zero** of them
  # live under `scripts/lib/adopt/` (derived, not assumed). So the predicate
  # was false for 100% of the population and only the wrong branch could ever
  # print — the exact failure it was written to fix, now wearing a derivation
  # that cannot fire. Worse, the fixture that "verified both ways" created
  # `scripts/lib/adopt/` BY HAND, so it measured the fixture and not the
  # install. Test a path the install actually writes, and let the suite drive
  # a REAL adoption rather than a hand-built shape.
  if [ -f "$root/scripts/check-phase-gate.sh" ]; then
    adopt_note "The framework's own scripts are ALREADY INSTALLED here, so the earlier run got"
    adopt_note "past the install. Re-running will not resume it — resuming an interrupted"
    adopt_note "adoption is not built yet — and moving $prior aside will not change that."
    adopt_note "Restore what you need from the MANIFEST above and carry on with:"
    adopt_note "  bash scripts/resume.sh"
  else
    adopt_note "The framework is not installed yet, so the earlier run stopped early. Move or"
    adopt_note "delete $prior and run this again."
  fi
  return 1
}

# ARM 3 — ALREADY FRAMEWORK-MANAGED BUT NOT ADOPTED, and it was missed in
# A1's first draft. On a SCAFFOLDED GREENFIELD project arms 1 and 2 are both
# silent: there is no `.adoption` to read, and the archive this run is about to
# create is not a PRIOR one. So adoption archives the scaffold's own framework
# files AS THE OPERATOR'S, overwrites gate-earned state, stamps it (no
# `.adoption` ⇒ no restamp refusal) and commits, at EXIT 0. Shipped v1 refused
# that tree through `adopt_install_framework`'s `n_copied -eq 0` tripwire,
# which D1's framework-wins install unreaches. Silent-success corruption, and
# worse in kind than the noisy case A1 was written for.
#
# THE `not adopted` CONJUNCT IS LOAD-BEARING AND IS NOT DEFENSIVE CODING. A
# stamped tree necessarily has a `phase-state.json`, so an arm 3 without it
# would catch arm 1's population too — and then dropping arm 1 would change
# nothing observable and arm 1's mutation proof would be green forever. The
# suite's PM1 is what pins it: strip this conjunct and PM1 goes red while PM1b
# stays green. (A draft credited PM1b, which drops arm 3 to prove arm 1 stands
# ALONE — a different property, and the mis-citation this file's own rule about
# citing by marker exists to prevent.)
_adopt_preflight_managed() {
  local root="$1" found=""
  ( cd "$root" && soif_adoption_adopted ".claude/manifest.json" ) && return 0
  ( cd "$root" && _soif_adoption_head_copy_adopted ".claude/manifest.json" ) && return 0

  if [ -f "$root/.claude/phase-state.json" ]; then
    # DECISIVE. `init.sh` and this driver are its only writers, so its presence
    # on an unadopted tree means the project was scaffolded.
    found=".claude/phase-state.json is present"
  elif [ -f "$root/.claude/manifest.json" ]; then
    # STRONG EVIDENCE, NOT PROOF — so the message says what was found and names
    # both explanations rather than asserting one.
    found=".claude/manifest.json is present"
  else
    # ── THE THIRD SIGNAL, AND IT IS A MAJORITY, NOT A SINGLE FILE ──────────
    # §8.3a-A1 specifies this arm on the two `.claude/` files. An adoption
    # interrupted after the framework install on a COLLISION-FREE adoptee has
    # neither — no manifest, no phase-state, and no archive either, because the
    # archive directory only materialises when something collides. All three
    # arms were silent there and the operator was re-asked the tier question
    # and every confirmation before the `n_copied -eq 0` tripwire refused,
    # which is this function's own "neither re-interrogate nor destroy" promise
    # going unmet.
    #
    # A FIRST CUT KEYED ON ONE FILE (`scripts/check-phase-gate.sh`) AND THAT
    # WAS A FALSE-REFUSAL BUG. An adoptee that legitimately vendors a script of
    # its own at that path adopted cleanly before this package
    # (`Installed 67 framework script(s); left 1 of your own file(s)
    # untouched.`) and was refused after — with a message naming two causes,
    # BOTH false for them. It was asymmetric too: vendoring `scripts/resume.sh`
    # instead, equally one of the shipped set, still adopted.
    #
    # AT LEAST HALF of the shipped set cannot be a coincidence and a handful can.
    # (`n_present * 2 -ge n_total` — at exactly half it REFUSES, so "majority" is
    # the wrong word for it and the suite pins both sides of that boundary.)
    # ── COUNT THE SAME SET THE INSTALLER WOULD, OR THE TWO DISAGREE ────────
    # `adopt_install_framework` skips any entry whose SOURCE is absent
    # (`# BL-242-INSTALL-SET-KEY`, pinned by `P6i`/`P6i2`) and tests the
    # destination with `-e`. `P6j` pins the PREFLIGHT's copy of that test, the
    # one below — NOT the installer's own `[ -e "$dst" ]`, which nothing pins
    # (measured: flipping it to `-f` leaves all eleven adoption suites green).
    # A draft attached `P6j` to both clauses, which is the mis-citation this
    # file's own rule exists to prevent, for the third time here. THE TWO
    # ARE SYNC SIBLINGS AND NOTHING IN THE LANGUAGE BINDS THEM — a first cut of
    # this comment claimed they "cannot drift", which was false: they are two
    # copies of one predicate in two functions, and review reverted this half
    # with every suite staying green. The markers are the binding, and
    # **`P6h` in `tests/test-brownfield-wp9b-preflight-approval.sh`** is the
    # fixture that makes a drift red — an incomplete framework root whose
    # adoptee holds every installable entry. *(A draft of this line cited `I2`,
    # which is a different fixture in a different section and stays GREEN under
    # both drift mutants. Mis-citing the proof is the failure this file's own
    # rule about citing by marker or function name exists to prevent, and it is
    # the second time in this file.)* A first
    # cut of this loop counted EVERY parsed line and tested `-f`, and the
    # mismatch was not academic: against an INCOMPLETE framework root — the
    # shape §0.3 warns about in as many words — the adoptee carried 24 of the
    # 24 files that root could install, while this counted 24 against a
    # denominator of 65, stayed silent, and let the run reach the `n_copied
    # -eq 0` tripwire. Two predicates about "is the framework here" that
    # disagree are worse than one, and a design sentence asserting the tripwire
    # unreachable was written on the strength of the wrong one.
    local n_present=0 n_total=0 _rel
    while IFS= read -r _rel; do
      [ -n "$_rel" ] || continue
      [ -f "$ADOPT_FRAMEWORK_ROOT/$_rel" ] || continue   # BL-242-INSTALL-SET-KEY-SIBLING
      n_total=$((n_total + 1))
      [ -e "$root/$_rel" ] && n_present=$((n_present + 1))
    done <<PREFLIGHT_SET
$(soif_parse_shipped_scripts "$ADOPT_FRAMEWORK_ROOT/init.sh" "$ADOPT_FRAMEWORK_ROOT/scripts")
PREFLIGHT_SET
    if [ "$n_total" -gt 0 ] && [ $((n_present * 2)) -ge "$n_total" ]; then
      found="$n_present of the framework's own $n_total scripts are already here"   # BL-242-PREFLIGHT-ARM3-INSTALLED
    fi
  fi
  [ -n "$found" ] || return 0

  adopt_refuse "this project already looks framework-managed: $found"
  adopt_note "Adoption is for a project that has never been under this framework. What is"
  adopt_note "here is one of these, and this script cannot tell them apart:"
  adopt_note "  • a project scaffolded by init.sh — in which case it is already set up,"
  adopt_note "    and adopting it would overwrite the phase it has earned;"
  adopt_note "  • an earlier adoption that stopped part-way, leaving its state behind;"
  adopt_note "  • files of your own that happen to sit where the framework's would."
  adopt_blank
  adopt_note "Check which by looking at what is here, then either run scripts/resume.sh to"
  adopt_note "carry on, or move it aside if you are certain this project was never"
  adopt_note "scaffolded and these files are not yours."
  return 1
}

# ── Stage 0 — APPROVAL_LOG.md (A4) ──────────────────────────────────────────
# adopt_write_approval_log ROOT — the tier-matched init.sh template, rendered.
#
# WHY IT EXISTS AT ALL. `check-phase-gate.sh` refuses on a
# phase-state-present/log-absent tree and `exit 1`s SIX LINES BEFORE
# `current_phase` is parsed. Without this file the resting state adoption
# leaves behind cannot run its own phase gate — the project is adopted and its
# gates are unusable.
#
# WHY NOT A FOURTH SPELLING. `init.sh` renders two tier-differentiated
# templates and `verify-install.sh` carries a third writer (`fix_approval_log`)
# whose shape must agree with them. An "empty, headed" fourth would drift from
# both, so this renders THE SAME template `init.sh` does, with the same two
# substitutions.
#
# WHY IT STILL BLOCKS THE GATE, WHICH IS CORRECT. The template's pre-condition
# rows carry `__TODAY__` in a `| # | Pre-Condition | Status | Date | Notes |`
# table — column-shaped cells, not the `| Date | … |` ROW that
# `_cpg_gate_has_evidence` greps for (`# BL-115-DATE-CELL`). So a freshly
# rendered log records no approval, and the gate says the gate date is not
# recorded. Adoption approves nothing; it only makes the question answerable.
# _adopt_approval_template — the tier-matched template path. Spelled once so
# the preflight's existence check and the writer cannot disagree about which
# file they mean.
_adopt_approval_template() {
  case "$ADOPT_DEPLOYMENT" in
    organizational) printf '%s\n' "$ADOPT_FRAMEWORK_ROOT/templates/generated/approval-log-org.tmpl" ;;
    *)              printf '%s\n' "$ADOPT_FRAMEWORK_ROOT/templates/generated/approval-log-personal.tmpl" ;;
  esac
}

adopt_write_approval_log() {
  local root="$1" tmpl today rendered
  tmpl="$(_adopt_approval_template)"
  if [ ! -f "$tmpl" ]; then
    # Reachable only if the checkout changed under a running adoption — the
    # preflight checks both templates at step 0 (# BL-242-PREFLIGHT-TEMPLATES).
    adopt_refuse "the approval-log template is missing: $tmpl"
    adopt_note "Without it the adopted project cannot run its own phase gate, so this"
    adopt_note "adoption stops rather than landing a project whose gates refuse."
    return 1
  fi
  today="$(date +%Y-%m-%d)"

  # ── NOT `sed`, AND THE REASON IS THE INPUT, NOT A PREFERENCE ─────────────
  # `ADOPT_PROJECT_NAME` is `${root##*/}` — a DIRECTORY BASENAME the operator
  # chose — and it lands in a substitution's REPLACEMENT half, the one place
  # in this driver where an operator string does (everything else uses
  # `jq --arg` or `git commit -m`). A first cut used `sed -e "s,__X__,$name,g"`
  # and justified the `,` delimiter against this repo's `|`-vs-`||` trap. That
  # rationale was refuted by the very input it named. Measured, all three at
  # the tip:
  #
  #   amp&co      rc 0  — `&` is THE WHOLE MATCH (CLAUDE.md names this trap),
  #                       rendering `amp__PROJECT_NAME__co`: two unrendered
  #                       placeholders, SILENTLY, in a committed document
  #   comma,inc   rc 1  — the delimiter itself; `sed` dies with `bad flag in
  #                       substitute command`, `cat` still succeeds on empty
  #                       input, so a ZERO-BYTE APPROVAL_LOG.md is written and
  #                       `adopt_refuse` is NEVER CALLED — 68 scripts on disk
  #                       and no honest refusal, against BL-225's contract
  #   back\slash  rc 0  — the backslash silently eaten
  #
  # ── THIS TOOK THREE ATTEMPTS AND EACH ONE CARRIED THE DEFECT ACROSS ──────
  # Attempt 1, `sed -e "s,__X__,$name,g"`: `amp&co` rendered
  # `amp__PROJECT_NAME__co` at rc 0 — `&` is THE WHOLE MATCH, the trap
  # CLAUDE.md names — and `comma,inc` collided with the delimiter, leaving a
  # ZERO-BYTE log at rc 1 with `adopt_refuse` never called.
  #
  # Attempt 2, `awk -v` + `gsub`: POSIX awk gives `&` in a `gsub` REPLACEMENT
  # the same whole-match meaning, so `amp&co` failed identically — the tool
  # changed and the defect did not.
  #
  # Attempt 3, `awk -v` + this `index`/`substr` loop: the loop is innocent and
  # the value never reaches it intact. **`-v` PERFORMS ESCAPE-SEQUENCE
  # PROCESSING ON THE VALUE** (gawk manual, *Other Command-Line Arguments*:
  # "Variable values provided on the command line are processed for escape
  # sequences"), so `back\slash` arrived as `backslash` and was committed that
  # way in the YAML frontmatter and the title. A comment here asserted the
  # opposite — "`-v` protects the value on the way IN" — which is backwards,
  # and the assertion is why two rounds of review were needed to catch it.
  #
  # `ENVIRON` is NOT escape-processed, and combined with `index`/`substr`
  # (which has no replacement-string semantics at all — no `&`, no escape, no
  # delimiter) the operator's string is copied verbatim on both legs. Measured
  # verbatim on this host for: `back\slash`, `amp&co`, `comma,inc`, `tab\there`,
  # `pct%d`, `dq"uote`, `dollar$var`, `-leading-dash`, UTF-8. An embedded
  # newline still refuses loudly, which is correct.
  #
  # `init.sh`'s `generate_approval_log` shares attempt 1's `&` exposure and not
  # its `,` one; it is the sibling shape and is left to its own change rather
  # than edited from here.
  rendered="$(SOIF_ADOPT_LOG_NAME="$ADOPT_PROJECT_NAME" SOIF_ADOPT_LOG_TODAY="$today" awk '
    BEGIN { n = ENVIRON["SOIF_ADOPT_LOG_NAME"]; t = ENVIRON["SOIF_ADOPT_LOG_TODAY"] }
    function repl(line, tok, val,   out, i) {
      out = ""
      while ((i = index(line, tok)) > 0) {
        out = out substr(line, 1, i - 1) val
        line = substr(line, i + length(tok))
      }
      return out line
    }
    # ORDER IS LOAD-BEARING AND IT IS THE OPPOSITE OF THE OBVIOUS ONE.
    # These are NESTED: the outer pass scans the INNER pass output, including
    # whatever it just inserted. With the name substituted first, a directory
    # called pre__TODAY__post had the date written INTO its own name --
    # pre2026-09-01post -- in both the frontmatter and the title, at rc 0,
    # while the same run commit subject carried the real name. Two artifacts
    # of one adoption disagreeing about the project.
    # The date goes FIRST because it is framework-controlled (date +%F) and
    # cannot contain either placeholder; the operator string goes LAST, so
    # nothing rescans it.
    # NO APOSTROPHES ABOVE, DELIBERATELY: this comment is inside a
    # SINGLE-QUOTED shell string, so one apostrophe ends the awk program and
    # the syntax error surfaces hundreds of lines away naming another function.
    { print repl(repl($0, "__TODAY__", t), "__PROJECT_NAME__", n) }
  ' "$tmpl")" || {   # BL-242-APPROVAL-LOG-RENDER
    adopt_refuse "could not render the approval log from $tmpl"
    return 1
  }
  # AND THE OUTPUT IS CHECKED, because "the renderer exited 0" and "the
  # renderer produced a document" are different facts — the empty-output case
  # above is exactly how a zero-byte log reached disk while the run said
  # nothing.
  case "$rendered" in
    '') adopt_refuse "the approval log rendered empty from $tmpl"; return 1 ;;   # BL-242-APPROVAL-LOG-NONEMPTY
  esac
  # ── WRITE IT, THEN LET THE STAGING GUARD DECIDE WHETHER IT IS COMMITTED ──
  # `adopt_write_file` records every path it writes for staging, and
  # `adopt_stage_and_commit` stages the recorded set in ONE `git add` — so a
  # recorded path git refuses aborts the whole adoption. MEASURED as a
  # REGRESSION: an adoptee whose `.gitignore` contains `APPROVAL_LOG.md`
  # adopted cleanly at rc 0 on `main` and, with A4 as first written, got
  # `[BLOCKED] git will not stage every file this adoption must commit` and NO
  # adoption commit — while the same run's archive half correctly printed
  # `your .gitignore covers: APPROVAL_LOG.md`. Two halves of one run, opposite
  # rules, and `docs/adoption.md` ships the archive's half as a guarantee.
  #
  # `_adopt_record_if_stageable` is that guarantee's existing implementation
  # (`# BL-225-ORACLE-SYNC`): it writes nothing, records only what `git add
  # --dry-run` accepts, and DISCLOSES the withholding by name. Routing through
  # it makes the log land on disk, be usable by the gate, and stay out of the
  # commit when the operator's own rule says so — instead of making a
  # previously-adoptable project unadoptable.
  #
  # The gate reads the WORKING TREE, so a withheld log still does its job; what
  # is lost is only its presence in history, which is what the operator asked
  # for.
  printf '%s\n' "$rendered" > "$root/APPROVAL_LOG.md" || {
    adopt_refuse "could not write APPROVAL_LOG.md"
    return 1
  }
  adopt_touched_disk   # BL-225-TOUCHED-DISK
  _adopt_record_if_stageable "$root" "APPROVAL_LOG.md"   # BL-242-APPROVAL-LOG-STAGEABLE
  return 0
}

# ── Stage 1 — phase-state ───────────────────────────────────────────────────
# adopt_write_phase_state ROOT — the FIRST write of the run, on purpose.
#
# `deployment` and `poc_mode` are the tier key (# BL-084-TIER-KEY names the
# sibling predicates that must agree). They are ASKED, never defaulted: an
# empty `deployment` makes the commit-time gate BYPASSABLE by the mothership
# safety rule, so silently omitting them would ship the adoptee a weaker gate
# than the operator chose — the exact direction §8.4 exists to prevent.
ADOPT_DEPLOYMENT=""
ADOPT_POC_MODE="production"
ADOPT_PROJECT_NAME=""

ADOPT_AUDIENCE_Q="Who is this project for?"
ADOPT_AUDIENCE_PERSONAL="Just me, or me and a few people I know"
ADOPT_AUDIENCE_ORG="A company, a client, or people who are paying for it"

adopt_ask_audience() {
  adopt_ask_choice "who the project is for" "$ADOPT_AUDIENCE_Q" \
    "$ADOPT_AUDIENCE_PERSONAL" "$ADOPT_AUDIENCE_ORG" || return 1
  case "$ADOPT_ANSWER" in
    "$ADOPT_AUDIENCE_ORG") ADOPT_DEPLOYMENT="organizational" ;;
    *)                     ADOPT_DEPLOYMENT="personal" ;;
  esac
  return 0
}

# THE LANDING IS A CONSTANT, AND IT IS SPELLED AS ONE (D10). Every adopted
# project lands at phase 0 and stays there until the ordinary gates move it:
# no scenario, no scanned rung, no floor, no arithmetic anywhere in any act.
# Spelled as a named local on its own marked line so that a mutation proof has
# exactly one thing to move and phase-state is the witness that it moved.
adopt_write_phase_state() {
  local root="$1"
  local adopt_landing=0   # BL-242-PHASE0-LANDING
  jq -n --arg p "$ADOPT_PROJECT_NAME" --arg d "$ADOPT_DEPLOYMENT" --arg m "$ADOPT_POC_MODE" \
        --argjson phase "$adopt_landing" \
    '{project: $p, framework_version: "1.0", current_phase: $phase, track: "full",
      deployment: $d, poc_mode: $m, compliance_ready: false, review_gate_enforced: true,
      gates: {phase_0_to_1: null, phase_1_to_2: null, phase_2_to_3: null, phase_3_to_4: null}}' \
    | adopt_write_file "$root" ".claude/phase-state.json"
}

# ── Stage 2 — intake ────────────────────────────────────────────────────────
adopt_write_intake() {
  local root="$1" report="$2"
  adopt_render_intake_doc "$root" || return 1
  adopt_render_intake_progress "$root" || return 1
  # A7: the FILE, not the phase-1 merge. `init.sh` guarantees every scaffolded
  # project a process-state and an adoptee must have one too; the
  # classification that used to ride in with it is Act 4's now (§8.7a row 5).
  adopt_write_process_state "$root" || return 1
  # The survey that justified every scanned answer travels with the project;
  # the stamp's scannerReportSha256 is the hash of exactly this file, so the
  # record and its evidence cannot drift apart.
  cat "$report" | adopt_write_file "$root" ".claude/adoption/scout-report.json" || return 1
  adopt_stub_provenance_headers
  return 0
}

# ── Stage 3 — manifest, and THE STAMP ───────────────────────────────────────
# §8.5: the stamp's home is `.claude/manifest.json`'s top-level `adoption`
# block, and this is its ONE product call site. `soif_currency_stamp` has
# exactly one too, and the operating-model design's F1 correction records why:
# a birth stamp that acquires a second caller has become a backfill. WP3 made
# that structural — a second stamp is REFUSED — but the budget here is one call
# either way.
# The `cmd … | awk … || fallback` spelling does NOT work here and is worth
# naming: the `||` binds to the whole PIPELINE, whose status is awk's, and awk
# succeeds happily on empty input — so a host without `shasum` would silently
# record an empty hash instead of trying `sha256sum`. Probe for the tool.
adopt_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
  else
    printf ''
  fi
}

adopt_write_manifest() {
  local root="$1" report="$2"
  local host mode sha
  host="$(adopt_report_read "$report" '.stack.ciHost // ""')"
  case "$host" in ''|null) host="other" ;; esac
  mode="$ADOPT_DEPLOYMENT"

  # BL-221-ADOPT-TIER-KEYS: write the tier keys an init.sh-scaffolded manifest
  # carries. This function wrote only `.host` and `.mode`, so an ADOPTED
  # manifest had no `deployment`, `poc_mode` or `enforcement_level` at all —
  # and `assert_choosable` read an absent `deployment` as the CHOOSABLE tier.
  # The predicate is now fail-closed too (# BL-221-TIER-FAIL-CLOSED); this half
  # removes the SOURCE of the divergence rather than defending against it, so
  # the two birth paths produce the same shape.
  #
  # Values match what the driver already writes to phase-state.json in
  # adopt_write_phase_state — same two variables, so the manifest and the
  # phase record cannot disagree about the tier. `enforcement_level` seeds to
  # `strict`, which is init.sh's default and the direction this framework
  # fails in.
  local poc="$ADOPT_POC_MODE"
  if [ -f "$root/.claude/manifest.json" ]; then
    adopt_jq_edit "$root" ".claude/manifest.json" \
      '.host = $h | .mode = $m | .deployment = $d | .poc_mode = $p | .enforcement_level = (.enforcement_level // "strict")' \
      --arg h "$host" --arg m "$mode" --arg d "$mode" --arg p "$poc" || return 1
  else
    jq -n --arg h "$host" --arg m "$mode" --arg p "$poc" \
      '{host: $h, mode: $m, remote_url: "", deployment: $m, poc_mode: $p, enforcement_level: "strict"}' \
      | adopt_write_file "$root" ".claude/manifest.json" || return 1
  fi

  sha="$(adopt_sha256 "$root/.claude/adoption/scout-report.json")"
  # REFUSE ON AN EMPTY HASH (R-WP4-3), and refuse HERE rather than hoping the
  # stamp will. WP9 gave `soif_adoption_stamp` its own
  # `# BL-242-STAMP-SHA-REQUIRED` guard on the same fact, and TWO guards on one
  # fact is deliberate rather than redundant: this one refuses LOUDLY, with an
  # operator-facing sentence naming the missing tool, while the writer's keeps
  # the property true for callers that do not exist yet. There is no case in
  # which "we could not hash the evidence" should still produce a record
  # claiming to have hashed it.
  if [ -z "$sha" ]; then                                                       # BF-ADOPT-SHA-REQUIRED
    adopt_refuse "cannot hash the kept scan report — neither shasum nor sha256sum is available, and the adoption record must not claim an evidence hash it does not have"
    return 1
  fi

  # THE ONE CALL SITE. adoptedAtCommit is not passed — the stamp takes it from
  # `git rev-parse HEAD` at stamp time, i.e. the PRE-ADOPTION TIP, the parent
  # the adoption commit is about to land on. That anchor is what bounds the TDD
  # exemption, so the stamp must be written BEFORE the adoption commit and the
  # adoption commit must be the very next one. Both hold here: this is the last
  # write of the last stage, and adopt_stage_and_commit follows immediately.
  #
  # THE CERTIFICATION ARRAYS ARE NOT PASSED BECAUSE THERE ARE NONE. v1-WP5's
  # certification pass is RETIRED, not deferred (§5.1): with no claimed rung
  # there is nothing to certify against, and under D10 no landed rung to
  # certify for. Three empty arrays whose owner no longer exists would read as
  # "measured, nothing found" with nobody left to correct the impression, so
  # §8.3 removed them from the record rather than leaving them empty in it.
  ( cd "$root" && soif_adoption_stamp ".claude/manifest.json" "$sha" ) \
    || { adopt_refuse "the adoption stamp was refused"; return 1; }   # BF-ADOPT-STAMP-CALL
  adopt_record_write ".claude/manifest.json"

  # The stamp no-ops silently (rc 0) when jq is missing or the manifest is not
  # there, so rc 0 alone is not proof it landed. Read it back.
  if ! ( cd "$root" && soif_adoption_adopted ".claude/manifest.json" ); then
    adopt_refuse "the adoption stamp did not land in .claude/manifest.json"
    return 1
  fi
  return 0
}

# ── Explicit staging and the commit (§8.5) ──────────────────────────────────
# NEVER `git add -A`. The counter-example is create_project()'s blanket add
# followed by `git commit --no-verify`, which on an adoptee would sweep their
# uncommitted work into a framework commit with verification bypassed. The
# precedent is upgrade-project.sh's `git add "${FILES_TO_STAGE[@]}"`.
#
# The array is built from the ledger every write recorded as it happened, so
# "anything not in it is never staged" is a property of the code. There is also
# no `--no-verify` here: whatever hook the adoptee already had still runs, and
# it is their gate, not ours, to bypass.
adopt_stage_and_commit() {
  local root="$1"
  local FILES_TO_STAGE=() rel n=0
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    [ -e "$root/$rel" ] || continue
    FILES_TO_STAGE[$n]="$rel"
    n=$((n + 1))
  done <<STAGE_SET
$(adopt_written_paths)
STAGE_SET
  if [ "$n" -eq 0 ]; then
    adopt_refuse "there is nothing to commit — no file was recorded as written"
    return 1
  fi
  # BL-225-STAGE-PREFLIGHT: ask BEFORE adding, and stop WHOLE.
  #
  # `git add` on a mixed pathspec STAGES THE CLEAN PATHS AND EXITS 1 — measured,
  # not assumed (T1 of tests/test-bl225-staging-preflight.sh). The old code
  # learned that from `git add`'s exit status, by which point the index was
  # already half-written.
  #
  # THE ORACLE IS `git add --dry-run`, AND THAT CHOICE IS THE FIX. The first
  # version asked `git check-ignore`, which is INDEX-AWARE and reports nothing
  # for a TRACKED path — so a tracked `.claude/manifest.json` under a
  # later-added `.claude/` rule passed the preflight and half-staged exactly as
  # before. Measured against `git add` as ground truth across a directory rule,
  # a file rule and a glob, `--dry-run` is the only oracle that agrees in all
  # three; `check-ignore --no-index` swaps the false-clean for a FALSE REFUSAL
  # on projects that work today. `--dry-run` writes nothing: `.git/` hashes
  # byte-identical before and after, so the promise below holds by construction.
  #
  # The set checked is FILES_TO_STAGE, complete by construction: it is exactly
  # what the `git add` would receive.
  local _dry _ignored _named
  if ! _dry=$( cd "$root" && git add --dry-run -- "${FILES_TO_STAGE[@]}" 2>&1 >/dev/null ); then
    # --dry-run names the PATTERN that matched; the helper names the PATHS.
    # Keep git's own diagnostic as the fallback, so a cause this code did not
    # anticipate (a pathspec-magic fatal, say) is REPORTED rather than
    # misdiagnosed as an ignore rule.
    _named=$(adopt_name_ignored_paths "$root" "${FILES_TO_STAGE[@]}") || _named=""
    _ignored="$_named"
    [ -n "$_ignored" ] || _ignored="$_dry"
    adopt_refuse "git will not stage every file this adoption must commit"
    {
      printf '          NOTHING WAS STAGED — your index is exactly as you left it.\n'
      printf '          git says:\n'
      # BL-225-NO-FORCE-HINT: strip git's `hint:` lines. git suggests `add -f`,
      # and `docs/adoption.md` guarantees adoption NEVER commits a file the
      # operator's .gitignore excludes — so relaying the hint would put two
      # contradictory instructions three lines apart, and would make this
      # message depend on the host's `advice.addIgnoredFile` setting.
      printf '%s\n' "$_ignored" | grep -v '^hint:' | sed 's/^/            /'
      printf '          These are framework files the adoption needs tracked, so they cannot be\n'
      printf '          quietly skipped: an install missing them is broken rather than reduced.\n'
      # The remedy, and ONLY when an ignore rule is the confirmed cause. The
      # first fix deleted this line outright because it is wrong for an
      # unmeasurable cause — which left the common case with no action at all,
      # except git's `-f` hint, which is the wrong one.
      # The remedy fires when an ignore rule is the CONFIRMED cause — from the
      # namer, or from git's own diagnostic. Gating on the namer alone left the
      # tracked-path case (this branch's headline case) with no remedy at all,
      # because `git check-ignore` is index-aware and structurally cannot name a
      # tracked path. It must still NOT fire on an unmeasured cause.
      if [ -n "$_named" ] || printf '%s' "$_dry" | grep -q 'ignored by one of your'; then
        printf '          Un-ignore them in .gitignore and run adoption again.\n'
      fi
    } >&2
    return 1
  fi
  adopt_head "Committing exactly what was written"
  adopt_note "$n file(s), named one by one. Anything else you had in progress stays"
  adopt_note "exactly as you left it — unstaged, uncommitted, untouched."
  ( cd "$root" && git add -- "${FILES_TO_STAGE[@]}" ) || {   # BF-ADOPT-STAGE-EXPLICIT
    adopt_refuse "could not stage the adoption files"
    return 1
  }
  ( cd "$root" && git commit -q -m "chore: adopt ${ADOPT_PROJECT_NAME:-this project} into the Solo Orchestrator framework" ) || {
    adopt_refuse "the adoption commit did not succeed — your own hooks or git identity may have refused it"
    return 1
  }
  ADOPT_COMMITTED=1   # BL-225-REFUSE-HONEST: derived, so a later refusal tells the truth
  return 0
}

# ── The hooks (§4.5: no forward exemption) ──────────────────────────────────
# adopt_install_hooks ROOT — put the framework's git hooks in place.
#
# WHY AFTER THE ADOPTION COMMIT, AND NOT BEFORE. The adoption commit belongs to
# the adoptee's world: whatever hooks THEY already had should judge it, and the
# framework's should not. Everything AFTER it belongs to the framework's world,
# which is exactly §4.5's rule that no arm anywhere exempts a commit written
# after adoption day. Installing here draws that line at the commit itself, and
# it removes any temptation to reach for `--no-verify` to get past a gate the
# driver had just installed on itself.
#
# Nothing here is staged, and nothing needs to be: `.git/hooks/` is not tracked.
#
# ONLY THE COMMIT-MSG HOOK IS INSTALLED, AND THE OMISSION IS MEASURED.
#
# The commit-msg hook carries the two MESSAGE-SCOPED gates — the BL-072
# TDD-ordering gate, whose pre-adoption exemption this WP's stamp bounds, and
# the BL-006 Build-Loop check. It COMPOSES: the shared emitter appends a MARKED
# block, so an adoptee's existing commit-msg hook keeps working and gains the
# framework's gates, and a second run finds the marker and stops.
#
# The FALLBACK PRE-COMMIT HOOK IS NOT INSTALLED, and this is a measurement
# rather than a preference. Installed on an adoptee at this point in the build
# it BRICKS the repository: with it in place a fixture here could not land an
# ordinary `docs:` commit (rc 1) because the hook expects framework artifacts
# — the Adoption Record among them — that WP7 has not landed yet. Shipping a
# gate that refuses every commit is not enforcement, it is a broken project,
# and the operator's only way out would be the `--no-verify` this framework
# forbids. §10 names no owner for that hook on the adoption path, so it is
# recorded as an open decision rather than quietly assumed; adopt_stub_hooks
# says which checks are consequently NOT running.
#
# The shared writer also writes the WHOLE pre-commit file, so an adoptee's own
# pre-commit hook is §7's own archive-and-replace example, belongs to WP6, and
# is left untouched either way.
adopt_install_hooks() {
  local root="$1"
  local hooks="$root/.git/hooks"
  adopt_head "Turning the gates on"
  adopt_touched_disk   # BL-225-TOUCHED-DISK
  mkdir -p "$hooks" 2>/dev/null || { adopt_refuse "could not create $hooks"; return 1; }

  if [ ! -f "$hooks/commit-msg" ]; then
    adopt_touched_disk   # BL-225-TOUCHED-DISK
    printf '%s\n' '#!/usr/bin/env bash' > "$hooks/commit-msg" || { adopt_refuse "could not create the commit-msg hook"; return 1; }
  fi
  if grep -qF "$SOIF_TDD_OPEN" "$hooks/commit-msg" 2>/dev/null; then
    adopt_note "The commit-msg gate was already present — left as it was."
  else
    adopt_touched_disk   # BL-225-TOUCHED-DISK
    soif_emit_tdd_commitmsg_block >> "$hooks/commit-msg" || { adopt_refuse "could not extend the commit-msg hook"; return 1; }
    adopt_note "Commit-msg gate installed (it composes with whatever was already in that hook)."
  fi
  chmod +x "$hooks/commit-msg" 2>/dev/null

  if [ -e "$hooks/pre-commit" ]; then
    # LEFT ALONE, AND ARCHIVED. WP6's archive already took a copy before any of
    # this ran, so the operator has a restorable record of the hook they wrote
    # even though nothing here replaces it. The WP4 stub that used to fire here
    # is gone: it announced the archive as missing, and it is not.
    adopt_note "You already have a pre-commit hook. It has been LEFT ALONE, and a copy is in"
    adopt_note "the archive with a restore line — see ${ADOPT_ARCHIVE_DIR:-the archive}/MANIFEST.md."
  fi
  adopt_stub_hooks
  adopt_stub_project_docs
  return 0
}

# ── The run ─────────────────────────────────────────────────────────────────
ADOPT_WORK=""

adopt_obtain_report() {
  local root="$1" given="$2"
  if [ -n "$given" ]; then
    if [ ! -f "$given" ]; then
      adopt_refuse "the scan report '$given' does not exist"
      return 1
    fi
    printf '%s' "$given"
    return 0
  fi
  local scout="$ADOPT_FRAMEWORK_ROOT/scripts/scout.sh"
  if [ ! -f "$scout" ]; then
    adopt_refuse "no scan report was given and Scout is not beside this driver"
    return 1
  fi
  bash "$scout" --root "$root" --out "$ADOPT_WORK/scan" >/dev/null 2>&1 || {
    adopt_refuse "the scan did not complete"
    return 1
  }
  printf '%s' "$ADOPT_WORK/scan/scout-report.json"
  return 0
}

adopt_main() {
  local root="$1" given_report="$2"
  local report stage rc=0

  if ! command -v jq >/dev/null 2>&1; then
    echo "adopt-project: jq is required." >&2
    return 2
  fi
  if ! ( cd "$root" && git rev-parse --verify --quiet HEAD >/dev/null 2>&1 ); then
    echo "adopt-project: '$root' is not a git repository with at least one commit." >&2
    echo "  Adoption records the commit it landed on, so there has to be one." >&2
    return 2
  fi

  ADOPT_WORK="$(mktemp -d "${TMPDIR:-/tmp}/adopt-work.XXXXXXXX" 2>/dev/null)" || {
    echo "adopt-project: could not create a temporary working directory." >&2
    return 2
  }
  trap 'rm -rf "$ADOPT_WORK"' EXIT INT TERM

  adopt_stdin_init
  adopt_ledger_init "$ADOPT_WORK/written" || return 2
  adopt_answers_init "$ADOPT_WORK/answers" || return 2
  ADOPT_PROJECT_NAME="${root##*/}"

  adopt_head "Adopting $ADOPT_PROJECT_NAME"
  adopt_note "Nothing is written until the questions are answered. If you stop partway,"
  adopt_note "this project ends up more strictly gated than it started, never less."

  # §8.2 STEP 0 — THE RE-ADOPTION PREFLIGHT (A1), BEFORE THE TIER QUESTION AND
  # BEFORE THE REPORT IS EVEN OBTAINED. Its position is the whole decision: a
  # second run must neither re-interrogate the operator nor destroy what the
  # first produced, and both of those start happening below this line.
  adopt_preflight "$root" || return 1   # BL-242-PREFLIGHT-CALL

  report="$(adopt_obtain_report "$root" "$given_report")" || return 1

  # §4.2's evidence, which decides nothing and is printed anyway (A6): it is
  # the only point in Act 2 where the operator sees what the survey found about
  # their own project, and §4.3 keeps it as pre-fill for the Phase 0 intake.
  adopt_present_evidence "$root" "$report"   # BL-242-EVIDENCE-CALL

  # §8.2 STEP 1 — THE TIER QUESTION, AND IT IS THE ONLY QUESTION ADOPTION ASKS
  # THAT IS NOT A CONFIRMATION. D9 keeps it: D4's reasoning is about
  # self-reported PROCESS MATURITY, which an operator using this framework
  # cannot be expected to know, and "is this for a company or for me" is a fact
  # they know for certain and no evidence can determine. It is the sole
  # producer of ADOPT_DEPLOYMENT, which `# BL-221-ADOPT-TIER-KEYS` requires an
  # adopted manifest to carry and which D2's secrets tiering will read.
  #
  # ITS POSITION IS THE CONSTRAINT: before any writer and before anything is
  # installed, so a run abandoned at it has changed neither the repository nor
  # the host.
  adopt_ask_audience || return 1   # BL-242-TIER-QUESTION

  # §8.2 STEP 2 — TOOL RESOLUTION, AND ITS POSITION IS THE CONSTRAINT.
  # BEFORE the secrets check that reads its result (§6.2) and BEFORE any
  # writer, so a run abandoned here has changed the repository not at all and
  # the host only if the operator said yes. AFTER the tier question, because
  # that is step 1 and a run abandoned at the only question adoption asks
  # should not have installed anything first.
  adopt_resolve_tools "$root" "$report" || return 1   # BL-242-RESOLVER-CALL
  # §6.2: if the step re-scanned, every later step reads the REFRESHED report —
  # including the state writer that persists it and the stamp that records its
  # hash, so "the persisted copy reflects what was actually acted on" is true
  # by construction rather than by a second write.
  [ -n "${ADOPT_REPORT_REFRESHED:-}" ] && report="$ADOPT_REPORT_REFRESHED"   # BL-242-RESOLVER-REFRESH

  adopt_run_reverse_intake "$report" || return 1

  adopt_stub_secrets_disposition "$report"

  # WP5b. Was adopt_stub_test_debt_ledger; it is a real measurement now.
  # BEFORE adopt_install_framework, and that ordering is stated rather than
  # inherited: the census reads `git ls-files`, so the ~60 framework scripts
  # the install is about to copy in could not enter the ledger even if this ran
  # after it — they are untracked until adopt_stage_and_commit. Running it here
  # keeps the two facts independent instead of resting the property on the
  # index's timing.
  #
  # A REFUSAL HERE ABORTS THE ADOPTION, and that is the safe direction: this is
  # before any state write, so a run that cannot measure the debt leaves the
  # project exactly as it found it rather than adopting it with no baseline.
  adopt_test_debt_record "$root" || return 1

  # §7 — THE COLLISION ARCHIVE, BEFORE ANY FRAMEWORK WRITER RUNS.
  #
  # It has to precede adopt_install_framework and adopt_install_hooks for one
  # reason: an archive taken AFTER a writer has run is a copy of the
  # framework's file, not of theirs, and the restore line would put the
  # framework's own output back under the operator's name. The commit-msg hook
  # is the live case — adopt_install_hooks appends a marked block to it — so
  # the archived copy is deliberately the PRE-composition one.
  adopt_archive_write "$root" "$ADOPT_WORK" || return 1

  adopt_install_framework "$root" || return 1
  if _adopt_halt_requested install; then
    adopt_refuse "halted after the framework install, before any state was written (SOIF_ADOPT_HALT_AFTER)"
    return 1
  fi

  while IFS= read -r stage; do
    [ -n "$stage" ] || continue
    case "$stage" in
      approval_log) adopt_write_approval_log "$root" || return 1 ;;   # BL-242-APPROVAL-LOG-WRITE
      phase_state) adopt_write_phase_state "$root" || return 1 ;;
      intake)      adopt_write_intake "$root" "$report" || return 1 ;;
      manifest)    adopt_write_manifest "$root" "$report" || return 1 ;;
      *)           adopt_refuse "unknown state stage '$stage'"; return 1 ;;
    esac
    if _adopt_halt_requested "$stage"; then
      adopt_refuse "halted after the '$stage' stage (SOIF_ADOPT_HALT_AFTER)"
      return 1
    fi
  done <<STATE_ORDER
$(_adopt_state_order)
STATE_ORDER

  adopt_stub_adoption_record
  adopt_stage_and_commit "$root" || return 1

  # AFTER the commit, and that ordering is the point — see adopt_install_hooks.
  adopt_install_hooks "$root" || return 1

  # ── THE ACT BOUNDARY (§8.1, §3.5) ─────────────────────────────────────────
  # "Completed" now means ACT 2 completed, and saying so is the whole point:
  # this is a four-act feature whose second act ends in a shell script and
  # whose third begins in a Claude Code session, and an operator who reads
  # "Adopted" as "finished" stops here and never gets the assessment.
  adopt_head "Act 2 complete — the project is adopted and sitting at phase 0"   # BL-242-ACT3-HANDOFF
  adopt_note "Your project is now under the framework and it starts where every project"
  adopt_note "starts: phase 0. Nothing has been marked as already done, and nothing was"
  adopt_note "guessed about how far along you are — you will be asked about that instead."
  adopt_blank
  adopt_note "NEXT: run this, and paste what it prints into Claude Code."
  adopt_note "  bash scripts/resume.sh"
  adopt_blank
  # Say exactly WHICH gates, and no more. "The gates are live" would be a claim
  # the run has not earned: the message-scoped ones are on from the next commit,
  # and adopt_stub_hooks has just listed the ones that are not.
  adopt_note "From your next commit onward the framework's two message gates are live in"
  adopt_note "this project: test-before-code ordering, and the Build-Loop commit check."
  adopt_blank
  adopt_stub_assessment
  return $rc
}
