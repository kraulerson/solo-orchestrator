#!/usr/bin/env bash
# tests/test-bl113-sast-honesty.sh — BL-113 AGGREGATOR (walk findings F14 + F15).
#
# TWO defects, one credibility story:
#
#   F14 — a freshly-scaffolded project FAILED the framework's OWN Phase-3 SAST.
#         `semgrep --config auto` flagged 6 WARNINGs, ALL in framework-shipped
#         files (5 mutable GitHub-Action tags in the generated
#         .github/workflows/{ci,release}.yml + 1 IFS-tamper in
#         scripts/check-versions.sh) and ZERO in the app's own src/. A scanner
#         FAIL is NOT attestable (only a SKIP is) — so an honest operator could
#         not clear Phase 3 without editing framework-generated files.
#
#   F15 — and the gate then LAUNDERED that FAIL. Whenever the tree is dirty (the
#         NORMAL state while authoring Phase-3 artifacts) the 3→4 gate's BL-082
#         staleness check autoruns the driver with `--offline`, which downgraded
#         semgrep/license/snyk/zap to SKIP. The operator saw "scanner
#         unavailable", attested the SKIP in good faith, and passed — never
#         learning that a REAL scan FAILs.
#
# WHAT THIS PROVES
#   T-scaffold-scan-clean   REAL init.sh scaffold → REAL `semgrep --config auto`
#                           → ZERO framework-origin findings. (SKIPs loudly if
#                           semgrep is not installed.)
#   T-no-launder-dirty-tree A dirty tree + a prior REAL semgrep FAIL → the 3→4
#                           gate does NOT present a fresh attestable SKIP. Both
#                           BL-113 defences are asserted on the operator-visible
#                           wording. Hermetic: needs no semgrep binary (the
#                           carry-forward arm) and uses a PATH stub (the
#                           tool-installed refusal arm).
#   T-offline-still-usable  Genuinely no tool + no prior real FAIL → an honest
#                           attestable SKIP, and the gate's Phase-3 validation
#                           arm still passes. The framework MUST work offline.
#   T-mutation-no-launder   Neuter the `# BL-113-NO-LAUNDER` decision bodies
#                           (marker intact) → T-no-launder goes RED; restore →
#                           GREEN.
#   T-mutation-action-pin   Revert ONE action pin to a mutable tag in a scratch
#                           scaffold → T-scaffold-scan-clean goes RED.
#
# AGGREGATOR: runs the REAL init.sh, so it is registered ONLY in
# tests/full-project-test-suite.sh (SUITE_SKIP_AGGREGATORS-gated) and NEVER in
# the tests.yml unit fast lane.
#
# Hermetic: mktemp scratch, --no-remote-creation, GITHUB_BASE_REF unset, local
# git identity in every fixture repo. bash-3.2 safe (no ${var,,}, no declare -A,
# no ((x++)) under set -e).

# HARNESS HOOKS (used ONLY by tests/test-bl099-guard-coverage.sh; a bare run of
# this file ignores both):
#   BL113_SCRIPTS_OVERRIDE=<dir>  after scaffolding, replace the scaffold's copies
#                                 of run-phase3-validation.sh + check-phase-gate.sh
#                                 with the ones in <dir>, so the guard harness can
#                                 drive this suite against a NEUTERED script.
#   BL113_ONLY=no-launder         run only the F15 anti-laundering arms (skip the
#                                 semgrep scaffold scan and the in-file mutation
#                                 arms) — keeps the harness's 2-runs-per-row cost
#                                 down and pins the assertion to the guard.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT="$REPO_ROOT/init.sh"
DRIVER_SRC="$REPO_ROOT/scripts/run-phase3-validation.sh"
GATE_SRC="$REPO_ROOT/scripts/check-phase-gate.sh"
BL113_ONLY="${BL113_ONLY:-}"
BL113_SCRIPTS_OVERRIDE="${BL113_SCRIPTS_OVERRIDE:-}"

