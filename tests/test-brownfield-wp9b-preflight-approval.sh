#!/usr/bin/env bash
# tests/test-brownfield-wp9b-preflight-approval.sh
#
# Brownfield adoption WP9b — A1's THREE-ARM RE-ADOPTION PREFLIGHT and A4's
# APPROVAL_LOG.md.
# Design: docs/designs/2026-08-23-brownfield-adoption-v2.md §8.2 step 0 (the
# preflight and why it is before the tier question), §8.2 step 7 (the log
# FIRST), §8.3a-A1, §8.3a-A4, §10-WP9.
#
# ── WHAT THIS FILE ASSERTS ON ───────────────────────────────────────────────
# A VERDICT by exit code; a STATE CHANGE by reading the state; CONTENT by the
# content. Never a printed label — and for the preflight, DELIBERATELY never
# the refusal's wording, because that is what made A1's defect survivable:
# arms 1 and 3 both refuse a stamped tree with near-identical text, so a
# text assertion goes green against a build that dropped arm 1 entirely.
#
# ── THE TWO MUTANTS THAT EXIT ZERO ──────────────────────────────────────────
# Arms 2 and 3 each guard a tree that adoption would otherwise complete on,
# at rc 0. So NEITHER of their assertions may key on a non-zero exit: they
# assert the REFUSAL happened and the TREE IS UNCHANGED. Arm 1's mutant does
# exit 1 (the restamp refusal fires late), which is exactly why its assertion
# reads the REVERTED STATE instead — a late refusal is still a refusal, and
# the damage is already on disk by then.
#
# ── WHY ARM 3 CARRIES A `not adopted` CONJUNCT ──────────────────────────────
# A stamped tree necessarily has a `.claude/phase-state.json`, so an arm 3
# spelled only as "phase-state present" catches arm 1's fixture too, and
# dropping arm 1 changes nothing observable — the mutation stays green
# forever. Arm 3 is the "already framework-managed but NOT adopted" arm and
# the conjunct is what makes arm 1's mutation discriminate. PM1 is the assertion
# that pins it: strip either conjunct and PM1 goes red (measured).
#
# ── MUTATION HARNESS STANDARD (inherited from the WP4/WP9a suites) ──────────
#   • anchored end-of-line markers, excised with `s|^.*MARKER$|…|`;
#   • the anchor asserted at sites==1 in its OWN shipped source;
#   • every mutant additionally asserts `bash -n`;
#   • a MODE-PRESERVING in-place edit;
#   • a FRESH fixture per scenario, from mktemp -d;
#   • mutants run against a framework MIRROR — the tree under test is never
#     edited, so a failure here cannot leave this repository mutated.
#
# Hermetic: temp dirs only, no network, no remote creation.
#
# LANE NOTE. mk_mirror below NAMES init.sh, which is the exemption predicate
# `# BL-181-UNIT-LANE-PREDICATE` reads — but this suite only READS that file
# (and renders a template beside it), never runs it, so it belongs in the fast
# unit lane and is registered there.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRIVER="$REPO_ROOT/scripts/adopt-project.sh"
LIB_DIR="$REPO_ROOT/scripts/lib/adopt"
L_STATE="$LIB_DIR/adopt-state.sh"
TMPL_ORG="$REPO_ROOT/templates/generated/approval-log-org.tmpl"
TMPL_PERSONAL="$REPO_ROOT/templates/generated/approval-log-personal.tmpl"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }

_mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || printf '?\n'; }
_num() { case "$1" in ''|null|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac }
_parses() { bash -n "$1" >/dev/null 2>&1 && printf '1\n' || printf '0\n'; }
_sites() { local n; n=$(grep -c "$2\$" "$1" 2>/dev/null); _num "$n"; }

_sed_inplace() {
  local file="$1" expr="$2" tmp mode
  mode="$(_mode_of "$file")"
  tmp="$(mktemp)"
  sed "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
  [ "$mode" != "?" ] && chmod "$mode" "$file" 2>/dev/null
  return 0
}

_changed_lines() {
  local n
  n=$(diff "$1" "$2" 2>/dev/null | grep -c '^[<>]')
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s\n' "$n"
}

# ── THE TREE HASH, AND WHY IT INCLUDES UNTRACKED FILES ──────────────────────
# Arms 2 and 3 are proven by "the tree did not change". A hash over `git
# ls-files` alone would MISS the entire damage: the framework install writes
# ~68 UNTRACKED files, the archive directory is untracked until the commit,
# and a mutant that adopts the tree would therefore hash identical to one that
# refused. Content is hashed, not just names, because `phase-state.json` is
# overwritten in place at a path that already existed.
_tree_hash() {
  local p="$1"
  ( cd "$p" 2>/dev/null && find . -path ./.git -prune -o -type f -print 2>/dev/null \
      | LC_ALL=C sort \
      | while IFS= read -r f; do
          printf '%s ' "$f"
          (shasum -a 256 "$f" 2>/dev/null || sha256sum "$f" 2>/dev/null || printf 'nohash\n') | awk '{print $1}'
        done ) | (shasum -a 256 2>/dev/null || sha256sum 2>/dev/null) | awk '{print $1}'
}

_json_str() {  # _json_str <file> <jq-filter>
  jq -r "$2 // \"\"" "$1" 2>/dev/null || printf '\n'
}

if [ ! -f "$DRIVER" ]; then
  echo "  [FAIL] setup — $DRIVER not found"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "  [FAIL] setup — jq is required by this suite"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

# ── Fixtures ────────────────────────────────────────────────────────────────
mk_adoptee() {
  local p="$1"
  mkdir -p "$p/src" "$p/docs" || return 1
  ( cd "$p" \
      && git init -q . \
      && git config user.email "wp9b@test.invalid" \
      && git config user.name  "WP9b Test" \
      && git config core.excludesFile /dev/null ) >/dev/null 2>&1 || return 1
  printf '{"name":"acme-api","scripts":{"test":"npm test"}}\n' > "$p/package.json"
  printf '# acme-api\n' > "$p/README.md"
  printf '# What this is for\n\nInvoice reconciliation for small firms.\n' > "$p/docs/product.md"
  printf '# Architecture\n\nA node service and a postgres database.\n' > "$p/docs/architecture.md"
  ( cd "$p" && git add -A && git commit -q -m "chore: their own history" ) >/dev/null 2>&1 || return 1
  return 0
}

TEMPLATE="$(newtmp)/template"
REPORT=""
REPORT_OK=0
if mk_adoptee "$TEMPLATE"; then
  if bash "$REPO_ROOT/scripts/scout.sh" --root "$TEMPLATE" --out "$TOPTMP/scan" >/dev/null 2>&1; then
    REPORT="$TOPTMP/scan/scout-report.json"
    [ -s "$REPORT" ] && REPORT_OK=1
  fi
fi
if [ "$REPORT_OK" -ne 1 ]; then
  echo "  [FAIL] setup — scripts/scout.sh produced no report"
  echo ""
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

# Five answers: the tier question plus this report's four scan-derived
# confirmations (A7). Inherited from the WP9a suite, where the LENGTH is
# documented as load-bearing; here it only has to be long enough to complete.
_ans() { local tier="${1:-1}"; printf '%s\n1\n1\n1\n1\n' "$tier"; }

RUN_RC=0; RUN_OUT=""; RUN_ERR=""
run_adopt() {
  local dir="$1" answers="$2" report="$3" fw="${4:-$REPO_ROOT}"
  RUN_RC=0
  RUN_OUT="$(dirname "$answers")/run-out"
  RUN_ERR="$(dirname "$answers")/run-err"
  ( cd "$dir" && bash "$fw/scripts/adopt-project.sh" --scan-report "$report" ) \
    < "$answers" > "$RUN_OUT" 2> "$RUN_ERR" || RUN_RC=$?
  return 0
}

mk_mirror() {
  local m="$1"
  mkdir -p "$m" || return 1
  cp -Rp "$REPO_ROOT/scripts" "$m/" || return 1
  cp -Rp "$REPO_ROOT/templates" "$m/" || return 1
  cp -p "$REPO_ROOT/init.sh" "$m/" || return 1
  return 0
}

GATE_RC=0; GATE_OUT=""
gate_in() {
  local dir="$1"; shift
  GATE_RC=0
  GATE_OUT="$TOPTMP/gate-out-$$-$RANDOM"
  ( cd "$dir" && bash scripts/check-phase-gate.sh "$@" ) > "$GATE_OUT" 2>&1 || GATE_RC=$?
  return 0
}

# `_adopted_fixture <dir>` — a completed Act 2 at its natural resting state.
_adopted_fixture() {
  local w="$1"
  mkdir -p "$w/p" || return 1
  mk_adoptee "$w/p" || return 1
  _ans 1 > "$w/answers"
  run_adopt "$w/p" "$w/answers" "$REPORT"
  [ "$RUN_RC" -eq 0 ] || return 1
  return 0
}

echo "=== P — A1's three-arm re-adoption preflight (§8.2 step 0) ==="

# The tier question's own text, hoisted because three sections key on "was the
# operator re-interrogated?" — the property §8.2 step 0 exists to guarantee.
P4_Q="Who is this project for?"

# ── ARM 1 — an ADOPTED tree, HAND-ADVANCED. ────────────────────────────────
# THE STARTING STATE IS THE PROOF. At the natural resting state — phase 0 with
# null gate dates — a mutant that reverts the project to phase 0 with null
# gates produces a state IDENTICAL to the one it started in, so the revert is
# invisible and the mutation is green forever. Advancing the fixture by hand
# first is what makes the damage observable.
P1="$(newtmp)"
P1_OK=0
if _adopted_fixture "$P1"; then
  jq '.current_phase = 2
      | .gates.phase_0_to_1 = "2026-01-05"
      | .gates.phase_1_to_2 = "2026-02-09"' \
     "$P1/p/.claude/phase-state.json" > "$P1/ps.new" 2>/dev/null \
    && mv "$P1/ps.new" "$P1/p/.claude/phase-state.json" \
    && ( cd "$P1/p" && git add -A && git commit -q -m "chore: earned two gates" ) >/dev/null 2>&1 \
    && P1_OK=1
fi

if [ "$P1_OK" -ne 1 ]; then
  fail_ "P setup (arm 1 fixture)" "could not build a hand-advanced adopted fixture"
else
  P1_PHASE_BEFORE="$(_json_str "$P1/p/.claude/phase-state.json" '.current_phase')"
  P1_G1_BEFORE="$(_json_str "$P1/p/.claude/phase-state.json" '.gates.phase_0_to_1')"
  P1_HASH_BEFORE="$(_tree_hash "$P1/p")"

  _ans 1 > "$P1/answers2"
  run_adopt "$P1/p" "$P1/answers2" "$REPORT"
  P1_RC="$RUN_RC"
  P1_PHASE_AFTER="$(_json_str "$P1/p/.claude/phase-state.json" '.current_phase')"
  P1_G1_AFTER="$(_json_str "$P1/p/.claude/phase-state.json" '.gates.phase_0_to_1')"
  P1_HASH_AFTER="$(_tree_hash "$P1/p")"

  [ "$P1_RC" -ne 0 ] \
    && pass "P1 — a second adoption of an adopted tree REFUSES (rc $P1_RC)" \
    || fail_ "P1" "the second run exited 0 on an already-adopted tree"

  # The load-bearing one. Not the wording — the STATE.
  if [ "$P1_PHASE_AFTER" = "$P1_PHASE_BEFORE" ] && [ "$P1_G1_AFTER" = "$P1_G1_BEFORE" ]; then
    pass "P1b — the hand-advanced state SURVIVES (phase $P1_PHASE_AFTER, gate $P1_G1_AFTER)"
  else
    fail_ "P1b" "state was clobbered: phase $P1_PHASE_BEFORE->$P1_PHASE_AFTER, gate '$P1_G1_BEFORE'->'$P1_G1_AFTER'"
  fi

  [ "$P1_HASH_AFTER" = "$P1_HASH_BEFORE" ] \
    && pass "P1c — the tree is byte-identical after the refusal" \
    || fail_ "P1c" "the refused run still changed the tree"
fi

# ── ARM 2 — an UNSTAMPED tree carrying a PRIOR archive. ────────────────────
# The fixture must carry NO phase-state.json and NO manifest.json — an
# interrupted run that died before the state stage — or arm 3 catches it too
# and this mutation proves nothing.
P2="$(newtmp)"
mkdir -p "$P2/p"
P2_OK=0
if mk_adoptee "$P2/p"; then
  mkdir -p "$P2/p/.claude/adoption-archive/2026-01-01T00-00-00Z-1234/.claude"
  printf '{"a":1}\n' > "$P2/p/.claude/adoption-archive/2026-01-01T00-00-00Z-1234/.claude/settings.json"
  printf '{"entries":[]}\n' > "$P2/p/.claude/adoption-archive/2026-01-01T00-00-00Z-1234/MANIFEST.json"
  ( cd "$P2/p" && git add -A && git commit -q -m "chore: an interrupted first run" ) >/dev/null 2>&1 && P2_OK=1
fi

if [ "$P2_OK" -ne 1 ]; then
  fail_ "P setup (arm 2 fixture)" "could not build a prior-archive fixture"
