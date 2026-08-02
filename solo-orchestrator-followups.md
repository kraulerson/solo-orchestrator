# solo-orchestrator-followups.md — revisit candidates (NOT backlog entries)

Items land here when a session raises something worth revisiting but no decision
has been made. **Nothing in this file is committed work**: each item needs a
decision — file as a `BL-NNN` backlog entry, fold into an existing entry, do it
immediately, or drop it — before any build happens. Promoting an item means
writing the real backlog entry and deleting (or annotating) the row here.

Scope note: this file is deliberately OUTSIDE the lint-enforced prose surface
(`lint-bl-markers.sh` and `lint-backlog-references.sh` enumerate their files),
so BL/marker citations below are informational, not machine-checked. Re-verify
before relying on them.

Grammar: `## F-NNN:` header, **Raised**, **Status** (`Awaiting decision` |
`Verified benign — latent note` | `Karl's own action`), body, **Options**.

---

## F-013: Two pre-existing edge defects in lint-backlog-references.sh

**Raised:** 2026-08-02 (BUG-008 review edge sweep — both confirmed byte-identical
on main, i.e. NOT introduced by the fix). **Status:** Awaiting decision.

(1) A backlog that exists but has zero `## BL-NNN:` headers (e.g. zero-byte) +
`--pre-commit-mode` + a BL-citing message crashes (`VALID_IDS[@]: unbound
variable`, bash-3.2 set -u empty-array expansion in `is_valid_id`, rc=1 → the
gate denies with a shell error as the reason). Fail-closed, reachable only if a
generated project creates its own backlog file. Fix: an empty-set guard at the
head of `is_valid_id`. (2) An UNREADABLE (chmod 000) backlog in repo mode
passes silently — `[ -f ]` passes and the awk/grep captures are not
status-checked, so an I/O error prints `OK … consistent.` rc=0: a repo-mode
silent-pass of exactly the class the FATAL guards against. Fix: `[ -r ]`
beside the existence check, same mode-aware shape.

**Options:** (a) small follow-up PR with both guards + tests; (b) accept —
both are edge-reachable only.

## F-001: Suppression-grammar drift has no canary (BL-201 × BL-185 coupling)

**Raised:** 2026-08-01, post-quick-sweep confidence review.
**Status:** Awaiting decision.