unset GITHUB_BASE_REF 2>/dev/null || true

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
note()  { echo "  [NOTE] $1"; }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

if ! command -v jq >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  echo "SKIP: jq/git required for the BL-113 SAST-honesty aggregator"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

# ════════════════════════════════════════════════════════════════════════════
# Shared fixture: ONE real organizational scaffold via the REAL init.sh.
# ════════════════════════════════════════════════════════════════════════════
SCAFFOLD="$TOPTMP/proj"
echo "=== Scaffolding an organizational project via the REAL init.sh (hermetic) ==="
if ! ( cd "$TOPTMP" && "$INIT" --non-interactive \
        --project bl113sast \
        --platform web \
        --deployment organizational \
        --gov-mode production \
        --language typescript \
        --project-dir "$SCAFFOLD" \
        --no-remote-creation ) >"$TOPTMP/init.out" 2>"$TOPTMP/init.err"; then
  fail_ "scaffold-init" "init.sh exited non-zero; stderr tail: $(tail -6 "$TOPTMP/init.err" | tr '\n' '|')"
  echo "Results: $PASSED passed, $FAILED failed"
  exit 1
fi
pass "real init.sh scaffolded an organizational project"

# Guard-harness override: swap the scaffold's copies of the two BL-113 scripts for
# the (possibly NEUTERED) ones the harness points at. Applied to the shared
# scaffold so every derived fixture below inherits it.
if [ -n "$BL113_SCRIPTS_OVERRIDE" ]; then
  for _ovr in run-phase3-validation.sh check-phase-gate.sh; do
    if [ -f "$BL113_SCRIPTS_OVERRIDE/$_ovr" ]; then
      cp "$BL113_SCRIPTS_OVERRIDE/$_ovr" "$SCAFFOLD/scripts/$_ovr"
      chmod +x "$SCAFFOLD/scripts/$_ovr"
    fi
  done
  echo "  [HOOK] scaffold scripts overridden from $BL113_SCRIPTS_OVERRIDE"
fi

# ════════════════════════════════════════════════════════════════════════════
# T-scaffold-scan-clean (F14) — a fresh scaffold must PASS the framework's own
# SAST. Zero findings of framework origin. This is the acceptance criterion.
# ════════════════════════════════════════════════════════════════════════════
if [ "$BL113_ONLY" = "no-launder" ]; then
  echo "=== T-scaffold-scan-clean / T-mutation-action-pin — SKIPPED (BL113_ONLY=no-launder) ==="
else
echo "=== T-scaffold-scan-clean: REAL semgrep --config auto on the fresh scaffold ==="
SEMGREP_AVAILABLE=0
if command -v semgrep >/dev/null 2>&1; then
  SEMGREP_AVAILABLE=1
fi

# scan_scaffold <dir> <out.json> — echo the finding count (or "ERR").
scan_scaffold() {
  local dir="$1" out="$2" rc=0
  ( cd "$dir" && semgrep --config auto --json --output "$out" . ) >/dev/null 2>&1 || rc=$?
  if [ "$rc" -ge 2 ] || [ ! -f "$out" ]; then echo "ERR"; return 0; fi
  jq -r '(.results | length) // 0' "$out" 2>/dev/null || echo "ERR"
}

if [ "$SEMGREP_AVAILABLE" -eq 0 ]; then
  # SKIP CLEANLY AND LOUDLY — never silently green. The acceptance criterion is
  # unverifiable without the tool, and pretending otherwise is the exact class of
  # dishonesty BL-113 exists to kill.
  echo ""
  echo "  ############################################################"
  echo "  # [SKIP-LOUD] T-scaffold-scan-clean + T-mutation-action-pin"
  echo "  # semgrep is NOT installed on this host."
  echo "  # The BL-113 F14 acceptance criterion (fresh scaffold →"
  echo "  # semgrep --config auto → ZERO framework-origin findings)"
  echo "  # CANNOT be verified here. This is NOT a pass."
  echo "  # Install semgrep (brew install semgrep) and re-run."
  echo "  ############################################################"
  echo ""
  note "T-scaffold-scan-clean SKIPPED (semgrep absent) — not counted as a pass"
  note "T-mutation-action-pin SKIPPED (semgrep absent) — not counted as a pass"
