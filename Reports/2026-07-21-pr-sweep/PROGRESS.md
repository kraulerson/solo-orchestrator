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

## WP-2 — BL-148 + BL-153: semgrep surface modernization, hook-parity policy

**Branch:** `fix/bl148-bl153-semgrep-modernization` · **Base:** `main` (stacked on
WP-1 #235, now MERGED to `main` @ `78d944e`; the reset base is an ancestor of
`main`, so the PR diff vs `main` is exactly the WP-2 delta). **Status:** PR opened
green, not merged.

### Reproduce (the finding)
- **BL-148:** all 10 `templates/pipelines/ci/github/*.yml` ran SAST via
  `semgrep/semgrep-action@713efdd… # v1 (v0.58.0)` — an action **archived
  upstream 2024-04-09**. Current upstream guidance (context7, semgrep docs): the
  `semgrep/semgrep` container running `semgrep scan`/`semgrep ci`.
- **BL-153:** the 2 bitbucket semgrep templates used `image: returntocorp/semgrep`
  (frozen at the 2023 org rename → `semgrep/semgrep`); all 10 bitbucket gitleaks
  steps used the pre-8.19 `gitleaks detect --source .` on an unpinned
  `zricethezav/gitleaks:latest`.
- **Scope discovery (drove the one deviation):** the same dead
  `returntocorp/semgrep` image + legacy gitleaks forms were present in **all 10
  gitlab CI templates** — which the plan's WP-2 "Files" line (github+bitbucket)
  omitted, but the global RED invariant + blast-radius grep require gone.

### Watched-RED (before any template touched)
Added WP-2 cases to the shared suite `tests/test-bl147-ci-template-integrity.sh`
(WP-1 already registered it in both lists). The expected semgrep flag set is
**DERIVED** from the hook's own `semgrep scan` invocation in
`scripts/lib/hook-templates.sh` (case `Cg-derive`) — single source, never
retyped; if the hook's policy changes the suite tracks it. Cases:
- **Cg1** no `templates/pipelines/**` file references `semgrep/semgrep-action` or
  `returntocorp/semgrep` (GLOBAL — github, gitlab, bitbucket, release, …)
- **Cg2** every github CI template carries a `semgrep scan --config` invocation
- **Cg3** every github semgrep invocation's config/severity/`--error` **EQUAL the
  hook** (config set = `p/owasp-top-ten` + `r/javascript.browser.security.insecure-document-method`, `--severity=ERROR`, `--error`)
- **Cg4** every github CI template declares the `image: semgrep/semgrep` container
- **Cg5** every non-github (gitlab+bitbucket) semgrep step: `image:
  semgrep/semgrep` + hook-parity flags (floor 12)
- **Cg6** every non-github gitleaks step modernized: no `detect --source`, runs
  `gitleaks dir`/`git`, off `zricethezav`, version-pinned image (floor 20)

Pre-fix run: **`Results: 18 passed, 13 failed`** (exit 1) — WP-1's 18 cases stay
green; every WP-2 failure maps to the finding (Cg1 flags 22 files; github has no
`semgrep scan`/container/parity; non-github carries `returntocorp` + the legacy
gitleaks forms). RED evidence saved to `scratchpad/wp2-RED.txt`.

### Fix
- **GitHub (10):** removed the archived `semgrep/semgrep-action` step; added a
  sibling `sast` job — `container: image: semgrep/semgrep`, `actions/checkout`
  (`fetch-depth: 0`, existing pin), then `run: semgrep scan
  --config=p/owasp-top-ten --config=r/javascript.browser.security.insecure-document-method
  --severity=ERROR --error`. Flags MIRROR the local hook (parity is the contract:
  CI and the dev gate enforce the identical ruleset). **Dropped `p/security-audit`**
  — the hook (single source) does not carry it; the backlog fix-shape example did,
  and it was corrected in the BL-148 Status update.
- **Verified the container form is correct** (context7 + web): `semgrep/semgrep`
  is Alpine-based (`docker.base_image=alpine:3.23`), but GitHub's runner detects
  Alpine and runs JS actions (checkout) with its musl `node20_alpine` build — this
  is Semgrep's own documented CI pattern. No deviation on the form.
