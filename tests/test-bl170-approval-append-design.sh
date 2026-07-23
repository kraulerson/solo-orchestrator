#!/usr/bin/env bash
# tests/test-bl170-approval-append-design.sh — BL-170 (Dogfood-4 F-DF4-017):
# the APPROVAL_LOG templates must NOT ship pre-seeded empty fill-in-place gate
# tables. Filling a committed placeholder line MODIFIES it, which the emitted
# `Governance - Approval log integrity` CI job (BL-147, append-only) rejects.
# The fix redesigns every gate/section to instruct the operator to APPEND a
# completed table under the header instead of editing shipped placeholders.
#
# WHAT THIS PINS
#   A. TEMPLATE PINS
#      A1  RED baseline: the ORIGINAL (cc0ce71) templates carry empty-value
#          gate rows and NO append marker (the shape this WP removes). Proven
#          against `git show` so the detector is shown to distinguish old/new.
#      A2  GREEN: the working-tree templates have ZERO empty-value rows in any
#          `## Phase Gate:` section and carry the `BL-170-APPEND-DESIGN` marker
#          in every gate section; and no `[YYYY-MM-DD]`/`[Name`/`[Attorney`
#          BL-138 placeholder bait remains anywhere.
#   B. BEHAVIOURAL CONSUMER CASES (drive the REAL check-phase-gate.sh)
#      B1  gate-date auto-record (_cpg_gate_has_evidence / BL-071) finds the
#          Date of an APPENDED gate table — within its head-15 window.
#      B2  validate_approval_fields / BL-138 does NOT flag the append
#          instruction text as "placeholder values".
#      B3  BL-143 self-approval scan reads the APPENDED Approver cell:
#          committer == approver  -> self-approval DETECTED (FAIL);
#          committer != approver  -> NOT detected (no false FAIL).
#      B4  org Phase 3->4 dual-approval (validate_approval_section_dated) sees
#          the Date of appended Application Owner + IT Security tables.
#   C. MUTATION PROOFS (the pins are load-bearing)
#      C1  inject an empty `| **Reviewer** | |` row back into a gate section
#          -> the A2 empty-row pin flips RED.
#      C2  strip the `BL-170-APPEND-DESIGN` marker from a gate section
#          -> the A2 marker pin flips RED.
#
# REGISTRATION: no init.sh, not an aggregator -> BOTH lists (full-project-test-
# suite.sh + tests.yml unit `tests=(`). Hermetic (mktemp fixtures, local git
# only, no remote). bash-3.2 safe: no associative arrays, no mapfile, no
# `${var,,}`, no `((x++))` under set -e.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CPG="$REPO_ROOT/scripts/check-phase-gate.sh"
PER_TMPL="$REPO_ROOT/templates/generated/approval-log-personal.tmpl"
ORG_TMPL="$REPO_ROOT/templates/generated/approval-log-org.tmpl"
ORIG_REF="cc0ce71"   # origin/main at WP start — RED baseline source

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# --- shared pin helpers ------------------------------------------------------
# Count empty-value table rows (`| **Field** | |`) inside `## Phase Gate:`
# sections only (bounded to the next `## ` header). Prints an integer.
count_empty_gate_rows() {
  awk '
    /^## Phase Gate:/ { insec = 1; next }
    insec && /^## / { insec = 0 }
    insec && /^\|[[:space:]]*\**[[:space:]]*[A-Za-z][^|]*\**[[:space:]]*\|[[:space:]]*\|[[:space:]]*$/ { e++ }
    END { print e + 0 }
  ' "$1"
}

# Print the header of every `## Phase Gate:` section that lacks the
# BL-170-APPEND-DESIGN marker before the next `## `. Empty output = all good.
gate_sections_missing_marker() {
  awk '
    /^## Phase Gate:/ {
      if (insec && !seen) print hdr
      insec = 1; seen = 0; hdr = $0; next
    }
    insec && /^## / { if (!seen) print hdr; insec = 0 }
    insec && /BL-170-APPEND-DESIGN/ { seen = 1 }
    END { if (insec && !seen) print hdr }
  ' "$1"
}

