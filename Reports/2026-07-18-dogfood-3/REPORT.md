# Project Dogfood 3 — Final Report

**Run:** 2026-07-18, one continuous fresh walker agent (Fable-tier), per `DOGFOOD-3-PROMPT.md`.
**Framework under test:** `main` @ `528f5b2` (post-remediation: PRs #199–#215 all merged).
**Companion files:** `LEDGER.md` (step-by-step, written as-it-went) · `FINDINGS.md` (F-DF3-001…005 with repro commands).
**Walker's scratch dir of record:** `/var/folders/35/…/T/dogfood3.1fYeam` (collected here).

## 1. Repo + tag + proof

- **Repo:** https://github.com/kraulerson/project-dogfood-3 (PRIVATE, created by real `init.sh`)
- **Final tag:** `v1.0.0` (annotated, pushed) → GitHub Release `v1.0.0` (not draft) with assets `dogfood-reader-3-v1.0.0.zip` + `sbom.json`; the Release workflow ran **green**.
- `gh repo view` (verbatim): `{"defaultBranchRef":{"name":"main"},"isPrivate":true,"name":"project-dogfood-3","pushedAt":"2026-07-18T20:59:47Z","url":"https://github.com/kraulerson/project-dogfood-3","visibility":"PRIVATE"}` — remote tags: `v1.0.0`; real commits from `chore: initialize` through `v1.0.0`, all pushed.

## 2. The app — do the 3 features work, and how tested

Yes, all three, verified in a real browser against the production build.
- **F1 Open & display** — `.txt` picker → client-side FileReader → render; `.txt`/10 MB guards, empty-file state, prior-doc-preserved on rejection.
- **F2 Find in document** — literal case-insensitive search, "k of N" counter, `<mark>` highlight, next/prev with wrap; renders XSS-inert.
- **F3 Font size** — A−/A+ 12–28 px, bound-disable, persisted to `localStorage` across reloads; corrupt-value fallback; private-mode notice.

**How tested:** 41 Vitest unit tests + full-app jsdom integration + **7 Playwright/Chromium E2E against `vite preview` (7/7)** + a real screenshot (`docs/test-results/2026-07-18_app-screenshot.png` in the project repo) showing `budget` highlighted 5× and `<script>…</script>`/`<img onerror>` rendered as **inert visible text**. Lighthouse **accessibility 100, performance 100**.

## 3. THE CENTRAL QUESTION — answered with evidence

> When the POC is promoted, does the framework FORCE the operator back through the stricter gates the POC tier skipped or only warned about?

**YES — the ratchet now holds, with real machinery. Dogfood-2's central-question hole (F-DF2-014) is CLOSED.**

- Built as private-POC/Light; POC mode **blocked Phase 4** (verbatim): `::error::Phase 4 (production release) is BLOCKED — project is in private poc mode. … To unlock Phase 4: bash scripts/upgrade-project.sh --to-production`.
- `upgrade-project.sh --to-production --track full` removed POC, bumped track→full. **The BL-124 ratchet rewrote Appendices A (Revenue), C (Trademark), AND D (Market Signal) from "SKIPPED" → "PENDING — required by track upgrade light → full on 2026-07-18".**
- **The gate READS the marker (the fix):** `check-phase-gate.sh` `# BL-124-PENDING-RATCHET` greps the manifesto for the PENDING literal and FAILs (`issues+1`), guarded by `current_phase>=4`. Confirmed `[OK] BL-124: no PENDING promotion markers` only after all three were resolved.
- Promotion additionally **re-demanded and enforced**: `[FAIL] Phase 3→4: Full Track requires penetration test — no exemption path available` (Light skipped it entirely); the review gate flipped Light-WARN → Full-FAIL (Security + Red Team mandatory); release-pipeline TODOs; k6/ZAP tooling.
- **Nuance:** BL-102 (Market Signal) is WARN-only by design (never increments `issues`) and credits the PENDING text as `[OK]` — it only WARNs on the *template*-placeholder pattern (that path proven to fire). The real enforcement of Appendix D's obligation therefore comes from BL-124 (which also marks App D PENDING), not BL-102. Net: the obligation is enforced; BL-102 alone would not have.

## 4. Fix-checkpoint scorecard — 20/20 HELD, zero REGRESSED, zero UNTESTABLE

| BL | Verdict | Verbatim evidence |
|---|---|---|
| **BL-118** (DOM-XSS SAST) | **HELD** | Naive `pane.innerHTML=html` commit REFUSED by git: `❯❯❱ …insecure-document-method …❰❰ Blocking ❱❱ … 42┆ pane.innerHTML = html` → `[BLOCKED] Semgrep detected security issues`, exit 1, HEAD unmoved |
| **BL-119** (stale-msg classifier) | **HELD** | `docs(frd)` commit `0596166` landed clean immediately after a `feat` commit |
| **BL-133** (stale COMMIT_EDITMSG) | **HELD** | subsumed by BL-119 fix; no prior-message block observed |
| **BL-107** (commit-msg hook) | **HELD** | `.git/hooks/commit-msg` present+exec, delegates `--terminal-mode --tdd-only`; fired on every feat/fix commit |
| **BL-111/123** (BP recovery) | **HELD** | `check-gate.sh --repair --branch-protection-attested` rc=0: `attestation RECORDED post-hoc (reason: github_free_tier …)` |
| **BL-126** (3 attest consumers) | **HELD** | `--preflight` rc=0, `--verify-init` `[OK] branch_protection_configured — attested`, gate honors it |
| **BL-110** (manifest pin) | **HELD** | `soloFrameworkCommit=528f5b2387d5793ef05480a7f78f93e1ff727c3c` == framework HEAD |
| **BL-096** (`--help`) | **HELD** | `--tdd-only … BL-072 tier-keyed TDD-ordering gate AND the BL-006 Build-Loop … Despite the name it is NOT TDD-only … --commit-msg-gates Honest-name alias` |
| **BL-129** (help vs code) | **HELD** | `--help-non-interactive`: `private_poc is ALWAYS personal … BL-129: this text previously claimed the OPPOSITE mapping` |
| **BL-114** (placeholder diagnostic) | **HELD** | gate emitted diagnostics, no rc=1 crash (surfaced F-DF3-001 as a precision bug, not a crash) |
| **BL-115** (dated rows / attorney) | **HELD** | legal_review fail-closed on `internal` w/o docs; satisfied with real PRIVACY_POLICY + dated attorney row |
| **BL-127** (UAT evidence) | **HELD** | empty `submissions/` → `[FAIL] Artifact check failed`; real file → `[OK] results_received: 1 submission file(s) present` |
| **BL-102** (Market Signal) | **HELD (WARN-only)** | placeholder → `[WARN] … carries template placeholder text — existence is not evidence`; imprecision: credits PENDING as `[OK]` |
| **BL-122** (ZAP clean app passable) | **HELD** | `[PASS] zap-dast — 0 Medium+ ZAP alerts (baseline rc=2; informational/low … remain)` |
| **BL-130** (attest a FAIL) | **HELD** | `[FAIL] --attest REFUSED: 'threat-model' last recorded a REAL FAIL … a FAIL must be FIXED or RE-RUN, not attested`, exit 2 |
| **BL-128** (review manifest headless) | **HELD** | `--compose-only` (no sessions) → 6 reviews → `--assemble-manifest` rc=0, `lint-review-manifest.sh` `[OK] schema is valid` — no hang, no orphans |
| **BL-105** (Phase-4 gate) | **HELD** | `--start-phase4` consulted the 3→4 gate and REFUSED until clean; advanced only when consistent |
| **BL-106** (go-live checklist) | **HELD** | `go_live_verified` BLOCKED while any box unticked / date placeholder; passed only after all 6 ticked+dated |
| **BL-117** (build-smoke) | **HELD** | `[WARN] No production-build smoke record … A build nobody started is not a production build` → produced a real dated one |
| **BL-124** (promotion ratchet) | **HELD** | wrote PENDING into App A/C/D; gate FAILs at phase≥4 until resolved (§3) |

## 5. The XSS / SAST live result — verbatim

Wrote the naive `renderWithMatches` (`pane.innerHTML = html` concatenating document text), `git add`, real `git commit`. **The commit was REFUSED by git:**

```
    src/render.ts
   ❯❯❱ javascript.browser.security.insecure-document-method.insecure-document-method
          ❰❰ Blocking ❱❱
          User controlled data in methods like `innerHTML`, `outerHTML` or `document.write` is an anti-pattern
          that can lead to XSS vulnerabilities
           42┆ pane.innerHTML = html;
[BLOCKED] Semgrep detected security issues in staged files.
```

`git commit` exited 1; **HEAD did not move**; the vulnerable bytes never entered history. Fixed with `createTextNode`/`createElement`/`textContent`; the clean commit landed **with** `[OK] semgrep: SAST ran on 10 staged file(s) — no ERROR-severity findings.` The exact inverse of Dogfood-2's F-DF2-007 (where the same XSS reached `main`). (BL-131/132's residual sinks were not exercised — the probe used the plain `innerHTML` the rule covers, via the straight stage→commit path.)