else
  count="$(scan_scaffold "$SCAFFOLD" "$TOPTMP/scan-clean.json")"
  if [ "$count" = "0" ]; then
    pass "T-scaffold-scan-clean: fresh scaffold has ZERO semgrep findings (real --config auto)"
  elif [ "$count" = "ERR" ]; then
    # A registry/network failure is not a test failure — but it is not a pass.
    note "T-scaffold-scan-clean INCONCLUSIVE: semgrep could not complete (rule registry unreachable?) — not counted"
  else
    fail_ "T-scaffold-scan-clean" "fresh scaffold has $count semgrep finding(s): $(jq -r '[.results[] | "\(.check_id)@\(.path):\(.start.line)"] | join(", ")' "$TOPTMP/scan-clean.json" 2>/dev/null)"
  fi

  # — the two F14 classes, asserted structurally as well (cheap, tool-free) —
  mutable=0
  for wf in "$SCAFFOLD/.github/workflows/ci.yml" "$SCAFFOLD/.github/workflows/release.yml"; do
    [ -f "$wf" ] || continue
    while IFS= read -r line; do
      case "$line" in
        *"uses:"*"@"*) ;;
        *) continue ;;
      esac
      # Anything after the `@` that is not a 40-hex commit SHA is a mutable ref.
      ref="${line#*@}"
      ref="${ref%% *}"
      if ! printf '%s' "$ref" | grep -qE '^[0-9a-f]{40}$'; then
        mutable=$((mutable + 1))
        echo "    mutable action ref in $(basename "$wf"): $line"
      fi
    done < "$wf"
  done
  if [ "$mutable" -eq 0 ]; then
    pass "T-scaffold-scan-clean: every generated-workflow action ref is a 40-hex commit SHA"
  else
    fail_ "T-scaffold-scan-clean action pins" "$mutable mutable action ref(s) in the generated workflows"
  fi

  # — NO SUPPRESSION MAY SHIP. The two release TEMPLATES carry a `# nosemgrep` on
  #   the `uses: __SETUP_ACTION__` placeholder line (the token is a build-time
  #   placeholder, not an action ref — a genuine false positive). That comment is
  #   STRIPPED at render time, keyed on the `__SOLO_TEMPLATE_ONLY__` marker. If it
  #   ever leaked, every generated project would silently suppress the
  #   mutable-action-tag rule on its own setup step — laundering-by-suppression,
  #   the very thing this PR exists to prevent. Assert it never reaches a scaffold.
  leak=0
  for wf in "$SCAFFOLD/.github/workflows/"*.yml; do
    [ -f "$wf" ] || continue
    if grep -qE 'nosemgrep|__SOLO_TEMPLATE_ONLY__|__SETUP_ACTION__' "$wf"; then
      leak=$((leak + 1))
      echo "    suppression/placeholder leaked into $(basename "$wf")"
    fi
  done
  if [ "$leak" -eq 0 ]; then
    pass "T-scaffold-scan-clean: no scanner suppression and no unsubstituted placeholder reaches the generated workflows"
  else
    fail_ "T-scaffold-scan-clean suppression leak" "$leak generated workflow(s) carry a nosemgrep suppression or an unsubstituted placeholder token"
  fi

  # ══════════════════════════════════════════════════════════════════════════
  # T-mutation-action-pin — revert ONE action pin to a mutable tag in a SCRATCH
  # copy of the real scaffold. T-scaffold-scan-clean must go RED.
  # ══════════════════════════════════════════════════════════════════════════
  echo "=== T-mutation-action-pin: un-pin actions/checkout in a scratch scaffold ==="
  MUT="$TOPTMP/mut-pin"
  cp -R "$SCAFFOLD" "$MUT"
  sed -e 's|actions/checkout@[0-9a-f]\{40\}.*$|actions/checkout@v4|' \
      "$MUT/.github/workflows/ci.yml" > "$MUT/.github/workflows/ci.yml.tmp" \
      && mv "$MUT/.github/workflows/ci.yml.tmp" "$MUT/.github/workflows/ci.yml"
  if grep -q 'actions/checkout@v4$' "$MUT/.github/workflows/ci.yml"; then
    mcount="$(scan_scaffold "$MUT" "$TOPTMP/scan-mut.json")"
    if [ "$mcount" = "ERR" ]; then
      note "T-mutation-action-pin INCONCLUSIVE: semgrep could not complete — not counted"
    elif [ "$mcount" -gt 0 ] 2>/dev/null; then
      pass "T-mutation-action-pin: RED as required — un-pinning actions/checkout re-introduces $mcount finding(s)"
    else
      fail_ "T-mutation-action-pin" "un-pinning actions/checkout did NOT make the scan RED (still 0 findings) — the acceptance test cannot detect a regression"
    fi
  else
    fail_ "T-mutation-action-pin" "could not apply the un-pin mutation to the scratch scaffold"
  fi
