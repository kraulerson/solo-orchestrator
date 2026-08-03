#!/usr/bin/env bash
# tests/test-brownfield-wp1-scout.sh — behaviour suite for Scout, the
# read-only brownfield scanner (WP1-brownfield).
#
# SPEC: docs/designs/2026-08-02-brownfield-adoption-v1.md — §3.1 (Scout is the
# read-only scanner, packaged standalone), §3.3 M1/M5 (one directory, one entry
# script, zero core dependencies), §8.2 (the NORMATIVE report schema and the two
# reuse-by-extraction rows), §4.2 (evidence + confidence tiers), §4.4 (the
# phase-placement ladder and its three corrections), §10-WP1. The standing
# module rules are transcribed in docs/module-contract.md.
#
# ─────────────────────────────────────────────────────────────────────────────
# WHAT THIS SUITE IS PROTECTING
#
# Scout has exactly two hard properties, and everything else in the design
# serves them:
#
#   READ-ONLY.  Scout writes NOTHING into the tree it scans. This is proven by
#   TREE HASH before/after over the WHOLE fixture — path + type + mode + content
#   for every entry including `.git/` — never by reading the source and
#   believing it. §10-WP1 names the tree-hash proof specifically, because the
#   predicate Scout extracts (process-checklist.sh's verify_init) opens with
#   `ensure_state_file` and appends to `.phase2_init.steps_completed` on every
#   passing probe. The extraction deletes those writes; R1/R2 are what keep
#   them deleted, and X2 is the proof that R1/R2 can actually bite.
#
#   ZERO-DEPENDENCY (M5).  Scout sources no core lib and runs in a clone that
#   has never been near init.sh. H1 proves it the strong way — Scout's files are
#   copied into an otherwise EMPTY tree and run there. H2 proves the WP0
#   carry-forward (review finding R-WP0-3): the lint's M5 arm forbids core
#   *lib* basenames only, so a Scout file that shelled out to a core ENTRY
#   script would pass the lint clean, and a hermetic test that moved only
#   `scripts/lib/` aside would pass too. H2 therefore moves `scripts/*.sh`
#   aside as well. X4 runs the real lint against a mutated copy.
#
# ─────────────────────────────────────────────────────────────────────────────
# EXIT CODES AND VALUES, NEVER LABELS. Every assertion reads an exit code, a
# jq-extracted JSON value, or a file/tree hash. None reads a printed banner —
# CLAUDE.md's [WARN] trap is precisely that the label and the outcome disagree.
#
# MUTATION PROOFS (X1-X4). Each builds a COPY of Scout, applies ONE anchored
# single-site neuter, asserts the copy really changed by exactly the expected
# number of lines (`_changed_lines`), runs the mutant, and requires the pinned
# assertion to flip. A control run of the UNMUTATED copy is asserted in the
# same case, so "the mutant failed" can never be a fixture accident. The
# in-place editor preserves file mode (`_sed_inplace`): the obvious spelling
# ends `chmod +x`, which silently promotes a 0644 lib to 0755 and rides along
# in the next commit.
#
#   X1  ladder: prefix-max -> last-wins  => the HANDOFF fixture reports 4, not 2
#   X2  a probe writes state             => the tree-hash proof (R1/R2) reds
#   X3  branch_protection consults a file => its `unknown` pin reds
#   X4  a Scout file sources a core lib   => scripts/lint-module-dependencies.sh reds
#
# HERMETICITY: every fixture is a `mktemp -d` tree. No network, no host CLI, no
# real remote — the one fixture remote is a `git remote add` of an unreachable
# URL, which is a config write and nothing more. Scout itself is never given a
# host credential to use. bash-3.2 safe: no associative arrays, no `${var,,}`,
# no `mapfile`, no `((x++))`.
#
# LANE: registered in tests/full-project-test-suite.sh AND in the
# .github/workflows/tests.yml `unit-shard` list. This suite never mentions,
# copies or executes the scaffolder, so it is a unit-lane test outright and
# must NOT appear in `lint-tests-registered.sh --list | grep unit-lane-exempt`.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCOUT="$REPO_ROOT/scripts/scout.sh"
SCOUT_LIB="$REPO_ROOT/scripts/lib/scout"
MODLINT="$REPO_ROOT/scripts/lint-module-dependencies.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for tests/test-brownfield-wp1-scout.sh" >&2
  exit 2
fi

TMPS=""
cleanup() { [ -n "$TMPS" ] && rm -rf $TMPS; return 0; }
trap cleanup EXIT
newtmp() { local d; d=$(mktemp -d); TMPS="$TMPS $d"; printf '%s\n' "$d"; }

# ── Portable primitives (house pattern) ─────────────────────────────────────

_md5file()  { if command -v md5 >/dev/null 2>&1; then md5 -q "$1"; else md5sum "$1" | awk '{print $1}'; fi; }
_md5stdin() { if command -v md5 >/dev/null 2>&1; then md5 -q; else md5sum | awk '{print $1}'; fi; }
_mode_of()  { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || echo "?"; }

# _tree_manifest DIR — one line per filesystem entry under DIR:
#   <relpath>|<type>|<mode>[|<content-md5>]
# `.git/` is INCLUDED on purpose. A scanner that "only" refreshed the index or
# dropped a lock file would still have written to the operator's repository, and
# the design's promise is that it writes nothing. Directory modes are captured
# so a chmod is caught, and symlink targets so a retarget is caught.
_tree_manifest() {
  ( cd "$1" 2>/dev/null || return 1
    find . -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r p; do
      if [ -L "$p" ];   then printf '%s|L|%s\n' "$p" "$(readlink "$p" 2>/dev/null)"
      elif [ -d "$p" ]; then printf '%s|D|%s\n' "$p" "$(_mode_of "$p")"
      elif [ -f "$p" ]; then printf '%s|F|%s|%s\n' "$p" "$(_mode_of "$p")" "$(_md5file "$p")"
      else                   printf '%s|O|-\n' "$p"
      fi
    done )
}
_tree_hash() { _tree_manifest "$1" | _md5stdin; }

