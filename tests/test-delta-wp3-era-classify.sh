#!/usr/bin/env bash
# tests/test-delta-wp3-era-classify.sh — Delta Track WP3.
#
# SPEC: docs/designs/2026-08-02-delta-track-v1.md §10.1 (the era invariant
# `active_delta != null => current_phase == 4`, its two enforcement points, and
# the [WARN]-trap warning), §10.2 (no new machinery for monotonicity), §4.1–§4.3
# (the four classes, the derived-then-confirmed attributes, confirm-not-quiz on
# the `# BL-204-PREFILL` pattern), §5.2 (the gate table the classifier feeds),
# §7.1 (gates_required materialised AT OPEN; the single-writer rule), §7.2 (the
# policy keys every derivation reads), §11-WP3.
#
# (No `# BL-NNN-…` marker anywhere in the delta track on purpose: no backlog
# entry exists for this build and minting one would red
# scripts/lint-bl-markers.sh, whose first pass resolves every marker to a real
# `## BL-NNN:` entry. The design-doc path above is the citation, per the WP1 and
# WP2 precedent.)
#
# ═════════════════════════════════════════════════════════════════════════════
# EXIT CODES, NEVER LABELS
#
# Every assertion below reads a process EXIT CODE, a JSON value read back off
# disk, or a byte-level md5. None reads a printed [OK]/[WARN]/[FAIL] banner.
# CLAUDE.md's `[WARN]` trap is precisely that the label and the exit predicate
# can disagree — in check-phase-gate.sh two arms printing the same word have
# opposite gate outcomes because one increments a counter — and §10.1 repeats
# the warning specifically for this WP. The validate.sh arm (V1/m5) is where it
# bites hardest, and it is asserted in BOTH directions on the exit code.
#
# ═════════════════════════════════════════════════════════════════════════════
# WHAT THIS SUITE PINS, AND WHICH MUTANT EACH ROW KILLS
#
#   E — THE ERA INVARIANT (§10.1), the load-bearing refusal
#     E1  --open REFUSED at phases 0, 1, 2, 3 and ALLOWED at 4  KILLS m1
#     E2  a refused open writes NOTHING — no state file appears
#     E3  an unreadable / absent phase records fails CLOSED (refused), because
#         "cannot tell" must not read as "phase 4"
#
#   A — SECOND ACTIVATION (§7.1) — the refusal WP2 explicitly DEFERRED to WP3
#     A1  a second --open while a delta is open is REFUSED, names the open
#         delta, and leaves the first delta's row BYTE-IDENTICAL      KILLS m2
#     A2  the other direction: nulling active_delta through the seam unblocks
#         the next open. Without this the refusal could be a script that always
#         refuses, which is not a guard.
#
#   D — THE §4.2 DERIVATIONS
#     D1  the phrase->class tiers, in order (security > hotfix > fix > feature)
#     D2  risk: a REAL git diff intersected with the policy's risk_surfaces;
#         and the §13-R4 residual — an EMPTY risk_surfaces makes every delta
#         feature-local, stated in the provenance rather than implied
#     D3  level: measured from a REAL git diff against the policy brackets, and
#         a policy RETUNE moves the bracket                            KILLS m3
#     D4  severity: from the BUGS.md row when one is cited; from phrasing
#         otherwise; NONE for a feature
#
#   R — RAISE FREE, LOWER REASON-RECORDED (§4.2)
#     R1  a raise sticks and toggles the extra gate
#     R2  a lower with no reason available is REFUSED (exit 5), writes nothing
#     R3  a lower WITH a reason is recorded on the delta's own row
#
#   G — gates_required MATERIALISED AT OPEN (§7.1) FROM §5.2
#     G1  each of the four classes yields its §5.2 base row, exactly
#     G2  risk: core adds brief_review                                 KILLS m4
#     G3  level: evolution adds brief
#     G4  the toggles are READ FROM POLICY: a project that retunes
#         attribute_toggles gets ITS gate, not the framework's
#
#   V — THE validate.sh ARM (§10.1's second enforcement point)
#     V1  the report FIRES at phase < 4 with a delta open, and the EXIT CODE is
#         identical to the same fixture without one                    KILLS m5
#     V2  at phase 4 the same state is CONSISTENT and nothing is reported
#     V3  the lint-forced routing is real: validate.sh reaches the state through
#         the ONE seam and its inline T2 waiver is load-bearing        KILLS m6
#
#   T — CONFIRM, DO NOT QUIZ (§4.3)
#     T1  the transcript's SHAPE: "You said", four labelled lines EACH carrying
#         a provenance parenthetical, and the one-question footer. Shape, not
#         prose — the wording is the design's and may be tuned.
#     T2  a scripted run with nobody to confirm REFUSES rather than
#         auto-accepting a side-effectful open (the repo's hard-N policy)
#
#   S — --status
#     S1  reports "no delta open" and then the open delta, rc 0 both ways
#
#   B — BOUNDARY (D1), cited not re-implemented
#     B1  the real tree is clean, the seam allowlist is still cardinality ONE,
#         and both new module files are in the DELTA manifest
#
# ═════════════════════════════════════════════════════════════════════════════
# COUNTERFACTUAL DISCIPLINE — how the mutations below are built
#
# Each mutation is an ANCHORED SINGLE-SITE neuter: the address is a marker
# comment pinned to END-OF-LINE (`/# DELTA-OPEN-ERA-GUARD$/`), never a bare
# substring. WP2's suite records why: an unanchored `/SHAPE-ATOM-CLOSED/` also
# matches SHAPE-ATOM-CLOSED-ROWS, neuters two atoms at once, and credits the
# resulting RED to the wrong one — a sweep that over-matches produces false
# GREEN pins, which is worse than no sweep. So every mutation here asserts
# THREE things before it believes its own result:
#   • the marker resolves to EXACTLY ONE line in the pristine file (site count);
#   • the mutated file DIFFERS from the pristine one (anti-tautology — a sed
#     that matched nothing would otherwise "prove" the guard by leaving it
#     intact);
#   • EXACTLY ONE LINE changed (one `<` and one `>` in the diff), so a mutation
#     cannot quietly demolish half the file and credit the RED to the guard.
#
# FRESH-FIXTURE ISOLATION. Every mutation builds its own mktemp project. m2's
# case in particular MUST start from a tree where the era guard would pass
# (phase 4) — run it at phase 2 and the era guard refuses first, the
# second-activation guard never executes, and the mutant looks pinned when it is
# not. That masking is the exact failure WP2's sweep found twice.
#
# MODE-PRESERVING HARNESS. `_sed_inplace` reads each file's mode and puts it
# back. The obvious spelling ends `chmod +x`, which silently turns a sourced
# 0644 lib into 0755; `git status` shows only "M" and the mode rides along in
# the next commit. That trap fired three times on this wave — do not
# "simplify" the mode dance away.
#
# ═════════════════════════════════════════════════════════════════════════════
# HERMETICITY: every fixture is a mktemp -d project carrying NO init.sh and NO
# templates/generated, so guard_not_in_framework sees a project and not the
# framework. Git fixtures configure an identity and unset GITHUB_BASE_REF. No
# remote is ever created; nothing reaches the network; nothing is written inside
# the checkout. bash-3.2 safe: no associative arrays, no ${var,,}, no ((x++)).
#
# LANE: registered in tests/full-project-test-suite.sh AND in the tests.yml
# `unit-shard` list. Its executed lines never name init.sh — the boundary-lint
# fixtures satisfy the vacuity floor from scripts/ alone.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINTER="$REPO_ROOT/scripts/lint-delta-boundary.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for tests/test-delta-wp3-era-classify.sh" >&2
  exit 2
