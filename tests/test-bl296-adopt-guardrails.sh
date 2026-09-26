#!/usr/bin/env bash
# tests/test-bl296-adopt-guardrails.sh — `## BL-296:` row 33: the Development
# Guardrails installed into an adopted project.
#
# Hermetic by construction: every case but G6 points adoption at a STUB clone
# (`SOIF_ADOPT_GUARDRAILS_DIR`) whose installer behaves like the real one where
# it matters — it REPLACES .claude/manifest.json with `>`, merges hooks into
# settings.json, writes .claude/framework/, and leaves a .claude-backup/<ts>/.
# G6 runs the host's real clone when there is one and SKIPS otherwise (the PR
# lane has none).
#
# WHAT EACH CASE OWNS.
#   G1  installed: the installer ran, its files are committed, and the manifest
#       carries BOTH its keys and the adoption stamp (the order is load-bearing)
#   G2  its .claude-backup is removed, and an operator's own is not
#   G3  a project that already has the Guardrails is left as it was
#   G4  no clone: adoption completes, says NOT INSTALLED with the two commands,
#       and the Adoption Record says so
#   G5  an installer that fails blocks the adoption before any write
#   G6  the real installer, when this host has it
#   G7  a project whose type the installer cannot detect still gets the
#       Guardrails — adoption passes --profile (init.sh's web-api fallback)
#   G8  the operator's own settings.json hooks survive the installer, which
#       REPLACES `.hooks` (the stub does exactly what the real one does)
#   G9  a settings.json that is not plain JSON is restored byte for byte, and
#       the run says the Guardrails' hooks are not registered
#   G10 an operator's file under .claude/project the installer never touches
#       is not claimed as an installer write (it would trip I20)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

echo "== BL-296 — the Development Guardrails on the adoption path =="
for t in git jq; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done
WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT

# _stub DIR [fail] — a fake Guardrails clone. It copies the REAL installer
# where adoption depends on it: detect-profile.sh exits 1 without a TTY when it
# recognises nothing (here: no package.json), the installer then fails unless
# given --profile, and settings.json is merged with `. + {hooks: $h}` — which
# REPLACES the operator's hooks — or overwritten with `>` when it does not
# parse. (The first stub appended to .hooks; review showed the real one does
# not, and the stub's kindness hid two defects.)
_stub() {
  local d="$1" mode="${2:-ok}"
  mkdir -p "$d/scripts" || return 1
  ( cd "$d" && git init -q . ) >/dev/null 2>&1
  cat > "$d/scripts/detect-profile.sh" <<'DETECT'
#!/usr/bin/env bash
if [ -n "${1:-}" ]; then echo "$1"; exit 0; fi
[ -f package.json ] && { echo web-api; exit 0; }
echo "no TTY and no signals. Pass a profile explicitly" >&2; exit 1
DETECT
  cat > "$d/scripts/init.sh" <<STUB
#!/usr/bin/env bash
set -euo pipefail
[ "$mode" = fail ] && { echo "stub installer: refusing on purpose" >&2; exit 1; }
[ -t 0 ] && { echo "stub: stdin is a terminal — adoption must run this non-interactively" >&2; exit 2; }
PROFILE_ARG=""
while [ \$# -gt 0 ]; do case "\$1" in --profile) shift; PROFILE_ARG="\${1:-}" ;; esac; shift; done
PROFILE=\$(bash "$d/scripts/detect-profile.sh" \$PROFILE_ARG | tail -1)
printf '%s\n' "\$PROFILE" > "$WORK/stub-profile"
mkdir -p .claude-backup/STUB-TS .claude/framework/hooks .claude/framework/rules
cp -r .claude .claude-backup/STUB-TS/ 2>/dev/null || true
printf '#!/bin/sh\n# STUB-GUARDRAILS-HOOK\n' > .claude/framework/hooks/stub-hook.sh
printf '# stub rule\n' > .claude/framework/rules/stub-rule.md
echo "{\"frameworkVersion\":\"9.9.9-stub\",\"profile\":\"\$PROFILE\"}" > .claude/manifest.json
H='{"SessionStart":[{"hooks":[{"type":"command","command":"bash .claude/framework/hooks/stub-hook.sh"}]}]}'
if [ -f .claude/settings.json ] && jq '.' .claude/settings.json >/dev/null 2>&1; then
  jq --argjson h "\$H" '. + {hooks: \$h}' .claude/settings.json > .claude/settings.json.tmp
  mv .claude/settings.json.tmp .claude/settings.json
else
  echo "{\"hooks\":\$H}" > .claude/settings.json
fi
touch "$WORK/stub-ran"
STUB
}
_base() {
  local p="$1"
  mkdir -p "$p/src" || return 1
  ( cd "$p" && git init -q . && git config user.email bl296@test.invalid && git config user.name "BL296 Test" ) >/dev/null 2>&1
  printf '{"name":"acme","scripts":{"test":"exit 0"}}\n' > "$p/package.json"
  printf 'export const x = 1;\n' > "$p/src/index.ts"
}
_commit() { ( cd "$1" && git add -- "${@:2}" && git commit -q --no-verify -m "chore: their history" ) >/dev/null 2>&1; }
_adopt() {  # _adopt DIR TAG GUARDRAILS_DIR
  local p="$1" tag="$2" g="$3"
  rm -f "$WORK/stub-ran"
  ( cd "$p" && printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n' | SOIF_ADOPT_QDRANT=no SOIF_ADOPT_GUARDRAILS_DIR="$g" \
      bash "$REPO_ROOT/scripts/adopt-project.sh" ) > "$WORK/$tag.out" 2>&1
  RUN_RC=$?
}

STUB="$WORK/stub"; _stub "$STUB"
P="$WORK/p"; _base "$P"
mkdir -p "$P/.claude-backup/THEIRS"; printf 'mine\n' > "$P/.claude-backup/THEIRS/keep.txt"
_commit "$P" package.json src/index.ts .claude-backup/THEIRS/keep.txt
_adopt "$P" p "$STUB"; PRC=$RUN_RC

g1() {
  local label="G1 installed: the installer ran, its files are committed, the manifest keeps BOTH its keys and the stamp" bad=""
  [ "$PRC" -eq 0 ] || { fail_ "$label" "rc $PRC: $(grep -E 'BLOCKED|REFUSED' "$WORK/p.out" | head -1)"; return; }
  [ -f "$WORK/stub-ran" ] || bad="$bad [the installer never ran]"
  jq -e '.frameworkVersion == "9.9.9-stub" and .adoption.adopted == true and .deployment == "personal"' "$P/.claude/manifest.json" >/dev/null 2>&1 \
    || bad="$bad [the manifest lost one side: $(jq -c '{frameworkVersion, adopted: .adoption.adopted}' "$P/.claude/manifest.json" 2>/dev/null)]"
  ( cd "$P" && git ls-files --error-unmatch .claude/framework/hooks/stub-hook.sh .claude/framework/rules/stub-rule.md ) >/dev/null 2>&1 \
    || bad="$bad [the installer's files are not in the adoption commit]"
  [ -z "$(cd "$P" && git status --porcelain --untracked-files=all | grep -v '^?? .claude-backup/THEIRS')" ] || bad="$bad [files left uncommitted: $(cd "$P" && git status --porcelain | head -3 | tr '\n' ' ')]"
  grep -q 'STUB-GUARDRAILS-HOOK\|stub-hook.sh' "$P/.claude/settings.json" || bad="$bad [its hook is not in settings.json]"
  grep -q 'session-version-check.sh' "$P/.claude/settings.json" || bad="$bad [the framework's own roster is missing beside it]"
  grep -q '| Development Guardrails | installed, version 9.9.9-stub' "$P/APPROVAL_LOG.md" || bad="$bad [the Adoption Record does not say it was installed]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

g2() {
  local label="G2 the installer's own backup is removed; an operator's .claude-backup is not" bad=""
  [ ! -e "$P/.claude-backup/STUB-TS" ] || bad="$bad [the installer's backup was left behind]"
  [ -f "$P/.claude-backup/THEIRS/keep.txt" ] || bad="$bad [the operator's own backup was removed]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

g3() {
  local label="G3 a project that already has the Guardrails is left as it was" bad="" p="$WORK/already"
  _base "$p"; mkdir -p "$p/.claude/framework/hooks"; printf '# THEIRS\n' > "$p/.claude/framework/hooks/theirs.sh"
  _commit "$p" package.json src/index.ts .claude/framework/hooks/theirs.sh
  _adopt "$p" already "$STUB"
  [ "$RUN_RC" -eq 0 ] || { fail_ "$label" "rc $RUN_RC"; return; }
  [ ! -f "$WORK/stub-ran" ] || bad="$bad [the installer ran over an existing install]"
  grep -q '# THEIRS' "$p/.claude/framework/hooks/theirs.sh" || bad="$bad [their install was changed]"
  grep -q 'already has the Guardrails' "$WORK/already.out" || bad="$bad [the run did not say so]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

g4() {
  local label="G4 no clone: adoption completes, says NOT INSTALLED with the commands, and the Record says so" bad="" p="$WORK/none"
  _base "$p"; _commit "$p" package.json src/index.ts
  _adopt "$p" none "$WORK/no-such-clone"
  [ "$RUN_RC" -eq 0 ] || { fail_ "$label" "rc $RUN_RC"; return; }
  grep -q 'NOT INSTALLED: there is no clone' "$WORK/none.out" || bad="$bad [the run did not say so]"
  grep -qF 'git clone https://github.com/kraulerson/claude-dev-framework.git ~/.claude-dev-framework' "$WORK/none.out" || bad="$bad [the clone command is not printed]"
  grep -q '| Development Guardrails | not installed' "$p/APPROVAL_LOG.md" || bad="$bad [the Record does not say it was not installed]"
  [ ! -e "$p/.claude/framework" ] || bad="$bad [something was installed anyway]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

g5() {
  local label="G5 an installer that fails blocks the adoption before any write" bad="" p="$WORK/fails" f="$WORK/stub-fail" before
  _stub "$f" fail
  _base "$p"; _commit "$p" package.json src/index.ts
  before="$(cd "$p" && git rev-parse HEAD)"
  _adopt "$p" fails "$f"
  [ "$RUN_RC" -ne 0 ] || bad="$bad [rc 0 with a failing installer]"
  grep -q 'Guardrails installer did not complete' "$WORK/fails.out" || bad="$bad [the block does not name the installer]"
  [ "$(cd "$p" && git rev-parse HEAD)" = "$before" ] || bad="$bad [a commit landed]"
  [ -z "$(cd "$p" && git status --porcelain)" ] || bad="$bad [files were written]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

g6() {
  local label="G6 the REAL installer, on a host that has it" p="$WORK/real" real="$HOME/.claude-dev-framework" bad=""
  [ -d "$real/.git" ] && [ -f "$real/scripts/init.sh" ] || { skip "$label" "no clone at ~/.claude-dev-framework on this host"; return; }
  _base "$p"; _commit "$p" package.json src/index.ts
  _adopt "$p" real "$real"
  [ "$RUN_RC" -eq 0 ] || { fail_ "$label" "rc $RUN_RC: $(grep -E 'BLOCKED|REFUSED' "$WORK/real.out" | head -1)"; return; }
  jq -e '(.frameworkVersion | type) == "string" and .adoption.adopted == true' "$p/.claude/manifest.json" >/dev/null 2>&1 || bad="$bad [the manifest lost one side]"
  [ "$(cd "$p" && git ls-files .claude/framework | grep -c .)" -gt 5 ] || bad="$bad [the installer's files are not committed]"
  [ ! -e "$p/.claude-backup" ] || bad="$bad [the installer's backup was left]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

g7() {
  local label="G7 a project the installer cannot classify still gets the Guardrails (--profile web-api)" bad="" p="$WORK/nosig"
  mkdir -p "$p" && ( cd "$p" && git init -q . && git config user.email bl296@test.invalid && git config user.name "BL296 Test" ) >/dev/null 2>&1
  printf '[project]\nname = "acme"\n' > "$p/pyproject.toml"; printf 'x = 1\n' > "$p/acme.py"
  _commit "$p" pyproject.toml acme.py
  rm -f "$WORK/stub-profile"
  _adopt "$p" nosig "$STUB"
  [ "$RUN_RC" -eq 0 ] || { fail_ "$label" "rc $RUN_RC: $(grep -E 'BLOCKED|REFUSED' "$WORK/nosig.out" | head -1)"; return; }
  [ "$(cat "$WORK/stub-profile" 2>/dev/null)" = "web-api" ] || bad="$bad [installer profile: '$(cat "$WORK/stub-profile" 2>/dev/null)']"
  grep -q 'could not tell this project' "$WORK/nosig.out" || bad="$bad [the fallback was not said]"
  grep -q '| Development Guardrails | installed, version 9.9.9-stub, profile web-api' "$p/APPROVAL_LOG.md" || bad="$bad [the Record does not say installed]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

_their_settings() {  # a project with its own settings.json hook
  local p="$1"; _base "$p"; mkdir -p "$p/.claude"
  printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo THEIR-OWN-HOOK"}]}]}}\n' > "$p/.claude/settings.json"
  _commit "$p" package.json src/index.ts .claude/settings.json
}
g8() {
  local label="G8 the operator's own settings.json hooks survive an installer that replaces .hooks" bad="" p="$WORK/theirhooks"
  _their_settings "$p"
  _adopt "$p" theirhooks "$STUB"
  [ "$RUN_RC" -eq 0 ] || { fail_ "$label" "rc $RUN_RC: $(grep -E 'BLOCKED|REFUSED' "$WORK/theirhooks.out" | head -1)"; return; }
  grep -q 'THEIR-OWN-HOOK' "$p/.claude/settings.json" || bad="$bad [their hook is gone from the live file]"
  grep -q 'stub-hook.sh' "$p/.claude/settings.json" || bad="$bad [the Guardrails' hook is not registered]"
  jq -e '[.hooks.PreToolUse[]?.hooks[]?.command] | index("echo THEIR-OWN-HOOK") != null' "$p/.claude/settings.json" >/dev/null 2>&1 || bad="$bad [their hook moved out of PreToolUse]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
g9() {
  local label="G9 a settings.json that is not plain JSON is restored byte for byte, and the run says so" bad="" p="$WORK/jsonc"
  _base "$p"; mkdir -p "$p/.claude"
  printf '// their comment\n{"hooks":{"PreToolUse":[]}}\n' > "$p/.claude/settings.json"
  cp "$p/.claude/settings.json" "$WORK/jsonc.orig"
  _commit "$p" package.json src/index.ts .claude/settings.json
  _adopt "$p" jsonc "$STUB"
  [ "$RUN_RC" -eq 0 ] || { fail_ "$label" "rc $RUN_RC: $(grep -E 'BLOCKED|REFUSED' "$WORK/jsonc.out" | head -1)"; return; }
  cmp -s "$WORK/jsonc.orig" "$p/.claude/settings.json" || bad="$bad [their settings.json was changed]"
  grep -q "Guardrails' hooks are NOT registered" "$WORK/jsonc.out" || bad="$bad [the run did not say the hooks are not registered]"
  grep -q '| Development Guardrails | installed.*hooks not registered' "$p/APPROVAL_LOG.md" || bad="$bad [the Record does not say so]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}
g10() {
  local label="G10 an operator's .claude/project file the installer never touches is not claimed as its write" bad="" p="$WORK/theirproj"
  _base "$p"; mkdir -p "$p/.claude/project"; printf '# THEIR NOTES\n' > "$p/.claude/project/notes.md"
  _commit "$p" package.json src/index.ts .claude/project/notes.md
  _adopt "$p" theirproj "$STUB"
  [ "$RUN_RC" -eq 0 ] || { fail_ "$label" "rc $RUN_RC: $(grep -E 'BLOCKED|REFUSED' "$WORK/theirproj.out" | head -1)"; return; }
  grep -q '# THEIR NOTES' "$p/.claude/project/notes.md" || bad="$bad [their file changed]"
  [ -z "$bad" ] && pass "$label" || fail_ "$label" "$bad"
}

g1; g2; g3; g4; g5; g6; g7; g8; g9; g10
echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
