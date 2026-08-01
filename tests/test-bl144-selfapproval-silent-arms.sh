#!/usr/bin/env bash
# tests/test-bl144-selfapproval-silent-arms.sh — BL-144 (Dogfood-3 SHOULD-fix
# wave verifier, S1+S2): the two shapes for which the self-approval scan in
# scripts/check-phase-gate.sh::validate_approval_fields stayed FULLY SILENT
# after BL-143.
#
# THE DEFECTS (both executed, both byte-for-byte pre-existing)
#   (a) MALFORMED HEADER + PAST-CAP, combined. A gate section whose header is
#       `### ` (not the canonical `## `) AND whose Approver row sits past the
#       walker pre-extraction's `grep -A 20` cap. The `# BL-143-PASTCAP-
#       RECOVERY` awk computes NO_SECTION and its generic `''|*[!0-9]*)` arm
#       DISCARDS it; the walker's own loud malformed-header refusal is
#       unreachable because it only runs once a name was pre-extracted, and a
#       past-cap row yields none. An attacker combining the two evasions got
#       ZERO output — measured on the pre-fix script: the gate printed
#       "Phase gates consistent." and exited 0 over a genuine self-approval.
#   (b) PAST-CAP PLACEHOLDER / BLANK APPROVER CELL. The BL-138 placeholder
#       predicate is `head -20`-capped, so a past-cap `| **Approver** |
#       [Name] |` never reaches it; the recovery then RECOVERS `[Name]`,
#       recognizes it in its own trigger condition, and drops it silently.
#       A BLANK cell escapes the BL-138 predicate at ANY distance (it carries
#       no template literal), so it was silent in-cap too.
#
# THE FIX — both arms are WARN-that-BLOCKS (they increment `issues`, which IS
# the gate's exit predicate; the [WARN] label is cosmetic — CLAUDE.md § THE
# [WARN] TRAP). That is what the BL-144 entry prescribes and what the arms
# around them already do:
#   (a) `# BL-144-NO-SECTION` surfaces the recovery's NO_SECTION "through the
#       walker's existing WARN" (the entry's words) — literally the same
#       string via `_cpg_warn_no_gate_section`, with the same increment the
#       walker's arm has always had. Deliberate scope call carried from the
#       entry: prose-only gate mentions also become loud.
#   (b) `# BL-144-PLACEHOLDER-CELL` WARNs when the recovered name is
#       `[Name]`/empty, matching the BL-138 placeholder WARN's blocking
#       semantics so a past-cap `[Name]` is exactly as blocking as the in-cap
#       `[Name]` that predicate already refuses.
#   PINNED BOUNDARY: BL-143's T4 (an entry with NO Approver row anywhere) maps
#   to NO_APPROVER, not NO_SECTION — U8 keeps it silent.
#
# ORACLE: the EXIT CODE, never the label. Every fixture below is built so the
# defect under test is the ONLY inconsistency in the project, so each silent
# arm shows up as rc 0 -> 1 plus a summary line reading exactly
# "1 inconsistency(ies) found" — the rendered value of `issues`.
#
# FIXTURES ARE THE SHIPPED ARTIFACT: every APPROVAL_LOG.md here is
# templates/generated/approval-log-org.tmpl rendered as init.sh renders it
# (generate_approval_log: __PROJECT_NAME__ / __TODAY__), then filled the way
# the template's own BL-170 append-design instructions say to fill it —
# pre-condition rows appended under the Pre-Phase-0 table, a completed
# approval table appended under the gate header above its closing `---`. Not
# a hand-rolled miniature. U0 asserts the template anchors the builder rides
# on still exist and that each built fixture really exhibits its shape.
#
# REGISTRATION: no init.sh, not an aggregator -> BOTH lists. Hermetic
# (mktemp fixtures, local commits only, no network). bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-phase-gate.sh"
TMPL="$REPO_ROOT/templates/generated/approval-log-org.tmpl"

# House rule: fixture git ops must not inherit a CI base ref.
unset GITHUB_BASE_REF 2>/dev/null || true

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

ESC=$(printf '\033')
strip_ansi() { sed "s/${ESC}\[[0-9;]*m//g"; }

