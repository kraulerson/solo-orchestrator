#!/usr/bin/env bash
# NOTE: deliberately NOT `set -e`. A single scanner returning non-zero
# (findings, missing tool, auth prompt) must NOT abort the whole driver —
# the driver's job is to run EVERY registered scanner and aggregate.
set -uo pipefail

# ═══════════════════════════════════════════════════════════════════════
# scripts/run-phase3-validation.sh — BL-070 Phase 3 validation-scan driver
# (SKELETON: harness + gate integration + attest-on-skip; NOT all 5 real
# scanners — see the SCANNER REGISTRY notes below for what is real vs
# stubbed).
#
# WHY THIS EXISTS
#   The Builder's/User guides + workflow.html imply Phase 3 automatically
#   runs Snyk (deps), license compliance, full-tree Semgrep SAST, OWASP ZAP
#   DAST, and threat-model verification. A grep of scripts/ found ZERO
#   invocations of any of these tools — a documented gate mechanic that was
#   not real. BL-070 (Karl-approved Option C) builds the DRIVER + GATE first,
#   every scanner SKIP-able, and adds real scanners incrementally.
#
# ATTEST-ON-SKIP (Karl's refinement)
#   When a scanner is unavailable/SKIP, the operator decides whether to
#   download + run it manually. ANY skipped scanner requires an attestation
#   (a reason AND a sign-off) recorded in
#   `.claude/phase-state.json::phase3.attestations.<scanner>`. A non-attested
#   SKIP counts as a gate FAIL. Mirrors the BL-032 escape-hatch pattern and
#   reuses BL-071's atomic-finalize write pattern (mkdir-lock + adjacent
#   mktemp + rename) so the state write is race-safe on macOS bash-3.2.
#
# GATE INTEGRATION
#   scripts/check-phase-gate.sh auto-invokes this driver on the Phase 3→4
#   check and refuses the transition unless the aggregate summary exists AND
#   every scanner is PASS or attested-skip-with-signoff (zero un-attested
#   SKIPs, zero FAILs). See the `# BL-070-GATE-CHECK` block in that script.
#
# USAGE
#   bash scripts/run-phase3-validation.sh [--offline] [--results-dir DIR]
#                                         [--state FILE]
#   bash scripts/run-phase3-validation.sh --attest <scanner> \
#                                         --reason "<why skipped>" \
#                                         [--signoff "<who>"]
#   bash scripts/run-phase3-validation.sh --list
#   bash scripts/run-phase3-validation.sh --help
#
# EXIT CODES
#   0 — every scanner PASS or attested-skip (gate-ready), or --attest/--list
#       succeeded.
#   1 — at least one un-attested SKIP or a scanner FAIL (the gate would
#       block Phase 3→4).
#   2 — usage / precondition error (bad flag, jq missing for --attest).
#
# bash-3.2 safe: no associative arrays, no mapfile, no `${var^^}`.
# ═══════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors (mirror helpers-core.sh; kept inline so the driver has no hard
# dependency on the helper lib when invoked from odd contexts).
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi

# ── SCANNER REGISTRY ─────────────────────────────────────────────────
# The five documented Phase 3 checks. Order is stable (used by --list, the
# summary, and the gate's per-scanner loop). Each name maps (via case
# dispatch in _p3_run_scanner / _p3_scan_*) to a detect+run implementation.
#
#   semgrep-full-tree  REAL   — full-tree SAST (`semgrep --config auto`),
#                               distinct from pre-commit-gate.sh's staged-
#                               only scan. Runs when semgrep is on PATH and
#                               we are not --offline; SKIP otherwise.
#   license            STUB   — dependency-license compliance. The per-
#                               language matrix (license-checker / pip-
#                               licenses / cargo-license / dotnet-project-
#                               licenses) is a LATER INCREMENT; always SKIP.
#   snyk               STUB   — `snyk test --json` needs `snyk auth` +
#                               network. Registered but SKIP in the skeleton
#                               (do NOT auto-run an auth prompt).
#   zap-dast           STUB   — OWASP ZAP baseline needs Docker + a live
#                               URL. Registered but SKIP in the skeleton.
#   threat-model       STUB   — parse docs/threat-model.md mitigation IDs vs
#                               the test suite. Registered but SKIP in the
#                               skeleton.
P3_SCANNERS="semgrep-full-tree license snyk zap-dast threat-model"

