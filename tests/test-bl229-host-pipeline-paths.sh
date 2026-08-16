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
# init.sh wrote `.gitlab-ci/release.yml` and `.bitbucket/release-pipelines.yml`
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

# _extract_fn <file> <name> — the SHIPPED function body. Executing a COPY of
# init.sh's release writer would prove nothing about init.sh; this is the same
# idiom the BL-234 suite uses for init.sh's Qdrant chain.
_extract_fn() {
  awk -v fn="$2" '
    $0 ~ "^" fn "\\(\\) \\{" { inf = 1 }
    inf { print }
    inf && /^}/ && $0 == "}" { exit }
  ' "$1"
}

# run_generate_release <projdir> <host> <language> <platform>
#   Executes init.sh::generate_release inside <projdir>. THIS IS THE R-3 GAP:
#   before this existed, nothing in the PR-blocking set ran the release writer,
#   so a mutant that broke the Bitbucket arm outright left both suites at 10/10.
GR_OUT=""; GR_RC=0
run_generate_release() {
  local proj="$1" host="$2" lang="$3" plat="$4"
  GR_RC=0
  GR_OUT="$(
    cd "$proj" || exit 9
    SCRIPT_DIR="$REPO_ROOT"
    GIT_HOST="$host"; LANGUAGE="$lang"; PLATFORM="$plat"
    TRACK="light"; PROJECT_NAME="fixture"
    # shellcheck disable=SC1090
    . "$REPO_ROOT/scripts/lib/helpers-core.sh" 2>/dev/null
    # shellcheck disable=SC1090
    . "$REPO_ROOT/scripts/lib/host.sh" 2>/dev/null
    eval "$(_extract_fn "$REPO_ROOT/init.sh" get_release_vars)"
    eval "$(_extract_fn "$REPO_ROOT/init.sh" generate_release)"
    generate_release 2>&1
  )" || GR_RC=$?
  return 0
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
bitbucket|bitbucket-pipelines.yml|.bitbucket/release-pipelines.yml|import"
if [ "$r1_out" = "$r1_want" ]; then
  pass "R1: all three hosts resolve to the paths init.sh writes, each carrying HOW the release artefact runs (file / include / import)"
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
            "bitbucket:.bitbucket/release-pipelines.yml"; do
  h="${spec%%:*}"; rel="${spec#*:}"
  d="$(newtmp)"; mk_proj "$d/p" "$h"
  mkdir -p "$d/p/$(dirname "$rel")"
  printf 'steps:\n  - echo TODO configure signing\n  - echo TODO deployment secrets\n' > "$d/p/$rel"
  printf '{"current_phase":3}\n' > "$d/p/.claude/phase-state.json"
  # WIRE the release file for the hosts that need it, so this case measures TODO
  # DETECTION rather than tripping G3's wiring check first. An unwired file's
  # TODOs are moot — that is G3's point, and keeping the two separable is what
  # makes each failure attributable.
  case "$h" in
    gitlab)
      printf 'stages: [test]\ninclude:\n  - local: /%s\n' "$rel" > "$d/p/.gitlab-ci.yml" ;;
    bitbucket)
      printf 'definitions:\n  imports:\n    release: %s\npipelines:\n  tags:\n    %s:\n      import: release-pipeline@release\n' \
        "$rel" "'v*'" > "$d/p/bitbucket-pipelines.yml" ;;
  esac
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

# ── S1: the wiring has ONE OWNER. W1 proves the wiring WORKS by executing it;
# this proves it exists in exactly one place, which W1 cannot see. Two callers
# now need it — init.sh at scaffold time and verify-install.sh as an auto-fix —
# and a second copy is precisely the drift that produced BL-229 in the first
# place (five scripts, five hardcoded GitHub paths). Read on EXECUTED LINES
# only: both files legitimately mention the wiring in comments.
s1_owner=$(_num "$(grep -c 'host_wire_release()' "$REPO_ROOT/scripts/lib/host.sh" 2>/dev/null)")
s1_dupes=0
for f in "$REPO_ROOT/init.sh" "$REPO_ROOT/scripts/verify-install.sh"; do
  n=$(sed -e 's/[[:space:]]*#.*$//' "$f" 2>/dev/null \
      | grep -cE "printf '.*imports:|printf '.*include:|sed .*/\^definitions:")
  s1_dupes=$((s1_dupes + $(_num "$n")))
