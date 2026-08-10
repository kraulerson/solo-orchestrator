#!/usr/bin/env bash
# tests/test-delta-db-ledger-close.sh — Delta Track D-B: THE RELEASE CUT CLOSES
# THE LEDGER ROWS IT SHIPPED.
#
# SPEC: docs/designs/2026-08-02-delta-track-v1.md §9.2 (THE THREE REFUSALS and
# the absolute property "performs no write of any kind before all three pass"),
# §9.3 (promotion, and the tag written LAST), §6.3 (BUGS.md's table format is
# PARSED BY SCRIPTS — its own header forbids format changes, so the delta link
# and now the version live in the EXISTING `Fix Reference` column and NEVER in
# a new one), §7.1 (`shipped_in`, write-once, through the seam), §5.2 (which
# ledger each class writes to). Karl's decision of 2026-08-09, recorded in
# .superpowers/sdd/2026-08-02-delta-track-v1/dB-ledger-close-brief.md.
#
# (No `# BL-NNN-…` marker anywhere in the delta track on purpose: no backlog
# entry exists for this build and minting one would red
# scripts/lint-bl-markers.sh, whose first pass resolves every marker to a real
# `## BL-NNN:` entry. The design-doc path above is the citation, per the WP1
# through WP8 precedent. The grep-able `CUTREL-LEDGER-*` markers in the product
# are this suite's citation primitive and its mutation addresses.)
#
# ═════════════════════════════════════════════════════════════════════════════
# THE DEFECT THIS CLOSES, AND WHY IT IS CLOSED HERE AND NOT AT `--close`
#
# `delta.sh --open` writes a REAL ledger row for every class (WP8, Karl's
# decision 3): a `| SEV-N | Open |` row in BUGS.md for fix / hotfix /
# security-patch, and a `**Status:** In Progress` block in FEATURES.md for
# feature. NOTHING EVER FLIPPED EITHER. `--complete-gate ledger_row` records
# only that the operator ATTESTS the row is filled; `--close` writes
# `.claude/delta-state.json` and deliberately nothing else; the cut wrote
# `shipped_in` into the state document and never touched the ledger. So every
# post-1.0 fix left a permanent apparently-open SEV-N row, monotonically, in
# the artefact this framework holds up as the bug record.
#
# CLOSE IS NOT SHIP, and marking the row at `--close` was rejected on the
# merits: a closed delta has reached nobody, so flipping the row there would
# state "this bug is fixed" before the fix exists for any user — a falsehood in
# the audit trail, which is the exact defect class this wave has been removing.
# The cut is the honest moment: it already loops the closed deltas to write
# `shipped_in`, so it knows precisely which shipped and in which version.
#
# ═════════════════════════════════════════════════════════════════════════════
# THE THREE PROPERTIES THIS SUITE EXISTS FOR
#
# 1. THE FLIP IS PHASE B ONLY. §9.2's property is absolute and this suite
#    re-takes WP7's instrument with LEDGERS PRESENT: a whole-tree `find` +
#    per-file md5 manifest across every refusal, singly and in combination,
#    plus a separate tag count. A refusal that closed a bug row would be a
#    release that never happened claiming a fix that never shipped.
#
# 2. THE TABLE STILL PARSES. §6.3 is a HARD constraint. BUGS.md's own header
#    says "Do NOT change the table format", and scripts/test-gate.sh greps
#    `SEV-1.*Open`, `SEV-2.*Open`, `SEV-2.*Deferred` and `SEV-3.*Open` across
#    it. G1/G2 assert the nine shipped columns survive on EVERY row (a `|`
#    field count, not a spot check), that the header and separator rows are
#    byte-identical, and that the gate's own greps still find the table while
#    no longer counting the shipped row as open.
#
# 3. A FLIP THAT FAILS SAYS SO, AND CLAIMS NOTHING. This is WP8's `_ledger_write`
#    lesson one layer up. WP8 measured an unguarded `{ … } >> "$ledger"`
#    returning the FILENAME — non-empty — on failure, so the caller's
#    "did it produce output?" check read a failed write as success and the lie
#    reached the STATE DOCUMENT, not just the transcript. The defence here is
#    structural: the ONLY thing that promotes a row to "closed" is a RE-READ of
#    the file after the write (`# CUTREL-LEDGER-VERIFY`). The writer's exit code
#    is never the promoter. m3 makes the promoter unconditional and F1 kills it.
#
# ═════════════════════════════════════════════════════════════════════════════
# EXIT CODES, NEVER LABELS
#
# Every verdict below is asserted on a process EXIT CODE, on a file's BYTES, on
# a whole-tree manifest, or on `git tag --list`. None is asserted on a printed
# banner. CLAUDE.md's `[WARN]` trap is that a label and an exit predicate can
# disagree. Printed text IS asserted in two places — the specific-failure lines
# — and there it is the deliverable itself, paired every time with a positive
# control that shows the same probe seeing the line when it is there.
#
# THE CONTRACT UNDER TEST (scripts/cut-release.sh), D-B's addition in bold:
#     0   the release was cut, and every ledger row it shipped was closed
#     3-11 unchanged (WP7's refusals and write failures)
#    12   **the release WAS cut — changelog promoted, shipped_in recorded, tag
#         created — and one or more ledger rows could NOT be closed.** The
#         release is not failed for it (it genuinely happened) but the cut does
#         not report clean either, and the rows are named.
#
# ═════════════════════════════════════════════════════════════════════════════
# WHAT THIS SUITE PINS
#
#   L — THE CLOSE ITSELF, over rows written by the REAL `delta.sh --open`
#     L1  a `fix` shipped -> its BUGS.md row reads `Fixed` and its Fix
#         Reference names BOTH the DELTA id and the version   KILLS m1, m4
#     L2  a `feature` shipped -> its FEATURES.md block reads
#         `**Status:** Complete (shipped in vX.Y.Z)`                KILLS m5
#     L3  BOTH CLASSES IN ONE CUT — the brief's "handle every class WP8
#         writes, not just BUGS.md", proven together rather than separately
#     L4  a project with NO ledger files at all still cuts clean (rc 0): the
#         benign case must not be turned into a failure by the guard
#     L5  THE PREFIX COLLISION — shipping `DELTA-1000` must not close the
#         `DELTA-100` row. The allocator zero-pads to three and keeps
#         counting, so a bare `index(cell, id)` closes a bug nobody fixed
#         the moment a project passes 999 deltas
#
#   A — THE FEATURES MATCHER IS ANCHORED TO THE WRITER'S OWN STRUCTURAL LINE
#     A1  a prose block that merely NAMES the delta, sitting ahead of the block
#         `_ledger_write` wrote -> the written block flips and the prose block
#         is BYTE-IDENTICAL. A block-anywhere match stamps the prose block
#         `Complete (shipped in vX.Y.Z)` and reports `[OK] Closed 1` at rc 0 —
#         a false close reported as a clean cut                        KILLS m7
#     A2  the prose block is ALL there is -> this is the ROW-ABSENT path:
#         nothing written, the row-absent wording, rc 12
#     A3  the written block's own Summary names a DIFFERENT delta -> that
#         mention changes neither which block closes for its own id nor the
#         foreign id's answer ("no row naming it")
#
#   S — THE STAGING GUARD (`-s`, not `-e`)
#     S1  the flip transform dies producing NOTHING -> the write is refused and
#         the ledger is byte-identical. `-e` would pass empty content to a
#         truncating redirect and blank the project's bug record   KILLS m6
#
#   G — §6.3's HARD CONSTRAINT: THE TABLE STILL PARSES
#     G1  every `|`-row in BUGS.md still has exactly NINE columns, the header
#         and separator rows are BYTE-IDENTICAL, and the file grew no rows
#     G2  scripts/test-gate.sh's own four greps still find the table, and the
#         shipped row has left the `SEV-1.*Open` count by exactly one
#
#   N — §9.2: A REFUSAL WRITES NOTHING, WITH LEDGERS PRESENT
#     N1  all nine WP7 refusals, singly and in combination, over a project
#         that HAS an open BUGS.md row and an open FEATURES.md block —
#         whole-tree manifest and tag set both unmoved
#
#   F — HONESTY WHEN THE FLIP FAILS (WP8's lesson, one layer up)
#     F1  the ledger is UNWRITABLE -> the run names the row specifically,
#         records no claim it did not honour, the row still reads open, THE
#         RELEASE STILL COMPLETES (changelog, shipped_in, tag) and the exit
#         code is 12 rather than 0                          KILLS m2, m3
#     F2  the ledger exists but has NO ROW for the delta -> named
#         specifically, distinct wording from F1, rc 12, tag still created
#
#   I — IDEMPOTENCE
#     I1  cut twice -> the second refuses at 8 and BUGS.md is byte-identical
#     I2  a row ALREADY `Fixed` at flip time is not an error (rc 0), is left
#         byte-identical, and the version text is not appended twice
#
#   C — THE CLASS MAP IS A SYNC SIBLING
#     C1  `_cutrel_ledger_for` (the closer) and `delta.sh::_ledger_for` (the
#         writer) are driven side by side over every class and agree. A
#         divergence is invisible until a shipped feature's row never closes.
#         The probe carries a POSITIVE CONTROL: the same lift over a
#         deliberately mutated private copy must return the mutated answer,
#         which is what proves the probe reads the sandbox and not the host
#
#   O — ORDERING (§9.3, WP7's cheapest-to-undo-first)
#     O1  the flip is AFTER the seam's ship write: with the ship action shimmed
#         to refuse, the cut stops at 11 and the ledger is byte-identical —
#         a refused ship must never leave a row claiming a version nobody tagged
#     O2  the flip is BEFORE the tag: asserted on marker order in the product
#
#   M — MUTATIONS (anchored end-of-line markers, sites==1, exactly one line
#       changed, `bash -n` on every mutant, mode preserved, fresh fixture each)
#     m1  suppress the flip            -> the row stays `Open`        L1 RED
#     m2  suppress the honesty arm     -> a failed flip reports a CLEAN cut,
#         rc 0, which is the BL-213 shape                             F1 RED
#     m3  promote without re-reading   -> a failed flip is COUNTED and claimed;
#         this is WP8's lie reaching the record, one layer up          F1 RED
#     m4  drop the version append      -> the row reads `Fixed` and names no
#         release, so the audit trail cannot say WHICH one carried it  L1 RED
#     m5  route `feature` to BUGS.md   -> the FEATURES.md block never closes,
#         and the BUGS table gains nothing, so the loss is silent      L2 RED
#     m6  `-s` -> `-e` on the stage    -> empty staged content reaches a
#         TRUNCATING redirect and the bug record becomes zero bytes;
#         killed on the FILE, because both guards answer rc 12 here     S1 RED
#     m7  unanchor the FEATURES match  -> the prose block is stamped and the
#         run reports `Closed 1` at rc 0                                A1 RED
#
# LANE: registered in tests/full-project-test-suite.sh AND in the tests.yml
# `unit-shard` list. No executed line names the scaffolder.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

for _t in git jq awk; do
  if ! command -v "$_t" >/dev/null 2>&1; then
    echo "$_t is required for tests/test-delta-db-ledger-close.sh" >&2
    exit 2
  fi
done

CUTREL="$REPO_ROOT/scripts/cut-release.sh"
DELTASH="$REPO_ROOT/scripts/delta.sh"
if [ ! -f "$CUTREL" ] || [ ! -f "$DELTASH" ]; then
  echo "  [FAIL] scripts/cut-release.sh and scripts/delta.sh must both exist" >&2
  exit 1
fi

# ── Dates (GNU-first, BSD fallback — the house pattern) ─────────────────────
days_ago() {
  local n="$1" e
  e=$(( $(date -u +%s) - n * 86400 ))
  date -u -d "@$e" +%Y-%m-%d 2>/dev/null || date -u -r "$e" +%Y-%m-%d
}
stamp_ago() {
  local n="$1" e
  e=$(( $(date -u +%s) - n * 86400 ))
  date -u -d "@$e" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$e" +%Y-%m-%dT%H:%M:%SZ
}

# ── Residue instruments (WP7's, inherited verbatim so the two agree) ────────
_md5file() {
  if command -v md5 >/dev/null 2>&1; then md5 -q "$1"
  else md5sum "$1" | awk '{print $1}'; fi
}
tree_files() { ( cd "$1" && find . -type f ! -path './.git/*' | LC_ALL=C sort ); }
tree_manifest() {
  local p="$1" f
  tree_files "$p" | while IFS= read -r f; do
    printf '%s  %s\n' "$(_md5file "$p/$f")" "$f"
  done
}
tag_list() { ( cd "$1" && git tag --list 2>/dev/null | LC_ALL=C sort ); }

