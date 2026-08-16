#!/usr/bin/env bash
# tests/test-bl229-host-pipeline-paths.sh
#
# BL-229 — the release/CI pipeline paths were HARDCODED to the GitHub spelling
# in five places, so on GitLab and Bitbucket the checks that read them either
# said nothing or said something false. One root cause, three distinct symptoms:
#
#   1. scripts/check-phase-gate.sh  — `[ -f ".github/workflows/release.yml" ]`
#      is false on the other two hosts, so the Phase 3→4 release-TODO block is
#      SKIPPED ENTIRELY and prints nothing. A pipeline full of unconfigured
#      TODOs passes the gate. Not a wrong answer — a MISSING one that reads
#      exactly like a clean one.
#   2. scripts/validate.sh          — the same paths, but with `fail`, and
#      `fail` increments `errors` while the script ends `exit $errors`. So a
#      HEALTHY GitLab or Bitbucket project is told
#      `[FAIL] CI pipeline missing (.github/workflows/ci.yml)` and exits
#      one higher than the identical GitHub project. A FALSE FAILURE, visible
#      to the operator, on a project that is correct.
#   3. scripts/verify-install.sh / scripts/reconfigure-project.sh — the writers.
#      verify-install refused to auto-fix gitlab/bitbucket on the stated grounds
#      that "there is no separate release file at repo root", which contradicts
#      init.sh (it writes one) and is only half true (see below).
#
# ── AND THE ONE UNDERNEATH (why fixing the readers alone would be theatre) ──
# init.sh wrote `.gitlab-ci/release.yml` and `bitbucket-pipelines/release.yml`
# and NOTHING INCLUDED EITHER. A comment at the writer claimed "deploy phase is
# appended to bitbucket-pipelines.yml via include"; no such include existed
# anywhere in the repo. So on two of three hosts the scaffolded release pipeline
# was written to disk and never executed, and the Phase 3→4 gate would have been
# carefully validating a file that could not run.
#
# The two hosts are NOT symmetric, and the asymmetry is the design:
#   • GitLab    — `include: local` genuinely supports a subdirectory file, so
#                 `.gitlab-ci/release.yml` is legitimate and merely needed
#                 wiring. Fixed by emitting the include.
#   • Bitbucket — sharing is CROSS-REPOSITORY only
#                 (`definitions.imports.<name>: <repo-slug>:<ref>:<path>`, and
#                 the source file needs `export: true` in the OTHER repo).
#                 There is no same-repo local include, so a separate release
#                 file can NEVER execute. Karl's decision: fold the release
#                 steps into `bitbucket-pipelines.yml` and stop writing the dead
#                 file. `verify-install.sh` was right about Bitbucket and wrong
#                 about GitLab; both halves are corrected.
#
# THE RESOLVER IS THE POINT. `scripts/lib/host.sh` now owns the mapping ONCE
# (`# BL-229-HOST-PIPELINE-PATHS`) and every caller asks it. init.sh's own
# `case "$host"` is replaced by a call, so the sync-sibling trap that
# `# BL-084-TIER-KEY` exists for is not re-created here. host.sh is already
# shipped downstream by init.sh's copy list and already sourced by
# check-phase-gate.sh, so every consumer can reach it in a generated project.
#
# Hermetic: temp dirs only, no network, no init.sh invocation. bash 3.2 safe.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

HOSTLIB="$REPO_ROOT/scripts/lib/host.sh"
GATE="$REPO_ROOT/scripts/check-phase-gate.sh"
VALIDATE="$REPO_ROOT/scripts/validate.sh"

BASH_BIN="$(command -v bash)"; [ -n "$BASH_BIN" ] || BASH_BIN="/bin/bash"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] jq is not installed — this suite asserts on manifest state."
  echo ""
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

TOPTMP="$(mktemp -d)"
trap 'chmod -R u+rwX "$TOPTMP" 2>/dev/null; rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/caseXXXXXX"; }

_mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || printf '?\n'; }
_num() { case "$1" in ''|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac }
_sites() { local n; n=$(grep -c "$2\$" "$1" 2>/dev/null); _num "$n"; }
_changed_lines() { local n; n=$(diff "$1" "$2" 2>/dev/null | grep -c '^[<>]'); _num "$n"; }

