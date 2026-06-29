#!/usr/bin/env bash
# tests/test-upgrade-project-retroactive-section.sh
#
# Regression test for the upgrade-project.sh half of tier-crosscheck-5
# (audit S3 closure): when a project is upgraded from personal to
# organizational, scripts/upgrade-project.sh:1610-1626 stamps a new
# "Retroactive Phase 1 → Phase 2 STA Approval" section into the
# regenerated APPROVAL_LOG.md. This section is the artifact that
# scripts/check-phase-gate.sh (lines 519-555) reads to emit the
# non-blocking WARN governed by tests/test-check-phase-gate-retroactive-
# approval.sh.
#
# PR #104 verifier (Wave 4) flagged that the original closure only
# tested the check-phase-gate.sh half — the stamping logic in
# upgrade-project.sh was verified only by hand-rolling the section into
# a fixture. Deleting upgrade-project.sh:1610-1626 left the suite green.
#
# This test runs the REAL scripts/upgrade-project.sh against a fresh
# personal project end-to-end and inspects the resulting APPROVAL_LOG.md
# for the new retroactive section header + frontmatter key
# (`upgraded_from: personal`) + the four field rows the
# check-phase-gate.sh parser depends on (Gate / Approver / Date /
# Reference).
#
# RED-on-main / GREEN-on-PR evidence:
#   - On origin/main, scripts/upgrade-project.sh does not emit the
#     "Retroactive Phase 1 → Phase 2 STA Approval" header at all (the
#     stamping block at lines 1610-1626 does not exist), so T1 fails.
#   - On PR #104, the stamping block is present and the section header
#     + four rows land in the regenerated log → T1 passes.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
UPGRADE="$REPO_ROOT/scripts/upgrade-project.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Seed a personal-deployment phase-state.json matching init.sh:1601-1616
# schema. Caller passes the project dir.
seed_personal_phase_state() {
  local dir="$1"
  mkdir -p "$dir/.claude"
  cat > "$dir/.claude/phase-state.json" <<'JSON'
{
  "project": "test-retroactive-section",
  "framework_version": "1.0",
  "current_phase": 2,
  "track": "standard",
  "deployment": "personal",
  "poc_mode": null,
  "compliance_ready": false,
  "gates": {"phase_0_to_1": "2026-04-01", "phase_1_to_2": "2026-04-15", "phase_3_to_4": null}
}
JSON
  # tier-crosscheck-6: seed phase1_artifacts so the upgrade-project
  # personal→organizational refusal doesn't fire (we're testing the
  # retroactive STA section stamping, not the new ZDR gate).
  cat > "$dir/.claude/process-state.json" <<'JSON'
{"phase1_artifacts":{"data_classification":"internal","zdr_attested":true}}
JSON
}

# Seed a personal APPROVAL_LOG.md (deployment: personal frontmatter) so
# upgrade-project.sh:1467-1472 detects it as a personal-format log and
# triggers the organizational restructure that stamps the retroactive
# section. Without this seed, the upgrade-project.sh path skips the
# restructure entirely.
seed_personal_approval_log() {
  local dir="$1"
  cat > "$dir/APPROVAL_LOG.md" <<'MD'
---
project: test-retroactive-section
deployment: personal
created: 2026-04-01
framework: Solo Orchestrator v1.0
---

# Approval Log (Personal Deployment)

## Phase Gate: Phase 0 → Phase 1
| Field | Value |
|---|---|
| **Gate** | Phase 0 → Phase 1 |
| **Reviewer** | Self |
| **Date** | 2026-04-01 |

## Phase Gate: Phase 1 → Phase 2
| Field | Value |
|---|---|
| **Gate** | Phase 1 → Phase 2 |
| **Reviewer** | Self |
| **Date** | 2026-04-15 |
MD
}

