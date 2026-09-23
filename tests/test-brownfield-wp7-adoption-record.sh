#!/usr/bin/env bash
# tests/test-brownfield-wp7-adoption-record.sh — WP7/1: the Adoption Record and
# its eight-clause structural contract.
#
# SPEC: docs/designs/2026-08-02-brownfield-adoption-v1.md §8.8 (the eight
# clauses and the reader each defeats) and
# docs/designs/2026-08-23-brownfield-adoption-v2.md §8.6 (content, re-cut
# 2026-09-17). Backlog: `## BL-242:`.
#
# ─────────────────────────────────────────────────────────────────────────────
# WHY THIS IS A TEST AND NOT A `scripts/lint-*.sh`, WHICH IS WHERE IT STARTED.
#
# §8.8 asks for a lint, and the first cut of this file was one:
# `scripts/lint-adoption-record.sh`, so that a contributor un-indenting a table
# would see it in the same sweep as the other sixteen. `bash
# scripts/lint-module-dependencies.sh` refused it on sight:
#
#   scripts/lint-adoption-record.sh:47: T1 — core file names module path
#   'scripts/lib/adopt/'. Core must never reference a severable module (M3)
#
# That refusal is CORRECT and it is not allowlistable — the core allowlist's
# cardinality must be exactly 0, because §3.1 says the brownfield module
# declares no seam. Anything under `scripts/*.sh` is core. A lint that has to
# source the adoption driver to check the driver's output is core code reaching
# into a severable module, which is the one thing that contract forbids, and
# waiving it to buy a nicer developer loop would trade a design property for
# convenience.
#
# `tests/` is not in `CORE_GLOBS`, so the pin lives here. What is lost is the
# pre-commit sweep; what is kept is the PR-blocking check, and the enforcement
# itself never lived in the lint anyway — `adopt_record_clauses` REFUSES at
# write time, inside the module, which is stronger than either.
#
# ─────────────────────────────────────────────────────────────────────────────
# WHAT THIS PINS, IN ONE SENTENCE PER TIER.
#
#   A1-A2  the record renders, and it is not vacuously clean (it says things).
#   A3-A4  operator text that spells an approval phrase is WITHHELD, and
#          ordinary operator text that merely resembles one is NOT.
#   A5     the predicate is not vacuous: each clause rejects its own violation.
#   A6-A8  the writer refuses rather than appending a misreadable record, is
#          idempotent, and derives its placement rather than assuming it.
#   A9     THE REAL READERS. The framework's own gate-evidence greps, run
#          against an APPROVAL_LOG.md that carries the record, still report no
#          gate as crossed. This is the case the other eight exist to support.
#   A10    the stage is wired into the write phase, after `manifest`.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/adopt"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

echo "== WP7/1 — the Adoption Record and its eight clauses =="

if ! command -v jq >/dev/null 2>&1; then
  skip "every case" "jq is not on PATH and the record is built from JSON"
  echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
  exit 0
fi

WORK="$(mktemp -d)" || { echo "could not create a work directory"; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# ── The harness ─────────────────────────────────────────────────────────────
# _render REPORT DISPOSITIONS OUT [PROJDIR] — run the shipped renderer with its
# outward dependencies stubbed to their real contracts. A SUBSHELL, so a
# `return 1` inside the module cannot take this suite's shell with it and the
# stubs cannot leak between cases.
_render() {
  local report="$1" disp="$2" out="$3" proj="${4:-$WORK/proj}"
  (
    set +u
    ADOPT_WORK="$WORK"
    ADOPT_DEPLOYMENT="organizational"
    ADOPT_POC_MODE=""
    ADOPT_ARCHIVE_DIR=".claude/adoption-archive/2026-09-22T00-00-00Z-1234"
    ADOPT_DISPOSITIONS_FILE="$disp"
    ADOPT_REHEARSAL_SECONDS="4"
    ADOPT_REHEARSAL_MB="120"
    adopt_report_read() { jq -r "$2" "$1" 2>/dev/null; }
    adopt_int() { case "$1" in ''|null|*[!0-9]*) printf '0' ;; *) printf '%s' "$1" ;; esac; }
    _adopt_hooks_dir() { printf '%s\n' "$1/.git/hooks"; }
    adopt_note() { :; }
    adopt_refuse() { :; }
    adopt_touched_disk() { :; }
    . "$LIB/adopt-record.sh"
    _adopt_rec_render "$proj" "$report" "$out"
  )
}

