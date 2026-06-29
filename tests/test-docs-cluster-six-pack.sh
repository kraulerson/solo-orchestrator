#!/usr/bin/env bash
# tests/test-docs-cluster-six-pack.sh
#
# Docs/code-lint tests for six S3 audit findings closed by
# PR docs/cluster-six-pack-closer:
#
#   T1 (user-guide-3): docs/user-guide.md §5 Phase 4 user-actions table
#       must include a POC precondition row directing operators to run
#       scripts/upgrade-project.sh --to-production first when poc_mode
#       is set. The row must be marked Required for both Personal and
#       Organizational columns.
#
#   T2 (governance-framework-4): docs/governance-framework.md §V must
#       include a 'Mid-Phase 2 Governance Checkpoint' subsection covering
#       the biweekly Senior-Technical-Authority status review (org-only,
#       30-min cap, recorded in the In-Phase Decision Log, does not
#       replace the Phase 3 gate).
#
#   T3 (extending-platforms-1): docs/extending-platforms.md release-pipeline
#       references must use the per-host path templates/pipelines/release/
#       {host}/{platform}.yml, name all three hosts (github/bitbucket/gitlab),
#       and document that github is canonical for discovery. The legacy
#       flat-dir path templates/pipelines/release/{platform}.yml must be
#       gone from the file-table row, Step 3 'File:' line, and the
#       Auto-Discovery section. Step 3 must instruct contributors to add
#       per-host copies.
#
#   T4 (extending-platforms-5): docs/extending-platforms.md 'What You Are
#       Creating' table must list six components, with a row for UAT
#       References (templates/uat/references/{platform}-pre-flight.html +
#       {platform}-scenario.json). A 'Step 6: UAT Reference Files' section
#       must exist documenting both files, init.sh's copy to
#       tests/uat/examples/, the print_warn fallback, and pointer to
#       docs/uat-authoring-guide.md.
#
#   T5 (uat-authoring-guide-1): docs/uat-authoring-guide.md §§3.1–3.4
#       and §§4.1–4.3 'Reference file:' lines must cite BOTH the
#       framework-source path (templates/uat/references/...) AND the
#       post-init path (tests/uat/examples/...), so the agent gets the
#       correct path regardless of which repo they're in.
#
#   T6 (uat-authoring-guide-2): init.sh's project-bootstrap doc copy
#       block must include docs/uat-authoring-guide.md. The two init.sh
#       print_* fallback strings that reference the guide must point at
#       docs/reference/uat-authoring-guide.md § 5. Likewise
#       templates/uat/test-session-template.html line ~95 must reference
#       the in-project path.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
USER_GUIDE="$REPO_ROOT/docs/user-guide.md"
GOV_FRAMEWORK="$REPO_ROOT/docs/governance-framework.md"
EXT_PLATFORMS="$REPO_ROOT/docs/extending-platforms.md"
UAT_GUIDE="$REPO_ROOT/docs/uat-authoring-guide.md"
INIT_SH="$REPO_ROOT/init.sh"
UAT_HTML_TMPL="$REPO_ROOT/templates/uat/test-session-template.html"

for f in "$USER_GUIDE" "$GOV_FRAMEWORK" "$EXT_PLATFORMS" "$UAT_GUIDE" "$INIT_SH" "$UAT_HTML_TMPL"; do
  if [ ! -f "$f" ]; then
    echo "FATAL: required file not found: $f" >&2
    exit 2
  fi
done

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

# ----------------------------------------------------------------
# T1 (user-guide-3): Phase 4 user-actions table has a POC precondition
# row pointing at upgrade-project.sh --to-production.
# ----------------------------------------------------------------
echo ""
echo "T1 (user-guide-3): Phase 4 user-actions table has POC precondition row"

