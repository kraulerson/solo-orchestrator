# The End-to-End Validation Walk — Acceptance Checklist

**Status:** SPEC. Nobody has walked this yet. This file is the contract a walker
executes; it is not a record of a walk.
**Derived:** 2026-07-11 — from the gate scripts first, the prose guides second.
**Walk date (planned):** 2026-07-12
**Companion:** [`CODE-VS-MANUAL.md`](./CODE-VS-MANUAL.md) — the bidirectional
doc-vs-code diff derived alongside this checklist. Every `UNENFORCED` item below
carries a `CM-*` cross-reference into it.

---

## Why this exists

This week's audits found gates that are **declared and blocking but hollow or
broken**, and none of the 100+ unit tests caught them — because the tests use
fixtures that supply what the real product fails to ship.

| Bug | The defect | Why every test passed |
|---|---|---|
| **BL-088** (Closed, PR #175) | `init.sh` never shipped `scripts/lib/tdd-classify.sh`, so the flagship TDD hard block **silently no-opped in every real project**. | Every BL-072 test `cp`'d the lib into its own fixture. The fixture hid the gap. |
| **BL-103** (Open) | The Phase 3→4 review gate is real and BLOCKING; its only remediation (`evaluation-prompts/Projects/run-reviews.sh`) dies at parse time on macOS bash 3.2 and probes filenames three of the six prompts never write — including **Red Team, a mandatory blocking reviewer**. | `tests/test-bl073-review-manifest-gate.sh` hand-writes its manifest and never runs the generator. |
| **BL-104** (Open) | Zero Phase-3 checklist steps **silently PASSES** the gate while 8-of-9 **BLOCKS**. An empty `{"reviews":[]}` manifest converts a blocking gate into a passing one. | No test asserts the *zero* case; the scoring inversion lives in the untested arm. |
| **BL-102** (Open) | Step 1.1.5 Market Signal is a declared DECISION GATE with **no template slot** to record it and **no script** that checks it. | Nothing to test — the gate does not exist in code. |

**The acceptance criterion for this checklist:** a walker following it faithfully
would have caught **all four**. See [§9 Would-it-have-caught-them](#9--would-it-have-caught-them-the-acceptance-criterion).

> ### ⚠️ Note added in proof — PR #187 merged; BL-103 and BL-104 are FIXED
>
> **Baseline: `main` @ `f2e30de`.** This checklist was first drafted against
> `3c75b9a`, where BL-102–BL-106 were all Open. **PR #187 has since merged**,
> fixing **BL-103** (the eval generator: bash-3.2 rewrite + slug parity) and
> **BL-104** (both scoring inversions — the zero-step arm now exists, marker
> **`# BL-104-P3-ZERO`**). It also closed two of this document's own findings:
> **D-3** (`init.sh` now creates `docs/eval-results/`) and **D-4**
> (`run-reviews.sh` is now mode `100755` and parses under bash 3.2).
>
> **This flips the walk's expected RESULTS. It does not change a single ASSERTION.**
>
> | Item | Was (bug reproduction) | Is now (regression assertion) |
> |---|---|---|
> | `P3-021` | Expect the generator to **die** on bash 3.2; expect it to probe `redteam-` | Expect it to **RUN**, and to emit a manifest containing **`redteam`**. |
> | `P3-019` | Expect `0` steps to **pass** and `8` to **block** (the inversion) | Expect **`0` steps to BLOCK** — i.e. expect the inversion to be **gone**. |
> | `P3-020` | Expect an empty manifest to **pass** where an absent one blocks | Expect both arms to behave **consistently**. |
>
> **The probes are byte-for-byte identical either way.** That is the strongest
> possible argument for this checklist's design: **an assertion that catches a bug
> is the same assertion that proves its fix holds.** Run all three regardless — and
> if the walk finds either bug still reproducing on `f2e30de`, **the fix is
> incomplete and that is a finding of the highest order.**
>
> ### 🔴 RETRACTION — my original headline finding (old D-1) was WRONG
>
> The first draft of this checklist led with *"Nothing invokes
> `check-phase-gate.sh`."* **That is false.** **All 30 of 30** scaffolded CI
> templates (`templates/pipelines/ci/{github,gitlab,bitbucket}/*.yml`) carry a
> **`Governance - Phase gate check`** step running `bash scripts/check-phase-gate.sh`
> on **both `push` and `pull_request` to `main`**. **The gate is genuinely wired
> in, in every generated project.**
>
> I reached the false conclusion from a **`head -20`-truncated grep** — the
> `templates/pipelines/` hits were on lines 21+. **This is precisely the failure
> mode this checklist exists to prevent:** I saw what I expected to see and stopped
> looking. It is why rule **R9** now exists. The narrow, true remnant is
> **`X-010`** (the *local* advance path doesn't consult the gate; CI catches it).
>
> **This retraction is good news, and it strengthens the walk:** every `BLOCKS`
> item below is genuinely blocking in a real project — not merely advisory.

**The single lesson encoded throughout:** a positive assertion is worthless on
its own. `[OK] gate passed` is emitted identically by a gate that works and a
gate that is dead. **Only the negative assertion — break it, and prove it
screams — distinguishes them.** Every `BLOCKS`-class item below therefore
carries a mandatory ⚠️ NEGATIVE assertion.

---

## 1 · §0 Setup

### 1.1 The project being built

A **minimal single-user note-keeper web app**, chosen because it activates every
validation surface with a real target:

| Property | Why it is in the walk |
|---|---|
| Login (username + password) | Auth threat surface → STRIDE threat model has real rows; Semgrep/ZAP have real targets |
| SQLite persistence | Injection + data-at-rest → data classification is genuinely non-`public` → the ZDR gate fires for real |
| Real npm dependencies | License scanner + Snyk have real targets (BL-086 has something to deny) |
| A UI | UAT + accessibility (Lighthouse) audits have real targets |
| A deployable artifact | Release, rollback, and monitoring steps have real targets |

### 1.2 The configuration (Karl-approved)

```
--platform web --language typescript --deployment organizational --track standard
--gov-mode production        # ← REQUIRED; see S-004. NOT a POC mode.
```

**`--gov-mode production` is mandatory and is easy to get wrong.** `init.sh`
hard-refuses `--deployment organizational` with no `--gov-mode` (the
`"--gov-mode is required when --deployment=organizational"` fail arm), and
`--gov-mode private_poc` is rejected outright for organizational. `production`
maps to `POC_MODE=""` → `"poc_mode": null` in `phase-state.json`. **This is the
whole reason the walk can reach Phase 4** — any POC mode hard-blocks it.

This configuration activates the **maximum enforcement surface**:

| Surface | Activated by |
|---|---|
| Governance pre-conditions (6, pre-Phase 0) | `deployment=organizational` |
| Senior Technical Authority / App Owner / IT Security approvals | `deployment=organizational` |
| Self-approval detection | `deployment=organizational` |
| Market Signal (Step 1.1.5) | `track=standard` (Standard+) |
| Penetration test (with the IT-Security exemption path) | `track=standard` (Standard+; Full has no exemption) |
| Attorney review | legal docs present (condition-gated, not track-gated) |
| **Review-manifest gate — BLOCKING FAIL** | `review_gate_enforced:true` (stamped by init) **AND** `track ∈ {standard,full}` |
| **TDD hard block — non-bypassable** | `deployment=organizational` (`# BL-084-TIER-KEY`) |
| **BL-086 license deny — hard block** | `deployment=organizational` (`# BL-086-TIER`) |
| ZDR / data-classification gate | `data_classification != public` |
| Verified-remote push gate (BL-084) | `deployment=organizational` |

### 1.3 Setup items

---

**`S-001` — Framework repo is pristine and stays pristine**
- **What must happen:** The walk records `git -C <framework> rev-parse HEAD` and `git status --porcelain` before and after. They must be identical.
- **Class:** ARTIFACT · **Enforced?** UNENFORCED (walk discipline — no CM row; this is the walk's own invariant, not a product claim)
- **POSITIVE:** `git -C "$FW" rev-parse HEAD > /tmp/fw-head-before.txt; git -C "$FW" status --porcelain > /tmp/fw-status-before.txt` — and the same after the walk; `diff` both pairs → empty.
- **⚠️ NEGATIVE:** n/a (this is the walk's own invariant, not a product gate). If the diff is non-empty at any checkpoint, the walk is **VOID** — the experiment has been contaminated. Stop, restore, restart.
- **Evidence:** both `diff` outputs, empty.

---

**`S-002` — Hermetic temp project dir; no real remote, ever**
- **What must happen:** The project is scaffolded into `$(mktemp -d)`, never under the framework repo, and **no live remote is created**.
- **Class:** ARTIFACT · **Enforced?** BLOCKS at merge time for tests (`scripts/lint-no-live-remote-in-tests.sh`); for the walk it is **house rule**, unenforced.
- **POSITIVE:** `TOPTMP=$(mktemp -d "${TMPDIR:-/tmp}/solo-e2e-XXXXXX")`, project at `"$TOPTMP/notekeeper"`. The blessed hermetic pattern is `--no-remote-creation` — see `tests/test-scaffold-tdd-block-real.sh` (the `# Hermetic: mktemp, git identity set locally, GITHUB_BASE_REF unset, init.sh run with --no-remote-creation (the blessed no-live-remote path)` header) and `tests/edge-case-test-suite.sh` (`# BL-076: --no-remote-creation is baked in so this wrapper is hermetic`).
- **⚠️ NEGATIVE:** After the walk, `gh repo list --limit 200 | grep -i notekeeper` → **must be empty**. A live `gh repo create` leaked a real repo on 2026-07-06; this is the check that would have caught it.
- **Evidence:** the `mktemp -d` path; the empty `gh repo list` grep.

---

**`S-003` — Hermetic git identity; `GITHUB_BASE_REF` unset**
- **What must happen:** `git config user.email/user.name` set **locally in the project**, and `GITHUB_BASE_REF` unset before any fixture git op (house portability rule).
- **Class:** ARTIFACT · **Enforced?** UNENFORCED (house rule; `CLAUDE.md` § HOUSE RULES DIGEST)
- **POSITIVE:** `unset GITHUB_BASE_REF; git -C "$PROJ" config user.email e2e@walk.invalid; git -C "$PROJ" config user.name e2e-walker`
- **⚠️ NEGATIVE:** n/a (harness hygiene).
- **Evidence:** `git -C "$PROJ" config --local --list | grep user`.

---

**`S-004` — The exact `init.sh` invocation**
- **What must happen:** The real `init.sh` runs, non-interactively, and exits 0.
- **Class:** AUTOMATED · **Enforced?** BLOCKS (`init.sh` `fail` arms)
- **POSITIVE:**
  ```bash
  ( cd "$TOPTMP" && "$FW/init.sh" --non-interactive \
      --project notekeeper \
      --description "Minimal single-user note-keeper with login and SQLite persistence" \
      --platform web \
      --language typescript \
      --deployment organizational \
      --gov-mode production \
      --track standard \
      --git-host github \
      --visibility private \
      --project-dir "$TOPTMP/notekeeper" \
      --no-remote-creation ) > "$TOPTMP/init.out" 2> "$TOPTMP/init.err"; echo "rc=$?"
  ```
  Expect `rc=0`. **Paste the full `init.out` into the results file** — it is the single richest artifact of the walk (it is the only place the framework tells the operator what it just did).
- **⚠️ NEGATIVE:** Re-run **without** `--gov-mode` → must FAIL with `--gov-mode is required when --deployment=organizational`. Re-run with `--gov-mode private_poc` → must FAIL (`--gov-mode=private_poc is not valid for --deployment=organizational`). Both prove the tier-shape validator is live.
- **Evidence:** `init.out`, `init.err`, `rc`, plus both negative-probe outputs.

---

**`S-005` — Tool inventory: record what is REAL and what is MOCKED, before anything runs**
- **What must happen:** The walk records, up front, which of the framework's tool dependencies are actually installed. **This is load-bearing: most of the framework's gates degrade to a silent `[WARN] … skipped` when their tool is absent.** A walk that does not record the tool inventory cannot tell a passing gate from an absent one.
- **Class:** ARTIFACT · **Enforced?** UNENFORCED (declared only) → **CM-U-01** (*"gates degrade to a silent skip when their tool is absent, and no doc says so"*)
- **POSITIVE:** for each of `jq git gh gitleaks semgrep snyk docker license-checker node npm lighthouse`: `command -v <tool> && <tool> --version`. Record present/absent + version in a table. `jq` and `git` are **hard** dependencies (init.sh guards on them).
- **⚠️ NEGATIVE:** n/a (inventory).
- **Simulation note:** Tools the walk **MOCKS** (house pattern: `tests/host-drivers/mock-cli.sh` — a temp dir of stub CLIs prepended to `PATH`, each stub matching an arg-pattern and emitting a canned fixture + exit code):
  - **`snyk`** — a real run needs a Snyk-authenticated CLI (`snyk auth`). The walk puts a `snyk` stub on `PATH` emitting a fixture `snyk test --json` report. **A real run would additionally need to validate the report against Snyk's live schema and confirm the auth token is scoped to the org.**
  - **`docker`** (for the ZAP DAST arm, `# BL-070-ZAP-DISPATCH`) — a real run needs Docker running **and** `SOLO_ZAP_TARGET_URL` pointing at a live deployed instance. The walk stands up the note-keeper on `http://127.0.0.1:PORT` and sets `SOLO_ZAP_TARGET_URL` to it — **a local target, not a mock, wherever possible**; if Docker is unavailable, the ZAP arm is mocked and the item is `SIMULATED`. **A real run would additionally need the app deployed to a real staging environment reachable from the scanner.**
  - **`gh`** — mocked for any remote op; `--no-remote-creation` should mean none are attempted. If `gh` is invoked at all, that is a **finding**.
  - **Monitoring alert** (Step 4.3) — no real Sentry/UptimeRobot. See P4-014.
  Tools the walk uses **REAL** if installed: `jq`, `git`, `gitleaks`, `semgrep`, `node`/`npm`, `license-checker`. **Record honestly which were real.**
- **Evidence:** the tool table; the `PATH` used; the mock dir listing.

---

**`S-006` — The walk NEVER modifies the framework repo**
- **What must happen:** Stated as a rule, checked as S-001. No `git commit` in the framework. No edit to any framework file. **No "fix" applied mid-walk, ever** — a fix destroys the experiment.
- **Class:** ARTIFACT · **Enforced?** UNENFORCED (walk discipline)
- **POSITIVE:** S-001's before/after diff is empty.
- **⚠️ NEGATIVE:** n/a.
- **Evidence:** S-001.

---

## 2 · Walker rules

Drawn from `docs/step5-dogfood-walker-rubric.md` — the framework's own hard-won
lesson that **walkers self-grade too generously**. Read that file before walking.

### R1 — Default to `PARTIAL`, never to `PASS` (BL-062)
> When the declared behavior and the observed artifact disagree, the grade
> defaults to `PARTIAL` — never `PASS` — pending a doc-vs-product resolution.

Both a "the artifact is fine, the wording is just imprecise" reading and a "the
artifact is wrong" reading are *always available at grading time*. That is what
makes the lenient reading tempting. **Your job is to flag the disagreement, not
to adjudicate it.** Record both texts verbatim; grade `PARTIAL`; move on.

### R2 — Never mark `PASS` on an assertion you did not personally run
No inference. No "this obviously works." No "the test suite covers this." If you
did not run the command and read its output, the status is not `PASS`. The
**exact command** and the **exact output** go in the results file for every item.

### R3 — Never work around a blocker. Record it and STOP.
If the framework blocks you and there is **no documented path forward**, that is
a **HARD STOP**. Write it down. Do not improvise. Do not hand-write an artifact
the product was supposed to generate — *that is precisely the sin that hid
BL-103* (the BL-073 test hand-wrote its manifest and never ran the generator).

### R3a — The ONE narrow exception: a documented in-product escape hatch
The framework ships real, designed attestation hatches (`SOLO_REVIEWERS_ATTESTED`,
`SOLO_TDD_ATTESTED`, `SOLO_LICENSE_ATTESTED`, `SOIF_FORCE_STEP`, and the
`run-phase3-validation.sh --attest` path). Taking one of these is **not** a
workaround — it is using the product. But taking one **silently** would hide the
defect.

> **Protocol.** When the *primary* path is broken and a *documented* hatch is the
> only way forward:
> 1. Grade the primary-path item **FAIL** (not `BLOCKED`, not `PARTIAL` — the
>    remediation the framework named did not work).
> 2. File it in the findings table with the exact command and the exact error.
> 3. Take the hatch **exactly as documented**, changing nothing else.
> 4. Grade the item that consumed the hatch `BLOCKED → ATTESTED-CONTINUE` and
>    record the attestation payload as evidence.
> 5. Continue the walk.

**This exception is load-bearing and Karl should know it will be exercised.**
BL-103 is open: the review generator cannot run on this host. Under a strict
reading of R3 the walk would HARD STOP at the Phase 3→4 gate and every Phase-4
item would be `BLOCKED` — we would lose all Phase-4 coverage to a bug we already
know about. R3a preserves the coverage while recording the defect at full
severity. **If Karl prefers the strict reading, say so and the walk stops at
P3-041; Phase 4 then reports as `BLOCKED` in full.**

### R4 — Never fix the framework mid-walk
Not even a one-character fix. Not even an "obvious" one. The walk is measuring
*what a real operator hits*; patching the framework mid-walk destroys the only
measurement we are taking. Findings go in the results file, and fixes go in a
**later PR**.

### R5 — The generated project is the laboratory; the framework repo is not
Negative assertions **mutate the generated project** — delete an artifact, blank
a state key, stage a bad commit — then attempt to advance and assert the gate
fires. That is legitimate and required. **Always restore the project to its
pre-probe state before continuing** (`git -C "$PROJ" stash` / `git -C "$PROJ"
checkout -- <file>` / re-write the state key). Record the restore.

### R6 — `[WARN]` in `check-phase-gate.sh` is *cosmetic*. Read the increment.
The gate's exit predicate is `if [ $issues -eq 0 ]`. **Any `[WARN]` line that
also runs `issues=$((issues + 1))` BLOCKS the gate.** Several do. Never grade an
item on the `[WARN]`/`[FAIL]` label — grade it on the **exit code**. (This trap
is BL-104's third finding and has bitten the project twice.)

### R7 — Report the exit code, not the tally line
Suites print `Results: N passed, M failed`; gates print `[OK]`/`[WARN]`/`[FAIL]`.
**The reliable signal is the process exit code.** Capture `echo "rc=$?"` after
every command and paste it.

### R8 — `timeout`/`gtimeout` do not exist on this host
Wrapping a command in them yields a spurious `rc=127`, not a timeout. Do not use
them. If a command hangs, record it as a finding.

### R9 — Never conclude "X does not exist" from a truncated search
**This rule exists because the author of this checklist broke it.**

The first draft's headline finding was *"nothing invokes `check-phase-gate.sh`"* —
derived from a `grep -rn … | head -20`. The disproving hits were on lines 21+.
**All 30 scaffolded CI templates run the gate.** The finding was retracted (see the
Note added in proof).

> **A negative conclusion requires an un-truncated search.** Before writing *"zero
> hits"*, *"nothing does X"*, or *"never shipped"*:
> 1. Re-run the search with **no `head`, no `tail`, no `| head -N`**.
> 2. Prefer `grep -c` or `grep -l | wc -l` — a **count** cannot be silently truncated.
> 3. Paste the count, not a sampled list.
>
> This is the same failure as grading a gate `PASS` from a positive assertion
> alone: **you saw what you expected and stopped looking.** R2 protects the
> positive direction; R9 protects the negative one. **The negative assertions in
> this checklist are its load-bearing half — they are worthless if reached
> carelessly.**

---

## 3 · Pre-walk discrepancies

**Findings collected while deriving this checklist — before the walk has run.**
Every one was confirmed by a grep against the code. Full detail, with fixes, is
in [`CODE-VS-MANUAL.md`](./CODE-VS-MANUAL.md); this is the short list the walker
must know *going in*, because several will change what the walker sees.

| # | Discrepancy | Evidence | Impact on the walk |
|---|---|---|---|
| ~~**D-1**~~ | 🔴 **RETRACTED — I WAS WRONG.** The original claim was *"nothing invokes `check-phase-gate.sh`."* **False.** `git grep -l 'bash scripts/check-phase-gate.sh' -- templates/pipelines/ \| wc -l` → **30 of 30** CI templates run it, in a `Governance - Phase gate check` step, on **`push` AND `pull_request` to `main`**, hard-`::error::`ing if the script is missing. **The gate is genuinely CI-enforced in every generated project.** I reached the false version from a `head -20`-truncated grep (see rule **R9**). | `git grep -c`, un-truncated | **This is good news and it strengthens the walk:** every `BLOCKS` item here is genuinely blocking. The narrow surviving remnant is **`X-010`**: the *local* advance path (`--start-phaseN`) still doesn't consult the gate — but **CI catches it at push**, so it is a defense-in-depth gap, not a hollow gate. → **CM-U-12** |
| **D-2** | **8 of 25 `templates/generated/*.tmpl` are never shipped** — and **5 of them are demanded by a gate**: `security.tmpl` (the `# P4-013: SECURITY.md check` blocks without it), `threat-model-validation.tmpl` (the `threat-model` scanner needs the report), `rollback-test.tmpl` (`phase4_release:rollback_tested` arm), `handoff-test-results.tmpl` (`phase4_release:handoff_tested` arm), and `security-audit-findings.tmpl` — which `process-checklist.sh` **names by path in its own failure message** (`Create a findings file using templates/generated/security-audit-findings.tmpl`) while `init.sh` never ships it. | `for f in templates/generated/*.tmpl; do grep -q "$(basename $f)" init.sh \|\| echo "NOT SHIPPED: $f"; done` | **NEW — not filed.** Pure BL-088 class (a shipped instruction pointing at an unshipped dependency), in artifact form. The walk will hit this at P2-018, P3-012, P3-034, P4-005, P4-016. |
| **D-3** ✅ **FIXED by PR #187** — `init.sh` now creates it (3 hits; re-verified on `f2e30de`). Historical record below. | ~~**`docs/eval-results/` was never created by `init.sh`.** `grep -n 'eval-results' init.sh` → **zero hits**. The review manifest — whose absence hard-FAILs the Phase 3→4 gate — must live in a directory the scaffold does not create. | grep above; `mkdir -p docs/...` line in init.sh omits it | Already filed as part of **BL-105**. Walker will hit it at P3-039. |
| **D-4** ✅ **FIXED by PR #187** — now mode `100755`, and it parses under bash 3.2 (re-verified on `f2e30de`). Historical record below. | ~~**`run-reviews.sh` was mode `644` — not executable** — and `init.sh` ships it with `cp -r` (mode-preserving) and **never `chmod +x`**. The gate's own failure message tells the operator to *"Run reviews: evaluation-prompts/Projects/run-reviews.sh"*. | `ls -l evaluation-prompts/Projects/run-reviews.sh` → `-rw-r--r--`; `grep -n 'chmod.*run-reviews' init.sh` → zero hits | **NEW — a third defect on top of BL-103's two.** Even on a bash-5 host where the `declare -A` parse succeeds, the named remediation is not executable. Walker hits it at P3-037. |
| **D-5** | **Phase 3 step-count drift: code has 9, the guide names 7.** `PHASE3_STEPS` in `process-checklist.sh` = `integration_testing security_hardening chaos_testing accessibility_audit performance_audit contract_testing results_archived` **`pre_launch_preparation` `legal_review`**. `grep -o 'phase3_validation:[a-z_]*' docs/builders-guide.md \| sort -u` returns only the **first seven**. Meanwhile the gate's P3-007 cross-check passes at `>= 9`. | greps above; the `p3_steps_done` block in `check-phase-gate.sh` | **A walker who follows the builders-guide exactly completes 7/9 and the gate BLOCKS them with "7/9 steps"** — with no doc anywhere naming the two missing step IDs. **This is a live, reproducible, guide-induced blocker.** NEW. Walker hits it at P3-035/P3-036. |
| **D-6** | **Phase 4 step-count drift: code has 6, the guide names 5.** `PHASE4_STEPS` adds **`handoff_tested`**, which the builders-guide never names as a step ID. `--finalize-phase 4` requires all six. | greps above | Same class as D-5. NEW. Walker hits it at P4-016. |
| **D-7** | **`data_classification` is not in `phase-state.json`** — it lives in `.claude/process-state.json::phase1_artifacts.data_classification`, and **`init.sh` never seeds it** (`grep -c 'phase1_artifacts' init.sh` → `0`). The Phase 1→2 ZDR gate FAILs until `intake-wizard.sh` (or `reconfigure-project.sh --field data_classification`) writes it. | grep above; the ZDR block in `check-phase-gate.sh` | Not a bug — but a **sequencing trap**. The walk must run the intake wizard before attempting 1→2, or the ZDR gate fires "correctly" for the wrong reason. P1-018. |
| **D-8** | **`HANDOFF.md` and `docs/INCIDENT_RESPONSE.md` are gate-checked at Phase 3→4 — but the builders-guide tells you to author them in Steps 4.5 and 4.1.5, i.e. *inside Phase 4*.** The artifact loop `for artifact in "HANDOFF.md" "docs/INCIDENT_RESPONSE.md" "sbom.json"` runs at `current_phase >= 3`. | the artifact loop in `check-phase-gate.sh`; guide Steps 4.1.5 / 4.5 | **Ordering trap.** Following the guide in order makes the 3→4 gate unpassable. Walker hits it at P3-042. NEW (adjacent to BL-105). |
| **D-9** | **The commit-msg hook (the TDD hard block) is only installed for languages with a non-empty `test_pattern`.** `install_tdd_commit_msg_hook` is called only when `[ -n "$test_pattern" ] && [ -n "$src_ext" ]`; the `case "$LANGUAGE"` arm sets `test_pattern=""` for **rust** and for **`*)` (other)**. | the `case "$LANGUAGE"` block preceding the `HOOKEOF` heredoc in `init.sh` | Our walk is `typescript` → hook **IS** installed. But **a Rust organizational project silently gets no TDD gate at all** — the BL-088 failure mode, still live, on a different axis. NEW. Out of scope for this walk (see §8); filed in CODE-VS-MANUAL. |
| **D-10** | **Upgrade-command drift.** `docs/builders-guide.md` § Process Right-Sizing says `scripts/intake-wizard.sh --upgrade-to-production`; `docs/governance-framework.md` § V says `scripts/upgrade-project.sh --to-production`. The gate's own message says `bash scripts/upgrade-project.sh --to-production`. **The code wins: `upgrade-project.sh`.** | the POC-mode block in `check-phase-gate.sh` | Cosmetic for this walk (we are not in a POC mode) but a real doc bug. |
| **D-11** | **`[WARN]` that blocks.** In `check-phase-gate.sh` the exit predicate is `if [ $issues -eq 0 ]`, and many `[WARN]` arms run `issues=$((issues + 1))`. `SECURITY.md`, `HANDOFF.md`, `INCIDENT_RESPONSE.md`, `sbom.json`, and the "7/9 steps" warning **all print `[WARN]` and all BLOCK.** | the `issues=$((issues + 1))` lines adjacent to each `[WARN]` | Already filed (BL-104 finding 3). Encoded as walker rule **R6**. |
| **D-12** | **`SOIF_PHASE_GATES=warn` downgrades the ENTIRE phase gate to non-blocking** (`exit 0` on any number of issues). It is a single env var that disables every gate in `check-phase-gate.sh` at once. | the final `if [ "${SOIF_PHASE_GATES:-}" = "warn" ]` block | The walk must probe whether this is documented anywhere an operator would find it (X-016). |
| **D-13** | 🔴 **`SOIF_FORCE_STEP` appears in NO operator-facing document.** It force-completes a `process-checklist.sh` step past its artifact check. Meanwhile the generated `CLAUDE.md` (from `claude-md.tmpl` § Construction Rules) promises the downstream agent: *"**Commits are blocked until all steps are completed in order.**"* | `grep -rln 'SOIF_FORCE_STEP' README.md docs/user-guide.md docs/builders-guide.md docs/governance-framework.md docs/security-scan-guide.md workflow.html CONTRIBUTING.md templates/generated/claude-md.tmpl` → **0**. ⚠️ **Be precise:** it is **not** absent from the repo — 4 hits exist under `docs/`, **all in `docs/superpowers/{plans,specs}/archive/`** (archived internal design specs). 3 hits in `scripts/`. | **The most consequential bypass an operator will never read about.** It voids the central promise the kickoff CLAUDE.md makes. Mitigated *only* by its TTY guard (X-014) — which is why X-014 matters. NEW. |
| **D-14** | 🔴 **`workflow.html` contradicts itself AND the code on the review-manifest gate.** One bullet: *"`check-phase-gate.sh` **only WARNs (not FAILs)** when `docs/eval-results/review-manifest.json` is missing."* Another, two bullets later, lists the manifest as a **Required artifact**. The code (`# BL-073-ESCALATE`) **FAILs**. It *also* calls the TDD check *"warning-only"* — contradicting README's *"hard-blocks"* — i.e. it is stale on the pre-BL-072-C2 behavior. **And it cites `check-phase-gate.sh:901–1056`, violating the repo's own CITATION RULE** (and the range has already drifted). | the two `workflow.html` bullets vs `# BL-073-ESCALATE` | `workflow.html` is the repo's most detailed enforcement spec **and is stale on two enforcement points.** Treat every line-number claim in it as expired. NEW. |
| **D-15** | 🔴 **2 of the 5 gate-blocking scanners have ZERO coverage in the guide named after them.** `grep -ci 'zap\|dast' docs/security-scan-guide.md` → **0**; same for `threat-model`. And **`SOLO_ZAP_TARGET_URL` is undocumented everywhere.** So `zap-dast` — a scanner that **hard-blocks Phase 3→4** — cannot be pointed at your app using any shipped documentation. | the greps; `# BL-070-ZAP-DISPATCH` | The walker will hit this at P3-015: to run the DAST scan at all, they must read the *source* to discover the env var. NEW. |
| **D-16** | ⚠️ **NON-FINDING, recorded to prevent a false alarm.** `grep -c 'PRODUCT_MANIFESTO' init.sh` → **0**. The scaffold does **not** create `PRODUCT_MANIFESTO.md`; it ships `product-manifesto.tmpl` to `templates/generated/`. **This is correct by design** — the manifesto is the Step 0.4 *deliverable*, authored in Phase 0, not a scaffold artifact. The Phase 0→1 gate's `validate_manifesto_content` therefore FAILs on a fresh project **for the right reason**. | the grep; guide Step 0.4 | **Do not file this.** It looks like a BL-088-class hole and is not one. Recorded here so the walker recognizes it on sight. |

---

## 4 · Cross-cutting items (`X-*`)

These are not phase-scoped. Several are the highest-value items in the document.

---

**`X-001` — The scaffold ships every sourced dependency (the BL-088 catch)**
- **Phase/Step:** Setup / post-init
- **What must happen:** Every `scripts/lib/*.sh` a shipped gate script sources must itself be shipped.
- **Class:** AUTOMATED · **Enforced?** BLOCKS at framework-merge time (`tests/test-scaffold-source-closure.sh`, marker `# BL-088-CLOSURE`); **UNENFORCED at scaffold time** (nothing re-checks in the generated project).
- **POSITIVE:** In the generated project: `ls "$PROJ/scripts/lib/"` → must contain **11** files, including `tdd-classify.sh`, `phase2-state.sh`, `cdf-refresh.sh`. And `test -x "$PROJ/scripts/run-phase3-validation.sh"` → true.
- **⚠️ NEGATIVE (the BL-088 reproduction):** `mv "$PROJ/scripts/lib/tdd-classify.sh" /tmp/`, then run X-004's test-less `feat:` commit. **It must still BLOCK.** — **It will NOT.** `tdd_terminal_enforce` opens with `command -v _tdd_triggers >/dev/null 2>&1 || return 0   # classifier absent -> no-op (safe)`, so the gate returns 0 = ALLOW. **This is BL-088 reproduced on demand.** Record `ALLOWED` as the observed behavior, restore the lib, re-run, confirm `BLOCKED`. This item is the reason the walk exists: it proves the gate is *load-bearing on a file the scaffold could stop shipping at any time, silently.*
- **Evidence:** the `ls` (11 files); the commit log showing `BLOCKED` with the lib present and `ALLOWED` with it removed; the restore.

---

**`X-002` — `.git/hooks/pre-commit` is installed and is self-contained**
- **Class:** ARTIFACT · **Enforced?** BLOCKS (the hook `exit $FAILED`)
- **POSITIVE:** `test -x "$PROJ/.git/hooks/pre-commit"`; `grep -c 'gitleaks\|semgrep\|Schema Migration' "$PROJ/.git/hooks/pre-commit"` ≥ 3. Note it invokes **no framework script** — it is a self-contained heredoc.
- **⚠️ NEGATIVE:** covered by X-005/X-006/X-007.
- **Evidence:** the hook file, verbatim.

---

**`X-003` — `.git/hooks/commit-msg` is installed and delegates to the two message gates**
- **Class:** ARTIFACT · **Enforced?** BLOCKS
- **POSITIVE:** `grep -q 'tdd-only' "$PROJ/.git/hooks/commit-msg"` → true; body is `scripts/pre-commit-gate.sh --terminal-mode --tdd-only || exit 1`, wrapped in the idempotency markers `# >>> SOIF BL-072 TDD gate (commit-msg) — managed by init.sh`.
- **⚠️ NEGATIVE:** `mv "$PROJ/.git/hooks/commit-msg" /tmp/` → the test-less `feat:` commit is **ALLOWED**. Restore → **BLOCKED**. Proves the hook, not something else, is the enforcement point.
- **Note (D-9):** this hook is **only installed when the language has a test pattern**. `typescript` qualifies. **Rust and `other` do not** — those projects get no TDD gate. Not walked here; see §8.
- **Evidence:** the hook file; both commit attempts.

---

**`X-004` — The TDD hard block fires on a real, non-bypassable scaffold (BL-072 C2)**
- **Phase/Step:** Phase 2 / commit surface
- **What must happen:** A `feat:` commit that stages implementation with **no** test is **BLOCKED**, because `deployment=organizational` is a NON-bypassable tier.
- **Class:** AUTOMATED · **Enforced?** **BLOCKS** — `tdd_terminal_enforce` in `pre-commit-gate.sh`, markers `# BL-072-TDD-DETECT` (trigger) and `# BL-072-TDD-ENFORCE` (block). Tier predicate: `_bl072_tier_bypassable`, marker `# BL-084-TIER-KEY`.
- **POSITIVE:**
  ```bash
  cd "$PROJ" && mkdir -p src && \
    printf 'export const add = (a: number, b: number): number => a + b;\n' > src/widget.ts && \
    git add src/widget.ts && git commit -m "feat: add widget without a test"; echo "rc=$?"
  ```
  Expect **`rc=1`** and stderr containing `[FAIL] BL-072 TDD ordering:` and `Tier is NON-bypassable (sponsored POC / production) — test-first ordering is ENFORCED.`
- **⚠️ NEGATIVE (three arms — all required):**
  1. **Gate is alive:** the above must exit **non-zero**. (If it exits 0, the flagship gate is dead — that is BL-088's exact signature.)
  2. **Gate is tier-keyed:** `jq '.deployment="personal" | .poc_mode=null' phase-state.json` → re-attempt → must be **ALLOWED** with `[WARN] … Tier is BYPASSABLE`, and a row appended to `.claude/tdd-warn-ledger.jsonl` with `"status":"bypassed"`. **Restore `organizational`.**
  3. **Gate is not a paper tiger:** add a matching `src/widget.test.ts` → commit must **PASS**. (A gate that blocks everything is as broken as one that blocks nothing.)
- **Evidence:** all three commit logs with `rc=`; the ledger row; the restored `phase-state.json`.

---

**`X-005` — The TDD attestation hatch RECORDS, it does not silence**
- **Class:** AUTOMATED · **Enforced?** BLOCKS-with-hatch (`tdd_record_attestation`)
- **POSITIVE:** `SOLO_TDD_ATTESTED=1 SOLO_TDD_REASON="walk probe" git commit -m "feat: attested"` → **ALLOWED**, and `jq '.tdd_attestations' .claude/process-state.json` shows a new entry carrying the reason.
- **⚠️ NEGATIVE:** `SOLO_TDD_ATTESTED=1` with **no** `SOLO_TDD_REASON` → the code defaults the reason to `unspecified - attested via SOLO_TDD_ATTESTED` and **still allows**. **Assert whether an empty-reason attestation is accepted.** If it is, that is a finding (the sibling BL-070/BL-073 attestation paths both *reject* whitespace-only reasons — this one does not appear to). Then: make `.claude/process-state.json` unwritable (`chmod 0444`) and retry the attested commit → must **BLOCK** with `an attested escape must be durably logged` (proving the LOUD-failure arm).
- **Evidence:** the attestation JSON; the read-only-file block message.

---

**`X-006` — The `gitleaks` arm of the pre-commit hook: does a secret actually get blocked?**
- **Class:** AUTOMATED / INFRA · **Enforced?** BLOCKS **only if `gitleaks` is installed**; otherwise `[WARN] gitleaks not found — secret detection skipped.` and the commit proceeds.
- **POSITIVE:** stage a file containing a plausible secret (e.g. an AWS-shaped key) → commit → expect `[BLOCKED] gitleaks detected secrets in staged files.` and `rc != 0`.
- **⚠️ NEGATIVE (the hollow-gate probe):** temporarily shadow `gitleaks` off `PATH` (`PATH=/usr/bin:/bin git commit …`) → the same secret **commits clean**, with only a `[WARN]`. **Record this.** The framework's secret gate is *entirely contingent on a tool it does not install and does not hard-require.* If `gitleaks` is absent on the walk host, this item is `SIMULATED` and the finding is: **an organizational production project ships with secret-scanning silently off.**
- **Simulation note:** If `gitleaks` is not installed, do **not** install it — that changes the measurement. Record `SIMULATED`, note that a real run would need `brew install gitleaks`, and record that the framework never checks for it at a blocking severity.
- **Evidence:** both commit attempts, verbatim.

---

**`X-007` — The `semgrep` arm: same probe**
- **Class:** AUTOMATED / INFRA · **Enforced?** BLOCKS only if `semgrep` is installed; else `[WARN] semgrep not found — pre-commit SAST skipped.`
- **POSITIVE:** stage a file with an OWASP-Top-Ten-detectable flaw (e.g. a raw string-concatenated SQL query — which the note-keeper's SQLite layer makes natural) → commit → `[BLOCKED] Semgrep detected security issues in staged files.`
- **⚠️ NEGATIVE:** shadow `semgrep` off `PATH` → the same flaw commits clean. Record.
- **Evidence:** both attempts.

---

**`X-008` — The BL-006 Build-Loop commit-message gate (BL-010 surface)**
- **Class:** AUTOMATED · **Enforced?** **BLOCKS** — `bl006_terminal_enforce` in `pre-commit-gate.sh` (marker `# BL-010-COMMITMSG-BL006`), delegating to `process-checklist.sh --check-commit-message`. **Phase-gated: only fires at `current_phase >= 2`.**
- **POSITIVE:** In Phase 2, with **no** active Build Loop, attempt `git commit -m "feat: something"` (with a test, so BL-072 does not fire) → must **BLOCK**, directing you to `scripts/process-checklist.sh --start-feature`.
- **⚠️ NEGATIVE (three arms):**
  1. `jq '.current_phase=1' .claude/phase-state.json` → the same `feat:` commit is **ALLOWED** (proves the phase gate). Restore to 2.
  2. A `chore:`-prefixed commit with the same staged files → **ALLOWED** (proves the feat-prefix classifier is not blocking everything).
  3. Open a Build Loop, complete `tests_written`→`implemented`, then commit `feat:` → **ALLOWED**.
- **Evidence:** all four commit logs.

---

**`X-009` — `SKIP_LINT=1` and `--no-verify`: the un-gated bypasses**
- **Class:** AUTOMATED · **Enforced?** N/A — these **are** the bypasses.
- **POSITIVE:** n/a.
- **⚠️ NEGATIVE (probe, do not use as a workaround):** `git commit --no-verify -m "feat: bypass"` → does it commit? Is anything recorded to `.claude/bypass-audit.json`? The terminal-mode block advertises *"To bypass anyway (recorded in `.claude/bypass-audit.json`): git commit --no-verify"* — **but `--no-verify` skips the hook entirely, so the hook cannot record its own bypass.** Assert whether the audit row actually appears. **If the file has no row, the framework is advertising an audit trail it does not produce.** Restore (`git reset --hard`) immediately.
- **Evidence:** the commit; `cat .claude/bypass-audit.json` before and after.

---

**`X-010` — Is the gate an INTERLOCK or only a DETECTOR? (Corrected — see the retraction.)**
- **Phase/Step:** all
- **What must happen:** Establish, empirically, **where** `check-phase-gate.sh` is forced to run — and where it is not.
- **Class:** AUTOMATED · **Enforced?** **BLOCKS in CI** → **CM-A-13**. The *local* advance path is un-gated → **CM-U-12**.
- ⚠️ **This item previously claimed "nothing runs the gate." That was WRONG and has been retracted** (see the Note added in proof, and rule **R9**). The corrected item is narrower — and the corrected answer is largely *good news*.
- **POSITIVE (assert the gate IS wired in — un-truncated, per R9):**
  ```bash
  git grep -l 'bash scripts/check-phase-gate.sh' -- templates/pipelines/ | wc -l   # expect 30
  ```
  and in the **generated project**: `grep -n -A4 'Governance - Phase gate check' .github/workflows/ci.yml` → the step exists, runs `bash scripts/check-phase-gate.sh`, hard-`::error::`s if the script is missing, and the workflow triggers on **`push`** *and* **`pull_request`** to `main`. **Paste it.** This is the single most important *positive* result in the walk: it means every `BLOCKS` item in this checklist is genuinely blocking in a real project.
- **⚠️ NEGATIVE (the surviving, narrow gap — CM-U-12):** From a state where the Phase 3→4 gate is **known to FAIL**, run:
  ```bash
  bash scripts/process-checklist.sh --start-phase4; echo "rc=$?"
  jq '.current_phase' .claude/phase-state.json
  ```
  **Expected per the code:** `start_phase4()` checks **only** `poc_mode`, then calls `_set_current_phase_min 4` — it **never** consults `check-phase-gate.sh` (`grep -c 'check-phase-gate'` inside the function → **0**). So `current_phase` becomes **4** locally with a failing gate. Assert it. Then run `bash scripts/check-phase-gate.sh`, show it FAILs, and **then push and show CI catch it.**
  **The finding is the asymmetry, not a hole:** the gate is an **interlock at push time** and only a **detector locally**. An operator can do a day's work past a gate that was failing all along, and only learn at push. Contrast `start_phase3()`, which **does** consult a gate (`test-gate.sh --check-phase-gate`) — **the pattern already exists in the same file.**
- **Simulation note:** the CI half needs a remote. Use the local bare repo from `P1-012` plus `act` if available; otherwise assert the CI *template* statically (the 30/30 grep) and mark the runtime half `SIMULATED`. **A real run would push to a real remote and watch the gate job fail.**
- **Evidence:** the `30` count; the generated `ci.yml` step verbatim; the `--start-phase4` advance with a failing gate; the after-the-fact gate FAIL.

---

**`X-011` — `verify-install.sh` on the fresh scaffold**
- **Class:** AUTOMATED · **Enforced?** BLOCKS (non-zero on missing required files)
- **POSITIVE:** `bash scripts/verify-install.sh; echo "rc=$?"` in the fresh project → expect `rc=0` and no MANUAL/FIXABLE entries. (`init.sh` runs `verify-install.sh --auto-fix` at the end of scaffolding, so a fresh project should be clean.)
- **⚠️ NEGATIVE:** `rm scripts/lib/tdd-classify.sh` → `verify-install.sh` must report it FIXABLE; `--auto-fix` must restore it. (This is the BL-088 healing path.)
- **Evidence:** both runs.

---

**`X-012` — `validate.sh` on the fresh scaffold**
- **Class:** AUTOMATED · **Enforced?** WARNS (counts errors/warnings)
- **POSITIVE:** `bash scripts/validate.sh; echo "rc=$?"` → record the full output. Expect warnings on an un-filled project (that is correct behavior).
- **⚠️ NEGATIVE:** n/a (advisory).
- **Note:** `validate.sh::check_competency` exists but **is never invoked by any gate, hook, or CI** (BL-105). Assert this: `grep -rn 'validate.sh' scripts/ .github/ templates/ init.sh` → is `validate.sh` itself ever invoked automatically? Record. → **CM-H-06**
- **Evidence:** the run; the invocation grep.

---

**`X-013` — `lint-review-manifest.sh` schema lint**
- **Class:** AUTOMATED · **Enforced?** BLOCKS (exit 1 on schema violation) — but see the negative.
- **POSITIVE:** After the manifest exists, `bash scripts/lint-review-manifest.sh; echo "rc=$?"` → `rc=0`.
- **⚠️ NEGATIVE (two arms):**
  1. Write `{"reviews":[{"reviewer":"security"}]}` (missing required `status` + `artifact`) → must exit **1**.
  2. **The gap probe:** with **no manifest at all**, the linter exits **0** ("nothing to lint"). Confirm. That is by design (the header says so) but it means **the linter can never catch an absent manifest** — only the phase gate can. Record the division of labor.
- **Evidence:** both runs.

---

**`X-014` — `SOIF_FORCE_STEP` requires a TTY (agent-bypass block)**
- **Class:** AUTOMATED · **Enforced?** BLOCKS non-interactively
- **POSITIVE:** For any step with a failing artifact check, `SOIF_FORCE_STEP=true bash scripts/process-checklist.sh --complete-step <p>:<s> < /dev/null` → must **FAIL** with `SOIF_FORCE_STEP requires interactive terminal. The Orchestrator must run this directly.`
- **⚠️ NEGATIVE:** This *is* the negative — it proves an agent cannot force-complete a step. Confirm the agent path is genuinely closed.
- **Evidence:** the run.

---

**`X-015` — `--reset` / `--reset-all` require a TTY**
- **Class:** AUTOMATED · **Enforced?** BLOCKS non-interactively
- **POSITIVE:** `bash scripts/process-checklist.sh --reset build_loop < /dev/null` → must FAIL with `Reset requires interactive authorization.`
- **⚠️ NEGATIVE:** as above.
- **Evidence:** the run.

---

**`X-016` — `SOIF_PHASE_GATES=warn` disables every phase gate at once**
- **Class:** AUTOMATED · **Enforced?** N/A — this is the master bypass.
- **POSITIVE:** n/a.
- **⚠️ NEGATIVE (probe):** From a state where `check-phase-gate.sh` FAILs, run `SOIF_PHASE_GATES=warn bash scripts/check-phase-gate.sh; echo "rc=$?"` → expect **`rc=0`** with `(warn mode — not blocking)`. **Then search every user-facing doc for the string `SOIF_PHASE_GATES`.** If it is not documented, an operator cannot knowingly consent to it — and an agent that reads only the code *can*. Record. → **CM-U-06**
- **Evidence:** the run; the doc grep.

---

**`X-017` — The full bypass/attestation inventory is recorded**
- **Class:** ARTIFACT · **Enforced?** UNENFORCED → **CM-U-06**
- **What must happen:** The walk records, for each of the **9** escape hatches, (a) does it work, (b) is the use recorded to an audit trail, (c) is it documented anywhere an operator would find it.
- **POSITIVE:** Fill this table:

  | Hatch | Works? | Recorded to | Documented in a user-facing doc? |
  |---|---|---|---|
  | `SOLO_TDD_ATTESTED` + `SOLO_TDD_REASON` | | `.claude/process-state.json::tdd_attestations[]` | |
  | `SOLO_REVIEWERS_ATTESTED` + `_REASON` | | `.claude/process-state.json::phase3.attestations.reviewers` | |
  | `SOLO_LICENSE_ATTESTED` + `SOLO_LICENSE_REASON` | | `.claude/phase-state.json::phase3.license_exceptions[]` | |
  | `run-phase3-validation.sh --attest` | | `.claude/phase-state.json::phase3.attestations.<scanner>` | |
  | `SOIF_FORCE_STEP=true` | | `.claude/process-audit.log` | |
  | `SOIF_PHASE_GATES=warn` | | **nothing** | |
  | `SKIP_LINT=1` | | **nothing** | |
  | `SOLO_PHASE3_GATE_NOAUTORUN=1` | | **nothing** | |
  | `git commit --no-verify` | | `.claude/bypass-audit.json`? (X-009 tests this claim) | |

  The three hatches that record **nothing** are the interesting ones.
- **⚠️ NEGATIVE:** n/a (inventory).
- **Evidence:** the completed table + the `grep -rn` over `docs/ README.md` for each var name.

---

**`X-018` — 🔴 `SOIF_FORCE_STEP` is undocumented, and it voids the promise the kickoff `CLAUDE.md` makes**
- **Class:** AUTOMATED · **Enforced?** N/A — this is a bypass. → **CM-U-03**
- **What must happen:** Establish that the framework's most consequential process bypass is **invisible to the operator and to their AI**.
- **POSITIVE:** n/a.
- **⚠️ NEGATIVE (the doc-gap probe — state it precisely; the sloppy version is refutable):**
  1. `grep -rln 'SOIF_FORCE_STEP' README.md docs/user-guide.md docs/builders-guide.md docs/governance-framework.md docs/security-scan-guide.md workflow.html CONTRIBUTING.md templates/generated/claude-md.tmpl` → **assert ZERO hits.** ⚠️ Do **not** claim it is absent from the repo — `grep -rln 'SOIF_FORCE_STEP' docs/` returns **4** hits, all under `docs/superpowers/{plans,specs}/archive/` (archived internal design specs, which no operator or downstream agent is told to read). The precise claim is: **it appears in no operator-facing document.**
  2. `grep -rn 'SOIF_FORCE_STEP' scripts/` → **assert it exists** (3 hits) and force-completes a `process-checklist.sh` step past its artifact check.
  3. Read the **generated project's** `CLAUDE.md` (from `claude-md.tmpl` § Construction Rules): it tells the downstream agent **"Commits are blocked until all steps are completed in order."** — an unqualified promise, with no mention that a single env var lifts it.
  4. Confirm the only thing standing between an agent and this bypass is the TTY guard (X-014). **Assert the TTY guard actually holds** — if it does not, an AI agent can silently force-complete every artifact-gated step in the framework.
- **Why it matters more than the other hatches:** every *other* hatch (`SOLO_TDD_ATTESTED`, `SOLO_LICENSE_ATTESTED`, `SOLO_REVIEWERS_ATTESTED`, `--attest`) **records** its use to a state file. `SOIF_FORCE_STEP` records to `.claude/process-audit.log` — verify that it does — but it is documented **nowhere**, so an operator cannot knowingly consent to it and cannot audit for it if they do not know its name.
- **Evidence:** both greps; the verbatim `claude-md.tmpl` promise; the TTY-guard result; the `process-audit.log` row (or its absence).

---

## 5 · Phase 0 — Product Discovery & Logic Mapping

### 5.1 Pre-Phase 0 — organizational governance pre-conditions

The builders-guide carries **one prose line** ("verify that all pre-Phase 0
pre-conditions are recorded in `APPROVAL_LOG.md`"); the actual list of **six** is
in `docs/governance-framework.md` § XIV.

---

**`P0-001` — The six pre-Phase-0 pre-conditions are present in `APPROVAL_LOG.md`**
- **What must happen:** For `deployment=organizational`, six named pre-conditions (insurance clearance; AI deployment path approved by IT Security; liability entity designated; project sponsor assigned; backup maintainer designated; ITSM registration) each carry a dated approval row.
- **Class:** HUMAN (SIMULATED) · **Enforced?** **WARNS — and the WARN BLOCKS** (see R6). The pre-condition block emits `[WARN] Pre-Phase 0: Organizational deployment — only $local_precond_count pre-condition date(s) recorded (6 required)` and runs `issues=$((issues + 1))`.
- **POSITIVE:** `grep -A30 'Pre-Phase 0' APPROVAL_LOG.md` shows six rows with populated Date columns; `bash scripts/check-phase-gate.sh` shows the pre-condition `[OK]`.
- **⚠️ NEGATIVE:** Blank one Date cell → re-run → must emit the named-precondition WARN **and** `issues` must increment (verify by `echo "rc=$?"` → non-zero). Restore.
- **Simulation note:** The agent plays **IT Security** and the **Orchestrator**. It writes six dated rows with `[SIMULATED]` in the Notes column. **A real run would additionally require:** a real insurance-clearance letter reference; a real IT-Security sign-off on the AI deployment path (a named human, not a role); a named legal entity accepting liability; a named sponsor and backup maintainer with real contact details; and a real ITSM/CMDB record ID. **None of that is verifiable by the framework — it checks only that a Date cell is non-empty.** That gap is itself the finding.
- **Evidence:** the APPROVAL_LOG section; the gate output; the negative-probe rc.

---

**`P0-002` — The pre-conditions template section EXISTS in the org approval log**
- **Class:** ARTIFACT · **Enforced?** WARNS-and-blocks (`[WARN] Pre-Phase 0: … no pre-conditions section found in APPROVAL_LOG.md`)
- **POSITIVE:** `grep -q 'Pre-Phase 0' APPROVAL_LOG.md` → true. Confirms `templates/generated/approval-log-org.tmpl` was the one rendered (the personal template has no such section).
- **⚠️ NEGATIVE:** n/a (covered by P0-001).
- **Evidence:** the grep.

---

**`P0-003` — Self-approval is detected and BLOCKED (organizational)**
- **What must happen:** An approver whose name matches the git commit author of the `APPROVAL_LOG.md` row is rejected.
- **Class:** AUTOMATED · **Enforced?** **BLOCKS** — `validate_approval_fields` emits `[FAIL] … self-approval detected for organizational deployment`.
- **POSITIVE:** Commit the approval log with author `e2e-walker`, and name a *different* approver (e.g. `Dana Okafor (STA) [SIMULATED]`) → no self-approval FAIL.
- **⚠️ NEGATIVE:** Set the Approver cell to `e2e-walker` (matching the commit author), commit, re-run the gate → must emit `[FAIL] … Approver 'e2e-walker' matches APPROVAL_LOG.md commit author … self-approval detected`. Restore.
- **Simulation note:** The agent is *simulating four humans from one git identity*. **A real run would require four distinct authenticated humans** — the framework verifies the commit author via `git blame`, so a real deployment genuinely cannot self-approve. Record that the walk's simulated approvers are only distinguishable because the walker deliberately used a different *name string*, not a different *identity*. This is the one place the simulation is materially weaker than reality, and it is worth saying so.
- **Evidence:** both gate runs; the `git blame` line the gate reads.

---

### 5.2 Phase 0 steps

---

**`P0-004` — Step 0.1 Functional Feature Set → `docs/phase-0/frd.md`**
- **Class:** ARTIFACT · **Enforced?** WARNS (`[WARN] Phase 0 intermediates: $p0_files/3 saved (check docs/phase-0/)`) — and the WARN increments `issues` → **BLOCKS**.
- **POSITIVE:** File exists; contains Must-Have / Should-Have / Will-Not-Have and a failure state per Must-Have. Template: `templates/generated/frd.tmpl` (**shipped**).
- **⚠️ NEGATIVE:** `rm docs/phase-0/frd.md` → gate must report `2/3` and `issues` must increment. Restore.
- **Evidence:** the file; both gate runs.

---

**`P0-005` — Step 0.2 User Personas & Interaction Flow → `docs/phase-0/user-journey.md`**
- **Class:** ARTIFACT · **Enforced?** WARNS-and-blocks (same `$p0_files/3` counter)
- **POSITIVE:** File exists with entry point, success path, failure recovery, feedback loops, exit points. Template `user-journey.tmpl` (**shipped**).
- **⚠️ NEGATIVE:** as P0-004.
- **Evidence:** the file.

---

**`P0-006` — Step 0.3 Data Input/Output & State Logic → `docs/phase-0/data-contract.md`**
- **Class:** ARTIFACT · **Enforced?** WARNS-and-blocks (same counter)
- **POSITIVE:** File exists; **includes the Sensitivity Classification Summary section** (this is what feeds Step 1.7's `data_classification`). Template `data-contract.tmpl` (**shipped**).
- **⚠️ NEGATIVE:** as P0-004.
- **Evidence:** the file; the sensitivity section.

---

**`P0-007` — Step 0.4 Product Manifesto → `PRODUCT_MANIFESTO.md`, all 8 numbered sections**
- **Class:** ARTIFACT · **Enforced?** **BLOCKS** — `validate_manifesto_content` emits `[FAIL] PRODUCT_MANIFESTO.md: missing required sections:` and loops sections **1..8**.
- **POSITIVE:** `bash scripts/check-phase-gate.sh` → `[OK]` on the manifesto. Sections 1–8: Product Intent, Functional Requirements, User Journeys, Data Contracts, MVP Cutline, Post-MVP Backlog, Will-Not-Have, Open Questions.
- **⚠️ NEGATIVE:** Delete the `## 5.` MVP Cutline heading → re-run → must `[FAIL] … missing required sections: 5`. Restore.
- **Evidence:** both runs.

---

**`P0-008` — Manifesto Open Questions are all resolved**
- **Class:** ARTIFACT · **Enforced?** **BLOCKS** — `[FAIL] PRODUCT_MANIFESTO.md: $open_count unresolved Open Question(s) — resolve before Phase 1`
- **POSITIVE:** Zero `Status: Open` lines in the manifesto → gate `[OK]`.
- **⚠️ NEGATIVE:** Add one `Status: Open` line under § 8 → re-run → must FAIL with the count. Restore.
- **Evidence:** both runs.

---

**`P0-009` — Manifesto placeholder content is flagged**
- **Class:** ARTIFACT · **Enforced?** WARNS (`[WARN] PRODUCT_MANIFESTO.md: sections with only placeholder content:`) — **verify whether this arm increments `issues`.** Record the answer; it determines whether a fully-templated, unfilled manifesto can pass Phase 0.
- **POSITIVE:** Real content in every section → no placeholder WARN.
- **⚠️ NEGATIVE:** Restore one section to its template placeholder text → re-run → WARN appears. **Then check the exit code** — does it block? Record. → **CM-U-04**
- **Evidence:** both runs + rc.

---

**`P0-010` — Step 0.5 Revenue Model → Manifesto **Appendix A** (Standard+ → REQUIRED here)**
- **Class:** ARTIFACT · **Enforced?** **UNENFORCED (declared only)** → **CM-H-04**. `validate_manifesto_content` loops sections **1..8 only** — Appendices A, B, C are **invisible to the gate**.
- **POSITIVE:** Appendix A exists in `PRODUCT_MANIFESTO.md` with pricing, per-user cost, break-even, hosting ceiling. Template `product-manifesto.tmpl` **does** ship Appendix A.
- **⚠️ NEGATIVE:** **Delete Appendix A entirely** → re-run `check-phase-gate.sh` → **it must still PASS.** That is the finding: a Standard-track project can pass Phase 0→1 with no revenue model at all, despite the track matrix marking it `Required`.
- **Walker must additionally record:** *did the framework ever prompt me for this?* (Search `init.sh` output and every scaffolded doc for "Revenue Model".) The answer determines whether this is a hollow gate or merely an unenforced one.
- **Evidence:** the passing gate with Appendix A deleted (the load-bearing evidence); the prompt search.

---

**`P0-011` — Step 0.6 Orchestrator Competency Matrix → Manifesto **Appendix B** (Required, ALL tracks)**
- **Class:** HUMAN (SIMULATED) · **Enforced?** **UNENFORCED (declared only)** → **CM-H-05**. Same 1..8 loop blindness. The builders-guide's `#### Enforcement` sub-heading says *each "No" domain's automated tool MUST be installed and active in CI before Phase 2* — **`validate.sh::check_competency` is the only implementation, it is never invoked by any gate/hook/CI, and it reads `PROJECT_INTAKE.md` rather than Appendix B, covering 4 of 9 domains.**
- **POSITIVE:** Appendix B exists with all 9 domains self-assessed.
- **⚠️ NEGATIVE:** Delete Appendix B → `check-phase-gate.sh` still PASSES. Then run `bash scripts/validate.sh` and see whether it even mentions competency. Record.
- **Simulation note:** The agent plays the Orchestrator self-assessing 9 domains. It will mark **Security = "No"** deliberately, because that is what should trigger the governance-framework's *Security Peer Review (Competency-Gated)* Phase-3 human checkpoint. **Assert whether anything in the framework reacts to that "No".** (Prediction: nothing does.) **A real run would need a real human's honest self-assessment**, and — per the guide — the CI tooling for every "No" domain installed before Phase 2.
- **Evidence:** the appendix; the still-passing gate; the `validate.sh` output; the (predicted absent) reaction to Security=No.

---

**`P0-012` — Step 0.7 Trademark & Legal Pre-Check → Manifesto **Appendix C** (Standard+ → REQUIRED)**
- **Class:** HUMAN (SIMULATED) · **Enforced?** **UNENFORCED (declared only)** → **CM-H-04**
- **POSITIVE:** Appendix C exists (USPTO/WIPO/app-store/domain search; privacy-reg applicability).
- **⚠️ NEGATIVE:** Delete it → gate still PASSES.
- **Simulation note:** The agent records a `[SIMULATED]` trademark search. **A real run needs an actual USPTO/WIPO search** (and, per the guide, distribution-channel legal requirements). The framework has no way to distinguish a real search from a fabricated one — record that.
- **Evidence:** as above.

---

**`P0-013` — The Phase-0 Artifact Map in the guide MIS-MAPS the appendices**
- **Class:** ARTIFACT · **Enforced?** N/A (doc bug)
- **What must happen:** The walker, following the guide's `#### Phase 0 Artifact Map`, is told Steps 0.5/0.6/0.7 land in "Section 7/6/8" of the manifesto. **The manifesto template's §6/§7/§8 are actually Post-MVP Backlog / Will-Not-Have / Open Questions.** The real homes are Appendices A/B/C.
- **POSITIVE:** n/a — this item exists to be **recorded**, not passed.
- **⚠️ NEGATIVE:** n/a.
- **Walker action:** Follow the Artifact Map literally. Write Appendix A content into "Section 7". Observe that the gate passes anyway (because it never checks) **and** that the manifesto is now corrupt (revenue model filed under Will-Not-Have). Record. → **CM-D-02** (filed as part of **BL-105**).
- **Evidence:** the corrupted manifesto; the passing gate.

---

**`P0-014` — The Phase 0→1 gate: dated approval entry within the 15-line proximity window**
- **Class:** HUMAN (SIMULATED) · **Enforced?** WARNS-and-blocks (`[WARN] Phase 0→1: gate dated …, but APPROVAL_LOG.md has no dated entry`)
- **POSITIVE:** `APPROVAL_LOG.md` has a `## Phase Gate: Phase 0 → Phase 1` section with a populated Date row **within 15 lines of the header** (the gate's proximity window — `get_gate_date`). Run `bash scripts/check-phase-gate.sh` → `[OK]`.
- **⚠️ NEGATIVE (two arms):**
  1. Blank the Date → gate WARNs and `issues` increments → non-zero rc.
  2. **Push the Date row >15 lines below the header** (insert filler) → the gate must **stop seeing it**. This proves the proximity window is real, and documents a trap: a legitimately-approved gate can read as unapproved purely because of markdown layout. Record whether the gate says anything useful when this happens.
- **Simulation note:** The agent plays the **Project Sponsor** (governance-framework § V names the Sponsor as the 0→1 approver). Row marked `[SIMULATED]`. **A real run requires the named sponsor's dated sign-off, committed by them** (the self-approval check reads `git blame`).
- **Evidence:** both gate runs; the >15-line probe.

---

**`P0-015` — `phase_0_to_1` gate date is written to `phase-state.json`**
- **Class:** AUTOMATED · **Enforced?** BLOCKS-adjacent — `_cpg_record_gate_date` (marker `# BL-071-WRITE`, atomic finalize) writes the date on PASS, guarded by `# BL-071-EVIDENCE-GATE`.
- **POSITIVE:** After a passing gate, `jq '.gates.phase_0_to_1' .claude/phase-state.json` → a date, not `null`.
- **⚠️ NEGATIVE:** `jq '.gates.phase_0_to_1=null'` + `current_phase=1` → re-run → must WARN `current_phase is 1 but gate date not recorded in phase-state.json` and increment. Restore.
- **Evidence:** the state key; both runs.

---

**`P0-016` — The Phase 0→1 snapshot is created**
- **Class:** AUTOMATED · **Enforced?** WARNS (no block)
- **POSITIVE:** After the gate passes, `ls docs/snapshots/phase-0-to-1_*/` contains `PRODUCT_MANIFESTO.md`, `APPROVAL_LOG.md`, `PROJECT_INTAKE.md` and a `phase-0/` subdir (per `create_gate_snapshot`'s `0-1)` arm).
- **⚠️ NEGATIVE:** n/a (evidence-capture, not a gate).
- **Evidence:** the snapshot listing.

---

## 6 · Phase 1 — Architecture & Technical Planning

---

**`P1-001` — Step 1.1 Business Strategy Gateway → Go/No-Go (DECISION GATE)**
- **Class:** HUMAN (SIMULATED) · **Enforced?** **UNENFORCED (declared only)** → **CM-H-03**. `grep -rliE 'market.?signal|go.?no.?go' scripts/` → **zero hits**.
- **POSITIVE:** A Go/No-Go decision + rationale is recorded somewhere an auditor could find it. **The guide says "Manifesto appendix or Bible §3 (ADR)" — the manifesto has no such appendix** (Appendices are A=Revenue, B=Competency, C=Trademark). The walker files it in the Bible's ADR section.
- **⚠️ NEGATIVE:** **Omit the Go/No-Go entirely.** Run `check-phase-gate.sh` at the 1→2 boundary. It **PASSES**. No script anywhere reads a Go/No-Go.
- **Walker MUST record:** *Did the framework ever prompt me for a Go/No-Go?* Search `init.sh` output, `PROJECT_INTAKE.md`, `CLAUDE.md` (the generated one), and `phase-state.json` for any Go/No-Go slot. **Prediction: nothing.** The guide's Step 1.1 is also, uniquely, a one-line directive with **no fenced prompt block** — unlike every sibling step. Record that too.
- **Simulation note:** Agent plays the Orchestrator; records `GO` with a `[SIMULATED]` rationale. **A real run needs the Orchestrator's own judgment** — the guide is explicit that this is a human decision.
- **Evidence:** the (absent) prompt; the passing gate with no Go/No-Go on record.

---

**`P1-002` — 🔴 Step 1.1.5 Market Signal Validation (DECISION GATE, Standard+ → REQUIRED here) — THE BL-102 CATCH**
- **Phase/Step:** Phase 1 / Step 1.1.5 — Market Signal Validation
- **What must happen:** *"At least one market signal before committing to architecture. Record the signal type (customer interview, letter of intent, survey result, landing page signups) and outcome in the Product Manifesto appendix or Project Bible."* Followed by: **"DECISION GATE — If no positive signal, return to Phase 0."**
- **Class:** HUMAN (SIMULATED) · **Enforced?** **UNENFORCED (declared only)** → **CM-H-03** (= **BL-102**)
- **POSITIVE — and this is the point:** *There is no positive assertion available.* There is **no artifact slot** and **no script**. The walker must attempt to comply and document the failure to comply:
  1. `grep -ril 'market signal' templates/` → **zero hits.** No template anywhere in the framework has a market-signal slot.
  2. `grep -rliE 'market.?signal' scripts/` → **zero hits.** No script reads one.
  3. The manifesto's appendices are **A (Revenue), B (Competency), C (Trademark)**. The guide names "the Product Manifesto appendix" — **there is no Appendix D.**
  4. `jq 'keys' .claude/phase-state.json` → no market-signal key.
- **⚠️ NEGATIVE:** **Complete the entire walk with zero market signal recorded.** Every gate passes. The framework never once asks. That *is* the assertion.
- **Simulation note:** The agent plays the Orchestrator and *would* record one simulated customer interview — **but there is nowhere to put it.** The walker must record exactly where it ended up filing it (an ad-hoc heading it invented) and note that a second walker would invent a different location, because the framework specifies none. **A real run needs a real interview / LOI / survey — and, per BL-102, an evidence grammar (`seen it` / `hunch` / `guess`) and a source-verification protocol that the framework does not yet have.**
- **Evidence:** all four greps, verbatim; the ad-hoc location the walker had to invent; the passing 1→2 gate.
- **→ This item, alone, catches BL-102.**

---

**`P1-003` — Step 1.2 Architecture & Stack Selection (DECISION GATE) → ADR**
- **Class:** HUMAN (SIMULATED) · **Enforced?** UNENFORCED (declared only) → **CM-H-07**
- **POSITIVE:** An ADR exists in `docs/ADR documentation/` selecting the stack from 3 evaluated options, with rejected alternatives. Template `adr.tmpl` (**shipped**).
- **⚠️ NEGATIVE:** Delete the ADR → no gate notices.
- **Simulation note:** Agent proposes 3 architectures, plays the Orchestrator selecting one (Node/Express + SQLite + a minimal SPA). **A real run needs the Orchestrator's decision**, informed by their own Competency Matrix.
- **Evidence:** the ADR; the indifferent gate.

---

**`P1-004` — Step 1.3 Threat Model (STRIDE) with stable `TM-NNN` IDs → Bible §4**
- **Class:** ARTIFACT · **Enforced?** **BLOCKS (indirectly, at Phase 3)** — the `threat-model` scanner (in `P3_SCANNERS`) parses Bible §4's `TM-NNN` rows and compares them against the validation report (marker `# BL-070-TM-COMPARE`). No TM IDs → the scanner has nothing to verify.
- **POSITIVE:** `PROJECT_BIBLE.md` § 4 has a Risk/Mitigation Matrix with rows `TM-001`…`TM-00N`, each with a mitigation. The note-keeper's login + SQLite give real rows (credential stuffing, session fixation, SQL injection, data-at-rest, IDOR on notes).
- **⚠️ NEGATIVE:** Deferred to **P3-032** (the threat-model scanner arm), where removing a `TM-` row must make the scanner FAIL. **The threat model's enforcement lives two phases later** — record that the walker had no feedback at Phase 1 that the IDs were even in the right format.
- **Evidence:** Bible § 4; the TM row IDs.

---

**`P1-005` — Step 1.4 Data Model → Bible §5**
- **Class:** ARTIFACT · **Enforced?** UNENFORCED (declared only) → **CM-H-07**
- **POSITIVE:** Bible §5 has entities, relationships, access control, sensitivity controls, and **both** create and rollback operations.
- **⚠️ NEGATIVE:** No gate reads it. Confirm.
- **Evidence:** Bible § 5.

---

**`P1-006` — Step 1.4.5 Data Migration Plan (N/A here — no legacy system)**
- **Class:** ARTIFACT · **Enforced?** UNENFORCED
- **POSITIVE:** Bible §6 records `N/A — greenfield, no legacy data` (the guide's *"Note on skipped steps"* requires an explicit `N/A — [reason]` so an auditor can distinguish skipped-deliberately from forgotten).
- **⚠️ NEGATIVE:** n/a.
- **Note:** `migration-plan.tmpl` exists in the framework and is **never shipped** (D-2) — so even a project that *did* need it would find no template. Record.
- **Evidence:** Bible § 6.

---

**`P1-007` — Step 1.5 UI & UX Scaffolding, all four states → Bible §9**
- **Class:** ARTIFACT · **Enforced?** UNENFORCED (declared only)
- **POSITIVE:** Bible §9 has layout, ≥2 component skeletons, and **all four states (Empty / Loading / Error / Success)** plus an a11y baseline.
- **⚠️ NEGATIVE:** Omit the Error state → nothing notices. (It resurfaces only at P3-024, the accessibility audit, if at all.)
- **Evidence:** Bible § 9.

---

**`P1-008` — Step 1.6 The Project Bible (DECISION GATE — "the point of no return")**
- **Class:** ARTIFACT · **Enforced?** **BLOCKS** — `[FAIL] Phase 1→2: PROJECT_BIBLE.md not found`; plus `[WARN] … only $bible_sections numbered sections (template specifies 16, minimum 14)` which **increments `issues` → blocks**.
- **POSITIVE:** `PROJECT_BIBLE.md` exists with **≥14** numbered sections (template ships 16). Gate → `[OK]`.
- **⚠️ NEGATIVE (two arms):**
  1. `mv PROJECT_BIBLE.md /tmp/` → gate must `[FAIL]`. Restore.
  2. Delete sections until only 13 remain → gate must WARN-and-block with the `14` minimum. Restore. **This is the one Phase-1 artifact with a real, numeric, blocking check** — prove it.
- **Evidence:** both probes.

---

**`P1-009` — Bible placeholder dates are flagged**
- **Class:** ARTIFACT · **Enforced?** WARNS (`[WARN] PROJECT_BIBLE.md has $placeholder_dates placeholder date(s)`) — **verify whether it increments.** Record.
- **POSITIVE:** No `YYYY-MM-DD` literals remain.
- **⚠️ NEGATIVE:** Reintroduce one → WARN → check rc.
- **Evidence:** both runs + rc.

---

**`P1-010` — Senior Technical Authority approves the Bible (organizational)**
- **Class:** HUMAN (SIMULATED) · **Enforced?** WARNS-and-blocks via the generic dated-entry check for the 1→2 gate section; the **STA role** itself is named only in `docs/governance-framework.md` § V, not checked by name.
- **POSITIVE:** `APPROVAL_LOG.md` § `Phase Gate: Phase 1 → Phase 2` has a dated Approver row (within the 15-line window). Gate → `[OK]`.
- **⚠️ NEGATIVE:** Blank the Date → gate WARNs + blocks. Restore. **Then:** set the Approver to a name that is *not* the STA (e.g. "Some Random Person") → **the gate accepts it.** The framework checks *that someone signed*, never *that the right role signed*. Record. → **CM-H-08**
- **Simulation note:** Agent plays the **Senior Technical Authority**. **A real run needs the actual STA** — and the framework cannot tell the difference, which is the finding.
- **Evidence:** all three gate runs.

---

**`P1-011` — 🔴 Step 1.7 Data Classification & ZDR Attestation (Phase 1→2 invariant)**
- **What must happen:** `.claude/process-state.json::phase1_artifacts.data_classification` is set to a value in the taxonomy `{public internal confidential pii financial health regulated}`; anything above `public` additionally requires `zdr_attested=true` **or** a non-empty `zdr_attestation_reason`.
- **Class:** AUTOMATED · **Enforced?** **BLOCKS (hard)** — three distinct FAIL arms in the Phase 1→2 ZDR block: `phase1_artifacts.data_classification not set`, `invalid data_classification '<x>' (not in taxonomy)`, and `data_classification='<x>' but no ZDR attestation evidence`.
- **POSITIVE:** The note-keeper stores user credentials → classification is **`pii`** (not `public`), so a ZDR attestation is genuinely required. Set it via `bash scripts/intake-wizard.sh` (§5.5) — **not by hand-editing the JSON.** Then `bash scripts/check-phase-gate.sh` → `[OK]` on the ZDR gate.
- **⚠️ NEGATIVE (all three arms — this gate has the richest failure surface in the framework, exercise it fully):**
  1. `jq 'del(.phase1_artifacts.data_classification)' process-state.json` → `[FAIL] … not set`.
  2. Set it to `"top-secret"` → `[FAIL] … invalid data_classification 'top-secret' (not in taxonomy)`.
  3. Set it to `"pii"` and **remove both** `zdr_attested` and `zdr_attestation_reason` → `[FAIL] … but no ZDR attestation evidence`.
  4. Set it to `"public"` with no attestation → **must PASS** (the exemption is real).
  Restore to `pii` + attestation after each.
- **Simulation note:** The agent plays the **Orchestrator attesting ZDR** (zero-data-retention) with the AI provider. **A real run requires the operator to actually confirm ZDR terms with their AI vendor** (and, per the guide, to re-verify at the Phase-4 biannual review). The framework checks only that a reason string is non-empty — it cannot verify the vendor's terms. Record.
- **Sequencing trap (D-7):** `init.sh` never seeds `phase1_artifacts` (`grep -c 'phase1_artifacts' init.sh` → `0`). **The gate FAILs on a fresh project for the "not set" reason regardless.** The walker must not mistake that for a working attestation check — run all four arms.
- **Evidence:** all four probes; the intake-wizard transcript.

---

**`P1-012` — Phase 1→2 BACKSTOP: verified remote push gate (BL-084)**
- **Class:** AUTOMATED · **Enforced?** **BLOCKS, non-bypassable** — `[FAIL] Phase 1→2 push gate: POC-Sponsored / Production (deployment=organizational, poc_mode=none) requires a VERIFIED remote (the code must be pushed) — MANDATORY, non-bypassable (BL-084)`. Markers `# BL-084-PUSH-VERIFY`, `# BL-084-TIER-KEY`.
- **POSITIVE:** ⚠️ **This gate and the walk's hermetic constraint are in direct conflict.** We ran `--no-remote-creation`, so there is no remote — and `deployment=organizational` makes the push gate **mandatory and non-bypassable**. **Expected: the walk CANNOT pass Phase 1→2 cleanly.**
  The walker must:
  1. Run `bash scripts/check-phase-gate.sh` and **capture the FAIL verbatim.** This is correct, desirable behavior — the gate is doing its job.
  2. Establish a **local bare repo** as the remote (`git init --bare "$TOPTMP/remote.git"; git remote add origin "$TOPTMP/remote.git"; git push -u origin main`) — this is hermetic (no network, no real host) and gives the gate a genuinely verified remote to find.
  3. Re-run the gate → `[OK]`.
  **If step 2 does not satisfy the gate** (e.g. the host-driver check demands a real GitHub API response), that is a **finding**: the framework's mandatory push gate is unsatisfiable without a live remote, which means **every hermetic test of it is a fiction**. Record the answer either way — this is exactly the fixture-hides-product-gap class.
- **⚠️ NEGATIVE:** With the local bare remote in place and the branch pushed, `git push origin --delete main` (or point `origin` at an empty bare repo) → the gate must FAIL again with `the remote still does NOT have the branch`. Restore.
- **Simulation note:** The remote is a **local bare repo**, not a real host. **A real run needs a real remote** with real branch protection. This is the walk's largest infrastructure simulation and its result should be read with that caveat.
- **Evidence:** the initial FAIL; the bare-repo setup; the re-run; the delete-branch probe.

---

**`P1-013` — Phase 1→2 BACKSTOP: branch-protection verification**
- **Class:** INFRA (SIMULATED) · **Enforced?** BLOCKS when the host driver loads (`[FAIL] Phase 1→2 backstop: protection verification failed`); **WARNS and skips** when the driver or manifest is missing (`[WARN] … host dispatcher or manifest.json missing — skipping (project predates host-aware gate)`).
- **POSITIVE:** Record which branch the code takes. With `--no-remote-creation` and a local bare remote there is no host API, so the gate will most likely take the **WARN-and-skip** path.
- **⚠️ NEGATIVE (the hollow-gate probe):** **This is the interesting arm.** If the gate silently skips because `manifest.json` has no `host` field, then **branch protection is unverified on every hermetic project** — and the WARN says so in language ("project predates host-aware gate") that misdescribes what actually happened. Assert: `jq '.host' .claude/manifest.json` → what is there? Does the gate skip? Record the exact WARN. → **CM-U-05**
- **Simulation note:** **A real run needs a real remote with real branch protection rules applied via the host API** (`scripts/host-drivers/github.sh`), and the gate would verify them by API call. The walk cannot exercise that path without a live remote. **This surface is essentially untested by this walk — say so loudly in §8.**
- **Evidence:** the manifest; the gate arm taken; the verbatim WARN/FAIL.

---

**`P1-014` — The Phase 1→2 gate date + snapshot**
- **Class:** AUTOMATED · **Enforced?** WARNS-and-blocks
- **POSITIVE:** `jq '.gates.phase_1_to_2'` → a date; `ls docs/snapshots/phase-1-to-2_*/` contains `PROJECT_BIBLE.md`, `PRODUCT_MANIFESTO.md`, `APPROVAL_LOG.md`.
- **⚠️ NEGATIVE:** as P0-015.
- **Evidence:** the state key; the snapshot.

---

## 7 · Phase 2 — Construction (the Loom Method)

### 7.1 Project initialization (the `phase2_init` process — 7 steps)

---

**`P2-001` … `P2-007` — The seven `phase2_init` steps**
- **Steps (in order):** `remote_repo_created`, `branch_protection_configured`, `project_scaffolded`, `data_model_applied`, `pre_commit_hooks_installed`, `ci_pipeline_configured`, `initialization_verified`
- **Class:** AUTOMATED · **Enforced?** **BLOCKS** — `--check-commit-ready` refuses every source commit at `current_phase == 2` until `.phase2_init.verified == true` (`[FAIL] Phase 2 initialization not verified.`). Ordering is enforced: `--complete-step` refuses any step whose predecessors are incomplete (`[FAIL] Cannot complete '<x>' — '<y>' not yet completed.`).
- **POSITIVE:** `bash scripts/process-checklist.sh --verify-init` → auto-marks what it can verify; then `jq '.phase2_init.verified' .claude/process-state.json` → `true`.
- **⚠️ NEGATIVE (two arms):**
  1. **Ordering:** `--complete-step phase2_init:ci_pipeline_configured` on a fresh state → must FAIL naming the first incomplete predecessor. This proves the state machine is real.
  2. **The commit block:** `jq '.phase2_init.verified=false'` → attempt any source commit → must FAIL with `Phase 2 initialization not verified.` Restore.
- **Note:** **None of the seven has an artifact-check arm** in the `case "${process}:${step_id}"` block — they are pure sequencing. So `--verify-init` marking `remote_repo_created` complete does **not** prove a remote exists (P1-012 is the only thing that does). Record.
- **Evidence:** the `--verify-init` output; both negative probes.

---

**`P2-008` — The scaffolded CI pipeline exists**
- **Class:** ARTIFACT · **Enforced?** UNENFORCED at this phase (a release-pipeline TODO check exists at Phase 3→4)
- **POSITIVE:** `.github/workflows/ci.yml` exists (from `templates/pipelines/ci/github/typescript.yml`).
- **⚠️ NEGATIVE:** n/a here.
- **Walker must record:** **does the scaffolded `ci.yml` invoke `check-phase-gate.sh`?** (Prediction, per X-010: **no**.) This is the second half of the interlock question — if CI does not run the gate either, then nothing does.
- **Evidence:** the workflow file, verbatim.

---

### 7.2 The Build Loop (6 steps × the real feature)

The walk builds **one real feature end-to-end**: *"user can create and list notes"* — chosen because it touches auth, SQLite, and the UI.

---

**`P2-009` — `--start-feature` opens a Build Loop**
- **Class:** AUTOMATED · **Enforced?** BLOCKS downstream
- **POSITIVE:** `bash scripts/process-checklist.sh --start-feature "create and list notes"` → `.build_loop.feature` is set.
- **⚠️ NEGATIVE:** covered by X-008 (a `feat:` commit with no open loop must block).
- **Evidence:** the state JSON.

---

**`P2-010` — Step 2.2 `build_loop:tests_written` (DECISION GATE — review the assertions)**
- **Class:** AUTOMATED + HUMAN · **Enforced?** BLOCKS (sequencing) · **no artifact-check arm**
- **POSITIVE:** Write real failing tests first (success + negative + boundary). `--complete-step build_loop:tests_written` → recorded.
- **⚠️ NEGATIVE:** `--complete-step build_loop:implemented` **before** `tests_written` → must FAIL naming `tests_written`. This is the ordering interlock.
- **Note:** There is **no artifact check** on `tests_written` — the step can be marked complete with **zero tests actually written**. Prove it: on a scratch copy, mark `tests_written` with an empty test dir → it succeeds. **The only thing that actually requires a test to exist is the BL-072 commit-msg gate (X-004).** Record that the Build Loop's own test step is unverified.
- **Simulation note:** The Orchestrator's DECISION GATE ("personally write ≥3 business-logic assertions per feature") is simulated by the agent. **A real run needs the human to write them** — the framework cannot tell who typed the assertions.
- **Evidence:** the ordering FAIL; the empty-test-dir probe.

---

**`P2-011` — `build_loop:tests_verified_failing`**
- **Class:** AUTOMATED · **Enforced?** BLOCKS (sequencing) · no artifact check
- **POSITIVE:** Run the suite, confirm RED, `--complete-step`.
- **⚠️ NEGATIVE:** Same class as P2-010 — nothing verifies the tests actually failed. Record.
- **Evidence:** the (real) failing test output; the state.

---

**`P2-012` — `build_loop:implemented`**
- **Class:** AUTOMATED · **Enforced?** BLOCKS (sequencing) · no artifact check
- **POSITIVE:** Implement; suite GREEN; `--complete-step`.
- **⚠️ NEGATIVE:** n/a beyond sequencing.
- **Evidence:** the green suite.

---

**`P2-013` — 🔴 `build_loop:security_audit` — the artifact arm that points at an UNSHIPPED template**
- **Class:** AUTOMATED · **Enforced?** **BLOCKS** — the `build_loop:security_audit` arm sets `artifact_check_failed=true` unless a feature-named file exists under `docs/security-audits/`, then `[FAIL] Artifact check failed. Produce the required artifact first.`
- **POSITIVE:** Create `docs/security-audits/create-and-list-notes-security-audit.md` (the exact slug the arm computes) → `--complete-step build_loop:security_audit` → succeeds.
- **⚠️ NEGATIVE:** Without the file → must FAIL with `No security audit findings for feature 'create and list notes' in docs/security-audits/.`
- **🔴 THE FINDING (D-2):** The failure message says: **`Create a findings file using templates/generated/security-audit-findings.tmpl`** — and `init.sh` **never ships that template**. Verify in the generated project: `ls templates/generated/security-audit-findings.tmpl` → **No such file.** **The gate blocks you, tells you to use a template, and the template is not there.** This is BL-088's exact class, in artifact form, still live. **NEW — file it.**
- **Evidence:** the FAIL message verbatim; the `ls` proving the named template is absent; the passing run after hand-authoring the file.

---

**`P2-014` — `build_loop:documentation_updated` + `feature_recorded`**
- **Class:** AUTOMATED · **Enforced?** BLOCKS (sequencing) · no artifact check
- **POSITIVE:** Update `CHANGELOG.md` (8 categories) + `FEATURES.md`; `bash scripts/test-gate.sh --record-feature "create and list notes"`; `--complete-step build_loop:feature_recorded`.
- **⚠️ NEGATIVE:** Nothing verifies the CHANGELOG was actually touched. Confirm.
- **Note:** On `feature_recorded`, the Build Loop **auto-resets** (`.build_loop.feature` → null). Confirm — otherwise the next `feat:` commit would ride the previous loop's completed steps.
- **Evidence:** the auto-reset in the state JSON.

---

**`P2-015` — The `feat:` commit now passes both message gates**
- **Class:** AUTOMATED · **Enforced?** BLOCKS
- **POSITIVE:** With the loop complete and a real test staged alongside the impl, `git commit -m "feat: create and list notes"` → **rc=0**.
- **⚠️ NEGATIVE:** Already covered (X-004, X-008). This item proves the **happy path closes** — a framework that only ever blocks is not shippable.
- **Evidence:** the commit; `git log -1`.

---

### 7.3 UAT (the `uat_session` process — 9 steps)

---

**`P2-016` … `P2-024` — The nine `uat_session` steps**
- **Steps:** `agents_dispatched`, `template_generated`, `orchestrator_notified`, `results_received`, `completeness_verified`, `bugs_consolidated`, `triage_complete`, `remediation_complete`, `gate_passed`
- **Class:** HUMAN (SIMULATED) + AUTOMATED · **Enforced?** **BLOCKS** — a mid-UAT source commit is refused: `[FAIL] UAT session in progress — complete all steps before committing.` (**not** bypassed by a non-`feat:` subject — deliberately).
- **POSITIVE:** `--start-uat 1`; generate the session template into `tests/uat/sessions/<date>-session-1/`; walk all nine steps.
- **⚠️ NEGATIVE (the load-bearing one):** With the UAT session open at step 3 of 9, attempt **any** source commit (even `chore:`) → must **BLOCK** listing the missing steps. This is the one gate that deliberately ignores the commit-type classifier — prove it does. Then complete all nine → commit → allowed.
- **Note:** **None of the nine has an artifact-check arm.** All nine can be marked complete with no UAT ever run. The only real artifact is the session dir the agent creates by hand.
- **Simulation note:** The agent plays **both** the dispatched test subagents *and* the Orchestrator who fills in the results. **A real run has a human filling the UAT template** — the framework's own design says the agent *waits* and does not poll. The walk collapses that wait to zero, which means **the walk cannot validate the human-in-the-loop handoff at all.** Say so in §8. **A real run would additionally need:** a real human tester, and (per `docs/uat-authoring-guide.md`) scenarios validated by `bash scripts/lint-uat-scenarios.sh <populated-html-file>` — **run that linter on the populated file; it is a parametrized tool, not a repo lint** (bare-invoked it exits 2).
- **Evidence:** the mid-UAT commit block, verbatim; the nine-step completion; the `lint-uat-scenarios.sh` run on the real populated file.

---

**`P2-025` — Step 2.8 Bug Triage: SEV-1 cannot be deferred**
- **Class:** AUTOMATED · **Enforced?** **BLOCKS** — `test-gate.sh --check-phase-gate` → `[FAIL] Bug gate BLOCKED. Resolve SEV-1/2 bugs before Phase 3.` (called by `process-checklist.sh --start-phase3`).
- **POSITIVE:** File ≥1 real bug found in UAT into `BUGS.md`, triage it, fix it, close it. Then `bash scripts/test-gate.sh --check-phase-gate` → rc=0.
- **⚠️ NEGATIVE (three arms — this is one of the few gates that is genuinely wired into an advance path, so exercise it properly):**
  1. Add an **open SEV-1** to `BUGS.md` → `--start-phase3` must **BLOCK**.
  2. Add an open **SEV-2** → must **BLOCK**.
  3. **Defer** the SEV-2 (mark it Deferred) → per the guide, *"SEV-2 open **or deferred** ⇒ BLOCKED — no third option"* → **must still BLOCK.** *Verify this.* If a deferred SEV-2 passes, the guide and the code disagree and the code wins → finding.
  Restore after each.
- **Evidence:** all three `--start-phase3` attempts with rc.

---

**`P2-026` — The Phase 2→3 gate: FEATURES.md, CHANGELOG.md, gate date**
- **Class:** ARTIFACT · **Enforced?** WARNS-and-blocks (`[WARN] Phase 2→3: FEATURES.md not found`, `… CHANGELOG.md not found`, each incrementing `issues`)
- **POSITIVE:** Both exist; the `Phase 2 → Phase 3` approval section is dated; `check-phase-gate.sh` → rc=0.
- **⚠️ NEGATIVE:** `mv FEATURES.md /tmp/` → WARN + non-zero rc. Restore.
- **Simulation note:** Agent plays the **STA** (governance-framework § V names STA as the 2→3 approver).
- **Evidence:** both runs.

---

**`P2-027` — Mid-Phase 2 Governance Checkpoint (organizational) — "a status check, not a gate"**
- **Class:** HUMAN (SIMULATED) · **Enforced?** **UNENFORCED (declared only)** → **CM-H-09**
- **POSITIVE:** The guide declares a biweekly ≤30-min checkpoint with 4 escalation triggers. **No script implements it.** The walker records the checkpoint in `APPROVAL_LOG.md` and confirms nothing reads it.
- **⚠️ NEGATIVE:** Skip it entirely → nothing notices.
- **Note:** The guide itself says *"this is a status check, **not a gate**"* — so this is **correctly** unenforced. **Include it precisely because it is the control case:** a declared-but-unenforced step that the docs *honestly label* as unenforced. Everything else in the UNENFORCED column should be compared against this one.
- **Evidence:** the absence of any script hit for the checkpoint.

---

## 8 · Phase 3 — Validation, Security & UAT

⚠️ **Phase 3 is where the framework's teeth are, and where three of the four
motivating bugs live.** Walk it slowly.

### 8.1 The nine `phase3_validation` steps

`PHASE3_STEPS` (code, authoritative) = `integration_testing`,
`security_hardening`, `chaos_testing`, `accessibility_audit`,
`performance_audit`, `contract_testing`, `results_archived`,
**`pre_launch_preparation`**, **`legal_review`**.

**The builders-guide names only the first seven** (D-5).

---

**`P3-001` — `--start-phase3` runs the bug gate and advances the phase**
- **Class:** AUTOMATED · **Enforced?** BLOCKS (via `test-gate.sh --check-phase-gate`; see P2-025)
- **POSITIVE:** `bash scripts/process-checklist.sh --start-phase3` → rc=0; `jq '.current_phase'` → `3`.
- **⚠️ NEGATIVE:** covered by P2-025.
- **Note:** `start_phase3()` **does** consult a gate (the bug gate) — unlike `start_phase4()`, which consults none. Record the asymmetry.
- **Evidence:** the run.

---

**`P3-002` — `phase3_validation:integration_testing`**
- **Class:** AUTOMATED · **Enforced?** **BLOCKS** (artifact arm) — needs `tests/` **or** `docs/test-results/*integration*` **or** `*e2e*`
- **POSITIVE:** Write a real E2E test automating the note-keeper's full User Journey (login → create note → list → logout). Archive the result to `docs/test-results/YYYY-MM-DD_e2e_pass.txt`. `--complete-step` → succeeds.
- **⚠️ NEGATIVE:** ⚠️ **The arm is satisfied by the mere existence of a `tests/` directory** — which every scaffolded project has. Prove it: on a scratch copy with **no** integration test and **no** `docs/test-results/` entry, `--complete-step phase3_validation:integration_testing` → **succeeds anyway**, because `ls tests/` returns non-empty. **The integration-testing gate is satisfied by the scaffold itself.** Record as a finding. → **CM-U-07**
- **Evidence:** the scratch-copy probe; the real E2E run.

---

**`P3-003` — `phase3_validation:security_hardening`**
- **Class:** AUTOMATED · **Enforced?** **BLOCKS** (artifact arm) — needs `docs/test-results/*semgrep*` or `*sast*`
- **POSITIVE:** Run the real full-tree Semgrep (`semgrep scan --config=p/owasp-top-ten --config=p/security-audit`), save to `docs/test-results/YYYY-MM-DD_semgrep_pass.json`. `--complete-step` → succeeds.
- **⚠️ NEGATIVE:** Without the file → must FAIL with `No SAST scan results found in docs/test-results/.` **Then:** `touch docs/test-results/semgrep-i-am-empty.json` (an empty file with the magic substring) → the arm **passes**. The check is a **filename glob**, not a content check. Record.
- **Simulation note:** If `semgrep` is absent, the scan is `SIMULATED` with a fixture report — and the walker must record that **the framework's Phase-3 SAST is satisfied by a filename**.
- **Evidence:** both probes; the real Semgrep output if available.

---

**`P3-004` — `phase3_validation:chaos_testing`**
- **Class:** AUTOMATED · **Enforced?** BLOCKS (sequencing only) — **no artifact-check arm**
- **POSITIVE:** Run real chaos tests (input abuse, error recovery, resource limits, concurrency). `--complete-step` → succeeds.
- **⚠️ NEGATIVE:** **Mark it complete having run nothing.** It succeeds. There is no artifact arm for `chaos_testing`. Record. → **CM-U-07**
- **Evidence:** the no-op completion.

---

**`P3-005` — `phase3_validation:accessibility_audit`**
- **Class:** AUTOMATED / INFRA · **Enforced?** **BLOCKS** (artifact arm) — needs `docs/test-results/*accessibility*` or `*lighthouse*`
- **POSITIVE:** Run Lighthouse against the local note-keeper → `docs/test-results/YYYY-MM-DD_lighthouse_pass.html`. Guide requires **≥90** (web) and **WCAG AA**.
- **⚠️ NEGATIVE:** Without the file → FAIL. **Then:** create `docs/test-results/lighthouse_fail.html` — note the filename contains `lighthouse` — → the arm **passes**. **A FAILING Lighthouse report satisfies the accessibility gate.** The guide's `≥90` threshold is **checked by nothing**. Record. → **CM-H-10**
- **Simulation note:** A real run needs Lighthouse (or axe) against a served instance. If unavailable, `SIMULATED`. **A real run would additionally verify the score against the ≥90 bar — which no script does.**
- **Evidence:** the `_fail`-named file passing the gate (the load-bearing evidence).

---

**`P3-006` — `phase3_validation:performance_audit`**
- **Class:** AUTOMATED / INFRA · **Enforced?** BLOCKS (artifact arm) — needs `*performance*` or `*lighthouse*`
- **POSITIVE:** Real perf baseline → archived.
- **⚠️ NEGATIVE:** Same glob-only weakness as P3-005. **Note the shared `*lighthouse*` glob: one Lighthouse file satisfies BOTH the accessibility and performance arms.** Prove it — delete every `*performance*` file, keep the Lighthouse HTML → both arms pass. Record.
- **Evidence:** the single-file-satisfies-two-gates probe.

---

**`P3-007` — `phase3_validation:contract_testing` (Standard+ → required)**
- **Class:** AUTOMATED · **Enforced?** BLOCKS (sequencing) — **no artifact-check arm**
- **POSITIVE:** Document + verify the note-keeper's API contracts; `--complete-step`.
- **⚠️ NEGATIVE:** No artifact arm → completes with nothing produced. Record.
- **Evidence:** the no-op completion.

---

**`P3-008` — `phase3_validation:results_archived`**
- **Class:** AUTOMATED · **Enforced?** **BLOCKS** (artifact arm) — `docs/test-results/` must be non-empty
- **POSITIVE:** Directory non-empty → succeeds.
- **⚠️ NEGATIVE:** `rm -rf docs/test-results/*` → must FAIL with `docs/test-results/ is empty — archive Phase 3 scan results first.` Restore.
- **Evidence:** both runs.

---

**`P3-009` — 🔴 `phase3_validation:pre_launch_preparation` — a step the guide never names**
- **Class:** AUTOMATED · **Enforced?** BLOCKS (sequencing) — **no artifact-check arm** (BL-105 notes this explicitly)
- **POSITIVE:** `--complete-step phase3_validation:pre_launch_preparation` → succeeds (it maps to guide Step 3.6, which declares no step ID).
- **⚠️ NEGATIVE:** **This is a D-5 catch item.** A walker following the builders-guide **would never know this step exists** — `grep -o 'phase3_validation:[a-z_]*' docs/builders-guide.md` returns only 7 IDs, and this is not one of them. Record: how did the walker discover it? (Answer: by reading `PHASE3_STEPS` in the code, or by hitting the "7/9" gate block.)
- **Note:** Guide Step 3.6 also declares the **Final UAT sign-off** as *"formal acceptance sign-off recorded in `APPROVAL_LOG.md`"* — **and neither approval-log template has a UAT sign-off section.** Verify: `grep -i 'uat' APPROVAL_LOG.md` → expect nothing. → **CM-H-11** (BL-105)
- **Evidence:** the guide grep (7 IDs); the code grep (9 IDs); the absent UAT section.

---

**`P3-010` — 🔴 `phase3_validation:legal_review` — a step the guide never names, with a real artifact arm**
- **Class:** HUMAN (SIMULATED) · **Enforced?** **BLOCKS** — the `phase3_validation:legal_review` arm: if a legal doc (`PRIVACY_POLICY.md` / `TERMS_OF_SERVICE.md`) exists **and** `APPROVAL_LOG.md` has no attorney/legal-review entry → `artifact_check_failed=true` → FAIL.
- **POSITIVE:** The note-keeper stores user credentials → it **needs** a Privacy Policy. Create `PRIVACY_POLICY.md`; record an Attorney / Legal Review row in `APPROVAL_LOG.md` (the org template **does** ship an `Attorney / Legal Review (if applicable)` section); `--complete-step` → succeeds.
- **⚠️ NEGATIVE (two arms):**
  1. With `PRIVACY_POLICY.md` present and **no** attorney row → must **FAIL** with `Legal documents found but no attorney review recorded in APPROVAL_LOG.md.` ✅ This gate is real.
  2. **The hole:** `rm PRIVACY_POLICY.md` → the arm takes the `has_legal_docs=false` branch → prints an **INFO** (`No legal documents found — attorney review may not be required.`) → **and completes.** **So the way to bypass the attorney gate is to not write a privacy policy** — for an app that collects credentials. Record. → **CM-H-12**
- **Simulation note:** The agent plays **Corporate Legal / an attorney**, signing a `[SIMULATED]` row. **A real run needs an actual qualified attorney to review the Privacy Policy and ToS** — the guide calls this `MANDATORY`. The framework verifies only that the string "attorney" or "legal review" appears somewhere in `APPROVAL_LOG.md` (a case-insensitive grep over the whole file, not a section-scoped date check). **Prove that weakness:** put the literal word `attorney` in an unrelated comment line in `APPROVAL_LOG.md` → the check passes. Record.
- **Evidence:** all four probes.

---

### 8.2 The five Phase-3 validation scanners (BL-070)

`P3_SCANNERS="semgrep-full-tree license snyk zap-dast threat-model"` — all five
`real` per `_p3_kind`. **Every one must be PASS or an attested-skip** for the
Phase 3→4 gate to pass (marker `# BL-070-GATE-CHECK`).

---

**`P3-011` — The driver runs and writes a tree-bound summary**
- **Class:** AUTOMATED · **Enforced?** BLOCKS (the gate consumes the summary)
- **POSITIVE:** `bash scripts/run-phase3-validation.sh; echo "rc=$?"` → a summary at `docs/test-results/phase3/summary-<ts>.md` containing five `RESULT <name> <STATUS>` lines, plus `- tree:` and `- dirty:` provenance lines.
- **⚠️ NEGATIVE:** covered by P3-016 (staleness).
- **Evidence:** the summary, verbatim.

---

**`P3-012` — Scanner: `semgrep-full-tree`**
- **Class:** AUTOMATED · **Enforced?** BLOCKS (a FAIL fails the gate)
- **POSITIVE:** PASS (or an attested skip if `semgrep` is absent).
- **⚠️ NEGATIVE:** Introduce a real OWASP-detectable flaw (the string-concatenated SQL query from X-007) → re-run the driver → the scanner must report **FAIL** and the Phase 3→4 gate must then FAIL with `validation scans not clean: 1 FAIL`. Revert.
- **Simulation note:** If `semgrep` is absent → the scanner SKIPs → **the walk must attest it** and record that an organizational production project can reach Phase 4 with SAST attested-away.
- **Evidence:** the FAIL summary; the gate FAIL.

---

**`P3-013` — Scanner: `license` (BL-086 policy layer)**
- **Class:** AUTOMATED · **Enforced?** **BLOCKS, hard, for organizational** — `# BL-086-TIER`: `deployment=organizational` OR `poc_mode=sponsored_poc` OR `poc_mode=private_poc` → **blocked=true**. Deny stems (`# BL-086-DENY`): `GPL-2.0 GPL-3.0 AGPL-1.0 AGPL-3.0 SSPL-1.0 GPL AGPL` (strong copyleft only; LGPL/MPL/EPL explicitly **not** denied).
- **POSITIVE:** With only permissive deps (MIT/Apache-2.0/ISC/BSD) → scanner PASS.
- **⚠️ NEGATIVE (four arms — this is the best-specified gate in the framework; exercise it fully):**
  1. **Add a real GPL-3.0 dependency** to `package.json` → re-run → scanner must **FAIL**, naming the package and license, and the Phase 3→4 gate must FAIL.
  2. **Dual-license FP hygiene:** add a dep licensed `MIT OR GPL-3.0` → must **NOT** be flagged (`_p3_expr_flagged` returns clean if any OR-alternative is denied-free). This proves the gate is not a blunt substring match.
  3. **LGPL is not denied:** add an `LGPL-3.0` dep → must **NOT** be flagged (token start-with matching: `LGPL-3.0` does not start with `GPL`).
  4. **Attested escape:** `SOLO_LICENSE_ATTESTED=1 SOLO_LICENSE_REASON="walk probe"` with the GPL dep → must **PASS** and write `.claude/phase-state.json::phase3.license_exceptions[]`. Confirm the record exists — *attested, not silenced*.
  Revert `package.json` after each.
- **Simulation note:** Uses **real npm deps** — no mock. `license-checker` must be installed (`npm i -g license-checker`) or the scanner SKIPs. Record which.
- **Evidence:** all four probes; the license-exception record.

---

**`P3-014` — Scanner: `snyk`**
- **Class:** INFRA (SIMULATED) · **Enforced?** BLOCKS (a FAIL fails the gate)
- **POSITIVE:** `snyk test --json` (marker `# BL-070-SNYK-DISPATCH`) → PASS.
- **⚠️ NEGATIVE:** Make the mock `snyk` emit a report with a high-severity vuln → the scanner must FAIL → the gate must FAIL. Then attest it and confirm the gate passes with the attestation recorded.
- **Simulation note:** **A real run needs a Snyk-authenticated CLI (`snyk auth`, an org token).** The walk mocks `snyk` on `PATH` (per `tests/host-drivers/mock-cli.sh`) emitting a fixture JSON report. **A real run would additionally validate the report against Snyk's actual schema and confirm the token's org scope** — the walk validates neither, so a schema drift in Snyk's output would not be caught here.
- **Evidence:** the mock; both scanner runs; the attestation record.

---

**`P3-015` — Scanner: `zap-dast`**
- **Class:** INFRA (SIMULATED) · **Enforced?** BLOCKS
- **POSITIVE:** Serve the note-keeper locally; `SOLO_ZAP_TARGET_URL=http://127.0.0.1:<port> bash scripts/run-phase3-validation.sh` → the ZAP baseline runs via `docker run … zaproxy … zap-baseline.py -t "$SOLO_ZAP_TARGET_URL"` (marker `# BL-070-ZAP-DISPATCH`) → PASS.
- **⚠️ NEGATIVE:** Unset `SOLO_ZAP_TARGET_URL` → the scanner must SKIP (not silently PASS) → the gate must FAIL on the **un-attested SKIP**. **This is the important arm: prove an un-attested skip blocks.**
- **Simulation note:** **A real run needs Docker + a deployed instance reachable by the scanner.** The walk uses a **local target** (genuinely running the app) if Docker is available; otherwise the whole arm is `SIMULATED` and attested. **A real run would additionally use an `active` scan on Full track** (baseline only on Standard) — the walk does not test the active path.
- **Evidence:** the target URL; the scanner output; the un-attested-SKIP gate FAIL.

---

**`P3-016` — Scanner: `threat-model` (pure-local, runs even offline)**
- **Class:** AUTOMATED · **Enforced?** BLOCKS
- **POSITIVE:** The scanner parses `PROJECT_BIBLE.md` § 4's `TM-NNN` rows and compares them against `docs/test-results/*_threat-model-validation.md` (marker `# BL-070-TM-COMPARE`). Every TM ID must be covered (mitigation implemented, or explicitly risk-accepted with an *Approved By*). → PASS.
- **⚠️ NEGATIVE (two arms):**
  1. Remove one `TM-` row from the validation report (leaving it in the Bible) → the scanner must **FAIL**, naming the unaccounted ID.
  2. **Delete the Bible's §4 table entirely** → per the code comment, *"No bible / no §4 table → attestable SKIP."* → the scanner **SKIPs**. **So deleting your threat model downgrades a FAIL to an attestable SKIP.** Confirm, and record: *the way to make the threat-model scanner stop failing is to delete the threat model.*
- **🔴 D-2 CATCH:** The report template — `templates/generated/threat-model-validation.tmpl` — is **never shipped by `init.sh`**. `ls templates/generated/threat-model-validation.tmpl` in the project → **absent.** The walker must hand-author the report format from the scanner's parser. Record.
- **Evidence:** both probes; the absent template.

---

**`P3-017` — Attest-on-skip: reason AND signoff, both non-whitespace**
- **Class:** AUTOMATED · **Enforced?** BLOCKS — `_cpg_phase3_attested` (marker `# BL-070-ATTEST-PREDICATE`) requires **both** a non-empty `reason` and a non-empty `signoff`, whitespace-trimmed.
- **POSITIVE:** `bash scripts/run-phase3-validation.sh --attest snyk --reason "no Snyk licence on the walk host" --signoff "e2e-walker [SIMULATED]"` → recorded to `phase-state.json::phase3.attestations.snyk`.
- **⚠️ NEGATIVE (three arms):**
  1. `--attest snyk --reason "   "` (whitespace only) → must be **REJECTED** (`--attest requires a non-empty --reason … (whitespace-only is rejected)`).
  2. Attest with a reason but **no signoff** → `_cpg_phase3_attested` returns false → the gate must still FAIL on the un-attested skip. **Verify:** does `--attest` without `--signoff` even write a record? If it writes a reason-only record that the gate then rejects, the operator gets a confusing loop. Record.
  3. `--attest not-a-scanner` → must FAIL with `is not a registered scanner. Valid: semgrep-full-tree license snyk zap-dast threat-model`.
- **Evidence:** all three probes.

---

**`P3-018` — BL-082 summary staleness: the summary is bound to the tree**
- **Class:** AUTOMATED · **Enforced?** BLOCKS — marker `# BL-082-STALENESS`. A summary is FRESH only if its recorded `tree:` equals `git rev-parse HEAD^{tree}`, its `dirty:` is `no`, **and** the live scoped working tree is clean.
- **POSITIVE:** Run the driver on a clean tree; run `check-phase-gate.sh` → the summary is accepted.
- **⚠️ NEGATIVE (three arms):**
  1. **Edit a source file** (without committing) → re-run the gate → must print `[STALE]` and **regenerate** the summary automatically (the `# BL-070-GATE-AUTORUN` path), then evaluate the fresh one.
  2. **Block the autorun:** `SOLO_PHASE3_GATE_NOAUTORUN=1` with a stale summary → the gate must **FAIL** (never silently accept a stale summary).
  3. **Scoping:** confirm that a change to `.claude/phase-state.json` alone does **NOT** mark the summary stale (`_cpg_scoped_dirty` excludes `.claude/` — otherwise the gate's own gate-date write would self-invalidate every summary). Prove it: run the gate twice in a row; the second must not report STALE.
- **Evidence:** all three probes; the summary `tree:`/`dirty:` lines.

---

### 8.3 The Phase 3→4 gate

---

**`P3-019` — 🔴 The BL-104 scoring inversion — NOW A REGRESSION ASSERTION (fixed by PR #187)**
- ⚠️ **Expected result flipped.** On `f2e30de` the `else` arm EXISTS (marker `# BL-104-P3-ZERO`) and increments `issues`. **Zero steps must now BLOCK.** The probe below is unchanged — only the expectation is. If zero steps still passes, the fix is broken and that is a top-severity finding.
- **Phase/Step:** Phase 3→4 gate / P3-007 cross-check
- **What must happen:** The gate reads `.claude/process-state.json::phase3_validation.steps_completed | length` and compares it against 9.
- **Class:** AUTOMATED · **Enforced?** **BLOCKS — perversely.** The code is:
  ```
  if   [ "$p3_steps_done" -ge 9 ]; then  [OK]
  elif [ "$p3_steps_done" -gt 0 ]; then  [WARN] "$p3_steps_done/9 steps"; issues=$((issues + 1))   # BLOCKS
  fi                                                                    # 0 → NEITHER arm → SILENT PASS
  ```
- **POSITIVE:** With all 9 complete → `[OK] Phase 3 process checklist: 9 steps completed` → this arm does not block.
- **⚠️ NEGATIVE — THE BL-104 CATCH (run all three, in this order, and paste all three exit codes):**
  1. `jq '.phase3_validation.steps_completed = []' .claude/process-state.json` (**zero** steps) → `bash scripts/check-phase-gate.sh` → **assert this arm emits NOTHING and does not increment `issues`.** *Diligence is punished; total neglect sails through.*
  2. `jq '.phase3_validation.steps_completed = [...8 of the 9...]'` (**eight** steps) → re-run → **assert `[WARN] Phase 3 process checklist incomplete: 8/9 steps` AND `issues` increments → the gate BLOCKS.**
  3. Restore all 9 → `[OK]`.
  **The assertion is the comparison:** *0 steps passes this arm, 8 steps blocks it.* If both 0 and 8 behave the same, BL-104 arm 1 has been fixed. If they differ as described, it is reproduced.
- **Evidence:** all three gate runs with their exit codes, and the specific arm's output line (or its absence) in each.
- **→ This item catches BL-104, arm 1.**

---

**`P3-020` — 🔴 The BL-104 empty-manifest bypass — NOW A REGRESSION ASSERTION (fixed by PR #187)**
- ⚠️ **Expected result flipped.** `check-phase-gate.sh` now carries 6 `BL-104` markers. **The no-manifest and empty-manifest arms must now behave consistently.** Probe unchanged; expectation flipped.
- **Class:** AUTOMATED · **Enforced?** BLOCKS (inconsistently — that is the bug)
- **What must happen:** Compare the *no-manifest* arm against the *empty-manifest* arm. In the code, the no-manifest WARN runs `issues=$((issues + 1))` (**blocks**); the incomplete-manifest WARN for a **non-enforced** project does **not** (**passes**).
- **POSITIVE:** In **our** config (`review_gate_enforced: true`, `track=standard`), `cpg_review_enforced=1`, so an empty manifest should hit the **FAIL** arm (`# BL-073-ESCALATE`). Assert: `echo '{"reviews":[]}' > docs/eval-results/review-manifest.json` → `check-phase-gate.sh` → must **FAIL** with `track=standard requires the Security AND Red Team reviews before Phase 4 (missing: Security, Red Team)`.
- **⚠️ NEGATIVE — THE BL-104 ARM-2 CATCH (the inversion probe):** Reproduce the ungrandfathered case. On a scratch copy:
  1. `jq '.review_gate_enforced = false' .claude/phase-state.json` (simulating a pre-BL-073 project) **and remove the manifest entirely** → run the gate → **assert it BLOCKS** (`[WARN] No review manifest found` + `issues++`).
  2. Same state, but `echo '{"reviews":[]}' > docs/eval-results/review-manifest.json` → run the gate → **assert it PASSES** (`[WARN] … bypass logged (grandfathered / POC: not blocking)` with **no** increment).
  **If (1) blocks and (2) passes, BL-104 arm 2 is reproduced: writing an empty manifest converts a blocking gate into a passing one.** Restore `review_gate_enforced: true`.
- **Evidence:** both gate runs with exit codes; the two `[WARN]` lines side by side.
- **→ This item catches BL-104, arm 2.**

---

**`P3-021` — 🔴 The six-eval generator actually RUNS — NOW A REGRESSION ASSERTION (fixed by PR #187)**
- ⚠️ **Expected result flipped.** On `f2e30de`: `/bin/bash -n evaluation-prompts/Projects/run-reviews.sh` **PASSES** under 3.2.57, and `git ls-tree` reports mode **`100755`**. **The generator must now RUN and must emit a manifest containing `redteam`.** Probe unchanged; expectation flipped. **Still do NOT hand-write the manifest** — running the real generator is the whole point, and is now also the only way to prove the fix holds end-to-end in a REAL scaffold (the fix's own test still builds its fixture by hand).
- **Phase/Step:** Phase 3→4 / the review gate's named remediation
- **What must happen:** The gate's failure message says: *"Run reviews: `evaluation-prompts/Projects/run-reviews.sh`"*. **The walker must run exactly that**, in the generated project, on this host — and must **NOT** hand-write the manifest under any circumstances. Hand-writing the manifest is precisely the sin that let BL-103 ship green.
- **Class:** AUTOMATED · **Enforced?** The gate that names it BLOCKS. The remediation itself is **BROKEN**.
- **POSITIVE (attempt, in this order — record each):**
  1. `ls -l evaluation-prompts/Projects/run-reviews.sh` → **expect mode `-rw-r--r--` (644, NOT executable)** — the scaffold `cp -r`'s it and never `chmod +x`. **D-4, a NEW defect on top of BL-103's two.**
  2. `./evaluation-prompts/Projects/run-reviews.sh web-app` → expect **Permission denied**.
  3. `bash evaluation-prompts/Projects/run-reviews.sh web-app` → expect a **bash-3.2 syntax error**:
     ```
     run-reviews.sh: line 142: conditional binary operator expected
     run-reviews.sh: line 142: syntax error near `"REVIEWERS[$num]"'
     ```
     (`declare -A REVIEWERS` + `[[ ! -v … ]]` are bash ≥4.2; macOS `/bin/bash` is 3.2.57 and the shebang is `#!/bin/bash`.)
  4. `/bin/bash -n evaluation-prompts/Projects/run-reviews.sh` → the same parse error, proving it is a **parse-time**, not runtime, death.
  5. Same for `evaluation-prompts/Projects/compose.sh` (`declare -A REVIEWER_BASE`).
- **⚠️ NEGATIVE (the second, independent defect — bites even on bash 5):** Compare the slugs the runner probes against the filenames the prompts instruct. Run:
  ```bash
  grep -n 'review-v1.md' evaluation-prompts/Projects/bases/*.md
  grep -n 'REVIEWERS\[' evaluation-prompts/Projects/run-reviews.sh
  ```
  **Assert the mismatch on three of six:**

  | Runner probes | Prompt writes | |
  |---|---|---|
  | `engineer-review-v1.md` | `senior-engineer-review-v1.md` | ✗ |
  | `techuser-review-v1.md` | `technical-user-review-v1.md` | ✗ |
  | **`redteam-review-v1.md`** | **`red-team-review-v1.md`** | ✗ **← MANDATORY BLOCKING REVIEWER** |
  | `cio` / `security` / `legal` | match | ✓ |

  The manifest entry is emitted only `if [ -f "$REVIEW_FILE" ]`. **So a Red Team review that was actually performed and saved exactly as instructed is recorded as missing, and the mandatory gate FAILs.** To prove this *independently of the bash-3.2 death*, the walker may run the generator under a bash ≥4.2 if one is available (`brew --prefix bash`), with all six review files present under their **prompt-declared** names — and assert the emitted manifest contains **only three** reviewers, missing `redteam`. If no bash ≥4.2 is available, record the filename mismatch as a static assertion from the two greps above and mark the item `PARTIAL`.
- **HARD-STOP / R3a:** The gate now blocks with no working remediation. **Per R3a**, grade this item **FAIL**, file the finding, and continue via the documented hatch (P3-022).
- **Evidence:** the `ls -l` mode; all four invocation attempts, verbatim; the two greps; the three-of-six mismatch table; the (optional) bash-5 manifest with only 3 entries.
- **→ This item catches BL-103 — both of its defects, plus the new mode-644 one.**

---

**`P3-022` — The review-gate attestation hatch (taken under protest, per R3a)**
- **Class:** AUTOMATED · **Enforced?** BLOCKS-with-hatch (`# BL-073-ESCALATE`)
- **POSITIVE:** `SOLO_REVIEWERS_ATTESTED=1 SOLO_REVIEWERS_ATTESTED_REASON="BL-103: run-reviews.sh cannot execute on bash 3.2 (parse error) and its redteam filename probe does not match the prompt-declared filename; no working remediation exists" bash scripts/check-phase-gate.sh` → must emit `[OK] Phase 3→4 review gate: … ATTESTED (reason: …) — recorded to .claude/process-state.json (not silenced).` and write `.claude/process-state.json::phase3.attestations.reviewers`.
- **⚠️ NEGATIVE (two arms):**
  1. `SOLO_REVIEWERS_ATTESTED=1` with a **whitespace-only** reason (`SOLO_REVIEWERS_ATTESTED_REASON="   "`) → must be **REJECTED** (the reason is trimmed before the non-empty test) → the gate must still FAIL. Prove the attestation cannot be a rubber stamp.
  2. `SOLO_REVIEWERS_ATTESTED=1` with **no** reason var at all → must not attest.
- **Note:** This is the framework working as designed — and it is *also* the whole complaint of BL-103: *"the framework herds every macOS operator into attesting past its own flagship security gate."* Record that the walk, following the framework's own instructions exactly, ended up attesting past the security review. **That sentence is the finding.**
- **Evidence:** the attestation record; both rejection probes.

---

**`P3-023` — The review manifest lives in a directory `init.sh` never creates**
- **Class:** ARTIFACT · **Enforced?** BLOCKS (the gate reads `docs/eval-results/review-manifest.json`)
- **POSITIVE:** n/a.
- **⚠️ NEGATIVE:** `ls -d docs/eval-results/` in the fresh project → **No such file or directory.** `grep -n 'eval-results' <framework>/init.sh` → **zero hits.** The operator must `mkdir` it themselves, with no instruction to do so. → **CM-H-13** (BL-105)
- **Evidence:** both commands.

---

**`P3-024` — Phase 3→4: penetration test (Standard → IT-Security exemption path)**
- **Class:** HUMAN/INFRA (SIMULATED) · **Enforced?** WARNS-and-blocks for Standard (`[WARN] Phase 3→4: No penetration test results or IT Security exemption found (standard track)` + `issues++`); **FAILs with no exemption path for Full**.
- **POSITIVE (the exemption path, which is what Standard is for):** Record an IT-Security exemption in `APPROVAL_LOG.md` — the gate greps `penetration.*exempted\|pen.*test.*exempted` (case-insensitive) — → `[OK] Penetration test exempted by IT Security (recorded in APPROVAL_LOG.md)`.
- **⚠️ NEGATIVE (three arms):**
  1. With **neither** results nor exemption → WARN + `issues++` → gate blocks.
  2. **The weakness:** the exemption check is a **bare grep over the whole file**, not a section-scoped, dated, role-verified check. Put the literal string `pen test exempted` in a code comment inside `APPROVAL_LOG.md` → **the gate accepts it.** Prove it. Contrast with `validate_approval_section_dated`, which the same script uses for the App Owner / IT Security rows — the framework *has* a section-scoped date validator and does not use it here. Record. → **CM-H-14**
  3. Provide a real result file (`docs/test-results/2026-07-12_pen-test_pass.md`) → `[OK] Penetration test results found`. Note the check is a **filename glob** (`*pen-test*`/`*pentest*`/`*penetration*`) — an empty file named `pen-test.md` passes.
- **Simulation note:** The agent plays **IT Security** granting the exemption. **A real run needs either a real third-party pen test, or a real IT-Security officer's documented, dated exemption decision.** The framework verifies neither — only that a matching string exists somewhere in the file.
- **Evidence:** all three probes.

---

**`P3-025` — Phase 3→4: Application Owner AND IT Security approvals (organizational)**
- **Class:** HUMAN (SIMULATED) · **Enforced?** WARNS-and-blocks — `validate_approval_section_dated "Application Owner Approval"` **AND** `validate_approval_section_dated "IT Security Approval"`; missing either → `[WARN] … requires a populated Date row in both … (missing: X)` + `issues++`.
- **POSITIVE:** Both subsections in `APPROVAL_LOG.md` (the org template ships them) carry a populated Date → `[OK] Phase 3→4: both Application Owner and IT Security approvals dated`.
- **⚠️ NEGATIVE:** Blank the IT Security Date → must WARN naming `IT Security` and block. Blank the Application Owner Date → must name it. Blank both → must name both. Restore.
- **Note:** This check is **section-scoped and date-validated** (unlike the pen-test grep in P3-024). It is one of the framework's **good** gates — call that out. It also *"runs regardless of the outer gate date check, so a freshly-generated empty template always surfaces a named WARN"* (per the code comment) — verify that on the fresh scaffold.
- **Simulation note:** Agent plays **Application Owner** and **IT Security** as two distinct named people. **A real run needs two real people, and the self-approval check (P0-003) would catch a single human signing both** — *if* they committed the rows themselves. Verify whether the self-approval check applies to these two rows as well, or only to the phase-gate Approver rows. Record.
- **Evidence:** all four probes.

---

**`P3-026` — Phase 3→4: `HANDOFF.md`, `docs/INCIDENT_RESPONSE.md`, `sbom.json`**
- **Class:** ARTIFACT · **Enforced?** WARNS-and-blocks — the artifact loop; each missing file `issues++`.
- **POSITIVE:** All three exist → three `[OK]` lines.
- **⚠️ NEGATIVE:** `mv HANDOFF.md /tmp/` → `[WARN] Phase 3→4: HANDOFF.md not found` and **the gate blocks** (R6). Repeat for the other two. Restore.
- **🔴 D-8 — THE ORDERING TRAP:** The builders-guide tells you to author `HANDOFF.md` in **Step 4.5** and `docs/INCIDENT_RESPONSE.md` in **Step 4.1.5** — *both inside Phase 4*. But this gate demands them **at Phase 3→4**, i.e. **before Phase 4 opens.** **A walker following the guide in order cannot pass this gate.** Record exactly what the walker had to do (author them early, out of the guide's order) and note that the guide gives no hint. NEW.
- **Evidence:** all three probes; a note recording the out-of-order authoring.

---

**`P3-027` — Phase 3→4: `SECURITY.md` — the template that is never shipped**
- **Class:** ARTIFACT · **Enforced?** WARNS-and-blocks (`# P4-013: SECURITY.md check`; `[WARN] Phase 3→4: SECURITY.md not found — required for production web/desktop/mobile apps` + `issues++`)
- **POSITIVE:** `SECURITY.md` exists → `[OK]`.
- **⚠️ NEGATIVE:** Remove it → WARN + block. Restore.
- **🔴 D-2:** `templates/generated/security.tmpl` **exists in the framework and is never shipped by `init.sh`.** `ls templates/generated/security.tmpl` in the project → absent. **The gate blocks on an artifact whose template the scaffold withholds.** The walker hand-authors it. NEW.
- **Evidence:** the gate probe; the absent template.

---

**`P3-028` — Phase 3→4: `docs/test-results/` non-empty (elevated to FAIL)**
- **Class:** ARTIFACT · **Enforced?** **BLOCKS (hard FAIL)** — `[FAIL] Phase 3→4: docs/test-results/ is empty` / `… directory not found`
- **POSITIVE:** Non-empty → `[OK] docs/test-results/ has N file(s)`.
- **⚠️ NEGATIVE:** `mkdir -p /tmp/save && mv docs/test-results/* /tmp/save/` → must hard-`[FAIL]`. Restore. Note: the check is `find -maxdepth 1 -type f` — **files in the `phase3/` subdir do not count.** Prove it: move everything into `docs/test-results/phase3/` only → the gate FAILs despite the scan summary being right there. Record.
- **Evidence:** both probes; the maxdepth quirk.

---

**`P3-029` — Phase 3→4: the release-pipeline TODO check**
- **Class:** ARTIFACT · **Enforced?** WARNS (`Release pipeline has $todo_count unconfigured TODO items in .github/workflows/release.yml`) — **verify the increment.**
- **POSITIVE:** Run it; record whether the scaffolded `release.yml` ships with TODOs (it likely does) and therefore whether **every fresh project blocks here**.
- **⚠️ NEGATIVE:** n/a.
- **Evidence:** the count; the rc.

---

**`P3-030` — The Phase 3→4 gate, all-green**
- **Class:** AUTOMATED · **Enforced?** BLOCKS
- **POSITIVE:** With everything satisfied, `bash scripts/check-phase-gate.sh; echo "rc=$?"` → **rc=0**. **This is the walk's single most important positive result:** it proves the whole gate *can* be passed by an honest operator. If it cannot — if some check is unsatisfiable — that is the biggest possible finding.
- **⚠️ NEGATIVE:** n/a (this is the aggregate).
- **Evidence:** the full green gate output, verbatim, with rc=0. **Also record how many of the passing checks were satisfied by an attestation rather than by real work** — that ratio is the honest measure of the framework's Phase-3 rigor.
- **Evidence:** the gate output + an attestation tally.

---

**`P3-031` — The Phase 3→4 snapshot**
- **Class:** AUTOMATED · **Enforced?** No block
- **POSITIVE:** `ls docs/snapshots/phase-3-to-4_*/` → contains the 10 artifacts of the `3-4)` arm (`PRODUCT_MANIFESTO`, `PROJECT_BIBLE`, `FEATURES`, `CHANGELOG`, `BUGS`, `USER_GUIDE`, `HANDOFF`, `RELEASE_NOTES`, `APPROVAL_LOG`, `sbom.json`) + `INCIDENT_RESPONSE.md` + a `test-results-listing.txt`.
- **⚠️ NEGATIVE:** n/a.
- **Evidence:** the listing.

---

## 9 · Phase 4 — Release & Maintenance

🔴 **Be precise about what is and is not missing here** — an imprecise grep gets
this wrong, and the imprecise version is easy to write:

| Claim | Grep | Truth |
|---|---|---|
| "There is no Phase 3→4 gate" | `grep -c 'phase_3_to_4' scripts/check-phase-gate.sh` → **9** | ❌ **FALSE.** The 3→4 gate exists and is the **most heavily enforced gate in the framework** (dual approvals, pen test, BL-070 scanner autorun, BL-073 review manifest, artifact roster, POC hard-block). All of §8.3 above. |
| "There is no `phase4_release` cross-check" | `grep -c 'phase4_release' scripts/check-phase-gate.sh` → **0** (vs `phase3_validation` → **1**, the P3-007 cross-check) | ✅ **TRUE.** The gate cross-references the **Phase-3** process checklist but has **no equivalent for Phase 4**. Nothing ever asks whether the six `phase4_release` steps were done. |
| "There is no gate *out of* Phase 4" | `_cpg_parse_gate_value` accepts exactly `phase_0_to_1 \| phase_1_to_2 \| phase_2_to_3 \| phase_3_to_4` | ✅ **TRUE.** Phase 4 is **terminal**. There is no `phase_4_to_released`. |

**So: the framework gates you hard on the way IN to Phase 4, and then never
looks at you again.** (This is BL-105's precise claim.) The only Phase-4
enforcement anywhere is `process-checklist.sh`'s per-step artifact arms and
`--finalize-phase 4` — **and nothing forces you to run either** (X-010).

---

**`P4-001` — `--start-phase4` advances to Phase 4 with NO gate consult**
- **Class:** AUTOMATED · **Enforced?** **BLOCKS only on `poc_mode`** — `start_phase4()` checks `poc_mode` and nothing else, then `_set_current_phase_min 4`.
- **POSITIVE:** `bash scripts/process-checklist.sh --start-phase4` → rc=0; `jq '.current_phase'` → `4`.
- **⚠️ NEGATIVE (two arms):**
  1. **The POC block (which IS real):** `jq '.poc_mode="sponsored_poc"' .claude/phase-state.json` → `--start-phase4` → must **FAIL** with `Phase 4 (production release) is blocked — project is in sponsored poc mode.` Restore to `null`. ✅ This gate works.
  2. **The gate that isn't (X-010):** From a state where `check-phase-gate.sh` **FAILs**, run `--start-phase4` → **it succeeds anyway.** `current_phase` becomes 4. **Nothing consulted the Phase 3→4 gate.** Record with the gate's failing output side by side with the successful advance.
- **Evidence:** both probes; the failing gate + the successful advance, together.

---

**`P4-002` … `P4-007` — The six `phase4_release` steps**
`production_build`, `rollback_tested`, `go_live_verified`, `monitoring_configured`, `handoff_written`, `handoff_tested`

---

**`P4-002` — `phase4_release:production_build`**
- **Class:** AUTOMATED · **Enforced?** BLOCKS (sequencing) — **no artifact-check arm**
- **POSITIVE:** Produce a real production build of the note-keeper; `--complete-step`.
- **⚠️ NEGATIVE:** Complete it having built nothing → succeeds. No arm. Record.
- **Evidence:** the no-op completion; the real build output.

---

**`P4-003` — `phase4_release:rollback_tested` (guide: "MUST"; "a rollback procedure that has never been tested is not a rollback procedure — it is a hope")**
- **Class:** INFRA (SIMULATED) · **Enforced?** **BLOCKS** (artifact arm) — needs `docs/test-results/*rollback*`
- **POSITIVE:** Actually deploy the note-keeper locally, actually roll it back, record the result to `docs/test-results/2026-07-12_rollback-test.md`. `--complete-step` → succeeds.
- **⚠️ NEGATIVE:** Without the file → FAIL with `No rollback test results found in docs/test-results/.` **Then:** `touch docs/test-results/rollback.md` (empty) → **the arm passes.** The check is a filename glob. **An empty file named `rollback` satisfies the framework's "MANDATORY rollback test".** Record. → **CM-H-15**
- **🔴 D-2:** `templates/generated/rollback-test.tmpl` exists and is **never shipped**. Confirm absent.
- **Simulation note:** The walk performs a **real local rollback** (deploy v1 → deploy v2 → roll back to v1 → verify data integrity). **A real run needs production or a production-equivalent environment** (the guide says so explicitly) and would additionally verify the data-model rollback against realistic data — the walk's SQLite file is small and synthetic.
- **Evidence:** the real rollback transcript; the empty-file probe; the absent template.

---

**`P4-004` — `phase4_release:go_live_verified` (DECISION GATE)**
- **Class:** HUMAN (SIMULATED) · **Enforced?** **BLOCKS** (artifact arm) — needs `RELEASE_NOTES.md`
- **POSITIVE:** `RELEASE_NOTES.md` exists (template `release-notes.tmpl` **is** shipped) → `--complete-step` succeeds.
- **⚠️ NEGATIVE:** Remove it → FAIL. Restore.
- **🔴 The platform go-live checklist is checked by NOTHING (BL-106):** the guide marks `docs/platform-modules/web.md`'s go-live checklist **"⟁ PLATFORM MODULE — MANDATORY"**. `grep -rn 'platform-modules' scripts/` → **assert zero parsing hits.** No script reads the platform checklists. The walker completes the web checklist by hand and records that nothing verified it. → **CM-H-16** (BL-106)
- **Simulation note:** Agent plays the Orchestrator doing the manual walkthrough. **A real run needs a human on each target platform** (per the guide, "each"). The framework checks only that `RELEASE_NOTES.md` exists.
- **Evidence:** both probes; the platform-modules grep.

---

**`P4-005` — `phase4_release:monitoring_configured` (guide: "'Configured' is not 'verified'")**
- **Class:** INFRA (SIMULATED) · **Enforced?** **BLOCKS** (artifact arm) — `HANDOFF.md` must **grep-match** `monitoring|error tracking|sentry|crashlytics|uptimerobot`
- **POSITIVE:** Document the monitoring tool, dashboard URL, and alert channel in `HANDOFF.md` § 8 → `--complete-step` succeeds.
- **⚠️ NEGATIVE (the load-bearing one):** Write the single word **`monitoring`** into `HANDOFF.md` — nothing else — → **the arm passes.** The framework's entire monitoring-verification gate is `grep -qi "monitoring\|..."` against one file. The guide demands *"trigger a test error and verify the alert is received"* and calls an untested setup *"indistinguishable from no monitoring"* — **and then checks for the presence of a word.** Record. → **CM-H-17** (BL-105)
- **Simulation note:** No real Sentry/UptimeRobot. The walk **does** stand up a local error-tracking stub and **does** trigger a real test error against it, recording the alert payload — so the *behavior* is exercised even though the *service* is simulated. **A real run needs a real monitoring service, a real alert rule, and a real alert received by a real human on a real channel.** The framework verifies none of this and cannot.
- **Evidence:** the one-word probe (the load-bearing evidence); the real triggered-error transcript.

---

**`P4-006` — `phase4_release:handoff_written`**
- **Class:** ARTIFACT · **Enforced?** **BLOCKS** (artifact arm) — `HANDOFF.md` must exist
- **POSITIVE:** All 9 sections present (template `handoff.tmpl` **is** shipped) → succeeds.
- **⚠️ NEGATIVE:** `mv HANDOFF.md /tmp/` → FAIL. Restore. Note: the arm checks **existence only** — a `HANDOFF.md` containing the single word `monitoring` satisfies both this arm and P4-005.
- **Evidence:** both probes.

---

**`P4-007` — 🔴 `phase4_release:handoff_tested` — the step the guide never names**
- **Class:** HUMAN (SIMULATED) · **Enforced?** **BLOCKS** (artifact arm) — needs `docs/test-results/*handoff*`
- **POSITIVE:** Have a "backup maintainer" attempt dev-env setup + issue triage using only `HANDOFF.md`; record gaps to `docs/test-results/2026-07-12_handoff-test.md`. `--complete-step` → succeeds.
- **⚠️ NEGATIVE:** Without the file → FAIL with `No handoff test results found… Have a backup maintainer test the handoff procedure.`
- **🔴 D-6:** **`handoff_tested` is in `PHASE4_STEPS` but the builders-guide never names it as a step ID** (`grep -o 'phase4_release:[a-z_]*' docs/builders-guide.md` returns only 5). **A walker following the guide completes 5 of 6 and `--finalize-phase 4` blocks them** with a step they were never told about. Prove it: run `--finalize-phase 4` with the 5 guide-declared steps complete → must FAIL naming `handoff_tested`. NEW.
- **🔴 D-2:** `templates/generated/handoff-test-results.tmpl` exists and is **never shipped**. Confirm absent.
- **Simulation note:** The agent plays the **backup maintainer**, reading only `HANDOFF.md` in a fresh context. This is a genuinely useful simulation (a fresh-context agent is a decent proxy for a new human). **A real run needs a real second human** — the governance framework mandates a designated backup maintainer, and the whole point is that they are *not* the person who wrote the doc.
- **Evidence:** the `--finalize-phase 4` FAIL naming `handoff_tested`; the guide grep (5 IDs) vs the code (6); the absent template.

---

**`P4-008` — `--finalize-phase 4` — the only Phase-4 aggregate check**
- **Class:** AUTOMATED · **Enforced?** **BLOCKS** — `[FAIL] Phase N step 'X' not completed.` per missing step, then `[FAIL] N step(s) missing. Phase 4 cannot be finalized.`
- **POSITIVE:** With all 6 complete → `[OK] Phase 4: all 6 steps complete. Safe to tag/release.`
- **⚠️ NEGATIVE (two arms):**
  1. With 5 of 6 → must FAIL naming the missing one (see P4-007).
  2. **The real question:** *does anything require `--finalize-phase 4` to be run before a release is tagged?* `grep -rn 'finalize-phase' scripts/ templates/ .github/ init.sh` → **assert whether the scaffolded `release.yml` invokes it.** If it does not, then the framework's only Phase-4 aggregate check is, like `check-phase-gate.sh`, a script nobody runs. Record. → **CM-H-18**
- **Evidence:** both probes; the invocation grep.

---

**`P4-009` — Step 4.4 Ongoing Maintenance Cadence**
- **Class:** HUMAN · **Enforced?** UNENFORCED (declared only) — no `process-checklist` step ID; `scripts/check-maintenance.sh` exists but nothing schedules it.
- **POSITIVE:** `bash scripts/check-maintenance.sh` → runs. Record its output.
- **⚠️ NEGATIVE:** Nothing invokes it. Confirm via `grep -rn 'check-maintenance' scripts/ .github/ templates/ init.sh`.
- **Simulation note:** Weekly/monthly/quarterly/biannual cadences cannot be walked in a day. `SIMULATED` — the walk runs the script once and records what it *would* check. **A real run is a calendar commitment, not a command.**
- **Evidence:** the run; the invocation grep.

---

**`P4-010` — Phase 4 is never cross-checked and is terminal — the closing assertion**
- **Class:** AUTOMATED · **Enforced?** **UNENFORCED** → **CM-H-19** (BL-105)
- **POSITIVE:** n/a.
- **⚠️ NEGATIVE (three greps, all required — state them precisely; the sloppy version of this claim is wrong):**
  1. `grep -c 'phase_3_to_4' scripts/check-phase-gate.sh` → **9**. **The gate INTO Phase 4 exists and is the framework's strongest.** Do not claim otherwise.
  2. `grep -c 'phase4_release' scripts/check-phase-gate.sh` → **0**, versus `grep -c 'phase3_validation'` → **1**. **The gate cross-checks the Phase-3 process checklist and has no equivalent for Phase 4.** Nothing, anywhere, ever asks whether `production_build` / `rollback_tested` / `go_live_verified` / `monitoring_configured` / `handoff_written` / `handoff_tested` were completed — unless the operator voluntarily runs `--finalize-phase 4` (P4-008).
  3. `_cpg_parse_gate_value` accepts exactly four gates: `phase_0_to_1 | phase_1_to_2 | phase_2_to_3 | phase_3_to_4`. **There is no gate out of Phase 4.** `current_phase=4` is terminal.
- **Record:** the framework gates you hard on the way *in* to Phase 4 — and then never looks at you again. Combined with X-010 (nothing invokes the gate at all) and P4-001 (`--start-phase4` advances without consulting it), **the walk should be able to reach `current_phase=4` and tag a release having satisfied nothing.** Attempt exactly that on a scratch copy and report whether it succeeds.
- **Evidence:** all three greps, verbatim; the scratch-copy walk-to-4-with-nothing-satisfied result.

---

## 10 · Results template

The walker fills this in a **separate file** — `Reports/2026-07-12-e2e-walk/RESULTS.md` —
created at walk time. **Do not edit this checklist during the walk** (R4).

```markdown
# E2E Validation Walk — Results
**Walked:** YYYY-MM-DD  **Walker:** <agent/model>  **Host:** <uname -a>
**Bash:** <bash --version | head -1>   **Tools real:** …   **Tools mocked:** …
**Framework HEAD:** <sha>  (before == after: YES/NO)

## Tally
| Phase | PASS | PARTIAL | FAIL | BLOCKED | SIMULATED | Total |
|---|---|---|---|---|---|---|
| Setup (S) | | | | | | |
| Cross-cutting (X) | | | | | | |
| Phase 0 | | | | | | |
| Phase 1 | | | | | | |
| Phase 2 | | | | | | |
| Phase 3 | | | | | | |
| Phase 4 | | | | | | |
| **TOTAL** | | | | | | |

## Items
| ID | Status | Evidence | Notes |
|---|---|---|---|
| S-001 | PASS | `diff` empty (see §Evidence/S-001) | |
| … | | | |

## Findings (new, not already filed)
| # | Item ID | Severity | What | Proposed BL |
|---|---|---|---|---|

## Attestation tally (the honest measure)
| Gate | Passed by real work | Passed by attestation |
|---|---|---|

## Evidence appendix
### S-001
```
<exact command>
<exact output>
```
…
```

**Status vocabulary — use exactly these five:**

| Status | Means |
|---|---|
| `PASS` | You ran the positive assertion **and** the negative assertion, and both behaved as specified. |
| `PARTIAL` | Declared behavior and observed artifact disagree, **or** you ran the positive but could not run the negative. Default here when unsure (R1). |
| `FAIL` | A gate that should have fired did not, or a documented remediation did not work. |
| `BLOCKED` | You could not run the item at all. Say why. If you continued via a documented hatch, write `BLOCKED → ATTESTED-CONTINUE` and cite the attestation (R3a). |
| `SIMULATED` | A HUMAN or INFRA item the agent stood in for. **Must** carry the "what a real run additionally requires" note. |

---

## 11 · Coverage map — what this walk does NOT test

Karl asked for **one basic project, no edge cases.** That is the right call for a
first walk. Here is what it honestly leaves untested. **Nothing below should be
described as "validated" after this walk.**

### Exercised

| Surface | Coverage |
|---|---|
| `--platform web` | ✅ full |
| `--language typescript` | ✅ full |
| `--deployment organizational` | ✅ full (max governance) |
| `--track standard` | ✅ full |
| `--gov-mode production` (no POC) | ✅ full |
| `--git-host github` (driver **not** exercised — see below) | ⚠️ partial |
| Phases 0 → 4, all four gates | ✅ full |
| BL-072 TDD hard block (non-bypassable tier) | ✅ full, incl. the BL-088 reproduction |
| BL-070 five scanners + attest-on-skip + BL-082 staleness | ✅ full (snyk/zap simulated) |
| BL-073 review gate | ✅ full (via the BL-103 blocker) |
| BL-084 push gate | ⚠️ via a **local bare repo**, not a real remote |
| BL-086 license deny + dual-license FP hygiene | ✅ full (real npm deps) |
| ZDR / data-classification gate | ✅ full (all four arms) |
| Build Loop + UAT state machines | ✅ full |

### NOT exercised — and therefore NOT validated

| Surface | Why it matters |
|---|---|
| **Every other platform** (`mobile`, `desktop`, `mcp_server`, `embedded`, `other`) | The platform modules carry ~66 MUST/MANDATORY items between them (mobile alone ~38) and **nothing parses any of them** (BL-106). Untested here. |
| **Every other language** — especially **`rust`** and **`other`** | 🔴 **D-9: the TDD commit-msg hook is NOT INSTALLED for `rust` or `other`** (the `case "$LANGUAGE"` arm leaves `test_pattern` empty, and `install_tdd_commit_msg_hook` is called only when it is non-empty). **A Rust organizational project silently gets no TDD gate at all.** That is BL-088's failure mode, still live, on an axis this walk does not touch. **This deserves its own walk.** |
| **`--track light`** and **`--track full`** | Light is where the review gate degrades to WARN-only and where BL-104's empty-manifest bypass actually bites in production. Full is where the pen test has **no** exemption path and all six reviewers are required. Neither is walked. |
| **Both POC modes** (`private_poc`, `sponsored_poc`) | The Phase-4 hard block, the bypassable TDD tier, and the `--to-production` upgrade path. Only the *negative* probes (P4-001, X-004) touch these, and only by mutating state — never by a real init. |
| **`--deployment personal`** | The `approval-log-personal.tmpl` path — which **lacks the pen-test and attorney sections the track-keyed gates demand** (BL-105's "deployment-vs-track orthogonality" hole). Untested. |
| **`upgrade-project.sh`** (all paths) | ~2,500 lines. `--to-production`, `--to-sponsored-poc`, `--backfill-only`. The entire migration surface. Untested. |
| **`reconfigure-project.sh`** | Untested. |
| **`--git-host gitlab` / `bitbucket` / `other`** | Three host drivers, three API surfaces, three branch-protection implementations. The `other` path in particular. Untested. |
| **Real remote creation + real branch protection** | The walk is hermetic by mandate. **P1-013's branch-protection backstop is effectively unexercised** — it takes the WARN-and-skip path. The one gate we most want to trust on an organizational project is the one we cannot test without a live remote. **This is the walk's biggest structural blind spot.** |
| **The human-in-the-loop wait** | The framework's design says the agent *dispatches UAT and waits*. The walk collapses that to zero. We cannot validate what happens when a human takes three days to respond, or responds partially, or contradicts the agent. |
| **Multi-session / context-handoff** | `resume.sh`, `check-session-state.sh`, `session-*` hooks, the out-of-band-commit detector. A one-session walk cannot exercise them. |
| **CDF integration** (`~/.claude-dev-framework`) | Present as a hard dependency; its hooks and asset sync are not probed. |
| **The `intake-wizard.sh` interactive path** | We use it for `data_classification` (P1-011) but do not walk its full ~2,250-line interactive flow. |
| **Real third-party services** | Snyk (mocked), Sentry/monitoring (stubbed), a real pen test (exempted), a real attorney (simulated), a real STA/App-Owner/IT-Security (simulated). **Every human approval in this walk is one agent wearing four hats.** The self-approval detector (P0-003) is the only thing that would catch that in reality — and it only works because the walker deliberately used different *name strings*. |

### The honest one-liner

> This walk validates **one cell** of a matrix with at least
> **6 platforms × 9 languages × 3 tracks × 2 deployments × 3 gov-modes × 4 git-hosts**.
> It is the *right* cell — the maximum-enforcement one — and it will find real
> bugs. It is not coverage.

---

## 12 · Would-it-have-caught-them (the acceptance criterion)

The test of this checklist is whether a walker following it **faithfully** would
have caught all four motivating bugs. Item-by-item:

### 🔴 BL-088 — `init.sh` never shipped `tdd-classify.sh`; the TDD hard block silently no-opped

**Caught by: `X-001` (primary), `X-004` (confirming), `X-011` (healing path).**

- **`X-001`'s negative assertion is the exact reproduction:** remove
  `scripts/lib/tdd-classify.sh` from the **real scaffold** and attempt the
  test-less `feat:` commit. It is **ALLOWED** — because `tdd_terminal_enforce`
  opens with `command -v _tdd_triggers … || return 0   # classifier absent -> no-op (safe)`.
  The walker sees `rc=0` on a commit that must be blocked.
- **Why it catches what 100+ tests missed:** X-001 runs against a **real
  `init.sh` scaffold**, never a fixture. Every BL-072 test `cp`'d the lib into
  its own fixture, so the fixture supplied what the product withheld. The walk
  *cannot* do that — `S-002`/`S-004` mandate a real init, and `R3`/`R4` forbid
  hand-supplying any artifact the product should have produced.
- **`X-004`'s three-arm negative** independently proves the gate is alive,
  tier-keyed, and not a paper tiger — so a *dead* gate cannot masquerade as a
  passing one.
- **The generalized catch:** X-001's positive assertion counts **all 11**
  `scripts/lib/` files and asserts `run-phase3-validation.sh` is executable.
  That would have caught all **four** BL-088 instances (`tdd-classify.sh`,
  `run-phase3-validation.sh`, `phase2-state.sh`, `cdf-refresh.sh`), not just the
  headline one.

### 🔴 BL-102 — Market Signal (Step 1.1.5) is a DECISION GATE with no slot and no check

**Caught by: `P1-002` (primary), `P1-001` (the Go/No-Go sibling), `P0-010`/`P0-011`/`P0-012` (the same class in Phase 0).**

- **`P1-002` is written to fail to comply.** Its "positive assertion" is four
  greps, all of which return **zero hits**:
  `grep -ril 'market signal' templates/` (no slot),
  `grep -rliE 'market.?signal' scripts/` (no check),
  the manifesto's appendices are **A/B/C with no D**,
  and `phase-state.json` has no key.
- **Its negative assertion is the finding:** *complete the entire walk, through
  Phase 4, with zero market signal recorded — and watch every gate pass.*
- **The walker is explicitly required to record "did the framework ever prompt me
  for this?"** — which is the exact question that turns an unenforced step into a
  *hollow* one. `P0-010`/`P0-011`/`P0-012` apply the same probe to Appendices
  A/B/C (invisible to `validate_manifesto_content`'s `1..8` loop), and `P1-001`
  to the Go/No-Go. **The class, not just the instance, is caught.**
- **`P2-027` is the control:** a declared-but-unenforced step the docs *honestly
  label* as not-a-gate. Comparing P1-002 against P2-027 is what distinguishes
  "correctly advisory" from "hollow."

### 🔴 BL-103 — the six-eval generator is dead on arrival (bash-3.2 + slug/filename mismatch)

**Caught by: `P3-021` (primary), `P3-022` (the forced-attestation consequence), `X-013` (the linter's blind spot), `P3-023` (the missing directory).**

- **`P3-021` forces the walker to RUN THE GENERATOR** — the one thing
  `tests/test-bl073-review-manifest-gate.sh` never does. Five ordered probes:
  the `ls -l` (mode **644** — a **new** third defect), `./run-reviews.sh`
  (Permission denied), `bash run-reviews.sh` (bash-3.2 syntax error at the
  `declare -A` / `[[ -v ]]` lines), `/bin/bash -n` (proving it is a **parse-time**
  death), and the same for `compose.sh`.
- **Its negative assertion catches Defect 2 independently** — the slug-vs-filename
  mismatch that bites on bash 5 too. Two greps produce the three-of-six table,
  including **`redteam-review-v1.md` (probed) vs `red-team-review-v1.md`
  (written)** — and Red Team is a **mandatory blocking reviewer**. So a Red Team
  review that *was performed and saved exactly as instructed* is recorded as
  missing and the gate FAILs.
- **The rule that makes it uncatchable-to-miss:** **R3 forbids hand-writing the
  manifest.** That prohibition is stated twice (R3 and P3-021's opening line) and
  is named as *"precisely the sin that hid BL-103."* A walker who hand-wrote the
  manifest — as the unit test does — would sail past. A walker following this
  checklist cannot.
- **`P3-022` records the consequence in the framework's own words:** the walk,
  following the framework's instructions exactly, **ends up attesting past its own
  flagship security review.** That sentence is the finding.

### 🔴 BL-104 — zero Phase-3 steps silently PASSES; an empty manifest is a bypass

**Caught by: `P3-019` (arm 1), `P3-020` (arm 2), and walker rule `R6` (the `[WARN]`-that-blocks trap).**

- **`P3-019` is a three-state differential probe, and the assertion is the
  *comparison*, not any single run:**
  `steps_completed = []` (zero) → **the arm emits nothing and does not increment
  `issues`** → the gate passes. `steps_completed = [8 of 9]` → `[WARN] … 8/9` →
  `issues++` → the gate **BLOCKS**. **Zero passes; eight blocks.** A walker who
  ran only the 9-of-9 happy path would never see it — which is why the item
  mandates all three runs and all three exit codes.
- **`P3-020` reproduces arm 2 by constructing the ungrandfathered case:** with
  `review_gate_enforced=false`, **no manifest BLOCKS** (the WARN arm increments)
  but **`{"reviews":[]}` PASSES** (the incomplete-manifest WARN arm does not
  increment). Writing an empty file converts a blocking gate into a passing one.
- **`R6` generalizes the third finding** — that `[WARN]` vs `[FAIL]` in
  `check-phase-gate.sh` is **cosmetic**, because the exit predicate is
  `if [ $issues -eq 0 ]`. Every item in this checklist that names a `[WARN]`
  therefore also names whether it increments, and **R7** requires the walker to
  grade on the **exit code**, never the label. That is what stops the *next*
  scoring inversion from hiding.

### Summary

| Bug | Primary item | Supporting items | The assertion that catches it |
|---|---|---|---|
| **BL-088** | `X-001` | `X-004`, `X-011` | Remove the lib from a **real scaffold** → the test-less `feat:` commit is **ALLOWED** (`rc=0`). Never a fixture. |
| **BL-102** | `P1-002` | `P1-001`, `P0-010`–`P0-012`, control: `P2-027` | Four greps returning **zero hits**; then a full walk to Phase 4 with **no market signal**, all gates green. |
| **BL-103** | `P3-021` | `P3-022`, `P3-023`, `X-013` | **Run the generator.** Parse error on bash 3.2 + the `redteam` vs `red-team` filename mismatch. **Never hand-write the manifest.** |
| **BL-104** | `P3-019`, `P3-020` | rule `R6`, rule `R7` | The **differential**: 0 steps passes, 8 steps blocks. Empty manifest passes, absent manifest blocks. |

**All four are caught. The acceptance criterion is met.**

### ⚠️ Two of the four are now FIXED — and that makes the criterion *stronger*, not weaker

**PR #187 merged while this checklist was being written**, fixing BL-103 and
BL-104. A reasonable objection: *"then P3-019/020/021 no longer catch anything."*

**They catch exactly as much as they did before.** The probes are byte-for-byte
unchanged; only the **expected result** flipped:

| | Before #187 | After #187 |
|---|---|---|
| `P3-019` | 0 steps **passes** ← the bug | 0 steps **blocks** ← the fix |
| `P3-021` | generator **dies** ← the bug | generator **runs** ← the fix |

> **This is the whole thesis of the document, demonstrated by accident:**
> **an assertion strong enough to catch a bug is, unchanged, the assertion that
> proves its fix holds.** A checklist built only of positive assertions would have
> passed *before* the fix and *after* it, learning nothing either time. This one
> distinguishes the two states — which is the only property that ever mattered.

**And the walk still adds something the fix's own tests do not:** `tests/test-bl103-eval-generator.sh`
(shipped by #187) validates the generator, but the walk runs it **in a real
`init.sh` scaffold**, against a **real project**, with the **real gate** reading
the **real manifest**. That end-to-end path — the one BL-088 proved a fixture
cannot stand in for — is still only exercised by `P3-021`.

**BL-102 remains OPEN**, so `P1-002` is still a live bug-reproduction. **BL-088
remains the archetype**, and `X-001` still reproduces it on demand.

---

## 13 · Item count

| Section | Items | ID range |
|---|---|---|
| §0 Setup (`S-*`) | 6 | `S-001`–`S-006` |
| Cross-cutting (`X-*`) | 18 | `X-001`–`X-018` |
| Phase 0 (`P0-*`) | 16 | `P0-001`–`P0-016` |
| Phase 1 (`P1-*`) | 14 | `P1-001`–`P1-014` |
| Phase 2 (`P2-*`) | 27 | `P2-001`–`P2-027` |
| Phase 3 (`P3-*`) | 31 | `P3-001`–`P3-031` |
| Phase 4 (`P4-*`) | 10 | `P4-001`–`P4-010` |
| **Total** | **122** | |

**By class:** `AUTOMATED` 62 · `ARTIFACT` 27 · `HUMAN` (→ SIMULATED) 20 · `INFRA` (→ SIMULATED) 13.

**By enforcement:** `BLOCKS` 71 · `WARNS` 9 · `UNENFORCED (declared only)` 21 · walk-discipline / inventory 21.

**Every one of the 71 `BLOCKS` items carries a negative assertion.** That is the
contract. An item with only a positive assertion passes even when the gate is
dead — which is exactly how BL-088, BL-103, and BL-104 shipped green.

### The 21 `UNENFORCED (declared only)` items — and their `CODE-VS-MANUAL.md` rows

Every one of these is a place where the framework **tells the operator to do
something and then never checks**. For each, the walker records the extra
question: *did the framework even prompt me for this?* Both directions of the
same finding:

| Item | What is declared | CM row |
|---|---|---|
| `X-010` | "Phase gates are CI-enforced" — but nothing invokes the gate | **CM-H-01** |
| `X-012` | The Competency Matrix enforcement (`validate.sh::check_competency`, never invoked) | **CM-H-06** |
| `X-016` | `SOIF_PHASE_GATES=warn` — the master bypass | **CM-U-06** |
| `X-017` | The 9-hatch bypass inventory | **CM-U-06** |
| `X-018` | `SOIF_FORCE_STEP` — undocumented, voids the kickoff promise | **CM-U-03** |
| `P0-010` | Step 0.5 Revenue Model → Appendix A (Standard+ **Required**) | **CM-H-04** |
| `P0-011` | Step 0.6 Competency Matrix → Appendix B (**Required, all tracks**) | **CM-H-05** |
| `P0-012` | Step 0.7 Trademark & Legal → Appendix C (Standard+ **Required**) | **CM-H-04** |
| `P0-013` | The Phase-0 Artifact Map mis-maps A/B/C to §6/7/8 | **CM-D-02** |
| `P1-001` | Step 1.1 Business Strategy **DECISION GATE** (Go/No-Go) | **CM-H-03** |
| `P1-002` | **Step 1.1.5 Market Signal — DECISION GATE** | **CM-H-03** (= **BL-102**) |
| `P1-003` | Step 1.2 Architecture **DECISION GATE** → ADR | **CM-H-07** |
| `P1-005` | Step 1.4 Data Model → Bible §5 | **CM-H-07** |
| `P1-007` | Step 1.5 UI/UX four states → Bible §9 | **CM-H-07** |
| `P1-010` | Senior Technical Authority — named approver, **no named-role check** | **CM-H-08** |
| `P2-027` | Mid-Phase 2 Governance Checkpoint (**the honest control case** — docs correctly say "not a gate") | **CM-H-09** |
| `P3-005` | Lighthouse **≥ 90** threshold — checked by nothing | **CM-H-10** |
| `P3-009` | Step 3.6 Final UAT sign-off — no template section | **CM-H-11** |
| `P4-004` | Platform-module go-live checklist — **"MANDATORY"**, parsed by nothing | **CM-H-16** (= **BL-106**) |
| `P4-009` | Step 4.4 Maintenance cadence — `check-maintenance.sh` invoked by nothing | **CM-H-18** |
| `P4-010` | No `phase4_release` cross-check; Phase 4 is terminal | **CM-H-19** (= **BL-105**) |