fi
fi

# — the IFS-tamper class (F14's 6th finding), asserted tool-free —
# semgrep's `bash.lang.security.ifs-tampering` flags an IFS *assignment* (`IFS=x`
# on its own, `local/export/declare IFS=x`) — it does NOT flag the COMMAND-PREFIX
# form (`IFS=',' read -a arr`), which is the remediation the rule itself
# recommends. Assert exactly that distinction so the check is tool-free but not
# a false alarm on the legitimate `IFS=',' read` lines the script also contains.
if [ "$BL113_ONLY" = "no-launder" ]; then
  :
elif [ ! -f "$SCAFFOLD/scripts/check-versions.sh" ]; then
  fail_ "T-scaffold-scan-clean IFS" "scripts/check-versions.sh was not shipped into the scaffold"
else
  ifs_bad=0
  # (i) scoped/exported assignment — always flagged.
  if grep -qE '^[[:space:]]*(local|export|declare|readonly)[[:space:]]+IFS=' "$SCAFFOLD/scripts/check-versions.sh"; then
    ifs_bad=$((ifs_bad + 1))
  fi
  # (ii) bare assignment with NO command following it on the line.
  if grep -qE '^[[:space:]]*IFS=[^[:space:]]*[[:space:]]*(#.*)?$' "$SCAFFOLD/scripts/check-versions.sh"; then
    ifs_bad=$((ifs_bad + 1))
  fi
  if [ "$ifs_bad" -eq 0 ]; then
    pass "T-scaffold-scan-clean: shipped check-versions.sh no longer tampers with IFS (command-prefix form only)"
  else
    fail_ "T-scaffold-scan-clean IFS" "the shipped scripts/check-versions.sh still ASSIGNS IFS ($ifs_bad form(s)) — semgrep bash.lang.security.ifs-tampering: $(grep -nE '^[[:space:]]*((local|export|declare|readonly)[[:space:]]+)?IFS=' "$SCAFFOLD/scripts/check-versions.sh" | tr '\n' '|')"
  fi
fi

# ════════════════════════════════════════════════════════════════════════════
# Phase-3 fixture helpers — put the scaffold at the 3→4 gate.
# ════════════════════════════════════════════════════════════════════════════

# seed_phase3 <project-dir>
# Commit the scaffold, then move phase-state to phase 4 so the BL-070 Phase-3
# validation block (guarded `current_phase >= 4`) evaluates. Leaves the tree
# CLEAN; the caller dirties it.
seed_phase3() {
  local p="$1"
  ( cd "$p" \
      && git config user.email "bl113@example.test" \
      && git config user.name "BL-113 Fixture" \
      && git add -A \
      && git -c core.hooksPath=/dev/null commit -q -m "chore: bl113 fixture baseline" ) >/dev/null 2>&1
  local st="$p/.claude/phase-state.json"
  jq '.current_phase = 4' "$st" > "$st.tmp" && mv "$st.tmp" "$st"
}