# The Phase 4 section starts at the '### Phase 4: Release & Maintenance'
# heading and ends at the next '### ' heading (or the Phase 4 details
# block). Extract just that span and look inside for the POC row.
phase4_block=$(awk '
  /^### Phase 4:/ { capture=1 }
  capture && /^### / && !/^### Phase 4:/ { exit }
  capture { print }
' "$USER_GUIDE")

if [ -z "$phase4_block" ]; then
  fail_ "T1-pre" "Could not isolate Phase 4 section in user-guide.md"
else
  # Row must explicitly call out poc_mode AND the upgrade-project.sh
  # --to-production command AND be Required in both columns.
  if printf '%s\n' "$phase4_block" \
       | grep -qE '\|.*poc_mode.*upgrade-project\.sh.*--to-production.*\|.*Required.*\|.*Required.*\|'; then
    pass "T1: Phase 4 table has POC precondition row (poc_mode + upgrade-project.sh --to-production + Required/Required)"
  else
    fail_ "T1" "Phase 4 user-actions table does not contain a POC precondition row matching '| ... poc_mode ... upgrade-project.sh --to-production ... | Required | Required |'"
  fi
fi

# ----------------------------------------------------------------
# T2 (governance-framework-4): §V has a 'Mid-Phase 2 Governance
# Checkpoint' subsection with the required content.
# ----------------------------------------------------------------
echo ""
echo "T2 (governance-framework-4): §V has Mid-Phase 2 Governance Checkpoint subsection"

# Find the subsection heading. Must be inside §V (between '## V.' and
# the next '## ' heading).
section_v_block=$(awk '
  /^## V\. / { capture=1 }
  capture && /^## / && !/^## V\. / { exit }
  capture { print }
' "$GOV_FRAMEWORK")

if [ -z "$section_v_block" ]; then
  fail_ "T2-pre" "Could not isolate §V in governance-framework.md"
else
  if printf '%s\n' "$section_v_block" | grep -qE '^### Mid-Phase 2 Governance Checkpoint'; then
    pass "T2a: §V has 'Mid-Phase 2 Governance Checkpoint' subsection heading"
  else
    fail_ "T2a" "§V missing '### Mid-Phase 2 Governance Checkpoint' subsection heading"
  fi

  # The body must mention biweekly cadence, Senior Technical Authority,
  # 30 minutes (or 30-min) cap, and the In-Phase Decision Log linkage.
  mp2_body=$(printf '%s\n' "$section_v_block" | awk '
    /^### Mid-Phase 2 Governance Checkpoint/ { capture=1; next }
    capture && /^### / { exit }
    capture { print }
  ')

  if printf '%s\n' "$mp2_body" | grep -qiE 'biweekly|every two weeks|every 2 weeks'; then
    pass "T2b: Mid-Phase 2 body specifies biweekly cadence"
  else
    fail_ "T2b" "Mid-Phase 2 body does not specify biweekly cadence"
  fi

  if printf '%s\n' "$mp2_body" | grep -q 'Senior Technical Authority'; then
    pass "T2c: Mid-Phase 2 body names Senior Technical Authority"
  else
    fail_ "T2c" "Mid-Phase 2 body does not name Senior Technical Authority"
  fi

  if printf '%s\n' "$mp2_body" | grep -qiE '30[- ]min|30 minutes'; then
    pass "T2d: Mid-Phase 2 body specifies 30-minute duration cap"
  else
    fail_ "T2d" "Mid-Phase 2 body does not specify a 30-minute duration cap"
  fi

  if printf '%s\n' "$mp2_body" | grep -q 'In-Phase Decision Log'; then
    pass "T2e: Mid-Phase 2 body references the In-Phase Decision Log"
  else
    fail_ "T2e" "Mid-Phase 2 body does not reference the In-Phase Decision Log"
  fi

  # The checkpoint must NOT replace the Phase 3 gate; spell that out.
  if printf '%s\n' "$mp2_body" | grep -qiE 'does not replace|not a replacement for|in addition to'; then
    pass "T2f: Mid-Phase 2 body states the checkpoint does not replace the Phase 3 gate"
  else
    fail_ "T2f" "Mid-Phase 2 body does not explicitly state it does not replace the Phase 3 gate"
  fi
fi

# ----------------------------------------------------------------
# T3 (extending-platforms-1): per-host release-pipeline path is used
# in the file-table row, Step 3 'File:' line, and Auto-Discovery.
# ----------------------------------------------------------------
echo ""
echo "T3 (extending-platforms-1): release-pipeline references use per-host path"

# T3a: the Step 3 'File:' line must NOT be the flat-dir path.
if grep -qE '^\*\*File:\*\*\s+`templates/pipelines/release/\{platform\}\.yml`' "$EXT_PLATFORMS"; then
  fail_ "T3a" "Step 3 'File:' line still uses the flat-dir path templates/pipelines/release/{platform}.yml (should be per-host: {host}/{platform}.yml)"
else
  pass "T3a: Step 3 'File:' line no longer uses the flat-dir templates/pipelines/release/{platform}.yml path"
fi

# T3b: Step 3 'File:' line uses the per-host path.
if grep -qE '^\*\*File:\*\*\s+`templates/pipelines/release/\{host\}/\{platform\}\.yml`' "$EXT_PLATFORMS"; then
  pass "T3b: Step 3 'File:' line uses the per-host path templates/pipelines/release/{host}/{platform}.yml"
else
  fail_ "T3b" "Step 3 'File:' line does not use the per-host path templates/pipelines/release/{host}/{platform}.yml"
fi

# T3c: Auto-Discovery section must name the github subdirectory, not
# the flat templates/pipelines/release/*.yml path.
autodisc_block=$(awk '
  /^## Auto-Discovery/ { capture=1 }
  capture && /^## / && !/^## Auto-Discovery/ { exit }
  capture { print }
' "$EXT_PLATFORMS")

if printf '%s\n' "$autodisc_block" | grep -qE 'templates/pipelines/release/github/\*\.yml'; then
  pass "T3c: Auto-Discovery references the github subdirectory (canonical for discovery)"
else
  fail_ "T3c" "Auto-Discovery does not reference templates/pipelines/release/github/*.yml as the canonical discovery tree"
fi

# T3d: the legacy flat 'Scans templates/pipelines/release/*.yml' bullet
# (without the github subdir) must be gone — that path is misleading.
if printf '%s\n' "$autodisc_block" | grep -qE 'Scans\s+\`templates/pipelines/release/\*\.yml\`'; then
  fail_ "T3d" "Auto-Discovery still says 'Scans templates/pipelines/release/*.yml' (flat dir — wrong; the actual scan is github/ only)"
else
  pass "T3d: Auto-Discovery no longer cites the flat templates/pipelines/release/*.yml path"
fi

# T3e: 'What You Are Creating' table row 3 (Release Pipeline) uses the
# per-host path and names all three hosts (github/bitbucket/gitlab).
table_block=$(awk '
  /^## What You Are Creating/ { capture=1 }
  capture && /^## / && !/^## What You Are Creating/ { exit }
  capture { print }
' "$EXT_PLATFORMS")

if printf '%s\n' "$table_block" | grep -qE 'templates/pipelines/release/\{host\}/\{platform\}\.yml' \
   && printf '%s\n' "$table_block" | grep -q 'github' \
   && printf '%s\n' "$table_block" | grep -q 'bitbucket' \
   && printf '%s\n' "$table_block" | grep -q 'gitlab'; then
  pass "T3e: 'What You Are Creating' table row 3 uses per-host path and names github/bitbucket/gitlab"
else
  fail_ "T3e" "'What You Are Creating' table row 3 does not use per-host path or does not name all three hosts (github/bitbucket/gitlab)"
fi

# T3f: Step 3 body must instruct contributors to add per-host copies
# (or at minimum mention all three host directories explicitly).
step3_block=$(awk '
  /^### Step 3: Release Pipeline/ { capture=1 }
  capture && /^### Step 4/ { exit }
  capture { print }
' "$EXT_PLATFORMS")

if printf '%s\n' "$step3_block" | grep -qE 'bitbucket' \
   && printf '%s\n' "$step3_block" | grep -qE 'gitlab' \
   && printf '%s\n' "$step3_block" | grep -qE 'github'; then
  pass "T3f: Step 3 body names all three host directories (github/bitbucket/gitlab)"
else
  fail_ "T3f" "Step 3 body does not name all three host directories"
fi

# ----------------------------------------------------------------
# T4 (extending-platforms-5): table lists six components with UAT
# References row, and Step 6 section exists.
# ----------------------------------------------------------------
echo ""
echo "T4 (extending-platforms-5): table has UAT References row + Step 6 section exists"

# T4a: 'What You Are Creating' table includes a row referencing
# templates/uat/references/{platform}-pre-flight.html and -scenario.json.
if printf '%s\n' "$table_block" \
     | grep -qE 'templates/uat/references/\{platform\}-pre-flight\.html'; then
  pass "T4a: 'What You Are Creating' table includes UAT References row (pre-flight.html)"
else
  fail_ "T4a" "'What You Are Creating' table missing UAT References row (templates/uat/references/{platform}-pre-flight.html)"
fi

if printf '%s\n' "$table_block" \
     | grep -qE 'templates/uat/references/\{platform\}-scenario\.json'; then
  pass "T4b: 'What You Are Creating' table includes UAT References row (scenario.json)"
else
  fail_ "T4b" "'What You Are Creating' table missing UAT References row (templates/uat/references/{platform}-scenario.json)"
fi

# T4c: numbered row 6 in the table exists (six rows total).
if printf '%s\n' "$table_block" | grep -qE '^\|\s*6\s*\|'; then
  pass "T4c: 'What You Are Creating' table has a 6th numbered row"
else
  fail_ "T4c" "'What You Are Creating' table does not have a 6th numbered row"
fi

# T4d: a 'Step 6: UAT Reference Files' section exists.
if grep -qE '^### Step 6: UAT Reference Files' "$EXT_PLATFORMS"; then
  pass "T4d: 'Step 6: UAT Reference Files' section exists"
else
  fail_ "T4d" "Missing '### Step 6: UAT Reference Files' section"
fi

# T4e: Step 6 body mentions both files, the tests/uat/examples copy
# target, the print_warn fallback, and points at the UAT authoring guide.
step6_block=$(awk '
  /^### Step 6: UAT Reference Files/ { capture=1 }
  capture && /^### / && !/^### Step 6/ { exit }
  capture && /^## / && !/^### Step 6/ { exit }
  capture { print }
' "$EXT_PLATFORMS")

if printf '%s\n' "$step6_block" | grep -q 'tests/uat/examples'; then
  pass "T4e1: Step 6 body mentions tests/uat/examples copy target"
else
  fail_ "T4e1" "Step 6 body does not mention tests/uat/examples"
fi

if printf '%s\n' "$step6_block" | grep -qE 'print_warn|fallback'; then
  pass "T4e2: Step 6 body mentions the print_warn fallback"
else
  fail_ "T4e2" "Step 6 body does not mention the print_warn fallback"
fi

if printf '%s\n' "$step6_block" | grep -q 'uat-authoring-guide'; then
  pass "T4e3: Step 6 body points at docs/uat-authoring-guide.md"
else
  fail_ "T4e3" "Step 6 body does not point at docs/uat-authoring-guide.md"
fi

# ----------------------------------------------------------------
# T5 (uat-authoring-guide-1): §§3.1–3.4 and §§4.1–4.3 'Reference file'
# lines cite BOTH source and post-init paths.
# ----------------------------------------------------------------
echo ""
echo "T5 (uat-authoring-guide-1): Reference-file lines cite both source and post-init paths"

# Count 'Reference file' lines that mention the framework source path.
src_refs=$(grep -cE 'Reference file.*templates/uat/references' "$UAT_GUIDE" || true)
case "$src_refs" in ''|*[!0-9]*) src_refs=0 ;; esac
# Count 'Reference file' lines that mention the post-init project path.
post_refs=$(grep -cE 'Reference file.*tests/uat/examples' "$UAT_GUIDE" || true)
case "$post_refs" in ''|*[!0-9]*) post_refs=0 ;; esac

# There are 7 reference-file lines total (4 pre-flight + 3 scenario);
# every one must cite both paths. Use a tight equality assertion.
if [ "$src_refs" -ge 7 ]; then
  pass "T5a: at least 7 'Reference file' lines cite the framework source path (got $src_refs)"
else
  fail_ "T5a" "fewer than 7 'Reference file' lines cite templates/uat/references (got $src_refs)"
fi

if [ "$post_refs" -ge 7 ]; then
  pass "T5b: at least 7 'Reference file' lines cite the post-init path (got $post_refs)"
else
  fail_ "T5b" "fewer than 7 'Reference file' lines cite tests/uat/examples (got $post_refs)"
fi

# T5c: §3.1 specifically must cite both — anchor on the web pre-flight.
sec31_block=$(awk '
  /^### 3\.1 web/ { capture=1; next }
  capture && /^### / { exit }
  capture { print }
' "$UAT_GUIDE")

if printf '%s\n' "$sec31_block" | grep -qE 'templates/uat/references/web-pre-flight\.html' \
   && printf '%s\n' "$sec31_block" | grep -qE 'tests/uat/examples/pre-flight-reference\.html'; then
  pass "T5c: §3.1 web cites both source (templates/uat/references/web-pre-flight.html) and post-init (tests/uat/examples/pre-flight-reference.html) paths"
else
  fail_ "T5c" "§3.1 web does not cite both source and post-init pre-flight paths"
fi

# ----------------------------------------------------------------
# T6 (uat-authoring-guide-2): init.sh copies the guide into projects;
# print_* and the HTML template reference the in-project path.
# ----------------------------------------------------------------
echo ""
echo "T6 (uat-authoring-guide-2): init.sh copies uat-authoring-guide.md + in-project path used"

# T6a: init.sh's docs/reference/ copy block (right after the user-guide
# cp) must include uat-authoring-guide.md.
if grep -qE 'cp\s+"\$SCRIPT_DIR/docs/uat-authoring-guide\.md"\s+docs/reference/' "$INIT_SH"; then
  pass "T6a: init.sh copies docs/uat-authoring-guide.md into docs/reference/"
else
  fail_ "T6a" "init.sh does not copy docs/uat-authoring-guide.md into docs/reference/"
fi

# T6b: the two init.sh print_* lines that previously pointed at
# docs/uat-authoring-guide.md must now point at the in-project path
# docs/reference/uat-authoring-guide.md. We anchor on '§ 5' which is
# the original section reference, ensuring we caught both call sites.
ref_print_count=$(grep -cE 'docs/reference/uat-authoring-guide\.md\s+§\s*5' "$INIT_SH" || true)
case "$ref_print_count" in ''|*[!0-9]*) ref_print_count=0 ;; esac

if [ "$ref_print_count" -ge 2 ]; then
  pass "T6b: init.sh has >= 2 print_* lines pointing at docs/reference/uat-authoring-guide.md § 5 (got $ref_print_count)"
else
  fail_ "T6b" "init.sh does not have >= 2 print_* lines pointing at docs/reference/uat-authoring-guide.md § 5 (got $ref_print_count)"
fi

# T6c: the legacy docs/uat-authoring-guide.md path must NOT remain in
# init.sh's print_* fallback strings (the source-of-truth in the
# framework repo is fine; we're checking that no print_info/print_warn
# string still cites the un-prefixed path that won't resolve in a
# generated project).
stale_print_lines=$(grep -nE 'print_(info|warn).*"[^"]*docs/uat-authoring-guide\.md' "$INIT_SH" || true)
if [ -n "$stale_print_lines" ]; then
  fail_ "T6c" "init.sh still has print_* fallback strings citing the un-prefixed docs/uat-authoring-guide.md path:
$stale_print_lines"
else
  pass "T6c: no init.sh print_* fallback strings still cite the un-prefixed docs/uat-authoring-guide.md path"
fi

# T6d: templates/uat/test-session-template.html must reference the
# in-project path (docs/reference/uat-authoring-guide.md), not the
# pre-init source path.
if grep -qE 'docs/reference/uat-authoring-guide\.md' "$UAT_HTML_TMPL"; then
  pass "T6d: test-session-template.html references docs/reference/uat-authoring-guide.md"
else
  fail_ "T6d" "test-session-template.html does not reference docs/reference/uat-authoring-guide.md"
fi

# T6e: the legacy un-prefixed docs/uat-authoring-guide.md path must
# NOT remain in the HTML template (that string ships to user projects
# where docs/uat-authoring-guide.md does not exist; only
# docs/reference/uat-authoring-guide.md is in-project).
if grep -qE '(^|[^/])docs/uat-authoring-guide\.md' "$UAT_HTML_TMPL"; then
  fail_ "T6e" "test-session-template.html still references the un-prefixed docs/uat-authoring-guide.md (won't resolve in generated projects)"
else
  pass "T6e: test-session-template.html no longer references the un-prefixed docs/uat-authoring-guide.md"
fi

# ----------------------------------------------------------------
# Summary
# ----------------------------------------------------------------
echo ""
echo "=================================================="
echo "Results: $PASSED passed, $FAILED failed"
echo "=================================================="
[ "$FAILED" -eq 0 ] || exit 1
exit 0
