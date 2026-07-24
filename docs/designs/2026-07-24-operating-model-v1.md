# The Configurable Operating Model — design v1 (normative-once-reviewed for the build)

**Status:** v1, 2026-07-24. **Awaiting adversarial design review.** The build of the
BL-097/098/100 delegation trio is GATED on this doc passing that review — the same
adversarial bar code faces (the currency-system design was BLOCKED once before it
passed; expect the same here). No product code, template edit, or policy text lands
anywhere from this work package: this is a design doc only. Anchors and counts are
verified 2026-07-24 and drift — prefer the grep recipes over quoted line numbers, and
re-verify every anchor before editing (CLAUDE.md citation rule).

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

This section is the currency-doc convention: on first adversarial review, each finding maps
here to the section it amended (r1: `B1→§X · M3→§Y · …`), and the status line above flips to
`v1.1, post-review`. v1 carries **no amendments yet** — it is the pre-review baseline. The
changelog exists now so the mapping has a home the moment review lands; it is not a placeholder.

---

## §1 — Problem and evidence

Four failures motivate this work. Each is anchored; where a claim is an operational record
without a git artifact, that is stated (honesty about evidence tier is itself a review
criterion the currency design established).

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
(§6), applied by the dispatching agent when a task straddles roles.

---

## §3 — Config schema and location

**Where the chosen model lives** — decision table. The weights are the repo's own precedents:
the currency design's **dual-source ban** ("never a second manifest file"), the BL-109
currency/upgrade interaction, the reconfigure surface, and machine-checkability.

| Option | Single-source-of-truth | BL-109 currency interaction | Reconfigure surface | Machine-checkable | Verdict |
|---|---|---|---|---|---|
| **A block inside `.claude/manifest.json`** (`operatingModel`) | **Best** — same file as `enforcement_level`, `deployment`, `currency`; honors the dual-source ban outright | **Best** — `soif_currency_stamp` already assembles a versioned block into this file; the operating-model block is stamped the same way and can be currency-tracked for drift | `reconfigure-project.sh` already edits this manifest (`--enforcement-level`) | jq-readable; one file to hash | **Recommended** |
| A new `.claude/operating-model.json` | Violates the dual-source-ban spirit; adds a second config file to reason about and to keep in sync | Adds a *new* currency-tracked surface (another `files{}`/render-base concern) | New surface to teach reconfigure | Same | Rejected |
| An intake-time `PROJECT_INTAKE.md` field | Not a storage location — it is a *setup mechanism* | n/a | n/a | Prose, not machine-readable | **Not a competitor** — it composes: the intake field is one way to *choose* (§4), rendered into option A at init. |

**Recommendation: a versioned `operatingModel` block inside `.claude/manifest.json`.** It sits
beside the existing `enforcement_level` field and the `currency` block, is stamped additively
at birth exactly as `soif_currency_stamp()` (in `scripts/lib/currency-manifest.sh`) stamps the
`currency` block via a jq-merge with atomic rename, and is edited in place by
`reconfigure-project.sh`. This is the same shape the framework already trusts for
`enforcement_level` (BL-030) — a single-source policy field, chosen at init, enforced,
reconfigurable — which is the closest living precedent to this entire feature.

**The JSON shape** (roles → `{model, effort}`, plus `schemaVersion`, provenance, preset, and
the `singleModel` flag). **Provider-neutrality is a design invariant:** the framework stores
**opaque, operator-supplied model-id strings** and **hardcodes no vendor's ids** — presets map
abstract tiers (top/mid/small) onto whatever concrete models the operator declares they have.
The example below uses tier placeholders precisely to keep the schema honest and neutral:

```json
"operatingModel": {
  "schemaVersion": 1,
  "chosenAt": "2026-07-24T18:00:00Z",
  "chosenVia": "init",
  "preset": "balanced",
  "singleModel": false,
  "roles": {
    "planner":      { "model": "<operator top-tier model id>",  "effort": "high" },
    "implementer":  { "model": "<operator mid-tier model id>",  "effort": "medium" },
    "verifier":     { "model": "<operator top-tier model id>",  "effort": "high" },
    "investigator": { "model": "<operator mid-tier model id>",  "effort": "medium" },
    "mechanical":   { "model": "<operator small-tier model id>", "effort": "low" }
  }
}
```

