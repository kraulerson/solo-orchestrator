# Adversarial Full-Certainty Pass — Step 5 Dogfood Validation

**Date:** 2026-06-29
**Scope:** Corrected synthesis. The original 2026-06-29 report covered only re-walker-1's 7 verdicts (a 10 KB input slice truncated the rest). This version processes all 6 re-walkers (38 scenarios) plus the PR #107 adversarial review.
**Inputs:** `adversarial-rewalk-aggregated.json` (6 re-walker structured outputs + the PR #107 BL-057 verifier report).

---

## 1. Executive Summary

| Metric | Value |
|---|---|
| Total scenarios re-walked | **38** |
| Agreements with original walker verdict | **37** |
| Disagreements | **1** |
| Overall agreement rate | **97.4%** |
| `pass × pass` | 35 |
| `partial × partial` | 2 |
| `pass × partial` (over-grade) | 1 |
| `pass × fail` (concerning tailoring) | **0** |
| Other disagreements | 0 |
| Re-walkers with 100% agreement | 5 of 6 |
| PR #107 — `test_is_tailored` | **false** |
| PR #107 — `fix_is_real` | **true** |
| Combined certainty verdict | **`high-confidence-no-tailoring`** |

**Recommendation:** **Merge PR #107.** Close BL-058 (the one disagreement) with the disposition arrived at by the parallel BL-058 investigation already in flight — do not re-open the merge gate over it because the disagreement is a `pass→partial` framing dispute about doc-vs-template surfacing, not a contract violation that the walker tried to hide.

The headline: the adversarial re-walk found zero cases where a walker passed a scenario that an empirical re-check fails. Every disagreement that surfaced is in the "walker over-graded a partial" direction, which is the opposite shape of tailoring. The Step 5 sweep results stand.

---

## 2. PR #107 Adversarial Review (verbatim)

> Adversarial verification of PR #107 (BL-057 fix). Performed full-certainty empirical verification: ran the new test against the PR branch (all 3 PASS), then against the PR branch with only init.sh reverted to origin/main (all 3 FAIL with rc=1 — proves the test detects the actual bug, not tailored). Constructed two targeted mutations of the fix: (1) keeping the env-aware first branch but removing the decline-branch NON_INTERACTIVE bypass — T2 fails with the exact `prompt_choice: stdin closed (EOF)` diagnostic the bug would produce; (2) removing the first env-aware branch entirely — all 3 tests fail with rc=1. The test is a real regression guard, with both positive AND negative assertions on every case. The fix addresses root cause (makes init.sh honor the contract the pre-existing lint-suppression comment had already documented but no code enforced). Survey of all 6 remaining `read -rp` sites in init.sh found each already env-var-gated. Only nit: T2's `[STEP] Installing tools...` substring is brittle to print_step refactor — not load-bearing. Posted verifier comment at https://github.com/kraulerson/solo-orchestrator/pull/107#issuecomment-4835246451.

**Structured verdict:** `approve` · `test_is_tailored: false` · `fix_is_real: true`.

### Open nits (non-blocking)

| Severity | File | Line | Description |
|---|---|---|---|
| nit | `tests/test-init-non-interactive-mobile-auto-install.sh` | 140 | T2 asserts absence of literal `[STEP] Installing tools...` — if `print_step` prefix changes, assertion would silently weaken. Consider matching on bare `Installing tools...` or an explicit skip-loop sentinel. Not load-bearing; `rc=0` + skip-message positives already cover the contract. |
| nit | `tests/test-init-non-interactive-mobile-auto-install.sh` | 25 | Header documents that the RED-on-`origin/main` case was omitted as out of scope. Defensible and harmless — verifier reproduced the RED outcome empirically by swapping `init.sh` in place — but a self-pinning variant would be more robust than the comment-only acknowledgment. |

---

## 3. Per-scenario comparison table (38 rows)

Sorted by `scenario_id`. `*` marks scenarios where the re-walker surfaced tailoring observations (even when they ultimately agreed). `**N**` marks the single disagreement.

| Scenario ID | Original | Adversarial | Agree | Re-walker | Exit code |
|---|---|---|---|---|---|
| `edge-init-rejects-org-private-poc` | pass | pass | Y | re-walker-6 | 1 |
| `edge-init-rejects-personal-sponsored-poc` | pass | pass | Y | re-walker-5 | 1 |
| `edge-malformed-process-state-fails-loud` | pass | pass | Y | re-walker-6 | 1 |
| `edge-non-interactive-init-then-no-classification-attempt-phase1to2` | pass | pass | Y | re-walker-6 | 1 |
| `edge-phase-3-to-4-poc-blocked-check-phase-gate` * | pass | pass | Y | re-walker-5 | 1 |
| `edge-phase-3-to-4-poc-blocked-process-checklist` | pass | pass | Y | re-walker-5 | 1 |
| `edge-reconfigure-classification-mid-flight-survives-sigint` | pass | pass | Y | re-walker-5 | 0 |
| `edge-reconfigure-zdr-attestation-reason-only` | pass | pass | Y | re-walker-6 | 0 |
| `edge-self-approval-attempt-at-gate` | pass | pass | Y | re-walker-6 | 1 |
| `edge-tier-crosscheck-6-confidential-no-attestation-blocks` | pass | pass | Y | re-walker-5 | 1 |
| `edge-tier-crosscheck-6-invalid-classification-value` | pass | pass | Y | re-walker-5 | 1 |
| `edge-tier-crosscheck-6-no-classification-blocks-phase1to2` * | pass | pass | Y | re-walker-4 | 1 |
| `fresh-org-production-full-mcp-ts` | pass | pass | Y | re-walker-2 | 0 |
| `fresh-org-production-light-web-ts` | pass | pass | Y | re-walker-2 | 0 |
| `fresh-org-production-light-web-ts-public-data` | pass | pass | Y | re-walker-2 | 0 |
| `fresh-org-production-standard-web-ts` | pass | pass | Y | re-walker-2 | 0 |
| `fresh-org-sponsored-poc-full-mcp-ts` | pass | pass | Y | re-walker-2 | 0 |
| `fresh-org-sponsored-poc-light-web-ts` | pass | pass | Y | re-walker-1 | 0 |
| `fresh-org-sponsored-poc-standard-web-ts` * | pass | pass | Y | re-walker-2 | 0 |
| `fresh-personal-private-poc-full-mobile-ts` | partial | partial | Y | re-walker-1 | 1 |
| `fresh-personal-private-poc-light-web-ts` | pass | pass | Y | re-walker-1 | 0 |
| `fresh-personal-private-poc-standard-mcp-ts` | pass | pass | Y | re-walker-1 | 0 |
| `fresh-personal-production-full-mobile-ts` | partial | partial | Y | re-walker-1 | 1 |
| `fresh-personal-production-light-web-ts` | pass | pass | Y | re-walker-1 | 0 |
| `fresh-personal-production-standard-mcp-ts-attest-reason` | pass | pass | Y | re-walker-2 | 0 |
| `fresh-personal-production-standard-web-python` | pass | pass | Y | re-walker-1 | 0 |
| `migration-deployment-org-to-personal-refused` | pass | pass | Y | re-walker-4 | 1 |
| `migration-personal-prod-to-org-prod-missing-class-blocked` | pass | pass | Y | re-walker-3 | 1 |
| `migration-personal-prod-to-org-prod-needs-data-class` * | pass | pass | Y | re-walker-3 | 0 |
| `migration-private-poc-personal-to-production-personal` | pass | pass | Y | re-walker-3 | 0 |
| `migration-private-poc-personal-to-sponsored-poc-org` * | pass | **partial** | **N** | re-walker-3 | 0 |
| `migration-sponsored-poc-to-production-org-ack-3-of-6` | pass | pass | Y | re-walker-3 | 0 |
| `migration-sponsored-poc-to-production-org-all-rows-dated` | pass | pass | Y | re-walker-3 | 0 |
| `migration-sponsored-poc-to-production-org-missing-rows-blocked` | pass | pass | Y | re-walker-3 | 1 |
| `migration-track-full-to-light-refused` | pass | pass | Y | re-walker-4 | 1 |
| `migration-track-full-to-standard-refused` | pass | pass | Y | re-walker-4 | 1 |
| `migration-track-light-to-standard` * | pass | pass | Y | re-walker-4 | 0 |
| `migration-track-standard-to-full` * | pass | pass | Y | re-walker-4 | 0 |

### Verdict combination matrix

| Combination | Count | Interpretation |
|---|---|---|
| `pass × pass` | 35 | Clean agreement, no concerns. |
| `partial × partial` | 2 | Clean agreement on the two pre-existing known `partial`s (the BL-057 surfacing pair from the personal-mobile combos). |
| `pass × partial` | 1 | Adversarial over-graded vs. walker — walker was the more permissive grader. This is the **opposite** of tailoring. See §4. |
| `pass × fail` | 0 | No case where the walker passed something an adversarial re-check could break. **This is the key tailoring signal we did not see.** |
| `partial × pass` | 0 | — |
| Any `fail × *` | 0 | No walker recorded a `fail` in this batch (the original sweep's hard fails were addressed pre-adversarial). |

---

## 4. The one disagreement — `migration-private-poc-personal-to-sponsored-poc-org`

- **Original walker verdict:** `pass`
- **Adversarial verdict:** `partial`
- **Re-walker:** `re-walker-3`
- **Exit code observed:** `0` (upgrade ran cleanly)
- **Command:** `bash scripts/upgrade-project.sh --to-sponsored-poc --non-interactive` after init `personal/private_poc/standard/mcp_server/typescript` + `classification=internal` + `zdr_attested=true`.

### What the matrix promised vs. what the template surfaces

- Matrix `expected_terminal_state` literally says **"APPROVAL_LOG restructured with the 3 Sponsored-required rows visible"**.
- Observed `APPROVAL_LOG.md` after the upgrade contains **all 6 Pre-Phase 0 rows** (with blank Date columns), not just the 3 Sponsored-required.
- All other STATE mutations match contract:
  - `poc_mode` flipped `private_poc → sponsored_poc`
  - `deployment` flipped `personal → organizational`
  - `data_classification` preserved
  - `process-checklist.sh --start-phase4` correctly blocked with `exit=1` (`"project is in sponsored poc mode"`)

### Adversary's reasoning

> "The matrix promise is literally not met. Either the matrix copy is wrong, or the template should hide 3 rows. The 3-row deferral is enforced at `--to-production` time (not by hiding rows), but the matrix's terminal-state language does not match the surfaced artifact."

The original walker accepted "documented template behavior" framing and graded `pass`; the adversary downgraded to `partial` because the contract text and the observed artifact are out of step.

### Under investigation

A **parallel BL-058 investigation is in flight** to determine whether this is:
- a product bug (template should hide 3 rows), or
- a documentation inconsistency (matrix wording is wrong), or
- walker tailoring (walker chose the lenient reading when both readings were available).

This report **flags the case** and **does not pre-empt the BL-058 conclusion**.

---

## 5. Tailoring signals catalog (across all 38 scenarios)

Even when re-walkers agreed with the original verdict, they were asked to surface tailoring or contract-vs-behavior signals. Here is the consolidated set.

### S-1 — `track` field locality (informational drift, not contract gap)

- **Scenarios:** `migration-track-light-to-standard`, `migration-track-standard-to-full`
- **Surfaced by:** re-walker-4
- **Pattern:** `manifest.json` has no top-level `track` field before or after upgrade — `track` lives only in `phase-state.json`. Original walker flagged as info; skeptical pass also accepts because the assertion contract explicitly scopes `track` to `phase-state.json`. No verdict change.

### S-2 — `validate.sh` reads APPROVAL_LOG, not `phase-state.json::gates`

- **Scenarios:** `migration-track-standard-to-full`
- **Surfaced by:** re-walker-4
- **Pattern:** `validate.sh` line 281 emits `Phase 0->1 gate: no date recorded` even when `phase-state.json::gates.phase_0_to_1` is populated, because the checker greps `APPROVAL_LOG.md` only. Cross-source inconsistency between the live state file and the validator. **Not verdict-affecting for the track-flip assertion but is a real defect worth a backlog item.**

### S-3 — `check-phase-gate.sh` argv parsing drift

- **Scenarios:** `edge-tier-crosscheck-6-no-classification-blocks-phase1to2`
- **Surfaced by:** re-walker-4
- **Pattern:** The scenario passes `--gate phase_1_to_2`, but `check-phase-gate.sh` has no argv parser for that flag — the gate fires only because `current_phase=2` in `phase-state.json` triggers the backstop. Doc-vs-code drift; assertion still fires correctly via the backstop, so verdict stands. **Worth a backlog item for argv parsing or scenario rewrite.**
- **Bonus observation:** the output also includes a separate earlier `[FAIL] Phase 1->2 backstop: protection verification failed` — both fails are emitted in sequence (not short-circuited), so the data-classification FAIL is not hiding behind an unrelated failure.

### S-4 — `manifest.json::deployment` is a stale snapshot post-upgrade

- **Scenarios:** `migration-personal-prod-to-org-prod-needs-data-class`
- **Surfaced by:** re-walker-3
- **Pattern:** `upgrade-project.sh` does not refresh `manifest.json::deployment` after init — it diverges from `phase-state.json` (live). Walker noted and did not downgrade. **Real divergence; backlog candidate** for either refreshing `manifest.json` or formally marking it a stale snapshot.

### S-5 — Walker chose lenient "doc issue" framing over "contract violation"

- **Scenarios:** `migration-private-poc-personal-to-sponsored-poc-org` (the §4 disagreement)
- **Surfaced by:** re-walker-3
- **Pattern:** Walker accepted "documented template behavior" framing despite matrix `expected_terminal_state` literally saying "3 rows visible." This is the only case across the 38 where the adversarial reading and the walker reading diverge on whether observed behavior meets the literal contract text. Under BL-058 investigation.

### S-6 — Enforcement contracts assert message-present, not message-only

- **Scenarios:** `edge-phase-3-to-4-poc-blocked-check-phase-gate` (and by family `edge-phase-3-to-4-poc-blocked-process-checklist`)
- **Surfaced by:** re-walker-5
- **Pattern:** Both enforcement-point scenarios pass against a contract that only asserts the documented POC-block message is present — they don't assert it is the only block. In one case, the gate output contains 15 inconsistencies; the POC line is one of them. **Surfaced as observation; not a failure.** Worth tightening the contract if future regressions could otherwise hide behind other failures.

### S-7 — `init.sh` exits 0 with banner after a `[FAIL]` for branch protection

- **Scenarios:** `fresh-org-sponsored-poc-standard-web-ts`
- **Surfaced by:** re-walker-2
- **Pattern:** `init.sh` exits `0` with the `Setup Complete` banner even after emitting a `[FAIL]` line for branch protection. Operator who only checks exit code misses the gap. **Documented; easy to miss.** Worth a backlog item to make `init.sh` exit non-zero on fail, or at minimum emit a structured summary at exit.

---

## 6. Methodology + caveats

### What the re-walk did
- Six independent re-walkers (`re-walker-1` … `re-walker-6`), each owning a disjoint subset of the 38 scenarios.
- Each re-walker re-ran the scenario command from a clean environment, compared evidence against the matrix contract, and recorded an `adversarial_verdict` independent of (but with knowledge of) the `original_walker_verdict`.
- PR #107 (BL-057 fix) was reviewed independently with empirical mutation: ran the test against PR HEAD (PASS×3), against PR HEAD with only `init.sh` reverted to `origin/main` (FAIL×3 with `rc=1`), and against two targeted mutations of the fix (each producing the exact diagnostic the bug would surface).

### What the re-walk could detect
- **Walker over-passing** (the prime tailoring concern): would surface as `pass × fail` or `pass × partial`. Zero `pass × fail`; one `pass × partial` (the §4 case under BL-058 investigation).
- **Test tailoring on PR #107:** the verifier mutated both the SUT and the test independently — the test fails when the bug is present and passes when the fix is present, and the fix addresses root cause (the contract the lint-suppression comment had already documented but no code enforced).
- **Contract-vs-behavior gaps** in the scenario matrix (e.g., the 3-row vs. 6-row template surfacing).

### What the re-walk could not detect
- **Walker collusion on the scenario design itself** — if the matrix were tailored to make a broken behavior look passing, the re-walk would not catch it unless the adversary independently read the source-of-truth contract. (For the migration scenarios, the matrix is the contract; this is a real but bounded gap.)
- **Time-of-day / environment-dependent flakiness** — single re-runs cannot rule out non-determinism.
- **Scenarios outside the 38 covered** — this batch did not exhaustively cover every scenario in the Step 5 catalog; selection followed the dogfood walker assignment.

### Re-walker variance
Five of six re-walkers logged 100% agreement with their original walker pair. Only `re-walker-3` (assigned the seven migration scenarios) logged a single disagreement. Without that, the rate would be 100/100. This concentration argues against "walker collusion across the board" and for "one genuinely interesting contract-vs-template gap in one scenario."

---

## 7. Recommendation

1. **Merge PR #107.** All adversarial signals for the BL-057 fix point to a real regression-guarding test, a root-cause fix, and no test tailoring. The two open items are documented nits (line-25 self-pinning, line-140 brittle substring) that can be addressed in a follow-up if desired.
2. **Close BL-058 with the disposition determined by the in-flight investigation.** Three possible outcomes:
   - *Product bug* — the upgrade template should hide the 3 deferred rows. Open a fix PR.
   - *Doc inconsistency* — the matrix `expected_terminal_state` should be updated to say "all 6 rows visible, 3 deferred at `--to-production` time." Open a matrix update.
   - *Walker tailoring* — re-grade the scenario as `partial` in the Step 5 results. Update the dogfood report.
3. **File backlog items for the §5 tailoring observations** even though they did not change verdicts:
   - S-2: `validate.sh` should read gate dates from `phase-state.json` or document why APPROVAL_LOG is the canonical source.
   - S-3: `check-phase-gate.sh` should parse `--gate` argv or the scenarios should not pass it.
   - S-4: `manifest.json::deployment` refresh policy post-upgrade.
   - S-6: tighten enforcement-point contracts to assert "no other unexpected FAILs" where applicable.
   - S-7: `init.sh` should exit non-zero (or emit a structured summary) when any `[FAIL]` line is printed.
4. **Do not re-run the Step 5 sweep.** The 97.4% agreement rate plus the zero `pass × fail` count plus the PR #107 adversarial clean read together justify the existing sweep result.

---

## 8. Appendix — per re-walker stats

| Re-walker | Scenarios walked | Agreed with original | Agreement rate |
|---|---:|---:|---:|
| `re-walker-1` | 7 | 7 | 100.0% |
| `re-walker-2` | 7 | 7 | 100.0% |
| `re-walker-3` | 7 | 6 | 85.7% |
| `re-walker-4` | 6 | 6 | 100.0% |
| `re-walker-5` | 6 | 6 | 100.0% |
| `re-walker-6` | 5 | 5 | 100.0% |
| **Total** | **38** | **37** | **97.4%** |

### Certainty verdict mapping

| Criterion | Threshold | Observed | Pass? |
|---|---|---|---|
| Overall agreement rate | ≥ 95% | 97.4% | Y |
| `pass × fail` count | 0 | 0 | Y |
| PR #107 `test_is_tailored` | `false` | `false` | Y |
| PR #107 `fix_is_real` | `true` | `true` | Y |
| Critical contract disagreement | none | one under BL-058 investigation (non-blocking framing dispute) | Y (advisory) |

**Mapped verdict:** `high-confidence-no-tailoring`.

---

## Source inputs

- `/private/tmp/claude-501/-Users-karl-Documents-Claude-Projects-solo-orchestrator/7492d236-9edf-4ad1-845b-634f9df45abf/scratchpad/adversarial-rewalk-aggregated.json`
- PR #107 verifier comment: https://github.com/kraulerson/solo-orchestrator/pull/107#issuecomment-4835246451
