#!/usr/bin/env bash
# tests/test-bl128-review-generator-headless.sh — BL-128 (Dogfood-2 F-DF2-015):
# the six-eval review generator must be viable for HEADLESS/agent operation.
#
# WHY THIS EXISTS
#   run-reviews.sh parses (BL-103) but never COMPLETED in practice: each
#   review is an UNBOUNDED nested `claude -p` (observed: ~40 min, ~159
#   orphaned claude processes, zero review files, zero manifest); a mid-run
#   trust-dialog block or spend-limit kill died SILENTLY (set -e aborted the
#   whole suite at the first failed review, so no manifest was ever written);
#   and there was no way to produce the manifest without the generator
#   driving six live sessions. The Phase 3→4 review gate's only documented
#   remediation therefore pushed operators to SOLO_REVIEWERS_ATTESTED not by
#   choice but because the happy path did not terminate.
#
# WHAT THIS PROVES (claude is a PATH stub throughout — hermetic, no network,
# no real sessions; the stub's call-N behavior comes from a plan file):
#   T-compose-only-no-claude   --compose-only writes every composed prompt to
#                              docs/eval-results/prompts/ and NEVER invokes
#                              claude (works with no usable claude at all).
#   T-assemble-manifest        --assemble-manifest builds + validates the
#                              manifest from review files already on disk
#                              (operator/agent ran the prompts elsewhere) —
#                              no claude invocation.
#   T-timeout-kills-group      a hanging review is killed at
#                              REVIEW_TIMEOUT_SECS — INCLUDING its spawned
#                              grandchildren (the 159-orphan defect) — the
#                              run reports the timeout and carries on.
#   T-failure-surfaced         a review dying with a spend/usage-limit error
#                              does NOT abort the suite: the error is
#                              surfaced with actionable guidance, later
#                              reviews still run, the manifest still lands.
#   T-incremental-manifest     the manifest is (re)written after EACH
#                              completed review — proven by the reviewer-2
#                              stub OBSERVING reviewer-1's entry already on
#                              disk before it hangs.
#
# REGISTRATION: no init.sh, not an aggregator → BOTH lists. bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$REPO_ROOT/evaluation-prompts/Projects/run-reviews.sh"
REVIEWS_DIR="$REPO_ROOT/evaluation-prompts/Projects"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq required (manifest assembly + assertions)"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# ── the claude stub ──────────────────────────────────────────────────────────
# Behavior per CALL NUMBER from $STUB_DIR/plan (one line per call):
#   write:<file>      create <file> in cwd (the PROJECT_DIR), exit 0
#   fail:<msg>        print <msg> to stderr, exit 1
#   hang:<secs>       spawn `sleep 30 &` grandchild (pid recorded), sleep, exit 0
#   hangcheck:<secs>  if the manifest already lists cio-review-v1.md, touch
#                     witness; then sleep (to be timed out)
#   trap              record the call and exit 97 (must never be reached)
STUBBIN="$TOPTMP/stubbin"; mkdir -p "$STUBBIN"
cat > "$STUBBIN/claude" <<'STUB'
#!/usr/bin/env bash
n=$(cat "$STUB_DIR/count" 2>/dev/null || echo 0); n=$((n+1)); printf '%s' "$n" > "$STUB_DIR/count"
plan=$(sed -n "${n}p" "$STUB_DIR/plan" 2>/dev/null)
case "$plan" in
  write:*)     printf 'stub review body\n' > "${plan#write:}"; exit 0 ;;
  fail:*)      printf '%s\n' "${plan#fail:}" >&2; exit 1 ;;
  hang:*)      sleep 30 & printf '%s' "$!" > "$STUB_DIR/gc.pid"; sleep "${plan#hang:}"; exit 0 ;;
  hangcheck:*) if jq -e '.reviews[] | select(.artifact=="cio-review-v1.md")' docs/eval-results/review-manifest.json >/dev/null 2>&1; then touch "$STUB_DIR/witness"; fi; sleep "${plan#hangcheck:}"; exit 0 ;;
  trap|*)      touch "$STUB_DIR/claude-called"; exit 97 ;;
esac
STUB
chmod +x "$STUBBIN/claude"

# mk_proj <dir> — a scratch PROJECT_DIR (git for provenance realism).
mk_proj() {
  local d="$1"
  mkdir -p "$d"
  ( cd "$d" && git init -q && git config user.email t@t.invalid && git config user.name t \
      && echo x > seed && git add seed && git commit -q -m "chore: init" ) || return 1
}

# run_runner <projdir> <stubdir> <timeout-or-empty> <args...>
run_runner() {
  local proj="$1" sd="$2" tmo="$3"; shift 3
  ( cd "$proj" && env PATH="$STUBBIN:$PATH" STUB_DIR="$sd" PROJECT_DIR="$proj" \
      REVIEW_DIR="$REVIEWS_DIR" REVIEW_TIMEOUT_SECS="${tmo:-900}" \
      bash "$RUNNER" "$@" 2>&1 )
}

