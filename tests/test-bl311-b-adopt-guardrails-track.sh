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
# AND THE ARCHIVED MANIFEST IS NEVER PUT BACK (A6, A7 — review round 1,
# R-BL311B-1). Adoption changes none of the operator's keys, so the archived
# copy returns nothing of theirs — and it predates the adoption stamp, so
# restoring it removed the stamp and every tier key: the phase gate then said
# "Adoption stamp LOST", and after a commit "Phase gates consistent." `--re-add
# .claude/manifest.json` refuses (A6), and neither the disclosure nor
# MANIFEST.md prints a `cp` line for it (A7).
#
# ROW 8 — adoption wrote `track: "full"` (enterprise) for a free offline hobby
# app, because the track was a constant. It is ASKED now, beside the tier
# question, with init.sh's three descriptions and its two rules (Full on a
# personal project is re-confirmed; Light needs a Private POC, which adoption
# never lands, so Light is re-asked). End of input refuses, as every adoption
# question does — it never picks a track; the question has FOUR reads (the
# track, the Full re-confirmation, the track again after declining Full, the
# Light re-ask) and T6 ends the input at each. Both state files record the one
# answer (T1-T5, T7 for Full on an organizational project), and both writers
# refuse a track that is not exactly light, standard or full (T8).
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
#   tldr_mode             `## BL-312:` TL;DR mode — init.sh's seed and `adopt_write_manifest`
SOLO_KEYS="host mode remote_url deployment poc_mode enforcement_level soloFrameworkCommit currency adoption mcp tldr_mode"

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
  local label="A5 the run says the Guardrails settings in the manifest were kept, and points to no restore" bad=""
  [ "$PARC" -eq 0 ] || { fail_ "$label" "adoption did not complete (A1)"; return; }
  grep -q 'Their settings in .claude/manifest.json (profile desktop-app, 13 rules, 14 hooks) are kept' "$WORK/pa.out" \
    && grep -q 'adoption adds this framework.s keys beside them and changes none of theirs' "$WORK/pa.out" \
    || bad="$bad [not said: $(grep -A3 'already has the Guardrails' "$WORK/pa.out" | tr '\n' '|')]"
  # R-BL311B-1: the note used to end "with the line that puts it back".
  grep -A4 'already has the Guardrails' "$WORK/pa.out" | grep -qi 'puts it back' && bad="$bad [the note still points to a restore]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