GATE_H2='## Phase Gate: Phase 0 → Phase 1'
GATE_H3='### Phase Gate: Phase 0 → Phase 1'
PRECOND_SEP='|---|---|---|---|---|---|---|---|'

WARN_NO_SECTION="no '## ' header matching gate"
WARN_CELL="Approver cell is a placeholder or blank"
WARN_BL138="contains placeholder values"
NO_SECTION_MSG="APPROVAL_LOG.md has no '## ' header matching gate"

# build_log <dest> <h2|h3> <incap|pastcap> <approver-cell-text|__NONE__>
#
# Renders the SHIPPED org approval-log template and fills it per its own
# instructions. `__NONE__` appends no approval table at all (the scaffolded
# shape — BL-143's pinned no-Approver-row boundary).
#
# Field order inside the appended table puts the Date row early on purpose:
# `_cpg_gate_has_evidence` reads the first 15 lines of the section, so the
# fixture stays otherwise-clean even when 22 evidence rows push the Approver
# row past every `grep -A 20` window.
build_log() {
  local dest="$1" hstyle="$2" pos="$3" approver="$4"
  local rendered="$dest.rendered"
  local line i in_target=0 block_done=0
  sed -e "s|__PROJECT_NAME__|BL144 Fixture|g" -e "s|__TODAY__|2026-01-15|g" \
    "$TMPL" > "$rendered" || return 1

  : > "$dest"
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$GATE_H2" ]; then
      if [ "$hstyle" = "h3" ]; then
        printf '%s\n' "$GATE_H3" >> "$dest"
      else
        printf '%s\n' "$GATE_H2" >> "$dest"
      fi
      in_target=1
      continue
    fi
    if [ "$in_target" -eq 1 ] && [ "$block_done" -eq 0 ] && [ "$line" = "---" ]; then
      if [ "$approver" != "__NONE__" ]; then
        {
          printf '%s\n' '| Field | Value |'
          printf '%s\n' '|---|---|'
          printf '%s\n' '| **Gate** | Phase 0 → Phase 1 |'
          printf '%s\n' '| **Date** | 2026-02-01 |'
          printf '%s\n' '| **Method** | Email |'
          printf '%s\n' '| **Reference** | TICK-100 |'
          if [ "$pos" = "pastcap" ]; then
            for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22; do
              printf '| **Artifacts reviewed (%s)** | evidence item %s |\n' "$i" "$i"
            done
          fi
          printf '| **Approver** | %s |\n' "$approver"
          printf '%s\n' '| **Role** | Project Sponsor |'
          printf '%s\n' '| **Decision** | Approved |'
        } >> "$dest"
      fi
      printf '%s\n' '---' >> "$dest"
      in_target=0
      block_done=1
      continue
    fi
    if [ "$line" = "$PRECOND_SEP" ]; then
      {
        printf '%s\n' "$line"
        printf '%s\n' '| 1 | AI deployment path approved | Ada Owner | IT Security | 2026-01-15 | Email | TICK-1 | |'
        printf '%s\n' '| 2 | Insurance coverage confirmed | Ada Owner | Insurance Broker | 2026-01-15 | Email | TICK-2 | |'
        printf '%s\n' '| 3 | Liability entity designated | Ada Owner | Legal / CIO | 2026-01-15 | Email | TICK-3 | |'
        printf '%s\n' '| 4 | Project sponsor assigned | Ada Owner | Executive Sponsor | 2026-01-15 | Email | TICK-4 | |'
        printf '%s\n' '| 5 | Backup maintainer designated | Ada Owner | Technical Lead | 2026-01-15 | Email | TICK-5 | |'
        printf '%s\n' '| 6 | ITSM project registered | Ada Owner | ITSM / PMO | 2026-01-15 | Email | TICK-6 | |'
      } >> "$dest"
      continue
    fi
    printf '%s\n' "$line" >> "$dest"
  done < "$rendered"
  rm -f "$rendered"
  [ "$block_done" -eq 1 ]
}

