# PR-Sweep Remediation Plan — BL-147…BL-154

**Provenance:** BL-146 cumulative-history review of all 229 merged PRs (2026-07-21,
Fable reviewer, every finding demonstrated by an executed probe on main
`e7bc567`), findings independently re-validated by the orchestrating session.
**Executor: Opus 4.8** (Karl's directive). **Plan author + final verifier:
Fable** (verifier tier ≥ implementer, the BL-097 rule). This plan is written to
the BL-098 junior-followable standard: follow it literally; where reality
disagrees with the plan, STOP and report — do not improvise.

**Ground rules (non-negotiable, all work):** watched-RED TDD (write/extend the
test, RUN it, see it fail for the stated reason, then build); every new test
registered in BOTH `tests/full-project-test-suite.sh` and the `tests.yml` unit
list; hermetic tests only (no network, no live remotes — CI-template checks are
CONTENT pins, never live runs); bash-3.2 subset; quote every path (the repo
path contains a space); no `--no-verify`; no gate route-arounds; one WP = one
branch = one PR, opened green, never self-merged; ledger entry per WP appended
to THIS file's directory as `PROGRESS.md`; backlog status updates staged
in-entry (Closed flips happen at merge, citing PR# + SHA).

---

## The one shared test asset (build FIRST, in WP-1)

`tests/test-bl147-ci-template-integrity.sh` — content-pin suite over
`templates/pipelines/**`. Grammar: derive the template list mechanically
(`find templates/pipelines/ci/github -name '*.yml'` etc. — never a hand
enumeration; a count floor guards vacuity, ≥10 github CI files). Each WP below
adds its cases here. Register in BOTH lists in WP-1; later WPs just add cases.

---

## WP-1 — BL-147 + BL-151: make the approval-integrity step real; gitleaks without the org-license trap

**Files:** all 10 `templates/pipelines/ci/github/*.yml`, both
`templates/pipelines/ci/gitlab/*.yml`, the new test suite.

1. RED first: cases asserting (a) every github CI template's checkout step
   carries `fetch-depth: 0`; (b) every github CI template contains the
   approval-integrity step (all 10 — today only python/typescript/other do);
   (c) no approval step contains `2>/dev/null`; (d) the diff base is the
   explicit expression below, not bare `origin/main...HEAD`; (e) no template
   uses `gitleaks/gitleaks-action` (the CLI form replaces it). Run → RED.
2. Checkout step in every github CI template becomes:
   `- uses: actions/checkout@<current-pin>` with `with: fetch-depth: 0`.
3. The approval step (stamp into ALL 10, byte-identical apart from nothing):
   ```yaml
   - name: Governance - Approval log integrity
     if: hashFiles('APPROVAL_LOG.md') != ''
     run: |
       BASE="origin/${{ github.base_ref || 'main' }}"
       if [ "${{ github.event_name }}" = "push" ]; then BASE="${{ github.event.before }}"; fi
       git fetch origin "${{ github.base_ref || 'main' }}" --quiet || true
       if ! git rev-parse --verify "$BASE" >/dev/null; then
         echo "::error::approval-log check cannot resolve base '$BASE' — failing LOUDLY (a check that cannot run must not pass)"; exit 1
       fi
       if git diff "$BASE...HEAD" -- APPROVAL_LOG.md | grep -qE '^\-[^-]'; then
         echo "::error::APPROVAL_LOG.md has deleted or modified lines. This file is append-only."; exit 1
       fi
   ```
   (Author-verification step: same base-resolution treatment.) NOTE the
   removed `2>/dev/null` and the fail-loud arm — that is the finding.
4. gitleaks: replace the action step in every github CI template with the CLI:
   ```yaml
   - name: Security - Secret detection (gitleaks)
     run: |
       GITLEAKS_VERSION=8.28.0
       curl -sSfL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" | tar -xz gitleaks
       ./gitleaks git --redact --exit-code 1
   ```
   (Version: check `gh api repos/gitleaks/gitleaks/releases/latest` at build
   time and use that; the value above is indicative. `gitleaks git` scans full
   history — that is why fetch-depth 0 matters here too.)
5. GitLab twins: same base-resolution + loud-fail fix in the gitlab CI
   templates' approval steps (gitlab clones are full by default, but the
   explicit-base + no-silencer discipline applies; verify what the templates
   actually contain and mirror the github semantics).
6. Mutation proofs: re-add `2>/dev/null` to one template → the suite case
   goes RED; remove `fetch-depth` from one → RED. Record both.
7. Blast radius: `bash scripts/run-lints.sh`; grep tests/ for any suite
   pinning the old approval-step text (`grep -rl 'origin/main...HEAD' tests/`)
   and update those fixtures deliberately (documented-bug exception applies —
   they pinned a vacuous step).

## WP-2 — BL-148 + BL-153: semgrep surface modernization, hook-parity policy

**Files:** all 10 github CI templates, all bitbucket CI templates, suite cases.

1. RED: cases asserting no template references `semgrep/semgrep-action` or
   `returntocorp/semgrep`; every github CI template carries a semgrep job/step
   whose flags EQUAL the local hook's policy string (derive the expected flag
   set by grepping `scripts/lib/hook-templates.sh` for the `semgrep scan`
   invocation — single source, never retype the rule list).
