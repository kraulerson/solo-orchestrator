# Team Orchestrator — architecture design v1

## Document Control

| Field | Value |
|---|---|
| **Document ID** | TEAM-001-ARCH |
| **Version** | v1.0, 2026-08-02 — **pre-review draft.** No adversarial round folded yet; §0.2 is the reserved amendment map. |
| **Classification** | Product architecture — normative-once-reviewed for the build |
| **Audience** | (a) the adversarial design reviewer this document must survive; (b) IT leaders of the sister companies invited to review and shape it at the ~2026-08-11 session |
| **Product** | **Team Orchestrator** — a fork of Solo Orchestrator for development teams of **2–10 people** |
| **Companion documents** | SOI-002-BUILD (`docs/builders-guide.md`) · SOI-003-GOV (`docs/governance-framework.md`) · SOI-004-INTAKE (`templates/project-intake.md`) · `docs/designs/2026-07-24-operating-model-v1.md` (the delegation substrate this design consumes) |
| **Status of the thing described** | **Nothing is built.** Team Orchestrator does not exist in any repo today (`grep -rni 'team.orchestrator'` over this tree returns zero hits outside this file). Every "exists today" claim below is about **Solo Orchestrator**, the asset base being forked. |

**Provenance.** Five decisions were settled by an adversarially-verified analysis before this
document was commissioned (§0.1). This design works **within** them; it does not relitigate
them. Where the repository contradicts or materially corrects the framing those decisions
were stated in, the correction is flagged in place and in §0.3 — never silently designed
around.

**Structural model.** `docs/designs/2026-07-24-operating-model-v1.md` is the house exemplar
and this document copies its discipline: a §0 traceability block, decision tables with one
recommendation and stated rejected alternatives, an honest mechanical/auditable/advisory
tiering of every enforcement claim, and — above all — **every "exists today" claim carries a
verification anchor**. Per the house citation rule, anchors are **grep-able marker comments**
(`# BL-NNN-…`) or **function names**, never bare `file:line`.

---

## Plain-English overview — read this first (about two minutes)

Solo Orchestrator is a system that lets **one** person, working with AI assistants, build and
ship production software with the paperwork and safety checks a real IT department expects.
It works by writing a set of small "state files" into the project — a record of which phase
the project is in, what has been approved, who bypassed which safety check and when — and by
installing automatic gates that refuse a commit when the rules are not met. It is deliberately
hard to cheat: you can route around a block, but you cannot route around the record of it.

The catch is in the name. Every one of those records assumes **exactly one person**. There is
one "what phase are we in" file, one "who is waiting for approval" flag, one list of tool usage.
Two people working at the same time do not break the safety checks — they break the
**bookkeeping**, and they break it in two ways. Their edits collide in version control. And,
more seriously, the records start lying: because the system works out "was this a human or the
AI?" by checking a list that exists only on one person's computer, a second developer's perfectly
legitimate work shows up in the first developer's audit trail as unexplained activity. Nobody did
anything wrong, and the audit trail says otherwise. That is the single problem this design
solves.

**Team Orchestrator** is a separate product, created by copying Solo Orchestrator wholesale
into its own repository, then rebuilding the bookkeeping layer for teams of two to ten people.
Three things change, and only three:

1. **The records learn who you are.** The project gains a *roster* — a short, committed list of
   team members, their version-control identities, and their roles. Every record that used to
   say "the operator did this" now says which named person did it. Records that belong to one
   person get their own file so two people never collide; records that belong to the whole
   project stay shared.
2. **The governance layer is imported, not invented.** Solo Orchestrator already ships an
   *organizational* track built for multiple humans — separate approvers per phase gate, a rule
   that you cannot approve your own work, an escalation ladder, a mandatory backup maintainer,
   quarterly portfolio reviews. Today that layer describes roles on paper. Team Orchestrator
   binds those roles to the named people on the roster, so the checks become automatic instead
   of aspirational.
3. **Two new AI roles.** A **Business Analyst** agent that turns a rough project request into
   the structured requirement documents the system already expects, and a **Project Manager**
   agent that keeps the decision log, the feature list, and the approval record current. We
   deliberately did *not* add a "scrum master" agent — there is no team of humans for it to
   unblock, and the coordination it would perform is already done by the written artifacts.

**What does not change is the important part.** The security scanners, the commit-time gates,
the phase approvals, the tiered strictness levels, and roughly a megabyte of proven enforcement
code all carry over untouched. The fork is a *bookkeeping* rearchitecture, not a safety
rearchitecture.

Two more things IT leadership should know. First, the two products are meant to **drift apart
on purpose**: shared improvements flow automatically for the first few months, then the channel
narrows to a shared toolbox, and after that changes cross between them only by deliberate,
reviewed decision. Second, Solo Orchestrator's own governance says an application must not stay
solo-maintained forever once it crosses defined size thresholds — today it "graduates" to a
conventional engineering team with no structure waiting for it. Team Orchestrator **is** that
structure. Graduation stops being an exit and becomes a supported migration.

---

## §0 — Decision traceability

### §0.1 — Settled decisions carried into this design

These five were settled by prior adversarially-verified analysis. This document designs
**within** them. Each row names where the design work for it lives.

| # | Settled decision | Designed in |
|---|---|---|
| **D1** | **Fork-and-modify into a separate repository.** The fork starts as a full copy with shared git history. In-repo variance was ruled untenable (the state rewrite reaches a large fraction of the suite — §3.2); a thin "kit" was ruled a capability desert. The fork arrives owning the entire proven asset base. | §3 |
| **D2** | **The merge channel is TEMPORARY by design.** Weekly `git merge upstream/main` while divergence is shallow, decaying to lib-only (`scripts/lib/` + lints + hooks + templates) within roughly two quarters once the state rewrite lands. After that, cross-propagation runs through the **family Change Assessor**, a separate coordination-repo agent. | §4 |
| **D3** | **Day-one fork protocol.** Recreate branch protection and install the pre-commit hook **before the first commit**; keep the inherited backlog frozen as audit substrate with fork-prefixed new entries; every red suite gets fix-or-recorded-retirement, never bulk deletion. | §3.3 |
| **D4** | **Roles verdict.** A **BA agent** and a **PM agent** are IN — both have real mechanical value over surfaces that already exist. A **scrum-master persona is OUT** — process theater with no team to unblock. | §7.2, §7.3, §7.4 |
| **D5** | **Graduation-as-migration.** Solo's governance doctrine forbids indefinite solo operation past defined thresholds and today graduates an application to an *unstructured* receiving team. Team Orchestrator is the structured landing zone; migration from a solo-generated project is a first-class intake path. | §8 |

### §0.2 — Amendment changelog (reserved)

v1.0 is the pre-review draft; no adversarial round has been folded. This section is the
reserved home for the finding → resolution map, written in the house style: corrections
**rewritten on top, not accreted**, each naming the section it changed.

### §0.3 — Verification posture, and where the repository corrected the brief

Every claim below marked *verified* was re-derived against this tree on **2026-08-02** by grep
or by reading the named function. Four findings materially correct the framing the settled
decisions were handed to me in. **None of them invalidates a settled decision**; all four are
scope corrections, and all four are designed for rather than around.

