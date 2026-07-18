#!/usr/bin/env bash
# NOTE: deliberately NOT `set -e`. A single scanner returning non-zero
# (findings, missing tool, auth prompt) must NOT abort the whole driver —
# the driver's job is to run EVERY registered scanner and aggregate.
set -uo pipefail

# ═══════════════════════════════════════════════════════════════════════
# scripts/run-phase3-validation.sh — BL-070 Phase 3 validation-scan driver.
# ALL FIVE registered scanners are now REAL (BL-070 completed 2026-07-10):
# semgrep-full-tree, license, snyk, zap-dast, threat-model. The tool-backed
# arms (semgrep / license / snyk / zap-dast) detect-and-run-if-available and
# SKIP under --offline so the gate autorun stays hermetic and instant; the
# pure-local threat-model arm runs even offline. Nothing is stubbed-by-decision.
# See the SCANNER REGISTRY notes below for each arm's detect/run/SKIP contract.
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
# SUMMARY PROVENANCE — tree binding (BL-082, 2026-07-09)
#   The summary header records the tree it validated so a stale summary cannot
#   satisfy the gate forever:
#       - tree: <git rev-parse HEAD^{tree}>   (or `none` outside a git repo)
#       - dirty: yes|no                        (scoped working-tree state)
#   `dirty` comes from a SCOPED `git status --porcelain` that EXCLUDES the
#   framework's OWN write surfaces — `.claude/` (this driver writes
#   attestations, and check-phase-gate.sh writes the BL-071 gate date, into
#   .claude/phase-state.json, which is TRACKED in downstream projects — the
#   generated .gitignore covers `test-results/` but not `.claude/`) and the
#   --results-dir (where this summary + scan archives land). WHY the scoping
#   (Karl-approved correction, 2026-07-09): an UNSCOPED dirty check would read
#   the tree as dirty the instant the gate writes phase-state.json on its first
#   PASS, marking every summary permanently stale (self-defeating; with
#   SOLO_PHASE3_GATE_NOAUTORUN=1 it bricks the gate). check-phase-gate.sh
#   re-checks freshness against the CURRENT tree AND live scoped porcelain and
#   regenerates when stale. Pre-BL-082 summaries have no `tree:` line and are
#   treated as STALE (backward compat).
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
#   license            REAL   — dependency-license compliance (BL-070
#                               increment). Reads the project language from
#                               .claude/tool-preferences.json (.context.language)
#                               and dispatches the per-language license tool
#                               (typescript→license-checker, python→pip-licenses,
#                               rust→cargo license, go→go-licenses, csharp→
#                               dotnet-project-licenses). Runs when the tool is
#                               on PATH and we are not --offline; unsupported
#                               language or missing tool → attestable SKIP.
#                               It INVENTORIES licenses AND (BL-086) enforces a
#                               tier-keyed DENY POLICY on the archived report:
#                               strong copyleft (GPL/AGPL/SSPL) BLOCKS the
#                               corporate track (deployment=organizational OR
#                               poc_mode=sponsored_poc OR private_poc); a pure
#                               personal project warns loudly instead. Override
#                               via .claude/license-policy.json; blocked-tier
#                               attested escape via SOLO_LICENSE_ATTESTED=1.
#   snyk               REAL   — dependency vulnerability scan (BL-070
#                               completion, WP-B3). Detect-and-run-if-available:
#                               SKIP under --offline; SKIP if `snyk` is not on
#                               PATH (names `npm install -g snyk`); SKIP if not
#                               authenticated (SNYK_TOKEN env OR a stored token
#                               via `snyk config get api` — names `snyk auth`);
#                               otherwise runs `snyk test --json`, archiving to
#                               snyk-<timestamp>.json. Findings policy MIRRORS
#                               the semgrep arm exactly (snyk exits 1 with a
#                               report when vulns are found): rc>=2 / no report →
#                               FAIL (execution error); vulnerabilities>0 → FAIL;
#                               0 vulns → PASS. Every SKIP is attestable.
#   zap-dast           REAL   — OWASP ZAP baseline DAST (BL-070 completion,
#                               WP-B4). Detect-and-run-if-available: SKIP under
#                               --offline; PLATFORM GATE FIRST — SKIP (attestable,
#                               never a silent auto-pass) unless
#                               .context.platform ∈ {web, api}; SKIP if `docker`
#                               is not on PATH; SKIP if SOLO_ZAP_TARGET_URL is
#                               unset (names the variable). Otherwise runs
#                               `zap-baseline.py` via the ghcr.io/zaproxy/zaproxy
#                               :stable image against SOLO_ZAP_TARGET_URL,
#                               archiving the JSON to zap-dast-<timestamp>.json.
#                               Findings policy MIRRORS the semgrep arm (zap-
#                               baseline exits 1/2 on FAIL-/WARN-level alerts
#                               while still producing a report): no report / rc>=3
#                               → FAIL (execution error); alerts>0 (or a non-zero
#                               baseline rc) → FAIL; 0 alerts → PASS.
#   threat-model       REAL   — threat-model verification (BL-070 increment).
#                               Validates every PROJECT_BIBLE.md Section-4
#                               `TM-NNN` threat row against the newest Phase-3
#                               threat-model VALIDATION REPORT in
#                               docs/test-results/ (glob accepts BOTH
#                               *_threat-model-validation.md and the legacy
#                               *_threat-validation.md name — a verified
#                               template naming inconsistency). PASS = every
#                               TM-ID is validated AND the Unmitigated table is
#                               empty-or-risk-accepted (each row has an
#                               Approved By); FAIL names the unaccounted IDs.
#                               No bible / no §4 table → attestable SKIP.
#                               UNLIKE the tool-backed arms this is PURE-LOCAL
#                               file parsing, so it deliberately RUNS under
#                               --offline (no tool/network to gate) — the gate
#                               autorun gets a real threat-model verdict.
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
  # BL-070 COMPLETE (2026-07-10): all five registered scanners are REAL; the
  # `*)` catch-all now only ever fires for an UNKNOWN name, never a shipped one.
  case "$1" in
    semgrep-full-tree) echo "real" ;;
    license)           echo "real" ;;
    snyk)              echo "real" ;;
    zap-dast)          echo "real" ;;
    threat-model)      echo "real" ;;
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

