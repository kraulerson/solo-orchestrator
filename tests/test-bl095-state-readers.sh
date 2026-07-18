#!/usr/bin/env bash
# tests/test-bl095-state-readers.sh — BL-095 (ergonomics F4): ONE state-parsing
# surface for deployment/poc_mode instead of nine inline variants.
#
# WHY THIS EXISTS
#   Nine files parsed `deployment`/`poc_mode` from phase-state inline — three
#   DIFFERENT grep-sed variants, plain jq, and a jq-with-grep-fallback dual —
#   and the duplication already produced the BL-084 null/production
#   mishandling class. The readers live in scripts/lib/helpers-core.sh
#   (`# BL-095-STATE-READERS`): the ONE lib every gate consumer already
#   sources and every fixture already copies, so centralizing there adds no
#   new sourcing surface and no fixture churn. Parsing is centralized;
#   per-gate PREDICATES (BL-084 vs BL-086 semantics) deliberately stay put.
#
# WHAT THIS PROVES
#   Unit contract of soif_read_phase_state_key / soif_read_deployment /
#   soif_read_poc_mode: value read; JSON null → default; absent key →
#   default; missing file → default; caller-chosen default honored (the
#   check-phase-gate deployment site defaults "personal", others "");
#   jq-ABSENT hosts take the grep fallback (PATH stub) with the SAME null
#   semantics (unquoted null never matches the quoted-value grep). Consumer
#   routing is proven by the migration suites staying green PLUS the
#   in-suite key-typo mutation: breaking the helper's key lookup must break
#   a real check-phase-gate read (proves the gate actually routes through
#   the helper, not a leftover inline parse).
#
# REGISTRATION: no init.sh, not an aggregator → BOTH lists. Hermetic.
# bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CORE="$REPO_ROOT/scripts/lib/helpers-core.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# The lib must define the readers at all.
if ! grep -q "soif_read_phase_state_key" "$CORE" 2>/dev/null; then
  fail_ "T-readers-exist" "scripts/lib/helpers-core.sh does not define soif_read_phase_state_key (BL-095: the nine inline parses have no shared surface)"
  echo ""
  echo "Results: $PASSED passed, $FAILED failed"
  exit 1
fi
pass "T-readers-exist"

# Source in a subshell-friendly way: helpers-core may set -u guards etc.
# shellcheck source=/dev/null
. "$CORE"

S1="$TOPTMP/s1.json"
cat > "$S1" <<'EOF'
{"current_phase":2,"track":"standard","deployment":"organizational","poc_mode":"sponsored_poc"}
EOF
S2="$TOPTMP/s2.json"
cat > "$S2" <<'EOF'
{"current_phase":1,"track":"light","deployment":"personal","poc_mode":null}
EOF
S3="$TOPTMP/s3.json"
cat > "$S3" <<'EOF'
{"current_phase":0,"track":"light"}
EOF

echo "=== T-value-read ==="
d=$(soif_read_deployment "$S1"); p=$(soif_read_poc_mode "$S1")
if [ "$d" = "organizational" ] && [ "$p" = "sponsored_poc" ]; then
  pass "T-value-read"
else
  fail_ "T-value-read" "got deployment='$d' poc_mode='$p' (want organizational/sponsored_poc)"
fi

echo "=== T-null-is-default ==="
p=$(soif_read_poc_mode "$S2"); p2=$(soif_read_poc_mode "$S2" "unset-default")
if [ "$p" = "" ] && [ "$p2" = "unset-default" ]; then
  pass "T-null-is-default"
else
  fail_ "T-null-is-default" "JSON null must yield the caller default (got '$p' / '$p2') — the BL-084 null-mishandling class"
fi

echo "=== T-absent-key-is-default ==="
d=$(soif_read_deployment "$S3" "personal"); p=$(soif_read_poc_mode "$S3")
if [ "$d" = "personal" ] && [ "$p" = "" ]; then
  pass "T-absent-key-is-default"