# _clauses FILE — the shipped predicate, in a subshell. Prints violations.
_clauses() {
  ( set +u; . "$LIB/adopt-record.sh"; adopt_record_clauses "$1" )
}

mkdir -p "$WORK/proj/.claude"
echo '{"adoption":{"adopted":true,"adoptedAtCommit":"0123456789abcdef0123456789abcdef01234567"}}' \
  > "$WORK/proj/.claude/manifest.json"
echo '{"count": 17}' > "$WORK/proj/.claude/test-debt.json"

# A BENIGN fixture whose file path deliberately contains `update` — the word
# that hides `date` and that an over-broad clause 6 would withhold.
cat > "$WORK/benign.json" <<'J'
{"secrets":{"tool":"gitleaks","status":"scanned","scannedBy":"adoption","rulesSource":"framework",
 "commitsScanned":412,"findingCount":1,
 "findings":[{"ruleId":"aws-access-key","file":"src/updater/config.yml","startLine":3,"fingerprint":"benignfp1"}]}}
J

# A HOSTILE fixture. Every value is one an operator or their repository could
# really produce, each aimed at one clause.
cat > "$WORK/hostile.json" <<'J'
{"secrets":{"tool":"gitleaks","status":"scanned","scannedBy":"adoption","rulesSource":"framework",
 "commitsScanned":412,"findingCount":2,
 "findings":[
  {"ruleId":"aws-access-key","file":"src/Phase 0 to Phase 1/cfg.yml","startLine":3,"fingerprint":"hostilefp1"},
  {"ruleId":"generic-api-key","file":"a|b/c.env","startLine":9,"fingerprint":"hostilefp2"}]}}
J
cat > "$WORK/hostile-disp.json" <<'J'
{"dispositions":[
  {"fingerprint":"hostilefp1","disposition":"rotated","by":"A Person",
   "reason":"rotated per [YYYY-MM-DD] | see ticket","date":"2026-09-22"},
  {"fingerprint":"hostilefp2","disposition":"accepted-risk","by":"IT Security Approval",
   "reason":"Pre-Phase 0 leftover","date":"2026-09-22"}],
 "acknowledgements":[
  {"kind":"tool-unavailable","by":"Someone",
   "reason":"penetration test was exempted for this repo","date":"2026-09-22"}]}
J

