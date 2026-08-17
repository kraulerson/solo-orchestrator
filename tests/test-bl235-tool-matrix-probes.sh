#!/usr/bin/env bash
# tests/test-bl235-tool-matrix-probes.sh
#
# BL-235 — the tool matrix records "Qdrant MCP installed" from a CONFIG ENTRY
# and never asks the database. `check_command` greps `~/.claude.json` for an
# `mcpServers.qdrant` key and `version_command` is `echo 'configured'` — a value
# that cannot be wrong, and therefore carries no information. A project with no
# running database is recorded `already_installed` and reported `[OK]` by every
# surface that consumes the resolver.
#
# THE SWEEP THE ENTRY ASKED FOR, RUN: the Qdrant row is NOT the only one.
# Derive it rather than trusting this comment:
#
#   jq -r '.tools | to_entries[]
#          | select((.value.check_command // "") | test("jq -e|settings\\.json"))
#          | .value.name' templates/tool-matrix/common.json
#
# Three rows today — Qdrant MCP, Context7 MCP and Superpowers — each pairing a
# config-grep check with an `echo`ed version string.
#
# ── THE PREREQUISITE, MEASURED, AND WHY IT COMES FIRST ──────────────────────
# The entry says a probe is unsafe because "the matrix schema does not currently
# express a bound". That is half right, and the half that is wrong changes the
# design:
#
#   scripts/resolve-tools.sh   run_cmd_with_timeout "$RESOLVE_TOOLS_EVAL_TIMEOUT"  BOUNDED (10s)
#   scripts/check-versions.sh  eval "$CHECK_CMD"                                   UNBOUNDED
#
# Two consumers of the same data, asymmetric bounding — and the unbounded one is
# ALREADY a live hazard: the matrix ships `colima version` and `docker --version`
# as version commands, and resolve-tools.sh's own header records that those
# "can hang indefinitely when the daemon is unreachable", which is why IT bounds
# them. So check-versions.sh can hang today, before this entry adds anything.
# Adding a network probe to the matrix without bounding that consumer would put
# a third hang path into the one script that cannot survive it. T1/T2 pin the
# bound; everything else depends on it.
#
# ASSERTIONS ARE WALL CLOCK, EXIT CODES AND EMITTED STATE — never the presence
# of a call. A probe that is merely ATTEMPTED is the defect restated.
#
# Hermetic: temp dirs, stub binaries on PATH, no network, no real database.
# bash 3.2 safe. No `timeout`/`gtimeout` (absent on the dev host).

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECKVER="$REPO_ROOT/scripts/check-versions.sh"
MATRIX="$REPO_ROOT/templates/tool-matrix/common.json"

BASH_BIN="$(command -v bash)"; [ -n "$BASH_BIN" ] || BASH_BIN="/bin/bash"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] jq is not installed — this suite asserts on matrix JSON."
  echo ""; echo "Results: 0 passed, 0 failed"; exit 0
fi

TOPTMP="$(mktemp -d)"
trap 'chmod -R u+rwX "$TOPTMP" 2>/dev/null; rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/caseXXXXXX"; }

_num() { case "$1" in ''|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac }
_mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || printf '?\n'; }
_sites() { local n; n=$(grep -c "$2\$" "$1" 2>/dev/null); _num "$n"; }
_changed_lines() { local n; n=$(diff "$1" "$2" 2>/dev/null | grep -c '^[<>]'); _num "$n"; }

_mutate() {
  local f="$1" marker="$2" repl="$3" before sites changed parses safe mode tmp
  safe=$(printf '%s' "$repl" | sed 's/&/\\&/g')
  mode="$(_mode_of "$f")"
  before="$(mktemp)"; cp -p "$f" "$before"
  sites=$(_sites "$f" "$marker")
  tmp="$(mktemp)"
  sed "s%^.*${marker}\$%${safe}%" "$f" > "$tmp" && mv "$tmp" "$f"
  [ "$mode" != "?" ] && chmod "$mode" "$f" 2>/dev/null
  changed=$(_changed_lines "$before" "$f")
  parses=0; bash -n "$f" >/dev/null 2>&1 && parses=1
  rm -f "$before"
  printf '%s %s %s\n' "$sites" "$changed" "$parses"
}

