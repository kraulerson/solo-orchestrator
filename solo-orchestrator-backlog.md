# Solo Orchestrator Backlog

Items that aren't formal-spec-worthy yet — proposals, tech debt, audits, drift-watches.
Promote to `docs/superpowers/specs/` when ready to design in depth.

## Format

Each item has an ID, title, logged date, severity, short description (3–5 lines),
trigger/deadline if any, and status.

**Categories:**
- **Proposal** — new feature suggested but not yet designed
- **Debt** — known suboptimal state we're living with
- **Audit** — things to check periodically
- **Drift-watch** — things that could silently break when upstream/environment changes

**Status values:** `open` / `in-progress` / `promoted-to-spec` / `resolved` / `wontfix`.

When an item is promoted to a full spec, leave the entry here with status `promoted-to-spec` and link the spec file — don't delete; the backlog is also an audit trail of what we considered.

---

## BL-001: Audit downstream sync mechanism for CDF updates

**Logged:** 2026-04-22
**Category:** Audit
**Severity:** Medium
**Status:** Open

Existing downstream projects at older CDF `FRAMEWORK_VERSION` need a sync mechanism to pick up upstream fixes. `scripts/upgrade-project.sh` is presumed to handle this, but if its CDF-sync logic is stale, silently skips, or doesn't update `.claude/framework/` files, downstream projects miss landed fixes — e.g., FRAMEWORK_VERSION 4.2.2's Context7 detection and stop-checklist `--no-merges`/`CURRENT_HAS_SOURCE` improvements.

**Scope:** read `upgrade-project.sh`'s CDF handling; verify it pulls fresh CDF clone; verify it replaces `.claude/framework/` files correctly; verify `FRAMEWORK_VERSION` is updated in the downstream project; add regression test in `tests/upgrade-path-tests.sh`; document user-facing invocation in `docs/user-guide.md`.

**Trigger:** Before the next major CDF upstream fix that downstream projects need to pick up, OR after a downstream project reports missing a fix.

**Related:** CDF upstream commits `a640ba8`, `fd8469a`, and `4.2.2`-era changes; solo-orchestrator's BUG-001 and BUG-007 "Superseded" updates.

---

## BL-002: Handle GitHub free-tier branch-protection 403 gracefully