# _mutate FILE MARKER REPLACEMENT — excise the one END-OF-LINE-anchored marked
# line. Delimiter '%' is absent from every marker and replacement here; '&' is
# escaped because in a sed replacement it means THE WHOLE MATCH.
_mutate() {
  local f="$1" marker="$2" repl="$3" before sites changed parses safe mode tmp
  safe=$(printf '%s' "$repl" | sed 's/&/\\&/g')
  mode="$(_mode_of "$f")"
  before="$(mktemp)"; cp -p "$f" "$before"
  sites=$(_sites "$f" "$marker")
  tmp="$(mktemp)"
  sed "s%^.*${marker}\$%${safe}%" "$f" > "$tmp" && mv "$tmp" "$f"
  [ "$mode" != "?" ] && chmod "$mode" "$f" 2>/dev/null
  changed=$(_changed_lines "$before" "$f")
  parses=0; bash -n "$f" >/dev/null 2>&1 && parses=1
  rm -f "$before"
  printf '%s %s %s\n' "$sites" "$changed" "$parses"
}

# mk_proj <dir> <host> — a project whose manifest names <host> and nothing else.
mk_proj() {
  local d="$1" host="$2"
  mkdir -p "$d/.claude"
  printf '# CLAUDE.md\n' > "$d/CLAUDE.md"
  jq -n --arg h "$host" '{host:$h}' > "$d/.claude/manifest.json"
  # check-phase-gate.sh exits 1 before any gate check if APPROVAL_LOG.md is
  # absent, so a fixture without one measures the missing fixture, not the gate.
  printf '# APPROVAL_LOG\n' > "$d/APPROVAL_LOG.md"
}

echo "=== R — the resolver owns the mapping, once ==="

# ── R1: every supported host resolves to the paths init.sh actually writes,
# and says whether the release artefact is an executable pipeline in its own
# right. Asserted as a triple per host, because a caller that gets the path but
# not the executability re-invents "…but not on Bitbucket" at every site.
R1="$(newtmp)"
r1_out="$(
  # shellcheck disable=SC1090
  . "$HOSTLIB" 2>/dev/null
  for h in github gitlab bitbucket; do
    if host_pipeline_resolve "$h" >/dev/null 2>&1; then
      printf '%s|%s|%s|%s\n' "$h" "$HOST_CI_PATH" "$HOST_RELEASE_PATH" "$HOST_RELEASE_EXECUTES"
    else
      printf '%s|RESOLVE-FAILED||\n' "$h"
    fi
  done
)"
r1_want="github|.github/workflows/ci.yml|.github/workflows/release.yml|file
gitlab|.gitlab-ci.yml|.gitlab-ci/release.yml|include
bitbucket|bitbucket-pipelines.yml|bitbucket-pipelines.yml|inline"
if [ "$r1_out" = "$r1_want" ]; then
  pass "R1: all three hosts resolve to the paths init.sh writes, each carrying HOW the release artefact runs (file / include / inline)"
else
  fail_ "R1" "got:
$r1_out
want:
$r1_want"
fi

# ── R2: an unknown host FAILS CLOSED and names itself. The old init.sh arm
# silently defaulted to the GitHub path with a warning, which is how a
# mis-recorded host produced a GitHub-shaped project on another host.
R2="$(newtmp)"
r2_rc=0
r2_err="$(
  # shellcheck disable=SC1090
  . "$HOSTLIB" 2>/dev/null
  host_pipeline_resolve "nosuchhost" 2>&1 >/dev/null
)" || r2_rc=$?
if [ "$r2_rc" -ne 0 ] && printf '%s' "$r2_err" | grep -q 'nosuchhost'; then
  pass "R2: an unknown host is REFUSED (rc=$r2_rc) and named in the message — it does not silently become GitHub"
else
  fail_ "R2" "rc=$r2_rc (want non-zero) err='$(printf '%s' "$r2_err" | tr '\n' '|' | cut -c1-200)'"
fi

# ── R3: with no argument the resolver reads the manifest, so callers inside a
# project need not know the host. Asserted by CHANGING the manifest and seeing
# the answer change — not by calling it once and trusting the value.
R3="$(newtmp)"
mk_proj "$R3/p" gitlab
r3_a="$( cd "$R3/p" && . "$HOSTLIB" 2>/dev/null && host_pipeline_resolve >/dev/null 2>&1 && printf '%s' "$HOST_RELEASE_PATH" )"
jq -n '{host:"github"}' > "$R3/p/.claude/manifest.json"
r3_b="$( cd "$R3/p" && . "$HOSTLIB" 2>/dev/null && host_pipeline_resolve >/dev/null 2>&1 && printf '%s' "$HOST_RELEASE_PATH" )"
if [ "$r3_a" = ".gitlab-ci/release.yml" ] && [ "$r3_b" = ".github/workflows/release.yml" ]; then
  pass "R3: with no argument the resolver reads .claude/manifest.json — flipping the manifest host flips the answer ($r3_a -> $r3_b)"
