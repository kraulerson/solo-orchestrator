# Dogfood 4 — findings register (F-DF4-001…017 → BL-155…BL-170)

Every finding reproduced before filing; walker mistakes and known-open items
were triaged out (see LEDGER.md). "Fixed" = implemented on a green walk PR,
pending Karl's merge.

| ID | Section | BL | Sev | Status | One-line |
|---|---|---|---|---|---|
| F-DF4-001 | S0 | BL-155 | Med | **Fixed** PR #243 | phase2-init gate fired before staged-file classification — the documented Phase 1→2 transition commit ("Commit both files together") was impossible |
| F-DF4-002 | S0 | BL-156 | Low | **Fixed** PR #243 | builders-guide still called the Phase-0 intermediates check "advisory"; it has been fully blocking since BL-114 |
| F-DF4-003 | S0 | BL-157 | Low | Open | `--no-remote-creation` + manual remote leaves remote markers unrecorded → undocumented two-step `check-gate.sh --repair` dance before free-tier attestation |
| F-DF4-004 | S0 | BL-158 | Low | Open | `--gate <name>` header prints the forced target phase as "Current phase" |
| F-DF4-005 | S1 | BL-159 | Med | **Fixed** PR #244 | emitted CI demands `npm run lint`/`npm test` (+`build` on GitHub) scripts nobody documented; ESLint ≥9 flat-config edge undocumented |
| F-DF4-006 | S1 | BL-160 | Med | **Fixed** PR #244 | emitted npm-audit step audits devDependencies — dev-only advisories with no in-major fix red the lane forever (false-FAIL doctrine) |
| F-DF4-007 | S1 | BL-161 | Low | Open | tracked `bypass-audit.json` self-appends a receipt per commit — tree perpetually one row dirty (design decision recorded) |
| F-DF4-008 | S2 | BL-162 | Low | Open | BL-120 audit gate double-prints its OPEN-finding warning when slug == name |
| F-DF4-009 | S2 | BL-163 | Med | Open | BLOCKED commit attempts leave no `bypass-audit.json` row — SAST/test refusals invisible to the enforcement ledger (enforcement intact; forensics understated) |
| F-DF4-010 | S3 | BL-164 | **High** | **Fixed** PR #245 | emitted BL-147 governance steps semgrep-ERROR shell-injectable → guaranteed Phase-3 SAST false-block on every generated github project |
| F-DF4-011 | S3 | BL-165 | Med | Open | Phase-3 DAST vs a static app's bare preview always FAILs on deploy-time host-header alerts — needs a hardened-serve harness/guidance |
| F-DF4-012 | S3 | BL-165 | Med | Open | (same entry) CSP non-inheriting directives (`form-action`/`frame-ancestors`/`base-uri`) — web.md note shipped on PR #245 |
| F-DF4-013 | S3 | BL-166 | Med | Open | `--gate phase_2_to_3` exit code dominated by Phase 3→4 readiness — legitimate crossing reads as "8 inconsistencies — blocking" |
| F-DF4-014 | S3 | BL-167 | Low | Open | BL-072 TDD warn counts `.claude/*.json` state files as impl files |
| F-DF4-015 | S4 | BL-168 | Med | Open (investigate) | CI governance threat-model arm intermittently un-attested-SKIPs on a table-present tree; no-change re-run passes (runs 29951076488 att.1 vs 2) |
| F-DF4-016 | S4 | BL-169 | **High** | **Fixed** PR #245 | scaffold gitignore's unanchored `test-results/` hides `docs/test-results/` — 3→4 gate fails on every fresh CI checkout while passing locally |
| F-DF4-017 | S4 | BL-170 | Med | Open (design) | fill-in-place APPROVAL_LOG gate templates conflict with the append-only CI guard; masked historically by the red audit lane halting governance steps |

## Triaged as NOT defects

- S0/F2 free-tier branch protection 403 → the BL-123/BL-126 attestation design
  worked as documented (used honestly).
- S0/F5 Appendix-D market-signal gate presence-only → deliberate WARN-first
  per BL-102's closure ("escalate later" already on record).
- S1 jsdom `File` lacking `arrayBuffer()`/`text()` → environment reality;
  handled project-side (FileReader path), documented in the project Bible.
- S2/S3 BL-072 warns on honest `refactor:`/`fix:` commits → tier-based
  by-design behavior (the `.claude` mislabel within it IS filed, BL-167).
- S3 `feature_recorded`-before-commit ordering trip → the gate's own comment
  documents commit-then-record; walker recovered per the documented order.
  Possible guide-clarity polish, folded into the report only.
- S4 local-hook/CI SAST equivalence forcing server-side plant delivery → the
  CI-as-backstop scenario working as intended (positive control).
