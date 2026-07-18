# DOGFOOD-3 LEDGER

Scratch dir (stable, outside both repos): /var/folders/35/40h2stxn1c7fnq3zlbmg8kjr0000gn/T//dogfood3.1fYeam
Started: 2026-07-18 12:17:56 MDT
Walker: fresh agent (Dogfood-3), per DOGFOOD-3-PROMPT.md

---

## STEP 0 — Preconditions (2026-07-18 12:17)

| check | command | result | verdict |
|---|---|---|---|
| gh auth | `gh auth status` | account kraulerson, scopes: delete_repo, gist, read:org, repo, workflow | PASS |
| repo free | `gh repo view kraulerson/project-dogfood-3` | "Could not resolve to a Repository" rc=1 | PASS |
| local dir absent | `ls -d ".../project-dogfood-3"` | No such file or directory | PASS |
| framework branch | `git branch --show-current` | main | PASS |
| PR #213 present | `git merge-base --is-ancestor ab62028 HEAD` | IS ancestor | PASS |
| PR #214 present | `git merge-base --is-ancestor 528f5b2 HEAD` | IS ancestor (== HEAD) | PASS |
| byte-clean | `git status --porcelain` | ONLY: ?? .claude/skills/, ?? .claude/worktrees/, ?? DOGFOOD-2-PROMPT.md, ?? DOGFOOD-3-PROMPT.md, ?? EXECUTIVE-SUMMARY.md — zero M/A/D | PASS |

**Framework baseline: HEAD=528f5b2387d5793ef05480a7f78f93e1ff727c3c, branch=main.** (End-of-run must match.)

## Running sections (maintained at bottom of this file)
- Findings (new): see FINDINGS.md
- POC leniencies observed: §L
- What promotion re-demanded (or did not): §P
- Fix-checkpoint results: §FC
- Simulations: §S
- Escape hatches (must be ZERO): §E