# attest_all <project-dir> — attest every scanner that a genuinely-offline run
# would SKIP, exactly as an honest operator would.
attest_all() {
  local p="$1" s
  for s in semgrep-full-tree license snyk zap-dast threat-model; do
    ( cd "$p" && bash scripts/run-phase3-validation.sh --attest "$s" \
        --reason "tool unavailable in this environment; recorded honestly" \
        --signoff "BL-113 Fixture" ) >/dev/null 2>&1 || true
  done
}

# A PATH-prefix dir containing a fake `semgrep` binary, so the gate's
# "tool is installed" probe is TRUE regardless of the host. Hermetic — it is
# never executed by the gate (only `command -v`-probed).
STUBBIN="$TOPTMP/stubbin"
mkdir -p "$STUBBIN"
printf '#!/bin/sh\nexit 2\n' > "$STUBBIN/semgrep"
chmod +x "$STUBBIN/semgrep"

# A PATH with NO semgrep at all (genuinely-no-tool arm). Built from the real
# PATH minus every dir that contains a semgrep binary.
nosemgrep_path() {
  local d out=""
  local oldifs="$IFS"
  IFS=':'
  for d in $PATH; do
    [ -n "$d" ] || continue
    [ -x "$d/semgrep" ] && continue
    out="${out}${out:+:}${d}"
  done
  IFS="$oldifs"
  printf '%s' "$out"
}
NOSEMGREP_PATH="$(nosemgrep_path)"

# seed_prior_real_fail <project-dir>
# Write a PRIOR summary that records a REAL (non-offline) semgrep FAIL — exactly
# what a real `semgrep --config auto` produced on a pre-BL-113 scaffold (F14).
# This is the ground truth the offline autorun used to launder away.
seed_prior_real_fail() {
  local p="$1" rd="$1/docs/test-results/phase3"
  mkdir -p "$rd"
  cat > "$rd/summary-2000-01-01T00-00-00Z.md" <<'EOF'
# Phase 3 Validation Summary

- Generated: 2000-01-01T00:00:00Z
- tree: 0000000000000000000000000000000000000000
- dirty: no
- Offline: no
- Scanners: 5
- PASS: 0  SKIP(attested): 4  SKIP(un-attested): 0  FAIL: 1
- Overall: FAIL

## Machine-readable results (parsed by scripts/check-phase-gate.sh)

```
RESULT semgrep-full-tree FAIL
RESULT license SKIP
RESULT snyk SKIP
RESULT zap-dast SKIP
RESULT threat-model SKIP
```
EOF
}

# ════════════════════════════════════════════════════════════════════════════
# T-no-launder-dirty-tree (F15) — a dirty tree + a REAL prior semgrep FAIL must
# NOT yield a fresh attestable SKIP at the 3→4 gate.
#
# TWO independent defences, asserted separately:
#   (a) DRIVER carry-forward — the offline autorun's SKIP is promoted back to
#       FAIL with `[STALE — last real result: FAIL]`. Needs NO semgrep binary.
#   (b) GATE refusal — an offline-autorun SKIP for a scanner whose TOOL IS ON
#       PATH is refused outright, attested or not.
# ════════════════════════════════════════════════════════════════════════════
echo "=== T-no-launder-dirty-tree: dirty tree + a REAL prior semgrep FAIL ==="

# dirty_tree <project-dir> — make the SCOPED working tree dirty exactly the way
# an operator authoring Phase-3 artifacts does: an uncommitted edit to a TRACKED
# source path outside `.claude/` and the results dir (the two paths the BL-082
# scoped-dirty check excludes). This is what triggers the [STALE] autorun.
dirty_tree() {
  local p="$1"
  printf '\n<!-- BL-113 fixture: Phase-3 work in progress (uncommitted) -->\n' >> "$p/README.md"
}