fi
if ! command -v git >/dev/null 2>&1; then
  echo "git is required for tests/test-delta-wp3-era-classify.sh" >&2
  exit 2
fi

# Portable md5 of a single file (macOS `md5 -q`, Linux `md5sum`) — house pattern.
_md5file() {
  if command -v md5 >/dev/null 2>&1; then md5 -q "$1"
  else md5sum "$1" | awk '{print $1}'; fi
}

# ── Fixtures ────────────────────────────────────────────────────────────────

# A bare project at a given phase: enough for delta.sh and the seam, no git.
mk_proj() {
  local d="$1" phase="$2"
  mkdir -p "$d/.claude"
  printf '{"track":"light","deployment":"personal","poc_mode":null,"current_phase":%s,"phases":{}}\n' \
    "$phase" > "$d/.claude/phase-state.json"
}

# The same, plus the four framework-file stubs scripts/validate.sh reads before
# it gets to the phase section. It still reports plenty of missing artifacts —
# that is fine and deliberate: V1 asserts the exit code is UNCHANGED between two
# otherwise-identical trees, not that it is zero. A pristine fixture would be a
# weaker pin, because it would only prove the arm is silent in the one
# configuration where nothing else has anything to say.
mk_validate_proj() {
  local d="$1" phase="$2"
  mk_proj "$d" "$phase"
  mkdir -p "$d/docs/reference" "$d/docs/platform-modules"
  {
    printf '%s\n' '- **Project:** fixture'
    printf '%s\n' '- **Platform:** web'
    printf '%s\n' '- **Track:** light'
    printf '%s\n' '- **Primary Language:** python'
  } > "$d/CLAUDE.md"
}

# A REAL git project, so the §4.2 derivations run against a real
# `git diff --name-only` / `--shortstat` rather than a hand-fed list. Two
# tracked files: one under a path a project would plausibly call a risk surface,
# one that is plainly not.
mk_git_proj() {
  local d="$1" phase="$2"
  mk_proj "$d" "$phase"
  mkdir -p "$d/src/auth" "$d/src/ui"
  printf 'base\n' > "$d/src/auth/login.ts"
  printf 'base\n' > "$d/src/ui/theme.ts"
  ( cd "$d" && git init -q \
      && git config user.email t@t.local && git config user.name T \
      && unset GITHUB_BASE_REF && git add -A && git commit -q -m init ) >/dev/null 2>&1
}

# grow <file> <n> — append exactly n lines, so `git diff --shortstat` reports a
# KNOWN insertion count and the level bracket is a measurement and not a guess.
grow() {
  local f="$1" n="$2" i=1
  while [ "$i" -le "$n" ]; do printf 'added line %s\n' "$i" >> "$f"; i=$((i + 1)); done
}

write_policy() { printf '%s\n' "$2" > "$1/.claude/delta-policy.json"; }

# Copy the framework's scripts/ tree so a MUTATED module can be run without
# touching the checkout. Nothing else is copied: init.sh is neither referenced
# nor needed, and the boundary-lint fixtures reach their vacuity floor from
# scripts/ alone.
mk_scripts_tree() {
  mkdir -p "$1"
  cp -R "$REPO_ROOT/scripts" "$1/scripts"
}

# ── Runners ─────────────────────────────────────────────────────────────────

# delta_run <scripts-dir> <project-dir> [args…] — stdout+stderr merged; the
# subshell's exit code is the script's.
delta_run() {
  local sd="$1" p="$2"; shift 2
  ( cd "$p" && unset GITHUB_BASE_REF; bash "$sd/delta.sh" "$@" </dev/null 2>&1 )
}

# seam <scripts-dir> <project-dir> [args…] — the single writer, used by the
# tests only where a test must ARRANGE state (A2 closes a delta). Assertions
# read the file directly; arrangements go through the seam, exactly like
# production.
seam() {
  local sd="$1" p="$2"; shift 2
  ( cd "$p" && unset GITHUB_BASE_REF; bash "$sd/process-checklist.sh" "$@" </dev/null 2>/dev/null )
}

validate_run() {
  local sd="$1" p="$2"
  ( cd "$p" && unset GITHUB_BASE_REF; bash "$sd/validate.sh" </dev/null 2>&1 )
}

# active_json <project-dir> [jq-flags…] <filter> — read an assertion straight
# off the state file the seam wrote. Assertions read the FILE, never a printed
# banner. A missing or unreadable file yields the literal READ-FAILED, which no
# expectation below ever matches — a helper that returned "" would let an
# absent file satisfy any "must not contain X" assertion, and that is precisely
# the vacuous-pin class this suite exists to avoid.
active_json() {
  local p="$1"; shift
  jq "$@" "$p/.claude/delta-state.json" 2>/dev/null || printf 'READ-FAILED'
}

# ── Mutation harness ────────────────────────────────────────────────────────

# _sed_inplace <file> <sed-expr> — portable in-place sed, PRESERVING the mode.
# (Inherited verbatim from tests/test-delta-wp2-state-policy.sh; see this file's
# header for why the `chmod +x` spelling is a trap.)
_sed_inplace() {
  local file="$1" expr="$2" tmp mode
  mode="$(stat -c '%a' "$file" 2>/dev/null || stat -f '%Lp' "$file" 2>/dev/null || echo "")"
  tmp="$(mktemp)"
  sed -e "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
  [ -n "$mode" ] && chmod "$mode" "$file" 2>/dev/null
  return 0
}

# _mutation_report <pristine> <mutant> <marker-regex> — echoes
# "<sites>|<changed>|<lines-changed>" so every mutation case can assert all
# three counterfactual properties at once. See this file's header.
_mutation_report() {
  local orig="$1" mut="$2" marker="$3" sites changed n
  sites="$(grep -c "$marker" "$orig" || true)"
  case "$sites" in ''|*[!0-9]*) sites=0 ;; esac
  if diff "$orig" "$mut" >/dev/null 2>&1; then changed=n; else changed=y; fi
  n="$(diff "$orig" "$mut" | grep -c '^[<>]' || true)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s|%s|%s' "$sites" "$changed" "$n"
}

