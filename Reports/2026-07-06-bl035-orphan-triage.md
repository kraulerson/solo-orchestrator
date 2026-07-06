# BL-035 / BL-052 Orphan-Test Disposition Triage

**Date:** 2026-07-06
**Source:** read-only triage agent (Wave-1 background analyst), corroborated by standalone runs.
**Scope:** the 50 files on `scripts/lint-tests-registered.sh::KNOWN_ORPHANS_PENDING_BL035` (tests parked off any aggregator → running zero times) + the BL-052 un-invoked-aggregator question.

## Summary counts (50 orphans)

| Disposition | Count |
|---|---|
| REGISTER | 44 |
| MERGE | 2 |
| DELETE | 1 |
| UNCERTAIN (needs Karl fork) | 3 |

Nearly all target **live product code** — the bridge is 44 genuinely-valuable suites running zero times, not dead weight. REGISTER target is `tests/full-project-test-suite.sh` (the only delegating aggregator) unless noted.

## Non-REGISTER dispositions (the ones needing attention)

**DELETE (1):**
- `test-init-other-host-attestation.sh` — fully superseded by the registered `test-init-fail-status-propagation.sh` (same fixture/invariant); T2 dups non-interactive N9. No unique assertion.

**MERGE (2):**
- `test-bypass-audit-schema.sh` → fold T1 (ledger `.[0]` shape) into `test-bl029-integration.sh`; T2/T3 dup out-of-band + bl029.
- `test-upgrade-personal-to-sponsored-poc.sh` → fold T1 (personal→sponsored_poc R3-A guard) into `edge-cases-scripts.sh` near E58/E60; retire T2 (dup E27) / T3 (dup E60).

**UNCERTAIN — 3 forks needing Karl's judgment:**
1. `test-bl030-calibration-replay.sh` — register as the canonical 3-level detector e2e, OR fold its one net-new check into bl029 and delete (it ~dups out-of-band T1-3).
2. `test-upgrade-paths.sh` — 581-line grab-bag; register wholesale, OR decompose to its unique T4 (BL-004 flat→per-host CI migration) / T5 (upgrade-time vendored-skills) / T6 (POC-strip) and drop the overlaps.
3. `test-poc-modes.sh` — its T5 (`--to-private-poc` stays personal) is CORRECT per current product, but the REGISTERED `edge-cases-scripts.sh` E60 asserts the OPPOSITE and is stale/RED. Fork: fix+register poc-modes and fix/retire E60, OR consolidate into edge-cases-scripts. (See cross-cutting finding #3.)

**REGISTER (44)** — into `full-project-test-suite.sh` unless noted (`github-free-tier-403` → `host-drivers/github.test.sh`):
test-bl029-integration, test-bypass-audit-integrity, test-bypass-audit-lib, test-bypass-detector, test-bypass-patterns, test-bypass-sentinel, test-out-of-band-detector, test-escalate-to-user, test-check-gate, test-check-changelog-filter, test-check-commit-message, test-check-phase-gate, test-check-phase-gate-counter-sanitizer, test-gate-principles, test-filesystem-gate-install, test-enforcement-level-init, test-enforcement-level-lib, test-enforcement-level-reconfigure, test-init-atomic-finalize, test-init-no-remote-creation, test-init-non-interactive, test-init-schema-phase-gate, test-github-free-tier-403, test-vendored-skills-install, test-upgrade-non-interactive, test-upgrade-bl030-backfill, test-upgrade-to-production-preconditions, test-upgrade-to-production-warn, test-verify-install-bl030-coverage, test-test-gate-counter-sanitizer, test-test-gate-null-handling, test-validate-counter-sanitizer, test-record-claude-commit, test-unrecord-feature, test-session-test-gate-check-merge, test-pending-approval, test-process-checklist-auto-advance, test-process-checklist-classifier, test-phase-finalize, test-platform-security-bugs-closer (after T4b path fix), test-docs-cluster-six-pack, test-specs-plans-remaining-quartet, test-lint-uat-scenarios, test-pre-commit-gate-terminal-mode (needs BL-074-class scaffold — already fixed on main).

## Cross-cutting findings (NOT in original BL-035 scope — filed separately)

1. **Stale `--language javascript`/`ts` fixture drift** (→ its own item): `init.sh` dropped `javascript` for `--platform web` (accepted set now `csharp/go/java/kotlin/other/python/rust/typescript`). ~10 orphan fixtures still pass `javascript`/`ts`, so init aborts and the suite fails downstream. Mechanical one-token sed per fixture. MUST land before/with wiring or ~10 registrations turn CI red. Affected: bl029-integration, bl030-calibration-replay, bypass-audit-schema, init-atomic-finalize, init-non-interactive (N7 `ts`), upgrade-bl030-backfill, verify-install-bl030-coverage, poc-modes (T1/T4), enforcement-level-init, enforcement-level-reconfigure.
2. **`test-platform-security-bugs-closer.sh` T4b** — red for a BL-046 docstring-probe path (`helpers.sh`→`helpers-core.sh`); one-line test-path fix.
3. **Live test-vs-test contradiction** (→ its own item): orphan `test-poc-modes.sh` T5 and REGISTERED `edge-cases-scripts.sh` E60 assert OPPOSITE outcomes for `upgrade-project.sh --to-private-poc` from personal. Current product (upgrade-project.sh:692-711, tier-crosscheck-3) makes it **personal** → T5 correct, E60 stale/RED. E60 is a bug in a registered test.

## BL-052 policy recommendation: Policy A (refined) — wire, don't delete

The 3 un-invoked aggregators (`edge-case-test-suite.sh`, `known-bugs-test-suite.sh`, `upgrade-path-tests.sh`) each hold substantial, largely-unique real tests — none is empty. **Also confirmed: CI (`.github/workflows/lint.yml`) runs ZERO test aggregators — only 6 lint scripts; `full-project-test-suite.sh` is manual-only** (this is filed as its own high finding). Recommendation: wire the 3 into the master run (or build the missing `tests/run-all.sh` orchestrator), delete none; prune within during the port where overlap exists.

## Suggested wiring wave (after decisions)

**Chunk 0 — prerequisites (mechanical, must land first):** (a) sed stale `javascript`/`ts`→`typescript` across the ~10 fixtures; (b) fix `test-platform-security-bugs-closer.sh` T4b probe path. (BL-074 scaffold fix already merged.)

Then 8 product-area PRs (grouped to localize `full-project-test-suite.sh` registration conflicts): 1 Bypass/governance · 2 Gate/check family · 3 Enforcement-level · 4 Init family (incl. DELETE init-other-host-attestation, github-403→host-drivers) · 5 Upgrade family (incl. MERGE personal-to-sponsored-poc) · 6 Test-gate/counter-sanitizer/session · 7 Process-checklist/pending/poc (resolve poc-modes fork + fix E60) · 8 Docs/specs/lint. Then **9 BL-052:** wire the 3 aggregators into the master (or new `tests/run-all.sh`); drain `KNOWN_ORPHANS_PENDING_BL035` to empty and re-enable that as the closing invariant.