else
  # Positive control on the fixture's own shape: if either of these files
  # existed, arm 3 would be the arm under test and P2M would prove nothing.
  if [ ! -f "$P2/p/.claude/phase-state.json" ] && [ ! -f "$P2/p/.claude/manifest.json" ]; then
    pass "P2ctl — the arm 2 fixture carries neither phase-state nor manifest (so arm 3 cannot mask it)"
  else
    fail_ "P2ctl" "the arm 2 fixture is also an arm 3 fixture; its mutation would prove nothing"
  fi

  P2_HASH_BEFORE="$(_tree_hash "$P2/p")"
  _ans 1 > "$P2/answers"
  run_adopt "$P2/p" "$P2/answers" "$REPORT"
  P2_RC="$RUN_RC"
  P2_HASH_AFTER="$(_tree_hash "$P2/p")"
  P2_ERR="$(cat "$RUN_ERR" 2>/dev/null)"
  P2_ALL="$(cat "$RUN_OUT" "$RUN_ERR" 2>/dev/null)"

  [ "$P2_RC" -ne 0 ] \
    && pass "P2 — an unstamped tree with a prior archive REFUSES (rc $P2_RC)" \
    || fail_ "P2" "adoption completed over a prior archive"

  [ "$P2_HASH_AFTER" = "$P2_HASH_BEFORE" ] \
    && pass "P2b — the tree is byte-identical after the refusal" \
    || fail_ "P2b" "the refused run still changed the tree"

  # The design requires arm 2 to NAME the directory: its recovery is that
  # archive's own restore lines, and a refusal that does not say where they
  # are sends the operator looking.
  case "$P2_ALL" in
    *".claude/adoption-archive/2026-01-01T00-00-00Z-1234"*)
      pass "P2c — the refusal names the prior archive directory" ;;
    *) fail_ "P2c" "the refusal did not name .claude/adoption-archive/2026-01-01T00-00-00Z-1234" ;;
  esac
fi

# ── ARM 3 — a SCAFFOLDED GREENFIELD tree. ──────────────────────────────────
# Arms 1 and 2 are both silent here: no `.adoption` to read, and the archive
# this run would create is not a PRIOR one. Shipped v1 refused this tree via
# `adopt_install_framework`'s `n_copied -eq 0` tripwire, which D1 unreaches —
# so without arm 3 the run archives the scaffold's OWN framework files as the
# operator's, overwrites gate-earned state, stamps it and commits at EXIT 0.
P3="$(newtmp)"
mkdir -p "$P3/p"
P3_OK=0
if mk_adoptee "$P3/p"; then
  mkdir -p "$P3/p/.claude"
  printf '{"current_phase":2,"gates":{"phase_0_to_1":"2026-03-02","phase_1_to_2":"2026-04-08"}}\n' \
    > "$P3/p/.claude/phase-state.json"
  printf '{"version":"1.0.0","deployment":"personal"}\n' > "$P3/p/.claude/manifest.json"
  ( cd "$P3/p" && git add -A && git commit -q -m "chore: scaffolded by init.sh" ) >/dev/null 2>&1 && P3_OK=1
fi

if [ "$P3_OK" -ne 1 ]; then
  fail_ "P setup (arm 3 fixture)" "could not build a scaffolded-greenfield fixture"
else
  # Positive control: this fixture is NOT adopted, so arm 1 is genuinely
  # silent on it and arm 3 is the only arm that can refuse.
  if jq -e '.adoption.adopted == true' "$P3/p/.claude/manifest.json" >/dev/null 2>&1; then
    fail_ "P3ctl" "the arm 3 fixture is stamped; arm 1 would refuse it and this proves nothing"
  else
    pass "P3ctl — the arm 3 fixture is framework-managed but NOT adopted"
  fi

  P3_PHASE_BEFORE="$(_json_str "$P3/p/.claude/phase-state.json" '.current_phase')"
  P3_HASH_BEFORE="$(_tree_hash "$P3/p")"
  _ans 1 > "$P3/answers"
  run_adopt "$P3/p" "$P3/answers" "$REPORT"
  P3_RC="$RUN_RC"
  P3_PHASE_AFTER="$(_json_str "$P3/p/.claude/phase-state.json" '.current_phase')"
  P3_HASH_AFTER="$(_tree_hash "$P3/p")"

  [ "$P3_RC" -ne 0 ] \
    && pass "P3 — a scaffolded greenfield tree REFUSES (rc $P3_RC)" \
    || fail_ "P3" "adoption completed over a scaffolded greenfield project at exit $P3_RC"

  [ "$P3_PHASE_AFTER" = "$P3_PHASE_BEFORE" ] \
    && pass "P3b — its gate-earned phase survives (phase $P3_PHASE_AFTER)" \
    || fail_ "P3b" "gate-earned phase clobbered: $P3_PHASE_BEFORE -> $P3_PHASE_AFTER"

  [ "$P3_HASH_AFTER" = "$P3_HASH_BEFORE" ] \
    && pass "P3c — the tree is byte-identical after the refusal" \
    || fail_ "P3c" "the refused run still changed the tree"

  if jq -e '.adoption' "$P3/p/.claude/manifest.json" >/dev/null 2>&1; then
    fail_ "P3d" "the scaffolded project's manifest gained an .adoption block"
  else
    pass "P3d — the manifest gained no .adoption block"
  fi
fi

# ── The preflight runs BEFORE the tier question. ───────────────────────────
# §8.2's whole reason for putting it at step 0: a second run must neither
# re-interrogate the operator nor destroy what the first produced.
#
# A DRAFT OF THIS PROVED IT BY STARVATION — no answers on stdin, assert the
# run refuses — AND THAT ASSERTION WAS VACUOUS: a FIRST adoption with no
# answers refuses too, by starving at the tier question. It passed against the
# unmodified tree, before the preflight existed. The discriminator is not that
# the run refused; it is that THE QUESTION WAS NEVER ASKED. Pinned on the
# question constant, with a positive control proving the same probe SEES that
# question on a tree the preflight does not refuse.
P4="$(newtmp)"
if _adopted_fixture "$P4"; then
  : > "$P4/empty"
  run_adopt "$P4/p" "$P4/empty" "$REPORT"
  P4_ASKED=0
  grep -qF "$P4_Q" "$RUN_OUT" 2>/dev/null && P4_ASKED=1
  [ "$P4_ASKED" -eq 0 ] \
    && pass "P4 — a re-adoption never reaches the tier question (the preflight precedes it)" \
    || fail_ "P4" "the re-adoption asked the operator the tier question before refusing"
fi

P4C="$(newtmp)"
mkdir -p "$P4C/p"
if mk_adoptee "$P4C/p"; then
  : > "$P4C/empty"
  run_adopt "$P4C/p" "$P4C/empty" "$REPORT"
  if grep -qF "$P4_Q" "$RUN_OUT" 2>/dev/null; then
    pass "P4ctl — the same probe DOES see the tier question on a first adoption (P4 is not vacuous)"
  else
    fail_ "P4ctl" "the probe cannot see the tier question even on a first adoption; P4 proves nothing"
  fi
else
  fail_ "P4ctl setup" "could not build a fresh adoptee"
fi

# ── ARM 1's SECOND WITNESS — the committed copy. ───────────────────────────
# Arm 1 reads TWO witnesses and the commit message headlines the second, but a
# review mutation deleted it and EVERY PR-blocking suite stayed green while the
# mutant completed an adoption at exit 0 and destroyed gate-earned state. A
# mechanism a package advertises and no check proves is a mechanism that leaves
# by accident. This is that fixture: adopted, hand-advanced, and the
# `.adoption` block deleted from the WORKING COPY ONLY — which defeats
# `soif_adoption_adopted` AND the restamp refusal together, and is exactly what
# an operator "starting over" does.
P5="$(newtmp)"
P5_OK=0
if _adopted_fixture "$P5"; then
  jq '.current_phase = 2 | .gates.phase_0_to_1 = "2026-01-05"' \
     "$P5/p/.claude/phase-state.json" > "$P5/ps.new" 2>/dev/null \
    && mv "$P5/ps.new" "$P5/p/.claude/phase-state.json" \
    && rm -f "$P5/p/scripts/check-versions.sh" \
    && ( cd "$P5/p" && git add -A && git commit -q -m "chore: earned a gate, lost a script" ) >/dev/null 2>&1 \
    && jq 'del(.adoption)' "$P5/p/.claude/manifest.json" > "$P5/mf.new" 2>/dev/null \
    && mv "$P5/mf.new" "$P5/p/.claude/manifest.json" \
    && P5_OK=1
fi

if [ "$P5_OK" -ne 1 ]; then
  fail_ "P5 setup" "could not build the blanked-manifest fixture"
else
  # The control: the working copy must NOT look adopted, or arm 1's first
  # witness would answer and the second would never be reached.
  if jq -e '.adoption.adopted == true' "$P5/p/.claude/manifest.json" >/dev/null 2>&1; then
    fail_ "P5ctl" "the working copy still says adopted; the second witness is not under test"
  else
    pass "P5ctl — the working copy no longer says adopted (only HEAD's copy does)"
  fi

  P5_PHASE_BEFORE="$(_json_str "$P5/p/.claude/phase-state.json" '.current_phase')"
  _ans 1 > "$P5/answers2"
  run_adopt "$P5/p" "$P5/answers2" "$REPORT"
  P5_RC="$RUN_RC"
  P5_PHASE_AFTER="$(_json_str "$P5/p/.claude/phase-state.json" '.current_phase')"

  [ "$P5_RC" -ne 0 ] \
    && pass "P5 — a blanked working manifest still REFUSES on the committed witness (rc $P5_RC)" \
    || fail_ "P5" "blanking the working manifest let the adoption run again at exit 0"

  [ "$P5_PHASE_AFTER" = "$P5_PHASE_BEFORE" ] \
    && pass "P5b — the gate-earned phase survives it (phase $P5_PHASE_AFTER)" \
    || fail_ "P5b" "gate-earned phase destroyed: $P5_PHASE_BEFORE -> $P5_PHASE_AFTER"
fi

# ── ARM 3'S THIRD SIGNAL — the collision-free interrupted tree. ────────────
# This shape escaped ALL THREE arms: an adoption interrupted after the install
# on an adoptee with nothing to archive has no manifest, no phase-state and no
# archive either, so the operator was re-interrogated before the `n_copied`
# tripwire refused. The fix shipped one round with NO TEST — review excised it
# and all six PR-blocking adoption suites passed with identical scores.
#
# THE FIXTURE IS A REAL INTERRUPTED ADOPTION, never a hand-built tree: the
# first version of this arm's sibling was "verified" against a hand-created
# directory and measured the fixture instead of the install.
P6="$(newtmp)"
mkdir -p "$P6/p"
P6_OK=0
if mk_adoptee "$P6/p"; then
  _ans 1 > "$P6/answers"
  ( cd "$P6/p" && SOIF_ADOPT_HALT_AFTER=install \
      bash "$REPO_ROOT/scripts/adopt-project.sh" --scan-report "$REPORT" ) \
    < "$P6/answers" > "$P6/out1" 2> "$P6/err1" || true
  # The shape is only interesting if it really has none of the other signals.
  if [ ! -d "$P6/p/.claude/adoption-archive" ] && [ ! -f "$P6/p/.claude/phase-state.json" ] \
     && [ ! -f "$P6/p/.claude/manifest.json" ] && [ -f "$P6/p/scripts/check-phase-gate.sh" ]; then
    P6_OK=1
  fi
fi

if [ "$P6_OK" -ne 1 ]; then
  fail_ "P6ctl" "could not produce a collision-free interrupted tree (no archive, no phase-state, no manifest, framework installed)"
else
  pass "P6ctl — a REAL interrupted adoption with NONE of arms 1-2's signals and no .claude/ state"
  run_adopt "$P6/p" "$P6/answers" "$REPORT"
  P6_RC="$RUN_RC"
  [ "$P6_RC" -ne 0 ] \
    && pass "P6 — arm 3 refuses it on the installed framework (rc $P6_RC)" \
    || fail_ "P6" "the collision-free interrupted tree adopted again at exit 0"
  if grep -q 'already looks framework-managed' "$RUN_ERR" 2>/dev/null; then
    pass "P6b — it refuses for ARM 3's own reason, not the install tripwire's"
  else
    fail_ "P6b" "the refusal came from somewhere else; arm 3 did not fire"
  fi
  if grep -qF "$P4_Q" "$RUN_OUT" 2>/dev/null; then
    fail_ "P6c" "the operator was re-interrogated before the refusal — the step-0 promise is unmet"
  else
    pass "P6c — the operator is NOT re-asked the tier question"
  fi
fi

# ── P6d — THE CONTROL THAT MATTERS MORE THAN THE REFUSAL. ──────────────────
# A first cut keyed arm 3 on a SINGLE file (`scripts/check-phase-gate.sh`) and
# that false-refused an adoptee which legitimately vendors a script of its own
# at that path — it adopted cleanly before this package. A majority of the
# shipped set cannot be coincidence; one file can.
P6D="$(newtmp)"
mkdir -p "$P6D/p"
if ! mk_adoptee "$P6D/p"; then
  fail_ "P6d setup" "could not build the adoptee"
else
  mkdir -p "$P6D/p/scripts"
  printf '#!/usr/bin/env bash\n# our own, not the framework1s\n' > "$P6D/p/scripts/check-phase-gate.sh"
  ( cd "$P6D/p" && git add -A && git commit -q -m "chore: our own script at that path" ) >/dev/null 2>&1
  _ans 1 > "$P6D/answers"
  run_adopt "$P6D/p" "$P6D/answers" "$REPORT"
  [ "$RUN_RC" -eq 0 ] \
    && pass "P6d — an adoptee vendoring ONE file at a framework path still adopts (rc 0): arm 3 keys on a majority, not a coincidence" \
    || fail_ "P6d" "adoption refused (rc $RUN_RC) a project that adopted cleanly before this package"
