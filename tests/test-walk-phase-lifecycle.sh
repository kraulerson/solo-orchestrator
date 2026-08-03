#!/usr/bin/env bash
# tests/test-walk-phase-lifecycle.sh — the 2026-08-02 first-time-user walk,
# phase-lifecycle findings (WALK-ISSUE-LOG ISSUE-004/005/007/012/013/015).
#
# WHY THIS EXISTS
#   A junior-developer persona built a real project end-to-end against the
#   generated framework and logged 18 findings. Six of them are lifecycle
#   defects in process-checklist.sh / reconfigure-project.sh and in the
#   governance prose that drives them:
#
#   ISSUE-015 (Major, THE DEADLOCK) — the generated CLAUDE.md told the
#     operator to set .current_phase by hand at every gate. Do that for 3→4
#     and the two halves lock: check-phase-gate.sh's BL-105 arm FAILs
#     ("current_phase is 4 but the Phase-4 release checklist was NEVER
#     STARTED — run --start-phase4") while --start-phase4 consults that same
#     gate FIRST and refuses. The only command that clears BL-105 will not
#     run while BL-105 is failing. Fixed in two places: the template text
#     (the --start-phaseN commands own the bump) and a recovery arm in
#     start_phase4 that SATISFIES the BL-105 requirement — initializing the
#     checklist before the consult — rather than bypassing it.
#   ISSUE-012 — --complete-step build_loop:X succeeded while
#     .build_loop.feature was null, recording steps against no feature.
#   ISSUE-007 — --status printed "Progress: 9/7 steps" for phase2_init
#     because writers outside the 7-step vocabulary append to the same array;
#     the inflated numerator also SUPPRESSED the "Remaining:" list.
#   ISSUE-004 — reconfigure-project.sh appended its audit row to the END of
#     APPROVAL_LOG.md (inside "## Penetration Test") instead of into
#     "## Approval History".
#   ISSUE-013 / ISSUE-005 — prose: the zero-collection privacy-policy path
#     and the phase-starter commands were both undiscoverable.
#
# REGISTRATION: no scaffolder invocation → BOTH lists (aggregator + the
# tests.yml unit lane). HERMETIC: git/jq/awk/sed only — no network, no
# Docker, no semgrep. The Phase-3 validation summary is pre-written FRESH
# (tree-bound, per BL-082) so the gate never autoruns the scanner driver.
# bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PC="$REPO_ROOT/scripts/process-checklist.sh"
CPG="$REPO_ROOT/scripts/check-phase-gate.sh"
RECONF="$REPO_ROOT/scripts/reconfigure-project.sh"
TMPL_CLAUDE="$REPO_ROOT/templates/generated/claude-md.tmpl"
GUIDE="$REPO_ROOT/docs/builders-guide.md"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq required"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# ── fixture builders ────────────────────────────────────────────────────────

# _install_scripts <dir> [extra scripts…] — copy the scripts under test plus
# the helper libs they source. scripts/ is gitignored in the fixtures so a
# script swap (the mutation batteries) never changes the fixture's git tree.
_install_scripts() {
  local d="$1"; shift
  mkdir -p "$d/scripts/lib"
  local s
  for s in "$@"; do
    cp "$REPO_ROOT/scripts/$s" "$d/scripts/" || return 1
    chmod +x "$d/scripts/$s"
  done
  cp "$REPO_ROOT/scripts/lib/helpers.sh" \
     "$REPO_ROOT/scripts/lib/helpers-core.sh" \
     "$REPO_ROOT/scripts/lib/helpers-full.sh" "$d/scripts/lib/" || return 1
}

