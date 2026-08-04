#!/usr/bin/env bash
# tests/test-delta-wp6-cadence.sh — Delta Track WP6.
#
# SPEC: docs/designs/2026-08-02-delta-track-v1.md §8.3 (the CALENDAR-based
# re-fire trigger — the threshold table, the three notes, the author-proposed
# `exit 2` design addition, and the two enforcement points), §0.3-C1 (the
# orphan is INVOCATION-only: the script already ships, so this WP wires callers
# and must NOT re-ship it), §0.3-C2 (the script/guide split), §7.2 (`cadence`
# policy keys and per-key fallback), §11-WP6, §13-R14 (the filename-derived
# evidence residual), §14-V13 (the executed run this suite refuses to let come
# back). Closes BL-213.
#
# (No `# BL-NNN-…` marker anywhere in the delta track on purpose: no backlog
# entry exists for this build and minting one would red
# scripts/lint-bl-markers.sh, whose first pass resolves every marker to a real
# `## BL-NNN:` entry. The design-doc path above is the citation, per the WP1,
# WP2, WP3, WP4 and WP5 precedent. BL-213 is named in prose here because it is
# the BUG this WP closes, not a code marker.)
#
# ═════════════════════════════════════════════════════════════════════════════
# THE ONE PROPERTY THIS SUITE EXISTS FOR
#
# "Unmeasurable" and "measured and fine" must never be the same answer.
#
# §14-V13 recorded the shipped defect by execution: every verdict in
# scripts/check-maintenance.sh sat inside `if [ "$last_epoch" -gt 0 ]`, and
# `last_epoch` came from a `date … || date … || echo "0"` tail. A date neither
# parser accepted resolved to 0, the guard was false, and THE WHOLE ARM WAS
# SKIPPED IN SILENCE — the script then printed "All maintenance cadences
# current." and exited 0 over evidence it had never read. That is fail-OPEN,
# and WP7's release cut is the consumer that would have been fooled by it.
#
# E3/E5/E6 are that fixture, now answering 2; m2 is the mutant that proves E3
# can see the counter's removal. m2 is the pin that matters most in this file.
#
# ═════════════════════════════════════════════════════════════════════════════
# EXIT CODES, NEVER LABELS
#
# Every cadence verdict below is asserted on a process EXIT CODE. None is
# asserted on a printed `[OK]`/`[WARN]` banner or on the closing sentence —
# CLAUDE.md's `[WARN]` trap is exactly that the label and the exit predicate
# can disagree, and the whole BL-213 defect is a closing sentence that lied.
# Where a mutant's printed text is quoted in a pass narrative it is MEASURED
# for the reader, never part of the predicate.
#
# The contract under test (scripts/check-maintenance.sh, for WP7):
#     0  every applicable cadence was MEASURED and is current
#     1  one or more cadences are OVERDUE
#     2  one or more could NOT BE MEASURED and none is overdue
#   WP7's cut-release.sh refuses on 1 AND on 2.
#
# ═════════════════════════════════════════════════════════════════════════════
# WHAT THIS SUITE PINS, AND WHICH MUTANT EACH ROW KILLS
#
#   P — POLICY ROUTING (§8.3 note 3, §7.2)
#     P1  absent policy -> the framework defaults still measure (15d -> 1,
#         13d -> 0). A project that never opened a post-release change still
#         gets a working checker                                     KILLS m1
#     P2  a project that retunes routine_review_days 14 -> 30 moves the
#         boundary: the SAME 15-day fixture goes 1 -> 0               KILLS m3
#     P3  deep_security_days is read too, and independently
#     P4  a policy file WITHOUT the cadence key falls back per-key
#     P5  the boundary lint stays rc 0 and the seam allowlist stays at ONE —
#         the routing is composed, not allowlisted
#
#   E — THE EXIT CONTRACT (§8.3 note 1 — BL-213)
#     E1  everything present and fresh -> 0
#     E2  CHANGELOG 15 days old -> 1
#     E3  a scan artefact dated 2026-13-45 -> 2, NOT the silent 0    KILLS m2
#     E4  docs/test-results/ present but holding no artefact -> 2
#         (the policy-expected-but-missing signal)
#     E5  CHANGELOG present but with no git history -> 2
#     E6  §14-V13's fixture verbatim -> 2
#     E7  overdue AND unmeasurable -> 1 (overdue dominates; 2 is the
#         zero-overdue code by design)
#     E8  a project with NO signal surface at all -> 0, and the residual is
#         stated rather than hidden: this checker measures a CADENCE, it does
#         not audit whether a maintenance practice exists
#     E9  sbom.json is the second routine arm and reads the same policy key
#     E10 the deep cadence fires at its own threshold (96 -> 1, 94 -> 0)
#
#   D — THE DATE LAYER (the no-default contract)
#     D1  a bare `YYYY-MM-DD` normalises to MIDNIGHT UTC before either parser
#         sees it — BSD's `date -j -f` otherwise fills unspecified fields FROM
#         NOW, so the pre-WP6 spelling answered a different number every call
#     D2  `2026-13-45` -> rc 1 and ZERO BYTES of output (no `|| echo 0` tail)
#     D3  empty / `banana` / an offset-bearing stamp -> rc 1, no output
#     D4  STRUCTURAL ABSENCE: neither the `|| echo "0"` tail nor the
#         `-gt 0` guard survives anywhere in the shipped script
#
#   H — THE SessionStart NAG ARM (§8.3's second enforcement point)
#     H1  SILENT when nothing is wrong — zero bytes on stdout AND stderr
#     H2  speaks on overdue, still rc 0
#     H3  speaks on unmeasurable, still rc 0
#     H4  FAIL-OPEN: a forced internal crash still exits 0             KILLS m4
#     H5  ZERO NETWORK: curl/wget/nc/ping shadowed in PATH are never invoked
#     H6  registered and shipped by init.sh the way its five siblings are —
#         and check-maintenance.sh is NOT re-shipped (§0.3-C1)
#     H7  DAY-ZERO SILENCE: the nag is post-launch only, so a pre-launch
#         project is byte-silent even while the checker says 2   KILLS m5
#     H8  NO EVIDENCE, NO HEADLINE: rc 1 is also `set -e`'s abort code, so a
#         checker that DIED must not be announced as an overdue — and an rc 1
#         that carries a real OVERDUE line still speaks         KILLS m6
#
#   I — IDENTIFIERS (§11-WP6's template deliverable)
#     I1  the generated identifier registry carries the DELTA- row
#
#   M — MUTATIONS (anchored, sites==1, one line changed, mode preserved,
#       fresh fixtures, both trees executed)
#     m1  revert the routine default 14 -> 35   -> the 15-day fixture passes
#     m2  remove the undetermined counter       -> the unparseable fixture
#         reports "All maintenance cadences current" at rc 0 — THE pin
#     m3  neuter the policy read                -> the retune stops moving
#     m4  neuter the hook's fail-open arm       -> a crashing checker takes
#         the session's SessionStart with it
#     m5  neuter the era gate                   -> day zero gets noisy again,
#         at rc 0 both ways, so only a byte count can see it
#     m6  neuter the evidence guard             -> a checker that merely died is
#         announced to the session as an overdue cadence
#
# LANE: registered in tests/full-project-test-suite.sh AND in the tests.yml
# `unit-shard` list. Its executed lines never name the init script — H6 reads
# that file through a SPLIT token for exactly that reason (see the comment
# there; the same idiom and the same reason are already in
# tests/test-intake-wizard-fixes.sh).
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v git >/dev/null 2>&1; then
  echo "git is required for tests/test-delta-wp6-cadence.sh" >&2
  exit 2
fi

CHECKER="$REPO_ROOT/scripts/check-maintenance.sh"
HOOK="$REPO_ROOT/scripts/session-cadence-check.sh"

# ── Dates ───────────────────────────────────────────────────────────────────
# GNU-first, BSD fallback — the house pattern, spelled here so the FIXTURES do
# not depend on the product's own parser to build the inputs that test it.

days_ago() {   # <n> -> YYYY-MM-DD, n whole days before now, UTC
  local n="$1" e
  e=$(( $(date -u +%s) - n * 86400 ))
  date -u -d "@$e" +%Y-%m-%d 2>/dev/null || date -u -r "$e" +%Y-%m-%d
}

epoch_of() {   # <YYYY-MM-DDTHH:MM:SSZ> -> epoch seconds, computed INDEPENDENTLY
  local s="$1" e
  e="$(date -u -d "$s" +%s 2>/dev/null)" || e=""
  if [ -z "$e" ]; then e="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$s" +%s 2>/dev/null)" || e=""; fi
  printf '%s\n' "$e"
}

# ── Fixtures ────────────────────────────────────────────────────────────────
# EVERY case builds its own tree and removes it. Nothing is shared, so a case
# can never inherit a surface it did not ask for — and a surface it did not ask
# for is exactly what would make a "not applicable" verdict look like a pass.

