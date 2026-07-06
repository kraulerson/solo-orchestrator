#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Phase Gate Consistency Check
# https://github.com/kraulerson/solo-orchestrator
#
# Reads .claude/phase-state.json and verifies that APPROVAL_LOG.md has
# dated entries for all completed phase gates. Designed to run in CI
# (as a warning step) or manually.
#
# Usage: bash scripts/check-phase-gate.sh
# Exit codes:
#   0 — all gates consistent, or phase state file not found (pre-framework)
#   1 — inconsistency detected (blocked). Set SOIF_PHASE_GATES=warn to downgrade.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# BL-046: uses run_with_timeout + prompt_yes_no only — source core subset.
source "$SCRIPT_DIR/lib/helpers-core.sh"

# ── Argv parser (BL-060) ─────────────────────────────────────────
# Adversarial cert re-walker-4 surfaced that scenarios invoke this
# script with `--gate phase_1_to_2` expecting the flag to scope the
# check to the named gate, but pre-fix the script had no argv parser
# at all — every arg was silently ignored, and the gate fired only
# because `current_phase=2` in phase-state.json coincidentally
# triggered the backstop. A future refactor of the backstop trigger
# would silently break `--gate` consumers.
#
# Contract:
#   --gate <name>   Force the named gate's checks to run regardless
#                   of current_phase, AND cap checks at that gate so
#                   HIGHER-phase gate blocks do not fire (strict scope).
#                   Valid names: phase_0_to_1, phase_1_to_2,
#                   phase_2_to_3, phase_3_to_4. Also accepts --gate=<v>.
#   --help, -h      Print usage and exit 0.
#
# Semantics for --gate:
#   Each gate crossing implies all prior gates have been crossed. So
#   `--gate phase_1_to_2` verifies Phase 0→1 evidence AND Phase 1→2
#   evidence, but skips Phase 2→3 and Phase 3→4 checks. Implementation:
#   override `current_phase` to the gate's TARGET phase.
#
# Exit codes:
#   2 — invalid argv (unknown gate, unknown flag, --gate given twice,
#       missing value). Diagnostics go to stderr.
show_check_phase_gate_help() {
  cat <<'HELP'
Usage: check-phase-gate.sh [--gate <name>] [--help]

Reads .claude/phase-state.json and verifies APPROVAL_LOG.md has dated
entries for all completed phase gates.

Options:
  --gate <name>   Scope the check to the named gate. Forces the gate's
                  checks to run regardless of current_phase in
                  phase-state.json; caps at that gate (skips higher
                  gates). Valid names:
                    phase_0_to_1, phase_1_to_2,
                    phase_2_to_3, phase_3_to_4
                  Also accepts --gate=<name>.
  --help, -h      Show this message.

Exit codes:
  0 — all gates consistent (or phase-state.json not found w/o --gate)
  1 — inconsistency detected (SOIF_PHASE_GATES=warn downgrades to 0),
      OR --gate was specified but no phase-state.json fixture exists
  2 — invalid argv (unknown gate, unknown flag, --gate given twice,
      missing value)
HELP
}

GATE_SCOPE=""

_cpg_parse_gate_value() {
  local val="$1"
  if [ -n "$GATE_SCOPE" ]; then
    echo -e "${RED}[FAIL]${NC} --gate specified more than once (already set to '$GATE_SCOPE', received '$val')" >&2
    exit 2
  fi
  if [ -z "$val" ]; then
    echo -e "${RED}[FAIL]${NC} --gate requires a value (one of: phase_0_to_1, phase_1_to_2, phase_2_to_3, phase_3_to_4)" >&2
    exit 2
  fi
  case "$val" in
    phase_0_to_1|phase_1_to_2|phase_2_to_3|phase_3_to_4)
      GATE_SCOPE="$val"
      ;;
    *)
      echo -e "${RED}[FAIL]${NC} Unknown gate: '$val'. Valid gates: phase_0_to_1, phase_1_to_2, phase_2_to_3, phase_3_to_4" >&2
      exit 2
      ;;
  esac
}

while [ $# -gt 0 ]; do
  case "$1" in
    --gate)
      if [ $# -lt 2 ]; then
        echo -e "${RED}[FAIL]${NC} --gate requires a value (one of: phase_0_to_1, phase_1_to_2, phase_2_to_3, phase_3_to_4)" >&2
        exit 2
      fi
      _cpg_parse_gate_value "$2"
      shift 2
      ;;
    --gate=*)
      _cpg_parse_gate_value "${1#--gate=}"
      shift
      ;;
    --help|-h)
      show_check_phase_gate_help
      exit 0
      ;;
    *)
      echo -e "${RED}[FAIL]${NC} Unknown argument: '$1'" >&2
      echo "Run 'bash scripts/check-phase-gate.sh --help' for usage." >&2
      exit 2
      ;;
  esac
done

# ── Non-interactive prompt guard ─────────────────────────────────
# code-check-gates-7 (audit v2, S3): the script's header (lines 8-9)
# advertises CI execution, and baseline §5 invariant #6 ("Phase gate
# consistency is a CI hard block by default") confirms unattended use.
# In a non-TTY context, `read -rp` reads EOF → empty string →
# `[[ ! "" =~ ^[Nn] ]]` is TRUE → side-effectful install commands
# would `eval` in CI without operator consent. Route every prompt
# through this helper so the guard lives in one place.
#
# Returns 0 (yes) or 1 (no). In non-interactive contexts (no TTY,
# CI=true, SOIF_NONINTERACTIVE=true) ALWAYS returns N (1) — the
# caller-supplied default is intentionally IGNORED as defense-in-depth,
# so a future caller that passes "Y" (as both call sites in this file
# originally did) cannot accidentally re-introduce the unattended-
# install bug surfaced by the cycle-7 adversarial verifier on PR #87.
# Prints a [WARN] explaining the skip so operators see the missing-
# tool list in CI logs.
prompt_yes_no() {
  local message="$1"
  local default_answer="${2:-N}"   # "Y" or "N" — honored ONLY when interactive

  if [ ! -t 0 ] || [ -n "${CI:-}" ] || [ -n "${SOIF_NONINTERACTIVE:-}" ]; then
    # Hard-N regardless of caller-supplied default. See
    # `tests/test-check-phase-gate-noninteractive.sh::T2` for the
    # regression guard that fixtures the install branch and asserts
    # `eval install_command` does NOT fire when this returns 1 in CI.
    echo -e "${YELLOW}[WARN]${NC} Non-interactive context: skipping prompt (\"$message\") — defaulting to 'N' (caller default '$default_answer' ignored in non-interactive context). Re-run interactively or install the listed tools manually."
    return 1
  fi

  local reply
  read -rp "$(echo -e "${BOLD}${message}${NC}: ")" reply # lint-raw-read-prompt: allow internal prompt_yes_no wrapper with TTY/CI hard-N guard above (lines 40-47) — equivalent to lib/helpers.sh::prompt_yes_no, retained here to avoid a cross-script dependency cycle
  if [ -z "$reply" ]; then
    case "$default_answer" in
      [Yy]*) return 0 ;;
      *)     return 1 ;;
    esac
  fi
  case "$reply" in
    [Nn]*) return 1 ;;
    *)     return 0 ;;
  esac
}

