# Solo Orchestrator — Remediation Plan (junior-engineer runbook)

**Written:** 2026-07-13, after the Dogfood 2 end-to-end walk.
**Scope:** every OPEN backlog item — the 13 new Dogfood-2 findings (BL-118…BL-130) **and** the 31 pre-existing open items — sequenced highest-severity-first, grouped so one sitting closes related items.
**Companion:** [`FINDINGS.md`](./FINDINGS.md) (what was found) · [`LEDGER.md`](./LEDGER.md) (the raw step-by-step evidence, S-001…S-023) · `solo-orchestrator-backlog.md` (the canonical entries).

You do not need to have watched the walk. Everything you need is here or one grep away.

---

## 0. Before you touch anything (read once)

**Set up the two repos** (tests and `init.sh` hard-require the CDF checkout):
```bash
git clone https://github.com/kraulerson/claude-dev-framework.git ~/.claude-dev-framework
# in the framework repo:
cp scripts/pre-commit-gate.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
```

**The five house rules you must not break** (they are also how each fix below is verified):
1. **No merge on red, ever.** No `gh pr merge --admin`. Never `--no-verify`.
2. **TDD with mutation proofs for every enforcement change.** Break the marked line → run the test → see RED → restore → see GREEN. *Prove* the gate fires; do not assert it. Half of the bugs below exist because a gate was "reachable" but never mutation-tested against a real trigger.
3. **Portability: GNU-first, then BSD.** `stat -c … || stat -f …`. **Never** rely on GNU-only regex in `sed`/`grep` (this is literally BL-121). macOS is the dev platform; test on it.
4. **Cite code by a grep-able `# BL-NNN-…` marker or a function name — never a bare `file:line`.** Line numbers drift within a day.
5. **Register every new `tests/test-*.sh`** in BOTH `tests/full-project-test-suite.sh` AND the `unit` list in `.github/workflows/tests.yml` (`lint-tests-registered.sh` enforces).