fi

# ── P6e — THE THRESHOLD'S BOUNDARY, not just its extremes. ────────────────
# P6 pins 68/68 (must refuse) and P6d pins 1/68 (must not). ANY predicate
# satisfying those two survives — review demonstrated three that do: requiring
# unanimity (`n_present * 1`), shifting `-ge` to `-gt`, and dropping the
# `n_total -gt 0` guard all passed the whole suite. A rule pinned only at its
# extremes is a rule a later edit can narrow silently, which is this package's
# own recurring lesson. Pin the two sides OF THE BOUNDARY.
#
# The predicate is `n_present * 2 -ge n_total` — AT LEAST HALF, not a strict
# majority: at exactly half it refuses, and the fixtures below say so.
_plant_k() {   # _plant_k <adoptee> <k> — copy K real framework scripts in
  local p="$1" k="$2" n=0 rel
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    [ -f "$REPO_ROOT/$rel" ] || continue
    [ "$n" -ge "$k" ] && break
    mkdir -p "$p/$(dirname "$rel")" 2>/dev/null
    cp -p "$REPO_ROOT/$rel" "$p/$rel" 2>/dev/null && n=$((n + 1))
  done <<PLANT
$( . "$REPO_ROOT/scripts/lib/helpers-core.sh" >/dev/null 2>&1
   . "$REPO_ROOT/scripts/lib/scaffold-shipped-set.sh" >/dev/null 2>&1
   soif_parse_shipped_scripts "$REPO_ROOT/init.sh" "$REPO_ROOT/scripts" )
PLANT
  printf '%s\n' "$n"
}

P6E_TOTAL="$( . "$REPO_ROOT/scripts/lib/helpers-core.sh" >/dev/null 2>&1
              . "$REPO_ROOT/scripts/lib/scaffold-shipped-set.sh" >/dev/null 2>&1
              soif_parse_shipped_scripts "$REPO_ROOT/init.sh" "$REPO_ROOT/scripts" \
                | while IFS= read -r r; do [ -f "$REPO_ROOT/$r" ] && echo x; done | wc -l | tr -d ' ' )"
P6E_TOTAL="$(_num "$P6E_TOTAL")"
P6E_HALF=$(( (P6E_TOTAL + 1) / 2 ))
P6E_UNDER=$(( P6E_HALF - 1 ))

if [ "$P6E_TOTAL" -lt 4 ]; then
  fail_ "P6e setup" "derived install set is $P6E_TOTAL; too small to have a boundary"
else
  pass "P6ectl — the install set derives to $P6E_TOTAL, so the boundary sits at $P6E_HALF (at least half)"

  # AT the boundary: must refuse.
  P6EA="$(newtmp)"; mkdir -p "$P6EA/p"
  if mk_adoptee "$P6EA/p"; then
    k="$(_plant_k "$P6EA/p" "$P6E_HALF")"
    ( cd "$P6EA/p" && git add -A && git commit -q -m "chore: half the set" ) >/dev/null 2>&1
    _ans 1 > "$P6EA/answers"
    run_adopt "$P6EA/p" "$P6EA/answers" "$REPORT"
    if [ "$RUN_RC" -ne 0 ] && grep -q 'already looks framework-managed' "$RUN_ERR" 2>/dev/null; then
      pass "P6e — at the boundary ($k of $P6E_TOTAL) arm 3 REFUSES"
    else
      fail_ "P6e" "planted $k of $P6E_TOTAL and the run did not refuse on arm 3 (rc $RUN_RC)"
    fi
  else
    fail_ "P6e setup" "could not build the adoptee"
  fi

  # ONE BELOW the boundary: must adopt. This is the assertion that kills the
  # unanimity mutant and the `-gt` shift together.
  P6EB="$(newtmp)"; mkdir -p "$P6EB/p"
  if mk_adoptee "$P6EB/p"; then
    k="$(_plant_k "$P6EB/p" "$P6E_UNDER")"
    ( cd "$P6EB/p" && git add -A && git commit -q -m "chore: just under half" ) >/dev/null 2>&1
    _ans 1 > "$P6EB/answers"
    run_adopt "$P6EB/p" "$P6EB/answers" "$REPORT"
    if [ "$RUN_RC" -eq 0 ]; then
      pass "P6f — one below the boundary ($k of $P6E_TOTAL) it still ADOPTS: the rule is at-least-half, not unanimity"
    else
      fail_ "P6f" "planted $k of $P6E_TOTAL and adoption refused (rc $RUN_RC) — the threshold is narrower than documented"
    fi
  else
    fail_ "P6f setup" "could not build the adoptee"
  fi
fi

# ── P6g — THE `n_total -gt 0` GUARD. ──────────────────────────────────────
# Without it the predicate is `0 * 2 >= 0`, which is TRUE — so a framework root
# whose install set parses to NOTHING would make arm 3 refuse EVERY project,
# with the nonsense message "0 of the framework's own 0 scripts are already
# here". Review excised the guard and the whole suite stayed green, because
# every other fixture uses a complete root. The mirror below keeps the driver
# and its libs (the run has to be able to execute) and empties only what the
# parser reads, which is what drives n_total to zero.
P6G="$(newtmp)"
mkdir -p "$P6G/fw" "$P6G/p"
if ! mk_mirror "$P6G/fw" || ! mk_adoptee "$P6G/p"; then
  fail_ "P6g setup" "could not build the mirror or the adoptee"
else
  printf '#!/usr/bin/env bash\n# a framework root whose install set parses to nothing\n' > "$P6G/fw/init.sh"
  P6G_TOTAL="$( . "$REPO_ROOT/scripts/lib/helpers-core.sh" >/dev/null 2>&1
                . "$REPO_ROOT/scripts/lib/scaffold-shipped-set.sh" >/dev/null 2>&1
                soif_parse_shipped_scripts "$P6G/fw/init.sh" "$P6G/fw/scripts" 2>/dev/null | grep -c . )"
  P6G_TOTAL="$(_num "$P6G_TOTAL")"
  if [ "$P6G_TOTAL" -ne 0 ]; then
    fail_ "P6gctl" "the parse still yields $P6G_TOTAL entries; this fixture does not exercise the guard"
  else
    pass "P6gctl — the mirror's install set parses to 0 entries, so the guard is what is under test"
    _ans 1 > "$P6G/answers"
    run_adopt "$P6G/p" "$P6G/answers" "$REPORT" "$P6G/fw"
    if grep -q 'already looks framework-managed' "$RUN_ERR" 2>/dev/null; then
      fail_ "P6g" "arm 3 refused a FRESH adoptee because the install set was empty — 0*2 >= 0 is true and the guard is gone"
    else
      pass "P6g — a fresh adoptee is NOT refused by arm 3 when the install set is empty (rc $RUN_RC)"
    fi
  fi
fi

# ── P6h — THE INCOMPLETE FRAMEWORK ROOT, and the sibling that makes it work. ─
# Arm 3 asks "is the framework already here" and so does
# `adopt_install_framework`'s `n_copied` — TWO COPIES OF ONE PREDICATE in two
# functions, with nothing in the language binding them. Round 6 aligned them
# (both now skip entries whose SOURCE is absent); review reverted that and
# EVERY suite stayed green, so the fix was real and nothing held it there.
#
# The discriminating shape is a framework root that cannot install its whole
# set. Counting every PARSED line against an adoptee that holds every
# INSTALLABLE one scores below the threshold, arm 3 goes silent, and the run
# falls through to the tripwire — re-interrogating the operator and writing
# into the project, which step 0 exists to prevent.
#
# ASSERTED IN BOTH DIRECTIONS: the arm-3 refusal is present AND the tripwire
# text is ABSENT. Either alone is satisfiable by the wrong build.
P6H="$(newtmp)"
mkdir -p "$P6H/fw" "$P6H/p"
P6H_MARKS_OK=1
for m in "# BL-242-INSTALL-SET-KEY" "# BL-242-INSTALL-SET-KEY-SIBLING"; do
  n="$(_sites "$L_STATE" "$m")"
  [ "$n" = "1" ] || { fail_ "P6h-anchor" "'$m' occurs $n times (need exactly 1)"; P6H_MARKS_OK=0; }
done
[ "$P6H_MARKS_OK" -eq 1 ] && pass "P6h-anchor — both sync-sibling markers occur exactly once"

if ! mk_mirror "$P6H/fw" || ! mk_adoptee "$P6H/p"; then
  fail_ "P6h setup" "could not build the mirror or the adoptee"
else
  # Make the mirror INCOMPLETE: keep the libs the driver needs to run, drop the
  # top-level scripts, so parsed >> installable.
  find "$P6H/fw/scripts" -maxdepth 1 -type f -name '*.sh' ! -name 'adopt-project.sh' ! -name 'scout.sh' \
    -exec rm -f {} + 2>/dev/null
  # The adoptee holds everything that mirror CAN still install.
  P6H_INSTALLABLE=0
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    [ -f "$P6H/fw/$rel" ] || continue
    mkdir -p "$P6H/p/$(dirname "$rel")" 2>/dev/null
    cp -p "$P6H/fw/$rel" "$P6H/p/$rel" 2>/dev/null && P6H_INSTALLABLE=$((P6H_INSTALLABLE + 1))
  done <<P6HSET
$( . "$REPO_ROOT/scripts/lib/helpers-core.sh" >/dev/null 2>&1
   . "$REPO_ROOT/scripts/lib/scaffold-shipped-set.sh" >/dev/null 2>&1
   soif_parse_shipped_scripts "$P6H/fw/init.sh" "$P6H/fw/scripts" )
P6HSET
  P6H_PARSED="$( . "$REPO_ROOT/scripts/lib/helpers-core.sh" >/dev/null 2>&1
                 . "$REPO_ROOT/scripts/lib/scaffold-shipped-set.sh" >/dev/null 2>&1
                 soif_parse_shipped_scripts "$P6H/fw/init.sh" "$P6H/fw/scripts" | grep -c . )"
  P6H_PARSED="$(_num "$P6H_PARSED")"
  ( cd "$P6H/p" && git add -A && git commit -q -m "chore: everything that root can install" ) >/dev/null 2>&1

  # THE CONTROL ASSERTS THE INEQUALITY THAT ACTUALLY DISCRIMINATES, which is
  # NOT `parsed > installable`. The buggy predicate scores
  # `n_present * 2 >= n_total` with n_total = PARSED, and the adoptee holds
  # every INSTALLABLE entry — so the mutant only fails while
  # `2 * installable < parsed`. A draft asserted the weaker inequality and
  # review proved it vacuous by widening the fixture five entries: the control
  # still passed while the round-6 revert went green underneath it. Five files
  # moving into `scripts/lib/` would have done the same, and WP10/11/12 each
  # add files there.
  if [ "$P6H_INSTALLABLE" -gt 0 ] && [ $((P6H_INSTALLABLE * 2)) -lt "$P6H_PARSED" ]; then
    pass "P6hctl — the mirror parses $P6H_PARSED entries and can install $P6H_INSTALLABLE; 2×$P6H_INSTALLABLE < $P6H_PARSED, which is the margin the mutant needs to fail in"
    _ans 1 > "$P6H/answers"
    run_adopt "$P6H/p" "$P6H/answers" "$REPORT" "$P6H/fw"
    if grep -q 'already looks framework-managed' "$RUN_ERR" 2>/dev/null; then
      pass "P6h — arm 3 refuses on the INSTALLABLE set, not the parsed one (rc $RUN_RC)"
    else
      fail_ "P6h" "arm 3 stayed silent — it is counting parsed entries against an adoptee that holds every installable one"
    fi
    if grep -q 'every framework script is already present' "$RUN_ERR" 2>/dev/null; then
      fail_ "P6h2" "the run fell through to the install tripwire, which is step 0's job to prevent"
    else
      pass "P6h2 — the install tripwire is never reached"
    fi
    if grep -qF "$P4_Q" "$RUN_OUT" 2>/dev/null; then
      fail_ "P6h3" "the operator was re-interrogated before the refusal"
    else
      pass "P6h3 — the operator is not re-asked the tier question"
    fi
  else
    fail_ "P6hctl" "parsed=$P6H_PARSED installable=$P6H_INSTALLABLE — 2×installable is not < parsed, so P6h cannot fail under the drift mutant and proves nothing"
  fi
fi

# ── P6i — THE INSTALLER HALF, pinned by BEHAVIOUR and not by its marker. ───
# Review neutered `# BL-242-INSTALL-SET-KEY` while LEAVING THE MARKER IN PLACE
# and the whole suite stayed green: the binding on that half was existence, not
# behaviour. The discriminating shape is an incomplete root plus a FRESH
# adoptee — the preflight stays silent (nothing is installed yet), so the
# install actually runs, and without the source filter it tries to copy a file
# that is not there.
P6I="$(newtmp)"
mkdir -p "$P6I/fw" "$P6I/p"
if ! mk_mirror "$P6I/fw" || ! mk_adoptee "$P6I/p"; then
  fail_ "P6i setup" "could not build the mirror or the adoptee"