mk_proj() {    # a git repo with an identity and a .claude dir, and NOTHING else
  local d="$1"
  mkdir -p "$d/.claude"
  # Phase 4 by default: the cadence surfaces are post-launch by construction,
  # and H7 is the row that sets it lower on purpose.
  (
    cd "$d" && unset GITHUB_BASE_REF
    git init -q .
    git config user.email "wp6@example.invalid"
    git config user.name "WP6 Fixture"
    git config commit.gpgsign false
  ) >/dev/null 2>&1
  printf '{"track":"light","deployment":"personal","poc_mode":null,"current_phase":4,"phases":{}}\n' \
    > "$d/.claude/phase-state.json"
}

# commit_dated <dir> <file> <days-ago>
#   Commit <file> with a fixed +0000 author date <days-ago> days back.
#
#   THE VERIFICATION IS THE LIVE HALF; THE VARYING CONTENT IS BELT AND BRACES.
#   Several rows below re-date a file the baseline fixture already committed,
#   and with identical bytes `git commit` is a SILENT no-op: the tip stays at
#   the old date and a threshold test passes without ever crossing the
#   threshold. That is what happened on the first draft of this suite — eight
#   rows agreed the checker was fine because none of their 15-day fixtures had
#   taken. So the call VERIFIES that the tree records the date it asked for and
#   counts a loud failure if it does not.
#
#   Measured, not assumed, and the review re-measured it: removing FIXTURE_SEQ
#   ALONE does not reproduce the no-op, because the days-back text in the line
#   below still varies the bytes. Forcing the content genuinely constant makes
#   the guard fire ten times and the suite go RED. Both belong here — the seq
#   makes collisions unlikely, the guard is what would catch one anyway.
#
#   A fixture that quietly did not happen is the same silent-success class this
#   whole WP exists to close; a suite that cannot see it in its own scaffolding
#   has no business asserting it about a product.
FIXTURE_SEQ=0
commit_dated() {
  local d="$1" f="$2" n="$3" stamp want got
  FIXTURE_SEQ=$((FIXTURE_SEQ + 1))
  want="$(days_ago "$n")"
  stamp="${want}T12:00:00+0000"
  printf 'fixture content for %s - revision %s, dated %s days back\n' "$f" "$FIXTURE_SEQ" "$n" > "$d/$f"
  (
    cd "$d" && unset GITHUB_BASE_REF
    GIT_AUTHOR_DATE="$stamp" GIT_COMMITTER_DATE="$stamp" git add "$f"
    GIT_AUTHOR_DATE="$stamp" GIT_COMMITTER_DATE="$stamp" git commit -q -m "chore: $f r$FIXTURE_SEQ"
  ) >/dev/null 2>&1
  got="$( cd "$d" && git log -1 --format='%ai' -- "$f" 2>/dev/null | awk '{ print $1 }' )"
  if [ "$got" != "$want" ]; then
    echo "  [FIXTURE] commit_dated $f wanted $want but the tree records '$got' — the fixture did not take" >&2
    FAILED=$((FAILED + 1))
  fi
  return 0
}

add_scan() {   # <dir> <filename> — one artefact under the evidence surface
  local d="$1" n="$2"
  mkdir -p "$d/docs/test-results"
  printf 'scan artefact\n' > "$d/docs/test-results/$n"
}

mk_current_proj() {   # every surface present, every one fresh -> the rc 0 baseline
  local d="$1"
  mk_proj "$d"
  commit_dated "$d" CHANGELOG.md 2
  commit_dated "$d" sbom.json 2
  add_scan "$d" "$(days_ago 10)_semgrep_pass.txt"
}

write_policy() { printf '%s\n' "$2" > "$1/.claude/delta-policy.json"; }

mk_scripts_tree() { mkdir -p "$1"; cp -R "$REPO_ROOT/scripts" "$1/scripts"; }

# strip_delta_module <tree> — remove the post-1.0 module from a copied scripts
#   tree, so the seam refuses every `--delta-*` action.
#
#   THIS IS THE SHIPPED DOWNSTREAM SHAPE, NOT AN EXOTIC ONE: init.sh copies the
#   checker and the seam but ships no delta libs at all today, so in every
#   generated project the seam answers "the delta module is not installed" and
#   the checker's OWN default constants are the live values. With the module
#   present the seam answers from §7.2's defaults instead — the same 14 and 95,
#   from a different file. Two sources for one number is a drift waiting to
#   happen, so P1 measures BOTH and requires them to agree.
strip_delta_module() {
  rm -f "$1/scripts/lib/delta-state.sh" "$1/scripts/lib/delta-policy.sh" \
        "$1/scripts/lib/delta-classify.sh" "$1/scripts/lib/delta-cadence.sh" 2>/dev/null
  return 0
}

# ── Runners ─────────────────────────────────────────────────────────────────

CHK_RC=0
CHK_OUT=""
run_check() {   # <scripts-dir> <project-dir> — sets CHK_RC / CHK_OUT
  local sd="$1" p="$2"
  CHK_RC=0
  CHK_OUT="$( cd "$p" && unset GITHUB_BASE_REF; bash "$sd/check-maintenance.sh" </dev/null 2>&1 )" || CHK_RC=$?
  return 0
}

HOOK_RC=0
HOOK_OUT=""
HOOK_ERR=""
run_hook() {   # <scripts-dir> <project-dir> [err-file]
  local sd="$1" p="$2" errf="${3:-}"
  local tmperr; tmperr="${errf:-$(mktemp)}"
  HOOK_RC=0
  HOOK_OUT="$( cd "$p" && unset GITHUB_BASE_REF; CLAUDE_PROJECT_DIR="$p" bash "$sd/session-cadence-check.sh" </dev/null 2>"$tmperr" )" || HOOK_RC=$?
  HOOK_ERR="$(cat "$tmperr" 2>/dev/null || true)"
  [ -n "$errf" ] || rm -f "$tmperr" 2>/dev/null || true
  return 0
}

# ── Mutation harness (inherited from the WP2/WP3/WP4/WP5 suites) ────────────

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

echo "== tests/test-delta-wp6-cadence.sh =="
echo ""

# The suite is meaningless if the two product files are not there at all — say
# so once, loudly, rather than letting thirty rows report the same absence.
if [ ! -f "$CHECKER" ]; then
  echo "  [FAIL] scripts/check-maintenance.sh is missing — WP6 wires it, it must exist" >&2
  exit 1
fi

# ════════════════════════════════════════════════════════════════════════════
echo "=== P — the thresholds are POLICY, read through the ONE seam (§8.3 note 3) ==="
# ════════════════════════════════════════════════════════════════════════════

# ── P1: absent policy -> the framework defaults still MEASURE ───────────────
# Asserted in BOTH directions from the same default. One direction alone would
# pass for a checker that always answers 1 (or always 0).
T=$(mktemp -d)
mk_current_proj "$T/over"; commit_dated "$T/over" CHANGELOG.md 15
run_check "$REPO_ROOT/scripts" "$T/over"; over_rc=$CHK_RC
mk_current_proj "$T/under"; commit_dated "$T/under" CHANGELOG.md 13
run_check "$REPO_ROOT/scripts" "$T/under"; under_rc=$CHK_RC
had_policy=n
[ -f "$T/over/.claude/delta-policy.json" ] && had_policy=y
# And again with the module GONE — the shape init.sh actually ships today, where
# the seam refuses and the checker's own constants are the live values. Both
# sources of the same default must give the same answer, or the drift between
# them is silent.
NOMOD="$T/nomod"; mk_scripts_tree "$NOMOD"; strip_delta_module "$NOMOD"
run_check "$NOMOD/scripts" "$T/over"; nm_over_rc=$CHK_RC
run_check "$NOMOD/scripts" "$T/under"; nm_under_rc=$CHK_RC
if [ "$over_rc" -eq 1 ] && [ "$under_rc" -eq 0 ] && [ "$had_policy" = n ] \
   && [ "$nm_over_rc" -eq 1 ] && [ "$nm_under_rc" -eq 0 ]; then
  pass "P1: with NO policy file anywhere (had_policy=$had_policy) the 14-day default still measures — 15 days overdue (rc $over_rc), 13 days current (rc $under_rc) — and it measures identically with the whole post-1.0 module deleted (rc $nm_over_rc / $nm_under_rc), which is the shape init.sh ships today. The checker does not require the module, and the two places that hold the same default agree"
else
  fail_ "P1" "module present: 15-day rc=$over_rc (expect 1), 13-day rc=$under_rc (expect 0); policy file present=$had_policy (expect n); module DELETED: 15-day rc=$nm_over_rc (expect 1), 13-day rc=$nm_under_rc (expect 0 — a disagreement here means the seam's defaults and the script's constants have drifted)"
