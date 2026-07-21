# PR-Sweep Remediation — PROGRESS ledger

One entry per work package, appended as each WP opens its PR. Executor: Opus 4.8.
Plan: `REMEDIATION-PLAN.md` (this directory).

---

## WP-1 — BL-147 + BL-151: make the approval-integrity step real; gitleaks without the org-license trap

**Branch:** `fix/bl147-bl151-ci-approval-integrity` · **Base:** `main` @ `e7bc567`
(fast-forwarded to the plan commit `e724d6a` to carry the BL-147/BL-151 backlog
entries — see the note under "Deviations"). **Status:** PR opened green, not merged.

### Reproduce (the finding)
- `templates/pipelines/ci/github/{python,typescript,other}.yml` ran
  `git diff origin/main...HEAD -- APPROVAL_LOG.md 2>/dev/null | grep -qE '^\-[^-]'`.
  `actions/checkout` defaults to a depth-1 clone with **no `origin/main` ref** →
  the diff dies `fatal: bad revision`, the `2>/dev/null` swallows it, and the
  step **PASSES on a tampered append-only log**. On push-to-main the `A...B`
  expression is self-comparing (vacuous there too).
- Parity hole: **7 of 10** GitHub language templates never got the approval
  steps at all (`csharp, dart, go, java, kotlin, rust, swift`).
- `gitleaks/gitleaks-action` needs `GITLEAKS_LICENSE` for ORG accounts +
  `fetch-depth: 0`; the templates set neither → org-track projects get a
  failing/license-less secret scan (BL-151).

### Watched-RED (before any template touched)
New shared content-pin suite `tests/test-bl147-ci-template-integrity.sh` —
the wave's ONE shared asset. Template lists derived mechanically
(`find … -name '*.yml'`) with a **>=10 count floor** (vacuity guard); cases:
- **Ca** checkout carries `fetch-depth: 0` (all 10 github)
- **Cb** both approval steps present in ALL 10 github (integrity + author)
- **Cc** no APPROVAL_LOG-touching line carries `2>/dev/null` (github + gitlab)
- **Cd** base resolved explicitly (`github.base_ref`, loud-fail
  `git rev-parse --verify "$BASE"`), never bare `origin/main...HEAD`
- **Ce** no `gitleaks/gitleaks-action`; every github template runs `./gitleaks git`
- **Cf** gitlab twin of Cc/Cd on the approval-bearing gitlab templates

Pre-fix run: **`Results: 3 passed, 11 failed`** (exit 1). Every failure mapped
to the finding — all 10 lack fetch-depth; 7 lack the steps; other/python/ts
(github) + python/ts (gitlab) silence stderr / use the bare base; all 10 use
gitleaks-action. RED evidence saved to `scratchpad/wp1-RED.txt`.

### Fix
- **Checkout** — `with: fetch-depth: 0` added to all 10 github CI templates
  (pin unchanged; WP-4 owns the pin refresh).
- **Approval steps** — both governance steps (integrity + author verification)
  stamped **BYTE-IDENTICAL** into all 10 (single sha `83ccd86…` across all 10):
  `BASE="origin/${{ github.base_ref || 'main' }}"`, `${{ github.event.before }}`
  on push, `git fetch origin … --quiet || true`, then a LOUD `exit 1` if
  `git rev-parse --verify "$BASE"` fails (a check that cannot run must not pass),
  then the append-only diff. No `2>/dev/null`.
- **gitleaks** — action → license-free CLI: `GITLEAKS_VERSION=8.30.1`
  (`gh api repos/gitleaks/gitleaks/releases/latest` → `v8.30.1`), `curl … |
  tar -xz gitleaks && ./gitleaks git --redact --exit-code 1`. `gitleaks git`
  scans full history — rides the fetch-depth fix.
- **GitLab twins** (`python.yml`, `typescript.yml`) — same explicit-base +
  loud-fail + no-silencer, using `CI_MERGE_REQUEST_TARGET_BRANCH_NAME` /
  `CI_DEFAULT_BRANCH`.

Post-fix run: **`Results: 14 passed, 0 failed`** (exit 0). All 20 CI templates
re-validated as parseable YAML (PyYAML `safe_load`).

### Tests
Registered in BOTH `tests/full-project-test-suite.sh` and the `tests.yml` unit
list (adjacent to `test-bl143`, each comment kept attached to its own if-block).
`scripts/lint-tests-registered.sh` → OK.

### Mutation proofs (run against the committed baseline; both restored to GREEN)
- Re-add `2>/dev/null` to one template's APPROVAL_LOG diff line → **Cc RED**
  (`Results: 13 passed, 1 failed`). `git checkout` restore → GREEN.