# ── Ledger readers, written INDEPENDENTLY of the product's own ─────────────
# These are the suite's instruments and they must not be the product's code
# read back at itself. They answer three questions about the shipped BUGS.md
# table: how many `|`-rows there are, how many columns each has, and what a
# named row's Status and Fix Reference cells say.

# bugs_row <file> <id> — the whole table row whose Fix Reference names <id>.
bugs_row() {
  awk -F'[|]' -v id="$2" 'NF == 11 && $1 == "" && index($9, id) > 0 { print; exit }' "$1" 2>/dev/null
}
# bugs_cell <file> <id> <n> — field <n> of that row, trimmed.
bugs_cell() {
  bugs_row "$1" "$2" | awk -F'[|]' -v n="$3" '{ c = $n; sub(/^[ \t]+/, "", c); sub(/[ \t]+$/, "", c); print c }'
}
# bugs_widths <file> — the DISTINCT column counts across every `|`-row of the
#   FIRST table, as a sorted space-separated list. §6.3's structural check: a
#   tenth column added anywhere shows up here as a second width, and a spot
#   check on one row would miss it.
#
#   SCOPED TO THE FIRST TABLE, and that scoping is load-bearing rather than
#   tidy: BUGS.md carries a two-column Status Guide and a four-column Severity
#   Guide further down the same file, so an unscoped sweep reports '11 4 6' and
#   the row can never distinguish a real tenth column from the guides. The
#   first non-`|` line after the table begins ends the scope for good.
bugs_widths() {
  awk -F'[|]' '
    /^\|/ { if (!past) { print NF; intable = 1 } ; next }
    { if (intable) past = 1 }
  ' "$1" 2>/dev/null | LC_ALL=C sort -u | tr '\n' ' ' | sed -e 's/ $//'
}
# feat_status <file> <id> — the `**Status:**` line of the Feature block that
#   names <id>, or the empty string.
#
#   DELIBERATELY THE LOOSE READER, and it stays loose. Every fixture that uses
#   it has exactly ONE Feature block carrying the id, so "the block that
#   mentions it" and "the block that owns it" cannot disagree there. The A rows
#   below are the ones where they DO disagree, and they use the two
#   position-addressed readers underneath instead — an instrument that had been
#   taught the product's anchoring rule could not have caught the product
#   getting that rule wrong.
feat_status() {
  awk -v id="$2" '
    /^## Feature / { blk++; got[blk] = ""; has[blk] = 0 }
    blk > 0 && index($0, id) > 0 { has[blk] = 1 }
    blk > 0 && /^\*\*Status:\*\*/ { if (got[blk] == "") got[blk] = $0 }
    END { for (i = 1; i <= blk; i++) if (has[i]) { print got[i]; exit } }
  ' "$1" 2>/dev/null
}
# feat_block <file> <n> — the BYTES of the n-th `## Feature` block: its header
#   line through the line before the next header (or EOF). Addressed by
#   POSITION, never by content, so a row can assert that an untouched block is
#   byte-identical without the reader itself having an opinion about which
#   block belongs to which delta.
feat_block() {
  awk -v n="$2" '/^## Feature / { blk++ } blk == n { print }' "$1" 2>/dev/null
}
# feat_status_at <file> <n> — the FIRST `**Status:**` line inside block <n>.
feat_status_at() {
  awk -v n="$2" '/^## Feature / { blk++ } blk == n && /^\*\*Status:\*\*/ { print; exit }' "$1" 2>/dev/null
}
# feat_insert_prose <features-file> <id> — a hand-written Feature block that
#   only TALKS about <id>, inserted immediately BEFORE the block `delta.sh
#   --open` appended. It is an ordinary Phase-2 block: its own `**Phase Built:**`
#   line says `2` and names no delta, and the id appears where ids really do
#   appear in a feature reference — in the prose of a Summary describing what a
#   later fix changed.
#
#   BEFORE, not after, on purpose: a matcher that takes the FIRST block
#   mentioning the id picks this one, so its position is what makes the
#   difference between the two matchers observable at all.
feat_insert_prose() {
  local f="$1" id="$2" n tmp
  n="$(grep -n '^## Feature ' "$f" | tail -1 | cut -d: -f1)"
  case "$n" in ''|*[!0-9]*) return 1 ;; esac
  tmp="$f.db.prose"
  awk -v n="$n" -v id="$id" '
    NR == n {
      print "## Feature 9: CSV export"
      print ""
      print "**Phase Built:** 2"
      print "**Status:** In Progress"
      print "**Summary:** the CSV exporter, whose encoding was later corrected by " id
      print "**Key Interfaces:** src/export.ts"
      print "**Related ADRs:** None"
      print "**Test Coverage:** Unit"
      print "**Known Limitations:** None"
      print ""
      print "---"
      print ""
    }
    { print }
  ' "$f" > "$tmp" && mv "$tmp" "$f"
}

# ── Fixtures ────────────────────────────────────────────────────────────────
# EVERY case builds its own tree. Nothing is shared, so no case can inherit a
# surface it did not ask for — and a surface it did not ask for is exactly what
# makes a refusal look like a pass.
#
# THE AGE IS A PARAMETER OF THE WHOLE FIXTURE (WP7's reasoning, inherited): the
# cadence refusal is the expensive one and every row that is not ABOUT it needs
# it quiet, and ageing a file afterwards would make `git log` answer a question
# about walk order rather than about the file.
mk_proj() {   # <dir> [age-days] [with-ledgers: y|n]
  local d="$1" age="${2:-1}" ledgers="${3:-y}" stamp
  mkdir -p "$d/.claude" "$d/docs/test-results" "$d/docs/deltas" "$d/templates/generated"
  (
    cd "$d" && unset GITHUB_BASE_REF
    git init -q .
    git config user.email "db@example.invalid"
    git config user.name "D-B Fixture"
    git config commit.gpgsign false
    git config tag.gpgsign false
  ) >/dev/null 2>&1
  printf '{"track":"light","deployment":"personal","poc_mode":null,"current_phase":4,"phases":{}}\n' \
    > "$d/.claude/phase-state.json"
  cp "$REPO_ROOT/templates/generated/changelog.tmpl" "$d/CHANGELOG.md"
  cp "$REPO_ROOT/templates/generated/delta-brief.tmpl" "$d/templates/generated/delta-brief.tmpl"
  if [ "$ledgers" = y ]; then
    cp "$REPO_ROOT/templates/generated/bugs.tmpl"     "$d/BUGS.md"
    cp "$REPO_ROOT/templates/generated/features.tmpl" "$d/FEATURES.md"
  fi
  printf '{"sbom":"fixture"}\n' > "$d/sbom.json"
  printf 'scan artefact\n' > "$d/docs/test-results/$(days_ago 3)_semgrep_pass.txt"
  stamp="$(days_ago "$age")T12:00:00+0000"
  (
    cd "$d" && unset GITHUB_BASE_REF
    GIT_AUTHOR_DATE="$stamp" GIT_COMMITTER_DATE="$stamp" git add -A
    GIT_AUTHOR_DATE="$stamp" GIT_COMMITTER_DATE="$stamp" git commit -q -m "chore: fixture"
  ) >/dev/null 2>&1
}

tag_at() { ( cd "$1" && unset GITHUB_BASE_REF; git tag "$2" ) >/dev/null 2>&1; }
write_state() { printf '%s\n' "$2" > "$1/.claude/delta-state.json"; }
state_doc() {
  printf '{"schemaVersion":1,"active_delta":%s,"hotfix_retros":%s,"cadence":{},"closed":%s}' \
    "$1" "$2" "$3"
}
closed_row() {   # <id> <class> [breaking] [shipped_in] [severity]
  local id="$1" cls="$2" brk="${3:-false}" ship="${4:-null}" sev="${5:-}"
  local shipj="null" sevj="null"
  [ "$ship" = "null" ] || shipj="\"$ship\""
  [ -z "$sev" ] || sevj="\"$sev\""
  printf '{"id":"%s","class":"%s","severity":%s,"closed_at":"%s","shipped_in":%s,"breaking":%s}' \
    "$id" "$cls" "$sevj" "$(stamp_ago 2)" "$shipj" "$brk"
}
ACTIVE_JSON='{"id":"DELTA-099","slug":"dark-mode","class":"feature","brief":"docs/deltas/DELTA-099-dark-mode.md","opened_at":"2026-08-01T00:00:00Z","opened_via":"guided","attributes":{"risk":"feature-local","level":"small","severity":null},"gates_required":["ledger_row"],"gates_completed":[]}'
open_retro() {
  printf '{"id":"%s","shipped_at":"%s","due_by":"%s","closed_at":null,"record":null}' \
    "$1" "$(stamp_ago $(( $2 + 3 )))" "$(stamp_ago "$2")"
}

mk_scripts_tree() { mkdir -p "$1"; cp -R "$REPO_ROOT/scripts" "$1/scripts"; }
stub_revalidation() {
  local sd="$1" rc="$2"
  cat > "$sd/run-phase3-validation.sh" <<'STUB_EOF'
#!/usr/bin/env bash
printf 'invoked %s\n' "$*" >> "${DB_REVALIDATION_LOG:-/dev/null}"
exit __RC__
STUB_EOF
  sed -e "s/__RC__/$rc/" "$sd/run-phase3-validation.sh" > "$sd/run-phase3-validation.sh.tmp" \
    && mv "$sd/run-phase3-validation.sh.tmp" "$sd/run-phase3-validation.sh"
  chmod +x "$sd/run-phase3-validation.sh"
}

# ── The REAL ledger rows ────────────────────────────────────────────────────
# The rows under test are written by the PRODUCT (`delta.sh --open`), never
# retyped here. A hand-typed row would let the writer's shape drift away from
# the closer's matcher with this suite still green — and "the row the framework
# writes is the row the framework closes" is the whole property.
#
# `--open` refuses a second delta while one is active, and `_next_id` reads the
# record, so each seeded delta is retired into `closed[]` before the next opens.
# That is exactly what a real close does to the slot (§7.1), minus the gates.
seed_open() {   # <project> <class> <slug> <describe> [extra flags…]
  local p="$1" cls="$2" slug="$3" desc="$4"; shift 4
  ( cd "$p" && unset GITHUB_BASE_REF
    bash "$REPO_ROOT/scripts/delta.sh" --open --describe "$desc" --class "$cls" \
      --slug "$slug" --risk feature-local --level small --confirm "$@" </dev/null
  ) >/dev/null 2>&1 || true
}
retire_active() {   # <project> — move active_delta into closed[], shipped_in null
  local p="$1" f tmp
  f="$p/.claude/delta-state.json"; tmp="$f.db.tmp"
  jq --arg at "$(stamp_ago 2)" '
    if (.active_delta // null) == null then .
    else .closed += [{ id: .active_delta.id, class: .active_delta.class,
                       severity: .active_delta.attributes.severity,
                       closed_at: $at, shipped_in: null, breaking: false }]
         | .active_delta = null
    end' "$f" > "$tmp" 2>/dev/null && mv "$tmp" "$f"
}
seeded_id() {   # <project> — the id of the most recently retired delta
  jq -r '.closed[-1].id // ""' "$1/.claude/delta-state.json" 2>/dev/null
}

# ── Runner ──────────────────────────────────────────────────────────────────
CUT_RC=0
CUT_OUT=""
run_cut() {   # <scripts-dir> <project-dir> [args…]
  local sd="$1" p="$2"; shift 2
  CUT_RC=0
  CUT_OUT="$( cd "$p" && unset GITHUB_BASE_REF; bash "$sd/cut-release.sh" "$@" </dev/null 2>&1 )" || CUT_RC=$?
  return 0
}

# ── The empty-stage probe (S1 and m6) ───────────────────────────────────────
# THE STAGING GUARD NEEDS A TRANSFORM THAT DIES PRODUCING NOTHING, and there is
# no way to reach that state from the fixture alone: the flip transform prints
# every line of its input, so its output is empty only if its input is empty —
# and an empty ledger is classified `none` and never reaches the write at all.
# The failure the guard exists for (`a transform that died halfway must not be
# allowed to blank a project's bug record`) therefore has to be INDUCED.
#
# IT IS INDUCED AT ONE SEAM AND NOWHERE ELSE. `-v ver=` is passed by
# cut-release.sh's two ledger FLIP transforms and by nothing else anywhere in
# scripts/ (`grep -rn -- '-v ver=' scripts/` returns those two lines). So the
# state READ that classifies the row as open, the changelog promotion, the seam
# and every other awk in the run reach the real awk untouched, and the ONLY
# thing that changes is that the staged content arrives empty — through the
# product's own `> "$stage"` redirect, at the product's own guard.
#
# The probe exits NON-ZERO as a dying transform really would. That rc is
# deliberately not what is being tested: the product writes `|| true` after the
# transform, precisely because a transform's own answer is not evidence, so the
# `-s` guard is the only thing standing between a dead transform and a blanked
# ledger. Two things prove the probe took effect rather than breaking the run
# somewhere earlier: it LOGS every suppression (asserted to be exactly one), and
# a `passthru` twin using the identical PATH mechanism must cut clean.
mk_awk_probe() {   # <dir> <mode: suppress|passthru>
  local d="$1" mode="$2" real
  real="$(command -v awk)"
  mkdir -p "$d"
  cat > "$d/awk" <<'AWK_PROBE_EOF'
#!/usr/bin/env bash
REAL_AWK="__REAL__"
if [ "__MODE__" = suppress ]; then
  for _a in "$@"; do
    case "$_a" in
      ver=*) printf '%s\n' "$_a" >> "${DB_AWK_PROBE_LOG:-/dev/null}"; exit 2 ;;
    esac
  done
fi
exec "$REAL_AWK" "$@"
AWK_PROBE_EOF
  sed -e "s|__REAL__|$real|" -e "s|__MODE__|$mode|" "$d/awk" > "$d/awk.tmp" \
    && mv "$d/awk.tmp" "$d/awk"
  chmod +x "$d/awk"
}
run_cut_probed() {   # <scripts-dir> <project-dir> <probe-dir> <log>
  local sd="$1" p="$2" pd="$3" lg="$4"
  CUT_RC=0
  CUT_OUT="$( cd "$p" && unset GITHUB_BASE_REF
    PATH="$pd:$PATH" DB_AWK_PROBE_LOG="$lg" bash "$sd/cut-release.sh" </dev/null 2>&1 )" || CUT_RC=$?
  return 0
}
probe_fired() {   # <log> — how many times the probe suppressed a transform
  local n
  n="$(grep -c '' "$1" 2>/dev/null || true)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s' "$n"
}