fi
rm -rf "$T"

# ── P2: a retune MOVES the boundary — this is the policy read, proved ───────
# The SAME 15-day fixture, the only difference being the project's own file.
T=$(mktemp -d)
mk_current_proj "$T/p"; commit_dated "$T/p" CHANGELOG.md 15
run_check "$REPO_ROOT/scripts" "$T/p"; before_rc=$CHK_RC
write_policy "$T/p" '{"schemaVersion":1,"cadence":{"routine_review_days":30,"deep_security_days":95}}'
run_check "$REPO_ROOT/scripts" "$T/p"; after_rc=$CHK_RC
if [ "$before_rc" -eq 1 ] && [ "$after_rc" -eq 0 ]; then
  pass "P2: one fixture, one file changed — a project that retunes routine_review_days 14 -> 30 turns the same 15-day-old CHANGELOG from overdue (rc $before_rc) into current (rc $after_rc). The threshold is the project's, not the script's"
else
  fail_ "P2" "rc before the retune=$before_rc (expect 1); rc after routine_review_days=30=$after_rc (expect 0)"
fi
rm -rf "$T"

# ── P3: deep_security_days is a SEPARATE key, read independently ────────────
T=$(mktemp -d)
mk_proj "$T/p"; commit_dated "$T/p" CHANGELOG.md 1; commit_dated "$T/p" sbom.json 1
add_scan "$T/p" "$(days_ago 20)_semgrep_pass.txt"
run_check "$REPO_ROOT/scripts" "$T/p"; deep_default_rc=$CHK_RC
write_policy "$T/p" '{"schemaVersion":1,"cadence":{"routine_review_days":14,"deep_security_days":10}}'
run_check "$REPO_ROOT/scripts" "$T/p"; deep_tuned_rc=$CHK_RC
if [ "$deep_default_rc" -eq 0 ] && [ "$deep_tuned_rc" -eq 1 ]; then
  pass "P3: a 20-day-old scan is current under the framework's 95 (rc $deep_default_rc) and overdue the moment the project sets deep_security_days=10 (rc $deep_tuned_rc) — the two cadence keys are read separately, and the routine arms stayed fresh throughout"
else
  fail_ "P3" "rc under the default 95=$deep_default_rc (expect 0); rc under deep_security_days=10=$deep_tuned_rc (expect 1)"
fi
rm -rf "$T"

# ── P4: PER-KEY fallback — a policy file without the cadence key ────────────
# §7.2's read-time fallback is per KEY, not per FILE. A project that seeded a
# policy for some other reason must not lose the cadence defaults.
T=$(mktemp -d)
mk_current_proj "$T/p"; commit_dated "$T/p" CHANGELOG.md 15
write_policy "$T/p" '{"schemaVersion":1,"size_thresholds":{"small":50}}'
run_check "$REPO_ROOT/scripts" "$T/p"; rc_nokey=$CHK_RC
if [ "$rc_nokey" -eq 1 ]; then
  pass "P4: a policy file that carries no cadence block at all still measures on the framework defaults (rc $rc_nokey on a 15-day fixture) — the fallback is per key, not per file"
else
  fail_ "P4" "rc=$rc_nokey (expect 1 — the 14-day default must survive a policy file that never mentions cadence)"
fi
rm -rf "$T"

# ── P5: the routing is COMPOSED, not allowlisted ───────────────────────────
# The T1 rule this WP had to design around is only worth anything if it is
# still green afterwards, with the seam's cardinality untouched.
lint_rc=0
( cd "$REPO_ROOT" && bash scripts/lint-delta-boundary.sh ) >/dev/null 2>&1 || lint_rc=$?
seam_n="$(sed -n '/^SEAM_ALLOWLIST=(/,/^)/p' "$REPO_ROOT/scripts/lint-delta-boundary.sh" | grep -c '^  "' || true)"
case "$seam_n" in ''|*[!0-9]*) seam_n=0 ;; esac
t1_hit=n
grep -n 'delta-policy\.json\|delta-policy\.sh\|delta-cadence\.sh\|delta-state\.sh' "$CHECKER" \
  | grep -v '^[0-9]*:[[:space:]]*#' >/dev/null 2>&1 && t1_hit=y
if [ "$lint_rc" -eq 0 ] && [ "$seam_n" -eq 1 ] && [ "$t1_hit" = n ]; then
  pass "P5: scripts/lint-delta-boundary.sh is still rc $lint_rc with the seam allowlist at exactly $seam_n entry, and the checker names no module path on any executed line (t1_hit=$t1_hit) — the policy read is composed through the seam, not allowlisted around the boundary"
else
  fail_ "P5" "boundary lint rc=$lint_rc (expect 0); seam allowlist entries=$seam_n (expect 1); module path on a non-comment line of the checker=$t1_hit (expect n)"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== E — the exit contract, and BL-213's fail-open repair (§8.3 note 1) ==="
# ════════════════════════════════════════════════════════════════════════════

# ── E1: the rc 0 baseline ──────────────────────────────────────────────────
T=$(mktemp -d); mk_current_proj "$T/p"
run_check "$REPO_ROOT/scripts" "$T/p"; rc1=$CHK_RC
if [ "$rc1" -eq 0 ]; then
  pass "E1: every surface present and fresh -> rc $rc1. This is the baseline every row below perturbs by exactly one thing, so a non-zero answer is attributable"
else
  fail_ "E1" "rc=$rc1 (expect 0) — the all-current baseline must be clean or every row below is unreadable:\n$CHK_OUT"
fi
rm -rf "$T"

# ── E2: overdue -> 1 ───────────────────────────────────────────────────────
T=$(mktemp -d); mk_current_proj "$T/p"; commit_dated "$T/p" CHANGELOG.md 15
run_check "$REPO_ROOT/scripts" "$T/p"; rc2=$CHK_RC
if [ "$rc2" -eq 1 ]; then
  pass "E2: a CHANGELOG.md last touched 15 days ago against a 14-day cadence -> rc $rc2 (the design's own number)"
else
  fail_ "E2" "rc=$rc2 (expect 1):\n$CHK_OUT"
fi
rm -rf "$T"

# ── E3: THE BL-213 PIN — an unparseable date -> 2, not the silent 0 ────────
# §14-V13's own fixture string. Both `date -j -f` and `date -d` reject
# 2026-13-45 on this host, which is why it was chosen: it is date-SHAPED but
# not a date, so a shape check passes it through to the real parser and the
# real parser is what must refuse it.
T=$(mktemp -d); mk_proj "$T/p"
commit_dated "$T/p" CHANGELOG.md 1; commit_dated "$T/p" sbom.json 1
add_scan "$T/p" "2026-13-45_semgrep_pass.txt"
run_check "$REPO_ROOT/scripts" "$T/p"; rc3=$CHK_RC
# MEASURED for the narrative, never asserted: the sentence the shipped script used to print.
said_current=n
printf '%s' "$CHK_OUT" | grep -qF 'All maintenance cadences current' && said_current=y
if [ "$rc3" -eq 2 ]; then
  pass "E3: the ONLY security artefact is dated 2026-13-45 — a string neither date parser accepts — and every other cadence is fresh, so the script answers rc $rc3, the code that means 'I could not measure this'. §14-V13 recorded rc 0 here (all-current sentence printed now: $said_current). Unmeasurable is no longer spelled the same as fine"
else
  fail_ "E3" "rc=$rc3 (expect 2 — this is BL-213; rc 0 is the shipped defect, rc 1 would be the fail-CLOSED collapse the design refuted):\n$CHK_OUT"
fi
rm -rf "$T"

# ── E4: a policy-expected signal that is MISSING -> 2 ──────────────────────
# The evidence surface exists — the project adopted the convention — and holds
# nothing the deep cadence can read. That is not "current".
T=$(mktemp -d); mk_proj "$T/p"
commit_dated "$T/p" CHANGELOG.md 1; commit_dated "$T/p" sbom.json 1
mkdir -p "$T/p/docs/test-results"
printf 'unrelated\n' > "$T/p/docs/test-results/README.md"
run_check "$REPO_ROOT/scripts" "$T/p"; rc4=$CHK_RC
if [ "$rc4" -eq 2 ]; then
  pass "E4: docs/test-results/ exists and holds no dependency- or security-scan artefact at all -> rc $rc4. A signal the policy expects and cannot find is unmeasurable, not satisfied"
else
  fail_ "E4" "rc=$rc4 (expect 2):\n$CHK_OUT"
fi
rm -rf "$T"

# ── E5: a signal file with no git history -> 2 ─────────────────────────────
T=$(mktemp -d); mk_proj "$T/p"
commit_dated "$T/p" sbom.json 1
add_scan "$T/p" "$(days_ago 5)_semgrep_pass.txt"
printf '# Changelog\n' > "$T/p/CHANGELOG.md"        # present, untracked, undatable
run_check "$REPO_ROOT/scripts" "$T/p"; rc5=$CHK_RC
if [ "$rc5" -eq 2 ]; then
  pass "E5: a CHANGELOG.md that is present but has no git history cannot be dated -> rc $rc5. The shipped script printed one INFO line here and still closed at rc 0"