# In every arm below the tree is DIRTIED after seeding — the NORMAL state while
# authoring Phase-3 artifacts, and precisely what makes the BL-082 staleness
# check autorun the driver with `--offline` (the laundering vector).
#
# (a) DRIVER carry-forward — semgrep NOT on PATH, so the gate's tool-presence
#     refusal cannot fire. The ONLY thing that can save us is the driver
#     promoting the offline SKIP back to FAIL. Fully hermetic.
NL_A="$TOPTMP/nl-carry"
rm -rf "$NL_A"; cp -R "$SCAFFOLD" "$NL_A"
seed_phase3 "$NL_A"
seed_prior_real_fail "$NL_A"
attest_all "$NL_A"
dirty_tree "$NL_A"
OUT_A="$( cd "$NL_A" && PATH="$NOSEMGREP_PATH" bash scripts/check-phase-gate.sh --gate phase_3_to_4 2>&1 )" || true
if printf '%s' "$OUT_A" | grep -q 'STALE'  && printf '%s' "$OUT_A" | grep -q 'last real result: FAIL'; then
  pass "T-no-launder-dirty-tree (a) driver carry-forward: gate shows '[STALE — last real result: FAIL]' instead of a fresh SKIP"
else
  fail_ "T-no-launder-dirty-tree (a)" "gate did NOT surface the carried-forward FAIL. Phase-3 lines: $(printf '%s' "$OUT_A" | grep -i 'phase 3' | tr '\n' '|')"
fi
if printf '%s' "$OUT_A" | grep -qi 'validation scans clean'; then
  fail_ "T-no-launder-dirty-tree (a)" "the gate reported 'validation scans clean' despite a prior REAL semgrep FAIL — THE LAUNDERING IS BACK"
else
  pass "T-no-launder-dirty-tree (a): the gate refuses to call the scans clean"
fi
# The attested SKIP must NOT be what carries the day: the summary must record FAIL.
NEW_SUM="$(ls -1 "$NL_A"/docs/test-results/phase3/summary-*.md 2>/dev/null | sort | tail -1)"
if [ -n "$NEW_SUM" ] && grep -q '^RESULT semgrep-full-tree FAIL' "$NEW_SUM"; then
  pass "T-no-launder-dirty-tree (a): the regenerated offline summary records semgrep FAIL, not SKIP"
else
  fail_ "T-no-launder-dirty-tree (a)" "the regenerated summary ($NEW_SUM) does not record semgrep FAIL: $(grep '^RESULT semgrep' "$NEW_SUM" 2>/dev/null | tr '\n' '|')"
fi

# (b) GATE refusal — semgrep IS on PATH (stub) and there is NO prior real FAIL,
#     so the carry-forward cannot fire. The ONLY thing that can save us is the
#     gate refusing an offline-autorun SKIP for an installed tool.
NL_B="$TOPTMP/nl-refuse"
rm -rf "$NL_B"; cp -R "$SCAFFOLD" "$NL_B"
seed_phase3 "$NL_B"
attest_all "$NL_B"
dirty_tree "$NL_B"
OUT_B="$( cd "$NL_B" && PATH="$STUBBIN:$NOSEMGREP_PATH" bash scripts/check-phase-gate.sh --gate phase_3_to_4 2>&1 )" || true
if printf '%s' "$OUT_B" | grep -q 'offline autorun SKIP REFUSED'; then
  pass "T-no-launder-dirty-tree (b) gate refusal: an offline-autorun SKIP for an INSTALLED semgrep is refused (attested or not)"
else
  fail_ "T-no-launder-dirty-tree (b)" "the gate accepted an attested offline-autorun SKIP while semgrep was installed. Phase-3 lines: $(printf '%s' "$OUT_B" | grep -i 'phase 3' | tr '\n' '|')"