# Create a point-in-time snapshot of artifacts at phase gate transitions
create_gate_snapshot() {
  local from_phase="$1"
  local to_phase="$2"
  local snapshot_dir="docs/snapshots/phase-${from_phase}-to-${to_phase}_$(date +%Y-%m-%d)"

  if [ -d "$snapshot_dir" ]; then
    echo -e "  ${YELLOW}[SKIP]${NC} Snapshot already exists: $snapshot_dir"
    return 0
  fi

  mkdir -p "$snapshot_dir"

  case "${from_phase}-${to_phase}" in
    0-1)
      for f in PRODUCT_MANIFESTO.md APPROVAL_LOG.md PROJECT_INTAKE.md; do
        [ -f "$f" ] && cp "$f" "$snapshot_dir/"
      done
      # Include Phase 0 intermediate outputs if they exist
      if [ -d "docs/phase-0" ]; then
        mkdir -p "$snapshot_dir/phase-0"
        for f in docs/phase-0/*.md; do
          [ -f "$f" ] && cp "$f" "$snapshot_dir/phase-0/"
        done
      fi
      ;;
    1-2)
      for f in PROJECT_BIBLE.md PRODUCT_MANIFESTO.md APPROVAL_LOG.md; do
        [ -f "$f" ] && cp "$f" "$snapshot_dir/"
      done
      ;;
    2-3)
      for f in PROJECT_BIBLE.md FEATURES.md CHANGELOG.md BUGS.md APPROVAL_LOG.md; do
        [ -f "$f" ] && cp "$f" "$snapshot_dir/"
      done
      ;;
    3-4)
      for f in PRODUCT_MANIFESTO.md PROJECT_BIBLE.md FEATURES.md CHANGELOG.md BUGS.md \
               USER_GUIDE.md HANDOFF.md RELEASE_NOTES.md APPROVAL_LOG.md sbom.json; do
        [ -f "$f" ] && cp "$f" "$snapshot_dir/"
      done
      [ -f "docs/INCIDENT_RESPONSE.md" ] && cp "docs/INCIDENT_RESPONSE.md" "$snapshot_dir/"
      if [ -d "docs/test-results" ]; then
        ls docs/test-results/ > "$snapshot_dir/test-results-listing.txt" 2>/dev/null || true
      fi
      ;;
  esac

  echo -e "  ${GREEN}[OK]${NC} Phase gate snapshot created: $snapshot_dir"
}

PHASE_STATE=".claude/phase-state.json"
APPROVAL_LOG="APPROVAL_LOG.md"

# If no phase state file, this is either a pre-framework project or
# the file was never created. Exit cleanly — don't block CI.
#
# BL-060 edge case: if --gate was explicitly specified but the fixture
# is missing, the operator asked for a scoped check we cannot perform.
# Emit a clear error and exit 1 (not 0) — silently succeeding would
# mask the missing fixture and defeat the point of the scope flag.
if [ ! -f "$PHASE_STATE" ]; then
  if [ -n "$GATE_SCOPE" ]; then
    echo -e "${RED}[FAIL]${NC} --gate $GATE_SCOPE specified but $PHASE_STATE not found — cannot verify gate without a phase-state.json fixture." >&2
    exit 1
  fi
  echo "No $PHASE_STATE found — skipping phase gate check."
  exit 0
fi

if [ ! -f "$APPROVAL_LOG" ]; then
  echo -e "${RED}[FAIL]${NC} $APPROVAL_LOG not found but $PHASE_STATE exists."
  exit 1
fi

# Parse phase state using lightweight JSON extraction (no jq dependency)
# This handles the simple flat structure of phase-state.json
current_phase=$(grep -o '"current_phase"[[:space:]]*:[[:space:]]*"*[0-9][0-9]*"*' "$PHASE_STATE" | grep -o '[0-9][0-9]*' || echo "0")
case "$current_phase" in ''|*[!0-9]*) current_phase=0 ;; esac

# BL-060: --gate override. Force current_phase to the gate's TARGET
# phase so the gate's checks fire (elevate), and cap subsequent
# threshold comparisons at that phase so HIGHER-gate checks skip
# (strict scope). Each gate crossing implies prior gates were also
# crossed, so this preserves prior-gate coverage under scoping.
if [ -n "$GATE_SCOPE" ]; then
  case "$GATE_SCOPE" in
    phase_0_to_1) current_phase=1 ;;
    phase_1_to_2) current_phase=2 ;;
    phase_2_to_3) current_phase=3 ;;
    phase_3_to_4) current_phase=4 ;;
  esac
fi

get_gate_date() {
  local gate_key="$1"
  local value
  value=$(grep -o "\"$gate_key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$PHASE_STATE" | sed 's/.*: *"//' | sed 's/"//' || echo "")
  # Validate the extracted value is a plausible date (YYYY-MM-DD format)
  if [ -n "$value" ] && ! echo "$value" | grep -qE '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'; then
    echo ""  # Invalid date format — treat as missing
    return
  fi
  echo "$value"
}

# ── BL-071: gate-date auto-write ─────────────────────────────────
# The Builder's Guide + workflow.html describe the framework RECORDING
# the date a phase gate passed into phase-state.json::gates.<gate>.
# Historically nothing wrote that field — the gate only READ it (and
# WARNed when it was empty), so a project that crossed a gate on real
# APPROVAL_LOG.md evidence still showed "gate date not recorded". These
# helpers close that loop: on a gate whose APPROVAL_LOG.md dated
# evidence is present, we record today's date (YYYY-MM-DD) plus a
# sibling actor field, atomically and idempotently.
#
# Reuses the PR #97 / scripts/lib/bypass-audit.sh atomic-finalize
# lineage: a portable mkdir-based advisory lock (flock isn't on macOS
# bash-3.2), a temp file written ADJACENT to phase-state.json so the
# `mv` is a same-filesystem atomic rename, and an EXIT/INT/TERM trap
# contained in a subshell so it never clobbers a caller trap.
#
# GUARD (read-only invocations): this write only fires from the real
# per-gate consistency path below, gated on genuine APPROVAL_LOG.md
# evidence. There is no dry-run/preview mode; --help / -h exits at the
# argv parser above (before PHASE_STATE is even read), so no read-only
# invocation reaches this code.

# _cpg_gate_actor — best-effort "who crossed the gate" identity.
# Prefers `git config user.name`/`user.email`, falls back to
# whoami@hostname. Schema-forward: readers ignore gates.<gate>_by if
# they don't know it.
_cpg_gate_actor() {
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

# _cpg_gate_has_evidence <approval-log-header-regex>
# Returns 0 iff APPROVAL_LOG.md contains the gate's section header AND a
# dated (YYYY-MM-DD) line within the first 15 lines of that section — i.e.
# genuine recorded evidence that the gate was crossed. This is the SOLE
# predicate that gates the auto-write below: a project with no dated
# approval entry must NEVER get a date synthesized into phase-state.json.
# Extracted from the four per-gate call sites (previously duplicated
# inline) so the evidence gate is a single audit/mutation surface — the
# BL-071 verifier follow-up added negative coverage that pins exactly this
# predicate (forcing it always-true must flip a test RED). The grep pair
# is byte-for-byte the original inline logic. This line is load-bearing:
#   # BL-071-EVIDENCE-GATE
_cpg_gate_has_evidence() {
  local header="$1"
  grep -q "$header" "$APPROVAL_LOG" \
    && grep -A 15 "$header" "$APPROVAL_LOG" \
       | grep -qE "[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])"
}

# _cpg_record_gate_date <gate_key> <label> <current_date>
# Records today's date into phase-state.json::gates.<gate_key> (and
# gates.<gate_key>_by) when <current_date> is empty. If <current_date>
# already holds a valid date, this is a re-pass: log [INFO] and DO NOT
# overwrite (preserve the first-pass timestamp). On gate FAIL the
# caller never reaches this helper for an unpopulated gate, and a
# populated gate is never cleared — so a prior PASS's record is real
# history that a later FAIL cannot erase.
# Returns:
#   0 — wrote today's date (fresh record)
#   1 — idempotent skip (valid date already present; nothing written)
#   2 — could not write (jq unavailable, lock timeout, or jq error);
#       caller treats this as an unresolved gate-date issue.
_cpg_record_gate_date() {
  local gate_key="$1" label="$2" current="$3"

  # Idempotency: a valid first-pass date is preserved, never clobbered.
  # Uses the already-regex-validated captured value (get_gate_date), so
  # this branch needs no jq — a healthy, already-dated gate never
  # false-fails just because jq is absent.
  if [ -n "$current" ]; then
    echo -e "${BLUE}[INFO]${NC} $label: gate date already recorded ($current) — preserving first-pass timestamp (idempotent)."
    return 1
  fi

  # Fresh record requires jq to edit the JSON structurally.
  if ! command -v jq >/dev/null 2>&1; then
    echo -e "${YELLOW}[WARN]${NC} $label: APPROVAL_LOG.md has a dated entry but the gate date could not be auto-recorded (jq not available). Add the date to $PHASE_STATE manually."
    return 2
  fi

  # WARN-MODE NOTE (deliberate): callers reach this record path whenever the
  # gate's APPROVAL_LOG.md evidence is present and the JSON date is empty —
  # INCLUDING under SOIF_PHASE_GATES=warn. That is intentional: an
  # evidence-backed gate date is a fact, so recording it (which reformats
  # phase-state.json via jq) keeps the feature working for warn-mode
  # projects. `warn` only downgrades the final BLOCKING exit; it is not a
  # read-only/preview mode and must not suppress this write. Operators who
  # want a pure read-only inspection should not run the gate at a phase past
  # a crossed-but-unrecorded gate — there is no state to synthesize once the
  # date is present (idempotent thereafter).
  local today actor file lock_dir attempts rc
  today=$(date +%Y-%m-%d)
  actor=$(_cpg_gate_actor)
  file="$PHASE_STATE"
  lock_dir="$file.lockdir"

  # Portable advisory lock via atomic mkdir (bypass-audit.sh lineage).
  # Fail-safe stale-lock behavior: a SIGKILL between this mkdir and the
  # subshell's EXIT trap can orphan "$lock_dir". The next run then spins
  # this loop for ~10s (100 × 0.1s) and returns 2 — degrading to the
  # historical "gate date not recorded" WARN (issues++), never a crash and
  # never a corrupted state file. Recovery is `rmdir "$lock_dir"` (or it is
  # swept with the project's temp state). This is an accepted trade for a
  # dependency-free, macOS-bash-3.2-portable lock.
  attempts=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 100 ]; then
      echo -e "${YELLOW}[WARN]${NC} $label: gate-date write lock timeout (>10s; possible stale $lock_dir from a killed run — remove it and retry) — record the date in $PHASE_STATE manually." >&2
      return 2
    fi
    sleep 0.1
  done

  rc=0
  (
    tmp=$(mktemp "${file}.XXXXXX") || exit 1
    trap 'rm -f "$tmp"; rmdir "$lock_dir" 2>/dev/null' EXIT INT TERM
    if jq --arg k "$gate_key" --arg d "$today" --arg by "$actor" \
         '.gates = ((.gates // {}) + {($k): $d, ($k + "_by"): $by})' \
         "$file" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$file" || exit 1   # BL-071-WRITE: atomic gate-date finalize (mutation target)
      trap - EXIT INT TERM
      exit 0
    else
      rm -f "$tmp"
      trap - EXIT INT TERM
      exit 1
    fi
  ) || rc=1
  # `|| true`: on a mv-failure path the subshell's EXIT trap already
  # removed the lock dir, so this rmdir would fail — never let that trip
  # `set -e` and abort the whole gate run.
  rmdir "$lock_dir" 2>/dev/null || true

  if [ "$rc" -eq 0 ]; then
    echo -e "${GREEN}  [OK]${NC} $label: gate date recorded ($today, by $actor) from APPROVAL_LOG.md evidence."
    return 0
  fi
  echo -e "${YELLOW}[WARN]${NC} $label: gate-date auto-write failed (jq error) — record the date in $PHASE_STATE manually."
  return 2
}

# ── BL-073: reviewer-attestation recorder ───────────────────────
# Records the SOLO_REVIEWERS_ATTESTED escape-hatch decision into
# .claude/process-state.json::phase3.attestations.reviewers (BL-032
# lineage — a block that is attested, not silenced). Reuses the same
# atomic-finalize pattern as _cpg_record_gate_date: a portable mkdir
# advisory lock, a temp file written ADJACENT to process-state.json so
# `mv` is a same-filesystem atomic rename, and an EXIT/INT/TERM trap
# contained in a subshell.
#
# GUARD (read-only invocations): this writer fires ONLY from the review
# block below when the operator has explicitly set SOLO_REVIEWERS_ATTESTED=1
# AND a mandatory reviewer is actually missing — never on a plain read.
# It is idempotent: if the recorded (reason,missing) already match, it
# returns without rewriting, so a re-run does not churn the date.
#
# _cpg_record_reviewer_attestation <reason> <missing_csv>
#   0 — recorded (or idempotent no-op: already recorded with same values)
#   2 — could not write (jq unavailable, lock timeout, or jq error)
_cpg_record_reviewer_attestation() {
  local reason="$1" missing="$2"
  local file=".claude/process-state.json"

  if ! command -v jq >/dev/null 2>&1; then
    return 2
  fi

  # Idempotency: skip the write when the existing record already matches.
  if [ -f "$file" ]; then
    local cur_reason cur_missing
    cur_reason=$(jq -r '.phase3.attestations.reviewers.reason // ""' "$file" 2>/dev/null || echo "")
    cur_missing=$(jq -r '.phase3.attestations.reviewers.missing // ""' "$file" 2>/dev/null || echo "")
    if [ "$cur_reason" = "$reason" ] && [ "$cur_missing" = "$missing" ]; then
      return 0
    fi
  else
    echo '{}' > "$file" 2>/dev/null || return 2
  fi

  local today actor lock_dir attempts rc
  today=$(date +%Y-%m-%d)
  actor=$(_cpg_gate_actor)
  lock_dir="$file.lockdir"

  attempts=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 100 ]; then
      return 2
    fi
    sleep 0.1
  done

  rc=0
  (
    tmp=$(mktemp "${file}.XXXXXX") || exit 1
    trap 'rm -f "$tmp"; rmdir "$lock_dir" 2>/dev/null' EXIT INT TERM
    if jq --arg reason "$reason" --arg missing "$missing" \
          --arg date "$today" --arg by "$actor" \
          '.phase3 = ((.phase3 // {}) | .attestations = ((.attestations // {}) + {reviewers: {reason: $reason, missing: $missing, date: $date, by: $by}}))' \
          "$file" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$file" || exit 1   # BL-073-ATTEST-WRITE: atomic attestation finalize
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

gate_0_to_1=$(get_gate_date "phase_0_to_1")
gate_1_to_2=$(get_gate_date "phase_1_to_2")
gate_2_to_3=$(get_gate_date "phase_2_to_3")
gate_3_to_4=$(get_gate_date "phase_3_to_4")

# Extract deployment type and track for conditional checks
deployment=$(grep -o '"deployment"[[:space:]]*:[[:space:]]*"[^"]*"' "$PHASE_STATE" 2>/dev/null | sed 's/.*: *"//' | sed 's/"//' || echo "personal")
track=$(grep -o '"track"[[:space:]]*:[[:space:]]*"[^"]*"' "$PHASE_STATE" 2>/dev/null | sed 's/.*: *"//' | sed 's/"//' || echo "light")
# BL-084 (verifier follow-up): poc_mode is the SECOND half of the tier key
# (with deployment) that decides push-escape bypass-eligibility below. It is
# NOT keyed on `track` — a sponsored/production project can carry track=light.
# `"poc_mode": null` (production / personal non-POC) is unquoted so this
# quoted-value grep yields "" (correctly ≠ sponsored_poc).
poc_mode=$(grep -o '"poc_mode"[[:space:]]*:[[:space:]]*"[^"]*"' "$PHASE_STATE" 2>/dev/null | sed 's/.*: *"//' | sed 's/"//' || echo "")

issues=0

echo -e "${BOLD}Phase Gate Consistency Check${NC}"
echo "Current phase: $current_phase"
echo ""

# --- Manifesto Content Validation (P0-003) ---
# Verify the Manifesto has substantive content, not just template defaults
validate_manifesto_content() {
  local file="PRODUCT_MANIFESTO.md"
  [ -f "$file" ] || return 0  # Existence checked separately

  local missing_sections=""
  local placeholder_sections=""

  # Check all 8 required sections
  for section_num in 1 2 3 4 5 6 7 8; do
    if ! grep -qE "^## ${section_num}\." "$file"; then
      missing_sections="${missing_sections} ${section_num}"
    else
      # Check if section has content beyond template placeholders
      local section_content
      section_content=$(sed -n "/^## ${section_num}\./,/^## [0-9]/p" "$file" | grep -v "^##" | grep -v "^---" | grep -v "^$" | grep -v "^<!--" | grep -v -e '-->$' | grep -v "^\[" | grep -v "^|.*|.*|$" | head -5)
      if [ -z "$section_content" ]; then
        placeholder_sections="${placeholder_sections} ${section_num}"
      fi
    fi
  done

  if [ -n "$missing_sections" ]; then
    echo -e "${RED}[FAIL]${NC} PRODUCT_MANIFESTO.md: missing required sections:${missing_sections}"
    issues=$((issues + 1))
  fi

  if [ -n "$placeholder_sections" ]; then
    echo -e "${YELLOW}[WARN]${NC} PRODUCT_MANIFESTO.md: sections with only placeholder content:${placeholder_sections}"
    issues=$((issues + 1))
  fi

  # Check for unresolved Open Questions (P0-012)
  if grep -qi "Status:[[:space:]]*Open" "$file" 2>/dev/null; then
    local open_count
    open_count=$(grep -ci "Status:[[:space:]]*Open" "$file" 2>/dev/null || echo "0")
    case "$open_count" in ''|*[!0-9]*) open_count=0 ;; esac
    echo -e "${RED}[FAIL]${NC} PRODUCT_MANIFESTO.md: $open_count unresolved Open Question(s) — resolve before Phase 1"
    issues=$((issues + 1))
  fi
}

# --- Approval Entry Field Validation (P0-004) ---
# Verify approval entries have populated fields, not just template defaults
validate_approval_fields() {
  local gate_name="$1"  # e.g., "Phase 0.*Phase 1"
  local gate_label="$2" # e.g., "Phase 0→1"

  # Find the gate section and check for populated approver/date fields
  local section
  section=$(grep -A 20 "$gate_name" "$APPROVAL_LOG" 2>/dev/null || echo "")
  [ -z "$section" ] && return 0  # No section = checked separately

  # Check for template defaults that indicate unfilled fields
  if echo "$section" | grep -qiE "(Approver|Reviewer).*\[.*\]|YYYY-MM-DD"; then
    echo -e "${YELLOW}[WARN]${NC} $gate_label: APPROVAL_LOG.md entry contains placeholder values — fill in approver name and date"
    issues=$((issues + 1))
  fi

  # For organizational deployments: detect self-approval (P0-005).
  # code-check-gates-5 (audit v2, S3): the previous implementation
  # used substring case-insensitive `grep -qi "$git_user"` on the
  # approver column, producing false [FAIL]s for any approver whose
  # name CONTAINED the operator's git user — e.g. operator "Karl"
  # incorrectly flagged approver "Karla" / "Karlyn" / "karl-cobb".
  # It also compared against the ambient `git config user.name`
  # rather than the actual commit author of the APPROVAL_LOG.md
  # change, which is what baseline §5 invariant #9 requires
  # ("The git author on the commit adding the approval entry must be
  # the approver, not the Orchestrator").
  #
  # Fix:
  #   1. Compare names token-exact (case-insensitive). Normalize by
  #      lowercasing and trimming surrounding whitespace; require
  #      full-string equality, not substring containment.
  #   2. The authoritative comparison source is the commit author of
  #      the most recent APPROVAL_LOG.md change. The ambient git
  #      user becomes a softer WARN signal when it matches the
  #      approver but the commit author does NOT — useful for
  #      catching operators who rewrote author metadata.
  if [ "$deployment" = "organizational" ]; then
    local approver_name
    approver_name=$(echo "$section" | awk -F'|' '/[Aa]pprover/ && !/Role/ { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); gsub(/\*/, "", $3); print $3; exit }' 2>/dev/null || echo "")
    if [ -n "$approver_name" ] && [ "$approver_name" != "[Name]" ] && [ "$approver_name" != "" ]; then
      local approver_norm git_user git_user_norm commit_author commit_author_norm approver_line
      approver_norm=$(printf '%s' "$approver_name" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      git_user=$(git config user.name 2>/dev/null || echo "")
      git_user_norm=$(printf '%s' "$git_user" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

      # code-check-gates-7-followup (cycle-7 PR-#87 verifier major #4):
      # the pre-fix lookup `git log -n 1 --format=%an -- APPROVAL_LOG.md`
      # returned whoever most recently TOUCHED the file — not who added
      # the specific gate's Approver row. Attack: Alice commits her own
      # approval row at gate A (real self-approval — should FAIL); Bob
      # later commits a typo fix to gate B; `git log -1` returns Bob;
      # Alice's self-approval silently passes.
      #
      # Fix: resolve the line number of the active gate section's
      # Approver row, then `git blame -L<N>,<N>` to extract the author
      # of THAT line's most recent change. Compare against approver.
      #
      # The awk walker scans for the gate header, then within the
      # section walks until the next ## header or `---` rule, locating
      # the first Approver row that isn't a Role row. It emits one of:
      #
      #   <integer>   the approver row's 1-based line number
      #   NO_APPROVER gate header found but no Approver row inside
      #   NO_SECTION  no `## ` header matching the gate at all
      #
      # PR #116 follow-up (post-merge verifier MINOR #2): the previous
      # implementation silently fell back to the pre-fix file-level
      # `git log -1` lookup when the walker found no line — reinstating
      # the exact self-approval evasion this PR was meant to close, for
      # any malformed/non-canonical APPROVAL_LOG.md. The fallback is
      # removed: missing section OR missing approver row → operator-
      # visible WARN + early return, never a silent file-level lookup.
      #
      # Headers and gate_name are both capitalized (canonical template
      # uses "## Phase Gate: Phase 0 → Phase 1"), so case-sensitive
      # matching is sufficient and matches the prior `grep -A 20` shape
      # (also case-sensitive). `IGNORECASE = 1` is a gawk extension
      # silently ignored on BSD/macOS awk — removed as dead code.
      approver_line=$(awk -v gate="$gate_name" '
        BEGIN { found_section = 0; found_approver = 0; approver_nr = 0 }
        $0 ~ gate && /^## / { in_section = 1; found_section = 1; next }
        in_section && /^## / { exit }
        in_section && /^---[[:space:]]*$/ { exit }
        in_section && /[Aa]pprover/ && !/Role/ {
          if (!found_approver) { approver_nr = NR; found_approver = 1 }
          exit
        }
        END {
          if (found_approver) print approver_nr
          else if (found_section) print "NO_APPROVER"
          else print "NO_SECTION"
        }
      ' "$APPROVAL_LOG" 2>/dev/null || echo "")

      case "$approver_line" in
        NO_SECTION)
          # Canonical `## ` header not present — silent fallback to
          # `git log -1` would reintroduce the self-approval evasion.
          # Surface as WARN so the malformed file becomes audit signal.
          echo -e "${YELLOW}[WARN]${NC} $gate_label: APPROVAL_LOG.md has no '## ' header matching gate — cannot verify self-approval (malformed file?). Refusing silent file-level fallback; restore canonical '## Phase Gate: …' header."
          issues=$((issues + 1))
          return 0
          ;;
        NO_APPROVER)
          # Gate section found but contains no Approver row — same
          # silent-pass risk if we fell back to file-level lookup.
          echo -e "${YELLOW}[WARN]${NC} $gate_label: APPROVAL_LOG.md gate section found but no Approver row — cannot verify self-approval. Add an 'Approver' row to the gate section."
          issues=$((issues + 1))
          return 0
          ;;
        ''|*[!0-9]*)
          # awk script failed entirely (unexpected — defensive).
          echo -e "${YELLOW}[WARN]${NC} $gate_label: APPROVAL_LOG.md gate-section walker produced no result — cannot verify self-approval."
          issues=$((issues + 1))
          return 0
          ;;
      esac

      # approver_line is a numeric line number — run per-line blame.
      # `git blame --line-porcelain` prints an `author <name>` line per
      # entry. When the line differs from HEAD (uncommitted working-
      # tree modification) blame returns "Not Committed Yet". Both
      # empty-author and "Not Committed Yet" mean the invariant cannot
      # be verified — collapse to the WARN branch below.
      commit_author=$(git blame --line-porcelain \
                        -L "${approver_line},${approver_line}" \
                        -- "$APPROVAL_LOG" 2>/dev/null \
                        | awk '/^author / { sub(/^author /, ""); print; exit }' \
                        || echo "")
      if [ "$commit_author" = "Not Committed Yet" ] || [ "$commit_author" = "External file (--contents)" ]; then
        commit_author=""
      fi
      commit_author_norm=$(printf '%s' "$commit_author" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

      if [ -n "$commit_author_norm" ] && [ "$commit_author_norm" = "$approver_norm" ]; then
        echo -e "${RED}[FAIL]${NC} $gate_label: Approver '$approver_name' matches APPROVAL_LOG.md commit author '$commit_author' — self-approval detected for organizational deployment"
        echo "  Governance requires a different individual to approve phase gates for organizational projects."
        echo "  Have the approver commit the APPROVAL_LOG.md entry themselves, or use --force with documented justification."
        issues=$((issues + 1))
      elif [ -n "$git_user_norm" ] && [ "$git_user_norm" = "$approver_norm" ] \
           && [ -n "$commit_author_norm" ] && [ "$commit_author_norm" != "$approver_norm" ]; then
        echo -e "${YELLOW}[WARN]${NC} $gate_label: ambient git user '$git_user' matches approver '$approver_name' but APPROVAL_LOG.md commit author is '$commit_author' — verify the commit author wasn't rewritten"
        issues=$((issues + 1))
      elif [ -z "$commit_author_norm" ] && [ -n "$approver_norm" ]; then
        # code-check-gates-7-followup: cannot verify the per-line blame
        # author because (a) the Approver row was added in the working
        # tree only (uncommitted) — `git blame` returns "Not Committed
        # Yet", normalized to empty above; or (b) git is unavailable.
        # The missing-section / no-approver-row cases never reach this
        # branch — the case-statement above returns early with a louder
        # WARN. Surface as WARN so the silent-pass case never recurs
        # (baseline §5 invariant #9 audit signal).
        echo -e "${YELLOW}[WARN]${NC} $gate_label: cannot verify commit author for approver '$approver_name' — APPROVAL_LOG.md row not yet committed (or per-line blame returned no author). Commit the approval entry to enable self-approval verification."
        issues=$((issues + 1))
      fi
    fi
  fi
}

