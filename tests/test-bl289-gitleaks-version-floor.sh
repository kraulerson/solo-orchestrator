#!/usr/bin/env bash
# BL-289 — THE GITLEAKS VERSION FLOOR, RAISED AND ENFORCED.
#
# THE DEFECT THIS PINS, AND WHY IT IS A SECURITY DIFFERENCE RATHER THAN A NIT.
# `templates/tool-matrix/common.json` declared `min_version: 8.18.0` for
# gitleaks and NOTHING read it — `grep -c min_version scripts/resolve-tools.sh`
# was 0, and the one reader (`check-versions.sh`) is an advisory report, not a
# path adoption takes. Two facts make that matter:
#
#   1. The subcommands Scout runs — `gitleaks git` and `gitleaks dir` — are the
#      post-8.19.0 spelling. Upstream deprecated and hid `detect`/`protect` in
#      **v8.19.0** (gitleaks README, "Usage > Commands"). A 8.18.x binary does
#      not answer `gitleaks git`.
#   2. So a too-old scanner produced `scan-failed` — the command errored — and
#      §6.1's table treats those two statuses very differently at `personal`:
#      `scan-failed` WARNS AND CARRIES ON with no acknowledgement, while
#      `tool-unavailable` STOPS until an acceptance is recorded.
#
# A contributor with an old gitleaks therefore adopted a personal project with
# a cheerful warning where the design requires a signed acceptance. The floor is
# what converts "the scanner broke" into the truthful "there is no usable
# scanner here", which is what `tool-unavailable` means.
#
# THE STUB IS THE WHOLE TECHNIQUE. Every case drives a fake `gitleaks` whose
# `version` output is the case's parameter, because the real one on this host is
# 8.30.1 and no version of this proof may depend on what a contributor happens
# to have installed. `SCOUT_GITLEAKS_BIN` is the seam scout-secrets.sh already
# documents for exactly this.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
TMPS=""

pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip_() { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

cleanup() { for d in $TMPS; do rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT
newtmp() { local d; d=$(mktemp -d); TMPS="$TMPS $d"; printf '%s\n' "$d"; }

command -v jq  >/dev/null 2>&1 || { echo "  [FAIL] jq is required";  echo "Results: 0 passed, 1 failed, 0 skipped"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "  [FAIL] git is required"; echo "Results: 0 passed, 1 failed, 0 skipped"; exit 1; }

# THE FLOOR IS READ FROM THE MATRIX, NEVER TRANSCRIBED. A test that hard-codes
# `8.19.0` passes after somebody lowers the matrix back to 8.18.0 — which is
# the exact regression this entry exists to prevent. F1 pins the matrix value
# itself; every other case compares against whatever the matrix now says.
FLOOR="$(jq -r '.tools[] | select(.name == "gitleaks") | .min_version // ""' \
         "$REPO_ROOT/templates/tool-matrix/common.json" 2>/dev/null)"

# mk_stub DIR VERSION — a fake gitleaks. `version` prints VERSION; `git`/`dir`
# write an EMPTY findings array and exit 0, so a scan that is allowed to run
# reports `scanned` with zero findings. That asymmetry is what lets a case tell
# "the floor stopped it" from "the scan ran and found nothing".
mk_stub() {
  local d="$1" v="$2"
  mkdir -p "$d" || return 1
  cat > "$d/gitleaks" <<STUB
#!/usr/bin/env bash
if [ "\${1:-}" = "version" ]; then printf '%s\n' "$v"; exit 0; fi
_out=""
while [ \$# -gt 0 ]; do
  case "\$1" in -r) _out="\$2"; shift 2 ;; *) shift ;; esac
done
[ -n "\$_out" ] && printf '[]\n' > "\$_out"
exit 0
STUB
  chmod +x "$d/gitleaks" || return 1
}

# scan ROOT BIN — run Scout's secrets scan and publish its work files.
SC_STATUS=""; SC_NOTE=""; SC_VER=""
scan() {
  local root="$1" bin="$2"
  local T; T="$(mktemp -d)"; TMPS="$TMPS $T"
  ( . "$REPO_ROOT/scripts/lib/scout/scout-core.sh"    >/dev/null 2>&1
    . "$REPO_ROOT/scripts/lib/scout/scout-secrets.sh" >/dev/null 2>&1
    SCOUT_GITLEAKS_BIN="$bin"
    scout_secrets_scan "$root" "$T" ) >/dev/null 2>&1
  SC_STATUS="$(cat "$T/secstatus" 2>/dev/null)"
  SC_NOTE="$(cat "$T/secnote"   2>/dev/null)"
  SC_VER="$(cat "$T/secversion" 2>/dev/null)"
}

mk_repo() {
  local d="$1"
  git init -q -b main "$d" 2>/dev/null || return 1
  ( cd "$d" || exit 1
    git config user.email bl289@test.invalid
    git config user.name  "BL289 Test"
    printf 'hello\n' > README.md
    git add -A && git commit -qm "their history" ) >/dev/null 2>&1 || return 1
}

echo "== BL-289 — the gitleaks version floor =="

# ═══════════════════════════════════════════════════════════════════════════
# F1 — THE MATRIX DECLARES A FLOOR OF AT LEAST 8.19.0
# ═══════════════════════════════════════════════════════════════════════════
f1() {
  local label="F1 the tool matrix declares gitleaks required, with a floor >= 8.19.0"
  local req=""
  req="$(jq -r '.tools[] | select(.name == "gitleaks") | .required' \
        "$REPO_ROOT/templates/tool-matrix/common.json" 2>/dev/null)"
  if [ "$req" != "true" ]; then fail_ "$label" "required=$req (want true)"; return; fi
  if [ -z "$FLOOR" ]; then fail_ "$label" "no min_version on the gitleaks entry"; return; fi
  # `8.19.0` is the version upstream deprecated `detect`/`protect` in, which is
  # the same release that made `git`/`dir` the spelling Scout uses.
  if awk -v a="$FLOOR" 'BEGIN{n=split(a,A,".");
        if ((A[1]+0) < 8) exit 0;
        if ((A[1]+0) == 8 && (A[2]+0) < 19) exit 0;
        exit 1 }'; then
    fail_ "$label" "min_version=$FLOOR is below 8.19.0, where gitleaks git/dir became the spelling Scout runs"
  else
  # THE DUPLICATION IS PINNED. Scout sources nothing (its M5 header) and must
  # work pointed at any project from anywhere, so it cannot read the framework's
  # matrix at runtime and carries the floor as its own constant. Two spellings
  # of one number drift silently unless something compares them — and a drift
  # here is not cosmetic: the matrix is what `check-versions.sh` reports to the
  # operator, while Scout's constant is what actually refuses a scan.
  local scout_floor=""
  # ANCHORED ON THE MARKER, AND EXACTLY ONE MATCH REQUIRED. A first cut took
  # `head -1` of every `_SCOUT_GITLEAKS_MIN="…"` in the file, which a DECOY
  # earlier occurrence defeats: declare the name with the right value high up,
  # assign the wrong one at the marker, and this read the right value while the
  # code used the wrong one. The suite still went red through F2/F3, so the
  # mutant died — but F1 is the case that claims to pin the drift, and it did
  # not. Keying on the marker line and refusing a second match fixes that.
  local _floor_lines
  _floor_lines="$(grep -cE '_SCOUT_GITLEAKS_MIN="[0-9][0-9.]*".*SCOUT-SECRETS-VERSION-FLOOR' \
      "$REPO_ROOT/scripts/lib/scout/scout-secrets.sh" 2>/dev/null)"
  case "$_floor_lines" in ''|*[!0-9]*) _floor_lines=0 ;; esac
  if [ "$_floor_lines" -ne 1 ]; then
    fail_ "$label" "expected exactly one marked floor constant, found $_floor_lines"
    return
  fi
  scout_floor="$(grep -E '_SCOUT_GITLEAKS_MIN="[0-9][0-9.]*".*SCOUT-SECRETS-VERSION-FLOOR' \
      "$REPO_ROOT/scripts/lib/scout/scout-secrets.sh" 2>/dev/null \
      | sed 's/.*_SCOUT_GITLEAKS_MIN="//; s/".*//')"
  if [ -z "$scout_floor" ]; then
    fail_ "$label" "no SCOUT-SECRETS-VERSION-FLOOR constant found in scout-secrets.sh"
  elif [ "$scout_floor" != "$FLOOR" ]; then
    fail_ "$label" "the matrix says $FLOOR and scout-secrets.sh enforces $scout_floor — one number, two spellings, drifted"
  else
    pass "$label (matrix and scout both say $FLOOR)"
  fi
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# F2 — A SCANNER BELOW THE FLOOR IS `tool-unavailable`, NEVER `scanned`
#      AND NEVER `scan-failed`
# ═══════════════════════════════════════════════════════════════════════════
f2() {
  local label="F2 a gitleaks below the floor reports tool-unavailable, not scanned and not scan-failed"
  local T; T=$(newtmp)
  mk_repo "$T/p"        || { fail_ "$label" "fixture repo failed"; return; }
  mk_stub "$T/old" "8.18.0" || { fail_ "$label" "stub build failed"; return; }

  scan "$T/p" "$T/old/gitleaks"
  local bad=""
  [ "$SC_STATUS" = "tool-unavailable" ] || bad="$bad [status=$SC_STATUS, want tool-unavailable]"
  # THE TWO WRONG ANSWERS, NAMED. `scanned` is a clean bill of health from a
  # binary that cannot run the scan; `scan-failed` is what the UNFIXED code
  # produced and it is the one that carries on at `personal`.
  [ "$SC_STATUS" = "scanned" ]     && bad="$bad [reported a clean scan from an unusable binary]"
  [ "$SC_STATUS" = "scan-failed" ] && bad="$bad [reported scan-failed, which carries on at personal]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# F3 — THE NOTE NAMES BOTH NUMBERS
#      "your scanner is too old" with neither number is not actionable.
# ═══════════════════════════════════════════════════════════════════════════
f3() {
  local label="F3 the refusal names the version found and the version required"
  local T; T=$(newtmp)
  mk_repo "$T/p" || { fail_ "$label" "fixture repo failed"; return; }
  mk_stub "$T/old" "8.18.0" || { fail_ "$label" "stub build failed"; return; }
  scan "$T/p" "$T/old/gitleaks"
  local bad=""
  case "$SC_NOTE" in *8.18.0*) : ;; *) bad="$bad [the note does not name the version found]" ;; esac
  case "$SC_NOTE" in *"$FLOOR"*) : ;; *) bad="$bad [the note does not name the floor $FLOOR]" ;; esac
  # And the version it FOUND is still recorded, so a reader of the report can
  # see what was on the host rather than only that it was rejected.
  [ "$SC_VER" = "8.18.0" ] || bad="$bad [secversion=$SC_VER, want 8.18.0]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# F4 — THE POSITIVE CONTROL, AND WITHOUT IT EVERY CASE ABOVE PASSES ON A
