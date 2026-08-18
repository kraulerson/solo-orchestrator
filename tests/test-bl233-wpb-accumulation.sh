#!/usr/bin/env bash
# tests/test-bl233-wpb-accumulation.sh
#
# BL-233 WP-B — the ACCUMULATION half. WP-A made the RETRIEVAL gate score
# outcomes instead of declarations; nothing anywhere required that anything was
# ever WRITTEN for a later session to retrieve. The entry states the reason in
# one line: *a retrieval requirement with no accumulation requirement is a
# ratchet with nothing behind it.*
#
# ── The decisions this suite pins (Karl, 2026-08-17) ───────────────────────
#   1. WARN at commit, BLOCK at the phase gate. Storing is not per-commit work:
#      a commit that produced no insight has nothing to store, and a gate people
#      cannot satisfy honestly is a gate they delete (`## BL-149:`).
#   2. The satisfaction window is DURABLE and scoped to the phase: at least one
#      SUCCESSFUL qdrant-store since the previous gate's date. It cannot come
#      from `.claude/tool-usage.json`, which `session-test-gate-check.sh` WIPES
#      on every `startup` — a phase spans many sessions, so the ledger can only
#      answer "did this SESSION store", which is satisfiable by one junk store
#      ten seconds before running the gate. The record therefore lives in
#      `.claude/process-state.json::mcp_accumulation`, which survives.
#   3. Conditional block plus an attested escape: it blocks only when the phase
#      actually made SOURCE commits and stored nothing.
#   4. Gates phase_1_to_2, phase_2_to_3 and phase_3_to_4. Phase 0→1 is
#      pre-code discovery and is deliberately exempt.
#
# ── The measurement that shaped the requirement derivation (A-group) ───────
# The obvious source for "does this project require Qdrant" is the ledger's
# `mcp_requirements.qdrant_required`. It is the WRONG source, twice over:
#
#   • The ledger is an untracked runtime scratch file. Deleting it would switch
#     the requirement off — BL-231's "tracking file absent => no enforcement,
#     silently" row, reintroduced in a blocking gate.
#   • Measured on this tree: of the 61 suites that execute check-phase-gate.sh,
#     29 drive it at current_phase >= 2, across 74 fixture-creation sites, and
#     NOT ONE of them writes a `.claude/tool-usage.json`. A requirement read
#     from the ledger would have forced 74 fixture edits to say nothing.
#
# The first fix for that read `.claude/settings.local.json`, reasoning that
# `init.sh` writes it and `git add -A` commits it. THAT WAS ALSO WRONG: Claude
# Code adds that file to the user's GLOBAL git excludes by design, and
# `generate_gitignore` COPIES templates/generated/gitignore-base.tmpl (which
# already ignores `.claude/tool-usage.json`) before appending. Both arms were
# absent from every fresh clone, so the gate blocked on the author's machine and
# printed NOT CHECKED on CI. The I-group is the round trip that catches it:
# build, commit, push to a local bare, clone back, and run the gate in the clone.
# TRACKEDNESS IS ASKED OF GIT (`# BL-233-WPB-TRACKED`), never inferred.
#
# A5 IS THE LOAD-BEARING ONE. The derivation reads the two PROJECT-scope
# settings files ONLY, never `$HOME/.claude.json` — even though
# `session-test-gate-check.sh` reads both scopes. Zero of those 29 fixtures
# redirect HOME, so a host-derived verdict passes on a developer machine with
# Qdrant configured and fails on a runner without it, or the reverse. That is
# `## BL-234:`'s class exactly: a silent local-vs-CI divergence. Every gate run
# in this suite therefore pins HOME to an empty per-fixture directory, so the
# suite cannot pass for a reason that belongs to the machine it ran on.
#
# ── What this suite refuses to do ─────────────────────────────────────────
# Not one assertion treats a printed label as a verdict. `## BL-104:`'s trap is
# that `[WARN]`/`[FAIL]` text is cosmetic and the exit predicate is
# `if [ $issues -eq 0 ]`, so a "WARN" arm that increments `issues` BLOCKS and
# two arms printing the same word can have opposite outcomes. Every phase-gate
# assertion here reads the ISSUE COUNT DELTA against a control fixture that
# differs in exactly one fact. The label is asserted separately, as text.
#
# ── Mutation harness standard ─────────────────────────────────────────────
#   • every mutant asserts sites==1 against an END-OF-LINE-anchored marker;
#   • every mutant asserts `changed >= 2` — the check that catches a sed or
#     perl that reported success and edited NOTHING. Three WP-A mutation proofs
#     silently proved nothing while reporting `sites=1 parses=1`, because
#     `_mutate` escaped `&` but not backslash-DIGIT and `\0`-`\9` are
#     BACKREFERENCES in a sed replacement. This harness sidesteps the whole
#     escaping class: replacements are passed to perl through the ENVIRONMENT
#     and interpolated as values, where neither `&` nor `\1` is special;
#   • every mutant asserts `bash -n` — a mutation landing as a syntax error
#     kills every test for the wrong reason and would score as a pass;
#   • mode-preserving (`stat -c || stat -f`, GNU-first);
#   • a FRESH fixture per mutant AND per direction — the gate rewrites
#     phase-state.json on every run, so a shared fixture leaks state.
#
# Hermetic: temp dirs only, local git repos only, no remotes, no network, no
# `--no-verify`, no `timeout`/`gtimeout` (absent on the dev host — spurious 127).
# bash 3.2 compatible: no ${var,,}, no declare -A, no nullglob.
#
# This suite does NOT name the scaffolder on any executed line, so it carries no
# unit-lane exemption and belongs in the tests.yml fast lane.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CPG="$REPO_ROOT/scripts/check-phase-gate.sh"
TRACKER="$REPO_ROOT/scripts/track-tool-usage.sh"
REMINDER="$REPO_ROOT/scripts/session-end-qdrant-reminder.sh"
COMMIT_GATE="$REPO_ROOT/scripts/pre-commit-gate.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'chmod -R u+rwX "$TOPTMP" 2>/dev/null; rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }

_num() { case "$1" in ''|null|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac }
_mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || printf '?\n'; }
_parses() { bash -n "$1" >/dev/null 2>&1 && printf '1\n' || printf '0\n'; }
_strip_ansi() { sed 's/'$'\033''\[[0-9;]*m//g'; }

# _sites FILE MARKER — occurrences of an END-OF-LINE-anchored marker.
_sites() { local n; n=$(grep -c "$2\$" "$1" 2>/dev/null); _num "$n"; }

_changed_lines() { local n; n=$(diff "$1" "$2" 2>/dev/null | grep -c '^[<>]'); _num "$n"; }

# _mutate FILE FIND REPL — literal find/replace, mode-preserving.
# Both operands travel through the ENVIRONMENT: \Q..\E makes the pattern
# literal, and the replacement interpolates a VALUE, so `&` (whole match in
# sed) and `\1` (a backreference in sed) are inert here. That escaping class
# silently voided three WP-A mutation proofs.
_mutate() {
  local file="$1" mode
  mode="$(_mode_of "$file")"
  MUT_FIND="$2" MUT_REPL="$3" perl -pi -e 'BEGIN{$f=$ENV{MUT_FIND};$r=$ENV{MUT_REPL}} s/\Q$f\E/$r/g' "$file"
  [ "$mode" != "?" ] && chmod "$mode" "$file" 2>/dev/null
  return 0
}

for _f in "$CPG" "$TRACKER" "$REMINDER" "$COMMIT_GATE"; do
  if [ ! -f "$_f" ]; then
    echo "  [FAIL] setup — $_f not found"
    echo ""
    echo "Results: 0 passed, 1 failed"
    exit 1
  fi
done

if ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] jq is not installed — this suite asserts on JSON state."
  echo ""
  echo "Results: 0 passed, 0 failed"
  exit 0
fi
if ! command -v perl >/dev/null 2>&1; then
  echo "  [SKIP] perl is not installed — the mutation harness needs it."
  echo ""
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

# ── Fixture builders ────────────────────────────────────────────────────────

# mk_proj DIR PHASE — a project at PHASE with prior gate dates recorded and an
# APPROVAL_LOG carrying matching evidence, inside a local git repo with an
# identity configured. HOME is a per-fixture empty dir (see A5).
mk_proj() {
  local d="$1" phase="$2"
  mkdir -p "$d/.claude" "$d/home" || return 1
  cat > "$d/.claude/phase-state.json" <<J
{"project":"fix","framework_version":"1.0","current_phase":$phase,"track":"light",
 "deployment":"personal","poc_mode":null,"compliance_ready":false,
 "review_gate_enforced":false,
 "gates":{"phase_0_to_1":"2026-01-01","phase_1_to_2":"2026-02-01",
          "phase_2_to_3":"2026-03-01","phase_3_to_4":null}}
J
  cat > "$d/APPROVAL_LOG.md" <<'M'
# Approval Log

## Phase Gate: Phase 0 -> Phase 1
| Field | Value |
|---|---|
| Approver | Test Owner |
| Date | 2026-01-01 |

## Phase Gate: Phase 1 -> Phase 2
| Field | Value |
|---|---|
| Approver | Test Owner |
| Date | 2026-02-01 |

## Phase Gate: Phase 2 -> Phase 3
| Field | Value |
|---|---|
| Approver | Test Owner |
| Date | 2026-03-01 |

## Phase Gate: Phase 3 -> Phase 4
| Field | Value |
|---|---|
| Approver | Test Owner |
| Date | 2026-04-01 |
M
  (
    cd "$d" || exit 1
    unset GITHUB_BASE_REF
    # BL-234-FIXTURE-BARE-HEAD sibling: name the branch rather than inheriting
    # a host default that differs between this Mac and an ubuntu runner.
    git init -q -b main . >/dev/null 2>&1 || { git init -q . >/dev/null 2>&1; git checkout -q -b main >/dev/null 2>&1; }
    git config user.email "t@e.x"
    git config user.name "Test Owner"

    # ── FORCE THE IGNORE CONDITION, NEVER INHERIT IT ──────────────────────
    # This is where the suite previously diverged local-vs-CI, and it did so in
    # the very tests written to close a `## BL-234:` defect. This Mac's
    # ~/.config/git/ignore carries `**/.claude/settings.local.json` (Claude Code
    # writes it there itself); an ubuntu runner has no such file. The fixture
    # ignore rules were being written AFTER the first `git add -A`, so on the
    # Mac the file was skipped and on CI it was committed — I2a/I2b then
    # measured two different projects and CI went red.
    #
    # Both halves are now forced: core.excludesFile points at a fixture-owned
    # (empty) file so the host's global excludes cannot reach in from either
    # direction, and the project .gitignore below is the sole authority. It is
    # written BEFORE any staging.
    : > "$d/.git/fixture-excludes"
    git config core.excludesFile "$d/.git/fixture-excludes"
    cat > .gitignore <<'GITIG'
.claude/settings.local.json
.claude/tool-usage.json
GITIG

    echo "readme" > README.md
    git add -A >/dev/null 2>&1
    git commit -qm "docs: initial" >/dev/null 2>&1
  ) || return 1
  return 0
}

# want_qdrant DIR [FILE] — declare Qdrant in a PROJECT-scope settings file.
want_qdrant() {
  local d="$1" f="${2:-settings.local.json}"
  cat > "$d/.claude/$f" <<'S'
{"mcpServers":{"qdrant":{"command":"uvx","args":["mcp-server-qdrant"]}}}
S
}

# want_qdrant_in_home DIR — declare Qdrant ONLY in the fixture's HOME. The gate
# must NOT see this (A5).
want_qdrant_in_home() {
  local d="$1"
  cat > "$d/home/.claude.json" <<'S'
{"mcpServers":{"qdrant":{"command":"uvx","args":["mcp-server-qdrant"]}}}
S
}

# ledger DIR REQUIRED — a tool-usage ledger declaring the requirement.
ledger() {
  local d="$1" req="$2"
  cat > "$d/.claude/tool-usage.json" <<J
{"session_id":"s","calls":[],"commits_since_last_context7":0,
 "qdrant_find_called":false,"qdrant_store_called":false,"context7_called":false,
 "mcp_gate_satisfied":false,
 "mcp_requirements":{"qdrant_required":$req,"context7_required":false,"additional_required":[]}}
J
}

