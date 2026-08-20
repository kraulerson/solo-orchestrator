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
# BL-233 WP-B: the accumulation predicates the commit-time warning must match.
#
# GUARDED, and the degradation is deliberate. Hard-failing here was the first
# attempt and it was WRONG: a project that predates this lib — every existing
# install, and every brownfield-adopted tree until it re-syncs — would have had
# its ENTIRE phase gate killed by a feature it never opted into. Measured: that
# reds test-walk-phase-lifecycle.sh, test-brownfield-wp3-adoption-arms.sh and
# test-brownfield-wp3-regenerate-path.sh, all of which model exactly that
# population.
#
# So the ACCUMULATION ARM alone goes unavailable and says so, naming the remedy;
# every other check in this gate runs untouched. It does NOT count against the
# gate: a project that never had this feature has not failed it. That is the
# same shape as the `none` requirement state, for the same reason.
SOIF_ACCUM_LIB_LOADED=0
if [ -f "$SCRIPT_DIR/lib/accumulation.sh" ]; then
  # shellcheck source=scripts/lib/accumulation.sh
  . "$SCRIPT_DIR/lib/accumulation.sh"
  SOIF_ACCUM_LIB_LOADED=1
fi
# Brownfield adoption WP3 — the in-core enabling arms (the `adopted` flag
# accessor and the regenerate-path loss detector). Guarded: a checkout that
# predates adoption simply has no such file, and the arm below no-ops.
if [ -f "$SCRIPT_DIR/lib/adoption-stamp.sh" ]; then
  # shellcheck source=scripts/lib/adoption-stamp.sh
  source "$SCRIPT_DIR/lib/adoption-stamp.sh"
fi

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

# BL-158-GATE-LABEL: capture the RECORDED phase BEFORE any --gate override so the
# header (and audit trails) can distinguish "as-if <forced>" from the state the
# project actually records. On a bare run this equals current_phase (header
# unchanged); under --gate it is the pre-override value.
recorded_phase="$current_phase"

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

# BL-166-GATE-SCOPE: keep a scoped --gate run's exit/count confined to the NAMED
# gate's checks. The override above sets current_phase to the named gate's TARGET
# so that gate's checks fire — but the Phase 3→4 readiness blocks below are
# guarded by `current_phase -ge 3`, which is EXACTLY the target of
# --gate phase_2_to_3. Without this fence those later-gate readiness checks
# (HANDOFF.md, sbom.json, pentest, docs/test-results/, review manifest, Phase-3
# process checklist) all fire and increment `issues`, so a project that
# legitimately clears every 2→3 requirement still exited 1 "8 inconsistency(ies)
# — blocking" (BL-166). When --gate names a gate whose TARGET is below 4, we set
# skip_later_gate=1; the Phase 3→4 readiness region then announces itself as a
# single non-counted [NEXT] line and does NOT run its block-counting checks.
#   • Bare run (no --gate): gate_scope_target="" and skip_later_gate stays 0 →
#     full per-item enforcement, byte-for-byte unchanged (BL-166 requirement).
#   • --gate phase_3_to_4 (target 4): skip_later_gate stays 0 → full enforcement.
# The `skip_later_gate=1` decision line is the mutation target: neutering it
# restores the leak and flips tests/test-bl166-gate-scope.sh::(a) RED.
gate_scope_target=""
skip_later_gate=0
if [ -n "$GATE_SCOPE" ]; then
  gate_scope_target="$current_phase"   # override set this to the named gate's target
  [ "$gate_scope_target" -lt 4 ] && skip_later_gate=1   # BL-166-GATE-SCOPE mutation target
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
  grep -q "$header" "$APPROVAL_LOG" || return 1
  # BL-115-DATE-CELL — the date must sit in the approval's Date ROW, not
  # anywhere in a 15-line proximity window: a BLANK Date cell used to be
  # masked by an incidental date in a Reference/Notes cell (walk F6 /
  # P1-010 — approval evidence satisfiable without approval). Accept both
  # `| Date |` and `| **Date** |` row shapes. The window is BOUNDED AT THE
  # NEXT `## ` SECTION (verifier SF#1): without the bound, a section with
  # NO Date row at all stole the next section's date through the window —
  # a missing row must be at least as strict as a blank one. awk range:
  # from the header line (exclusive) to the next section header or +15
  # lines, whichever first.
  awk -v h="$header" '$0 ~ h {f=1; next} f && /^## / {exit} f' "$APPROVAL_LOG" \
    | head -15 \
    | grep -E '^\|[[:space:]]*\**[[:space:]]*Date[[:space:]]*\**[[:space:]]*\|' \
    | head -1 \
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

# ══ BL-233 WP-B: the ACCUMULATION gate ═════════════════════════════════════
# WP-A made the RETRIEVAL half score outcomes instead of declarations. Nothing
# anywhere required that anything was ever WRITTEN for a later session to
# retrieve, and the entry names the consequence in one line: *a retrieval
# requirement with no accumulation requirement is a ratchet with nothing behind
# it.*
#
# Karl's decision (2026-08-17): WARN at commit, BLOCK here. Storing is not
# per-commit work — a commit that produced no insight has nothing to store, and
# a gate people cannot satisfy honestly is a gate they delete (`## BL-149:`).
# The phase boundary is where accumulation is genuinely owed, because it is the
# boundary the memory is supposed to carry across.

# WHERE THE REQUIREMENT COMES FROM — the decision most likely to be re-litigated.
#
# Reading it from .claude/tool-usage.json is the obvious answer and is wrong
# twice: the ledger is untracked runtime scratch that `startup` wipes, so
# deleting it would switch a blocking gate off (`## BL-231:`); and MEASURED ON
# MERGE-BASE 2344b13 — the tree the decision was made against, and stated as such
# because these numbers move with the PR — of the 60 suites that name
# check-phase-gate.sh under tests/, 29 drive it at current_phase >= 2 and NOT ONE
# writes a ledger, so a ledger-derived requirement would have forced an edit to
# every one of them to say nothing. The recipe is on `## BL-233:`; the
# load-bearing number is the ZERO.
#
# The earlier form of this comment said "61 suites" and "74 fixture-creation
# sites". The 61 was read off a working tree that already contained this
# feature's own new suite, and the 74 reproduces under no derivation anyone can
# write down, so it is WITHDRAWN. Both are corrected here and not only in the
# backlog: shipping a retraction to the ledger while the code keeps asserting the
# retracted figure is the same defect one file over.
#
# The first fix for that read .claude/settings.local.json instead, on the
# reasoning that init.sh writes it and `git add -A` commits it. THAT WAS ALSO
# WRONG, and worse, because it looked committed: Claude Code adds
# settings.local.json to the user's GLOBAL git excludes by design, so the
# requirement was invisible in every fresh clone and the gate blocked on the
# author's machine while printing NOT CHECKED on CI. The lesson is not "use a
# different file" — it is that TRACKEDNESS IS A QUESTION FOR GIT, not an
# inference from an ignore file you happened to read. accum_file_tracked asks it
# (scripts/lib/accumulation.sh, shared with the commit-time warning).
#
# $HOME is still never read, for the original reason: on that same base tree,
# zero of those 29 fixtures
# redirect HOME, so a host-derived verdict passes on a developer box with Qdrant
# configured and fails on a runner without it — `## BL-234:`'s class. A5 and
# mutant M3 pin the project-only scope in both directions.

# _cpg_accum_last_store — ISO timestamp of the last SUCCESSFUL qdrant-store,
# from the durable record that scripts/track-tool-usage.sh writes. A missing
# object reads as "" (no stores): a missing key defaulting RESTRICTIVE, which is
# the inverse of `## BL-221:`.
# _cpg_accum_record_unreadable — does the durable record exist but not parse?
#
# A SEPARATE PREDICATE, not a flag set inside _cpg_accum_last_store. That was the
# first attempt and it could not work: the caller reads that function through a
# COMMAND SUBSTITUTION, which is a subshell, so any global it assigns dies with
# it. Same subshell class that hid a meta-failure in this feature's own mutation
# harness earlier in this work.
_cpg_accum_record_unreadable() {
  [ -f ".claude/process-state.json" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  if _accum_json_ok ".claude/process-state.json"; then return 1; fi
  return 0   # BL-233-WPB-RECORD-UNREADABLE
}

_cpg_accum_last_store() {
  local v
  if [ ! -f ".claude/process-state.json" ] || ! command -v jq >/dev/null 2>&1; then
    printf ''
    return 0
  fi
  if ! _accum_json_ok ".claude/process-state.json"; then
    printf ''
    return 0
  fi
  v=$(jq -r '.mcp_accumulation.last_store_at // ""' ".claude/process-state.json" 2>/dev/null || printf '')
  if [ "$v" = "null" ]; then v=""; fi
  printf '%s' "$v"
}

# _cpg_accum_after <iso_timestamp> <gate_date> — is the store inside the window?
#
# Compared as INTEGERS (YYYYMMDD), never as strings: `[ "$a" \> "$b" ]` is a
# LOCALE-COLLATED comparison, and this repo has already been bitten by locale on
# tr/cut. The date halves are sliced with bash parameter expansion rather than
# tr/cut for the same reason.
#
# Same-day counts. gates.* carry a DATE with no time, so a store on the gate's
# own date cannot be ordered against it — rejecting it would be a coin flip
# dressed up as a rule.
_ACCUM_STORE_FUTURE=0
_cpg_accum_after() {
  local ts="$1" gate="$2" a b today_utc
  if [ -z "$ts" ]; then return 1; fi
  a="${ts:0:10}";   a="${a//-/}"

  # THE OTHER OPERAND OF THE SAME COMPARISON. Rounds 10-11 validated the window
  # START four ways and left the STORE TIMESTAMP unguarded — on the identical
  # hazard those guards cite. `_cpg_accum_window_measurable` justifies itself by
  # clock skew, and residual 19 says in as many words that a machine which is
  # ahead writes the gate date AND the store timestamp in the future. Only one
  # of the two was checked.
  #
  # It is the WORSE half to leave open. A future window start fails LOUDLY (the
  # gate refuses and names it); a future store timestamp satisfies the gate
  # SILENTLY and PERMANENTLY — measured, `9999-12-31` and `2099-01-01` both take
  # a blocking fixture from 11 issues to 10 — and `.claude/process-state.json`
  # is tracked (residual 17), so the bad value is committed and reaches every
  # clone.
  #
  # THE COMPARISON IS UTC-TO-UTC and that is what makes it exact rather than
  # slack-tolerant: the tracker writes this field with `date -u`
  # (`TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)`), so a correct clock can never
  # produce a value after `date -u` now, and no timezone allowance is needed.
  # Comparing against a LOCAL today would have needed a day of slack and would
  # have been a second thing to get wrong. A `date` that will not answer reads
  # as NOT satisfied — the fail-closed direction, consistent with the window.
  case "$a" in ''|*[!0-9]*) return 1 ;; esac
  today_utc=$(date -u +%Y%m%d 2>/dev/null) || today_utc=""
  case "$today_utc" in ''|*[!0-9]*) return 1 ;; esac
  if [ "$a" -gt "$today_utc" ]; then _ACCUM_STORE_FUTURE=1; return 1; fi   # BL-233-WPB-STORE-FUTURE

  if [ -z "$gate" ]; then return 0; fi
  b="${gate:0:10}"; b="${b//-/}"
  # $b needs no guard: it is get_gate_date output, regex-validated to YYYY-MM-DD
  # or "" by that function, and "" returned above. $a is guarded ABOVE, before
  # the future check that needs it numeric.
  [ "$a" -ge "$b" ]
}

