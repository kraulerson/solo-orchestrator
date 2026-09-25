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
  # `dispositions` — §6.3's two records — AFTER `intake` and BEFORE `manifest`
  # (the marker on the line below): inside the loop so the rehearsal covers them
  # (its audit rows land in the COPY's ledger and are discarded with it), and
  # before the stamp so an acceptance that cannot be recorded blocks the run
  # before the project reads as adopted. On the §8.4 line, not a line of its
  # own, because that line is a single-site mutation anchor.
  printf '%s\n' phase_state intake dispositions manifest   # BL-242-DISPOSITIONS-ORDER # BF-ADOPT-STATE-ORDER
  # AFTER `manifest` AND NOT BEFORE IT. The Adoption Record names the commit
  # this project was adopted at, and it takes that value from the stamp rather
  # than from a second `git rev-parse HEAD` — one fact, one source. The stamp
  # is written by the `manifest` stage, so the record cannot precede it.
  # AFTER `manifest` so the documents are written under a stamped adoption, and
  # BEFORE `adoption_record` so the record is still the last word in the log.
  # Inside the loop, not after it, because this loop is what the pre-write
  # rehearsal replays: a document written outside it would be the one write I20
  # never checked against the archive.
  printf '%s\n' framework_docs   # BL-242-DOCS-STAGE-ORDER
  # The framework's CI, at its own name (§7.4), before the record that names it.
  printf '%s\n' ci   # BL-242-CI-STAGE-ORDER
  # The Claude Code session layer (§10-WP9c): settings, hook roster, skills, MCP.
  printf '%s\n' session_layer   # BL-242-SESSION-STAGE-ORDER
  # The prompt resume.sh prints for the assessment; it needs the stamp's commit.
  printf '%s\n' assessment_prompt   # BL-242-ASSESSMENT-PROMPT-ORDER
  printf '%s\n' adoption_record   # BL-242-RECORD-STAGE
  printf '%s\n' write_set   # BL-242-WRITE-SET — LAST: it records what every stage before it wrote
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
  # NEVER during the pre-write rehearsal. `SOIF_ADOPT_HALT_AFTER` is a test seam
  # for the REAL run — it makes the driver stop after a named stage so a suite
  # can inspect a partial adoption. The rehearsal replays the same write phase,
  # so without this guard the seam fires there first: the rehearsal "fails", the
  # preflight refuses, and the real adoption never runs at all. Measured — that
  # is 12 failures across four adoption suites, including a `rc=127` whose real
  # cause was the adopted project's own gate script never being installed.
  [ "${ADOPT_REHEARSING:-0}" = "1" ] && return 1   # BL-225-REHEARSAL-NO-HALT
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
# _adopt_overwrite_inventory_check ROOT — I20, §9.1.
#
# planned ∩ pre-existing ⊆ inventory. Anything outside that is a path this run
# is about to overwrite with no copy kept and no row in the record — which is
# exactly what `## BL-292:` was, three times over.
#
# FAILS CLOSED. If the planned set is unavailable, or the inventory cannot be
# read, the answer is BLOCK: the check has not been performed, and the next
# statement writes over the operator's files. `## BL-147:` — a check that
# cannot run must not pass.
_adopt_overwrite_inventory_check() {
  local root="$1"
  local inv="" rel="" missing="" n=0

  if [ -z "${ADOPT_PLANNED_WRITES:-}" ]; then
    adopt_block "the pre-write rehearsal produced no list of what it would write"
    adopt_note "  Adoption cannot check that your own files are archived before replacing them,"
    adopt_note "  so it will not replace them. Nothing was written."
    return 1
  fi

  # THE INVENTORY'S OWN DIAGNOSTIC WINS. `2>/dev/null` here discarded it and
  # left I20 blaming the wrong cause: on a tree whose skill directory carries a
  # newline AND which owns `PROJECT_INTAKE.md`, the operator was told to file a
  # bug against adoption about their intake file, when the real cause was the
  # directory name and the fix was to rename it. `# BL-225-REFUSE-HONEST`: a
  # refusal must name what actually happened.
  local _inv_err="" _inv_rc=0
  _inv_err="$ADOPT_WORK/i20-inventory-err"
  inv="$(adopt_archive_inventory "$root" 2>"$_inv_err" | cut -f1)" || _inv_rc=$?
  if [ "$_inv_rc" -ne 0 ]; then
    adopt_block "the archive inventory could not be taken, so no file can be safely replaced"
    [ -s "$_inv_err" ] && while IFS= read -r _l; do
      [ -n "$_l" ] && adopt_note "  $_l"
    done < "$_inv_err"
    adopt_note "  Nothing was written."
    return 1
  fi

  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    # Only paths that EXISTED before this run can be overwritten; a path the
    # run creates has nothing to archive.
    [ -e "$root/$rel" ] || continue
    # THE AUDIT LEDGER IS APPENDED TO, NEVER REPLACED. `bypass_audit_append`
    # refuses anything but a single JSON array and writes `. + [$row]`, so every
    # row the operator already had survives — there is nothing an archive copy
    # would give back. Treating the append as an overwrite blocked EVERY
    # adoption of a project that already carried a ledger, once the `adoption`
    # row made the ledger a planned write on every run (review of WP7's audit
    # rows, measured: `[]` in place, rc 1 "would be replaced with no copy kept").
    case "$rel" in .claude/bypass-audit.json) continue ;; esac   # BL-242-I20-LEDGER-APPEND
    # `--` so a path beginning with a dash is a pattern, not an option: without
    # it grep exits 2 and prints usage to stderr. It fails CLOSED either way
    # (exit 2 reads as no-match, so the run blocks), but noisily and for the
    # wrong stated reason.
    printf '%s\n' "$inv" | grep -qxF -- "$rel" && continue
    missing="$missing$rel
"
    n=$((n + 1))
  done <<PLANNED
