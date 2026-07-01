#!/usr/bin/env bash
set -euo pipefail

# Solo Orchestrator — Maintenance Cadence Check
# Checks whether scheduled maintenance activities are overdue
# by reading CHANGELOG.md dates and SBOM modification time.
#
# Usage: bash scripts/check-maintenance.sh
#
# Exit codes:
#   0 — all maintenance cadences current
#   1 — one or more cadences overdue
#   2 — could not determine (missing data)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# BL-046: uses print_info / print_ok / print_warn only — source core subset.
source "$SCRIPT_DIR/lib/helpers-core.sh"

echo -e "${BOLD}Maintenance Cadence Check${NC}"
echo ""

overdue=0
warnings=0
now_epoch=$(date +%s)

# --- Monthly check: CHANGELOG.md should have an entry within 35 days ---
if [ -f "CHANGELOG.md" ]; then
  # Get the last modification date of CHANGELOG.md from git
  last_changelog_date=$(git log -1 --format='%ai' -- CHANGELOG.md 2>/dev/null | cut -d' ' -f1 || echo "")
  if [ -n "$last_changelog_date" ]; then
    last_epoch=$(date -j -f "%Y-%m-%d" "$last_changelog_date" +%s 2>/dev/null || date -d "$last_changelog_date" +%s 2>/dev/null || echo "0")
    if [ "$last_epoch" -gt 0 ]; then
      days_since=$(( (now_epoch - last_epoch) / 86400 ))
      if [ "$days_since" -gt 35 ]; then
        print_warn "Monthly maintenance overdue: CHANGELOG.md last updated $days_since days ago (threshold: 35 days)"
        overdue=$((overdue + 1))
      else
        print_ok "CHANGELOG.md updated $days_since days ago (monthly cadence: current)"
      fi
    fi
  else
    print_info "CHANGELOG.md has no git history — cannot determine age"
  fi
else
  print_info "No CHANGELOG.md — maintenance check not applicable"
fi

# --- Monthly check: SBOM should be regenerated within 35 days ---
if [ -f "sbom.json" ]; then
  last_sbom_date=$(git log -1 --format='%ai' -- sbom.json 2>/dev/null | cut -d' ' -f1 || echo "")
  if [ -n "$last_sbom_date" ]; then
    last_epoch=$(date -j -f "%Y-%m-%d" "$last_sbom_date" +%s 2>/dev/null || date -d "$last_sbom_date" +%s 2>/dev/null || echo "0")
    if [ "$last_epoch" -gt 0 ]; then
      days_since=$(( (now_epoch - last_epoch) / 86400 ))
      if [ "$days_since" -gt 35 ]; then
        print_warn "SBOM refresh overdue: sbom.json last updated $days_since days ago (threshold: 35 days)"
        overdue=$((overdue + 1))
      else
        print_ok "sbom.json updated $days_since days ago (monthly cadence: current)"
      fi
    fi
  fi
fi

# --- Quarterly check: last dependency audit ---
# Look for recent pip-audit/snyk/dependency scan results
if [ -d "docs/test-results" ]; then
  latest_dep_scan=$(ls -t docs/test-results/*snyk* docs/test-results/*dep* docs/test-results/*audit* 2>/dev/null | head -1 || echo "")
  if [ -n "$latest_dep_scan" ]; then
    scan_date=$(echo "$latest_dep_scan" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || echo "")
    if [ -n "$scan_date" ]; then
      last_epoch=$(date -j -f "%Y-%m-%d" "$scan_date" +%s 2>/dev/null || date -d "$scan_date" +%s 2>/dev/null || echo "0")
      if [ "$last_epoch" -gt 0 ]; then
        days_since=$(( (now_epoch - last_epoch) / 86400 ))
        if [ "$days_since" -gt 95 ]; then
          print_warn "Quarterly dependency audit overdue: last scan $days_since days ago (threshold: 95 days)"
          overdue=$((overdue + 1))
        else
          print_ok "Dependency scan $days_since days ago (quarterly cadence: current)"
        fi
      fi
    fi
  fi
fi

# --- Biannual check: full security re-audit ---
# Look for Phase 3-style security scan results within 185 days
if [ -d "docs/test-results" ]; then
  latest_security=$(ls -t docs/test-results/*semgrep* docs/test-results/*sast* 2>/dev/null | head -1 || echo "")
  if [ -n "$latest_security" ]; then
    scan_date=$(echo "$latest_security" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || echo "")
    if [ -n "$scan_date" ]; then
      last_epoch=$(date -j -f "%Y-%m-%d" "$scan_date" +%s 2>/dev/null || date -d "$scan_date" +%s 2>/dev/null || echo "0")
      if [ "$last_epoch" -gt 0 ]; then
        days_since=$(( (now_epoch - last_epoch) / 86400 ))
        if [ "$days_since" -gt 185 ]; then
          print_warn "Biannual security re-audit overdue: last full scan $days_since days ago (threshold: 185 days)"
          overdue=$((overdue + 1))
        else
          print_ok "Security scan $days_since days ago (biannual cadence: current)"
        fi
      fi
    fi
  fi
fi

echo ""
if [ "$overdue" -gt 0 ]; then
  echo -e "${YELLOW}${BOLD}$overdue maintenance cadence(s) overdue.${NC}"
  echo ""
  echo "Recommended actions:"
  echo "  Monthly: Run dependency audit, security patches, SBOM update, error dashboard review"
  echo "  Quarterly: Performance comparison, cost review, post-MVP backlog prioritization"
  echo "  Biannually: Full dependency audit, Phase 3 re-run, platform requirement review"
  echo ""
  echo "After maintenance, commit changes with 'chore: monthly maintenance [date]' to update the timestamps."
  exit 1
else
  echo -e "${GREEN}${BOLD}All maintenance cadences current.${NC}"
  exit 0
fi