# T1: run scripts/upgrade-project.sh --deployment organizational
# end-to-end and verify the regenerated APPROVAL_LOG.md carries the
# new "Retroactive Phase 1 → Phase 2 STA Approval" section.
t1_personal_to_org_stamps_retroactive_section() {
  local T; T=$(mktemp -d); local P="$T/p"
  mkdir -p "$P"
  ( cd "$P" && git init -q \
      && git config user.email t@t.l \
      && git config user.name t ) >/dev/null 2>&1
  seed_personal_phase_state "$P"
  seed_personal_approval_log "$P"
  ( cd "$P" && git add -A && git commit -q -m "personal seed" ) >/dev/null 2>&1

  local rc=0
  ( cd "$P" && bash "$UPGRADE" --deployment organizational --non-interactive ) > "$T/log" 2>&1 || rc=$?

  if [ "$rc" -ne 0 ]; then
    fail_ "T1" "upgrade-project.sh --deployment organizational returned rc=$rc; log tail:\n$(tail -15 "$T/log")"
    rm -rf "$T"; return
  fi

  if [ ! -f "$P/APPROVAL_LOG.md" ]; then
    fail_ "T1" "APPROVAL_LOG.md missing after upgrade"
    rm -rf "$T"; return
  fi

  # T1a — frontmatter: deployment flipped to organizational AND the
  # upgraded_from key is stamped. The frontmatter key is what
  # check-phase-gate.sh:536 grep-matches to activate the retroactive WARN.
  if ! grep -q '^deployment: organizational' "$P/APPROVAL_LOG.md"; then
    fail_ "T1a" "APPROVAL_LOG.md missing 'deployment: organizational' frontmatter; head:\n$(head -8 "$P/APPROVAL_LOG.md")"
    rm -rf "$T"; return
  fi
  if ! grep -q '^upgraded_from: personal' "$P/APPROVAL_LOG.md"; then
    fail_ "T1a" "APPROVAL_LOG.md missing 'upgraded_from: personal' frontmatter (check-phase-gate.sh:536 gate would not fire); head:\n$(head -8 "$P/APPROVAL_LOG.md")"
    rm -rf "$T"; return
  fi

  # T1b — the new Retroactive section header is present. This is the
  # exact string scripts/upgrade-project.sh:1610 stamps and
  # scripts/check-phase-gate.sh:538 greps for via "Retroactive Phase 1.*Phase 2.*STA".
  if ! grep -qE "Retroactive Phase 1.*Phase 2.*STA Approval" "$P/APPROVAL_LOG.md"; then
    fail_ "T1b" "APPROVAL_LOG.md missing 'Retroactive Phase 1 → Phase 2 STA Approval' section header (scripts/upgrade-project.sh:1610 stamping regression); APPROVAL_LOG tail:\n$(tail -30 "$P/APPROVAL_LOG.md")"
    rm -rf "$T"; return
  fi

  # T1c — the four field rows the check-phase-gate.sh parser depends
  # on are present (Gate / Approver / Date / Reference). Without these
  # the WARN/OK emission at scripts/check-phase-gate.sh:545-552 cannot
  # extract Approver and Date values from the table.
  local retro_section
  retro_section=$(grep -A 16 "Retroactive Phase 1.*Phase 2.*STA Approval" "$P/APPROVAL_LOG.md")
  local missing=""
  echo "$retro_section" | grep -qE '\*\*Gate\*\*[[:space:]]*\|[[:space:]]*Retroactive Phase 1' \
    || missing="$missing Gate"
  echo "$retro_section" | grep -qE '\*\*Approver\*\*[[:space:]]*\|' \
    || missing="$missing Approver"
  echo "$retro_section" | grep -qE '\*\*Date\*\*[[:space:]]*\|' \
    || missing="$missing Date"
  echo "$retro_section" | grep -qE '\*\*Reference\*\*[[:space:]]*\|.*builders-guide\.md.*Phase 1.*807' \
    || missing="$missing Reference"

  if [ -n "$missing" ]; then
    fail_ "T1c" "Retroactive section missing required field row(s):$missing. Section dump:\n$retro_section"
    rm -rf "$T"; return
  fi

  pass "T1: scripts/upgrade-project.sh --deployment organizational stamps Retroactive Phase 1→2 STA Approval section (header + Gate/Approver/Date/Reference rows + upgraded_from frontmatter)"

  # T2 — the personal log is preserved as APPROVAL_LOG.md.personal-backup
  # (scripts/upgrade-project.sh:1474). This is part of the same stamping
  # block; if the backup vanishes the upgrade has regressed away from
  # the audit-mandated preservation behavior.
  if [ ! -f "$P/APPROVAL_LOG.md.personal-backup" ]; then
    fail_ "T2" "APPROVAL_LOG.md.personal-backup missing (scripts/upgrade-project.sh:1474 backup regression); files in dir:\n$(ls "$P/")"
    rm -rf "$T"; return
  fi
  if ! grep -q '^deployment: personal' "$P/APPROVAL_LOG.md.personal-backup"; then
    fail_ "T2" "APPROVAL_LOG.md.personal-backup is not the original personal-deployment log"
    rm -rf "$T"; return
  fi
  pass "T2: original personal APPROVAL_LOG.md preserved as APPROVAL_LOG.md.personal-backup"

  rm -rf "$T"
}

echo "== tests/test-upgrade-project-retroactive-section.sh =="
t1_personal_to_org_stamps_retroactive_section

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
