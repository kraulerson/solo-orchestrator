#!/usr/bin/env bash
# tests/test-bl318-g5-guardrails-refresh.sh — `## BL-318:` G5.
#
# THE DEFECT (dogfood run 2, stage 1). The adoptee carried Development
# Guardrails 4.3.0 while the clone on the same machine was newer, and nothing
# ever said so. `check-versions.sh` treats the clone as a `git_repo` tool: it
# reports whether the CLONE is behind its remote (`# BL-234-CHECKVERSIONS-*`),
# and never compares the PROJECT's installed copy (`.claude/manifest.json` ->
# `frameworkVersion`) with the clone's `FRAMEWORK_VERSION`.
#
# THE FIX (Karl, 2026-10-05: ask first, at EVERY session start, and leave
# `.claude/settings.json` alone):
#   - check-versions.sh gains a project row (`# BL-318-G5-*`): installed vs
#     clone, numeric MAJOR.MINOR.PATCH. Behind -> a [WARN] and the update
#     command under "Update commands". Equal or ahead -> no warning. Anything
#     it cannot read -> "cannot tell", never silence and never "up to date".
#     Only in a project that has `.claude/framework/`.
#   - session-version-check.sh turns that row into an offer the agent relays
#     and must not act on itself (the update replaces the Guardrails that check
#     the agent's work; config-guard does NOT stop the agent running it — it
#     blocks direct edits only), so the human types the command after `!`. Its
#     words are checked against
#     scripts/lib/bypass-patterns.sh the way `# BL-311-ASSESSMENT-AUTO-MODE`'s
#     are (tests/test-bl311-e-clone-path.sh C8).
#   - scripts/refresh-guardrails.sh, shipped to every project, runs ONLY the
#     Guardrails refresh. `upgrade-project.sh --sync-framework` run the same
#     way (no TTY) does apply the refresh, and also re-syncs ~70 vendored
#     scripts, the skills, .gitignore and the Solo pin: 85 paths where the
#     update needs a handful. Measured; recorded on `## BL-318:`.
#
# CASES
#   G  check-versions.sh's row, one fixture project per state
#   S  session-version-check.sh's offer, and its words against the detector
#   E  scripts/refresh-guardrails.sh: end to end against the real upstream
#      refresh (SKIPPED with a reason where no clone supplies it — CI has none),
#      and its own guards against stub upstreams, which run everywhere
#   M  mutants: each rewrites ONE marked line in a mirror of the tree, checks
#      the edit landed by its literal text and still parses, and needs a named
#      case to go RED
#
# Hermetic: temp dirs, a fake HOME holding a fake clone with no remote (the
# refresh's `git pull --ff-only` fails at once and it proceeds from the working
# tree, which is its documented contract), stub `brew` and `curl` that fail so
# check-versions.sh sees no network. No init.sh, not an aggregator -> both
# lists. bash 3.2 safe.
set -uo pipefail
unset GITHUB_BASE_REF CDF_HOME 2>/dev/null || true

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0; FAILED=0; SKIPPED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }
skip()  { echo "  [SKIP] $1 — $2"; SKIPPED=$((SKIPPED + 1)); }

