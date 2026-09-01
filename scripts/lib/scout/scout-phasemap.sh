#!/usr/bin/env bash
# scripts/lib/scout/scout-phasemap.sh — §8.2's `phaseMap` section: the
# extracted artifact ladder.
#
# SPEC: docs/designs/2026-08-02-brownfield-adoption-v1.md §4.4 (the ladder and
# its THREE corrections), §8.2 (the `phaseMap` object and the extraction table
# row naming validate.sh as the source).
#
# M5: sources nothing. See scripts/lib/scout/scout-core.sh's header.
#
# ─────────────────────────────────────────────────────────────────────────────
# WHAT WAS EXTRACTED, AND FROM WHERE
#
# The original is `scripts/validate.sh`, in the straight-line top-level script
# body under `print_section "Phase State & Artifacts"`, where a variable named
# `artifact_phase` is assigned by a run of four independent `if [ -f … ]`
# tests: PRODUCT_MANIFESTO.md -> 1, PROJECT_BIBLE.md -> 2, a non-empty
# docs/test-results/ -> 3, HANDOFF.md -> 4.
#
# §8.2 specifies reuse-by-EXTRACTION: the PREDICATE is copied, the dependency
# is not. Nothing here sources validate.sh, and validate.sh is unchanged — it
# is a diagnostic for framework-native projects and it is correct at that job.
# What follows is a DECISION PROCEDURE for a project the framework has never
# seen, and §4.4 names three corrections it has to make.
#
# CORRECTION 1 — a function, and a marker.
#   The original is not in a function and carries no marker, so it cannot be
#   cited, called or mutation-tested. The extracted copy is `scout_phasemap_scan`
#   and its load-bearing line is `# SCOUT-LADDER-MAX`.
#
# CORRECTION 2 — maximum reached rung, not last-wins.
#   The original's assignments are sequential, so the LAST matching test wins.
#   A project with a HANDOFF.md and a since-emptied docs/test-results/ reports
#   4 — it is credited with a phase it demonstrably skipped. The extracted copy
#   CLIMBS: a rung advances the placement only when the rung below it was
#   itself reached, so the ladder stops at the first gap. That fixture reports
#   2 here, and X1 in tests/test-brownfield-wp1-scout.sh restores last-wins and
#   watches 2 become 4.
#
#   The report carries BOTH numbers, on purpose. `suggestedPhase` is where the
#   ladder stops; `highestSatisfiedRung` is the highest rung satisfied in
#   isolation. When they differ, the gap between them IS the finding — this
#   project has phase-4 artifacts and no phase-3 evidence — and hiding it
#   behind one number would throw away the most useful thing the scan learned.
#   §8.2's `note` is emitted verbatim.
#
# CORRECTION 3 — the adoptee's own evidence.
#   The original keys on four framework filenames, which a brownfield project
#   does not have; applied unchanged it would place every adoptee at 0. Each
#   rung is re-expressed over what the project actually has — a product
#   description of any name, an architecture document of any name, a test
#   corpus that runs, a lane out the door — with the framework filename kept as
#   ONE input among several. §4.4 calls this the least certain mechanism in the
#   design and §12 says so; the mitigation is that every rung publishes the
#   evidence string it decided on, so the operator can disagree with a specific
#   claim rather than with a number.
#
# THE FLOOR RULE (§4.4), which is why being wrong here is survivable: the
# interview may only move the placement DOWN. THAT FLOOR RULE IS DELETED
# (v2 D4/D10): there is no interview here and no placement anywhere — every
# adopted project lands at phase 0 and earns each boundary through the ordinary
# gates. The number below survives with a different job: EVIDENCE, pre-filling
# the Phase 0 intake. This is a ceiling offered for
# argument, never a floor asserted over the operator.

# _scout_rung1 ROOT — is the product described in writing anywhere?
_scout_rung1() {
  local root="$1" hit
  hit=$(scout_first_nonempty_file "$root" \
        PRODUCT_MANIFESTO.md README.md README.rst README.txt readme.md \
        docs/README.md PRD.md docs/PRD.md docs/prd.md docs/product.md \
        docs/vision.md docs/overview.md) && {
    printf '%s (the product is described in writing)\n' "$hit"; return 0; }
  printf 'no product description found — looked for PRODUCT_MANIFESTO.md, README.*, PRD.md, docs/product*, docs/vision*, docs/overview*\n'
  return 1
}

# _scout_rung2 ROOT — is the technical shape written down anywhere?
_scout_rung2() {
  local root="$1" hit d
  hit=$(scout_first_nonempty_file "$root" \
        PROJECT_BIBLE.md ARCHITECTURE.md architecture.md docs/ARCHITECTURE.md \
        docs/architecture.md DESIGN.md docs/DESIGN.md docs/design.md \
        docs/technical-design.md docs/system-design.md) && {
    printf '%s (the technical shape is documented)\n' "$hit"; return 0; }
  for d in docs/adr docs/adrs docs/designs docs/rfcs docs/architecture; do
    if scout_dir_has_entries "$root/$d"; then
      printf '%s/ (%s design documents)\n' "$d" "$(scout_count_entries "$root/$d")"
      return 0
    fi
  done
  printf 'no architecture or design document found — looked for PROJECT_BIBLE.md, ARCHITECTURE.md, DESIGN.md, docs/architecture*, docs/design*, docs/adr*, docs/rfcs\n'
  return 1
}

