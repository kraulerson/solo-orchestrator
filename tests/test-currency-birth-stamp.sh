#!/usr/bin/env bash
# tests/test-currency-birth-stamp.sh — BL-109 S1 AGGREGATOR fidelity test.
#
# The BL-088 precedent: fixtures hide scaffold gaps, so this test runs the REAL
# init.sh into a hermetic scratch project and proves the `currency` block is
# stamped at birth with shas that recompute end-to-end. It exercises init.sh's
# OWN copy/render/hook mechanism — the only way to catch a shipped-set or
# render-site drift that a hand-built fixture would paper over.
#
# It runs init.sh THREE times (typescript / rust / other) to cover the hook
# three-state enum (present / absent-intentional / absent-unavailable) against
# init.sh's real language→hook install decision. That is why it is an AGGREGATOR:
# it is registered ONLY in tests/full-project-test-suite.sh (SUITE_SKIP_AGGREGATORS
# -gated), NEVER in the tests.yml unit list — it executes init.sh.
#
# Hermetic: mktemp, GITHUB_BASE_REF unset, init.sh run with --no-remote-creation
# (the blessed no-live-remote path). bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT="$REPO_ROOT/init.sh"

unset GITHUB_BASE_REF 2>/dev/null || true

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

# Dependency guard — init.sh needs jq + git.
if ! command -v jq >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  echo "SKIP: jq/git required for the init.sh-driven currency birth-stamp test"
  echo "Results: 0 passed, 0 failed"
  exit 0
fi

# run_init <language> <project-name> <out-scaffold-dir>
run_init() {
  local lang="$1" name="$2" out="$3" errf="$TOPTMP/$2.err"
  ( cd "$TOPTMP" && "$INIT" --non-interactive \
      --project "$name" \
      --platform web \
      --deployment personal \
      --gov-mode private_poc \
      --language "$lang" \
      --project-dir "$out" \
      --no-remote-creation ) >"$TOPTMP/$name.out" 2>"$errf"
}

# ════════════════════════════════════════════════════════════════════════════
# Scaffold 1 — typescript: the FULL fidelity pass (shas, render bases, path,
# present hook enum).
# ════════════════════════════════════════════════════════════════════════════
echo "=== Scaffolding typescript project via real init.sh (hermetic) ==="
TS="$TOPTMP/ts"
if ! run_init typescript curbl109ts "$TS"; then
  fail_ "ts-scaffold-init" "init.sh exited non-zero; stderr tail: $(tail -6 "$TOPTMP/curbl109ts.err" | tr '\n' '|')"
  echo "Results: $PASSED passed, $FAILED failed"
  exit 1
fi
MAN="$TS/.claude/manifest.json"

# — currency block present —
if jq -e '.currency' "$MAN" >/dev/null 2>&1; then
  pass "currency block present in .claude/manifest.json"
else
  fail_ "currency block present" "no .currency key in the birth manifest"
  echo "Results: $PASSED passed, $FAILED failed"
  exit 1
fi

# — exactly the six schema keys —
keys="$(jq -r '.currency | keys | join(" ")' "$MAN")"
if [ "$keys" = "files hooks mcpProbe renderBases schemaVersion soloFrameworkPath" ]; then
  pass "currency has exactly the six schema keys"
else
  fail_ "currency schema keys" "got [$keys]"
fi

# — schemaVersion == 1 —
[ "$(jq -r '.currency.schemaVersion' "$MAN")" = "1" ] \
  && pass "schemaVersion == 1" || fail_ "schemaVersion" "not 1"

# — every files{} sha256 recomputes against the scaffolded tree —
jq -r '.currency.files | keys[]' "$MAN" > "$TOPTMP/ts.keys"
sha_bad=0; sha_tot=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  sha_tot=$((sha_tot + 1))
  if [ ! -f "$TS/$rel" ]; then
    sha_bad=$((sha_bad + 1)); echo "    missing on disk: $rel"; continue
  fi
  exp="$(shasum -a 256 "$TS/$rel" | awk '{print $1}')"
  got="$(jq -r --arg p "$rel" '.currency.files[$p].sha256' "$MAN")"
  [ "$exp" = "$got" ] || { sha_bad=$((sha_bad + 1)); echo "    sha mismatch: $rel"; }
