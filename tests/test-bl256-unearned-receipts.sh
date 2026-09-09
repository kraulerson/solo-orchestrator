#!/usr/bin/env bash
# tests/test-bl256-unearned-receipts.sh
#
# `## BL-256:` — TWO GATES HANDED OUT RECEIPTS THEY DID NOT EARN.
#
#   (a) scripts/run-phase3-validation.sh::_p3_scan_semgrep counted findings as
#       `jq '(.results | length) // 0' … || echo 0`, then sanitised anything
#       non-numeric to 0, and 0 meant PASS. A renamed key, an archive that is
#       not JSON, or a host with no jq: every one read as "0 findings — PASS",
#       a clean bill of health for a scan nobody could read, in the gate that
#       decides production release. `_p3_scan_snyk`, one function below, carried
#       the identical count (`.vulnerabilities`, `// 0`, `|| echo 0`, sanitise to
#       0) — the reviewer's R-3 — and is covered by section N with its own shim.
#   (b) scripts/process-checklist.sh's uat_session:results_received solo escape
#       appended its attestation with `jq … > tmp && mv` and then printed
#       "attested and RECORDED" unconditionally — a read-only .claude/ left no
#       record while the operator was told there was one. The general step
#       write at the end of complete_step had the same shape (review round 2,
#       R2-3): "Step … completed" at rc 0 with the state file untouched.
#
# Both drive the REAL scripts on fixtures. (a) uses a PATH shim `semgrep` that
# writes a canned archive to --output, on a PATH mirrored from the host MINUS
# the tools that would otherwise reach the network or the host (real semgrep,
# snyk, docker, go-licenses) — CLAUDE.md's rule: mirror the real PATH minus the
# excluded tools, and ASSERT the exclusion before trusting a measurement.
# (b) runs the checklist against a process-state fixture at the
# results_received step, once writable and once read-only. Mutants on a MIRROR.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
P3="$REPO_ROOT/scripts/run-phase3-validation.sh"
PC="$REPO_ROOT/scripts/process-checklist.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
# read-only fixture dirs must be writable again before the trap removes them
trap 'chmod -R u+w "$TOPTMP" 2>/dev/null; rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }
_num() { case "$1" in ''|null|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac }
_sites() { local n; n=$(grep -c "$2\$" "$1" 2>/dev/null); _num "$n"; }
_changed_lines() { local n; n=$(diff "$1" "$2" 2>/dev/null | grep -c '^[<>]'); case "$n" in ''|*[!0-9]*) n=0 ;; esac; printf '%s\n' "$n"; }

for f in "$P3" "$PC"; do
  [ -f "$f" ] || { echo "  [FAIL] setup — $f not found"; echo ""; echo "Results: 0 passed, 1 failed"; exit 1; }
done
command -v jq >/dev/null 2>&1 || { echo "  [FAIL] setup — jq is required by this suite"; echo ""; echo "Results: 0 passed, 1 failed"; exit 1; }

