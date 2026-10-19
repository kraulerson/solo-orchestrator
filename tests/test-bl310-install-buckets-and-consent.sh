#!/usr/bin/env bash
# tests/test-bl310-install-buckets-and-consent.sh
#
# `## BL-310:` rows 1 and 2, both carried from `## BL-242:`.
#
#   Row 1. scripts/resolve-tools.sh listed `manual` as its LAST install key, so
#     a matrix `manual` value counted as a found command. For gitleaks that value
#     is https://github.com/gitleaks/gitleaks/releases, and it landed in
#     `auto_install` — the bucket init.sh, upgrade-project.sh, verify-install.sh
#     and adoption execute — on any host without brew (macOS) or
#     apt/dnf/pacman (Linux).
#   Row 2. The Linux gitleaks recipe elevates and its consent never said so.
#     `## BL-316:` already replaced the unpinned `curl … | sudo tar` with
#     scripts/install-gitleaks.sh (8.30.1, a SHA-256 per arch checked before
#     extracting, `sudo install` into /usr/local/bin), and
#     tests/test-bl316-installers.sh pins that: G2 is the version/digest drift
#     check against tests.yml, G5 the unknown-arch refusal, G7 the mismatch
#     refusal. What it left is the consent: the operator is shown
#     `bash "${SOLO_SCRIPTS_DIR:-scripts}/install-gitleaks.sh"`, and nothing in
#     that string says sudo.
#
#   R  the REAL resolver over a copy of the REAL matrix in which only
#      `check_command` is replaced by `false` — every tool is absent on every
#      host, and every install object is byte-identical. auto_install holds
#      exactly the tools with a package-manager recipe for the host; a `manual`
#      value is only ever instructions.
#   I  init.sh's resolve_and_install_tools never evals the gitleaks URL.
#   K  the consent text init and adoption show before the Linux recipe names
#      sudo and /usr/local/bin, and brew's does not; every other recipe that
#      runs sudo (Docker's `sudo apt install …`) says so in init's plan too.
#   C  check-versions.sh, the one other reader of `.install.manual`: on a host
#      without brew it offered that value as the update command and its
#      interactive "update all" ran it with `eval`. Driven over a pty
#      (script(1)), with curl stubbed and no brew on PATH.
#   M  every BL-310 marker is mutation-proven against a mirror; the tree under
#      test is never edited, and each mutant asserts it LANDED by literal text.
#
# Hermetic: nothing is downloaded or installed. brew/apt/dnf/npm/curl/sudo are
# stubs, and the resolver runs on a PATH that holds only the tools it needs,
# so a runner's real apt cannot decide a case.
set -uo pipefail
export SOIF_ADOPT_MCP=off   # `# BL-311-MCP-SEAM`: adoption's MCP step is not under test here

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
pass()  { echo "  [PASS] $1"; PASSED=$((PASSED + 1)); }
fail_() { echo "  [FAIL] $1 — $2"; FAILED=$((FAILED + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "  [FAIL] setup — jq is required"; echo ""; echo "Results: 0 passed, 1 failed"; exit 1
fi

TOPTMP="$(mktemp -d)"
trap 'rm -rf "$TOPTMP"' EXIT INT TERM
newtmp() { mktemp -d "$TOPTMP/fixXXXXXX"; }

GL_URL='https://github.com/gitleaks/gitleaks/releases'
GL_LINUX='bash "${SOLO_SCRIPTS_DIR:-scripts}/install-gitleaks.sh"'
GL_BREW='brew install gitleaks'
SUDO_NOTE='this will run sudo to install gitleaks into /usr/local/bin'
SUDO_WORD='this will run sudo'

# ── An isolated PATH for the resolver and init's install function: each tool
# they call, linked in by itself, and nothing else — no package manager.
ISO="$TOPTMP/iso"; mkdir -p "$ISO"
for t in bash jq base64 tr mktemp cat rm date sleep seq dirname env sed awk; do
  p="$(command -v "$t" 2>/dev/null)" || { echo "  [FAIL] setup — '$t' not found"; echo ""; echo "Results: 0 passed, 1 failed"; exit 1; }
  ln -s "$p" "$ISO/$t"
done

# ── Package-manager stubs, one directory per host profile. Each logs and exits 0.
mk_stub() { printf '#!/bin/sh\necho "%s $*" >> "${STUB_LOG:-/dev/null}"\nexit 0\n' "$2" > "$1/$2"; chmod +x "$1/$2"; }
PROFILES="darwin-brew-npm darwin-none linux-apt-npm linux-dnf linux-none"
for prof in $PROFILES; do mkdir -p "$TOPTMP/pm/$prof"; done
mk_stub "$TOPTMP/pm/darwin-brew-npm" brew; mk_stub "$TOPTMP/pm/darwin-brew-npm" npm
mk_stub "$TOPTMP/pm/linux-apt-npm" apt;    mk_stub "$TOPTMP/pm/linux-apt-npm" npm
mk_stub "$TOPTMP/pm/linux-dnf" dnf
# prof_os <profile> / prof_keys <profile> — the dev OS, and the install keys the
# resolver may take a RECIPE from with exactly those package managers present.
prof_os() { printf '%s\n' "${1%%-*}"; }
prof_keys() {
  case "$1" in
    darwin-brew-npm) echo '["darwin_brew","darwin_manual","npm"]' ;;
    darwin-none)     echo '["darwin_manual"]' ;;
    linux-apt-npm)   echo '["linux_apt","linux_pip","linux_manual","npm"]' ;;
    linux-dnf)       echo '["linux_dnf","linux_pip","linux_manual"]' ;;
    linux-none)      echo '["linux_pip","linux_manual"]' ;;
  esac
}