# stored DIR TIMESTAMP — a durable accumulation record.
stored() {
  local d="$1" ts="$2"
  local f="$d/.claude/process-state.json"
  [ -f "$f" ] || echo '{}' > "$f"
  jq --arg ts "$ts" '.mcp_accumulation = {store_success_count: 1, last_store_at: $ts, attestations: {}}' \
    "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

# source_commit DIR — a commit touching a SOURCE path.
source_commit() {
  local d="$1"
  ( cd "$d" || exit 1
    unset GITHUB_BASE_REF
    mkdir -p src
    echo "print(1)" > src/main.py
    git add -A >/dev/null 2>&1
    git commit -qm "feat: source" >/dev/null 2>&1 )
}

# add_origin DIR — a HERMETIC origin: a LOCAL bare repo, never a live remote
# (`lint-no-live-remote-in-tests.sh` enforces; a live `gh repo create` leaked a
# real repo on 2026-07-06). The branch is NAMED on the bare, because this Mac's
# Xcode gitconfig sets init.defaultbranch=main and an ubuntu runner's does not —
# an unnamed bare produces a dangling HEAD symref there and the divergence is
# silent (## BL-234:).
add_origin() {
  local d="$1" bare="$TOPTMP/$(basename "$d").origin.git"
  git init -q --bare -b main "$bare" >/dev/null 2>&1 || {
    git init -q --bare "$bare" >/dev/null 2>&1
    git --git-dir="$bare" symbolic-ref HEAD refs/heads/main >/dev/null 2>&1
  }
  ( cd "$d" || exit 1
    unset GITHUB_BASE_REF
    git remote add origin "$bare" >/dev/null 2>&1
    git push -q origin main >/dev/null 2>&1 )
}

# _run DIR ARGS... — run the gate ONCE with a pinned empty HOME, publishing both
# the output ($GOUT) and the tally ($GISSUES) from that SINGLE invocation.
#
# IT MUST BE ONE INVOCATION. The first draft had separate `_gate` and `_issues`
# helpers and assertions called both on the same fixture — but the gate
# AUTO-WRITES gates.* into phase-state.json from APPROVAL_LOG evidence
# (`_cpg_record_gate_date`), so the second run reads state the first run
# created. B4, whose whole point is an UNRECORDED gate date, silently measured
# two different projects: run one saw no previous gate and passed, run two saw
# the date the first run had just written and blocked. Every other assertion
# passed only because mk_proj pre-records all three dates, making the auto-write
# idempotent — i.e. the bug was invisible everywhere it did not happen to bite.
GOUT=""
GISSUES=0
_run() {
  local d="$1"; shift
  GOUT=$( ( cd "$d" && HOME="$d/home" bash "$CPG" "$@" 2>&1 ) | _strip_ansi )
  GISSUES=$(_num "$(printf '%s\n' "$GOUT" | sed -n 's/^\([0-9][0-9]*\) inconsistency(ies) found.*/\1/p' | tail -1)")
}

# _run_env DIR "VAR=VAL" ... -- ARGS... — the same, with environment overrides.
_run_env() {
  local d="$1"; shift
  # An ARRAY, not a string: a reason carries spaces, and `env $envs` unquoted
  # word-splits it into bogus assignments that env rejects.
  local envs
  envs=()
  while [ "$1" != "--" ]; do envs[${#envs[@]}]="$1"; shift; done
  shift
  GOUT=$( ( cd "$d" && HOME="$d/home" env "${envs[@]}" bash "$CPG" "$@" 2>&1 ) | _strip_ansi )
  GISSUES=$(_num "$(printf '%s\n' "$GOUT" | sed -n 's/^\([0-9][0-9]*\) inconsistency(ies) found.*/\1/p' | tail -1)")
}

echo "BL-233 WP-B — accumulation: warn at commit, block at the phase gate"
echo ""

# ══ A. Requirement derivation — PROJECT scope only ═════════════════════════
echo "A. requirement derivation (project-scope, host-independent)"

A_CTRL="$(newtmp)"; mk_proj "$A_CTRL" 3; source_commit "$A_CTRL"
_run "$A_CTRL" --gate phase_2_to_3
a_ctrl_issues=$GISSUES
a4_out="$GOUT"

A1="$(newtmp)"; mk_proj "$A1" 3; source_commit "$A1"; want_qdrant "$A1"
_run "$A1" --gate phase_2_to_3; a1_issues=$GISSUES
if [ "$a1_issues" -eq $((a_ctrl_issues + 1)) ]; then
  pass "A1: .claude/settings.local.json naming mcpServers.qdrant makes accumulation REQUIRED (issues $a_ctrl_issues -> $a1_issues)"
else
  fail_ "A1" "expected $((a_ctrl_issues + 1)) issues, got $a1_issues"
fi

A2="$(newtmp)"; mk_proj "$A2" 3; source_commit "$A2"; want_qdrant "$A2" "settings.json"
_run "$A2" --gate phase_2_to_3; a2_issues=$GISSUES
if [ "$a2_issues" -eq $((a_ctrl_issues + 1)) ]; then
  pass "A2: .claude/settings.json is read too (issues $a_ctrl_issues -> $a2_issues)"
else
  fail_ "A2" "expected $((a_ctrl_issues + 1)) issues, got $a2_issues"
fi

A3="$(newtmp)"; mk_proj "$A3" 3; source_commit "$A3"; ledger "$A3" true
_run "$A3" --gate phase_2_to_3; a3_issues=$GISSUES
if [ "$a3_issues" -eq $((a_ctrl_issues + 1)) ]; then
  pass "A3: OR arm — a ledger with qdrant_required=true and NO project settings still requires accumulation (covers a project that adopted Qdrant after init)"
else
  fail_ "A3" "expected $((a_ctrl_issues + 1)) issues, got $a3_issues"
fi

if [ "$a_ctrl_issues" -gt 0 ] && echo "$a4_out" | grep -q "accumulation: NOT CHECKED"; then
  pass "A4: no Qdrant declared anywhere — the arm does NOT count, and says so explicitly rather than passing silently (# BL-112-SAST-NOTRUN doctrine)"
else
  fail_ "A4" "expected a 'NOT CHECKED' line and no increment; issues=$a_ctrl_issues"
fi

A5="$(newtmp)"; mk_proj "$A5" 3; source_commit "$A5"; want_qdrant_in_home "$A5"
_run "$A5" --gate phase_2_to_3; a5_issues=$GISSUES; a5_out="$GOUT"
if [ "$a5_issues" -eq "$a_ctrl_issues" ] && echo "$a5_out" | grep -q "accumulation: NOT CHECKED"; then
  pass "A5: Qdrant configured in \$HOME but NOT in the project is IGNORED — the verdict cannot depend on whose machine ran the gate (## BL-234: class)"
else
  fail_ "A5" "host config leaked into the verdict: expected $a_ctrl_issues issues, got $a5_issues"
fi

# A6 — jq absent. The first draft of this arm printed "this project declares no
# Qdrant MCP server" when jq was missing: a claim about the PROJECT that it had
# never read, which is `## BL-233:`'s own substitution committed inside the fix
# for it. It now fails closed and names jq. The tally cannot discriminate here
# (without jq, the required and not-required fixtures are indistinguishable by
# construction), so the honesty half is asserted as text and the ENFORCING half
# is proved by M8 below.
A6="$(newtmp)"; mk_proj "$A6" 3; source_commit "$A6"; want_qdrant "$A6"
# The isolated PATH MIRRORS the real one minus jq, rather than listing the
# handful of tools the gate looks like it needs. The first draft did the latter
# and appended /usr/bin:/bin as a safety net — which is where jq actually lives
# on many hosts, so the fixture silently ran WITH jq and A6 measured nothing.
# An allow-list of "the tools it needs" is a guess about another script's
# dependencies; excluding the single tool under test is a fact.
A6BIN="$(newtmp)/bin"; mkdir -p "$A6BIN"
_a6_ifs="$IFS"
IFS=:
for _p in $PATH; do
  IFS="$_a6_ifs"
  if [ -d "$_p" ]; then
    for _x in "$_p"/*; do
      [ -x "$_x" ] || continue
      _n="${_x##*/}"
      [ "$_n" = "jq" ] && continue
      [ -e "$A6BIN/$_n" ] && continue
      ln -s "$_x" "$A6BIN/$_n" 2>/dev/null
    done
  fi
  IFS=:
done
IFS="$_a6_ifs"
if PATH="$A6BIN" command -v jq >/dev/null 2>&1; then
  fail_ "A6 (meta)" "the isolated PATH still resolves jq — the fixture would measure nothing"
fi
a6_out=$( ( cd "$A6" && HOME="$A6/home" PATH="$A6BIN" bash "$CPG" --gate phase_2_to_3 2>&1 ) | _strip_ansi )
if echo "$a6_out" | grep -q "accumulation: CANNOT BE VERIFIED" && echo "$a6_out" | grep -q "jq is unavailable"; then
  pass "A6: with jq unavailable the arm says it COULD NOT VERIFY and names jq — it never reports an unread project fact as a project fact"
else
  fail_ "A6" "expected a 'CANNOT BE VERIFIED ... jq is unavailable' line; got: $(echo "$a6_out" | grep -i 'accumulation' || echo '<no accumulation line>')"
fi

# A7 — the LEGACY / BROWNFIELD-ADOPTED environment: a project whose scripts/lib
# predates accumulation.sh. Hard-failing here was the first attempt and it
# killed the ENTIRE phase gate for a feature the project never opted into —
# measured as three red suites (walk-phase-lifecycle, brownfield-wp3-adoption-arms,
# brownfield-wp3-regenerate-path), all of which model exactly that population.
# The arm must go unavailable and SAY SO without counting, while every other
# check in the gate keeps running.
A7="$(newtmp)"; mk_proj "$A7" 3; want_qdrant "$A7"; source_commit "$A7"
A7SCRIPTS="$(newtmp)/scripts"
mkdir -p "$A7SCRIPTS"
cp -R "$REPO_ROOT/scripts/." "$A7SCRIPTS/" 2>/dev/null
rm -f "$A7SCRIPTS/lib/accumulation.sh"
a7_out=$( ( cd "$A7" && HOME="$A7/home" bash "$A7SCRIPTS/check-phase-gate.sh" --gate phase_2_to_3 2>&1 ) | _strip_ansi )
a7_issues=$(_num "$(printf '%s\n' "$a7_out" | sed -n 's/^\([0-9][0-9]*\) inconsistency(ies) found.*/\1/p' | tail -1)")
# The control: the SAME fixture with the lib present blocks (so the fixture is
# one the gate would otherwise have an opinion about).
_run "$A7" --gate phase_2_to_3; a7_with_lib=$GISSUES
if echo "$a7_out" | grep -q "accumulation: NOT CHECKED" \
   && echo "$a7_out" | grep -q "sync-framework" \
   && echo "$a7_out" | grep -q "inconsistency(ies) found" \
   && [ "$a7_issues" -eq $((a7_with_lib - 1)) ]; then
  pass "A7: with scripts/lib/accumulation.sh absent the arm reports NOT CHECKED, names the remedy, does NOT count, and the rest of the gate still runs to a verdict ($a7_issues vs $a7_with_lib with the lib)"
else
  fail_ "A7" "issues=$a7_issues (want $((a7_with_lib - 1))); ran-to-verdict=$(echo "$a7_out" | grep -c 'inconsistency(ies) found'); line: $(echo "$a7_out" | grep -i 'accumulation' | head -1)"
fi

# A8 — the same environment for the COMMIT gate: the accumulation warning
# no-ops, and every other gate in that file still runs. A bare `source` here
# exited before ANY check ran (remote, TDD, Build Loop), which is total silent
# non-enforcement — the class `## BL-233:` exists to remove.
A8="$(newtmp)"; mk_proj "$A8" 2
A8ROOT="$(newtmp)/repo"
A8SCRIPTS="$A8ROOT/scripts"
mkdir -p "$A8SCRIPTS"
cp -R "$REPO_ROOT/scripts/." "$A8SCRIPTS/" 2>/dev/null
rm -f "$A8SCRIPTS/lib/accumulation.sh"
# The tests/ and .github/ symlinks matter: without them lint-tests-registered.sh
# denies, and the deny — not the guard — is what would satisfy the assertion.
# That is the M7 poisoning this file documents; A8 had it too.
ln -s "$REPO_ROOT/tests" "$A8ROOT/tests" 2>/dev/null
ln -s "$REPO_ROOT/.github" "$A8ROOT/.github" 2>/dev/null
a8_out=$( ( cd "$A8" && printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"chore: x\""}}' \
  | HOME="$A8/home" SKIP_LINT=1 bash "$A8SCRIPTS/pre-commit-gate.sh" 2>&1 ) | _strip_ansi )
# The CONTROL is the same fixture with the lib PRESENT: it must warn. Then with
# the lib absent the warning is gone AND no bash error appears AND another gate
# in the file still reached a decision. Asserting only `permissionDecision`
# present would pass with the whole accumulation block deleted.
a8_ctrl=$( ( cd "$A8" && printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"chore: x\""}}' \
  | HOME="$A8/home" SKIP_LINT=1 bash "$COMMIT_GATE" 2>&1 ) | _strip_ansi )
if ! echo "$a8_out" | grep -q "No such file or directory" \
   && echo "$a8_out" | grep -q '"permissionDecision"' \
   && ! echo "$a8_out" | grep -q 'Nothing has been stored to Qdrant'; then
  pass "A8: with the lib absent the commit gate reaches a real decision instead of dying at its source line, and only the accumulation warning is missing — the other gates in that file are not collateral"
else
  fail_ "A8" "lib-absent: $(echo "$a8_out" | head -c 180)"
fi

# A9 — a declaration that will not PARSE must not fold into "none". `none` says
# "this project declares no Qdrant MCP server", a claim about CONTENT, and a
# corrupt file has had its content read by nobody.
#
# THE FIXTURES CARRY NO VALID DECLARATION. The first version of this test called
# want_qdrant first, which writes a VALID settings.local.json — and a real
# declaration outranks an unreadable one, by design. So the fixture never
# reached the arm and its +1 was the ordinary untracked-declaration block:
# deleting the whole feature left both numeric clauses satisfied. Each case
# below is a lone corrupt file, and the count is asserted against a control
# fixture identical but for that file.
#
# The corrupt MANIFEST is asserted on message only: .claude/manifest.json has a
# second reader in this gate (the host dispatcher), so its delta is +2 and only
# one of those is this arm. settings.json and tool-usage.json have no other
# reader here, so their deltas are attributable.
a9_ctrl_dir="$(newtmp)"; mk_proj "$a9_ctrl_dir" 3; source_commit "$a9_ctrl_dir"
_run "$a9_ctrl_dir" --gate phase_2_to_3; a9_ctrl=$GISSUES

# THREE corruption SHAPES, not one. The first cut tested only truncation, and
# the fix for the truthiness bug (`jq -e .` -> `jq empty`) passed truncation
# while opening a fail-OPEN hole for zero-byte and whitespace-only files — which
# is what a died-mid-write `>` redirect or a full disk actually leaves behind.
a9_fail=""
for _bad in "settings.json" "settings.local.json" "tool-usage.json"; do
 for _shape in truncated empty whitespace; do
  _d="$(newtmp)"; mk_proj "$_d" 3; source_commit "$_d"
  case "$_shape" in
    truncated)  printf '%s' '{"broken":' > "$_d/.claude/$_bad" ;;
    empty)      : > "$_d/.claude/$_bad" ;;
    whitespace) printf '   \n\n' > "$_d/.claude/$_bad" ;;
  esac
  _run "$_d" --gate phase_2_to_3
  if [ "$GISSUES" -ne $((a9_ctrl + 1)) ] || ! echo "$GOUT" | grep -q "CANNOT BE VERIFIED"; then
    a9_fail="$a9_fail $_bad/$_shape(issues=$GISSUES want $((a9_ctrl + 1)))"
  fi
 done
