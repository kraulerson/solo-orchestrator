#!/usr/bin/env bash
# tests/test-bl234-currency-and-availability.sh
#
# BL-234 — currency and availability must be MEASURED, not DECLARED. Four
# shipped checks asked whether something was configured and reported the answer
# as whether it worked:
#
#   1. scripts/lib/freshness-detect.sh compared a project's pin against the
#      LOCAL clone it was scaffolded from — the same object, by construction —
#      and never fetched. `pin-behind` was structurally incapable of firing, and
#      on `powerpoint-voice` it stayed silent through 161 upstream commits.
#   2. scripts/lib/helpers-full.sh::is_qdrant_mcp_registered tested for an
#      `mcpServers.qdrant` KEY, so a stale global entry made every later project
#      skip provisioning the database.
#   3. scripts/track-tool-usage.sh decided emptiness partly by PHRASE, and
#      matched a stored memory that CONTAINED the words "empty result".
#   4. templates/tool-matrix — filed as `## BL-235:`, deliberately not fixed.
#
# ── WHAT THIS SUITE REFUSES TO DO ───────────────────────────────────────────
# "Do not let a test pass because a fetch or a probe was ATTEMPTED." Not one
# assertion below is satisfied by the presence of a call, a label, or a flag
# that says a thing happened. Every assertion is on EMITTED OUTPUT, LEDGER
# STATE, an EXIT CODE, or WALL-CLOCK TIME.
#
# Three arms are of the kind that silently cannot fire, so each has a test whose
# whole job is to MAKE it fire:
#   • the reference-age fallback  → A3/A4/A6 (fetch fails / never fetched / no remote)
#   • the probe bound             → A5/B6 (a stub that sleeps 30s, wall-clock asserted)
#   • the cannot-tell probe state → B3 (PATH with neither curl nor nc)
# The author of the brief shipped a `docker ps … | head || echo` whose fallback
# could never fire, because a pipeline's status is the last command's. That is
# recorded in `## BL-231:`'s ⚠ CORRECTION block and it is the standard here.
#
# ── Mutation harness standard (all mandatory) ───────────────────────────────
#   • anchored END-OF-LINE markers, asserted at sites==1 in the SHIPPED source;
#   • exactly-N-lines-changed per mutant — this is what catches a sed that
#     reported success and edited nothing (CLAUDE.md's sed trap). The delimiter
#     is `%`, absent from every marker and replacement here, and `&` is escaped
#     because in a sed replacement `&` means THE WHOLE MATCH;
#   • EVERY mutant asserts `bash -n` — a mutant that lands as a syntax error
#     kills every test for the wrong reason and would score as a pass;
#   • mode-preserving (`stat -c || stat -f`, GNU-first);
#   • a FRESH fixture per mutant AND per direction — the freshness detector
#     writes .claude/cache/freshness.json, so a reused project directory carries
#     snooze/cache state from the control run into the mutant run;
#   • structural discriminators for ABSENCES. Item 3 DELETES the phrase half, and
#     an absence cannot be greped for as proof, so M-EMPTY mutates a real shape
#     line back into a phrase match and shows the incident fixture flipping.
#
# Hermetic: temp dirs only. Origins are LOCAL BARE REPOS — never the network,
# never `gh repo create`. No `timeout`/`gtimeout` (absent on the dev host: they
# yield a spurious rc=127, not a timeout). bash 3.2: no ${var,,}, no declare -A,
# no nullglob, no ((x++)) under set -e.
#
# This suite does not invoke init.sh. It EXTRACTS init.sh's Qdrant
# reclassification chain from between its fence markers and executes that, so
# B5 asserts on the shipped chain rather than on a copy of it that could drift.
# `init.sh` is named on executed lines for that reason, so
# lint-tests-registered.sh will mark it unit-lane-exempt; it is registered in
# the tests.yml unit list anyway (the lint treats a listed test as "the
# exemption decided nothing") because it is fast enough for the fast lane.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FRESH_LIB="$REPO_ROOT/scripts/lib/freshness-detect.sh"
FRESH_SUT="$REPO_ROOT/scripts/session-freshness-check.sh"
HELPERS_FULL="$REPO_ROOT/scripts/lib/helpers-full.sh"
TRACKER="$REPO_ROOT/scripts/track-tool-usage.sh"
CHECKVER="$REPO_ROOT/scripts/check-versions.sh"
SCAFFOLDER="$REPO_ROOT/init.sh"
GITIGNORE_TMPL="$REPO_ROOT/templates/generated/gitignore-base.tmpl"
UPGRADE="$REPO_ROOT/scripts/upgrade-project.sh"

BASH_BIN="$(command -v bash)"
[ -n "$BASH_BIN" ] || BASH_BIN="/bin/bash"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] jq is not installed — this suite asserts on JSON state."
  echo ""
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

TOPTMP="$(mktemp -d)"
trap 'chmod -R u+rwX "$TOPTMP" 2>/dev/null; rm -rf "$TOPTMP"' EXIT INT TERM
# newtmp — a FRESH directory per case. It must be `mktemp -d` and not a counter:
# a counter incremented inside `$( … )` increments in a SUBSHELL and never
# reaches the parent, so every call returns the same path and every "fresh
# fixture" is the previous case's leftovers. That bug was live in the first
# draft of this file and A4 caught it (a fixture that had "never fetched" found
# a FETCH_HEAD), which is the whole reason the fresh-fixture rule exists.
newtmp() { mktemp -d "$TOPTMP/caseXXXXXX"; }