# ── BL-082 summary provenance ────────────────────────────────────────
# _p3_scoped_dirty <results_dir> — echo "yes" when the working tree has
# changes OUTSIDE the framework's own write surfaces, else "no".
# BL-082-STALENESS: the scoped porcelain EXCLUDES `.claude/` (this driver + the
# gate write phase-state.json there, and it is TRACKED downstream) and the
# results dir (this summary + scan archives), so a summary is not marked
# permanently stale by the very writes the gate makes on PASS. An absolute or
# parent-relative results dir is outside the porcelain scope already, so its
# exclusion is skipped (a repo-external path never appears in porcelain). Not a
# git repo / git error → conservative "yes". Kept textually identical to
# _cpg_scoped_dirty in scripts/check-phase-gate.sh.
_p3_scoped_dirty() {
  local rdir out
  rdir="${1:-}"
  rdir="${rdir#./}"
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "yes"; return 0
  fi
  case "$rdir" in
    ""|/*|../*|..)
      out=$(git status --porcelain -- . ':(exclude).claude' 2>/dev/null || true) ;;
    *)
      out=$(git status --porcelain -- . ':(exclude).claude' ":(exclude)$rdir" 2>/dev/null || true) ;;
  esac
  if [ -n "$out" ]; then echo "yes"; else echo "no"; fi
  return 0
}

# ── Identity / attestation helpers ───────────────────────────────────
# _p3_trim <string> — strip leading + trailing whitespace (bash-3.2 safe
# parameter-expansion idiom; same form as scripts/lint-counter-antipattern.sh
# parse_line). Load-bearing for the attestation checks: a whitespace-only
# reason/signoff must be treated as empty so the gate rejects it (verifier
# follow-up — `[ -n " " ]` is true, which would let " " pass as attested).
_p3_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

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

# ═══════════════════════════════════════════════════════════════════════
# BL-113 — NO LAUNDERING: a real FAIL is never downgraded to a fresh SKIP.
# ═══════════════════════════════════════════════════════════════════════
# THE DEFECT (walk finding F15). The 3→4 gate autoruns THIS driver with
# `--offline` whenever the working tree is dirty — the NORMAL state while the
# operator is authoring Phase-3 artifacts. `--offline` SKIPs every tool-backed
# scanner. So a scanner whose last REAL result was a FAIL (walk finding F14:
# semgrep FAILed on a fresh scaffold) was silently rewritten to SKIP, the
# operator attested the SKIP in good faith ("scanner unavailable"), and the
# gate passed. A FAIL is NOT attestable; a SKIP is. The offline autorun was
# the laundry.
#
# THE INVARIANT (marker `# BL-113-NO-LAUNDER`): a SKIP must never overwrite a
# prior REAL verdict of FAIL. When a scanner SKIPs, this driver looks back at
# the most recent summary that recorded a REAL (non-SKIP) verdict for that
# scanner. If that verdict was FAIL, the SKIP is REFUSED: the status is
# recorded as FAIL with a `[STALE - last real result: FAIL]` note plus a
# machine-readable `CARRIED <scanner> <origin>` line, so the gate blocks and
# the operator is told, in words, that the scan they are about to attest away
# was really run and really failed.
#
# WHY NOT "just run semgrep under the offline autorun" (option (i))? VERIFIED
# FALSE PREMISE: `semgrep --config auto` is NOT local-only. It hard-fetches its
# ruleset from https://semgrep.dev/c/auto and has NO local cache fallback — with
# the network blackholed it spends ~97s retrying, exits rc=2, and writes no
# report. Running it from the gate's autorun would therefore (a) make the gate
# non-hermetic and network-dependent, (b) add minutes to every dirty-tree gate
# run, and (c) brick genuinely-offline operators. The autorun stays `--offline`;
# the LAUNDERING is what dies, not the offline mode.
#
# OFFLINE MUST STAY USABLE. An honest "no tool / no network" SKIP remains
# attestable (that is what makes the framework work on a plane). Two supports:
#   * `_p3_scan_semgrep` now reports a registry-unreachable run as an honest
#     SKIP rather than a FAIL (see `# BL-113-SEMGREP-OFFLINE`), so an operator
#     with semgrep installed but no network can still produce a real, honest,
#     attestable non-result by running the driver WITHOUT --offline.
#   * The carry-forward below only fires when a REAL FAIL was actually observed.
#
# _p3_last_real_verdict <scanner> — echo "<PASS|FAIL> <origin-summary>" for the
# most recent summary in RESULTS_DIR that recorded a REAL (non-SKIP) verdict for
# <scanner>; echo "" when none exists. `CARRIED` provenance is preserved so the
# origin of a carried FAIL does not drift forward each run. Never returns
# non-zero (the verdict is the echoed string).
_p3_last_real_verdict() {
  local name="$1" f st origin
  [ -d "$RESULTS_DIR" ] || { echo ""; return 0; }
  # BL-130-SPACE-SAFE-LRV (E/F verifier MUST-FIX): the old unquoted
  # `for f in $(ls -1 … | sort -r)` word-split a spaced RESULTS_DIR into
  # fragments, every fragment failed [ -f ], and the verdict came back "" —
  # silently blinding BOTH the BL-130 attest-FAIL refusal and BL-113's
  # no-launder carry (this function is their shared oracle) on macOS-style
  # spaced paths. Glob into an array (space-safe; bash 3.2 has no nullglob —
  # the [ -f ] filter drops the unmatched-literal element) and walk it in
  # REVERSE: summary-<UTC-timestamp>.md names sort lexicographically =
  # chronologically, so reverse index order == `sort -r` == newest first.
  local _lrv_files _lrv_i
  _lrv_files=( "$RESULTS_DIR"/summary-*.md )
  _lrv_i=${#_lrv_files[@]}
  while [ "$_lrv_i" -gt 0 ]; do
    _lrv_i=$((_lrv_i - 1))
    f="${_lrv_files[$_lrv_i]}"
    [ -f "$f" ] || continue
    st=$(awk -v s="$name" '$1=="RESULT" && $2==s {v=$3} END{print v}' "$f" 2>/dev/null || true)
    case "$st" in
      PASS|FAIL)
        origin=$(awk -v s="$name" '$1=="CARRIED" && $2==s {v=$3} END{print v}' "$f" 2>/dev/null || true)
        [ -n "$origin" ] || origin=$(basename "$f")
        echo "${st} ${origin}"
        return 0
        ;;
    esac
  done
  echo ""
  return 0
}

# _p3_no_launder <scanner> — THE load-bearing BL-113 decision. Reads the just-
# computed P3_STATUS/P3_NOTE; if this run produced a SKIP but the scanner's most
# recent REAL verdict was a FAIL, promotes the SKIP back to FAIL and records the
# carry-forward origin in P3_CARRIED. Idempotent, and a no-op for PASS/FAIL.
P3_CARRIED=""
_p3_no_launder() {
  local name="$1" lrv lrv_status lrv_origin
  P3_CARRIED=""
  [ "$P3_STATUS" = "SKIP" ] || return 0
  lrv=$(_p3_last_real_verdict "$name")
  [ -n "$lrv" ] || return 0
  lrv_status="${lrv%% *}"
  lrv_origin="${lrv#* }"
  [ "$lrv_status" = "FAIL" ] || return 0
  P3_CARRIED="$lrv_origin"
  P3_STATUS="FAIL"
  P3_NOTE="[STALE - last real result: FAIL] SKIP REFUSED (was: ${P3_NOTE}) - the last REAL run of this scanner (${lrv_origin}) FAILED; an offline/unavailable SKIP does not clear it. Re-run for a real verdict: bash scripts/run-phase3-validation.sh (no --offline)"
  return 0
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
  reason=$(_p3_trim "$(jq -r --arg n "$name" '.phase3.attestations[$n].reason // ""' "$STATE_FILE" 2>/dev/null || echo "")")
  signoff=$(_p3_trim "$(jq -r --arg n "$name" '.phase3.attestations[$n].signoff // ""' "$STATE_FILE" 2>/dev/null || echo "")")
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
    # BL-113: an offline SKIP must DISCLOSE whether the tool is sitting right
    # there on PATH. "semgrep not run because the gate chose --offline, and
    # semgrep IS installed" is a very different thing to attest than "semgrep
    # is not available" — the gate refuses the former (# BL-113-NO-LAUNDER in
    # check-phase-gate.sh) precisely because the operator cannot honestly sign
    # "scanner unavailable" for a scanner that is installed.
    if command -v semgrep >/dev/null 2>&1; then
      P3_STATUS="SKIP"; P3_NOTE="offline mode (--offline / SOLO_PHASE3_OFFLINE) — semgrep not run, but semgrep IS INSTALLED locally: this SKIP is an artifact of the offline autorun, NOT a clean bill of health"
    else
      P3_STATUS="SKIP"; P3_NOTE="offline mode (--offline / SOLO_PHASE3_OFFLINE) — semgrep not run (semgrep is also not on PATH)"
    fi
    return
  fi
  if ! command -v semgrep >/dev/null 2>&1; then
    P3_STATUS="SKIP"; P3_NOTE="semgrep not on PATH — install to enable full-tree SAST"
    return
  fi
  # REAL full-tree scan (distinct from pre-commit-gate.sh's staged-only scan).
  local rc=0 errlog
  errlog=$(mktemp "${TMPDIR:-/tmp}/p3-semgrep-err-XXXXXX") || errlog="/dev/null"
  semgrep --config auto --json --output "$archive" . >/dev/null 2>"$errlog" || rc=$?
  P3_ARCHIVE="$archive"
  # semgrep exit: 0 = clean, 1 = findings, >=2 = execution error.
  if [ "$rc" -ge 2 ] || [ ! -f "$archive" ]; then
    # BL-113-SEMGREP-OFFLINE. `semgrep --config auto` is NOT local-only: it
    # fetches its ruleset from semgrep.dev and has no local-cache fallback, so
    # with no network it exits rc=2 having written NO report. Reporting that as
    # a FAIL would BRICK a genuinely-offline operator (a FAIL is not
    # attestable). A registry/network failure is an honest "could not look" —
    # i.e. a SKIP, attestable with a reason + sign-off, exactly like an absent
    # tool. A non-network execution error is still a real FAIL.
    if grep -qiE 'semgrep\.dev|max retries|proxyerror|connectionerror|nameresolution|failed to establish a new connection|temporary failure in name resolution|network is unreachable|failed to resolve' "$errlog" 2>/dev/null; then
      P3_STATUS="SKIP"
      P3_NOTE="semgrep could not reach its rule registry (semgrep.dev) — rc=$rc, no report produced. \`--config auto\` requires network; this is a no-network SKIP, not a clean result"
      P3_ARCHIVE="-"
      rm -f "$errlog" 2>/dev/null || true
      return
    fi
    P3_STATUS="FAIL"; P3_NOTE="semgrep execution error (rc=$rc)"
    rm -f "$errlog" 2>/dev/null || true
    return
  fi
  rm -f "$errlog" 2>/dev/null || true
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

# go-licenses emits CSV (package, license-URL, license-name), not JSON. Wrap
# its output into a minimal JSON envelope so the archived report is valid JSON
# like every other scanner's. Writes $1 and returns the tool's rc; on NO output
# it leaves $1 unwritten so the caller's non-empty-report check reports FAIL.
_p3_license_go_report() {
  local out="$1" csv rc=0
  csv=$(go-licenses report ./... 2>/dev/null) || rc=$?
  # No usable output → signal failure by NOT writing the archive (empty archive
  # → FAIL by the report-produced contract below).
  if [ -z "$csv" ]; then
    return "${rc:-1}"
  fi
  {
    printf '{"tool":"go-licenses","format":"csv","lines":['
    local first=1 line
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      if [ "$first" -eq 1 ]; then first=0; else printf ','; fi
      # JSON-escape backslashes then double-quotes (bash-3.2 safe).
      line=${line//\\/\\\\}
      line=${line//\"/\\\"}
      printf '"%s"' "$line"
    done <<EOF
$csv
EOF
    printf ']}\n'
  } > "$out"
  return 0
}

# ═══════════════════════════════════════════════════════════════════════
# BL-086 — tier-keyed license-policy DENY enforcement (2026-07-11)
# ═══════════════════════════════════════════════════════════════════════
# The BL-070 `license` arm INVENTORIES licenses (runs the per-language tool,
# archives the report, PASSes on a non-empty report). BL-086 adds a DENY
# POLICY on top, applied AFTER the inventory is archived (archive naming and
# BL-082 provenance are UNCHANGED — this only reads the archive back and, on a
# blocked-tier attestation, appends to phase-state.json under .claude/, which
# the BL-082 scoped-dirty check already excludes so it cannot re-mark the
# summary stale).
#
# DEFAULT DENY LIST — strong copyleft only. These are start-with STEMS matched
# against whole license TOKENS (see _p3_token_denied). Token start-with
# matching is inherently prefix/boundary-safe: "LGPL-3.0" is a single token
# that does NOT start with "GPL" (it starts with "L"), so an LGPL / MPL / EPL
# id can NEVER match a GPL stem — the prefix-safety the design requires, free.
#   GPL-2.0*  GPL-3.0*   GNU GPL v2 / v3 (all suffixes: -only / -or-later / +)
#   AGPL-1.0* AGPL-3.0*  GNU Affero GPL (copyleft triggers on network use alone)
#   SSPL-1.0             MongoDB Server Side Public License
#   GPL   AGPL           bare acronyms some tools emit ("GPLv3", "AGPLv3")
# EXPLICITLY NOT DENIED: LGPL-* (weak copyleft), MPL-*, EPL-*, and every
# permissive license (MIT, Apache-2.0, BSD-*, ISC, ...). Framework stance:
# block STRONG copyleft on the corporate track; the rest is the operator's
# call. Override the whole list via the .claude/license-policy.json DATA file.
#
# POLICY OVERRIDE (optional DATA file — NEVER a sourced script, so the BL-088
# source-closure check stays green): .claude/license-policy.json read via jq:
#     { "deny": ["SPDX-STEM", ...], "allow_packages": ["pkg", ...] }
#   • deny (when the key is PRESENT) REPLACES the default stem list entirely
#     (an empty array therefore denies nothing — a deliberate operator choice).
#   • allow_packages exempts named packages by name (the commercial-license
#     case): "pkg" matches an exact package name OR "pkg@<version>".
#   Malformed JSON → a LOUD scanner FAIL (never a silent skip of the policy).
DEFAULT_LICENSE_DENY="GPL-2.0 GPL-3.0 AGPL-1.0 AGPL-3.0 SSPL-1.0 GPL AGPL"

# _p3_token_denied <UPPERCASE-TOKEN> — 0 iff the token starts with any stem in
# $DENY_STEMS (dynamic-scoped from _p3_license_enforce). Token start-with
# matching is boundary-safe by construction (see the DEFAULT DENY LIST note).
_p3_token_denied() {
  local tok="$1" stem rc=1
  for stem in $DENY_STEMS; do
    # The guard skips empty stems AND keeps the loop body non-empty, so
    # excising the marked comparison below still yields a syntactically valid
    # (but non-denying) script — the load-bearing T-mutation-deny proof.
    [ -n "$stem" ] || continue
    case "$tok" in "$stem"*) rc=0 ;; esac   # BL-086-DENY: denied-stem comparison (mutation target #1)
  done
  return "$rc"
}

# _p3_alt_has_denied <UPPERCASE-ALTERNATIVE> — 0 iff the alternative (one side
# of a top-level OR; may itself be an AND-expression) carries a denied token.
# Tokenize by turning every non-[A-Z0-9.+-] char into a space so an SPDX id
# stays a single token and "GPL-3.0 AND MIT" splits into GPL-3.0 / AND / MIT.
_p3_alt_has_denied() {
  local toks t
  toks="$(printf '%s' "$1" | tr -c 'A-Z0-9.+-' ' ')"
  for t in $toks; do
    _p3_token_denied "$t" && return 0
  done
  return 1
}

# _p3_expr_flagged <license-expr> — 0 (FLAGGED) iff EVERY top-level OR
# alternative is denied; 1 (clean/elective) if any alternative is denied-free.
# FP HYGIENE: a dual license like "MIT OR GPL-3.0" is NOT flagged — the
# consumer may elect the safe (MIT) side. A bare denied id, or an AND-expression
# carrying a denied id, IS flagged. Simple top-level OR split (uppercase, strip
# parens, split on the literal " OR " operator — the spaces mean an internal
# "-OR-" in "GPL-2.0-OR-LATER" never splits); no full SPDX parser.
_p3_expr_flagged() {
  local u rest alt any_clean=1
  u="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr '()' '  ')"
  rest="$u"
  while :; do
    case "$rest" in
      *" OR "*) alt="${rest%%" OR "*}"; rest="${rest#*" OR "}" ;;
      *)        alt="$rest"; rest="" ;;
    esac
    if [ -n "$alt" ] && ! _p3_alt_has_denied "$alt"; then
      any_clean=0; break   # a denied-free alternative exists → package can elect it
    fi
    [ -n "$rest" ] || break
  done
  [ "$any_clean" -eq 1 ]
}

# _p3_pkg_allowed <pkg> <allow-list-newlines> — 0 iff <pkg> is exempted by an
# allow_packages entry (exact name, or "<name>@<version>"). Matched on the
# PACKAGE name, NEVER the license.
_p3_pkg_allowed() {
  local pkg="$1" allow_raw="$2" a
  [ -n "$allow_raw" ] || return 1
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    [ "$pkg" = "$a" ] && return 0
    case "$pkg" in "$a"@*) return 0 ;; esac
  done <<EOF
$allow_raw
EOF
  return 1
}

# _p3_go_csv_pairs — stdin: go-licenses CSV rows "pkg,license-url,license";
# stdout: "pkg<TAB>license" (field 1 + field 3; empty url handled).
_p3_go_csv_pairs() {
  local pkg url lic
  while IFS=, read -r pkg url lic; do
    [ -n "$pkg" ] || continue
    printf '%s\t%s\n' "$pkg" "$lic"
  done
}

# _p3_license_pairs <language> <archive> — echo "pkg<TAB>license" per package by
# parsing the archived report in that tool's format. Returns 2 when the archive
# is not valid JSON / not the expected shape (→ the caller LOUD-FAILs).
_p3_license_pairs() {
  local lang="$1" arch="$2"
  jq empty "$arch" 2>/dev/null || return 2
  case "$lang" in
    typescript) jq -r 'to_entries[] | [.key, ((.value.licenses // "") | if type=="array" then join(" AND ") else tostring end)] | @tsv' "$arch" 2>/dev/null || return 2 ;;
    python)     jq -r '.[] | [((.Name // "unknown")|tostring), ((.License // "")|tostring)] | @tsv' "$arch" 2>/dev/null || return 2 ;;
    rust)       jq -r '.[] | [((.name // "unknown")|tostring), ((.license // "")|tostring)] | @tsv' "$arch" 2>/dev/null || return 2 ;;
    csharp)     jq -r '.[] | [((.PackageName // .PackageId // .packageName // "unknown")|tostring), ((.LicenseType // .License // .licenseType // "")|tostring)] | @tsv' "$arch" 2>/dev/null || return 2 ;;
    go)         jq -r '.lines[]?' "$arch" 2>/dev/null | _p3_go_csv_pairs ;;
    *)          return 2 ;;
  esac
}

# _p3_license_warn_banner <findings-newline-list> — the LARGE, bordered,
# impossible-to-miss warning printed on the PURE-PERSONAL tier when a denied
# license is present (pure ASCII so it renders everywhere).
_p3_license_warn_banner() {
  local findings="$1" f
  echo ""
  echo "=============================================================================="
  echo "  !!  LICENSE WARNING - STRONG COPYLEFT DEPENDENCIES DETECTED (personal)  !!"
  echo "=============================================================================="
  echo "  These dependency license(s) are STRONG COPYLEFT (GPL / AGPL / SSPL class):"
  echo ""
  printf '%s\n' "$findings" | while IFS= read -r f; do
    [ -n "$f" ] && echo "      * $f"
  done
  echo ""
  echo "  This is ALLOWED for a PURELY PERSONAL project. But BEFORE you ever:"
  echo "      - DISTRIBUTE or SELL this project (ship binaries / an app / a library),"
  echo "      - RUN IT AS A COMMERCIAL SERVICE  (AGPL copyleft triggers on network"
  echo "        SERVICE alone - no distribution required),"
  echo "      - or TRANSITION it onto the organizational / sponsored-POC track,"
  echo ""
  echo "  you MUST first do ONE of these for EACH package above:"
  echo "      1. REMOVE the dependency,"
  echo "      2. obtain a COMMERCIAL license for it, or"
  echo "      3. OPEN-SOURCE your own project's source under a compatible copyleft"
  echo "         license (the share-your-source obligation travels with the code)."
  echo ""
  echo "  A private POC or ANY corporate-track project would be HARD-BLOCKED here;"
  echo "  you may proceed today only because this project is purely personal."
  echo "=============================================================================="
  echo ""
}

# _p3_write_license_exception <pkgs-nl> <lics-nl> <reason> — atomically append
# {date, packages[], licenses[], reason} to phase-state.json::phase3.
# license_exceptions[] (the BL-072/BL-032 attested-not-silenced lineage; same
# atomic tmp+mv + advisory-lock idiom as _p3_write_attestation). Returns 0 on
# success, 1 on any failure (jq missing, dir not writable, jq/mv error) — the
# caller turns a non-zero return into a scanner FAIL (recording failure REFUSES
# the pass). A fast writability probe fails an unwritable .claude immediately
# instead of spinning on the lock.
_p3_write_license_exception() {
  local pkgs="$1" lics="$2" reason="$3"
  local file="$STATE_FILE"

  if ! command -v jq >/dev/null 2>&1; then
    echo -e "${RED}[FAIL]${NC} license exception needs jq to edit $file (jq not found)." >&2
    return 1
  fi

  mkdir -p "$(dirname "$file")" 2>/dev/null || true
  if [ ! -f "$file" ]; then
    echo '{"phase3":{}}' > "$file" 2>/dev/null || {
      echo -e "${RED}[FAIL]${NC} cannot create $file to record the license exception." >&2
      return 1
    }
  fi

  # Fast writability probe (adjacent temp) — an unwritable state dir FAILs now.
  if ! ( : > "$file.wtest" ) 2>/dev/null; then
    echo -e "${RED}[FAIL]${NC} cannot write next to $file (state dir not writable) — license exception NOT recorded." >&2
    return 1
  fi
  rm -f "$file.wtest" 2>/dev/null || true

  local at lock_dir attempts rc
  at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  lock_dir="$file.lockdir"
  attempts=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 100 ]; then
      echo -e "${RED}[FAIL]${NC} license-exception write lock timeout (>10s; stale $lock_dir from a killed run?)." >&2
      return 1
    fi
    sleep 0.1
  done

  rc=0
  (
    tmp=$(mktemp "${file}.XXXXXX") || exit 1
    trap 'rm -f "$tmp"; rmdir "$lock_dir" 2>/dev/null' EXIT INT TERM
    if jq --arg at "$at" --arg pkgs "$pkgs" --arg lics "$lics" --arg reason "$reason" \
         '.phase3 = (.phase3 // {}) | .phase3.license_exceptions = ((.phase3.license_exceptions // []) + [{"date":$at,"packages":($pkgs|split("\n")|map(select(length>0))),"licenses":($lics|split("\n")|map(select(length>0))),"reason":$reason}])' \
         "$file" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$file" || exit 1
      trap - EXIT INT TERM
      exit 0
    else
      rm -f "$tmp"
      trap - EXIT INT TERM
      exit 1
    fi
  ) || rc=1
  rmdir "$lock_dir" 2>/dev/null || true
  return "$rc"
}

# _p3_license_enforce <language> <archive> <tool> — the BL-086 policy pass.
# Runs ONLY after a clean inventory (P3_STATUS=PASS). Reads the archived report,
# loads the deny policy, flags denied packages, and applies the TIER RULE. May
# set P3_STATUS=FAIL (blocked tier / unparseable / policy malformed / attest
# record failure) or leave it PASS (no denied licenses, OR-election, exempt,
# pure-personal warn, or a recorded attestation).
_p3_license_enforce() {
  local lang="$1" arch="$2" tool="$3"

  # ── policy override (optional DATA file, never sourced) ──
  local policy=".claude/license-policy.json"
  local DENY_STEMS="$DEFAULT_LICENSE_DENY"
  local allow_raw=""
  if [ -f "$policy" ]; then
    if ! command -v jq >/dev/null 2>&1 || ! jq empty "$policy" 2>/dev/null; then
      P3_STATUS="FAIL"
      P3_NOTE="license policy $policy is malformed JSON (or jq unavailable) — refusing the deny scan; fix or remove it"
      return
    fi
    if [ "$(jq -r 'has("deny")' "$policy" 2>/dev/null)" = "true" ]; then
      DENY_STEMS="$(jq -r '.deny[]? | ascii_upcase' "$policy" 2>/dev/null | tr '\n' ' ')"
    fi
    allow_raw="$(jq -r '.allow_packages[]?' "$policy" 2>/dev/null)"
  fi

  # ── extract (package, license) pairs from the archived inventory ──
  local pairs prc=0
  pairs="$(_p3_license_pairs "$lang" "$arch")" || prc=$?
  if [ "$prc" -ne 0 ]; then
    P3_STATUS="FAIL"
    P3_NOTE="license report ($tool/$lang) could not be parsed for the deny scan — invalid/unrecognised format in $arch (treat as a scan failure, not a skip)"
    return
  fi

  # ── evaluate each package against the deny policy ──
  local pkg lic findings="" findings_inline="" denied_pkgs="" denied_lics="" n=0
  while IFS="$(printf '\t')" read -r pkg lic; do
    [ -n "$pkg" ] || continue
    # allow_packages exemption (commercial-license case) — on the PACKAGE name.
    _p3_pkg_allowed "$pkg" "$allow_raw" && continue
    if _p3_expr_flagged "$lic"; then
      n=$((n + 1))
      findings_inline="${findings_inline}${findings_inline:+, }${pkg} (${lic})"
      findings="${findings}${pkg} (${lic})
"
      denied_pkgs="${denied_pkgs}${pkg}
"
      denied_lics="${denied_lics}${lic}
"
    fi
  done <<EOF
$pairs
EOF

  # No denied licenses → the inventory PASS stands (annotate the note).
  if [ "$n" -eq 0 ]; then
    P3_NOTE="${P3_NOTE}; policy: 0 denied license(s)"
    return
  fi

  # Denied licenses present → the TIER decides block vs. warn. Read
  # deployment + poc_mode from phase-state.json — NEVER `track` (spoofable:
  # a sponsored/production project can carry track=light non-interactively).
  local deployment poc_mode
  deployment="$(grep -o '"deployment"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" 2>/dev/null | sed 's/.*: *"//' | sed 's/"//')"
  poc_mode="$(grep -o '"poc_mode"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" 2>/dev/null | sed 's/.*: *"//' | sed 's/"//')"

  # BL-086-TIER: which tiers BLOCK on a denied license. DELIBERATELY STRICTER
  # than BL-084's bypass predicate: BL-084 treats poc_mode=private_poc as
  # Personal-adjacent (BYPASSABLE) for the remote-PUSH gate, but here a private
  # POC BLOCKS. WHY: a strong-copyleft dependency is a one-way ratchet. A
  # private POC is the framework's runway to a Sponsored POC / production; at
  # that transition the company must rip the dependency out, buy a commercial
  # license, or accept share-your-source obligations on distribution / network
  # service. No sponsor approves that, so the whole corporate track —
  # deployment=organizational OR poc_mode=sponsored_poc OR poc_mode=private_poc
  # — BLOCKS. Only a PURE personal project (deployment=personal, no poc_mode)
  # is allowed to proceed, and then only behind a loud warning banner.
  # Missing/empty phase-state (mothership / unscaffolded) → pure personal.
  local blocked=false
  [ "$deployment" = "organizational" ] || [ "$poc_mode" = "sponsored_poc" ] || [ "$poc_mode" = "private_poc" ] && blocked=true   # BL-086-TIER

  if [ "$blocked" = true ]; then
    # ATTESTED escape (attested, never silenced): record + PASS, or FAIL.
    if [ "${SOLO_LICENSE_ATTESTED:-}" = "1" ]; then
      local reason
      reason="${SOLO_LICENSE_REASON:-unspecified — attested via SOLO_LICENSE_ATTESTED}"
      if _p3_write_license_exception "$denied_pkgs" "$denied_lics" "$reason"; then
        echo -e "  ${BLUE}[ATTESTED]${NC} license — $n denied-license package(s) attested (SOLO_LICENSE_ATTESTED): ${findings_inline} — reason: ${reason}"
        P3_STATUS="PASS"
        P3_NOTE="ATTESTED: $n package(s) carry denied licenses but were attested (recorded to ${STATE_FILE}::phase3.license_exceptions[]): ${findings_inline}"
      else
        P3_STATUS="FAIL"
        P3_NOTE="denied license(s) present and the attestation record FAILED — refusing to pass; record it manually in ${STATE_FILE}::phase3.license_exceptions[]: ${findings_inline}"
      fi
      return
    fi
    P3_STATUS="FAIL"
    P3_NOTE="$n package(s) carry denied licenses: ${findings_inline}"
    return
  fi

  # PURE-PERSONAL tier: proceed, but emit the LARGE warning banner.
  _p3_license_warn_banner "$findings"
  P3_STATUS="PASS"
  P3_NOTE="PERSONAL project: $n package(s) carry strong-copyleft licenses — ALLOWED with a warning (see banner above): ${findings_inline}"
}

# REAL — dependency-license compliance (BL-070 increment; BL-086 deny policy).
_p3_scan_license() {
  local archive="$1"
  if [ -n "$OFFLINE" ]; then
    P3_STATUS="SKIP"; P3_NOTE="offline mode (--offline / SOLO_PHASE3_OFFLINE) — license scan not run"
    return
  fi

  # Language source: .claude/tool-preferences.json::.context.language. This is
  # the CANONICAL reader (mirrors scripts/check-phase-gate.sh's TOOL_PREFS
  # block). NOT .claude/manifest.json — that file holds only host/mode/
  # remote_url, so reading it returns empty and the scanner would silently
  # always-SKIP (the code-verify-reconfigure-1 bug class).
  local language=""
  if command -v jq >/dev/null 2>&1 && [ -f ".claude/tool-preferences.json" ]; then
    language=$(jq -r '.context.language // ""' ".claude/tool-preferences.json" 2>/dev/null || echo "")
  fi
  [ "$language" = "null" ] && language=""

  # Select the per-language license tool. Language values are platform-
  # dependent (web adds csharp/go/java/kotlin/other; mobile/desktop add
  # swift/dart), so an explicit `*)` catch-all is REQUIRED: any unknown
  # language → attestable SKIP.
  local tool=""
  case "$language" in
    typescript) tool="license-checker" ;;
    python)     tool="pip-licenses" ;;
    rust)       tool="cargo-license" ;;
    go)         tool="go-licenses" ;;
    csharp)     tool="dotnet-project-licenses" ;;
    java|kotlin|swift|dart|other|"")
      P3_STATUS="SKIP"
      P3_NOTE="no canonical license tool for language '${language:-unknown}' — run your ecosystem's license audit manually (e.g. Gradle license plugin / SwiftLicenseChecker), then attest"
      return ;;
    *)
      P3_STATUS="SKIP"
      P3_NOTE="no canonical license tool for language '$language' — run your ecosystem's license audit manually, then attest"
      return ;;
  esac

  # Tool not provisioned → attestable SKIP (the operator installs it or runs
  # the audit manually and attests; the gate never silently green-lights an
  # unscanned dependency tree).
  if ! command -v "$tool" >/dev/null 2>&1; then
    P3_STATUS="SKIP"
    P3_NOTE="$tool not on PATH — install it to enable license compliance for '$language', or run the audit manually and attest"
    return
  fi

  # Run the selected tool, archiving its JSON report. "report-produced"
  # semantics: some license tools exit 1 while still emitting a valid report,
  # so success is measured by a NON-EMPTY archive, NOT by rc==0.
  local rc=0
  case "$language" in
    typescript) license-checker --json          > "$archive" 2>/dev/null || rc=$? ;;  # BL-070-LICENSE-DISPATCH
    python)     pip-licenses --format=json       > "$archive" 2>/dev/null || rc=$? ;;
    rust)       cargo license --json             > "$archive" 2>/dev/null || rc=$? ;;
    csharp)     dotnet-project-licenses -j        > "$archive" 2>/dev/null || rc=$? ;;
    go)         _p3_license_go_report "$archive"                          || rc=$? ;;
  esac
  P3_ARCHIVE="$archive"

  # Inventory contract (BL-070): PASS = a non-empty report exists, FAIL = the
  # tool crashed / produced no output. BL-086 then layers a DENY POLICY on the
  # archived inventory (tier-keyed block vs. warn) — only when the inventory
  # itself succeeded (a crashed/empty report has nothing to judge).
  if [ -s "$archive" ]; then
    P3_STATUS="PASS"; P3_NOTE="license inventory produced via $tool ($language) — $archive"
    _p3_license_enforce "$language" "$archive" "$tool"   # BL-086: deny-policy enforcement on the archived inventory
  else
    P3_STATUS="FAIL"; P3_NOTE="$tool produced no license report (rc=$rc) — treat as a scan failure, not a skip"
  fi
}

# REAL — Snyk dependency vulnerability scan (BL-070 completion, WP-B3).
#
# Detect-and-run-if-available ONLY (no auth prompt, no network under --offline):
#   --offline                → SKIP (attestable), mirroring the semgrep arm — the
#                              gate autorun runs --offline and must stay hermetic.
#   snyk not on PATH         → SKIP (attestable), naming `npm install -g snyk`.
#   snyk on PATH, no auth    → SKIP (attestable), naming `snyk auth`. Auth is the
#                              canonical snyk way: SNYK_TOKEN env (CI convention)
#                              OR a stored token that `snyk config get api`
#                              prints (empty when unauthenticated). Cheap +
#                              mockable; never triggers interactive `snyk auth`.
#   authenticated            → run `snyk test --json`, archive to
#                              snyk-<timestamp>.json.
#
# Findings policy MIRRORS _p3_scan_semgrep EXACTLY (verified against the semgrep
# arm above): snyk exits 0 = no vulns, 1 = vulnerabilities found (still emits a
# JSON report), 2 = execution error, 3 = no supported project. So — like
# semgrep — rc>=2 OR no report → FAIL (execution error); findings>0 → FAIL;
# 0 findings → PASS. This is a SECURITY scanner (findings block), NOT an
# inventory like the license arm.
_p3_scan_snyk() {
  local archive="$1"
  if [ -n "$OFFLINE" ]; then
    P3_STATUS="SKIP"; P3_NOTE="offline mode (--offline / SOLO_PHASE3_OFFLINE) — Snyk dependency scan not run"
    return
  fi
  if ! command -v snyk >/dev/null 2>&1; then
    P3_STATUS="SKIP"
    P3_NOTE="snyk not on PATH — install it (npm install -g snyk) to enable the dependency scan, or run it manually and attest"
    return
  fi
  # Auth detection (cheap, non-interactive): SNYK_TOKEN env OR a stored token.
  local snyk_api=""
  snyk_api="$(snyk config get api 2>/dev/null || echo "")"
  if [ -z "${SNYK_TOKEN:-}" ] && [ -z "$snyk_api" ]; then
    P3_STATUS="SKIP"
    P3_NOTE="snyk not authenticated — run 'snyk auth' (or set SNYK_TOKEN) to enable the dependency scan, or run it manually and attest"
    return
  fi
  # Run the dependency scan (rc captured; snyk exits 1 WITH a report on findings).
  local rc=0
  snyk test --json > "$archive" 2>/dev/null || rc=$?   # BL-070-SNYK-DISPATCH
  P3_ARCHIVE="$archive"
  # rc>=2 (execution error / no supported project) OR an empty report → FAIL,
  # mirroring semgrep's "rc>=2 || no archive → execution error".
  if [ "$rc" -ge 2 ] || [ ! -s "$archive" ]; then
    P3_STATUS="FAIL"; P3_NOTE="snyk execution error (rc=$rc) — no usable report; treat as a scan failure, not a skip"
    return
  fi
  local findings=0
  if command -v jq >/dev/null 2>&1; then
    findings=$(jq '(.vulnerabilities | length) // 0' "$archive" 2>/dev/null || echo 0)
    case "$findings" in ''|*[!0-9]*) findings=0 ;; esac
  fi
  if [ "$findings" -gt 0 ]; then
    P3_STATUS="FAIL"; P3_NOTE="$findings snyk vulnerability finding(s) — review $archive"
  else
    P3_STATUS="PASS"; P3_NOTE="0 vulnerabilities (snyk test --json)"
  fi
}

# REAL — OWASP ZAP baseline DAST (BL-070 completion, WP-B4).
#
# Detect-and-run-if-available ONLY (Docker + network only when everything lines
# up; SKIP otherwise so the gate autorun stays hermetic):
#   --offline                → SKIP (attestable), mirroring the semgrep arm.
#   PLATFORM GATE (FIRST)    → read .context.platform the CANONICAL way (same
#                              reader as scripts/check-phase-gate.sh); platform
#                              ∉ {web, api} → SKIP (attestable) — DAST is a web/
#                              api concern. Conservative + attestable, NEVER a
#                              silent auto-pass.
#   docker not on PATH       → SKIP (attestable).
#   SOLO_ZAP_TARGET_URL unset→ SKIP (attestable), naming the variable — a DAST
#                              scan needs a live target.
#   all present              → run `zap-baseline.py` via the pinned ZAP image,
#                              archive the JSON to zap-dast-<timestamp>.json.
#
# Findings policy MIRRORS _p3_scan_semgrep: zap-baseline exits 0 = clean,
# 1 = FAIL-level alerts, 2 = WARN-level alerts (both still emit a JSON report),
# >=3 = execution error. So — like semgrep — no report / rc>=3 → FAIL (execution
# error); alerts>0 (or a non-zero baseline rc) → FAIL; 0 alerts → PASS.
_p3_scan_zap() {
  local archive="$1"
  if [ -n "$OFFLINE" ]; then
    P3_STATUS="SKIP"; P3_NOTE="offline mode (--offline / SOLO_PHASE3_OFFLINE) — OWASP ZAP DAST not run"
    return
  fi

  # PLATFORM GATE (first substantive check). DAST applies to web/api only.
  # .context.platform in .claude/tool-preferences.json is the CANONICAL source
  # (NOT manifest.json) — same reader as check-phase-gate.sh:1766.
  local platform=""
  if command -v jq >/dev/null 2>&1 && [ -f ".claude/tool-preferences.json" ]; then
    platform=$(jq -r '.context.platform // ""' ".claude/tool-preferences.json" 2>/dev/null || echo "")
  fi
  [ "$platform" = "null" ] && platform=""
  case "$platform" in
    web|api) : ;;   # DAST-eligible
    *)
      P3_STATUS="SKIP"
      P3_NOTE="DAST not applicable to platform '${platform:-unknown}' — OWASP ZAP runs for web/api platforms only; attest to record the skip"
      return ;;
  esac

  # Docker is required to run the ZAP baseline image.
  if ! command -v docker >/dev/null 2>&1; then
    P3_STATUS="SKIP"
    P3_NOTE="docker not on PATH — install Docker to enable OWASP ZAP DAST, or run the baseline scan manually and attest"
    return
  fi

  # A DAST scan needs a live target URL.
  if [ -z "${SOLO_ZAP_TARGET_URL:-}" ]; then
    P3_STATUS="SKIP"
    P3_NOTE="no target URL — set SOLO_ZAP_TARGET_URL=<live app/api URL> to enable OWASP ZAP DAST, or run it manually and attest"
    return
  fi

  # Run the ZAP baseline scan via Docker. `-J <name>` writes the JSON report into
  # the container's /zap/wrk, which is bind-mounted to a host tmpdir; copy it out
  # to the archive afterwards. Whole invocation kept on ONE physical line so the
  # mutation marker excises the entire dispatch (removing it → no report → FAIL).
  local zap_tmp rc=0
  zap_tmp=$(mktemp -d "${TMPDIR:-/tmp}/p3-zap-XXXXXX") || {
    P3_STATUS="FAIL"; P3_NOTE="could not create a temp dir for the ZAP report"; return
  }
  # BL-140-ZAP-WORKDIR-BEGIN
  # Dogfood-3 F-DF3-005: on macOS, mktemp lands in $TMPDIR (/var/folders/…),
  # which VM-based Docker runtimes (Colima and friends) do NOT share — only
  # /Users/<user> is mounted. The container then writes /zap/wrk/zap-report.json
  # into a bind that never syncs back: the driver FAILs a verifiably clean
  # app, and BL-130 (correctly) refuses to attest the FAIL — no path to
  # green. The work dir therefore lives under the PROJECT results tree,
  # which is where the operator works and inside the VM's shared mounts.
  # The mktemp above is kept as the excision-fallback: removing this fence
  # restores the old $TMPDIR behavior exactly (mutation target).
  rm -rf "$zap_tmp" 2>/dev/null || true
  zap_tmp="$RESULTS_DIR/.zap-work.$$"
  mkdir -p "$zap_tmp" || {
    P3_STATUS="FAIL"; P3_NOTE="could not create $zap_tmp for the ZAP report"; return
  }
  # BL-140-ZAP-WORKDIR-END
  docker run --rm -v "$zap_tmp:/zap/wrk" ghcr.io/zaproxy/zaproxy:stable zap-baseline.py -t "$SOLO_ZAP_TARGET_URL" -J zap-report.json >/dev/null 2>&1 || rc=$?   # BL-070-ZAP-DISPATCH
  if [ -f "$zap_tmp/zap-report.json" ]; then
    cp "$zap_tmp/zap-report.json" "$archive" 2>/dev/null || true
  fi
  rm -rf "$zap_tmp" 2>/dev/null || true
  P3_ARCHIVE="$archive"

  # No report at all → FAIL (docker/image/exec failure — a crash, not a skip).
  if [ ! -s "$archive" ]; then
    P3_STATUS="FAIL"; P3_NOTE="OWASP ZAP produced no report (rc=$rc) — treat as a scan failure, not a skip"
    # BL-140-ZAP-MOUNT-HINT-BEGIN
    # The FAIL posture is correct (an unreadable scan is not a clean scan —
    # the BL-112/BL-113 honesty class); the diagnosis must still be
    # ACTIONABLE: a report written in-container but absent host-side is the
    # classic VM-runtime mount gap.
    P3_NOTE="$P3_NOTE. If Docker runs in a VM (Colima/Rancher/Lima), ensure this project sits inside the VM's shared mounts (Colima shares /Users by default) — a container-side report that never lands host-side is the classic symptom; as a fallback, set TMPDIR to a mounted path."
    # BL-140-ZAP-MOUNT-HINT-END
    return
  fi
  # rc>=3 = execution error (docker error, image pull failure, ZAP crash) → FAIL.
  if [ "$rc" -ge 3 ]; then
    P3_STATUS="FAIL"; P3_NOTE="OWASP ZAP execution error (rc=$rc) — review $archive"
    return
  fi
  # BL-122-ZAP-RISK-FILTER — judge Medium+ (riskcode >= 2) alerts ONLY. The
  # unfiltered count made this gate unpassable for every web app: ZAP rule
  # 10049 (Storable/Cacheable Content, riskcode 0 = Informational) fires under
  # EVERY possible Cache-Control value, so findings >= 1 always, and BL-113
  # (correctly) refuses to attest past a FAIL (Dogfood-2 F-DF2-012). This
  # mirrors the semgrep arm's --severity=ERROR philosophy: block real issues
  # without drowning the operator in informational noise — lower-risk alerts
  # remain visible in the archived report. riskcode is a STRING in ZAP JSON
  # ("0".."3"); `// "0"` defaults a MISSING field to Informational, never to
  # blocking. An UNPARSEABLE report is a FAIL, never a pass — a report nobody
  # could read is not a clean scan (BL-112/BL-113 honesty class). jq may be
  # assumed here: a jq-less host never reaches this block — the platform
  # classification earlier in this function needs jq, and without it the arm
  # takes the attestable SKIP path (verifier-confirmed on the pre-fix code
  # too; there was never a jq-less silent pass). Baseline rc 1/2 alone no
  # longer FAILs: those are ZAP's own WARN/FAIL thresholds over ALL alerts
  # (informational included) — this risk filter IS the severity policy, and
  # crashes (no report / rc >= 3) already FAILed above.
  local findings
  if ! findings=$(jq '[.site[]?.alerts[]? | select(((.riskcode // "0") | tonumber) >= 2)] | length' "$archive" 2>/dev/null); then
    P3_STATUS="FAIL"; P3_NOTE="ZAP report unparseable by jq — refusing to guess; inspect $archive"
    return
  fi
  case "$findings" in ''|*[!0-9]*) findings=0 ;; esac
  if [ "$findings" -gt 0 ]; then
    P3_STATUS="FAIL"; P3_NOTE="$findings Medium+ ZAP alert(s) (riskcode>=2; baseline rc=$rc) — review $archive"
  else
    P3_STATUS="PASS"; P3_NOTE="0 Medium+ ZAP alerts (baseline rc=$rc; informational/low, if any, remain in $archive)"
  fi
}

# ── threat-model helpers (BL-070 increment, WP-B2) ───────────────────
# A "threat row" is a Markdown table line (carries a `|`) bearing a TM-NNN id.
# Threats live in PROJECT_BIBLE.md Section 4; the Phase-3 VALIDATION REPORT
# (docs/test-results/YYYY-MM-DD_threat-model-validation.md) carries a row per
# TM-ID plus an Unmitigated table whose accepted risks each need an approver.

# _p3_tm_has_table <file> — 0 iff <file> has at least one Section-4 threat row.
_p3_tm_has_table() {
  grep -E '\|' "$1" 2>/dev/null | grep -Eq 'TM-[0-9]{3}'
}

# _p3_tm_ids <file> — emit the whole-token TM-IDs from <file>'s table rows,
# sorted-unique, one per line. `TM-[0-9]{3,}` captures the FULL numeric token,
# so TM-001 and TM-0011 stay DISTINCT — the word-boundary guarantee the
# coverage diff below relies on.
_p3_tm_ids() {
  grep -E '\|' "$1" 2>/dev/null | grep -oE 'TM-[0-9]{3,}' | sort -u
}

# _p3_tm_count <words...> — count whitespace-separated tokens (no `wc`, so the
# counter-antipattern lint has nothing to match; zero args → 0).
_p3_tm_count() { echo "$#"; }

# _p3_tm_report <dir> — newest validation report under <dir>. The glob accepts
# BOTH conventional names (`*_threat-model-validation.md` per
# threat-model-validation.tmpl AND the legacy `*_threat-validation.md` name
# project-bible.tmpl linked to — a verified framework naming inconsistency).
# Name-sort → newest wins (report names lead with an ISO date), matching how
# the gate picks its summary. Empty if none match.
_p3_tm_report() {
  ls -1 "$1"/*threat-model-validation*.md "$1"/*threat-validation*.md 2>/dev/null | sort | tail -1
}

# _p3_tm_missing <bible-ids> <report-ids> — emit the Bible IDs ABSENT from the
# report's id-set, word-boundary-safe (space-padded token match → TM-0011 never
# satisfies TM-001). This IS the coverage comparison; its call site carries the
# load-bearing coverage-diff mutation marker.
_p3_tm_missing() {
  local bset="$1" rset="$2" id out=""
  for id in $bset; do
    case " $(echo $rset) " in
      *" $id "*) ;;                 # present → validated
      *) out="$out $id" ;;          # absent  → unvalidated
    esac
  done
  echo $out
}

# _p3_tm_unapproved <report> — emit the TM-IDs of rows in the report's
# "Unmitigated Threats" table whose Approved By column is empty. The approver
# column index is read from that section's header row (NOT hard-coded), so a
# column-layout change cannot silently defeat the check.
_p3_tm_unapproved() {
  awk '
    /^##[[:space:]]/ { insec = ($0 ~ /[Uu]nmitigated/) ? 1 : 0; acol = 0; next }
    insec && /\|/ {
      if ($0 ~ /^[[:space:]|:*-]+$/) next                       # separator row
      if (acol == 0 && $0 ~ /Approved/) {                       # header row
        n = split($0, c, "|")
        for (i = 1; i <= n; i++) if (c[i] ~ /Approved/) acol = i
        next
      }
      if ($0 ~ /TM-[0-9][0-9][0-9]/) {                          # data row
        n = split($0, c, "|")
        id = ""
        for (i = 1; i <= n; i++) if (match(c[i], /TM-[0-9]+/)) { id = substr(c[i], RSTART, RLENGTH); break }
        appr = (acol > 0 && acol <= n) ? c[acol] : ""
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", appr)
        if (appr == "") print id
      }
    }
  ' "$1"
}

# _p3_tm_archive <out> <total> <validated> <missing-ids> — write the scan JSON
# {ids_total, ids_validated, missing:[...]} like the other scanners archive.
_p3_tm_archive() {
  local out="$1" total="$2" validated="$3" missing="$4"
  local arr="" id first=1
  for id in $missing; do
    if [ "$first" -eq 1 ]; then first=0; else arr="$arr,"; fi
    arr="$arr\"$id\""
  done
  printf '{"scanner":"threat-model","ids_total":%s,"ids_validated":%s,"missing":[%s]}\n' \
    "$total" "$validated" "$arr" > "$out"
}

# REAL — threat-model verification (BL-070 increment, WP-B2).
#
# Validates that every threat recorded in PROJECT_BIBLE.md Section 4 (as
# `TM-NNN` table rows) is accounted for by the newest Phase-3 threat-model
# VALIDATION REPORT in docs/test-results/, and that the report's Unmitigated
# table carries an approver for every accepted risk.
#
# OFFLINE, DELIBERATELY UNGATED: unlike _p3_scan_semgrep / _p3_scan_license —
# which SKIP under --offline purely to avoid a network/tool run — this scanner
# is PURE-LOCAL FILE PARSING (no external tool, no network, no Docker). A
# threat-model verdict is cheap and hermetic, so it RUNS under --offline; that
# is what lets the gate autorun (which invokes the driver with --offline) get a
# REAL threat-model result instead of an un-attested SKIP. Do NOT add an
# OFFLINE short-circuit here.
_p3_scan_threat_model() {
  local archive="$1"
  local bible="PROJECT_BIBLE.md"

  # SKIP (attestable): no bible, or a bible with no Section-4 threat table.
  if [ ! -f "$bible" ] || ! _p3_tm_has_table "$bible"; then
    P3_STATUS="SKIP"
    P3_NOTE="no threat model recorded (PROJECT_BIBLE.md Section 4 threat table absent) — add TM-NNN rows or attest"
    return
  fi

  # Collect the Bible's TM-IDs (whole tokens, sorted-unique).
  local bible_ids ids_total
  bible_ids="$(_p3_tm_ids "$bible")"
  ids_total="$(_p3_tm_count $bible_ids)"

  # Newest validation report (accepts BOTH conventional names).
  local report
  report="$(_p3_tm_report "docs/test-results")"

  if [ -z "$report" ]; then
    # Report missing while TM-IDs exist → FAIL, naming every unvalidated ID.
    _p3_tm_archive "$archive" "$ids_total" 0 "$bible_ids"
    P3_ARCHIVE="$archive"
    P3_STATUS="FAIL"
    P3_NOTE="no threat-model validation report in docs/test-results/ (expected *_threat-model-validation.md) — $ids_total TM-ID(s) unvalidated: $(echo $bible_ids)"
    return
  fi

  # Validated TM-IDs = every TM token appearing in the report's table rows.
  local report_ids missing
  report_ids="$(_p3_tm_ids "$report")"
  missing="$(_p3_tm_missing "$bible_ids" "$report_ids")"   # BL-070-TM-COMPARE: Bible-vs-report coverage diff (mutation target)

  # Unmitigated-threats table: every accepted-risk row needs a non-empty
  # Approved By (emits the TM-IDs of any row lacking an approver).
  local unapproved
  unapproved="$(_p3_tm_unapproved "$report")"

  local ids_validated
  ids_validated=$(( ids_total - $(_p3_tm_count $missing) ))

  _p3_tm_archive "$archive" "$ids_total" "$ids_validated" "$missing"
  P3_ARCHIVE="$archive"

  if [ -n "$missing" ]; then
    P3_STATUS="FAIL"
    P3_NOTE="TM-ID(s) not validated in $(basename "$report"): $missing — add a validation row per missing ID"
    return
  fi
  if [ -n "$unapproved" ]; then
    P3_STATUS="FAIL"
    P3_NOTE="unmitigated threat(s) without an approver in $(basename "$report"): $(echo $unapproved) — record a risk-acceptance sign-off (Approved By)"
    return
  fi
  P3_STATUS="PASS"
  P3_NOTE="all $ids_total TM-ID(s) validated in $(basename "$report"); unmitigated table empty-or-risk-accepted"
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
  # Trim BEFORE the non-empty check so a whitespace-only reason/signoff is
  # rejected (or falls back to the actor), not silently recorded as a
  # "valid" attestation. Verifier follow-up.
  ATTEST_REASON="$(_p3_trim "$ATTEST_REASON")"
  ATTEST_SIGNOFF="$(_p3_trim "$ATTEST_SIGNOFF")"
  if [ -z "$ATTEST_REASON" ]; then
    echo -e "${RED}[FAIL]${NC} --attest requires a non-empty --reason \"<why the scan was skipped>\" (whitespace-only is rejected)." >&2
    exit 2
  fi
  # BL-130-ATTEST-FAIL-GUARD-BEGIN
  # An attestation is for a scan that COULD NOT RUN (SKIP) — never for one
  # that ran and FAILED. The driver already refuses to HONOR such an
  # attestation (BL-113's no-launder carry), but --attest still RECORDED it
  # and printed [OK], inviting the operator to believe the FAIL was cleared
  # and leaving a misleading "attested" row against a failing scanner
  # (Dogfood-2 F-DF2-013). Refuse at write time: a FAIL must be fixed or
  # re-run, not attested.
  _bl130_lrv="$(_p3_last_real_verdict "$ATTEST_SCANNER")"
  case "$_bl130_lrv" in
    FAIL\ *)
      echo -e "${RED}[FAIL]${NC} --attest REFUSED: '$ATTEST_SCANNER' last recorded a REAL FAIL (${_bl130_lrv#FAIL }). BL-113's rule: a FAIL must be FIXED or RE-RUN, not attested — attestations cover scans that could not run, and the driver would not honor this one anyway." >&2
      exit 2
      ;;
  esac
  # BL-130-ATTEST-FAIL-GUARD-END
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

# BL-082: bind the summary to the tree it validated (see header). `dirty` is
# computed BEFORE the summary/archives are written into RESULTS_DIR, and the
# scoped check excludes RESULTS_DIR + .claude anyway, so recording it here does
# not race with this run's own writes.
P3_TREE=$(git rev-parse "HEAD^{tree}" 2>/dev/null || echo none)
P3_DIRTY=$(_p3_scoped_dirty "$RESULTS_DIR")

echo -e "${BOLD}Phase 3 validation scans${NC}"
[ -n "$OFFLINE" ] && echo -e "${BLUE}[INFO]${NC} offline mode — real-execution scanners will SKIP (no network/Docker/semgrep run)."

# Accumulators.
n_pass=0; n_skip_attested=0; n_skip_unattested=0; n_fail=0
n_carried=0
result_lines=""   # machine-readable "RESULT <name> <STATUS>" block
carried_lines=""  # machine-readable "CARRIED <name> <origin-summary>" block
table_rows=""     # human Markdown table body

for s in $P3_SCANNERS; do
  _p3_run_scanner "$s" "$TS"

  # BL-113-NO-LAUNDER — THE decision. A SKIP produced by this run must never
  # overwrite a prior REAL FAIL for the same scanner (see the header block).
  # Neutering the two marked lines below (marker intact) makes the promotion a
  # no-op — a fresh attestable SKIP survives — and MUST turn
  # tests/test-bl113-sast-honesty.sh::T-no-launder-dirty-tree RED.
  # (`carried_origin` is pre-initialised on the UNMARKED line above so the
  # mutation stays `set -u`-safe.)
  carried_origin=""
  _p3_no_launder "$s"                                     # BL-113-NO-LAUNDER
  carried_origin="$P3_CARRIED"                            # BL-113-NO-LAUNDER

  status="$P3_STATUS"; note="$P3_NOTE"; archive="$P3_ARCHIVE"
  attested_col="-"
  if [ -n "$carried_origin" ]; then
    n_carried=$((n_carried + 1))
    carried_lines="${carried_lines}CARRIED ${s} ${carried_origin}
"
  fi

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
  echo "- tree: ${P3_TREE}"
  echo "- dirty: ${P3_DIRTY}"
  echo "- Offline: $([ -n "$OFFLINE" ] && echo yes || echo no)"
  echo "- Scanners: $(echo $P3_SCANNERS | wc -w | tr -d ' ')"
  echo "- PASS: ${n_pass}  SKIP(attested): ${n_skip_attested}  SKIP(un-attested): ${n_skip_unattested}  FAIL: ${n_fail}"
  echo "- SKIP-refused (BL-113 carry-forward of a prior REAL FAIL): ${n_carried}"
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
  printf '%s' "$carried_lines"
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
if [ "$n_carried" -gt 0 ]; then
  echo ""
  echo -e "${RED}[BL-113]${NC} $n_carried scanner(s) SKIPped in this run but FAILED the last time they REALLY ran."
  echo "  A real FAIL is NOT laundered into an attestable SKIP: those are recorded FAIL."
  echo "  A FAIL is not attestable. Fix the findings, then re-run a REAL scan:"
  echo "      bash scripts/run-phase3-validation.sh          (no --offline)"
fi
exit 1