# --- Section-scoped Date validator (tier-crosscheck-13) ---
# Returns 0 if the named subsection (e.g. "Application Owner Approval")
# has a Date row populated with an ISO date in its first 15 lines.
# Returns 1 if the subsection is absent, OR its Date row is missing,
# OR the Date row's value column is blank/template-default.
#
# tier-crosscheck-13 (audit v2, S3): the Phase 3→4 dual-approval gate
# previously used bare presence greps (`grep -qi "Application Owner"
# && grep -qi "IT Security"`) against the whole APPROVAL_LOG. The org
# template generated by upgrade-project.sh:1142-1170 contains both
# strings VERBATIM as subsection headers + Role rows before any
# approval is recorded, so the gate green-lit empty templates.
# Baseline §3.4 lines 368-371 requires recorded approvals with dates,
# not just header presence. This helper enforces that.
validate_approval_section_dated() {
  local section_header="$1"  # e.g., "Application Owner Approval"
  local section
  section=$(grep -A 15 "$section_header" "$APPROVAL_LOG" 2>/dev/null || echo "")
  [ -z "$section" ] && return 1
  # Find the Date row; extract the value column (3rd pipe-field for
  # | Field | Value | tables). Strip whitespace and markdown bold.
  local date_val
  date_val=$(echo "$section" \
    | awk -F'|' '/[Dd]ate/ { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); gsub(/\*/, "", $3); print $3; exit }' \
    2>/dev/null || echo "")
  [ -z "$date_val" ] && return 1
  # Reject template-default placeholders and require ISO date.
  case "$date_val" in
    "[Date]"|"YYYY-MM-DD") return 1 ;;
  esac
  if echo "$date_val" | grep -qE "^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$"; then
    return 0
  fi
  return 1
}