## STEP 1 — Required reading (PASS)
Read: DOGFOOD-3-PROMPT.md (in full), CLAUDE.md (in context), docs/builders-guide.md (all 2043 lines),
Reports/2026-07-13-dogfood-2/FINDINGS.md, Reports/2026-07-12-e2e-walk/CHECKLIST.md (structure + rules R1-R9),
backlog BL-118..BL-134 statuses.
- FIXED set to probe: BL-118 (PR #199), BL-119+133 (PR #200), BL-121 (PR #201), BL-122 (PR #203), BL-123+126 (PR #206), BL-124 (PR #204), BL-127 (PR #208), BL-128+129+130 (PR #211). Plus prompt checkpoints BL-096/102/105/106/107/110/111/114/115/117.
- KNOWN-OPEN (cite, never re-file): BL-120 (security_audit existence-only), BL-125 (no test run at commit), BL-131 (residual DOM sinks: insertAdjacentHTML, jQuery .html(), .vue, inline <script> in .html), BL-132 (worktree-vs-index scan gap), BL-134 (T2 timing flake), BL-135, BL-136, PR #215.

## STEP 2 — Fix checkpoints BL-129 + BL-096 (framework-side reads) — both HELD
- **BL-129 HELD.** `bash init.sh --help-non-interactive` now prints: "private_poc is ALWAYS personal; sponsored_poc is ALWAYS organizational (baseline §2.5). BL-129: this text previously claimed the OPPOSITE mapping and following it verbatim was rejected." Matches the validation code (my personal+private_poc config validates below).
- **BL-096 HELD.** `bash scripts/pre-commit-gate.sh --help` documents: "--tdd-only ... run ONLY the two MESSAGE-SCOPED commit-msg gates — the BL-072 tier-keyed TDD-ordering gate AND the BL-006 Build-Loop commit-message check (BL-010). Despite the name it is NOT TDD-only ... (BL-096)" and "--commit-msg-gates  Honest-name alias for --tdd-only (BL-096)."
- Bonus guard observed: init.sh REFUSES to run with cwd inside the framework repo ("Refusing to operate inside the Solo Orchestrator framework repo") — ran from parent dir instead.

## STEP 3 — init.sh --validate-only — PASS
Command (cwd = "/Users/karl/Documents/Claude Projects"):
bash ".../solo-orchestrator/init.sh" --non-interactive --project project-dogfood-3 --platform web --deployment personal --gov-mode private_poc --language typescript --track light --git-host github --visibility private --project-dir ".../project-dogfood-3" --validate-only
Resolved config echoed with _validated:true — personal + private_poc + light + github + private accepted.

## STEP 4 — REAL init.sh run — PARTIAL (expected free-tier 403; honest rc=2)
Command: same as STEP 3 minus --validate-only. Full output: scratch init-run.log (project copy: .solo-orchestrator/init-20260718-122021.log).
- Repo CREATED for real: gh repo view → {"name":"project-dogfood-3","visibility":"PRIVATE","defaultBranchRef":"main","pushedAt":"2026-07-18T18:20:58Z"}
- Initial push succeeded; local commits: 38e9b38 "chore: initialize Solo Orchestrator project", 70f12c4 "chore: record host setup outcome (init finalize)"
- Hooks installed by init: "[OK] Pre-commit hook installed (gitleaks + Semgrep + schema migration checks)" + "[OK] TDD ordering gate installed (commit-msg hook, tier-keyed hard block)"
- Branch protection VERBATIM: 'github driver: branch protection is unavailable on this repo. ... {"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","documentation_url":"https://docs.github.com/rest/branches/branch-protection#update-branch-protection","status":"403"}gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)'
- Non-interactive fallback: "[WARN] Branch protection unavailable via standard API on this github repo. / [INFO] Falling back to attestation flow / [FAIL] Attestation required — cannot proceed" → init "Setup INCOMPLETE", exit 2, remediation pointer to scripts/check-gate.sh --repair. HONEST failure, no silent pass.
- Verify-install report inside init: 81 passed / 0 manual actions.
Verdict: PASS for honesty (real failure recorded, exit non-zero); recovery attempt next (BL-111/123).

## STEP 5 — Fix checkpoints BL-111/123, BL-126, BL-107, BL-110 — ALL HELD
- **BL-111/123 HELD (real-repo recovery works end-to-end).** `bash scripts/check-gate.sh --repair --branch-protection-attested` → rc=0: "[OK] Repair: branch-protection attestation RECORDED post-hoc (reason: github_free_tier — upgrade the host plan to enable API enforcement; recorded_via: check-gate-repair)". No circularity, no destroy-and-recreate needed (Dogfood-2 F-DF2-002 fixed).
- **BL-126 HELD (3/3 consumers).** --preflight rc=0 "[OK] Ready: branch protection attested"; --verify-init "[OK] branch_protection_configured — attested (reason: github_free_tier)" (this was the FAILing 3rd consumer in F-DF2-005).
- **BL-107 HELD (installed).** .git/hooks/commit-msg exists, executable, delegates to `scripts/pre-commit-gate.sh --terminal-mode --tdd-only` (both message gates). "Fires" to be proven on first real commit.
- **BL-110 HELD.** manifest.json soloFrameworkCommit = 528f5b2387d5793ef05480a7f78f93e1ff727c3c == framework HEAD (exact).
- verify-init honest gaps at this stage: project_scaffolded FAIL (no lockfile yet — app not initialized; that is Phase-2 init work), data_model_applied manual. 4/6 auto-marked.

## STEP 6 — Phase 0 executed; Phase 0→1 gate crossed honestly (3 attempts; finding F-DF3-001)
- Artifacts: docs/phase-0/{frd,user-journey,data-contract}.md + PRODUCT_MANIFESTO.md (8 sections; App A "SKIPPED — internal tool, no revenue model required"; App B real matrix; App C SKIPPED; App D "SKIPPED — Light track / internal tool (Step 1.1.5 not required)"). APPROVAL_LOG Phase-Gate section filled (Reviewer/Date/Decision/Notes; [SIMULATED] tag in Notes).
- Commit 900ae28 "docs(phase-0): ..." — hooks fired: "[OK] semgrep: SAST ran on 5 staged file(s) — no ERROR-severity findings."
- Attempt 1: --start-phase1 REFUSED (rc=1) — "[WARN] ... placeholder values" (blocking increment). BL-114 HELD: gate consulted, no silent advance; date auto-recorded phase_0_to_1=2026-07-18 (+_by from commit author), idempotent on retry.
- Attempt 2 (Reviewer-cell bracket removed, commit 6552725): STILL refused — real mechanism: grep -A 20 on the gate name matches the Approval History row too; window bleeds into UAT Sign-off template placeholders (YYYY-MM-DD) added by BL-105/115. → F-DF3-001 (Medium).
- Attempt 3a (history row dropped, commit 58f8bdc): STILL refused — my explanatory comment itself contained the gate-name string. Detector triggers on ANY line mentioning the gate name within 20 lines above any placeholder.
- Attempt 3b (comment reworded, commit 8607703): PASS rc=0 — "Phase gates consistent", snapshot docs/snapshots/phase-0-to-1_2026-07-18, current_phase 0→1.
- §L (POC leniencies): Light track let me SKIP Step 0.5 (Revenue, App A), Step 0.7 (Trademark, App C), Steps 1.1/1.1.5 (Market Signal, App D — exact template skip line). These are the promotion re-demand candidates.
- §S: operator/self-review role simulated by walker, tagged in APPROVAL_LOG Notes.

## STEP 7 — Phase 1 + Phase 2 scaffold (PASS)
- Phase 1 artifacts committed (90e2941). 5 phase1_architecture steps marked. check-phase-gate at phase 1 = "Phase gates consistent" rc=0.
- ZDR gate (tier-crosscheck-6): data_classification=internal + zdr_attested=false with evidence-backed reason, set via `scripts/reconfigure-project.sh` (audit rows appended to APPROVAL_LOG.md).
- Real app scaffolded: vanilla TS + Vite, zero runtime deps. package.json/tsconfig/vite.config/eslint.config/prettier/index.html/styles.css/src{log,dom,main}.ts + smoke test.
- **Dependency hygiene (honest fix, not suppression):** initial install had 9 vulns (1 critical/3 high). Updated eslint→9.39.5, @playwright/test→1.61.1, vite→8.1.5, vitest→4.1.10 → `npm audit --audit-level=high` = "found 0 vulnerabilities". License gate (CI failOn list) rc=0, all permissive (202 MIT, 31 ISC, 21 Apache-2.0, ...; 2 MPL-2.0 not in denylist).
- Scaffold verified: `npm run build` rc=0 (dist built), `npm run lint` rc=0 (clean), `npm test` rc=0 (1 passed).
- Commit 4e281cf `build(scaffold): ...` landed (build: type → TDD gate out of scope). Pushed 38e9b38..4e281cf.
- verify-init: 5/6 (remote_repo_created, branch_protection_configured [attested], ci_pipeline_configured, project_scaffolded [lockfile], pre_commit_hooks_installed). data_model_applied deferred until F3 persistence tested (honest).

## STEP 8 — Build Loop F1 (Open & display) — PASS; BL-107 + BL-119 HELD
- TDD: tests/unit/open.test.ts written first → RED ("Test Files 1 failed", validateFile import missing) → implemented src/open.ts + src/render.ts (text-node seam) → GREEN (9/9). Full suite 10/10. build rc=0, lint rc=0.
- Security audit: semgrep on all 5 src files "Ran 27 rules on 5 files: 0 findings" rc=0; docs/security-audits/F1-...md written; ESLint no-restricted-properties bans innerHTML too.
- Docs: FEATURES.md F1 section, CHANGELOG Added/Security/Infra, ADR-0001. All 6 build_loop steps marked in order (caught my own out-of-order attempt: "[FAIL] Cannot complete 'documentation_updated' — 'security_audit' not yet completed" — sequential enforcement works).
- **BL-107 HELD (commit-msg hook fires):** feat commit 5d93fcb landed WITH "[OK] semgrep: SAST ran on 10 staged file(s) — no ERROR-severity findings." TDD-ordering gate allowed it (tests staged with impl); BL-006 build-loop gate allowed it (loop complete).
- **BL-119 HELD (no stale-message brick):** immediately after the feat commit, `docs(frd): ...` commit 0596166 landed clean rc=0 — classifier read THIS message, not the previous feat:. F-DF2-006 fixed.

## STEP 9 — Build Loop F2 (Find in document) — THE LIVE SAST PROBE — BL-118 HELD (headline)
- TDD: search.test.ts + render-highlight.test.ts (incl. 3 TM-001 XSS-inertness negatives) written first → RED ("Test Files 2 failed") → src/search.ts (literal indexOf, no regex).
- **NAIVE innerHTML renderer written deliberately** (renderWithMatches concatenating document text into `pane.innerHTML = html`), `git add`, REAL `git commit` attempted:
  VERBATIM hook output:
    src/render.ts
    ❯❯❱ javascript.browser.security.insecure-document-method.insecure-document-method
          ❰❰ Blocking ❱❱
          User controlled data in methods like `innerHTML`, `outerHTML` or `document.write` is an anti-pattern that can lead to XSS vulnerabilities
           42┆ pane.innerHTML = html;
    [BLOCKED] Semgrep detected security issues in staged files.
  → `git commit` exit 1; HEAD did NOT move (stayed 0596166); vulnerable bytes never entered history.
  This is the EXACT INVERSE of Dogfood-2 F-DF2-007 (innerHTML XSS reached main). Load-bearing rule = r/javascript.browser.security.insecure-document-method (BL-118 added to pre-commit + CI). **BL-118 HELD.**
- Fixed properly: renderWithMatches → createTextNode + createElement('mark') + textContent. semgrep on fixed files rc=0. 23/23 tests, build rc=0, lint rc=0.
- CLEAN commit d065fa4 landed WITH "[OK] semgrep: SAST ran on 10 staged file(s) — no ERROR-severity findings." exactly as protocol demands.
- Audit: docs/security-audits/F2-...md records the probe verbatim.
- Note on BL-131/132 (known-open, NOT re-filed): I used the straight stage→commit path (worktree==index), so BL-132's worktree-vs-index gap was not exercised; my sink was plain `innerHTML` which the rule covers, not BL-131's residual sinks (insertAdjacentHTML/jQuery.html()/.vue/inline <script>).

## STEP 10 — UAT session 1 (F1+F2) — BL-127 HELD; SAST gate strictness confirmed on test code
- **BL-127 HELD (both directions):**
  (a) results_received with EMPTY submissions/ → REFUSED: "[WARN] ...submissions/ has no files. ... [FAIL] Artifact check failed. Produce the required artifact first." (F-DF2-010 fixed).
  (b) after a REAL submission file (tests/uat/sessions/1/submissions/operator-uat-session-1.md) → "[OK] results_received: 1 submission file(s) present". Positive branch works.
- **SOLO_UAT_SOLO_ATTESTED escape: NOT USED.** I am a genuine solo operator who genuinely tested, so I provided a real submission file (stronger evidence) rather than the attestation. The sanctioned escape's correctness confirmed by reading process-checklist.sh (records to uat_session.solo_attestations[], warns off-Light-track). Escape-hatch count stays ZERO.
- Real E2E testing: tests/unit/app.integration.test.ts boots the real app against real index.html and drives all 3 features + malicious-user XSS-inertness. 6/6 pass; full suite 29/29.
- **Positive (not a finding): the pre-commit SAST gate is strict even on TEST code.** My first UAT commit was BLOCKED because the test helper used `document.body.innerHTML = body` (line 14) — semgrep flagged insecure-document-method. Fixed properly with DOMParser + importNode (no suppression). Clean commit e055830 landed with the [OK] semgrep receipt. Demonstrates the gate has no test-path blind spot.
- All 9 uat_session steps completed in order; test-gate --reset-counter recorded session 2026-07-18; --check-batch "Clear to continue".

## STEP 11 — Build Loop F3 (Font size, persisted) — PASS
- TDD: tests/unit/fontsize.test.ts written first → RED → src/fontsize.ts (clamp/step/load/save, corrupt-value fallback, fail-safe write). GREEN.
- Test-infra honesty: jsdom ships a NON-FUNCTIONAL localStorage stub (diagnosed: prototype only has isPrototypeOf). Added tests/setup.ts spec-compliant in-memory Storage double (legitimate test double for a browser API the runner omits) + @types/node@22.12.0 for the integration harness. Not a framework finding — an environment gap I handled honestly.
- Integration: F3 persist-across-reload proven end-to-end (set 20px → re-boot → 20px restored); bounds-disable proven. Full suite 41/41. build rc=0, lint rc=0.
- Security audit: semgrep on fontsize.ts+main.ts "0 findings"; docs/security-audits/F3-font-size-persist-security-audit.md.
- Caught my own naming slip: security_audit step wants the audit filename to contain the feature slug (f3-font-size-persist). Renamed F3-font-size-security-audit.md → F3-font-size-persist-security-audit.md. Sequential+artifact enforcement works.
- data_model_applied marked (localStorage single-key model verified: persist across reload + clear=reset). Commit 7af5a2d pushed.

## STEP 12 — CI on the REAL repo + phase advance
- Pushes trigger real CI. On the F3 commit (7af5a2d, run 29657490293): Build/Lint/Test/SAST(semgrep)/gitleaks/dep-audit/license/lockfile/approval-log-integrity/approval-author ALL ✓; ONLY "Governance - Phase gate check" ✗.
- Root-caused to F-DF3-002 (HIGH): check-phase-gate.sh "Tools needed" arm increments issues when Semgrep/Snyk/Claude Code aren't on the runner's PATH (they never are in CI). Locally gate rc=0. Deterministic CI block. NOT worked around (SOIF_PHASE_GATES=warn is forbidden; no honest in-project fix exists).
- gitleaks flake observed (F-DF3-003, Low) — failed on 2 earlier commits, passed on F3; cross-ref BL-135.
- Phase advance: current_phase was stuck at 1 because phase-2 auto-advance lives in --verify-init, last run before data_model_applied. Re-ran --verify-init → "initialization_verified — all prerequisite steps passed" → "Advanced .current_phase: 1 → 2". Intended flow, not a bug.

## STEP 13 — Real-browser verification + F-DF3-004 + Phase 2->3
- **App works in a REAL browser (Chromium via Playwright, production build):** 7/7 E2E pass. F1 open/empty; F2 count(5)+highlight+step; **F2 TM-001: window.__pwned stays undefined, no script/img element parsed, markup shown as inert text**; F3 persist-across-reload (16→20px survives reload) + bound-disable. Screenshot docs/test-results/2026-07-18_app-screenshot.png visually confirms highlighting + inert markup.
- Found a TEST bug (clicking a disabled bound button hangs Playwright) — the APP is correct (button disables at bound); fixed the test.
- **F-DF3-004 (Medium):** at Phase 2, real `git commit -m "test(e2e): ..."` BLOCKED as "'feat(...)' commit blocked — no Build Loop active". Root cause: framework-gate.sh calls `--check-commit-ready` WITHOUT `--subject`, so check_commit_ready's code-process-checklist-5 subject short-circuit can't fire on the user-terminal path. Proof (same staged .ts): no-subject rc=1, `--subject "test(e2e)"` rc=0, `--subject "feat"` rc=1. NOT worked around — E2E is Phase-3 Step-3.1 work; advanced to Phase 3 honestly and committed there.
- UAT session 2 (F3 + full regression): 41 unit + 7 E2E green, real submission (BL-127 positive branch again), 0 bugs. Bug gate → "Phase 2→3 gate clear."
- Phase 2→3 approval recorded; --start-phase3 → "Advanced .current_phase: 2 → 3".

## STEP 14 — Phase 3 scanners + BL-122 + BL-130 + F-DF3-005 (ZAP/Colima)
- Driver baseline: semgrep-full-tree PASS, license PASS (0 denied), threat-model PASS (6 TMs), snyk SKIP(unauthed), zap-dast SKIP(no target).
- **snyk** genuinely unauthenticated (`snyk test` → "Use snyk auth"). Attested skip with REAL compensating evidence: `npm audit --audit-level=high` = 0 vulns (local + CI every push), zero runtime deps. Sanctioned attestation, recorded+signed. NOT a forbidden escape.
- **BL-130 HELD:** induced a REAL threat-model FAIL (temp unvalidated TM-007 in Bible) → `--attest threat-model` REFUSED exit 2: "a FAIL must be FIXED or RE-RUN, not attested" (BL-113). Reverted Bible → PASS. Also confirmed on zap-dast: attest refused while FAIL; stale-detection refused a SKIP from laundering a prior FAIL. All anti-laundering controls HELD.
- **ZAP DAST (BL-122) — real scan, real hardening:**
  - First real ZAP run: FAIL-NEW 0 but **2 Medium (riskcode=2)**: "CSP: style-src unsafe-inline" + "Missing Anti-clickjacking Header". App genuinely not clean → correct for the gate to flag.
  - Hardened (real Phase-3 security work): removed style-src 'unsafe-inline' (unused; CSSOM font resize is not CSP-governed — proven by E2E staying green), added security response headers via a vite plugin (X-Frame-Options: DENY, COOP/COEP/CORP, X-Content-Type-Options, Referrer-Policy, Permissions-Policy) + public/_headers for the prod static host. Removed frame-ancestors from META CSP (header-only; was flagged "Meta Policy Invalid Directive").
  - Re-scan: **0 Medium+ (riskcode>=2)**, only 2 informational (Modern Web App, Storable-but-Non-Cacheable).
  - **F-DF3-005 (Medium):** driver's zap-dast FAILed ("no report") because `mktemp -d` uses macOS $TMPDIR=/var/folders, which Colima does NOT virtiofs-mount (only /Users/karl is) → the bind mount is VM-local, container writes never sync to host. Fix (env, honest): `export TMPDIR=$HOME/.df3-tmp/` (virtiofs-mounted) → driver's mktemp shares correctly.
  - With TMPDIR fixed, driver: **[PASS] zap-dast — 0 Medium+ ZAP alerts (baseline rc=2; informational/low ... remain)**. **BL-122 HELD** — clean app passes despite baseline rc=2.
- **Phase 3 scan summary: PASS=4, SKIP(attested)=1 [snyk], FAIL=0 → PASS. "[OK] Phase 3 validation gate-ready."**

## STEP 15 — BL-128 review manifest (headless path) — HELD
- `run-reviews.sh web-app --compose-only` → composed 6 prompts to docs/eval-results/prompts/, STARTED NO SESSIONS (the 159-orphan fix). rc=0, terminated cleanly.
- Ran all 6 reviews myself [SIMULATED, tagged, with the verbatim provenance header]: senior-engineer, cio, security, legal, technical-user, red-team → saved at the 6 demanded artifact names in project root. Genuine reviews of the real code (red-team enumerated 8 real attack attempts, all blocked).
- `run-reviews.sh web-app --assemble-manifest` → rc=0, "All requested reviews complete", wrote docs/eval-results/review-manifest.json. NO hang, NO orphans (Dogfood-2 F-DF2-015 fixed).
- `scripts/lint-review-manifest.sh` → "[OK] schema is valid." All 6 reviewers status=complete incl. the mandatory Security + Red Team.

## STEP 16 — Phase 3 complete; POC WALL hit (BL-105) — as designed
- Phase 3 validation: all 9 steps complete. Lighthouse a11y=100 perf=100. SBOM (CycloneDX 1.6, 259 comp). Scan evidence archived. Phase 3 scanners PASS=4 + snyk attested.
- legal_review: BL-115 fail-closed on internal classification (can't skip by omitting docs). Satisfied honestly: wrote truthful PRIVACY_POLICY.md (zero data collection) + dated [SIMULATED] attorney-review row referencing legal-review-v1.md. Step → 9/9.
- Phase 3 artifacts committed de74fe7, pushed.
- **POC WALL (verbatim):** `::error::Phase 4 (production release) is BLOCKED — project is in private poc mode. / POC projects complete at Phase 3 (ready to deploy). / To unlock Phase 4: bash scripts/upgrade-project.sh --to-production`. Gate also confirmed HANDOFF/sbom/review-manifest present + Security+RedTeam reviews complete + ZDR gate OK. This is the designed wall — reason to promote (Stage 2).

## STEP 17 — CENTRAL QUESTION: promotion (Stage 2) — the ratchet HOLDS with machinery
- `scripts/upgrade-project.sh --to-production --track full` → rc=0: "POC mode removed (production-ready), track upgraded from light to full". poc_mode: private_poc→null, track: light→full, deployment stays personal.
- **BL-124 ratchet WROTE markers:** PRODUCT_MANIFESTO App A (Revenue), App C (Trademark), App D (Market Signal) ALL rewritten "SKIPPED" → "PENDING — required by track upgrade light → full on 2026-07-18".
- **BL-124 gate READS them (the F-DF2-014 fix):** check-phase-gate.sh `# BL-124-PENDING-RATCHET` greps the whole manifesto for "PENDING — required by track upgrade" and FAILs (issues+1). Guarded by current_phase>=4 (fires once at phase 4, blocking finalize/go-live/CI — not the 3→4 transition itself, which the pen-test blocks first).
- **Post-upgrade Phase 3→4 gate re-demanded (verbatim):**
  - [FAIL] Phase 3→4: Full Track requires penetration test — no exemption path available (Light skipped it entirely — NEW hard demand).
  - [WARN] Release pipeline has 4 unconfigured TODO items (now production-relevant).
  - review gate: flipped from Light WARN-only to Full FAIL-enforced (I already have all 6 reviews complete, so it PASSES).
- **BL-102 checkpoint:** WARN-only arm (deliberately no issues increment). Tested: injected TEMPLATE placeholders → "[WARN] BL-102: Appendix D ... carries template placeholder text — existence is not evidence (the hollow-gate class)". With the BL-124 PENDING marker it prints [OK] (PENDING isn't the template-placeholder pattern) — minor imprecision, but gate-inconsequential (BL-102 never increments; BL-124 catches App D's PENDING at phase>=4). Restored, filling honestly.
- ANSWER: YES — governance obligations Light skipped (Revenue App A, Trademark App C, Market Signal App D, penetration test) are ALL re-demanded and ENFORCED after promotion (BL-124 phase>=4 + pen-test phase>=3). Dogfood-2's central-question hole (F-DF2-014: ratchet re-demands but nothing enforces) is CLOSED.

## STEP 18 — Full-track obligations satisfied + Phase 4 + v1.0.0
- Filled App A (Revenue: N/A $0, rationale), App C (Trademark/legal pre-check [SIMULATED]), App D (Market Signal: honest seen-it/hunch/guess, GO as free utility) → all 3 PENDING markers resolved.
- Pen test (full track, no exemption): docs/test-results/2026-07-18_penetration-test.md — 0 Crit/High/Med, based on real ZAP + red-team's 8 attack attempts; [SIMULATED] independent-firm role. Recorded in APPROVAL_LOG Penetration Test section.
- Release pipeline TODOs resolved: configured to package the static dist/ bundle as a release artifact (no external host/secrets). release.yml TODO count → 0.
- F-DF3-002 manifestation: full-track tools-check flagged k6 + OWASP ZAP (PATH/image presence). Installed k6 (brew) + pulled zaproxy/zap-stable (the image name the resolver checks). Load testing documented N/A (no server). Tools-check cleared.
- **BL-105 HELD:** `--start-phase4` consulted the 3→4 gate and REFUSED until clean; BL-124 ran at the transition ([OK] no PENDING). Advanced 3→4 only after all clear.
- **BL-117 HELD:** production_build refused without a dated build-smoke record ("A build nobody started is not a production build") → produced real one (built + started + HTTP 200 + title verified).
- rollback_tested: REAL rollback via isolated git worktree at 7af5a2d → rebuilt + served HTTP 200; main HEAD intact. (Found `.claude/bypass-audit.json` hook-churn blocks in-tree `git checkout` — worktree method used.)
- **BL-106 HELD:** go_live_verified BLOCKED while checklist boxes unticked + placeholder date. Ticked all 6 honestly against the running build (SSL: TLS-ready/host-provided; headers: verified served; CORS/cookies/rate-limit: N/A resolved w/ reason; Lighthouse 100/100). Also demanded substantive RELEASE_NOTES (filled v1.0.0).
- monitoring_configured: real verification event — triggered a non-.txt error via Playwright → error state "Only .txt files are supported." + structured log {event:open.reject.type}. Recorded in HANDOFF §8.
- handoff_written + handoff_tested: New-Maintainer persona followed HANDOFF §2 in a clean worktree. **Caught a real MY-CODE defect**: npm run lint failed on clean checkout (sbom.json + vite.config.ts prettier). Fixed (a9a4986: prettier-ignore sbom, reformat vite.config). Re-test clean (41 tests). This is the handoff test doing its job.
- BL-072 TDD tier observation: the fix(lint) commit WARNed (bypassable) because tier predicate is deployment-based (still personal), NOT track — full-track PERSONAL stays WARN-tier (BL-084 by design). Logged to tdd-warn-ledger, not blocked. NOT an escape hatch.
- Final gate (phase 4): after fixing an unreachable-preview zap FAIL (bound preview to 0.0.0.0), driver PASS=4/attested=1/FAIL=0, "[OK] validation scans clean", "Phase gates consistent" rc=0.
- **v1.0.0 tagged + pushed.** Release workflow SUCCESS → GitHub release v1.0.0 with assets dogfood-reader-3-v1.0.0.zip + sbom.json (not draft).
- CI (non-release) this run: FAILED at gitleaks (F-DF3-003 flake, "stderr is not empty") — Build/Lint/Test/SAST all ✓ (lint fix worked); gitleaks failed before phase-gate ran. F-DF3-002 (phase-gate tools) is the deterministic CI blocker on runs where gitleaks passes.

## §L POC leniencies observed (Light/private-POC let through)
- Skipped Step 0.5 Revenue (App A), Step 0.7 Trademark (App C), Steps 1.1/1.1.5 Market Signal (App D) — all marked SKIPPED.
- Review gate WARN-only on Light (I did all 6 anyway).
- Pen test not required on Light.
- POC mode blocked Phase 4 (the wall) — the reason to upgrade.

## §P What promotion re-demanded (or did not)
- RE-DEMANDED + ENFORCED: Revenue (App A), Trademark (App C), Market Signal (App D) via BL-124 PENDING markers (gate FAILs at phase>=4); penetration test (full track, no exemption, FAILs at phase>=3); review gate flipped WARN→FAIL (Security+RedTeam mandatory); release-pipeline TODOs; k6/ZAP tooling.
- NOT hard-enforced: BL-102 market-signal check is WARN-only (never increments) AND credits the PENDING marker as [OK] (it only WARNs on template-placeholder patterns) — minor imprecision, but BL-124 covers App D's PENDING marker so the obligation is still enforced. Central-question hole from Dogfood-2 (F-DF2-014) is CLOSED.

## §FC Fix-checkpoint results
BL-118 HELD · BL-119 HELD · BL-107 HELD · BL-111/123 HELD · BL-110 HELD · BL-096 HELD · BL-102 HELD (WARN-only, placeholder-WARN works; PENDING-credit imprecision noted) · BL-122 HELD · BL-130 HELD · BL-128 HELD · BL-114 HELD · BL-115 HELD · BL-105 HELD · BL-106 HELD · BL-117 HELD · BL-124 HELD · BL-126 HELD · BL-127 HELD · BL-129 HELD · BL-133 HELD.

## §S Simulations (all tagged [SIMULATED])
- Operator self-review at every phase gate (personal project).
- 6 evaluation-review personas (engineer/cio/security/legal/techuser/redteam).
- Attorney/legal review determination.
- Penetration test independent-firm role.
- UAT accepting stakeholder.
Attestations used (sanctioned, recorded-to-state class — NOT forbidden escapes): branch-protection github_free_tier (BL-123 recovery), ZDR data_classification=internal reason, snyk skip (npm-audit compensating evidence).

## §E Escape hatches used: ZERO
- No --no-verify. No --ack-preconditions. No SOIF_PHASE_GATES=warn. No SOIF_FORCE_STEP. No hand-forged artifacts/attestations. Every gate satisfied by real evidence or an honest recorded attestation.
- Env changes (outside both repos): TMPDIR=$HOME/.df3-tmp for the session (Colima virtiofs workaround, F-DF3-005), brew install k6, docker pull zaproxy/zap-stable, $HOME/.df3-tmp scratch. None touch either repo.

## FRAMEWORK REPO byte-clean at END: HEAD 528f5b2387d5793ef05480a7f78f93e1ff727c3c, branch main, ZERO modified tracked; only the 5 known-untracked paths (matches DOGFOOD-3 precondition baseline exactly).