done < "$TOPTMP/ts.keys"
if [ "$sha_bad" -eq 0 ] && [ "$sha_tot" -gt 0 ]; then
  pass "every files{} sha256 recomputes independently ($sha_tot files)"
else
  fail_ "files{} sha recompute" "$sha_bad of $sha_tot mismatched/missing"
fi

# — every files{} entry has mode + state:"current" —
non_current="$(jq -r '[.currency.files[] | select(.state != "current")] | length' "$MAN")"
[ "$non_current" = "0" ] && pass "every files{} entry state == current" \
  || fail_ "files{} state" "$non_current entries not current"
no_mode="$(jq -r '[.currency.files[] | select(.mode == null or .mode == "")] | length' "$MAN")"
[ "$no_mode" = "0" ] && pass "every files{} entry has a mode" \
  || fail_ "files{} mode" "$no_mode entries lack a mode"

# — class breakdown: T == 7 (docs/reference verbatim set); A1 == 2; M > 0 —
t_count="$(jq -r '[.currency.files[] | select(.class == "T")] | length' "$MAN")"
a1_count="$(jq -r '[.currency.files[] | select(.class == "A1")] | length' "$MAN")"
m_count="$(jq -r '[.currency.files[] | select(.class == "M")] | length' "$MAN")"
[ "$t_count" = "7" ] && pass "Class T == 7 (docs/reference verbatim set)" \
  || fail_ "Class T count" "expected 7, got $t_count"
[ "$a1_count" = "2" ] && pass "Class A1 == 2 (CLAUDE.md + PROJECT_INTAKE.md)" \
  || fail_ "Class A1 count" "expected 2, got $a1_count"
[ "$m_count" -gt 0 ] && pass "Class M > 0 (scripts + skills): $m_count" \
  || fail_ "Class M count" "expected > 0, got $m_count"

# — A2 agent-authored artifacts NOT in files{} (do not exist at birth) —
if [ "$(jq -r '.currency.files["PRODUCT_MANIFESTO.md"] // "null"' "$MAN")" = "null" ] \
   && [ "$(jq -r '.currency.files["PROJECT_BIBLE.md"] // "null"' "$MAN")" = "null" ]; then
  pass "A2 artifacts (manifesto/bible) are NOT in files{}"
else
  fail_ "A2 in files{}" "an A2 artifact leaked into files{}"
fi

# — render bases recompute (A1 template+output; A2 template-only) —
rb_ok=1
# A1 CLAUDE.md
exp="$(shasum -a 256 "$REPO_ROOT/templates/generated/claude-md.tmpl" | awk '{print $1}')"
[ "$(jq -r '.currency.renderBases.A1["CLAUDE.md"].templateSha' "$MAN")" = "$exp" ] || { rb_ok=0; echo "    A1 CLAUDE tmpl sha diff"; }
exp="$(shasum -a 256 "$TS/CLAUDE.md" | awk '{print $1}')"
[ "$(jq -r '.currency.renderBases.A1["CLAUDE.md"].outputSha' "$MAN")" = "$exp" ] || { rb_ok=0; echo "    A1 CLAUDE out sha diff"; }
# A1 PROJECT_INTAKE.md
exp="$(shasum -a 256 "$REPO_ROOT/templates/project-intake.md" | awk '{print $1}')"
[ "$(jq -r '.currency.renderBases.A1["PROJECT_INTAKE.md"].templateSha' "$MAN")" = "$exp" ] || { rb_ok=0; echo "    A1 INTAKE tmpl sha diff"; }
exp="$(shasum -a 256 "$TS/PROJECT_INTAKE.md" | awk '{print $1}')"
[ "$(jq -r '.currency.renderBases.A1["PROJECT_INTAKE.md"].outputSha' "$MAN")" = "$exp" ] || { rb_ok=0; echo "    A1 INTAKE out sha diff"; }
# A2 templates
exp="$(shasum -a 256 "$REPO_ROOT/templates/generated/project-bible.tmpl" | awk '{print $1}')"
[ "$(jq -r '.currency.renderBases.A2["PROJECT_BIBLE.md"].templateSha' "$MAN")" = "$exp" ] || { rb_ok=0; echo "    A2 bible tmpl sha diff"; }
exp="$(shasum -a 256 "$REPO_ROOT/templates/generated/product-manifesto.tmpl" | awk '{print $1}')"
[ "$(jq -r '.currency.renderBases.A2["PRODUCT_MANIFESTO.md"].templateSha' "$MAN")" = "$exp" ] || { rb_ok=0; echo "    A2 manifesto tmpl sha diff"; }
# A2 records template ONLY — no outputSha
[ "$(jq -r '.currency.renderBases.A2["PROJECT_BIBLE.md"].outputSha // "null"' "$MAN")" = "null" ] || { rb_ok=0; echo "    A2 bible has outputSha (should not)"; }
# A1 files{} sha reuses the captured render-time output sha (single hash, no post-hoc)
[ "$(jq -r '.currency.files["CLAUDE.md"].sha256' "$MAN")" = "$(jq -r '.currency.renderBases.A1["CLAUDE.md"].outputSha' "$MAN")" ] || { rb_ok=0; echo "    A1 files sha != render outputSha"; }
if [ "$rb_ok" -eq 1 ]; then pass "render bases recompute (A1 tmpl+out, A2 tmpl-only)"; else fail_ "render bases" "see diffs above"; fi