done
if [ "$s1_owner" -eq 1 ] && [ "$s1_dupes" -eq 0 ]; then
  pass "S1: host_wire_release is the single owner of the wiring — no caller emits its own include:/imports: fragment. W1 proves it works; this proves there is only one of it"
else
  fail_ "S1" "owners=$s1_owner (want 1) caller-side wiring emissions=$s1_dupes (want 0) — a second copy of the wiring is the drift this entry exists to remove"
fi

# ── S3: the false comment. verify-install.sh asserted there is "no separate
# release file" for BOTH gitlab and bitbucket. That is true for bitbucket and
# false for gitlab, and it contradicted init.sh. A wrong reason in a comment is
# how the next reader re-derives the wrong fix.
# EXECUTED LINES ONLY (the BL-181 predicate): this file now CITES the old
# `bitbucket|gitlab)` arm in a comment explaining why it was split, and a naive
# grep counts that citation as the defect. Strip whole-line and trailing
# comments before matching, or the fix can never satisfy its own test.
s3_hits=$(sed -e 's/[[:space:]]*#.*$//' "$REPO_ROOT/scripts/verify-install.sh" 2>/dev/null \
          | grep -c 'bitbucket|gitlab)')
if [ "$(_num "$s3_hits")" -eq 0 ]; then
  pass "S3: verify-install.sh no longer lumps gitlab in with bitbucket — the auto-fix path is restored for the host that supports it"
else
  fail_ "S3" "verify-install.sh still refuses gitlab and bitbucket together on a premise that is only true of bitbucket"
fi

echo "=== W — the release writer is EXECUTED, not merely inspected ==="

# ── W1: THE GAP THAT LET TWO BLOCKERS THROUGH. Nothing in the PR-blocking set
# ran init.sh::generate_release, so an arm that produced NOTHING scored 10/10.
# This runs the shipped writer per host and asserts on the artefacts it leaves:
# the release steps exist, the CI file still has its own content, and — for the
# two hosts whose release file is inert without wiring — the CI file REFERENCES
# the release file. Existence was never the property that mattered.
w1_bad=""
for spec in "github:.github/workflows/ci.yml:.github/workflows/release.yml:" \
            "gitlab:.gitlab-ci.yml:.gitlab-ci/release.yml:include" \
            "bitbucket:bitbucket-pipelines.yml:.bitbucket/release-pipelines.yml:import"; do
  h="${spec%%:*}"; r1="${spec#*:}"; ci="${r1%%:*}"; r2="${r1#*:}"; rel="${r2%%:*}"; how="${r2#*:}"
  d="$(newtmp)"; mkdir -p "$d/p"
  # a CI file shaped like the one init.sh lays down for this host
  mkdir -p "$d/p/$(dirname "$ci")"
  cp "$REPO_ROOT/templates/pipelines/ci/$h/typescript.yml" "$d/p/$ci" 2>/dev/null \
    || printf 'pipelines:\n  default:\n    - step: {script: [echo ci]}\n' > "$d/p/$ci"
  ci_before="$(wc -c < "$d/p/$ci" | tr -d ' ')"
  run_generate_release "$d/p" "$h" typescript web
  if [ ! -s "$d/p/$rel" ]; then
    w1_bad="$w1_bad ${h}(no-release-artefact)"
    continue
  fi
  ci_after="$(wc -c < "$d/p/$ci" | tr -d ' ')"
  if [ "$ci_after" -lt "$ci_before" ]; then
    w1_bad="$w1_bad ${h}(ci-file-shrank:${ci_before}->${ci_after})"
  fi
  if [ -n "$how" ]; then
    # the release file is INERT unless the CI file points at it
    grep -q "$(basename "$rel")" "$d/p/$ci" 2>/dev/null \
      || w1_bad="$w1_bad ${h}(release-file-not-wired-into-$ci)"
  fi
done
if [ -z "$w1_bad" ]; then
  pass "W1: the SHIPPED generate_release runs on all three hosts — each leaves a non-empty release artefact, none shrinks the CI file it was given, and both wiring hosts leave the CI file REFERENCING the release file. A release artefact nothing points at is the defect this whole entry is about"
else
  fail_ "W1" "executing the shipped writer left these wrong:$w1_bad"
