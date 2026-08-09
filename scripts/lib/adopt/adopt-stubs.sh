#!/usr/bin/env bash
# scripts/lib/adopt/adopt-stubs.sh — the parts of adoption WP4 does NOT build,
# said out loud at the point in the run where they belong.
#
# SPEC: docs/designs/2026-08-02-brownfield-adoption-v1.md §10 — WP5 (the
# certification pass), WP5b (the test-debt ledger), WP6 (the collision archive,
# the disclosure and the re-add warning), WP7 (the CI carve-out, the provenance
# headers and the Adoption Record), §6.3 (per-finding secrets disposition).
#
# ─────────────────────────────────────────────────────────────────────────────
# WHY STUBS EXIST AT ALL, AND WHAT MAKES ONE HONEST.
#
# A driver that quietly skipped the certification pass would produce a project
# that LOOKS certified: an `adoption` block with three empty certification
# arrays reads, to anyone who finds it later, exactly like "we measured and
# there was nothing to record". §5.1's indictment of bare grandfathering is
# that "nothing is measured; nothing is recorded; the exemption is the ABSENCE
# of a field" — an unannounced stub reproduces all three properties.
#
# So each stub below prints, at the moment the real thing would have run, what
# did not happen and which work package owns it. None of them returns a result,
# none of them writes a record, and none of them can be mistaken for a pass.
# They are load-bearing honesty, and they are the whole of WP4's answer to the
# parts of adoption it does not implement.

adopt_stub_notice() {
  local what="$1" owner="$2" consequence="$3"
  adopt_blank
  adopt_say "NOT DONE — $what"
  adopt_note "Owner: $owner. This build does not do it, and does not pretend to."
  adopt_note "$consequence"
}

# WP5 — the certification pass (§5). The empty certification arrays in the
# stamp are the visible consequence and the notice names them, because an empty
# array is exactly what a completed pass with no findings would also produce.
adopt_stub_certification() {
  local scenario="$1" landed="$2"
  local scope
  if [ "$scenario" = "completed" ]; then
    scope="every gate from 0 to 4, because landing at 4 means all four have notionally been crossed"
  else
    scope="the gates below phase $landed; the ones above it get crossed the ordinary way, later"
  fi
  adopt_stub_notice "the certification pass" "WP5" \
    "It would have run $scope, and a blocker-grade finding would have stopped this adoption."
  adopt_note "Because it did not run, the adoption record's certification lists are EMPTY."
  adopt_note "An empty list here means 'not measured', not 'measured and clean'."
}

# WP5b — the test-debt ledger and its ratchet (§5.4).
adopt_stub_test_debt_ledger() {
  adopt_stub_notice "the test-debt ledger" "WP5b" \
    "Existing untested files are not recorded, so nothing yet stops that set from growing."
}

# WP6 — the collision archive, its MANIFEST, the disclosure and the re-add
# warning (§7.2/§7.3). WP4 refuses to overwrite; it does not archive.
adopt_stub_collision_archive() {
  local n="${1:-0}"
  [ "$n" -gt 0 ] || return 0
  adopt_stub_notice "the collision archive" "WP6" \
    "$n of your files sit where a framework file would go. They were LEFT ALONE — not archived,"
  adopt_note "not replaced, not listed in a restorable manifest. The framework's version of each"
  adopt_note "of those files is therefore NOT installed, so anything that depends on it is inert."
}

# §6.3 — per-finding secrets disposition. Scout already reported the findings
# (redacted); deciding what to do about each one is not WP4's.
adopt_stub_secrets_disposition() {
  local report="$1"
  local n
  n="$(adopt_int "$(adopt_report_read "$report" '.secrets.findingCount // 0')")"
  local status
  status="$(adopt_report_read "$report" '.secrets.status // ""')"
  if [ "$status" != "scanned" ]; then
    adopt_stub_notice "the secrets disposition" "WP6" \
      "The scan did not run a secrets tool, so this adoption knows nothing about credentials in your history."
    return 0
  fi
  [ "$n" -gt 0 ] || return 0
  adopt_stub_notice "the secrets disposition" "WP6" \
    "The scan found $n secret-shaped finding(s) in this repository's history. Each one needs a"
  adopt_note "recorded decision and this build does not collect one. Read"
  adopt_note ".claude/adoption/scout-report.json's secrets section before you trust this repo."
}

# WP7 — the Adoption Record in APPROVAL_LOG.md, the audit rows, and the CI
# carve-out. Named here because its absence has an immediate, visible effect:
# check-phase-gate.sh exits 1 on a project with phase-state and no
# APPROVAL_LOG.md, which is the SAFE direction but is not a finished adoption.
adopt_stub_adoption_record() {
  local scenario="$1" landed="$2"
  adopt_stub_notice "the Adoption Record, the audit rows and the CI carve-out" "WP7" \
    "APPROVAL_LOG.md is not written, so the phase gate will report it missing until WP7 lands."
  adopt_note "That is the safe direction — a blocked project, not a silently-approved one — but it"
  adopt_note "means this adoption ($scenario, phase $landed) is recorded in the manifest and"
  adopt_note "nowhere else yet."
}

# The fallback PRE-COMMIT hook. Not attributed to a work package, because §10
# names no owner for it on the adoption path — that is the honest statement and
# the WP4 report records it as an open decision. Measured, not assumed: with
# that hook installed at this point in the build an adopted fixture could not
# land an ordinary `docs:` commit, because the hook expects framework artifacts
# a WP4 adoption has not produced.
adopt_stub_hooks() {
  adopt_stub_notice "the commit-time scanners (the fallback pre-commit hook)" "nobody yet — §10 names no owner" \
    "The message gates ARE on. The secret scan, the static-analysis pass and the schema-migration"
  adopt_note "checks that normally run on every commit are NOT — installing that hook today refuses"
  adopt_note "every commit, because it expects artifacts an adoption does not yet produce. Run them"
  adopt_note "by hand until it lands: bash scripts/pre-commit-gate.sh --terminal-mode"
}

# The adoptee's own framework DOCUMENTS — CLAUDE.md, the generated templates,
# docs/reference/, the .gitignore additions. Every one of them is a path an
# adoptee may already occupy (a CLAUDE.md especially), which makes writing them
# §7's collision question and therefore WP6's, not this package's. Named here
# because the absence is not cosmetic: CLAUDE.md is what a downstream agent
# reads at kickoff, so an adopted project without it starts every session
# without its orientation.
adopt_stub_project_docs() {
  adopt_stub_notice "your project's framework documents" "WP6 (they are collision decisions before they are writes)" \
    "CLAUDE.md, the document templates and the reference docs are NOT written. The scripts and the"
  adopt_note "state are here, so the gates work; the reading material an agent picks up at the start"
  adopt_note "of a session is not, and a CLAUDE.md you already have would be a collision, not a gap."
}

# WP7 — §8.6's provenance headers on reconstructed documents.
adopt_stub_provenance_headers() {
  adopt_stub_notice "the provenance headers on reconstructed documents" "WP7" \
    "PROJECT_INTAKE.md records where each answer came from, but it carries no machine-readable"
  adopt_note "provenance header. A near-miss header is worse than none: WP7 ships a lint for the"
  adopt_note "real one, and a lint cannot tell a near-miss from the genuine article."
}
