#!/usr/bin/env bash
# WP10b part 1 — THE STOP'S INPUT IS A SCAN THIS RUN PERFORMED (§6.2b, I14).
#
# WHY THESE CASES CANNOT BE STUBBED. Every other adoption suite drives the
# scanner through a seam (`SCOUT_GITLEAKS_BIN`, `SOIF_ADOPT_GITLEAKS_BIN`) and
# a canned report, because what those suites prove is what adoption DOES with
# a status. These five prove something else: that the REAL scanner, invoked
# the way `_adopt_secrets_scan_own` invokes it, is not suppressible by
# anything the adoptee controls. A stub that answers "2 findings" proves
# nothing about gitleaks' rule-file and cwd semantics — it proves only that the
# stub was called. So these run the real tool.
#
# THE POSTURE IS `tests/test-bl288-scout-shallow-history-claim.sh`'s, and it is
# deliberate in BOTH directions: SKIP when gitleaks is absent locally (a
# contributor without it still gets a usable run) and FAIL when `CI` is set
# (`.github/workflows/tests.yml` installs the pinned 8.30.1 with a checksum, so
# absence there is a broken lane, not a missing convenience). A suite that
# skipped in CI would report green over a proof that never ran — which is the
# defect class this whole package exists inside.
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

# ── gitleaks: skip locally, FAIL in CI ──────────────────────────────────────
HAVE_GITLEAKS=0
command -v gitleaks >/dev/null 2>&1 && HAVE_GITLEAKS=1
if [ "$HAVE_GITLEAKS" -eq 0 ]; then
  if [ -n "${CI:-}" ]; then
    echo "  [FAIL] gitleaks is absent under CI — the lane installs a pinned 8.30.1; this is a broken lane, not a skip"
    echo "Results: 0 passed, 1 failed, 0 skipped"
    exit 1
  fi
  echo "  gitleaks is not installed — every own-scan pin SKIPS (set CI=1 to make this a failure)"
fi

# THE PLANTS ARE ASSEMBLED FROM HALVES so this file does not itself carry a
# 20-character AKIA-shaped literal that a scan of THIS repository would report.
# BASE32-VALIDITY IS LOAD-BEARING (bl288's lesson): gitleaks' `aws-access-token`
# rule requires [A-Z2-7] after `AKIA`, so a plant with a digit outside that set
# yields zero findings and makes the proof vacuous. Both of these were measured
# to produce exactly one finding each before this suite was written.
PLANT_A="AKIAQZ7X4M2N""PLKJ3HRD"
PLANT_B="AKIAM4T6Y2XQ""WVBN5JZC"

# mk_hist DIR — a repository whose history holds PLANT_A in a commit that was
# later REVERTED, so the working tree is clean and only a history walk finds it.
mk_hist() {
  local d="$1"
  git init -q -b main "$d" 2>/dev/null || return 1
  ( cd "$d" || exit 1
    git config user.email adopt@test.local
    git config user.name  "Adopt Test"
    printf 'key = "%s"\n' "$PLANT_A" > creds.txt
    git add -A && git commit -qm "add config" || exit 1
    rm creds.txt
    git add -A && git commit -qm "remove config" || exit 1
    printf 'ok\n' > README.md
    git add -A && git commit -qm "readme" || exit 1 ) || return 1
}

# count_findings REPORTJSON — the projection's finding count, or -1.
count_findings() {
  local n
  n=$(jq -r '.secrets.findingCount // -1' "$1" 2>/dev/null)
  case "$n" in ''|*[!0-9-]*) n=-1 ;; esac
  printf '%s\n' "$n"
}

echo "== WP10b/1 — the own scan (§6.2b) =="

