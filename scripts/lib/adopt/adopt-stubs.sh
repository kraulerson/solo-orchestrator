#!/usr/bin/env bash
# scripts/lib/adopt/adopt-stubs.sh — the parts of adoption that are NOT built,
# said out loud at the point in the run where they belong.
#
# SPEC: docs/designs/2026-08-23-brownfield-adoption-v2.md §10 — WP10 (tool
# resolution and the tier-scoped secrets stop), WP11 (the `script` and
# `document` archive classes), WP12a (the assessment: interview, verdict, plan),
# WP12b (the D3 document writing) and WP7 (the CI carve-out, the provenance
# headers and the Adoption Record).
#
# WP6 AND WP5b HAVE LANDED AND WP5 IS RETIRED, and the header is the first place
# that has to change each time: §7's collision archive with its MANIFEST,
# disclosure and recorded re-adds ships (adopt-archive.sh); the test-debt ledger
# ships (adopt-test-debt.sh); and v1-WP5's certification pass is RETIRED rather
# than pending — D4 deleted the claimed rung it certified against and D10 the
# landed rung it would have certified for (§5.1), so `adopt_stub_certification`
# is gone and `adopt_stub_assessment` took its place.
# A stub file whose own header still claims a delivered package is exactly the
# "measured and clean" misreading these stubs exist to prevent, one level up —
# and this header claimed two of them, plus a retired one, through the whole of
# WP9a.
#
# ─────────────────────────────────────────────────────────────────────────────
# WHY STUBS EXIST AT ALL, AND WHAT MAKES ONE HONEST.
#
# A driver that quietly skipped a measurement produces a project that LOOKS
# measured. The original example was the certification pass: an `adoption` block
# with three empty certification arrays reads, to anyone who finds it later,
# exactly like "we measured and there was nothing to record". v2 §8.3 answered
# it more strongly than a stub could — the arrays are REMOVED from the record
# rather than left empty in it, because a field that is not there cannot be
# misread as a measurement — but the reasoning is why the stubs below exist. §5.1's indictment of bare grandfathering is
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