echo "== tests/test-delta-wp3-era-classify.sh =="
echo ""

# ════════════════════════════════════════════════════════════════════════════
echo "=== E — the era invariant: active_delta != null => current_phase == 4 (§10.1) ==="
# ════════════════════════════════════════════════════════════════════════════

# ── E1: refused at 0/1/2/3, allowed at 4 — ON THE EXIT CODE  [KILLS m1] ─────
T=$(mktemp -d)
e1_detail=""
e1_ok=y
for ph in 0 1 2 3; do
  P="$T/p$ph"; mk_proj "$P" "$ph"
  delta_run "$REPO_ROOT/scripts" "$P" --open --describe "the CSV export crashes on unicode" --confirm >/dev/null 2>&1
  rc=$?
  e1_detail="$e1_detail phase$ph=rc$rc"
  [ "$rc" -eq 3 ] || e1_ok=n
done
P="$T/p4"; mk_proj "$P" 4
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "the CSV export crashes on unicode" --confirm >/dev/null 2>&1
rc4=$?
e1_detail="$e1_detail phase4=rc$rc4"
[ "$rc4" -eq 0 ] || e1_ok=n
if [ "$e1_ok" = y ]; then
  pass "E1: --open is refused at phases 0/1/2/3 (rc 3) and allowed at phase 4 (rc 0) —$e1_detail"
else
  fail_ "E1" "expected rc 3 at phases 0-3 and rc 0 at phase 4; got:$e1_detail"
fi
rm -rf "$T"

# ── E2: a refused open writes NOTHING ───────────────────────────────────────
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 2
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "add dark mode" --confirm >/dev/null 2>&1
rc=$?
created=n; [ -e "$P/.claude/delta-state.json" ] && created=y
if [ "$rc" -eq 3 ] && [ "$created" = n ]; then
  pass "E2: a refused open creates no state at all (rc $rc, state file created=$created) — the refusal is before the write, not a write that is later undone"
else
  fail_ "E2" "rc=$rc (expect 3); state file created=$created (expect n)"
fi
rm -rf "$T"

# ── E3: an unreadable phase fails CLOSED ────────────────────────────────────
# "I cannot tell what phase this is" must never resolve to 4. Two shapes: no
# phase-state.json at all, and one whose current_phase is not a number.
T=$(mktemp -d)
P1="$T/nofile"; mkdir -p "$P1/.claude"
delta_run "$REPO_ROOT/scripts" "$P1" --open --describe "add dark mode" --confirm >/dev/null 2>&1; r1=$?
P2="$T/garbage"; mkdir -p "$P2/.claude"
printf '%s\n' '{"current_phase":"not-a-number"}' > "$P2/.claude/phase-state.json"
delta_run "$REPO_ROOT/scripts" "$P2" --open --describe "add dark mode" --confirm >/dev/null 2>&1; r2=$?
if [ "$r1" -eq 3 ] && [ "$r2" -eq 3 ]; then
  pass "E3: an absent (rc $r1) or unparseable (rc $r2) phase record fails CLOSED — 'cannot tell' never reads as phase 4"
else
  fail_ "E3" "absent rc=$r1, unparseable rc=$r2 (both must be 3)"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== A — the second-activation refusal WP2 deferred to WP3 (§7.1) ==="
# ════════════════════════════════════════════════════════════════════════════

# ── A1: a second open is refused and destroys nothing  [KILLS m2] ───────────
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "the CSV export crashes on unicode" --confirm >/dev/null 2>&1
first_id="$(active_json "$P" '.active_delta.id')"
before="$(_md5file "$P/.claude/delta-state.json")"
out=$(delta_run "$REPO_ROOT/scripts" "$P" --open --describe "add dark mode" --confirm); rc=$?
after="$(_md5file "$P/.claude/delta-state.json")"
names=n; printf '%s' "$out" | grep -qF 'DELTA-001' && names=y
if [ "$rc" -eq 4 ] && [ "$before" = "$after" ] && [ "$names" = y ] && [ "$first_id" = '"DELTA-001"' ]; then
  pass "A1: a second --open while DELTA-001 is open is refused (rc $rc), names the open delta, and leaves the record BYTE-IDENTICAL — the schema's single slot would otherwise have accepted the overwrite and taken gates_completed with it"
else
  fail_ "A1" "rc=$rc (expect 4); bytes before=$before after=$after (must MATCH); names-open-delta=$names; first_id=$first_id"
fi
rm -rf "$T"

# ── A2: the other direction — nulling active_delta unblocks the next open ───
# Without this the refusal could be a script that always refuses.
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "the CSV export crashes on unicode" --confirm >/dev/null 2>&1
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "add dark mode" --confirm >/dev/null 2>&1; blocked=$?
# Close it the way a close actually closes (§7.1): the row moves to the
# append-only `closed` tail AND the slot is emptied, in one seam write. Nulling
# the slot alone would erase the id from the record entirely, and the next open
# would legitimately reuse DELTA-001 — which would make this case pass for the
# wrong reason.
seam "$REPO_ROOT/scripts" "$P" --delta-state-update \
  '.closed += [{"id": .active_delta.id, "class": .active_delta.class, "closed_at": "2026-08-03T00:00:00Z", "shipped_in": null}] | .active_delta = null' \
  >/dev/null 2>&1; closed_rc=$?
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "add dark mode" --confirm >/dev/null 2>&1; unblocked=$?
second_id="$(active_json "$P" '.active_delta.id')"
if [ "$blocked" -eq 4 ] && [ "$closed_rc" -eq 0 ] && [ "$unblocked" -eq 0 ] && [ "$second_id" = '"DELTA-002"' ]; then
  pass "A2: with active_delta nulled through the seam the next open succeeds (rc $blocked -> $unblocked) and takes the NEXT id ($second_id) — the guard tracks state, it does not just always refuse"
else
  fail_ "A2" "blocked rc=$blocked (expect 4); close rc=$closed_rc (expect 0); unblocked rc=$unblocked (expect 0); new id=$second_id (expect \"DELTA-002\")"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== D — the §4.2 derivations ==="
# ════════════════════════════════════════════════════════════════════════════

