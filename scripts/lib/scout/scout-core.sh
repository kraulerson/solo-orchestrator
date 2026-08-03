#!/usr/bin/env bash
# scripts/lib/scout/scout-core.sh — the first file of the Scout module.
#
# SPEC: docs/designs/2026-08-02-brownfield-adoption-v1.md §3.1 (Scout is the
# read-only scanner, packaged as a standalone tool) and §3.3 M1/M5. The
# standing rules are transcribed in docs/module-contract.md.
#
# WHY THIS FILE EXISTS NOW, AHEAD OF THE SCANNER ITSELF (WP1-brownfield).
# scripts/lint-module-dependencies.sh has a vacuity floor: it exits 2 unless it
# finds at least one module file to scan. Landing the boundary lint before any
# module file would leave the repo's lint sweep red on main, and relaxing the
# floor to avoid that would defeat the floor. So the module opens with one
# honest stub instead — small, real, and bound by M5 from birth rather than
# retrofitted to it later.
#
# M5 APPLIES TO THIS FILE ALREADY: it sources NOTHING. Scout must run in a
# clone that has never had init.sh applied to it, so it may not reach for
# scripts/lib/*.sh — not for the shared printers, not for the state readers,
# not for the host drivers. §8.2's reuse is specified as reuse-by-EXTRACTION:
# copy the predicate, never the dependency. That duplication is the price of a
# survey tool that costs nothing to run, and it is deliberate.
#
# M1 APPLIES TOO: everything Scout owns lives under this directory, with
# scripts/scout.sh as its single entry script (WP1-brownfield). No Scout code
# belongs anywhere else in the tree.

# scout_module_version — the module's own version marker.
#
# Scout reports the version of the scanner that produced a report, and it has
# to do so without reading .claude/manifest.json or any framework state: at
# scan time there may be no framework installed at all. A literal here is the
# whole mechanism.
scout_module_version() {
  printf '%s\n' "0.1.0-wp0-stub"
}
