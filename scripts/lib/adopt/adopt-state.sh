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
_adopt_state_order() {
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
    [ -f "$src" ] || continue
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
  adopt_stub_framework_script_collisions "$n_collided" "$ADOPT_COLLISION_LIST"
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

adopt_write_phase_state() {
  local root="$1"
  jq -n --arg p "$ADOPT_PROJECT_NAME" --arg d "$ADOPT_DEPLOYMENT" --arg m "$ADOPT_POC_MODE" \
        --argjson phase "$ADOPT_LANDED_PHASE" \
    '{project: $p, framework_version: "1.0", current_phase: $phase, track: "full",
      deployment: $d, poc_mode: $m, compliance_ready: false, review_gate_enforced: true,
      gates: {phase_0_to_1: null, phase_1_to_2: null, phase_2_to_3: null, phase_3_to_4: null}}' \
    | adopt_write_file "$root" ".claude/phase-state.json"
}

# ── Stage 2 — intake ────────────────────────────────────────────────────────
adopt_write_intake() {
  local root="$1" report="$2"
  adopt_render_intake_doc "$root" "$ADOPT_SCENARIO" "$ADOPT_LANDED_PHASE" || return 1
  adopt_render_intake_progress "$root" "$ADOPT_SCENARIO" || return 1
  adopt_persist_phase1_artifacts "$root" || return 1
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
  # stamp will. `soif_adoption_stamp` takes `scanner_sha="${8:-}"` and writes
  # whatever it is given, so an empty string would land in the durable record
  # as a hash that ties the adoption decision to nothing — the same
  # silent-empty shape as adopt_sha256's old unreachable fallback, one layer
  # further out. There is no scenario in which "we could not hash the evidence"
  # should still produce a record claiming to have hashed it.
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
  # Certification is EMPTY and that is honest, not an oversight: the
  # certification pass is WP5 and has not run. adopt_stub_certification says so
  # out loud rather than letting an empty array read as "measured, nothing
  # found".
  ( cd "$root" && soif_adoption_stamp ".claude/manifest.json" "$ADOPT_SCENARIO" "$ADOPT_LANDED_PHASE" \
      '[]' '[]' '[]' '[]' "$sha" ) || { adopt_refuse "the adoption stamp was refused"; return 1; }   # BF-ADOPT-STAMP-CALL
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

  report="$(adopt_obtain_report "$root" "$given_report")" || return 1

  adopt_present_evidence "$root" "$report"
  adopt_ask_scenario || return 1
  adopt_decide_placement "$report" || return 1
  adopt_ask_audience || return 1
  adopt_run_reverse_intake "$report" "$ADOPT_SCENARIO" || return 1

  adopt_stub_secrets_disposition "$report"
  adopt_stub_certification "$ADOPT_SCENARIO" "$ADOPT_LANDED_PHASE"

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

  adopt_stub_adoption_record "$ADOPT_SCENARIO" "$ADOPT_LANDED_PHASE"
  adopt_stage_and_commit "$root" || return 1

  # AFTER the commit, and that ordering is the point — see adopt_install_hooks.
  adopt_install_hooks "$root" || return 1

  adopt_head "Adopted"
  adopt_note "Scenario: $ADOPT_SCENARIO. Landed at phase $ADOPT_LANDED_PHASE."
  # Say exactly WHICH gates, and no more. "The gates are live" would be a claim
  # the run has not earned: the message-scoped ones are on from the next commit,
  # and adopt_stub_hooks has just listed the ones that are not.
  adopt_note "From your next commit onward the framework's two message gates are live in"
  adopt_note "this project: test-before-code ordering, and the Build-Loop commit check."
  return $rc
}