for t in jq git; do
  command -v "$t" >/dev/null 2>&1 || { skip "every case" "$t is not on PATH"; echo; echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"; exit 0; }
done

# The real upstream refresh, read BEFORE any case fakes HOME.
UPSTREAM_SRC="${CDF_REFRESH_SRC:-$HOME/.claude-dev-framework/scripts/cdf-refresh.sh}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bl318g5.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
newtmp() { mktemp -d "$WORK/tXXXXXX"; }

STUB="$WORK/stub-bin"
mkdir -p "$STUB"
for t in brew curl; do printf '#!/bin/sh\nexit 1\n' > "$STUB/$t"; chmod +x "$STUB/$t"; done

GR='Development Guardrails in this project'
REFRESH_CMD='bash scripts/refresh-guardrails.sh'
CASE_DETAIL=""

# count_x TEXT LINE — how many lines of TEXT are exactly LINE (grep -c reads to
# EOF, so no SIGPIPE under pipefail: #435).
count_x() { printf '%s\n' "$1" | command grep -cxF -- "$2"; }
# count_f TEXT STRING — how many lines of TEXT contain STRING.
count_f() { printf '%s\n' "$1" | command grep -cF -- "$2"; }
has_x() { [ "$(count_x "$1" "$2")" -ge 1 ]; }
has_f() { [ "$(count_f "$1" "$2")" -ge 1 ]; }
last3() { printf '%s\n' "$1" | tail -3 | tr '\n' '|'; }

# mk_clone DIR VERSION [UPSTREAM] — a Guardrails clone: FRAMEWORK_VERSION, a
# hook the project has, a hook it does not (a new file takes its mode from the
# source, which is 644 here, so only the refresh's chmod makes it runnable), a
# data file, a rule, a gate, its own history and NO remote.
mk_clone() {
  local d="$1" v="$2" up="${3:-}"
  mkdir -p "$d/hooks" "$d/rules" "$d/gates" "$d/scripts" || return 1
  printf '%s\n' "$v" > "$d/FRAMEWORK_VERSION"
  printf '#!/usr/bin/env bash\necho HOOK-%s\n' "$v" > "$d/hooks/config-guard.sh"
  printf '#!/usr/bin/env bash\necho NEWHOOK-%s\n' "$v" > "$d/hooks/marker-guard.sh"
  printf 'stdlib-%s\n' "$v" > "$d/hooks/known-stdlib.txt"
  printf '# rule %s\n' "$v" > "$d/rules/plan-before-code.md"
  printf '#!/usr/bin/env bash\necho GATE-%s\n' "$v" > "$d/gates/visual-auditor.sh"
  if [ -n "$up" ]; then cp "$up" "$d/scripts/cdf-refresh.sh" || return 1; fi
  ( cd "$d" && git init -q && git config user.email t@t.local && git config user.name T \
      && git add -A && git commit -q -m "clone $v" ) >/dev/null 2>&1
}

# mk_proj DIR MANIFEST — a Guardrails project: an OLD hook, rule and gate in
# .claude/framework/; the manifest text given (NONE writes none); a settings.json
# registering the hook the way the Guardrails installer does; a one-row tool
# matrix whose row is always current, so every warning is this entry's; and its
# own history, so a case can list exactly what an update touched.
mk_proj() {
  local d="$1" mf="$2"
  mkdir -p "$d/.claude/framework/hooks" "$d/.claude/framework/rules" "$d/.claude/framework/gates" \
           "$d/templates/tool-matrix" "$d/scripts" || return 1
  printf '#!/usr/bin/env bash\necho HOOK-OLD\n' > "$d/.claude/framework/hooks/config-guard.sh"
  printf '# rule old\n' > "$d/.claude/framework/rules/plan-before-code.md"
  printf '#!/usr/bin/env bash\necho GATE-OLD\n' > "$d/.claude/framework/gates/visual-auditor.sh"
  chmod +x "$d/.claude/framework/hooks/config-guard.sh" "$d/.claude/framework/gates/visual-auditor.sh"
  [ "$mf" = NONE ] || printf '%s\n' "$mf" > "$d/.claude/manifest.json"
  printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/framework/hooks/config-guard.sh"}]}]}}' \
    > "$d/.claude/settings.json"
  matrix_rows "$d" '[{"name":"Probe","category":"version_control","phase":0,"required":false,"check_command":"true","version_command":"echo 1.0.0","min_version":null,"latest_check":null}]'
  ( cd "$d" && git init -q && git config user.email t@t.local && git config user.name T \
      && git add -A && git commit -q -m init ) >/dev/null 2>&1
}
# matrix_rows DIR JSON-ARRAY — the project's tool matrix holds exactly these rows.
matrix_rows() {
  jq -n --argjson t "$2" '{description:"fixture", schema_version:1, scope:"common", tools:$t}' \
    > "$1/templates/tool-matrix/common.json"
}
mf() { printf '{"frameworkVersion":"%s","frameworkCommit":"0396a1a","host":"github"}' "$1"; }

# pair INSTALLED CLONE — a fresh HOME holding a clone at CLONE and a project at
# INSTALLED. Sets H and P.
H=""; P=""
pair() {
  local t; t="$(newtmp)"; H="$t/home"; P="$t/proj"
  mk_clone "$H/.claude-dev-framework" "$2" && mk_proj "$P" "$(mf "$1")"
}

# cv / sv ROOT — ROOT's check-versions.sh / session-version-check.sh, run where
# the SessionStart hook runs them: in the project, no TTY.
cv() { ( cd "$P" && HOME="$H" PATH="$STUB:$PATH" bash "$1/scripts/check-versions.sh" </dev/null 2>&1 ); }
sv() { ( cd "$P" && HOME="$H" PATH="$STUB:$PATH" bash "$1/scripts/session-version-check.sh" </dev/null 2>&1 ); }

# below LIST-HEADING LINE TEXT — LINE appears after LIST-HEADING in TEXT.
below() {
  printf '%s\n' "$3" | HEAD_="$1" LINE_="$2" awk '
    $0 == ENVIRON["HEAD_"] { on = 1; next } on && $0 == ENVIRON["LINE_"] { f = 1 } END { exit !f }'
}

# no_offer TEXT — TEXT carries no Guardrails warning that offers an update and
# no update command.
no_offer() {
  local out="$1"
  if has_f "$out" "[WARN] $GR: "; then CASE_DETAIL="a Guardrails warning: $(printf '%s\n' "$out" | command grep -F "[WARN] $GR")"; return 1; fi
  if has_f "$out" "$REFRESH_CMD"; then CASE_DETAIL="the update command is offered"; return 1; fi
  return 0
}

# cannot_tell ROOT REASON — the row says "cannot tell" with exactly REASON,
# offers nothing, and claims no currency.
cannot_tell() {
  local out want
  out="$(cv "$1")"
  want="[WARN] $GR: cannot tell whether an update is available — $2"
  has_x "$out" "$want" || { CASE_DETAIL="no line '$want'; got: $(printf '%s\n' "$out" | command grep -F "$GR" | tr '\n' '|')"; return 1; }
  has_f "$out" "$REFRESH_CMD" && { CASE_DETAIL="an update command is offered on a version it cannot read"; return 1; }
  has_f "$out" "[OK] $GR" && { CASE_DETAIL="an [OK] Guardrails row beside 'cannot tell'"; return 1; }
  return 0
}

# ── G: check-versions.sh's row ───────────────────────────────────────────────
case_G1() {   # behind
  local out rc=0
  pair 4.3.0 4.3.7 || { CASE_DETAIL="fixture"; return 1; }
  out="$(cv "$1")" || rc=$?
  has_x "$out" "[WARN] $GR: 4.3.0 installed, 4.3.7 available" || { CASE_DETAIL="no behind row; tail: $(last3 "$out")"; return 1; }
  below "Update commands (run manually):" "  $GR: $REFRESH_CMD" "$out" || { CASE_DETAIL="the update command is not under 'Update commands (run manually):'"; return 1; }
  [ "$rc" -eq 0 ] || { CASE_DETAIL="rc=$rc: an available update is not a failed check"; return 1; }
}
case_G2() {   # equal
  local out
  pair 4.3.7 4.3.7 || { CASE_DETAIL="fixture"; return 1; }
  out="$(cv "$1")"
  no_offer "$out" || return 1
  has_x "$out" "  [OK] $GR: 4.3.7 — up to date" || { CASE_DETAIL="no up-to-date row"; return 1; }
}
case_G3() {   # ahead
  local out
  pair 4.3.8 4.3.7 || { CASE_DETAIL="fixture"; return 1; }
  out="$(cv "$1")"
  no_offer "$out" || return 1
  has_x "$out" "  [OK] $GR: 4.3.8 — newer than the clone's 4.3.7; nothing to update" || { CASE_DETAIL="no ahead row"; return 1; }
}
case_G4() {   # the key is missing
  pair 4.3.0 4.3.7 || { CASE_DETAIL="fixture"; return 1; }
  printf '%s\n' '{"frameworkCommit":"0396a1a","host":"github"}' > "$P/.claude/manifest.json"
  cannot_tell "$1" ".claude/manifest.json records no frameworkVersion"
}
case_G5() {   # no manifest
  pair 4.3.0 4.3.7 || { CASE_DETAIL="fixture"; return 1; }
  rm -f "$P/.claude/manifest.json"
  cannot_tell "$1" "this project has no .claude/manifest.json, so its installed version is unknown"
}
case_G6() {   # the manifest is not JSON
  pair 4.3.0 4.3.7 || { CASE_DETAIL="fixture"; return 1; }
  printf '%s\n' '{"frameworkVersion": "4.3.0",' > "$P/.claude/manifest.json"
  cannot_tell "$1" ".claude/manifest.json is not a JSON object"
}
case_G7() {   # the installed version is not MAJOR.MINOR.PATCH
  local v
  for v in 4.3 abc v4.3.0 4.3.0-rc1 '4.3.0 ' 1234567890.0.0; do
    pair 4.3.0 4.3.7 || { CASE_DETAIL="fixture"; return 1; }
    jq --arg v "$v" '.frameworkVersion = $v' "$P/.claude/manifest.json" > "$P/m" && mv "$P/m" "$P/.claude/manifest.json"
    cannot_tell "$1" ".claude/manifest.json records frameworkVersion '$v', which is not a MAJOR.MINOR.PATCH version" \
      || { CASE_DETAIL="'$v': $CASE_DETAIL"; return 1; }
  done
}
case_G8() {   # the clone's version is not MAJOR.MINOR.PATCH
  pair 4.3.0 four || { CASE_DETAIL="fixture"; return 1; }
  cannot_tell "$1" "the clone's FRAMEWORK_VERSION at $H/.claude-dev-framework holds 'four', which is not a MAJOR.MINOR.PATCH version"
}
case_G9() {   # no clone
  pair 4.3.0 4.3.7 || { CASE_DETAIL="fixture"; return 1; }
  rm -rf "$H/.claude-dev-framework"
  cannot_tell "$1" "no Guardrails clone with a FRAMEWORK_VERSION at $H/.claude-dev-framework to compare against"
}
case_G10() {  # not a Guardrails project: no row, and the session hook stays silent
  local out sout
  pair 4.3.0 4.3.7 || { CASE_DETAIL="fixture"; return 1; }
  rm -rf "$P/.claude/framework"
  out="$(cv "$1")"
  has_f "$out" "$GR" && { CASE_DETAIL="a Guardrails row in a project without .claude/framework/: $(printf '%s\n' "$out" | command grep -F "$GR" | head -1)"; return 1; }
  sout="$(sv "$1")"
  [ -z "$sout" ] || { CASE_DETAIL="the session hook spoke: $(last3 "$sout")"; return 1; }
}
case_G11() {  # numeric, part by part — multi-digit parts
  local row inst cl want out
  for row in 4.9.9:4.10.0:behind 4.10.0:4.9.9:no 9.99.99:10.0.0:behind 10.0.0:9.99.99:no \
             4.3.9:4.3.10:behind 4.3.10:4.3.9:no 0.0.9:0.0.10:behind; do
    inst="${row%%:*}"; cl="${row#*:}"; want="${cl#*:}"; cl="${cl%%:*}"
    pair "$inst" "$cl" || { CASE_DETAIL="fixture"; return 1; }
    out="$(cv "$1")"
    if [ "$want" = behind ]; then
      has_x "$out" "[WARN] $GR: $inst installed, $cl available" || { CASE_DETAIL="$inst vs $cl is not reported behind"; return 1; }
    else
      no_offer "$out" || { CASE_DETAIL="$inst vs $cl: $CASE_DETAIL"; return 1; }
    fi
  done
}
case_G12() {  # CDF_HOME names the clone, as it does for the refresh
  local out t
  pair 4.3.0 4.3.7 || { CASE_DETAIL="fixture"; return 1; }
  t="$(newtmp)"; mv "$H/.claude-dev-framework" "$t/elsewhere"
  out="$( cd "$P" && CDF_HOME="$t/elsewhere" HOME="$H" PATH="$STUB:$PATH" bash "$1/scripts/check-versions.sh" </dev/null 2>&1 )"
  has_x "$out" "[WARN] $GR: 4.3.0 installed, 4.3.7 available" || { CASE_DETAIL="the clone CDF_HOME names is not read: $(printf '%s\n' "$out" | command grep -F "$GR" | head -1)"; return 1; }
}
case_G13() {  # a manifest value cannot forge a report row
  local out v
  for v in '4.3.0\n  [OK] Forged: 9.9.9' "$(printf '4.3.0\n  [OK] Forged: 9.9.9')"; do
    pair 4.3.0 4.3.7 || { CASE_DETAIL="fixture"; return 1; }
    jq --arg v "$v" '.frameworkVersion = $v' "$P/.claude/manifest.json" > "$P/m" && mv "$P/m" "$P/.claude/manifest.json"
    out="$(cv "$1")"
    if printf '%s\n' "$out" | command grep -E '^[[:space:]]*\[OK\] Forged' >/dev/null; then
      CASE_DETAIL="a forged row: $(printf '%s\n' "$out" | command grep -F 'Forged' | head -1)"; return 1
    fi
    has_f "$out" "[WARN] $GR: cannot tell whether an update is available" || { CASE_DETAIL="no 'cannot tell' row for a forged value"; return 1; }
  done
}

# ── S: the session-start offer ───────────────────────────────────────────────
OFFER_HEAD='GUARDRAILS UPDATE OFFER'
case_S1() {
  local out want
  pair 4.3.0 4.3.7 || { CASE_DETAIL="fixture"; return 1; }
  out="$(sv "$1")"
  for want in "$OFFER_HEAD" \
              "  $GR: 4.3.0 installed, 4.3.7 available" \
              "into .claude/framework/" \
              "records the new version in .claude/manifest.json" \
              "It does not change .claude/settings.json." \
              "Do NOT run the update yourself" \
              "it replaces the Guardrails that check your own work, so starting it is the Orchestrator's decision" \
              "type ! and then this exact command at the Claude Code prompt" \
              "every session start until the update is done" \
              "no restart is needed for the new hooks"; do
    has_f "$out" "$want" || { CASE_DETAIL="the offer does not say: $want"; return 1; }
  done
  has_x "$out" "  $REFRESH_CMD" || { CASE_DETAIL="the command is not on a line of its own"; return 1; }
  [ "$(count_f "$out" "$REFRESH_CMD")" = "1" ] || { CASE_DETAIL="the command appears $(count_f "$out" "$REFRESH_CMD") times"; return 1; }
  has_f "$out" "Would you like me to run these updates now" && { CASE_DETAIL="the agent is told to offer to run the update itself"; return 1; }
  return 0
}
case_S2() {   # current: silent
  local out
  pair 4.3.7 4.3.7 || { CASE_DETAIL="fixture"; return 1; }
  out="$(sv "$1")"
  [ -z "$out" ] || { CASE_DETAIL="spoke: $(last3 "$out")"; return 1; }
}
# offer_para TEXT — the offer, from its head line to the end.
offer_para() { printf '%s\n' "$1" | awk -v h="$OFFER_HEAD" 'index($0, h) == 1 { on = 1 } on { print }'; }
case_S3() {   # the detector finds nothing in the offer, or in a relay of it
  local out para joined relay word hit=""
  pair 4.3.0 4.3.7 || { CASE_DETAIL="fixture"; return 1; }
  out="$(sv "$1")"
  para="$(offer_para "$out")"
  [ -n "$para" ] || { CASE_DETAIL="no offer to check"; return 1; }
  word="$(printf '%s\n' "$para" | command grep -oiE 'terminal|shell' | head -1)"
  [ -z "$word" ] || { CASE_DETAIL="the offer names a '$word' route; a relay of it in other words can match terminal_workaround"; return 1; }
  joined="$(printf '%s\n' "$para" | tr '\n' ' ' | tr -s ' ')"
  relay="Your project's Development Guardrails are 4.3.0 and 4.3.7 is available. I won't run the update myself: it replaces the Guardrails that check my own work, so it is your call. To update, type ! and then \`bash scripts/refresh-guardrails.sh\` at the Claude Code prompt; it does not change .claude/settings.json. Or skip it and I will carry on."
  hit="$( ( . "$1/scripts/lib/bypass-patterns.sh"
            while IFS= read -r l; do scan_bypass_patterns_all "$l" | sed 's/$/ (a line)/'; done <<< "$para"
            scan_bypass_patterns_all "$joined" | sed 's/$/ (the offer as one line)/'
            scan_bypass_patterns_all "$relay" | sed 's/$/ (a relay)/'
          ) 2>/dev/null | tr '\n' ';')"
  [ -z "$hit" ] || { CASE_DETAIL="the bypass detector flags it: $hit"; return 1; }
}
case_S4() {   # beside other warnings: the update is never in the list the agent may run
  local out
  pair 4.3.0 4.3.7 || { CASE_DETAIL="fixture"; return 1; }
  matrix_rows "$P" '[{"name":"Probe","category":"version_control","phase":0,"check_command":"true","version_command":"echo 1.0.0"},
                     {"name":"Ghost","category":"version_control","phase":0,"check_command":"false","version_command":"echo 1.0.0"}]'
  out="$(sv "$1")"
  has_f "$out" "VERSION CHECK: Report" && has_f "$out" "[WARN] Ghost: not installed" \
    || { CASE_DETAIL="the other warning is not reported: $(last3 "$out")"; return 1; }
  has_f "$out" "$OFFER_HEAD" || { CASE_DETAIL="no offer beside another warning"; return 1; }
  [ "$(count_f "$out" "$REFRESH_CMD")" = "1" ] || { CASE_DETAIL="the command appears $(count_f "$out" "$REFRESH_CMD") times (it is in the generic list)"; return 1; }
  has_f "$out" "[WARN] $GR: 4.3.0" && { CASE_DETAIL="the Guardrails row is listed among the warnings the agent offers to update itself"; return 1; }
  # Below a minimum: the URGENT text, its own command intact, the offer apart.
  matrix_rows "$P" '[{"name":"Old","category":"version_control","phase":0,"check_command":"true","version_command":"echo 0.1.0","min_version":"1.0.0","update_check":null,"install":{"manual":"echo upgrade-old"}}]'
  out="$(sv "$1")"
  has_f "$out" "URGENT" && has_x "$out" "  Old: echo upgrade-old" || { CASE_DETAIL="the urgent block lost its own command: $(last3 "$out")"; return 1; }
  has_f "$out" "$OFFER_HEAD" || { CASE_DETAIL="no offer beside an urgent block"; return 1; }
  [ "$(count_f "$out" "$REFRESH_CMD")" = "1" ] || { CASE_DETAIL="urgent: the command appears $(count_f "$out" "$REFRESH_CMD") times"; return 1; }
}
case_S5() {   # cannot tell: reported, not silent
  local out
  pair 4.3.0 4.3.7 || { CASE_DETAIL="fixture"; return 1; }
  rm -rf "$H/.claude-dev-framework"
  out="$(sv "$1")"
  has_f "$out" "[WARN] $GR: cannot tell whether an update is available" || { CASE_DETAIL="not reported: $(last3 "$out")"; return 1; }
  has_f "$out" "$OFFER_HEAD" && { CASE_DETAIL="an update is offered on a version it cannot read"; return 1; }
  return 0
}