# mk_phase3_clean <dir> — a Light-track project sitting at current_phase 3
# whose Phase 3→4 gate is CLEAN. Everything the 3→4 gate reads is present,
# so the ONLY thing that can fail the gate is the BL-105 never-started arm —
# which is exactly the walker's situation.
mk_phase3_clean() {
  local d="$1"
  rm -rf "$d"
  mkdir -p "$d/.claude" "$d/docs/test-results/phase3" "$d/docs/phase-0" "$d/docs/eval-results"
  ( cd "$d" && git init -q && git config user.email t@t.invalid && git config user.name t ) >/dev/null 2>&1 || return 1
  _install_scripts "$d" process-checklist.sh check-phase-gate.sh || return 1
  printf '{"host":"github","mode":"personal"}\n' > "$d/.claude/manifest.json"
  cat > "$d/.claude/phase-state.json" <<'JSON'
{"current_phase":3,"track":"light","deployment":"personal","poc_mode":null,"gates":{"phase_0_to_1":"2026-02-01","phase_1_to_2":"2026-03-01","phase_2_to_3":"2026-04-01","phase_3_to_4":null}}
JSON
  jq -n '{
    phase1_artifacts:{data_classification:"public"},
    phase2_init:{verified:true,steps_completed:["remote_repo_created","pushed_initial","branch_protection_configured","project_scaffolded","data_model_applied","pre_commit_hooks_installed","ci_pipeline_configured","initialization_verified"],attestations:{branch_protection:{reason:"github_free_tier"}}},
    phase3_validation:{steps_completed:["integration_testing","security_hardening","chaos_testing","accessibility_audit","performance_audit","contract_testing","results_archived","pre_launch_preparation","legal_review"],started_at:"2026-07-01T00:00:00Z"},
    phase4_release:{steps_completed:[],started_at:null},
    build_loop:{feature:null,step:0,steps_completed:[]},
    uat_session:{session_id:null,step:0,steps_completed:[],started_at:null}
  }' > "$d/.claude/process-state.json"
  cat > "$d/APPROVAL_LOG.md" <<'MD'
# Approval Log

## Phase Gate: Phase 0 → Phase 1
| Field | Value |
|---|---|
| Approver | Alice Signer |
| Date | 2026-02-01 |

## Phase Gate: Phase 1 → Phase 2
| Field | Value |
|---|---|
| Approver | Alice Signer |
| Date | 2026-03-01 |

## Phase Gate: Phase 2 → Phase 3
| Field | Value |
|---|---|
| Approver | Alice Signer |
| Date | 2026-04-01 |

## Phase Gate: Phase 3 → Phase 4
| Field | Value |
|---|---|
| Approver | Alice Signer |
| Date | 2026-05-01 |

## UAT Sign-off (Step 3.6 — final acceptance)
| Field | Value |
|---|---|
| Signed off by | Alice Signer |
| Date | 2026-05-01 |
MD
  { local n; for n in 1 2 3 4 5 6 7 8; do echo "## ${n}. S${n}"; echo "Content."; echo ""; done; } > "$d/PRODUCT_MANIFESTO.md"
  { local m; for m in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do echo "## ${m}. S${m}"; echo "Content."; echo ""; done; } > "$d/PROJECT_BIBLE.md"
  printf '# Features\n'          > "$d/FEATURES.md"
  printf '# Changelog\n'         > "$d/CHANGELOG.md"
  printf '# Handoff\n'           > "$d/HANDOFF.md"
  printf '# User Guide\n'        > "$d/USER_GUIDE.md"
  printf '# Security\n'          > "$d/SECURITY.md"
  printf '{"sbom":true}\n'       > "$d/sbom.json"
  printf '# Incident Response\n' > "$d/docs/INCIDENT_RESPONSE.md"
  printf 'frd\n'      > "$d/docs/phase-0/frd.md"
  printf 'journey\n'  > "$d/docs/phase-0/user-journey.md"
  printf 'contract\n' > "$d/docs/phase-0/data-contract.md"
  printf 'semgrep pass\n' > "$d/docs/test-results/2026-05-01_semgrep_pass.json"
  jq -n '{generated_at:"2026-05-01",reviews:[{reviewer:"Security",status:"complete",file:"sec.md"},{reviewer:"Red Team",status:"complete",file:"rt.md"}]}' \
    > "$d/docs/eval-results/review-manifest.json"
  # scripts/ and the gate's own write surfaces are ignored so the BL-082
  # tree binding below stays valid across script swaps and gate runs.
  printf 'scripts/\ndocs/snapshots/\ndocs/test-results/phase3/\n' > "$d/.gitignore"
  ( cd "$d" && git add -A && git commit -q -m "chore: fixture" ) >/dev/null 2>&1 || return 1
  local tree
  tree=$( cd "$d" && git rev-parse "HEAD^{tree}" )
  {
    echo "# Phase 3 Validation Summary"
    echo "- tree: $tree"
    echo "- dirty: no"
    echo "- Overall: PASS"
    echo ""
    echo "## Machine-readable results"
    echo '```'
    echo "RESULT semgrep-full-tree PASS"
    echo "RESULT license PASS"
    echo "RESULT snyk PASS"
    echo "RESULT zap-dast PASS"
    echo "RESULT threat-model PASS"
    echo '```'
  } > "$d/docs/test-results/phase3/summary-2026-05-01T00-00-00Z.md"
}