_p3_label() {
  case "$1" in
    semgrep-full-tree) echo "Full-tree Semgrep SAST" ;;
    license)           echo "License compliance" ;;
    snyk)              echo "Snyk dependency scan" ;;
    zap-dast)          echo "OWASP ZAP DAST" ;;
    threat-model)      echo "Threat-model verification" ;;
    *)                 echo "$1" ;;
  esac
}

_p3_kind() {   # "real" or "stub" — surfaced in --list and the summary.
  case "$1" in
    semgrep-full-tree) echo "real" ;;
    *)                 echo "stub" ;;
  esac
}

# ── Defaults / arg parsing ───────────────────────────────────────────
OFFLINE="${SOLO_PHASE3_OFFLINE:-}"
RESULTS_DIR="docs/test-results/phase3"
STATE_FILE=".claude/phase-state.json"
MODE="run"           # run | attest | list
ATTEST_SCANNER=""
ATTEST_REASON=""
ATTEST_SIGNOFF=""

_p3_usage() {
  cat <<'EOF'
run-phase3-validation.sh — Phase 3 validation-scan driver (BL-070 skeleton)

Run all registered scanners and write an aggregate summary:
  bash scripts/run-phase3-validation.sh [--offline] [--results-dir DIR] [--state FILE]

Attest a skipped scanner (reason + sign-off, recorded in phase-state.json):
  bash scripts/run-phase3-validation.sh --attest <scanner> --reason "<why>" [--signoff "<who>"]

List the scanner registry:
  bash scripts/run-phase3-validation.sh --list

Flags:
  --offline            Force every real-execution scanner to SKIP (no
                       network / Docker / semgrep run). Also SOLO_PHASE3_OFFLINE=1.
  --results-dir DIR    Where to archive scan JSON + summary (default docs/test-results/phase3).
  --state FILE         phase-state.json path (default .claude/phase-state.json).
  --attest <scanner>   Record a skip-attestation for <scanner>.
  --reason "<why>"     Attestation reason (required with --attest).
  --signoff "<who>"    Attestation sign-off (defaults to git/host identity).
  --list               Print the scanner registry (name / kind / label).
  --help, -h           This help.

Scanners: semgrep-full-tree license snyk zap-dast threat-model
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --offline)      OFFLINE=1; shift ;;
    --results-dir)  RESULTS_DIR="${2:?--results-dir requires a value}"; shift 2 ;;
    --results-dir=*) RESULTS_DIR="${1#--results-dir=}"; shift ;;
    --state)        STATE_FILE="${2:?--state requires a value}"; shift 2 ;;
    --state=*)      STATE_FILE="${1#--state=}"; shift ;;
    --attest)       MODE="attest"; ATTEST_SCANNER="${2:?--attest requires a scanner name}"; shift 2 ;;
    --attest=*)     MODE="attest"; ATTEST_SCANNER="${1#--attest=}"; shift ;;
    --reason)       ATTEST_REASON="${2:?--reason requires a value}"; shift 2 ;;
    --reason=*)     ATTEST_REASON="${1#--reason=}"; shift ;;
    --signoff)      ATTEST_SIGNOFF="${2:?--signoff requires a value}"; shift 2 ;;
    --signoff=*)    ATTEST_SIGNOFF="${1#--signoff=}"; shift ;;
    --list)         MODE="list"; shift ;;
    --help|-h)      _p3_usage; exit 0 ;;
    *)
      echo -e "${RED}[FAIL]${NC} Unknown argument: '$1'" >&2
      echo "Run 'bash scripts/run-phase3-validation.sh --help' for usage." >&2
      exit 2
      ;;
  esac