fi

echo "=== G3 — a release file nothing executes is not a release pipeline ==="

# ── G3: the deepest form of BL-229. A release file can exist and still never
# run — that is precisely what init.sh shipped for two hosts. Existence-only
# checks call that configured; the gate must not.
g3_bad=""
for spec in "gitlab:.gitlab-ci.yml:.gitlab-ci/release.yml" \
            "bitbucket:bitbucket-pipelines.yml:.bitbucket/release-pipelines.yml"; do
  h="${spec%%:*}"; r1="${spec#*:}"; ci="${r1%%:*}"; rel="${r1#*:}"
  d="$(newtmp)"; mk_proj "$d/p" "$h"
  printf '{"current_phase":3}\n' > "$d/p/.claude/phase-state.json"
  mkdir -p "$d/p/$(dirname "$ci")" "$d/p/$(dirname "$rel")"
  printf 'pipelines:\n  default:\n    - step: {script: [echo ci]}\n' > "$d/p/$ci"
  printf 'steps:\n  - echo release\n' > "$d/p/$rel"        # present, fully configured, and UNREFERENCED
  out="$( cd "$d/p" && "$BASH_BIN" "$GATE" --gate phase_3_to_4 2>&1 || true )"
  printf '%s' "$out" | grep -qi 'not wired\|never run\|not referenced\|unwired' \
    || g3_bad="$g3_bad ${h}"
done
if [ -z "$g3_bad" ]; then
  pass "G3: a release file that EXISTS but is referenced by nothing is reported on both wiring hosts — the gate stops accepting an artefact it has no reason to believe ever executes"
else
  fail_ "G3" "an unwired release file was accepted as configured on:$g3_bad"
fi

# ── N1: the export file's NAME is part of whether Bitbucket loads it at all.
# Atlassian states it twice: "create a separate file with a *pipelines.yml
# suffix". A file called release.yml in a directory called bitbucket-pipelines
# does NOT satisfy that — the directory is not the filename — and the first
# version of this fix shipped exactly that. A path the host will not read is the
# same defect as a path nothing references.
n1_rel="$( . "$HOSTLIB" 2>/dev/null; host_pipeline_resolve bitbucket >/dev/null 2>&1 && printf '%s' "$HOST_RELEASE_PATH" )"
case "$(basename "$n1_rel")" in
  *pipelines.yml)
    pass "N1: the Bitbucket export file is named '$(basename "$n1_rel")' — it ends in 'pipelines.yml', which Atlassian requires before it will load the file at all" ;;
  *)
    fail_ "N1" "export file basename '$(basename "$n1_rel")' does not end in 'pipelines.yml'; Bitbucket will not load it, so the release pipeline cannot run" ;;
esac

# ── N2: a CI file that ALREADY declares imports (brownfield adoption, or any
# repo already using YAML sharing — the population most likely to be on
# Bitbucket at all). The previous wiring emitted a SECOND `imports:` key here;
# YAML keeps the last, so the release declaration was silently discarded — and
# the substring check passed anyway, because the path string was sitting in the
# file under a shadowed key. Asserted on STRUCTURE.
N2="$(newtmp)"; mkdir -p "$N2/p"
printf 'definitions:\n  imports:\n    other: .bitbucket/other-pipelines.yml\npipelines:\n  default:\n    - step: {script: [echo ci]}\n' \
  > "$N2/p/bitbucket-pipelines.yml"
n2_rc=0
( cd "$N2/p" && . "$HOSTLIB" 2>/dev/null && host_wire_release bitbucket-pipelines.yml .bitbucket/release-pipelines.yml import ) || n2_rc=$?
n2_blocks=$(_num "$(grep -c '^  imports:$' "$N2/p/bitbucket-pipelines.yml" 2>/dev/null)")
n2_other=no; grep -q '^    other: ' "$N2/p/bitbucket-pipelines.yml" && n2_other=yes
n2_rel=no;   grep -q '^    release: ' "$N2/p/bitbucket-pipelines.yml" && n2_rel=yes
if [ "$n2_rc" -eq 0 ] && [ "$n2_blocks" -eq 1 ] && [ "$n2_other" = "yes" ] && [ "$n2_rel" = "yes" ]; then
  pass "N2: wiring MERGES into a pre-existing imports: block — one block ($n2_blocks), the project's own 'other' source preserved, and 'release' declared alongside it. Emitting a rival block let YAML discard the wiring while the check still passed"
