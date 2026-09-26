#!/usr/bin/env bash
# tests/test-brownfield-wp7e-ci-carveout.sh — WP7: the CI carve-out (§7.4).
#
# SPEC: ADOPT-002-ARCH v1 §7.4, carried unchanged by v2 §7.4 — their pipelines
# are audited, never archived or touched; the framework's CI installs as its
# OWN file; SDLC-undermining workflows get loud findings; keep-or-retire is the
# operator's recorded decision. Backlog: `## BL-242:`.
#
# WHAT EACH CASE OWNS.
#   C1  a GitHub project: the framework's CI lands at its OWN name, committed,
#       and every workflow of theirs is byte-identical afterwards
#   C2  the four detector rules each fire on their spelling, report a LINE
#       NUMBER, and never print the line's text
#   C3  the answer is recorded: keep and retire both reach the Adoption Record
#   C4  a clean workflow asks nothing; a commented-out rule does not fire
#   C5  a GitLab project: `.gitlab-ci.yml` byte-identical, `.gitlab-ci-solo.yml`
#       written, and the run prints the include line — because it does not run
#       until the operator adds it
#   C6  a file already at the framework's own name is left alone and named
#   C7  a project with no CI host gets no framework CI, and is told so
#   C8  an unanswered keep-or-retire question refuses before any write, and
#       the refusal is THAT question's
#   C9  a symlinked .github/workflows is read and never written through
#   C10 a file that cannot be read is reported as unread, never as clean
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

echo "== WP7 — the CI carve-out =="

for t in git jq; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done

WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT

_base() {   # _base DIR — a project with its own history
  local p="$1"
  mkdir -p "$p/src" || return 1
  ( cd "$p" && git init -q . && git config user.email wp7e@test.invalid && git config user.name "WP7e Test" ) >/dev/null 2>&1 || return 1
  printf '{"name":"acme","scripts":{"test":"exit 0"}}\n' > "$p/package.json"
  printf 'export const x = 1;\n' > "$p/src/index.ts"
  printf '# acme\n' > "$p/README.md"
}
_commit() { ( cd "$1" && git add -- "${@:2}" && git commit -q --no-verify -m "chore: their history" ) >/dev/null 2>&1; }
_run() {    # _run DIR TAG ANSWERS... — sets RUN_RC
  local p="$1" tag="$2"; shift 2
  printf '%s\n' "$@" > "$WORK/ans-$tag"
  ( cd "$p" && bash "$REPO_ROOT/scripts/adopt-project.sh" < "$WORK/ans-$tag" ) \
    > "$WORK/$tag.out" 2> "$WORK/$tag.err"
  RUN_RC=$?
}
_sha() { shasum -a 256 "$1" 2>/dev/null | cut -c1-64; }

# ── G: GitHub, two workflows — one that trips every rule, one clean ─────────
G="$WORK/gh"
_base "$G"
mkdir -p "$G/.github/workflows"
cat > "$G/.github/workflows/release.yml" <<'Y'
name: release
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - run: npm test
        continue-on-error: true   # SECRET-LINE-TEXT-MARKER on a line a rule REPORTS
      - run: gh pr merge 12 --auto --squash
      - run: git push --force origin main
      - run: ./deploy.sh
  # - run: git filter-branch   (a comment: must not fire)
Y
cat > "$G/.github/workflows/lint.yml" <<'Y'
name: lint
on: pull_request
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: npm run lint
Y
_commit "$G" package.json src/index.ts README.md .github/workflows/release.yml .github/workflows/lint.yml
SHA_REL="$(_sha "$G/.github/workflows/release.yml")"; SHA_LINT="$(_sha "$G/.github/workflows/lint.yml")"
# The tier, then ONE keep-or-retire (release.yml; lint.yml is clean), then the
# intake's confirmations — ten of them, because how many the intake asks
# depends on the environment and unread answers are harmless.
_run "$G" gh 1 2 1 1 1 1 1 1 1 1 1 1
GRC=$RUN_RC