# ── E: scripts/refresh-guardrails.sh ─────────────────────────────────────────
# Stub upstreams, so the script's own guards run where no real clone exists.
STUBS="$WORK/upstreams"; mkdir -p "$STUBS"
cat > "$STUBS/good.sh" <<'UP'
refresh_cdf_assets() {
  local p="$1" c="$2" f sub v
  for f in "$c"/hooks/*.sh "$c"/hooks/*.txt "$c"/rules/*.md "$c"/gates/*.sh; do
    [ -f "$f" ] || continue
    sub="${f%/*}"; sub="${sub##*/}"
    mkdir -p "$p/.claude/framework/$sub" && cp "$f" "$p/.claude/framework/$sub/"
  done
  [ "${STUB_NOCHMOD:-}" = 1 ] || chmod +x "$p"/.claude/framework/hooks/*.sh "$p"/.claude/framework/gates/*.sh 2>/dev/null
  v="$(tr -d '[:space:]' < "$c/FRAMEWORK_VERSION")"
  if [ -f "$p/.claude/manifest.json" ]; then
    jq --arg v "$v" '.frameworkVersion = $v' "$p/.claude/manifest.json" > "$p/.claude/m.tmp" && mv "$p/.claude/m.tmp" "$p/.claude/manifest.json"
  fi
  return "${STUB_RC:-0}"
}
UP
cat > "$STUBS/liar.sh" <<'UP'
refresh_cdf_assets() {
  jq '.frameworkVersion = "4.3.7"' "$1/.claude/manifest.json" > "$1/.claude/m.tmp" && mv "$1/.claude/m.tmp" "$1/.claude/manifest.json"
  return 0
}
UP
cat > "$STUBS/lazy.sh" <<'UP'
refresh_cdf_assets() {
  local f sub
  for f in "$2"/hooks/*.sh "$2"/hooks/*.txt "$2"/rules/*.md "$2"/gates/*.sh; do
    [ -f "$f" ] || continue
    sub="${f%/*}"; sub="${sub##*/}"; cp "$f" "$1/.claude/framework/$sub/"
  done
  chmod +x "$1"/.claude/framework/hooks/*.sh "$1"/.claude/framework/gates/*.sh
  return 0
}
UP
printf '%s\n' '# defines nothing' > "$STUBS/empty.sh"

# eproj ROOT INSTALLED CLONE UPSTREAM — a project carrying ROOT's
# refresh-guardrails.sh (committed, as shipped), a clone with UPSTREAM.
eproj() {
  pair "$2" "$3" || return 1
  cp "$4" "$H/.claude-dev-framework/scripts/cdf-refresh.sh" || return 1
  cp -p "$1/scripts/refresh-guardrails.sh" "$P/scripts/refresh-guardrails.sh" || return 1
  ( cd "$P" && git add -A && git commit -q -m ship ) >/dev/null 2>&1
}
# rg [ENV=V…] — the offered command, as typed after `!`: in the project, no TTY.
RG_OUT=""; RG_RC=0
rg() {
  RG_RC=0
  RG_OUT="$( cd "$P" && env HOME="$H" PATH="$STUB:$PATH" "$@" bash scripts/refresh-guardrails.sh </dev/null 2>&1 )" || RG_RC=$?
}
same_files() {  # every file the refresh copies is byte-identical in the project
  local f sub
  for f in "$H"/.claude-dev-framework/hooks/*.sh "$H"/.claude-dev-framework/hooks/*.txt \
           "$H"/.claude-dev-framework/rules/*.md "$H"/.claude-dev-framework/gates/*.sh; do
    [ -f "$f" ] || continue
    sub="${f%/*}"; sub="${sub##*/}"
    cmp -s "$f" "$P/.claude/framework/$sub/${f##*/}" || { CASE_DETAIL="$sub/${f##*/} differs"; return 1; }
  done
}

