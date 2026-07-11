# Backlog Reconciliation Plan — 2026-06-29

**Author:** synthesizer subagent (Opus 4.7)
**Inputs:** status-reconciliation scout, missing-entries scout, prioritization scout
**Canonical file:** `solo-orchestrator-backlog.md` (45 entries: BL-001…BL-043, plus BL-003a/BL-003b suffix splits)
**Lint script:** `scripts/lint-backlog-references.sh` — currently PASSING for all entries

---

## 1. Executive summary

### File-state vs true-state (status-reconciliation scout)

| Bucket | Count | IDs |
| --- | --- | --- |
| Status accurate (no change) | 31 | BL-001, BL-005, BL-006, BL-007, BL-008, BL-009, BL-010, BL-011, BL-012, BL-013, BL-014, BL-015, BL-016, BL-019, BL-020, BL-021, BL-022, BL-023, BL-024, BL-025, BL-031, BL-032, BL-033, BL-034, BL-035, BL-036, BL-037, BL-038, BL-039, BL-040, BL-041, BL-042, BL-043, BL-003a, BL-003b |
| Status drifted — shipped but listed Open | 4 | **BL-002**, **BL-003**, **BL-004**, **BL-018** |
| Status drifted — closed but lacks current-convention citation | 2 | **BL-029**, **BL-030** (BL-030 says "PR upcoming" which is stale) |
| Decision pending — Karl input needed | 1 | **BL-017** (user memory says "parked"; parking commit `94e2ec6` is NOT in HEAD; defensible to leave Open) |