# _cpg_accum_window_measurable <window_start> <window_key> <raw_window_value>
#   — can this window be measured at all?
#
# `git log --since=<date>` with a date in the FUTURE returns zero commits and
# exits 0. Git ANSWERED, so none of the three cannot-tell arms in
# _cpg_accum_source_work fire; the empty payload then matches `^$` in the exempt
# set and the gate announces "nothing owed — every change since 2099-12-31 was
# documentation". That is a false affirmative about the project — the same
# substitution the extension allow-list was rewritten to remove — arrived at by
# a different route, and it is a silent OFF SWITCH for a blocking gate. Refusing
# a silent off switch is the whole reason `## BL-233:` declined to read the
# requirement from the ledger; one reached through gates.* is no better.
#
# NOT hypothetical, and not only tampering. `_cpg_record_gate_date` PRESERVES a
# date already recorded (its idempotent branch), so a date written by a machine
# whose clock or timezone is ahead of the one running the gate is in the future
# THERE and nowhere else — `## BL-234:`'s silent local-vs-CI class, which this
# feature has now been bitten by twice.
#
# Answering "measurable" rather than "future" is deliberate: the caller must
# block on ANY reason the window cannot be read, not on one named reason. A
# `date` that will not answer therefore reads as NOT measurable — "could not
# measure" must never resolve to "nothing to measure".
#
# THE WINDOW START IS VALIDATED HERE, and the earlier version of this paragraph
# argued the opposite — that get_gate_date's anchoring made a guard an arm that
# could not fire (`## BL-104:`). That was refuted by this same file: that
# anchoring is a PER-LINE `grep -qE`, so a duplicate key passes it. The guard is
# `# BL-233-WPB-WINDOW-SHAPE`, it fires, and M23 kills the tree without it.
_ACCUM_WINDOW_REASON=""
_cpg_accum_window_measurable() {
  local w="$1" key="$2" raw="$3" a today _nan
  _ACCUM_WINDOW_REASON=""

  # AN EMPTY WINDOW START IS AMBIGUOUS, and reading it as "no gate recorded" was
  # a SECOND silent off switch through the same field. `get_gate_date` maps BOTH
  # "no gate recorded" AND "a gate is recorded whose value will not parse" to "",
  # and "" then reaches _cpg_accum_after, whose `[ -z "$gate" ] && return 0`
  # makes ANY store ever recorded satisfy the gate. Measured: one edit of
  # gates.* to `not-a-date` took a blocking fixture from 9 inconsistencies to 8,
  # landing on the no-requirement control, with a 2020 store reported as
  # satisfying. Same shape as the future window, no clock skew required.
  if [ -z "$w" ]; then
    # AN UNREADABLE STATE FILE IS NOT AN ABSENT GATE. The snapshot below reads
    # gates.* through jq, and jq's failure was swallowed to "" — which is the
    # very signal this arm keys on. Measured: one stray `,,,` in
    # phase-state.json alongside `"phase_1_to_2":"not-a-date"` produced
    # `[OK] accumulation: satisfied` off a 2020 store on a 2026 phase, with the
    # corruption surfacing only as a NON-COUNTING [WARN] elsewhere in the run,
    # so on an otherwise-consistent project nothing saved the gate. `gates` not
    # being an object does the same thing.
    if [ "${_ACCUM_GATES_READABLE:-1}" != "1" ]; then
      _ACCUM_WINDOW_REASON=".claude/phase-state.json does not parse (or its .gates is not an object), so \"no gate recorded\" and \"a gate recorded as garbage\" cannot be told apart"
      return 1
    fi
    # NON-EMPTY IS NOT ENOUGH — the raw value must also FAIL the date regex, or
    # every project with a perfectly good gate date is refused. That was the
    # first cut of this arm and it refused three fixtures out of four.
    #
    # $raw is a SNAPSHOT taken at the same instant as $w and BEFORE any check
    # ran, not a fresh read (`# BL-233-WPB-RAW-SNAPSHOT`). Re-reading the file
    # here is what the second cut did, and it measured a different file:
    # `_cpg_record_gate_date` rewrites gates.* from APPROVAL_LOG evidence DURING
    # the run, so `not-a-date` had already normalised to today's date by the
    # time this line saw it — the arm reported "parses fine", and the fail-open
    # it was written to close stayed open while the test for it went green.
    if [ -n "$raw" ] && ! grep -qE '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$' <<< "$raw"; then   # BL-233-WPB-AMBIGUOUS-WINDOW
      _ACCUM_WINDOW_REASON="a gate date IS recorded for $key and does not parse as YYYY-MM-DD (\"$raw\")"
      return 1
    fi
    return 0   # genuinely no gate recorded: the window is the whole history
  fi

  # THE WHOLE STRING IS VALIDATED, NOT ITS FIRST TEN CHARACTERS, and the
  # difference is a live fail-open. `get_gate_date` validates with a PER-LINE
  # `grep -qE`, so a DUPLICATE key in phase-state.json (which jq accepts, so the
  # file is not malformed) yields a multi-line value that passes if ANY line is a
  # date; accum_oneline then concatenates the lines.
  #
  # The first guard here sliced `${w:0:10}` and asked only whether that reduced
  # to a number. With the GARBAGE first — `ZZZZZZZZZZ2026-02-01` — that catches
  # it. With the DATE first it does not, and the full concatenation is what
  # reaches `git log --since`, where approxidate reads it as some other instant
  # entirely. Measured: `--since="2026-02-01 2099-12-31 00:00:00"` resolves to
  # --max-age=4102383600 (2099-12-31) and `--since="2026-02-012099-12-31 …"` to
  # 1798696800 (2026-12-31) — both FUTURE, both producing verbatim the
  # "nothing owed" verdict `# BL-233-WPB-FUTURE-WINDOW` exists to remove, at the
  # same 9 -> 8 issue delta. A guard that catches one operand order is not a
  # guard on the value.
  #
  # Anchored and whole, therefore: after this line $w IS a single YYYY-MM-DD, so
  # the slice below cannot be non-numeric and `git log --since` cannot be handed
  # anything approxidate can reinterpret.
  _nan="the recorded gate date is not a single YYYY-MM-DD value (\"${w:0:40}\") — a duplicate key in .claude/phase-state.json yields a multi-line value that per-line validation accepts, and git reads the concatenation as some other instant"
  # THE LINE COUNT IS PART OF THE CHECK. `grep` matches PER LINE, so an anchored
  # pattern alone passes any multi-line value whose FIRST line is a date — the
  # same per-line hole in `get_gate_date` that created this defect, reproduced
  # inside the guard for it. It happens to be unreachable in the shipped tree
  # because accum_oneline flattens $prev at ingest, and that is exactly the
  # reason to close it: a guard that is only correct because something upstream
  # is correct is not a guard, and D15 drives a tree where the upstream strip is
  # gone.
  if [ "$(grep -c . <<< "$w")" != "1" ] || ! grep -qE '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$' <<< "$w"; then _ACCUM_WINDOW_REASON="$_nan"; return 1; fi   # BL-233-WPB-WINDOW-SHAPE
  a="${w:0:10}"; a="${a//-/}"

  today=$(date +%Y%m%d 2>/dev/null) || today=""
  case "$today" in
    ''|*[!0-9]*)
      _ACCUM_WINDOW_REASON="the system date could not be read, so no window can be placed in time"
      return 1 ;;
  esac

  [ "$a" -le "$today" ] && return 0   # BL-233-WPB-FUTURE-WINDOW
  _ACCUM_WINDOW_REASON="it opens at $w, which is not in the past, so no commit and no store can fall inside it"
  return 1
}

# _cpg_accum_source_work <since_date> — did this phase produce SOURCE commits?
#
# Ground truth from git, NOT from a hook-maintained counter. `## BL-239:` — this
# week — shipped a contributor hook that was a silent no-op on every commit
# anyone ever made, and a blocking gate that trusts a skippable counter inherits
# that failure mode wholesale.
#
# Returns 0 (source work happened) when it CANNOT TELL: no git, not a repo, or a
# log that will not read. "Could not measure" must never resolve to "nothing to
# measure" — `# BL-112-SAST-NOTRUN`'s doctrine, and here also the fail-closed
# direction.
#
# The matches use HERE-STRINGS, not `printf | grep -q`. Under `set -o pipefail`
# that pipeline returns 141 ON A MATCH once the payload is big enough: grep -q
# exits the instant it matches, the writer takes SIGPIPE, and pipefail promotes
# that death over grep's success (`## BL-238:`). Here a spurious 141 would read
# as "no source work" — the fail-OPEN direction — on exactly the large-history
# repos where the check matters most.
_cpg_accum_source_work() {
  local since="$1" paths
  if ! command -v git >/dev/null 2>&1; then return 0; fi
  if ! git rev-parse --git-dir >/dev/null 2>&1; then return 0; fi
  # `00:00:00` IS LOAD-BEARING, and its absence was a fail-open found by a test
  # of this feature going intermittently green. git's approxidate fills the
  # fields a date string omits FROM THE CURRENT CLOCK, so a bare `--since=<date>`
  # means "that date at the time of day it happens to be right now", not
  # midnight. Measured on git 2.x: a commit made at 10:35:18 today is INVISIBLE
  # to `--since=<today>` two seconds later, and visible to
  # `--since=<today> 00:00:00`.
  #
  # Consequence without it: every source commit made earlier in the day on the
  # window's opening date is silently outside the window, so a phase whose
  # previous gate was recorded today reports "nothing owed" all afternoon — and
  # the SAME TREE yields a different verdict depending on the hour the gate runs,
  # which is `## BL-234:`'s class wearing a clock instead of a hostname.
  if [ -n "$since" ]; then
    paths=$(git log --since="$since 00:00:00" --name-only --pretty=format: 2>/dev/null) || return 0   # BL-233-WPB-SINCE-MIDNIGHT
  else
    paths=$(git log --name-only --pretty=format: 2>/dev/null) || return 0
  fi
  # SOURCE IS DEFINED BY NEGATION, matching this repo's own docs-only classifier
  # (process-checklist.sh's `\.(md|json|yml|yaml|toml|tmpl)$` plus _is_dep_manifest).
  # The first cut used an extension ALLOW-LIST lifted from pre-commit-gate.sh's
  # HAS_SOURCE check — ~14 extensions — and a Ruby, PHP, shell, Vue, Elixir, SQL
  # or Scala project therefore sailed through this gate AND was told
  # "no source commits since <date>", an affirmative claim about the project
  # that was false. That is the same substitution the jq arm above was rewritten
  # to avoid. In its original home the allow-list only gated a WARNING; reusing
  # it in a BLOCKING position is what made the gap consequential.
  #
  # Over-eager is the correct direction here: a commit touching only .gitignore
  # now counts as source work, which asks for a memory store that may not be
  # owed. Under-eager silently voids the gate, which is the defect being fixed.
  #
  # The `^$` alternative is load-bearing: `git log --name-only --pretty=format:`
  # emits a BLANK LINE between commits, and a blank line matches no extension —
  # without excluding it, every window would look like source work.
  if accum_paths_have_source "$paths"; then
    return 0
  fi
  return 1   # BL-233-WPB-SOURCEWORK
}

# _cpg_accum_source_since <sha> — source work committed after <sha>?
# Same classifier as _cpg_accum_source_work, over a commit RANGE instead of a
# date. Returns 0 = "the attestation no longer covers the tree" (stale),
# 1 = still covers it.
#
# THE PARAGRAPH THAT USED TO OPEN THIS BLOCK IS DELETED, NOT AMENDED. It said
# this function "returns 1 (no source work) when it CANNOT tell, and that
# permissive direction is correct ONLY here" — the pre-inversion behaviour,
# left in place when the inversion landed (backlog residual 5,
# `# BL-233-WPB-STALE-FAILCLOSED`), directly contradicted by the next paragraph.
# A reader who stopped at the first one would believe the permanent bypass was
# still by design.
#
# IT FAILS CLOSED, and it says why. The first version returned 1 (still valid)
# for an empty, malformed, tampered or garbage-collected `head` — so ANY
# unresolvable value silently restored the permanent bypass this check was added
# to remove, reachable by editing one JSON field OR by an ordinary
# `git gc --prune=now`. Its twin `_cpg_accum_source_work`, written in the same
# commit, fails CLOSED on the identical question and cites
# `# BL-112-SAST-NOTRUN` for doing so: "could not measure" must never resolve to
# "nothing to measure". This one now agrees with it.
#
# The one genuinely permissive arm is "no git at all": there is no history to
# compare against, so staleness is not a question that can be asked.
_ACCUM_STALE_REASON=""
_cpg_accum_source_since() {
  local sha paths
  # SANITISE AT THE BOUNDARY, not at each display site. $1 is `recorded_head`,
  # read by jq out of .claude/process-state.json — identical provenance to the
  # values that forged verdict lines twice already — and it is interpolated into
  # _ACCUM_STALE_REASON, which is rendered by the caller. Wrapping every display
  # site is how the sixth and seventh instances of this class got in: the sweep
  # each round described the PREVIOUS round's syntax (first `reason|recorded|
  # attest` keywords, then `echo -e`), and was blind to the surface the fix had
  # just created. Cleaning the value where it ENTERS makes the display sites
  # irrelevant, which is the only version of this that stays true.
  # RAW for git, CLEANED only where it is displayed. Sanitising this at ingest
  # was wrong in a way no test caught: `HE\001AD` is an INVALID ref that becomes
  # the VALID ref `HEAD` once C0 bytes are stripped, so a tampered attestation
  # resolved instead of failing and the arm's verdict flipped FAIL -> OK — the
  # exact fail-closed posture this function's own header promises. A display
  # filter must not decide whether a commit exists.
  sha="$1"   # BL-233-WPB-SHA-RAW-FOR-GIT
  _ACCUM_STALE_REASON="source work has landed since the attested commit"
  if ! command -v git >/dev/null 2>&1; then return 1; fi
  if ! git rev-parse --git-dir >/dev/null 2>&1; then return 1; fi
  # In a repo, an unresolvable commit means the record cannot be trusted.
  # The two causes are reported SEPARATELY. An earlier rewrite merged them into
  # one sentence and the operator could no longer tell whether the recorded
  # commit had vanished (history rewritten, gc'd, record tampered) or whether
  # work had simply landed after it — which are different problems with
  # different remedies.
  if [ -z "$sha" ]; then
    _ACCUM_STALE_REASON="no commit was recorded with it"
    return 0   # BL-233-WPB-STALE-FAILCLOSED
  fi
  if ! git cat-file -e "${sha}^{commit}" 2>/dev/null; then
    _ACCUM_STALE_REASON="the commit it named ($(accum_oneline "$sha")) is not reachable in this repository"
    return 0
  fi
  paths=$(git log "${sha}..HEAD" --name-only --pretty=format: 2>/dev/null) || {
    _ACCUM_STALE_REASON="the history since $(accum_oneline "$sha") could not be read"
    return 0
  }
  _ACCUM_STALE_REASON="source work has landed since $(accum_oneline "$sha")"
  if accum_paths_have_source "$paths"; then
    return 0
  fi
  return 1
}