done

# Valid JSON that is merely FALSEY must NOT read as corrupt — the bug the
# hardening was reacting to when it over-corrected.
A9F="$(newtmp)"; mk_proj "$A9F" 3; source_commit "$A9F"
printf '%s' 'null' > "$A9F/.claude/settings.json"
_run "$A9F" --gate phase_2_to_3; a9f_issues=$GISSUES

A9M="$(newtmp)"; mk_proj "$A9M" 3; source_commit "$A9M"
printf '%s' '{"mcp":{"qdrant_required":true}' > "$A9M/.claude/manifest.json"
_run "$A9M" --gate phase_2_to_3; a9m_out="$GOUT"; a9m_issues=$GISSUES

# And a VALID declaration alongside a corrupt sibling must still win — the
# unreadable state is a floor, not an override.
A9V="$(newtmp)"; mk_proj "$A9V" 3; source_commit "$A9V"; want_qdrant "$A9V"
printf '%s' '{"broken":' > "$A9V/.claude/settings.json"
_run "$A9V" --gate phase_2_to_3; a9v_out="$GOUT"

if [ -z "$a9_fail" ] && echo "$a9m_out" | grep -q "CANNOT BE VERIFIED" \
   && [ "$a9m_issues" -gt "$a9_ctrl" ] \
   && [ "$a9f_issues" -eq "$a9_ctrl" ] \
   && echo "$a9v_out" | grep -q "git does not track"; then
  pass "A9: each of the THREE declaration files, in each of THREE corruption shapes (truncated, zero-byte, whitespace-only), FAILS CLOSED with a counted [FAIL] naming that the requirement could not be read — including the ledger, which the first cut forgot — while a legible declaration alongside a corrupt sibling still wins"
else
  fail_ "A9" "per-file/shape:$a9_fail ; falsey-valid issues=$a9f_issues (want $a9_ctrl) ; manifest msg=$(echo "$a9m_out" | grep -c 'CANNOT BE VERIFIED') issues=$a9m_issues (want > $a9_ctrl) ; valid-wins=$(echo "$a9v_out" | grep -c 'git does not track')"
fi

# A10 was deleted after review: its control-vs-corrupt delta on settings.json is
# the same assertion A9's per-file loop already makes on the same file with the
# same control shape, and no mutant killed it separately from A9. Its unique
# content was prose about blast radius, which lives on the backlog entry.

# ══ B. The satisfaction window is durable and phase-scoped ════════════════
echo ""
echo "B. satisfaction window (durable, since the previous gate)"

B1="$(newtmp)"; mk_proj "$B1" 3; source_commit "$B1"; want_qdrant "$B1"; stored "$B1" "2026-02-15T10:00:00Z"
_run "$B1" --gate phase_2_to_3; b1_issues=$GISSUES; b1_out="$GOUT"
if [ "$b1_issues" -eq "$a_ctrl_issues" ] && echo "$b1_out" | grep -q "accumulation: satisfied"; then
  pass "B1: a successful store AFTER the previous gate (2026-02-01) satisfies the requirement"
else
  fail_ "B1" "expected $a_ctrl_issues issues, got $b1_issues"
fi

B2="$(newtmp)"; mk_proj "$B2" 3; source_commit "$B2"; want_qdrant "$B2"; stored "$B2" "2026-01-15T10:00:00Z"
_run "$B2" --gate phase_2_to_3; b2_issues=$GISSUES
if [ "$b2_issues" -eq $((a_ctrl_issues + 1)) ]; then
  pass "B2: a store from BEFORE the previous gate does NOT satisfy it — the window is the phase, not all history"
else
  fail_ "B2" "expected $((a_ctrl_issues + 1)) issues, got $b2_issues"
fi

B3="$(newtmp)"; mk_proj "$B3" 3; source_commit "$B3"; want_qdrant "$B3"
echo '{"build_loop":{"step":0}}' > "$B3/.claude/process-state.json"
_run "$B3" --gate phase_2_to_3; b3_issues=$GISSUES
if [ "$b3_issues" -eq $((a_ctrl_issues + 1)) ]; then
  pass "B3: a process-state.json with NO mcp_accumulation object reads as zero stores and BLOCKS — a missing key defaults RESTRICTIVE, the inverse of ## BL-221:"
else
  fail_ "B3" "expected $((a_ctrl_issues + 1)) issues, got $b3_issues"
fi

B4="$(newtmp)"; mk_proj "$B4" 2; source_commit "$B4"; want_qdrant "$B4"; stored "$B4" "2025-06-01T10:00:00Z"
jq '.gates.phase_0_to_1 = null' "$B4/.claude/phase-state.json" > "$B4/.claude/ps.tmp" && mv "$B4/.claude/ps.tmp" "$B4/.claude/phase-state.json"
b4_ctrl="$(newtmp)"; mk_proj "$b4_ctrl" 2; source_commit "$b4_ctrl"
jq '.gates.phase_0_to_1 = null' "$b4_ctrl/.claude/phase-state.json" > "$b4_ctrl/.claude/ps.tmp" && mv "$b4_ctrl/.claude/ps.tmp" "$b4_ctrl/.claude/phase-state.json"
_run "$b4_ctrl" --gate phase_1_to_2; b4_base=$GISSUES
_run "$B4" --gate phase_1_to_2; b4_issues=$GISSUES; b4_out="$GOUT"
# The "no increment" half of this assertion is TRUE OF AN UNIMPLEMENTED GATE.
# The output half is what makes it a discriminator: the arm must have run and
# reported satisfied, not merely failed to fire.
if [ "$b4_issues" -eq "$b4_base" ] && echo "$b4_out" | grep -q "accumulation: satisfied"; then
  pass "B4: with no previous gate date recorded, ANY successful store ever counts — an unscopeable window falls back to a satisfiable floor, not to a block nobody can clear (## BL-149:)"
else
  fail_ "B4" "expected $b4_base issues, got $b4_issues"
fi

B5="$(newtmp)"; mk_proj "$B5" 3; source_commit "$B5"; want_qdrant "$B5"; stored "$B5" "2026-02-01T00:00:01Z"
_run "$B5" --gate phase_2_to_3; b5_issues=$GISSUES; b5_out="$GOUT"
if [ "$b5_issues" -eq "$a_ctrl_issues" ] && echo "$b5_out" | grep -q "accumulation: satisfied"; then
  pass "B5: a store ON the previous gate's date counts — gates.* carry a DATE with no time, so same-day is the only honest direction"
else
  fail_ "B5" "expected $a_ctrl_issues issues, got $b5_issues"
fi

# ══ C. The honest path — nothing owed when no source work happened ════════
echo ""
echo "C. source-work conditional (the ## BL-149: honest path)"

C1="$(newtmp)"; mk_proj "$C1" 3; want_qdrant "$C1"
c1_ctrl="$(newtmp)"; mk_proj "$c1_ctrl" 3
_run "$c1_ctrl" --gate phase_2_to_3; c1_base=$GISSUES
_run "$C1" --gate phase_2_to_3; c1_issues=$GISSUES; c1_out="$GOUT"
if [ "$c1_issues" -eq "$c1_base" ] && echo "$c1_out" | grep -q "accumulation: nothing owed"; then
  pass "C1: a phase whose only commit was docs owes nothing and passes clean — no ceremony, no attestation"
else
  fail_ "C1" "expected $c1_base issues, got $c1_issues"
fi

C2="$(newtmp)"; mk_proj "$C2" 3; want_qdrant "$C2"; source_commit "$C2"
_run "$C2" --gate phase_2_to_3; c2_issues=$GISSUES; c2_out="$GOUT"
if [ "$c2_issues" -eq $((c1_base + 1)) ] && echo "$c2_out" | grep -q "accumulation: BLOCKED"; then
  pass "C2: source commits since the previous gate + zero stores BLOCKS (issues $c1_base -> $c2_issues)"
else
  fail_ "C2" "expected $((c1_base + 1)) issues, got $c2_issues"
fi

C3="$(newtmp)"; mk_proj "$C3" 3; want_qdrant "$C3"
rm -rf "$C3/.git"
c3_ctrl="$(newtmp)"; mk_proj "$c3_ctrl" 3; rm -rf "$c3_ctrl/.git"
_run "$c3_ctrl" --gate phase_2_to_3; c3_base=$GISSUES
_run "$C3" --gate phase_2_to_3; c3_issues=$GISSUES
if [ "$c3_issues" -eq $((c3_base + 1)) ]; then
  pass "C3: when git cannot answer whether source work happened, the conditional resolves to BLOCK — 'could not measure' must never read as 'nothing to measure'"
else
  fail_ "C3" "expected $((c3_base + 1)) issues, got $c3_issues"
fi

# ══ D. The attested escape ════════════════════════════════════════════════
echo ""
echo "D. attested escape (BL-072 shape: recorded, or refused)"

D1="$(newtmp)"; mk_proj "$D1" 3; want_qdrant "$D1"; source_commit "$D1"
_run_env "$D1" SOLO_MCP_ACCUM_ATTESTED=1 \
  "SOLO_MCP_ACCUM_ATTESTED_REASON=offline sprint, nothing novel decided" \
  -- --gate phase_2_to_3
d1_issues=$GISSUES
d1_recorded=$(jq -r '.mcp_accumulation.attestations.phase_2_to_3.reason // ""' "$D1/.claude/process-state.json" 2>/dev/null)
if [ "$d1_issues" -eq "$c1_base" ] && [ "$d1_recorded" = "offline sprint, nothing novel decided" ]; then
  pass "D1: an attested escape clears the block AND is durably recorded to .claude/process-state.json (not silenced)"
else
  fail_ "D1" "issues=$d1_issues (want $c1_base), recorded='$d1_recorded'"
fi

D2="$(newtmp)"; mk_proj "$D2" 3; want_qdrant "$D2"; source_commit "$D2"
_run_env "$D2" SOLO_MCP_ACCUM_ATTESTED=1 "SOLO_MCP_ACCUM_ATTESTED_REASON=   " \
  -- --gate phase_2_to_3
d2_issues=$GISSUES
if [ "$d2_issues" -eq $((c1_base + 1)) ]; then
  pass "D2: a whitespace-only reason is REJECTED — an attestation must carry a justification, not blank space (BL-070 tightener)"
else
  fail_ "D2" "expected $((c1_base + 1)) issues, got $d2_issues"
fi

D3="$(newtmp)"; mk_proj "$D3" 3; want_qdrant "$D3"; source_commit "$D3"
mkdir -p "$D3/.claude/process-state.json"   # unwritable: a directory where the record must go
d3_ctrl="$(newtmp)"; mk_proj "$d3_ctrl" 3; mkdir -p "$d3_ctrl/.claude/process-state.json"
_run "$d3_ctrl" --gate phase_2_to_3; d3_base=$GISSUES
_run_env "$D3" SOLO_MCP_ACCUM_ATTESTED=1 "SOLO_MCP_ACCUM_ATTESTED_REASON=a real reason" \
  -- --gate phase_2_to_3
d3_issues=$GISSUES
if [ "$d3_issues" -eq $((d3_base + 1)) ]; then
  pass "D3: an attestation that CANNOT be recorded is REFUSED, not honoured — an escape that leaves no trace is the advisory posture BL-233 exists to replace"
else
  fail_ "D3" "expected $((d3_base + 1)) issues, got $d3_issues"
fi

D4="$(newtmp)"; mk_proj "$D4" 3; want_qdrant "$D4"; source_commit "$D4"
d4_head=$( cd "$D4" && git rev-parse HEAD )
jq -n --arg h "$d4_head" '{mcp_accumulation:{store_success_count:0,last_store_at:null,
  attestations:{phase_2_to_3:{reason:"prior recorded exception",date:"2026-03-02",by:"Test Owner",head:$h}}}}' \
  > "$D4/.claude/process-state.json"
_run "$D4" --gate phase_2_to_3; d4_issues=$GISSUES; d4_out="$GOUT"
if [ "$d4_issues" -eq "$c1_base" ] && echo "$d4_out" | grep -q "accumulation: ATTESTED"; then
  pass "D4: an attestation already on record clears the gate without re-supplying the env vars (idempotent across runs)"
