#!/usr/bin/env bash
# tests/test-delta-wp7-cut-release.sh — Delta Track WP7.
#
# SPEC: docs/designs/2026-08-02-delta-track-v1.md §9.1 (semver, decided by the
# TOOL — the class->bump map is retunable, the PRECEDENCE is machinery — and
# §13-R2's recorded cost of having no override), §9.2 (THE THREE REFUSALS AND
# THEIR ORDER, and the last line: "performs no write of any kind before all
# three pass"), §9.3 (promotion, and the tag format C7 forces), §8.2 (a major
# bump re-runs run-phase3-validation.sh in full BEFORE the tag is written),
# §8.3 (overdue AND unmeasurable are both refusals), §7.1 (`shipped_in` is
# recorded at cut time THROUGH THE SEAM), §3.1 (cut-release.sh is a
# DELTA-MODULE file despite its core-sounding name), §0.3-C7 (GitLab's
# version-strict release lanes — why the tag format is a constraint and not a
# preference), §0.3-C8 (`--finalize-phase 4` is a SECOND orphan and WP7 does
# NOT wire it), §11-WP7.
#
# (No `# BL-NNN-…` marker anywhere in the delta track on purpose: no backlog
# entry exists for this build and minting one would red
# scripts/lint-bl-markers.sh, whose first pass resolves every marker to a real
# `## BL-NNN:` entry. The design-doc path above is the citation, per the WP1
# through WP6 precedent. The grep-able `CUTREL-*` markers in the product are
# this suite's citation primitive and its mutation addresses.)
#
# ═════════════════════════════════════════════════════════════════════════════
# THE TWO PROPERTIES THIS SUITE EXISTS FOR
#
# 1. A REFUSED CUT LEAVES NOTHING BEHIND. §9.2's last line is not a nicety:
#    "a partially-cut release (changelog promoted, tag absent) is a worse state
#    than a refused one". Every refusal row below is asserted with a WHOLE-TREE
#    `find` + per-file md5 manifest taken before and after, plus a separate
#    count of the repository's tags — because a `git tag` leaves nothing in the
#    working tree at all and a file manifest alone cannot see one. Checking a
#    handful of expected filenames cannot see a file nobody thought to look
#    for; that is the WP4/WP5 standard and it is inherited here verbatim.
#
# 2. THE TAG IS EXACTLY `vMAJOR.MINOR.PATCH`. C7 measured the release lanes:
#    GitHub (4 templates) and Bitbucket (4) match `v*`; GitLab (4) matches
#    `/^v\d+\.\d+\.\d+$/`. A `v1.2.0-rc1` therefore BUILDS on two hosts and
#    SILENTLY DOES NOTHING on the third — green on the host you tested, which
#    is the worst available failure mode. m2 emits exactly that suffix and this
#    suite must go RED for it.
#
# ═════════════════════════════════════════════════════════════════════════════
# EXIT CODES, NEVER LABELS
#
# Every verdict below is asserted on a process EXIT CODE, a file's BYTES, a
# whole-tree manifest, or a `git tag --list` count. None is asserted on a
# printed `[OK]`/`[WARN]`/`[FAIL]` banner. CLAUDE.md's `[WARN]` trap is that a
# label and an exit predicate can disagree — in check-phase-gate.sh two arms
# printing the SAME word have opposite gate outcomes — and BL-213's whole
# defect was a closing sentence that lied. Printed text is MEASURED for the
# reader in pass narratives; it is never the predicate.
#
# THE CONTRACT UNDER TEST (scripts/cut-release.sh):
#     0   the release was cut
#     2   invocation / environment error (bad flag, no git, no jq, no CHANGELOG)
#     3   REFUSAL 1 — a delta is open (§9.2)
#     4   REFUSAL 2 — an unfiled hotfix retro (§9.2)
#     5   REFUSAL 3 — cadence overdue OR unmeasurable (§9.2 + §8.3)
#     6   REFUSAL — the delta record exists and cannot be read (strict rc 3)
#     7   REFUSAL — there is no delta record at all (strict rc 4)
#     8   REFUSAL — nothing closed since the last tag (§9.1)
#     9   REFUSAL — a closed row's class maps to no bump (fail-closed)
#    10   REFUSAL — major bump, and the §8.2 revalidation did not pass
#    11   a write FAILED after every refusal passed — the cut is incomplete
#
# TWO CONSUMED CONTRACTS, NOT RE-SPELLED HERE:
#   • scripts/lib/delta-cadence.sh — WP5's retro predicates and the seam's
#     `--delta-state-read-strict` rc 0/3/4. WP7 REFUSES ON BOTH 3 AND 4.
#   • scripts/check-maintenance.sh — WP6's 0 measured-current / 1 overdue /
#     2 unmeasurable. WP7 REFUSES ON BOTH 1 AND 2.
#
# ═════════════════════════════════════════════════════════════════════════════
# WHAT THIS SUITE PINS, AND WHICH MUTANT EACH ROW KILLS
#
#   R — THE THREE REFUSALS (§9.2), ALONE, IN COMBINATION, WRITING NOTHING
#     R1  open delta alone                      -> 3, tree + tags unmoved
#     R2  open hotfix retro alone               -> 4, names the delta, its
#         due_by and how overdue it is                            KILLS m1
#     R3  cadence OVERDUE (checker rc 1) alone  -> 5
#     R4  cadence UNMEASURABLE (checker rc 2)   -> 5, NOT a pass    KILLS m3
#     R5  all three at once -> 3: the CHEAPEST refusal speaks first (§9.2's
#         author-proposed order), and the tree is still untouched   KILLS m5
#     R6  refusals 2 and 3 together -> 4: the order holds with the first
#         refusal removed, which is what proves it is an ORDER and not an
#         accident of which check happens to be cheap
#     R7  the state file exists and is CORRUPT  -> 6 (strict read rc 3)
#     R8  there is no state file at all         -> 7 (strict read rc 4)
#     R9  nothing closed since the last tag     -> 8
#     R10 EVERY refusal above leaves the repository's TAG SET identical —
#         a `git tag` writes nothing into the working tree, so the file
#         manifest in R1-R9 is structurally blind to it
#
#   S — SEMVER, DECIDED BY THE TOOL (§9.1)
#     S1  a feature + a fix        -> minor
#     S2  fixes only               -> patch
#     S3  a breaking marker        -> major, AND run-phase3-validation.sh is
#         actually INVOKED (§8.2), proven by a recording stub    KILLS m7
#     S4  major + a FAILING revalidation -> 10, and the tree is unmoved:
#         "before the tag is written" means before the CHANGELOG too
#     S5  the MAP is retunable: semver.fix = "minor" makes a fixes-only set
#         a minor release
#     S6  the PRECEDENCE is machinery: shuffling the `closed` rows cannot
#         change the answer, and no policy key can reorder it     KILLS m4
#     S7  no tag in the repository at all -> the base is 0.0.0
#     S8  a closed row whose class maps to no bump -> 9, fail-closed,
#         nothing written
#
#   P — PROMOTION (§9.3)
#     P1  `## [Unreleased]` becomes `## [X.Y.Z] — YYYY-MM-DD`, and a FRESH
#         `## [Unreleased]` sits ABOVE it
#     P2  all EIGHT template categories survive, in template order, verbatim
#     P3  the promoted block's body is BYTE-IDENTICAL to what was under
#         `## [Unreleased]` before — the tool writes no prose
#     P4  the fresh block contains NOTHING but its heading and the eight
#         category headings
#
#   T — THE TAG (§9.3 + C7)
#     T1  exactly ONE new tag, and it matches `^v[0-9]+\.[0-9]+\.[0-9]+$`
#                                                                 KILLS m2
#     T2  the tag names the tip of the current branch
#     T3  nothing was pushed: the fixture has NO remote at all, and the cut
#         still succeeds
#
#   W — `shipped_in` THROUGH THE SEAM (§7.1)
#     W1  every unshipped closed row now carries the tag; an already-shipped
#         row is untouched
#     W2  WRITE-ONCE: a second cut refuses with 8 and rewrites nothing
#     W3  STRUCTURAL: the script contains no direct write to the state file —
#         the ship pathway is the only route
#
#   A — ADJACENCIES AND CONSTRAINTS
#     A1  `--finalize-phase` is NOT wired (C8/Q3 — Karl did not decide it)
#     A2  there is NO semver override flag (§9.1, §13-R2)
#     A3  the boundary lint stays rc 0 and the seam allowlist stays at ONE
#     A4  every refusal prints what would clear it (§4.3's plain register)
#
#   M — MUTATIONS (anchored, sites==1, one line changed, mode preserved,
#       fresh fixtures, both trees executed)
#     m1  suppress the open-retro refusal   -> a release cuts with a retro
#         outstanding: the collateral on D3's loan is never called in
#     m2  emit `v1.2.0-rc1`                 -> the C7 defence
#     m3  collapse cadence rc 2 into a pass -> an unmeasured cadence
#         silently satisfies a release, which is BL-213 one level up
#     m4  reorder the semver precedence     -> a feature ships as a patch
#     m5  suppress the open-delta refusal   -> a release cuts mid-delta
#     m7  neuter the major revalidation     -> a breaking release skips the
#         §8.2 full re-run
#
# LANE: registered in tests/full-project-test-suite.sh AND in the tests.yml
# `unit-shard` list. Its executed lines never name the init script — the one
# row that reads that file does so through a SPLIT token, the same idiom and
# the same reason as tests/test-delta-wp6-cadence.sh::H6 and
# tests/test-intake-wizard-fixes.sh.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

