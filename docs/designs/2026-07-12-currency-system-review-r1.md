# Currency System design — adversarial review r1 (verdict: BLOCK)

**Reviewed:** `docs/designs/2026-07-12-currency-system-v1.md` (v1), 2026-07-12.
**Reviewer:** independent adversarial design refuter (top-tier model, same tier as the design author, per the verifiers-≥-implementers rule). Every claim ground-truthed against this repo on the reference host (macOS, bash 3.2) with count-based greps.
**Disposition:** all amendments folded into v1.1 of the design document (see its §0 changelog). This file is the audit record of the findings, condensed only by removing the reviewer's working notes; findings text is verbatim in substance.

## Verdict

**block.** The architecture (4 layers, consent-first, script-never-writes-Class-A, guard-registry doctrine) is sound and survived the strongest attacks. But the document contained claims contradicted by direct observation (the BL-100 block criterion), a dual-source-of-truth regression of the exact class that bit the predecessor, and Class-A mechanics that would violate the design's own invariant 3 for two of its four named artifacts. S1 built as written builds the wrong manifest file; S3 built as written stages placeholder-injecting merges.

**Ground-truth scorecard:** 35-test suite — exact. 25-row registry — exact (`grep -Ec '^check_guard '` → 25). All five markers present (BL-099-SYNC 2, DOC-GUARD 8, CONFIRM 4, APPLY-STATUS 9, PROMPT-FALLBACK 2). Sentinel wired on the sync path. SessionStart seam real (init.sh jq-injects session hooks; the generated CLAUDE.md Session Start rule "Do NOT auto-update anything — always ask first" is the teaching surface). `git merge-file`, `diff3`, `git apply` present (Apple Git 2.50.1). `guard_not_in_framework` ×6; two `-ef` guards.

## BLOCK findings

**B1 — "Layer 3 exists on main" was false as described; the riskiest refactor was assigned to no slice.** The only `soif_*` writer is `soif_write_precommit_hook` (scripts/lib/hook-templates.sh); `grep -c journal scripts/upgrade-project.sh` → 0; `grep -c "docs/updates"` across scripts/init.sh → 0. The landed engine is per-call-site `cp` + `_bl099_write_ok` post-checks + `.bak` files (9 `# BL-099-APPLY-STATUS` sites), and its cp-writes follow symlinked destinations. Migrating ~9 write sites plus hook writes into one primitive while keeping 35 tests + 25 rows green is the most defect-prone step of the whole build and was named nowhere in §5. → v1.1: §2-L3 retitled target-state with the landed foundation described honestly; new slice S3a (write-primitive promotion) incl. symlink lstat-refusal, WAL ordering, cross-FS temp placement, kill-mid-batch recovery rows.