# ── T1: --compose-only writes prompts, never calls claude ────────────────────
echo "=== T-compose-only-no-claude ==="
P1="$TOPTMP/p1"; SD1="$TOPTMP/sd1"; mkdir -p "$SD1"; mk_proj "$P1"
printf 'trap\ntrap\ntrap\ntrap\ntrap\ntrap\n' > "$SD1/plan"
out=$(run_runner "$P1" "$SD1" "" --compose-only web-app); rc=$?
nprompts=$(ls -1 "$P1/docs/eval-results/prompts/"*-prompt.md 2>/dev/null | wc -l | tr -d ' ')
if [ "$rc" -eq 0 ] && [ "$nprompts" = "6" ] && [ ! -f "$SD1/claude-called" ]; then
  pass "T-compose-only-no-claude"
else
  fail_ "T-compose-only-no-claude" "rc=$rc prompts=$nprompts claude-called=$([ -f "$SD1/claude-called" ] && echo YES || echo no) — --compose-only must emit all composed prompts and never start a session: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── T2: --assemble-manifest from files already on disk, no claude ────────────
echo "=== T-assemble-manifest ==="
P2="$TOPTMP/p2"; SD2="$TOPTMP/sd2"; mkdir -p "$SD2"; mk_proj "$P2"
printf 'trap\ntrap\n' > "$SD2/plan"
printf 'cio review\n'   > "$P2/cio-review-v1.md"
printf 'legal review\n' > "$P2/legal-review-v1.md"
out=$(run_runner "$P2" "$SD2" "" --assemble-manifest web-app 2 4); rc=$?
nrev=$(jq -r '.reviews | length' "$P2/docs/eval-results/review-manifest.json" 2>/dev/null || echo 0)
case "$nrev" in ''|*[!0-9]*) nrev=0 ;; esac
if [ "$rc" -eq 0 ] && [ "$nrev" = "2" ] && [ ! -f "$SD2/claude-called" ] \
   && jq empty "$P2/docs/eval-results/review-manifest.json" 2>/dev/null; then
  pass "T-assemble-manifest"
else
  fail_ "T-assemble-manifest" "rc=$rc reviews=$nrev claude-called=$([ -f "$SD2/claude-called" ] && echo YES || echo no) — the manifest-assembly step must build a valid manifest from on-disk review files without driving sessions: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── T3: a hanging review is group-killed at REVIEW_TIMEOUT_SECS ──────────────
echo "=== T-timeout-kills-group ==="
P3="$TOPTMP/p3"; SD3="$TOPTMP/sd3"; mkdir -p "$SD3"; mk_proj "$P3"
printf 'hang:20\n' > "$SD3/plan"
out=$(run_runner "$P3" "$SD3" "2" web-app 2); rc=$?
gc=$(cat "$SD3/gc.pid" 2>/dev/null || echo "")
gc_alive=no
if [ -n "$gc" ] && kill -0 "$gc" 2>/dev/null; then gc_alive=yes; kill -9 "$gc" 2>/dev/null; fi
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qi "timed out" && [ -n "$gc" ] && [ "$gc_alive" = "no" ]; then
  pass "T-timeout-kills-group"
else
  fail_ "T-timeout-kills-group" "rc=$rc gc-pid='${gc:-UNRECORDED}' grandchild-alive=$gc_alive timeout-reported=$(printf '%s' "$out" | grep -qi 'timed out' && echo yes || echo no) — an unbounded review is the F-DF2-015 hang; a missing gc.pid means the stub never ran (vacuous) and a surviving grandchild is the 159-orphan defect: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# ── T4: a failed review is surfaced actionably and the run CONTINUES ─────────
echo "=== T-failure-surfaced ==="
P4="$TOPTMP/p4"; SD4="$TOPTMP/sd4"; mkdir -p "$SD4"; mk_proj "$P4"
printf 'fail:Error: spend limit reached for this workspace\nwrite:legal-review-v1.md\n' > "$SD4/plan"
out=$(run_runner "$P4" "$SD4" "" web-app 2 4); rc=$?
nrev=$(jq -r '.reviews | length' "$P4/docs/eval-results/review-manifest.json" 2>/dev/null || echo 0)
case "$nrev" in ''|*[!0-9]*) nrev=0 ;; esac
if [ "$rc" -eq 0 ] && [ "$nrev" = "1" ] \
   && printf '%s' "$out" | grep -qiE "spend|usage" \
   && printf '%s' "$out" | grep -qi "legal"; then
  pass "T-failure-surfaced"
else
  fail_ "T-failure-surfaced" "rc=$rc reviews=$nrev — a spend-limit death must be SURFACED (not a silent set -e abort) and later reviews must still run + manifest still land: $(printf '%s' "$out" | tail -3 | tr '\n' ' ')"
fi

# ── T5: the manifest is written incrementally (after EACH review) ────────────
echo "=== T-incremental-manifest ==="
P5="$TOPTMP/p5"; SD5="$TOPTMP/sd5"; mkdir -p "$SD5"; mk_proj "$P5"
printf 'write:cio-review-v1.md\nhangcheck:20\n' > "$SD5/plan"
out=$(run_runner "$P5" "$SD5" "2" web-app 2 4); rc=$?
if [ -f "$SD5/witness" ] && jq -e '.reviews[] | select(.artifact=="cio-review-v1.md")' "$P5/docs/eval-results/review-manifest.json" >/dev/null 2>&1; then
  pass "T-incremental-manifest (reviewer 2's session observed reviewer 1's manifest entry already on disk)"
else
  fail_ "T-incremental-manifest" "witness=$([ -f "$SD5/witness" ] && echo yes || echo NO) rc=$rc — the manifest must accrete after EACH completed review so a partial/killed run is still usable: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
