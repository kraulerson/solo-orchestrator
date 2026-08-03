#!/usr/bin/env bash
# tests/test-walk003-update-command-render.sh — walk 2026-08-02 ISSUE-003:
# `check-versions.sh` printed a raw JSON array under a heading that promises a
# runnable command.
#
# WHY THIS EXISTS
#   BL-033 lets each `install.<key>` in the tool matrix be EITHER a string or an
#   ARRAY of stages, and scripts/resolve-tools.sh normalizes both (joining an
#   array with " && " for its `install_cmd` field). check-versions.sh did not:
#   it echoed the raw `jq -r` output, so a five-entry matrix printed
#       Colima: [ "brew install colima", "brew services start colima" ]
#   under "Update commands (run manually):". The walker's note is exact — a
#   junior cannot tell whether that is one command, two, or an error. Five tools
#   in the shipped matrix carry array-valued install keys (Colima, Docker,
#   gitleaks, k6, Rust), so this was not a corner case.
#
# THE CONTRACT (# WALK-ISSUE-003-UPDATE-CMD)
#   Every line under that heading is either a runnable command or LABELLED as
#   not being one:
#     • array  -> one line, stages joined with " && " (resolve-tools parity)
#     • string -> verbatim (the `<name>: <cmd>` grammar T-CV-MULTIWORD pins)
#     • URL    -> "see <url>" — a doc link is not a command
#     • absent -> an explicit "(no install command in the tool matrix …)"
#
# FIXTURE MECHANICS: min_version 99.0.0 + `version_command: echo 0.0.1` forces
# the BELOW-MINIMUM branch, which pushes onto UPDATES[]/UPDATE_CMDS[] with no
# network. Each tool carries the SAME shape under darwin_brew AND manual so the
# suite is portable across brew (macOS dev box) and non-brew (CI) hosts —
# whichever lookup wins, the shape under test is the one measured. Hermetic.
#
# REGISTRATION: no init.sh, not an aggregator → BOTH lists. bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CV="$REPO_ROOT/scripts/check-versions.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq required (tool matrix fixtures)"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# mk_fixture <dir> <script> <install-json-or-NONE>
mk_fixture() {
  local d="$1" script="$2" install="$3"
  rm -rf "$d"
  mkdir -p "$d/templates/tool-matrix" "$d/scripts/lib"
  if [ "$install" = NONE ]; then
    cat > "$d/templates/tool-matrix/common.json" <<'JSON'
{"tools":[{"name":"WalkTool","category":"tooling","required":true,
  "min_version":"99.0.0","description":"walk003 fixture",
  "check_command":"true","version_command":"echo 0.0.1",
  "tracks":["light","standard","full"],"languages":["all"],
  "platforms":["all"],"dev_os":["darwin","linux"]}]}
JSON
  else
    jq -n --argjson inst "$install" '
      {tools:[{name:"WalkTool",category:"tooling",required:true,
        min_version:"99.0.0",description:"walk003 fixture",
        check_command:"true",version_command:"echo 0.0.1",
        tracks:["light","standard","full"],languages:["all"],
        platforms:["all"],dev_os:["darwin","linux"],
        install:$inst}]}' > "$d/templates/tool-matrix/common.json"
  fi
  cp "$script" "$d/scripts/check-versions.sh"
  chmod +x "$d/scripts/check-versions.sh"
}

run_cv() { ( cd "$1" && bash scripts/check-versions.sh </dev/null 2>&1 || true ); }

# The same multi-stage value under both lookup keys (brew and non-brew hosts).
ARRAY_INSTALL='{"darwin_brew":["brew install colima","brew services start colima"],
                "manual":["brew install colima","brew services start colima"]}'
STRING_INSTALL='{"darwin_brew":"brew install walktool","manual":"brew install walktool"}'
URL_INSTALL='{"darwin_brew":"https://example.invalid/install","manual":"https://example.invalid/install"}'

