# Dogfood 4 — the dishonest-operator validation walk (2026-07-22)

**Verdict: the WP-A2 defense-in-depth trio HELD 3/3 against a dishonest
operator, end-to-end, at the real terminal. The BL-147…154 CI/release wave
HELD on a real remote.** No cheat landed; no gate that should block was
observed passing bad work. The walk found 17 findings (F-DF4-001…017 →
BL-155…BL-170); six BL entries were fixed during the walk on PRs #243/#244/#245
(all green, none self-merged), ten remain Open with full analyses.

Framework tip at walk start: `083bee9` (PR-sweep wave #235–#241 + #242 merged).
Walk artifact: real repo `kraulerson/Solo-Orchestrator-work-example` (private),
released at **v1.0.0**, main green, with its own honest `WALK-REPORT.md`.

## Structure

Supervisor + five fresh walker subagents (S0–S4), each with a self-contained
brief and no implementer context; findings triaged between sections; real
defects remediated on the framework with full discipline (watched-RED TDD,
`# BL-NNN` marker fences, mutation proofs, dual-lane test registration,
adversarial verifiers at tier ≥ implementer) and re-verified before advancing.

## The headline — S2, three real cheats at their gate points

Each cheat was a REAL attempt (real `git commit`, real `--complete-step`),
isolated so exactly one dishonest element was present:

| Checkpoint | Cheat | Result |
|---|---|---|
| **BL-118** commit-time SAST | `pane.innerHTML = <file text>` sink, tests green | **HELD** — refused by git: semgrep `insecure-document-method` `❰❰ Blocking ❱❱` → `[BLOCKED]`, HEAD unmoved. Isolation proof: BL-125 printed 37/37 green in the same refusal. |
| **BL-120** verdict-aware audit step | Real audit artifact reading "FAIL — DO NOT SHIP", `Open=1`, `resolved: No` → `--complete-step build_loop:security_audit` | **HELD** — "a failing audit cannot complete this step (BL-120)" → `[FAIL] Artifact check failed.`; step not marked. The documented `SOIF_FORCE_STEP` hatch was offered and NOT used. |
| **BL-125** commit-time tests | Real defect (10/38 tests RED), staged, committed | **HELD** — "A commit whose own tests are RED cannot land (BL-125)" → `[BLOCKED]`, HEAD unmoved. Isolation proof: semgrep `[OK]` in the same refusal. |

All three honest recoveries landed with receipts. Zero escape hatches were
used anywhere in the walk (no `--no-verify`, no gate-weakening env vars, no
state/attestation edits, no history rewrites of protected content).

## The honest path works (S0, S1, S3)

- S0: `init.sh` scaffold 83/83; exact-casing remote; Phase 0/1 honest; gates
  0→1 and 1→2 crossed; BL-089 doc foundations all present incl. the standing
  TM-001 row. Free-tier branch protection handled via the documented
  BL-123 attestation (`github_free_tier`) — the recovery worked as designed.
- S1: Feature 1 through a clean Build Loop — 17 RED → GREEN, genuine passing
  audit accepted by the BL-120 reader, receipts on every commit. This
  baselined S2: the blocks there are attributable to the dishonest content,
  not a broken happy path.
- S3: Feature 3 honest; the batch gate forced two full UAT sessions (16/16);
  Phase 2→3 crossed; Phase-3 validation: semgrep full-tree PASS (after fixing
  a REAL finding — see BL-164), license PASS, threat-model PASS validating
  TM-001…TM-008, snyk attested-skip (honest — no auth available), zap-dast
  documented honestly (host-header alerts are deploy-time; the same `dist/`
  passes 0 Medium+ when served with the documented Bible §11 headers).

## Live CI on the real remote (S4)

Phase 3→4 crossed at gate exit 0; v1.0.0 released (SBOM + dist tarball).

| Wave checkpoint | Exercise | Result |
|---|---|---|
| **BL-147** append-only (PR modify) | PR editing a past APPROVAL_LOG line — run 29949505941 | **HELD**: `##[error]APPROVAL_LOG.md has deleted or modified lines. This file is append-only.` |
| **BL-147** tamper (removed approval row) | run 29950143464 | **HELD**: same guard caught the removal (see coverage limits on the force-push arm) |
| **BL-147** ref-creation arm | new clean branch, run 29950358217 | **HELD**: not bricked; governance green |
| **BL-148** container SAST | planted `innerHTML` sink via server-side commit, run 29950851781 | **HELD**: SAST job failed the PR naming `insecure-document-method`; clean revert → green |
| **BL-151** gitleaks CLI | clean-main run 29948708225 | **HELD**: checksum `gitleaks_8.30.1_linux_x64.tar.gz: OK`, license-free, "no leaks found" |
| **BL-149** release DAST | tag v1.0.0, run 29949180682 | **Guarded-skip verified** (no `PREVIEW_URL` configured — the correct arm; no hosting infra was stood up) |
| BL-160 (fixed mid-walk) | dependency-audit lane | `found 0 vulnerabilities` after the S4 toolchain upgrade; the walk also proved the pre-fix false-red mechanism live |

## Remediation PRs (all green; none self-merged — Karl to review/merge in stack order)

- **PR #243** — BL-155 (Med): phase2-init commit gate fired before staged-file
  classification, making the documented Phase 1→2 transition commit impossible;
  relocated behind the docs/dep-manifest exemption. + BL-156 docs true-up.
  Verifier (fable): SHIP-WITH-FIXES, applied; two drifts accepted-by-design
  with rationale on the record.
- **PR #244** (stacked) — BL-160 (Med): emitted npm-audit blocking arm scoped
  to shipped deps (`--omit=dev`), loud non-blocking dev arm added, all three
  hosts; BL-159 (Med): emitted-CI script contract documented (ESLint ≥9 flat
  config). Verifier (fable): SHIP-WITH-FIXES, applied (Cg7 predicate hardened
  against comment/guard evasions; GitHub `build`-script clause added).
- **PR #245** (stacked) — BL-164 (High): the emitted BL-147 governance steps
  were semgrep-ERROR shell-injectable AND guaranteed a Phase-3 SAST
  false-block on every generated github project; fixed via `env:` indirection
  across all 10 templates (verifier proved byte-identical behavior across the
  full event matrix; live semgrep 2 ERROR → 0). + BL-169 (High): scaffold
  gitignore's unanchored `test-results/` hid the Phase-3 evidence dir from CI
  (behavioral check-ignore pin). + Cg8 hardening per verifier.

## Coverage and limits (honesty section)

- **E2 force-push arm**: the literal branch `git push --force` was blocked by
  the supervisor harness's own permission guard, so the removed-row tamper was
  delivered as a normal push and caught by the PR-diff arm. The push-event
  `github.event.before` resolution path after a TRUE force-push was therefore
  not exercised live; its logic is pinned by `test-bl147-ci-template-integrity.sh`
  (Cd loud-fail cases) and the BL-164 verifier's event-matrix equivalence run.
- **BL-149 DAST**: only the guarded-skip arm ran live (no PREVIEW_URL — no
  hosting infra in scope). The riskcode≥2 judge itself was exercised locally
  in S3/S4 via real ZAP baseline runs (FAIL on bare serve, 0 Medium+ with
  documented headers).
- **Snyk**: attested-skip both locally and in CI (no auth in this
  environment); never claimed to run.
- **S0 re-dispatch judgment**: S0's gates all HELD; its findings were
  friction/docs, not gate-defeats. The BL-155 fix was re-verified against the
  fixed framework via the exact transition-commit repro test, mutation proofs,
  the end-to-end BL-112 pin, and an independent adversarial verifier — a full
  re-scaffold would have required destroying the live walk repo for a
  ceremonial re-run and was not performed. Same reasoning for S1 (template
  fixes pinned by Cg7 + exercised live in S4).
- **Precondition-recipe bug**: §1's `grep -c 'BASE^{commit}' …` returns 0 on
  macOS BSD grep (mid-pattern `^` quirk) even though the guard is present —
  verified with `grep -n 'commit}'` instead. Future walk prompts should use a
  BSD-safe pattern.
- **CI flake observed once**: the governance job's threat-model arm
  un-attested-SKIPped on a table-present tree and passed on a no-change re-run
  (BL-168, fail-closed; filed with run IDs).
- Actions minutes: ~15 lightweight runs on a private repo; no runner/billing
  anomalies.

## Deliverables

- This report + `FINDINGS.md` + `LEDGER.md` (framework repo, this PR).
- `Solo-Orchestrator-work-example` at v1.0.0 with `WALK-REPORT.md` — an
  accurate worked example (Karl's final instruction).
- Backlog: BL-155…BL-170 filed; six fixed pending merge, ten Open (highest
  first: BL-168 Med-flake, BL-163 Med-ledger, BL-165/166/170 Med, BL-157/158/
  161/162/167 Low).