# mk_proj <dir> <h2|h3> <incap|pastcap> <approver-cell|__NONE__> <commit-author>
# A phase-1 ORGANIZATIONAL project (the self-approval control is org-only).
mk_proj() {
  local d="$1" hstyle="$2" pos="$3" approver="$4" author="$5" i
  rm -rf "$d"
  mkdir -p "$d/.claude" "$d/docs/phase-0" || return 1
  ( cd "$d" && git init -q \
      && git config user.email "ambient@example.invalid" \
      && git config user.name  "Ambient Operator" \
      && git config commit.gpgsign false ) || return 1
  cat > "$d/.claude/phase-state.json" <<'JSON'
{"current_phase":1,"track":"standard","deployment":"organizational","poc_mode":null,"gates":{"phase_0_to_1":"2026-02-01"}}
JSON
  printf 'frd\n'      > "$d/docs/phase-0/frd.md"
  printf 'journey\n'  > "$d/docs/phase-0/user-journey.md"
  printf 'contract\n' > "$d/docs/phase-0/data-contract.md"
  {
    echo "# PRODUCT_MANIFESTO"
    for i in 1 2 3 4 5 6 7 8; do
      echo "## ${i}. Section ${i}"
      echo "Real content for section ${i}."
      echo ""
    done
  } > "$d/PRODUCT_MANIFESTO.md"

  build_log "$d/APPROVAL_LOG.md" "$hstyle" "$pos" "$approver" || return 1

  ( cd "$d" && git add -A \
      && GIT_AUTHOR_NAME="$author" GIT_AUTHOR_EMAIL="author@example.invalid" \
         GIT_COMMITTER_NAME="$author" GIT_COMMITTER_EMAIL="author@example.invalid" \
         git commit -qm "record phase 0 to 1 approval" ) || return 1
}

# run_gate <dir> <ambient-git-user> [script-override]
# Prints the ANSI-stripped gate output. The exit code lands in $TOPTMP/last_rc
# (a file, not a variable: the caller reads this through `$( )`, so anything
# the function assigns dies with the subshell).
run_gate() {
  local d="$1" user="$2" script="${3:-$SCRIPT}" out rc
  out=$( cd "$d" && git config user.name "$user" \
           && bash "$script" </dev/null 2>&1 )
  rc=$?
  printf '%s' "$rc" > "$TOPTMP/last_rc"
  printf '%s\n' "$out" | strip_ansi
}
last_rc() { cat "$TOPTMP/last_rc" 2>/dev/null || echo "none"; }

# issue_count <output> — the rendered value of the gate's `issues` counter.
issue_count() {
  printf '%s\n' "$1" | sed -n 's/^\([0-9][0-9]*\) inconsistency(ies) found.*/\1/p' | head -1
}

# ── U0: fixture integrity — the shipped template + the built shapes ──────────
echo "U0: fixtures are the SHIPPED template and really exhibit their shapes"
u0_ok=1
for anchor in "$GATE_H2" "$PRECOND_SEP"; do
  if ! grep -qF -- "$anchor" "$TMPL"; then
    fail_ "U0-template-anchor" "templates/generated/approval-log-org.tmpl no longer contains the anchor the builder rides on: '$anchor' — every fixture below would be silently miniature"
    u0_ok=0
  fi
done
U0A="$TOPTMP/u0a"; mk_proj "$U0A" h3 pastcap "Karl Raulerson" "Karl Raulerson" || u0_ok=0
U0B="$TOPTMP/u0b"; mk_proj "$U0B" h2 incap   "Karl Raulerson" "Karl Raulerson" || u0_ok=0
if [ "$u0_ok" -eq 1 ]; then
  # Distance from the LAST gate-name mention to the Approver row decides
  # in-cap vs past-cap: `grep -A 20` windows from EVERY match.
  gl_a=$(grep -n 'Phase 0.*Phase 1' "$U0A/APPROVAL_LOG.md" | tail -1 | cut -d: -f1)
  ar_a=$(grep -n '^| \*\*Approver\*\*' "$U0A/APPROVAL_LOG.md" | tail -1 | cut -d: -f1)
  gl_b=$(grep -n 'Phase 0.*Phase 1' "$U0B/APPROVAL_LOG.md" | tail -1 | cut -d: -f1)
  ar_b=$(grep -n '^| \*\*Approver\*\*' "$U0B/APPROVAL_LOG.md" | tail -1 | cut -d: -f1)
  d_a=$((ar_a - gl_a))
  d_b=$((ar_b - gl_b))
  if grep -q '^### Phase Gate: Phase 0' "$U0A/APPROVAL_LOG.md" \
     && ! grep -q '^## Phase Gate: Phase 0' "$U0A/APPROVAL_LOG.md" \
     && grep -q '^## Phase Gate: Phase 0' "$U0B/APPROVAL_LOG.md" \
     && [ "$d_a" -gt 20 ] && [ "$d_b" -le 20 ] \
     && grep -qF 'BL-170-APPEND-DESIGN' "$U0A/APPROVAL_LOG.md"; then
    pass "U0-fixture-integrity (h3 header substituted; Approver row +$d_a lines past the last gate mention vs +$d_b in-cap; shipped template body intact)"
  else
    fail_ "U0-fixture-integrity" "built fixture does not exhibit its declared shape: pastcap-delta=$d_a incap-delta=$d_b h3=$(grep -c '^### Phase Gate: Phase 0' "$U0A/APPROVAL_LOG.md") h2-in-h3-fixture=$(grep -c '^## Phase Gate: Phase 0' "$U0A/APPROVAL_LOG.md")"
  fi