done

_p3_is_registered() {
  case " $P3_SCANNERS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# ── Identity / attestation helpers ───────────────────────────────────
# Best-effort "who signed off" — prefers git identity, falls back to
# whoami@hostname (mirrors check-phase-gate.sh::_cpg_gate_actor).
_p3_actor() {
  local name email host
  name=$(git config user.name 2>/dev/null || echo "")
  email=$(git config user.email 2>/dev/null || echo "")
  if [ -n "$name" ] && [ -n "$email" ]; then
    printf '%s <%s>' "$name" "$email"
  elif [ -n "$name" ]; then
    printf '%s' "$name"
  else
    host=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "localhost")
    printf '%s@%s' "$(whoami 2>/dev/null || echo unknown)" "$host"
  fi
}

# _p3_is_attested <scanner>
# Returns 0 iff phase-state.json::phase3.attestations.<scanner> carries a
# non-empty reason AND a non-empty sign-off (the two-part attestation the
# gate requires). Returns 1 if jq is absent (conservative — an un-verifiable
# attestation is treated as un-attested → gate FAIL).
_p3_is_attested() {
  local name="$1" reason signoff
  command -v jq >/dev/null 2>&1 || return 1
  [ -f "$STATE_FILE" ] || return 1
  reason=$(jq -r --arg n "$name" '.phase3.attestations[$n].reason // ""' "$STATE_FILE" 2>/dev/null || echo "")
  signoff=$(jq -r --arg n "$name" '.phase3.attestations[$n].signoff // ""' "$STATE_FILE" 2>/dev/null || echo "")
  [ -n "$reason" ] && [ "$reason" != "null" ] && [ -n "$signoff" ] && [ "$signoff" != "null" ]
}

# _p3_write_attestation <scanner> <reason> <signoff>
# Atomically records phase3.attestations.<scanner> = {reason, signoff, at}
# into phase-state.json. Reuses BL-071's atomic-finalize lineage: a portable
# mkdir advisory lock (flock is unavailable on macOS bash-3.2), a temp file
# written ADJACENT to the state file so `mv` is a same-filesystem atomic
# rename, and an EXIT/INT/TERM trap contained in a subshell.
# Returns 0 on success, 2 on failure (jq missing, lock timeout, jq error).
_p3_write_attestation() {
  local name="$1" reason="$2" signoff="$3"
  local file="$STATE_FILE"

  if ! command -v jq >/dev/null 2>&1; then
    echo -e "${RED}[FAIL]${NC} --attest needs jq to edit $file structurally (jq not found)." >&2
    return 2
  fi

  mkdir -p "$(dirname "$file")" 2>/dev/null || true
  if [ ! -f "$file" ]; then
    echo '{"phase3":{"attestations":{}}}' > "$file"
  fi

  local at lock_dir attempts rc
  at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  lock_dir="$file.lockdir"

  attempts=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 100 ]; then
      echo -e "${YELLOW}[WARN]${NC} attestation write lock timeout (>10s; possible stale $lock_dir from a killed run — remove it and retry)." >&2
      return 2
    fi
    sleep 0.1
  done

  rc=0
  (
    tmp=$(mktemp "${file}.XXXXXX") || exit 1
    trap 'rm -f "$tmp"; rmdir "$lock_dir" 2>/dev/null' EXIT INT TERM
    if jq --arg n "$name" --arg r "$reason" --arg s "$signoff" --arg at "$at" \
         '.phase3 = (.phase3 // {}) | .phase3.attestations = ((.phase3.attestations // {}) + {($n): {"reason":$r,"signoff":$s,"at":$at}})' \
         "$file" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$file" || exit 1   # BL-070-ATTEST-WRITE: atomic attestation finalize (mutation target)
      trap - EXIT INT TERM
      exit 0
    else
      rm -f "$tmp"
      trap - EXIT INT TERM
      exit 1
    fi
  ) || rc=1
  rmdir "$lock_dir" 2>/dev/null || true

  if [ "$rc" -eq 0 ]; then
    return 0
  fi
  echo -e "${YELLOW}[WARN]${NC} attestation auto-write failed (jq error) — record it in $file manually." >&2
  return 2
}