# A6 and A7 — `## BL-311:` review round 1, R-BL311B-1. Run on a COPY of the
# adopted tree, so a mutant that lets the restore through changes nothing the
# other cases read.
a6() {
  local label="A6 --re-add .claude/manifest.json is refused: the stamp and every tier key stay, nothing is recorded, nothing is asked" p="$WORK/pa6" bad="" rc=0 pre=""
  [ "$PARC" -eq 0 ] || { fail_ "$label" "adoption did not complete (A1)"; return; }
  cp -R "$PA" "$p" || { fail_ "$label" "could not copy the adopted tree"; return; }
  cp "$p/.claude/manifest.json" "$WORK/pa6-manifest.before"
  pre="$(jq -c '{adopted: .adoption.adopted, missing: (["host","mode","deployment","poc_mode","enforcement_level","remote_url"] - keys)}' "$WORK/pa6-manifest.before" 2>&1)"
  [ "$pre" = '{"adopted":true,"missing":[]}' ] \
    || { fail_ "$label" "the adopted manifest does not carry the stamp and the six tier keys to begin with: $pre"; return; }
  # `1` is "Yes — put it back": the answer that restored the file before the fix.
  ( cd "$p" && printf '1\n' | bash "$REPO_ROOT/scripts/adopt-project.sh" --re-add .claude/manifest.json ) > "$WORK/pa6.out" 2>&1 || rc=$?
  [ "$rc" -eq 1 ] || bad="$bad [rc $rc, not 1]"
  grep -qF '[REFUSED] .claude/manifest.json is not put back: nothing of yours in it was changed' "$WORK/pa6.out" \
    || bad="$bad [not the refusal: $(grep -m1 -E 'REFUSED|BLOCKED|is back' "$WORK/pa6.out")]"
  grep -q 'would remove the adoption stamp' "$WORK/pa6.out" || bad="$bad [the refusal does not say what restoring it would do]"
  grep -q 'Do you want to put your own' "$WORK/pa6.out" && bad="$bad [the question was asked]"
  cmp -s "$WORK/pa6-manifest.before" "$p/.claude/manifest.json" \
    || bad="$bad [the manifest changed: adoption=$(jq -c '.adoption.adopted' "$p/.claude/manifest.json" 2>/dev/null) deployment=$(jq -c '.deployment' "$p/.claude/manifest.json" 2>/dev/null)]"
  jq -e '[.[] | select(.details.event == "collision_re_add")] | length == 0' "$p/.claude/bypass-audit.json" >/dev/null 2>&1 \
    || bad="$bad [a collision_re_add row was recorded]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
a7() {
  local label="A7 the disclosure and MANIFEST.md print no cp line for the manifest — they say nothing of theirs changed and not to restore it" bad="" arc=""
  [ "$PARC" -eq 0 ] || { fail_ "$label" "adoption did not complete (A1)"; return; }
  arc="$(cd "$PA" && ls -d .claude/adoption-archive/*/ 2>/dev/null | head -1)"; arc="${arc%/}"
  [ -n "$arc" ] || { fail_ "$label" "no adoption archive"; return; }
  grep -qF "put it back: cp $arc/.claude/manifest.json" "$WORK/pa.out" && bad="$bad [the disclosure prints a cp line for it]"
  grep -A4 'yours: \.claude/manifest\.json' "$WORK/pa.out" | grep -q 'Nothing of yours was changed' || bad="$bad [the disclosure does not say nothing of theirs changed]"
  grep -A4 'yours: \.claude/manifest\.json' "$WORK/pa.out" | grep -q 'Do not put it back' || bad="$bad [the disclosure does not say not to restore it]"
  grep -F '| `.claude/manifest.json` |' "$PA/$arc/MANIFEST.md" | grep -q 'cp ' && bad="$bad [MANIFEST.md prints a cp line for it]"
  grep -F '| `.claude/manifest.json` |' "$PA/$arc/MANIFEST.md" | grep -q 'Do not put it back' || bad="$bad [MANIFEST.md does not say not to restore it]"
  jq -e '[.entries[] | select(.originalPath == ".claude/manifest.json" and .restore == null and ((.doNotRestore // "") | length > 0))] | length == 1' \
    "$PA/$arc/MANIFEST.json" >/dev/null 2>&1 || bad="$bad [MANIFEST.json still carries a restore command for it]"
  # THE CONTROL: every other file keeps its line, so "no cp line" is not the
  # whole disclosure having lost them.
  grep -qF "put it back: cp $arc/.claude/settings.json .claude/settings.json" "$WORK/pa.out" || bad="$bad [control: settings.json lost its restore line]"
  grep -F '| `.claude/settings.json` |' "$PA/$arc/MANIFEST.md" | grep -q 'cp ' || bad="$bad [control: MANIFEST.md lost settings.json's restore line]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
# A8 — the Adoption Record and PROJECT_INTAKE.md §13 promised that every
# archived file can be put back, and A6 shows the manifest cannot. Both now
# carry the disclosure's own formula: the MANIFEST gives, for each file, how to
# put it back or why not to.
a8() {
  local label="A8 the Adoption Record and §13 no longer promise every archived file goes back — the MANIFEST gives, for each, how to put it back or why not to" bad=""
  [ "$PARC" -eq 0 ] || { fail_ "$label" "adoption did not complete (A1)"; return; }
  grep -q 'any one of them can be put back with' "$PA/APPROVAL_LOG.md" && bad="$bad [the Record still promises every file goes back]"
  grep -qF "archived file, how to put it back or why not to." "$PA/APPROVAL_LOG.md" || bad="$bad [the Record does not carry the formula]"
  grep -qF -- '--re-add <your path>' "$PA/APPROVAL_LOG.md" || bad="$bad [control: the Record lost the --re-add line]"
  grep -q 'a restore line for each' "$PA/PROJECT_INTAKE.md" && bad="$bad [§13 still promises a restore line for each]"
  grep -qF 'and a MANIFEST that gives, for each file, how to put it back' "$PA/PROJECT_INTAKE.md" || bad="$bad [§13 does not carry the formula]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
a1; a2; a3; a4; a5; a6; a7; a8

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
t6() {  # end of input at each of the FOUR reads: refused, nothing written, never "full"
  # `adopt_ask_track` reads four times: the track; the Full re-confirmation;
  # the track again after declining Full (`afterfull`, review round 1,
  # R-BL311B-3 — unpinned until then, so `|| true` on that read survived and
  # wrote `track: ""`); and the Light re-ask.
  local c ans lbl p bad="" all=""
  for c in first reconfirm afterfull reask; do
    case "$c" in
      first)     ans='1\n';          lbl='the project track' ;;
      reconfirm) ans='1\nfull\n';    lbl='whether to keep the Full track' ;;
      afterfull) ans='1\nfull\nchoose a different track\n'; lbl='the project track' ;;
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
  [ -z "$all" ] && pass "T6 end of input at each of the four reads — the track, the Full re-confirmation, the track after declining Full, the Light re-ask — refuses; no track is ever picked" \
    || fail_ "T6 end of input refuses at every track read" "$all"
}
t7() {  # review round 1, R-BL311B-2: the Full rule's ORGANIZATIONAL side
  # Only a personal project is warned about Full. Dropping the `personal`
  # condition survived every case until this one. Three spare answers at the
  # end let a mutant that asks too much still reach the intake stage, so it
  # dies on the named assertions below and not on running out of input.
  local label="T7 Full on an organizational project is neither warned about nor re-confirmed, and both files record full" p="$WORK/t7" bad=""
  _base "$p"; _commit "$p" pyproject.toml src/app.py
  _adopt "$p" t7 '2\nfull\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n' intake
  grep -q 'Full track is designed for organizational projects' "$WORK/t7.out" && bad="$bad [the personal-only Full warning fired on an organizational project]"
  grep -q '^Continue with Full track?$' "$WORK/t7.out" && bad="$bad [Full was re-confirmed on an organizational project]"
  [ "$(grep -c '^Project track:$' "$WORK/t7.out")" -eq 1 ] || bad="$bad [the track was asked $(grep -c '^Project track:$' "$WORK/t7.out") times]"
  grep -q 'halted after the .intake. stage' "$WORK/t7.out" || bad="$bad [did not reach the intake stage: $(grep -m1 -E 'REFUSED|BLOCKED' "$WORK/t7.out")]"
  [ "$(_tracks "$p")" = "full|full" ] || bad="$bad [recorded $(_tracks "$p")]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
# T8 — review round 1, R-BL311B-3: THE WRITERS FAIL CLOSED. Each is called on
# its own, sourced the way the driver sources it, with a track that is not
# exactly one of the three; the control (`standard`) proves the harness can
# write at all, so a refusal is the guard and not a broken harness.
cat > "$WORK/track-writer.sh" <<'TW'
set -uo pipefail
R="$1"; P="$2"; which="$3"
ADOPT_FRAMEWORK_ROOT="$R"; ADOPT_CORE_LIB_DIR="$R/scripts/lib"
. "$ADOPT_CORE_LIB_DIR/helpers-core.sh"
for _p in adopt-core adopt-intake adopt-state; do . "$R/scripts/lib/adopt/$_p.sh"; done
ADOPT_WORK="$5"; ADOPT_PROJECT_NAME=kp; ADOPT_DEPLOYMENT=personal; ADOPT_POC_MODE=""
ADOPT_ANSWERS="$ADOPT_WORK/answers"; : > "$ADOPT_ANSWERS"
ADOPT_TRACK="$4"
case "$which" in
  ps) adopt_write_phase_state "$P" ;;
  ip) adopt_render_intake_progress "$P" ;;
