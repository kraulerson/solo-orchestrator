# Test Integrity Audit — 2026-06-28

**Scope:** Wave 1-4 test additions (PRs #83-#97 plus follow-up fixers 2d5f917, 33e351e) and adjacent test infrastructure.
**Triggered by:** Quality concern that test files were added in batches without confirmation that (a) the assertions actually pin behavior, and (b) the runners actually run them.
**Method:** 5 scout subagents (4 vacuous-pattern by area + 1 runner-registration audit) executed in parallel; synthesized here.

---

## 1. Executive summary

| Metric | Count |
|---|---|
| Vacuous-pattern findings (all severities) | **31** |
| Critical (tautology / both-branches-pass on contract behavior) | **4** |
| Major (catch-all "handled" branches; negative-only oracles that pass on crash) | **15** |
| Minor / noted | **12** |
| Test files under `tests/` | 87 (5 aggregators + 82 test files) |
| Test files invoked by any aggregator | 15 (4 explicit + 11 host-driver glob) |
| **Orphan test files (no aggregator runs them)** | **67** |
| Wave 1-4 test files added or extended | 17 |
| Wave 1-4 test files actually wired into an aggregator | **1** (`test-platform-mobile-mcp-docs.sh`) |
| Confirmed live bugs (user-flagged) | **2** (item-9, item-10) |
| Confirmed live bugs (scout-discovered, behind vacuous-pass assertions) | **4** (E31, E32, E39, T2 snapshot) |

**Top-line finding:** the test suite as a whole has a structural integrity problem distinct from any single test bug. Of the 17 test files added across Wave 1-4, **16 are not run by any aggregator** — they execute only if a human manually invokes them. The CI workflow (`.github/workflows/lint.yml`) runs lint scripts only and invokes zero test files. The pre-commit gate runs the same lint scripts and zero test files. The full-project test suite covers 4 explicit tests + the host-driver subdirectory. Everything else — including every test added to fix every blocker bug in the BL-006 through BL-030 range — is silent.

This means that **even where assertions are well-constructed**, regressions go undetected because the test never runs. And **where the test does run** (e.g. host-drivers), several assertions are vacuous on top of that.

The risk concentration is at the intersection: tests that both fail to assert and fail to execute. Section 5 enumerates that quadrant.

---

## 2. Confirmed live bugs

These are not test bugs — they are product bugs that the test files acknowledge (via SKIP or known-failing) but that remain unfixed in `main`.

### LB-1 (item-9): BL-016 init.sh non-interactive suite, E50 — RED on main
- **File:** `tests/edge-cases-scripts.sh` E50 block
- **Status:** Acknowledged as failing on `main` in the PR #89 implementer note. The assistant who added the test did not fix the underlying bug nor remove the failing assertion.
- **Behavior:** non-interactive init flow does not satisfy the contract the test pins.
- **Disposition:** Open product bug, no tracking entry yet. Recommend BL-034 (see §6).

### LB-2 (item-10a): `init.sh:2781` dry_run_summary omits the description
- **File product:** `scripts/init.sh:2781` (`dry_run_summary`)
- **Test artifact:** `tests/edge-cases-pre-init.sh` E2 left SKIP
- **Behavior:** the dry-run summary code path does not echo the project description that the user supplied. The literal-text-preservation E2 assertion cannot be satisfied today because the value never reaches stdout. Test was left as SKIP rather than removed, but the underlying bug is unscheduled.

### LB-3 (item-10b): `init.sh:3494` framework-repo guard blocks non-dry-run from inside the repo
- **File product:** `scripts/init.sh:3494`
- **Test artifact:** `tests/edge-cases-pre-init.sh` E8b left SKIP
- **Behavior:** the framework-repo guard refuses any non-dry-run invocation when CWD is inside the framework checkout. This makes it impossible to exercise the write-permission preflight (which is what E8b wants to verify) without either a product-side change (move the write-permission check earlier than the guard) or a test-harness change (run the test from a non-framework directory layout).

### LB-4 (scout-discovered, behind a critical tautology): E31 — upgrade-project.sh template refresh never invoked
- **File:** `tests/edge-cases-scripts.sh:1043` (test E31)
- **Behavior:** the test claims to verify "UAT upgrade refreshes templates" but **never invokes `upgrade-project.sh`**. It manually `cp`s the template from the repo, then greps for the placeholder string in the file it just copied — by construction the assertion always succeeds. **The underlying product behavior — `upgrade-project.sh`'s template refresh logic — has no live regression coverage at all.** If that codepath broke, no automated signal would fire.
- **This is also the identical shape that the audit's `tests-edge-cases-9` finding was supposedly fixed in E21**, so this is a structural regression.

### LB-5 (scout-discovered, behind a critical tautology): E32 — upgrade-project.sh idempotency never invoked
- **File:** `tests/edge-cases-scripts.sh:1065` (test E32)
- **Behavior:** the test claims to verify upgrade-script idempotency, but the loop `cp template → cp template` makes the post-condition diff trivially `0`. `upgrade-project.sh` is never sourced or invoked. **Idempotency contract has no live coverage.**

### LB-6 (scout-discovered, both-branches-pass on contract): E39 — newline preservation accepts any handling
- **File:** `tests/edge-cases-upgrade-input.sh:970` (E39)
- **Behavior:** both the if (line1 matched) and else (line1 not matched) branches call `pass()`. A regression that silently strips the newline AND the substring "line1" still PASSes with message `handled (stored as: ...)`. The newline-preservation contract has no live coverage.

### LB-7 (scout-discovered, hidden by acknowledged-vacuous test): T2 snapshot infrastructure
- **File:** `tests/test-upgrade-interruption.sh:240` (T2)
- **Behavior:** the snapshot-directory invariant is wrapped in `if [ -d "$TMPDIR_T/.claude/upgrade-snapshots" ]; then ... fi`. If `upgrade-project.sh`'s snapshot creation is completely broken and never creates the directory, the conditional is skipped and `pass T2` fires unconditionally. **The forensic-snapshot infrastructure could be broken right now and no test would catch it.**

Items 4-7 are categorized as "potential live bugs" — the test infrastructure cannot detect a regression, so we can't tell from the test whether the underlying product code is healthy. They need either (a) a tightened test that actually exercises the product code, or (b) a manual smoke-test to confirm the product code still works, before we know if there's a live bug or merely a test gap.

---

## 3. Vacuous assertions — by area

### 3.1 Edge-cases (edge-cases-scripts.sh, edge-cases-pre-init.sh, edge-cases-upgrade-input.sh) — 14 findings

**Critical (3):**
- **E31** — `edge-cases-scripts.sh:1043`. Tautology: never invokes `upgrade-project.sh`. Identical shape to a previously-"fixed" finding (`tests-edge-cases-9` → E21). See LB-4.
- **E32** — `edge-cases-scripts.sh:1065`. Tautology: idempotency loop diffs a file against the file it was just copied from. See LB-5.
- **E39** — `edge-cases-upgrade-input.sh:970`. Both branches pass. See LB-6.

**Major (8):**
- **E33** SQL injection (`:641`) — catch-all "sanitized" branch accepts arbitrary garbage.
- **E34** 10K-char description (`:671`) — passes on any non-zero length, including truncation to 1 char.
- **E36** Unicode (`:804`) — passes on any non-empty non-`MISSING` value (mojibake survives).
- **E37** Emoji (`:834`) — same shape as E36.
- **E40** NUL byte (`:1010`) — over-broad `grep -q "test"` matches `tes`, `test123abc`, `best test`.
- **E12a/E12b** resume.sh + missing/empty CLAUDE.md (`:216`, `:231`) — three-way structure where the catch-all else passes; only fails on four magic shell-error keywords.
- **E25a/b/c** validate/check-phase-gate/resume on phase=99 (`:906`, `:920`, `:926`) — same magic-keyword negative oracle; never inspect rc.
- **E27** UAT init (`:983`) — asymmetric with E26: claims to verify "reference pair" but only checks one half (`pre-flight-reference.html`); a regression dropping `scenario-reference.json` passes silently. E28/E29 inherit the same shape.

**Minor (3):**
- **E37 BL-006** MERGE_HEAD skips deny (`:1164`) — negative-only `! permissionDecision.*deny`. Crash also satisfies the negation. E38/E39 inherit the shape.
- **E5** other.yml has placeholder steps (`edge-cases-pre-init.sh:341`) — case-insensitive `TODO|placeholder|REPLACE|...` matches nearly any CI template.

### 3.2 Lib/lint/upgrade/other suite (10 files) — 9 findings (3 major + 3 minor + 3 listed sibling)

**Major (3):**
- **test-prompt-install-noninteractive.sh:137** — the harness `exit 127` (function missing) PASSes T1/T2/T3 unconditionally. Removing `prompt_install` entirely does not flip any test.
- **test-upgrade-interruption.sh:240** (T2 snapshot retention) — see LB-7.
- **test-verify-install-fix-functions.sh:197-242** (T6-T10) — five negative-only `[OK]` checks; verify-install.sh crashing or changing its OK-string format makes all five PASS vacuously.

**Minor (3):**
- **test-upgrade-sentinel-block.sh:189** (T3) — the only sanity-check that T1's block was sentinel-caused; any unrelated early-exit in `upgrade-project.sh` makes T3 pass.
- **test-specs-plans-host-aware-quartet.sh:162** (T2b) — fixed 250-line awk window can bleed into adjacent task bodies; future drift where Task 4.3 stops listing steps but a later task mentions them silently passes.
- **test-upgrade-project-atomic.sh:360** (T7c) — `|| true` on each of 4 upgrade runs; only the final snapshot count is asserted, so a regression that double-creates snapshots per run is not detected.

### 3.3 Reconfigure / intake-wizard / mobile suite — 3 findings (1 major + 2 minor)

**Major (1):**
- **test-intake-wizard-fixes.sh:81** (T1) — tautological branch: the awk filter `$1 == n` guarantees the post-filter `${wiz_line%%:*} != $tpl_num` comparison compares the value to itself. Section-title drift (number kept, title corrupted) is silently accepted. The `wiz_title` variable on line 78 is computed but never used.

**Minor (2):**
- **test-reconfigure-field-handlers.sh:218** (T3) — brittle regex tied to the current `language   — ...` help layout. A help-text restyle that keeps track/deployment listed silently passes.
- **test-reconfigure-field-handlers.sh:299** (T7) — substring-only check; partial sed substitution where only the H1 (not the body line) gets updated still passes.

### 3.4 Gates / pre-commit / hosts (7 files) — 8 findings (1 major + 5 minor + 2 noted)

**Major (1):**
- **test-check-phase-gate-self-approval.sh:141** (T3) — both branches pass. The elif at line 136 matches WARN output; the else at 138-141 also passes on absence-of-message. A regression that drops the WARN entirely still PASSes T3.

**Minor (5):**
- **test-check-phase-gate-noninteractive.sh:178** (T3) — source-level `grep -qE` over the script file itself. Wrapping the echo in `if false; then ... fi` keeps the string present but never emitted; T3 still passes.
- **test-pre-commit-gate-classifier.sh:188** (T8a/T8b) — author-acknowledged: these inputs never contained "create", so the BL-020 loose regex would not have matched them either. They don't gate a revert.
- **bitbucket.test.sh:331** (T5b) — `assert_contains BITBUCKET_API_TOKEN_EMAIL` against static help boilerplate; cannot distinguish which credential half is missing.
- **bitbucket.test.sh:416** (T9) — same shape as T5b for `BITBUCKET_PROJECT_KEY`.
- **test-pending-approval-resolve-decision.sh:160** (T5) — narrow regex source-pattern check; `printf %s | tee ...` or no-space `>...` redirect would bypass.
- **bitbucket.test.sh:201** (T2 SOIF_DEBUG) — only checks substring "restriction 99", not exit code. An unrelated mock-cli stderr containing the id satisfies the contains check.

**Noted (2):**
- **test-pre-commit-gate-classifier.sh:192** (T8a/T8b sibling concern) — duplicate of above; called out separately because the `[PASS] T8` label is misleading.

---

## 4. Runner registration gap

### What runs

| Aggregator | What it invokes |
|---|---|
| `tests/full-project-test-suite.sh` | 4 explicit `test-*.sh` (TEST 0b/0c/0d/0e); the rest of its assertions are inline |
| `tests/host-drivers/run-all.sh` | 11 host-driver tests via `*.test.sh` / `*.selftest.sh` glob |
| `tests/edge-case-test-suite.sh` | Self-contained, invokes **zero** other test files |
| `tests/known-bugs-test-suite.sh` | Self-contained, invokes **zero** other test files |
| `tests/upgrade-path-tests.sh` | Self-contained, invokes **zero** other test files |
| `.github/workflows/lint.yml` (CI) | Lint scripts only — **no test files** |
| `scripts/pre-commit-gate.sh` | Lint scripts only — **no test files** |

### Wave 1-4 orphans (test files added/extended in PRs #83-#97 + follow-ups that are NOT in any aggregator)

**Wave 1 (edge-cases extensions and intake/reconfigure):**
1. `tests/edge-cases-pre-init.sh` (PR #88 — 5 new S3 closures added)
2. `tests/edge-cases-scripts.sh` (PR #89 — 3 new S3 closures, plus the failing E50)
3. `tests/edge-cases-upgrade-input.sh` (PR #85 — 6 new S3 closures)
4. `tests/test-intake-wizard-fixes.sh` (PR #83)
5. `tests/test-reconfigure-field-handlers.sh` (PR #84)

**Wave 3 (gates / governance / hosts / bypass-audit):**
6. `tests/test-bypass-audit-tmp-hardening.sh` (PR #93)
7. `tests/test-bypass-audit-trap-isolation.sh` (verifier fix 2d5f917)
8. `tests/test-bypass-detector-session-id.sh` (PR #93)
9. `tests/test-check-phase-gate-noninteractive.sh` (PR #87)
10. `tests/test-check-phase-gate-self-approval.sh` (PR #87)
11. `tests/test-gitlab-ci-status-stderr-approvals.sh` (PR #91)
12. `tests/test-host-verify-protection-date-parse.sh` (PR #93)
13. `tests/test-pending-approval-resolve-decision.sh` (PR #87)
14. `tests/test-verify-install-fix-functions.sh` (PR #92)

**Wave 4 (upgrade / lint / plans):**
15. `tests/test-upgrade-interruption.sh` (PR #95)
16. `tests/test-upgrade-sentinel-block.sh` (PR #95)
17. `tests/test-lint-fix-functions-stderr.sh` (PR #96) — lint script itself runs in CI; the meta-test of the lint script does not
18. `tests/test-lint-raw-read-prompt.sh` (PR #96)
19. `tests/test-specs-plans-host-aware-quartet.sh` (PR #97)
20. `tests/test-prompt-install-noninteractive.sh` (verifier fix 33e351e)

**Only Wave 1-4 test wired into an aggregator:** `tests/test-platform-mobile-mcp-docs.sh` (PR #86 → `full-project-test-suite.sh` TEST 0e).

### Broader orphan footprint (pre-wave 1-4 tests that are also not in any aggregator)

A further ~50 test files predate wave 1-4 and are likewise not in any aggregator. See the scout's full enumeration in the input bundle. Notable ones (because they cover historically-fragile gates):

- `test-bl029-integration.sh` / `test-bl030-calibration-replay.sh` / `test-bypass-audit-*.sh` family (governance log integrity)
- `test-check-phase-gate-counter-sanitizer.sh` (counter-antipattern)
- `test-init-non-interactive.sh` (26 unit tests per the 2026-04-25 plan)
- `test-pre-commit-gate-classifier.sh` (BL-020 / BL-021 close coverage)
- `test-upgrade-paths.sh` (**not** the aggregator `tests/upgrade-path-tests.sh` — easily confused; possible source of the Step 4 recon mismatch)

### Confusable filenames

`tests/test-upgrade-paths.sh` vs `tests/upgrade-path-tests.sh` — the **first** is an orphan test file; the **second** is a top-level aggregator. Anyone scanning for "did wave-N upgrade work land?" by grepping for `upgrade-path` will see two hits and may assume the test is registered.

---

## 5. Risk matrix — (vacuous) × (unregistered)

Worst quadrant: the test asserts nothing AND no aggregator runs it. Findings in this cell are effectively non-existent as a regression signal.

| Finding | File | Vacuous? | Registered? | Quadrant |
|---|---|---|---|---|
| E31 (upgrade template refresh tautology) | edge-cases-scripts.sh:1043 | **Critical** | No | **Worst** |
| E32 (upgrade idempotency tautology) | edge-cases-scripts.sh:1065 | **Critical** | No | **Worst** |
| E39 (newline both-branches-pass) | edge-cases-upgrade-input.sh:970 | **Critical** | No | **Worst** |
| T1 intake-wizard tautological branch | test-intake-wizard-fixes.sh:81 | Major | No | **Worst** |
| T3 self-approval both-branches-pass | test-check-phase-gate-self-approval.sh:141 | Major | No | **Worst** |
| T6-T10 verify-install negative-only | test-verify-install-fix-functions.sh:197-242 | Major (x5) | No | **Worst** |
| T1/T2/T3 prompt_install harness exit 127 | test-prompt-install-noninteractive.sh:137 | Major | No | **Worst** |
| T2 snapshot retention conditional | test-upgrade-interruption.sh:240 | Major | No | **Worst** |
| E33-E40 catch-all "handled" patterns (8) | edge-cases-upgrade-input.sh | Major | No | **Worst** |
| E12/E25 magic-keyword negative oracles | edge-cases-scripts.sh | Major | No | **Worst** |
| T5b/T9 Bitbucket static-help assertions | host-drivers/bitbucket.test.sh | Minor | **Yes** (host-driver glob) | Mid (asserts weakly but runs) |
| T2 SOIF_DEBUG substring check | host-drivers/bitbucket.test.sh:201 | Minor | **Yes** | Mid |
| E5 placeholder grep | edge-cases-pre-init.sh:341 | Minor | No | Bad |

**Interpretation:** the entire critical and major-vacuous set is in the "Worst" quadrant. Every single finding above minor severity comes from a test file that is **also** orphaned. That co-occurrence is not a coincidence — it suggests the test authors didn't think they had to write tight assertions because nothing was running them anyway, OR the tests were drafted under time pressure and never re-examined because there was no failing aggregator to force re-examination.

---

## 6. Recommended backlog entries

The following entries are formatted to paste directly under the existing BL-033 entry in `solo-orchestrator-backlog.md`. Numbering continues from BL-033.

### BL-034: Wire orphan tests into aggregators (Wave 1-4 cohort)
- **Severity:** High
- **Why:** 16 of 17 Wave 1-4 test files do not run in any aggregator, CI, or pre-commit. Regressions in any of the corresponding product surfaces (intake-wizard, reconfigure, bypass-audit, host drivers, check-phase-gate, upgrade-interruption, sentinel-block, lint scripts, host-aware quartet) will not be caught.
- **Action:** Add explicit invocations to `tests/full-project-test-suite.sh` for the Wave 1-4 cohort enumerated in §4 of `Reports/2026-06-28-test-integrity-audit.md`. Where a test is intentionally manual (slow, network-dependent), document that in the test header and add a comment to the aggregator explaining the exclusion. The default disposition is "wired up".

### BL-035: Wire orphan tests into aggregators (pre-Wave 1-4 backlog)
- **Severity:** Medium
- **Why:** Approximately 50 additional `test-*.sh` files predate Wave 1-4 and are similarly orphaned. Coverage for BL-029, BL-030, counter-sanitizers, init non-interactive (BL-016), pre-commit-gate classifier (BL-020/021), and the bypass-audit family is all silent.
- **Action:** Audit each orphan from the Step 4 enumeration. For each, either (a) add to an aggregator, (b) merge logic into an existing aggregator's inline assertions, or (c) delete if redundant with current inline coverage. Schedule after BL-034.

### BL-036: Fix critical vacuous assertions (E31, E32, E39)
- **Severity:** Critical
- **Why:** Three tests in the edge-cases suite are tautological by construction. The corresponding product behaviors (`upgrade-project.sh` template refresh, `upgrade-project.sh` idempotency, save_answer newline preservation) have **zero regression coverage** in `main`. A regression could be merged today with no signal.
- **Action:**
  - **E31:** rewrite to actually invoke `upgrade-project.sh` (or whichever script handles UAT template refresh) and then assert the placeholder is present in the project-side template AFTER the upgrade ran.
  - **E32:** rewrite to invoke `upgrade-project.sh` twice and assert the second invocation is a no-op (diff-clean against a snapshot taken after invocation 1).
  - **E39:** collapse the both-branches-pass into a single positive assertion: `grep -q $'^line1\nline2$'` against the saved file (or whichever shape the contract demands).
- **Bundle with:** BL-034 (so the rewritten tests actually run when added to an aggregator).

### BL-037: Fix major vacuous assertions (catch-all "handled" + negative-only oracles)
- **Severity:** High
- **Why:** 15 major-severity findings across edge-cases, verify-install, prompt-install, snapshot-retention, intake-wizard, and self-approval tests use either catch-all `else pass: handled` branches or negative-only oracles (`! grep -q deny`, no positive assertion). Each one will silently pass on a crash or on garbage output.
- **Action:** Tighten each assertion to require a **positive** signal:
  - E33: pin the exact sanitized form (or the documented cap length).
  - E34: pin the exact stored length (`saved_len == 10000` or `saved_len == ${DESCRIPTION_CAP}`).
  - E36, E37: pin the exact stored bytes (UTF-8 roundtrip exact match).
  - E40: pin either `saved_value == "test\\0value"` or the documented sanitization (e.g. NUL stripped → `saved_value == "testvalue"`).
  - E12a/b, E25a/b/c: require `[ $? -eq 0 ]` (clean exit) AND a specific positive output substring.
  - E27, E28, E29: assert both halves of the reference pair (`pre-flight-reference.html` AND `scenario-reference.json`).
  - test-verify-install-fix-functions T6-T10: require the positive fail/manual line (mirror T5's tightened oracle).
  - test-prompt-install-noninteractive: require `type prompt_install` before each test; assert rc==1 specifically (not just rc!=0).
  - test-upgrade-interruption T2: remove the `if [ -d ... ]` wrap on the snapshot dir assertion — make the dir's presence a hard requirement.
  - test-intake-wizard-fixes T1: replace the tautological shell-parameter check with an actual title comparison: read `wiz_title` AND compare to the template's `tpl_title`.
  - test-check-phase-gate-self-approval T3: remove the `else pass` branch on absence-of-message; require the WARN substring as a positive condition.
- **Bundle with:** BL-034 (the tightened tests need to be registered to matter).

### BL-038: Mandate runner-registration check for new test files
- **Severity:** Medium
- **Why:** The pattern of "PR adds a test file, PR merges, test never runs" is now a systemic risk, not a one-off mistake. Without an automated gate, the next wave will reproduce the same issue.
- **Action:** Add a lint script `scripts/lint-tests-registered.sh` that:
  1. Enumerates `tests/*.sh` (excluding aggregators and helpers via an allowlist).
  2. Greps each top-level aggregator (`full-project-test-suite.sh`, `edge-case-test-suite.sh`, `known-bugs-test-suite.sh`, `upgrade-path-tests.sh`, `host-drivers/run-all.sh`) for invocation of each basename.
  3. FAILs the gate if any test file is not invoked by any aggregator (with override mechanism: `# LINT_TEST_REGISTRATION_EXEMPT: <reason>` magic comment in the test header).
- Wire into `.github/workflows/lint.yml` and `scripts/pre-commit-gate.sh` alongside the existing lint scripts.

### BL-039: Resolve LB-1 — fix the underlying bug behind E50 (BL-016 non-interactive init)
- **Severity:** High (the test acknowledges a RED failure on `main`; the bug is live)
- **Why:** PR #89's implementer note states E50 fails on main; the assistant chose not to fix the underlying bug nor remove the assertion. The product code path (`init.sh --non-interactive`) does not satisfy the contract E50 pins.
- **Action:** Debug E50's failure. Either fix `init.sh` to satisfy the contract, or — if the contract is now considered wrong — update the test AND document the contract change in `docs/builders-guide.md`. Do not delete the test silently.

### BL-040: Resolve LB-2 — `init.sh:2781` dry_run_summary omits the description
- **Severity:** Medium
- **Why:** E2 in `edge-cases-pre-init.sh` is SKIPed because the dry-run summary does not echo the project description that the user supplied. The literal-text-preservation guarantee that E2 wants to verify is absent in the product code.
- **Action:** Edit `scripts/init.sh:2781` (`dry_run_summary`) to include the description field in its emitted output. Remove the SKIP, restore the assertion.

### BL-041: Resolve LB-3 — `init.sh:3494` framework-repo guard layering
- **Severity:** Medium
- **Why:** The framework-repo guard at `init.sh:3494` runs before the write-permission preflight, making it impossible to exercise the preflight from inside the framework repo. E8b is SKIPed as a consequence.
- **Action:** Either (a) reorder the checks so the write-permission preflight runs first, or (b) rewrite the test harness to use a non-framework-repo layout (e.g. copy the relevant files into a tmpdir and run from there). Option (a) is preferred — the preflight is operator-facing and should fire before the developer-facing guard.

---

## 7. Recommended Wave 5 work

Sub-PRs in suggested execution order. Each should be small enough for a single review cycle.

### Wave 5 Slot 1 — Register Wave 1-4 orphans (BL-034)
- Single PR that adds the 16 wave 1-4 test files to `tests/full-project-test-suite.sh` with explicit `bash "$SCRIPT_DIR/tests/test-*.sh"` calls.
- For tests that are currently RED (E50, prompt_install harness) — invoke them but mark expected-fail until BL-036/037/039 land. The point is to get the runner pointing at them so subsequent fixes are visible.

### Wave 5 Slot 2 — Critical tautology fixes (BL-036)
- Rewrite E31, E32, E39. Each rewrite should include a deliberate mutation test: after writing the new assertion, manually break the product code and confirm the test FAILS. Capture the mutation result in the PR description.

### Wave 5 Slot 3 — Major vacuous assertion fixes (BL-037)
- Bundle as a single PR if changes total under ~300 lines, otherwise split by area:
  - 3a: edge-cases (E33-E40, E12, E25, E27-29)
  - 3b: verify-install + prompt-install (T6-T10, prompt-install harness)
  - 3c: upgrade/sentinel (test-upgrade-interruption T2, test-upgrade-sentinel-block T3 acknowledgment)
  - 3d: intake-wizard + self-approval (T1 tautology, T3 both-branches)

### Wave 5 Slot 4 — Pre-Wave-1-4 orphan triage (BL-035)
- Audit ~50 orphan test files. For each, decide: register, merge inline, or delete. Submit as one PR with a table mapping each file to its disposition.

### Wave 5 Slot 5 — Live product bugs (BL-039, BL-040, BL-041)
- Three separate PRs (or one bundled PR) that fix the underlying product code behind LB-1/LB-2/LB-3 and remove the SKIPs / mark E50 GREEN.

### Wave 5 Slot 6 — Prevent recurrence (BL-038)
- Add `scripts/lint-tests-registered.sh`, wire into CI and pre-commit. This is the structural fix.

### Wave 5 Slot 7 — Smoke-test the four "potentially broken" product areas behind tautological tests (LB-4 through LB-7)
- Manually invoke `upgrade-project.sh` against a fresh project to confirm the template-refresh and idempotency paths still work. If they don't, file separate bug entries; the Slot 2 rewrites will then catch the regression once landed.
- Manually verify `save_answer` preserves newlines and `upgrade-project.sh` creates `.claude/upgrade-snapshots/` on every run.

---

## 8. Methodology and scope skipped

### Methodology

- **Vacuous-pattern scouts (4):** Each scout took an area, read its test files end-to-end, and traced `if/elif/else` chains looking for both-branches-pass, catch-all `else pass`, magic-keyword negative oracles, source-pattern checks masquerading as behavioral checks, and tautological assertions (where the assertion's premise guarantees the conclusion by construction). Mutation tests were proposed for each finding — concrete one-line edits to product code that should flip the assertion but don't.
- **Runner registration scout:** Enumerated all `.sh` under `tests/`, grepped each aggregator for invocations, cross-referenced with `.github/workflows/*.yml` and `scripts/pre-commit-gate.sh`. Walked Wave 1-4 merge SHAs to identify which tests were added in that window.
- **Synthesis:** This document deduplicates findings across scouts, intersects (vacuous) × (unregistered), and translates into backlog entries.

### Scope skipped (explicit)

- **No tests under `docs/skills/` or `vendor/`** — those are not the project's primary test surface.
- **No assertions in product code itself** — `set -e` removal, missing `|| die`, etc. were not in scope. The "tests are silent" finding raises the question, but this audit is bounded to `tests/`.
- **No CI runtime check** — we did not actually run any aggregator and measure wall-time / failure surface. Slot 1 of Wave 5 will produce that data as a side effect.
- **No mutation-testing automation** — each finding includes a proposed mutation, but they were not executed (modulo a small number of confirmations the scouts performed inline). Slot 2 of Wave 5 should run the mutations end-to-end on the rewritten tests.
- **No coverage of `tests/host-drivers/mock-cli.sh`** — it is a helper, not a test, correctly excluded from `run-all.sh`'s `*.test.sh` glob.

### Confidence

- Critical and major findings are high-confidence (line-numbered, with concrete mutation cases). Several were independently confirmed via direct grep/awk against the files.
- Minor findings are medium-confidence — they are real weaknesses but a determined attacker would need to combine them with another regression to exploit; treat as "tightening" not "blockers".
- The runner-registration scout's enumeration is high-confidence — every entry was verified by basename-grep against every aggregator.

### Reproducing this audit

```bash
# Vacuous patterns
grep -nE '(\|\| pass|\|\| true|\|\| return 0)' tests/*.sh
grep -nE 'pass.*handled|gracefully' tests/*.sh
grep -nE '\[ "?\$\?"? ' tests/*.sh

# Runner registration
for f in tests/edge-case-test-suite.sh tests/full-project-test-suite.sh tests/known-bugs-test-suite.sh tests/upgrade-path-tests.sh tests/host-drivers/run-all.sh; do
  echo "=== $f ==="
  grep -oE 'tests/[a-zA-Z0-9_-]+\.sh|\$SCRIPT_DIR/tests/[a-zA-Z0-9_-]+\.sh' "$f" | sort -u
done

# Wave 1-4 test additions
for sha in 17ed4f3 78d2919 0d5605e e388d39 78d2919 e340f2f 6fd93e0 df6c208 6b3f2a1 732ad3e cbe6804 063f6ba 2d5f917 33e351e; do
  git show --diff-filter=A --name-only "$sha" 2>/dev/null | grep '^tests/' || true
done
```

---

**Report compiled:** 2026-06-28
**Inputs:** 4 vacuous-pattern scout reports + 1 runner-registration audit (parallel execution, ~25 min cap each)
**Total findings:** 31 vacuous-pattern + 67 orphan tests + 7 confirmed/potential live bugs