# ── The matrix under test, with every check_command replaced by `false`.
# absent_matrix <root> <dest> <gitleaks-only|gitleaks-docker|sweep>
#   sweep also widens `languages` and `platforms` to "all", so one resolver run
#   per platform file sees every tool in it instead of one language's share.
#   Install objects, dev_os, tracks and phases are untouched.
absent_matrix() {
  local root="$1" dest="$2" mode="$3" f want=1
  mkdir -p "$dest" || return 1
  if [ "$mode" = "gitleaks-only" ] || [ "$mode" = "gitleaks-docker" ]; then
    [ "$mode" = "gitleaks-docker" ] && want=2
    jq --arg m "$mode" '{tools: [.tools[] | select(.name == "gitleaks" or ($m == "gitleaks-docker" and .name == "Docker"))
                                | .check_command = "false"]}' \
      "$root/templates/tool-matrix/common.json" > "$dest/common.json" || return 1
    [ "$(jq '.tools | length' "$dest/common.json")" = "$want" ] || return 1
    return 0
  fi
  for f in "$root"/templates/tool-matrix/*.json; do
    jq '.tools |= map(.check_command = "false" | .languages = ["all"] | .platforms = ["all"])' \
      "$f" > "$dest/${f##*/}" || return 1
  done
  [ -s "$dest/common.json" ]
}

# resolve <root> <profile> <matrix-dir> <platform> <language> — the REAL
# resolver from <root>; prints its JSON, or nothing if it failed.
resolve() {
  env -i HOME="$TOPTMP" PATH="$TOPTMP/pm/$2:$ISO" RESOLVE_TOOLS_EVAL_TIMEOUT=5 \
    bash "$1/scripts/resolve-tools.sh" --dev-os "$(prof_os "$2")" --platform "$4" \
      --language "$5" --track full --phase 4 --matrix-dir "$3" 2>/dev/null
}

CASE_DETAIL=""

# bucket_of <json> <tool> — "auto:<install_cmd>", "manual:<instructions>", or "absent"
bucket_of() {
  printf '%s' "$1" | jq -r --arg n "$2" '
    ([.auto_install[]? | select(.name == $n) | "auto:" + .install_cmd]
     + [.manual_install[]? | select(.name == $n) | "manual:" + .instructions]) | first // "absent"'
}

# ════════════════════════════════════════════════════════════════════════════
# R — row 1, the resolver
# ════════════════════════════════════════════════════════════════════════════
case_R1() {   # macOS without brew: gitleaks' URL is an instruction, not a command
  local mx out got; mx="$(newtmp)"; absent_matrix "$1" "$mx" gitleaks-only || { CASE_DETAIL="matrix"; return 1; }
  out="$(resolve "$1" darwin-none "$mx" web typescript)"; got="$(bucket_of "$out" gitleaks)"
  CASE_DETAIL="gitleaks -> $got"
  [ "$got" = "manual:$GL_URL" ]
}

case_R2() {   # Linux without apt/dnf/pacman: the same
  local mx out got; mx="$(newtmp)"; absent_matrix "$1" "$mx" gitleaks-only || { CASE_DETAIL="matrix"; return 1; }
  out="$(resolve "$1" linux-none "$mx" web typescript)"; got="$(bucket_of "$out" gitleaks)"
  CASE_DETAIL="gitleaks -> $got"
  [ "$got" = "manual:$GL_URL" ]
}

case_R3() {   # with a package manager the recipes are unchanged: brew on macOS, the installer on apt and dnf
  local mx d a f; mx="$(newtmp)"; absent_matrix "$1" "$mx" gitleaks-only || { CASE_DETAIL="matrix"; return 1; }
  d="$(bucket_of "$(resolve "$1" darwin-brew-npm "$mx" web typescript)" gitleaks)"
  a="$(bucket_of "$(resolve "$1" linux-apt-npm "$mx" web typescript)" gitleaks)"
  f="$(bucket_of "$(resolve "$1" linux-dnf "$mx" web typescript)" gitleaks)"
  CASE_DETAIL="darwin+brew -> $d | linux+apt -> $a | linux+dnf -> $f"
  [ "$d" = "auto:$GL_BREW" ] && [ "$a" = "auto:$GL_LINUX" ] && [ "$f" = "auto:$GL_LINUX" ]
}