else
  find "$P6I/fw/scripts" -maxdepth 1 -type f -name '*.sh' ! -name 'adopt-project.sh' ! -name 'scout.sh' \
    -exec rm -f {} + 2>/dev/null
  # THE CONTROL P6h GOT AND THIS DID NOT. A COMPLETE root also adopts a fresh
  # project at rc 0 and also never says "could not install", so both assertions
  # below pass against a mirror that stopped being incomplete — review neutered
  # this `find` and watched the pair go green with the filter mutant live.
  # Assert the mirror is genuinely short of its own parse.
  P6I_PARSED="$( . "$REPO_ROOT/scripts/lib/helpers-core.sh" >/dev/null 2>&1
                 . "$REPO_ROOT/scripts/lib/scaffold-shipped-set.sh" >/dev/null 2>&1
                 soif_parse_shipped_scripts "$P6I/fw/init.sh" "$P6I/fw/scripts" | grep -c . )"
  P6I_HAVE="$( . "$REPO_ROOT/scripts/lib/helpers-core.sh" >/dev/null 2>&1
               . "$REPO_ROOT/scripts/lib/scaffold-shipped-set.sh" >/dev/null 2>&1
               soif_parse_shipped_scripts "$P6I/fw/init.sh" "$P6I/fw/scripts" \
                 | while IFS= read -r r; do [ -f "$P6I/fw/$r" ] && echo x; done | grep -c . )"
  P6I_PARSED="$(_num "$P6I_PARSED")"; P6I_HAVE="$(_num "$P6I_HAVE")"
  if [ "$P6I_HAVE" -gt 0 ] && [ "$P6I_PARSED" -gt "$P6I_HAVE" ]; then
    pass "P6ictl — the mirror parses $P6I_PARSED entries and holds only $P6I_HAVE: it is genuinely incomplete, so the assertions below discriminate"
  else
    fail_ "P6ictl" "parsed=$P6I_PARSED held=$P6I_HAVE — the mirror is complete; P6i/P6i2 would pass against any build"
  fi
  _ans 1 > "$P6I/answers"
  run_adopt "$P6I/p" "$P6I/answers" "$REPORT" "$P6I/fw"
  P6I_RC="$RUN_RC"
  if [ "$P6I_RC" -eq 0 ]; then
    pass "P6i — an incomplete framework root still adopts a fresh project (rc 0): the installer SKIPS entries it cannot copy"
  else
    fail_ "P6i" "adoption refused (rc $P6I_RC) on an incomplete root — the installer is trying to copy sources that are not there"
  fi
  if grep -q 'could not install' "$RUN_ERR" 2>/dev/null; then
    fail_ "P6i2" "the run hit 'could not install' — the source filter is not skipping absent entries"
  else
    pass "P6i2 — no 'could not install' refusal: the filter did its job"
  fi
fi

# ── P6j — THE `-e` HALF. ──────────────────────────────────────────────────
# The preflight tests the adoptee with `-e`, the installer with `-e`; a draft
# used `-f` on the preflight side and review showed reverting it is invisible.
# They differ for a NON-REGULAR file at a framework script path, so the fixture
# plants exactly the boundary count with one entry as a DIRECTORY: `-e` counts
# it and refuses, `-f` does not and adopts.
P6J="$(newtmp)"
mkdir -p "$P6J/p"
if ! mk_adoptee "$P6J/p"; then
  fail_ "P6j setup" "could not build the adoptee"
else
  k="$(_plant_k "$P6J/p" "$P6E_HALF")"
  # turn the LAST planted entry into a directory
  P6J_VICTIM="$( ( cd "$P6J/p" && find scripts -type f -name '*.sh' 2>/dev/null | LC_ALL=C sort | tail -1 ) )"
  if [ -n "$P6J_VICTIM" ]; then
    rm -f "$P6J/p/$P6J_VICTIM" && mkdir -p "$P6J/p/$P6J_VICTIM"
  fi
  ( cd "$P6J/p" && git add -A && git commit -q -m "chore: boundary count, one of them a directory" ) >/dev/null 2>&1
  # `-n` FIRST, and it is not belt-and-braces: with an empty victim the test
  # degenerates to `[ -d "$P6J/p/" ]`, which is TRUE, so the control passed
  # while nothing had been planted and P6j went green under the very mutant it
  # exists to catch. Review demonstrated exactly that.
  if [ -n "$P6J_VICTIM" ] && [ -d "$P6J/p/$P6J_VICTIM" ]; then
    pass "P6jctl — $k planted at the boundary with '$P6J_VICTIM' as a DIRECTORY, which -e counts and -f does not"
    _ans 1 > "$P6J/answers"
    run_adopt "$P6J/p" "$P6J/answers" "$REPORT"
    if [ "$RUN_RC" -ne 0 ] && grep -q 'already looks framework-managed' "$RUN_ERR" 2>/dev/null; then
      pass "P6j — the directory still counts toward the threshold (rc $RUN_RC): the preflight tests -e, matching the installer"
    else
      fail_ "P6j" "rc=$RUN_RC — a non-regular file at a framework path was not counted; the preflight is testing -f while the installer tests -e"
    fi
  else
    fail_ "P6jctl" "could not plant a directory at a framework script path"
  fi
fi

echo ""
echo "=== W — APPROVAL_LOG.md is an archive-and-replace surface (§7.1) ==="

# A4 writes APPROVAL_LOG.md over whatever is there. §7.1's rule is not "AI
# surfaces are archived", it is "every archive-and-replace surface produces a
# row" — and the first cut of WP9b added the replace without the row. MEASURED
# THEN: an operator's own never-committed APPROVAL_LOG.md was destroyed at
# rc 0, with ZERO recoverable copies, in a run that printed "Nothing was
# deleted." The fixture uses an UNCOMMITTED log deliberately: a committed one
# is recoverable from history and would understate the loss.
W1="$(newtmp)"
mkdir -p "$W1/p"
W1_OK=0
if mk_adoptee "$W1/p"; then
  printf '# OUR APPROVAL LOG\n\nSOX sign-off 2024-11-02, approved by the audit committee.\n' \
    > "$W1/p/APPROVAL_LOG.md"
  W1_OK=1
fi

if [ "$W1_OK" -ne 1 ]; then
  fail_ "W setup" "could not build the approval-log fixture"
else
  if ( cd "$W1/p" && git ls-files --error-unmatch APPROVAL_LOG.md >/dev/null 2>&1 ); then
    fail_ "W0ctl" "the fixture's APPROVAL_LOG.md is tracked; the unrecoverable case is not under test"
  else
    pass "W0ctl — the fixture's APPROVAL_LOG.md is UNCOMMITTED (so a loss here is unrecoverable)"
  fi

  _ans 1 > "$W1/answers"
  run_adopt "$W1/p" "$W1/answers" "$REPORT"
  W1_RC="$RUN_RC"
  W1_ARC="$(cd "$W1/p" && ls -d .claude/adoption-archive/*/ 2>/dev/null | head -1)"
  W1_ARC="${W1_ARC%/}"

  [ "$W1_RC" -eq 0 ] \
    && pass "W1ctl — the adoption completes over a pre-existing approval log (rc 0), so the assertions below are about the ARCHIVE, not a refusal" \
    || fail_ "W1ctl" "the adoption refused (rc $W1_RC); this section cannot say anything about archiving"

  if [ -n "$W1_ARC" ] && [ -f "$W1/p/$W1_ARC/APPROVAL_LOG.md" ]; then
    pass "W1 — the operator's APPROVAL_LOG.md is IN the archive"
  else
    fail_ "W1" "the operator's APPROVAL_LOG.md was replaced and never archived"
  fi

  # Their bytes, not the template's — an archive holding the framework's own
  # output under the operator's name is worse than no archive.
  if grep -q 'OUR APPROVAL LOG' "$W1/p/$W1_ARC/APPROVAL_LOG.md" 2>/dev/null; then
    pass "W2 — the archived copy carries THEIR content, not the rendered template"
  else
    fail_ "W2" "the archived copy is not the operator's original"
  fi

  # And the MANIFEST must name it, because the disclosure and the restore line
  # are both driven from there — an archived file with no row is invisible.
  if jq -e '[.entries[] | select(.originalPath == "APPROVAL_LOG.md")] | length > 0' \
       "$W1/p/$W1_ARC/MANIFEST.json" >/dev/null 2>&1; then
    pass "W3 — MANIFEST.json carries a row for it (so it has a restore line and reaches the disclosure)"
  else
    fail_ "W3" "APPROVAL_LOG.md is in the archive but absent from MANIFEST.json — invisible to the disclosure and to --re-add"
  fi

  # The row must say the file was REPLACED, not kept. `kept` means the
  # operator's original is still at the path, which A4 makes false — and
  # nothing in this repository read the field, so reverting it to `kept` was
  # invisible to every check until this assertion existed.
  W_DISPO="$(jq -r '[.entries[]|select(.originalPath=="APPROVAL_LOG.md")|.disposition]|first // ""' \
    "$W1/p/$W1_ARC/MANIFEST.json" 2>/dev/null)"
  [ "$W_DISPO" = "replaced" ] \
    && pass "W6 — the MANIFEST records disposition=replaced for it (not 'kept', which would be false)" \
    || fail_ "W6" "disposition is '$W_DISPO', want 'replaced'"

  # The transcript must SAY so. "Nothing was deleted" is printed in this block;
  # the first cut printed it in the same run that destroyed the file.
  if grep -q 'yours: APPROVAL_LOG.md' "$RUN_OUT" 2>/dev/null; then
    pass "W4 — the run TELLS the operator their approval log was archived"
  else
    fail_ "W4" "the archive disclosure never names APPROVAL_LOG.md, in a block that says 'Nothing was deleted'"
  fi

  # And the framework's log is the one now at the path.
  if grep -q 'Pre-Phase 0' "$W1/p/APPROVAL_LOG.md" 2>/dev/null; then
    pass "W5 — the rendered template is what sits at the path now (the replace still happened)"
  else
    fail_ "W5" "the path does not carry the rendered template; A4 did not run"
  fi
fi

echo ""
echo "=== X — the project name is DATA, not a substitution pattern ==="

# `ADOPT_PROJECT_NAME` is `${root##*/}` — a directory basename the operator
# chose — and it lands in a replacement. A first cut used `sed`, and all three
# of these were measured against it: `&` rendered `amp__PROJECT_NAME__co` at
# rc 0 (CLAUDE.md's whole-match trap), `,` collided with the delimiter and left
# a ZERO-BYTE log at rc 1 with `adopt_refuse` never called, and `\` was eaten.
# `back\slash` IS IN THIS LIST BECAUSE IT WAS THE ONE LEFT OUT. The commit
# enumerated three measured failures and section X pinned two of them; the
# unpinned one was still broken through two more fix attempts, because `awk -v`
# escape-processes its value before the render loop ever sees it. Pin every
# case you claim to have fixed.
# `pre__TODAY__post` IS IN THIS LIST BECAUSE THE TWO SUBSTITUTIONS NEST. The
# outer pass scans the inner pass output, so with the NAME substituted first a
# directory called that had the date written into its own name — at rc 0, in
# both fields, while the same run commit subject carried the real name. Order
# swapped; this pins it.
for xname in 'amp&co' 'comma,inc' 'back\slash' 'tab	here' 'dollar$var' 'pre__TODAY__post'; do
  XD="$(newtmp)"
  mkdir -p "$XD/$xname"
  if ! mk_adoptee "$XD/$xname"; then
    fail_ "X setup ($xname)" "could not build the adoptee"
    continue
  fi
  _ans 1 > "$XD/answers"
  run_adopt "$XD/$xname" "$XD/answers" "$REPORT"
  x_rc="$RUN_RC"
  x_bytes="$(wc -c < "$XD/$xname/APPROVAL_LOG.md" 2>/dev/null | tr -d ' ')"
  x_bytes="$(_num "$x_bytes")"
  # NOT a blanket placeholder count. `pre__TODAY__post` renders VERBATIM and
  # therefore legitimately contains the literal `__TODAY__` — a count would
  # fail the very case it was added to prove. Assert the two facts separately:
  # no `__PROJECT_NAME__` survives anywhere, and the date WAS substituted.
  x_left="$(grep -c '__PROJECT_NAME__' "$XD/$xname/APPROVAL_LOG.md" 2>/dev/null)"
  x_left="$(_num "$x_left")"
  x_dated=0
  grep -q "$(date +%Y-%m-%d)" "$XD/$xname/APPROVAL_LOG.md" 2>/dev/null && x_dated=1
  # BOTH substituted fields, not just the title: the claim under test is that
  # the operator string is copied verbatim on every leg, and a draft checked
  # only the title.
  x_named=0
  grep -qF "Approval Log — $xname" "$XD/$xname/APPROVAL_LOG.md" 2>/dev/null && x_named=1
  x_front=0
  grep -qF "project: $xname" "$XD/$xname/APPROVAL_LOG.md" 2>/dev/null && x_front=1
  if [ "$x_rc" -eq 0 ] && [ "$x_left" -eq 0 ] && [ "$x_bytes" -gt 0 ] \
     && [ "$x_named" -eq 1 ] && [ "$x_front" -eq 1 ] && [ "$x_dated" -eq 1 ]; then
    pass "X ($xname) — verbatim in BOTH fields, date substituted, no __PROJECT_NAME__ left ($x_bytes bytes)"
  else
    fail_ "X ($xname)" "rc=$x_rc bytes=$x_bytes name_placeholder_left=$x_left title=$x_named frontmatter=$x_front date_substituted=$x_dated"
  fi
done

echo ""
echo "=== PM — the preflight's mutation proofs (one per arm) ==="