# _cpg_record_accum_attestation <gate_key> <reason>
#   0 — recorded (or idempotent no-op: already recorded with the same reason)
#   2 — could not write (jq unavailable, lock timeout, unwritable state, jq error)
# Same atomic-finalize shape as _cpg_record_gate_date, and the same lock as
# _cpg_record_reviewer_attestation — which is the ONE other locked writer of
# .claude/process-state.json. (_cpg_record_gate_date writes phase-state.json
# under its own lock; an earlier draft of this comment claimed all three shared
# a lock, which was false.) Note that pre-commit-gate.sh's tdd_record_attestation
# and check-gate.sh's protection repair both read-modify-write this same file
# WITHOUT a lock, so exclusion here is partial; a lost update drops
# last_store_at, which blocks rather than passes.
_cpg_record_accum_attestation() {
  local gate_key="$1" reason="$2"
  local file=".claude/process-state.json"
  local today actor lock_dir attempts rc cur cur_head _att_head

  if ! command -v jq >/dev/null 2>&1; then return 2; fi

  # The commit this attestation EXCUSES. An escape that never expires is a
  # permanent bypass: without it one attested run would excuse every future
  # source commit in the phase. BL-072's TDD attestation is scoped per commit
  # and session-mcp-gate.sh's must be re-exported per session; this is the
  # phase-gate equivalent. Computed BEFORE the idempotence check, which reads it.
  _att_head=$(git rev-parse HEAD 2>/dev/null || printf '')

  # IDEMPOTENCE IS NOW HEAD-SENSITIVE. This early return once compared the reason
  # alone, which was safe while the record held only {reason,date,by}. Adding
  # `head` made the record COMMIT-DEPENDENT, and the unchanged early return then
  # made re-attesting with the same reason a NO-OP: the stale warning fired, the
  # operator did exactly what it advised, `head` was never refreshed, and the
  # next run blocked again. Escaping required inventing a NEW reason string —
  # an incentive to write junk reasons, which is the shape `## BL-149:` deletes.
  # An unparseable record is refused HERE, with the reason named. Reaching this
  # function with a corrupt file already failed closed — the jq write below
  # errors and the caller refuses — but the message then said only "could not be
  # recorded", which does not tell the operator that the file itself is the
  # problem. Closing the sweep's last real hit.
  if [ -f "$file" ] && ! _accum_json_ok "$file"; then
    return 2
  fi
  if [ -f "$file" ]; then
    cur=$(jq -r --arg g "$gate_key" '.mcp_accumulation.attestations[$g].reason // ""' "$file" 2>/dev/null || printf '')
    cur_head=$(jq -r --arg g "$gate_key" '.mcp_accumulation.attestations[$g].head // ""' "$file" 2>/dev/null || printf '')
    if [ "$cur" = "$reason" ] && [ -n "$cur_head" ] && [ "$cur_head" = "$_att_head" ]; then
      return 0   # BL-233-WPB-ATTEST-IDEMPOTENT
    fi
  fi

  today=$(date +%Y-%m-%d)
  actor=$(_cpg_gate_actor)
  lock_dir="$file.lockdir"
  attempts=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 100 ]; then return 2; fi
    sleep 0.1
  done

  # Created INSIDE the lock. The tracker's writer already did this; this one
  # created it outside, so a concurrent writer could observe a half-built file.
  if [ ! -f "$file" ]; then
    echo '{}' > "$file" 2>/dev/null || { rmdir "$lock_dir" 2>/dev/null; return 2; }
  fi

  rc=0
  (
    tmp=$(mktemp "${file}.XXXXXX") || exit 1
    trap 'rm -f "$tmp"; rmdir "$lock_dir" 2>/dev/null' EXIT INT TERM
    if jq --arg g "$gate_key" --arg reason "$reason" --arg date "$today" --arg by "$actor" --arg head "$_att_head" \
          '.mcp_accumulation = ((.mcp_accumulation // {})
             | .attestations = ((.attestations // {}) + {($g): {reason: $reason, date: $date, by: $by, head: $head}}))' \
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
  if [ "$rc" -ne 0 ]; then return 2; fi
  return 0
}

# _cpg_check_accumulation <gate_key> <prev_gate_date> <label>
#   0 — satisfied, nothing owed, attested, or not applicable
#   1 — BLOCK
#
# This function emits the LABEL and returns the VERDICT together, and
# _cpg_accum_gate below is the single increment site. `## BL-104:`'s trap is
# that the [WARN]/[FAIL] text is cosmetic while the exit predicate is
# `if [ $issues -eq 0 ]`, so two arms printing the same word can have opposite
# outcomes. Here the label and the increment cannot drift apart, because nothing
# outside this pair decides either one.
_cpg_check_accumulation() {
  local gate_key="$1" prev label="$3"
  # Same boundary rule. `get_gate_date` extracts with `grep -o` and validates
  # with an ANCHORED `grep -qE` — and grep matches PER LINE, so a duplicate
  # `"phase_1_to_2"` key in phase-state.json yields a multi-line value whose
  # FIRST line is a valid date and which therefore passes validation. jq accepts
  # duplicate keys, so the file is not even malformed. That predates this work,
  # but three display sites here interpolate $prev, so it is cleaned on the way in.
  prev=$(accum_oneline "$2")   # BL-233-WPB-PREV-ONELINE
  local last reason recorded recorded_head _accum_bad _accum_window_bad
  local _accum_state

  # FAIL CLOSED on a missing jq, rather than reporting a project fact that was
  # never read. This is the `degradation` row of `## BL-233:`'s own table —
  # "absent must fail closed, not exit 0" — and it follows this file's existing
  # precedent: the Phase 3→4 review gate already degrades to a BLOCKING warn
  # when the manifest is present but jq is not, rather than silently passing.
  if [ "$SOIF_ACCUM_LIB_LOADED" != "1" ]; then
    echo -e "${BLUE}  [NOTE]${NC} $label accumulation: NOT CHECKED — scripts/lib/accumulation.sh is absent, so this project predates the accumulation gate or its install is incomplete. Not counted against the gate."
    echo "        Enable it: bash scripts/upgrade-project.sh --sync-framework"
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo -e "${RED}[FAIL]${NC} $label accumulation: CANNOT BE VERIFIED — jq is unavailable, so neither the requirement nor the durable record can be read."
    echo "        Install jq. Passing silently here would be the substitution this gate exists to remove: \"could not check\" is not \"nothing to check\"."
    return 1   # BL-233-WPB-JQ-FAILCLOSED
  fi

  # ANNOUNCED BEFORE the requirement is resolved, because the `none` arm returns
  # early — and `none` is exactly the verdict a corrupt ledger produces for a
  # project whose only declaration lived there. Placing this after the resolution
  # meant it never printed in the one case it exists for.
  if [ -f ".claude/tool-usage.json" ] && ! accum_json_readable ".claude/tool-usage.json"; then
    echo -e "${YELLOW}[WARN]${NC} $label accumulation: .claude/tool-usage.json does not parse and was skipped. It is session scratch that SessionStart rewrites, so it does not block — but if it carried this project's only Qdrant declaration, the requirement is not being seen."   # BL-233-WPB-LEDGER-SKIPPED
  fi

  _accum_state=$(accum_requirement_state)
  if [ "$_accum_state" = "none" ]; then
    # [NOTE], deliberately NOT [NEXT]. In this file [NEXT] means "belongs to a
    # later gate and is not counted against this one", and
    # tests/test-bl166-gate-scope.sh asserts it appears ONLY as the 3→4 scoping
    # line — a bare run or `--gate phase_3_to_4` emitting any other [NEXT] is a
    # BL-166 regression. This line means something different: the check did not
    # apply here.
    echo -e "${BLUE}  [NOTE]${NC} $label accumulation: NOT CHECKED — this project declares no Qdrant MCP server that git tracks (.claude/manifest.json has no .mcp.qdrant_required, and no tracked .claude/settings*.json names mcpServers.qdrant). Nothing is owed here, and nothing was verified."
    echo "        If this project DOES use Qdrant, record it where a clone can see it:"
    echo "          jq '.mcp.qdrant_required = true' .claude/manifest.json"
    return 0
  fi
  if [ "$_accum_state" = "unreadable" ]; then
    # FAIL CLOSED. A declaration that will not parse has been read by nobody, so
    # reporting "this project declares no Qdrant MCP server" would assert a fact
    # about content nothing examined.
    # NAME THE FILE. The first version listed the two files it might have been,
    # and an operator whose ledger was corrupt was sent to inspect a manifest and
    # a settings file that were both healthy — which makes "fixing the JSON is
    # the honest escape" untrue, since it does not say which JSON.
    _accum_bad=$(accum_unreadable_path)
    printf '%b[FAIL]%b %s accumulation: CANNOT BE VERIFIED — a declaration file exists but is not valid JSON: ' "${RED}" "${NC}" "$label"
    printf '%s' "$(accum_oneline "${_accum_bad:-<unknown>}")"
    printf '\n        Fix that file, then re-run. Passing silently here would report a project fact that was never parsed.\n'
    return 1   # BL-233-WPB-UNREADABLE-FAILCLOSED
  fi

  if [ "$_accum_state" = "untracked" ]; then
    # Enforce, but say plainly that the enforcement is local-only. Blocking here
    # would fail every project that predates the manifest field; staying silent
    # would repeat the defect. The operator is told exactly how to make it
    # survive a clone.
    echo -e "${YELLOW}[WARN]${NC} $label accumulation: the Qdrant requirement is declared ONLY in a file git does not track (.claude/settings.local.json is in Claude Code's global excludes; .claude/tool-usage.json is in the generated .gitignore). Enforcing it HERE, but a fresh clone or CI runner will not see it."
    echo "        Make it durable: jq '.mcp.qdrant_required = true' .claude/manifest.json   (and commit it)"
  fi

  # THE WINDOW MUST BE MEASURABLE BEFORE EITHER QUESTION ABOUT IT MEANS ANYTHING,
  # so this precedes both "was anything stored in it" and "was source work done
  # in it". An unmeasurable window answers BOTH with a confident falsehood.
  #
  # A CONSEQUENCE THIS PLACEMENT OWNS, stated rather than discovered later: a
  # project that HAS stored, but whose window is unmeasurable, now blocks where
  # it previously read `[OK] satisfied`, and the attested escape below is not
  # reached either. That is deliberate — an attestation excuses "nothing was
  # stored", not "the gate does not know what it is measuring" — and the remedy
  # is in the message: the recorded date is the thing that is wrong. Note the
  # earlier draft of this comment justified the placement with "nothing can be
  # stored after it", which is FALSE in the clock-skew case it cites as
  # motivation: a machine that is ahead writes both the gate date AND the store
  # timestamp in the future. The placement is right; that argument for it was
  # not. Recorded as residual 19.
  #
  # THE REASON IS CARRIED, NOT ASSUMED. The first version hard-coded ", which is
  # not in the past" into this line — and that is false on EVERY path that
  # reaches it except one: an unreadable state file, a gate date recorded as
  # garbage, a window that is not a single YYYY-MM-DD, and a `date` that will not
  # answer all block on a window that may well be in the past. An arm added to
  # remove a false affirmative about the project was printing one of its own, and
  # an earlier draft of this very comment then MIScounted the paths as "two of
  # four". The count is not restated here on purpose: the paths are enumerated in
  # `_cpg_accum_window_measurable` and a number here is a second place to be
  # wrong. `_ACCUM_STALE_REASON` is the precedent for carrying it.
  # THE KEY THE WINDOW OPENS AT IS THE PREVIOUS GATE, NOT THIS ONE. Passing
  # $gate_key read phase_2_to_3's value while checking phase_2_to_3, so a
  # tampered phase_1_to_2 was reported by quoting an untouched, valid date — and
  # a legitimately NULL previous gate was refused because the SUCCESSOR was set.
  # Caught by driving all four shapes; it would have shipped as a message that
  # named the wrong field and a gate that blocked correct projects.
  local _accum_prev_key=""
  case "$gate_key" in
    phase_1_to_2) _accum_prev_key="phase_0_to_1" ;;
    phase_2_to_3) _accum_prev_key="phase_1_to_2" ;;
    phase_3_to_4) _accum_prev_key="phase_2_to_3" ;;
  esac
  # IT SETS A FLAG, IT DOES NOT RETURN. An earlier version returned 1 right here,
  # which put the block AHEAD of the attested escape and therefore made the
  # escape unreachable for it. That is `## BL-149:`'s rule violated by the very
  # entry that cites it: a gate an honest operator cannot satisfy is a gate they
  # delete. A wrong clock or a half-written state file is not misconduct, and
  # the operator staring at "your gate date is unreadable" must be able to say
  # so and move on — the attestation is still RECORDED, so nothing is silenced.
  #
  # What the flag buys is the part that mattered: the two PERMISSIVE shortcuts
  # below (a store "inside" the window, and "nothing owed") are skipped, because
  # those are the questions an unmeasurable window answers with a confident
  # falsehood. Fail-closed on the automatic paths, open to a human on the
  # attested one.
  _accum_window_bad=0
  if ! _cpg_accum_window_measurable "$prev" "$_accum_prev_key" "$4"; then
    _accum_window_bad=1   # BL-233-WPB-WINDOW-ATTESTABLE
  fi

  last=$(_cpg_accum_last_store)
  if [ "$_accum_window_bad" -eq 0 ] && _cpg_accum_after "$last" "$prev"; then
    # printf for $last: it is a PERSISTED value (jq out of process-state.json),
    # so `echo -e` renders \n in it as real newlines and a stored timestamp can
    # forge "[OK] …" verdict lines on every run. Found on the SIXTH recurrence of
    # this class, three lines from the arm fixed for it — because the sweep that
    # was supposed to close the class grepped for the WORDS `reason|recorded|
    # attest`, which is an instance search wearing a sweep's clothes. $last
    # carries none of those words.
    #
    # THE SWEEP THAT FINDS THIS ONE IS BY PROVENANCE, NOT KEYWORD: every `echo -e`
    # whose argument interpolates a value that came out of jq, a file, or the
    # environment. Under that rule the feature has exactly two ($last here,
    # ACC_PREV in pre-commit-gate.sh) and both are fixed; $label is a code
    # constant and $prev is regex-validated by get_gate_date.
    printf '%b  [OK]%b %s accumulation: satisfied — last successful qdrant-store ' "${GREEN}" "${NC}" "$label"
    printf '%s' "$(accum_oneline "$last")"
    printf ' (window opens %s).\n' "${prev:-project start}"
    return 0
  fi

  if [ "$_accum_window_bad" -eq 0 ] && ! _cpg_accum_source_work "$prev"; then
    printf '%b  [OK]%b %s accumulation: nothing owed — every change since ' "${GREEN}" "${NC}" "$label"
    printf '%s' "${prev:-project start}"
    printf ' was documentation, config or a dependency manifest.\n'
    return 0
  fi

  # Escape hatch in BL-072's shape: attested, durably recorded, and REFUSED if
  # it cannot be recorded. An escape that leaves no trace is the advisory
  # posture `## BL-233:` exists to replace.
  reason=""
  if [ -f ".claude/process-state.json" ] && command -v jq >/dev/null 2>&1 \
     && _accum_json_ok ".claude/process-state.json"; then
    # `// ""` already collapses null, so no "null" guard follows — it could not fire.
    recorded=$(jq -r --arg g "$gate_key" '.mcp_accumulation.attestations[$g].reason // ""' ".claude/process-state.json" 2>/dev/null || printf '')
    recorded_head=$(jq -r --arg g "$gate_key" '.mcp_accumulation.attestations[$g].head // ""' ".claude/process-state.json" 2>/dev/null || printf '')
    # An attestation excuses the work it was written for, NOT everything that
    # follows it. If source work landed after the commit it named, it is STALE:
    # the operator attests again, or stores something. Without this one attested
    # run permanently disabled the boundary for the rest of the phase.
    if [ -n "$recorded" ] && _cpg_accum_source_since "$recorded_head"; then
      # printf for the REASON, same as the ATTESTED line below. This one is the
      # MORE exploitable of the two: that one needs the env var on the current
      # invocation, this renders from the PERSISTED record on every subsequent
      # run, through the fully supported workflow. Found by sweeping the class
      # (`grep -n 'echo -e .*\$' | grep -iE 'reason|recorded|attest'`) after
      # fixing only the named instance — which is the recurring failure here.
      printf '%b[WARN]%b %s accumulation: the attestation on record ("' "${YELLOW}" "${NC}" "$label"
      printf '%s' "$(accum_oneline "$recorded")"
      printf '") no longer covers this tree — %s. Re-attest, or store what changed.\n' "${_ACCUM_STALE_REASON}"   # BL-233-WPB-ATTEST-STALE
      recorded=""
    fi
    reason="$recorded"
  fi
  if [ "${SOLO_MCP_ACCUM_ATTESTED:-}" = "1" ] && [ -n "${SOLO_MCP_ACCUM_ATTESTED_REASON:-}" ]; then
    reason="$SOLO_MCP_ACCUM_ATTESTED_REASON"
  fi
  # Trim BEFORE the non-empty test so a whitespace-only reason is REJECTED —
  # an attestation must carry a justification, not blank space (BL-070's
  # tightener, mirrored).
  reason=$(printf '%s' "$reason" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  if [ -n "$reason" ]; then
    if _cpg_record_accum_attestation "$gate_key" "$reason"; then
      # printf %s for the REASON, not echo -e. The reason is operator-supplied,
      # and `echo -e` interprets \n in it — so an attestation reason could forge
      # additional "[OK] …" lines into the gate transcript a human or a CI log
      # skims. The durable record was never at risk (jq --arg stores it
      # literally); the transcript was.
      printf '%b  [OK]%b %s accumulation: ATTESTED (reason: ' "${GREEN}" "${NC}" "$label"
      printf '%s' "$(accum_oneline "$reason")"
      printf ') — recorded to .claude/process-state.json, not silenced.\n'
      return 0
    fi
    echo -e "${RED}[FAIL]${NC} $label accumulation: an attestation was supplied but COULD NOT BE RECORDED to .claude/process-state.json — refusing it."
    echo "        An escape that leaves no trace is not an escape. Make the state file writable (and install jq), then re-run."
    return 1   # BL-233-WPB-ATTEST-REFUSE
  fi

  if [ "$_accum_window_bad" -eq 1 ]; then
    printf '%b[FAIL]%b %s accumulation: CANNOT BE VERIFIED — the window cannot be measured: ' "${RED}" "${NC}" "$label"
    printf '%s' "$(accum_oneline "${_ACCUM_WINDOW_REASON}")"
    printf '.\n'
    echo "        Nothing is being claimed about this project: a window that cannot be measured is not an empty one."
    echo "        Fix gates.${_accum_prev_key:-$gate_key} in .claude/phase-state.json, or check the clock on the machine that recorded it."
    echo "        If the date is wrong and the work IS stored, say so — it is recorded, not silenced:"
    echo "          SOLO_MCP_ACCUM_ATTESTED=1 SOLO_MCP_ACCUM_ATTESTED_REASON=\"<why the window is unreadable>\" bash scripts/check-phase-gate.sh"
    return 1
  fi

  if _cpg_accum_record_unreadable; then
    # Say which cause. Without this the operator is told to store or attest when
    # the real problem is a corrupt record — and any attestation already on
    # record has been silently discarded, so the advice names the wrong thing.
    echo -e "${RED}[FAIL]${NC} $label accumulation: BLOCKED — .claude/process-state.json exists but is not valid JSON, so neither a store nor an attestation could be read from it. Fix that file first; re-storing or re-attesting will not help until it parses."
    return 1
  fi
  printf '%b[FAIL]%b %s accumulation: BLOCKED — source commits since ' "${RED}" "${NC}" "$label"
  printf '%s' "${prev:-project start}"
  printf ', and NO successful qdrant-store in that window.\n'
  if [ "${_ACCUM_STORE_FUTURE:-0}" = "1" ]; then
    # Name the real cause. Without this the operator is told to store again when
    # the record already HAS a store — one whose timestamp is in the future, and
    # re-storing will not help while the clock that wrote it is wrong.
    echo "        NOTE: .claude/process-state.json records a store dated in the FUTURE (UTC), so it cannot be counted."
    echo "        The clock on the machine that wrote it is ahead. Fix the clock and store again, or attest."
  fi
  echo "        A retrieval requirement with no accumulation requirement is a ratchet with nothing behind it (## BL-233:)."
  echo "        Store what this phase decided (qdrant-store), then re-run — or attest:"
  echo "          SOLO_MCP_ACCUM_ATTESTED=1 SOLO_MCP_ACCUM_ATTESTED_REASON=\"<why nothing was worth storing>\" bash scripts/check-phase-gate.sh"
  return 1
}

