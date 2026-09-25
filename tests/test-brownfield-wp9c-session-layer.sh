#!/usr/bin/env bash
# tests/test-brownfield-wp9c-session-layer.sh — WP9c: the Claude Code session
# layer an adopted project receives, from the code init.sh uses.
#
# SPEC: ADOPT-002-ARCH v2.2 §10-WP9c (§8.7a rows 18–21). Backlog: `## BL-242:`.
#
# WHAT EACH CASE OWNS.
#   L1  a plain adoption gets .claude/settings.json with init.sh's permissions
#       for its language, and the four vendored skills byte-identical
#   L2  PARITY BY DERIVATION: the adoptee's hook roster is the one init.sh's
#       function registers, as a set of (event, script) pairs, EXCEPT exactly
#       the bypass detector's PostToolUse arm (`## BL-277:`)
#   L3  an adoptee's own settings.json is COMPOSED: its rule and its hook
#       survive, the framework's are added, the archive says `composed`
#   L4  an adoptee's own copy of a framework skill is archived and replaced;
#       an unrelated skill of theirs is untouched
#   L5  the MCP declaration follows the predicate: written with the project's
#       collection and recorded in the manifest when Qdrant is available,
#       neither when it is not
#   L6  a symlinked settings.json is never written through
#   L7  the intake's §13 prompt no longer says the guides are missing
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

echo "== WP9c — the Claude Code session layer =="
for t in git jq; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done
WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT
LIB="$REPO_ROOT/scripts/lib/claude-settings.sh"

