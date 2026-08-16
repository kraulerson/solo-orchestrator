#!/usr/bin/env bash
# tests/test-bl222-security-clock-evidence.sh
#
# BL-222 — the release gate's ONLY security clock is satisfied by a FILENAME,
# and the filename pattern is far wider than the thing it stands for.
#
# scripts/check-maintenance.sh reads the newest dated name in docs/test-results/
# matching `*snyk*`, `*dep*`, `*audit*`, `*semgrep*` or `*sast*`. `*dep*` catches
# `deployment-notes-<date>.md`. WP6 FOLDED the separate 95-day dependency-audit
# row into the deep-security cadence, so ONE stray match now satisfies the WHOLE
# deep-security clock — and that clock is what scripts/cut-release.sh refuses on
# (refusal 3, exit 5).
#
# Reproduced end-to-end by the WP6 adversarial review: a phase-4 project whose
# docs/test-results/ holds nothing but `deployment-notes-<date>.md` reports
# `[OK] Deep security scan (dependency audit folded in) current` and CUTS A
# RELEASE at rc 0 with the tag written, having never run a scan. Delete that one
# file and the same project refuses at rc 2.
#
# TWO PROPERTIES MAKE THIS WORSE THAN ITS SIBLINGS, and both are why it is the
# residual that got fixed rather than merely filed:
#   • it sits on the release gate's ONLY security clock, because the fold means
#     one match satisfies both the dependency and the deep-security windows;
#   • it needs NO INTENT WHATSOEVER. The dated-empty-file residual requires
#     someone to fabricate evidence. This one requires an honest project to
#     write deployment notes.
#
# ── THE THREE RESIDUALS, ALL FIXED HERE ────────────────────────────────────
#   R-WP6-4  SUBSTRING BREADTH — `*dep*` matches `deployment*`. Narrowed to the
#            dependency-audit vocabulary that does not spell `deployment`.
#            Note `*audit*` already covers `dep-audit`/`npm-audit`/`pip-audit`/
#            `cargo-audit`, so `*dep*` was mostly redundant BEFORE it was wrong.
#   R-WP6-7  NON-FILE ARTEFACTS — a freshly dated empty DIRECTORY, or a dangling
#            symlink, satisfied it too: `ls` supplies the name and the date is
#            read off the name. Now the artefact must be a readable regular file.
#   R-WP6-5  CROSS-HOST DATE DIVERGENCE — `2026-13-45` is refused by both
#            parsers, but an in-range impossibility like `2026-02-30`
#            NORMALISES on BSD (to March 2) and is refused by GNU. Same repo,
#            same file, two verdicts depending on the operator's laptop. Fixed
#            by round-tripping the parsed epoch back to a date and requiring it
#            to equal the input, which is host-independent.
#
# And the entry's own trigger: check-maintenance.sh's header claimed all three
# were "Filed as backlog lines". They were not; BL-222 IS that filing. A false
# tracking claim is worse than an untracked residual, because it stops anyone
# looking.
#
# ASSERTIONS ARE EXIT CODES, because the script's own contract is one:
#   0 = every cadence current    1 = something overdue    2 = UNDETERMINED
# and cut-release refuses on 2. A printed label is not the verdict — CLAUDE.md's
# `[WARN]` trap is about exactly that gap, and `## BL-213:` is this script's own
# instance of it.
#
# Hermetic: temp dirs, local git only, no network, no init.sh. bash 3.2 safe.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-maintenance.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'chmod -R u+rwX "$TOPTMP" 2>/dev/null; rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/caseXXXXXX"; }

_num() { case "$1" in ''|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac }
_mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || printf '?\n'; }
_sites() { local n; n=$(grep -c "$2\$" "$1" 2>/dev/null); _num "$n"; }
_changed_lines() { local n; n=$(diff "$1" "$2" 2>/dev/null | grep -c '^[<>]'); _num "$n"; }

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

days_ago() {   # <n> -> YYYY-MM-DD, n whole days before now, UTC
  local n="$1" e
  e=$(( $(date -u +%s) - n * 86400 ))
  date -u -d "@$e" +%Y-%m-%d 2>/dev/null || date -u -r "$e" +%Y-%m-%d
}