else
  fail_ "T-absent-key-is-default" "absent keys must yield defaults (got deployment='$d' poc_mode='$p')"
fi

echo "=== T-missing-file-is-default ==="
d=$(soif_read_deployment "$TOPTMP/nope.json" "personal"); rc=$?
if [ "$rc" -eq 0 ] && [ "$d" = "personal" ]; then
  pass "T-missing-file-is-default"
else
  fail_ "T-missing-file-is-default" "rc=$rc d='$d' — a missing state file must never error, only default"
fi

echo "=== T-nojq-fallback ==="
# PATH stub: hide jq entirely; the grep fallback must read values AND keep
# null semantics (unquoted null cannot match the quoted-value grep → default).
STUB="$TOPTMP/stubbin"; mkdir -p "$STUB"
for tool in bash grep sed head cat; do
  real=$(command -v "$tool") && ln -s "$real" "$STUB/$tool" 2>/dev/null
done
out=$(env PATH="$STUB" bash -c ". '$CORE'; soif_read_deployment '$S1'; echo; soif_read_poc_mode '$S2' 'nulled'" 2>/dev/null)
v1=$(printf '%s' "$out" | sed -n '1p'); v2=$(printf '%s' "$out" | sed -n '2p')
if [ "$v1" = "organizational" ] && [ "$v2" = "nulled" ]; then
  pass "T-nojq-fallback"
else
  fail_ "T-nojq-fallback" "without jq: deployment='$v1' (want organizational), null poc_mode='$v2' (want default 'nulled')"
fi

# ── Consumer closure: the four MIGRATED files must contain NO inline reader ──
# parses and check-phase-gate must actually CALL the helpers. Writers
# (`jq '.poc_mode = …'`) and the documented conforming-inline files
# (pre-commit-gate.sh — hook surface must not grow a sourcing dependency;
# run-phase3-validation.sh — self-contained by design) are exempt BY NOT
# BEING IN THIS LIST; their inline reads are named as sync-siblings at the
# # BL-095-STATE-READERS fence.
#
# Detector (E/F verifier A5 — widened): the original pattern caught only the
# canonical single-quoted spellings; `jq -r ".deployment"`, `jq '.deployment'`
# (no -r), `.["deployment"]`, double-quoted grep patterns, and
# `--arg`-style reads all slipped past. Now: ANY line mentioning jq or
# `grep -o` that also mentions deployment/poc_mode is a hit, minus the
# helper calls themselves, BL-095-marked lines, and writer assignments.
# The self-test below runs the SAME function over a probe file carrying the
# verifier's escape variants — detector blindness is loud, not silent.
bl095_detect_inline_readers() {
  # Exemptions, in order: comment lines; BL-095-marked lines; helper calls;
  # writer assignments (`.poc_mode = …`); and `--arg X "$shellvar"` lines,
  # which pass an ALREADY-READ shell variable INTO jq (composition, not a
  # parse) — while `--arg k deployment` (a literal KEY name) stays caught.
  grep -nE '(jq|grep -o)' "$1" 2>/dev/null \
    | grep -E '(deployment|poc_mode)' \
    | grep -vE '^[0-9]+:[[:space:]]*#' \
    | grep -v 'BL-095' \
    | grep -v 'soif_read_' \
    | grep -vE '\.(deployment|poc_mode)"?\]?[[:space:]]*=([^=]|$)' \
    | grep -vE -- '--arg [A-Za-z_]+ "\$' || true
}

echo "=== T-detector-sees-escape-variants ==="
PROBE="$TOPTMP/detector-probe.sh"
cat > "$PROBE" <<'EOF'
a=$(jq -r '.deployment // ""' f.json)
b=$(jq -r ".deployment" f.json)
c=$(jq '.poc_mode' f.json)
d=$(jq -r '.["deployment"]' f.json)
e=$(jq -r --arg k deployment '.[$k]' f.json)
f=$(grep -o '"poc_mode"[[:space:]]*:' f.json)
g=$(grep -o "\"deployment\"[[:space:]]*:" f.json)
legit1=$(soif_read_deployment f.json)   # helper call: jq-free, must NOT hit
jq '.poc_mode = null' f.json > tmp      # writer: must NOT hit
EOF
nhits=$(bl095_detect_inline_readers "$PROBE" | grep -c .)
if [ "$nhits" -eq 7 ]; then
  pass "T-detector-sees-escape-variants (7/7 escape spellings caught, writer + helper exempt)"