# --- Pre-Phase 0 Pre-Conditions Check (P0-010) ---
# For organizational deployments, verify pre-conditions are recorded.
#
# tier-crosscheck-7 (audit v2, S3): the previous implementation only
# COUNTED dated rows in the Pre-Phase 0 section. Any 6 dated lines
# satisfied the gate, including unrelated rows, duplicates, or
# template defaults — none of which constitute evidence that the 6
# NAMED pre-conditions (AI deployment path, Insurance, Liability,
# Sponsor, Backup maintainer, ITSM) were individually approved.
# Baseline §2.1 lines 61-63 + invariant #17 ("Insurance confirmation
# is a hard pre-Phase-0 gate") require per-named-row enforcement.
# Fix: in addition to the count, verify each of the 6 named rows has
# a date present in its row. Surface any missing names in the
# diagnostic so the operator knows which pre-condition lacks evidence.
if [ "$deployment" = "organizational" ] && [ "$current_phase" -ge 0 ]; then
  poc_mode_val=""
  poc_mode_val=$(grep -o '"poc_mode"[[:space:]]*:[[:space:]]*"[^"]*"' "$PHASE_STATE" 2>/dev/null | sed 's/.*: *"//' | sed 's/"//' || echo "")

  if [ -z "$poc_mode_val" ] || [ "$poc_mode_val" = "null" ]; then
    # Full organizational — all 6 pre-conditions required
    if grep -q "Pre-Phase 0" "$APPROVAL_LOG" 2>/dev/null; then
      local_precond_count=$(grep -A 30 "Pre-Phase 0" "$APPROVAL_LOG" 2>/dev/null | grep -cE "[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])" || echo "0")
      case "$local_precond_count" in ''|*[!0-9]*) local_precond_count=0 ;; esac

      # tier-crosscheck-7: per-named-row check. For each of the 6
      # named pre-conditions, grep the Pre-Phase 0 section for a row
      # that mentions the name AND contains an ISO date. Section is
      # the 30 lines after the "Pre-Phase 0" header (same window as
      # the count above).
      pre_phase0_section=$(grep -A 30 "Pre-Phase 0" "$APPROVAL_LOG" 2>/dev/null || echo "")
      missing_named=""
      # row_pattern => display name pairs. The pattern is a case-
      # insensitive ERE; the display name is what we tell the operator.
      check_named_row() {
        local pattern="$1"
        local display="$2"
        # A row "matches" if any line in the section contains the
        # pattern AND an ISO date.
        if ! echo "$pre_phase0_section" \
             | grep -iE "$pattern" \
             | grep -qE "[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])"; then
          if [ -z "$missing_named" ]; then
            missing_named="$display"
          else
            missing_named="$missing_named, $display"
          fi
        fi
      }
      check_named_row "AI deployment"        "AI deployment path"
      check_named_row "[Ii]nsurance"         "Insurance"
      check_named_row "[Ll]iability"         "Liability"
      check_named_row "[Ss]ponsor"           "Sponsor"
      check_named_row "[Bb]ackup maintainer" "Backup maintainer"
      check_named_row "ITSM"                 "ITSM"

      if [ -n "$missing_named" ]; then
        echo -e "${YELLOW}[WARN]${NC} Pre-Phase 0: Organizational deployment — named pre-condition(s) without a dated approval row: $missing_named"
        issues=$((issues + 1))
      elif [ "$local_precond_count" -lt 6 ]; then
        echo -e "${YELLOW}[WARN]${NC} Pre-Phase 0: Organizational deployment — only $local_precond_count pre-condition date(s) recorded (6 required)"
        issues=$((issues + 1))
      else
        echo -e "${GREEN}  [OK]${NC} Pre-Phase 0 pre-conditions recorded ($local_precond_count entries)"
      fi
    else
      echo -e "${YELLOW}[WARN]${NC} Pre-Phase 0: Organizational deployment — no pre-conditions section found in APPROVAL_LOG.md"
      issues=$((issues + 1))
    fi
  fi
fi

# Check: if current_phase >= 1, gate 0→1 should have a date.
# BL-071: evidence-first. When APPROVAL_LOG.md carries the dated entry
# (the real record the gate passed) we RECORD today's date into
# phase-state.json::gates.phase_0_to_1 (idempotent; never overwrites an
# existing date). The date-set-but-no-evidence and no-date-no-evidence
# branches preserve the historical WARN behavior.
if [ "$current_phase" -ge 1 ]; then
  if _cpg_gate_has_evidence "Phase 0.*Phase 1"; then
    cpg_rc=0
    _cpg_record_gate_date "phase_0_to_1" "Phase 0→1" "$gate_0_to_1" || cpg_rc=$?
    [ "$cpg_rc" -eq 2 ] && issues=$((issues + 1))
  elif [ -n "$gate_0_to_1" ]; then
    echo -e "${YELLOW}[WARN]${NC} Phase 0→1: gate dated $gate_0_to_1, but APPROVAL_LOG.md has no dated entry"
    issues=$((issues + 1))
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 0→1: current_phase is $current_phase but gate date not recorded in phase-state.json"
    issues=$((issues + 1))
  fi
fi

# Approval field validation: Phase 0→1 (P0-004, P0-005)
if [ "$current_phase" -ge 1 ]; then
  validate_approval_fields "Phase 0.*Phase 1" "Phase 0→1"
fi

# Artifact existence + content check: Phase 0→1
if [ "$current_phase" -ge 1 ]; then
  if [ -f "PRODUCT_MANIFESTO.md" ]; then
    echo -e "${GREEN}  [OK]${NC} PRODUCT_MANIFESTO.md exists"
    validate_manifesto_content
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 0→1: PRODUCT_MANIFESTO.md not found"
    issues=$((issues + 1))
  fi
  # Check for Phase 0 intermediate outputs (P0-002)
  if [ -d "docs/phase-0" ]; then
    p0_files=0
    [ -f "docs/phase-0/frd.md" ] && p0_files=$((p0_files + 1))
    [ -f "docs/phase-0/user-journey.md" ] && p0_files=$((p0_files + 1))
    [ -f "docs/phase-0/data-contract.md" ] && p0_files=$((p0_files + 1))
    if [ $p0_files -eq 3 ]; then
      echo -e "${GREEN}  [OK]${NC} Phase 0 intermediates: frd.md, user-journey.md, data-contract.md"
    elif [ $p0_files -gt 0 ]; then
      echo -e "${YELLOW}[WARN]${NC} Phase 0 intermediates: $p0_files/3 saved (check docs/phase-0/)"
    fi
  fi
fi

# Check: if current_phase >= 2, gate 1→2 should have a date (BL-071: see
# the Phase 0→1 block for the evidence-first auto-write rationale).
if [ "$current_phase" -ge 2 ]; then
  if _cpg_gate_has_evidence "Phase 1.*Phase 2"; then
    cpg_rc=0
    _cpg_record_gate_date "phase_1_to_2" "Phase 1→2" "$gate_1_to_2" || cpg_rc=$?
    [ "$cpg_rc" -eq 2 ] && issues=$((issues + 1))
  elif [ -n "$gate_1_to_2" ]; then
    echo -e "${YELLOW}[WARN]${NC} Phase 1→2: gate dated $gate_1_to_2, but APPROVAL_LOG.md has no dated entry"
    issues=$((issues + 1))
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 1→2: current_phase is $current_phase but gate date not recorded in phase-state.json"
    issues=$((issues + 1))
  fi
fi

# --- Phase 1→2 BACKSTOP: repo protection verification (spec 2026-04-21) ---
# Runs whenever current_phase is at or past 2 — catches drift where protection
# was loosened after init, or projects that predate the host-aware gate.
if [ "$current_phase" -ge 2 ]; then
  SCRIPT_DIR_CPG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  host_dispatcher="$SCRIPT_DIR_CPG/lib/host.sh"
  if [ -f "$host_dispatcher" ] && [ -f ".claude/manifest.json" ]; then
    # BL-002 follow-up (code-check-gates-1): honor a recorded
    # `github_free_tier` branch-protection attestation from
    # .claude/process-state.json BEFORE invoking host_verify_protection.
    # On tier-limited GitHub free repos the protection API returns 403
    # and the attestation IS the gate — see canonical implementation at
    # scripts/check-gate.sh::cmd_preflight (lines ~52-64). Without this
    # check, legitimately attested projects saw a false-fail backstop
    # while `--preflight` PASSED at the same moment.
    backstop_attest_reason=""
    if [ -f .claude/process-state.json ]; then
      backstop_attest_reason=$(jq -r '.phase2_init.attestations.branch_protection.reason // ""' \
                                 .claude/process-state.json 2>/dev/null || echo "")
    fi
    if [ "$backstop_attest_reason" = "github_free_tier" ]; then
      echo -e "${GREEN}  [OK]${NC} Phase 1→2 backstop: branch protection attested (reason: github_free_tier — upgrade to GitHub Pro to enable API enforcement)"
    elif [ "$backstop_attest_reason" = "gitlab_free_tier_approvals" ]; then
      # BL-032 close: honor the GitLab Free-tier approvals attestation
      # (proactive --approvals-attested / SOLO_APPROVALS_ATTESTED=1 flow).
      # On gitlab.com Free the projects/:id/approvals PUT is Premium-only,
      # so the attestation IS the gate — there is nothing to verify.
      echo -e "${GREEN}  [OK]${NC} Phase 1→2 backstop: branch protection attested (reason: gitlab_free_tier_approvals — set required-approvals manually via GitLab Settings > Merge requests, or upgrade to Premium)"
    else
      # shellcheck disable=SC1090
      source "$host_dispatcher"
      mode=$(jq -r '.mode // "personal"' .claude/manifest.json 2>/dev/null || echo "personal")
      if host_load_driver 2>/dev/null; then
        if host_verify_protection "main" "$mode" 2>/dev/null; then
          echo -e "${GREEN}  [OK]${NC} Phase 1→2 backstop: repo protection verified for $mode mode"
        else
          echo -e "${RED}[FAIL]${NC} Phase 1→2 backstop: protection verification failed"
          echo "        Remediate: scripts/check-gate.sh --repair"
          echo "        Preflight: scripts/check-gate.sh --preflight"
          issues=$((issues + 1))
        fi
      else
        echo -e "${YELLOW}[WARN]${NC} Phase 1→2 backstop: could not load host driver (manifest host field may be missing; run scripts/check-gate.sh --backfill-host)"
        issues=$((issues + 1))
      fi
    fi
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 1→2 backstop: host dispatcher or manifest.json missing — skipping (project predates host-aware gate)"
  fi
fi

# --- Phase 1→2 BACKSTOP: remote PUSH verification (BL-084) ---
# The protection backstop above proves branch PROTECTION; it does NOT prove
# the code was actually uploaded. This backstop verifies the remote really
# has the branch — the check that makes the verify-install "bring-your-own
# CI" warning TRUE rather than a mask for un-pushed code.
#
# SCOPE: this runs ONLY for host=="other" (the bring-your-own-host path).
# First-class hosts (github/gitlab/bitbucket) HARD-FAIL init on a push
# failure (create_and_protect_remote returns 1 → record_init_failure), so a
# first-class project that reached Phase 2 provably pushed at init; the
# protection backstop above (API verify) already re-confirms reachability.
# The 'other' path is the ONLY one where init can legitimately COMPLETE
# without a verified push — via the light-tier acknowledged escapes below —
# so it is exactly where a raw push-existence check adds real value.
#
# HERMETIC/testable: verification is a plain `git ls-remote --heads origin`
# — it works against a LOCAL bare repo (tests point origin there) and NEVER
# invokes gh/glab (BL-076: no real remote creation).
#
# TIER-aware, keyed on the ACTUAL project tier (deployment + poc_mode), NOT
# `track` — a POC-Sponsored / Production project can carry track=light
# non-interactively, so trusting `track` would let it bypass with no code
# pushed. This keying is IDENTICAL to init.sh::_bl084_tier_bypassable so the
# two enforcement points cannot disagree:
#   • NON-bypassable (POC-Sponsored / Production — deployment=organizational
#     OR poc_mode=sponsored_poc): a VERIFIED remote is MANDATORY — FAIL if the
#     remote does not have the code. No ack bypasses the push itself.
#   • BYPASSABLE (Personal / POC-Personal — deployment=personal AND
#     poc_mode≠sponsored_poc): require the verified remote UNLESS
#     local_only_acknowledged is on record (then PASS — operator opted out).
#     A push_deferred_acknowledged with no verified push still FAILs — the
#     deferral does NOT let them advance ("the gate WILL block you").
# The `# BL-084-PUSH-VERIFY` marker is a mutation-proof target (removing the
# verification flips the "deferred-but-not-pushed → FAIL" test RED); the
# `# BL-084-TIER-KEY` marker is the other (reverting eligibility to `track`
# flips the sponsored/production `--track light` bypass tests RED).
if [ "$current_phase" -ge 2 ]; then
  bl084_host=""
  if [ -f .claude/manifest.json ] && command -v jq >/dev/null 2>&1; then
    bl084_host=$(jq -r '.host // ""' .claude/manifest.json 2>/dev/null || echo "")
  fi
  if [ "$bl084_host" = "other" ]; then
    bl084_local_only_ack=false
    bl084_push_deferred_ack=false
    if [ -f .claude/process-state.json ] && command -v jq >/dev/null 2>&1; then
      [ "$(jq -r '.phase2_init.remote.local_only_acknowledged.risk_accepted // false' .claude/process-state.json 2>/dev/null)" = "true" ] && bl084_local_only_ack=true
      [ "$(jq -r '.phase2_init.remote.push_deferred_acknowledged.risk_accepted // false' .claude/process-state.json 2>/dev/null)" = "true" ] && bl084_push_deferred_ack=true
    fi

    # BL-084-TIER-KEY: bypass-eligibility = the ACTUAL tier, never `track`.
    bl084_bypassable=true
    if [ "$deployment" = "organizational" ] || [ "$poc_mode" = "sponsored_poc" ]; then
      bl084_bypassable=false
    fi

    bl084_remote_verified=false  # BL-084-PUSH-VERIFY
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git remote get-url origin >/dev/null 2>&1; then
      for _bl084_br in main master; do
        if git ls-remote --heads origin "$_bl084_br" 2>/dev/null | grep -q .; then
          bl084_remote_verified=true
          break
        fi
      done
    fi

    if [ "$bl084_remote_verified" = true ]; then
      echo -e "${GREEN}  [OK]${NC} Phase 1→2 push gate: remote has the branch — the code is pushed (BL-084)."
    elif [ "$bl084_bypassable" = true ] && [ "$bl084_local_only_ack" = true ]; then
      echo -e "${GREEN}  [OK]${NC} Phase 1→2 push gate: local-only acknowledged — operator opted out of a remote, on record (BL-084)."
    elif [ "$bl084_bypassable" != true ]; then
      echo -e "${RED}[FAIL]${NC} Phase 1→2 push gate: POC-Sponsored / Production (deployment=$deployment, poc_mode=${poc_mode:-none}) requires a VERIFIED remote (the code must be pushed) — MANDATORY, non-bypassable (BL-084)."
      echo "        Push the initial commit, then re-check: scripts/check-gate.sh --preflight"
      issues=$((issues + 1))
    elif [ "$bl084_push_deferred_ack" = true ]; then
      echo -e "${RED}[FAIL]${NC} Phase 1→2 push gate: push was DEFERRED (--defer-remote-push) but the remote still does NOT have the branch (BL-084)."
      echo "        The deferral does not let you advance — push before Phase 1→2:"
      echo "          git push -u origin main   # then: scripts/check-gate.sh --preflight"
      issues=$((issues + 1))
    else
      echo -e "${RED}[FAIL]${NC} Phase 1→2 push gate: no verified remote and no local-only acknowledgment on record (BL-084)."
      echo "        Push the initial commit, or (Personal / POC-Personal only) re-run init with --accept-local-only-risk."
      issues=$((issues + 1))
    fi
  fi