echo "== tests/test-delta-db-ledger-close.sh =="
echo ""

RT=$(mktemp -d)

# ════════════════════════════════════════════════════════════════════════════
echo "=== L — the close itself, over rows the PRODUCT wrote ==="
# ════════════════════════════════════════════════════════════════════════════

# L1 — a `fix`. The row `delta.sh --open` wrote is `| N | SEV-1 | Open | slug |
# desc | - | Fix Now | DELTA-NNN | - |`; the cut must leave column 3 reading
# `Fixed` and column 8 naming BOTH the delta and the version. §6.3: the version
# rides the EXISTING Fix Reference column, which already takes "PR #12"-shaped
# values, and never a new one.
PL1="$RT/l1"; SL1="$RT/l1-scripts"
mk_proj "$PL1"; tag_at "$PL1" "v1.2.0"
write_state "$PL1" "$(state_doc 'null' '[]' '[]')"
seed_open "$PL1" fix csv-encoding "fix the CSV export encoding" --severity SEV-1
retire_active "$PL1"
L1_ID="$(seeded_id "$PL1")"
l1_before_row="$(bugs_row "$PL1/BUGS.md" "$L1_ID")"
l1_widths_before="$(bugs_widths "$PL1/BUGS.md")"
l1_header_before="$(grep -n '^| # | Severity' "$PL1/BUGS.md" | head -1)"
l1_rows_before="$(grep -c '^|' "$PL1/BUGS.md" || true)"
mk_scripts_tree "$SL1"; stub_revalidation "$SL1/scripts" 0
run_cut "$SL1/scripts" "$PL1"
l1_status="$(bugs_cell "$PL1/BUGS.md" "$L1_ID" 4)"
l1_fixref="$(bugs_cell "$PL1/BUGS.md" "$L1_ID" 9)"
l1_names_delta=n; case "$l1_fixref" in *"$L1_ID"*) l1_names_delta=y ;; esac
l1_names_ver=n;   case "$l1_fixref" in *v1.2.1*) l1_names_ver=y ;; esac
l1_newtag="$(tag_list "$PL1" | grep -v '^v1\.2\.0$' || true)"
if [ "$CUT_RC" -eq 0 ] && [ -n "$L1_ID" ] && [ -n "$l1_before_row" ] \
   && [ "$l1_status" = "Fixed" ] && [ "$l1_names_delta" = y ] && [ "$l1_names_ver" = y ] \
   && [ "$l1_newtag" = "v1.2.1" ]; then
  pass "L1: the BUGS.md row that \`delta.sh --open\` itself wrote for $L1_ID reads Status='$l1_status' after the cut (rc $CUT_RC, $l1_newtag), and its EXISTING Fix Reference cell now names both the delta and the release: '$l1_fixref'. §6.3 satisfied without a tenth column"
else
  fail_ "L1" "rc=$CUT_RC (want 0); id='$L1_ID'; seeded row='$l1_before_row'; Status='$l1_status' (want Fixed); FixRef='$l1_fixref' (want it to name $L1_ID and v1.2.1); new tag='$l1_newtag' (want v1.2.1). Output: $CUT_OUT"
fi

# L2 — a `feature`. FEATURES.md is not a table; its block carries
# `**Status:** In Progress`, and the version rides that SAME line rather than a
# new field, for the same reason §6.3 gives for the table.
PL2="$RT/l2"; SL2="$RT/l2-scripts"
mk_proj "$PL2"; tag_at "$PL2" "v1.2.0"
write_state "$PL2" "$(state_doc 'null' '[]' '[]')"
seed_open "$PL2" feature dark-mode "add a dark mode"
retire_active "$PL2"
L2_ID="$(seeded_id "$PL2")"
l2_before="$(feat_status "$PL2/FEATURES.md" "$L2_ID")"
mk_scripts_tree "$SL2"; stub_revalidation "$SL2/scripts" 0
run_cut "$SL2/scripts" "$PL2"
l2_after="$(feat_status "$PL2/FEATURES.md" "$L2_ID")"
l2_newtag="$(tag_list "$PL2" | grep -v '^v1\.2\.0$' || true)"
l2_complete=n; case "$l2_after" in *Complete*) l2_complete=y ;; esac
l2_ver=n;      case "$l2_after" in *v1.3.0*) l2_ver=y ;; esac
if [ "$CUT_RC" -eq 0 ] && [ -n "$L2_ID" ] && [ "$l2_before" = "**Status:** In Progress" ] \
   && [ "$l2_complete" = y ] && [ "$l2_ver" = y ] && [ "$l2_newtag" = "v1.3.0" ]; then
  pass "L2: the FEATURES.md block \`delta.sh --open\` wrote for $L2_ID went from '$l2_before' to '$l2_after' (rc $CUT_RC, $l2_newtag) — the version is on the EXISTING Status line, so the block gained no new field"
else
  fail_ "L2" "rc=$CUT_RC (want 0); id='$L2_ID'; before='$l2_before' (want '**Status:** In Progress'); after='$l2_after' (want Complete + v1.3.0); new tag='$l2_newtag' (want v1.3.0). Output: $CUT_OUT"
fi

# L3 — BOTH CLASSES IN ONE CUT. The brief's "handle every class WP8 writes":
# the two ledgers must close TOGETHER, from one loop, not one at a time in two
# separately-green fixtures.
PL3="$RT/l3"; SL3="$RT/l3-scripts"
mk_proj "$PL3"; tag_at "$PL3" "v1.2.0"
write_state "$PL3" "$(state_doc 'null' '[]' '[]')"
seed_open "$PL3" fix csv-encoding "fix the CSV export encoding" --severity SEV-2
retire_active "$PL3"
L3_FIX="$(seeded_id "$PL3")"
seed_open "$PL3" feature dark-mode "add a dark mode"
retire_active "$PL3"
L3_FEAT="$(seeded_id "$PL3")"
mk_scripts_tree "$SL3"; stub_revalidation "$SL3/scripts" 0
run_cut "$SL3/scripts" "$PL3"
l3_bug="$(bugs_cell "$PL3/BUGS.md" "$L3_FIX" 4)"
l3_bugref="$(bugs_cell "$PL3/BUGS.md" "$L3_FIX" 9)"
l3_feat="$(feat_status "$PL3/FEATURES.md" "$L3_FEAT")"
l3_newtag="$(tag_list "$PL3" | grep -v '^v1\.2\.0$' || true)"
l3_ok=y
[ "$CUT_RC" -eq 0 ] || l3_ok=n
[ "$L3_FIX" != "$L3_FEAT" ] || l3_ok=n
[ "$l3_bug" = "Fixed" ] || l3_ok=n
case "$l3_bugref" in *v1.3.0*) : ;; *) l3_ok=n ;; esac
case "$l3_feat" in *"Complete"*v1.3.0*) : ;; *) l3_ok=n ;; esac
[ "$l3_newtag" = "v1.3.0" ] || l3_ok=n
if [ "$l3_ok" = y ]; then
  pass "L3: one cut closed BOTH ledger classes — $L3_FIX in BUGS.md (Status='$l3_bug', FixRef='$l3_bugref') and $L3_FEAT in FEATURES.md ('$l3_feat') — at $l3_newtag, rc $CUT_RC. Both are classes WP8 writes at open, so both are classes the cut has to close"
else
  fail_ "L3" "rc=$CUT_RC (want 0); fix=$L3_FIX Status='$l3_bug' FixRef='$l3_bugref'; feature=$L3_FEAT Status='$l3_feat'; new tag='$l3_newtag' (want v1.3.0). Output: $CUT_OUT"
fi

# L4 — THE BENIGN CASE. A project with no ledger files at all (WP7's own
# fixture shape) must still cut CLEAN. A guard that turns "there was nothing to
# close" into a failure would red every existing release path.
PL4="$RT/l4"; SL4="$RT/l4-scripts"
mk_proj "$PL4" 1 n; tag_at "$PL4" "v1.2.0"
write_state "$PL4" "$(state_doc 'null' '[]' "[$(closed_row DELTA-008 fix)]")"
mk_scripts_tree "$SL4"; stub_revalidation "$SL4/scripts" 0
run_cut "$SL4/scripts" "$PL4"
l4_newtag="$(tag_list "$PL4" | grep -v '^v1\.2\.0$' || true)"
if [ "$CUT_RC" -eq 0 ] && [ "$l4_newtag" = "v1.2.1" ]; then
  pass "L4: a project with NO BUGS.md and NO FEATURES.md still cuts clean (rc $CUT_RC, $l4_newtag) — 'there is no row to close' is not a failure, and this is the fixture shape every WP7 happy-path row uses"
else
  fail_ "L4" "rc=$CUT_RC (want 0), new tag='$l4_newtag' (want v1.2.1). Output: $CUT_OUT"
fi

# L5 — THE PREFIX COLLISION. `index(cell, id) > 0` alone makes `DELTA-100`
# match a `DELTA-1000` row: the allocator zero-pads to three and keeps counting,
# so the two coexist the moment a project passes 999 deltas, and the failure
# would be a release closing a bug it did not fix. Both rows are seeded here and
# only one delta ships; the other row must be untouched, byte for byte.
PL5="$RT/l5"; SL5="$RT/l5-scripts"
mk_proj "$PL5" 1 n; tag_at "$PL5" "v1.2.0"
cp "$REPO_ROOT/templates/generated/bugs.tmpl" "$PL5/BUGS.md"
l5_tmp="$PL5/BUGS.md.seed"
awk '
  { print }
  /^\|---/ && !done {
    print "| 1 | SEV-2 | Open | narrow-fix | the older one | - | Fix Now | DELTA-100 | - |"
    print "| 2 | SEV-2 | Open | wide-fix | the newer one | - | Fix Now | DELTA-1000 | - |"
    done = 1
  }