# ═══════════════════════════════════════════════════════════════════════════
# (1) A HANDED-IN REPORT IS NOT THE STOP'S INPUT
# ═══════════════════════════════════════════════════════════════════════════
t1() {
  local label="O1 a handed-in 'scanned, 0' report does not become the stop's input"
  [ "$HAVE_GITLEAKS" -eq 1 ] || { skip_ "$label" "gitleaks absent"; return; }
  local T; T=$(newtmp)
  mk_hist "$T/adoptee" || { fail_ "$label" "fixture build failed"; return; }

  # The lie: a report claiming a clean full-history scan over a history that
  # holds a live credential.
  cat > "$T/handed-in.json" <<'EOJ'
{"schemaVersion":2,"secrets":{"tool":"gitleaks","status":"scanned","scope":"full-history","findingCount":0,"findings":[]}}
EOJ

  local out; out="$T/own.json"
  if ! ( . "$REPO_ROOT/scripts/lib/adopt/adopt-tools.sh" >/dev/null 2>&1
         ADOPT_FRAMEWORK_ROOT="$REPO_ROOT"
         ADOPT_WORK="$T/work"; mkdir -p "$ADOPT_WORK"
         _adopt_secrets_scan_own "$T/adoptee" "$T/handed-in.json" "$out" ) >"$T/log" 2>&1; then
    fail_ "$label" "_adopt_secrets_scan_own returned non-zero: $(head -3 "$T/log" | tr '\n' ' ')"; return
  fi

  local n; n=$(count_findings "$out")
  local by;  by=$(jq -r '.secrets.scannedBy // ""'   "$out" 2>/dev/null)
  local src; src=$(jq -r '.secrets.rulesSource // ""' "$out" 2>/dev/null)
  if [ "$n" -ge 1 ] && [ "$by" = "adoption" ] && [ "$src" = "framework" ]; then
    pass "$label"
  else
    fail_ "$label" "findingCount=$n scannedBy=$by rulesSource=$src (want >=1 / adoption / framework)"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# (2) THE ADOPTEE'S OWN RULE FILES DO NOT REACH THE STOP'S SCAN
#     This is the cwd pin. A build that scanned the clone from the ADOPTEE's
#     cwd fails here and nowhere else (§6.2b, the review's R-2).
# ═══════════════════════════════════════════════════════════════════════════
t2() {
  local label="O2 a tracked .gitleaks.toml and .gitleaksignore do not suppress the stop's scan"
  [ "$HAVE_GITLEAKS" -eq 1 ] || { skip_ "$label" "gitleaks absent"; return; }
  local T; T=$(newtmp)
  mk_hist "$T/adoptee" || { fail_ "$label" "fixture build failed"; return; }

  # The adoptee's own suppressors, both TRACKED. The `.gitleaksignore` needs
  # the finding's fingerprint, so take it from a scan that honours nothing.
  ( cd "$T/adoptee"
    gitleaks git --no-banner --exit-code 0 -f json -r "$T/fp.json" . ) >/dev/null 2>&1
  local fp; fp=$(jq -r '.[0].Fingerprint // empty' "$T/fp.json" 2>/dev/null)
  [ -n "$fp" ] || { fail_ "$label" "could not derive a fingerprint for the ignore file"; return; }

  ( cd "$T/adoptee"
    printf '%s\n' "$fp" > .gitleaksignore
    printf '[extend]\nuseDefault = true\n\n[[rules]]\nid = "never-matches"\nregex = "zzz-no-such-thing-zzz"\n' > .gitleaks.toml
    git add -A && git commit -qm "project scanner rules" ) >/dev/null 2>&1

  local out; out="$T/own.json"
  ( . "$REPO_ROOT/scripts/lib/adopt/adopt-tools.sh" >/dev/null 2>&1
    ADOPT_FRAMEWORK_ROOT="$REPO_ROOT"
    ADOPT_WORK="$T/work"; mkdir -p "$ADOPT_WORK"
    _adopt_secrets_scan_own "$T/adoptee" "" "$out" ) >"$T/log" 2>&1

  local n; n=$(count_findings "$out")
  if [ "$n" -ge 1 ]; then
    pass "$label"
  else
    fail_ "$label" "findingCount=$n — the adoptee's own rules reached the stop's scan (cwd or -c wrong)"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# (3) GITLEAKS_CONFIG IN THE LAUNCHING ENVIRONMENT DOES NOT REACH IT
# ═══════════════════════════════════════════════════════════════════════════
t3() {
  local label="O3 GITLEAKS_CONFIG exported at an allowlisting config does not suppress the scan"
  [ "$HAVE_GITLEAKS" -eq 1 ] || { skip_ "$label" "gitleaks absent"; return; }
  local T; T=$(newtmp)
  mk_hist "$T/adoptee" || { fail_ "$label" "fixture build failed"; return; }

  # A config whose rule set matches nothing at all.
  printf '[[rules]]\nid = "never-matches"\nregex = "zzz-no-such-thing-zzz"\n' > "$T/empty-rules.toml"

  local out; out="$T/own.json"
  ( . "$REPO_ROOT/scripts/lib/adopt/adopt-tools.sh" >/dev/null 2>&1
    ADOPT_FRAMEWORK_ROOT="$REPO_ROOT"
    ADOPT_WORK="$T/work"; mkdir -p "$ADOPT_WORK"
    # THE TWO VARIABLES TAKE DIFFERENT THINGS AND GETTING IT WRONG MAKES THE
    # CASE VACUOUS. `GITLEAKS_CONFIG` is a PATH; `GITLEAKS_CONFIG_TOML` is the
    # file's CONTENT. A first cut passed a path to both — measured, that makes
    # gitleaks exit 1 with `invalid character at start of key: /`, so this case
    # exercised the _TOML vector as a CRASH and never as a suppression, and the
    # `unset` of it was pinned by nothing.
    export GITLEAKS_CONFIG="$T/empty-rules.toml"
    export GITLEAKS_CONFIG_TOML="$(cat "$T/empty-rules.toml")"
    _adopt_secrets_scan_own "$T/adoptee" "" "$out" ) >"$T/log" 2>&1

  local n; n=$(count_findings "$out")
  if [ "$n" -ge 1 ]; then
    pass "$label"
  else
    fail_ "$label" "findingCount=$n — the environment's config reached the scan"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# (4) AN INLINE `gitleaks:allow` DOES NOT SUPPRESS IT
#     MEASURED, and it is the reason the empty working tree is not enough: the
#     comment lives in the history BLOB, which a history walk reads regardless
#     of what is checked out. Without --ignore-gitleaks-allow this is 1 finding
#     where it should be 2.
# ═══════════════════════════════════════════════════════════════════════════
t4() {
  local label="O4 an inline gitleaks:allow in history does not suppress the stop's scan"
  [ "$HAVE_GITLEAKS" -eq 1 ] || { skip_ "$label" "gitleaks absent"; return; }
  local T; T=$(newtmp)
  mk_hist "$T/adoptee" || { fail_ "$label" "fixture build failed"; return; }

  ( cd "$T/adoptee"
    printf 'other = "%s" # gitleaks:allow\n' "$PLANT_B" > second.txt
    git add -A && git commit -qm "second credential, allowed inline"
    rm second.txt
    git add -A && git commit -qm "remove second" ) >/dev/null 2>&1

  local out; out="$T/own.json"
  ( . "$REPO_ROOT/scripts/lib/adopt/adopt-tools.sh" >/dev/null 2>&1
    ADOPT_FRAMEWORK_ROOT="$REPO_ROOT"
    ADOPT_WORK="$T/work"; mkdir -p "$ADOPT_WORK"
    _adopt_secrets_scan_own "$T/adoptee" "" "$out" ) >"$T/log" 2>&1

  local n; n=$(count_findings "$out")
  if [ "$n" -ge 2 ]; then
    pass "$label"
  else
    fail_ "$label" "findingCount=$n (want >=2) — the inline allow suppressed a real finding"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# (5) A SHALLOW ADOPTEE STAYS SHALLOW — the stop does not unshallow behind
#     the operator's back, and its commit count is the ADOPTEE's.
# ═══════════════════════════════════════════════════════════════════════════
t5() {
  local label="O5 a shallow adoptee yields scanned-partial with the adoptee's own commit count"
  [ "$HAVE_GITLEAKS" -eq 1 ] || { skip_ "$label" "gitleaks absent"; return; }
  local T; T=$(newtmp)
  mk_hist "$T/origin" || { fail_ "$label" "fixture build failed"; return; }
  git clone -q --depth 1 "file://$T/origin" "$T/adoptee" 2>/dev/null \
    || { fail_ "$label" "shallow clone failed"; return; }

  local want; want=$(git -C "$T/adoptee" rev-list --count HEAD 2>/dev/null)

  local out; out="$T/own.json"
  ( . "$REPO_ROOT/scripts/lib/adopt/adopt-tools.sh" >/dev/null 2>&1
    ADOPT_FRAMEWORK_ROOT="$REPO_ROOT"
    ADOPT_WORK="$T/work"; mkdir -p "$ADOPT_WORK"
    _adopt_secrets_scan_own "$T/adoptee" "" "$out" ) >"$T/log" 2>&1

  local st; st=$(jq -r '.secrets.status // ""'          "$out" 2>/dev/null)
  local cs; cs=$(jq -r '.secrets.commitsScanned // ""'  "$out" 2>/dev/null)
  if [ "$st" = "scanned-partial" ] && [ "$cs" = "$want" ]; then
    pass "$label"
  else
    fail_ "$label" "status=$st commitsScanned=$cs (want scanned-partial / $want)"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# (6) THE SURVEY'S POLICY IS UNCHANGED — the converse of (2), and without it
#     the parameterisation is vacuous: a build that forced framework rules on
#     EVERY caller would pass (1)-(5) and silently turn Scout's read-only
#     survey into something that refuses to honour a project's own config,
#     which `## BL-288:` forbids in as many words.
# ═══════════════════════════════════════════════════════════════════════════
t6() {
  local label="O6 the SURVEY still honours the project's own .gitleaks.toml (the converse pin)"
  [ "$HAVE_GITLEAKS" -eq 1 ] || { skip_ "$label" "gitleaks absent"; return; }
  local T; T=$(newtmp)
  mk_hist "$T/adoptee" || { fail_ "$label" "fixture build failed"; return; }

  ( cd "$T/adoptee"
    printf '[[rules]]\nid = "never-matches"\nregex = "zzz-no-such-thing-zzz"\n' > .gitleaks.toml
    git add -A && git commit -qm "project rules" ) >/dev/null 2>&1

  # THIS DRIVES `scripts/scout.sh`, NOT THE FUNCTION. A first cut called
  # `scout_secrets_scan` directly and asserted its DEFAULT — which proved the
  # default and nothing else. Measured: mutating scout.sh's call site to pass
  # `framework` left that version of this case GREEN, because it never went
  # through scout.sh at all. The survey is the SCRIPT, so the pin is the script.
  bash "$REPO_ROOT/scripts/scout.sh" --root "$T/adoptee" --out "$T/scan" >/dev/null 2>&1
  local rep="$T/scan/scout-report.json"
  if [ ! -f "$rep" ]; then fail_ "$label" "scout.sh produced no report"; return; fi

  local n cfg
  n=$(jq -r '.secrets.findingCount // -1' "$rep" 2>/dev/null)
  cfg=$(jq -r '.secrets.configFile // ""'  "$rep" 2>/dev/null)
  case "$n" in ''|*[!0-9-]*) n=-1 ;; esac

  # BOTH halves. The count says the project's rules were honoured; the
  # disclosure says the survey still TOLD the reader they were — `## BL-288:`
  # asks for the second as much as the first.
  if [ "$n" -eq 0 ] && [ "$cfg" = ".gitleaks.toml" ]; then
    pass "$label"
  else
    fail_ "$label" "survey findingCount=$n configFile='$cfg' (want 0 / .gitleaks.toml) — the survey stopped honouring or disclosing the project's config"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# (7) NOTHING IS WRITTEN INTO THE ADOPTEE (§9.1-I4, `## BL-225:`'s invariant)
# ═══════════════════════════════════════════════════════════════════════════
t7() {
  local label="O7 the own scan writes nothing into the adoptee's tree"
  [ "$HAVE_GITLEAKS" -eq 1 ] || { skip_ "$label" "gitleaks absent"; return; }
  local T; T=$(newtmp)
  mk_hist "$T/adoptee" || { fail_ "$label" "fixture build failed"; return; }

  # A FULL recursive fingerprint INCLUDING .git — path, type and content hash.
  _fp() {
    ( cd "$1" && find . \( -type f -o -type l -o -type d \) -print0 2>/dev/null \
      | LC_ALL=C sort -z \
      | while IFS= read -r -d '' p; do
          if [ -f "$p" ] && [ ! -L "$p" ]; then
            printf '%s F %s\n' "$p" "$(shasum -a 256 "$p" 2>/dev/null | cut -d' ' -f1)"
          elif [ -L "$p" ]; then printf '%s L\n' "$p"
          else printf '%s D\n' "$p"; fi
        done )
  }
  _fp "$T/adoptee" > "$T/before"

  ( . "$REPO_ROOT/scripts/lib/adopt/adopt-tools.sh" >/dev/null 2>&1
    ADOPT_FRAMEWORK_ROOT="$REPO_ROOT"
    ADOPT_WORK="$T/work"; mkdir -p "$ADOPT_WORK"
    _adopt_secrets_scan_own "$T/adoptee" "" "$T/own.json" ) >/dev/null 2>&1

  _fp "$T/adoptee" > "$T/after"

  # THE POSITIVE CONTROL, and it is not optional. "Nothing was written" is
  # TRUE OF A FUNCTION THAT DOES NOT EXIST — measured: this case passed
  # against the base tree, before a line of the own scan was written. Requiring
  # that the scan ALSO produced a real result is what makes the assertion mean
  # what it says. (`## BL-233:` residual 15's vacuity floor, one surface over.)
  local n; n=$(count_findings "$T/own.json")
  if [ "$n" -lt 1 ]; then
    fail_ "$label" "VACUOUS: the scan produced findingCount=$n, so 'nothing was written' proves nothing"
    return
  fi

  if diff -q "$T/before" "$T/after" >/dev/null 2>&1; then
    pass "$label"
  else
    fail_ "$label" "the adoptee changed: $(diff "$T/before" "$T/after" | head -4 | tr '\n' ' ')"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# (8) THE VENDORED CONFIG EXISTS AND EXTENDS THE DEFAULTS
#     A `-c` pointed at a missing file makes gitleaks exit non-zero, which the
#     own scan would report as `scan-failed` — a stop at organizational. So the
#     file's presence is load-bearing, not decorative.
# ═══════════════════════════════════════════════════════════════════════════
t8() {
  local label="O8 templates/gitleaks/framework.toml exists and extends gitleaks' defaults"
  local f="$REPO_ROOT/templates/gitleaks/framework.toml"
  if [ ! -f "$f" ]; then fail_ "$label" "missing: templates/gitleaks/framework.toml"; return; fi
  # `grep -q useDefault` ALONE ACCEPTS `useDefault = false`, which would empty
  # the rule set while the label still claimed it extends the defaults.
  if grep -qE 'useDefault[[:space:]]*=[[:space:]]*true' "$f" && grep -q '\[extend\]' "$f"; then
    pass "$label"
  else
    fail_ "$label" "the config does not carry [extend] useDefault"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# (9) A FRAMEWORK POLICY WITH NO USABLE CONFIG FAILS LOUD — it never falls
#     back to the rules of the project being audited.
#
#     THIS CASE EXISTS BECAUSE THE GUARD HAD NO PROOF. The review neutered the
#     condition and all eight cases above stayed green, so the one line
#     standing between the stop and the audited project's own rule file could
#     have been deleted by anyone without a check going red. The empty-string
#     shape is the dangerous one: `-c ""` is not "no config", it is "discover
#     config normally", which is exactly the fallback the policy refuses.
# ═══════════════════════════════════════════════════════════════════════════
t9() {
  local label="O9 framework policy with no usable config fails LOUD, never to the project's rules"
  [ "$HAVE_GITLEAKS" -eq 1 ] || { skip_ "$label" "gitleaks absent"; return; }
  local T; T=$(newtmp)
  mk_hist "$T/adoptee" || { fail_ "$label" "fixture build failed"; return; }
  git clone -q --shared --no-checkout "$T/adoptee" "$T/clone" 2>/dev/null \
    || { fail_ "$label" "clone failed"; return; }

  # A config at the SCAN's cwd that suppresses everything. With a correct
  # guard it is never consulted; without one, `-c ""` finds it.
  printf '[[rules]]\nid = "never-matches"\nregex = "zzz-no-such-thing-zzz"\n' > "$T/clone/.gitleaks.toml"

  local shape st count
  for shape in empty missing; do
    local cfg=""
    [ "$shape" = "missing" ] && cfg="$T/definitely-not-here.toml"
    rm -rf "$T/w-$shape"; mkdir -p "$T/w-$shape"
    ( . "$REPO_ROOT/scripts/lib/scout/scout-core.sh"    >/dev/null 2>&1
      . "$REPO_ROOT/scripts/lib/scout/scout-secrets.sh" >/dev/null 2>&1
      scout_secrets_scan "$T/clone" "$T/w-$shape" framework "$cfg" ) >/dev/null 2>&1
    st=$(cat "$T/w-$shape/secstatus" 2>/dev/null)
    count=$(cat "$T/w-$shape/seccount" 2>/dev/null)
    # BOTH halves. `scan-failed` is the loud answer; a count of 0 alongside it
    # would be a clean bill of health issued by a scan that did not happen.
    if [ "$st" != "scan-failed" ]; then
      fail_ "$label" "[$shape] status=$st (want scan-failed) — the stop fell back to discovery"; return
    fi
    if [ -n "$count" ] && [ "$count" = "0" ]; then
      fail_ "$label" "[$shape] reported 0 findings on a scan that did not run"; return
    fi
  done
  pass "$label"
}

# ═══════════════════════════════════════════════════════════════════════════
# (10) THE STOP NEVER WRITES ITS RESULT OVER THE REPORT IT WAS GIVEN — in any
#      spelling of "the same file".
#
#      THIS CASE EXISTS BECAUSE THE GUARD HAD NO PIN. Two review rounds found
#      this surface twice: first there was no guard at all and `jq … > "$out"`
#      truncated the operator's report before the function reported failure;
#      then the guard compared SPELLINGS, so `./x.json` and a symlink still
#      destroyed it. Both were caught by review, neither by a test, and all
#      nine cases plus all sixteen lints stayed green through both. The fourth
#      shape is the control: a guard that refused everything would satisfy the
#      first three and break the function.
# ═══════════════════════════════════════════════════════════════════════════
t10() {
  local label="O10 the stop refuses to write over its own input, by identity and not by spelling"
  [ "$HAVE_GITLEAKS" -eq 1 ] || { skip_ "$label" "gitleaks absent"; return; }
  local T; T=$(newtmp)
  mk_hist "$T/adoptee" || { fail_ "$label" "fixture build failed"; return; }

  local marker="OPERATOR-REPORT-INTACT"
  local shape base out rc before after why=""
  for shape in exact alias symlink different; do
    printf '{"schemaVersion":2,"secrets":{"status":"scanned","findingCount":0},"m":"%s"}' "$marker" > "$T/real.json"
    rm -f "$T/link.json" "$T/fresh.json"
    base="$T/real.json"
    case "$shape" in
      exact)     out="$T/real.json" ;;
      alias)     out="$T/./real.json" ;;
      symlink)   ln -s "$T/real.json" "$T/link.json"; out="$T/link.json" ;;
      different) out="$T/fresh.json" ;;
    esac
    before=$(wc -c < "$T/real.json" | tr -d ' ')
    ( . "$REPO_ROOT/scripts/lib/adopt/adopt-tools.sh" >/dev/null 2>&1
      ADOPT_FRAMEWORK_ROOT="$REPO_ROOT"
      ADOPT_WORK="$T/w-$shape"; mkdir -p "$ADOPT_WORK"
      _adopt_secrets_scan_own "$T/adoptee" "$base" "$out" ) >/dev/null 2>&1
    rc=$?
    after=$(wc -c < "$T/real.json" 2>/dev/null | tr -d ' ')

    # THE INPUT MUST SURVIVE IN EVERY SHAPE, including the one that succeeds.
    if [ "$before" != "$after" ] || ! grep -q "$marker" "$T/real.json" 2>/dev/null; then
      why="$why [$shape: input destroyed, $before -> ${after:-0} bytes]"
      continue
    fi
    case "$shape" in
      different)
        # THE POSITIVE CONTROL. Without it a refuse-everything guard passes.
        if [ "$rc" -ne 0 ]; then why="$why [different: refused a legitimate write, rc=$rc]"; fi
        if [ "$(jq -r '.secrets.scannedBy // ""' "$T/fresh.json" 2>/dev/null)" != "adoption" ]; then
          why="$why [different: no result written]"
        fi ;;
      *)
        if [ "$rc" -eq 0 ]; then why="$why [$shape: returned 0, want a refusal]"; fi ;;
    esac
  done

  if [ -z "$why" ]; then pass "$label"; else fail_ "$label" "$why"; fi
}

t1; t2; t3; t4; t5; t6; t7; t8; t9; t10

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
