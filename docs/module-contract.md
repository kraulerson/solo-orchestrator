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
| Post-MVP delta track | `scripts/lib/` (flat `delta-*.sh` set — **grandfathered, see below**) | `scripts/delta.sh` (plus `scripts/cut-release.sh`) | no | `scripts/lint-delta-boundary.sh` |
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

**The delta module is GRANDFATHERED against M1**, and the table says so rather
than leaving a reader to hit the contradiction. M1 as written requires an owned
`scripts/lib/<module>/` directory and exactly one entry script; the delta module
has neither — its files are a flat `delta-*.sh` set directly in `scripts/lib/`,
and `scripts/cut-release.sh` sits beside `scripts/delta.sh` as a second entry
point (it is in the delta manifest because it reads `delta-state.json`).
**M1 binds NEW modules.** The delta module keeps its flat layout; its
severability is enforced by its own lint's manifest, which does not depend on
the directory shape. M2–M5 bind it normally.

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

**The set "outside" means — five globs. Corrected 2026-08-09 (Karl's approval);
evidence-led, and now implemented in both lints.** Both lints render M3's universal as a
literal CORE glob set: `init.sh` + `scripts/*.sh` + `scripts/lib/*.sh` +
`scripts/hooks/*.sh` + **`scripts/host-drivers/*.sh`**, minus the module
inventory, minus the lint itself, minus sibling boundary lints. The fifth glob
is the correction; the designs named four and both lints were built faithful to
that number, each disclosing the exclusion in its own header as a pending design
question. **It was closed by plant, not by argument:** appending
`source "$SCRIPT_DIR/lib/delta-state.sh"` to `scripts/host-drivers/github.sh`
leaves `scripts/lint-delta-boundary.sh` at rc=0, and
`source "$SCRIPT_DIR/lib/scout/scout-phasemap.sh"` in
`scripts/host-drivers/gitlab.sh` leaves `scripts/lint-module-dependencies.sh` at
rc=0 — while the same lines in `scripts/validate.sh` and
`scripts/check-maintenance.sh` red at rc=1 on T1 and T2 respectively. Host
drivers are core by every other measure (`init.sh`, `scripts/lib/host.sh` and
`scripts/intake-wizard.sh` source them by path), so a convenience call added to
one fuses a module with nothing going red. **Both `CORE_GLOBS` arrays now carry
the fifth glob** (`## BL-215:`), under the sync-sibling marker
`# BL-215-CORE-GLOB-SYNC` — grep it to find the pair, and change them together;
a one-sided edit silently re-opens the hole on the other module. This page is no
longer ahead of the code. Widening the population found **no** pre-existing
violation in `scripts/host-drivers/`: the delta lint went from 73 to 76 scanned
core files and the module lint from 76 to 79, both still at rc=0. Amended in
both designs' §3.3 in the same pass.

**Each lint pins the new glob three ways, and the third is the load-bearing
one** (`tests/test-lint-delta-boundary.sh` S4-S6,
`tests/test-lint-module-dependencies.sh` S5-S7): the plant reds at the right
tier; a *clean* host driver must raise the reported CORE population by exactly
one, because `rc=0` cannot distinguish "scanned and clean" from "never scanned"
and that ambiguity is what let this gap survive; and deleting the glob from a
copy of the lint must let the plant through again, so neither pin can stay green
under the very edit it forbids.

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

*Enforced by:* **review.** `scripts/lint-bl-markers.sh` helps, but read what it
actually delivers before relying on it: a marker cited in the **prose** surface
reds when its last occurrence anywhere in the **code** surface disappears, and a
marker in code reds when it names a `## BL-NNN:` entry nobody filed. The module
header where M4 says the arms are listed **is itself in the code surface**, so
that listing keeps its own markers alive — delete or rename an arm and the stale
listing still satisfies both directions. **The lint does not red on a stale arm
list; a human reading the list is the check.** (§3.3's own M4 row claims only
"Review + the marker lint" — this page previously strengthened that into a
guarantee the mechanism does not provide.) The brownfield arms land in WP3 and
the list is empty until then; the delta module's seam is named in its lint's
seam allowlist with its reason.

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
- **What M5 does not currently catch, disclosed:** its forbidden set is core
  **lib** basenames (`scripts/lib/*.sh`) only. A Scout file that invokes a core
  **entry script** (`scripts/*.sh`) or `init.sh` itself passes the arm clean —
  verified, `rc=0`. That is faithful to M5's first sentence and violates its
  second, and it survives the behavioural backstop too: moving `scripts/lib/`
  aside leaves `scripts/*.sh` in place, so **WP1-brownfield's hermetic test must
  move `scripts/*.sh` aside as well, or assert against a bare tree.** Widening
  the token set is a design decision, not an implementation detail, and is
  pending rather than taken.
- Run `bash scripts/lint-module-dependencies.sh --list` (or the delta sibling's
  `--list`) for the per-file PASS/FAIL roster and the population counts.