# ── D1: the phrase->class tiers, IN ORDER ───────────────────────────────────
# Order is the whole algorithm: the last phrase carries fix AND production AND
# security wording, and security must win because a security-patch's
# obligations are the ones most costly to discover you skipped.
T=$(mktemp -d)
d1_ok=y; d1_detail=""
_d1() {
  local phrase="$1" want="$2" P got
  P="$T/$3"; mk_proj "$P" 4
  delta_run "$REPO_ROOT/scripts" "$P" --open --describe "$phrase" --confirm >/dev/null 2>&1
  got="$(active_json "$P" -r '.active_delta.class')"
  d1_detail="$d1_detail [$want<-$got]"
  [ "$got" = "$want" ] || d1_ok=n
}
_d1 "add dark mode to the settings screen"        feature        c1
_d1 "the CSV export crashes on unicode"           fix            c2
_d1 "checkout is down in production right now"    hotfix         c3
_d1 "fix the XSS in the comment box in production" security-patch c4
if [ "$d1_ok" = y ]; then
  pass "D1: the phrase->class tiers propose feature/fix/hotfix/security-patch in order, and the all-three-tiers phrase resolves to security-patch —$d1_detail"
else
  fail_ "D1" "want<-got:$d1_detail"
fi
rm -rf "$T"

# ── D2: risk from a REAL diff x the policy's risk_surfaces, plus §13-R4 ─────
T=$(mktemp -d)
Pc="$T/core"; mk_git_proj "$Pc" 4
write_policy "$Pc" '{"schemaVersion":1,"risk_surfaces":["src/auth/**"]}'
grow "$Pc/src/auth/login.ts" 3
delta_run "$REPO_ROOT/scripts" "$Pc" --open --describe "token check is wrong" --confirm >/dev/null 2>&1
risk_core="$(active_json "$Pc" -r '.active_delta.attributes.risk')"

Pl="$T/local"; mk_git_proj "$Pl" 4
write_policy "$Pl" '{"schemaVersion":1,"risk_surfaces":["src/auth/**"]}'
grow "$Pl/src/ui/theme.ts" 3
delta_run "$REPO_ROOT/scripts" "$Pl" --open --describe "the theme toggle is wrong" --confirm >/dev/null 2>&1
risk_local="$(active_json "$Pl" -r '.active_delta.attributes.risk')"

# §13-R4, asserted rather than trusted: with risk_surfaces EMPTY, a diff that
# would otherwise be core reads feature-local — and the transcript says WHY,
# rather than answering as though something had been checked.
Pe="$T/empty"; mk_git_proj "$Pe" 4
write_policy "$Pe" '{"schemaVersion":1,"risk_surfaces":[]}'
grow "$Pe/src/auth/login.ts" 3
out_e=$(delta_run "$REPO_ROOT/scripts" "$Pe" --open --describe "token check is wrong" --confirm)
risk_empty="$(active_json "$Pe" -r '.active_delta.attributes.risk')"
says_why=n; printf '%s' "$out_e" | grep -qi 'no risk surfaces are configured' && says_why=y
if [ "$risk_core" = "core" ] && [ "$risk_local" = "feature-local" ] \
   && [ "$risk_empty" = "feature-local" ] && [ "$says_why" = y ]; then
  pass "D2: a real diff touching src/auth/** derives risk=core; one touching src/ui/ derives feature-local; and with risk_surfaces EMPTY the same core-ish diff derives feature-local WITH the §13-R4 reason printed (not silently)"
else
  fail_ "D2" "core-case=$risk_core (expect core); local-case=$risk_local (expect feature-local); empty-surfaces=$risk_empty (expect feature-local); residual stated=$says_why"
fi
rm -rf "$T"

# ── D3: level from a REAL diff against the policy brackets  [KILLS m3] ──────
# The SAME ten-line diff lands in a different bracket under a different policy.
# That is the whole claim: the thresholds are READ, not compiled in.
T=$(mktemp -d)
Pd="$T/default"; mk_git_proj "$Pd" 4
grow "$Pd/src/ui/theme.ts" 10
delta_run "$REPO_ROOT/scripts" "$Pd" --open --describe "the theme toggle is wrong" --confirm >/dev/null 2>&1
lvl_default="$(active_json "$Pd" -r '.active_delta.attributes.level')"

Pr="$T/retuned"; mk_git_proj "$Pr" 4
write_policy "$Pr" '{"schemaVersion":1,"size_thresholds":{"small":5}}'
grow "$Pr/src/ui/theme.ts" 10
delta_run "$REPO_ROOT/scripts" "$Pr" --open --describe "the theme toggle is wrong" --confirm >/dev/null 2>&1
lvl_retuned="$(active_json "$Pr" -r '.active_delta.attributes.level')"

Pv="$T/evolution"; mk_git_proj "$Pv" 4
write_policy "$Pv" '{"schemaVersion":1,"size_thresholds":{"small":2,"significant":5}}'
grow "$Pv/src/ui/theme.ts" 10
delta_run "$REPO_ROOT/scripts" "$Pv" --open --describe "the theme toggle is wrong" --confirm >/dev/null 2>&1
lvl_evo="$(active_json "$Pv" -r '.active_delta.attributes.level')"
if [ "$lvl_default" = "small" ] && [ "$lvl_retuned" = "significant" ] && [ "$lvl_evo" = "evolution" ]; then
  pass "D3: the same measured 10-line diff derives level=small on the framework thresholds, significant when the project retunes small to 5, and evolution when it retunes significant to 5 — the brackets are read from policy"
else
  fail_ "D3" "default=$lvl_default (expect small); small:5 retune=$lvl_retuned (expect significant); significant:5 retune=$lvl_evo (expect evolution)"
fi
rm -rf "$T"

# ── D4: severity — the BUGS.md row wins; phrasing is the fallback ───────────
T=$(mktemp -d)
Pb="$T/bugrow"; mk_proj "$Pb" 4
{
  printf '%s\n' '| # | Severity | Status | Feature | Description | Session | Disposition | Fix Reference | Verified In |'
  printf '%s\n' '|---|---|---|---|---|---|---|---|---|'
  printf '%s\n' '| 12 | SEV-1 | Open | Export | CSV export crashes | Session 3 | Fix Now | | |'
} > "$Pb/BUGS.md"
delta_run "$REPO_ROOT/scripts" "$Pb" --open --describe "the crash in BUG-12 is still there" --confirm >/dev/null 2>&1
sev_row="$(active_json "$Pb" -r '.active_delta.attributes.severity')"

Pp="$T/phrase"; mk_proj "$Pp" 4
delta_run "$REPO_ROOT/scripts" "$Pp" --open --describe "the export is broken but there is a workaround" --confirm >/dev/null 2>&1
sev_phrase="$(active_json "$Pp" -r '.active_delta.attributes.severity')"

Pf="$T/feature"; mk_proj "$Pf" 4
delta_run "$REPO_ROOT/scripts" "$Pf" --open --describe "add dark mode" --confirm >/dev/null 2>&1
sev_feature="$(active_json "$Pf" -r '.active_delta.attributes.severity')"
if [ "$sev_row" = "SEV-1" ] && [ "$sev_phrase" = "SEV-2" ] && [ "$sev_feature" = "null" ]; then
  pass "D4: severity is read from the cited BUGS.md row when one exists (SEV-1, overriding the phrasing default), falls back to the Severity Guide's wording otherwise ($sev_phrase), and is null for a feature"