fi

# ── U1 (arm a, the filed shape): `### ` header + past-cap SELF-approval ──────
echo "U1: malformed ### header + past-cap Approver, author == approver → LOUD + rc=1"
U1="$TOPTMP/u1"
if mk_proj "$U1" h3 pastcap "Karl Raulerson" "Karl Raulerson"; then
  out=$(run_gate "$U1" "Karl Raulerson"); rc=$(last_rc)
  n=$(issue_count "$out")
  if printf '%s\n' "$out" | grep -qF "$WARN_NO_SECTION" && [ "$rc" = "1" ] && [ "${n:-0}" = "1" ]; then
    pass "U1-malformed-plus-pastcap-loud (rc=$rc, issues=$n — the WARN increments the exit predicate, it does not merely print)"
  else
    fail_ "U1-malformed-plus-pastcap-loud" "rc=$rc issues=${n:-none} — an executed self-approval behind a ### header AND a past-cap row produced no refusal: $(printf '%s\n' "$out" | tail -2 | tr '\n' ' ')"
  fi
else
  fail_ "U1-malformed-plus-pastcap-loud" "fixture build failed"
fi

# ── U2 (arm a): the past-cap refusal is the walker's EXISTING WARN, verbatim ─
echo "U2: past-cap malformed header emits the byte-identical line the in-cap twin emits"
U2="$TOPTMP/u2"
if mk_proj "$U2" h3 incap "Karl Raulerson" "Karl Raulerson"; then
  out_incap=$(run_gate "$U2" "Karl Raulerson")
  out_pastcap=$(run_gate "$U1" "Karl Raulerson")
  line_incap=$(printf '%s\n' "$out_incap"     | grep -F "$WARN_NO_SECTION" | head -1)
  line_pastcap=$(printf '%s\n' "$out_pastcap" | grep -F "$WARN_NO_SECTION" | head -1)
  if [ -n "$line_incap" ] && [ "$line_incap" = "$line_pastcap" ]; then
    pass "U2-warn-parity (surfaced THROUGH the walker's existing WARN — one string, one source)"
  else
    fail_ "U2-warn-parity" "in-cap and past-cap malformed headers disagree; in-cap='$line_incap' past-cap='$line_pastcap'"
  fi
else
  fail_ "U2-warn-parity" "fixture build failed"
fi

# ── U3 (control): canonical header + past-cap + a REAL distinct approver ─────
echo "U3: canonical header, past-cap, distinct approver committed by another → rc=0, no new WARN"
U3="$TOPTMP/u3"
if mk_proj "$U3" h2 pastcap "Karla Approver" "Bob Committer"; then
  out=$(run_gate "$U3" "Karl"); rc=$(last_rc)
  if [ "$rc" = "0" ] \
     && ! printf '%s\n' "$out" | grep -qF "$WARN_NO_SECTION" \
     && ! printf '%s\n' "$out" | grep -qF "$WARN_CELL"; then
    pass "U3-clean-control (the fixture family is otherwise spotless — that is what makes U1/U4/U5's rc 0→1 non-vacuous — and neither new arm is a blanket refusal)"
  else
    fail_ "U3-clean-control" "rc=$rc — a legitimate past-cap approval was refused: $(printf '%s\n' "$out" | grep -E 'WARN|FAIL' | head -3 | tr '\n' ' ')"
  fi
