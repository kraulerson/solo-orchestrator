#!/usr/bin/env bash
# tests/test-bl131-domsink-rules.sh — BL-131: the commit-time SAST gate must SEE
# the DOM-XSS sink classes NO public registry rule covers.
#
# WHY THIS EXISTS (BL-118 adversarial verification, PR #199)
#   Proven through the real emitted hook: `el.insertAdjacentHTML('beforeend', x)`,
#   jQuery `$(sel).html(x)`, `innerHTML` inside a `.vue` SFC <script>, and an inline
#   <script> with innerHTML/document.write in a committed `.html` all COMMIT CLEAN
#   with the `[OK] semgrep: SAST ran` receipt — p/owasp-top-ten and the browser pack
#   flag NONE of them at any severity. The fix ships a project-owned ruleset
#   (.semgrep/soif-dom-sinks.yml) referenced by an extra --config in the emitted
#   hook (# BL-131-DOM-SINKS) and every generated CI pipeline. js/ts innerHTML/
#   document.write are LEFT to the registry browser pack (BL-118) — this ruleset
#   covers only the residual gaps, so the two do not overlap.
#
# CASES
#   Static pins (hermetic, always run):
#     T-ruleset-ships           the ruleset file exists, is valid, carries its 3 rules
#     T-initsh-ships-ruleset     init.sh has the cp line that lays it into .semgrep/
#     T-hook-references-ruleset   the emitted hook's semgrep invocation --config's it
#     T-ci-references-ruleset     every github+gitlab CI pipeline --config's it
#   Rule-content (semgrep only, NO network — the ruleset scanned in isolation):
#     T-rule-<sink>              each of the four sinks -> a finding; benign -> none
#   Live + wiring (semgrep + registry; LOUD SKIP if the registry is unreachable):
#     T-live-<sink>              each sink committed through the emitted hook -> REFUSED
#     T-live-benign              the benign control commits clean
#     T-artifact-missing-is-loud DELETE the shipped ruleset -> the hook goes LOUD
#                                (SAST NOT ENFORCED), never a silent clean pass
#     T-mutation-ruleset-config  strip the --config line from the hook -> the four
#                                sinks LAND (RED) -> restore -> GREEN
#
# REGISTRATION: never runs init.sh, not an aggregator -> registered in BOTH
# tests/full-project-test-suite.sh AND the tests.yml unit fast lane (the live cases
# skip loudly there when the registry is unreachable; the static + rule-content pins
# still run and still bite). Hermetic: mktemp, local git identity, GITHUB_BASE_REF
# unset, no remote. bash-3.2 safe.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

unset GITHUB_BASE_REF 2>/dev/null || true

