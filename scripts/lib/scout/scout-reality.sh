#!/usr/bin/env bash
# scripts/lib/scout/scout-reality.sh — §8.2's `reality` section: the five
# read-only probes, plus the derived rollup.
#
# SPEC: docs/designs/2026-08-02-brownfield-adoption-v1.md §8.2 (the `reality`
# object and the extraction table row naming process-checklist.sh's
# `verify_init()` as the source).
#
# M5: sources nothing. See scripts/lib/scout/scout-core.sh's header.
#
# ─────────────────────────────────────────────────────────────────────────────
# WHAT WAS EXTRACTED, AND WHAT WAS DELETED IN THE COPY
#
# The original is `verify_init()` in `scripts/process-checklist.sh`. It is a
# WRITER: its first statement is `ensure_state_file`, and every passing probe
# appends its own name to `.phase2_init.steps_completed` in
# `.claude/process-state.json`. The final arm writes `phase2_init.verified` and
# raises `current_phase`.
#
# NONE OF THAT IS HERE, and the deletion is the point of the file rather than a
# detail of it. §3.1's promise is that the scanner writes NOTHING outside its
# own report path. A survey that mutates the thing being surveyed is not a
# survey, and — worse — it would be writing FRAMEWORK state into a project that
# has not agreed to adopt the framework. The writes are removed, not guarded:
# there is no flag that turns them back on, because a flag is a thing that gets
# set. The proof is tests/test-brownfield-wp1-scout.sh R1/R2, which hash the
# entire fixture before and after; X2 re-introduces an ensure_state_file-shaped
# write and requires those cases to go red.
#
# THE FIVE PROBES §8.2 NAMES, and the two it disposes of:
#
#   remote_repo_created         `git remote get-url origin` — read-only as-is.
#   branch_protection_configured  ALWAYS `unknown`. See below.
#   ci_pipeline_configured      widened past the original's exact `ci.yml`.
#   project_scaffolded          the original's lockfile list, unchanged.
#   pre_commit_hooks_installed  `.git/hooks/pre-commit` executable, unchanged.
#   branch_protection: see the marker.
#   data_model_applied          NOT probeable. Omitted with a reason, never
#                               faked — the original cannot auto-verify it
#                               either and says so to the operator.
#
# WHY branch_protection_configured IS ALWAYS `unknown`.
#   The original verifies it for real, through the host dispatcher, against the
#   host's API. A read-only survey tool must not make authenticated API calls
#   on the operator's behalf: the operator asked it to look at a directory, and
#   nothing about that request licenses spending their credentials on a remote
#   they may not even have chosen yet. `unknown` is the honest answer and the
#   `how` string carries the reason, so a later reader cannot mistake the blank
#   for "not configured". Worth noting that the original does not always reach
#   the host either — its `# BL-126-ATTEST-CONSULT-BEGIN` fence short-circuits
#   on a recorded tier-limited attestation — but that attestation lives in
#   framework state a brownfield project does not have.
#
# THE ROLLUP is `initialization_verified` in the original: an auto-complete arm
# that fires when every prerequisite step is done. Here it is a derived, written
# -nowhere summary. It can never read `pass`, because one probe is permanently
# `unknown` — and that is the correct result rather than a defect to paper
# over. The scanner genuinely does not know whether this project's phase-2
# initialization is complete, and saying so is what it is for.

# _scout_probe WORK NAME RESULT HOW — append one probe row.
_scout_probe() {
  printf '%s\t%s\t%s\n' "$2" "$3" "$4" >> "$1/probes"
}

