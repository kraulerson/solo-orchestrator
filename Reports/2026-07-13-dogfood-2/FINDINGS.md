# Dogfood 2 — Findings Register

**Walk date:** 2026-07-13 · **Method:** one continuous agent, real `init.sh` scaffold → real GitHub repo (`kraulerson/project-dogfood-2`, private) → real gates → real commits through the real hooks → tagged `v1.0.0`.
**Full step-by-step evidence:** [`LEDGER.md`](./LEDGER.md) (23 steps, S-001…S-023).
**Framework repo:** byte-clean at start and end (HEAD `8412b8c`, unchanged) — this findings work is the only intended modification, made after the walk closed at Karl's direction.

Each finding maps to a backlog item. Positive finding F-DF2-004 (the anti-self-approval control works) is not a defect and has no backlog entry.

| Finding | Sev | Backlog | One-line | Ledger |
|---|---|---|---|---|
| F-DF2-007 | **Critical** | BL-118 | Pre-commit + CI SAST are blind to DOM XSS; the BL-112 gate passed a real `innerHTML` XSS clean, which reached `main`. | S-013 |
| F-DF2-006 | High | BL-119 | Strict terminal gate classifies each commit by the *previous* commit's message; a correctly-blocked commit then bricks the repo. | S-011, S-017 |
| F-DF2-008 | High | BL-120 | Build-Loop `security_audit` step is existence-only — an audit reading "SEV-1, DO NOT SHIP" satisfies it. | S-014 |
| F-DF2-011 | High | BL-121 | MVP-Cutline counter uses GNU-sed alternation → BSD/macOS counts to EOF (68 vs 3) → hard-blocks the production gate. | S-016, S-022 |
| F-DF2-012 | High | BL-122 | Phase-3 `zap-dast` counts all alerts unfiltered; ZAP rule 10049 fires under every Cache-Control → gate unpassable for any web app. | S-019 |
| F-DF2-002 | High | BL-123 | Real-remote free-tier branch-protection recovery is circular; only destroy-and-recreate escapes. | S-005 |
| F-DF2-014 | High | BL-124 | Promotion re-opens the light-track skips (`SKIPPED→PENDING`) then no gate reads `PENDING`. | S-020 |
| F-DF2-009 | Medium | BL-125 | Nothing runs the test suite at commit time; a commit with 4 RED XSS tests landed clean. | S-014 |
| F-DF2-005 | Medium | BL-126 | `github_free_tier` attestation honored by 2 of 3 consumers; `--verify-init` FAILs it. | S-010 |
| F-DF2-010 | Medium | BL-127 | 9-step UAT process demands zero evidence; `results_received` marked with empty `submissions/`. | S-015 |
| F-DF2-015 | Medium | BL-128 | Six-eval review generator parses (BL-103 fixed) but never completes (~40 min, 159 orphaned procs, no manifest). | S-021 |
| F-DF2-003 | Low | BL-114 (addendum) | `--start-phase1` advances the phase with no gate consult and is undocumented in `--help`. | S-008 |
| F-DF2-001 | Low | BL-129 | `init.sh` non-interactive help contradicts the gov-mode validation code. | S-002 |
| F-DF2-013 | Low | BL-130 | `run-phase3-validation.sh --attest` records an attestation for a FAILing scanner and prints `[OK]` (BL-113 still refuses to honor it). | S-019 |
| F-DF2-004 | (positive) | — | The anti-self-approval control is real: the Phase 0→1 gate blocked until the approval row was committed, so `git blame` could verify approver ≠ author. | S-008 |

## The central question — answered

> When a POC is promoted to a real MVP, does the framework force the operator back to satisfy the stricter gates the POC tier let them skip?

**Governance and security-review obligations: YES (the ratchet holds).** `--to-production` refused until all six Pre-Phase-0 rows were dated (naming rows 2,3,5,6); the review gate flipped WARN→FAIL; the pen-test requirement flipped absent→FAIL (no exemption on Full track). All cleared honestly, no `--ack-preconditions`.

**Phase-0/1 product obligations: NO (the hole — BL-124).** The upgrade tool rewrites the Revenue Model and Trademark/Legal appendices from `SKIPPED` to `PENDING`, and Market Signal (BL-102) has no check — none of the three is enforced by any gate. A project reaches a tagged production release with all three still literally "PENDING." The framework *performs* the re-demand and *forgets* to enforce it — which reads to an auditor as a working ratchet.

## The XSS / SAST live test — the headline

The just-shipped BL-112 pre-commit SAST **did not block** a real stored DOM XSS. It ran, scanned the vulnerable file, and reported `no ERROR-severity findings`; the code (`pane.innerHTML = html`) reached `main` of the real repo (pushed `c8b1dd2..d6b4d14`). Root cause is the ruleset (`p/owasp-top-ten`, `p/security-audit`), not the scanner — verified with a positive control containing `eval`/`innerHTML`/`document.write` (0 findings), while `r/javascript.browser.security.insecure-document-method` and `--config auto` catch it. BL-112 fixed the plumbing; the gun was never loaded. → BL-118.

## Escape hatches used: ZERO

No `--no-verify`, no `--ack-preconditions`, no `SOIF_PHASE_GATES=warn`, no hand-forged artifacts. Documented attestations (branch-protection `github_free_tier`, ZDR, two Phase-3 scanner skips with real compensating evidence, `SOLO_REVIEWERS_ATTESTED` for reviews the broken generator couldn't package) were used and declared — the sanctioned, recorded-to-state class, not the forbidden one. The one environment change (a `~/.claude.json` trust flag to run the framework's own generator) was restored.