case_E1() {   # end to end, against the real upstream refresh
  local before_settings cmd hook changed bad sout
  eproj "$1" 4.3.0 4.3.7 "$UPSTREAM_SRC" || { CASE_DETAIL="fixture"; return 1; }
  before_settings="$(cksum < "$P/.claude/settings.json")"
  rg
  [ "$RG_RC" -eq 0 ] || { CASE_DETAIL="rc=$RG_RC: $(last3 "$RG_OUT")"; return 1; }
  has_f "$RG_OUT" "[OK] $GR updated: 4.3.0 -> 4.3.7" || { CASE_DETAIL="no [OK] line: $(last3 "$RG_OUT")"; return 1; }
  has_f "$RG_OUT" ".claude/settings.json was not changed" || { CASE_DETAIL="does not say settings.json was left alone"; return 1; }
  [ "$(jq -r .frameworkVersion "$P/.claude/manifest.json")" = 4.3.7 ] || { CASE_DETAIL="manifest frameworkVersion not 4.3.7"; return 1; }
  [ "$(jq -r .frameworkCommit "$P/.claude/manifest.json")" = "$(git -C "$H/.claude-dev-framework" rev-parse HEAD)" ] \
    || { CASE_DETAIL="manifest frameworkCommit is not the clone's HEAD"; return 1; }
  same_files || return 1
  [ -x "$P/.claude/framework/hooks/config-guard.sh" ] && [ -x "$P/.claude/framework/gates/visual-auditor.sh" ] \
    || { CASE_DETAIL="a hook or gate is not executable"; return 1; }
  # The command Claude Code runs for this hook, from settings.json, as it runs it.
  cmd="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$P/.claude/settings.json")"
  hook="$( cd "$P" && CLAUDE_PROJECT_DIR="$P" sh -c "$cmd" 2>&1 )"
  [ "$hook" = "HOOK-4.3.7" ] || { CASE_DETAIL="the registered hook command ran '$hook'"; return 1; }
  [ "$(cksum < "$P/.claude/settings.json")" = "$before_settings" ] || { CASE_DETAIL="settings.json changed"; return 1; }
  changed="$(git -C "$P" status --porcelain --untracked-files=all | awk '{print $NF}')"
  [ -n "$changed" ] || { CASE_DETAIL="git status shows no change"; return 1; }
  bad="$(printf '%s\n' "$changed" | command grep -vE '^\.claude/framework/|^\.claude/manifest\.json$' | tr '\n' ' ')"
  [ -z "$bad" ] || { CASE_DETAIL="it also changed: $bad"; return 1; }
  no_offer "$(cv "$1")" || { CASE_DETAIL="after the update: $CASE_DETAIL"; return 1; }
  sout="$(sv "$1")"
  [ -z "$sout" ] || { CASE_DETAIL="after the update the session hook spoke: $(last3 "$sout")"; return 1; }
}
case_E2() {   # a project without the Guardrails (its own manifest, no .claude/framework/): refused, nothing written
  local t m
  t="$(newtmp)"; H="$t/home"; P="$t/plain"
  mk_clone "$H/.claude-dev-framework" 4.3.7 "$STUBS/good.sh" || { CASE_DETAIL="fixture"; return 1; }
  mkdir -p "$P/scripts" "$P/.claude" && cp -p "$1/scripts/refresh-guardrails.sh" "$P/scripts/"
  printf '%s\n' '{"host":"github","deployment":"personal"}' > "$P/.claude/manifest.json"
  m="$(cksum < "$P/.claude/manifest.json")"
  rg
  [ "$RG_RC" -ne 0 ] || { CASE_DETAIL="rc=0 outside a Guardrails project"; return 1; }
  has_f "$RG_OUT" "[FAIL]" && has_f "$RG_OUT" "no .claude/framework/" || { CASE_DETAIL="no refusal naming .claude/framework/: $(last3 "$RG_OUT")"; return 1; }
  [ ! -e "$P/.claude/framework" ] || { CASE_DETAIL="it installed .claude/framework/ into a project that never had the Guardrails"; return 1; }
  [ "$(cksum < "$P/.claude/manifest.json")" = "$m" ] || { CASE_DETAIL="the manifest changed"; return 1; }
}
case_E3() {   # no clone: refused, says how to get one, manifest untouched
  local m
  eproj "$1" 4.3.0 4.3.7 "$STUBS/good.sh" || { CASE_DETAIL="fixture"; return 1; }
  rm -rf "$H/.claude-dev-framework"; m="$(cksum < "$P/.claude/manifest.json")"
  rg
  [ "$RG_RC" -ne 0 ] || { CASE_DETAIL="rc=0 with no clone"; return 1; }
  has_f "$RG_OUT" "no Guardrails clone at $H/.claude-dev-framework" && has_f "$RG_OUT" "git clone https://github.com/kraulerson/claude-dev-framework.git" \
    || { CASE_DETAIL="the refusal does not name the clone and how to get it: $(last3 "$RG_OUT")"; return 1; }
  [ "$(cksum < "$P/.claude/manifest.json")" = "$m" ] || { CASE_DETAIL="the manifest changed"; return 1; }
}
case_E4() {   # an upstream that bumps the version and copies nothing is caught
  eproj "$1" 4.3.0 4.3.7 "$STUBS/liar.sh" || { CASE_DETAIL="fixture"; return 1; }
  rg
  [ "$RG_RC" -ne 0 ] || { CASE_DETAIL="rc=0 though no file was copied"; return 1; }
  has_f "$RG_OUT" "[FAIL]" && has_f "$RG_OUT" ".claude/framework/hooks/config-guard.sh" \
    || { CASE_DETAIL="the stale file is not named: $(last3 "$RG_OUT")"; return 1; }
  has_f "$RG_OUT" "[OK]" && { CASE_DETAIL="an [OK] line beside the failure"; return 1; }
  return 0
}
case_E5() {   # an upstream that copies and records no version is caught
  eproj "$1" 4.3.0 4.3.7 "$STUBS/lazy.sh" || { CASE_DETAIL="fixture"; return 1; }
  rg
  [ "$RG_RC" -ne 0 ] || { CASE_DETAIL="rc=0 though the manifest still says 4.3.0"; return 1; }
  has_f "$RG_OUT" "[FAIL]" && has_f "$RG_OUT" "frameworkVersion" || { CASE_DETAIL="the stale version is not named: $(last3 "$RG_OUT")"; return 1; }
}
case_E6() {   # an upstream that reports failure is not called a success
  eproj "$1" 4.3.0 4.3.7 "$STUBS/good.sh" || { CASE_DETAIL="fixture"; return 1; }
  rg STUB_RC=1
  [ "$RG_RC" -ne 0 ] || { CASE_DETAIL="rc=0 though the refresh returned 1"; return 1; }
  has_f "$RG_OUT" "returned 1" || { CASE_DETAIL="the refresh's own status is not reported: $(last3 "$RG_OUT")"; return 1; }
}
case_E7() {   # a hook that lands without its execute bit is caught (Claude Code runs it by path)
  eproj "$1" 4.3.0 4.3.7 "$STUBS/good.sh" || { CASE_DETAIL="fixture"; return 1; }
  rg STUB_NOCHMOD=1
  [ "$RG_RC" -ne 0 ] || { CASE_DETAIL="rc=0 with a hook Claude Code cannot run"; return 1; }
  has_f "$RG_OUT" "not executable" || { CASE_DETAIL="the hook is not named as not executable: $(last3 "$RG_OUT")"; return 1; }
}
case_E8() {   # shipped to every project: generated, adopted and synced read init.sh's cp lines
  local set
  set="$( . "$1/scripts/lib/scaffold-shipped-set.sh" && soif_parse_shipped_scripts "$1/init.sh" "$1/scripts" )"
  has_x "$set" "scripts/refresh-guardrails.sh" || { CASE_DETAIL="not in init.sh's shipped set"; return 1; }
  [ -x "$1/scripts/refresh-guardrails.sh" ] || { CASE_DETAIL="not executable (adoption copies with cp -p)"; return 1; }
}
case_E9() {   # a project with no manifest is refused before anything is written
  eproj "$1" 4.3.0 4.3.7 "$STUBS/good.sh" || { CASE_DETAIL="fixture"; return 1; }
  rm -f "$P/.claude/manifest.json"
  rg
  [ "$RG_RC" -ne 0 ] || { CASE_DETAIL="rc=0 with no manifest"; return 1; }
  [ "$(tail -1 "$P/.claude/framework/hooks/config-guard.sh")" = "echo HOOK-OLD" ] || { CASE_DETAIL="the hooks were rewritten before the refusal"; return 1; }
  has_f "$RG_OUT" "no .claude/manifest.json" || { CASE_DETAIL="the refusal does not name the manifest: $(last3 "$RG_OUT")"; return 1; }
}
case_E10() {  # an upstream that defines no refresh is named as such
  eproj "$1" 4.3.0 4.3.7 "$STUBS/empty.sh" || { CASE_DETAIL="fixture"; return 1; }
  rg
  [ "$RG_RC" -ne 0 ] || { CASE_DETAIL="rc=0"; return 1; }
  has_f "$RG_OUT" "does not define refresh_cdf_assets" || { CASE_DETAIL="not named: $(last3 "$RG_OUT")"; return 1; }
}
case_E11() {  # --help writes nothing
  eproj "$1" 4.3.0 4.3.7 "$STUBS/good.sh" || { CASE_DETAIL="fixture"; return 1; }
  RG_RC=0; RG_OUT="$( cd "$P" && HOME="$H" bash scripts/refresh-guardrails.sh --help </dev/null 2>&1 )" || RG_RC=$?
  [ "$RG_RC" -eq 0 ] && has_f "$RG_OUT" "Usage: bash scripts/refresh-guardrails.sh" || { CASE_DETAIL="rc=$RG_RC: $(last3 "$RG_OUT")"; return 1; }
  [ -z "$(git -C "$P" status --porcelain)" ] || { CASE_DETAIL="--help changed the project"; return 1; }
}