# ── Scanner implementations ──────────────────────────────────────────
# Each _p3_scan_* sets three globals consumed by _p3_run_scanner:
#   P3_STATUS  — PASS | SKIP | FAIL
#   P3_NOTE    — human note for the summary
#   P3_ARCHIVE — path to the archived JSON, or "-"
P3_STATUS=""; P3_NOTE=""; P3_ARCHIVE="-"

# REAL — full-tree Semgrep SAST.
_p3_scan_semgrep() {
  local archive="$1"
  if [ -n "$OFFLINE" ]; then
    P3_STATUS="SKIP"; P3_NOTE="offline mode (--offline / SOLO_PHASE3_OFFLINE) — semgrep not run"
    return
  fi
  if ! command -v semgrep >/dev/null 2>&1; then
    P3_STATUS="SKIP"; P3_NOTE="semgrep not on PATH — install to enable full-tree SAST"
    return
  fi
  # REAL full-tree scan (distinct from pre-commit-gate.sh's staged-only scan).
  local rc=0
  semgrep --config auto --json --output "$archive" . >/dev/null 2>&1 || rc=$?
  P3_ARCHIVE="$archive"
  # semgrep exit: 0 = clean, 1 = findings, >=2 = execution error.
  if [ "$rc" -ge 2 ] || [ ! -f "$archive" ]; then
    P3_STATUS="FAIL"; P3_NOTE="semgrep execution error (rc=$rc)"
    return
  fi
  local findings=0
  if command -v jq >/dev/null 2>&1; then
    findings=$(jq '(.results | length) // 0' "$archive" 2>/dev/null || echo 0)
    case "$findings" in ''|*[!0-9]*) findings=0 ;; esac
  fi
  if [ "$findings" -gt 0 ]; then
    P3_STATUS="FAIL"; P3_NOTE="$findings semgrep finding(s) — review $archive"
  else
    P3_STATUS="PASS"; P3_NOTE="0 findings (full-tree --config auto)"
  fi
}

# STUB — license compliance. Always SKIP in the skeleton.
_p3_scan_license() {
  # BL-070 SKELETON STUB: the per-language dependency-license matrix
  # (license-checker / pip-licenses / cargo-license / dotnet-project-
  # licenses) is a later increment. Until then this scanner always SKIPs
  # and therefore requires an attestation — the gate never silently green-
  # lights an unscanned dependency tree.
  P3_STATUS="SKIP"
  P3_NOTE="license-compliance scanner stubbed (BL-070 skeleton) — wire the per-language license matrix in a later increment"
}

# STUB — Snyk dependency scan. Always SKIP in the skeleton.
_p3_scan_snyk() {
  # BL-070 SKELETON STUB: `snyk test --json` needs `snyk auth` + network.
  # We deliberately do NOT auto-run it (an auth prompt would hang unattended
  # runs). Real invocation is a later increment.
  P3_STATUS="SKIP"
  P3_NOTE="snyk dependency scan stubbed (BL-070 skeleton) — needs 'snyk auth'; wire 'snyk test --json' in a later increment"
}

# STUB — OWASP ZAP DAST. Always SKIP in the skeleton.
_p3_scan_zap() {
  # BL-070 SKELETON STUB: OWASP ZAP baseline needs Docker + a live target
  # URL (web/api platforms only). Real invocation is a later increment.
  P3_STATUS="SKIP"
  P3_NOTE="OWASP ZAP DAST stubbed (BL-070 skeleton) — needs Docker + a live URL; wire zap-baseline.py in a later increment"
}

# STUB — threat-model verification. Always SKIP in the skeleton.
_p3_scan_threat_model() {
  # BL-070 SKELETON STUB: parse docs/threat-model.md mitigation IDs and grep
  # the test suite for each mitigation's test-id anchor. Later increment.
  P3_STATUS="SKIP"
  P3_NOTE="threat-model verification stubbed (BL-070 skeleton) — parse docs/threat-model.md mitigations vs tests in a later increment"
}

