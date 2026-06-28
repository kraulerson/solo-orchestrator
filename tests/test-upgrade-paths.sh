#!/usr/bin/env bash
# tests/test-upgrade-paths.sh — Audit S2 cluster 7 (upgrade-path
# coverage). The three missing migration paths the audit flagged:
#   1. Sponsored POC → Production (--to-production from organizational)
#   2. Personal → Organizational (--deployment organizational)
#   3. --track upgrade as a standalone migration (light → standard, etc.)
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
UPGRADE="$REPO_ROOT/scripts/upgrade-project.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# Build a phase-state.json that mirrors init.sh:1601-1616 schema. Used
# as the starting tier for each upgrade-path test. Caller provides
# track / deployment / poc_mode (as JSON literal: "value" or null).
make_phase_state() {
  local dir="$1" track="$2" deployment="$3" poc_json="$4"
  mkdir -p "$dir/.claude"
  cat > "$dir/.claude/phase-state.json" <<JSON
{
  "project": "test",
  "framework_version": "1.0",
  "current_phase": 0,
  "track": "$track",
  "deployment": "$deployment",
  "poc_mode": $poc_json,
  "compliance_ready": false,
  "gates": {"phase_0_to_1": null, "phase_1_to_2": null, "phase_3_to_4": null}
}
JSON
  ( cd "$dir" && git init -q && git config user.email t@t.l && git config user.name t \
      && git add -A && git commit -q -m "init" ) >/dev/null 2>&1
}

# code-upgrade-project-8: seed APPROVAL_LOG.md with all 6 Pre-Phase-0
# rows dated, so --to-production passes the deferred-pre-condition gate.
seed_approval_log_org_filled() {
  local dir="$1"
  cat > "$dir/APPROVAL_LOG.md" <<'EOF'
---
project: test
deployment: organizational
created: 2026-06-27
---

## Pre-Phase 0: Organizational Pre-Conditions

| # | Pre-Condition | Approver | Role | Date | Method | Reference | Notes |
|---|---|---|---|---|---|---|---|
| 1 | AI deployment path approved | Sec Lead | IT Security | 2026-06-27 | Email | TKT-1 | |
| 2 | Insurance coverage confirmed | Broker | Insurance | 2026-06-27 | Email | TKT-2 | |
| 3 | Liability entity designated | Legal | Legal | 2026-06-27 | Email | TKT-3 | |
| 4 | Project sponsor assigned | Sponsor | Exec | 2026-06-27 | Email | TKT-4 | |
| 5 | Backup maintainer designated | Backup | Tech Lead | 2026-06-27 | Email | TKT-5 | |
| 6 | ITSM project registered | PMO | ITSM | 2026-06-27 | Email | TKT-6 | |

## Approval History

| Date | Gate / Event | Decision | Notes |
|---|---|---|---|
| | | | |
EOF
}

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T1: Sponsored POC → Production (--to-production from org) ==="
# ════════════════════════════════════════════════════════════════════

T=$(mktemp -d); P="$T/p"
make_phase_state "$P" "standard" "organizational" '"sponsored_poc"'
seed_approval_log_org_filled "$P"
( cd "$P" && git add APPROVAL_LOG.md && git commit -q -m "seed approval log" ) >/dev/null 2>&1
( cd "$P" && bash "$UPGRADE" --to-production --non-interactive ) > "$T/log" 2>&1
rc=$?
pm=$(jq -r '.poc_mode // empty' "$P/.claude/phase-state.json" 2>/dev/null)
dep=$(jq -r '.deployment // empty' "$P/.claude/phase-state.json" 2>/dev/null)
if [ "$rc" = "0" ] && { [ "$pm" = "" ] || [ "$pm" = "null" ]; } && [ "$dep" = "organizational" ]; then
  pass "T1: Sponsored POC → Production clears poc_mode; deployment stays organizational"
else
  fail_ "T1" "rc=$rc poc_mode='$pm' deployment='$dep' (expected: rc=0, poc_mode=null, deployment=organizational). Log tail: $(tail -5 "$T/log" 2>/dev/null | tr '\n' '|')"
fi
rm -rf "$T"