esac
echo "RC=$?"
TW
t8() {
  local w f v n=0 p bad="" all="" out rc
  for w in ps ip; do
    case "$w" in ps) f=.claude/phase-state.json ;; ip) f=.claude/intake-progress.json ;; esac
    for v in "" Full enterprise "full " "light standard" standard; do
      n=$((n + 1)); p="$WORK/t8-$n"; mkdir -p "$p/w" || { fail_ "T8" "could not create $p/w"; return; }
      out="$(bash "$WORK/track-writer.sh" "$REPO_ROOT" "$p" "$w" "$v" "$p/w" 2>&1)"
      rc="$(printf '%s\n' "$out" | sed -n 's/^RC=//p' | tail -1)"
      bad=""
      if [ "$v" = "standard" ]; then
        [ "$rc" = 0 ] || bad="$bad [control: rc $rc: $(printf '%s' "$out" | tr '\n' '|' | cut -c1-200)]"
        [ "$(jq -r '.track' "$p/$f" 2>/dev/null)" = "standard" ] || bad="$bad [control: $f does not record standard]"
      else
        [ "$rc" = 1 ] || bad="$bad [rc '$rc', not 1]"
        [ ! -e "$p/$f" ] || bad="$bad [$f written: track $(jq -c '.track' "$p/$f" 2>/dev/null)]"
        printf '%s\n' "$out" | grep -qF "the project track is '$v', which is not light, standard or full" || bad="$bad [not the track refusal: $(printf '%s' "$out" | grep -m1 -E 'REFUSED|BLOCKED')]"
      fi
      [ -z "$bad" ] || all="$all {$w '$v':$bad}"
    done
  done
  [ -z "$all" ] && pass "T8 both writers refuse a track that is not exactly light, standard or full (empty, Full, enterprise, 'full ', two words) and write nothing; standard is written" \
    || fail_ "T8 the writers fail closed on a track that is not one of the three" "$all"
}
t1; t2; t3; t4; t5; t6; t7; t8

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