# WP12a — THE ASSESSMENT (Act 3), which is the act this run just handed off to.
#
# THIS REPLACES THE WP5 CERTIFICATION STUB, AND THE REPLACEMENT IS NOT A
# RENAME. v1-WP5's pass certified every gate below a CLAIMED rung; D4 deleted
# the claim and D10 deleted the landing, so the pass has no object and §5.1
# RETIRES it. Announcing a retired package as "not built yet" would be worse
# than silence — it tells an operator to expect something nobody will ever
# build — so what is announced instead is the thing that genuinely has not run
# and genuinely will: the assessment.
#
# It is announced rather than started because Act 3 is a Claude Code session,
# not a shell step. The one honest thing this driver can do about it is name it
# and point at the script that generates the first message.
adopt_stub_assessment() {
  adopt_stub_notice "the assessment (Act 3) — the requirements interview, the fitness verdict and the plan" "WP12a" \
    "Adoption has surveyed, installed and recorded. What it has NOT done is ask you what this"
  adopt_note "project is for, judge whether the technology fits those answers, or write you a plan."
  adopt_note "Until that ships, PROJECT_INTAKE.md carries the cells the scan could fill and leaves"
  adopt_note "the rest blank, and the Phase 0 questions are asked the ordinary way instead."
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
# adopt_stub_secrets_disposition — RETIRED 2026-09-19 by WP10b/2.
#
# The secrets disposition is no longer a stub. `adopt_secrets_decide` in
# `scripts/lib/adopt/adopt-secrets.sh` implements §6.1's ten-cell tier table,
# and the driver calls it at step 3 (`# BL-242-SECRETS-DECIDE-CALL`) on a scan
# this run performed (`# BL-242-SECRETS-STOP-CALL`).
#
# THE NAME IS LEFT HERE AS A HEADSTONE rather than deleted silently, because
# `## BL-242:`'s own derivation of "what is still unbuilt" counts the
# `adopt_stub_*` functions that are actually CALLED, and a reader following an
# older handoff to this file should find out where the behaviour went.

# WP7 — the Adoption Record, the audit rows, and the CI carve-out.
#
# WHAT THIS USED TO SAY, AND WHY IT WAS WRONG AFTER WP9b. Both this comment and
# the notice below asserted that `APPROVAL_LOG.md` "is not written, so the phase
# gate will report it missing" — accurate until A4, and printed on every
# successful run AFTER the state loop had written that very file and BEFORE the
# commit that includes it. The stub told each operator the opposite of what the
# same run had just done. What is still missing is the RECORD — the eight-clause
# Adoption Record that WP7 appends INTO this log — not the log.
# adopt_stub_adoption_record — RETIRED 2026-09-22 by WP7/1.
#
# The Adoption Record is no longer a stub. `adopt_write_adoption_record` in
# `scripts/lib/adopt/adopt-record.sh` appends it to `APPROVAL_LOG.md` as the
# `adoption_record` stage of the write phase (`# BL-242-RECORD-STAGE`), and
# `adopt_record_clauses` holds v1 §8.8's eight-clause contract at write time
# rather than in a comment.
#
# THE NAME IS LEFT HERE AS A HEADSTONE, the same as the secrets stub above,
# because `## BL-242:`'s derivation of "what is still unbuilt" counts the
# `adopt_stub_*` functions that are actually CALLED, and a reader following an
# older handoff to this file should find out where the behaviour went.
#
# WHAT OF WP7 IS STILL OUT: the CI carve-out and the `adoption` audit row.
# `secrets_disposition` is UNOWNED, not WP7's — `adopt_audit_event`'s own
# header says so, and that header is the live list. An earlier draft of this
# paragraph assigned it to WP7 while the same commit's `docs/adoption.md`
# correctly called it unowned; two records of one fact disagreeing is the shape
# this file exists to prevent.

# adopt_stub_hooks — RETIRED 2026-09-23 by WP7/3.
#
# The commit-time scanners are installed now. `adopt_install_hooks` writes the
# fallback pre-commit hook through the shared emitter
# (`# BL-242-PRECOMMIT-INSTALL`) and `_adopt_install_semgrep_config` lays down
# the DOM-sink ruleset that hook reads (`# BL-242-SEMGREP-CONFIG`), without
# which its static-analysis arm warns on every commit instead of running.
#
# THE STUB'S OWN SENTENCE IS WHAT RETIRED IT. It said installing the hook
# "refuses every commit, because it expects artifacts an adoption does not yet
# produce" — a MEASUREMENT, and therefore one worth re-taking once WP7/1 landed
# the Adoption Record. Re-measured on a real adoption: an ordinary `docs:`
# commit lands at rc 0, a source file whose tests fail is blocked at rc 1, and
# a staged private key is blocked at rc 1.
#
# THE NAME IS LEFT AS A HEADSTONE, like the two above it, because `## BL-242:`
# derives "what is still unbuilt" from the `adopt_stub_*` functions that are
# CALLED, and a reader following an older handoff should find out where the
# behaviour went.

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
  adopt_stub_notice "your project's framework documents" "WP11 archives them, WP12b writes them (D3)" \
    "CLAUDE.md, the document templates and the reference docs are NOT written. The scripts and the"
  adopt_note "state are here, so the gates work; the reading material an agent picks up at the start"
  adopt_note "of a session is not, and a CLAUDE.md you already have would be a collision, not a gap."
  # NO BACKTICKS IN A DOUBLE-QUOTED ARGUMENT. `document` was command
  # substitution, so this line ran `document`, printed
  # `adopt-stubs.sh: line 190: document: command not found` to stderr on every
  # adoption, and told the operator "WP11 shipped D3's  class".
  adopt_note "Your framework documents ARE archived now — WP11 shipped D3's document class, so"
  adopt_note "each one you already owned is in the adoption archive with a restore line. What is"
  adopt_note "not built is the WRITING of the new ones (WP12b), which is what this notice is about."
}

# WP7 — §8.6's provenance headers on reconstructed documents.
adopt_stub_provenance_headers() {
  adopt_stub_notice "the provenance headers on reconstructed documents" "WP7" \
    "PROJECT_INTAKE.md records where each answer came from, but it carries no machine-readable"
  adopt_note "provenance header. A near-miss header is worse than none: WP7 ships a lint for the"
  adopt_note "real one, and a lint cannot tell a near-miss from the genuine article."
}