# The ONE increment site for the accumulation gate.
_cpg_accum_gate() {
  _cpg_check_accumulation "$1" "$2" "$3" "$4" || issues=$((issues + 1))   # BL-233-WPB-BLOCK
}

# _cpg_raw_gate_value <gate_key> — the gates.* value EXACTLY AS RECORDED.
# get_gate_date maps BOTH "absent" and "present but unparseable" to "", and the
# accumulation arm has to tell those apart: the first legitimately means "the
# window is the whole history", the second means the window cannot be measured.
_cpg_raw_gate_value() {
  local v=""
  if [ -f "$PHASE_STATE" ] && command -v jq >/dev/null 2>&1; then
    v=$(jq -r --arg k "$1" '.gates[$k] // ""' "$PHASE_STATE" 2>/dev/null || printf '')
    [ "$v" = "null" ] && v=""
  fi
  if [ "${SOIF_ACCUM_LIB_LOADED:-0}" = "1" ]; then
    # Boundary rule: sanitise where it ENTERS. NOT mutation-pinned, and that is
    # stated rather than hidden — removing it leaves the suite green because the
    # only display site sanitises again. It stays because the rule is "every
    # value that arrives from a file passes through accum_oneline where it
    # enters", and a rule with an exception is a search.
    v=$(accum_oneline "$v")
  fi
  printf '%s' "$v"
}

gate_0_to_1=$(get_gate_date "phase_0_to_1")
gate_1_to_2=$(get_gate_date "phase_1_to_2")
gate_2_to_3=$(get_gate_date "phase_2_to_3")
gate_3_to_4=$(get_gate_date "phase_3_to_4")
# Captured HERE, beside the validated values and before any check runs, because
# `_cpg_record_gate_date` rewrites gates.* mid-run from APPROVAL_LOG evidence.
# Whether gates.* could be READ AT ALL, captured with them. Without this a jq
# failure is indistinguishable from an absent gate, and "absent" is the
# permissive answer.
_ACCUM_GATES_READABLE=1
if [ -f "$PHASE_STATE" ] && command -v jq >/dev/null 2>&1; then
  if ! jq -e '(.gates // {}) | type == "object"' "$PHASE_STATE" >/dev/null 2>&1; then
    _ACCUM_GATES_READABLE=0   # BL-233-WPB-GATES-READABLE
  fi
fi
raw_gate_0_to_1=$(_cpg_raw_gate_value "phase_0_to_1")   # BL-233-WPB-RAW-SNAPSHOT
raw_gate_1_to_2=$(_cpg_raw_gate_value "phase_1_to_2")
raw_gate_2_to_3=$(_cpg_raw_gate_value "phase_2_to_3")

# Extract deployment type and track for conditional checks.
# BL-095: parsing goes through the # BL-095-STATE-READERS fence in
# lib/helpers-core.sh (sourced above) — one surface instead of per-site
# grep-sed variants. Per-site DEFAULTS stay here (policy, not parsing).
# NOTE (E/F verifier A1): the pre-BL-095 `|| echo` defaults here were DEAD
# (`||` bound to the last sed, which exits 0 on empty) — these defaults are
# now LIVE on null/absent/missing state. Every current consumer tests
# `= "organizational"` / `= "standard"` / `= "full"` only, so outcomes are
# unchanged; a future `[ "$deployment" = "personal" ]` or `[ -z … ]` consumer
# WILL see "personal"/"light" where the old code saw "".
deployment=$(soif_read_deployment "$PHASE_STATE" "personal")
track=$(soif_read_phase_state_key "$PHASE_STATE" "track" "light")
# BL-084 (verifier follow-up): poc_mode is the SECOND half of the tier key
# (with deployment) that decides push-escape bypass-eligibility below. It is
# NOT keyed on `track` — a sponsored/production project can carry track=light.
# `"poc_mode": null` (production / personal non-POC) maps to "" in the reader
# (correctly ≠ sponsored_poc — the null contract lives at the fence).
poc_mode=$(soif_read_poc_mode "$PHASE_STATE")

issues=0

echo -e "${BOLD}Phase Gate Consistency Check${NC}"
# BL-158-GATE-LABEL — under a --gate override the printed phase is FORCED
# ("as-if"), not the phase the project records; label it distinctly so an audit
# trail does not read the forced value as recorded current_phase. With NO --gate
# override the normal "Current phase: N" header is byte-for-byte unchanged.
if [ -n "$GATE_SCOPE" ]; then
  echo "Checking gate: $GATE_SCOPE (as-if phase $current_phase; recorded current_phase: $recorded_phase)"
else
  echo "Current phase: $current_phase"
fi
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
      # Check if section has content beyond template placeholders.
      # BL-114-F2-ERREXIT-GUARD: `|| true` is LOAD-BEARING. A placeholder-only
      # section filters down to NOTHING, the final `grep -v` exits 1, and
      # under `set -euo pipefail` the un-guarded assignment ABORTED the whole
      # gate BEFORE the placeholder WARN below ever printed — rc=1 with zero
      # diagnostic (walk F2: the WARN branch was unreachable code).
      local section_content
      section_content=$(sed -n "/^## ${section_num}\./,/^## [0-9]/p" "$file" | grep -v "^##" | grep -v "^---" | grep -v "^$" | grep -v "^<!--" | grep -v -e '-->$' | grep -v "^\[" | grep -v "^|.*|.*|$" | head -5) || true
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

# _cpg_warn_no_gate_section <gate_label>
# BL-144-NO-SECTION-MESSAGE: single source for the malformed-header refusal.
# TWO call sites emit it — the blame walker's own NO_SECTION arm (the PR #116
# / T-blame-4 contract) and, since BL-144, the BL-143 recovery's NO_SECTION
# arm. Sharing the string is the point: the operator must see the IDENTICAL
# audit signal whether or not the Approver row ALSO sits past the walker
# pre-extraction's `grep -A 20` cap. Combining the two evasions (malformed
# `### ` header + past-cap row) used to produce ZERO output — the walker's
# refusal was only reachable when a name had been pre-extracted.
# This WARN INCREMENTS `issues`, i.e. it BLOCKS (the label is cosmetic; the
# increment is the exit predicate) — lifted verbatim from the arm it now
# serves, so both arms keep that arm's established semantics.
_cpg_warn_no_gate_section() {
  echo -e "${YELLOW}[WARN]${NC} $1: APPROVAL_LOG.md has no '## ' header matching gate — cannot verify self-approval (malformed file?). Refusing silent file-level fallback; restore canonical '## Phase Gate: …' header."
  issues=$((issues + 1))
}

