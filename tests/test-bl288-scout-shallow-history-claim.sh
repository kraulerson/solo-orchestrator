#!/usr/bin/env bash
# tests/test-bl288-scout-shallow-history-claim.sh
#
# `## BL-288:` — SCOUT CALLED A ONE-COMMIT SCAN "full-history".
#
# scripts/lib/scout/scout-secrets.sh decided the secrets scope with a single
# question — is this inside a work tree? — and answered `full-history` whenever
# it was. A shallow clone is inside a work tree and has almost no history, so
# `gitleaks git` read the commits git happened to have, found nothing in them,
# and exited 0. Nothing failed. The report said `status: scanned`,
# `scope: full-history`, `findingCount: 0`, and a consumer reading it got a
# clean bill of health over a credential sitting in a commit the scanner was
# never given. Observed in the field at 1 of 3,653 commits.
#
# This is the shape `# BL-147` already legislates against in the emitted CI
# templates — "a check that cannot run must not pass" — and it lands on the one
# section docs/adoption.md promises unconditionally: "The full secrets scan.
# History does not care what phase you land at."
#
# THE FIXTURE IS THE PROOF. Three commits: the first adds a BASE32-valid AKIA
# key, the second removes it, the third is noise. The key is therefore absent
# from the working tree and present only in history, so the ONLY way to find it
# is to walk commits. A full clone of that repository finds it. A `--depth 1`
# clone of the SAME repository cannot, and before this fix it said
# `full-history` while not finding it. S0 asserts the full clone's non-zero
# count BEFORE anything else, so a dud fixture fails loudly rather than
# certifying nothing (the WP2 suite's G0 doctrine).
#
# S3 is the case that distinguishes this fix from a warning. The honest value
# has to be MACHINE-READABLE — in the JSON, as a status word a consumer
# switches on and a commit count it can compare — because the consumer here is
# scripts/lib/adopt/, not a person.
#
# THE MUTATIONS. Three, on mirrors, each re-opening a different half:
#   MP1  delete the shallow detection            -> the scope claim returns
#   MP2  degrade the scope but keep `scanned`    -> proves the status word is
#                                                   load-bearing on its own
#   MP3  drop `commitsScanned` from the report   -> proves S3 is asserting the
#                                                   machine-readable value and
#                                                   not the prose beside it
#
# LANE: registered in tests/full-project-test-suite.sh AND in the
# .github/workflows/tests.yml `unit-shard` canonical list. This suite never
# mentions, copies or executes the scaffolder, so it is a unit-lane test
# outright and must NOT appear in
# `lint-tests-registered.sh --list | grep unit-lane-exempt`.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCOUT="$REPO_ROOT/scripts/scout.sh"
SCOUT_LIB="$REPO_ROOT/scripts/lib/scout"