else
  fail_ "R3" "gitlab manifest gave '$r3_a' (want .gitlab-ci/release.yml); github manifest gave '$r3_b' (want .github/workflows/release.yml)"
fi

echo "=== V — validate.sh stops failing healthy non-GitHub projects ==="

# ── V1: THE REGRESSION THIS FIXES, measured before the fix as:
#   GitHub    exit 10   [OK]   CI pipeline
#   GitLab    exit 11   [FAIL] CI pipeline missing (.github/workflows/ci.yml)
# Three projects, each healthy FOR ITS OWN HOST. The assertion is that no host
# is told a file is missing when the file its own host uses is present.
v1_bad=""
for spec in "github:.github/workflows/ci.yml:.github/workflows/release.yml" \
            "gitlab:.gitlab-ci.yml:.gitlab-ci/release.yml" \
            "bitbucket:bitbucket-pipelines.yml:bitbucket-pipelines.yml"; do
  h="${spec%%:*}"; rest="${spec#*:}"; ci="${rest%%:*}"; rel="${rest#*:}"
  d="$(newtmp)"; mk_proj "$d/p" "$h"
  mkdir -p "$d/p/$(dirname "$ci")" "$d/p/$(dirname "$rel")"
  printf 'pipeline: ci\n' > "$d/p/$ci"
  printf 'pipeline: release\n' > "$d/p/$rel"
  out="$( cd "$d/p" && "$BASH_BIN" "$VALIDATE" 2>&1 )"
  if printf '%s' "$out" | grep -qiE '\[FAIL\].*(CI|Release) pipeline missing'; then
    v1_bad="$v1_bad $h"
  fi
done
if [ -z "$v1_bad" ]; then
  pass "V1: a project healthy for its OWN host is never told its pipeline is missing — github, gitlab and bitbucket all clean"
else
  fail_ "V1" "these hosts still get a false 'pipeline missing' FAIL:$v1_bad"
fi

echo "=== G — the Phase 3→4 gate runs on every host, and fails CLOSED ==="

# ── G1: a release pipeline full of TODOs must be CAUGHT on every host. Before
# the fix the gitlab/bitbucket arms were skipped entirely and printed nothing,
# which is the `# BL-112-SAST-NOTRUN` doctrine's exact prohibition: "the scanner
# did not run" must never be spelled the same as "the scanner found nothing".
g1_bad=""
for spec in "github:.github/workflows/release.yml" \
            "gitlab:.gitlab-ci/release.yml" \
            "bitbucket:bitbucket-pipelines.yml"; do
  h="${spec%%:*}"; rel="${spec#*:}"
  d="$(newtmp)"; mk_proj "$d/p" "$h"
  mkdir -p "$d/p/$(dirname "$rel")"
  printf 'steps:\n  - echo TODO configure signing\n  - echo TODO deployment secrets\n' > "$d/p/$rel"
  printf '{"current_phase":3}\n' > "$d/p/.claude/phase-state.json"
  out="$( cd "$d/p" && "$BASH_BIN" "$GATE" --gate phase_3_to_4 2>&1 || true )"
  printf '%s' "$out" | grep -qi 'unconfigured TODO' || g1_bad="$g1_bad $h"
done
if [ -z "$g1_bad" ]; then
  pass "G1: an unconfigured release pipeline is reported on ALL THREE hosts — the gitlab/bitbucket arms no longer skip in silence"
else
  fail_ "G1" "TODO-laden release pipeline went unreported on:$g1_bad"
fi

# ── G2: an ABSENT release pipeline is reported rather than skipped. This is the
# fail-closed half, and it is what the neighbouring artifact loop in the same
# script has always done for HANDOFF.md / sbom.json six lines below.
g2_bad=""
for h in github gitlab bitbucket; do
  d="$(newtmp)"; mk_proj "$d/p" "$h"
  printf '{"current_phase":3}\n' > "$d/p/.claude/phase-state.json"
  out="$( cd "$d/p" && "$BASH_BIN" "$GATE" --gate phase_3_to_4 2>&1 || true )"
  printf '%s' "$out" | grep -qi 'release pipeline' || g2_bad="$g2_bad $h"