# --- Approval Entry Field Validation (P0-004) ---
# Verify approval entries have populated fields, not just template defaults
validate_approval_fields() {
  local gate_name="$1"  # e.g., "Phase 0.*Phase 1"
  local gate_label="$2" # e.g., "Phase 0→1"

  # Find the gate section and check for populated approver/date fields.
  # BL-138 (Dogfood-3 F-DF3-001): the old `grep -A 20 "$gate_name"` window
  # re-anchored on the `| **Gate** | Phase X → Y |` table ROW and bled past
  # the section into the template's downstream UAT/Attorney PLACEHOLDER
  # rows — the same window-bleed class killed in _cpg_gate_has_evidence
  # (verifier SF#1) and # BL-115-ATTORNEY-ENTRY (E1b Claim-C); this was the
  # missed arm. Window is now H2-HEADER-anchored, stops at the next `## `,
  # and caps at +20 — table rows can neither anchor nor extend the scan.
  # The section feeds the self-approval check below too, which equally must
  # read THIS gate's rows only.
  # EXISTENCE is still judged by the old any-line grep: a gate mentioned
  # ANYWHERE (canonical H2, malformed H3, prose) must flow through to the
  # blame walker below, whose own H2-strict scan owns the loud
  # "gate section not found" refusal for malformed headers (PR #116 /
  # T-blame-4 contract — an early return here silently swallowed that
  # WARN, the exact silent-pass class the walker exists to close; caught
  # by test-check-phase-gate-blame-walker.sh on this PR's first CI run).
  grep -q "$gate_name" "$APPROVAL_LOG" 2>/dev/null || return 0  # truly absent = checked separately
  local section
  section=$(awk -v h="^## .*${gate_name}" '$0 ~ h {f=1; next} f && /^## / {exit} f' "$APPROVAL_LOG" 2>/dev/null | head -20)
  # An EMPTY bounded section (malformed/non-H2 header) is NOT a skip: the
  # placeholder predicate below no-ops on empty input and the walker still
  # runs to refuse loudly.

  # BL-144: has BL-138 already reported a placeholder for THIS GATE'S WINDOW?
  # Its window is `head -20`-capped, so a past-cap placeholder Approver cell
  # escapes it — that gap is what `# BL-144-PLACEHOLDER-CELL` covers, and this
  # flag keeps the two from double-reporting the same gate.
  # WINDOW-scoped, NOT cell-scoped — say it plainly, because the difference is
  # observable: the BL-138 predicate fires on ANY template literal
  # (`[YYYY-MM-DD]` / `[Name` / `[Attorney`) anywhere in the capped window, so
  # an IN-CAP DATE placeholder sets this flag and suppresses the BL-144 line
  # for a DIFFERENT defect — a past-cap blank Approver cell (R-BL144-1,
  # reviewer P3). That is a deliberate one-gate-one-`issues` trade, not
  # precision: the gate still BLOCKS (rc=1) and BL-138's own message already
  # tells the operator to fill in the approver name.
  # Declared here (outside both fences) so either fence can be excised on its
  # own: with the BL-138 fence gone the flag stays 0 and the BL-144 arm reports
  # the cell itself; with the BL-144 fence gone the flag is merely written and
  # never read.
  local bl144_placeholder_reported=0

  # BL-138-APPROVAL-WINDOW-BEGIN
  # Placeholder predicate tightened to the TEMPLATE-LITERAL shapes the
  # shipped approval-log templates actually carry — `[YYYY-MM-DD]` and
  # `[Name`/`[Attorney`-style bracketed name placeholders. The old
  # any-bracket arm (`(Approver|Reviewer).*\[.*\]`) flagged legitimate
  # bracketed annotations (the dogfood-required `[SIMULATED]` tag), and the
  # bare `YYYY-MM-DD` arm flagged date-FORMAT prose. A placeholder is what
  # the template shipped, not any bracket an operator writes.
  if echo "$section" | grep -qE '\[YYYY-MM-DD\]|\[Name|\[Attorney'; then
    echo -e "${YELLOW}[WARN]${NC} $gate_label: APPROVAL_LOG.md entry contains placeholder values — fill in approver name and date"
    issues=$((issues + 1))
    bl144_placeholder_reported=1
  fi
  # BL-138-APPROVAL-WINDOW-END

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
    local approver_name walker_section
    # BL-138 follow-up (caught by T-blame-4 on this PR's first CI run): the
    # walker's PRE-extraction must stay PERMISSIVE (old any-line grep -A 20)
    # — with the bounded `$section`, a malformed H3-header log yielded an
    # empty section, no approver name, and the whole walker was SKIPPED,
    # silencing its "gate section not found" refusal (the exact silent-pass
    # class PR #116 closed). Permissive extraction is safe here: the walker
    # re-locates the row with its own H2-strict awk and refuses LOUDLY on
    # anything malformed — a bled or misparsed name can only lead to the
    # WARN, never a silent pass. The tightened `$section` above remains the
    # placeholder predicate's input.
    walker_section=$(grep -A 20 "$gate_name" "$APPROVAL_LOG" 2>/dev/null || echo "")
    approver_name=$(echo "$walker_section" | awk -F'|' '/[Aa]pprover/ && !/Role/ { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); gsub(/\*/, "", $3); print $3; exit }' 2>/dev/null || echo "")
    # BL-143-PASTCAP-RECOVERY-BEGIN
    # The permissive pre-extraction above is `grep -A 20` CAPPED: an
    # Approver row sitting more than 20 lines past the LAST gate-name
    # mention (filler/annotation rows — BL-138's bounding made the edge
    # reachable, wave verifier C3) yields an EMPTY name here, and the
    # `[ -n "$approver_name" ]` guard below skipped the ENTIRE
    # anti-self-approval control with zero output — while the blame
    # walker's own H2-strict scan (UNCAPPED: it walks to the next `## ` /
    # `---`) would have located the row. Recover the name FROM THE
    # WALKER'S OWN CONTRACT: locate the row with a faithful copy of the
    # walker's awk (keep IN SYNC with the `approver_line=` scan below —
    # this fence is deliberately ADDITIVE so excision restores the old
    # silent skip exactly), then read column 3 off the located line. A log
    # with truly NO Approver row anywhere stays out of scope (the
    # pre-BL-138 status quo): NO_SECTION / NO_APPROVER / awk-failure keep
    # their meanings in the walker's own arms, which are only reachable
    # when a name exists to verify.
    if [ -z "$approver_name" ] || [ "$approver_name" = "[Name]" ]; then
      local bl143_line
      bl143_line=$(awk -v gate="$gate_name" '
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
      case "$bl143_line" in
        # BL-144-NO-SECTION-BEGIN
        # BL-144 shape (a): the recovery computed NO_SECTION — no `## `
        # header matches the gate — and the generic `''|*[!0-9]*)` arm below
        # DISCARDED it, leaving the whole control silent. The walker's own
        # NO_SECTION refusal further down is unreachable here, because it
        # only runs once a name has been pre-extracted, and a past-cap row
        # yields no name. So a malformed `### ` header COMBINED with a
        # past-cap Approver row printed nothing at all — an executed
        # self-approval passed the gate fully green. Surface the recovery's
        # NO_SECTION through the walker's existing WARN (shared helper =
        # byte-identical message + the same `issues` increment, so this arm
        # BLOCKS exactly as its in-cap twin does). Deliberate scope call
        # carried over from the BL-144 entry: this also makes prose-only
        # gate mentions loud. BL-143's T4 boundary (an entry with NO
        # Approver row anywhere) maps to NO_APPROVER, not NO_SECTION, and is
        # NOT disturbed — it still falls through the silent arm below.
        NO_SECTION)
          _cpg_warn_no_gate_section "$gate_label"
          return 0
          ;;
        # BL-144-NO-SECTION-END
        ''|*[!0-9]*) : ;;  # nothing locatable — the declared boundary
        *)
          approver_name=$(sed -n "${bl143_line}p" "$APPROVAL_LOG" 2>/dev/null \
            | awk -F'|' '{ gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); gsub(/\*/, "", $3); print $3 }' 2>/dev/null) || approver_name=""
          # BL-144-PLACEHOLDER-CELL-BEGIN
          # BL-144 shape (b): the recovery LOCATED the Approver row and read
          # back a template placeholder (`[Name]`) or a blank cell — then the
          # `[ -n … ] && [ … != "[Name]" ]` guard below dropped it without a
          # word. The BL-138 placeholder predicate cannot cover this: its
          # window is `head -20`-capped, so a past-cap cell never reaches it
          # (and a BLANK cell carries no template literal, so it escapes that
          # predicate at ANY distance). Report it here — the row exists, it
          # names nobody, and self-approval therefore cannot be verified.
          # WARN + `issues` increment, i.e. BLOCKING: that is the established
          # semantics of every arm around this one (the BL-138 placeholder
          # WARN and all three of the walker's cannot-verify WARNs increment),
          # and it keeps a past-cap `[Name]` cell exactly as blocking as the
          # in-cap `[Name]` cell the BL-138 predicate already refuses.
          # NOT a double report: when BL-138 already reported a placeholder for
          # this gate's WINDOW the flag suppresses this line, so one gate still
          # costs one `issues`. The suppression is window-scoped, not
          # cell-scoped — an in-cap DATE placeholder can therefore mute this
          # line for a past-cap blank cell (R-BL144-1; the gate still blocks,
          # rc=1). See the flag's declaration for why that trade is deliberate.
          # Return either way — an unnamed approver is unverifiable.
          if [ -z "$approver_name" ] || [ "$approver_name" = "[Name]" ]; then
            if [ "$bl144_placeholder_reported" -eq 0 ]; then
              echo -e "${YELLOW}[WARN]${NC} $gate_label: APPROVAL_LOG.md Approver cell is a placeholder or blank — cannot verify self-approval. Record the approver's real name in the gate's Approver row."
              issues=$((issues + 1))
            fi
            return 0
          fi
          # BL-144-PLACEHOLDER-CELL-END
          ;;
      esac
    fi
    # BL-143-PASTCAP-RECOVERY-END
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
          # BL-144: the line itself moved into `_cpg_warn_no_gate_section`
          # (message + `issues` increment unchanged) so the recovery's
          # NO_SECTION arm above cannot drift from this one.
          _cpg_warn_no_gate_section "$gate_label"
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
  # BL-170 (verifier HIGH-1): section-BOUNDED, not a bare `grep -A 15`.
  # The unbounded window bled into the NEXT subsection once the templates'
  # pre-seeded empty `| **Date** | |` row (an accidental first-match
  # shield) was removed by the append redesign — an IT-Security-only
  # append satisfied the Application Owner check, passing dual-approval
  # with ONE signer. Bound at the next header line, then cap at 15 (the
  # documented evidence-window budget). Same defect class as BL-115/BL-138.
  section=$(awk -v h="$section_header" '
    found && /^#/ { exit }
    found { print }
    index($0, h) > 0 { found = 1 }
  ' "$APPROVAL_LOG" 2>/dev/null | head -15)
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
  poc_mode_val=$(soif_read_poc_mode "$PHASE_STATE")

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
  # Check for Phase 0 intermediate outputs (P0-002).
  # BL-114-F1-INTERMEDIATES: the documented behavior is WARNS-AND-BLOCKS —
  # but this check never incremented `issues` (deleting frd.md printed
  # "2/3 saved" and the gate said "consistent", walk F1), and an ABSENT
  # docs/phase-0/ produced no output at all. Code now matches docs: any
  # missing intermediate BLOCKS, labeled [FAIL] so the verdict and the label
  # agree (the BL-104 [WARN] trap runs the other way too — a blocking arm
  # must not dress as a warning).
  if [ -d "docs/phase-0" ]; then
    p0_files=0
    [ -f "docs/phase-0/frd.md" ] && p0_files=$((p0_files + 1))
    [ -f "docs/phase-0/user-journey.md" ] && p0_files=$((p0_files + 1))
    [ -f "docs/phase-0/data-contract.md" ] && p0_files=$((p0_files + 1))
    if [ $p0_files -eq 3 ]; then
      echo -e "${GREEN}  [OK]${NC} Phase 0 intermediates: frd.md, user-journey.md, data-contract.md"
    else
      echo -e "${RED}[FAIL]${NC} Phase 0 intermediates: $p0_files/3 saved — docs/phase-0/ requires frd.md, user-journey.md, data-contract.md (Step 0 evidence; documented as blocking)"
      issues=$((issues + 1))
    fi
  else
    echo -e "${RED}[FAIL]${NC} Phase 0 intermediates: docs/phase-0/ missing entirely — frd.md, user-journey.md, data-contract.md are required Step 0 evidence (documented as blocking)"
    issues=$((issues + 1))
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
          # WALK-ISSUE-006-CI-PROTECTION-SCOPE-BEGIN
          # Walk 2026-08-02, ISSUE-006 (Major): this arm made the generated
          # project's "Governance - Phase gate check" step STRUCTURALLY
          # unpassable on the framework's OWN default happy path (a public
          # personal GitHub repo that init.sh had just created). Branch
          # protection is an AUTHENTICATED API read on every first-class
          # host, and a CI runner holds no credential for it unless the
          # operator exports one:
          #   • GitHub Actions puts NO token in a step's environment —
          #     `secrets.GITHUB_TOKEN` has to be mapped explicitly, and even
          #     mapped it CANNOT read branch protection (the workflow
          #     `permissions:` block has no `administration` key). Only a
          #     PAT / App token with admin-read can.
          #   • The generated gitlab + bitbucket governance jobs run in
          #     `bash:5` with only jq+git added — no `glab`, no `curl`, no
          #     credential either.
          # So the identical command exited 0 on the dev workstation and 1 on
          # every push. The walker's only escape was SOIF_PHASE_GATES=warn,
          # which downgrades the WHOLE gate — a far bigger hammer than this.
          #
          # SCOPING mirrors the BL-137 "Tools needed" fence further down this
          # same file — `grep -n 'BL-137' "$0"` finds it. Its marker token is
          # deliberately NOT spelled out here: tests/test-bl137-ci-tools-scope.sh
          # ::T5 excises that fence by line range and then asserts NO residual
          # occurrence of the marker text anywhere in the script, so a second
          # mention of it — even in a comment, even as a citation — fails the
          # excision guard. Do not "helpfully" add one back.
          #
          # Keyed STRICTLY on $CI *plus* the absence of a host credential —
          # NEVER on TTY, so
          # scripted LOCAL runs (hooks, other gates driving this one) keep
          # blocking. Export the token and this arm BLOCKS again in CI: that
          # is the documented hard-enforcement path, and it is spelled out at
          # the phase-gate step of every generated ci.yml.
          #
          # host="other" is deliberately NOT exempt: its host_verify_protection
          # reads a LOCAL attestation file and needs no credential at all, so
          # a failure there is equally real on a runner and on a laptop.
          #
          # HONESTY: the exempt arm prints "could NOT RUN", never "verified".
          # The contract is UNVERIFIED on such a run — it is not satisfied.
          _cpg_walk006_credentialless_ci() {
            [ -n "${CI:-}" ] || return 1   # WALK-ISSUE-006-CI-KEY
            case "${1:-}" in
              github)    [ -z "${GH_TOKEN:-}" ] && [ -z "${GITHUB_TOKEN:-}" ] ;;
              gitlab)    [ -z "${GITLAB_TOKEN:-}" ] && [ -z "${GL_TOKEN:-}" ] ;;
              bitbucket) [ -z "${BITBUCKET_API_TOKEN:-}" ] && [ -z "${BITBUCKET_APP_PASSWORD:-}" ] ;;
              *)         return 1 ;;
            esac
          }
          backstop_host=$(jq -r '.host // empty' .claude/manifest.json 2>/dev/null || echo "")
          if _cpg_walk006_credentialless_ci "$backstop_host"; then
            echo -e "${YELLOW}[WARN]${NC} Phase 1→2 backstop: protection verification COULD NOT RUN here — \$CI is set and no ${backstop_host:-host} API credential is exported on this runner."
            echo "        This is NOT a pass. The protection contract is UNVERIFIED on this run; it is enforced on the dev workstation, where this same arm BLOCKS (WALK-ISSUE-006)."
            echo ""
            echo "        >> FIX THIS ONCE, and this warning is replaced by real enforcement:"
            echo "               scripts/check-gate.sh --setup-ci-token"
            echo "           A guided, least-privilege walkthrough: it explains what the token is for, walks"
            echo "           you through a fine-grained PAT with the ONE permission needed (Administration:"
            echo "           Read-only, this repo only), proves the token can read protection BEFORE storing"
            echo "           it, and sets it as the Actions secret your workflow already reads."
            echo "           The built-in GITHUB_TOKEN cannot do this — it has no admin-read permission."
            echo "           A warning nobody clears is a check nobody reads. Please clear it."
            echo ""
            echo "        Verify locally any time: scripts/check-gate.sh --preflight"
          else
            echo -e "${RED}[FAIL]${NC} Phase 1→2 backstop: protection verification failed"
            echo "        Remediate: scripts/check-gate.sh --repair"
            echo "        Preflight: scripts/check-gate.sh --preflight"
            issues=$((issues + 1))
          fi
          # WALK-ISSUE-006-CI-PROTECTION-SCOPE-END
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
  bl084_gate_applies=false
  [ "$bl084_host" = "other" ] && bl084_gate_applies=true
  # BL-116-PUSH-GATE-SCOPE-BEGIN
  # BL-116: the gate used to be scoped `host == "other"` on the premise that
  # "first-class hosts are provably pushed at init" — FALSE for
  # --no-remote-creation, which is the blessed hermetic flow: a github/gitlab
  # project scaffolded that way never received the MANDATORY push gate at all
  # (E2E walk F7). The first-class exemption is now EARNED, not assumed: it
  # holds only when phase2_init.steps_completed records BOTH
  # remote_repo_created and pushed_initial — the on-disk meaning of "provably
  # pushed at init". Fence is excision-safe: removing it restores the
  # host=other-only scope.
  if [ "$bl084_gate_applies" != true ]; then
    bl084_init_pushed=false
    if [ -f .claude/process-state.json ] && command -v jq >/dev/null 2>&1; then
      if jq -e '.phase2_init.steps_completed | (index("remote_repo_created") != null) and (index("pushed_initial") != null)' \
           .claude/process-state.json >/dev/null 2>&1; then
        bl084_init_pushed=true
      fi
    fi
    [ "$bl084_init_pushed" != true ] && bl084_gate_applies=true
  fi
  # BL-116-PUSH-GATE-SCOPE-END
  if [ "$bl084_gate_applies" = true ]; then
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