PF_ARM1_MARK="# BL-242-PREFLIGHT-ARM1"
PF_ARM2_MARK="# BL-242-PREFLIGHT-ARM2"
PF_ARM3_MARK="# BL-242-PREFLIGHT-ARM3"

for m in "$PF_ARM1_MARK" "$PF_ARM2_MARK" "$PF_ARM3_MARK"; do
  n="$(_sites "$L_STATE" "$m")"
  [ "$n" = "1" ] \
    && pass "PM-anchor — '$m' occurs exactly once at end-of-line in adopt-state.sh" \
    || fail_ "PM-anchor" "'$m' occurs $n times (need exactly 1) — the mutants below cannot be aimed"
done

# _mutate_lib <mirror> <lib-basename> <marker> <replacement>
_mutate_lib() {
  local mir="$1" lib="$2" mark="$3" repl="$4" before after changed
  before="$(mktemp)"; cp "$mir/scripts/lib/adopt/$lib" "$before"
  _sed_inplace "$mir/scripts/lib/adopt/$lib" "s|^.*${mark}\$|${repl}|"
  after="$mir/scripts/lib/adopt/$lib"
  changed="$(_changed_lines "$before" "$after")"
  rm -f "$before"
  [ "$changed" -ge 2 ] || { printf '0\n'; return 0; }
  [ "$(_parses "$after")" = "1" ] || { printf '0\n'; return 0; }
  printf '1\n'
}

# _mutate_state <mirror> <marker> <replacement>  → 1 on a clean, parsing edit
_mutate_state() {
  local mir="$1" mark="$2" repl="$3" before after changed
  before="$(mktemp)"; cp "$mir/scripts/lib/adopt/adopt-state.sh" "$before"
  _sed_inplace "$mir/scripts/lib/adopt/adopt-state.sh" "s|^.*${mark}\$|${repl}|"
  after="$mir/scripts/lib/adopt/adopt-state.sh"
  changed="$(_changed_lines "$before" "$after")"
  rm -f "$before"
  [ "$changed" -ge 2 ] || { printf '0\n'; return 0; }
  [ "$(_parses "$after")" = "1" ] || { printf '0\n'; return 0; }
  printf '1\n'
}

# ── PM1 — drop arm 1 on the hand-advanced adopted fixture. ─────────────────
# ITS MUTANT EXITS 1 (a later refusal fires), so the assertion CANNOT read the
# exit code. It reads the reverted state — which is the whole point: refusing
# after `adopt_write_file` has already `cat >` overwritten phase-state.json is
# not refusing.
#
# THE FIXTURE DELETES ONE FRAMEWORK SCRIPT, AND THAT IS NOT A CONTRIVANCE — it
# is what makes the design's specified RED reachable TODAY. On an untouched
# adopted tree every framework file is already present, so
# `adopt_install_framework`'s `n_copied -eq 0` tripwire refuses BEFORE the
# state stage and the mutant leaves phase-state intact: measured, dropping
# arm 1 changed nothing, and this proof was green against a build with no
# arm 1 at all. That tripwire is shipped v1's, and D1's framework-wins install
# UNREACHES it at WP11 — at which point the untouched tree reaches the state
# stage too. Deleting one script makes n_copied non-zero now, so this suite
# proves the property at WP9b instead of waiting for WP11 to make it visible.
# A partly-deleted adopted tree is also an ordinary thing to find in the wild.
PM1="$(newtmp)"
mkdir -p "$PM1/fw"
if ! mk_mirror "$PM1/fw"; then
  fail_ "PM1 setup" "could not mirror the framework"
elif [ "$(_mutate_state "$PM1/fw" "$PF_ARM1_MARK" "  :")" != "1" ]; then
  fail_ "PM1 setup" "the arm-1 mutation did not apply cleanly (or the mutant does not parse)"
elif ! _adopted_fixture "$PM1"; then
  fail_ "PM1 setup" "could not build the adopted fixture"
else
  jq '.current_phase = 2 | .gates.phase_0_to_1 = "2026-01-05"' \
     "$PM1/p/.claude/phase-state.json" > "$PM1/ps.new" 2>/dev/null \
    && mv "$PM1/ps.new" "$PM1/p/.claude/phase-state.json"
  rm -f "$PM1/p/scripts/check-versions.sh"
  ( cd "$PM1/p" && git add -A && git commit -q -m "chore: earned a gate, lost a script" ) >/dev/null 2>&1
  PM1_PHASE_BEFORE="$(_json_str "$PM1/p/.claude/phase-state.json" '.current_phase')"
  _ans 1 > "$PM1/answers2"
  run_adopt "$PM1/p" "$PM1/answers2" "$REPORT" "$PM1/fw"
  PM1_PHASE_AFTER="$(_json_str "$PM1/p/.claude/phase-state.json" '.current_phase')"
  PM1_G1_AFTER="$(_json_str "$PM1/p/.claude/phase-state.json" '.gates.phase_0_to_1')"
  if [ "$PM1_PHASE_AFTER" != "$PM1_PHASE_BEFORE" ] || [ -z "$PM1_G1_AFTER" ]; then
    pass "PM1 (MUTATION) — dropping arm 1 reverts the earned state (phase $PM1_PHASE_BEFORE -> $PM1_PHASE_AFTER, gate '$PM1_G1_AFTER'): arm 1 is what protects it"
  else
    fail_ "PM1 (MUTATION)" "dropping arm 1 changed nothing — arm 1 is not load-bearing, or another arm is masking it (see PM1b/PM1c)"
  fi
fi

# ── PM1c — the SAME fixture, UNMUTATED. ────────────────────────────────────
# PM1 above is only a proof if the shipped code holds where the mutant fails.
# Without this control, a PM1 that went RED for an unrelated reason (the
# deleted script breaking the run outright, say) would look like a proof.
PM1C="$(newtmp)"
if ! _adopted_fixture "$PM1C"; then
  fail_ "PM1c setup" "could not build the adopted fixture"
else
  jq '.current_phase = 2 | .gates.phase_0_to_1 = "2026-01-05"' \
     "$PM1C/p/.claude/phase-state.json" > "$PM1C/ps.new" 2>/dev/null \
    && mv "$PM1C/ps.new" "$PM1C/p/.claude/phase-state.json"
  rm -f "$PM1C/p/scripts/check-versions.sh"
  ( cd "$PM1C/p" && git add -A && git commit -q -m "chore: earned a gate, lost a script" ) >/dev/null 2>&1
  PM1C_PHASE_BEFORE="$(_json_str "$PM1C/p/.claude/phase-state.json" '.current_phase')"
  _ans 1 > "$PM1C/answers2"
  run_adopt "$PM1C/p" "$PM1C/answers2" "$REPORT"
  PM1C_PHASE_AFTER="$(_json_str "$PM1C/p/.claude/phase-state.json" '.current_phase')"
  PM1C_G1_AFTER="$(_json_str "$PM1C/p/.claude/phase-state.json" '.gates.phase_0_to_1')"
  if [ "$PM1C_PHASE_AFTER" = "$PM1C_PHASE_BEFORE" ] && [ "$PM1C_G1_AFTER" = "2026-01-05" ]; then
    pass "PM1c — on that same fixture the SHIPPED code holds the state (phase $PM1C_PHASE_AFTER, gate $PM1C_G1_AFTER)"
  else
    fail_ "PM1c" "the shipped code did not protect the fixture PM1 mutates: phase $PM1C_PHASE_BEFORE -> $PM1C_PHASE_AFTER, gate '$PM1C_G1_AFTER'"
  fi
fi

# ── PM1b — arm 3 must NOT mask arm 1. ──────────────────────────────────────
# If arm 3 were spelled as bare "phase-state present", it would refuse the
# adopted fixture too and PM1 above would pass without arm 1 existing. This
# drops arm 3 ONLY and requires arm 1 to hold alone — so PM1's red is
# attributable to arm 1 rather than to arm 3 having been absent from that
# mutant. (Review checked the other direction too: strip arm 3's `not adopted`
# conjunct and PM1 goes red while PM1b stays green — PM1 is the assertion that
# pins the conjunct, and a draft of the shipped comment credited PM1b.)
PM1B="$(newtmp)"
mkdir -p "$PM1B/fw"
if ! mk_mirror "$PM1B/fw"; then
  fail_ "PM1b setup" "could not mirror the framework"
elif [ "$(_mutate_state "$PM1B/fw" "$PF_ARM3_MARK" "  :")" != "1" ]; then
  fail_ "PM1b setup" "the arm-3 mutation did not apply cleanly"
elif ! _adopted_fixture "$PM1B"; then
  fail_ "PM1b setup" "could not build the adopted fixture"
else
  jq '.current_phase = 2 | .gates.phase_0_to_1 = "2026-01-05"' \
     "$PM1B/p/.claude/phase-state.json" > "$PM1B/ps.new" 2>/dev/null \
    && mv "$PM1B/ps.new" "$PM1B/p/.claude/phase-state.json"
  ( cd "$PM1B/p" && git add -A && git commit -q -m "chore: earned a gate" ) >/dev/null 2>&1
  PM1B_PHASE_BEFORE="$(_json_str "$PM1B/p/.claude/phase-state.json" '.current_phase')"
  _ans 1 > "$PM1B/answers2"
  run_adopt "$PM1B/p" "$PM1B/answers2" "$REPORT" "$PM1B/fw"
  PM1B_PHASE_AFTER="$(_json_str "$PM1B/p/.claude/phase-state.json" '.current_phase')"
  [ "$PM1B_PHASE_AFTER" = "$PM1B_PHASE_BEFORE" ] \
    && pass "PM1b — with arm 3 dropped, ARM 1 alone still protects an adopted tree (phase $PM1B_PHASE_AFTER)" \
    || fail_ "PM1b" "arm 1 alone did not hold: phase $PM1B_PHASE_BEFORE -> $PM1B_PHASE_AFTER (arm 3 was masking arm 1)"
fi

# ── PM1d — drop arm 1's SECOND WITNESS. THE MUTANT EXITS ZERO. ─────────────
# Review deleted this one line and every PR-blocking suite stayed green while
# the mutant completed an adoption and destroyed gate-earned state. Arms 2 and
# 3 cannot catch it: each returns 0 on its own head-copy check, so with the
# second witness gone there is nothing left to refuse.
PM1D="$(newtmp)"
mkdir -p "$PM1D/fw"
PM1D_MARK="# BL-242-PREFLIGHT-WITNESS2"
pm1d_sites="$(_sites "$L_STATE" "$PM1D_MARK")"
[ "$pm1d_sites" = "1" ] \
  && pass "PM1d-anchor — '$PM1D_MARK' occurs exactly once at end-of-line" \
  || fail_ "PM1d-anchor" "'$PM1D_MARK' occurs $pm1d_sites times (need exactly 1)"

if ! mk_mirror "$PM1D/fw"; then
  fail_ "PM1d setup" "could not mirror the framework"
elif [ "$(_mutate_state "$PM1D/fw" "$PM1D_MARK" "    :")" != "1" ]; then
  fail_ "PM1d setup" "the second-witness mutation did not apply cleanly"
elif ! _adopted_fixture "$PM1D"; then
  fail_ "PM1d setup" "could not build the adopted fixture"
else
  jq '.current_phase = 2 | .gates.phase_0_to_1 = "2026-01-05"' \
     "$PM1D/p/.claude/phase-state.json" > "$PM1D/ps.new" 2>/dev/null \
    && mv "$PM1D/ps.new" "$PM1D/p/.claude/phase-state.json"
  rm -f "$PM1D/p/scripts/check-versions.sh"
  ( cd "$PM1D/p" && git add -A && git commit -q -m "chore: earned a gate, lost a script" ) >/dev/null 2>&1
  # The `.adoption` deletion comes AFTER the commit, so HEAD's copy still says
  # adopted and only the working copy is blanked — which is the whole point.
  jq 'del(.adoption)' "$PM1D/p/.claude/manifest.json" > "$PM1D/mf.new" 2>/dev/null \
    && mv "$PM1D/mf.new" "$PM1D/p/.claude/manifest.json"
  PM1D_PHASE_BEFORE="$(_json_str "$PM1D/p/.claude/phase-state.json" '.current_phase')"
  _ans 1 > "$PM1D/answers2"
  run_adopt "$PM1D/p" "$PM1D/answers2" "$REPORT" "$PM1D/fw"
  PM1D_RC="$RUN_RC"
  PM1D_PHASE_AFTER="$(_json_str "$PM1D/p/.claude/phase-state.json" '.current_phase')"
  if [ "$PM1D_PHASE_AFTER" != "$PM1D_PHASE_BEFORE" ]; then
    pass "PM1d (MUTATION) — dropping the committed witness lets a blanked manifest re-adopt (rc $PM1D_RC) and reverts the earned state ($PM1D_PHASE_BEFORE -> $PM1D_PHASE_AFTER)"
  else
    fail_ "PM1d (MUTATION)" "dropping the second witness changed nothing — it is not load-bearing, or something else refuses first"
  fi
fi

# ── PM1e — drop arm 3's INSTALLED-FRAMEWORK signal. ───────────────────────
# Review excised exactly this line and every PR-blocking adoption suite passed
# with identical scores. Fourth round running that a fix shipped with no mutant.
PM1E="$(newtmp)"
mkdir -p "$PM1E/fw" "$PM1E/p"
PM1E_MARK="# BL-242-PREFLIGHT-ARM3-INSTALLED"
pm1e_sites="$(_sites "$L_STATE" "$PM1E_MARK")"
[ "$pm1e_sites" = "1" ] \
  && pass "PM1e-anchor — '$PM1E_MARK' occurs exactly once at end-of-line" \
  || fail_ "PM1e-anchor" "'$PM1E_MARK' occurs $pm1e_sites times (need exactly 1)"

