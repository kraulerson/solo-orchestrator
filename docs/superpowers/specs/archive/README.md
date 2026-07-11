# Spec archive — `docs/superpowers/specs/archive/`

This directory holds **design specs** from `docs/superpowers/specs/` whose
design has **shipped** — the implementation landed on `main` (each spec's
sibling implementation plan is already archived under
[`../../plans/archive/`](../../plans/archive/README.md) with the shipping
PR/commit). Specs are archived, never deleted, so the trail
spec → plan → PR/commit → shipped code stays intact and citable.

## Convention (mirrors the plans archive, stub-at-old-path style)

When a spec's design has shipped:

1. Prove it shipped — cross-check `git log` / the sibling archived plan /
   `solo-orchestrator-backlog.md` for the PR or commit that landed the design.
2. `git mv docs/superpowers/specs/<name>.md
   docs/superpowers/specs/archive/<name>.md` (preserves history; the archived
   copy stays **byte-for-byte intact** — several specs are still read as live
   fixtures by `tests/test-specs-plans-*.sh` / `tests/test-intake-wizard-fixes.sh`,
   so their content must not drift).
3. Leave a short **pointer stub** at the old top-level path: H1 title, a
   one-line SHIPPED status with the PR/commit citation, and links to the
   archived copy and the sibling implementation plan. The stub keeps every
   existing citation of the old path resolving — prose references in
   `solo-orchestrator-backlog.md`, cross-references from other specs, and
   path citations in read-only scripts (`scripts/host-drivers/github.sh`,
   `scripts/reconfigure-project.sh`) all land on the stub and can click
   through.
4. If a test reads the spec **content** (not just its path), repoint that
   test's spec-path variable at the archived copy — the content is intact, so
   the assertions keep passing. (Done here for the intake, phase-audit, and
   host-aware fixtures.)
5. Never delete an archived spec — some are live regression fixtures.

## What stays in `docs/superpowers/specs/` (not archived)

A design spec stays at the top level as long as its implementation has **not**
shipped yet. Don't archive a spec just because it looks old; confirm shipped
status against `git log` / the sibling plan first.

## Contents

All 16 April 2026 design specs — every one's implementation shipped (see each
stub for the PR/commit). Fixtures flagged **do not delete**: the intake-wizard,
phase-audit, and host-aware-repo-gate specs.
