#!/usr/bin/env bash
# tests/test-bl253-adoption-state-parity.sh
#
# `## BL-253:` — an ADOPTED project must be born with the same state an
# init.sh-SCAFFOLDED one is born with. The design's headline promise
# (docs/designs/2026-08-23-brownfield-adoption-v2.md: "indistinguishable from a
# scaffolded project in what the gates demand") was asserted in two documents
# and executed by no test, and the one key it got wrong was the tier key's
# second half: init.sh writes `poc_mode: null` for a production project
# (`poc_json="null"` in create_project; `poc_mode:null` in
# prepare_initial_state_for_commit), adoption wrote the STRING "production",
# and every reader treats a non-null value as the NAME OF A POC MODE — so
# `process-checklist.sh --start-phase4` refused every adoptee ("project is in
# production mode… run --to-production"), and the organizational Pre-Phase-0
# guard in check-phase-gate.sh, keyed on `poc_mode` being null, skipped its six
# pre-conditions for every organizational adoptee. Reproduced on main c61edb1,
# both tiers, by the 2026-09-08 codebase review's second pass.
#
# THE ORACLE IS init.sh's OWN EMITTER, READ AS SOURCE — NEVER EXECUTED. init.sh
# ends in an unconditional `main "$@"`, so it cannot be sourced for its
# functions, and running it needs ~/.claude-dev-framework plus network, which
# would make this suite non-hermetic and full-lane-only. Instead the
# phase-state heredoc is lifted out of create_project by its `PHEOF` fence,
# its shell interpolations substituted with the values adoption would use, and
# the result parsed with jq. If init.sh's emitter moves or changes shape, O0
# fails LOUDLY and says so — that is the canary, not a defect in this suite.
# This file therefore NAMES init.sh on executed lines (the awk below) and is
# registered in the tests.yml unit lane by hand: it reads init.sh, it never
# invokes it.
#
# MUTATION HARNESS STANDARD (inherited from the WP9a/9b/10a suites): every
# mutant is applied to a MIRROR of the framework, never the real tree; every
# marker is asserted unique and end-of-line anchored (MP0) so a mutation cannot
# silently hit a second site; every mutant must parse (`bash -n`) and must
# have changed the file (>=2 diff lines) or the case fails as a setup error.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRIVER="$REPO_ROOT/scripts/adopt-project.sh"
LIB_DIR="$REPO_ROOT/scripts/lib/adopt"
L_STATE="$LIB_DIR/adopt-state.sh"

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

if [ ! -f "$DRIVER" ]; then
  echo "  [FAIL] setup — $DRIVER not found"; echo ""; echo "Results: 0 passed, 1 failed"; exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "  [FAIL] setup — jq is required by this suite"; echo ""; echo "Results: 0 passed, 1 failed"; exit 1
fi