#      FLOOR THAT REJECTS EVERYTHING
# ═══════════════════════════════════════════════════════════════════════════
f4() {
  local label="F4 a gitleaks AT and ABOVE the floor is allowed to scan"
  local T; T=$(newtmp)
  mk_repo "$T/p" || { fail_ "$label" "fixture repo failed"; return; }
  local bad="" v
  # SUFFIXED AND `v`-PREFIXED TAGS ARE LEGITIMATE and earlier cuts refused
  # both: the guard read the raw string (so `v8.30.1` was "unreadable"), then
  # required the whole string to be numeric-dotted (so `9.9.9-fake` was too).
  # This is the converse control for F5 — a guard that refuses everything
  # passes F5 and fails here.
  for v in "$FLOOR" "8.30.1" "9.0.0" "v8.30.1" "v$FLOOR" "9.9.9-fake" "$FLOOR-rc1"; do
    mk_stub "$T/ok-$v" "$v" || { bad="$bad [stub $v failed]"; continue; }
    scan "$T/p" "$T/ok-$v/gitleaks"
    [ "$SC_STATUS" = "scanned" ] || bad="$bad [$v: status=$SC_STATUS, want scanned]"
  done
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# F5 — AN UNREADABLE VERSION FAILS CLOSED
#      `## BL-147:`: a check that cannot run must not pass. A binary whose
#      version cannot be parsed has not demonstrated it meets the floor.
# ═══════════════════════════════════════════════════════════════════════════
f5() {
  local label="F5 a scanner whose version cannot be read is tool-unavailable, not assumed current"
  local T; T=$(newtmp)
  mk_repo "$T/p" || { fail_ "$label" "fixture repo failed"; return; }
  local bad="" v
  # NO NUMERIC PREFIX AT ALL is what "unreadable" means here. `9abc` and
  # `v9-dev` are deliberately NOT in this list: their numeric prefix is 9, they
  # compare as major 9, and they meet the floor. That is a recorded choice, not
  # an oversight — requiring the whole string to be numeric-dotted refused
  # `9.9.9-fake`, and a gitleaks built from source carries exactly that shape.
  # `version is set by build process` IS UPSTREAM'S LITERAL DEFAULT when the
  # build does not stamp it — `go install` and a plain `go build` both produce
  # it. It has no digits, so it is refused, and the note names the remedy.
  for v in "" "not-a-version" "banana.split" "-" "v" "version is set by build process"; do
    mk_stub "$T/weird" "$v" || { bad="$bad [stub failed]"; continue; }
    scan "$T/p" "$T/weird/gitleaks"
    [ "$SC_STATUS" = "tool-unavailable" ] \
      || bad="$bad ['$v': status=$SC_STATUS, want tool-unavailable]"
    # THE STATUS ALONE CANNOT PIN THIS GUARD, and that is measured: an empty
    # version compares as below the floor anyway, so BOTH paths reach
    # `tool-unavailable` and the guard's mutant survived a status-only
    # assertion. What differs is the MESSAGE — "its version could not be read"
    # against "is , and this scan needs 8.19.0", the second of which names a
    # version the operator never saw. The message is the reason the guard
    # exists, so the message is what this asserts.
    case "$SC_NOTE" in
      *"version could not be read"*) : ;;
      *) bad="$bad ['$v': the note does not say the version was unreadable]" ;;
    esac
  done
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# F6 — THE TIER CONSEQUENCE, WHICH IS THE WHOLE POINT
#      §6.1: `tool-unavailable` at `personal` STOPS until an acceptance is
#      recorded; `scan-failed` carries on with none. This case is what makes
#      F2 a security property rather than a spelling preference.
# ═══════════════════════════════════════════════════════════════════════════
f6() {
  local label="F6 a too-old scanner makes a PERSONAL adoption stop for a signed acceptance, not carry on"
  local T; T=$(newtmp)
  local rc=0
  jq -n '{schemaVersion: 2, secrets: {status: "tool-unavailable", findingCount: 0,
          scannedBy: "adoption", rulesSource: "framework",
          head: "0000000000000000000000000000000000000000", commitsScanned: 0}}' > "$T/r.json"
  ( . "$REPO_ROOT/scripts/lib/adopt/adopt-core.sh"    >/dev/null 2>&1
    . "$REPO_ROOT/scripts/lib/adopt/adopt-secrets.sh" >/dev/null 2>&1
    ADOPT_DEPLOYMENT=personal
    ADOPT_DISPOSITIONS_FILE=""
    ADOPT_WORK="$T/w"; mkdir -p "$ADOPT_WORK"
    adopt_secrets_decide "$T/r.json" ) >"$T/out" 2>&1 || rc=$?

  # THE CONTRAST CASE. If the floor were not enforced the same host would
  # produce `scan-failed`, and this is what that does at the same tier.
  local rc2=0
  jq '.secrets.status = "scan-failed"' "$T/r.json" > "$T/failed.json" 2>/dev/null
  ( . "$REPO_ROOT/scripts/lib/adopt/adopt-core.sh"    >/dev/null 2>&1
    . "$REPO_ROOT/scripts/lib/adopt/adopt-secrets.sh" >/dev/null 2>&1
    ADOPT_DEPLOYMENT=personal
    ADOPT_DISPOSITIONS_FILE=""
    ADOPT_WORK="$T/w2"; mkdir -p "$ADOPT_WORK"
    adopt_secrets_decide "$T/failed.json" ) >/dev/null 2>&1 || rc2=$?

  local bad=""
  [ "$rc" -ne 0 ]  || bad="$bad [tool-unavailable did not stop a personal adoption]"
  [ "$rc2" -eq 0 ] || bad="$bad [scan-failed stopped, so this case cannot show the difference]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

f1; f2; f3; f4; f5; f6

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