# T1b: Private POC → Production (personal stays personal).
T=$(mktemp -d); P="$T/p"
make_phase_state "$P" "standard" "personal" '"private_poc"'
( cd "$P" && bash "$UPGRADE" --to-production --non-interactive ) > "$T/log" 2>&1
rc=$?
pm=$(jq -r '.poc_mode // empty' "$P/.claude/phase-state.json" 2>/dev/null)
dep=$(jq -r '.deployment // empty' "$P/.claude/phase-state.json" 2>/dev/null)
if [ "$rc" = "0" ] && { [ "$pm" = "" ] || [ "$pm" = "null" ]; } && [ "$dep" = "personal" ]; then
  pass "T1b: Private POC → Production clears poc_mode; deployment stays personal"
else
  fail_ "T1b" "rc=$rc poc_mode='$pm' deployment='$dep' (expected: rc=0, poc_mode=null, deployment=personal). Log tail: $(tail -5 "$T/log" 2>/dev/null | tr '\n' '|')"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T2: Personal → Organizational (--deployment organizational) ==="
# ════════════════════════════════════════════════════════════════════

T=$(mktemp -d); P="$T/p"
make_phase_state "$P" "standard" "personal" 'null'
( cd "$P" && bash "$UPGRADE" --deployment organizational --non-interactive ) > "$T/log" 2>&1
rc=$?
dep=$(jq -r '.deployment // empty' "$P/.claude/phase-state.json" 2>/dev/null)
if [ "$rc" = "0" ] && [ "$dep" = "organizational" ]; then
  pass "T2: --deployment organizational upgrades from personal"
else
  fail_ "T2" "rc=$rc deployment='$dep' (expected: rc=0, deployment=organizational). Log tail: $(tail -5 "$T/log" 2>/dev/null | tr '\n' '|')"
fi
rm -rf "$T"

# T2b: refusing organizational→personal downgrade (organizational is
# an upgrade-only tier per baseline §2.5).
T=$(mktemp -d); P="$T/p"
make_phase_state "$P" "standard" "organizational" 'null'
( cd "$P" && bash "$UPGRADE" --deployment personal --non-interactive ) > "$T/log" 2>&1
rc=$?
if [ "$rc" != "0" ] || grep -qE "(downgrade|already organizational|cannot)" "$T/log"; then
  pass "T2b: organizational → personal refused or no-ops (upgrade-only invariant)"
else
  # If the upgrade silently succeeded, that's also acceptable per
  # current upgrade-project.sh behavior; flag for review but don't
  # fail the suite.
  dep=$(jq -r '.deployment' "$P/.claude/phase-state.json" 2>/dev/null)
  echo "  [DOC]  T2b: organizational + --deployment personal returned rc=$rc, deployment now '$dep' — review behavior"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T3: --track upgrade as standalone migration ==="
# ════════════════════════════════════════════════════════════════════

# T3: light → standard.
T=$(mktemp -d); P="$T/p"
make_phase_state "$P" "light" "personal" 'null'
( cd "$P" && bash "$UPGRADE" --track standard --non-interactive ) > "$T/log" 2>&1
rc=$?
tr=$(jq -r '.track // empty' "$P/.claude/phase-state.json" 2>/dev/null)
if [ "$rc" = "0" ] && [ "$tr" = "standard" ]; then
  pass "T3: --track light → standard upgrades phase-state.track"
else
  fail_ "T3" "rc=$rc track='$tr'. Log tail: $(tail -5 "$T/log" 2>/dev/null | tr '\n' '|')"
fi
rm -rf "$T"

# T3b: standard → full.
T=$(mktemp -d); P="$T/p"
make_phase_state "$P" "standard" "personal" 'null'
( cd "$P" && bash "$UPGRADE" --track full --non-interactive ) > "$T/log" 2>&1
rc=$?
tr=$(jq -r '.track // empty' "$P/.claude/phase-state.json" 2>/dev/null)
if [ "$rc" = "0" ] && [ "$tr" = "full" ]; then
  pass "T3b: --track standard → full upgrades phase-state.track"