else
  fail_ "N2" "rc=$n2_rc (want 0) imports-blocks=$n2_blocks (want 1) other-preserved=$n2_other (want yes) release-declared=$n2_rel (want yes)"
fi

# ── N3: DECLARED IS NOT INVOKED. An import source that nothing references never
# runs — this is the reviewer's MUT-E, which survived a full 12/12 because the
# old check only looked for the path string.
N3="$(newtmp)"; mkdir -p "$N3/p"
printf 'definitions:\n  imports:\n    release: .bitbucket/release-pipelines.yml\npipelines:\n  default:\n    - step: {script: [echo ci]}\n' \
  > "$N3/p/bitbucket-pipelines.yml"
n3_rc=0
( cd "$N3/p" && . "$HOSTLIB" 2>/dev/null && _hwr_verify bitbucket-pipelines.yml .bitbucket/release-pipelines.yml import ) || n3_rc=$?
# and a path named only in a COMMENT must not count either
N3b="$(newtmp)"; mkdir -p "$N3b/p"
printf '# TODO wire .bitbucket/release-pipelines.yml one day\npipelines:\n  default:\n    - step: {script: [echo ci]}\n' \
  > "$N3b/p/bitbucket-pipelines.yml"
n3b_rc=0
( cd "$N3b/p" && . "$HOSTLIB" 2>/dev/null && _hwr_verify bitbucket-pipelines.yml .bitbucket/release-pipelines.yml import ) || n3b_rc=$?
if [ "$n3_rc" -ne 0 ] && [ "$n3b_rc" -ne 0 ]; then
  pass "N3: the wiring check refuses a source that is DECLARED but never invoked (rc $n3_rc) and one named only in a COMMENT (rc $n3b_rc) — it reads structure, not a substring. Both passed the previous check"
else
  fail_ "N3" "declared-not-invoked rc=$n3_rc (want non-zero) comment-only rc=$n3b_rc (want non-zero) — the predicate is still satisfiable without a working reference"
fi

# ── G4: THE READERS MUST ASK THE SHARED PREDICATE, NOT RE-DERIVE IT. Review
# found `_hwr_verify` wired into the WRITER only, while both readers kept a
# private `grep -q "$path" "$ci"` — so the Phase 3→4 gate, the thing that
# actually blocks a release, blessed all three inert states the writer's own
# verifier rejected. Two predicates for one question, disagreeing, inside the
# entry whose thesis is single ownership. These are those three states.
g4_bad=""
# Each shape is written EXPLICITLY. A shared "append the reference" step made the
# declared-never-invoked row genuinely wired, and the case then failed for the
# right reason against the wrong fixture — caught on the first run.
_g4_case() {   # <label> <ci-content>
  local label="$1" content="$2" d out
  d="$(newtmp)"; mk_proj "$d/p" bitbucket
  printf '{"current_phase":3}\n' > "$d/p/.claude/phase-state.json"
  mkdir -p "$d/p/.bitbucket"
  printf 'steps:\n  - echo release\n' > "$d/p/.bitbucket/release-pipelines.yml"
  printf '%s' "$content" > "$d/p/bitbucket-pipelines.yml"
  out="$( cd "$d/p" && "$BASH_BIN" "$GATE" --gate phase_3_to_4 2>&1 || true )"
  printf '%s' "$out" | grep -qi 'Release pipeline configured' && g4_bad="$g4_bad $label"
  return 0
}

# 1. the path appears ONLY in a comment
_g4_case comment '# TODO wire .bitbucket/release-pipelines.yml one day
pipelines:
  default:
    - step: {script: [echo ci]}
'
# 2. DECLARED as an import source, never invoked by any pipeline
_g4_case declared 'definitions:
  imports:
    release: .bitbucket/release-pipelines.yml
pipelines:
  default:
    - step: {script: [echo ci]}
'
# 3. declaration SHADOWED — two imports: blocks, YAML keeps the last, so the
#    release source is discarded while the reference still points at it
_g4_case shadowed 'definitions:
  imports:
    release: .bitbucket/release-pipelines.yml
  imports:
    other: .bitbucket/other-pipelines.yml