# ── BL-233 WP-B: accumulation, checked ONCE, for the gate being crossed ────
# `-eq`, not `-ge`, and the difference from every sibling check in this file is
# deliberate. The gate-date and artifact checks use `-ge` because their evidence
# must exist INDEPENDENTLY at each boundary, so all of them firing at phase 4 is
# correct. Accumulation is not like that: the windows NEST. A store that
# satisfies "since phase_2_to_3" necessarily satisfies "since phase_1_to_2", so
# the latest gate's window is the strictest and subsumes the earlier ones.
# Firing all three would count ONE missing store as THREE inconsistencies and
# print the same sentence three times.
#
# THE NESTING ARGUMENT COVERS THE STORE HALF ONLY, and the difference is a real
# limit rather than a proof: `_cpg_accum_source_work` is evaluated over the
# NARROW window too, so an earlier phase's unpaid debt is not re-litigated once
# that boundary is behind you. A phase-2 project that committed source and
# stored nothing blocks at 1→2; advance it to phase 3 and the 2→3 arm reports
# "nothing owed" if phase 3 itself committed only docs. Running
# `--gate phase_1_to_2` still finds it. This is deliberate — a passed gate is
# passed — but it is a limit, not something the nesting claim establishes.
#
# phase_0_to_1 has no arm: Phase 0 is pre-code discovery, it writes no source,
# and the conditional would never fire anyway — an arm that cannot fire is the
# `## BL-104:` shape and is better absent than decorative.
case "$current_phase" in
  2) _cpg_accum_gate "phase_1_to_2" "$gate_0_to_1" "Phase 1→2" "$raw_gate_0_to_1" ;;
  3) _cpg_accum_gate "phase_2_to_3" "$gate_1_to_2" "Phase 2→3" "$raw_gate_1_to_2" ;;
  4) _cpg_accum_gate "phase_3_to_4" "$gate_2_to_3" "Phase 3→4" "$raw_gate_2_to_3" ;;
esac

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
#
# BL-082 (2026-07-09): the summary is bound to the tree it validated. A summary
# is FRESH only if its recorded `tree:` line is present, ≠ `none`, EQUALS the
# current `git rev-parse HEAD^{tree}`, its recorded `dirty:` is `no`, AND the
# live SCOPED working tree is clean (HEAD^{tree} alone misses uncommitted edits
# — a clean-tree summary must not stay trusted while source is edited). Any
# other state → STALE: print `[STALE]`, regenerate offline via the
# `# BL-070-GATE-AUTORUN` path, and evaluate the FRESH summary in a single pass;
# if regeneration is impossible (SOLO_PHASE3_GATE_NOAUTORUN=1 or driver
# missing/non-executable) STALE = gate FAIL (never silently accept a stale
# summary). Pre-BL-082 summaries have no `tree:` line → STALE (backward compat).
# The freshness decision line is marked `# BL-082-STALENESS` (mutation target).
# The scoped dirty check (# BL-082-STALENESS in _cpg_scoped_dirty) EXCLUDES
# `.claude/` and the results dir because the gate itself writes the BL-071 gate
# date into .claude/phase-state.json on PASS (line ~374) and that file is
# TRACKED downstream — an UNSCOPED check would mark every summary permanently
# stale after its first PASS (self-defeating).

# ═══════════════════════════════════════════════════════════════════════
# BL-113 — the offline autorun must not launder a real FAIL into a SKIP.
# ═══════════════════════════════════════════════════════════════════════
# Walk finding F15: whenever the tree is dirty (the NORMAL state while the
# operator is authoring Phase-3 artifacts) the BL-082 staleness check autoruns
# the driver with `--offline`, which SKIPs every tool-backed scanner. The
# operator saw "scanner unavailable", attested the SKIP in good faith, and
# passed — never learning that a REAL semgrep run FAILs (F14). A FAIL is not
# attestable; a SKIP is. The autorun was the laundry.
#
# TWO defences, both marked `# BL-113-NO-LAUNDER`:
#
#   1. IN THE DRIVER (scripts/run-phase3-validation.sh, `_p3_no_launder`): a
#      SKIP never overwrites a prior REAL FAIL — it is promoted back to FAIL
#      with a `[STALE - last real result: FAIL]` note and a machine-readable
#      `CARRIED <scanner> <origin>` line. The gate surfaces that line verbatim
#      below so the operator reads WHY the FAIL is there.
#
#   2. HERE: an offline-autorun SKIP for a scanner whose TOOL IS ON PATH is
#      REFUSED — attested or not. It is not a result; it is the autorun's own
#      choice not to look, and the operator cannot honestly sign "scanner
#      unavailable" for a scanner that is installed. To clear it the operator
#      must run the driver themselves WITHOUT `--offline`, which yields a real
#      verdict (PASS/FAIL) or — with the tool present but no network — an
#      HONEST, attestable SKIP recorded against a non-offline summary.
#
# THE AUTORUN STAYS `--offline` (deliberate, verified): `semgrep --config auto`
# is NOT local-only. It hard-fetches its ruleset from semgrep.dev with no local
# cache fallback (network blackholed: ~97s of retries, rc=2, no report). Running
# it from the gate would make the gate non-hermetic, slow, and would brick
# genuinely-offline operators. The laundering dies; the offline mode does not.
#
# GENUINELY OFFLINE STAYS USABLE: tool absent → no refusal → an honest SKIP is
# still attestable and the gate is still passable. That is the whole point of
# the attest-on-skip design and BL-113 does not touch it.

# _cpg_phase3_scanner_tool <scanner> — echo the single binary whose presence on
# PATH makes the scanner LOCALLY RUNNABLE, or "" when there is no unambiguous
# one. Deliberately narrow (BL-113): only `semgrep-full-tree` is mapped.
#   * semgrep is the SAST the walk caught being laundered, and its real-run path
#     now degrades to an honest attestable SKIP when the rule registry is
#     unreachable (`# BL-113-SEMGREP-OFFLINE`), so forcing a real run can never
#     brick an offline operator.
#   * `snyk`'s real-run path FAILs (not SKIPs) on an offline execution error, so
#     forcing a real snyk run on an offline operator WOULD brick them.
#   * `license` has no single binary (per-language tool); `threat-model` is
#     pure-local and already runs under --offline.
# The DRIVER-side carry-forward (defence 1) protects ALL FIVE scanners, so a
# real FAIL from any of them is still never laundered.
_cpg_phase3_scanner_tool() {
  case "$1" in
    semgrep-full-tree) echo "semgrep" ;;
    *)                 echo "" ;;
  esac
}

# _cpg_phase3_summary_offline <summary> — echo "yes"/"no": was this summary
# produced by an --offline run (i.e. by the gate's own autorun)?
_cpg_phase3_summary_offline() {
  local v
  v=$(grep -m1 '^- Offline:' "$1" 2>/dev/null | sed 's/^- Offline:[[:space:]]*//; s/[[:space:]]*$//' || true)
  case "$v" in yes) echo "yes" ;; *) echo "no" ;; esac
}

# _cpg_phase3_carried_origin <summary> <scanner> — echo the origin summary of a
# BL-113 carried-forward FAIL for <scanner>, or "".
_cpg_phase3_carried_origin() {
  awk -v s="$2" '$1=="CARRIED" && $2==s {v=$3} END{print v}' "$1" 2>/dev/null || true
}

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

# _cpg_scoped_dirty <results_dir> — echo "yes"/"no". Scoped `git status
# --porcelain` that EXCLUDES the framework's own write surfaces so a summary is
# not marked permanently stale by the very writes the gate makes on PASS.
# BL-082-STALENESS: excludes `.claude/` (the gate writes the BL-071 gate date +
# the driver writes attestations into phase-state.json, TRACKED downstream) and
# the results dir. Absolute/parent-relative results dirs are outside the
# porcelain scope already → exclusion skipped. Not a git repo → conservative
# "yes". Kept textually identical to _p3_scoped_dirty in
# scripts/run-phase3-validation.sh.
#
# BL-214-SNAPSHOT-EXCLUDE: `docs/snapshots` is excluded for the SAME reason
# `.claude/` is — `create_gate_snapshot` writes there on PASS, so without this
# a fully passing gate run planted its own next failure: run 1 exits 0 and
# leaves `?? docs/snapshots/`, run 2 reports the summary STALE and FAILs when
# auto-regeneration is off. THIS FUNCTION AND ITS SIBLING MUST CHANGE TOGETHER;
# tests/test-bl214-gate-snapshot-staleness.sh::B1 compares the two bodies
# byte-for-byte so an edit to one alone goes RED even where it behaves.
_cpg_scoped_dirty() {
  local rdir out
  rdir="${1:-}"
  rdir="${rdir#./}"
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "yes"; return 0
  fi
  case "$rdir" in
    ""|/*|../*|..)
      out=$(git status --porcelain -- . ':(exclude).claude' ':(exclude)docs/snapshots' 2>/dev/null || true) ;;
    *)
      out=$(git status --porcelain -- . ':(exclude).claude' ':(exclude)docs/snapshots' ":(exclude)$rdir" 2>/dev/null || true) ;;
  esac
  if [ -n "$out" ]; then echo "yes"; else echo "no"; fi
  return 0
}

# _cpg_phase3_freshness <summary> <results_dir> — echo "fresh" or
# "stale:<reason>". FRESH iff the summary recorded a real tree that EQUALS the
# current HEAD^{tree} AND recorded dirty=no AND the live scoped tree is clean.
# HEAD^{tree} alone misses uncommitted edits, so the live scoped check is
# required (Correction 2): a clean-tree summary must not stay trusted while
# source is edited uncommitted. Pre-BL-082 summaries (no `tree:` line) → stale.
# Always returns 0 (the verdict is the echoed string) so the gate's `set -e`
# is not tripped by a "stale" result.
_cpg_phase3_freshness() {
  local summary rdir cur_tree rec_tree rec_dirty live_dirty
  summary="$1"; rdir="$2"
  cur_tree=$(git rev-parse "HEAD^{tree}" 2>/dev/null || echo none)
  rec_tree=$(grep -m1 '^- tree:' "$summary" 2>/dev/null | sed 's/^- tree:[[:space:]]*//; s/[[:space:]]*$//' || true)
  rec_dirty=$(grep -m1 '^- dirty:' "$summary" 2>/dev/null | sed 's/^- dirty:[[:space:]]*//; s/[[:space:]]*$//' || true)
  live_dirty=$(_cpg_scoped_dirty "$rdir")
  if [ -n "$rec_tree" ] && [ "$rec_tree" != "none" ] && [ "$rec_tree" = "$cur_tree" ] && [ "$rec_dirty" = "no" ] && [ "$live_dirty" = "no" ]; then
    echo "fresh"; return 0
  fi
  if [ -z "$rec_tree" ]; then echo "stale:no tree provenance recorded (pre-BL-082 summary)"
  elif [ "$rec_tree" = "none" ]; then echo "stale:summary was generated outside a git repo (tree: none)"
  elif [ "$cur_tree" = "none" ]; then echo "stale:current tree unavailable (not a git repo)"
  elif [ "$rec_tree" != "$cur_tree" ]; then echo "stale:the tree changed since this summary was generated"
  elif [ "$rec_dirty" != "no" ]; then echo "stale:the summary was generated on a dirty working tree"
  else echo "stale:there are uncommitted changes since this summary was generated"
  fi
  return 0
}

if [ "$current_phase" -ge 4 ]; then
  P3_RESULTS_DIR="docs/test-results/phase3"
  P3_DRIVER="$SCRIPT_DIR/run-phase3-validation.sh"

  # Discover the newest existing summary.
  p3_summary=""
  if compgen -G "$P3_RESULTS_DIR/summary-*.md" >/dev/null 2>&1; then
    p3_summary=$(ls -1 "$P3_RESULTS_DIR"/summary-*.md 2>/dev/null | sort | tail -1)
  fi

  # BL-082 freshness: trust an existing summary only if it was generated
  # against the CURRENT tree with a clean (scoped) working tree. The decision
  # line below is the mutation target — excising every `# BL-082-STALENESS`
  # line defaults p3_fresh to "fresh" and MUST make
  # tests/test-phase3-validation-gate.sh::T-stale-norerun-fails go RED.
  p3_stale=0
  p3_stale_reason=""
  p3_fresh="fresh"
  if [ -n "$p3_summary" ]; then
    p3_fresh=$(_cpg_phase3_freshness "$p3_summary" "$P3_RESULTS_DIR")   # BL-082-STALENESS
    : # keep this then-branch non-empty so excising the marked line above stays valid
  fi
  case "$p3_fresh" in
    fresh) p3_stale=0 ;;
    *)     p3_stale=1; p3_stale_reason="${p3_fresh#stale:}" ;;
  esac

  # AUTO-RUN (Karl: "evals should be automatic"). Regenerate an offline
  # baseline summary when NONE exists OR the existing one is STALE (offline =>
  # hermetic/fast: NO network/Docker/semgrep run from the gate). Operators run
  # `scripts/run-phase3-validation.sh` (no --offline) for REAL scans. A STALE
  # summary prints an explicit [STALE] line, then we regenerate and evaluate
  # the FRESH file in a SINGLE pass (no second staleness check — it was just
  # written against the current tree). Set SOLO_PHASE3_GATE_NOAUTORUN=1 to
  # disable auto-generation; then STALE = gate FAIL (never silently accept a
  # stale summary).
  if [ "$p3_stale" -eq 1 ]; then
    echo -e "${BLUE}[STALE]${NC} Phase 3→4: ${p3_stale_reason} — the recorded validation summary no longer matches the working tree; regenerating."
  fi
  if [ -z "$p3_summary" ] || [ "$p3_stale" -eq 1 ]; then
    if [ -z "${SOLO_PHASE3_GATE_NOAUTORUN:-}" ] && [ -x "$P3_DRIVER" ]; then
      bash "$P3_DRIVER" --offline >/dev/null 2>&1 || true   # BL-070-GATE-AUTORUN
      p3_summary=""
      if compgen -G "$P3_RESULTS_DIR/summary-*.md" >/dev/null 2>&1; then
        p3_summary=$(ls -1 "$P3_RESULTS_DIR"/summary-*.md 2>/dev/null | sort | tail -1)
      fi
      p3_stale=0   # freshly regenerated against the current tree → evaluate directly
    fi
  fi

  p3_block=0
  p3_msg=""
  p3_ok_detail=""
  if [ "$p3_stale" -eq 1 ]; then
    # STALE and regeneration was impossible (SOLO_PHASE3_GATE_NOAUTORUN=1 or
    # the driver is missing/non-executable) — never silently accept a stale
    # summary. Tell the operator to re-run the driver.
    p3_block=1
    p3_msg="Phase 3 validation summary is STALE (${p3_stale_reason}) and auto-regeneration is off/unavailable — re-run: bash scripts/run-phase3-validation.sh"
  elif [ -z "$p3_summary" ]; then
    p3_block=1
    p3_msg="no Phase 3 validation summary (docs/test-results/phase3/summary-*.md) — run: bash scripts/run-phase3-validation.sh"
  else
    p3_fail=0
    p3_unattested=0
    p3_refused=0
    p3_detail=""
    p3_summary_offline=$(_cpg_phase3_summary_offline "$p3_summary")
    for p3_scanner in semgrep-full-tree license snyk zap-dast threat-model; do
      p3_status=$(awk -v s="$p3_scanner" '$1=="RESULT" && $2==s {v=$3} END{print v}' "$p3_summary" 2>/dev/null || true)
      [ -n "$p3_status" ] || p3_status="MISSING"
      case "$p3_status" in
        PASS) ;;
        SKIP)
          # BL-113-NO-LAUNDER (defence 2 — see the header block above). An
          # offline-autorun SKIP for a scanner whose TOOL IS INSTALLED is not a
          # result and is REFUSED, attested or not. `p3_refuse` is the whole
          # decision: neutering the marked line below (marker intact) leaves it
          # 0 forever, restores the laundering, and MUST turn
          # tests/test-bl113-sast-honesty.sh::T-no-launder-dirty-tree RED.
          # Both operands are pre-initialised on UNMARKED lines so the mutation
          # stays syntactically valid and `set -u`-safe.
          p3_tool=""
          p3_refuse=0
          p3_tool=$(_cpg_phase3_scanner_tool "$p3_scanner")
          if [ -n "$p3_tool" ] && [ "$p3_summary_offline" = "yes" ] && command -v "$p3_tool" >/dev/null 2>&1; then
            p3_refuse=1   # BL-113-NO-LAUNDER: locally-installed tool + offline autorun => the SKIP is not a result
            :             # kept non-empty so excising the marked line above stays valid
          fi
          if [ "$p3_refuse" -eq 1 ]; then
            p3_refused=$((p3_refused + 1))
            p3_detail="${p3_detail}${p3_detail:+, }${p3_scanner}(offline-autorun SKIP REFUSED)"
            echo -e "${RED}[FAIL]${NC} Phase 3→4: ${p3_scanner} — offline autorun SKIP REFUSED: the gate's own --offline autorun skipped it, but ${p3_tool} IS INSTALLED on this machine. An offline SKIP is not a clean bill of health and will NOT be accepted (attested or not). Run a REAL scan:  bash scripts/run-phase3-validation.sh   (no --offline)"
          elif _cpg_phase3_attested "$p3_scanner"; then
            :   # attested-skip-with-signoff → acceptable (honest no-tool/no-network SKIP)
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
          # BL-113-NO-LAUNDER: if this FAIL is the driver's carry-forward of a
          # prior REAL FAIL (defence 1), say so in words — the operator must
          # know the scan they were about to attest away really ran and really
          # failed, and that a FAIL is not attestable.
          p3_carried_from=""
          p3_carried_from=$(_cpg_phase3_carried_origin "$p3_summary" "$p3_scanner")   # BL-113-NO-LAUNDER
          if [ -n "$p3_carried_from" ]; then
            echo -e "${RED}[FAIL]${NC} Phase 3→4: ${p3_scanner} — [STALE — last real result: FAIL] (origin: ${p3_carried_from}). This scanner SKIPped in the latest run, but the last time it REALLY ran it FAILED, so the SKIP was refused rather than laundered. A FAIL is not attestable — fix the findings and re-run:  bash scripts/run-phase3-validation.sh   (no --offline)"
          fi
          ;;
      esac
    done
    if [ "$p3_fail" -gt 0 ] || [ "$p3_unattested" -gt 0 ] || [ "$p3_refused" -gt 0 ]; then
      p3_block=1
      p3_msg="validation scans not clean: ${p3_fail} FAIL, ${p3_unattested} un-attested SKIP, ${p3_refused} offline-autorun SKIP REFUSED (tool installed) [${p3_detail}] — attest: bash scripts/run-phase3-validation.sh --attest <scanner> --reason \"...\", or install the tool and re-run"
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