for _t in git jq; do
  if ! command -v "$_t" >/dev/null 2>&1; then
    echo "$_t is required for tests/test-delta-wp7-cut-release.sh" >&2
    exit 2
  fi
done

CUTREL="$REPO_ROOT/scripts/cut-release.sh"

# ── Dates ───────────────────────────────────────────────────────────────────
# GNU-first, BSD fallback — the house pattern, spelled here so the FIXTURES do
# not depend on the product's own parser to build the inputs that test it.
days_ago() {   # <n> -> YYYY-MM-DD, n whole days before now, UTC
  local n="$1" e
  e=$(( $(date -u +%s) - n * 86400 ))
  date -u -d "@$e" +%Y-%m-%d 2>/dev/null || date -u -r "$e" +%Y-%m-%d
}
stamp_ago() {  # <n> -> YYYY-MM-DDTHH:MM:SSZ, n whole days before now, UTC
  local n="$1" e
  e=$(( $(date -u +%s) - n * 86400 ))
  date -u -d "@$e" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$e" +%Y-%m-%dT%H:%M:%SZ
}
today_utc() { date -u +%Y-%m-%d; }

# ── Residue instruments ─────────────────────────────────────────────────────
# Portable md5 of a single file (macOS `md5 -q`, Linux `md5sum`) — house pattern.
_md5file() {
  if command -v md5 >/dev/null 2>&1; then md5 -q "$1"
  else md5sum "$1" | awk '{print $1}'; fi
}

tree_files() {
  ( cd "$1" && find . -type f ! -path './.git/*' | LC_ALL=C sort )
}

# tree_manifest <project-dir> — every file in the tree with its md5. THE
# refusal-residue instrument: a refusal that says "nothing was written" is a
# claim about the whole filesystem, and checking one expected filename cannot
# see a file nobody thought to look for.
#
# IT IS DELIBERATELY BLIND TO ONE THING, AND R10 IS WHY IT HAS A SIBLING. A
# `git tag` writes into `.git/`, which this excludes — so a refusal that
# nevertheless tagged would pass every manifest row in this file. R10 counts
# tags separately for exactly that reason.
tree_manifest() {
  local p="$1" f
  tree_files "$p" | while IFS= read -r f; do
    printf '%s  %s\n' "$(_md5file "$p/$f")" "$f"
  done
}

tag_list() {   # <project-dir> — every tag, sorted, one per line
  ( cd "$1" && git tag --list 2>/dev/null | LC_ALL=C sort )
}

# ── Fixtures ────────────────────────────────────────────────────────────────
# EVERY case builds its own tree and removes it. Nothing is shared, so a case
# can never inherit a surface it did not ask for — and a surface it did not ask
# for is exactly what would make a refusal look like a pass.

FIXTURE_SEQ=0

# mk_proj <dir> [age-days] — a phase-4 git project with a MEASURABLE cadence and
#   no delta state at all. The cadence surfaces are seeded fresh by default on
#   purpose: the third refusal is the expensive one and every row that is not
#   ABOUT it needs it quiet.
#
#   THE AGE IS A PARAMETER OF THE WHOLE FIXTURE, NOT A LATER RE-COMMIT, and that
#   is not a style choice. Ageing CHANGELOG.md afterwards means committing it
#   with an author AND committer date OLDER than the commit already at HEAD, and
#   `git log`'s default ordering is by commit date — so `git log -1 -- CHANGELOG.md`
#   would be answering a question about walk order rather than about the file.
#   Building the tree at the age the row needs removes the question.
mk_proj() {
  local d="$1" age="${2:-1}" stamp
  mkdir -p "$d/.claude" "$d/docs/test-results"
  (
    cd "$d" && unset GITHUB_BASE_REF
    git init -q .
    git config user.email "wp7@example.invalid"
    git config user.name "WP7 Fixture"
    git config commit.gpgsign false
    git config tag.gpgsign false
  ) >/dev/null 2>&1
  printf '{"track":"light","deployment":"personal","poc_mode":null,"current_phase":4,"phases":{}}\n' \
    > "$d/.claude/phase-state.json"
  cp "$REPO_ROOT/templates/generated/changelog.tmpl" "$d/CHANGELOG.md"
  printf '{"sbom":"fixture"}\n' > "$d/sbom.json"
  printf 'scan artefact\n' > "$d/docs/test-results/$(days_ago 3)_semgrep_pass.txt"
  stamp="$(days_ago "$age")T12:00:00+0000"
  (
    cd "$d" && unset GITHUB_BASE_REF
    GIT_AUTHOR_DATE="$stamp" GIT_COMMITTER_DATE="$stamp" git add -A
    GIT_AUTHOR_DATE="$stamp" GIT_COMMITTER_DATE="$stamp" git commit -q -m "chore: fixture"
  ) >/dev/null 2>&1
}

# tag_at <dir> <tag> — a local, unsigned tag on the current tip.
tag_at() { ( cd "$1" && unset GITHUB_BASE_REF; git tag "$2" ) >/dev/null 2>&1; }

# write_state <dir> <json> — the delta record, verbatim.
write_state() { printf '%s\n' "$2" > "$1/.claude/delta-state.json"; }

# closed_row <id> <class> [breaking] [shipped_in]
closed_row() {
  local id="$1" cls="$2" brk="${3:-false}" ship="${4:-null}"
  local shipj="null"
  [ "$ship" = "null" ] || shipj="\"$ship\""
  printf '{"id":"%s","class":"%s","severity":null,"closed_at":"%s","shipped_in":%s,"breaking":%s}' \
    "$id" "$cls" "$(stamp_ago 2)" "$shipj" "$brk"
}

# state_doc <active-json> <retros-json> <closed-json>
state_doc() {
  printf '{"schemaVersion":1,"active_delta":%s,"hotfix_retros":%s,"cadence":{},"closed":%s}' \
    "$1" "$2" "$3"
}

# A minimal, schema-valid open delta.
ACTIVE_JSON='{"id":"DELTA-009","slug":"dark-mode","class":"feature","brief":"docs/deltas/DELTA-009-dark-mode.md","opened_at":"2026-08-01T00:00:00Z","opened_via":"guided","attributes":{"risk":"feature-local","level":"small","severity":null},"gates_required":["ledger_row"],"gates_completed":[]}'