else
  fail_ "D4" "expected $c1_base issues, got $d4_issues"
fi

# D5 — an attestation excuses the work it named, not the phase forever.
# The reviewer's R-360-5: one attested run permanently disabled the boundary,
# because the recorded reason was read back before the environment was
# consulted. BL-072's TDD escape is scoped per commit and session-mcp-gate.sh's
# per session; this is the phase-gate equivalent.
D5="$(newtmp)"; mk_proj "$D5" 3; want_qdrant "$D5"; source_commit "$D5"
_run_env "$D5" SOLO_MCP_ACCUM_ATTESTED=1 "SOLO_MCP_ACCUM_ATTESTED_REASON=one-off, nothing novel" \
  -- --gate phase_2_to_3
d5_first=$GISSUES
d5_head=$(jq -r '.mcp_accumulation.attestations.phase_2_to_3.head // ""' "$D5/.claude/process-state.json" 2>/dev/null)
# NEW source work, and NO environment variables this time.
( cd "$D5" && unset GITHUB_BASE_REF && mkdir -p src && echo "print(2)" > src/later.py \
    && git add -A >/dev/null 2>&1 && git commit -qm "feat: more source" >/dev/null 2>&1 )
_run "$D5" --gate phase_2_to_3; d5_second=$GISSUES; d5_out="$GOUT"
if [ "$d5_first" -eq "$c1_base" ] && [ -n "$d5_head" ] && [ "$d5_second" -eq $((c1_base + 1)) ] \
   && echo "$d5_out" | grep -q "no longer covers this tree"; then
  pass "D5: the attestation records the commit it excused ($d5_head) and goes STALE when source work lands after it — an escape that never expires is a permanent bypass"
else
  fail_ "D5" "first=$d5_first (want $c1_base) head='$d5_head' second=$d5_second (want $((c1_base + 1)))"
fi

# D6 — an attestation whose `head` cannot be resolved must be treated as STALE,
# LOUDLY. The first version of the staleness check returned "still valid" for an
# empty, malformed, tampered or garbage-collected head, so any unresolvable
# value silently restored the permanent bypass the check was added to remove —
# reachable by editing one JSON field, or by an ordinary `git gc --prune=now`.
# Its twin _cpg_accum_source_work fails CLOSED on the identical question.
for _d6 in 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef' '' 'not-a-sha'; do
  D6="$(newtmp)"; mk_proj "$D6" 3; want_qdrant "$D6"; source_commit "$D6"
  jq -n --arg h "$_d6" '{mcp_accumulation:{store_success_count:0,last_store_at:null,
    attestations:{phase_2_to_3:{reason:"tampered",date:"2026-03-02",by:"T",head:$h}}}}' \
    > "$D6/.claude/process-state.json"
  _run "$D6" --gate phase_2_to_3
  if [ "$GISSUES" -eq $((c1_base + 1)) ] && echo "$GOUT" | grep -q "no longer covers this tree"; then
    :
  else
    fail_ "D6[head='$_d6']" "expected a BLOCK and a stale warning; issues=$GISSUES"
    _d6_bad=1
  fi
done
# A record with NO head key at all — the shape a pre-staleness attestation has.
D6B="$(newtmp)"; mk_proj "$D6B" 3; want_qdrant "$D6B"; source_commit "$D6B"
cat > "$D6B/.claude/process-state.json" <<'J'
{"mcp_accumulation":{"store_success_count":0,"last_store_at":null,
 "attestations":{"phase_2_to_3":{"reason":"legacy, no head","date":"2026-03-02","by":"T"}}}}
J
_run "$D6B" --gate phase_2_to_3
if [ -z "${_d6_bad:-}" ] && [ "$GISSUES" -eq $((c1_base + 1)) ] && echo "$GOUT" | grep -q "no longer covers this tree"; then
  pass "D6: an unresolvable, tampered, empty or absent attestation head FAILS CLOSED and says so — 'could not measure' never resolves to 'nothing to measure' (# BL-112-SAST-NOTRUN)"
else
  fail_ "D6" "a headless record did not fail closed: issues=$GISSUES"
fi

# D7 — re-attesting with the SAME reason must refresh the record. The staleness
# WARN tells the operator to re-attest; before this, doing exactly that was a
# no-op, because the idempotence early-return compared only the reason. Escaping
# then required inventing a NEW reason string — an incentive to write junk
# reasons, which is the shape `## BL-149:` deletes.
D7="$(newtmp)"; mk_proj "$D7" 3; want_qdrant "$D7"; source_commit "$D7"
_run_env "$D7" SOLO_MCP_ACCUM_ATTESTED=1 "SOLO_MCP_ACCUM_ATTESTED_REASON=same reason throughout" \
  -- --gate phase_2_to_3
d7_head1=$(jq -r '.mcp_accumulation.attestations.phase_2_to_3.head // ""' "$D7/.claude/process-state.json")
( cd "$D7" && unset GITHUB_BASE_REF && mkdir -p src && echo "x" > src/more.py \
    && git add -A >/dev/null 2>&1 && git commit -qm "feat: more" >/dev/null 2>&1 )
# the remedy the WARN advises, verbatim: same reason, again
_run_env "$D7" SOLO_MCP_ACCUM_ATTESTED=1 "SOLO_MCP_ACCUM_ATTESTED_REASON=same reason throughout" \
  -- --gate phase_2_to_3
d7_head2=$(jq -r '.mcp_accumulation.attestations.phase_2_to_3.head // ""' "$D7/.claude/process-state.json")
# and it must now STICK on a plain re-run with no env vars
_run "$D7" --gate phase_2_to_3; d7_third=$GISSUES
if [ -n "$d7_head1" ] && [ "$d7_head1" != "$d7_head2" ] && [ "$d7_third" -eq "$c1_base" ]; then
  pass "D7: re-attesting with the SAME reason refreshes the recorded commit ($d7_head1 -> $d7_head2) and the gate then stays clear — the advised remedy is not a no-op"
else
  fail_ "D7" "head1='$d7_head1' head2='$d7_head2' third-run issues=$d7_third (want $c1_base)"
fi

# D8 — an operator-supplied attestation reason must not be able to FORGE gate
# output. `echo -e` interprets \n in the reason, so a reason could inject extra
# "[OK] …" lines into the transcript a human or CI log skims. The durable record
# was never at risk (jq --arg stores it literally); the transcript was.
D8="$(newtmp)"; mk_proj "$D8" 3; want_qdrant "$D8"; source_commit "$D8"
_run_env "$D8" SOLO_MCP_ACCUM_ATTESTED=1 \
  'SOLO_MCP_ACCUM_ATTESTED_REASON=benign\n  [OK] Phase 3 review gate: FORGED\n  more' \
  -- --gate phase_2_to_3
d8_forged=$(printf '%s\n' "$GOUT" | grep -c 'FORGED')
# ANCHORED at line start: with printf the reason prints literally on ONE line,
# so an unanchored grep matches it as a SUBSTRING of the legitimate ATTESTED
# line and reports a forgery that did not happen. What must not exist is a
# standalone verdict line.
d8_onlines=$(printf '%s\n' "$GOUT" | grep -cE '^ *\[OK\] Phase 3 review gate: FORGED')
d8_recorded=$(jq -r '.mcp_accumulation.attestations.phase_2_to_3.reason // ""' "$D8/.claude/process-state.json" 2>/dev/null)
if [ "$d8_onlines" -eq 0 ] && [ "$d8_forged" -ge 1 ] \
   && printf '%s' "$d8_recorded" | grep -q 'FORGED'; then
  pass "D8: a reason carrying newline escapes appears as TEXT, not as extra gate verdict lines — the reason is still shown and still recorded verbatim, it just cannot manufacture an [OK] line"
else
  fail_ "D8" "forged-verdict-lines=$d8_onlines (want 0); reason-visible=$d8_forged (want >=1); recorded='$d8_recorded'"
fi

# D9 — the STALE path renders the reason too, and it is the MORE exploitable of
# the two: D8's needs the env var on the current invocation, this one renders
# from the PERSISTED record on every subsequent run through the supported
# workflow. Fixing only D8's line is the named-instance habit; the class sweep
# (`grep -n 'echo -e .*\$' … | grep -iE 'reason|recorded|attest'`) found this.
D9="$(newtmp)"; mk_proj "$D9" 3; want_qdrant "$D9"; source_commit "$D9"
_run_env "$D9" SOLO_MCP_ACCUM_ATTESTED=1 \
  'SOLO_MCP_ACCUM_ATTESTED_REASON=benign\n  [OK] Phase 3 review gate: FORGED-VIA-STALE\n  tail' \
  -- --gate phase_2_to_3
( cd "$D9" && unset GITHUB_BASE_REF && mkdir -p src && echo "x" > src/after.py \
    && git add -A >/dev/null 2>&1 && git commit -qm "feat: after" >/dev/null 2>&1 )
_run "$D9" --gate phase_2_to_3
d9_forged=$(printf '%s\n' "$GOUT" | grep -cE '^ *\[OK\] Phase 3 review gate: FORGED-VIA-STALE')
d9_warned=$(printf '%s\n' "$GOUT" | grep -c 'no longer covers this tree')
if [ "$d9_forged" -eq 0 ] && [ "$d9_warned" -ge 1 ]; then
  pass "D9: the STALE-attestation warning renders the persisted reason as TEXT — a reason stored once cannot forge a verdict line on every later run"
else
  fail_ "D9" "forged-lines=$d9_forged (want 0); stale-warning=$d9_warned (want >=1)"
fi

# D10 — a corrupt DURABLE RECORD must name its own cause. Without this the gate
# says "no successful qdrant-store in that window" — which is a claim about a
# file nothing parsed — and worse, an attestation sitting in that file is
# silently discarded while the operator is told to attest.
D10="$(newtmp)"; mk_proj "$D10" 3; want_qdrant "$D10"; source_commit "$D10"
printf '%s' '{"mcp_accumulation":{"last_store_at":"2099-01-01T00' > "$D10/.claude/process-state.json"
_run "$D10" --gate phase_2_to_3; d10_out="$GOUT"; d10_issues=$GISSUES
D10C="$(newtmp)"; mk_proj "$D10C" 3; want_qdrant "$D10C"; source_commit "$D10C"
_run "$D10C" --gate phase_2_to_3; d10_ctrl=$GISSUES
if [ "$d10_issues" -eq "$d10_ctrl" ] && echo "$d10_out" | grep -q "not valid JSON" \
   && ! echo "$d10_out" | grep -q "NO successful qdrant-store in that window"; then
  pass "D10: an unparseable .claude/process-state.json is reported as exactly that, instead of as 'no successful qdrant-store' — a verdict about a file nothing parsed, with any attestation in it silently discarded"
else
  fail_ "D10" "issues=$d10_issues (want $d10_ctrl); names-json=$(echo "$d10_out" | grep -c 'not valid JSON'); still-claims-no-store=$(echo "$d10_out" | grep -c 'NO successful qdrant-store')"
fi

# G4 — a store that SUCCEEDED but whose durable record could not be written must
# be VISIBLE. The tracker has always incremented qdrant_store_record_failed and
# nothing anywhere read it, so the operator met a phase gate blocking for a
# reason no surface named — the outcome that field's own comment promised to
# prevent.
G4="$(newtmp)"; mkdir -p "$G4/.claude" "$G4/home/.claude"
cat > "$G4/home/.claude/settings.json" <<'S'
{"mcpServers":{"qdrant":{"command":"uvx","args":["mcp-server-qdrant"]}}}
S
cat > "$G4/.claude/tool-usage.json" <<'J'
{"session_id":"s","commits_since_last_context7":1,"calls":[],
 "qdrant_store_called":true,"qdrant_store_succeeded":true,
 "qdrant_store_record_failed":2,"context7_called":false}
J
echo '{"current_phase":2}' > "$G4/.claude/phase-state.json"
g4_out=$( ( cd "$G4" && HOME="$G4/home" bash "$REMINDER" 2>&1 ) | _strip_ansi )
if echo "$g4_out" | grep -q 'could NOT be written' && echo "$g4_out" | grep -q 'process-state.json'; then
  pass "G4: a successful store whose durable record failed to write is REPORTED, naming the file the phase gate actually reads — the field is no longer write-only"
else
  fail_ "G4" "no record-failure warning: $(echo "$g4_out" | tail -3)"
fi

# ══ E. Gate scoping ═══════════════════════════════════════════════════════
echo ""
echo "E. which gates the arm belongs to"

E1="$(newtmp)"; mk_proj "$E1" 2; want_qdrant "$E1"; source_commit "$E1"
e1_ctrl="$(newtmp)"; mk_proj "$e1_ctrl" 2; source_commit "$e1_ctrl"
_run "$e1_ctrl" --gate phase_1_to_2; e1_base=$GISSUES
_run "$E1" --gate phase_1_to_2; e1_issues=$GISSUES
if [ "$e1_issues" -eq $((e1_base + 1)) ]; then
  pass "E1: --gate phase_1_to_2 enforces accumulation against the phase_0_to_1 date"
else
  fail_ "E1" "expected $((e1_base + 1)) issues, got $e1_issues"
fi