echo "== tests/test-walk003-update-command-render.sh =="

# ── T1: an array install renders as ONE runnable && chain, no JSON ──────────
echo "=== T1-array-renders-runnable ==="
P="$TOPTMP/p1"; mk_fixture "$P" "$CV" "$ARRAY_INSTALL"
out=$(run_cv "$P")
line=$(printf '%s\n' "$out" | grep '^  WalkTool:' | head -1)
if printf '%s' "$line" | grep -Fq 'brew install colima && brew services start colima' \
   && ! printf '%s' "$line" | grep -q '\['; then
  pass "T1-array-renders-runnable (stages joined with ' && ', resolve-tools parity)"
else
  fail_ "T1-array-renders-runnable" "the walk's exact defect: a JSON array under 'Update commands (run manually)'. line=[$line]"
fi

# ── T2: a plain string is still printed VERBATIM (T-CV-MULTIWORD parity) ───
echo "=== T2-string-verbatim ==="
P="$TOPTMP/p2"; mk_fixture "$P" "$CV" "$STRING_INSTALL"
out=$(run_cv "$P")
if printf '%s\n' "$out" | grep -qE '^  WalkTool: brew install walktool$'; then
  pass "T2-string-verbatim (the '<name>: <cmd>' grammar is unchanged)"
else
  fail_ "T2-string-verbatim" "the single-command shape must not regress: $(printf '%s\n' "$out" | grep -i walktool | tr '\n' ' ')"
fi

# ── T3: a documentation URL is labelled, not presented as a command ────────
echo "=== T3-url-labelled ==="
P="$TOPTMP/p3"; mk_fixture "$P" "$CV" "$URL_INSTALL"
out=$(run_cv "$P")
if printf '%s\n' "$out" | grep -qE '^  WalkTool: see https://example\.invalid/install$'; then
  pass "T3-url-labelled (a doc link is not a runnable command)"
else
  fail_ "T3-url-labelled" "expected 'see <url>': $(printf '%s\n' "$out" | grep -i walktool | tr '\n' ' ')"
fi

# ── T4: no install block at all → explicit, never a dangling colon ─────────
echo "=== T4-absent-labelled ==="
P="$TOPTMP/p4"; mk_fixture "$P" "$CV" NONE
out=$(run_cv "$P")
if printf '%s\n' "$out" | grep -q '^  WalkTool: (no install command in the tool matrix'; then
  pass "T4-absent-labelled (an empty entry says so instead of printing 'WalkTool: ')"
else
  fail_ "T4-absent-labelled" "expected the labelled empty case: $(printf '%s\n' "$out" | grep -i walktool | tr '\n' ' ')"
fi

# ── M1: mutant — drop the array normalizer, the raw JSON comes back ────────
# Asserted POSITIVELY: the mutant must reproduce the walk's verbatim output.
echo "=== M1-mutant-drop-normalizer ==="
MUT="$TOPTMP/cv-mutant.sh"
sed "s|^_cv_jq_install_cmd=.*|_cv_jq_install_cmd='.'|" "$CV" > "$MUT"
if grep -q "^_cv_jq_install_cmd='\.'\$" "$MUT"; then
  P="$TOPTMP/pm1"; mk_fixture "$P" "$MUT" "$ARRAY_INSTALL"
  out=$(run_cv "$P")
  if printf '%s\n' "$out" | grep -q 'WalkTool: \['; then
    pass "M1-mutant-drop-normalizer (without the normalizer the raw JSON array returns — it carries T1)"
  else
    fail_ "M1-mutant-drop-normalizer" "the mutant did not reproduce ISSUE-003, so T1 proves nothing: $(printf '%s\n' "$out" | grep -i walktool | tr '\n' ' ')"
  fi
else
  fail_ "M1-mutant-drop-normalizer" "sed did not rewrite _cv_jq_install_cmd — mutant is vacuous"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