**B2 — Manifest split-brain; the Layer-1 check was unimplementable as specced.** The pins already live in `.claude/manifest.json` (init.sh MANIFESTEOF block + jq soloFrameworkCommit birth-stamp + CDF's frameworkVersion/frameworkCommit via scripts/lib/cdf-refresh.sh); the design's new `.claude/framework-manifest.json` would be a second overlapping truth — the predecessor's dual-source class reborn at the fact base. And nothing anywhere records where the solo framework clone lives (`grep -c "SOLO_FRAMEWORK_HOME\|FRAMEWORK_DIR" scripts/upgrade-project.sh` → 0; --sync-framework works only because it must be run FROM the framework checkout) — so "framework pin vs clone" had no path to check, and the design's own "zero env-var channels" forbids the obvious hack. → v1.1: extend `.claude/manifest.json` with one `currency` block; `soloFrameworkPath` stamped at init and re-stamped by every sync/apply, with the `_bl099_stamp_pin`-style skip contract.

**B3 — Class A mechanics were wrong for half their members, dropped the BL-101 mechanism the design claimed to absorb, and contradicted invariant 2 at rollback.** (a) PRODUCT_MANIFESTO.md and PROJECT_BIBLE.md are created by NO script (`grep -c "PRODUCT_MANIFESTO.md" init.sh` → 0; same for the bible; init.sh ships only the .tmpl skeletons) — a render-output sha is unstampable and a line-level three-way against wholly user-authored prose is noise. (b) For the two real renders, v1's merge legs were template-then/template-now/user-file — template hunks overlapping substituted lines inject `__PROJECT_NAME__`-class text into the staged candidate (the I3 nightmare); BL-101's actual mechanism (parameterize the generator, recover vars, re-render) appeared nowhere. (c) §2-L3's `--rollback` "restores from that run's archive" with no carve-out directly contradicted I2 for runs containing Class-A items. → v1.1: Class A split into A1 (script-rendered; generator-leg three-way; conflicts stay in the candidate) and A2 (agent-authored; structural diff only, no merge ever); rollback stages and instructs, never writes; I2 gains "including `--rollback`".

**B4 — The taxonomy could not express upstream deletion or rename.** Upstream renames check-phase-gate.sh → phase-gate.sh: a plan with add/change verbs only stages the new file and leaves the old executable enforcing stale rules forever, still manifest-listed. The verb field is S1 schema — retrofitting later means a migration. → v1.1: verbs `add | update | retire | rename`; retire = archive-then-delete, item-consent always; detection reports orphans.

## MAJOR findings (condensed; full amendments in v1.1 §0 map)

- **M1** Changelog roll-up infeasible when the pin predates the clone boundary — `~/.claude-dev-framework` is cloned `--depth 1` (verified shallow; `git log <absent-pin>..HEAD` → fatal). → best-effort roll-up with the shallow fallback line; never network-fetch during `--plan`.
- **M2** Apply-time TOCTOU + same-day run-id collision between concurrent sessions. → run-id gains time+pid + exclusive mkdir; per-item base-sha re-verify + framework-pin check at apply; clean-tree precondition.
- **M3** Class-A archive staleness window (plan-time archive vs later edits). → `--archive-item` immediately before editing; `--verify` refuses across unexplained base drift.
- **M4** UPDATE-PLAN checkboxes vs manifest selections = a new dual source of truth (the slug-parity class). → checkboxes are the single human surface; `--apply` parses them into the manifest as one-way journal.
- **M5** Enforcement-tier drift was indefinitely snoozeable. → 7-day auto-expiry, recorded via `scripts/lib/bypass-audit.sh`, standing "N enforcement items snoozed" line.
- **M6** I7's letter violated by its own TTL `git fetch` (a write), and concurrent SessionStarts tear the cache. → zero network at session start; atomic cache; honest origin-staleness aging; cache gitignored.
- **M7** Hook writes (arbitrary code on every commit) were batch-consentable; supply chain is an unauthenticated https clone. → new I11: hooks/gate scripts never batch-consented, full diff + provenance, origin-URL change warning, pin-ancestry tripwire.
- **M8** Reviewer prompt-injection via upstream content (commit messages/template comments steer the model whose prose steers selection). → mechanical facts computed script-side; advisory confined + injection-pinned; roll-ups fully mechanical (Haiku call deleted).
- **M9** "Expected-absent" laundered BL-107's bug into a fact (Rust deliberate vs `*)` silent). → three-state enum; `absent-unavailable` reports at enforcement tier and converts to an `add` item when upstream fixes.

## MINOR findings (all folded)

BL-102 tense; per-template placeholder grammars ∪ conflict markers, live-files scan scope; run-folder commit scope + prune rules; tool-baseline cut (existing data-driven check); I1 carve-outs + spaced-path and symlink fixtures; the no-timeout host trap stated; T-vs-M one-liner; S1→S2 dependency; APFS note; date-stamped counts.

## SOLID (held under attack)

The Class-A fence (I2, end-to-end once B3c landed); the consent model (I5/I6, inheriting the proven `# BL-099-CONFIRM`/`# BL-099-PROMPT-FALLBACK` discipline); the guard-registry doctrine (anti-cheat steps foreclose vacuous rows; 25 rows verified live); session-start feasibility (measured ≈0.5s for the full shipped surface; zero-network makes the budget hold); the SessionStart seam claim (real, three hooks already injected); decision 1 (no silent auto-apply — survives once M5 lands); fail-open detection; the Class T pipeline (it IS the landed behavior); and the no-agent Class-A mechanics (patch + candidate + `git apply` by the operator's hand — invariant 2 preserved).

## Residual risk (accepted into v1.1 §7)

Class-A's last mile is human/agent behavior: mechanical verification proves absence-of-catastrophe, not merge correctness. The fence is still the right trade; the mitigation is a cheap archive/rollback loop. A poisoned framework clone remains a channel; I11 raises its cost, does not eliminate it.

## Unverified (stated, not guessed)

Claude Code harness-side SessionStart constraints (output size, hook timeout); the specific matrix rows for semgrep/python in the data-driven tool check (mechanism verified, rows not); which suite tests pin the two out-of-registry guards; Pantheon's on-disk state; the Haiku/Sonnet ↔ BL-097 tier naming (BL-097 speaks in tiers — the design's model names are an interpretation).