| # | Correction | Consequence |
|---|---|---|
| **C1** | **The `.claude/` singleton surface is larger than the eleven files named in the brief.** Grepping `init.sh`, `scripts/`, and `templates/` for `.claude/` paths yields **19 distinct files plus 5 directories** (§5.1). The brief's list omitted `pending-approval.json`, `tdd-warn-ledger.jsonl`, `license-policy.json`, `dast-headers.json`, `test-command`, `last-checked-commit.txt`, `last-gate-pass.txt`, and `process-audit.log`. | §5.1 designs the measured inventory, not the brief's. WP sizing in §10 reflects the larger surface. |
| **C2** | **Nearly all of `.claude/` is version-controlled.** The shipped ignore template (`templates/generated/gitignore-base.tmpl`) carries exactly **two** `.claude/*` ignore lines — `last-checked-commit.txt` and `last-gate-pass.txt`, both under the `SYNC SIBLINGS (BL-174)` comment — plus an incidental `*.log` pattern that covers `.claude/process-audit.log`. Everything else under `.claude/` is committed. | This is the *reason* the fork is necessary and the reason the rearchitecture is a merge-semantics problem, not a locking problem. §5.2 is built on it. |
| **C3** | **"STA checkpoints" is a paraphrase, not the governance document's own vocabulary.** `grep -rnw 'STA' docs/` returns **nothing**; the abbreviation does exist in `scripts/` (`check-phase-gate.sh`, `upgrade-project.sh`, `reconfigure-project.sh`, around the retroactive-approval path). The real artifact is the **Mid-Phase 2 Governance Checkpoint (Organizational)** — biweekly, 30 minutes maximum, held with the **Senior Technical Authority**, outcomes recorded as rows in the In-Phase Decision Log, explicitly *not* gate-style ("does not approve or block at this cadence"). | The substance of the settled decision is correct; §6.3 imports the real mechanism under its real name. The prose/code vocabulary split is itself worth knowing — the fork inherits both. |
| **C4** | **The delegation substrate this design consumes is itself unbuilt.** `docs/designs/2026-07-24-operating-model-v1.md` is an approved *design*; its five roles, the `operatingModel` manifest block, and the tier tokens do not exist in product code (that document's own §1 records `grep -rn 'operating_model\|operatingModel\|modelTier' scripts init.sh templates` returning nothing). | §7 is explicit that roles 1–5 are **inherited-as-designed, not inherited-as-built**, and §10 sequences accordingly. Overstating this is the single easiest way for this document to fail review. |
| **C5** | **The state-coupled suite count is roughly double the brief's estimate.** The brief cited ~60–80 of 175. Measured 2026-08-02: `grep -l 'phase-state\|process-state\|build-progress\|bypass-audit\|manifest\.json' tests/*.sh` matches **130** of the 182 files that glob covers (175 `test-*.sh` plus 7 non-`test-` suites). Excluding the loosest token (`manifest.json`, 73 hits on its own) still leaves **122**. Per-token: `phase-state` 92, `manifest.json` 73, `process-state` 57, `bypass-audit` 30, `pending-approval` 18, `build-progress` 6. | **This strengthens D1 rather than threatening it** — the in-repo option's cost is larger than the decision was priced at. It is nonetheless a grep upper bound that over-counts (§3.2), which is why the design refuses to convert it into a build estimate. |
| **C6** | **"Seven role slots" in `approval-log-org.tmpl` is a count of gate sections, not of roles.** The template declares no such number. Seven is the count of **signature-bearing gate/completion sections**; the count of distinct **role label strings** across the file is roughly double that, and since the `<!-- BL-170-APPEND-DESIGN -->` redesign the template ships **no pre-filled rows at all** — every table is a header row, and role names live in prose append instructions. | §6.1 maps the real, named role slots and states the section-versus-role distinction rather than inheriting the miscount. |
| **C7** | **The backlog-prefix lint patch is larger than "~10 lines."** The `BL-` literal is embedded in **19 distinct regex literals across 15 executable lines** (6 in `scripts/lint-backlog-references.sh`, 9 in `scripts/lint-bl-markers.sh`), plus 6–10 lines of surrounding single-backlog-file infrastructure. Realistic: **~20–25 lines of lint code plus test updates.** | §3.3 states the measured figure. The decision is unaffected — the design is not prefix-*hostile* architecturally (no data structure is keyed by the string `BL`), it is merely un-parameterized. |

---

## §1 — Problem and evidence

Four problems motivate a team product. Each carries an anchor and an evidence tier, in the
house convention (*verified current state* = re-derived from this tree; *doctrine* = written
policy in a shipped document; *design rationale* = a recorded decision, not a repo fact).

| # | Problem | Evidence (anchor) | Evidence tier |
|---|---|---|---|
| 1 | **Every execution-layer record is a repo-level singleton.** One `phase-state.json`, one `process-state.json`, one `build-progress.json`, one `pending-approval.json`. Two people driving the same project concurrently do not defeat the gates — they collide in git on the *bookkeeping* the gates read. | The measured `.claude/` inventory (§5.1); `scripts/lib/phase2-state.sh::_phase2_state_repo_root` resolves state to the **git repo root**, i.e. one document per repository, with `_record_phase2_step` as the single shared writer. | Verified current state |
| 2 | **The audit ledger has no concept of a named human.** The bypass-audit `actor` vocabulary is a *class* enum, and its value is a **hardcoded literal at each write site** — it records which process wrote the row, not which human acted. In a team, "a human bypassed the gate" is not an adequate record; "which human" is the whole point of an audit trail. | `scripts/lib/bypass-audit.sh` schema docblock and the per-site literals (§5.4); the governance framework's own Approval Verification Control 1 already demands identity ("the git author on the commit serves as the verification record"), which the ledger does not carry. | Verified current state |
| 2b | **A second developer manufactures false audit findings by doing nothing wrong.** `user_terminal_inferred` is derived by set-difference against a **per-clone** ledger (`.claude/claude-commits.jsonl`) and a per-clone baseline. Every commit developer B makes and developer A pulls is absent from A's ledger, so A's next SessionStart labels B's legitimate, gate-passing commits as out-of-band. **This is an audit-*correctness* failure, not a merge conflict** — the strongest single argument that the execution layer must be rearchitected rather than tolerated. | `scripts/hooks/record-claude-commit.sh` (writer), `scripts/detect-out-of-band-commits.sh` (the `is_in_ledger` / `is_derivative` filters), and `docs/audit-log-lifecycle.md`'s own statement that "the detector cannot prove the human at the keyboard". | Verified current state |
| 3 | **The organizational governance layer is written for multiple humans and bound to none.** `docs/governance-framework.md` §V defines approval authority **by role, not individual**, mandates "Named individuals must be assigned before Phase 0 begins", forbids self-approval, and defines an escalation chain. `templates/generated/approval-log-org.tmpl` ships the log those roles sign. The binding from role to person is prose that a human maintains by hand. | `docs/governance-framework.md` § V *Approval Authority* and § V *Approval Verification Controls* 1–4; the org/personal template pair in `templates/generated/`. | Verified current state (doctrine) |
| 4 | **Graduation has no landing zone.** `docs/governance-framework.md` § X *Graduation Criteria* mandates that an application must not remain solo-operated beyond 90 days past a trigger, and § X *Graduation Transition Plan* hands it to a "conventional engineering team" that receives a codebase, budgets 40–80 hours of knowledge transfer, and "produce[s] a remediation plan". Nothing in the framework meets that team on the other side. | `docs/governance-framework.md` § X *Graduation Criteria* (five triggers) and § X *Graduation Transition Plan* (steps 1–6). | Verified current state (doctrine) |

**What does not exist today (verified).** There is no roster, no per-actor state, no
multi-driver mode, and no team product. `grep -rni 'team.orchestrator'` over this tree returns
nothing outside this file. The framework's only concession to a second human is the **Backup
Maintainer** (`docs/governance-framework.md` § X), who is defined explicitly as someone who
"does not need to actively develop".

---

## §2 — Product boundary

**Team Orchestrator is:** the same methodology, the same gates, the same scanners, and the same
enforcement tiers, with an execution layer that knows there are 2–10 named people and a
governance layer bound to them.

**Team Orchestrator is not:**

- **Not a project-management tool.** It does not schedule, estimate, assign, or track velocity.
  It records decisions and approvals, which is a different thing (§7.4).
- **Not a scaling story past 10.** Beyond roughly ten developers the coordination problem stops
  being a bookkeeping problem and becomes an organizational one; the design does not pretend
  otherwise (§12).
- **Not a replacement for Solo Orchestrator.** Solo stays the right product for one person. The
  two are siblings with a deliberately decaying shared channel (§4), not a version pair.
- **Not a multi-tenant service.** Each team's project is a repository, exactly as today.

**Sizing rationale for 2–10.** The lower bound is 2 because at 1 the correct product already
exists. The upper bound is 10 because that is where the design's **serialized-driving default**
(§5.5) stops being economical and where `docs/governance-framework.md` § X *Portfolio Scaling*'s
own observation applies — coordination cost compounds faster than headcount.

---

## §3 — The fork (D1)

### §3.1 — Why a fork, restated with the repository's own numbers

The decision is settled; what follows is the evidence a reviewing architect will want, measured
on this tree on 2026-08-02.

| Option | What the team product would own on day one | Cost of the state rewrite | Verdict |
|---|---|---|---|
| **In-repo variance** (one repo, a `team` mode flag) | Everything, shared | Every state-file rewrite must stay bimodal forever: two shapes per file, two readers per gate, two fixtures per suite, on a suite corpus of ~175 files. Every future solo change pays the team tax and vice versa. | **Rejected (settled)** |
| **A thin kit** (a small team-only layer that consumes solo as a dependency) | A coordination layer and nothing else | Cheap to build, but the kit owns none of the gates, none of the scanners, and none of the CI. A capability desert: the team product would have to re-earn everything that makes the solo product credible. | **Rejected (settled)** |
| **Fork-and-modify, separate repo, shared history** | The **entire** asset base | One rewrite, one shape, one set of fixtures. Divergence is paid once, deliberately, and the merge channel (§4) recovers upstream improvements for as long as that is cheap. | **ADOPTED (settled)** |

**The asset base the fork inherits, measured 2026-08-02** (`du -sh`, `wc -c`, `ls | wc -l` on
this tree — these drift; re-measure before quoting):

| Asset | Measure |
|---|---|
| `scripts/` (gate scripts, lints, session hooks, libs) — 70 files | **1.6 MB** (1,560,645 bytes of file content) |
| ├─ `scripts/lib/` | **18** shared modules, 384 KB |
| ├─ `scripts/lint-*.sh` | **14** lint scripts; `run-lints.sh` runs **13 of 14** (it excludes `lint-uat-scenarios.sh`, a parametrized tool that exits 2 bare-invoked, not a repo lint) |
| └─ `scripts/hooks/` | `bypass-detector.sh`, `record-claude-commit.sh` |
| `init.sh` (the scaffolder) | **223,031 bytes** |
| `tests/` | **175** `test-*.sh` suites + **22** further `.sh` (aggregators, edge-case suites, `host-drivers/`) = **197** files, **3.9 MB** |
| `templates/` | **27** `.tmpl` files (97 files total incl. `skills/`), 644 KB |
| `evaluation-prompts/` (the adversarial persona library) | 39 files, 680 KB |
| CI | `.github/workflows/lint.yml` — **11** lint jobs; `.github/workflows/tests.yml` — **3** jobs: a sharded `unit-shard` matrix (`lint-sweep, lint-scan, sast, slow-misc, rest`), a zero-work `unit` aggregator that is the required status check, and a `workflow_dispatch`-only `full` job at `timeout-minutes: 180` |
| Git history | 1,242 commits |

> **Drift note for the reviewer, offered as evidence for the method rather than the numbers.**
> `CLAUDE.md` records "10 jobs as of 2026-07-31" for `lint.yml` (there are **11**) and "13 lint
> scripts … 12 of the 13" in the sweep (there are **14**, and the sweep runs **13**). Both are
> stale by one, both in the same direction, and both were found by re-measuring rather than by
> reading. The repo's own orientation document instructs exactly this — *prefer the grep
> recipes; counts drift* — and the fork inherits that discipline along with the code. **Every
> number in this table is dated 2026-08-02 and should be re-measured, not quoted.**

### §3.2 — The blast radius the fork buys out of

The settled decision cites a state rewrite reaching a large fraction of the suite. **This is
the claim in this document most likely to be attacked, so it is given as a method with a
measured upper bound — never as a build estimate.** Measured on this tree, 2026-08-02, over the
182 files the `tests/*.sh` glob covers (175 `test-*.sh` plus 7 aggregator/edge-case suites):

| Token | Suites matching |
|---|---|
| `phase-state` | 92 |
| `manifest.json` | 73 |
| `process-state` | 57 |
| `bypass-audit` | 30 |
| `pending-approval` | 18 |
| `build-progress` | 6 |
| **union of the five in the standard recipe** | **130** |
| union **excluding** `manifest.json` (the loosest token) | 122 |
| any mention of `.claude/` at all | 138 |

**This over-counts, deliberately and in a known direction.** `grep -l` matches any mention —
a comment, a docstring, a fixture directory named `.claude` — and does not distinguish "asserts
on this file's schema" from "happens to say the word". `manifest.json` is the worst offender: it
is the generic project manifest, named by init/upgrade/tier suites with no phase- or
process-state coupling at all.

**A grep-measured audit of a comparable surface has under-read it twice in this repo's own
history.** `CLAUDE.md` § HOUSE RULES records that a 2026-07-26 grep audit of the unit-lane
exemption rows moved five files, and that a second pass tracing **execution** found a sixth the
grep had missed — which is why the standing house rule is now "audit by EXECUTION, not by grep."
**The real figure is therefore a WP0 deliverable (§10), produced by running the suites against a
changed-shape shim.**

**What the measurement does settle (C5).** The brief priced this at ~60–80 of 175; the grep bound
is **130 of 182**, and still 122 after removing the loosest token. Whatever the execution-measured
number proves to be, it is bounded below by the 30 suites naming `bypass-audit` and the 18 naming
`pending-approval` — both surfaces this design definitely rewrites. **The settled decision is
reinforced, not threatened: the in-repo option was priced too cheaply, not too dearly.**

### §3.3 — Day-one fork protocol (D3)

Four ordered obligations. The first three are **before the first commit**, because each is a
control that is far more expensive to retrofit than to establish.

| # | Obligation | Why before the first commit | Anchor in current practice |
|---|---|---|---|
| **1** | **Recreate branch protection on the fork's `main`.** Required status checks re-declared by name, including the aggregator job whose name is the required check. | A fork does not inherit branch protection. A repo that takes commits before protection exists has an unprotected window, and the house rule is absolute: **no merge on red, ever; no `gh pr merge --admin`.** | `CLAUDE.md` § CANONICAL COMMANDS records that the `unit` job survives as a zero-work aggregator **because it is the required status check** — renaming or deleting it leaves every PR waiting on a check that never reports. The fork must reproduce that arrangement deliberately. |
| **2** | **Install the pre-commit gate hook in the fork clone.** `cp scripts/pre-commit-gate.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit`. | Hooks live in `.git/`, which is **not** cloned. A fork begins with zero commit-time enforcement. | `CONTRIBUTING.md`'s contributor-hook instructions; `scripts/install-contributor-hooks.sh`. Note the trap: `pre-commit-gate.sh --tdd-only` runs **two** message gates (the BL-072 TDD ordering gate *and* the BL-006 Build-Loop check) — the flag name is kept for hook backward-compat. |
| **3** | **Declare the fork's identifier namespace before anything cites it.** New entries use the `TL-` prefix (`TL-001`, marker comments `# TL-001-…`); the inherited `BL-` corpus is frozen. | The repo mints identifier namespaces and registers them in one place; inventing a prefix after the fact strands citations. | `templates/generated/identifiers.tmpl` (`# BL-089`) is the shipped registry pattern: "If your prefix isn't here, add it in the same commit that first uses it." `TM-`, `ADR-`, `BUG-`, `UAT-`, `SEV-` are taken; `TL-` is free (verified). |
| **4** | **Disposition every red suite individually.** Each failing suite is either **fixed** or **retired with a recorded reason and a citing entry**. Bulk deletion is forbidden. | A deleted suite is indistinguishable from a suite that never existed; a retired-with-reason suite is a durable record of a deliberate scope decision. | The repo's own aggregator-registration invariant (`scripts/lint-tests-registered.sh`) exists precisely because silently-unrun tests are the framework's recurring defect class. Retirement must therefore also **deregister** from `tests/full-project-test-suite.sh` and the `tests.yml` unit list in the same commit, or the lint goes red. |

**The frozen-backlog decision.** The inherited `solo-orchestrator-backlog.md` is kept **verbatim
and frozen** — renamed to a fork-local `inherited-backlog.md`, never edited — because its Closed
entries are the audit substrate that explains why the inherited code looks the way it does. New
work goes in a fresh `team-orchestrator-backlog.md` under `TL-`.

**The lint patch this requires — measured, because the brief's "~10 lines" is optimistic (C7).**
Two lints hardcode the prefix: `scripts/lint-backlog-references.sh` (Closed/Resolved entries must
cite a PR # or a backticked SHA; the prefix knowledge lives in `is_valid_id` / `normalize_id`'s
feeder regexes) and `scripts/lint-bl-markers.sh` (bidirectional marker↔entry resolution plus a
vacuity floor, under the `# BL-196-ALLOWLIST-BEGIN`, `# BL-196-EMPTY-SET-GUARD`, and
`# BL-196-PROSE-CITE-BEGIN` fences, plus a three-layer self-exclusion arm). The literal `BL-`
appears in
**19 distinct regex literals across 15 executable lines** — 6 and 9 respectively — with two lines
carrying the prefix twice (the valid-ID builder's grep+sed pair, and the prose-cite alternation
that handles the backticked and hash-prefixed spellings). The ID grammar is `BL-[0-9]+[a-z]?`
throughout; the marker grammar is that plus a `-[A-Za-z][A-Za-z0-9_-]*` suffix.

**Design shape:** replace each literal with a **prefix alternation from one constant**, so a
third prefix is a one-line change rather than a third edit pass. **Three honest caveats:**

1. **A width-coupled offset.** `scripts/lint-backlog-references.sh`'s `# BL-207-HEADER-UNIQUENESS`
   arm slices the id with `substr($0, RSTART + 3, RLENGTH - 4)`. Those offsets encode `"## "` and
   `":"`, not the prefix — so an equal-width prefix like `TL-` survives and an unequal one like
   `TSK-` breaks **silently**. Its own comment records that this offset already masked a mutation
   test once. `TL-` is chosen partly for this reason.
2. **The empty-set guard inverts.** `# BL-196-EMPTY-SET-GUARD` treats an empty entry set as never
   legitimate. On a fresh fork with no `TL-` entries yet, an empty `TL-` set **is** legitimate —
   so a naive per-prefix generalization turns a vacuity floor into a false failure. This must be
   per-prefix with a "not yet used" state.
3. **Path plumbing.** Both lints assume a single backlog file (`BACKLOG` is one path, `VALID_IDS`
   one flat array), and `lint-bl-markers.sh` scopes its prose and code surfaces by path lists
   naming solo-specific files. Re-pointing those is not prefix logic but is in the same patch.

**Realistic total: ~20–25 lines of lint code plus updates to `tests/test-lint-backlog-references.sh`
(T15/T16/T17 pin the anchor and the `[a-z]?` grammar) and `tests/test-lint-bl-markers.sh` (which
excises the prose-cite fence as its mutation, and so needs a second or parameterized fence).**
The design is prefix-*un-parameterized*, not prefix-*hostile*: no data structure is keyed by the
string `BL`.

---

## §4 — The merge channel, and its deliberate decay (D2)

The channel is **temporary by design**. Its value is highest when divergence is shallow and
falls monotonically as the state rewrite lands. Designing it as permanent would be the
error — a permanently-merged fork is an in-repo variance with extra steps, which §3.1 already
rejected.

### §4.1 — The three phases

| Phase | When | Mechanism | Scope | What makes it end |
|---|---|---|---|---|
| **P1 — Full merge** | Fork day → the state rewrite lands | Weekly `git merge upstream/main`, whole tree, conflicts resolved by hand | Everything | The first WP that rewrites a state file's shape. From that commit, whole-tree merges start producing conflicts in files whose *contract* differs, not just whose *text* differs. |
| **P2 — Lib-only merge** | State rewrite landed → ~2 quarters post-fork | Path-scoped merge: `scripts/lib/`, `scripts/lint-*.sh`, `scripts/hooks/`, `templates/` | Shared toolbox only. Never `init.sh`, never the gate scripts, never `tests/` | Divergence in the shared paths themselves — when a lib module's *callers* differ enough that an upstream change to it is no longer safe to take unread. |
| **P3 — Assessed propagation** | ~2 quarters post-fork onward | The family **Change Assessor** (§4.3) | Per-change, by decision | Terminal state. |

### §4.2 — Why lib-only, and why those four paths

The P2 scope is not arbitrary. Those four paths are the ones whose contract is **inward-facing**
— they are consumed by callers, and the fork keeps its own callers:

- `scripts/lib/` — 18 modules, 384 KB, and the repo's own designated "single audit-grep surface
  for future drift" (the rationale header of `scripts/lib/phase2-state.sh` states exactly that
  motive for lifting a helper into a lib).