' "$PL5/BUGS.md" > "$l5_tmp" && mv "$l5_tmp" "$PL5/BUGS.md"
write_state "$PL5" "$(state_doc 'null' '[]' "[$(closed_row DELTA-1000 fix false null SEV-2)]")"
l5_100_before="$(bugs_row "$PL5/BUGS.md" "DELTA-100 ")"
mk_scripts_tree "$SL5"; stub_revalidation "$SL5/scripts" 0
run_cut "$SL5/scripts" "$PL5"
l5_100_after="$(bugs_row "$PL5/BUGS.md" "DELTA-100 ")"
l5_1000_status="$(bugs_cell "$PL5/BUGS.md" "DELTA-1000" 4)"
l5_100_status="$(bugs_cell "$PL5/BUGS.md" "DELTA-100 " 4)"
if [ "$CUT_RC" -eq 0 ] && [ -n "$l5_100_before" ] && [ "$l5_100_before" = "$l5_100_after" ] \
   && [ "$l5_1000_status" = "Fixed" ] && [ "$l5_100_status" = "Open" ]; then
  pass "L5: shipping DELTA-1000 closed only its own row (Status='$l5_1000_status') and left the DELTA-100 row byte-identical and still '$l5_100_status'. A bare substring match on the id would have closed a bug this release never fixed"
else
  fail_ "L5" "rc=$CUT_RC (want 0); DELTA-1000 Status='$l5_1000_status' (want Fixed); DELTA-100 Status='$l5_100_status' (want Open); DELTA-100 row before='$l5_100_before' after='$l5_100_after' (want identical and non-empty). Output: $CUT_OUT"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== A — the FEATURES matcher is anchored to the WRITER'S OWN LINE ==="
# ════════════════════════════════════════════════════════════════════════════
# THE BUGS TABLE HAS A COLUMN FOR THIS AND FEATURES.md DOES NOT. §6.3 gives the
# delta link one cell — `Fix Reference` — so the BUGS matcher can require a
# nine-column row and read field 9, and free text elsewhere in the file cannot
# reach it. A Feature block is prose with a few bolded labels, so a matcher that
# takes the id ANYWHERE in the block takes it out of a Summary too: a feature
# whose description merely says "superseded by DELTA-007" gets stamped
# `**Status:** Complete (shipped in vX.Y.Z)` and the run reports `[OK] Closed 1`
# and exits 0. A FALSE CLOSE REPORTED AS A CLEAN CUT — the same defect class
# this whole change removes one level up, reintroduced by the fix for it.
#
# `delta.sh::_ledger_write` puts the id on its own structural line, and that is
# the line the match is anchored to. What the writer actually emits for the
# feature class (read out of the function, not out of a brief):
#
#     ## Feature <n>: <slug>
#     **Phase Built:** 4 (post-1.0 <id>)
#     **Status:** In Progress
#     **Summary:** <describe>
#     …
#
# The id appears on `**Phase Built:**`, and on `**Brief:**` when a brief path
# carries it — but `**Phase Built:**` is the one the writer emits unconditionally
# for every feature it opens, so that is the anchor. A block with no such line
# is not a block this framework wrote, and the cut says "no row naming it"
# rather than guessing: rc 12 and a human closes it by hand, which is the safe
# direction when the alternative is stamping a shipped version onto somebody
# else's feature.

# A1 — TWO BLOCKS, ONE ID. Block A only talks about the delta; block B is the
# one `delta.sh --open` wrote. B must flip and A must be BYTE-IDENTICAL — bytes,
# not just its Status text, because a matcher that rewrote A's Summary or its
# spacing would still leave "Status: In Progress" readable there.
PA1="$RT/a1"; SA1="$RT/a1-scripts"
mk_proj "$PA1"; tag_at "$PA1" "v1.2.0"
write_state "$PA1" "$(state_doc 'null' '[]' '[]')"
seed_open "$PA1" feature dark-mode "add a dark mode"
retire_active "$PA1"
A1_ID="$(seeded_id "$PA1")"
feat_insert_prose "$PA1/FEATURES.md" "$A1_ID"
# The fixture's own shape is asserted, not assumed: block 2 must be the prose
# one (it names the id and its Phase Built line does not), block 3 the written
# one (its Phase Built line is where the id lives). If the template ever gains
# or loses a block these preconditions fail loudly instead of the row passing
# over a fixture that no longer contains the collision it is about.
a1_A_before="$(feat_block "$PA1/FEATURES.md" 2)"
a1_B_before="$(feat_block "$PA1/FEATURES.md" 3)"
a1_shape=y
case "$a1_A_before" in *"$A1_ID"*) : ;; *) a1_shape=n ;; esac
case "$a1_A_before" in *"**Phase Built:** 2"*) : ;; *) a1_shape=n ;; esac
case "$a1_B_before" in *"**Phase Built:** 4 (post-1.0 $A1_ID)"*) : ;; *) a1_shape=n ;; esac
mk_scripts_tree "$SA1"; stub_revalidation "$SA1/scripts" 0
run_cut "$SA1/scripts" "$PA1"
a1_A_after="$(feat_block "$PA1/FEATURES.md" 2)"
a1_B_status="$(feat_status_at "$PA1/FEATURES.md" 3)"
# THE CLOSE CLAIM IS MATCHED ON THE WHOLE SENTENCE, not on `Closed `: the cut's
# own header prints "Closed since then: N change(s)" before Phase B runs, and a
# probe that matched that would report a close on every run including the ones
# that closed nothing. A2's absence probe below is the same sentence with the
# COUNT removed — strictly wider than this one — so A1 and A3 matching here are
# literal positive controls for A2 asserting it absent.
a1_claimed=n; case "$CUT_OUT" in *"Closed 1 bug/feature row(s) with v1.3.0"*) a1_claimed=y ;; esac
a1_newtag="$(tag_list "$PA1" | grep -v '^v1\.2\.0$' || true)"
if [ "$a1_shape" = y ] && [ "$CUT_RC" -eq 0 ] \
   && [ "$a1_A_before" = "$a1_A_after" ] \
   && [ "$a1_B_status" = "**Status:** Complete (shipped in v1.3.0)" ] \
   && [ "$a1_claimed" = y ] && [ "$a1_newtag" = "v1.3.0" ]; then
  pass "A1: with a prose block that merely names $A1_ID sitting AHEAD of the block delta.sh wrote, the cut flipped the written block ('$a1_B_status') and left the prose block byte-identical — rc $CUT_RC, $a1_newtag, one row claimed. The id is matched on the writer's own \`**Phase Built:**\` line, so free text cannot be mistaken for a ledger row"
else
  fail_ "A1" "fixture shape ok=$a1_shape; rc=$CUT_RC (want 0); prose block changed=$([ "$a1_A_before" = "$a1_A_after" ] && echo n || echo YES) (want n); written block Status='$a1_B_status' (want '**Status:** Complete (shipped in v1.3.0)'); claimed=$a1_claimed (want y); new tag='$a1_newtag' (want v1.3.0). Output: $CUT_OUT"
fi

# A2 — THE PROSE BLOCK IS ALL THERE IS. This is the row-absent path and it must
# be REACHED: nothing written, the row-absent wording rather than the
# write-failed wording, and rc 12 — not a false `[OK] Closed 1` at rc 0.
PA2="$RT/a2"; SA2="$RT/a2-scripts"
mk_proj "$PA2"; tag_at "$PA2" "v1.2.0"
write_state "$PA2" "$(state_doc 'null' '[]' "[$(closed_row DELTA-007 feature)]")"
feat_insert_prose "$PA2/FEATURES.md" "DELTA-007"
a2_before="$(_md5file "$PA2/FEATURES.md")"
a2_mentions="$(grep -c 'DELTA-007' "$PA2/FEATURES.md" || true)"
case "$a2_mentions" in ''|*[!0-9]*) a2_mentions=0 ;; esac
mk_scripts_tree "$SA2"; stub_revalidation "$SA2/scripts" 0
run_cut "$SA2/scripts" "$PA2"
a2_after="$(_md5file "$PA2/FEATURES.md")"
a2_absent=n;  case "$CUT_OUT" in *"DELTA-007"*"no row naming it"*) a2_absent=y ;; esac
a2_claimed=n; case "$CUT_OUT" in *"bug/feature row(s) with"*) a2_claimed=y ;; esac
a2_newtag="$(tag_list "$PA2" | grep -v '^v1\.2\.0$' || true)"
if [ "$a2_mentions" -ge 1 ] && [ "$CUT_RC" -eq 12 ] && [ "$a2_before" = "$a2_after" ] \
   && [ "$a2_absent" = y ] && [ "$a2_claimed" = n ] && [ "$a2_newtag" = "v1.3.0" ]; then
  pass "A2: a FEATURES.md whose only mention of DELTA-007 is prose ($a2_mentions mention(s)) is the ROW-ABSENT case — the file is byte-identical ($a2_after), the run says 'no row naming it', claims nothing closed, and answers rc $CUT_RC. The release still happened ($a2_newtag); the paperwork is reported as not done rather than reported as done"
else
  fail_ "A2" "mentions=$a2_mentions (want >=1); rc=$CUT_RC (want 12); FEATURES.md md5 $a2_before -> $a2_after (want identical); row-absent line=$a2_absent (want y); any close claimed=$a2_claimed (want n); new tag='$a2_newtag' (want v1.3.0). Output: $CUT_OUT"
fi

# A3 — A FOREIGN ID IN THE WRITTEN BLOCK'S OWN BODY. The describe text is the
# operator's, and operators cross-reference deltas in it; `_ledger_write` copies
# it verbatim into `**Summary:**`. That mention must not make the block answer
# for the delta it names — while the block still closes for the delta whose
# `**Phase Built:**` line it carries. Both directions, one cut.
PA3="$RT/a3"; SA3="$RT/a3-scripts"
mk_proj "$PA3"; tag_at "$PA3" "v1.2.0"
write_state "$PA3" "$(state_doc 'null' '[]' '[]')"
seed_open "$PA3" feature dark-mode "add a dark mode, superseding DELTA-900"
retire_active "$PA3"
A3_ID="$(seeded_id "$PA3")"
a3_tmp="$PA3/.claude/delta-state.json.db"
jq -c --argjson r "$(closed_row DELTA-900 feature)" '.closed += [$r]' \
  "$PA3/.claude/delta-state.json" > "$a3_tmp" 2>/dev/null && mv "$a3_tmp" "$PA3/.claude/delta-state.json"
a3_foreign="$(grep -c 'superseding DELTA-900' "$PA3/FEATURES.md" || true)"
case "$a3_foreign" in ''|*[!0-9]*) a3_foreign=0 ;; esac
mk_scripts_tree "$SA3"; stub_revalidation "$SA3/scripts" 0
run_cut "$SA3/scripts" "$PA3"
a3_own="$(feat_status_at "$PA3/FEATURES.md" 2)"
a3_absent=n;  case "$CUT_OUT" in *"DELTA-900"*"no row naming it"*) a3_absent=y ;; esac
a3_claimed=n; case "$CUT_OUT" in *"Closed 1 bug/feature row(s) with v1.3.0"*) a3_claimed=y ;; esac
a3_newtag="$(tag_list "$PA3" | grep -v '^v1\.2\.0$' || true)"
if [ "$a3_foreign" -eq 1 ] && [ "$CUT_RC" -eq 12 ] \
   && [ "$a3_own" = "**Status:** Complete (shipped in v1.3.0)" ] \
   && [ "$a3_absent" = y ] && [ "$a3_claimed" = y ] && [ "$a3_newtag" = "v1.3.0" ]; then
  pass "A3: the written block's own Summary names DELTA-900, and that changed nothing about which block belongs to whom — the block closed for $A3_ID ('$a3_own', one row claimed) and DELTA-900 was reported as having 'no row naming it' (rc $CUT_RC) rather than silently taking a block it does not own"
else
  fail_ "A3" "foreign mention present=$a3_foreign (want 1); rc=$CUT_RC (want 12); own block Status='$a3_own' (want '**Status:** Complete (shipped in v1.3.0)'); DELTA-900 row-absent line=$a3_absent (want y); one row claimed=$a3_claimed (want y); new tag='$a3_newtag' (want v1.3.0). Output: $CUT_OUT"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== G — §6.3's hard constraint: the table still parses ==="
# ════════════════════════════════════════════════════════════════════════════