# _scout_test_corpus ROOT — a relative path naming the test corpus, or empty.
_scout_test_corpus() {
  local root="$1" d hit
  for d in tests test spec __tests__ src/test src/tests test_suite; do
    if scout_dir_has_entries "$root/$d"; then printf '%s/\n' "$d"; return 0; fi
  done
  hit=$(grep -E '(^|/)(test_[^/]+|[^/]+_test|[^/]+\.test|[^/]+\.spec)\.[A-Za-z0-9]+$' \
        "$SCOUT_FILES_LIST" 2>/dev/null | head -1)
  [ -n "$hit" ] && { printf '%s\n' "$hit"; return 0; }
  return 1
}

# _scout_rung3 ROOT WORK — is there a test corpus that actually runs?
#
# "That runs" is the phrase §4.4 uses and it is doing real work: a `tests/`
# directory with no way to invoke it is a folder, not a corpus. Rung 3 needs
# BOTH a corpus and a command — or the framework's own archive of results,
# which is proof the corpus ran at least once.
#
# EVERY "is there content here" question on this ladder goes through
# `scout_dir_has_entries`, which counts NON-HIDDEN entries. A `.gitkeep` is not
# an archived test result. Read that function's header before replacing any of
# these calls with an inline emptiness test — the last time the predicate and
# the count were spelled separately, this arm reported a satisfied rung and
# "0 archived result files" in the same breath, and the design's own scenario
# regressed to the number correction 2 exists to remove.
_scout_rung3() {
  local root="$1" work="$2" corpus cmd
  if scout_dir_has_entries "$root/docs/test-results"; then
    printf 'docs/test-results/ (%s archived result files)\n' "$(scout_count_entries "$root/docs/test-results")"
    return 0
  fi
  corpus=$(_scout_test_corpus "$root") || corpus=""
  cmd=""
  [ -s "$work/testcmd" ] && cmd=$(cut -f1 < "$work/testcmd")
  if [ -n "$corpus" ] && [ -n "$cmd" ]; then
    printf 'test corpus at %s, runnable with `%s`\n' "$corpus" "$cmd"
    return 0
  fi
  if [ -n "$corpus" ]; then
    printf 'a test corpus exists at %s but no test command was found to run it\n' "$corpus"
    return 1
  fi
  if [ -n "$cmd" ]; then
    printf 'a test command exists (`%s`) but no test corpus was found\n' "$cmd"
    return 1
  fi
  printf 'no test corpus and no test command found; docs/test-results/ is absent or empty\n'
  return 1
}

# _scout_rung4 ROOT — is there a lane out the door?
_scout_rung4() {
  local root="$1" hit f base tags
  hit=$(scout_first_nonempty_file "$root" HANDOFF.md RELEASE_NOTES.md docs/RUNBOOK.md docs/runbook.md) && {
    printf '%s (a handover / release record exists)\n' "$hit"; return 0; }
  for f in "$root/.github/workflows"/*.yml "$root/.github/workflows"/*.yaml; do
    [ -f "$f" ] || continue
    base="${f##*/}"
    case "$base" in
      *deploy*|*release*|*publish*|cd.yml|cd.yaml|*delivery*)
        printf '.github/workflows/%s (a deploy or release lane)\n' "$base"; return 0 ;;
    esac
  done
  if [ -f "$root/.gitlab-ci.yml" ] && grep -qE '^[[:space:]]*(stage|-)[[:space:]]*:?[[:space:]]*(deploy|release)' "$root/.gitlab-ci.yml" 2>/dev/null; then
    printf '.gitlab-ci.yml (a deploy or release stage)\n'; return 0
  fi
  if scout_have_git; then
    tags=$(git -C "$root" tag --list 2>/dev/null | grep -cE '^v?[0-9]+\.[0-9]+') || tags=0
    case "$tags" in ''|*[!0-9]*) tags=0 ;; esac
    if [ "$tags" -gt 0 ]; then
      printf '%s version-shaped git tag(s)\n' "$tags"; return 0
    fi
  fi
  printf 'no lane out the door found — no HANDOFF.md or RELEASE_NOTES.md, no deploy/release pipeline, no version-shaped tags\n'
  return 1
}

# scout_phasemap_scan ROOT WORK — fills $WORK with the phaseMap section's data.
#
# Writes (all inside WORK):
#   rungs      `<rung>\t<0|1>\t<evidence>`, ascending
#   suggested  the maximum REACHED rung (the ladder stops at the first gap)
#   highest    the maximum rung satisfied in isolation
scout_phasemap_scan() {
  local root="$1" work="$2"
  local _rung _sat _ev _prev _suggested=0 _highest=0
  local TAB
  TAB=$(printf '\t')

  : > "$work/rungs"
  for _rung in 1 2 3 4; do
    case "$_rung" in
      1) _ev=$(_scout_rung1 "$root") && _sat=1 || _sat=0 ;;
      2) _ev=$(_scout_rung2 "$root") && _sat=1 || _sat=0 ;;
      3) _ev=$(_scout_rung3 "$root" "$work") && _sat=1 || _sat=0 ;;
      4) _ev=$(_scout_rung4 "$root") && _sat=1 || _sat=0 ;;
    esac
    printf '%s\t%s\t%s\n' "$_rung" "$_sat" "$_ev" >> "$work/rungs"
  done

  while IFS="$TAB" read -r _rung _sat _ev; do
    [ -n "$_rung" ] || continue
    _prev=$(( _rung - 1 ))
    if [ "$_sat" -eq 1 ] && [ "$_suggested" -eq "$_prev" ]; then _suggested="$_rung"; fi  # SCOUT-LADDER-MAX
    if [ "$_sat" -eq 1 ] && [ "$_rung" -gt "$_highest" ]; then _highest="$_rung"; fi
  done < "$work/rungs"

  printf '%s\n' "$_suggested" > "$work/suggested"
  printf '%s\n' "$_highest" > "$work/highest"
  return 0
}