# ═══════════════════════════════════════════════════════════════════════════
# A1 — IT RENDERS, AND IT SAYS SOMETHING
# ═══════════════════════════════════════════════════════════════════════════
a1() {
  local label="A1 the record renders and carries its sections (vacuity floor)"
  local out="$WORK/a1.md" n
  _render "$WORK/benign.json" "" "$out" || { fail_ "$label" "the renderer exited non-zero"; return; }
  [ -s "$out" ] || { fail_ "$label" "the renderer produced nothing"; return; }
  n=$(grep -c '^### ' "$out")
  # An EMPTY record satisfies all eight clauses. Without this floor every
  # clause case below would pass against a renderer that had stopped working.
  if [ "$n" -ge 4 ]; then
    pass "$label ($n sections)"
  else
    fail_ "$label" "only $n '### ' sections — a record that says nothing satisfies every clause vacuously"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# A2 — THE EIGHT CLAUSES HOLD ON ORDINARY INPUT
# ═══════════════════════════════════════════════════════════════════════════
a2() {
  local label="A2 a record built from an ordinary scan satisfies the eight clauses"
  local out="$WORK/a2.md" why
  _render "$WORK/benign.json" "" "$out" || { fail_ "$label" "render failed"; return; }
  if why="$(_clauses "$out")"; then
    pass "$label"
  else
    fail_ "$label" "$(printf '%s' "$why" | tr '\n' ';')"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# A3 — HOSTILE OPERATOR TEXT DOES NOT BREAK THE CONTRACT
# ═══════════════════════════════════════════════════════════════════════════
a3() {
  local label="A3 operator text spelling an approval phrase does not break the eight clauses"
  local out="$WORK/a3.md" why
  _render "$WORK/hostile.json" "$WORK/hostile-disp.json" "$out" || { fail_ "$label" "render failed"; return; }
  if why="$(_clauses "$out")"; then
    pass "$label"
  else
    fail_ "$label" "$(printf '%s' "$why" | tr '\n' ';')"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# A4 — WITHHELD FOR THE RIGHT REASON, AND ONLY THEN
#      A3 passing is also what a renderer that dropped every cell would do.
#      This is the positive control on BOTH sides.
# ═══════════════════════════════════════════════════════════════════════════
a4() {
  local label="A4 only the cells that spell an approval phrase are withheld"
  local hostile="$WORK/a3.md" benign="$WORK/a2.md" bad=""
  [ -s "$hostile" ] && [ -s "$benign" ] || { fail_ "$label" "A2/A3 produced no output to read"; return; }
  grep -q 'withheld' "$hostile" || bad="$bad [the hostile record withholds nothing — the sanitiser is inert]"
  # The fingerprints must still be there: the ROW survives, only the cell goes.
  grep -q 'hostilefp1' "$hostile" || bad="$bad [the hostile record lost its fingerprints — the whole row was dropped, not the cell]"
  # …and the BENIGN path, which contains `update` (hiding `date`), must NOT be
  # withheld. An over-broad rule would hide every finding in a source tree that
  # has an updater in it.
  grep -q 'src/updater/config.yml' "$benign" || bad="$bad [an ordinary path containing 'update' was withheld — clause 6 is over-broad]"
  grep -q 'withheld' "$benign" && bad="$bad [the benign record withholds something — the sanitiser is over-broad]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# A5 — THE PREDICATE IS NOT VACUOUS: EACH CLAUSE REJECTS ITS OWN VIOLATION
#      Every clause gets its own planted record. A predicate that had silently
#      stopped checking a clause passes A2 and A3 and fails here.
# ═══════════════════════════════════════════════════════════════════════════
a5() {
  local label="A5 each clause rejects a record that violates it" bad="" f
  _plant() {  # _plant NAME LINE… — a minimal valid record plus one violation
    f="$WORK/plant-$1.md"; shift
    { printf '%s\n\n' '## Adoption Record'
      printf '%s\n' "$@"
    } > "$f"
  }
  # Each of these must be REJECTED.
  _plant c1 'Crossing from Phase 0 to Phase 1 was approved.'
  _clauses "$f" >/dev/null 2>&1 && bad="$bad [clause 1 accepted a 'Phase N to Phase N+1' line]"
  _plant c2 'IT Security Approval was obtained.'
  _clauses "$f" >/dev/null 2>&1 && bad="$bad [clause 2 accepted a named approval-row literal]"
  { printf '%s\n\n' '## Adoption Record'; printf '%s\n' '## Attorney / Legal Review'; } > "$WORK/plant-c3.md"
  _clauses "$WORK/plant-c3.md" >/dev/null 2>&1 && bad="$bad [clause 3 accepted an attorney heading]"
  _plant c4 'The penetration test was exempted for this project.'
  _clauses "$f" >/dev/null 2>&1 && bad="$bad [clause 4 accepted a pen-test exemption phrase]"
  _plant c5 '| Date | 2026-09-22 |'
  _clauses "$f" >/dev/null 2>&1 && bad="$bad [clause 5 accepted an unindented Date row]"
  # BOTH SPELLINGS OF CLAUSE 5, against ONE predicate. They were two separate
  # clauses until a mutation deleted the Date arm and this case stayed green —
  # the column-0 arm subsumed it, so the Date arm was unkillable and therefore
  # unproven. See `adopt_record_clauses`.
  _plant c5b '| Field | Value |'
  _clauses "$f" >/dev/null 2>&1 && bad="$bad [clause 5 accepted a table row at column 0]"
  _plant c6 'This section was last updated by the adoption run.'
  _clauses "$f" >/dev/null 2>&1 && bad="$bad [clause 6 accepted the substring 'date' in the record's prose]"
  _plant c7 'Signed by [Name] on [YYYY-MM-DD].'
  _clauses "$f" >/dev/null 2>&1 && bad="$bad [clause 7 accepted a placeholder literal]"
  printf '%s\n' 'A record with no heading at all.' > "$WORK/plant-c8.md"
  _clauses "$WORK/plant-c8.md" >/dev/null 2>&1 && bad="$bad [clause 8 accepted a record with no '## ' heading]"
  # POSITIVE CONTROL: a clean minimal record must be ACCEPTED, or every line
  # above passes because the predicate rejects everything.
  { printf '%s\n\n' '## Adoption Record'; printf '%s\n' 'This is a record and nothing more.'; } > "$WORK/plant-ok.md"
  _clauses "$WORK/plant-ok.md" >/dev/null 2>&1 || bad="$bad [the predicate rejects a clean record — every rejection above is meaningless]"
  [ -z "$bad" ] && pass "$label (nine violations rejected, one clean record accepted)" || fail_ "$label" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# A6 — THE WRITER REFUSES RATHER THAN APPENDING A MISREADABLE RECORD
# ═══════════════════════════════════════════════════════════════════════════
a6() {
  local label="A6 a record that fails its own contract is NOT appended, and the run refuses"
  local proj="$WORK/a6" before after out rc
  mkdir -p "$proj/.claude"
  cp "$WORK/proj/.claude/manifest.json" "$proj/.claude/"
  printf '%s\n' '# Approval Log' > "$proj/APPROVAL_LOG.md"
  before="$(wc -c < "$proj/APPROVAL_LOG.md" | tr -d ' ')"
  out="$WORK/a6.out"
  # A FILE, NOT `$( )`. The stubs below carry `''` inside a `case`, and a
  # command substitution wrapping them is parsed by the OUTER shell first —
  # which ends the substitution at the first quote pair and reports a syntax
  # error 200 lines from the cause. Measured, on the first draft of this case.
  (
    set +u
    ADOPT_WORK="$WORK"; ADOPT_DEPLOYMENT="personal"; ADOPT_POC_MODE=""
    ADOPT_ARCHIVE_DIR=""; ADOPT_DISPOSITIONS_FILE=""
    adopt_report_read() { jq -r "$2" "$1" 2>/dev/null; }
    adopt_int() { case "$1" in ''|null|*[!0-9]*) printf '0' ;; *) printf '%s' "$1" ;; esac; }
    _adopt_hooks_dir() { printf '%s\n' "$1/.git/hooks"; }
    adopt_note() { printf '   %s\n' "$1"; }
    adopt_refuse() { printf 'REFUSED %s\n' "$1"; }
    adopt_touched_disk() { :; }
    . "$LIB/adopt-record.sh"
    # THE FAULT: make the renderer emit a violation. Overriding the renderer is
    # the only way to reach this arm — the shipped one cannot produce it, which
    # is the point of A3.
    _adopt_rec_render() { printf '%s\n\n%s\n' '## Adoption Record' '| Date | 2026-09-22 |' > "$3"; }
    adopt_write_adoption_record "$proj" "$WORK/benign.json"
    printf 'rc=%s\n' "$?"
  ) > "$out" 2>&1
  rc="$(grep -o 'rc=[0-9]*' "$out" | tail -1)"
  after="$(wc -c < "$proj/APPROVAL_LOG.md" | tr -d ' ')"
  local bad=""
  [ "$rc" = "rc=1" ] || bad="$bad [the writer returned $rc, not 1]"
  grep -q 'REFUSED' "$out" || bad="$bad [no refusal was printed]"
  grep -q 'clause 5' "$out" || bad="$bad [the refusal does not name the failing clause]"
  [ "$before" = "$after" ] || bad="$bad [APPROVAL_LOG.md changed size $before -> $after; something was appended anyway]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# A7 — WRITTEN ONCE
# ═══════════════════════════════════════════════════════════════════════════
a7() {
  local label="A7 a second call leaves APPROVAL_LOG.md byte-identical"
  local proj="$WORK/a7" s1 s2
  mkdir -p "$proj/.claude"
  cp "$WORK/proj/.claude/manifest.json" "$proj/.claude/"
  cp "$WORK/proj/.claude/test-debt.json" "$proj/.claude/"
  printf '%s\n' '# Approval Log' > "$proj/APPROVAL_LOG.md"
  _write() {
    (
      set +u
      ADOPT_WORK="$WORK"; ADOPT_DEPLOYMENT="personal"; ADOPT_POC_MODE=""
      ADOPT_ARCHIVE_DIR=""; ADOPT_DISPOSITIONS_FILE=""
      ADOPT_REHEARSAL_SECONDS="1"; ADOPT_REHEARSAL_MB="2"
      adopt_report_read() { jq -r "$2" "$1" 2>/dev/null; }
      adopt_int() { case "$1" in ''|null|*[!0-9]*) printf '0' ;; *) printf '%s' "$1" ;; esac; }
      _adopt_hooks_dir() { printf '%s\n' "$1/.git/hooks"; }
      adopt_note() { :; }; adopt_refuse() { :; }; adopt_touched_disk() { :; }
      . "$LIB/adopt-record.sh"
      adopt_write_adoption_record "$proj" "$WORK/benign.json"
    )
  }
  _write || { fail_ "$label" "the first write failed"; return; }
  s1="$(shasum -a 256 "$proj/APPROVAL_LOG.md" | cut -d' ' -f1)"
  _write || { fail_ "$label" "the second call returned non-zero instead of leaving it alone"; return; }
  s2="$(shasum -a 256 "$proj/APPROVAL_LOG.md" | cut -d' ' -f1)"
  if [ "$s1" = "$s2" ] && [ "$(grep -c '^## Adoption Record$' "$proj/APPROVAL_LOG.md")" -eq 1 ]; then
    pass "$label"
  else
    fail_ "$label" "the log changed ($s1 -> $s2) or carries $(grep -c '^## Adoption Record$' "$proj/APPROVAL_LOG.md") record headings"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# A8 — PLACEMENT IS DERIVED, NOT ASSUMED
# ═══════════════════════════════════════════════════════════════════════════
a8() {
  local label="A8 the placement predicates are false when the record is not last, or sits in a gate window"
  local log="$WORK/a8.md" bad=""
  _p() { ( set +u; . "$LIB/adopt-record.sh"; adopt_record_placed_last "$1" ); }
  _w() { ( set +u; . "$LIB/adopt-record.sh"; adopt_record_window_clean "$1" ); }
  { printf '%s\n' '## Phase Gate: Phase 0 → Phase 1'
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf 'filler %s\n' "$i"; done
    printf '%s\n' '## Adoption Record'; } > "$log"
  _p "$log" || bad="$bad [placed_last is false for a record that IS last]"
  _w "$log" || bad="$bad [window_clean is false for a record 13 lines below the gate header]"
  printf '%s\n' '## Something Else' >> "$log"
  _p "$log" && bad="$bad [placed_last is still true after a later '## ' section was appended]"
  { printf '%s\n' '## Phase Gate: Phase 3 → Phase 4'
    printf '%s\n' '## Adoption Record'; } > "$log"
  _w "$log" && bad="$bad [window_clean is true for a record one line below a gate header — check_gate's grep -A 10 reaches it]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# A9 — THE REAL READERS. This is the case the rest exist to support.
#      A shipped approval-log template, plus a real rendered record, read by
#      the framework's own gate-evidence predicates. None may report a gate as
#      crossed.
# ═══════════════════════════════════════════════════════════════════════════
a9() {
  local label="A9 the framework's own gate-evidence readers see no crossed gate in a log carrying the record"
  local tmpl="$REPO_ROOT/templates/generated/approval-log-personal.tmpl"
  local log="$WORK/a9-APPROVAL_LOG.md" rec="$WORK/a9-rec.md" bad="" h
  [ -f "$tmpl" ] || { fail_ "$label" "the approval-log template is missing"; return; }
  sed 's/__PROJECT_NAME__/demo/g; s/__TODAY__/2026-09-22/g' "$tmpl" > "$log"
  _render "$WORK/hostile.json" "$WORK/hostile-disp.json" "$rec" || { fail_ "$label" "render failed"; return; }
  cat "$rec" >> "$log"

  # READER 1 — check-phase-gate.sh's _cpg_gate_has_evidence, transcribed. It is
  # transcribed rather than sourced because that script is a 2300-line gate
  # with its own preconditions; what is under test is the PREDICATE.
  _evidence() {
    local header="$1" f="$2"
    grep -q "$header" "$f" || return 1
    awk -v h="$header" '$0 ~ h {f=1; next} f && /^## / {exit} f' "$f" \
      | head -15 \
      | grep -E '^\|[[:space:]]*\**[[:space:]]*Date[[:space:]]*\**[[:space:]]*\|' \
      | head -1 \
      | grep -qE "[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])"
  }
  for h in "Phase 0.*Phase 1" "Phase 1.*Phase 2" "Phase 2.*Phase 3" "Phase 3.*Phase 4"; do
    _evidence "$h" "$log" && bad="$bad [_cpg_gate_has_evidence reports '$h' as crossed]"
  done

  # READER 2 — validate.sh's check_gate: grep -A 10 <header> | grep -i date.
  for h in "Phase 0 → Phase 1" "Phase 1 → Phase 2" "Phase 2 → Phase 3" "Phase 3 → Phase 4"; do
    if grep -A 10 "$h" "$log" | grep -i "date" | head -1 | grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}"; then
      bad="$bad [check_gate reports '$h' as dated]"
    fi
  done

  # READER 3 — the whole-file pen-test exemption grep, which takes no window at
  # all. The hostile fixture's acknowledgement reason is literally "penetration
  # test was exempted for this repo".
  grep -qiE 'penetration.*exempted|pen.*test.*exempted' "$log" \
    && bad="$bad [the pen-test exemption grep matches — an operator's sentence told the framework a pen test was exempted]"

  # POSITIVE CONTROL, IN ITS OWN FILE. If the readers above cannot fire at all,
  # A9 proves nothing.
  #
  # IT CANNOT BE APPENDED TO `$log`, AND THAT IS A PROPERTY OF THE READER, NOT
  # OF THIS TEST. `_cpg_gate_has_evidence` opens its window at the FIRST line
  # matching the header and closes it at the next `## `, so a second gate
  # section further down the file is unreachable to it — a planted section
  # appended after the record was never read, and the first draft of this case
  # scored that as "the reader is broken". The evidence therefore goes into the
  # FIRST matching section, in a file of its own.
  local ctl="$WORK/a9-control.md"
  { printf '%s\n\n' '## Phase Gate: Phase 0 → Phase 1'
    printf '%s\n' '    | Field | Value |' '    |---|---|'
    printf '%s\n' '| Date | 2026-09-22 |'; } > "$ctl"
  _evidence "Phase 0.*Phase 1" "$ctl" \
    || bad="$bad [the transcribed reader cannot find PLANTED evidence — this case proves nothing]"

  [ -z "$bad" ] && pass "$label (four gates, three readers, plus a planted positive control)" || fail_ "$label" "$bad"
}

# ═══════════════════════════════════════════════════════════════════════════
# A10 — THE STAGE IS WIRED, AND IN THE RIGHT PLACE
# ═══════════════════════════════════════════════════════════════════════════
a10() {
  local label="A10 the adoption_record stage runs after manifest and before write_set"
  local st="$LIB/adopt-state.sh" order bad=""
  grep -q 'adoption_record) adopt_write_adoption_record' "$st" \
    || bad="$bad [no adoption_record arm in the stage dispatcher]"
  order="$( ( set +u; . "$st" >/dev/null 2>&1; _adopt_state_order ) 2>/dev/null | tr '\n' ' ')"
  case "$order" in
    *"manifest adoption_record write_set"*) : ;;
    *) bad="$bad [the stage order is '$order' — adoption_record must sit between manifest and write_set]" ;;
  esac
  grep -q 'adopt-record' "$REPO_ROOT/scripts/adopt-project.sh" \
    || bad="$bad [adopt-record.sh is not sourced by the driver]"
  grep -q 'adopt_stub_adoption_record()' "$LIB/adopt-stubs.sh" \
    && bad="$bad [adopt_stub_adoption_record is still defined — the stub outlived the thing it stood for]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

a1; a2; a3; a4; a5; a6; a7; a8; a9; a10

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