done
if [ -z "$g2_bad" ]; then
  pass "G2: a MISSING release pipeline is named on all three hosts — absence fails closed instead of reading as clean"
else
  fail_ "G2" "absence went unmentioned on:$g2_bad"
fi

echo "=== S — the scaffolded release pipeline can actually RUN ==="

# ── S1: GitLab. init.sh writes `.gitlab-ci/release.yml`; the root
# `.gitlab-ci.yml` must INCLUDE it or the file is decorative. GitLab's
# `include: local` supports a subdirectory path, so this is the whole fix.
if grep -rq "include" "$REPO_ROOT/templates/pipelines/ci/" 2>/dev/null \
   && grep -rq "gitlab-ci/release.yml" "$REPO_ROOT/templates/" "$REPO_ROOT/init.sh" 2>/dev/null; then
  pass "S1: the scaffolded GitLab pipeline INCLUDES .gitlab-ci/release.yml — the release file is reachable rather than decorative"
else
  fail_ "S1" "no include of .gitlab-ci/release.yml found in the scaffolded GitLab pipeline; the release file would never execute"
fi

# ── S2: Bitbucket. A separate file can never execute there, so the scaffolder
# must NOT write one. Karl's decision: fold the steps into
# bitbucket-pipelines.yml. Asserted as an ABSENCE with a structural
# discriminator — the dead path must not be written anywhere.
if [ "$(_num "$(grep -c 'target_dir="bitbucket-pipelines"' "$REPO_ROOT/init.sh" 2>/dev/null)")" -eq 0 ]; then
  pass "S2: init.sh no longer writes bitbucket-pipelines/release.yml — a file Bitbucket cannot include, and therefore cannot run"
else
  fail_ "S2" "init.sh still writes bitbucket-pipelines/release.yml, which Bitbucket has no mechanism to execute"
fi

# ── S3: the false comment. verify-install.sh asserted there is "no separate
# release file" for BOTH gitlab and bitbucket. That is true for bitbucket and
# false for gitlab, and it contradicted init.sh. A wrong reason in a comment is
# how the next reader re-derives the wrong fix.
if ! grep -q 'bitbucket|gitlab)' "$REPO_ROOT/scripts/verify-install.sh" 2>/dev/null; then
  pass "S3: verify-install.sh no longer lumps gitlab in with bitbucket — the auto-fix path is restored for the host that supports it"
else
  fail_ "S3" "verify-install.sh still refuses gitlab and bitbucket together on a premise that is only true of bitbucket"
fi

echo "=== M — mutation proofs (sites==1, N lines changed, bash -n, fresh fixture) ==="

# ── M1: the resolver's mapping is load-bearing for the gate. Neuter it and the
# gitlab arm must go back to silence.
M1="$(newtmp)"
cp -R "$REPO_ROOT/scripts" "$M1/scripts" 2>/dev/null
m1_meta=$(_mutate "$M1/scripts/lib/host.sh" '# BL-229-HOST-PIPELINE-PATHS' '  HOST_CI_PATH=".github/workflows/ci.yml"; HOST_RELEASE_PATH=".github/workflows/release.yml"; HOST_RELEASE_EXECUTES=file')
m1_sites="${m1_meta%% *}"; m1_rest="${m1_meta#* }"; m1_changed="${m1_rest%% *}"; m1_parses="${m1_rest##* }"
d="$(newtmp)"; mk_proj "$d/p" gitlab
mkdir -p "$d/p/.gitlab-ci"
printf 'steps:\n  - echo TODO configure signing\n' > "$d/p/.gitlab-ci/release.yml"
printf '{"current_phase":3}\n' > "$d/p/.claude/phase-state.json"
m1_out="$( cd "$d/p" && "$BASH_BIN" "$M1/scripts/check-phase-gate.sh" --gate phase_3_to_4 2>&1 || true )"
m1_caught=no; printf '%s' "$m1_out" | grep -qi 'unconfigured TODO' && m1_caught=yes
if [ "$m1_sites" -eq 1 ] && [ "$m1_parses" -eq 1 ] && [ "$m1_caught" = "no" ]; then
  pass "M1: with the host mapping collapsed to the GitHub spelling, a TODO-laden GitLab release pipeline goes UNREPORTED again — G1 is load-bearing (sites=$m1_sites changed=$m1_changed parses=$m1_parses)"
else
  fail_ "M1" "sites=$m1_sites (want 1) parses=$m1_parses (want 1) changed=$m1_changed caught=$m1_caught (want no)"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