The lint script (`scripts/lint-backlog-references.sh --list`) currently reports **PASS** for every entry, including BL-017 ("open: no citation required") and BL-029/BL-030 (lint accepts any PR# or SHA anywhere in the block). So **none of these mutations are required for CI green** — they are accuracy/clarity improvements that close the gap between what the file says and what shipped.

### New entries proposed (missing-entries scout)

12 new entries spanning bug + performance + cleanup:

- **BL-044** — Bug, High: TEST 4 silent template-path drift (8 stale assertions in `tests/full-project-test-suite.sh` from the host-subdir migration)
- **BL-045..BL-054** — Step 4 ROI top-10 (parallelize TEST 1 matrix, helpers.sh split, cli arm, user-guide anchors, delete orphan plans, verify-install eval factory, get_available_platforms memoize, retire un-invoked aggregators, TEST 4 fixture sharing, tiny dead-code)
- **BL-055** — Placeholder note for code-check-gates-7-followup (per-line APPROVAL_LOG blame walker) — currently in flight as wf_c62d9fbe-369

Numbering picks up at BL-044 (BL-043 is the current highest).

### Tier distribution (prioritization scout)

- **T1 blockers (live bugs on main):** 4 — BL-039, BL-040, BL-041, code-check-gates-7-followup (will become BL-055 if not closed by wf_c62d9fbe-369)
- **T2 leverage (systemic / prevents defect classes):** 7 — BL-034, BL-038, BL-036, Step4-#1 (→BL-045), Step4-#2 (→BL-046), BL-002, BL-032
- **T3 bounded debt:** 18 — BL-037, BL-035, BL-001, BL-003, BL-004, BL-018, BL-033, BL-042, BL-043, BL-023, Step4-#3..#10 (→BL-047..BL-054)
- **T4 parked / optional:** 8 — BL-017, BL-010, BL-011, BL-012, BL-013, BL-014, BL-019, BL-025
- **T5 wontfix:** 0

---

## 2. Status truth-check

The four entries below have shipped on `main` but the **Status:** line still reads "Open". Lint already passes (citations exist in the block body) — these mutations are about accuracy. Closure-doc commits that never landed (e.g. `f2e97e7` for BL-018) explain the drift.

| ID | Current line (verbatim) | Recommended new line | Evidence |
| --- | --- | --- | --- |
| **BL-002** | `**Status:** Open` (line 45) | `**Status:** Closed (2026-04-27, PR #36, commit 50c0430)` | PR #36 (`50c0430`, `feat(host-drivers,init,check-gate): GitHub free-tier 403 graceful degradation (BL-002)`) is ancestor of HEAD. Backstop attestation honor added in PR #75 (`6ee4937`). |
| **BL-003** | `**Status:** Open` (line 67) | `**Status:** Closed (2026-06-27, PR #59, commit f684aa7) — split into BL-003a/BL-003b for gitlab/bitbucket follow-up coverage; both sub-entries now closed (PR #61, PR #62)` | PR #59 (`f684aa7`) shipped the github e2e umbrella. The two sub-entries BL-003a (PR #61, `fc9db0e`) and BL-003b (PR #62, `c8585fa`) are already marked Closed. The umbrella status is stale. |
| **BL-004** | `**Status:** Open` (line 82) | `**Status:** Closed (2026-06-27, PR #58, commit a3ea907)` | PR #58 (`a3ea907`, `test(upgrade-paths): flat → per-host layout + manifest .host backfill (BL-004)`) shipped T4 in `tests/test-upgrade-paths.sh:198`. Verified line 198 reads `=== T4: flat → per-host CI/release template layout + manifest .host backfill (BL-004) ===`. |
| **BL-018** | `**Status:** Open` (line 354) | `**Status:** Closed (2026-04-27, PR #33, commit e30759f)` | PR #33 (`e30759f`, `feat(upgrade): non-interactive semantic + --validate-only + tighter validation (BL-018)`) is in HEAD. The closure-doc commit `f2e97e7` never landed on main. |

The two entries below have **non-canonical Status wording** that may confuse readers but currently passes lint. Normalizing to the convention used by BL-006/BL-015/etc. (`Closed (DATE, PR #NN, commit SHA)`) improves consistency:

| ID | Current line (verbatim) | Recommended new line | Evidence |
| --- | --- | --- | --- |
| **BL-029** | `**Status:** Closed — shipped 2026-04-28 (PRs #40, #41); envelope-schema correction shipped 2026-06-26 (PR #46).` (line 594) | `**Status:** Closed (2026-06-26, PR #46, commit 5d1996b; bypass-audit infrastructure shipped earlier via PR #40 (2026-05-04) and PR #41 (2026-05-14))` | PR #40 (`0d6f988`), PR #41 (`e44227e`), PR #46 (`5d1996b`) all in HEAD. The 2026-04-28 date appears to be an authoring date — the PR #40 merge is dated 2026-05-04. |
| **BL-030** | `**Status:** Closed — shipped 2026-06-26 (PR upcoming).` (line 609) | `**Status:** Closed (2026-06-26, PR #48, commit 328c9c7; follow-ups PR #49, PR #51, PR #54)` | PR #48 (`328c9c7`, `feat(enforcement-level model BL-030)`) is in HEAD. "PR upcoming" is stale wording — PR #48 merged on 2026-06-26 and follow-ups #49/#51/#54 have since landed. |

### BL-017 — decision required (NOT mutating in this plan)

| ID | Current line | Note |
| --- | --- | --- |
| BL-017 | `**Status:** Open` (line 337) | User memory file `project_current_state.md` says BL-017 was parked 2026-04-27; parking-doc commit `94e2ec6` (`docs(backlog): park BL-017 awaiting real driver`) is NOT in HEAD (`git merge-base --is-ancestor 94e2ec6 HEAD` returns 1). The decision was made but never recorded in the file. Two defensible options: (a) honor the documented intent and write `**Status:** Parked — 2026-04-27 brainstorm concluded no concrete user; re-evaluate when a CI/agent-driven intake automation user emerges`; (b) leave as Open since no PR ever shipped the park. **Karl needs to decide before any mutation here.** Filed in §7 Decisions below. |

### Entries the status-reconciliation scout flagged as Closed but I'm leaving Open

The scout's initial pass marked **BL-025** as Closed because of commits `db099ca` and `1ace793` on a calibration branch — but on re-inspection the scout corrected itself: those commits are NOT in HEAD (`git merge-base --is-ancestor` confirms), the helper file `tests/test-helpers/init-phase2-verified.sh` does not exist on main (`ls tests/test-helpers/` returns "No such file or directory"), and `git log HEAD --oneline --grep='BL-025\b'` returns only the filing commits. **BL-025 stays Open.** No mutation.

---

## 3. New entries

The missing-entries scout produced 12 ready-to-append blocks. Each is structured for direct paste into `solo-orchestrator-backlog.md` after BL-043 (the current tail). The full bodies are passed through verbatim in the `backlog_mutations.new_entries` JSON. Summaries here:

> ### BL-044: TEST 4 in full-project-test-suite.sh silently fails 8 assertions due to stale template-layout paths
>
> **Category:** Bug · **Severity:** High · **Status:** Open
>
> PR #104's full-suite run reported 321/329 passing — 8 failures all in TEST 4. Root cause: `tests/full-project-test-suite.sh:506-507` copies from the flat `templates/pipelines/{ci,release}/*.yml` paths that no longer exist (now under `github/|gitlab/|bitbucket/` subdirs per host-subdir migration). The `[ -f ]` guards silently no-op, then verification asserts `File missing: .github/workflows/ci.yml` for every test combo. Pre-existing on main — not introduced by Wave 1–4 PRs. Scope: update TEST 4's `cp` source paths to use host-subdir layout, parameterize the host if practical, add fixture-sanity precheck at TEST 4 head. Bundle with BL-053 (fixture sharing) + BL-038 (registration check).

> ### BL-045: Parallelize TEST 1 resolver matrix in full-project-test-suite.sh (Step 4 ROI #1)
>
> **Category:** Performance · **Severity:** High · **Status:** Open
>
> TEST 1 walks 81 cells (3 platforms × 9 languages × 3 tracks) and forks fresh `bash scripts/resolve-tools.sh` per cell — fully serial, ~240s of the >600s timed-out suite. This is the gating reason `full-project-test-suite.sh` is NOT wired into CI today. Scope: `xargs -P 8` per-cell, or collapse into one batched resolver call (API change). Bundle with BL-053 (TEST 4 fixture sharing) for a single perf PR.

> ### BL-046 — Split `lib/helpers.sh` into focused libraries (Step 4 ROI #2)
> ### BL-047 — Audit and retire the disabled `cli` arm of `verify-install.sh` (Step 4 ROI #3)
> ### BL-048 — Repair dead user-guide anchors (Step 4 ROI #4)
> ### BL-049 — Delete orphan plan docs under `docs/superpowers/plans/` (Step 4 ROI #5)
> ### BL-050 — Wire `verify-install.sh --eval-factory` into the lint gate (Step 4 ROI #6)
> ### BL-051 — Memoize `get_available_platforms` in `resolve-tools.sh` (Step 4 ROI #7)
> ### BL-052 — Retire un-invoked test aggregators (Step 4 ROI #8 — note: scope overlap with BL-035; see cross-ref)
> ### BL-053 — Share TEST 4 fixture across combos in full-project-test-suite.sh (Step 4 ROI #9)
> ### BL-054 — Tiny dead-code cleanup pass (`_phase2_state_file`, `tool_install_json`) (Step 4 ROI #10)
> ### BL-055 — Placeholder: tier-crosscheck-6 follow-up (per-line APPROVAL_LOG blame walker)

**Scope-overlap callout (BL-052 vs BL-035):** Step 4 ROI #8 recommends *retiring* un-invoked aggregators; BL-035 already in the backlog recommends *wiring orphan tests into aggregators*. These are opposite actions on overlapping files. Karl needs to pick a policy:
- **Policy A** — wire all orphan tests into a single aggregator and retire the empty ones (BL-035 wins, BL-052 narrows to the truly-empty aggregators)
- **Policy B** — delete-and-rebuild (BL-052 wins, BL-035 narrows to only those tests worth keeping)

I am NOT making this decision; it's filed in §7.

---

## 4. Prioritization tiers

### T1 — Blockers (live bugs on main)

| ID | One-line rationale |
| --- | --- |
| BL-039 | E50 test acknowledged RED on main per PR #89 implementer note — `init.sh --non-interactive` does not satisfy the contract pinned in `tests/edge-cases-scripts.sh:E50`. |
| BL-040 | `scripts/init.sh:2781` `dry_run_summary` omits user-supplied description — literal-text-preservation guarantee absent in product code. |
| BL-041 | `scripts/init.sh:3494` framework-repo guard runs *before* the write-permission preflight; E8b is SKIPed as a consequence. Makes BL-040's test infrastructure unreachable. |
| code-check-gates-7-followup (→BL-055 if not closed) | `check-phase-gate.sh:246` uses `git log -n 1 --format=%an -- APPROVAL_LOG.md` returning the most-recent toucher of the file rather than the row's actual author — self-approval evasion surface. PR #87 only landed a minimum-viable WARN. **In flight as wf_c62d9fbe-369; expected to close this S3 imminently.** |

### T2 — Leverage (systemic / prevents defect classes)

| ID | One-line rationale |
| --- | --- |
| BL-034 | 16 of 17 Wave 1–4 test files run in zero aggregators — every assertion dark today; gating dep for BL-036/037 to have signal. |
| BL-038 | `lint-tests-registered.sh` — prevents recurrence of the orphan-test pattern; turns structural risk into automated gate. |
| BL-036 | Critical tautologies (E31/E32/E39) — three product surfaces have ZERO regression coverage; a regression could merge today. |
| BL-045 (Step 4 #1) | Parallelize TEST 1 — 240s → 30–60s; unblocks wiring full-project-test-suite.sh into CI. |
| BL-046 (Step 4 #2) | `helpers.sh` split — 30–40ms × ~15 short-lived callers compounds across the entire CLI surface. |
| BL-002 | Free-tier 403 — already shipped per §2; **moves to "verify status mutation lands" rather than implementation work.** |
| BL-032 | GitLab analog of BL-002 — same pattern, same leverage, not yet shipped. |

### T3 — Bounded debt cleanup

BL-037, BL-035, BL-001, BL-003 (verify status mutation), BL-004 (verify status mutation), BL-018 (verify status mutation), BL-033, BL-042, BL-043, BL-023, BL-044 (new), BL-047, BL-048, BL-049, BL-050, BL-051, BL-052 (policy-pending), BL-053, BL-054 — see prioritization-scout rationale; all bounded, low per-item urgency, no live regression hidden behind any single one.

### T4 — Parked / optional

| ID | Rationale |
| --- | --- |
| BL-017 | Parked 2026-04-27 per user memory; parking commit never landed (see §2 + §7). |
| BL-010 | `commit-msg` git hook for editor-case coverage — explicit "evaluate when concrete need arises". |
| BL-011 | Cutline-ID-aware enforcement — same. |
| BL-012 | Retroactive scanning for drifted feature commits — same. |
| BL-013 | Squash-merge CI enforcement — same. |
| BL-014 | Commit-type hygiene enforcement — same. |
| BL-019 | `verify-install.sh --non-interactive` audit — no current consumer needs it. |
| BL-025 | Phase 2 init-verified state helper for tests — proposal-grade, low severity. |

### T5 — Wontfix

(none)

---

## 5. Sequencing plan

Recommended next 3 waves (with file-conflict isolation per wave to avoid the Wave-3-style cascade):

### Wave A — "Status truth + closer" (1 PR, low risk, no file conflicts)

**Scope:** All 6 status_updates from §2 (BL-002, BL-003, BL-004, BL-018, BL-029, BL-030) plus the 12 new-entry appends (BL-044…BL-055). Single-file diff against `solo-orchestrator-backlog.md`. Includes the BL-017 decision (either parked or stays Open) per §7 outcome.

**File-conflict surface:** zero — only `solo-orchestrator-backlog.md`.

**Verification:** `bash scripts/lint-backlog-references.sh --list` shows PASS for all entries (currently passes, must still pass after).

**Why first:** Cheap, removes drift between the file and reality, sets up Wave B's prioritization to operate on accurate state. No code changes.

### Wave B — T1 blockers (parallel-safe, 4 PRs)

| Slot | Item | File surface | Conflict notes |
| --- | --- | --- | --- |
| B1 | BL-039 (E50 fix) | `scripts/init.sh` (BL-016 non-interactive path); `tests/edge-cases-scripts.sh` E50 | Conflicts with B2 (both touch `scripts/init.sh`) — sequence B1 → B2 OR keep edits in disjoint functions and rebase. |
| B2 | BL-040 (dry_run_summary description) | `scripts/init.sh:2781` | Sequence after B1 to avoid `init.sh` merge churn. |
| B3 | BL-041 (framework-repo guard layering) | `scripts/init.sh:3494`; `tests/edge-cases-scripts.sh` E8b | Touches a different region of `init.sh` than B1/B2 — likely independent, but rebase-check before merge. |
| B4 | code-check-gates-7-followup (per-line APPROVAL_LOG blame walker) | `scripts/check-phase-gate.sh:246` | Already in flight as wf_c62d9fbe-369; no conflict with B1/B2/B3. May close before this wave runs. |

**Order:** B4 lands first (in flight). Then B1 → B2 (sequential due to `init.sh`). B3 in parallel with B1/B2 (different `init.sh` region).

### Wave C — T2 leverage (4 PRs, mostly parallel)

| Slot | Item | File surface | Conflict notes |
| --- | --- | --- | --- |
| C1 | BL-034 (Wave 1–4 orphan registration) | Aggregator files under `tests/`; per-test runner additions | Foundation for C2/C3 — sequence first. |
| C2 | BL-038 (lint-tests-registered.sh) | New `scripts/lint-tests-registered.sh`; `.github/workflows/lint.yml`; `scripts/pre-commit-gate.sh` | Sequence after C1 (lint passes only when C1 lands). |
| C3 | BL-036 (critical tautologies E31/E32/E39) | `tests/edge-cases-scripts.sh`; `tests/edge-cases-upgrade-input.sh`; product code for upgrade-project template refresh & save_answer | Touches same files as wave-3 fallout; sequence after C1 to ensure assertions actually run. |
| C4 | BL-045 (TEST 1 parallelization) | `tests/full-project-test-suite.sh`; possibly `scripts/resolve-tools.sh` (if batching API change) | Independent of C1/C2/C3; can land in parallel. |
| C5 (stretch) | BL-002 verification + BL-032 implementation | `scripts/host-drivers/gitlab.sh`; `scripts/init.sh` (attestation flow); `scripts/check-phase-gate.sh` | BL-002 already shipped (just verify status mutation took); BL-032 is the gitlab analog using the same pattern. |

**Order:** C1 → (C2 + C3) → C5. C4 fully parallel.

### Alternative: single "do-the-rest" cleanup PR plan

If Karl wants Wave A on its own and then defers everything else, the single combined cleanup PR would be: status mutations + new-entry appends (file-only diff). Recommended; lowest risk.

### File-conflict heat map

| File | Touched by |
| --- | --- |
| `scripts/init.sh` | BL-039 (B1), BL-040 (B2), BL-041 (B3), BL-024 (already shipped) |
| `tests/edge-cases-scripts.sh` | BL-039 (B1, E50), BL-041 (B3, E8b), BL-036 (C3, E31/E32/E39) |
| `tests/edge-cases-upgrade-input.sh` | BL-036 (C3) |
| `tests/full-project-test-suite.sh` | BL-045 (C4), BL-044 (new), BL-053 (new) |
| `solo-orchestrator-backlog.md` | Wave A (all status mutations + all new entries) |
| `scripts/host-drivers/gitlab.sh` | BL-032 (C5) |
| `scripts/check-phase-gate.sh` | code-check-gates-7-followup (B4, in flight) |

---

## 6. Tier-crosscheck-6 status

**In flight:** workflow `wf_c62d9fbe-369` (task #89: "Implement tier-crosscheck-6 hard-block (final S3 closure)") is currently executing the per-line `APPROVAL_LOG.md` blame walker as the hard-block upgrade to PR #87's minimum-viable WARN.

**Reconciliation impact:**
- If wf_c62d9fbe-369 closes before Wave A lands → no backlog entry needed; the existing PR will carry its own citation in the commit message and either close inline or never reach the backlog.
- If wf_c62d9fbe-369 has not closed by the time Wave A is ready → **append BL-055** (the placeholder block included in the new_entries list) so the eventual PR can flip it to Closed using the existing citation pattern.

**Recommendation:** Pre-stage BL-055 in Wave A even if wf_c62d9fbe-369 closes first — a redundant Closed entry costs nothing and protects against the workflow stalling. If wf_c62d9fbe-369 lands first, BL-055 ships pre-Closed with the PR# citation.

---

## 7. Decisions Karl needs to make

| # | Decision | Default if no input |
| --- | --- | --- |
| 1 | **BL-017 status:** honor 2026-04-27 "parked" intent (write the parked status) or leave as Open since the park-doc commit never landed? | Leave as Open (status quo, no mutation). I am NOT including this in `status_updates`. |
| 2 | **BL-052 vs BL-035 policy:** wire orphan tests into a consolidated aggregator (BL-035 wins, BL-052 narrows), OR delete-and-rebuild (BL-052 wins, BL-035 narrows)? | Defer — file both as written; sequence the *implementation* PRs only after policy is set. |
| 3 | **BL-002 status mutation:** PR #75 added the backstop attestation honor on 2026-06-28; should the Closed-date be 2026-04-27 (original 403 fix, PR #36) or 2026-06-28 (final shape)? Current recommendation: cite PR #36 (earliest functional close) + footnote PR #75 in the body. | Use 2026-04-27, PR #36, commit 50c0430. |
| 4 | **Wave-A timing:** ship the file-only reconciliation PR now, or hold until Wave B's T1 fixes are ready to bundle? | Ship Wave A now — no code risk, removes confusion for any future agent reading the backlog. |
| 5 | **BL-029 closure date discrepancy:** the entry body says "shipped 2026-04-28" but PR #40 merge commit is 2026-05-04 in HEAD. Authoring vs merge date? | Use 2026-06-26 (the *final* fix, PR #46) as the close date, with footnote citing the earlier 2026-05-04 and 2026-05-14 PRs. |

---

## 8. Out of scope

- **Lint-script changes.** The current `scripts/lint-backlog-references.sh` is permissive (PR# or SHA anywhere in the block satisfies). I considered recommending a stricter format requirement on the Status line but rejected — the current convention has shipped well and the friction of forcing every legacy entry to match a single format isn't worth it.
- **CDF upstream sync.** BL-001 (upgrade-sync audit) recommends a refresh-from-CDF mechanism; I did not propose new entries to expand that scope. Per user memory `feedback_cross_repo_fixes.md`, CDF upstream fixes are preferred over Solo shims.
- **PR-creation automation.** A pre-PR check that flips Open→Closed automatically when a PR cites a BL number is interesting but out of scope here — file as a follow-up if desired.
- **Re-numbering / re-grouping of BL IDs.** Some readers might prefer a categorical re-grouping (bugs / debt / proposals / parked). I did not touch numbering — every existing ID is referenced from prior PRs and reports; renumbering would break those references.
- **Resolved (early-convention) entries.** BL-005 through BL-016, BL-024 use `Resolved (DATE, PR #N)` rather than the newer `Closed (...)` form. They all lint-PASS today; I did not propose normalizing to "Closed" since the prioritization scout flagged it as cosmetic-only.
- **Tier-2 leverage scope expansion.** I considered breaking BL-036 into per-test items (E31, E32, E39 separately) but the existing entry's brainstorm decision was to keep them bundled — I did not override that.
- **BL-025 closure.** Scout's first pass marked it Closed; the corrected reading is that the helper file never landed on main. Left Open.