$ADOPT_PLANNED_WRITES
PLANNED

  [ "$n" -eq 0 ] && return 0

  adopt_block "$n file(s) of yours would be replaced with no copy kept"
  adopt_note "  Adoption plans to write these paths, they already exist in your project, and the"
  adopt_note "  archive has no record of them:"
  printf '%s' "$missing" | while IFS= read -r rel; do
    [ -n "$rel" ] && adopt_say "     $rel"
  done
  adopt_note "  This is a defect in adoption, not in your project: every path it replaces must be"
  adopt_note "  archived first. Nothing was written."
  return 1
}

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
      # ── D1 FRAMEWORK-WINS: ARCHIVE THEIRS, INSTALL OURS ──────────────────
      # This was `continue` — skip on collision — until WP11. That preserved
      # the operator's bytes, which sounds like the safe direction and is not:
      # a project carrying its own `scripts/validate.sh` received every
      # framework script EXCEPT that one, silently, and the gates that call it
      # then ran THEIR file. Half an installed framework is not a safer state
      # than a replaced file with a copy in the archive; it is an unannounced
      # one.
      #
      # THE RECEIPT CHECK IS WHAT MAKES THAT SAFE, and it is called ONCE per
      # path immediately before the copy rather than once for the set: the
      # question is not "did the archive run" but "is THIS file's copy on
      # disk". `# BL-242-RECEIPT-CHECK` refuses when the answer is no, so the
      # operator's bytes are never replaced on the strength of an archive that
      # did not happen.
      if ! adopt_receipt_check "$root" "$rel"; then   # BL-242-RECEIPT-CHECK
        adopt_block "cannot replace $rel: this project's own copy is not in the archive"
        adopt_note "  The framework's version of that file would overwrite yours, and the archive"
        adopt_note "  has no copy to put back. Nothing more was written."
        return 1
      fi
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
  # NAMED, NOT COUNTED. "left 3 of your own files untouched" tells an operator
  # nothing they can act on, and after framework-wins it would also be false —
  # those files were REPLACED. Every path is printed, which is what makes the
  # standing warning below checkable rather than a promise.
  if [ "$n_collided" -gt 0 ]; then
    adopt_note "Installed $n_copied framework script(s). $n_collided of your own file(s) were"
    adopt_note "replaced by the framework's version; your copy of each is in the archive:"
    printf '%s' "$ADOPT_COLLISION_LIST" | while IFS= read -r _c; do
      [ -n "$_c" ] && adopt_say "     $_c"
    done
    adopt_note "The archive's MANIFEST carries a restore line for every one of them."
  else
    adopt_note "Installed $n_copied framework script(s); none of your own files collided."
  fi
  _adopt_install_semgrep_config "$root" || return 1   # BL-242-SEMGREP-CONFIG

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
# ── WP9d item (2) — THE HOOKS DIRECTORY IS RESOLVED THROUGH GIT, ONCE ───────
#
# `$root/.git/hooks` is a guess. It is wrong for a linked worktree and a
# submodule (`.git` is a FILE), and it is wrong wherever `core.hooksPath` is
# configured — git then runs hooks from THERE and a hook written here is never
# executed. Measured on `579b0b0` (`## BL-290:`): with hooksPath set, adoption
# wrote `.git/hooks/commit-msg`, printed that the message gates are live, and
# `GIT_TRACE=1 git commit` ran no hook at all.
#
# ONE spelling, shared by `adopt_install_hooks` and `adopt_archive_inventory`'s
# `git-hook` class, so the directory the archive copies FROM and the directory
# the installer writes TO can never diverge (invariant I21). Two spellings
# because `--path-format` is git ≥ 2.31; the fallback is physical by `pwd -P`.
# TWO ANSWERS, AND THE DIFFERENCE IS LOAD-BEARING.
#   _adopt_hooks_path  — the path git NAMES, symlink intact. Measured: for a
#                        repository whose `.git/hooks` is a symlink,
#                        `--git-path hooks` reports `.git/hooks` while
#                        `--path-format=absolute --git-path hooks` reports the
#                        link's TARGET. The absolute form therefore cannot see
#                        the link at all, and `[ -L ]` on it is false — so the
#                        shape rule must ask its question of THIS one.
#   _adopt_hooks_dir   — where the write actually lands. Used by the installer
#                        and the archive (I21).
# Step 0 refuses every shape where the two disagree, so after preflight they
# name the same directory; before it, only the first can answer the question.
_adopt_hooks_path() {                                  # BL-242-HOOKS-PATH-RAW
  local root="$1" rel
  rel="$(git -C "$root" rev-parse --git-path hooks 2>/dev/null)" || return 1
  [ -n "$rel" ] || return 1
  case "$rel" in
    /*) printf '%s' "$rel" ;;
    *)  printf '%s' "$root/$rel" ;;
  esac
}

_adopt_hooks_dir() {                                   # BL-242-HOOKS-DIR
  local root="$1" d=""
  d="$(git -C "$root" rev-parse --path-format=absolute --git-path hooks 2>/dev/null)" || d=""
  if [ -z "$d" ]; then
    d="$(_adopt_hooks_path "$root")" || return 1
    # Physical only where it EXISTS; an absent hooks directory is ordinary and
    # `cd` cannot resolve it.
    if [ -d "$d" ]; then
      d="$( cd "$d" 2>/dev/null && pwd -P )" || return 1
    fi
  fi
  [ -n "$d" ] || return 1
  printf '%s' "$d"
}

# _adopt_phys DIR — the physical path of a directory that exists, else empty.
_adopt_phys() { [ -d "$1" ] && ( cd "$1" 2>/dev/null && pwd -P ); }

# ── WP9d item (1) — R1's STEP-0 REFUSALS (Karl, 2026-09-17) ─────────────────
#
# Adoption refuses BEFORE any question and before any write when git will not
# run the hook this driver installs, or when that hook would land somewhere
# this repository does not own. Every arm names what it found and prints the
# remedy in `# BL-209-HOOKSPATH-SAME-DIR`'s shape.
#
# WHY THIS IS A SHAPE RULE AND NOT A STRONGER WRITE TEST. `.git/hooks` as a
# symlink to a writable directory OUTSIDE the repository passes `-L`, `-d` AND
# `-w`; the write succeeds; and `--git-path hooks` reports the LINK's own path,
# so the derived sentence below re-resolves through the link, finds the hook it
# just wrote, and prints TRUTHFULLY about a hook this repository does not own
# (ADOPT-002-ARCH v2.2 §13-V48). No predicate over writability separates that
# from the ordinary case. `scripts/verify-install.sh`'s
# `# BL-145-SYMLINK-GUARD-BEGIN` holds the same policy and its header records
# the trap this arm is written against: a LEAF `-L` test is not sufficient,
# because `ln -s ~/.githooks .git/hooks` makes the DIRECTORY the link.
_adopt_preflight_placement() {
  local root="$1" phys_root phys_top

  phys_root="$(_adopt_phys "$root")"
  phys_top=""
  if phys_top="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)"; then
    phys_top="$(_adopt_phys "$phys_top")"
  fi
  if [ -z "$phys_top" ] || [ "$phys_root" != "$phys_top" ]; then   # BL-242-PLACEMENT-TOPLEVEL
    adopt_refuse "this is not the top level of the repository — adoption writes a project's state at its root, and the hook it installs belongs to the repository, not to a directory inside it"
    adopt_note "  you asked to adopt: ${phys_root:-$root}"
    adopt_note "  the repository's top level is: ${phys_top:-(git cannot report one here)}"
    adopt_note "  Run adoption from the top level, or pass --root there."
    return 1
  fi

  if [ ! -d "$root/.git" ]; then                                   # BL-242-PLACEMENT-GITDIR
    adopt_refuse "this project's .git is a FILE, not a directory — a linked worktree or a submodule, where the hooks live in the repository this one points at"
    adopt_note "  Adopt the repository that owns the history instead."
    return 1
  fi

  # Configured is read off git config's EXIT STATUS, never off the value: a
  # hooksPath set to the empty string runs NO hook, and its value is empty too.
  if git -C "$root" config core.hooksPath >/dev/null 2>&1; then    # BL-242-PLACEMENT-HOOKSPATH
    local hp hp_phys own own_phys
    hp="$(git -C "$root" config core.hooksPath 2>/dev/null)"
    own="$(git -C "$root" rev-parse --git-common-dir 2>/dev/null)/hooks"
    case "$own" in /*) ;; *) own="$root/$own" ;; esac
    hp_phys="$(_adopt_phys "$hp")"
    [ -n "$hp_phys" ] || hp_phys="$(_adopt_phys "$root/$hp")"
    own_phys="$(_adopt_phys "$own")"
    # The SAME-DIRECTORY exception (M1, author-proposed): a hooksPath pointing
    # at the repository's own hooks directory is not a redirection, and the
    # ruling's "configured" is narrowed by exactly that much.
    if [ -z "$hp_phys" ] || [ -z "$own_phys" ] || [ "$hp_phys" != "$own_phys" ]; then
      adopt_refuse "core.hooksPath is configured to '${hp:-(empty)}' — git runs this project's hooks from there, so the gate this adoption installs would never run"
      adopt_note "  This driver will not write into a configured hooksPath: it can be shared across"
      adopt_note "  repositories or tracked in the project."
      adopt_note "  To let the framework manage the commit-time gates: git config --unset core.hooksPath"
      return 1
    fi
  fi

  local hooks raw own_hooks
  raw="$(_adopt_hooks_path "$root")" || raw=""
  hooks="$(_adopt_hooks_dir "$root")" || hooks=""
  if [ -z "$raw" ] || [ -z "$hooks" ]; then
    adopt_refuse "git could not tell this driver where this repository's hooks directory is"
    return 1
  fi
  # TWO PATHS GET THE SHAPE TEST, AND THE SECOND IS NOT REDUNDANT.
  #   $raw       — the path git NAMES for this repository's hooks.
  #   $own_hooks — this repository's OWN hooks directory, whatever hooksPath says.
  # Measured: with `core.hooksPath` pointed at an outside directory AND
  # `.git/hooks` symlinked to that same directory, EACH rule alone stands aside
  # — the same-directory exception above sees the two PHYSICAL paths match
  # (because this repository's own hooks path is the link), and `$raw` is then
  # the hooksPath value, a real directory with no link on it. Adoption exited 0
  # and the gate landed outside the repository. The narrowing cannot be allowed
  # to launder a link out of the repository, so the link is refused wherever it
  # sits on either path.
  own_hooks="$(git -C "$root" rev-parse --git-common-dir 2>/dev/null)/hooks"
  case "$own_hooks" in /*) ;; *) own_hooks="$root/$own_hooks" ;; esac
  # `-L` on the RAW path: the absolute form resolves the link away (see
  # _adopt_hooks_path). Asked of the DIRECTORY, never of a leaf hook file —
  # `# BL-145-SYMLINK-GUARD-BEGIN`'s header records that a leaf test is not
  # sufficient, and a repository whose commit-msg alone is a symlink is ordinary.
  if [ -L "$raw" ] || [ -L "$own_hooks" ]; then                    # BL-242-PLACEMENT-HOOKS-SHAPE
    # INITIALISED, and the empty string is load-bearing. `local tgt` alone
    # leaves it UNSET, and the next line reads it under `set -u` — which is
    # silent on bash 3.2 (this Mac) and `tgt: unbound variable` on bash 5.2
    # (the runner). Measured: every macOS suite passed and the CI lane went
    # red on this one line. CLAUDE.md's version-split class, met again.
    local tgt=""
    [ -L "$raw" ] && tgt="$(readlink "$raw" 2>/dev/null)"
    [ -n "$tgt" ] || tgt="$(readlink "$own_hooks" 2>/dev/null)"
    adopt_refuse "this repository's hooks directory is a SYMLINK -> ${tgt:-(unresolvable)} — the gate would be written THROUGH the link, into a directory this project does not own and may share with others"
    adopt_note "  Nothing was written. Replace the link with a real directory to let the framework"
    adopt_note "  manage this project's commit-time gates, or install the hook by hand."
    return 1
  fi
  # M16 (author-proposed, beside the ruling): a regular file at that path is the
  # one remaining shape that reaches `mkdir` and fails AFTER the adoption commit.
  if { [ -e "$raw" ] && [ ! -d "$raw" ]; } || { [ -e "$own_hooks" ] && [ ! -d "$own_hooks" ]; }; then   # BL-242-PLACEMENT-HOOKS-SHAPE
    adopt_refuse "this repository's hooks path exists and is not a directory: $raw"
    adopt_note "  Nothing was written. Remove or rename it and run adoption again."
    return 1
  fi
  # The write test, LAST, because the shapes above are what it cannot answer.
  # `preflight_target_writable` is the shipped predicate for this question — a
  # deepest-existing-ancestor walk, which is the conditional (the directory when
  # it exists, its parent when it does not) generalised. Its message names
  # init.sh, so only its exit status is used and adoption prints its own.
  # THE DEPENDENCY IS NAMED, NOT ASSUMED. `preflight_target_writable` lives in
  # `scripts/lib/helpers-core.sh`, which `adopt-project.sh` sources as part of
  # M2's declared core set — and `docs/module-contract.md` says in as many words
  # that "the adoption driver may source core freely" (M5's re-implementation
  # rule binds Scout, not this). But an absent function under `set +e` returns
  # 127, and `if ! <missing>` reads as "not writable": a broken checkout would
  # be reported as the operator's permissions problem. Say which it is.
  if ! command -v preflight_target_writable >/dev/null 2>&1; then
    adopt_refuse "this framework checkout is incomplete: scripts/lib/helpers-core.sh did not provide preflight_target_writable"
    return 1
  fi
  if ! preflight_target_writable "$hooks" 2>/dev/null; then        # BL-242-PLACEMENT-HOOKS-WRITABLE
    adopt_refuse "this repository's hooks directory is not writable: $hooks"
    adopt_note "  Nothing was written. The gate is installed after the adoption commit, so this"
    adopt_note "  would otherwise have stopped the run with the commit already landed."
    return 1
  fi
  return 0
}

# ── WP9d item (6) — the identity the adoption commit will need ──────────────
#
# `git commit` resolves an identity or refuses. Today that refusal lands AFTER
# the stamp and leaves the adoption window (`## BL-291:`); the oracle here is
# the one git itself consults, so the run stops before anything is written.
_adopt_preflight_identity() {                          # BL-242-IDENT-PRECHECK
  local root="$1"
  if ! git -C "$root" var GIT_COMMITTER_IDENT >/dev/null 2>&1; then
    adopt_refuse "git cannot resolve an identity for the commit this adoption has to make"
    adopt_note "  Set one and run adoption again — nothing has been written:"
    adopt_note "    git config user.name  \"Your Name\""
    adopt_note "    git config user.email \"you@example.com\""
    return 1
  fi
  return 0
}

adopt_preflight() {
  local root="$1"
  _adopt_preflight_placement "$root" || return 1       # BL-242-PREFLIGHT-PLACEMENT
  _adopt_preflight_identity "$root" || return 1        # BL-242-PREFLIGHT-IDENTITY
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

  # BL-242-PREFLIGHT-WINDOW — the adoption window, before the generic arm. The
  # witnesses disagree: the working copy says adopted and HEAD does not, so the
  # adoption was written and never committed. `resume.sh` is the wrong pointer
  # for that project; `--finish` is the right one.
  if _adopt_in_window "$root"; then
    adopt_block "this project is part-way through an adoption: the state was written and the commit did not land"
    adopt_note "Nothing is lost. The files are on disk and the list of them is in"
    adopt_note "$ADOPT_WRITE_SET_REL. Finish the adoption with:"
    adopt_note "  bash scripts/adopt-project.sh --finish"
    adopt_blank
    adopt_note "If your own pre-commit hook refused the commit, it will refuse again —"
    adopt_note "fix or bypass that hook first, then run --finish."
    return 1
  fi

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
# `## BL-253:` — PRODUCTION IS THE ABSENCE OF A POC MODE, and it is spelled
# that way because every reader spells it that way. init.sh maps "Production"
# to POC_MODE="" (collect_inputs_non_interactive: `production) POC_MODE=""`)
# and writes JSON null into both state files; process-checklist.sh's
# --start-phase4 and check-phase-gate.sh's organizational Pre-Phase-0 guard
# both read a non-null value as THE NAME OF A POC MODE. This constant was
# "production" for the whole of WP9a–WP10a, so every adoptee was refused at
# Phase 4 ("project is in production mode… run --to-production") and every
# organizational adoptee skipped six pre-conditions. Reproduced on main
# c61edb1, both tiers, by the 2026-09-08 review's second pass; pinned by
# tests/test-bl253-adoption-state-parity.sh against init.sh's own emitter.
# Adoption asks no POC question (D9: one question), so this is a constant —
# the sponsored_poc / private_poc rungs are a residual on the entry.
ADOPT_POC_MODE=""   # BL-253-POC-MODE
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
  # NULL, NOT "" — init.sh's own idiom (`poc_json="null"` in create_project).
  # The readers forgive an empty string; the parity oracle in the BL-253 suite
  # does not, because a scaffolded project never carries one.
  local poc_json='null'   # BL-253-POC-NULL
  [ -n "$ADOPT_POC_MODE" ] && poc_json="\"$ADOPT_POC_MODE\""
  jq -n --arg p "$ADOPT_PROJECT_NAME" --arg d "$ADOPT_DEPLOYMENT" --argjson m "$poc_json" \
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
  # BL-268-MODE-VOCABULARY: `mode` and `deployment` are NOT the same field.
  # `deployment` takes personal|organizational; `mode` takes personal|org, and
  # every reader of `mode` feeds it to host_verify_protection, whose org-only
  # rules are gated on the literal string "org". Writing ADOPT_DEPLOYMENT into
  # both made an adopted organizational project read as personal for branch
  # protection. init.sh does this same translation at its own write site
  # (`_RESOLVED_MODE="$DEPLOYMENT"` then `= "organizational" && "org"`); an
  # adopted project must be born with the same shape as a scaffolded one.
  mode="$ADOPT_DEPLOYMENT"
  [ "$mode" = "organizational" ] && mode="org"

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
  # NULL, NOT "" — the same idiom as adopt_write_phase_state, for the same
  # reason: init.sh's prepare_initial_state_for_commit writes `poc_mode:null`.
  local poc_json='null'   # BL-253-POC-NULL-MANIFEST
  [ -n "$ADOPT_POC_MODE" ] && poc_json="\"$ADOPT_POC_MODE\""
  if [ -f "$root/.claude/manifest.json" ]; then
    adopt_jq_edit "$root" ".claude/manifest.json" \
      '.host = $h | .mode = $m | .deployment = $d | .poc_mode = $p | .enforcement_level = (.enforcement_level // "strict")' \
      --arg h "$host" --arg m "$mode" --arg d "$ADOPT_DEPLOYMENT" --argjson p "$poc_json" || return 1
  else
    jq -n --arg h "$host" --arg m "$mode" --arg d "$ADOPT_DEPLOYMENT" --argjson p "$poc_json" \
      '{host: $h, mode: $m, remote_url: "", deployment: $d, poc_mode: $p, enforcement_level: "strict"}' \
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
    adopt_block "git will not stage every file this adoption must commit"
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
# ── _adopt_install_semgrep_config ROOT — the DOM-sink ruleset the hook reads
#
# WITHOUT THIS THE COMMIT-TIME SAST ARM IS INERT ON EVERY ADOPTED PROJECT, and
# it says so itself. The emitted pre-commit hook passes
# `--config=.semgrep/soif-dom-sinks.yml` UNCONDITIONALLY, and `init.sh`'s own
# comment at the line that installs it for scaffolded projects
# (`# BL-131-DOM-SINKS`) states the consequence of its absence: *"a missing file
# makes semgrep exit non-zero and the SAST arm WARNs loudly (never a silent
# clean pass)"*. Measured on a real adoption before this shipped, on EVERY
# commit:
#
#   [WARN] semgrep could not complete (exit 7) — the tool itself failed.
#     SAST NOT ENFORCED for this commit — the scanner did not run.
#     [ERROR] unable to find a config; path `.semgrep/soif-dom-sinks.yml` does not exist
#
# So the honest arm is loud and the project is unprotected — the right
# behaviour for a missing file, and the wrong state for a project the framework
# just adopted.
#
# ONLY WHEN ABSENT, AND THAT IS A DELIBERATE NARROWING. An adoptee that already
# has a file at this path has its OWN semgrep rules there; the hook passes the
# path either way, so theirs satisfies it. Replacing them would be a new
# archive-and-replace class — §7.1's population is the AI-layer surfaces and the
# git hooks, and this is neither — and nobody has ruled on it. Keeping to
# "write only what is not there" also keeps this writer out of I20's overwrite
# inventory by construction rather than by a row somebody has to remember.
_adopt_install_semgrep_config() {                      # BL-242-SEMGREP-CONFIG
  local root="$1" src rel
  rel=".semgrep/soif-dom-sinks.yml"
  src="$ADOPT_FRAMEWORK_ROOT/templates/semgrep/soif-dom-sinks.yml"
  if [ ! -f "$src" ]; then
    adopt_note "The framework's DOM-sink ruleset is missing from this checkout, so the"
    adopt_note "commit-time static-analysis pass will warn on every commit until it is there."
    return 0
  fi
  # `-L` AS WELL AS `-e`: `-e` is FALSE for a dangling symlink, so `cp -p`
  # followed it and CREATED the file at the link's far end — outside the
  # project, during the rehearsal, before a refusal that then said nothing had
  # been written. The same class as `# BL-243-INSTALL-SKIP-LOUD`'s `-e`/`-L`.
  if [ -e "$root/$rel" ] || [ -L "$root/$rel" ]; then
    adopt_note "You already have $rel — left as it is. The commit-time"
    adopt_note "static-analysis pass reads that path, so your rules are what it will use."
    return 0
  fi
  adopt_touched_disk   # BL-225-TOUCHED-DISK
  mkdir -p "$root/.semgrep" 2>/dev/null || { adopt_refuse "could not create .semgrep/"; return 1; }
  adopt_touched_disk   # BL-225-TOUCHED-DISK
  cp -p "$src" "$root/$rel" 2>/dev/null || { adopt_refuse "could not install $rel"; return 1; }
  adopt_record_write "$rel"
  return 0
}

# _adopt_precommit_replace_ok ROOT HOOKSDIR — may the fallback hook overwrite
# what is at HOOKSDIR/pre-commit? Returns 0 if yes; else 1 with ADOPT_PC_WHY set.
#
# The one invariant: NEVER OVERWRITE BYTES THE ARCHIVE CANNOT GIVE BACK. So:
# nothing there → yes; a symlink → no (a write follows it, the archive does not);
# a plain file → yes only if its sha256 equals the MANIFEST row's, i.e. the
# archived copy is a faithful copy of exactly what is about to be replaced.
ADOPT_PC_WHY=""; ADOPT_PC_ARCHIVE=""
_adopt_precommit_replace_ok() {                        # BL-242-PRECOMMIT-GUARD
  local root="$1" h="$2/pre-commit" arc row live arch_rel
  ADOPT_PC_WHY=""; ADOPT_PC_ARCHIVE=""
  if [ -L "$h" ]; then ADOPT_PC_WHY="symlink"; return 1; fi
  [ -e "$h" ] || return 0
  [ -f "$h" ] || { ADOPT_PC_WHY="unarchived"; return 1; }
  # READ-ONLY IS REFUSED HERE, BEFORE THE EMITTER IS CALLED, because checking
  # afterwards is too late. `soif_write_precommit_hook` ends in `chmod +x` and
  # runs it even when its write failed, so on a `chmod 444` hook the content
  # check below it correctly said "not installed" — and the operator's hook,
  # which git had never run, had meanwhile been made EXECUTABLE (measured:
  # `-r--r--r--` became `-r-xr-xr-x`). Not calling the emitter is the only way
  # to leave the file exactly as it was.
  [ -w "$h" ] || { ADOPT_PC_WHY="readonly"; return 1; }
  arc="$(adopt_archive_latest "$root")"
  if [ -z "$arc" ] || [ ! -f "$root/$arc/MANIFEST.json" ]; then
    ADOPT_PC_WHY="unarchived"; return 1
  fi
  row="$(jq -r '[.entries[] | select(.originalPath == ".git/hooks/pre-commit") | .sha256] | first // ""' \
          "$root/$arc/MANIFEST.json" 2>/dev/null)"
  [ -n "$row" ] || { ADOPT_PC_WHY="unarchived"; return 1; }
  # THE ARCHIVED BYTES, NOT ONLY THE ROW THAT DESCRIBES THEM. A row can outlive
  # its file: a copy withheld from the commit for a secret match is plainly
  # disclosed with "Rotate it at the source; deleting the file does not un-leak
  # it", which invites exactly that deletion — and `--finish` then replaced the
  # hook at rc 0 with "Your copy is in the archive", over an empty git-hooks/.
  # Measured by review. What makes a replacement safe is a restorable copy.
  arch_rel="$(jq -r '[.entries[] | select(.originalPath == ".git/hooks/pre-commit") | .archivedPath] | first // ""' \
          "$root/$arc/MANIFEST.json" 2>/dev/null)"
  if [ -z "$arch_rel" ] || [ ! -f "$root/$arc/$arch_rel" ] \
     || [ "$(adopt_sha256 "$root/$arc/$arch_rel")" != "$row" ]; then
    ADOPT_PC_WHY="unarchived"; return 1
  fi
  live="$(adopt_sha256 "$h")"
  [ -n "$live" ] && [ "$live" = "$row" ] || { ADOPT_PC_WHY="changed"; return 1; }
  ADOPT_PC_ARCHIVE="$arc"
  return 0
}

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
# THE FALLBACK PRE-COMMIT HOOK IS INSTALLED NOW, AND THE MEASUREMENT THAT
# DEFERRED IT IS THE ONE THAT UN-DEFERRED IT.
#
# This comment used to say the hook BRICKS an adoptee: "a fixture here could
# not land an ordinary `docs:` commit (rc 1) because the hook expects framework
# artifacts — the Adoption Record among them — that WP7 has not landed yet."
# That was true and it was a measurement, which is why it was worth re-taking
# once WP7/1 landed the Record. Re-measured on a real hermetic adoption at
# `f790e09`, hook installed, gitleaks 8.30.1 and semgrep 1.175.0 present:
#
#   docs: commit, nothing else staged          rc 0   lands
#   a source file whose tests fail (BL-125)    rc 1   [BLOCKED] project tests FAILED
#   a staged RSA private key                   rc 1   [BLOCKED] gitleaks detected secrets
#
# So it admits a compliant commit and blocks a non-compliant one BY EXIT CODE,
# which is §10-WP7's stated proof obligation. Karl's decision was that this
# hook is WP7's, "last, once the artifacts it reads exist". They exist.
#
# THE OPERATOR'S OWN PRE-COMMIT HOOK IS REPLACED, NOT LEFT ALONE, and that is
# §7.1's rule rather than a new one: its archive-and-replace population is the
# AI-layer surfaces and every non-`.sample` file in `.git/hooks/`. WP6 already
# takes the copy — before any writer runs, so the archived bytes are THEIRS and
# not a composition — and the MANIFEST carries a restore line. The arm that
# used to print "It has been LEFT ALONE" is gone, because leaving it alone is
# what left an adopted project with no commit-time scanners at all.
#
# The shared writer writes the WHOLE file, so this cannot compose the way the
# commit-msg gate does. That asymmetry is why one is appended and one replaces.
adopt_install_hooks() {
  local root="$1"
  local hooks
  hooks="$(_adopt_hooks_dir "$root")" || { adopt_block "git could not report this repository's hooks directory"; return 1; }   # BL-242-HOOKS-DIR
  adopt_head "Turning the gates on"
  adopt_touched_disk   # BL-225-TOUCHED-DISK
  mkdir -p "$hooks" 2>/dev/null || { adopt_block "could not create $hooks"; return 1; }

  if [ ! -f "$hooks/commit-msg" ]; then
    adopt_touched_disk   # BL-225-TOUCHED-DISK
    # SOIF_ADOPT_FAIL_HOOK_WRITE — a fault seam, the `SOIF_ADOPT_HALT_AFTER`
    # precedent. Item (3)'s derived sentence is only provable against a run
    # where the hook write fails and everything before it succeeded, and step
    # 0's shape and write rules now refuse every natural way to reach that.
    if [ -n "${SOIF_ADOPT_FAIL_HOOK_WRITE:-}" ]; then               # BL-242-HOOKS-FAULT-SEAM
      adopt_block "could not create the commit-msg hook"
      return 1
    fi
    printf '%s\n' '#!/usr/bin/env bash' > "$hooks/commit-msg" || { adopt_block "could not create the commit-msg hook"; return 1; }
  fi
  if grep -qF "$SOIF_TDD_OPEN" "$hooks/commit-msg" 2>/dev/null; then
    adopt_note "The commit-msg gate was already present — left as it was."
  else
    adopt_touched_disk   # BL-225-TOUCHED-DISK
    soif_emit_tdd_commitmsg_block >> "$hooks/commit-msg" || { adopt_block "could not extend the commit-msg hook"; return 1; }
    adopt_note "Commit-msg gate installed (it composes with whatever was already in that hook)."
  fi
  # NOT SWALLOWED. A commit-msg that is not executable is a hook git will not
  # run; the live derivation below catches it, but a silent chmod failure is
  # the same missing receipt one step earlier, so say it.
  chmod +x "$hooks/commit-msg" 2>/dev/null \
    || adopt_note "could not make the commit-msg hook executable — the gate will not run until it is."

  # ── THE FALLBACK PRE-COMMIT HOOK (§10-WP7) ───────────────────────────────
  # Written through the SHARED emitter, never a heredoc here: `init.sh` and
  # `scripts/upgrade-project.sh --sync-framework` emit the same bytes from
  # `soif_write_precommit_hook`, and a third spelling is how this repo's own
  # hand-installed hook became a silent stale version (`# BL-243-HOOK-TEMPLATE`).
  #
  # GUARDED, BECAUSE THE FIRST CUT DESTROYED AN OPERATOR'S HOOK FOR GOOD.
  # `soif_write_precommit_hook` writes with `printf >`, which FOLLOWS A SYMLINK,
  # and the archive collects plain files only. Measured on a real adoption: a
  # `.git/hooks/pre-commit` linked to a shared hook OUTSIDE the repository —
  # one file serving many repos, an ordinary hand-rolled arrangement — was
  # overwritten at the far end with 1707 lines of framework hook, no archive
  # was taken, and the run printed "Your copy is in the archive". The operator's
  # bytes were gone and the transcript said they were safe.
  #
  # So nothing is written unless the file at that path is EXACTLY the one the
  # archive holds, byte for byte — which also closes the `--finish` case: an
  # operator told to "fix or bypass that hook first, then run --finish" edits
  # it, the edit is newer than the archive, and overwriting it would lose the
  # edit while the restore line put back the version that refused every commit.
  local _pc_had=0 _pc_ref="" _pc_sha=""
  [ -e "$hooks/pre-commit" ] && _pc_had=1
  ADOPT_PC_STATE="absent"
  if ! _adopt_precommit_replace_ok "$root" "$hooks"; then   # BL-242-PRECOMMIT-GUARD
    ADOPT_PC_STATE="refused"
    adopt_say "   NOT INSTALLED — the commit-time scanners (the fallback pre-commit hook)"
    case "$ADOPT_PC_WHY" in
      symlink)
        adopt_note "  $hooks/pre-commit is a SYMLINK. Writing the framework's hook would go THROUGH"
        adopt_note "  it and overwrite whatever it points at — possibly a hook other repositories"
        adopt_note "  share — and the archive cannot hold a copy of a link's target. Left exactly"
        adopt_note "  as it is." ;;
      readonly)
        adopt_note "  $hooks/pre-commit is READ-ONLY, so it was not overwritten and its permissions"
        adopt_note "  were not touched." ;;
      changed)
        adopt_note "  $hooks/pre-commit is not the file the adoption archive holds a copy of — it"
        adopt_note "  was changed after the archive was taken. Overwriting it would lose that change"
        adopt_note "  with nothing to restore it from, so it was left exactly as it is."
        # THE ARCHIVE'S RESTORE LINE NOW POINTS AT THE OLDER VERSION. The
        # MANIFEST was written before the operator's edit and records
        # `replaced`; running its restore line would put back the hook they had
        # to fix, over the fix. Recorded on `## BL-242:` as a residual — the
        # MANIFEST is already committed by the time this is known.
        adopt_note "  Do NOT run the archive's restore line for this hook: it would put back the"
        adopt_note "  OLDER version over the one you have now." ;;
      *)
        adopt_note "  $hooks/pre-commit exists but has no archived copy to restore it from, so it"
        adopt_note "  was left exactly as it is rather than overwritten." ;;
    esac
    # A REMEDY THAT LEADS SOMEWHERE. The first version said "move your hook
    # aside and run this again" — and both routes then REFUSE: a re-run says
    # "this project has already been adopted", and `--finish` says it is "not
    # part-way through an adoption". Measured by review. This command is the
    # shared emitter, which ships into every adopted project; it was run in a
    # real adopted project with the hook moved aside and installed a hook under
    # which a compliant commit landed.
    adopt_note "  To install them: move your hook aside, then run, from the project root,"
    adopt_note "    bash -c '. scripts/lib/hook-templates.sh && soif_write_precommit_hook .git/hooks/pre-commit'"
    adopt_note "  Or run them by hand on each commit:  bash scripts/pre-commit-gate.sh --terminal-mode"
  else
    adopt_touched_disk   # BL-225-TOUCHED-DISK
    # RENDER BESIDE IT, VERIFY, THEN RENAME — never write into the existing
    # file. A write INTO it follows whatever the path is: review measured a
    # HARDLINKED hook (`ln`, no `-s`, so `-L` is false) sharing its inode with a
    # file outside the repository, and that outside file became 1707 lines of
    # framework hook at rc 0. A rename replaces the directory ENTRY, so the
    # shared inode is untouched. It also takes the reference render out of
    # `$TMPDIR`: a failed `mktemp` there reported "could not be written" over a
    # hook that HAD been replaced, with no replacement disclosed.
    _pc_ref="$hooks/.pre-commit.soif-new.$$"
    # CLEARED FIRST. A name that already exists — a symlink planted at it, or a
    # leftover from an interrupted run, since nothing traps this path — would
    # otherwise be written THROUGH by the emitter's `printf >`, which is the
    # very behaviour this whole block exists to avoid. `rm -f` on a link removes
    # the link, never its target.
    rm -f "$_pc_ref" "$_pc_ref.t" 2>/dev/null
    soif_write_precommit_hook "$_pc_ref" 2>/dev/null   # BL-242-PRECOMMIT-INSTALL
    # SOIF_ADOPT_HOOK_FAULT=pctrunc — the same fault seam as the commit-msg
    # arm's: a render that exits 0 having written a truncated file is the state
    # this verification exists for, and nothing natural produces it on demand.
    # Truncated IN PLACE (`cat >`), so the mode survives: a `mv` of a fresh
    # file dropped the executable bit and the `-x` test caught it first, which
    # left the completeness check below it untested.
    [ "${SOIF_ADOPT_HOOK_FAULT:-}" = "pctrunc" ] && [ -f "$_pc_ref" ] \
      && head -5 "$_pc_ref" > "$_pc_ref.t" 2>/dev/null && cat "$_pc_ref.t" > "$_pc_ref"   # BL-242-HOOKS-FAULT-SEAM
    # `pcnoexec`: the render is complete but NOT executable — a hooks directory
    # on a filesystem with no exec bit (SMB, exFAT), where `chmod +x` fails in
    # silence. git ignores a non-executable hook, so it must not be reported
    # installed; nothing else reaches the `-x` test below.
    [ "${SOIF_ADOPT_HOOK_FAULT:-}" = "pcnoexec" ] && chmod -x "$_pc_ref" 2>/dev/null   # BL-242-HOOKS-FAULT-SEAM
    # COMPLETE: it ends with the region's closing marker, so a truncated render
    # cannot pass. Then the rename, then confirm what is at the path is exactly
    # the file that was verified.
    _pc_sha=""
    if [ -f "$_pc_ref" ] && [ -x "$_pc_ref" ] \
       && grep -qxF "$SOIF_PRECOMMIT_CLOSE" "$_pc_ref" 2>/dev/null; then
      _pc_sha="$(adopt_sha256 "$_pc_ref")"
      mv -f "$_pc_ref" "$hooks/pre-commit" 2>/dev/null || _pc_sha=""
    fi
    if [ -n "$_pc_sha" ] && [ ! -L "$hooks/pre-commit" ] \
       && [ "$(adopt_sha256 "$hooks/pre-commit")" = "$_pc_sha" ]; then
      ADOPT_PC_STATE="installed"
      if [ "$_pc_had" -eq 1 ]; then
        adopt_note "Your own pre-commit hook was REPLACED by the framework's. Your copy is in the"
        adopt_note "archive with a restore line — see ${ADOPT_PC_ARCHIVE:-the archive}/MANIFEST.md."
        adopt_note "Nothing of it was merged: the framework's hook is written whole, so the two"
        adopt_note "could not compose the way the commit-msg gate does."
      fi
      adopt_note "Commit-time scanners installed: secret detection, the static-analysis pass and"
      adopt_note "the schema-migration checks now run on every commit."
    else
      ADOPT_PC_STATE="failed"
      adopt_say "   NOT INSTALLED — the commit-time scanners (the fallback pre-commit hook)"
      adopt_note "  The framework's hook could not be written and verified at $hooks/pre-commit."
      adopt_note "  Your hook, if you had one, is unchanged. To install the scanners by hand,"
      adopt_note "  from the project root:"
      adopt_note "    bash -c '. scripts/lib/hook-templates.sh && soif_write_precommit_hook .git/hooks/pre-commit'"
    fi
    rm -f "$_pc_ref" "$_pc_ref.t" 2>/dev/null
  fi
  # SOIF_ADOPT_HOOK_FAULT — the seam the live derivation's OTHER TWO conjuncts
  # need. `_adopt_hooks_live` asserts three facts: the hook exists, it is
  # EXECUTABLE, and it carries the gate's marker. Only the first had a fixture,
  # so an independent review deleted each of the other two and both suites
  # stayed green — two thirds of that check was decorative. Neither degenerate
  # state has a natural route: the owner's own `chmod +x` always succeeds here,
  # and the marker is appended whenever it is absent. This produces the state
  # for real, so the derivation OBSERVES it rather than being told the answer.
  # Both are reachable in the field: a hooks directory on a filesystem with no
  # exec bit (SMB, exFAT — plausible for a brownfield adoptee), and an append
  # that exits 0 having written nothing.
  case "${SOIF_ADOPT_HOOK_FAULT:-}" in                 # BL-242-HOOKS-FAULT-SEAM
    noexec) chmod -x "$hooks/commit-msg" 2>/dev/null || : ;;
    nomark) printf '%s\n' '#!/usr/bin/env bash' > "$hooks/commit-msg" 2>/dev/null || :
            chmod +x "$hooks/commit-msg" 2>/dev/null || : ;;
  esac
  return 0
}

# ── WP9d item (4) — THE WRITE SET, PERSISTED (`## BL-291:`) ────────────────
#
# The ledger lives in `$ADOPT_WORK`, which the EXIT trap deletes. So when the
# adoption commit is refused — the adoptee's own pre-commit hook, or no git
# identity — the list of what was written evaporates with the run, and the only
# way back is by hand. Persisting it into the adoptee is what makes `--finish`
# possible at all, and it must include ITSELF or a finish would re-stage
# everything except this file.
ADOPT_WRITE_SET_REL=".claude/adoption/write-set.txt"
adopt_write_write_set() {
  local root="$1" dest="$root/$ADOPT_WRITE_SET_REL" tmp
  # The marker precedes the FIRST write, `mkdir -p` included: `adopt_refuse`
  # reads it to decide whether this project was touched, and a directory
  # created before the marker is a touch it would not know about.
  adopt_touched_disk   # BL-225-TOUCHED-DISK
  mkdir -p "$(dirname "$dest")" 2>/dev/null || {
    adopt_block "could not create $(dirname "$ADOPT_WRITE_SET_REL") for the write set"; return 1; }
  tmp="$dest.tmp.$$"
  { adopt_written_paths; printf '%s\n' "$ADOPT_WRITE_SET_REL"; } | LC_ALL=C sort -u > "$tmp" || {
    adopt_block "could not write the write set"; rm -f "$tmp" 2>/dev/null; return 1; }
  mv "$tmp" "$dest" || { adopt_block "could not write the write set"; rm -f "$tmp" 2>/dev/null; return 1; }
  # `adopt_record_write`, NOT `adopt_record_written`. The typo made this line a
  # `command not found` on stderr of EVERY adoption, so the write set never
  # recorded ITSELF — which is the one property `## BL-291:`'s own comment four
  # lines above calls load-bearing: "it must include ITSELF or a finish would
  # re-stage everything except this file". Found by adversarial review reading
  # the stderr of a real run; no test looked at stderr.
  adopt_record_write "$ADOPT_WRITE_SET_REL"
  return 0
}

# _adopt_in_window ROOT — the adoption window: this project's WORKING COPY says
# adopted and its HEAD does not. Both witnesses already exist (arm 1 asks the
# same two questions); the window is the state BETWEEN them, which nothing read
# before. Measured on `579b0b0`: 83 files written, the stamp set, HEAD unmoved,
# every path still in the index, no commit-msg hook — and a re-run refusing it
# as "already adopted" while advising `resume.sh`.
_adopt_in_window() {
  local root="$1"
  ( cd "$root" && soif_adoption_adopted ".claude/manifest.json" ) || return 1
  ( cd "$root" && _soif_adoption_head_copy_adopted ".claude/manifest.json" ) && return 1
  return 0
}

# _adopt_hooks_live ROOT — is the commit-msg gate where git will look for it?
#
# Not "did the installer succeed" — that is the claim item (3) exists to stop
# resting on. It asks whether git still reports a hooks directory, whether a
# `commit-msg` in it is EXECUTABLE, and whether it carries the gate's own
# marker. The directory is published so the failure arm can name it.
#
# TWO OF THE THREE FILE TESTS DISCRIMINATE, NOT THREE, and this header said
# three until it was measured. Deleting `[ -x ]` or the marker grep each turns
# a case RED (H5, H6 — both added after an independent review deleted them and
# both suites stayed green). Deleting `[ -f ]` changes NOTHING: `[ -x ]` on a
# path that does not exist is false too, so `-f` is SUBSUMED. It is kept
# because it reads as the question a human asks first, and it is named here so
# nobody writes a mutation proof for a conjunct that cannot fail. That is this
# package's own subject applied to its own code: a check that cannot fail is
# not a check, and saying so is better than pinning it.
ADOPT_HOOKS_LIVE_DIR=""
_adopt_hooks_live() {
  local root="$1" d
  d="$(_adopt_hooks_dir "$root" 2>/dev/null)" || d=""
  ADOPT_HOOKS_LIVE_DIR="$d"
  [ -n "$d" ] || return 1
  [ -f "$d/commit-msg" ] || return 1
  [ -x "$d/commit-msg" ] || return 1
  grep -qF "$SOIF_TDD_OPEN" "$d/commit-msg" 2>/dev/null || return 1
  # SOIF_ADOPT_HOOK_VANISH — the seam the suite needs to reach this arm with an
  # install that RETURNED 0. Every natural route is refused at step 0 now, so
  # without a seam the false-receipt arm is unreachable and its proof vacuous.
  [ -z "${SOIF_ADOPT_HOOK_VANISH:-}" ] || return 1     # BL-242-HOOKS-LIVE-SEAM
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

# ── `## BL-225:` — ONE WRITE PHASE, RUN TWICE ───────────────────────────────
#
# `_adopt_write_phase` is the ONLY place the adoptee's files are written, and it
# is called twice: once by `adopt_prewrite_preflight` against a COPY of the
# tree, and once for real. That is the whole anti-drift argument. The planned
# path set is not a maintained list that can fall behind the writers — it IS
# what the writers produced, on a rehearsal. A new writer added to this function
# is in the preflight the moment it is in the real run, with no second edit.
#
# Everything after this function — staging, the commit, the hooks — is git work,
# not file writing, and is already guarded by `# BL-225-STAGE-PREFLIGHT`.
_adopt_write_phase() {
  local root="$1" work="$2" report="$3" stage

  # `.claude/test-debt.json` is the FIRST thing written into the adoptee, and a
  # first cut of the pre-write preflight sat BELOW it — so the preflight printed
  # "nothing was written to your project" while its own derived count said one
  # file had been. Measured on `## BL-242:`'s S5 fixture, and it is the exact
  # defect class this entry exists to close, in the guard written to close it.
  # It is in the phase so the rehearsal covers it and the preflight can precede
  # every writer.
  adopt_test_debt_record "$root" || return 1

  # Deliberately FIRST among the framework writers: an archive taken after a
  # writer has run is a copy of the framework's file, not of theirs.
  adopt_archive_write "$root" "$work" || return 1

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
      dispositions) adopt_write_dispositions "$root" "$report" || return 1 ;;   # BL-242-DISPOSITIONS-STAGE
      manifest)    adopt_write_manifest "$root" "$report" || return 1 ;;
      framework_docs) adopt_write_framework_docs "$root" || return 1 ;;   # BL-242-DOCS-STAGE
      ci)          adopt_write_ci "$root" "$report" || return 1 ;;   # BL-242-CI-STAGE
      session_layer) adopt_write_session_layer "$root" "$report" || return 1 ;;   # BL-242-SESSION-STAGE
      assessment_prompt) adopt_write_assessment_prompt "$root" || return 1 ;;
      adoption_record) adopt_write_adoption_record "$root" "$report" || return 1 ;;   # BL-242-RECORD-STAGE
      write_set)   adopt_write_write_set "$root" || return 1 ;;   # BL-242-WRITE-SET
      *)           adopt_refuse "unknown state stage '$stage'"; return 1 ;;
    esac
    if _adopt_halt_requested "$stage"; then
      adopt_refuse "halted after the '$stage' stage (SOIF_ADOPT_HALT_AFTER)"
      return 1
    fi
  done <<STATE_ORDER
$(_adopt_state_order)
STATE_ORDER
  return 0
}

# adopt_prewrite_preflight ROOT REPORT — refuse BEFORE the first write if any
# path the adoption is about to write is refused by the adoptee's ignore rules.
#
# THE HALF THIS CLOSES. `# BL-225-STAGE-PREFLIGHT` protects the INDEX: it asks
# `git add --dry-run` before staging and stops whole. By the time it runs, ~78
# files are already on disk. This runs before the first one.
#
# WHY A COPY AND NOT A NO-WRITE FLAG. A flag on each writer is a second thing
# that can be forgotten; a writer that ignored it would write during the
# "rehearsal". The copy needs no per-writer cooperation: the rehearsal is the
# real write phase, running for real, somewhere else. It also cannot be
# redirected by destination alone — `adopt_archive_write` copies FROM the
# adoptee into an archive inside it, so a scratch destination with the real
# source would rehearse nothing. The whole tree is copied, `.git` included,
# because the rehearsal's git behaviour must match the real one's.
#
# THE ORACLE IS NOT THE STAGING HALF'S. That half asks `git add --dry-run`,
# which needs the files to EXIST; here they do not yet. What replaces it is TWO
# questions, not one — see the block at the loop below, which carries the
# measurement. An earlier version of this header claimed a single
# `check-ignore --no-index` agreed with `git add` "in all eight" shapes; it does
# not, and asking it alone over-refused working projects. The header is kept
# short deliberately: one description of this oracle, in one place.
adopt_prewrite_preflight() {
  local root="$1" report="$2" copy work saved rc=0 planned ignored=""
  local _bl225_landed=0 _bl225_p=""
  local _reh_err="" _rl=""
  copy="$ADOPT_WORK/rehearsal/tree"
  work="$ADOPT_WORK/rehearsal/work"
  mkdir -p "$ADOPT_WORK/rehearsal" "$work" 2>/dev/null || {
    adopt_refuse "could not create the rehearsal directory"; return 1; }

  # WP9d item (7) — THE BOUND, AND THE OBJECT STORE IS SHARED (`## BL-294:`).
  # The first cut copied the whole tree, `.git/objects` included, with no bound
  # and one failure message that named disk space. On this repository that is
  # 57 MB and 0.43 s; on a real brownfield repository with a multi-GB history it
  # doubles disk use on the system volume AFTER every question has been
  # answered. Measure BEFORE copying — a bound checked afterwards is not a
  # bound — and share the objects the rehearsal only ever reads.
  local _reh_kb _reh_mb _reh_max _reh_t0 _reh_t1
  _reh_max="${SOIF_ADOPT_REHEARSAL_MAX_MB:-}"
  # FAIL LOUD ON A BAD BOUND. A non-numeric value makes `[ "$x" -ge "$y" ]`
  # print an error and evaluate FALSE — the bound switched off by a typo, with
  # noise instead of a refusal.
  case "$_reh_max" in
    ''|*[!0-9]*)
      if [ -n "$_reh_max" ]; then
        adopt_refuse "SOIF_ADOPT_REHEARSAL_MAX_MB is '$_reh_max', which is not a number of megabytes"
        return 1
      fi
      ;;
  esac
  _reh_kb="$( du -sk "$root" 2>/dev/null | awk '{print $1+0; exit}' )"
  case "$_reh_kb" in ''|*[!0-9]*) _reh_kb=0 ;; esac
  _reh_mb=$(( _reh_kb / 1024 ))
  if [ -n "$_reh_max" ] && [ "$_reh_mb" -ge "$_reh_max" ]; then   # BL-242-REHEARSAL-BOUND
    adopt_refuse "this project measures ${_reh_mb} MB and SOIF_ADOPT_REHEARSAL_MAX_MB is ${_reh_max} — the pre-write rehearsal copies the working tree and would exceed that"
    adopt_note "  Nothing was written. Raise or unset SOIF_ADOPT_REHEARSAL_MAX_MB to proceed."
    return 1
  fi
  _reh_t0="$(date +%s 2>/dev/null)" || _reh_t0=0
  # `cp -a` keeps modes and symlinks; the trailing `/.` copies the CONTENTS so
  # the copy is the tree rather than a directory holding it.
  # BL-242-REHEARSAL-SHARED — everything EXCEPT the object store, which is then
  # borrowed through `alternates`. The rehearsal only ever READS objects (the
  # ignore and index oracles), so a copy of them buys nothing and costs the
  # whole history. git treats an alternates file as authoritative, so the copy
  # is a working repository by every oracle the rehearsal asks.
  mkdir -p "$copy" 2>/dev/null || {
    adopt_refuse "could not create the rehearsal copy directory"; return 1; }
  ( cd "$root" && tar -cf - --exclude='./.git/objects' . 2>/dev/null ) \
    | ( cd "$copy" && tar -xf - 2>/dev/null ) || {
    adopt_refuse "could not copy the project for the pre-write rehearsal (disk space?)"
    return 1; }

  # The ledger is global. Point it at the rehearsal's own file and restore it
  # afterwards, or the real run would start with the rehearsal's paths already
  # recorded and stage files it never wrote.
  saved="$ADOPT_WRITTEN_LEDGER"
  mkdir -p "$copy/.git/objects/info" 2>/dev/null || {
    adopt_refuse "could not prepare the rehearsal's shared object store"; return 1; }
  printf '%s\n' "$root/.git/objects" > "$copy/.git/objects/info/alternates" || {
    adopt_refuse "could not point the rehearsal at this project's object store"; return 1; }
  # NOT "the rehearsal ran" — it has not. This times and names the COPY, which
  # is the cost the bound exists for; saying otherwise would be a receipt for
  # work not yet done, one level down from the receipt this package is about.
  _reh_t1="$(date +%s 2>/dev/null)" || _reh_t1="$_reh_t0"
  # KEPT, NOT ONLY PRINTED. §8.6 puts the rehearsal's measured time and size in
  # the Adoption Record, and a number that exists only in a scrollback buffer is
  # not a record — that sentence is the whole reason this package exists.
  ADOPT_REHEARSAL_SECONDS=$(( _reh_t1 - _reh_t0 ))   # BL-242-RECORD-REHEARSAL
  ADOPT_REHEARSAL_MB="$_reh_mb"                      # BL-242-RECORD-REHEARSAL
  adopt_note "copied the project in ${ADOPT_REHEARSAL_SECONDS}s over ${_reh_mb} MB for the rehearsal (objects shared, not copied)."

  adopt_ledger_init "$work/written" || { adopt_refuse "could not open the rehearsal ledger"; return 1; }

  # The touched-disk marker is a FILE at $ADOPT_WORK/touched and it is GLOBAL,
  # so the rehearsal's writers raise it for the copy and `adopt_refuse` then
  # tells the operator adoption "had already ATTEMPTED writes to this project".
  # Measured on `## BL-242:`'s S5 fixture. Remember whether it was already up
  # and put it back exactly as found — the rehearsal must leave no trace in the
  # facts a refusal derives from.
  local _touched_before=0
  adopt_has_touched_disk && _touched_before=1
  ADOPT_REHEARSING=1
  # THE REHEARSAL'S OWN DIAGNOSTIC IS OTHERWISE UNREACHABLE. Its output is
  # discarded so the operator sees one adoption, not two — but then a refusal
  # can only say "the rehearsal did not complete (rc=N)", which is exactly the
  # unhelpful shape `# BL-225-REFUSE-HONEST` exists to prevent. `SOIF_REHEARSAL_ERR`
  # names a file to keep it in, and finding `## BL-242:`'s S5 cause needed it:
  # the reversed state order fails at `manifest` because that writer hashes the
  # kept scan report, which `intake` writes earlier in the correct order.
  # THE REHEARSAL'S STDERR IS KEPT, NOT DISCARDED. It defaulted to /dev/null,
  # so every refusal raised INSIDE the write phase reached the operator as the
  # bare "the pre-write rehearsal did not complete (rc=1)" below — no cause, no
  # remedy. Measured on a tree whose skill directory carries a newline: the run
  # stopped correctly and safely, and told the operator nothing they could act
  # on. The seam still wins when set, so the suite can point it elsewhere.
  _reh_err="${SOIF_REHEARSAL_ERR:-$ADOPT_WORK/rehearsal-err}"
  _adopt_write_phase "$copy" "$work" "$report" >/dev/null 2>"$_reh_err" || rc=$?
  ADOPT_REHEARSING=0
  if [ "$_touched_before" -eq 0 ] && [ -n "${ADOPT_WORK:-}" ]; then
    rm -f "$ADOPT_WORK/touched" 2>/dev/null || true   # BL-225-REHEARSAL-NO-TRACE
  fi
  planned="$(adopt_written_paths)"
  # Publish the rehearsal's planned set so I20 can check it against the
  # archive's inventory before the real write phase runs (see
  # `# BL-242-OVERWRITE-INVENTORY`). A global rather than a return value
  # because the preflight's rc already means something else.
  ADOPT_PLANNED_WRITES="$planned"

  ADOPT_WRITTEN_LEDGER="$saved"
  # SOIF_REHEARSAL_KEEP=<dir> — the seam the suite needs. The copy is deleted
  # at the end of the preflight, so without it neither a control nor a mutant
  # of the shared-objects property is observable at all: the seam is
  # load-bearing, not a convenience.
  if [ -n "${SOIF_REHEARSAL_KEEP:-}" ]; then          # BL-242-REHEARSAL-KEEP
    mkdir -p "$SOIF_REHEARSAL_KEEP" 2>/dev/null \
      && cp -a "$ADOPT_WORK/rehearsal/." "$SOIF_REHEARSAL_KEEP/" 2>/dev/null || true
  fi
  rm -rf "$ADOPT_WORK/rehearsal" 2>/dev/null || true

  if [ "$rc" -ne 0 ]; then
    adopt_refuse "the pre-write rehearsal did not complete (rc=$rc) — nothing was written to your project"
    # RELAY THE INNER REASON. `# BL-225-REFUSE-HONEST`: a refusal must name what
    # actually happened, and the rehearsal is a WRAPPER — the thing that failed
    # is inside it. Without this the operator is told a rehearsal exited 1 and
    # nothing about which of their files caused it or what to do.
    if [ -s "$_reh_err" ]; then
      adopt_note "  The rehearsal stopped because:"
      while IFS= read -r _rl; do
        [ -n "$_rl" ] && adopt_note "  $_rl"
      done < "$_reh_err"
    fi
    return 1
  fi
  if [ -z "$planned" ]; then
    adopt_refuse "the pre-write rehearsal recorded no files — refusing rather than guessing"
    return 1
  fi

  # THE ORACLE, AND WHY IT IS TWO QUESTIONS AND NOT ONE. `git add` refuses an
  # ignored path — but for a path already TRACKED it refuses only when an
  # ANCESTOR DIRECTORY is ignored, not when a file or glob rule covers it.
  # Measured across four rule shapes on a tracked path (`git add` rc):
  #     .claude/   -> 1     .claude/*  -> 0     *.json -> 0     exact path -> 0
  # A first cut asked `check-ignore --no-index` for every path, which says
  # IGNORED in all four and so REFUSED THREE PROJECTS THAT WORK TODAY — any
  # adoptee that tracks a file the adoption rewrites and has a non-directory
  # rule covering it. Two measurements of the same thing had been generalised
  # from one rule shape each, in opposite directions; twelve shapes settled it.
  # `--no-index` stays for the untracked half: without it git reports nothing
  # for a tracked path, the index-aware false-clean that defeated the first fix
  # of `# BL-225-STAGE-PREFLIGHT`.
  #
  # FAIL CLOSED. `check-ignore` exits 128 on a pathspec beyond a symbolic link,
  # and treating that as "not ignored" would be a fail-OPEN guard — the shape
  # this entry exists to remove. Anything but 0 or 1 refuses.
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    local _ci=0 _dir
    if ( cd "$root" && git ls-files --error-unmatch -- "$rel" ) >/dev/null 2>&1; then
      _dir="${rel%/*}"
      [ "$_dir" = "$rel" ] && continue        # top-level tracked file: git add accepts it
      ( cd "$root" && git check-ignore --no-index -q -- "$_dir" ) 2>/dev/null || _ci=$?
    else
      ( cd "$root" && git check-ignore --no-index -q -- "$rel" ) 2>/dev/null || _ci=$?
    fi
    case "$_ci" in
      0) ignored="$ignored
$rel" ;;
      1) : ;;                                  # not ignored
      *) adopt_refuse "cannot tell whether '$rel' is covered by your ignore rules (git check-ignore exited $_ci) — refusing rather than guessing"   # BL-225-ORACLE-FAIL-CLOSED
         return 1 ;;
    esac
  done <<PLANNED
$planned
PLANNED

  if [ -n "$ignored" ]; then
    # DERIVE THE BLAST RADIUS FROM THE TREE, NOT FROM THE MARKER — BUT ONLY
    # WHERE THE TREE CAN ANSWER. The touched-disk marker records an ATTEMPT and
    # is raised BEFORE each write, so an arm that attempted one and left nothing
    # still raises it — the tool resolver does exactly that on a host missing
    # node/npm. The refusal then told the operator adoption "had already
    # ATTEMPTED writes to this project" over a provably clean tree: measured in
    # `ubuntu:24.04`, 0 files under `.claude/`, and the message still claiming
    # otherwise. That is the false-claim class `# BL-225-REFUSE-HONEST` exists
    # to remove, and it was invisible on macOS because the resolver's arm is not
    # taken when the tools are present.
    #
    # WHY THE PLANNED SET AND NOT `git status --porcelain --ignored`. Not
    # because git mis-reports an empty directory — it does not; measured on
    # macOS git 2.50.1 and ubuntu git 2.43.0, an empty ignored `.claude/`
    # yields ZERO rows under the default `--ignored=traditional` (only
    # `--ignored=matching` prints `!! .claude/`, and that is the directory
    # matching the pattern, not a file). An earlier draft of this comment
    # claimed the opposite and was refuted on both hosts; do not reinstate it.
    # The real reason is that a working project's OWN ignored content answers
    # the question wrongly: on a fixture ignoring `node_modules/ .env dist/`,
    # `git status --porcelain --ignored` returns 3 rows on both hosts before
    # adoption touches anything at all. git answers "is this tree dirty",
    # which is not the question. The planned set is exactly what THIS adoption
    # would have written, so if not one of those paths exists, this adoption
    # wrote none of them. A planned path the OPERATOR already had counts as
    # existing, which only makes this arm more conservative: it keeps the
    # marker and says less.
    #
    # AND IT IS AN INTERSECTION, NOT A REPLACEMENT. The planned set bounds the
    # driver's own writers; it does not bound the tool resolver's `eval`, whose
    # recipe may write anything anywhere. Clearing on the planned set alone
    # would let the refusal say "nothing was written" over an installer's
    # leftover file — the exact sentence adopt-tools.sh records as measured
    # history. So the clear requires BOTH: no planned path landed AND
    # `# BL-225-TOUCHED-UNBOUNDED` unraised. That flag is evidence-based, not
    # attempt-based — the resolver fingerprints the adoptee's path list either
    # side of the eval and raises it only on a real difference, or when it
    # could not read the tree at all. So a recipe that ran and changed nothing
    # does not cost the operator an honest message, and one that changed
    # something cannot be argued away by a derivation that never saw it.
    _bl225_landed=0
    while IFS= read -r _bl225_p; do
      [ -n "$_bl225_p" ] || continue
      [ -e "$root/$_bl225_p" ] && { _bl225_landed=1; break; }
    done <<LANDED
$planned
LANDED
    if [ "$_bl225_landed" -eq 0 ] && ! adopt_has_unbounded_write \
       && [ -n "${ADOPT_WORK:-}" ]; then
      rm -f "$ADOPT_WORK/touched" 2>/dev/null || true   # BL-225-REFUSE-DERIVED
    fi
    # The paths go IN the refusal, not after it in `adopt_note`s: notes print on
    # STDOUT and refusals on STDERR, so a reader piping stderr to a log would
    # get "some of your files are refused" with no list of which.
    # ROWS, not words: `wc -w` counted "my file.txt" as two refused files.
    adopt_block "your ignore rules refuse $(printf '%s' "$ignored" | grep -c .) of the files this adoption must write, so it would leave the project half-installed. NOTHING WAS WRITTEN. The refused path(s):$ignored"   # BL-225-PREWRITE-REFUSE
    adopt_note "These are the files the adoption IS — skipping one produces a broken install,"
    adopt_note "not a disclosed omission. Un-ignore them (or narrow the rule) and run this again."
    adopt_note "Note that git cannot re-include a file under an ignored DIRECTORY, so a"
    adopt_note "'!.claude/manifest.json' under '.claude/' does not help — narrow the rule itself."
    return 1
  fi
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

  # ── §8.2 STEP 3 — THE SECRETS CHECK, AND ITS POSITION IS THE POINT ───────
  # BEFORE the reverse intake, not after it. The shipped stub ran after, which
  # is right for a NOTICE and wrong for a STOP: an adoption that is going to be
  # refused must not first take the operator through every question the
  # interview asks. §8.2's step 3 row says so in as many words, and it is the
  # reason this moved rather than being replaced in place.
  #
  # THE STOP'S INPUT IS A SCAN THIS RUN PERFORMS (§6.2b). Not the survey's
  # section, not a `--scan-report` handed in — both are things the project
  # being audited controls. `_adopt_secrets_scan_own` clones the history with
  # no checkout and scans it under the framework's own rules.
  _adopt_secrets_scan_own "$root" "$report" "$ADOPT_WORK/secrets-report.json" || return 1   # BL-242-SECRETS-STOP-CALL
  # Every later step reads the report the STOP used, so the persisted copy and
  # the stamp's `scannerReportSha256` name the scan the decision was made on —
  # §6.2's property, now true of the stop and not only of the re-scan.
  report="$ADOPT_WORK/secrets-report.json"
  adopt_secrets_decide "$report" || return 1   # BL-242-SECRETS-DECIDE-CALL

  # THE CI AUDIT AND ITS QUESTIONS, BEFORE THE INTAKE. Read-only; its answers
  # are held for the record. Here rather than after the intake so its questions
  # sit at a FIXED position in the run: the intake's count depends on what the
  # environment has installed (PR #446 measured one more on the ubuntu runner).
  adopt_ci_audit "$root" || return 1   # BL-242-CI-AUDIT-CALL

  adopt_run_reverse_intake "$report" || return 1

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
  # §7 — THE COLLISION ARCHIVE, BEFORE ANY FRAMEWORK WRITER RUNS.
  #
  # It has to precede adopt_install_framework and adopt_install_hooks for one
  # reason: an archive taken AFTER a writer has run is a copy of the
  # framework's file, not of theirs, and the restore line would put the
  # framework's own output back under the operator's name. The commit-msg hook
  # is the live case — adopt_install_hooks appends a marked block to it — so
  # the archived copy is deliberately the PRE-composition one.
  adopt_prewrite_preflight "$root" "$report" || return 1   # BL-225-PREWRITE-CALL

  # ── I20 — THE OVERWRITE INVENTORY INVARIANT ──────────────────────────────
  # Every path this run PLANS to write that ALREADY EXISTED must have a row in
  # the archive's inventory. Not "the archive ran"; not "these three known
  # paths" — the intersection, computed from the rehearsal's own planned set.
  #
  # IT IS AN INVARIANT RATHER THAN A LIST BECAUSE THE LIST IS WHAT ROTS.
  # `## BL-292:` was three writers added over time, none of which had an
  # archive row, and nothing noticed for months: the defect was not that
  # somebody chose wrongly, it was that choosing wrongly had no consequence.
  # This gives it one, at the boundary, before the first real write — so the
  # next writer added without a row is caught by its author rather than by a
  # reviewer a month later.
  _adopt_overwrite_inventory_check "$root" || return 1   # BL-242-OVERWRITE-INVENTORY

  _adopt_write_phase "$root" "$ADOPT_WORK" "$report" || return 1   # BL-225-WRITE-PHASE-REAL

  # `adopt_stub_adoption_record` USED TO BE HERE. The record is real now and it
  # is written INSIDE the write phase (the `adoption_record` stage), which is
  # where it has to be: the phase is what the pre-write rehearsal replays, so a
  # record written outside it would be the one write of the run that nobody
  # rehearsed — and `_adopt_overwrite_inventory_check`'s whole point is that a
  # writer without a rehearsed, inventoried path is how `## BL-292:` happened
  # three times over.
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
  #
  # WP9d item (3) — AND THE SENTENCE IS DERIVED FROM THE HOOK THAT IS THERE.
  # It used to print because the installer had returned 0, which is a claim
  # about having TRIED. Measured on `579b0b0` (`## BL-290:`): with
  # `core.hooksPath` configured the installer wrote `.git/hooks/commit-msg`,
  # returned 0, this sentence printed, and `GIT_TRACE=1 git commit` ran no hook
  # at all. Step 0 now refuses that shape, but a receipt must not rest on a
  # refusal elsewhere holding: re-resolve the directory git will actually use
  # and look for the gate in it.
  if _adopt_hooks_live "$root"; then                    # BL-242-HOOKS-LIVE-DERIVED
    adopt_note "From your next commit onward the framework's two message gates are live in"
    adopt_note "this project: test-before-code ordering, and the Build-Loop commit check."
    adopt_blank
  else
    adopt_block "the commit-msg gate is NOT installed where git will look for it"
    adopt_note "  git runs this project's hooks from: ${ADOPT_HOOKS_LIVE_DIR:-(git could not say)}"
    adopt_note "  and the gate is not there, so test-before-code ordering and the Build-Loop"
    adopt_note "  commit check are NOT on. The adoption itself landed; this step did not."
    adopt_blank
    return 1
  fi
  # THE SCANNERS' SENTENCE IS DERIVED THE SAME WAY, and the run's exit code
  # carries it. An adoption that could not install the commit-time scanners
  # LANDED — but a caller reading rc 0 would take it as fully gated.
  if [ "${ADOPT_PC_STATE:-}" != "installed" ]; then   # BL-242-PRECOMMIT-RECEIPT
    adopt_block "the commit-time scanners are NOT installed in this project"
    adopt_note "  Secret detection, the static-analysis pass and the schema-migration checks will"
    adopt_note "  NOT run on commit. The reason is printed above, under 'Turning the gates on'."
    adopt_note "  The adoption itself landed; this step did not."
    adopt_blank
    adopt_act3_next
    return 1
  fi
  adopt_act3_next
  return $rc
}

# ── WP9d item (4) — `--finish`: complete an adoption that was written but never
# committed. NEVER `git add -A`: the operator's own uncommitted work must stay
# theirs, which is `# BF-ADOPT-STAGE-EXPLICIT`'s property and the one a fallback
# would destroy. The write set is the only source of what to stage; if it is
# absent or names a path that is gone, this refuses rather than guessing.
adopt_finish_main() {                                  # BL-242-FINISH
  local root="$1"
  ADOPT_OPERATION="Finishing the adoption"
  # THE SAME SUBJECT, which means the same name. `ADOPT_PROJECT_NAME` is set
  # inside `adopt_main`, and `--finish` is dispatched BEFORE it (like
  # `--re-add`), so without this line the subject renders its `:-this project`
  # fallback and the finished commit differs from the one the interrupted run
  # would have made — on every real adoptee. The design says "commits with the
  # same subject"; this is what makes that true.
  ADOPT_PROJECT_NAME="${root##*/}"
  if ! _adopt_in_window "$root"; then
    adopt_refuse "this project is not part-way through an adoption — --finish has nothing to complete"
    adopt_note "  --finish only completes an adoption whose state was written and whose commit"
    adopt_note "  did not land. Run adoption itself, or scripts/resume.sh if it is already adopted."
    return 1
  fi
  local ws="$root/$ADOPT_WRITE_SET_REL"
  if [ ! -f "$ws" ] || [ ! -s "$ws" ]; then
    adopt_refuse "the record of what that adoption wrote is missing ($ADOPT_WRITE_SET_REL) — refusing to guess which files belong to it"
    adopt_note "  Staging everything would sweep in your own uncommitted work. Restore that file"
    adopt_note "  from the interrupted run, or re-adopt into a clean checkout."
    return 1
  fi
  # READ INTO AN ARRAY, never `$(tr '\n' ' ' < "$ws")`. Measured: an unquoted
  # command substitution word-splits on the space, so a written path containing
  # one reaches `git add` as two pathspecs and the whole finish refuses with
  # `fatal: pathspec 'a' did not match any files` — an adoption that could never
  # be completed. Adoption writes no such path TODAY, which is exactly the kind
  # of "today" this repository's own path (with a space in it) is a standing
  # argument against.
  local rel missing=0
  FINISH_PATHS=()
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    FINISH_PATHS+=("$rel")
    [ -e "$root/$rel" ] || { adopt_note "  missing: $rel"; missing=$((missing + 1)); }
  done < "$ws"
  if [ "$missing" -gt 0 ]; then
    adopt_block "$missing path(s) the adoption recorded are no longer on disk — refusing to commit a partial adoption"
    return 1
  fi
  # The same oracle the adoption commit uses: ask before staging, stop whole.
  local blocked
  blocked="$( cd "$root" && git add --dry-run --ignore-missing -- "${FINISH_PATHS[@]}" 2>&1 >/dev/null )" || true
  if [ -n "$blocked" ]; then
    adopt_block "git will not stage every file that adoption wrote"
    adopt_note "  $blocked"
    return 1
  fi
  adopt_head "Finishing the adoption"
  local n
  n=${#FINISH_PATHS[@]}
  adopt_note "Committing exactly what the interrupted run wrote"
  adopt_note "   $n file(s), from $ADOPT_WRITE_SET_REL. Anything else you had in progress stays"
  adopt_note "   exactly as you left it — unstaged, uncommitted, untouched."
  # PAST THIS LINE THE INDEX HOLDS THE ADOPTION. `adopt_refuse` would derive
  # "nothing was written" here and be WRONG — `adopt_finish_main` runs without
  # `$ADOPT_WORK` or a ledger (it is dispatched before `adopt_main`), so the
  # derivation sees no writes and takes the REFUSED arm over an index holding
  # every path. That is `## BL-295:`'s defect class inside the function that
  # closes it, and `## BL-225:` measured the staging half too: `git add` on a
  # MIXED pathspec stages the clean paths and exits 1.
  ( cd "$root" && git add -- "${FINISH_PATHS[@]}" ) || {   # BF-ADOPT-STAGE-EXPLICIT
    adopt_block "could not stage every file that adoption wrote"
    adopt_note "  Some of them may now be staged. Check with: git status"
    return 1; }
  ( cd "$root" && git commit -q -m "chore: adopt ${ADOPT_PROJECT_NAME:-this project} into the Solo Orchestrator framework" ) || {
    adopt_block "the adoption commit still did not succeed — your own hooks or git identity may be refusing it"
    adopt_note "  The $n file(s) that adoption wrote are STAGED and waiting. Nothing was lost."
    adopt_note "  Fix or bypass what refused the commit, then run --finish again."
    return 1
  }
  ADOPT_COMMITTED=1
  adopt_install_hooks "$root" || return 1
  if _adopt_hooks_live "$root"; then                    # BL-242-HOOKS-LIVE-DERIVED
    adopt_head "Adoption complete — the project is adopted and sitting at phase 0"
    adopt_note "From your next commit onward the framework's two message gates are live in"
    adopt_note "this project: test-before-code ordering, and the Build-Loop commit check."
    adopt_blank
    adopt_note "NEXT: run this, and paste what it prints into Claude Code."
    adopt_note "  bash scripts/resume.sh"
    # `--finish` IS THE PATH THE CHANGED-HOOK GUARD EXISTS FOR, so it carries
    # the same receipt as a full run: the operator was told to fix their hook
    # and re-run, so theirs is the likeliest one to be left in place here.
    if [ "${ADOPT_PC_STATE:-}" != "installed" ]; then   # BL-242-PRECOMMIT-RECEIPT
      adopt_block "the commit-time scanners are NOT installed in this project"
      adopt_note "  The reason is printed above. The adoption itself landed; this step did not."
      return 1
    fi
    return 0
  fi
  adopt_block "the commit-msg gate is NOT installed where git will look for it"
  adopt_note "  git runs this project's hooks from: ${ADOPT_HOOKS_LIVE_DIR:-(git could not say)}"
  return 1
}
