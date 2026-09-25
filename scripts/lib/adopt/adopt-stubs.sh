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
# adopt_stub_assessment — RETIRED 2026-09-24 by WP12a. The assessment is
# built: Act 2 writes the prompt (`# BL-242-ASSESSMENT-PROMPT`), resume.sh
# prints it (`# BL-242-RESUME-ASSESSMENT`), a Claude Code session conducts it,
# and `adopt-project.sh --act4` records it (`# BL-242-ACT4-FINISH`). The run
# now ends with `adopt_act3_next`, which names the step instead. The name is
# left as a headstone, like the others in this file.

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
# WHAT OF WP7 IS STILL OUT: the provenance-header lint. The CI carve-out ships
# (`# BL-242-CI-AUDIT`, `# BL-242-CI-STAGE`) and the `adoption` and
# `secrets_disposition` audit rows are written since 2026-09-24
# (`# BL-242-ADOPTION-EVENT`, `# BL-242-DISPOSITIONS-EVENT`); `adopt_audit_event`'s
# own header is the live list of which events have an emitter.

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

# adopt_stub_project_docs — RETIRED 2026-09-24 by WP12b.
#
# The framework documents are written now: `adopt_write_framework_docs`
# (`# BL-242-DOCS-STAGE`, scripts/lib/adopt/adopt-docs.sh) renders CLAUDE.md
# through the renderer `init.sh` uses, copies the six document templates, lays
# down the reference guides where absent, and names every original it replaced
# with an invitation to retrieve content from the archive — D3's informing
# half. What is NOT built is D3's "adapt or merge" half, which is judgement and
# belongs to the assessment (Act 3), and the `.gitignore` additions `init.sh`
# makes.
#
# THE NAME IS LEFT AS A HEADSTONE, like the ones above it.

# adopt_stub_provenance_headers — RETIRED 2026-09-25 by WP7. PROJECT_INTAKE.md
# opens with §8.6's header (`# BL-242-PROVENANCE-HEADER`), checked where it is
# written (`# BL-242-PROVENANCE-WRITE-CHECK`) and again by the Act 4 finisher
# (`# BL-242-PROVENANCE-ACT4-CHECK`). A headstone, like the others here.