**Logged:** 2026-04-22
**Category:** Debt
**Severity:** Medium
**Status:** Closed (2026-04-27, PR #36, commit 50c0430)

Surfaced during live-API verification of the host-aware repo gate. On free-tier GitHub personal accounts, branch protection is unavailable on private repos (API returns HTTP 403 *"Upgrade to GitHub Pro or make this repository public to enable this feature."*). The current GitHub driver fails hard: `host_configure_protection` returns non-zero, the init.sh flow aborts, and the user gets a cryptic "failed to configure protection" message without the tier context.

**Scope:** In `scripts/host-drivers/github.sh`, detect the specific 403 response body mentioning "Upgrade to GitHub Pro" and:
1. Print a clear remediation message explaining the tier limitation (upgrade to Pro / use public / accept risk).
2. Offer to fall back to an attestation-style flow matching the `other` host path (user confirms they'll configure protection manually when they have Pro).
3. Record the attestation in `process-state.json` so the backstop gate can recognize it.

Similar check for GitLab and Bitbucket tier restrictions if their equivalent exists (GitLab's free tier allows branch protection on all projects; Bitbucket's free tier includes branch restrictions; neither currently has this issue).

**Trigger:** Before any free-tier user tries to use the framework in `private` mode. Workaround documented in `docs/builders-guide.md` § Repository Setup.

**Related:** Live-API verification on 2026-04-22. Orphan test repos in user's GitHub account needing manual cleanup.

---

## BL-003: Full end-to-end init.sh test against mocked host CLIs

**Logged:** 2026-04-22
**Category:** Audit
**Severity:** Medium
**Status:** Closed (2026-06-27, PR #59, commit f684aa7) — umbrella closed; sub-entries BL-003a (PR #61) and BL-003b (PR #62) cover gitlab/bitbucket follow-up coverage

Plan Task 10.1 was deferred during inline execution. Current test coverage: driver-level unit tests (mocked CLIs) and three regression cases (lancache-pattern, missing host field, protection drift). Missing: a "happy path" test that runs `init.sh`'s new `create_and_protect_remote` end-to-end against mocked `gh`/`glab`/`curl` and verifies all post-conditions (manifest host field set, CI template at correct host-specific path, `process-state.json` `phase2_init.steps_completed` populated).

**Scope:** add `tests/host-drivers/e2e-init.test.sh`. For each host (github/gitlab/bitbucket/other), scaffold a minimal init environment, run `create_and_protect_remote`, assert post-state.

**Trigger:** Before refactoring `init.sh`'s host flow; any change there risks silent regression without this test.

---

## BL-004: Upgrade-path regression test for flat→per-host template migration

**Logged:** 2026-04-22
**Category:** Audit
**Severity:** Medium
**Status:** Closed (2026-06-27, PR #58, commit a3ea907)

Plan Task 10.3 was deferred during inline execution. `scripts/upgrade-project.sh` now handles two migrations (flat CI templates → per-host subfolders; manifest `host` field backfill) but neither migration has a regression test.

**Scope:** add case to `tests/upgrade-path-tests.sh`. Scaffold a project with old flat `templates/pipelines/ci/*.yml` layout and manifest without `host` field, run upgrade, assert: existing `.github/workflows/ci.yml` preserved, templates moved to `github/` subfolder, `host` field backfilled to `github` (inferred from remote URL), process-state.json NOT auto-verified.

**Trigger:** Before the first downstream project attempts to upgrade to this framework version.

---

## BL-005: Parity test coverage for GitLab and Bitbucket drivers

**Logged:** 2026-04-22
**Category:** Debt
**Severity:** Low
**Status:** Resolved (2026-06-28, PR #81)

Driver-level test coverage varies: GitHub has 8 scenarios (full contract, both modes, drift cases); GitLab has 6 (most of contract, both modes); Bitbucket has 4 (name, require_cli, register_remote, parse_origin only — HTTP logic untested). Bitbucket's `host_configure_protection` and `host_verify_protection` HTTP calls are validated by code review only.

**Scope:** extend `tests/host-drivers/bitbucket.test.sh` with mock-curl fixtures for: configure_protection (personal + org payloads), verify_protection (all restriction types present → pass; missing restrictions → fail with specific messages), drift detection.

**Trigger:** Before the first solo-orchestrator user tries Bitbucket, OR whenever touching `bitbucket.sh`.

**Resolution (cycle 8, 2026-06-28):** Closed via test additions across three files plus one doc + backlog tweak. (1) `tests/host-drivers/bitbucket.test.sh` adds 6 unit-test scenarios — `host_configure_protection` (personal, org) and `host_verify_protection` (personal pass, personal fail, org pass, org fail) — exercising the previously-untested curl payloads under `_bb_curl` / `_bb_curl_no_body`. (2) `tests/host-drivers/gitlab.test.sh` adds 6 parity scenarios surfaced against `github.test.sh`: `host_require_cli` unauthed, `host_create_repo` public + dupe, `host_register_remote` replace existing, `host_configure_protection` org, `host_verify_protection` org pass. (3) `tests/host-drivers/mock-cli.sh` extended with stdin-drain guard (`[ -t 0 ] || cat >/dev/null`) so bitbucket's `--data-binary @-` POSTs don't race against stub exit on the success path; stderr discipline preserved (stub writes stderr only on unmatched-fixture exit 127). (4) `docs/cli-setup-addendum.md` § Bitbucket: `BITBUCKET_WORKSPACE` is now documented as required (not org-only) per audit code-host-bitbucket-1. Full host-drivers run-all + 3 e2e suites remain green.

---

## BL-006: Enforce Build Loop via pre-commit hook (commit-message-triggered)

**Logged:** 2026-04-22
**Category:** Debt
**Severity:** High
**Status:** Resolved (2026-04-24, PR #15)

Surfaced during the lancache project audit. `scripts/process-checklist.sh --start-feature` is advisory — a `feat(...)` commit can land without starting a Build Loop session, and `--record-feature` detects the drift only after the fact (post-commit audit). On lancache, ID1 and ID3 (MVP Cutline items per PRODUCT_MANIFESTO §5) were committed as `feat(init): ...` without going through the Build Loop; the drift was caught only when running `--record-feature` retroactively.

**Scope (locked during brainstorm):** add a new trigger in `pre-commit-gate.sh` that extracts the commit message and delegates to a new `process-checklist.sh --check-commit-message "MSG"` subcommand. When the message subject starts with `feat`, `feat(scope)`, `feat!`, or `feat(scope)!`, enforce the same strict state check the existing file-heuristic path uses (feature started + first 5 build_loop steps done). Strict enforcement — no warns-then-blocks grace window, no `SOIF_*` bypass. Non-Cutline scaffolding must use `chore:`/`build:`/`ci:`/`docs:` instead. Derivative commits (amend, merge, revert, cherry-pick, squash-merge) are filtered and pass through. Editor-case commits (no `-m`) fall through to the existing file-heuristic path.

**Trigger:** Before another MVP Cutline ID can drift past the Build Loop unnoticed. Coupled with BL-007 (shipped PR #14) — the doc rule defines what the hook enforces; this is the mechanical-enforcement companion.

**Related:** lancache project Phase 2 audit, 2026-04-22; path-forward decision to use pre-commit (not post-commit) per technical constraint that post-commit hooks cannot block. BL-007 (PR #14) shipped the doctrinal rule on 2026-04-23; BL-006 mechanically enforces it.

**Spec:** `docs/superpowers/specs/2026-04-23-build-loop-precommit-enforcement-design.md` (committed 2026-04-23).

**Follow-ups logged as optional:** BL-010 (commit-msg git hook for editor-case), BL-011 (Cutline-ID-aware enforcement), BL-012 (retroactive scanning), BL-013 (squash-merge CI enforcement), BL-014 (commit-type hygiene).

**Resolution:** Implemented via spec above + plan `docs/superpowers/plans/2026-04-24-build-loop-precommit-enforcement-implementation.md`. Shipped in PR #15 (merged 2026-04-24 at `ec6083c`). Two-layer design: `pre-commit-gate.sh` extracts commit message (inline `-m`, heredoc, `-F file`) and filters derivative commits (amend, merge, revert, cherry-pick, squash, `MERGE_HEAD`); delegates policy to new `process-checklist.sh --check-commit-message "MSG"` subcommand. Feat-prefix regex `^feat(\([^)]*\))?!?:[[:space:]]` (case-sensitive per Conventional Commits). Shared helper `require_build_loop_state_for_commit` factored out of existing `check_commit_ready`; both file-heuristic and message-prefix paths now produce the spec's Case A/B remediation messages. 17 unit tests in `tests/test-check-commit-message.sh`, 7 integration tests (E33–E39) in `tests/edge-cases-scripts.sh`, all passing. Builder's Guide § "MVP Cutline Work Requires the Build Loop" gets a "Mechanical enforcement" paragraph; `claude-md.tmpl` gets a subordinate bullet; `upgrade-project.sh` gets a header changelog note (no migration code — existing upgrade flow copies the updated scripts). Security audit `docs/security-audits/bl-006-precommit-buildloop-enforcement-security-audit.md` — 0 open findings.

---

## BL-007: Builder's Guide rule — MVP Cutline IDs always require full Build Loop

**Logged:** 2026-04-22
**Category:** Debt
**Severity:** Medium
**Status:** Resolved (2026-04-23, PR #14)

Surfaced during the lancache project audit. Builder's Guide §2.0 (Phase 2 Init sub-steps) and §2.1+ (Build Loop) are distinct phases. A developer or AI reading CLAUDE.md can reasonably conclude that init-era feature work (during §2.0 steps 2–10: scaffolding, migrations, CI setup, Docker, backup verification) doesn't need the full Build Loop ceremony — which is exactly what happened on lancache when `feat(init): initial migration + runner` and `feat(init): structlog with correlation-ID propagation` were treated as init scaffolding. Both were actually MVP Cutline IDs (ID1 and ID3) that deserved full Build Loops.

**Scope:** explicit rule in Builder's Guide — "MVP Cutline items (F-IDs and ID-IDs per PRODUCT_MANIFESTO §5) ALWAYS require a full Build Loop, regardless of which Phase 2 sub-step they land in. If Phase 2 Init work (§2.0 steps 2–10) produces a commit that implements a Cutline ID, that commit must go through `--start-feature` → tests → implementation → audit → `--record-feature` just like any §2.1+ work."

Possibly pair with tooling enforcement in BL-006 that cross-references commit messages against a manifest-derived Cutline ID list — but doc-only is the minimum.

**Trigger:** Couple with BL-006 — the doc rule defines what the hook enforces.

**Resolution:** Implemented via spec `docs/superpowers/specs/2026-04-23-mvp-cutline-build-loop-rule-design.md` + plan `docs/superpowers/plans/2026-04-23-mvp-cutline-build-loop-rule-implementation.md`. Shipped in PR #14 (merged 2026-04-23 at `442c0d6`). Two-file doc change: new subsection "MVP Cutline Work Requires the Build Loop" in `docs/builders-guide.md` between §2.0 and §2.1 with rule + rationale + 3 worked examples + recovery guidance; new bullet in `templates/generated/claude-md.tmpl` "Your Constraints" block pointing at the Builder's Guide subsection. Rule is generic (no F-/ID- prefix convention forced). BL-006 will mechanically enforce this same rule via pre-commit hook — next up in the triage.

---

## BL-008: Rollback/abort workflow for recorded features and UAT sessions

**Logged:** 2026-04-22
**Category:** Debt
**Severity:** Medium
**Status:** Resolved (2026-04-23, PR #12)

Surfaced during the lancache project audit. When a feature gets recorded incorrectly (e.g., `--record-feature` called for a commit that shouldn't have been treated as a feature) or a UAT session is started but needs to be aborted, there's no sanctioned workflow. On lancache, the user is about to correct via direct `jq` edit of `build-progress.json` + `--reset uat_session` — workable but undocumented.

**Scope:** add `scripts/process-checklist.sh --unrecord-feature NAME` to cleanly remove a feature from `build-progress.json` (with confirmation prompt); document the existing `--reset uat_session` in CLAUDE.md's Testing & Bug Workflow section; possibly add `--abort-build-loop` if a feature was started but never finished and the orchestrator wants to scrap it without recording.

**Trigger:** Most immediate follow-up of the three — user is doing the manual fix via jq today. Smallest scope (new subcommand + docs); good quick-win to tackle first.

**Related:** lancache project Phase 2 audit, 2026-04-22. Tackling first per path-forward ordering.

**Resolution:** Implemented via spec `docs/superpowers/specs/2026-04-23-unrecord-feature-design.md` and plan `docs/superpowers/plans/2026-04-23-unrecord-feature-implementation.md`. Shipped in PR #12 (merged 2026-04-23 at `8550e82`). `scripts/test-gate.sh --unrecord-feature NAME` is the new subcommand; `--reset uat_session` / `--reset build_loop` are documented in CLAUDE.md's Testing & Bug Workflow section. 7 unit tests in `tests/test-unrecord-feature.sh` covering state transform + error paths; interactive wrapper verified via bash harness.

---

## BL-009: UAT template quality guardrails + platform-aware authoring

**Logged:** 2026-04-23
**Category:** Debt
**Severity:** Medium
**Status:** Resolved (2026-04-23, PR #13)

Surfaced during lancache project UAT Session 1 (2026-04-22 → 2026-04-23). The framework's UAT template accepts schema-valid-but-operationally-broken scenarios: no system context, implicit working directory, cross-scenario dependencies, vague pass/fail criteria, non-deterministic expected-output matching, informal cleanup, unmarked optional dependencies. The Orchestrator's review after first generation: *"The tests are not stating what system this is done on, it doesn't walk through the tests step by step and makes assumption the tester knows where everything is."* Plus a platform-variance gap: the existing template's example is desktop-CLI shaped and doesn't translate to web, mobile, MCP-server, or long-tail platforms.

**Scope:** three-layer guardrail — universal HTML-comment quality checklist + anti-pattern list; per-platform reference examples (pre-flight + scenario) for each of solo's 4 first-class platforms under `templates/uat/references/`; interactive co-build protocol for `other` platform; pattern-based `scripts/lint-uat-scenarios.sh` invoked by the agent before saving populated UAT files. Plus templates reorganized into `templates/uat/` subdirectory, partial MD-template parity (pre-flight reminder + HTML pointer), new `docs/uat-authoring-guide.md`, and auto-migration via `upgrade-project.sh`.

**Trigger:** tackled now, ahead of BL-006/BL-007 — lancache pain is active and the fix is bounded (one spec, one plan). BL-006 and BL-007 remain queued afterward per the agreed triage order.

**Spec:** `docs/superpowers/specs/2026-04-23-uat-template-quality-design.md` (committed 2026-04-23 at `7b3dfff`).

**Resolution:** Implemented via spec above + plan `docs/superpowers/plans/2026-04-23-uat-template-quality-implementation.md`. Shipped in PR #13 (merged 2026-04-23 at `9f11c88`). Three-layer guardrail: universal HTML checklist + 4 per-platform reference pairs + `scripts/lint-uat-scenarios.sh` pattern linter. `other` platform handled via 5-question co-build protocol in `docs/uat-authoring-guide.md § 5`. Templates reorganized to `templates/uat/` subdirectory. `upgrade-project.sh` migration block for existing projects. 11 linter unit tests + 7 integration tests (E26–E32 in edge-cases-scripts.sh), all passing.

---

## BL-010: `.git/hooks/commit-msg` for editor-case & human-terminal coverage

**Logged:** 2026-04-23
**Category:** Proposal
**Severity:** Low
**Status:** Open — Optional (evaluate when a concrete need arises)

Punted from BL-006. Install a local `commit-msg` git hook via `init.sh` that invokes `scripts/process-checklist.sh --check-commit-message "$(head -n1 "$1")"`. Extends enforcement to two populations the PreToolUse hook cannot reach: (a) `git commit` with no `-m` flag (editor opens), and (b) human-Orchestrator commits from the terminal. The BL-006 design was explicitly built so this is a pure addition — no refactor needed.

**Trigger:** A concrete case where an editor-opened or human-typed `feat:` commit drifts past the Build Loop. Lancache pain was AI-agent authored only, so there is no current signal this matters.

**Tradeoff:** adds a second enforcement site to keep in sync with the PreToolUse hook; meaningful surface-area increase on `init.sh`. Worth it only if the gap bites.

**Related:** BL-006 spec § 10 (out-of-scope note); `pre-commit-gate.sh` architecture is Claude-only by design.

---

## BL-011: Cutline-ID-aware enforcement

**Logged:** 2026-04-23
**Category:** Proposal
**Severity:** Low
**Status:** Open — Optional (evaluate when a concrete need arises)

Punted from BL-006. Parse `PRODUCT_MANIFESTO.md §5` for F-/ID- Cutline identifiers and require commits that touch Cutline work to explicitly reference the ID (e.g., `feat(ID1): ...`), cross-checking that each Cutline ID gets exactly one Build Loop. Catches drift where Cutline work masquerades as a bugfix (`fix(ID1): ...`) or doesn't mention the ID at all.

**Trigger:** A concrete case where a Cutline item drifts under a non-`feat` commit prefix after BL-006 ships. BL-006 closes the `feat:` gap; BL-011 would close a hypothetical `fix:`/`refactor:` gap.

**Tradeoff:** forces every project to adopt an F-/ID- prefix convention in their manifest. BL-007 deliberately kept the rule generic — no ID convention imposed. BL-011 would re-impose one.

**Related:** BL-006 spec § 10; BL-007 doctrinal decision to keep the Cutline rule convention-free.

---

## BL-012: Retroactive scanning for drifted feature commits

**Logged:** 2026-04-23
**Category:** Proposal
**Severity:** Low
**Status:** Open — Optional (evaluate when a concrete need arises)

Punted from BL-006. Scan git history for `feat:`-prefixed commits with no corresponding Build Loop recorded in `.claude/build-progress.json`. Report drift and optionally walk the user through `test-gate.sh --record-feature` reconciliation for each.

**Trigger:** A project onboarding to solo-orchestrator mid-stream wants to audit its git history for past Cutline drift. Today, `test-gate.sh --record-feature` handles one-at-a-time post-hoc recording; BL-012 would batch it.

**Tradeoff:** the hook enforces forward-only by design — the backlog's position is that historical commits don't need retroactive gating. BL-012 only matters if a user explicitly asks for history audit tooling.

**Related:** BL-006 spec § 10; existing `test-gate.sh --record-feature` post-hoc path.

---

## BL-013: Squash-merge server-side enforcement via CI

**Logged:** 2026-04-23
**Category:** Proposal
**Severity:** Low
**Status:** Open — Optional (evaluate when a concrete need arises)

Punted from BL-006. `gh pr merge --squash` runs on the remote host, outside the PreToolUse hook's reach. Any enforcement there needs CI — a GitHub Actions workflow (and GitLab CI / Bitbucket Pipelines equivalents) that reads the squash-merge commit message and rejects the merge if it's `feat:`-prefixed and the branch never recorded a Build Loop.

**Trigger:** A concrete case where a Cutline item is merged via squash-merge without a matching Build Loop on the branch. Requires solo-orchestrator's host drivers to gain CI-workflow templates for all three hosts.

**Tradeoff:** cross-host workflow parity is non-trivial; secrets and state-file access from CI add complexity. The pre-commit gate catches drift at authoring time, which is the more common failure mode.

**Related:** BL-006 spec § 10; host driver architecture (`scripts/host-drivers/`).

---

## BL-014: Commit-type hygiene enforcement

**Logged:** 2026-04-23
**Category:** Proposal
**Severity:** Low
**Status:** Open — Optional (evaluate when a concrete need arises)

Punted from BL-006. Prevent mis-typed commit types — e.g., a real feature disguised as `chore:` or `refactor:` to evade the BL-006 gate. Would require intent inference from the staged diff (lines added to `src/`, new public API surface, new test files asserting behavior) combined with the declared commit-type.

**Trigger:** Observed abuse of the `chore:`/`build:`/`ci:`/`docs:` escape route in BL-006 — i.e., a Cutline feature committed as `chore:` to bypass the gate. Today this is reviewer/author judgment.

**Tradeoff:** intent inference from diffs is brittle and prone to false positives. Likely better addressed by code review norms or an Agent-side lint rather than a pre-commit gate.

**Related:** BL-006 spec § 3 (escape-route decision: Conventional Commits type) and § 10 (out-of-scope note).

---

## BL-015: Pending-approval sentinel reader (Solo side)

**Logged:** 2026-04-25
**Category:** Debt
**Severity:** High
**Status:** Resolved (2026-04-25, PR #16)

Surfaced during the lancache 2026-04-24 incident review. CDF 4.2.3 (`f55c8bc`) introduced `.claude/pending-approval.json` as a sentinel the agent writes when offering structured options to the user; the CDF stop-hook honors it (exits silently, breaking the "Complete these, then finish" pressure loop). Solo's pre-commit-gate currently does NOT honor it — meaning even with the stop-hook silenced, an agent under rationalization pressure can still commit unilaterally. BL-015 closes the symmetric gap.

**Scope (locked during brainstorm 2026-04-24/25):**
- New helper `scripts/pending-approval.sh` with 5 subcommands (`--offer`/`--resolve`/`--clear`/`--status`/`--validate`).
- New `pa_check()` block in `scripts/pre-commit-gate.sh` between `--no-verify` (security) and `--amend` (workflow).
- New bullet in `templates/generated/claude-md.tmpl` Construction Rules.
- New "Structured Decision Points" subsection in `docs/builders-guide.md`.
- One-line changelog note in `scripts/upgrade-project.sh`.
- 17 unit tests + 8 integration tests.

**Locked design parameters:** rich JSON-aware deny reason (parses sentinel, reflects question/options/recommendation back); blocks both `git commit` and `gh pr create`; refuses double-`--offer`; matches CDF's "existence alone suffices" semantics; punts staleness handling (manual `rm` recovery). Position in `pre-commit-gate.sh` chosen so security gates (SOIF_*, no-remote, --no-verify) fire first but workflow gates (--amend, bl006_check) fire after — pending approval upgrades the existing --amend warn into a hard block.

**Upstream dependency:** CDF 4.2.3 — already shipped and verified on 2026-04-25.

**Trigger:** Lancache 2026-04-24 commit-structure rationalization incident. Coupled with the CDF stop-hook fix; both enforcement points needed for the mechanism to be effective.

**Spec:** `docs/superpowers/specs/2026-04-25-pending-approval-sentinel-reader-design.md` (committed 2026-04-25).

**Resolution:** Implemented via spec above + plan `docs/superpowers/plans/2026-04-25-pending-approval-sentinel-reader-implementation.md`. Shipped in PR #16 (merged 2026-04-25 at `e9364cf`). New `scripts/pending-approval.sh` helper with 5 subcommands (`--offer`/`--resolve`/`--clear`/`--status`/`--validate`); atomic write via `mktemp + mv`; refuses double-offer. New `pa_check()` block in `scripts/pre-commit-gate.sh` between `--no-verify` (security) and `--amend` (workflow): blocks `git commit` and `gh pr create` when sentinel present, with rich JSON-aware deny reason reflecting question/options/recommendation back to the agent. Falls back to malformed-reason text per CDF 4.2.3 contract. 17 unit tests in `tests/test-pending-approval.sh`, 8 integration tests (E40–E47) in `tests/edge-cases-scripts.sh`. Builder's Guide gets new `### Structured Decision Points` subsection documenting lancache 2026-04-24 incident, lifecycle, and upgrade asymmetry. `claude-md.tmpl` gets new Construction Rules bullet. `upgrade-project.sh` header changelog updated. Security audit `docs/security-audits/bl-015-pending-approval-sentinel-reader-security-audit.md` — 0 open findings.

---

## BL-016: init.sh non-interactive mode (--non-interactive + --config)

**Logged:** 2026-04-25
**Category:** Debt
**Severity:** High
**Status:** Resolved (2026-04-25, PR #19)

Surfaced by UAT 2026-04-25 finding U-A — confirmed by 8 of 13 agents (highest-frequency finding). `init.sh` has only `--dry-run` and `--help` flags; the entire flow is interactive (`prompt_input` / `prompt_choice` for ~15 inputs). Blocks UAT, CI, scripted onboarding, and AI-orchestrator-driven project creation. Agents currently work around this with fragile heredoc drivers that break when prompt order changes (Docker install state, host CLI presence, language list filtering by platform).

**Scope (locked during brainstorm 2026-04-25):**
- New `--non-interactive` mode flag + `--config FILE` (JSON) + `--validate-only` + `--help-non-interactive` + ~12 per-input flags (`--project`, `--platform`, `--track`, `--deployment`, `--gov-mode`, `--language`, `--project-dir`, `--git-host`, `--visibility`, `--remote-url`, `--branch-protection-attested`, `--allow-existing-dir`, `--description`).
- New `collect_inputs_non_interactive()` function in init.sh; existing 2500-line interactive block UNTOUCHED (Approach A — separate code paths).
- Three-pass validation (schema, context-required, resource) with uniform `[FAIL] init.sh non-interactive: ... Reason/Action/Context` error format.
- 4-line surgical change in `create_and_protect_remote()` per host-related variable to check new top-level vars before falling back to `intake-progress.json`/prompts.
- 26 unit tests + 8 integration tests + re-test sweep on 8-10 UAT configs.
- Builder's Guide gets a "Scripted / Non-Interactive Project Initialization" subsection; `claude-md.tmpl` gets one Operations Reference bullet.

**Locked design parameters:** strict mode (separate code path); CLI flags + JSON config (both supported, flag wins on conflict); conditional-required (project/platform/deployment/language always; gov-mode/remote-url/branch-protection-attested by context); fail-fast on missing dependencies (no auto-install); kebab-case-full flag naming; JSON config in `snake_case` matching framework state files.

**Trigger:** UAT 2026-04-25 sweep — 8/13 agents flagged init.sh as the top blocker for scripted UAT/CI. The `prompt_choice` EOF guard (PR #18) was a safety net; this is the proper fix.

**Spec:** `docs/superpowers/specs/2026-04-25-init-sh-non-interactive-design.md` (committed 2026-04-25).

**Follow-ups logged for sibling scripts:** BL-017 (intake-wizard.sh non-interactive), BL-018 (upgrade-project.sh non-interactive), BL-019 (verify-install.sh non-interactive audit).

**Resolution:** Implemented via spec above + plan `docs/superpowers/plans/2026-04-25-init-sh-non-interactive-implementation.md`. Shipped in PR #19 (merged 2026-04-25 at `cb7633b`). New `--non-interactive` mode with ~12 per-input flags + JSON `--config FILE` support (flag-overrides-config). Three-pass validation (schema, context-required, resource) with uniform `[FAIL] init.sh non-interactive: ...` error format. New `--validate-only` for smoke-testing without scaffolding. New `--help-non-interactive` reference output. New `collect_inputs_non_interactive()` function + new top-level vars (`GOV_MODE`, `GIT_HOST`, `VISIBILITY`, `REMOTE_URL`, `BRANCH_PROTECTION_ATTESTED`, `ALLOW_EXISTING_DIR`). Surgical changes in `create_and_protect_remote()` so non-interactive resolved values flow through. 26 unit tests in `tests/test-init-non-interactive.sh`, 8 integration tests (E48–E55) in `tests/edge-cases-scripts.sh`. Builder's Guide gets new "Scripted / Non-Interactive Project Initialization" subsection. `claude-md.tmpl` gets new bullet. `upgrade-project.sh` header changelog updated. Existing interactive flow UNTOUCHED (Approach A — separate code paths). Security audit `docs/security-audits/bl-016-init-non-interactive-security-audit.md` — 0 open findings.

---

## BL-017: intake-wizard.sh non-interactive mode

**Logged:** 2026-04-25
**Category:** Debt
**Severity:** Medium
**Status:** Parked — 2026-06-29 recon found no operator demand in 60+ days across 4 waves of intake-wizard work. Field-specific flags shipped piecemeal cover known automation needs: `--data-classification` + `--zdr-attested` (PR #105, tier-crosscheck-6), `--upgrade-to-production` / `--upgrade-track` / `--upgrade-deployment` / `--to-sponsored-poc` / `--to-private-poc` (tier-promotion paths), `--resume` (session continuation). Re-evaluate when a holistic non-interactive harness use case surfaces (e.g., scale scaffolding 100+ projects/day, headless CI Phase-1 setup, AI-agent-driven full Phase-1 automation).

Sibling-script follow-up logged when BL-016 shipped. `scripts/intake-wizard.sh` has `--upgrade-to-production` and `--upgrade-deployment` flags but no overarching `--non-interactive` semantic for the initial intake interview (Sections 1–8 of the wizard). Lower urgency than init.sh because the wizard is typically run once per project; init.sh is the high-frequency entry point.

**Scope (suggested when promoted to spec):** add `--non-interactive` flag mirroring BL-016's design — per-section input flags, JSON `--config FILE` support, three-pass validation, `--validate-only`, uniform error format. Keep the existing interactive flow untouched (Approach A from BL-016).

**Trigger:** an explicit need for scripted intake (CI pipeline that creates many similar projects, agent-driven intake automation).

**Recon evidence (2026-06-29):** `Reports/2026-06-29-backlog-reconciliation-plan.md` § BL-017 recon. `grep -E "non.?interactive|NON_INTERACTIVE|--config" scripts/intake-wizard.sh` finds only audit-comment references, no flag implementation. Tests that exercise intake-wizard use only `--resume` or piped `</dev/null` (the latter only as edge-case fixture). PRs that touched intake-wizard since 2026-04-27 (#83, #99, #104, #105) added field-specific flags or sourceability, never a holistic `--non-interactive` mode.

**Related:** BL-016 spec §12 (out-of-scope items); `Reports/2026-06-29-backlog-reconciliation-plan.md`.

---

## BL-018: upgrade-project.sh non-interactive mode

**Logged:** 2026-04-25
**Category:** Debt
**Severity:** Medium
**Status:** Closed (2026-04-27, PR #33, commit e30759f)

Sibling-script follow-up logged when BL-016 shipped. `scripts/upgrade-project.sh` already has `--track`, `--deployment`, `--to-production`, `--to-sponsored-poc` flags but no overarching `--non-interactive` semantic. Defaults are mostly already non-prompting; the gap is explicit input validation (uniform error format) + `--validate-only` smoke-test mode.

**Scope (suggested):** wrap the existing flag set in a `--non-interactive` mode that adds the BL-016 validation/error/validate-only patterns. Smaller than BL-017 because the underlying flags already exist.

**Trigger:** when scripted upgrades become a frequent operation (post-BL-017 likely).

**Related:** BL-016 spec §12.

---

## BL-019: verify-install.sh non-interactive audit

**Logged:** 2026-04-25
**Category:** Audit
**Severity:** Low
**Status:** Open

Sibling-script follow-up logged when BL-016 shipped. `scripts/verify-install.sh` already has `--check-only` and `--auto-fix` flags, both of which are arguably non-interactive variants. Audit task: confirm no remaining interactive prompts in those modes. The framework-self-contamination incident (UAT 2026-04-25 U-N) was triggered by `verify-install.sh` running outside a project — the U-N guard in PR #18 prevents that, but the script's "auto-create stub artifacts" remediation behavior (UAT U-M) is also worth re-examining.

**Scope:** read `verify-install.sh` end-to-end; identify any interactive `read`/`prompt_*` calls in `--check-only` or `--auto-fix` paths; if any exist, either remove or guard them behind a non-interactive default.

**Trigger:** opportunistic — pair with the next visit to verify-install.sh code.

**Related:** BL-016 spec §12; UAT 2026-04-25 U-M (verify-install.sh auto-creates stub artifacts when run outside a real project).

---

## BL-020: pre-commit-gate.sh `\bgit\b.*\bcommit\b` regex over-broad

**Logged:** 2026-04-26
**Closed:** 2026-04-27 — commit `b9c4c4c` ("fix(hooks,docs): tighten pre-commit-gate classifier; clarify UAT step semantics (BL-020 + BL-022)"). The classifier was extracted into the named helper `_is_git_commit` in `scripts/pre-commit-gate.sh:81-93` using the anchored regex `(^|[^"'\''])git[[:space:]]+commit\b`; all 6 inline regex call sites (lines 123, 136, 187, 216, 231, 319) were replaced with calls to the helper. Regression coverage: `tests/test-pre-commit-gate-classifier.sh` (6/6).
**Category:** Debt
**Severity:** Medium
**Status:** Closed

`scripts/pre-commit-gate.sh:253` classifies a Bash command as "git commit" via `grep -qE '\bgit\b.*\bcommit\b'`. The regex matches any command line that contains both substrings, not just `git commit` invocations. Concrete false-positives:
- `cat scripts/pre-commit-gate.sh | grep "git commit"` — Claude tries to read the gate's own source while debugging, gets blocked because the command text itself contains both `git` and `commit`.
- `rg "git commit" docs/` — docs grep blocked.
- Multi-command lines like `git status; echo commit` — incidentally tripped.

Effect: when an agent tries to inspect or grep the gate scripts (legitimate read-only debugging), the very gate they're inspecting denies the read. Adds friction during framework debugging sessions.

**Scope:** tighten the classifier. Options:
1. Anchor the regex to actual git invocations: `^(git|.*[;&|]\s*git)\b.*\bcommit\b` and reject any command containing pipes or strings matching the literal `"git commit"` substring as text.
2. Parse the command's first token (post `bash -c` unwrap, post `cd && ...` chain) and only check classification if it's literally `git`.
3. Whitelist read-only invocations (`grep`, `cat`, `rg`, etc.) before applying the classifier.

**Trigger:** opportunistic — fix when next touching `pre-commit-gate.sh`.

**Related:** Surfaced from lancache UAT-2 session 2026-04-26 (operator reported handoff churn). Same hook also has the BL-021 over-blocking behavior.

---

## BL-021: config-guard.sh allowlist excludes read-only `git` subcommands

**Logged:** 2026-04-26
**Closed:** 2026-04-27 — CDF commit `eee6bb3` ("fix(config-guard): allow read-only git inspection of protected paths (BL-021)") on `~/.claude-dev-framework` main. The fix uses exactly the suggested pattern: a read-only `git` subcommand allowlist (`diff|log|show|blame|status|ls-files|cat-file|rev-parse|reflog|describe|name-rev|grep`) placed before the existing `cat|head|...` allowlist at `hooks/config-guard.sh:40-43`. Mutating subcommands (`add`, `checkout`, `restore`, `rm`, `mv`, `commit`, `stash`, `reset`, `clean`, `apply`, `update-ref`) remain blocked. Fixed upstream in CDF per the cross-repo preference; no Solo-side shim needed.
**Category:** Debt
**Severity:** Medium
**Status:** Closed

`~/.claude-dev-framework/hooks/config-guard.sh:41` allows read-only Bash inspection of `.claude/*` files via a hardcoded allowlist: `cat|head|tail|less|more|wc|file|stat|ls|grep|rg|awk|bat`. `git` is absent. Concrete false-positives blocked despite being purely read-only:
- `git diff .claude/manifest.json`
- `git log --oneline .claude/manifest.json`
- `git show HEAD:.claude/manifest.json`
- `git blame .claude/manifest.json`
- `git status .claude/`

Effect: a debugging Claude session can't inspect the history or current diff of framework state files, so investigations of "why did manifest end up like this" require operator handoff. Same handoff-churn pattern as BL-020.

Note: write-side `git` commands (`git add`, `git checkout --`, `git restore`, `git rm`, `git mv` against `.claude/*` paths) MUST stay blocked — those mutate framework state. Allowlist must distinguish read-only subcommands from mutating ones.

**Scope:** extend the allowlist to recognize specific read-only `git` subcommands. Suggested patterns:
```bash
if echo "$COMMAND" | grep -qE '^\s*git\s+(diff|log|show|blame|status|ls-files|cat-file|rev-parse|reflog|describe|name-rev|grep)\b'; then
  exit 0
fi
```
(Place before the existing `cat|head|...` allowlist.) Keep existing block on `git add`, `git checkout`, `git restore`, `git rm`, `git mv`, `git commit`, `git stash`, etc.

**Trigger:** ship together with BL-020 (same hook-author surface) OR opportunistic during next CDF maintenance pass.

**Related:** Lives in CDF (`~/.claude-dev-framework/hooks/config-guard.sh`) — fix upstream per the cross-repo preference (memory `feedback_cross_repo_fixes.md`); a Solo-side shim is not appropriate here. BL-020 is the symmetric Solo-side issue.

---

## BL-022: UAT step semantics ambiguous — `remediation_complete` and `gate_passed` framing

**Logged:** 2026-04-26
**Closed:** 2026-04-27 — commit `b9c4c4c` (same commit as BL-020 — "fix(hooks,docs): tighten pre-commit-gate classifier; clarify UAT step semantics (BL-020 + BL-022)"). `docs/builders-guide.md:1252-1259` now carries the unambiguous framing: `remediation_complete` = "all remediation work is written and tested locally" (NOT "merged to remote"), with the explicit caution "Do NOT wait for the commit/PR to mark this — that creates the chicken-and-egg confusion"; `gate_passed` = "test-gate has been re-cleared locally" (NOT post-merge CI state). The intended workflow (write → tests green → `--reset-counter` → mark `remediation_complete` → mark `gate_passed` → commit → push → PR) is documented step-for-step.
**Category:** Debt (docs/guidance)
**Severity:** Medium
**Status:** Closed

UAT_STEPS as defined in `scripts/process-checklist.sh:30` are: `agents_dispatched template_generated orchestrator_notified results_received completeness_verified bugs_consolidated triage_complete remediation_complete gate_passed`. The last two have ambiguous framing in the framework's docs:

- `remediation_complete` — Does this mean (a) "all fix code has been written and tests are green locally" or (b) "all fixes are merged to main"? The `process-checklist.sh:900` gate blocks source commits while `uat_completed < 9`, which implies (a) — fixes must be marked complete BEFORE the commit that ships them. But agents reading the step name as "shipped to remote" hit a logical contradiction (can't mark complete until commit, can't commit until marked complete).

- `gate_passed` — Does this mean (a) "test-gate counter has been reset and tests pass locally" or (b) "test-gate is green post-merge"? Same ambiguity.

Effect: a recent lancache UAT-2 agent session (2026-04-26) spent 19+ minutes in handoff-theater churn because the agent read interpretation (b), concluded marking before committing was "borderline" and "tripping framework intent", and bounced commits back to the operator instead of completing the documented sequence.

The framework's intended workflow is:
1. Write fixes locally; tests green.
2. Run `scripts/test-gate.sh --reset-counter`.
3. Mark `remediation_complete` (truthful: local fixes done).
4. Mark `gate_passed` (truthful: counter reset, tests green).
5. Commit; gate now allows source commits.
6. Push, open PR.

**Scope:** clarify in `docs/builders-guide.md` (or wherever UAT_STEPS are documented) that:
- `remediation_complete` means "local remediation work done; ready to commit." NOT "shipped."
- `gate_passed` means "local gate-check passing; ready to commit." NOT "post-merge CI green."
- The commit-blocker at `process-checklist.sh:900` is intentional: it forces operators to acknowledge the local remediation state before committing during UAT, NOT to gate the commit on post-merge state.
- Optionally: rename to `remediation_done_locally` / `gate_passed_locally` for sharper semantics.

**Trigger:** before the next UAT cycle in any project (lancache, solo-orchestrator self-test, downstream project).

**Related:** Surfaced from lancache UAT-2 session 2026-04-26. Pairs with BL-020 + BL-021 (all three contributed to the same handoff-churn incident). The `pre-commit-gate.sh` flow at line 250-275 implements the actual gate behavior.

---

## BL-023: Rev3 runbook `$GOV` unquoted expansion is fragile

**Logged:** 2026-04-27
**Category:** Debt (cosmetic)
**Severity:** Low
**Status:** Open

The rev3 sweep runbook at `Reports/uat-2026-04-26-rev3/RUNBOOK.md` Section A constructs the init.sh invocation with `$GOV` unquoted between flags:

```bash
bash "$FRAMEWORK/init.sh" --non-interactive ... $GOV --language ...
```

When `GOV="--gov-mode production"`, word-splitting produces two args (`--gov-mode`, `production`) — works in bash but is shell-fragility on the glide path. Under stricter shells or when the value contains spaces in the option text, this breaks.

Surfaced by rev3 sweep agent 7 as a documentation gap. All 12 rev3 agents successfully ran the existing form, so this is cosmetic, not blocking.

**Scope:** rewrite Section A's invocation to use an array or split `$GOV` into `$GOV_FLAG $GOV_VALUE`:

```bash
GOV_FLAG=""
GOV_VALUE=""
case "{SCENARIO}" in
  private_poc)   GOV_FLAG="--gov-mode"; GOV_VALUE="private_poc" ;;
  sponsored_poc) GOV_FLAG="--gov-mode"; GOV_VALUE="sponsored_poc" ;;
  production)    GOV_FLAG="--gov-mode"; GOV_VALUE="production" ;;
esac
bash "$FRAMEWORK/init.sh" --non-interactive ... ${GOV_FLAG:+$GOV_FLAG "$GOV_VALUE"} --language ...
```

Apply to any future runbook templates as well; the existing rev1/rev2 runbooks have the same shape and could be updated opportunistically.

**Trigger:** before the next sweep runbook is written.

**Related:** `Reports/uat-2026-04-26-rev3/TRIAGE.md` Gap 1.

---

## BL-024: `init.sh --branch-protection-attested` not recorded when push fails on `--git-host other`

**Logged:** 2026-04-27
**Category:** Debt (real bug)
**Severity:** Medium
**Status:** Resolved (2026-04-27, PR #38)

**Resolution:** `init.sh::create_and_protect_remote` reordered so the attestation prompt + record block runs BEFORE `git push` on the `--git-host other` path. Push failure no longer drops the attestation. New `tests/test-init-other-host-attestation.sh` covers the regression (2 cases: attestation persists on push failure, regression check that the flag is still required).

`init.sh::create_and_protect_remote` for the `--git-host other` path has the wrong order of operations relative to `--branch-protection-attested`. The flow at `init.sh:1768-1836`:

1. Resolve `remote_url` (from `--remote-url` or interactive prompt).
2. `git remote add origin "$remote_url"`.
3. `git push -u origin main || git push -u origin master`. **If push fails → `return 1`.**
4. Print "Since 'other' host is not API-verifiable, attest branch protection:".
5. Honor `BRANCH_PROTECTION_ATTESTED` (or prompt) → record attestation in `.claude/process-state.json::phase2_init.attestations.branch_protection`.

When the operator passes `--remote-url https://example.invalid/fake.git --branch-protection-attested` (the standard rev1/rev2/rev3 sweep pattern), the push at step 3 fails and the function returns 1 BEFORE the attestation block at step 4-5 runs. Init still completes overall (the U-B fix at `init.sh:1717-1730` wraps the call in `if ! ...`), but `phase2_init.attestations.branch_protection` is never written.

Reproduced 2026-04-27:

```
tmp=$(mktemp -d) && bash init.sh --non-interactive --project trace --platform web \
  --deployment personal --language typescript --git-host other \
  --remote-url https://example.com/fake.git --branch-protection-attested \
  --visibility private --project-dir "$tmp/proj" --allow-existing-dir
jq '.phase2_init.attestations // "MISSING"' "$tmp/proj/.claude/process-state.json"
# → "MISSING"
```

Real-world impact: with a real remote URL the push usually succeeds and the attestation IS recorded — so this hasn't been seen by users yet. But anyone running init in a context where the push fails (corporate firewall, momentary connectivity, fake URL for CI smoke-test) gets:
- init log says "Remote setup did not complete cleanly" and points at `check-gate.sh --repair`
- `process-state.json` lacks the attestation
- subsequent `check-gate.sh --preflight` (post-PR-#36) won't honor the attestation it never recorded
- `verify-init` will then report `branch_protection_configured` as failed

**Scope:** reorder the "other" branch in `create_and_protect_remote` so attestation runs BEFORE push (or alongside it as a checkpoint), since attestation is a forward-looking commitment by the operator and is independent of whether the push succeeds. Specifically:

1. Move the attestation prompt + record block to run AFTER `git remote add` but BEFORE `git push`. The attestation describes what the operator commits to — push success isn't a precondition.
2. Optionally: don't `return 1` on push failure when `BRANCH_PROTECTION_ATTESTED=true` — the operator has explicitly attested they'll set up the remote later, so log `print_warn` and continue.

TDD: a focused test in `tests/test-init-no-remote-creation.sh` (or sibling) that runs the repro flow and asserts `phase2_init.attestations.branch_protection.attested_by == "orchestrator"` after init.

**Trigger:** if a user reports init.sh "lost" their attestation, OR before any sweep that depends on the attestation being present in process-state.json. Lower priority than the user-facing tier-3 backlog items because the rev1/rev2/rev3 runbooks all worked around it (manual `jq` writes in agent test setup) — but it's a real correctness gap.

**Related:** `Reports/uat-2026-04-26-rev3/TRIAGE.md` Gap 2 (agent 2). Pairs conceptually with PR #36 (BL-002) which added a parallel attestation flow for github free-tier 403 — that one DOES record correctly because it runs after host_configure_protection completes (success or specific 403), not after a push.

---

## BL-025: Phase 2 init-verified state setup helper for tests

**Logged:** 2026-04-27
**Category:** Proposal (test infrastructure)
**Severity:** Low
**Status:** Open

Several T2 + R3 test cases needed to drive a project to "Phase 2 init verified" state to exercise the gates that depend on it (the dep-manifest classifier in `process-checklist.sh::check_commit_ready`, the build_loop gate, the UAT step semantics, the `--start-phase3` advance). The current happy path takes a real init + Phase 1 walk + 6 phase2_init `--complete-step` calls + manual `data_model_applied` mark + `initialization_verified` auto-complete. Both rev3 agents 2 and 6 had to do manual `jq` patching to reach the right state.

**Scope:** a `tests/test-helpers/init-phase2-verified.sh` helper that takes:
- a target tempdir path
- platform / track / deployment / gov_mode args (same shape as init.sh)
- shortcut flags for state-only setup (skip CLAUDE.md generation, skip framework clone, etc.)

…and produces a directory with `.claude/manifest.json`, `.claude/phase-state.json` (current_phase=2), `.claude/process-state.json` with `phase2_init.verified=true`, and the minimum filesystem artifacts (`.git/`, `package-lock.json` or equivalent, `.git/hooks/pre-commit`) so `verify-init` would mark it complete.

This isn't a public-facing helper — it's purely for the test suite. Could live alongside `tests/` or in a sibling `tests/helpers/` directory.

**Trigger:** when adding the next test that needs phase 2 verified state (e.g., a test for any post-T2 fix that depends on the gate context).

**Related:** `Reports/uat-2026-04-26-rev3/TRIAGE.md` Gap 3. Adjacent to BL-003 (end-to-end init.sh tests against mocked host CLIs) — same "make init.sh testable in a fresh tempdir" theme.

---

## BL-029: Bypass audit-log infrastructure

**Logged:** 2026-04-27 (calibration agent 5)
**Category:** Bug + Feature (correctness)
**Severity:** Critical
**Status:** Closed (2026-06-26, PR #46, commit 5d1996b; bypass-audit infrastructure shipped earlier via PR #40 (2026-05-04) and PR #41 (2026-05-14))

PostToolUse + Stop bypass-shaped-language detector writes structured rows to `.claude/bypass-audit.json`, plus a confirmation-phrase sentinel and the `escalate-to-user.sh` documented alternative. Always-on regardless of enforcement_level.

**Plan:** `docs/superpowers/plans/2026-04-28-bl029-bypass-audit-plan.md`
**Spec:** Agent-5 calibration deliverable at `Reports/uat-2026-04-27-calibration/results/agent-5.json`
**Audit follow-up:** PR #46 corrected hook envelope schema (`tool_result` → `tool_response`, `transcript` → `last_assistant_message`) and updated plan docs to match canonical Claude Code schema.

---

## BL-030: User-terminal enforcement model

**Logged:** 2026-04-28 (calibration brainstorm)
**Category:** Feature (process enforcement)
**Severity:** High
**Status:** Closed (2026-06-26, PR #48, commit 328c9c7; follow-ups PR #49, PR #51, PR #54)

Three-tier enforcement level (`no` / `light` / `strict`) configurable at init or via `reconfigure-project.sh --enforcement-level`. Tier semantics:

- **strict** (default + forced for sponsored_poc / production tiers): installs `.git/hooks/framework-gate.sh`, which sources `scripts/lib/enforcement-level.sh` + delegates to `process-checklist.sh --check-commit-ready` and `pre-commit-gate.sh --terminal-mode`. Block messages carry the W5/P1 teaching pattern (block reason + principle + procedure) sourced from `scripts/lib/gate-principles.sh`. `--no-verify` bypasses the gate but is captured by the SessionStart detector.
- **light**: same SessionStart detector; no filesystem gate; user-terminal commits land freely but are recorded in `.claude/bypass-audit.json`.
- **no**: detector self-no-ops; only Claude-side audit (BL-029) remains.

**Components shipped (PR upcoming):**
  - `scripts/lib/enforcement-level.sh` (read_enforcement_level, assert_choosable, validate_transition)
  - `scripts/lib/gate-principles.sh` (principle_for "<gate>")
  - `scripts/hooks/record-claude-commit.sh` (PostToolUse Claude-commit ledger)
  - `scripts/detect-out-of-band-commits.sh` (SessionStart out-of-band detector)
  - `scripts/install-filesystem-gates.sh` (idempotent installer/uninstaller for `.git/hooks/framework-gate.sh`)
  - `scripts/pre-commit-gate.sh --terminal-mode` flag for framework-gate composition
  - `init.sh` `--enforcement-level` + `--confirm-pitfalls` non-interactive flags + finalization (manifest merge, detection baseline, audit row, filesystem-gate install if strict)
  - `scripts/reconfigure-project.sh --enforcement-level` + `--reset-detection-baseline` transition flags
  - SessionStart + PostToolUse hook entries in the project template's `.claude/settings.json`
  - Test coverage: enforcement-level lib 10/10, record-claude-commit 5/5, out-of-band-detector 8/8, filesystem-gate-install 7/7, pre-commit-gate terminal-mode 3/3, gate-principles 3/3, init UX 8/8, reconfigure 7/7, bypass-audit schema 3/3, calibration replay 4/4 — 58/58 across the new BL-030 suites.

**Plan:** `docs/superpowers/plans/2026-04-28-bl030-enforcement-model-plan.md` (Task 1–12, executed as a single PR).
**Spec:** `docs/superpowers/specs/2026-04-28-bl030-enforcement-model-design.md`

**Audit follow-up:** the v2 audit finding `specs-plans-bl029-bl030-3` ("spec exists; ZERO implementation") is now closed.

**Audit follow-up:** the v2 audit finding `specs-plans-bl029-bl030-5` ("naive substring match in `scripts/hooks/record-claude-commit.sh` + missing --amend handling") is now closed. The BL-029 ledger recorder now uses the anchored regex `(^|[^"'\''])git[[:space:]]+commit\b` (verbatim sibling of the BL-020 fix in PR #53 on `scripts/pre-commit-gate.sh:81-93`), rejecting quote-preceded false-positives like `grep "git commit"`. `git commit --amend` is treated as a fresh ledger entry (option C from the audit response) — the amended SHA is recorded so the out-of-band detector classifies it as Claude-issued, and the original entry persists harmlessly as an orphan SHA in the append-only ledger. Regression coverage: `tests/test-record-claude-commit.sh` T6-T9 (9/9 total).

---

## BL-031: init.sh:2009 hardcodes GitHub-branded messaging for any driver returning exit 3

**Logged:** 2026-06-27
**Category:** Bug (UX, cross-driver)
**Severity:** Medium
**Status:** Closed — shipped 2026-06-27 (PR #65, commit `b2e080b`).

`scripts/host-drivers/gitlab.sh:120` returns exit 3 from `host_configure_protection` when the org-mode approvals PUT fails. `init.sh:2009` treats `_hcp_rc=3` as the GitHub-free-tier attestation fallback and surfaces a print_warn with the literal string `"Branch protection unavailable on this repo (free-tier limit)"` plus a print_info chain mentioning `"Upgrade to GitHub Pro"`. A GitLab user with partial token scopes lands in the wrong remediation flow with wrong-host messaging.

The exit code 3 was originally a github-specific signal ("free-tier 403 detected — fall back to attestation"). When the gitlab driver was added, exit 3 was reused for a different semantic (gitlab approvals PUT failed) without the init.sh dispatch being updated to disambiguate.

**Resolution:** option 1 (host-agnostic init.sh wording). The init.sh exit-3 branch (lines ~1998-2045) now parameterizes the warn/info on `$host` ("Branch protection unavailable via standard API on this $host repo" / "see $host driver remediation message above") and defers host-specific remediation to the driver's own stderr — which is already emitted before init.sh prints these lines. The driver code (github.sh:120-132, gitlab.sh:120) was deliberately not touched: the exit-3 contract ("I failed in a way you can attest around") is correct; the bug was init.sh interpreting that contract with GitHub-only words. The attestation reason string `github_free_tier` is retained for backward compat with `scripts/check-gate.sh` and `tests/test-check-gate.sh::T5`; broadening the reason taxonomy is out of scope for this fix.

**Regression test updated:** `tests/host-drivers/e2e-init-gitlab.test.sh::T6` now asserts the corrected behavior: init exits 0 (U-B contract preserved), log does NOT contain "GitHub Pro" or "free-tier limit", log DOES contain `"on this gitlab repo"` / `"gitlab driver remediation"` plus the gitlab driver's own `"approvals config failed"` stderr.

**Verification:** `tests/host-drivers/e2e-init-gitlab.test.sh` 6/6 PASS · `tests/host-drivers/e2e-init.test.sh` 5/5 PASS (github regression) · `tests/test-github-free-tier-403.sh` 4/4 PASS (driver unchanged).

**Related:** BL-003a (introduced the T6 detection test).

---

## BL-003a: init.sh GitLab end-to-end test (mocked CLI)

**Logged:** 2026-04-22 (originally as BL-003 sub-task; split for cycle 5 scope)
**Status:** Closed — shipped 2026-06-27 (PR #61, commit `fc9db0e`).

Adds `tests/host-drivers/e2e-init-gitlab.test.sh`: full init.sh e2e with mocked `glab` CLI + `GIT_CONFIG_GLOBAL` `pushInsteadOf` redirect to a local bare repo. Mirrors PR #59's github harness. Six scenarios: T1 personal success, T2 org success, T3 push fail, T4 repo-already-exists, T5 protection POST 403, T6 (documentary) gitlab-exit-3 cross-wiring at `init.sh:2009` — see BL-031.

---

## BL-003b: init.sh Bitbucket end-to-end test (curl-stub variant)

**Logged:** 2026-04-22 (originally as BL-003 sub-task; split for cycle 5 scope)
**Status:** Closed — shipped 2026-06-27 (PR #62, commit `c8585fa`).

Adds `tests/host-drivers/e2e-init-bitbucket.test.sh`: full init.sh e2e with mocked `curl` (bitbucket driver uses curl with `-u USER:PASS`, no CLI binary). PATH-prepended `curl` stub case-matches on `-X METHOD` + URL substrings (repo create POST, branch-restrictions GET/POST/DELETE). Configure-vs-verify GET ambiguity (same URL hit twice) resolved with a `$TMP`-side counter file. Five scenarios parallel to BL-003a (T1 personal success, T2 org success, T3 push fail, T4 slug-already-exists, T5 protection POST 403); no bitbucket analogue of BL-003a T6 because bitbucket has no exit-3 cross-wired branch — the BL-031 cross-wiring is gitlab-specific.

**Cycle 5 verifier watch-outs honored in the stub:**

  1. `scripts/host-drivers/bitbucket.sh::_bb_curl` pipes `2>&1` and the caller does `if ! resp=$(... | _bb_curl ...)`, so the stub MUST write stderr only on intentional failure modes — otherwise jq parses the error message as JSON and crashes the success path. Stub gates all stderr emission behind `if [ "$rc" -ne 0 ]` arms.
  2. POST/DELETE-with-body callsites pipe a JSON payload (`echo "$payload" | _bb_curl POST URL`); stub drains stdin (`cat >/dev/null`) on every POST arm including the failure path.
  3. `host_configure_protection` and `host_verify_protection` both GET `/branch-restrictions?pattern=main`. Counter file in `$TMP` disambiguates: first GET serves `MOCK_BB_PROTECT_GET_JSON_CONFIGURE` (default `{"values":[]}` — no prior restrictions), subsequent GETs serve `MOCK_BB_PROTECT_GET_JSON_VERIFY` (per-mode JSON satisfying `host_verify_protection`'s kind-count checks).

---

## code-upgrade-project-8: upgrade-project.sh --to-production deferred pre-condition guard

**Logged:** 2026-06-27 (cycle 6 verifier)
**Category:** Bug / governance
**Severity:** Major
**Status:** Closed — shipped 2026-06-27 (PR forthcoming, this commit).

`scripts/upgrade-project.sh --to-production` unconditionally flipped `POC_REMOVED=true` whenever the project had a `poc_mode` (lines 735-737), with no check that the deferred Pre-Phase-0 pre-conditions had actually been cleared. `docs/governance-framework.md:248` simultaneously promised the script "re-runs Section 8 of the intake wizard to capture the deferred pre-conditions" — a fictional control. Per `docs/governance-framework.md:230` Sponsored POC defers 3 of 6 Pre-Phase-0 items (insurance, liability, ITSM, backup maintainer; AI deployment path, sponsor, time-boxed exit criteria are upfront) and Private POC defers all 6; Production requires all 6 cleared.

**Resolution:** Inserted a gate in `scripts/upgrade-project.sh` that runs when `TO_PRODUCTION=true && CURRENT_POC_MODE != "" && CURRENT_DEPLOYMENT == organizational`. The gate parses the Pre-Phase 0 table in `APPROVAL_LOG.md`, walks rows 1-6, and counts a row satisfied when the Date column contains an ISO date `YYYY-MM-DD`. Parser uses awk-scoped section-walk (not the brittle `grep -A 30 ... | grep -c` pattern that PR #53 sanitized). Personal deployments skip the gate because `templates/generated/approval-log-personal.tmpl` pre-fills all 6 rows with `__TODAY__` at init. Operators driving `--non-interactive` can acknowledge missing rows via `--ack-preconditions=<N1,N2,...>` (validated to `^[1-6](,[1-6])*$`); each ack writes an `actor: "user_terminal"` row to `.claude/bypass-audit.json` with `details.action = "to_production_preconditions_acked"`. Failure mode emits a structured `_upgrade_fail` listing the missing row numbers AND their canonical Pre-Condition labels. `docs/governance-framework.md:248` downgraded to describe the gate-only behavior (no wizard re-run claim). 6 new tests in `tests/test-upgrade-to-production-preconditions.sh`; `tests/test-upgrade-paths.sh` T1 fixture seeded with a filled APPROVAL_LOG.md to keep the happy path green.

---

## code-check-gates-1: check-phase-gate.sh Phase 1→2 backstop ignores github_free_tier attestation

**Logged:** 2026-06-28 (cycle 7 slot 1)
**Category:** Bug / governance (silent-bypass-shaped false-fail)
**Severity:** Major
**Status:** Closed — shipped 2026-06-28 (PR forthcoming, this commit).

`scripts/check-phase-gate.sh:279-305` (the Phase 1→2 BACKSTOP block) unconditionally invoked `host_verify_protection "main" "$mode"` whenever `current_phase >= 2`, without first consulting `.claude/process-state.json::phase2_init.attestations.branch_protection.reason`. On legitimate github free-tier private repos — the demographic that BL-002 (PR #36) and BL-031 (PR #65) wired the attestation flow to support — the GitHub API returns 403 *"Upgrade to GitHub Pro or make this repository public to enable this feature."*, host_verify_protection returns non-zero, and the backstop emitted `[FAIL] Phase 1→2 backstop: protection verification failed` AND incremented the gate's `$issues` counter, causing the script to exit 1.

Operator-visible symptom: `scripts/check-gate.sh --preflight` PASSED (it correctly honors the attestation at `cmd_preflight:52-64`) while `scripts/check-phase-gate.sh` FAILED at the same moment with the same project state. Contradictory signals; the `[FAIL]` is structurally a silent-bypass-shaped false-fail (the gate "fails" without actionable remediation — the operator already attested at init time).

**Resolution:** ~10-line additive fix in `scripts/check-phase-gate.sh` mirroring the canonical pattern at `scripts/check-gate.sh::cmd_preflight` (lines 52-64). A new pre-check inside the Phase 1→2 backstop block reads `.claude/process-state.json::phase2_init.attestations.branch_protection.reason` via jq. When the value equals `github_free_tier`, the gate prints an `[OK]` line ("branch protection attested ... upgrade to GitHub Pro to enable API enforcement") and SKIPS the `host_verify_protection` call entirely (does not increment `$issues`). The existing `if host_load_driver` / `if host_verify_protection` branches are preserved as the else-arm — projects without an attestation continue to be verified against the live host API exactly as before. No broadening to `other_host_attestation` (per cycle 7 verifier scope: gate to known-good values only).

**Regression coverage:** new `tests/test-check-phase-gate-backstop-attestation.sh` with three cases:
- **T1 positive:** Phase-2 project + `manifest.json {host:"github", mode:"personal"}` + dated APPROVAL_LOG.md + process-state.json with `branch_protection.reason="github_free_tier"`. PATH-prepended `gh` stub returns 403 on any `/protection` GET (proves the test would FAIL without the fix). Assert backstop emits OK line and does not emit the FAIL line.
- **T2 negative (regression guard):** same shape WITHOUT the attestation; same gh stub. Assert backstop FAIL line surfaces and exit code is non-zero. Proves the fix did not over-broadly skip verification.
- **T3 coexistence:** runs `tests/test-check-gate.sh` end-to-end (incl. T5 `t5_preflight_honors_free_tier_attestation`) to confirm the canonical preflight contract is preserved across both scripts.

**Verification:** new suite 3/3 · `tests/test-check-gate.sh` 5/5 · `tests/test-check-phase-gate-counter-sanitizer.sh` 7/7 · `tests/test-init-other-host-attestation.sh` 2/2 · `tests/test-github-free-tier-403.sh` 4/4. Registered in `tests/full-project-test-suite.sh` (new TEST 0c section after the counter-antipattern lint, to keep the gate-validation backstops co-located).

**Related:** BL-002 (PR #36) introduced the attestation flow; BL-031 (PR #65) generalized cross-host attestation messaging; PR #71 (preflight branch) shipped the canonical pattern this fix mirrors. The case-sanitizer pattern from PR #53 was considered but not needed here — the jq output is used in a string equality test, not arithmetic, so no sanitizer is required.

---

## BL-032: Handle gitlab.com Free org-mode required-approvals 403 gracefully

**Logged:** 2026-06-28
**Category:** Debt
**Severity:** Medium
**Status:** Open

GitLab analog of BL-002. On gitlab.com Free, `PUT projects/:id/approvals` with `approvals_before_merge>=1` is a Premium-tier feature — Free returns HTTP 403 *"This feature is not available on your plan."* (exact wording has varied across GitLab releases — "premium", "ultimate", "not available on your plan", "feature is not available", "requires .* plan"). Organizational deployments on gitlab.com Free cannot clear the Phase 1→2 protection bar because the required-approvals invariant is structurally unavailable.

The driver remediation (this PR, `fix/host-gitlab-ci-status-stderr-approvals`) addresses the operator-recovery side: it pattern-matches the Premium-only response, returns a dedicated exit code (4), and prints a structured remediation listing upgrade / self-hosted / attestation-escape-hatch options. What's still open is the third option — the attestation flow itself.

**Scope:** In `scripts/host-drivers/gitlab.sh` and `scripts/init.sh`:
1. Add a `--approvals-attested` flag (and `SOLO_APPROVALS_ATTESTED=1` env var) honored by `host_configure_protection`. When set in org mode, skip the approvals PUT and record an attestation in `.claude/process-state.json::phase2_init.attestations.branch_protection.reason = "gitlab_free_tier_approvals"`.
2. Extend `scripts/check-phase-gate.sh` Phase 1→2 backstop to honor the new attestation reason (mirroring the existing `github_free_tier` branch added in PR #62 — see code-check-gates-1 entry above).
3. Update `docs/builders-guide.md` § Repository Setup to document the GitLab Free tier limitation alongside the existing GitHub free-tier note (line ~933).

The CI pipeline-success gate (code-host-gitlab-2 / `only_allow_merge_if_pipeline_succeeds`) is NOT Premium-gated on gitlab.com Free, so this BL is scoped strictly to the approvals API.

**Trigger:** Before the first organizational deployment on gitlab.com Free attempts `init.sh` in `org` mode.

**Related:** code-host-gitlab-8 audit finding (the gap that triggered this entry); BL-002 (the GitHub analog this mirrors); code-check-gates-1 (the canonical attestation-honoring backstop pattern this should reuse).

---

## BL-033: Migrate multi-stage install_cmds in templates/tool-matrix/*.json to structured shapes

**Logged:** 2026-06-28 (PR #92 verifier follow-up)
**Category:** Debt / Security hardening
**Severity:** Medium
**Status:** Open

Following the structured-dispatch hardening in `scripts/verify-install.sh::fix_tool_install` (PR #92 verifier blocker-1 close), the legacy `bash -c` fallback now REFUSES any install_cmd whose payload contains shell-chaining metacharacters (`;`, `|`, `` ` ``, `$(`, `<`, `>`, newline). Several existing tool-matrix entries use multi-stage shell pipelines that trip this gate:

- `gitleaks.install.linux_apt` (+ `linux_dnf` + `linux_pacman`) — `GITLEAKS_VERSION=$(curl ...) && curl ... | sudo tar -xz -C /usr/local/bin gitleaks`
- `k6.install.linux_apt` — `sudo gpg ... && echo 'deb ...' | sudo tee /etc/apt/sources.list.d/k6.list && sudo apt update && sudo apt install k6`
- `rust.install.darwin_brew` (+ `linux_apt`) — `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && source "$HOME/.cargo/env"`
- `context7.install.npm` — `echo y | claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp@latest` (bare `|` trips the gate)

Note: `docker.install.linux_apt` uses `sudo apt install ... && sudo usermod ...` — the `&&` is stripped before the metachar check, so this currently passes Layer 2 unchanged (but a future tightening should still consider migrating it for clarity).

**Scope:** Each entry needs either (a) a small wrapper script in `scripts/install-helpers/<tool>.sh` that the install_cmd invokes by absolute path (turning the multi-stage shell into a single argv invocation), or (b) the install delegated to a sanctioned package source (e.g. k6's official apt repo via cloud-init style provisioning). The wrapper-script approach preserves the structured-dispatch contract: the install_cmd becomes `bash scripts/install-helpers/gitleaks.sh` which Layer 1 doesn't currently match but Layer 2's metachar gate passes.

**Workaround until migrated:** operators on these tools currently see the DEPRECATED warning and a REFUSED install. Manual install per the matrix's `manual` instructions still works.

**Related:** PR #92 verifier review (blocker-1 close). VERIFY_INSTALL_NO_LEGACY_DISPATCH=1 env var exists for operators who want to enforce structured-only mode immediately.

---

## BL-042: init.sh `prompt_install` interaction with pipefail when stdin is closed

**Logged:** 2026-06-29 (PR #104 verifier follow-up — Wave 4 risk note 2)
**Category:** Bug / non-interactive UX (test-only workaround in tree)
**Severity:** Low (workaround in place; affects test ergonomics, not user-facing behavior)
**Status:** Open

When `init.sh --non-interactive` is invoked from a test harness with a piped/heredoc stdin (e.g. `printf 'Y\n...' | bash init.sh ...`), the `prompt_install` helper at `scripts/lib/helpers.sh:295-324` interacts poorly with `set -o pipefail` in two ways:

1. `prompt_install` checks `[ ! -t 0 ]` at line 306 to detect non-interactive context and returns 1 (no install). When stdin is a `printf`-fed pipe rather than a tty, the gate fires correctly — but the *test* expects the install to proceed (or be silently skipped without error).
2. Some upstream callers chain `printf | bash init.sh` directly. Under `pipefail`, if init.sh exits before consuming the full stdin, the upstream `printf` receives SIGPIPE and exits 141 — which propagates through the pipeline and fails the parent command. Tests work around this by using process substitution (`< <(printf 'Y\nY\n...')`) so each program reads its own fd without a true pipe.

**Current workaround (test-side, in tree):**
- `tests/test-init-organizational.sh:50,146` — `< <(printf 'Y\nY\nY\nY\nY\nY\nY\nY\nY\nY\n')` feeds finite stdin.
- `tests/edge-cases-scripts.sh:983,1083` — same shape.
- The PR-#104 body explicitly notes this as a worked-around bonus catch.

**Proposed source fix (deferred):**
- Audit `prompt_install` and its callers so the non-interactive path is the *only* path that runs when `CI=1`, `SOIF_NONINTERACTIVE=1`, or `--non-interactive` is passed, and the function NEVER attempts a `read -rp` on a closed-stdin stream. Today the `-t 0` test at line 306 catches the pipe-stdin case, but the broader question is whether `bash init.sh --non-interactive < /dev/null` (genuinely closed stdin, no fed input) is well-defined for callers that don't want even the `[WARN]` chatter on lines 307.
- Add a `tests/test-init-prompt-install-closed-stdin.sh` regression to fix the boundary so future tests don't need the printf-fed workaround.

**Why deferred (not in PR #104 fix-commit):** the workaround is local to tests, the user-facing behavior of `init.sh --non-interactive` (which the gate at `prompt_install:306` handles correctly) is sound, and the source audit touches multiple helpers + their callers. Capturing as a backlog item per the Wave 4 retrospective so it does not become a "silent backlog" item.

**Related:** PR #104 (test-singletons-and-tier-crosscheck-5), `scripts/lib/helpers.sh:295-324`, `init.sh:117-249` (all the `prompt_install` callsites), Wave 4 retrospective risk note 2.

---

## BL-043: intake-wizard.sh module-load side effects justify a `main()` extraction refactor

**Logged:** 2026-06-29 (PR #104 verifier follow-up — Wave 4 risk note 2)
**Category:** Debt / sourceability hardening
**Severity:** Low (current main-guard + trap-guard handle the surface; refactor improves hygiene)
**Status:** Open

PR #104 added two main-guard gates to `scripts/intake-wizard.sh`:
1. Lines 27 + 2009 (PR #104 base): block the project-root discovery + `main "$@"` call when sourced.
2. Lines 290 + 314 (PR #104 verifier follow-up): block the EXIT trap that cleans up `_PAUSE_FILE` when sourced, so it does not clobber the caller's pre-existing EXIT trap.

These two gates patch the most damaging clobber surfaces, but the underlying design is still that intake-wizard.sh runs side-effects at module-load time (helpers sourced at line 13, `_PAUSE_FILE` allocated at line 273, function definitions, etc.). A cleaner shape would be:
- All side-effect setup (CWD anchor, `_PAUSE_FILE`, trap, project-root discovery, `main "$@"`) lives inside an explicit `main()` body.
- The module-load section contains only `set -euo pipefail`, `SCRIPT_DIR=…`, `source lib/helpers.sh`, and function definitions.
- The main-guard at the bottom becomes a single `if [ "${BASH_SOURCE[0]}" = "${0}" ]; then main "$@"; fi`.

**Proposed scope:**
- ~50-100 LOC moved, no new behavior — but every test that currently subshell-wraps `source scripts/intake-wizard.sh` should still pass without the wrapper. Add a `tests/test-intake-wizard-sourceable-no-side-effects.sh` regression that sources the file at the top level of a test process and verifies (a) no trap registered, (b) no `_PAUSE_FILE` written, (c) the caller's CWD unchanged.

**Why deferred (not in PR #104 fix-commit):** the gates already close the verifier-flagged risks for the current call shapes; the refactor is a hygiene improvement that touches the wizard's structure rather than its behavior. Schedule for a focused refactor PR so the diff is reviewable.

**Related:** PR #104 verifier follow-up (Wave 4 majors #3 + #4), `scripts/intake-wizard.sh:24-27` (sourced-probe), `scripts/intake-wizard.sh:273-321` (pause-file + trap), `scripts/intake-wizard.sh:2009-2011` (main-guard).

---

## code-check-gates-7-followup: per-gate-section blame for APPROVAL_LOG.md commit-author lookup

**Logged:** 2026-06-28 (PR #87 cycle-7 verifier major #4)
**Category:** Bug / governance (precision of self-approval check)
**Severity:** Major
**Status:** Closed (2026-06-30, PR #<PR>, commit `06fb186`)

`scripts/check-phase-gate.sh:246` resolves the commit author of an approval via `git log -n 1 --format=%an -- APPROVAL_LOG.md`, which returns whoever most recently touched the file — not who added the specific gate's Approver row. The cycle-7 PR-#87 adversarial verifier (major #4) flagged the resulting attack surface: if Alice committed her own approval row (true self-approval — should FAIL) and Bob later committed a typo fix to a different gate's row, the check passes for Alice because the latest commit author is Bob.

PR #87's fix-commit added a minimum-viable WARN at the elif branch (`commit_author_norm` empty + `approver_norm` non-empty) so the silent-pass case at least surfaces, but does NOT close the amended/secondary-edit gap.

**Proposed fix:** walk the active gate section in APPROVAL_LOG.md to find the line containing the Approver row, then use `git blame --line-porcelain -L<N>,<N> APPROVAL_LOG.md` (or `git log -L<N>,<N>:APPROVAL_LOG.md --format=%an --no-patch | head -1`) to extract the author of that specific line's most recent change. Compare THAT against the approver name. The section walker already exists in `validate_approval_fields` — the new logic only needs the line-number resolver (awk `$0 ~ /Approver/ && !/Role/ { print NR; exit }` inside the section).

**Test coverage to add:**
- T-blame-1: Alice approves gate A in commit C1; Bob later fixes a typo in gate B in commit C2. `check-phase-gate.sh` MUST still FAIL on Alice's self-approval at gate A.
- T-blame-2: Alice's row is added in the working tree only (uncommitted). Behavior should match the PR-#87 WARN ("cannot verify").
- T-blame-3: Bob commits Alice's approval row on her behalf (legitimate organizational approval). MUST NOT FAIL (commit author differs from approver).

**Why deferred (not in PR #87 fix-commit):** the WARN is sufficient to remove the silent-pass surface; the blame-walker is ~30 lines of new code with three new tests, exceeding the scope of a verifier-feedback fix-commit. Schedule for cycle 8.

---

## BL-034: Wire orphan tests into aggregators (Wave 1-4 cohort)

**Logged:** 2026-06-28 (test integrity audit)
**Category:** Test infrastructure / regression coverage
**Severity:** High
**Status:** Closed (2026-06-29, PR #111, commit `cc1e532`)

Of the 17 test files added in Wave 1-4 (PRs #83-#97 plus follow-up fixers 2d5f917, 33e351e), only **1** (`tests/test-platform-mobile-mcp-docs.sh` via PR #86) is invoked by any aggregator. The remaining 16 test files execute only via direct `bash tests/test-foo.sh` — no aggregator, no CI, no pre-commit-gate runs them. Regressions in intake-wizard, reconfigure, bypass-audit, check-phase-gate, host drivers (gitlab approvals, host_verify_protection date-parse), pending-approval resolve-decision, verify-install fix-functions, upgrade-interruption + sentinel-block, lint scripts, and the host-aware quartet plan are all silent.

**Files needing registration** (full list in `Reports/2026-06-28-test-integrity-audit.md` §4):

- `tests/edge-cases-pre-init.sh` (extended PR #88)
- `tests/edge-cases-scripts.sh` (extended PR #89)
- `tests/edge-cases-upgrade-input.sh` (extended PR #85)
- `tests/test-intake-wizard-fixes.sh` (PR #83)
- `tests/test-reconfigure-field-handlers.sh` (PR #84)
- `tests/test-bypass-audit-tmp-hardening.sh` (PR #93)
- `tests/test-bypass-audit-trap-isolation.sh` (verifier fix 2d5f917)
- `tests/test-bypass-detector-session-id.sh` (PR #93)
- `tests/test-check-phase-gate-noninteractive.sh` (PR #87)
- `tests/test-check-phase-gate-self-approval.sh` (PR #87)
- `tests/test-gitlab-ci-status-stderr-approvals.sh` (PR #91)
- `tests/test-host-verify-protection-date-parse.sh` (PR #93)
- `tests/test-pending-approval-resolve-decision.sh` (PR #87)
- `tests/test-verify-install-fix-functions.sh` (PR #92)
- `tests/test-upgrade-interruption.sh` (PR #95)
- `tests/test-upgrade-sentinel-block.sh` (PR #95)
- `tests/test-lint-fix-functions-stderr.sh` (PR #96)
- `tests/test-lint-raw-read-prompt.sh` (PR #96)
- `tests/test-specs-plans-host-aware-quartet.sh` (PR #97)
- `tests/test-prompt-install-noninteractive.sh` (verifier fix 33e351e)

**Action:** Add explicit `bash "$SCRIPT_DIR/tests/test-*.sh"` invocations to `tests/full-project-test-suite.sh` under new TEST sections. For tests currently RED on main (E50, prompt_install harness — see BL-039), invoke them but mark expected-fail until the underlying bugs land.

**Bundle with:** BL-036 (critical-tautology fixes need to run when added). BL-038 (test-registration lint gate prevents recurrence).

**Related:** `Reports/2026-06-28-test-integrity-audit.md` §4 (runner registration gap), §7 Slot 1.

---

## BL-035: Wire orphan tests into aggregators (pre-Wave 1-4 backlog)

**Logged:** 2026-06-28 (test integrity audit)
**Category:** Test infrastructure / regression coverage
**Severity:** Medium
**Status:** Open

Approximately 50 `tests/test-*.sh` files predate Wave 1-4 and are not invoked by any aggregator. Coverage for BL-029 (governance log integrity), BL-030 (calibration replay + bypass-audit), counter-sanitizers, init non-interactive (BL-016 — 26 unit tests per the 2026-04-25 plan), pre-commit-gate classifier (BL-020/021), and the bypass-audit family is all silent.

Notable orphans (non-exhaustive — full list in `Reports/2026-06-28-test-integrity-audit.md` Step 4 enumeration):
- `test-bl029-integration.sh`, `test-bl030-calibration-replay.sh`, `test-bypass-audit-{integrity,lib,schema}.sh`
- `test-check-phase-gate-counter-sanitizer.sh`, `test-check-phase-gate.sh`
- `test-init-non-interactive.sh`, `test-init-atomic-finalize.sh`, `test-init-schema-phase-gate.sh`
- `test-pre-commit-gate-classifier.sh`, `test-pre-commit-gate-lints.sh`, `test-pre-commit-gate-terminal-mode.sh`
- `test-upgrade-paths.sh` (NOT the aggregator `tests/upgrade-path-tests.sh` — easily confused)
- `test-upgrade-bl030-backfill.sh`, `test-upgrade-project-atomic.sh`, `test-upgrade-to-production-{preconditions,warn}.sh`
- `test-validate-counter-sanitizer.sh`, `test-test-gate-counter-sanitizer.sh`, `test-test-gate-null-handling.sh`
- `test-bypass-detector.sh`, `test-bypass-patterns.sh`, `test-bypass-sentinel.sh`
- `test-pending-approval.sh`, `test-escalate-to-user.sh`, `test-out-of-band-detector.sh`
- `test-enforcement-level-{init,lib,reconfigure}.sh`
- `test-vendored-skills-install.sh`, `test-record-claude-commit.sh`, `test-unrecord-feature.sh`
- `test-filesystem-gate-install.sh`, `test-gate-principles.sh`, `test-github-free-tier-403.sh`
- `test-poc-modes.sh`, `test-phase-finalize.sh`, `test-process-checklist-{auto-advance,classifier}.sh`

**Action:** Audit each orphan. For each, decide: (a) add to an aggregator, (b) merge logic into an existing aggregator's inline assertions, or (c) delete if redundant. Submit as one PR with a disposition table.

**Schedule:** After BL-034 lands (so the Wave 1-4 cohort is the proven pattern to mirror).

**Confusable filename warning:** `tests/test-upgrade-paths.sh` (orphan test file) vs `tests/upgrade-path-tests.sh` (top-level aggregator). Anyone scanning for upgrade coverage may see two hits and assume the test is registered.

**Related:** `Reports/2026-06-28-test-integrity-audit.md` §4, §7 Slot 4.

---

## BL-036: Fix critical vacuous assertions in edge-cases suite

**Logged:** 2026-06-28 (test integrity audit)
**Category:** Bug / test integrity
**Severity:** Critical
**Status:** Closed (2026-06-29, PR #110, commit `66da15c`)

Three tests in the edge-cases suite are tautological by construction. The corresponding product behaviors have **zero regression coverage** on `main` — a regression could be merged today with no signal.

**E31 (`tests/edge-cases-scripts.sh:1043`) — UAT upgrade refreshes templates:**
The test never invokes `upgrade-project.sh`. The subshell at 1031-1042 inlines `cp "$REPO_DIR/templates/uat/..." tests/uat/...` then asserts the placeholder exists in the file just copied. Assertion is effectively `grep $X $X_COPY`. Identical shape to the audit's `tests-edge-cases-9` finding that was supposedly fixed in E21 — this is a structural regression.
**Fix:** Rewrite to actually invoke `bash scripts/upgrade-project.sh --to-X` (or whichever subcommand handles UAT template refresh). Assert the placeholder is present in the project-side template AFTER the upgrade ran.

**E32 (`tests/edge-cases-scripts.sh:1065`) — UAT upgrade migration is idempotent:**
The loop at 1057-1064 runs the same `cp` twice. The diff at 1065-1066 compares destination to source — guaranteed identical by construction. `upgrade-project.sh`'s idempotency logic is never invoked.
**Fix:** Invoke `upgrade-project.sh` twice. Snapshot project-side state after run 1, run 2, assert the second invocation is diff-clean against the snapshot.

**E39 (`tests/edge-cases-upgrade-input.sh:970`) — newlines preserved:**
Both branches of the inner if/else call pass(). A regression that silently strips the newline AND "line1" still PASSes the else branch with 'handled (stored as: ...)'.
**Fix:** Collapse to a single positive assertion: `grep -q $'^line1\nline2$'` against the saved file (exact two-line round-trip).

**Verification protocol:** For each rewrite, perform a deliberate mutation test — break the product code, confirm the test FAILS, restore the product code, confirm the test PASSes. Capture in PR description.

**Bundle with:** BL-034 (rewritten tests need to be registered in an aggregator to fire).

**Related:** `Reports/2026-06-28-test-integrity-audit.md` §2 (LB-4/5/6), §3.1, §7 Slot 2.

---

## BL-037: Fix major vacuous assertions across test suite

**Logged:** 2026-06-28 (test integrity audit)
**Category:** Bug / test integrity
**Severity:** High
**Status:** Closed (2026-06-30, PR #115, commit `359c714`)

15 major-severity findings across edge-cases, verify-install, prompt-install, snapshot-retention, intake-wizard, and self-approval tests use either catch-all `else pass: handled` branches or negative-only oracles (`! grep -q deny`, no positive assertion). Each will silently pass on a crash or on garbage output.

**Tighten each assertion to require a POSITIVE signal:**

- **E33** (SQL injection, `edge-cases-upgrade-input.sh:641`): pin the exact sanitized form (or documented cap length). Reject the catch-all 'sanitized' branch.
- **E34** (10K-char description, `:671`): pin exact stored length (`saved_len == 10000` or `saved_len == ${DESCRIPTION_CAP}`). A regression to 1 char must FAIL.
- **E36** (Unicode, `:804`): pin exact stored bytes (UTF-8 roundtrip exact match).
- **E37** (emoji, `:834`): same shape as E36.
- **E40** (NUL byte, `:1010`): pin either `saved_value == "test\0value"` or the documented sanitization (e.g. NUL stripped → `saved_value == "testvalue"`).
- **E12a/b** (resume.sh + missing/empty CLAUDE.md, `edge-cases-scripts.sh:216, :231`): require `[ $? -eq 0 ]` (clean exit) AND a specific positive output substring. Remove magic-keyword negative oracle.
- **E25a/b/c** (validate/check-phase-gate/resume on phase=99, `:906, :920, :926`): same fix — require rc==expected AND positive output.
- **E27/E28/E29** (UAT init reference pair, `:983` and following): assert BOTH halves of the reference pair (`pre-flight-reference.html` AND `scenario-reference.json`).
- **test-verify-install-fix-functions.sh T6-T10** (`:197, :208, :219, :231, :242`): require the positive fail/manual line (mirror T5's tightened oracle at `:175-178`).
- **test-prompt-install-noninteractive.sh T1/T2/T3** (`:137`): add `type prompt_install >/dev/null || fail` before each test; assert rc==1 specifically (not just rc!=0). Currently a missing function passes with rc=127.
- **test-upgrade-interruption.sh T2** (`:240`): remove the `if [ -d "$TMPDIR_T/.claude/upgrade-snapshots" ]; then ... fi` wrap. Make the dir's presence a hard requirement (otherwise the snapshot infrastructure can be silently broken — see LB-7).
- **test-intake-wizard-fixes.sh T1** (`:81`): replace the tautological shell-parameter-expansion check (`${wiz_line%%:*} != $tpl_num` — unreachable because awk already filtered on `$1 == n`) with an actual title comparison using `wiz_title` against `tpl_title`.
- **test-check-phase-gate-self-approval.sh T3** (`:141`): remove the `else pass` branch on absence-of-message. Require the WARN substring as a positive condition. Currently both elif (WARN matched) and else (no message) pass — a regression dropping the WARN passes silently.

**Verification protocol:** Same mutation-test discipline as BL-036 — break the underlying product code, confirm the tightened test FAILS, restore, confirm GREEN.

**Bundle with:** BL-034 (tightened tests need to be registered to matter). Consider splitting into 4 sub-PRs by area if line count exceeds ~300.

**Related:** `Reports/2026-06-28-test-integrity-audit.md` §3.1, §3.2, §3.3, §3.4, §7 Slot 3.

---

## BL-038: Mandate runner-registration check for new test files

**Logged:** 2026-06-28 (test integrity audit)
**Category:** Test infrastructure / preventive control
**Severity:** Medium
**Status:** Open

The pattern of 'PR adds a test file, PR merges, test never runs' is now a systemic risk, not a one-off mistake. 16 of 17 Wave 1-4 test files landed without aggregator registration. Without an automated gate, the next wave will reproduce the same issue.

**Action:** Add a lint script `scripts/lint-tests-registered.sh` that:
1. Enumerates `tests/*.sh` (excluding aggregators and helpers via an allowlist).
2. Greps each top-level aggregator (`full-project-test-suite.sh`, `edge-case-test-suite.sh`, `known-bugs-test-suite.sh`, `upgrade-path-tests.sh`, `host-drivers/run-all.sh`) for invocation of each basename.
3. FAILs the gate if any test file is not invoked by any aggregator.
4. Provides override mechanism: `# LINT_TEST_REGISTRATION_EXEMPT: <reason>` magic comment in the test header (e.g. for slow / network-dependent / manual-only tests).

Wire into `.github/workflows/lint.yml` and `scripts/pre-commit-gate.sh` alongside the existing lint scripts (counter-antipattern, backlog-references, fix-functions-stderr, raw-read-prompt).

Add self-test `tests/test-lint-tests-registered.sh` covering: (a) all-registered fixture passes, (b) one-orphan fixture fails, (c) exempted-orphan fixture passes, (d) malformed exempt comment is rejected.

**Bundle with:** BL-034 (the gate cannot be enabled until existing orphans are dispositioned). Land BL-034 + BL-035 first, then turn the gate on.

**Related:** `Reports/2026-06-28-test-integrity-audit.md` §4, §7 Slot 6.

---

## BL-039: Resolve LB-1 — fix the underlying bug behind E50 (BL-016 non-interactive init)

**Logged:** 2026-06-28 (test integrity audit)
**Category:** Bug / live product defect
**Severity:** High
**Status:** Closed (2026-06-30, PR #117, commit 2888fa2)

E50 in `tests/edge-cases-scripts.sh` (BL-016 init.sh non-interactive suite) is acknowledged as failing on `main` per the PR #89 implementer note. The assistant who added the test did not fix the underlying bug nor remove the assertion. The product code path (`init.sh --non-interactive`) does not satisfy the contract E50 pins.

Because E50 is in an orphan test file (`edge-cases-scripts.sh` is not invoked by any aggregator — see BL-034), the failure is invisible to CI. The only way it surfaces today is if a developer manually runs the edge-cases file.

**Action:**
1. Debug E50 in isolation: `bash tests/edge-cases-scripts.sh 2>&1 | grep -A20 'E50'`.
2. Determine whether the contract E50 pins is correct.
   - If correct: fix `scripts/init.sh` non-interactive code path to satisfy the contract.
   - If the contract is wrong (e.g. the spec changed): update the test AND document the contract change in `docs/builders-guide.md`.
3. Do not delete the test silently — if it's removed, capture the decision in this BL closure.
4. Verify E50 GREEN before closing.

**Dependencies:** BL-034 must register `edge-cases-scripts.sh` in an aggregator so the GREEN state is enforced going forward. Land BL-034 first (with E50 marked expected-fail), then this BL flips it to expected-pass.

**Resolution:** Investigated 2026-06-30 against `init.sh:3262-3268` and `docs/governance-framework.md:257`. The contract E50 was pinning (organizational + private_poc → success with visibility=private) is **wrong** — baseline §2.5 explicitly rejects the `organizational/private_poc` tier shape, and `init.sh` correctly returns exit 1 with the audit code-init-sh-4 / tier-crosscheck-2 rejection message. The 2026-04-25 BL-016 spec table 6.6 row E50 was authored before the tier-crosscheck-2 audit landed and was never reconciled. Rewrote E50 to use `sponsored_poc` (the gov_mode that IS valid for organizational deployments) preserving the org→visibility=private force assertion on mobile+kotlin, and added E50b as a positive rejection test for the actual contract so a future regression that re-permits the invalid combination surfaces loudly. Updated `docs/superpowers/specs/2026-04-25-init-sh-non-interactive-design.md` §8.2 to reflect the actual contract. Narrowed the `SKIP_KNOWN_FAILING` gate in `tests/full-project-test-suite.sh` TEST 0r to track only BL-065 (E30 `--platform other`) — the BL-039 component is lifted. `init.sh` source unchanged; mutation experiment verified E50b would catch a regression (replaced rejection block with `:`, init.sh accepted the invalid combo → E50b would flip RED).

**Related:** `Reports/2026-06-28-test-integrity-audit.md` §2 (LB-1), §7 Slot 5. PR #89 implementer note.

---

## BL-040: Resolve LB-2 — `init.sh:2781` dry_run_summary omits the description

**Logged:** 2026-06-28 (test integrity audit)
**Category:** Bug / live product defect (low-impact UX)
**Severity:** Medium
**Status:** Open

E2 in `tests/edge-cases-pre-init.sh` is left as SKIP because `scripts/init.sh:2781` (`dry_run_summary`) does not echo the project description that the user supplied. The literal-text-preservation guarantee that E2 wants to verify is absent in the product code — there is nothing on stdout to grep against.

**Action:**
1. Read `scripts/init.sh:2781` (`dry_run_summary` function).
2. Add the description field to the function's emitted output (likely a line like `echo "Description: ${project_description}"` near the other summary fields).
3. Verify by running `bash scripts/init.sh --dry-run --project-name foo --description "My test description"` — confirm the description appears.
4. Remove the SKIP in `tests/edge-cases-pre-init.sh` E2; restore the assertion.
5. Confirm E2 PASSes.

**Dependencies:** BL-034 (register `edge-cases-pre-init.sh` in an aggregator) and BL-041 (LB-3 framework-repo guard layering — required to actually run E2 from inside the framework repo).

**Related:** `Reports/2026-06-28-test-integrity-audit.md` §2 (LB-2), §7 Slot 5.

---

## BL-041: Resolve LB-3 — `init.sh:3494` framework-repo guard layering

**Logged:** 2026-06-28 (test integrity audit)
**Category:** Bug / live product defect (test-harness blocker)
**Severity:** Medium
**Status:** Open

The framework-repo guard at `scripts/init.sh:3494` runs before the write-permission preflight. When the test harness invokes init.sh from inside the framework checkout (which is how `tests/edge-cases-pre-init.sh` is structured), the guard refuses any non-dry-run invocation before the preflight can fire. E8b is SKIPed as a consequence — there is no way to exercise the write-permission failure path under the current layering.

**Action (preferred — option (a)):** Reorder the checks in `init.sh` so the write-permission preflight runs first (operator-facing check fires before developer-facing guard). The preflight should not depend on any state mutated by the guard.

**Action (fallback — option (b)):** If reordering is structurally infeasible, rewrite the test harness to copy the relevant files into a tmpdir and run init.sh from there (non-framework-repo layout). This is less preferred because (i) it duplicates fixture setup work in every affected test, (ii) it weakens the test's representativeness vs. the operator scenario.

**Verification:** After the fix, remove the SKIP on E8b and confirm the assertion fires correctly (a deliberately read-only destination should cause init.sh to FAIL on the write-permission preflight, not on the framework-repo guard).

**Dependencies:** Lands E8b only after BL-034 (registers `edge-cases-pre-init.sh` in an aggregator).

**Related:** `Reports/2026-06-28-test-integrity-audit.md` §2 (LB-3), §7 Slot 5.

---

## BL-044: TEST 4 in full-project-test-suite.sh silently fails 8 assertions due to stale template-layout paths

**Logged:** 2026-06-29
**Category:** Bug
**Severity:** High
**Status:** Closed (2026-06-30, PR #113, commit ca2d5e7)

The PR #104 fixer's full-suite run reported 321/329 passing with 8 failures, all concentrated in `tests/full-project-test-suite.sh` TEST 4 ("Simulated Project Structure Verification"). The failures are pre-existing on `main` — not introduced by any of the Wave 1–4 PRs — and share a single root cause: the test's `cp` source paths still reference the **flat** layout that predated the host-subdir migration. Specifically, lines 506–507 do:

```bash
[ -f "$SCRIPT_DIR/templates/pipelines/ci/$ci_tpl" ] && cp "$SCRIPT_DIR/templates/pipelines/ci/$ci_tpl" "$project_dir/.github/workflows/ci.yml"
[ -f "$SCRIPT_DIR/templates/pipelines/release/${t_platform}.yml" ] && cp "$SCRIPT_DIR/templates/pipelines/release/${t_platform}.yml" "$project_dir/.github/workflows/release.yml"
```

But the actual layout is now `templates/pipelines/ci/github/typescript.yml` (and `gitlab/`, `bitbucket/`) and `templates/pipelines/release/github/web.yml` etc. The flat-path `[ -f ]` guards silently no-op, then verification at line 597–598 emits `File missing ($label): .github/workflows/ci.yml` for every one of the 7 test combos that expects a CI template (7 × 1 = 7 failures), plus the `release.yml` presence check at line 602–604 fires when `templates/pipelines/release/${t_platform}.yml` *would* match under the current layout.

This is a high-severity finding because the failure is **silent at the test-suite gate**: TEST 4 is the only thing in the project that exercises the combinatorial init.sh templating contract end-to-end, and it has been broken for at least the entire Wave 1–4 cycle without any wave catching it. A regression in the actual CI/release templates would not be detected.

**Scope:**
- Update TEST 4's `cp` source paths to use the host-subdir layout (default to `github/` since the test fixture uses GitHub semantics — `.github/workflows/` destination).
- Either parameterize the host (so the test can exercise gitlab/ and bitbucket/ too) or document the GitHub-only scope inline.
- Verify all 8 previously-silent assertions now fail-or-pass correctly: run `bash tests/full-project-test-suite.sh` and confirm TEST 4 reports 0 failures (or surfaces real regressions if any exist in the host-specific templates).
- Add a fixture sanity check at the top of TEST 4 that fails fast if any of the expected source templates are missing, so future template moves don't silently break the suite again.

**Trigger:** Next test-infrastructure pass. Bundle naturally with BL-053 (TEST 4 fixture sharing) and BL-038 (lint-tests-registered) since all three touch the same test surface.

**Related:** PR #104 full-suite run output (321/329); `tests/full-project-test-suite.sh:455-720`; `templates/pipelines/ci/github/`, `templates/pipelines/release/github/` (actual layout); BL-053 (TEST 4 fixture-sharing refactor); BL-038 (runner-registration check).

---

## BL-045: Parallelize TEST 1 resolver matrix in full-project-test-suite.sh (Step 4 ROI #1)

**Logged:** 2026-06-29
**Category:** Performance
**Severity:** High
**Status:** Closed (2026-06-30, PR #114, commit `38dbf17`)

TEST 1 of `tests/full-project-test-suite.sh` walks an 81-cell matrix (3 platforms × 9 languages × 3 tracks) and forks a fresh `bash scripts/resolve-tools.sh` invocation per cell. Each cell re-reads `templates/tool-matrix/*.json` from disk and version-probes every tool. The walk is fully serial. Step 4 recon timed the full suite at >600 s (timed out at the 10-minute bash limit), with TEST 1 alone responsible for ~240 s — the single largest time-sink in the entire project.

This matters because the >600 s suite runtime is the primary reason the CI workflow does **not** run the full-project-test-suite at all today (`.github/workflows/lint.yml` runs only lint scripts). Bringing TEST 1 under control unblocks wiring the suite into CI, which in turn closes the structural gap that BL-034/BL-035/BL-038 are also tackling from the other side.

**Scope:** Refactor TEST 1's 81-cell walk to either (a) `xargs -P 8` per-cell invocations into temp output files + aggregate at the end, or (b) collapse into a single resolver invocation that batches the matrix and emits per-cell JSON in one pass. Option (a) is simpler and lower-risk; option (b) is faster but requires `scripts/resolve-tools.sh` API change. Expected reduction: ~240 s → ~30–60 s (4-8× speedup). Document the parallelism level in CONTRIBUTING.md so contributors know how to debug a single failing cell.

**Trigger:** Before wiring full-project-test-suite.sh into `.github/workflows/lint.yml` or `scripts/pre-commit-gate.sh`. Bundle with BL-053 (TEST 4 fixture sharing) since both reduce wall-clock on the same suite.

**Related:** `Reports/2026-06-28-step4-dead-code-perf-eval.md` §5.3, §7 item 1; `tests/full-project-test-suite.sh` TEST 1 block; BL-034, BL-035, BL-038.

---

## BL-046: Split `lib/helpers.sh` into focused libraries (Step 4 ROI #2)

**Logged:** 2026-06-29
**Category:** Performance
**Severity:** Medium
**Status:** Open

`lib/helpers.sh` is sourced by ~15 short-lived script callers. Each source incurs a 30–40 ms parse+exec cost (Step 4 recon profiling) regardless of which helpers the caller actually uses. Compounded across the CLI surface this is visible latency on the per-script TUI flow.

**Scope:** Split `lib/helpers.sh` into focused libraries (e.g. `lib/helpers-string.sh`, `lib/helpers-fs.sh`, `lib/helpers-git.sh`, `lib/helpers-host.sh`) so callers source only the surface they need. Audit each call site and update its `source` line to the narrowest helper-library required. Retain a thin `lib/helpers.sh` shim that sources all of them so any third-party caller continues to work.

**Trigger:** When CLI latency becomes user-visible OR when adding the next big helper that would push `lib/helpers.sh` parse time over a perceptible threshold.

**Related:** `Reports/2026-06-28-step4-dead-code-perf-eval.md` §5, §7 item 2; `lib/helpers.sh`; all `source lib/helpers.sh` call sites under `scripts/`.

---

## BL-047: Audit and retire the disabled `cli` arm of `verify-install.sh` (Step 4 ROI #3)

**Logged:** 2026-06-29
**Category:** Debt
**Severity:** Low
**Status:** Open

`scripts/verify-install.sh` carries a `cli` arm that has been disabled / unreachable (per Step 4 recon). The dead branch confuses readers and is a maintenance trap if a future change accidentally re-enables it without re-validating its assertions.

**Scope:** Confirm the `cli` arm is genuinely unreachable from all entry points (CI workflow, pre-commit gate, manual operator usage). If unreachable, delete the dead branch and its associated tests. If reachable from a path Step 4 missed, document the path and gate the arm behind an explicit flag.

**Trigger:** Next pass on `verify-install.sh` for any reason; bundle with BL-050.

**Related:** `Reports/2026-06-28-step4-dead-code-perf-eval.md` §7 item 3; `scripts/verify-install.sh`.

---

## BL-048: Repair dead user-guide anchors (Step 4 ROI #4)

**Logged:** 2026-06-29
**Category:** Debt
**Severity:** Low
**Status:** Open

Step 4 recon enumerated dead anchors in `docs/builders-guide.md` and adjacent user-guide markdown — section headings have been renamed without updating in-doc cross-references. The link-check lint does not catch in-document anchors (only external URLs).

**Scope:** Run an anchor-validator over `docs/` (a small awk/grep script: collect every `## Heading` → derived anchor and every `[link](#anchor)` reference; flag the orphans). Repair each broken anchor. Add the validator script to the lint suite.

**Trigger:** Next docs pass; cheap.

**Related:** `Reports/2026-06-28-step4-dead-code-perf-eval.md` §7 item 4; `docs/builders-guide.md`.

---

## BL-049: Delete orphan plan docs under `docs/superpowers/plans/` (Step 4 ROI #5)

**Logged:** 2026-06-29
**Category:** Debt
**Severity:** Low
**Status:** Open

Multiple plan documents under `docs/superpowers/plans/` correspond to work that has since shipped (or been superseded). Step 4 recon flagged these as orphans — keeping them around dilutes the active-plan signal for any agent searching that directory.

**Scope:** Enumerate each plan doc, cross-check against `git log` and shipped PRs, and either (a) delete the orphan, (b) move to `docs/superpowers/plans/archive/` with a one-line note pointing at the shipping PR, or (c) keep if still actionable. Document the convention in `docs/superpowers/README.md`.

**Trigger:** Next docs-cleanup pass.

**Related:** `Reports/2026-06-28-step4-dead-code-perf-eval.md` §7 item 5; `docs/superpowers/plans/`.

---

## BL-050: Wire `verify-install.sh --eval-factory` into the lint gate (Step 4 ROI #6)

**Logged:** 2026-06-29
**Category:** Debt
**Severity:** Medium
**Status:** Open

`scripts/verify-install.sh --eval-factory` exists as an internal evaluation harness but is not invoked by any CI gate or pre-commit check. Step 4 recon notes this means the factory's regression surface is exercised only by operators who know to run it manually.

**Scope:** Add `bash scripts/verify-install.sh --eval-factory` to `.github/workflows/lint.yml` (or to the test-aggregator harness once BL-034 lands). Verify the eval-factory is quick enough to run on every PR (~seconds, not minutes); if not, gate it behind a path filter or a slow-job label. Bundle with BL-047 if both land together.

**Trigger:** After BL-034 (orphan-test registration) so the gate has a stable aggregator to plug into.

**Related:** `Reports/2026-06-28-step4-dead-code-perf-eval.md` §7 item 6; `scripts/verify-install.sh`; `.github/workflows/lint.yml`.

---

## BL-051: Memoize `get_available_platforms` in `resolve-tools.sh` (Step 4 ROI #7)

**Logged:** 2026-06-29
**Category:** Performance
**Severity:** Low
**Status:** Open

`scripts/resolve-tools.sh::get_available_platforms` re-scans `templates/tool-matrix/*.json` on every call. Within a single resolver invocation the function is called O(N) times where N is the platform count. Step 4 recon recommends a single-pass memoization via a process-local associative array.

**Scope:** Wrap `get_available_platforms` in a memoization cache (bash associative array keyed by '' since there's no arg). First call populates; subsequent calls hit the cache. Add a test that confirms the function is called once even when invoked 10× in a row (via a counter helper).

**Trigger:** When tackling BL-045 (TEST 1 parallelization) — the per-cell `resolve-tools.sh` fork amplifies any in-function cost. Bundle.

**Related:** `Reports/2026-06-28-step4-dead-code-perf-eval.md` §7 item 7; `scripts/resolve-tools.sh`; BL-045.

---

## BL-052: Retire un-invoked test aggregators (Step 4 ROI #8)

**Logged:** 2026-06-29
**Category:** Debt
**Severity:** Low
**Status:** Open — POLICY DECISION PENDING (see Related)

Step 4 recon identified test aggregators under `tests/` that are not invoked from any CI gate, pre-commit hook, or other aggregator. They appear to be dead — sourcing them costs nothing but they confuse the test-discovery surface.

**Scope:** Enumerate every aggregator (`tests/*.sh` that sources other tests), cross-check invocation surface (`.github/workflows/`, `scripts/pre-commit-gate.sh`, `tests/*aggregator*`, etc.), and delete the un-invoked ones.

**POLICY OVERLAP — Karl decision required:** BL-035 (Wire orphan tests into aggregators — pre-Wave 1-4 backlog) recommends the opposite action on adjacent files: register orphans into existing aggregators rather than deleting empty aggregators. Possible reconciliations:
- **Policy A (BL-035 wins):** Consolidate orphans into a small set of aggregators; BL-052 narrows to retire only the *truly* empty ones.
- **Policy B (BL-052 wins):** Delete the un-invoked aggregators; BL-035 narrows to only those orphan tests worth keeping post-cleanup.

Neither item should ship before the policy is set.

**Trigger:** After Karl picks a policy.

**Related:** `Reports/2026-06-28-step4-dead-code-perf-eval.md` §7 item 8; BL-035 (cross-ref / overlap); `tests/`.

---

## BL-053: Share TEST 4 fixture across combos in full-project-test-suite.sh (Step 4 ROI #9)

**Logged:** 2026-06-29
**Category:** Performance
**Severity:** Medium
**Status:** Open

TEST 4 in `tests/full-project-test-suite.sh` builds a fresh project fixture per combo (scaffold the directory, copy templates, write manifest). Per Step 4 recon the fixture-setup overhead dominates the per-combo wall-clock; a shared base fixture with combo-specific overlays would cut TEST 4 wall-clock substantially.

**Scope:** Refactor TEST 4 to build one base project fixture (the common scaffolding), then layer combo-specific files on top (CI template, manifest deltas). Each combo runs against an isolated working copy of the base via `cp -r` (cheap) or a per-combo overlay directory. Verify all existing assertions still execute against the same effective state.

**Trigger:** Bundle with BL-044 (TEST 4 path-fix) and BL-045 (TEST 1 parallelization) — single perf PR that touches `full-project-test-suite.sh`.

**Related:** `Reports/2026-06-28-step4-dead-code-perf-eval.md` §7 item 9; BL-044, BL-045; `tests/full-project-test-suite.sh` TEST 4.

---

## BL-054: Tiny dead-code cleanup pass — `_phase2_state_file`, `tool_install_json` (Step 4 ROI #10)

**Logged:** 2026-06-29
**Category:** Debt
**Severity:** Low
**Status:** Open

Step 4 recon identified several small dead-code surfaces, notably the `_phase2_state_file` helper and the `tool_install_json` variable, that are referenced nowhere in current call sites (verified by grep). They're vestigial from earlier refactors.

**Scope:** Grep-confirm each candidate is truly unreferenced (also check templates and docs, not just `scripts/`). Delete in a single small PR. Run the full lint + test gate; nothing should regress.

**Trigger:** Any time; cheap. Could ship as a 'simplify' PR.

**Related:** `Reports/2026-06-28-step4-dead-code-perf-eval.md` §7 item 10; `scripts/`.

---

## BL-055: Per-line APPROVAL_LOG.md blame walker for check-phase-gate.sh self-approval evasion

**Logged:** 2026-06-29
**Category:** Bug
**Severity:** Medium
**Status:** Open

Placeholder entry for the tier-crosscheck-6 follow-up. `scripts/check-phase-gate.sh:246` uses `git log -n 1 --format=%an -- APPROVAL_LOG.md` which returns whoever most-recently touched the file rather than the actual author of the Approver row being checked. This is a self-approval evasion surface: if Bob makes a typo-fix commit to `APPROVAL_LOG.md`, his name shadows Alice's as the latest toucher, which would unblock Alice's self-approval against an Approver row Alice herself added.

PR #87 shipped a minimum-viable WARN that surfaces the risk but does not hard-block. The hard-block upgrade — a per-line blame walker that resolves the author of *the specific Approver row*, not the file as a whole — is in flight as workflow `wf_c62d9fbe-369`.

**Scope:** Implement `_resolve_approver_row_author` in `scripts/check-phase-gate.sh` that, given an Approver row's line content, runs `git blame -L <line>,<line> APPROVAL_LOG.md` to find the commit that introduced *that exact row*, then resolves `%an` of that commit. Replace the current `git log -n 1 --format=%an -- APPROVAL_LOG.md` at line 246 with the per-line resolver. Wire into the existing self-approval refusal logic. Add regression tests covering the Bob-typo-fix-shadows-Alice scenario plus the standard happy path.

**Trigger:** This entry exists as a placeholder in case `wf_c62d9fbe-369` does not close before the next backlog snapshot. If `wf_c62d9fbe-369` ships first, this entry flips to Closed with the PR# citation.

**Related:** `scripts/check-phase-gate.sh:246`; PR #87 (minimum-viable WARN); workflow `wf_c62d9fbe-369` (hard-block in flight); audit code-check-gates-7.

---

## BL-057: init.sh --non-interactive must honor AUTO_INSTALL_TOOLS env var

**Logged:** 2026-06-29
**Category:** Bug
**Severity:** High
**Status:** Closed (2026-06-29, PR #107, commit `a0a4e8d`)

Surfaced by the Step-5 dogfood validation walker (`Reports/2026-06-29-step5-dogfood-validation.md`, DOGFOOD-001) — the only bug found across 38 scenarios. `init.sh:736` called `read -rp "Proceed with this plan? [Y/n]"` UNCONDITIONALLY whenever the resolved tool plan contained any `auto_install` or `manual_install` entries.

The inline `lint-raw-read-prompt: allow` comment at the same line documented the INTENDED bypass — *"NON_INTERACTIVE path uses AUTO_INSTALL_TOOLS env var rather than this prompt"* — but no code in `init.sh` actually read `AUTO_INSTALL_TOOLS`, and the guard immediately above did not check `NON_INTERACTIVE` either. Under `set -euo pipefail` with closed stdin (the documented `--non-interactive` contract), `read` returned non-zero and the script terminated silently with `rc=1`.

Currently surfaced only on `--platform mobile` (Android Studio auto_install row on Darwin hosts without Android Studio installed). Blast radius would grow with every new `auto_install` entry added to `templates/tool-matrix/*.json`.

**Repro (RED on origin/main):**

    init.sh --non-interactive --platform mobile --language typescript \
            --track full --deployment personal --gov-mode private_poc \
            --project foo --project-dir <tmp> </dev/null
    # → prints Tool Installation Plan, then dies silently. rc=1.

**Resolution (PR #107):** Replaced the unconditional `read -rp` with an env-aware branch that mirrors the documented contract — `NON_INTERACTIVE=true` → `response = ${AUTO_INSTALL_TOOLS:-Y}`. Paired with a `NON_INTERACTIVE` short-circuit inside the `[Nn]` decline branch so `AUTO_INSTALL_TOOLS=N` logs *"AUTO_INSTALL_TOOLS=N — skipping tool auto-installation..."* and proceeds, instead of dropping into the interactive `prompt_choice` sub-menu (which would EOF-fail under closed stdin). Regression test at `tests/test-init-non-interactive-mobile-auto-install.sh` covers all three contract cases (default Y, explicit N, explicit Y) and is wired into `tests/full-project-test-suite.sh` as TEST 0c4 per BL-034.

**Related:** `init.sh:733-737` (`resolve_and_install_tools`); Step-5 dogfood walker; BL-034 (test-aggregator wiring invariant); `scripts/lint-raw-read-prompt.sh` (the allowlist marker that documented the bypass that did not exist).

---

## BL-058: Sponsored POC `APPROVAL_LOG.md` canonical shape — doc/matrix wording clarified (no product change)

**Logged:** 2026-06-29
**Category:** Documentation
**Severity:** Low
**Status:** Won't Fix — documentation aligned with product behavior. Doc tightening shipped in the same PR.

**What:** The adversarial dogfood re-walker (2026-06-29) flagged `migration-private-poc-personal-to-sponsored-poc-org` as `partial`. The matrix's `expected_terminal_state` said: "APPROVAL_LOG restructured with the 3 Sponsored-required rows visible." After `bash scripts/upgrade-project.sh --to-sponsored-poc --non-interactive` the resulting `APPROVAL_LOG.md` contains all 6 Pre-Phase-0 rows. The re-walker read "3 rows visible" as a restructure-to-3 contract; that reading is incorrect — the product behavior is the canonical contract.

**Why (canonical contract — file:line citations):**
- `templates/generated/approval-log-org.tmpl:20-27` — the organizational APPROVAL_LOG template has all 6 Pre-Phase-0 rows in the table. The template is shape-only; the 6 rows are always present regardless of POC mode.
- `scripts/upgrade-project.sh:1551-1562` — the personal→organizational APPROVAL_LOG restructure emits all 6 rows in the new org-format table. There is no POC-mode-conditional row filter, and the contract does not call for one.
- `tests/test-upgrade-to-production-preconditions.sh:90-134` (`_write_approval_log_org`) — the canonical sponsored-POC fixture seeds all 6 rows. The deferred-vs-upfront distinction is *which rows have dates*, not which rows are present.
- `docs/governance-framework.md` §V — Sponsored POC requires rows 1 (AI deployment path) and 4 (project sponsor) dated upfront; defers rows 2 (insurance), 3 (liability), 5 (backup), 6 (ITSM) until `--to-production` clears them via dated approval or `--ack-preconditions=2,3,5,6`. Exit criteria is §XIV item #8, tracked outside `APPROVAL_LOG.md`.
- `docs/governance-framework.md` §V (pre-clarify wording, original): said "3 of 6" upfront + "5 of 6 minus the 3 required = the remainder". The "3 of 6" count counted exit-criteria as one of the 6, which §XIV does not; "5 of 6 minus 3" was nonsense arithmetic. This PR rewrites §V row 246 to spell out "2 of 6 blocking from §XIV upfront (rows 1,4); 4 of 6 deferred (rows 2,3,5,6); exit criteria is §XIV #8 tracked outside the table; all 6 rows remain visible."

**Scope:**
- `docs/governance-framework.md` §V row 246 — re-worded as above to remove "5 of 6 minus 3" gibberish and explicitly state "all 6 rows remain visible in `APPROVAL_LOG.md`."
- `scripts/upgrade-project.sh:888` — error message tightened from "Sponsored POC deferred 3" to "Sponsored POC requires rows 1,4 upfront and defers rows 2,3,5,6" so operators hitting the `--to-production` gate read the correct row numbers.
- `tests/test-upgrade-to-production-preconditions.sh:10-15` — comment rewritten to match the corrected canonical split.
- Scratchpad `dogfood-matrix.json` — the `migration-private-poc-personal-to-sponsored-poc-org` and `migration-sponsored-poc-to-production-org-ack-bypass` entries had the same "3 Sponsored-required" wording. Updated to "rows 1,4 dated (the 2 Sponsored-required) and rows 2,3,5,6 still TBD" so future dogfood passes don't re-misread the contract.

**No product code change** — `scripts/upgrade-project.sh` already implements the canonical contract correctly.

**Trigger:** Doc-only PR; ships immediately. No follow-up work required unless a separate investigation determines that the dogfood walker's failure to verify the actual canonical contract (rows 1,4 dated, 2,3,5,6 blank) is itself a walker-coverage gap worth filing — that would be a separate ticket about adversarial-walk assertion depth, not this one.

**Related:** Adversarial re-walk verdict 2026-06-29 (`partial`); `docs/governance-framework.md:246` (pre-clarify); `scripts/upgrade-project.sh:1503-1672` (restructure logic, unchanged); `templates/generated/approval-log-org.tmpl`; `tests/test-upgrade-to-production-preconditions.sh`; closed audit `code-upgrade-project-8` (which introduced the original "3 of 6" wording and the deferred-pre-condition gate).

**Reproduction (confirms the canonical 6-row shape is correct):**
```
# Outside the framework repo:
bash $REPO/init.sh --non-interactive --project foo --deployment personal \
  --gov-mode private_poc --platform mcp_server --language typescript \
  --track standard --project-dir "$PWD/foo" --git-host other \
  --remote-url https://example.com/foo.git --branch-protection-attested \
  --no-remote-creation
# Set data_classification + zdr_attested in .claude/process-state.json
jq '. + {"phase1_artifacts":{"data_classification":"internal","zdr_attested":true}}' \
  foo/.claude/process-state.json > /tmp/p.json && mv /tmp/p.json foo/.claude/process-state.json
( cd foo && bash $REPO/scripts/upgrade-project.sh --to-sponsored-poc --non-interactive )
# Expect: APPROVAL_LOG.md contains 6 Pre-Phase-0 rows in org format.
# Sponsored-required rows (1=AI deployment, 4=sponsor) are left BLANK in the
# template — the operator fills them by hand or via subsequent approvals.
grep -c '^| [0-9] |' foo/APPROVAL_LOG.md   # → 6
```

---

## BL-059: validate.sh reads APPROVAL_LOG.md instead of phase-state.json::gates for gate-date checks

**Logged:** 2026-06-29
**Category:** Bug
**Severity:** Medium
**Status:** Open

The adversarial certainty re-walk (re-walker-4, scenario `migration-track-standard-to-full`) surfaced that `scripts/validate.sh:281` emits `Phase 0->1 gate: no date recorded` even when `phase-state.json::gates.phase_0_to_1` is populated. Root cause: the checker greps `APPROVAL_LOG.md` only, while the live state file (`phase-state.json::gates`) is the actual source of truth for gate-passage timestamps. Cross-source inconsistency between the live state file and the validator.

**Why it matters:** Operators reading `validate.sh` output get a false negative for gate-date recording — the gate may have passed and been recorded in `phase-state.json`, but `validate.sh` claims no date is on file. Operators may then try to "re-record" a gate that is already recorded, or treat the project as out-of-compliance when it is in fact compliant. The drift also confuses any downstream automation that trusts `validate.sh`'s output.

**Scope:**
- Pick the canonical source. Two valid resolutions per the report:
  - (a) Update `scripts/validate.sh:281` to read gate dates from `phase-state.json::gates.<gate>` first, falling back to `APPROVAL_LOG.md` only if the JSON path is absent (back-compat).
  - (b) Document that `APPROVAL_LOG.md` is canonical and update any writer that updates `phase-state.json::gates` without mirroring to the log.
- Add a regression test that initializes a project, advances Phase 0→1 (which populates `phase-state.json::gates.phase_0_to_1`), then asserts `validate.sh` does NOT emit `no date recorded` for that gate.
- Audit any other validator checks that conflate the two sources.

**Trigger:** Next pass on `scripts/validate.sh` for any reason; or when an operator next reports a phantom "no date recorded" warning for a gate they know is recorded. Bundle with BL-060 (sibling argv-parser drift in `check-phase-gate.sh`).

**Reproduction:** Per the report — `bash scripts/upgrade-project.sh --to-full --non-interactive` after a Phase-0→1-recorded project, then `bash scripts/validate.sh` and observe the false-negative line at `validate.sh:281`.

**Related:** `Reports/2026-06-29-adversarial-certainty-pass.md` § Tailoring signals catalog (S-2); `scripts/validate.sh:281`; `phase-state.json::gates`; `APPROVAL_LOG.md`; sibling entries BL-060, BL-061 (same report).

---

## BL-060: check-phase-gate.sh does not parse `--gate` argv flag

**Logged:** 2026-06-29
**Category:** Bug
**Severity:** Medium
**Status:** Open

The adversarial certainty re-walk (re-walker-4, scenario `edge-tier-crosscheck-6-no-classification-blocks-phase1to2`) surfaced that the scenario passes `--gate phase_1_to_2` to `scripts/check-phase-gate.sh`, but the script has no argv parser for that flag — the gate fires only because `current_phase=2` in `phase-state.json` triggers the backstop. Doc-vs-code drift: the documented CLI surface and the implemented CLI surface disagree.

The re-walker also noted (helpfully) that the output included a separate earlier `[FAIL] Phase 1->2 backstop: protection verification failed` line, and that both fails are emitted in sequence (not short-circuited) — so the data-classification FAIL is not hiding behind the unrelated branch-protection failure. The assertion still fires correctly via the backstop, so the scenario verdict stands; the defect is in the CLI surface itself.

**Why it matters:** Operators (and scripts) that invoke `check-phase-gate.sh --gate <name>` expecting the flag to scope the check are silently relying on the backstop's coincidental triggering. A future refactor that changes the backstop's trigger condition (e.g., by inferring the gate from `current_phase` differently) would silently break callers that pass `--gate`. Scenarios documenting the flag perpetuate the drift.

**Scope:** Two resolution paths:
- (a) Implement an argv parser for `--gate <name>` in `scripts/check-phase-gate.sh` that scopes the check to the named gate (and validates the name is one of the known gates). Update the help text and any in-repo docs that mention the flag.
- (b) If the flag is not desired, remove `--gate` from the affected scenario(s) (e.g. `edge-tier-crosscheck-6-no-classification-blocks-phase1to2`) and any doc that mentions it, so the scenario explicitly exercises the backstop path.
- Either way, add a regression test that asserts the chosen behavior (flag honored, OR flag rejected with a clear diagnostic).

**Trigger:** Next pass on `check-phase-gate.sh`'s CLI surface; bundle with BL-055 (per-line APPROVAL_LOG.md blame walker), which already touches the same script.

**Reproduction:** `bash scripts/check-phase-gate.sh --gate phase_1_to_2` with no `--gate phase_1_to_2`-specific arg-parsing path active — observe that the check still fires by virtue of `current_phase=2` in `phase-state.json` rather than via the flag.

**Related:** `Reports/2026-06-29-adversarial-certainty-pass.md` § Tailoring signals catalog (S-3); `scripts/check-phase-gate.sh`; scenario `edge-tier-crosscheck-6-no-classification-blocks-phase1to2`; sibling entries BL-055, BL-059, BL-061 (same report / adjacent script).

---

## BL-061: manifest.json::deployment is a stale snapshot after upgrade-project.sh runs

**Logged:** 2026-06-29
**Category:** Bug
**Severity:** Medium
**Status:** Open

The adversarial certainty re-walk (re-walker-3, scenario `migration-personal-prod-to-org-prod-needs-data-class`) surfaced that `scripts/upgrade-project.sh` does not refresh `manifest.json::deployment` after the upgrade completes. The field diverges from `phase-state.json` (which is the live source of truth) — for example, after a `personal → organizational` upgrade, `phase-state.json::deployment = organizational` but `manifest.json::deployment` still reads `personal`.

**Why it matters:** Operators (and any tooling that reads `manifest.json` rather than `phase-state.json`) get a stale view of project state post-upgrade. The two-source split also encourages bugs where a future check naively reads `manifest.json::deployment` and makes the wrong decision (e.g., gating an org-only path that the project has already upgraded into). Today the walker noted and did not downgrade, but the divergence is real.

**Scope:** Two resolution paths (the report explicitly offers both):
- (a) **Refresh `manifest.json` in `upgrade-project.sh`** — extend the upgrade routine to update `manifest.json::deployment` (and any other fields that should track `phase-state.json`) atomically alongside the `phase-state.json` write. Pick one canonical write helper to avoid drift between upgrade paths.
- (b) **Formally mark `manifest.json` a stale snapshot** — add a comment / docs note that `manifest.json` captures *initial* project shape (at `init.sh` time) and is NOT refreshed by `upgrade-project.sh`. Audit every reader of `manifest.json::deployment` and migrate to `phase-state.json::deployment`.
- Whichever path is chosen, add a regression test that initializes a personal project, upgrades to organizational, and asserts the chosen contract (refreshed OR documented-stale).

**Trigger:** Bundle with the next `upgrade-project.sh` change. Higher urgency if any new code is about to read `manifest.json::deployment` (would compound the drift).

**Reproduction:** Initialize a personal project, then `bash scripts/upgrade-project.sh --to-organizational --non-interactive`, then `jq -r '.deployment' manifest.json` and `jq -r '.deployment' phase-state.json` — observe the mismatch.

**Related:** `Reports/2026-06-29-adversarial-certainty-pass.md` § Tailoring signals catalog (S-4); `scripts/upgrade-project.sh`; `manifest.json`; `phase-state.json`; sibling entries BL-059, BL-060 (same report).

---

## BL-062: Step-5 walker grading rubric — when matrix text and observed artifact disagree, default to `partial`

**Logged:** 2026-06-29
**Category:** Documentation
**Severity:** Minor
**Status:** Open

The adversarial certainty re-walk (re-walker-3, scenario `migration-private-poc-personal-to-sponsored-poc-org`) surfaced the only re-walker disagreement across 38 scenarios: the original walker graded `pass` by accepting "documented template behavior" framing, while the adversary downgraded to `partial` because the matrix `expected_terminal_state` literally said "3 rows visible" but the surfaced artifact contains all 6 rows. Both readings were available; the walker chose the lenient one.

This is a walker-process (rubric) signal, not a product defect. The underlying contract question (template vs. matrix wording) is already under BL-058 investigation and addressed by PR #108.

**Why it matters:** If the same divergence shape appears in a future sweep and walkers continue to default to the lenient reading, real contract-violations could be silently graded `pass` and hide regressions. The certainty rate was 97.4% only because the adversarial pass caught this one — the original walker pass would have hidden it.

**Scope:**
- Update the Step-5 dogfood-walker rubric / spec to make the default explicit: **when matrix `expected_terminal_state` text and observed artifact disagree, the grade is `partial` (NOT `pass`), pending a doc-vs-product resolution.** The walker should flag the disagreement, not paper over it with the lenient reading.
- Add a rubric example using this exact scenario (Sponsored POC 3-row-vs-6-row case) showing the correct `partial` grading and the resolution paths (product fix / doc fix / re-grade after disposition).
- No code change; doc-only.

**Trigger:** Before the next Step-5 dogfood sweep (so the new rubric is in force when re-walks are commissioned).

**Reproduction:** N/A (process signal, not a runtime defect). The triggering scenario is documented in `Reports/2026-06-29-adversarial-certainty-pass.md` §4.

**Related:** `Reports/2026-06-29-adversarial-certainty-pass.md` § Tailoring signals catalog (S-5), §4 (the disagreement); BL-058 (the underlying contract resolution); sibling entries BL-063 (same rubric surface).

---

## BL-063: Enforcement-point scenario contracts assert message-present, not message-only

**Logged:** 2026-06-29
**Category:** Coverage
**Severity:** Minor
**Status:** Open

The adversarial certainty re-walk (re-walker-5, scenarios `edge-phase-3-to-4-poc-blocked-check-phase-gate` and `edge-phase-3-to-4-poc-blocked-process-checklist`) surfaced that both enforcement-point scenarios pass against a contract that only asserts the documented POC-block message is present — they do not assert it is the only block. In one case, the gate output contains 15 inconsistencies; the POC block line is one of them. The scenarios pass as long as the POC-block string appears somewhere in the output, regardless of what else fails.

**Why it matters:** A future regression that introduces an unrelated `[FAIL]` at the same enforcement point would not be caught by these scenarios — the POC-block line is still present, so the assertion still fires. The contract is too loose to detect "the POC block fires for the right reason, alone." This is silent-defect-hiding waiting to happen.

**Scope:**
- Tighten the enforcement-point contracts so they assert either "no other unexpected FAILs" OR "the POC block is the *first* `[FAIL]` line." Pick the stricter of the two that does not over-couple to incidental noise.
- Audit any other scenario in the Step-5 matrix that uses "message present" semantics for an enforcement-point assertion; promote them to the tighter contract.
- Add a negative-control test fixture (deliberately seed an unrelated `[FAIL]` at the enforcement point) and confirm the tightened contract catches it.

**Trigger:** Before the next Step-5 dogfood sweep or when a new enforcement point is added. Bundle with BL-062 (same rubric surface).

**Reproduction:** Compare `edge-phase-3-to-4-poc-blocked-check-phase-gate`'s assertion against the full output of `check-phase-gate.sh` for a Phase-3→4 POC-blocked transition — observe that the POC-block line is one of many failure lines in the gate output.

**Related:** `Reports/2026-06-29-adversarial-certainty-pass.md` § Tailoring signals catalog (S-6); `scripts/check-phase-gate.sh`; `scripts/process-checklist.sh`; scenarios `edge-phase-3-to-4-poc-blocked-check-phase-gate` and `edge-phase-3-to-4-poc-blocked-process-checklist`; sibling entry BL-062 (same report, sibling rubric tightening).

---

## BL-064: init.sh exits 0 with `Setup Complete` banner after emitting `[FAIL]` for branch protection (silent-success defect)

**Logged:** 2026-06-29
**Category:** Bug
**Severity:** Major
**Status:** Closed (2026-06-30, PR #118, commit 443b50a)

The adversarial certainty re-walk (re-walker-2, scenario `fresh-org-sponsored-poc-standard-web-ts`) surfaced that `init.sh` exits `0` with the `Setup Complete` banner even after emitting a `[FAIL]` line for branch protection. Operators who only check the exit code (or scan for the banner) miss the gap entirely — the script claims success while having printed a failure diagnostic. This is the same silent-success defect shape that PR #105 fixed in `intake-wizard.sh:2028` (and the same defect class addressed by recent retroactive lint additions for `[FAIL]`-followed-by-`exit 0` patterns).

**Why it matters:** Silent-success defects are the single highest-priority bug class in this project's history: they corrupt operator trust in the exit-code contract, they bypass any wrapper script that gates downstream actions on `init.sh` succeeding, and they let a half-configured project look fully configured. In this specific case, an operator who runs `init.sh` non-interactively (e.g., in a setup script) gets `rc=0` and a "Setup Complete" banner while branch protection is in a `[FAIL]` state — exactly the scenario branch protection exists to prevent.

**Scope:**
- Audit `init.sh` for every `print_fail` / `[FAIL]` emit site and ensure each one either (a) sets an error-tracking variable that causes the final exit to be non-zero, or (b) explicitly justifies why a `[FAIL]` is acceptable to continue past (with a code comment citing the justification).
- The branch-protection `[FAIL]` path specifically: confirm whether the failure is fatal (most-common operator expectation) or non-fatal-but-loud (with a structured summary at exit). Decide and implement; do not leave both interpretations live.
- At minimum, emit a structured summary at exit-time that re-lists every `[FAIL]` printed during the run, so an operator scanning only the tail of the log still sees the gaps.
- Add a regression test that runs `init.sh` against a fixture that triggers the branch-protection `[FAIL]` path and asserts the new contract (either non-zero exit, or a Setup-Incomplete banner with the failures re-listed).
- Extend `scripts/lint-counter-antipattern.sh` (or a sibling lint) to flag any new `print_fail` site in `init.sh` that does not feed into the exit-status tracking — same shape as the PR #105 lint addition.

**Trigger:** Treat as the next Major bug in queue. Silent-success defects have repeatedly produced operator pain in past audits (PR #105 cycle); this one is the same shape and deserves the same urgency.

**Reproduction:** Per the report — run the `fresh-org-sponsored-poc-standard-web-ts` scenario from the Step-5 dogfood matrix, observe `[FAIL]` line for branch protection in the output, observe `rc=0` and `Setup Complete` banner in the same run.

**Related:** `Reports/2026-06-29-adversarial-certainty-pass.md` § Tailoring signals catalog (S-7); `init.sh` (branch-protection section); PR #105 (sibling silent-success fix in `intake-wizard.sh:2028`); sibling entries BL-059..BL-063 (same report).

---

## BL-065: E30 (`init.sh --platform other`) RED on main in `tests/edge-cases-scripts.sh` — failure mode uncharacterized

**Logged:** 2026-06-30
**Category:** Bug
**Severity:** Trivial
**Status:** Open

When PR #111 wired `tests/edge-cases-scripts.sh` into `full-project-test-suite.sh` (TEST 0r), the aggregator-registration commit (`cc1e532`) documented the file as `known-RED (BL-039 + BL-009 follow-up)` and gated it behind a new `SKIP_KNOWN_FAILING` env var so the suite stays green for local iteration loops while the underlying defects are tracked separately. The cited BLs cover E50 (BL-039) and the UAT-template guardrails (BL-009 follow-up), but the RED state in `tests/edge-cases-scripts.sh` also covers **E30** — the `init.sh --platform other` case at `tests/edge-cases-scripts.sh:1031-1041` — which has no backlog entry today. E30 asserts that `init.sh --platform other` skips the UAT reference-pair copy while leaving `tests/uat/templates/test-session-template.html` in place (the documented escape hatch for unsupported platforms); the failure mode (whether the template is missing, the reference files are present anyway, the script exits non-zero, or something else) is not characterized in the PR #111 commit message or in any current report.

**Why it matters:** `--platform other` is the documented escape hatch for any platform the matrix does not enumerate (per `docs/builders-guide.md` platform section). If it is broken, operators trying to onboard a non-listed platform (e.g. embedded, firmware, browser-extension) get a silently wrong scaffold — either no UAT skeleton at all, or one with platform-mismatched reference content. The defect is currently invisible because the only test that pins the contract is gated by `SKIP_KNOWN_FAILING` by default in the iteration loop, and the suite-level CI gate is still pending (BL-038/BL-045 dependency chain). Until BL-065 is fixed, `--platform other` is functionally unsupported and any operator who selects it is on the wrong side of the contract that E30 was written to enforce.

**Scope:**
- Run E30 in isolation: `bash tests/edge-cases-scripts.sh 2>&1 | grep -B2 -A20 'E30'`. Capture the log path emitted on FAIL (`$_uat_work/init-other.log`) and read it to see which of the three E30 assertions tripped (template present, refs absent×2).
- Characterize the failure mode in three buckets and pick the matching fix:
  - Bucket A (template missing): `init.sh` `--platform other` is not copying the source template at all. Trace through `scripts/init.sh` UAT-copy section; either the platform key is unrecognized and the function early-returns, or the template lookup uses a non-existent fixture path. Fix the path/lookup.
  - Bucket B (reference files present anyway): `init.sh` is treating `other` as if it were a known platform and copying a reference pair anyway. Add an explicit branch for `other` (or harden the platform allow-list) that skips the reference copy.
  - Bucket C (script exits non-zero before reaching UAT step): some upstream check rejects `other` as an invalid platform value. Either widen the platform allow-list or change the gate to a WARN.
- Write a regression test inside `tests/edge-cases-scripts.sh` that pins the bucket-A/B/C boundary so a future "fix" to a different bucket cannot silently re-break the original behavior.
- Verify E30 GREEN before closing; once GREEN, the `known-RED` annotation for `tests/edge-cases-scripts.sh` in `tests/full-project-test-suite.sh` TEST 0r needs to be updated to reflect that only BL-039 (E50) + BL-009 (follow-up) remain — or removed entirely if those have also landed.

**Trigger:** Treat as the next Major bug in queue after BL-064. Same urgency as BL-039 (sibling known-RED in the same file) — both are gated by `SKIP_KNOWN_FAILING` and both represent silent contract violations of operator-facing init.sh behavior. Land BL-065 + BL-039 together if scope permits since they share the same edge-cases aggregator and the same investigation pattern (run-in-isolation → read log → patch init.sh → flip the test from RED to GREEN).

**Reproduction:** From a clean tree, `bash tests/edge-cases-scripts.sh 2>&1 | grep -A2 'E30'` — observe the `[FAIL] E30: real init.sh --platform other produced wrong state (refs present or template missing) (log: /tmp/...)` line and inspect the cited log for the exact failure shape.

**Dependencies:** None blocking. BL-034 is already landed (PR #111 `cc1e532`) so `tests/edge-cases-scripts.sh` is in an aggregator; this BL just flips E30 from RED to GREEN.

**Related:** PR #111 commit `cc1e532` (registered the file as `known-RED`); `tests/edge-cases-scripts.sh:1031-1041` (E30 assertion block); `tests/edge-cases-scripts.sh:949-1041` (UAT-platform E26-E30 block surrounding E30); BL-039 (sibling known-RED E50 in the same file); BL-009 (UAT-template guardrails / platform-aware authoring); BL-034 (test-aggregator wiring invariant); `scripts/init.sh` UAT reference-pair copy section; `docs/builders-guide.md` platform escape-hatch documentation.

### Characterization (2026-06-30)

**Confirmed failure mode:** `init.sh` exits with rc=1 *before* the project scaffold or the UAT copy block ever runs. The stderr signature is:

```
[FAIL] init.sh non-interactive: language 'typescript' is not supported for platform 'other'
  Reason: no CI pipeline template (templates/pipelines/ci/github/<lang>.yml) lists other in its platforms marker for that language.
  Action: re-run with one of: other
  Context: --platform='other', --language='typescript'
```

E30's three positive/negative file assertions (`tests/edge-cases-scripts.sh:1120-1122`: template present, two reference files absent) all fail because the project tree was never created — not because the `--platform other` UAT branch produced the wrong state.

**Root cause:** The `_uat_real_init` helper at `tests/edge-cases-scripts.sh:1040-1058` hardcodes `--language typescript` for every platform it is called with. The non-interactive Pass-2 validator at `init.sh:3447` (mirror of the interactive filter at `init.sh:524-529`) walks `templates/pipelines/ci/github/*.yml` and reads each file's `# solo-orchestrator: platforms=` marker; the only template that lists `other` is the catch-all `templates/pipelines/ci/github/other.yml` (gated via the special-case branch at `init.sh:3417`). Because `typescript.yml`'s marker does not include `other`, the combination is rejected and init.sh aborts before reaching the `PLATFORM = other` UAT branch at `init.sh:1261`.

The production `other` branch is itself correct — re-running the same invocation with `--language other` produces rc=0, creates `tests/uat/templates/test-session-template.html`, and does NOT create the reference pair, exactly matching the E30 assertion contract.

**Blast radius:** test-harness-only. Zero operator-facing impact: every wizard path and every legitimate non-interactive contract path for `--platform other` produces the correct state. The defect is confined to one helper invocation inside one assertion block.

**Recommended severity:** **S4 (Trivial / test-harness-only).** Downgrade from the as-filed Major (S2). The PR #111 commit message inferred the failure was a production contract violation on the documented `--platform other` escape hatch; the characterization refutes that. The E30 helper, rewritten in PR #110 / commit `66da15c`, simply missed that the typescript pipeline-template marker excludes `other`. Per the task's own classification rubric ("test-harness-only -> S4"), the severity must drop.

**Reproduction commands:**

```bash
# Reproduce the RED state E30 exhibits today:
tmp=$(mktemp -d) && cd "$tmp" && mkdir -p e30-other && ( cd "$tmp" && \
  bash "/Users/karl/Documents/Claude Projects/solo-orchestrator/init.sh" \
    --non-interactive --project e30-other --platform other --deployment personal \
    --language typescript --git-host github --visibility private --no-remote-creation \
    --project-dir "$tmp/e30-other" --allow-existing-dir \
    < <(printf 'Y\nY\nY\nY\nY\nY\nY\nY\nY\nY\n') ) ; echo rc=$?
# Expected: rc=1, stderr 'language typescript is not supported for platform other'

# Control proving production is correct with the legitimate language:
tmp=$(mktemp -d) && cd "$tmp" && mkdir -p e30-other && ( cd "$tmp" && \
  bash "/Users/karl/Documents/Claude Projects/solo-orchestrator/init.sh" \
    --non-interactive --project e30-other --platform other --deployment personal \
    --language other --git-host github --visibility private --no-remote-creation \
    --project-dir "$tmp/e30-other" --allow-existing-dir \
    < <(printf 'Y\nY\nY\nY\nY\nY\nY\nY\nY\nY\n') ) ; echo rc=$? ; \
  ls "$tmp/e30-other/tests/uat/templates/test-session-template.html" ; \
  ls "$tmp/e30-other/tests/uat/examples/"
# Expected: rc=0, template present, examples dir empty (matches E30's three assertions)
```

**Fix complexity:** **Trivial.** Two equally valid options:

1. One-line change at `tests/edge-cases-scripts.sh:1052` — when the platform is `other`, pass `--language other` instead of the hardcoded `--language typescript`. Smallest possible patch.
2. Generalize `_uat_real_init` to accept a per-platform language argument (default typescript, override to `other` for the `other` case). Slightly larger but keeps the helper reusable for future per-platform E-tests.

No production code change is needed in `init.sh`, the UAT-copy section, or the pipeline templates. After the fix, narrow the `SKIP_KNOWN_FAILING` gate in `tests/full-project-test-suite.sh` TEST 0r to drop BL-065 from the known-RED set (BL-039 / BL-009 follow-up may remain depending on their state).

**Severity line update:** Yes — change the entry's `**Severity:** Major` to `**Severity:** Trivial` and adjust the `Why it matters` / `Trigger` sections to reflect that this is a test-harness fix, not a production contract violation. The `--platform other` escape hatch is NOT broken in production.

---

## BL-066: 3 of 9 host-drivers e2e tests RED on main (`e2e-init`, `e2e-init-gitlab`, `e2e-init-bitbucket`) — failure modes uncharacterized

**Logged:** 2026-06-30
**Category:** Bug
**Severity:** Trivial
**Status:** Open

When PR #111 wired `tests/host-drivers/run-all.sh` into `full-project-test-suite.sh` (TEST 0s), the aggregator-registration commit (`cc1e532`) documented the file as `known-RED (e2e-init-* trio)` and gated it behind `SKIP_KNOWN_FAILING` so the suite stays green for local iteration loops. The "trio" comprises `tests/host-drivers/e2e-init.test.sh` (github), `tests/host-drivers/e2e-init-gitlab.test.sh`, and `tests/host-drivers/e2e-init-bitbucket.test.sh` — the three end-to-end init.sh tests that exercise the full host-driver path against a mocked host CLI / `curl` stub (per BL-003, BL-003a, BL-003b, all closed). The other six children of `run-all.sh` (`github.test.sh`, `gitlab.test.sh`, `bitbucket.test.sh`, `regressions.test.sh`, `mock-cli.selftest.sh`, `dispatcher.test.sh`) are all GREEN; only the e2e trio is RED, and the specific failure modes are not characterized in the PR #111 commit message or in any current report. Whether all three e2e tests share a single root cause (e.g. a regression in `init.sh`'s host-driver invocation path), or each fails for a distinct host-specific reason, is unknown today.

**Why it matters:** BL-003 / BL-003a / BL-003b were closed (PRs #59, #61, #62) on the explicit promise that the host-driver e2e surface is regression-protected end-to-end. RED state on the trio means that promise is currently false: any silent regression in the init.sh host-driver invocation path, the mocked-CLI contract, the `curl`-stub case-match logic, or the post-init verification assertions would not be caught by CI. Because all three failed simultaneously, the most likely shapes are (a) a shared init.sh refactor that desynced the e2e fixtures, (b) a shared change in the mock-CLI harness that the e2e suite consumes (`tests/host-drivers/mock-cli.sh`), or (c) three independent host-specific regressions that all happen to be live at the same time. The first two are higher-priority because a single fix could close all three; the third would require splitting BL-066 into BL-066a/b/c per host.

**Scope:**
- Run each of the three RED e2e tests in isolation to capture the failure shape:
  - `bash tests/host-drivers/e2e-init.test.sh 2>&1 | tee /tmp/e2e-github.log`
  - `bash tests/host-drivers/e2e-init-gitlab.test.sh 2>&1 | tee /tmp/e2e-gitlab.log`
  - `bash tests/host-drivers/e2e-init-bitbucket.test.sh 2>&1 | tee /tmp/e2e-bitbucket.log`
- Compare the three logs for common signal (same failing assertion name, same stderr fragment, same exit code on the same line of init.sh) — if found, root-cause once and fix all three in one PR.
- If the three failures are independent (different assertions, different hosts, different code paths), split this BL into BL-066a (github), BL-066b (gitlab), BL-066c (bitbucket) and file each per the per-host scope below.
- Per-host scope template:
  - Trace from the failing assertion back through the mocked-CLI invocation transcript (the tests write `$TMP/<cli>-calls.log` and check it after init.sh exits). Determine whether the failure is in (i) the mock didn't get called as expected (init.sh didn't reach the call site), (ii) the mock got called with the wrong args (init.sh's host-driver dispatch is wrong), or (iii) the post-init verification assertion is wrong (artifact-state expectation changed).
  - Apply the fix in init.sh / the driver / the test (in that order of preference — test changes are last resort and require an inline comment explaining the contract drift).
  - Flip the test from RED to GREEN, confirm `bash tests/host-drivers/run-all.sh` reports 9/9 PASS.
- Once GREEN, update the PR #111 `known-RED (e2e-init-* trio)` annotation in `tests/full-project-test-suite.sh` TEST 0s (remove the gate so the test runs in the default suite).
- Add a regression note in the per-host driver doc (`scripts/host-drivers/<host>/`) capturing what changed and why the e2e test now pins it.

**Trigger:** Treat as the next Major bug in queue after BL-065. Three simultaneously-RED e2e tests is the strongest possible signal that the host-driver surface has drifted from its tested contract — same severity tier as BL-064 (silent-success in init.sh) because both are operator-facing contract violations on the primary onboarding code path. Land BL-066 before any further host-driver work (PR #110-era backlog items, BL-031-family follow-ups) so subsequent PRs are not built on top of an unverified e2e surface.

**Reproduction:** `bash tests/host-drivers/run-all.sh 2>&1 | tail -30` — observe the `[FAIL]` lines for the three e2e children, then `bash tests/host-drivers/e2e-init.test.sh` (and the gitlab/bitbucket siblings) individually to capture each failure mode.

**Dependencies:** None blocking. BL-034 is already landed (PR #111 `cc1e532`) so `tests/host-drivers/run-all.sh` is in an aggregator; this BL just flips the e2e trio from RED to GREEN. If split into BL-066a/b/c, the three sub-BLs are independent and can land in any order or in parallel.

**Related:** PR #111 commit `cc1e532` (registered `run-all.sh` as `known-RED (e2e-init-* trio)`); `tests/host-drivers/e2e-init.test.sh`, `tests/host-drivers/e2e-init-gitlab.test.sh`, `tests/host-drivers/e2e-init-bitbucket.test.sh` (the three RED files); `tests/host-drivers/run-all.sh` (the umbrella runner); `tests/host-drivers/mock-cli.sh` (shared mock harness — candidate shared root cause); BL-003 (e2e umbrella, closed PR #59 `f684aa7`), BL-003a (gitlab e2e, closed PR #61), BL-003b (bitbucket e2e, closed PR #62); BL-034 (test-aggregator wiring invariant); `scripts/init.sh` host-driver dispatch section.

### Characterization (2026-06-30)

**Confirmed failure mode:** All three e2e tests exit rc=1 with an identical root-cause stderr signature emitted by `init.sh:3447` (the non-interactive Pass-2 platform×language validator):

```
[FAIL] init.sh non-interactive: language 'javascript' is not supported for platform 'web'
  Reason: no CI pipeline template (templates/pipelines/ci/github/<lang>.yml) lists web in its platforms marker for that language.
  Action: re-run with one of: csharp, go, java, kotlin, other, python, rust, typescript (or pick a different --platform).
  Context: --platform='web', --language='javascript'
```

Results:
- `tests/host-drivers/e2e-init.test.sh`: 0/5 pass (T1 personal, T2 org, T3 push-fail, T4 repo-exists, T5 protection-403)
- `tests/host-drivers/e2e-init-gitlab.test.sh`: 0/7 pass (T1-T5 plus T6 BL-031 host-agnostic exit-3 + T7 BL-032 Premium-tier regression guards)
- `tests/host-drivers/e2e-init-bitbucket.test.sh`: 0/5 pass (T1-T5)

init.sh bails before any host-driver dispatch runs, so the mocked-CLI never gets invoked and the test runner emits secondary `cd: $PROJ: No such file or directory` errors when it tries to enter the never-created project directory.

**Root cause:** Single shared root cause across all three files — stale CLI argument `--language javascript` baked into the `run_init_e2e` helper of each test:

- `tests/host-drivers/e2e-init.test.sh:179`
- `tests/host-drivers/e2e-init-gitlab.test.sh:201`
- `tests/host-drivers/e2e-init-bitbucket.test.sh:238`

init.sh added the strict Pass-2 validation in commit `73da7c9` (2026-06-28, "fix(init,intake): non-interactive Pass-2/Pass-3 language×platform validation alignment"). The validator walks `templates/pipelines/ci/github/*.yml` and reads each file's `# solo-orchestrator: platforms=` marker. No `javascript.yml` ships in the templates directory (only `typescript.yml` covers JS-family with `platforms=web,desktop,mobile,mcp_server`). The three e2e tests were written earlier (commits `f684aa7` / `fc9db0e` / `c8585fa`, BL-003 / BL-003a / BL-003b) and still pass `--language javascript`, so every scenario aborts before any host-driver code runs.

The host drivers, dispatcher, mocked-CLI harness (`tests/host-drivers/mock-cli.sh`), `curl`-stub case-match logic, and post-init verification assertions are all unchanged and remain proven green by their own unit suites (`github.test.sh`, `gitlab.test.sh`, `bitbucket.test.sh`), which bypass `init.sh` and call the driver entrypoints directly.

**Blast radius:** test-harness-only. Production code (`init.sh` validation logic, host drivers, dispatcher, mock-CLI harness) is correct. The BL's hypothesized scenarios — (a) shared init.sh refactor that desynced fixtures, (b) shared mock-CLI harness regression, (c) three independent host-specific bugs — all dissolve: it is (a) in the *trivial* sense that init.sh's validation tightened, but the fix is in the stale test args, not in init.sh or the drivers.

**Recommended severity:** **S4 (Trivial / test-harness-only)** — aggregate across all three. Downgrade from the as-filed Major (S2). Per the playbook rule "if all 3 are test-harness-only -> S4 aggregate". The BL-003 / BL-003a / BL-003b regression-protection promise is *restorable* with a one-line edit per file; the protection itself was never substantively broken — only silenced by stale test args. Note: while RED, T6 (BL-031) and T7 (BL-032) regression guards in `e2e-init-gitlab.test.sh` are silently bypassed because the failure aborts before reaching them — restoring the e2e suite also restores those guards.

**Reproduction commands:**

```bash
cd /Users/karl/Documents/Claude\ Projects/solo-orchestrator && \
  bash tests/host-drivers/e2e-init.test.sh           > /tmp/e2e-init.out      2>&1; echo rc=$?
cd /Users/karl/Documents/Claude\ Projects/solo-orchestrator && \
  bash tests/host-drivers/e2e-init-gitlab.test.sh    > /tmp/e2e-gitlab.out    2>&1; echo rc=$?
cd /Users/karl/Documents/Claude\ Projects/solo-orchestrator && \
  bash tests/host-drivers/e2e-init-bitbucket.test.sh > /tmp/e2e-bitbucket.out 2>&1; echo rc=$?

# Confirm no javascript.yml ships and typescript.yml covers web:
ls /Users/karl/Documents/Claude\ Projects/solo-orchestrator/templates/pipelines/ci/github/
head -1 /Users/karl/Documents/Claude\ Projects/solo-orchestrator/templates/pipelines/ci/github/typescript.yml
# Expected first line: # solo-orchestrator: platforms=web,desktop,mobile,mcp_server
```

**Fix complexity:** **Trivial.** One-line change per file in each `run_init_e2e` helper:

- `tests/host-drivers/e2e-init.test.sh:179`         — `--language javascript` -> `--language typescript`
- `tests/host-drivers/e2e-init-gitlab.test.sh:201`  — `--language javascript` -> `--language typescript`
- `tests/host-drivers/e2e-init-bitbucket.test.sh:238` — `--language javascript` -> `--language typescript`

No changes to host drivers, dispatcher, `tests/host-drivers/mock-cli.sh`, the `curl` stub, or any production code. After the swap, downstream assertions (manifest `host=`, `mode=`, `steps=`, `origin=`, `commit_count=2`, and the BL-031/BL-032 regression guards) should pass because the mock-CLI fixtures (`PROTECT_JSON_PERSONAL`, `PROTECT_JSON_ORG`, `MOCK_GH_*` env hooks) are unchanged from when the suite was last GREEN.

Once GREEN, remove the `known-RED (e2e-init-* trio)` annotation from `tests/full-project-test-suite.sh` TEST 0s so the test runs in the default suite. DO NOT split into BL-066a/b/c — single shared root cause, single PR.

**Severity line update:** Yes — change the entry's `**Severity:** Major` to `**Severity:** Trivial`. Update `Why it matters` to clarify that the BL-003 promise is silenced (not substantively broken), update `Scope` to remove the "split into BL-066a/b/c" branch (root cause confirmed shared), and update `Trigger` to note this can land alongside BL-065 in a single test-harness-only PR rather than being treated as a Major bug blocking subsequent host-driver work.