- **GitLab + Bitbucket (20):** `returntocorp/semgrep` → `semgrep/semgrep`; the
  semgrep invocation → the same hook-parity form (`semgrep scan …`); gitleaks
  `detect --source .` → `dir .`; `zricethezav/gitleaks:latest` →
  `ghcr.io/gitleaks/gitleaks:v8.30.1` (official image; latest release confirmed via
  `gh api repos/gitleaks/gitleaks/releases/latest` = `v8.30.1`, manifest verified
  pullable HTTP 200).

Post-fix run: **`Results: 31 passed, 0 failed`** (exit 0). All 30 changed CI
templates re-validated as parseable YAML (PyYAML `safe_load`, 30/0). Evidence:
`scratchpad/wp2-GREEN.txt`.

### Mutation proof (run against the working tree; restored to GREEN)
- Strip the DOM-XSS config (`r/javascript.browser.security.insecure-document-method`)
  from `github/go.yml`'s semgrep line → **Cg3-config-parity RED**
  (`go.yml(=--config=p/owasp-top-ten )` ≠ hook; `Results: 30 passed, 1 failed`).
  Restore → GREEN (`31 passed, 0 failed`).

### Blast radius
- `grep -rln 'semgrep-action|returntocorp' templates/ scripts/ tests/ docs/` → the
  ONLY surviving hit is `tests/test-bl147-ci-template-integrity.sh` itself (the Cg1
  assertion pattern + its comments must contain the literals to grep for them).
  No template, script, or product doc references the dead namespaces.
- Two present-tense code comments corrected ("semgrep-action container" →
  "semgrep container") in `scripts/check-phase-gate.sh` + `tests/test-bl137-ci-tools-scope.sh`.
- Docs modernized (BL-153 theme): `docs/builders-guide.md`, `docs/user-guide.md`
  (`gitleaks detect --source .` → `gitleaks dir .`), `docs/cli-setup-addendum.md`
  (stale "CI runs gitleaks-action" → "the gitleaks CLI").
- Left untouched (historical/out-of-scope): all `Reports/**`, archived plans, the
  `evaluation-prompts/**` eval fixtures, and the BL-148/BL-153 problem statements.
- `bash scripts/run-lints.sh` → PASS (tally in the PR body).
  `scripts/lint-backlog-references.sh` → OK after the Status updates.

### Deviations from the plan
- **Expanded to gitlab CI (the one deviation).** The plan's WP-2 "Files" line lists
  github + bitbucket, but the dispatcher's RED case (i) is global ("no template
  ANYWHERE references … returntocorp/semgrep") and the blast-radius grep expects
  zero `returntocorp` under `templates/`. All 10 gitlab CI templates carried it, so
  eliminating the dead namespace forced editing every gitlab file. Being already in
  each file, the gitleaks + semgrep-flag modernization (identical debt to bitbucket)
  rode along for one consistent three-host surface. No other WP owns gitlab CI
  templates; stacked cleanly on WP-1.
- **gitleaks image registry:** the plan said only "pin the image tag." Chose the
  official current image `ghcr.io/gitleaks/gitleaks:v8.30.1` (DockerHub `gitleaks/gitleaks`
  does not exist; `zricethezav/*` is the retired personal namespace) — consistent
  with WP-3's `ghcr.io/zaproxy/*` convention.

---

## WP-3 — BL-149: port BL-122 into the release DAST + tool-matrix image fix

**Branch:** `fix/bl149-release-dast` · **Base:** `fix/bl148-bl153-semgrep-modernization`
(stacked on WP-2 #236; the worktree was reset to WP-2's head @ `4671df8`, and the
WP-3 branch cut from there). **Status:** PR opened green, not merged.

### Reproduce (the finding)
- `templates/pipelines/release/github/web.yml` ran
  `docker run -t zaproxy/zap-stable zap-baseline.py -t ${{ vars.PREVIEW_URL }}`
  and judged the **RAW docker exit code**. ZAP baseline reports every alert as
  WARN (exit 2), and rule 10049 (Storable/Cacheable, riskcode 0 = Informational)
  fires under EVERY Cache-Control value (the proven BL-122 mechanism) — so any
  real site fails the release. PR #203 fixed exactly this in
  `run-phase3-validation.sh` (`# BL-122-ZAP-RISK-FILTER` + `# BL-140-ZAP-WORKDIR`)
  and never touched the template.
- Aggravators: the image was **unpinned** (every other action in the file is
  SHA-pinned) and points at the dead `zaproxy/zap-stable`; **no guard** when
  `PREVIEW_URL` is unset; `templates/tool-matrix/web.json` checked/pulled the
  same dead `zaproxy/zap-stable` — an image the scanner never uses (CR-8 nit).