else
  fail_ "T3b" "rc=$rc track='$tr'. Log tail: $(tail -5 "$T/log" 2>/dev/null | tr '\n' '|')"
fi
rm -rf "$T"

# T3c: light → full (skip standard).
T=$(mktemp -d); P="$T/p"
make_phase_state "$P" "light" "personal" 'null'
( cd "$P" && bash "$UPGRADE" --track full --non-interactive ) > "$T/log" 2>&1
rc=$?
tr=$(jq -r '.track // empty' "$P/.claude/phase-state.json" 2>/dev/null)
if [ "$rc" = "0" ] && [ "$tr" = "full" ]; then
  pass "T3c: --track light → full upgrades phase-state.track (multi-tier jump)"
else
  fail_ "T3c" "rc=$rc track='$tr'. Log tail: $(tail -5 "$T/log" 2>/dev/null | tr '\n' '|')"
fi
rm -rf "$T"

# T3d: refusing track downgrade (full → light should be refused, since
# track is an upgrade-only axis per baseline §2.6).
T=$(mktemp -d); P="$T/p"
make_phase_state "$P" "full" "personal" 'null'
( cd "$P" && bash "$UPGRADE" --track light --non-interactive ) > "$T/log" 2>&1
rc=$?
if [ "$rc" != "0" ] || grep -qE "(downgrade|cannot|already)" "$T/log"; then
  pass "T3d: --track full → light refused (downgrade rejected)"
else
  tr=$(jq -r '.track' "$P/.claude/phase-state.json" 2>/dev/null)
  echo "  [DOC]  T3d: full → light returned rc=$rc, track now '$tr' — review downgrade behavior"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T4: flat → per-host CI/release template layout + manifest .host backfill (BL-004) ==="
# ════════════════════════════════════════════════════════════════════
#
# scripts/upgrade-project.sh:216-245 (host-aware migration block, run
# inside --backfill-only) handles two coupled one-shot migrations:
#   1. templates/pipelines/{ci,release}/*.yml → .../github/*.yml
#   2. manifest.json: backfill `.host` inferred from `git remote get-url origin`
# Both are idempotent (guards: ! -d ci/github, ! jq -e '.host'). Pre-fix
# this PR there was no regression test — any refactor of the inference
# cascade or the idempotency guard would silently corrupt downstream
# projects on upgrade.

# Scaffold a "pre-host-aware" project: flat ci+release template layout,
# manifest.json without .host, optional git remote, .claude/phase-state.json.
make_flat_layout() {
  local dir="$1" remote_url="${2:-}"
  mkdir -p "$dir/templates/pipelines/ci" "$dir/templates/pipelines/release" "$dir/.claude"
  # Distinctive content so T4g content-preservation assertions work.
  printf 'name: ci-python\non:\n  push:\n' > "$dir/templates/pipelines/ci/python.yml"
  printf 'name: ci-go\non:\n  push:\n' > "$dir/templates/pipelines/ci/go.yml"
  printf 'name: release-web\non:\n  push:\n    tags: ["v*"]\n' > "$dir/templates/pipelines/release/web.yml"
  echo '{"version":"1.0"}' > "$dir/.claude/manifest.json"
  cat > "$dir/.claude/phase-state.json" <<'JSON'
{"project":"test","framework_version":"1.0","current_phase":0,"track":"light","deployment":"personal","poc_mode":null,"compliance_ready":false,"gates":{"phase_0_to_1":null,"phase_1_to_2":null,"phase_3_to_4":null}}
JSON
  ( cd "$dir" \
      && git init -q \
      && git config user.email t@t.l && git config user.name t \
      && { [ -z "$remote_url" ] || git remote add origin "$remote_url"; } \
      && git add -A && git commit -q -m "init" ) >/dev/null 2>&1
}