# mk_matrix_proj <dir> <check_cmd> <version_cmd> — a project whose matrix holds
# exactly one tool, with the given commands. check-versions.sh reads
# templates/tool-matrix relative to CWD.
mk_matrix_proj() {
  local d="$1" chk="$2" ver="$3"
  mkdir -p "$d/templates/tool-matrix" "$d/.claude"
  jq -n --arg c "$chk" --arg v "$ver" \
    '{description:"fixture", schema_version:1, scope:"common",
      tools:{ Probe:{ name:"Probe", category:"mcp_server", phase:2, required:false,
                      check_command:$c, version_command:$v, description:"fixture row" } } }' \
    > "$d/templates/tool-matrix/common.json"
}

echo "=== T — the unbounded consumer is bounded (the prerequisite) ==="

# ── T1: a check_command that sleeps must NOT hold check-versions.sh for its
# full duration. Asserted on WALL CLOCK, because "a timeout exists" is a claim
# and elapsed seconds are a measurement.
T1="$(newtmp)"; mk_matrix_proj "$T1" 'sleep 12' "echo 1.0"
t1_start=$(date +%s)
( cd "$T1" && CHECKVER_EVAL_TIMEOUT=2 "$BASH_BIN" "$CHECKVER" >/dev/null 2>&1 ) || true
t1_elapsed=$(( $(date +%s) - t1_start ))
if [ "$t1_elapsed" -lt 9 ]; then
  pass "T1: a 12s check_command did not hold check-versions.sh for 12s (elapsed ${t1_elapsed}s) — the eval is bounded, so a matrix row can probe without freezing the one consumer that never had a timeout"
else
  fail_ "T1" "elapsed ${t1_elapsed}s for a 12s check_command at a 2s bound — the eval is unbounded, and the matrix already ships 'colima version' / 'docker --version', which hang when the daemon is unreachable"
fi

# ── T2: the same for version_command. Both evals are unbounded today, and a
# probe would most naturally live in the version command.
T2="$(newtmp)"; mk_matrix_proj "$T2" 'true' 'sleep 12'
t2_start=$(date +%s)
( cd "$T2" && CHECKVER_EVAL_TIMEOUT=2 "$BASH_BIN" "$CHECKVER" >/dev/null 2>&1 ) || true
t2_elapsed=$(( $(date +%s) - t2_start ))
if [ "$t2_elapsed" -lt 9 ]; then
  pass "T2: a 12s version_command is bounded too (elapsed ${t2_elapsed}s) — bounding only the check would leave the other half of every row unbounded"
else
  fail_ "T2" "elapsed ${t2_elapsed}s for a 12s version_command at a 2s bound"
fi

# ── T3: the bound must not break a NORMAL row. Over-tightening would turn every
# healthy tool into 'not installed', which is the same class of wrong answer.
T3="$(newtmp)"; mk_matrix_proj "$T3" 'true' "echo 9.9.9"
t3_out="$( cd "$T3" && "$BASH_BIN" "$CHECKVER" 2>&1 )" || true
if printf '%s' "$t3_out" | grep -q '9.9.9'; then
  pass "T3: a fast, healthy row still reports its version through the bounded runner (9.9.9 seen) — the bound refuses hangs, not tools"
else
  fail_ "T3" "the bounded runner lost a healthy row's version; out='$(printf '%s' "$t3_out" | tr '\n' '|' | cut -c1-200)'"
fi

echo "=== D — the three declaration rows now exercise the tool ==="

