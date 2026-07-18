# Dogfood-2 Remediation — Final Report

**Run:** 2026-07-17 → 2026-07-18, autonomous per `REMEDIATION-PROMPT.md`, order per `REMEDIATION-PLAN.md`.
**Merge policy:** AUTO_MERGE = NO — every fix is an open green PR awaiting Karl's review; merge the stack ASCENDING (#203 → … → #211; auto-delete-head-branches is ON, so children retarget automatically).
**Evidence of record:** `REMEDIATION-PROGRESS.md` (per-WP reproduce / watched-RED / GREEN / mutation / verifier / residuals). This report is the roll-up.

---

## 1. Fixed

Every row: TDD with a WATCHED RED, fix behind a grep-able `# BL-NNN-…` marker, mutation proof (break the marked line/fence → RED → restore → GREEN), suites registered in BOTH `tests/full-project-test-suite.sh` and the `tests.yml` unit list where eligible.

| BL | Sev | PR | One-line | Mutation proof | Merged? |
|---|---|---|---|---|---|
| BL-118 (+folds: verify-install third emitter) | Critical | #199 | Commit-time SAST now catches DOM-XSS sinks (`r/javascript.browser.security.insecure-document-method` + exact-token pins, 20 CI templates, CI full-lane semgrep) | source-level config-line deletion → 5/6 RED; in-test emitted-hook strip | **YES** (via #202 `88bddd3`) |
| BL-119 (+BL-087, +BL-133) | High | #200 | Plain `--terminal-mode` runs NO message consumer — the stale-COMMIT_EDITMSG brick and the stale BR-lint feed are dead; mothership passes gracefully | fence excision per arm; rewritten bug-pinning tests under documented-bug exception | **YES** (via #202) |
| BL-121 | High | #201 | Cutline counter awk-based (POSIX ERE) — BSD sed no longer miscounts the Must-Have block; counter-antipattern lint catches the `sed \|` class repo-wide | counter revert → RED on macOS shape; lint self-test | **YES** (via #202) |
| BL-122 | High | #203 | ZAP verdict filters riskcode ≥ 2 (jq), rc 1/2 out of the verdict, unparseable → FAIL — the DAST gate is passable by a clean web app and still fail-closed | `# BL-122-ZAP-RISK-FILTER` excision + ZAP_INFO_LOW/MIXED/MALFORMED fixtures | open |
| BL-124 + BL-102 | High + Med | #204 | 3→4 gate FAILS on the `PENDING — required by track upgrade` marker; Market Signal gets Appendix D + WARN-first evidence arm (anchored placeholder regex) | marker-arm excision → RED; parity pin on empirically-clean issues=0 fixture | open |
| BL-107 | High | #205 | EVERY language gets the commit-msg TDD hook (rust inline-test attribute family incl. rstest/proptest/wasm_bindgen, staged+branch axes, `--no-ext-diff`); currency/freshness read "present" universally | `# BL-107-RUST-INLINE-TESTS` excision; scaffold-tdd suite gained rust/other real-init cases | open |
| BL-123 + BL-111 + BL-126 | High + High + Med | #206 | Branch-protection attestation recoverable post-hoc (`check-gate.sh --repair`, host-keyed, precondition-guarded, idempotent) and consulted by all three consumers | 11-case suite; fence-excision mutants both arms | open |
| BL-110 + BL-116 | Med + Med | #207 | `soloFrameworkCommit` pin stamped on the hermetic path too; push-gate exemption requires recorded `remote_repo_created`+`pushed_initial` | pin-stamp revert → T-scaffold-pin-stamped RED; scope-arm excision | open |
| BL-114 + BL-115 + BL-127 | Med ×3 | #208 | 0→1 gate survives placeholder sections (errexit guard) + real intermediates arm + `--start-phase1` consults the gate; approval evidence needs a DATED Date ROW section-bounded; UAT `results_received` needs real files (session_id-resolved, dotfile-excluded, recorded solo-attest escape) | 16-case suite incl. per-arm excisions; verifier SF#1 window-steal case | open |
| BL-105 | Med | #209 | Phase 4 has a real gate: `--start-phase4` consults 3→4, presence arm keys on `started_at` and the FILE's real phase (no circularity), three substantive-evidence arms, both templates gain UAT sign-off + attorney/pen-test slots | double-fence mutation in-suite; auto-advance T4 rewritten from bug-pin to refusal-pin | open |
| BL-115 follow-up (E1b verifier Claim-C) | — | #210 (`3fee6d3`) | Attorney evidence window SECTION-BOUNDED — a filled Pen-Test date no longer satisfies legal_review with a placeholder attorney Date | exit-at-next-section clause excision → RED on exactly the new case | open |
| BL-108 + BL-117 | Med + Med | #210 | init.sh ships all 5 gate-demanded templates + 4 guide-named tools, enforced FOREVER by a mechanical closure test (shipped-set = init cp lines; referenced-set = non-comment script text + guide; self-tested extractor); `production_build` demands dated build-smoke evidence | init cp-line revert → closure RED on exactly the shipped items; smoke-fence excision | open |
| BL-130 | Low | #211 (`f33a8da` + space-safe follow-up) | `--attest` REFUSES a scanner whose newest real verdict is FAIL (exit 2, cites BL-113's rule); SKIP-attest untouched; verifier's MUST-FIX landed — `# BL-130-SPACE-SAFE-LRV` makes the shared verdict oracle space-safe (it had silently blinded this guard AND BL-113's carry on spaced `--results-dir`) | in-suite fence excision, positively asserted; spaced-dir case RED-watched | open |
| BL-129 | Low | #211 (`09e39bf`) | `--help-non-interactive` states the REAL gov-mode mapping (personal: production/private_poc; organizational: production/sponsored_poc); stale "choosable" comments scrubbed | false-claim reinsertion → N30 RED | open |
| BL-096 | Low | #211 (`6a6a132`) | CDF preflight names the exact clone line at suite entry (warn-and-continue — CI runs CDF-less by design); `pre-commit-gate.sh --help` exists and tells the truth about `--tdd-only` (+ `--commit-msg-gates` alias, behavior-pinned); contributor hook install is one idempotent command | triple-arm single mutation run → exactly T5/T3/T7 RED | open |
| BL-095 | Med | #211 (`4d7a94a`) | ONE parsing surface for deployment/poc_mode (`# BL-095-STATE-READERS` in helpers-core.sh, null-safe both arms); 13 reader sites migrated; conforming-inline siblings documented (pre-commit-gate, run-phase3-validation, verify-install) | fence excision must CRASH check-phase-gate naming the missing reader (baseline rc=0 proven first); 16-suite blast-radius battery ALL GREEN | open |
| BL-128 | Med | #211 (`4d7a94a`) | Review generator headless-viable: per-review process-GROUP watchdog (`REVIEW_TIMEOUT_SECS`), continue-on-failure with trust/spend triage, incremental manifest, claude-free `--compose-only`/`--assemble-manifest` | combined 4-arm mutation → all 5 cases RED incl. the resurrected orphan (`grandchild-alive=yes`) | open |