# G1 — STRUCTURAL, not a spot check. Every `|`-row of the bug table is counted
# by FIELDS, so a tenth column added anywhere shows up as a second width; the
# header and separator rows are compared BYTE-FOR-BYTE; and the row count is
# unchanged, because a flip that appended a row instead of editing one would
# also pass a "the row says Fixed" check.
l1_widths_after="$(bugs_widths "$PL1/BUGS.md")"
l1_header_after="$(grep -n '^| # | Severity' "$PL1/BUGS.md" | head -1)"
l1_sep_after="$(grep -c '^|---|---|---|---|---|---|---|---|---|$' "$PL1/BUGS.md" || true)"
l1_rows_after="$(grep -c '^|' "$PL1/BUGS.md" || true)"
if [ "$l1_widths_before" = "11" ] && [ "$l1_widths_after" = "11" ] \
   && [ "$l1_header_before" = "$l1_header_after" ] && [ "$l1_sep_after" -ge 1 ] \
   && [ "$l1_rows_before" = "$l1_rows_after" ]; then
  pass "G1: after the flip every row of the bug table still splits into exactly nine columns (field widths seen: '$l1_widths_after'), the header row is byte-identical to before, the nine-column separator survives, and the file has the same $l1_rows_after table rows it started with — no tenth column, no appended row"
else
  fail_ "G1" "widths before='$l1_widths_before' after='$l1_widths_after' (both want '11' = nine columns); header before='$l1_header_before' after='$l1_header_after'; separator rows=$l1_sep_after (want >=1); table rows $l1_rows_before -> $l1_rows_after"
fi

# G2 — THE GATE'S OWN GREPS. scripts/test-gate.sh counts open bugs with
# `SEV-N.*Status`-shaped patterns; §6.3 exists because a format change breaks
# them silently. So the four real patterns are run here, before and after, and
# the shipped SEV-1 must have LEFT the open count — which is the human point of
# the whole change.
PG="$RT/g2"; SG="$RT/g2-scripts"
mk_proj "$PG"; tag_at "$PG" "v1.2.0"
write_state "$PG" "$(state_doc 'null' '[]' '[]')"
seed_open "$PG" fix login-crash "fix the crash on login" --severity SEV-1
retire_active "$PG"
G_ID="$(seeded_id "$PG")"
g_sev1_before="$(grep -c 'SEV-1.*Open' "$PG/BUGS.md" || true)"
mk_scripts_tree "$SG"; stub_revalidation "$SG/scripts" 0
run_cut "$SG/scripts" "$PG"
g_sev1_after="$(grep -c 'SEV-1.*Open' "$PG/BUGS.md" || true)"
g_sev2_open="$(grep -c 'SEV-2.*Open' "$PG/BUGS.md" || true)"
g_sev2_def="$(grep -c 'SEV-2.*Deferred' "$PG/BUGS.md" || true)"
g_sev3_open="$(grep -c 'SEV-3.*Open' "$PG/BUGS.md" || true)"
g_fixed="$(grep -c 'SEV-1.*Fixed' "$PG/BUGS.md" || true)"
for _v in g_sev1_before g_sev1_after g_sev2_open g_sev2_def g_sev3_open g_fixed; do
  eval "case \"\$$_v\" in ''|*[!0-9]*) $_v=0 ;; esac"
done
if [ "$CUT_RC" -eq 0 ] && [ "$g_sev1_before" -eq 1 ] && [ "$g_sev1_after" -eq 0 ] \
   && [ "$g_fixed" -ge 1 ] && [ "$g_sev2_open" -eq 0 ] && [ "$g_sev2_def" -eq 0 ] \
   && [ "$g_sev3_open" -eq 0 ]; then
  pass "G2: the gate's own four patterns still read this table. The shipped $G_ID left the open count exactly as intended — 'SEV-1.*Open' $g_sev1_before -> $g_sev1_after, 'SEV-1.*Fixed' now $g_fixed — and the three patterns that were zero stayed zero. This is the human consequence the brief names: a healthy product no longer accumulates apparently-open SEV-1s"
else
  fail_ "G2" "rc=$CUT_RC (want 0); SEV-1.*Open $g_sev1_before -> $g_sev1_after (want 1 -> 0); SEV-1.*Fixed=$g_fixed (want >=1); SEV-2.*Open=$g_sev2_open, SEV-2.*Deferred=$g_sev2_def, SEV-3.*Open=$g_sev3_open (all want 0). Output: $CUT_OUT"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== N — §9.2: a refusal writes NOTHING, with ledgers present ==="
# ════════════════════════════════════════════════════════════════════════════
# WP7 took this manifest over a project with no ledgers at all, so its rows are
# structurally unable to see a ledger write on a refusal path. Re-taken here
# with an OPEN BUGS.md row and an OPEN FEATURES.md block in the tree, which is
# the only shape in which the new write could possibly fire early.

