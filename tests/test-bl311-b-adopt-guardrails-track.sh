#!/usr/bin/env bash
# tests/test-bl311-b-adopt-guardrails-track.sh — `## BL-311:` rows 2 and 8,
# from brownfield dogfood run 1 (k-pdf, 2026-09-27).
#
# ROW 2 — adoption refused "this project already looks framework-managed" on a
# project whose `.claude/` was the Development Guardrails' own and nothing of
# this framework's. The fixture is that project's `.claude/` as the Guardrails
# 4.3.0 installer left it, copied from the run's evidence: a `frameworkVersion`
# manifest carrying the operator's profile, rules, hooks, project config and
# discovery answers, `settings.json` with the Guardrails' hooks and permission
# rules, an untracked `settings.local.json`, and `.claude/framework/`.
#
# The recognition must stay STRICT, so both sides are pinned:
#   the Solo side — every top-level key this framework writes into
#     `.claude/manifest.json` still refuses, exactly as before. The list is
#     DERIVED: K1 takes what adoption adds from a real run, K2 reads init.sh's
#     writers as source; R1 drives every key through the preflight.
#   the Guardrails side — the real 4.3.0 shape adopts (A1), and adopting it
#     changes none of the operator's Guardrails settings (A2-A5).
#
# ROW 8 — adoption wrote `track: "full"` (enterprise) for a free offline hobby
# app, because the track was a constant. It is ASKED now, beside the tier
# question, with init.sh's three descriptions and its two rules (Full on a
# personal project is re-confirmed; Light needs a Private POC, which adoption
# never lands, so Light is re-asked). End of input refuses, as every adoption
# question does — it never picks a track. Both state files record the one
# answer (T1-T6).
set -uo pipefail
# `## BL-311:` the adoption driver's MCP step can ask a question and run
# `claude mcp add` / `docker` on a machine that has `claude` and is missing a
# server. This suite's piped answers were written before that step existed, so
# it is switched off here (`# BL-311-MCP-SEAM`); tests/test-bl311-adopt-mcp.sh
# exercises the real step.
export SOIF_ADOPT_MCP=off

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

echo "== BL-311 rows 2 and 8 — a Guardrails-only .claude/ adopts; the track is asked =="
for t in git jq; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done
WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT
# Never created. The host's real Guardrails clone must not run here: a mutant
# that admitted a shape without `.claude/framework/` would otherwise run it.
NOCLONE="$WORK/no-guardrails-clone"

# ── The fixture: k-pdf's `.claude/`, as the Guardrails 4.3.0 installer left it ──
GR_MANIFEST='{"frameworkVersion":"4.3.0","frameworkRepo":"kraulerson/claude-dev-framework","localClonePath":"~/.claude-dev-framework","lastSyncDate":"2026-07-09T17:20:36Z","profile":"desktop-app","profileInherits":["_base"],"files":{},"activeRules":["evaluate-before-implement","plan-before-code","test-per-bugfix","test-strategy","naming-conventions","context-management","session-discipline","superpowers-workflow","verify-after-complete","plan-closure","version-bump","changelog-update","future-scalability"],"activeHooks":["session-start","compliance-reinforce","config-guard","enforce-evaluate","enforce-superpowers","stop-checklist","session-end","marker-tracker","marker-guard","enforce-plan-tracking","enforce-context7","verification-gate","pre-commit-checks","branch-safety"],"projectConfig":{"_base":{"sourceExtensions":[".py",".qss"],"protectedBranches":["main"],"verificationGates":[]},"branches":[]},"discovery":{"branch:main":{"purpose":"Primary development branch","devOS":"macOS","targetPlatform":"Windows, macOS, Linux","buildTools":"uv, Nuitka, PySide6"},"discoveryDate":"2026-04-02","lastReviewDate":"2026-04-02"},"frameworkCommit":"0396a1a"}'
GR_SETTINGS='{"permissions":{"allow":["Read","Edit","Write","Glob","Grep","Bash","WebFetch(domain:*)"],"deny":["Bash(curl * | bash)","Bash(rm -rf /)","Bash(rm -rf /*)","Bash(wget * | bash)","Edit(/.claude/framework/**)","Edit(/.claude/manifest.json)","Edit(/.claude/settings.json)","Edit(/.claude/settings.local.json)","Edit(//private/tmp/.claude_*)","Edit(//tmp/.claude_*)","Read(./.env)","Read(./.env.*)","Write(/.claude/framework/**)","Write(/.claude/manifest.json)","Write(/.claude/settings.json)","Write(/.claude/settings.local.json)","Write(//private/tmp/.claude_*)","Write(//tmp/.claude_*)"]},"hooks":{"PostToolUse":[{"hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/marker-tracker.sh"}]}],"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/enforce-evaluate.sh"},{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/verification-gate.sh"},{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/pre-commit-checks.sh"},{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/branch-safety.sh"}]},{"matcher":"Bash|Write|Edit|NotebookEdit","hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/config-guard.sh"},{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/marker-guard.sh"}]},{"matcher":"Write|Edit|NotebookEdit","hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/enforce-superpowers.sh"},{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/enforce-plan-tracking.sh"},{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/enforce-context7.sh"}]}],"SessionEnd":[{"hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/session-end.sh"}]}],"SessionStart":[{"hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/session-start.sh"}]}],"Stop":[{"hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/stop-checklist.sh"}]}],"UserPromptSubmit":[{"hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/compliance-reinforce.sh"}]}]}}'
GR_LOCAL='{"permissions":{"allow":["Bash(cd *)"]}}'

