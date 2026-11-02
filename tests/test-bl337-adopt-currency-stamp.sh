#!/usr/bin/env bash
# tests/test-bl337-adopt-currency-stamp.sh — `## BL-337:` (issue #464): adoption
# stamps the Currency System's `currency` block, with the A1 and A2 render bases
# recorded as UNKNOWN, not empty (Karl, 2026-10-08).
#
# THE DEFECT. `soif_currency_stamp` had one caller, init.sh (`# BL-109-CURRENCY`),
# so an adopted project's `.claude/manifest.json` had no `currency` block and the
# session-start freshness check had nothing to check. The render bases come from
# a scratch file only init.sh's render step fills, so a naive call from adoption
# would have recorded EMPTY bases, which every reader skips as "nothing to say".
#
# CASES
#   A1  a real adoption stamps `currency`: schemaVersion 1, soloFrameworkPath is
#       the framework clone, per-file entries {sha256, mode, class, state} for
#       class M and T, each sha the file's on disk; committed in the adoption
#       commit
#   A2  the stamp lands AFTER the files it hashes: the reference docs, which
#       the framework documents stage writes after the manifest stage, are in
#       files{}
#   A3  renderBases.A1/.A2 carry a row for each artifact init.sh records a render
#       base for (derived from init.sh's soif_currency_record_render_base calls),
#       each marked `base: "unknown"` with `templateSha: null` and a reason —
#       not `{}`, not "" — and no A1 artifact gets a files{} row
#   A4  re-running adoption refuses and leaves the manifest byte-identical
#   A5  the adoption writer itself refuses to stamp a manifest that already has
#       a `currency` block (a birth stamp never becomes a backfill); with the
#       block removed, the same harness stamps (so A5's refusal is the guard's)
#   F1  the adoptee's own session-freshness-check.sh reports the unknown render
#       bases by name, says "adopted project", never claims an update is
#       available, and its machine block carries check `render-base-unknown`
#       with current:false
#   F2  the known-base arm never reads an unknown row as a base: an unknown row
#       carrying a stale templateSha raises no "older template" item, while a
#       known row with the same stale sha still does
#   F3  the freshness cache the check writes is ignored by the adoptee's git
#   F4  the unknown item can be snoozed like any informational item
#   P1  `--plan` on the adoptee names the unknown render bases in its notices,
#       stages no A1/A2 candidate, and does not say everything is current
#   G1  init.sh's stamp shape is unchanged: captured rows keep exactly
#       {templateSha, outputSha} / {templateSha}, A1 artifacts keep their files{}
#       rows, and no row carries `base`; init.sh's call passes no render-base mode
#
# Hermetic: temp dirs only, no network (SOIF_FRESHNESS_FETCH=0, no Guardrails
# clone, no MCP step). Reads init.sh as source (A3, G1) and never runs it.
# bash 3.2 safe.
set -uo pipefail
unset GITHUB_BASE_REF 2>/dev/null || true
export SOIF_ADOPT_MCP=off   # BL-311-MCP-SEAM
export SOIF_FRESHNESS_FETCH=0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

echo "== BL-337 — adoption stamps the currency block, render bases unknown =="
for t in jq git shasum; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bl337.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT INT TERM
gitq() { git -C "$1" "${@:2}" >/dev/null 2>&1; }
D=""

# ── fixtures ─────────────────────────────────────────────────────────────────
# The adoptee and answers of tests/test-bl322-s1-audit-loop.sh: a small node
# project; the tier, the track, four confirmations.
mk_adoptee() {
  local p="$1"
  mkdir -p "$p/src" || return 1
  gitq "$p" init -q . && gitq "$p" config user.email bl337@test.invalid && gitq "$p" config user.name "BL337 Test" \
    && gitq "$p" config core.excludesFile /dev/null || return 1
  printf '{"name":"acme-api","scripts":{"test":"npm test"}}\n' > "$p/package.json"
  printf '# acme-api\n' > "$p/README.md"
  printf 'node_modules/\n' > "$p/.gitignore"
  gitq "$p" add -A && gitq "$p" commit -q --no-verify -m "chore: their own history"
}
run_adopt() {   # DIR OUTFILE — sets RUN_RC
  RUN_RC=0
  ( cd "$1" && printf '1\nstandard\n1\n1\n1\n1\n' | env SOIF_ADOPT_SCANNER_BIN=sh SOIF_ADOPT_QDRANT=no \
      SOIF_ADOPT_GUARDRAILS_DIR="$WORK/no-guardrails" bash "$REPO_ROOT/scripts/adopt-project.sh" ) \
    > "$2" 2>&1 || RUN_RC=$?
}
freshness() {   # DIR [args...] — the adoptee's OWN copy of the check, as a session runs it
  ( cd "$1" && CLAUDE_PROJECT_DIR="$1" CDF_HOME="$WORK/no-cdf" bash "$1/scripts/session-freshness-check.sh" "${@:2}" ) 2>&1
}