else
  fail_ "U3-clean-control" "fixture build failed"
fi

# ── U4 (arm b): past-cap `[Name]` placeholder cell ───────────────────────────
echo "U4: past-cap Approver cell is [Name] → LOUD + rc=1"
U4="$TOPTMP/u4"
if mk_proj "$U4" h2 pastcap "[Name]" "Bob Committer"; then
  out=$(run_gate "$U4" "Karl"); rc=$(last_rc)
  n=$(issue_count "$out")
  if printf '%s\n' "$out" | grep -qF "$WARN_CELL" && [ "$rc" = "1" ] && [ "${n:-0}" = "1" ]; then
    pass "U4-pastcap-placeholder-loud (rc=$rc, issues=$n — recovered, recognized, and now REPORTED)"
  else
    fail_ "U4-pastcap-placeholder-loud" "rc=$rc issues=${n:-none} — the recovery recovered [Name] and dropped it silently: $(printf '%s\n' "$out" | tail -2 | tr '\n' ' ')"
  fi
else
  fail_ "U4-pastcap-placeholder-loud" "fixture build failed"
fi

# ── U5 (arm b): past-cap BLANK cell ──────────────────────────────────────────
echo "U5: past-cap Approver cell is blank → LOUD + rc=1"
U5="$TOPTMP/u5"
if mk_proj "$U5" h2 pastcap "" "Bob Committer"; then
  out=$(run_gate "$U5" "Karl"); rc=$(last_rc)
  n=$(issue_count "$out")
  if printf '%s\n' "$out" | grep -qF "$WARN_CELL" && [ "$rc" = "1" ] && [ "${n:-0}" = "1" ]; then
    pass "U5-pastcap-blank-loud (rc=$rc, issues=$n)"
  else
    fail_ "U5-pastcap-blank-loud" "rc=$rc issues=${n:-none} — a blank Approver cell still passes the gate green: $(printf '%s\n' "$out" | tail -2 | tr '\n' ' ')"
  fi
else
  fail_ "U5-pastcap-blank-loud" "fixture build failed"
fi

# ── U6 (arm b): IN-CAP blank cell — the BL-138 predicate has no blank arm ────
echo "U6: in-cap Approver cell is blank → LOUD + rc=1 (no template literal to match, so BL-138 never saw it)"
U6="$TOPTMP/u6"
if mk_proj "$U6" h2 incap "" "Bob Committer"; then
  out=$(run_gate "$U6" "Karl"); rc=$(last_rc)
  n=$(issue_count "$out")
  if printf '%s\n' "$out" | grep -qF "$WARN_CELL" && [ "$rc" = "1" ] && [ "${n:-0}" = "1" ]; then
    pass "U6-incap-blank-loud (rc=$rc, issues=$n)"
  else
    fail_ "U6-incap-blank-loud" "rc=$rc issues=${n:-none} — a blank Approver cell is silent at close range too: $(printf '%s\n' "$out" | tail -2 | tr '\n' ' ')"
  fi
else
  fail_ "U6-incap-blank-loud" "fixture build failed"
fi

# ── U7 (arm b): in-cap `[Name]` stays the BL-138 report — exactly ONE issue ──
echo "U7: in-cap [Name] keeps the BL-138 message and costs exactly ONE issue (no double report)"
U7="$TOPTMP/u7"
if mk_proj "$U7" h2 incap "[Name]" "Bob Committer"; then
  out=$(run_gate "$U7" "Karl"); rc=$(last_rc)
  n=$(issue_count "$out")
  cells=$(printf '%s\n' "$out" | grep -cF "$WARN_CELL") || cells=0
  case "$cells" in ''|*[!0-9]*) cells=0 ;; esac
  if printf '%s\n' "$out" | grep -qF "$WARN_BL138" && [ "$cells" -eq 0 ] \
     && [ "$rc" = "1" ] && [ "${n:-0}" = "1" ]; then
    pass "U7-no-double-report (BL-138 still owns the cells inside its window; issues=$n)"
  else
    fail_ "U7-no-double-report" "rc=$rc issues=${n:-none} extra-cell-warns=$cells — one placeholder cell was reported twice (or the BL-138 message was displaced): $(printf '%s\n' "$out" | grep -E 'WARN|FAIL' | head -3 | tr '\n' ' ')"
  fi
