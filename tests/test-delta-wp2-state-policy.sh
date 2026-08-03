#!/usr/bin/env bash
# tests/test-delta-wp2-state-policy.sh — Delta Track WP2.
#
# SPEC: docs/designs/2026-08-02-delta-track-v1.md §7.1 (the delta-state schema +
# the D7 single-writer rule), §7.2 (the project-owned delta-policy schema),
# §3.2 (the mechanism/policy split — NOTICE-ONLY is the DECIDED sync semantics,
# modelled on the `# BL-099-DOC-GUARD` rendered-doc fence), §3.1 (the ONE seam),
# §11-WP2 (test intent + the design's own mutation).
#
# (No `# BL-NNN-…` marker anywhere in the delta track on purpose: no backlog
# entry exists for this build and minting one would red scripts/lint-bl-markers.sh,
# whose first pass resolves every marker to a `## BL-NNN:` entry. The design-doc
# path above is the citation, per the WP1 precedent.)
#
# ─────────────────────────────────────────────────────────────────────────────
# WHAT THIS SUITE PINS, AND WHICH MUTANT EACH ROW KILLS
#
# Every row below was verified by EXECUTING its mutant and watching the named
# case go RED, then restoring and watching it go GREEN. A pin whose fixture
# never reaches the guarded code is the defect class both prior WPs in this
# build were caught on, so the mutants are not described — they are RUN, here,
# in cases M1/M1b/M2/M3/M4/M5. A green suite is the proof.
#
#   STATE (§7.1)
#     S1  read with no state file            -> the §7.1 empty document, rc 0
#     S2  write-then-read round trip through the seam
#     S3a ATOMICITY, through the production surface: an update whose result
#         violates the schema shape leaves the previous file BYTE-IDENTICAL and
#         drops no `.tmp` residue.                       KILLS M2
#     S3b ATOMICITY, at the lib boundary: invalid JSON on the write's stdin
#         leaves the previous file BYTE-IDENTICAL.       KILLS M2
#     S4  corrupt state file -> defaults on stdout, warning on stderr, rc 0
#     S4b valid JSON of the WRONG SHAPE -> same, AND still writable (the guard
#         must not lock the single writer out of its own file)
#     S5  `closed` is append-only: an update that DROPS a closed row is refused
#         and writes nothing
#     S5b the REWRITE half of append-only — reorder, equal-length replacement,
#         in-place field rewrite, and the bare shipped_in fill
#     S6  single writer (D7): the boundary lint passes on the real tree and its
#         seam allowlist is still cardinality ONE, so no core file other than
#         scripts/process-checklist.sh can name the state file. Cited, not
#         re-implemented — scripts/lint-delta-boundary.sh owns that predicate
#         and tests/test-lint-delta-boundary.sh owns its mutations.
#     S7  every SHAPE atom, one refusal each
#
#   THE shipped_in WRITE-ONCE PATHWAY (§7.1 Part 2)
#     SH1 the cut-time backfill succeeds and changes nothing else
#     SH2 write-once: a second ship, an unknown id, a missing argument
#     SH3 every OTHER closed[] mutation is refused by the ship predicate too
#     SH4 an unrecognised closed-rule fails CLOSED; ship with no previous file
#         is refused
#
#   ── WHY S5b / S7 / SH3 EXIST, AND THE RULE THEY ENCODE ──────────────────
#   The first cut of this suite pinned only the DROP half of append-only and
#   none of the shape atoms. An adversarial review (R-WP2-1) then deleted three
#   atoms of the shipped write guard — the prefix-equality atom, the
#   closed-is-array atom, and the schemaVersion atom — and the suite stayed at
#   24/0 with all 14 lints green. That is the repo's own recorded defect class
#   (CLAUDE.md / `# BL-181-UNIT-LANE-PREDICATE`: a one-character narrowing
#   passed both PR-blocking checks three times).
#
#   THE RULE, now enforced by construction: EVERY atom of the write guard
#   carries a marker, and every marker has at least one refusal case behind it.
#   The per-atom counterfactual sweep (neuter one marked atom -> the suite must
#   go RED) is the audit, and it found two more holes on its first run that a
#   reading of the code did not:
#     • SHIP-ATOM-OUTSIDE was unpinned — the "change outside closed" case had
#       no accompanying fill, so EXACTLY-ONE refused it first and OUTSIDE never
#       had to do any work. SH3 now carries a fill+outside candidate.
#     • APPEND-ATOM-LENGTH was UNPINNABLE, not merely unpinned: prefix-equality
#       already subsumes it. It was DELETED rather than papered over — see the
#       note under _delta_state_closed_is_append.
#
#   POLICY (§7.2)
#     P1  the seed writer emits the §7.2 defaults, key for key
#     P2  a SECOND seed does not overwrite an existing file  KILLS M4
#     P3  absent KEY (file present) -> framework default; a present sibling key
#         still wins                                        KILLS M3
#     P4  absent FILE -> every key resolves to its default
#     P5  corrupt file -> defaults, warning on stderr, rc 0 for reads
#     P6  a key in neither the project file nor the defaults -> rc 1, no output
#
#   NOTICE-ONLY (§3.2)
#     N1  the `# BL-099-DOC-GUARD` flag matrix, mirrored: under a bare sync,
#         --dry-run, and --apply-doc-updates {sidecar|overwrite|overwrite
#         --confirm-doc-overwrite}, `.claude/delta-policy.json` is byte-identical
#         AND the `.claude/delta-policy*` NAMESPACE does not grow (no `.new`, no
#         `.bak`, no template copy) AND the notice names the missing key.
#                                                    KILLS M1 and M1b
#     N2  a project with NO policy file gets NO notice and NO file
#     N3  a COMPLETE policy file gets no notice at all
#     N4  ROUTING: the notice text is produced by the seam
#         (process-checklist.sh --delta-policy-notice), and upgrade-project.sh
#         reaches it core->core. The boundary lint stays rc=0 with the seam
#         allowlist at cardinality 1.
#     M5  the single inline T2 waiver on upgrade-project.sh's seam invocation is
#         LOAD-BEARING: strip its `# lint-delta-boundary: allow` marker and the
#         boundary lint goes rc=1. This is the pin on the lint-forced routing —
#         it proves the invocation is a real T2 hit being consciously waived
#         with a reason, not a line the lint cannot see.
#
# ─────────────────────────────────────────────────────────────────────────────
# EXIT CODES, NOT LABELS. Every assertion below reads an exit code, a file's
# bytes (md5), or a directory listing. None reads a printed [OK]/[WARN] banner —
# CLAUDE.md's [WARN] trap is that the label and the exit predicate disagree.
#
# HERMETICITY: every fixture is a mktemp -d project that carries NO init.sh and
# NO templates/generated, so `guard_not_in_framework` sees a project and not the
# framework. Sync runs pin CDF_HOME to a nonexistent path (BL-001 skips
# gracefully — no clone, no network), configure a git identity, unset
# GITHUB_BASE_REF, and feed </dev/null + SOIF_NONINTERACTIVE=1. No remote is
# ever created. bash-3.2 safe: no associative arrays, no ${var,,}, no ((x++)).
#
# LANE: registered in tests/full-project-test-suite.sh AND in the tests.yml
# `unit-shard` list. It never EXECUTES init.sh — the mutant-framework builder
# copies it as a file because scaffold-shipped-set.sh reads it to derive the
# shipped set, exactly as tests/test-upgrade-sync-framework.sh does.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PC="$REPO_ROOT/scripts/process-checklist.sh"
UPGRADE="$REPO_ROOT/scripts/upgrade-project.sh"
LINTER="$REPO_ROOT/scripts/lint-delta-boundary.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for tests/test-delta-wp2-state-policy.sh" >&2
  exit 2
fi

