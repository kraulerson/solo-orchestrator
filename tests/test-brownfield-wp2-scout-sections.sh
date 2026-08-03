#!/usr/bin/env bash
# tests/test-brownfield-wp2-scout-sections.sh — behaviour suite for Scout's
# remaining four report sections: secrets, collisions, testsBaseline,
# intakePrefill (WP2-brownfield).
#
# SPEC: docs/designs/2026-08-02-brownfield-adoption-v1.md — §6.1 (scope: full
# history when it is a repo), §6.2 (REDACTION IS A PROJECTION, NOT A FLAG — the
# field allowlist table is normative), §6.5 (the planted-secret test and its two
# BASE32 fixture facts), §1.2 (the twelve-row collision surface), §7.1 (the four
# buckets), §7.2 (the shallow hook description), §7.4 (the SDLC-undermining
# detector rules, report-only), §8.2 (the schema), §8.3 (scan-derived /
# judgment / non-skippable), §10-WP2, §13-V3 (the executed gitleaks evidence).
#
# ─────────────────────────────────────────────────────────────────────────────
# WHAT THIS SUITE IS PROTECTING, IN ONE SENTENCE
#
# Every artifact Scout writes is built by an explicit field ALLOWLIST — never a
# passthrough, never a denylist — and this suite proves it with REAL PLANTED
# SECRETS asserted absent from every byte written.
#
# WP2 is the package where a defect is worst (§10's own words): its failure mode
# is a leaked credential in a committed file, and §0.3-C7 proves the obvious
# implementation has exactly that bug.
#
# ─────────────────────────────────────────────────────────────────────────────
# THE THREE PLANTS, AND WHY EACH ONE IS SHAPED THE WAY IT IS
#
#   DIFF_PLANT  AKIAQZ7X4M2NPLKJ3HRD  — added by commit 1's diff.
#   CARRIER     AKIA5DPR7HW6TSNQ2FUX  — added by commit 2's diff.
#   MSG_PLANT   AKIAVX3T6QW2ZLMK4RBS  — ONLY in commit 2's commit MESSAGE.
#
# All three match `AKIA[A-Z2-7]{16}`. BASE32-VALIDITY IS LOAD-BEARING (§6.5):
# the `aws-access-token` rule requires the 16 characters after `AKIA` to be
# drawn from [A-Z2-7], so a plant containing a `9` yields ZERO findings and
# makes the whole proof vacuous — the design's own v1.0 shipped that dud.
# `AKIAIOSFODNN7EXAMPLE` is separately allowlisted by gitleaks' default config
# and also yields zero. G0 asserts a NON-ZERO finding count BEFORE anything
# else, so a dud fixture fails loudly instead of certifying nothing.
#
# WHY THE CARRIER EXISTS — MEASURED ON THIS HOST, NOT ASSUMED. §13-V3 records
# that `gitleaks git` scans diffs, not commit messages: a BASE32-valid key
# present only in a message yields zero findings. What that leaves unsaid, and
# what an implementer discovers the expensive way, is that the `Message` field
# of a finding is the message of the commit THAT PRODUCED THAT FINDING. A
# message plant on a commit whose diff is clean is therefore invisible even
# under a full report passthrough — Mutation B would go green against a
# correct implementation and against a broken one alike. The CARRIER key puts a
# real finding on the same commit as MSG_PLANT, which is what makes that
# commit's message reach the report at all. Verified against gitleaks 8.30.1:
# redacted report -> DIFF_PLANT x0, CARRIER x0, MSG_PLANT x1 (in `Message`).
#
# A FOURTH PLANT lives in the fixture's `.git/hooks/pre-commit` (HOOK_PLANT).
# §7.2 requires a what-it-invokes description for every archived git hook, and
# §7.3 names the hazard in as many words: a hand-rolled hook can contain a
# token. The description generator therefore emits ONLY names drawn from a
# fixed tool vocabulary — the §6.2 doctrine generalised — and C3 proves it by
# planting a secret in the hook and asserting the bytes.
#
# ─────────────────────────────────────────────────────────────────────────────
# THE MUTATIONS. §10-WP2 names two; this suite runs three, because a single
# one-line neuter CANNOT expose the diff plant against a correct build, and
# saying so is more useful than shipping a mutation that passes vacuously.
#
#   XA1  drop `--redact` ALONE              -> the raw plant reaches the TOOL
#                                              report, and Scout's artifacts
#                                              STAY CLEAN. Layer 2 holds.
#   XA2  add Secret/Match to the allowlist   -> a `secret` key appears in the
#        ALONE                                 artifact carrying `REDACTED`,
#                                              never the plant. Layer 1 holds.
#   XA   BOTH lines at once                  -> THE DIFF PLANT APPEARS -> RED.
#   XB   allowlist -> report passthrough     -> THE MESSAGE PLANT APPEARS ->
#        (ONE line)                            RED. **The one that matters.**
#
# XA1 and XA2 are not padding: together they are the executable statement of
# §6.2's claim that `--redact` is NECESSARY AND NOT SUFFICIENT. XB needs no
# such pairing because the allowlist is the only thing standing between the
# `Message` field and the artifact — `--redact` does not touch `Message`, which
# is C7 in one line.
#
# ─────────────────────────────────────────────────────────────────────────────
# EXIT CODES AND VALUES, NEVER LABELS (CLAUDE.md's [WARN] trap). Every
# assertion reads an exit code, a jq-extracted JSON value, a byte grep, or a
# tree hash.
#
# GITLEAKS IS DETECTED, NEVER ASSUMED — and a skip is LOUD. If gitleaks is not
# installed, the planted-secret cases are skipped with a SKIPPED tally that
# prints its own banner and is repeated in the final line. A silently-skipped
# planted-secret proof is the silent-success defect class aimed at the one
# assertion in this repository that most needs to be visible.
#
# HERMETICITY: every fixture is a `mktemp -d` tree; no network, no host CLI, no
# real remote. bash-3.2 safe: no associative arrays, no `${var,,}`, no
# `mapfile`, no `((x++))`.
#
# LANE: registered in tests/full-project-test-suite.sh AND in the
# .github/workflows/tests.yml `unit-shard` list. This suite never mentions,
# copies or executes the scaffolder, so it is a unit-lane test outright and
# must NOT appear in `lint-tests-registered.sh --list | grep unit-lane-exempt`.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCOUT="$REPO_ROOT/scripts/scout.sh"
SCOUT_LIB="$REPO_ROOT/scripts/lib/scout"
WIZARD="$REPO_ROOT/scripts/intake-wizard.sh"