## 6. Real-repo branch-protection result (BL-111/123)

Real free-tier private repo → init hit the genuine 403 (verbatim): `github driver: branch protection is unavailable on this repo. … {"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","…"status":"403"}` → init recorded the failure, printed `Setup INCOMPLETE`, exit 2. **The framework's own recovery worked end-to-end:** `check-gate.sh --repair --branch-protection-attested` → rc=0, `attestation RECORDED post-hoc (reason: github_free_tier … recorded_via: check-gate-repair)`, honored by all three consumers. **No circularity, no destroy-and-recreate** — Dogfood-2's F-DF2-002 is fixed.

## 7. NEW findings (F-DF3-###), ranked — details + repros in FINDINGS.md

- **F-DF3-002 (High → BL-137):** the framework-generated CI runs `check-phase-gate.sh`, whose "Tools needed" arm blocks whenever dev-workstation tools (Semgrep/Snyk/Claude Code) aren't on the runner's PATH — they never are in CI. **The generated CI's governance gate is structurally unpassable in CI** (project CI run 29657490293: everything ✓ except `Governance - Phase gate check` ✗). No honest in-project fix exists; the only "fix" is the forbidden `SOIF_PHASE_GATES=warn` (not used).
- **F-DF3-001 (Medium → BL-138):** `validate_approval_fields`' placeholder detector self-collides with the template — the `grep -A 20` window bleeds into the BL-105/115 UAT/Attorney placeholder rows, and bracketed annotations in filled cells (e.g. the walk-required `[SIMULATED]`) trip it → the first gate is unpassable while following the template, with a wrong-fix diagnostic. Same window-bleed class the BL-115 fixes killed elsewhere.
- **F-DF3-004 (Medium → BL-139):** `.git/hooks/framework-gate.sh` calls `--check-commit-ready` **without `--subject`**, so at Phase 2 any staged source file is treated as a feat commit — legitimate `test:`/`chore:`/`refactor:` source commits are blocked on the user-terminal path (proof: identical staged `.ts`; no-subject → rc=1; `--subject "test(e2e): x"` → rc=0).
- **F-DF3-005 (Medium → BL-140):** `zap-dast` cannot retrieve its report under Colima/macOS — the container writes the report, but `mktemp -d` lands in macOS `$TMPDIR=/var/folders`, which Colima does not mount → the driver FAILs a verifiably clean app, and BL-130 then (correctly) refuses to attest the FAIL. Honest env workaround used and recorded: `TMPDIR=$HOME/.df3-tmp` → `[PASS] zap-dast — 0 Medium+`.
- **F-DF3-003 (Low, flake → noted on BL-135):** gitleaks CI step intermittently fails `stderr is not empty` (3 commits failed, others passed) — recorded as an observation on the existing CI-flake watch.