# open_retro <id> <days-overdue>
open_retro() {
  printf '{"id":"%s","shipped_at":"%s","due_by":"%s","closed_at":null,"record":null}' \
    "$1" "$(stamp_ago $(( $2 + 3 )))" "$(stamp_ago "$2")"
}

# mk_scripts_tree <dir> — a private copy of scripts/ so a mutant never touches
#   the repository under test.
mk_scripts_tree() { mkdir -p "$1"; cp -R "$REPO_ROOT/scripts" "$1/scripts"; }

# stub_revalidation <scripts-dir> <exit-code> — replace the Phase 3 driver with
#   a recorder. S3 needs PROOF the driver ran, and running the real one would
#   drag five scanners (and a network) into a unit test.
stub_revalidation() {
  local sd="$1" rc="$2"
  cat > "$sd/run-phase3-validation.sh" <<'STUB_EOF'
#!/usr/bin/env bash
# WP7 test stub — records that it was invoked, then answers the code it was built with.
printf 'invoked %s\n' "$*" >> "${WP7_REVALIDATION_LOG:-/dev/null}"
exit __RC__
STUB_EOF
  sed -e "s/__RC__/$rc/" "$sd/run-phase3-validation.sh" > "$sd/run-phase3-validation.sh.tmp" \
    && mv "$sd/run-phase3-validation.sh.tmp" "$sd/run-phase3-validation.sh"
  chmod +x "$sd/run-phase3-validation.sh"
}

# ── Runner ──────────────────────────────────────────────────────────────────
CUT_RC=0
CUT_OUT=""
run_cut() {   # <scripts-dir> <project-dir> [args...]
  local sd="$1" p="$2"; shift 2
  CUT_RC=0
  CUT_OUT="$( cd "$p" && unset GITHUB_BASE_REF; bash "$sd/cut-release.sh" "$@" </dev/null 2>&1 )" || CUT_RC=$?
  return 0
}

# ── Mutation harness (inherited from the WP2-WP6 suites) ────────────────────

_sed_inplace() {
  local file="$1" expr="$2" tmp mode
  mode="$(stat -c '%a' "$file" 2>/dev/null || stat -f '%Lp' "$file" 2>/dev/null || echo "")"
  tmp="$(mktemp)"
  sed -e "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
  [ -n "$mode" ] && chmod "$mode" "$file" 2>/dev/null
  return 0
}

_mutation_report() {
  local orig="$1" mut="$2" marker="$3" sites changed n
  sites="$(grep -c "$marker" "$orig" || true)"
  case "$sites" in ''|*[!0-9]*) sites=0 ;; esac
  if diff "$orig" "$mut" >/dev/null 2>&1; then changed=n; else changed=y; fi
  n="$(diff "$orig" "$mut" | grep -c '^[<>]' || true)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s|%s|%s' "$sites" "$changed" "$n"
}

_mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || echo "?"; }

echo "== tests/test-delta-wp7-cut-release.sh =="
echo ""

if [ ! -f "$CUTREL" ]; then
  echo "  [FAIL] scripts/cut-release.sh is missing — WP7 delivers it, it must exist" >&2
  exit 1
fi

# ════════════════════════════════════════════════════════════════════════════
echo "=== R — the three refusals (§9.2): order, and NO WRITE OF ANY KIND ==="
# ════════════════════════════════════════════════════════════════════════════

# _refuse_case <name> <want-rc> <setup-fn>
#   One refusal row, with the whole-tree manifest and the tag set captured on
#   both sides. Returns the detail string through R_DETAIL.
R_DETAIL=""
R_OK=y
R_TAGS_OK=y
_refuse_case() {
  local name="$1" want="$2" setup="$3" age="${4:-1}" P before after tags_before tags_after
  P="$RT/$name"
  mk_proj "$P" "$age"
  tag_at "$P" "v1.2.0"
  "$setup" "$P"
  before="$(tree_manifest "$P")"; tags_before="$(tag_list "$P")"
  run_cut "$REPO_ROOT/scripts" "$P"
  after="$(tree_manifest "$P")"; tags_after="$(tag_list "$P")"
  R_DETAIL="$R_DETAIL [$name=rc$CUT_RC]"
  [ "$CUT_RC" -eq "$want" ] || { R_OK=n; R_DETAIL="$R_DETAIL(want $want)"; }
  [ "$before" = "$after" ] || { R_OK=n; R_DETAIL="$R_DETAIL(TREE MOVED)"; }
  [ "$tags_before" = "$tags_after" ] || { R_TAGS_OK=n; R_DETAIL="$R_DETAIL(TAGGED)"; }
  # Every refusal must say what would clear it (§4.3).
  case "$CUT_OUT" in
    *"To clear this:"*) : ;;
    *) R_OK=n; R_DETAIL="$R_DETAIL(NO REMEDY)" ;;
  esac
}