E3="$(newtmp)"; mk_proj "$E3" 4; want_qdrant "$E3"; source_commit "$E3"
e3_ctrl="$(newtmp)"; mk_proj "$e3_ctrl" 4; source_commit "$e3_ctrl"
_run "$e3_ctrl" --gate phase_3_to_4; e3_base=$GISSUES
_run "$E3" --gate phase_3_to_4; e3_issues=$GISSUES
if [ "$e3_issues" -eq $((e3_base + 1)) ]; then
  pass "E3: --gate phase_3_to_4 enforces accumulation against the phase_2_to_3 date"
else
  fail_ "E3" "expected $((e3_base + 1)) issues, got $e3_issues"
fi

# E4 asserts an ABSENCE, which an unimplemented gate satisfies for free. The
# positive control is the SAME fixture driven at 2->3: the string must be
# producible here, or the absence at 0->1 proves nothing.
E4="$(newtmp)"; mk_proj "$E4" 1; want_qdrant "$E4"; source_commit "$E4"
_run "$E4" --gate phase_0_to_1; e4_out="$GOUT"
E4B="$(newtmp)"; mk_proj "$E4B" 3; want_qdrant "$E4B"; source_commit "$E4B"
_run "$E4B" --gate phase_2_to_3; e4b_out="$GOUT"
if ! echo "$e4_out" | grep -q "accumulation:" && echo "$e4b_out" | grep -q "accumulation:"; then
  pass "E4: --gate phase_0_to_1 does NOT evaluate accumulation, while the same fixture shape at 2->3 does — Phase 0 is pre-code discovery and writes no source"
else
  fail_ "E4" "expected silence at 0->1 and a report at 2->3 (control produced: $(echo "$e4b_out" | grep -c 'accumulation:') line(s))"
fi

# ══ F. The tracker's durable write ════════════════════════════════════════
echo ""
echo "F. tracker records the durable accumulation (outcome-gated)"

_fire() {   # _fire DIR EVENT TOOL
  local d="$1" ev="$2" tool="$3" payload
  if [ "$ev" = "PostToolUse" ]; then
    payload=$(jq -nc --arg t "$tool" '{session_id:"s",hook_event_name:"PostToolUse",tool_name:$t,tool_input:{information:"x"},tool_response:[{type:"text",text:"stored"}]}')
  else
    payload=$(jq -nc --arg t "$tool" '{session_id:"s",hook_event_name:"PostToolUseFailure",tool_name:$t,tool_input:{information:"x"},error:"All connection attempts failed",is_interrupt:false}')
  fi
  ( cd "$d" && printf '%s' "$payload" | bash "$TRACKER" >/dev/null 2>&1 )
}

F1="$(newtmp)"; mkdir -p "$F1/.claude"; ledger "$F1" true
_fire "$F1" PostToolUse "mcp__qdrant__qdrant-store"
f1_count=$(jq -r '.mcp_accumulation.store_success_count // 0' "$F1/.claude/process-state.json" 2>/dev/null)
f1_at=$(jq -r '.mcp_accumulation.last_store_at // ""' "$F1/.claude/process-state.json" 2>/dev/null)
if [ "$(_num "$f1_count")" -eq 1 ] && [ -n "$f1_at" ] && [ "$f1_at" != "null" ]; then
  pass "F1: a SUCCESSFUL qdrant-store writes the durable record (count=$f1_count, last_store_at=$f1_at)"
else
  fail_ "F1" "count='$f1_count' last_store_at='$f1_at'"
fi

# F2 and F3 assert a count of ZERO, which an unimplemented tracker gives for
# free. Each therefore fires a SUCCEEDING store into the SAME fixture
# afterwards and requires the count to reach 1 — proving the fixture was
# capable of accumulating and that the first event was rejected on its merits.
F2="$(newtmp)"; mkdir -p "$F2/.claude"; ledger "$F2" true
_fire "$F2" PostToolUseFailure "mcp__qdrant__qdrant-store"
f2_count=$(jq -r '.mcp_accumulation.store_success_count // 0' "$F2/.claude/process-state.json" 2>/dev/null)
_fire "$F2" PostToolUse "mcp__qdrant__qdrant-store"
f2_after=$(jq -r '.mcp_accumulation.store_success_count // 0' "$F2/.claude/process-state.json" 2>/dev/null)
if [ "$(_num "$f2_count")" -eq 0 ] && [ "$(_num "$f2_after")" -eq 1 ]; then
  pass "F2: a FAILED qdrant-store (PostToolUseFailure) writes NO durable record, while a succeeding one in the same fixture does — the accumulation half scores outcomes, exactly as WP-A made retrieval do"
else
  fail_ "F2" "failure->count=$f2_count (want 0), then success->count=$f2_after (want 1)"
fi

F3="$(newtmp)"; mkdir -p "$F3/.claude"; ledger "$F3" true
_fire "$F3" PostToolUse "mcp__qdrant__qdrant-find"
f3_count=$(jq -r '.mcp_accumulation.store_success_count // 0' "$F3/.claude/process-state.json" 2>/dev/null)
_fire "$F3" PostToolUse "mcp__qdrant__qdrant-store"
f3_after=$(jq -r '.mcp_accumulation.store_success_count // 0' "$F3/.claude/process-state.json" 2>/dev/null)
if [ "$(_num "$f3_count")" -eq 0 ] && [ "$(_num "$f3_after")" -eq 1 ]; then
  pass "F3: a successful qdrant-FIND does not count as accumulation, while a store in the same fixture does — retrieval is the other half"
else
  fail_ "F3" "find->count=$f3_count (want 0), then store->count=$f3_after (want 1)"
fi

F4="$(newtmp)"; mkdir -p "$F4/.claude"; ledger "$F4" true
_fire "$F4" PostToolUse "mcp__qdrant__qdrant-store"
_fire "$F4" PostToolUse "mcp__qdrant__qdrant-store"
f4_count=$(jq -r '.mcp_accumulation.store_success_count // 0' "$F4/.claude/process-state.json" 2>/dev/null)
if [ "$(_num "$f4_count")" -eq 2 ]; then
  pass "F4: the counter accumulates across calls (count=$f4_count)"
else
  fail_ "F4" "expected 2, got $f4_count"
fi

# ══ G. The Stop-hook reminder counts OUTCOMES ═════════════════════════════
echo ""
echo "G. session-end reminder counts outcomes, not declarations (WP-A residual 4)"

G1="$(newtmp)"; mkdir -p "$G1/.claude" "$G1/home"
mkdir -p "$G1/home/.claude"
cat > "$G1/home/.claude/settings.json" <<'S'
{"mcpServers":{"qdrant":{"command":"uvx","args":["mcp-server-qdrant"]}}}
S
cat > "$G1/.claude/tool-usage.json" <<'J'
{"session_id":"s","commits_since_last_context7":3,
 "calls":[
  {"tool":"mcp__qdrant__qdrant-find","event":"PostToolUseFailure","outcome":"failure","empty_result":false},
  {"tool":"mcp__qdrant__qdrant-find","event":"PostToolUseFailure","outcome":"failure","empty_result":false},
  {"tool":"mcp__qdrant__qdrant-find","event":"PostToolUse","outcome":"success","empty_result":false},
  {"tool":"mcp__qdrant__qdrant-store","event":"PostToolUseFailure","outcome":"failure","empty_result":false}
 ],
 "qdrant_find_called":true,"qdrant_find_succeeded":true,"qdrant_find_failed":2,
 "qdrant_store_called":true,"qdrant_store_succeeded":false,
 "context7_called":false,"context7_query_docs_succeeded":false}
J
echo '{"current_phase":2}' > "$G1/.claude/phase-state.json"
g1_out=$( ( cd "$G1" && HOME="$G1/home" bash "$REMINDER" 2>&1 ) | _strip_ansi )
if echo "$g1_out" | grep -q "Qdrant-find: 1 "; then
  pass "G1: three find CALLS of which one succeeded is reported as 1, not 3 — the reminder no longer disagrees with the gate WP-A shipped"
else
  fail_ "G1" "declaration count leaked into the summary: $(echo "$g1_out" | grep -i 'TOOL USAGE' || echo '<no summary line>')"
fi

if echo "$g1_out" | grep -qi "stored nothing in Qdrant"; then
  pass "G2: qdrant_store_called=true with qdrant_store_succeeded=false still WARNS — a store that failed is not a store"
else
  fail_ "G2" "a failed store silenced the warning"
fi

if echo "$g1_out" | grep -qi "failed"; then
  pass "G3: the failed round trips are VISIBLE in the summary rather than absent — a broken server is reportable"
else
  fail_ "G3" "failures are invisible in the summary"
fi

# ══ H. Commit-time is a WARNING, never a block ════════════════════════════
echo ""
echo "H. commit-time warn (Karl: warn at commit, block at the phase gate)"
# ENV GOES ON THE RIGHT OF THE PIPE. `HOME=... SKIP_LINT=1 printf ... | bash gate`
# sets both variables for PRINTF, not for the gate — so SKIP_LINT never took
# effect (the two documented slow full-tree lints ran on every call, ~75s each,
# five times) and, worse, HOME was never pinned, so these fixtures read the
# REAL home directory. That is the host-dependence class this suite exists to
# pin, sitting inside the suite itself. Measured: 455s -> ~80s once corrected.
# SKIP_LINT=1 on every commit-gate invocation below. The gate runs the repo's
# LINT SUITE, and because these fixtures drive the framework's own
# pre-commit-gate.sh its SCRIPT_DIR is this repository — so each call linted the
# whole repo. Measured: the H group was 249s of a 505s suite, on a shard already
# at 98.6% of its 12-minute cap, and it burst it. Skipping the lint stage costs
# this group nothing (no assertion here is about lints) and REMOVES an unrelated
# deny that could mask the arm under test — the R-360-15 failure mode.

H1="$(newtmp)"; mk_proj "$H1" 2; add_origin "$H1"; want_qdrant "$H1"; ledger "$H1" true
# phase2_init.verified satisfies an EARLIER commit-gate arm that would otherwise
# deny before this one runs. It deliberately carries NO mcp_accumulation object,
# which is the state under test: the project has stored nothing.
cat > "$H1/.claude/process-state.json" <<'J'
{"build_loop":{"feature":null,"step":0,"steps_completed":[],"started_at":null},
 "phase2_init":{"steps_completed":[],"verified":true}}
J
mkdir -p "$H1/src" "$H1/tests"
echo "print(1)" > "$H1/src/main.py"
# A matching test is staged alongside the source: without it the BL-072 TDD
# ordering gate fires FIRST and this arm is never reached, so the fixture would
# be measuring the wrong gate.
echo "def test_main(): pass" > "$H1/tests/test_main.py"
( cd "$H1" && git add -A >/dev/null 2>&1 )
# `chore:`, not `feat:`. A `feat:` commit is denied outright without an active
# Build Loop, which would stop the run before this arm — and standing up a
# Build Loop would be a large fixture for no extra coverage, because the arm
# keys on STAGED SOURCE PATHS and never looks at the conventional-commit type.
h1_payload=$(jq -nc '{tool_name:"Bash",tool_input:{command:"git commit -m \"chore: x\""}}')
h1_out=$( ( cd "$H1" && printf '%s' "$h1_payload" | HOME="$H1/home" SKIP_LINT=1 bash "$COMMIT_GATE" 2>&1 ) | _strip_ansi )
if echo "$h1_out" | grep -q 'phase gate' && echo "$h1_out" | grep -q '"permissionDecision": *"allow"'; then
  pass "H1: a source commit with nothing stored WARNS and names the phase gate that will block, while still ALLOWING the commit"
else
  fail_ "H1" "no allow-shaped warning naming the phase gate: $(echo "$h1_out" | head -2)"
fi

if ! echo "$h1_out" | grep -q '"permissionDecision": *"deny"'; then
  pass "H2: the commit-time arm never denies — storing is not per-commit work, and a gate people cannot satisfy honestly gets deleted (## BL-149:)"
else
  fail_ "H2" "the commit-time arm denied a commit"
fi


# H3 — the commit-time warning on the path the FIX creates. In a clone of a
# project scaffolded by init.sh the manifest is the ONLY declaration, and the
# warning's requirement loop used to read settings*.json and the ledger but not
# the manifest — so the phase gate blocked and the warning said nothing, on
# exactly the projects the manifest fix produces. "Warn at commit, block at the
# phase gate" with the warn half missing is worse than no warning at all.
H3="$(newtmp)"; mk_proj "$H3" 2; add_origin "$H3"
cat > "$H3/.claude/process-state.json" <<'J'
{"build_loop":{"feature":null,"step":0,"steps_completed":[],"started_at":null},
 "phase2_init":{"steps_completed":[],"verified":true}}
J
jq -n '{mcp:{qdrant_required:true}}' > "$H3/.claude/manifest.json"
mkdir -p "$H3/src" "$H3/tests"
echo "print(1)" > "$H3/src/main.py"
echo "def test_main(): pass" > "$H3/tests/test_main.py"
( cd "$H3" && git add -A >/dev/null 2>&1 )
h3_settings_absent=1
[ -f "$H3/.claude/settings.local.json" ] && h3_settings_absent=0
h3_out=$( ( cd "$H3" && printf '%s' "$h1_payload" | HOME="$H3/home" SKIP_LINT=1 bash "$COMMIT_GATE" 2>&1 ) | _strip_ansi )
if [ "$h3_settings_absent" -eq 1 ] && echo "$h3_out" | grep -q 'Nothing has been stored to Qdrant' \
   && ! echo "$h3_out" | grep -q '"permissionDecision": *"deny"'; then
  pass "H3: with the TRACKED manifest as the only declaration — the shape a clone of a scaffolded project has — the commit-time warning still fires, so the warn half is not missing exactly where the fix applies"
