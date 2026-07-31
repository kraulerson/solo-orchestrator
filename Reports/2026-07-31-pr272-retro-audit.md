# Retroactive adversarial audit of PR #272 — record of completion

**Audited:** 2026-07-31, by a fable-tier `pr-reviewer` dispatch (read-only; every finding pinned to
immutable SHAs). **Subject:** PR #272 (merge `d970b27`, merged 2026-07-26) — "docs: close the
#265-#271 wave, file BL-180/181/182, reconcile the handoff archive" — the one PR that merged
UNREVIEWED after the 2026-07-27 standing review gate was established; its audit has been queued in
handoffs since.

## Verdict: FINDINGS-INERT

Real defects existed; all were since fixed by later work or are harmless today. **Nothing on
today's `main` needs remediation from this audit.**

## Findings

1. **R-272-1 (refuted claim, since repaired):** the filed BL-181 entry claimed the comment-exemption
   hole "re-classifies exactly one current file"; the auditor re-ran the entry's own predicate at
   the filing tree (`b0b60aa`) and measured **seven** — six fast tests beyond the named one were
   silently outside every PR-blocking lane at that moment. Repaired the next day by `7faaedf`
   (all seven in the unit list today); the `## BL-181:` entry already carries the strikethrough
   correction (added 2026-07-27) and CLAUDE.md's HOUSE RULES record the true count. A
   contemporaneous reviewer would have caught it in one command — the concrete cost of the skipped
   review.
2. **R-272-2 (minor, inert):** "docs-only — no product code" was an overclaim: the PR edited
   `templates/generated/gitignore-base.tmpl`, which `generate_gitignore()` copies verbatim into
   every scaffold. The change was 100% `#`-comment lines (behavior-inert), the bypass
   classification was extension-legitimate, and every factual claim in the added comment
   re-verifies today. Cosmetic residue: generated `.gitignore`s carry framework-maintenance prose
   meaningless downstream — optional one-line trim, unfiled.
3. **R-272-3 (trivial, attributed to LATER waves, not #272):** older handoff stubs' "Live
   state-of-record" lines point one hop behind (at `2026-07-30-…`, itself now a stub). The chain
   resolves by following it (two-plus hops — three as of this writing, after #294 stubbed the
   middle link) and CLAUDE.md's "trust the non-stub" rule — added by #272 itself — covers
   it. Candidate fix for a future handoff-close pass: point stub Live-lines at `docs/INDEX.md`
   instead of a moving filename.

## What held (the substance of the audit)

All six closure citations (`7866022` `d857294` `ed406c8` `b0b60aa` `73c6083` `8afb9ba`) resolve to
the claimed merges and every cited `# BL-NNN-…` marker exists in the cited tree; backlog
arithmetic exact (176→179 entries, 28→25 open); BL-180/BL-182's filed claims verify byte-for-byte
against `b0b60aa` and both were fixed along their filed shapes (#273/#274); the boldest
"verified, not inferred" claim (no CI lane ran the two BL-173-repaired suites) verified on all
three legs; all five archive moves are blob-identical to their pre-move files; the bugs file was
untouched as designed.

**Conclusion for the process record:** the skipped review would have caught exactly one thing
(R-272-1) — and that thing was a live coverage hole. The standing review-before-PR gate earns its
cost; the queue item "retroactive audit of #272" is retired by this report.
