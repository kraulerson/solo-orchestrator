#!/usr/bin/env bash
# tests/test-check-phase-gate-retroactive-approval.sh
#
# Regression test for tier-crosscheck-5 (audit S3 closure):
#   The Personal → Organizational upgrade path in
#   scripts/upgrade-project.sh restructures APPROVAL_LOG.md and stamps
#   the frontmatter with `upgraded_from: personal`. Baseline §4
#   (docs/builders-guide.md line 807) requires that, after such an
#   upgrade, the Senior Technical Authority retroactively review and
#   approve the existing Project Bible — yet nothing in the code
#   enforces this. The previous APPROVAL_LOG.md template didn't even
#   carry a row for the retroactive approver/date.
#
# Fix (option B from the audit recommendation):
#   1. upgrade-project.sh's organizational APPROVAL_LOG.md restructure
#      now includes a dedicated "Retroactive Phase 1 → Phase 2 STA
#      Approval" section with Approver/Date fields.
#   2. scripts/check-phase-gate.sh detects this state — frontmatter
#      `upgraded_from: personal` AND current_phase >= 2 — and emits a
#      non-blocking WARN when the Retroactive Approver or Date is
#      blank, citing builders-guide.md § Phase 1 (line 807).
#
# This test exercises check-phase-gate.sh against three scenarios:
#   T1: upgraded project with current_phase >= 2 and blank retroactive
#       approval rows → must emit WARN that mentions "Retroactive".
#   T2: same scenario but with Approver + Date filled in → no WARN
#       about retroactive approval.
#   T3: project NOT upgraded from personal (no `upgraded_from` key) →
#       check-phase-gate.sh must NOT emit the retroactive WARN even
#       when current_phase >= 2.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-phase-gate.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

setup() {
  TMP=$(mktemp -d)
  PROJ="$TMP/p"
  mkdir -p "$PROJ/.claude"
  ( cd "$PROJ" && git init -q \
      && git config user.email "ops@example.com" \
      && git config user.name "Ops" )
  # Phase state — current_phase 2 so the new check fires.
  cat > "$PROJ/.claude/phase-state.json" <<'JSON'
{
  "current_phase": 2,
  "project": "tier-crosscheck-5-fixture",
  "deployment": "organizational",
  "gates": {"phase_0_to_1": "2026-04-01", "phase_1_to_2": "2026-04-15"}
}
JSON
  # Minimal PROJECT_BIBLE.md (so the Phase 1→2 artifact check passes
  # and we observe only the retroactive WARN).
  printf '## 1. one\n## 2. two\n## 3. three\n## 4. four\n## 5. five\n## 6. six\n## 7. seven\n## 8. eight\n## 9. nine\n## 10. ten\n## 11. eleven\n## 12. twelve\n## 13. thirteen\n## 14. fourteen\n' > "$PROJ/PROJECT_BIBLE.md"
  # Minimal PRODUCT_MANIFESTO.md (Phase 0→1 artifact).
  cat > "$PROJ/PRODUCT_MANIFESTO.md" <<'MANIFESTO'
# Product Manifesto

## Problem Statement
A real problem.

## Compliance Screening
Required by IT Security.

## Cost & Maintenance Discussion
Acknowledged.

## Stakeholder Map
Sponsor, Owner.
MANIFESTO
}
teardown() { rm -rf "$TMP"; }