- `scripts/lint-*.sh` — repo-hygiene tools, largely orthogonal to the state layer. The two
  exceptions are named in §3.3 and are precisely the two the fork patches.
- `scripts/hooks/` — `bypass-detector.sh` and `record-claude-commit.sh`. **Honest exception:**
  both are ledger writers, so both are touched by the actor rearchitecture (§5.4). They are in
  the P2 scope because their *upstream* changes are usually detection improvements worth taking,
  not because they are unmodified.
- `templates/` — 27 `.tmpl` documents. Mostly prose the two products want to keep in sync.

`init.sh`, `scripts/check-phase-gate.sh`, `scripts/pre-commit-gate.sh`,
`scripts/process-checklist.sh`, and `tests/` are **out of P2 scope permanently** — they are the
files the rearchitecture rewrites, and merging them blind is how a fork silently un-does its own
design.

### §4.3 — The Change Assessor: a dependency contract, not a design

The Change Assessor is a **separate coordination-repo agent** and is **out of scope for this
document**. It is named here as a dependency, with the minimum contract this design relies on:

- **Input:** a landed change in any family repo (Solo, Team, and any future sibling), identified
  by PR and commit.
- **Output:** a per-sibling verdict — *propagate as-is* / *propagate with adaptation* /
  *do not propagate* / *inverse* (the sibling should do the opposite) — each with a written
  reason, filed as a citing entry in the receiving repo's backlog.
- **Non-guarantee:** it does not apply changes. It assesses and files. Application goes through
  the receiving repo's normal build loop and its normal gates.

**What this design depends on:** only that P3 has *some* recorded, per-change decision surface.
If the Change Assessor is late, P2 extends — that is a schedule risk, not a design risk. If it
is never built, P3 degrades to "someone reads both changelogs quarterly", which is worse but not
fatal. **This is stated so the reviewer can attack the schedule without attacking the
architecture.**

### §4.4 — The decay schedule's assumptions, stated

Three, all falsifiable, all listed again in §12: (i) the state rewrite lands inside one quarter;
(ii) upstream Solo continues active development through the window, so the channel has something
to carry; (iii) shared-path divergence stays low enough that a path-scoped merge is reviewable
by one person in under an hour a week. If (iii) fails first, P2 collapses into P3 early — which
is a **success case for the design**, not a failure, because the channel was always meant to end.

---

## §5 — Execution-layer rearchitecture

This is the core of the fork. It is a **bookkeeping** rearchitecture: the gates' predicates do
not change, the files they read do.

### §5.1 — The measured singleton inventory

Derived 2026-08-02 by `grep -rhoE '\.claude/[a-zA-Z0-9._-]+' init.sh scripts/ templates/ | sort -u`.
Nineteen files and five directories. The **contention class** column is the design's own
classification, not a repo fact.

| `.claude/` artifact | What it holds · writer | Tracked? | Contention class |
|---|---|---|---|
| `phase-state.json` | Phase + per-gate approvals; written by `create_project()`, gate dates by `_cpg_record_gate_date` | tracked | **Project-global** — one truth by definition |
| `manifest.json` | `deployment`, `poc_mode`, `enforcement_level`, `currency`, `soloFrameworkCommit` (`# BL-110-PIN-UNIVERSAL`), and — per the operating-model design — `operatingModel`; seeded by `prepare_initial_state_for_commit()`, stamped by `soif_currency_stamp()` | tracked | **Project-global** — policy. Its `currency.files{}` hash inventory re-diffs on any scaffolded-file edit (intentional drift detection) |
| `process-state.json` | `build_loop{feature,step,…}`, `uat_session{session_id,…}`, `phase3_validation`, `phase4_release`, `phase2_init{…}`; shared writer `_record_phase2_step` (`scripts/lib/phase2-state.sh`) | tracked | **Per-workstream — the worst singleton.** `build_loop.feature` and `.step` are *singular*: two developers in the Build Loop cannot both be represented, and last-writer-wins silently discards the other's position |
| `build-progress.json` | `features_completed[]`, test-interval counters, `testing_required` | tracked | **Per-workstream** |
| `intake-progress.json` | Resumable wizard doc (`last_section`, `completed_sections[]`, `answers{}`); `# BL-204-VISIBILITY-PERSIST` | tracked | Project-global (one intake); two concurrent wizard runs interleave badly |
| `bypass-audit.json` | The enforcement ledger — a **pretty-printed JSON array** of rows; `bypass_audit_append` in `scripts/lib/bypass-audit.sh` | tracked (deliberately) | **Append-only ledger stored in the worst shape for merging** (§5.4) |
| `claude-commits.jsonl` | `{sha,timestamp,session_id,gate}` per agent commit; `scripts/hooks/record-claude-commit.sh` | tracked | **Append-only ledger** — and the *input* to actor inference (§5.4) |
| `tdd-warn-ledger.jsonl` | TDD-ordering warnings; `scripts/pre-commit-gate.sh` | tracked | **Append-only ledger** |
| `tool-usage.json` | `session_id`, `calls[]`, MCP counters; rewritten by `scripts/track-tool-usage.sh` on every PostToolUse | tracked | **Per-actor, and the highest-frequency collision** — it carries one session's truth and is rewritten every few seconds |
| `tool-preferences.json` | `context{dev_os,platform,language,track}`, substitutions, installed sets; `write_tool_preferences()` | tracked | Project-global |
| `orchestrator-source.json` | `{source_dir}` — **an absolute path to one machine's framework checkout** | tracked | Project-global in intent, **per-machine in fact** — guaranteed to differ per developer |
| `pending-approval.json` | The approval sentinel; `sentinel_path()` in `scripts/pending-approval.sh` | tracked | **Repo-level singleton with no owner — the concurrency crux (§5.5)** |
| `license-policy.json` | License allow/deny; read by `scripts/run-phase3-validation.sh` | operator-owned | Project-global |
| `dast-headers.json` | Declared response headers for the hardened DAST serve (`# BL-165-HARDENED-SERVE`) | operator-owned | Project-global |
| `test-command` | The project's test invocation; read by `scripts/lib/hook-templates.sh`, never framework-written | operator-owned | Project-global |
| `settings.json` | Harness hook registrations (SessionStart / Stop / PreToolUse / PostToolUse) + permissions | tracked | Project-global |
| `settings.local.json` | Qdrant MCP registration, written only when jq + Qdrant are present | **tracked** (**see note**) | **Per-actor** |
| `last-checked-commit.txt` | Out-of-band detector baseline | **ignored** (`# BL-174` sibling pair) | Per-clone by construction |
| `last-gate-pass.txt` | Gate-ran receipt (`# BL-161-NO-ROUTINE-PASS`) | **ignored** (`# BL-174` sibling pair) | Per-clone by construction |
| `process-audit.log` | Process-checklist audit trail | ignored **incidentally** by the template's `*.log` pattern (no `.claude`-specific line, no negation) | Per-clone |
| `cache/` | Freshness snooze store (`scripts/lib/freshness-detect.sh`) | **ignored** — appended by `generate_gitignore()`, not by the template | Per-clone |
| `framework/`, `skills/`, `upgrade-snapshots/`, `worktrees/` | Vendored CDF, shipped skills, upgrade snapshots, worktrees | mixed | Out of scope for the rewrite |