else
  fail_ "E5" "rc=$rc5 (expect 2):\n$CHK_OUT"
fi
rm -rf "$T"

# ── E6: §14-V13's fixture, verbatim -> 2 ───────────────────────────────────
# "a git repo with an untracked CHANGELOG.md and a docs/test-results/ file
# dated 2026-13-45". The design logged rc 0. This row is the regression pin on
# the exact tree that produced the bug report.
T=$(mktemp -d); mk_proj "$T/p"
printf '# Changelog\n' > "$T/p/CHANGELOG.md"
add_scan "$T/p" "2026-13-45_semgrep_pass.txt"
run_check "$REPO_ROOT/scripts" "$T/p"; rc6=$CHK_RC
if [ "$rc6" -eq 2 ]; then
  pass "E6: §14-V13's fixture verbatim — untracked CHANGELOG.md plus a lone 2026-13-45 artefact — answers rc $rc6 where the executed design log recorded rc 0 over two cadences it had never read"
else
  fail_ "E6" "rc=$rc6 (expect 2 — this is the exact tree §14-V13 ran):\n$CHK_OUT"
fi
rm -rf "$T"

# ── E7: overdue AND unmeasurable -> 1 ──────────────────────────────────────
# §8.3 is explicit: 2 is the code for a non-zero undetermined with ZERO
# overdue. Both refuse a release cut, so the ordering costs nothing — but a
# checker that answered 2 here would hide a REAL overdue behind an unreadable
# date, which is the same disease pointing the other way.
T=$(mktemp -d); mk_proj "$T/p"
commit_dated "$T/p" CHANGELOG.md 15
commit_dated "$T/p" sbom.json 1
add_scan "$T/p" "2026-13-45_semgrep_pass.txt"
run_check "$REPO_ROOT/scripts" "$T/p"; rc7=$CHK_RC
named_both=n
printf '%s' "$CHK_OUT" | grep -qi 'could not be measured' && named_both=y
if [ "$rc7" -eq 1 ]; then
  pass "E7: a genuinely overdue cadence and an unreadable one in the same tree -> rc $rc7, because 2 is by design the ZERO-overdue code — and the unmeasurable one is still named in the report (named=$named_both) rather than lost behind the louder answer"
else
  fail_ "E7" "rc=$rc7 (expect 1):\n$CHK_OUT"
fi
rm -rf "$T"

# ── E8: no signal surface at all -> 0, and the residual is STATED ──────────
# Recorded as a row rather than left implicit: absence of an artefact is a
# legitimate project shape, so the checker says "not applicable" and does not
# invent a verdict. It measures a CADENCE; it does not audit whether a
# maintenance practice exists. If that boundary ever moves, this row moves
# with it — deliberately, not by accident.
T=$(mktemp -d); mk_proj "$T/p"
run_check "$REPO_ROOT/scripts" "$T/p"; rc8=$CHK_RC
na="$(printf '%s' "$CHK_OUT" | grep -c 'not applicable' || true)"
case "$na" in ''|*[!0-9]*) na=0 ;; esac
if [ "$rc8" -eq 0 ] && [ "$na" -eq 3 ]; then
  pass "E8: a project with no CHANGELOG.md, no sbom.json and no docs/test-results/ answers rc $rc8 and says 'not applicable' $na times — the stated residual: an absent surface is a project shape, not a failure, and this checker does not audit whether a maintenance practice exists"
else
  fail_ "E8" "rc=$rc8 (expect 0); 'not applicable' lines=$na (expect 3 — one per surface, so the silence is legible):\n$CHK_OUT"
fi
rm -rf "$T"

# ── E9: sbom.json is the second routine arm, on the same key ──────────────
T=$(mktemp -d); mk_current_proj "$T/p"; commit_dated "$T/p" sbom.json 15
run_check "$REPO_ROOT/scripts" "$T/p"; rc9=$CHK_RC
write_policy "$T/p" '{"schemaVersion":1,"cadence":{"routine_review_days":30}}'
run_check "$REPO_ROOT/scripts" "$T/p"; rc9b=$CHK_RC
if [ "$rc9" -eq 1 ] && [ "$rc9b" -eq 0 ]; then
  pass "E9: sbom.json is the routine cadence's second arm and reads the SAME policy key — 15 days is overdue (rc $rc9) and the 30-day retune clears it (rc $rc9b), with CHANGELOG fresh throughout"
else
  fail_ "E9" "sbom 15-day rc=$rc9 (expect 1); after routine_review_days=30 rc=$rc9b (expect 0)"
fi
rm -rf "$T"

# ── E10: the deep cadence fires at ITS threshold, both sides ──────────────
T=$(mktemp -d)
mk_proj "$T/a"; commit_dated "$T/a" CHANGELOG.md 1; commit_dated "$T/a" sbom.json 1
add_scan "$T/a" "$(days_ago 96)_semgrep_pass.txt"
run_check "$REPO_ROOT/scripts" "$T/a"; rc10a=$CHK_RC
mk_proj "$T/b"; commit_dated "$T/b" CHANGELOG.md 1; commit_dated "$T/b" sbom.json 1
add_scan "$T/b" "$(days_ago 94)_semgrep_pass.txt"
run_check "$REPO_ROOT/scripts" "$T/b"; rc10b=$CHK_RC
# The dependency audit is FOLDED IN (§8.3's table): one clock over the union of
# both artefact families, so a snyk artefact satisfies the same cadence.
mk_proj "$T/c"; commit_dated "$T/c" CHANGELOG.md 1; commit_dated "$T/c" sbom.json 1
add_scan "$T/c" "$(days_ago 94)_snyk_report.json"
run_check "$REPO_ROOT/scripts" "$T/c"; rc10c=$CHK_RC
if [ "$rc10a" -eq 1 ] && [ "$rc10b" -eq 0 ] && [ "$rc10c" -eq 0 ]; then
  pass "E10: the deep cadence answers overdue at 96 days (rc $rc10a) and current at 94 (rc $rc10b) against the framework's 95, and the dependency audit is FOLDED IN — a lone snyk artefact satisfies the same one clock (rc $rc10c) instead of the separate 95-day row the shipped script kept"
else
  fail_ "E10" "96-day semgrep rc=$rc10a (expect 1); 94-day semgrep rc=$rc10b (expect 0); 94-day snyk rc=$rc10c (expect 0 — the folded family)"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== D — the date layer, and the no-default contract ==="
# ════════════════════════════════════════════════════════════════════════════

# The parse helper is exercised DIRECTLY, extracted from the shipped file. It
# is the one place where "returns nothing" and "returns 0" have to be
# distinguishable, and a whole-script run cannot see the difference: both would
# read as "that arm did not fire".
T=$(mktemp -d)
sed -n '/^cadence_epoch() {$/,/^}$/p' "$CHECKER" > "$T/lib.sh"
extracted="$(grep -c . "$T/lib.sh" || true)"
case "$extracted" in ''|*[!0-9]*) extracted=0 ;; esac

_epoch_call() {   # <arg…> -> prints "<rc>|<stdout-bytes>|<stdout>"
  local out rc=0
  out="$( . "$T/lib.sh"; cadence_epoch "$@" 2>/dev/null )" || rc=$?
  printf '%s|%s|%s' "$rc" "${#out}" "$out"
}

if [ "$extracted" -lt 8 ]; then
  fail_ "D0" "could not extract cadence_epoch() from scripts/check-maintenance.sh (got $extracted non-blank lines) — the date layer must be a named function so it can be tested where a whole-script run cannot see it"