if ! mk_mirror "$PM1E/fw"; then
  fail_ "PM1e setup" "could not mirror the framework"
elif [ "$(_mutate_state "$PM1E/fw" "$PM1E_MARK" "      found=\"\"")" != "1" ]; then
  fail_ "PM1e setup" "the installed-signal mutation did not apply cleanly"
elif ! mk_adoptee "$PM1E/p"; then
  fail_ "PM1e setup" "could not build the adoptee"
else
  _ans 1 > "$PM1E/answers"
  ( cd "$PM1E/p" && SOIF_ADOPT_HALT_AFTER=install \
      bash "$PM1E/fw/scripts/adopt-project.sh" --scan-report "$REPORT" ) \
    < "$PM1E/answers" > "$PM1E/out1" 2> "$PM1E/err1" || true
  run_adopt "$PM1E/p" "$PM1E/answers" "$REPORT" "$PM1E/fw"
  if grep -qF "$P4_Q" "$RUN_OUT" 2>/dev/null; then
    pass "PM1e (MUTATION) — without the installed-framework signal the operator is re-interrogated before anything refuses"
  else
    fail_ "PM1e (MUTATION)" "excising the signal changed nothing observable"
  fi
fi

# ── PM2 — drop arm 2. THE MUTANT EXITS ZERO. ───────────────────────────────
PM2="$(newtmp)"
mkdir -p "$PM2/fw" "$PM2/p"
if ! mk_mirror "$PM2/fw"; then
  fail_ "PM2 setup" "could not mirror the framework"
elif [ "$(_mutate_state "$PM2/fw" "$PF_ARM2_MARK" "  :")" != "1" ]; then
  fail_ "PM2 setup" "the arm-2 mutation did not apply cleanly"
elif ! mk_adoptee "$PM2/p"; then
  fail_ "PM2 setup" "could not build the adoptee"
else
  mkdir -p "$PM2/p/.claude/adoption-archive/2026-01-01T00-00-00Z-1234/.claude"
  printf '{"a":1}\n' > "$PM2/p/.claude/adoption-archive/2026-01-01T00-00-00Z-1234/.claude/settings.json"
  ( cd "$PM2/p" && git add -A && git commit -q -m "chore: an interrupted first run" ) >/dev/null 2>&1
  PM2_HASH_BEFORE="$(_tree_hash "$PM2/p")"
  _ans 1 > "$PM2/answers"
  run_adopt "$PM2/p" "$PM2/answers" "$REPORT" "$PM2/fw"
  PM2_HASH_AFTER="$(_tree_hash "$PM2/p")"
  [ "$PM2_HASH_AFTER" != "$PM2_HASH_BEFORE" ] \
    && pass "PM2 (MUTATION) — dropping arm 2 lets the run write over a prior archive (rc $RUN_RC, tree changed)" \
    || fail_ "PM2 (MUTATION)" "dropping arm 2 changed nothing — arm 2 is not load-bearing, or another arm masks it"
fi

# ── PM3 — drop arm 3. THE MUTANT EXITS ZERO — a completed adoption. ────────
PM3="$(newtmp)"
mkdir -p "$PM3/fw" "$PM3/p"
if ! mk_mirror "$PM3/fw"; then
  fail_ "PM3 setup" "could not mirror the framework"
elif [ "$(_mutate_state "$PM3/fw" "$PF_ARM3_MARK" "  :")" != "1" ]; then
  fail_ "PM3 setup" "the arm-3 mutation did not apply cleanly"
elif ! mk_adoptee "$PM3/p"; then
  fail_ "PM3 setup" "could not build the adoptee"
else
  mkdir -p "$PM3/p/.claude"
  printf '{"current_phase":2,"gates":{"phase_0_to_1":"2026-03-02"}}\n' > "$PM3/p/.claude/phase-state.json"
  printf '{"version":"1.0.0","deployment":"personal"}\n' > "$PM3/p/.claude/manifest.json"
  ( cd "$PM3/p" && git add -A && git commit -q -m "chore: scaffolded by init.sh" ) >/dev/null 2>&1
  PM3_PHASE_BEFORE="$(_json_str "$PM3/p/.claude/phase-state.json" '.current_phase')"
  _ans 1 > "$PM3/answers"
  run_adopt "$PM3/p" "$PM3/answers" "$REPORT" "$PM3/fw"
  PM3_RC="$RUN_RC"
  PM3_PHASE_AFTER="$(_json_str "$PM3/p/.claude/phase-state.json" '.current_phase')"
  PM3_ADOPTED=0
  jq -e '.adoption' "$PM3/p/.claude/manifest.json" >/dev/null 2>&1 && PM3_ADOPTED=1
  if [ "$PM3_PHASE_AFTER" != "$PM3_PHASE_BEFORE" ] && [ "$PM3_ADOPTED" -eq 1 ]; then
    pass "PM3 (MUTATION) — dropping arm 3 overwrites a greenfield's gate-earned state ($PM3_PHASE_BEFORE -> $PM3_PHASE_AFTER) AND stamps it, at rc $PM3_RC"
  else
    fail_ "PM3 (MUTATION)" "dropping arm 3 changed nothing observable (phase $PM3_PHASE_BEFORE -> $PM3_PHASE_AFTER, stamped=$PM3_ADOPTED)"
  fi
fi

echo ""
echo "=== A — A4's APPROVAL_LOG.md (§8.2 step 7, §8.3a-A4) ==="

A0="$(newtmp)"
A0_OK=0
_adopted_fixture "$A0" && A0_OK=1

if [ "$A0_OK" -ne 1 ]; then
  fail_ "A setup" "the resting-state adoption did not complete"
else
  [ -f "$A0/p/APPROVAL_LOG.md" ] \
    && pass "A1 — Act 2 writes APPROVAL_LOG.md" \
    || fail_ "A1" "APPROVAL_LOG.md is absent from a completed adoption"

  # THE POINT OF A4: the gate must reach a VERDICT instead of dying on the
  # precondition. Asserted on the absence of that specific refusal AND on the
  # presence of the gate's own summary, because "no precondition failure" is
  # trivially true of a gate that never ran.
  gate_in "$A0/p" --gate phase_0_to_1
  case "$(cat "$GATE_OUT" 2>/dev/null)" in
    *"APPROVAL_LOG.md not found but"*)
      fail_ "A2" "the gate still exits on the missing-approval-log precondition" ;;
    *)
      case "$(cat "$GATE_OUT" 2>/dev/null)" in
        *"Phase Gate Consistency Check"*)
          pass "A2 — the gate runs to a verdict instead of exiting on the precondition (rc $GATE_RC)" ;;
        *) fail_ "A2" "the gate produced no consistency-check output at all" ;;
      esac ;;
  esac

  # It is COMMITTED, not merely written: the adoption commit is what makes it
  # survive a fresh clone, and `adopt_stage_and_commit` stages explicitly.
  if ( cd "$A0/p" && git ls-tree -r --name-only HEAD 2>/dev/null | grep -qx 'APPROVAL_LOG.md' ); then
    pass "A3 — APPROVAL_LOG.md is in the adoption commit"
  else
    fail_ "A3" "APPROVAL_LOG.md was written but never committed"
  fi

  # A4 forbids a fourth spelling: it must be the tier-matched init.sh
  # template, rendered. Compared structurally, because __TODAY__ and
  # __PROJECT_NAME__ legitimately differ from the template's own bytes.
  #
  # NOT BY SECTION COUNT — a draft did that and it cannot discriminate:
  # MEASURED, both templates carry exactly 10 `## ` headers, so a count pins
  # "some approval log" and says nothing about WHICH. The personal template's
  # own header line is the discriminator, and A7ctl proves the two differ on it.
  if grep -qx '## Pre-Phase 0: Pre-Conditions' "$A0/p/APPROVAL_LOG.md" 2>/dev/null; then
    pass "A4 — the log is the PERSONAL template (its own pre-conditions header)"
  else
    fail_ "A4" "the personal template's header is absent — this is not the tier-matched rendered template"
  fi

  # No placeholder may survive rendering.
  if grep -q '__TODAY__\|__PROJECT_NAME__' "$A0/p/APPROVAL_LOG.md" 2>/dev/null; then
    fail_ "A5" "an unrendered placeholder survived into APPROVAL_LOG.md"
  else
    pass "A5 — every template placeholder is rendered"
  fi

  # And it carries NO dated gate-approval row — the adoption approved nothing.
  gate_in "$A0/p" --gate phase_0_to_1
  case "$(cat "$GATE_OUT" 2>/dev/null)" in
    *"gate date not recorded"*)
      pass "A6 — the rendered log carries no dated gate-approval row (the gate says so)" ;;
    *) fail_ "A6" "the gate found approval evidence in a log the adoption just wrote" ;;
  esac
fi

# ── A7 — the tier match. ───────────────────────────────────────────────────
# D9's tier answer is the log's only input besides the name. A build that
# ignores it and always renders one template passes every assertion above.
A7="$(newtmp)"
mkdir -p "$A7/p"
if mk_adoptee "$A7/p"; then
  _ans 2 > "$A7/answers"        # 2 = organizational
  run_adopt "$A7/p" "$A7/answers" "$REPORT"
  if [ "$RUN_RC" -ne 0 ]; then
    fail_ "A7 setup" "the organizational adoption did not complete (rc $RUN_RC)"
  else
    A7_DEPLOY="$(_json_str "$A7/p/.claude/manifest.json" '.deployment')"
    A7_ORG_H='## Pre-Phase 0: Organizational Pre-Conditions'
    A7_PER_H='## Pre-Phase 0: Pre-Conditions'
    # The control: the discriminator must actually separate the two templates,
    # each appearing in its own and NOT in the other. Without this the two
    # assertions below could both be true of one file.
    if grep -qxF "$A7_ORG_H" "$TMPL_ORG" && ! grep -qxF "$A7_ORG_H" "$TMPL_PERSONAL" \
       && grep -qxF "$A7_PER_H" "$TMPL_PERSONAL" && ! grep -qxF "$A7_PER_H" "$TMPL_ORG"; then
      pass "A7ctl — the two templates are separated by their pre-conditions header (section COUNT cannot: both are 10)"
      if [ "$A7_DEPLOY" != "organizational" ]; then
        fail_ "A7" "answer 2 produced deployment '$A7_DEPLOY', not organizational — the fixture is not exercising the org arm"
      elif grep -qxF "$A7_ORG_H" "$A7/p/APPROVAL_LOG.md" 2>/dev/null; then
        pass "A7 — an organizational adoption renders the ORG template"
      else
        fail_ "A7" "deployment '$A7_DEPLOY' did not render the org template — the tier is being ignored"
      fi
    else
      fail_ "A7ctl" "the pre-conditions headers do not separate the two templates; this assertion cannot discriminate"
    fi
  fi
else
  fail_ "A7 setup" "could not build the adoptee"
fi

echo ""
echo "=== G — a gitignored APPROVAL_LOG.md must not make a project unadoptable ==="

# MEASURED AS A REGRESSION against `main`: an adoptee whose `.gitignore` lists
# APPROVAL_LOG.md adopted at rc 0 before this package and, once A4 recorded the
# log for staging unconditionally, got `[BLOCKED] git will not stage every file
# this adoption must commit` and NO adoption commit — while the SAME run's
# archive half printed `your .gitignore covers: APPROVAL_LOG.md`. Two halves,
# opposite rules, and `docs/adoption.md` publishes the archive's half as a
# shipped guarantee.
G1="$(newtmp)"
mkdir -p "$G1/p"
if ! mk_adoptee "$G1/p"; then
  fail_ "G setup" "could not build the adoptee"
else
  printf 'APPROVAL_LOG.md\n' > "$G1/p/.gitignore"
  ( cd "$G1/p" && git add -A && git commit -q -m "chore: we ignore the approval log" ) >/dev/null 2>&1
  _ans 1 > "$G1/answers"
  run_adopt "$G1/p" "$G1/answers" "$REPORT"
  G1_RC="$RUN_RC"

  [ "$G1_RC" -eq 0 ] \
    && pass "G1 — an adoptee that gitignores APPROVAL_LOG.md still adopts (rc 0)" \
    || fail_ "G1" "adoption refused (rc $G1_RC) on a project that adopted cleanly before this package"

  if ( cd "$G1/p" && git log --oneline -1 2>/dev/null | grep -q 'adopt' ); then
    pass "G1b — the adoption commit exists"
  else
    fail_ "G1b" "no adoption commit was created"
  fi

  # On disk (so the gate, which reads the working tree, still works)…
  [ -f "$G1/p/APPROVAL_LOG.md" ] \
    && pass "G1c — the log is on disk, so the phase gate still reads it" \
    || fail_ "G1c" "the log is absent; the adopted project cannot run its own gate"
  gate_in "$G1/p"
  case "$(cat "$GATE_OUT" 2>/dev/null)" in
    *"APPROVAL_LOG.md not found but"*) fail_ "G1d" "the gate died on the precondition despite the log being on disk" ;;
    *) pass "G1d — the gate runs to a verdict (rc $GATE_RC)" ;;
  esac

  # …and NOT in the commit, because the operator said so.
  if ( cd "$G1/p" && git ls-tree -r --name-only HEAD 2>/dev/null | grep -qx 'APPROVAL_LOG.md' ); then
    fail_ "G1e" "the operator's ignore rule was overridden — APPROVAL_LOG.md is in the commit"
  else
    pass "G1e — it is NOT committed, honouring the operator's own .gitignore"
  fi

  # And the withholding is DISCLOSED, not silent.
  if grep -q 'APPROVAL_LOG.md' "$RUN_OUT" 2>/dev/null && grep -q 'stays out of the commit' "$RUN_OUT" 2>/dev/null; then
    pass "G1f — the run says so, by name"
  else
    fail_ "G1f" "the log was withheld from the commit and the operator was never told"
  fi