# ── Fixtures (same adoptee the WP4/WP10a suites drive) ──────────────────────
mk_adoptee() {
  local p="$1"
  mkdir -p "$p/src" "$p/docs" || return 1
  ( cd "$p" \
      && git init -q . \
      && git config user.email "bl253@test.invalid" \
      && git config user.name  "BL253 Test" \
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
if mk_adoptee "$TEMPLATE" \
   && bash "$REPO_ROOT/scripts/scout.sh" --root "$TEMPLATE" --out "$TOPTMP/scan" >/dev/null 2>&1 \
   && [ -s "$TOPTMP/scan/scout-report.json" ]; then
  REPORT="$TOPTMP/scan/scout-report.json"
else
  echo "  [FAIL] setup — scripts/scout.sh produced no report"; echo ""; echo "Results: 0 passed, 1 failed"; exit 1
fi

# Five answers: the tier question (1 personal / 2 organizational) plus this
# report's four scan-derived confirmations.
_ans() { local tier="${1:-1}"; printf '%s\n1\n1\n1\n1\n' "$tier"; }

RUN_RC=0; RUN_OUT=""; RUN_ERR=""
# run_adopt <dir> <answers> <report> [fw] — the scanner probe is pinned to a
# binary every host has (`sh`) so BL-251's fast path fires and the resolver is
# never consulted: this suite is about STATE, not tools, and must not depend on
# what the host has installed.
run_adopt() {
  local dir="$1" answers="$2" report="$3" fw="${4:-$REPO_ROOT}"
  RUN_RC=0
  RUN_OUT="$(dirname "$answers")/run-out"
  RUN_ERR="$(dirname "$answers")/run-err"
  ( cd "$dir" && env SOIF_ADOPT_SCANNER_BIN=sh bash "$fw/scripts/adopt-project.sh" --scan-report "$report" ) \
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

_mutate() {   # _mutate <mirror> <lib> <marker> <replacement>
  local mir="$1" lib="$2" mark="$3" repl="$4" before after changed
  before="$(mktemp)"; cp "$mir/scripts/lib/adopt/$lib" "$before"
  # THE DELIMITER IS ABSENT FROM PATTERN AND REPLACEMENT — CLAUDE.md's sed trap,
  # met head-on: a first cut used '#', which every marker contains, so all three
  # mutations silently failed to apply and the setup guard caught it. No marker
  # or replacement in this suite carries '|'; the >=2-changed-lines check below
  # is what proves the edit applied rather than trusting sed's exit status.
  _sed_inplace "$mir/scripts/lib/adopt/$lib" "s|^.*${mark}\$|${repl}|"
  after="$mir/scripts/lib/adopt/$lib"
  changed="$(_changed_lines "$before" "$after")"
  rm -f "$before"
  [ "$changed" -ge 2 ] || { printf '0\n'; return 0; }
  [ "$(_parses "$after")" = "1" ] || { printf '0\n'; return 0; }
  printf '1\n'
}

# adopt_one <tier> → sets ADOPTED (dir) or fails loudly; the caller asserts.
ADOPTED=""
adopt_one() {
  local tier="$1" fw="${2:-$REPO_ROOT}" d
  d="$(newtmp)"; mkdir -p "$d/p"
  mk_adoptee "$d/p" || { fail_ "setup" "could not build the adoptee"; return 1; }
  _ans "$tier" > "$d/answers"
  run_adopt "$d/p" "$d/answers" "$REPORT" "$fw"
  [ "$RUN_RC" -eq 0 ] || { fail_ "setup" "adoption (tier $tier) exited $RUN_RC — see $RUN_ERR"; return 1; }
  [ -f "$d/p/.claude/phase-state.json" ] || { fail_ "setup" "adoption wrote no phase-state.json"; return 1; }
  ADOPTED="$d/p"
  return 0
}

echo "=== O — the oracle: init.sh's phase-state emitter, read as source ==="

# O0 — lift the heredoc out of create_project by its PHEOF fence and parse it
# with adoption's values in place of the shell interpolations. A production,
# personal, full-track project named like the fixture — exactly what adoption
# writes for tier 1.
ORACLE_PS=""
ORACLE_PS="$(awk '/cat > \.claude\/phase-state\.json << PHEOF/{f=1;next} /^PHEOF$/{f=0} f{print}' "$REPO_ROOT/init.sh" \
  | sed -e 's/"\$PROJECT_NAME"/"acme-api"/' -e 's/"\$TRACK"/"full"/' -e 's/"\$DEPLOYMENT"/"personal"/' -e 's/\$poc_json/null/' \
  | jq -c . 2>/dev/null)"
if [ -n "$ORACLE_PS" ]; then
  pass "O0 — init.sh's phase-state heredoc was lifted and parses (the oracle exists)"
else
  fail_ "O0" "init.sh's phase-state emitter has moved or changed shape — re-derive this suite's oracle before trusting anything below"
fi

# O1 — provenance pins: the two literals this suite's parity claim rests on.
# If either goes, the oracle above may still parse while meaning something
# else, so they are pinned by name.
[ "$(grep -c 'poc_json="null"' "$REPO_ROOT/init.sh")" -ge 1 ] \
  && pass "O1 — init.sh still writes poc_json=\"null\" for a production project (phase-state)" \
  || fail_ "O1" "init.sh no longer writes poc_json=\"null\" — the phase-state half of the oracle is unanchored"
[ "$(grep -c 'poc_mode:null' "$REPO_ROOT/init.sh")" -ge 2 ] \
  && pass "O1b — init.sh still writes poc_mode:null for a production manifest (both branches)" \
  || fail_ "O1b" "init.sh no longer writes poc_mode:null in prepare_initial_state_for_commit — the manifest half of the oracle is unanchored"

echo "=== P — parity: an adopted project is born with a scaffolded project's state ==="

# P1 — personal tier.
if adopt_one 1; then
  P1="$ADOPTED"
  if jq -e '.poc_mode == null' "$P1/.claude/phase-state.json" >/dev/null 2>&1; then
    pass "P1 — adopted phase-state.json carries poc_mode: null, as init.sh writes for production"
  else
    fail_ "P1" "adopted phase-state.json has poc_mode $(jq -c '.poc_mode' "$P1/.claude/phase-state.json") — init.sh writes null; every reader takes a non-null value as a POC mode name"
  fi
  if jq -e '.poc_mode == null' "$P1/.claude/manifest.json" >/dev/null 2>&1; then
    pass "P1b — adopted manifest.json carries poc_mode: null"
  else
    fail_ "P1b" "adopted manifest.json has poc_mode $(jq -c '.poc_mode' "$P1/.claude/manifest.json" 2>/dev/null) — init.sh writes null"
  fi
  # key-by-key against the oracle, allowing only what adoption adds on top
  if [ -n "$ORACLE_PS" ]; then
    ok_keys="$(printf '%s' "$ORACLE_PS" | jq -r 'keys | sort | join(",")')"
    ad_keys="$(jq -r 'del(.adoption) | keys | sort | join(",")' "$P1/.claude/phase-state.json")"
    [ "$ok_keys" = "$ad_keys" ] \
      && pass "P1c — adopted phase-state.json has exactly init.sh's key set (minus .adoption)" \
      || fail_ "P1c" "key sets differ — init.sh: [$ok_keys]  adoption: [$ad_keys]"
    # the constants a fresh project is born with must be byte-equal
    diffs="$(jq -rn --argjson o "$ORACLE_PS" --slurpfile a "$P1/.claude/phase-state.json" \
      '[ "framework_version","current_phase","track","deployment","poc_mode","compliance_ready","review_gate_enforced","gates" ]
       | map(select($o[.] != $a[0][.])) | join(",")')"
    [ -z "$diffs" ] \
      && pass "P1d — every birth constant equals init.sh's (framework_version, phase, track, tier key, flags, gates)" \
      || fail_ "P1d" "these keys differ from init.sh's birth values: $diffs"
  fi
  # the manifest's tier keys are the set init.sh writes
  if jq -e 'has("host") and has("mode") and has("remote_url") and has("deployment") and has("poc_mode") and has("enforcement_level")' "$P1/.claude/manifest.json" >/dev/null 2>&1; then
    pass "P1e — adopted manifest.json carries init.sh's six tier/host keys"
  else
    fail_ "P1e" "adopted manifest.json is missing one of init.sh's six keys: $(jq -c 'keys' "$P1/.claude/manifest.json" 2>/dev/null)"
  fi

  # P2 — the consumer that turned the string into a dead end.
  P2_OUT="$( cd "$P1" && bash scripts/process-checklist.sh --start-phase4 </dev/null 2>&1 )" || true
  if printf '%s' "$P2_OUT" | grep -q "project is in production mode"; then
    fail_ "P2" "process-checklist.sh --start-phase4 refuses the adoptee as a POC: 'project is in production mode'"
  else
    pass "P2 — process-checklist.sh --start-phase4 does not read the adoptee as a POC"
  fi
fi

# P3 — organizational tier: the Pre-Phase-0 guard must FIRE. It is keyed on
# poc_mode being null; with the string it was silently skipped.
if adopt_one 2; then
  P3="$ADOPTED"
  jq -e '.deployment == "organizational"' "$P3/.claude/phase-state.json" >/dev/null 2>&1 \
    || fail_ "P3 setup" "tier 2 did not land as organizational"
  P3_OUT="$( cd "$P3" && bash scripts/check-phase-gate.sh --gate phase_0_to_1 </dev/null 2>&1 )" || true
  if printf '%s' "$P3_OUT" | grep -q "Pre-Phase 0"; then
    pass "P3 — an organizational adoptee is held to the six Pre-Phase-0 pre-conditions"
  else
    fail_ "P3" "the organizational Pre-Phase-0 guard did not fire for the adoptee — six pre-conditions skipped"
  fi
  jq -e '.poc_mode == null' "$P3/.claude/phase-state.json" >/dev/null 2>&1 \
    && pass "P3b — organizational adoptee's phase-state.json carries poc_mode: null" \
    || fail_ "P3b" "organizational adoptee's poc_mode is $(jq -c '.poc_mode' "$P3/.claude/phase-state.json")"
fi

echo "=== MP — mutation proofs ==="

MP_MODE="# BL-253-POC-MODE"
MP_NULL="# BL-253-POC-NULL"
MP_NULL_M="# BL-253-POC-NULL-MANIFEST"

# MP0 — the markers are unique and end-of-line anchored.
for _m in "$MP_MODE" "$MP_NULL" "$MP_NULL_M"; do
  _n="$(_sites "$L_STATE" "$_m")"
  [ "$_n" = "1" ] \
    && pass "MP0 — '$_m' occurs exactly once at end-of-line in adopt-state.sh" \
    || fail_ "MP0" "'$_m' occurs $_n times in adopt-state.sh (need exactly 1)"
done

# MP1 — restore the string and both consumers must regress: P2's dead end
# returns and P3's guard goes quiet.
MP1="$(newtmp)"; mkdir -p "$MP1/fw"
if ! mk_mirror "$MP1/fw"; then
  fail_ "MP1 setup" "could not mirror the framework"
elif [ "$(_mutate "$MP1/fw" "adopt-state.sh" "$MP_MODE" "ADOPT_POC_MODE=\"production\"   $MP_MODE")" != "1" ]; then
  fail_ "MP1 setup" "the poc-mode mutation did not apply cleanly"
else
  if adopt_one 1 "$MP1/fw"; then
    M1="$ADOPTED"
    M1_OUT="$( cd "$M1" && bash scripts/process-checklist.sh --start-phase4 </dev/null 2>&1 )" || true
    printf '%s' "$M1_OUT" | grep -q "project is in production mode" \
      && pass "MP1 (MUTATION) — with the string restored, --start-phase4 refuses the adoptee again: P2 is what stops it" \
      || fail_ "MP1 (MUTATION)" "restoring the string did not bring the dead end back — P2 may be passing for another reason"
  fi
  if adopt_one 2 "$MP1/fw"; then
    M1o="$ADOPTED"
    M1o_OUT="$( cd "$M1o" && bash scripts/check-phase-gate.sh --gate phase_0_to_1 </dev/null 2>&1 )" || true
    printf '%s' "$M1o_OUT" | grep -q "Pre-Phase 0" \
      && fail_ "MP1b (MUTATION)" "restoring the string did not silence the Pre-Phase-0 guard — P3 may be passing for another reason" \
      || pass "MP1b (MUTATION) — with the string restored, the organizational guard goes quiet again: P3 is what stops it"
  fi
fi

# MP2 — write "" instead of null in phase-state: the readers forgive it, the
# parity oracle must not. This is what proves the null emission is
# load-bearing and not just the constant.
MP2="$(newtmp)"; mkdir -p "$MP2/fw"
if ! mk_mirror "$MP2/fw"; then
  fail_ "MP2 setup" "could not mirror the framework"
elif [ "$(_mutate "$MP2/fw" "adopt-state.sh" "$MP_NULL" "  local poc_json='\"\"'   $MP_NULL")" != "1" ]; then
  fail_ "MP2 setup" "the phase-state null mutation did not apply cleanly"
elif adopt_one 1 "$MP2/fw"; then
  jq -e '.poc_mode == null' "$ADOPTED/.claude/phase-state.json" >/dev/null 2>&1 \
    && fail_ "MP2 (MUTATION)" "writing \"\" still yielded null — P1 may be passing for another reason" \
    || pass "MP2 (MUTATION) — with \"\" written, phase-state.json no longer matches init.sh: P1 is what stops it"
fi

# MP3 — the same for the manifest writer.
MP3="$(newtmp)"; mkdir -p "$MP3/fw"
if ! mk_mirror "$MP3/fw"; then
  fail_ "MP3 setup" "could not mirror the framework"
elif [ "$(_mutate "$MP3/fw" "adopt-state.sh" "$MP_NULL_M" "  local poc_json='\"\"'   $MP_NULL_M")" != "1" ]; then
  fail_ "MP3 setup" "the manifest null mutation did not apply cleanly"
elif adopt_one 1 "$MP3/fw"; then
  jq -e '.poc_mode == null' "$ADOPTED/.claude/manifest.json" >/dev/null 2>&1 \
    && fail_ "MP3 (MUTATION)" "writing \"\" still yielded null in the manifest — P1b may be passing for another reason" \
    || pass "MP3 (MUTATION) — with \"\" written, manifest.json no longer matches init.sh: P1b is what stops it"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] && exit 0
exit 1