# scout_reality_probes ROOT WORK — fills $WORK with the reality section's data.
#
# Writes (all inside WORK, which the entry script owns and removes):
#   probes  `<name>\t<pass|fail|unknown>\t<how>` in §8.2's order
#   rollup  `<result>\t<passed>\t<total>\t<how>`
#
# READ-ONLY. Every statement below is a test, a read or a printf. Nothing here
# creates, truncates, moves or chmods anything under ROOT.
scout_reality_probes() {
  local _root="$1" _work="$2"
  local _bp_result _ci_file _f _lf _base
  local _pass=0 _fail=0 _unknown=0 _total=0 _result _how
  local TAB
  TAB=$(printf '\t')

  : > "$_work/probes"

  # ── 1. remote_repo_created ────────────────────────────────────────────────
  if ! scout_have_git; then
    _scout_probe "$_work" remote_repo_created unknown \
      "git is not installed on this machine, so no repository question can be answered"
  elif git -C "$_root" remote get-url origin >/dev/null 2>&1; then
    _scout_probe "$_work" remote_repo_created pass \
      "git remote get-url origin resolves"
  else
    _scout_probe "$_work" remote_repo_created fail \
      "git remote get-url origin found no remote named origin"
  fi

  # ── 2. branch_protection_configured ───────────────────────────────────────
  # The one line in this file that must never grow a condition. See the header.
  _bp_result="unknown"  # SCOUT-PROBE-BP-UNKNOWN
  _scout_probe "$_work" branch_protection_configured "$_bp_result" \
    "host API not consulted — this is a read-only scan and it makes no authenticated calls to your git host"

  # ── 3. ci_pipeline_configured ─────────────────────────────────────────────
  # Widened from the original's exact `.github/workflows/ci.yml`: an adoptee
  # names its pipeline whatever it likes, and §8.2's own example shows the
  # probe passing on a `deploy.yml`. Any workflow file counts.
  _ci_file=""
  for _f in "$_root/.github/workflows"/*.yml "$_root/.github/workflows"/*.yaml; do
    if [ -f "$_f" ]; then _base="${_f##*/}"; _ci_file=".github/workflows/$_base"; break; fi
  done
  if [ -z "$_ci_file" ] && [ -f "$_root/.gitlab-ci.yml" ]; then _ci_file=".gitlab-ci.yml"; fi
  if [ -z "$_ci_file" ] && [ -f "$_root/bitbucket-pipelines.yml" ]; then _ci_file="bitbucket-pipelines.yml"; fi
  if [ -n "$_ci_file" ]; then
    _scout_probe "$_work" ci_pipeline_configured pass "$_ci_file"
  else
    _scout_probe "$_work" ci_pipeline_configured fail \
      "no pipeline file found (.github/workflows/*.yml, .gitlab-ci.yml, bitbucket-pipelines.yml)"
  fi

  # ── 4. project_scaffolded ─────────────────────────────────────────────────
  # The original's lockfile list, copied unchanged. A lockfile is the cheapest
  # honest signal that dependencies were actually installed once.
  _lf=""
  for _f in package-lock.json yarn.lock pnpm-lock.yaml bun.lockb Pipfile.lock \
            poetry.lock Cargo.lock go.sum pubspec.lock Package.resolved \
            gradle.lockfile packages.lock.json mix.lock composer.lock; do
    if [ -f "$_root/$_f" ]; then _lf="$_f"; break; fi
  done
  if [ -n "$_lf" ]; then
    _scout_probe "$_work" project_scaffolded pass "lockfile found: $_lf"
  else
    _scout_probe "$_work" project_scaffolded fail \
      "no dependency lockfile found in the project root"
  fi

  # ── 5. pre_commit_hooks_installed ─────────────────────────────────────────
  if [ -x "$_root/.git/hooks/pre-commit" ]; then
    _scout_probe "$_work" pre_commit_hooks_installed pass \
      ".git/hooks/pre-commit exists and is executable"
  else
    _scout_probe "$_work" pre_commit_hooks_installed fail \
      ".git/hooks/pre-commit is missing or not executable"
  fi

  # ── The derived rollup ────────────────────────────────────────────────────
  while IFS="$TAB" read -r _f _result _how; do
    [ -n "$_f" ] || continue
    _total=$(( _total + 1 ))
    case "$_result" in
      pass)    _pass=$(( _pass + 1 )) ;;
      fail)    _fail=$(( _fail + 1 )) ;;
      *)       _unknown=$(( _unknown + 1 )) ;;
    esac
  done < "$_work/probes"

  if [ "$_fail" -gt 0 ]; then
    _result="fail"
    _how="$_fail of $_total checks came back negative"
  elif [ "$_unknown" -gt 0 ]; then
    _result="unknown"
    _how="$_pass of $_total checks passed and $_unknown could not be answered without contacting your git host"
  else
    _result="pass"
    _how="all $_total checks passed"
  fi
  printf '%s\t%s\t%s\t%s\n' "$_result" "$_pass" "$_total" "$_how" > "$_work/rollup"
  return 0
}