fi
if printf '%s' "$OUT_B" | grep -qi 'validation scans clean'; then
  fail_ "T-no-launder-dirty-tree (b)" "the gate reported 'validation scans clean' for an offline SKIP of an INSTALLED scanner"
else
  pass "T-no-launder-dirty-tree (b): the gate refuses to call the scans clean"
fi

# ════════════════════════════════════════════════════════════════════════════
# T-offline-still-usable — the framework MUST work genuinely offline. No tool,
# no prior real FAIL → an honest attestable SKIP, and the Phase-3 validation arm
# of the gate PASSES.
# ════════════════════════════════════════════════════════════════════════════
echo "=== T-offline-still-usable: genuinely no tool → honest attestable SKIP → gate passable ==="
OFF="$TOPTMP/offline"
rm -rf "$OFF"; cp -R "$SCAFFOLD" "$OFF"
seed_phase3 "$OFF"
attest_all "$OFF"
dirty_tree "$OFF"
OUT_OFF="$( cd "$OFF" && PATH="$NOSEMGREP_PATH" bash scripts/check-phase-gate.sh --gate phase_3_to_4 2>&1 )" || true
if printf '%s' "$OUT_OFF" | grep -qi 'Phase 3→4: validation scans clean'; then
  pass "T-offline-still-usable: no tool + honest attestations → '[OK] validation scans clean' (the gate stays passable offline)"
else
  fail_ "T-offline-still-usable" "the Phase-3 validation arm BLOCKED a genuinely-offline, honestly-attested project — BL-113 must not break offline use. Phase-3 lines: $(printf '%s' "$OUT_OFF" | grep -i 'phase 3' | tr '\n' '|')"
fi
if printf '%s' "$OUT_OFF" | grep -q 'SKIP REFUSED'; then
  fail_ "T-offline-still-usable" "the gate REFUSED a SKIP even though no tool is installed — the refusal must be scoped to locally-installed tools"
else
  pass "T-offline-still-usable: no spurious refusal when the tool is genuinely absent"
fi

# ════════════════════════════════════════════════════════════════════════════
# T-mutation-no-launder — neuter the `# BL-113-NO-LAUNDER` decision bodies
# (marker intact) in BOTH the driver and the gate → T-no-launder must go RED.
# Restore → GREEN. This proves the marked lines are load-bearing, not decorative.
# ════════════════════════════════════════════════════════════════════════════
# (Under BL113_ONLY the guard harness is ALREADY driving this file against a
# neutered script — re-neutering here would be redundant and would double the
# harness's runtime, so the in-file mutation arms stand down.)
if [ "$BL113_ONLY" = "no-launder" ]; then
  echo "=== T-mutation-no-launder — SKIPPED (BL113_ONLY=no-launder; the guard harness owns the mutation) ==="
else
echo "=== T-mutation-no-launder: neuter the BL-113-NO-LAUNDER decision bodies ==="

# neuter <file> — replace every CODE line carrying the marker with `: # marker`
# (marker intact, body gone). Comment-only lines are left alone. The exec bit is
# RESTORED afterwards: the gate's autorun is guarded by `[ -x "$P3_DRIVER" ]`, so
# a mutant that merely lost its +x would block for the WRONG reason and give a
# false RED (the mutation must fail the gate *by laundering*, not by absence).
neuter() {
  local f="$1"
  sed -e '/^[[:space:]]*#/!s|^\([[:space:]]*\).*# BL-113-NO-LAUNDER.*$|\1: # BL-113-NO-LAUNDER (NEUTERED BY MUTATION TEST)|' \
      "$f" > "$f.mut" && mv "$f.mut" "$f"
  chmod +x "$f"
}

MUTP="$TOPTMP/mut-launder"
rm -rf "$MUTP"; cp -R "$SCAFFOLD" "$MUTP"
neuter "$MUTP/scripts/run-phase3-validation.sh"
neuter "$MUTP/scripts/check-phase-gate.sh"