fi

# --- Phase 1→2 BACKSTOP: data_classification + ZDR attestation (tier-crosscheck-6) ---
# docs/governance-framework.md §VII line 299 declared a "Mandatory ZDR
# gate" — projects classified Internal or higher MUST use the ZDR or
# self-hosted deployment path. The gate was documented but never
# enforced: no field captured the classification, no field recorded the
# ZDR attestation, and this script had no backstop reading any such
# field. tier-crosscheck-6 (the final S3 audit finding) closes the loop
# by making this an invariant equivalent to the github_free_tier
# branch-protection backstop above (PR #75).
#
# Behavior: when current_phase >= 2, the gate REFUSES (exit 1, FAIL line)
# unless .claude/process-state.json::phase1_artifacts carries:
#   * data_classification: one of {public, internal, confidential, pii,
#     financial, health, regulated} — the 7-tier taxonomy adopted from
#     templates/project-intake.md:209 + docs/user-guide.md:466.
#   * AND one of: zdr_attested == true | "true",
#     OR  zdr_attestation_reason is a non-empty string (written exception
#     such as a customer-mandated retention clause or a self-hosted LLM).
#
# Remediation message points operators at intake-wizard.sh (greenfield)
# and reconfigure-project.sh --field data_classification (retrofit).
if [ "$current_phase" -ge 2 ]; then
  zdr_state_file=".claude/process-state.json"
  zdr_taxonomy="public internal confidential pii financial health regulated"
  zdr_classification=""
  zdr_attested_raw=""
  zdr_reason=""

  if [ -f "$zdr_state_file" ] && command -v jq >/dev/null 2>&1; then
    zdr_classification=$(jq -r '.phase1_artifacts.data_classification // ""' "$zdr_state_file" 2>/dev/null || echo "")
    zdr_attested_raw=$(jq -r '.phase1_artifacts.zdr_attested // ""' "$zdr_state_file" 2>/dev/null || echo "")
    zdr_reason=$(jq -r '.phase1_artifacts.zdr_attestation_reason // ""' "$zdr_state_file" 2>/dev/null || echo "")
    # jq returns the string "null" when a key is present but null; normalize.
    [ "$zdr_classification" = "null" ] && zdr_classification=""
    [ "$zdr_attested_raw" = "null" ]  && zdr_attested_raw=""
    [ "$zdr_reason" = "null" ]        && zdr_reason=""
  fi

  # Normalize classification to lowercase canonical form so the taxonomy
  # match isn't fooled by stored "Public" vs "public" — both intake and
  # reconfigure write the canonical lowercase value, but defense-in-
  # depth covers operators who hand-edit process-state.json.
  zdr_classification_canon=$(printf '%s' "$zdr_classification" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  zdr_taxonomy_ok=0
  if [ -n "$zdr_classification_canon" ]; then
    for _allowed in $zdr_taxonomy; do
      if [ "$zdr_classification_canon" = "$_allowed" ]; then
        zdr_taxonomy_ok=1
        break
      fi
    done
  fi

  zdr_attest_ok=0
  case "$zdr_attested_raw" in
    true|True|TRUE) zdr_attest_ok=1 ;;
  esac
  if [ "$zdr_attest_ok" -eq 0 ] && [ -n "$zdr_reason" ]; then
    zdr_attest_ok=1
  fi

  if [ -z "$zdr_classification_canon" ]; then
    echo -e "${RED}[FAIL]${NC} Phase 1→2 ZDR gate: phase1_artifacts.data_classification not set in $zdr_state_file"
    echo "        Required taxonomy (one of): $zdr_taxonomy"
    echo "        Remediate: scripts/intake-wizard.sh (greenfield) — OR for retrofit:"
    echo "                   bash scripts/reconfigure-project.sh --field data_classification --new <value>"
    echo "        Reference: docs/governance-framework.md § VII (Mandatory ZDR gate, line 299) + invariant #16."
    issues=$((issues + 1))
  elif [ "$zdr_taxonomy_ok" -eq 0 ]; then
    echo -e "${RED}[FAIL]${NC} Phase 1→2 ZDR gate: invalid data_classification '$zdr_classification' (not in taxonomy)"
    echo "        Allowed (one of): $zdr_taxonomy"
    echo "        Remediate: bash scripts/reconfigure-project.sh --field data_classification --new <value>"
    issues=$((issues + 1))
  elif [ "$zdr_classification_canon" = "public" ]; then
    # docs/governance-framework.md § VII line 297-299: ZDR is mandatory
    # for Internal or higher. Public-only projects are exempt from the
    # attestation requirement — the classification itself is the
    # evidence that no sensitive data flows to the LLM provider.
    echo -e "${GREEN}  [OK]${NC} Phase 1→2 ZDR gate: data_classification='public' (ZDR attestation not required for Public-only data)"
  elif [ "$zdr_attest_ok" -eq 0 ]; then
    echo -e "${RED}[FAIL]${NC} Phase 1→2 ZDR gate: data_classification='$zdr_classification_canon' but no ZDR attestation evidence"
    echo "        Required: phase1_artifacts.zdr_attested=true OR a non-empty phase1_artifacts.zdr_attestation_reason."
    echo "        Remediate: bash scripts/reconfigure-project.sh --field zdr_attested --new true"
    echo "                   (or --field zdr_attestation_reason --new \"<written exception, e.g. customer retention SOW>\")"
    echo "        Reference: docs/governance-framework.md § VII (line 297-299) — ZDR mandatory for Internal or higher."
    issues=$((issues + 1))
  else
    if [ -n "$zdr_reason" ] && [ "$zdr_attested_raw" != "true" ] && [ "$zdr_attested_raw" != "True" ] && [ "$zdr_attested_raw" != "TRUE" ]; then
      echo -e "${GREEN}  [OK]${NC} Phase 1→2 ZDR gate: data_classification='$zdr_classification_canon' (attestation reason: $zdr_reason)"
    else
      echo -e "${GREEN}  [OK]${NC} Phase 1→2 ZDR gate: data_classification='$zdr_classification_canon', zdr_attested=true"
    fi
  fi
fi

# Approval field validation: Phase 1→2 (P0-004)
if [ "$current_phase" -ge 2 ]; then
  validate_approval_fields "Phase 1.*Phase 2" "Phase 1→2"
fi

# Artifact existence + completeness check: Phase 1→2 (P1-008, P1-011)
if [ "$current_phase" -ge 2 ]; then
  if [ -f "PROJECT_BIBLE.md" ]; then
    echo -e "${GREEN}  [OK]${NC} PROJECT_BIBLE.md exists"
    # Check for placeholder dates (YYYY-MM-DD) indicating unfilled sections
    placeholder_dates=$(grep -c "YYYY-MM-DD" PROJECT_BIBLE.md 2>/dev/null || echo "0")
    case "$placeholder_dates" in ''|*[!0-9]*) placeholder_dates=0 ;; esac
    if [ "$placeholder_dates" -gt 0 ]; then
      echo -e "${YELLOW}[WARN]${NC} PROJECT_BIBLE.md has $placeholder_dates placeholder date(s) — update Last Updated markers"
      issues=$((issues + 1))
    fi
    # Check key sections exist (numbered 1-16 per template)
    bible_sections=$(grep -cE "^## [0-9]+\." PROJECT_BIBLE.md 2>/dev/null || echo "0")
    case "$bible_sections" in ''|*[!0-9]*) bible_sections=0 ;; esac
    if [ "$bible_sections" -lt 14 ]; then
      echo -e "${YELLOW}[WARN]${NC} PROJECT_BIBLE.md has only $bible_sections numbered sections (template specifies 16, minimum 14)"
      issues=$((issues + 1))
    fi
  else
    echo -e "${RED}[FAIL]${NC} Phase 1→2: PROJECT_BIBLE.md not found"
    issues=$((issues + 1))
  fi
fi

# audit tier-crosscheck-5 closure: Personal → Organizational upgrade
# retroactive STA approval. baseline §4 row 5 / builders-guide.md line
# 807 require that any project upgraded from personal to organizational
# have its existing Project Bible retroactively reviewed and approved
# by a Senior Technical Authority. Pre-fix nothing enforced this — the
# upgrade-project.sh APPROVAL_LOG.md restructure didn't even surface
# a row for the retroactive sign-off, so check-phase-gate.sh had
# nothing to validate.
#
# Behavior: when the APPROVAL_LOG.md frontmatter carries
# `upgraded_from: personal` AND current_phase >= 2, parse the
# `Retroactive Phase 1 → Phase 2 STA Approval` section. If the
# Approver or Date is blank, emit a non-blocking WARN (does NOT
# increment $issues — this is a recurring nudge, not a gate-block,
# per the audit recommendation). When the section is missing entirely
# we WARN too (for projects upgraded before this row was added).
if [ "$current_phase" -ge 2 ] && [ -f "$APPROVAL_LOG" ] && \
   grep -q '^upgraded_from: personal' "$APPROVAL_LOG" 2>/dev/null; then
  # Slice out the Retroactive section header and the next ~15 lines.
  retro_section=$(grep -A 15 "Retroactive Phase 1.*Phase 2.*STA" "$APPROVAL_LOG" 2>/dev/null || echo "")
  if [ -z "$retro_section" ]; then
    echo -e "${YELLOW}[WARN]${NC} Phase 1→2 retroactive: project upgraded from personal but APPROVAL_LOG.md has no 'Retroactive Phase 1 → Phase 2 STA Approval' section."
    echo "        Required by docs/builders-guide.md § Phase 1 (line 807). Re-run scripts/upgrade-project.sh"
    echo "        to regenerate the section, or add it manually with Approver + Date."
  else
    # Extract Approver and Date values from the Field/Value table.
    retro_approver=$(echo "$retro_section" | grep -E '\*\*Approver\*\*' | head -1 | sed -E 's/.*\*\*Approver\*\*[[:space:]]*\|[[:space:]]*//; s/[[:space:]]*\|.*$//')
    retro_date=$(echo "$retro_section" | grep -E '\*\*Date\*\*' | head -1 | sed -E 's/.*\*\*Date\*\*[[:space:]]*\|[[:space:]]*//; s/[[:space:]]*\|.*$//')
    if [ -z "$retro_approver" ] || [ -z "$retro_date" ]; then
      echo -e "${YELLOW}[WARN]${NC} Phase 1→2 retroactive: project upgraded from personal but Retroactive STA Approval row is incomplete (Approver='$retro_approver' Date='$retro_date')."
      echo "        Required by docs/builders-guide.md § Phase 1 (line 807). Have the Senior Technical"
      echo "        Authority retroactively review the Project Bible and fill in the Approver + Date."
    else
      echo -e "${GREEN}  [OK]${NC} Phase 1→2 retroactive: STA approval recorded ($retro_approver, $retro_date)"
    fi
  fi