pipelines:
  custom:
    release:
      import: release-pipeline@release
'
if [ -z "$g4_bad" ]; then
  pass "G4: the gate refuses all three inert shapes its old private grep blessed — a path named only in a COMMENT, a source DECLARED but never invoked, and a declaration SHADOWED by a rival imports: block. It asks the same predicate the writer does, so the two cannot disagree"
else
  fail_ "G4" "the gate still reports 'configured' for:$g4_bad — it is re-deriving the answer instead of asking # BL-229-WIRE-VERIFY"
fi

echo "=== M — mutation proofs (sites==1, N lines changed, bash -n, fresh fixture) ==="

# ── M1: the resolver's mapping is load-bearing for the gate. Neuter it and the
# gitlab arm must go back to silence.
M1="$(newtmp)"
cp -R "$REPO_ROOT/scripts" "$M1/scripts" 2>/dev/null
# Target the GitLab arm's release-path line, NOT the `case` line: replacing the
# `case` orphans its arms and the mutant lands as a SYNTAX ERROR, which kills
# every case for the wrong reason and would score as a kill. Measured on the
# first draft of this suite: parses=0. This mutant stays valid bash and is
# behaviourally decisive.
m1_meta=$(_mutate "$M1/scripts/lib/host.sh" '# BL-229-HOST-PIPELINE-GITLAB' '      HOST_RELEASE_PATH=".github/workflows/release.yml"')
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

# ── M2: THE MUTANT THAT SURVIVED THE WHOLE PR-BLOCKING SET. Adversarial review
# broke the Bitbucket release arm outright and both suites still reported 10/10,
# because nothing executed the writer. W1 exists to kill exactly this. Here the
# import declaration is emitted EMPTY, so the release file is written and never
# referenced — the shipped-broken state, reproduced deliberately.
M2="$(newtmp)"; cp -R "$REPO_ROOT" "$M2/repo" 2>/dev/null
m2_meta=$(_mutate "$M2/repo/scripts/lib/host.sh" '# BL-229-IMPORT-WIRE' '      : > "$frag"')
m2_sites="${m2_meta%% *}"; m2_rest="${m2_meta#* }"; m2_changed="${m2_rest%% *}"; m2_parses="${m2_rest##* }"
m2_d="$(newtmp)"; mkdir -p "$m2_d/p"
cp "$REPO_ROOT/templates/pipelines/ci/bitbucket/typescript.yml" "$m2_d/p/bitbucket-pipelines.yml"
m2_out="$(
  cd "$m2_d/p" || exit 9
  SCRIPT_DIR="$M2/repo"
  GIT_HOST=bitbucket; LANGUAGE=typescript; PLATFORM=web; TRACK=light; PROJECT_NAME=fixture
  # shellcheck disable=SC1090
  . "$M2/repo/scripts/lib/helpers-core.sh" 2>/dev/null
  # shellcheck disable=SC1090
  . "$M2/repo/scripts/lib/host.sh" 2>/dev/null
  eval "$(_extract_fn "$M2/repo/init.sh" get_release_vars)"
  eval "$(_extract_fn "$M2/repo/init.sh" generate_release)"
  generate_release 2>&1
)"
m2_wired=yes
grep -q '.bitbucket/release-pipelines.yml' "$m2_d/p/bitbucket-pipelines.yml" 2>/dev/null || m2_wired=no
m2_warned=no
printf '%s' "$m2_out" | grep -qi 'could not wire' && m2_warned=yes
if [ "$m2_sites" -eq 1 ] && [ "$m2_parses" -eq 1 ] && [ "$m2_wired" = "no" ] && [ "$m2_warned" = "yes" ]; then
  pass "M2: with the import declaration emitted empty, the release file lands UNWIRED — and the writer says so ('Could NOT wire') instead of reporting success. Both halves matter: W1 catches the broken state, and the scaffolder refuses to claim a write it did not make (sites=$m2_sites changed=$m2_changed parses=$m2_parses)"
else
  fail_ "M2" "sites=$m2_sites (want 1) parses=$m2_parses (want 1) changed=$m2_changed wired=$m2_wired (want no) warned=$m2_warned (want yes) — if wired=no but warned=no, the scaffolder is silently shipping an inert release pipeline, which is the exact defect this entry was blocked on"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