else
  fail_ "D4" "BUGS.md row=$sev_row (expect SEV-1); phrasing=$sev_phrase (expect SEV-2); feature=$sev_feature (expect null)"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== R — raises are free, lowers are reason-recorded (§4.2) ==="
# ════════════════════════════════════════════════════════════════════════════

# ── R1: a raise sticks, with no justification required ──────────────────────
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "the export is broken" --risk core --level evolution --confirm >/dev/null 2>&1
rc=$?
attrs="$(active_json "$P" -c '.active_delta.attributes')"
reasons="$(active_json "$P" -c '.active_delta.attribute_reasons')"
if [ "$rc" -eq 0 ] \
   && [ "$(printf '%s' "$attrs" | jq -r '.risk')" = "core" ] \
   && [ "$(printf '%s' "$attrs" | jq -r '.level')" = "evolution" ] \
   && [ "$(printf '%s' "$reasons" | jq -r '[.risk, .level] | all(. == null)')" = "true" ]; then
  pass "R1: raising risk to core and level to evolution needs no justification and sticks ($attrs), and records no reason ($reasons) — a raise is the operator knowing something the measurement does not"
else
  fail_ "R1" "rc=$rc; attributes=$attrs; reasons=$reasons"
fi
rm -rf "$T"

# ── R2: a lower with no reason available is REFUSED, and writes nothing ─────
T=$(mktemp -d); P="$T/proj"; mk_git_proj "$P" 4
write_policy "$P" '{"schemaVersion":1,"risk_surfaces":["src/auth/**"]}'
grow "$P/src/auth/login.ts" 3
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "token check is wrong" --risk feature-local --confirm >/dev/null 2>&1
rc=$?
created=n; [ -e "$P/.claude/delta-state.json" ] && created=y
if [ "$rc" -eq 5 ] && [ "$created" = n ]; then
  pass "R2: lowering risk from the derived core with no reason available is refused (rc $rc) and nothing is opened (state file created=$created) — a blank reason is indistinguishable from a raise nobody noticed"
else
  fail_ "R2" "rc=$rc (expect 5); state file created=$created (expect n)"
fi
rm -rf "$T"

# ── R3: a lower WITH a reason is recorded on the delta's own row ────────────
T=$(mktemp -d); P="$T/proj"; mk_git_proj "$P" 4
write_policy "$P" '{"schemaVersion":1,"risk_surfaces":["src/auth/**"]}'
grow "$P/src/auth/login.ts" 3
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "token check is wrong" \
  --risk feature-local --reason "only the log message changed" --confirm >/dev/null 2>&1
rc=$?
risk="$(active_json "$P" -r '.active_delta.attributes.risk')"
reason="$(active_json "$P" -r '.active_delta.attribute_reasons.risk')"
gates="$(active_json "$P" -c '.active_delta.gates_required')"
has_review=y; printf '%s' "$gates" | grep -qF 'brief_review' || has_review=n
if [ "$rc" -eq 0 ] && [ "$risk" = "feature-local" ] \
   && [ "$reason" = "only the log message changed" ] && [ "$has_review" = n ]; then
  pass "R3: the same lower WITH --reason is accepted, the reason is recorded on the delta's own row, and the gate the raise would have added is correspondingly absent (gates=$gates)"
else
  fail_ "R3" "rc=$rc; risk=$risk (expect feature-local); recorded reason='$reason'; brief_review present=$has_review (expect n); gates=$gates"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== G — gates_required materialised at open from §5.2 ==="
# ════════════════════════════════════════════════════════════════════════════

# ── G1: each class yields its §5.2 base row, exactly and in order ───────────
T=$(mktemp -d)
g1_ok=y; g1_detail=""
_g1() {
  local class="$1" want="$2" P got
  P="$T/$class"; mk_proj "$P" 4
  delta_run "$REPO_ROOT/scripts" "$P" --open --describe "something to do" --class "$class" --confirm >/dev/null 2>&1
  got="$(active_json "$P" -c '.active_delta.gates_required')"
  [ "$got" = "$want" ] || { g1_ok=n; g1_detail="$g1_detail [$class want=$want got=$got]"; }
}
_g1 feature        '["brief","brief_review","ledger_row","build_loop","close_review","changelog"]'
_g1 fix            '["ledger_row","repro_test_red_first","close_review","changelog"]'
_g1 hotfix         '["ledger_row","audit_row_at_open","retro_review","changelog"]'
_g1 security-patch '["ledger_row","repro_test_red_first","dependency_scan","sbom_refresh","flagged_release_note","close_review","changelog"]'
if [ "$g1_ok" = y ]; then
  pass "G1: each of the four classes materialises its §5.2 base row exactly, in the table's reading order (no sorting — a sorted row is the same set and a worse checklist)"
else
  fail_ "G1" "mismatches:$g1_detail"
fi
rm -rf "$T"

# ── G2: risk: core adds brief_review  [KILLS m4] ────────────────────────────
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "the export is broken" --class fix --risk core --confirm >/dev/null 2>&1
gates="$(active_json "$P" -c '.active_delta.gates_required')"
if [ "$gates" = '["ledger_row","repro_test_red_first","close_review","changelog","brief_review"]' ]; then
  pass "G2: risk: core appends brief_review to the fix row from attribute_toggles.risk_core ($gates)"
else
  fail_ "G2" "gates=$gates (expect the fix row plus brief_review)"
fi
rm -rf "$T"

# ── G3: level: evolution adds brief ─────────────────────────────────────────
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "the export is broken" --class fix --level evolution --confirm >/dev/null 2>&1
gates="$(active_json "$P" -c '.active_delta.gates_required')"
if [ "$gates" = '["ledger_row","repro_test_red_first","close_review","changelog","brief"]' ]; then
  pass "G3: level: evolution appends brief to the fix row from attribute_toggles.level_evolution ($gates)"
else
  fail_ "G3" "gates=$gates (expect the fix row plus brief)"
fi
rm -rf "$T"

# ── G4: the toggles are READ FROM POLICY, not compiled in ───────────────────
# A project that retunes attribute_toggles gets ITS gate. This is the pin that
# separates "materialised from policy" from "materialised from a table that
# happens to agree with policy today".
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
write_policy "$P" '{"schemaVersion":1,"attribute_toggles":{"risk_core":["second_reviewer"],"level_evolution":["brief"]}}'
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "the export is broken" --class fix --risk core --confirm >/dev/null 2>&1
gates="$(active_json "$P" -c '.active_delta.gates_required')"
if [ "$gates" = '["ledger_row","repro_test_red_first","close_review","changelog","second_reviewer"]' ]; then
  pass "G4: a project that retunes attribute_toggles.risk_core gets ITS gate (second_reviewer) and not the framework's brief_review ($gates)"