**The one trap that hid two prior bugs — the `[WARN]` trap in `check-phase-gate.sh`:** the block/pass decision is `if [ $issues -eq 0 ]`, so any arm that prints `[WARN]` *and* runs `issues=$((issues+1))` **BLOCKS**, while a true non-blocking WARN must **omit** the increment. Read the increment, not the label. (This is why BL-121's "warning" is actually a hard block.)

**Where the gates live (your primary targets):**
| Script | What it gates |
|---|---|
| `scripts/pre-commit-gate.sh` | commit-time gates (SAST arm, Build-Loop classifier, TDD ordering) |
| `scripts/check-phase-gate.sh` | phase 0→1 / 1→2 / 2→3 / 3→4 gates |
| `scripts/process-checklist.sh` | Build-Loop / UAT / phase-init step machine |
| `scripts/run-phase3-validation.sh` | the 5 Phase-3 scanners |
| `scripts/test-gate.sh` | bug gate + feature/UAT counters |
| `init.sh` | scaffolds all of the above into generated projects |

**Local verification loop** (run before every commit): `bash scripts/run-lints.sh` (all repo lints; ~2 min — the two full-tree scans are slow, not hung), plus the specific `tests/<file>.sh` for what you touched. The reliable pass/fail signal is the **process exit code**, not the tally line.

---

## How to read the sequence

Work packages are ordered by risk. **Do them top to bottom.** Each package lists: the BL items it closes, why it's grouped, the exact target (marker/function), the reproduce command, the fix, and the **mutation proof** that is your definition of done. Start at WP-A1.

> Rule of thumb for ordering: **a gate that reports "safe" on a real vulnerability (Phase A) outranks a gate that wrongly blocks safe work (Phase B), which outranks a gate that is merely absent (Phase E), which outranks hygiene (Phase H).** A false "all clear" on security is the most dangerous state a framework can be in.

---

# PHASE A — Security enforcement (a gate says "clean" on a real vulnerability)

*The Dogfood-2 walk shipped a live stored XSS to `main` past three independent controls. Each of the three should have caught it. Fix all three; then no single miss is fatal.*

## WP-A1 — SAST ruleset is blind to DOM XSS  ·  **BL-118 (Critical)**

**Why first:** this is the framework's flagship security promise (commit-time SAST on the flagship `web` platform) reporting "no findings" on the #1 web vulnerability. It is the single most dangerous defect in the backlog.

**Target:** the Semgrep invocation behind the `# BL-112-SAST-ERROR` marker in `init.sh` (which scaffolds `.git/hooks/pre-commit`), and the `config:` block of `.github/workflows/ci.yml` (both the framework's and the one `init.sh` generates).

**Reproduce (positive control — do this first so you believe the fix):**
```bash
cat > /tmp/sink.ts <<'EOF'
export function danger(x: string, el: HTMLElement){ eval(x); el.innerHTML = x; document.write(x); }
EOF
semgrep scan --config=p/owasp-top-ten --severity=ERROR --error /tmp/sink.ts   # → 0 findings  ← the bug
semgrep scan --config=r/javascript.browser.security.insecure-document-method /tmp/sink.ts  # → flags innerHTML+write
```

**Fix:** add `--config=r/javascript.browser.security.insecure-document-method` to the pre-commit hook's semgrep line **and** to `ci.yml`'s config list. Keep `--severity=ERROR --error` (block only high-confidence). Consider `--config auto` where the network allows, wrapped in the BL-113 offline-attestation discipline so an unreachable registry is a loud SKIP, not a silent pass.

**Mutation proof (definition of done):** write `tests/test-bl118-sast-dom-xss.sh` that scaffolds a project (or uses the marker's unit harness), stages a file containing `el.innerHTML = userInput`, runs the generated pre-commit hook, and asserts **non-zero exit + a `[BLOCKED]` line**. Then break the fix (remove the new `--config`) and confirm the test goes RED. Register the test in both required lists (house rule 5).

**Watch for:** the framework repo can't self-trigger this path (`check_commit_message` short-circuits at `current_phase < 2`, and the framework has no `phase-state.json`) — your test must drive a *generated* project or the hook directly.

## WP-A2 — the other two controls that missed the same XSS  ·  **BL-120 (High) + BL-125 (Medium)**

**Why grouped:** BL-118, BL-120, and BL-125 are three independent gates that all waved the same real XSS through. Defense in depth means each must catch it.

**BL-120 — `security_audit` step reads no verdict.** Target: the `ls docs/security-audits/*"${feature_slug}"*` existence check in `process-checklist.sh`. Fix: require a machine-readable verdict line in the audit artifact (e.g. `**Verdict:** PASS|FAIL`, `**Open critical/high:** N`) and FAIL the step on `FAIL` / N>0. Mutation proof: an audit file whose verdict is `FAIL` must block `--complete-step build_loop:security_audit`; flip it to `PASS` → passes.

**BL-125 — no test execution at commit time.** Target: the commit path (`pre-commit-gate.sh` / `framework-gate.sh`) or the `implemented`/`security_audit` completion in `process-checklist.sh`. Fix: run the project's configured test command and block on failure, with the *same* "tool-not-runnable → loud SKIP, never silent pass" discipline as the SAST arm. Keep latency sane (changed-file-aware or a fast lane). Mutation proof: stage code that makes a committed test RED → commit blocked; make it green → commit allowed.

## WP-A3 — the strict gate bricks the repo after a blocked commit  ·  **BL-119 (High)**

**Why here:** it's a security-adjacent gate that is also a **hard dev-loop blocker** — once you start fixing enforcement code you *will* trip it, so fix it early or you'll fight it all week.

**Target:** the `TERMINAL_MODE` block in `pre-commit-gate.sh` that reads `.git/COMMIT_EDITMSG`, invoked from `.git/hooks/framework-gate.sh` at **pre-commit** time (where the file still holds the *previous* commit's subject).

**Reproduce:** on a strict organizational scaffold, land a `feat:` commit through a full Build Loop, then `git commit -m "docs: x"` → wrongly blocked as `'feat(...)'`.

**Fix:** stop running the commit-*message* classifier at `pre-commit` — the `commit-msg` hook already runs it with the correct message. Either drop the message check from `framework-gate.sh`'s pre-commit path, or thread the real prospective subject to it. Mutation proof: `tests/test-bl119-…sh` — a `docs:`-only commit immediately after a `feat:` commit must succeed; revert the fix → RED.

---

# PHASE B — Release-gate correctness (a gate wrongly blocks a clean release)

## WP-B1 — BSD-sed miscount hard-blocks the production gate on macOS  ·  **BL-121 (High)**

**Target:** the `cutline_items=$(sed -n '/Must-Have/,/Should-Have\|Will-Not-Have\|---/p' … )` line in `test-gate.sh`. `\|` is GNU-only; BSD reads it literally so the range runs to EOF.

**Reproduce (macOS):** `bash scripts/test-gate.sh --check-phase-gate` → `Feature count (N) < MVP Cutline items (68)`; and `printf 'A\nSTOP-B\nC\n' | sed -n '/A/,/STOP\|NOPE/p'` prints all 3 lines.

**Fix:** replace with an `awk` range using a real regex (`/Should-Have|Will-Not-Have|^---/`) or bound the count to the `## 5. MVP Cutline` → `**CUTLINE**` section. Mutation proof: a fixture manifesto with a known 3-item cutline must count **3** on both GNU and BSD sed. **Also extend `lint-counter-antipattern.sh` to flag `sed` alternation** so this class can't recur (house rule 3).

## WP-B2 — the DAST gate is unpassable for any web app  ·  **BL-122 (High)**

**Target:** `findings=$(jq '[.site[]?.alerts[]?] | length' …)` behind `# BL-070-ZAP-DISPATCH` in `run-phase3-validation.sh`. It counts every alert including Informational; ZAP rule 10049 fires under *every* Cache-Control value.

**Reproduce:** run the driver against any clean static site (`FAIL-NEW=0`) → `[FAIL] zap-dast — 1 alert`; the alert is `riskcode: 0`, `pluginid: 10049`.

**Fix:** filter by risk — `jq '[.site[]?.alerts[]? | select((.riskcode|tonumber) >= 2)] | length'` (Medium+), matching the semgrep arm's `--severity ERROR` philosophy. Mutation proof: a report JSON containing only a `riskcode:0` alert → PASS; add a `riskcode:2` alert → FAIL.

## WP-B3 — the ratchet asks but doesn't check  ·  **BL-124 (High) + BL-102 (Medium)**

**Why grouped:** these are the two halves of the promotion hole the walk's central question exposed. The upgrade tool re-opens the light-track skips; the gate never reads them.

**Target:** `check-phase-gate.sh` Phase 3→4 section (add the check); the marker `upgrade-project.sh` writes is `PENDING — required by track upgrade`.

**Reproduce:** `grep -rl PENDING scripts/check-phase-gate.sh scripts/test-gate.sh` → no matches (only `upgrade-project.sh` writes it); `grep -rli 'market.signal|1\.1\.5' scripts/*.sh` → no matches.

**Fix:** in `check-phase-gate.sh`, FAIL the Phase 3→4 gate (track-keyed standard/full) when `PRODUCT_MANIFESTO.md` Appendix A or C still carries a `PENDING` marker (BL-124), and enforce a Market Signal evidence artifact for standard+ (BL-102 — decide the evidence shape: a dated line in the Bible/Manifesto appendix, same pattern as the ZDR attestation). Wire the tool that *writes* `PENDING` to the gate that *reads* it. Mutation proof: a manifesto with `Appendix A: … PENDING` blocks the standard/full gate; filled-in → passes; a light-track project is unaffected.

---

# PHASE C — TDD-gate coverage

## WP-C1 — whole languages get no TDD gate  ·  **BL-107 (High)**

**Target:** the language→test-convention logic in `init.sh` that installs the `commit-msg` TDD hook (Rust is skipped for inline `#[cfg(test)]`; `other` falls through). The docs advertise the TDD hard-block as non-bypassable on organizational/production tiers — but Rust and `other`-language projects on those tiers get **no gate at all.**

**Fix:** install a TDD gate for every language, using a language-appropriate test-file heuristic (for Rust, detect `#[cfg(test)]` / `#[test]` additions in the same or a sibling file; for `other`, a conservative "does any staged file look like a test" heuristic with an attested escape). Mutation proof: scaffold a Rust (and an `other`) organizational project, stage impl with no test on a `feat:` commit → must hard-block; add a test → passes.

---

# PHASE D — the `--no-remote-creation` / branch-protection blind spot (one flow, four findings)

## WP-D1 — branch-protection attestation: unsatisfiable + inconsistent  ·  **BL-123 (High) + BL-111 (High) + BL-126 (Medium)**

**Why grouped:** all three are the same attestation machinery. The attestation is writable only inside `init.sh`'s in-flight fallback (BL-111 offline, BL-123 real-remote), and one of its three readers ignores it (BL-126).

**Fix (one lever closes BL-111 + BL-123):** give `check-gate.sh` an attestation-recording path — accept `--branch-protection-attested` / honor `SOLO_BP_ATTESTED=1` — so the documented `check-gate.sh --repair` remediation can actually record the `github_free_tier` attestation *post-hoc*, instead of pointing at a flag only `init.sh` accepts. **BL-126:** make `process-checklist.sh::verify_init()` read the attestation reason before calling `host_verify_protection`, exactly as `check-gate.sh --preflight` and the `check-phase-gate.sh` backstop already do (ideally via a shared helper — see WP-F4/BL-095).

**Mutation proofs:** (BL-123/111) a project that hit the 403 with no flag can be recovered by `check-gate.sh --repair --branch-protection-attested` alone; (BL-126) `verify_init` on an attested free-tier scaffold reports `[OK]`, matching `--preflight`.

## WP-D2 — the same uncovered flow on the pin and push axes  ·  **BL-110 (Medium) + BL-116 (Medium)**

**BL-110:** `soloFrameworkCommit` is never stamped on `--no-remote-creation` scaffolds (freshness pin absent on the hermetic path). **BL-116:** the "MANDATORY, non-bypassable" push gate is implemented only for `host=other`; first-class hosts scaffolded `--no-remote-creation` never get it. **Fix shape (both):** key the behavior on *"was a remote actually created/pushed"* (the manifest records it), not on host brand or code path. Mutation proof for BL-116: a `github` project scaffolded `--no-remote-creation` with no pushed branch must FAIL the push gate.

---

# PHASE E — hollow gates & missing enforcement sweep

## WP-E1 — declared MUSTs with no check  ·  **BL-105 (Med) + BL-127 (Med) + BL-115 (Med) + BL-114 (Med, incl. F-DF2-003) + BL-106 (Low)**

**Why grouped:** these are one class — a step or document the process declares mandatory, gated by existence-or-nothing.
- **BL-105:** rollback test / monitoring / go-live / UAT sign-off / trademark / revenue / competency matrix / Go-No-Go have no home and no check. Give each a machine-checkable artifact + gate arm.
- **BL-127:** the 9-step UAT process demands zero evidence (`results_received` passes with an empty `submissions/`). Gate the evidence-bearing steps on real files (with an explicit attested solo-mode for Light track).
- **BL-115:** approval evidence is satisfiable without approval (any date in a 15-line window; the attorney gate is satisfied by its own template header). Tighten the proximity/format and require a non-template value.
- **BL-114 (+ F-DF2-003):** the 0→1 gate integrity bugs, and `--start-phase1` advances with no gate consult and is undocumented in `--help`. Make `start_phase1` consult the gate; add it to `--help`; fix the errexit-kills-the-WARN and the never-blocking intermediates WARN. **Mind the `[WARN]` trap** (§0).
- **BL-106:** platform-module go-live checklists are declared MANDATORY and parsed by nothing.

Each fix is small; the *pattern* is the point — an existence check is not enforcement. Mutation proof per item: the gate must FAIL when the declared thing is absent/false, and PASS when present/true.

## WP-E2 — shipped instruction points at an unshipped dependency  ·  **BL-108 (Med) + BL-117 (Med)**

**Why grouped:** the "BL-088 class" — a gate or guide names a file `init.sh` never ships. **BL-108:** templates that exist but aren't shipped (incl. `security-audit-findings.tmpl`, which a gate's own error message tells the operator to use). **BL-117:** the production build ships without its own migration asset, and `check-maintenance.sh` is never scaffolded. **The durable fix (do this, not just the one-offs):** extend the `[[bl088-scaffold-source-closure]]` check from *sourced scripts* to *every path any shipped script or guide names* (templates, tools, artifacts), mechanically derived so it can't drift — that single check would have caught five of six recurrences. Also add a **smoke arm** to `production_build` (the built artifact must actually start). Mutation proof: reference a not-shipped template in a scaffolded gate → the closure check FAILs.

---

# PHASE F — tooling & doc correctness

| WP | BL | Sev | Fix in one line | Verify |
|---|---|---|---|---|
| F1 | **BL-128** | Med | Make `run-reviews.sh` viable headless: per-review timeout + process-group teardown, write the manifest **incrementally**, surface trust-dialog/spend-limit as errors, add a `--compose-only` mode. | Generated project → generator terminates and leaves a valid partial manifest. |
| F2 | **BL-129** | Low | Correct `init.sh --help-non-interactive` gov-mode text to match the code; scrub the dead `organizational + private_poc` "choosable" comments in `enforcement-level.sh` + `init.sh`. | `--validate-only` matrix matches the help. Doc-only. |
| F3 | **BL-130** | Low | `run-phase3-validation.sh --attest` must refuse/warn when the scanner's last result is FAIL (distinguish SKIP-attest from FAIL-attest). | Attesting a FAILing scanner → refused; BL-113 unchanged. |
| F4 | **BL-095** | Med | Centralize deployment/`poc_mode` parsing (9 scripts inline it today) into one helper — this is the *enabler* that makes BL-126 (and future drift) a one-line change. Change in sync with the `# BL-084-TIER-KEY` siblings. | All 9 call sites use the helper; tier tests green. |
| F5 | **BL-096** | Low | Cold-start hardening bundle: CDF preflight, `--tdd-only` help truth, contributor hook bootstrap. | Fresh-clone contributor path works without tribal knowledge. |

---

# PHASE G — larger operator-directed features (schedule as projects, not bug-fixes)

These are **features/refactors**, not gate fixes — each is a planning effort of its own. Do them after Phases A–F unless a product priority reorders them. **BL-109 is High** but it is a ground-up system, not a one-sitting fix.

| BL | Sev | What it is |
|---|---|---|
| **BL-109** | High | The Currency System — session-start freshness, staged review-folder updates, consented apply with archive/rollback. The framework's answer to "how do generated projects stay current." Ground-up; slices S1–S3 already landed — continue the slice plan. |
| BL-099 | Med | Complete the auto-update system (session-start freshness for framework/hooks/CDF + `--sync-framework`). Overlaps BL-109 — coordinate. |
| BL-098 | Med | Plan-first execution — strongest model writes a junior-followable build plan before subagents build. |
| BL-100 | Med | Adversarial verification of delegated work — official acceptance step for subagent-built changes. |
| BL-089 / 090 / 091 / 092 | Med/Low | Documentation-foundation quartet (doc map + identifier registry; `check-doc-refs`; docs-rules section; CLAUDE.md modularization). Do 092 LAST (largest). |
| BL-101 | Low | Assisted apply for rendered docs (regenerate CLAUDE.md/PROJECT_INTAKE from recovered vars + 3-way merge). |
| BL-097 | Low | Subagent model-selection rubric (assess-and-select vs inherit session model). |

---

# PHASE H — opportunistic / hygiene (do when you're already in the file; several are DEFERRED)

| BL | Sev | Note |
|---|---|---|
| BL-087 | Low | BL-006 commit-msg would hard-block inside the framework repo if a hook were installed (latent); `--amend` surface asymmetry. Touches the same code as WP-A3/BL-119 — **do it while you're there.** |
| BL-093 | Low | Split the backlog audit-trail into an archive file (92% is closed history). Pairs with BL-089. |
| BL-094 | Low | Grep-anchored function/section indexes for the 5 biggest scripts. Do while adding markers for the fixes above. |
| BL-019 | Low | `verify-install.sh` non-interactive audit — DEFERRED; bundle with the next `verify-install` visit. |
| BL-025 | Low | Phase-2 init-verified state test helper — OPPORTUNISTIC; build only when a gate-wave test needs it. |
| BL-042 | Low | `init.sh prompt_install` + pipefail on closed stdin — DEFERRED; test-only workaround in tree. |
| BL-043 | Low | `intake-wizard.sh` `main()` extraction — DEFERRED; hygiene. |
| BL-085 | Low | Make the ~3h full suite CI-fast — DEFERRED; manual dispatch works. |

---

## Appendix — every open item, mapped

**New (Dogfood 2):** BL-118→WP-A1 · BL-119→WP-A3 · BL-120→WP-A2 · BL-121→WP-B1 · BL-122→WP-B2 · BL-123→WP-D1 · BL-124→WP-B3 · BL-125→WP-A2 · BL-126→WP-D1 · BL-127→WP-E1 · BL-128→WP-F1 · BL-129→WP-F2 · BL-130→WP-F3 · (F-DF2-003→BL-114 addendum, WP-E1).

**Pre-existing open:** BL-102→WP-B3 · BL-105/106/114/115→WP-E1 · BL-107→WP-C1 · BL-108/117→WP-E2 · BL-110/116→WP-D2 · BL-111→WP-D1 · BL-095→WP-F4 · BL-096→WP-F5 · BL-089/090/091/092/097/098/099/100/101/109→Phase G · BL-019/025/042/043/085/087/093/094→Phase H.

**Suggested first week:** WP-A1 (BL-118), WP-A3 (BL-119, unblocks your own commits), WP-B1 (BL-121, unblocks the production gate on your Mac), then WP-A2. Those four remove the "security gate lies," "repo bricks itself," and "release gate can't pass on macOS" failures — the ones that make everything else hard to work on.