c1() {
  local label="C1 GitHub: framework CI at its OWN name, committed; their workflows byte-identical" bad=""
  [ "$GRC" -eq 0 ] || { fail_ "$label" "rc $GRC: $(grep -E 'BLOCKED|REFUSED' "$WORK/gh.out" "$WORK/gh.err" | head -2 | tr '\n' ' ')"; return; }
  [ -s "$G/.github/workflows/solo-gates.yml" ] || bad="$bad [no .github/workflows/solo-gates.yml]"
  cmp -s "$G/.github/workflows/solo-gates.yml" "$REPO_ROOT/templates/pipelines/ci/github/typescript.yml" \
    || bad="$bad [solo-gates.yml is not the framework's typescript template]"
  ( cd "$G" && git ls-files --error-unmatch .github/workflows/solo-gates.yml ) >/dev/null 2>&1 || bad="$bad [not committed]"
  [ "$(_sha "$G/.github/workflows/release.yml")" = "$SHA_REL" ] || bad="$bad [release.yml changed]"
  [ "$(_sha "$G/.github/workflows/lint.yml")" = "$SHA_LINT" ] || bad="$bad [lint.yml changed]"
  [ ! -e "$G/.github/workflows/ci.yml" ] || bad="$bad [the canonical ci.yml was written]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

c2() {
  local label="C2 all four rules fire with a line number, and the line's text is never printed" bad="" r
  for r in 'auto-merge' 'force-push or history rewrite' 'a failing step is allowed to pass' 'deploys on a branch push'; do
    grep -qE "line [0-9]+  $r" "$WORK/gh.out" || bad="$bad [rule not reported: $r]"
  done
  grep -q 'SECRET-LINE-TEXT-MARKER' "$WORK/gh.out" "$WORK/gh.err" "$G/APPROVAL_LOG.md" && bad="$bad [a workflow line's text was printed or recorded]"
  # BY LINE NUMBER: the report prints numbers, never text, so a grep for the
  # commented-out command's words could never see it fire.
  local cl
  cl="$(grep -n 'filter-branch' "$G/.github/workflows/release.yml" | cut -d: -f1)"
  [ -n "$cl" ] || bad="$bad [fixture: no commented-out line]"
  grep -qE "line $cl  " "$WORK/gh.out" && bad="$bad [the commented-out line $cl fired]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

c3() {
  local label="C3 the keep-or-retire answer is in the Adoption Record" bad=""
  grep -qE '^    \| \.github/workflows/release\.yml \| .*retire' "$G/APPROVAL_LOG.md" || bad="$bad [release.yml's 'retire' is not recorded]"
  grep -q 'solo-gates.yml' "$G/APPROVAL_LOG.md" || bad="$bad [the record does not name the framework's CI file]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

c4() {
  local label="C4 a clean workflow asks nothing (one question for two files)" n
  n="$(grep -c 'Keep .* as it is, or will you retire it' "$WORK/gh.out")"
  [ "$n" -eq 1 ] && pass "$label" || fail_ "$label" "$n keep-or-retire question(s), not 1"
}

c5() {
  local label="C5 GitLab: theirs byte-identical, .gitlab-ci-solo.yml written, and the include line printed" bad="" p="$WORK/gl" sha
  _base "$p"
  printf 'stages: [test]\ntest:\n  script: npm test\n' > "$p/.gitlab-ci.yml"
  _commit "$p" package.json src/index.ts README.md .gitlab-ci.yml
  sha="$(_sha "$p/.gitlab-ci.yml")"
  _run "$p" gl 1 1 1 1 1 1 1 1 1 1 1
  [ "$RUN_RC" -eq 0 ] || { fail_ "$label" "rc $RUN_RC"; return; }
  [ "$(_sha "$p/.gitlab-ci.yml")" = "$sha" ] || bad="$bad [.gitlab-ci.yml changed]"
  cmp -s "$p/.gitlab-ci-solo.yml" "$REPO_ROOT/templates/pipelines/ci/gitlab/typescript.yml" || bad="$bad [.gitlab-ci-solo.yml is not the gitlab template]"
  grep -q "local: '.gitlab-ci-solo.yml'" "$WORK/gl.out" || bad="$bad [the include line was not printed]"
  grep -q 'IT DOES NOT RUN YET' "$WORK/gl.out" || bad="$bad [the run did not say the file does not run yet]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

c6() {
  local label="C6 a file already at the framework's own name is left alone and named" bad="" p="$WORK/own" 
  _base "$p"
  mkdir -p "$p/.github/workflows"
  printf 'name: theirs\non: pull_request\njobs: {}\n# THEIR-SOLO-GATES\n' > "$p/.github/workflows/solo-gates.yml"
  _commit "$p" package.json src/index.ts README.md .github/workflows/solo-gates.yml
  _run "$p" own 1 1 1 1 1 1 1 1 1 1 1
  [ "$RUN_RC" -eq 0 ] || { fail_ "$label" "rc $RUN_RC"; return; }
  grep -q 'THEIR-SOLO-GATES' "$p/.github/workflows/solo-gates.yml" || bad="$bad [their file was overwritten]"
  grep -q 'solo-gates.yml already exists' "$WORK/own.out" || bad="$bad [the run did not say so]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

c7() {
  local label="C7 no CI host: no framework CI, and the run says so" bad="" p="$WORK/nohost"
  _base "$p"
  _commit "$p" package.json src/index.ts README.md
  _run "$p" nohost 1 1 1 1 1 1 1 1 1 1 1
  [ "$RUN_RC" -eq 0 ] || { fail_ "$label" "rc $RUN_RC"; return; }
  [ ! -e "$p/.github/workflows/solo-gates.yml" ] && [ ! -e "$p/.gitlab-ci-solo.yml" ] || bad="$bad [a framework CI file was written with no host]"
  grep -q 'No framework CI was laid down' "$WORK/nohost.out" || bad="$bad [the run did not say so]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

c8() {
  local label="C8 an unanswered keep-or-retire refuses before any write" bad="" p="$WORK/unanswered" before
  _base "$p"
  mkdir -p "$p/.github/workflows"
  printf 'on: push\njobs:\n  t:\n    steps:\n      - run: x\n        continue-on-error: true\n' > "$p/.github/workflows/t.yml"
  _commit "$p" package.json src/index.ts README.md .github/workflows/t.yml
  before="$(cd "$p" && git rev-parse HEAD)"
  # The tier and nothing else: the keep-or-retire question finds no answer.
  _run "$p" unanswered 1
  [ "$RUN_RC" -ne 0 ] || bad="$bad [rc 0 with the question unanswered]"
  [ "$(cd "$p" && git rev-parse HEAD)" = "$before" ] || bad="$bad [a commit landed]"
  [ -z "$(cd "$p" && git status --porcelain)" ] || bad="$bad [files were written]"
  # BY NAME: an answer file that simply runs out would also refuse — at the
  # intake — so rc alone cannot tell this question's refusal from a later one.
  grep -q 'no answer was given: what happens to .github/workflows/t.yml' "$WORK/unanswered.out" "$WORK/unanswered.err" \
    || bad="$bad [the refusal is not the keep-or-retire question's]"
  # AND IT STOPPED THERE: a refusal that is printed and then carried past
  # still names the question — the run only fails later, at the intake.
  grep -q '══ The interview' "$WORK/unanswered.out" && bad="$bad [the run carried on past the unanswered question into the intake]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

c9() {
  local label="C9 a symlinked .github/workflows: read, and nothing written through it" bad="" p="$WORK/linked" out="$WORK/outside-workflows" before
  _base "$p"
  mkdir -p "$out" "$p/.github"
  printf 'on: pull_request\njobs:\n  t:\n    steps:\n      - run: npm test\n' > "$out/theirs.yml"
  _commit "$p" package.json src/index.ts README.md
  ln -s "$out" "$p/.github/workflows"
  before="$(ls -A "$out" | tr '\n' ' ')"
  _run "$p" linked 1 1 1 1 1 1 1 1 1 1 1
  [ "$RUN_RC" -eq 0 ] || { fail_ "$label" "rc $RUN_RC: $(grep -E 'BLOCKED|REFUSED' "$WORK/linked.out" "$WORK/linked.err" | head -2 | tr '\n' ' ')"; return; }
  [ "$(ls -A "$out" | tr '\n' ' ')" = "$before" ] || bad="$bad [a file was written into the folder the link points at: $(ls -A "$out" | tr '\n' ' ')]"
  grep -q 'was NOT written: its folder is a symlink' "$WORK/linked.out" || bad="$bad [the run did not say it was not written]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

c10() {
  local label="C10 a Latin-1 byte does not blind the rules; a file that cannot be read is NEVER reported clean" bad="" p="$WORK/latin" u="$WORK/unread" w="$WORK/unread-work"
  # (a) A REAL RUN: a Latin-1 first line, then a force-push. macOS awk under a
  #     UTF-8 locale aborted on the byte and the file read as clean (review).
  _base "$p"
  mkdir -p "$p/.github/workflows"
  printf '# D\xe9ploiement\non: pull_request\njobs:\n  x:\n    steps:\n      - run: git push --force\n' > "$p/.github/workflows/latin.yml"
  _commit "$p" package.json src/index.ts README.md .github/workflows/latin.yml
  ( cd "$p" && printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n' | LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 bash "$REPO_ROOT/scripts/adopt-project.sh" ) > "$WORK/latin.out" 2> "$WORK/latin.err"
  [ "$?" -eq 0 ] || bad="$bad [the Latin-1 adoption did not complete: $(grep -E 'BLOCKED|REFUSED' "$WORK/latin.out" "$WORK/latin.err" | head -1)]"
  grep -qE 'line [0-9]+  force-push' "$WORK/latin.out" || bad="$bad [the force-push behind a Latin-1 byte was not reported]"
  # (b) THE AUDIT ITSELF on an unreadable file. A full adoption cannot reach
  #     this — the rehearsal's copy refuses an unreadable file first — so the
  #     arm is driven directly: it must say "could NOT be read" and record it,
  #     never report the file clean.
  if [ "$(id -u)" -ne 0 ]; then
    mkdir -p "$u/.github/workflows" "$w"
    printf 'on: pull_request\n' > "$u/.github/workflows/locked.yml"
    chmod 000 "$u/.github/workflows/locked.yml"
    ( set +u
      for l in adopt-core adopt-ci; do . "$REPO_ROOT/scripts/lib/adopt/$l.sh" >/dev/null 2>&1; done
      ADOPT_WORK="$w"
      adopt_ci_audit "$u" ) > "$WORK/unread.out" 2>&1
    chmod 644 "$u/.github/workflows/locked.yml"
    grep -q 'locked.yml — could NOT be read' "$WORK/unread.out" || bad="$bad [the unreadable file was not named as unread]"
    grep -q 'none matched a known way' "$WORK/unread.out" && bad="$bad [the audit called an unread file clean]"
    grep -qF "$(printf '.github/workflows/locked.yml\tcould not be read\tnot asked')" "$w/ci-decisions.tsv" 2>/dev/null \
      || bad="$bad [the unread file is not in what the record reads]"
  fi
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

c1; c2; c3; c4; c5; c6; c7; c8; c9; c10

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