else
  fail_ "G4" "gates=$gates (expect the fix row plus second_reviewer)"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== V — the validate.sh assertion: REPORT-ONLY, pinned on the exit code ==="
# ════════════════════════════════════════════════════════════════════════════

# ── V1: the report fires and the exit code does not move  [KILLS m5] ────────
# BOTH DIRECTIONS. The report must appear (or the arm is dead), and the exit
# code must be IDENTICAL to the same tree without the inconsistency (or the arm
# is a blocking gate wearing a warning's label — CLAUDE.md's `[WARN]` trap).
T=$(mktemp -d)
Pn="$T/none"; mk_validate_proj "$Pn" 2
validate_run "$REPO_ROOT/scripts" "$Pn" >/dev/null 2>&1; rc_none=$?
Po="$T/open"; mk_validate_proj "$Po" 2
printf '%s\n' '{"schemaVersion":1,"active_delta":{"id":"DELTA-007","slug":"dark-mode"},"hotfix_retros":[],"cadence":{},"closed":[]}' \
  > "$Po/.claude/delta-state.json"
out_open=$(validate_run "$REPO_ROOT/scripts" "$Po"); rc_open=$?
reported=n; printf '%s' "$out_open" | grep -qF 'DELTA-007' && reported=y
if [ "$reported" = y ] && [ "$rc_open" -eq "$rc_none" ]; then
  pass "V1: validate.sh REPORTS an open delta at phase 2 and its exit code is unchanged by it (rc $rc_none with no delta, rc $rc_open with one) — report-only, asserted on the code and not the label"
else
  fail_ "V1" "reported=$reported (expect y); rc without delta=$rc_none, rc with delta=$rc_open (must be EQUAL)"
fi
rm -rf "$T"

# ── V2: at phase 4 the same state is consistent, so nothing is reported ─────
T=$(mktemp -d); P="$T/proj"; mk_validate_proj "$P" 4
printf '%s\n' '{"schemaVersion":1,"active_delta":{"id":"DELTA-007","slug":"dark-mode"},"hotfix_retros":[],"cadence":{},"closed":[]}' \
  > "$P/.claude/delta-state.json"
out=$(validate_run "$REPO_ROOT/scripts" "$P")
silent=y; printf '%s' "$out" | grep -qF 'DELTA-007' && silent=n
if [ "$silent" = y ]; then
  pass "V2: the identical state at phase 4 is CONSISTENT and produces no report — the arm asserts the invariant, it does not merely notice an open delta"
else
  fail_ "V2" "the arm reported an inconsistency at phase 4, where active_delta != null is exactly what the invariant permits"
fi
rm -rf "$T"

# ── V3: the lint-forced routing is real  [KILLS m6] ─────────────────────────
# validate.sh is CORE, so it may not name a module path (T1, not waivable) and
# may not join the seam allowlist (cardinality asserted at one). It therefore
# reaches the state core->core through the ONE seam — and the seam's action
# flags carry the `delta-` prefix by design, so that line IS a genuine T2 hit
# carrying the lint's reason-required inline waiver. Strip the marker and the
# lint must go rc=1: that is what proves the waiver is doing work rather than
# decorating a line the lint never saw.
T=$(mktemp -d); MT="$T/tree"; mk_scripts_tree "$MT"
control_out=$(bash "$LINTER" --root "$MT" 2>&1); control_rc=$?
_sed_inplace "$MT/scripts/validate.sh" 's|# lint-delta-boundary: allow.*$||'
mut_out=$(bash "$LINTER" --root "$MT" 2>&1); mut_rc=$?
waivers="$(grep -c 'lint-delta-boundary: allow' "$REPO_ROOT/scripts/validate.sh" || true)"
t1_clean=y; printf '%s' "$control_out" | grep -q 'FAIL	T1' && t1_clean=n
if [ "$control_rc" -eq 0 ] && [ "$mut_rc" -eq 1 ] && [ "$waivers" = "1" ] && [ "$t1_clean" = y ] \
   && printf '%s' "$mut_out" | grep -q 'T2'; then
  pass "V3: validate.sh carries EXACTLY ONE inline T2 waiver ($waivers) for its seam invocation, names no module path (T1 clean), and stripping the marker reds the boundary lint (rc $control_rc -> $mut_rc)"
else
  fail_ "V3" "control rc=$control_rc (expect 0); mutant rc=$mut_rc (expect 1); waiver rows in validate.sh=$waivers (expect 1); T1 clean=$t1_clean"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== T — confirm, do not quiz (§4.3) ==="
# ════════════════════════════════════════════════════════════════════════════

# ── T1: the transcript's SHAPE, with provenance on every line ──────────────
# Asserted as SHAPE and not prose: the wording is the design's and may be
# tuned, but §4.3's structural claim — four lines, each naming where its value
# came from, and ONE question — is what must not silently erode.
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
out=$(delta_run "$REPO_ROOT/scripts" "$P" --open --describe "the CSV export crashes on unicode" --confirm)
said=n;  printf '%s\n' "$out" | grep -qE '^You said: "the CSV export crashes on unicode"$' && said=y
onequ=n; printf '%s\n' "$out" | grep -qF '[1] Keep all four' && onequ=y
prov=0
for label in Class Severity Risk Level; do
  printf '%s\n' "$out" | grep -qE "^  $label: +[^ ]+ +\(.+" && prov=$((prov + 1))
done
if [ "$said" = y ] && [ "$onequ" = y ] && [ "$prov" -eq 4 ]; then
  pass "T1: the open transcript echoes the operator's own words, prints all four attributes with a provenance parenthetical on EVERY line ($prov/4), and asks exactly one question"
else
  fail_ "T1" "echoes-input=$said; one-question footer=$onequ; lines carrying provenance=$prov/4; transcript:\n$out"
fi
rm -rf "$T"

# ── T2: nobody to confirm => REFUSE, never auto-accept ─────────────────────
# The repo's hard-N policy (helpers-core.sh::prompt_yes_no, after the cycle-7
# PR #87 unattended-install incident): a side-effectful action must never
# auto-proceed just because the operator was absent.
T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
out=$(delta_run "$REPO_ROOT/scripts" "$P" --open --describe "add dark mode"); rc=$?
created=n; [ -e "$P/.claude/delta-state.json" ] && created=y
shown=n; printf '%s' "$out" | grep -qF '[1] Keep all four' && shown=y
if [ "$rc" -eq 2 ] && [ "$created" = n ] && [ "$shown" = y ]; then
  pass "T2: a scripted run with no terminal and no --confirm still SHOWS the proposal, then refuses (rc $rc) and opens nothing — confirmation is never assumed from silence"
else
  fail_ "T2" "rc=$rc (expect 2); state file created=$created (expect n); transcript shown=$shown (expect y)"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== S — --status ==="
# ════════════════════════════════════════════════════════════════════════════