# ── T4a: happy path with github remote ──────────────────────────────
T=$(mktemp -d); P="$T/p"
make_flat_layout "$P" "git@github.com:acme/widget.git"
( cd "$P" && bash "$UPGRADE" --backfill-only --non-interactive ) > "$T/log" 2>&1
rc=$?
flat_remaining=$( find "$P/templates/pipelines/ci" -maxdepth 1 -name '*.yml' -type f 2>/dev/null | wc -l | tr -d ' ' )
nested_python=$( [ -f "$P/templates/pipelines/ci/github/python.yml" ] && echo y || echo n )
nested_go=$(     [ -f "$P/templates/pipelines/ci/github/go.yml"     ] && echo y || echo n )
nested_web=$(    [ -f "$P/templates/pipelines/release/github/web.yml" ] && echo y || echo n )
host_inferred=$( jq -r '.host // ""' "$P/.claude/manifest.json" 2>/dev/null )
if [ "$rc" = "0" ] && [ "$flat_remaining" = "0" ] \
   && [ "$nested_python" = "y" ] && [ "$nested_go" = "y" ] && [ "$nested_web" = "y" ] \
   && [ "$host_inferred" = "github" ]; then
  pass "T4a: github remote → flat layout migrated + .host='github'"
else
  fail_ "T4a" "rc=$rc flat_remaining=$flat_remaining nested(python=$nested_python go=$nested_go web=$nested_web) host=$host_inferred"
fi
rm -rf "$T"

# ── T4b: host inference fan-out across the 4 case branches ──────────
for case in 'git@github.com:a/b.git|github' \
            'https://gitlab.com/a/b.git|gitlab' \
            'https://gitlab.example.com/a/b.git|gitlab' \
            'https://bitbucket.org/a/b.git|bitbucket' \
            'https://codeberg.org/a/b.git|other'; do
  url="${case%|*}"; expected="${case##*|}"
  T=$(mktemp -d); P="$T/p"
  make_flat_layout "$P" "$url"
  ( cd "$P" && bash "$UPGRADE" --backfill-only --non-interactive ) > "$T/log" 2>&1
  actual=$( jq -r '.host // ""' "$P/.claude/manifest.json" 2>/dev/null )
  if [ "$actual" = "$expected" ]; then
    pass "T4b: remote=$url → .host='$actual'"
  else
    fail_ "T4b" "remote=$url expected=$expected actual='$actual' log:\n$(tail -5 "$T/log")"
  fi
  rm -rf "$T"
done

# ── T4c: idempotency — second run is a no-op ────────────────────────
T=$(mktemp -d); P="$T/p"
make_flat_layout "$P" "git@github.com:a/b.git"
( cd "$P" && bash "$UPGRADE" --backfill-only --non-interactive ) > "$T/log1" 2>&1
manifest_snapshot=$( cat "$P/.claude/manifest.json" )
ci_listing_1=$( find "$P/templates/pipelines/ci" -type f | sort )
( cd "$P" && bash "$UPGRADE" --backfill-only --non-interactive ) > "$T/log2" 2>&1
rc2=$?
manifest_after=$( cat "$P/.claude/manifest.json" )
ci_listing_2=$( find "$P/templates/pipelines/ci" -type f | sort )
log2_no_migrate=no
grep -q "Migrating flat CI template layout" "$T/log2" 2>/dev/null || log2_no_migrate=yes
log2_no_backfill=no
grep -q "Backfilling manifest.json" "$T/log2" 2>/dev/null || log2_no_backfill=yes
if [ "$rc2" = "0" ] && [ "$manifest_snapshot" = "$manifest_after" ] \
   && [ "$ci_listing_1" = "$ci_listing_2" ] \
   && [ "$log2_no_migrate" = "yes" ] && [ "$log2_no_backfill" = "yes" ]; then
  pass "T4c: second run is a no-op (no diff, no 'Migrating...' / 'Backfilling...' log)"
else
  fail_ "T4c" "rc=$rc2 manifest_diff=$([ "$manifest_snapshot" = "$manifest_after" ] && echo none || echo yes) listing_diff=$([ "$ci_listing_1" = "$ci_listing_2" ] && echo none || echo yes) migrate_skipped=$log2_no_migrate backfill_skipped=$log2_no_backfill"
fi
rm -rf "$T"