check() {
  local label="$1" fn="$2"
  CASE_DETAIL=""
  if "$fn" "$REPO_ROOT"; then pass "$label"; else fail_ "$label" "$CASE_DETAIL"; fi
}

echo "=== G — check-versions.sh: this project's Guardrails against the clone ==="
check "G1: 4.3.0 installed, 4.3.7 in the clone -> a [WARN] and the update command under 'Update commands', rc 0" case_G1
check "G2: equal -> no warning, no command, an up-to-date row" case_G2
check "G3: installed ahead of the clone -> no warning, no command" case_G3
check "G4: no frameworkVersion in the manifest -> 'cannot tell', never silence" case_G4
check "G5: no manifest -> 'cannot tell'" case_G5
check "G6: a manifest that is not JSON -> 'cannot tell'" case_G6
check "G7: an installed version that is not MAJOR.MINOR.PATCH (4.3, abc, v4.3.0, 4.3.0-rc1, a trailing space, a 10-digit part) -> 'cannot tell'" case_G7
check "G8: a clone version that is not MAJOR.MINOR.PATCH -> 'cannot tell'" case_G8
check "G9: no clone -> 'cannot tell', naming the path" case_G9
check "G10: a project without .claude/framework/ gets no row and no session-start text" case_G10
check "G11: numeric part by part — 4.9.9 < 4.10.0, 9.99.99 < 10.0.0, 4.3.9 < 4.3.10, and the reverses are not offered" case_G11
check "G12: CDF_HOME names the clone, as it does for the refresh" case_G12
check "G13: a manifest value carrying a newline or a backslash-n cannot forge an [OK] row" case_G13