2. GitHub: replace the action step with:
   ```yaml
   sast:
     runs-on: ubuntu-latest
     container: { image: semgrep/semgrep }
     steps:
       - uses: actions/checkout@<current-pin>
         with: { fetch-depth: 0 }
       - run: semgrep scan --config p/owasp-top-ten --config p/security-audit --config r/javascript.browser.security.insecure-document-method --severity=ERROR --error
   ```
   (Exact flags: whatever the hook emits — read it, don't copy this.)
3. Bitbucket: `image: returntocorp/semgrep` → `image: semgrep/semgrep`; same
   flag parity; `gitleaks detect --source .` → `gitleaks dir .` and pin the
   image tag to a real version (check upstream latest).
4. Mutation: strip the DOM-XSS config from one template → parity case RED.

## WP-3 — BL-149: port BL-122 into the release DAST + tool-matrix image fix

**Files:** `templates/pipelines/release/github/web.yml`,
`templates/tool-matrix/web.json`, suite cases.

1. RED: cases asserting the release template (a) pins
   `ghcr.io/zaproxy/zaproxy:stable` (the scanner's image — not zap-stable);
   (b) judges `riskcode >= 2` via jq on a `-J` JSON report, never the raw exit
   code; (c) guards on `vars.PREVIEW_URL != ''`; and tool-matrix checks the
   SAME image the scanner runs.
2. Port the `# BL-122-ZAP-RISK-FILTER` logic (read it in
   `scripts/run-phase3-validation.sh`): run with mounted workdir + `-J`,
   drop rc 1/2 from the verdict, jq-count riskcode≥2, fail iff count>0 or the
   report is unreadable (unreadable = fail LOUDLY, the BL-140 posture).
3. tool-matrix/web.json: `zaproxy/zap-stable` → `ghcr.io/zaproxy/zaproxy:stable`
   in both check_command and the manual hint.
4. Mutation: revert the verdict line to raw exit → RED.

## WP-4 — BL-150: the pin refresh

**Files:** `.github/workflows/{lint,tests}.yml`, all emitted CI + release
templates, init.sh `RELEASE_SETUP_ACTION` table.

1. For each action: `gh api repos/<owner>/<repo>/releases/latest` → tag; then
   `gh api repos/<owner>/<repo>/git/ref/tags/<tag>` (deref annotated tags) →
   commit SHA. Update every pin to `<sha> # vN (vN.N.N)` comment form.
   Actions list: checkout, setup-node, setup-python, setup-java, setup-go?,
   upload-artifact, softprops/action-gh-release, golangci-lint-action,
   gitleaks-action IF any usage survives WP-1 (it should not), flutter-action
   (verify current), everything else `grep -rhoE 'uses: [^@]+@' templates/ .github/` finds.
2. gitleaks-action v3 note is moot if WP-1 removed it — verify.
3. RED-able pin case: suite asserts every `uses:` line carries a 40-hex SHA
   pin + a version comment (shape check, not version check — the version
   WATCHER is BL-109/BL-150's deferred half, out of scope here).
4. THE FRAMEWORK'S OWN workflows changed → CI must stay green on the PR; that
   run IS the live test of the new pins.

## WP-5 — BL-152: GitLab approval_rules migration

**Files:** `scripts/host-drivers/gitlab.sh`, `tests/test-gitlab-*` suites.

1. Read the driver's exit-code contract header FIRST (rc 3 generic / rc 4
   Premium-only — BL-032). RED: extend the driver suite (it stubs `glab`) with
   a case asserting the invocation is `POST projects/:id/approval_rules` with
   `approvals_required` — watch it fail against the PUT form.
2. Swap the call; preserve the BL-032 Premium-only detection (the error-body
   sniff — verify what string the approval_rules endpoint returns on free
   tier by reading the suite's existing fixtures; if unknowable offline, keep
   BOTH sniffs).
3. All gitlab suites green; mutation: revert to PUT → new case RED.

## WP-6 — BL-154: unit-list enforcement arm + CLAUDE.md true-up

**Files:** `scripts/lint-tests-registered.sh`, its test suite, CLAUDE.md.

1. RED: suite case with a fixture test file that is aggregator-registered but
   absent from a fixture tests.yml unit list → the new arm must flag it; and
   an init.sh-invoking fixture file must be EXEMPT (aggregator-only is correct
   for those — derive the predicate from the file's own text, the
   `grep -L 'init\.sh'` convention documented in tests.yml).
2. Implement behind a marker fence; the real repo must pass (delta is zero
   today — verified).
3. CLAUDE.md: the "lint-tests-registered.sh enforces" sentence becomes true —
   no edit needed beyond confirming; if the arm lands with a different name,
   update the sentence.

---

## Sequencing & discipline

Order: WP-1 → WP-2 → WP-3 (template wave, same suite file, stacked or
sequential-after-merge to avoid same-anchor conflicts — SEQUENTIAL preferred;
note the tests.yml/full-suite registration anchors collide across parallel
branches: the merge-choreography lesson) → WP-4 → WP-5 → WP-6.
Each WP: watched-RED evidence in the PR body; mutation proofs recorded; a
`PROGRESS.md` entry in this directory written before the PR opens. After the
last WP merges: consolidated Fable adversarial verification of the whole wave
(the #225–#227 pattern), then the Dogfood-4 milestone
(Solo-Orchestrator-work-example) proceeds.

**Out of scope (recorded, not built):** the action-pin version WATCHER
(BL-150's durable half — BL-109 territory); gitlab/bitbucket release-DAST
parity (recorded in BL-149); host-parity of approval steps beyond
github+gitlab (bitbucket has no approval step today — record, don't invent).
