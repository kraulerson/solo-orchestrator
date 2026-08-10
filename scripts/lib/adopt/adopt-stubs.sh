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

# WP5b — the test-debt ledger and its ratchet (§5.4) — RETIRED, NOT DELETED IN
# SPIRIT. The stub that used to live here said "existing untested files are not
# recorded, so nothing yet stops that set from growing". They are recorded now:
# scripts/lib/adopt/adopt-test-debt.sh writes .claude/test-debt.json during the
# run and adopt_test_debt_record announces what it measured. The one thing WP5b
# does NOT ship is an automatic commit-time invocation — §10 gives WP7 the
# commit-time hook — and adopt_stub_hooks below already carries that sentence,
# so a second stub here would be a duplicate notice, not an extra honesty.

# THE FRAMEWORK-SCRIPT COLLISION CLASS — a file of theirs sitting at a path a
# framework SCRIPT wants. WP6 landed the collision archive, so this notice no
# longer says "not archived": it says what is genuinely still missing, which is
# the REPLACEMENT half.
#
# WHY WP6'S ARCHIVE DOES NOT COVER THIS CLASS, stated rather than left as a
# gap. §7.1's archive-and-replace population is their AI-LAYER surfaces and
# their GIT HOOKS, and that boundary is deliberate: archiving-and-replacing an
# adoptee's `scripts/validate.sh` with the framework's would swap out a file
# their own CI may call, on day one, with no operator decision in between —
# the same class of harm §7.4 refuses for their pipelines. Which package owns
# that decision is not settled in §10, so it is named here and not assumed.
#
# adopt_stub_framework_script_collisions N [LIST] — LIST is passed explicitly
# rather than read from a global, so the paths printed are the caller's own.
adopt_stub_framework_script_collisions() {
  local n="${1:-0}" list="${2:-}" p
  [ "$n" -gt 0 ] || return 0
  adopt_stub_notice "installing the framework's version of $n colliding script(s)" \
    "unassigned — §10 gives this class to no work package" \
    "$n of your files sit where a framework SCRIPT would go. They were LEFT ALONE, which is"
  adopt_note "the safe direction, and it has a cost: the framework's version of each of those"
  adopt_note "files is NOT installed, so anything that depends on it is inert. The collision"
  adopt_note "ARCHIVE (WP6) covers your AI-layer settings and your git hooks; these are neither,"
  adopt_note "and replacing a script your own build may call is a decision nobody has made yet."
  # The PATHS, not just the count — "3 collisions" tells an operator nothing
  # they can act on. Bounded, because a heavily-occupied tree could otherwise
  # bury the rest of the run.
  if [ -n "$list" ]; then
    printf '%s\n' "$list" | head -20 | while IFS= read -r p; do
      [ -n "$p" ] && adopt_note "  yours, kept: $p"
    done
    [ "$n" -gt 20 ] && adopt_note "  ...and $((n - 20)) more."
  fi
  return 0
}

# §6.3 — per-finding secrets disposition. Scout already reported the findings
# (redacted); deciding what to do about each one is not WP4's.
adopt_stub_secrets_disposition() {
  local report="$1"
  local n
  n="$(adopt_int "$(adopt_report_read "$report" '.secrets.findingCount // 0')")"
  local status
  status="$(adopt_report_read "$report" '.secrets.status // ""')"
  # OWNER CORRECTED AT WP6. §6.3's per-finding disposition of the project's
  # HISTORY is a different surface from §7.3's archive scan, which WP6 did
  # build, and §10 assigns §6.3 to no work package at all. Naming WP6 here now
  # that WP6 has landed would read as "already done".
  if [ "$status" != "scanned" ]; then
    adopt_stub_notice "the secrets disposition" "unassigned — §10 gives §6.3 to no work package" \
      "The scan did not run a secrets tool, so this adoption knows nothing about credentials in your history."
    return 0
  fi
  [ "$n" -gt 0 ] || return 0
  adopt_stub_notice "the secrets disposition" "unassigned — §10 gives §6.3 to no work package" \
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
#
# OWNER CORRECTED AT WP6, for the same reason as the secrets stub above. WP6
# built §7's collision ARCHIVE — the AI-layer surfaces and the git hooks. It
# does not write the adoptee's framework DOCUMENTS, and §10-WP6's scope row
# does not ask it to. Leaving "WP6" here after WP6 landed would announce a
# delivered owner for undelivered work, which is the one thing an honest stub
# must not do.
adopt_stub_project_docs() {
  adopt_stub_notice "your project's framework documents" "unassigned — §10 names no owner" \
    "CLAUDE.md, the document templates and the reference docs are NOT written. The scripts and the"
  adopt_note "state are here, so the gates work; the reading material an agent picks up at the start"
  adopt_note "of a session is not, and a CLAUDE.md you already have would be a collision, not a gap."
  adopt_note "WP6's archive covers your AI-layer settings and your git hooks; documents are neither."
}

# WP7 — §8.6's provenance headers on reconstructed documents.
adopt_stub_provenance_headers() {
  adopt_stub_notice "the provenance headers on reconstructed documents" "WP7" \
    "PROJECT_INTAKE.md records where each answer came from, but it carries no machine-readable"
  adopt_note "provenance header. A near-miss header is worse than none: WP7 ships a lint for the"
  adopt_note "real one, and a lint cannot tell a near-miss from the genuine article."
}