mut_driver_hits="$(grep -c 'NEUTERED BY MUTATION TEST' "$MUTP/scripts/run-phase3-validation.sh" 2>/dev/null || echo 0)"
mut_gate_hits="$(grep -c 'NEUTERED BY MUTATION TEST' "$MUTP/scripts/check-phase-gate.sh" 2>/dev/null || echo 0)"
if [ "$mut_driver_hits" -ge 1 ] && [ "$mut_gate_hits" -ge 1 ] \
   && bash -n "$MUTP/scripts/run-phase3-validation.sh" 2>/dev/null \
   && bash -n "$MUTP/scripts/check-phase-gate.sh" 2>/dev/null; then
  pass "T-mutation-no-launder: neutered $mut_driver_hits driver + $mut_gate_hits gate decision line(s); both still parse (marker intact)"
else
  fail_ "T-mutation-no-launder setup" "neuter did not apply cleanly (driver=$mut_driver_hits gate=$mut_gate_hits) or broke syntax"
fi

# — RED arm (a): carry-forward, no semgrep on PATH —
seed_phase3 "$MUTP"
seed_prior_real_fail "$MUTP"
attest_all "$MUTP"
dirty_tree "$MUTP"
MOUT_A="$( cd "$MUTP" && PATH="$NOSEMGREP_PATH" bash scripts/check-phase-gate.sh --gate phase_3_to_4 2>&1 )" || true
if printf '%s' "$MOUT_A" | grep -qi 'validation scans clean'; then
  pass "T-mutation-no-launder RED(a): with the decision neutered the gate LAUNDERS again ('validation scans clean' despite a prior REAL FAIL) — the marked driver lines are load-bearing"
else
  fail_ "T-mutation-no-launder RED(a)" "neutering the driver decision did NOT reintroduce the laundering — the test is not actually pinned to the marked lines. Phase-3 lines: $(printf '%s' "$MOUT_A" | grep -i 'phase 3' | tr '\n' '|')"
fi

# — RED arm (b): gate refusal, semgrep stub on PATH, no prior FAIL —
MUTB="$TOPTMP/mut-launder-b"
rm -rf "$MUTB"; cp -R "$SCAFFOLD" "$MUTB"
neuter "$MUTB/scripts/run-phase3-validation.sh"
neuter "$MUTB/scripts/check-phase-gate.sh"
seed_phase3 "$MUTB"
attest_all "$MUTB"
dirty_tree "$MUTB"
MOUT_B="$( cd "$MUTB" && PATH="$STUBBIN:$NOSEMGREP_PATH" bash scripts/check-phase-gate.sh --gate phase_3_to_4 2>&1 )" || true
if printf '%s' "$MOUT_B" | grep -q 'offline autorun SKIP REFUSED'; then
  fail_ "T-mutation-no-launder RED(b)" "the refusal still fired with the marked gate line neutered — the assertion is not pinned to the decision"
else
  pass "T-mutation-no-launder RED(b): with the decision neutered the gate accepts the offline SKIP of an INSTALLED semgrep again — the marked gate line is load-bearing"
fi

# — GREEN restore: the pristine shipped scripts still hold the line. (NL_A/NL_B
#   above already exercised the un-mutated scripts and went GREEN; re-assert the
#   markers survive in the SOURCE so the mutation was to a copy, not the repo.)
if grep -q '# BL-113-NO-LAUNDER' "$DRIVER_SRC" && grep -q '# BL-113-NO-LAUNDER' "$GATE_SRC" \
   && ! grep -q 'NEUTERED BY MUTATION TEST' "$DRIVER_SRC" \
   && ! grep -q 'NEUTERED BY MUTATION TEST' "$GATE_SRC"; then
  pass "T-mutation-no-launder GREEN: the repo's own scripts are unmutated and still carry the BL-113-NO-LAUNDER markers"
else
  fail_ "T-mutation-no-launder GREEN" "the mutation leaked into the repo source — scripts/ must never be modified by this test"
fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