echo "=== A. TEMPLATE PINS ==="

# A1 — RED baseline against the ORIGINAL templates (documents what the WP removed).
for t in personal org; do
  orig="$TOPTMP/orig-$t.tmpl"
  if git -C "$REPO_ROOT" show "$ORIG_REF:templates/generated/approval-log-$t.tmpl" > "$orig" 2>/dev/null; then
    e=$(count_empty_gate_rows "$orig")
    # grep -c prints "0" and exits 1 on no match; capture it plainly (no
    # `|| echo 0`, which would append a SECOND "0" — the PR #53 trap) and
    # sanitize to a bare integer.
    m=$(grep -c 'BL-170-APPEND-DESIGN' "$orig" 2>/dev/null)
    case "$m" in ''|*[!0-9]*) m=0 ;; esac
    if [ "$e" -gt 0 ] && [ "$m" -eq 0 ]; then
      pass "A1-$t: ORIGINAL template is RED as expected (empty gate rows=$e, markers=$m)"
    else
      fail_ "A1-$t: ORIGINAL template not the expected RED baseline" "empty=$e markers=$m (want empty>0, markers=0)"
    fi
  else
    echo "  [SKIP] A1-$t: cannot resolve $ORIG_REF (shallow clone?) — RED baseline check skipped"
  fi
done

# A2 — GREEN on the working-tree templates.
for t in personal org; do
  case "$t" in personal) f="$PER_TMPL" ;; org) f="$ORG_TMPL" ;; esac
  e=$(count_empty_gate_rows "$f")
  if [ "$e" -eq 0 ]; then
    pass "A2-$t: no empty-value rows remain in any gate section"
  else
    fail_ "A2-$t: empty-value gate rows still present" "count=$e"
  fi
  miss=$(gate_sections_missing_marker "$f")
  if [ -z "$miss" ]; then
    pass "A2-$t: BL-170-APPEND-DESIGN marker present in every gate section"
  else
    fail_ "A2-$t: gate section(s) missing the append marker" "$(echo "$miss" | tr '\n' ';')"
  fi
  if grep -qE '\[YYYY-MM-DD\]|\[Name|\[Attorney' "$f"; then
    fail_ "A2-$t: BL-138 placeholder bait still present" "found [YYYY-MM-DD]/[Name/[Attorney token"
  else
    pass "A2-$t: no BL-138 placeholder bait remains"
  fi
done

# --- behavioural fixture helpers --------------------------------------------
# Append a completed gate table under the 0->1 header of $1, using field $2 as
# the approver/reviewer LABEL row and $3 as the name.
append_gate01() { # <file> <label(Approver|Reviewer)> <name>
  awk -v lbl="$2" -v nm="$3" '
    { print }
    /^## Phase Gate: Phase 0 / {
      print ""
      print "| Field | Value |"; print "|---|---|"
      print "| **Gate** | Phase 0 to Phase 1 |"
      print "| **" lbl "** | " nm " |"
      print "| **Role** | Project Sponsor |"
      print "| **Date** | " ISO " |"
      print "| **Method** | Email |"
      print "| **Decision** | Approved |"
    }
  ' ISO="$TODAY" "$1" > "$1.t" && mv "$1.t" "$1"
}

# Append filled Application Owner + IT Security tables under the org Phase 3->4
# subsection headers.
append_p34_subsections() { # <file>
  awk -v iso="$TODAY" '
    { print }
    /^### Application Owner Approval$/ {
      print ""; print "| Field | Value |"; print "|---|---|"
      print "| **Gate** | Phase 3 to Phase 4 (Application Owner) |"
      print "| **Approver** | Ada Lovelace |"; print "| **Role** | Application Owner |"
      print "| **Date** | " iso " |"; print "| **Method** | Email |"; print "| **Decision** | Approved |"
    }
    /^### IT Security Approval$/ {
      print ""; print "| Field | Value |"; print "|---|---|"
      print "| **Gate** | Phase 3 to Phase 4 (IT Security) |"
      print "| **Approver** | Grace Hopper |"; print "| **Role** | IT Security |"
      print "| **Date** | " iso " |"; print "| **Method** | Ticket |"; print "| **Decision** | Approved |"
    }
  ' "$1" > "$1.t" && mv "$1.t" "$1"
}