# Portable md5 of a single file (macOS `md5 -q`, Linux `md5sum`) — house pattern.
_md5file() {
  if command -v md5 >/dev/null 2>&1; then md5 -q "$1"
  else md5sum "$1" | awk '{print $1}'; fi
}

# Every `.claude/delta-policy*` entry, one per line. The NOTICE-ONLY promise is
# that this set never grows: no `.new`, no `.bak`, no `.upstream-template.new`.
# Asserting the NAMESPACE and not just the two bytes is the BL-099 round-2
# lesson (MAJOR-B: `--apply-doc-updates sidecar` wrote BESIDE the guarded doc
# and the byte assertion never noticed).
_policy_artifacts() {
  ( cd "$1/.claude" 2>/dev/null && ls -1 2>/dev/null | grep -E '^delta-policy' | LC_ALL=C sort ) || true
}

# ── Fixtures ────────────────────────────────────────────────────────────────

# A bare project directory: enough for the seam, no git, no framework signature.
mk_bare() { mkdir -p "$1/.claude"; }

# A minimal, current-vintage upgradeable project (mirrors
# tests/test-upgrade-sync-framework.sh::mk_project).
mk_proj() {
  local dir="$1" lang="${2:-python}"
  mkdir -p "$dir/.claude" "$dir/scripts/lib" "$dir/docs/reference"
  printf '%s\n' '{"track":"light","deployment":"personal","poc_mode":null,"current_phase":1,"phases":{}}' > "$dir/.claude/phase-state.json"
  printf '%s\n' '{"frameworkVersion":"1.0.0","host":"github","mode":"personal","deployment":"personal","poc_mode":null,"enforcement_level":"strict"}' > "$dir/.claude/manifest.json"
  printf '%s\n' "{\"context\":{\"track\":\"light\",\"platform\":\"web\",\"language\":\"$lang\"}}" > "$dir/.claude/tool-preferences.json"
  ( cd "$dir" && git init -q && git config user.email t@t.local && git config user.name T \
      && unset GITHUB_BASE_REF && git add -A && git commit -q -m init ) >/dev/null 2>&1
}

# A project policy file that is DELIBERATELY behind the framework: it keeps
# `classes` and `size_thresholds` (with a TUNED small threshold, so the "project
# wins" half of P3 has something to win with) and omits `cadence`, `semver`,
# `fix_sla`, `cvss_sla`, `attribute_toggles`, `risk_surfaces`.
write_stale_policy() {
  cat > "$1/.claude/delta-policy.json" <<'STALEEOF'
{
  "schemaVersion": 1,
  "classes": {
    "feature": { "gates": ["brief", "ledger_row", "build_loop", "changelog"] }
  },
  "size_thresholds": { "small": 5 }
}
STALEEOF
}

# Copy just the framework's scripts/ tree — everything process-checklist.sh
# needs (helpers-core.sh + the two delta libs). Used to run the seam against a
# MUTATED module without touching the checkout.
mk_scripts_tree() {
  local dir="$1"
  mkdir -p "$dir"
  cp -R "$REPO_ROOT/scripts" "$dir/scripts"
}

# A self-contained fake FRAMEWORK checkout with its own git history (mirrors
# tests/test-upgrade-sync-framework.sh::make_fake_framework). Copies the subset
# a --sync-framework run reads. init.sh is COPIED, never executed.
mk_fake_framework() {
  local fw="$1"
  mkdir -p "$fw/templates"
  cp "$REPO_ROOT/init.sh" "$fw/init.sh"
  cp -R "$REPO_ROOT/scripts" "$fw/scripts"
  cp -R "$REPO_ROOT/docs" "$fw/docs"
  cp -R "$REPO_ROOT/templates/generated" "$fw/templates/generated"
  cp -R "$REPO_ROOT/templates/semgrep" "$fw/templates/semgrep"
  cp "$REPO_ROOT/templates/project-intake.md" "$fw/templates/project-intake.md"
  ( cd "$fw" && git init -q && git config user.email fw@t.local && git config user.name FW \
      && unset GITHUB_BASE_REF && git add -A && git commit -q -m "fake framework HEAD" ) >/dev/null 2>&1
}

# ── Runners ─────────────────────────────────────────────────────────────────

# seam <scripts-dir> <project-dir> [args…] — run the seam with cwd = project.
# stdout only; stderr is dropped so assertions read the ACTION's output.
seam() {
  local sd="$1" p="$2"; shift 2
  ( cd "$p" && unset GITHUB_BASE_REF; bash "$sd/process-checklist.sh" "$@" </dev/null 2>/dev/null )
}
# Same, with stderr merged (for the warning assertions).
seam_all() {
  local sd="$1" p="$2"; shift 2
  ( cd "$p" && unset GITHUB_BASE_REF; bash "$sd/process-checklist.sh" "$@" </dev/null 2>&1 )
}

# run_sync <framework-scripts-dir> <project-dir> [extra sync args…]
run_sync() {
  local sd="$1" p="$2"; shift 2
  ( cd "$p" && unset GITHUB_BASE_REF; CDF_HOME="$p/.no-such-cdf" SOIF_NONINTERACTIVE=1 \
      "$sd/upgrade-project.sh" --sync-framework "$@" </dev/null 2>&1 )
}