- `schemaVersion` — mirrors `currency.schemaVersion`; lets `_run_idempotent_backfill` and
  currency detection migrate old blocks.
- `chosenVia` — `init | reconfigure | backfill`; the provenance the audit row (§8) mirrors.
- `preset` — `always-best | balanced | single-model | custom` (§4); `custom` once any per-role
  override is applied.
- `singleModel` — the mode flag (§7). When `true`, all five `model` values are identical and
  the degradation protocol is active.
- `roles.<role>.effort` — the harness's reasoning-effort token (illustrated `low/medium/high`);
  stored opaque, like `model`.

**Single-model invariant (machine-checkable):** `singleModel == true` **iff** all five role
`model` values are equal. A lint (§5, §10-WP4) asserts this so the flag cannot drift from the
data it summarizes.

---

## §4 — Selection at setup

**Where the choice happens (verified surfaces):** `init.sh` accepts non-interactive flags and
scaffolds the manifest via `prepare_initial_state_for_commit()` — the **universal birth site**
(it runs on every path, including `--no-remote-creation`; it is where `enforcement_level`,
`soloFrameworkCommit` (`# BL-110-PIN-UNIVERSAL`), and the `soif_currency_stamp` call already
land). `scripts/intake-wizard.sh` is the interactive wrapper (it fills `PROJECT_INTAKE.md` and
triggers `reconfigure-project.sh` on field change). The operating-model choice is added at both:
an `init.sh --operating-model <preset>` flag (+ per-role `--model-<role>` overrides) and an
intake-wizard question — mirroring exactly how `--enforcement-level <no|light|strict>` is
selected today (default `strict`, `--confirm-pitfalls` required to go lower).

**What the operator is asked — presets, not raw per-role prompts** (a five-way model prompt is
setup friction; presets collapse it to one choice with an override escape hatch):

| Preset | planner | implementer | verifier | investigator | mechanical | When to pick |
|---|---|---|---|---|---|---|
| **always-best** | top | top | top | top | top | Cost is no object; maximum quality everywhere. |
| **balanced** *(the BL-097 rubric defaults)* | top | mid | top | mid | small | The recommended default — matches BL-097 rule 3 verbatim. |
| **single-model** | X | X | X | X | X | Only one model available (`singleModel:true`, §7). X = that model. |

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
If the environment exposes exactly one model (operator declares it, or a future harness probe
reports it), init selects `single-model` and records `chosenVia:"init"` with `singleModel:true`.

---

## §5 — Enforcement surfaces (honest tiering)

This is the section the adversarial reviewer will attack hardest, so it is deliberately
conservative. **Dispatch happens inside an agent conversation; the framework cannot mechanically
gate a decision the harness does not route through a hook it owns.** Claims are tiered
**mechanical** (a script blocks/asserts), **auditable** (an artifact records it after the fact),
or **advisory** (doctrine the agent is asked to follow). Advisory items are LABELED advisory.

| # | Surface | What it does | Tier | Precedent / anchor |
|---|---|---|---|---|
| 1 | **Config-derived policy block in the generated `CLAUDE.md`** | The `### Multi-Agent Parallelism` / `### Agent Personas` sections render the chosen per-role models from the manifest. A lint asserts the rendered block matches `operatingModel` (and the `singleModel` invariant of §3). | **Mechanical** (on the artifact) | The currency design's "machine block whose format is a lint-checked contract"; `scripts/lint-review-manifest.sh` is the existing render-vs-manifest lint precedent. |
| 2 | **Manifest is machine-readable + surfaced at session start** | `operatingModel` is jq-readable; a SessionStart hook prints the chosen models once per session (silent otherwise). | **Mechanical** (surfacing) / **advisory** (adherence) | `init.sh` injects `session-version-check.sh` / `session-freshness-check.sh` into `.claude/settings.json` `.hooks.SessionStart`; `session-freshness-check.sh` (BL-109 S2) is the silent-when-current, fail-open, zero-network model to copy. |
| 3 | **Dispatch-summary transparency (BL-097 r6)** | Every dispatch summary states the fleet's model/effort mix, landing in the session/PR record. | **Auditable** (after the fact) | New requirement; audit-artifact discipline mirrors `.claude/bypass-audit.json` row-writing. |
| 4 | **What a PreToolUse hook can and cannot see** | The shipped hook `scripts/pre-commit-gate.sh` is "registered as a PreToolUse hook on Bash tool calls" and reads tool-input JSON on stdin. A **subagent dispatch is not a Bash tool call**, and the chosen model/effort is not a field the framework can rely on the harness exposing to a hook. So **hard pre-dispatch enforcement of per-role model choice is NOT available.** | **Honest non-capability** | `scripts/pre-commit-gate.sh` header ("Registered as a PreToolUse hook on Bash tool calls. Input: … JSON on stdin"). |
| 5 | **Actual per-dispatch model choice inside the conversation** | The agent chooses per role per the rendered policy. | **Advisory** | The persona table's fresh-context doctrine is followed the same advisory way today. |
| 6 | **Verifier-≥-implementer adherence (BL-097 r4 / BL-100 r5)** | The dispatching agent assigns the verifier at ≥ the work's blast radius. | **Advisory**, but its *output* (the verifier verdict + double-mutation, BL-100 r4) is an **auditable** artifact per change. | BL-100 rules 2–4. |