# ═══════════════════════════════════════════════════════════════════════
# Phase 3→4 readiness region (fires at current_phase>=3). These blocks belong
# to the phase_3_to_4 gate, not phase_2_to_3. Under a scoped --gate whose target
# is below 4 (BL-166-GATE-SCOPE) each is skipped from counting and the region is
# summarized as ONE non-counted [NEXT] line; a bare run keeps them all.
# ═══════════════════════════════════════════════════════════════════════
if [ "$skip_later_gate" -eq 1 ] && [ "$current_phase" -ge 3 ]; then
  # BL-166-GATE-SCOPE — announce (do NOT count) the next gate's deliverables.
  echo -e "${BLUE}[NEXT]${NC} Phase 3→4 readiness (POC-mode release block, release-pipeline TODOs, HANDOFF.md, docs/INCIDENT_RESPONSE.md, sbom.json, docs/test-results/, SECURITY.md, penetration test, review manifest, Phase-3 process checklist) is NOT evaluated under --gate $GATE_SCOPE — these belong to the phase_3_to_4 gate and are not counted against it."
fi

# POC mode check (Phase 3→4) — block production release if in POC mode
if [ "$current_phase" -ge 3 ] && [ "$skip_later_gate" -eq 0 ]; then   # BL-166-GATE-SCOPE
  # BL-095: this was the jq-with-grep-fallback DUAL variant — exactly the
  # branch pair soif_read_poc_mode implements once, with identical null
  # semantics on both arms.
  poc_mode=$(soif_read_poc_mode .claude/phase-state.json)
  if [ -n "$poc_mode" ] && [ "$poc_mode" != "null" ]; then
    echo "::error::Phase 4 (production release) is BLOCKED — project is in ${poc_mode//_/ } mode."
    echo "  POC projects complete at Phase 3 (ready to deploy)."
    echo "  To unlock Phase 4: bash scripts/upgrade-project.sh --to-production"
    issues=$((issues + 1))
  fi
fi

# Release pipeline configuration check (Phase 3→4)
if [ "$current_phase" -ge 3 ] && [ "$skip_later_gate" -eq 0 ]; then   # BL-166-GATE-SCOPE
  # BL-229-GATE-RELEASE-PATH: resolve the release pipeline from the RECORDED
  # host rather than assuming the GitHub spelling. Before this the `-f` test was
  # false on GitLab and Bitbucket, so the whole block was skipped and printed
  # NOTHING — a release pipeline full of unconfigured TODOs passed the 3→4 gate
  # on two of three hosts, and the silence read exactly like a clean result.
  # That is the `# BL-112-SAST-NOTRUN` prohibition: "did not run" must never be
  # spelled the same as "found nothing".
  #
  # All three failure arms below increment `issues`, i.e. they BLOCK. Read the
  # increment, not the [WARN] label (CLAUDE.md's WARN trap) — and note the
  # artifact loop immediately below has always failed closed this way for
  # HANDOFF.md / sbom.json. This block is now consistent with its neighbour.
  # Reuse SCRIPT_DIR_CPG when the phase>=2 block already derived it; the >=3
  # guard above implies it ran, but derive as a fallback rather than assume.
  _cpg_lib_dir="${SCRIPT_DIR_CPG:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
  _rel_path=""; _rel_how=""; _rel_ci=""
  if [ -f "$_cpg_lib_dir/lib/host.sh" ]; then
    # shellcheck disable=SC1090
    . "$_cpg_lib_dir/lib/host.sh"
    if host_pipeline_resolve >/dev/null 2>&1; then
      _rel_path="$HOST_RELEASE_PATH"
      _rel_how="$HOST_RELEASE_EXECUTES"
      _rel_ci="$HOST_CI_PATH"
    fi
  fi
  if [ -z "$_rel_path" ]; then
    # Same tier rule as the absence arm below (# BL-229-RELEASE-ABSENT-TIER /
    # BL-084-TIER-KEY). An unrecorded host is "cannot tell", and cannot-tell
    # must never read as clean — so it is ALWAYS reported. But requiring a
    # recorded host to clear 3→4 is a new gate condition BL-229 never asked
    # for, and it blocked light-track personal fixtures that have no manifest
    # at all. Block where the tier expects a release pipeline; inform otherwise.
    if [ "$deployment" = "organizational" ] || [ "$poc_mode" = "sponsored_poc" ]; then
      echo -e "${YELLOW}[WARN]${NC} Phase 3→4: release pipeline NOT CHECKED — could not resolve this project's host"
      echo "  This tier (deployment=$deployment) needs the check to run. Record the host with: bash scripts/check-gate.sh --backfill-host"
      issues=$((issues + 1))
    else
      echo -e "${BLUE}  [INFO]${NC} Phase 3→4: release pipeline not checked — no host recorded (deployment=$deployment). Record one with: bash scripts/check-gate.sh --backfill-host"
    fi
  elif [ ! -f "$_rel_path" ]; then
    # BL-229-RELEASE-ABSENT-TIER / BL-084-TIER-KEY (SYNC SIBLINGS — same
    # predicate as the bypass-eligibility arm above, and as pre-commit-gate.sh,
    # init.sh and scripts/lib/enforcement-level.sh).
    #
    # ABSENCE IS NOT THE SAME DEFECT AS SILENCE. BL-229 is about the check not
    # RUNNING on two of three hosts; a light-track personal project with no
    # release pipeline is a legitimate shape, not a finding. An earlier version
    # of this block made absence BLOCK on every host, which imposed a new
    # requirement the entry never asked for and broke 13 assertions across three
    # suites whose fixtures encode exactly that shape. So: always REPORT — never
    # silent, which was the real defect — and BLOCK only where the tier expects
    # a release pipeline to exist.
    if [ "$deployment" = "organizational" ] || [ "$poc_mode" = "sponsored_poc" ]; then
      echo -e "${YELLOW}[WARN]${NC} Phase 3→4: release pipeline not found at $_rel_path"
      echo "  This tier (deployment=$deployment, poc_mode=${poc_mode:-none}) requires one before production release."
      issues=$((issues + 1))
    else
      echo -e "${BLUE}  [INFO]${NC} Phase 3→4: no release pipeline at $_rel_path (deployment=$deployment) — not required at this tier, and not checked further"
    fi
  elif [ "$_rel_how" != "file" ] && { _hwr_verify "$_rel_ci" "$_rel_path" "$_rel_how"; _wire_rc=$?; [ "$_wire_rc" -ne 0 ]; }; then
    # BL-229-GATE-RELEASE-WIRED: existence is not execution. On GitLab and
    # Bitbucket the release file is INERT until the root pipeline references it
    # — GitLab by `include:`, Bitbucket by `definitions.imports` plus an
    # `import:`. init.sh shipped unreferenced release files on both hosts for
    # months, so a gate that stops at `[ -f ]` would bless exactly the state
    # this entry exists to end.
    # ASK the shared predicate (# BL-229-WIRE-VERIFY) rather than re-deriving it.
    # A private `grep -q "$path" "$ci"` here was satisfied by a mention in a
    # comment, by a source declared and never invoked, and by a declaration
    # YAML had already discarded — so the gate blessed three inert states the
    # writer's own verifier rejected. Two predicates for one question, and they
    # disagreed: a fresh sync sibling inside the entry about sync siblings.
    if [ "$_wire_rc" -eq 2 ]; then
      echo -e "${YELLOW}[WARN]${NC} Phase 3→4: could NOT VERIFY that $_rel_path is wired into $_rel_ci"
      echo "  The pipeline file uses a shape this check cannot read (flow style, or multiple documents)."
      echo "  Cannot-measure is not a pass. Confirm by hand that $_rel_ci contains:"
      case "$_rel_how" in
        include) echo "    include: [{ local: /$_rel_path }]" ;;
        import)  echo "    definitions.imports.release: $_rel_path"
                 echo "    and, under a pipelines start-condition: import: release-pipeline@release" ;;
      esac
    else
      echo -e "${YELLOW}[WARN]${NC} Phase 3→4: release pipeline $_rel_path is NOT WIRED into $_rel_ci — it will never run"
      echo "  This host reaches the release file by '$_rel_how'; without that reference the file is inert."
    fi
    issues=$((issues + 1))
  else
    todo_count=$(grep -c "TODO" "$_rel_path" 2>/dev/null) || todo_count=0
    case "$todo_count" in ''|*[!0-9]*) todo_count=0 ;; esac
    if [ "$todo_count" -gt 0 ]; then
      echo -e "${YELLOW}[WARN]${NC} Release pipeline has $todo_count unconfigured TODO items in $_rel_path"
      echo "  Configure code signing, deployment secrets, and store credentials before production release."
      issues=$((issues + 1))
    else
      echo -e "${GREEN}  [OK]${NC} Release pipeline configured ($_rel_path; steps run: $_rel_how)"
    fi
  fi
fi

