# The severable-module contract (M1–M5)

**Status:** normative. Transcribed from
[designs/2026-08-02-brownfield-adoption-v1.md](designs/2026-08-02-brownfield-adoption-v1.md)
§3.3, where the rules were authored as a proposal co-owned with the delta
track. This page is the standing version: it binds **every severable module in
this repository**, present and future.

A severable module is one that could be lifted out with a `git mv` rather than a
refactor. The property is easy to state and easy to lose — nobody decides to
fuse a module into the framework; someone adds one convenience call on a Tuesday
and the property is gone with no test failing. These five rules exist so that
edit is a red check instead of a silent regression.

**Modules in scope**

| Module | Directory | Entry script | Zero-dependency (M5)? | Enforcing lint |
|---|---|---|---|---|
| Post-MVP delta track | `scripts/lib/` (flat `delta-*.sh` set) | `scripts/delta.sh` | no | `scripts/lint-delta-boundary.sh` |
| Scout (brownfield scanner) | `scripts/lib/scout/` | `scripts/scout.sh` | **yes** | `scripts/lint-module-dependencies.sh` |
| Adoption driver | `scripts/lib/adopt/` | `scripts/adopt-project.sh` | no | `scripts/lint-module-dependencies.sh` |

**The delta module predates this page**, and is enforced by its own sibling
lint rather than by the one this page introduces. That is a deliberate
convergence decision, not an oversight: `lint-delta-boundary.sh` was written
against the delta design and survived two adversarial review rounds, so the
brownfield lint was built as a SIBLING in the same proven shape rather than as a
generalisation that would have churned freshly reviewed enforcement code. Both
lints share the architecture — literal manifest, executed-lines-only comment
stripping, two match tiers, reasoned exact-token allowlist, vacuity floor,
`--list`, `--root` — and neither can be weakened by an edit aimed at the other.
A single generalised engine remains available later as a rename-level change.

---

## The rules

### M1 — One directory per module

A severable module owns `scripts/lib/<module>/` and exactly one entry script.
No module code lives outside its directory.

*Enforced by:* the module manifest in each boundary lint — a path that is not in
the manifest is core, and core naming a module path is an M3 violation, so
scattered module code reds from the other direction. Grep the
`MODULE-DEPS-MANIFEST` fence for the brownfield inventory.

### M2 — Declared dependencies

Each module's entry script carries a fenced header listing the core libs it may
source. Anything not listed is a violation.

*Enforced by:* the boundary lints. For a zero-dependency module the declared set
is empty and M5 is the whole of M2; for the others the header is the declaration
and review is the check until a module actually accrues a listed dependency.

### M3 — Direction

`module → core` is permitted. **`core → module` is forbidden**: no file outside
`scripts/lib/<module>/` may source or invoke module code. This is the property
that makes severance a `git mv`, not a refactor.

*Enforced by:* both lints, in two match tiers. T1 is the literal manifest path
and is **not** waivable. T2 is a path-shaped token that catches runtime
composition (`"$SCRIPT_DIR/lib/scout/${part}.sh"` carries no literal manifest
path but still carries the module's path segment) and takes an inline allowlist
that **requires a reason**. Both tiers read EXECUTED lines only — see the
`MODULE-DEPS-STRIP` fence, and treat its width and spelling as load-bearing: the
sibling predicate `# BL-181-UNIT-LANE-PREDICATE` was re-opened three times by
one-character narrowings that passed every PR-blocking check.

**Seam allowlists are per-module and their cardinality is asserted.** The delta
module declares exactly ONE seam and its lint fails if the array grows. The
brownfield module declares **NONE**, and its lint asserts cardinality **zero** —
the in-core enabling arms are core code that reads an `adopted` flag and never
sources module code, so they are not seams and need no exemption. Growing either
number is a design change to be argued in the design doc, not a row to append.

### M4 — The enabling arms are core, and are named

In-core arms that support a module are *not* part of it. They are listed by
marker in the module's header so severance has an explicit, short interface to
preserve.

*Enforced by:* review, plus `scripts/lint-bl-markers.sh`, which resolves marker
citations in both directions — a named arm that is deleted or renamed reds. The
brownfield arms land in WP3 and the list is empty until then; the delta module's
seam is named in its lint's seam allowlist with its reason.

### M5 — The scanner depends on nothing

Scout sources **no** core lib. Its bootstrap must work in a clone that has never
run `init.sh`.

*Enforced by:* the zero-dependency arm of `scripts/lint-module-dependencies.sh`
(grep the `MODULE-DEPS-M5-CALL` marker), which forbids any Scout file from
naming a `scripts/lib/*.sh` core lib on an executed line — plus, from
WP1-brownfield, a hermetic test that runs the scanner with `scripts/lib/` moved
aside. **The arm is scout-only and that bound is itself pinned**: the adoption
driver may source core freely, and an M5 applied to every module would forbid
what M3 explicitly permits.

M5 is the load-bearing rule and it has a cost worth restating: Scout cannot
reuse `helpers-core.sh`'s printers, the `soif_read_*` state readers, or the host
drivers. It re-implements the small subset it needs. That is deliberate
duplication in exchange for a tool that runs anywhere, and it is why reuse is
specified as **reuse-by-extraction** — copy the *predicate*, not the
*dependency*.

---

## Working on a module

- **Adding a module file** is a one-line edit to the lint's manifest fence.
- **Both lints exit 2, not 0, on a collapsed scan.** A boundary lint that scans
  nothing passes trivially, and a passing lint that proves nothing is worse than
  no lint. If you get exit 2, the manifest or the `--root` is wrong.
- **What no grep-based lint can catch:** a reference composed below the token
  boundary — a path assembled from a variable holding the module name. The
  backstop there is behavioural, not lexical: the severability test that deletes
  the module and reverts the seam fails on a fused module however the fusion is
  spelled.
- Run `bash scripts/lint-module-dependencies.sh --list` (or the delta sibling's
  `--list`) for the per-file PASS/FAIL roster and the population counts.