**The honest summary:** the mechanical layer enforces that the *policy is chosen, recorded,
rendered, internally consistent, and surfaced* — not that any given dispatch obeys it. Obedience
is advisory, backed by an auditable dispatch summary and an auditable verifier verdict. This is
the same enforcement ceiling the currency design accepted for Class-A files ("mechanical
verification proves absence-of-catastrophe, not correctness") and that the framework accepts for
its whole between-gate agent behavior ("you can route around the block, you cannot route around
the audit"). **Anyone who claims hard per-dispatch model gating is overselling — flag it in review.**

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
4. **Freshness** — grep-able markers only; executors verify anchors before editing.
5. **Bounded catch-up** — a fresh agent reads: scaffold/mothership CLAUDE.md + the single live handoff + its own slice.

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
protocol itself.

---

## §8 — Reconfigure / update path

The recorded escape hatch: "too expensive" (drop a tier) or "not good enough" (raise a tier).

**Surface (verified precedent):** `scripts/reconfigure-project.sh` today takes
`--field <field> --old <old> --new <new>` and dedicated flags like `--enforcement-level`, is
"called by the intake wizard when platform, language, track, or deployment changes," reads
project context from `.claude/tool-preferences.json::.context.*`, and self-protects with
`guard_not_in_framework` (so it cannot rewrite the framework repo's own config).

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
joins. "You can change the operating model; you cannot change it without the ledger recording it."

---

## §9 — Migration and BL-109 interaction

Existing generated projects (Pantheon-era) have no `operatingModel` block. Two ways in:

| Path | Mechanism | Pro | Con |
|---|---|---|---|
| **Upgrade backfill** | `_run_idempotent_backfill()` (in `scripts/upgrade-project.sh`; reachable via `--backfill-only`) grows an idempotent arm that stamps a default `operatingModel` block if absent — the same idempotent pattern that backfills the `currency` block and that migrated `enforcement_level` for pre-BL-030 projects. | Reuses proven, sentinel-guarded, idempotent machinery; runs on the paths operators already invoke | Only reaches projects that upgrade/sync |
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
- **WP3 — Reconfigure path.** `reconfigure-project.sh --operating-model` + per-role overrides +
  the `operating_model_set` audit row + `guard_not_in_framework` still holds. *Tests:* field
  change rewrites the block and regenerates the CLAUDE.md policy block; audit row appended with
  correct provenance; framework-repo self-run refused. **Mutation-provable:** the audit-row append
  (suppress it → change leaves no ledger trace → RED).
- **WP4 — Template render + lint contract.** Render the per-role block into `claude-md.tmpl`
  `### Multi-Agent Parallelism` / `### Agent Personas` (both multi-model and single-model
  variants, §7); a lint asserts rendered-block == manifest and the `singleModel`↔equal-models
  invariant (§3). *Tests:* both variants render; the lint fails on a hand-edited mismatch.
  **Mutation-provable:** the render-vs-manifest lint (edit the rendered block off the manifest → RED).
- **WP5 — Session-start surface.** A `session-operating-model-check.sh` (or an arm folded into
  `session-freshness-check.sh`) that prints the chosen models once, silent otherwise, fail-open
  exit 0, zero-network. *Tests:* silent when adherent; one compact line on first surface; a forced
  internal crash still exits 0.
- **WP6 — Migration backfill.** The `_run_idempotent_backfill()` arm + the currency-detection
  informational item (§9). *Tests:* backfill is idempotent (second run is a no-op); a project
  missing the block gets the `balanced` default with `chosenVia:"backfill"`; detection reports the
  gap at the informational tier and names the command.
- **WP7 — Docs.** The policy payload (§6) lands in `docs/builders-guide.md` Build Loop, the
  mothership `CLAUDE.md`, and the user guide; coordinate with BL-092 on shared surfaces. *Tests:*
  `scripts/lint-doc-anchors.sh` + `scripts/lint-backlog-references.sh` clean; no new dead refs.

**Sequencing:** WP1 → WP2/WP3 (both depend on WP1's schema) → WP4/WP5 (depend on the block
existing) → WP6 → WP7. WP4's lint is the linchpin — it is the only *mechanical* tie between the
config and the teaching surface, so it gets top-tier implementation and a double-mutation verify.

---

## §11 — Non-goals and rejected alternatives

- **Fixed doctrine** (a single hard-coded tier policy) — **rejected** by Karl 2026-07-20: it is
  wrong for single-model operators and unenforceable. The whole design exists because doctrine
  was rejected for configurability.
- **Per-task dynamic model routing at runtime** (a router that picks a model per task on the fly)
  — **out of scope.** This design configures a *policy per role*, chosen at setup and enforced by
  transparency + audit; it does not build a runtime dispatcher that reassigns models mid-flight.
  That is a different, heavier system and is not what the trio decision asked for.
- **Enforcement pretensions beyond §5's honest list** — **explicitly disclaimed.** No hard
  pre-dispatch gating of model choice is claimed or promised; §5 is the ceiling. Any future PR
  that asserts more is overselling.
- **A second config file** — rejected (§3): the dual-source ban puts the block in the existing manifest.
- **Provider-specific model ids in the framework** — rejected: the framework stores opaque
  operator-supplied ids and hardcodes none (§3 provider-neutrality invariant).

---

## Self-review pass (fresh-eyes checklist)

- **Every entry requirement covered?** Role taxonomy (§2), config schema + location (§3),
  selection at setup (§4), enforcement surfaces (§5), the three rule sets in full (§6),
  single-model degradation (§7), reconfigure path (§8), migration + BL-109 (§9), build plan
  (§10), non-goals + rejected alternatives (§11) — all present, plus §0 changelog and §1 evidence.
- **Every "exists today" claim anchored and verified?** `prepare_initial_state_for_commit()`,
  `soif_currency_stamp()` + `# BL-109-CURRENCY`, `# BL-110-PIN-UNIVERSAL`, `enforcement_level`
  seed, `.claude/bypass-audit.json` + `enforcement_level_set` + `docs/audit-log-lifecycle.md`,
  `reconfigure-project.sh` + `guard_not_in_framework`, `intake-wizard.sh`, the SessionStart
  injection in `init.sh`, `session-freshness-check.sh`, `pre-commit-gate.sh` PreToolUse/Bash
  scope, the `claude-md.tmpl` `### Multi-Agent Parallelism` / `### Agent Personas` sections and
  their "starts fresh" line, `evaluation-prompts/` + `lint-review-manifest.sh`,
  `_run_idempotent_backfill()` + `--backfill-only`, `--enforcement-level` — each was grep-verified
  in the repo on 2026-07-24. The "no per-role model selection exists" claim was verified by a
  negative grep.
- **Any unresolved placeholders?** None. Every underdetermined choice is a decision table with
  one recommendation and stated alternatives (granularity §2; storage §3; unattended default §4;
  reconfigure verb §8; migration path §9).
- **Honesty on enforcement?** §5 tiers every surface mechanical/auditable/advisory and states the
  non-capability (no hard per-dispatch gating) outright, inviting the reviewer to flag any oversell.

## Open questions flagged for the adversarial reviewer

1. **Effort vocabulary.** The schema stores `effort` as an opaque token (illustrated
   `low/medium/high`). Is a fixed enum wanted, or must it stay free-form to track harness
   changes? Recommended free-form; flagged because it affects the WP4 lint.
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