- Out of scope (per BL-149): gitlab/bitbucket release templates have no DAST
  step at all — recorded, not invented.

### Watched-RED (before any template touched)
Added WP-3 cases to the shared suite `tests/test-bl147-ci-template-integrity.sh`
(WP-1 registered it in both lists; WP-3 only adds cases — content pins only, no
live docker). Cases:
- **Cz0** the two named files exist (vacuity guard — a rename must fail loud)
- **Cz-a** release `web.yml` pins `ghcr.io/zaproxy/zaproxy:stable`, never `zap-stable`
- **Cz-b** the ZAP step writes `-J zap-report.json` to a mounted `/zap/wrk`,
  judges jq `riskcode >= 2`, and CAPTURES the raw exit (`|| rc=$?`) — never the verdict
- **Cz-c** the step is guarded `if: vars.PREVIEW_URL != ''`
- **Cz-d** an absent/unparseable report FAILs loudly (both arms exist textually)
- **Cz-e** `tool-matrix/web.json` references the SAME image (check + manual), never `zap-stable`

Pre-fix run: **`Results: 32 passed, 11 failed`** (exit 1) — WP-1+WP-2's 31 cases
stay green, Cz0 passes (files exist), every other WP-3 assertion RED and mapped
to the finding. RED evidence: `scratchpad/wp3-RED.txt`.