FIXTURE_SEQ=0
mk_proj() {
  local d="$1"
  mkdir -p "$d/.claude"
  (
    cd "$d" && unset GITHUB_BASE_REF
    git init -q .
    git config user.email "bl222@example.invalid"
    git config user.name "BL222 Fixture"
    git config commit.gpgsign false
  ) >/dev/null 2>&1
  printf '{"track":"light","deployment":"personal","poc_mode":null,"current_phase":4,"phases":{}}\n' \
    > "$d/.claude/phase-state.json"
}

commit_dated() {
  local d="$1" f="$2" n="$3" stamp want
  FIXTURE_SEQ=$((FIXTURE_SEQ + 1))
  want="$(days_ago "$n")"; stamp="${want}T12:00:00+0000"
  printf 'fixture %s r%s\n' "$f" "$FIXTURE_SEQ" > "$d/$f"
  (
    cd "$d" && unset GITHUB_BASE_REF
    GIT_AUTHOR_DATE="$stamp" GIT_COMMITTER_DATE="$stamp" git add "$f"
    GIT_AUTHOR_DATE="$stamp" GIT_COMMITTER_DATE="$stamp" git commit -q -m "chore: $f r$FIXTURE_SEQ"
  ) >/dev/null 2>&1
}

# mk_base <dir> — every cadence surface fresh EXCEPT the security evidence.
# Each case then supplies exactly one security artefact, so a non-zero answer is
# attributable to that artefact and nothing else.
mk_base() {
  local d="$1"
  mk_proj "$d"
  commit_dated "$d" CHANGELOG.md 2
  commit_dated "$d" sbom.json 2
  mkdir -p "$d/docs/test-results"
}

CHK_RC=0; CHK_OUT=""
run_check() {   # <scripts-dir> <project-dir>
  local sd="$1" p="$2"
  CHK_RC=0
  CHK_OUT="$( cd "$p" && unset GITHUB_BASE_REF; bash "$sd/check-maintenance.sh" </dev/null 2>&1 )" || CHK_RC=$?
  return 0
}

if [ ! -f "$CHECKER" ]; then
  echo "  [FAIL] scripts/check-maintenance.sh is missing" >&2
  echo "Results: 0 passed, 1 failed"; exit 1
fi

echo "=== B — the baseline, so every row below perturbs exactly one thing ==="

# ── B1: a genuine, freshly dated scan artefact makes the whole check rc 0.
# Without this the suite could pass by making EVERYTHING undetermined, which is
# the "narrowed until nothing matches" failure mode.
B1="$(newtmp)"; mk_base "$B1/p"
printf 'scan\n' > "$B1/p/docs/test-results/$(days_ago 10)_semgrep_pass.txt"
run_check "$REPO_ROOT/scripts" "$B1/p"
if [ "$CHK_RC" -eq 0 ]; then
  pass "B1: a real, fresh semgrep artefact -> rc 0. This is the baseline; anything below that answers non-zero does so because of the artefact it swapped in"
else
  fail_ "B1" "rc=$CHK_RC (want 0) out='$(printf '%s' "$CHK_OUT" | tr '\n' '|' | cut -c1-300)'"
fi

echo "=== D — a filename is not a scan ==="

# ── D1: THE HEADLINE. Deployment notes are not a security scan, and no honest
# project should have to know that `deployment` contains `dep`.
D1="$(newtmp)"; mk_base "$D1/p"
printf 'we deployed on tuesday\n' > "$D1/p/docs/test-results/deployment-notes-$(days_ago 3).md"
run_check "$REPO_ROOT/scripts" "$D1/p"
d1_said_current=no
printf '%s' "$CHK_OUT" | grep -qi 'Deep security scan.*current' && d1_said_current=yes
if [ "$CHK_RC" -eq 2 ] && [ "$d1_said_current" = "no" ]; then
  pass "D1: a project whose ONLY artefact is deployment-notes-<date>.md answers rc 2 (undetermined) and does NOT report the deep-security scan current — the release gate's only security clock stops being satisfied by a word that merely contains 'dep'"
else
  fail_ "D1" "rc=$CHK_RC (want 2) said-current=$d1_said_current (want no) — a deployment note is still satisfying the security clock"
fi