**Also closed by the run:** BL-133 (stale BR-lint feed — filed and fixed inside WP-A3), BL-087 (mothership false-positive, folded into A3). **Filed as recorded residuals (Open):** BL-131 (DOM sinks no public semgrep rule covers — `insertAdjacentHTML`, jQuery `.html()`, `.vue` SFCs, inline `<script>` in `.html`), BL-132 (hook scans worktree bytes, not index content — pre-existing BL-112 design).

## 2. Stopped / flagged for Karl

- **BL-106** — product choice: machine-checkable platform go-live checklists vs downgrading the MANDATORY language. Both options written into the entry; nothing implemented.
- **Semgrep in the unit lane?** (from WP-A1) — would run the live DOM-XSS blocking proof on every PR at the cost of a registry fetch (latency/flake) per run. Shipped conservative: full lane only.
- **BL-133 surface question** (from WP-A3) — should the BR-lint feed instead move to the commit-msg surface (where the message is current) rather than being removed outright? Removed-outright shipped; the alternative is recorded in the entry.
- **Phase G (design notes in the ledger, entries stay Open):** BL-109 next rung is a product escalation (detect → offer-and-apply); BL-099 and BL-101 recommended for close-into-BL-109; BL-089 ready pending the IDENTIFIERS pre-seed list; BL-090 blocked on the Pantheon corpus for FP calibration; BL-091 sequenced behind 089; BL-092 last of the quartet with a split-list sign-off; BL-097/098/100 delegation trio hinges on ONE decision — normative text vs gate-checked evidence.
- **Phase H untouched by design:** BL-019/025/042/043/085 (DEFERRED), BL-087✓(folded)/093/094 (opportunistic — 093/094 not touched).

## 3. Blocked