# Build an upgraded-from-personal APPROVAL_LOG.md. The flag toggles
# whether the Retroactive Approver/Date rows are filled in.
write_upgraded_log() {
  local fill_retroactive="$1"
  local approver date
  if [ "$fill_retroactive" = "true" ]; then
    approver="Jane Doe"; date="2026-04-20"
  else
    approver=""; date=""
  fi
  cat > "$PROJ/APPROVAL_LOG.md" <<MD
---
project: tier-crosscheck-5-fixture
deployment: organizational
created: 2026-04-15
upgraded_from: personal
framework: Solo Orchestrator v1.0
---

# Approval Log

## Phase Gate: Phase 0 → Phase 1
| Field | Value |
|---|---|
| **Gate** | Phase 0 → Phase 1 |
| **Approver** | Sponsor |
| **Date** | 2026-04-01 |

## Phase Gate: Phase 1 → Phase 2
| Field | Value |
|---|---|
| **Gate** | Phase 1 → Phase 2 |
| **Approver** | Sponsor |
| **Date** | 2026-04-15 |

## Retroactive Phase 1 → Phase 2 STA Approval
| Field | Value |
|---|---|
| **Gate** | Retroactive Phase 1 → Phase 2 (STA) |
| **Approver** | $approver |
| **Date** | $date |
| **Reference** | See docs/builders-guide.md § Phase 1 (line 807) |
MD
}

write_non_upgraded_org_log() {
  cat > "$PROJ/APPROVAL_LOG.md" <<'MD'
---
project: tier-crosscheck-5-fixture
deployment: organizational
created: 2026-04-15
framework: Solo Orchestrator v1.0
---

# Approval Log

## Phase Gate: Phase 0 → Phase 1
| Field | Value |
|---|---|
| **Gate** | Phase 0 → Phase 1 |
| **Approver** | Sponsor |
| **Date** | 2026-04-01 |

## Phase Gate: Phase 1 → Phase 2
| Field | Value |
|---|---|
| **Gate** | Phase 1 → Phase 2 |
| **Approver** | Sponsor |
| **Date** | 2026-04-15 |
MD
}

# T1: upgraded_from=personal + blank retroactive rows → WARN emitted.
t1_upgraded_blank_retroactive_emits_warn() {
  setup
  write_upgraded_log "false"
  local output
  output=$( cd "$PROJ" && bash "$SCRIPT" 2>&1 ) || true
  if echo "$output" | grep -qiE "WARN.*retroactive|Retroactive STA Approval"; then
    pass "T1: upgraded_from=personal + blank retroactive rows → check-phase-gate.sh emits Retroactive WARN"
  else
    fail_ "T1" "expected WARN mentioning 'retroactive'; got:\n$output"
  fi
  teardown
}

# T2: upgraded_from=personal + filled retroactive rows → no Retroactive WARN.
t2_upgraded_filled_retroactive_no_warn() {
  setup
  write_upgraded_log "true"
  local output
  output=$( cd "$PROJ" && bash "$SCRIPT" 2>&1 ) || true
  if echo "$output" | grep -qiE "WARN.*retroactive: project upgraded from personal but.*incomplete|WARN.*retroactive: project upgraded from personal but APPROVAL_LOG\.md has no"; then
    fail_ "T2" "expected NO Retroactive WARN when approver+date filled; got:\n$output"
  else
    pass "T2: upgraded_from=personal + Approver+Date filled → no Retroactive WARN"
  fi
  teardown
}

# T3: NOT upgraded_from=personal → check must skip the retroactive WARN.
t3_non_upgraded_no_retroactive_warn() {
  setup
  write_non_upgraded_org_log
  local output
  output=$( cd "$PROJ" && bash "$SCRIPT" 2>&1 ) || true
  if echo "$output" | grep -qiE "WARN.*retroactive: project upgraded from personal but.*incomplete|WARN.*retroactive: project upgraded from personal but APPROVAL_LOG\.md has no"; then
    fail_ "T3" "expected NO Retroactive WARN when not upgraded_from=personal; got:\n$output"
  else
    pass "T3: non-upgraded organizational project does NOT trigger Retroactive WARN"
  fi
  teardown
}

echo "== tests/test-check-phase-gate-retroactive-approval.sh =="
t1_upgraded_blank_retroactive_emits_warn
t2_upgraded_filled_retroactive_no_warn
t3_non_upgraded_no_retroactive_warn

echo ""
echo "== Total: $((PASSED + FAILED)) | Passed: $PASSED | Failed: $FAILED =="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