bump_to_4() {  # the manual bump the old CLAUDE.md prescribed
  ( cd "$1" && jq '.current_phase = 4' .claude/phase-state.json > ps.tmp && mv ps.tmp .claude/phase-state.json )
}

gate_rc()   { ( cd "$1" && bash scripts/check-phase-gate.sh   >/dev/null 2>&1 ); echo $?; }
gate_out()  { ( cd "$1" && bash scripts/check-phase-gate.sh          2>&1 ); }
start4_out(){ ( cd "$1" && bash scripts/process-checklist.sh --start-phase4 2>&1 ); }
start4_rc() { ( cd "$1" && bash scripts/process-checklist.sh --start-phase4 >/dev/null 2>&1 ); echo $?; }
started_at(){ jq -r '.phase4_release.started_at' "$1/.claude/process-state.json"; }

# mk_basic <dir> — a minimal phase-2 project for the build-loop / status arms.
mk_basic() {
  local d="$1"
  rm -rf "$d"
  mkdir -p "$d/.claude"
  ( cd "$d" && git init -q && git config user.email t@t.invalid && git config user.name t ) >/dev/null 2>&1 || return 1
  _install_scripts "$d" process-checklist.sh || return 1
  printf '{"host":"github","mode":"personal"}\n' > "$d/.claude/manifest.json"
  printf '{"current_phase":2,"track":"light","deployment":"personal","poc_mode":null,"gates":{}}\n' > "$d/.claude/phase-state.json"
}

# ════════════════════════════════════════════════════════════════════════════
# ISSUE-015 — the phase-4 deadlock
# ════════════════════════════════════════════════════════════════════════════
echo "=== ISSUE-015: manual current_phase bump to 4 deadlocks --start-phase4 ==="

P="$TOPTMP/deadlock"
if ! mk_phase3_clean "$P"; then
  fail_ "T15-fixture" "could not build the phase-3 fixture"
else
  # Sanity: the fixture's 3→4 gate is clean BEFORE the bump. Without this the
  # rest of the block would prove nothing (a gate failing for other reasons
  # also refuses start-phase4).
  if [ "$(gate_rc "$P")" != "0" ]; then
    fail_ "T15-fixture-clean" "fixture gate is not clean at current_phase=3:
$(gate_out "$P")"
  else
    pass "T15-fixture-clean: the 3→4 gate passes at current_phase=3"
  fi

  bump_to_4 "$P"

  out=$(gate_out "$P"); rc=$(gate_rc "$P")
  if [ "$rc" = "0" ]; then
    fail_ "T15-a" "expected the gate to BLOCK after the manual bump; rc=0"
  elif ! printf '%s' "$out" | grep -q "NEVER STARTED"; then
    fail_ "T15-a" "gate blocked but not on the BL-105 never-started arm:
$out"
  else
    pass "T15-a: manual bump to 4 makes the gate FAIL on BL-105 (never started)"
  fi

  out=$(start4_out "$P"); rc=$(start4_rc "$P")
  if [ "$rc" != "0" ]; then
    fail_ "T15-b" "--start-phase4 refused in the deadlock state (rc=$rc) — the deadlock is back:
$out"
  elif [ "$(started_at "$P")" = "null" ]; then
    fail_ "T15-b" "--start-phase4 returned 0 but phase4_release.started_at is still null"
  elif ! printf '%s' "$out" | grep -q "deadlock state"; then
    fail_ "T15-b" "recovery ran without the explanatory INFO:
$out"
  else
    pass "T15-b: --start-phase4 recovers — checklist initialized, INFO explains why"
  fi

  if [ "$(gate_rc "$P")" != "0" ]; then
    fail_ "T15-c" "the gate still blocks after recovery:
$(gate_out "$P")"
  else
    pass "T15-c: the BL-105 arm is SATISFIED after recovery (gate rc=0)"
  fi

  # Recovery must not leave scratch state behind.
  if ls "$P/.claude/"*.bak >/dev/null 2>&1; then
    fail_ "T15-d" "recovery left a backup file behind: $(ls "$P/.claude/"*.bak)"
  else
    pass "T15-d: recovery leaves no backup file behind"
  fi
fi

echo "=== ISSUE-015: the normal path (no manual bump) is unchanged ==="
P="$TOPTMP/normal"
if ! mk_phase3_clean "$P"; then
  fail_ "T15-e" "fixture build failed"
else
  out=$(start4_out "$P"); rc=$(start4_rc "$P")
  cur=$(jq -r '.current_phase' "$P/.claude/phase-state.json")
  if [ "$rc" != "0" ]; then
    fail_ "T15-e" "--start-phase4 from current_phase=3 should succeed; rc=$rc
$out"
  elif [ "$cur" != "4" ]; then
    fail_ "T15-e" "--start-phase4 did not advance current_phase (got '$cur')"
  elif printf '%s' "$out" | grep -q "deadlock state"; then
    fail_ "T15-e" "recovery INFO fired on the normal path (false positive):
$out"
  else
    pass "T15-e: from current_phase=3 the starter owns the bump; no recovery INFO"
  fi
fi

echo "=== ISSUE-015: a REFUSED start-phase4 still mutates nothing ==="
P="$TOPTMP/refuse"
if ! mk_phase3_clean "$P"; then
  fail_ "T15-f" "fixture build failed"
else
  # Break the gate for a REAL reason (no Phase-3 validation summary, and no
  # autorun to regenerate one), then enter the deadlock state.
  rm -f "$P"/docs/test-results/phase3/summary-*.md
  bump_to_4 "$P"
  before=$(shasum -a 256 "$P/.claude/process-state.json" | awk '{print $1}')
  rc=$( ( cd "$P" && SOLO_PHASE3_GATE_NOAUTORUN=1 bash scripts/process-checklist.sh --start-phase4 >/dev/null 2>&1 ); echo $? )
  after=$(shasum -a 256 "$P/.claude/process-state.json" | awk '{print $1}')
  if [ "$rc" = "0" ]; then
    fail_ "T15-f" "start-phase4 passed a genuinely failing 3→4 gate — the recovery must not bypass it"
  elif [ "$before" != "$after" ]; then
    fail_ "T15-f" "a REFUSED start-phase4 left process-state.json mutated"
  elif ls "$P/.claude/"*.bak >/dev/null 2>&1; then
    fail_ "T15-f" "a REFUSED start-phase4 left a backup file behind"
  else
    pass "T15-f: a genuinely failing 3→4 gate still refuses, and rolls the recovery back"
  fi
fi

# ════════════════════════════════════════════════════════════════════════════
# ISSUE-012 — build-loop steps against a null feature
# ════════════════════════════════════════════════════════════════════════════
echo "=== ISSUE-012: --complete-step build_loop:X refuses a null feature ==="
P="$TOPTMP/nullfeat"
if ! mk_basic "$P"; then
  fail_ "T12" "fixture build failed"
else
  cat > "$P/.claude/process-state.json" <<'JSON'
{"build_loop":{"feature":null,"step":0,"steps_completed":[],"started_at":null},
 "uat_session":{"session_id":null,"step":0,"steps_completed":[],"started_at":null},
 "phase1_architecture":{"steps_completed":[],"started_at":null},
 "phase3_validation":{"steps_completed":[],"started_at":null},
 "phase4_release":{"steps_completed":[],"started_at":null},
 "phase2_init":{"steps_completed":[],"verified":true}}