fi

echo ""
echo "=== AM — A4's mutation proofs (two arms, two fixtures) ==="

AL_WRITE_MARK="# BL-242-APPROVAL-LOG-WRITE"
AL_FIRST_MARK="# BL-242-APPROVAL-LOG-FIRST"

for m in "$AL_WRITE_MARK" "$AL_FIRST_MARK"; do
  n="$(_sites "$L_STATE" "$m")"
  [ "$n" = "1" ] \
    && pass "AM-anchor — '$m' occurs exactly once at end-of-line in adopt-state.sh" \
    || fail_ "AM-anchor" "'$m' occurs $n times (need exactly 1)"
done

# ── AM1 — drop the write. The gate must go back to dying on the precondition.
AM1="$(newtmp)"
mkdir -p "$AM1/fw"
if ! mk_mirror "$AM1/fw"; then
  fail_ "AM1 setup" "could not mirror the framework"
elif [ "$(_mutate_state "$AM1/fw" "$AL_WRITE_MARK" "      approval_log) : ;;")" != "1" ]; then
  fail_ "AM1 setup" "the approval-log-write mutation did not apply cleanly"
else
  mkdir -p "$AM1/p"
  if ! mk_adoptee "$AM1/p"; then
    fail_ "AM1 setup" "could not build the adoptee"
  else
    _ans 1 > "$AM1/answers"
    run_adopt "$AM1/p" "$AM1/answers" "$REPORT" "$AM1/fw"
    gate_in "$AM1/p" --gate phase_0_to_1
    case "$(cat "$GATE_OUT" 2>/dev/null)" in
      *"APPROVAL_LOG.md not found but"*)
        pass "AM1 (MUTATION) — dropping the write returns the gate to its precondition death (rc $GATE_RC)" ;;
      *) fail_ "AM1 (MUTATION)" "dropping the approval-log write changed nothing the gate can see" ;;
    esac
  fi
fi

# ── AM2 — THE CONVERSE, and it needs a DIFFERENT fixture. ──────────────────
# On the resting fixture `--gate phase_0_to_1` blocks for THREE independent
# reasons (measured: gate date unrecorded, PRODUCT_MANIFESTO.md absent, and
# the docs/phase-0 trio absent), so removing one leaves it blocked and "the
# gate passes a boundary nobody approved" is UNREACHABLE there. This fixture
# satisfies the other two so the approval is the only thing left.
#
# Two constraints the design names and this honours: the gate AUTO-RECORDS a
# seeded date into phase-state, so each arm gets a FRESH tree; and a malformed
# row adds issues rather than passing, so the seeded row is well-formed.
_a4_converse_fixture() {   # <dir> — an adopted tree, phase-0-complete except approval
  local w="$1"
  _adopted_fixture "$w" || return 1
  mkdir -p "$w/p/docs/phase-0" || return 1
  printf '# Functional Requirements\n\nWhat it must do.\n' > "$w/p/docs/phase-0/frd.md"
  printf '# User Journey\n\nHow they get through it.\n'   > "$w/p/docs/phase-0/user-journey.md"
  printf '# Data Contract\n\nWhat is stored and why.\n'   > "$w/p/docs/phase-0/data-contract.md"
  # THE SHAPE IS THE GATE'S, NOT A GUESS. check-phase-gate.sh requires eight
  # sections spelled `## <n>.` AND rejects any whose body filters down to
  # nothing after it strips headings, rules, blanks, comments, links and table
  # rows — so each body here is an ordinary prose line. A draft used descriptive
  # headings ("## The Problem") and the gate reported all eight missing, which
  # left AM2ctl at 2 issues and AM2 unreachable.
  {
    printf '# Product Manifesto\n\n'
    _i=1
    for _s in "The Problem" "Who It Is For" "What It Does" "What It Does Not Do" \
              "Why Now" "How We Know It Works" "Constraints" "Open Questions"; do
      printf '## %s. %s\n\nA real paragraph about %s, long enough that the gate reads it as prose rather than a placeholder.\n\n' "$_i" "$_s" "$_s"
      _i=$((_i + 1))
    done
  } > "$w/p/PRODUCT_MANIFESTO.md"
  return 0
}

AM2="$(newtmp)"
if ! _a4_converse_fixture "$AM2"; then
  fail_ "AM2 setup" "could not build the phase-0-complete-except-approval fixture"
else
  gate_in "$AM2/p" --gate phase_0_to_1
  AM2_ISSUES="$(grep -o '[0-9][0-9]* inconsistency' "$GATE_OUT" 2>/dev/null | head -1 | awk '{print $1}')"
  AM2_ISSUES="$(_num "$AM2_ISSUES")"
  if [ "$GATE_RC" -ne 0 ] && [ "$AM2_ISSUES" = "1" ]; then
    pass "AM2ctl — the converse fixture blocks with EXACTLY 1 issue (the missing approval), so the mutation below is reachable"
  else
    fail_ "AM2ctl" "the converse fixture blocks with $AM2_ISSUES issue(s) at rc $GATE_RC — removing one would leave it blocked and AM2 could never go RED"
    sed -n '1,20p' "$GATE_OUT" 2>/dev/null | sed 's/^/        /'
  fi
fi

# The mutation: seed a well-formed dated gate-approval row into the log the
# adoption wrote. A FRESH tree, because the gate above auto-records dates.
AM2B="$(newtmp)"
if ! _a4_converse_fixture "$AM2B"; then
  fail_ "AM2 setup (fresh tree)" "could not rebuild the converse fixture"
else
  awk '
    /^## Phase Gate: Phase 0 . Phase 1/ {
      print
      print ""
      print "| Field | Value |"
      print "|---|---|"
      print "| Date | 2026-05-04 |"
      print "| Approver | The operator |"
      print "| Decision | Approved |"
      next
    }
    { print }
  ' "$AM2B/p/APPROVAL_LOG.md" > "$AM2B/log.new" 2>/dev/null && mv "$AM2B/log.new" "$AM2B/p/APPROVAL_LOG.md"
  gate_in "$AM2B/p" --gate phase_0_to_1
  [ "$GATE_RC" -eq 0 ] \
    && pass "AM2 (MUTATION) — seeding a dated approval row makes the gate PASS (rc 0): the rendered log is what withholds approval" \
    || fail_ "AM2 (MUTATION)" "the gate still blocked (rc $GATE_RC) with a well-formed dated row seeded — the assertion above is not measuring the approval"
fi

# ── AM3 — the ORDER: the log is written FIRST in step 7. ───────────────────
# §8.2's constraint, and it is not cosmetic. Written last, every mid-step-7
# death leaves phase-state-present/log-absent — the gate's hard refusal. A
# log alone is inert (with no phase-state the gate exits 0), so first is the
# only safe order. Proven by halting the run between stages.
AM3="$(newtmp)"
mkdir -p "$AM3/p"
if ! mk_adoptee "$AM3/p"; then
  fail_ "AM3 setup" "could not build the adoptee"
else
  _ans 1 > "$AM3/answers"
  RUN_RC=0
  RUN_OUT="$AM3/run-out"; RUN_ERR="$AM3/run-err"
  ( cd "$AM3/p" && SOIF_ADOPT_HALT_AFTER=phase_state \
      bash "$REPO_ROOT/scripts/adopt-project.sh" --scan-report "$REPORT" ) \
    < "$AM3/answers" > "$RUN_OUT" 2> "$RUN_ERR" || RUN_RC=$?
  if [ -f "$AM3/p/.claude/phase-state.json" ] && [ -f "$AM3/p/APPROVAL_LOG.md" ]; then
    pass "AM3 — halted right after the phase_state stage, the log is ALREADY on disk (written first)"
  elif [ -f "$AM3/p/.claude/phase-state.json" ]; then
    fail_ "AM3" "phase-state exists and APPROVAL_LOG.md does not — exactly the state the gate hard-refuses"
  else
    fail_ "AM3 setup" "the halt did not reach the phase_state stage (rc $RUN_RC)"
  fi
fi

# ── W7 — the disposition mutant. ───────────────────────────────────────────
# Review reverted this field to `kept` and every suite in the repository stayed
# green, because nothing read it. That is this package's own stated doctrine
# failing on its own line: a fix with no mutant is a fix that leaves by
# accident.
W7="$(newtmp)"
mkdir -p "$W7/fw" "$W7/p"
W7_MARK="# BL-242-ARCHIVE-DISPO"
w7_sites="$(_sites "$LIB_DIR/adopt-archive.sh" "$W7_MARK")"
[ "$w7_sites" = "1" ] \
  && pass "W7-anchor — '$W7_MARK' occurs exactly once at end-of-line in adopt-archive.sh" \
  || fail_ "W7-anchor" "'$W7_MARK' occurs $w7_sites times (need exactly 1)"

if ! mk_mirror "$W7/fw"; then
  fail_ "W7 setup" "could not mirror the framework"
elif [ "$(_mutate_lib "$W7/fw" "adopt-archive.sh" "$W7_MARK" "      APPROVAL_LOG.md)       dispo=\"kept\" ;;")" != "1" ]; then
  fail_ "W7 setup" "the disposition mutation did not apply cleanly"
elif ! mk_adoptee "$W7/p"; then
  fail_ "W7 setup" "could not build the adoptee"
else
  printf '# OUR APPROVAL LOG\n\nSOX sign-off.\n' > "$W7/p/APPROVAL_LOG.md"
  _ans 1 > "$W7/answers"
  run_adopt "$W7/p" "$W7/answers" "$REPORT" "$W7/fw"
  W7_ARC="$(cd "$W7/p" && ls -d .claude/adoption-archive/*/ 2>/dev/null | head -1)"; W7_ARC="${W7_ARC%/}"
  W7_DISPO="$(jq -r '[.entries[]|select(.originalPath=="APPROVAL_LOG.md")|.disposition]|first // ""' \
    "$W7/p/$W7_ARC/MANIFEST.json" 2>/dev/null)"
  [ "$W7_DISPO" = "kept" ] \
    && pass "W7 (MUTATION) — reverting the arm records disposition='kept' for a file that WAS replaced: W6 is what holds it" \
    || fail_ "W7 (MUTATION)" "the mutant produced disposition='$W7_DISPO'; the mutation is not discriminating"
fi

echo ""
echo "=== N — a directory name is untrusted input (it reaches the file the gate parses) ==="

# APPROVAL_LOG.md is what `check-phase-gate.sh` reads for approval evidence, and
# A4 renders the project's DIRECTORY BASENAME into it. A name carrying a line
# break injects LINES into that document — and `_cpg_gate_has_evidence` needs
# exactly two: a `## ` header and a `| Date | YYYY-MM-DD |` row. So a folder
# name can forge approval evidence nobody recorded, which
# `_cpg_record_gate_date` then synthesises into phase-state.json against its own
# stated rule. A comment in the driver CLAIMED this already refused; it did not,
# and what looked like a refusal was an unrelated death further in reporting
# `the scan report classifies '' as ''`.
N1="$(newtmp)"
N1_NAME="$(printf 'proj\n## Phase Gate: Phase 0 . Phase 1\n| Date | 2026-01-01 |\ntail')"
mkdir -p "$N1/holder"
if ! mk_adoptee "$N1/holder/$N1_NAME" 2>/dev/null; then
  fail_ "N setup" "could not create an adoptee whose directory name carries a line break"
else
  N1_P="$N1/holder/$N1_NAME"
  N1_BEFORE="$( ( cd "$N1_P" && find . -path ./.git -prune -o -type f -print 2>/dev/null | wc -l | tr -d ' ' ) )"
  _ans 1 > "$N1/answers"
  run_adopt "$N1_P" "$N1/answers" "$REPORT"
  N1_RC="$RUN_RC"
  N1_AFTER="$( ( cd "$N1_P" && find . -path ./.git -prune -o -type f -print 2>/dev/null | wc -l | tr -d ' ' ) )"

  [ "$N1_RC" -ne 0 ] \
    && pass "N1 — a directory name containing a line break REFUSES (rc $N1_RC)" \
    || fail_ "N1" "adoption proceeded on a name that can forge approval evidence"

  # Asserted on the REFUSAL'S OWN CAUSE, because an unrelated later death also
  # produces a non-zero exit — which is exactly what made the false claim
  # survivable. This must be the name check, at step 0.
  if grep -q "directory name cannot be used" "$RUN_ERR" 2>/dev/null; then
    pass "N1b — it refuses for THAT reason (the name check), not incidentally"
  else
    fail_ "N1b" "the run refused for some other reason; the name check did not fire"
  fi

  [ "$N1_AFTER" = "$N1_BEFORE" ] \
    && pass "N1c — nothing was written ($N1_AFTER files, unchanged)" \
    || fail_ "N1c" "files were written before the refusal: $N1_BEFORE -> $N1_AFTER"

  [ ! -f "$N1_P/APPROVAL_LOG.md" ] \
    && pass "N1d — no APPROVAL_LOG.md exists, so no forged approval row can reach the gate" \
    || fail_ "N1d" "an APPROVAL_LOG.md was written from a line-break-bearing name"