BL-201 (#292) floats CI semgrep to `semgrep/semgrep:latest`; BL-185 (#303)
detects staged suppressions by grepping the spellings semgrep honors **today**
(`nosem`/`nosemgrep`, any case — measured against current versions, fence
`# BL-185-SUPPRESSION-DETECT-BEGIN`). The BL-200 canary pins the syntax-error
line FORMAT only. If a future semgrep honors a new suppression spelling, the
receipt undercounts silently and `sast_suppression` ledger rows go missing.
Blast radius is low — the row is `recorded_only` (advisory by Karl's BL-185
decision), so nothing blocks that shouldn't; the failure is a quiet audit gap.

**Options:** (a) extend the BL-200-style canary with a suppression-grammar case
(fixture per spelling; assert the finding is actually suppressed AND counted);
(b) file as a Low backlog entry; (c) accept and annotate the closed BL-185 entry.

## F-002: Unit-lane `tests=(` array hand-audit after the sweep's conflict resolutions

**Raised:** 2026-08-01. **Status:** Verified benign — latent note.

Checked on merged main `da66a66` (the sweep's hand-resolved merges were the
risk window): 144 live entries, ZERO commented-out entries inside the array
scope. One latent hazard remains: the documentation comment inside the array
names the literal path `tests/test-lint-no-live-remote.sh`, and per the BL-181
residual, comments inside the scope COUNT as lint membership — benign today
because the live entry exists (array line ~124), but if that live entry is ever
removed, the lint stays green while the test stops running.

**Options:** (a) deface the path token in that comment (e.g. split the word) so
it can never satisfy membership; (b) accept — it is one file, and the residual
is already recorded on `## BL-181:`.

## F-003: BL-206's naive comment-strip is a pinned approximation

**Raised:** 2026-08-01 (recorded trade-off from #300's review).
**Status:** Awaiting decision (lean: leave until the trigger fires).

The Cg5-scan-exec extraction strips comments naively (quote-tracker was
retreated from during review). Thirteen strip-control fixtures + the MUT-S3
standing guard pin today's templates; a future CI template carrying `#` inside
a quoted YAML scalar could be mis-stripped in a shape the guard doesn't cover.

**Revisit trigger:** any change to `templates/pipelines/ci/**` that introduces
`#` inside a quoted scalar — check the bl147 suite catches it.

## F-004: Closure/docs PRs get one review round vs code's multi-round

**Raised:** 2026-08-01. **Status:** Awaiting decision (process/policy).

Every code PR this sweep went through adversarial rounds that found real
defects (including in the supervisor's own package); the closures PR (#307) got
one round (minor_concerns, three number corrections — all real). Base rate says
first-pass work contains defects; the docs pass gets the least pressure.
Mitigation already in place: `lint-backlog-references` + `lint-bl-markers`
mechanically verify closure cites and marker references.

**Options:** (a) mandate a confirm round on closure PRs like code PRs;
(b) accept lint coverage as the second layer (cheapest, current de-facto state).

## F-005: Per-agent scratchpad subdirectories in wave dispatches

**Raised:** 2026-08-01 (a sibling agent clobbered another's commit-message file
in the shared scratchpad during the sweep). **Status:** Awaiting decision.

**Options:** (a) add "use a per-agent subdir under the scratchpad" to the
standing dispatch template (one line, supervisor-side habit); (b) fold into the
operating-model re-plan where dispatch mechanics are being redesigned anyway.

## F-006: Re-run the execution-based audit of unit-lane-exempt rows

**Raised:** standing CLAUDE.md instruction (BL-181 section: "Re-run it; do not
cite the number") — the 2026-07-26 execution-trace pass covered 27 rows; the
tree has since grown (~29+ via the BL-180 suites, plus this sweep's additions).
**Status:** Awaiting decision — the instruction exists but has no owner or
trigger.

**Options:** (a) run it now (recipe is in CLAUDE.md: env-gated marker append to
init.sh, run each exempt row, marker = proof); (b) attach a trigger — "re-run
after any wave that adds test suites" — recorded on `## BL-181:`; (c) fold into
BL-181's eventual structural fix and stop hand-auditing.

## F-007: Branch/worktree housekeeping

**Raised:** accumulated through 2026-07-31→08-01. **Status:** Karl's own action
(agents are blocked from destructive git ops).

- ~95 stale agent worktrees under `.claude/worktrees/` (inert, disk only).
- `fix/bl112-sast-scan-coverage` — retained as evidence for filing
  BL-185/186/188/189; those were filed in #295, so the branch is now prunable.
- `perf/unit-lane-shard-rebalance` — one superseded draft commit, prunable.

## F-008: Live-ZAP real-container smoke of the BL-165 hardened-serve harness

**Raised:** 2026-07-24 (#263's verifier: "worth doing at next dogfood walk");
never scheduled. **Status:** Awaiting decision.

The DAST hardened-serve path is proven in the stub world + local ZAP; a real
container run has not exercised the Replacer-hook + `/zap/wrk` bind end-to-end
since the harness landed.

**Options:** (a) fold into the next dogfood walk's checklist; (b) one-off smoke
now; (c) accept local coverage.

## F-009: The E2E walk checklist was authored but the walk never ran

**Raised:** 2026-07-12 (`Reports/2026-07-12-e2e-walk/CHECKLIST.md`, 122 items,
71 blocking with negative assertions); superseded in priority by the Currency
arc, then the dogfood walks partially overlapped it. **Status:** Awaiting
decision.

**Options:** (a) run it after Currency S3a (its original re-entry point);
(b) declare Dogfood-3/4 supersede it and archive the checklist with a note;
(c) diff the checklist against what the dogfoods covered and run only the gap.

## F-011: Unit-lane sibling for the generated-tree doc-ref pin

**Raised:** 2026-08-01 (PR #309 review, finding R-1 — minor, non-blocking).
**Status:** Awaiting decision.

The `# BL-090-DOC-REFS` generated-tree assertion lives in
`tests/test-currency-birth-stamp.sh`, an init.sh-invoking suite that runs only
in the ~3h full lane — so a REINTRODUCED shipped-depth link break survives
every PR-blocking check (the reviewer proved it by mutation). Optional
hardening, reviewer-designed: a hermetic unit-lane sibling that mirrors the
ship layout into a temp dir WITHOUT running init.sh — source
`scripts/lib/scaffold-shipped-set.sh` (the same source of truth the suite
already uses, no retyped cp list) — then run `lint-doc-anchors.sh --docs-dir`
against it. Fast, PR-blocking, closes the lane gap.

**Options:** (a) build it (small, well-specified); (b) accept full-lane-only
coverage — the class was just swept to zero and the docs change rarely.

## F-012: python3 is a hard, undocumented, language-independent dependency of upgrade-project.sh

**Raised:** 2026-08-01 (WP-5 prereq-honesty audit, triage finding; echoed by its review R-PH-3).
**Status:** Awaiting decision.

`scripts/upgrade-project.sh` (~line 1643) hard-fails (`print_fail "python3 is
required but not installed."` + exit) even for Rust/Go/etc. projects. The
message is plain-language but, unlike the jq check two lines above it, gives no
install hint; and python3 appears in no prerequisites table (defensible today:
post-init maintenance tool, fails loudly, near-universal binary).

**Options:** (a) one-line install hint in the message + a "maintenance tools"
docs note; (b) accept — the failure is loud and self-explanatory.

## F-010: Brownfield onboarding gap — still unfiled

**Raised:** 2026-07-12 session note ("real gap, NOT filed yet"); re-verified
2026-08-01 — zero `brownfield` mentions in the backlog. `init.sh` refuses
existing directories, so the framework cannot onboard an existing codebase.
**Status:** Awaiting decision.

**Options:** (a) file as a backlog entry sourced from our own surfaces (the
init.sh refusal path) with explicit scope choices; (b) declare out-of-scope for
the framework's mission and record that in README/CLAUDE.md; (c) leave here.