echo "=== B. BEHAVIOURAL CONSUMER CASES ==="
if ! command -v jq >/dev/null 2>&1; then
  echo "  [SKIP] B*: jq not available — gate-date auto-record and phase-state reads require jq."
else
  TODAY="$(date +%Y-%m-%d)"

  # B1+B2+B3(detect) — ORG, appended 0->1, committed BY the approver (self-approval).
  P="$TOPTMP/b-org-self"; mkdir -p "$P/.claude"
  ( cd "$P" && git init -q && git config user.email amb@x.invalid && git config user.name "Ambient Person" )
  printf '%s\n' '{"project":"d","current_phase":1,"deployment":"organizational","track":"standard","gates":{}}' > "$P/.claude/phase-state.json"
  sed -e "s|__PROJECT_NAME__|d|g" -e "s|__TODAY__|$TODAY|g" "$ORG_TMPL" > "$P/APPROVAL_LOG.md"
  append_gate01 "$P/APPROVAL_LOG.md" "Approver" "Ada Lovelace"
  ( cd "$P" && git add -A && git -c user.name="Ada Lovelace" -c user.email=ada@x.invalid commit -qm x )
  out=$( cd "$P" && bash "$CPG" 2>&1 || true )

  if printf '%s' "$out" | grep -q "gate date recorded.*from APPROVAL_LOG.md evidence"; then
    pass "B1: gate-date auto-record found the APPENDED Date (evidence within head-15 window)"
  else
    fail_ "B1: auto-record did not fire on the appended gate table" "$(printf '%s' "$out" | grep -i 'phase 0' | head -2)"
  fi
  if printf '%s' "$out" | grep -qi "placeholder values"; then
    fail_ "B2: BL-138 flagged the append instruction as placeholder values" "unexpected placeholder WARN"
  else
    pass "B2: BL-138 did NOT flag the append instruction text as placeholder values"
  fi
  if printf '%s' "$out" | grep -q "self-approval detected"; then
    pass "B3a: BL-143 read the APPENDED Approver cell — self-approval DETECTED (committer == approver)"
  else
    fail_ "B3a: self-approval NOT detected though committer == approver" "walker missed the appended Approver row"
  fi

  # B3(non-self) — ORG, appended 0->1, committed by a DIFFERENT author.
  P="$TOPTMP/b-org-other"; mkdir -p "$P/.claude"
  ( cd "$P" && git init -q && git config user.email amb@x.invalid && git config user.name "Ambient Person" )
  printf '%s\n' '{"project":"d","current_phase":1,"deployment":"organizational","track":"standard","gates":{}}' > "$P/.claude/phase-state.json"
  sed -e "s|__PROJECT_NAME__|d|g" -e "s|__TODAY__|$TODAY|g" "$ORG_TMPL" > "$P/APPROVAL_LOG.md"
  append_gate01 "$P/APPROVAL_LOG.md" "Approver" "Ada Lovelace"
  ( cd "$P" && git add -A && git -c user.name="Bob Builder" -c user.email=bob@x.invalid commit -qm x )
  out=$( cd "$P" && bash "$CPG" 2>&1 || true )
  if printf '%s' "$out" | grep -q "self-approval detected"; then
    fail_ "B3b: false self-approval FAIL when committer != approver" "walker mis-attributed the approver"
  else
    pass "B3b: no false self-approval when committer != approver"
  fi

  # B4 — ORG Phase 3->4 dual approval, both subsections appended.
  P="$TOPTMP/b-org-p34"; mkdir -p "$P/.claude"
  ( cd "$P" && git init -q && git config user.email amb@x.invalid && git config user.name "Ambient Person" )
  printf '%s\n' '{"project":"d","current_phase":4,"deployment":"organizational","track":"standard","gates":{"phase_0_to_1":"'"$TODAY"'","phase_1_to_2":"'"$TODAY"'","phase_2_to_3":"'"$TODAY"'"}}' > "$P/.claude/phase-state.json"
  sed -e "s|__PROJECT_NAME__|d|g" -e "s|__TODAY__|$TODAY|g" "$ORG_TMPL" > "$P/APPROVAL_LOG.md"
  append_p34_subsections "$P/APPROVAL_LOG.md"
  ( cd "$P" && git add -A && git -c user.name="Carol Author" -c user.email=carol@x.invalid commit -qm x )
  out=$( cd "$P" && bash "$CPG" 2>&1 || true )
  if printf '%s' "$out" | grep -q "both Application Owner and IT Security approvals dated"; then
    pass "B4: appended App Owner + IT Security tables satisfy the Phase 3->4 dual-approval date check"
  elif printf '%s' "$out" | grep -q "gate date recorded.*from APPROVAL_LOG.md evidence" \
       && ! printf '%s' "$out" | grep -q "Application Owner AND IT Security"; then
    pass "B4: Phase 3->4 evidence recorded and no missing-subsection WARN"
  else
    fail_ "B4: Phase 3->4 dual-approval not satisfied by appended subsection tables" "$(printf '%s' "$out" | grep -i 'phase 3' | head -3)"
  fi

  # B5 — PERSONAL, appended 0->1: gate-date auto-record works and no self-approval logic runs.
  P="$TOPTMP/b-per"; mkdir -p "$P/.claude"
  ( cd "$P" && git init -q && git config user.email amb@x.invalid && git config user.name "Ambient Person" )
  printf '%s\n' '{"project":"d","current_phase":1,"deployment":"personal","track":"light","gates":{}}' > "$P/.claude/phase-state.json"
  sed -e "s|__PROJECT_NAME__|d|g" -e "s|__TODAY__|$TODAY|g" "$PER_TMPL" > "$P/APPROVAL_LOG.md"
  append_gate01 "$P/APPROVAL_LOG.md" "Reviewer" "Self"
  ( cd "$P" && git add -A && git commit -qm x )
  out=$( cd "$P" && bash "$CPG" 2>&1 || true )
  if printf '%s' "$out" | grep -q "gate date recorded.*from APPROVAL_LOG.md evidence"; then
    pass "B5: personal appended 0->1 table auto-records the gate date"
  else
    fail_ "B5: personal auto-record did not fire" "$(printf '%s' "$out" | grep -i 'phase 0' | head -2)"
  fi