JSON
  out=$( cd "$P" && bash scripts/process-checklist.sh --complete-step build_loop:tests_written 2>&1 )
  rc=$( ( cd "$P" && bash scripts/process-checklist.sh --complete-step build_loop:tests_written >/dev/null 2>&1 ); echo $? )
  n=$(jq '.build_loop.steps_completed | length' "$P/.claude/process-state.json")
  if [ "$rc" = "0" ]; then
    fail_ "T12-a" "a step was recorded against a null feature (rc=0):
$out"
  elif [ "$n" != "0" ]; then
    fail_ "T12-a" "the refusal still wrote the step (steps_completed length=$n)"
  elif ! printf '%s' "$out" | grep -q -- "--start-feature"; then
    fail_ "T12-a" "the refusal does not name --start-feature:
$out"
  else
    pass "T12-a: null feature → refusal that names --start-feature, nothing recorded"
  fi

  # No false positive: with a real feature the same step completes.
  ( cd "$P" && bash scripts/process-checklist.sh --start-feature "walk-feature" >/dev/null 2>&1 )
  rc=$( ( cd "$P" && bash scripts/process-checklist.sh --complete-step build_loop:tests_written >/dev/null 2>&1 ); echo $? )
  if [ "$rc" != "0" ]; then
    fail_ "T12-b" "a real Build Loop can no longer record tests_written (rc=$rc)"
  else
    pass "T12-b: with a registered feature the step still completes"
  fi
fi

# ════════════════════════════════════════════════════════════════════════════
# ISSUE-007 — "Progress: 9/7 steps"
# ════════════════════════════════════════════════════════════════════════════
echo "=== ISSUE-007: phase2_init progress counts only template steps ==="
P="$TOPTMP/status"
if ! mk_basic "$P"; then
  fail_ "T7" "fixture build failed"
else
  jq -n '{build_loop:{feature:null,step:0,steps_completed:[],started_at:null},
          uat_session:{session_id:null,step:0,steps_completed:[],started_at:null},
          phase1_architecture:{steps_completed:[],started_at:null},
          phase3_validation:{steps_completed:[],started_at:null},
          phase4_release:{steps_completed:[],started_at:null},
          phase2_init:{verified:true,steps_completed:["remote_repo_created","branch_protection_configured","project_scaffolded","data_model_applied","pre_commit_hooks_installed","ci_pipeline_configured","initialization_verified","pushed_initial","branch_protection_verified"]}}' \
    > "$P/.claude/process-state.json"
  out=$( cd "$P" && bash scripts/process-checklist.sh --status 2>&1 )
  if printf '%s' "$out" | grep -q "Progress: 9/7"; then
    fail_ "T7-a" "still prints an out-of-range numerator:
$out"
  elif ! printf '%s' "$out" | grep -q "Progress: 7/7 steps"; then
    fail_ "T7-a" "expected 'Progress: 7/7 steps':
$out"
  elif ! printf '%s' "$out" | grep -q "pushed_initial"; then
    fail_ "T7-a" "the out-of-vocabulary steps were dropped instead of reported:
$out"
  else
    pass "T7-a: 7/7 with the two init-time steps reported separately"
  fi

  # The inflated numerator also SUPPRESSED the Remaining: list — 6 template
  # steps + 3 extras cleared the old `completed < total` guard.
  jq -n '{build_loop:{feature:null,step:0,steps_completed:[],started_at:null},
          uat_session:{session_id:null,step:0,steps_completed:[],started_at:null},
          phase1_architecture:{steps_completed:[],started_at:null},
          phase3_validation:{steps_completed:[],started_at:null},
          phase4_release:{steps_completed:[],started_at:null},
          phase2_init:{verified:false,steps_completed:["remote_repo_created","branch_protection_configured","project_scaffolded","data_model_applied","pre_commit_hooks_installed","ci_pipeline_configured","pushed_initial","branch_protection_verified","local_only_acknowledged"]}}' \
    > "$P/.claude/process-state.json"
  out=$( cd "$P" && bash scripts/process-checklist.sh --status 2>&1 )
  if ! printf '%s' "$out" | grep -q "Progress: 6/7 steps"; then
    fail_ "T7-b" "expected 'Progress: 6/7 steps':