else
  fail_ "T-detector-sees-escape-variants" "detector caught $nhits of 7 escape variants (verifier A5: a reintroduced inline parse in an uncaught spelling passes the tripwire silently): $(bl095_detect_inline_readers "$PROBE" | head -8 | tr '\n' ' ')"
fi

echo "=== T-no-inline-parse-left ==="
leftovers=""
for f in scripts/check-phase-gate.sh scripts/process-checklist.sh scripts/upgrade-project.sh scripts/intake-wizard.sh; do
  hits=$(bl095_detect_inline_readers "$REPO_ROOT/$f")
  [ -n "$hits" ] && leftovers="$leftovers
$f: $(printf '%s' "$hits" | head -3 | tr '\n' ' ')"
done
if [ -z "$leftovers" ] \
   && grep -q "soif_read_poc_mode" "$REPO_ROOT/scripts/check-phase-gate.sh" \
   && grep -q "soif_read_deployment" "$REPO_ROOT/scripts/check-phase-gate.sh"; then
  pass "T-no-inline-parse-left"
else
  fail_ "T-no-inline-parse-left" "inline deployment/poc_mode reader parses remain in migrated files (or check-phase-gate never calls the helpers):$leftovers"
fi

# ── Mutation: excising the reader fence must CRASH a migrated consumer ───────
# (bl104-style copy-mutant with lib siblings beside it, asserted POSITIVELY in
# both directions: baseline must SUCCEED, the fence-excised mutant must FAIL —
# so a fixture that crashes for unrelated reasons cannot vacuously pass).
echo "=== T-fence-excision-breaks-consumer ==="
FIX="$TOPTMP/proj"
mkdir -p "$FIX/.claude" "$FIX/scripts/lib" "$FIX/docs"
( cd "$FIX" && git init -q && git config user.email t@t.invalid && git config user.name t \
    && echo x > seed && git add seed && git commit -q -m "chore: init" ) || true
cat > "$FIX/.claude/phase-state.json" <<'EOF'
{"current_phase":0,"track":"standard","deployment":"organizational","poc_mode":"sponsored_poc","gates":{}}
EOF
printf '# Approval Log\n' > "$FIX/APPROVAL_LOG.md"
cp "$REPO_ROOT/scripts/check-phase-gate.sh" "$FIX/scripts/"
cp "$REPO_ROOT/scripts/lib/"*.sh "$FIX/scripts/lib/"
base_rc=0
( cd "$FIX" && bash scripts/check-phase-gate.sh >/dev/null 2>&1 ) || base_rc=$?
sed '/# BL-095-STATE-READERS-BEGIN/,/# BL-095-STATE-READERS-END/d' \
  "$REPO_ROOT/scripts/lib/helpers-core.sh" > "$FIX/scripts/lib/helpers-core.sh"
mut_out=$( cd "$FIX" && bash scripts/check-phase-gate.sh 2>&1 ); mut_rc=$?
if [ "$base_rc" -eq 0 ] && [ "$mut_rc" -ne 0 ] && printf '%s' "$mut_out" | grep -q "soif_read"; then
  pass "T-fence-excision-breaks-consumer (the gate dies naming the missing reader — it routes through the fence)"
else
  fail_ "T-fence-excision-breaks-consumer" "base_rc=$base_rc mut_rc=$mut_rc — either the baseline fixture is broken (vacuous) or the gate does not route through the # BL-095-STATE-READERS fence: $(printf '%s' "$mut_out" | tail -1)"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
