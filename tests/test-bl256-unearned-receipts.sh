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
#       decides production release.
#   (b) scripts/process-checklist.sh's uat_session:results_received solo escape
#       appended its attestation with `jq … > tmp && mv` and then printed
#       "attested and RECORDED" unconditionally — a read-only .claude/ left no
#       record while the operator was told there was one.
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
# run_uat <fixture> [checklist] → UAT_OUT, UAT_RC
run_uat() {
  local fx="$1" pc="${2:-$PC}"
  UAT_OUT="$( cd "$fx" && env SOLO_UAT_SOLO_ATTESTED=1 SOLO_UAT_REASON="bl256-test" bash "$pc" --complete-step uat_session:results_received 2>&1 )"; UAT_RC=$?
  return 0
}

U1="$(newtmp)"; mk_uat_fixture "$U1"; run_uat "$U1"
if printf '%s' "$UAT_OUT" | grep -q "RECORDED" && jq -e '.uat_session.solo_attestations[0].reason == "bl256-test"' "$U1/.claude/process-state.json" >/dev/null 2>&1; then
  pass "U1 — with a writable state file the attestation is recorded AND announced (rc=$UAT_RC)"
else
  fail_ "U1" "rc=$UAT_RC; recorded=$(jq -c '.uat_session.solo_attestations' "$U1/.claude/process-state.json" 2>/dev/null); out: $(printf '%s' "$UAT_OUT" | grep -i 'results_received' | head -2 | tr '\n' ' ')"
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

echo "=== M — mutation proofs on a mirror ==="

M_P3="# BL-256-P3-COUNT-RECEIPT"
M_UR="# BL-256-UAT-ATTEST-RECEIPT"
M_UF="# BL-256-UAT-ATTEST-REFUSE"
for pair in "$P3|$M_P3" "$PC|$M_UR" "$PC|$M_UF"; do
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
