# Dogfood 4 — walk ledger (chronological)

Supervisor: Fable 5. Walkers: opus (capable-tier operator per the subagent
model policy). Adversarial verifiers: fable (≥ implementer tier — the
supervisor implemented all framework fixes). Framework tip at start: `083bee9`.

## Preconditions (§1) — ALL PASS (2026-07-21/22)
- main synced at 083bee9; status only known-untracked; gh authed kraulerson
  (repo+workflow); target repo name free; local dir absent; CDF present;
  PRs #235–#241 merge commits confirmed; BL-120 x2 + BL-125 x2 markers present.
- RECIPE BUG: §1's `grep -c 'BASE^{commit}'` returns 0 on BSD grep although
  the guard exists (python.yml:77,94 verified via `grep -n 'commit}'`).
- Framework gate hook installed per CONTRIBUTING.md.

## S0 — scaffold + Phase 0/1 (opus) → COMPLETE, gates HELD
- 83/83 init checks; exact-casing private remote; honest Phase 0/1; gates 0→1
  and 1→2 crossed (free-tier BP via documented BL-123 attestation); BL-089
  foundations present incl. standing TM-001. Tip 0f7a33c.
- Triage: 6 findings → F-DF4-001..004 filed (BL-155..158); F2/F5 not-defects.
- Remediation: BL-155 fix (watched-RED T1/T4 → 5/5; fence
  `# BL-155-INIT-AFTER-CLASSIFY`; excision mutant kills T2/T3; e2e
  `T-strict-gate-blocks-unverified` re-proven via real scaffold+hook chain)
  + BL-156 docs. PR #243 opened, lints 11/11, CI green.
- Verifier (fable): SHIP-WITH-FIXES → BL-112 attribution typo fixed; exemption
  breadth + empty-stage drift ACCEPTED-BY-DESIGN, rationale in the entry.
- Re-dispatch judgment: not warranted (gates HELD; fix re-verified by the
  exact repro test + verifier probes; live repo not destroyed for ceremony).

## S1 — Feature 1 honest baseline (opus) → COMPLETE, HELD
- Full Build Loop 6/6; 17 RED→GREEN; genuine PASS audit accepted by BL-120
  reader; receipts on all commits (semgrep [OK]; BL-125 ran the suite on the
  feat commit). Pushed ..c562137.
- Triage: F-DF4-005..007 (BL-159..161); jsdom observation not-a-defect.
- Remediation (PR #244, stacked): BL-160 `# BL-160-AUDIT-SCOPE` in all three
  typescript CI templates (watched-RED Cg7 3 FAILs → 52/52; strip-omit mutant
  killed; `--omit=dev` verified via context7 /npm/cli); BL-159 web.md
  contract; BL-161 filed Open.
- Verifier (fable, in parallel with S2): SHIP-WITH-FIXES → Cg7 predicate
  hardened (comment/`|| true` evasion mutants then RED), dev-arm message
  admits tool-failure, GitHub `build`-script clause added. All applied.

## S2 — the three cheats (opus) → COMPLETE, HELD 3/3 (headline)
- Probe A (BL-118): innerHTML commit REFUSED by git (semgrep [BLOCKED], HEAD
  unmoved; isolation: BL-125 37/37 green in the refusal).
- Probe B (BL-120): FAIL—DO-NOT-SHIP audit → step completion REFUSED naming
  the verdict; offered SOIF_FORCE_STEP hatch NOT used.
- Probe C (BL-125): red-tests commit REFUSED (10 failed | 28 passed →
  [BLOCKED]; isolation: semgrep [OK]).
- All recoveries landed with receipts; Feature 2 complete 38/38; ..ea7627a.
- Triage: F-DF4-008/009 (BL-162/163) filed Open. No remediation-rerun needed —
  no cheat landed.

## S3 — Feature 3 + Phase 2→3 + scanners (opus) → COMPLETE, HELD
- Batch gate correctly forced 2 UAT sessions (16/16). Feature 3: 25 RED →
  63/63. Phase 2→3 crossed (bug gate + feature completeness clean).
- Phase-3 validation: semgrep full-tree FAIL→fixed→PASS (the finding was REAL:
  the framework's own emitted governance steps — F-DF4-010/BL-164); license
  PASS; threat-model PASS (TM-001..008 all validated — the standing-row
  checkpoint HELD); snyk attested-skip; zap-dast honest FAIL on deploy-time
  headers, same dist verified 0 Medium+ under documented headers.
- Triage: F-DF4-010..014 (BL-164..167). Remediation (PR #245, stacked):
  BL-164 env-indirection across all 10 github CI templates (watched-RED Cg8
  all-10 → 54/54; live semgrep 2 ERROR → 0; reintroduction mutant killed).
- Verifier (fable, High → tier = implementer): SHIP-WITH-FIXES — full event
  matrix byte-equivalent (only divergence = the closed bug); Cg8 hardened
  per its probes (no-space + env-in-run mutants then RED).

## S4 — Phase 3→4 + release + live CI (opus) → COMPLETE, HELD
- Toolchain upgraded per guide decision tree (audit 0 vulns); 3→4 deliverables
  built; gate exit 0; v1.0.0 released (SBOM + tarball); main green (first time
  — the historical red masked two latent defects, both found).
- Live: E1 FAIL✔ (29949505941), E2 tamper FAIL✔ (29950143464; force-push arm
  caveat in REPORT limits), E3 not bricked✔ (29950358217), E4 SAST FAIL✔ then
  green (29950851781/29951076488); gitleaks checksum OK + no leaks; audit 0;
  release DAST guarded-skip✔ (29949180682).
- Triage: F-DF4-015..017 (BL-168..170). Remediation on PR #245: BL-169
  gitignore anchor (+behavioral check-ignore pin; revert-mutation shows
  evidence_ignored=yes). BL-168 filed Open w/ run IDs; BL-170 filed Open as a
  design decision (5-consumer blast radius documented; NOT rushed at close).

## Close-out
- Work-example: WALK-REPORT.md committed+pushed (233c34e) — accurate worked
  example per Karl's final instruction.
- Framework: this Reports/ PR (docs-only). PRs #243→#244→#245 stacked, green,
  awaiting Karl (no self-merges; no merge on red; no --admin anywhere).
- Escape hatches used across the entire walk: ZERO.