# ── PATH mirrors ─────────────────────────────────────────────────────────────
# mk_cleanbin <dir> <excluded-basenames…> → a dir of symlinks to every
# executable on the current PATH except the named ones; asserts the exclusion.
mk_cleanbin() {
  local d="$1"; shift
  local ex=" $* " p f b
  mkdir -p "$d" || return 1
  local IFS=:
  for p in $PATH; do
    [ -d "$p" ] || continue
    for f in "$p"/*; do
      [ -x "$f" ] && [ ! -d "$f" ] || continue
      b="$(basename "$f")"
      case "$ex" in *" $b "*) continue ;; esac
      [ -e "$d/$b" ] || ln -s "$f" "$d/$b" 2>/dev/null
    done
  done
  unset IFS
  for b in "$@"; do
    if PATH="$d" command -v "$b" >/dev/null 2>&1; then
      echo "  [FAIL] setup — '$b' is still reachable on the isolated PATH" ; return 1
    fi
  done
  return 0
}

# mk_semgrep_shim <dir> — a `semgrep` that copies $P3_FAKE_ARCHIVE to --output
mk_semgrep_shim() {
  local d="$1"
  mkdir -p "$d" || return 1
  cat > "$d/semgrep" <<'SHIM'
#!/usr/bin/env bash
# test shim: stands in for semgrep; writes the canned archive to --output
out=""
while [ $# -gt 0 ]; do
  case "$1" in --output) out="$2"; shift 2 ;; *) shift ;; esac
done
[ -n "$out" ] || exit 2
cp "${P3_FAKE_ARCHIVE:?}" "$out"
exit "${P3_FAKE_RC:-0}"
SHIM
  chmod +x "$d/semgrep"
  [ -x "$d/semgrep" ]
}

# mk_snyk_shim <dir> — a `snyk` that answers `config get api` with a token and
# `test --json` with $P3_FAKE_ARCHIVE on stdout (the driver redirects stdout
# into its archive); anything else is an execution error
mk_snyk_shim() {
  local d="$1"
  mkdir -p "$d" || return 1
  cat > "$d/snyk" <<'SHIM'
#!/usr/bin/env bash
# test shim: stands in for snyk
case "$*" in
  "config get api") printf 'shim-token\n'; exit 0 ;;
  "test --json")    cat "${P3_FAKE_ARCHIVE:?}"; exit "${P3_FAKE_RC:-0}" ;;
  *)                exit 2 ;;
esac
SHIM
  chmod +x "$d/snyk"
  [ -x "$d/snyk" ]
}

# mk_p3_fixture <dir> — a minimal project the driver can scan
mk_p3_fixture() {
  local d="$1"
  mkdir -p "$d/.claude" "$d/src" "$d/docs" || return 1
  printf 'console.log(1)\n' > "$d/src/a.js"
  printf '{"project":"p","current_phase":3,"track":"standard","deployment":"personal","poc_mode":null,"gates":{}}\n' > "$d/.claude/phase-state.json"
  return 0
}

# run_p3 <fixture> <archive-json> <PATH> [driver] → sets P3_OUT (stdout+stderr), P3_RC, P3_SUMMARY
run_p3() {
  local fx="$1" archive="$2" path="$3" driver="${4:-$P3}" res
  res="$fx/results"; mkdir -p "$res"
  P3_OUT="$( cd "$fx" && env PATH="$path" P3_FAKE_ARCHIVE="$archive" bash "$driver" --results-dir "$res" --state "$fx/.claude/phase-state.json" 2>&1 )"; P3_RC=$?
  P3_SUMMARY="$(ls -t "$res"/summary-*.md 2>/dev/null | head -1)"
  return 0
}
# semgrep_line → the summary's line for the semgrep scanner (label from _p3_label)
semgrep_line() { grep -m1 'Full-tree Semgrep SAST\|semgrep-full-tree' "${P3_SUMMARY:-/dev/null}" 2>/dev/null; }
# snyk_line → the summary's line for the snyk scanner (label from _p3_label)
snyk_line() { grep -m1 '^| snyk |\|Snyk dependency scan' "${P3_SUMMARY:-/dev/null}" 2>/dev/null; }

echo "=== S — (a) the semgrep count is a receipt only when a .results array was counted ==="

CLEAN="$(newtmp)/cleanbin"
SHIMD="$(newtmp)/shim"
if ! mk_cleanbin "$CLEAN" semgrep snyk docker go-licenses; then
  fail_ "S setup" "could not build the isolated PATH"
elif ! mk_semgrep_shim "$SHIMD"; then
  fail_ "S setup" "could not build the semgrep shim"
else
  PATH_S="$SHIMD:$CLEAN"
  [ "$(PATH="$PATH_S" command -v semgrep)" = "$SHIMD/semgrep" ] \
    && pass "S0 — on the isolated PATH, semgrep resolves to the shim and not the host's" \
    || fail_ "S0" "semgrep resolves to $(PATH="$PATH_S" command -v semgrep)"

  ARCH="$(newtmp)"
  printf '{"results":[],"errors":[]}\n' > "$ARCH/empty.json"
  printf '{"results":[{"check_id":"a"},{"check_id":"b"}],"errors":[]}\n' > "$ARCH/two.json"
  printf '{"findings":[],"errors":[]}\n' > "$ARCH/renamed.json"
  printf 'this is not json\n' > "$ARCH/garbage.json"

  # S1 — a real empty result is a PASS
  F1="$(newtmp)"; mk_p3_fixture "$F1"; run_p3 "$F1" "$ARCH/empty.json" "$PATH_S"
  l="$(semgrep_line)"
  printf '%s' "$l" | grep -q "PASS" && printf '%s' "$l" | grep -q "0 findings" \
    && pass "S1 — an archive with an empty .results array is PASS, 0 findings" \
    || fail_ "S1" "summary line: ${l:-<none>} (rc=$P3_RC, summary=$P3_SUMMARY)"

  # S2 — two findings is a FAIL that counts them
  F2="$(newtmp)"; mk_p3_fixture "$F2"; run_p3 "$F2" "$ARCH/two.json" "$PATH_S"
  l="$(semgrep_line)"
  printf '%s' "$l" | grep -q "FAIL" && printf '%s' "$l" | grep -q "2 semgrep finding" \
    && pass "S2 — an archive with two results is FAIL, '2 semgrep finding(s)'" \
    || fail_ "S2" "summary line: ${l:-<none>}"

  # S3 — a renamed key must NOT read as 0 findings
  F3="$(newtmp)"; mk_p3_fixture "$F3"; run_p3 "$F3" "$ARCH/renamed.json" "$PATH_S"
  l="$(semgrep_line)"
  if printf '%s' "$l" | grep -q "PASS"; then
    fail_ "S3" "an archive with NO .results array read as PASS — an unearned receipt: ${l}"
  elif printf '%s' "$l" | grep -q "FAIL" && printf '%s' "$l" | grep -q "NOTHING WAS COUNTED"; then
    pass "S3 — an archive with no .results array is FAIL and says NOTHING WAS COUNTED"
  else
    fail_ "S3" "summary line: ${l:-<none>}"
  fi

  # S4 — an unparseable archive must NOT read as 0 findings
  F4="$(newtmp)"; mk_p3_fixture "$F4"; run_p3 "$F4" "$ARCH/garbage.json" "$PATH_S"
  l="$(semgrep_line)"
  if printf '%s' "$l" | grep -q "PASS"; then
    fail_ "S4" "an unparseable archive read as PASS — an unearned receipt: ${l}"
  elif printf '%s' "$l" | grep -q "FAIL" && printf '%s' "$l" | grep -q "NOTHING WAS COUNTED"; then
    pass "S4 — an unparseable archive is FAIL and says NOTHING WAS COUNTED"
  else
    fail_ "S4" "summary line: ${l:-<none>}"
  fi

  # S6/S7 — `.results` PRESENT but NOT an array. A first cut had no such case,
  # and a reviewer mutant that weakened the type check to a presence check
  # (`has("results") and .results != null`) survived 14/0 while re-opening
  # the defect: `{"results":{}}` counted 0 → PASS, and `{"results":"abcdefgh"}`
  # counted the STRING'S LENGTH as eight findings.
  printf '{"results":{},"errors":[]}\n' > "$ARCH/object.json"
  printf '{"results":"abcdefgh","errors":[]}\n' > "$ARCH/string.json"
  F6="$(newtmp)"; mk_p3_fixture "$F6"; run_p3 "$F6" "$ARCH/object.json" "$PATH_S"
  l="$(semgrep_line)"
  if printf '%s' "$l" | grep -q "PASS"; then
    fail_ "S6" "a .results that is an OBJECT read as PASS — an unearned receipt: ${l}"
  elif printf '%s' "$l" | grep -q "FAIL" && printf '%s' "$l" | grep -q "NOTHING WAS COUNTED"; then
    pass "S6 — a .results that is an object (not an array) is FAIL and says NOTHING WAS COUNTED"
  else
    fail_ "S6" "summary line: ${l:-<none>}"
  fi
  F7="$(newtmp)"; mk_p3_fixture "$F7"; run_p3 "$F7" "$ARCH/string.json" "$PATH_S"
  l="$(semgrep_line)"
  if printf '%s' "$l" | grep -qE "PASS|[0-9]+ semgrep finding"; then
    fail_ "S7" "a .results that is a STRING was counted or passed — ${l}"
  elif printf '%s' "$l" | grep -q "FAIL" && printf '%s' "$l" | grep -q "NOTHING WAS COUNTED"; then
    pass "S7 — a .results that is a string is FAIL and says NOTHING WAS COUNTED (never the string's length)"
  else
    fail_ "S7" "summary line: ${l:-<none>}"
  fi

  # S2b — ONE finding must be FAIL (the `-gt 0` boundary; a `-gt 1` mutant
  # survived review round 2 because only 0 and 2 were pinned)
  printf '{"results":[{"check_id":"only-one"}],"errors":[]}\n' > "$ARCH/one.json"
  F2b="$(newtmp)"; mk_p3_fixture "$F2b"; run_p3 "$F2b" "$ARCH/one.json" "$PATH_S"
  l="$(semgrep_line)"
  if printf '%s' "$l" | grep -q "FAIL" && printf '%s' "$l" | grep -q "1 semgrep finding"; then
    pass "S2b — an archive with ONE result is FAIL, '1 semgrep finding(s)' (the >0 boundary)"
  else
    fail_ "S2b" "summary line: ${l:-<none>}"
  fi

  # S8 — a MULTI-DOCUMENT archive (two JSON documents concatenated). jq emits
  # one count per document, so `findings` becomes "0\n0": the `*[!0-9]*`
  # sanitiser arm is the only thing between that and `[ "0\n0" -gt 0 ]`
  # erroring into the PASS branch (the driver is deliberately not set -e).
  # A reviewer mutant that dropped that arm survived 17/0; MP3 pins it.
  printf '{"results":[],"errors":[]}\n{"results":[],"errors":[]}\n' > "$ARCH/multidoc.json"
  F8="$(newtmp)"; mk_p3_fixture "$F8"; run_p3 "$F8" "$ARCH/multidoc.json" "$PATH_S"
  l="$(semgrep_line)"
  if printf '%s' "$l" | grep -q "PASS"; then
    fail_ "S8" "a two-document archive read as PASS — an unearned receipt: ${l}"
  elif printf '%s' "$l" | grep -q "FAIL" && printf '%s' "$l" | grep -q "NOTHING WAS COUNTED"; then
    pass "S8 — a multi-document archive is FAIL and says NOTHING WAS COUNTED"
  else
    fail_ "S8" "summary line: ${l:-<none>}"
  fi

  # S9 — a TOP-LEVEL ARRAY archive (no object to carry .results) must not count
  printf '[]\n' > "$ARCH/toparray.json"
  F9="$(newtmp)"; mk_p3_fixture "$F9"; run_p3 "$F9" "$ARCH/toparray.json" "$PATH_S"
  l="$(semgrep_line)"
  if printf '%s' "$l" | grep -q "PASS"; then
    fail_ "S9" "a top-level array archive read as PASS — an unearned receipt: ${l}"
  elif printf '%s' "$l" | grep -q "FAIL" && printf '%s' "$l" | grep -q "NOTHING WAS COUNTED"; then
    pass "S9 — a top-level ARRAY archive is FAIL and says NOTHING WAS COUNTED"
  else
    fail_ "S9" "summary line: ${l:-<none>}"
  fi

  # S5 — no jq at all must NOT read as 0 findings
  CLEAN5="$(newtmp)/cleanbin"
  if ! mk_cleanbin "$CLEAN5" semgrep snyk docker go-licenses jq; then
    fail_ "S5 setup" "could not build the jq-less PATH"
  else
    F5="$(newtmp)"; mk_p3_fixture "$F5"; run_p3 "$F5" "$ARCH/empty.json" "$SHIMD:$CLEAN5"
    l="$(semgrep_line)"
    if printf '%s' "$l" | grep -q "PASS"; then
      fail_ "S5" "with no jq on PATH the scan read as PASS — an unearned receipt: ${l}"
    elif printf '%s' "$l" | grep -q "FAIL" && printf '%s' "$l" | grep -qi "jq is not on PATH"; then
      pass "S5 — with no jq the scan is FAIL and says the archive could not be counted"
    else
      fail_ "S5" "summary line: ${l:-<none>}"
    fi
  fi
fi

echo "=== N — (a) again for snyk: the count is a receipt only when a .vulnerabilities array was counted ==="
# The reviewer's R-3: `_p3_scan_snyk` carried the identical count one function
# below the semgrep arm. Same drive: a `snyk` shim on the isolated PATH that
# answers `config get api` with a token and `test --json` with the canned
# report on stdout. The semgrep shim stays on the PATH and reads the same
# report (its line says NOTHING WAS COUNTED — only the snyk line is read here).
SNYKD="$(newtmp)/snykshim"
if [ -z "${PATH_S:-}" ] || [ -z "${ARCH:-}" ]; then
  fail_ "N setup" "no isolated PATH from section S"
elif ! mk_snyk_shim "$SNYKD"; then
  fail_ "N setup" "could not build the snyk shim"
else
  PATH_N="$SNYKD:$PATH_S"
  [ "$(PATH="$PATH_N" command -v snyk)" = "$SNYKD/snyk" ] \
    && pass "N0 — on the isolated PATH, snyk resolves to the shim and not the host's" \
    || fail_ "N0" "snyk resolves to $(PATH="$PATH_N" command -v snyk)"

  printf '{"ok":true,"vulnerabilities":[],"dependencyCount":3}\n' > "$ARCH/snyk-empty.json"
  printf '{"ok":false,"vulnerabilities":[{"id":"a"},{"id":"b"}],"dependencyCount":3}\n' > "$ARCH/snyk-two.json"
  printf '{"ok":true,"issues":[],"dependencyCount":3}\n' > "$ARCH/snyk-renamed.json"
  printf '{"ok":true,"vulnerabilities":{},"dependencyCount":3}\n' > "$ARCH/snyk-object.json"

  # N1 — a real empty array is a PASS (the honest-outcome control)
  FN1="$(newtmp)"; mk_p3_fixture "$FN1"; run_p3 "$FN1" "$ARCH/snyk-empty.json" "$PATH_N"
  l="$(snyk_line)"
  if printf '%s' "$l" | grep -q "PASS" && printf '%s' "$l" | grep -q "0 vulnerabilities"; then
    pass "N1 — a report with an empty .vulnerabilities array is PASS, 0 vulnerabilities"
  else
    fail_ "N1" "summary line: ${l:-<none>}"
  fi

  # N2 — two vulnerabilities is FAIL with the count
  FN2="$(newtmp)"; mk_p3_fixture "$FN2"; run_p3 "$FN2" "$ARCH/snyk-two.json" "$PATH_N"
  l="$(snyk_line)"
  if printf '%s' "$l" | grep -q "FAIL" && printf '%s' "$l" | grep -q "2 snyk vulnerability finding"; then
    pass "N2 — a report with two vulnerabilities is FAIL, '2 snyk vulnerability finding(s)'"
  else
    fail_ "N2" "summary line: ${l:-<none>}"
  fi

  # N3 — a renamed key (no .vulnerabilities) must NOT read as 0
  FN3="$(newtmp)"; mk_p3_fixture "$FN3"; run_p3 "$FN3" "$ARCH/snyk-renamed.json" "$PATH_N"
  l="$(snyk_line)"
  if printf '%s' "$l" | grep -q "PASS"; then
    fail_ "N3" "a report with no .vulnerabilities key read as PASS — an unearned receipt: ${l}"
  elif printf '%s' "$l" | grep -q "FAIL" && printf '%s' "$l" | grep -q "NOTHING WAS COUNTED"; then
    pass "N3 — a report with no .vulnerabilities array is FAIL and says NOTHING WAS COUNTED"
  else
    fail_ "N3" "summary line: ${l:-<none>}"
  fi

  # N4 — a .vulnerabilities that is present but an OBJECT must not count as 0
  FN4="$(newtmp)"; mk_p3_fixture "$FN4"; run_p3 "$FN4" "$ARCH/snyk-object.json" "$PATH_N"
  l="$(snyk_line)"
  if printf '%s' "$l" | grep -q "PASS"; then
    fail_ "N4" "a .vulnerabilities object read as PASS — an unearned receipt: ${l}"
  elif printf '%s' "$l" | grep -q "FAIL" && printf '%s' "$l" | grep -q "NOTHING WAS COUNTED"; then
    pass "N4 — a .vulnerabilities that is an object (not an array) is FAIL and says NOTHING WAS COUNTED"
  else
    fail_ "N4" "summary line: ${l:-<none>}"
  fi

  # N5 — a TOP-LEVEL ARRAY report (the `--all-projects` shape this arm never
  # asks for) must not be counted as clean. Review round 2's surviving mutant
  # (x10) added an `if type == "array"` arm that summed `.[]?.vulnerabilities[]?`
  # and read `[{"vulnerabilities":[]}]` as PASS — no case fed a top-level array.
  printf '[{"ok":true,"vulnerabilities":[],"dependencyCount":3}]\n' > "$ARCH/snyk-toparray.json"
  FN5="$(newtmp)"; mk_p3_fixture "$FN5"; run_p3 "$FN5" "$ARCH/snyk-toparray.json" "$PATH_N"
  l="$(snyk_line)"
  if printf '%s' "$l" | grep -q "PASS"; then
    fail_ "N5" "a top-level array report read as PASS — an unearned receipt: ${l}"
  elif printf '%s' "$l" | grep -q "FAIL" && printf '%s' "$l" | grep -q "NOTHING WAS COUNTED"; then
    pass "N5 — a top-level ARRAY report (the --all-projects shape) is FAIL and says NOTHING WAS COUNTED"
  else
    fail_ "N5" "summary line: ${l:-<none>}"
  fi

  # N6 — no jq: the snyk row must say so (not "schema drift"), mirroring S5
  if [ -z "${CLEAN5:-}" ]; then
    fail_ "N6 setup" "no jq-less PATH from S5"
  else
    FN6="$(newtmp)"; mk_p3_fixture "$FN6"; run_p3 "$FN6" "$ARCH/snyk-empty.json" "$SNYKD:$SHIMD:$CLEAN5"
    l="$(snyk_line)"
    if printf '%s' "$l" | grep -q "PASS"; then
      fail_ "N6" "with no jq on PATH the snyk scan read as PASS — an unearned receipt: ${l}"
    elif printf '%s' "$l" | grep -q "FAIL" && printf '%s' "$l" | grep -qi "jq is not on PATH"; then
      pass "N6 — with no jq the snyk scan is FAIL and says jq is not on PATH (not schema drift)"
    else
      fail_ "N6" "summary line: ${l:-<none>}"
    fi
  fi
fi

echo "=== U — (b) the UAT solo attestation is announced only when it was recorded ==="

# mk_uat_fixture <dir> — process-state at the results_received step, Light track
mk_uat_fixture() {
  local d="$1"
  mkdir -p "$d/.claude" "$d/tests/uat/sessions/s1/submissions" || return 1
  cat > "$d/.claude/process-state.json" <<'STATE'
{
  "build_loop": {"feature": null, "step": 0, "steps_completed": [], "started_at": null},
  "uat_session": {"session_id": "s1", "step": 3, "steps_completed": ["agents_dispatched","template_generated","orchestrator_notified"], "started_at": "2026-09-08T00:00:00Z"},
  "phase1_architecture": {"steps_completed": [], "started_at": null},
  "phase3_validation": {"steps_completed": [], "started_at": null}
}
STATE
  printf '{"project":"p","current_phase":2,"track":"light","deployment":"personal","poc_mode":null,"gates":{}}\n' > "$d/.claude/phase-state.json"
  return 0
}
# run_uat <fixture> [checklist] [PATH] → UAT_OUT, UAT_RC (the solo-attested path)
run_uat() {
  local fx="$1" pc="${2:-$PC}" path="${3:-$PATH}"
  UAT_OUT="$( cd "$fx" && env PATH="$path" SOLO_UAT_SOLO_ATTESTED=1 SOLO_UAT_REASON="bl256-test" bash "$pc" --complete-step uat_session:results_received 2>&1 )"; UAT_RC=$?
  return 0
}
# run_step <fixture> [checklist] → UAT_OUT, UAT_RC (the NON-solo path: a real
# submission file is present, so only the general step write is exercised)
run_step() {
  local fx="$1" pc="${2:-$PC}" path="${3:-$PATH}"
  UAT_OUT="$( cd "$fx" && env PATH="$path" bash "$pc" --complete-step uat_session:results_received 2>&1 )"; UAT_RC=$?
  return 0
}
# mk_mv_shim <dir> — an `mv` that refuses only when its LAST argument ends in
# process-state.json (so jq succeeds and the rename fails — review round 2 showed
# this is a portable fixture, not a "same-dir permission split"); everything
# else is delegated to /bin/mv
mk_mv_shim() {
  local d="$1"
  mkdir -p "$d" || return 1
  cat > "$d/mv" <<'SHIM'
#!/bin/sh
# test shim: refuse to replace process-state.json; delegate everything else
for last; do :; done
case "$last" in *process-state.json) echo "mv: simulated failure" >&2; exit 1 ;; esac
exec /bin/mv "$@"
SHIM
  chmod +x "$d/mv"
  [ -x "$d/mv" ]
}

U1="$(newtmp)"; mk_uat_fixture "$U1"; run_uat "$U1"
if printf '%s' "$UAT_OUT" | grep -q "RECORDED" && jq -e '.uat_session.solo_attestations[0].reason == "bl256-test"' "$U1/.claude/process-state.json" >/dev/null 2>&1; then
  pass "U1 — with a writable state file the attestation is recorded AND announced (rc=$UAT_RC)"
else
  fail_ "U1" "rc=$UAT_RC; recorded=$(jq -c '.uat_session.solo_attestations' "$U1/.claude/process-state.json" 2>/dev/null); out: $(printf '%s' "$UAT_OUT" | grep -i 'results_received' | head -2 | tr '\n' ' ')"
fi

# U1b — the healthy NON-solo path: the step write lands and is announced (the
# control for U4/U4c — without it a guard that refuses EVERY completion would
# pass this suite; review round 3, R3-3)
U1b="$(newtmp)"; mk_uat_fixture "$U1b"
printf 'tester A results\n' > "$U1b/tests/uat/sessions/s1/submissions/tester-a.md"
run_step "$U1b"
if [ "$UAT_RC" -eq 0 ] && printf '%s' "$UAT_OUT" | grep -q "Step 'results_received' completed" \
   && [ "$(jq -r '.uat_session.steps_completed | length' "$U1b/.claude/process-state.json" 2>/dev/null)" = "4" ]; then
  pass "U1b — on the healthy non-solo path the step is recorded (4 steps) AND announced (rc=0)"
else
  fail_ "U1b" "rc=$UAT_RC steps=$(jq -c '.uat_session.steps_completed' "$U1b/.claude/process-state.json" 2>/dev/null); out: $(printf '%s' "$UAT_OUT" | grep -i 'results_received' | head -2 | tr '\n' ' ')"
fi

U2="$(newtmp)"; mk_uat_fixture "$U2"
before="$(cat "$U2/.claude/process-state.json")"
chmod 555 "$U2/.claude"
if [ -w "$U2/.claude" ]; then
  fail_ "U2 setup" ".claude stayed writable after chmod 555 (running as root?) — the read-only case cannot be measured"
else
  run_uat "$U2"
  chmod 755 "$U2/.claude"
  if printf '%s' "$UAT_OUT" | grep -q "RECORDED"; then
    fail_ "U2" "the attestation was announced as RECORDED with a read-only .claude/ — an unearned receipt (rc=$UAT_RC)"
  elif [ "$UAT_RC" -ne 0 ] && printf '%s' "$UAT_OUT" | grep -q "REFUSED"; then
    pass "U2 — with a read-only .claude/ the attestation is REFUSED (rc=$UAT_RC), never announced"
  else
    fail_ "U2" "rc=$UAT_RC out: $(printf '%s' "$UAT_OUT" | grep -i 'results_received\|REFUSED' | head -2 | tr '\n' ' ')"
  fi
  [ "$(cat "$U2/.claude/process-state.json")" = "$before" ] \
    && pass "U2b — and the state file is byte-identical to before" \
    || fail_ "U2b" "the state file changed under a refused attestation"
fi

# U2c — a STALE .tmp (crash mid-write) inside a .claude/ that is now read-only:
# jq's redirect into the writable file succeeds, mv fails, and the rm -f of
# the .tmp fails too — under set -e that rm used to exit the script BEFORE
# the refusal was printed (review round 3, R3-2). rc was honest; the text
# was missing.
U2c="$(newtmp)"; mk_uat_fixture "$U2c"
printf '{"stale":true}\n' > "$U2c/.claude/process-state.json.tmp"
before="$(cat "$U2c/.claude/process-state.json")"
chmod 555 "$U2c/.claude"
if [ -w "$U2c/.claude" ]; then
  fail_ "U2c setup" ".claude stayed writable after chmod 555 (running as root?)"
else
  run_uat "$U2c"
  chmod 755 "$U2c/.claude"
  if printf '%s' "$UAT_OUT" | grep -q "RECORDED"; then
    fail_ "U2c" "announced as RECORDED with a stale .tmp in a read-only .claude/ (rc=$UAT_RC)"
  elif [ "$UAT_RC" -ne 0 ] && printf '%s' "$UAT_OUT" | grep -q "REFUSED" && [ "$(cat "$U2c/.claude/process-state.json")" = "$before" ]; then
    pass "U2c — with a stale .tmp in a read-only .claude/ the refusal is still PRINTED (rc=$UAT_RC), state unchanged"
  else
    fail_ "U2c" "rc=$UAT_RC refused=$(printf '%s' "$UAT_OUT" | grep -c REFUSED) out: $(printf '%s' "$UAT_OUT" | tail -2 | tr '\n' ' ')"
  fi
fi

# U2d — the attestation write's jq half on a WRITABLE dir (review round 4,
# R4-1): `.solo_attestations` is a string, so `(… // []) + [{…}]` is a jq
# error; a guard that tolerated it (`; mv`) would rename an EMPTY .tmp over
# the state file and print RECORDED. rc≠0, REFUSED, byte-identical, no .tmp.
U2d="$(newtmp)"; mk_uat_fixture "$U2d"
jq '.uat_session.solo_attestations = "corrupt"' "$U2d/.claude/process-state.json" > "$U2d/.claude/ps.new" && mv "$U2d/.claude/ps.new" "$U2d/.claude/process-state.json"
before="$(cat "$U2d/.claude/process-state.json")"
run_uat "$U2d"
if printf '%s' "$UAT_OUT" | grep -q "RECORDED"; then
  fail_ "U2d" "announced as RECORDED after jq failed on a corrupt solo_attestations (rc=$UAT_RC, state bytes=$(wc -c < "$U2d/.claude/process-state.json" | tr -d ' '))"
elif [ "$UAT_RC" -ne 0 ] && printf '%s' "$UAT_OUT" | grep -q "REFUSED" \
     && [ "$(cat "$U2d/.claude/process-state.json")" = "$before" ] && [ ! -e "$U2d/.claude/process-state.json.tmp" ]; then
  pass "U2d — with jq failing on a writable dir the attestation is REFUSED (rc=$UAT_RC), state byte-identical, no .tmp"
else
  fail_ "U2d" "rc=$UAT_RC refused=$(printf '%s' "$UAT_OUT" | grep -c REFUSED) tmp=$([ -e "$U2d/.claude/process-state.json.tmp" ] && echo yes || echo no) out: $(printf '%s' "$UAT_OUT" | tail -2 | tr '\n' ' ')"
fi

# U3 — jq succeeds, the rename fails: REFUSED, and the .tmp is not left behind
MVD="$(newtmp)/mvshim"
if ! mk_mv_shim "$MVD"; then
  fail_ "U3 setup" "could not build the mv shim"
else
  U3="$(newtmp)"; mk_uat_fixture "$U3"
  before="$(cat "$U3/.claude/process-state.json")"
  run_uat "$U3" "$PC" "$MVD:$PATH"
  if printf '%s' "$UAT_OUT" | grep -q "RECORDED"; then
    fail_ "U3" "the attestation was announced as RECORDED after mv failed — an unearned receipt (rc=$UAT_RC)"
  elif [ "$UAT_RC" -ne 0 ] && printf '%s' "$UAT_OUT" | grep -q "REFUSED"; then
    pass "U3 — with jq succeeding and the rename failing the attestation is REFUSED (rc=$UAT_RC)"
  else
    fail_ "U3" "rc=$UAT_RC out: $(printf '%s' "$UAT_OUT" | grep -i 'results_received\|REFUSED' | head -2 | tr '\n' ' ')"
  fi
  if [ ! -e "$U3/.claude/process-state.json.tmp" ] && [ "$(cat "$U3/.claude/process-state.json")" = "$before" ]; then
    pass "U3b — no .tmp is left behind and the state file is byte-identical"
  else
    fail_ "U3b" "tmp-left-behind=$([ -e "$U3/.claude/process-state.json.tmp" ] && echo yes || echo no); state-unchanged=$([ "$(cat "$U3/.claude/process-state.json")" = "$before" ] && echo yes || echo no)"
  fi
fi

# U4 — the NON-solo path (a real submission file, no attestation): the general
# step write at the end of complete_step must not announce "completed" when the
# state file could not be written (review round 2, R2-3)
U4="$(newtmp)"; mk_uat_fixture "$U4"
printf 'tester A results\n' > "$U4/tests/uat/sessions/s1/submissions/tester-a.md"
before="$(cat "$U4/.claude/process-state.json")"
chmod 555 "$U4/.claude"
if [ -w "$U4/.claude" ]; then
  fail_ "U4 setup" ".claude stayed writable after chmod 555 (running as root?)"
else
  run_step "$U4"
  chmod 755 "$U4/.claude"
  if printf '%s' "$UAT_OUT" | grep -q "Step 'results_received' completed"; then
    fail_ "U4" "the step was announced as completed with a read-only .claude/ — an unearned receipt (rc=$UAT_RC)"
  elif [ "$UAT_RC" -ne 0 ] && printf '%s' "$UAT_OUT" | grep -q "NOT recorded"; then
    pass "U4 — with a read-only .claude/ the step completion is refused (rc=$UAT_RC), never announced"
  else
    fail_ "U4" "rc=$UAT_RC out: $(printf '%s' "$UAT_OUT" | grep -i 'results_received\|recorded' | head -2 | tr '\n' ' ')"
  fi
  [ "$(cat "$U4/.claude/process-state.json")" = "$before" ] \
    && pass "U4b — and the state file is byte-identical to before" \
    || fail_ "U4b" "the state file changed under a refused step completion"
fi

# U4c — the step write's rename half: jq succeeds, the rename fails (review
# round 3, R3-1: a guard that covered only jq and tolerated mv announced
# "completed" at rc 0 and survived 40/0). U4 fails BOTH halves at once — the
# shell cannot even create the .tmp in a read-only dir — so it pins neither
# half on its own; U4c is the rename-only case and U4e the jq-only case.
if [ -z "${MVD:-}" ]; then
  fail_ "U4c setup" "no mv shim from U3"
else
  U4c="$(newtmp)"; mk_uat_fixture "$U4c"
  printf 'tester A results\n' > "$U4c/tests/uat/sessions/s1/submissions/tester-a.md"
  before="$(cat "$U4c/.claude/process-state.json")"
  run_step "$U4c" "$PC" "$MVD:$PATH"
  if printf '%s' "$UAT_OUT" | grep -q "Step 'results_received' completed"; then
    fail_ "U4c" "the step was announced as completed after mv failed — an unearned receipt (rc=$UAT_RC)"
  elif [ "$UAT_RC" -ne 0 ] && printf '%s' "$UAT_OUT" | grep -q "NOT recorded" \
       && [ "$(cat "$U4c/.claude/process-state.json")" = "$before" ] && [ ! -e "$U4c/.claude/process-state.json.tmp" ]; then
    pass "U4c — with jq succeeding and the rename failing the step is refused (rc=$UAT_RC), state unchanged, no .tmp"
  else
    fail_ "U4c" "rc=$UAT_RC tmp=$([ -e "$U4c/.claude/process-state.json.tmp" ] && echo yes || echo no) out: $(printf '%s' "$UAT_OUT" | grep -i 'recorded\|completed' | head -2 | tr '\n' ' ')"
  fi
fi

# U4d — the stale-.tmp + read-only case on the STEP arm (R3-2, step half)
U4d="$(newtmp)"; mk_uat_fixture "$U4d"
printf 'tester A results\n' > "$U4d/tests/uat/sessions/s1/submissions/tester-a.md"
printf '{"stale":true}\n' > "$U4d/.claude/process-state.json.tmp"
before="$(cat "$U4d/.claude/process-state.json")"
chmod 555 "$U4d/.claude"
if [ -w "$U4d/.claude" ]; then
  fail_ "U4d setup" ".claude stayed writable after chmod 555 (running as root?)"
else
  run_step "$U4d"
  chmod 755 "$U4d/.claude"
  if printf '%s' "$UAT_OUT" | grep -q "Step 'results_received' completed"; then
    fail_ "U4d" "announced as completed with a stale .tmp in a read-only .claude/ (rc=$UAT_RC)"
  elif [ "$UAT_RC" -ne 0 ] && printf '%s' "$UAT_OUT" | grep -q "NOT recorded" && [ "$(cat "$U4d/.claude/process-state.json")" = "$before" ]; then
    pass "U4d — with a stale .tmp in a read-only .claude/ the step refusal is still PRINTED (rc=$UAT_RC), state unchanged"
  else
    fail_ "U4d" "rc=$UAT_RC notrec=$(printf '%s' "$UAT_OUT" | grep -c 'NOT recorded') out: $(printf '%s' "$UAT_OUT" | tail -2 | tr '\n' ' ')"
  fi
fi

# U4e — the step write's jq half on a WRITABLE dir (review round 4, R4-1):
# `steps_completed` is a STRING carrying the prior names — the prior-step
# check is jq `index($step)`, a substring search on a string, so it passes,
# and the write's `+= [$step]` is the first jq to fail. A guard that
# tolerated it (`> tmp || true && mv`) would rename an EMPTY .tmp over the
# state file and print "completed": that mutant survived 45/0.
U4e="$(newtmp)"; mk_uat_fixture "$U4e"
printf 'tester A results\n' > "$U4e/tests/uat/sessions/s1/submissions/tester-a.md"
jq '.uat_session.steps_completed = "agents_dispatched template_generated orchestrator_notified"' "$U4e/.claude/process-state.json" > "$U4e/.claude/ps.new" && mv "$U4e/.claude/ps.new" "$U4e/.claude/process-state.json"
before="$(cat "$U4e/.claude/process-state.json")"
run_step "$U4e"
if printf '%s' "$UAT_OUT" | grep -q "Step 'results_received' completed"; then
  fail_ "U4e" "announced as completed after jq failed on a corrupt steps_completed (rc=$UAT_RC, state bytes=$(wc -c < "$U4e/.claude/process-state.json" | tr -d ' '))"
elif [ "$UAT_RC" -ne 0 ] && printf '%s' "$UAT_OUT" | grep -q "NOT recorded" \
     && [ "$(cat "$U4e/.claude/process-state.json")" = "$before" ] && [ ! -e "$U4e/.claude/process-state.json.tmp" ]; then
  pass "U4e — with jq failing on a writable dir the step is refused (rc=$UAT_RC), state byte-identical, no .tmp"
else
  fail_ "U4e" "rc=$UAT_RC notrec=$(printf '%s' "$UAT_OUT" | grep -c 'NOT recorded') tmp=$([ -e "$U4e/.claude/process-state.json.tmp" ] && echo yes || echo no) out: $(printf '%s' "$UAT_OUT" | grep -i 'recorded\|completed\|jq' | head -2 | tr '\n' ' ')"
fi

echo "=== M — mutation proofs on a mirror ==="

M_P3="# BL-256-P3-COUNT-RECEIPT"
M_PN="# BL-256-P3-SNYK-COUNT-RECEIPT"
M_UR="# BL-256-UAT-ATTEST-RECEIPT"
M_UF="# BL-256-UAT-ATTEST-REFUSE"
M_SR="# BL-256-STEP-RECEIPT"
M_SF="# BL-256-STEP-REFUSE"
for pair in "$P3|$M_P3" "$P3|$M_PN" "$PC|$M_UR" "$PC|$M_UF" "$PC|$M_SR" "$PC|$M_SF"; do
  f="${pair%%|*}"; m="${pair#*|}"
  n="$(_sites "$f" "$m")"
  [ "$n" = "1" ] \
    && pass "M0 — '$m' occurs exactly once at end-of-line in $(basename "$f")" \
    || fail_ "M0" "'$m' occurs $n times in $(basename "$f") (need exactly 1)"
done

mk_mirror() { local m="$1"; mkdir -p "$m" && cp -Rp "$REPO_ROOT/scripts" "$m/"; }

# MP1 — restore the old count (`// 0` + `|| echo 0`) on a mirror: S3's renamed
# key must read as PASS again.
MP1="$(newtmp)/fw"
if ! mk_mirror "$MP1"; then
  fail_ "MP1 setup" "could not mirror scripts/"
else
  tgt="$MP1/scripts/run-phase3-validation.sh"; before="$(mktemp)"; cp "$tgt" "$before"
  # `~` is the delimiter because the marker carries `#` and the replacement
  # carries `|` and `/` — CLAUDE.md's sed trap, hit on the first cut of this
  # very line (the mutation "did not apply cleanly" was sed refusing it).
  sed "s~^.*${M_P3}\$~  findings=\$(jq '(.results | length) // 0' \"\$archive\" 2>/dev/null || echo 0)   ${M_P3}~" "$before" > "$tgt"
  if [ "$(_changed_lines "$before" "$tgt")" -lt 2 ] || ! bash -n "$tgt" 2>/dev/null || ! grep -q "(.results | length) // 0" "$tgt"; then
    fail_ "MP1 setup" "the count mutation did not apply cleanly"
  elif [ -z "${PATH_S:-}" ]; then
    fail_ "MP1 setup" "no isolated PATH from section S"
  else
    FM="$(newtmp)"; mk_p3_fixture "$FM"; run_p3 "$FM" "$ARCH/renamed.json" "$PATH_S" "$tgt"
    l="$(semgrep_line)"
    printf '%s' "$l" | grep -q "PASS" \
      && pass "MP1 (MUTATION) — with the old count restored, a renamed key reads as PASS again: S3 is what stops it" \
      || fail_ "MP1 (MUTATION)" "restoring the old count changed nothing — S3 may be passing for another reason: ${l:-<none>}"
  fi
fi

# MP2 — weaken the type check to a PRESENCE check on a mirror (the exact
# mutant that survived a first cut of this suite): S6's object must read PASS
# and S7's string must be "counted" again.
MP2="$(newtmp)/fw"
if ! mk_mirror "$MP2"; then
  fail_ "MP2 setup" "could not mirror scripts/"
else
  tgt="$MP2/scripts/run-phase3-validation.sh"; before="$(mktemp)"; cp "$tgt" "$before"
  sed "s~^.*${M_P3}\$~  findings=\$(jq -e 'if has(\"results\") and .results != null then (.results | length) else error(\"x\") end' \"\$archive\" 2>/dev/null) || findings=\"\"   ${M_P3}~" "$before" > "$tgt"
  if [ "$(_changed_lines "$before" "$tgt")" -lt 2 ] || ! bash -n "$tgt" 2>/dev/null || ! grep -q 'has("results") and .results != null' "$tgt"; then
    fail_ "MP2 setup" "the presence-check mutation did not apply cleanly"
  elif [ -z "${PATH_S:-}" ]; then
    fail_ "MP2 setup" "no isolated PATH from section S"
  else
    FO="$(newtmp)"; mk_p3_fixture "$FO"; run_p3 "$FO" "$ARCH/object.json" "$PATH_S" "$tgt"
    lo="$(semgrep_line)"
    FS="$(newtmp)"; mk_p3_fixture "$FS"; run_p3 "$FS" "$ARCH/string.json" "$PATH_S" "$tgt"
    ls_="$(semgrep_line)"
    if printf '%s' "$lo" | grep -q "PASS" && printf '%s' "$ls_" | grep -q "8 semgrep finding"; then
      pass "MP2 (MUTATION) — with a presence check, an object reads PASS and a string counts its own length: S6/S7 are what stop it"
    else
      fail_ "MP2 (MUTATION)" "the presence-check mutant did not re-open the defect — object: ${lo:-<none>} string: ${ls_:-<none>}"
    fi
  fi
fi

# MP3 — drop the `*[!0-9]*` sanitiser alternative on a mirror: S8's
# two-document archive must read PASS again. The case line is the one after
# the marked jq line; it is located by its own literal, not by the marker.
MP3="$(newtmp)/fw"
if ! mk_mirror "$MP3"; then
  fail_ "MP3 setup" "could not mirror scripts/"
else
  tgt="$MP3/scripts/run-phase3-validation.sh"; before="$(mktemp)"; cp "$tgt" "$before"
  # only the semgrep arm's sanitiser — the first `''|*[!0-9]*)` AFTER the marker line
  awk -v mark="$M_P3" 'index($0, mark) {seen=1} seen && !done && /^[[:space:]]*'"'"''"'"'\|\*\[!0-9\]\*\)/ {sub(/'"'"''"'"'\|\*\[!0-9\]\*\)/, "'"'"''"'"')"); done=1} {print}' "$before" > "$tgt"
  if [ "$(_changed_lines "$before" "$tgt")" -lt 2 ] || ! bash -n "$tgt" 2>/dev/null; then
    fail_ "MP3 setup" "the sanitiser mutation did not apply cleanly"
  elif [ -z "${PATH_S:-}" ]; then
    fail_ "MP3 setup" "no isolated PATH from section S"
  else
    FM3="$(newtmp)"; mk_p3_fixture "$FM3"; run_p3 "$FM3" "$ARCH/multidoc.json" "$PATH_S" "$tgt"
    l="$(semgrep_line)"
    printf '%s' "$l" | grep -q "PASS" \
      && pass "MP3 (MUTATION) — with the sanitiser arm dropped, a two-document archive reads PASS again: S8 is what stops it" \
      || fail_ "MP3 (MUTATION)" "dropping the sanitiser arm changed nothing — S8 may be passing for another reason: ${l:-<none>}"
  fi
fi

# MP4 — restore the old snyk count (`// 0` + `|| echo 0`) on a mirror: N3's
# renamed key must read as PASS again.
MP4="$(newtmp)/fw"
if ! mk_mirror "$MP4"; then
  fail_ "MP4 setup" "could not mirror scripts/"
else
  tgt="$MP4/scripts/run-phase3-validation.sh"; before="$(mktemp)"; cp "$tgt" "$before"
  sed "s~^.*${M_PN}\$~  findings=\$(jq '(.vulnerabilities | length) // 0' \"\$archive\" 2>/dev/null || echo 0)   ${M_PN}~" "$before" > "$tgt"
  if [ "$(_changed_lines "$before" "$tgt")" -lt 2 ] || ! bash -n "$tgt" 2>/dev/null || ! grep -q "(.vulnerabilities | length) // 0" "$tgt"; then
    fail_ "MP4 setup" "the snyk count mutation did not apply cleanly"
  elif [ -z "${PATH_N:-}" ]; then
    fail_ "MP4 setup" "no isolated PATH from section N"
  else
    FM4="$(newtmp)"; mk_p3_fixture "$FM4"; run_p3 "$FM4" "$ARCH/snyk-renamed.json" "$PATH_N" "$tgt"
    l="$(snyk_line)"
    printf '%s' "$l" | grep -q "PASS" \
      && pass "MP4 (MUTATION) — with the old snyk count restored, a renamed key reads as PASS again: N3 is what stops it" \
      || fail_ "MP4 (MUTATION)" "restoring the old snyk count changed nothing — N3 may be passing for another reason: ${l:-<none>}"
  fi
fi

# MP5 — weaken the snyk type check to a PRESENCE check on a mirror: N4's object
# must read PASS again.
MP5="$(newtmp)/fw"
if ! mk_mirror "$MP5"; then
  fail_ "MP5 setup" "could not mirror scripts/"
else
  tgt="$MP5/scripts/run-phase3-validation.sh"; before="$(mktemp)"; cp "$tgt" "$before"
  sed "s~^.*${M_PN}\$~  findings=\$(jq -e 'if has(\"vulnerabilities\") and .vulnerabilities != null then (.vulnerabilities | length) else error(\"x\") end' \"\$archive\" 2>/dev/null) || findings=\"\"   ${M_PN}~" "$before" > "$tgt"
  if [ "$(_changed_lines "$before" "$tgt")" -lt 2 ] || ! bash -n "$tgt" 2>/dev/null || ! grep -q 'has("vulnerabilities") and .vulnerabilities != null' "$tgt"; then
    fail_ "MP5 setup" "the snyk presence-check mutation did not apply cleanly"
  elif [ -z "${PATH_N:-}" ]; then
    fail_ "MP5 setup" "no isolated PATH from section N"
  else
    FM5="$(newtmp)"; mk_p3_fixture "$FM5"; run_p3 "$FM5" "$ARCH/snyk-object.json" "$PATH_N" "$tgt"
    l="$(snyk_line)"
    printf '%s' "$l" | grep -q "PASS" \
      && pass "MP5 (MUTATION) — with a presence check, a .vulnerabilities object reads PASS again: N4 is what stops it" \
      || fail_ "MP5 (MUTATION)" "the snyk presence-check mutant did not re-open the defect: ${l:-<none>}"
  fi
fi

# MP6 — review round 2's surviving mutant x10: an `if type == "array"` arm that
# sums `.[]?.vulnerabilities[]?` over a top-level array. N5 must catch it.
MP6="$(newtmp)/fw"
if ! mk_mirror "$MP6"; then
  fail_ "MP6 setup" "could not mirror scripts/"
else
  tgt="$MP6/scripts/run-phase3-validation.sh"; before="$(mktemp)"; cp "$tgt" "$before"
  sed "s~^.*${M_PN}\$~  findings=\$(jq -e 'if type == \"array\" then ([.[]?.vulnerabilities[]?] | length) elif (.vulnerabilities | type) == \"array\" then (.vulnerabilities | length) else error(\"x\") end' \"\$archive\" 2>/dev/null) || findings=\"\"   ${M_PN}~" "$before" > "$tgt"
  if [ "$(_changed_lines "$before" "$tgt")" -lt 2 ] || ! bash -n "$tgt" 2>/dev/null || ! grep -q 'if type == "array" then (\[\.\[\]?\.vulnerabilities' "$tgt"; then
    fail_ "MP6 setup" "the top-level-array mutation did not apply cleanly"
  elif [ -z "${PATH_N:-}" ]; then
    fail_ "MP6 setup" "no isolated PATH from section N"
  else
    FM6="$(newtmp)"; mk_p3_fixture "$FM6"; run_p3 "$FM6" "$ARCH/snyk-toparray.json" "$PATH_N" "$tgt"
    l="$(snyk_line)"
    printf '%s' "$l" | grep -q "PASS" \
      && pass "MP6 (MUTATION) — with a top-level-array arm accepted, the --all-projects shape reads PASS again: N5 is what stops it" \
      || fail_ "MP6 (MUTATION)" "the top-level-array mutant did not re-open the defect: ${l:-<none>}"
  fi
fi

# MU2 — drop the `rm -f "$PROCESS_STATE.tmp"` on the attestation REFUSE path
# (the line before the marker) on a mirror: U3b must see the .tmp left behind.
MU2="$(newtmp)/fw"
if ! mk_mirror "$MU2"; then
  fail_ "MU2 setup" "could not mirror scripts/"
else
  tgt="$MU2/scripts/process-checklist.sh"; before="$(mktemp)"; cp "$tgt" "$before"
  mline="$(grep -n "${M_UF}\$" "$before" | head -1 | cut -d: -f1)"
  rmline=$(( ${mline:-0} - 1 ))
  if [ "$rmline" -lt 1 ] || ! sed -n "${rmline}p" "$before" | grep -q 'rm -f "\$PROCESS_STATE.tmp"'; then
    fail_ "MU2 setup" "the line before the REFUSE marker is not the rm -f"
  else
    sed "${rmline}d" "$before" > "$tgt"
    if [ "$(_changed_lines "$before" "$tgt")" -ne 1 ] || ! bash -n "$tgt" 2>/dev/null; then
      fail_ "MU2 setup" "the rm -f deletion did not apply cleanly"
    elif [ -z "${MVD:-}" ]; then
      fail_ "MU2 setup" "no mv shim from U3"
    else
      UM2="$(newtmp)"; mk_uat_fixture "$UM2"
      run_uat "$UM2" "$tgt" "$MVD:$PATH"
      [ -e "$UM2/.claude/process-state.json.tmp" ] \
        && pass "MU2 (MUTATION) — with the rm -f dropped, a failed rename leaves the .tmp behind: U3b is what stops it" \
        || fail_ "MU2 (MUTATION)" "dropping the rm -f left no .tmp — U3b may be passing for another reason (rc=$UAT_RC)"
    fi
  fi
fi

# MU3 — turn the step-completion REFUSE arm back into the old unconditional
# receipt on a mirror: U4's read-only case must announce "completed" again.
MU3="$(newtmp)/fw"
if ! mk_mirror "$MU3"; then
  fail_ "MU3 setup" "could not mirror scripts/"
else
  tgt="$MU3/scripts/process-checklist.sh"; before="$(mktemp)"; cp "$tgt" "$before"
  sed "s~^.*${M_SF}\$~    print_ok \"Step '\$step_id' completed for \$process (\$new_step_num/\${#steps[@]})\"   ${M_SF}~" "$before" > "$tgt"
  if [ "$(_changed_lines "$before" "$tgt")" -lt 2 ] || ! bash -n "$tgt" 2>/dev/null || [ "$(grep -c "print_ok \"Step '\$step_id' completed for" "$tgt")" -ne 2 ]; then
    fail_ "MU3 setup" "the step refuse-arm mutation did not apply cleanly"
  else
    UM3="$(newtmp)"; mk_uat_fixture "$UM3"
    printf 'tester A results\n' > "$UM3/tests/uat/sessions/s1/submissions/tester-a.md"
    chmod 555 "$UM3/.claude"
    run_step "$UM3" "$tgt"; chmod 755 "$UM3/.claude"
    printf '%s' "$UAT_OUT" | grep -q "Step 'results_received' completed" \
      && pass "MU3 (MUTATION) — with the step refuse arm turned back into a receipt, a read-only .claude/ is announced as completed: U4 is what stops it" \
      || fail_ "MU3 (MUTATION)" "the mutant did not produce the false receipt — U4 may be passing for another reason"
  fi
fi

# MU4 — review round 3's surviving m5: the step guard covers only jq and
# tolerates a failed mv (`mv … || true` on its own line). U4c must catch it.
MU4="$(newtmp)/fw"
if ! mk_mirror "$MU4"; then
  fail_ "MU4 setup" "could not mirror scripts/"
else
  tgt="$MU4/scripts/process-checklist.sh"; before="$(mktemp)"; cp "$tgt" "$before"
  mline="$(grep -n "${M_SR}\$" "$before" | head -1 | cut -d: -f1)"
  gline=$(( ${mline:-0} - 1 ))
  if [ "$gline" -lt 1 ] || ! sed -n "${gline}p" "$before" | grep -qF '&& mv "$PROCESS_STATE.tmp" "$PROCESS_STATE"; then'; then
    fail_ "MU4 setup" "the line before the STEP-RECEIPT marker is not the guarded write"
  else
    awk -v L="$gline" 'NR==L { sub(/ && mv "\$PROCESS_STATE\.tmp" "\$PROCESS_STATE"; then/, "; then"); print; print "    mv \"$PROCESS_STATE.tmp\" \"$PROCESS_STATE\" 2>/dev/null || true"; next } { print }' "$before" > "$tgt"
    if [ "$(_changed_lines "$before" "$tgt")" -lt 2 ] || ! bash -n "$tgt" 2>/dev/null || [ "$(grep -cF 'mv "$PROCESS_STATE.tmp" "$PROCESS_STATE" 2>/dev/null || true' "$tgt")" -ne 1 ]; then
      fail_ "MU4 setup" "the jq-only-guard mutation did not apply cleanly"
    elif [ -z "${MVD:-}" ]; then
      fail_ "MU4 setup" "no mv shim from U3"
    else
      UM4="$(newtmp)"; mk_uat_fixture "$UM4"
      printf 'tester A results\n' > "$UM4/tests/uat/sessions/s1/submissions/tester-a.md"
      run_step "$UM4" "$tgt" "$MVD:$PATH"
      [ "$UAT_RC" -eq 0 ] && printf '%s' "$UAT_OUT" | grep -q "Step 'results_received' completed" \
        && pass "MU4 (MUTATION) — with the guard covering only jq, a failed rename is announced as completed at rc 0: U4c is what stops it" \
        || fail_ "MU4 (MUTATION)" "the jq-only guard did not produce the false receipt (rc=$UAT_RC) — U4c may be passing for another reason"
    fi
  fi
fi

# _mutate_line <src> <dst> <lineno> <literal-pattern> <replacement> — rewrite
# one line by literal substitution (bash expansion, no sed/awk metachars —
# the replacements below carry `&&`, `|`, `$` and `"`); returns 1 if the
# pattern is not on that line
_mutate_line() {
  local src="$1" dst="$2" ln="$3" pat="$4" rep="$5" orig mut
  orig="$(sed -n "${ln}p" "$src")"
  case "$orig" in *"$pat"*) ;; *) return 1 ;; esac
  mut="${orig/"$pat"/$rep}"
  { head -n $((ln - 1)) "$src"; printf '%s\n' "$mut"; tail -n +$((ln + 1)) "$src"; } > "$dst"
}

# MU5 — review round 4's surviving x1b: the step guard tolerates a jq failure
# (`> tmp || true && mv`), so a failed jq renames an EMPTY .tmp over the state
# file and prints the receipt. U4e must catch it.
MU5="$(newtmp)/fw"
if ! mk_mirror "$MU5"; then
  fail_ "MU5 setup" "could not mirror scripts/"
else
  tgt="$MU5/scripts/process-checklist.sh"; before="$(mktemp)"; cp "$tgt" "$before"
  mline="$(grep -n "${M_SR}\$" "$before" | head -1 | cut -d: -f1)"
  gline=$(( ${mline:-0} - 1 ))
  if [ "$gline" -lt 1 ] || ! _mutate_line "$before" "$tgt" "$gline" '> "$PROCESS_STATE.tmp" && mv' '> "$PROCESS_STATE.tmp" || true && mv' \
     || [ "$(_changed_lines "$before" "$tgt")" -ne 2 ] || ! bash -n "$tgt" 2>/dev/null; then
    fail_ "MU5 setup" "the jq-tolerant step-guard mutation did not apply cleanly"
  else
    UM5="$(newtmp)"; mk_uat_fixture "$UM5"
    printf 'tester A results\n' > "$UM5/tests/uat/sessions/s1/submissions/tester-a.md"
    jq '.uat_session.steps_completed = "agents_dispatched template_generated orchestrator_notified"' "$UM5/.claude/process-state.json" > "$UM5/.claude/ps.new" && mv "$UM5/.claude/ps.new" "$UM5/.claude/process-state.json"
    run_step "$UM5" "$tgt"
    if [ "$UAT_RC" -eq 0 ] && printf '%s' "$UAT_OUT" | grep -q "Step 'results_received' completed" && [ ! -s "$UM5/.claude/process-state.json" ]; then
      pass "MU5 (MUTATION) — with the step guard tolerating jq, a failed jq zero-bytes the state file and is announced as completed: U4e is what stops it"
    else
      fail_ "MU5 (MUTATION)" "the jq-tolerant mutant did not produce the false receipt (rc=$UAT_RC, bytes=$(wc -c < "$UM5/.claude/process-state.json" | tr -d ' ')) — U4e may be passing for another reason"
    fi
  fi
fi

# MU6 — round 4's surviving x3: the attestation guard's `&& mv` becomes `; mv`
# (the if-list's status is mv's), so a failed jq is RECORDED over an empty
# state file. U2d must catch it.
MU6="$(newtmp)/fw"
if ! mk_mirror "$MU6"; then
  fail_ "MU6 setup" "could not mirror scripts/"
else
  tgt="$MU6/scripts/process-checklist.sh"; before="$(mktemp)"; cp "$tgt" "$before"
  mline="$(grep -n "${M_UR}\$" "$before" | head -1 | cut -d: -f1)"
  gline=$(( ${mline:-0} - 1 ))
  if [ "$gline" -lt 1 ] || ! _mutate_line "$before" "$tgt" "$gline" '&& mv "$PROCESS_STATE.tmp"' '; mv "$PROCESS_STATE.tmp"' \
     || [ "$(_changed_lines "$before" "$tgt")" -ne 2 ] || ! bash -n "$tgt" 2>/dev/null; then
    fail_ "MU6 setup" "the jq-tolerant attestation-guard mutation did not apply cleanly"
  else
    UM6="$(newtmp)"; mk_uat_fixture "$UM6"
    jq '.uat_session.solo_attestations = "corrupt"' "$UM6/.claude/process-state.json" > "$UM6/.claude/ps.new" && mv "$UM6/.claude/ps.new" "$UM6/.claude/process-state.json"
    run_uat "$UM6" "$tgt"
    if printf '%s' "$UAT_OUT" | grep -q "RECORDED" && [ ! -s "$UM6/.claude/process-state.json" ]; then
      pass "MU6 (MUTATION) — with the attestation guard tolerating jq, a failed jq zero-bytes the state file and is announced as RECORDED: U2d is what stops it"
    else
      fail_ "MU6 (MUTATION)" "the jq-tolerant mutant did not produce the false receipt (rc=$UAT_RC, bytes=$(wc -c < "$UM6/.claude/process-state.json" | tr -d ' ')) — U2d may be passing for another reason"
    fi
  fi
fi

# MU1 — turn the REFUSE arm back into the old unconditional receipt on a
# mirror: U2's read-only case must be announced as RECORDED again.
MU1="$(newtmp)/fw"
if ! mk_mirror "$MU1"; then
  fail_ "MU1 setup" "could not mirror scripts/"
else
  tgt="$MU1/scripts/process-checklist.sh"; before="$(mktemp)"; cp "$tgt" "$before"
  # `~` as the delimiter: the marker carries `#` (see MP1)
  sed "s~^.*${M_UF}\$~          print_ok \"results_received: SOLO-MODE attested and RECORDED (reason: \$uat_reason) — no external submissions required.\"   ${M_UF}~" "$before" > "$tgt"
  # count print_ok LINES, not the phrase — the fix's own comment quotes it
  if [ "$(_changed_lines "$before" "$tgt")" -lt 2 ] || ! bash -n "$tgt" 2>/dev/null || [ "$(grep -c 'print_ok "results_received: SOLO-MODE attested and RECORDED' "$tgt")" -ne 2 ]; then
    fail_ "MU1 setup" "the refuse-arm mutation did not apply cleanly"
  else
    UM="$(newtmp)"; mk_uat_fixture "$UM"; chmod 555 "$UM/.claude"
    run_uat "$UM" "$tgt"; chmod 755 "$UM/.claude"
    printf '%s' "$UAT_OUT" | grep -q "RECORDED" \
      && pass "MU1 (MUTATION) — with the refuse arm turned back into a receipt, a read-only .claude/ is announced as RECORDED: U2 is what stops it" \
      || fail_ "MU1 (MUTATION)" "the mutant did not produce the false receipt — U2 may be passing for another reason"
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] && exit 0
exit 1
