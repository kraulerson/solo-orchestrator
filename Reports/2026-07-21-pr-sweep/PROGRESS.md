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

## WP-5 — BL-152: GitLab approval_rules migration

**Branch:** `fix/bl152-gitlab-approval-rules` · **Base:** `main` @ `78d944e`
(origin/main after WP-1 merged as #235). **Status:** PR opened green, not merged.
File-disjoint from the template wave — no stacking.

### Reproduce (the finding)
`scripts/host-drivers/gitlab.sh` `host_configure_protection` (org mode) set
required approvals via `glab api -X PUT projects/:id/approvals` with
`{"approvals_before_merge":1,"reset_approvals_on_push":true}`. `approvals_before_merge`
is deprecated since GitLab 14.0 and **scheduled for removal in REST API v5**
(confirmed in the GitLab REST docs). On removal the PUT fails into the driver's
generic exit-3 arm, not the handled BL-032 free-tier exit-4 arm.

### API shape (Context7, GitLab REST docs — merge_request_approvals)
- `POST /projects/:id/approval_rules` — **required:** `name` (string),
  `approvals_required` (integer). **Optional:** `rule_type`
  (`any_approver`/`regular`/`report_approver`), `user_ids`, `group_ids`, etc.
- The docs explicitly advise **omitting `rule_type`** when creating rules via
  the API ("Users should avoid using the rule_type field when building approval
  rules via the API") — so the payload is `name` + `approvals_required` only.
- `GET /projects/:id` still returns `approvals_before_merge` but flagged
  `// Deprecated. Use merge request approvals API instead.` — the field's
  removal in v5 is the currency risk BL-152 names.

### Watched-RED (before the driver changed)
New case **T9** in `tests/test-gitlab-ci-status-stderr-approvals.sh`. The fake
`glab` was extended to record every invocation's argv + `--input` payload to
`GLAB_ARGV_LOG` (off unless the env var is set → other scenarios unaffected).
T9 asserts a `POST …/approval_rules` call that carries `approvals_required` and
NO `approvals_before_merge`. Pre-fix run: **`8 passed / 1 failed`** — T9 RED,
the recorded log showing `api -X PUT projects/org%2Frepo/approvals … {"approvals_before_merge":1,"reset_approvals_on_push":true}`.

### Fix
- Call migrated to
  `glab api -X POST "projects/$project/approval_rules" --input - <<<'{"name":"Require approval","approvals_required":1}'`.
- **BL-032 Premium sniff preserved verbatim:** the broad detection regex
  (`premium|ultimate|not available on your plan|feature is not available|requires.*plan`)
  is retained UNCHANGED. The exact Free-tier body for `approval_rules` is not
  verifiable offline, so per the plan BOTH endpoints' 403 phrasings are covered
  by the retained union (requiring MR approvals is the Premium gate regardless
  of endpoint) — comment added saying so.
- **rc 3 / rc 4 contract unchanged** — only the call underneath moved. Header
  contract, the `WHY GLAB STDERR`/`WHY BL-032 EXISTS` blocks, the shortcircuit
  comment, and the operator remediation message updated only where they named
  the old endpoint (`projects/:id/approvals` + `approvals_before_merge` →
  `projects/:id/approval_rules` + `approvals_required`; "PUT" → "POST").

Post-fix run: **`9 passed / 0 failed`**.

### Tests (fixture arms updated in lockstep — all four gitlab suites GREEN)
- `tests/test-gitlab-ci-status-stderr-approvals.sh` → **9/0** (T9 added; fake-glab
  arm `-X PUT …/approvals` → `-X POST …/approval_rules`).
- `tests/test-bl032-gitlab-free-approvals-attestation.sh` → **8/0** (same arm
  swap; `APPROVALS_PUT_TRACKER` + reactive/attested paths intact).
- `tests/host-drivers/gitlab.test.sh` → **12/12** (org-configure mock
  `-X PUT …/approvals` → `-X POST …/approval_rules`).
- `tests/host-drivers/e2e-init-gitlab.test.sh` → **7/0** (mock arm swap; T6
  exit-3 + T7 exit-4 Premium paths both fire on the new call; internal
  `MOCK_GL_APPROVALS_PUT_*` knob names retained, noted).

No NEW test file → no aggregator/tests.yml registration anchors touched
(the RED case extends an existing suite already registered).

### Mutation proof (against the migrated driver; restored to GREEN)
Revert the driver call to the PUT form (copy mutated, then restored from a
backup) → **T9 RED** (`5 passed / 4 failed`; the recorded log again shows
`-X PUT …/approvals` + `approvals_before_merge`, and the fixture arm — now
wired to the POST — no longer injects the T1/T5/T6 exit codes, further proving
the arm tracks the new call shape). Restore → **9/0 GREEN**.

### Blast radius
- `grep -l gitlab tests/*.sh` → the 4 driver suites above plus 11 that only
  mention "gitlab" for host/manifest/CI-template purposes; grep-verified NONE
  reference the driver approvals call / source / `approvals_before_merge`. Ran
  the fast ones (`test-bl116/118/147/123/currency-manifest/docs-cluster-six-pack/
  lint-no-live-remote/specs-plans-remaining-quartet/check-phase-gate-backstop-attestation`)
  → all **rc=0**. The init-heavy aggregators (edge-case, edge-cases-pre-init,
  upgrade-paths) don't touch the driver call (grep-proven) and the init.sh path
  is exercised end-to-end by e2e-init-gitlab (7/0).
- `bash scripts/run-lints.sh` → (tally in PR body).

### Scope notes (recorded, NOT built — per plan "STOP and report, do not improvise")
- **Verify path unchanged:** `host_verify_protection` still reads the
  (also-deprecated) `approvals_before_merge` scalar from
  `GET projects/:id/approvals`. WP-5's scope is "swap the [configure] call"
  (BL-152's fix shape names only the POST); left as a follow-up since that read
  may return 0 once the field is removed in v5. The unit + e2e verify fixtures
  still pin `approvals_before_merge` and stay green.
- **`reset_approvals_on_push:true` dropped:** it rode along on the old PUT but
  belongs to the `/approvals` config endpoint, not `approval_rules`. Preserving
  it would need a separate config POST beyond "swap the call". Flagged.
- **Idempotency on re-run:** `POST …/approval_rules` creates a rule; unlike the
  old idempotent PUT, a second org-configure could create a duplicate/renamed
  rule. `host_configure_protection` runs once at Phase-2 init (rare re-runs),
  so low risk — noted for the durable follow-up.