else
  fail_ "U7-no-double-report" "fixture build failed"
fi

# ── U8: BL-143's T4 boundary — NO Approver row anywhere stays SILENT ─────────
echo "U8: scaffolded template, no Approver row at all → neither new arm fires (NO_APPROVER, not NO_SECTION)"
U8="$TOPTMP/u8"
if mk_proj "$U8" h2 incap "__NONE__" "Bob Committer"; then
  # Section-scoped: the shipped template's own instruction block at the top of
  # the file carries a `| **Approver** | approver name |` line inside a fenced
  # code sample, far above the gate header — the boundary that matters is that
  # the GATE SECTION has no Approver row.
  u8_section=$(sed -n '/^## Phase Gate: Phase 0/,/^---$/p' "$U8/APPROVAL_LOG.md")
  if printf '%s\n' "$u8_section" | grep -q 'Approver'; then
    fail_ "U8-absent-row-boundary" "fixture's gate section still has an Approver row — the boundary shape was not built"
  else
    out=$(run_gate "$U8" "Karl")
    if ! printf '%s\n' "$out" | grep -qF "$WARN_NO_SECTION" \
       && ! printf '%s\n' "$out" | grep -qF "$WARN_CELL"; then
      pass "U8-absent-row-boundary (the declared nothing-to-verify boundary is untouched — BL-143 T4 maps to NO_APPROVER)"
    else
      fail_ "U8-absent-row-boundary" "a new arm swallowed BL-143's pinned boundary: $(printf '%s\n' "$out" | grep -F -e "$WARN_NO_SECTION" -e "$WARN_CELL" | head -2 | tr '\n' ' ')"
    fi
  fi
else
  fail_ "U8-absent-row-boundary" "fixture build failed"
fi

# ── U9: mutation, arm (a) — excise # BL-144-NO-SECTION → U1 goes silent ──────
echo "U9: excise # BL-144-NO-SECTION → U1's fixture is silently green again"
MUT_A="$TOPTMP/mut-a"
mkdir -p "$MUT_A"
cp -R "$REPO_ROOT/scripts/lib" "$MUT_A/lib"
before=$(grep -c 'BL-144-NO-SECTION-BEGIN\|BL-144-NO-SECTION-END' "$SCRIPT") || before=0
case "$before" in ''|*[!0-9]*) before=0 ;; esac
sed '/# BL-144-NO-SECTION-BEGIN/,/# BL-144-NO-SECTION-END/d' "$SCRIPT" > "$MUT_A/check-phase-gate.sh"
after=$(grep -c 'BL-144-NO-SECTION-BEGIN\|BL-144-NO-SECTION-END' "$MUT_A/check-phase-gate.sh") || after=0
case "$after" in ''|*[!0-9]*) after=0 ;; esac
chmod +x "$MUT_A/check-phase-gate.sh"
if [ "$before" -ne 2 ] || [ "$after" -ne 0 ] || ! bash -n "$MUT_A/check-phase-gate.sh" 2>/dev/null; then
  fail_ "U9-mutation-arm-a" "excision vacuous or non-parsing (markers before=$before after=$after)"
else
  out=$(run_gate "$U1" "Karl Raulerson" "$MUT_A/check-phase-gate.sh"); rc=$(last_rc)
  if ! printf '%s\n' "$out" | grep -qF "$WARN_NO_SECTION" && [ "$rc" = "0" ]; then
    pass "U9-mutation-arm-a (rc=$rc, silence restored exactly — the fence IS the detection)"
  else
    fail_ "U9-mutation-arm-a" "rc=$rc — the mutant still refused, so arm (a) does not live (only) inside its fence: $(printf '%s\n' "$out" | tail -2 | tr '\n' ' ')"
  fi
fi