T=$(mktemp -d); P="$T/proj"; mk_proj "$P" 4
out_empty=$(delta_run "$REPO_ROOT/scripts" "$P" --status); rc_empty=$?
created=n; [ -e "$P/.claude/delta-state.json" ] && created=y
delta_run "$REPO_ROOT/scripts" "$P" --open --describe "the CSV export crashes on unicode" --confirm >/dev/null 2>&1
out_open=$(delta_run "$REPO_ROOT/scripts" "$P" --status); rc_open=$?
names=n; printf '%s' "$out_open" | grep -qF 'DELTA-001' && names=y
gates=n; printf '%s' "$out_open" | grep -qF 'repro_test_red_first' && gates=y
if [ "$rc_empty" -eq 0 ] && [ "$created" = n ] && [ "$rc_open" -eq 0 ] && [ "$names" = y ] && [ "$gates" = y ]; then
  pass "S1: --status reports rc 0 both with no delta (and creates nothing) and with one open, naming the delta and what it still owes"
else
  fail_ "S1" "empty rc=$rc_empty, created=$created (expect n); open rc=$rc_open, names delta=$names, lists outstanding gates=$gates"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== B — the boundary holds (D1), cited not re-implemented ==="
# ════════════════════════════════════════════════════════════════════════════

lint_out=$(bash "$LINTER" --list 2>&1); lint_rc=$?
seam_rows="$(printf '%s\n' "$lint_out" | grep -c 'INFO	seam' || true)"
in_manifest=y
grep -q '"scripts/delta.sh"' "$LINTER" || in_manifest=n
grep -q '"scripts/lib/delta-classify.sh"' "$LINTER" || in_manifest=n
if [ "$lint_rc" -eq 0 ] && [ "$seam_rows" = "1" ] && [ "$in_manifest" = y ]; then
  pass "B1: the boundary lint is clean on the real tree (rc $lint_rc) with the seam allowlist still at cardinality one, and both WP3 module files are in the DELTA manifest — the predicate itself is scripts/lint-delta-boundary.sh's and is mutation-pinned by its own suite"
else
  fail_ "B1" "lint rc=$lint_rc (expect 0); seam rows=$seam_rows (expect 1); WP3 files in manifest=$in_manifest"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== M — mutation proofs (each mutant is BUILT and RUN here) ==="
# ════════════════════════════════════════════════════════════════════════════

# ── m1: neuter the ERA refusal -> an open at phase 2 SUCCEEDS -> E1 RED ────
# The design's own mutation (§11-WP3), and §10.1's instruction is explicit:
# assert the EXIT CODE, not the printed label.
T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"
_sed_inplace "$MT/scripts/delta.sh" '/# DELTA-OPEN-ERA-GUARD$/s@.*@  if false; then@'
rep="$(_mutation_report "$REPO_ROOT/scripts/delta.sh" "$MT/scripts/delta.sh" 'DELTA-OPEN-ERA-GUARD$')"
sites="${rep%%|*}"; rest="${rep#*|}"; changed="${rest%%|*}"; nlines="${rest##*|}"
P="$T/proj"; mk_proj "$P" 2
delta_run "$MT/scripts" "$P" --open --describe "the CSV export crashes on unicode" --confirm >/dev/null 2>&1
mut_rc=$?
opened=n; [ -e "$P/.claude/delta-state.json" ] && opened=y
if [ "$sites" = "1" ] && [ "$changed" = y ] && [ "$nlines" -eq 2 ] && [ "$mut_rc" -eq 0 ] && [ "$opened" = y ]; then
  pass "m1: with the era guard neutered, --open at phase 2 SUCCEEDS (rc $mut_rc, state written) instead of rc 3 — E1 goes RED on the EXIT CODE (marker sites=$sites, one line changed=$nlines/2)"
else
  fail_ "m1" "marker sites=$sites (expect 1); mutation applied=$changed (expect y); diff lines=$nlines (expect 2); mutant rc=$mut_rc (expect 0); state written=$opened (expect y)"
fi
rm -rf "$T"

# ── m2: neuter the SECOND-ACTIVATION refusal -> double-open succeeds -> A1 RED
# FRESH FIXTURE AT PHASE 4 on purpose: at any lower phase the era guard refuses
# first, this guard never executes, and the mutant would look pinned when it is
# not. That masking is the failure WP2's per-atom sweep found twice.
T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"
_sed_inplace "$MT/scripts/delta.sh" '/# DELTA-OPEN-ACTIVE-GUARD$/s@.*@  if false; then@'
rep="$(_mutation_report "$REPO_ROOT/scripts/delta.sh" "$MT/scripts/delta.sh" 'DELTA-OPEN-ACTIVE-GUARD$')"
sites="${rep%%|*}"; rest="${rep#*|}"; changed="${rest%%|*}"; nlines="${rest##*|}"
P="$T/proj"; mk_proj "$P" 4
delta_run "$MT/scripts" "$P" --open --describe "the CSV export crashes on unicode" --confirm >/dev/null 2>&1
before="$(_md5file "$P/.claude/delta-state.json")"
delta_run "$MT/scripts" "$P" --open --describe "add dark mode" --confirm >/dev/null 2>&1
mut_rc=$?
after="$(_md5file "$P/.claude/delta-state.json")"
second_class="$(active_json "$P" -r '.active_delta.class')"
if [ "$sites" = "1" ] && [ "$changed" = y ] && [ "$nlines" -eq 2 ] \
   && [ "$mut_rc" -eq 0 ] && [ "$before" != "$after" ] && [ "$second_class" = "feature" ]; then
  pass "m2: with the second-activation guard neutered, a second --open SUCCEEDS (rc $mut_rc) and OVERWRITES the open delta (bytes moved; class now $second_class) — A1 goes RED, and this is exactly the loss WP2 deferred to WP3 (marker sites=$sites, one line changed=$nlines/2)"
else
  fail_ "m2" "marker sites=$sites (expect 1); mutation applied=$changed (expect y); diff lines=$nlines (expect 2); mutant rc=$mut_rc (expect 0); bytes before=$before after=$after (must DIFFER); overwritten class=$second_class (expect feature)"
fi
rm -rf "$T"