else
  # ── D1: a bare date normalises to MIDNIGHT UTC ──────────────────────────
  # BSD's `date -j -f '%Y-%m-%d'` fills unspecified fields FROM THE CURRENT
  # TIME, so without the normalisation the same bare date answers a different
  # number every call and a different number from GNU's answer. The expected
  # value is computed here from the EXPLICIT stamp, independently.
  bare="$(days_ago 5)"
  got="$(_epoch_call "$bare")"; got_rc="${got%%|*}"; got_val="${got##*|}"
  want="$(epoch_of "${bare}T00:00:00Z")"
  again="$(_epoch_call "$bare")"; again_val="${again##*|}"
  if [ "$got_rc" -eq 0 ] && [ -n "$want" ] && [ "$got_val" = "$want" ] && [ "$again_val" = "$got_val" ]; then
    pass "D1: the bare date $bare resolves to $got_val, which is exactly midnight UTC computed independently ($want), and twice in a row to the same number — the BSD 'fill the missing fields from now' nondeterminism the shipped spelling carried is gone"
  else
    fail_ "D1" "rc=$got_rc (expect 0); value=$got_val; independently-computed midnight=$want; second call=$again_val (all three must agree)"
  fi

  # ── D2: the unparseable date returns NOTHING ───────────────────────────
  bad="$(_epoch_call '2026-13-45')"; bad_rc="${bad%%|*}"; bad_rest="${bad#*|}"; bad_len="${bad_rest%%|*}"
  if [ "$bad_rc" -ne 0 ] && [ "$bad_len" -eq 0 ]; then
    pass "D2: 2026-13-45 — date-SHAPED but not a date — returns rc $bad_rc and $bad_len bytes of output. A caller that ignored the return code has nothing to misread as a date, which is exactly what the '|| echo 0' tail gave it"
  else
    fail_ "D2" "rc=$bad_rc (expect non-zero); stdout bytes=$bad_len (expect 0 — printing a 0 here IS the defect)"
  fi

  # ── D3: every other non-date is the same answer ────────────────────────
  d3_ok=y; d3_detail=""
  for cand in "" "banana" "2026-08-03T00:00:00+02:00" "20260803" "2026-8-3"; do
    r="$(_epoch_call "$cand")"; r_rc="${r%%|*}"; r_rest="${r#*|}"; r_len="${r_rest%%|*}"
    d3_detail="$d3_detail '$cand'->rc$r_rc/${r_len}b"
    { [ "$r_rc" -ne 0 ] && [ "$r_len" -eq 0 ]; } || d3_ok=n
  done
  if [ "$d3_ok" = y ]; then
    pass "D3: every non-date refuses the same way —$d3_detail. There is no third answer and no default"
  else
    fail_ "D3" "each candidate must give a non-zero rc and zero bytes:$d3_detail"
  fi
fi
rm -rf "$T"

# ── D4: STRUCTURAL ABSENCE of the two atoms that made the defect ──────────
# An absence has to be discriminated structurally, and both halves are named
# because either one alone would have been survivable: the `|| echo "0"` tail
# is what manufactured the sentinel, and the epoch guard is what turned the
# sentinel into silence.
#
# COUNTED ON EXECUTED LINES ONLY, with the repo's own two-stage stripper. The
# file DESCRIBES the defect at length in its header — quoting the dead idiom is
# how the next reader learns not to reintroduce it — so a whole-file grep would
# fail this row for documenting the bug it fixes, which is precisely backwards.
T=$(mktemp -d)
sed -e 's/^[[:space:]]*#.*$//' -e 's/\([^[:space:]]\)[[:space:]][[:space:]]*#.*$/\1/' \
  "$CHECKER" > "$T/stripped"
tail_hits="$(grep -c '|| echo "\{0,1\}0"\{0,1\}' "$T/stripped" || true)"
case "$tail_hits" in ''|*[!0-9]*) tail_hits=0 ;; esac
guard_hits="$(grep -c 'last_epoch' "$T/stripped" || true)"
case "$guard_hits" in ''|*[!0-9]*) guard_hits=0 ;; esac
epoch_guard_hits="$(grep -c -- '[Ee]poch[a-z_]*" \{0,1\}-gt 0 \]' "$T/stripped" || true)"
case "$epoch_guard_hits" in ''|*[!0-9]*) epoch_guard_hits=0 ;; esac
stripped_lines="$(grep -c . "$T/stripped" || true)"
case "$stripped_lines" in ''|*[!0-9]*) stripped_lines=0 ;; esac
rm -rf "$T"
if [ "$tail_hits" -eq 0 ] && [ "$guard_hits" -eq 0 ] && [ "$epoch_guard_hits" -eq 0 ] \
   && [ "$stripped_lines" -gt 40 ]; then
  pass "D4: across $stripped_lines executed lines neither half of the shipped defect survives — no '|| echo 0' capture tail ($tail_hits), no last_epoch sentinel ($guard_hits), no '\$…epoch -gt 0' arm guard ($epoch_guard_hits). The two '-gt 0' tests that DO remain are the overdue/undetermined counters at the closing verdict, which is a different shape and deliberately not matched"