**None.** No work package ended blocked. (The one mid-run incident — the stranded PR stack after non-ascending merges — was healed by landing merge PR #202, and Karl enabled auto-delete-head-branches to prevent recurrence.)

## 4. Verification

Commands any reviewer can run from a checkout of `fix/phase-f-bl129-bl130-bl096`:

```bash
# The Phase-F suites (all exit 0; tally lines shown in the ledger):
bash tests/test-bl130-attest-fail-guard.sh        # 3/3
bash tests/test-init-non-interactive.sh           # 32/32 (N30–N32 = BL-129)
bash tests/test-bl096-cold-start.sh               # 8/8
bash tests/test-bl095-state-readers.sh            # 8/8
bash tests/test-bl128-review-generator-headless.sh# 5/5
# The E-wave suites still green on this branch:
bash tests/test-bl114-bl115-bl127-gate-integrity.sh  # 17/17 (incl. T-attorney-bleed-blocked)
bash tests/test-bl105-phase4-wave.sh                 # 12/12
bash tests/test-bl108-bl117-ship-closure.sh          # 5/5
# Repo lints:
bash scripts/lint-tests-registered.sh             # OK
bash scripts/lint-evalprompts-portability.sh      # 3/3 clean
```

The 16-suite BL-095 blast-radius battery (bl084-tier, bl104, poc-block, backstop, date-writeback, poc-modes, trio, bl105, E2, auto-advance, bl102, bl116, bl124, upgrade-manifest-refresh, upgrade-bl030-backfill, intake-wizard-fixes): **ALL GREEN** — raw per-suite lines in the WP-F4 ledger entry.

**Adversarial verification:** eleven per-WP verdicts through Phase E (all SHIP; every should-fix landed pre-push or as a tracked follow-up), plus a consolidated Phase-E/F verifier (Fable-tier, refutation brief) against PR #211's commits. Its verdict: **SHIP-WITH-FIXES** — one MUST-FIX (`_p3_last_real_verdict`'s unquoted ls-loop silently defeated both the new BL-130 refusal and BL-113's no-launder carry on a spaced absolute `--results-dir`; **LANDED** as `# BL-130-SPACE-SAFE-LRV` with a watched-RED spaced-dir case, suite 4/4) and two SHOULD-FIXes (**LANDED**: count-floor vacuity guards in the mechanical-closure suite — the verifier's blinding mutant now fails loudly; widened inline-parse detector with a 7-variant self-test, suite 9/9). What HELD under attack: the BL-095 old-vs-new equivalence matrix (ten value shapes, both jq arms — no gate outcome can change), `--help` unreachable from every hook path, the BL-128 group-kill against TERM-ignoring and SIGSTOPped process trees, all 8 BL-129 combo probes, and every BL-115 attorney edge (all divergences fail-closed). Full disposition in the ledger's consolidated-verification entry; verdict comment on #211.

## 5. Escape hatches used

**ZERO.** No `--no-verify`, no `SOIF_PHASE_GATES=warn`, no `--ack-preconditions`, no forged artifacts, no test edited to pass except under the documented-bug exception (each such rewrite named in its WP entry and mutation-proved). `SKIP_LINT=1` appears ONLY inside test fixtures scoping suites to their subject (documented per-suite as test scoping, not gate weakening). `SOLO_UAT_SOLO_ATTESTED`/`SOLO_TDD_*` are the sanctioned RECORDED attestation class — used only inside fixtures that test them.

## 6. Honest limits

- **Untracked root files left untouched:** `DOGFOOD-2-PROMPT.md`, `EXECUTIVE-SUMMARY.md` (dogfood-2 artifacts Karl may want moved into this Reports dir), `.claude/skills/`, `.claude/worktrees/`. Deliberate — not named by the kickoff's Step 0.
- **BL-115 residuals:** approver-ROLE verification (CM-H-08) unaddressed; within the section-bounded attorney window a date in ANY table row still counts (Date-ROW-shape not mirrored — multi-column tables would false-reject).
- **BL-105 residuals:** validate.sh competency depth is PROJECT_INTAKE-based (4/9 domains); pass-path `--start-phase4` mechanics await a golden 3→4 fixture; a gate-side UAT-sign-off reader arm (the template section now exists as its home).
- **BL-095 scope:** parsing centralized, predicates untouched (by design); `track` migrated only where adjacent in check-phase-gate; three files stay conforming-inline for stated reasons (hook-brick class, self-containment, nested shape) — they are named sync siblings, which is a promise of discipline, not a mechanical guarantee.
- **BL-128:** the fix makes the live path bounded+resumable and adds a claude-free path; it does not make six live LLM reviews fast, and the timeout default (900s) is a guess pending real-world calibration.
- **BL-096 preflight** warns rather than aborts (CI constraint) — a fresh-host operator who ignores the warning still fails deep, just now with the clone line already printed at entry.
- **grep-based closure assertions** (BL-095's source-closure, E2's mechanical closure) can be gamed by creative reformatting; they catch drift, not adversaries. Mutation fences are the stronger guard.
- **The full ~3h suite was NOT run** (workflow_dispatch-only per CLAUDE.md); the unit lane, the touched-suite batteries, and the real-init aggregators relevant to each WP were.