PASSED=0
FAILED=0
SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip_() { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT

HOOK_SRC="$REPO_ROOT/scripts/lib/hook-templates.sh"
RULESET_SRC="$REPO_ROOT/templates/semgrep/soif-dom-sinks.yml"
INIT_SH="$REPO_ROOT/init.sh"
EMITTED="$TOPTMP/emitted-hook"
RULESET_REF='.semgrep/soif-dom-sinks.yml'

if [ ! -f "$HOOK_SRC" ]; then
  echo "SKIP: scripts/lib/hook-templates.sh missing"; echo "Results: 0 passed, 0 failed"; exit 0
fi
# shellcheck source=/dev/null
. "$HOOK_SRC"
soif_write_precommit_hook "$EMITTED"

# Comment-stripped fixed-string grep: a config that survives only in a comment is
# not a config.
has_live() { grep -v '^[[:space:]]*#' "$1" | grep -qF -- "$2"; }

# ── Fixture files (one per sink + benign control) ────────────────────────────
FX="$TOPTMP/fx"; mkdir -p "$FX"
printf 'export function render(el, u) {\n  el.insertAdjacentHTML("beforeend", u);\n}\n' > "$FX/sink_ia.ts"
printf 'function render(sel, u) {\n  $(sel).html(u);\n}\n' > "$FX/sink_jq.js"
printf '<template><div id="p"></div></template>\n<script>\nexport default {\n  mounted() { this.$el.querySelector("#p").innerHTML = location.hash; }\n}\n</script>\n' > "$FX/sink_vue.vue"
printf '<!doctype html>\n<html><body><div id="o"></div>\n<script>\n  document.getElementById("o").innerHTML = location.hash;\n  document.write(location.hash);\n</script>\n</body></html>\n' > "$FX/sink_html.html"
printf 'export function render(el, u) {\n  el.textContent = u;\n  el.insertAdjacentText("beforeend", u);\n}\n' > "$FX/benign.ts"

# parallel arrays: fixture -> committed name -> label
N_SINKS=4
S_FILE_0="$FX/sink_ia.ts";   S_DEST_0="app.ts";    S_LABEL_0="insertAdjacentHTML"
S_FILE_1="$FX/sink_jq.js";   S_DEST_1="legacy.js"; S_LABEL_1="jquery-html"
S_FILE_2="$FX/sink_vue.vue"; S_DEST_2="comp.vue";  S_LABEL_2="vue-innerHTML"
S_FILE_3="$FX/sink_html.html"; S_DEST_3="index.html"; S_LABEL_3="html-inline-script"

sfile() { eval "printf '%s' \"\$S_FILE_$1\""; }
sdest() { eval "printf '%s' \"\$S_DEST_$1\""; }
slabel() { eval "printf '%s' \"\$S_LABEL_$1\""; }

# ═══════════════════════════════════════════════════════════════════════════════
# STATIC PINS (hermetic)
# ═══════════════════════════════════════════════════════════════════════════════
echo "=== T-ruleset-ships ==="
if [ ! -f "$RULESET_SRC" ]; then
  fail_ "T-ruleset-ships" "templates/semgrep/soif-dom-sinks.yml is missing — the shipped artifact does not exist"
elif ! grep -q 'id: soif-insert-adjacent-html' "$RULESET_SRC" \
     || ! grep -q 'id: soif-jquery-html-sink' "$RULESET_SRC" \
     || ! grep -q 'id: soif-dom-sink-markup' "$RULESET_SRC"; then
  fail_ "T-ruleset-ships" "ruleset is missing one of its three pinned rule ids (insert-adjacent-html / jquery-html-sink / dom-sink-markup)"
else
  pass "T-ruleset-ships: the ruleset file exists and carries its three rule ids"
fi

echo "=== T-initsh-ships-ruleset ==="
if [ ! -f "$INIT_SH" ]; then
  fail_ "T-initsh-ships-ruleset" "init.sh not found"
elif ! grep -qF 'cp "$SCRIPT_DIR/templates/semgrep/soif-dom-sinks.yml" .semgrep/' "$INIT_SH"; then
  fail_ "T-initsh-ships-ruleset" "init.sh has no cp line shipping templates/semgrep/soif-dom-sinks.yml into .semgrep/ — a scaffold would reference a file it never received"
else
  pass "T-initsh-ships-ruleset: init.sh lays the ruleset into the scaffold's .semgrep/"
fi

echo "=== T-hook-references-ruleset ==="
if ! has_live "$EMITTED" "--config=$RULESET_REF"; then
  fail_ "T-hook-references-ruleset" "the emitted hook's semgrep invocation does not --config the shipped ruleset (BL-131 wiring absent)"
elif ! has_live "$EMITTED" "p/owasp-top-ten" || ! has_live "$EMITTED" "insecure-document-method"; then
  fail_ "T-hook-references-ruleset" "the fix dropped the registry configs — it must ADD coverage, not trade BL-112/BL-118's away"
else
  pass "T-hook-references-ruleset: the emitted hook --config's the ruleset alongside the registry packs"
fi

echo "=== T-ci-references-ruleset ==="
ci_missing=""
ci_count=0
for tpl in "$REPO_ROOT"/templates/pipelines/ci/github/*.yml "$REPO_ROOT"/templates/pipelines/ci/gitlab/*.yml; do
  [ -f "$tpl" ] || continue
  ci_count=$((ci_count + 1))
  has_live "$tpl" "--config=$RULESET_REF" || ci_missing="$ci_missing ${tpl#"$REPO_ROOT"/}"
done
if [ "$ci_count" -eq 0 ]; then
  fail_ "T-ci-references-ruleset" "no CI templates found under templates/pipelines/ci/"
elif [ -n "$ci_missing" ]; then
  fail_ "T-ci-references-ruleset" "$(echo "$ci_missing" | wc -w | tr -d ' ') of $ci_count CI templates lack --config=$RULESET_REF:$ci_missing"
else
  pass "T-ci-references-ruleset ($ci_count github+gitlab pipelines)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# The semgrep predicate, stated LOUDLY
# ═══════════════════════════════════════════════════════════════════════════════
HAVE_SEMGREP=0
if command -v semgrep >/dev/null 2>&1; then
  HAVE_SEMGREP=1
else
  echo ""
  echo "#################################################################"
  echo "## semgrep IS NOT INSTALLED ON THIS HOST.                      ##"
  echo "## The rule-content + live cases are SKIPPED, NOT PASSED.      ##"
  echo "## The static pins above still bind the artifacts.             ##"
  echo "## Install semgrep to exercise them: brew install semgrep      ##"
  echo "#################################################################"
  echo ""
fi

# ═══════════════════════════════════════════════════════════════════════════════
# RULE-CONTENT (semgrep only, NO network — the ruleset scanned in isolation)
# ═══════════════════════════════════════════════════════════════════════════════
# scan_one <config> <file> -> semgrep rc (1 == blocking finding, 0 == clean)
scan_one() {
  semgrep scan --config="$1" --severity=ERROR --error --no-git-ignore "$2" >/dev/null 2>&1
  echo $?
}
if [ "$HAVE_SEMGREP" -eq 1 ] && [ -f "$RULESET_SRC" ]; then
  # validity
  if semgrep --validate --config="$RULESET_SRC" >/dev/null 2>&1; then
    pass "T-rule-validates: the shipped ruleset is a valid semgrep config"
  else
    fail_ "T-rule-validates" "semgrep --validate rejected the shipped ruleset"
  fi
  i=0
  while [ "$i" -lt "$N_SINKS" ]; do
    lbl="$(slabel "$i")"; f="$(sfile "$i")"
    echo "=== T-rule-$lbl ==="
    rc="$(scan_one "$RULESET_SRC" "$f")"
    if [ "$rc" -eq 1 ]; then
      pass "T-rule-$lbl: the ruleset flags the sink in isolation (no registry needed)"
    else
      fail_ "T-rule-$lbl" "the ruleset did NOT flag the $lbl sink (semgrep rc=$rc, want 1)"
    fi
    i=$((i + 1))
  done
  echo "=== T-rule-benign ==="
  rcb="$(scan_one "$RULESET_SRC" "$FX/benign.ts")"
  if [ "$rcb" -eq 0 ]; then
    pass "T-rule-benign: textContent / insertAdjacentText are NOT flagged (no over-block)"
  else
    fail_ "T-rule-benign" "the benign control was flagged (semgrep rc=$rcb, want 0) — over-blocking"
  fi
else
  skip_ "T-rule-content" "semgrep absent or ruleset missing"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# LIVE + WIRING (semgrep + registry; LOUD SKIP if unreachable)
# ═══════════════════════════════════════════════════════════════════════════════
# mk_repo <dir> <hook> <ship_ruleset:1|0>
mk_repo() {
  local d="$1" hook="$2" ship="$3"
  mkdir -p "$d"
  ( cd "$d" && git init -q && git config user.email bl131@test.invalid && git config user.name "BL-131 Test" \
      && echo "# bl131" > README.md && git add README.md && git commit -q -m "chore: init" ) || return 1
  if [ "$ship" = "1" ] && [ -f "$RULESET_SRC" ]; then
    mkdir -p "$d/.semgrep"; cp "$RULESET_SRC" "$d/.semgrep/soif-dom-sinks.yml"
  fi
  cp "$hook" "$d/.git/hooks/pre-commit"; chmod +x "$d/.git/hooks/pre-commit"
}
head_of() { ( cd "$1" && git rev-parse HEAD 2>/dev/null ) || echo none; }
not_enforced() { grep -q "SAST NOT ENFORCED" "$1"; }
# commit_fixture <repo> <fixture> <destname> <log> -> COMMITTED|REFUSED
commit_fixture() {
  local d="$1" fx="$2" dest="$3" log="$4"
  cp "$fx" "$d/$dest"
  if ( cd "$d" && git add "$dest" && git commit -m "feat: $dest" ) >"$log" 2>&1; then echo COMMITTED; else echo REFUSED; fi
}

if [ "$HAVE_SEMGREP" -eq 1 ]; then
  i=0
  while [ "$i" -lt "$N_SINKS" ]; do
    lbl="$(slabel "$i")"; f="$(sfile "$i")"; dst="$(sdest "$i")"
    echo "=== T-live-$lbl ==="
    R="$TOPTMP/live-$i"
    if ! mk_repo "$R" "$EMITTED" 1; then
      fail_ "T-live-$lbl" "repo setup failed"
    else
      H0="$(head_of "$R")"
      V="$(commit_fixture "$R" "$f" "$dst" "$TOPTMP/live-$i.log")"
      H1="$(head_of "$R")"
      if [ "$V" = "COMMITTED" ]; then
        if not_enforced "$TOPTMP/live-$i.log"; then
          skip_ "T-live-$lbl" "scanner did not run (registry unreachable?) — blocking UNPROVEN here"
        else
          fail_ "T-live-$lbl" "the $lbl sink COMMITTED CLEAN through the hook (BL-131 wiring not blocking): $(grep -E '\[OK\]|\[BLOCKED\]' "$TOPTMP/live-$i.log" | head -1)"
        fi
      elif ! grep -q "\[BLOCKED\]" "$TOPTMP/live-$i.log"; then
        fail_ "T-live-$lbl" "refused but without [BLOCKED] (wrong reason): $(tail -3 "$TOPTMP/live-$i.log" | tr '\n' '|')"
      elif [ "$H0" != "$H1" ]; then
        fail_ "T-live-$lbl" "non-zero exit but HEAD MOVED"
      else
        pass "T-live-$lbl: the sink is REFUSED by the emitted hook, HEAD unmoved"
      fi
    fi
    i=$((i + 1))
  done

  # ── T-live-benign ──────────────────────────────────────────────────────────
  echo "=== T-live-benign ==="
  RB="$TOPTMP/live-benign"
  if ! mk_repo "$RB" "$EMITTED" 1; then
    fail_ "T-live-benign" "repo setup failed"
  else
    H0="$(head_of "$RB")"
    V="$(commit_fixture "$RB" "$FX/benign.ts" "safe.ts" "$TOPTMP/live-benign.log")"
    H1="$(head_of "$RB")"
    if not_enforced "$TOPTMP/live-benign.log"; then
      skip_ "T-live-benign" "scanner did not run — clean case vacuous here"
    elif [ "$V" = "REFUSED" ]; then
      fail_ "T-live-benign" "the benign control was BLOCKED (false positive): $(grep '\[BLOCKED\]' "$TOPTMP/live-benign.log" | head -1)"
    elif ! grep -q "\[OK\] semgrep: SAST ran" "$TOPTMP/live-benign.log"; then
      fail_ "T-live-benign" "landed but no [OK] receipt — cannot prove the scan RAN"
    else
      pass "T-live-benign: the benign control commits clean AND the scan RAN"
    fi
  fi

  # ── T-artifact-missing-is-loud (behavioral pin: DELETE the shipped ruleset) ─
  # Baseline WITH the ruleset must block (proves the machinery + registry). Then a
  # repo WITHOUT the ruleset must NOT silently pass clean — the hook goes LOUD.
  echo "=== T-artifact-missing-is-loud ==="
  RBASE="$TOPTMP/pin-base"; mk_repo "$RBASE" "$EMITTED" 1
  VB="$(commit_fixture "$RBASE" "$FX/sink_ia.ts" "app.ts" "$TOPTMP/pin-base.log")"
  if [ "$VB" != "REFUSED" ] || not_enforced "$TOPTMP/pin-base.log"; then
    skip_ "T-artifact-missing-is-loud" "baseline sink did not block (registry unreachable?) — the deletion pin is unprovable here"
  else
    RNO="$TOPTMP/pin-noruleset"; mk_repo "$RNO" "$EMITTED" 0   # ship=0: ruleset ABSENT
    VN="$(commit_fixture "$RNO" "$FX/sink_ia.ts" "app.ts" "$TOPTMP/pin-noruleset.log")"
    if grep -q "\[OK\] semgrep: SAST ran" "$TOPTMP/pin-noruleset.log"; then
      fail_ "T-artifact-missing-is-loud" "with the ruleset DELETED the hook printed the CLEAN [OK] receipt — coverage vanished SILENTLY (verdict=$VN)"
    elif not_enforced "$TOPTMP/pin-noruleset.log" || grep -q "\[BLOCKED\]" "$TOPTMP/pin-noruleset.log"; then
      pass "T-artifact-missing-is-loud: a deleted ruleset makes the hook go LOUD (NOTRUN/blocked), never a silent clean pass"
    else
      fail_ "T-artifact-missing-is-loud" "deleted ruleset produced neither a clean pass, a NOTRUN, nor a block: $(tail -4 "$TOPTMP/pin-noruleset.log" | tr '\n' '|')"
    fi
  fi

  # ── T-mutation-ruleset-config (strip the --config line only) ────────────────
  echo "=== T-mutation-ruleset-config ==="
  MUT="$TOPTMP/mut-hook"
  sed "/soif-dom-sinks.yml/d" "$EMITTED" > "$MUT"
  if has_live "$MUT" "--config=$RULESET_REF"; then
    fail_ "T-mutation-ruleset-config" "the mutation did not remove the --config line"
  elif ! grep -qF '# BL-131-DOM-SINKS' "$MUT"; then
    fail_ "T-mutation-ruleset-config" "the mutation removed the marker too — it must attack BEHAVIOUR, keep the config on its own line"
  elif ! bash -n "$MUT" 2>/dev/null; then
    fail_ "T-mutation-ruleset-config" "stripping the config line broke the hook's syntax — keep it on its own continuation line"
  else
    landed=0; blocked=0; skipped_mut=0
    i=0
    while [ "$i" -lt "$N_SINKS" ]; do
      f="$(sfile "$i")"; dst="$(sdest "$i")"
      R="$TOPTMP/mut-$i"; mk_repo "$R" "$MUT" 1
      V="$(commit_fixture "$R" "$f" "$dst" "$TOPTMP/mut-$i.log")"
      if not_enforced "$TOPTMP/mut-$i.log"; then skipped_mut=$((skipped_mut + 1))
      elif [ "$V" = "COMMITTED" ]; then landed=$((landed + 1))
      else blocked=$((blocked + 1)); fi
      i=$((i + 1))
    done
    # GREEN direction: the real (unstripped) hook blocks the same four sinks.
    green_blocked=0; green_skipped=0
    i=0
    while [ "$i" -lt "$N_SINKS" ]; do
      f="$(sfile "$i")"; dst="$(sdest "$i")"
      R="$TOPTMP/mutg-$i"; mk_repo "$R" "$EMITTED" 1
      V="$(commit_fixture "$R" "$f" "$dst" "$TOPTMP/mutg-$i.log")"
      if not_enforced "$TOPTMP/mutg-$i.log"; then green_skipped=$((green_skipped + 1))
      elif [ "$V" = "REFUSED" ]; then green_blocked=$((green_blocked + 1)); fi
      i=$((i + 1))
    done
    if [ "$skipped_mut" -eq "$N_SINKS" ] || [ "$green_skipped" -eq "$N_SINKS" ]; then
      skip_ "T-mutation-ruleset-config" "scanner did not run (registry unreachable?) — mutation direction unprovable here"
    elif [ "$blocked" -eq 0 ] && [ "$landed" -gt 0 ] && [ "$green_blocked" -gt 0 ]; then
      pass "T-mutation-ruleset-config: without the --config line the sinks LAND ($landed/$N_SINKS, RED); with it restored they are REFUSED ($green_blocked blocked, GREEN)"
    else
      fail_ "T-mutation-ruleset-config" "expected RED (sinks land, none blocked) + GREEN (sinks blocked); got mut[landed=$landed blocked=$blocked skip=$skipped_mut] green[blocked=$green_blocked skip=$green_skipped]"
    fi
  fi
else
  skip_ "T-live-domsinks" "semgrep absent"
fi

echo ""
if [ "$SKIPPED" -gt 0 ]; then echo "!! $SKIPPED case(s) SKIPPED — skipped != passed."; fi
echo "Results: $PASSED passed, $FAILED failed ($SKIPPED skipped)"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