### Fix
- **`templates/pipelines/release/github/web.yml`** — the DAST step now mirrors the
  Phase-3 scanner's verdict: `docker run --rm -v "$ZAP_WORK:/zap/wrk"
  ghcr.io/zaproxy/zaproxy:stable zap-baseline.py -t "…PREVIEW_URL…" -J
  zap-report.json || rc=$?` into an ABSOLUTE mounted workdir
  (`${GITHUB_WORKSPACE}/.zap-work`, the BL-140 posture — docker `-v` rejects a
  relative path as a named volume); the raw exit is CAPTURED, not judged; the
  verdict is jq `[.site[]?.alerts[]? | select(((.riskcode // "0") | tonumber) >= 2)]
  | length` (Medium+ only). An absent report → `::error:: … exit 1`; `rc>=3` →
  execution-error `exit 1`; a jq-unparseable report → `::error:: … exit 1` (the
  BL-140/BL-112 fail-loud honesty class). Step guarded `if: vars.PREVIEW_URL != ''`.
- **`templates/tool-matrix/web.json`** — `check_command` and the manual hint now
  inspect/pull `ghcr.io/zaproxy/zaproxy:stable` (the SAME image the scanner runs).

Post-fix run: **`Results: 43 passed, 0 failed`** (exit 0). All changed release
templates re-validated as parseable YAML (PyYAML `safe_load`) and web.json as
valid JSON. GREEN evidence: `scratchpad/wp3-GREEN.txt`.

### Mutation proof (backup + restore; restored to GREEN)
- Remove the `|| rc=$?` capture from the docker line → under the runner's `set -e`
  the raw docker exit becomes the step verdict → **Cz-b-raw-exit-captured RED**
  (`Results: 42 passed, 1 failed`). Restore from backup → GREEN (`43 passed, 0 failed`).

### Blast radius
- `grep -rn 'zap-stable' templates/ scripts/ tests/ docs/` → the ONLY surviving
  hits are the suite's own grep literals in `tests/test-bl147-ci-template-integrity.sh`
  (the Cz assertions must contain the string to grep for it) and the historical
  `docs/superpowers/plans/archive/**` (carved-out records). No live template,
  script, or product doc references the dead image.
- **Image-name cleanup (same dead-image defect, comment/doc-only):** the commented
  DAST examples in `release/github/desktop.yml` + `mobile.yml` and the five
  references in `docs/platform-modules/web.md` were repointed
  `zaproxy/zap-stable` → `ghcr.io/zaproxy/zaproxy:stable`.
- `bash scripts/run-lints.sh` → PASS (all lints; tally in the PR body).
  `scripts/lint-backlog-references.sh` → OK after the BL-149 Status update.
- No new test file → registration unchanged (WP-1 already registered the shared
  suite in both `tests/full-project-test-suite.sh` and the `tests.yml` unit list).

### Deviations from the plan
- **Image-name cleanup beyond the two named files (blast-radius, not scope creep).**
  The plan's WP-3 "Files" line names `web.yml` + `web.json`; the task's blast-radius
  directive (`grep -rn 'zap-stable' …` → fix or report survivors) surfaced the SAME
  dead image name in two commented DAST examples (`desktop.yml`, `mobile.yml`) and
  `docs/platform-modules/web.md`. These are inert comments / docs — the image-name
  fix is a pure find-replace of a nonexistent image (the CR-8 defect BL-149 names),
  applied for a consistent estate. The **verdict-logic port** is confined to the
  emitted `web.yml` per the plan; the docs' CI snippet still illustrates a plain
  `zap-baseline.py` invocation (a docs example, not an emitted gate) — reported,
  not rewritten. No verdict logic was ported into gitlab/bitbucket release
  templates (they have no DAST — recorded in BL-149, not invented).

---

## WP-4 — BL-150: the action-pin refresh

**Branch:** `fix/bl150-pin-refresh` · **Base:** `fix/bl149-release-dast` (stacked
on WP-3 #237; the worktree was reset to WP-3's head @ `afd7161` and the WP-4
branch cut from there). **Status:** PR opened green, not merged.

### Reproduce (the finding)
- The estate SHA-pins its GitHub Actions (BL-113), but every pin had drifted
  1–3 majors behind upstream: `actions/checkout@v4.3.1` while latest is
  `v7.0.1`; setup-node/-python/-go on v4/v5 while latest is v7; upload/download-
  artifact, action-gh-release, golangci-lint-action, expo, setup-java, setup-
  dotnet all stale. Action pins are structurally invisible to BL-109's currency
  block (which tracks file SHAs / hooks / MCP), so nothing flags the drift.
- Surfaces: `.github/workflows/{lint,tests}.yml` (the framework's OWN CI),
  every emitted CI + release template, and the `RELEASE_SETUP_ACTION` pin table
  — which exists in `init.sh` **and** a byte-identical sync sibling in
  `scripts/reconfigure-project.sh`.

### Action inventory (built FIRST, before any edit)
`grep -rhoE 'uses: [^@ ]+@[^ ]+' templates/ .github/` (15 distinct actions) +
the two `RELEASE_SETUP_ACTION` tables. For each: `releases/latest` → `.tag_name`
→ `git/ref/tags/<tag>` → commit SHA (annotated tags de-ref'd once via
`git/tags/<sha>`). Pin form `<40-hex-sha> # vN (vN.N.N)`.

### Watched-RED (pre-green shape guard + mutation)
Added WP-4 cases to the shared suite `tests/test-bl147-ci-template-integrity.sh`
(WP-1 registered it in both lists; WP-4 only adds cases — SHAPE check only, no
network, no version-freshness assertion):
- **Cp1** every `uses:` ref under `templates/pipelines/**` + `.github/workflows/
  *.yml` carries `@<40-hex-sha> # <version comment>` (the build-time placeholder
  `__SETUP_ACTION__` is the sole exemption); floor 20.
- **Cp2** every action-bearing `RELEASE_SETUP_ACTION=` entry in `init.sh` AND the
  sync sibling `scripts/reconfigure-project.sh` is likewise SHA-pinned; floor 12.

Because the estate was ALREADY sha-pinned (only STALE), the cases **PRE-PASS**
on the stacked tree (`Cp1-floor 71 refs`, `Cp2-floor 14 entries`, all pinned) —
a legitimate pre-green shape guard, exactly the case the task anticipated. The
RED half is proven two ways: (i) the pin-refresh diff itself, and (ii) a
**mutation** — flip `github/python.yml`'s checkout to a bare `@v4` tag →
**Cp1-sha-pin RED** (`Results: 46 passed, 1 failed`); restore → GREEN
(`47 passed, 0 failed`).

### Fix — the pin table (old → new)
| action | old | new | bump |
|---|---|---|---|
| actions/checkout | v4.3.1 | **v7.0.1** `3d3c42e…` | MAJOR |
| actions/download-artifact | v4.3.0 | **v8.0.1** `3e5f45b…` | MAJOR |
| actions/setup-node | v4.4.0 | **v7.0.0** `82076278…` | MAJOR |
| actions/setup-python | v5.6.0 | **v7.0.0** `5fda3b9…` | MAJOR |
| actions/setup-go | v5.6.0 | **v7.0.0** `b7ad1da…` | MAJOR |
| actions/setup-java | v4.8.0 | **v5.6.0** `03ad4de…` | MAJOR |
| actions/setup-dotnet | v4.3.1 | **v6.0.0** `a98b568…` | MAJOR |
| actions/upload-artifact | v4.6.2 | **v7.0.1** `043fb46…` | MAJOR |
| golangci/golangci-lint-action | v6.5.2 | **v9.3.0** `ba0d7d2…` | MAJOR |
| softprops/action-gh-release | v2.6.2 | **v3.0.2** `3d0d988…` | MAJOR |
| expo/expo-github-action | 8.2.1 | **9.0.0** `eab7a23…` | MAJOR (commented usage) |
| google/osv-scanner-action | v2.3.5 | **v2.3.8** `9a49870…` | patch |
| dtolnay/rust-toolchain | stable-head 06-30 | **stable-head 07-21** `4cda84d…` | branch head |
| subosito/flutter-action | v2.23.0 | v2.23.0 (unchanged) | already current |
| realm/SwiftLint | 0.57.0 | 0.57.0 (**DEFERRED**) | see below |

### Input-compat verification (every MAJOR bump)
Checked each major's release notes for renamed/removed inputs the templates
actually use. **Result: zero input breakage** — the majors are Node-runtime
bumps (node20→node24) + minimum-runner-version, not input renames:
- checkout `fetch-depth: 0` — unchanged v4→v7.
- setup-node `node-version`/`cache`/`registry-url` — unchanged; v5 added
  auto-cache detection (additive), v6 limited auto-cache to npm (= what we use).
- setup-python `python-version` — unchanged; v7 removed the `pip-install` input,
  which the templates do NOT use.
- setup-go `go-version`, setup-java `distribution`/`java-version`/`cache`,
  setup-dotnet `dotnet-version` — all unchanged (node24 only).
- upload-artifact `path`/`name` — unchanged; v7's new `archive` param defaults
  to `true` (= the old zip behavior).
- download-artifact (bare, download-all) — v8 defaults `digest-mismatch=error`
  (a hardening; same-run artifacts never mismatch) and skips non-zip files by
  Content-Type (upload-artifact v7 zips by default → unzipped normally). Safe.
- action-gh-release `files`/`generate_release_notes` — unchanged (node24 only).
- golangci-lint-action `version: latest` — the `version` input survives; v7+
  supports golangci-lint **v2 only**, but `version: latest` already floats to
  the v2 line and init.sh scaffolds **no `.golangci.yml`** (v2 runs on defaults),
  so bumping the action major to v9 now MATCHES the linter major `latest`
  resolves to (v6 + v2-linter was the latent mismatch). Recorded, not a blocker.

### Deferred bump (reported, not built)
- **realm/SwiftLint 0.57.0 → held.** The repo ships **no `action.yml`/`action.yaml`
  at any ref** (confirmed via git-tree + raw fetch, tree not truncated) — it is a
  root-`Dockerfile` container action. The template passes `with: strict: true`,
  which has no verifiable input mapping, and the container contract **changed**
  between 0.57.0 (`CMD ["swiftlint"]`, no ENTRYPOINT) and 0.65.0
  (`ENTRYPOINT ["/usr/bin/swiftlint"]` + `CMD ["."]`). Per the plan's "do NOT
  blind-bump anything whose used inputs you cannot verify — leave at current pin
  and REPORT as deferred" rule, SwiftLint stays at 0.57.0. (The `strict` input
  appearing vestigial is a separate latent SwiftLint-step issue, out of WP-4's
  pin-refresh scope.)

### Deviation from the plan (one, sibling-sync)
- **`scripts/reconfigure-project.sh` updated in lockstep.** The plan's WP-4
  "Files" line names `init.sh`'s `RELEASE_SETUP_ACTION` table but not this file.
  reconfigure-project.sh carries a **byte-identical duplicate** of that table
  (the CLAUDE.md "SYNC SIBLINGS" class); leaving it stale would emit old pins on
  a reconfigure while init emits new ones. Both tables were bumped together and
  verified `diff`-identical. Cp2 now guards both against future drift.

### Fixed the framework's OWN CI too (sanctioned pins-only exception)
`.github/workflows/{lint,tests}.yml` checkout pins were bumped (v4→v7). CLAUDE.md
says don't modify lint.yml; this touches **pins only**, no job structure — the
sanctioned exception per the plan. The PR's own CI run IS the live test of the
new checkout pin.

### Post-fix
- Shared suite: **`Results: 47 passed, 0 failed`** (exit 0).
- All 44 changed pipeline templates + `.github/workflows/*.yml` re-validated as
  parseable YAML (PyYAML `safe_load`, 44/44); `tool-matrix/web.json` valid JSON.
- `bash -n` clean on `init.sh`, `scripts/reconfigure-project.sh`, and the suite.

### Blast radius
- No OLD action SHA survives anywhere in `templates/ .github/ init.sh
  scripts/reconfigure-project.sh` (per-SHA grep → none).
- `grep -rnE '@v[0-9]' templates/ .github/ | grep -v '#'` → **nothing unpinned**.
- Both commented example refs (mobile.yml, desktop.yml, the `# Example:` line)
  were bumped along with the active pins for a consistent estate.
- `bash scripts/run-lints.sh` → PASS (tally in the PR body);
  `scripts/lint-tests-registered.sh` → OK (suite already registered in WP-1);
  `scripts/lint-backlog-references.sh` → OK after the BL-150 Status update.

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

### Follow-up (verifier-adjudicated SHOULD-FIXes — same branch/PR)
The consolidated verifier held that BL-152 cannot close with the two items
below merely "recorded", so they are now BUILT:

- **Verify migrated off the deprecated scalar.** `host_verify_protection` now
  reads `GET projects/:id/approval_rules` (a JSON array) and judges "approvals
  configured" by ANY rule with `approvals_required >= 1`
  (`jq -r '[.[]?.approvals_required // 0] | max // 0'`) — mirroring the
  configure side. The old `.approvals_before_merge` read from `GET .../approvals`
  is deprecated (removed in v5) and does NOT reflect approval_rules, so it would
  false-fail on Premium once configure sets approvals via rules. Context7 confirmed
  the GET `/approval_rules` array shape (each element carries `approvals_required`).
- **`reset_approvals_on_push:true` re-applied.** Via a dedicated
  `POST projects/:id/approvals` CONFIG call after the approval_rules POST
  succeeds. Context7 confirmed `reset_approvals_on_push` is a current,
  non-deprecated field on that config endpoint (only its `approvals_before_merge`
  rule-count field was deprecated → migrated to approval_rules; the endpoint
  survives for the non-rule settings). Ordering makes it Free-safe: the Premium
  403 short-circuits at the approval_rules POST above, so the reset call is only
  reached on a tier that supports it. Its failure returns exit 3 (contract header
  updated: exit 3 now covers the approval-rules POST OR the reset config POST).

**Watched-RED (both new cases, against the pre-follow-up driver `git checkout HEAD -- gitlab.sh`):**
`8 passed / 3 failed` — **T10** (verify must GET `approval_rules`; RED log showed
`api projects/org%2Frepo/approvals`), **T11** (configure must emit a
`POST /approvals` carrying `reset_approvals_on_push`; RED log had no such call),
and **T3** (its fixture now expects the array-based verify). Post-fix: **11/0**.

**Isolated mutation proofs (finished driver; `</dev/null` to avoid the fixture's
GET-stdin `cat` blocking on a piped stdin):** revert ONLY the verify read
(`approval_rules` → `approvals_before_merge`) → **T10 RED, T11 green**; neutralize
ONLY the reset payload → **T11 RED, T10 green**; restore → **11/0 GREEN**.

**Fixtures updated:** `test-gitlab-ci-status-stderr-approvals.sh` (GET
`approval_rules` arm returns the array via `GLAB_GET_APPR_BODY`, new
`-X POST …/approvals` reset arm with `GLAB_POST_RESET_*` knobs, T2/T3 bodies →
array, T10/T11 added + registered); `tests/host-drivers/gitlab.test.sh`
(approval_rules GET mocks + reset POST mock); `tests/host-drivers/e2e-init-gitlab.test.sh`
(GET `approval_rules` arm, new reset POST arm + `MOCK_GL_RESET_POST_*` knobs,
`APPROVALS_JSON_ORG` → array).

### Scope note still recorded (NOT built)
- **Idempotency on re-run:** `POST …/approval_rules` creates a rule; unlike the
  old idempotent PUT, a second org-configure could create a duplicate/renamed
  rule. `host_configure_protection` runs once at Phase-2 init (rare re-runs),
  so low risk — noted for a durable follow-up.