else
  fail_ "H3" "settings.local absent=$h3_settings_absent; got: $(echo "$h3_out" | head -c 200)"
fi

# H4 — the OTHER direction of the commit-time window. H1/H3 only ever assert
# that the warning FIRES; nothing asserted it stays SILENT when a store is
# genuinely inside the window. That half is what makes the warning trustworthy
# rather than constant noise, and the date compare it depends on is the one
# predicate the library did NOT unify — so it is the most likely to drift.
H4="$(newtmp)"; mk_proj "$H4" 2; add_origin "$H4"
cat > "$H4/.claude/process-state.json" <<'J'
{"build_loop":{"feature":null,"step":0,"steps_completed":[],"started_at":null},
 "phase2_init":{"steps_completed":[],"verified":true}}
J
jq -n '{mcp:{qdrant_required:true}}' > "$H4/.claude/manifest.json"
# gates.phase_1_to_2 is 2026-02-01 in mk_proj; this store is after it.
jq '.mcp_accumulation = {store_success_count: 1, last_store_at: "2026-02-15T10:00:00Z", attestations: {}}' \
  "$H4/.claude/process-state.json" > "$H4/.claude/ps.tmp" && mv "$H4/.claude/ps.tmp" "$H4/.claude/process-state.json"
mkdir -p "$H4/src" "$H4/tests"
echo "print(1)" > "$H4/src/main.py"
echo "def test_main(): pass" > "$H4/tests/test_main.py"
( cd "$H4" && git add -A >/dev/null 2>&1 )
h4_out=$( ( cd "$H4" && printf '%s' "$h1_payload" | HOME="$H4/home" SKIP_LINT=1 bash "$COMMIT_GATE" 2>&1 ) | _strip_ansi )
if ! echo "$h4_out" | grep -q 'Nothing has been stored to Qdrant' \
   && ! echo "$h4_out" | grep -q '"permissionDecision": *"deny"'; then
  pass "H4: a store INSIDE the window silences the commit-time warning — the date compare is exercised in both directions, not just the firing one"
else
  fail_ "H4" "warned despite a store inside the window: $(echo "$h4_out" | head -c 200)"
fi

# ══ I. The clone round trip — the test that was missing ═══════════════════
echo ""
echo "I. tracked-vs-untracked declaration (the fresh-clone question)"

# mk_clone_pair DIR — a project carrying the REAL generated ignore rules for the
# two untracked declaration files, committed, pushed to a LOCAL bare, and cloned
# back out. The ignore rules are written INTO the fixture rather than inherited
# from the host: this machine's ~/.config/git/ignore already excludes
# **/.claude/settings.local.json (Claude Code writes that itself), an
# ubuntu-latest runner's does not, and a fixture that depends on which is true
# is the ## BL-234: divergence class all over again.
mk_clone_pair() {
  local d="$1"
  # The ignore rules live in mk_proj now, written before the first `git add -A`.
  # Writing them here was one step too late: source_commit had already staged
  # settings.local.json on any host without a matching global exclude.
  ( cd "$d" || exit 1
    unset GITHUB_BASE_REF
    git add -A >/dev/null 2>&1
    git commit -qm "docs: declarations" >/dev/null 2>&1 )
  add_origin "$d"
  local clone="$TOPTMP/$(basename "$d").clone"
  git clone -q "$TOPTMP/$(basename "$d").origin.git" "$clone" >/dev/null 2>&1 || return 1
  # BL-234-FIXTURE-CLONE-RECEIPT: a clone's exit code is not proof it checked
  # anything out — a dangling HEAD symref clones successfully and empty.
  [ -f "$clone/.claude/phase-state.json" ] || return 1
  mkdir -p "$clone/home"
  printf '%s' "$clone"
}

# I1 — declaration in the TRACKED manifest: the clone must still enforce.
I1="$(newtmp)"; mk_proj "$I1" 3; want_qdrant "$I1"; source_commit "$I1"
jq '.mcp = {qdrant_required: true}' <<< '{}' > "$I1/.claude/manifest.json"
i1_clone=$(mk_clone_pair "$I1")
if [ -n "$i1_clone" ]; then
  ( cd "$i1_clone" && git config user.email t@e.x && git config user.name "Test Owner" ) >/dev/null 2>&1
  _run "$i1_clone" --gate phase_2_to_3; i1_out="$GOUT"
  i1_tracked=$( cd "$i1_clone" && git ls-files .claude/ | tr '\n' ' ' )
  if echo "$i1_out" | grep -q "accumulation: BLOCKED"; then
    pass "I1: a declaration in the TRACKED .claude/manifest.json survives clone->CI and still BLOCKS (clone tracks: $i1_tracked)"
  else
    fail_ "I1" "the gate went inert in a fresh clone: $(echo "$i1_out" | grep -i 'accumulation' || echo '<no line>')"
  fi
else
  fail_ "I1 (meta)" "clone fixture did not build"
fi

# I2 — declaration ONLY in the untracked settings.local.json. On the authoring
# machine it must ENFORCE and say the enforcement is local-only; in the clone it
# is genuinely absent, and the gate must say so rather than imply it checked.
I2="$(newtmp)"; mk_proj "$I2" 3; want_qdrant "$I2"; source_commit "$I2"
i2_clone=$(mk_clone_pair "$I2")
_run "$I2" --gate phase_2_to_3; i2_local_out="$GOUT"
if echo "$i2_local_out" | grep -q "accumulation: BLOCKED" && echo "$i2_local_out" | grep -q "git does not track"; then
  pass "I2a: an untracked-only declaration still ENFORCES on the authoring machine, and warns in as many words that a clone will not see it"
else
  fail_ "I2a" "expected a BLOCK plus an untracked warning; got: $(echo "$i2_local_out" | grep -i 'accumulation' || echo '<no line>')"
fi
if [ -n "$i2_clone" ]; then
  ( cd "$i2_clone" && git config user.email t@e.x && git config user.name "Test Owner" ) >/dev/null 2>&1
  _run "$i2_clone" --gate phase_2_to_3; i2_out="$GOUT"
  if echo "$i2_out" | grep -q "NOT CHECKED" && echo "$i2_out" | grep -q "manifest.json"; then
    pass "I2b: in the clone that declaration is genuinely gone, and the gate says NOT CHECKED and names the fix — the honest report of a real limit, not a silent pass"
  else
    fail_ "I2b" "expected NOT CHECKED naming manifest.json; got: $(echo "$i2_out" | grep -i 'accumulation' || echo '<no line>')"
  fi
else
  fail_ "I2b (meta)" "clone fixture did not build"
fi

# ══ J. Source-work coverage ═══════════════════════════════════════════════
echo ""
echo "J. source-work classifier covers languages, by negation"

# _j_pred PATH — classify a path through the SHIPPED library predicate, with no
# fixture and no gate run. The J-group asserts what counts as source work, and
# that IS this predicate; driving 35 full gate invocations to ask it cost ~150s
# of a 12-minute shard budget and contributed to a CI cancellation. The
# end-to-end path is still proved: _j_case anchors below run the real gate, and
# M10/M13 prove both gates consume this exact function rather than a copy.
_j_pred() {
  # If the library cannot be sourced, SAY SO — do not let a missing function
  # return non-zero and read as "exempt". Against the base tree that is exactly
  # what happened: no lib, `accum_paths_have_source` undefined, non-zero exit,
  # and J2/J3/J4 passed vacuously on a tree with no feature in it at all.
  ( if ! . "$REPO_ROOT/scripts/lib/accumulation.sh" 2>/dev/null; then printf 'NOLIB'; exit 0; fi
    if ! type accum_paths_have_source >/dev/null 2>&1; then printf 'NOLIB'; exit 0; fi
    if accum_paths_have_source "$1"; then printf 'SOURCE'; else printf 'exempt'; fi )
}

# _j_case EXT_PATH — one commit of that path onto a fresh fixture; echoes verdict.
_j_case() {
  local path="$1" d
  d="$(newtmp)"; mk_proj "$d" 3 >/dev/null 2>&1; want_qdrant "$d"
  ( cd "$d" || exit 1
    unset GITHUB_BASE_REF
    mkdir -p "$(dirname "$path")" 2>/dev/null
    echo "x" > "$path"
    git add -A >/dev/null 2>&1
    git commit -qm "add $path" >/dev/null 2>&1 )
  _run "$d" --gate phase_2_to_3
  if echo "$GOUT" | grep -q "accumulation: BLOCKED"; then printf 'BLOCKED'; else printf 'exempt'; fi
}

j_fail=""
# Three END-TO-END through the real gate — the integration anchor.
for _p in "models/user.rb" "public/index.php" "scripts/deploy.sh"; do
  v=$(_j_case "$_p")
  [ "$v" = "BLOCKED" ] || j_fail="$j_fail $_p(e2e:$v)"
done
# The remaining families at predicate level.
for _p in "components/Button.vue" "web/router.ex" "db/q.sql" "Main.hs" "core.lua" \
          "main.scala" "x.svelte"; do
  v=$(_j_pred "$_p")
  [ "$v" = "SOURCE" ] || j_fail="$j_fail $_p($v)"
done
if [ -z "$j_fail" ]; then
  pass "J1: Ruby, PHP, shell, Vue, Elixir, SQL, Haskell, Lua, Scala and Svelte source all count as source work — the allow-list voided this gate for every one of them"
else
  fail_ "J1" "still exempt:$j_fail"
fi

j2=$(_j_pred "docs/notes.md")
j2b=$(_j_pred "package.json")
if [ "$j2" = "exempt" ] && [ "$j2b" = "exempt" ]; then
  pass "J2: documentation and project metadata are exempt — the inversion did not turn every commit into source work (## BL-149: a gate nobody can satisfy gets deleted)"
else
  fail_ "J2" "docs=$j2 metadata=$j2b, expected both exempt"
fi

# J2c — INFRASTRUCTURE AS CODE IS SOURCE WORK. A blanket `\.(json|yml|yaml|toml)$`
# exemption meant an entire Kubernetes, Helm, Ansible or OpenAPI phase counted
# as "nothing owed" and the gate SAID SO — "every change was documentation,
# config or a dependency manifest" — which is the allow-list defect J1 exists
# for, with YAML substituted for Ruby. The exemption is now by metadata
# BASENAME, so an unrecognised .yml fails CLOSED.
j2c_fail=""
# One end-to-end, the rest at predicate level.
v=$(_j_case "k8s/deployment.yaml")
[ "$v" = "BLOCKED" ] || j2c_fail="$j2c_fail k8s/deployment.yaml(e2e:$v)"
for _infra in "docker-compose.yml" "helm/values.yaml" "ansible/site.yml" \
              "openapi.yaml" ".github/workflows/ci.yml" "Dockerfile"; do
  v=$(_j_pred "$_infra")
  [ "$v" = "SOURCE" ] || j2c_fail="$j2c_fail $_infra($v)"
done
if [ -z "$j2c_fail" ]; then
  pass "J2c: infrastructure-as-code (compose, k8s, Helm, Ansible, OpenAPI, CI, Dockerfile) counts as SOURCE work — an unrecognised structured-data file fails closed instead of silently voiding the gate"
else
  fail_ "J2c" "still exempt:$j2c_fail"
fi

# The exempt set claims to mirror process-checklist.sh::_is_dep_manifest. The
# first version listed only SOME of it and drifted on day one: Gemfile.lock,
# Pipfile.lock, pubspec.lock and requirements_dev.txt were exempt to the
# Build-Loop classifier and SOURCE to this one. Every entry is now driven,
# including the four that drifted — a fixture set calibrated to the
# implementation instead of the rule it cites proves only that the code agrees
# with itself.
j3_fail=""
# Driven from process-checklist.sh::_is_dep_manifest ITSELF, not a hand-copy of
# it: the previous list named 15 of its 19 entries while the pass text claimed
# "every" one. A fixture list transcribed from the rule it cites can drift from
# the rule; reading the rule cannot.
_dep_entries=$(awk '/^_is_dep_manifest\(\)/{f=1} f&&/^  esac/{exit} f&&/) return 0 ;;/{gsub(/^ +/,""); sub(/\) return 0 ;;.*/,""); gsub(/\|/," "); print}' \
  "$REPO_ROOT/scripts/process-checklist.sh" | tr ' ' '\n' | grep -v '^$' | sed 's/\*/dev/g')
# VACUITY FLOOR: if the extractor ever returns nothing (the function is
# reshaped, renamed, moved), the loop below would iterate zero times and J3
# would pass having tested nothing. That is this suite's recurring failure mode,
# so the extraction asserts its own yield.
# The floor is DERIVED from the function too, not transcribed. The first version
# hard-coded 15 — which was the size of the hand-copy it replaced, in the round
# whose subject line was "derive the counts". A silent drop of one case line
# would have yielded 16 and sailed past it.
_dep_n=$(printf '%s\n' $_dep_entries | grep -cv '^$')
_dep_expect=$(awk '/^_is_dep_manifest\(\)/{f=1} f&&/^  esac/{exit} f' "$REPO_ROOT/scripts/process-checklist.sh" \
  | grep -c ') return 0 ;;')