# Artifact existence checks: Phase 3→4
if [ "$current_phase" -ge 3 ] && [ "$skip_later_gate" -eq 0 ]; then   # BL-166-GATE-SCOPE
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
  #
  # BL-104 (scoring inversion): this used to be a two-armed `if / elif` with NO
  # `else`. 8/9 steps took the elif → WARN + issues++ → BLOCKED. But ZERO steps
  # is neither `-ge 9` nor `-gt 0`, so it fell off the end of the chain and the
  # gate PASSED IN SILENCE — a project that never ran Phase-3 validation at all
  # outscored one that ran eight of the nine steps. The `else` arm below closes
  # that hole.
  #
  # WHY IT BLOCKS (issues++), not a soft WARN: the arm immediately above blocks
  # at 1-8 steps. A gate where 8/9 blocks and 0/9 passes is not a gate. Zero is
  # strictly worse than eight, so it must score at least as harshly. Operators
  # who genuinely have no Phase-3 state simply have no process-state.json, and
  # the whole block is skipped — this arm only fires when the project HAS the
  # file and it records nothing, which is the "checklist was never started"
  # signal, not an absence of information.
  if [ -f ".claude/process-state.json" ] && command -v jq &>/dev/null; then
    p3_steps_done=$(jq '.phase3_validation.steps_completed | length' .claude/process-state.json 2>/dev/null || echo "0")
    case "$p3_steps_done" in ''|*[!0-9]*) p3_steps_done=0 ;; esac
    if [ "$p3_steps_done" -ge 9 ]; then
      echo -e "${GREEN}  [OK]${NC} Phase 3 process checklist: $p3_steps_done steps completed"
    elif [ "$p3_steps_done" -gt 0 ]; then
      echo -e "${YELLOW}[WARN]${NC} Phase 3 process checklist incomplete: $p3_steps_done/9 steps"
      issues=$((issues + 1))
    else
      echo -e "${YELLOW}[WARN]${NC} Phase 3 process checklist not started: 0/9 steps recorded in .claude/process-state.json"
      echo "  Run Phase 3 validation: scripts/process-checklist.sh --start-phase3"
      issues=$((issues + 1))   # BL-104-P3-ZERO
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
if [ "$current_phase" -ge 3 ] && [ "$skip_later_gate" -eq 0 ]; then   # BL-166-GATE-SCOPE
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

    # BL-104: how many reviews does this manifest actually ATTEST TO? A manifest
    # whose `.reviews[]` holds nothing `complete` records no review work at all —
    # see the BL-104-MANIFEST-ARM block below for why that number, not the mere
    # existence of the file, is what the non-enforced arm must score on.
    cpg_complete_reviews=$(jq '[ .reviews[]? | select((.status // "complete") == "complete") ] | length' "$MANIFEST" 2>/dev/null || echo "0")
    case "$cpg_complete_reviews" in ''|*[!0-9]*) cpg_complete_reviews=0 ;; esac

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
        elif [ "$cpg_complete_reviews" -eq 0 ]; then
          # BL-104 (scoring inversion): the no-manifest arm above WARNs and
          # BLOCKS (issues++) even on the non-enforced / light / grandfathered
          # track — that is the pre-BL-073 legacy contract and it is preserved.
          # This arm — manifest present but incomplete — WARNs and does NOT
          # block. Two [WARN] lines, opposite gate outcomes. The consequence:
          #
          #   (no manifest)                                  → BLOCKED
          #   echo '{"reviews":[]}' > …/review-manifest.json → PASSED
          #
          # Creating an empty file — recording ZERO reviews — turned a blocking
          # gate into a passing one. The bug is that the arms scored on FILE
          # EXISTENCE, not on review CONTENT. Fix: a manifest that attests to no
          # completed review is materially identical to no manifest, and blocks
          # the same way.
          #
          # DELIBERATELY NARROW. A PARTIAL manifest (>= 1 completed review) still
          # takes the WARN-only arm below, preserving the documented contract —
          # builders-guide.md § Phase 3→4: "track=light / personal: WARN only
          # (POC preserved); the bypass is logged." Real-but-incomplete review
          # work on a POC is not blocked. And the enforced standard/full FAIL
          # above is untouched: an empty manifest there still FAILs, as before.
          echo -e "${YELLOW}[WARN]${NC} Phase 3→4 review gate: the review manifest records ZERO completed reviews (missing: $cpg_missing_mandatory; track=$track) — an empty manifest is not a review; treated as no manifest."
          echo "  Run evaluation prompts before Phase 4: evaluation-prompts/Projects/run-reviews.sh"
          issues=$((issues + 1))   # BL-104-MANIFEST-ARM
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

        # BL-137-CI-TOOLS-SCOPE-BEGIN
        # Dogfood-3 F-DF3-002 (High): this increment made the generated
        # project's CI governance job STRUCTURALLY unpassable — the
        # required-tools contract names DEV-WORKSTATION tools (Semgrep CLI,
        # Snyk CLI, Claude Code) no CI runner carries (CI runs SAST via the
        # semgrep container and never holds Snyk auth or an
        # interactive CLI), so every push failed governance while the same
        # command exited 0 locally. The sibling install prompts already
        # hard-N under $CI; the BLOCK now scopes the same way: on a CI
        # runner the missing-tools list above stays printed (visibility)
        # with an explicit note, and is NOT counted as an issue — the
        # contract binds where the tools run, the dev workstation. Keyed
        # STRICTLY on $CI, never on TTY: scripted LOCAL runs (hooks, other
        # gates driving this one) must keep blocking.
        if [ -n "${CI:-}" ]; then
          echo -e "${CYAN}[note]${NC} CI runner detected (\$CI set): the required-tools contract binds on the dev workstation, not this runner — listed above for visibility, NOT blocking here (BL-137)."
        else
          issues=$((issues + 1))
        fi
        # BL-137-CI-TOOLS-SCOPE-END
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

# --- BL-124: Promotion-Ratchet PENDING markers (Phase 3→4) ---
# BL-124-PENDING-RATCHET-BEGIN
# upgrade-project.sh rewrites Light-track "SKIPPED" markers on
# PRODUCT_MANIFESTO.md Appendix A (Revenue Model) / Appendix C (Trademark &
# Legal) to "PENDING — required by track upgrade <old> → <new> on <date>" —
# a promise the promotion itself re-demands. Until BL-124, NOTHING read that
# marker: a project reached a tagged production release with the obligations
# still literally PENDING (Dogfood-2 F-DF2-014 — the central-question hole:
# the ratchet performed the re-demand and forgot to enforce it). This arm
# FAILS the 3→4 gate while the marker is present. Keyed on the WRITER'S
# LITERAL, not on track: track is spoofable (BL-084), and Light-track
# projects carry SKIPPED — never PENDING — so they are naturally unaffected.
# Keep the literal IN SYNC with upgrade-project.sh's writer
# (tests/test-bl124-pending-ratchet.sh T-writer-reader-wired pins both sides
# to one constant).
if [ "$current_phase" -ge 4 ] && [ -f "PRODUCT_MANIFESTO.md" ]; then
  echo ""
  echo -e "${BOLD}Promotion Ratchet Check (BL-124)${NC}"
  bl124_pending=$(grep -n "PENDING — required by track upgrade" PRODUCT_MANIFESTO.md 2>/dev/null) || bl124_pending=""
  if [ -n "$bl124_pending" ]; then
    echo -e "${RED}[FAIL]${NC} BL-124: PRODUCT_MANIFESTO.md still carries PENDING promotion marker(s) — the track upgrade re-demanded these obligations and they are unmet:"
    echo "$bl124_pending" | sed 's/^/    /'
    echo "    Fill the appendix (Revenue Model / Trademark & Legal), remove the PENDING marker, then re-run."
    issues=$((issues + 1))
  else
    echo -e "${GREEN}[OK]${NC} BL-124: no PENDING promotion markers in PRODUCT_MANIFESTO.md"
  fi
fi
# BL-124-PENDING-RATCHET-END

# --- BL-105: Competency Matrix visibility (WARN-first, never blocking) ---
# The builders-guide calls Appendix B "not advisory" with two MUSTs — and no
# gate, hook, or CI ever looked at it. WARN-first per the grandfather
# discipline (BL-073/BL-102): existing projects without the appendix must not
# hard-block; NO issues increment here (the BL-104 [WARN] trap — the
# increment is the verdict). Deeper domain scoring stays in
# validate.sh::check_competency (residual: it reads PROJECT_INTAKE.md and
# covers 4 of 9 domains — recorded in BL-105).
if [ "$current_phase" -ge 1 ] && [ -f "PRODUCT_MANIFESTO.md" ]; then
  if grep -q "## Appendix B" PRODUCT_MANIFESTO.md 2>/dev/null; then
    echo -e "${GREEN}  [OK]${NC} Competency Matrix: Appendix B present (deep check: scripts/validate.sh --competency)"
  else
    echo -e "${YELLOW}[WARN]${NC} Competency Matrix (Appendix B) not found in PRODUCT_MANIFESTO.md — the guide calls it 'not advisory'. WARN-first, not blocking."
  fi
fi

# --- BL-105: Phase-4 release checklist presence (Phase 4 was terminal + unforced) ---
# BL-105-PHASE4-GATE-BEGIN
# check-phase-gate.sh carried ZERO phase4_release cross-references: nothing
# ever forced the Phase-4 checklist to run, and Phase 4 is terminal — the
# walk reached a tagged release with the checklist never started. At
# current_phase >= 4 the checklist must at least EXIST in process-state
# (started via --start-phase4, which now also consults the 3→4 gate);
# incomplete steps are surfaced as information (Phase 4 is in-progress by
# nature), but a NEVER-STARTED checklist blocks. Excision-safe fence.
# Keyed on the FILE's REAL phase, not the (possibly --gate-elevated)
# current_phase variable: `--gate phase_3_to_4` elevates the variable to 4,
# and an elevated-keyed arm would demand a STARTED phase-4 checklist DURING
# the prospective 3→4 check — making --start-phase4's own gate consult
# SELF-BLOCKING (circular) on an otherwise-passing gate. This arm is a
# retroactive audit of projects that ARE at phase 4 on disk.
bl105_real_phase=0
if [ -f "$PHASE_STATE" ] && command -v jq >/dev/null 2>&1; then
  bl105_real_phase=$(jq -r '.current_phase // 0' "$PHASE_STATE" 2>/dev/null) || bl105_real_phase=0
  case "$bl105_real_phase" in ''|*[!0-9]*) bl105_real_phase=0 ;; esac
fi
if [ "$bl105_real_phase" -ge 4 ] && [ -f .claude/process-state.json ] && command -v jq >/dev/null 2>&1; then
  echo ""
  echo -e "${BOLD}Phase 4 Release Checklist (BL-105)${NC}"
  # Keyed on started_at, NOT key-existence: ensure_state_file pre-seeds an
  # empty phase4_release skeleton (started_at: null) on every invocation, so
  # the key exists on any project process-checklist ever touched. started_at
  # is written only by a real --start-phase4 (which now consults the gate).
  if ! jq -e '.phase4_release.started_at // empty' .claude/process-state.json >/dev/null 2>&1; then
    echo -e "${RED}[FAIL]${NC} BL-105: current_phase is $current_phase but the Phase-4 release checklist was NEVER STARTED (phase4_release.started_at is null) — run: scripts/process-checklist.sh --start-phase4"
    issues=$((issues + 1))
  else
    bl105_p4_done=$(jq -r '.phase4_release.steps_completed | length' .claude/process-state.json 2>/dev/null) || bl105_p4_done=0
    case "$bl105_p4_done" in ''|*[!0-9]*) bl105_p4_done=0 ;; esac
    echo -e "${GREEN}[OK]${NC} BL-105: Phase-4 checklist started ($bl105_p4_done/6 steps recorded — production_build, rollback_tested, go_live_verified, monitoring_configured, handoff_written, handoff_tested)"
  fi
fi
# BL-105-PHASE4-GATE-END

# --- BL-102: Market Signal / Go-No-Go evidence (Phase 1→2, WARN-first) ---
# BL-102-MARKET-SIGNAL-BEGIN
# builders-guide Step 1.1.5: at least one DOCUMENTED market signal before
# committing to architecture (Required on Standard/Full; SKIP on Light), with
# the Step 1.1 Go/No-Go decision recorded. The home is PRODUCT_MANIFESTO.md
# Appendix D (shipped by the template since BL-102). WARN-FIRST by design —
# deliberately NO `issues` increment: never hard-block on a slot existing
# projects don't have (BL-073 grandfather discipline; escalate to FAIL in a
# later wave once the fleet carries the appendix). THE [WARN] TRAP (BL-104):
# the increment, not the label, is the verdict — tests/
# test-bl102-market-signal-warn.sh pins the ABSENCE of an increment by
# exit-code parity, and its mutation case proves the pin catches an injected
# increment. Do not add one here casually. Track-keyed (not marker-keyed):
# acceptable for a WARN-only arm, and it is what BL-102 specifies.
if [ "$current_phase" -ge 2 ] && [ -f "PRODUCT_MANIFESTO.md" ]; then
  bl102_track=$(jq -r '.track // "standard"' "$PHASE_STATE" 2>/dev/null) || bl102_track="standard"
  case "$bl102_track" in ''|null) bl102_track="standard" ;; esac
  if [ "$bl102_track" != "light" ]; then
    echo ""
    echo -e "${BOLD}Market Signal Evidence Check (BL-102)${NC}"
    if ! grep -q "## Appendix D: Market Signal" PRODUCT_MANIFESTO.md; then
      # BL-102-MARKET-SIGNAL-WARNLINE
      echo -e "${YELLOW}[WARN]${NC} BL-102: no 'Appendix D: Market Signal & Go/No-Go Evidence' section in PRODUCT_MANIFESTO.md (track: $bl102_track). Step 1.1.5 requires at least one documented, re-fetchable signal before architecture. WARN-first — not blocking yet."
    elif grep -A 20 "## Appendix D: Market Signal" PRODUCT_MANIFESTO.md | grep -qE '\[e\.g\.|\[GO / NO-GO\]|\[customer interview /'; then
      echo -e "${YELLOW}[WARN]${NC} BL-102: Appendix D exists but still carries template placeholder text — existence is not evidence (the hollow-gate class). Fill the signal table and the Go/No-Go decision. WARN-first — not blocking yet."
    else
      echo -e "${GREEN}[OK]${NC} BL-102: Appendix D market-signal evidence present (track: $bl102_track)"
    fi
  fi
fi
# BL-102-MARKET-SIGNAL-END

# --- Brownfield adoption: stamp acceptance + loss detection ---
# BF-ADOPT-GATE-BEGIN
# The gate's half of the brownfield enabling arms (design §10-WP3 deliverable
# 4, §12-12). It READS the adoption flag through the single accessor and adds
# no logic to any existing predicate (§9).
#
# THE [WARN] TRAP APPLIES HERE AND THE CHOICE IS DELIBERATE. In this script the
# label is cosmetic — the exit predicate is `if [ $issues -eq 0 ]`, so an
# exemption is the ABSENCE of an increment and a block is its presence. This
# arm INCREMENTS, on purpose: a project whose committed manifest records an
# adoption while the live manifest no longer does has silently un-adopted, and
# a silent un-adoption is precisely the failure §12-12 says cannot be prevented
# and must therefore never be quiet. The upstream regenerating writer lives in
# another repository; the only thing in this design's control is refusing to
# pass the gate while the record is missing. Removing the increment — or the
# detector it calls — turns the failure back into silence.
#
# DELIBERATELY NOT FENCED BY `skip_later_gate`. BL-166 confines a `--gate`
# scoped run to the NAMED gate's checks, and that fence is right for checks
# that BELONG to a later gate. This one belongs to no gate: the adoption record
# is a precondition of every arm that reads the flag, so a scoped run that
# passed while the record was missing would be the same silence under a
# narrower heading. Stated here because the omission is a decision, not an
# oversight.
if command -v soif_adoption_integrity_lost >/dev/null 2>&1; then
  if soif_adoption_integrity_lost ".claude/manifest.json"; then
    echo ""
    echo -e "${BOLD}Adoption Stamp Integrity${NC}"
    soif_adoption_report_loss ".claude/manifest.json"
    issues=$((issues + 1))   # BF-ADOPT-GATE-ISSUES
  elif soif_adoption_adopted ".claude/manifest.json"; then
    echo ""
    echo -e "${BOLD}Adoption Stamp Integrity${NC}"
    # `|| var=…` is not decoration: this script runs under `set -e`, and a bare
    # `var=$(cmd)` takes cmd's exit status, so a jq that failed here would abort
    # the WHOLE gate mid-run — a reporting line taking the enforcement down with
    # it. The fallbacks keep a cosmetic read cosmetic.
    cpg_adopt_scenario=$(soif_adoption_read ".claude/manifest.json" '.adoption.scenario // "unknown"') || cpg_adopt_scenario="unknown"
    cpg_adopt_at=$(soif_adoption_read ".claude/manifest.json" '.adoption.adoptedAt // "unknown"') || cpg_adopt_at="unknown"
    echo -e "${GREEN}[OK]${NC} Adoption stamp present and intact (scenario: $cpg_adopt_scenario, adopted: $cpg_adopt_at)"
  fi
fi
# BF-ADOPT-GATE-END

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