# ── D1: the sweep. No shipped row may decide 'installed' by grepping a config
# file. Derived from the matrix, not from a list in this file.
d1_bad="$(jq -r '.tools | to_entries[]
  | select((.value.check_command // "") | test("jq -e|settings\\.json|[.]claude[.]json"))
  | "  " + (.value.name // .key)' "$MATRIX" 2>/dev/null)"
if [ -z "$d1_bad" ]; then
  pass "D1: no shipped row decides 'installed' by grepping a config file — the check exercises the tool, which is the difference between configured and working"
else
  fail_ "D1" "rows still deciding installed-ness from a config file:
$d1_bad"
fi

# ── D2: a version that cannot be wrong carries no information. `echo
# 'configured'` is true of a machine with nothing installed.
d2_bad="$(jq -r '.tools | to_entries[]
  | select((.value.version_command // "") | test("^echo "))
  | "  " + (.value.name // .key)' "$MATRIX" 2>/dev/null)"
if [ -z "$d2_bad" ]; then
  pass "D2: no shipped row reports a hardcoded version string — a value that cannot be wrong is not evidence, and all three of these were 'configured'/'installed'"
else
  fail_ "D2" "rows whose version_command cannot be wrong:
$d2_bad"
fi

# ── D3: the probe must be reachability, not presence-of-config. Asserted
# behaviourally: with the config present but NOTHING listening, the row must not
# report installed.
D3="$(newtmp)"
qdrant_chk="$(jq -r '.tools | to_entries[] | select(.value.name == "Qdrant MCP") | .value.check_command // ""' "$MATRIX" 2>/dev/null)"
if [ -z "$qdrant_chk" ]; then
  fail_ "D3" "no Qdrant MCP row found in the matrix"
else
  mkdir -p "$D3/home"
  printf '{"mcpServers":{"qdrant":{"env":{"QDRANT_URL":"http://127.0.0.1:59999"}}}}\n' > "$D3/home/.claude.json"
  # 59999 is chosen to be closed; the config says the server is there and it is not.
  d3_rc=0
  ( HOME="$D3/home" bash -c "$qdrant_chk" >/dev/null 2>&1 ) || d3_rc=$?
  if [ "$d3_rc" -ne 0 ]; then
    pass "D3: with the MCP config present and NOTHING listening, the Qdrant check fails (rc=$d3_rc) — 'registered' stopped meaning 'working', which is the whole entry"
  else
    fail_ "D3" "the Qdrant check passed against a closed port with only a config entry present — it is still reading a declaration"
  fi
fi

echo "=== M — mutation proofs ==="

# ── M1: remove the bound and T1 must hang again.
M1="$(newtmp)"; cp -R "$REPO_ROOT/scripts" "$M1/scripts" 2>/dev/null
m1_meta=$(_mutate "$M1/scripts/check-versions.sh" '# BL-235-BOUND-CHECK' '  if ! eval "$CHECK_CMD" >/dev/null 2>&1; then')
m1_sites="${m1_meta%% *}"; m1_rest="${m1_meta#* }"; m1_changed="${m1_rest%% *}"; m1_parses="${m1_rest##* }"
M1D="$(newtmp)"; mk_matrix_proj "$M1D" 'sleep 12' "echo 1.0"
m1_start=$(date +%s)
( cd "$M1D" && "$BASH_BIN" "$M1/scripts/check-versions.sh" >/dev/null 2>&1 ) || true
m1_elapsed=$(( $(date +%s) - m1_start ))
if [ "$m1_sites" -eq 1 ] && [ "$m1_parses" -eq 1 ] && [ "$m1_elapsed" -ge 10 ]; then
  pass "M1: with the bound removed, a 12s check_command holds the script for ${m1_elapsed}s again — the bound is load-bearing and measured in seconds, not asserted (sites=$m1_sites changed=$m1_changed parses=$m1_parses)"
else
  fail_ "M1" "sites=$m1_sites (want 1) parses=$m1_parses (want 1) changed=$m1_changed elapsed=${m1_elapsed}s (want >=10)"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