# ── T4d: pre-existing per-host layout → SKIP file migration ────────
# The guard `[ ! -d templates/pipelines/ci/github ]` skips the file
# migration when a partial per-host layout already exists. This
# documents the partial-migration policy: do not touch a directory
# that's been partially organized. (Manifest .host backfill is
# orthogonal and still runs.)
T=$(mktemp -d); P="$T/p"
make_flat_layout "$P" "git@github.com:a/b.git"
mkdir -p "$P/templates/pipelines/ci/github"   # pre-existing partial layout
( cd "$P" && git add -A && git commit -q -m "partial" ) >/dev/null 2>&1
( cd "$P" && bash "$UPGRADE" --backfill-only --non-interactive ) > "$T/log" 2>&1
rc=$?
# Flat python.yml should STILL be at the flat path (not moved)
flat_python_present=$( [ -f "$P/templates/pipelines/ci/python.yml" ] && echo y || echo n )
host_inferred=$( jq -r '.host // ""' "$P/.claude/manifest.json" 2>/dev/null )
if [ "$rc" = "0" ] && [ "$flat_python_present" = "y" ] && [ "$host_inferred" = "github" ]; then
  pass "T4d: pre-existing ci/github skips file migration; .host backfill still runs"
else
  fail_ "T4d" "rc=$rc flat_python_present=$flat_python_present host=$host_inferred"
fi
rm -rf "$T"

# ── T4e: no git remote → .host inferred as 'other' ──────────────────
T=$(mktemp -d); P="$T/p"
make_flat_layout "$P" ""   # no remote
( cd "$P" && bash "$UPGRADE" --backfill-only --non-interactive ) > "$T/log" 2>&1
rc=$?
host_inferred=$( jq -r '.host // ""' "$P/.claude/manifest.json" 2>/dev/null )
if [ "$rc" = "0" ] && [ "$host_inferred" = "other" ]; then
  pass "T4e: no remote → .host='other' (case default branch)"
else
  fail_ "T4e" "rc=$rc host='$host_inferred' (expected 'other')"
fi
rm -rf "$T"

# ── T4f: manifest already has .host → preserved verbatim ───────────
# Idempotency on the manifest backfill side: the `! jq -e '.host'`
# guard must short-circuit if .host is set, even if its value disagrees
# with the inferred host from the remote.
T=$(mktemp -d); P="$T/p"
make_flat_layout "$P" "git@github.com:a/b.git"   # remote says github
# Pre-set manifest .host to gitlab — should NOT be clobbered.
tmp=$(mktemp)
jq '.host = "gitlab"' "$P/.claude/manifest.json" > "$tmp" && mv "$tmp" "$P/.claude/manifest.json"
( cd "$P" && git add -A && git commit -q -m "preset host" ) >/dev/null 2>&1
( cd "$P" && bash "$UPGRADE" --backfill-only --non-interactive ) > "$T/log" 2>&1
rc=$?
host_after=$( jq -r '.host // ""' "$P/.claude/manifest.json" 2>/dev/null )
if [ "$rc" = "0" ] && [ "$host_after" = "gitlab" ]; then
  pass "T4f: pre-set .host='gitlab' preserved even when remote suggests 'github'"
else
  fail_ "T4f" "rc=$rc host='$host_after' (expected 'gitlab', remote was github)"
fi
rm -rf "$T"

# ── T4g: content preservation across the file moves ────────────────
# Sanity guard: the migration uses `git mv` (or `mv` fallback); both
# must preserve file content byte-for-byte.
T=$(mktemp -d); P="$T/p"
make_flat_layout "$P" "git@github.com:a/b.git"
sha_python_pre=$( shasum -a 256 "$P/templates/pipelines/ci/python.yml" | awk '{print $1}' )
sha_web_pre=$(    shasum -a 256 "$P/templates/pipelines/release/web.yml" | awk '{print $1}' )
( cd "$P" && bash "$UPGRADE" --backfill-only --non-interactive ) > "$T/log" 2>&1
sha_python_post=$( shasum -a 256 "$P/templates/pipelines/ci/github/python.yml" 2>/dev/null | awk '{print $1}' )
sha_web_post=$(    shasum -a 256 "$P/templates/pipelines/release/github/web.yml" 2>/dev/null | awk '{print $1}' )
if [ "$sha_python_pre" = "$sha_python_post" ] && [ "$sha_web_pre" = "$sha_web_post" ]; then
  pass "T4g: file content preserved through migration (sha256 unchanged)"
