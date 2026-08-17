#!/usr/bin/env bash
# tests/test-bl230-workflow-html-lint-surface.sh
#
# BL-230 — `workflow.html` cites 13 code markers, 3 backlog entries, 7 relative
# doc paths and 2 in-page anchors, and sat OUTSIDE every lint surface:
# `lint-doc-anchors.sh` walks `find "$DOCS_DIR" -name '*.md'` and the file is
# neither `*.md` nor under `docs/`; `lint-bl-markers.sh`'s prose surface is
# CLAUDE.md, README.md, CONTRIBUTING.md, the backlog and `docs/**`. Adversarial
# review proved it by MUTATION — it broke a relative link and corrupted a cited
# marker, ran both lints, and got rc 0 from each.
#
# The page's whole value is that an operator can trust it. It went six weeks and
# ~40 PRs out of date once, and a human asking was the only thing that noticed.
#
# ── WHAT THIS SUITE PINS, AND THE TWO TRAPS IT IS BUILT AROUND ──────────────
# TRAP 1 — a naive extractor REDS ON A CORRECT PAGE. The page contains
# marker-SHAPED tokens that are not marker citations:
#     <code>## BL-219:</code>              a backlog ENTRY id (`##`, colon)
#     <code>… --retro DELTA-NNN …</code>   a placeholder inside a command
# `F1` requires the clean fixture to pass WITH both present, so a future
# tightening cannot start crying wolf on legitimate prose.
#
# TRAP 2 — a `#`-only reader CHECKS 12 OF 13 AND REPORTS CLEAN. One real
# citation, `BL-170-APPEND-DESIGN`, is written `<code>&lt;!-- MARKER --&gt;</code>`
# because the file it marks is a `.tmpl` with no `#` comment syntax. `M3` breaks
# exactly that citation, and `M4` proves the `<!--` alternative is load-bearing
# by deleting it from a COPY of the lint and watching M3's mutation survive.
#
# Every case runs the REAL lint against a fixture tree. Hermetic: temp dirs,
# no network, no writes to the repo. bash 3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ANCHORS="$REPO_ROOT/scripts/lint-doc-anchors.sh"
MARKERS="$REPO_ROOT/scripts/lint-bl-markers.sh"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'chmod -R u+rwX "$TOPTMP" 2>/dev/null; rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/caseXXXXXX"; }
_num() { case "$1" in ''|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$1" ;; esac }

# mk_fixture <dir> — a miniature tree with the same shapes the real page uses.
# The HTML deliberately carries BOTH citation forms, an entry id, and a
# placeholder, so a clean run proves the extractor discriminates rather than
# merely matching something.
mk_fixture() {
  local d="$1"
  mkdir -p "$d/docs" "$d/scripts" "$d/templates"

  printf '# Doc\n\nA heading to link to.\n' > "$d/docs/guide.md"
  printf '# Readme\n' > "$d/README.md"

  # Code surface: the markers the page cites must EXIST here.
  cat > "$d/scripts/thing.sh" <<'SH'
#!/usr/bin/env bash
run_gate() { :; }            # BL-070-GATE-CHECK
write_it()  { :; }           # BL-071-WRITE
SH
  # An HTML-comment marker, in a template — the shape with no `#` syntax.
  printf '<!-- BL-170-APPEND-DESIGN -->\ncontent\n' > "$d/templates/approval.tmpl"

  cat > "$d/solo-orchestrator-backlog.md" <<'MD'
## BL-070: gate check
**Status:** Closed — PR #1

## BL-071: write
**Status:** Closed — PR #1

## BL-170: append design
**Status:** Closed — PR #1

## BL-219: an entry the page references by id
**Status:** Open
MD

  cat > "$d/workflow.html" <<'HTML'
<!doctype html>
<html><body>
<h2 id="alpha">Alpha</h2>
<h2 id="beta">Beta</h2>
<p>Jump to <a href="#alpha">Alpha</a> and <a href="#beta">Beta</a>.</p>
<p>See <a href="docs/guide.md">the guide</a> and <a href="README.md">the readme</a>.</p>
<p>The gate is <code>#&nbsp;BL-070-GATE-CHECK</code> and the writer is
   <code>#&nbsp;BL-071-WRITE</code>.</p>
<p>The append contract is <code>&lt;!-- BL-170-APPEND-DESIGN --&gt;</code>.</p>
<p>Tracked as <code>## BL-219:</code>, and the command is
   <code>scripts/delta.sh --retro DELTA-NNN --record "x"</code>.</p>
</body></html>
HTML
}

run_anchors() { ( cd "$1" && bash "$ANCHORS" --docs-dir "$1/docs" 2>&1 ); }
run_markers() { ( cd "$1" && bash "$MARKERS" --root "$1" 2>&1 ); }

echo "=== F — the clean fixture passes BOTH lints (and does not cry wolf) ==="

F="$(newtmp)"; mk_fixture "$F"
f1a=$(run_anchors "$F"); f1a_rc=$?
f1m=$(run_markers "$F"); f1m_rc=$?
if [ "$f1a_rc" -eq 0 ] && [ "$f1m_rc" -eq 0 ]; then
  pass "F1: a correct page passes both lints WITH an entry id (<code>## BL-219:</code>) and a placeholder (DELTA-NNN) present — the extractor discriminates a citation from a marker-shaped token instead of matching anything that looks like one"
else
  fail_ "F1" "anchors rc=$f1a_rc markers rc=$f1m_rc (want 0/0) — a correct page must not red. anchors: $(printf '%s' "$f1a" | tail -2 | tr '\n' ' ') | markers: $(printf '%s' "$f1m" | tail -2 | tr '\n' ' ')"
fi

# F2: the marker lint must actually SEE the page — a pass proves nothing if it
# scanned nothing. Both citation forms must be rendered as resolved rows.
f2=$( cd "$F" && bash "$MARKERS" --root "$F" --list 2>/dev/null )
f2_hash=$(_num "$(printf '%s' "$f2" | grep -c 'workflow.html.*BL-070-GATE-CHECK')")
f2_html=$(_num "$(printf '%s' "$f2" | grep -c 'workflow.html.*BL-170-APPEND-DESIGN')")
if [ "$f2_hash" -ge 1 ] && [ "$f2_html" -ge 1 ]; then
  pass "F2: --list shows workflow.html rows for BOTH forms — the '#'-prefixed citation and the '<!--'-prefixed one. A green lint that rendered no rows would be a pass over an unscanned file"
else
  fail_ "F2" "hash-form rows=$f2_hash html-form rows=$f2_html (want >=1 each) — the page is not actually in the prose surface"
fi

echo "=== L — the link/anchor arm (lint-doc-anchors) ==="

L2="$(newtmp)"; mk_fixture "$L2"
sed -i.bak 's|href="docs/guide.md"|href="docs/GONE.md"|' "$L2/workflow.html" && rm -f "$L2/workflow.html.bak"
l2=$(run_anchors "$L2"); l2_rc=$?
if [ "$l2_rc" -eq 1 ] && printf '%s' "$l2" | grep -q 'docs/GONE.md'; then
  pass "L2: a relative doc link that does not resolve fails the lint and names the target — this is the mutation adversarial review ran to prove the page was unguarded, and it now reds"
else
  fail_ "L2" "rc=$l2_rc (want 1) named=$(printf '%s' "$l2" | grep -c 'GONE') (want >=1)"
fi

L3="$(newtmp)"; mk_fixture "$L3"
sed -i.bak 's|href="#beta"|href="#betaZ"|' "$L3/workflow.html" && rm -f "$L3/workflow.html.bak"
l3=$(run_anchors "$L3"); l3_rc=$?
if [ "$l3_rc" -eq 1 ] && printf '%s' "$l3" | grep -q 'betaZ'; then
  pass "L3: an in-page anchor with no matching id= fails and names it — the page's own table of contents cannot rot silently"
else
  fail_ "L3" "rc=$l3_rc (want 1) named=$(printf '%s' "$l3" | grep -c 'betaZ') (want >=1)"
fi

# L4: THE VACUITY FLOOR. A page rewritten with different markup yields zero
# links, and "found nothing" must not read as "clean".
L4="$(newtmp)"; mk_fixture "$L4"
printf '<html><body><p>nothing to see</p></body></html>\n' > "$L4/workflow.html"
l4=$( cd "$L4" && MIN_WORKFLOW_LINKS=5 MIN_WORKFLOW_ANCHORS=1 bash "$ANCHORS" --docs-dir "$L4/docs" 2>&1 ); l4_rc=$?
if [ "$l4_rc" -eq 2 ] && printf '%s' "$l4" | grep -q 'below the floor'; then
  pass "L4: a page yielding no links or anchors exits 2 — CANNOT TELL, which is distinct from both clean (0) and broken (1). A silent 0 here would be the defect this arm was added to remove, one level up"
else
  fail_ "L4" "rc=$l4_rc (want 2) floor_message=$(printf '%s' "$l4" | grep -c 'below the floor')"
fi

echo "=== M — the marker arm (lint-bl-markers) ==="

M2="$(newtmp)"; mk_fixture "$M2"
sed -i.bak 's/BL-070-GATE-CHECK<\/code>/BL-070-GATE-CHECZ<\/code>/' "$M2/workflow.html" && rm -f "$M2/workflow.html.bak"
m2=$(run_markers "$M2"); m2_rc=$?
if [ "$m2_rc" -eq 1 ] && printf '%s' "$m2" | grep -q 'BL-070-GATE-CHECZ'; then
  pass "M2: a corrupted '#'-form marker citation fails and names the dead token — the exact mutation that returned rc 0 before this arm existed"
else
  fail_ "M2" "rc=$m2_rc (want 1) named=$(printf '%s' "$m2" | grep -c 'CHECZ') (want >=1)"
fi

M3="$(newtmp)"; mk_fixture "$M3"
sed -i.bak 's/BL-170-APPEND-DESIGN --&gt;/BL-170-APPEND-DESIGZ --\&gt;/' "$M3/workflow.html" && rm -f "$M3/workflow.html.bak"
m3=$(run_markers "$M3"); m3_rc=$?
if [ "$m3_rc" -eq 1 ] && printf '%s' "$m3" | grep -q 'BL-170-APPEND-DESIGZ'; then
  pass "M3: a corrupted '<!--'-form citation ALSO fails — the form a '#'-only reader silently skips, which would have left 12 of 13 checked and reported clean"
else
  fail_ "M3" "rc=$m3_rc (want 1) named=$(printf '%s' "$m3" | grep -c 'DESIGZ') (want >=1)"
fi

# ── M4 (MUTATION ON THE LINT ITSELF): delete the `<!--` alternative from a COPY
# and M3's corruption must survive undetected. This is what proves that
# alternative is load-bearing rather than decorative — without it, M3 would pass
# for the wrong reason and nobody could tell.
M4="$(newtmp)"; mk_fixture "$M4"
sed -i.bak 's/BL-170-APPEND-DESIGN --&gt;/BL-170-APPEND-DESIGZ --\&gt;/' "$M4/workflow.html" && rm -f "$M4/workflow.html.bak"
mkdir -p "$M4/lint"
cp "$MARKERS" "$M4/lint/lint-bl-markers.sh"
before=$(_num "$(grep -c '<!--\[\[:space:\]\]\*BL-' "$M4/lint/lint-bl-markers.sh")")
sed -i.bak 's/|<!--\[\[:space:\]\]\*BL-\[0-9\]+\[a-z\]?-\[A-Za-z\]\[A-Za-z0-9_\*-\]\*//' "$M4/lint/lint-bl-markers.sh" && rm -f "$M4/lint/lint-bl-markers.sh.bak"
after=$(_num "$(grep -c '<!--\[\[:space:\]\]\*BL-' "$M4/lint/lint-bl-markers.sh")")
m4_parses=0; bash -n "$M4/lint/lint-bl-markers.sh" >/dev/null 2>&1 && m4_parses=1
m4=$( cd "$M4" && bash "$M4/lint/lint-bl-markers.sh" --root "$M4" 2>&1 ); m4_rc=$?
if [ "$before" -ge 1 ] && [ "$after" -eq 0 ] && [ "$m4_parses" -eq 1 ] && [ "$m4_rc" -eq 0 ]; then
  pass "M4: with the '<!--' alternative deleted from a copy of the lint, M3's corrupted citation goes UNDETECTED (rc=0) — so that alternative is what catches it, not something else (sites $before -> $after, parses=$m4_parses)"
else
  fail_ "M4" "alternative sites before=$before (want >=1) after=$after (want 0) parses=$m4_parses (want 1) mutant rc=$m4_rc (want 0 — a non-zero means something ELSE caught it and M3 proves less than it claims)"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