# The setups. Each one leaves exactly ONE condition wrong unless it says so.
# `_break_cadence2` is factored out because three rows need it and it must not
# also decide what the state document says.
_break_cadence2() {
  # §14-V13's fixture: a date NEITHER parser accepts -> the checker's rc 2.
  rm -f "$1"/docs/test-results/*
  printf 'scan artefact\n' > "$1/docs/test-results/2026-13-45_semgrep_pass.txt"
}
_s_open_delta()  { write_state "$1" "$(state_doc "$ACTIVE_JSON" '[]' "[$(closed_row DELTA-008 fix)]")"; }
_s_open_retro()  { write_state "$1" "$(state_doc 'null' "[$(open_retro DELTA-007 2)]" "[$(closed_row DELTA-008 fix)]")"; }
_s_clean()       { write_state "$1" "$(state_doc 'null' '[]' "[$(closed_row DELTA-008 fix)]")"; }
_s_cadence_2()   { _s_clean "$1"; _break_cadence2 "$1"; }
_s_all_three()   {
  write_state "$1" "$(state_doc "$ACTIVE_JSON" "[$(open_retro DELTA-007 2)]" "[$(closed_row DELTA-008 fix)]")"
  _break_cadence2 "$1"
}
_s_two_and_three() {
  write_state "$1" "$(state_doc 'null' "[$(open_retro DELTA-007 2)]" "[$(closed_row DELTA-008 fix)]")"
  _break_cadence2 "$1"
}
_s_corrupt()     { printf '{"schemaVersion": 1, "active_delta"\n' > "$1/.claude/delta-state.json"; }
_s_absent()      { rm -f "$1/.claude/delta-state.json"; }
_s_nothing()     { write_state "$1" "$(state_doc 'null' '[]' "[$(closed_row DELTA-008 fix false v1.2.0)]")"; }

RT=$(mktemp -d)
_refuse_case open-delta      3 _s_open_delta
_refuse_case open-retro      4 _s_open_retro
# 20 days > the 14-day routine default: OVERDUE, so the checker answers 1.
_refuse_case cadence-overdue 5 _s_clean 20
_refuse_case cadence-unmeas  5 _s_cadence_2
_refuse_case all-three       3 _s_all_three
_refuse_case two-and-three   4 _s_two_and_three
_refuse_case corrupt-state   6 _s_corrupt
_refuse_case absent-state    7 _s_absent
_refuse_case nothing-closed  8 _s_nothing

if [ "$R_OK" = y ]; then
  pass "R1-R9 + A4: every refusal answers its own exit code —$R_DETAIL — leaves the whole tree byte-for-byte as it found it (find + per-file md5), and prints what would clear it"
else
  fail_ "R1-R9" "expected rc 3/4/5/5/3/4/6/7/8 with an unchanged tree and a remedy line; got:$R_DETAIL"
fi

if [ "$R_TAGS_OK" = y ]; then
  pass "R10: not one of those nine refusals created a tag — asserted on the repository's tag set, which the working-tree manifest above is structurally blind to"
else
  fail_ "R10" "a refusal created a tag:$R_DETAIL"
fi

# ── R2 detail: the retro refusal NAMES the delta, its due_by and how late ────
P="$RT/retro-msg"; mk_proj "$P"; tag_at "$P" "v1.2.0"; _s_open_retro "$P"
run_cut "$REPO_ROOT/scripts" "$P"
r2_named=y
case "$CUT_OUT" in *DELTA-007*) : ;; *) r2_named=n ;; esac
case "$CUT_OUT" in *"$(stamp_ago 2)"*) : ;; *) r2_named=n ;; esac
case "$CUT_OUT" in *"2 day"*) : ;; *) r2_named=n ;; esac
if [ "$r2_named" = y ] && [ "$CUT_RC" -eq 4 ]; then
  pass "R2: the open-retro refusal (rc $CUT_RC) names the delta, its due_by and how overdue it is — §9.2's three things, from WP5's delta_retro_rows and not re-derived here"
else
  fail_ "R2" "rc=$CUT_RC (want 4); message did not name all three (id / due_by / days overdue). Output was: $CUT_OUT"
fi

# ── R4 detail: the UNMEASURABLE cadence is a refusal, and the report names it ─
P="$RT/cad2-msg"; mk_proj "$P"; tag_at "$P" "v1.2.0"; _s_cadence_2 "$P"
run_cut "$REPO_ROOT/scripts" "$P"
r4_named=n
case "$CUT_OUT" in *"COULD NOT BE MEASURED"*) r4_named=y ;; esac
if [ "$CUT_RC" -eq 5 ] && [ "$r4_named" = y ]; then
  pass "R4: an UNMEASURABLE cadence refuses (rc $CUT_RC) and the checker's own report — which names each arm that could not be read — is surfaced verbatim rather than collapsed into a headline"
else
  fail_ "R4" "rc=$CUT_RC (want 5); the unmeasurable arms were named=$r4_named. Output was: $CUT_OUT"
fi
rm -rf "$RT"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== S — semver, decided by the TOOL (§9.1) ==="
# ════════════════════════════════════════════════════════════════════════════

# _cut_ok <name> <closed-json> [policy-json] [reval-rc] — a fixture that should
#   CUT, run against a private scripts tree with a recording revalidation stub.
#   Sets CUT_RC / CUT_OUT, and NEW_TAG to the tag that appeared (or "").
NEW_TAG=""
REVAL_LOG=""
_cut_ok() {
  local name="$1" closed="$2" policy="${3:-}" reval="${4:-0}" P SD before_tags after_tags
  P="$ST/$name"; SD="$ST/$name-scripts"
  mk_proj "$P"; tag_at "$P" "v1.2.0"
  write_state "$P" "$(state_doc 'null' '[]' "$closed")"
  [ -z "$policy" ] || printf '%s\n' "$policy" > "$P/.claude/delta-policy.json"
  mk_scripts_tree "$SD"; stub_revalidation "$SD/scripts" "$reval"
  REVAL_LOG="$ST/$name.reval"; : > "$REVAL_LOG"
  before_tags="$(tag_list "$P")"
  CUT_RC=0
  CUT_OUT="$( cd "$P" && unset GITHUB_BASE_REF; WP7_REVALIDATION_LOG="$REVAL_LOG" \
      bash "$SD/scripts/cut-release.sh" </dev/null 2>&1 )" || CUT_RC=$?
  after_tags="$(tag_list "$P")"
  NEW_TAG="$(printf '%s\n%s\n' "$before_tags" "$after_tags" | LC_ALL=C sort | uniq -u | tr -d ' ')"
  CUT_PROJ="$P"
  return 0
}

ST=$(mktemp -d)

_cut_ok minor "[$(closed_row DELTA-008 fix),$(closed_row DELTA-009 feature)]"
if [ "$CUT_RC" -eq 0 ] && [ "$NEW_TAG" = "v1.3.0" ]; then
  pass "S1: a feature closed alongside a fix yields a MINOR bump — v1.2.0 -> $NEW_TAG (rc $CUT_RC)"
else
  fail_ "S1" "rc=$CUT_RC (want 0), new tag='$NEW_TAG' (want v1.3.0). Output: $CUT_OUT"
fi

_cut_ok patch "[$(closed_row DELTA-008 fix),$(closed_row DELTA-010 hotfix)]"
if [ "$CUT_RC" -eq 0 ] && [ "$NEW_TAG" = "v1.2.1" ]; then
  pass "S2: fixes and hotfixes only yield a PATCH bump — v1.2.0 -> $NEW_TAG (rc $CUT_RC)"
else
  fail_ "S2" "rc=$CUT_RC (want 0), new tag='$NEW_TAG' (want v1.2.1). Output: $CUT_OUT"
fi

_cut_ok major "[$(closed_row DELTA-008 fix),$(closed_row DELTA-011 feature true)]" "" 0
s3_reval="$(wc -l < "$REVAL_LOG" | tr -d ' ')"
if [ "$CUT_RC" -eq 0 ] && [ "$NEW_TAG" = "v2.0.0" ] && [ "$s3_reval" -ge 1 ]; then
  pass "S3: a breaking marker yields a MAJOR bump — v1.2.0 -> $NEW_TAG — AND §8.2's full run-phase3-validation.sh re-run was genuinely INVOKED ($s3_reval recorded invocation(s)), proven by a recording stub rather than by reading the source"
else
  fail_ "S3" "rc=$CUT_RC (want 0), new tag='$NEW_TAG' (want v2.0.0), revalidation invocations=$s3_reval (want >= 1). Output: $CUT_OUT"
fi

# S4 — the revalidation FAILS. "Before the tag is written" (§8.2) has to mean
# before the CHANGELOG too, or the failure leaves the worse state §9.2 names.
P4="$ST/major-fail"; SD4="$ST/major-fail-scripts"
mk_proj "$P4"; tag_at "$P4" "v1.2.0"
write_state "$P4" "$(state_doc 'null' '[]' "[$(closed_row DELTA-011 feature true)]")"
mk_scripts_tree "$SD4"; stub_revalidation "$SD4/scripts" 1
s4_before="$(tree_manifest "$P4")"; s4_tags_before="$(tag_list "$P4")"
CUT_RC=0
CUT_OUT="$( cd "$P4" && unset GITHUB_BASE_REF; bash "$SD4/scripts/cut-release.sh" </dev/null 2>&1 )" || CUT_RC=$?
s4_after="$(tree_manifest "$P4")"; s4_tags_after="$(tag_list "$P4")"
if [ "$CUT_RC" -eq 10 ] && [ "$s4_before" = "$s4_after" ] && [ "$s4_tags_before" = "$s4_tags_after" ]; then
  pass "S4: a major bump whose §8.2 revalidation FAILS refuses at rc $CUT_RC with the whole tree and the tag set both unmoved — 'before the tag is written' includes before the changelog"
else
  fail_ "S4" "rc=$CUT_RC (want 10); tree moved=$([ "$s4_before" = "$s4_after" ] && echo n || echo y); tagged=$([ "$s4_tags_before" = "$s4_tags_after" ] && echo n || echo y)"
fi

# S5 — the MAP is retunable (§9.1: "the map lives in delta-policy.json::semver
# so a project can retune the class->bump mapping").
_cut_ok retuned "[$(closed_row DELTA-008 fix)]" '{"schemaVersion":1,"semver":{"feature":"minor","fix":"minor","hotfix":"patch","security-patch":"patch","breaking":"major"}}'
if [ "$CUT_RC" -eq 0 ] && [ "$NEW_TAG" = "v1.3.0" ]; then
  pass "S5: the class->bump MAP is project-retunable — with semver.fix = minor the same fixes-only set cuts $NEW_TAG instead of v1.2.1 (rc $CUT_RC)"
else
  fail_ "S5" "rc=$CUT_RC (want 0), new tag='$NEW_TAG' (want v1.3.0 from the retuned map). Output: $CUT_OUT"
fi

# S6 — the PRECEDENCE is machinery. THREE arms, because two of them alone would
# be satisfied by an implementation that reads a key nobody has written yet: the
# answer is invariant under row ORDER, AND a policy file that actively TRIES to
# reorder it is ignored. The third arm is the one that would catch a future
# "configurable precedence" being added quietly — asserting the key is absent
# from the source would only catch it being added with that exact spelling.
_cut_ok order-a "[$(closed_row DELTA-008 feature),$(closed_row DELTA-009 fix)]"
s6_a="$NEW_TAG"; s6_a_rc="$CUT_RC"
_cut_ok order-b "[$(closed_row DELTA-008 fix),$(closed_row DELTA-009 feature)]"
s6_b="$NEW_TAG"; s6_b_rc="$CUT_RC"
_cut_ok reorder-attempt "[$(closed_row DELTA-008 fix),$(closed_row DELTA-009 feature)]" \
  '{"schemaVersion":1,"semver":{"feature":"minor","fix":"patch","hotfix":"patch","security-patch":"patch","breaking":"major"},"semver_precedence":["patch","minor","major"],"precedence":["patch","minor","major"]}'
s6_c="$NEW_TAG"; s6_c_rc="$CUT_RC"
if [ "$s6_a" = "v1.3.0" ] && [ "$s6_b" = "v1.3.0" ] && [ "$s6_c" = "v1.3.0" ] \
   && [ "$s6_a_rc" -eq 0 ] && [ "$s6_b_rc" -eq 0 ] && [ "$s6_c_rc" -eq 0 ]; then
  pass "S6: the PRECEDENCE is machinery, not policy — the same feature+fix set answers $s6_a with either row order, and a policy file that explicitly asks for patch-beats-minor-beats-major is ignored ($s6_c, not v1.2.1). §9.1: a project that could reorder this could make a feature release a patch"
else
  fail_ "S6" "order A -> '$s6_a' (rc $s6_a_rc), order B -> '$s6_b' (rc $s6_b_rc), reorder attempt -> '$s6_c' (rc $s6_c_rc); all three want v1.3.0"
fi

# S7 — no tag at all: the base is 0.0.0.
P7="$ST/no-tag"; SD7="$ST/no-tag-scripts"
mk_proj "$P7"
write_state "$P7" "$(state_doc 'null' '[]' "[$(closed_row DELTA-008 feature)]")"
mk_scripts_tree "$SD7"; stub_revalidation "$SD7/scripts" 0
CUT_RC=0
CUT_OUT="$( cd "$P7" && unset GITHUB_BASE_REF; bash "$SD7/scripts/cut-release.sh" </dev/null 2>&1 )" || CUT_RC=$?
s7_tag="$(tag_list "$P7" | tr -d ' ')"
if [ "$CUT_RC" -eq 0 ] && [ "$s7_tag" = "v0.1.0" ]; then
  pass "S7: a repository with NO tag at all bases the arithmetic at 0.0.0 — a feature cuts $s7_tag (rc $CUT_RC)"
else
  fail_ "S7" "rc=$CUT_RC (want 0), tag='$s7_tag' (want v0.1.0). Output: $CUT_OUT"
fi

# S8 — an unmappable class is FAIL-CLOSED. Under-bumping is the dangerous
# direction (a breaking change shipped as a patch), so an unknown class refuses
# rather than defaulting.
P8="$ST/unmapped"; mk_proj "$P8"; tag_at "$P8" "v1.2.0"
write_state "$P8" "$(state_doc 'null' '[]' '[{"id":"DELTA-012","class":"experiment","severity":null,"closed_at":"2026-08-01T00:00:00Z","shipped_in":null}]')"
s8_before="$(tree_manifest "$P8")"; s8_tags_before="$(tag_list "$P8")"
run_cut "$REPO_ROOT/scripts" "$P8"
s8_after="$(tree_manifest "$P8")"; s8_tags_after="$(tag_list "$P8")"
if [ "$CUT_RC" -eq 9 ] && [ "$s8_before" = "$s8_after" ] && [ "$s8_tags_before" = "$s8_tags_after" ]; then
  pass "S8: a closed row whose class maps to no bump refuses at rc $CUT_RC with nothing written — fail-closed, because the alternative is a class nobody scored shipping as a patch"
else
  fail_ "S8" "rc=$CUT_RC (want 9); tree moved=$([ "$s8_before" = "$s8_after" ] && echo n || echo y)"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== P — changelog promotion (§9.3): categories verbatim, no prose ==="
# ════════════════════════════════════════════════════════════════════════════

PP="$ST/promote"; SDP="$ST/promote-scripts"
mk_proj "$PP"; tag_at "$PP" "v1.2.0"
write_state "$PP" "$(state_doc 'null' '[]' "[$(closed_row DELTA-008 fix)]")"
# Put real content under two of the eight headings, so P3 can prove the tool
# MOVED the operator's prose rather than rewriting or dropping it.
awk '{ print }
  /^### Added$/ { print "- dark mode" }
  /^### Fixed$/ { print "- the thing that was broken" }' "$PP/CHANGELOG.md" > "$PP/CHANGELOG.md.new"
mv "$PP/CHANGELOG.md.new" "$PP/CHANGELOG.md"
CL_BEFORE="$(cat "$PP/CHANGELOG.md")"
mk_scripts_tree "$SDP"; stub_revalidation "$SDP/scripts" 0
CUT_RC=0
CUT_OUT="$( cd "$PP" && unset GITHUB_BASE_REF; bash "$SDP/scripts/cut-release.sh" </dev/null 2>&1 )" || CUT_RC=$?
CL_AFTER="$(cat "$PP/CHANGELOG.md")"
TODAY="$(today_utc)"

# P1 — the two headings, in the right order.
p1_unrel_line="$(printf '%s\n' "$CL_AFTER" | grep -n '^## \[Unreleased\]' | head -1 | cut -d: -f1)"
p1_ver_line="$(printf '%s\n' "$CL_AFTER" | grep -n "^## \[1\.2\.1\] " | head -1 | cut -d: -f1)"
p1_unrel_n="$(printf '%s\n' "$CL_AFTER" | grep -c '^## \[Unreleased\]' || true)"
if [ -n "$p1_unrel_line" ] && [ -n "$p1_ver_line" ] && [ "$p1_unrel_line" -lt "$p1_ver_line" ] \
   && [ "$p1_unrel_n" -eq 1 ] \
   && printf '%s\n' "$CL_AFTER" | grep -q "^## \[1\.2\.1\] — $TODAY\$"; then
  pass "P1: '## [Unreleased]' became '## [1.2.1] — $TODAY' (line $p1_ver_line) and exactly one FRESH '## [Unreleased]' now sits above it (line $p1_unrel_line)"
else
  fail_ "P1" "unreleased at line '$p1_unrel_line' (count $p1_unrel_n), version heading at '$p1_ver_line'; wanted one Unreleased strictly above '## [1.2.1] — $TODAY'"
fi

# P2 — all eight template categories, in template order, in the FRESH block.
TMPL_CATS="$(grep '^### ' "$REPO_ROOT/templates/generated/changelog.tmpl")"
FRESH_BLOCK="$(printf '%s\n' "$CL_AFTER" | awk '/^## \[Unreleased\]/ { on = 1; next } /^## \[/ && on { on = 0 } on { print }')"
FRESH_CATS="$(printf '%s\n' "$FRESH_BLOCK" | grep '^### ' || true)"
if [ "$FRESH_CATS" = "$TMPL_CATS" ]; then
  pass "P2: the fresh block carries all eight categories from templates/generated/changelog.tmpl, verbatim and in template order — compared against the template's own bytes, not against a list retyped here"
else
  fail_ "P2" "fresh categories differ from the template's. Got: $(printf '%s' "$FRESH_CATS" | tr '\n' '/'); want: $(printf '%s' "$TMPL_CATS" | tr '\n' '/')"
fi

# P3 — the promoted body is byte-identical to the old Unreleased body.
OLD_BODY="$(printf '%s\n' "$CL_BEFORE" | awk '/^## \[Unreleased\]/ { on = 1; next } /^## \[/ && on { on = 0 } on { print }')"
NEW_BODY="$(printf '%s\n' "$CL_AFTER" | awk '/^## \[1\.2\.1\] / { on = 1; next } /^## \[/ && on { on = 0 } on { print }')"
if [ "$OLD_BODY" = "$NEW_BODY" ]; then
  pass "P3: the promoted section's body is BYTE-IDENTICAL to what was under '## [Unreleased]' before — the operator's two entries moved with it and the tool wrote no prose of its own"
else
  fail_ "P3" "the promoted body differs from the original Unreleased body"
fi

# P4 — the fresh block is empty of prose. STRUCTURAL: every non-blank line in it
# is a `### ` heading. Asserting "does not contain 'dark mode'" would pass for a
# tool that invented some OTHER sentence.
p4_extra="$(printf '%s\n' "$FRESH_BLOCK" | grep -v '^### ' | grep -v '^[[:space:]]*$' || true)"
if [ -z "$p4_extra" ]; then
  pass "P4: the fresh '## [Unreleased]' block contains nothing but its category headings — asserted structurally (every non-blank line is a '### ' heading), which also refuses a sentence the tool invented rather than copied"
else
  fail_ "P4" "the fresh block carries non-heading content: $(printf '%s' "$p4_extra" | tr '\n' '/')"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T — the tag: EXACTLY vMAJOR.MINOR.PATCH (§9.3 + C7) ==="
# ════════════════════════════════════════════════════════════════════════════

t1_tags="$(tag_list "$PP")"
t1_new="$(printf '%s\n' "$t1_tags" | grep -v '^v1\.2\.0$' || true)"
t1_n="$(printf '%s\n' "$t1_new" | grep -c . || true)"
t1_shape=n
printf '%s\n' "$t1_new" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' && t1_shape=y
if [ "$CUT_RC" -eq 0 ] && [ "$t1_n" -eq 1 ] && [ "$t1_shape" = y ]; then
  pass "T1: the cut created EXACTLY ONE new tag ('$t1_new') and it matches /^v[0-9]+\\.[0-9]+\\.[0-9]+\$/ — GitLab's release lanes match that regex while GitHub's and Bitbucket's match 'v*', so a pre-release suffix would build on two hosts and silently do nothing on the third"
else
  fail_ "T1" "rc=$CUT_RC; new tags=$t1_n ('$t1_new'); shape ok=$t1_shape"
fi

t2_tagsha="$( cd "$PP" && git rev-parse "$t1_new^{commit}" 2>/dev/null )"
t2_head="$( cd "$PP" && git rev-parse HEAD 2>/dev/null )"
if [ -n "$t2_tagsha" ] && [ "$t2_tagsha" = "$t2_head" ]; then
  pass "T2: the tag names the tip of the current branch ($t2_head)"
else
  fail_ "T2" "tag commit '$t2_tagsha' != HEAD '$t2_head'"
fi

t3_remotes="$( cd "$PP" && git remote 2>/dev/null | grep -c . || true)"
if [ "$t3_remotes" -eq 0 ] && [ "$CUT_RC" -eq 0 ]; then
  pass "T3: the fixture has NO git remote at all and the cut still succeeded (rc $CUT_RC) — the tool creates a LOCAL tag and pushes nothing, so no test here can leak a real remote"
else
  fail_ "T3" "remotes=$t3_remotes (want 0), rc=$CUT_RC (want 0)"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== W — shipped_in, through WP2's write-once ship pathway (§7.1) ==="
# ════════════════════════════════════════════════════════════════════════════

PW="$ST/ship"; SDW="$ST/ship-scripts"
mk_proj "$PW"; tag_at "$PW" "v1.2.0"
write_state "$PW" "$(state_doc 'null' '[]' "[$(closed_row DELTA-006 fix false v1.2.0),$(closed_row DELTA-008 fix),$(closed_row DELTA-009 feature)]")"
mk_scripts_tree "$SDW"; stub_revalidation "$SDW/scripts" 0
CUT_RC=0
CUT_OUT="$( cd "$PW" && unset GITHUB_BASE_REF; bash "$SDW/scripts/cut-release.sh" </dev/null 2>&1 )" || CUT_RC=$?
w1_006="$(jq -r '.closed[] | select(.id=="DELTA-006") | .shipped_in' "$PW/.claude/delta-state.json" 2>/dev/null)"
w1_008="$(jq -r '.closed[] | select(.id=="DELTA-008") | .shipped_in' "$PW/.claude/delta-state.json" 2>/dev/null)"
w1_009="$(jq -r '.closed[] | select(.id=="DELTA-009") | .shipped_in' "$PW/.claude/delta-state.json" 2>/dev/null)"
if [ "$CUT_RC" -eq 0 ] && [ "$w1_006" = "v1.2.0" ] && [ "$w1_008" = "v1.3.0" ] && [ "$w1_009" = "v1.3.0" ]; then
  pass "W1: both unshipped rows now carry the new tag (DELTA-008=$w1_008, DELTA-009=$w1_009) and the row already shipped in v1.2.0 was left exactly as it was (DELTA-006=$w1_006)"
else
  fail_ "W1" "rc=$CUT_RC; DELTA-006='$w1_006' (want v1.2.0), DELTA-008='$w1_008' / DELTA-009='$w1_009' (want v1.3.0). Output: $CUT_OUT"
fi

w2_before="$(_md5file "$PW/.claude/delta-state.json")"
CUT_RC=0
CUT_OUT="$( cd "$PW" && unset GITHUB_BASE_REF; bash "$SDW/scripts/cut-release.sh" </dev/null 2>&1 )" || CUT_RC=$?
w2_after="$(_md5file "$PW/.claude/delta-state.json")"
if [ "$CUT_RC" -eq 8 ] && [ "$w2_before" = "$w2_after" ]; then
  pass "W2: a second cut over the same record refuses with 'nothing to release' (rc $CUT_RC) and rewrites not one byte of the state file — shipped_in is write-once, which is what makes the audit tail worth reading"
else
  fail_ "W2" "rc=$CUT_RC (want 8); state file md5 $w2_before -> $w2_after"
fi

# W3 — THE SHIP PATHWAY IS THE ONLY ROUTE (§7.1's single-writer rule).
#
# THE DECISIVE ARM IS FUNCTIONAL, NOT A GREP, and the first draft of this row is
# why: a grep for `delta-state.json` near a `>` matched the REMEDY SENTENCE in a
# refusal message ("...the tag and .claude/delta-state.json disagree..." >&2) and
# reported a direct write that does not exist. A pattern that cannot tell a
# filename in prose from a filename in a redirection is not an instrument.
#
# So the seam's SHIP ACTION is replaced by a shim that refuses, and the question
# becomes empirical: with the only sanctioned route closed, does the state file
# move at all? If cut-release.sh had any second path to that file — a `jq`, a
# redirect, a `mv` — the bytes would change. They must not.
PS="$ST/ship-blocked"; SDS="$ST/ship-blocked-scripts"
mk_proj "$PS"; tag_at "$PS" "v1.2.0"
write_state "$PS" "$(state_doc 'null' '[]' "[$(closed_row DELTA-008 fix)]")"
mk_scripts_tree "$SDS"; stub_revalidation "$SDS/scripts" 0
mv "$SDS/scripts/process-checklist.sh" "$SDS/scripts/process-checklist-real.sh"
cat > "$SDS/scripts/process-checklist.sh" <<'SEAM_SHIM_EOF'
#!/usr/bin/env bash
# WP7 test shim — delegates every seam action EXCEPT the ship write, which it
# refuses. Anything that still reaches the state file is doing so some other way.
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "${1:-}" = "--delta-state-ship" ]; then exit 1; fi
exec bash "$D/process-checklist-real.sh" "$@"
SEAM_SHIM_EOF
chmod +x "$SDS/scripts/process-checklist.sh"
w3_before="$(_md5file "$PS/.claude/delta-state.json")"
CUT_RC=0
CUT_OUT="$( cd "$PS" && unset GITHUB_BASE_REF; bash "$SDS/scripts/cut-release.sh" </dev/null 2>&1 )" || CUT_RC=$?
w3_after="$(_md5file "$PS/.claude/delta-state.json")"
w3_tags="$(tag_list "$PS" | grep -v '^v1\.2\.0$' || true)"
# The narrowed structural arm, kept as a second opinion: a REDIRECTION or an
# in-place rewrite naming the state file, on an executed line.
w3_direct="$(grep -vE '^[[:space:]]*#' "$CUTREL" \
  | grep -nE '(>[[:space:]]*"?[^"]*delta-state\.json|(^|[^[:alnum:]_])(mv|cp|rm|tee|jq)[[:space:]][^|]*delta-state\.json)' || true)"
w3_ship="$(grep -c -- '--delta-state-ship' "$CUTREL" || true)"
case "$w3_ship" in ''|*[!0-9]*) w3_ship=0 ;; esac
if [ "$CUT_RC" -eq 11 ] && [ "$w3_before" = "$w3_after" ] && [ -z "$w3_tags" ] \
   && [ -z "$w3_direct" ] && [ "$w3_ship" -ge 1 ]; then
  pass "W3: with the seam's ship action shimmed to refuse, the cut stops at rc $CUT_RC, creates no tag, and the state file is byte-identical ($w3_before) — there is no second route to it. The seam is named $w3_ship time(s) and no executed line redirects, mv's or jq-rewrites onto the file"
else
  fail_ "W3" "rc=$CUT_RC (want 11); state md5 $w3_before -> $w3_after; new tags='$w3_tags'; direct writes='$w3_direct'; --delta-state-ship references=$w3_ship"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== A — adjacencies and constraints (C8, §13-R2, §3.1/§3.3) ==="
# ════════════════════════════════════════════════════════════════════════════

# A1 — C8/Q3: `--finalize-phase 4` is the natural pre-tag check and Karl did
# NOT decide to wire it. Executed lines only; the header names it in prose on
# purpose, which is the adjacency record.
a1_exec="$(grep -n 'finalize-phase' "$CUTREL" | grep -v '^[0-9]*:[[:space:]]*#' || true)"
if [ -z "$a1_exec" ]; then
  pass "A1: --finalize-phase is not wired — no EXECUTED line in cut-release.sh names it (C8/Q3: it is the natural pre-tag check and Karl did not decide it, so it is recorded as an adjacency in the header and nowhere else)"
else
  fail_ "A1" "an executed line names finalize-phase: $a1_exec"
fi

# A2 — §9.1/§13-R2: there is no override, and the cost is recorded rather than
# quietly patched. Asserted by EXECUTION on four spellings, not by grep.
a2_detail=""; a2_ok=y
PA="$ST/override"; mk_proj "$PA"; tag_at "$PA" "v1.2.0"
write_state "$PA" "$(state_doc 'null' '[]' "[$(closed_row DELTA-008 fix)]")"
for flag in --major --minor --patch "--version=2.0.0" --bump; do
  a2_tags_before="$(tag_list "$PA")"
  run_cut "$REPO_ROOT/scripts" "$PA" "$flag"
  a2_tags_after="$(tag_list "$PA")"
  a2_detail="$a2_detail [$flag=rc$CUT_RC]"
  [ "$CUT_RC" -eq 2 ] || a2_ok=n
  [ "$a2_tags_before" = "$a2_tags_after" ] || { a2_ok=n; a2_detail="$a2_detail(TAGGED)"; }
done
if [ "$a2_ok" = y ]; then
  pass "A2: there is NO semver override in v1 —$a2_detail — every spelling is an invocation error (rc 2) that tags nothing. The cost of that decision is real and is recorded at §13-R2, not smoothed over with a flag"
else
  fail_ "A2" "expected rc 2 and no tag for every override spelling; got:$a2_detail"
fi

# A3 — §3.1: cut-release.sh is a DELTA-MODULE file despite its core-sounding
# name, and the seam allowlist stays at cardinality one.
a3_rc=0
a3_out="$( cd "$REPO_ROOT" && bash scripts/lint-delta-boundary.sh --list </dev/null 2>&1 )" || a3_rc=$?
a3_card="$(printf '%s\n' "$a3_out" | grep -c 'cardinality 1/1' || true)"
case "$a3_card" in ''|*[!0-9]*) a3_card=0 ;; esac
a3_manifest=n
grep -q '"scripts/cut-release.sh"' "$REPO_ROOT/scripts/lint-delta-boundary.sh" && a3_manifest=y
if [ "$a3_rc" -eq 0 ] && [ "$a3_card" -ge 1 ] && [ "$a3_manifest" = y ]; then
  pass "A3: the boundary lint is clean (rc $a3_rc) with cut-release.sh present, it is in the DELTA manifest (not CORE — it reads delta-state.json, so classifying it as core would create a second core->delta edge), and the seam allowlist is still cardinality 1/1"
else
  fail_ "A3" "lint rc=$a3_rc (want 0); cardinality-1 rows=$a3_card; in DELTA manifest=$a3_manifest"
fi

rm -rf "$ST"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== M — mutation proofs (each mutant is BUILT and RUN here) ==="
# ════════════════════════════════════════════════════════════════════════════

# _mutate <name> <marker> <sed-expr> <check-fn>
#   Copy scripts/ into a private tree, change the ONE line carrying <marker>,
#   report sites / changed / lines, then hand the tree to <check-fn>. The
#   report is printed whether the mutant is killed or not: a mutation that
#   changed nothing is a green row that proved nothing, and that is the failure
#   mode this harness exists to make visible.
MT=""
_mutate() {
  local name="$1" marker="$2" expr="$3" check="$4" SD rep sites changed lines mode_before mode_after
  SD="$MT/$name"
  mk_scripts_tree "$SD"
  stub_revalidation "$SD/scripts" 0
  mode_before="$(_mode_of "$SD/scripts/cut-release.sh")"
  cp "$SD/scripts/cut-release.sh" "$MT/$name.orig"
  _sed_inplace "$SD/scripts/cut-release.sh" "$expr"
  mode_after="$(_mode_of "$SD/scripts/cut-release.sh")"
  rep="$(_mutation_report "$MT/$name.orig" "$SD/scripts/cut-release.sh" "$marker")"
  sites="${rep%%|*}"; rep="${rep#*|}"; changed="${rep%%|*}"; lines="${rep##*|}"
  MUT_REPORT="marker '$marker' sites=$sites, changed=$changed, diff-lines=$lines, mode $mode_before -> $mode_after"
  MUT_SD="$SD/scripts"
  if [ "$sites" -ne 1 ] || [ "$changed" != y ] || [ "$lines" -ne 2 ] || [ "$mode_before" != "$mode_after" ]; then
    fail_ "$name (harness)" "the mutation is not anchored/single-line/mode-preserving: $MUT_REPORT"
    return 0
  fi
  "$check" "$name"
  return 0
}

MT=$(mktemp -d)

# ── m1: suppress the open-retro refusal ─────────────────────────────────────
_m1_check() {
  local name="$1" P rc tags_before tags_after
  P="$MT/$name-proj"; mk_proj "$P"; tag_at "$P" "v1.2.0"
  write_state "$P" "$(state_doc 'null' "[$(open_retro DELTA-007 2)]" "[$(closed_row DELTA-008 fix)]")"
  tags_before="$(tag_list "$P")"
  rc=0
  ( cd "$P" && unset GITHUB_BASE_REF; bash "$MUT_SD/cut-release.sh" </dev/null >/dev/null 2>&1 ) || rc=$?
  tags_after="$(tag_list "$P")"
  if [ "$rc" -eq 0 ] && [ "$tags_before" != "$tags_after" ]; then
    pass "m1: with the open-retro refusal neutered the mutant CUTS A RELEASE over an unfiled retro (rc $rc, a new tag appeared) — R2 sees it. $MUT_REPORT"
  else
    fail_ "m1" "the mutant still refused (rc $rc, tags unchanged=$([ "$tags_before" = "$tags_after" ] && echo y || echo n)) — R2 cannot see this line. $MUT_REPORT"
  fi
}
_mutate m1 '# CUTREL-REFUSE-RETRO$' 's|^\(.*# CUTREL-REFUSE-RETRO\)$|  if false; then :; fi   # CUTREL-REFUSE-RETRO|' _m1_check

# ── m2: emit a pre-release suffix (the C7 defence) ──────────────────────────
_m2_check() {
  local name="$1" P rc newtag
  P="$MT/$name-proj"; mk_proj "$P"; tag_at "$P" "v1.2.0"
  write_state "$P" "$(state_doc 'null' '[]' "[$(closed_row DELTA-008 fix)]")"
  rc=0
  ( cd "$P" && unset GITHUB_BASE_REF; bash "$MUT_SD/cut-release.sh" </dev/null >/dev/null 2>&1 ) || rc=$?
  newtag="$(tag_list "$P" | grep -v '^v1\.2\.0$' || true)"
  if ! printf '%s\n' "$newtag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
    pass "m2: with the tag-format line emitting a pre-release suffix, the mutant produces no conforming tag (rc $rc, new tag '$newtag') — T1 sees it, and that tag is exactly the one GitLab's /^v\\d+\\.\\d+\\.\\d+\$/ lane would silently ignore while GitHub and Bitbucket built it. $MUT_REPORT"
  else
    fail_ "m2" "the mutant still produced a conforming tag '$newtag' — T1 cannot see this line. $MUT_REPORT"
  fi
}
_mutate m2 '# CUTREL-TAG-FORMAT$' 's|^\(.*\)# CUTREL-TAG-FORMAT$|  TAG="v${NEXT_MAJOR}.${NEXT_MINOR}.${NEXT_PATCH}-rc1"   # CUTREL-TAG-FORMAT|' _m2_check

# ── m3: collapse the checker's rc 2 into a pass ─────────────────────────────
_m3_check() {
  local name="$1" P rc tags_before tags_after
  P="$MT/$name-proj"; mk_proj "$P"; tag_at "$P" "v1.2.0"
  write_state "$P" "$(state_doc 'null' '[]' "[$(closed_row DELTA-008 fix)]")"
  rm -f "$P"/docs/test-results/*
  printf 'scan artefact\n' > "$P/docs/test-results/2026-13-45_semgrep_pass.txt"
  tags_before="$(tag_list "$P")"
  rc=0
  ( cd "$P" && unset GITHUB_BASE_REF; bash "$MUT_SD/cut-release.sh" </dev/null >/dev/null 2>&1 ) || rc=$?
  tags_after="$(tag_list "$P")"
  if [ "$rc" -eq 0 ] && [ "$tags_before" != "$tags_after" ]; then
    pass "m3: with rc 2 collapsed into a pass the mutant CUTS over a cadence nobody could measure (rc $rc, a new tag appeared) — R4 sees it. This is BL-213's fail-open one level up: WP6 stopped the checker lying, and this line is what stops the release believing a lie it was never told. $MUT_REPORT"
  else
    fail_ "m3" "the mutant still refused (rc $rc) — R4 cannot see this line. $MUT_REPORT"
  fi
}
_mutate m3 '# CUTREL-CADENCE-UNMEASURABLE$' 's|^\(.*\)# CUTREL-CADENCE-UNMEASURABLE$|    2) CADENCE_REFUSE=n ;;   # CUTREL-CADENCE-UNMEASURABLE|' _m3_check

# ── m4: reorder the semver precedence ───────────────────────────────────────
_m4_check() {
  local name="$1" P rc newtag
  P="$MT/$name-proj"; mk_proj "$P"; tag_at "$P" "v1.2.0"
  write_state "$P" "$(state_doc 'null' '[]' "[$(closed_row DELTA-008 fix),$(closed_row DELTA-009 feature)]")"
  rc=0
  ( cd "$P" && unset GITHUB_BASE_REF; bash "$MUT_SD/cut-release.sh" </dev/null >/dev/null 2>&1 ) || rc=$?
  newtag="$(tag_list "$P" | grep -v '^v1\.2\.0$' || true)"
  if [ "$newtag" != "v1.3.0" ]; then
    pass "m4: with the precedence ranking reordered, the same feature+fix set no longer cuts a minor (rc $rc, new tag '$newtag' instead of v1.3.0) — S1/S6 see it. §9.1: a project that could reorder this could make a feature release a patch. $MUT_REPORT"
  else
    fail_ "m4" "the mutant still cut v1.3.0 — S1/S6 cannot see this line. $MUT_REPORT"
  fi
}
_mutate m4 '# CUTREL-SEMVER-PRECEDENCE$' 's|^\(.*\)# CUTREL-SEMVER-PRECEDENCE$|_cutrel_rank() { case "${1:-}" in major) printf 3 ;; minor) printf 0 ;; *) printf 1 ;; esac; }   # CUTREL-SEMVER-PRECEDENCE|' _m4_check

# ── m5: suppress the open-delta refusal ─────────────────────────────────────
_m5_check() {
  local name="$1" P rc tags_before tags_after
  P="$MT/$name-proj"; mk_proj "$P"; tag_at "$P" "v1.2.0"
  write_state "$P" "$(state_doc "$ACTIVE_JSON" '[]' "[$(closed_row DELTA-008 fix)]")"
  tags_before="$(tag_list "$P")"
  rc=0
  ( cd "$P" && unset GITHUB_BASE_REF; bash "$MUT_SD/cut-release.sh" </dev/null >/dev/null 2>&1 ) || rc=$?
  tags_after="$(tag_list "$P")"
  if [ "$rc" -eq 0 ] && [ "$tags_before" != "$tags_after" ]; then
    pass "m5: with the open-delta refusal neutered the mutant cuts a release in the middle of DELTA-009 (rc $rc, a new tag appeared) — R1/R5 see it. $MUT_REPORT"
  else
    fail_ "m5" "the mutant still refused (rc $rc) — R1/R5 cannot see this line. $MUT_REPORT"
  fi
}
_mutate m5 '# CUTREL-REFUSE-ACTIVE$' 's|^\(.*# CUTREL-REFUSE-ACTIVE\)$|  if false; then :; fi   # CUTREL-REFUSE-ACTIVE|' _m5_check

# ── m7: neuter the major revalidation ───────────────────────────────────────
_m7_check() {
  local name="$1" P rc log newtag n
  P="$MT/$name-proj"; mk_proj "$P"; tag_at "$P" "v1.2.0"
  write_state "$P" "$(state_doc 'null' '[]' "[$(closed_row DELTA-011 feature true)]")"
  log="$MT/$name.reval"; : > "$log"
  rc=0
  ( cd "$P" && unset GITHUB_BASE_REF; WP7_REVALIDATION_LOG="$log" \
      bash "$MUT_SD/cut-release.sh" </dev/null >/dev/null 2>&1 ) || rc=$?
  n="$(wc -l < "$log" | tr -d ' ')"
  newtag="$(tag_list "$P" | grep -v '^v1\.2\.0$' || true)"
  if [ "$n" -eq 0 ] && [ "$newtag" = "v2.0.0" ]; then
    pass "m7: with the §8.2 revalidation neutered the mutant cuts the major release ($newtag, rc $rc) having invoked run-phase3-validation.sh $n times — S3 sees it, because S3 asserts on a RECORDED invocation and not on the presence of a call in the source. $MUT_REPORT"
  else
    fail_ "m7" "the mutant still revalidated ($n invocation(s)) or did not cut ('$newtag') — S3 cannot see this line. $MUT_REPORT"
  fi
}
_mutate m7 '# CUTREL-MAJOR-REVALIDATE$' 's|^\(.*# CUTREL-MAJOR-REVALIDATE\)$|  if false; then :; fi   # CUTREL-MAJOR-REVALIDATE|' _m7_check

rm -rf "$MT"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