# ── m3: hardcode the small threshold -> the policy-retune test goes RED ────
T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"
_sed_inplace "$MT/scripts/lib/delta-classify.sh" '/# DELTA-CLASSIFY-LEVEL-SMALL$/s@.*@  small=50@'
rep="$(_mutation_report "$REPO_ROOT/scripts/lib/delta-classify.sh" "$MT/scripts/lib/delta-classify.sh" 'DELTA-CLASSIFY-LEVEL-SMALL$')"
sites="${rep%%|*}"; rest="${rep#*|}"; changed="${rest%%|*}"; nlines="${rest##*|}"
P="$T/proj"; mk_git_proj "$P" 4
write_policy "$P" '{"schemaVersion":1,"size_thresholds":{"small":5}}'
grow "$P/src/ui/theme.ts" 10
delta_run "$MT/scripts" "$P" --open --describe "the theme toggle is wrong" --confirm >/dev/null 2>&1
mut_level="$(active_json "$P" -r '.active_delta.attributes.level')"
if [ "$sites" = "1" ] && [ "$changed" = y ] && [ "$nlines" -eq 2 ] && [ "$mut_level" = "small" ]; then
  pass "m3: with the small threshold hardcoded to the framework's 50, a project that retuned it to 5 gets level=$mut_level for a 10-line diff instead of significant — D3 goes RED, and note the failure mode: no error, no warning, just a quietly wrong bracket (marker sites=$sites, one line changed=$nlines/2)"
else
  fail_ "m3" "marker sites=$sites (expect 1); mutation applied=$changed (expect y); diff lines=$nlines (expect 2); mutant level=$mut_level (expect small, i.e. the retune ignored)"
fi
rm -rf "$T"

# ── m4: drop the attribute_toggle read -> risk: core stops adding the gate ──
T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"
_sed_inplace "$MT/scripts/lib/delta-classify.sh" '/# DELTA-CLASSIFY-TOGGLE-RISKCORE$/s@.*@  toggle_core="[]"@'
rep="$(_mutation_report "$REPO_ROOT/scripts/lib/delta-classify.sh" "$MT/scripts/lib/delta-classify.sh" 'DELTA-CLASSIFY-TOGGLE-RISKCORE$')"
sites="${rep%%|*}"; rest="${rep#*|}"; changed="${rest%%|*}"; nlines="${rest##*|}"
P="$T/proj"; mk_proj "$P" 4
delta_run "$MT/scripts" "$P" --open --describe "the export is broken" --class fix --risk core --confirm >/dev/null 2>&1
mut_gates="$(active_json "$P" -c '.active_delta.gates_required')"
# EXACT equality, not "does not contain brief_review": a run that produced no
# state at all would satisfy a negative assertion and credit the RED to the
# neutered toggle when the delta had in fact never opened.
lost=n
[ "$mut_gates" = '["ledger_row","repro_test_red_first","close_review","changelog"]' ] && lost=y
if [ "$sites" = "1" ] && [ "$changed" = y ] && [ "$nlines" -eq 2 ] && [ "$lost" = y ]; then
  pass "m4: with the risk_core toggle read dropped, a delta confirmed at risk: core materialises WITHOUT brief_review ($mut_gates) — G2 goes RED, and the delta would have closed with the pre-build adversarial review silently never demanded (marker sites=$sites, one line changed=$nlines/2)"
else
  fail_ "m4" "marker sites=$sites (expect 1); mutation applied=$changed (expect y); diff lines=$nlines (expect 2); mutant gates=$mut_gates (must be the bare fix row, i.e. brief_review dropped AND the delta still opened)"
fi
rm -rf "$T"

# ── m5: make the validate.sh arm BLOCKING -> V1's exit-code pin goes RED ───
# THE `[WARN]` TRAP, IN BOTH DIRECTIONS. One character of intent — `warn` for
# `fail` — changes nothing about the printed line's meaning and everything about
# the script's exit status. This is the mutation that proves V1 is asserting the
# code and not the banner.
T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"
_sed_inplace "$MT/scripts/validate.sh" '/# DELTA-ERA-REPORT-ONLY$/s@warn @fail @'
rep="$(_mutation_report "$REPO_ROOT/scripts/validate.sh" "$MT/scripts/validate.sh" 'DELTA-ERA-REPORT-ONLY$')"
sites="${rep%%|*}"; rest="${rep#*|}"; changed="${rest%%|*}"; nlines="${rest##*|}"
Pn="$T/none"; mk_validate_proj "$Pn" 2
validate_run "$MT/scripts" "$Pn" >/dev/null 2>&1; mut_none=$?
Po="$T/open"; mk_validate_proj "$Po" 2
printf '%s\n' '{"schemaVersion":1,"active_delta":{"id":"DELTA-007","slug":"dark-mode"},"hotfix_retros":[],"cadence":{},"closed":[]}' \
  > "$Po/.claude/delta-state.json"
mut_out=$(validate_run "$MT/scripts" "$Po"); mut_open=$?
still_reported=n; printf '%s' "$mut_out" | grep -qF 'DELTA-007' && still_reported=y
if [ "$sites" = "1" ] && [ "$changed" = y ] && [ "$nlines" -eq 2 ] \
   && [ "$mut_open" -ne "$mut_none" ] && [ "$still_reported" = y ]; then
  pass "m5: swapping the arm's warn for fail moves validate.sh's exit code (rc $mut_none -> $mut_open) while the PRINTED LINE is unchanged (still reported=$still_reported) — V1 goes RED, and this is the [WARN] trap in one line (marker sites=$sites, one line changed=$nlines/2)"
else
  fail_ "m5" "marker sites=$sites (expect 1); mutation applied=$changed (expect y); diff lines=$nlines (expect 2); mutant rc without delta=$mut_none, with delta=$mut_open (must DIFFER); line still printed=$still_reported (expect y — the point is that the OUTPUT does not move)"
fi
rm -rf "$T"

# ── m6: strip the T2 waiver -> the boundary lint reds -> V3 RED ────────────
# The lint-forced-routing pin, mutated. Covered inside V3 itself (control vs
# stripped), so this row asserts the OTHER half: that the waiver's absence is
# what reds it, and not the seam invocation merely existing.
T=$(mktemp -d); MT="$T/tree"; mk_scripts_tree "$MT"
_sed_inplace "$MT/scripts/validate.sh" '/# DELTA-ERA-REPORT-ONLY$/s@.*@  return 0@'
after_arm_rc=0; bash "$LINTER" --root "$MT" >/dev/null 2>&1 || after_arm_rc=$?
MT2="$T/tree2"; mk_scripts_tree "$MT2"
_sed_inplace "$MT2/scripts/validate.sh" 's|lint-delta-boundary: allow|lint-delta-boundary: allowed because|'
typo_rc=0; bash "$LINTER" --root "$MT2" >/dev/null 2>&1 || typo_rc=$?
if [ "$after_arm_rc" -eq 0 ] && [ "$typo_rc" -eq 1 ]; then
  pass "m6: the waiver is what waives — a NEAR-MISS spelling ('allowed because …') is not the marker and reds the lint (rc $typo_rc), while removing the invocation entirely leaves it clean (rc $after_arm_rc). The exemption fails CLOSED, so a typo cannot silently waive a real edge"
else
  fail_ "m6" "lint rc with the arm removed=$after_arm_rc (expect 0); lint rc with a near-miss waiver spelling=$typo_rc (expect 1)"
fi
rm -rf "$T"

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