## 8. Gates that fired / should have and didn't

**Fired correctly (blocked until satisfied honestly):** pre-commit Semgrep DOM-XSS; Phase 0→1 approval/manifesto; ZDR/data-classification; Build-Loop sequential-step + feat-gate; UAT evidence; bug gate; Phase-3 5-scanner driver with attest + stale-detection + no-attest-on-FAIL; review-manifest gate; POC-blocks-Phase-4; BL-124 ratchet; Full-track pen-test (no exemption); BL-105 start-phase4 consult; BL-106 go-live checklist; BL-117 build-smoke; BL-115 legal fail-closed; production/rollback/monitoring/handoff steps.
**Fired but arguably shouldn't (the findings):** the phase-gate "Tools needed" arm in CI (F-DF3-002); framework-gate blocking non-feat source commits (F-DF3-004); the approval placeholder detector (F-DF3-001); zap-dast FAIL-not-SKIP under Colima (F-DF3-005).
**Should have fired but didn't (soft):** BL-102 credited a "PENDING" marker as market-signal evidence (`[OK]`) — imprecise, but WARN-only, and BL-124 enforces the same marker, so the obligation held.

## 9. Escape hatches + simulations

**Escape hatches used: ZERO.** No `--no-verify`, no `--ack-preconditions`, no `SOIF_PHASE_GATES=warn`, no `SOIF_FORCE_STEP`, no forged artifacts/attestations.
**Sanctioned recorded-to-state attestations (declared):** branch-protection `github_free_tier` (the BL-123 recovery); ZDR for `data_classification=internal` with an evidence-backed no-retention reason; snyk skip with compensating evidence (`npm audit --audit-level=high` = 0 vulns, zero runtime deps). `SOLO_UAT_SOLO_ATTESTED` was NOT used — real UAT submission files were supplied.
**Simulations (all tagged `[SIMULATED]`):** operator self-review at phase gates; the 6 evaluation-review personas; attorney/legal determination; pen-test independent-firm role; UAT accepting stakeholder — each with what a real run additionally needs.
**Env changes (outside both repos):** `TMPDIR=$HOME/.df3-tmp` (F-DF3-005 workaround), `brew install k6`, `docker pull zaproxy/zap-stable`, scratch `$HOME/.df3-tmp`.

## 10. Framework repo byte-clean at start and end — proven

Start AND end: `HEAD = 528f5b2387d5793ef05480a7f78f93e1ff727c3c`, branch `main`, **zero modified tracked files**, identical five known-untracked paths (`.claude/skills/`, `.claude/worktrees/`, `DOGFOOD-2-PROMPT.md`, `DOGFOOD-3-PROMPT.md`, `EXECUTIVE-SUMMARY.md`). The framework repo was never modified; `init.sh` even refused to run from inside it (ran from the parent dir).
