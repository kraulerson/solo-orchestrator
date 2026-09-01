#!/usr/bin/env bash
# tests/test-brownfield-wp3-adoption-arms.sh
#
# Brownfield adoption WP3 — the IN-CORE ENABLING ARMS. Design:
# docs/designs/2026-08-02-brownfield-adoption-v1.md §10-WP3 (deliverables and
# proofs), §3.1/§3.2 (why the arms are in-core), §5.3 (the per-gate mapping;
# the TDD ordering row is kind (c)), §8.5 (the stamp's home, its
# merge-versus-re-stamp reasoning, and the five existing-file writers), §9
# (what does not change).
#
# WP3 is the design's own named LINCHPIN: it is the only brownfield package
# that touches a gate.
#
# ── THE [WARN] TRAP (repo CLAUDE.md; §10's preamble) ────────────────────────
# In check-phase-gate.sh the `[WARN]` / `[FAIL]` text is COSMETIC — the exit
# predicate is `if [ $issues -eq 0 ]`. An exemption is the ABSENCE of an
# `issues=$((issues + 1))`; a block is its presence. Of the 66 increment sites,
# 34 print `[WARN]` and 10 print `[FAIL]`. So EVERY verdict in this file is
# asserted on an EXIT CODE. Printed strings appear only as PATH DISCRIMINATORS
# (see below) and never as a verdict.
#
# ── Structural discriminators (this wave's harness standard) ────────────────
# Three of the proofs below expect an ABSENCE as the mutant's result (no block,
# no finding, no report). Several DIFFERENT edits share that one downstream
# silence — a mutant that dies on a syntax error is also silent. Every such
# proof therefore carries a discriminator that only the INTENDED path can
# satisfy: the mutant must still load its library and still answer the accessor
# correctly, and (where the path is observable) must print the arm's own
# message. The exit code remains the verdict; the discriminator only proves
# WHICH path produced it.
#
# ── Scenarios ───────────────────────────────────────────────────────────────
#   A1..A4  The `adopted` flag accessor. Absent file, absent block and
#           `adopted:false` all read NOT ADOPTED — a greenfield project must be
#           untouched by every arm in this WP (§10-WP3 deliverable 1).
#   S1      soif_adoption_stamp is an ADDITIVE merge: a foreign top-level
#           manifest key survives it, and the written block carries §8.5's
#           schema.
#   S2      No-op on a missing manifest (the `[ -f … ] || return 0` idiom
#           soif_currency_stamp uses).
#   S3      The five existing-file manifest writers named in §8.5 are run IN
#           SEQUENCE over a stamped manifest and the stamp is still present
#           afterwards. Each writer's jq filter is PINNED at sites==1 in its
#           own shipped source, so a writer that changes shape fails this test
#           loudly instead of leaving it exercising a stale copy.
#   S4      An EMPTY evidence hash is REFUSED — a durable record must not be
#           written malformed. THIS ROW WAS RE-AIMED AT WP9: it used to pin the
#           `completed|in-flight` scenario enum, and v2 §8.3 removed `scenario`
#           from the record with the chooser that produced it (D4). The guard's
#           JOB did not go with its subject — the evidence hash is what is left
#           to validate, and it is validated in the writer rather than left to
#           the writer's one caller.
#   T1/T2   TDD arm, DIRECTION (i): an adopted project's pre-adoption commit is
#           exempt (T1, rc 0); neuter the exemption guard and the SAME fixture
#           blocks (T2, rc 1).
#   T3/T4   TDD arm, DIRECTION (ii) — THE ONE THAT MATTERS. A post-adoption
#           commit with no test BLOCKS (T3, rc 1); neuter the BOUND and it
#           PASSES (T4, rc 0). An unbounded exemption is a permanent TDD waiver
#           wearing an adoption badge, so T4 is the proof this WP turns on.
#   T5      Greenfield regression: no adoption block ⇒ the gate behaves exactly
#           as it did before this WP (rc 1 on a non-bypassable tier).
#   T6      Tier behaviour is UNTOUCHED (§9): a bypassable tier still warns and
#           allows post-adoption.
#   G1..G4  Stamp acceptance in the gate, and the loss detector: intact ⇒ no
#           finding (G1); committed-at-HEAD but gone from the working tree ⇒
#           the gate exits NON-ZERO (G2); neuter the detector ⇒ the project
#           SILENTLY un-adopts and the gate exits 0 (G3); a mid-adoption
#           project whose stamp is not yet committed raises no false alarm
#           (G4).
#
# The REAL regenerate path (delete the manifest → verify-install.sh --auto-fix
# → fix_framework_manifest → the upstream CDF writer rewrites it wholesale) is
# proved in tests/test-brownfield-wp3-regenerate-path.sh, which is deliberately
# a separate suite: it executes the upstream installer and is therefore
# unit-lane exempt, while everything here stays in the fast lane.
#
# Hermetic: temp dirs only, no network, no remote creation.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/adoption-stamp.sh"
GATE="$REPO_ROOT/scripts/check-phase-gate.sh"
PCG="$REPO_ROOT/scripts/pre-commit-gate.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT INT TERM
# newtmp — a FRESH directory per scenario. `mktemp -d`, not an incrementing
# counter: newtmp is always called in a command substitution, i.e. a SUBSHELL,
# so a counter variable never survives back to the parent and every scenario
# silently lands in the same directory. That is not a hypothetical — it is what
# this file did on its first run, and it made one mutation proof pass against a
# fixture the previous scenario had already committed into.
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }

# _mode_of FILE — octal permission bits, GNU-first then BSD (house portability
# rule). "?" when neither answers.
_mode_of() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || printf '?\n'
}