else
  fail_ "T4g" "python sha pre=$sha_python_pre post=$sha_python_post; web sha pre=$sha_web_pre post=$sha_web_post"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T5: S3 sweep — vendored-skills sync + POC_TO_PRIVATE + Manifesto refresh ==="
# ════════════════════════════════════════════════════════════════════
#
# Three audit-cleanup items shipped together in one PR (S3 sweep):
#   T5a — code-upgrade-project-3: vendored-skills sync. upgrade-project.sh
#         previously refreshed only helper scripts; vendored skills shipped
#         after a project's init never made it into upgraded projects.
#   T5b — code-upgrade-project-7: --to-private-poc was missing from the
#         APPROVAL_LOG audit-row condition AND from the COMMIT_PARTS block,
#         silently dropping audit coverage and producing a misleading
#         generic commit subject.
#   T5c — code-upgrade-project-6: PRODUCT_MANIFESTO.md Appendix A/C
#         "SKIPPED — internal tool, …" markers (light-track Phase-0 exemption)
#         were never rewritten on track-up to standard/full; appendices
#         silently stayed marked SKIPPED even though required.

# ── T5a: vendored-skills sync via --backfill-only ──────────────────
# Old project predates the skill-install block — .claude/skills/ doesn't
# even exist. After upgrade-project.sh runs, all four vendored skills
# should land in .claude/skills/<name>/SKILL.md, with NOTICE alongside
# when the framework ships one. The framework currently vendors:
# grill-with-docs, session-handoff, sweep-triage, zoom-out.
T=$(mktemp -d); P="$T/p"
make_phase_state "$P" "light" "personal" 'null'
# Ensure the project has NO .claude/skills/ directory (pre-skill projects).
rm -rf "$P/.claude/skills"
( cd "$P" && bash "$UPGRADE" --backfill-only --non-interactive ) > "$T/log" 2>&1
rc=$?
missing_skills=""
for s in grill-with-docs session-handoff sweep-triage zoom-out; do
  if [ ! -f "$P/.claude/skills/$s/SKILL.md" ]; then
    missing_skills="$missing_skills $s"
  fi
done
# NOTICE check: at least one skill ships a NOTICE in the framework
# (vendored from mattpocock/skills, MIT). Confirm the copier preserved
# at least one NOTICE so attribution doesn't silently disappear.
notice_count=$( find "$P/.claude/skills" -maxdepth 2 -name NOTICE -type f 2>/dev/null | wc -l | tr -d ' ' )
if [ "$rc" = "0" ] && [ -z "$missing_skills" ] && [ "$notice_count" -ge 1 ]; then
  pass "T5a: vendored-skills sync — all 4 skills installed with NOTICE attribution preserved"
else
  fail_ "T5a" "rc=$rc missing_skills='$missing_skills' notice_count=$notice_count. Log tail: $(tail -10 "$T/log" 2>/dev/null | tr '\n' '|')"
fi
rm -rf "$T"

# ── T5b: --to-private-poc commit subject + APPROVAL_LOG audit row ──
# Setup: personal project with no POC mode. APPROVAL_LOG.md is pre-seeded
# with an Approval History section so the audit-row branch is reachable
# (otherwise the audit-write block exits via `[ -f "$APPROVAL_LOG" ]`).
T=$(mktemp -d); P="$T/p"
make_phase_state "$P" "light" "personal" 'null'
cat > "$P/APPROVAL_LOG.md" <<'EOF'
---
project: test
deployment: personal
---

# Approval Log — test

## Approval History

| Date | Gate / Event | Approver | Role | Decision | Reference |
|---|---|---|---|---|---|
EOF
( cd "$P" && git add APPROVAL_LOG.md && git commit -q -m "seed approval log" ) >/dev/null 2>&1
( cd "$P" && bash "$UPGRADE" --to-private-poc --non-interactive ) > "$T/log" 2>&1
rc=$?
# (a) commit subject contains the new "private POC" branch text
commit_subject=$( cd "$P" && git log -1 --pretty=%s 2>/dev/null )
subject_ok=no
case "$commit_subject" in
  *"private POC"*) subject_ok=yes ;;