# ── U10: mutation, arm (b) — excise # BL-144-PLACEHOLDER-CELL → U4/U5 silent ─
echo "U10: excise # BL-144-PLACEHOLDER-CELL → U4's and U5's fixtures are silently green again"
MUT_B="$TOPTMP/mut-b"
mkdir -p "$MUT_B"
cp -R "$REPO_ROOT/scripts/lib" "$MUT_B/lib"
before=$(grep -c 'BL-144-PLACEHOLDER-CELL-BEGIN\|BL-144-PLACEHOLDER-CELL-END' "$SCRIPT") || before=0
case "$before" in ''|*[!0-9]*) before=0 ;; esac
sed '/# BL-144-PLACEHOLDER-CELL-BEGIN/,/# BL-144-PLACEHOLDER-CELL-END/d' "$SCRIPT" > "$MUT_B/check-phase-gate.sh"
after=$(grep -c 'BL-144-PLACEHOLDER-CELL-BEGIN\|BL-144-PLACEHOLDER-CELL-END' "$MUT_B/check-phase-gate.sh") || after=0
case "$after" in ''|*[!0-9]*) after=0 ;; esac
chmod +x "$MUT_B/check-phase-gate.sh"
if [ "$before" -ne 2 ] || [ "$after" -ne 0 ] || ! bash -n "$MUT_B/check-phase-gate.sh" 2>/dev/null; then
  fail_ "U10-mutation-arm-b" "excision vacuous or non-parsing (markers before=$before after=$after)"
else
  out4=$(run_gate "$U4" "Karl" "$MUT_B/check-phase-gate.sh"); rc4=$(last_rc)
  out5=$(run_gate "$U5" "Karl" "$MUT_B/check-phase-gate.sh"); rc5=$(last_rc)
  if ! printf '%s\n' "$out4" | grep -qF "$WARN_CELL" && [ "$rc4" = "0" ] \
     && ! printf '%s\n' "$out5" | grep -qF "$WARN_CELL" && [ "$rc5" = "0" ]; then
    pass "U10-mutation-arm-b (rc=$rc4/$rc5, silence restored exactly for both the [Name] and blank shapes)"
  else
    fail_ "U10-mutation-arm-b" "rc4=$rc4 rc5=$rc5 — the mutant still reported, so arm (b) does not live (only) inside its fence"
  fi
fi

# ── U11: the malformed-header message has exactly ONE source, load-bearing ───
echo "U11: one copy of the malformed-header message; delete it → in-cap AND past-cap both go quiet"
copies=$(grep -c "$NO_SECTION_MSG" "$SCRIPT") || copies=0
case "$copies" in ''|*[!0-9]*) copies=0 ;; esac
MUT_C="$TOPTMP/mut-c"
mkdir -p "$MUT_C"
cp -R "$REPO_ROOT/scripts/lib" "$MUT_C/lib"
sed "/APPROVAL_LOG.md has no '## ' header matching gate/d" "$SCRIPT" > "$MUT_C/check-phase-gate.sh"
chmod +x "$MUT_C/check-phase-gate.sh"
if [ "$copies" -ne 1 ] || ! bash -n "$MUT_C/check-phase-gate.sh" 2>/dev/null; then
  fail_ "U11-shared-helper-single-source" "message copies in the script = $copies (want exactly 1 — two copies can drift), or the mutant does not parse"
else
  outc1=$(run_gate "$U1" "Karl Raulerson" "$MUT_C/check-phase-gate.sh"); rcc1=$(last_rc)
  outc2=$(run_gate "$U2" "Karl Raulerson" "$MUT_C/check-phase-gate.sh"); rcc2=$(last_rc)
  if ! printf '%s\n' "$outc1" | grep -qF "$WARN_NO_SECTION" \
     && ! printf '%s\n' "$outc2" | grep -qF "$WARN_NO_SECTION" \
     && [ "$rcc1" = "1" ] && [ "$rcc2" = "1" ]; then
    pass "U11-shared-helper-single-source (both arms speak through _cpg_warn_no_gate_section; deleting its line mutes both while the issues increment survives, rc=$rcc1/$rcc2)"
  else
    fail_ "U11-shared-helper-single-source" "rc=$rcc1/$rcc2 — a second copy of the malformed-header message exists, or the increment vanished with the message: $(printf '%s\n' "$outc1" "$outc2" | grep -F "$WARN_NO_SECTION" | head -2 | tr '\n' ' ')"
  fi
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