# THE SOLO KEY LIST, AND WHERE EACH ONE COMES FROM. K1 and K2 below re-derive
# it from the writers; R1 drives every entry through the preflight.
#   host mode remote_url deployment poc_mode enforcement_level
#       init.sh's manifest seed (prepare_initial_state_for_commit) and
#       adoption's `adopt_write_manifest`
#   soloFrameworkCommit   init.sh's birth pin (# BL-110-PIN-UNIVERSAL)
#   currency              soif_currency_stamp (# BL-109-CURRENCY)
#   mcp                   `.mcp.qdrant_required`, init.sh and adoption's session layer
#   adoption              the adoption stamp
SOLO_KEYS="host mode remote_url deployment poc_mode enforcement_level soloFrameworkCommit currency adoption mcp"

_base() {
  local p="$1"
  mkdir -p "$p/src" || return 1
  ( cd "$p" && git init -q . && git config user.email bl311b@test.invalid && git config user.name "BL311b Test" ) >/dev/null 2>&1
  printf '[project]\nname = "kp"\nversion = "0.1.0"\n' > "$p/pyproject.toml"
  printf 'x = 1\n' > "$p/src/app.py"
}
_commit() { ( cd "$1" && git add -- "${@:2}" && git commit -q --no-verify -m "chore: their history" ) >/dev/null 2>&1; }
# _guardrails DIR [MANIFEST] [nofw] — the Guardrails' .claude/, committed as
# the operator had it; settings.local.json stays untracked, as it does in the
# field.
_guardrails() {
  local p="$1" m="${2:-$GR_MANIFEST}" nofw="${3:-}" h r
  mkdir -p "$p/.claude" || return 1
  printf '%s\n' "$m" > "$p/.claude/manifest.json"
  printf '%s\n' "$GR_SETTINGS" | jq . > "$p/.claude/settings.json"
  printf '%s\n' "$GR_LOCAL" | jq . > "$p/.claude/settings.local.json"
  if [ -z "$nofw" ]; then
    mkdir -p "$p/.claude/framework/hooks" "$p/.claude/framework/rules" "$p/.claude/framework/gates"
    for h in session-start stop-checklist config-guard enforce-evaluate branch-safety; do
      printf '#!/usr/bin/env bash\n# Guardrails 4.3.0 hook: %s\nexit 0\n' "$h" > "$p/.claude/framework/hooks/$h.sh"
    done
    for r in plan-before-code test-strategy version-bump; do
      printf '# Guardrails 4.3.0 rule: %s\n' "$r" > "$p/.claude/framework/rules/$r.md"
    done
    printf '#!/usr/bin/env bash\nexit 0\n' > "$p/.claude/framework/gates/visual-auditor.sh"
  fi
  if [ -z "$nofw" ]; then
    _commit "$p" pyproject.toml src/app.py .claude/manifest.json .claude/settings.json .claude/framework
  else
    _commit "$p" pyproject.toml src/app.py .claude/manifest.json .claude/settings.json
  fi
}
# _adopt DIR TAG ANSWERS [HALT_STAGE] — ANSWERS is a printf format.
_adopt() {
  local p="$1" tag="$2" ans="$3" halt="${4:-}"
  # shellcheck disable=SC2059
  ( cd "$p" && printf "$ans" | SOIF_ADOPT_QDRANT=no SOIF_ADOPT_GUARDRAILS_DIR="$NOCLONE" SOIF_ADOPT_HALT_AFTER="$halt" \
      bash "$REPO_ROOT/scripts/adopt-project.sh" ) > "$WORK/$tag.out" 2>&1
  RUN_RC=$?
}
_frameworktree() { ( cd "$1/.claude/framework" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$(cksum < "$f")" "$f"; done ); }

echo
echo "=== A — the Guardrails' own .claude/ adopts, and keeps every setting ==="
PA="$WORK/pa"; _base "$PA"; _guardrails "$PA"
cp "$PA/.claude/manifest.json" "$WORK/pa-manifest.orig"
cp "$PA/.claude/settings.json" "$WORK/pa-settings.orig"
cp "$PA/.claude/settings.local.json" "$WORK/pa-local.orig"
_frameworktree "$PA" > "$WORK/pa-framework.orig"
_adopt "$PA" pa '1\nstandard\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n'; PARC=$RUN_RC

a1() {
  local label="A1 a Guardrails-only .claude/ (4.3.0, k-pdf's shape) adopts: rc 0, stamped, the Guardrails' own arm reached" bad=""
  [ "$PARC" -eq 0 ] || { fail_ "$label" "rc $PARC: $(grep -E 'BLOCKED|REFUSED' "$WORK/pa.out" | head -1)"; return; }
  jq -e '.adoption.adopted == true' "$PA/.claude/manifest.json" >/dev/null 2>&1 || bad="$bad [no adoption stamp]"
  grep -q 'This project already has the Guardrails' "$WORK/pa.out" || bad="$bad [the Guardrails stage did not take its already-installed arm]"
  grep -q 'already looks framework-managed' "$WORK/pa.out" && bad="$bad [the managed refusal printed]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
a2() {
  local label="A2 every key of the operator's Guardrails manifest is unchanged after adoption" bad=""
  [ "$PARC" -eq 0 ] || { fail_ "$label" "adoption did not complete (A1)"; return; }
  bad="$(jq -rn --slurpfile o "$WORK/pa-manifest.orig" --slurpfile a "$PA/.claude/manifest.json" \
    '[$o[0] | to_entries[] | select($a[0][.key] != .value) | .key] | join(",")' 2>/dev/null)" || bad="(could not compare)"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "changed or dropped: $bad"
}
a3() {
  local label="A3 their settings survive: every hook command and permission rule, settings.local.json byte for byte, .claude/framework/ untouched" bad="" miss=""
  [ "$PARC" -eq 0 ] || { fail_ "$label" "adoption did not complete (A1)"; return; }
  miss="$(jq -rn --slurpfile o "$WORK/pa-settings.orig" --slurpfile a "$PA/.claude/settings.json" \
    '([$o[0].hooks | .. | objects | select(has("command")) | .command] - [$a[0].hooks | .. | objects | select(has("command")) | .command]) | join(" ")' 2>/dev/null)"
  [ -z "$miss" ] || bad="$bad [hook commands dropped: $miss]"
  miss="$(jq -rn --slurpfile o "$WORK/pa-settings.orig" --slurpfile a "$PA/.claude/settings.json" \
    '(($o[0].permissions.allow + $o[0].permissions.deny) - (($a[0].permissions.allow // []) + ($a[0].permissions.deny // []))) | join(" ")' 2>/dev/null)"
  [ -z "$miss" ] || bad="$bad [permission rules dropped: $miss]"
  cmp -s "$WORK/pa-local.orig" "$PA/.claude/settings.local.json" || bad="$bad [settings.local.json changed]"
  _frameworktree "$PA" | cmp -s "$WORK/pa-framework.orig" - || bad="$bad [.claude/framework/ changed]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
a4() {
  local label="A4 the manifest as it was is archived (byte for byte, disposition composed) and the disclosure names it" bad="" arc=""
  [ "$PARC" -eq 0 ] || { fail_ "$label" "adoption did not complete (A1)"; return; }
  arc="$(cd "$PA" && ls -d .claude/adoption-archive/*/ 2>/dev/null | head -1)"; arc="${arc%/}"
  [ -n "$arc" ] || { fail_ "$label" "no adoption archive"; return; }
  cmp -s "$WORK/pa-manifest.orig" "$PA/$arc/.claude/manifest.json" || bad="$bad [the archived copy is not the original]"
  jq -e '[.entries[] | select(.originalPath == ".claude/manifest.json" and .disposition == "composed")] | length == 1' "$PA/$arc/MANIFEST.json" >/dev/null 2>&1 \
    || bad="$bad [MANIFEST.json has no composed row for it: $(jq -c '[.entries[] | select(.originalPath == ".claude/manifest.json")]' "$PA/$arc/MANIFEST.json" 2>/dev/null)]"
  grep -q 'yours: \.claude/manifest\.json' "$WORK/pa.out" || bad="$bad [the disclosure does not list it]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
a5() {
  local label="A5 the run says the Guardrails settings in the manifest were kept, and where the original is"
  [ "$PARC" -eq 0 ] || { fail_ "$label" "adoption did not complete (A1)"; return; }
  if grep -q 'Their settings in .claude/manifest.json (profile desktop-app, 13 rules, 14 hooks) are kept' "$WORK/pa.out" \
     && grep -q 'adoption adds this framework.s keys beside them and changes none of theirs' "$WORK/pa.out"; then
    pass "$label"
  else
    fail_ "$label" "not said: $(grep -A3 'already has the Guardrails' "$WORK/pa.out" | tr '\n' '|')"
  fi
}
a1; a2; a3; a4; a5

echo
echo "=== K — the Solo key list, derived from its writers ==="
k1() {
  local label="K1 every key a real adoption adds to a Guardrails manifest is on the Solo key list" added="" k extra=""
  [ "$PARC" -eq 0 ] || { fail_ "$label" "adoption did not complete (A1)"; return; }
  added="$(jq -rn --slurpfile o "$WORK/pa-manifest.orig" --slurpfile a "$PA/.claude/manifest.json" '($a[0] | keys) - ($o[0] | keys) | .[]' 2>/dev/null)"
  [ -n "$added" ] || { fail_ "$label" "adoption added no key at all — the derivation measured nothing"; return; }
  for k in $added; do
    case " $SOLO_KEYS " in *" $k "*) : ;; *) extra="$extra $k" ;; esac
  done
  [ -z "$extra" ] && pass "$label ($(printf '%s' "$added" | tr '\n' ' '))" \
    || fail_ "$label" "adoption now writes$extra — add it to SOLO_KEYS here and to the product list (# BL-311-SOLO-KEYS)"
}
k2() {
  local label="K2 init.sh's manifest writers name no key missing from the list (seed literal, birth pin, MCP flag, currency)" seed="" k bad=""
  seed="$(command grep -oE "'\. \+ \{[^}]*\}'" "$REPO_ROOT/init.sh" | head -1)"
  [ -n "$seed" ] || { fail_ "$label" "init.sh's manifest seed literal ('. + {host:…}') moved — re-derive the Solo key list"; return; }
  for k in $(printf '%s' "$seed" | command grep -oE '[a-z_]+:' | tr -d ':'); do
    case " $SOLO_KEYS " in *" $k "*) : ;; *) bad="$bad [seed writes $k]" ;; esac
  done
  [ "$(printf '%s' "$seed" | command grep -oE '[a-z_]+:' | wc -l | tr -d ' ')" -ge 6 ] || bad="$bad [the seed literal carries fewer than six keys: $seed]"
  command grep -q "'\.soloFrameworkCommit = \$c'" "$REPO_ROOT/init.sh" || bad="$bad [init.sh's soloFrameworkCommit writer moved]"
  command grep -q "'\.mcp = ((\.mcp // {}) | \.qdrant_required = true)'" "$REPO_ROOT/init.sh" || bad="$bad [init.sh's mcp writer moved]"
  command grep -q 'soif_currency_stamp "\$manifest"' "$REPO_ROOT/init.sh" || bad="$bad [init.sh no longer stamps currency into the manifest]"
  command grep -q "'\.currency = \$currency'" "$REPO_ROOT/scripts/lib/currency-manifest.sh" || bad="$bad [the currency writer moved]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad — re-derive SOLO_KEYS and the product list (# BL-311-SOLO-KEYS)"
}
k1; k2

echo
echo "=== R — every other shape refuses exactly as before ==="
_refused_managed() {  # _refused_managed TAG DIR WHAT ORIGFILE — the arm-3 refusal, nothing written
  local tag="$1" p="$2" what="$3" orig="$4" bad=""
  [ "$RUN_RC" -eq 1 ] || bad="$bad [rc $RUN_RC, not 1]"
  grep -qF "[REFUSED] this project already looks framework-managed: $what" "$WORK/$tag.out" || bad="$bad [not the managed refusal: $(grep -m1 -E 'REFUSED|BLOCKED' "$WORK/$tag.out")]"
  [ ! -e "$p/.claude/adoption-archive" ] || bad="$bad [an archive was written]"
  cmp -s "$orig" "$p/.claude/manifest.json" || bad="$bad [the manifest changed]"
  printf '%s' "$bad"
}
r1() {
  local k v p m bad="" all=""
  for k in $SOLO_KEYS; do
    case "$k" in
      adoption) v='{"adoptedAtCommit":"0000000000000000000000000000000000000000"}' ;;   # a block without the flag: arm 1 is silent
      currency) v='{"schemaVersion":1}' ;;
      mcp)      v='{"qdrant_required":true}' ;;
      poc_mode) v='null' ;;   # PRESENCE counts, not a truthy value
      *)        v='"personal"' ;;
    esac
    p="$WORK/r1-$k"; _base "$p"
    m="$(printf '%s' "$GR_MANIFEST" | jq -c --arg k "$k" --argjson v "$v" '. + {($k): $v}')"
    _guardrails "$p" "$m"
    cp "$p/.claude/manifest.json" "$WORK/r1-$k.orig"
    _adopt "$p" "r1-$k" '1\nstandard\n1\n1\n1\n1\n1\n1\n1\n1\n'
    bad="$(_refused_managed "r1-$k" "$p" ".claude/manifest.json is present" "$WORK/r1-$k.orig")"
    [ -z "$bad" ] || all="$all {$k:$bad}"
  done
  [ -z "$all" ] && pass "R1 a Guardrails manifest carrying ANY one Solo key still refuses (${SOLO_KEYS// /, })" \
    || fail_ "R1 a Guardrails manifest carrying ANY one Solo key still refuses" "$all"
}
r2() {
  local label="R2 a Guardrails manifest beside a .claude/phase-state.json refuses on the phase-state" p="$WORK/r2" bad=""
  _base "$p"; _guardrails "$p"; printf '{"current_phase":0}\n' > "$p/.claude/phase-state.json"
  cp "$p/.claude/manifest.json" "$WORK/r2.orig"
  _adopt "$p" r2 '1\nstandard\n1\n1\n1\n1\n1\n1\n1\n1\n'
  bad="$(_refused_managed r2 "$p" ".claude/phase-state.json is present" "$WORK/r2.orig")"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
r3() {
  local label="R3 a Guardrails manifest carrying the adoption stamp refuses as already adopted" p="$WORK/r3" m bad=""
  _base "$p"; m="$(printf '%s' "$GR_MANIFEST" | jq -c '. + {adoption: {adopted: true}}')"; _guardrails "$p" "$m"
  _adopt "$p" r3 '1\nstandard\n1\n1\n1\n1\n1\n1\n1\n1\n'
  [ "$RUN_RC" -eq 1 ] || bad="$bad [rc $RUN_RC]"
  grep -qF '[REFUSED] this project has already been adopted' "$WORK/r3.out" || bad="$bad [not the adopted refusal: $(grep -m1 -E 'REFUSED|BLOCKED' "$WORK/r3.out")]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
r4() {
  local label="R4 a manifest that is not the Guardrails' own shape still refuses" m p bad="" all="" c
  # nofw: frameworkVersion, but no .claude/framework/hooks for the stage's already-installed arm to find
  for c in nofw noversion emptyversion numversion notjson notobject; do
    p="$WORK/r4-$c"; _base "$p"
    case "$c" in
      nofw)         _guardrails "$p" "$GR_MANIFEST" nofw ;;
      noversion)    _guardrails "$p" "$(printf '%s' "$GR_MANIFEST" | jq -c 'del(.frameworkVersion)')" ;;
      emptyversion) _guardrails "$p" "$(printf '%s' "$GR_MANIFEST" | jq -c '.frameworkVersion = ""')" ;;
      numversion)   _guardrails "$p" "$(printf '%s' "$GR_MANIFEST" | jq -c '.frameworkVersion = 4')" ;;
      notjson)      _guardrails "$p" '{"frameworkVersion": "4.3.0",' ;;
      notobject)    _guardrails "$p" '["frameworkVersion"]' ;;
    esac
    cp "$p/.claude/manifest.json" "$WORK/r4-$c.orig"
    _adopt "$p" "r4-$c" '1\nstandard\n1\n1\n1\n1\n1\n1\n1\n1\n'
    bad="$(_refused_managed "r4-$c" "$p" ".claude/manifest.json is present" "$WORK/r4-$c.orig")"
    [ -z "$bad" ] || all="$all {$c:$bad}"
  done
  [ -z "$all" ] && pass "$label (no .claude/framework/, no/empty/numeric frameworkVersion, not JSON, not an object)" || fail_ "$label" "$all"
}
r1; r2; r3; r4