fi

echo "=== C. MUTATION PROOFS (pins are load-bearing) ==="

# C1 — inject an empty placeholder row back into a gate section -> empty-row pin RED.
mut="$TOPTMP/mut-empty.tmpl"
awk '
  { print }
  /^## Phase Gate: Phase 0 / && !done { print "| **Reviewer** | |"; done = 1 }
' "$PER_TMPL" > "$mut"
e=$(count_empty_gate_rows "$mut")
if [ "$e" -gt 0 ]; then
  pass "C1: re-injecting an empty '| **Reviewer** | |' row flips the empty-row pin RED (count=$e)"
else
  fail_ "C1: empty-row pin did NOT catch a re-injected placeholder" "detector is not load-bearing"
fi

# C2 — strip the marker from a gate section -> marker pin RED.
mut2="$TOPTMP/mut-marker.tmpl"
# Remove ONLY the first gate-section marker occurrence (leave the top-of-file one).
awk '
  /^## Phase Gate:/ { ingate = 1 }
  ingate && /BL-170-APPEND-DESIGN/ && !stripped { stripped = 1; next }
  { print }
' "$PER_TMPL" > "$mut2"
miss=$(gate_sections_missing_marker "$mut2")
if [ -n "$miss" ]; then
  pass "C2: stripping a gate-section marker flips the marker pin RED ($(echo "$miss" | head -1))"
else
  fail_ "C2: marker pin did NOT catch a stripped marker" "detector is not load-bearing"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