$out"
  elif ! printf '%s' "$out" | sed -n '/Phase 2 Initialization/,$p' | grep -q "initialization_verified"; then
    fail_ "T7-b" "the genuinely missing step is still hidden from Remaining::
$out"
  else
    pass "T7-b: 6/7 and the missing template step is listed under Remaining:"
  fi
fi

# ════════════════════════════════════════════════════════════════════════════
# ISSUE-004 — audit row routed to the Approval History section
# ════════════════════════════════════════════════════════════════════════════
echo "=== ISSUE-004: reconfigure audit rows land in ## Approval History ==="

# mk_reconf <dir> <approval-log-template> — a project the reconfigure script
# will act on, with a fully rendered approval log.
mk_reconf() {
  local d="$1" tmpl="$2"
  rm -rf "$d"
  mkdir -p "$d/.claude"
  ( cd "$d" && git init -q && git config user.email t@t.invalid && git config user.name t ) >/dev/null 2>&1 || return 1
  _install_scripts "$d" reconfigure-project.sh || return 1
  printf '{"host":"github","mode":"personal","frameworkVersion":"test"}\n' > "$d/.claude/manifest.json"
  printf '{"current_phase":1,"track":"light","deployment":"personal","context":{"project":"t","platform":"web","language":"javascript","track":"light"}}\n' > "$d/.claude/phase-state.json"
  printf '{"source_dir":"%s"}\n' "$REPO_ROOT" > "$d/.claude/orchestrator-source.json"
  printf '{}\n' > "$d/.claude/process-state.json"
  printf '# t\n' > "$d/CLAUDE.md"
  printf '# Project Intake — t\n' > "$d/PROJECT_INTAKE.md"
  sed -e 's/__PROJECT_NAME__/t/g' -e 's/__TODAY__/2026-01-01/g' \
    "$REPO_ROOT/templates/generated/$tmpl" > "$d/APPROVAL_LOG.md"
  printf 'scripts/\n' > "$d/.gitignore"
  ( cd "$d" && git add -A && git commit -q -m fixture ) >/dev/null 2>&1
}

# _history_section <file> — the ## Approval History section, exclusive of the
# next H2 header.
_history_section() {
  awk '/^## Approval History/ {f=1; next} f && /^## / {exit} f' "$1"
}

P="$TOPTMP/reconf-personal"
if ! mk_reconf "$P" approval-log-personal.tmpl; then
  fail_ "T4-a" "fixture build failed"
else
  tail_before=$(tail -1 "$P/APPROVAL_LOG.md")
  ( cd "$P" && bash scripts/reconfigure-project.sh --field data_classification --new confidential >/dev/null 2>&1 )
  sec=$(_history_section "$P/APPROVAL_LOG.md")
  row=$(printf '%s\n' "$sec" | grep "data_classification set" || true)
  cells=$(printf '%s' "$row" | awk '{n = gsub(/\|/, "|"); print n - 1}')
  dels=$( cd "$P" && git diff --numstat -- APPROVAL_LOG.md | awk '{print $2}' )
  if [ -z "$row" ]; then
    fail_ "T4-a" "no audit row inside ## Approval History; section was:
$sec"
  elif [ "$cells" != "4" ]; then
    fail_ "T4-a" "row has $cells cells but the personal Approval History table has 4 — the tail cells would not render: $row"
  elif [ "$(tail -1 "$P/APPROVAL_LOG.md")" != "$tail_before" ]; then
    fail_ "T4-a" "the row still landed at end-of-file (last line changed)"
  elif [ "${dels:-0}" != "0" ]; then
    fail_ "T4-a" "append-only violated: $dels line(s) deleted/modified"
  else
    pass "T4-a: personal template — 4-cell row inside the section, pure insertion"
  fi
fi

P="$TOPTMP/reconf-org"
if ! mk_reconf "$P" approval-log-org.tmpl; then
  fail_ "T4-b" "fixture build failed"