# — soloFrameworkPath == the framework checkout used —
got_path="$(jq -r '.currency.soloFrameworkPath' "$MAN")"
[ "$got_path" = "$REPO_ROOT" ] && pass "soloFrameworkPath == framework checkout ($REPO_ROOT)" \
  || fail_ "soloFrameworkPath" "expected [$REPO_ROOT], got [$got_path]"

# — mcpProbe is a valid present/absent enum —
mcp="$(jq -r '.currency.mcpProbe.context7' "$MAN")"
{ [ "$mcp" = "present" ] || [ "$mcp" = "absent" ]; } \
  && pass "mcpProbe.context7 is a valid enum ($mcp)" \
  || fail_ "mcpProbe" "got [$mcp]"

# — pre-existing pins/fields preserved (additive stamp) —
[ "$(jq -r '.frameworkCommit // "MISSING"' "$MAN")" != "MISSING" ] \
  && pass "additive: CDF frameworkCommit pin preserved" \
  || fail_ "additive pin" "frameworkCommit lost"

# — typescript hooks: commit-msg + pre-commit present —
[ "$(jq -r '.currency.hooks["commit-msg"]' "$MAN")" = "present" ] \
  && pass "typescript -> commit-msg hook present" \
  || fail_ "ts commit-msg" "not present"
[ "$(jq -r '.currency.hooks["pre-commit"]' "$MAN")" = "present" ] \
  && pass "pre-commit hook present" \
  || fail_ "pre-commit" "not present"

# ════════════════════════════════════════════════════════════════════════════
# Scaffold 2 — rust: commit-msg hook is absent-intentional (inline tests).
# ════════════════════════════════════════════════════════════════════════════
echo "=== Scaffolding rust project via real init.sh (hermetic) ==="
RS="$TOPTMP/rs"
if run_init rust curbl109rs "$RS"; then
  st="$(jq -r '.currency.hooks["commit-msg"]' "$RS/.claude/manifest.json")"
  [ "$st" = "absent-intentional" ] \
    && pass "rust -> commit-msg absent-intentional" \
    || fail_ "rust commit-msg" "expected absent-intentional, got [$st]"
else
  fail_ "rust-scaffold-init" "init.sh exited non-zero; stderr tail: $(tail -6 "$TOPTMP/curbl109rs.err" | tr '\n' '|')"
fi

# ════════════════════════════════════════════════════════════════════════════
# Scaffold 3 — other: commit-msg hook is absent-unavailable (the *) catch-all,
# surfaced at the enforcement tier — must NOT launder a bug into a fact.
# ════════════════════════════════════════════════════════════════════════════
echo "=== Scaffolding 'other'-language project via real init.sh (hermetic) ==="
OT="$TOPTMP/ot"
if run_init other curbl109ot "$OT"; then
  st="$(jq -r '.currency.hooks["commit-msg"]' "$OT/.claude/manifest.json")"
  [ "$st" = "absent-unavailable" ] \
    && pass "other -> commit-msg absent-unavailable" \
    || fail_ "other commit-msg" "expected absent-unavailable, got [$st]"
else
  fail_ "other-scaffold-init" "init.sh exited non-zero; stderr tail: $(tail -6 "$TOPTMP/curbl109ot.err" | tr '\n' '|')"
fi

# ── Tally ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