# _sed_inplace FILE SED-EXPR — in-place sed PRESERVING the file's mode. The
# obvious spelling ends in `chmod +x`, which silently widens a 0644 lib to 0755
# and rides along in the next commit.
_sed_inplace() {
  local file="$1" expr="$2" tmp mode
  mode="$(_mode_of "$file")"
  tmp="$(mktemp)"
  sed "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
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

# _num VALUE — a shell-comparable integer (jq prints a missing field as the
# four-character string "null", which `[ "$x" -eq 1 ]` rejects with a
# diagnostic AND a false branch — a missing field would otherwise take the same
# path as a zero).
_num() { case "$1" in ''|null|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac }

# _parses FILE — 1 iff the mutant is still valid shell. THE discriminator this
# file exists to carry, and it is not theoretical: the first cut of T2 replaced
# a line that sat MID-CONTINUATION of a two-line `if` condition. diff reported
# the expected 2 changed lines, the anchor resolved at sites==1, and the result
# was a MANGLED PARSE that took the exemption branch for a reason having nothing
# to do with the exemption. A mutation proof whose mutant does not parse is
# measuring a syntax error. Every mutant below must parse.
_parses() { bash -n "$1" >/dev/null 2>&1 && printf '1\n' || printf '0\n'; }

if [ ! -f "$LIB" ]; then
  echo "  [FAIL] setup — $LIB not found (WP3 deliverable 1/2 missing)"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

# shellcheck source=/dev/null
. "$LIB"

echo "=== A — the adopted flag accessor (§10-WP3 deliverable 1) ==="

A="$(newtmp)"
if soif_adoption_adopted "$A/nope.json"; then
  fail_ "A1" "a missing manifest read as ADOPTED"
else
  pass "A1: a missing manifest reads NOT ADOPTED (rc non-zero)"
fi

printf '%s\n' '{"host":"github","frameworkVersion":"1"}' > "$A/greenfield.json"
if soif_adoption_adopted "$A/greenfield.json"; then
  fail_ "A2" "a manifest with no adoption block read as ADOPTED — every arm in this WP would fire on a greenfield project"
else
  pass "A2: absent adoption block reads NOT ADOPTED (greenfield unaffected)"
fi

printf '%s\n' '{"adoption":{"adopted":true,"schemaVersion":1}}' > "$A/adopted.json"
if soif_adoption_adopted "$A/adopted.json"; then
  pass "A3: adoption.adopted=true reads ADOPTED (rc 0)"
else
  fail_ "A3" "adoption.adopted=true did not read as ADOPTED"
fi

printf '%s\n' '{"adoption":{"adopted":false,"schemaVersion":1}}' > "$A/notadopted.json"
if soif_adoption_adopted "$A/notadopted.json"; then
  fail_ "A4" "adoption.adopted=false read as ADOPTED"
else
  pass "A4: adoption.adopted=false reads NOT ADOPTED"
fi

echo ""
echo "=== S — soif_adoption_stamp (§8.5: one additive merge, one call site) ==="

S="$(newtmp)"
( cd "$S" && git init -q . && git config user.email s@t.invalid && git config user.name S \
    && echo x > f.txt && git add f.txt && git commit -q -m "chore: base" ) >/dev/null 2>&1
printf '%s\n' '{"foreignKey":"keep-me","host":"gitlab","currency":{"schemaVersion":1}}' > "$S/manifest.json"

( cd "$S" && soif_adoption_stamp "manifest.json" "deadbeef" ) >/dev/null 2>&1
s1_foreign=$(jq -r '.foreignKey // "MISSING"' "$S/manifest.json" 2>/dev/null)
s1_currency=$(jq -r '.currency.schemaVersion // "MISSING"' "$S/manifest.json" 2>/dev/null)
s1_adopted=$(jq -r '.adoption.adopted // "MISSING"' "$S/manifest.json" 2>/dev/null)
# The v2 block's key set, asserted as a SET rather than as three absences: a
# partial deletion passes an absence pair and fails a set comparison.
s1_keys=$(jq -r '.adoption | keys | join(",")' "$S/manifest.json" 2>/dev/null)
s1_ver=$(jq -r '.adoption.schemaVersion // "MISSING"' "$S/manifest.json" 2>/dev/null)
s1_sha=$(jq -r '.adoption.scannerReportSha256 // "MISSING"' "$S/manifest.json" 2>/dev/null)
s1_at=$(jq -r '.adoption.adoptedAt // "MISSING"' "$S/manifest.json" 2>/dev/null)
s1_anchor=$(jq -r '.adoption.adoptedAtCommit // "MISSING"' "$S/manifest.json" 2>/dev/null)
s1_head=$( cd "$S" && git rev-parse HEAD 2>/dev/null )
if [ "$s1_foreign" = "keep-me" ] && [ "$s1_currency" = "1" ] && [ "$s1_adopted" = "true" ] \
   && [ "$s1_keys" = "adopted,adoptedAt,adoptedAtCommit,scannerReportSha256,schemaVersion" ] \
   && [ "$s1_ver" = "2" ] \
   && [ "$s1_sha" = "deadbeef" ] && [ "$s1_anchor" = "$s1_head" ] \
   && printf '%s' "$s1_at" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'; then
  pass "S1: the stamp is ADDITIVE — foreignKey and .currency both survive — and the block carries v2 §8.3's schema EXACTLY (five keys, schemaVersion 2, adoptedAtCommit = the pre-adoption tip)"
else
  fail_ "S1" "foreign=$s1_foreign currency=$s1_currency adopted=$s1_adopted keys=$s1_keys schemaVersion=$s1_ver sha=$s1_sha adoptedAt=$s1_at anchor=$s1_anchor head=$s1_head"
fi

S2D="$(newtmp)"
if ( cd "$S2D" && soif_adoption_stamp "absent-manifest.json" "deadbeef" ) >/dev/null 2>&1; then
  if [ -e "$S2D/absent-manifest.json" ]; then
    fail_ "S2" "the stamp CREATED a manifest that did not exist"
  else
    pass "S2: no-op on a missing manifest (rc 0, nothing created)"
  fi
else
  fail_ "S2" "the stamp returned non-zero on a missing manifest (expected a silent no-op)"
fi

# ── S3: the five §8.5 existing-file writers, run IN SEQUENCE ────────────────
# Each writer is exercised by the jq filter EXTRACTED from its own shipped
# source, and each anchor is asserted at sites==1 first. That pin is the point:
# if any writer changes shape, this test fails loudly rather than continuing to
# exercise a hard-coded copy that no longer matches the tree. (Invoking the
# whole surrounding script instead would drag an installer into a fast-lane
# suite; the property under test is the ADDITIVITY OF THE FILTER.)
W_CG="$REPO_ROOT/scripts/check-gate.sh"
W_UP="$REPO_ROOT/scripts/upgrade-project.sh"
W_CM="$REPO_ROOT/scripts/lib/currency-manifest.sh"
F_HOST_CG='jq --arg h "$inferred" '"'"'.host = $h'"'"''
F_HOST_UP='jq --arg h "$inferred_host" '"'"'.host = $h'"'"''
F_BL030="'. + {deployment: \$dep, poc_mode: \$pm, enforcement_level: \"strict\"}'"
F_BL061="'. + {deployment: \$dep, poc_mode: \$pm}'"
F_CURR="'.currency = \$currency'"
n_cg=$(grep -cF -- "$F_HOST_CG" "$W_CG" 2>/dev/null); n_cg=$(_num "$n_cg")
n_up=$(grep -cF -- "$F_HOST_UP" "$W_UP" 2>/dev/null); n_up=$(_num "$n_up")
n_30=$(grep -cF -- "$F_BL030" "$W_UP" 2>/dev/null); n_30=$(_num "$n_30")
n_61=$(grep -cF -- "$F_BL061" "$W_UP" 2>/dev/null); n_61=$(_num "$n_61")
n_cu=$(grep -cF -- "$F_CURR" "$W_CM" 2>/dev/null); n_cu=$(_num "$n_cu")

S3D="$(newtmp)"
cp "$S/manifest.json" "$S3D/manifest.json"
_w() { # _w <jq-filter> <args...>  — apply one writer with the atomic-rename pattern
  local filter="$1"; shift
  jq "$@" "$filter" "$S3D/manifest.json" > "$S3D/manifest.json.tmp" && mv "$S3D/manifest.json.tmp" "$S3D/manifest.json"
}
w_ok=1
_w '.host = $h' --arg h "github"                                                        || w_ok=0
_w '.host = $h' --arg h "gitlab"                                                        || w_ok=0
_w '. + {deployment: $dep, poc_mode: $pm, enforcement_level: "strict"}' --arg dep organizational --arg pm sponsored_poc || w_ok=0
_w '. + {deployment: $dep, poc_mode: $pm}' --arg dep organizational --arg pm sponsored_poc || w_ok=0
_w '.currency = $currency' --argjson currency '{"schemaVersion":1,"files":{}}'           || w_ok=0
s3_adopted=$(jq -r '.adoption.adopted // "MISSING"' "$S3D/manifest.json" 2>/dev/null)
s3_ver=$(jq -r '.adoption.schemaVersion // "MISSING"' "$S3D/manifest.json" 2>/dev/null)
s3_foreign=$(jq -r '.foreignKey // "MISSING"' "$S3D/manifest.json" 2>/dev/null)
if [ "$w_ok" -eq 1 ] && [ "$s3_adopted" = "true" ] && [ "$s3_ver" = "2" ] \
   && [ "$s3_foreign" = "keep-me" ] \
   && [ "$n_cg" -eq 1 ] && [ "$n_up" -eq 1 ] && [ "$n_30" -eq 1 ] && [ "$n_61" -eq 1 ] && [ "$n_cu" -eq 1 ]; then
  pass "S3: all five §8.5 existing-file writers run in sequence (host×2, BL-030 backfill, BL-061 refresh, .currency) and the adoption block survives every one; each filter pinned at sites==1 in its shipped source"
else
  fail_ "S3" "writers_ok=$w_ok adopted=$s3_adopted schemaVersion=$s3_ver foreign=$s3_foreign sites: check-gate=$n_cg upgrade-host=$n_up bl030=$n_30 bl061=$n_61 currency=$n_cu (each want 1)"
fi

S4D="$(newtmp)"
printf '%s\n' '{"host":"github"}' > "$S4D/manifest.json"
if ( cd "$S4D" && soif_adoption_stamp "manifest.json" "" ) >/dev/null 2>&1; then
  fail_ "S4" "an EMPTY evidence hash was ACCEPTED"
else
  if jq -e '.adoption' "$S4D/manifest.json" >/dev/null 2>&1; then
    fail_ "S4" "the stamp refused (rc non-zero) but still wrote an adoption block"
  else
    pass "S4: an EMPTY evidence hash is refused and nothing is written — the record never claims a hash it does not have"
  fi
fi

# ── S5: "written once, at adoption, never re-stamped" is ENFORCED ──────────
# §8.5 states the property; the first cut only asserted it in a header, and a
# second stamp was accepted — silently moving adoptedAtCommit to the current
# tip, which re-opens the TDD exemption window at will (adversarial review
# R-WP3-2). Both directions are pinned here: the FIRST stamp must succeed
# (otherwise a refusal that refused everything would pass this test), and the
# SECOND must be refused with the anchor unmoved.
S5D="$(newtmp)"
( cd "$S5D" && git init -q . && git config user.email s5@t.invalid && git config user.name S5 \
    && echo x > f.txt && git add f.txt && git commit -q -m "chore: base" ) >/dev/null 2>&1
printf '%s\n' '{"host":"github"}' > "$S5D/manifest.json"
s5_first=0
( cd "$S5D" && soif_adoption_stamp "manifest.json" "one" ) >/dev/null 2>&1 && s5_first=1
s5_anchor_1=$(jq -r '.adoption.adoptedAtCommit // "MISSING"' "$S5D/manifest.json" 2>/dev/null)
s5_sha_1=$(jq -r '.adoption.scannerReportSha256 // "MISSING"' "$S5D/manifest.json" 2>/dev/null)
( cd "$S5D" && echo y > g.txt && git add g.txt && git commit -q -m "chore: adopt" ) >/dev/null 2>&1
s5_second_rc=0
( cd "$S5D" && soif_adoption_stamp "manifest.json" "two" ) >/dev/null 2>&1 || s5_second_rc=$?
s5_anchor_2=$(jq -r '.adoption.adoptedAtCommit // "MISSING"' "$S5D/manifest.json" 2>/dev/null)
s5_sha_2=$(jq -r '.adoption.scannerReportSha256 // "MISSING"' "$S5D/manifest.json" 2>/dev/null)
if [ "$s5_first" -eq 1 ] && [ "$s5_second_rc" -ne 0 ] \
   && [ "$s5_anchor_1" = "$s5_anchor_2" ] && [ "$s5_sha_1" = "one" ] && [ "$s5_sha_2" = "one" ]; then
  pass "S5: the FIRST stamp is written and the SECOND is REFUSED (rc $s5_second_rc) with the anchor and the whole block unmoved — §8.5's 'never re-stamped' is structural, not a convention"
else
  fail_ "S5" "first_stamp_ok=$s5_first (want 1) second_rc=$s5_second_rc (want non-zero) anchor_before=$s5_anchor_1 anchor_after=$s5_anchor_2 (want equal) sha_before=$s5_sha_1 sha_after=$s5_sha_2 (want both 'one')"
fi

echo ""
echo "=== T — the TDD pre-adoption arm (§5.3 kind (c); dual-direction) ==="

# mk_tdd_proj DIR TIER — a scratch project on the NON-bypassable tier by
# default, so a firing TDD gate HARD-BLOCKS (rc 1) rather than warns and the
# exit code is an unambiguous verdict. current_phase=1 keeps the BL-006
# message check short-circuited (< 2) so the TDD arm alone decides.
mk_tdd_proj() {
  local d="$1" tier="${2:-strict}"
  mkdir -p "$d/.claude" "$d/scripts/lib"
  ( cd "$d" \
      && git init -q \
      && git config user.email "wp3@test.invalid" \
      && git config user.name  "WP3 Test" \
      && echo "# scratch" > README.md \
      && git add README.md \
      && git commit -q -m "chore: their history" ) || return 1
  if [ "$tier" = "strict" ]; then
    printf '%s\n' '{"current_phase":1,"track":"full","deployment":"organizational","poc_mode":"sponsored_poc","phases":{}}' > "$d/.claude/phase-state.json"
  else
    printf '%s\n' '{"current_phase":1,"track":"light","deployment":"personal","poc_mode":null,"phases":{}}' > "$d/.claude/phase-state.json"
  fi
  printf '%s\n' '{"phase2_init":{"steps_completed":[],"verified":false},"build_loop":{"feature":null,"step":0,"steps_completed":[]},"uat_session":{},"phase3_validation":{},"phase4_release":{}}' > "$d/.claude/process-state.json"
  printf '%s\n' '{"frameworkVersion":"test","host":"other","mode":"personal"}' > "$d/.claude/manifest.json"
  cp "$PCG" "$d/scripts/"
  cp "$REPO_ROOT/scripts/lib/helpers.sh" \
     "$REPO_ROOT/scripts/lib/helpers-core.sh" \
     "$REPO_ROOT/scripts/lib/helpers-full.sh" \
     "$REPO_ROOT/scripts/lib/tdd-classify.sh" \
     "$LIB" "$d/scripts/lib/"
  chmod +x "$d/scripts/pre-commit-gate.sh"
}

# adopt_proj DIR — write a real adoption stamp into the fixture's manifest with
# the anchor at the CURRENT tip (this is the adoption window: the stamp exists,
# the adoption commit has not landed yet).
adopt_proj() {
  local d="$1"
  ( cd "$d" && soif_adoption_stamp ".claude/manifest.json" "completed" 3 '[]' '[]' '["tdd-ordering"]' '[]' "sha" )
}

# stage_impl_only DIR — one implementation file, no test, staged.
stage_impl_only() {
  local d="$1"
  mkdir -p "$d/src"
  printf 'export function add(a,b){return a+b;}\n' > "$d/src/add.js"
  ( cd "$d" && git add src/add.js )
}

# run_tdd DIR SUBJECT — the commit-msg surface. Echoes output; rc is the verdict.
run_tdd() {
  local d="$1" subject="$2"
  printf '%s\n' "$subject" > "$d/.git/COMMIT_EDITMSG"
  ( cd "$d" && bash scripts/pre-commit-gate.sh --terminal-mode --tdd-only 2>&1 )
}

# ── T1 — direction (i) CONTROL: a pre-adoption commit is exempt ─────────────
T1D="$(newtmp)/p"
if ! mk_tdd_proj "$T1D"; then
  fail_ "T1" "fixture setup failed"
else
  adopt_proj "$T1D" >/dev/null 2>&1
  stage_impl_only "$T1D"
  t1_out=$(run_tdd "$T1D" "feat: their pre-adoption work"); t1_rc=$?
  if [ "$t1_rc" -eq 0 ]; then
    pass "T1 (direction i, control): an adopted project's PRE-adoption commit is exempt on a NON-bypassable tier — rc 0"
  else
    fail_ "T1" "rc=$t1_rc (want 0). Output: $(printf '%s' "$t1_out" | tail -3 | tr '\n' ' ')"
  fi
fi

# ── T2 — direction (i) MUTATION: neuter the exemption guard ────────────────
T2R="$(newtmp)"; T2D="$T2R/p"
if ! mk_tdd_proj "$T2D"; then
  fail_ "T2" "fixture setup failed"
else
  adopt_proj "$T2D" >/dev/null 2>&1
  stage_impl_only "$T2D"
  MUT="$T2D/scripts/pre-commit-gate.sh"
  guard_sites=$(grep -c 'BF-ADOPT-TDD-GUARD$' "$PCG" 2>/dev/null); guard_sites=$(_num "$guard_sites")
  cp "$PCG" "$T2R/orig.ref"
  _sed_inplace "$MUT" 's|^.*BF-ADOPT-TDD-GUARD$|  if false; then   # BF-ADOPT-TDD-GUARD|'
  chg2=$(_changed_lines "$T2R/orig.ref" "$MUT")
  p2=$(_parses "$MUT")
  t2_out=$(run_tdd "$T2D" "feat: their pre-adoption work"); t2_rc=$?
  if [ "$t2_rc" -ne 0 ] && [ "$chg2" -eq 2 ] && [ "$guard_sites" -eq 1 ] && [ "$p2" -eq 1 ]; then
    pass "T2 (direction i, mutation): with the exemption guard neutered (1 line, mutant still parses), the SAME pre-adoption fixture BLOCKS — rc $t2_rc; the exemption is load-bearing"
  else
    fail_ "T2" "rc=$t2_rc (want non-zero) changed_lines=$chg2 (want 2) guard_anchor_sites=$guard_sites (want 1) mutant_parses=$p2 (want 1)"
  fi
fi

# ── T3 — direction (ii) CONTROL: a POST-adoption commit blocks ─────────────
# The adoption commit has landed, so the anchor is a STRICT ancestor of HEAD.
T3R="$(newtmp)"; T3D="$T3R/p"
if ! mk_tdd_proj "$T3D"; then
  fail_ "T3" "fixture setup failed"
else
  adopt_proj "$T3D" >/dev/null 2>&1
  ( cd "$T3D" && git add -A .claude && git commit -q -m "chore: adopt project" ) >/dev/null 2>&1
  stage_impl_only "$T3D"
  t3_out=$(run_tdd "$T3D" "feat: work written AFTER adoption day"); t3_rc=$?
  if [ "$t3_rc" -ne 0 ]; then
    pass "T3 (direction ii, control): a POST-adoption commit with no test BLOCKS — rc $t3_rc. §4.5: no arm exempts a commit written after adoption day"
  else
    fail_ "T3" "rc=$t3_rc (want non-zero) — the exemption leaked past the adoption commit"
  fi
fi

# ── T4 — direction (ii) MUTATION: neuter the BOUND. THE PROOF THAT MATTERS ──
# An unbounded exemption is a permanent TDD waiver wearing an adoption badge.
# The expected mutant result is an ABSENCE (no block), so this carries a
# structural discriminator: the mutant must PRINT the arm's own exemption line,
# which only the exemption path can emit. rc is still the verdict.
T4R="$(newtmp)"; T4D="$T4R/p"
if ! mk_tdd_proj "$T4D"; then
  fail_ "T4" "fixture setup failed"
else
  adopt_proj "$T4D" >/dev/null 2>&1
  ( cd "$T4D" && git add -A .claude && git commit -q -m "chore: adopt project" ) >/dev/null 2>&1
  stage_impl_only "$T4D"
  MUT4="$T4D/scripts/lib/adoption-stamp.sh"
  bound_sites=$(grep -c 'BF-ADOPT-BOUND$' "$LIB" 2>/dev/null); bound_sites=$(_num "$bound_sites")
  cp "$LIB" "$T4R/orig-lib.ref"
  _sed_inplace "$MUT4" 's|^.*BF-ADOPT-BOUND$|  if false; then   # BF-ADOPT-BOUND|'
  chg4=$(_changed_lines "$T4R/orig-lib.ref" "$MUT4")
  p4=$(_parses "$MUT4")
  t4_out=$(run_tdd "$T4D" "feat: work written AFTER adoption day"); t4_rc=$?
  # Discriminator 1: the mutant library still LOADS and still answers the
  # accessor — so an rc 0 cannot be a crashed-and-silent mutant.
  d4_load=0
  ( . "$MUT4" && soif_adoption_adopted "$T4D/.claude/manifest.json" ) >/dev/null 2>&1 && d4_load=1
  # Discriminator 2: the EXEMPTION path announced itself. rc 0 alone is shared
  # by "exempted" and "the gate never fired"; only the exemption emits this.
  d4_msg=0
  printf '%s' "$t4_out" | grep -q 'PRE-ADOPTION commit' && d4_msg=1
  if [ "$t4_rc" -eq 0 ] && [ "$chg4" -eq 2 ] && [ "$bound_sites" -eq 1 ] \
     && [ "$p4" -eq 1 ] && [ "$d4_load" -eq 1 ] && [ "$d4_msg" -eq 1 ]; then
    pass "T4 (direction ii, mutation — THE ONE THAT MATTERS): with the BOUND neutered (1 line, mutant still parses), a POST-adoption commit with no test PASSES (rc 0) via the exemption path; the unmutated control (T3) blocks"
  else
    fail_ "T4" "rc=$t4_rc (want 0) changed_lines=$chg4 (want 2) bound_anchor_sites=$bound_sites (want 1) mutant_parses=$p4 (want 1) mutant_lib_loads=$d4_load (want 1) exemption_path_announced=$d4_msg (want 1)"
  fi
fi

# ── T5 — greenfield regression: the arm must not leak ──────────────────────
T5R="$(newtmp)"; T5D="$T5R/p"
if ! mk_tdd_proj "$T5D"; then
  fail_ "T5" "fixture setup failed"
else
  stage_impl_only "$T5D"
  t5_out=$(run_tdd "$T5D" "feat: ordinary greenfield work"); t5_rc=$?
  if [ "$t5_rc" -ne 0 ]; then
    pass "T5: a project with NO adoption block behaves exactly as before — rc $t5_rc on a non-bypassable tier"
  else
    fail_ "T5" "rc=$t5_rc (want non-zero) — the WP3 arm changed greenfield behaviour"
  fi
fi

# ── T6 — tier behaviour untouched (§9) ─────────────────────────────────────
T6R="$(newtmp)"; T6D="$T6R/p"
if ! mk_tdd_proj "$T6D" bypassable; then
  fail_ "T6" "fixture setup failed"
else
  adopt_proj "$T6D" >/dev/null 2>&1
  ( cd "$T6D" && git add -A .claude && git commit -q -m "chore: adopt project" ) >/dev/null 2>&1
  stage_impl_only "$T6D"
  t6_out=$(run_tdd "$T6D" "feat: post-adoption on a bypassable tier"); t6_rc=$?
  t6_warned=0
  printf '%s' "$t6_out" | grep -q 'BL-072 TDD ordering' && t6_warned=1
  if [ "$t6_rc" -eq 0 ] && [ "$t6_warned" -eq 1 ]; then
    pass "T6: tier behaviour is UNTOUCHED — a bypassable tier still warns-and-allows post-adoption (rc 0, BL-072 line emitted)"
  else
    fail_ "T6" "rc=$t6_rc (want 0) bl072_line_emitted=$t6_warned (want 1)"
  fi
fi

echo ""
echo "=== T7 — THE BOUND ATTACK BATTERY (adversarial review R-WP3-1) ==="
# WHY THIS SECTION EXISTS. T1-T6 shipped 19/19 green while the bound was
# DEFEATABLE BY EVERYDAY GIT. The refuted model was this file's own first
# comment: "P not an ancestor => a branch cut before adoption => EXEMPT". That
# state is UNREACHABLE for a genuinely pre-adoption branch — such a branch has
# the PRE-adoption manifest checked out, so the accessor reads NOT ADOPTED and
# the arm never runs. Every state that actually reaches the "not an ancestor"
# arm carries the STAMPED tree, which means adoption already happened. The old
# arm therefore exempted only post-adoption commits — the exact inversion of
# §4.5.
#
# The T-series never constructed a divergent history, which is precisely why
# the hole and a green suite coexisted. So this battery is not one regression
# for one attack: it pins ALL TEN histories the reviewer drove, six of which
# produced an exempt post-adoption commit (rc 0 + the exemption banner) against
# the shipped code. Four of the six need no intent at all — a local `git
# rebase`, a SQUASH MERGE (a GitHub default, and the worst: it exempts every
# subsequent mainline commit forever), an orphan branch, and a cherry-pick.
#
# T1 remains the indispensable control: a predicate that simply blocked
# everything would pass all ten of these and be just as wrong.
# Verdicts are EXIT CODES. Non-zero = the gate refused the commit = correct.

# atk_base DIR — an adopted project whose adoption commit HAS LANDED.
# C1 "chore: their history" (the anchor) -> stamp -> C2 "chore: adopt project".
atk_base() {
  local d="$1"
  mk_tdd_proj "$d" || return 1
  adopt_proj "$d" >/dev/null 2>&1 || return 1
  ( cd "$d" && git add -A .claude && git commit -q -m "chore: adopt project" ) || return 1
}

# atk_verdict DIR — stage an impl-only change, run the real commit-msg surface
# with a post-adoption `feat:` subject, echo "<rc>|<banner>|<blocked-for-reason>".
#
# THE THIRD FIELD IS THE POINT (adversarial re-review R-WP3-7). "rc non-zero and
# no exemption banner" is satisfied by a row that never reached the gate at all
# — a fixture that rots and exits 127 scores rc=127, banner=0 and would be
# credited as BLOCKED. That is the same vacuity class that let the original
# bound hole hide behind 19/19 green, and its cousin already bit this file once
# (T7d's aborted cherry-pick died at the derivative-resume sentinel, rc 0 and no
# banner, reading exactly like a hole while proving nothing). So a row only
# counts as blocked when the BL-072 gate itself says it blocked. `grep -F` is
# load-bearing here: `[FAIL]` is a character class in a basic regex and would
# never match the literal text.
atk_verdict() {
  local d="$1" out rc=0 banner=0 reason=0
  stage_impl_only "$d" >/dev/null 2>&1
  out=$(run_tdd "$d" "feat: work written AFTER adoption day") || rc=$?
  printf '%s' "$out" | grep -q 'PRE-ADOPTION commit' && banner=1
  printf '%s' "$out" | grep -qF '[FAIL] BL-072 TDD ordering' && reason=1
  printf '%s|%s|%s\n' "$rc" "$banner" "$reason"
}

# _atk_split VALUE — parse atk_verdict's triple into ATK_RC/ATK_BANNER/
# ATK_REASON. Called from the PARENT shell (never a subshell) so the globals
# survive; `${v##*|}` alone silently reads the wrong field once there are three.
_atk_split() {
  local v="$1" rest
  ATK_RC="${v%%|*}"; rest="${v#*|}"
  ATK_BANNER="${rest%%|*}"; ATK_REASON="${rest##*|}"
}

# atk_report LABEL DIR EXPECT — EXPECT is `blocked` or `exempt`. Verdict is the
# EXIT CODE; the banner and the block-reason are discriminators that say WHICH
# path produced it.
atk_report() {
  local label="$1" d="$2" expect="$3" rc banner reason
  _atk_split "$(atk_verdict "$d")"
  rc="$ATK_RC"; banner="$ATK_BANNER"; reason="$ATK_REASON"
  ATK_RCS="${ATK_RCS}${label}=rc:${rc} "
  if [ "$expect" = "blocked" ]; then
    if [ "$rc" -ne 0 ] && [ "$banner" -eq 0 ] && [ "$reason" -eq 1 ]; then
      pass "$label: BLOCKED (rc=$rc, no exemption banner, blocked BY the BL-072 gate) — the bound holds"
    else
      fail_ "$label" "rc=$rc (want non-zero) exemption_banner=$banner (want 0) blocked_by_tdd_gate=$reason (want 1) — either a POST-adoption commit was exempted, or the fixture never reached the gate and the row would have false-passed"
    fi
  else
    if [ "$rc" -eq 0 ] && [ "$banner" -eq 1 ] && [ "$reason" -eq 0 ]; then
      pass "$label: EXEMPT (rc=0, banner printed, no gate block) — the adoption window is preserved"
    else
      fail_ "$label" "rc=$rc (want 0) exemption_banner=$banner (want 1) blocked_by_tdd_gate=$reason (want 0)"
    fi
  fi
}
ATK_RCS=""

# ── T7a — local `git rebase` rewrites the anchor commit ────────────────────
D="$(newtmp)/p"
if ! mk_tdd_proj "$D"; then fail_ "T7a" "fixture setup failed"; else
  ( cd "$D" && git checkout -q -b adopt-work \
      && echo work > work.txt && git add work.txt && git commit -q -m "chore: pre-stamp work" ) >/dev/null 2>&1
  adopt_proj "$D" >/dev/null 2>&1
  ( cd "$D" && git add -A .claude && git commit -q -m "chore: adopt project" ) >/dev/null 2>&1
  ( cd "$D" && git checkout -q main 2>/dev/null || git checkout -q master ) >/dev/null 2>&1
  ( cd "$D" && git commit -q --allow-empty -m "chore: mainline moves on" ) >/dev/null 2>&1
  ( cd "$D" && git checkout -q adopt-work && git rebase -q main ) >/dev/null 2>&1
  atk_report "T7a [local git rebase rewrote the anchor]" "$D" blocked
fi

# ── T7b — SQUASH-MERGED adoption branch (a GitHub default; the worst hole) ─
D="$(newtmp)/p"
if ! mk_tdd_proj "$D"; then fail_ "T7b" "fixture setup failed"; else
  ( cd "$D" && git checkout -q -b adopt-branch \
      && echo work > work.txt && git add work.txt && git commit -q -m "chore: pre-stamp work" ) >/dev/null 2>&1
  adopt_proj "$D" >/dev/null 2>&1
  ( cd "$D" && git add -A .claude && git commit -q -m "chore: adopt project" ) >/dev/null 2>&1
  ( cd "$D" && ( git checkout -q main 2>/dev/null || git checkout -q master ) \
      && git merge -q --squash adopt-branch && git commit -q -m "chore: adopt project (squashed)" ) >/dev/null 2>&1
  atk_report "T7b [squash-merged adoption branch]" "$D" blocked
fi

# ── T7c — orphan branch carrying the stamped tree ──────────────────────────
D="$(newtmp)/p"
if ! atk_base "$D"; then fail_ "T7c" "fixture setup failed"; else
  ( cd "$D" && git checkout -q --orphan orph && git commit -q -m "chore: orphan root" ) >/dev/null 2>&1
  atk_report "T7c [orphan branch]" "$D" blocked
fi

# ── T7d — adoption commit cherry-picked onto a branch that diverged earlier ─
# `.claude/` is TRACKED before the branch point on purpose. Left untracked, the
# cherry-pick aborts ("untracked working tree file would be overwritten"), git
# leaves CHERRY_PICK_HEAD behind, and `tdd_terminal_enforce` returns 0 at its
# derivative-resume sentinel WITHOUT EVER REACHING THE BOUND — rc 0 and no
# banner, which reads exactly like a hole while proving nothing about one. The
# first cut of this fixture did precisely that.
D="$(newtmp)/p"
if ! mk_tdd_proj "$D"; then fail_ "T7d" "fixture setup failed"; else
  ( cd "$D" && git add -A .claude && git commit -q -m "chore: their tooling" ) >/dev/null 2>&1
  ( cd "$D" && git branch divergent ) >/dev/null 2>&1
  ( cd "$D" && echo more > more.txt && git add more.txt && git commit -q -m "chore: their later history" ) >/dev/null 2>&1
  adopt_proj "$D" >/dev/null 2>&1
  ( cd "$D" && git add -A .claude && git commit -q -m "chore: adopt project" ) >/dev/null 2>&1
  adopt_sha=$( cd "$D" && git rev-parse HEAD )
  ( cd "$D" && git checkout -q divergent && git commit -q --allow-empty -m "chore: divergent work" \
      && git cherry-pick "$adopt_sha" ) >/dev/null 2>&1
  d7d_clean=0
  [ -f "$D/.git/CHERRY_PICK_HEAD" ] || d7d_clean=1
  if [ "$d7d_clean" -eq 0 ]; then
    fail_ "T7d" "cherry-pick did not complete (CHERRY_PICK_HEAD present) — the fixture would hit the derivative-resume skip and prove nothing about the bound"
  else
    atk_report "T7d [cherry-picked adoption onto a divergent branch]" "$D" blocked
  fi
fi

# ── T7e — bogus 40-hex anchor (fail-closed; defeats the any-40-hex class) ──
D="$(newtmp)/p"
if ! atk_base "$D"; then fail_ "T7e" "fixture setup failed"; else
  ( cd "$D" && jq '.adoption.adoptedAtCommit = "0123456789abcdef0123456789abcdef01234567"' .claude/manifest.json > m.tmp && mv m.tmp .claude/manifest.json ) >/dev/null 2>&1
  atk_report "T7e [bogus 40-hex anchor]" "$D" blocked
fi

# ── T7f — shallow clone: the anchor object is not in this repository ───────
D="$(newtmp)"
if ! atk_base "$D/src"; then fail_ "T7f" "fixture setup failed"; else
  ( cd "$D/src" && git add -A && git commit -q -m "chore: track everything" ) >/dev/null 2>&1
  ( cd "$D/src" && echo later > later.txt && git add later.txt && git commit -q -m "chore: later work" ) >/dev/null 2>&1
  if ( cd "$D" && git clone -q --depth 1 "file://$D/src" shallow ) >/dev/null 2>&1; then
    cp "$PCG" "$D/shallow/scripts/" 2>/dev/null
    cp "$REPO_ROOT/scripts/lib/helpers.sh" "$REPO_ROOT/scripts/lib/helpers-core.sh" \
       "$REPO_ROOT/scripts/lib/helpers-full.sh" "$REPO_ROOT/scripts/lib/tdd-classify.sh" \
       "$LIB" "$D/shallow/scripts/lib/" 2>/dev/null
    ( cd "$D/shallow" && git config user.email "wp3@test.invalid" && git config user.name "WP3 Test" ) >/dev/null 2>&1
    atk_report "T7f [shallow clone, anchor object absent]" "$D/shallow" blocked
  else
    fail_ "T7f" "shallow clone fixture could not be built"
  fi
fi

# ── T7g — a SECOND adoption stamp (re-stamp silently moving the anchor) ────
D="$(newtmp)/p"
if ! atk_base "$D"; then fail_ "T7g" "fixture setup failed"; else
  before=$( cd "$D" && jq -r '.adoption.adoptedAtCommit' .claude/manifest.json )
  restamp_rc=0
  ( cd "$D" && soif_adoption_stamp ".claude/manifest.json" "completed" 3 '[]' '[]' '[]' '[]' "sha2" ) >/dev/null 2>&1 || restamp_rc=$?
  after=$( cd "$D" && jq -r '.adoption.adoptedAtCommit' .claude/manifest.json )
  atk_report "T7g [second adoption stamp]" "$D" blocked
  if [ "$restamp_rc" -ne 0 ] && [ "$before" = "$after" ]; then
    pass "T7g-stamp: the re-stamp itself was REFUSED (rc $restamp_rc) and the anchor did not move — §8.5's 'written once, never re-stamped' is enforced, not merely asserted"
  else
    fail_ "T7g-stamp" "restamp_rc=$restamp_rc (want non-zero) anchor_before=$before anchor_after=$after (want equal)"
  fi
fi

# ── T7h — working-copy anchor tamper (no commit needed) ────────────────────
D="$(newtmp)/p"
if ! atk_base "$D"; then fail_ "T7h" "fixture setup failed"; else
  head_sha=$( cd "$D" && git rev-parse HEAD )
  ( cd "$D" && jq --arg h "$head_sha" '.adoption.adoptedAtCommit = $h' .claude/manifest.json > m.tmp && mv m.tmp .claude/manifest.json ) >/dev/null 2>&1
  atk_report "T7h [working-copy anchor tampered to HEAD]" "$D" blocked
fi

# ── T7i — detached HEAD at the adoption commit ─────────────────────────────
D="$(newtmp)/p"
if ! atk_base "$D"; then fail_ "T7i" "fixture setup failed"; else
  ( cd "$D" && git checkout -q --detach HEAD ) >/dev/null 2>&1
  atk_report "T7i [detached HEAD at the adoption commit]" "$D" blocked
fi

# ── T7j — a pre-adoption branch that has since MERGED adopted main ─────────
D="$(newtmp)/p"
if ! mk_tdd_proj "$D"; then fail_ "T7j" "fixture setup failed"; else
  ( cd "$D" && git branch feature ) >/dev/null 2>&1
  adopt_proj "$D" >/dev/null 2>&1
  ( cd "$D" && git add -A .claude && git commit -q -m "chore: adopt project" ) >/dev/null 2>&1
  mainref=$( cd "$D" && git rev-parse --abbrev-ref HEAD )
  ( cd "$D" && git checkout -q feature && git merge -q --no-edit "$mainref" ) >/dev/null 2>&1
  atk_report "T7j [pre-adoption branch after merging adopted main]" "$D" blocked
fi

echo "  [rc table] $ATK_RCS"

echo ""
echo "=== T8 — each conjunct of the corrected bound is load-bearing ==="
# T4 mutates the WHOLE bound line, which proves the line matters but not that
# BOTH halves do. A two-conjunct predicate needs two proofs, or one half can be
# dead code that nothing would notice — and a dead conjunct here is a reopened
# hole. Each mutation below deletes exactly ONE conjunct from the single
# `# BF-ADOPT-BOUND` line and pairs it with the fixture that ONLY that conjunct
# defends, plus the unmutated control on the same fixture.

# ── T8a — drop conjunct 2 (the committed witness) ──────────────────────────
# Fixture: the working-copy anchor tamper. anchor == HEAD, so conjunct 1 lets it
# through; only "HEAD's committed manifest is already adopted" refuses it.
T8A="$(newtmp)"; T8AD="$T8A/p"
if ! atk_base "$T8AD"; then fail_ "T8a" "fixture setup failed"; else
  h=$( cd "$T8AD" && git rev-parse HEAD )
  ( cd "$T8AD" && jq --arg h "$h" '.adoption.adoptedAtCommit = $h' .claude/manifest.json > m.tmp && mv m.tmp .claude/manifest.json ) >/dev/null 2>&1
  _atk_split "$(atk_verdict "$T8AD")"; ctl_rc="$ATK_RC"; ctl_reason="$ATK_REASON"
  MUT8A="$T8AD/scripts/lib/adoption-stamp.sh"
  bound_sites=$(grep -c 'BF-ADOPT-BOUND$' "$LIB" 2>/dev/null); bound_sites=$(_num "$bound_sites")
  cp "$LIB" "$T8A/orig-lib.ref"
  _sed_inplace "$MUT8A" 's|^.*BF-ADOPT-BOUND$|  if [ "$anchor" != "$head" ]; then   # BF-ADOPT-BOUND|'
  chg8a=$(_changed_lines "$T8A/orig-lib.ref" "$MUT8A")
  p8a=$(_parses "$MUT8A")
  ( cd "$T8AD" && git reset -q ) >/dev/null 2>&1
  _atk_split "$(atk_verdict "$T8AD")"; mut_rc="$ATK_RC"; mut_banner="$ATK_BANNER"
  if [ "$ctl_rc" -ne 0 ] && [ "$ctl_reason" -eq 1 ] && [ "$mut_rc" -eq 0 ] && [ "$mut_banner" -eq 1 ] \
     && [ "$chg8a" -eq 2 ] && [ "$bound_sites" -eq 1 ] && [ "$p8a" -eq 1 ]; then
    pass "T8a: dropping the COMMITTED-WITNESS conjunct (1 line, mutant parses) lets a tampered anchor exempt a post-adoption commit (rc 0, banner); the unmutated control blocks BY the BL-072 gate (rc $ctl_rc) — conjunct 2 is load-bearing"
  else
    fail_ "T8a" "control_rc=$ctl_rc (want non-zero) control_blocked_by_gate=$ctl_reason (want 1) mutant_rc=$mut_rc (want 0) mutant_banner=$mut_banner (want 1) changed_lines=$chg8a (want 2) bound_sites=$bound_sites (want 1) parses=$p8a (want 1)"
  fi
fi

# ── T8b — drop conjunct 1 (anchor == HEAD) ─────────────────────────────────
# Fixture: the stamp is written, then an UNRELATED commit lands (src only, the
# manifest still uncommitted). anchor != HEAD, but HEAD's committed manifest is
# not adopted — so only conjunct 1 refuses. Without it every commit after the
# stamp stays exempt until the manifest is finally committed.
T8B="$(newtmp)"; T8BD="$T8B/p"
if ! mk_tdd_proj "$T8BD"; then fail_ "T8b" "fixture setup failed"; else
  adopt_proj "$T8BD" >/dev/null 2>&1
  ( cd "$T8BD" && mkdir -p src && echo 'export const a=1;' > src/unrelated.js \
      && git add src/unrelated.js && git commit -q -m "chore: unrelated work" ) >/dev/null 2>&1
  _atk_split "$(atk_verdict "$T8BD")"; ctl_rc="$ATK_RC"; ctl_reason="$ATK_REASON"
  MUT8B="$T8BD/scripts/lib/adoption-stamp.sh"
  cp "$LIB" "$T8B/orig-lib.ref"
  _sed_inplace "$MUT8B" 's|^.*BF-ADOPT-BOUND$|  if _soif_adoption_head_copy_adopted "$manifest"; then   # BF-ADOPT-BOUND|'
  chg8b=$(_changed_lines "$T8B/orig-lib.ref" "$MUT8B")
  p8b=$(_parses "$MUT8B")
  ( cd "$T8BD" && git reset -q ) >/dev/null 2>&1
  _atk_split "$(atk_verdict "$T8BD")"; mut_rc="$ATK_RC"; mut_banner="$ATK_BANNER"
  if [ "$ctl_rc" -ne 0 ] && [ "$ctl_reason" -eq 1 ] && [ "$mut_rc" -eq 0 ] && [ "$mut_banner" -eq 1 ] \
     && [ "$chg8b" -eq 2 ] && [ "$p8b" -eq 1 ]; then
    pass "T8b: dropping the anchor==HEAD conjunct (1 line, mutant parses) exempts a commit made AFTER the stamp on a still-uncommitted manifest (rc 0, banner); the unmutated control blocks BY the BL-072 gate (rc $ctl_rc) — conjunct 1 is load-bearing"
  else
    fail_ "T8b" "control_rc=$ctl_rc (want non-zero) control_blocked_by_gate=$ctl_reason (want 1) mutant_rc=$mut_rc (want 0) mutant_banner=$mut_banner (want 1) changed_lines=$chg8b (want 2) parses=$p8b (want 1)"
  fi
fi

echo ""
echo "=== G — stamp acceptance in the gate + the loss detector ==="

# mk_gate_proj DIR — a project check-phase-gate.sh will actually evaluate.
mk_gate_proj() {
  local d="$1"
  mkdir -p "$d/.claude" "$d/scripts/lib" "$d/docs"
  ( cd "$d" \
      && git init -q \
      && git config user.email "wp3g@test.invalid" \
      && git config user.name  "WP3 Gate Test" ) || return 1
  printf '%s\n' '{"current_phase":0,"track":"light","deployment":"personal","poc_mode":null,"gates":{}}' > "$d/.claude/phase-state.json"
  printf '%s\n' '# Approval Log' > "$d/APPROVAL_LOG.md"
  printf '%s\n' '{"frameworkVersion":"test","host":"other","mode":"personal"}' > "$d/.claude/manifest.json"
  cp "$GATE" "$d/scripts/"
  cp "$REPO_ROOT/scripts/lib/helpers.sh" \
     "$REPO_ROOT/scripts/lib/helpers-core.sh" \
     "$REPO_ROOT/scripts/lib/helpers-full.sh" \
     "$LIB" "$d/scripts/lib/"
  chmod +x "$d/scripts/check-phase-gate.sh"
}

run_gate() { ( cd "$1" && bash scripts/check-phase-gate.sh 2>&1 ); }

# ── G1 — intact adoption ⇒ no finding (baseline parity) ────────────────────
G1D="$(newtmp)/p"
if ! mk_gate_proj "$G1D"; then
  fail_ "G1" "fixture setup failed"
else
  g1_base_out=$(run_gate "$G1D"); g1_base_rc=$?
  ( cd "$G1D" && soif_adoption_stamp ".claude/manifest.json" "completed" 0 '[]' '[]' '[]' '[]' "sha" ) >/dev/null 2>&1
  ( cd "$G1D" && git add -A && git commit -q -m "chore: adopt" ) >/dev/null 2>&1
  g1_out=$(run_gate "$G1D"); g1_rc=$?
  if [ "$g1_rc" -eq "$g1_base_rc" ] && [ "$g1_rc" -eq 0 ]; then
    pass "G1: an adopted project with an INTACT stamp exits exactly as the unadopted control (rc $g1_rc) — the arm adds no finding when nothing is wrong"
  else
    fail_ "G1" "adopted_rc=$g1_rc unadopted_control_rc=$g1_base_rc (want both 0)"
  fi
fi

# ── G2 — the stamp is committed at HEAD but gone from the working tree ─────
G2D="$(newtmp)/p"
if ! mk_gate_proj "$G2D"; then
  fail_ "G2" "fixture setup failed"
else
  ( cd "$G2D" && soif_adoption_stamp ".claude/manifest.json" "completed" 0 '[]' '[]' '[]' '[]' "sha" ) >/dev/null 2>&1
  ( cd "$G2D" && git add -A && git commit -q -m "chore: adopt" ) >/dev/null 2>&1
  # Simulate the wholesale regeneration: an upstream key set with no Solo keys.
  printf '%s\n' '{"frameworkVersion":"9","frameworkRepo":"kraulerson/claude-dev-framework","files":{}}' > "$G2D/.claude/manifest.json"
  g2_out=$(run_gate "$G2D"); g2_rc=$?
  g2_named=0
  printf '%s' "$g2_out" | grep -q 'adoption' && g2_named=1
  if [ "$g2_rc" -ne 0 ] && [ "$g2_named" -eq 1 ]; then
    pass "G2: a manifest regenerated without the adoption block makes the gate exit NON-ZERO (rc $g2_rc) and the report names the loss — detected, not prevented"
  else
    fail_ "G2" "rc=$g2_rc (want non-zero) loss_reported=$g2_named (want 1)"
  fi
fi

# ── G3 — MUTATION: remove the detection ⇒ the project SILENTLY un-adopts ───
# Expected mutant result is an ABSENCE, so the discriminators matter: the
# mutant gate must still RUN to completion (it prints its own consistency
# verdict) and the mutant library must still answer the accessor.
G3R="$(newtmp)"; G3D="$G3R/p"
if ! mk_gate_proj "$G3D"; then
  fail_ "G3" "fixture setup failed"
else
  ( cd "$G3D" && soif_adoption_stamp ".claude/manifest.json" "completed" 0 '[]' '[]' '[]' '[]' "sha" ) >/dev/null 2>&1
  ( cd "$G3D" && git add -A && git commit -q -m "chore: adopt" ) >/dev/null 2>&1
  printf '%s\n' '{"frameworkVersion":"9","frameworkRepo":"kraulerson/claude-dev-framework","files":{}}' > "$G3D/.claude/manifest.json"
  MUT3="$G3D/scripts/lib/adoption-stamp.sh"
  det_sites=$(grep -c 'BF-ADOPT-LOSS-DETECT$' "$LIB" 2>/dev/null); det_sites=$(_num "$det_sites")
  cp "$LIB" "$G3R/orig-lib.ref"
  _sed_inplace "$MUT3" 's|^.*BF-ADOPT-LOSS-DETECT$|  return 1   # BF-ADOPT-LOSS-DETECT|'
  chg3=$(_changed_lines "$G3R/orig-lib.ref" "$MUT3")
  p3=$(_parses "$MUT3")
  g3_out=$(run_gate "$G3D"); g3_rc=$?
  d3_ran=0
  printf '%s' "$g3_out" | grep -q 'Phase gates consistent' && d3_ran=1
  d3_load=0
  ( . "$MUT3" && ! soif_adoption_adopted "$G3D/.claude/manifest.json" ) >/dev/null 2>&1 && d3_load=1
  if [ "$g3_rc" -eq 0 ] && [ "$chg3" -eq 2 ] && [ "$det_sites" -eq 1 ] && [ "$p3" -eq 1 ] \
     && [ "$d3_ran" -eq 1 ] && [ "$d3_load" -eq 1 ]; then
    pass "G3 (mutation): with the post-regeneration detection removed (1 line), the project SILENTLY un-adopts — the gate exits 0 on the same fixture G2 blocks; the mutant gate still ran to its own verdict and the mutant library still loads"
  else
    fail_ "G3" "rc=$g3_rc (want 0) changed_lines=$chg3 (want 2) detect_anchor_sites=$det_sites (want 1) mutant_parses=$p3 (want 1) gate_ran_to_verdict=$d3_ran (want 1) mutant_lib_loads=$d3_load (want 1)"
  fi
fi

# ── G4 — mid-adoption: the stamp is not committed yet ⇒ no false alarm ─────
G4D="$(newtmp)/p"
if ! mk_gate_proj "$G4D"; then
  fail_ "G4" "fixture setup failed"
else
  ( cd "$G4D" && git add -A && git commit -q -m "chore: their history" ) >/dev/null 2>&1
  ( cd "$G4D" && soif_adoption_stamp ".claude/manifest.json" "in-flight" 0 '[]' '[]' '[]' '[]' "sha" ) >/dev/null 2>&1
  g4_out=$(run_gate "$G4D"); g4_rc=$?
  if [ "$g4_rc" -eq 0 ]; then
    pass "G4: a mid-adoption project (stamp written, not yet committed) raises NO loss finding — rc 0"
  else
    fail_ "G4" "rc=$g4_rc (want 0) — false alarm before the adoption commit lands"
  fi
fi

# ── G5 — no FALSE ALARM from a subdirectory ────────────────────────────────
# `git show HEAD:<p>` resolves from the REPO ROOT; `[ -f <p> ]` resolves from
# the CWD. Off-root those name different files, and the mismatch reads exactly
# like "committed but missing from the working tree". A false FAIL is the
# failure direction this repo has already paid for twice, so the guard against
# it gets its own pin rather than riding on the happy path.
G5D="$(newtmp)/p"
if ! mk_gate_proj "$G5D"; then
  fail_ "G5" "fixture setup failed"
else
  ( cd "$G5D" && soif_adoption_stamp ".claude/manifest.json" "completed" 0 '[]' '[]' '[]' '[]' "sha" ) >/dev/null 2>&1
  ( cd "$G5D" && git add -A && git commit -q -m "chore: adopt" ) >/dev/null 2>&1
  mkdir -p "$G5D/src/deep"
  g5_root_lost=0
  ( cd "$G5D" && soif_adoption_integrity_lost ".claude/manifest.json" ) >/dev/null 2>&1 && g5_root_lost=1
  g5_sub_lost=0
  ( cd "$G5D/src/deep" && soif_adoption_integrity_lost ".claude/manifest.json" ) >/dev/null 2>&1 && g5_sub_lost=1
  if [ "$g5_root_lost" -eq 0 ] && [ "$g5_sub_lost" -eq 0 ]; then
    pass "G5: an intact adopted project reports no loss from the repo root AND none from a subdirectory — the off-root path mismatch cannot manufacture a false FAIL"
  else
    fail_ "G5" "loss_at_root=$g5_root_lost (want 0) loss_in_subdir=$g5_sub_lost (want 0)"
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