else
  ( cd "$P" && bash scripts/reconfigure-project.sh --field data_classification --new confidential >/dev/null 2>&1 )
  sec=$(_history_section "$P/APPROVAL_LOG.md")
  row=$(printf '%s\n' "$sec" | grep "data_classification set" || true)
  cells=$(printf '%s' "$row" | awk '{n = gsub(/\|/, "|"); print n - 1}')
  if [ -z "$row" ]; then
    fail_ "T4-b" "no audit row inside ## Approval History; section was:
$sec"
  elif [ "$cells" != "6" ]; then
    fail_ "T4-b" "row has $cells cells but the organizational table has 6: $row"
  else
    pass "T4-b: organizational template — 6-cell row inside the section"
  fi
fi

# ════════════════════════════════════════════════════════════════════════════
# ISSUE-013 / ISSUE-005 — discoverability prose
# ════════════════════════════════════════════════════════════════════════════
echo "=== ISSUE-013: the legal_review refusal names the zero-collection path ==="
P="$TOPTMP/legal"
if ! mk_basic "$P"; then
  fail_ "T13-a" "fixture build failed"
else
  jq -n '{phase1_artifacts:{data_classification:"internal"},
          build_loop:{feature:null,step:0,steps_completed:[]},
          uat_session:{session_id:null,step:0,steps_completed:[],started_at:null},
          phase2_init:{verified:true,steps_completed:[]},
          phase3_validation:{steps_completed:["integration_testing","security_hardening","chaos_testing","accessibility_audit","performance_audit","contract_testing","results_archived","pre_launch_preparation"],started_at:"2026-07-01T00:00:00Z"},
          phase4_release:{steps_completed:[],started_at:null}}' \
    > "$P/.claude/process-state.json"
  out=$( cd "$P" && bash scripts/process-checklist.sh --complete-step phase3_validation:legal_review 2>&1 )
  rc=$( ( cd "$P" && bash scripts/process-checklist.sh --complete-step phase3_validation:legal_review >/dev/null 2>&1 ); echo $? )
  if [ "$rc" = "0" ]; then
    fail_ "T13-a" "the fail-closed legal_review arm no longer blocks — the gate must NOT be weakened:
$out"
  elif ! printf '%s' "$out" | grep -qi "collects, stores and transmits no user data"; then
    fail_ "T13-a" "the refusal does not name the zero-collection policy path:
$out"
  else
    pass "T13-a: still fail-closed, and the honest zero-collection path is named"
  fi
fi

echo "=== ISSUE-013/005: the prose surfaces carry the same guidance ==="
if grep -q "collects, stores and transmits no user data" "$GUIDE"; then
  pass "T13-b: builders-guide Step 3.6 Legal names the zero-collection policy"
else
  fail_ "T13-b" "docs/builders-guide.md does not carry the zero-collection sentence"
fi

# The generated CLAUDE.md is where the walker looked for the phase starters
# and where the deadlock instruction lived. Scope the assertions to the
# Governance Tracking section so a mention anywhere else cannot satisfy them.
GOV=$(awk '/^### Governance Tracking/ {f=1; next} f && /^### / {exit} f' "$TMPL_CLAUDE")
missing=""
for cmd in -- --start-phase1 --start-phase3 --start-phase4 --verify-init; do
  [ "$cmd" = "--" ] && continue
  printf '%s' "$GOV" | grep -q -- "$cmd" || missing="$missing $cmd"
done
if [ -n "$missing" ]; then
  fail_ "T5-a" "Governance Tracking does not mention:$missing"
else
  pass "T5-a: Governance Tracking names every phase-entry command"
fi

if printf '%s' "$GOV" | grep -q "set \`current_phase\` to the new phase number"; then
  fail_ "T5-b" "Governance Tracking still instructs the manual current_phase bump that causes the deadlock"
elif ! printf '%s' "$GOV" | grep -qi "Never set \`current_phase\` by hand"; then
  fail_ "T5-b" "Governance Tracking does not state that the starters own the bump"
else
  pass "T5-b: the manual-bump instruction is gone and the ownership rule is stated"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