- Remove `fetch-depth: 0` from one template → **Ca RED**
  (`Results: 13 passed, 1 failed`). Restore → GREEN. (The gitleaks CLI comment's
  incidental "fetch-depth: 0 on checkout." mention is correctly ignored by the
  case's `…0$` anchor.)

### Blast radius
- `grep -rl 'origin/main...HEAD' tests/` → **none** (the old text was pinned by
  no test fixture — only the templates carried it). No fixture updates needed.
- `grep -rln 'gitleaks|Approval log|Secret detection' tests/` → the hits are
  hook/PATH/install-command surfaces, NONE pin the changed CI-template content.
- `bash scripts/run-lints.sh` → PASS (see the PR body for the tally).
- `scripts/lint-backlog-references.sh` → OK after the backlog Status updates.

### Deviations from the plan
- **Base reconciliation (not a spec deviation):** the worktree was cut from
  `origin/main`, but the BL-147/BL-151 backlog entries + the plan live only on
  `origin/docs/pr-sweep-remediation-plan` (one docs commit `e724d6a` = main + the
  entries/plan). To append the required in-entry Status updates, the WP-1 branch
  was **fast-forwarded** to that commit (zero file overlap with the WP-1 code
  changes — clean FF). Consequence: this PR also carries the sweep findings +
  plan doc. No change to the WP-1 work itself.
- **gitleaks version:** the plan's `8.28.0` was flagged indicative; used the real
  current `8.30.1` per `gh api … releases/latest`, exactly as instructed.
- Author-verification step stamped into all 10 (not just the 3 that had it) to
  close the parity hole the finding names ("7 of 10 never got the steps"), with
  the plan's "same base-resolution treatment"; the integrity step is the one the
  plan pins byte-identical, and both are byte-identical across all 10.

---

## WP-6 — BL-154: tests.yml unit-list enforcement arm + CLAUDE.md true-up

**Branch:** `fix/bl154-unit-lane-lint` · **Base:** `main` @ `origin/main`.
**Status:** PR opened green, not merged. File-disjoint from the template wave
(WP-1..3), so worked directly on an isolated worktree (no stacking).

### Reproduce (the finding)
`scripts/lint-tests-registered.sh` enforced ONLY aggregator registration
(BL-038). Nothing structural greps `.github/workflows/tests.yml`, yet CLAUDE.md
(CANONICAL COMMANDS + HOUSE RULES) claimed the lint enforces BOTH the aggregator
list AND the fast-lane unit list. Latent, not live: today's delta is zero — all
70 non-`init.sh` `tests/test-*.sh` files are already present in the 106-entry
`tests=(` array (`comm` of `grep -L 'init\.sh' tests/test-*.sh` vs the array
parsed from tests.yml → empty in the arm's direction). The 36 "extra" array
entries contain the string `init.sh` (mentioned, not necessarily scaffolding);
the arm treats them as EXEMPT, so no false positives.

### Watched-RED (before the lint was touched)
Extended the existing suite `tests/test-lint-tests-registered.sh` (NO new file)
with U1–U5. Pre-implementation run: **`Results: 13 passed, 4 failed`** (exit 1):
- **U1** (init.sh test exempt) RED — `rc=2` unknown flag `--tests-yml`
- **U2** (non-init test absent from unit list must flag) RED — `rc=2` unknown flag
- **U3** (real-repo unit-lane clean) already green (arm absent → nothing flagged)
- **U4** (fence-excision mutation) RED — "no BL-154-UNIT-LANE fence found"
- **U5** (tests.yml-entry-removal mutation) RED — `rc=2` unknown flag

### Fix (behind the `# BL-154-UNIT-LANE-BEGIN/END` fence)
- `--tests-yml FILE` override (fixture idiom mirroring `--tests-dir` /
  `--aggregators`); flag acceptance + var init kept OUTSIDE the fence so the
  excision mutant still parses the flag (only ENFORCEMENT reverts).
- `_build_unit_list_set` parses the `tests=(` array MECHANICALLY (awk between
  `tests=(` and its closing `)`, then `grep -oE 'tests/test-[A-Za-z0-9._-]+\.sh'`)
  into a pipe-delimited membership string (same idiom as `REGISTERED_STR`). A
  whole-file grep would over-count (the checkout comment names
  `test-lint-backlog-references.sh`), so the array is scoped. Count-floor
  vacuity guard: a 0-entry parse in repo mode exits 2 (refuse to claim a pass).
- `_check_unit_lane` flags any top-level `tests/test-*.sh` that does NOT contain
  `init.sh` (the exact `grep -L 'init\.sh'` convention tests.yml documents) and
  is missing from the array. init.sh-invoking tests → EXEMPT (slow lane only).
  Resolution: `--tests-yml` → fixture file; repo mode → real tests.yml; fixture
  mode without `--tests-yml` → arm inactive (aggregator check still runs, so the
  pre-existing T1–T11 fixtures are untouched).

Post-implementation run: **`Results: 17 passed, 0 failed`** (exit 0).

### Mutation proofs (in-suite, GREEN)
- **U4 (fence-excision):** copy the lint, `sed '/# BL-154-UNIT-LANE-BEGIN/,/# BL-154-UNIT-LANE-END/d'`,
  vacuity-guarded (marker count ≥ 1 AND mutant line-count < original) + `bash -n`
  clean, re-run the U2 scenario → the non-init test is NO LONGER flagged (exit 0).
  Proves the fence is load-bearing.
- **U5 (tests.yml entry):** `grep -vF 'tests/test-check-gate.sh'` on a COPY of the
  real tests.yml, consumed via `--tests-yml` against the real tests dir → that one
  test is flagged (exit 1, named, "unit lane"). Proves the arm reads the real list.

### CLAUDE.md disposition
The overclaim is cured by the implementation. HOUSE RULES sentence trued up to
make the `init.sh` exemption explicit and name both enforced lists (mechanism
name `lint-tests-registered.sh` unchanged, per plan). CANONICAL COMMANDS
"…are both lint-enforced" is now literally true — left as-is.

### Blast radius
- `bash tests/test-lint-tests-registered.sh` → 17/17 (exit 0).
- `bash scripts/lint-tests-registered.sh` (repo mode) → OK, exit 0.
- `bash scripts/run-lints.sh` → PASS (tally in the PR body).
- `bash scripts/lint-backlog-references.sh` → OK (exit 0) after the BL-154
  Status update.
- Markers use the repo's dominant plain-ASCII fence style (`# BL-154-…-BEGIN`,
  not the box-drawing `# ── …` form) so the standard `sed` excision idiom matches.

### Deviations from the plan
- None. The plan anticipated adding a fixture mode for tests.yml if absent
  (there was none) — added `--tests-yml`, mirroring the existing override idiom.