# _neuter_fn <file> <fn> <body> — replace fn's whole body, keeping the signature
# and every marker comment in the file (the anti-tautology mutation shape from
# tests/test-upgrade-sync-framework.sh). bash-3.2 / BSD-awk safe.
_neuter_fn() {
  local file="$1" fn="$2" body="$3" tmp
  tmp="$(mktemp)"
  awk -v fn="$fn" -v body="$body" '
    !mutated && index($0, fn "() {") == 1 { print; print "  " body; skip = 1; next }
    skip && $0 == "}" { print; skip = 0; mutated = 1; next }
    skip { next }
    { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
  chmod +x "$file"
}

# _sed_inplace <file> <sed-expr> — portable in-place sed (no GNU -i semantics),
# PRESERVING the file's mode.
#
# The obvious spelling ends `chmod +x "$file"`, because mktemp hands back 0600
# and the mv would otherwise narrow an executable. That idiom is a trap and it
# has now cost this branch two commits: applied to an in-tree file it silently
# turns a sourced 0644 lib into 0755, `git status` shows only "M", and the mode
# change rides along in the next commit. Read the mode first and put it back
# instead — GNU-first with the BSD fallback, per the house portability rule.
_sed_inplace() {
  local file="$1" expr="$2" tmp mode
  mode="$(stat -c '%a' "$file" 2>/dev/null || stat -f '%Lp' "$file" 2>/dev/null || echo "")"
  tmp="$(mktemp)"
  sed -e "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
  [ -n "$mode" ] && chmod "$mode" "$file" 2>/dev/null
  return 0
}

echo "== tests/test-delta-wp2-state-policy.sh =="
echo ""

# ════════════════════════════════════════════════════════════════════════════
echo "=== S — .claude/delta-state.json (§7.1) ==="
# ════════════════════════════════════════════════════════════════════════════

# ── S1: read with no state file -> the §7.1 empty document, rc 0 ────────────
T=$(mktemp -d); P="$T/proj"; mk_bare "$P"
out=$(seam "$REPO_ROOT/scripts" "$P" --delta-state-read); rc=$?
shape=$(printf '%s' "$out" | jq -r '
  [ (.schemaVersion == 1),
    (.active_delta == null),
    ((.hotfix_retros|type) == "array"), ((.hotfix_retros|length) == 0),
    ((.cadence|type) == "object"),
    ((.closed|type) == "array"),  ((.closed|length) == 0) ] | all' 2>/dev/null)
if [ "$rc" -eq 0 ] && [ "$shape" = "true" ] && [ ! -e "$P/.claude/delta-state.json" ]; then
  pass "S1: --delta-state-read with no state file emits the §7.1 empty document (rc 0) and CREATES NOTHING"
else
  fail_ "S1" "rc=$rc shape=$shape created=$([ -e "$P/.claude/delta-state.json" ] && echo yes || echo no); out:\n$out"
fi
rm -rf "$T"

# ── S2: write-then-read round trip through the seam ─────────────────────────
T=$(mktemp -d); P="$T/proj"; mk_bare "$P"
seam "$REPO_ROOT/scripts" "$P" --delta-state-update \
  '.active_delta = {"id":"DELTA-001","slug":"dark-mode","class":"feature","gates_required":["brief"],"gates_completed":[]}' >/dev/null
rc=$?
id=$(seam "$REPO_ROOT/scripts" "$P" --delta-state-read | jq -r '.active_delta.id // "MISSING"')
onfile=$(jq -r '.active_delta.slug // "MISSING"' "$P/.claude/delta-state.json" 2>/dev/null)
if [ "$rc" -eq 0 ] && [ "$id" = "DELTA-001" ] && [ "$onfile" = "dark-mode" ]; then
  pass "S2: --delta-state-update writes through the seam and --delta-state-read reads it back (active_delta is the object slot, §7.1)"
else
  fail_ "S2" "rc=$rc id=$id onfile=$onfile"
fi
rm -rf "$T"

# ── S3a: ATOMICITY through the production surface  [KILLS M2] ───────────────
# A shape-violating result reaches the WRITE (it is valid JSON — the filter
# succeeded), so the failure happens downstream of the redirect. That is what
# makes this a real atomicity pin rather than an input-validation pin: with a
# direct `> "$f"` the shell truncates the target before jq ever refuses.
T=$(mktemp -d); P="$T/proj"; mk_bare "$P"
seam "$REPO_ROOT/scripts" "$P" --delta-state-update '.closed = [{"id":"DELTA-000"}]' >/dev/null
before=$(_md5file "$P/.claude/delta-state.json")
out=$(seam_all "$REPO_ROOT/scripts" "$P" --delta-state-update '.hotfix_retros = "not-an-array"'); rc=$?
after=$(_md5file "$P/.claude/delta-state.json")
residue=$(ls -1 "$P/.claude" 2>/dev/null | grep -c 'delta-state.json.tmp')
# ANTI-VACUITY: `before` is empty when the file was never created, and an empty
# string equals an empty string. Without this guard the case passes against a
# missing implementation — which is exactly what it did on the RED baseline.
if [ -n "$before" ] && [ "$rc" -ne 0 ] && [ "$before" = "$after" ] && [ "$residue" = "0" ]; then
  pass "S3a: a refused write leaves .claude/delta-state.json BYTE-IDENTICAL and drops no .tmp residue (atomic tmp+mv, §7.1)"
else
  fail_ "S3a" "rc=$rc (expect non-zero) before=$before after=$after residue=$residue; out:\n$out"
fi
rm -rf "$T"

# ── S3b: ATOMICITY at the lib boundary  [KILLS M2] ─────────────────────────
# Invalid JSON on the write's stdin cannot be reached through the seam (a jq
# filter always emits valid JSON), so this half sources the lib directly. It is
# a unit probe of the writer, NOT a second production writer — D7's single
# writer is asserted by S6.
T=$(mktemp -d); P="$T/proj"; mk_bare "$P"
seam "$REPO_ROOT/scripts" "$P" --delta-state-update '.closed = [{"id":"DELTA-000"}]' >/dev/null
before=$(_md5file "$P/.claude/delta-state.json")
rc=0
( cd "$P" && . "$REPO_ROOT/scripts/lib/delta-state.sh" \
    && printf '%s' 'this is not json at all' | delta_state_write "." ) >/dev/null 2>&1 || rc=$?
after=$(_md5file "$P/.claude/delta-state.json")
if [ -n "$before" ] && [ "$rc" -ne 0 ] && [ "$before" = "$after" ]; then
  pass "S3b: delta_state_write refuses invalid JSON on stdin and the previous state file keeps its bytes"
else
  fail_ "S3b" "before='$before' (must be non-empty — the fixture write must have landed) rc=$rc (expect non-zero) after=$after"
fi
rm -rf "$T"

# ── S4: corrupt state file -> defaults + stderr warning, rc 0 ──────────────
T=$(mktemp -d); P="$T/proj"; mk_bare "$P"
printf '%s\n' '{ this is not valid json' > "$P/.claude/delta-state.json"
out=$(seam "$REPO_ROOT/scripts" "$P" --delta-state-read); rc=$?
merged=$(seam_all "$REPO_ROOT/scripts" "$P" --delta-state-read)
shape=$(printf '%s' "$out" | jq -r '.schemaVersion == 1 and .active_delta == null' 2>/dev/null)
warned=n; printf '%s' "$merged" | grep -q 'delta-state.json' && warned=y
if [ "$rc" -eq 0 ] && [ "$shape" = "true" ] && [ "$warned" = y ]; then
  pass "S4: a corrupt state file reads as the §7.1 defaults (rc 0) with a visible warning on stderr — callers never crash"
else
  fail_ "S4" "rc=$rc shape=$shape warned=$warned; stdout:\n$out"
fi
rm -rf "$T"

# ── S4b: valid JSON of the WRONG SHAPE also reads as the empty schema ──────
# The unparseable case (S4) is the obvious one. This is the one that bites: a
# file hand-edited into a top-level ARRAY parses fine, and every later caller
# that does `.active_delta.id` on it dies inside jq. It must ALSO be possible to
# write over — a guard that refused here would lock the single writer out of the
# only file it owns.
T=$(mktemp -d); P="$T/proj"; mk_bare "$P"
printf '%s\n' '["not","a","state","document"]' > "$P/.claude/delta-state.json"
out=$(seam "$REPO_ROOT/scripts" "$P" --delta-state-read); rc=$?
merged=$(seam_all "$REPO_ROOT/scripts" "$P" --delta-state-read)
shape=$(printf '%s' "$out" | jq -r '.schemaVersion == 1 and .active_delta == null' 2>/dev/null)
warned=n; printf '%s' "$merged" | grep -q 'not a state document' && warned=y
seam "$REPO_ROOT/scripts" "$P" --delta-state-update '.closed += [{"id":"DELTA-001"}]' >/dev/null; wrc=$?
n=$(jq -r '.closed | length' "$P/.claude/delta-state.json" 2>/dev/null)
if [ "$rc" -eq 0 ] && [ "$shape" = "true" ] && [ "$warned" = y ] && [ "$wrc" -eq 0 ] && [ "$n" = "1" ]; then
  pass "S4b: a state file that PARSES but is not a state document reads as the empty schema (rc 0, warned) and can still be written over — no self-inflicted deadlock"
else
  fail_ "S4b" "rc=$rc shape=$shape warned=$warned write rc=$wrc closed-len=$n (expect 0/true/y/0/1)"
fi
rm -rf "$T"

# ── S5: `closed` is append-only (§7.1) ─────────────────────────────────────
T=$(mktemp -d); P="$T/proj"; mk_bare "$P"
seam "$REPO_ROOT/scripts" "$P" --delta-state-update '.closed = [{"id":"DELTA-001"},{"id":"DELTA-002"}]' >/dev/null
before=$(_md5file "$P/.claude/delta-state.json")
seam "$REPO_ROOT/scripts" "$P" --delta-state-update '.closed = [{"id":"DELTA-001"}]' >/dev/null; rc=$?
after=$(_md5file "$P/.claude/delta-state.json")
seam "$REPO_ROOT/scripts" "$P" --delta-state-update '.closed += [{"id":"DELTA-003"}]' >/dev/null; rc_ok=$?
n=$(jq -r '.closed | length' "$P/.claude/delta-state.json" 2>/dev/null)
if [ -n "$before" ] && [ "$rc" -ne 0 ] && [ "$before" = "$after" ] && [ "$rc_ok" -eq 0 ] && [ "$n" = "3" ]; then
  pass "S5: 'closed' is append-only — a write that DROPS a row is refused and writes nothing; a genuine append succeeds"
else
  fail_ "S5" "drop rc=$rc (expect non-zero) before=$before after=$after; append rc=$rc_ok len=$n (expect 0/3)"
fi
rm -rf "$T"

# ── S6: single writer (D7), cited from the boundary lint ───────────────────
out=$(bash "$LINTER" 2>&1); rc=$?
card=$(bash "$LINTER" --list 2>/dev/null | grep -c 'cardinality 1/1')
if [ "$rc" -eq 0 ] && [ "$card" = "1" ]; then
  pass "S6: scripts/lint-delta-boundary.sh is rc=0 on the real tree with the seam allowlist at cardinality ONE — no core file but scripts/process-checklist.sh can name the state file (D7 single writer, §3.3 clause 3)"
else
  fail_ "S6" "lint rc=$rc (expect 0); cardinality-1 rows=$card (expect 1); out:\n$out"
fi

# ── Fixture + probes for the guard-atom cases (S5b / S7 / SH*) ─────────────
# WHY THESE EXIST. The first cut of this suite pinned only the DROP half of the
# append-only property and none of the shape atoms, so three atoms of the
# shipped write guard could be deleted with every PR-blocking check green
# (adversarial review R-WP2-1). The cases below are refusal assertions against
# the UN-mutated tree, one per atom — which is the cheap way to pin an atom that
# lives inside a jq program.

# Seed two closed rows, both unshipped. The §7.1 flow: a delta is CLOSED before
# it is SHIPPED, so `shipped_in` starts null and is backfilled at cut time.
seed_closed() {
  seam "$REPO_ROOT/scripts" "$1" --delta-state-update \
    '.closed = [{"id":"DELTA-004","class":"fix","closed_at":"2026-07-01T00:00:00Z","shipped_in":null},{"id":"DELTA-005","class":"feature","closed_at":"2026-07-28T10:00:00Z","shipped_in":null}]' >/dev/null
}

# Render a candidate document by applying a jq filter to the CURRENT state file.
cand_from() { jq -c "$2" "$1/.claude/delta-state.json"; }

# Feed a candidate straight to the writer under a named closed-rule, bypassing
# the actions. This is a unit probe of the PREDICATE — the only way to reach
# mutation shapes that no seam action can emit — not a second production writer.
lib_write() {
  local sd="$1" p="$2" rule="$3" doc="$4"
  ( cd "$p" && . "$sd/lib/delta-state.sh" && printf '%s\n' "$doc" | delta_state_write "." "$rule" ) >/dev/null 2>&1
}

# ── S5b: the REWRITE half of append-only  [pins APPEND-ATOM-PREFIX] ────────
# S5 pins the DROP (a truncation is caught by the length atom alone). Nothing
# pinned reorder, equal-length replacement or in-place field rewrite — so the
# prefix-equality atom was deletable with the suite at 24/0. Each filter below
# preserves the array LENGTH, so the length atom cannot catch any of them.
T=$(mktemp -d); P="$T/proj"; mk_bare "$P"; seed_closed "$P"
before=$(_md5file "$P/.claude/delta-state.json")
leaked=""
for f in \
  '.closed |= reverse' \
  '.closed[0] = {"id":"DELTA-999","class":"fix","closed_at":"2026-07-01T00:00:00Z","shipped_in":null}' \
  '.closed[-1].class = "hotfix"' \
  '.closed[-1].shipped_in = "v1.2.1"' \
  ; do
  seam "$REPO_ROOT/scripts" "$P" --delta-state-update "$f" >/dev/null 2>&1; rc=$?
  after=$(_md5file "$P/.claude/delta-state.json")
  if [ "$rc" -eq 0 ] || [ "$after" != "$before" ]; then leaked="$leaked [$f rc=$rc]"; fi
done
if [ -n "$before" ] && [ -z "$leaked" ]; then
  pass "S5b: reorder, equal-length row replacement, in-place field rewrite AND the bare shipped_in fill are all refused through --delta-state-update, file byte-identical each time — the REWRITE half of append-only, not just the drop"
else
  fail_ "S5b" "before='$before' (must be non-empty); accepted-when-it-should-refuse:$leaked"
fi
rm -rf "$T"

# ── S7: the shape atoms, one refusal each  [pins every SHAPE-ATOM-*] ───────
# Every one of these was ACCEPTED by the first cut (rc=0, file changed) — the
# reviewer's probe list. Each row names the atom it kills.
T=$(mktemp -d); P="$T/proj"; mk_bare "$P"; seed_closed "$P"
before=$(_md5file "$P/.claude/delta-state.json")
leaked=""
for f in \
  'del(.schemaVersion)' \
  '.schemaVersion = "banana"' \
  '.active_delta = "not-an-object"' \
  '.hotfix_retros = {}' \
  '.cadence = []' \
  '.closed = "not-an-array"' \
  '.closed += ["just-a-string"]' \
  '.EVIL = {"exfil": true}' \
  ; do
  seam "$REPO_ROOT/scripts" "$P" --delta-state-update "$f" >/dev/null 2>&1; rc=$?
  after=$(_md5file "$P/.claude/delta-state.json")
  if [ "$rc" -eq 0 ] || [ "$after" != "$before" ]; then leaked="$leaked [$f rc=$rc]"; fi
done
if [ -n "$before" ] && [ -z "$leaked" ]; then
  pass "S7: missing/non-numeric schemaVersion, non-object active_delta, non-array hotfix_retros, non-object cadence, non-array closed, a non-object closed ROW, and an arbitrary extra top-level key are each refused with the file byte-identical (the top level is closed-world: exactly the five §7.1 keys)"
else
  fail_ "S7" "before='$before' (must be non-empty); accepted-when-it-should-refuse:$leaked"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== SH — the shipped_in write-once pathway (§7.1 Part 2) ==="
# ════════════════════════════════════════════════════════════════════════════
# §7.1: "shipped_in is recorded at cut time via the seam — cut-release.sh asks
# process-checklist.sh to write it and never touches the file itself." That
# write is a null->value fill on an ALREADY-CLOSED row, which the append rule
# refuses (S5b's fourth filter). Resolution (adversarial review R-WP2-2): the
# append rule is NOT widened; the fill gets a dedicated action whose predicate
# permits exactly one mutation shape.

# ── SH1: (i) the backfill succeeds and changes NOTHING else ────────────────
T=$(mktemp -d); P="$T/proj"; mk_bare "$P"; seed_closed "$P"
pre_doc=$(jq -S -c '.' "$P/.claude/delta-state.json")
out=$(seam "$REPO_ROOT/scripts" "$P" --delta-state-ship DELTA-005 v1.2.1); rc=$?
shipped=$(jq -r '.closed[] | select(.id=="DELTA-005") | .shipped_in' "$P/.claude/delta-state.json" 2>/dev/null)
other=$(jq -r '.closed[] | select(.id=="DELTA-004") | .shipped_in' "$P/.claude/delta-state.json" 2>/dev/null)
# The whole document with that ONE field reverted must equal the original.
post_reverted=$(jq -S -c '(.closed[] | select(.id=="DELTA-005") | .shipped_in) = null' "$P/.claude/delta-state.json")
if [ "$rc" -eq 0 ] && [ "$shipped" = "v1.2.1" ] && [ "$other" = "null" ] \
   && [ "$pre_doc" = "$post_reverted" ]; then
  pass "SH1: --delta-state-ship records shipped_in on a closed row (rc 0) and the document is otherwise byte-for-byte what it was — the §7.1 cut-time write is expressible through the seam again"
else
  fail_ "SH1" "rc=$rc shipped='$shipped' (expect v1.2.1) other='$other' (expect null) doc-otherwise-identical=$([ "$pre_doc" = "$post_reverted" ] && echo yes || echo NO); out:\n$out"
fi
rm -rf "$T"

# ── SH2: (ii) WRITE-ONCE — a second ship, and an unknown id, are refused ───
T=$(mktemp -d); P="$T/proj"; mk_bare "$P"; seed_closed "$P"
seam "$REPO_ROOT/scripts" "$P" --delta-state-ship DELTA-005 v1.2.1 >/dev/null 2>&1
before=$(_md5file "$P/.claude/delta-state.json")
seam "$REPO_ROOT/scripts" "$P" --delta-state-ship DELTA-005 v9.9.9 >/dev/null 2>&1; rc_again=$?
a1=$(_md5file "$P/.claude/delta-state.json")
seam "$REPO_ROOT/scripts" "$P" --delta-state-ship DELTA-404 v1.0.0 >/dev/null 2>&1; rc_norow=$?
a2=$(_md5file "$P/.claude/delta-state.json")
seam "$REPO_ROOT/scripts" "$P" --delta-state-ship DELTA-004 >/dev/null 2>&1; rc_args=$?
still=$(jq -r '.closed[] | select(.id=="DELTA-005") | .shipped_in' "$P/.claude/delta-state.json" 2>/dev/null)
if [ -n "$before" ] && [ "$rc_again" -ne 0 ] && [ "$a1" = "$before" ] \
   && [ "$rc_norow" -ne 0 ] && [ "$a2" = "$before" ] \
   && [ "$rc_args" -eq 2 ] && [ "$still" = "v1.2.1" ]; then
  pass "SH2: shipped_in is WRITE-ONCE — a second ship of the same delta is refused (file byte-identical, original version intact); an unknown id is refused; a missing version argument is a usage error (rc 2)"
else
  fail_ "SH2" "before='$before'; second-ship rc=$rc_again md5=$a1; unknown-id rc=$rc_norow md5=$a2; missing-arg rc=$rc_args (expect 2); shipped_in now='$still' (expect v1.2.1)"
fi
rm -rf "$T"

# ── SH3: (iii) every OTHER closed[] mutation is refused through the ship
#        predicate too  [pins every SHIP-ATOM-*] ─────────────────────────────
# These candidates cannot be produced by the action (it only ever emits a
# single-row fill), so they are fed to the writer directly. Without them the
# ship pathway's atoms would be exactly as deletable as the append atoms were.
T=$(mktemp -d); P="$T/proj"; mk_bare "$P"; seed_closed "$P"
before=$(_md5file "$P/.claude/delta-state.json")
leaked=""
#   filter                                                                    | atom it pins
#   ------------------------------------------------------------------------- | ------------
for f in \
  '.active_delta = {"id":"DELTA-006"}' \
  '.closed[1].shipped_in = "v1.2.1" | .active_delta = {"id":"DELTA-006"}' \
  '.closed += [{"id":"DELTA-006","shipped_in":null}] | .closed[1].shipped_in = "v1.2.1"' \
  '.closed[1].shipped_in = "v1.2.1" | .closed[1].class = "hotfix"' \
  '.closed[1].shipped_in = 5' \
  '.closed[1].shipped_in = ""' \
  '.closed[0].shipped_in = "v1.0.0" | .closed[1].shipped_in = "v1.2.1"' \
  '.closed[0].class = "hotfix" | .closed[1].shipped_in = "v1.2.1"' \
  '.closed |= reverse' \
  '.' \
  ; do
  doc=$(cand_from "$P" "$f")
  lib_write "$REPO_ROOT/scripts" "$P" ship "$doc"; rc=$?
  after=$(_md5file "$P/.claude/delta-state.json")
  if [ "$rc" -eq 0 ] || [ "$after" != "$before" ]; then leaked="$leaked [$f rc=$rc]"; fi
done
# And an already-shipped row cannot be re-filled at the PREDICATE level either,
# not merely at delta_state_ship's friendlier check.
seam "$REPO_ROOT/scripts" "$P" --delta-state-ship DELTA-004 v1.0.0 >/dev/null 2>&1
before2=$(_md5file "$P/.claude/delta-state.json")
doc=$(cand_from "$P" '.closed[0].shipped_in = "v9.9.9"')
lib_write "$REPO_ROOT/scripts" "$P" ship "$doc"; rc_over=$?
after2=$(_md5file "$P/.claude/delta-state.json")
if [ -n "$before" ] && [ -z "$leaked" ] && [ "$rc_over" -ne 0 ] && [ "$before2" = "$after2" ]; then
  pass "SH3: the ship predicate refuses a change outside closed — alone AND riding along with an otherwise-legal fill — plus a length change, a second field changed on the filled row, a non-string version, an empty version, a two-row fill, a fill accompanied by a rewrite, a reorder, a no-op, and an overwrite of an already-set shipped_in. Exactly one mutation shape is permitted and nothing else"
else
  fail_ "SH3" "before='$before'; accepted-when-it-should-refuse:$leaked; overwrite rc=$rc_over md5 $before2 -> $after2"
fi
rm -rf "$T"

# ── SH4: there is no unguarded write path ─────────────────────────────────
T=$(mktemp -d); P="$T/proj"; mk_bare "$P"; seed_closed "$P"
before=$(_md5file "$P/.claude/delta-state.json")
doc=$(cand_from "$P" '.closed = []')
lib_write "$REPO_ROOT/scripts" "$P" "" "$doc"; rc_empty=$?
lib_write "$REPO_ROOT/scripts" "$P" "none" "$doc"; rc_none=$?
after=$(_md5file "$P/.claude/delta-state.json")
# A ship-rule write with NO previous file must also refuse: you cannot ship what
# was never closed.
Q="$T/fresh"; mk_bare "$Q"
lib_write "$REPO_ROOT/scripts" "$Q" ship '{"schemaVersion":1,"active_delta":null,"hotfix_retros":[],"cadence":{},"closed":[]}'; rc_fresh=$?
if [ -n "$before" ] && [ "$rc_empty" -ne 0 ] && [ "$rc_none" -ne 0 ] && [ "$before" = "$after" ] \
   && [ "$rc_fresh" -ne 0 ] && [ ! -e "$Q/.claude/delta-state.json" ]; then
  pass "SH4: an unrecognised closed-rule fails CLOSED (a typo is a refusal, not an unguarded write) and the ship rule refuses when there is no previous file — you cannot ship what was never closed"
else
  fail_ "SH4" "before='$before'; empty-rule rc=$rc_empty none-rule rc=$rc_none md5 $before -> $after; fresh-ship rc=$rc_fresh created=$([ -e "$Q/.claude/delta-state.json" ] && echo yes || echo no)"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== P — .claude/delta-policy.json (§7.2) ==="
# ════════════════════════════════════════════════════════════════════════════

# ── P1: the seed writer emits the §7.2 defaults, key for key ───────────────
T=$(mktemp -d); P="$T/proj"; mk_bare "$P"
seam "$REPO_ROOT/scripts" "$P" --delta-policy-init >/dev/null; rc=$?
f="$P/.claude/delta-policy.json"
ok=$(jq -r '
  [ (.schemaVersion == 1),
    (.classes.feature.gates == ["brief","brief_review","ledger_row","build_loop","close_review","changelog"]),
    (.classes.fix.gates == ["ledger_row","repro_test_red_first","close_review","changelog"]),
    (.classes.hotfix.gates == ["ledger_row","audit_row_at_open","retro_review","changelog"]),
    (.classes.hotfix.retro_due_days == 3),
    (.classes["security-patch"].gates == ["ledger_row","repro_test_red_first","dependency_scan","sbom_refresh","flagged_release_note","close_review","changelog"]),
    (.attribute_toggles.risk_core == ["brief_review"]),
    (.attribute_toggles.level_evolution == ["brief"]),
    (.attribute_toggles.touch_trigger == ["threat_model_refresh"]),
    (.risk_surfaces == []),
    (.size_thresholds == {"small":50,"significant":400}),
    (.cadence == {"routine_review_days":14,"deep_security_days":95}),
    (.fix_sla == {"SEV-1":"24h","SEV-2":"7d","SEV-3":"best-effort","SEV-4":"post-mvp"}),
    (.cvss_sla == {"critical":"24h","high":"7d","medium":"next-monthly","low":"next-quarterly"}),
    (.semver == {"feature":"minor","fix":"patch","hotfix":"patch","security-patch":"patch","breaking":"major"}),
    ((keys | length) == 9) ] | all' "$f" 2>/dev/null)
if [ "$rc" -eq 0 ] && [ "$ok" = "true" ]; then
  pass "P1: --delta-policy-init seeds the §7.2 defaults verbatim — both SLA tables, both size thresholds, the retuned cadence, the semver map, the attribute toggles and an EMPTY risk_surfaces (9 top-level keys, no more)"
else
  fail_ "P1" "rc=$rc all-keys-match=$ok; file:\n$(cat "$f" 2>/dev/null)"
fi
rm -rf "$T"

# ── P2: a second seed does NOT overwrite  [KILLS M4] ───────────────────────
T=$(mktemp -d); P="$T/proj"; mk_bare "$P"
printf '%s\n' '{"schemaVersion":1,"size_thresholds":{"small":7,"significant":9}}' > "$P/.claude/delta-policy.json"
before=$(_md5file "$P/.claude/delta-policy.json")
seam "$REPO_ROOT/scripts" "$P" --delta-policy-init >/dev/null; rc=$?
after=$(_md5file "$P/.claude/delta-policy.json")
small=$(jq -r '.size_thresholds.small' "$P/.claude/delta-policy.json" 2>/dev/null)
if [ "$before" = "$after" ] && [ "$small" = "7" ]; then
  pass "P2: --delta-policy-init on an EXISTING file is a no-op — the project's tuned values survive byte-for-byte (birth-once, §3.2)"
else
  fail_ "P2" "rc=$rc before=$before after=$after small=$small (expect 7)"
fi
rm -rf "$T"

# ── P3: absent KEY -> framework default; present key still wins  [KILLS M3] ─
T=$(mktemp -d); P="$T/proj"; mk_bare "$P"; write_stale_policy "$P"
d1=$(seam "$REPO_ROOT/scripts" "$P" --delta-policy-get cadence.routine_review_days); r1=$?
d2=$(seam "$REPO_ROOT/scripts" "$P" --delta-policy-get size_thresholds.significant); r2=$?
d3=$(seam "$REPO_ROOT/scripts" "$P" --delta-policy-get size_thresholds.small); r3=$?
d4=$(seam "$REPO_ROOT/scripts" "$P" --delta-policy-get semver.feature); r4=$?
d5=$(seam "$REPO_ROOT/scripts" "$P" --delta-policy-get classes.feature.gates); r5=$?
if [ "$r1" -eq 0 ] && [ "$d1" = "14" ] \
   && [ "$r2" -eq 0 ] && [ "$d2" = "400" ] \
   && [ "$r3" -eq 0 ] && [ "$d3" = "5" ] \
   && [ "$r4" -eq 0 ] && [ "$d4" = "minor" ] \
   && [ "$r5" -eq 0 ] && [ "$d5" = '["brief","ledger_row","build_loop","changelog"]' ]; then
  pass "P3: PER-KEY fallback — an absent whole key (cadence.*) and an absent NESTED key (size_thresholds.significant) resolve to the framework default, while the project's own size_thresholds.small (5) and its trimmed classes.feature.gates still win"
else
  fail_ "P3" "cadence.routine_review_days=$d1/rc$r1 (expect 14/0); size_thresholds.significant=$d2/rc$r2 (expect 400/0); size_thresholds.small=$d3/rc$r3 (expect 5/0); semver.feature=$d4/rc$r4 (expect minor/0); classes.feature.gates=$d5/rc$r5"
fi
rm -rf "$T"

# ── P4: absent FILE -> defaults throughout ─────────────────────────────────
T=$(mktemp -d); P="$T/proj"; mk_bare "$P"
a=$(seam "$REPO_ROOT/scripts" "$P" --delta-policy-get semver.feature); ra=$?
b=$(seam "$REPO_ROOT/scripts" "$P" --delta-policy-get classes.hotfix.retro_due_days); rb=$?
c=$(seam "$REPO_ROOT/scripts" "$P" --delta-policy-get risk_surfaces); rc2=$?
if [ "$ra" -eq 0 ] && [ "$a" = "minor" ] && [ "$rb" -eq 0 ] && [ "$b" = "3" ] \
   && [ "$rc2" -eq 0 ] && [ "$c" = "[]" ] && [ ! -e "$P/.claude/delta-policy.json" ]; then
  pass "P4: with NO policy file every key resolves to its framework default and the read CREATES NOTHING"
else
  fail_ "P4" "semver.feature=$a/rc$ra retro_due_days=$b/rc$rb risk_surfaces=$c/rc$rc2 created=$([ -e "$P/.claude/delta-policy.json" ] && echo yes || echo no)"
fi
rm -rf "$T"

# ── P5: corrupt file -> defaults + stderr warning, rc 0 ────────────────────
T=$(mktemp -d); P="$T/proj"; mk_bare "$P"
printf '%s\n' '{"schemaVersion": 1, ' > "$P/.claude/delta-policy.json"
before=$(_md5file "$P/.claude/delta-policy.json")
v=$(seam "$REPO_ROOT/scripts" "$P" --delta-policy-get cadence.deep_security_days); rc=$?
merged=$(seam_all "$REPO_ROOT/scripts" "$P" --delta-policy-get cadence.deep_security_days)
after=$(_md5file "$P/.claude/delta-policy.json")
warned=n; printf '%s' "$merged" | grep -q 'delta-policy.json' && warned=y
if [ "$rc" -eq 0 ] && [ "$v" = "95" ] && [ "$warned" = y ] && [ "$before" = "$after" ]; then
  pass "P5: a corrupt policy file fails TOWARD the framework defaults (rc 0) with a visible stderr warning, and is not repaired, replaced or deleted"
else
  fail_ "P5" "rc=$rc value=$v (expect 95) warned=$warned before=$before after=$after"
fi
rm -rf "$T"

# ── P6: a key in neither the file nor the defaults -> rc 1, no output ──────
T=$(mktemp -d); P="$T/proj"; mk_bare "$P"
v=$(seam "$REPO_ROOT/scripts" "$P" --delta-policy-get no_such_key.at_all); rc=$?
if [ "$rc" -eq 1 ] && [ -z "$v" ]; then
  pass "P6: an unknown key is rc=1 with EMPTY stdout — a caller can tell 'absent, defaulted' from 'no such policy key'"
else
  fail_ "P6" "rc=$rc (expect 1) out='$v' (expect empty)"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== N — NOTICE-ONLY on upgrade (§3.2, the # BL-099-DOC-GUARD form) ==="
# ════════════════════════════════════════════════════════════════════════════

# The flag matrix is MIRRORED from tests/test-upgrade-sync-framework.sh
# ::t_rendered_doc_never_applied — the shipped never-overwrite proof for
# CLAUDE.md / PROJECT_INTAKE.md — and widened by two combinations the rendered-
# doc test does not carry (a BARE sync and --dry-run), because §3.2 says
# "under ANY flag/env combination".
POLICY_COMBOS="bare|--dry-run|--install-hooks --apply-doc-updates sidecar|--install-hooks --apply-doc-updates overwrite|--install-hooks --apply-doc-updates overwrite --confirm-doc-overwrite"

# _notice_matrix <framework-scripts-dir> — runs every combination against a
# fresh stale-policy fixture and echoes "<verdict>|<detail>".
# verdict=ok when, for EVERY combination: the policy file is byte-identical, the
# `.claude/delta-policy*` namespace did not grow, and the notice named the
# missing key. Any other outcome echoes the first failing combination.
_notice_matrix() {
  local sd="$1" combo old_ifs T P before after pre_ls post_ls out
  old_ifs="$IFS"; IFS='|'
  # shellcheck disable=SC2086
  set -- $POLICY_COMBOS
  IFS="$old_ifs"
  for combo in "$@"; do
    T=$(mktemp -d); P="$T/proj"; mk_proj "$P"; write_stale_policy "$P"
    before=$(_md5file "$P/.claude/delta-policy.json")
    pre_ls=$(_policy_artifacts "$P")
    if [ "$combo" = "bare" ]; then
      out=$(run_sync "$sd" "$P")
    else
      # shellcheck disable=SC2086
      out=$(run_sync "$sd" "$P" $combo)
    fi
    after=$(_md5file "$P/.claude/delta-policy.json")
    post_ls=$(_policy_artifacts "$P")
    if [ "$before" != "$after" ]; then
      echo "mutated|'$combo' MUTATED .claude/delta-policy.json"; rm -rf "$T"; return 0
    fi
    if [ "$pre_ls" != "$post_ls" ]; then
      echo "grew|'$combo' grew the .claude/delta-policy* namespace: before:[$(echo "$pre_ls" | tr '\n' ' ')] after:[$(echo "$post_ls" | tr '\n' ' ')]"; rm -rf "$T"; return 0
    fi
    if ! printf '%s' "$out" | grep -qF 'Framework policy key(s) absent from it:'; then
      echo "nonotice|'$combo' printed no policy notice; tail:\n$(printf '%s' "$out" | tail -8)"; rm -rf "$T"; return 0
    fi
    if ! printf '%s' "$out" | grep -qF 'cadence'; then
      echo "unnamed|'$combo' printed a notice that does not name the missing key 'cadence'"; rm -rf "$T"; return 0
    fi
    rm -rf "$T"
  done
  echo "ok|"
}

# ── N1: the flag matrix ────────────────────────────────────────────────────
res=$(_notice_matrix "$REPO_ROOT/scripts")
verdict="${res%%|*}"; detail="${res#*|}"
if [ "$verdict" = "ok" ]; then
  pass "N1: under bare / --dry-run / sidecar / overwrite / overwrite+confirm, .claude/delta-policy.json is BYTE-IDENTICAL, the delta-policy* namespace does not grow (no .new, no .bak, no template copy), and the notice names the missing key"
else
  fail_ "N1" "$verdict — $detail"
fi

# ── N2: no policy file -> no notice, no file ───────────────────────────────
T=$(mktemp -d); P="$T/proj"; mk_proj "$P"
out=$(run_sync "$REPO_ROOT/scripts" "$P")
quiet=n; printf '%s' "$out" | grep -qF 'Framework policy key(s) absent from it:' || quiet=y
if [ "$quiet" = y ] && [ ! -e "$P/.claude/delta-policy.json" ]; then
  pass "N2: a project that never opened a delta gets NO notice and NO policy file — the upgrade does not seed one"
else
  fail_ "N2" "quiet=$quiet created=$([ -e "$P/.claude/delta-policy.json" ] && echo yes || echo no)"
fi
rm -rf "$T"

# ── N3: a COMPLETE policy file -> no notice at all ─────────────────────────
T=$(mktemp -d); P="$T/proj"; mk_proj "$P"
seam "$REPO_ROOT/scripts" "$P" --delta-policy-init >/dev/null
before=$(_md5file "$P/.claude/delta-policy.json")
out=$(run_sync "$REPO_ROOT/scripts" "$P")
after=$(_md5file "$P/.claude/delta-policy.json")
quiet=n; printf '%s' "$out" | grep -qF 'Framework policy key(s) absent from it:' || quiet=y
if [ -n "$before" ] && [ "$quiet" = y ] && [ "$before" = "$after" ]; then
  pass "N3: a policy file that is already current draws NO notice and is not touched — the notice fires iff a key is genuinely missing"
else
  fail_ "N3" "before='$before' (must be non-empty — the seed must have landed) quiet=$quiet after=$after; tail:\n$(printf '%s' "$out" | tail -8)"
fi
rm -rf "$T"

# ── N4: routing — the notice comes from the SEAM ──────────────────────────
# upgrade-project.sh is CORE and may not name a delta-module path (§3.3 T1) or
# grow the seam allowlist (§3.3 clause 3), so the notice arm is delivered
# core->core: it invokes scripts/process-checklist.sh --delta-policy-notice and
# the SEAM does the key-diff. This asserts the same text is reachable directly
# from the seam, and that the boundary lint is still clean with ONE seam.
T=$(mktemp -d); P="$T/proj"; mk_proj "$P"; write_stale_policy "$P"
direct=$(seam "$REPO_ROOT/scripts" "$P" --delta-policy-notice); rcd=$?
lint_out=$(bash "$LINTER" 2>&1); rcl=$?
t1_clean=y; printf '%s' "$lint_out" | grep -q 'T1' && t1_clean=n
named=n; printf '%s' "$direct" | grep -qF 'Framework policy key(s) absent from it:' && named=y
if [ "$rcd" -eq 0 ] && [ "$named" = y ] && [ "$rcl" -eq 0 ] && [ "$t1_clean" = y ]; then
  pass "N4: --delta-policy-notice is a SEAM action (rc 0, emits the notice); upgrade-project.sh reaches it core->core and the boundary lint stays rc=0 with no T1 hit and one seam"
else
  fail_ "N4" "seam rc=$rcd named=$named; lint rc=$rcl t1_clean=$t1_clean; lint:\n$lint_out"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== M — mutation proofs (each mutant is BUILT and RUN here) ==="
# ════════════════════════════════════════════════════════════════════════════

# ── M1: the upgrade path WRITES the policy file -> N1 goes RED ────────────
# The design's own mutation (§11-WP2). _postmvp_policy_notice's body is replaced
# with a write, the marker comments stay in the file, and the N1 matrix is
# re-run against the mutant framework: it must report `mutated`.
T=$(mktemp -d); FW="$T/fw"; mk_fake_framework "$FW"
_neuter_fn "$FW/scripts/upgrade-project.sh" _postmvp_policy_notice \
  'printf "%s\n" "{\"schemaVersion\":1,\"CLOBBERED\":true}" > "$PROJECT_ROOT/.claude/delta-policy.json"; return 0'
res=$(_notice_matrix "$FW/scripts"); verdict="${res%%|*}"
if [ "$verdict" = "mutated" ]; then
  pass "M1: an upgrade arm that WRITES .claude/delta-policy.json is caught by N1's byte assertion (verdict=$verdict) — the never-overwrite pin is load-bearing"
else
  fail_ "M1" "mutant verdict='$verdict' (expect 'mutated'); N1 did not detect a clobbering upgrade — the pin is vacuous. detail: ${res#*|}"
fi
rm -rf "$T"

# ── M1b: the upgrade path writes a SIDECAR -> N1 goes RED on the namespace ─
# The BL-099 round-2 hole (MAJOR-B) in its delta form: a write BESIDE the file
# leaves its bytes untouched, so only the namespace assertion can see it.
T=$(mktemp -d); FW="$T/fw"; mk_fake_framework "$FW"
_neuter_fn "$FW/scripts/upgrade-project.sh" _postmvp_policy_notice \
  'printf "%s\n" "{}" > "$PROJECT_ROOT/.claude/delta-policy.json.new"; return 0'
res=$(_notice_matrix "$FW/scripts"); verdict="${res%%|*}"
if [ "$verdict" = "grew" ]; then
  pass "M1b: an upgrade arm that writes a .new SIDECAR is caught by N1's NAMESPACE assertion (verdict=$verdict) — asserting bytes alone would have missed it, exactly as it did in BL-099 round 1"
else
  fail_ "M1b" "mutant verdict='$verdict' (expect 'grew'); the namespace assertion is vacuous. detail: ${res#*|}"
fi
rm -rf "$T"

# ── M2: break atomicity (write direct instead of tmp+mv) -> S3a/S3b RED ────
T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"
# Literally "write direct instead of tmp+mv": the render target becomes the
# state file itself and the rename disappears. Addressed by marker, not by line
# number (CLAUDE.md's citation rule) and not by a pattern that could silently
# match nothing — `changed` below is the anti-tautology check.
_sed_inplace "$MT/scripts/lib/delta-state.sh" '/DELTA-STATE-ATOMIC-TARGET/s@.*@  local target="$f"@'
_sed_inplace "$MT/scripts/lib/delta-state.sh" '/DELTA-STATE-ATOMIC-RENAME/s@.*@  :@'
changed=$(diff "$REPO_ROOT/scripts/lib/delta-state.sh" "$MT/scripts/lib/delta-state.sh" >/dev/null 2>&1 && echo n || echo y)
P="$T/proj"; mk_bare "$P"
seam "$MT/scripts" "$P" --delta-state-update '.closed = [{"id":"DELTA-000"}]' >/dev/null
mut_before=$(_md5file "$P/.claude/delta-state.json")
seam "$MT/scripts" "$P" --delta-state-update '.hotfix_retros = "not-an-array"' >/dev/null 2>&1
mut_after=$(_md5file "$P/.claude/delta-state.json")
P2d="$T/proj2"; mk_bare "$P2d"
seam "$MT/scripts" "$P2d" --delta-state-update '.closed = [{"id":"DELTA-000"}]' >/dev/null
b2=$(_md5file "$P2d/.claude/delta-state.json")
( cd "$P2d" && . "$MT/scripts/lib/delta-state.sh" && printf '%s' 'not json' | delta_state_write "." ) >/dev/null 2>&1
a2=$(_md5file "$P2d/.claude/delta-state.json")
if [ "$changed" = y ] && [ "$mut_before" != "$mut_after" ] && [ "$b2" != "$a2" ]; then
  pass "M2: writing DIRECT instead of tmp+mv destroys the previous state file on a refused write — S3a and S3b both go RED (mutation applied=$changed)"
else
  fail_ "M2" "mutation-applied=$changed (expect y); S3a bytes before=$mut_before after=$mut_after (must DIFFER); S3b before=$b2 after=$a2 (must DIFFER)"
fi
rm -rf "$T"

# ── M3: remove the per-key fallback -> P3 goes RED ────────────────────────
T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"
_sed_inplace "$MT/scripts/lib/delta-policy.sh" '/DELTA-POLICY-FALLBACK/s@.*@    | $pv as $v@'
changed=$(diff "$REPO_ROOT/scripts/lib/delta-policy.sh" "$MT/scripts/lib/delta-policy.sh" >/dev/null 2>&1 && echo n || echo y)
P="$T/proj"; mk_bare "$P"; write_stale_policy "$P"
mv1=$(seam "$MT/scripts" "$P" --delta-policy-get cadence.routine_review_days); mr1=$?
mv2=$(seam "$MT/scripts" "$P" --delta-policy-get size_thresholds.small); mr2=$?
if [ "$changed" = y ] && [ "$mv1" != "14" ] && [ "$mr2" -eq 0 ] && [ "$mv2" = "5" ]; then
  pass "M3: with the default lookup removed, an absent key returns nothing (got '$mv1'/rc$mr1 instead of 14) while a PRESENT key still resolves — P3 goes RED on the fallback half specifically (mutation applied=$changed)"
else
  fail_ "M3" "mutation-applied=$changed (expect y); mutant cadence.routine_review_days='$mv1'/rc$mr1 (must NOT be 14); mutant size_thresholds.small='$mv2'/rc$mr2 (must stay 5/0)"
fi
rm -rf "$T"

# ── M4: the seed writer overwrites an existing file -> P2 goes RED ────────
T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"
_sed_inplace "$MT/scripts/lib/delta-policy.sh" '/DELTA-POLICY-BIRTHONCE/s@.*@  :@'
changed=$(diff "$REPO_ROOT/scripts/lib/delta-policy.sh" "$MT/scripts/lib/delta-policy.sh" >/dev/null 2>&1 && echo n || echo y)
P="$T/proj"; mk_bare "$P"
printf '%s\n' '{"schemaVersion":1,"size_thresholds":{"small":7,"significant":9}}' > "$P/.claude/delta-policy.json"
b=$(_md5file "$P/.claude/delta-policy.json")
seam "$MT/scripts" "$P" --delta-policy-init >/dev/null 2>&1
a=$(_md5file "$P/.claude/delta-policy.json")
small=$(jq -r '.size_thresholds.small // "gone"' "$P/.claude/delta-policy.json" 2>/dev/null)
if [ "$changed" = y ] && [ "$b" != "$a" ] && [ "$small" = "50" ]; then
  pass "M4: with the birth-once guard removed the seed CLOBBERS a tuned policy file (small 7 -> $small) — P2 goes RED (mutation applied=$changed)"
else
  fail_ "M4" "mutation-applied=$changed (expect y); before=$b after=$a (must DIFFER); small=$small (expect 50, the framework default)"
fi
rm -rf "$T"

# ── M5: the T2 waiver on the seam invocation is load-bearing -> lint RED ───
# LINT-FORCED ROUTING, pinned. upgrade-project.sh reaches the seam by NAME, and
# the seam's action flags carry the `delta-` prefix by design — so that one line
# IS a T2 hit and carries the lint's inline waiver with a reason. Strip the
# marker and the boundary lint must go rc=1: that is what proves the waiver is
# doing work rather than decorating a line the lint never saw.
T=$(mktemp -d); MT="$T/tree"; mk_scripts_tree "$MT"
touch "$MT/init.sh"
control_out=$(bash "$LINTER" --root "$MT" 2>&1); control_rc=$?
_sed_inplace "$MT/scripts/upgrade-project.sh" 's|# lint-delta-boundary: allow.*$||'
mut_out=$(bash "$LINTER" --root "$MT" 2>&1); mut_rc=$?
waiver_hits=$(grep -c 'lint-delta-boundary: allow' "$REPO_ROOT/scripts/upgrade-project.sh")
if [ "$control_rc" -eq 0 ] && [ "$mut_rc" -eq 1 ] && [ "$waiver_hits" = "1" ] \
   && printf '%s' "$mut_out" | grep -q 'T2'; then
  pass "M5: upgrade-project.sh carries EXACTLY ONE inline T2 waiver ($waiver_hits) for its seam invocation; stripping the marker reds the boundary lint (rc $control_rc -> $mut_rc, T2) — the routing is a real edge consciously waived with a reason, and the SEAM allowlist never grew"
else
  fail_ "M5" "control rc=$control_rc (expect 0); mutant rc=$mut_rc (expect 1); waiver rows in upgrade-project.sh=$waiver_hits (expect 1); mutant out:\n$mut_out"
fi
rm -rf "$T"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