# _sed_inplace FILE EXPR — portable in-place sed PRESERVING the file's mode.
# Read the mode first and put it back: `chmod +x` after the mv silently widens
# a 0644 lib to 0755, `git status` shows only "M", and the mode change rides
# along in the next commit.
_sed_inplace() {
  local file="$1" expr="$2" tmp mode
  mode="$(_mode_of "$file")"
  tmp="$(mktemp)"
  sed -e "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
  [ "$mode" != "?" ] && chmod "$mode" "$file" 2>/dev/null
  return 0
}

# _awk_inplace FILE AWK-PROGRAM — same contract, awk edition (BSD-awk safe).
# Used for the mutations, because an anchored single-site substitution is far
# easier to write correctly (and to bound to ONE site via a `done` flag) in awk
# than in a sed expression full of escaped shell metacharacters.
_awk_inplace() {
  local file="$1" prog="$2" tmp mode
  mode="$(_mode_of "$file")"
  tmp="$(mktemp)"
  awk "$prog" "$file" > "$tmp" && mv "$tmp" "$file"
  [ "$mode" != "?" ] && chmod "$mode" "$file" 2>/dev/null
  return 0
}

# _changed_lines A B — how many lines diff reports as added or removed.
# A one-line SUBSTITUTION is 2 (one `<`, one `>`); a one-line INSERTION is 1.
# Asserting this is what stops a mutation from quietly becoming a rewrite, and
# what stops a NO-OP edit from being read as a proof.
_changed_lines() {
  local n
  n=$(diff "$1" "$2" 2>/dev/null | grep -c '^[<>]')
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s\n' "$n"
}