fi

# Check: if current_phase >= 3, gate 2→3 should have a date (BL-071: see
# the Phase 0→1 block for the evidence-first auto-write rationale).
if [ "$current_phase" -ge 3 ]; then
  if _cpg_gate_has_evidence "Phase 2.*Phase 3"; then
    cpg_rc=0
    _cpg_record_gate_date "phase_2_to_3" "Phase 2→3" "$gate_2_to_3" || cpg_rc=$?
    [ "$cpg_rc" -eq 2 ] && issues=$((issues + 1))
  elif [ -n "$gate_2_to_3" ]; then
    echo -e "${YELLOW}[WARN]${NC} Phase 2→3: gate dated $gate_2_to_3, but APPROVAL_LOG.md has no dated entry"
    issues=$((issues + 1))
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 2→3: current_phase is $current_phase but gate date not recorded in phase-state.json"
    issues=$((issues + 1))
  fi
fi

# Artifact existence check: Phase 2→3
if [ "$current_phase" -ge 3 ]; then
  if [ -f "FEATURES.md" ]; then
    echo -e "${GREEN}  [OK]${NC} FEATURES.md exists"
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 2→3: FEATURES.md not found"
    issues=$((issues + 1))
  fi
  if [ -f "CHANGELOG.md" ]; then
    echo -e "${GREEN}  [OK]${NC} CHANGELOG.md exists"
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 2→3: CHANGELOG.md not found"
    issues=$((issues + 1))
  fi
fi

# Check: if current_phase >= 4, gate 3→4 should have a date (BL-071: see
# the Phase 0→1 block for the evidence-first auto-write rationale).
if [ "$current_phase" -ge 4 ]; then
  if _cpg_gate_has_evidence "Phase 3.*Phase 4"; then
    cpg_rc=0
    _cpg_record_gate_date "phase_3_to_4" "Phase 3→4" "$gate_3_to_4" || cpg_rc=$?
    [ "$cpg_rc" -eq 2 ] && issues=$((issues + 1))
  elif [ -n "$gate_3_to_4" ]; then
    echo -e "${YELLOW}[WARN]${NC} Phase 3→4: gate dated $gate_3_to_4, but APPROVAL_LOG.md has no dated entry"
    issues=$((issues + 1))
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 3→4: current_phase is $current_phase but gate date not recorded in phase-state.json"
    issues=$((issues + 1))
  fi

  # P3-007 / tier-crosscheck-13: For organizational deployments at
  # Phase 4, verify BOTH the Application Owner Approval AND IT
  # Security Approval subsections have a populated Date row.
  #
  # Pre-fix used bare presence greps against the whole APPROVAL_LOG
  # which the unfilled org template (subsection headers + Role rows)
  # already satisfied. Now runs regardless of the outer gate date
  # check, so a freshly-generated empty template always surfaces a
  # named WARN for whichever approver section lacks a Date.
  if [ "$deployment" = "organizational" ]; then
    app_owner_ok=0; it_sec_ok=0
    validate_approval_section_dated "Application Owner Approval" && app_owner_ok=1
    validate_approval_section_dated "IT Security Approval"       && it_sec_ok=1
    if [ "$app_owner_ok" -eq 1 ] && [ "$it_sec_ok" -eq 1 ]; then
      echo -e "${GREEN}  [OK]${NC} Phase 3→4: both Application Owner and IT Security approvals dated"
    else
      missing=""
      [ "$app_owner_ok" -eq 0 ] && missing="Application Owner"
      [ "$it_sec_ok"   -eq 0 ] && missing="${missing:+$missing, }IT Security"
      echo -e "${YELLOW}[WARN]${NC} Phase 3→4: organizational deployment requires a populated Date row in both Application Owner AND IT Security approval subsections (missing: $missing)"
      issues=$((issues + 1))
    fi
  fi
fi

# ═══════════════════════════════════════════════════════════════════════
# BL-070: Phase 3 validation scans (Snyk / license / full-tree Semgrep /
# OWASP ZAP DAST / threat-model) + attest-on-skip gate.
#
# The Builder's/User guides imply Phase 3 auto-runs these five scans; a grep
# of scripts/ found ZERO invocations. This distinct, self-contained step
# (Karl-approved Option C) refuses Phase 3→4 unless the aggregate summary
# from scripts/run-phase3-validation.sh exists AND every scanner is PASS or
# an attested-skip-with-signoff (zero un-attested SKIPs, zero FAILs).
#
# Positioned deliberately APART from the review-manifest reviewer check
# (BL-073, further below) to keep the two Phase-3→4 gate edits from
# colliding on rebase.
#
# `# BL-070-GATE-CHECK` marks the load-bearing enforcement (mutation target,
# per tests/test-phase3-validation-gate.sh::T-mutation). Auto-run marked
# `# BL-070-GATE-AUTORUN`. Attestation predicate marked
# `# BL-070-ATTEST-PREDICATE`.

# _cpg_phase3_attested <scanner>
# 0 iff phase-state.json::phase3.attestations.<scanner> carries a non-empty
# reason AND a non-empty sign-off. jq-absent → not-attested (conservative).
_cpg_phase3_attested() {
  local name="$1" reason signoff
  command -v jq >/dev/null 2>&1 || return 1   # BL-070-ATTEST-PREDICATE
  reason=$(jq -r --arg n "$name" '.phase3.attestations[$n].reason // ""' "$PHASE_STATE" 2>/dev/null || echo "")
  signoff=$(jq -r --arg n "$name" '.phase3.attestations[$n].signoff // ""' "$PHASE_STATE" 2>/dev/null || echo "")
  # Trim leading/trailing whitespace (bash-3.2 param-expansion) BEFORE the
  # non-empty check so a whitespace-only reason/signoff is un-attested → gate
  # FAIL (verifier follow-up — `[ -n " " ]` is true, which would pass " ").
  reason="${reason#"${reason%%[![:space:]]*}"}"; reason="${reason%"${reason##*[![:space:]]}"}"
  signoff="${signoff#"${signoff%%[![:space:]]*}"}"; signoff="${signoff%"${signoff##*[![:space:]]}"}"
  [ -n "$reason" ] && [ "$reason" != "null" ] && [ -n "$signoff" ] && [ "$signoff" != "null" ]
}

if [ "$current_phase" -ge 4 ]; then
  P3_RESULTS_DIR="docs/test-results/phase3"
  P3_DRIVER="$SCRIPT_DIR/run-phase3-validation.sh"

  # AUTO-RUN (Karl: "evals should be automatic"). If no summary exists yet,
  # generate a baseline offline summary so the attestation gate always has
  # teeth (offline => hermetic/fast: NO network/Docker/semgrep run from the
  # gate). Operators run `scripts/run-phase3-validation.sh` (no --offline)
  # for REAL scans; a later increment can auto-run real scans in interactive
  # sessions. Set SOLO_PHASE3_GATE_NOAUTORUN=1 to disable auto-generation
  # (e.g. CI that pre-runs the driver, or a pure read-only inspection).
  p3_summary=""
  if compgen -G "$P3_RESULTS_DIR/summary-*.md" >/dev/null 2>&1; then
    p3_summary=$(ls -1 "$P3_RESULTS_DIR"/summary-*.md 2>/dev/null | sort | tail -1)
  fi
  if [ -z "$p3_summary" ] && [ -z "${SOLO_PHASE3_GATE_NOAUTORUN:-}" ] && [ -x "$P3_DRIVER" ]; then
    bash "$P3_DRIVER" --offline >/dev/null 2>&1 || true   # BL-070-GATE-AUTORUN
    if compgen -G "$P3_RESULTS_DIR/summary-*.md" >/dev/null 2>&1; then
      p3_summary=$(ls -1 "$P3_RESULTS_DIR"/summary-*.md 2>/dev/null | sort | tail -1)
    fi
  fi

  p3_block=0
  p3_msg=""
  p3_ok_detail=""
  if [ -z "$p3_summary" ]; then
    p3_block=1
    p3_msg="no Phase 3 validation summary (docs/test-results/phase3/summary-*.md) — run: bash scripts/run-phase3-validation.sh"
  else
    p3_fail=0
    p3_unattested=0
    p3_detail=""
    for p3_scanner in semgrep-full-tree license snyk zap-dast threat-model; do
      p3_status=$(awk -v s="$p3_scanner" '$1=="RESULT" && $2==s {v=$3} END{print v}' "$p3_summary" 2>/dev/null || true)
      [ -n "$p3_status" ] || p3_status="MISSING"
      case "$p3_status" in
        PASS) ;;
        SKIP)
          if _cpg_phase3_attested "$p3_scanner"; then
            :   # attested-skip-with-signoff → acceptable
          else
            p3_unattested=$((p3_unattested + 1))
            p3_detail="${p3_detail}${p3_detail:+, }${p3_scanner}(un-attested SKIP)"
          fi
          ;;
        *)
          # FAIL, MISSING, or any garbled/unknown status counts toward the
          # block — a real scanner (e.g. semgrep) reporting findings, or a
          # summary missing/corrupting a scanner's RESULT line, must NOT
          # slip through as clean.
          p3_fail=$((p3_fail + 1))   # BL-070-FAIL-ARM: FAIL/MISSING status is gate-blocking (mutation target)
          p3_detail="${p3_detail}${p3_detail:+, }${p3_scanner}(${p3_status})"
          ;;
      esac
    done
    if [ "$p3_fail" -gt 0 ] || [ "$p3_unattested" -gt 0 ]; then
      p3_block=1
      p3_msg="validation scans not clean: ${p3_fail} FAIL, ${p3_unattested} un-attested SKIP [${p3_detail}] — attest: bash scripts/run-phase3-validation.sh --attest <scanner> --reason \"...\", or install the tool and re-run"
    else
      p3_ok_detail="all PASS or attested-skip; summary: $(basename "$p3_summary")"
    fi
  fi

  if [ "$p3_block" -eq 1 ]; then
    echo -e "${RED}[FAIL]${NC} Phase 3→4: $p3_msg"   # BL-070-GATE-CHECK
    issues=$((issues + 1))                            # BL-070-GATE-CHECK
    : # phase-3 validation enforcement block — kept non-empty so a mutation excising the two marked lines above stays syntactically valid
  else
    echo -e "${GREEN}  [OK]${NC} Phase 3→4: validation scans clean (${p3_ok_detail})"
  fi
fi

# POC mode check (Phase 3→4) — block production release if in POC mode
if [ "$current_phase" -ge 3 ]; then
  poc_mode=""
  if command -v jq &>/dev/null; then
    poc_mode=$(jq -r '.poc_mode // empty' .claude/phase-state.json 2>/dev/null || echo "")
  else
    poc_mode=$(grep -o '"poc_mode"[[:space:]]*:[[:space:]]*"[^"]*"' .claude/phase-state.json 2>/dev/null | sed 's/.*: *"//' | sed 's/"//' || echo "")
  fi
  if [ -n "$poc_mode" ] && [ "$poc_mode" != "null" ]; then
    echo "::error::Phase 4 (production release) is BLOCKED — project is in ${poc_mode//_/ } mode."
    echo "  POC projects complete at Phase 3 (ready to deploy)."
    echo "  To unlock Phase 4: bash scripts/upgrade-project.sh --to-production"
    issues=$((issues + 1))
  fi
fi