_num() { case "$1" in ''|null|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac }
_mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || printf '?\n'; }
_mtime_of() { stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1" 2>/dev/null || printf '\n'; }
_parses() { bash -n "$1" >/dev/null 2>&1 && printf '1\n' || printf '0\n'; }

_sed_inplace() {
  local file="$1" expr="$2" tmp mode
  mode="$(_mode_of "$file")"
  tmp="$(mktemp)"
  sed "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
  [ "$mode" != "?" ] && chmod "$mode" "$file" 2>/dev/null
  return 0
}

_changed_lines() { local n; n=$(diff "$1" "$2" 2>/dev/null | grep -c '^[<>]'); _num "$n"; }
_sites() { local n; n=$(grep -c "$2\$" "$1" 2>/dev/null); _num "$n"; }

# _mutate FILE MARKER REPLACEMENT — excise the one END-OF-LINE-anchored marked
# line and replace it. Echoes "sites changed parses".
_mutate() {
  local f="$1" marker="$2" repl="$3"
  local before sites changed parses safe
  safe=$(printf '%s' "$repl" | sed 's/&/\\&/g')
  before="$(mktemp)"
  cp -p "$f" "$before"
  sites=$(_sites "$f" "$marker")
  _sed_inplace "$f" "s%^.*${marker}\$%${safe}%"
  changed=$(_changed_lines "$before" "$f")
  parses=$(_parses "$f")
  rm -f "$before"
  printf '%s %s %s\n' "$sites" "$changed" "$parses"
}

_git() { git -c user.email=t@t.t -c user.name=tester -c commit.gpgsign=false "$@"; }

# ════════════════════════════════════════════════════════════════════════════
# FIXTURES — a framework clone, optionally anchored to a LOCAL BARE ORIGIN.
# ════════════════════════════════════════════════════════════════════════════

# build_fw <fwdir> [baredir] — a minimal framework checkout. When <baredir> is
# given it is created as a LOCAL BARE repo, pushed to, and set as `origin` with
# an upstream — a real remote with no network anywhere near it.
# Sets FW and PIN. Never echoes: a stray git line would corrupt a capture.
FW=""; PIN=""
build_fw() {
  local fw="$1" bare="${2:-}"
  mkdir -p "$fw/scripts"
  printf 'echo fw v1\n' > "$fw/scripts/validate.sh"
  _git -C "$fw" init -q -b main >/dev/null 2>&1 || { _git -C "$fw" init -q >/dev/null 2>&1; _git -C "$fw" symbolic-ref HEAD refs/heads/main >/dev/null 2>&1; }
  _git -C "$fw" add -A >/dev/null 2>&1
  _git -C "$fw" commit -qm "fw v1" >/dev/null 2>&1
  if [ -n "$bare" ]; then
    _git init -q --bare "$bare" >/dev/null 2>&1
    _git -C "$fw" remote add origin "$bare" >/dev/null 2>&1
    _git -C "$fw" push -q -u origin main >/dev/null 2>&1
    _git -C "$fw" fetch -q origin >/dev/null 2>&1
  fi
  FW="$fw"
  PIN="$(_git -C "$fw" rev-parse HEAD 2>/dev/null)"
}

# advance_origin <baredir> <workdir> — push one NEW commit to the bare origin
# from a throwaway clone, so the framework checkout is genuinely behind its
# remote without its own refs knowing it yet.
advance_origin() {
  local bare="$1" work="$2"
  _git clone -q "$bare" "$work" >/dev/null 2>&1 || return 1
  printf 'echo fw v2\n' > "$work/scripts/validate.sh"
  _git -C "$work" add -A >/dev/null 2>&1
  _git -C "$work" commit -qm "fw v2" >/dev/null 2>&1
  _git -C "$work" push -q origin HEAD:main >/dev/null 2>&1
}

# _fh_of <fwdir> — the absolute path of that clone's FETCH_HEAD.
_fh_of() {
  local f
  f="$(_git -C "$1" rev-parse --git-dir 2>/dev/null)/FETCH_HEAD"
  case "$f" in /*) : ;; *) f="$1/$f" ;; esac
  printf '%s' "$f"
}
# _fh_size <path> — size in bytes, 0 when absent/unreadable.
_fh_size() { local n; n=$(wc -c < "$1" 2>/dev/null | tr -d ' '); _num "$n"; }

# build_fw_failed_fetch <casedir> — a framework clone whose LAST fetch FAILED,
# leaving FETCH_HEAD at ZERO BYTES with a FRESH mtime.
#
# MEASURED on this host, not assumed: after a successful fetch FETCH_HEAD was
# 130 bytes; after a fetch against a deleted origin it was 0 bytes with a NEWER
# mtime. So the mtime dates the last ATTEMPT and the SIZE is the only thing that
# separates success from failure. Reading the mtime alone reports "last fetched
# 0 day(s) ago" forever on an offline machine — active false reassurance, worse
# than the silence this package removes. A8 and M7 exist for that one byte.
build_fw_failed_fetch() {
  local d="$1"
  build_fw "$d/fw" "$d/origin"
  rm -rf "$d/origin"                       # the remote path is gone
  _git -C "$d/fw" fetch -q >/dev/null 2>&1 || true   # this fetch FAILS and truncates FETCH_HEAD
}

# build_proj <projdir> <fwdir> <pin> — a scaffolded project whose currency block
# is EMPTY except for the pin, so only the framework check can speak. Any other
# emitted line would be a fixture bug, not a finding.
build_proj() {
  local proj="$1" fw="$2" pin="$3"
  mkdir -p "$proj/.claude"
  jq -n --arg pin "$pin" --arg fw "$fw" \
    '{ soloFrameworkCommit:$pin,
       currency:{ schemaVersion:1, soloFrameworkPath:$fw,
                  files:{}, renderBases:{A1:{},A2:{}}, hooks:{} } }' \
    > "$proj/.claude/manifest.json"
}

# run_fresh <projdir> [env assignments...] — invoke the SHIPPED SessionStart
# wrapper. Captures stdout/stderr/exit and the wall-clock seconds it took.
FOUT=""; FERR=""; FRC=0; FSECS=0
run_fresh() {
  local proj="$1"; shift
  local errf t0 t1
  errf="$TOPTMP/err.$$"
  t0=$(date +%s)
  FOUT="$(env "$@" CDF_HOME="$TOPTMP/no-cdf" CLAUDE_PROJECT_DIR="$proj" "$BASH_BIN" "$FRESH_SUT" 2>"$errf")"
  FRC=$?
  t1=$(date +%s)
  FSECS=$((t1 - t0))
  FERR="$(cat "$errf" 2>/dev/null)"
  rm -f "$errf"
}

# run_fresh_at <sut> <projdir> [env assignments...] — the same, against an
# arbitrary (mirrored or MUTATED) copy of the wrapper.
run_fresh_at() {
  local sut="$1" proj="$2"; shift 2
  local errf
  errf="$TOPTMP/merr.$$"
  FOUT="$(env "$@" CDF_HOME="$TOPTMP/no-cdf" CLAUDE_PROJECT_DIR="$proj" "$BASH_BIN" "$sut" 2>"$errf")"
  FRC=$?
  FERR="$(cat "$errf" 2>/dev/null)"; rm -f "$errf"
}

echo "=== A — framework currency is measured against the REMOTE, and says so when it cannot be ==="

# ── A1: the silent case. The clone is behind its origin; today nothing says so.
A1="$(newtmp)"
build_fw "$A1/fw" "$A1/origin"
A1PIN="$PIN"
if ! advance_origin "$A1/origin" "$A1/adv"; then
  fail_ "A1" "fixture: could not advance the local bare origin"
else
  build_proj "$A1/proj" "$A1/fw" "$A1PIN"
  run_fresh "$A1/proj"
  if [ "$FRC" -eq 0 ] && printf '%s' "$FOUT" | grep -q 'pin-behind-upstream'; then
    pass "A1: framework clone is behind its origin -> REPORTED (the pin/HEAD comparison could never see this: they are the same object by construction)"
  else
    fail_ "A1" "rc=$FRC and no pin-behind-upstream item; output was: $(printf '%s' "$FOUT" | tr '\n' '|' | cut -c1-400)"
  fi
fi

# ── A2: no false noise. Clone current with its origin -> byte-silent.
A2="$(newtmp)"
build_fw "$A2/fw" "$A2/origin"
build_proj "$A2/proj" "$A2/fw" "$PIN"
run_fresh "$A2/proj"
if [ "$FRC" -eq 0 ] && [ -z "$FOUT" ] && [ -z "$FERR" ]; then
  pass "A2: clone current with its origin -> zero bytes on stdout AND stderr, exit 0 (a fetch that succeeds must stay silent)"
else
  fail_ "A2" "rc=$FRC out='$(printf '%s' "$FOUT" | tr '\n' '|' | cut -c1-300)' err='$(printf '%s' "$FERR" | tr '\n' '|' | cut -c1-200)'"
fi

# ── A3: the fetch FAILS. The reference-age line must still appear.
# Asserting only "did not crash" would pass over the exact silence this package
# exists to remove, so the age text itself is asserted.
A3="$(newtmp)"
build_fw "$A3/fw" "$A3/origin"
build_proj "$A3/proj" "$A3/fw" "$PIN"
rm -rf "$A3/origin"                     # the remote path is now gone: fetch cannot succeed
A3_FH="$(_git -C "$A3/fw" rev-parse --git-dir 2>/dev/null)/FETCH_HEAD"
case "$A3_FH" in /*) : ;; *) A3_FH="$A3/fw/$A3_FH" ;; esac
touch -t 202601010000 "$A3_FH" 2>/dev/null
A3_MT="$(_mtime_of "$A3_FH")"
if [ -z "$A3_MT" ] || [ ! -f "$A3_FH" ]; then
  fail_ "A3" "fixture: FETCH_HEAD absent or unstattable at $A3_FH"
else
  A3_NOW=$((A3_MT + 30 * 86400 + 60))
  run_fresh "$A3/proj" "SOIF_FRESHNESS_NOW=$A3_NOW"
  if [ "$FRC" -eq 0 ] \
     && printf '%s' "$FOUT" | grep -q 'fw-reference-age' \
     && printf '%s' "$FOUT" | grep -q '30 day' ; then
    pass "A3: fetch impossible (origin path deleted) -> exit 0, no crash, AND the reference-age line names the real age (30 days)"
  else
    fail_ "A3" "rc=$FRC — wanted a fw-reference-age item naming '30 day'; got: $(printf '%s' "$FOUT" | tr '\n' '|' | cut -c1-500)"
  fi
fi

# ── A4: NEVER fetched — powerpoint-voice's true state, and the one the old code
# reported as "current".
A4="$(newtmp)"
build_fw "$A4/fw"                       # no bare origin: nothing has ever been fetched
_git -C "$A4/fw" remote add origin "$A4/nonexistent-bare" >/dev/null 2>&1
build_proj "$A4/proj" "$A4/fw" "$PIN"
A4_FH="$(_git -C "$A4/fw" rev-parse --git-dir 2>/dev/null)/FETCH_HEAD"
case "$A4_FH" in /*) : ;; *) A4_FH="$A4/fw/$A4_FH" ;; esac
if [ -f "$A4_FH" ]; then
  fail_ "A4" "fixture: FETCH_HEAD exists but this fixture must never have fetched"
else
  run_fresh "$A4/proj"
  if [ "$FRC" -eq 0 ] && printf '%s' "$FOUT" | grep -qi 'never fetched'; then
    pass "A4: a clone that has NEVER been fetched is reported as such — the true answer on powerpoint-voice, where silence was reported instead"
  else
    fail_ "A4" "rc=$FRC — wanted 'never fetched'; got: $(printf '%s' "$FOUT" | tr '\n' '|' | cut -c1-500)"
  fi
fi

# ── A5: THE BOUND ACTUALLY BOUNDS. Proved with a git stub that sleeps 30s and a
# wall-clock assertion — not by asserting that a timeout value was passed.
# This is also the only test that can catch an orphaned child holding the
# command-substitution pipe open: run_with_timeout kills the stub, but a
# surviving grandchild that inherited stdout would stall the capture for 30s.
A5="$(newtmp)"
build_fw "$A5/fw" "$A5/origin"
build_proj "$A5/proj" "$A5/fw" "$PIN"
mkdir -p "$A5/bin"
REAL_GIT="$(command -v git)"
cat > "$A5/bin/git" << STUBEOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = "fetch" ]; then sleep 30; exit 0; fi
done
exec "$REAL_GIT" "\$@"
STUBEOF
chmod 755 "$A5/bin/git"
run_fresh "$A5/proj" "PATH=$A5/bin:$PATH" "SOIF_FRESHNESS_FETCH_TIMEOUT=2"
if [ "$FRC" -eq 0 ] && [ "$FSECS" -le 8 ] && printf '%s' "$FOUT" | grep -q 'fw-reference-age'; then
  pass "A5: a fetch that would hang for 30s is cut off at the 2s bound (measured ${FSECS}s wall clock) and the reference-age line still appears"
else
  fail_ "A5" "rc=$FRC elapsed=${FSECS}s (want <=8) — and wanted fw-reference-age; got: $(printf '%s' "$FOUT" | tr '\n' '|' | cut -c1-300)"
fi

# ── A6: no remote at all. A fetch that was never ATTEMPTED is still a fetch that
# did not happen, and the reference is still unanchored.
A6="$(newtmp)"
build_fw "$A6/fw"
build_proj "$A6/proj" "$A6/fw" "$PIN"
run_fresh "$A6/proj"
if [ "$FRC" -eq 0 ] && printf '%s' "$FOUT" | grep -q 'fw-reference-age'; then
  pass "A6: a framework clone with NO remote reports that its currency could not be checked, instead of reporting 'current'"
else
  fail_ "A6" "rc=$FRC — wanted fw-reference-age; got: $(printf '%s' "$FOUT" | tr '\n' '|' | cut -c1-300)"
fi

# ── A7: the machine block's `network` field was a DECLARATION too. It was the
# literal string "none", and would have gone on saying "none" while the detector
# fetched. The fixture carries a pin-behind item that fires in BOTH modes, so a
# machine block exists to read in both — otherwise the opt-out run is silent and
# the field could not be compared at all.
A7="$(newtmp)"
build_fw "$A7/fw"
A7PIN="$PIN"
printf 'echo fw v2\n' > "$A7/fw/scripts/validate.sh"
_git -C "$A7/fw" add -A >/dev/null 2>&1
_git -C "$A7/fw" commit -qm "fw v2" >/dev/null 2>&1
_net_of() { printf '%s' "$1" | sed -n '/```soif-freshness/,/```/p' | sed '1d;$d' | jq -r '.network // "MISSING"' 2>/dev/null; }
build_proj "$A7/p1" "$A7/fw" "$A7PIN"
run_fresh "$A7/p1"
A7_ON="$(_net_of "$FOUT")"
A7_ON_AGE=no; printf '%s' "$FOUT" | grep -q 'fw-reference-age' && A7_ON_AGE=yes
build_proj "$A7/p2" "$A7/fw" "$A7PIN"
run_fresh "$A7/p2" "SOIF_FRESHNESS_FETCH=0"
A7_OFF="$(_net_of "$FOUT")"
A7_OFF_AGE=no; printf '%s' "$FOUT" | grep -q 'fw-reference-age' && A7_OFF_AGE=yes
if [ "$A7_ON" = "fetch-bounded" ] && [ "$A7_ON_AGE" = "yes" ] \
   && [ "$A7_OFF" = "none" ] && [ "$A7_OFF_AGE" = "no" ]; then
  pass "A7: the machine block reports the mode that actually ran — 'fetch-bounded' by default, 'none' under SOIF_FRESHNESS_FETCH=0, which restores M1's zero-network contract INCLUDING its silence"
else
  fail_ "A7" "default: network='$A7_ON' (want fetch-bounded) age=$A7_ON_AGE (want yes); opt-out: network='$A7_OFF' (want none) age=$A7_OFF_AGE (want no)"
fi

# ── A8: THE `failed` ARM. A3 pins `ok <epoch>` and A4 pins `never`; until this
# case existed the third state — a PREVIOUS session's failed fetch, FETCH_HEAD
# truncated to zero bytes — had no test anywhere, and the one-character mutant
# `-eq 0` -> `-lt 0` passed every suite in the repo while making the tool say
# "last fetched 0 day(s) ago" forever on an offline machine. The assertion is
# two-sided on purpose: the honest wording must be PRESENT and the false
# reassurance must be ABSENT, because only the second half dies under the mutant.
A8="$(newtmp)"
build_fw_failed_fetch "$A8"
build_proj "$A8/proj" "$A8/fw" "$PIN"
A8_FH="$(_fh_of "$A8/fw")"
A8_SZ="$(_fh_size "$A8_FH")"
if [ ! -f "$A8_FH" ] || [ "$A8_SZ" != "0" ]; then
  fail_ "A8" "fixture: wanted a ZERO-byte FETCH_HEAD from a failed fetch; got size=$A8_SZ at $A8_FH"
else
  run_fresh "$A8/proj"
  if [ "$FRC" -eq 0 ] \
     && printf '%s' "$FOUT" | grep -q 'UNKNOWN time' \
     && ! printf '%s' "$FOUT" | grep -q 'last fetched 0 day'; then
    pass "A8: a clone whose last fetch FAILED (FETCH_HEAD truncated to 0 bytes) reports an UNKNOWN fetch time — and does NOT report 'last fetched 0 day(s) ago', which is what reading the mtime alone would say forever while offline"
  else
    fail_ "A8" "rc=$FRC — wanted 'UNKNOWN time' and NOT 'last fetched 0 day'; got: $(printf '%s' "$FOUT" | tr '\n' '|' | cut -c1-500)"
  fi
fi

# ── A9: NAME THE RIGHT CAUSE. _soif_fresh_try_fetch returned one code for three
# different not-attempted states, and the caller's sentence asserted the third
# of them — "the clone has no remote configured" — as a FACT for all three. On a
# clone that HAS a remote but has no bounded runner, that sentence sent the
# operator to fix a remote that was never broken. The fixture is a mirror with
# helpers-core.sh withheld, so run_with_timeout genuinely does not exist; the
# clone keeps a real local bare origin, so the false claim is falsifiable.
A9="$(newtmp)"
mkdir -p "$A9/m/scripts/lib"
cp -p "$REPO_ROOT/scripts/session-freshness-check.sh" "$A9/m/scripts/"
cp -p "$FRESH_LIB" "$A9/m/scripts/lib/"
for f in currency-manifest.sh hook-templates.sh bypass-audit.sh; do
  [ -f "$REPO_ROOT/scripts/lib/$f" ] && cp -p "$REPO_ROOT/scripts/lib/$f" "$A9/m/scripts/lib/"
done                                    # helpers-core.sh deliberately WITHHELD
build_fw "$A9/fw" "$A9/origin"
build_proj "$A9/proj" "$A9/fw" "$PIN"
A9_REMOTES="$(_git -C "$A9/fw" remote 2>/dev/null | wc -l | tr -d ' ')"
run_fresh_at "$A9/m/scripts/session-freshness-check.sh" "$A9/proj"
if [ "$A9_REMOTES" != "0" ] && [ "$FRC" -eq 0 ] \
   && printf '%s' "$FOUT" | grep -q 'no bounded runner' \
   && ! printf '%s' "$FOUT" | grep -q 'no remote configured'; then
  pass "A9: with no bounded runner available, a clone that HAS a remote is told the runner is missing — not that its remote is, which is what one shared return code made the tool claim"
else
  fail_ "A9" "remotes=$A9_REMOTES (want >0) rc=$FRC — wanted 'no bounded runner' and NOT 'no remote configured'; got: $(printf '%s' "$FOUT" | tr '\n' '|' | cut -c1-400)"
fi

echo ""
echo "=== B — 'registered' must mean 'registered AND the database answers' ==="

# A private HOME so nothing here can read or write the developer's real
# ~/.claude.json. Every B case gets its own.
mk_home() {
  local h="$1" url="$2" key="${3:-}"    # url empty => no qdrant entry at all
  mkdir -p "$h/.claude"
  if [ -n "$url" ]; then
    jq -n --arg u "$url" --arg k "$key" \
      '{mcpServers:{qdrant:{type:"stdio",command:"uvx",args:["mcp-server-qdrant"],
        env:(if $k == "" then {QDRANT_URL:$u,COLLECTION_NAME:"c"}
             else {QDRANT_URL:$u,COLLECTION_NAME:"c",QDRANT_API_KEY:$k} end)}}}' > "$h/.claude.json"
  else
    printf '{}\n' > "$h/.claude.json"
  fi
}

# probe_state <home> <url> [extra-path] — source the SHIPPED helpers with a
# private HOME and report "rc state" from the real predicate.
probe_state() {
  local h="$1" pathv="${2:-$PATH}"
  env -i HOME="$h" PATH="$pathv" "$BASH_BIN" -c '
    set -uo pipefail
    . "'"$HELPERS_FULL"'" >/dev/null 2>&1
    rc=0
    is_qdrant_mcp_registered || rc=$?
    printf "%s %s\n" "$rc" "${QDRANT_MCP_STATE:-UNSET}"
  ' 2>/dev/null
}

# A local HTTP server standing in for a reachable Qdrant. Python is used only as
# a socket; nothing here talks to a real database or the network.
QSRV_PID=""; QSRV_PORT=""
start_stub_qdrant() {
  local d="$1" py
  py="$(command -v python3 || command -v python)"
  [ -n "$py" ] || return 1
  QSRV_PORT=$(( 18000 + (RANDOM % 2000) ))
  "$py" - "$QSRV_PORT" > "$d/srv.log" 2>&1 << 'PYEOF' &
import sys
try:
    from http.server import BaseHTTPRequestHandler, HTTPServer
except ImportError:
    sys.exit(1)
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.send_header("Content-Length","2")
        self.end_headers(); self.wfile.write(b"ok")
    def log_message(self, *a): pass
HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PYEOF
  QSRV_PID=$!
  local i=0
  while [ "$i" -lt 40 ]; do
    curl -fsS --max-time 1 -o /dev/null "http://127.0.0.1:$QSRV_PORT/readyz" 2>/dev/null && return 0
    i=$((i + 1)); sleep 0.1
  done
  kill "$QSRV_PID" 2>/dev/null; QSRV_PID=""
  return 1
}

# start_keyed_qdrant <dir> <required-key> — a SECURED Qdrant: 200 when the
# `api-key` header matches, 401 otherwise. Qdrant's own /readyz declares that
# header as required (api.qdrant.tech/api-reference/service/readyz), so this is
# the state a real keyed server is in, not an invented one. Every request is
# appended to <dir>/hits.log as AUTH, WRONGKEY or NOKEY — three outcomes, because
# a LEAKED cross-file key is a WRONG key and a two-outcome log records it
# identically to an honest unkeyed request. That is how a test can tell
# "the header was sent" from "the probe got lucky".
start_keyed_qdrant() {
  local d="$1" key="$2" py
  py="$(command -v python3 || command -v python)"
  [ -n "$py" ] || return 1
  QSRV_PORT=$(( 18000 + (RANDOM % 2000) ))
  : > "$d/hits.log"
  "$py" - "$QSRV_PORT" "$key" "$d/hits.log" > "$d/srv.log" 2>&1 << 'PYEOF' &
import sys
try:
    from http.server import BaseHTTPRequestHandler, HTTPServer
except ImportError:
    sys.exit(1)
KEY = sys.argv[2]
LOG = sys.argv[3]
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        # THREE outcomes, not two. A WRONG key and NO key both fail
        # authentication, but they are opposite facts about the client: one sent
        # a credential and one did not. Collapsing them hid a leaked cross-file
        # key behind the same NOKEY the honest case produces.
        sent = self.headers.get("api-key")
        ok = sent == KEY
        with open(LOG, "a") as fh:
            fh.write(("AUTH" if ok else ("WRONGKEY" if sent is not None else "NOKEY")) + "\n")
        if ok:
            self.send_response(200); self.send_header("Content-Length", "2")
            self.end_headers(); self.wfile.write(b"ok")
        else:
            self.send_response(401); self.send_header("Content-Length", "1")
            self.end_headers(); self.wfile.write(b"!")
    def log_message(self, *a): pass
HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PYEOF
  QSRV_PID=$!
  local i=0
  while [ "$i" -lt 40 ]; do
    curl -sS --max-time 1 -o /dev/null "http://127.0.0.1:$QSRV_PORT/readyz" 2>/dev/null && { : > "$d/hits.log"; return 0; }
    i=$((i + 1)); sleep 0.1
  done
  kill "$QSRV_PID" 2>/dev/null; QSRV_PID=""
  return 1
}
stop_stub_qdrant() { [ -n "$QSRV_PID" ] && { kill "$QSRV_PID" 2>/dev/null; wait "$QSRV_PID" 2>/dev/null; QSRV_PID=""; }; return 0; }

# ── B1: THE DEFECT. A registered entry whose database does not answer.
B1="$(newtmp)"
mk_home "$B1/home" "http://127.0.0.1:1"     # port 1 is never a Qdrant
B1_OUT="$(probe_state "$B1/home")"
B1_RC="${B1_OUT%% *}"; B1_ST="${B1_OUT##* }"
if [ "$B1_RC" != "0" ] && [ "$B1_ST" = "unreachable" ]; then
  pass "B1: a stale global MCP entry with no reachable database is NOT 'registered' (rc=$B1_RC, state=$B1_ST) — the chain now falls through to provisioning"
else
  fail_ "B1" "rc=$B1_RC state=$B1_ST — wanted a non-zero rc and state=unreachable"
fi

# ── B2: the honest positive. Registered AND answering.
B2="$(newtmp)"
if ! start_stub_qdrant "$B2"; then
  fail_ "B2" "fixture: could not start the local stub HTTP server"
else
  mk_home "$B2/home" "http://127.0.0.1:$QSRV_PORT"
  B2_OUT="$(probe_state "$B2/home")"
  kill "$QSRV_PID" 2>/dev/null; wait "$QSRV_PID" 2>/dev/null; QSRV_PID=""
  B2_RC="${B2_OUT%% *}"; B2_ST="${B2_OUT##* }"
  if [ "$B2_RC" = "0" ] && [ "$B2_ST" = "reachable" ]; then
    pass "B2: registered AND answering -> satisfied (rc=0, state=reachable) — no false negative introduced"
  else
    fail_ "B2" "rc=$B2_RC state=$B2_ST — wanted rc=0 and state=reachable"
  fi
fi

# ── B3: CANNOT TELL is its own state, and it is not 'satisfied'.
# PATH is stripped of every probe tool. jq must remain reachable or the
# predicate cannot even read the config, so a private bin dir links only jq.
B3="$(newtmp)"
mkdir -p "$B3/bin"
for t in jq bash sh env sed grep cat; do
  p="$(command -v "$t" 2>/dev/null)"
  [ -n "$p" ] && ln -sf "$p" "$B3/bin/$t" 2>/dev/null
done
mk_home "$B3/home" "http://127.0.0.1:1"
B3_OUT="$(probe_state "$B3/home" "$B3/bin")"
B3_RC="${B3_OUT%% *}"; B3_ST="${B3_OUT##* }"
if [ "$B3_RC" != "0" ] && [ "$B3_ST" = "unknown" ]; then
  pass "B3: with neither curl nor nc the probe answers 'cannot tell' (state=unknown) and does NOT satisfy the predicate — BL-112's doctrine, not a coin flip"
else
  fail_ "B3" "rc=$B3_RC state=$B3_ST — wanted a non-zero rc and state=unknown"
fi

# ── B4: no entry at all is a determinate answer, distinguishable from the rest.
B4="$(newtmp)"
mk_home "$B4/home" ""
B4_OUT="$(probe_state "$B4/home")"
B4_RC="${B4_OUT%% *}"; B4_ST="${B4_OUT##* }"
if [ "$B4_RC" != "0" ] && [ "$B4_ST" = "unregistered" ]; then
  pass "B4: no MCP entry -> state=unregistered, a THIRD state distinct from unreachable and from cannot-tell"
else
  fail_ "B4" "rc=$B4_RC state=$B4_ST — wanted a non-zero rc and state=unregistered"
fi

# ── B5: THE CHAIN ITSELF. init.sh's reclassification is extracted from between
# its fence markers and executed, so this asserts on the shipped code.
run_reclassify() {
  local d="$1" home="$2" docker_present="$3"
  local block="$d/chain.sh"
  awk '/# BL-234-QDRANT-RECLASSIFY-BEGIN$/{f=1;next} /# BL-234-QDRANT-RECLASSIFY-END$/{f=0} f' \
    "$SCAFFOLDER" > "$block"
  [ -s "$block" ] || { printf 'NOBLOCK\n'; return 1; }
  mkdir -p "$d/bin"
  for t in jq bash sh env sed grep cat awk curl nc; do
    p="$(command -v "$t" 2>/dev/null)"
    [ -n "$p" ] && ln -sf "$p" "$d/bin/$t" 2>/dev/null
  done
  if [ "$docker_present" = "yes" ]; then
    printf '#!/usr/bin/env bash\nexit 0\n' > "$d/bin/docker"; chmod 755 "$d/bin/docker"
  fi
  env -i HOME="$home" PATH="$d/bin" BLOCK="$block" HELPERS="$HELPERS_FULL" "$BASH_BIN" -c '
    set -uo pipefail
    . "$HELPERS" >/dev/null 2>&1
    # No container is running in this harness — the question under test is what
    # the FIRST branch decides, and whether the chain reaches the docker arm.
    is_qdrant_container_running() { return 1; }
    resolver_output=$(jq -n "{already_installed:[],auto_install:[],manual_install:[{name:\"Qdrant MCP\"}]}")
    configure_items="[]"
    . "$BLOCK"
    # Count, never `if (stream)` — a jq `if` over an EMPTY stream produces no
    # output at all, so the "which lane" question would answer with silence and
    # the assertion would compare against an empty string.
    printf "%s\n" "$resolver_output" | jq -r "
      if (((.already_installed // []) | map(select(.name==\"Qdrant MCP\")) | length) > 0) then \"already_installed\"
      elif (((.auto_install // []) | map(select(.name==\"Qdrant MCP\")) | length) > 0) then \"auto_install\"
      else \"manual\" end"
  ' 2>/dev/null
}

B5="$(newtmp)"
mk_home "$B5/home" "http://127.0.0.1:1"     # stale entry, nothing listening
B5_LANE="$(run_reclassify "$B5" "$B5/home" yes)"
if [ "$B5_LANE" = "auto_install" ]; then
  pass "B5: a stale global MCP entry with NO reachable database now falls through init.sh's own chain to the docker arm -> Qdrant is provisioned (was: already_installed, and the database was never created)"
else
  fail_ "B5" "lane='$B5_LANE' — wanted auto_install (the extracted chain must not short-circuit on a dead registration)"
fi

# ── B6: the reachability probe is bounded too. Same standard as A5.
B6="$(newtmp)"
mkdir -p "$B6/bin"
for t in jq bash sh env sed grep cat sleep; do
  p="$(command -v "$t" 2>/dev/null)"
  [ -n "$p" ] && ln -sf "$p" "$B6/bin/$t" 2>/dev/null
done
printf '#!/usr/bin/env bash\nsleep 30\n' > "$B6/bin/curl"; chmod 755 "$B6/bin/curl"
mk_home "$B6/home" "http://127.0.0.1:1"
B6_T0=$(date +%s)
B6_OUT="$(env -i HOME="$B6/home" PATH="$B6/bin" SOLO_QDRANT_PROBE_TIMEOUT=2 "$BASH_BIN" -c '
  set -uo pipefail
  . "'"$HELPERS_FULL"'" >/dev/null 2>&1
  rc=0; is_qdrant_mcp_registered || rc=$?
  printf "%s %s\n" "$rc" "${QDRANT_MCP_STATE:-UNSET}"
' 2>/dev/null)"
B6_T1=$(date +%s)
B6_EL=$((B6_T1 - B6_T0))
B6_RC="${B6_OUT%% *}"
if [ "$B6_RC" != "0" ] && [ "$B6_EL" -le 10 ]; then
  pass "B6: a curl that would hang for 30s is cut off at the 2s bound (measured ${B6_EL}s) — init.sh cannot be made to hang by an unresponsive Qdrant"
else
  fail_ "B6" "rc=$B6_RC elapsed=${B6_EL}s (want <=10 and a non-zero rc)"
fi

# ── B7: A SECURED SERVER IS NOT A DEAD SERVER. Qdrant's /readyz declares
# `api-key` as a required header, so a keyed instance answers an unkeyed probe
# with 401 — and `curl -fsS` exits 22 on any status >= 400, the same "failure"
# the code used for a dead port. Measured on the pre-fix predicate against a
# local 401 responder: rc=1, state=unreachable, for a server that was answering.
# Caller 1 then calls a working memory "a stale registration" while caller 2
# provisions a redundant container beside it. For a REACHABILITY question, an
# HTTP error status IS an answer.
B7="$(newtmp)"
if ! start_keyed_qdrant "$B7" "sekret"; then
  fail_ "B7" "fixture: could not start the local keyed stub HTTP server"
else
  mk_home "$B7/home" "http://127.0.0.1:$QSRV_PORT"     # registration carries NO key
  B7_OUT="$(probe_state "$B7/home")"
  B7_HITS="$(grep -c 'NOKEY' "$B7/hits.log" 2>/dev/null | tr -d ' ')"
  stop_stub_qdrant
  B7_RC="${B7_OUT%% *}"; B7_ST="${B7_OUT##* }"
  if [ "$B7_RC" = "0" ] && [ "$B7_ST" = "reachable" ] && [ "${B7_HITS:-0}" != "0" ]; then
    pass "B7: a server that answers 401 (secured, unkeyed probe — $B7_HITS request(s) logged) is REACHABLE, not dead — the pre-fix predicate returned state=unreachable for exactly this healthy server"
  else
    fail_ "B7" "rc=$B7_RC state=$B7_ST 401_requests=$B7_HITS — wanted rc=0, state=reachable, and at least one request actually reaching the server"
  fi
fi

# ── B8: and the key the REGISTRATION carries is actually sent. B7 alone cannot
# tell a probe that authenticated from one that merely tolerated a 401, so the
# server records every request as AUTH, WRONGKEY or NOKEY and this case asserts on that
# log — the server's observation, not ours.
B8="$(newtmp)"
if ! start_keyed_qdrant "$B8" "sekret"; then
  fail_ "B8" "fixture: could not start the local keyed stub HTTP server"
else
  mk_home "$B8/home" "http://127.0.0.1:$QSRV_PORT" "sekret"
  B8_OUT="$(probe_state "$B8/home")"
  B8_AUTH="$(grep -c 'AUTH' "$B8/hits.log" 2>/dev/null | tr -d ' ')"
  B8_NOKEY="$(grep -c 'NOKEY' "$B8/hits.log" 2>/dev/null | tr -d ' ')"
  stop_stub_qdrant
  B8_RC="${B8_OUT%% *}"; B8_ST="${B8_OUT##* }"
  if [ "$B8_RC" = "0" ] && [ "$B8_ST" = "reachable" ] \
     && [ "${B8_AUTH:-0}" != "0" ] && [ "${B8_NOKEY:-0}" = "0" ]; then
    pass "B8: with QDRANT_API_KEY in the registration the probe AUTHENTICATES (server logged $B8_AUTH keyed request(s), $B8_NOKEY unkeyed) — the key travels with the URL it belongs to"
  else
    fail_ "B8" "rc=$B8_RC state=$B8_ST auth=$B8_AUTH (want >0) nokey=$B8_NOKEY (want 0)"
  fi
fi

# ── B9: the key goes to the REGISTERED host and nowhere else. The fix that made
# the probe send a credential also made it possible to send that credential to
# any url a caller passes — qdrant_probe_reachable takes an OPTIONAL one. The
# registration here names a DIFFERENT host, so the keyed stub must see an
# UNKEYED request. Asserted on the server's own log, because both directions
# return "reachable" and a state assertion could not tell them apart.
B9="$(newtmp)"
if ! start_keyed_qdrant "$B9" "sekret"; then
  fail_ "B9" "fixture: could not start the local keyed stub HTTP server"
else
  mk_home "$B9/home" "http://127.0.0.1:1" "sekret"     # registered elsewhere, with a key
  B9_RC="$(env -i HOME="$B9/home" PATH="$PATH" QPORT="$QSRV_PORT" "$BASH_BIN" -c '
    set -uo pipefail
    . "'"$HELPERS_FULL"'" >/dev/null 2>&1
    rc=0; qdrant_probe_reachable "http://127.0.0.1:$QPORT" || rc=$?
    printf "%s\n" "$rc"' 2>/dev/null)"
  B9_AUTH="$(grep -c 'AUTH' "$B9/hits.log" 2>/dev/null | tr -d ' ')"
  B9_NOKEY="$(grep -c 'NOKEY' "$B9/hits.log" 2>/dev/null | tr -d ' ')"
  stop_stub_qdrant
  if [ "$B9_RC" = "0" ] && [ "${B9_NOKEY:-0}" != "0" ] && [ "${B9_AUTH:-0}" = "0" ]; then
    pass "B9: probing a host the registration does NOT name sends no credential ($B9_NOKEY unkeyed request(s), $B9_AUTH keyed) — the api-key travels with its own URL and with nothing else"
  else
    fail_ "B9" "rc=$B9_RC (want 0) nokey=$B9_NOKEY (want >0) auth=$B9_AUTH (want 0)"
  fi
fi

# mk_home_settings <home> <url> <key> — a qdrant entry in the OTHER config file,
# ~/.claude/settings.json. Used to build the cross-file fixture; either field may
# be empty, which is the point.
mk_home_settings() {
  local h="$1" url="$2" key="$3"
  mkdir -p "$h/.claude"
  jq -n --arg u "$url" --arg k "$key" \
    '{mcpServers:{qdrant:{type:"stdio",command:"uvx",
      env:( ({} | if $u == "" then . else .QDRANT_URL = $u end)
                | if $k == "" then . else .QDRANT_API_KEY = $k end )}}}' > "$h/.claude/settings.json"
}

# mk_curl_stub <bindir> <recorddir> — a `curl` that RECORDS its argv and the
# content of any -K config it was given, then exits 0. Nothing leaves the
# machine, and no port is touched — which is why the key-without-URL case uses
# it: that path resolves to the hard-coded localhost:6333, and a real Qdrant may
# be listening there on a developer box.
mk_curl_stub() {
  local b="$1" rec="$2"
  mkdir -p "$b" "$rec"
  cat > "$b/curl" << STUBEOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$rec/argv.log"
prev=""
for a in "\$@"; do
  if [ "\$prev" = "-K" ]; then cat "\$a" >> "$rec/config.log" 2>/dev/null; fi
  prev="\$a"
done
exit 0
STUBEOF
  chmod 755 "$b/curl"
}

# ── B10: THE CROSS-FILE PAIRING. qdrant_mcp_url and qdrant_mcp_api_key applied
# claude.json-first fallback PER FIELD, so they could take the URL from one
# registration and the key from the other. Measured on the pre-fix code:
# claude.json with a URL and no key, settings.json with a DIFFERENT url and
# QDRANT_API_KEY=crosskey => the probe delivered `crosskey` to claude.json's
# host. The `base == qdrant_mcp_url` guard cannot see it: it scopes the key to
# whatever the URL lookup returned, not to the entry the key came from.
B10="$(newtmp)"
if ! start_keyed_qdrant "$B10" "sekret"; then
  fail_ "B10" "fixture: could not start the local keyed stub HTTP server"
else
  mk_home "$B10/home" "http://127.0.0.1:$QSRV_PORT"              # claude.json: URL, NO key
  mk_home_settings "$B10/home" "http://127.0.0.1:1" "crosskey"   # settings.json: other url + a key
  B10_OUT="$(probe_state "$B10/home")"
  # ANY credential at all is the failure, not just a correct one: a leaked
  # cross-file key is a WRONG key here, and a stub that only distinguished
  # AUTH from NOKEY would have logged it identically to the honest case.
  B10_SENT="$(grep -cE 'AUTH|WRONGKEY' "$B10/hits.log" 2>/dev/null | tr -d ' ')"
  B10_NOKEY="$(grep -c 'NOKEY' "$B10/hits.log" 2>/dev/null | tr -d ' ')"
  stop_stub_qdrant
  B10_ST="${B10_OUT##* }"
  if [ "$B10_ST" = "reachable" ] && [ "${B10_SENT:-0}" = "0" ] && [ "${B10_NOKEY:-0}" != "0" ]; then
    pass "B10: a key living in the OTHER config file is not paired with this entry's URL — the probed host saw $B10_NOKEY unkeyed request(s) and $B10_SENT carrying any credential; pre-fix it received 'crosskey', which its own registration never mentioned"
  else
    fail_ "B10" "state=$B10_ST requests_carrying_a_key=$B10_SENT (want 0) nokey=$B10_NOKEY (want >0)"
  fi
fi

# ── B11: A KEY WITH NO URL OF ITS OWN. The entry carries QDRANT_API_KEY and no
# QDRANT_URL, so qdrant_mcp_url substitutes the hard-coded http://localhost:6333
# — a host the operator never named. It must get NO credential. Asserted against
# a curl STUB, deliberately: this path resolves to port 6333 and a real Qdrant
# may be listening there on a developer machine.
B11="$(newtmp)"
mk_curl_stub "$B11/bin" "$B11/rec"
mkdir -p "$B11/home/.claude"
jq -n '{mcpServers:{qdrant:{type:"stdio",command:"uvx",env:{QDRANT_API_KEY:"lonelykey",COLLECTION_NAME:"c"}}}}' > "$B11/home/.claude.json"
env -i HOME="$B11/home" PATH="$B11/bin:$PATH" "$BASH_BIN" -c '
  . "'"$HELPERS_FULL"'" >/dev/null 2>&1
  qdrant_probe_reachable' >/dev/null 2>&1
B11_ARGV="$(cat "$B11/rec/argv.log" 2>/dev/null)"
B11_CFG="$(cat "$B11/rec/config.log" 2>/dev/null)"
if printf '%s' "$B11_ARGV" | grep -q 'localhost:6333' \
   && ! printf '%s' "$B11_ARGV$B11_CFG" | grep -q 'lonelykey'; then
  pass "B11: an entry with a key but NO QDRANT_URL probes the documented default and sends NOTHING with it — the fallback host is not a host the registration named, so it gets no credential"
else
  fail_ "B11" "argv='$(printf '%s' "$B11_ARGV" | tr '\n' '|' | cut -c1-200)' config='$(printf '%s' "$B11_CFG" | tr '\n' '|' | cut -c1-120)' — wanted the localhost fallback probed and 'lonelykey' nowhere"
fi

# ── B12: THE CREDENTIAL IS NOT ON argv. `-H "api-key: …"` put it in the process
# table, readable by any local process with `ps` for the probe's lifetime, at
# session start, on every project. It now travels as a curl config handed over by
# process substitution: argv carries only /dev/fd/N. The stub records both, so
# this asserts on where the secret WAS and where it WAS NOT.
B12="$(newtmp)"
mk_curl_stub "$B12/bin" "$B12/rec"
mk_home "$B12/home" "http://127.0.0.1:6399" "argvsecret"
env -i HOME="$B12/home" PATH="$B12/bin:$PATH" "$BASH_BIN" -c '
  . "'"$HELPERS_FULL"'" >/dev/null 2>&1
  qdrant_probe_reachable' >/dev/null 2>&1
B12_ARGV="$(cat "$B12/rec/argv.log" 2>/dev/null)"
B12_CFG="$(cat "$B12/rec/config.log" 2>/dev/null)"
if ! printf '%s' "$B12_ARGV" | grep -q 'argvsecret' \
   && printf '%s' "$B12_CFG" | grep -q 'api-key: argvsecret'; then
  pass "B12: the api-key is absent from curl's argv and present in the config curl actually read — off the process table, still delivered"
else
  fail_ "B12" "argv contains secret=$(printf '%s' "$B12_ARGV" | grep -c 'argvsecret') (want 0); config carries header=$(printf '%s' "$B12_CFG" | grep -c 'api-key: argvsecret') (want >0)"
fi

echo ""
echo "=== C — emptiness is decided by SHAPE; the phrase half is gone ==="

# THE REGRESSION, VERBATIM. This is the stored memory whose text made a
# ten-entry retrieval get recorded as empty on 2026-08-14.
INCIDENT_TEXT='D8 empty result returns 200 with {games: [], meta.total: 0}'

# run_tracker <dir> <payload-json> — run the SHIPPED PostToolUse tracker in a
# throwaway project and echo the resulting qdrant_find_empty value.
run_tracker() {
  local d="$1" payload="$2"
  mkdir -p "$d/.claude"
  printf '%s' "$payload" | ( cd "$d" && "$BASH_BIN" "$TRACKER" --event PostToolUse >/dev/null 2>&1 )
  jq -r '.qdrant_find_empty' "$d/.claude/tool-usage.json" 2>/dev/null
}

# ── C1: a FULL retrieval carrying the incident's phrase.
C1="$(newtmp)"
C1_PAYLOAD="$(jq -n --arg t "$INCIDENT_TEXT" '{
  hook_event_name:"PostToolUse", tool_name:"mcp__qdrant__qdrant-find",
  tool_response:[{type:"text",text:"Results for the query"},
                 {type:"text",text:("<entry><content>lancache BL7 locked decisions: " + $t + " and eleven more</content></entry>")},
                 {type:"text",text:"<entry><content>another substantial memory with real prior context</content></entry>"}]}')"
C1_EMPTY="$(run_tracker "$C1/p" "$C1_PAYLOAD")"
if [ "$C1_EMPTY" = "false" ]; then
  pass "C1: a THREE-BLOCK retrieval whose text contains the incident's own sentence records qdrant_find_empty=false — it matched a memory ABOUT emptiness and called the retrieval empty"
else
  fail_ "C1" "qdrant_find_empty=$C1_EMPTY — wanted false on a full retrieval containing: $INCIDENT_TEXT"
fi

# ── C2: a genuinely empty retrieval is still caught, by shape.
C2="$(newtmp)"
C2_EMPTY="$(run_tracker "$C2/p" '{"hook_event_name":"PostToolUse","tool_name":"mcp__qdrant__qdrant-find","tool_response":[]}')"
if [ "$C2_EMPTY" = "true" ]; then
  pass "C2: zero content blocks -> qdrant_find_empty=true (shape, not prose)"
else
  fail_ "C2" "qdrant_find_empty=$C2_EMPTY — wanted true for a zero-length content array"
fi

# ── C3: all-whitespace text is empty by shape.
C3="$(newtmp)"
C3_EMPTY="$(run_tracker "$C3/p" '{"hook_event_name":"PostToolUse","tool_name":"mcp__qdrant__qdrant-find","tool_response":[{"type":"text","text":"   \n\t  "}]}')"
if [ "$C3_EMPTY" = "true" ]; then
  pass "C3: an all-whitespace payload -> qdrant_find_empty=true"
else
  fail_ "C3" "qdrant_find_empty=$C3_EMPTY — wanted true"
fi

# ── C4: an absent tool_response on a success event is empty by shape.
C4="$(newtmp)"
C4_EMPTY="$(run_tracker "$C4/p" '{"hook_event_name":"PostToolUse","tool_name":"mcp__qdrant__qdrant-find"}')"
if [ "$C4_EMPTY" = "true" ]; then
  pass "C4: tool_response absent on a success event -> qdrant_find_empty=true"
else
  fail_ "C4" "qdrant_find_empty=$C4_EMPTY — wanted true"
fi

# ── C5: the phrase list is GONE from the shipped file, and the accepted loss is
# real rather than claimed. A server that words a true zero result in prose now
# records false. Asserting the loss keeps the trade honest instead of implied.
C5="$(newtmp)"
C5_EMPTY="$(run_tracker "$C5/p" '{"hook_event_name":"PostToolUse","tool_name":"mcp__qdrant__qdrant-find","tool_response":[{"type":"text","text":"No results found for that query."}]}')"
# Comments are stripped before the grep: the shipped file DOCUMENTS the deleted
# regex verbatim (that documentation is the point — the next reader must be able
# to see what was removed and why), so a raw grep would match the explanation
# and report the code. Executed lines are what the claim is about. This strip is
# deliberately crude and is NOT the load-bearing proof — M5 is, by mutating a
# shape branch back into a phrase test and watching the incident fixture flip.
C5_REGEX=1
sed 's/[[:space:]]*#.*$//' "$TRACKER" 2>/dev/null | grep -q 'empty (result|collection)' && C5_REGEX=0
if [ "$C5_REGEX" = "1" ] && [ "$C5_EMPTY" = "false" ]; then
  pass "C5: the phrase regex is absent from the shipped tracker, and the accepted loss is real — prose-only 'No results found' inside a content block now records false (the lesser error: a missed true-empty, never a false alarm on a full memory)"
else
  fail_ "C5" "phrase-regex-absent=$C5_REGEX (want 1) qdrant_find_empty=$C5_EMPTY (want false)"
fi

echo ""
echo "=== E — check-versions.sh: the bound is real, and an UNBOUNDABLE fetch is 'cannot tell' ==="

# check_for_update is EXTRACTED from the shipped script and executed. Sourcing
# check-versions.sh whole would run its main body (it sets NETWORK_AVAILABLE and
# starts checking tools), so the function is lifted from its own opening line to
# its column-0 closing brace and run against stubs.
run_check_for_update() {
  local d="$1" repo="$2" with_rwt="$3"
  run_check_for_update_at "$CHECKVER" "$d" "$repo" "$with_rwt" || { printf 'NOFN\n'; return 1; }
  printf '%s\n' "$CVOUT"
}

# run_check_for_update_at <src> <workdir> <repo> <with_rwt> [env assignments...]
# The same extraction against an arbitrary (possibly MUTATED) copy of
# check-versions.sh, with env assignments and a WALL-CLOCK measurement — because
# "the fetch is bounded" is a claim about elapsed time, and greping the shipped
# file for the word `run_with_timeout` is a claim about spelling.
CVOUT=""; CVSECS=0
run_check_for_update_at() {
  local src="$1" d="$2" repo="$3" with_rwt="$4"; shift 4
  awk '/^check_for_update\(\)/{f=1} f{print} f&&/^}$/{exit}' "$src" > "$d/fn.sh"
  [ -s "$d/fn.sh" ] || { CVOUT="NOFN"; return 1; }
  local pre="" t0 t1
  [ "$with_rwt" = "yes" ] && pre=". \"$REPO_ROOT/scripts/lib/helpers-core.sh\" >/dev/null 2>&1"
  t0=$(date +%s)
  CVOUT="$(env "$@" "$BASH_BIN" -c "
    set -uo pipefail
    $pre
    . '$d/fn.sh'
    NETWORK_AVAILABLE=true
    check_for_update git_repo \"\$(jq -nc --arg p '$repo' '{path:\$p}')\"
    printf '%s|%s\n' \"\$UPDATE_CHECK_STATUS\" \"\$UPDATE_CHECK_MSG\"
  " 2>/dev/null)"
  t1=$(date +%s)
  CVSECS=$((t1 - t0))
  return 0
}

# mk_git_fetch_stub <bindir> <seconds> — a `git` that sleeps on `fetch` and is
# the real git for everything else. Exits 0 after sleeping, so an UNBOUNDED
# caller reads it as a SUCCESSFUL fetch — which is the failure mode being
# measured, not a crash.
mk_git_fetch_stub() {
  local b="$1" secs="$2"
  mkdir -p "$b"
  cat > "$b/git" << STUBEOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = "fetch" ]; then sleep $secs; exit 0; fi
done
exec "$REAL_GIT" "\$@"
STUBEOF
  chmod 755 "$b/git"
}

# ── E1: with the bounded runner available, the handler does its job.
E1="$(newtmp)"
build_fw "$E1/fw" "$E1/origin"
E1PIN="$PIN"
advance_origin "$E1/origin" "$E1/adv" || true
E1_OUT="$(run_check_for_update "$E1" "$E1/fw" yes)"
if printf '%s' "$E1_OUT" | grep -q '^behind|'; then
  pass "E1: with run_with_timeout available the git_repo handler fetches and reports the clone as behind ($E1_OUT)"
else
  fail_ "E1" "got '$E1_OUT' — wanted status 'behind' after a real bounded fetch of a local bare origin"
fi

# ── E2: THE ARM THE GUARD EXISTS FOR. check-versions.sh has a fallback that
# defines the colours and print_* inline when helpers-core.sh is missing — and
# that fallback does NOT define run_with_timeout. Unguarded, the bounded fetch
# would exit 127, `|| true` would swallow it, and the handler would compare
# STALE refs and report a currency verdict from a fetch that never ran. It must
# say "cannot tell" instead.
E2="$(newtmp)"
build_fw "$E2/fw" "$E2/origin"
advance_origin "$E2/origin" "$E2/adv" || true
E2_OUT="$(run_check_for_update "$E2" "$E2/fw" no)"
E2_STATUS="${E2_OUT%%|*}"
if [ "$E2_STATUS" = "unknown" ] && printf '%s' "$E2_OUT" | grep -qi 'cannot bound'; then
  pass "E2: with no bounded runner the handler reports 'unknown — cannot bound a fetch', instead of comparing refs a swallowed rc=127 left stale ($E2_OUT)"
else
  fail_ "E2" "got '$E2_OUT' — wanted status 'unknown' naming the unboundable fetch"
fi

# ── E3: THE ORDINARY PATH, which stayed broken while E2's exotic one was fixed.
# A fetch that FAILS WITHIN the bound — offline, remote deleted, auth gone — used
# to be swallowed by `|| true`, and the handler then compared HEAD against an
# origin/main no fetch had refreshed. Reproduced before the fix on a clone
# genuinely ONE COMMIT BEHIND its deleted origin with NETWORK_AVAILABLE=true:
# verdict `up_to_date`. Silent false reassurance for CDF and every `git_repo`
# tool while offline. The fixture is BEHIND on purpose: a fixture that is
# actually current would pass with the bug present.
E3="$(newtmp)"
build_fw "$E3/fw" "$E3/origin"
advance_origin "$E3/origin" "$E3/adv" || true
E3_LOCAL="$(_git -C "$E3/fw" rev-parse HEAD 2>/dev/null)"
E3_TRUE="$(_git -C "$E3/origin" rev-parse main 2>/dev/null)"
rm -rf "$E3/origin"                     # now unreachable, exactly like being offline
E3_OUT="$(run_check_for_update "$E3" "$E3/fw" yes)"
E3_STATUS="${E3_OUT%%|*}"
if [ -n "$E3_TRUE" ] && [ "$E3_LOCAL" != "$E3_TRUE" ] \
   && [ "$E3_STATUS" = "unknown" ] && printf '%s' "$E3_OUT" | grep -qi 'could not refresh refs'; then
  pass "E3: a clone genuinely behind an UNREACHABLE origin reports 'unknown — could not refresh refs' instead of the 'up_to_date' a failed fetch used to produce from stale refs ($E3_OUT)"
else
  fail_ "E3" "local=$E3_LOCAL true_origin=$E3_TRUE (must differ) got '$E3_OUT' — wanted status 'unknown' naming the failed refresh"
fi

# ── E4: THE BOUND, MEASURED. M6 asserted that the shipped file CONTAINS the
# word run_with_timeout, which this suite's own charter forbids ("not one
# assertion is satisfied by the presence of a call"). This one runs a git that
# sleeps 12s on `fetch` and asserts the WALL CLOCK, the same standard as A5/B6.
E4="$(newtmp)"
build_fw "$E4/fw" "$E4/origin"
mk_git_fetch_stub "$E4/bin" 12
run_check_for_update_at "$CHECKVER" "$E4" "$E4/fw" yes "PATH=$E4/bin:$PATH" "SOLO_FETCH_TIMEOUT=2"
E4_STATUS="${CVOUT%%|*}"
if [ "$CVSECS" -le 8 ] && [ "$E4_STATUS" = "unknown" ] \
   && printf '%s' "$CVOUT" | grep -qi 'could not refresh refs'; then
  pass "E4: a fetch that would hang for 12s is cut off at the 2s bound (measured ${CVSECS}s wall clock) and the handler says so rather than comparing stale refs"
else
  fail_ "E4" "elapsed=${CVSECS}s (want <=8) status='$E4_STATUS' (want unknown) out='$CVOUT'"
fi

# ── E5: A GARBAGE BOUND IS NOT A BOUND. Measured on this host:
# `run_with_timeout abc sleep 3` returns rc 0 after 3039ms — the `-ge` test
# errors on every iteration, the kill never fires, and the caller's
# `>/dev/null 2>&1` swallows the complaint. So a non-numeric SOLO_FETCH_TIMEOUT
# silently UNBOUNDS this fetch: the resurrected defect, one env var away. The
# assertion is on the EMITTED SENTENCE, which names the seconds actually used —
# `10s` once the value has been sanitized, `abcs` if it never was.
E5="$(newtmp)"
build_fw "$E5/fw" "$E5/origin"
rm -rf "$E5/origin"
run_check_for_update_at "$CHECKVER" "$E5" "$E5/fw" yes "SOLO_FETCH_TIMEOUT=abc"
E5_STATUS="${CVOUT%%|*}"
if [ "$E5_STATUS" = "unknown" ] && printf '%s' "$CVOUT" | grep -q '10s bound' \
   && ! printf '%s' "$CVOUT" | grep -q 'abcs bound'; then
  pass "E5: SOLO_FETCH_TIMEOUT=abc is sanitized to the 10s default before it reaches run_with_timeout — the emitted sentence names a NUMBER, so the bound can actually fire ($CVOUT)"
else
  fail_ "E5" "status='$E5_STATUS' (want unknown) out='$CVOUT' — wanted the message to name '10s bound' and never 'abcs bound'"
fi

echo ""
echo "=== D — the MCP ledger is runtime state, and git must be told so (BL-236) ==="

# ── D1: measured with git itself, not by greping the template.
D1="$(newtmp)"
mkdir -p "$D1/p/.claude"
cp "$GITIGNORE_TMPL" "$D1/p/.gitignore"
_git -C "$D1/p" init -q >/dev/null 2>&1
printf '{}\n' > "$D1/p/.claude/tool-usage.json"
if _git -C "$D1/p" check-ignore -q .claude/tool-usage.json 2>/dev/null; then
  pass "D1: a project scaffolded from the shipped .gitignore template IGNORES .claude/tool-usage.json (asserted with git check-ignore, not a grep)"
else
  fail_ "D1" "git check-ignore says .claude/tool-usage.json is still trackable"
fi

# ── D2: an ALREADY-scaffolded project gets the line from the upgrade backfill.
# The block is extracted from between its own fence markers and executed, so
# this asserts on the shipped backfill.
D2="$(newtmp)"
mkdir -p "$D2/p/.claude"
printf '{}\n' > "$D2/p/.claude/manifest.json"
printf '{}\n' > "$D2/p/.claude/tool-usage.json"
printf '# pre-existing\n*.log\n' > "$D2/p/.gitignore"
_git -C "$D2/p" init -q >/dev/null 2>&1
awk '/# BL-174-GITIGNORE-BACKFILL START$/{f=1;next} /# BL-174-GITIGNORE-BACKFILL END$/{f=0} f' \
  "$UPGRADE" > "$D2/backfill.sh"
if [ ! -s "$D2/backfill.sh" ]; then
  fail_ "D2" "could not extract the BL-174 backfill block from upgrade-project.sh"
else
  ( cd "$D2/p" && env -i HOME="$D2" PATH="$PATH" BF="$D2/backfill.sh" "$BASH_BIN" -c \
      'print_ok() { :; }; . "$BF"' >/dev/null 2>&1 )
  if _git -C "$D2/p" check-ignore -q .claude/tool-usage.json 2>/dev/null; then
    pass "D2: the upgrade backfill adds the ignore line to an ALREADY-scaffolded project (SYNC SIBLINGS: the template and the backfill are the file's two writers)"
  else
    fail_ "D2" "after running the shipped backfill, git still does not ignore .claude/tool-usage.json"
  fi
fi

# ── D3: the backfill is idempotent — running it twice must not duplicate lines.
D3_COUNT=0
if [ -s "$D2/backfill.sh" ]; then
  ( cd "$D2/p" && env -i HOME="$D2" PATH="$PATH" BF="$D2/backfill.sh" "$BASH_BIN" -c \
      'print_ok() { :; }; . "$BF"' >/dev/null 2>&1 )
  D3_COUNT=$(grep -cxF '.claude/tool-usage.json' "$D2/p/.gitignore" 2>/dev/null)
  D3_COUNT=$(_num "$D3_COUNT")
fi
if [ "$D3_COUNT" = "1" ]; then
  pass "D3: running the backfill a second time leaves exactly one ignore line (idempotent, like its two siblings)"
else
  fail_ "D3" "found $D3_COUNT copies of the ignore line after two backfill runs (want 1)"
fi

echo ""
echo "=== M — mutation proofs (each: sites==1, N lines changed, bash -n, fresh fixture) ==="

mk_mirror_lib() {
  local m="$1"
  mkdir -p "$m/scripts/lib" || return 1
  cp -p "$REPO_ROOT/scripts/session-freshness-check.sh" "$m/scripts/" || return 1
  cp -p "$FRESH_LIB" "$m/scripts/lib/" || return 1
  for f in currency-manifest.sh hook-templates.sh bypass-audit.sh helpers-core.sh; do
    [ -f "$REPO_ROOT/scripts/lib/$f" ] && cp -p "$REPO_ROOT/scripts/lib/$f" "$m/scripts/lib/"
  done
  return 0
}

# ── M1: delete the fetch. This is the shipped code before BL-234, and A1 is the
# direction that must die.
M1="$(newtmp)"
if ! mk_mirror_lib "$M1/m"; then
  fail_ "M1" "mirror setup failed"
else
  # A FRESH FRAMEWORK CLONE PER DIRECTION, not just a fresh project. The control
  # run FETCHES, and a fetch mutates the clone's remote-tracking refs — so a
  # mutant sharing that clone would read an origin/main the control run already
  # advanced and "report drift" with the fetch removed. This suite hit that
  # exact failure and it is the sharpest form of the fresh-fixture rule: the
  # thing under test writes to the fixture.
  build_fw "$M1/fw1" "$M1/origin1"; M1PIN1="$PIN"
  advance_origin "$M1/origin1" "$M1/adv1" || true
  build_proj "$M1/p1" "$M1/fw1" "$M1PIN1"
  run_fresh_at "$M1/m/scripts/session-freshness-check.sh" "$M1/p1"
  m1_ctl=no; printf '%s' "$FOUT" | grep -q 'pin-behind-upstream' && m1_ctl=yes
  m1_meta=$(_mutate "$M1/m/scripts/lib/freshness-detect.sh" '# BL-234-FETCH-REVERSAL' '  _fetch_rc=2')
  set -- $m1_meta; m1_sites=$1; m1_changed=$2; m1_parses=$3
  build_fw "$M1/fw2" "$M1/origin2"; M1PIN2="$PIN"
  advance_origin "$M1/origin2" "$M1/adv2" || true
  build_proj "$M1/p2" "$M1/fw2" "$M1PIN2"
  run_fresh_at "$M1/m/scripts/session-freshness-check.sh" "$M1/p2"
  m1_mut=no; printf '%s' "$FOUT" | grep -q 'pin-behind-upstream' && m1_mut=yes
  if [ "$m1_ctl" = "yes" ] && [ "$m1_mut" = "no" ] \
     && [ "$m1_sites" -eq 1 ] && [ "$m1_changed" -eq 2 ] && [ "$m1_parses" -eq 1 ]; then
    pass "M1: control reports the clone is behind its origin; with the fetch removed the SAME behind-clone reports nothing — BL-234's silence, restored on demand"
  else
    fail_ "M1" "control=$m1_ctl (want yes) mutant=$m1_mut (want no) sites=$m1_sites changed=$m1_changed parses=$m1_parses"
  fi
fi

# ── M2: delete the reference-age fallback. The fetch still runs and still fails;
# only the honest report goes away. This is the mutant that proves A3/A4/A6 are
# testing the fallback and not merely the absence of a crash.
M2="$(newtmp)"
if ! mk_mirror_lib "$M2/m"; then
  fail_ "M2" "mirror setup failed"
else
  build_fw "$M2/fw"; M2PIN="$PIN"
  build_proj "$M2/p1" "$M2/fw" "$M2PIN"
  run_fresh_at "$M2/m/scripts/session-freshness-check.sh" "$M2/p1"
  m2_ctl=no; printf '%s' "$FOUT" | grep -q 'fw-reference-age' && m2_ctl=yes
  m2_meta=$(_mutate "$M2/m/scripts/lib/freshness-detect.sh" '# BL-234-REFERENCE-AGE' '    :')
  set -- $m2_meta; m2_sites=$1; m2_changed=$2; m2_parses=$3
  build_proj "$M2/p2" "$M2/fw" "$M2PIN"
  run_fresh_at "$M2/m/scripts/session-freshness-check.sh" "$M2/p2"
  m2_mut=no; printf '%s' "$FOUT" | grep -q 'fw-reference-age' && m2_mut=yes
  if [ "$m2_ctl" = "yes" ] && [ "$m2_mut" = "no" ] \
     && [ "$m2_sites" -eq 1 ] && [ "$m2_changed" -eq 2 ] && [ "$m2_parses" -eq 1 ]; then
    pass "M2: control names the unfetchable reference; with only the emit removed the check goes SILENT while still failing to fetch — the exact shape this package exists to remove"
  else
    fail_ "M2" "control=$m2_ctl (want yes) mutant=$m2_mut (want no) sites=$m2_sites changed=$m2_changed parses=$m2_parses"
  fi
fi

# ── M3: unbound the fetch. Proves A5's wall clock is load-bearing.
M3="$(newtmp)"
if ! mk_mirror_lib "$M3/m"; then
  fail_ "M3" "mirror setup failed"
else
  build_fw "$M3/fw" "$M3/origin"; M3PIN="$PIN"
  mkdir -p "$M3/bin"
  cat > "$M3/bin/git" << STUBEOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = "fetch" ]; then sleep 12; exit 0; fi
done
exec "$REAL_GIT" "\$@"
STUBEOF
  chmod 755 "$M3/bin/git"
  build_proj "$M3/p1" "$M3/fw" "$M3PIN"
  m3_t0=$(date +%s)
  run_fresh_at "$M3/m/scripts/session-freshness-check.sh" "$M3/p1" "PATH=$M3/bin:$PATH" "SOIF_FRESHNESS_FETCH_TIMEOUT=2"
  m3_t1=$(date +%s); m3_ctl=$((m3_t1 - m3_t0))
  m3_meta=$(_mutate "$M3/m/scripts/lib/freshness-detect.sh" '# BL-234-FETCH-BOUND' '  if git -C "$d" fetch --quiet --no-tags >/dev/null 2>&1; then')
  set -- $m3_meta; m3_sites=$1; m3_changed=$2; m3_parses=$3
  build_proj "$M3/p2" "$M3/fw" "$M3PIN"
  m3_t2=$(date +%s)
  run_fresh_at "$M3/m/scripts/session-freshness-check.sh" "$M3/p2" "PATH=$M3/bin:$PATH" "SOIF_FRESHNESS_FETCH_TIMEOUT=2"
  m3_t3=$(date +%s); m3_mut=$((m3_t3 - m3_t2))
  if [ "$m3_ctl" -le 8 ] && [ "$m3_mut" -ge 11 ] \
     && [ "$m3_sites" -eq 1 ] && [ "$m3_changed" -eq 2 ] && [ "$m3_parses" -eq 1 ]; then
    pass "M3: control returns in ${m3_ctl}s against a 12s fetch; with run_with_timeout removed the same session-start hook takes ${m3_mut}s — the bound is doing the work, not the flag"
  else
    fail_ "M3" "control=${m3_ctl}s (want <=8) mutant=${m3_mut}s (want >=11) sites=$m3_sites changed=$m3_changed parses=$m3_parses"
  fi
fi

# ── M4: make the Qdrant predicate ignore reachability again — BL-234 item 2,
# restored in one line.
M4="$(newtmp)"
mkdir -p "$M4/lib"
cp -p "$HELPERS_FULL" "$M4/lib/helpers-full.sh"
cp -p "$REPO_ROOT/scripts/lib/helpers-core.sh" "$M4/lib/helpers-core.sh"
mk_home "$M4/home" "http://127.0.0.1:1"
m4_ctl_out="$(env -i HOME="$M4/home" PATH="$PATH" "$BASH_BIN" -c '. "'"$M4/lib/helpers-full.sh"'" >/dev/null 2>&1; rc=0; is_qdrant_mcp_registered || rc=$?; printf "%s\n" "$rc"' 2>/dev/null)"
m4_meta=$(_mutate "$M4/lib/helpers-full.sh" '# BL-234-QDRANT-PREDICATE' '  _qmr_rc=0')
set -- $m4_meta; m4_sites=$1; m4_changed=$2; m4_parses=$3
mk_home "$M4/home2" "http://127.0.0.1:1"
m4_mut_out="$(env -i HOME="$M4/home2" PATH="$PATH" "$BASH_BIN" -c '. "'"$M4/lib/helpers-full.sh"'" >/dev/null 2>&1; rc=0; is_qdrant_mcp_registered || rc=$?; printf "%s\n" "$rc"' 2>/dev/null)"
if [ "$m4_ctl_out" != "0" ] && [ "$m4_mut_out" = "0" ] \
   && [ "$m4_sites" -eq 1 ] && [ "$m4_changed" -eq 2 ] && [ "$m4_parses" -eq 1 ]; then
  pass "M4: control refuses a dead registration (rc=$m4_ctl_out); with the probe result discarded the same dead entry reports 'registered' (rc=$m4_mut_out) — the stale-entry short-circuit, back in one line"
else
  fail_ "M4" "control=$m4_ctl_out (want non-zero) mutant=$m4_mut_out (want 0) sites=$m4_sites changed=$m4_changed parses=$m4_parses"
fi

# ── M5: STRUCTURAL DISCRIMINATOR for the deleted phrase half. An absence cannot
# be greped for as proof, so a shape line is mutated back INTO a phrase match and
# the incident fixture is shown flipping.
M5="$(newtmp)"
mkdir -p "$M5/m"
cp -p "$TRACKER" "$M5/m/tracker.sh"
run_tracker_at() {
  local sut="$1" d="$2" payload="$3"
  mkdir -p "$d/.claude"
  printf '%s' "$payload" | ( cd "$d" && "$BASH_BIN" "$sut" --event PostToolUse >/dev/null 2>&1 )
  jq -r '.qdrant_find_empty' "$d/.claude/tool-usage.json" 2>/dev/null
}
m5_ctl="$(run_tracker_at "$M5/m/tracker.sh" "$M5/p1" "$C1_PAYLOAD")"
# The replacement must contain NO `%` — that is this harness's sed delimiter,
# and a `%` inside it terminates the expression early, leaving the file
# unchanged WHILE SED REPORTS SUCCESS (CLAUDE.md's sed trap). The first draft
# used `printf "%s"` here and sed refused it outright; a quieter `%` would have
# produced a mutant that was never applied and scored as killed.
m5_meta=$(_mutate "$M5/m/tracker.sh" '# BL-234-EMPTY-SHAPE-ONLY' '  elif echo "$RESPONSE_TEXT" | grep -qiE "empty (result|collection)" 2>/dev/null; then IS_EMPTY=1')
set -- $m5_meta; m5_sites=$1; m5_changed=$2; m5_parses=$3
m5_mut="$(run_tracker_at "$M5/m/tracker.sh" "$M5/p2" "$C1_PAYLOAD")"
if [ "$m5_ctl" = "false" ] && [ "$m5_mut" = "true" ] \
   && [ "$m5_sites" -eq 1 ] && [ "$m5_changed" -eq 2 ] && [ "$m5_parses" -eq 1 ]; then
  pass "M5: control records the ten-memory retrieval as NOT empty; with a phrase test spliced back into the shape branch the same full retrieval reports EMPTY — the live 2026-08-14 incident, reproduced on demand"
else
  fail_ "M5" "control=$m5_ctl (want false) mutant=$m5_mut (want true) sites=$m5_sites changed=$m5_changed parses=$m5_parses"
fi

# ── M6: restore `|| true` — the bounded-but-DISCARDED fetch outcome. This mutant
# used to assert only that the shipped file CONTAINS `run_with_timeout`, which is
# a claim about spelling and is exactly what this suite's charter refuses. It now
# RUNS both directions against E3's fixture: a clone behind an unreachable
# origin. Control says it could not refresh; the mutant swallows the failure and
# reports `up_to_date` — the §8 finding, restored in one marked line.
M6="$(newtmp)"
mkdir -p "$M6/scripts/lib"
cp -p "$CHECKVER" "$M6/scripts/check-versions.sh"
build_fw "$M6/fw" "$M6/origin"
advance_origin "$M6/origin" "$M6/adv" || true
rm -rf "$M6/origin"
m6_ctl_out="$(run_check_for_update "$M6" "$M6/fw" yes)"
m6_ctl="${m6_ctl_out%%|*}"
m6_meta=$(_mutate "$M6/scripts/check-versions.sh" '# BL-234-CHECKVERSIONS-TIMEOUT' '        git -C "$repo_path" fetch --quiet 2>/dev/null || true')
set -- $m6_meta; m6_sites=$1; m6_changed=$2; m6_parses=$3
build_fw "$M6/fw2" "$M6/origin2"
advance_origin "$M6/origin2" "$M6/adv2" || true
rm -rf "$M6/origin2"
run_check_for_update_at "$M6/scripts/check-versions.sh" "$M6" "$M6/fw2" yes
m6_mut="${CVOUT%%|*}"
if [ "$m6_ctl" = "unknown" ] && [ "$m6_mut" = "up_to_date" ] \
   && [ "$m6_sites" -eq 1 ] && [ "$m6_changed" -eq 2 ] && [ "$m6_parses" -eq 1 ]; then
  pass "M6: control refuses to compare refs a failed fetch left stale; with the outcome discarded by \`|| true\` the same behind-and-offline clone is reported '$m6_mut' — a currency verdict from a fetch that never landed"
else
  fail_ "M6" "control=$m6_ctl (want unknown) mutant=$m6_mut (want up_to_date) sites=$m6_sites changed=$m6_changed parses=$m6_parses"
fi

# ── M8: delete the seconds guard. E5's sanitized `10s` becomes the raw `abcs`,
# which run_with_timeout cannot compare against — so the kill never fires and the
# fetch is unbounded again, silently. One line, and the only visible difference
# is three characters in a sentence nobody reads until they are offline.
M8="$(newtmp)"
mkdir -p "$M8/scripts"
cp -p "$CHECKVER" "$M8/scripts/check-versions.sh"
build_fw "$M8/fw" "$M8/origin"
rm -rf "$M8/origin"
run_check_for_update_at "$CHECKVER" "$M8" "$M8/fw" yes "SOLO_FETCH_TIMEOUT=abc"
m8_ctl=no; printf '%s' "$CVOUT" | grep -q '10s bound' && m8_ctl=yes
m8_meta=$(_mutate "$M8/scripts/check-versions.sh" '# BL-234-CHECKVERSIONS-SECS' '        _cv_secs="${SOLO_FETCH_TIMEOUT:-10}"')
set -- $m8_meta; m8_sites=$1; m8_changed=$2; m8_parses=$3
build_fw "$M8/fw2" "$M8/origin2"
rm -rf "$M8/origin2"
run_check_for_update_at "$M8/scripts/check-versions.sh" "$M8" "$M8/fw2" yes "SOLO_FETCH_TIMEOUT=abc"
m8_mut=no; printf '%s' "$CVOUT" | grep -q 'abcs bound' && m8_mut=yes
if [ "$m8_ctl" = "yes" ] && [ "$m8_mut" = "yes" ] \
   && [ "$m8_sites" -eq 1 ] && [ "$m8_changed" -eq 2 ] && [ "$m8_parses" -eq 1 ]; then
  pass "M8: control sanitizes a garbage SOLO_FETCH_TIMEOUT to 10s; with the guard removed the raw 'abc' reaches run_with_timeout, whose -ge test then errors on every iteration and never kills"
else
  fail_ "M8" "control=$m8_ctl (want yes) mutant=$m8_mut (want yes) sites=$m8_sites changed=$m8_changed parses=$m8_parses"
fi

# ── M7: THE ONE-CHARACTER MUTANT, KILLED BY NAME. `-eq 0` -> `-lt 0` in
# _soif_fresh_last_fetch. A size is never negative, so the `failed` arm becomes
# unreachable and every truncated FETCH_HEAD is read as a SUCCESS whose mtime is
# our own failed attempt. Measured before this test existed: the mutant left
# this suite at 29/0, test-freshness-check at 26/0, test-freshness-birth at 8/0
# and all 172 unit-lane suites green, while the shipped wrapper emitted
# "last fetched 0 day(s) ago" on a clone that had not fetched successfully in
# months. The discriminator is the EMITTED SENTENCE in both directions, not the
# presence of the branch.
M7="$(newtmp)"
if ! mk_mirror_lib "$M7/m"; then
  fail_ "M7" "mirror setup failed"
else
  build_fw_failed_fetch "$M7/c"
  build_proj "$M7/p1" "$M7/c/fw" "$PIN"
  m7_ctl_sz="$(_fh_size "$(_fh_of "$M7/c/fw")")"
  run_fresh_at "$M7/m/scripts/session-freshness-check.sh" "$M7/p1"
  m7_ctl=no; printf '%s' "$FOUT" | grep -q 'UNKNOWN time' && m7_ctl=yes
  m7_meta=$(_mutate "$M7/m/scripts/lib/freshness-detect.sh" '# BL-234-FETCH-FAILED-SIZE' '  if [ "$sz" -lt 0 ]; then printf '"'"'failed'"'"'; return 0; fi')
  set -- $m7_meta; m7_sites=$1; m7_changed=$2; m7_parses=$3
  build_fw_failed_fetch "$M7/d"          # FRESH clone: the control run's own fetch rewrites FETCH_HEAD
  build_proj "$M7/p2" "$M7/d/fw" "$PIN"
  m7_mut_sz="$(_fh_size "$(_fh_of "$M7/d/fw")")"
  run_fresh_at "$M7/m/scripts/session-freshness-check.sh" "$M7/p2"
  m7_mut=no; printf '%s' "$FOUT" | grep -q 'last fetched 0 day' && m7_mut=yes
  if [ "$m7_ctl_sz" = "0" ] && [ "$m7_mut_sz" = "0" ] \
     && [ "$m7_ctl" = "yes" ] && [ "$m7_mut" = "yes" ] \
     && [ "$m7_sites" -eq 1 ] && [ "$m7_changed" -eq 2 ] && [ "$m7_parses" -eq 1 ]; then
    pass "M7: control calls a truncated FETCH_HEAD an UNKNOWN fetch time; with -eq 0 changed to -lt 0 the SAME clone reports 'last fetched 0 day(s) ago' — one character, still parses, and it is false reassurance rather than silence"
  else
    fail_ "M7" "ctl_size=$m7_ctl_sz mut_size=$m7_mut_sz (both want 0) control=$m7_ctl (want yes) mutant=$m7_mut (want yes) sites=$m7_sites changed=$m7_changed parses=$m7_parses"
  fi
fi

# ── M9: collapse the two not-attempted causes back into one. The runner-missing
# return becomes the no-remote return, and the shipped wrapper then tells an
# operator whose remote is fine that their clone has no remote configured. The
# discriminator is the SENTENCE, in both directions — the exit code is 0 either
# way, which is precisely why one code for three causes survived review.
M9="$(newtmp)"
mkdir -p "$M9/m/scripts/lib"
cp -p "$REPO_ROOT/scripts/session-freshness-check.sh" "$M9/m/scripts/"
cp -p "$FRESH_LIB" "$M9/m/scripts/lib/"
for f in currency-manifest.sh hook-templates.sh bypass-audit.sh; do
  [ -f "$REPO_ROOT/scripts/lib/$f" ] && cp -p "$REPO_ROOT/scripts/lib/$f" "$M9/m/scripts/lib/"
done                                    # helpers-core.sh withheld, as in A9
build_fw "$M9/fw" "$M9/origin"; M9PIN="$PIN"
build_proj "$M9/p1" "$M9/fw" "$M9PIN"
run_fresh_at "$M9/m/scripts/session-freshness-check.sh" "$M9/p1"
m9_ctl=no; printf '%s' "$FOUT" | grep -q 'no bounded runner' && m9_ctl=yes
m9_meta=$(_mutate "$M9/m/scripts/lib/freshness-detect.sh" '# BL-234-TRYFETCH-NORUNNER' '  command -v run_with_timeout >/dev/null 2>&1 || return 4')
set -- $m9_meta; m9_sites=$1; m9_changed=$2; m9_parses=$3
build_proj "$M9/p2" "$M9/fw" "$M9PIN"
run_fresh_at "$M9/m/scripts/session-freshness-check.sh" "$M9/p2"
m9_mut=no; printf '%s' "$FOUT" | grep -q 'no remote configured' && m9_mut=yes
if [ "$m9_ctl" = "yes" ] && [ "$m9_mut" = "yes" ] \
   && [ "$m9_sites" -eq 1 ] && [ "$m9_changed" -eq 2 ] && [ "$m9_parses" -eq 1 ]; then
  pass "M9: control names the missing bounded runner; with the two causes sharing one return code the SAME clone — remote intact — is told it has no remote configured, which is a false factual claim in the one feature about honest wording"
else
  fail_ "M9" "control=$m9_ctl (want yes) mutant=$m9_mut (want yes) sites=$m9_sites changed=$m9_changed parses=$m9_parses"
fi

# ── M10: drop 22 from the reachable set. The secured server that B7 calls
# reachable goes back to being called dead, in one line, with no exit code
# anywhere in the framework changing except the predicate's own.
M10="$(newtmp)"
mkdir -p "$M10/lib"
cp -p "$HELPERS_FULL" "$M10/lib/helpers-full.sh"
cp -p "$REPO_ROOT/scripts/lib/helpers-core.sh" "$M10/lib/helpers-core.sh"
if ! start_keyed_qdrant "$M10" "sekret"; then
  fail_ "M10" "fixture: could not start the local keyed stub HTTP server"
else
  mk_home "$M10/home" "http://127.0.0.1:$QSRV_PORT"
  m10_ctl="$(env -i HOME="$M10/home" PATH="$PATH" "$BASH_BIN" -c '. "'"$M10/lib/helpers-full.sh"'" >/dev/null 2>&1; rc=0; is_qdrant_mcp_registered || rc=$?; printf "%s\n" "${QDRANT_MCP_STATE:-UNSET}"' 2>/dev/null)"
  m10_meta=$(_mutate "$M10/lib/helpers-full.sh" '# BL-234-QDRANT-REACHABLE' '  case "$rc" in 0) return 0 ;; esac')
  set -- $m10_meta; m10_sites=$1; m10_changed=$2; m10_parses=$3
  mk_home "$M10/home2" "http://127.0.0.1:$QSRV_PORT"
  m10_mut="$(env -i HOME="$M10/home2" PATH="$PATH" "$BASH_BIN" -c '. "'"$M10/lib/helpers-full.sh"'" >/dev/null 2>&1; rc=0; is_qdrant_mcp_registered || rc=$?; printf "%s\n" "${QDRANT_MCP_STATE:-UNSET}"' 2>/dev/null)"
  stop_stub_qdrant
  if [ "$m10_ctl" = "reachable" ] && [ "$m10_mut" = "unreachable" ] \
     && [ "$m10_sites" -eq 1 ] && [ "$m10_changed" -eq 2 ] && [ "$m10_parses" -eq 1 ]; then
    pass "M10: control calls a 401-answering server reachable; with 22 dropped from the reachable set the SAME answering server is scored '$m10_mut' — a working secured memory reported as a stale registration"
  else
    fail_ "M10" "control=$m10_ctl (want reachable) mutant=$m10_mut (want unreachable) sites=$m10_sites changed=$m10_changed parses=$m10_parses"
  fi
fi

# ── M11: stop sending the key. Both directions still say "reachable" (22 is an
# answer), so the ONLY discriminator is what the SERVER saw — which is why the
# stub logs AUTH/NOKEY per request. A test asserting the state alone would have
# passed with the header silently dropped.
M11="$(newtmp)"
mkdir -p "$M11/lib"
cp -p "$HELPERS_FULL" "$M11/lib/helpers-full.sh"
cp -p "$REPO_ROOT/scripts/lib/helpers-core.sh" "$M11/lib/helpers-core.sh"
if ! start_keyed_qdrant "$M11" "sekret"; then
  fail_ "M11" "fixture: could not start the local keyed stub HTTP server"
else
  mk_home "$M11/home" "http://127.0.0.1:$QSRV_PORT" "sekret"
  env -i HOME="$M11/home" PATH="$PATH" "$BASH_BIN" -c '. "'"$M11/lib/helpers-full.sh"'" >/dev/null 2>&1; is_qdrant_mcp_registered' >/dev/null 2>&1
  m11_ctl="$(grep -c 'AUTH' "$M11/hits.log" 2>/dev/null | tr -d ' ')"
  : > "$M11/hits.log"
  m11_meta=$(_mutate "$M11/lib/helpers-full.sh" '# BL-234-QDRANT-KEY-HEADER' '  key=""')
  set -- $m11_meta; m11_sites=$1; m11_changed=$2; m11_parses=$3
  mk_home "$M11/home2" "http://127.0.0.1:$QSRV_PORT" "sekret"
  env -i HOME="$M11/home2" PATH="$PATH" "$BASH_BIN" -c '. "'"$M11/lib/helpers-full.sh"'" >/dev/null 2>&1; is_qdrant_mcp_registered' >/dev/null 2>&1
  m11_mut_auth="$(grep -c 'AUTH' "$M11/hits.log" 2>/dev/null | tr -d ' ')"
  m11_mut_nokey="$(grep -c 'NOKEY' "$M11/hits.log" 2>/dev/null | tr -d ' ')"
  stop_stub_qdrant
  if [ "${m11_ctl:-0}" != "0" ] && [ "${m11_mut_auth:-0}" = "0" ] && [ "${m11_mut_nokey:-0}" != "0" ] \
     && [ "$m11_sites" -eq 1 ] && [ "$m11_changed" -eq 2 ] && [ "$m11_parses" -eq 1 ]; then
    pass "M11: control authenticates ($m11_ctl keyed request(s) seen by the server); with the registration's key discarded the same probe arrives UNKEYED ($m11_mut_nokey 401s) — asserted on the server's log, because the predicate's answer is 'reachable' either way"
  else
    fail_ "M11" "control_auth=$m11_ctl (want >0) mutant_auth=$m11_mut_auth (want 0) mutant_nokey=$m11_mut_nokey (want >0) sites=$m11_sites changed=$m11_changed parses=$m11_parses"
  fi
fi

# ── M12: send the key unconditionally. Both directions still return 0, so the
# ONLY visible difference is that the credential now arrives at a host the
# registration never named. M11 mutates the same line in the other direction
# (never send it); together they pin that the key is sent EXACTLY when it should
# be, which neither mutant proves alone.
M12="$(newtmp)"
mkdir -p "$M12/lib"
cp -p "$HELPERS_FULL" "$M12/lib/helpers-full.sh"
cp -p "$REPO_ROOT/scripts/lib/helpers-core.sh" "$M12/lib/helpers-core.sh"
if ! start_keyed_qdrant "$M12" "sekret"; then
  fail_ "M12" "fixture: could not start the local keyed stub HTTP server"
else
  mk_home "$M12/home" "http://127.0.0.1:1" "sekret"
  env -i HOME="$M12/home" PATH="$PATH" QPORT="$QSRV_PORT" "$BASH_BIN" -c '. "'"$M12/lib/helpers-full.sh"'" >/dev/null 2>&1; qdrant_probe_reachable "http://127.0.0.1:$QPORT"' >/dev/null 2>&1
  m12_ctl_auth="$(grep -c 'AUTH' "$M12/hits.log" 2>/dev/null | tr -d ' ')"
  : > "$M12/hits.log"
  m12_meta=$(_mutate "$M12/lib/helpers-full.sh" '# BL-234-QDRANT-KEY-HEADER' '  key="$(qdrant_mcp_api_key)"')
  set -- $m12_meta; m12_sites=$1; m12_changed=$2; m12_parses=$3
  mk_home "$M12/home2" "http://127.0.0.1:1" "sekret"
  env -i HOME="$M12/home2" PATH="$PATH" QPORT="$QSRV_PORT" "$BASH_BIN" -c '. "'"$M12/lib/helpers-full.sh"'" >/dev/null 2>&1; qdrant_probe_reachable "http://127.0.0.1:$QPORT"' >/dev/null 2>&1
  m12_mut_auth="$(grep -c 'AUTH' "$M12/hits.log" 2>/dev/null | tr -d ' ')"
  stop_stub_qdrant
  if [ "${m12_ctl_auth:-0}" = "0" ] && [ "${m12_mut_auth:-0}" != "0" ] \
     && [ "$m12_sites" -eq 1 ] && [ "$m12_changed" -eq 2 ] && [ "$m12_parses" -eq 1 ]; then
    pass "M12: control sends no credential to an unregistered host ($m12_ctl_auth keyed request(s)); with the scope test removed the same probe hands the api-key to a server the registration never named ($m12_mut_auth) — and returns 0 either way"
  else
    fail_ "M12" "control_auth=$m12_ctl_auth (want 0) mutant_auth=$m12_mut_auth (want >0) sites=$m12_sites changed=$m12_changed parses=$m12_parses"
  fi
fi

# ── M13: restore the PER-FIELD fallback. The key is read with claude.json-first
# fallback of its own instead of from the entry the URL came from, and B10's
# cross-file fixture immediately hands `crosskey` to a host whose registration
# never mentioned it. The predicate answers "reachable" in both directions —
# only the SERVER'S log distinguishes them, which is why B10 reads it.
M13="$(newtmp)"
mkdir -p "$M13/lib"
cp -p "$HELPERS_FULL" "$M13/lib/helpers-full.sh"
cp -p "$REPO_ROOT/scripts/lib/helpers-core.sh" "$M13/lib/helpers-core.sh"
if ! start_keyed_qdrant "$M13" "sekret"; then
  fail_ "M13" "fixture: could not start the local keyed stub HTTP server"
else
  mk_home "$M13/home" "http://127.0.0.1:$QSRV_PORT"
  mk_home_settings "$M13/home" "http://127.0.0.1:1" "crosskey"
  env -i HOME="$M13/home" PATH="$PATH" "$BASH_BIN" -c '. "'"$M13/lib/helpers-full.sh"'" >/dev/null 2>&1; is_qdrant_mcp_registered' >/dev/null 2>&1
  m13_ctl="$(grep -cE 'AUTH|WRONGKEY' "$M13/hits.log" 2>/dev/null | tr -d ' ')"
  case "$m13_ctl" in ''|*[!0-9]*) m13_ctl=0 ;; esac
  : > "$M13/hits.log"
  # ONE marked line: the key read stops using the entry the URL came from and
  # goes back to its OWN claude.json-then-settings.json fallback. That is the
  # whole pre-fix behaviour, and it is all the pairing defect ever was.
  #
  # THE jq FILTER IS SINGLE-QUOTED HERE, and that is not style. The first draft
  # wrote it double-quoted with `\"` around the mcp-server-qdrant alias — and
  # SED'S REPLACEMENT COLLAPSES `\"` TO `"`, so the file received a bare `"`
  # inside an already-double-quoted argument. The result parsed (`bash -n` said
  # yes), jq then failed on a broken filter, the key came back EMPTY, and the
  # mutant scored as killed while testing nothing. Same family as CLAUDE.md's
  # `s|` and `&` traps: a mutant that lands, parses, and is inert. Caught only
  # because this assertion reads the SERVER'S log instead of an exit code.
  m13_meta=$(_mutate "$M13/lib/helpers-full.sh" '# BL-234-QDRANT-KEY-ENTRY' '  k=$(jq -r '"'"'.mcpServers.qdrant.env.QDRANT_API_KEY // empty'"'"' "$HOME/.claude.json" 2>/dev/null); [ -n "$k" ] || k=$(jq -r '"'"'.mcpServers.qdrant.env.QDRANT_API_KEY // empty'"'"' "$HOME/.claude/settings.json" 2>/dev/null)')
  set -- $m13_meta; m13_sites=$1; m13_changed=$2; m13_parses=$3
  mk_home "$M13/home2" "http://127.0.0.1:$QSRV_PORT"
  mk_home_settings "$M13/home2" "http://127.0.0.1:1" "crosskey"
  env -i HOME="$M13/home2" PATH="$PATH" "$BASH_BIN" -c '. "'"$M13/lib/helpers-full.sh"'" >/dev/null 2>&1; is_qdrant_mcp_registered' >/dev/null 2>&1
  m13_mut="$(grep -cE 'AUTH|WRONGKEY' "$M13/hits.log" 2>/dev/null | tr -d ' ')"
  case "$m13_mut" in ''|*[!0-9]*) m13_mut=0 ;; esac
  stop_stub_qdrant
  if [ "$m13_ctl" = "0" ] && [ "$m13_mut" != "0" ] \
     && [ "$m13_sites" -eq 1 ] && [ "$m13_changed" -eq 2 ] && [ "$m13_parses" -eq 1 ]; then
    pass "M13: control sends NO credential to a host whose own entry carries none ($m13_ctl requests carried one); with the key read per-file instead of per-entry the OTHER file's key arrives at this host ($m13_mut) — the cross-file pairing, restored in one line"
  else
    fail_ "M13" "control_auth=$m13_ctl (want 0) mutant_auth=$m13_mut (want >0) sites=$m13_sites changed=$m13_changed parses=$m13_parses"
  fi
fi

# ── M14: put the credential back on argv. Both directions authenticate and both
# return 0 — the ONLY difference is that `ps` can read the secret in one of them.
# A test asserting "the probe worked" cannot see this; the stub's argv log can.
M14="$(newtmp)"
mkdir -p "$M14/lib"
cp -p "$HELPERS_FULL" "$M14/lib/helpers-full.sh"
cp -p "$REPO_ROOT/scripts/lib/helpers-core.sh" "$M14/lib/helpers-core.sh"
mk_curl_stub "$M14/bin" "$M14/rec"
mk_home "$M14/home" "http://127.0.0.1:6399" "argvsecret"
env -i HOME="$M14/home" PATH="$M14/bin:$PATH" "$BASH_BIN" -c '. "'"$M14/lib/helpers-full.sh"'" >/dev/null 2>&1; qdrant_probe_reachable' >/dev/null 2>&1
m14_ctl=$(grep -c 'argvsecret' "$M14/rec/argv.log" 2>/dev/null | tr -d ' ')
case "$m14_ctl" in ''|*[!0-9]*) m14_ctl=0 ;; esac
: > "$M14/rec/argv.log"; : > "$M14/rec/config.log"
m14_meta=$(_mutate "$M14/lib/helpers-full.sh" '# BL-234-QDRANT-KEY-STDIN' '    run_with_timeout "$secs" curl -fsS --max-time "$secs" -o /dev/null -H "api-key: $esc" "$u" >/dev/null 2>&1 || rc=$?')
set -- $m14_meta; m14_sites=$1; m14_changed=$2; m14_parses=$3
mk_home "$M14/home2" "http://127.0.0.1:6399" "argvsecret"
env -i HOME="$M14/home2" PATH="$M14/bin:$PATH" "$BASH_BIN" -c '. "'"$M14/lib/helpers-full.sh"'" >/dev/null 2>&1; qdrant_probe_reachable' >/dev/null 2>&1
m14_mut=$(grep -c 'argvsecret' "$M14/rec/argv.log" 2>/dev/null | tr -d ' ')
case "$m14_mut" in ''|*[!0-9]*) m14_mut=0 ;; esac
if [ "$m14_ctl" = "0" ] && [ "$m14_mut" != "0" ] \
   && [ "$m14_sites" -eq 1 ] && [ "$m14_changed" -eq 2 ] && [ "$m14_parses" -eq 1 ]; then
  pass "M14: control keeps the api-key out of curl's argv ($m14_ctl occurrences); with the header spelled back onto the command line it appears in the process table ($m14_mut) — and the probe succeeds either way"
else
  fail_ "M14" "control_argv_hits=$m14_ctl (want 0) mutant_argv_hits=$m14_mut (want >0) sites=$m14_sites changed=$m14_changed parses=$m14_parses"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