else
  fail_ "D4" "'|| echo 0' tails=$tail_hits (expect 0); last_epoch mentions=$guard_hits (expect 0); epoch '-gt 0' guards=$epoch_guard_hits (expect 0); executed lines seen=$stripped_lines (expect >40 — a stripper that ate the file would make this row vacuous)"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== H — the SessionStart nag arm (§8.3's second enforcement point) ==="
# ════════════════════════════════════════════════════════════════════════════

if [ ! -f "$HOOK" ]; then
  fail_ "H0" "scripts/session-cadence-check.sh is missing — §8.3's second enforcement point is the SessionStart nag, and the whole H section depends on it"
else
  # ── H1: SILENT when nothing is wrong ────────────────────────────────────
  # Zero bytes on BOTH streams. A hook that "only prints a little" when healthy
  # is a hook every session learns to skim past.
  T=$(mktemp -d); mk_current_proj "$T/p"
  run_hook "$REPO_ROOT/scripts" "$T/p"
  if [ "$HOOK_RC" -eq 0 ] && [ "${#HOOK_OUT}" -eq 0 ] && [ "${#HOOK_ERR}" -eq 0 ]; then
    pass "H1: against an all-current project the hook exits $HOOK_RC having written ${#HOOK_OUT} bytes to stdout and ${#HOOK_ERR} to stderr — silent when nothing is wrong, the house contract for every SessionStart hook the framework ships"
  else
    fail_ "H1" "rc=$HOOK_RC (expect 0); stdout bytes=${#HOOK_OUT} (expect 0); stderr bytes=${#HOOK_ERR} (expect 0); stdout='$HOOK_OUT'; stderr='$HOOK_ERR'"
  fi
  rm -rf "$T"

  # ── H2 / H3: it speaks on BOTH refusal codes, and never non-zero ────────
  T=$(mktemp -d)
  mk_current_proj "$T/over"; commit_dated "$T/over" CHANGELOG.md 40
  run_hook "$REPO_ROOT/scripts" "$T/over"; o_rc=$HOOK_RC; o_len=${#HOOK_OUT}
  mk_proj "$T/und"; commit_dated "$T/und" CHANGELOG.md 1; commit_dated "$T/und" sbom.json 1
  add_scan "$T/und" "2026-13-45_semgrep_pass.txt"
  run_hook "$REPO_ROOT/scripts" "$T/und"; u_rc=$HOOK_RC; u_len=${#HOOK_OUT}
  if [ "$o_rc" -eq 0 ] && [ "$o_len" -gt 0 ] && [ "$u_rc" -eq 0 ] && [ "$u_len" -gt 0 ]; then
    pass "H2/H3: the nag speaks on BOTH refusal codes — $o_len bytes for an overdue project and $u_len for an unmeasurable one — and exits 0 either way (rc $o_rc / $u_rc). A session hook reports; it never blocks"
  else
    fail_ "H2/H3" "overdue: rc=$o_rc (expect 0) bytes=$o_len (expect >0); unmeasurable: rc=$u_rc (expect 0) bytes=$u_len (expect >0)"
  fi
  rm -rf "$T"

  # ── H4: FAIL-OPEN under a forced internal crash ────────────────────────
  # Three separate ways for the thing it calls to be broken. A hook that
  # exits non-zero at SessionStart is a hook that can brick a session, so the
  # guarantee has to hold for a crash nobody anticipated — not just for the
  # one shape the author thought of.
  T=$(mktemp -d); mk_current_proj "$T/p"
  h4_ok=y; h4_detail=""
  for kind in exit42 syntax missing notadir; do
    ST="$T/tree-$kind"; mk_scripts_tree "$ST"
    case "$kind" in
      exit42)   printf '#!/usr/bin/env bash\nexit 42\n' > "$ST/scripts/check-maintenance.sh" ;;
      syntax)   printf '#!/usr/bin/env bash\nif [ \n' > "$ST/scripts/check-maintenance.sh" ;;
      missing)  rm -f "$ST/scripts/check-maintenance.sh" ;;
      notadir)  rm -f "$ST/scripts/check-maintenance.sh"; mkdir -p "$ST/scripts/check-maintenance.sh" ;;
    esac
    run_hook "$ST/scripts" "$T/p"
    h4_detail="$h4_detail $kind->rc$HOOK_RC"
    [ "$HOOK_RC" -eq 0 ] || h4_ok=n
  done
  if [ "$h4_ok" = y ]; then
    pass "H4: every forced internal crash still exits 0 —$h4_detail. A broken checker is inert at SessionStart, never a blocked session"
  else
    fail_ "H4" "each crash shape must still exit 0:$h4_detail"
  fi
  rm -rf "$T"

  # ── H5: ZERO NETWORK ───────────────────────────────────────────────────
  # Asserted by SHADOWING, not by reading the source: four network binaries
  # are put ahead of the real ones in PATH and each records its own invocation.
  # The fixture is the overdue one on purpose — the path that does the most
  # work is the one worth watching.
  T=$(mktemp -d); mk_current_proj "$T/p"; commit_dated "$T/p" CHANGELOG.md 40
  mkdir -p "$T/shim"
  for b in curl wget nc ping ssh; do
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s" >> "%s"\nexit 0\n' "$b" "$T/called" > "$T/shim/$b"
    chmod +x "$T/shim/$b"
  done
  net_rc=0
  net_out="$( cd "$T/p" && unset GITHUB_BASE_REF; PATH="$T/shim:$PATH" CLAUDE_PROJECT_DIR="$T/p" \
    bash "$REPO_ROOT/scripts/session-cadence-check.sh" </dev/null 2>&1 )" || net_rc=$?
  called="$(cat "$T/called" 2>/dev/null | tr '\n' ' ' || true)"
  shim_live=n
  ( PATH="$T/shim:$PATH"; curl --version >/dev/null 2>&1 ) && shim_live=y
  rm -f "$T/called"
  if [ "$net_rc" -eq 0 ] && [ -z "$called" ] && [ "$shim_live" = y ]; then
    pass "H5: with curl/wget/nc/ping/ssh shadowed ahead of the real binaries in PATH — and the shims proved reachable (shim_live=$shim_live) — the hook made no call at all ('$called') and still exited $net_rc on the busiest path it has"
  else
    fail_ "H5" "rc=$net_rc (expect 0); network binaries invoked='$called' (expect none); shims reachable=$shim_live (expect y — an unreachable shim would make this row vacuous); output:\n$net_out"
  fi
  rm -rf "$T"

  # ── H8: NO EVIDENCE, NO HEADLINE (R-WP6-3) ─────────────────────────────
  # rc 1 is also the code a shell hands back when it aborts under `set -e`, so a
  # checker that DIED looks exactly like one that measured an overdue — until
  # you look for the verdict line. The pre-review hook printed "a cadence is
  # OVERDUE" over a crash that had said nothing at all. Asserted in BOTH
  # directions from the same exit code, which is the only way to tell "suppress
  # a false headline" apart from "suppress the headline": a bare rc 1 is silent,
  # and an rc 1 that carries a real OVERDUE line still speaks.
  T=$(mktemp -d); mk_current_proj "$T/p"
  h8_ok=y; h8_detail=""
  for kind in crash1-silent crash1-noisy crash2-silent real1; do
    ST="$T/tree-$kind"; mk_scripts_tree "$ST"
    case "$kind" in
      crash1-silent) printf '#!/usr/bin/env bash\nexit 1\n' > "$ST/scripts/check-maintenance.sh"; want=quiet ;;
      crash1-noisy)  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "[WARN] Routine review (CHANGELOG.md) OVERDUE: last signal 40 days ago (threshold: 14 days)"\nexit 1\n' \
                       > "$ST/scripts/check-maintenance.sh"; want=loud ;;
      crash2-silent) printf '#!/usr/bin/env bash\nprintf "%%s\\n" "some unrelated chatter"\nexit 2\n' > "$ST/scripts/check-maintenance.sh"; want=quiet ;;
      real1)         : ;;   # the SHIPPED checker against a genuinely overdue tree
    esac
    if [ "$kind" = real1 ]; then
      commit_dated "$T/p" CHANGELOG.md 40; want=loud
    fi
    run_hook "$ST/scripts" "$T/p"
    h8_detail="$h8_detail ${kind}->rc$HOOK_RC/${#HOOK_OUT}b"
    case "$want" in
      quiet) { [ "$HOOK_RC" -eq 0 ] && [ "${#HOOK_OUT}" -eq 0 ] && [ "${#HOOK_ERR}" -eq 0 ]; } || h8_ok=n ;;
      loud)  { [ "$HOOK_RC" -eq 0 ] && [ "${#HOOK_OUT}" -gt 0 ]; } || h8_ok=n ;;
    esac
  done
  if [ "$h8_ok" = y ]; then
    pass "H8: a headline is only spoken when the verdict line it is about actually exists —$h8_detail. A checker that dies at rc 1 saying nothing is silent (it is a crash, not a measurement), one that dies at rc 1 having genuinely printed an OVERDUE line still speaks, and the shipped checker against a real 40-day-old CHANGELOG speaks too. The suppression is of the false claim, not of the report"
  else
    fail_ "H8" "crash-with-no-verdict-line must be silent while a real verdict must still speak:$h8_detail"
  fi
  rm -rf "$T"

  # ── H7: DAY-ZERO SILENCE — the nag is a POST-LAUNCH surface ────────────
  # Found by scaffolding a real project rather than by reasoning about one:
  # init.sh creates docs/test-results/ at birth, so a brand-new tree has the
  # evidence surface with nothing in it, the checker correctly answers 2, and
  # an ungated nag printed 354 bytes at the FIRST SessionStart of every
  # generated project — about a security scan a phase-0 project has never had
  # any reason to run. Silence is asserted at every pre-launch phase and for a
  # record that cannot be read at all, on BOTH streams; and the checker itself
  # must keep answering honestly underneath, or the gate has been put in the
  # wrong place.
  T=$(mktemp -d)
  h7_ok=y; h7_detail=""
  for ph in 0 1 2 3 missing garbage; do
    P="$T/p$ph"
    mk_proj "$P"                                   # writes current_phase 4
    commit_dated "$P" CHANGELOG.md 1
    mkdir -p "$P/docs/test-results"                # the birth shape: surface, no artefact
    case "$ph" in
      missing) rm -f "$P/.claude/phase-state.json" ;;
      garbage) printf 'not json at all\n' > "$P/.claude/phase-state.json" ;;
      *)       printf '{"track":"light","deployment":"personal","poc_mode":null,"current_phase":%s,"phases":{}}\n' "$ph" \
                 > "$P/.claude/phase-state.json" ;;
    esac
    run_hook "$REPO_ROOT/scripts" "$P"
    run_check "$REPO_ROOT/scripts" "$P"
    h7_detail="$h7_detail ${ph}->nag(rc$HOOK_RC/${#HOOK_OUT}b/${#HOOK_ERR}e,check rc$CHK_RC)"
    { [ "$HOOK_RC" -eq 0 ] && [ "${#HOOK_OUT}" -eq 0 ] && [ "${#HOOK_ERR}" -eq 0 ] && [ "$CHK_RC" -eq 2 ]; } || h7_ok=n
  done
  if [ "$h7_ok" = y ]; then
    pass "H7: at every pre-launch phase — and for a phase record that is missing or unreadable — the nag is byte-silent on both streams while the checker underneath still answers 2:$h7_detail. The gate is on the ADVISORY surface only, so WP7's release cut, which calls the checker directly at phase 4, is untouched"
  else
    fail_ "H7" "each case must be a silent rc 0 nag over an honest rc 2 checker:$h7_detail"
  fi
  rm -rf "$T"

  # ── H6: shipped and registered the way its five siblings are ───────────
  # THE SPLIT TOKEN IS LOAD-BEARING, and it is the house idiom (the identical
  # split and the identical reason are in tests/test-intake-wizard-fixes.sh):
  # the BL-154/BL-181 unit-lane predicate reads NAMES ON EXECUTED LINES, so
  # spelling the init script's filename here would silently exempt this whole
  # file from the tests.yml membership lint. This suite never RUNS that script
  # — it reads it. Do not "simplify" this back.
  INITF="$REPO_ROOT/init"; INITF="${INITF}.sh"
  h6_ok=1; h6_detail=""
  grep -qF "# CADENCE-NAG-HOOK-BEGIN" "$INITF" || { h6_ok=0; h6_detail="$h6_detail no-fence"; }
  grep -qF "# CADENCE-NAG-HOOK-END" "$INITF"   || { h6_ok=0; h6_detail="$h6_detail no-fence-end"; }
  grep -qF 'session-cadence-check.sh"))' "$INITF" || { h6_ok=0; h6_detail="$h6_detail no-idempotent-guard"; }
  grep -qF 'cp "$SCRIPT_DIR/scripts/session-cadence-check.sh" scripts/' "$INITF" || { h6_ok=0; h6_detail="$h6_detail not-shipped"; }
  grep -q 'chmod +x .*scripts/session-cadence-check\.sh' "$INITF" || { h6_ok=0; h6_detail="$h6_detail not-chmodded"; }
  # §0.3-C1: the orphan is INVOCATION-only. Re-shipping the checker would
  # re-fix a closed defect (BL-117 F20), so the cp count must stay at one.
  cm_cp="$(grep -c 'cp "\$SCRIPT_DIR/scripts/check-maintenance.sh"' "$INITF" || true)"
  case "$cm_cp" in ''|*[!0-9]*) cm_cp=0 ;; esac
  [ "$cm_cp" -eq 1 ] || { h6_ok=0; h6_detail="$h6_detail check-maintenance-cp=$cm_cp"; }
  hook_mode="$(_mode_of "$HOOK")"
  case "$hook_mode" in *7*|*5*|*1*) : ;; *) h6_ok=0; h6_detail="$h6_detail hook-not-executable($hook_mode)" ;; esac
  if [ "$h6_ok" -eq 1 ]; then
    pass "H6: the nag is copied, chmodded and merged into .hooks.SessionStart under its own excisable fence by the same idempotent contains-guard its five siblings use, the hook file itself is executable ($hook_mode), and check-maintenance.sh is still copied exactly $cm_cp time — §0.3-C1's orphan is wired, not re-shipped"
  else
    fail_ "H6" "missing wiring:$h6_detail"
  fi
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== I — the identifier registry (§11-WP6) ==="
# ════════════════════════════════════════════════════════════════════════════