P="$WORK/p"
mk_adoptee "$P" || { echo "fixture failed"; exit 1; }
run_adopt "$P" "$WORK/adopt.out"
ADOPT_RC=$RUN_RC
M="$P/.claude/manifest.json"

# init.sh's own render-base records, as "<group> <artifact>" lines — the set the
# unknown rows must cover. Read from source, never run.
INIT_RB="$(command grep -E '^[[:space:]]*soif_currency_record_render_base A[12] ' "$REPO_ROOT/init.sh" \
  | awk '{print $2" "$3}' | LC_ALL=C sort -u)"

echo
echo "=== A — the adoption stamps the block ==="
a1() {
  local label="A1 an adoption stamps currency: schemaVersion 1, soloFrameworkPath, per-file M/T entries hashed from disk, committed" bad="" n rel sha
  [ "$ADOPT_RC" -eq 0 ] || { fail_ "$label" "adoption rc $ADOPT_RC: $(command grep -E 'BLOCKED|REFUSED' "$WORK/adopt.out" | head -1)"; return; }
  n="$(jq -e '.currency | type == "object"' "$M" 2>&1)" || { fail_ "$label" "no currency block: $n (keys: $(jq -c keys "$M" 2>&1))"; return; }
  [ "$(jq -r '.currency.schemaVersion' "$M")" = "1" ] || bad="$bad [schemaVersion]"
  [ "$(jq -r '.currency.soloFrameworkPath' "$M")" = "$REPO_ROOT" ] || bad="$bad [soloFrameworkPath=$(jq -r '.currency.soloFrameworkPath' "$M")]"
  n="$(jq '[.currency.files[] | select(.class == "M")] | length' "$M")"; [ "${n:-0}" -gt 0 ] || bad="$bad [no class M rows]"
  n="$(jq '[.currency.files[] | select(.class == "T")] | length' "$M")"; [ "${n:-0}" -gt 0 ] || bad="$bad [no class T rows]"
  jq -e '[.currency.files[] | (keys == ["class","mode","sha256","state"]) and .state == "current" and (.sha256 | length == 64)] | all' "$M" >/dev/null 2>&1 \
    || bad="$bad [a files{} entry is not {sha256, mode, class, state:current}]"
  for rel in scripts/check-phase-gate.sh scripts/session-freshness-check.sh; do
    sha="$(shasum -a 256 "$P/$rel" | awk '{print $1}')"
    [ "$(jq -r --arg r "$rel" '.currency.files[$r].sha256 // ""' "$M")" = "$sha" ] || bad="$bad [$rel sha is not the file's]"
  done
  git -C "$P" show HEAD:.claude/manifest.json 2>/dev/null | jq -e '.currency.schemaVersion == 1' >/dev/null 2>&1 \
    || bad="$bad [the adoption commit does not carry the block]"
  [ -z "$(git -C "$P" status --porcelain -- .claude/manifest.json)" ] || bad="$bad [manifest differs from the commit]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
a2() {
  # The skills the session layer installs would pin the later bound, but
  # soif_parse_shipped_skills yields no skill path on this tree (it reads init.sh's
  # loop literally, `$(soif_vendored_skills)`), so neither birth hashes a skill
  # today; the reference docs pin the stamp past the framework documents stage.
  local label="A2 the stamp lands after the files it hashes: the reference docs (framework documents stage, after manifest) are in files{}" bad="" rel sha
  for rel in docs/reference/builders-guide.md docs/reference/messaging-standard.md; do
    [ -f "$P/$rel" ] || { bad="$bad [$rel was not installed — fixture]"; continue; }
    sha="$(shasum -a 256 "$P/$rel" | awk '{print $1}')"
    [ "$(jq -r --arg r "$rel" '.currency.files[$r].sha256 // ""' "$M" 2>/dev/null)" = "$sha" ] || bad="$bad [$rel not in files{} with its sha]"
  done
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
a3() {
  local label="A3 renderBases has a row for each of init.sh's render-base artifacts, each base:unknown, templateSha:null, reason recorded — not empty" bad="" got
  [ -n "$INIT_RB" ] || { fail_ "$label" "could not read init.sh's render-base records"; return; }
  got="$(jq -r '.currency.renderBases // {} | to_entries[] | .key as $g | .value | to_entries[] | "\($g) \(.key)"' "$M" 2>/dev/null | LC_ALL=C sort -u)"
  [ "$got" = "$INIT_RB" ] || bad="$bad [rows: $(printf '%s' "$got" | tr '\n' ',') want: $(printf '%s' "$INIT_RB" | tr '\n' ',')]"
  jq -e '[.currency.renderBases[][] | .base == "unknown" and .templateSha == null and .reason == "adopted"] | (length > 0 and all)' "$M" >/dev/null 2>&1 \
    || bad="$bad [a row is not {base:unknown, templateSha:null, reason:adopted}: $(jq -c '.currency.renderBases' "$M" 2>/dev/null)]"
  jq -e '[.currency.renderBases.A1[] | has("outputSha") and .outputSha == null] | all' "$M" >/dev/null 2>&1 || bad="$bad [an A1 row has no outputSha:null]"
  jq -e '[.currency.files | to_entries[] | select(.value.class == "A1")] | length == 0' "$M" >/dev/null 2>&1 \
    || bad="$bad [an A1 artifact has a files{} row, hashed after the fact]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
a4() {
  local label="A4 re-running adoption refuses and the manifest is byte-identical (no re-stamp)" before="$WORK/m.before"
  cp "$M" "$before"
  run_adopt "$P" "$WORK/adopt2.out"
  if [ "$RUN_RC" -ne 0 ] && cmp -s "$before" "$M"; then pass "$label"
  else fail_ "$label" "rc $RUN_RC, manifest changed: $(cmp "$before" "$M" 2>&1)"; fi
}
# The writer, called directly in a copy of the adopted project, with the
# driver's libs sourced (the driver itself would refuse at its preflight first).
writer() {   # DIR — prints the writer's output, returns its rc
  ( cd "$REPO_ROOT" || exit 9
    for l in helpers-core render-project-docs tldr-mode claude-settings adoption-stamp scaffold-shipped-set hook-templates \
             enforcement-level tdd-classify bypass-audit guardrails currency-manifest; do
      . "scripts/lib/$l.sh" || exit 9
    done
    for l in adopt-core adopt-evidence adopt-intake adopt-tools adopt-mcp adopt-secrets adopt-state adopt-record adopt-docs \
             adopt-ci adopt-session adopt-guardrails adopt-act4 adopt-archive adopt-stubs adopt-test-debt; do
      . "scripts/lib/adopt/$l.sh" || exit 9
    done
    command -v adopt_write_currency >/dev/null 2>&1 || { echo "NO-WRITER"; exit 8; }
    ADOPT_FRAMEWORK_ROOT="$REPO_ROOT"; ADOPT_WRITTEN_LEDGER=""; ADOPT_GUARD_REAL_ROOT=""
    adopt_write_currency "$1" "$P/.claude/adoption/scout-report.json" ) 2>&1
}
a5() {
  local label="A5 the adoption writer refuses a manifest that already has a currency block, and stamps one without it" c="$WORK/a5" out rc=0 before
  cp -R "$P" "$c" || { fail_ "$label" "copy failed"; return; }
  before="$(cat "$c/.claude/manifest.json")"
  out="$(writer "$c")" || rc=$?
  if [ "$rc" -eq 0 ] || [ "$before" != "$(cat "$c/.claude/manifest.json")" ] || ! printf '%s' "$out" | command grep -q 'backfill'; then
    fail_ "$label" "on a stamped manifest: rc $rc, changed=$([ "$before" = "$(cat "$c/.claude/manifest.json")" ] && echo no || echo yes), out: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"; return
  fi
  jq 'del(.currency)' "$c/.claude/manifest.json" > "$c/m.tmp" && mv "$c/m.tmp" "$c/.claude/manifest.json"
  rc=0; out="$(writer "$c")" || rc=$?
  if [ "$rc" -eq 0 ] && jq -e '.currency.renderBases.A1["CLAUDE.md"].base == "unknown"' "$c/.claude/manifest.json" >/dev/null 2>&1; then pass "$label"
  else fail_ "$label" "positive control: rc $rc, out: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"; fi
}
a1; a2; a3; a4; a5

echo
echo "=== F — the freshness check reports unknown honestly ==="
FOUT="$(freshness "$P")"
f1() {
  local label="F1 the adoptee's freshness check names the unknown render bases, says adopted project, claims no update, machine block current:false" bad="" blk a
  printf '%s' "$FOUT" | command grep -q 'freshness check unavailable' && bad="$bad [the check crashed]"
  printf '%s' "$FOUT" | command grep -q 'render base unknown' || bad="$bad [no 'render base unknown' line]"
  printf '%s' "$FOUT" | command grep -q 'adopted project' || bad="$bad [does not say adopted project]"
  for a in $(printf '%s\n' "$INIT_RB" | awk '{print $2}'); do
    printf '%s' "$FOUT" | command grep 'render base unknown' | command grep -qF "$a" || bad="$bad [does not name $a]"
  done
  printf '%s' "$FOUT" | command grep -q 'older template' && bad="$bad [an unknown base was compared as a known one]"
  blk="$(printf '%s\n' "$FOUT" | awk '/^```soif-freshness$/{f=1;next} /^```$/{f=0} f')"
  if printf '%s' "$blk" | jq -e '[.items[] | .check == "render-base-unknown"] | all' >/dev/null 2>&1; then
    printf '%s' "$FOUT" | command grep -q 'updates available' && bad="$bad [header claims updates are available when the only item is the unknown one]"
  fi
  printf '%s' "$blk" | jq -e '.current == false and ([.items[] | select(.check == "render-base-unknown")] | length == 1)' >/dev/null 2>&1 \
    || bad="$bad [machine block: $(printf '%s' "$blk" | jq -c '{current, items: [.items[] | {id, check}]}' 2>/dev/null)]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad — output: $(printf '%s' "$FOUT" | head -6 | tr '\n' '|')"
}
f2() {
  local label="F2 an unknown row is never read as a base, even carrying a stale templateSha; a known stale row still reports" c="$WORK/f2" out stale
  cp -R "$P" "$c" || { fail_ "$label" "copy failed"; return; }
  stale="0000000000000000000000000000000000000000000000000000000000000000"
  jq --arg s "$stale" '.currency.renderBases.A1["CLAUDE.md"].templateSha = $s' "$c/.claude/manifest.json" > "$c/m.tmp" && mv "$c/m.tmp" "$c/.claude/manifest.json"
  out="$(freshness "$c")"
  if printf '%s' "$out" | command grep -q 'CLAUDE.md was rendered from an older template'; then
    fail_ "$label" "the unknown row's templateSha was compared"; return
  fi
  jq --arg s "$stale" '.currency.renderBases.A1["CLAUDE.md"] = {templateSha: $s, outputSha: $s}' "$c/.claude/manifest.json" > "$c/m.tmp" && mv "$c/m.tmp" "$c/.claude/manifest.json"
  out="$(freshness "$c")"
  if printf '%s' "$out" | command grep -q 'CLAUDE.md was rendered from an older template'; then pass "$label"
  else fail_ "$label" "control: a known stale CLAUDE.md row did not report: $(printf '%s' "$out" | head -4 | tr '\n' '|')"; fi
}
f3() {
  local label="F3 the freshness cache is written and ignored by the adoptee's git"
  if [ -f "$P/.claude/cache/freshness.json" ] && [ -z "$(git -C "$P" status --porcelain --untracked-files=all -- .claude/cache)" ]; then pass "$label"
  else fail_ "$label" "cache present=$([ -f "$P/.claude/cache/freshness.json" ] && echo yes || echo no); status: $(git -C "$P" status --porcelain --untracked-files=all -- .claude/cache | tr '\n' ' ')"; fi
}
f4() {
  local label="F4 the unknown item snoozes like an informational item" c="$WORK/f4" out
  printf '%s' "$FOUT" | command grep -q 'render base unknown' || { fail_ "$label" "nothing to snooze: the check reported no unknown render base"; return; }
  cp -R "$P" "$c" || { fail_ "$label" "copy failed"; return; }
  freshness "$c" --snooze render-base-unknown >/dev/null
  out="$(freshness "$c")"
  if printf '%s' "$out" | command grep -q 'render base unknown'; then fail_ "$label" "still reported after --snooze: $(printf '%s' "$out" | head -3 | tr '\n' '|')"
  else pass "$label"; fi
}
f1; f2; f3; f4

echo
echo "=== P — the plan names it and stages nothing from it ==="
p1() {
  local label="P1 --plan's notices name the unknown render bases, no A1/A2 candidate is staged, and it does not say everything is current" c="$WORK/p1" run bad="" plan
  cp -R "$P" "$c" || { fail_ "$label" "copy failed"; return; }
  run="$( ( for l in hook-templates scaffold-shipped-set currency-manifest freshness-detect render-project-docs plan-staging; do
              . "$REPO_ROOT/scripts/lib/$l.sh"; done
            set +e; soif_plan_run "$c" "$REPO_ROOT" "$REPO_ROOT/init.sh" "$WORK/no-cdf" ) 2>/dev/null | tail -1)"
  plan="$run/UPDATE-PLAN.md"
  [ -f "$plan" ] || { fail_ "$label" "no UPDATE-PLAN.md (run=$run)"; return; }
  command grep -q '(render-base-unknown).*render base unknown' "$plan" || bad="$bad [no render-base-unknown notice]"
  command grep -q 'Everything tracked is current' "$plan" && bad="$bad [says everything tracked is current]"
  [ -z "$(ls "$run/merged" 2>/dev/null)" ] || bad="$bad [a candidate was staged: $(ls "$run/merged" | tr '\n' ' ')]"
  command grep -qE 'A[12][[:space:]]*\|' "$plan" && bad="$bad [an A1/A2 item is in the plan]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
p1

echo
echo "=== G — init.sh's stamp is unchanged ==="
g1() {
  local label="G1 a captured stamp keeps {templateSha, outputSha} / {templateSha} rows and A1 files{} rows, carries no base key; init.sh passes no mode" g="$WORK/g1" bad=""
  mkdir -p "$g/proj/scripts" "$g/proj/.claude" || { fail_ "$label" "mkdir"; return; }
  cp "$REPO_ROOT/scripts/check-phase-gate.sh" "$g/proj/scripts/"
  printf '# rendered\n' > "$g/proj/CLAUDE.md"
  printf '{"host":"github"}\n' > "$g/proj/.claude/manifest.json"
  ( . "$REPO_ROOT/scripts/lib/currency-manifest.sh"
    soif_currency_renderbase_init
    soif_currency_record_render_base A1 CLAUDE.md "$REPO_ROOT/templates/generated/claude-md.tmpl" "$g/proj/CLAUDE.md"
    soif_currency_record_render_base A2 PROJECT_BIBLE.md "$REPO_ROOT/templates/generated/project-bible.tmpl" ""
    soif_currency_stamp "$g/proj/.claude/manifest.json" "$REPO_ROOT/init.sh" "$REPO_ROOT" "$g/proj" node "$REPO_ROOT"
    rm -f "$SOIF_CURRENCY_RENDERBASE_FILE" ) >/dev/null 2>&1
  local m="$g/proj/.claude/manifest.json"
  jq -e '.currency | keys == ["files","hooks","mcpProbe","renderBases","schemaVersion","soloFrameworkPath"]' "$m" >/dev/null 2>&1 || bad="$bad [block keys: $(jq -c '.currency | keys' "$m" 2>/dev/null)]"
  jq -e '.currency.renderBases.A1["CLAUDE.md"] | keys == ["outputSha","templateSha"] and (.templateSha | length == 64)' "$m" >/dev/null 2>&1 || bad="$bad [A1 row: $(jq -c '.currency.renderBases.A1' "$m" 2>/dev/null)]"
  jq -e '.currency.renderBases.A2["PROJECT_BIBLE.md"] | keys == ["templateSha"]' "$m" >/dev/null 2>&1 || bad="$bad [A2 row: $(jq -c '.currency.renderBases.A2' "$m" 2>/dev/null)]"
  jq -e '.currency.files["CLAUDE.md"].class == "A1"' "$m" >/dev/null 2>&1 || bad="$bad [no A1 files{} row]"
  jq -e '.host == "github"' "$m" >/dev/null 2>&1 || bad="$bad [the merge lost an existing key]"
  command grep -qF 'soif_currency_stamp "$manifest" "$SCRIPT_DIR/init.sh" "$SCRIPT_DIR" "." "$LANGUAGE" "$SCRIPT_DIR"   # BL-109-CURRENCY' "$REPO_ROOT/init.sh" \
    || bad="$bad [init.sh's stamp call changed]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
g1

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