**The load-bearing fact (C2).** `templates/generated/gitignore-base.tmpl` carries exactly **two**
`.claude/*` ignore lines — both under its `SYNC SIBLINGS (BL-174)` comment — and
`generate_gitignore()` appends a third for `.claude/cache/`. **Everything else in the table is
committed**, so every singleton is a merge surface. Three entries deserve separate flags:

- **`settings.local.json` is tracked despite its name.** `docs/cli-setup-addendum.md` describes
  it as "project-level, personal, gitignored"; nothing ignores it. Worse, whether it exists at
  all depends on each developer's local Qdrant state, so it flip-flops in and out of the tree.
  **A documentation-versus-behaviour mismatch the fork should fix, not inherit.**
- **`orchestrator-source.json` commits one machine's absolute filesystem path.** Harmless with
  one developer; a permanent diff with several.
- **`tool-usage.json` already carries a `session_id`** — the file's own schema knows it is
  per-session state. It is simply stored where only one session can win.

### §5.2 — Disposition: three keying strategies

| Strategy | Applied to | Mechanism | Conflict behaviour |
|---|---|---|---|
| **Stay global** | `phase-state.json`, `manifest.json`, `tool-preferences.json`, `orchestrator-source.json`, `license-policy.json`, `dast-headers.json`, `test-command`, `settings.json`, `intake-progress.json` | Unchanged shape, unchanged path | Genuine conflicts. Correct: two people disagreeing about the project's phase or enforcement level **is** a conflict and should stop at review. |
| **Branch-keyed** (per workstream) | `process-state.json`, `build-progress.json` | Move to `.claude/workstreams/<slug>/`, where `<slug>` derives from the branch name; readers resolve the current workstream from `git rev-parse --abbrev-ref HEAD` with a configured fallback | Conflict-free by construction — two branches never write the same path. Merging a workstream to `main` merges its directory. |
| **Actor-keyed** | `tool-usage.json`, `settings.local.json` | Move to `.claude/actors/<actorId>/`, `<actorId>` resolved from the roster (§5.3) | Conflict-free by construction |
| **Ledger, append-only** | `bypass-audit.json`, `claude-commits.jsonl`, `tdd-warn-ledger.jsonl` | See §5.4 | Union-merged |

**Why phase is global and build-loops are not.** The phase gates are *project* assertions —
`scripts/check-phase-gate.sh` answers "may this project advance", a question with one answer.
The Build Loop is a *change* assertion — `scripts/process-checklist.sh` classifies whether a
given change is commit-ready — and in a team there are several changes in flight. Keying build
state to the branch is therefore not a workaround; it is the honest shape of the thing.

**Rejected alternative — key everything by actor.** Simplest to implement and wrong: it would
let two people hold contradictory beliefs about the project's phase with no conflict to surface
the disagreement. The gates' value comes from having exactly one answer where one answer is
correct.