IDT="$REPO_ROOT/templates/generated/identifiers.tmpl"
i1_ok=1
[ -f "$IDT" ] || i1_ok=0
if [ "$i1_ok" -eq 1 ]; then
  grep -qF '`DELTA-' "$IDT" || i1_ok=0
  grep -qF 'DELTA-001' "$IDT" || i1_ok=0
fi
if [ "$i1_ok" -eq 1 ]; then
  pass "I1: the generated identifier registry carries the DELTA- row with its example, so the post-release namespace is registered before anything mints an id in it — the registry's own rule three"
else
  fail_ "I1" "templates/generated/identifiers.tmpl must carry a DELTA- row with a DELTA-001 example (file present=$( [ -f "$IDT" ] && echo y || echo n ))"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== M — mutations: anchored, sites==1, one line changed, mode preserved ==="
# ════════════════════════════════════════════════════════════════════════════

# ── m1: revert the routine default 14 -> 35 ────────────────────────────────
# BOTH trees have the module stripped, and that is the whole point of the row
# rather than a convenience. With the module present the seam answers the same
# 14 from §7.2 and the script's constant is dead code — a first version of this
# mutant reverted the constant to 35 and NOTHING MOVED, which is how the second
# source got found. The stripped tree is the shape init.sh ships, so this row
# tests the value that is actually live in a generated project.
T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"; PT="$T/pri"; mk_scripts_tree "$PT"
strip_delta_module "$MT"; strip_delta_module "$PT"
pre_mode="$(_mode_of "$MT/scripts/check-maintenance.sh")"
_sed_inplace "$MT/scripts/check-maintenance.sh" 's|^.*CADENCE-DEFAULT-ROUTINE$|ROUTINE_DEFAULT_DAYS=35|'
post_mode="$(_mode_of "$MT/scripts/check-maintenance.sh")"
rep="$(_mutation_report "$REPO_ROOT/scripts/check-maintenance.sh" "$MT/scripts/check-maintenance.sh" 'CADENCE-DEFAULT-ROUTINE$')"
sites="${rep%%|*}"; rest="${rep#*|}"; changed="${rest%%|*}"; nlines="${rest##*|}"
mk_current_proj "$T/p"; commit_dated "$T/p" CHANGELOG.md 15
run_check "$PT/scripts" "$T/p"; pri_rc=$CHK_RC
run_check "$MT/scripts" "$T/p"; mut_rc=$CHK_RC
if [ "$sites" = "1" ] && [ "$changed" = y ] && [ "$nlines" -eq 2 ] && [ "$pre_mode" = "$post_mode" ] \
   && [ "$pri_rc" -eq 1 ] && [ "$mut_rc" -eq 0 ]; then
  pass "m1: with the routine default reverted to the shipped 35 — in the module-less tree init.sh actually produces — a CHANGELOG untouched for 15 days passes clean (rc $mut_rc) where the tuned tree refuses it (rc $pri_rc). P1's second arm goes RED; the 35 -> 14 retune is load-bearing and not decoration (marker sites=$sites, one line changed=$nlines/2, mode $pre_mode -> $post_mode)"
else
  fail_ "m1" "marker sites=$sites (expect 1); applied=$changed (expect y); diff lines=$nlines (expect 2); mode $pre_mode -> $post_mode; PRISTINE rc=$pri_rc (expect 1); MUTANT rc=$mut_rc (expect 0)"
fi
rm -rf "$T"

# ── m2: REMOVE THE UNDETERMINED COUNTER — the pin that matters most ────────
# The design names this mutant explicitly and requires it to be asserted on the
# EXIT CODE. The mutant's printed sentence is measured below for the reader,
# and it is the sentence BL-213 was filed about — but the predicate is the code.
T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"
pre_mode="$(_mode_of "$MT/scripts/check-maintenance.sh")"
_sed_inplace "$MT/scripts/check-maintenance.sh" 's|^.*CADENCE-UNDETERMINED-COUNTER$|  :|'
post_mode="$(_mode_of "$MT/scripts/check-maintenance.sh")"
rep="$(_mutation_report "$REPO_ROOT/scripts/check-maintenance.sh" "$MT/scripts/check-maintenance.sh" 'CADENCE-UNDETERMINED-COUNTER$')"
sites="${rep%%|*}"; rest="${rep#*|}"; changed="${rest%%|*}"; nlines="${rest##*|}"
mk_proj "$T/p"; commit_dated "$T/p" CHANGELOG.md 1; commit_dated "$T/p" sbom.json 1
add_scan "$T/p" "2026-13-45_semgrep_pass.txt"
run_check "$REPO_ROOT/scripts" "$T/p"; pri_rc=$CHK_RC
run_check "$MT/scripts" "$T/p"; mut_rc=$CHK_RC
mut_said=n
printf '%s' "$CHK_OUT" | grep -qF 'All maintenance cadences current' && mut_said=y
if [ "$sites" = "1" ] && [ "$changed" = y ] && [ "$nlines" -eq 2 ] && [ "$pre_mode" = "$post_mode" ] \
   && [ "$pri_rc" -eq 2 ] && [ "$mut_rc" -eq 0 ]; then
  pass "m2: with the undetermined counter removed — ONE line — a security artefact dated 2026-13-45 stops being an answer the script owes anyone: rc $mut_rc where the repaired tree answers rc $pri_rc, and the closing sentence is 'All maintenance cadences current' again (measured, not asserted: $mut_said). E3 goes RED. This is BL-213 re-opened in a single line, and the assertion is the exit code (marker sites=$sites, one line changed=$nlines/2, mode $pre_mode -> $post_mode)"
else
  fail_ "m2" "marker sites=$sites (expect 1); applied=$changed (expect y); diff lines=$nlines (expect 2); mode $pre_mode -> $post_mode; PRISTINE rc=$pri_rc (expect 2); MUTANT rc=$mut_rc (expect 0); mutant printed the all-current sentence=$mut_said"
fi
rm -rf "$T"

# ── m3: neuter the policy read ─────────────────────────────────────────────
T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"
pre_mode="$(_mode_of "$MT/scripts/check-maintenance.sh")"
_sed_inplace "$MT/scripts/check-maintenance.sh" 's|^.*CADENCE-POLICY-READ.*$|    v=""|'
post_mode="$(_mode_of "$MT/scripts/check-maintenance.sh")"
rep="$(_mutation_report "$REPO_ROOT/scripts/check-maintenance.sh" "$MT/scripts/check-maintenance.sh" 'CADENCE-POLICY-READ')"
sites="${rep%%|*}"; rest="${rep#*|}"; changed="${rest%%|*}"; nlines="${rest##*|}"
mk_current_proj "$T/p"; commit_dated "$T/p" CHANGELOG.md 15
write_policy "$T/p" '{"schemaVersion":1,"cadence":{"routine_review_days":30,"deep_security_days":95}}'
run_check "$REPO_ROOT/scripts" "$T/p"; pri_rc=$CHK_RC
run_check "$MT/scripts" "$T/p"; mut_rc=$CHK_RC
# WHAT THE MUTANT DOES NOT SAY, PROBED HONESTLY (R-WP6-6). A bare `policy` grep
# is useless here and the first version of this row used one: EVERY rc-1 run
# prints the standing recommendation "Both windows are policy, not constants",
# so the probe matched the boilerplate and the narrative then claimed a silence
# its own token was reporting as absent. The probe is now the set of phrases a
# script would use to REPORT a failed read, and the boilerplate is measured
# separately so the sentence can name what the match actually was.
mut_diag=n
printf '%s' "$CHK_OUT" | grep -qiE 'could not read|could not resolve|falling back|fall back|unavailable|ignoring' && mut_diag=y
mut_boiler=n
printf '%s' "$CHK_OUT" | grep -qF 'Both windows are policy, not constants' && mut_boiler=y
if [ "$sites" = "1" ] && [ "$changed" = y ] && [ "$nlines" -eq 2 ] && [ "$pre_mode" = "$post_mode" ] \
   && [ "$pri_rc" -eq 0 ] && [ "$mut_rc" -eq 1 ] && [ "$mut_diag" = n ]; then
  pass "m3: with the seam read neutered, a project whose own policy says 30 days is refused at 15 anyway (rc $mut_rc) where the tuned tree honours it (rc $pri_rc) — and the damage is SILENT: the mutant's transcript carries no diagnostic that a read failed (diagnostic phrases=$mut_diag), and the only mention of the word 'policy' in it is the standing recommendation every overdue run prints (boilerplate=$mut_boiler). P2 goes RED (marker sites=$sites, one line changed=$nlines/2, mode $pre_mode -> $post_mode)"