# R4 — the whole matrix: 3 platform files x 5 host profiles, every tool in each
# (the sweep matrix). For every row of the output: an auto_install tool has a
# recipe under one of the profile's keys; an auto_installable tool in
# manual_install has none, and its instructions are its `manual` value.
# `rerouted` (auto_installable tools filed as manual) must include gitleaks on
# the bare Linux host, or the case proved nothing. The 15 resolver runs go in
# parallel: each polls its 30-odd `false` probes at 0.1s, about 5s apiece.
R4_CHECK='
  ($c[0].tools + $p[0].tools) as $T
  | def tool($n): [$T[] | select(.name == $n)] | first;
    def recipe($t): [$K[] as $k | (($t.install // {})[$k]) | select(. != null and . != "" and . != [])] | length > 0;
  { unknown:  [($out.auto_install + $out.manual_install)[] | .name as $n | select(tool($n) == null) | $n],
    bad_auto: [$out.auto_install[] | .name as $n | tool($n) as $t | select($t != null) | select(recipe($t) | not) | "\($n)=\(.install_cmd)"],
    bad_manual: [$out.manual_install[] | .name as $n | tool($n) as $t | select($t != null and $t.auto_installable == true)
                 | select(recipe($t) or (.instructions != ($t.install.manual // "See documentation"))) | $n],
    rerouted: [$out.manual_install[] | .name as $n | tool($n) | select(. != null and .auto_installable == true) | .name] }'
case_R4() {
  local mx d plat prof out res n=0 bad="" nrows=0 nrerouted=0 gl_linux_none=0
  mx="$(newtmp)"; d="$(newtmp)"; absent_matrix "$1" "$mx" sweep || { CASE_DETAIL="matrix"; return 1; }
  for plat in web desktop mobile; do
    for prof in $PROFILES; do
      resolve "$1" "$prof" "$mx" "$plat" typescript > "$d/$plat.$prof.json" &
    done
  done
  wait
  for plat in web desktop mobile; do
    for prof in $PROFILES; do
      out="$(cat "$d/$plat.$prof.json")"
      [ -n "$out" ] || { CASE_DETAIL="resolver produced nothing for $plat/$prof"; return 1; }
      res="$(jq -cn --slurpfile c "$mx/common.json" --slurpfile p "$mx/$plat.json" \
               --argjson out "$out" --argjson K "$(prof_keys "$prof")" "$R4_CHECK")" \
        || { CASE_DETAIL="check failed for $plat/$prof"; return 1; }
      n="$(printf '%s' "$out" | jq '(.auto_install + .manual_install) | length')"; nrows=$((nrows + n))
      n="$(printf '%s' "$res" | jq '.rerouted | length')"; nrerouted=$((nrerouted + n))
      if [ "$(printf '%s' "$res" | jq '(.unknown + .bad_auto + .bad_manual) | length')" != "0" ]; then
        bad="$bad [$plat/$prof $(printf '%s' "$res" | jq -c '{unknown, bad_auto, bad_manual}')]"
      fi
      if [ "$prof" = "linux-none" ] && printf '%s' "$res" | jq -e '.rerouted | index("gitleaks")' >/dev/null; then
        gl_linux_none=$((gl_linux_none + 1))
      fi
    done
  done
  CASE_DETAIL="rows=$nrows rerouted=$nrerouted gitleaks-rerouted-on-linux-none=$gl_linux_none/3 violations:${bad:- none}"
  [ -z "$bad" ] && [ "$nrows" -gt 0 ] && [ "$gl_linux_none" -eq 3 ]
}

# ════════════════════════════════════════════════════════════════════════════
# I / K-init — init.sh's REAL resolve_and_install_tools, extracted from <root>,
# run against a fixture framework holding <root>'s REAL resolver and the
# gitleaks-only absent matrix.
# ════════════════════════════════════════════════════════════════════════════
# init_fw <root> <dir> [matrix-mode]
init_fw() {
  mkdir -p "$2/scripts/lib" "$2/templates" || return 1
  cp "$1/scripts/resolve-tools.sh" "$2/scripts/" && cp "$1/scripts/lib/helpers-core.sh" "$2/scripts/lib/" || return 1
  absent_matrix "$1" "$2/templates/tool-matrix" "${3:-gitleaks-only}"
}

# run_init <root> <fw> <profile> <OS_TYPE> <AUTO_INSTALL_TOOLS> — prints init's output
run_init() {
  local root="$1" fw="$2" prof="$3" os="$4" yn="$5" cwd
  cwd="$(newtmp)"
  awk '/^resolve_and_install_tools\(\) \{/{f=1} f{print} f && /^\}$/{exit}' "$root/init.sh" > "$cwd/fn.sh"
  [ -s "$cwd/fn.sh" ] || { echo "NO-FUNCTION"; return 0; }
  ( cd "$cwd" && env -i HOME="$TOPTMP" PATH="$TOPTMP/pm/$prof:$ISO" _FN="$cwd/fn.sh" _FW="$fw" \
      _HC="$root/scripts/lib/helpers-core.sh" _OS="$os" _YN="$yn" bash -c '
      set +e
      source "$_HC"
      print_step() { echo "[STEP] $*"; }; print_info() { echo "[INFO] $*"; }; print_ok() { echo "[OK] $*"; }
      print_warn() { echo "[WARN] $*"; }; print_fail() { echo "[FAIL] $*"; }
      BOLD=; NC=; GREEN=; CYAN=; BLUE=; YELLOW=; RED=
      SCRIPT_DIR="$_FW"; OS_TYPE="$_OS"; PLATFORM=web; LANGUAGE=typescript; TRACK=standard
      NON_INTERACTIVE=true; AUTO_INSTALL_TOOLS="$_YN"
      is_qdrant_mcp_registered() { return 1; }; is_qdrant_container_running() { return 1; }
      source "$_FN"; resolve_and_install_tools' 2>&1 )
}

case_I1() {   # init on Linux without a package manager: the URL is listed as manual setup and never run
  local fw out; fw="$(newtmp)/fw"; init_fw "$1" "$fw" || { CASE_DETAIL="fixture"; return 1; }
  out="$(run_init "$1" "$fw" linux-none Linux Y)"
  CASE_DETAIL="out=$(printf '%s' "$out" | tr '\n' '~' | cut -c1-600)"
  printf '%s\n' "$out" | command grep -qxF "│    gitleaks — $GL_URL" \
    && ! printf '%s' "$out" | command grep -qF 'Installing gitleaks' \
    && ! printf '%s' "$out" | command grep -qF 'Could not install gitleaks'
}

case_K5() {   # init's plan on Linux names sudo beside gitleaks, before the question; declining runs nothing
  local fw out log; fw="$(newtmp)/fw"; init_fw "$1" "$fw" || { CASE_DETAIL="fixture"; return 1; }
  out="$(run_init "$1" "$fw" linux-apt-npm Linux N)"
  CASE_DETAIL="out=$(printf '%s' "$out" | tr '\n' '~' | cut -c1-600)"
  printf '%s\n' "$out" | command grep -qxF "│    gitleaks (Secret Detection) — $SUDO_NOTE" \
    && ! printf '%s' "$out" | command grep -qF 'Installing gitleaks'
}

case_K6() {   # init's plan on macOS with brew: no sudo sentence (brew does not elevate)
  local fw out; fw="$(newtmp)/fw"; init_fw "$1" "$fw" || { CASE_DETAIL="fixture"; return 1; }
  out="$(run_init "$1" "$fw" darwin-brew-npm Darwin N)"
  CASE_DETAIL="out=$(printf '%s' "$out" | tr '\n' '~' | cut -c1-600)"
  printf '%s\n' "$out" | command grep -qxF "│    gitleaks (Secret Detection)" \
    && ! printf '%s' "$out" | command grep -qF 'sudo'
}

case_K8() {   # init's plan on Linux: Docker's `sudo apt install …` says sudo too, beside gitleaks' own sentence
  local fw out; fw="$(newtmp)/fw"; init_fw "$1" "$fw" gitleaks-docker || { CASE_DETAIL="fixture"; return 1; }
  out="$(run_init "$1" "$fw" linux-apt-npm Linux N)"
  CASE_DETAIL="out=$(printf '%s' "$out" | tr '\n' '~' | cut -c1-600)"
  printf '%s\n' "$out" | command grep -qxF "│    Docker (containerization) — $SUDO_WORD" \
    && printf '%s\n' "$out" | command grep -qxF "│    gitleaks (Secret Detection) — $SUDO_NOTE"
}

# ════════════════════════════════════════════════════════════════════════════
# K — the elevation sentence itself, and adoption's consent
# ════════════════════════════════════════════════════════════════════════════
note_of() {   # note_of <root> <cmd> — what soif_install_elevation_note prints, or NO-FUNCTION
  _HC="$1/scripts/lib/helpers-core.sh" _C="$2" bash -c '
    source "$_HC" >/dev/null 2>&1
    command -v soif_install_elevation_note >/dev/null 2>&1 || { echo NO-FUNCTION; exit 0; }
    soif_install_elevation_note "$_C"' 2>&1
}

case_K1() {   # the sentence for each of the matrix's Linux gitleaks values; nothing for brew
  local k v got bad=""
  for k in linux_apt linux_dnf linux_pacman; do
    v="$(jq -r --arg k "$k" '.tools[] | select(.name == "gitleaks") | .install[$k]' "$1/templates/tool-matrix/common.json")"
    got="$(note_of "$1" "$v")"
    [ "$got" = "$SUDO_NOTE" ] || bad="$bad $k=[$v]->[$got]"
  done
  got="$(note_of "$1" "$GL_BREW")"
  [ -z "$got" ] || bad="$bad brew->[$got]"
  CASE_DETAIL="mismatches:${bad:- none}"
  [ -z "$bad" ]
}

case_K2() {   # the sentence says what the installer does: sudo, and its own INSTALL_DIR
  local f="$1/scripts/install-gitleaks.sh" dir
  dir="$(sed -n 's/^INSTALL_DIR="\([^"]*\)".*/\1/p' "$f")"
  CASE_DETAIL="installer INSTALL_DIR=[$dir] sudo-install-lines=$(command grep -c '^sudo install .*"\$INSTALL_DIR/gitleaks"' "$f")"
  [ -n "$dir" ] && [ "$SUDO_NOTE" = "this will run sudo to install gitleaks into $dir" ] \
    && [ "$(command grep -c '^sudo install .*"\$INSTALL_DIR/gitleaks"' "$f")" = "1" ]
}

# K7 — every install value in the real matrix (an array joined with " && ", as
# the resolver joins it; `manual` left out, it is not an install key) through
# the helper in ONE shell. The oracle is jq's, not the helper's pattern: a value
# runs sudo when `sudo` stands as a word followed by whitespace. "pseudo-sudo"
# shapes are not sudo, so a helper that matched the bare substring would lie.
case_K7() {
  local vals out bad n_sudo n_plain
  vals="$(newtmp)/vals"
  jq -rs '[.[].tools[] | (.install // {}) | to_entries[] | select(.key != "manual") | .value
           | if type == "array" then join(" && ") else . end] | unique | .[]' \
    "$1"/templates/tool-matrix/*.json > "$vals" || { CASE_DETAIL="jq"; return 1; }
  printf '%s\n' 'pseudo-sudo-tool --install' 'npm install -g pseudo' >> "$vals"
  out="$(_HC="$1/scripts/lib/helpers-core.sh" _V="$vals" bash -c '
    source "$_HC" >/dev/null 2>&1
    command -v soif_install_elevation_note >/dev/null 2>&1 || { echo NO-FUNCTION; exit 0; }
    while IFS= read -r v; do printf "%s\t%s\n" "$v" "$(soif_install_elevation_note "$v")"; done < "$_V"' 2>&1)"
  bad="$(printf '%s\n' "$out" | jq -rR --arg g "$SUDO_NOTE" --arg s "$SUDO_WORD" '
    split("\t") as [$v, $n]
    | (if ($v | test("install-gitleaks\\.sh")) then $g
       elif ($v | test("(^|[^A-Za-z0-9_./-])sudo\\s")) then $s else "" end) as $want
    | select(($n // "") != $want) | "[\($v)] -> [\($n // "")] want [\($want)]"')"
  n_sudo="$(printf '%s\n' "$out" | command grep -c "	$SUDO_WORD\$")"
  n_plain="$(printf '%s\n' "$out" | command grep -c '	$')"
  CASE_DETAIL="values=$(printf '%s\n' "$out" | command grep -c .) sudo=$n_sudo plain=$n_plain mismatches: $(printf '%s' "${bad:-none}" | tr '\n' ' ' | cut -c1-500)"
  [ -z "$bad" ] && [ "$n_sudo" -gt 0 ] && [ "$n_plain" -gt 0 ]
}

# Adoption fixtures (as tests/test-bl316-installers.sh builds them).
ADOPT_REPORT=""
mk_adoptee() {
  local p="$1"
  mkdir -p "$p/src" "$p/docs" || return 1
  ( cd "$p" && git init -q . && git config user.email "bl310@test.invalid" \
      && git config user.name "BL310 Test" && git config core.excludesFile /dev/null ) >/dev/null 2>&1 || return 1
  printf '{"name":"acme-api","scripts":{"test":"npm test"}}\n' > "$p/package.json"
  printf '# acme-api\n' > "$p/README.md"
  printf '# What this is for\n\nInvoice reconciliation for small firms.\n' > "$p/docs/product.md"
  printf '# Architecture\n\nA node service and a postgres database.\n' > "$p/docs/architecture.md"
  ( cd "$p" && git add package.json README.md docs/product.md docs/architecture.md \
      && git commit -q -m "chore: their own history" ) >/dev/null 2>&1 || return 1
}
adopt_report() {
  [ -n "$ADOPT_REPORT" ] && return 0
  local t; t="$(newtmp)"
  mk_adoptee "$t/tpl" || return 1
  bash "$REPO_ROOT/scripts/scout.sh" --root "$t/tpl" --out "$t/scan" >/dev/null 2>&1 || return 1
  [ -s "$t/scan/scout-report.json" ] || return 1
  ADOPT_REPORT="$t/scan/scout-report.json"
}

# run_adopt_decline <root> <profile> — adoption with a resolver stub carrying the
# REAL resolver's gitleaks-only output for <profile>, operator answers "skip it".
# Sets AD_OUT (stdout+stderr), AD_LOG (every stub call), AD_PAYLOAD.
run_adopt_decline() {
  local root="$1" prof="$2" t mx
  adopt_report || { AD_OUT="no scout report"; return 1; }
  t="$(newtmp)"; mx="$t/mx"
  absent_matrix "$root" "$mx" gitleaks-only || { AD_OUT="matrix"; return 1; }
  AD_PAYLOAD="$(resolve "$root" "$prof" "$mx" web typescript)"
  [ -n "$AD_PAYLOAD" ] || { AD_OUT="resolver produced nothing"; return 1; }
  { printf '#!/usr/bin/env bash\ncat <<'"'"'RESOLVERJSON'"'"'\n'; printf '%s\n' "$AD_PAYLOAD"; printf 'RESOLVERJSON\n'; } > "$t/resolver"
  chmod +x "$t/resolver"
  mkdir -p "$t/stubs"; for s in curl sudo brew apt; do mk_stub "$t/stubs" "$s"; done
  AD_LOG="$t/log"; : > "$AD_LOG"
  mk_adoptee "$t/p" || { AD_OUT="adoptee"; return 1; }
  printf '1\nstandard\n2\n1\n1\n1\n1\n' > "$t/answers"   # tier 1, track, SKIP IT, four confirmations
  AD_OUT="$( cd "$t/p" && env -u SOLO_SCRIPTS_DIR SOIF_ADOPT_RESOLVER="$t/resolver" STUB_LOG="$AD_LOG" \
      PATH="$t/stubs:/usr/bin:/bin" bash "$root/scripts/adopt-project.sh" --scan-report "$ADOPT_REPORT" < "$t/answers" 2>&1 )"
  return 0
}

case_K3() {   # adoption on Linux: the sudo sentence follows the command and precedes the question; declining runs nothing
  local a q s
  run_adopt_decline "$1" linux-apt-npm || { CASE_DETAIL="$AD_OUT"; return 1; }
  a="$(printf '%s\n' "$AD_OUT" | command grep -nF 'This would run, exactly as written' | head -1 | cut -d: -f1)"
  s="$(printf '%s\n' "$AD_OUT" | command grep -nF "Administrator rights: $SUDO_NOTE." | head -1 | cut -d: -f1)"
  q="$(printf '%s\n' "$AD_OUT" | command grep -nF 'Set gitleaks up now?' | head -1 | cut -d: -f1)"
  CASE_DETAIL="payload=$(bucket_of "$AD_PAYLOAD" gitleaks) offered@${a:-none} sudo@${s:-none} question@${q:-none} calls=[$(tr '\n' ';' < "$AD_LOG")]"
  [ -n "$a" ] && [ -n "$s" ] && [ -n "$q" ] && [ "$a" -lt "$s" ] && [ "$s" -lt "$q" ] \
    && printf '%s\n' "$AD_OUT" | command grep -qF "  $GL_LINUX" \
    && [ ! -s "$AD_LOG" ]
}

case_K4() {   # adoption on macOS with brew: the command is offered with no sudo sentence
  run_adopt_decline "$1" darwin-brew-npm || { CASE_DETAIL="$AD_OUT"; return 1; }
  CASE_DETAIL="payload=$(bucket_of "$AD_PAYLOAD" gitleaks) offered=$(printf '%s\n' "$AD_OUT" | command grep -cF 'This would run, exactly as written') sudo-lines=$(printf '%s\n' "$AD_OUT" | command grep -cF 'sudo')"
  printf '%s\n' "$AD_OUT" | command grep -qF 'This would run, exactly as written' \
    && printf '%s\n' "$AD_OUT" | command grep -qF "  $GL_BREW" \
    && ! printf '%s\n' "$AD_OUT" | command grep -qF 'sudo'
}

# ════════════════════════════════════════════════════════════════════════════
# C — check-versions.sh on a host without brew. Its interactive branch needs a
# terminal (`[ -t 0 ]`), so the run goes through script(1); the BSD and
# util-linux spellings differ, and the probe picks one (as
# tests/test-bl320-approval-schema2.sh does). curl is a stub that answers every
# URL with a release tagged v99.0.0, so the network check passes and the latest
# version is known without a network.
# ════════════════════════════════════════════════════════════════════════════
CV_ISO="$TOPTMP/cv-iso"; CV_STUBS="$TOPTMP/cv-stubs"; mkdir -p "$CV_ISO" "$CV_STUBS"
for t in bash jq tr sed tail seq rm mktemp grep cut sort head dirname awk date sleep cat env git uname wc ls touch mkdir basename; do
  p="$(command -v "$t" 2>/dev/null)" && ln -s "$p" "$CV_ISO/$t"
done
printf '#!/bin/sh\necho "{\\"tag_name\\":\\"v99.0.0\\"}"\nexit 0\n' > "$CV_STUBS/curl"; chmod +x "$CV_STUBS/curl"

# cv_fixture <root> <dir> <gl-below|gl-behind|canary> — a project dir holding
# <root>'s check-versions.sh and helpers-core.sh and a one-tool matrix. The
# gitleaks rows are the REAL entry with only its probes replaced; the canary
# row's only install value is a `manual` that leaves a file if anything runs it.
cv_fixture() {
  local root="$1" d="$2" kind="$3"
  mkdir -p "$d/proj/templates/tool-matrix" "$d/proj/scripts/lib" "$d/home" || return 1
  cp "$root/scripts/check-versions.sh" "$d/proj/scripts/" && cp "$root/scripts/lib/helpers-core.sh" "$d/proj/scripts/lib/" || return 1
  case "$kind" in
    gl-below|gl-behind)
      jq --arg v "$([ "$kind" = gl-below ] && echo 8.0.0 || echo 8.30.1)" \
        '{tools: [.tools[] | select(.name == "gitleaks") | .check_command = "true" | .version_command = ("echo " + $v)]}' \
        "$root/templates/tool-matrix/common.json" > "$d/proj/templates/tool-matrix/common.json" || return 1 ;;
    canary)
      jq -n --arg c "touch '$d/CANARY'" '{tools: [{name: "BL310Canary", category: "tooling", required: true,
        min_version: "99.0.0", description: "bl310 fixture", check_command: "true", version_command: "echo 0.0.1",
        tracks: ["light","standard","full"], languages: ["all"], platforms: ["all"], dev_os: ["darwin","linux"],
        install: {manual: $c}}]}' > "$d/proj/templates/tool-matrix/common.json" || return 1 ;;
  esac
  printf '#!/bin/bash\ncd "%s/proj" || exit 1\nexec env -i HOME="%s/home" PATH="%s:%s" TERM=dumb bash scripts/check-versions.sh\n' \
    "$d" "$d" "$CV_STUBS" "$CV_ISO" > "$d/run.sh"
}

# cv_run <dir> <answers|-> — "-" runs with no terminal; otherwise over a pty,
# feeding <answers>. Sets CV_OUT (carriage returns removed).
cv_run() {
  local d="$1"
  if [ "$2" = "-" ]; then
    CV_OUT="$(bash "$d/run.sh" </dev/null 2>&1)"
    return 0
  fi
  printf '%b' "$2" > "$d/answers"
  if script -q /dev/null true </dev/null >/dev/null 2>&1; then
    CV_OUT="$( { cat "$d/answers"; sleep 2; } | script -q /dev/null bash "$d/run.sh" 2>&1 | tr -d '\r')"
  else
    CV_OUT="$( { cat "$d/answers"; sleep 2; } | script -q -c "bash '$d/run.sh'" /dev/null 2>&1 | tr -d '\r')"
  fi
}
have_pty() { command -v script >/dev/null 2>&1; }

case_C1() {   # "update all" on a brew-less host: gitleaks' URL is shown as a reference and never run
  local d; d="$(newtmp)"; have_pty || { CASE_DETAIL="no script(1) on PATH — cannot drive the interactive branch"; return 1; }
  cv_fixture "$1" "$d" gl-below || { CASE_DETAIL="fixture"; return 1; }
  cv_run "$d" 'a\n'
  CASE_DETAIL="out=$(printf '%s' "$CV_OUT" | tr '\n' '~' | cut -c1-700)"
  printf '%s' "$CV_OUT" | command grep -qF 'Choice [a/b/c]' \
    && printf '%s' "$CV_OUT" | command grep -qF "gitleaks: no auto-update command available — see $GL_URL" \
    && ! printf '%s' "$CV_OUT" | command grep -qF 'Updating gitleaks' \
    && ! printf '%s' "$CV_OUT" | command grep -qF 'Could not update gitleaks'
}

case_C2() {   # "update all": a `manual` value that IS runnable is still never run
  local d; d="$(newtmp)"; have_pty || { CASE_DETAIL="no script(1) on PATH"; return 1; }
  cv_fixture "$1" "$d" canary || { CASE_DETAIL="fixture"; return 1; }
  cv_run "$d" 'a\n'
  CASE_DETAIL="canary=$([ -e "$d/CANARY" ] && echo CREATED || echo absent) out=$(printf '%s' "$CV_OUT" | tr '\n' '~' | cut -c1-500)"
  printf '%s' "$CV_OUT" | command grep -qF 'Choice [a/b/c]' && [ ! -e "$d/CANARY" ] \
    && printf '%s' "$CV_OUT" | command grep -qF "BL310Canary: no auto-update command available — touch '$d/CANARY'"
}

case_C3() {   # "select" (b, then 1): the same — the reference is shown, nothing runs
  local d; d="$(newtmp)"; have_pty || { CASE_DETAIL="no script(1) on PATH"; return 1; }
  cv_fixture "$1" "$d" gl-below || { CASE_DETAIL="fixture"; return 1; }
  cv_run "$d" 'b\n1\n'
  CASE_DETAIL="out=$(printf '%s' "$CV_OUT" | tr '\n' '~' | cut -c1-700)"
  printf '%s' "$CV_OUT" | command grep -qF "gitleaks: no auto-update command available — see $GL_URL" \
    && ! printf '%s' "$CV_OUT" | command grep -qF 'Updating gitleaks'
}

case_C4() {   # no terminal, below minimum: "Update commands (run manually)" still names the reference
  local d; d="$(newtmp)"
  cv_fixture "$1" "$d" gl-below || { CASE_DETAIL="fixture"; return 1; }
  cv_run "$d" -
  CASE_DETAIL="out=$(printf '%s' "$CV_OUT" | tr '\n' '~' | cut -c1-600)"
  printf '%s' "$CV_OUT" | command grep -qF 'Update commands (run manually):' \
    && printf '%s\n' "$CV_OUT" | command grep -qxF "  gitleaks: see $GL_URL"
}

case_C5() {   # "skip" (c), behind the latest release: the manual list names the reference
  local d; d="$(newtmp)"; have_pty || { CASE_DETAIL="no script(1) on PATH"; return 1; }
  cv_fixture "$1" "$d" gl-behind || { CASE_DETAIL="fixture"; return 1; }
  cv_run "$d" 'c\n'
  CASE_DETAIL="out=$(printf '%s' "$CV_OUT" | tr '\n' '~' | cut -c1-700)"
  printf '%s' "$CV_OUT" | command grep -qF '99.0.0 available' \
    && printf '%s' "$CV_OUT" | command grep -qF 'Manual update commands:' \
    && printf '%s\n' "$CV_OUT" | command grep -qxF "  gitleaks: see $GL_URL"
}

check() {   # check <label> <case-fn> — run against the tree under test
  if "$2" "$REPO_ROOT"; then pass "$1"; else fail_ "$1" "$CASE_DETAIL"; fi
}

echo "=== R — row 1: a manual value is an instruction, never a command ==="
check "R1 — macOS without brew: gitleaks is manual_install with its releases URL" case_R1
check "R2 — Linux without apt/dnf/pacman: the same" case_R2
check "R3 — with a package manager nothing changes: brew install gitleaks / the vetted installer on apt and dnf" case_R3
check "R4 — whole matrix, 3 platform files x 5 hosts: auto_install is exactly the tools with a recipe for the host" case_R4

echo "=== I — row 1 through init.sh ==="
check "I1 — init on a Linux host with no package manager lists the URL as manual setup and never runs it" case_I1

echo "=== K — row 2: the consent names the elevation ==="
check "K1 — soif_install_elevation_note: the sudo sentence for every Linux gitleaks value, nothing for brew" case_K1
check "K2 — the sentence matches the installer: sudo install into its own INSTALL_DIR" case_K2
check "K3 — adoption, Linux: command, then the sudo sentence, then the question; declined, nothing ran" case_K3
check "K4 — adoption, macOS + brew: the command is offered with no sudo sentence" case_K4
check "K5 — init's plan, Linux: gitleaks carries the sudo sentence; declined, nothing ran" case_K5
check "K6 — init's plan, macOS + brew: gitleaks carries no sudo sentence" case_K6
check "K7 — every matrix install value: sudo named exactly where sudo runs (and not for 'pseudo-sudo')" case_K7
check "K8 — init's plan, Linux: Docker's sudo recipe says 'this will run sudo' beside gitleaks' sentence" case_K8

echo "=== C — check-versions.sh never runs a manual value (row 1's rule, its other reader) ==="
check "C1 — update all, no brew: gitleaks' URL is shown as a reference, never run" case_C1
check "C2 — update all, no brew: a runnable manual value is never run either (canary)" case_C2
check "C3 — select 1, no brew: the reference is shown, nothing runs" case_C3
check "C4 — no terminal, below minimum: 'Update commands (run manually)' still names the URL" case_C4
check "C5 — skip, behind the latest release: 'Manual update commands' still names the URL" case_C5

# ════════════════════════════════════════════════════════════════════════════
# M — MUTANTS. Each rewrites ONE marked line in a mirror, asserts the edit
# landed by its literal text and still parses, and requires a named case to go
# RED against that mirror.
# ════════════════════════════════════════════════════════════════════════════
echo "=== M — every BL-310 marker is load-bearing ==="

mk_mirror() {
  mkdir -p "$2" && cp -Rp "$1/scripts" "$1/templates" "$1/init.sh" "$2/"
}

# mutate <file> <marker> <replacement-line> — 0 iff exactly one line ended in
# <marker>, it now reads <replacement-line> exactly, and the file parses.
mutate() {
  local f="$1" mark="$2" repl="$3" n
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

mutant() {   # mutant <id> <rel-file> <marker> <replacement> <killer-case> <what>
  local id="$1" rel="$2" mark="$3" repl="$4" killer="$5" what="$6" m why
  m="$(newtmp)/mirror"
  mk_mirror "$REPO_ROOT" "$m" || { fail_ "$id" "could not build a mirror"; return; }
  why="$(mutate "$m/$rel" "$mark" "$repl")" || { fail_ "$id" "mutant did not land: $why"; return; }
  if "$killer" "$m"; then
    fail_ "$id" "$what — SURVIVED: ${killer#case_} still passes against the mutant ($CASE_DETAIL)"
  else
    pass "$id (MUTATION) — $what: killed by ${killer#case_}"
  fi
}

mutant MR1 scripts/resolve-tools.sh '# BL-310-MANUAL-NOT-A-KEY' '_keys="${_keys}manual"' case_R2 \
  "\`manual\` is an install key again, so the gitleaks URL is filed under auto_install"
mutant MR2 scripts/resolve-tools.sh '# BL-310-MANUAL-NOT-A-KEY' '_keys="${_keys}manual"' case_I1 \
  "the same mutant, seen from init.sh: the URL is handed to eval"
mutant MK1 scripts/lib/helpers-core.sh '# BL-310-ELEVATION-NOTE' '    __bl310_mutant_never_matches__) ;;' case_K1 \
  "the helper no longer recognises the installer"
mutant MK2 scripts/lib/helpers-core.sh '# BL-310-ELEVATION-NOTE' "    *) printf '%s\\n' \"$SUDO_NOTE\" ;;" case_K4 \
  "the helper says sudo for every command, brew included"
mutant MA1 scripts/lib/adopt/adopt-tools.sh '# BL-310-ADOPT-ELEVATION' ':' case_K3 \
  "adoption's consent drops the sudo sentence"
mutant MI1 init.sh '# BL-310-INIT-ELEVATION' '      echo -e "${BOLD}│${NC}$line"' case_K5 \
  "init's plan drops the sudo sentence"
mutant MK3 scripts/lib/helpers-core.sh '# BL-310-ELEVATION-SUDO' '    __bl310_mutant_never_matches__) ;;' case_K8 \
  "a recipe that runs sudo is no longer named as one"
mutant MK4 scripts/lib/helpers-core.sh '# BL-310-ELEVATION-SUDO' "    *sudo*) printf '%s\\n' \"$SUDO_WORD\" ;;" case_K7 \
  "any value containing the letters 'sudo' is named as running sudo"

CV=scripts/check-versions.sh
mutant MC1 "$CV" '# BL-310-CV-NO-MANUAL' \
  "  [ -n \"\$c\" ] || c=\$(printf '%s' \"\$1\" | jq -r \"(.install.npm // .install.linux_pip // .install.manual // empty) | \$_cv_jq_install_cmd\")" \
  case_C2 "the manual value is an update command again, so 'update all' evals it"
mutant MC2 "$CV" '# BL-310-CV-REF-A' '          print_warn "$tool_name: no auto-update command available"' case_C1 \
  "'update all' drops the reference"
mutant MC3 "$CV" '# BL-310-CV-REF-B' '            :' case_C3 \
  "'select' says nothing for a row with no command"
mutant MC4 "$CV" '# BL-310-CV-SHOW' '  _cv_render_update_cmd "${UPDATE_CMDS[$1]:-}"' case_C4 \
  "the printers lose the reference"
mutant MC5 "$CV" '# BL-310-CV-SHOW-N' '    echo "  ${UPDATE_NAMES[$idx]}: $(_cv_render_update_cmd "${UPDATE_CMDS[$idx]}")"' case_C4 \
  "the no-terminal printer renders the command only"
mutant MC6 "$CV" '# BL-310-CV-SHOW-C' '          echo "  ${UPDATE_NAMES[$idx]}: $(_cv_render_update_cmd "${UPDATE_CMDS[$idx]}")"' case_C5 \
  "the 'skip' printer renders the command only"
mutant MC7 "$CV" '# BL-310-CV-REF-MIN' ':' case_C4 \
  "a below-minimum row records no reference"
mutant MC8 "$CV" '# BL-310-CV-REF-LATEST' ':' case_C5 \
  "a behind-latest row records no reference"

# MD1 rewrites a line with no marker — the installer's INSTALL_DIR — so the
# sentence and the installer can no longer drift apart silently.
md1() {
  local m f old='INSTALL_DIR="/usr/local/bin"' new='INSTALL_DIR="/opt/bl310-mutant/bin"'
  m="$(newtmp)/mirror"; mk_mirror "$REPO_ROOT" "$m" || { fail_ MD1 "could not build a mirror"; return; }
  f="$m/scripts/install-gitleaks.sh"
  [ "$(command grep -cxF -- "$old" "$f")" = "1" ] || { fail_ MD1 "mutant did not land: '$old' is not on exactly one line"; return; }
  OLD="$old" NEW="$new" awk '$0 == ENVIRON["OLD"] { print ENVIRON["NEW"]; next } { print }' "$f" > "$f.mut" && cat "$f.mut" > "$f" && rm -f "$f.mut"
  [ "$(command grep -cxF -- "$new" "$f")" = "1" ] && bash -n "$f" 2>/dev/null || { fail_ MD1 "mutant did not land"; return; }
  if case_K2 "$m"; then
    fail_ MD1 "the installer moves to another directory — SURVIVED: K2 still passes ($CASE_DETAIL)"
  else
    pass "MD1 (MUTATION) — the installer moves to another directory while the consent still says /usr/local/bin: killed by K2"
  fi
}
md1

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