PASSED=0
FAILED=0
SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip_() { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for tests/test-brownfield-wp2-scout-sections.sh" >&2
  exit 2
fi

HAVE_GITLEAKS=0
command -v gitleaks >/dev/null 2>&1 && HAVE_GITLEAKS=1

# GITLEAKS-ABSENT IS A SKIP LOCALLY AND A FAILURE IN CI (R-WP2-1).
#
# The original posture — detect and skip, loudly — was the brief's, and it
# produced a hole the review found: the runner image does not ship gitleaks and
# no workflow installed it, so the §6.5 byte-absence proof and all four
# mutation proofs skipped in BOTH lanes and the suite still exited 0. A green
# required check, credited with a proof that never ran, guarding the property
# whose failure mode is a leaked credential in a committed file.
#
# A loud log line does not gate a merge; an exit code does. So the two audiences
# are separated. A developer without gitleaks gets a banner and a skip, because
# failing their local run for a missing optional tool teaches them to ignore the
# suite. CI gets a FAILURE, because CI is the only place the skip is invisible —
# nobody reads a green check's log. `CI` is set by GitHub Actions (and by every
# other major provider) and the workflows now install a pinned gitleaks, so this
# arm fires only if that install is removed or breaks.
GITLEAKS_ABSENT_IS_FATAL=0
[ -n "${CI:-}" ] && GITLEAKS_ABSENT_IS_FATAL=1

TMPS=""
cleanup() { [ -n "$TMPS" ] && rm -rf $TMPS; return 0; }
trap cleanup EXIT
newtmp() { local d; d=$(mktemp -d); TMPS="$TMPS $d"; printf '%s\n' "$d"; }

# ── The plants ──────────────────────────────────────────────────────────────
# Assembled from halves so that this source file does not itself carry a
# 20-character AKIA-shaped literal that a secret scanner pointed at THIS
# repository would report. The halves are inert; the join is what matches.
DIFF_PLANT="AKIAQZ7X4M2N""PLKJ3HRD"
CARRIER="AKIA5DPR7HW6""TSNQ2FUX"
MSG_PLANT="AKIAVX3T6QW2""ZLMK4RBS"
HOOK_PLANT="AKIA7YB4XM3Q""RVUC6KDN"

# ── Portable primitives (house pattern, WP1 parity) ─────────────────────────

_md5file()  { if command -v md5 >/dev/null 2>&1; then md5 -q "$1"; else md5sum "$1" | awk '{print $1}'; fi; }
_md5stdin() { if command -v md5 >/dev/null 2>&1; then md5 -q; else md5sum | awk '{print $1}'; fi; }
_mode_of()  { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || echo "?"; }

# _tree_manifest DIR — one line per filesystem entry: <relpath>|<type>|<mode>[|<md5>]
# `.git/` INCLUDED on purpose: a scanner that "only" refreshed an index would
# still have written to the operator's repository.
_tree_manifest() {
  ( cd "$1" 2>/dev/null || return 1
    find . -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r p; do
      if [ -L "$p" ];   then printf '%s|L|%s\n' "$p" "$(readlink "$p" 2>/dev/null)"
      elif [ -d "$p" ]; then printf '%s|D|%s\n' "$p" "$(_mode_of "$p")"
      elif [ -f "$p" ]; then printf '%s|F|%s|%s\n' "$p" "$(_mode_of "$p")" "$(_md5file "$p")"
      else                   printf '%s|O|-\n' "$p"
      fi
    done )
}
_tree_hash() { _tree_manifest "$1" | _md5stdin; }

# _awk_inplace FILE AWK-PROGRAM — in-place awk PRESERVING the file's mode. The
# obvious spelling ends in `chmod +x`, which silently widens a 0644 lib to 0755
# and rides along in the next commit.
_awk_inplace() {
  local file="$1" prog="$2" tmp mode
  mode="$(_mode_of "$file")"
  tmp="$(mktemp)"
  awk "$prog" "$file" > "$tmp" && mv "$tmp" "$file"
  [ "$mode" != "?" ] && chmod "$mode" "$file" 2>/dev/null
  return 0
}

# _changed_lines A B — lines diff reports added or removed. A one-line
# SUBSTITUTION is 2. Asserting it stops a mutation from becoming a rewrite and
# stops a NO-OP edit from being read as a proof.
_changed_lines() {
  local n
  n=$(diff "$1" "$2" 2>/dev/null | grep -c '^[<>]')
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s\n' "$n"
}

# mk_scout_copy DIR — Scout, and only Scout, at its real relative paths.
mk_scout_copy() {
  local d="$1"
  mkdir -p "$d/scripts/lib/scout"
  cp "$SCOUT" "$d/scripts/scout.sh"
  cp "$SCOUT_LIB"/*.sh "$d/scripts/lib/scout/"
  chmod +x "$d/scripts/scout.sh"
}

# _num VALUE — a shell-comparable integer. jq prints the JSON literal `null`
# as the four-character string "null", which `[ "$x" -ge 1 ]` rejects with
# `integer expression expected` — a diagnostic on stderr and a FALSE branch, so
# a missing field silently takes the same path as a zero. Normalise once, here.
_num() {
  case "$1" in ''|null|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac
}

# _grep_tree_for DIR NEEDLE — how many FILES under DIR contain NEEDLE.
# Binary-safe (`-r` with `-l`), and it counts files rather than lines so an
# artifact that repeats the string is still exactly one hit to explain.
_grep_tree_for() {
  local n
  n=$(grep -rl -- "$2" "$1" 2>/dev/null | grep -c '')
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s\n' "$n"
}

# ── Fixtures ────────────────────────────────────────────────────────────────

# THE PLANTED-SECRET FIXTURE (§6.5). Two commits:
#   c1  diff introduces DIFF_PLANT     message: "add config"
#   c2  diff introduces CARRIER        message: "rotate key, old one was <MSG_PLANT>"
# c2's finding is what carries c2's message into the report. Without it the
# message plant never appears even under a full passthrough — see the header.
# The working tree is CLEAN of DIFF_PLANT, so only a history scan can find it,
# which is also §6.1's full-history claim under test.
mk_secret_fixture() {
  local d="$1"
  ( cd "$d" && unset GITHUB_BASE_REF
    git init -q .
    git config user.email t@t.local
    git config user.name T
    printf 'aws_key = %s\n' "$DIFF_PLANT" > config.ini
    git add -A && git commit -q -m "add config"
    printf 'aws_key = ROTATED\n' > config.ini
    printf 'deploy_key = %s\n' "$CARRIER" > deploy.ini
    git add -A && git commit -q -m "rotate key, old one was $MSG_PLANT" ) >/dev/null 2>&1
  # HOOK_PLANT: §7.3's named hazard, in the one file the archive would promote
  # from untracked into version control.
  printf '#!/bin/sh\nexport AWS_KEY=%s\nnpx lint-staged\nnpm test -- --bail\n' \
    "$HOOK_PLANT" > "$d/.git/hooks/pre-commit"
  chmod +x "$d/.git/hooks/pre-commit"
}

# A repository with no secrets at all — the discriminator for "scanned and
# clean" against "not scanned" and against "tool unavailable".
mk_clean_repo_fixture() {
  local d="$1"
  ( cd "$d" && unset GITHUB_BASE_REF
    git init -q .
    git config user.email t@t.local
    git config user.name T
    printf 'hello\n' > a.txt
    git add -A && git commit -q -m "clean" ) >/dev/null 2>&1
}

# A NON-git directory carrying a plant in the working tree: §6.1's graceful
# degradation to `gitleaks dir`, and the scope field that must say so honestly.
mk_nongit_secret_fixture() {
  local d="$1"
  printf 'aws_key = %s\n' "$DIFF_PLANT" > "$d/config.ini"
}

# THE COLLISION FIXTURE — the §1.2 surfaces, in the shapes a real adoptee has.
#   husky-style .git/hooks/pre-commit          archive-and-replace
#   .git/hooks/commit-msg                      marker-composed
#   .claude/settings.json + settings.local.json archive-and-replace
#   .claude/skills/session-handoff/SKILL.md    archive-and-replace
#   .mcp.json                                  archive-and-replace
#   a FOREIGN .gitlab-ci.yml                   audit-only, never touched
#   .gitignore, CHANGELOG.md, FEATURES.md      keep-theirs / composed
#   .claude-backup/, uncommitted work
mk_collision_fixture() {
  local d="$1"
  mkdir -p "$d/.claude/skills/session-handoff" "$d/.claude-backup" "$d/src"
  ( cd "$d" && unset GITHUB_BASE_REF
    git init -q .
    git config user.email t@t.local
    git config user.name T
    printf 'console.log(1)\n' > src/a.js
    git add -A && git commit -q -m "initial" ) >/dev/null 2>&1
  printf '#!/bin/sh\n. "$(dirname "$0")/husky.sh"\nnpx lint-staged\n' > "$d/.git/hooks/pre-commit"
  chmod +x "$d/.git/hooks/pre-commit"
  printf '#!/bin/sh\nnpx commitlint --edit "$1"\n' > "$d/.git/hooks/commit-msg"
  chmod +x "$d/.git/hooks/commit-msg"
  printf '{"hooks":{}}\n' > "$d/.claude/settings.json"
  printf '{"mcpServers":{"qdrant":{}}}\n' > "$d/.claude/settings.local.json"
  printf '# Session handoff\n' > "$d/.claude/skills/session-handoff/SKILL.md"
  printf '{"mcpServers":{}}\n' > "$d/.mcp.json"
  printf 'stages:\n  - build\nbuild:\n  script:\n    - make all\n' > "$d/.gitlab-ci.yml"
  printf 'node_modules/\n' > "$d/.gitignore"
  printf '# Changelog\n\n## 1.0.0\n' > "$d/CHANGELOG.md"
  printf '# Features\n' > "$d/FEATURES.md"
  printf 'old settings\n' > "$d/.claude-backup/settings.json"
  # uncommitted work, which today is swept into a --no-verify commit
  printf 'console.log(2)\n' > "$d/src/b.js"
}

# THE SDLC-UNDERMINING WORKFLOW FIXTURE (§7.4) — one file per rule so a
# finding can never be credited to the wrong detector, plus a CLEAN workflow so
# the detectors are shown to discriminate rather than to fire on everything.
mk_ci_findings_fixture() {
  local d="$1"
  mkdir -p "$d/.github/workflows"
  printf 'name: clean\non:\n  pull_request:\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: npm test\n' \
    > "$d/.github/workflows/clean.yml"
  printf 'name: sec\non:\n  pull_request:\njobs:\n  scan:\n    runs-on: ubuntu-latest\n    steps:\n      - name: security scan\n        run: gitleaks detect\n        continue-on-error: true\n' \
    > "$d/.github/workflows/skip.yml"
  printf 'name: am\non:\n  pull_request:\njobs:\n  merge:\n    runs-on: ubuntu-latest\n    steps:\n      - run: gh pr merge --auto --squash\n' \
    > "$d/.github/workflows/automerge.yml"
  printf 'name: dep\non:\n  push:\n    branches: [main]\njobs:\n  deploy:\n    runs-on: ubuntu-latest\n    steps:\n      - run: ./deploy.sh production\n' \
    > "$d/.github/workflows/deploy.yml"
  printf 'name: rw\non:\n  workflow_dispatch:\njobs:\n  clean:\n    runs-on: ubuntu-latest\n    steps:\n      - run: git push --force origin main\n' \
    > "$d/.github/workflows/rewrite.yml"
}

# A node project with a REAL, trivially-runnable test command and a mixed
# source tree — five implementation files, one test file.
mk_tests_fixture() {
  local d="$1" i
  mkdir -p "$d/src" "$d/tests"
  cat > "$d/package.json" <<'EOF'
{
  "name": "acme-api",
  "version": "0.4.1",
  "scripts": { "test": "sh -c 'exit 0'" }
}
EOF
  printf 'lockfileVersion: 6.0\n' > "$d/pnpm-lock.yaml"
  i=1
  while [ "$i" -le 5 ]; do
    printf 'export const v%s = %s;\n' "$i" "$i" > "$d/src/mod$i.ts"
    i=$((i + 1))
  done
  printf "test('v1', () => {});\n" > "$d/tests/mod1.test.ts"
  printf '# acme-api\n\nBilling API.\n' > "$d/README.md"
}

# Same shape, but the declared test command FAILS. `commandRan` is about
# whether Scout ran it, never about whether it passed.
mk_failing_tests_fixture() {
  local d="$1"
  mkdir -p "$d/src"
  cat > "$d/package.json" <<'EOF'
{
  "name": "acme-red",
  "scripts": { "test": "sh -c 'exit 3'" }
}
EOF
  printf 'export const v = 1;\n' > "$d/src/mod.ts"
}

# A rust tree whose ONLY tests are inline — `# BL-107-RUST-INLINE-TESTS`
# parity. A path-only classifier calls every one of these untested.
mk_rust_fixture() {
  local d="$1"
  mkdir -p "$d/src"
  printf '[package]\nname = "acme"\n' > "$d/Cargo.toml"
  printf 'pub fn a() -> u8 { 1 }\n\n#[cfg(test)]\nmod tests {\n    #[test]\n    fn t() {}\n}\n' > "$d/src/lib.rs"
  printf 'pub fn b() -> u8 { 2 }\n' > "$d/src/plain.rs"
}

mk_bare_fixture() { printf 'hello\n' > "$1/notes.txt"; }

# ── Runners ─────────────────────────────────────────────────────────────────

scout_json() {
  local root="$1" entry="${2:-$SCOUT}"
  bash "$entry" --root "$root" </dev/null 2>/dev/null
}
jqv() { printf '%s' "$1" | jq -r "$2" 2>/dev/null; }

echo "== tests/test-brownfield-wp2-scout-sections.sh =="
echo ""
if [ "$HAVE_GITLEAKS" -eq 0 ]; then
  echo "  ***********************************************************************"
  echo "  *  gitleaks IS NOT INSTALLED ON THIS HOST.                            *"
  echo "  *  The PLANTED-SECRET PROOF (§6.5) and ALL FOUR mutation proofs       *"
  echo "  *  cannot run. A skipped planted-secret proof is NOT a passing build  *"
  echo "  *  — the secrets section is the highest-stakes surface in the design. *"
  echo "  *  Install it:  brew install gitleaks                                 *"
  echo "  ***********************************************************************"
  if [ "$GITLEAKS_ABSENT_IS_FATAL" -eq 1 ]; then
    echo "  *  CI IS SET, SO THIS IS A FAILURE, NOT A SKIP. The workflows install *"
    echo "  *  a pinned gitleaks precisely so this proof cannot sit out a merge.  *"
    echo "  *  If you are seeing this, that install step is gone or broken.       *"
    echo "  ***********************************************************************"
    fail_ "GITLEAKS MISSING IN CI" "the planted-secret proof and all four mutation proofs cannot run, and a green check that skipped them is exactly the silent success this suite exists to prevent"
  fi
  echo ""
fi

# ════════════════════════════════════════════════════════════════════════════
echo "=== G — the planted-secret proof (§6.5), the reason this suite exists ==="
# ════════════════════════════════════════════════════════════════════════════

SEC=$(newtmp);   mk_secret_fixture "$SEC"
CLEAN=$(newtmp); mk_clean_repo_fixture "$CLEAN"
NONGIT=$(newtmp); mk_nongit_secret_fixture "$NONGIT"

if [ "$HAVE_GITLEAKS" -eq 1 ]; then

  # ── G0: THE PRECONDITION, ASSERTED BEFORE ANYTHING ELSE ──────────────────
  # A dud plant yields zero findings, at which point every absence assertion
  # below passes for the wrong reason and Mutation A can never go RED. §6.5
  # names this precondition as non-optional and records that the design's own
  # v1.0 shipped exactly that dud. It is asserted FIRST, on purpose.
  G0OUT=$(newtmp)
  bash "$SCOUT" --root "$SEC" --out "$G0OUT" </dev/null >/dev/null 2>&1
  out=$(scout_json "$SEC")
  fc=$(jqv "$out" '.secrets.findingCount')
  st=$(jqv "$out" '.secrets.status')
  # And the fixture really does still hold the plants where we put them —
  # an absence proof over a fixture that lost its plants is worth nothing.
  hist_has_diff=$( ( cd "$SEC" && git log -p 2>/dev/null | grep -c -- "$DIFF_PLANT" ) )
  hist_has_msg=$( ( cd "$SEC" && git log 2>/dev/null | grep -c -- "$MSG_PLANT" ) )
  tree_has_diff=$(_grep_tree_for "$SEC" "$DIFF_PLANT")
  if [ "$(_num "$fc")" -ge 1 ] && [ "$st" = "scanned" ] \
     && [ "$(_num "$hist_has_diff")" -ge 1 ] && [ "$(_num "$hist_has_msg")" -ge 1 ]; then
    pass "G0 PRECONDITION: the BASE32-valid diff plant yields findingCount=$fc (non-zero) and both plants are live in the fixture's history"
  else
    fail_ "G0 PRECONDITION" "findingCount='$fc' (want >=1) status='$st' (want scanned) diff-plant-in-history=$hist_has_diff msg-plant-in-history=$hist_has_msg working-tree-files-with-diff-plant=$tree_has_diff — a dud plant makes every assertion below vacuous"
  fi

  # ── G1: NO PLANT STRING IN ANY BYTE OF ANY ARTIFACT ──────────────────────
  # The assertion §6.5 is written to produce. Scope: every file under the
  # output directory, and — because Scout stages its intermediate results in a
  # work directory — every file under a TMPDIR this case owns exclusively, read
  # AFTER Scout has exited and removed it. Temp residue is an artifact too.
  G1OUT=$(newtmp)
  G1TMP=$(newtmp)
  TMPDIR="$G1TMP" bash "$SCOUT" --root "$SEC" --out "$G1OUT" </dev/null >/dev/null 2>&1
  g1_rc=$?
  leak_report=""
  for plant_name in DIFF_PLANT CARRIER MSG_PLANT HOOK_PLANT; do
    eval "plant=\$$plant_name"
    n_out=$(_grep_tree_for "$G1OUT" "$plant")
    n_tmp=$(_grep_tree_for "$G1TMP" "$plant")
    [ "$n_out" -eq 0 ] || leak_report="$leak_report [$plant_name in $n_out output file(s)]"
    [ "$n_tmp" -eq 0 ] || leak_report="$leak_report [$plant_name in $n_tmp temp file(s)]"
  done
  artifacts=$( (cd "$G1OUT" && LC_ALL=C ls -1) | tr '\n' ' ')
  if [ -z "$leak_report" ] && [ "$g1_rc" -eq 0 ] \
     && [ -f "$G1OUT/scout-report.json" ] && [ -f "$G1OUT/scout-report.md" ]; then
    pass "G1: none of the four plants occurs in ANY byte of ANY artifact (json, markdown, temp residue); artifacts written: $artifacts"
  else
    fail_ "G1" "rc=$g1_rc artifacts='$artifacts' LEAKS:$leak_report"
  fi

  # ── G2: the finding object's keys ARE the §6.2 allowlist, exactly ────────
  # Structural, not a spot check: the emitted key set is compared to the
  # allowlist as a sorted string. An ADDED field fails this even if it happens
  # to be harmless, which is the point — §6.2's table is normative and the
  # schema HAS NO `secret` field to forget to strip.
  keys=$(jqv "$out" '[.secrets.findings[0] | keys[]] | sort | join(",")')
  want="commit,date,description,file,fingerprint,ruleId,startLine"
  banned=0
  for k in secret Secret match Match message Message author Author email Email entropy Entropy tags Tags; do
    printf '%s' "$out" | jq -e ".secrets.findings[0] | has(\"$k\")" >/dev/null 2>&1 && banned=1
  done
  if [ "$keys" = "$want" ] && [ "$banned" -eq 0 ]; then
    pass "G2: a finding carries EXACTLY the seven allowlisted fields ($want) and none of the fourteen refused ones"
  else
    fail_ "G2" "keys='$keys' want='$want' banned_field_present=$banned"
  fi

  # ── G3: scope is stated honestly, and differs by target ──────────────────
  # §6.1: `gitleaks git` walks history; a non-repo can only be scanned as a
  # directory, and a report that called that "full-history" would be a lie in
  # the direction of false confidence.
  scope_git=$(jqv "$out" '.secrets.scope')
  ng=$(scout_json "$NONGIT")
  scope_dir=$(jqv "$ng" '.secrets.scope')
  fc_dir=$(jqv "$ng" '.secrets.findingCount')
  # The history-only proof: DIFF_PLANT is absent from the working tree and
  # present in history, so a working-tree scan could not have found it.
  wt_hits=$(grep -rl -- "$DIFF_PLANT" "$SEC" --exclude-dir=.git 2>/dev/null | grep -c '')
  if [ "$scope_git" = "full-history" ] && [ "$scope_dir" = "working-tree-only" ] \
     && [ "${wt_hits:-1}" -eq 0 ] && [ "$(_num "$fc_dir")" -ge 1 ]; then
    pass "G3: a repo scans full-history (and finds a plant that exists ONLY in history); a non-repo degrades to working-tree-only and says so"
  else
    fail_ "G3" "repo scope='$scope_git' nonrepo scope='$scope_dir' working-tree-files-with-plant=$wt_hits (want 0) nonrepo findingCount='$fc_dir'"
  fi

  # ── G4: a clean repo is 'scanned' with 0, not confusable with 'unscanned' ─
  cl=$(scout_json "$CLEAN")
  cl_st=$(jqv "$cl" '.secrets.status')
  cl_fc=$(jqv "$cl" '.secrets.findingCount')
  cl_type=$(printf '%s' "$cl" | jq -r '.secrets.findings | type' 2>/dev/null)
  if [ "$cl_st" = "scanned" ] && [ "$cl_fc" = "0" ] && [ "$cl_type" = "array" ]; then
    pass "G4: a clean repository reports status=scanned, findingCount=0, findings=[] — a positive claim, not an absence"
  else
    fail_ "G4" "status='$cl_st' findingCount='$cl_fc' findings type='$cl_type'"
  fi

  # ── G5: the tool's version is recorded (§12-13's drift assumption) ───────
  tv=$(jqv "$out" '.secrets.toolVersion')
  fm=$(printf '%s' "$out" | jq -r '.secrets.fieldsMissing | type' 2>/dev/null)
  fmn=$(jqv "$out" '.secrets.fieldsMissing | length')
  if printf '%s' "$tv" | grep -Eq '^[0-9]+\.[0-9]+' && [ "$fm" = "array" ] && [ "$fmn" = "0" ]; then
    pass "G5: toolVersion='$tv' is recorded and fieldsMissing is an empty array — the allowlist found every field it names"
  else
    fail_ "G5" "toolVersion='$tv' fieldsMissing type='$fm' length='$fmn'"
  fi

else
  skip_ "G0-G5 (planted-secret proof)" "gitleaks not installed — see the banner above"
  skip_ "G1 byte assertion" "gitleaks not installed"
fi

# ── G6: version-drift is LOUD, not silent — a renamed field is REPORTED ────
# §12-13's assumption made testable: an allowlist fails SAFE on an added field
# (it is dropped) and must fail LOUD on a renamed one (it goes missing). The
# fixture is a hand-written report with `Fingerprint` renamed, fed through the
# projection directly, so the case runs with or without gitleaks installed.
if [ -f "$SCOUT_LIB/scout-secrets.sh" ]; then
  G6=$(newtmp)
  cat > "$G6/report.json" <<'EOF'
[
 {
  "RuleID": "aws-access-token",
  "Description": "AWS Access Token",
  "StartLine": 1,
  "Match": "REDACTED",
  "Secret": "REDACTED",
  "File": "config.ini",
  "Commit": "deadbeef",
  "Date": "2026-08-02T00:00:00Z",
  "Message": "irrelevant",
  "FingerprintV2": "deadbeef:config.ini:aws-access-token:1"
 }
]
EOF
  ( . "$SCOUT_LIB/scout-secrets.sh"
    _scout_secrets_project "$G6/report.json" "$G6" ) >/dev/null 2>&1
  missing=$(cat "$G6/secmissing" 2>/dev/null | tr '\n' ' ')
  nfind=$(cut -f1 < "$G6/secfields" 2>/dev/null | LC_ALL=C sort -u | grep -c '')
  if printf '%s' "$missing" | grep -q 'Fingerprint' && [ "${nfind:-0}" -eq 1 ]; then
    pass "G6: a RENAMED allowlisted field is reported in fieldsMissing ('$missing'), not silently dropped"
  else
    fail_ "G6" "fieldsMissing='$missing' (want Fingerprint) findings parsed=$nfind"
  fi

  # ── G7: an ADDED field is dropped silently and safely (the other half) ───
  cat > "$G6/added.json" <<'EOF'
[
 {
  "RuleID": "aws-access-token",
  "Description": "AWS Access Token",
  "StartLine": 1,
  "File": "config.ini",
  "Commit": "deadbeef",
  "Date": "2026-08-02T00:00:00Z",
  "Fingerprint": "deadbeef:config.ini:aws-access-token:1",
  "NewLeakyFieldGitleaksAdded": "SUPERSECRETVALUE",
  "Tags": ["a", "b"]
 }
]
EOF
  ( . "$SCOUT_LIB/scout-secrets.sh"
    _scout_secrets_project "$G6/added.json" "$G6" ) >/dev/null 2>&1
  leaked=$(grep -c 'SUPERSECRETVALUE' "$G6/secfields" 2>/dev/null)
  missing2=$(cat "$G6/secmissing" 2>/dev/null | tr '\n' ' ')
  if [ "${leaked:-1}" -eq 0 ] && [ -z "$(printf '%s' "$missing2" | tr -d ' ')" ]; then
    pass "G7: a field gitleaks ADDS in a future release is dropped by the allowlist and never reaches the projection"
  else
    fail_ "G7" "added-field occurrences in projection=$leaked (want 0) fieldsMissing='$missing2' (want empty)"
  fi
else
  fail_ "G6/G7" "scripts/lib/scout/scout-secrets.sh does not exist"
fi

# ── G8: gitleaks ABSENT is reported as tool-unavailable, never as clean ────
# The silent-success class, aimed at the one section where it matters most.
#
# THE SEAM IS SCOUT_GITLEAKS_BIN, AND THE COMMENT NOW SAYS SO (R-WP2-5). An
# earlier version of this case also built a PATH-stub gitleaks that nothing
# ever used, and described a "PATH_MASK" mechanism that was not the one being
# exercised — dead fixture code plus a comment about a test that did not run.
# The env seam hits the SAME predicate the real absence would (`command -v`
# against the configured name), which is what makes it a valid stand-in, and
# it does not require making the host's real gitleaks unreachable.
gl_out=$(SCOUT_GITLEAKS_BIN="definitely-not-a-real-binary-name" bash "$SCOUT" --root "$SEC" </dev/null 2>/dev/null)
gl_st=$(jqv "$gl_out" '.secrets.status')
gl_fc=$(jqv "$gl_out" '.secrets.findingCount')
gl_ft=$(printf '%s' "$gl_out" | jq -r '.secrets.findings | type' 2>/dev/null)
gl_rem=$(jqv "$gl_out" '.secrets.remediation')
if [ "$gl_st" = "tool-unavailable" ] && [ "$gl_fc" = "null" ] && [ "$gl_ft" = "null" ] \
   && [ -n "$gl_rem" ] && [ "$gl_rem" != "null" ]; then
  pass "G8: with the scanner unavailable, status=tool-unavailable, findingCount=null, findings=null (NOT []), and a remediation line is printed"
else
  fail_ "G8" "status='$gl_st' (want tool-unavailable) findingCount='$gl_fc' (want null) findings type='$gl_ft' (want null) remediation='$gl_rem'"
fi

# ── G9: a repo-local gitleaks config is DISCLOSED ─────────────────────────
# Measured on this host: a `.gitleaks.toml` with an allowlist regex reduces the
# two-plant fixture to ZERO findings. A report that printed "0 findings"
# without saying the project's own config was in force would be a clean bill of
# health issued by the thing being audited.
if [ "$HAVE_GITLEAKS" -eq 1 ]; then
  G9=$(newtmp); mk_secret_fixture "$G9"
  cat > "$G9/.gitleaks.toml" <<'EOF'
title = "suppress everything"
[allowlist]
regexes = ['''AKIA[A-Z2-7]{16}''']
EOF
  g9=$(scout_json "$G9")
  g9_cfg=$(jqv "$g9" '.secrets.configFile')
  g9_fc=$(jqv "$g9" '.secrets.findingCount')
  g9_note=$(jqv "$g9" '.secrets.configNote')
  if [ "$g9_cfg" = ".gitleaks.toml" ] && [ "$g9_fc" = "0" ] \
     && [ -n "$g9_note" ] && [ "$g9_note" != "null" ]; then
    pass "G9: the project's own .gitleaks.toml is disclosed alongside the (suppressed) count of $g9_fc, with a note"
  else
    fail_ "G9" "configFile='$g9_cfg' findingCount='$g9_fc' configNote='$g9_note'"
  fi
else
  skip_ "G9 (repo-local gitleaks config disclosure)" "gitleaks not installed"
fi

# ── G10: a CORRUPT report is scan-failed, never a clean read (R-WP2-3) ────
# The scan-failed arm used to key on `rc != 0 || report missing`, so a scanner
# that exited 0 having written garbage — the disk-full / truncated-write class
# — parsed to zero findings and was reported as `scanned` with a clean count.
# Against a fixture with two live plants in history. That is a false clean bill
# of health in the one section where the consequence is a credential, and it
# contradicts the file's own stated doctrine.
#
# Three shapes, because the first two failed DIFFERENTLY before the fix: braced
# garbage produced phantom findings and an all-seven `fieldsMissing`, while
# brace-free garbage and a bare `[` produced a completely silent clean read.
# The fourth run is the positive control that keeps the fix from being "call
# everything corrupt".
G10=$(newtmp)
_mk_fake_gitleaks() {
  cat > "$1" <<FAKEEOF
#!/bin/sh
# Emulates gitleaks: writes \$2 of the -r flag, exits 0.
out=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -r) out="\$2"; shift 2 ;;
    version) echo "9.9.9-fake"; exit 0 ;;
    *) shift ;;
  esac
done
[ -n "\$out" ] && printf '%s' '$2' > "\$out"
exit 0
FAKEEOF
  chmod +x "$1"
}
g10_fail=""
g10_n=0
for shape in 'this is not json' 'this is not json {{{' '[' '[]'; do
  g10_n=$((g10_n + 1))
  _mk_fake_gitleaks "$G10/fake$g10_n" "$shape"
  g10_out=$(SCOUT_GITLEAKS_BIN="$G10/fake$g10_n" bash "$SCOUT" --root "$SEC" </dev/null 2>/dev/null)
  g10_st=$(jqv "$g10_out" '.secrets.status')
  g10_fc=$(jqv "$g10_out" '.secrets.findingCount')
  if [ "$shape" = "[]" ]; then
    # The control: a VALID empty report is still a real, positive result.
    [ "$g10_st" = "scanned" ] && [ "$g10_fc" = "0" ] \
      || g10_fail="$g10_fail [valid-empty-report got status='$g10_st' count='$g10_fc', want scanned/0]"
  else
    [ "$g10_st" = "scan-failed" ] && [ "$g10_fc" = "null" ] \
      || g10_fail="$g10_fail [corrupt '$shape' got status='$g10_st' count='$g10_fc', want scan-failed/null]"
  fi
done
if [ -z "$g10_fail" ]; then
  pass "G10: three shapes of corrupt report (brace-free garbage, braced garbage, truncated '[') all report scan-failed with findingCount null; a valid empty report still reports scanned/0"
else
  fail_ "G10" "$g10_fail"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== X — the mutation proofs (§10-WP2), anchored and line-counted ==="
# ════════════════════════════════════════════════════════════════════════════

if [ "$HAVE_GITLEAKS" -eq 1 ]; then
  ORIG_SEC="$SCOUT_LIB/scout-secrets.sh"
  # Both anchors must resolve to exactly ONE EXECUTED line. WP1's X1 records
  # what happens otherwise: a marker-only anchor hit the header comment that
  # cites it and the mutant died on an unbound variable, reporting nothing at
  # all — an empty result is not a leak, and asserting on it proves nothing.
  redact_sites=$(grep -c '_flags=.*# SCOUT-SECRETS-REDACT' "$ORIG_SEC")
  allow_sites=$(grep -c '_SCOUT_SECRET_FIELDS=.*# SCOUT-SECRETS-ALLOWLIST' "$ORIG_SEC")

  # ── XA1: drop --redact ALONE -> layer 2 (the allowlist) still holds ──────
  XA1=$(newtmp); mk_scout_copy "$XA1"
  MUT="$XA1/scripts/lib/scout/scout-secrets.sh"
  _awk_inplace "$MUT" '
    { if (!done && index($0, "# SCOUT-SECRETS-REDACT") > 0 && index($0, "_flags=") > 0) {
        print "  _flags=\"--no-banner --exit-code 0\""
        done = 1; next }
      print }'
  chg_a1=$(_changed_lines "$ORIG_SEC" "$MUT")
  XA1OUT=$(newtmp)
  bash "$XA1/scripts/scout.sh" --root "$SEC" --out "$XA1OUT" </dev/null >/dev/null 2>&1
  a1_leak=$(_grep_tree_for "$XA1OUT" "$DIFF_PLANT")
  a1_fc=$(jqv "$(bash "$XA1/scripts/scout.sh" --root "$SEC" </dev/null 2>/dev/null)" '.secrets.findingCount')
  if [ "$chg_a1" -eq 2 ] && [ "$a1_leak" -eq 0 ] && [ "$(_num "$a1_fc")" -ge 1 ] && [ "$redact_sites" -eq 1 ]; then
    pass "XA1: with --redact DROPPED the artifacts are STILL clean (0 files carry the plant) — the field allowlist alone holds the line (§6.2: --redact is not sufficient, and it is not load-bearing either)"
  else
    fail_ "XA1" "changed_lines=$chg_a1 (want 2) files_leaking=$a1_leak (want 0) findingCount=$a1_fc (want >=1) redact_anchor_sites=$redact_sites (want 1)"
  fi

  # ── XA2: add Secret/Match to the allowlist ALONE -> layer 1 holds ────────
  XA2=$(newtmp); mk_scout_copy "$XA2"
  MUT="$XA2/scripts/lib/scout/scout-secrets.sh"
  _awk_inplace "$MUT" '
    { if (!done && index($0, "# SCOUT-SECRETS-ALLOWLIST") > 0 && index($0, "_SCOUT_SECRET_FIELDS=") > 0) {
        print "_SCOUT_SECRET_FIELDS=\"RuleID File Commit Fingerprint StartLine Date Description Secret Match\""
        done = 1; next }
      print }'
  chg_a2=$(_changed_lines "$ORIG_SEC" "$MUT")
  XA2OUT=$(newtmp)
  bash "$XA2/scripts/scout.sh" --root "$SEC" --out "$XA2OUT" </dev/null >/dev/null 2>&1
  a2_leak=$(_grep_tree_for "$XA2OUT" "$DIFF_PLANT")
  a2_has_secret=$(grep -c '"secret"' "$XA2OUT/scout-report.json" 2>/dev/null)
  if [ "$chg_a2" -eq 2 ] && [ "$a2_leak" -eq 0 ] && [ "${a2_has_secret:-0}" -ge 1 ] && [ "$allow_sites" -eq 1 ]; then
    pass "XA2: with Secret/Match ADDED to the allowlist a \`secret\` key does appear ($a2_has_secret occurrence(s)) but carries only REDACTED — --redact holds the line when the allowlist falls"
  else
    fail_ "XA2" "changed_lines=$chg_a2 (want 2) files_leaking=$a2_leak (want 0) secret_key_occurrences=$a2_has_secret (want >=1) allowlist_anchor_sites=$allow_sites (want 1)"
  fi

  # ── XA: BOTH layers down -> THE DIFF PLANT APPEARS -> RED ────────────────
  # §10-WP2's Mutation A. It is a TWO-line mutation and the suite says so
  # rather than pretending otherwise: measured against a correct build, NO
  # single-line neuter can expose the diff plant, because the two layers are
  # independent and either one alone suppresses it (XA1 and XA2 above are that
  # measurement). A one-line Mutation A here would pass vacuously — the exact
  # defect §6.5 exists to prevent, wearing a different hat.
  XA=$(newtmp); mk_scout_copy "$XA"
  MUT="$XA/scripts/lib/scout/scout-secrets.sh"
  _awk_inplace "$MUT" '
    { if (!done_r && index($0, "# SCOUT-SECRETS-REDACT") > 0 && index($0, "_flags=") > 0) {
        print "  _flags=\"--no-banner --exit-code 0\""
        done_r = 1; next }
      if (!done_a && index($0, "# SCOUT-SECRETS-ALLOWLIST") > 0 && index($0, "_SCOUT_SECRET_FIELDS=") > 0) {
        print "_SCOUT_SECRET_FIELDS=\"RuleID File Commit Fingerprint StartLine Date Description Secret Match\""
        done_a = 1; next }
      print }'
  chg_a=$(_changed_lines "$ORIG_SEC" "$MUT")
  XAOUT=$(newtmp)
  bash "$XA/scripts/scout.sh" --root "$SEC" --out "$XAOUT" </dev/null >/dev/null 2>&1
  a_leak=$(_grep_tree_for "$XAOUT" "$DIFF_PLANT")
  # The control: the same fixture, the UNMUTATED copy, in the same case, so a
  # red mutant can never be a fixture accident.
  XAC=$(newtmp); mk_scout_copy "$XAC"
  XACOUT=$(newtmp)
  bash "$XAC/scripts/scout.sh" --root "$SEC" --out "$XACOUT" </dev/null >/dev/null 2>&1
  a_ctl=$(_grep_tree_for "$XACOUT" "$DIFF_PLANT")
  if [ "$chg_a" -eq 4 ] && [ "$a_leak" -ge 1 ] && [ "$a_ctl" -eq 0 ]; then
    pass "XA (Mutation A): both layers neutered (2 substitutions, $chg_a diff lines) -> the DIFF plant appears in $a_leak artifact file(s); the unmutated control leaks 0"
  else
    fail_ "XA" "changed_lines=$chg_a (want 4) mutant_files_leaking=$a_leak (want >=1) control_files_leaking=$a_ctl (want 0)"
  fi

  # ── XB: THE ONE THAT MATTERS (C7) — allowlist -> report passthrough ──────
  # ONE line, --redact still ON, and the MESSAGE plant walks straight out. The
  # `Message` field is the full commit message and `--redact` does not touch
  # it; §13-V3 records that `gitleaks git` does not scan commit messages at
  # all, so no finding COUNT can ever reveal this and only an assertion on the
  # artifact's BYTES catches it. This is the mutation that separates a design
  # that redacts from a design that projects.
  XB=$(newtmp); mk_scout_copy "$XB"
  MUT="$XB/scripts/lib/scout/scout-secrets.sh"
  _awk_inplace "$MUT" '
    { if (!done && index($0, "# SCOUT-SECRETS-ALLOWLIST") > 0 && index($0, "_SCOUT_SECRET_FIELDS=") > 0) {
        print "_SCOUT_SECRET_FIELDS=\"RuleID Description StartLine EndLine StartColumn EndColumn Match Secret File SymlinkFile Commit Entropy Author Email Date Message Tags Fingerprint\""
        done = 1; next }
      print }'
  chg_b=$(_changed_lines "$ORIG_SEC" "$MUT")
  XBOUT=$(newtmp)
  bash "$XB/scripts/scout.sh" --root "$SEC" --out "$XBOUT" </dev/null >/dev/null 2>&1
  b_leak=$(_grep_tree_for "$XBOUT" "$MSG_PLANT")
  b_diff_leak=$(_grep_tree_for "$XBOUT" "$DIFF_PLANT")
  XBC=$(newtmp); mk_scout_copy "$XBC"
  XBCOUT=$(newtmp)
  bash "$XBC/scripts/scout.sh" --root "$SEC" --out "$XBCOUT" </dev/null >/dev/null 2>&1
  b_ctl=$(_grep_tree_for "$XBCOUT" "$MSG_PLANT")
  if [ "$chg_b" -eq 2 ] && [ "$b_leak" -ge 1 ] && [ "$b_ctl" -eq 0 ] \
     && [ "$b_diff_leak" -eq 0 ] && [ "$allow_sites" -eq 1 ]; then
    pass "XB (Mutation B, C7): ONE line — allowlist replaced by the tool's full 18-field report — leaks the MESSAGE plant into $b_leak artifact file(s) with --redact still on (the DIFF plant stays redacted, $b_diff_leak); the unmutated control leaks 0"
  else
    fail_ "XB" "changed_lines=$chg_b (want 2) mutant_files_leaking_MSG=$b_leak (want >=1) control=$b_ctl (want 0) mutant_files_leaking_DIFF=$b_diff_leak (want 0) allowlist_anchor_sites=$allow_sites (want 1)"
  fi
  # ── XT: neuter the cleanup trap -> G1's TEMP-RESIDUE leg must go RED ─────
  # THE COUNTERFACTUAL THAT LEG NEVER HAD, and it is here because it was
  # already exploited. The WP2 review neutered exactly this line and the whole
  # suite stayed 44/0 GREEN while ~44 work directories — each holding the RAW
  # gitleaks report with the message plant intact in `Message`, which
  # `--redact` does not touch — piled up in shared temp, unseen.
  #
  # The root cause was not the assertion, it was the address it read. BSD
  # `mktemp -d` IGNORES an overridden TMPDIR (measured: `TMPDIR=$P mktemp -d`
  # returns a path under /var/folders, not under $P), so G1 was grepping a
  # directory Scout had never written to. scout.sh now uses the template form
  # `mktemp -d "${TMPDIR:-/tmp}/scout-work.XXXXXXXX"`, which both BSD and GNU
  # honour — and this case is what proves the leg is live rather than merely
  # re-worded. It asserts BOTH directions in one place: the mutant leaves the
  # plant-bearing work directory behind under a TMPDIR this case owns, and the
  # unmutated control leaves that directory empty.
  XT=$(newtmp); mk_scout_copy "$XT"
  XTTMP=$(newtmp)
  XTCTMP=$(newtmp)
  trap_sites=$(grep -c "^trap 'rm -rf \"\$SCOUT_WORK\"' EXIT INT TERM$" "$SCOUT")
  _awk_inplace "$XT/scripts/scout.sh" '
    { if (!done && $0 == "trap '"'"'rm -rf \"$SCOUT_WORK\"'"'"' EXIT INT TERM") {
        print "trap '"'"':'"'"' EXIT INT TERM"
        done = 1; next }
      print }'
  chg_t=$(_changed_lines "$SCOUT" "$XT/scripts/scout.sh")
  TMPDIR="$XTTMP" bash "$XT/scripts/scout.sh" --root "$SEC" </dev/null >/dev/null 2>&1
  xt_leak=$(_grep_tree_for "$XTTMP" "$MSG_PLANT")
  XTC=$(newtmp); mk_scout_copy "$XTC"
  TMPDIR="$XTCTMP" bash "$XTC/scripts/scout.sh" --root "$SEC" </dev/null >/dev/null 2>&1
  xt_ctl=$(_grep_tree_for "$XTCTMP" "$MSG_PLANT")
  xt_ctl_entries=$( (cd "$XTCTMP" && LC_ALL=C ls -1A 2>/dev/null) | grep -c '')
  if [ "$chg_t" -eq 2 ] && [ "$xt_leak" -ge 1 ] && [ "$xt_ctl" -eq 0 ] \
     && [ "$xt_ctl_entries" -eq 0 ] && [ "$trap_sites" -eq 1 ]; then
    pass "XT: with Scout's cleanup trap neutered (1 line), the raw report carrying the MESSAGE plant is left behind in $xt_leak file(s) under an owned TMPDIR; the unmutated control leaves the directory completely empty — G1's temp-residue leg is live, not decorative"
  else
    fail_ "XT" "changed_lines=$chg_t (want 2) mutant_residue_files=$xt_leak (want >=1) control_residue_files=$xt_ctl (want 0) control_tmpdir_entries=$xt_ctl_entries (want 0) trap_anchor_sites=$trap_sites (want 1) — if the mutant leaks 0, Scout is not honouring TMPDIR and the residue leg is scanning a directory it never used"
  fi
else
  skip_ "XA1/XA2/XA/XB/XT (all five mutation proofs)" "gitleaks not installed — see the banner above"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== C — the §1.2 collision inventory, bucketed per §7.1, report-only ==="
# ════════════════════════════════════════════════════════════════════════════

COL=$(newtmp); mk_collision_fixture "$COL"
col=$(scout_json "$COL")

# _bucket_of JSON PATH — the bucket recorded for one inventory path.
_bucket_of() {
  printf '%s' "$1" | jq -r --arg p "$2" '.collisions.entries[] | select(.path==$p) | .bucket' 2>/dev/null
}
_class_of() {
  printf '%s' "$1" | jq -r --arg p "$2" '.collisions.entries[] | select(.path==$p) | .class' 2>/dev/null
}

# ── C1: the three named fixtures land in the three right buckets ───────────
b_hook=$(_bucket_of "$col" ".git/hooks/pre-commit")
b_cm=$(_bucket_of "$col" ".git/hooks/commit-msg")
b_gl=$(_bucket_of "$col" ".gitlab-ci.yml")
b_sl=$(_bucket_of "$col" ".claude/settings.local.json")
b_ch=$(_bucket_of "$col" "CHANGELOG.md")
if [ "$b_hook" = "archive-and-replace" ] && [ "$b_cm" = "marker-composed" ] \
   && [ "$b_gl" = "audit-only" ] && [ "$b_sl" = "archive-and-replace" ] \
   && [ "$b_ch" = "keep-theirs" ]; then
  pass "C1: husky pre-commit=archive-and-replace, commit-msg=marker-composed, foreign .gitlab-ci.yml=audit-only, settings.local.json=archive-and-replace, CHANGELOG.md=keep-theirs"
else
  fail_ "C1" "pre-commit='$b_hook' commit-msg='$b_cm' gitlab-ci='$b_gl' settings.local='$b_sl' CHANGELOG='$b_ch'"
fi

# ── C2: every bucket value is drawn from §7.1's four, and nothing else ─────
badbucket=$(printf '%s' "$col" | jq -r '[.collisions.entries[].bucket] | map(select(. != "archive-and-replace" and . != "marker-composed" and . != "audit-only" and . != "keep-theirs")) | join(",")' 2>/dev/null)
nent=$(jqv "$col" '.collisions.entries | length')
if [ -z "$badbucket" ] && [ "$(_num "$nent")" -ge 10 ]; then
  pass "C2: all $nent inventory entries carry one of §7.1's four bucket values and no invented fifth"
else
  fail_ "C2" "entries=$nent (want >=10) off-vocabulary buckets='$badbucket'"
fi

# ── C3: the hook description is built from a TOOL VOCABULARY, never bytes ──
# §7.2 requires a what-it-invokes description; §7.3 names the hazard — a
# hand-rolled hook can contain a token. The generator therefore emits only
# names it recognises. The proof is the secret fixture, whose pre-commit hook
# carries HOOK_PLANT: G1 already asserted the bytes, and this case asserts the
# description is nonetheless USEFUL rather than merely empty.
desc=$(printf '%s' "$col" | jq -r '.collisions.entries[] | select(.path==".git/hooks/pre-commit") | .description' 2>/dev/null)
if printf '%s' "$desc" | grep -q 'lint-staged' && printf '%s' "$desc" | grep -q 'npx' \
   && [ -n "$desc" ] && [ "$desc" != "null" ]; then
  pass "C3: the git-hook description names the tools it recognised ('$desc') — a fixed vocabulary, never a quoted line"
else
  fail_ "C3" "description='$desc' (want it to name npx and lint-staged)"
fi

# ── C4: absence is structural, never fabricated ────────────────────────────
# A bare tree has none of these surfaces. The discriminator is that the
# entries array is EMPTY, not that it is full of rows saying "absent".
BARE=$(newtmp); mk_bare_fixture "$BARE"
bare=$(scout_json "$BARE")
bare_n=$(jqv "$bare" '.collisions.entries | length')
bare_t=$(printf '%s' "$bare" | jq -r '.collisions.entries | type' 2>/dev/null)
if [ "$bare_n" = "0" ] && [ "$bare_t" = "array" ]; then
  pass "C4: a tree with none of the §1.2 surfaces reports an EMPTY entries array — absent surfaces are absent, not invented"
else
  fail_ "C4" "entries length='$bare_n' (want 0) type='$bare_t'"
fi

# ── C5: the four §7.4 detectors each fire, on their own file, and only there ─
CI=$(newtmp); mk_ci_findings_fixture "$CI"
ci=$(scout_json "$CI")
_rules_for() {
  printf '%s' "$1" | jq -r --arg p "$2" '[.collisions.entries[] | select(.path==$p) | .findings[]] | sort | join(",")' 2>/dev/null
}
r_skip=$(_rules_for "$ci" ".github/workflows/skip.yml")
r_am=$(_rules_for "$ci" ".github/workflows/automerge.yml")
r_dep=$(_rules_for "$ci" ".github/workflows/deploy.yml")
r_rw=$(_rules_for "$ci" ".github/workflows/rewrite.yml")
r_clean=$(_rules_for "$ci" ".github/workflows/clean.yml")
if [ "$r_skip" = "check-skipping" ] && [ "$r_am" = "auto-merge" ] \
   && [ "$r_dep" = "deploy-around-the-release-lane" ] \
   && [ "$r_rw" = "force-push-or-history-rewrite-in-ci" ] && [ -z "$r_clean" ]; then
  pass "C5: each §7.4 rule fires on exactly its own fixture workflow, and the clean workflow draws no finding at all"
else
  fail_ "C5" "skip='$r_skip' automerge='$r_am' deploy='$r_dep' rewrite='$r_rw' clean='$r_clean' (want empty)"
fi

# ── C6: a loud finding, and ZERO EDITS — the carve-out is audit-only ───────
# §7.4: their pipelines are audited, never touched. Proven by tree hash over
# the whole fixture, the same instrument WP1 uses for read-only.
CI2=$(newtmp); mk_ci_findings_fixture "$CI2"
h_before=$(_tree_hash "$CI2")
CI2OUT=$(newtmp)
bash "$SCOUT" --root "$CI2" --out "$CI2OUT" </dev/null >/dev/null 2>&1
scout_json "$CI2" >/dev/null
h_after=$(_tree_hash "$CI2")
det=$(printf '%s' "$ci" | jq -r '[.collisions.findingDetail[] | select(.rule=="check-skipping")] | length' 2>/dev/null)
det_line=$(printf '%s' "$ci" | jq -r '[.collisions.findingDetail[] | select(.rule=="check-skipping")][0].line' 2>/dev/null)
if [ "$h_before" = "$h_after" ] && [ "$(_num "$det")" -ge 1 ] \
   && printf '%s' "$det_line" | grep -Eq '^[0-9]+$'; then
  pass "C6: a continue-on-error security step draws a loud finding with a line number ($det_line) and the fixture is byte-identical afterwards (tree hash equal)"
else
  fail_ "C6" "tree_hash_before=$h_before after=$h_after check-skipping_details=$det line='$det_line'"
fi

# ── C7: the detail rows carry NO file content — the §6.2 doctrine, generalised ─
# A workflow line can contain a credential. The detector therefore reports the
# rule, the path and the LINE NUMBER, and never the matched text. This is the
# same allowlist discipline as the secrets section and it is asserted the same
# way: the keys of a detail row are exactly the four named.
dkeys=$(printf '%s' "$ci" | jq -r '[.collisions.findingDetail[0] | keys[]] | sort | join(",")' 2>/dev/null)
if [ "$dkeys" = "line,path,rule,why" ]; then
  pass "C7: a finding detail row carries exactly rule/path/line/why — the matched TEXT is never quoted into the report"
else
  fail_ "C7" "detail keys='$dkeys' want='line,path,rule,why'"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T — testsBaseline: the one place Scout may execute project code ==="
# ════════════════════════════════════════════════════════════════════════════

TST=$(newtmp); mk_tests_fixture "$TST"

# ── T1: BY DEFAULT Scout does not run anything, and says why ───────────────
# A scanner that executes arbitrary project code by default is a trap. The
# reason is a positive statement, not an empty field.
t=$(scout_json "$TST")
t_ran=$(jqv "$t" '.testsBaseline.commandRan')
t_reason=$(jqv "$t" '.testsBaseline.reason')
t_ec=$(jqv "$t" '.testsBaseline.exitCode')
t_cmd=$(jqv "$t" '.testsBaseline.testCommand.value')
if [ "$t_ran" = "false" ] && [ -n "$t_reason" ] && [ "$t_reason" != "null" ] \
   && [ "$t_ec" = "null" ] && [ -n "$t_cmd" ] && [ "$t_cmd" != "null" ]; then
  pass "T1: by default commandRan=false with a stated reason, exitCode=null — and the command was still DETECTED ('$t_cmd')"
else
  fail_ "T1" "commandRan='$t_ran' reason='$t_reason' exitCode='$t_ec' testCommand='$t_cmd'"
fi

# ── T2: --run-tests is the opt-in, and it really runs ──────────────────────
tr_out=$(bash "$SCOUT" --root "$TST" --run-tests </dev/null 2>/dev/null); rc=$?
tr_ran=$(jqv "$tr_out" '.testsBaseline.commandRan')
tr_ec=$(jqv "$tr_out" '.testsBaseline.exitCode')
tr_dur=$(jqv "$tr_out" '.testsBaseline.durationSeconds')
if [ "$rc" -eq 0 ] && [ "$tr_ran" = "true" ] && [ "$tr_ec" = "0" ] \
   && printf '%s' "$tr_dur" | grep -Eq '^[0-9]+$'; then
  pass "T2: --run-tests runs the detected command: commandRan=true, exitCode=0, durationSeconds=$tr_dur"
else
  fail_ "T2" "scout rc=$rc commandRan='$tr_ran' exitCode='$tr_ec' durationSeconds='$tr_dur'"
fi

# ── T3: a FAILING test suite is data, not a Scout error ────────────────────
RED=$(newtmp); mk_failing_tests_fixture "$RED"
rd=$(bash "$SCOUT" --root "$RED" --run-tests </dev/null 2>/dev/null); rc=$?
rd_ec=$(jqv "$rd" '.testsBaseline.exitCode')
rd_ran=$(jqv "$rd" '.testsBaseline.commandRan')
if [ "$rc" -eq 0 ] && [ "$rd_ran" = "true" ] && [ "$rd_ec" = "3" ]; then
  pass "T3: a test command that exits 3 is recorded as exitCode=3 and Scout still exits 0 — a red baseline is a finding, not a scanner failure"
else
  fail_ "T3" "scout rc=$rc (want 0) commandRan='$rd_ran' exitCode='$rd_ec' (want 3)"
fi

# ── T4: --run-tests with NO detected command runs nothing ──────────────────
nb=$(bash "$SCOUT" --root "$BARE" --run-tests </dev/null 2>/dev/null)
nb_ran=$(jqv "$nb" '.testsBaseline.commandRan')
nb_reason=$(jqv "$nb" '.testsBaseline.reason')
if [ "$nb_ran" = "false" ] && printf '%s' "$nb_reason" | grep -qi 'command'; then
  pass "T4: --run-tests on a tree with no detectable test command runs nothing and says so ('$nb_reason')"
else
  fail_ "T4" "commandRan='$nb_ran' reason='$nb_reason'"
fi

# ── T5: the untested-source count, and the classifier parity statement ─────
t_total=$(jqv "$t" '.testsBaseline.totalSourceFiles')
t_test=$(jqv "$t" '.testsBaseline.testFiles')
t_unt=$(jqv "$t" '.testsBaseline.untestedSourceFiles')
t_carried=$(jqv "$t" '.testsBaseline.classifierParity.carried | length')
t_simpl=$(jqv "$t" '.testsBaseline.classifierParity.simplified | length')
t_meth=$(jqv "$t" '.testsBaseline.untestedMethod')
# 5 impl files (src/mod1..5.ts), 1 test file; package.json/README.md/lockfile
# are not implementation under the extracted predicate.
if [ "$t_total" = "5" ] && [ "$t_test" = "1" ] && [ "$t_unt" = "4" ] \
   && [ "$(_num "$t_carried")" -ge 1 ] && [ "$(_num "$t_simpl")" -ge 1 ] \
   && [ -n "$t_meth" ] && [ "$t_meth" != "null" ]; then
  pass "T5: 5 implementation files, 1 test file, 4 untested — and the report states which parts of the classifier were carried ($t_carried) and which simplified ($t_simpl)"
else
  fail_ "T5" "total='$t_total' (want 5) testFiles='$t_test' (want 1) untested='$t_unt' (want 4) carried=$t_carried simplified=$t_simpl method='$t_meth'"
fi

# ── T6: `# BL-107-RUST-INLINE-TESTS` parity is real, not a claim ───────────
# The path-only classifier calls an inline-tested .rs file untested. The gate
# carries a content probe for exactly this; the extraction carries it too, and
# this case is what keeps it carried: src/lib.rs has inline tests, src/plain.rs
# does not, so the honest answer is 2 source files and 1 untested.
RS=$(newtmp); mk_rust_fixture "$RS"
rs=$(scout_json "$RS")
rs_total=$(jqv "$rs" '.testsBaseline.totalSourceFiles')
rs_unt=$(jqv "$rs" '.testsBaseline.untestedSourceFiles')
if [ "$rs_total" = "2" ] && [ "$rs_unt" = "1" ]; then
  pass "T6: a .rs file whose only tests are inline (#[cfg(test)]) is NOT counted untested — 2 source files, 1 untested"
else
  fail_ "T6" "totalSourceFiles='$rs_total' (want 2) untestedSourceFiles='$rs_unt' (want 1) — the BL-107 content probe is not carried"
fi

# ── T7: the execution bound is real ────────────────────────────────────────
SLOW=$(newtmp)
mkdir -p "$SLOW/src"
cat > "$SLOW/package.json" <<'EOF'
{ "name": "acme-slow", "scripts": { "test": "sleep 45" } }
EOF
printf 'export const v = 1;\n' > "$SLOW/src/mod.ts"
sl=$(SCOUT_TEST_TIMEOUT=2 bash "$SCOUT" --root "$SLOW" --run-tests </dev/null 2>/dev/null); rc=$?
sl_to=$(jqv "$sl" '.testsBaseline.timedOut')
sl_ran=$(jqv "$sl" '.testsBaseline.commandRan')
sl_dur=$(jqv "$sl" '.testsBaseline.durationSeconds')
if [ "$rc" -eq 0 ] && [ "$sl_to" = "true" ] && [ "$sl_ran" = "true" ] \
   && printf '%s' "$sl_dur" | grep -Eq '^[0-9]+$' && [ "${sl_dur:-99}" -le 10 ]; then
  pass "T7: a test command that would run for 45s is bounded at SCOUT_TEST_TIMEOUT=2 and reported timedOut=true after ${sl_dur}s"
else
  fail_ "T7" "scout rc=$rc timedOut='$sl_to' commandRan='$sl_ran' durationSeconds='$sl_dur' (want <=10)"
fi

# ── T8: the bound actually KILLS the command, and kills it QUIETLY ─────────
# Two properties that a reader would reasonably assume and that neither T7 nor
# A2 covers, both of which are one careless edit away from regressing:
#
#   (a) THE DESCENDANT DIES. `sh -c "sleep 3; touch marker"` is stopped at 1s.
#       If only the wrapper subshell had been signalled, the sleep would
#       survive and the marker would appear 3 seconds later. The case waits
#       past that moment and asserts the marker never arrives. This is what
#       the process-group kill buys, and asserting the absence of the marker is
#       the only way to see it — the exit code looks identical either way.
#   (b) IT IS SILENT. The bound uses `set -m` to get the command its own
#       process group, and job control is exactly the bash feature that
#       announces itself on stderr ("Terminated"). Scout's contract is an empty
#       stderr on a successful scan, and A2's loop does not reach this path.
T8=$(newtmp)
T8M=$(newtmp)
mkdir -p "$T8/src"
printf 'export const v = 1;\n' > "$T8/src/mod.ts"
cat > "$T8/package.json" <<EOF
{ "name": "acme-survivor", "scripts": { "test": "sleep 3; touch $T8M/survived" } }
EOF
t8err=$(SCOUT_TEST_TIMEOUT=1 bash "$SCOUT" --root "$T8" --run-tests </dev/null 2>&1 >/dev/null); rc=$?
sleep 4
if [ "$rc" -eq 0 ] && [ -z "$t8err" ] && [ ! -f "$T8M/survived" ]; then
  pass "T8: the stopped command's descendant really died (its delayed marker never appeared) and the kill wrote nothing to stderr"
else
  fail_ "T8" "rc=$rc stderr='$(printf '%s' "$t8err" | head -2)' survivor_marker_exists=$( [ -f "$T8M/survived" ] && echo yes || echo no ) (want no)"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== P — intakePrefill: §8.3's mapping table, one row per wizard runner ==="
# ════════════════════════════════════════════════════════════════════════════

pf=$(scout_json "$TST")

# ── P1: FIFTEEN rows, and the ids are the REAL runners — a currency canary ──
# The table is a static data block inside Scout (M5: Scout must run in a tree
# that has never had the framework, so it cannot read intake-wizard.sh at scan
# time). This suite lives in the framework repo and CAN read it, so the ids are
# derived from the wizard itself rather than restated. Add a runner to the
# wizard without adding a row here and this case goes red — which is the only
# thing that keeps the table from decaying into a snapshot of 2026.
wizard_ids=$(grep -o '^run_section_[a-z0-9_]*' "$WIZARD" 2>/dev/null \
  | sed -e 's/^run_section_//' | LC_ALL=C sort | tr '\n' ' ')
table_ids=$(printf '%s' "$pf" | jq -r '[.intakePrefill.sections[].id] | sort | join(" ")' 2>/dev/null)
table_ids="$table_ids "
nrows=$(jqv "$pf" '.intakePrefill.sections | length')
if [ "$nrows" = "15" ] && [ "$wizard_ids" = "$table_ids" ]; then
  pass "P1: 15 rows, one per run_section_* runner, ids derived from scripts/intake-wizard.sh and matching exactly"
else
  fail_ "P1" "rows=$nrows (want 15)\n  wizard ids: '$wizard_ids'\n  table  ids: '$table_ids'"
fi

# ── P2: every row carries a §8.3 class and nothing outside the vocabulary ──
badkind=$(printf '%s' "$pf" | jq -r '[.intakePrefill.sections[].kind] | map(select(. != "scan-derived" and . != "judgment" and . != "non-skippable")) | join(",")' 2>/dev/null)
n_scan=$(jqv "$pf" '[.intakePrefill.sections[] | select(.kind=="scan-derived")] | length')
n_judg=$(jqv "$pf" '[.intakePrefill.sections[] | select(.kind=="judgment")] | length')
n_non=$(jqv "$pf" '[.intakePrefill.sections[] | select(.kind=="non-skippable")] | length')
if [ -z "$badkind" ] && [ "$(_num "$n_scan")" -ge 1 ] && [ "$(_num "$n_judg")" -ge 1 ] && [ "$(_num "$n_non")" -ge 1 ]; then
  pass "P2: every row is scan-derived / judgment / non-skippable (${n_scan} / ${n_judg} / ${n_non}), with no invented fourth class"
else
  fail_ "P2" "off-vocabulary kinds='$badkind' scan=$n_scan judgment=$n_judg non-skippable=$n_non"
fi

# ── P3: judgment rows carry value:null — NEVER A GUESSED VALUE ─────────────
# §8.3: the prefill pattern is right for facts the framework recorded and wrong
# for judgments it has never made. A guessed business context is worse than no
# business context, because it will be confirmed away.
guessed=$(printf '%s' "$pf" | jq -r '[.intakePrefill.sections[] | select(.kind!="scan-derived") | select(.value != null) | .id] | join(",")' 2>/dev/null)
# NON-VACUITY: "no row broke the rule" is only a claim if rows were subject to
# it. An empty table satisfies the emptiness test perfectly.
n_subject=$(jqv "$pf" '[.intakePrefill.sections[] | select(.kind!="scan-derived")] | length')
if [ -z "$guessed" ] && [ "$(_num "$n_subject")" -ge 1 ]; then
  pass "P3: all $n_subject judgment/non-skippable rows carry value:null — Scout never guesses an answer it has no evidence for"
else
  fail_ "P3" "rows with a non-null value that should have none: '$guessed'; rows subject to the rule: $n_subject (want >=1)"
fi

# ── P4: scan-derived rows carry BOTH a value and its provenance ────────────
# §8.3's shipped pattern discloses the value AND where it came from; a prefill
# without provenance is an assertion the operator cannot check.
noprov=$(printf '%s' "$pf" | jq -r '[.intakePrefill.sections[] | select(.kind=="scan-derived") | select((.value == null) or (.source == null)) | .id] | join(",")' 2>/dev/null)
pname=$(printf '%s' "$pf" | jq -r '.intakePrefill.sections[] | select(.id=="1") | .value' 2>/dev/null)
if [ -z "$noprov" ] && [ "$pname" = "acme-api" ]; then
  pass "P4: every scan-derived row carries value+source, and section 1 reads the real project name ('$pname') off the fixture"
else
  fail_ "P4" "scan-derived rows missing value or source: '$noprov'; section 1 value='$pname' (want acme-api)"
fi

# ── P5: data classification is NON-SKIPPABLE, in both scenarios ────────────
# §8.3 and §4.3: the Phase 1→2 ZDR backstop's hard [FAIL] makes this a
# mechanical necessity, not a policy preference. Section 5 is where 5.5 lives.
k5=$(printf '%s' "$pf" | jq -r '.intakePrefill.sections[] | select(.id=="5") | .kind' 2>/dev/null)
v5=$(printf '%s' "$pf" | jq -r '.intakePrefill.sections[] | select(.id=="5") | .value' 2>/dev/null)
if [ "$k5" = "non-skippable" ] && [ "$v5" = "null" ]; then
  pass "P5: the section carrying 5.5 Data Classification & ZDR is non-skippable with no prefilled value"
else
  fail_ "P5" "section 5 kind='$k5' (want non-skippable) value='$v5' (want null)"
fi

# ── P6: the table is a DATA BLOCK Scout owns, readable without a scan ──────
# §10-WP4 consumes it. It must therefore be addressable as data, not only as a
# side effect of emitting a report.
if [ -f "$SCOUT_LIB/scout-prefill.sh" ]; then
  rows=$( . "$SCOUT_LIB/scout-prefill.sh" 2>/dev/null; _scout_prefill_table 2>/dev/null | grep -c '' )
  if [ "${rows:-0}" -eq 15 ]; then
    pass "P6: _scout_prefill_table emits the 15-row mapping as data, independent of any scan (WP4 consumes it)"
  else
    fail_ "P6" "_scout_prefill_table emitted $rows rows (want 15)"
  fi
else
  fail_ "P6" "scripts/lib/scout/scout-prefill.sh does not exist"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== R — READ-ONLY still holds, with four more sections in the scan ==="
# ════════════════════════════════════════════════════════════════════════════

# ── R1: the collision fixture is byte-identical after repeated scans ───────
# RUN TWICE, deliberately: an idempotent write is invisible to a
# before/after hash taken across a single run, and WP1 records a case that
# stayed green under a state-writing mutant for exactly that reason.
R1F=$(newtmp); mk_collision_fixture "$R1F"
SIDE=$(newtmp)
r1_before=$(_tree_hash "$R1F")
scout_json "$R1F" >/dev/null
scout_json "$R1F" >/dev/null
bash "$SCOUT" --root "$R1F" --markdown </dev/null >/dev/null 2>&1
bash "$SCOUT" --root "$R1F" --out "$SIDE" </dev/null >/dev/null 2>&1
r1_after=$(_tree_hash "$R1F")
if [ "$r1_before" = "$r1_after" ]; then
  pass "R1: the collision fixture (.claude/, .git/hooks/, .mcp.json, CI, uncommitted work) is byte-identical after four scans"
else
  _tree_manifest "$R1F" > "$SIDE/after.txt"
  fail_ "R1" "tree hash changed: $r1_before -> $r1_after"
fi

# ── R2: the SECRETS scan is read-only over a git repository ───────────────
# `gitleaks git` walks history through git plumbing. Measured here rather than
# assumed, `.git/` included, because a scan that refreshed an index would still
# have written to the operator's repository.
if [ "$HAVE_GITLEAKS" -eq 1 ]; then
  R2F=$(newtmp); mk_secret_fixture "$R2F"
  r2_before=$(_tree_hash "$R2F")
  scout_json "$R2F" >/dev/null
  scout_json "$R2F" >/dev/null
  r2_after=$(_tree_hash "$R2F")
  if [ "$r2_before" = "$r2_after" ]; then
    pass "R2: a full-history gitleaks scan leaves the repository byte-identical, .git/ included (run twice)"
  else
    fail_ "R2" "tree hash changed: $r2_before -> $r2_after"
  fi
else
  skip_ "R2 (read-only under a full-history secrets scan)" "gitleaks not installed"
fi

# ── R3: --run-tests, and an HONEST statement of what the hash excludes ─────
# This is the one flag that executes project code, so the fixture's test
# command is the only thing that can write — and here it is `sh -c 'exit 0'`,
# which writes nothing, so the WHOLE tree including .git/ is asserted
# unchanged. That is the honest scope of this proof: it shows SCOUT writes
# nothing under --run-tests. It cannot show that somebody else's test suite
# writes nothing, and no test could — running `npm test` on a real project
# creates coverage output, caches and lockfile touches by design. The report
# says so in the section itself; the flag is opt-in for this reason.
R3F=$(newtmp); mk_tests_fixture "$R3F"
( cd "$R3F" && unset GITHUB_BASE_REF && git init -q . && git config user.email t@t.local \
  && git config user.name T && git add -A && git commit -q -m init ) >/dev/null 2>&1
r3_before=$(_tree_hash "$R3F")
bash "$SCOUT" --root "$R3F" --run-tests </dev/null >/dev/null 2>&1
bash "$SCOUT" --root "$R3F" --run-tests </dev/null >/dev/null 2>&1
r3_after=$(_tree_hash "$R3F")
if [ "$r3_before" = "$r3_after" ]; then
  pass "R3: --run-tests with a no-write test command leaves the whole tree (.git/ included) identical — Scout itself writes nothing even on its one executing path"
else
  fail_ "R3" "tree hash changed under --run-tests: $r3_before -> $r3_after"
fi

# ── R4: the instrument is live (non-vacuity control) ──────────────────────
PROBE=$(newtmp); mk_bare_fixture "$PROBE"
p1=$(_tree_hash "$PROBE")
printf 'x\n' >> "$PROBE/notes.txt"
p2=$(_tree_hash "$PROBE")
if [ "$p1" != "$p2" ]; then
  pass "R4: the tree-hash instrument registers a one-byte append (R1-R3 are not vacuous)"
else
  fail_ "R4" "the recipe is blind: $p1 == $p2"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== A — interface, stderr hygiene, and M5 with the new libs ==="
# ════════════════════════════════════════════════════════════════════════════

# ── A1: all SEVEN §8.2 sections are emitted, and none is declared missing ──
a1=$(scout_json "$COL")
emitted=$(jqv "$a1" '.sections | sort | join(",")')
pending=$(jqv "$a1" '.sectionsNotEmitted | length')
present=1
for k in stack phaseMap reality secrets collisions testsBaseline intakePrefill; do
  printf '%s' "$a1" | jq -e "has(\"$k\")" >/dev/null 2>&1 || present=0
done
if [ "$emitted" = "collisions,intakePrefill,phaseMap,reality,secrets,stack,testsBaseline" ] \
   && [ "$pending" = "0" ] && [ "$present" -eq 1 ]; then
  pass "A1: all seven §8.2 sections are emitted and present as keys; sectionsNotEmitted is now empty"
else
  fail_ "A1" "sections='$emitted' sectionsNotEmitted length='$pending' all_keys_present=$present"
fi

# ── A2: a successful scan is SILENT on stderr, new sections included ───────
# WP1's A6, extended. gitleaks writes INF/WRN progress lines to stderr on every
# run — measured on 8.30.1 — so this case is the net that keeps them out of
# Scout's own stderr. `set -e` is deliberately absent from Scout, which is
# exactly why an empty stderr is the cheapest available proof that no predicate
# is quietly failing.
a2_fail=""
for f in "$SEC" "$COL" "$CI" "$TST" "$BARE" "$NONGIT" "$CLEAN"; do
  err=$(bash "$SCOUT" --root "$f" </dev/null 2>&1 >/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -z "$err" ] \
    || a2_fail="$a2_fail [json rc=$rc err='$(printf '%s' "$err" | head -2)']"
  err=$(bash "$SCOUT" --root "$f" --markdown </dev/null 2>&1 >/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -z "$err" ] \
    || a2_fail="$a2_fail [md rc=$rc err='$(printf '%s' "$err" | head -2)']"
done
err=$(bash "$SCOUT" --root "$TST" --run-tests </dev/null 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 0 ] && [ -z "$err" ] \
  || a2_fail="$a2_fail [run-tests rc=$rc err='$(printf '%s' "$err" | head -2)']"
if [ -z "$a2_fail" ]; then
  pass "A2: every successful scan across seven fixture shapes (json, markdown, --run-tests) writes NOTHING to stderr"
else
  fail_ "A2" "$a2_fail"
fi

# ── A3: the Markdown view renders the four new sections ───────────────────
# The needles are the four EXACT headings, not loose words: "test" and
# "intake" appear in a WP1 report already, so a substring probe would have
# passed against a build that emitted none of these sections. It did, in this
# suite's own first RED run.
md=$(bash "$SCOUT" --root "$COL" --markdown </dev/null 2>/dev/null)
md_ok=1
for needle in \
  "## Secrets in this project's history" \
  "## What would collide with the framework" \
  "## What the tests do today" \
  "## What the interview can skip"; do
  printf '%s' "$md" | grep -qF -- "$needle" || md_ok=0
done
md_leak=0
if [ "$HAVE_GITLEAKS" -eq 1 ]; then
  smd=$(bash "$SCOUT" --root "$SEC" --markdown </dev/null 2>/dev/null)
  for plant_name in DIFF_PLANT CARRIER MSG_PLANT HOOK_PLANT; do
    eval "plant=\$$plant_name"
    printf '%s' "$smd" | grep -q -- "$plant" && md_leak=1
  done
fi
if [ "$md_ok" -eq 1 ] && [ "$md_leak" -eq 0 ]; then
  pass "A3: the human view renders all four new sections and carries none of the plants"
else
  fail_ "A3" "markdown missing a section heading (ok=$md_ok) or leaking a plant (leak=$md_leak)"
fi

# ── A4: M5 — Scout alone in an EMPTY tree still emits all seven sections ──
# The new libs inherit the zero-dependency rule: no core lib, no other entry
# script, no jq. H1's proof, re-run against the WP2 build.
A4=$(newtmp); mk_scout_copy "$A4"
A4F=$(newtmp); mk_collision_fixture "$A4F"
a4=$(bash "$A4/scripts/scout.sh" --root "$A4F" </dev/null 2>/dev/null); rc=$?
a4_sections=$(jqv "$a4" '.sections | length')
a4_valid=0
printf '%s' "$a4" | jq -e . >/dev/null 2>&1 && a4_valid=1
if [ "$rc" -eq 0 ] && [ "$a4_sections" = "7" ] && [ "$a4_valid" -eq 1 ]; then
  pass "A4 (M5): scripts/scout.sh + scripts/lib/scout/ copied ALONE into an empty tree emits all 7 sections as valid JSON"
else
  fail_ "A4" "rc=$rc sections=$a4_sections (want 7) valid_json=$a4_valid"
fi

# ── A5: no new Scout lib names a core lib on an executed line ─────────────
if [ -d "$SCOUT_LIB" ]; then
  a5_bad=""
  for f in "$SCOUT_LIB"/scout-secrets.sh "$SCOUT_LIB"/scout-collisions.sh \
           "$SCOUT_LIB"/scout-testsbaseline.sh "$SCOUT_LIB"/scout-prefill.sh; do
    [ -f "$f" ] || { a5_bad="$a5_bad [missing $(basename "$f")]"; continue; }
    if sed -e 's/[[:space:]]*#.*$//' "$f" | grep -qE '(^|[^-a-zA-Z0-9_])(intake-wizard\.sh|pre-commit-gate\.sh|check-phase-gate\.sh|tdd-classify\.sh)'; then
      a5_bad="$a5_bad [$(basename "$f") names a core script on an executed line]"
    fi
  done
  if [ -z "$a5_bad" ]; then
    pass "A5 (M5, lexical): none of the four new libs names a core script or lib on an executed line — the prefill table is DATA, not a read of intake-wizard.sh"
  else
    fail_ "A5" "$a5_bad"
  fi
else
  fail_ "A5" "$SCOUT_LIB does not exist"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== K — the gitleaks pin's own verification cannot silently pass ==="
# ════════════════════════════════════════════════════════════════════════════
#
# R-WP2-6. The CI step that installs gitleaks is what makes the planted-secret
# proof runnable at all, so the integrity check on that download sits on the
# critical path of this entire package. Written the obvious way it is a check
# that cannot fail — measured on this host:
#
#   $ echo "THIS-IS-NOT-A-HASH  gl.tgz" | sha256sum -c -
#   sha256sum: WARNING: 1 line is improperly formatted
#   rc=0
#
# A typo in the pin, or a variable that expanded to nothing, and the download is
# unverified while CI stays green. These cases execute every failure mode of the
# replacement ON THIS HOST, with no appeal to what some other platform's binary
# would have done — which is the whole reason the verification lives in a script
# instead of three lines of workflow YAML.

KV="$REPO_ROOT/scripts/ci-verify-sha256.sh"
if [ ! -f "$KV" ]; then
  fail_ "K1-K7" "scripts/ci-verify-sha256.sh does not exist"
else
  K=$(newtmp)
  printf 'the payload\n' > "$K/asset.bin"
  K_REAL=$( { sha256sum "$K/asset.bin" 2>/dev/null || shasum -a 256 "$K/asset.bin" 2>/dev/null; } | awk '{print $1; exit}' )
  # A well-formed 64-hex value that is NOT the file's hash. Derived from the
  # real one so it cannot accidentally BE the real one.
  K_WRONG=$(printf '%s' "$K_REAL" | tr '0123456789abcdef' '1234567890fedcba')

  # ── K1: the honest positive — a correct pin verifies ────────────────────
  # Without this, an implementation that failed EVERYTHING would satisfy
  # K2-K6 perfectly.
  bash "$KV" "$K/asset.bin" "$K_REAL" >/dev/null 2>&1; k1=$?
  if [ "$k1" -eq 0 ] && [ "${#K_REAL}" -eq 64 ]; then
    pass "K1: a correct 64-hex pin verifies (rc=0) — the negative cases below are not vacuous"
  else
    fail_ "K1" "rc=$k1 (want 0) computed='$K_REAL' (want 64 hex chars)"
  fi

  # ── K2: a MALFORMED pin FAILS (the R-WP2-6 defect itself) ───────────────
  bash "$KV" "$K/asset.bin" "THIS-IS-NOT-A-HASH" >/dev/null 2>&1; k2=$?
  if [ "$k2" -eq 1 ]; then
    pass "K2: a MALFORMED pin exits 1 — the spelling this replaced exits 0 on this host and verifies nothing"
  else
    fail_ "K2" "rc=$k2 (want 1) — a malformed pin is being treated as verified"
  fi

  # ── K3: an EMPTY pin FAILS (the expanded-to-nothing case) ───────────────
  bash "$KV" "$K/asset.bin" "" >/dev/null 2>&1; k3=$?
  if [ "$k3" -eq 1 ]; then
    pass "K3: an EMPTY pin exits 1 — an unset or mistyped variable cannot pass as verified"
  else
    fail_ "K3" "rc=$k3 (want 1)"
  fi

  # ── K4: a WRONG BUT WELL-FORMED pin FAILS ──────────────────────────────
  bash "$KV" "$K/asset.bin" "$K_WRONG" >/dev/null 2>&1; k4=$?
  if [ "$k4" -eq 1 ] && [ "$K_WRONG" != "$K_REAL" ]; then
    pass "K4: a well-formed pin that is not this file's hash exits 1"
  else
    fail_ "K4" "rc=$k4 (want 1) wrong='$K_WRONG' real='$K_REAL' (must differ)"
  fi

  # ── K5: a TAMPERED ASSET fails against a correct pin ───────────────────
  # The threat the pin exists for: the pin is right, the bytes changed.
  printf 'the payload with one more byte\n' > "$K/asset.bin"
  bash "$KV" "$K/asset.bin" "$K_REAL" >/dev/null 2>&1; k5=$?
  if [ "$k5" -eq 1 ]; then
    pass "K5: a TAMPERED asset exits 1 against the pin that matched it moments earlier"
  else
    fail_ "K5" "rc=$k5 (want 1) — a replaced release asset would install silently"
  fi

  # ── K6: a MISSING file and bad usage are errors, not passes ────────────
  bash "$KV" "$K/does-not-exist" "$K_REAL" >/dev/null 2>&1; k6a=$?
  bash "$KV" "$K/asset.bin" >/dev/null 2>&1; k6b=$?
  if [ "$k6a" -eq 1 ] && [ "$k6b" -eq 2 ]; then
    pass "K6: a missing file exits 1 and a missing argument exits 2 — neither is mistaken for a verified download"
  else
    fail_ "K6" "missing-file rc=$k6a (want 1) missing-arg rc=$k6b (want 2)"
  fi

  # ── K7: the workflow actually CALLS it, in every job that installs ─────
  # A verifier nothing invokes is decoration. Asserted against the real
  # workflow file: every gitleaks download is followed by a verification, and
  # the superseded `sha256sum -c` spelling is gone from the file entirely.
  # COMMENTS ARE STRIPPED BEFORE THE LEGACY-SPELLING GREP, and this case caught
  # its own author: the first version counted the two explanatory comments that
  # NAME `sha256sum -c` and went red against a workflow that does not run it.
  # Same defect class as this repository's unit-lane predicate reading a
  # mention as an invocation (CLAUDE.md, `# BL-181-UNIT-LANE-PREDICATE`) — a
  # check must read executed lines, not prose about them.
  WF="$REPO_ROOT/.github/workflows/tests.yml"
  WF_EXEC="$K/workflow-no-comments.txt"
  sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#[^"'"'"']*$//' "$WF" > "$WF_EXEC"
  k7_dl=$(grep -c 'gitleaks_.*_linux_x64\.tar\.gz"$' "$WF_EXEC" 2>/dev/null)
  k7_verify=$(grep -c 'ci-verify-sha256\.sh /tmp/gitleaks\.tar\.gz' "$WF_EXEC" 2>/dev/null)
  k7_old=$(grep -c 'sha256sum -c' "$WF_EXEC" 2>/dev/null)
  k7_pin=$(grep -c 'GITLEAKS_SHA256: "551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"' "$WF_EXEC" 2>/dev/null)
  if [ "$(_num "$k7_verify")" -eq 2 ] && [ "$(_num "$k7_pin")" -eq 2 ] \
     && [ "$(_num "$k7_old")" -eq 0 ] && [ "$(_num "$k7_verify")" -eq "$(_num "$k7_dl")" ]; then
    pass "K7: both jobs that download gitleaks verify it through the script ($k7_dl download(s), $k7_verify verification(s), $k7_pin pinned checksum(s)); the exit-0-on-malformed spelling appears nowhere"
  else
    fail_ "K7" "downloads=$k7_dl verifications=$k7_verify (want 2 and equal) pinned_checksums=$k7_pin (want 2) legacy 'sha256sum -c' occurrences=$k7_old (want 0)"
  fi
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
if [ "$SKIPPED" -gt 0 ]; then
  echo "!! $SKIPPED case(s) SKIPPED because gitleaks is not installed — the"
  echo "!! planted-secret proof (§6.5) DID NOT RUN. This build is not certified"
  echo "!! against the defect WP2 exists to prevent. Install gitleaks and re-run."
  if [ "$GITLEAKS_ABSENT_IS_FATAL" -eq 1 ]; then
    echo "!! CI is set, so this run is also FAILED, not merely incomplete."
  fi
fi
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