else
  fail_ "m3" "marker sites=$sites (expect 1); applied=$changed (expect y); diff lines=$nlines (expect 2); mode $pre_mode -> $post_mode; PRISTINE rc=$pri_rc (expect 0); MUTANT rc=$mut_rc (expect 1); mutant diagnostic about the lost policy=$mut_diag (expect n); rc-1 boilerplate present=$mut_boiler"
fi
rm -rf "$T"

# ── m4: neuter the hook's fail-open arm ────────────────────────────────────
if [ -f "$HOOK" ]; then
  T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"; PT="$T/pri"; mk_scripts_tree "$PT"
  pre_mode="$(_mode_of "$MT/scripts/session-cadence-check.sh")"
  _sed_inplace "$MT/scripts/session-cadence-check.sh" 's|^.*CADENCE-NAG-FAILOPEN$|  *) exit "$rc" ;;|'
  post_mode="$(_mode_of "$MT/scripts/session-cadence-check.sh")"
  rep="$(_mutation_report "$HOOK" "$MT/scripts/session-cadence-check.sh" 'CADENCE-NAG-FAILOPEN$')"
  sites="${rep%%|*}"; rest="${rep#*|}"; changed="${rest%%|*}"; nlines="${rest##*|}"
  # BOTH trees get the identical crashing checker, so the only difference
  # between the two runs is the mutated line.
  for t in "$PT" "$MT"; do printf '#!/usr/bin/env bash\nexit 42\n' > "$t/scripts/check-maintenance.sh"; done
  mk_current_proj "$T/p"
  run_hook "$PT/scripts" "$T/p"; pri_rc=$HOOK_RC
  run_hook "$MT/scripts" "$T/p"; mut_rc=$HOOK_RC
  if [ "$sites" = "1" ] && [ "$changed" = y ] && [ "$nlines" -eq 2 ] && [ "$pre_mode" = "$post_mode" ] \
     && [ "$pri_rc" -eq 0 ] && [ "$mut_rc" -eq 42 ]; then
    pass "m4: with the fail-open arm neutered, a checker that crashes takes SessionStart down with it (hook rc $mut_rc) where the shipped hook stays inert (rc $pri_rc). H4 goes RED — fail-open is a line, not a promise in a header (marker sites=$sites, one line changed=$nlines/2, mode $pre_mode -> $post_mode)"
  else
    fail_ "m4" "marker sites=$sites (expect 1); applied=$changed (expect y); diff lines=$nlines (expect 2); mode $pre_mode -> $post_mode; PRISTINE hook rc=$pri_rc (expect 0); MUTANT hook rc=$mut_rc (expect 42)"
  fi
  rm -rf "$T"
fi

# ── m5: neuter the era gate -> day zero gets noisy again ──────────────────
if [ -f "$HOOK" ]; then
  T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"; PT="$T/pri"; mk_scripts_tree "$PT"
  pre_mode="$(_mode_of "$MT/scripts/session-cadence-check.sh")"
  _sed_inplace "$MT/scripts/session-cadence-check.sh" 's|^.*CADENCE-NAG-ERA-GATE$|:|'
  post_mode="$(_mode_of "$MT/scripts/session-cadence-check.sh")"
  rep="$(_mutation_report "$HOOK" "$MT/scripts/session-cadence-check.sh" 'CADENCE-NAG-ERA-GATE$')"
  sites="${rep%%|*}"; rest="${rep#*|}"; changed="${rest%%|*}"; nlines="${rest##*|}"
  # The birth shape, exactly: phase 0, one commit, an empty evidence surface.
  P="$T/p"; mk_proj "$P"; commit_dated "$P" CHANGELOG.md 1
  mkdir -p "$P/docs/test-results"
  printf '{"track":"light","deployment":"personal","poc_mode":null,"current_phase":0,"phases":{}}\n' \
    > "$P/.claude/phase-state.json"
  run_hook "$PT/scripts" "$P"; pri_rc=$HOOK_RC; pri_len=${#HOOK_OUT}
  run_hook "$MT/scripts" "$P"; mut_rc=$HOOK_RC; mut_len=${#HOOK_OUT}
  if [ "$sites" = "1" ] && [ "$changed" = y ] && [ "$nlines" -eq 2 ] && [ "$pre_mode" = "$post_mode" ] \
     && [ "$pri_len" -eq 0 ] && [ "$mut_len" -gt 0 ] && [ "$pri_rc" -eq 0 ] && [ "$mut_rc" -eq 0 ]; then
    pass "m5: with the era gate neutered, a phase-0 project one commit old is nagged about a quarterly security scan at its very first SessionStart — $mut_len bytes where the shipped hook writes $pri_len. H7 goes RED. Both still exit 0, which is the point: this failure is invisible to an exit-code assertion and needs a BYTE COUNT to see (marker sites=$sites, one line changed=$nlines/2, mode $pre_mode -> $post_mode)"
  else
    fail_ "m5" "marker sites=$sites (expect 1); applied=$changed (expect y); diff lines=$nlines (expect 2); mode $pre_mode -> $post_mode; PRISTINE bytes=$pri_len rc=$pri_rc (expect 0 bytes, rc 0); MUTANT bytes=$mut_len rc=$mut_rc (expect >0 bytes, rc 0)"
  fi
  rm -rf "$T"
fi

# ── m6: neuter the evidence guard -> a crash speaks as an overdue again ───
if [ -f "$HOOK" ]; then
  T=$(mktemp -d); MT="$T/mut"; mk_scripts_tree "$MT"; PT="$T/pri"; mk_scripts_tree "$PT"
  pre_mode="$(_mode_of "$MT/scripts/session-cadence-check.sh")"
  _sed_inplace "$MT/scripts/session-cadence-check.sh" 's|^.*CADENCE-NAG-EVIDENCE$|:|'
  post_mode="$(_mode_of "$MT/scripts/session-cadence-check.sh")"
  rep="$(_mutation_report "$HOOK" "$MT/scripts/session-cadence-check.sh" 'CADENCE-NAG-EVIDENCE$')"
  sites="${rep%%|*}"; rest="${rep#*|}"; changed="${rest%%|*}"; nlines="${rest##*|}"
  # Both trees get the identical silently-crashing checker: rc 1, no output.
  for t in "$PT" "$MT"; do printf '#!/usr/bin/env bash\nexit 1\n' > "$t/scripts/check-maintenance.sh"; done
  P="$T/p"; mk_current_proj "$P"
  run_hook "$PT/scripts" "$P"; pri_rc=$HOOK_RC; pri_len=${#HOOK_OUT}
  run_hook "$MT/scripts" "$P"; mut_rc=$HOOK_RC; mut_len=${#HOOK_OUT}
  mut_claims=n
  printf '%s' "$HOOK_OUT" | grep -qF 'a cadence is OVERDUE' && mut_claims=y
  if [ "$sites" = "1" ] && [ "$changed" = y ] && [ "$nlines" -eq 2 ] && [ "$pre_mode" = "$post_mode" ] \
     && [ "$pri_len" -eq 0 ] && [ "$mut_len" -gt 0 ] && [ "$mut_claims" = y ] \
     && [ "$pri_rc" -eq 0 ] && [ "$mut_rc" -eq 0 ]; then
    pass "m6: with the evidence guard neutered, a checker that simply died — rc 1, not one byte of output — is announced to the session as 'a cadence is OVERDUE' (claim present=$mut_claims, $mut_len bytes) where the shipped hook stays silent ($pri_len bytes). H8 goes RED. Both exit 0, so like m5 this failure is invisible to an exit-code assertion; it needs the byte count and the claim probe (marker sites=$sites, one line changed=$nlines/2, mode $pre_mode -> $post_mode)"
  else
    fail_ "m6" "marker sites=$sites (expect 1); applied=$changed (expect y); diff lines=$nlines (expect 2); mode $pre_mode -> $post_mode; PRISTINE bytes=$pri_len rc=$pri_rc (expect 0 bytes, rc 0); MUTANT bytes=$mut_len rc=$mut_rc (expect >0 bytes, rc 0) claiming OVERDUE=$mut_claims (expect y)"
  fi
  rm -rf "$T"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