N_DETAIL=""
N_OK=y
_n_case() {   # <name> <want-rc> <setup-fn> [age]
  local name="$1" want="$2" setup="$3" age="${4:-1}" P before after tags_before tags_after
  P="$RT/$name"
  mk_proj "$P" "$age"
  tag_at "$P" "v1.2.0"
  write_state "$P" "$(state_doc 'null' '[]' '[]')"
  seed_open "$P" fix csv-encoding "fix the CSV export encoding" --severity SEV-1
  retire_active "$P"
  seed_open "$P" feature dark-mode "add a dark mode"
  retire_active "$P"
  "$setup" "$P"
  before="$(tree_manifest "$P")"; tags_before="$(tag_list "$P")"
  run_cut "$REPO_ROOT/scripts" "$P"
  after="$(tree_manifest "$P")"; tags_after="$(tag_list "$P")"
  N_DETAIL="$N_DETAIL [$name=rc$CUT_RC]"
  [ "$CUT_RC" -eq "$want" ] || { N_OK=n; N_DETAIL="$N_DETAIL(want $want)"; }
  [ "$before" = "$after" ] || { N_OK=n; N_DETAIL="$N_DETAIL(TREE MOVED)"; }
  [ "$tags_before" = "$tags_after" ] || { N_OK=n; N_DETAIL="$N_DETAIL(TAGGED)"; }
  case "$CUT_OUT" in *"To clear this:"*) : ;; *) N_OK=n; N_DETAIL="$N_DETAIL(NO REMEDY)" ;; esac
}
_break_cadence2() {
  rm -f "$1"/docs/test-results/*
  printf 'scan artefact\n' > "$1/docs/test-results/2026-13-45_semgrep_pass.txt"
}
_n_active()   { local d; d="$(jq -c --argjson a "$ACTIVE_JSON" '.active_delta = $a' "$1/.claude/delta-state.json")"; printf '%s\n' "$d" > "$1/.claude/delta-state.json"; }
_n_retro()    { local d; d="$(jq -c --argjson r "$(open_retro DELTA-007 2)" '.hotfix_retros += [$r]' "$1/.claude/delta-state.json")"; printf '%s\n' "$d" > "$1/.claude/delta-state.json"; }
_n_clean()    { : ; }
_n_cad2()     { _break_cadence2 "$1"; }
_n_all()      { _n_active "$1"; _n_retro "$1"; _break_cadence2 "$1"; }
_n_two_three(){ _n_retro "$1"; _break_cadence2 "$1"; }
_n_corrupt()  { printf '{"schemaVersion": 1, "active_delta"\n' > "$1/.claude/delta-state.json"; }
_n_absent()   { rm -f "$1/.claude/delta-state.json"; }
_n_shipped()  { local d; d="$(jq -c '.closed = [.closed[] | .shipped_in = "v1.2.0"]' "$1/.claude/delta-state.json")"; printf '%s\n' "$d" > "$1/.claude/delta-state.json"; }

_n_case n-open-delta      3 _n_active
_n_case n-open-retro      4 _n_retro
_n_case n-cadence-overdue 5 _n_clean 20
_n_case n-cadence-unmeas  5 _n_cad2
_n_case n-all-three       3 _n_all
_n_case n-two-and-three   4 _n_two_three
_n_case n-corrupt         6 _n_corrupt
_n_case n-absent          7 _n_absent
_n_case n-nothing-closed  8 _n_shipped

if [ "$N_OK" = y ]; then
  pass "N1: all nine refusals still leave the WHOLE TREE byte-for-byte as they found it (find + per-file md5) and the tag set unmoved, over a project that HAS an open BUGS.md row and an open FEATURES.md block —$N_DETAIL. §9.2's property is absolute: the flip is Phase B only"
else
  fail_ "N1" "expected rc 3/4/5/5/3/4/6/7/8 with an unchanged tree, unchanged tags and a remedy line; got:$N_DETAIL"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== F — honesty when the flip fails (WP8's lesson, one layer up) ==="
# ════════════════════════════════════════════════════════════════════════════

# F1 — THE FORCED FAILURE. WP8 measured what happens when a ledger write fails
# and nobody checks: `_ledger_write`'s unguarded `{ … } >> "$ledger"` returned
# the FILENAME, the caller read non-empty as success, and `ledger: "FEATURES.md"`
# went into the STATE DOCUMENT for a row that was never written. One layer up,
# the same shape would be a release claiming it closed a bug it did not.
#
# The write here is a TRUNCATING REDIRECT rather than a rename precisely so that
# `chmod 444` is a real failure: a rename succeeds on a read-only FILE whenever
# the DIRECTORY is writable, which is why WP8's own L5 had to use the FEATURES
# branch (`>>`) and could not force the BUGS branch (mktemp + mv) to fail at all.
#
# THE PRECONDITION IS ASSERTED, NOT ASSUMED (WP8's L5 lesson): if the mode bit
# does not bite — a root runner, an exotic filesystem — every assertion below is
# vacuous, and a vacuous row must say so rather than pass quietly.
PF1="$RT/f1"; SF1="$RT/f1-scripts"
mk_proj "$PF1"; tag_at "$PF1" "v1.2.0"
write_state "$PF1" "$(state_doc 'null' '[]' '[]')"
seed_open "$PF1" fix csv-encoding "fix the CSV export encoding" --severity SEV-1
retire_active "$PF1"
F1_ID="$(seeded_id "$PF1")"
f1_changelog_before="$(_md5file "$PF1/CHANGELOG.md")"
chmod 444 "$PF1/BUGS.md" 2>/dev/null || true
f1_forced=y
if ( printf 'x\n' >> "$PF1/BUGS.md" ) 2>/dev/null; then f1_forced=n; fi
mk_scripts_tree "$SF1"; stub_revalidation "$SF1/scripts" 0
run_cut "$SF1/scripts" "$PF1"
f1_rc=$CUT_RC
f1_out="$CUT_OUT"
f1_status="$(bugs_cell "$PF1/BUGS.md" "$F1_ID" 4)"
chmod 644 "$PF1/BUGS.md" 2>/dev/null || true
f1_named=n;      case "$f1_out" in *"$F1_ID"*"could not be written"*) f1_named=y ;; esac
f1_claimed=n;    case "$f1_out" in *"Closed 1 "*) f1_claimed=y ;; esac
f1_remedy=n;     case "$f1_out" in *"To clear this:"*) f1_remedy=y ;; esac
f1_newtag="$(tag_list "$PF1" | grep -v '^v1\.2\.0$' || true)"
f1_shipped="$(jq -r --arg i "$F1_ID" '.closed[] | select(.id == $i) | .shipped_in // "null"' "$PF1/.claude/delta-state.json" 2>/dev/null)"
f1_changelog_after="$(_md5file "$PF1/CHANGELOG.md")"

# THE POSITIVE CONTROL for every absence asserted above. Same probe, same
# fixture shape, ledger writable: the success claim MUST appear and the failure
# line MUST NOT. Without this pair, `f1_claimed=n` is satisfied by a probe that
# can never match anything.
PF1G="$RT/f1-control"; SF1G="$RT/f1-control-scripts"
mk_proj "$PF1G"; tag_at "$PF1G" "v1.2.0"
write_state "$PF1G" "$(state_doc 'null' '[]' '[]')"
seed_open "$PF1G" fix csv-encoding "fix the CSV export encoding" --severity SEV-1
retire_active "$PF1G"
F1G_ID="$(seeded_id "$PF1G")"
mk_scripts_tree "$SF1G"; stub_revalidation "$SF1G/scripts" 0
run_cut "$SF1G/scripts" "$PF1G"
f1g_rc=$CUT_RC
f1g_claimed=n;  case "$CUT_OUT" in *"Closed 1 "*) f1g_claimed=y ;; esac
f1g_named=n;    case "$CUT_OUT" in *"could not be written"*) f1g_named=y ;; esac
f1g_status="$(bugs_cell "$PF1G/BUGS.md" "$F1G_ID" 4)"

if [ "$f1_forced" = n ]; then
  fail_ "F1 (vacuous)" "the forced failure did not take effect — BUGS.md stayed writable after chmod 444, so nothing below was exercised. Running as root, or on a filesystem that ignores the mode bit"
elif [ "$f1_rc" -eq 12 ] && [ "$f1_named" = y ] && [ "$f1_claimed" = n ] \
     && [ "$f1_remedy" = y ] && [ "$f1_status" = "Open" ] \
     && [ "$f1_newtag" = "v1.2.1" ] && [ "$f1_shipped" = "v1.2.1" ] \
     && [ "$f1_changelog_before" != "$f1_changelog_after" ] \
     && [ "$f1g_rc" -eq 0 ] && [ "$f1g_claimed" = y ] && [ "$f1g_named" = n ] \
     && [ "$f1g_status" = "Fixed" ]; then
  pass "F1: with BUGS.md unwritable the run NAMES $F1_ID and says specifically that the file could not be written, claims nothing it did not honour (no 'Closed 1' line), prints a remedy, and leaves the row reading '$f1_status' — while THE RELEASE STILL COMPLETES: changelog promoted, shipped_in='$f1_shipped', tag $f1_newtag created. The verdict is rc $f1_rc, not 0, so the cut does not report clean. Positive control on the same probe with a writable ledger: rc $f1g_rc, success claimed=$f1g_claimed, failure line=$f1g_named, row='$f1g_status'"
else
  fail_ "F1" "forced arm: rc=$f1_rc (want 12) named=$f1_named (want y) false-claim=$f1_claimed (want n) remedy=$f1_remedy (want y) row='$f1_status' (want Open) tag='$f1_newtag' (want v1.2.1) shipped_in='$f1_shipped' (want v1.2.1) changelog-moved=$([ "$f1_changelog_before" != "$f1_changelog_after" ] && echo y || echo n) (want y); control arm: rc=$f1g_rc (want 0) claimed=$f1g_claimed (want y) failure-line=$f1g_named (want n) row='$f1g_status' (want Fixed). Forced output: $f1_out"
fi

# F2 — THE ROW IS NOT THERE. A ledger that exists but carries no row for the
# delta is a DIFFERENT situation from a write that failed, and collapsing the
# two into one message is how an operator goes looking for a permissions problem
# that does not exist. Distinct wording is asserted, in both directions.
PF2="$RT/f2"; SF2="$RT/f2-scripts"
mk_proj "$PF2"; tag_at "$PF2" "v1.2.0"
write_state "$PF2" "$(state_doc 'null' '[]' "[$(closed_row DELTA-042 fix false null SEV-2)]")"
mk_scripts_tree "$SF2"; stub_revalidation "$SF2/scripts" 0
run_cut "$SF2/scripts" "$PF2"
f2_rc=$CUT_RC
f2_named=n;   case "$CUT_OUT" in *"DELTA-042"*"no row naming it"*) f2_named=y ;; esac
f2_wrongmsg=n; case "$CUT_OUT" in *"could not be written"*) f2_wrongmsg=y ;; esac
f2_newtag="$(tag_list "$PF2" | grep -v '^v1\.2\.0$' || true)"
if [ "$f2_rc" -eq 12 ] && [ "$f2_named" = y ] && [ "$f2_wrongmsg" = n ] \
   && [ "$f2_newtag" = "v1.2.1" ]; then
  pass "F2: a BUGS.md with no row for DELTA-042 is reported as exactly that ('no row naming it', rc $f2_rc) and NOT as a write failure ($f2_wrongmsg) — two situations, two messages — and the release still completed at $f2_newtag. F1 above is the positive control for the wording this row asserts absent"
else
  fail_ "F2" "rc=$f2_rc (want 12); named-specifically=$f2_named (want y); wrongly-said-unwritable=$f2_wrongmsg (want n); new tag='$f2_newtag' (want v1.2.1). Output: $CUT_OUT"
fi

# S1 — THE STAGING GUARD. The write is `cat "$stage" > "$ledger"`, and a
# TRUNCATING REDIRECT opens the target and empties it before anything is copied
# in. So the moment the staged content is empty for any reason, the difference
# between "the flip did not happen" and "the project's bug record is now a zero
# byte file" is one character: `-s` rather than `-e`. That character is the
# anti-truncation defence the product's own comment claims — "a transform that
# died halfway must not be allowed to blank a project's bug record" — and a
# claim the suite does not check is worth exactly nothing.
#
# The failure is induced at the flip transform and nowhere else (see the probe
# above). Under `-s` the refusal must leave the ledger BYTE-IDENTICAL: the row
# is reported as unclosed, the release still completes, and rc is 12. m6 flips
# the guard to `-e` over this same fixture and the ledger comes back blank.
PS1="$RT/s1"; SS1="$RT/s1-scripts"
PS1_PROBE="$RT/s1-probe"; PS1_LOG="$RT/s1-probe.log"
mk_proj "$PS1"; tag_at "$PS1" "v1.2.0"
write_state "$PS1" "$(state_doc 'null' '[]' '[]')"
seed_open "$PS1" fix csv-encoding "fix the CSV export encoding" --severity SEV-1
retire_active "$PS1"
S1_ID="$(seeded_id "$PS1")"
mk_scripts_tree "$SS1"; stub_revalidation "$SS1/scripts" 0
mk_awk_probe "$PS1_PROBE" suppress
: > "$PS1_LOG"
s1_before="$(_md5file "$PS1/BUGS.md")"
s1_changelog_before="$(_md5file "$PS1/CHANGELOG.md")"
run_cut_probed "$SS1/scripts" "$PS1" "$PS1_PROBE" "$PS1_LOG"
s1_rc=$CUT_RC
s1_out="$CUT_OUT"
s1_after="$(_md5file "$PS1/BUGS.md")"
s1_size="$(wc -c < "$PS1/BUGS.md" | tr -d ' ')"
s1_fired="$(probe_fired "$PS1_LOG")"
s1_status="$(bugs_cell "$PS1/BUGS.md" "$S1_ID" 4)"
s1_named=n;   case "$s1_out" in *"$S1_ID"*"could not be written"*) s1_named=y ;; esac
s1_claimed=n; case "$s1_out" in *"Closed 1 "*) s1_claimed=y ;; esac
s1_newtag="$(tag_list "$PS1" | grep -v '^v1\.2\.0$' || true)"
s1_shipped="$(jq -r --arg i "$S1_ID" '.closed[] | select(.id == $i) | .shipped_in // "null"' "$PS1/.claude/delta-state.json" 2>/dev/null)"
s1_changelog_after="$(_md5file "$PS1/CHANGELOG.md")"

# THE PASSTHRU TWIN — the positive control for the MECHANISM. Same fixture, same
# PATH override, same probe script with its one suppression arm compiled out. If
# this arm did not cut clean, the rc 12 above would be evidence of a broken
# runner rather than of a guard doing its job.
PS1G="$RT/s1-control"; SS1G="$RT/s1-control-scripts"
PS1G_PROBE="$RT/s1-control-probe"; PS1G_LOG="$RT/s1-control-probe.log"
mk_proj "$PS1G"; tag_at "$PS1G" "v1.2.0"
write_state "$PS1G" "$(state_doc 'null' '[]' '[]')"
seed_open "$PS1G" fix csv-encoding "fix the CSV export encoding" --severity SEV-1
retire_active "$PS1G"
S1G_ID="$(seeded_id "$PS1G")"
mk_scripts_tree "$SS1G"; stub_revalidation "$SS1G/scripts" 0
mk_awk_probe "$PS1G_PROBE" passthru
: > "$PS1G_LOG"
run_cut_probed "$SS1G/scripts" "$PS1G" "$PS1G_PROBE" "$PS1G_LOG"
s1g_rc=$CUT_RC
s1g_status="$(bugs_cell "$PS1G/BUGS.md" "$S1G_ID" 4)"
s1g_fired="$(probe_fired "$PS1G_LOG")"

if [ "$s1_fired" -ne 1 ]; then
  fail_ "S1 (vacuous)" "the probe suppressed $s1_fired transform(s), want exactly 1 — the staged content was never forced empty, so nothing below was exercised. Output: $s1_out"
elif [ "$s1_rc" -eq 12 ] && [ "$s1_before" = "$s1_after" ] && [ "$s1_size" -gt 0 ] \
     && [ "$s1_status" = "Open" ] && [ "$s1_named" = y ] && [ "$s1_claimed" = n ] \
     && [ "$s1_newtag" = "v1.2.1" ] && [ "$s1_shipped" = "v1.2.1" ] \
     && [ "$s1_changelog_before" != "$s1_changelog_after" ] \
     && [ "$s1g_rc" -eq 0 ] && [ "$s1g_status" = "Fixed" ] && [ "$s1g_fired" -eq 0 ]; then
  pass "S1: the flip transform died producing nothing (probe fired $s1_fired time, at the flip and nowhere else) and the staging guard REFUSED the write — BUGS.md is byte-identical ($s1_after, $s1_size bytes) with its row still '$s1_status', the run names $S1_ID specifically, claims nothing, and answers rc $s1_rc while the release completes (shipped_in='$s1_shipped', tag $s1_newtag, changelog promoted). Mechanism control: the passthru twin over the same PATH override cut clean at rc $s1g_rc with its row '$s1g_status' and $s1g_fired suppressions"
else
  fail_ "S1" "forced arm: probe fired=$s1_fired (want 1) rc=$s1_rc (want 12) BUGS.md md5 $s1_before -> $s1_after (want identical) size=$s1_size (want >0) row='$s1_status' (want Open) named=$s1_named (want y) false-claim=$s1_claimed (want n) tag='$s1_newtag' (want v1.2.1) shipped_in='$s1_shipped' (want v1.2.1) changelog-moved=$([ "$s1_changelog_before" != "$s1_changelog_after" ] && echo y || echo n) (want y); control arm: rc=$s1g_rc (want 0) row='$s1g_status' (want Fixed) fired=$s1g_fired (want 0). Forced output: $s1_out"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== I — idempotence ==="
# ════════════════════════════════════════════════════════════════════════════

# I1 — two cuts. `shipped_in` is write-once at the seam, so the second cut has
# nothing to release and refuses at 8; the assertion that matters is that the
# LEDGER is byte-identical afterwards, because a flip that ran unconditionally
# over the closed set would append the version a second time.
i1_before="$(_md5file "$PL1/BUGS.md")"
run_cut "$SL1/scripts" "$PL1"
i1_rc=$CUT_RC
i1_after="$(_md5file "$PL1/BUGS.md")"
i1_vercount="$(grep -c 'v1\.2\.1' "$PL1/BUGS.md" || true)"
case "$i1_vercount" in ''|*[!0-9]*) i1_vercount=0 ;; esac
if [ "$i1_rc" -eq 8 ] && [ "$i1_before" = "$i1_after" ] && [ "$i1_vercount" -eq 1 ]; then
  pass "I1: a second cut over the same record refuses with 'nothing to release' (rc $i1_rc) and BUGS.md is byte-identical ($i1_after) — the version appears exactly $i1_vercount time, so nothing was double-written"
else
  fail_ "I1" "rc=$i1_rc (want 8); BUGS.md md5 $i1_before -> $i1_after; occurrences of the version=$i1_vercount (want 1)"
fi

# I2 — the row is ALREADY `Fixed` when the flip runs. Not an error: an operator
# who closed the row by hand before cutting has done nothing wrong, and
# overwriting their cell — or refusing the release over it — would both be worse
# than leaving it alone and saying so.
PI2="$RT/i2"; SI2="$RT/i2-scripts"
mk_proj "$PI2"; tag_at "$PI2" "v1.2.0"
write_state "$PI2" "$(state_doc 'null' '[]' '[]')"
seed_open "$PI2" fix csv-encoding "fix the CSV export encoding" --severity SEV-1
retire_active "$PI2"
I2_ID="$(seeded_id "$PI2")"
# Close it by hand, the way an operator would: the Status cell, nothing else.
i2_tmp="$PI2/BUGS.md.handedit"
awk -F'[|]' -v OFS='|' -v id="$I2_ID" 'NF == 11 && $1 == "" && index($9, id) > 0 { $4 = " Fixed " } { print }' \
  "$PI2/BUGS.md" > "$i2_tmp" && mv "$i2_tmp" "$PI2/BUGS.md"
i2_before="$(_md5file "$PI2/BUGS.md")"
mk_scripts_tree "$SI2"; stub_revalidation "$SI2/scripts" 0
run_cut "$SI2/scripts" "$PI2"
i2_rc=$CUT_RC
i2_after="$(_md5file "$PI2/BUGS.md")"
i2_told=n; case "$CUT_OUT" in *"$I2_ID"*"already closed"*) i2_told=y ;; esac
i2_newtag="$(tag_list "$PI2" | grep -v '^v1\.2\.0$' || true)"
if [ "$i2_rc" -eq 0 ] && [ "$i2_before" = "$i2_after" ] && [ "$i2_told" = y ] \
   && [ "$i2_newtag" = "v1.2.1" ]; then
  pass "I2: a row the operator had ALREADY closed is left byte-identical ($i2_after), is not an error (rc $i2_rc, $i2_newtag cut), and is still reported rather than passed over in silence ('already closed' naming $I2_ID)"
else
  fail_ "I2" "rc=$i2_rc (want 0); BUGS.md md5 $i2_before -> $i2_after (want identical); reported=$i2_told (want y); new tag='$i2_newtag' (want v1.2.1). Output: $CUT_OUT"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== C — the class map is a SYNC SIBLING, and it is checked ==="
# ════════════════════════════════════════════════════════════════════════════
# `delta.sh::_ledger_for` decides where a class's row is WRITTEN;
# `cut-release.sh::_cutrel_ledger_for` decides where it is CLOSED. They are one
# map read from two ends, in two files, and a divergence is invisible until a
# shipped feature's row silently never closes. So both are LIFTED and DRIVEN
# rather than compared by eye.
#
# THE PROBE RUNS IN A PRIVATE SANDBOX AND CARRIES A POSITIVE CONTROL. A sibling
# probe in this repo turned out to be reading the runner's own filesystem and
# reporting a pass it had not earned; the control below lifts from a copy whose
# map has been DELIBERATELY changed and requires the probe to return the changed
# answer. If it returns the real answer, it is not reading what it claims to.
lift_fn() {    # <file> <fn-name> — that function's source text, and nothing else
  awk -v fn="$2" '
    index($0, fn "() {") == 1 { on = 1 }
    on { print }
    on && /^}/ { exit }
  ' "$1"
}
probe_map() {  # <file> <fn-name> <class> — the answer that function gives
  local f p out
  f="$(mktemp)"
  { lift_fn "$1" "$2"; printf '%s "%s"\n' "$2" "$3"; } > "$f"
  out="$(bash "$f" 2>/dev/null)" || out="ERR"
  rm -f "$f" 2>/dev/null || true
  [ -n "$out" ] || out="EMPTY"
  printf '%s' "$out"
}
CS="$RT/class-sandbox"
mkdir -p "$CS"
cp "$DELTASH" "$CS/delta.sh"
cp "$CUTREL"  "$CS/cut-release.sh"
c1_detail=""
c1_ok=y
for cls in feature fix hotfix security-patch unknown-class ""; do
  w="$(probe_map "$CS/delta.sh" _ledger_for "$cls")"
  c="$(probe_map "$CS/cut-release.sh" _cutrel_ledger_for "$cls")"
  c1_detail="$c1_detail [${cls:-<empty>}: writer=$w closer=$c]"
  [ "$w" = "$c" ] || c1_ok=n
  case "$w" in BUGS.md|FEATURES.md) : ;; *) c1_ok=n ;; esac
done
# The positive control: change the CLOSER's map inside the sandbox and require
# the probe to see the change.
sed -e "s|^\(.*\)# CUTREL-LEDGER-CLASS\$|    feature) printf 'CONTROL.md' ;;   # CUTREL-LEDGER-CLASS|" \
  "$CS/cut-release.sh" > "$CS/cut-release-control.sh"
c1_control="$(probe_map "$CS/cut-release-control.sh" _cutrel_ledger_for feature)"
if [ "$c1_ok" = y ] && [ "$c1_control" = "CONTROL.md" ]; then
  pass "C1: the writer's map and the closer's map are lifted from their own files and driven side by side, and they agree on every class —$c1_detail. The probe is proven to be reading the sandbox and not the host: the same lift over a copy whose feature arm was rewritten returns '$c1_control'"
else
  fail_ "C1" "map agreement:$c1_detail (every pair must match and be a real ledger name); positive control returned '$c1_control' (want CONTROL.md — anything else means the probe is not reading the file it claims to)"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== O — ordering inside Phase B (§9.3) ==="
# ════════════════════════════════════════════════════════════════════════════

# O1 — THE FLIP IS AFTER THE SHIP WRITE. If the seam refuses a row, no tag is
# created and the release did not happen; a ledger already flipped at that point
# would claim a version that nothing carries. WP7's shim is reused verbatim so
# the two suites cannot disagree about what "the ship action refused" means.
PO="$RT/o1"; SO="$RT/o1-scripts"
mk_proj "$PO"; tag_at "$PO" "v1.2.0"
write_state "$PO" "$(state_doc 'null' '[]' '[]')"
seed_open "$PO" fix csv-encoding "fix the CSV export encoding" --severity SEV-1
retire_active "$PO"
O_ID="$(seeded_id "$PO")"
mk_scripts_tree "$SO"; stub_revalidation "$SO/scripts" 0
mv "$SO/scripts/process-checklist.sh" "$SO/scripts/process-checklist-real.sh"
cat > "$SO/scripts/process-checklist.sh" <<'SEAM_SHIM_EOF'
#!/usr/bin/env bash
# D-B test shim — delegates every seam action EXCEPT the ship write, which it
# refuses. Anything that still changes the ledger is doing so too early.
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "${1:-}" = "--delta-state-ship" ]; then exit 1; fi
exec bash "$D/process-checklist-real.sh" "$@"
SEAM_SHIM_EOF
chmod +x "$SO/scripts/process-checklist.sh"
o1_before="$(_md5file "$PO/BUGS.md")"
run_cut "$SO/scripts" "$PO"
o1_rc=$CUT_RC
o1_after="$(_md5file "$PO/BUGS.md")"
o1_status="$(bugs_cell "$PO/BUGS.md" "$O_ID" 4)"
o1_tags="$(tag_list "$PO" | grep -v '^v1\.2\.0$' || true)"
if [ "$o1_rc" -eq 11 ] && [ "$o1_before" = "$o1_after" ] && [ "$o1_status" = "Open" ] \
   && [ -z "$o1_tags" ]; then
  pass "O1: with the seam's ship action refused the cut stops at rc $o1_rc, creates no tag, and BUGS.md is byte-identical ($o1_after) with its row still reading '$o1_status' — the flip is downstream of the ship write, so a release that did not happen closes nothing"
else
  fail_ "O1" "rc=$o1_rc (want 11); BUGS.md md5 $o1_before -> $o1_after (want identical); row='$o1_status' (want Open); new tags='$o1_tags' (want none). Output: $CUT_OUT"
fi

# O2 — THE FLIP IS BEFORE THE TAG. §9.3's ordering is cheapest-to-undo first and
# the tag is last because it is what the release pipelines watch. Asserted on
# the position of the marked line relative to the `git tag` call, on EXECUTED
# lines only.
o2_flip="$(grep -n '# CUTREL-LEDGER-CLOSE$' "$CUTREL" | head -1 | cut -d: -f1)"
o2_tag="$(grep -n 'git tag "\$TAG"' "$CUTREL" | grep -v '^[0-9]*:[[:space:]]*#' | head -1 | cut -d: -f1)"
case "$o2_flip" in ''|*[!0-9]*) o2_flip=0 ;; esac
case "$o2_tag"  in ''|*[!0-9]*) o2_tag=0 ;; esac
if [ "$o2_flip" -gt 0 ] && [ "$o2_tag" -gt 0 ] && [ "$o2_flip" -lt "$o2_tag" ]; then
  pass "O2: the marked flip runs before the tag is created — §9.3's ordering is cheapest-to-undo first, and the tag stays last because it is the only thing a release pipeline watches"
else
  fail_ "O2" "could not establish the order: flip marker at line $o2_flip, 'git tag \"\$TAG\"' at line $o2_tag (the flip must come first, and both must exist)"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== M — mutation proofs (each mutant is BUILT, SYNTAX-CHECKED and RUN) ==="
# ════════════════════════════════════════════════════════════════════════════

_sed_inplace() {
  local file="$1" expr="$2" tmp mode
  mode="$(stat -c '%a' "$file" 2>/dev/null || stat -f '%Lp' "$file" 2>/dev/null || echo "")"
  tmp="$(mktemp)"
  sed -e "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
  [ -n "$mode" ] && chmod "$mode" "$file" 2>/dev/null
  return 0
}
_mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || echo "?"; }
_mutation_report() {
  local orig="$1" mut="$2" marker="$3" sites changed n
  sites="$(grep -c "$marker" "$orig" || true)"
  case "$sites" in ''|*[!0-9]*) sites=0 ;; esac
  if diff "$orig" "$mut" >/dev/null 2>&1; then changed=n; else changed=y; fi
  n="$(diff "$orig" "$mut" | grep -c '^[<>]' || true)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s|%s|%s' "$sites" "$changed" "$n"
}

# _mutate <name> <marker> <sed-expr> <check-fn>
#   Copy scripts/ into a private tree, change the ONE line carrying <marker>,
#   report sites / changed / lines / mode / `bash -n`, then hand the tree to
#   <check-fn>. The report prints whether the mutant is killed or not: a
#   mutation that changed nothing is a green row that proved nothing, and a
#   mutant that does not PARSE is a green row that proved less than nothing —
#   every arm below it would "pass" because the script never ran.
MT=""
MUT_SD=""
MUT_REPORT=""
_mutate() {
  local name="$1" marker="$2" expr="$3" check="$4" SD rep sites changed lines mode_before mode_after synrc
  SD="$MT/$name"
  mk_scripts_tree "$SD"
  stub_revalidation "$SD/scripts" 0
  mode_before="$(_mode_of "$SD/scripts/cut-release.sh")"
  cp "$SD/scripts/cut-release.sh" "$MT/$name.orig"
  _sed_inplace "$SD/scripts/cut-release.sh" "$expr"
  mode_after="$(_mode_of "$SD/scripts/cut-release.sh")"
  synrc=0
  bash -n "$SD/scripts/cut-release.sh" >/dev/null 2>&1 || synrc=$?
  rep="$(_mutation_report "$MT/$name.orig" "$SD/scripts/cut-release.sh" "$marker")"
  sites="${rep%%|*}"; rep="${rep#*|}"; changed="${rep%%|*}"; lines="${rep##*|}"
  MUT_REPORT="marker '$marker' sites=$sites, changed=$changed, diff-lines=$lines, mode $mode_before -> $mode_after, bash -n rc=$synrc"
  MUT_SD="$SD/scripts"
  if [ "$sites" -ne 1 ] || [ "$changed" != y ] || [ "$lines" -ne 2 ] \
     || [ "$mode_before" != "$mode_after" ] || [ "$synrc" -ne 0 ]; then
    fail_ "$name (harness)" "the mutation is not anchored/single-line/mode-preserving/parseable: $MUT_REPORT"
    return 0
  fi
  "$check" "$name"
  return 0
}

# _mut_proj <dir> <class> <slug> <severity-flag…> — a fresh fixture with ONE
#   real ledger row, retired into `closed`. Fresh per mutant, never shared.
_mut_proj() {   # <dir> <class> <slug> [extra open flags…]
  local d="$1" cls="$2" slug="$3"; shift 3
  mk_proj "$d"; tag_at "$d" "v1.2.0"
  write_state "$d" "$(state_doc 'null' '[]' '[]')"
  seed_open "$d" "$cls" "$slug" "a change that needs shipping" "$@"
  retire_active "$d"
}

MT=$(mktemp -d)

# ── m1: suppress the flip ───────────────────────────────────────────────────
_m1_check() {
  local name="$1" P rc id st
  P="$MT/$name-proj"; _mut_proj "$P" fix csv-encoding --severity SEV-1
  id="$(seeded_id "$P")"
  rc=0
  ( cd "$P" && unset GITHUB_BASE_REF; bash "$MUT_SD/cut-release.sh" </dev/null >/dev/null 2>&1 ) || rc=$?
  st="$(bugs_cell "$P/BUGS.md" "$id" 4)"
  if [ "$st" = "Open" ]; then
    pass "m1: with the marked write suppressed the mutant ships $id and leaves its row reading '$st' (rc $rc) — L1 sees it, and this is precisely the defect the brief describes: a permanent apparently-open SEV-N row for work that shipped. $MUT_REPORT"
  else
    fail_ "m1" "the mutant still closed the row (Status='$st', rc $rc) — L1 cannot see this line. $MUT_REPORT"
  fi
}
_mutate m1 '# CUTREL-LEDGER-CLOSE$' \
  's|^\(.*\)# CUTREL-LEDGER-CLOSE$|  if false; then :; fi   # CUTREL-LEDGER-CLOSE|' _m1_check

# ── m2: suppress the honesty arm ────────────────────────────────────────────
# The BL-213 shape: the work fails, and the closing verdict says it did not.
_m2_check() {
  local name="$1" P rc id forced out
  P="$MT/$name-proj"; _mut_proj "$P" fix csv-encoding --severity SEV-1
  id="$(seeded_id "$P")"
  chmod 444 "$P/BUGS.md" 2>/dev/null || true
  forced=y
  if ( printf 'x\n' >> "$P/BUGS.md" ) 2>/dev/null; then forced=n; fi
  rc=0
  out="$( cd "$P" && unset GITHUB_BASE_REF; bash "$MUT_SD/cut-release.sh" </dev/null 2>&1 )" || rc=$?
  chmod 644 "$P/BUGS.md" 2>/dev/null || true
  if [ "$forced" = n ]; then
    fail_ "m2 (vacuous)" "chmod 444 did not bite, so the mutant was never given a failure to hide. $MUT_REPORT"
  elif [ "$rc" -eq 0 ]; then
    pass "m2: with the honesty arm suppressed a flip that FAILED reports a clean cut (rc $rc instead of 12) over a row that never closed — F1 sees it. The release really did happen, which is exactly why the silence is convincing. $MUT_REPORT"
  else
    fail_ "m2" "the mutant still answered rc $rc — F1 cannot see this line. $MUT_REPORT"
  fi
}
_mutate m2 '# CUTREL-LEDGER-HONEST$' \
  's|^\(.*\)# CUTREL-LEDGER-HONEST$|  LEDGER_INCOMPLETE=n   # CUTREL-LEDGER-HONEST|' _m2_check

# ── m3: promote without re-reading — WP8's lie, one layer up ────────────────
# The re-read is the ONLY thing that turns a write into a claim. Make the
# promoter unconditional and a failed write is counted, claimed and reported
# clean — the same shape as `_ledger_write` returning the filename on failure.
_m3_check() {
  local name="$1" P rc id forced out claimed st
  P="$MT/$name-proj"; _mut_proj "$P" fix csv-encoding --severity SEV-1
  id="$(seeded_id "$P")"
  chmod 444 "$P/BUGS.md" 2>/dev/null || true
  forced=y
  if ( printf 'x\n' >> "$P/BUGS.md" ) 2>/dev/null; then forced=n; fi
  rc=0
  out="$( cd "$P" && unset GITHUB_BASE_REF; bash "$MUT_SD/cut-release.sh" </dev/null 2>&1 )" || rc=$?
  chmod 644 "$P/BUGS.md" 2>/dev/null || true
  claimed=n; case "$out" in *"Closed 1 "*) claimed=y ;; esac
  st="$(bugs_cell "$P/BUGS.md" "$id" 4)"
  if [ "$forced" = n ]; then
    fail_ "m3 (vacuous)" "chmod 444 did not bite, so the write never failed and the promoter was never asked to lie. $MUT_REPORT"
  elif [ "$claimed" = y ] && [ "$st" = "Open" ] && [ "$rc" -eq 0 ]; then
    pass "m3: with the re-read removed as the promoter, the mutant CLAIMS it closed a row that still reads '$st' (rc $rc, 'Closed 1' printed) — F1 sees it. This is WP8's measured defect one layer up: the writer's own answer is not evidence that anything landed. $MUT_REPORT"
  else
    fail_ "m3" "the mutant did not produce the lie (claimed=$claimed, row='$st', rc $rc) — F1 cannot see this line. $MUT_REPORT"
  fi
}
_mutate m3 '# CUTREL-LEDGER-VERIFY$' \
  's|^\(.*\)# CUTREL-LEDGER-VERIFY$|  if true; then   # CUTREL-LEDGER-VERIFY|' _m3_check

# ── m4: drop the version from the Fix Reference cell ────────────────────────
# A row that reads `Fixed` and names no release is a row nobody can trace to a
# shipped artefact — the audit trail loses the only thing the cut knew.
_m4_check() {
  local name="$1" P rc id st ref
  P="$MT/$name-proj"; _mut_proj "$P" fix csv-encoding --severity SEV-1
  id="$(seeded_id "$P")"
  rc=0
  ( cd "$P" && unset GITHUB_BASE_REF; bash "$MUT_SD/cut-release.sh" </dev/null >/dev/null 2>&1 ) || rc=$?
  st="$(bugs_cell "$P/BUGS.md" "$id" 4)"
  ref="$(bugs_cell "$P/BUGS.md" "$id" 9)"
  case "$ref" in
    *v1.2.1*) fail_ "m4" "the mutant still recorded the version in the Fix Reference cell ('$ref') — L1 cannot see this line. $MUT_REPORT" ;;
    *) pass "m4: with the version append dropped, the mutant leaves Status='$st' but a Fix Reference of '$ref' that names no release (rc $rc) — L1 sees it. §6.3's whole point is that the version rides that existing cell. $MUT_REPORT" ;;
  esac
}
_mutate m4 '# CUTREL-LEDGER-VERSION$' \
  's|^\(.*\)# CUTREL-LEDGER-VERSION$|        if (0) { fr = fr " shipped in " ver }   # CUTREL-LEDGER-VERSION|' _m4_check

# ── m5: route `feature` to the wrong ledger ─────────────────────────────────
# The silent one. Nothing errors: the closer looks for the feature in BUGS.md,
# does not find it, and the FEATURES.md block stays In Progress forever.
_m5_check() {
  local name="$1" P rc id st
  P="$MT/$name-proj"; _mut_proj "$P" feature dark-mode
  id="$(seeded_id "$P")"
  rc=0
  ( cd "$P" && unset GITHUB_BASE_REF; bash "$MUT_SD/cut-release.sh" </dev/null >/dev/null 2>&1 ) || rc=$?
  st="$(feat_status "$P/FEATURES.md" "$id")"
  if [ "$st" = "**Status:** In Progress" ]; then
    pass "m5: with the feature class routed to the wrong ledger, the mutant ships $id and its FEATURES.md block still reads '$st' (rc $rc) — L2 sees it. Nothing errors on this path, which is why the class map needed a driven agreement check (C1) and not a comment. $MUT_REPORT"
  else
    fail_ "m5" "the mutant still closed the feature block ('$st', rc $rc) — L2 cannot see this line. $MUT_REPORT"
  fi
}
_mutate m5 '# CUTREL-LEDGER-CLASS$' \
  "s|^\(.*\)# CUTREL-LEDGER-CLASS\$|    feature) printf 'BUGS.md' ;;   # CUTREL-LEDGER-CLASS|" _m5_check

# ── m6: the staging guard, `-s` -> `-e` ─────────────────────────────────────
# ONE CHARACTER. `-e` is true for the temp file the moment `mktemp` creates it,
# so empty staged content passes the guard, the truncating redirect opens the
# ledger, and the project's bug record becomes zero bytes. THE MUTANT IS KILLED
# ON THE FILE, NOT ON A MESSAGE: both guards answer rc 12 here — under `-e` the
# blanked ledger re-reads as `none`, which is also "not closed" — so a row that
# asserted the message would pass over a wiped BUGS.md.
_m6_check() {
  local name="$1" P rc id before after size fired pd lg out
  P="$MT/$name-proj"; _mut_proj "$P" fix csv-encoding --severity SEV-1
  id="$(seeded_id "$P")"
  pd="$MT/$name-probe"; lg="$MT/$name-probe.log"
  mk_awk_probe "$pd" suppress
  : > "$lg"
  before="$(_md5file "$P/BUGS.md")"
  rc=0
  out="$( cd "$P" && unset GITHUB_BASE_REF
    PATH="$pd:$PATH" DB_AWK_PROBE_LOG="$lg" bash "$MUT_SD/cut-release.sh" </dev/null 2>&1 )" || rc=$?
  after="$(_md5file "$P/BUGS.md")"
  size="$(wc -c < "$P/BUGS.md" | tr -d ' ')"
  fired="$(probe_fired "$lg")"
  if [ "$fired" -ne 1 ]; then
    fail_ "m6 (vacuous)" "the probe suppressed $fired transform(s), want exactly 1 — the mutant was never handed empty staged content, so nothing was proved. $MUT_REPORT"
  elif [ "$before" != "$after" ] && [ "$size" -eq 0 ]; then
    pass "m6: with the guard widened to \`-e\`, empty staged content passes it and the truncating redirect leaves $id's BUGS.md at $size bytes (md5 $before -> $after, rc $rc) — the project's entire bug record destroyed by a transform that produced nothing. S1 sees it, on the file rather than on the message. $MUT_REPORT"
  else
    fail_ "m6" "the mutant did not blank the ledger (md5 $before -> $after, size=$size, rc $rc) — S1 cannot see this line. $MUT_REPORT"
  fi
}
_mutate m6 '# CUTREL-LEDGER-STAGE$' \
  's@^.*# CUTREL-LEDGER-STAGE$@  [ -e "$src" ] || return 1   # CUTREL-LEDGER-STAGE@' _m6_check

# ── m7: unanchor the FEATURES matcher ───────────────────────────────────────
# Back to "the id anywhere in the block", which is what the first draft of this
# change shipped. The mutant stamps a shipped version onto a feature nobody
# shipped and reports `[OK] Closed 1` at rc 0 — a false close reported as a
# clean cut. THE RED IS ASSERTED ON THE WRONG BLOCK'S BYTES, not on the suite
# merely going non-zero: A1 has several ways to fail and only one of them is
# this one.
_m7_check() {
  local name="$1" P rc id a_before a_after b_status claimed stamped out
  P="$MT/$name-proj"; _mut_proj "$P" feature dark-mode
  id="$(seeded_id "$P")"
  feat_insert_prose "$P/FEATURES.md" "$id"
  a_before="$(feat_block "$P/FEATURES.md" 2)"
  rc=0
  out="$( cd "$P" && unset GITHUB_BASE_REF; bash "$MUT_SD/cut-release.sh" </dev/null 2>&1 )" || rc=$?
  a_after="$(feat_block "$P/FEATURES.md" 2)"
  b_status="$(feat_status_at "$P/FEATURES.md" 3)"
  claimed=n; case "$out" in *"Closed 1 "*) claimed=y ;; esac
  stamped=n; case "$a_after" in *"**Status:** Complete (shipped in v1.3.0)"*) stamped=y ;; esac
  if [ -z "$a_before" ]; then
    fail_ "m7 (vacuous)" "the prose block was never inserted, so the mutant had only one block to choose from. $MUT_REPORT"
  elif [ "$a_before" != "$a_after" ] && [ "$stamped" = y ] && [ "$claimed" = y ] && [ "$rc" -eq 0 ]; then
    pass "m7: with the match unanchored the mutant stamped the PROSE block — a feature that only mentioned $id now reads '**Status:** Complete (shipped in v1.3.0)' — while the block delta.sh actually wrote still reads '$b_status', and the run reported 'Closed 1' at rc $rc. A1 sees it: the wrong block's bytes moved. $MUT_REPORT"
  else
    fail_ "m7" "the mutant did not stamp the prose block (changed=$([ "$a_before" = "$a_after" ] && echo n || echo y), stamped=$stamped, claimed=$claimed, rc $rc, written block='$b_status') — A1 cannot see this line. $MUT_REPORT"
  fi
}
_mutate m7 '# CUTREL-LEDGER-FEATANCHOR$' \
  's@^.*# CUTREL-LEDGER-FEATANCHOR$@    blk > 0 \&\& !hit {   # CUTREL-LEDGER-FEATANCHOR@' _m7_check

rm -rf "$MT"
rm -rf "$RT"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