# Release pipeline configuration check (Phase 3→4)
if [ "$current_phase" -ge 3 ]; then
  if [ -f ".github/workflows/release.yml" ]; then
    todo_count=$(grep -c "TODO" .github/workflows/release.yml 2>/dev/null) || todo_count=0
    if [ "$todo_count" -gt 0 ]; then
      echo -e "${YELLOW}[WARN]${NC} Release pipeline has $todo_count unconfigured TODO items in .github/workflows/release.yml"
      echo "  Configure code signing, deployment secrets, and store credentials before production release."
      issues=$((issues + 1))
    fi
  fi
fi

# Artifact existence checks: Phase 3→4
if [ "$current_phase" -ge 3 ]; then
  for artifact in "HANDOFF.md" "docs/INCIDENT_RESPONSE.md" "sbom.json"; do
    if [ -f "$artifact" ]; then
      echo -e "${GREEN}  [OK]${NC} $artifact exists"
    else
      echo -e "${YELLOW}[WARN]${NC} Phase 3→4: $artifact not found"
      issues=$((issues + 1))
    fi
  done

  # Check docs/test-results/ is non-empty (elevated to FAIL for Phase 3→4)
  if [ -d "docs/test-results" ]; then
    result_count=$(find docs/test-results -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$result_count" -eq 0 ]; then
      echo -e "${RED}[FAIL]${NC} Phase 3→4: docs/test-results/ is empty — archive Phase 3 scan results before proceeding"
      issues=$((issues + 1))
    else
      echo -e "${GREEN}  [OK]${NC} docs/test-results/ has $result_count file(s)"
    fi
  else
    echo -e "${RED}[FAIL]${NC} Phase 3→4: docs/test-results/ directory not found"
    issues=$((issues + 1))
  fi

  # P4-013: SECURITY.md check (web/desktop/mobile with external users)
  if [ -f "SECURITY.md" ]; then
    echo -e "${GREEN}  [OK]${NC} SECURITY.md exists"
  else
    echo -e "${YELLOW}[WARN]${NC} Phase 3→4: SECURITY.md not found — required for production web/desktop/mobile apps"
    issues=$((issues + 1))
  fi

  # P3-004: Penetration test check for Standard+ track
  if [ "$track" = "standard" ] || [ "$track" = "full" ]; then
    # UAT 2026-04-26 fix (T1-E): use compgen instead of `ls glob1 glob2 glob3
    # | head -1`. Under `set -euo pipefail`, `ls` returns non-zero on any
    # unmatched glob, propagating through the pipe and failing the if even
    # when one of the patterns matches a real file. compgen -G tests each
    # pattern independently and doesn't shell-out to ls.
    if compgen -G "docs/test-results/*pen-test*" >/dev/null \
       || compgen -G "docs/test-results/*pentest*" >/dev/null \
       || compgen -G "docs/test-results/*penetration*" >/dev/null; then
      echo -e "${GREEN}  [OK]${NC} Penetration test results found in docs/test-results/"
    elif [ "$track" = "standard" ] && grep -qi "penetration.*exempted\|pen.*test.*exempted" APPROVAL_LOG.md 2>/dev/null; then
      # Standard track allows IT Security exemption
      echo -e "${GREEN}  [OK]${NC} Penetration test exempted by IT Security (recorded in APPROVAL_LOG.md)"
    elif [ "$track" = "full" ]; then
      # Full track: no exemption path — pen test is mandatory
      echo -e "${RED}[FAIL]${NC} Phase 3→4: Full Track requires penetration test — no exemption path available"
      echo "  Provide pen test results in docs/test-results/ before proceeding."
      issues=$((issues + 1))
    else
      echo -e "${YELLOW}[WARN]${NC} Phase 3→4: No penetration test results or IT Security exemption found ($track track)"
      issues=$((issues + 1))
    fi
  fi

  # P3-007: Cross-reference process-state.json for Phase 3 completion
  if [ -f ".claude/process-state.json" ] && command -v jq &>/dev/null; then
    p3_steps_done=$(jq '.phase3_validation.steps_completed | length' .claude/process-state.json 2>/dev/null || echo "0")
    case "$p3_steps_done" in ''|*[!0-9]*) p3_steps_done=0 ;; esac
    if [ "$p3_steps_done" -ge 9 ]; then
      echo -e "${GREEN}  [OK]${NC} Phase 3 process checklist: $p3_steps_done steps completed"
    elif [ "$p3_steps_done" -gt 0 ]; then
      echo -e "${YELLOW}[WARN]${NC} Phase 3 process checklist incomplete: $p3_steps_done/9 steps"
      issues=$((issues + 1))
    fi
  fi
fi