echo "=== S — session-version-check.sh: the offer ==="
check "S1: the offer names both versions, what changes (not settings.json), asks for ! and forbids the agent running it; offered every session" case_S1
check "S2: current -> the session hook is silent" case_S2
check "S3: no terminal/shell route in the offer; the detector flags no line, the offer joined, or a relay of it" case_S3
check "S4: beside another warning and an URGENT block, the update is never in the list the agent may run" case_S4
check "S5: 'cannot tell' reaches the session start; nothing is offered" case_S5

echo "=== E — scripts/refresh-guardrails.sh (the command typed after !) ==="
if [ -f "$UPSTREAM_SRC" ]; then
  check "E1: end to end with the real upstream refresh, no TTY: 4.3.0 -> 4.3.7, files byte-identical, hooks executable and run as registered, only .claude/framework/ and the manifest changed, settings.json untouched, then no offer and a silent session hook" case_E1
else
  skip "E1: end to end" "the real upstream refresh is not at $UPSTREAM_SRC (set CDF_REFRESH_SRC); the E2-E11 guards run against stub upstreams"
fi
check "E2: a project with its own manifest and no .claude/framework/ -> refused, no Guardrails installed, manifest untouched" case_E2
check "E3: no clone -> refused with the clone command, manifest untouched" case_E3
check "E4: an upstream that records the version and copies nothing -> [FAIL] naming the stale file" case_E4
check "E5: an upstream that copies and records no version -> [FAIL] naming frameworkVersion" case_E5
check "E6: an upstream that returns 1 -> rc != 0, its status reported" case_E6
check "E7: a hook left without its execute bit -> [FAIL]" case_E7
check "E8: shipped — in init.sh's shipped set (generated, adopted, synced) and executable" case_E8
check "E9: no manifest -> refused before any file is rewritten" case_E9
check "E10: an upstream that defines no refresh -> named" case_E10
check "E11: --help prints usage and writes nothing" case_E11