PASSED=0
FAILED=0
SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip_() { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

command -v jq >/dev/null 2>&1 || {
  echo "jq is required for tests/test-bl288-scout-shallow-history-claim.sh" >&2; exit 2; }
[ -f "$SCOUT" ] || {
  echo "  [FAIL] setup — $SCOUT not found"; echo ""; echo "Results: 0 passed, 1 failed"; exit 1; }

# GITLEAKS-ABSENT IS A SKIP LOCALLY AND A FAILURE IN CI (R-WP2-1's posture,
# adopted verbatim). Every case here depends on a real scan; skipping them all
# and still exiting 0 would hand CI a green check credited with a proof that
# never ran, guarding the property whose failure mode is a leaked credential.
HAVE_GITLEAKS=0
command -v gitleaks >/dev/null 2>&1 && HAVE_GITLEAKS=1
GITLEAKS_ABSENT_IS_FATAL=0
[ -n "${CI:-}" ] && GITLEAKS_ABSENT_IS_FATAL=1

TMPS=""
cleanup() { [ -n "$TMPS" ] && rm -rf $TMPS; return 0; }
trap cleanup EXIT INT TERM
newtmp() { local d; d=$(mktemp -d); TMPS="$TMPS $d"; printf '%s\n' "$d"; }

# Assembled from halves so this source file does not itself carry a
# 20-character AKIA-shaped literal that a scanner pointed at THIS repository
# would report. BASE32-VALIDITY IS LOAD-BEARING: gitleaks' `aws-access-token`
# rule requires [A-Z2-7] for the sixteen characters after `AKIA`, so a plant
# containing a digit outside that set yields zero findings and makes the whole
# proof vacuous.
HIST_PLANT="AKIAQZ7X4M2N""PLKJ3HRD"

_num() { case "$1" in ''|null|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac; }
jqv()  { printf '%s' "$1" | jq -r "$2" 2>/dev/null; }

# _changed_lines A B — lines diff reports added or removed. A one-line
# SUBSTITUTION is 2. Asserting it stops a mutation from becoming a rewrite and
# stops a NO-OP edit from being read as a proof.
_changed_lines() {
  local n; n=$(diff "$1" "$2" 2>/dev/null | grep -c '^[<>]')
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s\n' "$n"
}

# mk_scout_copy DIR — Scout, and only Scout, at its real relative paths.
mk_scout_copy() {
  local d="$1"
  mkdir -p "$d/scripts/lib/scout" || return 1
  cp "$SCOUT" "$d/scripts/scout.sh" || return 1
  cp "$SCOUT_LIB"/*.sh "$d/scripts/lib/scout/" || return 1
  chmod +x "$d/scripts/scout.sh"
}

# ── The fixture ─────────────────────────────────────────────────────────────
#
# KEPT TO THREE COMMITS ON PURPOSE. gitleaks walks every commit it is given, so
# a fixture with real history turns this suite into a minute of scanning for a
# property that one removed commit already proves. `file://` is required for
# `--depth` — git silently ignores depth on a plain local path clone and
# hardlinks the whole object store instead, which would make the shallow arm a
# second full clone and this entire suite vacuously green.
mk_origin() {
  local d="$1"
  ( cd "$d" && unset GITHUB_BASE_REF
    git init -q -b main . \
      && git config user.email t@t.local \
      && git config user.name T \
      && printf 'aws_key = %s\n' "$HIST_PLANT" > config.ini \
      && git add -A && git commit -q -m "add config" \
      && printf 'aws_key = ROTATED\n' > config.ini \
      && git add -A && git commit -q -m "rotate the key" \
      && printf 'hello\n' > README.md \
      && git add -A && git commit -q -m "add a readme" ) >/dev/null 2>&1
}

# scout_json SCOUT_PATH ROOT — the JSON report, or empty on a non-zero exit.
scout_json() {
  local s="$1" r="$2" out rc
  out=$(bash "$s" --root "$r" 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] || { printf ''; return 1; }
  printf '%s' "$out"
}

if [ "$HAVE_GITLEAKS" -eq 0 ]; then
  if [ "$GITLEAKS_ABSENT_IS_FATAL" -eq 1 ]; then
    fail_ "setup" "gitleaks is not installed and CI is set — every case here needs a real scan; a green check credited with a proof that never ran is the outcome this arm exists to prevent"
  else
    skip_ "the whole suite" "gitleaks not installed (install it to run BL-288's proofs locally)"
  fi
else
  D="$(newtmp)"
  mkdir -p "$D/src"
  mk_origin "$D/src"
  ( cd "$D" && git clone -q "file://$D/src" full \
             && git clone -q --depth 1 "file://$D/src" shallow ) >/dev/null 2>&1

  full_commits=$(git -C "$D/full" rev-list --count HEAD 2>/dev/null)
  shal_commits=$(git -C "$D/shallow" rev-list --count HEAD 2>/dev/null)
  wt_hits=$(grep -rl -- "$HIST_PLANT" "$D/full" --exclude-dir=.git 2>/dev/null | grep -c '')

  # ── S0: the fixture is real, and the plant is history-only ────────────────
  # Asserted FIRST. Everything below is a comparison between two scans of the
  # same repository, and a fixture that plants nothing findable makes every one
  # of those comparisons true for the wrong reason.
  full_json=$(scout_json "$SCOUT" "$D/full")
  full_fc=$(_num "$(jqv "$full_json" '.secrets.findingCount')")
  if [ "$(_num "$full_commits")" -eq 3 ] && [ "$(_num "$shal_commits")" -eq 1 ] \
     && [ "${wt_hits:-1}" -eq 0 ] && [ "$full_fc" -ge 1 ]; then
    pass "S0: the fixture is sound — 3 commits in the full clone, 1 in the --depth 1 clone, the plant absent from the working tree and found $full_fc time(s) by the full scan (so only a history walk can find it)"
  else
    fail_ "S0" "full_commits=$full_commits (want 3) shallow_commits=$shal_commits (want 1) working-tree-files-with-plant=$wt_hits (want 0) full findingCount=$full_fc (want >=1)"
  fi

  # ── S1: a full clone still reports full-history ───────────────────────────
  # The regression guard. A fix that made every repository "partial" would
  # satisfy S2 and S3 and destroy the section.
  s1_scope=$(jqv "$full_json" '.secrets.scope')
  s1_status=$(jqv "$full_json" '.secrets.status')
  s1_commits=$(jqv "$full_json" '.secrets.commitsScanned')
  if [ "$s1_scope" = "full-history" ] && [ "$s1_status" = "scanned" ] \
     && [ "$s1_commits" = "3" ]; then
    pass "S1: a full clone reports scope=full-history, status=scanned, commitsScanned=3 — the claim is unchanged where it is true"
  else
    fail_ "S1" "scope='$s1_scope' (want full-history) status='$s1_status' (want scanned) commitsScanned='$s1_commits' (want 3)"
  fi

  # ── S2: a --depth 1 clone does NOT report full-history ────────────────────
  # The defect, stated as the weakest assertion that excludes it. Deliberately
  # NOT pinned to a particular replacement value — S3 does that — so that this
  # case reads as the bug and S3 reads as the design.
  shal_json=$(scout_json "$SCOUT" "$D/shallow")
  s2_scope=$(jqv "$shal_json" '.secrets.scope')
  s2_status=$(jqv "$shal_json" '.secrets.status')
  s2_fc=$(_num "$(jqv "$shal_json" '.secrets.findingCount')")
  if [ -n "$shal_json" ] && [ "$s2_scope" != "full-history" ] && [ "$s2_status" != "scanned" ]; then
    pass "S2: a --depth 1 clone of the same repository does NOT claim full-history and does NOT claim a completed scan (scope='$s2_scope' status='$s2_status', findingCount=$s2_fc against the full clone's $full_fc)"
  else
    fail_ "S2" "the shallow clone reported scope='$s2_scope' status='$s2_status' findingCount=$s2_fc while the full clone found $full_fc — a clean bill of health over a credential the scanner was never given"
  fi

  # ── S3: the honest value is MACHINE-READABLE, not a human-facing warning ──
  # A warning on stderr or a sentence inside `note` does not reach
  # scripts/lib/adopt/, which is the consumer that matters. Three demands:
  # a scope enum a reader can compare, a status word distinct from `scanned`
  # (both of adoption's readers spell their switch `!= "scanned"`), and the
  # depth as a JSON NUMBER rather than a string buried in prose.
  s3_commits=$(jqv "$shal_json" '.secrets.commitsScanned')
  s3_commits_type=$(printf '%s' "$shal_json" | jq -r '.secrets.commitsScanned | type' 2>/dev/null)
  s3_note=$(jqv "$shal_json" '.secrets.note')
  if [ "$s2_scope" = "shallow-history" ] && [ "$s2_status" = "scanned-partial" ] \
     && [ "$s3_commits" = "1" ] && [ "$s3_commits_type" = "number" ] \
     && [ -n "$s3_note" ] && [ "$s3_note" != "null" ]; then
    pass "S3: the honest value is machine-readable — scope='shallow-history', status='scanned-partial', commitsScanned=1 as a JSON number, and a note beside them rather than instead of them"
  else
    fail_ "S3" "scope='$s2_scope' (want shallow-history) status='$s2_status' (want scanned-partial) commitsScanned='$s3_commits' type='$s3_commits_type' (want 1/number) note='$(printf '%.60s' "$s3_note")'"
  fi

  # ── S4: the markdown half stops claiming every commit ─────────────────────
  # The JSON is what adoption reads; the markdown is what the operator reads,
  # and before this fix it printed "every commit in this project" beneath a
  # one-commit scan. Both halves carried the same false claim.
  S4OUT="$(newtmp)/md"
  mkdir -p "$S4OUT"
  bash "$SCOUT" --root "$D/shallow" --markdown --out "$S4OUT" >/dev/null 2>&1
  if [ -f "$S4OUT/scout-report.md" ]; then
    # The positive half is scoped to the SECRETS heading, not to the whole
    # document: `shallow` already appears elsewhere (§7.2's hook descriptions
    # use the word), so an unscoped `grep -i shallow` is true on an unfixed
    # report and would let this case pass for the wrong reason. Measured on
    # unmodified main: 2 hits, neither of them in this section.
    sec_md=$(awk '/^## Secrets in/{f=1} f && /^## /&&!/^## Secrets in/{f=0} f' "$S4OUT/scout-report.md")
    if ! grep -q 'every commit in this project' "$S4OUT/scout-report.md" \
       && printf '%s' "$sec_md" | grep -qi 'shallow'; then
      pass "S4: the human-readable report does not tell the operator every commit was read, and its secrets section says shallow instead"
    else
      fail_ "S4" "markdown claims-every-commit=$(grep -c 'every commit in this project' "$S4OUT/scout-report.md") secrets-section-says-shallow=$(printf '%s' "$sec_md" | grep -ci 'shallow')"
    fi
  else
    fail_ "S4" "no markdown report was written to $S4OUT"
  fi

  # ── S5: a non-repository still degrades to working-tree-only ──────────────
  # §6.1's existing arm, unchanged. The shallow arm sits beside it, not on top
  # of it, and `commitsScanned` is null where the question does not apply.
  NG="$(newtmp)"
  printf 'aws_key = %s\n' "$HIST_PLANT" > "$NG/config.ini"
  ng_json=$(scout_json "$SCOUT" "$NG")
  ng_scope=$(jqv "$ng_json" '.secrets.scope')
  ng_status=$(jqv "$ng_json" '.secrets.status')
  ng_commits=$(jqv "$ng_json" '.secrets.commitsScanned')
  if [ "$ng_scope" = "working-tree-only" ] && [ "$ng_status" = "scanned" ] \
     && [ "$ng_commits" = "null" ]; then
    pass "S5: a non-repository is unaffected — working-tree-only, scanned, commitsScanned=null"
  else
    fail_ "S5" "scope='$ng_scope' status='$ng_status' commitsScanned='$ng_commits'"
  fi

  # ── S6: the schema version carries the widened enumerations ───────────────
  # `secrets.status` gained a fourth word and `secrets.scope` a third. A reader
  # pinned to 1 is entitled to the old enumerations, so the number moves.
  s6_sv=$(jqv "$shal_json" '.schemaVersion')
  s6_sv_full=$(jqv "$full_json" '.schemaVersion')
  if [ "$s6_sv" = "2" ] && [ "$s6_sv_full" = "2" ]; then
    pass "S6: schemaVersion is 2 on both reports — the widened status and scope enumerations are announced, not slipped in"
  else
    fail_ "S6" "shallow schemaVersion='$s6_sv' full schemaVersion='$s6_sv_full' (want 2)"
  fi

  # ── MP1 (MUTATION): delete the shallow detection ──────────────────────────
  # Restores the single-question scope on a mirror. S2 and S3 must both
  # re-open; if they do not, they are passing for some other reason.
  MP1="$(newtmp)/fw"
  if ! mk_scout_copy "$MP1"; then
    fail_ "MP1 setup" "could not mirror Scout"
  else
    tgt="$MP1/scripts/lib/scout/scout-secrets.sh"
    before="$(mktemp)"; cp "$tgt" "$before"
    if [ "$(grep -c '^      _scope="shallow-history"$' "$before")" -ne 1 ]; then
      fail_ "MP1 setup" "the shallow-history assignment is not a unique single line"
    else
      # SUBSTITUTED, not deleted. Deleting the line empties the `if` body and
      # `bash -n` rejects the file, which would make this a syntax-error proof
      # rather than a behaviour proof. Re-pointing it at the old value is the
      # exact pre-fix behaviour, in one line, still valid bash.
      sed 's/^      _scope="shallow-history"$/      _scope="full-history"/' "$before" > "$tgt"
      if ! bash -n "$tgt" 2>/dev/null || [ "$(_changed_lines "$before" "$tgt")" -ne 2 ]; then
        fail_ "MP1 setup" "the mutation did not apply cleanly ($(_changed_lines "$before" "$tgt") changed lines, want 2)"
      else
        m1=$(scout_json "$MP1/scripts/scout.sh" "$D/shallow")
        m1_scope=$(jqv "$m1" '.secrets.scope')
        m1_status=$(jqv "$m1" '.secrets.status')
        if [ "$m1_scope" = "full-history" ] && [ "$m1_status" = "scanned" ]; then
          pass "MP1 (MUTATION) — with the detection removed the shallow clone is back to scope=full-history / status=scanned and 0 findings: S2 and S3 are what stop it"
        else
          fail_ "MP1 (MUTATION)" "removing the detection changed nothing (scope='$m1_scope' status='$m1_status') — S2/S3 may be passing for another reason"
        fi
      fi
    fi
  fi

  # ── MP2 (MUTATION): degrade the scope, keep the status ────────────────────
  # The half-fix a reviewer would most plausibly accept: an honest `scope` with
  # `status: scanned` beside it. Both of adoption's readers switch on status
  # alone (`adopt-tools.sh` `_adopt_rescan_secrets`, `adopt-stubs.sh`
  # `adopt_stub_secrets_disposition`), so this mutant keeps the false clean
  # bill of health for every consumer that matters while looking fixed.
  MP2="$(newtmp)/fw"
  if ! mk_scout_copy "$MP2"; then
    fail_ "MP2 setup" "could not mirror Scout"
  else
    tgt2="$MP2/scripts/lib/scout/scout-secrets.sh"
    before2="$(mktemp)"; cp "$tgt2" "$before2"
    if [ "$(grep -c "^    printf 'scanned-partial" "$before2")" -ne 1 ]; then
      fail_ "MP2 setup" "the scanned-partial write is not a unique single line"
    else
      sed "s/^    printf 'scanned-partial/    printf 'scanned/" "$before2" > "$tgt2"
      if ! bash -n "$tgt2" 2>/dev/null || [ "$(_changed_lines "$before2" "$tgt2")" -ne 2 ]; then
        fail_ "MP2 setup" "the mutation did not apply cleanly ($(_changed_lines "$before2" "$tgt2") changed lines, want 2)"
      else
        m2=$(scout_json "$MP2/scripts/scout.sh" "$D/shallow")
        m2_scope=$(jqv "$m2" '.secrets.scope')
        m2_status=$(jqv "$m2" '.secrets.status')
        if [ "$m2_scope" = "shallow-history" ] && [ "$m2_status" = "scanned" ]; then
          pass "MP2 (MUTATION) — an honest scope with status=scanned beside it still reads as a completed scan to every consumer that switches on status: S3's status demand is what stops it"
        else
          fail_ "MP2 (MUTATION)" "scope='$m2_scope' status='$m2_status' — the status word may not be independently asserted"
        fi
      fi
    fi
  fi

  # ── MP3 (MUTATION): drop commitsScanned from the report ───────────────────
  # Leaves the prose and removes the number. Proves S3 is asserting a value a
  # script can read and compare, not the sentence printed next to it.
  MP3="$(newtmp)/fw"
  if ! mk_scout_copy "$MP3"; then
    fail_ "MP3 setup" "could not mirror Scout"
  else
    tgt3="$MP3/scripts/lib/scout/scout-report.sh"
    before3="$(mktemp)"; cp "$tgt3" "$before3"
    if [ "$(grep -c '"commitsScanned": %s' "$before3")" -ne 1 ]; then
      fail_ "MP3 setup" "the commitsScanned emission is not a unique single line"
    else
      grep -v '"commitsScanned": %s' "$before3" > "$tgt3"
      if ! bash -n "$tgt3" 2>/dev/null || [ "$(_changed_lines "$before3" "$tgt3")" -ne 1 ]; then
        fail_ "MP3 setup" "the mutation did not apply cleanly"
      else
        m3=$(scout_json "$MP3/scripts/scout.sh" "$D/shallow")
        m3_note=$(jqv "$m3" '.secrets.note')
        m3_commits=$(printf '%s' "$m3" | jq -r '.secrets | has("commitsScanned")' 2>/dev/null)
        if [ "$m3_commits" = "false" ] && [ -n "$m3_note" ] && [ "$m3_note" != "null" ]; then
          pass "MP3 (MUTATION) — with the number gone the warning prose survives untouched, and only S3's machine-readable demand notices"
        else
          fail_ "MP3 (MUTATION)" "has(commitsScanned)='$m3_commits' note='$(printf '%.40s' "$m3_note")' — the field may not be independently asserted"
        fi
      fi
    fi
  fi
fi

# ── S7 / S8: adoption's SECOND reader ───────────────────────────────────────
# The fix's own comment says "both of adoption's readers spell that switch
# `[ "$status" != "scanned" ]`", and a first cut updated one of them. The other
# is `_adopt_rescan_secrets` (scripts/lib/adopt/adopt-tools.sh), where the same
# spelling put `scanned-partial` on the WRONG side of the guard: a tool had
# already looked, and the run re-walked the whole history anyway — the exact
# cost that function's own doc-comment says the guard exists to avoid.
echo ""
echo "S7 / S8: adoption's re-scan reader handles the fourth status word"

ADOPT_TOOLS="$REPO_ROOT/scripts/lib/adopt/adopt-tools.sh"
ADOPT_CORE="$REPO_ROOT/scripts/lib/adopt/adopt-core.sh"

# drive_rescan <status> → RESCAN_OUT, RESCAN_RC
# ADOPT_FRAMEWORK_ROOT is pointed at an EMPTY directory on purpose: past the
# guard the function hits its missing-Scout arm and says so, so "did the guard
# return early" is observable as the presence or absence of that sentence, with
# no scanner ever running. Hermetic, and fast.
drive_rescan() {
  local status="$1" d
  d="$(newtmp)"
  mkdir -p "$d/proj" "$d/emptyfw"
  printf '{"secrets":{"status":"%s"}}\n' "$status" > "$d/report.json"
  # THE REDIRECTION IS ON THE COMMAND, AND THAT IS LOAD-BEARING. A first cut
  # wrote `2>&1` on its own line before the closing paren, where it is a NULL
  # COMMAND rather than a redirection — and being last, its status is what `$?`
  # captures, so RESCAN_RC was ALWAYS 0. S7's "no re-scan, rc=0" was then
  # stating a measurement it had not taken: changing the guard to `return 7`
  # left the suite GREEN while the pass line still claimed rc=0. Measured:
  # `f7() { return 7; }` in that shape yields 0; on the command, 7. This is the
  # `## BL-256:` unearned-receipt class, in a test rather than in a gate.
  RESCAN_OUT="$(
    # shellcheck source=/dev/null
    . "$ADOPT_CORE"  >/dev/null 2>&1 || exit 91
    # shellcheck source=/dev/null
    . "$ADOPT_TOOLS" >/dev/null 2>&1 || exit 92
    ADOPT_FRAMEWORK_ROOT="$d/emptyfw"
    _adopt_rescan_secrets "$d/proj" "$d/report.json" 2>&1
  )"
  RESCAN_RC=$?
  return 0
}

if [ ! -f "$ADOPT_TOOLS" ] || [ ! -f "$ADOPT_CORE" ]; then
  fail_ "S7 setup" "adopt-tools.sh / adopt-core.sh not found — the reader this case is about is missing"
else
  # CONTROL FIRST. A status nobody looked at MUST get past the guard, or S7
  # below proves nothing: an early return for every input would pass it.
  drive_rescan "tool-unavailable"
  if [ "$RESCAN_RC" -ge 91 ]; then
    fail_ "S7 (control)" "could not source the adopt libraries (rc=$RESCAN_RC)"
  elif printf '%s' "$RESCAN_OUT" | grep -q "missing part of Scout"; then
    pass "S7 (control) — 'tool-unavailable' still gets PAST the guard and attempts a re-scan"

    drive_rescan "scanned-partial"
    if printf '%s' "$RESCAN_OUT" | grep -q "missing part of Scout"; then
      fail_ "S7" "'scanned-partial' was re-scanned — a tool had already looked, and this pays a full history walk to learn the same thing in the same clone"
    elif [ "$RESCAN_RC" -ne 0 ]; then
      fail_ "S7" "'scanned-partial' returned rc=$RESCAN_RC, want 0"
    else
      pass "S7 — 'scanned-partial' is on the 'somebody looked' side of the guard: no re-scan, rc=0"
    fi
  else
    fail_ "S7 (control)" "'tool-unavailable' did not reach the re-scan attempt; got: $(printf '%s' "$RESCAN_OUT" | head -1)"
  fi

  # S8 — SOURCE-LEVEL, and labelled. The arm is reachable only by a re-scan
  # that RETURNS partial (tool-unavailable -> scanner installed -> shallow
  # clone), which needs a real scanner and a real shallow clone inside an
  # adoption run. The assertion is scoped to the `# BL-242-RESCAN-HONEST` case
  # block, so a mention of the word anywhere else in the file cannot satisfy it,
  # and the block must be FOUND or the case fails rather than passing by absence.
  rescan_case="$(awk '/# BL-242-RESCAN-HONEST/{f=1} f{print} f&&/^    esac$/{exit}' "$ADOPT_TOOLS")"
  if [ -z "$rescan_case" ]; then
    fail_ "S8" "could not locate the # BL-242-RESCAN-HONEST case block — this case would otherwise pass by absence"
  elif ! printf '%s' "$rescan_case" | grep -q '^      scanned-partial)'; then
    fail_ "S8" "the re-scan status enumeration has no 'scanned-partial' arm — a re-scan that comes back partial falls through to the generic 'its status is ...' line"
  elif ! printf '%s' "$rescan_case" | grep -qi 'unshallow'; then
    fail_ "S8" "the 'scanned-partial' arm does not name the operator's remedy (git fetch --unshallow)"
  else
    pass "S8 (source-level: the re-scan enumeration has a 'scanned-partial' arm that names the remedy)"
  fi
fi

# ── S9: the REMEDY WE PRINT MUST BE RUNNABLE AS PRINTED ─────────────────────
# The remedy is `git remote set-branches origin '*' && git fetch --unshallow`,
# and the glob MUST reach the operator quoted. It is emitted from five sites in
# three different quoting contexts — a single-quoted `printf` in
# scout-report.sh, and double-quoted arguments in scout-secrets.sh,
# adopt-stubs.sh and adopt-tools.sh — so the spelling that is safe in one is
# broken in the others. Both mistakes were made here in turn: `"*"` inside a
# double-quoted string terminates it, and `'*'` inside a single-quoted string
# terminates that, and in BOTH cases the quotes are stripped from the rendered
# text and the operator is told to run a bare `origin *`, which globs against
# whatever is in their working directory.
#
# `bash -n` passes on every one of those variants. Only rendering catches it,
# which is why this case renders rather than greps the source.
echo ""
echo "S9: every printed remedy is runnable as printed"

_s9_render() {  # <file> <lineno>
  local line d out
  line="$(sed -n "${2}p" "$1")"
  d="$(newtmp)"
  out="$( cd "$d" && touch alpha.txt beta.txt && \
          adopt_note() { printf '%s\n' "$*"; } && _commits=7 && \
          eval "${line%;;}" 2>&1 | head -1 )"
  printf '%s' "$out"
}

# LOCATE EACH REMEDY BY CONTENT, NOT LINE NUMBER. A first cut hardcoded
# `adopt-tools.sh:508` and the other three; an unrelated change above the
# remedy (BL-225's fingerprint block) moved it to 526, `sed -n 508p` rendered a
# different line, and this case reported "(no-remedy)" on correct code. That is
# the `file:line` trap CLAUDE.md § CITATION RULE forbids, one level down.
# Find the ONE executable line per file that prints the remedy — the arm that
# starts with adopt_note/scout_ and carries `set-branches` — and render that.
s9_bad=""; s9_seen=0
# `adopt-stubs.sh` was this list's first member until 2026-09-19. WP10b/2
# retired `adopt_stub_secrets_disposition`, and the remedy it printed moved to
# `_adopt_secrets_unshallow_remedy` in `adopt-secrets.sh` — the same two
# commands, spelled once, now reachable from both `scanned-partial` arms of
# §6.1's table. The SITE moved; the count of sites did not.
for _s9f in scripts/lib/adopt/adopt-secrets.sh scripts/lib/adopt/adopt-tools.sh \
            scripts/lib/scout/scout-secrets.sh scripts/lib/scout/scout-report.sh; do
  [ -f "$REPO_ROOT/$_s9f" ] || { s9_bad="$s9_bad $_s9f(missing)"; continue; }
  _s9l="$(grep -n 'set-branches' "$REPO_ROOT/$_s9f" | grep -vE '^[0-9]+:[[:space:]]*#' | head -1 | cut -d: -f1)"
  [ -n "$_s9l" ] || { s9_bad="$s9_bad $_s9f(no-remedy-line)"; continue; }
  _s9out="$(cd "$REPO_ROOT" && _s9_render "$_s9f" "$_s9l")"
  case "$_s9out" in
    *"set-branches origin '*'"*) s9_seen=$((s9_seen + 1)) ;;
    *"set-branches origin"*)     s9_bad="$s9_bad $_s9f(unquoted)" ;;
    *)                           s9_bad="$s9_bad $_s9f(no-remedy)" ;;
  esac
done
# docs/scout.md is prose, not shell — grep it directly.
if grep -q "set-branches origin '\*'" "$REPO_ROOT/docs/scout.md" 2>/dev/null; then
  s9_seen=$((s9_seen + 1))
else
  s9_bad="$s9_bad docs/scout.md"
fi

if [ -n "$s9_bad" ]; then
  fail_ "S9" "the printed remedy is not runnable as printed at:$s9_bad — a bare \`origin *\` globs in the operator's shell"
elif [ "$s9_seen" -ne 5 ]; then
  fail_ "S9" "expected 5 remedy sites, rendered $s9_seen — a site was moved or removed and this case would pass by absence"
else
  pass "S9 — all 5 printed remedies render the glob QUOTED (\`origin '*'\`), across three different quoting contexts"
fi

# ── S10: findings from the commits a shallow clone CAN read are EMITTED ─────
# The fix claims "scanned-partial findings are REAL … so they are emitted rather
# than nulled" — and nothing above tests it, because the only shallow fixture
# plants its secret in the part a --depth 1 clone cannot reach (findingCount is
# 0 either way). A reviewer narrowed `produced` back to `scanned` alone and this
# suite stayed 14/0 while two live credentials vanished from the report and the
# rotate-first advice with them. This fixture plants the secret in the TIP
# commit, which a depth-1 clone DOES read.
echo "S10: a secret in the commit a shallow clone CAN read is reported, not nulled"
D2="$(newtmp)"; mkdir -p "$D2/src"
( cd "$D2/src" && unset GITHUB_BASE_REF
  git init -q -b main . && git config user.email t@t.local && git config user.name T \
    && printf 'hello\n' > README.md && git add -A && git commit -q -m "add a readme" \
    && printf 'more\n' >> README.md && git add -A && git commit -q -m "more readme" \
    && printf 'aws_key = %s\n' "$HIST_PLANT" > config.ini && git add -A && git commit -q -m "add config (tip)" ) >/dev/null 2>&1
( cd "$D2" && git clone -q --depth 1 "file://$D2/src" shallow ) >/dev/null 2>&1
tip_json=$(scout_json "$SCOUT" "$D2/shallow")
tip_status=$(jqv "$tip_json" '.secrets.status')
tip_fc=$(_num "$(jqv "$tip_json" '.secrets.findingCount')")
tip_n=$(printf '%s' "$tip_json" | jq -r '.secrets.findings | length' 2>/dev/null)
tip_hr=$(printf '%s' "$tip_json" | jq -r '.secrets.historyRewrite | type' 2>/dev/null)
if [ "$tip_status" = "scanned-partial" ] && [ "${tip_fc:-0}" -ge 1 ] && [ "${tip_n:-0}" -ge 1 ] && [ "$tip_hr" != "null" ]; then
  pass "S10 — --depth 1 clone with the plant in its one reachable commit: status=scanned-partial, findingCount=$tip_fc, findings=$tip_n, historyRewrite=$tip_hr"
else
  fail_ "S10" "shallow-reachable finding was dropped: status=$tip_status findingCount=${tip_fc:-?} findings=${tip_n:-?} historyRewrite=${tip_hr:-?} (want scanned-partial / >=1 / >=1 / non-null)"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed${SKIPPED:+, $SKIPPED skipped}"
[ "$FAILED" -eq 0 ] && exit 0
exit 1