# mk_scout_copy DIR — Scout, and ONLY Scout, laid out at its real relative
# paths under DIR. This is both the mutation substrate and H1's bare tree.
mk_scout_copy() {
  local d="$1"
  mkdir -p "$d/scripts/lib/scout"
  cp "$SCOUT" "$d/scripts/scout.sh"
  cp "$SCOUT_LIB"/*.sh "$d/scripts/lib/scout/"
  chmod +x "$d/scripts/scout.sh"
}

# ── Fixtures ────────────────────────────────────────────────────────────────

# A node/pnpm project that is genuinely mid-flight: product + architecture
# docs, a running test corpus, CI, a lockfile, a hook, an origin remote — but
# no deploy lane and no tags, so rung 4 is honestly unsatisfied.
mk_node_fixture() {
  local d="$1" i
  mkdir -p "$d/src" "$d/tests" "$d/docs" "$d/.github/workflows"
  cat > "$d/package.json" <<'EOF'
{
  "name": "acme-api",
  "version": "0.4.1",
  "scripts": {
    "build": "tsc -p .",
    "test": "vitest run",
    "lint": "eslint ."
  },
  "dependencies": { "fastify": "^4.0.0" }
}
EOF
  printf 'lockfileVersion: 6.0\n' > "$d/pnpm-lock.yaml"
  i=1
  while [ "$i" -le 12 ]; do
    printf 'export const v%s = %s;\n' "$i" "$i" > "$d/src/mod$i.ts"
    i=$((i + 1))
  done
  printf 'module.exports = {};\n' > "$d/src/legacy.js"
  printf "import { v1 } from '../src/mod1';\ntest('v1', () => {});\n" > "$d/tests/mod1.test.ts"
  printf '# acme-api\n\nA billing API for the acme platform.\n' > "$d/README.md"
  printf '# Architecture\n\nFastify + Postgres, one service.\n' > "$d/ARCHITECTURE.md"
  printf 'name: ci\non: [push]\njobs:\n  build:\n    runs-on: ubuntu-latest\n' \
    > "$d/.github/workflows/ci.yml"
  ( cd "$d" && unset GITHUB_BASE_REF
    git init -q .
    git config user.email t@t.local
    git config user.name T
    git remote add origin https://example.invalid/acme/acme-api.git
    git add -A && git commit -q -m "initial import" ) >/dev/null 2>&1
  printf '#!/bin/sh\nexit 0\n' > "$d/.git/hooks/pre-commit"
  chmod +x "$d/.git/hooks/pre-commit"
}

# A python/poetry project: a smaller corpus (so its confidence tier differs
# from the node fixture's), a pytest config, NO CI, NO git, NO lockfile-backed
# hook — several probes must be able to reach `fail`.
mk_python_fixture() {
  local d="$1" i
  mkdir -p "$d/acme" "$d/tests"
  cat > "$d/pyproject.toml" <<'EOF'
[tool.poetry]
name = "acme-etl"
version = "0.2.0"

[tool.pytest.ini_options]
testpaths = ["tests"]
EOF
  printf '# poetry lock\n' > "$d/poetry.lock"
  printf '[pytest]\ntestpaths = tests\n' > "$d/pytest.ini"
  i=1
  while [ "$i" -le 5 ]; do
    printf 'def f%s():\n    return %s\n' "$i" "$i" > "$d/acme/m$i.py"
    i=$((i + 1))
  done
  printf 'def test_f1():\n    assert True\n' > "$d/tests/test_f1.py"
  printf '# acme-etl\n\nNightly ETL for acme.\n' > "$d/README.md"
  printf '# Design\n\nAirflow DAG, one worker.\n' > "$d/docs-design.md"
  mkdir -p "$d/docs"
  printf '# Design\n\nAirflow DAG, one worker.\n' > "$d/docs/design.md"
}

# THE LADDER FIXTURE — §4.4 correction 2, stated as an executable expectation.
#
# It has a product description (rung 1), an architecture document (rung 2), an
# EMPTY docs/test-results/ and no test corpus at all (rung 3 UNSATISFIED), and
# a HANDOFF.md (rung 4 satisfied — the framework filename is one legitimate
# input to the shipped-lane rung).
#
# validate.sh's original ladder assigns sequentially, so the LAST matching test
# wins and this tree reports 4. The extracted copy climbs the ladder instead
# and stops at the first gap: 2. X1 restores last-wins and watches 2 become 4.
mk_handoff_fixture() {
  local d="$1"
  mkdir -p "$d/docs/test-results"
  printf '# legacy-svc\n\nThe original order service.\n' > "$d/README.md"
  printf '# Architecture\n\nMonolith, MySQL.\n' > "$d/ARCHITECTURE.md"
  printf '# Handoff\n\nOwned by the platform team.\n' > "$d/HANDOFF.md"
}

# A tree with NO framework state of any kind: no git, no CI, no lockfile, no
# hook, no docs. §10-WP1's "probes run in a repo with NO framework state" —
# which is the entire point of a brownfield scanner.
mk_bare_fixture() {
  local d="$1"
  printf 'hello\n' > "$d/notes.txt"
}

# ── Runners ─────────────────────────────────────────────────────────────────

# scout_json ROOT [entry] — the JSON document on stdout. stderr is dropped so a
# diagnostic can never be mistaken for report bytes.
scout_json() {
  local root="$1" entry="${2:-$SCOUT}"
  bash "$entry" --root "$root" </dev/null 2>/dev/null
}
scout_md() {
  local root="$1" entry="${2:-$SCOUT}"
  bash "$entry" --root "$root" --markdown </dev/null 2>/dev/null
}
jqv() { printf '%s' "$1" | jq -r "$2" 2>/dev/null; }

echo "== tests/test-brownfield-wp1-scout.sh =="
echo ""

NODE=$(newtmp);   mk_node_fixture   "$NODE"
PY=$(newtmp);     mk_python_fixture "$PY"
LADDER=$(newtmp); mk_handoff_fixture "$LADDER"
BARE=$(newtmp);   mk_bare_fixture   "$BARE"

# ════════════════════════════════════════════════════════════════════════════
echo "=== A — interface, headers, and the honest absence of WP2's sections ==="
# ════════════════════════════════════════════════════════════════════════════

# ── A1: the default interface is JSON on stdout, and it is valid JSON ───────
out=$(scout_json "$NODE"); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
  pass "A1: bare invocation emits valid JSON on stdout, rc=0"
else
  fail_ "A1" "rc=$rc, or stdout was not valid JSON; first 300 bytes:\n$(printf '%s' "$out" | head -c 300)"
fi

# ── A2: every §8.2 header key is present and correctly typed ───────────────
sv=$(jqv "$out" '.schemaVersion')
at=$(jqv "$out" '.scannedAt')
ver=$(jqv "$out" '.scannerVersion')
rr=$(jqv "$out" '.repoRoot')
hc=$(jqv "$out" '.headCommit')
ok=1
[ "$sv" = "1" ] || ok=0
printf '%s' "$at" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' || ok=0
[ -n "$ver" ] && [ "$ver" != "null" ] || ok=0
[ "$rr" = "$(cd "$NODE" && pwd)" ] || ok=0
printf '%s' "$hc" | grep -Eq '^[0-9a-f]{7,40}$' || ok=0
if [ "$ok" -eq 1 ]; then
  pass "A2: schemaVersion/scannedAt/scannerVersion/repoRoot/headCommit all present and well-formed"
else
  fail_ "A2" "schemaVersion=$sv scannedAt=$at scannerVersion=$ver repoRoot=$rr headCommit=$hc"
fi

# ── A3: WP2's four sections are declared ABSENT, not silently missing ───────
# The brief's requirement: this version emits three sections and says which
# four it does not. A consumer that reads `sections` can tell "not scanned yet"
# apart from "scanned and found nothing" — which for `secrets` is the whole
# difference between a survey and a false clean bill of health.
emitted=$(jqv "$out" '.sections | join(",")')
pending=$(jqv "$out" '.sectionsNotEmitted | join(",")')
absent=1
for k in testsBaseline secrets collisions intakePrefill; do
  printf '%s' "$out" | jq -e "has(\"$k\")" >/dev/null 2>&1 && absent=0
done
if [ "$emitted" = "stack,phaseMap,reality" ] \
   && [ "$pending" = "testsBaseline,secrets,collisions,intakePrefill" ] \
   && [ "$absent" -eq 1 ]; then
  pass "A3: sections=[stack,phaseMap,reality]; the four WP2 sections are named as not-emitted and their keys are absent"
else
  fail_ "A3" "emitted='$emitted' pending='$pending' wp2_keys_absent=$absent"
fi

# ── A4: --out writes the pair, and writes NOTHING else ─────────────────────
OUTD=$(newtmp)
o=$(bash "$SCOUT" --root "$NODE" --out "$OUTD" </dev/null 2>/dev/null); rc=$?
files=$( (cd "$OUTD" && LC_ALL=C ls -1) | tr '\n' ' ')
jsonok=0
[ -f "$OUTD/scout-report.json" ] && jq -e . "$OUTD/scout-report.json" >/dev/null 2>&1 && jsonok=1
if [ "$rc" -eq 0 ] && [ "$files" = "scout-report.json scout-report.md " ] && [ "$jsonok" -eq 1 ] \
   && printf '%s' "$o" | grep -q 'scout-report.json'; then
  pass "A4: --out writes exactly scout-report.json + scout-report.md and names them on stdout"
else
  fail_ "A4" "rc=$rc files='$files' jsonok=$jsonok stdout:\n$o"
fi

# ── A5: an unknown flag is a usage error, not a silent default scan ────────
o=$(bash "$SCOUT" --root "$NODE" --wat </dev/null 2>&1); rc=$?
if [ "$rc" -eq 2 ]; then
  pass "A5: an unrecognised flag exits 2 (usage), never 0 with a partial report"
else
  fail_ "A5" "expected rc=2; rc=$rc; output:\n$o"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== R — READ-ONLY, proven by tree hash over the whole fixture ==="
# ════════════════════════════════════════════════════════════════════════════

# ── R1: a BARE (non-git) fixture is byte-identical after every mode ─────────
before=$(_tree_hash "$BARE")
scout_json "$BARE" >/dev/null
scout_md   "$BARE" >/dev/null
SIDE=$(newtmp); bash "$SCOUT" --root "$BARE" --out "$SIDE" </dev/null >/dev/null 2>&1
after=$(_tree_hash "$BARE")
if [ "$before" = "$after" ]; then
  pass "R1: bare fixture unchanged after json + markdown + --out runs (tree hash equal)"
else
  fail_ "R1" "tree hash changed: $before -> $after\n$(diff <(_tree_manifest "$BARE") /dev/null | head -20)"
fi

# ── R2: a GIT fixture is byte-identical, `.git/` included ───────────────────
# This is the case that would catch the extracted verify_init's writes: the
# original appends to .claude/process-state.json on every passing probe, and
# the node fixture makes four of the five probes pass.
_tree_manifest "$NODE" > "$SIDE/node-before.txt"
before=$(_tree_hash "$NODE")
scout_json "$NODE" >/dev/null
scout_md   "$NODE" >/dev/null
bash "$SCOUT" --root "$NODE" --out "$SIDE" </dev/null >/dev/null 2>&1
after=$(_tree_hash "$NODE")
if [ "$before" = "$after" ]; then
  pass "R2: git fixture unchanged (.git/ included) after json + markdown + --out runs"
else
  _tree_manifest "$NODE" > "$SIDE/node-after.txt"
  fail_ "R2" "tree hash changed: $before -> $after\n$(diff "$SIDE/node-before.txt" "$SIDE/node-after.txt" | head -20)"
fi

# ── R3: the recipe is not vacuous — it detects a one-byte write ─────────────
# A read-only proof whose instrument cannot register a change proves nothing.
PROBE=$(newtmp); mk_bare_fixture "$PROBE"
h1=$(_tree_hash "$PROBE")
printf 'x\n' >> "$PROBE/notes.txt"
h2=$(_tree_hash "$PROBE")
mkdir -p "$PROBE/.claude"
h3=$(_tree_hash "$PROBE")
if [ "$h1" != "$h2" ] && [ "$h2" != "$h3" ]; then
  pass "R3: the tree-hash recipe detects both a content append and a new directory (instrument is live)"
else
  fail_ "R3" "recipe is blind: h1=$h1 h2=$h2 h3=$h3"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== S — stack detection across two shapes, with confidence tiers (§4.2) ==="
# ════════════════════════════════════════════════════════════════════════════

njson=$(scout_json "$NODE")
pjson=$(scout_json "$PY")

# ── S1: the node/pnpm shape ────────────────────────────────────────────────
ts_files=$(jqv "$njson" '.stack.languages[] | select(.name=="typescript") | .files')
ts_conf=$(jqv "$njson" '.stack.languages[] | select(.name=="typescript") | .confidence')
pm=$(jqv "$njson" '.stack.packageManagers | join(",")')
bf=$(jqv "$njson" '.stack.buildFiles | join(",")')
tc=$(jqv "$njson" '.stack.testCommand.value')
tcs=$(jqv "$njson" '.stack.testCommand.source')
ci=$(jqv "$njson" '.stack.ciHost')
if [ "$ts_files" = "13" ] && [ "$ts_conf" = "high" ] \
   && printf '%s' "$pm" | grep -q 'pnpm' \
   && printf '%s' "$bf" | grep -q 'package.json' \
   && [ "$tc" = "vitest run" ] && [ "$tcs" = "package.json scripts.test" ] \
   && [ "$ci" = "github" ]; then
  pass "S1: node fixture — typescript(13,high), pnpm, package.json, testCommand from scripts.test, ciHost=github"
else
  fail_ "S1" "ts_files=$ts_files ts_conf=$ts_conf pm='$pm' bf='$bf' tc='$tc' tcs='$tcs' ci='$ci'"
fi

# ── S2: the python/poetry shape ────────────────────────────────────────────
py_files=$(jqv "$pjson" '.stack.languages[] | select(.name=="python") | .files')
py_conf=$(jqv "$pjson" '.stack.languages[] | select(.name=="python") | .confidence')
ppm=$(jqv "$pjson" '.stack.packageManagers | join(",")')
ptcs=$(jqv "$pjson" '.stack.testCommand.source')
pci=$(jqv "$pjson" '.stack.ciHost')
if [ "$py_files" = "6" ] && [ "$py_conf" = "medium" ] \
   && printf '%s' "$ppm" | grep -q 'poetry' \
   && printf '%s' "$ptcs" | grep -q 'pytest' \
   && [ "$pci" = "null" ]; then
  pass "S2: python fixture — python(6,medium), poetry, pytest-sourced testCommand, ciHost=null"
else
  fail_ "S2" "py_files=$py_files py_conf=$py_conf ppm='$ppm' ptcs='$ptcs' pci='$pci'"
fi

# ── S3: every language carries a tier, and the tiers actually vary ─────────
# §4.2 presents each signal WITH ITS OWN CONFIDENCE. A field that is always the
# same string is decoration, not evidence, so assert the vocabulary AND that at
# least two distinct tiers are observable across real shapes.
tiers=$( { jqv "$njson" '.stack.languages[].confidence'; jqv "$pjson" '.stack.languages[].confidence'; } \
         | LC_ALL=C sort -u | tr '\n' ' ')
bad=$( { jqv "$njson" '.stack.languages[].confidence'; jqv "$pjson" '.stack.languages[].confidence'; } \
       | grep -vc -E '^(high|medium|low)$')
case "$bad" in ''|*[!0-9]*) bad=0 ;; esac
distinct=$(printf '%s' "$tiers" | wc -w | tr -d ' ')
if [ "$bad" -eq 0 ] && [ "$distinct" -ge 2 ]; then
  pass "S3: every confidence is in {high,medium,low} and $distinct distinct tiers appear across the two fixtures ($tiers)"
else
  fail_ "S3" "off_vocabulary=$bad distinct=$distinct tiers='$tiers'"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== P — the extracted artifact ladder (§4.4, three corrections) ==="
# ════════════════════════════════════════════════════════════════════════════

ljson=$(scout_json "$LADDER")

# ── P1: THE DESIGN'S OWN TEST — HANDOFF.md + emptied test-results => 2 ─────
sp=$(jqv "$ljson" '.phaseMap.suggestedPhase')
hi=$(jqv "$ljson" '.phaseMap.highestSatisfiedRung')
r3=$(jqv "$ljson" '.phaseMap.rungs[] | select(.rung==3) | .satisfied')
r4=$(jqv "$ljson" '.phaseMap.rungs[] | select(.rung==4) | .satisfied')
if [ "$sp" = "2" ] && [ "$r3" = "false" ] && [ "$r4" = "true" ] && [ "$hi" = "4" ]; then
  pass "P1: HANDOFF.md + empty docs/test-results/ reports suggestedPhase 2 (rung 3 false, rung 4 true, highest 4)"
else
  fail_ "P1" "suggestedPhase=$sp highestSatisfiedRung=$hi rung3.satisfied=$r3 rung4.satisfied=$r4"
fi

# ── P2: the note is §8.2's string, verbatim ────────────────────────────────
note=$(jqv "$ljson" '.phaseMap.note')
if [ "$note" = "maximum satisfied rung; the interview may only lower this" ]; then
  pass "P2: phaseMap.note is §8.2's string verbatim"
else
  fail_ "P2" "note='$note'"
fi

# ── P3: the evidence table is transparent — 4 rungs, each with a reason ────
# §10-WP1: "keep the evidence table transparent in the report output (each
# rung: satisfied yes/no + the evidence string)". An unsatisfied rung needs its
# string as much as a satisfied one: it is what tells the operator what is
# missing, and it is what makes the placement arguable rather than oracular.
nr=$(jqv "$ljson" '.phaseMap.rungs | length')
empty=$(jqv "$ljson" '[.phaseMap.rungs[] | select((.evidence|type) != "string" or (.evidence|length) == 0)] | length')
sat_typed=$(jqv "$ljson" '[.phaseMap.rungs[] | select((.satisfied|type) != "boolean")] | length')
if [ "$nr" = "4" ] && [ "$empty" = "0" ] && [ "$sat_typed" = "0" ]; then
  pass "P3: 4 rungs, every one carrying a non-empty evidence string and a boolean satisfied"
else
  fail_ "P3" "rungs=$nr empty_evidence=$empty non_boolean_satisfied=$sat_typed"
fi

# ── P4: the ladder discriminates — three fixtures, three placements ────────
sp_bare=$(jqv "$(scout_json "$BARE")" '.phaseMap.suggestedPhase')
sp_node=$(jqv "$njson" '.phaseMap.suggestedPhase')
if [ "$sp_bare" = "0" ] && [ "$sp_node" = "3" ]; then
  pass "P4: bare tree places at 0, the node fixture (docs + running corpus, no deploy lane) at 3"
else
  fail_ "P4" "bare=$sp_bare node=$sp_node (expected 0 and 3)"
fi

# ── P5: correction (c) — the ladder reads the ADOPTEE's evidence ───────────
# No framework filename exists anywhere in the node or python fixtures. If the
# extracted ladder still keyed on PRODUCT_MANIFESTO.md / PROJECT_BIBLE.md it
# would place every brownfield project at 0, which is the failure §4.4 names.
fw=$(ls "$NODE"/PRODUCT_MANIFESTO.md "$NODE"/PROJECT_BIBLE.md "$NODE"/HANDOFF.md 2>/dev/null | wc -l | tr -d ' ')
e1=$(jqv "$njson" '.phaseMap.rungs[] | select(.rung==1) | .evidence')
e2=$(jqv "$njson" '.phaseMap.rungs[] | select(.rung==2) | .evidence')
sp_py=$(jqv "$pjson" '.phaseMap.suggestedPhase')
if [ "$fw" -eq 0 ] && printf '%s' "$e1" | grep -q 'README.md' \
   && printf '%s' "$e2" | grep -q 'ARCHITECTURE.md' && [ "$sp_py" -ge 2 ]; then
  pass "P5: with zero framework filenames present, rungs 1/2 resolve on README.md and ARCHITECTURE.md (python fixture places at $sp_py)"
else
  fail_ "P5" "framework_files=$fw rung1='$e1' rung2='$e2' python_phase=$sp_py"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== V — the five reality probes, read-only copies of verify_init ==="
# ════════════════════════════════════════════════════════════════════════════

bjson=$(scout_json "$BARE")
probe_n() { jqv "$1" ".reality.probes[] | select(.name==\"$2\") | .result"; }
probe_h() { jqv "$1" ".reality.probes[] | select(.name==\"$2\") | .how"; }

# ── V1: the §8.2 probe roster, in order, on a well-equipped tree ───────────
names=$(jqv "$njson" '.reality.probes[].name' | tr '\n' ',')
want="remote_repo_created,branch_protection_configured,ci_pipeline_configured,project_scaffolded,pre_commit_hooks_installed,"
if [ "$names" = "$want" ]; then
  pass "V1: the probe roster is §8.2's five names in §8.2's order"
else
  fail_ "V1" "got '$names' want '$want'"
fi

# ── V2: on the node fixture the four probeable steps all pass ─────────────
ok=1
for p in remote_repo_created ci_pipeline_configured project_scaffolded pre_commit_hooks_installed; do
  [ "$(probe_n "$njson" "$p")" = "pass" ] || ok=0
done
if [ "$ok" -eq 1 ]; then
  pass "V2: node fixture — remote/ci/scaffold/hook all pass"
else
  fail_ "V2" "results: $(for p in remote_repo_created ci_pipeline_configured project_scaffolded pre_commit_hooks_installed; do printf '%s=%s ' "$p" "$(probe_n "$njson" "$p")"; done)"
fi

# ── V3: on a tree with NO framework state the same four all fail ──────────
# §10-WP1: "probes run in a repo with NO framework state (that is the whole
# point)". A scanner that needed .claude/process-state.json to exist before it
# could answer would be useless on the only trees it is ever pointed at.
ok=1
for p in remote_repo_created ci_pipeline_configured project_scaffolded pre_commit_hooks_installed; do
  [ "$(probe_n "$bjson" "$p")" = "fail" ] || ok=0
done
rcb=0; scout_json "$BARE" >/dev/null 2>&1 || rcb=$?
if [ "$ok" -eq 1 ] && [ "$rcb" -eq 0 ]; then
  pass "V3: bare tree — all four probeable steps fail, and the scan still exits 0 (findings are not errors)"
else
  fail_ "V3" "all_fail=$ok rc=$rcb results: $(for p in remote_repo_created ci_pipeline_configured project_scaffolded pre_commit_hooks_installed; do printf '%s=%s ' "$p" "$(probe_n "$bjson" "$p")"; done)"
fi

# ── V4: branch_protection_configured is ALWAYS unknown, and says why ──────
# §8.2's correction: a read-only tool must not make authenticated API calls on
# the operator's behalf. `unknown` is the honest answer and the `how` string
# must name the reason, so nobody later reads the blank as "not configured".
bp_n=$(probe_n "$njson" branch_protection_configured)
bp_b=$(probe_n "$bjson" branch_protection_configured)
bp_h=$(probe_h "$njson" branch_protection_configured)
if [ "$bp_n" = "unknown" ] && [ "$bp_b" = "unknown" ] \
   && printf '%s' "$bp_h" | grep -qi 'read-only' \
   && printf '%s' "$bp_h" | grep -qi 'not consulted'; then
  pass "V4: branch_protection_configured is unknown on BOTH fixtures, with a how-string naming the read-only reason"
else
  fail_ "V4" "node='$bp_n' bare='$bp_b' how='$bp_h'"
fi

# ── V5: data_model_applied is OMITTED with a reason, never faked ──────────
dm_probe=$(jqv "$njson" '[.reality.probes[] | select(.name=="data_model_applied")] | length')
dm_om=$(jqv "$njson" '.reality.omitted[] | select(.name=="data_model_applied") | .why')
if [ "$dm_probe" = "0" ] && [ -n "$dm_om" ] && [ "$dm_om" != "null" ]; then
  pass "V5: data_model_applied is absent from probes[] and declared in omitted[] with a reason"
else
  fail_ "V5" "probe_count=$dm_probe omitted_why='$dm_om'"
fi

# ── V6: the derived rollup carries verify_init's shape, read-only ─────────
ru_n=$(jqv "$njson" '.reality.rollup.result')
ru_p=$(jqv "$njson" '.reality.rollup.passed')
ru_t=$(jqv "$njson" '.reality.rollup.total')
ru_b=$(jqv "$bjson" '.reality.rollup.result')
ru_name=$(jqv "$njson" '.reality.rollup.name')
if [ "$ru_name" = "initialization_verified" ] && [ "$ru_p" = "4" ] && [ "$ru_t" = "5" ] \
   && [ "$ru_n" = "unknown" ] && [ "$ru_b" = "fail" ]; then
  pass "V6: rollup = initialization_verified 4/5 -> unknown on the node fixture, fail on the bare one"
else
  fail_ "V6" "name='$ru_name' passed=$ru_p total=$ru_t node='$ru_n' bare='$ru_b'"
fi

# ── V7: all three result states are reachable in fixtures ────────────────
states=$( { jqv "$njson" '.reality.probes[].result'; jqv "$bjson" '.reality.probes[].result'; } \
          | LC_ALL=C sort -u | tr '\n' ' ')
if [ "$states" = "fail pass unknown " ]; then
  pass "V7: pass, fail and unknown are each reachable across the fixtures"
else
  fail_ "V7" "observed states: '$states' (want 'fail pass unknown ')"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== D — the Markdown view renders the same data (currency-system precedent) ==="
# ════════════════════════════════════════════════════════════════════════════

# ── D1: the human view carries the machine view's values ─────────────────
md=$(scout_md "$NODE")
ok=1
printf '%s' "$md" | grep -q "$(jqv "$njson" '.phaseMap.suggestedPhase')" || ok=0
printf '%s' "$md" | grep -q 'typescript' || ok=0
printf '%s' "$md" | grep -q '13' || ok=0
printf '%s' "$md" | grep -q 'vitest run' || ok=0
printf '%s' "$md" | grep -q 'branch_protection_configured' || ok=0
printf '%s' "$md" | grep -q 'unknown' || ok=0
printf '%s' "$md" | grep -q "$(jqv "$njson" '.phaseMap.note')" || ok=0
if [ "$ok" -eq 1 ]; then
  pass "D1: the Markdown view renders the phase, the language + file count, the test command, the probe roster and the note"
else
  fail_ "D1" "a JSON value was missing from the Markdown view; markdown:\n$(printf '%s' "$md" | head -40)"
fi

# ── D2: the pair written by --out is the pair printed to stdout ──────────
# Same data, two projections — not two independent scans that could disagree.
PAIR=$(newtmp)
bash "$SCOUT" --root "$LADDER" --out "$PAIR" </dev/null >/dev/null 2>&1
a=$(jq -r '.phaseMap.suggestedPhase' "$PAIR/scout-report.json" 2>/dev/null)
b=$(jqv "$ljson" '.phaseMap.suggestedPhase')
mdsp=$(grep -c "$a" "$PAIR/scout-report.md" 2>/dev/null)
case "$mdsp" in ''|*[!0-9]*) mdsp=0 ;; esac
if [ -n "$a" ] && [ "$a" = "$b" ] && [ "$mdsp" -ge 1 ]; then
  pass "D2: --out's json and md agree with the stdout scan on suggestedPhase ($a)"
else
  fail_ "D2" "out_json=$a stdout_json=$b md_hits=$mdsp"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== H — M5: zero dependency, proven in a tree that has nothing else ==="
# ════════════════════════════════════════════════════════════════════════════

# ── H1: Scout alone in an empty tree still produces the full report ───────
H1=$(newtmp); mk_scout_copy "$H1"
core_libs=$(ls "$H1/scripts/lib"/*.sh 2>/dev/null | wc -l | tr -d ' ')
core_entries=$(ls "$H1/scripts"/*.sh 2>/dev/null | grep -vc '/scout\.sh$')
case "$core_entries" in ''|*[!0-9]*) core_entries=0 ;; esac
h1out=$(bash "$H1/scripts/scout.sh" --root "$NODE" </dev/null 2>/dev/null); rc=$?
h1sec=$(jqv "$h1out" '.sections | join(",")')
if [ "$rc" -eq 0 ] && [ "$core_libs" -eq 0 ] && [ "$core_entries" -eq 0 ] \
   && [ "$h1sec" = "stack,phaseMap,reality" ]; then
  pass "H1: Scout copied ALONE into an empty tree (0 core libs, 0 other entry scripts) emits all three sections"
else
  fail_ "H1" "rc=$rc core_libs=$core_libs other_entry_scripts=$core_entries sections='$h1sec'"
fi

# ── H2: the WP0 carry-forward (R-WP0-3) — move the ENTRY SCRIPTS aside too ─
# docs/module-contract.md, "What M5 does not currently catch": the lint's
# forbidden set is core LIB basenames only, so a Scout file that shelled out to
# `scripts/check-gate.sh` passes the lint clean — and a hermetic test that moved
# only `scripts/lib/` aside would pass too, because `scripts/*.sh` is still
# sitting there. This case moves both.
H2=$(newtmp)
cp -R "$REPO_ROOT/scripts" "$H2/scripts"
mkdir -p "$H2/moved-aside/lib"
for f in "$H2/scripts/lib"/*.sh; do [ -f "$f" ] && mv "$f" "$H2/moved-aside/lib/"; done
for f in "$H2/scripts"/*.sh; do
  [ -f "$f" ] || continue
  case "$f" in */scout.sh) continue ;; esac
  mv "$f" "$H2/moved-aside/"