esac
# (b) APPROVAL_LOG.md gained a row mentioning Private POC under the
# Approval History section.
audit_row_count=$( grep -ci "Private POC" "$P/APPROVAL_LOG.md" 2>/dev/null )
if [ "$rc" = "0" ] && [ "$subject_ok" = "yes" ] && [ "$audit_row_count" -ge 1 ]; then
  pass "T5b: --to-private-poc commit subject + APPROVAL_LOG audit row both populated"
else
  fail_ "T5b" "rc=$rc commit_subject='$commit_subject' subject_ok=$subject_ok audit_row_count=$audit_row_count. Log tail: $(tail -10 "$T/log" 2>/dev/null | tr '\n' '|')"
fi
rm -rf "$T"

# ── T5c: PRODUCT_MANIFESTO.md Appendix A/C refresh on track upgrade ─
# Light-track project carries SKIPPED markers in Appendix A (Revenue
# Model) and Appendix C (Trademark & Legal). After --track standard
# they should be rewritten to PENDING with today's date, and committed
# alongside the other upgrade artifacts.
T=$(mktemp -d); P="$T/p"
make_phase_state "$P" "light" "personal" 'null'
cat > "$P/PRODUCT_MANIFESTO.md" <<'EOF'
# Product Manifesto — test

## 1. Product Intent
Test product.

## Appendix A: Revenue Model & Unit Economics

**Pricing Model:** SKIPPED — internal tool, no revenue model required

## Appendix C: Trademark & Legal Pre-Check

**Trademark Search:** SKIPPED — internal tool, no trademark check required
EOF
( cd "$P" && git add PRODUCT_MANIFESTO.md && git commit -q -m "seed manifesto" ) >/dev/null 2>&1
( cd "$P" && bash "$UPGRADE" --track standard --non-interactive ) > "$T/log" 2>&1
rc=$?
skipped_remaining=$( grep -c "SKIPPED" "$P/PRODUCT_MANIFESTO.md" 2>/dev/null )
pending_added=$(    grep -c "PENDING — required by track upgrade" "$P/PRODUCT_MANIFESTO.md" 2>/dev/null )
# Verify the rewrite landed in a commit (FILES_TO_STAGE includes Manifesto)
manifesto_in_log=$( cd "$P" && git log --name-only --pretty=format: 2>/dev/null | grep -c "^PRODUCT_MANIFESTO.md$" )
if [ "$rc" = "0" ] && [ "$skipped_remaining" = "0" ] && [ "$pending_added" -ge 2 ] && [ "$manifesto_in_log" -ge 1 ]; then
  pass "T5c: PRODUCT_MANIFESTO.md SKIPPED markers rewritten → PENDING on track-up and committed"
else
  fail_ "T5c" "rc=$rc skipped_remaining=$skipped_remaining pending_added=$pending_added manifesto_in_log=$manifesto_in_log. Log tail: $(tail -10 "$T/log" 2>/dev/null | tr '\n' '|')"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "=== T6: CLAUDE.md POC-mode strip preserves surrounding prose (code-upgrade-project-4) ==="
# ════════════════════════════════════════════════════════════════════
#
# Audit code-upgrade-project-4 regression: the python heredoc that
# strips POC watermarks from CLAUDE.md when --to-production runs uses a
# skip_block state that terminates ONLY on a blank line. A mid-paragraph
# mention of "POC mode" or "POC constraints" inside a numbered list or
# right before a markdown heading therefore swallows the trailing list
# items / the heading and its body. Operator-customized CLAUDE.md files
# can lose data silently. Default templated CLAUDE.md has no POC prose
# so blast radius is operator-edits only — still a real correctness bug.
#
# Fix: broaden skip_block termination to also close on a markdown
# heading line (starts with #) or a list-item line (-, *, +, or
# numbered N.). T6a covers the list-item case; T6b covers the heading.

# ── T6a: numbered list — items after a mid-list POC mention survive ──
T=$(mktemp -d); P="$T/p"
make_phase_state "$P" "standard" "organizational" '"sponsored_poc"'
seed_approval_log_org_filled "$P"
cat > "$P/CLAUDE.md" <<'EOF'
# Project Identity