if [ "$_dep_expect" -lt 5 ] || [ "$_dep_n" -lt "$_dep_expect" ]; then
  fail_ "J3 (meta)" "extraction yielded $_dep_n entries from $_dep_expect case arms — the loop would under-test the rule it cites"
fi
for _dep in $_dep_entries \
            "uv.lock" "mix.lock" "flake.lock" "deno.lock" "bun.lock" "bun.lockb" \
            "Podfile.lock" "Gopkg.lock"; do
  v=$(_j_pred "$_dep")
  [ "$v" = "exempt" ] || j3_fail="$j3_fail $_dep($v)"
done
if [ -z "$j3_fail" ]; then
  pass "J3: every entry READ OUT OF process-checklist.sh::_is_dep_manifest is exempt here too, plus the eight ecosystems it predates (uv, mix, flake, deno, bun.lock and the pre-1.2 bun.lockb, Podfile, Gopkg) — a lockfile bump is not an insight (## BL-149:)"
else
  fail_ "J3" "not exempt:$j3_fail"
fi

# Extension-less config: a negation-based classifier calls these source unless
# named. A phase whose only commits touched .gitignore would otherwise be told
# to store an insight it never had.
j4_fail=""
for _cfg in ".gitignore" "LICENSE" "CODEOWNERS" ".editorconfig"; do
  v=$(_j_pred "$_cfg")
  [ "$v" = "exempt" ] || j4_fail="$j4_fail $_cfg($v)"
done
# Build logic is deliberately NOT exempt — a Makefile change is real work.
j4_mk=$(_j_pred "Makefile")
if [ -z "$j4_fail" ] && [ "$j4_mk" = "SOURCE" ]; then
  pass "J4: extension-less CONFIG (.gitignore, LICENSE, CODEOWNERS, .editorconfig) is exempt while build logic (Makefile) is not — the negation is bounded deliberately, not accidentally"
else
  fail_ "J4" "config not exempt:$j4_fail ; Makefile=$j4_mk (want SOURCE)"
fi

# ══ M. Mutation proofs — dual direction, changed>=2 asserted ══════════════
echo ""
echo "M. mutation proofs"

# _mk_mutant_repo LABEL FILE MARKER FIND REPL — copies the repo, mutates, and
# publishes the mutated root in the GLOBAL $MUT_ROOT. Meta-assertions (sites,
# changed, parses) are enforced here so a mutation that did not apply can never
# score as a killed mutant.
#
# IT PUBLISHES THROUGH A GLOBAL ON PURPOSE. The first draft of this harness
# echoed the path and was called as `root=$(_mk_mutant_repo ...)`. That is a
# SUBSHELL: every `fail_` it emitted was captured into the variable instead of
# printed, and every `FAILED=$((FAILED + 1))` incremented a counter that died
# with the subshell. A meta-failure — the mutation not applying at all — was
# therefore INVISIBLE and scored as nothing. That is the same silent-success
# class this suite exists to pin, reproduced in its own harness.
MUT_ROOT=""
_mk_mutant_repo() {
  local label="$1" relfile="$2" marker="$3" find="$4" repl="$5"
  local root file before sites changed parses
  MUT_ROOT=""
  root="$(newtmp)/repo"
  mkdir -p "$root"
  cp -R "$REPO_ROOT/scripts" "$root/scripts" 2>/dev/null
  # The mutant needs a COMPLETE-ENOUGH tree, not just scripts/. pre-commit-gate.sh
  # resolves its lints relative to its own directory, and a root with no tests/
  # and no .github/ makes lint-tests-registered.sh DENY — which silences the
  # commit-time warning for a reason that has nothing to do with the mutation.
  # M7 passed that way until its not-denied control was added.
  ln -s "$REPO_ROOT/tests" "$root/tests" 2>/dev/null
  ln -s "$REPO_ROOT/.github" "$root/.github" 2>/dev/null
  file="$root/$relfile"
  sites=$(_sites "$file" "$marker")
  if [ "$sites" -ne 1 ]; then
    fail_ "$label (meta)" "marker '$marker' has $sites end-of-line sites in $relfile, want exactly 1"
    return 1
  fi
  before="$(mktemp)"; cp "$file" "$before"
  _mutate "$file" "$find" "$repl"
  changed=$(_changed_lines "$before" "$file")
  parses=$(_parses "$file")
  if [ "$changed" -lt 2 ]; then
    fail_ "$label (meta)" "mutation did not apply — changed=$changed (<2). A mutation that does not mutate must not pass as a killed mutant."
    return 1
  fi
  if [ "$parses" -ne 1 ]; then
    fail_ "$label (meta)" "mutant does not parse (bash -n): $(bash -n "$file" 2>&1 | head -2)"
    return 1
  fi
  MUT_ROOT="$root"
  return 0
}

# _mutant_issues MUTANT_ROOT FIXTURE [ENV_ASSIGNMENTS...] — run a mutated gate.
_mutant_issues() {
  local root="$1" fix="$2"; shift 2
  local n
  n=$( cd "$fix" && HOME="$fix/home" env "$@" bash "$root/scripts/check-phase-gate.sh" --gate phase_2_to_3 2>&1 \
       | _strip_ansi | sed -n 's/^\([0-9][0-9]*\) inconsistency(ies) found.*/\1/p' | tail -1 )
  _num "$n"
}

# M1 — remove the single increment site: C2's block must evaporate.
if _mk_mutant_repo "M1" "scripts/check-phase-gate.sh" "# BL-233-WPB-BLOCK" \
      '|| issues=$((issues + 1))   # BL-233-WPB-BLOCK' \
      '|| : "no-op"                # BL-233-WPB-BLOCK'; then
  M1F="$(newtmp)"; mk_proj "$M1F" 3; want_qdrant "$M1F"; source_commit "$M1F"
  m1_issues=$(_mutant_issues "$MUT_ROOT" "$M1F")
  if [ "$m1_issues" -eq "$c1_base" ]; then
    pass "M1: excising the ONE increment site flips C2 from BLOCK to pass — the increment, not the [FAIL] label, is what enforces (## BL-104:)"
  else
    fail_ "M1" "mutant still blocked: issues=$m1_issues, want $c1_base"
  fi
fi

# M2 — invert the source-work verdict: C1's honest path must start blocking.
if _mk_mutant_repo "M2" "scripts/check-phase-gate.sh" "# BL-233-WPB-SOURCEWORK" \
      'return 1   # BL-233-WPB-SOURCEWORK' \
      'return 0   # BL-233-WPB-SOURCEWORK'; then
  M2F="$(newtmp)"; mk_proj "$M2F" 3; want_qdrant "$M2F"
  m2_issues=$(_mutant_issues "$MUT_ROOT" "$M2F")
  if [ "$m2_issues" -eq $((c1_base + 1)) ]; then
    pass "M2: inverting the source-work verdict makes a docs-only phase block — C1 is a real discriminator, not a vacuous pass"
  else
    fail_ "M2" "mutant did not block the docs-only phase: issues=$m2_issues, want $((c1_base + 1))"
  fi
fi

# M3 — widen the settings scan to $HOME: A5's host-independence must break.
if _mk_mutant_repo "M3" "scripts/lib/accumulation.sh" "# BL-233-WPB-SCOPE" \
      'for _f in ".claude/settings.local.json" ".claude/settings.json"; do   # BL-233-WPB-SCOPE' \
      'for _f in ".claude/settings.local.json" ".claude/settings.json" "$HOME/.claude.json"; do   # BL-233-WPB-SCOPE'; then
  M3F="$(newtmp)"; mk_proj "$M3F" 3; source_commit "$M3F"; want_qdrant_in_home "$M3F"
  m3_issues=$(_mutant_issues "$MUT_ROOT" "$M3F")
  if [ "$m3_issues" -eq $((a_ctrl_issues + 1)) ]; then
    pass "M3: adding \$HOME to the settings scan makes the host's own config decide the verdict — A5 pins the scope that keeps local and CI in agreement"
  else
    fail_ "M3" "widening the scope changed nothing: issues=$m3_issues, want $((a_ctrl_issues + 1))"
  fi
fi

# M4 — drop the tracker's outcome guard: F2 must start accumulating failures.
if _mk_mutant_repo "M4" "scripts/track-tool-usage.sh" "# BL-233-WPB-ACCUM-WRITE" \
      'if [ "$OUTCOME" = "success" ]; then   # BL-233-WPB-ACCUM-WRITE' \
      'if [ "$OUTCOME" != "zzz" ]; then   # BL-233-WPB-ACCUM-WRITE'; then
  m4_root="$MUT_ROOT"
  M4F="$(newtmp)"; mkdir -p "$M4F/.claude"; ledger "$M4F" true
  m4_payload=$(jq -nc '{session_id:"s",hook_event_name:"PostToolUseFailure",tool_name:"mcp__qdrant__qdrant-store",tool_input:{information:"x"},error:"All connection attempts failed",is_interrupt:false}')
  ( cd "$M4F" && printf '%s' "$m4_payload" | bash "$m4_root/scripts/track-tool-usage.sh" >/dev/null 2>&1 )
  m4_count=$(jq -r '.mcp_accumulation.store_success_count // 0' "$M4F/.claude/process-state.json" 2>/dev/null)
  if [ "$(_num "$m4_count")" -eq 1 ]; then
    pass "M4: removing the outcome guard makes a FAILED store accumulate — F2 proves the guard is what separates outcomes from declarations"
  else
    fail_ "M4" "mutant did not accumulate the failure: count=$m4_count"
  fi
fi

# M5 — honour an unrecordable attestation: D3's refusal must evaporate.
if _mk_mutant_repo "M5" "scripts/check-phase-gate.sh" "# BL-233-WPB-ATTEST-REFUSE" \
      'return 1   # BL-233-WPB-ATTEST-REFUSE' \
      'return 0   # BL-233-WPB-ATTEST-REFUSE'; then
  m5_root="$MUT_ROOT"
  M5F="$(newtmp)"; mk_proj "$M5F" 3; want_qdrant "$M5F"; source_commit "$M5F"
  mkdir -p "$M5F/.claude/process-state.json"
  m5_ctrl="$(newtmp)"; mk_proj "$m5_ctrl" 3; mkdir -p "$m5_ctrl/.claude/process-state.json"
  m5_base=$(_mutant_issues "$m5_root" "$m5_ctrl")
  m5_issues=$(_mutant_issues "$m5_root" "$M5F" \
    SOLO_MCP_ACCUM_ATTESTED=1 SOLO_MCP_ACCUM_ATTESTED_REASON="a real reason")
  if [ "$m5_issues" -eq "$m5_base" ]; then
    pass "M5: removing the refusal lets an unrecordable attestation clear the gate — D3 proves the record, not the env var, is the authority"
  else
    fail_ "M5" "mutant still refused: issues=$m5_issues, want $m5_base"
  fi
fi

# M6 — point the reminder back at the DECLARATION flag: G2 must go quiet.
if _mk_mutant_repo "M6" "scripts/session-end-qdrant-reminder.sh" "# BL-233-WPB-OUTCOME" \
      ".qdrant_store_succeeded // false' \"\$TOOL_USAGE\" 2>/dev/null)   # BL-233-WPB-OUTCOME" \
      ".qdrant_store_called // false' \"\$TOOL_USAGE\" 2>/dev/null)   # BL-233-WPB-OUTCOME"; then
  m6_out=$( ( cd "$G1" && HOME="$G1/home" bash "$MUT_ROOT/scripts/session-end-qdrant-reminder.sh" 2>&1 ) | _strip_ansi )
  if ! echo "$m6_out" | grep -qi "stored nothing in Qdrant"; then
    pass "M6: reading the *_called declaration instead of *_succeeded silences the warning on a session whose only store FAILED — G2 is a real discriminator"
  else
    fail_ "M6" "mutant still warned — G2 would pass either way"
  fi
fi

# M7 — suppress the commit-time warning: H1 must go quiet. The commit arm is
# non-enforcing by design, so its mutant proves the WARNING is real rather than
# that a block is real — H1 asserts the text, and without this it would be the
# only new surface with no mutant behind it.
if _mk_mutant_repo "M7" "scripts/pre-commit-gate.sh" "# BL-233-WPB-COMMIT-WARN" \
      'if [ "$ACC_SATISFIED" = false ]; then   # BL-233-WPB-COMMIT-WARN' \
      'if [ "$ACC_SATISFIED" = "never" ]; then   # BL-233-WPB-COMMIT-WARN'; then
  m7_out=$( ( cd "$H1" && printf '%s' "$h1_payload" | HOME="$H1/home" SKIP_LINT=1 bash "$MUT_ROOT/scripts/pre-commit-gate.sh" 2>&1 ) | _strip_ansi )
  # The NOT-DENIED control is what makes this attributable. Asserting only the
  # ABSENCE of the warning lets any earlier deny in pre-commit-gate.sh satisfy
  # the mutant for free — H1 could go red while M7 stayed green. The control
  # cannot be "an allow envelope is present": with the sole warning suppressed,
  # WARNINGS is empty and the gate emits NOTHING and exits 0, which is the whole
  # point of a non-blocking arm.
  if ! echo "$m7_out" | grep -q 'Nothing has been stored to Qdrant' \
     && ! echo "$m7_out" | grep -q '"permissionDecision": *"deny"'; then
    pass "M7: neutering the commit-time predicate silences the warning — H1 asserts a message that is actually produced, not one that happens to appear"
  else
    fail_ "M7" "expected the warning gone AND no deny; got: $(echo "$m7_out" | head -c 260)"
  fi