echo
echo "=== T — the track is asked, validated as init.sh validates it, and recorded once ==="
_tracks() {  # _tracks DIR → "<phase-state track>|<intake-progress track>"
  printf '%s|%s' "$(jq -r '.track' "$1/.claude/phase-state.json" 2>/dev/null)" "$(jq -r '.track' "$1/.claude/intake-progress.json" 2>/dev/null)"
}
t1() {
  local label="T1 the answer is what both state files record (personal, standard)"
  [ "$PARC" -eq 0 ] || { fail_ "$label" "adoption did not complete (A1)"; return; }
  [ "$(_tracks "$PA")" = "standard|standard" ] && pass "$label" || fail_ "$label" "phase-state|intake-progress = $(_tracks "$PA")"
}
t2() {
  local label="T2 init.sh's three track descriptions are shown verbatim before the question" d bad="" n=0
  [ -s "$WORK/pa.out" ] || { fail_ "$label" "no transcript (A1)"; return; }
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    n=$((n + 1))
    grep -qF -- "$d" "$WORK/pa.out" || bad="$bad [missing: $d]"
  done <<DESCS
$(command grep -E '^[[:space:]]*echo "[[:space:]]+(Light|Standard|Full)[[:space:]]+— ' "$REPO_ROOT/init.sh" | sed -e 's/^[[:space:]]*echo "[[:space:]]*//' -e 's/"[[:space:]]*$//')
DESCS
  [ "$n" -eq 3 ] || bad="$bad [init.sh has $n description lines, not 3 — its prompt moved]"
  grep -q '^Project track:$' "$WORK/pa.out" || bad="$bad [the question was not asked]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
t3() {
  local label="T3 Light on an organizational project is re-asked (production needs Standard or Full); no Full warning" p="$WORK/t3" bad=""
  _base "$p"; _commit "$p" pyproject.toml src/app.py
  _adopt "$p" t3 '2\nlight\nfull\n1\n1\n1\n1\n1\n1\n1\n1\n1\n' intake
  grep -q 'halted after the .intake. stage' "$WORK/t3.out" || { fail_ "$label" "did not reach the intake stage: $(grep -m1 -E 'REFUSED|BLOCKED' "$WORK/t3.out")"; return; }
  grep -q 'Production builds require Standard or Full track' "$WORK/t3.out" || bad="$bad [no light-track warning]"
  grep -q '^Select a track:$' "$WORK/t3.out" || bad="$bad [not re-asked]"
  grep -q 'Full track is designed for organizational projects' "$WORK/t3.out" && bad="$bad [the personal-only Full warning fired on an organizational project]"
  [ "$(_tracks "$p")" = "full|full" ] || bad="$bad [recorded $(_tracks "$p")]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
t4() {
  local label="T4 Full on a personal project is warned and re-confirmed; choosing again, then Light, lands on the re-asked answer" p="$WORK/t4" bad=""
  _base "$p"; _commit "$p" pyproject.toml src/app.py
  _adopt "$p" t4 '1\nfull\nchoose a different track\nlight\nstandard\n1\n1\n1\n1\n1\n1\n1\n1\n1\n' intake
  grep -q 'halted after the .intake. stage' "$WORK/t4.out" || { fail_ "$label" "did not reach the intake stage: $(grep -m1 -E 'REFUSED|BLOCKED' "$WORK/t4.out")"; return; }
  grep -q 'Full track is designed for organizational projects with enterprise compliance' "$WORK/t4.out" || bad="$bad [no Full-on-personal warning]"
  grep -q '^Continue with Full track?$' "$WORK/t4.out" || bad="$bad [not re-confirmed]"
  [ "$(grep -c '^Project track:$' "$WORK/t4.out")" -eq 2 ] || bad="$bad [the track was not asked again after declining]"
  grep -q 'Production builds require Standard or Full track' "$WORK/t4.out" || bad="$bad [the re-asked Light was not checked]"
  [ "$(_tracks "$p")" = "standard|standard" ] || bad="$bad [recorded $(_tracks "$p")]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
t5() {
  local label="T5 Full on a personal project, re-confirmed, is recorded as full in both files" p="$WORK/t5" bad=""
  _base "$p"; _commit "$p" pyproject.toml src/app.py
  _adopt "$p" t5 '1\nfull\ncontinue with Full track\n1\n1\n1\n1\n1\n1\n1\n1\n1\n' intake
  grep -q 'halted after the .intake. stage' "$WORK/t5.out" || { fail_ "$label" "did not reach the intake stage: $(grep -m1 -E 'REFUSED|BLOCKED' "$WORK/t5.out")"; return; }
  [ "$(_tracks "$p")" = "full|full" ] || bad="$bad [recorded $(_tracks "$p")]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
t6() {  # end of input at each of the three reads: refused, nothing written, never "full"
  local c ans lbl p bad="" all=""
  for c in first reconfirm reask; do
    case "$c" in
      first)     ans='1\n';          lbl='the project track' ;;
      reconfirm) ans='1\nfull\n';    lbl='whether to keep the Full track' ;;
      reask)     ans='2\nlight\n';   lbl='the project track' ;;
    esac
    p="$WORK/t6-$c"; _base "$p"; _commit "$p" pyproject.toml src/app.py
    _adopt "$p" "t6-$c" "$ans"
    bad=""
    [ "$RUN_RC" -eq 1 ] || bad="$bad [rc $RUN_RC]"
    grep -qF "no answer was given: $lbl" "$WORK/t6-$c.out" || bad="$bad [not the mandatory refusal for '$lbl': $(grep -m1 -E 'REFUSED|BLOCKED' "$WORK/t6-$c.out")]"
    # AND THE RUN STOPPED THERE. A refusal that is printed and then carried
    # past — a track picked on the way out — still names the question; what
    # gives it away is a second refusal further on, or the track being settled.
    [ "$(grep -c '^\[REFUSED\]' "$WORK/t6-$c.out")" -eq 1 ] || bad="$bad [the run went on past the refusal: $(grep '^\[REFUSED\]' "$WORK/t6-$c.out" | tr '\n' '|')]"
    grep -q '^   Track: ' "$WORK/t6-$c.out" && bad="$bad [a track was settled: $(grep '^   Track: ' "$WORK/t6-$c.out")]"
    [ ! -e "$p/.claude/phase-state.json" ] || bad="$bad [phase-state written: $(_tracks "$p")]"
    [ -z "$bad" ] || all="$all {$c:$bad}"
  done
  [ -z "$all" ] && pass "T6 end of input at the track question, the re-confirmation and the re-ask refuses — no track is ever picked" \
    || fail_ "T6 end of input refuses at every track read" "$all"
}
t1; t2; t3; t4; t5; t6

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
