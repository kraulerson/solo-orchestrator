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
ADOPT_COLLISIONS=""
adopt_install_framework() {
  local root="$1"
  local rel src dst n_copied=0 n_collided=0
  ADOPT_COLLISIONS="$ADOPT_WORK/collisions"
  : > "$ADOPT_COLLISIONS"
  adopt_head "Installing the framework's own scripts"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    src="$ADOPT_FRAMEWORK_ROOT/$rel"
    dst="$root/$rel"
    [ -f "$src" ] || continue
    if [ -e "$dst" ]; then
      printf '%s\n' "$rel" >> "$ADOPT_COLLISIONS"
      n_collided=$((n_collided + 1))
      continue
    fi
    mkdir -p "$(dirname "$dst")" 2>/dev/null || { adopt_refuse "could not create $(dirname "$rel")"; return 1; }
    cp "$src" "$dst" 2>/dev/null || { adopt_refuse "could not install $rel"; return 1; }
    chmod +x "$dst" 2>/dev/null
    adopt_record_write "$rel"
    n_copied=$((n_copied + 1))
  done <<INSTALL_SET
$(soif_parse_shipped_scripts "$ADOPT_FRAMEWORK_ROOT/init.sh" "$ADOPT_FRAMEWORK_ROOT/scripts")
INSTALL_SET
  adopt_note "Installed $n_copied framework script(s); left $n_collided of your own file(s) untouched."
  [ "$n_copied" -gt 0 ] || { adopt_refuse "no framework scripts could be installed — is this a complete clone?"; return 1; }
  adopt_stub_collision_archive "$n_collided"
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
adopt_sha256() {
  shasum -a 256 "$1" 2>/dev/null | awk '{print $1}' \
    || sha256sum "$1" 2>/dev/null | awk '{print $1}' \
    || printf ''
}

adopt_write_manifest() {
  local root="$1" report="$2"
  local host mode sha
  host="$(adopt_report_read "$report" '.stack.ciHost // ""')"
  case "$host" in ''|null) host="other" ;; esac
  mode="$ADOPT_DEPLOYMENT"

  if [ -f "$root/.claude/manifest.json" ]; then
    adopt_jq_edit "$root" ".claude/manifest.json" '.host = $h | .mode = $m' --arg h "$host" --arg m "$mode" || return 1
  else
    jq -n --arg h "$host" --arg m "$mode" '{host: $h, mode: $m, remote_url: ""}' \
      | adopt_write_file "$root" ".claude/manifest.json" || return 1
  fi

  sha="$(adopt_sha256 "$root/.claude/adoption/scout-report.json")"

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
  adopt_head "Committing exactly what was written"
  adopt_note "$n file(s), named one by one. Anything else you had in progress stays"
  adopt_note "exactly as you left it — unstaged, uncommitted, untouched."
  ( cd "$root" && git add -- "${FILES_TO_STAGE[@]}" ) || {   # BF-ADOPT-STAGE-EXPLICIT
    adopt_refuse "could not stage the adoption files (are any of them ignored by .gitignore?)"
    return 1
  }
  ( cd "$root" && git commit -q -m "chore: adopt ${ADOPT_PROJECT_NAME:-this project} into the Solo Orchestrator framework" ) || {
    adopt_refuse "the adoption commit did not succeed — your own hooks or git identity may have refused it"
    return 1
  }
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
  adopt_stub_test_debt_ledger

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

  adopt_head "Adopted"
  adopt_note "Scenario: $ADOPT_SCENARIO. Landed at phase $ADOPT_LANDED_PHASE."
  adopt_note "The framework's gates are live in this project from the next commit onward."
  return $rc
}
