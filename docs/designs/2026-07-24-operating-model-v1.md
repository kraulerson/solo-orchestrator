# The Configurable Operating Model — design v1 (normative-once-reviewed for the build)

**Status:** v1.2.2, 2026-07-25 — **review-r4 (the standing adversarial pr-reviewer, dispatched on PR #269):
corrections folded** — 2 MAJORs (R-269-1 version-floor story; R-269-2 nonexistent "S5 lint") + 6 minors,
all mapped in §0; no decision-table, adopted-mechanism, or WP-boundary change; WP3/WP4/WP4b/WP5 test intents retuned
per R-269-3/4/5 (R-269-9 wording precision). Prior: r3 APPROVE at v1.2.1; r1/r2 BLOCK → the v1.1/v1.2 remediations.
The build of the BL-097 / BL-098 / BL-100 delegation trio is now **un-gated on review**, still sequenced
after Dogfood-4 per Karl's 2026-07-20 decision; the three backlog entries stay Open until the build
lands. No product code, template edit, or policy text lands from this work package: design doc only.
Every "exists today" anchor was re-grep-verified 2026-07-24, and re-derived independently at r4 on
2026-07-25 — which refuted two narrative-layer claims, now corrected (v1.2.2). Prefer the grep recipes
over quoted line numbers; re-verify before editing.

**Provenance:** authored per Karl's recorded **2026-07-20 trio decision** (logged verbatim
on BL-097, referenced by BL-098 and BL-100): enforcement of the delegation protocol becomes
a **configurable operating model**, chosen per role at setup, then enforced, with a
documented reconfigure path and a single-model degradation story — because *not every AI
setup has multiple models*. Modeled structurally on `docs/designs/2026-07-12-currency-system-v1.md`
(the repo's normative design-doc precedent): its §0 changelog convention, its decision-table
discipline, and above all its rule that **every "exists today" claim carries a verification
anchor** (that design was blocked in review-r1 for claiming an unbuilt thing existed).

**Backlog:** BL-097 (right-sized dispatch rubric), BL-098 (plan-first execution), BL-100
(adversarial acceptance) — together the complete delegation protocol: plan → right-sized
build → adversarial acceptance. Interacts with BL-109 (currency/upgrade pipeline — the
config rides its inventory + backfill machinery), BL-092 (template modularization — shared
CLAUDE.md surface), and BL-030 (the `enforcement_level` feature — the closest structural
precedent: a policy chosen at init, enforced, reconfigurable, backfillable).

---

## §0 — Review-amendment changelog (traceability)

**v1.1 (2026-07-24) — review-r1 amendment map** (finding → resolution; corrections rewritten on
top, not accreted; F1/F2/F3 were refuted "exists" claims — all now re-grepped, not header-trusted):

- **F1 (BLOCK) → §9/WP6** — migration re-anchored to the BL-030 `enforcement_level` arm in `_run_idempotent_backfill` (writes deployment/poc_mode/enforcement_level + an `enforcement_level_set` row); the `currency` block is **birth-stamp-only** (`soif_currency_stamp` = one call site), never a backfill precedent as v1 claimed.
- **F2 (BLOCK) → §4/§8** — the intake wizard does NOT call `reconfigure-project.sh` (one `print_warn`) and has no enforcement-level question; verified surfaces = init flag + reconfigure flag; the wizard question + its manifest write-path are NEW wiring, now labelled.
- **F3 (BLOCK) → §5-s1/WP4** — `lint-review-manifest.sh` is a JSON-shape linter, not render-vs-manifest; no such lint exists — the WP4 lint is NEW (nearest precedents: currency `renderBases` sha-tracking + freshness `render-base`).
- **F4 (MAJOR) → §5.1/§11** — PreToolUse is matcher-generic (`init.sh` writes Bash AND Write/Edit groups); surface 4 is now a decision table — an `Agent`-matcher gate (fail-open by matcher inertness) + harness-native `.claude/agents` role pinning, both adopted; §11 stops branding a Task gate as oversell.
- **F5 (MAJOR) → §6.1** — restored BL-098 plan-review wiring + anti-bloat r4 (BL-090 checker) / r5 (grep/section/history).
- **F6 (MAJOR) → §3/§4/§7** — config stores **tier tokens** (`tier:top`…) until the operator binds real ids (`modelsBound`), resolving the opaque-id-vs-default contradiction.
- **F7 (MAJOR) → §5-s1/§8/WP4** — dual-source lifecycle closed: lint executing surface (pre-commit-gate arm), A1 re-render leg, marker-block mechanism, manifest-wins.
- **F8 (MAJOR) → §8/WP3** — `operating_model_set` is out-of-schema on three surfaces (`bypass-audit.sh` enum, `test-bl029-integration.sh` T6, `docs/audit-log-lifecycle.md`); WP3 amends all three.
- **F9 → §3** `.claude/tool-preferences.json` location row added · **F10 → §2/§4** dropped "verbatim", investigator fact-verification rounding = rendered doctrine · **F11 → Open-Qs** model-id-vanishes + freshness-enum-growth · **F12 (drive-by) → `docs/INDEX.md`** Designs row added.

**v1.2 (2026-07-24) — review-r2 amendment map** (r2 BLOCK, narrow; all 12 r1 resolutions verified genuine):

- **R2-1 (BLOCK) → §5.1** — corrected the ".claude/agents ships nothing" claim: init.sh ships none to generated projects (verified), but the framework repo carries BL-146's `pr-reviewer` (`.claude/agents/pr-reviewer.md`, `model: fable`) — the in-family precedent for mechanism (b).
- **R2-2 (MAJOR) → §10-WP4a/WP4b** — added WPs building both ADOPTED F4 mechanisms: (b) manifest-rendered role-agent files and (a) the PreToolUse `Agent`-matcher gate, each with test intent + mutation proof.
- **R2-3 (MAJOR) → §5.1/WP4b** — defined gate semantics: unbound (`modelsBound:false`) enforces only "a model is named" (BL-097 r1); the set-membership arm activates on bind; membership = exact-string over the bound set (no framework alias resolution — provider-neutrality).
- **R2-4 (MAJOR) → §5.1/§5-s3** — reworked the version-floor story so fail-open rests on **matcher inertness**, not a version compare. **[Corrected at r4 / R-269-1: the r2 "uncitable / present by 2.1.69 / gradual transition" reading was itself a docs-search miss — sub-agents.md documents the rename at exactly 2.1.63, with `Task(...)` kept as a backward-compat alias, which is why `Task` prose recurs in later changelog entries.]** **Independent-verification note:** the `resolvedModel`/`modelsUsed` versions (2.1.174/2.1.212) have zero mentions in the public changelog (verified), so I flagged rather than laundered — **resolved at r3 (see v1.2.1):** hooks.md's `Agent` `tool_response` table documents both; the pins are restored, feature-detection retained.
- **R2-5 (MINOR) → §3/§4** — named the deterministic single-model pre-bind token: `tier:top` (all five roles).
- **R2-6 (MINOR) → §10-WP5** — the session-start line now reports the gate active/inert (one word), so fail-open is attested, not silent.

**v1.2.1 (2026-07-24) — review-r3: APPROVE** (design cleared; no further round). Two MINOR folds:

- **R3-1 → §5.1/§5-s3/Q7** — the `resolvedModel`@v2.1.174 / `modelsUsed`@v2.1.212 pins are **restored**, cited to **hooks.md's `Agent` `tool_response` schema table** (NOT the changelog). **Adjudication:** the r2 doubt was half-right — the changelog has **zero mentions (verified)**, but **hooks.md documents both**; my r2 hooks-docs search was the miss. The refuse-to-launder posture was ruled correct process, and the runtime mechanism **stays feature-detection** (version-proof; a doc-annotation anchor is weak). **Open question 7 is closed (resolved).** Cosmetic: "without an `Agent` matcher" → "whose dispatch tool is not named `Agent`".
- **R3-2 → §5.1/WP4b** — adopted **STRICT** composition: the gate's names-no-model deny applies even to a role-typed dispatch (`subagent_type:<role>` with no explicit `model`); the shipped role file's frontmatter pin is defense-in-depth, not an exemption (BL-097 r1). Stated so the semantics and WP4b's test list agree.

**v1.2.2 (2026-07-25) — review-r4 amendment map** (the standing adversarial pr-reviewer — `.claude/agents/pr-reviewer.md`, BL-146 — dispatched on PR #269; 2 MAJOR + 6 minor, all folded; no decision-table, adopted-mechanism, or WP-boundary change — WP3/WP4/WP4b/WP5 test intents retuned per R-269-3/4/5, and WP5's shipped attestation word-pair changed per R-269-5):

- **R-269-1 (MAJOR) → §0-R2-4/§5.1×3** — the "uncitable v2.1.63+ / gradual transition / ≥2.1.69" story was FALSE: sub-agents.md documents the `Task`→`Agent` rename at exactly **2.1.63** ("In version 2.1.63, the Task tool was renamed to Agent. Existing `Task(...)` references in settings and agent definitions still work as aliases"). Floor corrected + cited; "gradual transition" deleted; fail-open was never floor-dependent, unchanged.
- **R-269-2 (MAJOR) → §10-WP6/Q6** — "the S5 lint" does not exist: currency-design slice S5 is UNBUILT (`session-freshness-check.sh`'s MACHINE-BLOCK CONTRACT comment says "S5 will lint it" — future tense; today the `soif-freshness` fence's only consumers are the freshness scripts/tests). Both sites now say so and anchor to that comment.
- **R-269-3 → §10-WP3/WP4** — WP3's test list asserted the CLAUDE.md marker-region rewrite, a WP4 deliverable that does not exist at WP3's sequence position; the assertion moved to WP4 (F7c's home); WP3 keeps manifest+audit scope.
- **R-269-4 → §10-WP4b** — "the hook is inert where the dispatch tool is not named `Agent`" is harness behavior, not testable in this repo; replaced with hermetic proxies (matcher string exactly `Agent`; the hook script exits 0 on any non-`Agent` `tool_name` stdin).
- **R-269-5 → §10-WP5** — the active/inert attestation had no detection mechanism (settings registration ≠ harness support — an old harness would attest "active" while inert, the exact silent degradation R2-6 targets); downgraded to the honest pair **configured / not-configured**, read from `.claude/settings.json`.
- **R-269-6 → §8** — the "cannot change it without the ledger recording it" claim is qualified to the reconfigure surface; an out-of-band manifest edit passes the WP4 lint (consistency, not provenance) un-ledgered — commit review is the backstop (same property as `enforcement_level` today); optional WP6-time informational crosscheck noted.
- **R-269-7 → §5-s3/self-review** — the resolvedModel/modelsUsed pin story deduplicated: the §5.1 residual-limits note is canonical; body siblings point at it (§0 entries and Q7 remain as ledger).
- **R-269-8 → §5.1** — "docs-confirmed" fail-open now carries its citations (hooks-guide: "check that the matcher pattern exactly matches the tool name (case-sensitive)"; debug-your-config: "A misspelled tool name will also prevent the matcher from working").

Status: **v1.2.2 — the r3 APPROVE stands on every design decision; r4 folded narrative/coordination corrections only.** The trio build is un-gated on review (still sequenced after Dogfood-4); the three backlog entries stay Open until it lands.

---

## §1 — Problem and evidence

Four failures motivate this work. Each is anchored; where a claim is an operational record
without a git artifact, that is stated.

| # | Problem | Evidence (anchor) | Evidence tier |
|---|---|---|---|
| 1 | **Silent model inheritance.** Dispatched subagents inherit the session's model without anyone naming it. On 2026-07-10 (gate wave) a fleet silently ran on an *unintended* model until killed and relaunched. | `Reports/2026-07-11-project-post-mortem.md` §5b ("The model-dispatch mistake"); BL-097 problem statement. | Operational — the post-mortem §5 preamble states 5b is an operator process-note incident with **no SHA**. Reported as motivation, not repo-verifiable fact. |
| 2 | **Blanket top-tier cost.** The opposite over-correction: running every dispatch on the top tier is cost overkill for mechanical work (bulk transforms, classification sweeps). | BL-097 problem statement + rule 3 tier guide. | Design rationale (Karl directive). |
| 3 | **No acceptance step between gates.** Between phase gates, a delegated (subagent-built) change has **no required independent acceptance** — the implementing agent's own report is the only evidence its work is accepted on. Adversarial personas exist at ten named phase steps and the Phase-3 review manifest is gate-enforced, but nothing sits *between gates* per delegated change. | BL-100 "What is missing today" paragraph; the persona table in `templates/generated/claude-md.tmpl` (`### Agent Personas`); the review-manifest gate in `scripts/check-phase-gate.sh` + `scripts/lint-review-manifest.sh` + the repo-root `evaluation-prompts/` library. | Verified current-state. |
| 4 | **Fixed doctrine was the wrong answer.** BL-097/098/100 were originally logged as *fixed* rules to encode. Karl's 2026-07-20 decision REJECTED fixed doctrine: not every AI setup has multiple models, so a single hard-coded "top tier for X, mid for Y" policy is unenforceable and wrong for single-model operators. | Karl 2026-07-20 decision, recorded on BL-097. | Recorded decision. |

**What does not exist today (verified):** there is **no per-role model selection anywhere**
— `grep -rn 'operating_model\|operatingModel\|modelTier' scripts init.sh templates` returns
nothing, and the `### Multi-Agent Parallelism` and `### Agent Personas` sections of
`templates/generated/claude-md.tmpl` say nothing about model or tier. The trio's premise —
"choose who builds, then verify" — has no config, no schema, and no enforcement surface. This
design supplies all three.

**Why configurable, precisely:** the operator picks a **model per role** at setup (planner,
implementer, verifier, …); the framework then makes that choice **visible, auditable, and
rendered into the teaching surface**; a reconfigure path exists for "too expensive" (drop a
tier) or "not good enough" (raise a tier); and a **single-model** mode degrades the protocol
gracefully when only one model is available.

---

## §2 — Role taxonomy

The config keys on **roles**, not phase steps (phase steps are too fine — 10+ persona rows —
and would bloat the config; a coarse role set maps cleanly onto BL-097 rule 3's tier guide).

**Granularity decision:**

| Option | Keys | Pro | Con | Verdict |
|---|---|---|---|---|
| Coarse (3): plan / build / verify | 3 | Minimal config | Collapses research and mechanical work into "build" — loses the exact distinction BL-097 rule 3 draws | Rejected |
| **Roles (5): planner, implementer, verifier, investigator, mechanical** | 5 | One row per distinct tier posture in BL-097 rule 3; small enough to render inline | Slightly more setup surface | **Recommended** |
| Per-phase-step | 10+ | Maximal precision | Config bloat; duplicates the persona table; drifts against BL-092 modularization | Rejected |

**The five roles** (default tier posture mapped from BL-097 rule 3; "verifier ≥ implementer"
column from BL-097 rule 4 / BL-100 rule 5):

| Role | What it does | Default tier (BL-097 r3) | Verifier-≥-implementer applies? |
|---|---|---|---|
| **planner / architect** | Authors the junior-followable build plan (BL-098); architecture judgment; front-loads the decisions execution then conforms to. | **Top** — architecture judgment + plan authoring. | n/a (it *is* the front-loaded judgment) |
| **implementer** | Routine, well-specified construction from a plan slice; structured refactors under strong tests. | **Mid** default; **one tier up** for enforcement/gate/security code (BL-097 r5). | Its verifier must be ≥ its own tier and ≥ the work's blast radius. |
| **verifier / reviewer** | Fresh-context adversarial acceptance of delegated work; refutes, never confirms (BL-100). | **Top** for gate/enforcement blast radius (BL-100 r5); at least the implementer's tier otherwise. | **This is the constraint** — the verifier is the role the rule protects. |
| **investigator / researcher** | Bulk search, code archaeology, structured research; **fact-verification documents**. | **Mid** for search/archaeology; **top** for fact-verification documents (BL-097 r3). | Verified by whoever consumes the finding; low direct blast radius. |
| **mechanical** | Mechanical transforms, bulk renames, classification sweeps — no judgment. | **Small** (BL-097 r3). | Output is checked by the strong verifier of the change it feeds. |

**"Uncertain → one tier which way" (BL-097 r5)** is a per-role modifier, not a sixth role:
uncertain enforcement work rounds **up**, uncertain mechanical work rounds **down**. The
config stores the *chosen* tier; the rounding rule is doctrine in the rendered policy block
(§6), applied by the dispatching agent when a task straddles roles. **Likewise the investigator's
split posture** (BL-097 r3: *mid* for search/archaeology but *top* for fact-verification documents,
F10) cannot be a single config value — the config stores one tier for the `investigator` role and
the "top for fact-verification documents" exception lives as rendered doctrine (§6), exactly like
the r5 rounding.

---

## §3 — Config schema and location

**Where the chosen model lives** — decision table. The weights are the repo's own precedents:
the currency design's **dual-source ban** ("never a second manifest file"), the BL-109
currency/upgrade interaction, the reconfigure surface, and machine-checkability.

| Option | Single-source-of-truth | BL-109 currency interaction | Reconfigure surface | Machine-checkable | Verdict |
|---|---|---|---|---|---|
| **A block inside `.claude/manifest.json`** (`operatingModel`) | **Best** — same file as `enforcement_level`, `deployment`, `currency`; honors the dual-source ban outright | **Best** — `soif_currency_stamp` already assembles a versioned block into this file; the operating-model block is stamped the same way and can be currency-tracked for drift | `reconfigure-project.sh` already edits this manifest (`--enforcement-level`) | jq-readable; one file to hash | **Recommended** |
| A new `.claude/operating-model.json` | Violates the dual-source-ban spirit; adds a second config file to reason about and to keep in sync | Adds a *new* currency-tracked surface (another `files{}`/render-base concern) | New surface to teach reconfigure | Same | Rejected |
| Inside `.claude/tool-preferences.json` (`.context.*`) (F9) | Partial — a real config file that already holds project context (`.context.platform` / `.context.language`) and is read by `reconfigure-project.sh` — but it is the TOOL/context store, and the sibling policy field `enforcement_level` lives in the manifest, not here; putting policy here splits the two policy fields across two files | Not currency-tracked today | already read by `reconfigure-project.sh` | jq-readable | Rejected — keep the policy fields together; `tool-preferences.json` stays the context store |
| An intake-time `PROJECT_INTAKE.md` field | Not a storage location — it is a *setup mechanism* | n/a | n/a | Prose, not machine-readable | **Not a competitor** — it composes: the intake field is one way to *choose* (§4), rendered into option A at init. |

**Recommendation: a versioned `operatingModel` block inside `.claude/manifest.json`.** It sits
beside the existing `enforcement_level` field and the `currency` block, is stamped additively
at birth exactly as `soif_currency_stamp()` (in `scripts/lib/currency-manifest.sh`) stamps the
`currency` block via a jq-merge with atomic rename, and is edited in place by
`reconfigure-project.sh`. This is the same shape the framework already trusts for
`enforcement_level` (BL-030) — a single-source policy field, chosen at init, enforced,
reconfigurable — which is the closest living precedent to this entire feature.

**Representation of the model value — the F6 decision.** Provider-neutrality is a design
invariant: the framework **hardcodes no vendor's model ids**. That created a v1 contradiction —
if the block stores only opaque operator ids, an unattended init or a migration backfill has
*nothing* to write. Resolution:

| Option | Default/backfill writes | Rendered as | Verdict |
|---|---|---|---|
| Opaque operator ids only | *nothing* (no ids known) | — | Rejected — the v1 contradiction |
| **Tier tokens as declared-degraded values** (`tier:top` / `tier:mid` / `tier:small`) | the preset's per-role tier tokens | doctrine ("planner: use your top-tier model") + a session-start nudge to bind real ids | **Recommended** |
| Preset name only, `roles` unset-pending | preset; roles empty | nothing until bound | Rejected — renders nothing useful; adds a pending state everywhere |

**Recommendation: tier tokens are first-class values.** A role's `model` is either a **tier token**
(`tier:top` / `tier:mid` / `tier:small`) or a **concrete operator-supplied id**. Init and backfill
write the preset's tier tokens (needing zero knowledge of the operator's ids); the rendered CLAUDE.md
block is immediately useful as doctrine; a session-start nudge asks the operator to **bind** concrete
ids (a reconfigure that replaces tokens with ids) when they want the fully machine-checkable,
`.claude/agents`-pinned surface (§5-surface-4). This keeps the framework provider-neutral AND gives
every state a meaningful default.

**The JSON shape** (`model` is a tier token until bound, then a concrete id):

```json
"operatingModel": {
  "schemaVersion": 1,
  "chosenAt": "2026-07-24T18:00:00Z",
  "chosenVia": "init",
  "preset": "balanced",
  "singleModel": false,
  "modelsBound": false,
  "roles": {
    "planner":      { "model": "tier:top",   "effort": "high" },
    "implementer":  { "model": "tier:mid",   "effort": "medium" },
    "verifier":     { "model": "tier:top",   "effort": "high" },
    "investigator": { "model": "tier:mid",   "effort": "medium" },
    "mechanical":   { "model": "tier:small", "effort": "low" }
  }
}
```

- `schemaVersion` — mirrors `currency.schemaVersion`; lets a future migration bump the block.
- `chosenVia` — `init | reconfigure | backfill`; the provenance the audit row (§8) mirrors.
- `preset` — `always-best | balanced | single-model | custom` (§4); `custom` once any per-role
  override is applied.
- `singleModel` — the mode flag (§7): all five `model` values equal (see invariant).
- `modelsBound` — `false` while any value is a `tier:*` token; `true` once every role carries a
  concrete id. Drives whether the session-start nudge fires and whether the `.claude/agents`
  model-pinning of §5-surface-4 can render concrete ids.
- `roles.<role>.effort` — the harness's per-subagent effort token. **Verified harness enum** (per
  the Claude Code sub-agents frontmatter docs): `low | medium | high | xhigh | max`. The WP4 lint
  validates membership.

**Single-model invariant (machine-checkable):** `singleModel == true` **iff** all five role `model`
values are equal — true whether they are all the same tier token (`tier:top` ×5, the unbound
single-model default) or all the same concrete id (bound). The WP4 lint asserts the iff so the flag
cannot drift from the data it summarizes.

---

## §4 — Selection at setup

**Where the choice happens.** *Verified today:* `init.sh` accepts non-interactive flags and
scaffolds the manifest via `prepare_initial_state_for_commit()` — the **universal birth site**
(runs on every path, including `--no-remote-creation`; where `enforcement_level`,
`soloFrameworkCommit` (`# BL-110-PIN-UNIVERSAL`), and the `soif_currency_stamp` call already land).
The `--enforcement-level <no|light|strict>` init flag (default `strict`, `--confirm-pitfalls` to go
lower) is the verified precedent for a policy chosen at init. `scripts/intake-wizard.sh` fills
`PROJECT_INTAKE.md` interactively — but **(F2 correction)** it does **not** invoke
`reconfigure-project.sh` (its sole reference to that script is a `print_warn` telling the operator
to run it by hand), and there is **no** enforcement-level intake question. So the only verified
selection surfaces today are the **init flag** and the **reconfigure flag** (§8); reconfigure's own
header claim that it is "called by the intake wizard" is stale, and v1 laundered it.

*New wiring this design must build:* an `init.sh --operating-model <preset>` flag (+ per-role
`--model-<role>` overrides) is the primary selection surface, mirroring `--enforcement-level`. An
intake-wizard question is **optional new wiring**; if built, the wizard→manifest write path (wizard
answer → the `operatingModel` block via the same stamp call §4 adds to init) is itself new and must
be specified explicitly, not assumed from the wizard's current behaviour.

**What the operator is asked — presets, not raw per-role prompts** (a five-way model prompt is
setup friction; presets collapse it to one choice with an override escape hatch):

| Preset | planner | implementer | verifier | investigator | mechanical | When to pick |
|---|---|---|---|---|---|---|
| **always-best** | top | top | top | top | top | Cost is no object; maximum quality everywhere. |
| **balanced** *(the BL-097 rubric defaults)* | top | mid | top | mid | small | The recommended default — the BL-097 rule-3 tier mapping (F10: **not** verbatim — rule 3 also puts *fact-verification documents* at top, an investigator posture a single row cannot hold, so it lives as rendered doctrine, §2). |
| **single-model** | X | X | X | X | X | Only one model available (`singleModel:true`, §7). X = the one model — the deterministic pre-bind token `tier:top` for all five roles (R2-5), the operator's one concrete id once bound. |

Plus **per-role override**: any preset may be amended (`--model-implementer <id>` etc.),
flipping `preset` to `custom`. The override is where "one tier up for enforcement code" (BL-097
r5) is expressed when a project does mostly gate work.

**Recorded default if unattended (decision):**

| Option | Behavior on non-interactive init | Risk | Verdict |
|---|---|---|---|
| Default `always-best` | Top tier everywhere | Safe for quality, maximal cost — contradicts the cost motive (problem 2) | Rejected as default |
| **Default `balanced`, with planner+verifier pinned top regardless** | BL-097 defaults, but the two risk-bearing roles never silently drop below top | Cheap roles are mechanical/implementer only; risk is never silently cheapened | **Recommended** |
| Default `single-model` | Assumes one model | Wrong for multi-model operators; hides the choice | Rejected |

**Recommendation:** unattended default = **balanced**, with an invariant that **planner and
verifier never fall below top tier under any preset except explicit `single-model`**. This
mirrors `enforcement_level`'s "default to the safe maximum (`strict`), require an explicit
confirmed step to lower it" posture: the safe-by-default roles are the ones whose errors ship.
If the environment exposes exactly one model (operator-declared; see the deferred-probe open
question), init selects `single-model` and records `chosenVia:"init"` with `singleModel:true`. In
every unattended case the block is written with **tier tokens** (`modelsBound:false`, §3-F6) — init
never invents concrete ids; the session-start nudge later invites the operator to bind them.

---

## §5 — Enforcement surfaces (honest tiering)

This is the section the adversarial reviewer attacks hardest, and v1 got it wrong in the *cautious*
direction: it declared hard per-dispatch gating unavailable on the strength of one hook's Bash-only
header. Review-r1 (F4) proved the hook surface is matcher-**generic** and the harness routes each
dispatch through an interceptable, denyable **`Agent`** tool call. So the honest picture is richer
than v1 admitted: some per-dispatch enforcement IS mechanically available (fail-open by matcher inertness),
role→model pinning is harness-native, and only tier-*correctness* for unclassified dispatches stays advisory.
Claims are tiered **mechanical** / **auditable** / **advisory**.

| # | Surface | What it does | Tier | Precedent / anchor |
|---|---|---|---|---|
| 1 | **Marker-delimited policy block in the generated `CLAUDE.md`** | Init renders the chosen per-role models into a marker-delimited region (`SOIF-OPMODEL-OPEN`…`_CLOSE`, mirroring `scripts/lib/hook-templates.sh`'s `SOIF_PRECOMMIT_OPEN/_CLOSE` managed regions); reconfigure rewrites the region idempotently in place; a **new** lint asserts the region matches the manifest `operatingModel` and the §3 `singleModel` iff. | **Mechanical** (on the artifact; executing surface in §10-WP4) | **F3: no render-vs-manifest lint exists today** — `lint-review-manifest.sh` is a JSON-*shape* linter. Nearest real precedents: the currency `renderBases` sha-tracking and the freshness `render-base` check; the marker region is the `hook-templates.sh` managed-block precedent. |
| 2 | **Manifest machine-readable + surfaced at session start** | `operatingModel` is jq-readable; a SessionStart hook prints the chosen models once per session (silent otherwise) and, while `modelsBound:false`, nudges the operator to bind concrete ids. | **Mechanical** (surfacing) / **advisory** (adherence) | `init.sh` injects `session-version-check.sh` / `session-freshness-check.sh` into `.claude/settings.json` `.hooks.SessionStart`; `session-freshness-check.sh` (BL-109 S2) is the silent-when-current, fail-open, zero-network model. |
| 3 | **Dispatch-summary transparency + post-hoc resolved-model audit** | Every dispatch summary states the fleet's model/effort mix (BL-097 r6). A PostToolUse arm can record the harness's `resolvedModel` (v2.1.174) / `modelsUsed` (v2.1.212) so the *actual* model is auditable, not just the requested one. | **Auditable** (after the fact) | audit-artifact discipline mirrors `.claude/bypass-audit.json` row-writing; the `resolvedModel` / `modelsUsed` pin-and-anchor story lives once, canonically, in the §5.1 residual-limits note (R-269-7); the audit arm **feature-detects** the field at runtime (version-proof). |
| 4 | **Per-dispatch model gate (the F4 mechanism)** | A PreToolUse `Agent`-matcher gate and/or manifest-rendered `.claude/agents/` role pinning — **two adoptable mechanisms**, evaluated in the §5.1 decision table below. | **Mechanical** (fail-open by matcher inertness) + stated residual limits | Verified: the `Agent` matcher, `subagent_type`+`model` tool-input, deny via exit-2 / `permissionDecision` (Claude Code hooks docs); `init.sh`'s existing matcher-generic PreToolUse writes (Bash + Write/Edit). |
| 5 | **Actual per-dispatch choice inside the conversation** | The agent chooses per role per the rendered policy. | **Advisory** (but constrained by surface 4 wherever a role agent-type or the gate applies) | the persona table's fresh-context doctrine is followed the same advisory way today. |
| 6 | **Verifier-≥-implementer adherence (BL-097 r4 / BL-100 r5)** | The dispatching agent assigns the verifier at ≥ the work's blast radius. | **Advisory**, but its *output* (verifier verdict + double-mutation) is an **auditable** per-change artifact. | BL-100 rules 2–4. |

### §5.1 — Per-dispatch enforcement: the F4 decision table

The mechanism, verified against the Claude Code sub-agents + hooks docs: the dispatch tool is the
**`Agent`** tool — renamed from `Task` in **v2.1.63** (sub-agents.md: "In version 2.1.63, the Task tool
was renamed to Agent. Existing `Task(...)` references in settings and agent definitions still work as
aliases"; the alias is why `Task` prose recurs in later changelog entries — R-269-1 corrected the r2
"gradual transition" misread; no floor is load-bearing, see fail-open below); a
PreToolUse hook matches it exactly as `init.sh` already matches `Bash` and
`Write`/`Edit`; the hook receives tool-input JSON on stdin carrying `subagent_type` and an optional
`model`, and can **deny** the call (exit 2 or `permissionDecision:"deny"`). Subagent files
(`.claude/agents/*.md`) accept `model:` and `effort:` frontmatter. **On what ships (R2-1):** `init.sh`
ships no `.claude/agents/` to generated projects (verified); the framework repo itself carries one
standing agent — BL-146's `pr-reviewer` (`.claude/agents/pr-reviewer.md`, `model: fable`) — the
in-family precedent (b) generalizes. For a generated project both options are new capability.

| Option | Enforces mechanically | Residual limit | Decision |
|---|---|---|---|
| **(b) Manifest-rendered `.claude/agents/` role files** — one generated agent per role, each pinning `model:`/`effort:` from `operatingModel` (a concrete id once `modelsBound`, else doctrine + no hard pin) | A dispatch naming `subagent_type: <role>` is model-pinned **by the harness** — the role→model binding becomes a harness-enforced fact, no gate needed | Governs only dispatches that USE a shipped role agent-type; an ad-hoc `subagent_type` or a raw `model:` override is not covered by (b) alone | **ADOPT for v1** — low-risk (generated markdown), harness-native, and the most direct delivery of the recorded "the framework then ENFORCES" language |
| **(a) A PreToolUse `Agent`-matcher gate** — a shipped hook reading the dispatch tool-input, with the R2-3 semantics: while `modelsBound:false` deny a dispatch naming *no* model (BL-097 r1, "never inherit silently"); once `modelsBound:true` also deny a `model` outside the configured set | unbound: "every dispatch names a model"; bound: also "model ∈ the configured set" — **membership = exact-string over the bound set** (R2-3: the framework does NOT resolve aliases to ids — the id space is provider-specific and drifts; the operator binds whatever spelling they dispatch with, and the deny message names the set so a mismatch self-corrects) | Cannot classify an ad-hoc dispatch's ROLE/tier from `subagent_type`+`prompt` alone; the harness's `resolvedModel` (v2.1.174, per hooks.md; feature-detected at runtime) may differ from the requested `model`; the `Agent` matcher + `model` field are available from 2.1.63 (the documented rename, R-269-1) | **ADOPT for v1** — **fail-open is automatic via matcher inertness** (docs-confirmed with citations, R-269-8 — hooks-guide: "check that the matcher pattern exactly matches the tool name (case-sensitive)"; debug-your-config: "A misspelled tool name will also prevent the matcher from working"; an unmatched matcher simply never fires, so no runtime version compare is needed); full semantics in WP4b |

**Honest residual limits surviving both:** (i) tier-*correctness* for an unclassified/ad-hoc dispatch
— a gate enforces "a configured model," not "the right tier for this task" — stays advisory; (ii)
`resolvedModel`/`modelsUsed` mean the request-time gate sees the *requested* model, not the harness's
final resolution, so a **PostToolUse** audit of the actually-resolved model (surface 3) is the
complement; (iii) harness-version coverage — the gate/pinning need the `Agent` matcher (present from
2.1.63, the documented rename), but fail-open is free via matcher inertness (no runtime version compare). **R2-4/R3-1 note:**
`resolvedModel` (v2.1.174) / `modelsUsed` (v2.1.212) are documented in **hooks.md's `Agent`
`tool_response` schema table** — **changelog: zero mentions (verified); hooks.md: documents both** (the
r2 doubt was a hooks-docs search miss, adjudicated at r3). The audit arm still **feature-detects** the
field at runtime (version-proof) rather than hard-coding the name/version.

**Bottom line:** per-dispatch policy is partly mechanical (render+lint, `.claude/agents` pinning,
`Agent`-gate deny) with an honest advisory/auditable residue — v1's "impossible" was false.

---

## §6 — The policy payload (the three rule sets, edited into one protocol)

The payload is carried here in full so the build can lift it verbatim. It is **one protocol in
three movements**: plan-first → right-sized dispatch → adversarial acceptance. Where each lands
when built is a **build-plan pointer, not an edit** (no policy text lands in this WP).

### 6.1 Plan-first (BL-098)

**The junior-followable standard** — the strongest available model (planner role) writes, before
any above-trivial delegated build, a plan an execution agent can follow without re-deriving
judgment:
1. Exact surfaces: files + **grep-able marker/function citations** (never bare line numbers).
2. Step-by-step build order with contracts/interfaces stated, not implied.
3. The test list, first-class: each case's intent + its expected RED→GREEN mutation proof where
   enforcement code is touched.
4. Explicit done-criteria and known traps.
5. **Escalate-on-ambiguity, stated IN the plan:** an executor that hits a gap or contradiction
   STOPS and returns it to the planner — improvising around plan gaps is forbidden.

**Plan-lifecycle anti-bloat rules** (so plans do not negate their own savings):
1. **Sliced, not omnibus** — each executor ingests only its own work-package slice (target ≤ ~250 lines).
2. **Ephemeral by default** — the durable record is the PR body + backlog citation; a plan is
   committed only to cross a session boundary, then archived-with-stub on execution.
3. **Rewrite, don't accrete** — a revised plan replaces its predecessor; no append-only "Update:" stacks.
4. **Freshness** — grep-able markers only; executors verify anchors before editing; **any committed plan falls under BL-090's reference checker** (F5-restored).
5. **Bounded catch-up** — a fresh agent reads: scaffold/mothership CLAUDE.md + the single live handoff + its own slice. **The backlog is consulted by grep recipe, guides by section, history never** (BL-092/BL-093 enforce the fat ends of this) (F5-restored).

**Process wiring (BL-098, F5-restored):** the plan is authored by the top tier (BL-097 r3); **the
plan itself gets reviewed** — adversarial review for gate/enforcement work, and at minimum the work's
verifier checks **plan-conformance as a first-class target**; execution is dispatched per the BL-097
rubric; verifiers ≥ risk. A top-tier plan converts execution from judgment work into conformance
work — the cheapest thing to verify and the safest thing to delegate down-tier.

### 6.2 Right-sized dispatch (BL-097)

1. **Never inherit silently** — every dispatch names its model and effort explicitly.
2. **Assess per dispatch** on three axes: difficulty (judgment vs mechanical), blast radius
   (does an error ship? gate/enforcement code = high), downstream verification (strongly-verified
   work tolerates a cheaper implementer).
3. **Tier guide:** top for enforcement/gate logic, adversarial verification, architecture
   judgment, fact-verification docs; mid for routine well-specified implementation, doc drafting
   from verified sources, structured refactors under strong tests; small for mechanical
   transforms, bulk searches, classification sweeps.
4. **Verifiers ≥ implementers** whenever the work is risky.
5. **When uncertain:** one tier up for enforcement code, one tier down for mechanical work.
6. **Transparency:** the dispatch summary states the fleet's model/effort mix so the operator can veto.

### 6.3 Adversarial acceptance (BL-100)

1. Every delegated implementation above trivial is accepted only on an **independent adversarial
   verifier's verdict** — a fresh agent prompted to REFUTE, not confirm.
2. **Calibrated rubric:** `block` (any implementer claim contradicted by observation, or a
   known defect-class regression — silent-success / weak-test / non-hermetic / unregistered);
   `major_concerns` (vacuous assertion, spec miss, or the verifier's own mutation survives);
   `minor_concerns`; `approve` = "tried to refute and failed." **`major_concerns`+ blocks
   acceptance;** verifiers must not default to minor to be polite.
3. **Claim reproduction:** the verifier independently re-runs every suite, lint, and check the implementer cites.
4. **Double-mutation for enforcement/gate code:** the verifier designs and runs its OWN mutation,
   distinct from the implementer's documented proof; a surviving mutation = `major_concerns` minimum.
5. **Tiering per BL-097:** verifier tier ≥ the work's blast radius (gate code verifies at top tier
   even when the implementation safely ran mid tier).
6. **Separation:** verifiers never fix — findings return to the planner/implementer (the BL-098
   escalation loop), preserving reviewer independence.

### 6.4 Where each movement lives when built (pointers)

| Movement | Primary surface | Secondary |
|---|---|---|
| Plan-first (6.1) | `templates/generated/claude-md.tmpl` `### Multi-Agent Parallelism` (+ Superpowers `writing-plans` integration) | `docs/builders-guide.md` Build Loop; mothership `CLAUDE.md` |
| Right-sized dispatch (6.2) | `templates/generated/claude-md.tmpl` `### Multi-Agent Parallelism` (the rendered per-role block from §5-surface-1) | mothership `CLAUDE.md`; `docs/builders-guide.md` if it covers dispatch |
| Adversarial acceptance (6.3) | `templates/generated/claude-md.tmpl` `### Multi-Agent Parallelism` + `### Agent Personas` | `docs/builders-guide.md` Build Loop; mothership `CLAUDE.md` |

Coordinate with **BL-092** (template modularization) on the shared `claude-md.tmpl` surfaces —
if BL-092 moves the Multi-Agent section into a phase-scoped reference file first, these blocks
ride along (BL-097's sequencing note: compatible in either order).

---

## §7 — Single-model degradation

The recorded requirement: when only one model exists, the protocol must still run — via
**fresh-context, same-model verification**. `singleModel:true` (§3) switches it on.

**What weakens:** tier separation is gone. "Verifier ≥ implementer" and "top tier for gate
code" collapse to "same model everywhere" — a stronger model cannot check a weaker one because
there is only one.

**What survives (and is therefore what the degraded protocol leans on):**
- **Fresh context** — the verifier is a *new* agent with no inherited state or bias. This is the
  mechanism the persona table already ships: "Each persona starts fresh with no inherited context
  or bias" (`templates/generated/claude-md.tmpl` `### Agent Personas`). It is model-independent.
- **Refute-framing** — the verifier is prompted to disprove, not confirm (BL-100 r1).
- **Claim reproduction** — re-running every cited suite/lint/check is model-independent (BL-100 r3).
- **Double-mutation** — an independent mutation the verifier designs is model-independent proof of
  test strength (BL-100 r4); a survivor still blocks.

**How the flag switches the protocol:** when `singleModel:true`, the rendered policy block (§5
surface 1) drops the tier-comparison language and substitutes the degraded-mode wording: "one
model; separation is by *fresh context and refute-framing*, and acceptance still requires claim
reproduction + an independent double-mutation." The rubric and the block-on-`major_concerns`
threshold are unchanged — only the tier-separation clauses are rewritten. Multi-model projects
render the full tier language. One config flag, two rendered variants, no code-path fork in the
protocol itself. (The flag is the §3 machine-checkable invariant — all five `model` values equal —
so it holds identically whether the operator is on unbound tier tokens or bound concrete ids, F6.)

---

## §8 — Reconfigure / update path

The recorded escape hatch: "too expensive" (drop a tier) or "not good enough" (raise a tier).

**Surface (verified precedent):** `scripts/reconfigure-project.sh` today takes
`--field <field> --old <old> --new <new>` and dedicated flags like `--enforcement-level`, reads
project context from `.claude/tool-preferences.json::.context.*`, and self-protects with
`guard_not_in_framework` (so it cannot rewrite the framework repo's own config). **(F2: ignore the
script's stale header line claiming it is "called by the intake wizard" — verified false; the wizard
only `print_warn`s a suggestion to run it. Reconfigure is an operator-invoked surface.)**

**Recommended shape:** a dedicated `--operating-model <preset>` flag plus per-role
`--model-<role> <id>` overrides — **not** the generic `--field` path — because changing the
operating model is a *compound* change (up to five role rows + the `singleModel` invariant +
`preset` recomputation), which the single-field verb does not express cleanly. This mirrors why
`--enforcement-level` is its own flag rather than `--field enforcement_level`.

**What changes downstream:** the `operatingModel` block in `.claude/manifest.json` is rewritten
(atomic jq-merge), then the generated `CLAUDE.md` policy block (§5 surface 1) is regenerated
from it — the same regenerate-structural-files-on-config-change job reconfigure already performs.

**Audit trail (verified precedent):** append one row to `.claude/bypass-audit.json` with a new
`type:"operating_model_set"`, mirroring the `enforcement_level_set` row that `init.sh` seeds at
birth and that `reconfigure-project.sh --enforcement-level` appends on change. The row records
`chosenVia`, old preset, new preset, and timestamp. The ledger's per-row lifecycle and
atomic-append guarantees are documented in `docs/audit-log-lifecycle.md`; the taxonomy there
(`enforcement_level_set`, `escalation`, `claude_bypass_proposal`, …) is the family this new row
joins. "You can change the operating model; you cannot change it **through the reconfigure surface**
without the ledger recording it." **Honest residual (R-269-6):** only `reconfigure-project.sh` writes
the row — a direct out-of-band edit of `.claude/manifest.json` (with a hand-matched rendered region)
passes the WP4 lint, which checks region↔manifest *consistency*, not provenance, and leaves no ledger
row; commit review is the actual backstop, exactly as for `enforcement_level` today. Optional, decide
at WP6: a freshness **informational** crosscheck flagging an `operatingModel` block whose content has
no matching latest `operating_model_set` row.

**Adding a new row `type` is not free (F8):** `operating_model_set` is currently *out of schema* on
three surfaces that WP3 must amend in sync — the enum comment in `scripts/lib/bypass-audit.sh`, the
**T6 type-enum whitelist** in `tests/test-bl029-integration.sh` (an unknown type FAILS T6, verified),
and the row-types + per-enforcement-level tables in `docs/audit-log-lifecycle.md` (the row appears at
all three levels — `no` / `light` / `strict` — like `enforcement_level_set`, since an operating-model
change is orthogonal to the enforcement level).

---

## §9 — Migration and BL-109 interaction

Existing generated projects (Pantheon-era) have no `operatingModel` block. Two ways in.

**F1 correction:** the `currency` block is **not** a backfill precedent — `soif_currency_stamp` has
exactly one product call site (`init.sh` birth; re-stamping is explicitly out-of-scope). The real,
in-function precedent is the BL-030 `enforcement_level` backfill arm.

| Path | Mechanism | Pro | Con |
|---|---|---|---|
| **Upgrade backfill** | `_run_idempotent_backfill()` (in `scripts/upgrade-project.sh`; reachable via `--backfill-only`) grows an idempotent arm that stamps a default `operatingModel` block (tier tokens, `chosenVia:"backfill"`) if absent — modelled **exactly on the BL-030 `enforcement_level` arm already inside that function**, which stamps `deployment`/`poc_mode`/`enforcement_level` and appends an `enforcement_level_set` audit row (`source:"upgrade-backfill"`) when the field is missing. | Reuses proven, sentinel-guarded, idempotent machinery on the paths operators already invoke | Only reaches projects that upgrade/sync |
| **Currency detection flag** | `scripts/session-freshness-check.sh` (BL-109 Layer 1) adds an item that reports a missing `operatingModel` block, naming the backfill command. | Nudges dormant projects at session start; zero-network, silent-when-present | Detection only — it names the remediation, never applies it (the currency invariant) |

**Recommendation: both, in that order** — backfill is the primary acquisition path
(`_run_idempotent_backfill` stamps the `balanced` default with `chosenVia:"backfill"`);
currency detection is the **nudge** that surfaces the gap for projects that have not upgraded,
at the **informational** tier (a missing operating-model block is a feature gap, not an
enforcement-drift emergency — it should not block or nag like a stale gate script). This matches
BL-109's tiering: enforcement drift is loud, feature drift is informational.

---

## §10 — Build plan skeleton (ordered work packages)

Each WP is a future wave's slice; each states its test intent and marks what is **mutation-provable**
(the RED-under-neuter → GREEN-restored proof the repo requires for enforcement code). A future
session can plan directly from this list. Every WP goes through §6.3 adversarial acceptance.

- **WP1 — Schema + init stamp.** Add the `operatingModel` block (§3) and a
  `soif_operating_model_stamp`-style writer beside `soif_currency_stamp()`; call it from
  `prepare_initial_state_for_commit()`. *Tests:* birth-stamp present on every path
  (incl. `--no-remote-creation`); additive merge preserves every pre-existing field; jq-absent
  is a clean no-op. **Mutation-provable:** the additive-merge guard (break it → a sibling field
  is dropped → RED).
- **WP2 — Setup selection.** `init.sh --operating-model <preset>` + `--model-<role>` overrides +
  the intake-wizard question + preset→role resolution + the unattended default (§4) + the
  planner/verifier-pinned-top invariant + single-model detection. *Tests:* each preset resolves
  to the right five rows; unattended → `balanced`; single-model sets `singleModel:true` and equal
  models. **Mutation-provable:** the planner/verifier-top invariant (break it → a preset lets
  verifier drop below top → RED).
- **WP3 — Reconfigure path + audit schema.** `reconfigure-project.sh --operating-model` + per-role
  overrides + the `operating_model_set` audit row + `guard_not_in_framework` still holds. **Amend the
  audit schema on all three surfaces (F8):** the enum comment in `scripts/lib/bypass-audit.sh`, the T6
  whitelist in `tests/test-bl029-integration.sh`, and `docs/audit-log-lifecycle.md` (row-types +
  per-level tables, at all three levels). *Tests:* the manifest block is rewritten atomically with preset/`singleModel` recomputation; audit row
  appended with correct provenance (the CLAUDE.md marker-region regeneration is **WP4's** deliverable/F7c
  and is asserted there — R-269-3); T6 accepts the new type and still rejects
  an unknown one; framework-repo self-run refused. **Mutation-provable:** the audit-row append (suppress
  it → change leaves no ledger trace → RED) AND the T6 whitelist (drop the new type from the whitelist →
  a real `operating_model_set` row → RED).
- **WP4 — Template render + marker block + the NEW render-vs-manifest lint.** Render the per-role models
  into a **marker-delimited region** (`SOIF-OPMODEL-OPEN`…`_CLOSE`, the `hook-templates.sh` managed-block
  precedent) inside `claude-md.tmpl` `### Multi-Agent Parallelism` / `### Agent Personas` — both
  multi-model and single-model variants (§7), and both the doctrine wording (unbound tier tokens) and
  concrete-id wording (bound). Teach the A1 render function `soif_render_claude_md`
  (`scripts/lib/render-project-docs.sh`) the new placeholders and grow the **fixed argument list** at its
  call site in `scripts/lib/plan-staging.sh` (F7b — so the BL-109 currency A1 render legs stay
  placeholder-free, honouring `# BL-109-PLAN-A1PLACEHOLDER`). Build the **NEW render-vs-manifest lint**
  (F3 — none exists today); its **executing surface is a `pre-commit-gate.sh` arm** (F7a — verified
  precedent: `lint-counter-antipattern` and `lint-backlog-references` already run inside
  `pre-commit-gate.sh`), asserting the marker region matches the manifest `operatingModel` and the
  `singleModel`↔equal-models iff. Reconfigure rewrites the region idempotently in place (F7c).
  **Manifest wins (F7d):** any `PROJECT_INTAKE.md` prose echo is advisory, never read by a gate; a
  reconfigure regenerates the region and marks the prose echo possibly-stale. *Tests:* both variants
  render; the lint fails on a hand-edited region↔manifest mismatch; a reconfigure-driven field change
  rewrites the region in place (moved from WP3 — R-269-3); the A1 legs carry no surviving placeholder. **Mutation-provable:** the render-vs-manifest lint (edit the region off the manifest → RED).
- **WP4a — Manifest-rendered role-agent files (F4 mechanism b).** Render one `.claude/agents/<role>.md`
  per role from `operatingModel`, pinning `model:`/`effort:` frontmatter (a concrete id once
  `modelsBound`, else the role doctrine as the agent description with no hard `model:` pin); init renders
  them, reconfigure regenerates them, and they ship downstream under the BL-088 source-closure discipline
  (the framework's own `.claude/agents/pr-reviewer.md`, BL-146, is the in-repo exemplar of the frontmatter
  pin). *Tests:* bound vs unbound variants render; a role model change regenerates the file's `model:`; the
  closure check sees the new shipped files. **Mutation-provable:** the render (change a role's manifest model
  → the agent file's `model:` must change → a pinned test RED).
- **WP4b — PreToolUse `Agent`-matcher gate (F4 mechanism a).** A shipped hook registered under a PreToolUse
  `Agent` matcher in `.claude/settings.json` (the same matcher-generic jq-injection init already does for
  Bash and Write/Edit), shipped downstream with BL-088 source-closure. **Semantics (R2-3):** while
  `modelsBound:false` deny only a dispatch that names no model (BL-097 r1); once `modelsBound:true` also
  deny a `model` not in the bound set (exact-string membership, no alias resolution). **Strict composition
  (R3-2):** the names-no-model deny applies EVEN to a role-typed dispatch (`subagent_type:<role>` with no
  explicit `model` param) — the shipped role file's frontmatter pin is defense-in-depth, not an exemption
  (BL-097 r1 compels naming the model at the dispatch site); this is what the tests below already encode.
  **Fail-open by matcher inertness** — on a harness whose dispatch tool is not named `Agent` the hook never
  fires, so no version compare. *Tests:* a model-less dispatch is denied (including a role-typed one with no
  `model`); the unbound state denies ONLY the model-less case; a bound out-of-set model is denied;
  hermetic inertness proxies (R-269-4): the settings registration's matcher string is exactly `Agent`,
  and the hook script itself exits 0 (no deny) on any stdin whose `tool_name` is not `Agent` — actual
  non-firing on a non-`Agent` harness is harness behavior, attested by those two properties, not
  directly testable here. **Mutation-provable:** neuter
  the deny path → a model-less dispatch passes → RED.
- **WP5 — Session-start surface.** A `session-operating-model-check.sh` (or an arm folded into
  `session-freshness-check.sh`) that prints the chosen models once, silent otherwise, fail-open
  exit 0, zero-network — and **reports the gate's registration state in one word (configured / not-configured)**, read from
  `.claude/settings.json` — a SessionStart script cannot probe the harness's dispatch-tool naming, so
  registration is the honest attestable fact (R-269-5, downgrading R2-6's active/inert; harness-level
  inertness stays fail-open-by-matcher and is surfaced post-hoc by the surface-3 audit when it fires).
  *Tests:* silent when adherent; one compact line on first surface; the gate-state word reflects the
  settings.json registration; a forced internal crash still exits 0.
- **WP6 — Migration backfill + upgrade re-render + freshness item.** The `_run_idempotent_backfill()`
  arm modelled on the BL-030 `enforcement_level` arm (§9); the upgrade A1 re-render carries the new
  placeholders through the currency `--plan` legs (F7b, shared with WP4); and a currency-detection
  **informational** item in `session-freshness-check.sh` reports a missing `operatingModel` block —
  which **grows the freshness `check` enum**
  (`local-edit|framework|framework-drift|orphan|hook|render-base|cdf`) by one member (F11: a
  machine-block contract change; the S5 machine-block lint — currency-design slice S5, **not yet
  built**; today the fence's only consumers are the freshness scripts/tests — must include the new
  member when it lands; anchor: the MACHINE-BLOCK CONTRACT comment in `session-freshness-check.sh` —
  R-269-2). *Tests:* backfill is idempotent
  (second run a no-op); a project missing the block gets the tier-token `balanced` default with
  `chosenVia:"backfill"`; detection reports the gap at the informational tier and names the command;
  the freshness machine block still validates with the new `check` value.
- **WP7 — Docs.** The policy payload (§6) lands in `docs/builders-guide.md` Build Loop, the
  mothership `CLAUDE.md`, and the user guide; coordinate with BL-092 on shared surfaces. *Tests:*
  `scripts/lint-doc-anchors.sh` + `scripts/lint-backlog-references.sh` clean; no new dead refs.

**Sequencing:** WP1 → WP2/WP3 (depend on WP1's schema) → WP4/WP4a/WP4b/WP5 (depend on the block
existing; WP4a renders role agents, WP4b gates dispatch) → WP6 → WP7. WP4's lint and WP4b's gate are
the linchpins — the two *mechanical* ties between the config and behaviour, so both get top-tier
implementation and a double-mutation verify.

---

## §11 — Non-goals and rejected alternatives

- **Fixed doctrine** (a single hard-coded tier policy) — **rejected** by Karl 2026-07-20: it is
  wrong for single-model operators and unenforceable. The whole design exists because doctrine
  was rejected for configurability.
- **Per-task dynamic model routing at runtime** (a router that picks a model per task on the fly)
  — **out of scope.** This design configures a *policy per role*, chosen at setup and enforced by
  transparency + audit; it does not build a runtime dispatcher that reassigns models mid-flight.
  That is a different, heavier system and is not what the trio decision asked for.
- **Enforcement pretensions beyond §5's honest list** — **bounded, not disclaimed wholesale (F4).**
  §5.1 adopts an `Agent`-matcher gate (fail-open by matcher inertness) and harness-native `.claude/agents` role pinning:
  those are legitimate mechanical enforcement, not oversell. What remains out of reach and must not be
  claimed: **tier-*correctness* for an unclassified/ad-hoc dispatch** (a gate enforces "a configured
  model," never "the right tier for this specific task"), and **preventing** a post-request
  `resolvedModel` swap (auditable, not preventable). A PR claiming either is overselling; a PR shipping
  the §5.1 gate is not.
- **A second config file** — rejected (§3): the dual-source ban puts the block in the existing manifest.
- **Provider-specific model ids in the framework** — rejected: the framework stores opaque
  operator-supplied ids and hardcodes none (§3 provider-neutrality invariant).

---

## Self-review pass (fresh-eyes checklist)

- **Every entry requirement covered?** Role taxonomy (§2), config schema + location (§3),
  selection at setup (§4), enforcement surfaces (§5), the three rule sets in full (§6),
  single-model degradation (§7), reconfigure path (§8), migration + BL-109 (§9), build plan
  (§10), non-goals + rejected alternatives (§11) — all present, plus §0 changelog and §1 evidence.
- **Every "exists today" claim anchored and re-verified (v1.2)?** Yes — F1/F2/F3 (v1) and R2-1 (v1.1)
  were all header-trust/grep-miss defects, so every anchor is re-grepped. Corrections carried:
  `soif_currency_stamp` = one call site (F1); the intake wizard only `print_warn`s reconfigure (F2);
  `lint-review-manifest.sh` is a shape linter (F3); `.claude/agents/` is NOT empty in the framework repo —
  `pr-reviewer.md`/BL-146 exists (R2-1), though `init.sh` ships none downstream. Re-verified in-repo:
  `prepare_initial_state_for_commit()`, `_run_idempotent_backfill()`'s BL-030 arm, `guard_not_in_framework`,
  the matcher-generic PreToolUse writes (Bash + Write/Edit), `session-freshness-check.sh`, the
  `bypass-audit.sh` enum + `test-bl029-integration.sh` T6 whitelist + `docs/audit-log-lifecycle.md` tables,
  `hook-templates.sh` `SOIF_*_OPEN/_CLOSE`, `soif_render_claude_md`, `.claude/agents/pr-reviewer.md`
  (`model: fable`). Harness facts vs the Claude Code docs: matcher-inertness fail-open confirmed, citations at §5.1
  (R-269-8); the `Task`→`Agent` rename documented at exactly 2.1.63 (R-269-1); the
  resolvedModel/modelsUsed pin story is canonical at §5.1 (R-269-7) — feature-detected at runtime.
- **Any unresolved placeholders?** None. Every underdetermined choice is a decision table with one
  recommendation and stated alternatives (granularity §2; storage §3; id representation §3-F6; unattended
  default §4; per-dispatch enforcement §5.1; reconfigure verb §8; migration path §9).
- **Honesty on enforcement?** §5/§5.1 tier every surface mechanical/auditable/advisory. v1.1 corrects
  v1's *under*-claim: per-dispatch gating IS partly mechanical (an `Agent`-matcher gate, fail-open by
  matcher inertness, + harness-native role pinning); the honest residue (tier-correctness for ad-hoc
  dispatch; requested-vs-resolved model) is stated as advisory/auditable — not hidden, not overclaimed.

## Open questions flagged for the adversarial reviewer

1. **Effort vocabulary — now partly answered (F4).** The verified harness enum is
   `low|medium|high|xhigh|max`. Open sub-question: store the value opaque, or validate it against that
   enum in the WP4 lint? Recommended: validate, but keep the enum data-driven (one constant) so a harness
   addition is a one-line change, not a schema migration.
2. **Planner/verifier-top invariant vs `always-best`-only operators.** The §4 invariant pins
   planner+verifier to top under every non-single-model preset. Is that too paternalistic for a
   cost-obsessed operator who explicitly wants a mid-tier verifier? Recommended: keep the pin,
   allow an explicit per-role override to break it (with the override surfaced in the dispatch
   summary) — so the escape exists but is never silent.
3. **Single-model detection.** §4 assumes the operator declares single-model or a future harness
   probe reports it. There is no reliable model-availability probe today — should `single-model`
   be operator-declared only for v1? Recommended yes (declared-only), probe deferred.
4. **BL-092 ordering.** If BL-092 modularizes `claude-md.tmpl` before this builds, WP4's render
   target moves. Non-blocking (BL-097's sequencing note), but the two waves should coordinate the
   shared surface rather than race it.
5. **A configured model id vanishes upstream (F11).** If a bound concrete id is retired by the
   provider, should the framework silently substitute the nearest tier sibling, escalate to the operator,
   or record an audit row and fall back to the tier token? Recommended: fall back to the tier token
   (`modelsBound` flips false for that role), surface it at session start, and write an audit row — never
   silently substitute a different concrete model.
6. **The freshness `check` enum grows (F11).** WP6 adds one member to
   `local-edit|framework|framework-drift|orphan|hook|render-base|cdf`. That enum is a machine-block
   contract (the `soif-freshness` fence; per `session-freshness-check.sh`'s MACHINE-BLOCK CONTRACT
   comment the currency-slice **S5 lint will pin it once built — S5 does not exist yet**; today's only
   consumers are the freshness scripts/tests) — flag the growth as a deliberate contract change so the
   future lint and every consumer move in the same wave, not silently (R-269-2).
7. **Harness audit-field versions — RESOLVED (r3).** review-r2 asked to pin `resolvedModel`@v2.1.174 /
   `modelsUsed`@v2.1.212; I declined pending a verifiable anchor (the changelog had zero mentions — verified).
   **r3 adjudication:** both are documented in **hooks.md's `Agent` `tool_response` schema table** — my r2
   hooks-docs search was the miss. Pins restored (§5.1/§5-s3); the runtime mechanism stays **feature-detection**
   (version-proof; a doc-annotation anchor is weak). The refuse-to-launder step was ruled correct process. Closed.