_base() {   # _base DIR — a small TypeScript project with its own history
  local p="$1"
  mkdir -p "$p/src" "$p/.claude" || return 1
  ( cd "$p" && git init -q . && git config user.email wp9c@test.invalid && git config user.name "WP9c Test" ) >/dev/null 2>&1
  printf '{"name":"acme","scripts":{"test":"exit 0"}}\n' > "$p/package.json"
  printf 'export const x = 1;\n' > "$p/src/index.ts"
}
_commit() { ( cd "$1" && git add -- "${@:2}" && git commit -q --no-verify -m "chore: their history" ) >/dev/null 2>&1; }
_adopt() {  # _adopt DIR TAG [ENV=VAL]
  local p="$1" tag="$2"; shift 2
  ( cd "$p" && printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n' | env "$@" bash "$REPO_ROOT/scripts/adopt-project.sh" ) > "$WORK/$tag.out" 2>&1
  RUN_RC=$?
}
_pairs() {  # _pairs FILE — (event, script) pairs, sorted
  jq -r '.hooks | to_entries[] | .key as $e | .value[] | .hooks[] | "\($e) \(.command as $c | (($c | capture("scripts/(?<s>[^ \"]+)").s) // $c))"' "$1" 2>/dev/null | LC_ALL=C sort -u
}
_dispo() { jq -r --arg r "$2" '.entries[] | select(.originalPath == $r) | .disposition' "$1"/.claude/adoption-archive/*/MANIFEST.json 2>/dev/null; }

P="$WORK/plain"; _base "$P"; _commit "$P" package.json src/index.ts
_adopt "$P" plain SOIF_ADOPT_QDRANT=no; PRC=$RUN_RC

l1() {
  local label="L1 a plain adoption gets init.sh's permissions and the four skills" bad="" s
  [ "$PRC" -eq 0 ] || { fail_ "$label" "rc $PRC: $(grep -E 'BLOCKED|REFUSED' "$WORK/plain.out" | head -1)"; return; }
  ( . "$LIB"; soif_claude_settings_json typescript ) | jq -S .permissions > "$WORK/want-perms.json"
  jq -S .permissions "$P/.claude/settings.json" > "$WORK/got-perms.json" 2>/dev/null
  cmp -s "$WORK/want-perms.json" "$WORK/got-perms.json" || bad="$bad [the permissions are not init.sh's for typescript]"
  for s in $( . "$LIB"; soif_vendored_skills ); do
    cmp -s "$P/.claude/skills/$s/SKILL.md" "$REPO_ROOT/templates/generated/skills/$s/SKILL.md" || bad="$bad [skill $s missing or altered]"
  done
  ( cd "$P" && git ls-files --error-unmatch .claude/settings.json .claude/skills/zoom-out/SKILL.md ) >/dev/null 2>&1 || bad="$bad [not committed]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

l2() {
  local label="L2 the roster is init.sh's, minus exactly the bypass detector's PostToolUse arm" d
  mkdir -p "$WORK/init-roster/.claude"
  ( cd "$WORK/init-roster" && . "$LIB" && soif_claude_settings_json typescript > .claude/settings.json && soif_register_hook_roster .claude/settings.json )
  _pairs "$WORK/init-roster/.claude/settings.json" > "$WORK/init.pairs"
  _pairs "$P/.claude/settings.json" > "$WORK/adopt.pairs"
  [ "$(grep -c . "$WORK/init.pairs")" -ge 12 ] || { fail_ "$label" "the greenfield roster has $(grep -c . "$WORK/init.pairs") pairs — the derivation is broken"; return; }
  d="$(comm -3 "$WORK/init.pairs" "$WORK/adopt.pairs")"
  if [ "$(printf '%s\n' "$d" | sed 's/^[[:space:]]*//' | grep -c .)" -eq 1 ] && printf '%s\n' "$d" | grep -q '^PostToolUse hooks/bypass-detector.sh$'; then
    pass "$label"
  else
    fail_ "$label" "difference is not exactly that one pair: $(printf '%s' "$d" | tr '\n' '|')"
  fi
}

l3() {
  local label="L3 an adoptee's settings.json is composed: theirs survives, the framework's is added" bad="" p="$WORK/own"
  _base "$p"
  printf '{"permissions":{"allow":["Bash(make *)"]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo THEIR-STOP-HOOK"}]}]},"theirKey":1}\n' > "$p/.claude/settings.json"
  _commit "$p" package.json src/index.ts .claude/settings.json
  _adopt "$p" own SOIF_ADOPT_QDRANT=no
  [ "$RUN_RC" -eq 0 ] || { fail_ "$label" "rc $RUN_RC"; return; }
  jq -e '.permissions.allow[0] == "Bash(make *)" and (.permissions.allow | index("Read")) != null and .theirKey == 1' "$p/.claude/settings.json" >/dev/null 2>&1 \
    || bad="$bad [their rule, their key, or the framework's rules missing]"
  grep -q 'THEIR-STOP-HOOK' "$p/.claude/settings.json" || bad="$bad [their hook was lost]"
  _pairs "$p/.claude/settings.json" | grep -q 'session-version-check.sh' || bad="$bad [the framework's hooks were not added]"
  [ "$(_dispo "$p" .claude/settings.json)" = "composed" ] || bad="$bad [archive row reads '$(_dispo "$p" .claude/settings.json)']"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

l4() {
  local label="L4 their copy of a framework skill is archived and replaced; their own skill is untouched" bad="" p="$WORK/skills"
  _base "$p"; mkdir -p "$p/.claude/skills/zoom-out" "$p/.claude/skills/mine"
  printf '# THEIR-ZOOM-OUT\n' > "$p/.claude/skills/zoom-out/SKILL.md"
  printf '# THEIR-OWN-SKILL\n' > "$p/.claude/skills/mine/SKILL.md"
  _commit "$p" package.json src/index.ts .claude/skills/zoom-out/SKILL.md .claude/skills/mine/SKILL.md
  _adopt "$p" skills SOIF_ADOPT_QDRANT=no
  [ "$RUN_RC" -eq 0 ] || { fail_ "$label" "rc $RUN_RC"; return; }
  cmp -s "$p/.claude/skills/zoom-out/SKILL.md" "$REPO_ROOT/templates/generated/skills/zoom-out/SKILL.md" || bad="$bad [the framework's zoom-out is not installed]"
  grep -q 'THEIR-ZOOM-OUT' "$p"/.claude/adoption-archive/*/.claude/skills/zoom-out/SKILL.md 2>/dev/null || bad="$bad [theirs is not in the archive]"
  [ "$(_dispo "$p" .claude/skills/zoom-out/SKILL.md)" = "replaced" ] || bad="$bad [archive row reads '$(_dispo "$p" .claude/skills/zoom-out/SKILL.md)']"
  grep -q 'THEIR-OWN-SKILL' "$p/.claude/skills/mine/SKILL.md" || bad="$bad [their own skill was changed]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

l5() {
  local label="L5 the MCP declaration follows the predicate" bad="" p="$WORK/mcp"
  _base "$p"; _commit "$p" package.json src/index.ts
  _adopt "$p" mcp SOIF_ADOPT_QDRANT=yes
  [ "$RUN_RC" -eq 0 ] || { fail_ "$label" "rc $RUN_RC"; return; }
  jq -e '.mcpServers.qdrant.args | index("mcp") != null and (.[-1] == "mcp")' "$p/.claude/settings.local.json" >/dev/null 2>&1 \
    || bad="$bad [settings.local.json does not name the project's collection]"
  jq -e '.mcp.qdrant_required == true' "$p/.claude/manifest.json" >/dev/null 2>&1 || bad="$bad [the requirement is not in the manifest]"
  [ ! -e "$P/.claude/settings.local.json" ] || bad="$bad [written with Qdrant unavailable]"
  jq -e '.mcp.qdrant_required // false | not' "$P/.claude/manifest.json" >/dev/null 2>&1 || bad="$bad [recorded with Qdrant unavailable]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

l6() {
  local label="L6 a symlinked settings.json is never written through" bad="" p="$WORK/link"
  _base "$p"; _commit "$p" package.json src/index.ts
  printf '{"shared":true}\n' > "$WORK/shared-settings.json"
  ln -s "$WORK/shared-settings.json" "$p/.claude/settings.json"
  _adopt "$p" link SOIF_ADOPT_QDRANT=no
  [ "$RUN_RC" -eq 0 ] || { fail_ "$label" "rc $RUN_RC: $(grep -E 'BLOCKED|REFUSED' "$WORK/link.out" | head -1)"; return; }
  [ "$(cat "$WORK/shared-settings.json")" = '{"shared":true}' ] || bad="$bad [the link's target was written]"
  grep -q 'is a symlink, or inside one; it was left alone' "$WORK/link.out" || bad="$bad [the run did not say so]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

l7() {
  local label="L7 §13 no longer says the guides are missing, and names the Platform Module"
  if grep -q 'an adopted one' "$P/PROJECT_INTAKE.md" || ! grep -q 'Platform Module' "$P/PROJECT_INTAKE.md"; then
    fail_ "$label" "the prompt still claims the guides are absent, or does not name the Platform Module"
  else pass "$label"; fi
}

l1; l2; l3; l4; l5; l6; l7
echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