**Rejected alternative — a lock server / external state store.** Rejected on the framework's
strongest invariant: state lives **in the repository**, so a successor or an auditor can
reconstruct it from a clone alone. `docs/governance-framework.md` § X *Shadow IT Risk* item 5
names the in-repo audit as the thing that makes the enforcement guarantee real ("you can route
around the block, you cannot route around the audit"). An external store breaks that.

### §5.3 — The identity model: a committed roster

A new tracked file, `.claude/roster.json`, is the fork's single new project-global artifact:

```json
{
  "schemaVersion": 1,
  "members": [
    {
      "actorId": "a.rivera",
      "displayName": "Ana Rivera",
      "gitIdentities": ["ana.rivera@example.com"],
      "roles": ["orchestrator", "senior_technical_authority"],
      "startedAt": "2026-08-05",
      "endedAt": null
    }
  ]
}
```

- **`actorId`** — the stable key every per-actor path and every ledger row uses. Stable across
  email changes; that is the whole reason it is not the email.
- **`gitIdentities`** — a list, because contractors and re-orgs produce second addresses. This
  is the join key: `git config user.email` → roster member → `actorId`.
- **`roles`** — role slots from the governance layer (§6). A member may hold several; a role may
  be held by several. **Not** an ACL — it is the binding the gates read to answer "was this
  approval authored by someone holding the approving role, and were they a different person from
  the author of the work".
- **`endedAt`** — non-null retires a member without deleting them, so historical ledger rows
  keep resolving. Deletion is forbidden for the same reason Closed backlog entries are kept.

**Roster resolution failure is tiered, not fatal.** An unmatched git identity is handled by the
existing `enforcement_level` ladder (`no` / `light` / `strict`), reusing
`scripts/lib/enforcement-level.sh` rather than inventing a second severity vocabulary: silent at
`no`, a warning at `light`, **blocking at `strict`**. This matters because the tier predicate is
implemented across multiple scripts that must change in sync — `pre-commit-gate.sh`,
`check-phase-gate.sh`, `init.sh`, and `scripts/lib/enforcement-level.sh`, all carrying the
`# BL-084-TIER-KEY` marker whose comment literally reads "SYNC SIBLINGS". The fork's roster arm
joins that sibling set and inherits its sync obligation.

**Roster lifecycle.** Written at init (a team intake question), edited by a
`reconfigure-project.sh --roster-*` surface, and **every mutation writes a ledger row**, exactly
as `enforcement_level` changes do today.

### §5.4 — Attestations gain an actor, without breaking the enum

The bypass-audit ledger's `actor` field is a **class** enum, declared verbatim in the schema
docblock of `scripts/lib/bypass-audit.sh` as
`"claude" | "user_terminal" | "user_terminal_inferred" | "framework"`.

**How `actor` is actually determined — and it is not what the name suggests.** There is no
runtime probe of any kind: no tty check, no `$SSH_TTY`, no env heuristic. **The value is a
hardcoded literal at each of the eight-or-so write sites** — `bypass-detector.sh` always writes
`claude`, `record_audit_row` in `scripts/lib/hook-templates.sh` always writes `user_terminal`,
`escalate-to-user.sh` and `_soif_fresh_audit_snooze` always write `framework`, and so on. The
field records **which process wrote the row**, not which human acted.

**The one real inference is `user_terminal_inferred`, and it is a negative ledger, not a probe.**
`scripts/hooks/record-claude-commit.sh` appends every SHA the agent commits to
`.claude/claude-commits.jsonl`; `scripts/detect-out-of-band-commits.sh` then walks
`$BASELINE..HEAD` and labels anything absent from that ledger (and not a merge/revert/squash
derivative) as `user_terminal_inferred`. `docs/audit-log-lifecycle.md` states the semantics
honestly: *"the detector cannot prove the human at the keyboard; the SHA was just not in any
other ledger."*

> **This breaks on contact with a second developer, and it breaks quietly.** Both the ledger and
> the baseline (`.claude/last-checked-commit.txt`) are **per-clone**. Every commit developer B
> makes and developer A pulls is absent from A's ledger, so at A's next SessionStart the
> detector labels **B's legitimate, gate-passing commits** as `user_terminal_inferred` in A's
> audit log. Two developers therefore manufacture false out-of-band findings for each other by
> doing nothing wrong. **This is not a merge conflict — it is an audit-correctness failure, and
> it is the strongest single piece of evidence that the execution layer must be rearchitected
> rather than tolerated.** The fix falls directly out of the roster: the detector must consult
> the *union* of the team's commit ledgers, or resolve the commit's author against the roster
> before inferring anything.

Named humans must therefore appear in the ledger. There are two ways to do that, and the choice
is not cosmetic.

| Option | Shape | Effect on existing consumers | Verdict |
|---|---|---|---|
| **Grow the `actor` enum** with roster ids (`a.rivera`, …) | One field, unbounded domain | Breaks every enum-pinning consumer. Two pins exist and both are exact-membership `case` statements in `tests/test-bl029-integration.sh` — **T5** (`# T5: actor enum invariant`) over the four actor values and **T6** over the type enum. The operating-model design's F8 already showed that adding a single new *row type* was out-of-schema on **three** surfaces at once. An unbounded actor domain makes any such whitelist unwritable. | **Rejected** |
| **Keep `actor` as the class enum; add orthogonal fields** — `actorId` (roster key or `null`) and `actorIdSource` (`roster` / `unmatched` / `inferred`) | Two new fields, both additive | Every existing reader, jq recipe, and enum pin keeps working unchanged. A team-aware reader gets identity. An old row (no `actorId`) is legibly "pre-roster", not corrupt. | **RECOMMENDED** |

**`actorIdSource` is the honesty field.** It refuses to launder an inference as a fact: an actor
resolved from a matched git identity is `roster`; one derived from the negative-ledger inference
above is `inferred`; a real human the roster does not know is `unmatched` — which is a finding,
not a blank.

**The fork must also repair three inherited defects in this surface, because the rearchitecture
touches all of them anyway.** Naming them here is the difference between forking an asset and
forking a liability:

1. **The enum has no runtime validation.** `bypass_audit_append` validates only
   `jq -e 'type == "object"'` — it will happily write `actor: "banana"`. The team product's
   roster join is exactly the point at which a real membership check becomes cheap.
2. **The type enum is already out of sync, in two directions.** `sast_suppression` (`BL-185`) is
   documented but **absent** from T6's seven-value whitelist, and `freshness_enforcement_snooze`
   — written by `_soif_fresh_audit_snooze` in `scripts/lib/freshness-detect.sh` — is a **ninth**
   type that self-declares as an undocumented deviation and appears in neither the docblock nor
   T6. Both pins pass today only because they run over fixture ledgers that never contain those
   types. **A test that cannot fail is not a pin**, and the fork should not inherit two of them.
3. **Five writers bypass the locking library entirely.** `append_audit_row` in
   `scripts/detect-out-of-band-commits.sh`, `record_audit_row` in
   `scripts/install-filesystem-gates.sh`, and sites in `reconfigure-project.sh`,
   `upgrade-project.sh`, and `init.sh` each roll their own `mktemp` + `jq '. + [$r]'` + `mv`
   **without taking the lock** that `bypass_audit_append` uses (a portable `mkdir "$file.lockdir"`
   advisory lock — chosen because flock is absent on macOS by default) and, in at least one case,
   with a `$TMPDIR` mktemp whose `mv` is a cross-filesystem copy, not an atomic rename. A racing
   detector run and hook can therefore lose rows **on one machine today**. With several
   developers, the exposure multiplies.

**Ledger merge semantics.** The three ledgers are append-only, so union merge is exactly the
right primitive — but it only works line-wise:

| Ledger | Today | Change |
|---|---|---|
| `claude-commits.jsonl` | one JSON object per line | none needed |
| `tdd-warn-ledger.jsonl` | one JSON object per line | none needed |
| `bypass-audit.json` | a JSON **array** — two concurrent appends conflict on the closing bracket, and a text merge of an array is a syntax error waiting to happen | **Convert to `bypass-audit.jsonl`**, one row per line, and declare `merge=union` in `.gitattributes` |

**Honest limits of `merge=union`, stated because a reviewer will find them:** union merge (i) can
**duplicate** a row that both sides appended identically, (ii) does not order the result, and
(iii) is a *text* merge with no idea it is merging JSON. Mitigations, all cheap: every row
carries a UUID so duplicates are detectable and idempotent to drop; every row carries an ISO
timestamp so readers sort rather than trust file order; and a lint validates that every line of
every `.jsonl` ledger parses. **Residual:** union merge cannot prevent a *malicious* rewrite of
history — nothing in-repo can. Git history remains the tamper evidence, exactly as
`docs/governance-framework.md` § V already says of `APPROVAL_LOG.md`.

**Converting the ledger is not free** — the same three surfaces the F8 precedent names must move
in one wave: the writers in `scripts/lib/bypass-audit.sh`, the type/shape assertions in the
integration suite, and the taxonomy plus the cold-pickup jq recipes in
`docs/audit-log-lifecycle.md`. That is a work package (§10-WP3), not a footnote.

### §5.5 — Concurrent sessions, and the cheap answer

`pending-approval.json` is a **repo-level singleton with no owner**, and it is the sharpest
concurrency edge in the whole system — not a merge hazard but a **global mutex nobody holds**.
Verified in `scripts/pending-approval.sh` (BL-015):

- **`sentinel_path()` is the whole scoping story:** it returns `"$1/.claude/pending-approval.json"`
  where `$1` comes from `find_project_root()`, which walks upward to the first directory
  containing a `.claude/`. **One sentinel per project root.** No branch scoping, no session
  scoping, no worktree scoping, no user scoping.
- **The payload has no owner field.** The documented schema is `question`, `options`,
  `recommendation`, `offered_at` — no `session_id`, no `actor`, no `owner`. There is no way to
  learn *whose* question is pending.
- **`cmd_offer` hard-refuses a second question**, printing that one already exists. Developer B
  literally cannot escalate while developer A's question is open.
- **`cmd_clear` and `cmd_resolve` are unauthenticated.** Anyone can clear anyone's sentinel, and
  nothing records whose it was. Its paired ledger call `bypass_audit_close_pending` closes **all**
  PENDING `claude_bypass_proposal` rows regardless of origin.
- **Existence alone blocks, validity irrelevant.** `pa_check` in `scripts/pre-commit-gate.sh`
  denies `git commit` and `gh pr create` on presence; `_bl015_sentinel_guard` in
  `scripts/upgrade-project.sh` exits 1 at both of its call sites. Malformed files are not
  auto-cleaned. **So one developer's stray sentinel blocks every other developer's commits.**
- **Two independent TOCTOU races on one path.** `scripts/hooks/bypass-detector.sh` writes the
  sentinel *directly* with `jq > "$SENTINEL"` under a bare `[ ! -f "$SENTINEL" ]` guard,
  bypassing `cmd_offer`'s own existence check.
- **A path-resolution disagreement already exists.** `pa_check` uses a **relative**
  `.claude/pending-approval.json` while `pending-approval.sh` and `upgrade-project.sh` resolve an
  absolute project root — so a git worktree or a subdirectory invocation can disagree about which
  sentinel is in force. **This is a latent solo bug that becomes routine on a team**, since
  worktrees are how parallel work is done.

Two people can therefore be waiting on each other's question with only one slot to hold it, and
neither can tell whose slot it is.

**Two operating modes. The design ships the cheap one first, on purpose.**

| Mode | Rule | Singleton impact | Cost |
|---|---|---|---|
| **Serialized driving (DEFAULT, v1)** | Exactly one member holds **the wheel** at a time — a short lease in `.claude/wheel.json` naming the holding `actorId` and an expiry. Non-holders work freely on their own branches (edit, test, commit, open PRs) but do not advance project-global state or raise approvals. | **Zero.** Every singleton stays a singleton and stays correct, because there is only ever one writer of global state. | Real, and it must not be minimised: at the top of the range — a 10-person team — the wheel is a genuine throughput ceiling on *gate-advancing* work. It is not a ceiling on ordinary development, which is branch-local and unaffected. |
| **Concurrent driving (v2, opt-in)** | The sentinel shards: `.claude/pending-approval/<actorId>.json`; readers glob the directory; a gate blocks on the asking actor's sentinel only. The payload gains an owner field; `cmd_clear` refuses to clear another actor's sentinel without an attested override; `pa_check`'s relative path is unified with `find_project_root()`. Branch-keyed state (§5.2) already supports parallel build loops. | The sentinel and the build loops parallelise. Project-global state (phase, manifest) still does not, and should not. | A real design surface: two people raising two approvals against one phase gate needs an ordering rule, which is deferred (§12). |

**Why serialized-first is the right call and not timidity.** It converts the entire singleton
problem into a **lease** problem, which is one small new file with one clear owner, and it lets
the fork's first release be *correct* rather than *ambitious*. The delta between the two modes is
honestly small for a 2–4 person team and grows with headcount — which is precisely why the mode
is a config flag on the roster, not a fork of the product.

**What the lease is not.** It is not a lock: it has an expiry, it is advisory at
`enforcement_level: no`, and a stale lease is breakable with a ledger row recording who broke it
and why. A hard lock in a distributed version-control system is a fiction; an attested lease is
not.

---

## §6 — Governance: imported, not invented

The single highest-leverage fact in this design: **the organizational governance track is
already multi-human.** It defines roles, forbids self-approval, mandates named individuals, and
ships the log they sign. What it does not have is a **binding** from role to person that a
machine can read. The roster (§5.3) is that binding, and it is the *only* new thing §6 adds.

### §6.1 — The role mapping

`templates/generated/approval-log-org.tmpl` carries the organizational role slots;
`docs/governance-framework.md` § V *Approval Authority* defines what each approves and at which
gate. Team Orchestrator binds each slot to one or more roster `roles` values.

**First, C6's correction, because the mapping depends on it.** The org template declares no
count of role slots. **Seven** is the number of *signature-bearing gate and completion sections*
— Pre-Phase 0, the three phase gates 0→1 / 1→2 / 2→3, the two `###` subsections of Phase 3→4,
and Phase 4 Completion — plus three further conditional slots (Attorney/Legal Review, Penetration
Test, UAT Sign-off) and a running Approval History ledger. The number of distinct **role label
strings** is roughly double. Moreover, since the `<!-- BL-170-APPEND-DESIGN -->` redesign the
template ships **no pre-filled rows at all**: every table is a header row and the role names live
in prose append instructions, appended-to under an append-only contract enforced by a CI job.

The **Pre-Phase 0** section alone names six roles the § V gate table does not:
`IT Security`, `Insurance Broker`, `Legal / CIO`, `Executive Sponsor`, `Technical Lead`,
`ITSM / PMO` — and `scripts/check-phase-gate.sh::check_named_row` requires a dated row for each
of the six, by name, within a 30-line window of the `## Pre-Phase 0` header.

| Governance role slot (org track) | Gate it holds (§ V *Approval Authority*) | Team-product roster role | Binding rule |
|---|---|---|---|
| **IT Security** | Pre-Phase 0 — AI deployment path; co-signs Phase 3→4 | `it_security` | May be external to the team; roster entry with no `gitIdentities` is permitted and marks the approval as out-of-band-evidenced |
| **Project Sponsor** | Phase 0→1 — business justification, resource allocation, compliance screening | `project_sponsor` | Typically non-technical; out-of-band evidence expected |
| **Senior Technical Authority** | Phase 1→2 — architecture, security posture, data classification; Phase 2→3 for organizational deployments; runs the Mid-Phase 2 checkpoint and the quarterly portfolio review | `senior_technical_authority` | **Must be a roster member with a git identity** — this is the role the self-approval check compares against |
| **Application Owner** | Phase 3→4 — go-live readiness, risk acceptance (co-signed with IT Security) | `application_owner` | Business owner; may be external |
| **Orchestrator** | Phase 2→3 for personal deployments; the builder at every phase | `orchestrator` | **In a team, this slot is held by several people.** The one-to-many change is the crux of §6.2 |
| **Backup Maintainer** | Not a gate role — mandatory per § X, monthly sync, handoff test, quarterly access verification | `backup_maintainer` | In a team of ≥2 developers this role is **naturally satisfied** rather than specially appointed (§6.4) |
| **CIO (or designated authority)** | Terminal escalation; the only source of a written exception to the graduation deadline | `cio` | Roster entry for evidence attribution; rarely a git identity |

**The table above is the gate-bearing set, not the whole set.** Pre-Phase 0 names five further
roles the § V gate table never mentions — `insurance_broker`, `legal`, `executive_sponsor`,
`technical_lead`, `itsm_pmo` — each of which `check_named_row` requires a dated row for. They are
roster roles too; they simply hold a pre-condition rather than a gate. **Seven is the count of
gate-bearing roles, not of governance roles**, and a reviewer who counts the template's role
strings will get a larger number (C6).

**Which template is rendered is decided by `$DEPLOYMENT` alone.** `init.sh::generate_approval_log`
is a two-arm branch: `organizational` → `approval-log-org.tmpl`, everything else →
`approval-log-personal.tmpl`. It is **not** keyed by `TRACK` — the personal template's own
BL-105/BL-115 comment says so ("template chosen by deployment, gates keyed by track"), which is
why the personal variant had to grow Attorney and Pen-Test slots it does not conceptually need.
**Team Orchestrator inherits this seam and should close it**, since a team is a deployment shape,
not a track.

> **A second seam the fork must handle (and a reviewer will find).** The approval log is **not
> single-sourced.** `init.sh` renders the empty append-only template, while
> `scripts/upgrade-project.sh` writes a *different*, **pre-filled** organizational log from an
> inline Python heredoc on personal→organizational upgrade — including a
> `## Retroactive Phase 1 → Phase 2 STA Approval` section the init template does not have, and a
> `Conditions (if any)` row it also lacks. **Any importer must parse both shapes.** This is
> recorded as a residual (§12) rather than silently assumed away.

**Phase 3→4 is the dual-approval gate** — § V requires **Application Owner + IT Security**, two
distinct roles, on the same gate, and the template's append instruction names the order
explicitly ("Application Owner first, then IT Security"). `scripts/check-phase-gate.sh` enforces
it via `validate_approval_section_dated`, called once per subsection header, requiring a real ISO
date (`[Date]` and `YYYY-MM-DD` are rejected) inside a window bounded at the next `#` line — a
bound added because an unbounded `grep -A 15` previously let an IT-Security-only append satisfy
the Application Owner check, "passing dual-approval with ONE signer".

**But it checks that a date is present, not who signed.** In the solo product both signatures are
collected from people outside the repo. In the team product both are roster-resolvable, so
"two **distinct people** signed, each holding the required role" becomes a machine-checkable
predicate for the first time — which is exactly the gap §6.2 quantifies.

### §6.2 — Self-approval detection: the change from "the operator" to "a person"

`docs/governance-framework.md` § V *Approval Verification Controls* already states the rule and
the mechanism:

- Control 1 — "Each approval entry MUST be committed to `APPROVAL_LOG.md` by the *approver*, not
  the Orchestrator. The git author on the commit serves as the verification record."
- Control 3 — "The Orchestrator MUST NOT author git commits that add their own name as approver."
- Control 4 — quarterly reconciliation of commit authors against listed approvers, with the note
  that "CI provides continuous verification via the approval integrity check".

`scripts/check-phase-gate.sh` implements the continuous half in **`validate_approval_fields`**.
The mechanism is stronger than the doctrine implies and its coverage is weaker; both matter.

**The mechanism (keep it).** It locates the gate's Approver row, recovers it H2-strictly if the
permissive scan fails (`# BL-143-PASTCAP-RECOVERY-BEGIN`), computes the row's line number, and
then runs **per-line** `git blame --line-porcelain -L <n>,<n> -- APPROVAL_LOG.md`, comparing
names **token-exact** after normalization — not substring, so `Karl` no longer matches `Karla`.
The comment records the attack the per-line blame closes: a whole-file `git log -1` returned
whoever last *touched* the file, so "Alice commits her own approval row at gate A … Bob later
commits a typo fix to gate B; `git log -1` returns Bob; Alice's self-approval silently passes."
**Inherit this verbatim. It is good work.**

**The coverage gap (fix it).** `validate_approval_fields` is invoked **exactly twice** —
`"Phase 0.*Phase 1"` and `"Phase 1.*Phase 2"`. **There is no call for Phase 2→3 or Phase 3→4.**
The go-live gate — the one § V protects with dual approval and the one whose failure ships to
production — has **no approver-versus-commit-author verification at all**. Both signatures can be
authored entirely by the Orchestrator with nothing detecting it. The function also returns 0
immediately for any non-`organizational` deployment.

**So the team predicate is a widening, not just a rewrite.** It must become: *the approver is a
**different roster member** from the author of the work being approved, **and** holds the role
that gate requires* — and it must run at **all four** gates, with the Phase 3→4 arm additionally
asserting that the two subsection signers are **two distinct roster members**.

**A precedent already exists for the join key.** `_cpg_gate_actor` in the same script composes
`git config user.name` + `user.email` into a `Name <email>` identity and `_cpg_record_gate_date`
writes it to `phase-state.json::gates.<gate>_by`. The framework already captures git identity at
gate time; the roster only gives that identity a stable name.

**A ready-made hardening point exists in CI.** The generated-project workflows
(`templates/pipelines/ci/github/*.yml`, all ten language variants) ship two governance jobs:
*Approval log integrity*, which **hard-fails** any commit that modifies or deletes a committed
line of `APPROVAL_LOG.md` (append-only, enforced), and *Approval author verification*, which
compares commit author to listed approver and emits **`::warning::`** — deliberately
non-blocking, with an inline comment inviting organizations wanting hard enforcement to change it
to `::error::` and uncomment `exit 1`. **For Team Orchestrator that promotion is the default**,
because with a roster the check can distinguish a genuine mismatch from a benign one.

**The `[WARN]` trap governs this change.** In `check-phase-gate.sh` the `[WARN]` / `[FAIL]`
labels are cosmetic; the exit predicate is `if [ $issues -eq 0 ]`, so *any* arm that increments
`issues` blocks the gate regardless of what it prints. Concretely: **every** outcome arm of the
self-approval control increments `issues` and therefore blocks, and only one of them prints
`[FAIL]` — the other arms (ambient-identity mismatch, empty blame author, `NO_SECTION`,
`NO_APPROVER`, placeholder cell) all print `[WARN]` and block anyway. The helper
`_cpg_warn_no_gate_section` (`# BL-144-NO-SECTION-MESSAGE`) says so in its own comment: the WARN
*"BLOCKS (the label is cosmetic; the increment is the exit predicate)"*. The same is true of the
dual-approval arm, the named-pre-condition arm, and the `# BL-104-MANIFEST-ARM` empty-manifest
arm. **The fork's roster-aware arms must therefore declare blocking intent by the increment, not
the label, and every mutation proof must assert the exit code, not the printed text.** The one
genuine global downgrade is `SOIF_PHASE_GATES=warn`, which converts a non-zero `issues` to
`exit 0` with an explicit "(warn mode — not blocking)" message.

### §6.3 — The coordination structures that already exist (C3)

The settled decision's "STA checkpoints" resolves to two real, shipped artifacts. Both are
imported unchanged; both are load-bearing for §7.4's argument that a scrum-master agent is
redundant.

- **Mid-Phase 2 Governance Checkpoint (Organizational)** — `docs/governance-framework.md` § V.
  Biweekly, 30 minutes maximum, held with the Senior Technical Authority for the duration of
  Phase 2. Fixed agenda: features delivered versus scope, architectural deviations, test
  pass-rate trend, unresolved security findings, risk-register delta. Explicitly **not**
  gate-style — "The Senior Technical Authority does not approve or block at this cadence."
- **In-Phase Decision Log** — `docs/governance-framework.md` § V, shipped as
  `templates/generated/decision-log.tmpl`. Append-only rows: date, decision, rationale,
  alternatives considered; the checkpoint's outcomes are recorded as rows in it; reviewed by the
  Senior Technical Authority at the Phase 2→3 gate.

**In a team, both become multi-actor with no schema change** — each row gains the `actorId` of
its author, which the roster already resolves.

### §6.4 — What team membership makes free

Three § X obligations get cheaper or disappear when there is more than one developer, and the
design should claim them rather than re-solve them:

- **Bus Factor.** § X states flatly that "The bus factor for a solo-maintained application is 1"
  and that documentation does not change this. A team of ≥2 with real repository access changes
  it by construction.
- **Backup Maintainer.** § X mandates a designated second technologist with full repository and
  hosting access, a 1-hour monthly sync, and independent incident-playbook execution. In a team,
  the role is *satisfied* by an existing member rather than *appointed* from outside — but the
  **Handoff Test** (§ X, mandatory per project) is still owed, and the design keeps it, because
  its purpose is to surface undocumented tribal knowledge, which a team accumulates faster than
  a soloist, not slower.
- **Quarterly Portfolio Review.** § X requires the Senior Technical Authority to review each
  application independently, not on the Orchestrator's self-report. Roster-attributed ledgers
  make the review's evidence machine-gatherable for the first time.

**What team membership does not make free — and this must not be overclaimed:** § X's
graduation thresholds are properties of the *application*, not the team. A team-built app that
crosses >10,000 users or a compliance-scope change still triggers § X's 30-day assessment and
90-day resolution clock. Team Orchestrator changes who is available to respond; it does not
repeal the trigger.

---

## §7 — The agent delegation layer

### §7.1 — Roles 1–5: inherited as *designed*, not as *built* (C4)

`docs/designs/2026-07-24-operating-model-v1.md` specifies five delegation roles — **planner,
implementer, verifier, investigator, mechanical** — a per-role model/effort choice stored as
tier tokens in a `.claude/manifest.json` `operatingModel` block, presets (`always-best`,
`balanced`, `single-model`), and an enforcement story tiered mechanical/auditable/advisory.

**It is a design, not code.** That document's own §1 records the verification:
`grep -rn 'operating_model\|operatingModel\|modelTier' scripts init.sh templates` returns
nothing. Team Orchestrator therefore inherits a **specification**, and §10 sequences the fork's
role work *after* it, or accepts building it in the fork first.

**What the team product changes about roles 1–5: nothing structural, one addition.** The five
roles are the **per-developer** delegation substrate — each team member dispatches their own
planner/implementer/verifier fleet. The one addition is that a dispatch's audit trail carries the
dispatching member's `actorId`, so "who ran a mid-tier implementer on gate code" is answerable.
The BL-097 "verifier ≥ implementer" rule is **unchanged and still per-developer** — it is a
property of a change, not of a team.

**Rejected: a shared team-wide agent pool.** Tempting and wrong. It would make the dispatch
ledger ambiguous about which human's work a given agent run belongs to, destroying the
attribution §5.4 is built to provide.

### §7.2 — Role 6: the BA agent

**Mechanical value, stated concretely.** Phase 0 already demands three structured documents
before the Product Manifesto is written, and they already ship as templates:

| Surface | Phase 0 step | What it captures |
|---|---|---|
| `templates/generated/frd.tmpl` | Step 0.1 | Full functional requirements — "the detailed logic triggers, failure states, and rationale that the Manifesto summary may compress" |
| `templates/generated/user-journey.tmpl` | Step 0.2 | The user journey map. Note the template already names its adversarial persona: *"Agent persona for this step: Skeptical Product Manager. Challenge every success path."* |
| `templates/generated/data-contract.tmpl` | Step 0.3 | What data flows through the system — explicitly **not** how (architecture is Phase 1) |
| `templates/project-intake.md` + `scripts/intake-wizard.sh` | Phase 0 input | The structured intake the wizard fills interactively |

The BA agent's job is **intake refinement over exactly these four surfaces**: take a rough team
request, interrogate it, and produce FRD / user-journey / data-contract drafts complete enough
that the Phase 0→1 gate has something real to judge. This is mechanical value because the target
artifacts are already gate-visible — `scripts/check-phase-gate.sh` already references the Phase 0
document set — so a better draft is measurably a better gate outcome, not a nicer-looking file.

**Why a team needs this more than a soloist.** A soloist holds the requirement in their head and
the FRD is a formality. On a team the FRD is the *interface between people*, and its quality is
the difference between two developers building the same thing and two developers building
adjacent things.

**Honest tiering.** The BA agent is **advisory**. It drafts; it does not approve. The Phase 0→1
gate approval remains the Project Sponsor's (§6.1), and no agent output satisfies a gate.

### §7.3 — Role 7: the PM agent

**Mechanical value, stated concretely.** This repository practises a ledger discipline on
itself — dated handoffs with one live state-of-record and archived-with-stub predecessors, a
backlog whose Closed entries must cite a PR or a commit SHA (`scripts/lint-backlog-references.sh`
enforces it), and Closed entries kept permanently as audit substrate. That discipline is
currently a *practice*. Productizing it is the PM agent's entire remit.

| Surface | What the PM agent maintains |
|---|---|
| `templates/generated/decision-log.tmpl` | In-Phase Decision Log rows, and the biweekly checkpoint rows (§6.3) |
| `templates/generated/features.tmpl` | The MVP-cutline reconciliation § V's Phase 2→3 gate demands as evidence ("FEATURES.md vs MVP Cutline reconciliation") |
| `templates/generated/approval-log-org.tmpl` | Approval-log hygiene: entries complete, evidence references present. **It never authors an approval** (§6.2 forbids it structurally) |
| `templates/generated/changelog.tmpl` | Changelog currency, which § X's maintenance-cadence tracking depends on |
| the fork's `TL-` backlog | Entry hygiene: statuses in the real vocabulary, Closed entries carrying a PR/SHA citation |

**Why this is not process theater when a scrum master would be.** Every artifact above is
already **read by a gate or a mandated review**. The PM agent's output is checked by machinery
that exists. Its failure mode is a stale document, which a lint catches.

**Honest tiering.** **Auditable, not mechanical.** The PM agent keeps records; it does not
enforce. `scripts/lint-backlog-references.sh` and the phase gates remain the enforcement.

### §7.4 — Why there is no scrum-master agent (D4)

Stated with its rationale, because reviewers will ask and because the negative result is a
design decision of equal weight to the positive ones.

A scrum master's function is **unblocking humans and shielding a team from process
friction**. In this product:

1. **There is no team for it to unblock.** The developers are humans with a roster and a
   decision log; the agents are dispatched per-developer (§7.1) and have no standing to
   reprioritise another human's work.
2. **Its coordination outputs already exist as mechanical artifacts.** Standing coordination is
   met by the **In-Phase Decision Log** (§6.3), the **biweekly Mid-Phase 2 checkpoint** with its
   fixed agenda (§6.3), and the org track's escalation ladder — *Orchestrator → Senior Technical
   Authority → Project Sponsor → CIO* (`docs/governance-framework.md` § V *Escalation Path*),
   with five named escalation triggers. An agent producing a *narrative* about these adds a
   document nobody's gate reads.
3. **It would fail the product's own honesty test.** Every surface in this framework is tiered
   mechanical / auditable / advisory. A scrum-master agent is advisory-only with no artifact a
   gate consumes — the definition of process theater in a system whose entire value proposition
   is that its claims are checkable.

**The falsifiable version of this decision**, offered to reviewers: if a pilot team reports that
coordination failures are their dominant cost *and* that the decision log plus the biweekly
checkpoint did not surface them, this decision should be revisited — and Question 8 in the final
section asks exactly that.

---

## §8 — Graduation as migration (D5)

`docs/governance-framework.md` § X *Graduation Criteria* mandates transition when any one trigger
fires:

| Trigger | Threshold |
|---|---|
| Active user count | >10,000 |
| Sustained maintenance demand | >4 hours/week for 3+ consecutive months |
| Enterprise system integrations | >3 |
| Business criticality | Designated business-critical by the Application Owner |
| Compliance scope change | Application comes under SOC 2, HIPAA, PCI-DSS, or similar |

Enforcement is a **30-day assessment / 90-day resolution** clock, and § X is categorical: "An
application MUST NOT remain in Solo Orchestrator state beyond 90 days after a graduation trigger
is met without a written CIO exception."

**Today the destination is unstructured.** § X *Graduation Transition Plan* hands the codebase to
"a conventional engineering team", budgets 40–80 hours of Orchestrator knowledge transfer against
`HANDOFF.md` / the Project Bible / the ADRs, has the receiving team "produce a remediation plan",
and runs 4–8 weeks of parallel support before cutover. **Nothing about the receiving team is
specified** — not their tooling, not their gates, not their audit trail. A project leaves a
governed environment for an unknown one, and that is the weakest joint in the whole governance
story.

**Team Orchestrator is the specified destination**, and migration becomes a first-class intake
path with three properties:

| Property | Mechanism | Why it matters at the gate |
|---|---|---|
| **State carries over, it does not restart** | `phase-state.json`, `manifest.json` (`deployment`, `poc_mode`, `enforcement_level`), and `orchestrator-source.json` migrate in place; the project does not re-enter Phase 0 | A production application forced back through Phase 0 would be re-approved by people who never de-approved it. The phase is a fact about the app, not about the team. |
| **The audit trail is continuous** | The inherited `bypass-audit` ledger converts to `.jsonl` (§5.4) with every historical row preserved and `actorId: null` / `actorIdSource: "unmatched"` — legibly **pre-roster**, not blank | § X's whole shadow-IT argument rests on the audit being reconstructible from the repo. A migration that truncates it defeats the control. |
| **The Orchestrator becomes roster member #1** | The soloist is written into `.claude/roster.json` holding `orchestrator`; the receiving developers are added as members; the 4–8 week parallel-support window of § X step 4 is exactly the window in which the roster grows | § X's knowledge-transfer step gets a mechanical companion: the **Handoff Test** (§6.4) is run by the new members, against the same documentation, with a recorded result |

**What this does not fix, stated plainly.** Migration does not address § X step 3 — the receiving
team's codebase assessment and remediation plan. A graduating application's technical debt is
real and is not a bookkeeping problem. Team Orchestrator gives the receiving team the *gates* to
work under; it does not pay the debt.

---

## §9 — What does not change (the honest blast radius)

Named explicitly so reviewers can see the fork's true scope. Everything in this section carries
over **untouched in substance**.

| Kept | Anchor | Note |
|---|---|---|
| **The Phase 3 security scanners** | `scripts/run-phase3-validation.sh` — SAST, dependency, license, DAST (incl. the hardened-serve arm `# BL-165-HARDENED-SERVE` and the risk filter it judges under) | Zero team-specific content. A scanner does not care how many people wrote the code. |
| **The commit-time gates** | `scripts/pre-commit-gate.sh` (TDD ordering + Build-Loop message check), the installed framework gate, `scripts/hooks/bypass-detector.sh`, `scripts/hooks/record-claude-commit.sh` | Gate *predicates* unchanged. Only the ledger rows they write gain `actorId` (§5.4). |
| **The phase gates' security substance** | `scripts/check-phase-gate.sh` | The approval *identity* logic changes (§6.2). What is being approved — architecture, security posture, data classification, go-live readiness — does not. |
| **The six-reviewer review-manifest gate** | `scripts/check-phase-gate.sh` (`cpg_role_present`, `# BL-073-ESCALATE`, `# BL-073-ATTEST-WRITE`, `# BL-104-MANIFEST-ARM`, `# BL-166-GATE-SCOPE`) + `scripts/lint-review-manifest.sh` + the repo-root `evaluation-prompts/` library | **A second, already-multi-role surface, kept whole.** Six canonical reviewer slugs (`redteam`, `security`, `engineer`, `cio`, `legal`, `techuser`); Security **and** Red Team mandatory on standard/full tracks; the full track requires all six. Its escape hatch is the framework's doctrine in miniature — `SOLO_REVIEWERS_ATTESTED=1` plus a non-empty reason, persisted to `process-state.json`: **"blocks are attested, not silenced."** The team product changes nothing here except that the attestation gains an `actorId`. |
| **The enforcement-tier concept** | `enforcement_level` = `no` / `light` / `strict`, plus the deployment + `poc_mode` tier predicate marked `# BL-084-TIER-KEY` in `pre-commit-gate.sh`, `check-phase-gate.sh`, `init.sh`, and `scripts/lib/enforcement-level.sh` | **Reused, not replaced** — the roster's own failure severity rides this ladder (§5.3). The "SYNC SIBLINGS" obligation is inherited. |
| **The Build Loop classifier** | `scripts/process-checklist.sh` | Its *state file* becomes branch-keyed (§5.2). Its classification logic does not change. |
| **The repo hygiene lints** | 13 `scripts/lint-*.sh`; 11 CI lint jobs | Two get a prefix-set patch (§3.3). The other eleven are untouched. |
| **The house rules** | No merge on red; never `--no-verify`; TDD with mutation proofs for enforcement changes; hermetic tests only; register every new suite in **both** lists; grep-able marker citations, never bare `file:line` | These are the reason the asset base is worth forking. Changing them would forfeit the inheritance. |
| **The docs estate conventions** | Live-vs-archive with pointer stubs; `docs/INDEX.md` as the map; dated `Reports/` | Inherited wholesale. |

**The honest summary of blast radius:** the fork rewrites the **execution/bookkeeping layer** and
**one predicate** in the phase gate (approval identity). It does not touch security substance,
scanner behaviour, tier semantics, or the Build Loop's classification. A reviewer who reads this
section and §5 together has the complete change surface.

---

## §10 — Build plan skeleton (ordered work packages)

Every WP goes through adversarial acceptance. "Mutation-provable" means the RED-under-neuter →
GREEN-restored proof this framework requires of enforcement code.

| WP | Scope | Test intent · mutation proof |
|---|---|---|
| **WP0 — Fork establishment + honest baseline** | §3.3's four obligations, in order. Then the §3.2 measurement **by execution**: run the suite against a changed-shape shim and record what actually breaks. **No code changes.** | *Deliverable:* a dated report and one `TL-` entry per red suite (fix or recorded retirement) |
| **WP1 — Roster schema + resolution** | `.claude/roster.json` (§5.3); the `git config user.email` → `actorId` resolver; tiered unmatched-identity behaviour on the `# BL-084-TIER-KEY` ladder | Multi-identity members resolve; a retired member's historical rows still resolve; unmatched is silent at `no` / warns at `light` / blocks at `strict`. **Mutation:** neuter the strict arm → unmatched identity commits → RED |
| **WP2 — Ledger actor fields** | `actorId` + `actorIdSource` on the `scripts/lib/bypass-audit.sh` writers and the two hook writers. Additive; the `actor` class enum untouched | Every existing row-shape assertion still passes; a matched commit writes `roster`, an unmatched one writes `unmatched`, never a blank. **Mutation:** force the resolver to always succeed → an unmatched identity is laundered as `roster` → RED |
| **WP3 — Ledger → JSONL + union merge** | `bypass-audit.json` → `.jsonl`, row UUIDs, `.gitattributes merge=union`, a parse lint. **Repair the two dead pins and the five unlocked writers of §5.4 in the same wave**, and amend all three F8-precedent surfaces: writers, integration-suite assertions, and `docs/audit-log-lifecycle.md`'s taxonomy **and cold-pickup jq recipes** | A two-branch concurrent append merges with no conflict and no row loss; duplicates detectable by UUID; a malformed line fails the lint; T5/T6 now fail on a bad value (today they cannot) |
| **WP4 — Branch-keyed workstream state** | `process-state.json`, `build-progress.json` → `.claude/workstreams/<slug>/`; teach every reader/writer the resolver, starting at `scripts/lib/phase2-state.sh` (`_phase2_state_repo_root`, `_record_phase2_step`) | Two branches keep independent build loops with zero conflict; a merge to `main` carries the directory; detached HEAD hits the fallback rather than crashing |
| **WP5 — Actor-keyed state** | `tool-usage.json`, `settings.local.json` → `.claude/actors/<actorId>/`; and **ignore `settings.local.json`**, closing the C2 docs-versus-behaviour mismatch | Two actors' counters never collide; a missing actor directory is created idempotently |
| **WP6 — Wheel lease + serialized-driving default** | `.claude/wheel.json`, expiry, attested break path (§5.5); unify `pa_check`'s relative sentinel path with `find_project_root()` | A non-holder's gate-advancing action is refused at `strict`; an expired lease is breakable; every break writes a ledger row naming breaker and reason. **Mutation:** suppress the break row → a silent steal → RED |
| **WP7 — Roster-aware approval identity, widened to all four gates** | §6.2's predicate — approver ≠ author-of-work **and** approver holds the gate's role — extended from `validate_approval_fields`'s two current call sites to **Phase 2→3 and Phase 3→4**, which have no author verification today. Promote the generated-project CI *Approval author verification* job from `::warning::` to `::error::` | Self-approval blocks at **each** of the four gates; a correct two-person approval passes; right-person/wrong-role blocks; Phase 3→4 requires two **distinct** roster members and an Orchestrator-authored pair blocks (it passes today). **Mutation:** drop the `issues` increment → self-approval passes → RED, **asserted on the exit code, not the label**. Preserve the contracts pinned by `tests/test-check-phase-gate-self-approval.sh`, `tests/test-check-phase-gate-blame-walker.sh`, `tests/test-bl170-approval-append-design.sh` |
| **WP8 — BA + PM agent surfaces** | Role definitions and artifact bindings (§7.2, §7.3) | Generated artifacts validate against their templates; **no agent path can author an approval-log approval entry** |
| **WP9 — Migration intake path** | §8's flow: state carry-over, ledger conversion preserving `actorId: null`, roster seeding | A solo-generated fixture migrates with phase preserved, zero ledger rows lost, pre-roster rows legibly marked |
| **WP10 — Docs** | The fork's `CLAUDE.md`, `docs/INDEX.md`, and the governance-framework team delta | `lint-doc-anchors.sh --strict-refs` and `lint-backlog-references.sh` clean |

**Sequencing.** WP0 → WP1 (everything keys on the roster) → WP2/WP3 (ledger) → WP4/WP5 (state
keying) → WP6/WP7 → WP8/WP9 → WP10. **WP7 is the linchpin** — the only package that changes a
gate predicate, and where the `[WARN]` trap will bite a careless implementer. WP6 and WP7 both
get top-tier implementation and double-mutation verification.

---

## §11 — Non-goals and rejected alternatives

- **In-repo variance and the thin kit** — rejected (§3.1, settled).
- **A permanent merge channel** — rejected (§4). A permanently-merged fork is in-repo variance
  with extra steps and re-incurs the cost §3.1 rejected.
- **An external lock server or state service** — rejected (§5.2). It breaks the
  reconstructible-from-a-clone invariant that `docs/governance-framework.md` § X names as the
  thing making the enforcement guarantee real.
- **Growing the `actor` enum with human names** — rejected (§5.4) on the repo's own F8 precedent:
  a single new enum member was out-of-schema on three surfaces at once; an unbounded domain makes
  any enum pin unwritable.
- **Keying every state file by actor** — rejected (§5.2). It would let two people hold
  contradictory beliefs about the project's phase with nothing to surface the disagreement.
- **A scrum-master agent** — rejected (§7.4, settled), with a falsifiable revisit condition.
- **A shared team-wide agent pool** — rejected (§7.1): it destroys dispatch attribution.
- **Re-entering Phase 0 on migration** — rejected (§8): the phase is a fact about the
  application, not about the team.
- **Scaling past 10 developers** — out of scope (§2), not merely unbuilt.

---

## §12 — Honest residuals

Written in the house style: what is deferred, what is unknowable today, and which assumptions
would falsify parts of this design.

**Deferred by decision (named, scoped, not designed here):**

1. **Parallel-workstream merge semantics beyond two drivers.** Branch-keyed state (§5.2) is
   conflict-free for *N* branches, but the design has only reasoned carefully about two
   concurrent drivers of *gate-advancing* work. Three or more simultaneous approvals against one
   phase gate needs an ordering rule (queue? first-complete-wins? sponsor arbitration?) that v1
   does not specify. The serialized-driving default (§5.5) is what makes deferring this safe —
   the unspecified case is unreachable in the default mode.
2. **Cross-repo CI.** A team spanning several repositories has a CI story this design does not
   touch. Every gate here is repo-local by construction, which is a limit, not an oversight.
3. **The Change Assessor itself** (§4.3) — a separate coordination-repo product, contracted here
   only as a dependency.
4. **Secrets and hosting access provisioning.** § X mandates that the Backup Maintainer can
   retrieve production secrets and that access is verified quarterly. Team Orchestrator records
   *who holds which role*; it does not provision anything.
5. **The wheel-lease UX.** §5.5 specifies the lease's semantics, not how a developer acquires,
   sees, or hands off the wheel in practice. That is a pilot-informed design.
6. **The two approval-log seams (§6.1).** (a) `init.sh::generate_approval_log` and
   `scripts/upgrade-project.sh` emit **two different organizational logs** — an empty append-only
   template versus a pre-filled Python-heredoc variant carrying a
   `## Retroactive Phase 1 → Phase 2 STA Approval` section the template lacks. WP7's roster-aware
   parser must handle **both**, because a parser written against only the init shape would pass
   its own tests and fail on every upgraded project. (b) The template is selected by `$DEPLOYMENT`
   alone, never by `TRACK`. Collapsing (a) to one generator and closing (b) are both right fixes
   and both out of this design's scope — recorded rather than assumed away.

**Cannot be known before a pilot:**

7. **Whether serialized driving is tolerable.** §5.5 argues the throughput cost is confined to
   gate-advancing work. That is a reasoned claim, not a measured one, and it is the single most
   likely thing a pilot refutes. If refuted, WP6's mode flag is the escape and concurrent driving
   moves up the schedule.
8. **Whether the BA and PM agents earn their keep.** §7.2 and §7.3 argue mechanical value from
   the fact that their outputs are gate-read. Whether teams *use* them is a different question.
9. **Where 2–10 actually breaks.** The upper bound is reasoned (§2), not measured.
10. **How much of the inherited suite genuinely breaks.** §3.2 deliberately declines to state a
   number and makes the measurement WP0's deliverable, because this repo's own history contains
   two grep-based audits that under-read a comparable surface.

**Assumptions that would falsify parts of this design if wrong:**

11. **The merge-channel decay schedule (§4.4)** assumes the state rewrite lands inside one
    quarter, that upstream Solo stays actively developed, and that shared-path divergence stays
    reviewable in under an hour a week. If the third fails first, P2 collapses into P3 early —
    which is a success case, since the channel was always meant to end.
12. **The operating-model design ships** (C4). If roles 1–5 are never built upstream, the fork
    must build them itself; §7.1 is written so that this changes the schedule, not the
    architecture.
13. **`merge=union` is adequate for the ledgers** (§5.4). Its three known limits are stated with
    mitigations. If a pilot shows duplicate-row noise is worse than predicted, the fallback is
    per-actor ledger shards with globbing readers — more invasive, and deliberately not v1.

---

## Self-review pass (fresh-eyes checklist)

- **Every commissioned element present?** Execution-layer rearchitecture (§5), governance import
  with the mapping table (§6), the delegation layer including BA/PM and the scrum-master negative
  (§7), the explicit kept-set (§9), honest residuals (§12), and the reviewer questions (below) —
  plus Document Control, the plain-English opening, §0 traceability, and a build plan (§10).
- **Every "exists today" claim anchored?** Yes, and re-derived on 2026-08-02 rather than trusted
  from the brief — which is how C1 through C4 were found. Anchors are function names
  (`_phase2_state_repo_root`, `_record_phase2_step`), marker comments (`# BL-084-TIER-KEY`,
  `# BL-165-HARDENED-SERVE`, `# BL-161-NO-ROUTINE-PASS`, `# BL-174` sibling pair, `# BL-089`), or
  named document sections (`docs/governance-framework.md` § V, § X). No bare `file:line` anywhere.
- **Are the settled decisions designed within, not relitigated?** Yes. D1–D5 appear in §0.1 as
  premises. Where the repository corrected the *framing* (C1–C4), the correction is flagged in
  §0.3 and designed for. No settled decision is contradicted by any repo fact found.
- **Is enforcement honestly tiered?** Yes. §7.2 marks the BA agent advisory; §7.3 marks the PM
  agent auditable-not-mechanical; §5.4 states three named limits of `merge=union`; §5.5 states
  the wheel is a lease, not a lock; §6.4 refuses to claim graduation triggers are repealed; §8
  refuses to claim migration pays technical debt.
- **Unresolved placeholders?** None. Every underdetermined choice is a decision table with one
  recommendation and stated alternatives (fork shape §3.1; state keying §5.2; actor field §5.4;
  driving mode §5.5), or is named in §12 as an explicit deferral.
- **Biggest attack surface for the reviewer.** §3.2 (the suite-blast-radius claim, deliberately
  stated as a method with the number deferred to WP0) and §5.5 (the throughput cost of serialized
  driving, argued but unmeasured). Both are flagged rather than defended.

---

## Questions for Reviewing Architects

Ten questions, all answerable from your own environment, each attached to a decision this design
can still change. Answers received before the build starts are cheap; answers received after WP1
are not.

1. **Identity and SSO.** The roster (§5.3) joins on `git config user.email`. In your
   environment, is a developer's git identity the same as their SSO identity — and if not, should
   the roster carry a second key (an SSO subject, an employee ID) so approvals reconcile against
   your identity provider rather than against a self-declared email?

2. **Approval hierarchies per company.** §6.1 defines seven gate-bearing roster roles, plus six
   more named only at Pre-Phase 0 (Insurance Broker, Legal/CIO, Executive Sponsor, Technical
   Lead, ITSM/PMO, IT Security). Do your organizations use this set, or do you need slots it
   lacks (a data steward, a change advisory board, a divisional CISO)? And are any of your
   approvals **committee** decisions rather than individual ones? A committee signature is a
   shape this design does not currently have — the roster models people, and the gates compare
   one approver against one author.

3. **Repository hosting constraints.** The design assumes GitHub-style branch protection and
   required status checks (§3.3). If your companies run GitLab, Bitbucket, or Azure DevOps —
   which of them, and are there hosting constraints (self-hosted only, no forks across
   organizations, mandatory signed commits) that change the fork protocol?

4. **Serialized versus concurrent driving.** §5.5 ships serialized driving by default and defers
   concurrent driving to v2. For **your** team sizes and cadence, is a single gate-advancing
   driver at a time acceptable for a first release, or is concurrent driving a day-one
   requirement? This is the single answer most likely to reorder the build plan.

5. **Audit retention and export.** The ledger is a JSONL file in the repository (§5.4). Do your
   compliance regimes require the audit trail to be exported to an external system — SIEM, GRC
   platform, ITSM — and if so, is a push, a scheduled export, or a pull API the right shape?

6. **Team boundaries and contractors.** The roster models members with git identities and an
   `endedAt` (§5.3). How do you handle contractors, offshore partners, and people who need to
   *approve* but never commit? The design permits a roster entry with no git identity — is that
   sufficient, or do you need a distinct classification with different evidence rules?

7. **Where the graduation boundary really sits.** §8 makes Team Orchestrator the destination for
   applications graduating out of solo operation. Given § X's thresholds (>10,000 users, >4
   maintenance hours/week sustained, >3 enterprise integrations, business-critical designation,
   compliance-scope change), is a 2–10 person Team Orchestrator the *right* destination for
   applications at that size in your organizations — or is it an intermediate stop before a
   conventional engineering team?

8. **The scrum-master decision (§7.4).** We argue coordination needs are met by the In-Phase
   Decision Log, the biweekly Mid-Phase 2 checkpoint, and the escalation ladder. From your
   experience running teams of this size: is that sufficient, or is there a specific recurring
   coordination failure those artifacts demonstrably do not catch? A concrete failure mode would
   reopen this decision.

9. **Pilot appetite, and what a pilot would need.** Would any of your organizations run a pilot,
   and if so: what is the smallest real project you would trust it with, what would you need to
   see before starting (a security review, a data-handling attestation, an exit plan), and what
   would you measure to call it a success?

10. **The rule we have not written.** Each of your companies runs software delivery under
    constraints we have not modelled. What is the one control your environment mandates that this
    design would fail on day one — and would it be a configuration, a new gate, or a reason the
    product does not fit at all?