# ── D2: THE ANTI-OVER-NARROWING ROW. Real dependency-audit artefacts must still
# count, or the fix trades a false pass for a false alarm. Every spelling here is
# one a real toolchain emits.
d2_bad=""
# `dep-scan` is OWASP's vulnerability scanner and `dependabot-alerts` is the
# commonest dependency artefact on the default host — both were caught by the
# old broad `*dep*` and both are lost by a naive narrowing. The loss direction
# is fail-safe (rc 2 blocks a release cut rather than waving one through), but a
# false alarm on a project that DID run its scan is still a defect.
for name in "dep-audit-DATE.json" "npm-audit-DATE.txt" "pip-audit-DATE.json" \
            "cargo-audit-DATE.txt" "dependency-check-DATE.html" "deps-report-DATE.txt" \
            "dep-scan-DATE.json" "dependabot-alerts-DATE.json"; do
  d="$(newtmp)"; mk_base "$d/p"
  printf 'findings: none\n' > "$d/p/docs/test-results/${name/DATE/$(days_ago 5)}"
  run_check "$REPO_ROOT/scripts" "$d/p"
  [ "$CHK_RC" -eq 0 ] || d2_bad="$d2_bad ${name}(rc=$CHK_RC)"
done
if [ -z "$d2_bad" ]; then
  pass "D2: every real dependency-audit spelling still satisfies the clock — dep-audit, npm-audit, pip-audit, cargo-audit, dependency-check, deps-report, dep-scan (OWASP) and dependabot-alerts. The narrowing removed 'deployment', not the coverage"
else
  fail_ "D2" "these legitimate artefacts stopped counting:$d2_bad"
fi

# ── D3: a freshly dated empty DIRECTORY is not evidence. `ls` supplies the name
# and the date is read off the name, so before the fix a mkdir satisfied it.
D3="$(newtmp)"; mk_base "$D3/p"
mkdir -p "$D3/p/docs/test-results/$(days_ago 3)_semgrep_run"
run_check "$REPO_ROOT/scripts" "$D3/p"
if [ "$CHK_RC" -eq 2 ]; then
  pass "D3: a freshly dated empty DIRECTORY does not satisfy the clock (rc 2) — the artefact must be a readable regular file, not merely a name in the listing"
else
  fail_ "D3" "rc=$CHK_RC (want 2) — a mkdir is still passing as a security scan"
fi

# ── D4: a dangling symlink is a name with nothing behind it. Same shape as D3,
# one step further: the path resolves to nothing at all.
D4="$(newtmp)"; mk_base "$D4/p"
ln -s /nonexistent/target "$D4/p/docs/test-results/$(days_ago 3)_sast_report.txt" 2>/dev/null
run_check "$REPO_ROOT/scripts" "$D4/p"
if [ "$CHK_RC" -eq 2 ]; then
  pass "D4: a DANGLING SYMLINK does not satisfy the clock (rc 2) — a name that resolves to nothing is not a scan report"
else
  fail_ "D4" "rc=$CHK_RC (want 2) — a broken symlink is still passing as a security scan"
fi

echo "=== C — the same date must mean the same thing on every host ==="

# ── D5 / R-WP6-5: 2026-02-30 does not exist. GNU refuses it; BSD NORMALISES it
# to March 2 and returns a perfectly good epoch. Same repo, same file, two
# verdicts depending on whose laptop ran the check. Asserted on THIS host, but
# the fix is a round-trip comparison, which is host-independent by construction.
D5="$(newtmp)"; mk_base "$D5/p"
printf 'scan\n' > "$D5/p/docs/test-results/2026-02-30_semgrep_pass.txt"
run_check "$REPO_ROOT/scripts" "$D5/p"
if [ "$CHK_RC" -eq 2 ]; then
  pass "D5: an in-range impossible date (2026-02-30) is refused (rc 2) rather than silently normalised to March 2 — the verdict no longer depends on which date(1) the operator happens to have"
else
  fail_ "D5" "rc=$CHK_RC (want 2) — 2026-02-30 was accepted as a real date on this host, so the answer is host-dependent"
fi

echo "=== H — the header stops claiming a filing that never happened ==="

# ── H1: the trigger for the whole entry. Three residuals were described
# accurately and then said to have been "Filed as backlog lines"; none was. A
# false tracking claim is worse than an untracked residual, because it stops
# anyone from looking. Asserted as an absence, so it is paired with H2's
# structural check that the disclosure itself survives.
if ! grep -q 'Filed as backlog lines' "$CHECKER"; then
  pass "H1: the header no longer claims the three residuals were 'Filed as backlog lines' — they were not, and BL-222 is that filing"