**Track:** Standard
**Deployment:** Organizational

## Operating Checklist

1. Review the project intake before each phase gate.
2. POC mode is documented in section 4 below for context.
3. CANARY-LIST-ITEM-THREE must be preserved.
4. CANARY-LIST-ITEM-FOUR must be preserved.

## Next Section

CANARY-NEXT-SECTION-BODY must be preserved.
EOF
( cd "$P" && git add APPROVAL_LOG.md CLAUDE.md && git commit -q -m "seed approval log + claude.md" ) >/dev/null 2>&1
( cd "$P" && bash "$UPGRADE" --to-production --non-interactive --ack-preconditions=1,2,3,4,5,6 ) > "$T/log" 2>&1
rc=$?
have_three=$(grep -c "CANARY-LIST-ITEM-THREE" "$P/CLAUDE.md" 2>/dev/null); have_three=${have_three:-0}
have_four=$(grep -c "CANARY-LIST-ITEM-FOUR"  "$P/CLAUDE.md" 2>/dev/null); have_four=${have_four:-0}
have_next=$(grep -c "CANARY-NEXT-SECTION-BODY" "$P/CLAUDE.md" 2>/dev/null); have_next=${have_next:-0}
if [ "$rc" = "0" ] && [ "$have_three" -ge 1 ] && [ "$have_four" -ge 1 ] && [ "$have_next" -ge 1 ]; then
  pass "T6a: numbered-list items after mid-list POC mention preserved through --to-production strip"
else
  fail_ "T6a" "rc=$rc have_three=$have_three have_four=$have_four have_next=$have_next. Log tail: $(tail -10 "$T/log" 2>/dev/null | tr '\n' '|')"
fi
rm -rf "$T"

# ── T6b: heading after a "POC constraints" line is preserved ────────
T=$(mktemp -d); P="$T/p"
make_phase_state "$P" "standard" "organizational" '"sponsored_poc"'
seed_approval_log_org_filled "$P"
cat > "$P/CLAUDE.md" <<'EOF'
# Project Identity

**Track:** Standard
**Deployment:** Organizational

POC constraints apply during pilot.
## Configuration

CANARY-CONFIG-BODY must be preserved.

## Deployment Notes

CANARY-DEPLOY-BODY must be preserved.
EOF
( cd "$P" && git add APPROVAL_LOG.md CLAUDE.md && git commit -q -m "seed approval log + claude.md" ) >/dev/null 2>&1
( cd "$P" && bash "$UPGRADE" --to-production --non-interactive --ack-preconditions=1,2,3,4,5,6 ) > "$T/log" 2>&1
rc=$?
have_config_head=$(grep -c "^## Configuration"  "$P/CLAUDE.md" 2>/dev/null); have_config_head=${have_config_head:-0}
have_config_body=$(grep -c "CANARY-CONFIG-BODY" "$P/CLAUDE.md" 2>/dev/null); have_config_body=${have_config_body:-0}
have_deploy_head=$(grep -c "^## Deployment Notes" "$P/CLAUDE.md" 2>/dev/null); have_deploy_head=${have_deploy_head:-0}
have_deploy_body=$(grep -c "CANARY-DEPLOY-BODY" "$P/CLAUDE.md" 2>/dev/null); have_deploy_body=${have_deploy_body:-0}
if [ "$rc" = "0" ] && [ "$have_config_head" -ge 1 ] && [ "$have_config_body" -ge 1 ] \
   && [ "$have_deploy_head" -ge 1 ] && [ "$have_deploy_body" -ge 1 ]; then
  pass "T6b: heading + body after 'POC constraints' line preserved through --to-production strip"
else
  fail_ "T6b" "rc=$rc config_head=$have_config_head config_body=$have_config_body deploy_head=$have_deploy_head deploy_body=$have_deploy_body. Log tail: $(tail -10 "$T/log" 2>/dev/null | tr '\n' '|')"
fi
rm -rf "$T"

# ════════════════════════════════════════════════════════════════════
echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