# ── M: mutants ───────────────────────────────────────────────────────────────
mk_mirror() { mkdir -p "$2" && cp -Rp "$1/scripts" "$1/init.sh" "$2/"; }
# mutate FILE MARKER REPLACEMENT — 0 iff exactly one line ends in MARKER, it now
# reads REPLACEMENT exactly, and the file still parses.
mutate() {
  local f="$1" mark="$2" repl="$3" n=""
  [ -f "$f" ] || { echo "no such file: $f"; return 1; }
  n="$(MARK="$mark" awk 'BEGIN{c=0; m=ENVIRON["MARK"]} length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m {c++} END{print c}' "$f")"
  [ "$n" = "1" ] || { echo "marker '$mark' ends $n line(s) of $f (need 1)"; return 1; }
  MARK="$mark" REPL="$repl" awk '{ m=ENVIRON["MARK"]
      if (length($0) >= length(m) && substr($0, length($0)-length(m)+1) == m) print ENVIRON["REPL"]; else print }' \
    "$f" > "$f.mut" && cat "$f.mut" > "$f" && rm -f "$f.mut"
  command grep -qF -- "$mark" "$f" && { echo "marker still present after the edit"; return 1; }
  [ "$(command grep -cxF -- "$repl" "$f")" -ge 1 ] || { echo "replacement did not land"; return 1; }
  bash -n "$f" 2>/dev/null || { echo "mutant does not parse"; return 1; }
  return 0
}
mutant() {
  local id="$1" rel="$2" mark="$3" repl="$4" killer="$5" what="$6" m why
  m="$(newtmp)/mirror"
  mk_mirror "$REPO_ROOT" "$m" || { fail_ "$id" "could not build a mirror"; return; }
  why="$(mutate "$m/$rel" "$mark" "$repl")" || { fail_ "$id" "mutant did not land: $why"; return; }
  CASE_DETAIL=""
  if "$killer" "$m"; then
    fail_ "$id" "$what — SURVIVED: ${killer#case_} still passes against the mutant"
  else
    pass "$id (MUTATION) — $what: killed by ${killer#case_} ($CASE_DETAIL)"
  fi
}