fi

# M8 — make the jq-missing arm non-counting: the tally must drop by exactly 1.
# A6 asserts only the TEXT, so without this the fail-closed half would be unproven —
# a [FAIL] label that increments nothing is precisely `## BL-104:`'s trap.
if _mk_mutant_repo "M8" "scripts/check-phase-gate.sh" "# BL-233-WPB-JQ-FAILCLOSED" \
      'return 1   # BL-233-WPB-JQ-FAILCLOSED' \
      'return 0   # BL-233-WPB-JQ-FAILCLOSED'; then
  m8_clean=$( ( cd "$A6" && HOME="$A6/home" PATH="$A6BIN" bash "$CPG" --gate phase_2_to_3 2>&1 ) \
    | _strip_ansi | sed -n 's/^\([0-9][0-9]*\) inconsistency(ies) found.*/\1/p' | tail -1 )
  m8_mut=$( ( cd "$A6" && HOME="$A6/home" PATH="$A6BIN" bash "$MUT_ROOT/scripts/check-phase-gate.sh" --gate phase_2_to_3 2>&1 ) \
    | _strip_ansi | sed -n 's/^\([0-9][0-9]*\) inconsistency(ies) found.*/\1/p' | tail -1 )
  m8_clean=$(_num "$m8_clean"); m8_mut=$(_num "$m8_mut")
  if [ "$m8_clean" -eq $((m8_mut + 1)) ]; then
    pass "M8: making the jq-missing arm non-counting drops the tally by exactly 1 — the [FAIL] label A6 reads actually enforces (## BL-104:)"
  else
    fail_ "M8" "clean=$m8_clean mutant=$m8_mut — expected clean to be exactly one higher"
  fi
fi


# M9 — make _cpg_file_tracked always answer "tracked": the untracked-only
# declaration then looks durable, and I2a's warning disappears. This is the
# mutant for the blocking defect the reviewer found — the gate reported a
# requirement as project-wide when it was machine-local.
if _mk_mutant_repo "M9" "scripts/lib/accumulation.sh" "# BL-233-WPB-TRACKED" \
      'git ls-files --error-unmatch -- "$1" >/dev/null 2>&1   # BL-233-WPB-TRACKED' \
      'true   # BL-233-WPB-TRACKED'; then
  M9F="$(newtmp)"; mk_proj "$M9F" 3; want_qdrant "$M9F"; source_commit "$M9F"
  # POSITIVE CONTROL FIRST. M9 asserts an ABSENCE, and an absence is free: on a
  # runner the UNMUTATED gate printed no warning either (the fixture reached a
  # different state), so M9 passed for a reason unrelated to its mutation. That
  # is the exact defect M7 had just been fixed for, reintroduced here in the
  # same commit. The control asserts the unmutated gate DOES warn on this very
  # fixture before the mutant's silence is allowed to mean anything.
  m9_ctrl=$( ( cd "$M9F" && HOME="$M9F/home" bash "$CPG" --gate phase_2_to_3 2>&1 ) | _strip_ansi )
  m9_out=$( ( cd "$M9F" && HOME="$M9F/home" bash "$MUT_ROOT/scripts/check-phase-gate.sh" --gate phase_2_to_3 2>&1 ) | _strip_ansi )
  if ! echo "$m9_ctrl" | grep -q "git does not track"; then
    fail_ "M9 (meta)" "the UNMUTATED gate does not warn on this fixture, so the mutant's silence proves nothing"
  elif ! echo "$m9_out" | grep -q "git does not track"; then
    pass "M9: assuming trackedness instead of asking git silences the local-only warning — I2a proves the gate now distinguishes 'required here' from 'required everywhere'"
  else
    fail_ "M9" "mutant still warned — I2a would pass either way"
  fi
fi

# M10 — restore the extension ALLOW-LIST the reviewer refuted: a Ruby commit
# must stop being source work, which is exactly how the gate silently voided
# itself for whole language families.
if _mk_mutant_repo "M10" "scripts/lib/accumulation.sh" "# BL-233-WPB-SOURCE-NEGATION" \
      'grep -qvE "$_ACCUM_EXEMPT_RE" <<< "$1"   # BL-233-WPB-SOURCE-NEGATION' \
      'grep -qE "\.(py|ts|js|rs|go)$" <<< "$1"   # BL-233-WPB-SOURCE-NEGATION'; then
  M10F="$(newtmp)"; mk_proj "$M10F" 3; want_qdrant "$M10F"
  ( cd "$M10F" || exit 1
    unset GITHUB_BASE_REF
    mkdir -p models
    echo "x" > models/user.rb
    git add -A >/dev/null 2>&1
    git commit -qm "add ruby" >/dev/null 2>&1 )
  # POSITIVE CONTROL. M10 asserts an ABSENCE on a fixture no unmutated assertion
  # touches, which is M9's defect exactly — named in review, fixed on M9 only,
  # and left here. The unmutated gate must BLOCK this fixture before the
  # mutant's silence is allowed to mean anything.
  m10_ctrl=$( ( cd "$M10F" && HOME="$M10F/home" bash "$CPG" --gate phase_2_to_3 2>&1 ) | _strip_ansi )
  m10_out=$( ( cd "$M10F" && HOME="$M10F/home" bash "$MUT_ROOT/scripts/check-phase-gate.sh" --gate phase_2_to_3 2>&1 ) | _strip_ansi )
  if ! echo "$m10_ctrl" | grep -q "accumulation: BLOCKED"; then
    fail_ "M10 (meta)" "the UNMUTATED gate does not block this Ruby fixture, so the mutant's silence proves nothing"
  elif ! echo "$m10_out" | grep -q "accumulation: BLOCKED"; then
    pass "M10: an extension allow-list lets a Ruby-only phase through — J1 proves the negation is what closes that hole, not the [FAIL] text"
  else
    fail_ "M10" "mutant still blocked — J1 would pass either way"
  fi
fi


# M11 — neuter the staleness check: the attestation becomes permanent again.
if _mk_mutant_repo "M11" "scripts/check-phase-gate.sh" "# BL-233-WPB-ATTEST-STALE" \
      'if [ -n "$recorded" ] && _cpg_accum_source_since "$recorded_head"; then' \
      'if [ -n "$recorded" ] && false; then'; then
  M11F="$(newtmp)"; mk_proj "$M11F" 3; want_qdrant "$M11F"; source_commit "$M11F"
  cat > "$M11F/.claude/process-state.json" <<'J'
{"mcp_accumulation":{"store_success_count":0,"last_store_at":null,
 "attestations":{"phase_2_to_3":{"reason":"stale one","date":"2026-03-02","by":"T","head":"HEADSHA"}}}}
J
  m11_head=$( cd "$M11F" && git rev-parse HEAD )
  python3 - "$M11F/.claude/process-state.json" "$m11_head" <<'PYX'
import io,sys
f,h=sys.argv[1],sys.argv[2]
s=io.open(f,encoding="utf-8").read().replace("HEADSHA",h)
io.open(f,"w",encoding="utf-8").write(s)
PYX
  ( cd "$M11F" && unset GITHUB_BASE_REF && mkdir -p src && echo "x" > src/after.py \
      && git add -A >/dev/null 2>&1 && git commit -qm "feat: after attestation" >/dev/null 2>&1 )
  m11_issues=$(_mutant_issues "$MUT_ROOT" "$M11F")
  if [ "$m11_issues" -eq "$c1_base" ]; then
    pass "M11: without the staleness check the stale attestation clears the gate again — D5 proves the scoping is what expires it"
  else
    fail_ "M11" "mutant still blocked: issues=$m11_issues, want $c1_base"
  fi
fi

# M12 — empty the exempt set: every commit becomes source work, so a docs-only
# phase starts demanding a store. J2/J3 assert an "exempt" verdict, which the
# BASE TREE also produces (nothing blocks there at all) — measured: they are the
# only 2 of 48 that pass against `main`. This mutant is what makes them
# attributable rather than free.
if _mk_mutant_repo "M12" "scripts/lib/accumulation.sh" "# BL-233-WPB-EXEMPT-SET" \
      "_ACCUM_EXEMPT_RE='^\$|" \
      "_ACCUM_EXEMPT_RE='^ZZZ_NEVER_MATCHES\$'; _ACCUM_PARKED='"; then
  M12F="$(newtmp)"; mk_proj "$M12F" 3; want_qdrant "$M12F"
  ( cd "$M12F" || exit 1
    unset GITHUB_BASE_REF
    mkdir -p docs
    echo "notes" > docs/notes.md
    git add -A >/dev/null 2>&1
    git commit -qm "docs: notes" >/dev/null 2>&1 )
  m12_issues=$(_mutant_issues "$MUT_ROOT" "$M12F")
  if [ "$m12_issues" -eq $((c1_base + 1)) ]; then
    pass "M12: emptying the exempt set makes a docs-only phase BLOCK — J2/J3 are real guards on the inversion, not passes inherited from the base tree"
  else
    fail_ "M12" "mutant did not block the docs-only phase: issues=$m12_issues, want $((c1_base + 1))"
  fi
fi

# M13 — prove pre-commit-gate.sh actually CONSUMES the shared predicate. M10 and
# M12 mutate the library but assert only on check-phase-gate.sh, so a re-inlined
# copy inside pre-commit-gate.sh would survive both. This mutant changes the
# LIBRARY and asserts the COMMIT-TIME warning changes — which is the entire
# point of the extraction, and was otherwise unpinned.
if _mk_mutant_repo "M13" "scripts/lib/accumulation.sh" "# BL-233-WPB-SOURCE-NEGATION" \
      'grep -qvE "$_ACCUM_EXEMPT_RE" <<< "$1"   # BL-233-WPB-SOURCE-NEGATION' \
      'false   # BL-233-WPB-SOURCE-NEGATION'; then
  m13_ctrl=$( ( cd "$H1" && printf '%s' "$h1_payload" | HOME="$H1/home" SKIP_LINT=1 bash "$COMMIT_GATE" 2>&1 ) | _strip_ansi )
  m13_out=$( ( cd "$H1" && printf '%s' "$h1_payload" | HOME="$H1/home" SKIP_LINT=1 bash "$MUT_ROOT/scripts/pre-commit-gate.sh" 2>&1 ) | _strip_ansi )
  if ! echo "$m13_ctrl" | grep -q 'Nothing has been stored to Qdrant'; then
    fail_ "M13 (meta)" "the UNMUTATED commit gate does not warn on H1, so the mutant proves nothing"
  elif ! echo "$m13_out" | grep -q 'Nothing has been stored to Qdrant' \
       && ! echo "$m13_out" | grep -q '"permissionDecision": *"deny"'; then
    pass "M13: mutating the LIBRARY silences the COMMIT-TIME warning — pre-commit-gate.sh genuinely consumes the shared predicate rather than carrying a re-inlined copy"
  else
    fail_ "M13" "the commit gate did not follow the library: $(echo "$m13_out" | head -c 200)"
  fi
fi

# M14 — switch off the unreadable arm. The reviewer flipped this exact line and
# all 59 assertions still passed, because A9's only discriminating clause was a
# printed-string grep — the label-as-verdict trap this suite's header disavows.
if _mk_mutant_repo "M14" "scripts/check-phase-gate.sh" "# BL-233-WPB-UNREADABLE-FAILCLOSED" \
      'return 1   # BL-233-WPB-UNREADABLE-FAILCLOSED' \
      'return 0   # BL-233-WPB-UNREADABLE-FAILCLOSED'; then
  M14F="$(newtmp)"; mk_proj "$M14F" 3; source_commit "$M14F"
  printf '%s' '{"broken":' > "$M14F/.claude/tool-usage.json"
  _run "$M14F" --gate phase_2_to_3; m14_clean=$GISSUES
  m14_mut=$(_mutant_issues "$MUT_ROOT" "$M14F")
  if [ "$m14_clean" -eq $((m14_mut + 1)) ]; then
    pass "M14: switching off the unreadable arm drops the tally by exactly 1 — A9 now enforces rather than merely reading a message ($m14_clean -> $m14_mut)"
  else
    fail_ "M14" "clean=$m14_clean mutant=$m14_mut — expected clean exactly one higher"
  fi
fi

# M15 — remove the LEDGER's validity guard specifically. That is the file the
# first cut forgot, and without a mutant on it the regression would be silent.
if _mk_mutant_repo "M15" "scripts/lib/accumulation.sh" "# BL-233-WPB-LEDGER-UNREADABLE" \
      '_unreadable=1   # BL-233-WPB-LEDGER-UNREADABLE' \
      ': "no-op"       # BL-233-WPB-LEDGER-UNREADABLE'; then
  M15F="$(newtmp)"; mk_proj "$M15F" 3; source_commit "$M15F"
  printf '%s' '{"broken":' > "$M15F/.claude/tool-usage.json"
  _run "$M15F" --gate phase_2_to_3; m15_clean=$GISSUES
  m15_mut=$(_mutant_issues "$MUT_ROOT" "$M15F")
  if [ "$m15_clean" -eq $((m15_mut + 1)) ]; then
    pass "M15: dropping the LEDGER's validity guard lets a one-byte corruption switch the gate off again — the arm the first cut omitted is now pinned in its own right"
  else
    fail_ "M15" "clean=$m15_clean mutant=$m15_mut — expected clean exactly one higher"
  fi
fi
echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
