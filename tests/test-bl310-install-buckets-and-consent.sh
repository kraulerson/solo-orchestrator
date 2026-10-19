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
#      sudo and /usr/local/bin, and brew's does not.
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
# absent_matrix <root> <dest> <gitleaks-only|sweep>
#   sweep also widens `languages` and `platforms` to "all", so one resolver run
#   per platform file sees every tool in it instead of one language's share.
#   Install objects, dev_os, tracks and phases are untouched.
absent_matrix() {
  local root="$1" dest="$2" mode="$3" f
  mkdir -p "$dest" || return 1
  if [ "$mode" = "gitleaks-only" ]; then
    jq '{tools: [.tools[] | select(.name == "gitleaks") | .check_command = "false"]}' \
      "$root/templates/tool-matrix/common.json" > "$dest/common.json" || return 1
    [ "$(jq '.tools | length' "$dest/common.json")" = "1" ] || return 1
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
  local mx d plat prof out res bad="" nrows=0 nrerouted=0 gl_linux_none=0
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
      nrows=$((nrows + $(printf '%s' "$out" | jq '(.auto_install + .manual_install) | length')))
      nrerouted=$((nrerouted + $(printf '%s' "$res" | jq '.rerouted | length')))
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
# init_fw <root> <dir>
init_fw() {
  mkdir -p "$2/scripts/lib" "$2/templates" || return 1
  cp "$1/scripts/resolve-tools.sh" "$2/scripts/" && cp "$1/scripts/lib/helpers-core.sh" "$2/scripts/lib/" || return 1
  absent_matrix "$1" "$2/templates/tool-matrix" gitleaks-only
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