# _p3_run_scanner <name> <timestamp> — dispatch to the right implementation.
_p3_run_scanner() {
  local name="$1" ts="$2"
  local archive="$RESULTS_DIR/${name}-${ts}.json"
  P3_STATUS="SKIP"; P3_NOTE=""; P3_ARCHIVE="-"
  case "$name" in
    semgrep-full-tree) _p3_scan_semgrep "$archive" ;;
    license)           _p3_scan_license "$archive" ;;
    snyk)              _p3_scan_snyk "$archive" ;;
    zap-dast)          _p3_scan_zap "$archive" ;;
    threat-model)      _p3_scan_threat_model "$archive" ;;
    *)                 P3_STATUS="FAIL"; P3_NOTE="unknown scanner" ;;
  esac
}

# ═══════════════════════════════════════════════════════════════════════
# MODE: list
# ═══════════════════════════════════════════════════════════════════════
if [ "$MODE" = "list" ]; then
  echo -e "${BOLD}Phase 3 scanner registry${NC}"
  for s in $P3_SCANNERS; do
    printf '  %-20s %-5s %s\n' "$s" "[$(_p3_kind "$s")]" "$(_p3_label "$s")"
  done
  exit 0
fi

# ═══════════════════════════════════════════════════════════════════════
# MODE: attest
# ═══════════════════════════════════════════════════════════════════════
if [ "$MODE" = "attest" ]; then
  if ! _p3_is_registered "$ATTEST_SCANNER"; then
    echo -e "${RED}[FAIL]${NC} --attest: '$ATTEST_SCANNER' is not a registered scanner. Valid: $P3_SCANNERS" >&2
    exit 2
  fi
  if [ -z "$ATTEST_REASON" ]; then
    echo -e "${RED}[FAIL]${NC} --attest requires --reason \"<why the scan was skipped>\"." >&2
    exit 2
  fi
  [ -n "$ATTEST_SIGNOFF" ] || ATTEST_SIGNOFF="$(_p3_actor)"
  if _p3_write_attestation "$ATTEST_SCANNER" "$ATTEST_REASON" "$ATTEST_SIGNOFF"; then
    echo -e "${GREEN}[OK]${NC} Attested skip for '$ATTEST_SCANNER' recorded in $STATE_FILE::phase3.attestations"
    echo "     reason:  $ATTEST_REASON"
    echo "     signoff: $ATTEST_SIGNOFF"
    exit 0
  fi
  echo -e "${RED}[FAIL]${NC} Could not record the attestation for '$ATTEST_SCANNER'." >&2
  exit 2
fi

# ═══════════════════════════════════════════════════════════════════════
# MODE: run — execute every registered scanner + write the aggregate summary
# ═══════════════════════════════════════════════════════════════════════
mkdir -p "$RESULTS_DIR" 2>/dev/null || {
  echo -e "${RED}[FAIL]${NC} Cannot create results dir: $RESULTS_DIR" >&2
  exit 2
}

# File-safe timestamp (dashes, no colons — sortable, matches the repo's
# `date -u +"%Y-%m-%dT%H-%M-%SZ"` file-stamp idiom). The `at`/Generated
# fields below use the colon form to match the repo's ISO-8601 body idiom.
TS=$(date -u +"%Y-%m-%dT%H-%M-%SZ")
GEN=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SUMMARY="$RESULTS_DIR/summary-${TS}.md"

echo -e "${BOLD}Phase 3 validation scans${NC}"
[ -n "$OFFLINE" ] && echo -e "${BLUE}[INFO]${NC} offline mode — real-execution scanners will SKIP (no network/Docker/semgrep run)."

# Accumulators.
n_pass=0; n_skip_attested=0; n_skip_unattested=0; n_fail=0
result_lines=""   # machine-readable "RESULT <name> <STATUS>" block
table_rows=""     # human Markdown table body