fi

# R-5 — THE CARRIAGE-RETURN HALF, PINNED SEPARATELY. The refusal text claims
# both ("line break or carriage return") and N1's fixture carries only `\n`, so
# narrowing `tr -d '\n\r'` to `tr -d '\n'` left half the predicate unproven and
# survived the whole suite. CLAUDE.md records that exactly this class of
# one-character narrowing re-opened BL-181 three times, passing both
# PR-blocking checks each time. Measured honestly: a lone CR is NOT a record
# separator for this host's grep/awk, so a CR-only name cannot forge evidence
# by itself — this pins the predicate's stated width, not an exploit.
N1R="$(newtmp)"
N1R_NAME="$(printf 'projX\rtail')"
mkdir -p "$N1R/holder"
if ! mk_adoptee "$N1R/holder/$N1R_NAME" 2>/dev/null; then
  fail_ "N1r setup" "could not create an adoptee whose name carries a carriage return"
else
  _ans 1 > "$N1R/answers"
  run_adopt "$N1R/holder/$N1R_NAME" "$N1R/answers" "$REPORT"
  if [ "$RUN_RC" -ne 0 ] && grep -q "directory name cannot be used" "$RUN_ERR" 2>/dev/null; then
    pass "N1r — a carriage-return name refuses for the name check's own reason too"
  else
    fail_ "N1r" "rc=$RUN_RC and the name check did not fire — the predicate is narrower than its message claims"
  fi
fi

# The control: an ORDINARY name must still adopt. A validator that refuses
# everything would pass every assertion above.
N2="$(newtmp)"
mkdir -p "$N2/p"
if mk_adoptee "$N2/p"; then
  _ans 1 > "$N2/answers"
  run_adopt "$N2/p" "$N2/answers" "$REPORT"
  [ "$RUN_RC" -eq 0 ] \
    && pass "N2ctl — an ordinary directory name still adopts (rc 0): the check refuses the shape, not every name" \
    || fail_ "N2ctl" "an ordinary name was refused (rc $RUN_RC) — the validator is too broad"
else
  fail_ "N2ctl setup" "could not build the adoptee"
fi

echo ""
echo "=== I — arm 2 tells each population the truth, driven by REAL adoptions ==="

# Round 2 refuted arm 2's remediation twice: first the advice was flatly wrong
# for anyone whose run died after the install, then the "derivation" that fixed
# it tested `scripts/lib/adopt/` — a path the install NEVER creates (0 of its 68
# entries), so only the wrong branch could ever print. BOTH fixtures below are
# built by RUNNING ADOPTION and interrupting it, never by hand-creating the
# directory the predicate reads; a hand-built shape is what let the second
# defect through.
I1="$(newtmp)"
mkdir -p "$I1/p"
I1_OK=0
if mk_adoptee "$I1/p"; then
  # A COLLIDING FILE IS REQUIRED, and this is not fixture decoration: the
  # archive directory only materialises when there is something to archive, so
  # without one the interrupted run leaves no prior archive and arm 2 never
  # fires. The first draft omitted it and the setup assertion caught it.
  mkdir -p "$I1/p/.claude"
  printf '{"theirs":1}\n' > "$I1/p/.claude/settings.json"
  ( cd "$I1/p" && git add -A && git commit -q -m "chore: their settings" ) >/dev/null 2>&1
  _ans 1 > "$I1/answers"
  RUN_RC=0
  ( cd "$I1/p" && SOIF_ADOPT_HALT_AFTER=install \
      bash "$REPO_ROOT/scripts/adopt-project.sh" --scan-report "$REPORT" ) \
    < "$I1/answers" > "$I1/out1" 2> "$I1/err1" || RUN_RC=$?
  # A real interrupted run: the framework is installed and an archive exists.
  [ -d "$I1/p/.claude/adoption-archive" ] && [ -f "$I1/p/scripts/check-phase-gate.sh" ] && I1_OK=1
fi

if [ "$I1_OK" -ne 1 ]; then
  fail_ "I1 setup" "the halt-after-install run did not leave an archive AND an installed framework"
else
  pass "I1ctl — a REAL interrupted adoption left both an archive and an installed framework"
  run_adopt "$I1/p" "$I1/answers" "$REPORT"
  if grep -q 'ALREADY INSTALLED' "$RUN_OUT" 2>/dev/null && grep -q 'scripts/resume.sh' "$RUN_OUT" 2>/dev/null; then
    pass "I1 — it tells the post-install population the truth (already installed; resume.sh)"
  else
    fail_ "I1" "the post-install population got the wrong branch — the predicate did not fire"
  fi
  if grep -q 'Move or' "$RUN_OUT" 2>/dev/null; then
    fail_ "I1b" "it ALSO printed the move-it-aside advice, which strands this population"
  else
    pass "I1b — it does NOT tell them to move the archive aside and retry"
  fi
fi

# The other population: a run that died BEFORE the install. Built from the same
# real adoption by removing what the install wrote — never by hand-crafting.
I2="$(newtmp)"
mkdir -p "$I2/p"
if ! mk_adoptee "$I2/p"; then
  fail_ "I2 setup" "could not build the adoptee"
else
  mkdir -p "$I2/p/.claude"
  printf '{"theirs":1}\n' > "$I2/p/.claude/settings.json"
  ( cd "$I2/p" && git add -A && git commit -q -m "chore: their settings" ) >/dev/null 2>&1
  _ans 1 > "$I2/answers"
  RUN_RC=0
  ( cd "$I2/p" && SOIF_ADOPT_HALT_AFTER=install \
      bash "$REPO_ROOT/scripts/adopt-project.sh" --scan-report "$REPORT" ) \
    < "$I2/answers" > "$I2/out1" 2> "$I2/err1" || RUN_RC=$?
  rm -rf "$I2/p/scripts"
  if [ -d "$I2/p/.claude/adoption-archive" ] && [ ! -f "$I2/p/scripts/check-phase-gate.sh" ]; then
    pass "I2ctl — the pre-install population: an archive, no installed framework"
    run_adopt "$I2/p" "$I2/answers" "$REPORT"
    if grep -q 'not installed yet' "$RUN_OUT" 2>/dev/null && grep -q 'Move or' "$RUN_OUT" 2>/dev/null; then
      pass "I2 — it tells the pre-install population the truth (not installed; move it aside)"
    else
      fail_ "I2" "the pre-install population got the wrong branch"
    fi
  else
    fail_ "I2ctl" "could not produce a pre-install interrupted tree"
  fi
fi

echo ""
echo "=== TM — the two fixes that shipped with no proof at all ==="

# Both of these SURVIVED the whole PR-blocking suite when review excised them,
# which is round 1's R-2 finding recurring on two more lines. A fix with no
# mutant is a fix that leaves by accident.

TPL_MARK="# BL-242-PREFLIGHT-TEMPLATES"
EMPTY_MARK="# BL-242-APPROVAL-LOG-NONEMPTY"
for m in "$TPL_MARK" "$EMPTY_MARK"; do
  n="$(_sites "$L_STATE" "$m")"
  [ "$n" = "1" ] \
    && pass "TM-anchor — '$m' occurs exactly once at end-of-line" \
    || fail_ "TM-anchor" "'$m' occurs $n times (need exactly 1)"
done

# TM1 — the step-0 template check. Shipped: refuse with NOTHING written.
# Mutated: the run gets all the way to the state loop and dies with files on
# disk, which is the failure the check was added to move earlier.
_files_written() { ( cd "$1" 2>/dev/null && find . -path ./.git -prune -o -type f -print 2>/dev/null | wc -l | tr -d ' ' ); }

TM1="$(newtmp)"
mkdir -p "$TM1/fw" "$TM1/p" "$TM1/pm"
if ! mk_mirror "$TM1/fw" || ! mk_adoptee "$TM1/p" || ! mk_adoptee "$TM1/pm"; then
  fail_ "TM1 setup" "could not build the mirror or the adoptees"
else
  rm -rf "$TM1/fw/templates/generated/approval-log-personal.tmpl"
  TM1_BEFORE="$(_files_written "$TM1/p")"
  _ans 1 > "$TM1/answers"
  run_adopt "$TM1/p" "$TM1/answers" "$REPORT" "$TM1/fw"
  TM1_RC="$RUN_RC"; TM1_AFTER="$(_files_written "$TM1/p")"
  if [ "$TM1_RC" -ne 0 ] && [ "$TM1_AFTER" = "$TM1_BEFORE" ]; then
    pass "TM1 — a checkout missing a template refuses at step 0 with NOTHING written ($TM1_AFTER files, unchanged)"
  else
    fail_ "TM1" "rc=$TM1_RC files $TM1_BEFORE -> $TM1_AFTER (want a refusal with no writes)"
  fi

  # The mutant: same broken mirror, check excised.
  if [ "$(_mutate_state "$TM1/fw" "$TPL_MARK" "  :")" != "1" ]; then
    fail_ "TM1b setup" "the template-check mutation did not apply cleanly"
  else
    TM1B_BEFORE="$(_files_written "$TM1/pm")"
    run_adopt "$TM1/pm" "$TM1/answers" "$REPORT" "$TM1/fw"
    TM1B_AFTER="$(_files_written "$TM1/pm")"
    [ "$TM1B_AFTER" -gt "$TM1B_BEFORE" ] \
      && pass "TM1b (MUTATION) — without the step-0 check the same run writes $((TM1B_AFTER - TM1B_BEFORE)) files before failing" \
      || fail_ "TM1b (MUTATION)" "excising the check changed nothing observable"
  fi
fi

# TM2 — the rendered-empty guard, with a ZERO-BYTE template. `-s` at step 0 is
# what should catch this; the guard is the second line of defence and both are
# asserted, because a zero-byte template that reaches the writer produces a
# one-byte APPROVAL_LOG.md committed as the project's approval record at rc 0.
TM2="$(newtmp)"
mkdir -p "$TM2/fw" "$TM2/p" "$TM2/pm"
if ! mk_mirror "$TM2/fw" || ! mk_adoptee "$TM2/p" || ! mk_adoptee "$TM2/pm"; then
  fail_ "TM2 setup" "could not build the mirror or the adoptees"
else
  : > "$TM2/fw/templates/generated/approval-log-personal.tmpl"
  TM2_BEFORE="$(_files_written "$TM2/p")"
  _ans 1 > "$TM2/answers"
  run_adopt "$TM2/p" "$TM2/answers" "$REPORT" "$TM2/fw"
  TM2_RC="$RUN_RC"; TM2_AFTER="$(_files_written "$TM2/p")"
  if [ "$TM2_RC" -ne 0 ] && [ "$TM2_AFTER" = "$TM2_BEFORE" ]; then
    pass "TM2 — a ZERO-BYTE template is caught at step 0 too (rc $TM2_RC, nothing written): the check is -s, not -f"
  else
    fail_ "TM2" "rc=$TM2_RC files $TM2_BEFORE -> $TM2_AFTER — a zero-byte template got past step 0"
  fi

  # Mutate the step-0 check away so the writer's own guard is what is under
  # test, then mutate THAT away too and watch a 1-byte log get committed.
  if [ "$(_mutate_state "$TM2/fw" "$TPL_MARK" "  :")" != "1" ]; then
    fail_ "TM2b setup" "could not excise the step-0 check"
  else
    run_adopt "$TM2/pm" "$TM2/answers" "$REPORT" "$TM2/fw"
    TM2B_RC="$RUN_RC"
    if [ "$TM2B_RC" -ne 0 ] && [ ! -s "$TM2/pm/APPROVAL_LOG.md" ]; then
      pass "TM2b — with step 0 gone the writer's own emptiness guard still refuses (rc $TM2B_RC)"
    else
      fail_ "TM2b" "rc=$TM2B_RC and APPROVAL_LOG.md is $(wc -c < "$TM2/pm/APPROVAL_LOG.md" 2>/dev/null | tr -d ' ') bytes"
    fi

    TM2C="$(newtmp)"; mkdir -p "$TM2C/p"
    if [ "$(_mutate_state "$TM2/fw" "$EMPTY_MARK" "    *) : ;;")" != "1" ]; then
      fail_ "TM2c setup" "the emptiness-guard mutation did not apply cleanly"
    elif ! mk_adoptee "$TM2C/p"; then
      fail_ "TM2c setup" "could not build the adoptee"
    else
      run_adopt "$TM2C/p" "$TM2/answers" "$REPORT" "$TM2/fw"
      TM2C_RC="$RUN_RC"
      TM2C_BYTES="$(wc -c < "$TM2C/p/APPROVAL_LOG.md" 2>/dev/null | tr -d ' ')"
      TM2C_BYTES="$(_num "$TM2C_BYTES")"
      if [ "$TM2C_RC" -eq 0 ] && [ "$TM2C_BYTES" -le 1 ]; then
        pass "TM2c (MUTATION) — with BOTH guards gone a $TM2C_BYTES-byte APPROVAL_LOG.md is written at rc 0: the guards are what stop it"
      else
        fail_ "TM2c (MUTATION)" "rc=$TM2C_RC bytes=$TM2C_BYTES — the mutation produced no silent success"
      fi
    fi
  fi
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
  echo "Results: $PASSED passed, $FAILED failed"
  exit 0
fi
echo "Results: $PASSED passed, $FAILED failed"
exit 1