else
  fail_ "H1" "check-maintenance.sh still asserts the residuals were filed as backlog lines"
fi

# ── H2: the disclosure must not be deleted along with the false clause. An
# absence assertion needs a companion that fails if the whole block went.
if grep -q 'R-WP6-4' "$CHECKER" && grep -q 'BL-222' "$CHECKER"; then
  pass "H2: the residual disclosure SURVIVES and now cites its real filing (R-WP6-4 named, BL-222 cited) — H1 is not satisfiable by deleting the block"
else
  fail_ "H2" "the residual disclosure was removed rather than corrected — H1 must not be satisfiable by deletion"
fi

echo "=== M — mutation proofs ==="

# ── M1: restore the broad `*dep*` glob and D1 must go back to passing a
# deployment note off as a security scan.
M1="$(newtmp)"; cp -R "$REPO_ROOT/scripts" "$M1/scripts"
m1_meta=$(_mutate "$M1/scripts/check-maintenance.sh" '# BL-222-DEP-GLOB' "  _dep_glob='docs/test-results/*dep*'")
m1_sites="${m1_meta%% *}"; m1_rest="${m1_meta#* }"; m1_changed="${m1_rest%% *}"; m1_parses="${m1_rest##* }"
d="$(newtmp)"; mk_base "$d/p"
printf 'we deployed on tuesday\n' > "$d/p/docs/test-results/deployment-notes-$(days_ago 3).md"
run_check "$M1/scripts" "$d/p"
if [ "$m1_sites" -eq 1 ] && [ "$m1_parses" -eq 1 ] && [ "$CHK_RC" -eq 0 ]; then
  pass "M1: with the broad '*dep*' glob restored, a deployment note satisfies the security clock again (rc 0 where the repaired tree answers 2) — the narrowing is load-bearing (sites=$m1_sites changed=$m1_changed parses=$m1_parses)"
else
  fail_ "M1" "sites=$m1_sites (want 1) parses=$m1_parses (want 1) changed=$m1_changed rc=$CHK_RC (want 0)"
fi

# ── M2: remove the round-trip date check and D5 must go back to being decided
# by whichever date(1) is installed.
M2="$(newtmp)"; cp -R "$REPO_ROOT/scripts" "$M2/scripts"
m2_meta=$(_mutate "$M2/scripts/check-maintenance.sh" '# BL-222-DATE-ROUNDTRIP' '  :')
m2_sites="${m2_meta%% *}"; m2_rest="${m2_meta#* }"; m2_changed="${m2_rest%% *}"; m2_parses="${m2_rest##* }"
d="$(newtmp)"; mk_base "$d/p"
printf 'scan\n' > "$d/p/docs/test-results/2026-02-30_semgrep_pass.txt"
run_check "$M2/scripts" "$d/p"
# The discriminator is rc 2 vs ANY MEASURED verdict, not rc 2 vs rc 0.
# 2026-02-30 normalises to March 2, which is far enough in the past to read as
# OVERDUE rather than current — so the mutant answers rc 1 here. That is still
# decisive, and it is the sharper statement of the defect: the mutant does not
# merely mis-date the artefact, it FABRICATES A MEASUREMENT from a date that
# does not exist, where the repaired tree says it cannot measure at all (rc 2,
# proven by D5). Asserted this way the proof is also immune to calendar drift:
# a hardcoded impossible date would wander in and out of the 95-day window as
# the real date moves, and this suite would start failing for the wrong reason.
m2_measured=no
[ "$CHK_RC" -ne 2 ] && m2_measured=yes
if [ "$m2_sites" -eq 1 ] && [ "$m2_parses" -eq 1 ] && [ "$m2_measured" = "yes" ]; then
  pass "M2: with the round-trip removed, this host turns 2026-02-30 into a real measurement (rc $CHK_RC) where the repaired tree refuses to measure at all (rc 2) — a date that does not exist becomes a security verdict (sites=$m2_sites changed=$m2_changed parses=$m2_parses)"
else
  fail_ "M2" "sites=$m2_sites (want 1) parses=$m2_parses (want 1) changed=$m2_changed rc=$CHK_RC (want anything but 2) — NOTE: on a GNU-date host this mutant cannot fire at all, because GNU refuses 2026-02-30 outright. That is a real limit of this proof and not a pass"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