echo "=== M — mutants ==="
CV=scripts/check-versions.sh
SV=scripts/session-version-check.sh
RGS=scripts/refresh-guardrails.sh
mutant MV1  "$CV" '# BL-318-G5-FRAMEWORK-DIR' '  :' case_G10 "every project gets the row, Guardrails or not"
mutant MV2  "$CV" '# BL-318-G5-CMP' '    if [[ "$_x" < "$_y" ]]; then echo lt; return 0; fi' case_G11 "versions compared as text: 4.10.0 reads older than 4.9.9"
mutant MV3  "$CV" '# BL-318-G5-VALID' '  return 0' case_G7 "any string is a version, so 'abc' reads as up to date"
mutant MV4  "$CV" '# BL-318-G5-NO-MANIFEST' '    return 0' case_G5 "no manifest is silence"
mutant MV5  "$CV" '# BL-318-G5-BAD-JSON' '    return 0' case_G6 "a broken manifest is silence"
mutant MV6  "$CV" '# BL-318-G5-NO-KEY' '      return 0' case_G4 "a missing frameworkVersion is silence"
mutant MV7  "$CV" '# BL-318-G5-BAD-INSTALLED' '      return 0' case_G7 "an unreadable installed version is silence"
mutant MV8  "$CV" '# BL-318-G5-NO-CLONE' '      return 0' case_G9 "a missing clone is silence"
mutant MV9  "$CV" '# BL-318-G5-BAD-CLONE' '        return 0' case_G8 "an unreadable clone version is silence"
mutant MV10 "$CV" '# BL-318-G5-OFFER' '      :' case_G1 "behind is warned with no command"
mutant MV11 "$CV" '# BL-318-G5-CALL' ':' case_G1 "the row never runs"
mutant MV12 "$CV" '# BL-318-G5-SAFE' '  printf '"'"'%s'"'"' "$1" | LC_ALL=C cut -c1-40' case_G13 "a manifest value is rendered raw and forges an [OK] row"
mutant MS1  "$SV" '# BL-318-G5-SESSION-OFFER' '  :' case_S1 "the offer is never made"
mutant MS2  "$SV" '# BL-318-G5-SESSION-DETECT' 'GR_CMD_LINE=""' case_S1 "the offer is never recognised"
mutant MS3  "$SV" '# BL-318-G5-SESSION-SPLIT' '  :' case_S4 "the update stays in the list the agent offers to run itself"
mutant MS4  "$SV" '# BL-318-G5-SESSION-WARN-SPLIT' '  :' case_S1 "the Guardrails row also lands in the generic block, whose question offers to run it"
mutant MS5  "$SV" '# BL-318-G5-SESSION-ROUTE' "  printf '%s\\n' \"Do NOT run the update yourself. Ask the Orchestrator to run it in their own terminal:\"" case_S3 "the offer names a terminal route"
mutant MR1  "$RGS" '# BL-318-G5-REFRESH-PROJECT' ':' case_E2 "a folder with no Guardrails gets .claude/framework/ written into it"
mutant MR2  "$RGS" '# BL-318-G5-REFRESH-MANIFEST' ':' case_E9 "a project with no manifest has its hooks rewritten, then fails"
mutant MR3  "$RGS" '# BL-318-G5-REFRESH-CLONE' ':' case_E3 "no clone: no word on where it should be or how to get it"
mutant MR4  "$RGS" '# BL-318-G5-REFRESH-DEFINED' ':' case_E10 "an upstream with no refresh is reported as a bare status"
mutant MR5  "$RGS" '# BL-318-G5-REFRESH-RC' ':' case_E6 "the upstream's failure is reported as success"
mutant MR6  "$RGS" '# BL-318-G5-RECEIPT-FILES' '      :' case_E4 "a stale hook beside a new version number is called updated"
mutant MR7  "$RGS" '# BL-318-G5-RECEIPT-EXEC' '      :' case_E7 "a hook Claude Code cannot run is called updated"
mutant MR8  "$RGS" '# BL-318-G5-RECEIPT-VERSION' ':' case_E5 "files copied, version not recorded, called updated"
mutant MI1  init.sh '# BL-318-G5-SHIP' '  :' case_E8 "the script is not shipped, so the offered command does not exist"

echo
echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -eq 0 ]