done
left_libs=$(ls "$H2/scripts/lib"/*.sh 2>/dev/null | wc -l | tr -d ' ')
left_entries=$(ls "$H2/scripts"/*.sh 2>/dev/null | grep -vc '/scout\.sh$')
case "$left_entries" in ''|*[!0-9]*) left_entries=0 ;; esac
h2out=$(bash "$H2/scripts/scout.sh" --root "$LADDER" </dev/null 2>/dev/null); rc=$?
h2sp=$(jqv "$h2out" '.phaseMap.suggestedPhase')
h2sec=$(jqv "$h2out" '.sections | join(",")')
if [ "$rc" -eq 0 ] && [ "$left_libs" -eq 0 ] && [ "$left_entries" -eq 0 ] \
   && [ "$h2sec" = "stack,phaseMap,reality" ] && [ "$h2sp" = "2" ]; then
  pass "H2: with every core lib AND every core entry script moved aside, Scout still reports all three sections (phase $h2sp)"
else
  fail_ "H2" "rc=$rc leftover_libs=$left_libs leftover_entry_scripts=$left_entries sections='$h2sec' phase=$h2sp"
fi

# ── H3: nothing under scripts/lib/scout/ names a core lib, statically ─────
# H1/H2 are behavioural. This is the lexical companion and it is the REAL
# lint, run against the REAL tree — the same assertion X4 mutates.
o=$(bash "$MODLINT" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  pass "H3: scripts/lint-module-dependencies.sh is green on the working tree"
else
  fail_ "H3" "the module-dependency lint is rc=$rc on the tree:\n$o"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== X — mutation proofs (anchored, single-site, mode-preserving) ==="
# ════════════════════════════════════════════════════════════════════════════

# ── X1: restore last-wins in the ladder -> the fixture reports 4, not 2 ───
# §10-WP1's own mutation. The extracted copy climbs: a rung only advances the
# placement when the rung BELOW it was reached. Delete that clause and the
# assignment becomes validate.sh's sequential one, where the last matching
# test wins — and the fixture's HANDOFF.md carries it to 4 across the gap at
# rung 3. That number, 4, is the defect §4.4 correction 2 exists to remove.
#
# THE ANCHOR IS TWO-PART, AND THE SECOND PART IS NOT DECORATION. The lib's
# header CITES `# SCOUT-LADDER-MAX` in prose, as the citation rule asks it to,
# so a marker-only anchor hits the comment on line 29 and replaces THAT — the
# mutant then dies on an unbound variable and reports nothing at all. An empty
# result is not "reports 4"; asserting on it would have proved nothing while
# looking green-adjacent. This is the same defect class as the unit-lane
# predicate that read comments as executed lines (CLAUDE.md,
# `# BL-181-UNIT-LANE-PREDICATE`), and it gets the same fix: the anchor must
# match a line that is EXECUTED, so it requires the assignment token too.
X1=$(newtmp); mk_scout_copy "$X1"
ORIG="$SCOUT_LIB/scout-phasemap.sh"
MUT="$X1/scripts/lib/scout/scout-phasemap.sh"
anchor_sites=$(grep -c 'SCOUT-LADDER-MAX.*$' "$ORIG")
exec_sites=$(grep -c '_suggested="\$_rung".*# SCOUT-LADDER-MAX' "$ORIG")
_awk_inplace "$MUT" '
  { if (!done && index($0, "# SCOUT-LADDER-MAX") > 0 && index($0, "_suggested=\"$_rung\"") > 0) {
      print "    if [ \"$_sat\" -eq 1 ]; then _suggested=\"$_rung\"; fi"
      done = 1; next }
    print }'
chg=$(_changed_lines "$ORIG" "$MUT")
mut_sp=$(jqv "$(bash "$X1/scripts/scout.sh" --root "$LADDER" </dev/null 2>/dev/null)" '.phaseMap.suggestedPhase')
X1C=$(newtmp); mk_scout_copy "$X1C"
ctl_sp=$(jqv "$(bash "$X1C/scripts/scout.sh" --root "$LADDER" </dev/null 2>/dev/null)" '.phaseMap.suggestedPhase')
if [ "$chg" -eq 2 ] && [ "$mut_sp" = "4" ] && [ "$ctl_sp" = "2" ] \
   && [ "$exec_sites" -eq 1 ] && [ "$anchor_sites" -ge 1 ]; then
  pass "X1: last-wins restored (1 executed line of $anchor_sites marker mentions) -> the HANDOFF fixture reports 4; the unmutated control reports 2"
else
  fail_ "X1" "changed_lines=$chg (want 2) mutant_phase=$mut_sp (want 4) control_phase=$ctl_sp (want 2) executed_anchor_sites=$exec_sites (want exactly 1) total_marker_mentions=$anchor_sites"
fi

# ── X2: make a probe write state -> the read-only proof reds ──────────────
# The mutation re-introduces exactly what the extraction deleted: verify_init's
# `ensure_state_file` — a mkdir plus a state-file create at the top of the
# probe run. R1/R2 must go red on it, or they are decoration.
X2=$(newtmp); mk_scout_copy "$X2"
ORIG="$SCOUT_LIB/scout-reality.sh"
MUT="$X2/scripts/lib/scout/scout-reality.sh"
_awk_inplace "$MUT" '
  { print
    if (!done && $0 == "scout_reality_probes() {") {
      print "  mkdir -p \"$1/.claude\" 2>/dev/null; : > \"$1/.claude/process-state.json\" 2>/dev/null"
      done = 1 } }'
chg=$(_changed_lines "$ORIG" "$MUT")
RO=$(newtmp); mk_bare_fixture "$RO"
h_before=$(_tree_hash "$RO")
bash "$X2/scripts/scout.sh" --root "$RO" </dev/null >/dev/null 2>&1
h_mut=$(_tree_hash "$RO")
RO2=$(newtmp); mk_bare_fixture "$RO2"
h2_before=$(_tree_hash "$RO2")
scout_json "$RO2" >/dev/null
h2_after=$(_tree_hash "$RO2")
if [ "$chg" -eq 1 ] && [ "$h_before" != "$h_mut" ] && [ "$h2_before" = "$h2_after" ]; then
  pass "X2: a state-writing probe (1 inserted line) changes the fixture's tree hash; the unmutated control leaves it identical"
else
  fail_ "X2" "changed_lines=$chg (want 1) mutant_before=$h_before mutant_after=$h_mut control_equal=$([ "$h2_before" = "$h2_after" ] && echo yes || echo no)"
fi

# ── X3: make branch_protection consult anything -> its unknown pin reds ───
# The mutant restores the pre-2026-04-21 proxy check ("a CI yaml exists, so
# protection must be on"). It consults the filesystem rather than the host, so
# it is the MILDEST possible violation of "no host calls" — and V4 still has to
# catch it, because the property being defended is `unknown`, not `no network`.
#
# Anchored the same two-part way as X1, and for the same reason: the marker
# must resolve to the EXECUTED assignment, never to a line that merely names
# it. `bp_exec_sites` is the standing guard — if a future edit adds a prose
# citation, this case fails loudly instead of silently mutating a comment.
X3=$(newtmp); mk_scout_copy "$X3"
MUT="$X3/scripts/lib/scout/scout-reality.sh"
bp_exec_sites=$(grep -c '_bp_result="unknown".*# SCOUT-PROBE-BP-UNKNOWN' "$SCOUT_LIB/scout-reality.sh")
_awk_inplace "$MUT" '
  { if (!done && index($0, "# SCOUT-PROBE-BP-UNKNOWN") > 0 && index($0, "_bp_result=\"unknown\"") > 0) {
      print "  if [ -f \"$_root/.github/workflows/ci.yml\" ]; then _bp_result=\"pass\"; else _bp_result=\"unknown\"; fi"
      done = 1; next }
    print }'
chg=$(_changed_lines "$SCOUT_LIB/scout-reality.sh" "$MUT")
mut_bp=$(jqv "$(bash "$X3/scripts/scout.sh" --root "$NODE" </dev/null 2>/dev/null)" \
             '.reality.probes[] | select(.name=="branch_protection_configured") | .result')
if [ "$chg" -eq 2 ] && [ "$mut_bp" = "pass" ] && [ "$bp_n" = "unknown" ] && [ "$bp_exec_sites" -eq 1 ]; then
  pass "X3: a consulting branch_protection probe (1 line) reports pass; the unmutated control reports unknown"
else
  fail_ "X3" "changed_lines=$chg (want 2) mutant_result='$mut_bp' (want pass) control_result='$bp_n' (want unknown) executed_anchor_sites=$bp_exec_sites (want exactly 1)"
fi

# ── X4: source a core lib from Scout -> the REAL lint reds ────────────────
# M5's lexical half. The assertion is the shipped lint's exit code, run against
# a full copy of scripts/ so its vacuity floors are satisfied for real.
X4=$(newtmp)
cp -R "$REPO_ROOT/scripts" "$X4/scripts"
rc_ctl=0; bash "$MODLINT" --root "$X4" >/dev/null 2>&1 || rc_ctl=$?
# Derived, never hardcoded: the lint builds its forbidden set from the tree it
# is pointed at, so the mutation has to name a lib that tree actually has.
CORE_LIB_BASENAME=$(basename "$(ls "$X4/scripts/lib"/*.sh 2>/dev/null | head -1)")
before_lines=$(grep -c '' "$X4/scripts/lib/scout/scout-core.sh")
printf '%s\n' "source \"\$(dirname \"\$0\")/../$CORE_LIB_BASENAME\"" >> "$X4/scripts/lib/scout/scout-core.sh"
after_lines=$(grep -c '' "$X4/scripts/lib/scout/scout-core.sh")
added=$((after_lines - before_lines))
o=$(bash "$MODLINT" --root "$X4" 2>&1); rc_mut=$?
if [ "$added" -eq 1 ] && [ "$rc_ctl" -eq 0 ] && [ "$rc_mut" -eq 1 ] \
   && printf '%s' "$o" | grep -q 'M5'; then
  pass "X4: one source line added to a Scout lib -> lint-module-dependencies rc=1 on M5; the unmutated copy is rc=0"
else
  fail_ "X4" "added_lines=$added (want 1) control_rc=$rc_ctl (want 0) mutant_rc=$rc_mut (want 1); lint output:\n$o"
fi

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