for s in $P3_SCANNERS; do
  _p3_run_scanner "$s" "$TS"
  status="$P3_STATUS"; note="$P3_NOTE"; archive="$P3_ARCHIVE"
  attested_col="-"

  case "$status" in
    PASS)
      n_pass=$((n_pass + 1))
      echo -e "  ${GREEN}[PASS]${NC} $s — $note"
      ;;
    SKIP)
      if _p3_is_attested "$s"; then
        attested_col="yes"
        n_skip_attested=$((n_skip_attested + 1))
        echo -e "  ${BLUE}[SKIP]${NC} $s — $note ${GREEN}(attested)${NC}"
      else
        attested_col="NO"
        n_skip_unattested=$((n_skip_unattested + 1))
        echo -e "  ${YELLOW}[SKIP]${NC} $s — $note ${RED}(UN-ATTESTED — attest or run manually)${NC}"
      fi
      ;;
    *)
      status="FAIL"
      n_fail=$((n_fail + 1))
      echo -e "  ${RED}[FAIL]${NC} $s — $note"
      ;;
  esac

  result_lines="${result_lines}RESULT ${s} ${status}
"
  table_rows="${table_rows}| ${s} | $(_p3_kind "$s") | ${status} | ${attested_col} | ${archive} | ${note} |
"
done

# Overall verdict: gate-ready iff no FAIL and no un-attested SKIP.
overall="PASS"
if [ "$n_fail" -gt 0 ] || [ "$n_skip_unattested" -gt 0 ]; then
  overall="FAIL"
fi

# Write the aggregate summary. The `RESULT <name> <STATUS>` lines are the
# machine-readable contract the gate parses (decoupled from the Markdown
# table formatting); live attestations are re-checked by the gate at read
# time, so attesting AFTER this summary is written still flips the gate.
{
  echo "# Phase 3 Validation Summary"
  echo ""
  echo "- Generated: ${GEN}"
  echo "- Offline: $([ -n "$OFFLINE" ] && echo yes || echo no)"
  echo "- Scanners: $(echo $P3_SCANNERS | wc -w | tr -d ' ')"
  echo "- PASS: ${n_pass}  SKIP(attested): ${n_skip_attested}  SKIP(un-attested): ${n_skip_unattested}  FAIL: ${n_fail}"
  echo "- Overall: ${overall}"
  echo ""
  echo "## Results"
  echo ""
  echo "| Scanner | Kind | Status | Attested | Archive | Note |"
  echo "|---|---|---|---|---|---|"
  printf '%s' "$table_rows"
  echo ""
  echo "## Machine-readable results (parsed by scripts/check-phase-gate.sh)"
  echo ""
  echo '```'
  printf '%s' "$result_lines"
  echo '```'
  echo ""
  echo "## Attest a skipped scanner"
  echo ""
  echo "A SKIP without an attestation blocks the Phase 3→4 gate. To attest:"
  echo ""
  echo '```'
  echo 'bash scripts/run-phase3-validation.sh --attest <scanner> --reason "<why skipped>"'
  echo '```'
} > "$SUMMARY"

echo ""
echo -e "${BOLD}Summary:${NC} $SUMMARY"
echo -e "  PASS=${n_pass}  SKIP(attested)=${n_skip_attested}  SKIP(un-attested)=${n_skip_unattested}  FAIL=${n_fail}  →  ${overall}"

if [ "$overall" = "PASS" ]; then
  echo -e "${GREEN}[OK]${NC} Phase 3 validation gate-ready (all PASS or attested-skip)."
  exit 0
fi
echo -e "${YELLOW}[ACTION]${NC} $n_skip_unattested un-attested SKIP(s) / $n_fail FAIL(s) block Phase 3→4."
echo "  Attest a skip:  bash scripts/run-phase3-validation.sh --attest <scanner> --reason \"...\""
echo "  Or install the tool and re-run (drop --offline) to get a real result."
exit 1