# ── Review-manifest gate (Phase 3+) — BL-073 track-aware enforcement ──
# Historically this block only checked that the manifest FILE existed and
# emitted a WARN when absent — it never verified the six reviewers actually
# ran, so a Full-track project that skipped the Security + Red Team reviews
# passed Phase 3→4 with only a banner. BL-073 makes it a real, track-aware
# gate:
#   • track=full / track=standard  → FAIL if the Security OR Red Team
#     reviewer is missing/not-complete (the mandatory subset per
#     docs/builders-guide.md). Full track additionally requires all six —
#     the other four missing WARN and still count toward gate blocking.
#   • track=light / personal       → WARN only (POC preserved). The bypass
#     is logged to the console/CI audit trail; enforcement flips to FAIL
#     automatically once the track is promoted to standard/full.
# GRANDFATHER: enforcement (the FAIL) applies ONLY to projects created or
#   advanced under the enforcement regime, keyed on phase-state.json::
#   review_gate_enforced (stamped by init.sh at creation, re-stamped by
#   upgrade-project.sh on any tier advance). A pre-existing project that
#   lacks the flag keeps the legacy WARN-only behavior and is NEVER
#   retroactively blocked by the new completeness check.
# ESCAPE HATCH: SOLO_REVIEWERS_ATTESTED=1 + a documented reason (env
#   SOLO_REVIEWERS_ATTESTED_REASON, or a reason already recorded in
#   process-state.json) downgrades the FAIL to an attested OK and RECORDS
#   the decision to .claude/process-state.json::phase3.attestations.reviewers
#   (BL-032 lineage) — blocks are attested, not silenced.
if [ "$current_phase" -ge 3 ]; then
  MANIFEST="docs/eval-results/review-manifest.json"

  # Grandfather cutover: the FAIL applies only when the enforcement flag is
  # present AND the track mandates the reviews (standard or full). Read the
  # flag via jq, falling back to a tolerant grep when jq is absent.
  cpg_review_flag="false"
  if command -v jq >/dev/null 2>&1; then
    cpg_review_flag=$(jq -r 'if (.review_gate_enforced == true) then "true" else "false" end' "$PHASE_STATE" 2>/dev/null || echo "false")
  elif grep -qE '"review_gate_enforced"[[:space:]]*:[[:space:]]*true' "$PHASE_STATE" 2>/dev/null; then
    cpg_review_flag="true"
  fi
  cpg_review_enforced=0
  if [ "$cpg_review_flag" = "true" ] && { [ "$track" = "standard" ] || [ "$track" = "full" ]; }; then
    cpg_review_enforced=1
  fi

  # Escape hatch: resolve the attestation state (BL-032 lineage).
  cpg_reviewers_attested=0
  cpg_attest_reason=""
  cpg_attest_proactive=0
  if [ -f ".claude/process-state.json" ] && command -v jq >/dev/null 2>&1; then
    cpg_attest_reason=$(jq -r '.phase3.attestations.reviewers.reason // ""' ".claude/process-state.json" 2>/dev/null || echo "")
    [ "$cpg_attest_reason" = "null" ] && cpg_attest_reason=""
  fi
  if [ "${SOLO_REVIEWERS_ATTESTED:-}" = "1" ] && [ -n "${SOLO_REVIEWERS_ATTESTED_REASON:-}" ]; then
    cpg_attest_reason="$SOLO_REVIEWERS_ATTESTED_REASON"
  fi
  # Trim leading/trailing whitespace BEFORE the non-empty test so a
  # whitespace-only reason (e.g. "   ") is REJECTED — an attestation must
  # carry a real justification, not blank space (mirrors the BL-070
  # attestation-reason/signoff tightener). Empty was already rejected.
  cpg_attest_reason=$(printf '%s' "$cpg_attest_reason" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [ "${SOLO_REVIEWERS_ATTESTED:-}" = "1" ]; then
    if [ -n "$cpg_attest_reason" ]; then
      cpg_reviewers_attested=1
      cpg_attest_proactive=1
    fi
  elif [ -n "$cpg_attest_reason" ]; then
    cpg_reviewers_attested=1
  fi

  if [ ! -f "$MANIFEST" ]; then
    # No manifest at all. Legacy behavior (WARN + issues++) is preserved for
    # non-enforced projects; enforced-and-unattested escalates to FAIL.
    if [ "$cpg_review_enforced" -eq 1 ] && [ "$cpg_reviewers_attested" -eq 1 ]; then
      echo -e "${GREEN}  [OK]${NC} Phase 3→4 review gate: no manifest, but reviewers ATTESTED (reason: $cpg_attest_reason) — recorded to .claude/process-state.json (not silenced)."
      if [ "$cpg_attest_proactive" -eq 1 ]; then
        _cpg_record_reviewer_attestation "$cpg_attest_reason" "Security, Red Team (no manifest)" \
          || echo -e "${YELLOW}[WARN]${NC}   (could not persist the reviewer attestation — jq unavailable or state locked)"
      fi
    else
      cpg_review_sev="WARN"
      if [ "$cpg_review_enforced" -eq 1 ]; then
        : # BL-073 escalation guard — keeps this branch non-empty when the marked line below is excised (mutation-proof)
        cpg_review_sev="FAIL"   # BL-073-ESCALATE
      fi
      if [ "$cpg_review_sev" = "FAIL" ]; then
        echo -e "${RED}[FAIL]${NC} Phase 3→4 review gate: no review manifest found (docs/eval-results/review-manifest.json). track=$track requires the Security AND Red Team reviews before Phase 4."
        echo "  Run reviews: evaluation-prompts/Projects/run-reviews.sh — or attest: SOLO_REVIEWERS_ATTESTED=1 SOLO_REVIEWERS_ATTESTED_REASON=\"<reason>\""
        issues=$((issues + 1))
      else
        echo -e "${YELLOW}[WARN]${NC} No review manifest found (docs/eval-results/review-manifest.json)"
        echo "  Run evaluation prompts before Phase 4: evaluation-prompts/Projects/run-reviews.sh"
        issues=$((issues + 1))
      fi
    fi
  elif ! command -v jq >/dev/null 2>&1; then
    # Manifest present but jq unavailable — cannot verify reviewer
    # completion. Degrade to a blocking WARN under enforcement rather than
    # silently passing; preserve the legacy OK for non-enforced projects.
    if [ "$cpg_review_enforced" -eq 1 ]; then
      echo -e "${YELLOW}[WARN]${NC} Phase 3→4 review gate: review manifest present but jq is unavailable — cannot verify Security/Red Team completion for track=$track. Install jq."
      issues=$((issues + 1))
    else
      echo -e "${GREEN}  [OK]${NC} Review manifest exists (install jq for details)"
    fi
  else
    # Manifest present + jq available — verify the reviewers actually ran.
    review_count=$(jq '.reviews | length' "$MANIFEST" 2>/dev/null || echo "0")
    case "$review_count" in ''|*[!0-9]*) review_count=0 ;; esac
    review_commit=$(jq -r '.commit // "unknown"' "$MANIFEST" 2>/dev/null || echo "unknown")
    echo -e "${GREEN}  [OK]${NC} Review manifest: $review_count review(s) recorded (commit: ${review_commit:0:8})"

    # Map each COMPLETE review entry to a canonical role. Red Team is tested
    # BEFORE Security because "Red Team / Offensive Security" also contains
    # "security"; ordering keeps the two roles distinct. Accepts both the
    # canonical slug ("security", "redteam") and the descriptive persona
    # ("SVP IT Security", "Red Team / Offensive Security"). A missing status
    # field is treated as "complete" for backward-compat with pre-BL-073
    # manifests that recorded an entry only when the review file existed.
    cpg_present_roles=$(jq -r '
      [ .reviews[]?
        | select((.status // "complete") == "complete")
        | ((.reviewer // "") | ascii_downcase) as $r
        | if   ($r | test("red[ ._-]?team|offensive")) then "redteam"
          elif ($r | test("security"))                  then "security"
          elif ($r | test("engineer"))                  then "engineer"
          elif ($r | test("cio|chief information"))      then "cio"
          elif ($r | test("legal|counsel"))             then "legal"
          elif ($r | test("techuser|technical user|non.?coder")) then "techuser"
          else empty end
      ] | unique | join(" ")
    ' "$MANIFEST" 2>/dev/null || echo "")

    cpg_role_present() { case " $cpg_present_roles " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

    cpg_missing_mandatory=""
    cpg_role_present "security" || cpg_missing_mandatory="Security"
    cpg_role_present "redteam"  || cpg_missing_mandatory="${cpg_missing_mandatory:+$cpg_missing_mandatory, }Red Team"

    if [ -n "$cpg_missing_mandatory" ]; then
      if [ "$cpg_reviewers_attested" -eq 1 ]; then
        echo -e "${GREEN}  [OK]${NC} Phase 3→4 review gate: mandatory reviews incomplete (missing: $cpg_missing_mandatory) but ATTESTED (reason: $cpg_attest_reason) — recorded to .claude/process-state.json (not silenced)."
        if [ "$cpg_attest_proactive" -eq 1 ]; then
          _cpg_record_reviewer_attestation "$cpg_attest_reason" "$cpg_missing_mandatory" \
            || echo -e "${YELLOW}[WARN]${NC}   (could not persist the reviewer attestation — jq unavailable or state locked)"
        fi
      else
        cpg_review_sev="WARN"
        if [ "$cpg_review_enforced" -eq 1 ]; then
          : # BL-073 escalation guard — keeps this branch non-empty when the marked line below is excised (mutation-proof)
          cpg_review_sev="FAIL"   # BL-073-ESCALATE
        fi
        if [ "$cpg_review_sev" = "FAIL" ]; then
          echo -e "${RED}[FAIL]${NC} Phase 3→4 review gate: track=$track requires the Security AND Red Team reviews before Phase 4 (missing: $cpg_missing_mandatory)."
          echo "  Run reviews: evaluation-prompts/Projects/run-reviews.sh — or attest: SOLO_REVIEWERS_ATTESTED=1 SOLO_REVIEWERS_ATTESTED_REASON=\"<reason>\""
          issues=$((issues + 1))
        else
          echo -e "${YELLOW}[WARN]${NC} Phase 3→4 review gate: Security and/or Red Team review incomplete (missing: $cpg_missing_mandatory; track=$track) — bypass logged (grandfathered / POC: not blocking)."
        fi
      fi
    else
      echo -e "${GREEN}  [OK]${NC} Phase 3→4 review gate: Security and Red Team reviews complete."
    fi

    # Full Track requires ALL SIX reviewers. The remaining four are
    # non-mandatory (WARN, not the Security/Red Team FAIL) but, for an
    # enforced Full-track project, still count toward gate blocking.
    if [ "$cpg_review_enforced" -eq 1 ] && [ "$track" = "full" ]; then
      for _cpg_role_pair in "engineer:Senior Software Engineer" "cio:CIO" "legal:Corporate Legal" "techuser:Technical User"; do
        _cpg_rk="${_cpg_role_pair%%:*}"
        _cpg_rn="${_cpg_role_pair##*:}"
        if ! cpg_role_present "$_cpg_rk"; then
          echo -e "${YELLOW}[WARN]${NC} Phase 3→4 review gate: Full Track requires all six reviewers — $_cpg_rn review missing."
          issues=$((issues + 1))
        fi
      done
    fi
  fi
fi

# Check for reverse inconsistency: approval log has dates but phase state doesn't reflect them
if [ "$current_phase" -lt 1 ] && [ -n "$gate_0_to_1" ]; then
  echo -e "${YELLOW}[WARN]${NC} Phase 0→1 gate has date $gate_0_to_1 but current_phase is still $current_phase"
  issues=$((issues + 1))
fi

# --- Tool Resolution Check (for phase transitions) ---
# If transitioning to a new phase, check for deferred tools that are now needed
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESOLVER="$PROJECT_ROOT/scripts/resolve-tools.sh"
TOOL_PREFS=".claude/tool-preferences.json"

if [ -f "$TOOL_PREFS" ] && [ -x "$RESOLVER" ] && command -v jq &>/dev/null; then
  dev_os=$(jq -r '.context.dev_os' "$TOOL_PREFS" 2>/dev/null || echo "")
  platform=$(jq -r '.context.platform' "$TOOL_PREFS" 2>/dev/null || echo "")
  language=$(jq -r '.context.language' "$TOOL_PREFS" 2>/dev/null || echo "")
  track=$(jq -r '.context.track' "$TOOL_PREFS" 2>/dev/null || echo "")

  if [ -n "$dev_os" ] && [ -n "$platform" ] && [ -n "$language" ] && [ -n "$track" ]; then
    # Resolve for the current phase
    tool_output=$("$RESOLVER" \
      --dev-os "$dev_os" \
      --platform "$platform" \
      --language "$language" \
      --track "$track" \
      --phase "$current_phase" \
      --matrix-dir "$PROJECT_ROOT/templates/tool-matrix" \
      --tool-prefs "$TOOL_PREFS" 2>/dev/null) || tool_output=""

    if [ -n "$tool_output" ]; then
      missing_required=$(echo "$tool_output" | jq '[(.auto_install + .manual_install)[] | select(.required == true)]')
      missing_count=$(echo "$missing_required" | jq 'length')

      if [ "$missing_count" -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}${BOLD}Tools needed for Phase $current_phase:${NC}"
        echo "$missing_required" | jq -r '.[] | "  • \(.name) — \(.description // .category)"'
        echo ""

        # Check if any can be auto-installed
        auto_installable=$(echo "$tool_output" | jq '[.auto_install[]]')
        auto_count=$(echo "$auto_installable" | jq 'length')

        if [ "$auto_count" -gt 0 ]; then
          echo -e "${CYAN}The following can be auto-installed:${NC}"
          echo "$auto_installable" | jq -r '.[] | "  • \(.name)"'
          echo ""
          # code-check-gates-7: route through prompt_yes_no — hard-N
          # in CI / non-TTY (the helper ignores the caller-supplied
          # default in non-interactive contexts) so `eval` of install
          # commands never fires unattended. We still pass "N" here
          # as documentation of intent — caller-side belt + helper-
          # side suspenders (cycle-7 PR-#87 verifier finding).
          if prompt_yes_no "Install now? [Y/n]" N; then
            echo "$auto_installable" | jq -r '.[] | .install_command // empty' | while IFS= read -r cmd; do
              [ -z "$cmd" ] && continue
              echo -e "  ${CYAN}Running:${NC} $cmd"
              eval "$cmd" || echo -e "  ${YELLOW}[WARN]${NC} Command failed: $cmd"
            done
          fi
        fi

        # Show manual items
        manual_items=$(echo "$tool_output" | jq '[.manual_install[]]')
        manual_count=$(echo "$manual_items" | jq 'length')
        if [ "$manual_count" -gt 0 ]; then
          echo ""
          echo -e "${YELLOW}Manual setup still required:${NC}"
          echo "$manual_items" | jq -r '.[] | "  • \(.name) — \(.instructions // "see docs")"'
        fi

        # Special handling: if Qdrant is in the missing list and Docker is running, offer Docker setup
        if echo "$missing_required" | jq -e '.[] | select(.name == "Qdrant MCP")' >/dev/null 2>&1; then
          if command -v docker &>/dev/null && docker info &>/dev/null; then
            echo ""
            echo -e "${CYAN}Qdrant MCP can be set up now (Docker is running):${NC}"
            # code-check-gates-7: same non-interactive guard as the
            # main install prompt above. Qdrant setup spawns docker
            # containers + MCP registration — must not run in CI.
            # Pass "N" as caller default for symmetry; helper hard-N's
            # in non-interactive contexts regardless.
            if prompt_yes_no "Start Qdrant container and register MCP? [Y/n]" N; then
              # Check if container already exists
              if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^qdrant$"; then
                docker start qdrant 2>/dev/null && echo -e "  ${GREEN}[OK]${NC} Existing Qdrant container started"
              else
                docker run -d --name qdrant \
                  -p 6333:6333 -p 6334:6334 \
                  -v qdrant_storage:/qdrant/storage \
                  --restart unless-stopped \
                  qdrant/qdrant:latest 2>&1 && echo -e "  ${GREEN}[OK]${NC} Qdrant running at http://localhost:6333"
              fi
              # Register MCP if uvx available
              if command -v uvx &>/dev/null; then
                project_name=$(jq -r '.project // "claude-memory"' .claude/phase-state.json 2>/dev/null)
                if run_with_timeout 30 bash -c "echo y | claude mcp add -s user -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=$project_name qdrant -- uvx --python 3.13 mcp-server-qdrant >/dev/null 2>&1"; then
                  echo -e "  ${GREEN}[OK]${NC} Qdrant MCP registered (collection: $project_name)"
                else
                  echo -e "  ${YELLOW}[WARN]${NC} Qdrant MCP registration timed out or failed"
                  echo "  Register manually: claude mcp add -s user -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=$project_name qdrant -- uvx --python 3.13 mcp-server-qdrant"
                fi
              else
                echo -e "  ${YELLOW}[WARN]${NC} uv/uvx not found. Install: curl -LsSf https://astral.sh/uv/install.sh | sh"
                echo "  Then: claude mcp add -s user -e QDRANT_URL=http://localhost:6333 -e COLLECTION_NAME=claude-memory qdrant -- uvx --python 3.13 mcp-server-qdrant"
              fi
            fi
          fi
        fi

        issues=$((issues + 1))
      fi
    fi
  fi
fi

# --- Test/Bug Gate Check (for Phase 2→3) ---
TEST_GATE="$PROJECT_ROOT/scripts/test-gate.sh"

if [ -x "$TEST_GATE" ] && [ "$current_phase" -ge 3 ]; then
  echo ""
  echo -e "${BOLD}Bug Gate Check${NC}"
  gate_result=0
  bash "$TEST_GATE" --check-phase-gate || gate_result=$?

  if [ "$gate_result" -eq 1 ]; then
    echo ""
    echo -e "${RED}[FAIL]${NC} Bug gate BLOCKED. Resolve SEV-1/2 bugs before Phase 3."
    issues=$((issues + 1))
  elif [ "$gate_result" -eq 2 ]; then
    echo ""
    echo -e "${YELLOW}[WARN]${NC} Bug gate has warnings. User attestation required."
    issues=$((issues + 1))
  fi
fi

echo ""
if [ $issues -eq 0 ]; then
  echo -e "${GREEN}${BOLD}Phase gates consistent.${NC}"

  # Create snapshots for gates that have been passed but not yet snapshotted
  if [ "$current_phase" -ge 1 ]; then
    existing_01=$(ls -d docs/snapshots/phase-0-to-1_* 2>/dev/null | head -1 || true)
    [ -z "$existing_01" ] && create_gate_snapshot 0 1
  fi
  if [ "$current_phase" -ge 2 ]; then
    existing_12=$(ls -d docs/snapshots/phase-1-to-2_* 2>/dev/null | head -1 || true)
    [ -z "$existing_12" ] && create_gate_snapshot 1 2
  fi
  if [ "$current_phase" -ge 3 ]; then
    existing_23=$(ls -d docs/snapshots/phase-2-to-3_* 2>/dev/null | head -1 || true)
    [ -z "$existing_23" ] && create_gate_snapshot 2 3
  fi
  if [ "$current_phase" -ge 4 ]; then
    existing_34=$(ls -d docs/snapshots/phase-3-to-4_* 2>/dev/null | head -1 || true)
    [ -z "$existing_34" ] && create_gate_snapshot 3 4
  fi

  exit 0
else
  if [ "${SOIF_PHASE_GATES:-}" = "warn" ]; then
    echo -e "${YELLOW}${BOLD}$issues inconsistency(ies) found (warn mode — not blocking).${NC}"
    echo "Update .claude/phase-state.json and APPROVAL_LOG.md to match."
    exit 0
  else
    echo -e "${RED}${BOLD}$issues inconsistency(ies) found — blocking.${NC}"
    echo "Update .claude/phase-state.json and APPROVAL_LOG.md to match."
    echo "Set SOIF_PHASE_GATES=warn to downgrade to warning."
    exit 1
  fi
fi
